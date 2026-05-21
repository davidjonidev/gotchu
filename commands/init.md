---
description: Initialize gotchu in the current repo — creates .claude/gotchu/ state and prints the statusLine snippet.
---

# /gotchu init

Run the init script that creates the per-repo state directory `.claude/gotchu/` and prints the snippet for wiring the pet into your statusLine.

When the user runs this command, execute:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/init.sh"
```

After running, briefly summarize what was created and which statusLine option (A: paste 1 line into existing script, B: swap to the wrapper) suits the user better based on whether they already have a custom statusLine configured.
