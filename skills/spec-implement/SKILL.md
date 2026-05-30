---
name: spec-implement
description: "Execute the next pending task (or a named task ID) from a spec's tasks.md, invoking the named skill or agent, running the validation step, and ticking the checkbox in place when it passes. Stops on validation failure and reports back. Use after spec-tasks, when the user says \"implement spec NNN\", \"run T05\", \"continue the spec\", \"executar a próxima task\". Final step of the spec-create → spec-plan → spec-tasks → spec-implement flow."
---

# spec-implement

Execute one task at a time from `specs/NNN-<slug>/tasks.md`. The skill is the **runner**; the actual implementation is delegated to the skill or agent named in the task. After each task, run its validation, update the checkbox, and either continue or stop.

## When to invoke

- "Implement spec 003"
- "Run the next task in spec 003"
- "Execute T05 from spec 003"
- "Continue the favorites spec"
- After `spec-tasks`, or to resume work on a partially-completed spec.

## Inputs to collect

| Input | Notes |
|---|---|
| Spec ID | `NNN`, defaults to most recent `specs/NNN-*/` |
| Task ID | Optional — `T05`. If omitted, runs the next unchecked task. |
| Mode | `single` (run one task and stop — default) or `auto` (run all remaining until failure or done) |

Default to `single`. Switch to `auto` only if the user asks ("implement everything", "run all remaining tasks").

## Workflow

1. Read `specs/NNN-<slug>/tasks.md`. Refuse if missing — point at `spec-tasks`.
2. Identify the target task:
   - If task ID given, find it and confirm it's unchecked.
   - Otherwise, pick the first `[ ]` task whose dependencies (from "Depends on") are all `[x]`.
   - If nothing is runnable (all done, or all blocked), report and stop.
3. Echo the task to the user **before executing**:
   ```
   → T05: Create <Entity>Service with @Transactional writes
     Files: service/<Entity>Service.java
     Skill: add-crud-resource (service portion)
     Validation: ./mvnw compile
   ```
4. Execute:
   - **If task names a skill:** invoke that skill with task-specific scope (e.g. only the service portion of `add-crud-resource`).
   - **If task names an agent:** call the `Agent` tool with that agent type, hand it the spec/plan as context.
   - **If neither:** make the edits inline based on the task's "Files" field and the plan.
5. Run the validation step. Capture pass/fail and any error output.
6. **If validation passes:** flip `[ ]` → `[x]` in `tasks.md`, append a `→ done YYYY-MM-DD HH:MM` suffix to the task title.
7. **If validation fails:** leave the box unchecked, append a `→ failed: <one-line reason>` note to the task, and stop. Show the user the failure and ask whether to retry, fix manually, or skip.
8. In `auto` mode, repeat from step 2 until done or a failure stops the loop.

## Updating tasks.md

The checkbox flip happens in place via `Edit`:

- **Before:** `- [ ] **T05** — Create ...`
- **After (success):** `- [x] **T05** — Create ... → done 2026-05-15 14:30`
- **After (failure):** `- [ ] **T05** — Create ... → failed: validation step \`./mvnw compile\` exited 1`

Also update the spec header:

- `Status: not started` → `Status: in progress` after first task completes
- → `Status: completed` after the last unchecked task is checked

## Report after each task

Keep it terse — the user reads the diff:

```
T05 → done. Service compiled.
Next: T06 — Create <Entity>Resource (depends on T05).
Run `spec-implement NNN` to continue, or stop here.
```

In `auto` mode, only report at the end (or on failure).

## Anti-patterns to refuse

- Running a task whose dependencies aren't `[x]` — explain why and suggest the right next task.
- Skipping the validation step. Even a "trivial" task gets validated; that's how the box gets ticked honestly.
- Marking `[x]` when validation failed. Never lie to the checklist.
- Editing `tasks.md` to renumber, reorder, or delete tasks. Append-only; if scope grew, add `T12`, `T13`, …
- Bundling multiple tasks into one execution to "move faster" in single mode. The user chose single for a reason.
- Continuing after a failure in `auto` mode. The whole point of the gate is that downstream tasks usually depend on the failed one's output.

## Recovery

If a task partially modified files and then failed validation:

1. Report exactly which files were touched.
2. Do **not** auto-revert — let the user decide. Often the partial change is correct and the validation is the issue (e.g. unrelated test failure).
3. Suggest: "Fix the validation issue, then `spec-implement NNN T05` to retry — the task will re-execute the skill from scratch, so any in-progress state will be overwritten."

## When the spec is done

When all tasks are `[x]`:

1. Set the spec header `Status: completed`.
2. Suggest a final review pass: any of `release-manager`, `api-governance`, `privacy-compliance` agents that the plan flagged but isn't already in the task list.
3. Suggest the commit message convention this repo uses (see git log) — but **do not commit** unless the user explicitly asks.
