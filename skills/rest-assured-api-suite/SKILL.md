---
name: rest-assured-api-suite
description: "Build professional REST Assured suites for Quarkus APIs. Use when testing REST resources, authentication, authorization, JSON payloads, validation errors, pagination, filters, sorting, multipart uploads, headers, rate limits, and documented response contracts."
---

# rest-assured-api-suite

## Goal

Write HTTP-level tests that prove the API contract and security behavior clients depend on.

## Workflow

1. Create explicit fixtures for users, tokens, and domain data.
2. Cover happy path, validation failure, not found, conflict, unauthorized, forbidden, and unsupported media paths.
3. Assert status, content type, stable fields, error code, and important headers.
4. Test pagination, filters, sorting, and default values for list endpoints.
5. Use multipart helpers for uploads and avoid relying on external local files.
6. Keep tests independent and readable; avoid hidden shared mutable state.

## Patterns

- Use helper methods for `adminToken()`, `userToken()`, common payload builders, and JSON path assertions.
- Keep one behavior per test when diagnosing failures matters.
- Prefer asserting contract fields over full JSON snapshots.
- Use `given().auth().oauth2(token)` for protected endpoints.

## Required Cases

- Public endpoint without token if applicable.
- Protected endpoint without token and with wrong role.
- Invalid payload shape and invalid field values.
- Success response shape and persisted side effects.

## Example

For `POST /v1/albums`, test admin success, user `403`, anonymous `401`, missing title `400`, invalid artist ID `404`, duplicate conflict `409`, and response fields `id`, `title`, `year`, and `artists`.
