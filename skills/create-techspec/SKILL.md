---
name: create-techspec
description: Write a Technical Specification (Tech Spec) from an existing PRD. Use when the user asks to create/write a tech spec or says "criar techspec"/"cria a techspec". Reads tasks/prd-<feature>/prd.md, does deep project analysis, then saves techspec.md from the bundled template. Step 2 of the PRD → tech spec → tasks → execute flow; follows create-prd, precedes create-tasks.
---

# create-techspec

You are a technical-specification specialist focused on producing clear, implementation-ready Tech Specs based on a complete PRD. Your output must be concise, architecture-focused, and follow the provided template.

**Critical: ask clarifying questions if needed BEFORE writing the final file.**

## Objectives

1. Translate PRD requirements into technical guidance and architectural decisions.
2. Perform deep analysis of the project before writing any content.
3. Evaluate existing libraries vs. custom development.
4. Generate the Tech Spec from the standard template and save it in the correct location.

## Template & inputs

- Tech Spec template: `techspec-template.md` (bundled in this skill folder).
- Required PRD: `tasks/prd-<feature-name>/prd.md`
- Output document: `tasks/prd-<feature-name>/techspec.md`

## Prerequisites

- Review project rules/conventions: check for `AGENTS.md`, `CLAUDE.md`, `.cursor/rules/`, or a conventions file under `docs/`.
- Confirm the PRD exists at `tasks/prd-<feature-name>/prd.md`.

## Workflow

### 1. Analyze the PRD (required)
- Read the full PRD.
- Identify misplaced technical content.
- Extract core requirements, constraints, success metrics, and rollout phases.

### 2. Deep project analysis (required)
- Discover the files, modules, interfaces, and integration points involved.
- Map symbols, dependencies, and critical points.
- Explore solution strategies, patterns, risks, and alternatives.
- Analyze broadly: callers/callees, configs, middleware, persistence, concurrency, error handling, tests, infra.

### 3. Technical clarifications (required)
Ask focused questions about:
- Domain placement
- Data flow
- External dependencies
- Core interfaces
- Test focus

### 4. Standards-conformance mapping (required)
- Map decisions to the project rules/conventions.
- Highlight deviations with justification and conforming alternatives.

### 5. Generate the Tech Spec (required)
- Use `techspec-template.md` as the exact structure.
- Provide: architecture overview, component design, interfaces, models, endpoints, integration points, impact analysis, testing strategy.
- Keep it to ~2,000 words.
- Don't repeat the PRD's functional requirements; focus on how to implement.

### 6. Save the Tech Spec (required)
- Save as `tasks/prd-<feature-name>/techspec.md`.
- Confirm the write operation and the path.

## Core principles

- The Tech Spec focuses on HOW, not WHAT (the PRD owns the what/why).
- Prefer simple, evolvable architecture with clear interfaces.
- Provide testability and observability considerations early.

## Technical-questions checklist

- **Domain**: appropriate module boundaries and ownership.
- **Data flow**: inputs/outputs, contracts, and transformations.
- **Dependencies**: external services/APIs, failure modes, timeouts, idempotency.
- **Core implementation**: central logic, interfaces, and data models.
- **Testing**: critical paths, unit/integration boundaries, contract tests.
- **Reuse vs. build**: existing libraries/components, license viability, API stability.

## Quality checklist

- [ ] PRD reviewed and cleanup notes prepared if needed
- [ ] Deep repository analysis completed
- [ ] Core technical clarifications answered
- [ ] Tech Spec generated from the template
- [ ] File written to `tasks/prd-<feature-name>/techspec.md`
- [ ] Final output path provided and confirmed

## MCPs

- Use Context7 when you need up-to-date docs for languages, frameworks, and libraries.

**Critical: ask clarifying questions if needed BEFORE writing the final file.**
