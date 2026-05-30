---
name: release-readiness-checklist
description: "Prepare Quarkus REST APIs for safe releases. Use before deployment or tagging to verify tests, migrations, configuration, secrets, Docker images, health checks, API compatibility, rollback notes, release notes, operational risks, and production readiness."
---

# release-readiness-checklist

## Goal

Make release decisions explicit and reduce production surprises.

## Checklist

1. Build and tests: targeted tests, `./mvnw test`, and `./mvnw verify` when integration paths changed.
2. Database: Flyway migrations ordered, reviewed, non-destructive or approved, and compatible with existing data.
3. API contract: OpenAPI, README examples, status codes, and DTO compatibility reviewed.
4. Security: no secrets committed, auth paths tested, roles verified, JWT keys configured outside production images.
5. Runtime: Docker build, Compose config, health endpoints, and environment variables verified.
6. Observability: logs, correlation IDs, health checks, and operational failure modes are adequate.
7. Rollback: data and deployment rollback options are known.
8. Notes: release summary, risks, manual steps, and post-deploy checks are documented.

## Release Evidence

Capture commit SHA, commands run, image tag, migration list, changed endpoints, config changes, and residual risks.

## Stop Conditions

Do not release when migrations are untested, credentials are embedded, health checks fail, breaking API changes are undocumented, or rollback is unknown for risky data changes.

## Example

For a release adding image uploads, verify MinIO config, bucket startup, upload limits, health checks, Docker env vars, resource tests, and rollback behavior for metadata migrations.
