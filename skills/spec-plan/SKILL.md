---
name: spec-plan
description: "Turn a spec.md into a concrete architectural plan.md by delegating cross-file design to the architect agent — names files, packages, the next Flyway migration number, role annotations, transaction boundaries, and which companion skills (add-crud-resource, add-flyway-migration, etc) to invoke per phase. Use after spec-create, when the user says \"plan the spec\", \"design the implementation\", \"/spec-plan NNN\", or \"como vou implementar isso\". Second step of the spec-create → spec-plan → spec-tasks → spec-implement flow."
---

# spec-plan

Translate intent (`spec.md`) into a file-by-file implementation plan that respects this project's Quarkus + Panache + Flyway conventions. Output is `specs/NNN-<slug>/plan.md`.

## When to invoke

- "Plan spec 003"
- "Design the implementation for the favorites feature"
- After `spec-create`, before `spec-tasks`.
- Refuse if no `spec.md` exists for the referenced number — ask the user to run `spec-create` first.

## Inputs to collect

| Input | Notes |
|---|---|
| Spec ID | `NNN` (3-digit) — or "the latest" / "the most recent" |
| Open questions to resolve | Anything in spec's "Open questions" section that can be answered now |

If the user just says "plan the latest spec", read `specs/` and pick the highest-numbered directory. Confirm before proceeding.

## Workflow

1. Read `specs/NNN-<slug>/spec.md`. If it doesn't exist, refuse and point at `spec-create`.
2. Read `CLAUDE.md` (or `AGENTS.md`) for project conventions — package root, layered architecture, auth model, migration ownership.
3. Detect the next Flyway migration number by listing `src/main/resources/db/migration/V*.sql`.
4. Detect the Java package root by reading `entity/` directory.
5. **Library / framework grounding (context7)**. If `spec.md` has a
   `## Library references` section, re-confirm the relevant API surfaces
   are still current via `mcp__context7__query-docs` before planning. If
   the spec did NOT capture library references but the plan will rely on
   a Quarkus/Hibernate/Panache/etc API beyond what `CLAUDE.md` documents,
   query context7 now — for example `"Quarkus 3.31 @Scheduled cron syntax"`
   or `"Hibernate 6.4 @SoftDelete behavior"`. Stale plans waste cycles.
   - **If context7 is not installed**: proceed with training data and
     mention it once at the end (e.g. "context7 unavailable — Hibernate
     6.4 API assumed from training data; verify before merge"). Point
     the user at `AGENTS.md` §"MCP servers (context7)" for install.
6. Delegate cross-file design to the **`architect` agent** with a prompt that includes:
   - The full `spec.md` content
   - Project conventions summary
   - Next available migration number
   - Package root
   - Any context7-confirmed API constraints from step 5
   - Constraint: name files, packages, the migration number, role annotations, and which companion skills to invoke
7. Receive the architect's plan, write it into `plan.md` using the template below.
8. Surface unresolved questions back to the user — don't guess.

## Template for `plan.md`

```markdown
# Plan NNN — <Feature Title>

- **Spec:** [./spec.md](./spec.md)
- **Status:** draft
- **Updated:** YYYY-MM-DD

## Layered impact

| Layer | Action |
|---|---|
| Migration | <new V<n>__*.sql or "none"> |
| Entity | <new classes / modified classes> |
| Repository | <Panache methods to add> |
| Service | <new services / methods, transaction boundaries> |
| Resource | <new endpoints, paths, role annotations> |
| DTOs | <request / response records> |
| Tests | <REST Assured + Mockito + integration coverage> |
| Cross-cutting | <auth, rate limit, observability, websocket, scheduler — only if touched> |

## Files to create

- `src/main/resources/db/migration/V<n>__<name>.sql`
- `src/main/java/<pkg>/entity/<Entity>.java`
- `src/main/java/<pkg>/repository/<Entity>Repository.java`
- `src/main/java/<pkg>/service/<Entity>Service.java`
- `src/main/java/<pkg>/resource/<Entity>Resource.java`
- `src/main/java/<pkg>/dto/request/<Entity>Request.java`
- `src/main/java/<pkg>/dto/response/<Entity>Response.java`
- `src/test/java/<pkg>/resource/<Entity>ResourceTest.java`
- `src/test/java/<pkg>/service/<Entity>ServiceTest.java`

## Files to modify

- `<path>` — <why>

## Skills to invoke

In execution order. `spec-implement` will run these in `spec-tasks` order; this list maps tasks → skills.

1. `add-flyway-migration` — for the V<n> file
2. `add-crud-resource` — for the Entity slice
3. `add-jwt-auth` — only if a new role is introduced (rare)
4. `add-pagination` — if the listing endpoint expects >100 rows
5. `add-rate-limit` — already global; mention if a per-endpoint cap is needed
6. <other `add-*` skills as relevant>

## Roles & security

- Read endpoints: `@RolesAllowed({"USER","ADMIN"})`
- Write endpoints: `@RolesAllowed("ADMIN")`
- Anonymous access: <none, or list specific paths>
- New JWT claims required: <none / list>

## Transaction boundaries

- Service methods that write: `@Transactional` (REQUIRED — default)
- Read-only services: <`@Transactional(TxType.NEVER)` only if measured contention; otherwise omit>
- Cross-aggregate writes: <flag any case where one method spans two aggregate roots>

## Validation strategy

- Bean Validation annotations on request DTOs (`@NotBlank`, `@Size`, `@Pattern`).
- DB constraints encoded in the migration as the second line of defense.
- Negative tests for every required field.

## Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| <e.g. N+1 from new relationship> | medium | Use `JOIN FETCH` in repository finder |
| <e.g. rate limit bypass> | low | Confirm filter applies to new endpoints |

## Test plan

- **Unit (Mockito):** <list service methods to cover>
- **API (REST Assured):** <list endpoints to cover, including auth + validation failures>
- **Integration:** <only if external dependency — name the WireMock stub or Testcontainer resource>

## Companion-agent reviews to schedule

After implementation, before merge — invoke each as needed:

- `migration-safety` — if any migration was added
- `transaction-consistency` — if `@Transactional` placement is non-trivial
- `query-optimization` — if new repository finders or list endpoints
- `security` — for any new endpoint or role boundary
- `testing` — to confirm coverage matches the test plan above

## Open questions

- [ ] <Anything the architect couldn't resolve — flag for the user>
```

## After writing

Tell the user:
- Path to `plan.md`.
- Any open questions that need their input before `spec-tasks`.
- Next step: `spec-tasks NNN` to break the plan into ordered, atomic tasks.

## Anti-patterns to refuse

- Producing a plan without a corresponding `spec.md` — refuse and run `spec-create` first.
- Inventing file paths that don't match `CLAUDE.md` conventions — always use the detected package root and the actual `entity/` location.
- Picking a Flyway number without listing the migration directory — always re-read at plan time, the number may have moved since the spec was written.
- Producing a plan that mutates an already-applied migration. Always allocate the next free number.
- Skipping the `architect` agent for a multi-file feature — that agent embodies the cross-file design rules. The exception is single-layer changes (e.g. "add a field to existing DTO") where architect would refuse anyway.
- Planning around a library API from memory when the spec touches a non-trivial Quarkus/Hibernate/Panache feature. Query context7 first; the cost of one doc lookup beats the cost of a wrong file in `plan.md`.
