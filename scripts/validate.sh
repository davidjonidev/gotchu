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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
