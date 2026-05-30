---
name: commit
description: Create a concise git commit with a one-line message. Use when the user asks to commit, "commita", "faz o commit", or save staged/unstaged changes to git. Skip for amends, force-pushes, or pushes.
---

# commit

Minimum-token commit. No body, no trailers, no AI attribution.

## Steps

1. Run `git status --short` and `git diff --stat` in parallel.
2. Compose ONE subject line, ≤ 60 chars, imperative mood, no trailing period.
3. `git add <specific files>` — never `-A` or `.` when unrelated untracked files exist.
4. `git commit -m "<subject>"` (single `-m`, plain string — no HEREDOC needed for one-liners).
5. `git log -1 --oneline` to confirm.

## Hard rules

- The message must contain NO AI/model/tool name and NO `Co-Authored-By` trailer.
- No `--amend`, no `--no-verify`, no `git push`.
- If the diff spans unrelated changes, ask the user to scope before committing.

## Subject style

`add X`, `fix Y`, `remove Z`, `update W`, `rename A to B`. Drop articles and "this commit" boilerplate. One concept per commit.
