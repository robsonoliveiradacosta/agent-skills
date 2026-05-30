---
name: spec-create
description: "Start a spec-driven feature by writing specs/NNN-feature-slug/spec.md — captures problem, goals, non-goals, user-facing behavior, acceptance criteria, and open questions. Use whenever the user says \"create a spec for X\", \"start a feature X\", \"criar uma spec\", \"vamos planejar X\", or wants to begin work on a non-trivial change before code is written. First step of the spec-create → spec-plan → spec-tasks → spec-implement flow."
---

# spec-create

Capture **what** to build and **why** in a single source-of-truth file before any architecture or code. The spec is consumed by `spec-plan` (architecture), `spec-tasks` (work breakdown), and `spec-implement` (execution).

## When to invoke

- "Create a spec for adding playlists"
- "Vamos começar uma feature de favoritos"
- "Start a spec for the bulk import endpoint"
- Any non-trivial change touching ≥2 layers — refuse for one-file edits and tell the user to make the change directly.

## Inputs to collect

Spec-driven development is **interview-driven** — the value is in the
conversation that happens before the file is written. Do **not** dump every
question in one message; run focused rounds and reflect understanding back
between them. A vague spec leads to a vague plan, which leads to wasted
implementation.

| Input | Notes |
|---|---|
| Feature name | Short, kebab-case-friendly (e.g. `user-favorites`) |
| Problem statement | What pain or opportunity drives this? Why now? |
| Goals | 1-3 measurable outcomes |
| Non-goals | What you explicitly will NOT do in this iteration |
| User-facing behavior | API surface (endpoints, payloads), or domain behavior change |
| Constraints | Existing entities to reuse, roles required, perf/SLA, deadline |
| Out of scope | Adjacent work that's tempting but separate |

## Workflow

1. **Round 0 — pitch**: read the user's initial request. If it's a single
   sentence ("create a spec for X"), don't push for everything at once;
   continue to Round 1.
2. **Round 1 — problem & scope**. Ask 2-3 focused questions about *why*
   this and *who* feels the pain. Use the `AskUserQuestion` tool when the
   answer is one of a few clear options (e.g. read-only vs read-write,
   user-facing vs admin-only). Open text otherwise.
3. **Round 2 — user-facing behavior**. Now that the *why* is clear, ask
   about the *what*: endpoints, request/response shape, key fields, edge
   cases the user has already thought about. Reflect back a draft of the
   API surface in plain text and ask "is this right?" before continuing.
4. **Round 3 — constraints**. Ask about roles required (read/write), reuse
   of existing entities, performance budget, deadline, dependencies on
   other in-flight work. Skip questions whose answer is obvious from the
   project (e.g. "always Flyway-owned schema" — don't ask).
5. **Library / framework grounding (context7)**. If the feature mentions
   any library, framework, SDK, API, or CLI tool *not* already established
   in `CLAUDE.md`, call the `mcp__context7__resolve-library-id` tool with
   the name to find the canonical ID, then `mcp__context7__query-docs`
   with a topic-focused query (e.g. `"Quarkus 3.31 @Scheduled cron syntax"`)
   to ground the spec in *current* docs rather than your training data.
   Note in the spec what was confirmed against current docs and what
   version was assumed.
   - **If context7 is not installed** (the `mcp__context7__*` tools aren't
     available in this session): don't block — proceed using training
     data, but record `context7: unavailable` in the `## Library
     references` section so the user knows the spec wasn't doc-grounded.
     Once, at the end of the interview, point the user at `AGENTS.md`
     §"MCP servers (context7)" for the install one-liner so future specs
     can be grounded.
6. **Recap & confirm**. Before writing, summarize the spec in 5-8 bullet
   points and ask: "Anything missing or wrong?" Wait for the OK.
7. **Write**. List existing `specs/` directory, pick the **next**
   zero-padded 3-digit number (`001`, `002`, …), slugify the feature name
   (lowercase, hyphens, no diacritics), and create
   `specs/NNN-<slug>/spec.md` using the template below. Include a
   `## Library references` section if context7 was used.
8. Echo the path back to the user and the next step (`spec-plan NNN`).

### When to skip rounds

- The user provides a *complete* brief in one message (problem + behavior
  + constraints + AC). Then summarize and skip to step 6.
- The feature is a small extension of an existing pattern in this repo
  (e.g. "add `description` field to Album"). Skip to a single confirmation
  round and write — you don't need a 3-round interview for a one-field
  change. (And honestly, that probably doesn't need a spec at all — push
  back and suggest a direct edit.)

### Round style

- One topic per round, max 4 questions per round.
- Use `AskUserQuestion` for closed choices; plain text for open-ended.
- Always reflect what you heard before asking the next round — this is
  where misunderstandings surface cheaply.
- Stop the interview the moment requirements are clear. Don't ask for the
  sake of asking.

## Numbering

- Find max `NNN` across `specs/NNN-*/` directories. Use **decimal**, not lexical, comparison.
- Never reuse a number. If a spec was abandoned, leave the directory or move it under `specs/_archive/`.

## Template

```markdown
# Spec NNN — <Feature Title>

- **Status:** draft
- **Created:** YYYY-MM-DD
- **Owner:** <user>
- **Slug:** `NNN-<slug>`

## Problem

<2-4 sentences. What's broken or missing today? Who feels the pain? What's
the cost of not doing this?>

## Goals

- <Outcome 1, measurable if possible>
- <Outcome 2>

## Non-goals

- <Thing this spec deliberately doesn't address>

## User-facing behavior

<API endpoints, request/response shapes, domain events, UI changes — whatever
the consumer of this feature actually sees. Keep it concrete.>

### Example interaction

```http
POST /v1/<resource>
Authorization: Bearer <jwt>
Content-Type: application/json

{ "field": "value" }

→ 201 Created
{ "id": 42, "field": "value" }
```

## Acceptance criteria

- [ ] <Concrete, testable condition 1>
- [ ] <Concrete, testable condition 2>
- [ ] All new endpoints documented in OpenAPI (`@Operation`, `@APIResponse`).
- [ ] Tests cover happy path + at least one auth/validation failure path.

## Constraints & assumptions

- **Reuses:** <existing entities/services/skills>
- **Roles:** read = `<USER|ADMIN>`, write = `<ADMIN>`
- **Performance:** <p95 latency, throughput, payload size — or "no specific budget">
- **Deadline:** <date or "none">

## Out of scope

- <Adjacent feature that should be a separate spec>

## Open questions

- [ ] <Anything still ambiguous — flag for plan stage>

## Library references

<Only present if context7 was queried during the interview. List each
library/topic with the version assumed and the key constraint that came
out of the docs.>

- **<library>** (version <X.Y>) — confirmed via context7 on YYYY-MM-DD.
  - <Key constraint or capability that shapes this spec>

## References

- Related specs: <NNN, NNN>
- Tickets / chat threads: <links>
```

## After writing

Tell the user:
- Path to the new spec.
- Any open questions you couldn't resolve from inputs.
- Next step: `spec-plan NNN` to produce the architectural plan.

## Anti-patterns to refuse

- Writing a spec without acceptance criteria — refuse and ask the user for them.
- Writing a "spec" that's actually a plan (file lists, package names) — those belong in `plan.md`. Push back and capture only intent here.
- Editing a spec that's already in `status: implemented` — start a new spec for follow-up work, link to it via References.
- Creating spec files outside `specs/NNN-<slug>/` — the directory layout is what `spec-plan` and `spec-tasks` rely on to find sibling files.
- Dumping every interview question in a single message. Run focused rounds and reflect understanding back between them.
- Writing a spec that mentions a library/framework/API/SDK without first checking current docs via context7. Your training data may be stale; the spec should be grounded in the version actually in use.
- Skipping the "recap & confirm" step. The user always gets a chance to correct the summary before the file is written.

## Notes for this project

- The `specs/` directory is committed to the repo so the spec lives next to the code that implements it. Don't add it to `.gitignore`.
- For Quarkus features, the typical scope hint to capture is which layer is touched: resource only, full slice (resource + service + repository + entity + migration), background job, integration with external API, or cross-cutting concern (auth, observability, rate limit).
