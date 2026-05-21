#!/usr/bin/env bash
# gotchu init — creates .claude/gotchu/ state dir and prints statusLine guidance.
set -euo pipefail

mkdir -p .claude/gotchu
: > .claude/gotchu/tool-log.jsonl

cat > .claude/gotchu/state.json <<'JSON'
{"emoji":"🐕","text":"watching","expires_at":0}
JSON

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

cat <<EOM
gotchu initialized in $(pwd)/.claude/gotchu/

To wire the pet into your statusLine, run:

    /gotchu wire

That auto-detects your current setup, shows a plan, and applies it on
y/N confirmation. Or do it manually:

  Option A — paste this 1 line at the bottom of your existing statusLine
  script (it consumes the same stdin JSON Claude Code already gave you):

    "${PLUGIN_ROOT}/scripts/gotchu-line.sh" <<< "\$input" || true

  Option B — point settings.json statusLine.command at gotchu's full wrapper
  (only if you don't already have a custom statusLine):

    "${PLUGIN_ROOT}/scripts/gotchu-statusline.sh"

Recommended for both options — set in settings.json so the pet line
repaints every 3 seconds:

    "statusLine": { ..., "refreshInterval": 3 }
EOM
