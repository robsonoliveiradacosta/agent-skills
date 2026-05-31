---
name: add-gitlab-ci
description: "Generate a production-grade GitLab CI/CD pipeline (.gitlab-ci.yml) for a Quarkus project — Maven build with cache, unit + integration tests against a real Postgres service, JUnit report integration, optional native build, container image build pushed to the GitLab Container Registry, Trivy/Container-Scanning for CVEs, CycloneDX SBOM, and a tag-triggered release. Use when the user wants CI on GitLab, a .gitlab-ci.yml, GitLab pipelines, automated testing, 'set up the pipeline' on GitLab, container scanning, or publishing images to the GitLab registry. This is the GitLab counterpart to add-ci-pipeline (which targets GitHub Actions)."
---

# add-gitlab-ci

Generate a `.gitlab-ci.yml` for a Quarkus API that matches what a serious team runs on every merge request and tag — the GitLab counterpart to [`add-ci-pipeline`](../add-ci-pipeline/SKILL.md) (GitHub Actions). Same intent, GitLab idioms: **stages**, `services:`, `cache:`, `rules:`, CI/CD variables, and the built-in **Container Registry** + **security scanning** templates.

Pipeline shape:

1. **build-test** — `./mvnw verify` on every MR, with a Postgres service and a keyed Maven cache; JUnit reports surfaced in the MR.
2. **native** — native image build, gated to the default branch and tags (slow/expensive).
3. **container** — build the JVM image, scan with Trivy, attach a CycloneDX SBOM artifact.
4. **release** — on `v*.*.*` tags, push to the GitLab Container Registry with a semver tag.

## When to invoke

- "Set up CI on GitLab" · "Add a `.gitlab-ci.yml`"
- "Automate the build / tests on GitLab"
- "Push my image to the GitLab registry"
- "Scan dependencies / container for CVEs on GitLab"

## Inputs to collect

| Input | Default |
|---|---|
| Default branch | `main` |
| Container registry | `$CI_REGISTRY_IMAGE` (project's built-in GitLab registry) |
| Run native build on every MR? | **no** — only on default branch + tags |
| Postgres version | match `docker-compose.yml` |
| Java version | `21` |
| Fail pipeline on HIGH/CRITICAL CVE? | yes |
| GitLab tier | Free works; note where Ultimate-only security templates differ |

## Library / framework grounding (context7)

GitLab CI keywords, the `rules:`/`workflow:` semantics, and the bundled security templates (`Jobs/Container-Scanning`, `Jobs/Dependency-Scanning`, `Jobs/SAST`) change across GitLab releases, and predefined variables (`CI_REGISTRY_IMAGE`, `CI_COMMIT_TAG`, `CI_DEFAULT_BRANCH`) get added/renamed. Before writing the file, verify current keyword syntax and template includes via `mcp__context7__query-docs` (e.g. `"gitlab ci rules if changes"`, `"gitlab container scanning template include"`, `"gitlab ci services postgres health"`). A stale `include:` template path silently no-ops the scan.

- **If context7 is not installed** (the `mcp__context7__*` tools aren't present): proceed with training data, but say so once at the end and point the user at `AGENTS.md` §"MCP servers (context7)" for the install one-liner.

## File to generate — `.gitlab-ci.yml`

```yaml
stages: [build-test, native, container, release]

variables:
  MAVEN_OPTS: "-Dmaven.repo.local=$CI_PROJECT_DIR/.m2/repository -Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=WARN"
  MAVEN_CLI_OPTS: "-B -ntp"
  IMAGE: "$CI_REGISTRY_IMAGE"        # built-in per-project registry

# Run the pipeline for MRs, the default branch, and tags — not for every branch push.
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_COMMIT_TAG

# Key the Maven cache by the lockfile-equivalent so it busts when deps change.
.maven-cache: &maven-cache
  key:
    files: [pom.xml]
  paths: [.m2/repository]

# ──────────────────────────────────────────────────────────────
build-test:
  stage: build-test
  image: maven:3.9-eclipse-temurin-21
  cache: *maven-cache
  services:
    - name: postgres:18.1-alpine3.23
      alias: postgres
  variables:
    POSTGRES_USER: postgres
    POSTGRES_PASSWORD: postgres
    POSTGRES_DB: {{dbName}}_test
    DB_URL: jdbc:postgresql://postgres:5432/{{dbName}}_test   # service alias as host
    DB_USERNAME: postgres
    DB_PASSWORD: postgres
  script:
    - ./mvnw $MAVEN_CLI_OPTS verify -DskipITs=false
  artifacts:
    when: always
    reports:
      junit:
        - "**/target/surefire-reports/TEST-*.xml"
        - "**/target/failsafe-reports/TEST-*.xml"
    paths:
      - "**/target/*-reports/**"
    expire_in: 1 week

# ──────────────────────────────────────────────────────────────
native:
  stage: native
  image: ghcr.io/graalvm/graalvm-community:21
  needs: [build-test]
  cache: *maven-cache
  script:
    - ./mvnw $MAVEN_CLI_OPTS package -Dnative -DskipTests
  artifacts:
    paths: ["target/*-runner"]
    expire_in: 1 day
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_COMMIT_TAG

# ──────────────────────────────────────────────────────────────
# Build the JVM image with Kaniko (no privileged Docker daemon needed).
container:
  stage: container
  image:
    name: gcr.io/kaniko-project/executor:debug
    entrypoint: [""]
  needs: [build-test]
  script:
    - mkdir -p /kaniko/.docker
    - echo "{\"auths\":{\"$CI_REGISTRY\":{\"username\":\"$CI_REGISTRY_USER\",\"password\":\"$CI_REGISTRY_PASSWORD\"}}}" > /kaniko/.docker/config.json
    - /kaniko/executor --context "$CI_PROJECT_DIR" --dockerfile "$CI_PROJECT_DIR/Dockerfile"
        --destination "$IMAGE:$CI_COMMIT_SHORT_SHA"
        $( [ "$CI_COMMIT_BRANCH" = "$CI_DEFAULT_BRANCH" ] && echo --destination "$IMAGE:latest" )

# Built-in container scanning (scans the image we just pushed). Ultimate surfaces it
# in the MR security widget; on Free it still runs and produces the report artifact.
container_scanning:
  stage: container
  needs: [container]
  variables:
    CS_IMAGE: "$IMAGE:$CI_COMMIT_SHORT_SHA"
    CS_SEVERITY_THRESHOLD: HIGH

sbom:
  stage: container
  image: maven:3.9-eclipse-temurin-21
  needs: [build-test]
  cache: *maven-cache
  script:
    - ./mvnw $MAVEN_CLI_OPTS org.cyclonedx:cyclonedx-maven-plugin:2.9.1:makeBom
  artifacts:
    reports:
      cyclonedx: ["target/bom.json"]
    paths: ["target/bom.json"]
    expire_in: 1 month

# ──────────────────────────────────────────────────────────────
release:
  stage: release
  image:
    name: gcr.io/kaniko-project/executor:debug
    entrypoint: [""]
  needs: [container, native]
  rules:
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
  script:
    - export VERSION="${CI_COMMIT_TAG#v}"
    - mkdir -p /kaniko/.docker
    - echo "{\"auths\":{\"$CI_REGISTRY\":{\"username\":\"$CI_REGISTRY_USER\",\"password\":\"$CI_REGISTRY_PASSWORD\"}}}" > /kaniko/.docker/config.json
    - /kaniko/executor --context "$CI_PROJECT_DIR" --dockerfile "$CI_PROJECT_DIR/Dockerfile"
        --destination "$IMAGE:$VERSION" --destination "$IMAGE:latest"

# Pull in GitLab's maintained security scanners.
include:
  - template: Jobs/Container-Scanning.gitlab-ci.yml
  - template: Jobs/Dependency-Scanning.gitlab-ci.yml
  - template: Jobs/SAST.gitlab-ci.yml
```

> **Why Kaniko, not `docker build`?** Most shared GitLab runners run jobs in unprivileged containers where there's no Docker daemon. Kaniko builds an OCI image from the Dockerfile entirely in userspace — no `docker:dind`, no `privileged: true`. If your runners *are* privileged, you can swap in the `docker:dind` service instead.

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

> Embedding the plugin means `./mvnw package` produces `target/bom.json` locally too, not only in CI.

### Dependency updates — Renovate (GitLab has no Dependabot)

GitLab doesn't ship Dependabot. Use the GitLab-hosted **Renovate** (`renovate.json`) or GitLab's built-in Dependency Scanning (above). Minimal `renovate.json`:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "packageRules": [
    { "matchPackagePatterns": ["^io.quarkus"], "groupName": "quarkus" },
    { "matchPackagePatterns": ["^org.testcontainers"], "groupName": "testcontainers" }
  ]
}
```

## CI/CD variables to set (Settings → CI/CD → Variables)

| Variable | Notes |
|---|---|
| `CI_REGISTRY`, `CI_REGISTRY_USER`, `CI_REGISTRY_PASSWORD` | **Predefined** — GitLab injects these for the built-in registry. No setup needed. |
| `$CI_JOB_TOKEN` | Predefined; use for registry/API auth instead of a PAT where possible. |
| Any external creds (e.g. external registry, deploy keys) | Add as **masked + protected** variables; never inline in YAML. |

## Protected branches — recommend, don't enforce

After the file lands, tell the user to (Settings → Repository → Protected branches):
1. Protect `main`: allow merge via MR only, no direct push.
2. Settings → Merge requests → require pipelines to succeed and all threads resolved.
3. Require at least one approval (Settings → Merge requests → Approvals).

The skill **can't** make these changes — they're project settings. State them explicitly.

## Anti-patterns to refuse

- **Skipping tests** (`-DskipTests`) on the `build-test` job. CI exists to run them; only `native`/`container` skip tests because `build-test` already gated them.
- **`docker build` on shared runners assuming a daemon.** Use Kaniko (or an explicit privileged `dind` service you control).
- **Hardcoded tokens in `.gitlab-ci.yml`.** Use predefined `$CI_*` vars or masked/protected CI/CD variables.
- **Caching `target/` as truth.** Cache only `.m2/repository`, keyed on `pom.xml`. Pass build outputs between stages via `artifacts`, not `cache`.
- **Running the full pipeline on every branch push.** The `workflow.rules` limit it to MRs, the default branch, and tags — otherwise you double-run (branch + MR) and waste minutes.
- **Letting CVEs through** by dropping the severity threshold. Fix, or document an exception in the scanner's allowlist with a reason per CVE.

## Post-generation

- The **first** pipeline is slow until the `.m2` cache is warm; later runs reuse it.
- Container Scanning's MR security widget is **Ultimate**-only; on Free/Premium the job still runs and the report is downloadable as an artifact.
- JUnit reports appear in the MR's **Tests** tab once `build-test` runs.
- Verify by opening an MR (build-test runs), merging to `main` (native + container run), and pushing a `vX.Y.Z` tag (release runs).

---

## Strategic considerations & governance

## Goal

Make every merge request prove the API still builds, tests, packages, and meets baseline security expectations — with the same rigor as the GitHub pipeline, expressed in GitLab idioms.

## Recommended gates

1. Compile + unit tests on every MR.
2. Integration verification (`./mvnw verify`) against a real Postgres service.
3. Container build + scan for runtime/Dockerfile changes.
4. Dependency + SAST scanning per project policy.
5. SBOM artifact attached to the pipeline.
6. JUnit + report artifacts collected on failure.

## Pipeline rules

- Fast checks (build-test) before expensive native/container stages; use `needs:` for a DAG, not strict stage waits, where it speeds feedback.
- Cache `.m2/repository` keyed on `pom.xml`; pass artifacts between stages explicitly.
- Secrets live in CI/CD variables (masked + protected), never in the repo.
- `workflow.rules` scope runs to MRs, the default branch, and tags.
- Fail the pipeline on test failure or a CVE above the agreed threshold.

## Example

For an MR changing MinIO upload behavior: `build-test` runs targeted upload tests against Postgres, the container stage rebuilds and scans the image, dependency scanning flags any new CVE, and the SBOM is regenerated — the MR can't merge until the pipeline is green and approved.
