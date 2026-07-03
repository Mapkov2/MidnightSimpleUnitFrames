# PLAN: Assistant Context Engine

Goal: the in-game assistant controls every MSUF option with human-like context
understanding. This plan turns that into small, independently shippable steps
that any strong coding model (Opus 4.8 or better) can execute one session at a
time. All architecture decisions are made HERE so execution sessions are
verification-driven, not design-driven.

Written 2026-07-03 against the current beta branch. All line numbers are
approximate anchors — re-locate by the quoted function names, not by number.

---

## Ground rules (every session, every step)

1. **One step per session.** Do not combine steps. Do not refactor code you are
   not told to touch. Do not reorder the parser pipeline.
2. **Harness gate.** The external training harness (3711 cases) must stay green.
   If you cannot run it yourself, finish the step, run the in-game acceptance
   sentences, and hand off with "harness run required" noted. Never declare a
   step done with a red or unrun harness AND unrun acceptance sentences.
3. **Syntax gate.** `luac -p <file>` for every touched file
   (luac at `C:\Users\Marco\AppData\Local\Programs\Lua\bin\luac`). Target is
   WoW Lua 5.1: no `goto`, no integer division, no bitwise operators.
4. **English only** for all new labels, aliases, and responses. Do not delete
   existing German aliases (separate cleanup, not this plan).
5. **Additive bias.** Every new behavior needs a fall-through: if the new code
   is not confident, it must return nil and let the existing pipeline run
   unchanged. A killswitch flag accompanies each phase (see steps).
6. **No behavior change without an acceptance sentence.** Each step lists its
   sentences. Add new ones to the harness when possible.

---

## Architecture map (recon results — trust these, verify anchors on read)

Input flow:

- `A.HandleInput(text)` — `MSUF_Assistant.lua:5848` → `A.RouteInput` →
  `A.HandleCommandInput` → parser pipelines.
- Pipeline order comment: `MSUF_AssistantParser.lua:4646` ("Pipeline order
  matters"). Follow-up handling runs EARLY: `A._ParseFollowupAnswer` then
  `P.BuildFollowup` (`MSUF_AssistantParser.lua:4651-4652`), then broad registry
  matching in later stages.
- `BuildFollowup` gating: `MSUF_AssistantParser_Followups.lua:395` with bare
  reference words at `:61` and `:534` (`explicitFollowupReference`: "it",
  "that", "more", ...). THIS is why partially re-stated subjects ("now move
  target leader up") bypass follow-up mode: they don't look like bare
  references, so the full parse wins with a broader match.

Plans and execution:

- Plan shape: `{ kind = "changes", changes = { { setting = <spec>, value = v,
  relativeDelta = n?, valueLabel = s?, direction = s? } }, summary, label }`.
- Dispatch: `MSUF_Assistant.lua:5577` (`if plan.kind == "changes" then ...
  ExecuteChanges(plan)`).
- `ExecuteChanges` — `MSUF_Assistant.lua:5378`. **`relativeDelta` already
  works** (`:5394`: `newValue = old + relativeDelta`). Number clamping via
  `A.ClampNumber` respects setting.min/max/step.
- **No-op exit (Phase 0 choke point #1)**: `MSUF_Assistant.lua:5447-5455` —
  when `#undoChanges == 0`: `RememberUnchangedChangeContext(plan, changes)`
  then `AlreadySetResponse(changes)`.

Conversation context (already exists, underused):

- Store: `A.GetContext()` — `MSUF_AssistantHistory.lua:172` (persisted in the
  assistant DB). Written by `A.RememberAppliedBundle` (`:182`): `lastSetting`
  (key string), `lastUnit`, `lastFrameType`, `lastCategory`, `lastValue`.
- `ExecuteChanges` additionally records `lastDirection`
  (`MSUF_Assistant.lua:5429`) and text-editing context via
  `RememberTextChangeContext` (`:5180`): `lastTextArea`, `lastTextSlot`,
  `lastTextSetting`, `lastTextUnit`, `selectedTextEditorTarget`.
- `RememberUnchangedChangeContext` (`:5254`) records context even for no-op
  plans — good: the subject of an "Already set" answer IS in context.

Registry (the tool layer — do not restructure):

- `A.Registry` object, methods in `MSUF_AssistantRegistry_Core_Registry.lua`:
  `RegisterSetting`, `GetSetting(key)`, `AllSettings()`,
  `FindSettings{unit=, frameType=, attribute=, type=}` (indexed).
- Setting spec fields available for scoring/escalation: `key` ("unit.dbKey"),
  `label`, `category`, `unit`, `frameType`, `attribute`, `type`
  ("boolean"|"number"|enum-ish "string"), `min/max/step/percent`, `aliases`,
  optional `moveAxis`/`moveStep`/`moveAmount` (see
  `MSUF_AssistantRegistry_Unitframes_Core_SettingsBase_Unit.lua`).
- Generated fallback settings (from `MSUF_AssistantRegistry_AutoCoverage.lua`)
  carry `generated = true`. When scoring, prefer non-generated on ties.

Known failure classes this plan fixes (real screenshots, 2026-07-03):

- F1 "lost subject": "Target Leader / Assist is already enabled." → user:
  "now move target leader up" → assistant changed **Target Y Position** (frame)
  instead of the leader indicator offset.
- F2 "enum eats relative": "move target of target name more to the right" →
  "Already set. Target of Target Name Text Anchor is already right." — the
  anchor enum matched; the user wanted an X-offset nudge.

---

## Phase 0 — chokepoint fixes (2 steps, ~1 session each)

### Step 0.1 — No-op escalation to relative nudge (fixes F2)

**Contract.** When a `changes` plan executes as a complete no-op AND the source
utterance carries relative-intent markers AND the plan has exactly one change
whose setting is non-numeric (enum/string/boolean-anchor style), re-plan the
change as `relativeDelta` on the associated numeric axis setting and execute
that instead of answering "Already set". If any condition fails or no axis
setting resolves, answer exactly as today.

**Implementation anchors.**

1. New shared marker data on `A` (create in `MSUF_Assistant.lua` near the
   response helpers, or a tiny new file loaded before it):
   - `A.RELATIVE_INTENT_MARKERS = { "more", "further", "farther", "a bit",
     "bit more", "slightly", "a little", "little more", "again", "keep going",
     "even more", "much more", "way more" }`
   - Reuse/align with the lists in `MSUF_AssistantParser_Followups.lua:423`
     and `:465` — do NOT duplicate semantics; if practical, move those lists to
     this shared table and reference it from Followups.
   - Direction extraction: `A.ExtractNudgeDirection(text)` → "left" | "right" |
     "up" | "down" | nil (word-boundary match; "to the right", "rightwards",
     "right" all → "right").
2. The plan needs the source utterance at execute time. Add
   `plan.sourceText = normalized` at the single dispatch site
   (`MSUF_Assistant.lua:5577` caller — the function that receives the parsed
   plan plus the input text; if the text is not in scope there, set
   `A._currentInputText` in `A.HandleCommandInput` before parsing and read it
   in `ExecuteChanges`). Prefer the explicit plan field if the text is
   reachable; fall back to the module-local only if not.
3. Hook inside `ExecuteChanges` immediately before the
   `#undoChanges == 0` return block (`MSUF_Assistant.lua:5447`):

   ```lua
   if #undoChanges == 0 and A.ContextEngineEnabled ~= false then
       local escalated = TryNoOpEscalation(plan, changes)
       if escalated then return escalated end
   end
   ```

   `TryNoOpEscalation(plan, changes)`:
   - require `#changes == 1`, `changes[1].relativeDelta == nil`
   - require `plan.sourceText` contains a relative marker OR
     (a direction word AND the setting is not type "number")
   - `direction = A.ExtractNudgeDirection(plan.sourceText)`; nil → give up
   - resolve axis setting (below); nil → give up
   - `delta = (direction == "left" or direction == "down") and -amount or amount`
     where `amount = axisSetting.moveStep or 10`, halved (min 2) when the text
     contains "a bit"/"slightly"/"a little"/"tiny"
   - build `{ kind = "changes", changes = { { setting = axisSetting,
     relativeDelta = delta, direction = direction } }, summary = plan.summary,
     label = plan.label, sourceText = plan.sourceText }` and return
     `ExecuteChanges(newPlan)` (recursion depth 1 — guard with a flag on the
     plan so escalation never chains).
4. Axis resolution `ResolveAxisSetting(setting, direction)`:
   - axis = ("left"/"right") and "X" or "Y"
   - candidate attribute names, in order:
     a. `setting.moveAxis`-declared partner if the spec provides one
     b. attribute stem: strip trailing "Anchor"/"Align"/"Alignment"/"Side"
        from `setting.attribute`, try `<stem>Offset<axis>`, `<stem><axis>`
     c. text context: if `A.GetContext().lastTextArea` matches the setting
        (same unit + the setting is a text setting), try
        `<lastTextArea>Offset<axis>` (MSUF text offsets follow
        `<prefix>OffsetX/Y`, see `M.TextOffsetKeys` usage in
        `MSUF_Menu2_Support.lua:380`)
     d. generic frame axis: `offset<axis>`, `<axis lowercase>` ("x"/"y")
   - resolve each candidate via `A.Registry:FindSettings{ unit = setting.unit,
     attribute = cand }`; first hit wins; prefer non-generated when multiple.
   - Must return a `type == "number"` setting; otherwise nil.
5. Response: the normal `ChangedResponse` path already produces
   "Done. I changed <axis label> from a to b." — no special text needed.
6. Killswitch: `A.ContextEngineEnabled` (default true), checked at the hook.

**Acceptance sentences** (in-game, target's name anchor already "right"):
- "move target of target name more to the right" → changes name X offset,
  NOT "Already set". Then "undo" reverts it.
- "move target of target name to the right" when anchor is NOT right →
  still sets the anchor enum (unchanged behavior — no relative marker and the
  enum change is not a no-op).
- "set target name anchor to right" when already right → still answers
  "Already set" (no relative marker, no direction-only escalation for explicit
  "set ... to <value>" phrasing: require the verb "move"/"nudge"/"shift"/"push"
  in the text when escalating on direction-without-marker).
- "move target frame up" → unchanged behavior (numeric Y setting, not a no-op).

### Step 0.2 — Continuation follow-up with partial subject (fixes F1)

**Contract.** An utterance that (a) starts with or contains a continuation
marker, (b) contains a move/change verb, and (c) re-states a subject whose
tokens overlap the LAST turn's subject, is resolved against the last subject's
setting family first. If no confident family match exists, return nil and let
the normal pipeline run (today's behavior, including its mistakes).

**Implementation anchors.**

1. New function `P.BuildContinuationFollowup(normalized, ctx)` in
   `MSUF_AssistantParser_Followups.lua`, registered in the pipeline DIRECTLY
   AFTER `BuildFollowup` (`MSUF_AssistantParser.lua:4652`). It must be
   side-effect free when returning nil.
2. Turn freshness: add `ctx.lastTurnSerial` — increment a serial in
   `A.HandleInput` (`MSUF_Assistant.lua:5848`) via
   `A.SetContextValue("turnSerial", n+1)`; `A.RememberAppliedBundle` stamps
   `ctx.lastSubjectTurn = turnSerial`. Continuation only fires when
   `turnSerial - lastSubjectTurn <= 3`.
3. Gates (all must pass, else nil):
   - continuation marker present: `{ "now ", "then ", "also ", "next ",
     "ok now", "and now" }` (prefix or embedded with word boundaries)
   - move/change verb present: `{ "move", "nudge", "shift", "push", "raise",
     "lower" }`
   - `ctx.lastSetting` resolves via `A.Registry:GetSetting(ctx.lastSetting)`
4. Subject overlap: tokenize the utterance minus stopwords, verbs, directions,
   amounts, and unit words; tokenize the last setting's `label` + `category`.
   Require every remaining utterance subject token to appear in the
   label/category token set (case-insensitive, singular/plural tolerant). For
   F1: utterance tokens {"target","leader"} ⊂ label tokens of
   "Target Leader / Assist ..." → pass. "now move target up" leaves subject
   token {"target"} which also passes — acceptable: family resolution (next
   step) then decides, and the frame family only wins if the last setting was
   a frame setting.
5. Family resolution: candidates =
   `A.Registry:FindSettings{ unit = last.unit }` filtered to
   `category == last.category`; direction from `A.ExtractNudgeDirection`;
   pick the numeric setting whose attribute matches the axis
   (`...Offset<axis>`, `...<axis>`), reusing `ResolveAxisSetting` from Step 0.1
   with `last` as the base setting. Exactly one confident hit → build a
   `changes` plan with `relativeDelta` (amount rules from Step 0.1). Zero or
   ambiguous → return nil (fall through).
6. Killswitch: same `A.ContextEngineEnabled` flag.

**Acceptance sentences:**
- "enable target leader icon" (or toggle it in the menu is NOT enough — the
  context comes from assistant turns) → "now move target leader up" → changes
  the leader/assist indicator Y offset, NOT "Target Y Position". "undo" works.
- "set target hp bar opacity to 80%" → "now move target leader up" → must NOT
  use the stale hp context (subject tokens {"target","leader"} do not all
  appear in "Target HP Bar Opacity" label → falls through to normal parse;
  today's behavior).
- "move target frame up" with no prior assistant turn → unchanged behavior.
- Four turns after the leader turn (freshness expired) → "now move target
  leader up" behaves like today.

---

## Phase 1 — context as default, scoring instead of first-match (~3 sessions)

### Step 1.1 — Formalize the context object

- Single accessor `A.ConversationContext()` returning a typed view over
  `A.GetContext()`: `{ subject = { settingKey, unit, frameType, category,
  textArea, textSlot }, lastValue, lastDirection, turnSerial, ageTurns }`.
- Record context on EVERY answer path, not only applied changes: ambiguous
  answers ("Which of these..."), failed parses, and info answers must at least
  stamp `lastMentionedUnit` / `lastMentionedCategory` when the parser resolved
  them before failing. Anchors: `NormalizePlanResult` callers in
  `A.HandleInput` / `A.HandleCommandInput` (`MSUF_Assistant.lua:5848` area).
- No behavior change in this step — pure plumbing + fields. Acceptance: all
  Phase 0 sentences still pass; harness green.

### Step 1.2 — Candidate scoring at the registry matching layer

- Locate the broad matching stage: `MSUF_AssistantParser_Registry.lua` (5742
  lines) and `MSUF_AssistantParser_Registry_MatchCache.lua` /
  `_ExactAlias.lua`. Find where multiple alias hits compete and the first/
  longest match wins today.
- Introduce `P.ScoreSettingCandidates(candidates, features)` used ONLY at that
  stage. Score = aliasQuality (existing longest-match length, normalized)
  + 0.25 * subjectUnitMatch (candidate.unit == context subject.unit)
  + 0.25 * subjectCategoryMatch
  + 0.15 * textAreaMatch
  − 0.40 * noOpPenalty (candidate's `get()` already equals the value the
    utterance asks for — only computable for explicit values; skip otherwise)
  − 0.10 * generatedPenalty (`generated == true`)
- Deterministic tie-break: previous behavior's winner. Behind
  `A.ContextEngineEnabled`. Cache-safety: context features must NOT poison the
  match cache — score AFTER cache lookup, never inside cached key computation.
- Acceptance: F1/F2 sentences, plus: "move target name up" after talking about
  target name text → nudges name Y, not frame Y. Harness green (this is the
  risky step — if harness regresses, ship behind killswitch default OFF and
  iterate).

### Step 1.3 — Ambiguity answers become context

- When the assistant asks "Which one did you mean?" store the candidate list
  in context (`pendingCandidates`), so "the second one" / a partial re-statement
  resolves against that list before anything else. Anchor: the existing
  pending-results flow in `A.HandleInput`
  (`CurrentPendingResults`/`ClearPendingResults`, `MSUF_Assistant.lua:5850`).
- Acceptance: trigger any ambiguous query, answer with an ordinal, verify.

---

## Phase 2 — patterns to data + alias curation (ongoing, mechanical)

- **2a. Literal lifting.** One parser file per session: move `ContainsAny`
  phrase lists into the existing `_Data`-file pattern (see
  `MSUF_AssistantRegistry_*_Data*.lua` for the convention). Logic unchanged,
  literals become data. Harness after every file. Never combine with logic
  changes.
- **2b. Alias curation loop.** Weekly/per-release: `/msufcoverage` → for scopes
  where `generated` fallbacks carry real traffic, run
  `/msufcoverage stubs <scope>` and promote the important keys to hand-written
  registrations with curated English aliases (the generated ones stay as
  backstop; RegisterSetting dedupes by key, hand-written wins when registered
  in domain files which load before AutoCoverage's PLAYER_LOGIN fill).
- **2c. Defaults manifest (unlocks true 100%).** The DB is nil-preserving:
  untouched options have no DB key, so AutoCoverage cannot see them. Have the
  external harness dump the union of all setting keys from a freshly seeded
  profile into a shipped data file
  (`MSUF_AssistantRegistry_AutoCoverage_Manifest.lua`, table of
  scope → { key = defaultValue }); extend `Auto.Fill()` to also register
  manifest keys absent from the live DB (get() falls back to the manifest
  default). After this, `/msufcoverage` percentages measure against the full
  option space, not just materialized keys.

---

## What is intentionally OUT of scope

- No LLM in-game: WoW addons have no network access. True free-form language
  needs an out-of-game companion app that receives the registry as a tool
  schema (the Knowledge module already builds dumps) and returns a declarative
  plan string for the existing executor. The context engine above raises the
  in-game ceiling; it does not remove it.
- No German alias cleanup, no file consolidation of the 280 registry files,
  no parser rewrite. The registry and executor are keepers.

## Session recipe for the executing model

1. Read this plan's step, then ONLY the anchored functions (do not browse).
2. Implement exactly the contract. Unsure → return nil / fall through.
3. `luac -p` every touched file.
4. Run the step's acceptance sentences in-game if possible; otherwise list
   them for Marco with expected before/after.
5. Report: files touched, contract deviations (should be none), harness status.
