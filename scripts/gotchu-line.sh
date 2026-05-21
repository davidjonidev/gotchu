#!/usr/bin/env bash
# gotchu-line.sh — read statusLine JSON on stdin, write the pet line (or nothing).
set -euo pipefail

input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // "."' 2>/dev/null || echo ".")
STATE_FILE="$cwd/.claude/gotchu/state.json"

[ -f "$STATE_FILE" ] || exit 0

NOW=$(date +%s)
LINE=$(jq -r --argjson now "$NOW" '
  if ((.sticky // "") != "") then
    "\(.emoji // "😴") \(.text // "hushed")"
  elif ((.expires_at // 0) > $now) then
    "\(.emoji // "🐕") \(.text // "watching")"
  else
    "🐕 watching"
  end
' "$STATE_FILE" 2>/dev/null || echo "")

[ -n "$LINE" ] && echo "$LINE"
exit 0
