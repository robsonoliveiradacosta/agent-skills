---
name: add-testcontainers-resource
description: "Generate a Quarkus QuarkusTestResourceLifecycleManager that starts a Testcontainers container (PostgreSQL, MinIO, Kafka, Redis, …) and overrides the relevant Quarkus config properties for tests. Use whenever the user asks for an isolated test container, \"Testcontainers wrapper\", \"test resource for X\", or wants tests to stop depending on a local running service."
---

# add-testcontainers-resource

Generate a `QuarkusTestResourceLifecycleManager` implementation for Testcontainers, matching this repo's `PostgresResource` / `MinioTestResource` style. The generated class is wired into specific test classes via `@QuarkusTestResource(<Resource>.class)` so different tests can opt in independently.

## When to invoke

- "Add a Postgres test resource"
- "I want tests to run without a local DB"
- "Wrap MinIO / Redis / Kafka in Testcontainers"

## Inputs to collect

| Input | Notes |
|---|---|
| Service kind | `postgres`, `minio`, `redis`, `kafka`, `mongodb`, generic GenericContainer |
| Image tag | If unspecified, use the version already in the project's `docker-compose.yml` for consistency |
| Test class names that should use it | Optional — if listed, also wire `@QuarkusTestResource` annotations |

## Dependencies (per kind)

```xml
<dependency>
    <groupId>org.testcontainers</groupId>
    <artifactId>postgresql</artifactId>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.testcontainers</groupId>
    <artifactId>minio</artifactId>
    <scope>test</scope>
</dependency>
```

(For Kafka / Redis / MongoDB, swap the artifactId accordingly.)

## Templates per kind

### PostgreSQL — `test/.../common/PostgresResource.java`

```java
package {{packageRoot}}.common;

import io.quarkus.test.common.QuarkusTestResourceLifecycleManager;
import org.testcontainers.containers.PostgreSQLContainer;

import java.util.Map;

public class PostgresResource implements QuarkusTestResourceLifecycleManager {

    private final PostgreSQLContainer<?> postgres =
        new PostgreSQLContainer<>("postgres:18.1-alpine3.23");

    @Override
    public Map<String, String> start() {
        postgres.withUsername("user_test")
                .withPassword("password_test")
                .withDatabaseName("{{dbName}}_test")
                .start();
        return Map.of(
            "quarkus.datasource.jdbc.url", postgres.getJdbcUrl(),
            "quarkus.datasource.username",  postgres.getUsername(),
            "quarkus.datasource.password",  postgres.getPassword()
        );
    }

    @Override
    public void stop() { postgres.stop(); }
}
```

### MinIO — `test/.../common/MinioTestResource.java`

```java
package {{packageRoot}}.common;

import io.quarkus.test.common.QuarkusTestResourceLifecycleManager;
import org.testcontainers.containers.MinIOContainer;

import java.util.Map;

public class MinioTestResource implements QuarkusTestResourceLifecycleManager {

    private final MinIOContainer minio =
        new MinIOContainer("minio/minio:RELEASE.2025-09-07T16-13-09Z")
            .withUserName("minioadmin")
            .withPassword("minioadmin");

    @Override
    public Map<String, String> start() {
        minio.start();
        return Map.of(
            "quarkus.minio.host", minio.getS3URL(),
            "quarkus.minio.access-key", "minioadmin",
            "quarkus.minio.secret-key", "minioadmin"
        );
    }

    @Override
    public void stop() { minio.stop(); }
}
```

### Redis — `test/.../common/RedisTestResource.java`

```java
package {{packageRoot}}.common;

import io.quarkus.test.common.QuarkusTestResourceLifecycleManager;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.utility.DockerImageName;

import java.util.Map;

public class RedisTestResource implements QuarkusTestResourceLifecycleManager {

    private final GenericContainer<?> redis =
        new GenericContainer<>(DockerImageName.parse("redis:7-alpine"))
            .withExposedPorts(6379);

    @Override
    public Map<String, String> start() {
        redis.start();
        return Map.of(
            "quarkus.redis.hosts",
            "redis://" + redis.getHost() + ":" + redis.getMappedPort(6379)
        );
    }

    @Override
    public void stop() { redis.stop(); }
}
```

### Kafka — `test/.../common/KafkaTestResource.java`

```java
package {{packageRoot}}.common;

import io.quarkus.test.common.QuarkusTestResourceLifecycleManager;
import org.testcontainers.kafka.ConfluentKafkaContainer;
import org.testcontainers.utility.DockerImageName;

import java.util.Map;

public class KafkaTestResource implements QuarkusTestResourceLifecycleManager {

    private final ConfluentKafkaContainer kafka =
        new ConfluentKafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.6.0"));

    @Override
    public Map<String, String> start() {
        kafka.start();
        return Map.of("kafka.bootstrap.servers", kafka.getBootstrapServers());
    }

    @Override
    public void stop() { kafka.stop(); }
}
```

### Generic — `test/.../common/<Name>TestResource.java`

Use when no first-class Testcontainers module exists. Adapt `withExposedPorts` and the property map.

```java
GenericContainer<?> container = new GenericContainer<>(DockerImageName.parse("<image>"))
    .withExposedPorts(<port>)
    .waitingFor(Wait.forListeningPort());
```

## Usage in tests

Show the user how to wire it into a specific test:

```java
@QuarkusTest
@QuarkusTestResource(PostgresResource.class)
class GenreResourceTest { ... }
```

For multiple resources, stack annotations:

```java
@QuarkusTest
@QuarkusTestResource(PostgresResource.class)
@QuarkusTestResource(MinioTestResource.class)
class ImageResourceTest { ... }
```

> **Don't** add `@QuarkusTestResource` globally via `META-INF/services` unless the user explicitly asks for it. Selective resources let fast tests stay fast.

## Conventions to enforce

- Test resource classes live in `src/test/java/.../common/`. Keep them out of `service/`, `resource/` packages.
- Image tags **match the docker-compose.yml** versions exactly. Test/prod parity reduces "works on my machine".
- Don't override more properties than necessary — surprising overrides break the next test author's mental model.
- For databases, return the **container-generated URL/user/password**, not hardcoded values. Testcontainers picks a random port; never assume the default.

## Anti-patterns to refuse

- Reusing a singleton container across the whole JVM via static fields without `withReuse(true)` and `~/.testcontainers.properties` enabled. If the user wants reuse, opt in explicitly — silent reuse leaks state between tests.
- Mocking the DB instead of using Testcontainers. The whole point of this skill is real-infra fidelity.
- Setting `quarkus.devservices.enabled=true` to "skip writing this" — the project has it off globally for good reasons (compose is the source of truth for local infra).

---

## Strategic considerations & governance

## Goal

Create integration tests that exercise real infrastructure while staying deterministic in local and CI runs.

## Workflow

1. Decide which dependency must be real: PostgreSQL, MinIO, external HTTP service, or multiple services together.
2. Centralize container setup in shared test resources such as `PostgresResource` or `MinioTestResource`.
3. Wire Quarkus test configuration through dynamic properties, not hard-coded localhost ports.
4. Keep data isolated with Flyway clean-at-start, explicit cleanup, or per-test identifiers.
5. Use WaitStrategies and health checks instead of sleeps.
6. Keep container logs available when CI failures occur.

## Stability Rules

- Avoid fixed host ports unless the project requires them.
- Do not share mutable test data across unrelated tests.
- Keep images pinned enough for reproducibility.
- Fail fast when Docker is unavailable and document the requirement.
- Use WireMock for remote APIs instead of calling real services.

## Example

For MinIO upload tests, start a MinIO container, create the bucket during test resource startup, inject the endpoint into Quarkus config, upload a small in-memory image, and assert object metadata plus API response.
