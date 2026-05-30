---
name: spec-tasks
description: "Break a spec.md + plan.md into an ordered, atomic tasks.md checklist that spec-implement can execute one task at a time. Each task has an ID (T01..), title, files touched, the skill to invoke, validation step, and depends-on chain. Use after spec-plan, when the user says \"break the plan into tasks\", \"/spec-tasks NNN\", or \"vamos quebrar isso em tarefas\". Third step of the spec-create → spec-plan → spec-tasks → spec-implement flow."
---

# spec-tasks

Translate a `plan.md` (file lists, skills, risks) into a sequenced, executable checklist. The output is `specs/NNN-<slug>/tasks.md` — the working document that `spec-implement` reads, executes, and ticks off.

## When to invoke

- "Break spec 003 into tasks"
- "Generate the task list for the favorites plan"
- After `spec-plan`, before `spec-implement`.
- Refuse if `plan.md` doesn't exist for the referenced spec — point at `spec-plan` first.

## Inputs to collect

| Input | Notes |
|---|---|
| Spec ID | `NNN` (3-digit) — defaults to the latest `specs/NNN-*/` |
| Granularity | "fine" (one file = one task) or "coarse" (one slice = one task) — default coarse |

Coarse is the right default for most Quarkus features because skills like `add-crud-resource` already generate multiple files atomically.

## Workflow

1. Read `specs/NNN-<slug>/spec.md` and `specs/NNN-<slug>/plan.md`. Refuse if either is missing.
2. From the plan's "Files to create / modify" + "Skills to invoke" + "Test plan" + "Companion-agent reviews", produce ordered tasks.
3. Each task has the fields in the template below — be specific, no vague verbs ("update stuff", "fix things").
4. Order tasks so each is **runnable in isolation** given the previous ones are done. Migrations always come first; tests come after the code they verify; review agents come last.
5. Write `tasks.md`. Echo the path and the count of tasks back to the user.

## Sequencing rules

- **T01 always = the Flyway migration** (if any). Schema-first so the entity in T02 compiles against a real table.
- **Entity → Repository → Service → Resource** order — each compiles before the next.
- **DTOs** can be a single task or attached to the resource task; coarse default attaches.
- **Tests** come after the code they cover, never before. (TDD is fine but this scaffold is post-implementation tests.)
- **Companion-agent reviews** (security, migration-safety, …) are the **last block**, one task per agent. They are gates, not implementation steps.

## Template for `tasks.md`

```markdown
# Tasks NNN — <Feature Title>

- **Spec:** [./spec.md](./spec.md)
- **Plan:** [./plan.md](./plan.md)
- **Status:** not started
- **Updated:** YYYY-MM-DD

Run with `spec-implement NNN` (next pending task) or `spec-implement NNN T05`
(specific task). Each task is checked off in place when completed.

## Implementation

- [ ] **T01** — Add Flyway migration `V<n>__<name>.sql`
  - **Files:** `src/main/resources/db/migration/V<n>__<name>.sql`
  - **Skill:** `add-flyway-migration`
  - **Validation:** `./mvnw test -Dtest=NoneSuchClass` (compile-only check) — or skip; T08 will run the schema.
  - **Depends on:** —

- [ ] **T02** — Create `<Entity>` JPA entity
  - **Files:** `src/main/java/<pkg>/entity/<Entity>.java`
  - **Skill:** `add-crud-resource` (entity portion only)
  - **Validation:** `./mvnw compile`
  - **Depends on:** T01

- [ ] **T03** — Create `<Entity>Repository`
  - **Files:** `src/main/java/<pkg>/repository/<Entity>Repository.java`
  - **Skill:** `add-crud-resource` (repository portion)
  - **Validation:** `./mvnw compile`
  - **Depends on:** T02

- [ ] **T04** — Create request/response DTOs
  - **Files:** `dto/request/<Entity>Request.java`, `dto/response/<Entity>Response.java`
  - **Skill:** `add-crud-resource` (dto portion)
  - **Validation:** `./mvnw compile`
  - **Depends on:** T02

- [ ] **T05** — Create `<Entity>Service` with `@Transactional` writes
  - **Files:** `service/<Entity>Service.java`
  - **Skill:** `add-crud-resource` (service portion)
  - **Validation:** `./mvnw compile`
  - **Depends on:** T03, T04

- [ ] **T06** — Create `<Entity>Resource` with `@RolesAllowed` and OpenAPI annotations
  - **Files:** `resource/<Entity>Resource.java`
  - **Skill:** `add-crud-resource` (resource portion)
  - **Validation:** `./mvnw compile && ./mvnw quarkus:dev` smoke check (optional)
  - **Depends on:** T05

## Tests

- [ ] **T07** — REST Assured suite for `<Entity>Resource`
  - **Files:** `src/test/java/<pkg>/resource/<Entity>ResourceTest.java`
  - **Skill:** `rest-assured-api-suite` (or `add-crud-resource` test portion)
  - **Validation:** `./mvnw test -Dtest=<Entity>ResourceTest`
  - **Depends on:** T06

- [ ] **T08** — Mockito unit tests for `<Entity>Service`
  - **Files:** `src/test/java/<pkg>/service/<Entity>ServiceTest.java`
  - **Skill:** `quarkus-test-patterns`
  - **Validation:** `./mvnw test -Dtest=<Entity>ServiceTest`
  - **Depends on:** T05

## Reviews (gates before merge)

- [ ] **T09** — `migration-safety` agent review on V<n>
  - **Agent:** `migration-safety`
  - **Validation:** Agent reports no critical findings.
  - **Depends on:** T01

- [ ] **T10** — `security` agent review on `<Entity>Resource`
  - **Agent:** `security`
  - **Validation:** Agent reports no critical findings.
  - **Depends on:** T06

- [ ] **T11** — `testing` agent — confirm coverage matches plan's test plan
  - **Agent:** `testing`
  - **Validation:** Agent confirms no missing tests.
  - **Depends on:** T07, T08

## Notes

- A failed validation pauses execution; the user must decide to fix and retry, skip, or abort.
- Marking `[x]` requires the validation step to have passed.
- New tasks discovered during execution are appended (e.g. `T12`, `T13`); never renumbered.
```

## After writing

Tell the user:
- Path to `tasks.md`.
- Number of tasks (e.g. "11 tasks: 6 implementation, 2 tests, 3 reviews").
- Next step: `spec-implement NNN` to start executing, or `spec-implement NNN T01` to run a specific task.

## Anti-patterns to refuse

- Generating tasks without a `plan.md` — refuse and run `spec-plan` first.
- Tasks that bundle review + implementation ("implement and verify security") — keep them separate; reviews are gates.
- Skipping validation steps to "move faster" — the validation is what lets `spec-implement` know whether to tick the box.
- Renumbering tasks when inserting new ones — always append to keep IDs stable across edits.
- Producing a single mega-task ("implement the whole thing") — defeats the point. Break it down even if each task is small.
