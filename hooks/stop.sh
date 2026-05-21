#!/usr/bin/env bash
# Stop hook (type:"command"). Invokes claude -p haiku to compose an
# end-of-turn teaching debrief from the accumulated tool-log, then emits a
# {"systemMessage": "..."} JSON object on stdout for Claude Code to surface.
#
# Deterministic responsibilities (don't rely on Haiku):
#   1. Read cwd, validate gotchu state dir
#   2. Honor sticky=hushed (exit silent)
#   3. Read intent.json, then delete it
#   4. Read tool-log.jsonl
#   5. If empty AND intent != "what" → silent, reset state, exit
#   6. Otherwise pass log + intent to claude -p haiku, capture stdout
#   7. ALWAYS reset state (truncate tool-log.jsonl, reset state.json) before exit
#   8. If haiku produced non-empty text → emit {"systemMessage": text}
#      Else → emit {} (silent)
set -euo pipefail

# Read hook payload from stdin (JSON with cwd, transcript_path, etc).
PAYLOAD=$(cat 2>/dev/null || echo '{}')
cwd=$(echo "$PAYLOAD" | jq -r '.cwd // .workspace.current_dir // "."' 2>/dev/null || echo ".")

STATE_DIR="$cwd/.claude/gotchu"
if [ ! -d "$STATE_DIR" ]; then
  echo '{}'
  exit 0
fi

STATE_FILE="$STATE_DIR/state.json"
LOG_FILE="$STATE_DIR/tool-log.jsonl"
INTENT_FILE="$STATE_DIR/intent.json"

reset_state() {
  : > "$LOG_FILE" 2>/dev/null || true
  echo '{"emoji":"🐕","text":"watching","expires_at":0}' > "$STATE_FILE.tmp" 2>/dev/null \
    && mv "$STATE_FILE.tmp" "$STATE_FILE" 2>/dev/null || true
}

# Sticky hushed → silent.
STICKY=$(jq -r '.sticky // empty' "$STATE_FILE" 2>/dev/null || echo "")
if [ "$STICKY" = "hushed" ]; then
  reset_state
  echo '{}'
  exit 0
fi

# Read + consume intent.
INTENT=""
if [ -f "$INTENT_FILE" ]; then
  INTENT=$(jq -r '.command // empty' "$INTENT_FILE" 2>/dev/null || echo "")
  rm -f "$INTENT_FILE"
fi

LOG_LINES=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ' || echo "0")

# Nothing happened this turn and user didn't force a debrief → silent.
if [ "$LOG_LINES" = "0" ] && [ "$INTENT" != "what" ]; then
  reset_state
  echo '{}'
  exit 0
fi

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROMPT_FILE="$PLUGIN_ROOT/prompts/stop.md"
CLAUDE_BIN="${GOTCHU_CLAUDE_BIN:-claude}"

if [ ! -f "$PROMPT_FILE" ] || ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  # Can't compose without claude CLI on PATH or prompt file present.
  reset_state
  echo '{}'
  exit 0
fi

PROMPT_BODY=$(cat "$PROMPT_FILE")
LOG_CONTENT=$(cat "$LOG_FILE" 2>/dev/null || echo "")

FULL_PROMPT="$PROMPT_BODY

## Tool log this turn

$LOG_CONTENT

## Intent

${INTENT:-(none)}
"

# Call Haiku via the user's Claude Code subscription. Capture stdout only;
# discard stderr. Any failure → silent debrief (still reset state).
DEBRIEF=$("$CLAUDE_BIN" -p --model claude-haiku-4-5-20251001 "$FULL_PROMPT" 2>/dev/null || true)

# Trim leading/trailing whitespace.
DEBRIEF=$(printf '%s' "$DEBRIEF" | awk 'NF{f=1} f' | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}')

reset_state

if [ -z "$DEBRIEF" ]; then
  echo '{}'
else
  jq -nc --arg m "$DEBRIEF" '{systemMessage:$m}'
fi
