---
name: architecture-decision-records
description: "Create and maintain architecture decision records for Quarkus API projects. Use when documenting significant choices about Quarkus, Panache, Flyway, PostgreSQL, MinIO, JWT, Testcontainers, Docker, transactions, migrations, security, observability, or operational tradeoffs."
---

# architecture-decision-records

## Goal

Capture important technical decisions so future contributors understand context, tradeoffs, and consequences.

## Workflow

1. Create ADRs for decisions that are hard to reverse, cross-cutting, operationally important, or likely to be questioned later.
2. Store ADRs under `docs/adr` unless the repository already has a different convention.
3. Use a simple structure: title, status, date, context, decision, consequences, alternatives, and links.
4. Keep ADRs factual and concise; document why the decision was made, not just what was chosen.
5. Update or supersede ADRs instead of silently rewriting history.

## ADR Candidates

- Quarkus and Java version choices.
- PostgreSQL plus Flyway for persistence.
- MinIO for object storage.
- JWT and role-based access.
- Testcontainers and WireMock test strategy.
- Docker Compose local runtime.
- Migration and transaction safety policy.

## Example

An ADR for MinIO should explain why object storage is separate from PostgreSQL, how metadata is stored, what failure modes exist, and how local Docker Compose supports it.
