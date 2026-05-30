---
name: dockerized-quarkus-runtime
description: "Package and run Quarkus APIs with Docker and Docker Compose following this repository's runtime pattern. Use when creating Dockerfiles, docker-compose services, environment variables, PostgreSQL/MinIO dependencies, health checks, JVM/native container builds, local start scripts, or deployment-ready runtime documentation."
---

# dockerized-quarkus-runtime

## Goal

Create a reproducible local and container runtime for Quarkus APIs without hiding configuration in code.

## Workflow

1. Build the application with `./mvnw package` before JVM container packaging.
2. Add a root `Dockerfile` for the default Compose app service.
3. Keep Quarkus-generated variants in `src/main/docker`: JVM, legacy jar, native, and native micro when needed.
4. Add `docker-compose.yml` services for the app and required dependencies.
5. Configure dependencies with environment variables and safe local defaults.
6. Add health checks for app, PostgreSQL, and MinIO when present.
7. Add `start.sh` only when it improves the common local workflow.

## Compose Rules

- Use service names in internal URLs, for example `jdbc:postgresql://postgres:5432/<db>` and `http://minio:9000`.
- Use `depends_on` with health conditions for infrastructure dependencies.
- Keep credentials overridable through `.env`; do not hard-code production secrets.
- Expose only useful local ports such as `8080`, `5432`, `9000`, and `9001`.

## Commands

```bash
./mvnw package -DskipTests
docker compose up --build -d
docker compose ps
docker compose logs -f app
docker compose down
```

## Validation

Run `docker compose config`, start the stack, and verify `http://localhost:8080/q/health`. For native builds, use `./mvnw package -Dnative -Dquarkus.native.container-build=true` when GraalVM is not installed locally.
