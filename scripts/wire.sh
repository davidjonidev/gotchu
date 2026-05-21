#!/usr/bin/env bash
# gotchu wire — automatically wire the pet into the user's Claude Code statusLine.
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LINE_SCRIPT="$PLUGIN_ROOT/scripts/gotchu-line.sh"
WRAPPER="$PLUGIN_ROOT/scripts/gotchu-statusline.sh"
SETTINGS="${GOTCHU_SETTINGS:-$HOME/.claude/settings.json}"

YES=0; DRY=0; UNWIRE=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes)     YES=1 ;;
    -n|--dry-run) DRY=1 ;;
    --unwire)     UNWIRE=1 ;;
    -h|--help)
      cat <<USAGE
gotchu wire — wire the pet into your Claude Code statusLine.

Usage:
  gotchu wire             show plan, ask y/N
  gotchu wire --yes       apply without asking
  gotchu wire --dry-run   show plan and exit, change nothing
  gotchu wire --unwire    remove the gotchu-wired-* block from your script

Detects ~/.claude/settings.json's statusLine.command:
  • script present → Option A: appends a marked block to that script
  • no statusLine  → Option B: points settings at gotchu-statusline.sh
Always sets statusLine.refreshInterval = 3.

Override target with GOTCHU_SETTINGS=/path/to/settings.json
USAGE
      exit 0
      ;;
  esac
done

BEGIN_MARK="# gotchu-wired-begin"
END_MARK="# gotchu-wired-end"

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

CURRENT_CMD=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null || echo "")
CURRENT_REFRESH=$(jq -r '.statusLine.refreshInterval // empty' "$SETTINGS" 2>/dev/null || echo "")

# Extract a target script path from a "bash <path>" or "<path>" command.
target_from_cmd() {
  local cmd="$1"
  cmd="${cmd# }"
  cmd="${cmd#bash }"
  cmd="${cmd#sh }"
  set -- $cmd
  [ -f "${1:-}" ] && echo "$1" || true
}

TARGET_SCRIPT=""
if [ -n "$CURRENT_CMD" ]; then
  TARGET_SCRIPT="$(target_from_cmd "$CURRENT_CMD")"
fi

if [ "$UNWIRE" = "1" ]; then
  if [ -z "$TARGET_SCRIPT" ]; then
    echo "Nothing to unwire — no script-based statusLine found in $SETTINGS."
    exit 0
  fi
  if ! grep -qF "$BEGIN_MARK" "$TARGET_SCRIPT"; then
    echo "No gotchu block found in $TARGET_SCRIPT — nothing to unwire."
    exit 0
  fi
  echo "Plan: remove gotchu-wired block from $TARGET_SCRIPT"
  if [ "$DRY" = "1" ]; then exit 0; fi
  if [ "$YES" != "1" ]; then
    printf "Apply? [y/N] "
    read -r reply
    [ "$reply" = "y" ] || [ "$reply" = "Y" ] || { echo "Aborted."; exit 1; }
  fi
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0 ~ b {skip=1; next}
    $0 ~ e {skip=0; next}
    !skip {print}
  ' "$TARGET_SCRIPT" > "$TARGET_SCRIPT.tmp"
  mv "$TARGET_SCRIPT.tmp" "$TARGET_SCRIPT"
  echo "✓ Unwired."
  exit 0
fi

# Build the plan.
MODE=""
PLAN_LINES=()
if [ -n "$TARGET_SCRIPT" ]; then
  MODE="A"
  if grep -qF "$BEGIN_MARK" "$TARGET_SCRIPT"; then
    PLAN_LINES+=("skip: gotchu block already present in $TARGET_SCRIPT")
  else
    PLAN_LINES+=("append gotchu-wired block to: $TARGET_SCRIPT")
    if ! grep -qE 'input=\$\(cat\)|read .*<&0|cat *$' "$TARGET_SCRIPT" 2>/dev/null; then
      PLAN_LINES+=("  ⚠ warning: $TARGET_SCRIPT may not read stdin into \$input — verify after wiring")
    fi
  fi
else
  MODE="B"
  if [ -n "$CURRENT_CMD" ]; then
    PLAN_LINES+=("⚠ existing statusLine.command isn't a script path I can append to:")
    PLAN_LINES+=("    $CURRENT_CMD")
    PLAN_LINES+=("  Will REPLACE it with gotchu-statusline.sh (Option B).")
  else
    PLAN_LINES+=("set settings.json statusLine.command → $WRAPPER (Option B)")
  fi
fi
if [ "$CURRENT_REFRESH" != "3" ]; then
  PLAN_LINES+=("set $SETTINGS statusLine.refreshInterval = 3 (was: ${CURRENT_REFRESH:-unset})")
fi

echo "Plan (mode $MODE):"
for l in "${PLAN_LINES[@]}"; do echo "  • $l"; done

if [ "$DRY" = "1" ]; then exit 0; fi
if [ "$YES" != "1" ]; then
  printf "Apply? [y/N] "
  read -r reply
  [ "$reply" = "y" ] || [ "$reply" = "Y" ] || { echo "Aborted."; exit 1; }
fi

# Apply.
if [ "$MODE" = "A" ] && ! grep -qF "$BEGIN_MARK" "$TARGET_SCRIPT"; then
  {
    printf '\n%s\n' "$BEGIN_MARK"
    printf '"%s" <<< "$input" || true\n' "$LINE_SCRIPT"
    printf '%s\n' "$END_MARK"
  } >> "$TARGET_SCRIPT"
fi

if [ "$MODE" = "B" ]; then
  jq --arg cmd "$WRAPPER" \
     '.statusLine = ((.statusLine // {}) | .type = "command" | .command = $cmd)' \
     "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
fi

jq '.statusLine.refreshInterval = 3' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"

echo "✓ Wired. Reload Claude Code (or run /reload-plugins) to see the pet line."
