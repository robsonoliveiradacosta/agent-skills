#!/usr/bin/env bash
#
# Install the third-party Agent Skills I use across projects.
# See external-skills.md for what each skill does.
#
#   ./setup-skills.sh            # machine setup + global skills (run once per machine)
#   ./setup-skills.sh --angular  # add the Angular dev skill to the CURRENT project
#
set -euo pipefail

# ---- prerequisites ------------------------------------------------------------
# Fail early with a clear message instead of blowing up mid-install.
for bin in node npm npx; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "✗ '$bin' not found. Install Node.js first." >&2
    echo "  macOS: 'brew install node' or use nvm (https://github.com/nvm-sh/nvm)." >&2
    echo "  Other: https://nodejs.org" >&2
    exit 1
  fi
done

# non-interactive skills CLI (auto-installs the `skills` package via npx --yes)
add() { npx --yes skills add -y "$@"; }

# ---- per-project mode ---------------------------------------------------------
# Angular skills are project-type specific, so they go per-project, not global.
if [[ "${1:-}" == "--angular" ]]; then
  add https://github.com/angular/skills --skill angular-developer
  # Only when scaffolding a brand-new app (otherwise it just clutters the skill list):
  # add https://github.com/angular/skills --skill angular-new-app
  echo "✓ angular-developer added to $(pwd)"
  exit 0
fi

# ---- 1) one-time machine binary (agent-browser CLI) ---------------------------
# The skill drives this CLI; without the binary it can't do anything.
if ! command -v agent-browser >/dev/null 2>&1; then
  echo "→ installing agent-browser CLI (global, once per machine)"
  npm i -g agent-browser
  agent-browser install
else
  echo "✓ agent-browser CLI already installed"
fi

# ---- 2) general-purpose skills → global (-g), available in every project -------
add -g https://github.com/anthropics/skills --skill frontend-design
add -g https://github.com/vercel-labs/agent-skills --skill web-design-guidelines
add -g https://github.com/nextlevelbuilder/ui-ux-pro-max-skill --skill ui-ux-pro-max
add -g https://github.com/vercel-labs/agent-browser --skill agent-browser
add -g https://github.com/obra/superpowers --skill brainstorming
add -g https://github.com/obra/superpowers --skill writing-plans

echo
echo "✓ Machine + global skills ready."
echo "  Inside an Angular project, run:  ./setup-skills.sh --angular"
