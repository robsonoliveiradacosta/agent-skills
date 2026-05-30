# agent-skills

A collection of agent-agnostic [Agent Skills](https://github.com/vercel-labs/skills) — reusable instruction sets in the universal `SKILL.md` format. Install them into Claude Code, Cursor, opencode, Codex, Windsurf, and 40+ other agents with the `skills` CLI.

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

| Skill | Description |
| --- | --- |
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
