---
name: add-openapi-client-gen
description: "Generate typed client SDKs (TypeScript, Java, Kotlin, Python, …) from a Quarkus project's /q/openapi specification, using the openapi-generator Maven plugin or CLI. Adds a clients/ directory layout, a maven module / npm package skeleton per language, a CI job that regenerates clients on every release, and a check that fails when the spec drifts. Use when the user asks for an SDK, \"TypeScript client\", auto-generated API client, or wants frontends to consume the API without hand-writing fetch wrappers."
---

# add-openapi-client-gen

Generate client SDKs from the project's OpenAPI spec (`/q/openapi`) using `openapi-generator-maven-plugin`. The generated clients sit in a `clients/<language>/` directory and are published as part of the release workflow.

This skill assumes:
- `quarkus-smallrye-openapi` is already on the classpath.
- The user wants a **typed** client, not a thin wrapper.

## When to invoke

- "Generate a TypeScript SDK"
- "I want the frontend to import a Java client"
- "Auto-generate API clients"

## Inputs to collect

| Input | Default |
|---|---|
| Target languages | required (one or more of: `typescript-fetch`, `typescript-axios`, `java`, `kotlin`, `python`, `go`) |
| Package / module name | derive from artifactId, e.g. `@acme/catalog-client` (TS) or `com.acme.catalog.client` (Java) |
| Spec source | `target/openapi/openapi.yaml` (Quarkus generates this at build time) |
| Output directory | `clients/<language>/` |
| Publish to npm / Maven Central? | ask — typically no on initial setup |

## Quarkus side — emit spec at build time

```properties
quarkus.smallrye-openapi.store-schema-directory=target/openapi
quarkus.smallrye-openapi.store-schema-file-name=openapi
# Default media type — OpenAPI generator handles both, but consistency helps consumers
mp.openapi.servers=http://localhost:8080
```

Quarkus writes `target/openapi/openapi.yaml` during `./mvnw package`. The generator plugin consumes that file in a later phase.

## `pom.xml` additions — per language

Wrap each language in a Maven profile so the user can `./mvnw -Pclient-ts package` selectively:

### TypeScript (fetch)

```xml
<profile>
    <id>client-ts</id>
    <build>
        <plugins>
            <plugin>
                <groupId>org.openapitools</groupId>
                <artifactId>openapi-generator-maven-plugin</artifactId>
                <version>7.11.0</version>
                <executions>
                    <execution>
                        <id>generate-ts-client</id>
                        <phase>package</phase>
                        <goals><goal>generate</goal></goals>
                        <configuration>
                            <inputSpec>${project.build.directory}/openapi/openapi.yaml</inputSpec>
                            <generatorName>typescript-fetch</generatorName>
                            <output>${project.basedir}/clients/typescript</output>
                            <skipValidateSpec>false</skipValidateSpec>
                            <configOptions>
                                <npmName>{{tsPackage}}</npmName>
                                <npmVersion>${project.version}</npmVersion>
                                <supportsES6>true</supportsES6>
                                <withInterfaces>true</withInterfaces>
                                <typescriptThreePlus>true</typescriptThreePlus>
                            </configOptions>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
</profile>
```

### Java

```xml
<profile>
    <id>client-java</id>
    <build>
        <plugins>
            <plugin>
                <groupId>org.openapitools</groupId>
                <artifactId>openapi-generator-maven-plugin</artifactId>
                <version>7.11.0</version>
                <executions>
                    <execution>
                        <id>generate-java-client</id>
                        <phase>package</phase>
                        <goals><goal>generate</goal></goals>
                        <configuration>
                            <inputSpec>${project.build.directory}/openapi/openapi.yaml</inputSpec>
                            <generatorName>java</generatorName>
                            <output>${project.basedir}/clients/java</output>
                            <library>native</library> <!-- java 11 HttpClient, no extra deps -->
                            <configOptions>
                                <groupId>{{javaGroup}}</groupId>
                                <artifactId>{{javaArtifact}}</artifactId>
                                <artifactVersion>${project.version}</artifactVersion>
                                <invokerPackage>{{javaPkg}}.invoker</invokerPackage>
                                <apiPackage>{{javaPkg}}.api</apiPackage>
                                <modelPackage>{{javaPkg}}.model</modelPackage>
                                <java8>true</java8>
                                <dateLibrary>java8</dateLibrary>
                            </configOptions>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
</profile>
```

> Use `library=native` for the Java generator — it relies only on JDK 11+ `HttpClient` and avoids dragging in `okhttp` / `jersey` transitives.

## Directory layout produced

```
clients/
├── typescript/
│   ├── package.json
│   ├── tsconfig.json
│   ├── apis/
│   ├── models/
│   └── index.ts
└── java/
    ├── pom.xml
    ├── src/main/java/<javaPkg>/
    │   ├── api/
    │   ├── model/
    │   └── invoker/
    └── README.md
```

## `.gitignore`

Decide explicitly with the user:

- **Option A** — commit generated clients. Pros: easy for consumers, no build step. Cons: noisy diffs on every spec change.
- **Option B** — gitignore them, publish via release pipeline. Pros: clean history. Cons: consumers can't fork the client easily.

Default: **Option B** for serious projects.

```
# Generated SDKs — produced by openapi-generator
/clients/*/
!/clients/README.md
```

## Drift check (mandatory)

The hardest failure mode: the spec changes but the SDK isn't regenerated. Add a CI job that **fails the PR** if the committed spec diverges from what the current code produces:

`.github/workflows/openapi-drift.yml`:

```yaml
name: OpenAPI drift check

on:
  pull_request: { branches: [main] }

jobs:
  drift:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '21', cache: maven }

      - name: Regenerate spec
        run: ./mvnw -B -DskipTests package

      - name: Compare committed vs regenerated
        run: |
          diff -q docs/openapi.yaml target/openapi/openapi.yaml \
            || (echo "::error::OpenAPI spec drift — commit the regenerated docs/openapi.yaml" && exit 1)
```

> Convention: commit a stable copy of the spec at `docs/openapi.yaml`. Code reviewers can read OpenAPI diffs there. Hands-on developers regenerate clients from `target/openapi/openapi.yaml`.

## Release workflow integration

If `add-ci-pipeline` already exists, append a `clients` job to `ci.yml` that runs on tagged commits:

```yaml
  clients:
    if: startsWith(github.ref, 'refs/tags/v')
    needs: [build-and-test]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '21', cache: maven }
      - uses: actions/setup-node@v4
        with: { node-version: '22' }
      - run: ./mvnw -B -DskipTests -Pclient-ts -Pclient-java package
      # Publish steps (npm publish, mvn deploy) — generate stubs but leave secrets to the user
```

## Anti-patterns to refuse

- **Hand-editing generated code.** Anything in `clients/<lang>/` is disposable. If a template is wrong, customize the `mustache` templates via `<templateDirectory>` in the plugin config, not the output.
- **Multiple generators producing the same SDK from competing specs.** One source of truth — the live API.
- **Skipping the drift check.** Without it, SDKs silently fall behind and consumers debug ghost bugs.
- **Generating a client for an internal/admin API and shipping it publicly.** Use `@SecurityRequirement` / `@Hidden` to keep admin endpoints out of the spec, or generate from a filtered subset.
- **Setting `skipValidateSpec=true` to bypass validation errors.** Fix the spec — invalid OpenAPI breaks downstream tooling.

## Post-generation

- Tell the user the commands:
  - TypeScript: `./mvnw -Pclient-ts package` → `clients/typescript/`.
  - Java: `./mvnw -Pclient-java package` → `clients/java/`.
- For local frontend testing: `cd clients/typescript && npm install && npm run build && npm link` → `npm link {{tsPackage}}` in the consumer.
- Suggest hosting the generated docs (e.g. `redocly build` against `docs/openapi.yaml`) on GitHub Pages.
