---
description: Automatically wire the gotchu pet into your Claude Code statusLine — appends one line to your existing script (or sets up the wrapper) and enables refreshInterval. Shows a plan first.
---

# /gotchu wire

Run the wire script that detects your current statusLine setup and patches it (or `~/.claude/settings.json`) so the pet line renders. The script always shows its plan first and asks for confirmation unless you pass `--yes`.

When the user runs this command, execute:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/wire.sh" $ARGUMENTS
```

Pass-through arguments the user may include:

| Arg | Effect |
|---|---|
| (none) | Show plan, prompt y/N |
| `--yes` / `-y` | Apply without prompting |
| `--dry-run` / `-n` | Show plan only, change nothing |
| `--unwire` | Remove the gotchu-wired block from the target script |

After running, briefly tell the user what changed (which file got the appended block, or that settings.json now points at the wrapper) and remind them to reload plugins or restart Claude Code if needed.
