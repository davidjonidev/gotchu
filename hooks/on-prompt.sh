#!/usr/bin/env bash
# UserPromptSubmit hook. Regex-only @gotchu directive parser. No LLM.
set -euo pipefail

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // "."' 2>/dev/null || echo ".")
prompt=$(echo "$input" | jq -r '.prompt // empty' 2>/dev/null || echo "")

STATE_DIR="$cwd/.claude/gotchu"
[ -d "$STATE_DIR" ] || exit 0

STATE_FILE="$STATE_DIR/state.json"
INTENT_FILE="$STATE_DIR/intent.json"
TMP="$STATE_FILE.tmp"

set_state() {
  jq "$1" "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
}

[ -z "$prompt" ] && exit 0

if echo "$prompt" | grep -qE '@gotchu[[:space:]]+hush\b'; then
  set_state '. + {sticky:"hushed",emoji:"😴",text:"hushed",expires_at:0}'
elif echo "$prompt" | grep -qE '@gotchu[[:space:]]+wake\b'; then
  set_state 'del(.sticky) | .emoji="🐕" | .text="watching" | .expires_at=0'
elif echo "$prompt" | grep -qE '@gotchu[[:space:]]+more\b'; then
  jq -n '{command:"more"}' > "$INTENT_FILE"
elif echo "$prompt" | grep -qE '@gotchu[[:space:]]+what\b'; then
  jq -n '{command:"what"}' > "$INTENT_FILE"
else
  N=$(echo "$prompt" | grep -oE '@gotchu[[:space:]]+[1-9]\b' | grep -oE '[1-9]' | head -1 || true)
  [ -n "$N" ] && jq -n --arg n "$N" '{command:$n}' > "$INTENT_FILE"
fi

exit 0
