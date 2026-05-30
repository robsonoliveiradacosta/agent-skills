---
name: bootstrap-quarkus-rest
description: "Scaffold a new Quarkus 3.x REST project that follows this repository's layered architecture (resource/service/repository/entity), with Flyway-owned PostgreSQL schema, JWT auth, optional MinIO + WebSocket + scheduler, multi-stage Dockerfile and docker-compose stack. Use whenever the user wants to start a new Quarkus backend with the same conventions as this project."
---

# bootstrap-quarkus-rest

Bootstrap a new Quarkus 3.x REST service that matches this project's conventions: Java 21, layered architecture under `com.<group>.*`, Flyway-owned schema, SmallRye JWT, OpenAPI docs, health checks, REST Assured + Testcontainers, and a `docker-compose` stack for local infra.

This skill creates the **skeleton only**. Use the companion skills (`add-jwt-auth`, `add-minio-storage`, `add-crud-resource`, …) to layer features on top.

---

## When to invoke

- "Quero criar um projeto Quarkus novo com a mesma estrutura"
- "Bootstrap a Quarkus REST API"
- "Start a Java backend like this one"

## Inputs to collect first

Ask the user **only** for what cannot be inferred:

| Input | Default if user has no preference |
|---|---|
| `artifactId` (and target directory name) | required, kebab-case |
| Java package root (e.g. `com.acme.catalog`) | derive from artifactId |
| PostgreSQL database name | snake_case of artifactId |
| Include optional features? | none — start minimal, add later with companion skills |

Do **not** ask about: Quarkus version (3.31.1), Java version (21), test framework (JUnit 5 + REST Assured + Testcontainers), build tool (Maven). These are fixed by this project's standard.

## Workflow

1. Confirm the four inputs above in a single short message.
2. Create the directory tree.
3. Write the eight files in the templates section, substituting placeholders:
   - `{{artifactId}}` — Maven artifactId / kebab name
   - `{{groupId}}` — Maven groupId (default `com`)
   - `{{packageRoot}}` — Java package root (e.g. `com.acme.catalog`)
   - `{{packagePath}}` — same, with `.` → `/` (e.g. `com/acme/catalog`)
   - `{{dbName}}` — Postgres database
4. Run `chmod +x mvnw start.sh` and `git init && git add -A && git commit -m "Initial Quarkus skeleton"` only if the user asked for a fresh repo. If the user already invoked the skill inside an existing repo, **skip git init** and just leave the files staged for review.
5. Report next steps (run `add-jwt-auth` etc.).

## Directory tree to create

```
{{artifactId}}/
├── .mvn/wrapper/maven-wrapper.properties   (copy from official Quarkus 3.31.1 archetype)
├── mvnw, mvnw.cmd                          (copy from official Quarkus 3.31.1 archetype)
├── pom.xml
├── Dockerfile
├── docker-compose.yml
├── .env.example
├── .gitignore
├── start.sh
├── CLAUDE.md
├── README.md
└── src/
    ├── main/
    │   ├── docker/                         (let user add per-target Dockerfiles later)
    │   ├── java/{{packagePath}}/
    │   │   ├── config/                     (empty, ready for MinioStartup etc.)
    │   │   ├── dto/{request,response}/     (empty)
    │   │   ├── entity/                     (empty)
    │   │   ├── exception/                  (NotAuthorizedExceptionMapper from template)
    │   │   ├── health/                     (empty — add per-resource health checks)
    │   │   ├── repository/                 (empty)
    │   │   ├── resource/                   (empty)
    │   │   ├── service/                    (empty)
    │   │   └── security/                   (empty)
    │   └── resources/
    │       ├── application.properties
    │       └── db/migration/.gitkeep
    └── test/
        └── java/{{packagePath}}/
            ├── common/                     (empty — add PostgresResource via add-testcontainers-resource)
            └── util/                       (empty — add TestTokenHelper via add-jwt-auth)
```

## Critical conventions to enforce

- **Schema generation is OFF**: `quarkus.hibernate-orm.database.generation=none`. All schema changes happen via Flyway.
- **`deny-unannotated-endpoints=false`** combined with explicit `@RolesAllowed` on every resource method. Document this in the generated `CLAUDE.md` so future contributors don't get tripped up.
- **Dev Services disabled** (`quarkus.devservices.enabled=false`). Local infra runs from `docker-compose.yml`.
- **Test profile uses Flyway clean-at-start** against a separate `{{dbName}}_test` database.
- Token lifespan default: **300 s**. Always paired with a `/auth/refresh` endpoint.

---

## File templates

> Substitute `{{...}}` placeholders. The templates below are deliberately minimal — companion skills add features.

### `pom.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>{{groupId}}</groupId>
    <artifactId>{{artifactId}}</artifactId>
    <version>1.0-SNAPSHOT</version>

    <properties>
        <compiler-plugin.version>3.14.1</compiler-plugin.version>
        <maven.compiler.release>21</maven.compiler.release>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
        <quarkus.platform.artifact-id>quarkus-bom</quarkus.platform.artifact-id>
        <quarkus.platform.group-id>io.quarkus.platform</quarkus.platform.group-id>
        <quarkus.platform.version>3.31.1</quarkus.platform.version>
        <skipITs>true</skipITs>
        <surefire-plugin.version>3.5.4</surefire-plugin.version>
        <testcontainers.version>1.21.3</testcontainers.version>
    </properties>

    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>${quarkus.platform.group-id}</groupId>
                <artifactId>${quarkus.platform.artifact-id}</artifactId>
                <version>${quarkus.platform.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
            <dependency>
                <groupId>org.testcontainers</groupId>
                <artifactId>testcontainers-bom</artifactId>
                <version>${testcontainers.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>

    <dependencies>
        <dependency><groupId>io.quarkus</groupId><artifactId>quarkus-rest-jackson</artifactId></dependency>
        <dependency><groupId>io.quarkus</groupId><artifactId>quarkus-arc</artifactId></dependency>
        <dependency><groupId>io.quarkus</groupId><artifactId>quarkus-hibernate-orm-panache</artifactId></dependency>
        <dependency><groupId>io.quarkus</groupId><artifactId>quarkus-jdbc-postgresql</artifactId></dependency>
        <dependency><groupId>io.quarkus</groupId><artifactId>quarkus-flyway</artifactId></dependency>
        <dependency><groupId>io.quarkus</groupId><artifactId>quarkus-hibernate-validator</artifactId></dependency>
        <dependency><groupId>io.quarkus</groupId><artifactId>quarkus-smallrye-openapi</artifactId></dependency>
        <dependency><groupId>io.quarkus</groupId><artifactId>quarkus-smallrye-health</artifactId></dependency>

        <dependency><groupId>io.quarkus</groupId><artifactId>quarkus-junit5</artifactId><scope>test</scope></dependency>
        <dependency><groupId>io.rest-assured</groupId><artifactId>rest-assured</artifactId><scope>test</scope></dependency>
        <dependency><groupId>io.quarkus</groupId><artifactId>quarkus-junit5-mockito</artifactId><scope>test</scope></dependency>
        <dependency><groupId>org.testcontainers</groupId><artifactId>postgresql</artifactId><scope>test</scope></dependency>
        <dependency><groupId>org.testcontainers</groupId><artifactId>junit-jupiter</artifactId><scope>test</scope></dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>${quarkus.platform.group-id}</groupId>
                <artifactId>quarkus-maven-plugin</artifactId>
                <version>${quarkus.platform.version}</version>
                <extensions>true</extensions>
                <executions>
                    <execution>
                        <goals>
                            <goal>build</goal>
                            <goal>generate-code</goal>
                            <goal>generate-code-tests</goal>
                            <goal>native-image-agent</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>
            <plugin>
                <artifactId>maven-compiler-plugin</artifactId>
                <version>${compiler-plugin.version}</version>
                <configuration><parameters>true</parameters></configuration>
            </plugin>
            <plugin>
                <artifactId>maven-surefire-plugin</artifactId>
                <version>${surefire-plugin.version}</version>
                <configuration>
                    <argLine>--add-opens java.base/java.lang=ALL-UNNAMED</argLine>
                    <systemPropertyVariables>
                        <java.util.logging.manager>org.jboss.logmanager.LogManager</java.util.logging.manager>
                    </systemPropertyVariables>
                </configuration>
            </plugin>
            <plugin>
                <artifactId>maven-failsafe-plugin</artifactId>
                <version>${surefire-plugin.version}</version>
                <executions>
                    <execution>
                        <goals><goal>integration-test</goal><goal>verify</goal></goals>
                    </execution>
                </executions>
                <configuration>
                    <argLine>--add-opens java.base/java.lang=ALL-UNNAMED</argLine>
                    <systemPropertyVariables>
                        <native.image.path>${project.build.directory}/${project.build.finalName}-runner</native.image.path>
                        <java.util.logging.manager>org.jboss.logmanager.LogManager</java.util.logging.manager>
                    </systemPropertyVariables>
                </configuration>
            </plugin>
        </plugins>
    </build>

    <profiles>
        <profile>
            <id>native</id>
            <activation><property><name>native</name></property></activation>
            <properties>
                <quarkus.package.jar.enabled>false</quarkus.package.jar.enabled>
                <skipITs>false</skipITs>
                <quarkus.native.enabled>true</quarkus.native.enabled>
            </properties>
        </profile>
    </profiles>
</project>
```

### `src/main/resources/application.properties`

```properties
quarkus.application.name={{artifactId}}

# HTTP
quarkus.http.port=8080
quarkus.http.cors=true
quarkus.http.cors.origins=${CORS_ALLOWED_ORIGINS:http://localhost:3000}
quarkus.http.cors.methods=GET,POST,PUT,DELETE,OPTIONS
quarkus.http.cors.headers=Authorization,Content-Type

# Datasource
quarkus.datasource.db-kind=postgresql
quarkus.datasource.username=${DB_USERNAME:postgres}
quarkus.datasource.password=${DB_PASSWORD:postgres}
quarkus.datasource.jdbc.url=${DB_URL:jdbc:postgresql://localhost:5432/{{dbName}}}
quarkus.datasource.jdbc.max-size=16

# Hibernate — schema is owned by Flyway
quarkus.hibernate-orm.database.generation=none
quarkus.hibernate-orm.log.sql=false

# Flyway
quarkus.flyway.migrate-at-start=true
quarkus.flyway.baseline-on-migrate=true
quarkus.flyway.baseline-version=0
quarkus.flyway.locations=classpath:db/migration

# Security — explicit @RolesAllowed required everywhere; unannotated are public
quarkus.security.jaxrs.deny-unannotated-endpoints=false

# OpenAPI
quarkus.swagger-ui.always-include=true
quarkus.swagger-ui.path=/q/swagger-ui

# Health
quarkus.smallrye-health.root-path=/q/health

# Logging
quarkus.log.console.enable=true
quarkus.log.console.level=INFO
quarkus.log.category."{{packageRoot}}".level=DEBUG

# Dev Services off — local infra is docker-compose
quarkus.devservices.enabled=false

# Profiles
%dev.quarkus.log.console.level=DEBUG
%dev.quarkus.hibernate-orm.log.sql=true

%test.quarkus.datasource.jdbc.url=jdbc:postgresql://localhost:5432/{{dbName}}_test
%test.quarkus.flyway.migrate-at-start=true
%test.quarkus.flyway.clean-at-start=true

%prod.quarkus.log.console.level=INFO
%prod.quarkus.hibernate-orm.log.sql=false
```

### `Dockerfile` (multi-stage, distroless)

```dockerfile
FROM maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN ./mvnw -B -DskipTests dependency:go-offline
COPY src/ src/
RUN ./mvnw -B -DskipTests package

FROM gcr.io/distroless/java21-debian12:nonroot
WORKDIR /deployments
COPY --from=build /workspace/target/quarkus-app/lib/ /deployments/lib/
COPY --from=build /workspace/target/quarkus-app/app/ /deployments/app/
COPY --from=build /workspace/target/quarkus-app/quarkus/ /deployments/quarkus/
COPY --from=build /workspace/target/quarkus-app/quarkus-run.jar /deployments/quarkus-run.jar
EXPOSE 8080
USER nonroot
ENTRYPOINT ["java", "-Dquarkus.http.host=0.0.0.0", "-Djava.util.logging.manager=org.jboss.logmanager.LogManager", "-jar", "/deployments/quarkus-run.jar"]
```

### `docker-compose.yml`

```yaml
services:
  postgres:
    image: postgres:18.1-alpine3.23
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-{{dbName}}}
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres}
    ports: ["5432:5432"]
    volumes: [postgres_data:/var/lib/postgresql/data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-postgres}"]
      interval: 10s
      timeout: 5s
      retries: 5

  app:
    build: { context: ., dockerfile: Dockerfile }
    environment:
      DB_URL: jdbc:postgresql://postgres:5432/${POSTGRES_DB:-{{dbName}}}
      DB_USERNAME: ${POSTGRES_USER:-postgres}
      DB_PASSWORD: ${POSTGRES_PASSWORD:-postgres}
      CORS_ALLOWED_ORIGINS: ${CORS_ALLOWED_ORIGINS:-http://localhost:3000}
    ports: ["8080:8080"]
    depends_on:
      postgres: { condition: service_healthy }
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/q/health/live"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

volumes:
  postgres_data:
```

### `.env.example`

```bash
POSTGRES_DB={{dbName}}
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
CORS_ALLOWED_ORIGINS=http://localhost:3000
```

### `.gitignore`

```
target/
.idea/
*.iml
.vscode/
.env
src/main/resources/privateKey.pem
src/main/resources/publicKey.pem
```

### `start.sh`

```bash
#!/bin/bash
set -e
echo "Building application..."
./mvnw package -DskipTests
echo "Starting services..."
docker compose up --build -d
echo "Waiting for services to be healthy..."
sleep 20
curl -s http://localhost:8080/q/health
echo ""
echo "API: http://localhost:8080  | Swagger: http://localhost:8080/q/swagger-ui"
```

### `src/main/java/{{packagePath}}/exception/NotAuthorizedExceptionMapper.java`

```java
package {{packageRoot}}.exception;

import jakarta.ws.rs.NotAuthorizedException;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;

@Provider
public class NotAuthorizedExceptionMapper implements ExceptionMapper<NotAuthorizedException> {
    @Override
    public Response toResponse(NotAuthorizedException exception) {
        return Response.status(Response.Status.UNAUTHORIZED)
                .entity("{\"status\":401,\"error\":\"Unauthorized\"}")
                .type("application/json")
                .build();
    }
}
```

### `CLAUDE.md` (initial)

Generate a short CLAUDE.md pointing to the same architecture conventions: Flyway owns schema, `@RolesAllowed` mandatory, devservices off, JWT keys not in git. Reference companion skills (`/add-crud-resource`, `/add-jwt-auth`, etc.) so the next contributor knows where to extend.

---

## Post-bootstrap checklist

Tell the user to run, in order:

1. `/add-jwt-auth` — wire SmallRye JWT (keys, TokenService, AuthResource, users table). **Required before any `@RolesAllowed`-protected endpoint works.**
2. `/add-testcontainers-resource postgres` — adds `PostgresResource` so unit tests don't need a running local DB.
3. `/add-crud-resource <EntityName>` — for each domain entity.
4. Optional: `/add-minio-storage`, `/add-rate-limit`, `/add-websocket-broadcast`, `/add-scheduled-rest-client`.

Never run `./mvnw quarkus:dev` before step 1 — there are no migrations yet and the app will start with an empty schema.

---

## Strategic considerations & governance

## Goal

Create a production-oriented Quarkus API skeleton that matches this repository's structure and defaults. Prefer the existing architecture over generic Quarkus examples.

## Workflow

1. Confirm the domain name, base package, database name, and required integrations.
2. Create a Maven wrapper project targeting Java 21 and Quarkus 3.x.
3. Add core dependencies: REST Jackson, Arc, Hibernate ORM Panache, PostgreSQL JDBC, Flyway, Hibernate Validator, SmallRye OpenAPI, SmallRye Health, and JUnit 5 test support.
4. Add optional integrations only when needed: SmallRye JWT, MinIO, REST Client Jackson, Scheduler, WebSocket, Bucket4j, Testcontainers, Mockito, REST Assured, and WireMock.
5. Create the standard package layout:

```text
src/main/java/<base>/{config,dto/request,dto/response,entity,exception,health,integration,repository,resource,scheduler,security,service,websocket}
src/main/resources/db/migration
src/test/java/<base>/{common,resource,security,service,util}
```

6. Add `application.properties` with environment-variable overrides for database, CORS, JWT, MinIO, external APIs, OpenAPI, health, logging, and `%dev`, `%test`, `%prod` profiles.
7. Add Docker assets: root `Dockerfile`, `docker-compose.yml`, and Quarkus Dockerfiles under `src/main/docker`.
8. Add `README.md`, `AGENTS.md`, and a small `start.sh` when the stack needs multiple services.

## Baseline Conventions

- Use package names in lowercase and avoid framework code outside the base package.
- Keep REST resources thin; move business rules into services.
- Use Flyway for schema changes. Do not rely on Hibernate auto-DDL outside throwaway experiments.
- Make configuration externalized with safe local defaults.
- Ensure `/q/swagger-ui` and `/q/health` work in local development.

## Validation

Run `./mvnw test` for the generated project. Run `docker compose config` and `docker compose up -d postgres minio` when Docker services are included.

## Example

User request: "Create a catalog API for books and authors with auth, PostgreSQL, Docker Compose, Flyway, OpenAPI, and tests."

Expected output: a Quarkus project with `BookResource`, `BookService`, `BookRepository`, `Book`, request/response DTOs, Flyway migrations, test scaffolding, Docker services, and documented local commands.
