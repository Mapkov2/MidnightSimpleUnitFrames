# MSUF PTR 12.1 Improvement Audit

Date: 2026-07-21  
Checkout: `6.0-beta-branch` at `a5af1c2897f4512f5011eaeddf5041fa994a1c8c`  
Addon target: Interface `120100`, version `6.0-beta25`  
PTR source: local `wow-ui-source-ptr`, build `12.1.0 (68745)`, commit `b5547c...`; the local mirror matched its configured remote when checked.

## Executive verdict

The current runtime architecture does **not** need a broad performance rewrite. It already uses compiled update routes, shared route snapshots, event narrowing, cached visual writes, active-only drivers, and complete disabled-state teardown. The full current core suite passed **142/142** Lua 5.1 smoke tests, and all 250 core Lua files passed real Lua 5.1 loadability.

The best next PTR work is:

1. Fix the current localization/static-gate failure before release.
2. Add health-text hide-at-max/threshold through the existing compiled text runtime.
3. Add the same mechanism for power text only as an explicit, resource-aware option.
4. Capture a fresh Menu2 trace on the current code before making another Menu2 optimization.
5. Fix Perfy source-path normalization so baseline/candidate function diffs are trustworthy.
6. Add automatic crowd-control emphasis using Blizzard's native `CROWD_CONTROL` candidate filter.
7. Add an event-driven standalone group combat indicator.
8. Add fit-to-area group scaling as an optional OOC/layout feature.
9. Treat friendly group-pet frames and arena frames as separate, staged projects.

## Current release blockers

### P0.1 - Restore the localization gate

The current full static check stops in `full_menu_locale_coverage_smoke.py`:

- `enUS` and `enGB`: 64 missing menu keys each.
- The other ten shipped locales: 60 missing keys each.
- First reported keys include ` matching color`, ` matching colors`, `1 px`, `100%`, and `2 px`.

This appears in the current dirty worktree containing ongoing Menu2/text work, so it should be resolved before packaging rather than attributed to the clean branch commit. The appropriate correction is to distinguish actual translatable UI strings from formatting fragments and to add every real label through the existing locale path. Do not weaken the gate to make the failure disappear.

### P0.2 - Obtain a current Menu2 performance baseline

The last valid five-second Menu2 trace recorded:

- 639.491 ms total addon CPU, or 127.888 ms/s during the captured construction scenario.
- 20.46 MiB allocated, or 245.519 MiB/min when extrapolated from that deliberately short construction window.
- Compared with its baseline: CPU -9.7%, allocation -15.7%.

That trace was captured at 15:46. Commit `7e5445a8` (`perf(menu2): reduce page construction and preview work`) landed later and changed lazy page construction, preview work, font collection, control-catalog metadata, themes, and search registration. Therefore the old trace is useful historical evidence but **cannot identify the current top Menu2 function**.

Required next measurement, only when a new Perfy capture is explicitly requested:

1. Use the exact same five-second Menu-open/page-construction scenario.
2. Capture the clean current candidate and a stable baseline with identical profile/UI state.
3. Compare total CPU, allocation, calls, and top self-time.
4. Change only one coherent cause before the next capture.

### P0.3 - Canonicalize function identities in the Perfy analyzer

The current comparison treats temporary package roots such as `perfy-build-20260721-144903` and `perfy-build-20260721-153831` as different function identities. The report consequently shows the same function as one `-100%` row and one `n/a` row. Normalize paths at least from `/AddOns/<addon>/...` before comparison. Until that is fixed, trust aggregate before/after CPU and allocation, but not the per-function delta table.

## Features to implement now

### P1.1 - Hide health text at max or above a threshold

This is fully possible on 12.1 and is the strongest low-risk feature addition.

Recommended UI:

- Per health-text slot: `Always`, `Hide at 100%`, or `Hide at/above N%`.
- Default: `Always`, preserving every existing profile.
- One shared threshold control can be offered in Quick Settings; per-slot override can remain in the advanced text page.

Recommended runtime design:

1. Compile the option in `CompileTextRuntime`; do not inspect DB settings during health events.
2. Cache one Blizzard step curve per integer threshold.
3. Select a health-text updater variant when applying the profile.
4. Call `UnitHealthPercent(unit, true, curve)` only for an enabled visibility rule.
5. Feed its 0/1 or secret evaluated result directly into `FontString:SetAlpha`.
6. Reuse one curve result for every slot sharing the same threshold.
7. Restore alpha to 1 on disable, profile replacement, or slot-mode changes.

Performance contract:

- Disabled: zero added event branches, zero added API calls, zero polling, zero allocations.
- Enabled: normally one native percentage/curve evaluation per health event plus one to three `SetAlpha` calls.
- If the displayed mode already needs the raw health percentage, secret-value rules may still require a separate curve-evaluated percentage call; do not compare or branch on the secret in Lua.
- Absorb-only text should not be hidden by the health rule unless the user explicitly enables that behavior.

PTR API evidence:

- `UnitHealthPercent(unit, usePredicted, curve)` returns the curve-evaluated result and is marked for secret returns.
- `SimpleRegion:SetAlpha` accepts secret alpha arguments and carries the alpha aspect C-side.
- The former expiration-timed full-frame Spell Indicator experiment was removed: secret group-aura duration cannot reliably drive an arbitrary external frame effect without a restricted bridge or recurring polling.

### P1.2 - Add resource-aware power-text threshold hiding

`UnitPowerPercent(unitToken, powerType, unmodified, curve)` provides the equivalent 12.1 primitive. The implementation should reuse the health feature's compiler and curve cache, but its UX must be resource-aware:

- Mana/energy/focus: `Hide at max` is intuitive.
- Rage, runic power, insanity, fury, maelstrom, and similar builder/spender resources: remain off by default and require an explicit choice.
- Alternate mana and class-resource bars should keep independent settings.

It must use the same disabled-zero-overhead contract and must not add a generic power polling driver.

### P1.3 - Automatic crowd-control emphasis

MSUF already accepts Blizzard's native `CROWD_CONTROL` Aura candidate filter. Turn that into an optional automatic presentation preset:

- Full-frame border/glow/tint, or a centered icon.
- Optional priority over normal spell-indicator placements.
- Scope controls for party, raid, target, and focus.
- Use the native candidate group and existing spell-indicator/frame-effect machinery; do not scan auras in Lua or maintain a broad manual spell list.

This should have zero work when disabled and only native Aura-container/event work while enabled.

### P1.4 - Standalone group combat indicator

Group frames currently have role, leader, assist, raid marker, ready check, summon, resurrection, PvP, phase, and status text, but no independent combat-status icon. Add it as another compiled group status region:

- Listen only to the relevant `UNIT_FLAGS`/roster lifecycle events when enabled.
- Use `UnitAffectingCombat(unit)` on those events.
- Reuse the existing icon style, anchor, layer, cached visibility, preview, copy/reset, locale, and Assistant metadata contracts.
- Do not attach a ticker.

### P1.5 - Optional fit-to-area group scaling

The current group-size breakpoints are already good (`1-10`, `11-20`, `21-25`, `26+`). Add a separate `Fit available area` mode for users whose chosen frame dimensions, spacing, and column count still overflow:

- Recalculate only on roster/topology, display-size, UI-scale, profile, or Edit Mode changes.
- Apply only out of combat; coalesce one post-combat apply.
- Solve from compiled frame dimensions and available bounds, not from a continuous frame scan.
- Keep the existing breakpoints as the predictable default.

## Larger feature projects

### P2.1 - Friendly party/raid pet frames

The PTR secure templates explicitly support pet unit suffixing and map `raid1pet` to `raidpet1`, so a parallel secure group header is feasible.

Recommended scope:

- Separate, optional pet header linked to the party/raid layout.
- Reuse a reduced MSUF unit spec: health, name, range, dispel/status, click casting.
- Default off; create no pet frames or subscriptions while disabled.
- Compile a smaller event route than full player frames.
- Test vehicles, missing pets, roster churn, combat lockdown, click casting, and raid scale transitions.

This is useful but touches secure header ownership, so it should not be bundled with unrelated PTR polish.

### P2.2 - Arena frames, staged

MSUF has no arena1-5 frame family. PTR still has Blizzard's `CompactArenaFrame` with pre-match, stealthed, debuff, CC-remover, castbar, and visibility behavior. A safe project should be staged:

1. First evaluate an optional MSUF placement/skin layer over the native compact arena frame.
2. Only build fully owned MSUF arena frames if the native layer cannot meet the product goal.
3. Keep the module unloaded/inert outside arena use.
4. Validate pre-match identity, stealth, CC-remover cooldowns, casts, spec/class presentation, targeting/click actions, Edit Mode ownership, Blizzard suppression/restore, and combat lockdown in-client.

This is high user value for PvP but high regression/security risk. It is not a small pre-release patch.

### P2.3 - Group portraits and detached group power

Group portraits are absent even though normal unit portraits and portrait event handling exist. Detached group power is also much less flexible than normal unit-frame power placement.

If implemented:

- Default off and compile away all portrait/power-specific events when off.
- Share portrait media and identity caches, but use a reduced group-specific runtime.
- Avoid 3D PlayerModel portraits on 20-40 raid members; prefer 2D/class portraits.
- Lazy-create portrait/decorative regions only for enabled scopes.
- Validate range fade, opacity exclusion, frame effects, text layers, and auto scale.

These are visual completeness features, not performance priorities.

### P2.4 - Spec-aware healer indicator presets

The current placed indicators and frame effects are powerful but configuration-heavy. Add declarative per-spec presets that seed existing spell-indicator rules without creating a second runtime:

- Preview the exact rules before applying.
- Store normal spell-indicator configuration after opt-in.
- Version preset data independently from the runtime.
- Never overwrite customized rules during upgrades.

### P3 - Optional layout/presentation backlog

Lower priority, demand-driven additions:

- Center-out party growth or additional secure grid ordering modes.
- Per-spec group range-spell override, retaining the current automatic fallback.
- Vertical health/power bar orientation.
- Animated dispel presentation using C-side `AnimationGroup`, active only while shown.
- Custom group labels/subgroup formatting.

Avoid health-drain/trailing animations unless users clearly want them and a measured, active-only implementation is available; they naturally introduce continuous update work.

## Performance work after a fresh trace

### Menu2

Only pursue items that remain visible in the new trace:

1. Keep hidden pages virtual; build controls and native previews only when first shown.
2. Pool/reuse group/unit preview handles when switching scope instead of creating equivalent decorations again.
3. If superellipse creation is still material, reduce the number of six-texture pills or use a cheaper style for dense rows. Existing per-frame reuse already prevents repeated creation after first build.
4. Cache successful font verification per applied font key. Re-run `GetFont`/`GetStringWidth` only for a new key, explicit force, or a detected external mutation.
5. Gate theme/gradient/layout passes by a theme revision and geometry revision so a refresh that changes data does not repaint unchanged chrome.
6. Keep control-catalog command metadata lazy and explicit IDs on the fast registration path, as introduced by `7e5445a8`.
7. Keep slider dragging preview-only and commit one bounded runtime apply at release/debounce.

### Runtime

The valid rapid-target-swap trace is already low: 57.060 ms total over 20.003 seconds (2.853 ms/s) and 8.6 KiB allocated. It does not justify a broad Core/Text/Aura rewrite.

Potential micro-candidates, only after an exact scenario proves material impact:

- `SetFrameAlpha` verifies `GetAlpha()` even when its ownership cache matches. A forced/cold verification path and a trusted hot ownership path could avoid the native read, but the observed absolute cost was only 2.727 ms over 20 seconds.
- Prediction `UpdateFull`/`UpdateCalc` and health-percent allocation should be revisited only in a heal/absorb-heavy raid trace, not inferred from target swapping.
- Do not restore an expiration-timed full-frame Spell Indicator driver. Keep full-frame effects on native AuraSlot ancestry for active-aura visibility; native cooldown, duration text, and duration bars remain the supported timing surfaces.
- Target sound's observed self-time was allocation-free and dominated by native calls. Leave it alone unless a sound-disabled/current trace says otherwise.

## Code-quality work

1. Keep the real Lua 5.1 compiler gate mandatory; it currently passes all 250 core files.
2. Keep the explicit 142-test core manifest mandatory and add focused tests for every new compiled feature.
3. Restore the locale gate rather than exempting newly added labels/fragments.
4. Add a PTR API contract check that records the mirror build/commit and verifies every secret-value sink used by health, power, auras, status bars, colors, and alpha.
5. Gradually consolidate duplicated setting definitions across defaults, runtime compiler, Menu2, preview, copy/reset, localization, and Assistant metadata into declarative field specs. Migrate one feature family at a time with equivalence tests; do not perform a whole-addon schema rewrite.
6. Preserve the cold-compiler/hot-executor boundary: DB normalization and option branching belong at apply time, not in unit events.
7. Require every feature to declare events, unitless events, optional timers, teardown, and post-combat replay behavior.
8. Use the keyed scheduler for genuinely duplicate next-frame work, but do not convert every timer mechanically.
9. Retire compatibility globals only at an explicit migration/version boundary with profile/import tests.
10. Repair the Graphify helper environment by pinning/locating its required 64-bit Python, so architectural queries do not silently fall back during future audits.

## What is already implemented and should not be rebuilt

- Native Aura-container ownership, validated filters, `CROWD_CONTROL`, max-duration filters, and secret-safe Aura rendering.
- Active-aura spell-indicator frame effects, native duration bars, and animated icon glow.
- Temporary maximum-health reduction overlay, default off.
- Priority Frames with secure headers, event-driven updates, and zero polling.
- Group-size auto-scaling breakpoints.
- Group role/status/threat/dispel indicators and flexible grid columns/growth.
- Compiled health/power/text update plans and interned event routes.
- Event-driven range handling with full shutdown.
- Active-only castbar, class-resource, Edit Mode, and preview drivers.

## Explicit non-recommendations

- No direct Aura scanning or revival of an older Aura engine beside Auras3.
- No new permanent `OnUpdate` for health, power, combat status, range, priority frames, or layout.
- No Lua comparison/branch on secret health, power, or duration values.
- No threshold-triggered Aura sound based on secret remaining duration; the current API offers a safe visual sink, not a safe Lua decision callback.
- No combinatorial explosion of specialized Core closures without a measured A/B win.
- No large file split or global rename merely to reduce file length.
- No claim of `maximal performance` from smoke tests alone; exact in-client before/after traces remain required.

## Verification performed for this audit

- Branch/version/PTR mirror and dirty-tree boundary checked.
- Local PTR source used for `UnitHealthPercent`, `UnitPowerPercent`, `SetAlpha`, `SetAlphaFromBoolean`, `LuaDuration`, secure group headers, and native arena behavior.
- Full core Lua 5.1 smoke manifest: **142 passed, 0 failed**.
- Focused disabled lifecycle, runtime perf, route interning, Menu2 hotpath, aura seed-cache, and secret group-health tests: passed.
- Core Lua 5.1 loadability: **250 files passed**, 0 BOMs stripped.
- Static checker: stopped only at the current Menu2 locale-coverage failure described above; it is not green.
- Existing Perfy sessions were inspected read-only. No new package or trace was created.
- Graphify query was attempted but unavailable because its pinned 64-bit Python 3.13 runtime was missing; cross-file conclusions were rechecked directly in source instead.

## Recommended delivery order

1. Finish current Menu2/text work and restore localization/static green.
2. Implement health hide-at-max/threshold with focused secret/runtime/menu/preview tests.
3. Optionally extend the same compiler to resource-aware power text.
4. Explicitly request and capture the current Menu2 A/B trace; fix the analyzer's path identity first or alongside it.
5. Optimize only the new top measured Menu2 cause.
6. Add automatic CC emphasis and group combat indicator as separate sub-commits.
7. Add fit-to-area scaling as another isolated feature.
8. Scope group pets, arena frames, and group portraits as separate projects with in-client secure-frame test plans.
