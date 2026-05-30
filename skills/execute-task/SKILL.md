---
name: execute-task
description: Pick the next available task from a generated task list and implement it end to end. Use when the user asks to execute/implement the next task or says "executar task"/"executa a task"/"implementa a próxima task". Reads tasks/prd-<feature>/{prd.md,techspec.md,tasks.md} plus the task file, implements it, then ticks the box in tasks.md. Step 4 of the PRD → tech spec → tasks → execute flow; follows create-tasks.
---

# execute-task

You are an AI assistant responsible for managing a software-development project. Your task is to identify the next available task, do the necessary setup, and get ready to start the work.

## File locations

- PRD: `tasks/prd-<feature-name>/prd.md`
- Tech Spec: `tasks/prd-<feature-name>/techspec.md`
- Tasks: `tasks/prd-<feature-name>/tasks.md`
- Project rules: check for `AGENTS.md`, `CLAUDE.md`, `.cursor/rules/`, or a conventions file under `docs/`.

## Steps

### 1. Pre-task setup
- Read the task definition.
- Review the PRD context.
- Check the tech-spec requirements.
- Understand dependencies on earlier tasks.

### 2. Task analysis
Consider:
- The task's primary objectives.
- How the task fits the project context.
- Alignment with project rules and standards.
- Possible solutions or approaches.

### 3. Task summary

```
Task ID: [ID or number]
Task Name: [Name or brief description]
PRD Context: [Key PRD points]
Tech Spec Requirements: [Key technical requirements]
Dependencies: [List of dependencies]
Primary Objectives: [Primary objectives]
Risks/Challenges: [Identified risks or challenges]
```

### 4. Approach plan

```
1. [First step]
2. [Second step]
3. [Additional steps as needed]
```

## Important notes

- Always verify against the PRD, tech spec, and task file.
- Implement proper solutions **without hacks/workarounds**.
- Follow all established project standards.

## Implementation

After providing the summary and approach, start implementing the task immediately:

- Run the necessary commands.
- Make code changes.
- Follow the project's established standards.
- Ensure all requirements are met.

**You MUST** start implementing right after the process above.

<critical>Use Context7 to consult documentation for the language, frameworks, and libraries involved in the implementation.</critical>

<critical>After completing the task, mark it complete in tasks.md.</critical>
