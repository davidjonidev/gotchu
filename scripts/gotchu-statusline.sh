#!/usr/bin/env bash
# gotchu-statusline.sh — full standalone statusLine. For users without an existing one.
set -euo pipefail

input=$(cat)
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
DIR=$(echo "$input" | jq -r '.workspace.current_dir // "."')

BRANCH=""
if [ -d "$DIR/.git" ] || (cd "$DIR" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1); then
  BRANCH=" | 🌿 $(cd "$DIR" && git branch --show-current 2>/dev/null)"
fi

echo "[$MODEL] 📁 ${DIR##*/}$BRANCH"

echo "$input" | "$PLUGIN_ROOT/scripts/gotchu-line.sh" || true
