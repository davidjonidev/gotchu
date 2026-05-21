#!/usr/bin/env bash
# PostToolUse hook — shell only, no LLM. Appends tool call metadata to
# tool-log.jsonl and updates the statusLine state with a count/timing line.
# Fast (~10ms). The Stop hook is the only LLM call per turn.
set -euo pipefail

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // "."' 2>/dev/null || echo ".")

STATE_DIR="$cwd/.claude/gotchu"
[ -d "$STATE_DIR" ] || exit 0

STICKY=$(jq -r '.sticky // empty' "$STATE_DIR/state.json" 2>/dev/null || echo "")
[ "$STICKY" = "hushed" ] && exit 0

NOW=$(date +%s)
TOOL=$(echo "$input" | jq -r '.tool_name // "unknown"')

# Append a record of this tool call (the Stop hook reads these).
RECORD=$(jq -nc \
  --arg t "$TOOL" \
  --argjson ts "$NOW" \
  --argjson ti "$(echo "$input" | jq -c '.tool_input // {}')" \
  --argjson tr "$(echo "$input" | jq -c '.tool_response // {}')" \
  '{tool:$t,ts:$ts,input:$ti,response:$tr}')
echo "$RECORD" >> "$STATE_DIR/tool-log.jsonl"

# Derive statusLine flavor from accumulated count + elapsed seconds.
COUNT=$(wc -l < "$STATE_DIR/tool-log.jsonl" | tr -d ' ')
FIRST_TS=$(head -1 "$STATE_DIR/tool-log.jsonl" | jq -r '.ts' 2>/dev/null || echo "$NOW")
ELAPSED=$((NOW - FIRST_TS))

if   [ "$COUNT" -le 2 ];  then EMOJI="🐕"; TEXT="watching · $COUNT tool call(s)"
elif [ "$COUNT" -le 5 ];  then EMOJI="🐕"; TEXT="watching · $COUNT tool calls · ${ELAPSED}s"
elif [ "$COUNT" -le 10 ]; then EMOJI="👀"; TEXT="paying attention · $COUNT calls · ${ELAPSED}s"
else                            EMOJI="📖"; TEXT="lots to teach about · $COUNT calls · ${ELAPSED}s"
fi

EXPIRES=$((NOW + 30))
jq -n --arg e "$EMOJI" --arg t "$TEXT" --argjson ex "$EXPIRES" \
  '{emoji:$e,text:$t,expires_at:$ex}' > "$STATE_DIR/state.json.tmp"
mv "$STATE_DIR/state.json.tmp" "$STATE_DIR/state.json"

exit 0
