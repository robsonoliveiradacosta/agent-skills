---
name: api-test-strategy-matrix
description: "Create professional QA test strategy matrices for Quarkus REST API features. Use when deciding coverage across unit, service, resource, integration, contract, security, performance, smoke, regression, and exploratory tests before or after implementing API changes."
---

# api-test-strategy-matrix

## Goal

Choose the right tests for each API change before writing large suites. Use this to avoid both gaps and duplicate low-value tests.

## Workflow

1. Identify changed endpoints, services, entities, migrations, external dependencies, roles, and files.
2. Classify risk: business criticality, data mutation, auth sensitivity, external IO, concurrency, and backward compatibility.
3. Fill a test matrix by layer: unit, service, resource, integration, contract, security, performance, smoke, and regression.
4. Mark each planned test as required, optional, or unnecessary with a short reason.
5. Prefer the narrowest layer that proves the behavior, then add end-to-end coverage for critical flows.

## Matrix Columns

- Scenario: user-visible behavior or failure mode.
- Layer: service, resource, integration, contract, security, performance, or smoke.
- Tool: JUnit, Mockito, REST Assured, Testcontainers, WireMock, k6, PIT, or manual exploratory.
- Data: fixture, seed user, token, file, or external stub.
- Evidence: command, assertion, report, or CI gate.

## Quality Rules

- Every mutating endpoint needs success, validation, auth, and conflict or not-found coverage.
- Every external dependency needs timeout and failure coverage.
- Every public contract change needs OpenAPI or REST payload verification.

## Example

For album image upload, include service validation tests, REST Assured multipart tests, MinIO integration tests, admin/user auth tests, invalid MIME and oversized file tests, and a smoke test for `/q/health`.
