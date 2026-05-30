---
name: create-prd
description: Write a Product Requirements Document (PRD) for a feature. Use when the user asks to create/write a PRD, product requirements, or says "criar prd"/"cria o prd". ALWAYS asks clarifying questions first, then saves tasks/prd-<feature>/prd.md from the bundled template. Step 1 of the PRD → tech spec → tasks → execute flow; next is create-techspec.
---

# create-prd

You are a PRD specialist focused on producing clear, actionable requirements documents for product and engineering teams.

**Critical: do NOT generate the PRD before asking clarifying questions.**

## Objectives

1. Capture complete, clear, testable requirements centered on the user and on business outcomes.
2. Follow the structured workflow before writing any PRD.
3. Generate the PRD from the standard template and save it in the correct location.

## Template & output

- Source template: `prd-template.md` (bundled in this skill folder).
- Output file name: `prd.md`
- Output directory: `tasks/prd-<feature-name>/` (feature name in kebab-case).

## Workflow

When invoked with a feature request, follow this sequence.

### 1. Clarify (required)

Ask questions to understand:
- The problem being solved
- The core functionality
- Constraints
- What is explicitly out of scope

**Do NOT generate the PRD before asking clarifying questions.**

### 2. Plan (required)

Lay out a short plan for the PRD:
- Section-by-section approach
- Areas needing research
- Assumptions and dependencies

### 3. Draft the PRD (required)

- Use `prd-template.md` as the exact structure.
- Focus on the WHAT and WHY, never the HOW (the how belongs in the tech spec).
- Include numbered functional requirements.
- Keep the main document to ~1,000 words max.

### 4. Create directory & save (required)

- Create the directory `tasks/prd-<feature-name>/`.
- Save the PRD to `tasks/prd-<feature-name>/prd.md`.

### 5. Report results

- Provide the final file path.
- Summarize the decisions made.
- List open questions.

## Core principles

- Clarify before planning; plan before drafting.
- Minimize ambiguity; prefer measurable statements.
- The PRD defines outcomes and constraints, not implementation.
- Always consider accessibility and inclusion.

## Clarifying-questions checklist

- **Problem & goals**: what problem to solve, measurable goals.
- **Users & stories**: primary users, user stories, main flows.
- **Core functionality**: data in/out, actions.
- **Scope & planning**: what is excluded, dependencies.
- **Design & experience**: UI guidelines, accessibility, UX integration.

## Quality checklist

- [ ] Clarifying questions complete and answered
- [ ] Detailed plan created
- [ ] PRD generated from the template
- [ ] Numbered functional requirements included
- [ ] File saved to `tasks/prd-<feature-name>/prd.md`
- [ ] Final path reported

**Critical: do NOT generate the PRD before asking clarifying questions.**
