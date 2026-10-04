#!/usr/bin/env bash
# Rolls back the last git commit: resets the live config, reverts HEAD (as a new commit, history is kept),
# then re-applies every folder's install.sh from the resulting repo state. Keeps your AI sidebar backend choice.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"
CFG="$HOME/.config/illogical-impulse/config.json"
[ -z "$(git status --porcelain)" ] || { echo "Working tree not clean; commit or stash first." >&2; exit 1; }
echo "Rolling back: $(git log -1 --oneline)"
backend=$(jq -r '.ai.sidebarBackend // empty' "$CFG" 2>/dev/null || true)
"$REPO/reset.sh"
git revert --no-edit HEAD
for d in */; do [ -x "$d/install.sh" ] && { echo "== $d"; "$d/install.sh"; }; done
if [ -n "$backend" ] && [ -f "$CFG" ]; then
    jq --arg b "$backend" '.ai.sidebarBackend=$b' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
fi
echo "Rolled back. Restart the shell if QML changed: qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown"
