# Skills I install in projects

Curated third-party Agent Skills I usually add on top of this repo's own skills.
Everything installs with the [`skills` CLI](https://github.com/vercel-labs/skills)
(`npx skills add …`) — except `agent-browser`, which also needs a companion binary.

Add `-g` to install globally (`~/.<agent>/skills/`) instead of per-project, or
`-a <agent>` to target a single agent (e.g. `-a claude-code`, `-a cursor`).

> Descriptions below are taken from each skill's real `SKILL.md` frontmatter.

## Quick install

The fastest path is the bundled script:

```bash
./setup-skills.sh            # machine setup + global skills (run once per machine)
./setup-skills.sh --angular  # add the Angular dev skill to the CURRENT project
```

It splits the install into two levels, because two of these don't fit the plain
`npx skills add --skill …` pattern:

- **`agent-browser`** needs a global CLI binary — that's **one-time machine setup**, not per-project.
- **`angular/skills`** with no `--skill` installs *both* Angular skills; we pin `angular-developer` and keep it **per-project** (it's project-type specific).

Everything else is general-purpose, so it goes **global** (`-g`) once and works in every project.

### Manual equivalent

```bash
# 1) one-time machine binary (agent-browser CLI)
command -v agent-browser >/dev/null || { npm i -g agent-browser && agent-browser install; }

# 2) general-purpose skills → global (-g), once per machine
npx skills add -g https://github.com/anthropics/skills --skill frontend-design
npx skills add -g https://github.com/vercel-labs/agent-skills --skill web-design-guidelines
npx skills add -g https://github.com/nextlevelbuilder/ui-ux-pro-max-skill --skill ui-ux-pro-max
npx skills add -g https://github.com/vercel-labs/agent-browser --skill agent-browser
npx skills add -g https://github.com/obra/superpowers --skill brainstorming
npx skills add -g https://github.com/obra/superpowers --skill writing-plans

# 3) project-type specific → per project
npx skills add https://github.com/angular/skills --skill angular-developer
# npx skills add https://github.com/angular/skills --skill angular-new-app   # only when scaffolding a new app
```

## Catalog

### Frontend / UI / design

- **`frontend-design`** — Create distinctive, production-grade frontend interfaces (web components, pages, dashboards, artifacts, React/HTML/CSS) with high design quality that avoids generic "AI slop" aesthetics.
  Source: [anthropics/skills](https://github.com/anthropics/skills)
  ```bash
  npx skills add https://github.com/anthropics/skills --skill frontend-design
  ```

- **`web-design-guidelines`** — Reviews/audits existing UI code for Web Interface Guidelines compliance. Triggers: "review my UI", "check accessibility", "audit design", "review UX". (Takes a `<file-or-pattern>`.)
  Source: [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills)
  ```bash
  npx skills add https://github.com/vercel-labs/agent-skills --skill web-design-guidelines
  ```

- **`ui-ux-pro-max`** — UI/UX design intelligence for web and mobile: 50+ styles, 161 color palettes, 57 font pairings, 99 UX guidelines, and 25 chart types across 10 stacks (React, Next.js, Vue, Svelte, SwiftUI, React Native, Flutter, Tailwind, shadcn/ui, HTML/CSS). Plan, build, review, fix, and optimize UI/UX code.
  Source: [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill)
  ```bash
  npx skills add https://github.com/nextlevelbuilder/ui-ux-pro-max-skill --skill ui-ux-pro-max
  ```

### Angular

The repo has two skills. Running `npx skills add https://github.com/angular/skills`
with no `--skill` installs **both**, so pin the one you want:

- **`angular-developer`** — Generates Angular code and gives architectural guidance: reactivity (signals, `linkedSignal`, `resource`), forms, dependency injection, routing, SSR, accessibility (ARIA), animations, styling (component styles, Tailwind), testing, and CLI tooling. *(install this one by default)*
- **`angular-new-app`** — Creates a new Angular app via the Angular CLI, with guidelines for a modern app setup. *(only when scaffolding a brand-new app)*

Source: [angular/skills](https://github.com/angular/skills)
```bash
npx skills add https://github.com/angular/skills --skill angular-developer
# npx skills add https://github.com/angular/skills --skill angular-new-app   # new app only
```

### Browser automation

- **`agent-browser`** — Browser-automation CLI for AI agents: navigate pages, fill forms, click, screenshot, scrape data, and test web apps (exploratory testing, QA, dogfooding). Also drives Electron apps (VS Code, Slack, Discord, Figma, Notion), runs in Vercel Sandbox microVMs, and AWS Bedrock AgentCore browsers. Two-step install: the global binary first, then the skill.
  Source: [vercel-labs/agent-browser](https://github.com/vercel-labs/agent-browser)
  ```bash
  npm i -g agent-browser && agent-browser install
  npx skills add https://github.com/vercel-labs/agent-browser --skill agent-browser
  ```

### Planning & thinking

From [obra/superpowers](https://github.com/obra/superpowers):

- **`brainstorming`** — Use *before* any creative work (new features, components, behavior changes): explores user intent, requirements, and design before implementation.
  ```bash
  npx skills add https://github.com/obra/superpowers --skill brainstorming
  ```

- **`writing-plans`** — Use when you have a spec or requirements for a multi-step task, before touching code: turns it into a concrete plan.
  ```bash
  npx skills add https://github.com/obra/superpowers --skill writing-plans
  ```
