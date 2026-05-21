---
name: gotchu
description: A shoulder-tutor that watches the main agent and teaches the user at end of turn about patterns, decisions, codebase context, and risk. PostToolUse adds zero latency (shell-only); Stop is the single LLM call per turn. The user may issue @gotchu directives in their prompts.
---

# gotchu

A small Haiku-powered companion for Claude Code. PostToolUse logs each tool call (shell only, ~10ms) and ticks a live statusLine counter. At Stop, Haiku reads the full turn's tool log, picks the strongest 1-3 teaching moments, emits a short debrief. Subscription-billed via the native `type:"agent"` hook.

## Activation

This plugin runs automatically via hooks once installed. No slash command to "invoke" mid-turn. One-time setup: `/gotchu init` creates `.claude/gotchu/` in the current repo.

## Commands the user might type

The user may include `@gotchu ...` directives in their messages. UserPromptSubmit intercepts them and updates local state — they do NOT go to you:

- `@gotchu more` — next debrief is in detailed mode
- `@gotchu N` (1–3) — detailed view of just lesson N
- `@gotchu what` — forces a debrief on next Stop even with empty tool log
- `@gotchu hush` — mute for the rest of the session
- `@gotchu wake` — unmute

If the user types one of these directly to you, acknowledge briefly. Don't try to "be" the pet.

## How it works (so you can explain it if asked)

- **PostToolUse:** plain shell script. Appends `{tool, ts, input, response}` to `.claude/gotchu/tool-log.jsonl`. Updates `state.json` with a count/timing line for the statusLine. Zero LLM, ~10ms.
- **Stop:** `type:"agent"` Haiku 4.5. Reads the tool log + any intent.json, picks top lessons, emits `systemMessage`, clears state. ~2-3s once per turn.
- **UserPromptSubmit:** regex parser for `@gotchu` commands. No LLM.

The statusLine helper renders the pet line from `state.json` with a 30-second TTL on the count message — falls back to "🐕 watching" when stale.

## Cost / dependencies

Uses your Claude Code subscription via native agent hook. No separate API key. `bash` + `jq` need to be on PATH.

## Personality

Brief. Curious. Teaching-first. Doesn't lecture; surfaces. Silence is a feature.
