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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
