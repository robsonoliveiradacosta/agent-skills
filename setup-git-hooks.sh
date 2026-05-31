#!/usr/bin/env bash
#
# Install the global git commit-msg hook that strips AI attribution
# (Co-Authored-By: Claude, "Generated with Claude Code") from every commit.
# Run once per machine.
#
#   ./setup-git-hooks.sh
#
# The hook is enforced by git itself, so it applies no matter who writes the
# message (model, skill, or you in the terminal). Reverting it later:
#   git config --global --unset core.hooksPath
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_HOOK="$SCRIPT_DIR/git-hooks/commit-msg"

# Honor XDG; default to ~/.config/git/hooks (git's conventional global location).
HOOKS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/git/hooks"

if [[ ! -f "$SRC_HOOK" ]]; then
  echo "✗ Hook source not found at $SRC_HOOK" >&2
  exit 1
fi

# ---- warn if a global core.hooksPath is already set elsewhere ------------------
EXISTING="$(git config --global core.hooksPath || true)"
if [[ -n "$EXISTING" && "$EXISTING" != "$HOOKS_DIR" ]]; then
  echo "! global core.hooksPath is already set to: $EXISTING"
  echo "  This script will repoint it to: $HOOKS_DIR"
  echo "  Move any hooks you rely on into that directory first, then re-run."
  read -r -p "  Continue? [y/N] " ans
  [[ "$ans" == [yY] ]] || { echo "aborted."; exit 1; }
fi

# ---- install ------------------------------------------------------------------
mkdir -p "$HOOKS_DIR"
install -m 0755 "$SRC_HOOK" "$HOOKS_DIR/commit-msg"
git config --global core.hooksPath "$HOOKS_DIR"

# ---- verify -------------------------------------------------------------------
tmp="$(mktemp)"
printf 'test\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\n' > "$tmp"
"$HOOKS_DIR/commit-msg" "$tmp"
if grep -qi claude "$tmp"; then
  echo "✗ hook installed but did not strip attribution — check $HOOKS_DIR/commit-msg" >&2
  rm -f "$tmp"; exit 1
fi
rm -f "$tmp"

echo "✓ commit-msg hook installed at $HOOKS_DIR/commit-msg"
echo "  global core.hooksPath -> $(git config --global core.hooksPath)"
echo "  Note: repos with their own core.hooksPath (e.g. Husky) bypass this global hook."
