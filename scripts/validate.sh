#!/usr/bin/env bash
# gotchu self-test. Runs in a tempdir. Tests non-LLM components only;
# the Stop agent hook is verified by manual smoke test.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTDIR="$(mktemp -d)"
PASS=0
FAIL=0

cleanup() { rm -rf "$TESTDIR"; }
trap cleanup EXIT

assert() {
  local desc="$1"; local actual="$2"; local expected="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_file() {
  local desc="$1"; local path="$2"
  if [ -f "$path" ]; then
    echo "  ✓ $desc"; PASS=$((PASS + 1))
  else
    echo "  ✗ $desc (file missing: $path)"; FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1"; local haystack="$2"; local needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  ✓ $desc"; PASS=$((PASS + 1))
  else
    echo "  ✗ $desc (did not find: $needle)"; FAIL=$((FAIL + 1))
  fi
}

echo "Running gotchu self-test in $TESTDIR"
cd "$TESTDIR"

assert "harness smoke test" "ok" "ok"

# === Component tests appended below as each task lands. ===

# --- Task 3: scripts/init.sh ---
echo ""
echo "[init.sh]"
mkdir -p init-test
(cd init-test && "$PLUGIN_ROOT/scripts/init.sh" > /tmp/init-out 2>&1)
assert_file "creates state.json"    "init-test/.claude/gotchu/state.json"
assert_file "creates tool-log.jsonl" "init-test/.claude/gotchu/tool-log.jsonl"
INIT_OUT=$(cat /tmp/init-out)
assert_contains "prints statusLine guidance" "$INIT_OUT" "statusLine"
STATE=$(cat init-test/.claude/gotchu/state.json)
assert_contains "state.json has watching text" "$STATE" "watching"

# --- Task 4: scripts/gotchu-line.sh ---
echo ""
echo "[gotchu-line.sh]"

mkdir -p line-test/.claude/gotchu
LINE_INPUT() {
  jq -n --arg dir "$(pwd)/line-test" '{workspace: {current_dir: $dir}}'
}

# Case 1: missing state → silent
rm -f line-test/.claude/gotchu/state.json
RESULT=$(LINE_INPUT | "$PLUGIN_ROOT/scripts/gotchu-line.sh" 2>/dev/null || true)
assert "missing state → empty output" "$RESULT" ""

# Case 2: idle state → fallback idle line
echo '{"emoji":"🐕","text":"watching","expires_at":0}' > line-test/.claude/gotchu/state.json
RESULT=$(LINE_INPUT | "$PLUGIN_ROOT/scripts/gotchu-line.sh" 2>/dev/null)
assert "idle state → fallback line" "$RESULT" "🐕 watching"

# Case 3: live transient
FUTURE=$(($(date +%s) + 60))
jq -n --argjson e "$FUTURE" '{emoji:"👀",text:"4 tool calls · 12s",expires_at:$e}' > line-test/.claude/gotchu/state.json
RESULT=$(LINE_INPUT | "$PLUGIN_ROOT/scripts/gotchu-line.sh" 2>/dev/null)
assert "live transient → renders" "$RESULT" "👀 4 tool calls · 12s"

# Case 4: expired transient → fallback
PAST=$(($(date +%s) - 60))
jq -n --argjson e "$PAST" '{emoji:"👀",text:"stale",expires_at:$e}' > line-test/.claude/gotchu/state.json
RESULT=$(LINE_INPUT | "$PLUGIN_ROOT/scripts/gotchu-line.sh" 2>/dev/null)
assert "expired transient → fallback" "$RESULT" "🐕 watching"

# Case 5: sticky hushed
jq -n '{emoji:"😴",text:"hushed",expires_at:0,sticky:"hushed"}' > line-test/.claude/gotchu/state.json
RESULT=$(LINE_INPUT | "$PLUGIN_ROOT/scripts/gotchu-line.sh" 2>/dev/null)
assert "sticky hushed → renders hushed" "$RESULT" "😴 hushed"

# --- Task 5: scripts/gotchu-statusline.sh ---
echo ""
echo "[gotchu-statusline.sh]"
SL_INPUT() {
  jq -n --arg dir "$(pwd)/line-test" '{
    model: {display_name: "Sonnet 4.6"},
    workspace: {current_dir: $dir},
    cost: {total_cost_usd: 1.23, total_duration_ms: 65000},
    context_window: {used_percentage: 42}
  }'
}
mkdir -p line-test/.claude/gotchu
echo '{"emoji":"🐕","text":"watching","expires_at":0}' > line-test/.claude/gotchu/state.json
RESULT=$(SL_INPUT | "$PLUGIN_ROOT/scripts/gotchu-statusline.sh" 2>/dev/null)
assert_contains "renders model"   "$RESULT" "Sonnet 4.6"
assert_contains "renders pet line" "$RESULT" "🐕 watching"

# --- Task 6: hooks/on-prompt.sh ---
echo ""
echo "[on-prompt.sh]"

mkdir -p prompt-test/.claude/gotchu
echo '{"emoji":"🐕","text":"watching","expires_at":0}' > prompt-test/.claude/gotchu/state.json

PROMPT_INPUT() {
  jq -n --arg dir "$(pwd)/prompt-test" --arg p "$1" '{cwd: $dir, prompt: $p}'
}

# Case 1: hush → sticky=hushed
PROMPT_INPUT "@gotchu hush please" | "$PLUGIN_ROOT/hooks/on-prompt.sh" > /dev/null 2>&1
STATE=$(cat prompt-test/.claude/gotchu/state.json)
assert_contains "hush sets sticky" "$STATE" "hushed"

# Case 2: wake → sticky removed
PROMPT_INPUT "@gotchu wake up" | "$PLUGIN_ROOT/hooks/on-prompt.sh" > /dev/null 2>&1
STATE=$(cat prompt-test/.claude/gotchu/state.json)
HAS=$(echo "$STATE" | jq -r 'has("sticky")')
assert "wake removes sticky" "$HAS" "false"

# Case 3: more → intent.json
PROMPT_INPUT "@gotchu more" | "$PLUGIN_ROOT/hooks/on-prompt.sh" > /dev/null 2>&1
assert_file "intent.json on more" "prompt-test/.claude/gotchu/intent.json"
INTENT=$(jq -r '.command' prompt-test/.claude/gotchu/intent.json)
assert "intent is 'more'" "$INTENT" "more"
rm -f prompt-test/.claude/gotchu/intent.json

# Case 4: numeric intent
PROMPT_INPUT "tell me what @gotchu 2 means" | "$PLUGIN_ROOT/hooks/on-prompt.sh" > /dev/null 2>&1
INTENT=$(jq -r '.command' prompt-test/.claude/gotchu/intent.json)
assert "numeric intent captured" "$INTENT" "2"
rm -f prompt-test/.claude/gotchu/intent.json

# Case 5: no @gotchu → no intent
PROMPT_INPUT "just some normal coding question" | "$PLUGIN_ROOT/hooks/on-prompt.sh" > /dev/null 2>&1
[ ! -f prompt-test/.claude/gotchu/intent.json ] && \
  { echo "  ✓ no @gotchu → no intent"; PASS=$((PASS+1)); } || \
  { echo "  ✗ no @gotchu produced an intent file"; FAIL=$((FAIL+1)); }

# --- Task 7: prompts/stop.md ---
echo ""
echo "[prompts/stop.md]"
assert_file "stop.md exists" "$PLUGIN_ROOT/prompts/stop.md"
STOP=$(cat "$PLUGIN_ROOT/prompts/stop.md" 2>/dev/null || echo "")
assert_contains "mentions lens menu"           "$STOP" "pattern"
assert_contains "default to silence"           "$STOP" "DEFAULT TO SILENCE"
assert_contains "reads tool-log.jsonl"         "$STOP" "tool-log.jsonl"
assert_contains "short-mode template"          "$STOP" "🐕 gotchu — N lesson"
assert_contains "detail-mode template"         "$STOP" "WHAT IT IS"
assert_contains "systemMessage in final resp"  "$STOP" "systemMessage"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
