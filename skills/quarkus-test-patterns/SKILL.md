---
name: quarkus-test-patterns
description: "Design and implement tests for this repository's Quarkus architecture. Use when adding or fixing unit tests, resource/API tests, integration tests, Testcontainers resources, REST Assured assertions, Mockito-based service tests, WireMock tests, auth tests, or Maven test commands."
---

# quarkus-test-patterns

## Goal

Add focused tests that protect behavior without making the suite brittle.

## Test Types

- Service tests verify business rules, validation, mapping, and repository interactions.
- Resource tests verify HTTP status codes, request validation, auth behavior, response shape, pagination, and sorting.
- Integration tests verify database, Flyway, MinIO, external API, or WebSocket behavior.
- Security tests verify JWT, roles, rate limits, and access control boundaries.

## Workflow

1. Identify the behavior and layer under change.
2. Add the narrowest test that catches the risk.
3. Use Mockito for isolated service rules and Quarkus tests for CDI/resource behavior.
4. Use REST Assured for HTTP API tests.
5. Use Testcontainers for real infrastructure behavior and WireMock for external APIs.
6. Keep helpers in `src/test/java/com/quarkus/common` or `util`.
7. Run the smallest relevant command first, then broaden if the change affects shared behavior.

## Naming and Commands

- Name classes `*Test`, for example `AlbumServiceTest` or `RegionalResourceTest`.
- Run one test: `./mvnw test -Dtest=AlbumResourceTest`.
- Run the suite: `./mvnw test`.
- Run integration verification: `./mvnw verify`.

## Assertion Rules

- Assert business outcomes, not incidental implementation details.
- Include negative cases for validation, not found, unauthorized, and forbidden paths.
- Keep test data explicit and minimal.
- Avoid relying on test order.

## Example

For a new admin-only `GenreResource`, test create success as admin, `403` as user, `401` without a token, invalid payload `400`, duplicate name conflict, list pagination, and get-by-id not found.
