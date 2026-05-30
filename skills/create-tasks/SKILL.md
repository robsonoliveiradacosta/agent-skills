---
name: create-tasks
description: Break a PRD + Tech Spec into an ordered, dependency-aware task list with one file per task. Use when the user asks to create/generate tasks or says "criar tasks"/"gera as tasks". Reads tasks/prd-<feature>/{prd.md,techspec.md} and writes tasks.md plus N_task.md files from the bundled templates. ALWAYS shows the high-level task list for approval first. Step 3 of the PRD → tech spec → tasks → execute flow; follows create-techspec, precedes execute-task.
---

# create-tasks

You are an assistant specialized in software-project management. Your job is to create a detailed task list based on a PRD and a Technical Specification for a specific feature. Your plan must clearly separate sequential dependencies from tasks that can run in parallel.

## Prerequisites

The feature you work on is identified by its slug:

- Required PRD: `tasks/prd-<feature-name>/prd.md`
- Required Tech Spec: `tasks/prd-<feature-name>/techspec.md`

## Process

**Critical: BEFORE generating any file, show me the high-level task list for approval.**

1. **Analyze the PRD and Tech Spec**
   - Extract requirements and technical decisions.
   - Identify the main components.

2. **Generate the task structure**
   - Organize the sequencing.

3. **Generate individual task files**
   - Create one file per main task.
   - Detail subtasks and success criteria.

## Task-creation guidelines

- Group tasks by domain (e.g., agent, tool, flow, infra).
- Order tasks logically, with dependencies before dependents.
- Make each main task independently completable.
- Define clear scope and deliverables for each task.
- Include tests as subtasks within each main task.

## Output spec

### File locations
- Feature folder: `tasks/prd-<feature-name>/`
- Task-list template: `tasks-template.md` (bundled in this skill folder)
- Task list: `tasks/prd-<feature-name>/tasks.md`
- Per-task template: `task-template.md` (bundled in this skill folder)
- Individual tasks: `tasks/prd-<feature-name>/<num>_task.md`

### Task summary format (tasks.md)
- **Follow `tasks-template.md` strictly.**

### Individual task format (<num>_task.md)
- **Follow `task-template.md` strictly.**

## Final guidelines

- Assume the primary reader is a junior developer.
- For large features (>10 main tasks), suggest splitting into phases.
- Use X.0 for main tasks, X.Y for subtasks.
- Clearly indicate dependencies and mark parallel tasks.
- Suggest implementation phases.

After completing the analysis and generating all required files, present the results to the user and wait for confirmation before proceeding with implementation (`execute-task`).
