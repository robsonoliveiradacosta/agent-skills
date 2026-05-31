# agent-skills

A collection of agent-agnostic Agent Skills — reusable instruction sets in the universal `SKILL.md` format. Install them into Claude Code, Cursor, opencode, Codex, Windsurf, and 40+ other agents with the `skills` CLI.

## Install

```bash
# Preview what's in this repo
npx skills add robsonoliveiradacosta/agent-skills --list

# Install all skills (interactive)
npx skills add robsonoliveiradacosta/agent-skills

# Install a specific skill
npx skills add robsonoliveiradacosta/agent-skills --skill commit
```

Useful flags:

- `-a <agent>` — target a specific agent (e.g. `-a claude-code`, `-a cursor`, `-a opencode`).
- `-g` — install globally (`~/.<agent>/skills/`) instead of per-project.
- `-y` — non-interactive, for CI/CD.

## Skills

65 skills, mostly geared toward backend APIs built with **Quarkus 3.x + Panache + PostgreSQL** (plus an **Angular frontend** set, a few agent-agnostic ones like `commit`, the spec-driven workflow, and the PRD-driven workflow).

### Project setup & scaffolding

| Skill | Description |
| --- | --- |
| [`bootstrap-quarkus-rest`](skills/bootstrap-quarkus-rest/SKILL.md) | Scaffold a new Quarkus REST project with the repo's layered architecture (resource/service/repository/entity), Flyway, JWT, Docker. |
| [`add-crud-resource`](skills/add-crud-resource/SKILL.md) | Generate a full CRUD slice for a new entity — entity, repository, service, resource, DTOs, migration, and tests in one pass. |
| [`dockerized-quarkus-runtime`](skills/dockerized-quarkus-runtime/SKILL.md) | Package and run the API with multi-stage Dockerfile + docker-compose (Postgres/MinIO), health checks, JVM/native builds. |
| [`add-ci-pipeline`](skills/add-ci-pipeline/SKILL.md) | Generate a GitHub Actions pipeline — build, tests against real Postgres, JVM/native matrix, Trivy scan, SBOM, GHCR release. |

### Frontend (Angular)

A separate-repo Angular SPA that consumes the Quarkus API through a generated OpenAPI client. Pairs with the design skills in [`external-skills.md`](external-skills.md) (`frontend-design`, `ui-ux-pro-max`, `angular-developer`).

| Skill | Description |
| --- | --- |
| [`bootstrap-angular-app`](skills/bootstrap-angular-app/SKILL.md) | Scaffold a standalone Angular app (signals, Tailwind) wired to the API via a generated `typescript-angular` OpenAPI client, with env config and a dev proxy. |
| [`add-angular-jwt-auth`](skills/add-angular-jwt-auth/SKILL.md) | Login/refresh against the Quarkus JWT backend — Bearer interceptor, **proactive** token refresh before expiry, and `authGuard`/`roleGuard` route protection. |
| [`add-primeng-ui`](skills/add-primeng-ui/SKILL.md) | Wire PrimeNG (component library) into a Tailwind app the v18+ way — `providePrimeNG` theme preset plus the CSS `@layer` order that makes PrimeNG and Tailwind coexist. |
| [`add-angular-ci`](skills/add-angular-ci/SKILL.md) | GitHub Actions for the SPA — build, lint, headless tests, an OpenAPI-client drift check, and static deploy (Nginx / S3+CloudFront / Vercel). |

Run them in order — each builds on the previous: `bootstrap-angular-app` → `add-angular-jwt-auth` → `add-primeng-ui` (optional) → `add-angular-ci`.

### REST API features

| Skill | Description |
| --- | --- |
| [`add-api-versioning`](skills/add-api-versioning/SKILL.md) | URL-path API versioning with RFC 8594 deprecation/sunset headers and per-version OpenAPI docs. |
| [`add-pagination`](skills/add-pagination/SKILL.md) | Convert a listing endpoint to the `PageResponse<T>` pattern with page/size/sort/filter params. |
| [`add-error-handling`](skills/add-error-handling/SKILL.md) | Replace ad-hoc errors with RFC 7807 Problem Details mappers that never leak stack traces. |
| [`add-rate-limit`](skills/add-rate-limit/SKILL.md) | Per-principal in-process rate limiting with bucket4j and `X-RateLimit-*` headers. |
| [`add-idempotency-key`](skills/add-idempotency-key/SKILL.md) | Stripe-style `Idempotency-Key` support so retries of POST/PUT/PATCH are safe. |
| [`add-cache`](skills/add-cache/SKILL.md) | Declarative method-level caching with quarkus-cache (Caffeine or Redis), TTL and size caps. |
| [`add-fault-tolerance`](skills/add-fault-tolerance/SKILL.md) | Harden external calls with `@Timeout`/`@Retry`/`@CircuitBreaker`/`@Bulkhead`/`@Fallback`. |
| [`add-scheduled-rest-client`](skills/add-scheduled-rest-client/SKILL.md) | Periodic sync job consuming an external REST API via MicroProfile REST Client. |
| [`add-websocket-broadcast`](skills/add-websocket-broadcast/SKILL.md) | websockets-next broadcast endpoint that fans out events to all connected clients. |
| [`add-openapi-client-gen`](skills/add-openapi-client-gen/SKILL.md) | Generate typed client SDKs (TS, Java, Kotlin, Python…) from the project's OpenAPI spec. |
| [`api-docs-openapi-health`](skills/api-docs-openapi-health/SKILL.md) | Add OpenAPI metadata, Swagger UI examples, and readiness/liveness health checks. |

### Auth & security

| Skill | Description |
| --- | --- |
| [`add-jwt-auth`](skills/add-jwt-auth/SKILL.md) | Wire SmallRye JWT (RS256) auth — keys, User entity, login/refresh endpoints, test token helper. |
| [`add-multi-tenancy`](skills/add-multi-tenancy/SKILL.md) | Row-level multi-tenancy via Hibernate `@TenantId` resolved from JWT claims. |
| [`api-security-testing`](skills/api-security-testing/SKILL.md) | Security-focused tests — JWT, RBAC, auth bypass, injection, uploads, OWASP API Top 10. |
| [`threat-modeling-api-security`](skills/threat-modeling-api-security/SKILL.md) | Threat-model an API with OWASP API Top 10 and STRIDE-style thinking. |
| [`secrets-config-management`](skills/secrets-config-management/SKILL.md) | Manage secrets and runtime config — profiles, env vars, JWT keys, rotation, exposure review. |
| [`dependency-supply-chain-security`](skills/dependency-supply-chain-security/SKILL.md) | Audit Maven/Docker supply chain — CVEs, base images, SBOMs, license risk, CI gates. |
| [`privacy-data-retention-lgpd`](skills/privacy-data-retention-lgpd/SKILL.md) | Review privacy/LGPD concerns — PII in logs, deletion/anonymization, retention periods. |

### Persistence & database

| Skill | Description |
| --- | --- |
| [`add-flyway-migration`](skills/add-flyway-migration/SKILL.md) | Create the next sequential Flyway migration with a template matching the change type. |
| [`add-jsonb-column`](skills/add-jsonb-column/SKILL.md) | Add a PostgreSQL JSONB column with GIN index and typed Hibernate mapping. |
| [`add-audit-trail`](skills/add-audit-trail/SKILL.md) | Automatic `created_at`/`updated_at`/`created_by`/`updated_by` audit columns via a listener. |
| [`add-soft-delete`](skills/add-soft-delete/SKILL.md) | Convert an entity to soft-delete with `deleted_at`, restore, and 410 Gone semantics. |
| [`add-purge-job`](skills/add-purge-job/SKILL.md) | Scheduled hard-delete of soft-deleted rows past a configurable retention window. |
| [`add-optimistic-locking`](skills/add-optimistic-locking/SKILL.md) | Add `@Version` optimistic locking with a 409 Conflict mapper and retry pattern. |
| [`add-bulk-operations`](skills/add-bulk-operations/SKILL.md) | Efficient batched inserts/updates/deletes with proper flush+clear and JPQL bulk ops. |
| [`add-outbox-pattern`](skills/add-outbox-pattern/SKILL.md) | Transactional outbox for reliable event publishing to Kafka/RabbitMQ/webhooks. |
| [`add-minio-storage`](skills/add-minio-storage/SKILL.md) | MinIO (S3-compatible) object storage with presigned URLs and a health check. |
| [`panache-orm-mapping-patterns`](skills/panache-orm-mapping-patterns/SKILL.md) | Design JPA/Hibernate+Panache mappings — relationships, fetch, cascade, N+1 prevention. |
| [`postgres-query-patterns`](skills/postgres-query-patterns/SKILL.md) | Predictable repository query patterns — filters, pagination, joins, counts, existence checks. |
| [`postgres-migration-safety`](skills/postgres-migration-safety/SKILL.md) | Plan safe, zero-downtime Flyway migrations — backfills, constraints, large-table changes. |
| [`data-integrity-constraints`](skills/data-integrity-constraints/SKILL.md) | Design DB-backed integrity — unique/FK/check constraints aligned with Bean Validation. |
| [`transaction-boundary-design`](skills/transaction-boundary-design/SKILL.md) | Decide `@Transactional` placement, rollback behavior, and service-method atomicity. |
| [`database-performance-review`](skills/database-performance-review/SKILL.md) | Review Postgres/JPA/Panache performance — indexes, query plans, N+1, lock behavior. |

### Observability & operations

| Skill | Description |
| --- | --- |
| [`add-observability`](skills/add-observability/SKILL.md) | Micrometer/Prometheus metrics, OpenTelemetry tracing, structured logs, request-id correlation. |
| [`sre-incident-runbooks`](skills/sre-incident-runbooks/SKILL.md) | Incident runbooks for API/Postgres/MinIO/JWT/migration failures and follow-up. |
| [`backup-restore-disaster-recovery`](skills/backup-restore-disaster-recovery/SKILL.md) | Plan backup/restore/rollback/DR for Postgres + MinIO with RPO/RTO and restore drills. |
| [`release-readiness-checklist`](skills/release-readiness-checklist/SKILL.md) | Pre-deploy checklist — tests, migrations, secrets, images, compatibility, rollback notes. |

### Testing

| Skill | Description |
| --- | --- |
| [`add-testcontainers-resource`](skills/add-testcontainers-resource/SKILL.md) | Generate a Testcontainers-backed `QuarkusTestResourceLifecycleManager` (Postgres, Kafka…). |
| [`add-test-data-builders`](skills/add-test-data-builders/SKILL.md) | Fluent test data builders per entity with sensible defaults and a `persisted()` variant. |
| [`add-load-testing`](skills/add-load-testing/SKILL.md) | k6 load tests derived from OpenAPI with thresholds and a nightly CI run. |
| [`add-mutation-testing`](skills/add-mutation-testing/SKILL.md) | Pitest mutation testing to measure real test quality and gate PRs on the score. |
| [`add-pact-contract-tests`](skills/add-pact-contract-tests/SKILL.md) | Pact provider-side contract verification against the running API in CI. |
| [`quarkus-test-patterns`](skills/quarkus-test-patterns/SKILL.md) | Patterns for unit/resource/integration tests with REST Assured, Mockito, WireMock. |
| [`persistence-test-patterns`](skills/persistence-test-patterns/SKILL.md) | Test repositories, migrations, transactions, and relationships against real Postgres. |
| [`rest-assured-api-suite`](skills/rest-assured-api-suite/SKILL.md) | Build REST Assured suites covering auth, payloads, validation, pagination, uploads. |
| [`api-test-strategy-matrix`](skills/api-test-strategy-matrix/SKILL.md) | QA test-strategy matrix across unit→exploratory layers before/after API changes. |
| [`flaky-test-triage`](skills/flaky-test-triage/SKILL.md) | Diagnose and fix intermittent tests — shared data, clocks, async, ports, races. |

### Spec-driven workflow

| Skill | Description |
| --- | --- |
| [`spec-create`](skills/spec-create/SKILL.md) | Start a feature spec (`spec.md`) — problem, goals, behavior, acceptance criteria. |
| [`spec-plan`](skills/spec-plan/SKILL.md) | Turn a spec into an architectural `plan.md` naming files, migrations, and skills to use. |
| [`spec-tasks`](skills/spec-tasks/SKILL.md) | Break the plan into an ordered, atomic `tasks.md` checklist with validation steps. |
| [`spec-implement`](skills/spec-implement/SKILL.md) | Execute the next pending task, run its validation, and tick the checkbox when it passes. |

### PRD-driven workflow

A heavier, document-first flow (`PRD → tech spec → tasks → execute`) that writes everything under `tasks/prd-<feature>/`. Each step asks for approval before writing files; templates ship bundled inside each skill.

| Skill | Description |
| --- | --- |
| [`create-prd`](skills/create-prd/SKILL.md) | Ask clarifying questions, then write a Product Requirements Document (`prd.md`) focused on the what/why. |
| [`create-techspec`](skills/create-techspec/SKILL.md) | Read the PRD, analyze the repo, and write an implementation-ready Tech Spec (`techspec.md`). |
| [`create-tasks`](skills/create-tasks/SKILL.md) | Break the PRD + tech spec into an ordered `tasks.md` plus one `<num>_task.md` per task (approval-gated). |
| [`execute-task`](skills/execute-task/SKILL.md) | Pick the next available task, implement it end to end, and tick its box in `tasks.md`. |

Run them in order — each step reads the previous step's output:

```
create-prd       →  tasks/prd-<feature>/prd.md        # what + why (asks clarifying questions first)
create-techspec  →  tasks/prd-<feature>/techspec.md   # how: architecture + decisions
create-tasks     →  tasks/prd-<feature>/tasks.md      # ordered checklist + one <num>_task.md per task
execute-task                                          # implements the next task, then ticks its box
```

Install the whole pipeline at once:

```bash
npx skills add robsonoliveiradacosta/agent-skills \
  --skill create-prd --skill create-techspec --skill create-tasks --skill execute-task
```

> Use this when you want a heavier, document-first paper trail. For a lighter in-repo flow, prefer the spec-driven skills above.

### Docs & governance

| Skill | Description |
| --- | --- |
| [`architecture-decision-records`](skills/architecture-decision-records/SKILL.md) | Create and maintain ADRs for significant Quarkus/Postgres/infra decisions. |
| [`commit`](skills/commit/SKILL.md) | Create a concise git commit with a one-line message (no body, no trailers, no AI attribution). |

## Adding a skill

Create a directory under `skills/` with a `SKILL.md` file:

```
skills/<skill-name>/SKILL.md
```

```markdown
---
name: <skill-name>
description: What this skill does and when to use it.
---

# <skill-name>

Instructions for the agent...
```

Only `name` and `description` are required in the frontmatter. Keep the body free of agent-specific tools or paths so the skill stays portable.
