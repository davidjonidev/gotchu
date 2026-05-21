# gotchu

> A Haiku-powered shoulder-tutor for Claude Code. Watches your main agent and teaches you what just happened at end of turn. **Zero latency between tool calls. Runs on your Claude Code subscription.**

> 🤖 **Heads up:** gotchu was built collaboratively with Claude Code. The whole plugin — hooks, scripts, prompts — was implemented by an AI agent following a human-written spec and plan. It's tested (32 self-test assertions) and reviewed, but please give the code a once-over before installing into a repo you care about, and treat v0.1.0 as early-days.

**The problem:** AI coding agents do the work, devs lose skill. Code lands without you understanding why it landed that way. Patterns, framework idioms, design decisions — invisible.

**What gotchu does:** logs every Bash/Write/Edit your main agent makes (instant, shell-only), shows live counters in your statusLine, and at end of turn surfaces 1–3 short lessons about the most interesting things that happened.

```
🐕 gotchu — 2 lessons

1. useTransition (React 18+)
   Marks updates non-urgent so they don't block keystrokes. Agent
   used it here because filtering 400 items would jank typing.

2. JSONB over JSON in migration
   Binary, indexable, queryable. JSON preserves key order; JSONB
   doesn't. JSONB is the right call for queryable payload data.

@gotchu 1 · @gotchu 2 · @gotchu more · @gotchu hush
```

## Install

```bash
/plugin marketplace add davidjonidev/gotchu
/plugin install gotchu@gotchu
```

Then in any repo:

```bash
/gotchu init
```

This creates `.claude/gotchu/` for state and prints the statusLine snippet.

## Setting up the statusLine

**Easy mode:** run `/gotchu wire`. It detects your current setup, prints a plan, and applies it on y/N confirm. Pass `--yes` to skip the prompt, `--dry-run` to preview only, `--unwire` to reverse it.

Prefer to do it by hand? Two options:

**Option A** — you already have a custom statusLine. Add ONE line to it:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/gotchu-line.sh" <<< "$input" || true
```

**Option B** — you don't. Point `settings.json` at gotchu's wrapper:

```json
{
  "statusLine": {
    "type": "command",
    "command": "${CLAUDE_PLUGIN_ROOT}/scripts/gotchu-statusline.sh",
    "refreshInterval": 3
  }
}
```

For Option A, also set `refreshInterval: 3` in your statusLine config so the pet line repaints in near-real-time.

## Commands

| Command | Effect |
|---|---|
| `@gotchu more` | Next Stop debrief is detailed mode |
| `@gotchu N` (1–3) | Detailed view of just lesson N |
| `@gotchu what` | Force a debrief on next Stop even with empty tool log |
| `@gotchu hush` | Mute pet for the rest of the session |
| `@gotchu wake` | Unmute |

## Architecture

Three hooks. Two are shell-only and instant; one is the single LLM call per turn.

| Hook | Type | Latency | LLM? |
|---|---|---|---|
| UserPromptSubmit | command (regex) | ~10ms | ❌ |
| PostToolUse | command (shell) | ~10ms | ❌ |
| Stop | agent (Haiku 4.5) | ~2-3s once per turn | ✅ (1 per turn) |

The statusLine reads `.claude/gotchu/state.json` (updated by PostToolUse on every tool call). Tool calls accumulate in `.claude/gotchu/tool-log.jsonl`. At Stop, Haiku reads the full log, picks the strongest 1-3 teaching moments, emits the debrief, and clears state.

**Why one LLM call per turn instead of per-tool?** Haiku at Stop sees ALL tool calls together — it can correlate, prioritize, and skip noise. Mid-turn per-call evaluation can't do that. Also: zero perceptible latency between tool calls.

## Requirements

- Claude Code (this plugin uses native agent hooks — Claude-Code-only)
- `bash` and `jq` on PATH

No `ANTHROPIC_API_KEY`. The Stop hook runs Haiku via Claude Code's `type:"agent"` primitive, which uses your existing Claude.ai subscription.

## Philosophy

Every observation is a teaching moment, including risky ones. There's no separate "safety mode" — when the agent does something with notable failure modes, gotchu teaches you the failure mode at end of turn instead of nagging mid-flow. Silence is the default; the pet only speaks when it has something worth saying.

## License

MIT — see [LICENSE](./LICENSE).

---

Built by [David Joni](https://davidjoni.dev). Part of the AI Engineering section of my portfolio.
