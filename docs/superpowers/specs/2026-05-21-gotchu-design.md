# gotchu — design spec

- **Date:** 2026-05-21
- **Status:** Draft (pre-implementation)
- **Plugin name:** `gotchu`
- **Target agent:** Claude Code (uses hooks, agent-type hooks, statusLine — Claude-Code-only by design)
- **Standalone repo:** `~/dev/gotchu/`

---

## Premise

A small Haiku-powered "shoulder-tutor" plugin for Claude Code. Watches the main agent end-of-turn (and during turns via the statusLine), teaches the user the interesting bits of what the agent just did, stays silent when there's nothing worth saying.

**The unification:** every observation — including risky ones — is a teaching moment. Safety guidance is a *flavor* of teaching, not a separate concern. Single voice, single purpose.

**One-line pitch:** *AI agents do the work; gotchu makes sure you learn from it.*

---

## Goals

- Reduce **skill atrophy** in devs who lean on AI coding agents — surface the techniques, patterns, decisions, and tradeoffs the agent makes silently.
- Provide a **passive safety net** without duplicating Claude Code's existing classifier/permissions stack — by *teaching* the failure mode rather than blocking the action.
- Feel **alive** through a statusLine ticker that reacts mid-session, not just at end-of-turn.
- Respect the user's attention — **silent unless notable**, hard-capped output, easy hush.

## Non-goals (explicitly out of v1)

- Cross-session learning log or "things I already know" personalization
- Cross-repo memory
- Support for non–Claude-Code agents (hooks are CC-only)
- Hardcoded pitfall library (lessons are LLM-judged from transcript context)
- Replacing or interfering with Claude Code's auto-mode classifier
- Any UI surface beyond statusLine + transcript text

---

## Architecture

Three hooks + state file + statusLine integration.

```
┌──────────────────────────────────────────────────────────────┐
│ Main agent does work in Claude Code                          │
└──────────────────────────────────────────────────────────────┘
        │
        ▼
   [tool call]
        │
        ▼
┌──────────────────────────────────────────────────────────────┐
│ PostToolUse hook (async: true, non-blocking)                 │
│  • spawns Haiku 4.5 worker via type:"agent" hook             │
│  • prompt: per-tool teaching-lens scan over last ~15 msgs    │
│  • appends finding to .claude/gotchu/findings.jsonl          │
│  • writes transient line to .claude/gotchu/state.json        │
│    with expires_at = now + 40s                               │
└──────────────────────────────────────────────────────────────┘
        │
        ▼
┌──────────────────────────────────────────────────────────────┐
│ UserPromptSubmit hook (cheap, regex only — no LLM)           │
│  • scans user message for @gotchu commands                   │
│  • on match, writes a flag to .claude/gotchu/intent.json     │
│  • Stop hook reads the flag and adjusts behavior             │
└──────────────────────────────────────────────────────────────┘
        │
        ▼
┌──────────────────────────────────────────────────────────────┐
│ Stop hook (sync, runs at end of agent turn)                  │
│  • reads findings.jsonl + intent.json                        │
│  • if no findings AND no @gotchu what intent → silent exit   │
│  • else spawns Haiku 4.5 to compose the debrief              │
│    (short by default, detailed if @gotchu more/N was used)   │
│  • emits via systemMessage into the conversation             │
│  • truncates findings.jsonl, resets state to idle            │
└──────────────────────────────────────────────────────────────┘
```

**Why two hooks instead of one Stop hook?** Per-tool collection catches signal that's gone by end of turn — agent runs `npm test`, output flashes a warning, agent moves on. PostToolUse grabs that in flight. The Stop hook then composes from accumulated notes, not the live transcript alone.

---

## Components

### 1. PostToolUse hook (`hooks/per-tool.sh`)

- Hook type: `"agent"` (Claude Code's agent-hook type — runs a Haiku worker with a prompt)
- Matcher: `"Bash|Write|Edit|Read"` (skip trivial tool calls like Glob/Grep to control cost)
- `async: true`, `model: "claude-haiku-4-5-20251001"`
- Receives last ~15 messages of the transcript via stdin
- Output: JSON with `{ ok: bool, finding?: { lens, summary, detail }, statusline_text?: string }`
- Side effects: append to `findings.jsonl`, write to `state.json`

### 2. UserPromptSubmit hook (`hooks/on-prompt.sh`)

- Plain shell, no LLM
- Regex match user message against `@gotchu (more|hush|wake|what|[0-9]+)`
- Write matched intent to `.claude/gotchu/intent.json`

### 3. Stop hook (`hooks/on-stop.sh`)

- Hook type: `"agent"` with Haiku 4.5
- Reads accumulated findings + intent
- Composes the debrief per the formatting rules in §Output Format
- Emits `{ "systemMessage": "<debrief>" }` to surface in the conversation
- If `findings.jsonl` is empty AND intent isn't `what` → silent exit

### 4. State files

All under `<repo>/.claude/gotchu/`:

- `state.json` — current statusLine content: `{ emoji, text, expires_at, sticky?: "hushed" }`. The `sticky` field is set when the user runs `@gotchu hush` and cleared by `@gotchu wake`; while present, transient lines are ignored and the statusLine renders the hushed indicator.
- `findings.jsonl` — one JSON per line, accumulated since last Stop. Cleared at the end of every Stop hook (truncate to empty).
- `intent.json` — per-turn intent (`more`, `N`, `what`). Read by Stop, then deleted. Session-persistent state (hush/wake) is NOT stored here; it lives in `state.json.sticky`.

The directory is gitignored by default — local state, not for teammates. Stale files from a prior crashed session are tolerated: transients expire by TTL on read, `findings.jsonl` is overwritten on first Stop of the next session, and `intent.json` is deleted after a single read. No SessionStart cleanup needed.

### 5. StatusLine wrapper (`scripts/gotchu-statusline.sh`)

Optional install path that wraps the user's existing statusLine script. Reads `state.json`, checks `expires_at` against `now()`, and renders one of:

- Active finding line (within TTL): `<emoji> <text>`
- Sticky state (hush/preview/debrief-incoming): rendered as-is, ignores TTL
- Idle fallback: `🐕 watching · N tool calls · M lessons` (or rare rotating tip)

Plugin `settings.json` for the gotchu install sets `refreshInterval: 3` on the statusLine so the line repaints every 3 seconds.

### 6. Slash command (`commands/init.md`)

`/gotchu init` — creates `.claude/gotchu/` in the current repo, prints the statusLine snippet for the user to either paste into their existing script (minimal path) or swap in the wrapper script.

### 7. SKILL.md

Canonical agent-facing description of the plugin. Briefly explains the personality, the `@gotchu` commands the user might type, and what to do if the user disables gotchu mid-session.

---

## Data flow

```
turn starts
  user prompt → UserPromptSubmit hook → maybe writes intent.json
  agent runs tool call → PostToolUse hook → Haiku worker
    → may append to findings.jsonl
    → may write transient state.json line
  ... more tool calls, more findings, statusLine repaints every 3s
agent finishes → Stop hook
  reads findings + intent
  composes debrief OR exits silently
  emits systemMessage to conversation
  clears findings.jsonl, resets state to idle
turn ends
```

---

## Output format

### Short mode (default conversational output)

```
🐕 gotchu — 2 lessons

1. useTransition (React 18+)
   Marks updates non-urgent so they don't block keystrokes. Agent
   used it here because filtering 400 items would jank typing.

2. JSONB over JSON in migration
   Binary, indexable, queryable. JSON preserves key order; JSONB
   doesn't. JSONB is the right call for queryable payload data.

@gotchu 1  ·  @gotchu 2  ·  @gotchu more  ·  @gotchu hush
```

### Detailed mode (`@gotchu more` or `@gotchu N`)

Each lesson expands into sections — *What it is · Why the agent picked it · Tradeoff / alternative · Failure mode (if risky).* Paragraphs separated by blank lines. No wall-of-text even at depth.

### Layout rules in Haiku's prompt

- Always newlines between items
- One blank line between sections in detail mode
- Lead with the *thing*, then the *why*
- Max 3 lessons per debrief (any more → top 3 selected, rest dropped)
- No emoji inflation — one pet emoji at the top, that's it

### Teaching lens menu (the prompt hands Haiku these four lenses)

- **Pattern lens** — interesting techniques/APIs the agent used
- **Decision lens** — the choice the agent made and the alternative
- **Codebase-context lens** — why something works in *this* repo
- **Risk lens** — failure modes of what just happened (safety-flavored)

Haiku picks whichever lens fits the turn most naturally. Mixed bag is fine.

---

## StatusLine — dynamic ticker

Beyond static state indicators, the pet writes transient lines into the statusLine reactively. Examples:

- `🐕 watching · 4 tool calls · 1 worth teaching about` — active idle
- `👀 fyi: that fetch is no-store — every request hits the server` — live finding
- `💡 while you wait — useTransition is a React 18 hook for non-urgent updates` — bite-sized teaching during a slow tool call
- `🤔 agent disabled strict null checks on auth — flagged for debrief` — notable risky thing
- `📖 3 lessons coming…` — preview before Stop debrief lands
- `😴 hushed` — when the user said `@gotchu hush`
- `🐕 sniff sniff…` — long idle stretch fallback

### TTL & priority rules

- Transient lines expire after 40 seconds — statusLine then falls back to idle
- Newest finding wins if two arrive close together
- Sticky states (hush, debrief-preview) override transients and never expire by TTL
- Idle flavor rotation is lowest priority; never preempts a real finding
- Idle rotation fires at most once per real minute of inactivity (small built-in tip library, ships with the plugin)

---

## On-demand commands

User commands during a turn, parsed by the UserPromptSubmit hook (regex only, no LLM):

| Command | Effect |
|---|---|
| `@gotchu more` | Next Stop hook re-emits the most recent debrief in detailed mode |
| `@gotchu N` (1–3) | Next Stop hook emits detailed view of lesson N only |
| `@gotchu what` | Forces a debrief on the next Stop even if no findings accumulated |
| `@gotchu hush` | Mute pet for the rest of the session — state becomes sticky `😴 hushed` |
| `@gotchu wake` | Unmute |

One slash command for setup: `/gotchu init` — creates `.claude/gotchu/` in current repo and prints the statusLine snippet.

---

## Repo layout

```
gotchu/
├── plugin.json                 # Claude Code minimal manifest
├── .claude-plugin/
│   └── marketplace.json        # single-plugin marketplace
├── SKILL.md                    # canonical instructions / personality
├── README.md                   # pitch, install, demo, philosophy
├── LICENSE                     # MIT
├── commands/
│   └── init.md                 # /gotchu init
├── hooks/
│   ├── hooks.json
│   ├── per-tool.sh             # PostToolUse handler (calls Haiku via agent-hook)
│   ├── on-stop.sh              # Stop handler
│   └── on-prompt.sh            # UserPromptSubmit handler (regex)
├── scripts/
│   ├── init.sh                 # creates .claude/gotchu/ in target repo
│   ├── gotchu-statusline.sh    # optional wrapper for existing statuslines
│   └── validate.sh             # self-test
├── prompts/
│   ├── per-tool.md             # Haiku per-tool prompt
│   ├── stop-short.md           # Stop short-mode prompt
│   └── stop-detail.md          # Stop detail-mode prompt
├── docs/
│   └── superpowers/specs/2026-05-21-gotchu-design.md   # this file
└── .github/workflows/validate.yml
```

---

## Cost analysis

- **PostToolUse:** ~$0.002 per call (Haiku 4.5, ~3k input + ~50 output). Matcher limits firing to Bash/Write/Edit/Read — typically 5–15 fires per turn.
- **Stop:** ~$0.005 (slightly larger input including findings buffer).
- **UserPromptSubmit:** free (no LLM).
- **Per turn:** ~$0.02–0.04.
- **Heavy day, 100 turns:** ~$2–4.

If cost feels high in practice, the matcher can be narrowed (Bash + Write only), or PostToolUse can be skipped when the findings buffer already has 3 entries (cap reached, no need to scan more).

---

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Noise fatigue | Strict "default silent" prompt. Hard cap of 3 lessons per debrief. `@gotchu hush` for nuclear option. |
| Hook latency slows agent | PostToolUse is `async: true` — never blocks. Stop is sync but bounded (~1–2s for Haiku). |
| Token spend creeps | Bounded per turn; matcher excludes cheap tool calls; cap-stop on PostToolUse when buffer is full. |
| Hallucinated lessons | Prompt requires citing the specific tool call/code the lesson is about. Haiku grounded; not free-form. |
| Conflicts with auto-mode classifier | Hooks run after classifier decisions — no conflict possible. Gotchu observes & teaches, doesn't block. |
| StatusLine flicker | `refreshInterval: 3` is gentle. State file writes are atomic (write to tmp, rename). |
| State files survive crashes | All readers are crash-tolerant: TTL-expired transients are skipped, findings.jsonl is overwritten on next Stop, intent.json is single-read-then-deleted. No SessionStart cleanup hook required. |

---

## Open implementation decisions (resolved during writing-plans, not now)

- Exact Haiku prompts for per-tool and Stop (will iterate)
- Idle-tip library content (~20 tips, hand-curated)
- Whether `@gotchu N` for non-existent N produces an error or silent ignore (probably silent)
- StatusLine emoji set finalization (current draft: 🐕 👀 💡 🤔 📖 🚨 😴)

---

## Out of scope for v1 (deferred to v2+)

- Cross-session learning log (separate "review what I learned" app idea)
- Personalization / user knowledge profile
- Cross-repo memory
- Other agents (Codex, Cursor, etc.)
- Custom pitfall library / user-configurable rule set
- Web/UI surface beyond statusLine
- Multi-language localization
