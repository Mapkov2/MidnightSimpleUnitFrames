# GOAL: MSUF In-Game LLM

**The MSUF Assistant becomes an in-game "LLM for MSUF" — offline, natural-language,
with maximum performance and 0.0 combat overhead.**

It is not a real language model in the client. It is a fully deterministic engine
that *feels* like talking to an expert, scoped strictly to MSUF, running locally.

## What that means concretely

### Language (feels like chatting with an expert)
- Understands natural English for **every** button, slider, color, and DB setting —
  including typos, casual phrasing, and paraphrases.
- **Never dead-ends**: with no exact match it offers the nearest catalog options
  (read-only) instead of sending the user to Discord.
- **Explains, not just toggles**: why a control is greyed out, what it requires,
  what it conflicts with — sourced from the live dependency graph.
- **Remembers the conversation** across turns ("the other one", "back to the player one").
- On real ambiguity (e.g. anchor **vs** position) it **asks** — it never silently
  picks the wrong thing.

### Control (truly everything)
- Every visible control and DB setting is reachable — with a **verified value
  domain**, never guessed.
- The named scope wins: "on the player frame" resolves to the player setting,
  never a global fallback.

### Safety (P0, non-negotiable)
- On uncertainty it offers a read-only choice instead of mutating. **Zero** wrong
  writes. Every change is atomic and undoable.

### Performance (core condition)
- **Fully offline** — no external service, no model in the client.
- **0.0 combat overhead** — no events, tickers, or work during combat; load-on-demand.
- Fast warm answers; cold load with no frame spike.

### Assured
- Every closed error class has a **registry-wide, self-extending gate test**, so a
  fixed bug can never silently return.

## Definition of Done
For every visible control, across DE/EN prompts: resolved correctly · explained
correctly · changed safely or cleanly clarified · zero wrong writes in an
adversarial corpus · all measured offline and free during combat.

## Progress

Deterministic path chosen; English output first (DE output deferred by decision).

| Item | Status |
|---|---|
| F1 — live dependency-graph verdict in the plain "explain" answer | done |
| F2 — catalog "did you mean" fallback instead of the Discord dead-end | done |
| F3 — multi-turn reach-back to earlier subjects (read-only) | done |
| Charge 1 — 120 read-only number settings made safely writable (inherited domain) | done |
| Scope priority — named frame beats generated global fallback (registry-wide, 148 combos) | done |
| Move-vs-anchor — "move name to the left/right/up/down" now offsets; "to middle" still anchors | done |
| Anchor-vs-position choice on genuine ambiguity (bare "name to the left" asks instead of guessing) | done |

Every change so far preserves 0.0 combat overhead (static metadata / menu-only
answer paths; no new events or tickers).

## Non-goals
- No real LLM or external inference in the client.
- No network calls, no telemetry of user config.
- No guessed value domains: an unreviewed range stays read-only until verified.
