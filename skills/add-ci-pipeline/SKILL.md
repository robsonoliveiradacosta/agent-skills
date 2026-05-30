---
name: add-ci-pipeline
description: "Generate a production-grade GitHub Actions CI pipeline for a Quarkus project — runs Maven build with cache, unit + integration tests against a real Postgres service container, JVM and native image matrix, container image build with Trivy vulnerability scan, CycloneDX SBOM generation, and an optional release job that pushes to GHCR on tagged commits. Use when the user asks for CI, GitHub Actions, automated testing, \"set up the pipeline\", security scanning of dependencies, or publishing container images."
---

# add-ci-pipeline

Generate `.github/workflows/` files for a CI pipeline that matches what a serious team would run on every PR and tag:

1. **build-and-test** — Maven verify on every PR, with Postgres service container and Maven cache.
2. **native-build** — matrix native build (gated to main / tags to save minutes).
3. **container** — Build JVM container, scan with Trivy, attach CycloneDX SBOM.
4. **release** (tag-triggered) — push image to GHCR with semver tag.

## When to invoke

- "Set up CI"
- "Add GitHub Actions"
- "Automate the build"
- "Scan my dependencies for CVEs"

## Inputs to collect

| Input | Default |
|---|---|
| Default branch | `main` |
| Container registry | `ghcr.io/<owner>/<artifactId>` |
| Run native build matrix on every PR? | **no** (slow & expensive — only on push to main + tags) |
| Postgres version | match `docker-compose.yml` |
| Java version | `21` |
| Fail PR on HIGH or CRITICAL CVE? | yes |

## Files to generate

### `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [{{defaultBranch}}]
    tags:    ['v*.*.*']
  pull_request:
    branches: [{{defaultBranch}}]

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:

  # ────────────────────────────────────────────────────────────────
  build-and-test:
    name: Build & Test (JVM)
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:18.1-alpine3.23
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: {{dbName}}_test
        ports: ['5432:5432']
        options: >-
          --health-cmd "pg_isready -U postgres"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK {{javaVersion}}
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '{{javaVersion}}'
          cache: maven

      - name: Verify (unit + integration)
        run: ./mvnw -B verify -DskipITs=false
        env:
          DB_URL:      jdbc:postgresql://localhost:5432/{{dbName}}_test
          DB_USERNAME: postgres
          DB_PASSWORD: postgres

      - name: Upload test reports
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: surefire-reports
          path: |
            **/target/surefire-reports/**
            **/target/failsafe-reports/**

  # ────────────────────────────────────────────────────────────────
  native-build:
    name: Native build matrix
    if: github.event_name == 'push' || startsWith(github.ref, 'refs/tags/')
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest]   # extend with macos-latest if you ship native macs
    needs: [build-and-test]
    steps:
      - uses: actions/checkout@v4
      - uses: graalvm/setup-graalvm@v1
        with:
          java-version: '{{javaVersion}}'
          distribution: graalvm
          github-token: ${{ secrets.GITHUB_TOKEN }}
      - run: ./mvnw -B package -Dnative -DskipTests

  # ────────────────────────────────────────────────────────────────
  container:
    name: Container build + scan
    runs-on: ubuntu-latest
    needs: [build-and-test]
    permissions:
      contents: read
      packages: write
      security-events: write   # for SARIF upload
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '{{javaVersion}}', cache: maven }

      - name: Package JAR
        run: ./mvnw -B -DskipTests package

      - name: Build container image
        run: docker build -t local/{{artifactId}}:${{ github.sha }} .

      - name: Trivy vulnerability scan
        uses: aquasecurity/trivy-action@0.28.0
        with:
          image-ref: local/{{artifactId}}:${{ github.sha }}
          format: sarif
          output: trivy.sarif
          severity: HIGH,CRITICAL
          exit-code: '1'
          ignore-unfixed: true

      - name: Upload Trivy results
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with: { sarif_file: trivy.sarif }

      - name: Generate CycloneDX SBOM
        run: ./mvnw -B org.cyclonedx:cyclonedx-maven-plugin:2.9.1:makeBom

      - name: Upload SBOM
        uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: target/bom.json

  # ────────────────────────────────────────────────────────────────
  release:
    name: Release to GHCR
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    needs: [container, native-build]
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '{{javaVersion}}', cache: maven }

      - run: ./mvnw -B -DskipTests package

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Derive version
        id: ver
        run: echo "tag=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"

      - name: Build & push
        run: |
          IMAGE={{registry}}
          docker build -t "$IMAGE:${{ steps.ver.outputs.tag }}" -t "$IMAGE:latest" .
          docker push "$IMAGE:${{ steps.ver.outputs.tag }}"
          docker push "$IMAGE:latest"
```

### `.github/workflows/codeql.yml` (optional — static analysis)

Only generate if the user wants it:

```yaml
name: CodeQL

on:
  push:    { branches: [{{defaultBranch}}] }
  pull_request: { branches: [{{defaultBranch}}] }
  schedule:
    - cron: '0 6 * * 1'

jobs:
  analyze:
    runs-on: ubuntu-latest
    permissions: { actions: read, contents: read, security-events: write }
    steps:
      - uses: actions/checkout@v4
      - uses: github/codeql-action/init@v3
        with: { languages: java-kotlin }
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '{{javaVersion}}', cache: maven }
      - run: ./mvnw -B -DskipTests compile
      - uses: github/codeql-action/analyze@v3
```

### `pom.xml` addition (for SBOM)

```xml
<plugin>
    <groupId>org.cyclonedx</groupId>
    <artifactId>cyclonedx-maven-plugin</artifactId>
    <version>2.9.1</version>
    <executions>
        <execution>
            <phase>package</phase>
            <goals><goal>makeBom</goal></goals>
        </execution>
    </executions>
</plugin>
```

> Embedding the plugin in `pom.xml` means SBOM generation works locally too (`./mvnw package` produces `target/bom.json`), not only in CI.

### `.github/dependabot.yml`

```yaml
version: 2
updates:
  - package-ecosystem: maven
    directory: "/"
    schedule: { interval: weekly }
    open-pull-requests-limit: 10
    groups:
      quarkus:
        patterns: ["io.quarkus*"]
      testcontainers:
        patterns: ["org.testcontainers*"]
  - package-ecosystem: docker
    directory: "/"
    schedule: { interval: weekly }
  - package-ecosystem: github-actions
    directory: "/"
    schedule: { interval: weekly }
```

> Grouped Maven updates avoid one PR per Quarkus artifact every week — they all move in lockstep anyway.

## Branch protection — recommend, don't enforce

After files land, tell the user to:
1. Settings → Branches → Add rule for `main`.
2. Require **build-and-test** and **container** as required status checks.
3. Require code review (at least 1).
4. Forbid force-push.

The skill **can't** make these changes — they're org-level. State them explicitly.

## Anti-patterns to refuse

- **Skipping tests in CI** (`-DskipTests`) to speed up the pipeline. CI exists precisely to run them.
- **`actions: write` or `contents: write` on the build job.** Minimal permissions per job.
- **Caching `~/.m2/repository` manually.** `actions/setup-java@v4` with `cache: maven` does it correctly and respects `pom.xml` changes.
- **Hardcoded secrets in YAML.** Always `${{ secrets.NAME }}`. Reject any PR that adds a token in plaintext.
- **`docker login` with the user's PAT** instead of `GITHUB_TOKEN`. The token is scoped and rotated automatically.
- **`exit-code: '0'` on Trivy** to "let things through". If HIGH/CRITICAL are blocking the build, fix or document the exception via `.trivyignore` with a comment per CVE.

## Post-generation

- Run the workflow locally with `act` if the user has it, otherwise the first push will trigger it.
- Tell the user the **first** push will fail until `mvn.repository` is warmed (cache miss). Subsequent runs use cache.
- Suggest enabling GitHub Code Scanning so Trivy SARIF surfaces under Security tab.

---

## Strategic considerations & governance

## Goal

Make every pull request prove that the API still builds, tests, packages, and meets baseline quality expectations.

## Recommended Gates

1. Compile and unit tests: `./mvnw test`.
2. Integration verification: `./mvnw verify` when Testcontainers or external stubs are involved.
3. Docker build or `docker compose config` for runtime changes.
4. OpenAPI or contract check when public endpoints change.
5. Dependency/security scan when project policy supports it.
6. Artifact collection for test reports and logs on failure.

## Pipeline Rules

- Run fast checks before expensive integration or Docker jobs.
- Cache Maven dependencies without caching generated target output as truth.
- Keep secrets in CI secret storage, not repository files.
- Use service containers or Testcontainers consistently.
- Fail the pipeline on test failure, compilation warnings elevated by policy, or invalid Compose config.

## Pull Request Evidence

Ask contributors to include commands run, key test output, migration impact, API changes, and deployment considerations.

## Example

For a PR changing MinIO upload behavior, require targeted upload tests, `./mvnw test`, Compose validation, and evidence that oversized and invalid MIME uploads still fail.
