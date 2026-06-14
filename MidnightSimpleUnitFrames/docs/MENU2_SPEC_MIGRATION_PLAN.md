# Menu2 Spec-Driven Pages — Migration Plan

Status: proposed. Builds directly on `MENU3_REWRITE_EXPERIMENT_LEARNINGS.md`.

## Goal (honest scope)

Shrink and clarify the **Pages** layer of Menu2 by turning repeated control
declarations into declarative spec rows, while the proven UI core (Window,
NavRail, Widgets, Theme, Preview, Search) stays **byte-for-byte unchanged**.

This is the explicit successor to the failed Menu3 rewrite. It does NOT create a
second shell and does NOT touch the Assistant subsystem.

## Why a full "Menu3" failed (from the post-mortem)

1. Independent shell chrome was never pixel-identical.
2. "Rewrite" taken literally re-created a huge parity problem.
3. Line reduction by deleting UI detail caused regressions.

The fix the post-mortem itself prescribes: keep Menu2 visuals as source of
truth, make specs drive **data not chrome**, migrate **page by page**.

## What the numbers actually say

Total "Menu2" is ~89.9k lines, but:

| Part      | Lines  | In scope? | Note |
|-----------|--------|-----------|------|
| Assistant | ~48.1k | NO        | Separate NLP subsystem, not menu chrome |
| Pages     | ~15.4k | YES       | The duplication lives here |
| Core/root | ~13.3k | NO (stays)| Window/Widgets/Theme/NavRail — pixel source of truth |
| Preview   | ~9.3k  | NO        | Stateful render modules |
| Search    | ~3.8k  | partial   | Aliases can move into specs later |

**Realistic reduction: ~35–45% of the Pages layer (~15.4k → ~9–10k).**
A flat "50% of all of Menu2" is NOT realistic without deleting real behavior.

## Where specs pay off (bind-calls vs custom local-funcs)

High bind / low custom-func pages = pure boilerplate = biggest, safest win:
- GroupIndicators (50 / 48), GroupBars (34 / 38), UnitText (24 / 24),
  GroupLayout (20 / 15), UnitFrameVisuals (29 / 35), UnitStatusSection (18 / 22).

Low bind / high custom-func pages = mostly real logic = leave mostly as-is:
- Auras (6 / 89), AdvancedColors (1 / 60), Unit (0 / 57), Group (9 / 69).
  Forcing these into specs is exactly what broke Menu3. Migrate only their
  trivial controls; keep their custom logic hand-written.

## The spec schema (data, not chrome)

A page becomes an ordered list of section + control rows. Each control row:

```lua
{
  type   = "toggle" | "slider" | "segment" | "dropdown" | "color",
  label  = "Show shadow",
  values = ...,                 -- segment/dropdown only
  min/max/step = ...,           -- slider only
  get    = function() ... end,  -- reads DB (one place)
  set    = function(v) ... end, -- writes DB + fires apply reason (one place)
  gate   = function() ... end,  -- optional: enabled/disabled
  search = "shadow text outline",-- optional: feeds Search index
}
```

A shared renderer walks the rows and calls the SAME `W.*` widgets +
`M.Bind*` binders the pages already use. No new widgets, no new theme — so
output is automatically pixel-identical.

Custom logic (color previews, name-shortening branches, runtime apply chains)
stays as named functions referenced from `set`/`gate`. Specs hold data; code
holds behavior.

## Milestones

### M0 — Spec renderer (no page changes yet)
- Extend `W.PageBuilder` with `b:Rows(spec)` that renders the control types
  above via existing widgets/binders.
- Acceptance: a throwaway 3-control spec renders identically to the same 3
  hand-written controls (side-by-side screenshot).

### M1 — Pilot: UnitText (541 lines, balanced)
- Convert its plain toggles/sliders/segments to spec rows.
- Keep any custom funcs as-is, referenced from rows.
- Acceptance (parity gate, visual + workflow first):
  - same controls, order, spacing, labels (screenshot diff)
  - every toggle/slider/dropdown changes the same DB key + same apply reason
  - Search still finds the same controls
- Target: ~541 → ~330–360 lines.

### M2 — Boilerplate-dense pages
- GroupLayout, GroupBars, GroupIndicators, UnitFrameVisuals, UnitStatusSection.
- One page per change, each with its own before/after screenshot.

### M3 — Mixed pages (partial)
- GlobalFonts, GlobalBars, UnitSections: spec the plain controls, leave
  custom logic alone.

### M4 — Heavy-logic pages
- Auras, Group, AdvancedColors, Unit: usually NOT worth specing. Only migrate
  obviously repeated rows. Stop early if parity risk rises.

## Hard rules (so we don't repeat Menu3)

1. UI core files are untouched. If a parity gap appears, fix the spec
   renderer to match the core — never the reverse.
2. One page per commit. Each commit ships a before/after screenshot.
3. Visual + workflow parity is the gate, not line count. Lua parse + action
   inventory are necessary but not sufficient.
4. If a page resists speccing, that's a signal it's real behavior — leave it.
5. No new entry point. Menu2 stays the visible, shipping menu the whole time.

## Pilot decision

Start with **UnitText**. Balanced bind/custom ratio: proves specs shrink
boilerplate AND coexist with hand-written logic. Runner-up: GroupLayout.

---

## MEASURED REALITY (updated after reading the real code)

The line-count table above was misleading. After reading the actual pages
(UnitText, GlobalFonts, GlobalBars, GroupIndicators, UnitFrameVisuals,
AdvancedGameplay) and measuring widget/layout/gate density, the picture is:

### What does NOT shrink the pages

1. **A generic vertical control renderer (`b:Rows`).** Most pages use manual
   pixel-positioned multi-column card layouts, not auto-flow stacks. A blunt
   renderer only fits the few already-small pages.

2. **A declarative card layout spec, applied broadly.** Measured: most cards
   hold only 1–4 controls (placements/card ratio 0.4–1.4). The pages already
   collapsed repetition into one-line local closures (`BindPortraitSlider(...)`).
   A spec row with get/set closures is LONGER than that one-liner. Proof: a 4-line
   Geometry card became 19 lines. Break-even is ~6+ controls/card; only
   AdvancedGameplay (7.0) and UnitStatusSection (4.2) clear it. Rolling card
   specs out broadly would GROW the Pages — the Menu3 trap again.

### What DOES shrink the pages (the real lever)

**Shared logic, not layout.** Measured duplication across Pages:
- 91 `SetControlEnabled` + 60 `SetControlsEnabled` calls
- 22 RefreshProxy/refresh-closure wirings
- The single most repeated shape is the "master toggle gates a dependent
  control group" idiom (~3 lines each), appearing dozens of times.

### Infrastructure built (additive, no page is forced to use it)

1. `W.BuildCard(ctx, parent, spec)` + `b:Card(spec)` in Widgets.lua —
   pixel-faithful card renderer (firstRowY/rowGap/width reproduce exact coords).
   Use ONLY for the 2–3 genuinely dense cards. Not a broad rollout.

2. `M.BindGateGroup(ctx, source, entries, opts)` in Support.lua — collapses the
   gate-group idiom from ~3 lines to one declarative row and absorbs the
   RefreshProxy/TrackRefresh wiring. This is the real reduction lever.

### Proof completed

AdvancedGameplay `disabledRefresh` (10 gates) converted to `BindGateGroup`:
net −8 lines, behavior verified gate-by-gate identical. `luac -p` clean.

### Realistic revised target

Pages reduction comes from migrating the gate/refresh idiom (and pushing more
pages onto GroupPage/UnitSectionShared), NOT from layout specs. Estimated
realistic Pages reduction is **lower than 35–45%** — more like 15–25% — because
the pages are already heavily factored. Honest number beats the original guess.

### Migration order for the gate lever (one page per commit, parity-gated)

1. AdvancedGameplay — DONE (proof).
2. UnitFrameVisuals, AdvancedClassPower (27 gate calls each).
3. GlobalBars (23), UnitText (13), UnitStatusSection (13).
4. Remaining pages with refresh closures, stopping where a page's gate logic
   is too entangled to express declaratively (leave those as-is).

---

## FINAL MEASURED RESULT (after migrating 4 pages)

Even the gate lever does NOT deliver 15-25%. Measured net line change:

| Page              | Net lines | Note |
|-------------------|-----------|------|
| AdvancedGameplay  | -8        | real win: flat closure with the repetitive `local xOn; SetControls(group,xOn); SetControl(enable,true)` 3-line-per-gate pattern |
| GlobalBars        | -2        | only 3 clean closures converted; 4 hybrid (gate+sideeffect) left as-is |
| AdvancedColors    | -1        | small flat closures |
| UnitFrameVisuals  | +2        | notice-block side effects moved into `also`, no shrink |
| AdvancedClassPower| +15 -> REVERTED | already dense; state-table prelude made it longer |

Pages net ≈ **-9 lines**. Plus infra: BindGateGroup +51 (Support),
BuildCard +141 (Widgets, currently unused by any page).

### The honest conclusion

`M.BindGateGroup` only shrinks ONE closure shape: the repetitive per-gate
`local xOn = cfg.x; SetControlsEnabled(group, xOn); SetControlEnabled(enable, true)`
pattern. Every other page already writes its gate closures densely (shared head
vars, single-line gates), so a declarative spec is LONGER there.

Menu2's Pages were already squeezed by the earlier "reduced boilerplate" commits.
The 15-25% reduction target does not exist in this code anymore. Decision (user):
keep the conversions for consistency, not for line count. BindGateGroup stays as a
reusable helper; BuildCard stays as infra for any future dense card.

Behavior of all 4 converted pages verified gate-by-gate identical; all `luac -p`
clean. No regressions introduced.
