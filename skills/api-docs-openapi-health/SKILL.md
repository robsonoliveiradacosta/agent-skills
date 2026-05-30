---
name: api-docs-openapi-health
description: "Add API documentation, OpenAPI metadata, Swagger UI examples, and Quarkus health checks. Use when documenting REST resources, adding operation summaries, response schemas, request examples, error responses, /q/swagger-ui configuration, /q/health checks, readiness/liveness probes, or operational endpoint docs."
---

# api-docs-openapi-health

## Goal

Make API behavior inspectable for developers and operators without duplicating truth across too many files.

## OpenAPI Workflow

1. Configure OpenAPI metadata in `application.properties`: title, version, description, contact, and Swagger UI path.
2. Add resource-level and method-level annotations when they clarify behavior.
3. Document request DTOs with validation constraints and meaningful field names.
4. Include success and error response shapes for public endpoints.
5. Keep examples realistic and consistent with seeded users and domain data.
6. Update README endpoint examples when user-facing API behavior changes.

## Health Workflow

1. Add liveness checks for application process health.
2. Add readiness checks for dependencies such as PostgreSQL and MinIO.
3. Keep health checks fast, side-effect free, and safe to run frequently.
4. Surface dependency names clearly in failure data while avoiding secrets.
5. Verify `/q/health`, `/q/health/live`, and `/q/health/ready`.

## Design Rules

- Do not use documentation annotations to compensate for unclear DTOs or inconsistent endpoint names.
- Keep OpenAPI output aligned with actual status codes and validation behavior.
- Treat health checks as operational contracts; avoid expensive queries or remote sync calls.

## Example

For a new `GenreResource`, document list, get, create, update, and delete operations, include `400`, `401`, `403`, and `404` responses where applicable, and update README examples if the endpoint is part of the public API.
