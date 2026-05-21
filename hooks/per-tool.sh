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
# Pre-extract tool_input/tool_response with a null fallback so a missing key,
# a malformed payload, or an unexpected shape (string/number/array) can't
# crash the hook under set -euo pipefail.
TI=$(echo "$input" | jq -c '.tool_input // null' 2>/dev/null || echo "null")
TR=$(echo "$input" | jq -c '.tool_response // null' 2>/dev/null || echo "null")
[ -n "$TI" ] || TI="null"
[ -n "$TR" ] || TR="null"
RECORD=$(jq -nc \
  --arg t "$TOOL" \
  --argjson ts "$NOW" \
  --argjson ti "$TI" \
  --argjson tr "$TR" \
  '{tool:$t,ts:$ts,input:$ti,response:$tr}' 2>/dev/null) || RECORD=""
[ -n "$RECORD" ] && echo "$RECORD" >> "$STATE_DIR/tool-log.jsonl"

# Derive statusLine flavor from accumulated count + elapsed seconds.
COUNT=$(wc -l < "$STATE_DIR/tool-log.jsonl" | tr -d ' ')
FIRST_TS=$(head -1 "$STATE_DIR/tool-log.jsonl" | jq -r '.ts' 2>/dev/null || echo "$NOW")
ELAPSED=$((NOW - FIRST_TS))

if   [ "$COUNT" -le 2 ];  then EMOJI="🐕"; TEXT="watching · $COUNT tool call(s)"
elif [ "$COUNT" -le 5 ];  then EMOJI="🐕"; TEXT="watching · $COUNT tool calls · ${ELAPSED}s"
elif [ "$COUNT" -le 10 ]; then EMOJI="👀"; TEXT="paying attention · $COUNT calls · ${ELAPSED}s"
else                            EMOJI="📖"; TEXT="lots to teach about · $COUNT calls · ${ELAPSED}s"
fi

# TTL spans the longest realistic gap between consecutive PostToolUse hooks
# within a single turn (text-generation, thinking, reading tool output).
# 30s was too short — measured avg gap is ~20s and peaks well above 30s.
# Stop hook clears state at end of turn, so this is only a safety net for
# crashed/abandoned turns where Stop didn't run.
EXPIRES=$((NOW + 180))
jq -n --arg e "$EMOJI" --arg t "$TEXT" --argjson ex "$EXPIRES" \
  '{emoji:$e,text:$t,expires_at:$ex}' > "$STATE_DIR/state.json.tmp"
mv "$STATE_DIR/state.json.tmp" "$STATE_DIR/state.json"

exit 0
