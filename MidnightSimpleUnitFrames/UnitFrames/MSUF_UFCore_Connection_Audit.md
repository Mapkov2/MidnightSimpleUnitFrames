# MSUF UFCore connection audit

Created: 2026-07-07
Backup before this work:
`C:\MSUF Beta Branch\MidnightSimpleUnitFrames\_backups\MidnightSimpleUnitFrames-pre-core-connect-20260707-194655.zip`

Goal:
Connect all UnitFrame and GroupFrame features, options, previews, and frontend apply paths to the new embedded UFCore without regressing current performance. Hotpaths must stay event-driven and direct. Coldpath work must absorb layout, settings compilation, expensive scans, preview rebuilds, and profile/menu apply work.

## PTR API anchors

Source repo: https://github.com/Gethe/wow-ui-source/tree/ptr

Checked files:
- `Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua`
- `Interface/AddOns/Blizzard_UIPanels_Game/Shared/CastingBarFrame.lua`
- `Interface/AddOns/Blizzard_UnitFrame/Shared/CompactUnitFrame.lua`
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/CurveUtilDocumentation.lua`
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/LuaColorCurveObjectAPIDocumentation.lua`

Relevant findings:
- Secure unit clicks are attribute driven: `SecureUnitButton_OnLoad` sets target/menu attributes, not Lua target handlers.
- Castbar target name is native: `UnitShouldDisplaySpellTargetName`, `UnitSpellTargetName`, `UnitSpellTargetClass`.
- Health gradient color is native for live units: `UnitHealthPercent(unit, true, colorCurve)` accepts a `LuaColorCurveObject` created through `C_CurveUtil.CreateColorCurve()`.
- Blizzard unitframe style uses `RegisterUnitEvent` for unit-filtered events.
- Compact frames update only the event-specific component instead of running a broad refresh.

## Current core load state

New owner boundary:
- `UnitFrames/Embeds/MSUF_UFCore/MSUF_UFCore.lua`
- `MSUF.UFCore`, `MSUF.UF`, `MSUF.GF`

Currently loaded through the embed:
- Core: `MSUF_UF_Secrets`, `Apply`, `Metadata`, `Layers`, `Core`, `Runtime`, `Config`
- Basic elements: bars common, health, power, text common/format/layout/runtime, load conditions
- Factory: `MSUF_UF_Factory`
- Group base: group DB, config, headers, adapter, Blizzard ownership, metadata, runtime

Important caveat:
The embed owns loading, but several modules are still old implementation files under `UnitFrames/Engine`. That is acceptable short term, but final code should not be a collection of bridges around external globals.

## Connection matrix

| Area | Current state | Target state | Risk |
| --- | --- | --- | --- |
| Health | Core element | Keep direct UF element | Low |
| Power | Core element | Keep direct UF element | Low |
| Text | Core element, but still has dispatch-named cache fields | Keep hot compiled writers; clean names later only if no perf loss | Medium |
| Load conditions | Core element | Keep; combat-safe driver updates only | Low |
| Borders/Status/Prediction/Alpha | Loaded as optional UF elements through the embed; activated only when `IsEnabled` passes | Keep event lists option-scoped and coldpath-applied | Medium |
| RangeFade | Loaded as optional UF element; driver is created only when active frames register | Keep polling dormant when disabled | High |
| GroupRangeFade | Loaded as optional group UF element | Keep settle/offline drivers registration-count gated | High |
| Auras3 | Registered as `UF.RegisterElement("Auras")`; backend remains separate, frame resolution is Core-first, and scoped coldpath apply is available through `RequestScope`/`MenuModel.Apply` | Keep global `RequestApply` only for true profile/global resets | High |
| Castbars | External runtime; frame anchoring, unit-specific menu apply, and unit-scoped UF visual refresh are Core-first/coldpath; live spellcast path remains external and event-driven | Rewrite as proper UF element only if it can preserve the current direct spellcast path | High |
| ClassPower | External runtime; frame resolution is Core-first, Menu2/Assistant/Preview/Profile apply paths use `MSUF_ClassPower_Apply(opts)`, and player UF visual refresh is connected through `UF.RegisterVisualRefreshCallback` | Rewrite as player UF element only if it keeps the current direct event runners | High |
| Group headers | Core group base is connected | Keep secure header work coldpath/combat-deferred | Medium |
| Group visuals/status/indicators | Loaded as group UF elements and included in group structure/dirty masks | Keep dirty-mask application precise | High |
| Group targeted spells | Separate party-only subsystem; Assistant settings now use a direct `targetedSpells` coldpath and the `GF.RefreshVisuals` hook is dirty-mask aware | Keep runtime event tracker separate; do not fold enemy nameplate scanning into generic GF refresh | Medium |
| Rounded frames | Loaded late as optional effect; unitframe iteration is Core-first and unit visual refresh is connected through `UF.RegisterVisualRefreshCallback` | Keep enable/disable/profile applies broad; keep normal visual refresh unit-scoped | Medium |
| Menu2 apply | Broad `UF.ForceUpdate(nil)` calls removed from Menu2/Assistant; normal GF GroupPage/Assistant applies now use dirty masks including combined masks; group-copy without `general` scope is dirty-mask based; undo/rebuild/aura refresh-all paths remain | Route remaining group/aura applies through dirty masks where semantically safe | High |
| Unit preview | Separate preview renderer; live frame reads are now Core-first with old globals only as fallback | Keep separate from combat core; share compiled specs/helpers only | Medium |
| Group preview | Separate preview renderer using GF APIs | Keep separate from combat core; share GF compiled specs only | Medium |
| Diagnostics | ClickCoreProfiler file exists but is no longer loaded by the main TOC | Keep diagnostics manual/external only; never in hotpath by default | Low |

## Rules for migration

1. No new work in click or target-change hotpath unless it is a direct native API read for the affected unit.
2. No broad `UF.ForceUpdate(nil)` from menu/frontend when a dirty mask can target one element/unit.
3. No C_Timer zero-delay fanout in combat hotpaths. Zero-delay is acceptable in menu/preview/coldpath if coalesced.
4. Every feature must be one of:
   - core element,
   - explicit coldpath service,
   - external system with small core API,
   - not connected and documented.
5. Existing performance is the baseline. If a migration adds measurable click/target/cast overhead, revert that piece and mark it not connected.

## First implementation targets

1. Replace legacy `_G.MSUF_UnitFrames` reads in non-hot systems with `MSUF.UF.GetFrame`/`MSUF.UF.frames`.
2. Replace Castbars/ClassPower bridge queue behavior with explicit coldpath apply hooks.
3. Load or explicitly reject existing UF element files: Alpha, Borders, Prediction, StatusIndicators, RangeFade, GroupRangeFade, GroupVisuals, GroupStatusRuntime, GroupCornerIndicators.
4. Convert Menu2 apply calls to dirty masks where possible.

## Completed in this audit pass

- Removed `Features/Diagnostics/MSUF_ClickCoreProfiler.lua` from the normal TOC load path.
- Split the Core element gates after a performance regression: `UF.CoreElementAllowed` is again the strict Basic-only hotpath gate, while `UF.ApplyElementAllowed` is the wider coldpath/apply gate backed by metadata owners/masks. Optional real UF elements can still be applied deliberately, but they must not automatically enter the per-unit event path.
- Loaded optional single-frame elements through `MSUF_UFCore_Elements.xml`: Visuals common, Portrait, Prediction, StatusIndicators, Borders, Alpha, RangeFade.
- Loaded optional group elements through `MSUF_UFCore_Group.xml`: Config indicators, GroupRangeFade, GroupVisuals, GroupStatusRuntime, GroupCornerIndicators.
- Expanded the group structure apply mask so secure header children receive the optional group elements during coldpath structure apply.
- Fixed deferred element refresh gating to use `UF.CoreElementAllowed`, so optional Core elements queued during combat are not dropped after combat.
- Converted non-hot frame lookups to Core-first in Menu2 scale/preview, Unit preview runtime/castbar preview, preview animation/diagnostics, castbar preview/anchor helpers, boss castbar preview, Auras3 edit/runtime frame resolution, Gameplay combat-timer anchoring, Highlight, Rounded Frames, BugReport diagnostics, and ClassPower frame lookup fallbacks.
- Removed remaining broad `UF.ForceUpdate(nil)` calls from Menu2/Assistant color/bar apply paths and replaced them with targeted border/highlight refreshes.
- Narrowed normal Assistant group visual/font/border/color applies to GF dirty masks. Rebuild/undo paths remain broad because they intentionally span multiple DB domains or lack changed-domain metadata.
- Narrowed GroupPage queued applies to combined GF dirty masks. `visual`, `font`, `color`, `border`, and `auras` now collapse to one explicit mask instead of falling back to unmasked `RefreshVisuals`.
- Narrowed GroupPage and Assistant group-copy applies: copy with `general` scope still rebuilds secure headers, but copy scopes without `general` now use `DIRTY_CONFIG` or narrower `DIRTY_FONT`/`DIRTY_BORDER`/`DIRTY_AURAS` masks.
- Added combined dirty-mask resolution in `GF.ApplyMaskForDirtyMask` and post-combat `GF.DeferGroupRuntime` mask merging, so multiple queued group refreshes do not overwrite each other before `PLAYER_REGEN_ENABLED`.
- Added unit-specific castbar visual apply through `MSUF_ApplyCastbarVisualsForUnit` and routed `MSUF_ApplyCastbarUnitAndSync` through it for player/target/focus option changes. Login/profile-wide castbar refreshes remain broad by design.
- Changed target/focus castbar driver anchoring to resolve unitframes through `MSUF.UF.GetFrame` first.
- Changed castbar width-source and anchor frame resolution in `MSUF_CastbarAnchors.lua` to resolve unitframes through `MSUF.UF.GetFrame` before falling back to legacy unitframe tables/globals. This keeps castbar match-width/anchor coldpaths aligned with the embedded UFCore owner.
- Added `MSUF_ClassPower_Apply(opts)` as the ClassPower coldpath API. Structural changes still call one full refresh, while visual/color/font/player-HP/CDM-width changes can now use smaller explicit flags. Menu2 ClassPower controls, Assistant domain/color apply, reset fanout, preview handles, and late anchor reanchor now route through this API.
- Fixed the ClassPower charged-color cache invalidation scope so color fanouts invalidate the actual local cache instead of a global fallback.
- Added `A3.RequestScope(scope, reason)` for targeted Auras3 coldpath refresh without breaking legacy `RequestApply(reason)` call sites. Unit-copy and Assistant aura fallback paths now use the scoped API when available.
- Reduced Aura color fanouts so they no longer run a full shared Aura apply and then a second `ApplyFontsFromGlobal` refresh. Color changes now use one native visual-generation bump/refresh plus the needed group cooldown-text recolor.
- Made Assistant aura apply return whether it actually refreshed Auras3; group aura fallback is now dirty-mask `auras` only and only runs when Auras3 cannot apply the scope.
- Added `GF.TargetedSpells.RequestApply` and a dedicated Assistant `targetedSpells` group apply mode. Party targeted-spell settings now refresh the targeted-spells controller directly instead of flowing through generic `visual`/`geometry` group refreshes.
- Narrowed the targeted-spells `GF.RefreshVisuals` wrapper so it only reacts to party/global dirty masks that can affect targeted-spell placement or runtime ownership; font/color/border/aura-only group refreshes no longer re-read targeted-spell settings.
- Connected RoundedFrames to the UFCore visual-refresh callback list. Normal `UF.RefreshVisuals(unit)` now reapplies rounded unit masks only for that unit; enable/disable/profile paths still use the existing full rounded apply because they create/remove optional regions.
- Narrowed unit-scoped castbar applies in `MSUF_Menu2_ApplyService`: `RequestUnit(unit, { castbar = true })` now calls `MSUF_ApplyCastbarUnitAndSync(unit)`/`MSUF_ApplyCastbarVisualsForUnit(unit)` instead of promoting the change to global `MSUF_UpdateCastbarVisuals`.
- Registered a Castbars UF visual-refresh callback. Unit-scoped `UF.RefreshVisuals(unit)` can now refresh that unit's castbar visuals, while global `UF.RefreshVisuals(nil)` intentionally does not fan out into all castbars.
- Registered a ClassPower UF visual-refresh callback. Player-scoped `UF.RefreshVisuals("player")` now runs `MSUF_ClassPower_Apply({ visuals = true, playerHP = true })`, avoiding full ClassPower rebuilds for visual-only player refreshes.
- Reduced ClassPower profile/integration coldpaths to prefer `MSUF_ClassPower_Apply({ full = true, cdm = true })` with legacy `Refresh`/`RefreshTextures`/`RefreshCDMWidthBindings` fallbacks only when the new API is absent.
- Narrowed the UFCore ClassPower bridge ownership path. The first enable/disable transition still runs the full ClassPower rebuild because it can create/hide resources and rebind structural events, but unchanged player Core applies now use a lightweight `anchor`/geometry apply instead of `full=true`. Late anchor reanchor and third-party anchor proxy refreshes also use this lightweight path, with full refresh only as the legacy fallback.
- Narrowed remaining player-power and preview ClassPower relayout fanouts. `RequestUnit("player", { power = true })`, class-power preview handle applies, and unit-preview class-power offset writes now use `MSUF_ClassPower_Apply({ anchor = true, cdm = true, playerHP = true, syncNow = false })` instead of a full rebuild. Explicit ClassPower/profile/page-reset paths still use `full=true`.
- Narrowed EditMode castbar anchor toggles to `MSUF_ApplyCastbarUnitAndSync(unit)` instead of global castbar visual refresh.
- Narrowed EditMode HUD group-position reset to `GF.RefreshGeometry(kind)` instead of full group refresh when the native GF API is available.
- Reduced Auras3 profile-import apply from `RefreshAll()` plus `ApplyFontsFromGlobal()` to one `ApplyFontsFromGlobal(nil, "MSUF_PROFILE_IMPORT_AURAS")` call with `RefreshAll` fallback.
- Made `GF.RefreshGeometry(kind)`/`GF.RefreshHeaderLayout(kind)` kind-aware. Party geometry changes no longer need to touch raid/mythicraid headers, and raid/mythicraid geometry changes no longer need to touch party headers.
- Narrowed EditMode group drag-end and group preview nudge finalization to `GF.RefreshGeometry(kind)`.
- Narrowed EditMode undo restores: castbar snapshots now reapply only `MSUF_ApplyCastbarUnitAndSync(unit)`, aura snapshots use `A3.RequestScope(unit)`/`RefreshUnit(unit)`, and group-frame snapshots use `GF.RefreshGeometry(kind)` plus a kind-scoped visual dirty pass where available. The old global refresh functions remain only as legacy fallbacks.
- Removed the unconditional `MSUF_UpdateAllFonts()` call from EditMode undo restore. Unit-frame undo now requests only the restored unit's text layout when available.
- Narrowed EditMode aura-preview toggles/sync/exit to `A3.RefreshEditPreview()` instead of full `A3.RefreshAll()` when that API exists. `RefreshEditPreview()` now hides preview groups while EditMode is inactive instead of rebuilding them.
- Narrowed Group Menu2 geometry flushes and EM2 group popup/nudge applies to pass the known group kind into `GF.RefreshGeometry(kind)`.
- Preserved group dirty masks through combat-deferred `layout` applies: `GF.DeferGroupRuntime("layout", kind, mask)` now runs the kind-scoped header layout and then the kind-scoped dirty visual pass after combat.
- Added `GF.Rebuild(kind)` for scoped group rebuilds. Menu2 group rebuilds and Assistant group rebuild/copy fallbacks now use the target kind when available instead of rebuilding every group header.
- Narrowed GroupFrames profile-import post-apply to the group kinds actually present in the import payload. It now uses `GF.Rebuild(kind)`/kind-scoped geometry+visual fallback instead of always calling global GF refresh.
- Narrowed the UF Castbars bridge so Castbar enable/disable queues only the affected unit through `MSUF_ApplyCastbarUnitAndSync(unit)`/`MSUF_ApplyCastbarVisualsForUnit(unit)` before falling back to global castbar visual refresh.
- Narrowed castbar preview fallback refreshes to `MSUF_ApplyCastbarVisualsForUnit(unit)` where available, including boss preview fallback, instead of immediately fanning out to every castbar.
- Narrowed castbar coldpaths further: driver login now applies player/target/focus through unit castbar APIs, boss castbar enable refreshes only boss visuals, global fill-direction refresh prefers unit visual applies for player/target/focus/boss, and boss `MSUF_ApplyCastbarUnitAndSync("boss")` now includes boss unit visual apply before returning.
- Narrowed remaining EditMode/Menu2 castbar fallback paths with known units: castbar popup apply, castbar anchor toggle, edit-mode nudge/drag fallback, and unit-preview handle moves now try `MSUF_ApplyCastbarVisualsForUnit(unit)` before falling back to global `MSUF_UpdateCastbarVisuals`.
- Narrowed Assistant EditMode aura-preview toggle to `A3.RefreshEditPreview()` with `A3.RefreshAll()` only as a legacy fallback.
- Added unit-scoped alpha refresh support. `UF.RefreshAlphas(unit)`, `MSUF_RefreshAllUnitAlphas(unit)`, `MSUF_RequestAlphaRefresh(unit)`, and Menu2 unit apply now refresh only the affected unit when a unit alpha/range-fade setting changes; global alpha refresh remains for profile/global operations.
- Removed the remaining global font refresh from the single-unit EditMode popup apply path. Unit popup changes now rely on the immediate unit apply plus `MSUF_ForceTextLayoutForUnitKey(unit)`.
- Routed Auras3 EditMode popup/nudge refreshes through `A3.RequestScope(unit, reason)` before falling back to `RefreshUnit(unit)`/`RefreshAll()`.
- Converted EditMode frame/cache/anchor resolvers to Core-first lookups (`UF.ForEachFrame`, `UF.GetFrame`, `UF.frames`) with old `_G.MSUF_UnitFrames` reads kept only as compatibility fallback.
- Reordered the Group EM2 geometry fallback so a scoped `GF.RefreshVisuals(kind, geometryMask)` is preferred before legacy `GF.RefreshAll()`.
- Reduced profile/runtime ClassPower fanout in Menu2 apply: `ApplyProfileFanout` now calls `MSUF_ClassPower_Apply({ full = true, cdm = true })` once and only falls back to legacy `Refresh`/`RefreshTextures`/`RefreshCDMWidthBindings` if the new API is missing.
- Fixed the Menu2 `classpower=true` apply flag. It is now copied into the coalesced pending-general state and runs `MSUF_ClassPower_Apply({ full = true, cdm = true })` unless the caller marks the runtime work as already done with `classpowerApplied=true`.
- Normalized ClassPower apply flag variants in Menu2 ApplyService. `classpower`, `classPower`, `classPowerPlayerHP`, `detachedPowerBar`, and `altMana` now coalesce into the ClassPower coldpath; `classPowerPlayerHP` can request the smaller `{ playerHP = true }` path unless a full ClassPower refresh is merged, and `classpowerApplied`/`classPowerApplied` avoids duplicate runtime apply after page-local handlers already ran.
- Narrowed profile/runtime Castbar fanout to per-unit `MSUF_ApplyCastbarUnitAndSync(unit)`/`MSUF_ApplyCastbarVisualsForUnit(unit)` for player/target/focus/boss before using legacy global castbar refresh.
- Extended UnitPreview refresh hooks to include `MSUF_ClassPower_Apply` and `MSUF_ApplyCastbarVisualsForUnit`, so new scoped coldpath APIs still refresh previews.
- Routed boss-preview aura refresh through `A3.RequestScope("boss", reason)` before lower-level `RequestUnit`/`RefreshUnit` fallbacks.
- Narrowed Menu2 general castbar flushes: pending castbar applies now run player/target/focus/boss through unit castbar APIs first, with `MSUF_UpdateCastbarVisuals` only as legacy fallback.
- Removed global castbar visual refreshes from Menu2 profile/restore fanout lists. Profile and restore fanouts now reuse the per-unit castbar apply loop.
- Added scoped font follower handling in `MSUF_FontRuntime`. `MSUF_UpdateAllFonts(onlyKey)` now keeps Castbar, Auras3, ClassPower, text relayout, and external gameplay/MSCB font followers scoped instead of fanning out globally; full font changes still refresh all followers.
- Reduced Global Castbar texture apply fanout. The Castbar page no longer calls immediate and deferred global visual refreshes before the ApplyService; it invalidates textures, refreshes boss preview, then lets the per-unit castbar apply loop run.
- Removed the zero-delay KickReady refresh from the Castbar active-start path. Target/focus/player cast starts now refresh KickReady synchronously for the active frame, while later interruptible/not-interruptible events still refresh the same frame directly.
- Trimmed CastbarEngine `BuildState` overhead by localizing WoW cast APIs and using a shared inactive state for no-unit calls. The existing same-frame state cache remains the main protection against repeated cast API reads during event bursts.
- Narrowed profile-import Auras3 post-apply when the import payload only touches `auras3.perUnit`. Those imports now call scoped `ApplyFontsFromGlobal(scope)`/`RequestScope(scope)`/`RefreshUnit(scope)` instead of a full Auras3 refresh; shared/general aura imports still use the full path.
- Narrowed profile-import unit alpha post-apply. Imports that touch alpha keys for specific unit configs now call `MSUF_RefreshAllUnitAlphas(unit)`/`MSUF_RequestAlphaRefresh(unit)` for those units; full-profile imports still refresh all unit alphas.
- Removed the implicit Menu2 ApplyService promotion from `applyAll=false` with unknown flags to `visual=true`. Menu-only, tooltip, locale, preview-only, and assistant control writes no longer fall through to global `MSUF_RefreshAllFrames`; callers that really need frame visuals must pass `visual=true`, `frames=true`, or a specific dirty flag.
- Tightened GroupFrame legacy fallbacks in EditMode HUD reset, EditMode group drag-end, EditMode undo, and profile-import apply. When `MSUF.GF.RefreshGeometry(kind)` is unavailable but exported legacy scoped functions exist, those paths now call `MSUF_GF_RefreshGeometry(kind)`/`MSUF_GF_RefreshUnitBindings(kind)`/`MSUF_GF_RefreshVisuals(kind)` before falling back to `MSUF_GF_RefreshAll`.
- Classified generated Assistant AutoCoverage applies for `general.*` keys. Generated Castbar, Color, Font/Text, Bar, Power, Aura, Portrait, ClassPower, alpha/range, and menu-only settings now route to the matching RegistryCore apply helper or explicit dirty flags; only unknown generated general keys request an explicit scoped `visual=true` apply.
- Made the legacy Castbar visual refresh export unit-aware. `MSUF_UpdateCastbarVisuals(unit)` now routes to the same per-unit coldpath as `MSUF_ApplyCastbarVisualsForUnit`, while `MSUF_UpdateCastbarVisuals()` remains the full global refresh. Castbar preview, boss preview, EditMode popup/nudge/undo, UF bridge, and UnitPreview fallback paths with a known unit now pass that unit instead of fanning out to every castbar.
- Tightened Assistant GroupFrame fallback applies. The central Assistant group apply helper normalizes `gf_*` scopes, routes rebuild/visual/font/color/border/aura modes through scoped `GF` APIs, and uses exported scoped legacy functions (`MSUF_GF_RefreshGeometry`, `MSUF_GF_RefreshUnitBindings`, `MSUF_GF_RefreshVisuals`) before falling back to `MSUF_GF_RefreshAll`. Assistant group-copy fallback now refreshes only the destination group kind, and non-structural copies avoid geometry/unit-binding refreshes.
- Made Auras3 EditMode boss scope explicit. `RefreshUnit("boss")`, `RefreshEditPreview("boss")`, `HideUnit("boss")`, and `UpdateUnitAnchor("boss")` now fan only to `boss1` through `boss5` instead of missing the preview scope or requiring broader `RefreshAll` fallbacks. This keeps boss aura preview/runtime refreshes aligned with the scoped `RequestScope("boss")` coldpath.
- Narrowed the Unit Status "Midnight Style" toggle. Changing `general.statusIconsUseMidnightStyle` from the Unit page now uses `applyAll=false` and relies on the dedicated StatusIndicators refresh (`MSUF_RequestStatusIconsRefreshForCurrent`) instead of promoting the menu write to a full unitframe apply.
- Made StatusIndicators refresh aliases unit-aware. Assistant per-unit status applies, Unit page status control changes, and single-target unit-copy status applies now pass the affected unit into the Core StatusIndicators refresh path and avoid duplicate specific+generic status refreshes; global status style/state changes and copy-to-all still call the aliases without a unit by design.
- Reordered the Unit page Auras3 copy fallback so `A3.RequestScope(unit, reason)` is preferred before lower-level `RefreshUnit`/`RequestUnit` fallbacks whenever `MenuModel.Apply` is unavailable. This keeps unit-copy aura refreshes on the scoped public coldpath and preserves the old global `RequestApply` only as the final legacy fallback.
- Scoped Global Bars groupframe visual/border refresh helpers to the current groupframe bars scope. Editing `gf_party` now refreshes only party group frames; editing `gf_raid` refreshes raid plus mythicraid to match the existing DB fanout; shared/global bar edits remain broad by design.
- Threaded explicit Bars scope metadata from the Global page into `MSUF_Menu2_ApplyService`. Queued bars applies now keep `gf_party`/`gf_raid` groupframe visual refreshes scoped when all queued bar changes share that scope, while mixed or legacy no-scope callers still fall back to the previous broad group refresh.
- Threaded explicit Font scope metadata from the Global page and unit apply queue into `MSUF_Menu2_ApplyService`. Unit font changes now call `MSUF_UpdateAllFonts_Immediate(unit)` and unit-scoped identity/power text color refreshes; groupframe font changes refresh only the matching group kind(s); mixed or legacy no-scope font callers remain broad.
- Made the UFCore color refresh exports accept an optional unit. `MSUF_RefreshAllFrameColors`, `MSUF_RefreshAllIdentityColors`, and `MSUF_RefreshAllPowerTextColors` remain global when called without a unit but can now be used by scoped coldpaths without fanning through every unitframe.
- Reduced Assistant/Menu color apply fanout. `MSUF_Menu2_ApplyService.RequestColors()` now treats a successful `MSUF._colorsAPI.PushVisualUpdates()` call as the authoritative color repaint path and no longer queues extra global font/bar refreshes in that case; missing or failed color API calls keep the old broad font/bar/color fallback behavior.
- Narrowed generated Assistant AutoCoverage applies for unit and group scopes. Generated unit settings now pass text/power/alpha/castbar/aura hints into `ApplyUnit` when the key family is identifiable; unit aura hints now route through scoped Auras3 apply before falling back to unitframe apply. Generated group settings now map keys to `fonts`, `colors`, `border`, `auras`, `geometry`, `rebuild`, or `visual` instead of always using the generic visual group refresh; status/icon/corner/highlight keys are explicitly visual so they do not trigger secure-header rebuilds.
- Made generated Assistant AutoCoverage fallbacks scope-aware. If a RegistryCore helper is unavailable, unit scopes call the unit-scoped UF refresh and group scopes call the matching scoped GF rebuild/geometry/dirty visual path instead of falling back to global `MSUF_RefreshAllFrames()`.
- Preserved combined group dirty masks through GroupPage queues, Assistant group fallbacks, and post-combat GF runtime merging. Geometry changes now carry geometry/layout masks into the scoped visual pass, while config masks stay authoritative when multiple deferred changes are merged.
- Added a castbar-unit coldpath queue to `MSUF_Menu2_ApplyService`. Assistant settings that already know the castbar unit now queue only `player`/`target`/`focus`/`boss` through `MSUF_ApplyCastbarUnitAndSync`/`MSUF_ApplyCastbarVisualsForUnit`; global castbar appearance, texture, FocusKick, profile, and restore paths remain broad by design.
- Made the bar texture runtime scope-aware. `MSUF_UpdateAllBarTextures_Immediate(scope)` and `MSUF_UpdateAbsorbBarTextures(scope)` now update only the requested UnitFrame scope, only the requested GF kind for `gf_party`/`gf_raid`, or all frames for shared/global callers.
- Made bar gradient refresh scope-aware. `MSUF_UpdateAllBarGradients(scope)` now refreshes only Health/Power on the requested unit scope, only the matching GF kind(s), or all frames for shared/global callers.
- Threaded Assistant scoped bar/font apply metadata into the ApplyService. `RegisterScopedSetting()` now passes the setting scope to apply helpers, Assistant `ApplyBars`/`ApplyBarGradients`/`ApplyFonts` forward it as `barsScope`/`fontScope`, and scoped reset actions reapply only the reset scope.
- Closed remaining direct Global Bars page no-scope applies for rounded bars and gradients. They now pass `CurrentBarsScope()` into the coalesced ApplyService and scoped gradient runtime call.
- Tightened the generated Assistant AutoCoverage unit fallback. If the curated RegistryCore helper is missing, generated unit settings now try `ApplyService.RequestUnit(scope, reason, UnitApplyOptsForKey(key))` and then `UF.Apply(scope)` before falling back to legacy `MSUF_RefreshAllFrames(scope)`.
- Narrowed generated Assistant `general.*` castbar coverage. AutoCoverage now resolves known Castbar DB keys to `player`/`target`/`focus`/`boss` and passes that unit into `ApplyCastbar`/`ApplyCastbarColors`; scoped castbar-color applies skip the global color push and queue only the matching Castbar unit refresh.
- Made `Auras3.RequestApply(scope, reason)` scope-aware while preserving old no-arg/reason-only global behavior. Aura helper and unit-copy fallbacks with a known unit now call `RequestApply(unit, reason)` instead of forcing a global `RefreshAll`.
- Narrowed Advanced ClassPower text applies. ClassPower text controls now rely on `MSUF_ClassPower_Apply({ fonts = true, text = true })` and no longer request a global UnitFrame font/text refresh from the general apply queue.
- Routed Advanced detached Player Power applies through the `player` UnitFrame apply queue. Detached power layout/text controls now call the scoped `MSUF_ApplyPowerBarEmbedLayout_ForUnitKey("player")` path, queue player-only text/font/power refreshes, and mark ClassPower as already handled so the player unit apply does not trigger an extra full ClassPower refresh.
- Made the UF border refresh runtime accept an optional UnitFrame scope. `UF.RefreshBorders(unit)` and the exported outline refresh aliases still refresh all frames when called without a unit, but can now refresh only `boss`/`player`/other config scopes when a caller already knows the affected frame family.
- Narrowed remaining Unit page frontend fanouts for Castbar backend and Boss target highlight. Castbar backend changes now queue `RequestUnitApply(unit, { castbar = true })`; Boss target highlight changes queue the `boss` UnitFrame scope instead of a global general apply.
- Narrowed ClassPower preview drag apply. Moving detached power/power text in the preview now uses `RequestUnitApply("player")`; class/HP-only preview moves remain classpower-preview applies and no longer request generic UnitFrame text/power fanout.
- Tightened Boss-target highlight Assistant and color paths. Assistant `general.bossTargetHighlightEnabled`, Global Bars Boss Target Border, Advanced Colors Boss-target color, and Assistant Boss-target color now refresh only boss borders through `UF.RefreshBorders("boss")` and no longer route through global bar/unitframe applies.
- Closed the remaining Boss-target highlight color residual fanout. Advanced Colors and Assistant Boss-target color changes now refresh the UF settings cache and then only the boss border/color scope, with scoped legacy fallbacks; they no longer call the generic `ApplyColors()` path.
- Narrowed EditMode aura popup preview refresh. After popup changes, Auras3 still reapplies each affected unit through `RequestScope`/`RefreshUnit`, but the follow-up edit-preview refresh now targets the affected unit or the aggregate `boss` scope instead of refreshing every aura preview.
- Scoped ClassPower color applies to the player coldpath. Advanced color controls and Assistant ClassPower color writes now queue `colorScope="player"`, refreshing only player UnitFrame colors/bar textures plus `MSUF_ClassPower_InvalidateColors()`; scoped color applies no longer run global gameplay color or priority-row fanouts.
- Routed Colors page reset ClassPower work through `MSUF_Menu2_ApplyService.RequestClassPower({ colors = true, playerHP = true })` instead of calling `MSUF_ClassPower_InvalidateColors()` directly. The reset path now coalesces ClassPower color cache invalidation with the existing ApplyService flush, and `MSUF_ClassPower_Apply({ colors = true })` also invalidates the Balance-Druid external color cache that the old direct helper covered.
- Split Castbar color applies from generic UnitFrame colors. Advanced color controls and Assistant Castbar color writes now queue the Castbar coldpath directly and no longer call `ApplyColors()`/`RequestColors()` first; global Castbar color changes still refresh KickReady colors, while unit-scoped Castbar applies stay on the unit Castbar queue.
- Scoped the underlying Castbar Color-API push path. Castbar text/border/background/fill/interrupt/player-override setters now coalesce into `PushCastbarVisualUpdates()` and only refresh Castbar visuals plus Castbar previews, instead of silently scheduling the global `PushVisualUpdates()` UnitFrame/GroupFrame color fanout before the Castbar coldpath runs.
- Loaded the UF bridge element set through the active embedded Core XML and added `Castbars`/`ClassPower` to the Core `defaultApplyMask`. Normal `UF.Apply(unit)` now enables/disables Castbar ownership and ClassPower ownership through the Core coldpath instead of relying only on later legacy fanouts; the bridge queues per-unit Castbar refreshes and the existing granular ClassPower apply API.
- Made Menu2 history restore source-aware for single-unit changes. Undo/redo for `unit:<unit>:...` and `apply:unit:<unit>:...` snapshots now restores the DB snapshot but applies only the affected UnitFrame scope, including scoped text/power/font/alpha/castbar/aura plus unit-scoped bar/color coldpaths; profile/session restore and unknown multi-domain sources remain broad by design.
- Tightened targeted general refresh scope use in the Menu2 ApplyService. `RefreshTargetedGeneral()` now honors unit `fontScope`, `powerScope`/`barsScope`, and `alphaScope` before falling back to global text, power, or alpha refreshes.
- Scoped Menu2 unit page resets. Resetting Player/Target/Focus/Pet/Boss UnitFrame pages now applies only the affected UnitFrame plus unit-scoped bar/color coldpaths, and undo/redo for those page-reset snapshots stays on the same scoped history path; whole-profile and multi-domain page resets still use the broad restore fanout.
- Scoped feature-specific Menu2 page resets. Castbar, ClassPower, Gameplay, and Modules page resets now return through their owning coldpath/runtime apply helpers instead of the generic profile restore fanout, and undo/redo for those page-reset snapshots replays the same feature-scoped apply path.

## Regression found against `MidnightSimpleUnitFrames (7).zip`

Observed regression:
- The ZIP baseline had lower general CPU usage and lower target-change cost.
- The current local repo differed from the ZIP in hotpath files, especially `MSUF_UF_Core.lua`, `MSUF_UF_Runtime.lua`, `MSUF_UF_Factory.lua`, `MSUF_UF_Group_Runtime.lua`, `MSUF_UF_Elements_Bridges.lua`, runtime color/font/texture files, and Castbar runtime files.
- The target/click investigation showed no meaningful new `PLAYER_TARGET_CHANGED`/`UNIT_TARGET` listener class versus the ZIP. The regression was therefore not primarily "more target events", and not the target frame appearing by itself.

Actual cause:
- During the feature reconnect work, the Core gate was widened incorrectly.
- `UF.CoreElementAllowed` was changed from the strict Basic-only gate to a broader metadata-backed gate using `Metadata.runtimeUpdateOwners` and `Metadata.defaultApplyMask`.
- That broader gate was then used by hotpath code:
  - `UF.RebuildRuntimeStatusState()` compiled `_msufRuntimeAllPath` from the broader element set.
  - `RebuildFrameEvents()` registered event handlers for every active element allowed by the broader gate.
  - `FrameEnableElement()`/`ApplyElementToFrame()` used the same broad gate.
  - `UF.RefreshElements()` and deferred refresh queues also used the same broad gate.
- After `Castbars` and `ClassPower` were added to `Metadata.defaultApplyMask`, those bridge elements were valid for Core apply work. Because the same predicate was reused for hotpath routing, coldpath ownership work could leak into unit event/runtime paths.
- This violated the core rule from the migration plan: feature ownership and settings apply may be connected to Core, but per-unit events must stay limited to the minimum direct API work.

Why the ZIP was faster:
- In the ZIP, the true unit event path stayed closer to Basic-only behavior: health, power, text, and identity updates.
- Optional systems such as Castbars, ClassPower, Auras, Range/Visuals, and group helpers were not allowed to become generic Core event runners simply because they were connected for apply/settings ownership.
- This kept click-triggered target changes and normal target swaps from compiling or executing extra feature paths through `_msufRuntimeAllPath` and frame event routing.

Fix applied:
- `MSUF_UF_Core.lua` now separates the gates:
  - `HotElementAllowed(name)`: strict Basic-only predicate for event routing and `_msufRuntimeAllPath`.
  - `UF.CoreElementAllowed`: exported as the same hotpath predicate for compatibility.
  - `ApplyElementAllowed(name)`: wider metadata-backed predicate for coldpath `UF.Apply`, `UF.ApplyElementToFrame`, and explicit refresh/apply work.
- `MSUF_UF_Runtime.lua` now uses `UF.ApplyElementAllowed` for explicit `RefreshElements()` and deferred refresh queues, so optional elements can still be deliberately applied without entering the event hotpath.
- Synced to PTR for immediate testing:
  - `UnitFrames/Engine/MSUF_UF_Core.lua`
  - `UnitFrames/Engine/MSUF_UF_Runtime.lua`
- PTR backup before sync:
  - `E:\World of Warcraft\_ptr_\Interface\AddOns\_MSUF_backups\hotpath_20260708_081722`
- Full Lua syntax check after the fix: `luac -p` passed for 561 Lua files.

Rule going forward:
- Never use a coldpath/apply predicate to build per-unit event routing.
- `defaultApplyMask`, bridge ownership, menu apply, preview apply, and feature reconnect work must remain coldpath-only.
- If a feature needs live events, it must register its own minimal event path or become a true Basic-hot element only after profiling proves zero regression against the ZIP baseline.
- If target swaps remain slower after this fix, the next candidates are Castbar visual sync and group dirty refresh, not the Core event predicate itself.

## Health color mode regression found after UFCore reconnect

Observed bug:
- `Dark Mode` and `Unified Color Mode` worked.
- `Class Color Mode` and `Color Gradient` did not repaint correctly on real unitframes.
- This affected the new Core health renderer, not the menu controls themselves.

Actual cause:
- The simplified Core `Health` element painted the health bar from compiled static `spec.health.r/g/b`.
- That is correct for `dark` and `unified`, because those modes compile a static color into the spec.
- It is wrong for `class` and `gradient`, because those are runtime colors:
  - `class` needs unit identity/class/reaction state.
  - `gradient` needs current health evaluated against a color curve.
- As a result, the static fallback color could overwrite the runtime color path.

PTR API source:
- Local source branch: `_local_workflows/references/wow-ui-source`, `upstream/ptr` at `d93edffb654e78dbe41e8ae10fd9bb5c771194e0`.
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua` documents `UnitHealthPercent(unit, usePredicted, curve)` and states that with a curve it returns the result of evaluating that curve with health percentage as input.
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/CurveUtilDocumentation.lua` documents `C_CurveUtil.CreateColorCurve()`.
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/LuaColorCurveObjectAPIDocumentation.lua` documents color curve `AddPoint()` and `Evaluate()`.

Fix applied:
- `MSUF_UF_Elements_Health.lua`
  - Keeps static `SetColor()` for `dark` and `unified`.
  - Routes `class` and `gradient` through `BarsCommon.ApplyHealthStatusColor()` in the Core health update path.
  - Applies the runtime color once during `Health.Apply()` so freshly applied frames do not sit on the compiled fallback color until the next event.
- `MSUF_UF_Elements_BarsCommon.lua`
  - Keeps the normal gradient path on Blizzard/PTR C-side evaluation: `UnitHealthPercent(unit, true, colorCurve)`.
  - Builds the curve with `C_CurveUtil.CreateColorCurve()` and `CreateColor()`.
  - Does not manually interpolate live frame color from `hp / maxHP`; fake preview health is the only path that evaluates a curve from a supplied percentage.

Rule going forward:
- Do not compile runtime health color modes into static `spec.health.r/g/b`.
- `dark`/`unified` can stay static.
- `class`/`gradient` must stay in the runtime health color resolver.
- Gradient must use Blizzard's curve evaluation API for live units; manual interpolation is preview-only because previews do not have a real unit token.
- GroupFrames use `GF.ApplyStructureSpec -> UF.ApplySpec`, so they share the same Health element and must not grow a separate hotpath color implementation unless the Core path cannot support them.

## Preview health color reconnect

Observed follow-up:
- After the real Core health color path was fixed, previews could still show stale or wrong colors because several preview renderers treated compiled `health.r/g/b` as final even for runtime modes.
- This was visible risk for `class` and `gradient`: the live frame should resolve those from unit identity/current health, while preview data is fake and must resolve them in preview coldpath.

Fix applied:
- `MSUF_UF_Elements_BarsCommon.lua`
  - Exports `PreviewHealthGradientColor(health, pct)`.
  - Uses the same `C_CurveUtil.CreateColorCurve()` color-curve object as the live gradient path.
  - Preview evaluation uses `curve:EvaluateUnpacked(pct)`/`curve:Evaluate(pct)` because preview health is fake data, not a real unit token.
- `MSUF_Menu2_UnitPreview_Model.lua`
  - Uses the common preview curve resolver and the configured `healthGradientLow/Mid/High` stops instead of hardcoded red/yellow/green interpolation.
- `MSUF_Menu2_UnitPreview_Render.lua`
  - Uses compiled static `health.r/g/b` only for `dark`, `unified`, or `custom`; `class` and `gradient` fall back to the preview model resolver.
- `MSUF_UF_Group_Preview.lua`
  - Core-backed group preview frames now use the common preview curve resolver when fake preview health changes.
- `MSUF_Menu2_GroupPreview_Native.lua` and `MSUF_Menu2_GroupPreview_Render.lua`
  - Group mock previews now normalize `class`/`gradient`/`dark`/`unified` modes consistently and use the common gradient resolver.
  - Runtime compiled static health colors are honored only for static modes.

Performance note:
- This work is preview/menu coldpath only.
- It does not add event registrations or per-unit live update work.
- The live gradient path still prefers `UnitHealthPercent(unit, true, colorCurve)`; preview-only fake health cannot use that unit-token API and therefore evaluates the same curve object directly.

Follow-up fix:
- `MSUF_UF_Group_Config.lua`
  - Groupframes now inherit all global unitframe health modes from the Core settings cache, including `class` and `gradient`.
  - `gradient` falls back to `class` only when `enableHealthGradient` is explicitly disabled.
- `MSUF_Menu2_GroupPreview_Native.lua`
  - Native group preview now uses the same global-mode normalization and configured gradient stops.

Bug cause:
- The group Core resolver previously only honored global `dark` and `unified`.
- Global `gradient` was ignored and group frames fell back to the group-local health mode/default `class`.
- This was a coldpath mode-resolution bug, not a live gradient API bug.

Follow-up fix:
- `MSUF_UF_Elements_BarsCommon.lua`
  - Removed the live `hp/maxHP` gradient fallback after the PTR API check.
  - Live unitframes now resolve gradient color only through the native health-percent curve path or the native heal-prediction calculator path.
  - Preview code still uses fake percentage input because there is no real unit token in menu/group previews.

PTR API source:
- Local source branch-qualified read: `_local_workflows/references/wow-ui-source`, `upstream/ptr`.
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua` documents `UnitHealthPercent(unit, usePredicted, curve)`.
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/CurveUtilDocumentation.lua` documents `C_CurveUtil.CreateColorCurve()`.

## Castbar target-name state reconnect

Observed state:
- Castbar runtime already has a readable `Engine -> Runtime -> Driver` split.
- Target/focus castbar target-name display was still resolved directly inside `MSUF_CastbarDriver.lua`.
- That kept native cast-target APIs outside the shared cast-state cache even though PTR exposes them as unit cast APIs.

PTR API source:
- Local source branch: `_local_workflows/references/wow-ui-source`, `upstream/ptr` at `d93edffb654e78dbe41e8ae10fd9bb5c771194e0`.
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua` documents:
  - `UnitShouldDisplaySpellTargetName(unit)`
  - `UnitSpellTargetName(unit)`
  - `UnitSpellTargetClass(unit)`
- These are native cast-target APIs; no targeted-spell scanner is needed for this feature.

Fix applied:
- `MSUF_CastbarEngine.lua`
  - Added `Engine:ResolveTargetInfo(state)`.
  - Stores target display readiness, target name, and target class on the cached cast-state table.
  - Exports `MSUF_ResolveCastbarTargetInfo(state)` for compatibility.
- `MSUF_CastbarDriver.lua`
  - Target/focus target-name text now asks the Engine for target info first.
  - Direct native API calls remain only as legacy fallback if the Engine helper is unavailable.
  - The resolver is called only after `castbarTargetShowTargetName`/`castbarFocusShowTargetName` is enabled and an active cast state exists.

Performance note:
- No new events were registered.
- Default settings keep this path off.
- When enabled, native target-name APIs are resolved once per cached cast-state instead of being owned by the Driver's visual mutation path.

## Player castbar Engine-first state reuse

Observed state:
- Target/focus castbars already route spellcast state reads through `MSUF_CastbarEngine:BuildState()`.
- Player castbar runtime still performed its own `UnitCastingInfo`/`UnitChannelInfo` reads for player/vehicle selection, cast start, channel start, and post-interrupt resync.
- Player could not fully reuse the Engine state without preserving PTR `castID`/`castBarID`, because stop/failed/interrupted events validate against those identifiers.

PTR API source:
- Local source branch: `_local_workflows/references/wow-ui-source`, `upstream/ptr`.
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua` documents:
  - `UnitCastingInfo()` return fields include `castID`, `castingSpellID`, `castBarID`, and `delayTimeMs`.
  - `UnitChannelInfo()` return fields include `spellID`, `isEmpowered`, `numEmpowerStages`, and `castBarID`.

Fix applied:
- `MSUF_CastbarEngine.lua`
  - Cast-state tables now carry `castID`, `castBarID`, `delayTimeMS`, tradeskill, empowered, and empower-stage metadata.
- `MSUF_PlayerCastbarRuntime.lua`
  - Player/vehicle active-unit selection now uses `MSUF_BuildCastState()` with a direct fallback only if the Engine export is unavailable.
  - Cast/channel start and soft resync apply the Engine state through a single `ApplyCastState()` path instead of separately querying cast and channel APIs.
  - Player/vehicle spellcast events invalidate the Engine cache before rebuilding, so same-frame caching removes duplicate reads without reusing stale state.

Performance note:
- No new events, timers, or OnUpdate paths were added.
- Stop/failed/interrupted identity checks still use event-provided identifiers.
- This reduces duplicate spellcast API reads in the player castbar start/resync hotpath while preserving the existing player-specific latency, interrupt, vehicle, and channel behavior.

## Castbar coldpath Core-first cleanup

Observed state:
- Castbar previews and anchor helpers still had fallback reads from legacy `_G.MSUF_UnitFrames`/`_G.UnitFrames` tables.
- Castbar fill-direction coldpaths in `MSUF_CastbarStyle.lua` and `MSUF_Castbars_Core.lua` still queried `UnitChannelInfo()` directly to determine whether an active castbar should be treated as a channel.

Fix applied:
- `MSUF_CastbarAnchors.lua`
  - Unitframe table lookup now uses `MSUF.UF.frames` only, with the existing named-frame fallback kept for very early load ordering.
- `MSUF_CastbarPreviews.lua`
  - Preview sizing/parenting now resolves live unitframes through `MSUF.UF.GetFrame()`/`MSUF.UF.frames`, not legacy global UnitFrames tables.
- `MSUF_CastbarStyle.lua` and `MSUF_Castbars_Core.lua`
  - Fill-direction coldpaths use `MSUF_BuildCastState()` for channel/empower detection when the Engine is available.
  - Direct `UnitChannelInfo()` remains only as fallback when the Engine export is unavailable.

Performance note:
- This is menu/profile/preview coldpath work only.
- No spellcast event registrations changed.
- The Castbars folder no longer references legacy `_G.MSUF_UnitFrames` or `_G.UnitFrames`.

## ClassPower bridge ownership narrowing

Observed state:
- `ClassPower` is connected to UFCore as an apply/ownership bridge, not yet as a true live Core element.
- The bridge still called `MSUF_ClassPower_Apply({ full = true, cdm = true })` every time the player Core spec applied while ClassPower was enabled.
- That was correct for first enable/disable transitions, but too broad for unchanged Core applies such as player frame visual/layout refreshes.

Fix applied:
- `MSUF_CP_Controller.lua`
  - Adds exported `MSUF_ClassPower_RefreshLayout()` as a small coldpath geometry refresh.
  - Extends `MSUF_ClassPower_Apply(opts)` with `anchor`/`reanchor`/`geometry` flags that call only the lightweight layout path.
  - Keeps existing `full`/`structure`/`layout` flags as full refreshes, so real ClassPower option changes still rebuild safely.
  - Player frame `OnSizeChanged` and the second `PLAYER_ENTERING_WORLD` relayout pass now use the lightweight anchor/CDM path instead of replaying `FullRefresh()`.
- `MSUF_UF_Elements_Bridges.lua`
  - Tracks the last Core ClassPower enabled state on the player frame.
  - Runs full ClassPower apply only when the enabled state changes.
  - Runs lightweight `anchor=true` apply for unchanged enabled player Core applies.
- `MSUF_Menu2_ApplyService.lua`, `MSUF_Menu2_ClassPowerPreview.lua`, and `MSUF_Menu2_UnitPreview_View.lua`
  - Player power applies and preview offset writes now call the same lightweight anchor/CDM/PlayerHP path.
  - Full ClassPower apply remains reserved for explicit ClassPower structure/profile/page-reset applies.
- `MSUF_UF_Factory.lua` and `MSUF_Integration_ThirdPartyAnchors.lua`
  - Late anchor/proxy refreshes now call the lightweight ClassPower anchor path instead of a full ClassPower rebuild.

Performance note:
- No live ClassPower events or OnUpdate paths were added.
- The change reduces coldpath spillover from generic player UF applies into ClassPower structure rebuilds.
- The live class-resource event loop remains external and is still listed below as not fully connected.

## Auras3/ClassPower Core-frame fallback cleanup

Observed state:
- Auras3 runtime/editmode and ClassPower controller/core/balance/menu quick paths still had legacy `_G.MSUF_UnitFrames` frame lookup fallbacks after the new Core lookup.
- These were not live event loops, but leaving them in place made ownership ambiguous and kept old registry assumptions alive in coldpaths.

Fix applied:
- `MSUF_Auras3_UnitFrames.lua`
  - Runtime unit resolution now uses Auras3's runtime owner cache, `MSUF.UF.GetFrame()`, `MSUF.UF.frames`, then the named frame fallback.
- `MSUF_Auras3_EditMode.lua`
  - EditMode frame resolution now uses Auras3 ownership plus `MSUF.UF.GetFrame()`/`MSUF.UF.frames`, not the old global UnitFrames table.
- `MSUF_CP_Controller.lua`, `MSUF_CP_Core.lua`, and `MSUF_CP_BalanceDruid.lua`
  - Player frame resolution now uses `CoreUnitFrame("player")` plus `_G.MSUF_player` as the early-load fallback.
- `MSUF_Menu2_AdvancedClassPower.lua`
  - Quick preview/runtime checks now follow the same Core-first player-frame lookup.

Performance note:
- No events, timers, or OnUpdate paths were added.
- This is coldpath/frame ownership cleanup only.
- Search verification shows no `_G.MSUF_UnitFrames`/`_G.UnitFrames` fallback remains in `Auras3/`, `ClassPower/`, or the AdvancedClassPower page.

## Legacy UnitFrame registry reader cleanup

Observed state:
- A few remaining debug, EditMode, gameplay, and optional visual systems still read `_G.MSUF_UnitFrames`, `_G.MSUF_UnitFramesList`, or `_G.UnitFrames` as fallback registries.
- These paths were not click/target hotpaths, but they kept old ownership semantics alive outside the embedded UFCore.

Fix applied:
- `MSUF_Feature_DebugPosition.lua`
  - Position overlay now resolves inspected frames through `MSUF.UF.GetFrame()`/`MSUF.UF.frames` with named-frame fallback.
- `MSUF_Feature_GameplayRuntime.lua`
  - Combat timer anchoring now uses Core-first frame lookup.
- `MSUF_UF_RoundedFrames.lua`
  - Rounded unitframe enumeration now uses `MSUF.UF.ForEachFrame()`/`MSUF.UF.frames`.
- `MSUF_UF_Highlight.lua`
  - Highlight cleanup/debug frame enumeration now uses `MSUF.UF.ForEachFrame()`/`MSUF.UF.frameList`.
- `MSUF_EditMode_Layout.lua`, `MSUF_EditMode_Movers.lua`, and `MSUF_EditMode_Core.lua`
  - EditMode frame resolution/cache invalidation now uses `MSUF.UF.GetFrame()`/`MSUF.UF.frames`/`MSUF.UF.ForEachFrame()`.
- `MSUF_Menu2_BugReport.lua`
  - Frame context now enumerates through `MSUF.UF.ForEachFrame()` or `MSUF.UF.frames`; debug text now names the UFCore registry.

Performance note:
- No new live event registrations, C_Timer paths, or OnUpdate paths were added.
- Search verification shows the only remaining `MSUF_UnitFrames` references in Lua are compatibility exports that point directly at `UF.frames`/`UF.frameList`.
- The old global registries are no longer used as fallback readers by addon code.

## Font/media Castbar coldpath narrowing

Observed state:
- Global font follower refresh and bundled-media key migration still called the broad castbar visual refresh directly.
- These paths are coldpath only, but they affected all castbar objects through the legacy compatibility function even when the newer per-unit castbar visual API was available.

Fix applied:
- `MSUF_FontRuntime.lua`
  - Global font follower refresh now prefers `MSUF_ApplyCastbarVisualsForUnit()` for `player`, `target`, `focus`, and `boss`.
  - The old immediate/global castbar refresh remains fallback only when the unit-scoped API is unavailable.
- `MSUF_Libs.lua`
  - Legacy media key migration now applies castbar visuals through the same unit-scoped loop after updating bar textures.
  - The broad `MSUF_UpdateCastbarVisuals()` call remains fallback only.

Performance note:
- No live spellcast events, target-change handlers, timers, or OnUpdate paths were added.
- This affects font/media coldpaths only and keeps castbar live state ownership unchanged.
- Castbar visual mutation is now explicitly per castbar unit where the newer API exists.

## Assistant AutoCoverage group fallback narrowing

Observed state:
- Generated Assistant settings already infer unit/group domains and can route most applies through `RegistryCore`.
- When `RegistryCore` is unavailable or a generated group setting falls through to the legacy path, group rebuild mode still had a direct `MSUF_GF_RefreshAll()` fallback.
- Generated entries know the exact group scope (`party`, `raid`, or `mythicraid`), so the legacy fallback can remain scoped before using a global group refresh.

Fix applied:
- `MSUF_AssistantRegistry_AutoCoverage.lua`
  - Adds `ApplyLegacyGroupScope(groupScope, mode, dirty)`.
  - Legacy `rebuild` now tries `MSUF_GF_RefreshGeometry(groupScope)`, `MSUF_GF_RefreshUnitBindings(groupScope)`, and `MSUF_GF_RefreshVisuals(groupScope, dirty)` before any global refresh fallback.
  - Legacy `geometry` and visual modes also stay scoped through `MSUF_GF_RefreshGeometry(groupScope)`/`MSUF_GF_RefreshVisuals(groupScope, dirty)`.

Performance note:
- No runtime group events or OnUpdate paths were changed.
- This only affects generated Assistant setting applies, which are menu/coldpath actions.
- `MSUF_GF_RefreshAll()` remains as final fallback for scoped generated group rebuilds only if no scoped API is available.

## Menu2 page-reset domain fanout narrowing

Observed state:
- `MSUF_Menu2_Bindings.lua` already had scoped reset handling for unit pages and feature pages such as Castbars/ClassPower/Gameplay.
- Bars, Fonts, Aura, Color, and Group page resets still fell through to the generic restore fanout path, which calls broad restore globals intended for profile/snapshot restores.
- Those page resets have a known domain and should use the same ApplyService/Core coldpaths as normal setting changes.

Fix applied:
- `MSUF_Menu2_Bindings.lua`
  - Adds `ApplyDomainPageResetRuntime(info, reason)`.
  - Group page resets use GF runtime directly: invalidate config cache, refresh all group frames, request group aura refresh, and refresh group previews. This is still all group scopes because the reset function resets all `gf_*` tables.
  - Bars page resets call `ApplyService.RequestBars(reason)`.
  - Fonts page resets call `ApplyService.RequestFonts(reason)`.
  - Colors page resets call `ApplyService.RequestColors(reason)`, refresh Auras3 color state through the aura apply path, and invalidate ClassPower colors.
  - Aura page resets call Auras3 apply directly.

Performance note:
- Page resets are menu/coldpath only.
- Unit, feature, and now domain page resets return before the broad restore fanout.
- The broad `ApplyRestoreFanout()` path remains for profile and miscellaneous resets, where the touched DB domains are intentionally broad or mixed.

## Unitframe Class/Gradient Color Core apply fix

Observed state:
- PTR source `upstream/ptr:Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua` confirms `UnitHealthPercent(unit, usePredicted, curve)` can evaluate a supplied curve C-side.
- PTR source `upstream/ptr:Interface/AddOns/Blizzard_APIDocumentationGenerated/CurveUtilDocumentation.lua` confirms `C_CurveUtil.CreateColorCurve()`.
- Unitframe live gradient already uses a cached `LuaColorCurveObject` through `UnitHealthPercent(unit, true, curve)`/`EvaluateCurrentHealthPercent(curve)`, not Lua `hp / maxHP` interpolation.
- The remaining live-apply bug was in the menu/apply coldpath: `colorsPushed=true` let `ApplyService` skip its own Core color runtime after the older color push path was scheduled.
- GroupFrame color refresh used `GF.RefreshVisuals(kind, DIRTY_COLOR)` without invalidating compiled group specs, even though group health color mode and gradient stops are compiled fields.

Fix applied:
- `MSUF_Menu2_ApplyService.lua`
  - `ApplyColorRuntime(opt)` now runs for every `opts.colors` apply, even when the legacy `MSUF._colorsAPI.PushVisualUpdates()` path has already been scheduled.
  - This keeps the legacy fanout as supplemental compatibility, but the new Core remains authoritative for health/color mode refreshes.
- `MSUF_UF_Group_Runtime.lua`
  - `GF.RefreshColors(kind)` now invalidates compiled specs before the color dirty pass.
  - This lets group frames pick up global/per-scope `class`, `gradient`, `dark`, `unified`, and gradient stop changes without requiring a full rebuild.

Performance note:
- These are option/menu coldpath changes only.
- No UNIT_HEALTH, PLAYER_TARGET_CHANGED, spellcast, secure-click, timer, or OnUpdate hotpath changed.
- The live gradient calculation remains C-side through PTR `UnitHealthPercent(..., colorCurve)`.

## Raid layout situation refresh narrowing

Observed state:
- `GF.SwitchRaidLayout(situationKey, kind)` already knows the affected group kind (`raid` or `mythicraid`), but it still called `GF.RefreshGeometry()` without the kind.
- If the geometry API was unavailable, the fallback was a full `GF.RefreshAll()`, touching party, raid, and mythicraid from a single raid-layout situation switch.

Fix applied:
- `MSUF_GroupFrames_DB.lua`
  - Adds `RefreshRaidLayoutKind(kind)`.
  - The primary path now calls `GF.RefreshGeometry(kind)`.
  - Scoped fallbacks try `GF.RefreshHeaderLayout(kind)`, `GF.RefreshUnitBindings(kind)`, and `GF.RefreshVisuals(kind, dirty)` before the final global fallback.

Performance note:
- This is a group layout/options coldpath only.
- No roster event, UNIT_* event, click path, target-change path, timer, or OnUpdate logic changed.
- Raid situation switches no longer have to refresh unrelated group-frame families when scoped APIs are present.

## EditMode group geometry fallback scoping

Observed state:
- EditMode HUD reset and EditMode drag-end already knew the affected group kind (`party`, `raid`, or `mythicraid`).
- The primary path used `MSUF.GF.RefreshGeometry(kind)`, but the legacy fallback still jumped from `MSUF_GF_RefreshGeometry(kind)` directly to broad `MSUF_GF_RefreshAll()` if the geometry export was unavailable.
- These are coldpath interactions, but they can still make EditMode changes more expensive than needed.

Fix applied:
- `MSUF_EditMode_HUD.lua`
  - Adds `RefreshGroupGeometryScoped(kind)` for HUD position reset.
  - The fallback now tries scoped `RefreshVisuals(kind, dirty)` before any global group refresh.
- `MSUF_EditMode_Layout.lua`
  - Adds the same scoped helper for group drag-end finalization.
  - Drag-end no longer jumps straight to global group refresh when a scoped visuals API is available.

Performance note:
- EditMode reset/drag-end are configuration coldpaths only.
- No live secure-click, target-swap, roster, UNIT_HEALTH, aura, spellcast, timer, or OnUpdate runtime path changed.
- The final broad fallback remains only for compatibility when no scoped group runtime API exists.

## Group preview, detached power, and first-show target state reconnect

Observed bugs:
- EditMode and the Group Frame menu did not show dummy frames because the new embedded group Core XML loaded group runtime but not the existing group preview/EditMode bridge files.
- Menu2 GroupFrame preview could not accurately mirror and edit the live group frame because the native preview exports were not present in the active UFCore group load path.
- Class Resource one-click setup wrote detached player power settings correctly, but the Core `Power` element ignored `power.detached`, detached width/height/anchor fields, and detached ClassPower sync fields.
- First target/self-target build could show stale or incomplete target-frame state because `RegisterUnitWatch` can make the secure target frame visible after the event pass that would otherwise update it.

PTR source:
- Local source branch: `_local_workflows/references/wow-ui-source`, `upstream/ptr` at `d93edffb654e78dbe41e8ae10fd9bb5c771194e0`.
- `Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/SecureStateDriver.lua` documents `RegisterUnitWatch(frame, asState)`: without `asState`, the unit-existence monitor notifies via `:Show()`/`:Hide()`.

Fix applied:
- `MSUF_UFCore_Group.xml`
  - Loads `MSUF_UF_Group_Preview.lua` and `MSUF_UF_Group_EM2.lua` after group runtime.
  - This restores the existing `MSUF_GF_ShowPreview`, preview anchor, preview refresh, and EM2 group registration paths under the embedded group Core.
- `MSUF_UF_Elements_Power.lua`
  - The Core Power element now handles detached layout directly in `Power.Apply()`.
  - Detached player power can sync width from `MSUF_ClassPowerContainer`, fall back to configured ClassPower width, or use the selected cooldown width frame.
  - Detached player power can anchor to `MSUF_ClassPowerContainer` and supports the compiled `BAR`, `ROUND`, `CRYSTAL`, and `ORB` shape media.
- `MSUF_UF_Factory.lua`
  - Single unitframes now get a guarded `OnShow` runtime update.
  - `ApplyFrame()` also passes `MSUF_APPLY` into `UF.ApplySpec()` so visible frames receive a full initial runtime state after coldpath apply.

Performance note:
- Group preview/EM2 loading is menu/EditMode coldpath only.
- Detached power layout runs in `Power.Apply()`/explicit power layout refreshes, not in `Power.Update()` or UNIT_POWER hotpaths.
- The target first-show fix uses a guarded `OnShow` update for visibility transitions instead of adding more `PLAYER_TARGET_CHANGED` fanout.
- No live secure-click, target-swap, roster, UNIT_HEALTH, UNIT_POWER, spellcast, timer, or OnUpdate event registrations were added.

## Group Menu2 element preview drag/apply and EditMode raid preview display

Observed bugs:
- GroupFrame movement in EditMode worked, but the individual Menu2 Group Preview element handles did not persist or visibly apply movement.
- The same broken path affected non-mouse writes such as Assistant-driven element movement because the preview/live apply path reused stale compiled group specs after writing DB offsets.
- Raid/Mythic group preview display in EditMode could be suppressed by the Menu2 page preview scope filter even though EditMode itself should own preview visibility while active.

Fix applied:
- `MSUF_Menu2_GroupPreview_Handles.lua`
  - The drag capture frame is now owned by the preview stage instead of being anchored against `UIParent` from inside the preview box.
  - Every handle write invalidates `GF.InvalidateCompiledSpecs(refreshKind)` before refreshing the preview/live group visuals.
  - Spell indicator handle writes also invalidate `GF.SpellIndicators` runtime caches before scoped visual refresh.
- `MSUF_Menu2_PagePreviews.lua`
  - When MSUF EditMode is active, Menu2 no longer forces a single active group preview kind. It clears the active preview kind and lets EditMode show the configured group previews.
- `MSUF_UF_Group_EM2.lua`
  - Group geometry/bounds coldpaths invalidate compiled group specs before scoped geometry refresh.
  - Without an explicit active preview kind, EditMode no longer falls back to the current live group kind; it can show all enabled group preview families.

Performance note:
- Changes are menu/EditMode coldpath only.
- No live roster, UNIT_*, target, secure-click, spellcast, timer, or OnUpdate hotpath changed.
- The preview drag `OnUpdate` exists only while actively dragging a Menu2 preview handle and is removed on mouse-up/hide.

## ClassPower frontend apply coalescing

Observed state:
- ClassPower already exposes `MSUF_ClassPower_Apply(opts)` with narrower options such as `visuals`, `fonts`, `playerHP`, `anchor`, and `cdm`.
- Several Menu2/Assistant surfaces still called `MSUF_ClassPower_Apply()` directly and then separately queued a general/unit apply. Rapid knob changes could therefore run ClassPower immediately for each control interaction before the normal Menu2 apply queue coalesced the rest.
- Detached player power Assistant apply also used `MSUF_ApplyPowerBarEmbedLayout_All()` even though the Core has `MSUF_ApplyPowerBarEmbedLayout_ForUnitKey("player")`.

Fix applied:
- `MSUF_Menu2_ApplyService.lua`
  - Adds `RequestClassPower(reason, runtimeOpts, applyFlags)`.
  - ClassPower runtime options are merged into one pending coldpath payload and flushed once per Menu2 apply pass.
  - Existing `classpowerApplied` flags are preserved so the later general/unit apply does not run ClassPower a second time.
- `MSUF_AssistantRegistry_Core_Apply_Domains.lua`
  - Assistant ClassPower and detached power actions now use `ApplyService.RequestClassPower()` when available.
  - Detached player power layout now prefers `MSUF_ApplyPowerBarEmbedLayout_ForUnitKey("player", true)` and falls back to the old broad apply only if the scoped export is missing.
- `MSUF_Menu2_AdvancedClassPower.lua`
  - ClassPower page runtime applies now route through the same queued ClassPower apply service when available.
  - Detached power/player HP page actions route ClassPower refresh through the shared apply flush; Detached power texture/layout helpers are handled by the later dedicated detached-power apply queue pass.

Performance note:
- This is configuration/menu/Assistant coldpath only.
- No ClassPower live eventframe, UNIT_POWER, aura timer, secure-click, target, spellcast, or OnUpdate hotpath changed.
- The remaining ClassPower live resource runtime is still outside UFCore event routing; this change only reduces redundant frontend apply work.

## Castbar frontend apply coalescing

Observed state:
- Castbar live spellcast handling is still external, but Menu2/Assistant apply already funnels many changes through `MSUF_Menu2_ApplyService`.
- `RequestCastbarUnit()` and global `RequestCastbars()` still called `MSUF_Castbars_OnSettingsChanged()` immediately for each frontend change, then queued visual/unit apply work for the next flush.
- That backend sync call applies legacy backend flags, ownership state, Blizzard suppression, target/focus/player/boss backend state, and stale-frame hiding. Running it immediately for every knob is unnecessary coldpath work.

PTR source:
- Local source branch: `_local_workflows/references/wow-ui-source`, `upstream/ptr` at `d93edffb654e78dbe41e8ae10fd9bb5c771194e0`.
- `Interface/AddOns/Blizzard_UIPanels_Game/Mainline/CastingBarFrame.lua` keeps castbar runtime unit-event driven via `RegisterUnitEvent("UNIT_SPELLCAST_*", unit)` and `UnitCastingInfo`/`UnitChannelInfo`; this change does not alter MSUF's live spellcast event handling.

Fix applied:
- `MSUF_Menu2_ApplyService.lua`
  - Adds a pending `Castbars_OnSettingsChanged` flag/source.
  - `RequestCastbarUnit()` and `RequestCastbars()` now queue this backend sync instead of running it immediately.
  - The pending backend sync flushes once before any queued castbar unit/visual apply in the same apply pass.

Performance note:
- This is menu/Assistant/profile coldpath only.
- No live spellcast event registration, castbar OnUpdate, target-swap, secure-click, unitframe UNIT_* path, or castbar driver runtime changed.
- It reduces duplicate frontend backend-sync work when several castbar controls are changed quickly.

## Still not connected cleanly

- Power text/color hotpath cleanup:
  - PTR source reference: `_local_workflows/references/wow-ui-source`, `upstream/ptr` at `d93edffb654e78dbe41e8ae10fd9bb5c771194e0`.
  - `UnitPowerMax` and `UnitPowerPercent` are both documented as restricted/secret-capable APIs in `Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`.
  - The Core Power element was feeding the fast `UnitPowerPercent` bar result back as a generic power return. In some routes that could be interpreted by PowerText as current power while max was missing/zero, producing displays like `66.615... - 0`.
  - The fix keeps the bar on the `UnitPowerPercent` fast path, but the percent path now returns no fake current/max values. PowerText reads `UnitPower`/`UnitPowerMax` only when its compiled runtime flags (`powerNeedsCurrent`/`powerNeedsMax`) require them; percent-only text consumes the dispatched percent and does not add absolute API calls.
  - Power bar coloring now uses the shared `UFBarTextCommon.PowerColor` resolver. `dark`, `unified`, and `static` stay compiled/coldpath colors; `class` and dynamic power coloring no longer use the blue compiled fallback.
  - Non-secret power type/token is cached per frame+unit for the percent bar path. Frequent `UNIT_POWER_UPDATE`/`UNIT_POWER_FREQUENT` ticks reuse cached metadata; secret type/token results clear the cache and are never marked known.
  - Power background/media application was moved out of `SetColor()` and remains in `Power.Apply()`, so `UNIT_POWER_*` color updates no longer touch background texture/media state.
  - `FrameOnShow` now exits if no spec/runtime path exists yet, preventing a visibility transition before finished spec apply from entering the runtime update path.
  - No new live `UNIT_*`, target, secure-click, spellcast, timer, or `OnUpdate` registrations were added.

- Castbars are still an external live spellcast runtime. Preview/anchors, unit-specific option applies, Core enable/disable ownership, and optional native target-name state are Core/Engine-first or coldpath, but the spellcast event path itself is still owned by CastbarDriver/BossCastbars instead of Core event routing.
- ClassPower is still an external runtime with its own eventframe/timers. It is now Core-first for frame lookup and coldpath ownership/apply, and unchanged Core ownership applies no longer force a full ClassPower rebuild, but the live class-resource event loop is still outside Core event routing.
- Auras3 still owns native aura containers and keeps broad `RefreshAll` for true global/profile resets. Normal menu model, unit-copy, Assistant scope fallback, and color visual fanouts now have scoped/coldpath routes.
- Assistant EditMode `ApplyAllSettings()` remains broad by design for global EditMode controls such as `anchorToCooldown` and anchor-name changes. Narrowing that path without changed-domain metadata would risk leaving position/cooldown anchoring out of sync.
- Assistant whole-DB/profile undo/redo still calls broad scheduled refresh functions because those snapshots intentionally restore multiple DB domains. Normal Assistant setting undo already replays per-setting `apply()` handlers.

## Assistant broad apply group coldpath

Observed state:
- Assistant undo/broad apply already used the Menu2 ApplyService for general runtime and Auras3 refreshes, but GroupFrames still called `MSUF.GF.RefreshAll()` directly inside the scheduled broad apply steps.
- The broad nature of assistant undo is correct because a restored snapshot may span several DB domains, but the GroupFrame part can still use the same coalesced Group ApplyService path as the new menu.

Fix applied:
- `Shell/Menu2/Assistant/MSUF_AssistantUndo.lua`
  - Adds `RequestGroupRuntime(reason)`.
  - Normal path calls `MSUF_Menu2_ApplyService.RequestGroupReset(reason)` or `RequestGroup("group", "reset", reason)` and flushes the shared ApplyService.
  - Direct `MSUF.GF.RefreshAll()` / `GF.RefreshVisuals()` remains only as fallback if the ApplyService is unavailable.

Performance note:
- This is scheduled Assistant coldpath only.
- No live UnitFrame, GroupFrame, click, target, cast, aura, or class-resource hotpath changed.
- Assistant broad undo remains broad by design, but its GroupFrame portion now goes through the same coalesced reset path as Menu2 page resets.

## Assistant AutoCoverage fallback live apply

Observed state:
- Generated Assistant settings already prefer RegistryCore helpers when present.
- If RegistryCore was missing or a generated entry fell through to `FallbackScopeApply`, unit scopes used ApplyService, but group scopes called GF methods directly and flat scopes could fall back to `MSUF_RefreshAllFrames()`.

Fix applied:
- `Shell/Menu2/Assistant/MSUF_AssistantRegistry_AutoCoverage.lua`
  - Adds a local ApplyService resolver.
  - Group fallback applies now call `ApplyService.RequestGroup(groupScope, mode, reason)` before any direct GF fallback.
  - Flat-scope fallback applies now call `M.RequestGeneralApply()` / `ApplyService.RequestGeneral()` with concrete flags derived from the DB key (`bars`, `colors`, `castbar`, `classpower`, `fonts`, `alpha`, or `power`) instead of using `visual=true`.

Performance note:
- This only affects generated Assistant coldpath apply callbacks.
- Avoiding `visual=true` prevents these fallback writes from silently promoting to global `MSUF_RefreshAllFrames()`.

## Assistant EditMode apply fallback ordering

Observed state:
- Assistant EditMode global controls such as cooldown anchoring and anchor picker still need a broad apply when the exact affected frame family is not known.
- The shared Assistant helper tried `EM2.Util.ApplyAllSettingsSafe()` first, but if that failed it called `MSUF.UF.Apply(nil)` directly before attempting the new Menu2 apply queue.

Fix applied:
- `Shell/Menu2/Assistant/MSUF_AssistantRegistry_EditMode_Shared.lua`
  - Keeps `EM2.Util.ApplyAllSettingsSafe()` as the preferred precise EditMode path.
  - Then uses `Menu.RequestGeneralApply("MSUF_ASSISTANT_EDIT_MODE_CONTROL", { applyAll = true })` or `MSUF_Menu2_ApplyService.RequestGeneral(...)`.
  - Direct `UF.Apply(nil)` and `MSUF_RefreshAllFrames()` are now only final fallbacks when the menu/core apply service is unavailable.

Performance note:
- This remains a scheduled Assistant/EditMode coldpath.
- It does not narrow the intentionally broad global EditMode operation, but it routes live Assistant changes through the new menu/core apply queue before using direct global fallbacks.

## Assistant RegistryCore apply fallback ordering

Observed state:
- The central Assistant RegistryCore apply helper already used `M.RequestUnitApply()` and `M.RequestGeneralApply()` when Menu2 bindings were loaded.
- If those bindings were unavailable, unit applies fell directly to `MSUF.UF.Apply(unit)`, while general applies simply did nothing. That made some Assistant fallback/load-order paths bypass the shared Menu2 ApplyService.

Fix applied:
- `Shell/Menu2/Assistant/MSUF_AssistantRegistry_Core_Apply.lua`
  - Adds a local ApplyService resolver.
  - `ApplyUnit()` now tries `M.RequestUnitApply()`, then `MSUF_Menu2_ApplyService.RequestUnit()`, then direct `UF.Apply(unit)` as the final fallback.
  - `ApplyGeneral()` now tries `M.RequestGeneralApply()`, then `MSUF_Menu2_ApplyService.RequestGeneral()`.

Performance note:
- This is Assistant/frontend coldpath only.
- Existing Menu2 history/combat guards remain first because `M.Request*Apply()` still owns the normal path.
- Fallback Assistant live applies now reach the same coalesced ApplyService queue before any direct Core apply fallback.

## Assistant ClassPower color apply queue

Observed state:
- Assistant class-power color changes used the scoped UnitFrame color path, then called `MSUF_ClassPower_InvalidateColors()` directly.
- That bypassed the ClassPower ApplyService queue and could run immediately per Assistant setting write.

Fix applied:
- `Shell/Menu2/Assistant/MSUF_AssistantRegistry_Core_Apply_Visuals.lua`
  - `ApplyClassPowerColors()` still requests player-scoped UnitFrame colors.
  - ClassPower itself now queues `MSUF_Menu2_ApplyService.RequestClassPower(reason, { colors = true, playerHP = true }, ...)`.
  - Direct `MSUF_ClassPower_InvalidateColors()` remains only as fallback if ApplyService is unavailable.

Performance note:
- This is Assistant color-setting coldpath only.
- It matches the Menu2 Colors reset path and coalesces ClassPower visual/cache work into the shared ApplyService flush.

## Auras3 PTR4 forward-only AuraContainer rewrite

User instruction:
- Do not keep compatibility for both old/new AuraContainer signatures.
- Target the new PTR4 API from the addon-author notes:
  - `AddAuraGroup(groupKey, filterString, options)`
  - `SetAuraGroupLayout(groupKey, options)`
  - `AddAuraSlot(slotKey, filterString, options)`
  - AuraContainers create and anchor AuraButtons; addons do not create AuraButtons directly.

PTR source state:
- Local source branch: `_local_workflows/references/wow-ui-source`, `upstream/ptr` at `b8f90f2a00340cafc23baa42dd22809bf2a86849`, `version.txt` = `12.1.0.68412`.
- The local mirror still exposes the older in-source form `AuraContainerAuraGroupsMixin:AddAuraGroup(description)` in `Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerGroups.lua`.
- The local mirror still includes `CustomAuraContainerSharedMixin:AddAuraFrame(auraFrame)` in `Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua`.
- Per user note, the actual target is the newer PTR4 addon-author API, not this still-stale mirror surface.

Fix applied:
- `Auras3/MSUF_Auras3_UnitFrames.lua`
  - Removed the old `CreateFrame("AuraButton", ..., "CustomAuraButtonTemplate")` + `AddAuraFrame` fallback path for normal lanes.
  - Removed the old manual AuraButton + `AddAuraFrame` fallback path for dispel sensors.
  - Removed `AddAuraFilter`/`ClearAuraFilters` forced-refresh fallback logic.
  - Normal lanes now require `AddAuraGroup` and call the new forward-only signature with group key, filter string, and options.
  - Dispel sensors now require `AddAuraSlot` and create one slot per needed sensor position.
  - Group layout uses one forward-only `SetAuraGroupLayout(groupKey, options)` call instead of probing several legacy/guessed option shapes.
  - Added a hard PTR4 AuraContainer contract check for `SetUnit`, `SetEnabled`, `AddAuraGroup`, `SetAuraGroupLayout`, `AddAuraSlot`, and `AddItemEnchantment`.
  - Removed the remaining per-method compatibility checks around group/slot creation; stale old-signature containers now fail the contract before MSUF calls any AuraContainer setup.
  - Button customization remains only inside `initializeFrame`, so the container owns button creation and assignment.
- `MSUF_Menu2_ApplyService.lua`
  - Adds queued `RequestAuras(scope, reason, opts)` and `RequestAuraFonts(scope, reason)`.
  - Aura visual-generation bumps are queued and flushed once before the native container apply, instead of calling `A3.ApplyFontsFromGlobal()` directly from each frontend path.
- Menu2/Assistant aura apply paths:
  - Auras page batch apply, Unit copy-aura apply, Advanced aura colors, and Assistant aura helpers now prefer the ApplyService queue.
  - Assistant broad undo/redo now requests Auras through `ApplyService.RequestAuraFonts`/`RequestAuras` and flushes the service instead of calling `A3.RequestApply()` directly on the normal path.
  - Assistant EditMode aura-preview toggles now prefer `A3.RefreshEditPreview()` or the ApplyService aura queue before falling back to a broad Auras3 refresh.

Performance note:
- This is still configuration/menu/Assistant coldpath plus native-container construction code.
- No custom MSUF `UNIT_AURA` scanner was added.
- No aura OnUpdate loop was added.
- The steady-state aura churn remains owned by Blizzard AuraContainers.
- Because this is intentionally forward-only, it is expected to fail on a client that only exposes the older local-mirror `AddAuraGroup(description)` / `AddAuraFrame` surface.

## Group ApplyService queue

Observed state:
- Assistant group settings and several Menu2 group controls could still call group refresh helpers directly or via `GroupPage.QueueGF()`.
- That was acceptable functionally, but it meant rapid frontend changes could still schedule several geometry/visual/aura/font refreshes separately instead of merging them into one dirty-mask pass.

Fix applied:
- `MSUF_Menu2_ApplyService.lua`
  - Adds `RequestGroup(scope, mode, reason)`.
  - Adds `RequestGroupDirtyMask(scope, dirtyMask, reason)` for callers that already know the exact group dirty mask.
  - Coalesces pending group work by group kind (`party`, `raid`, `mythicraid`, or all groups).
  - Merges dirty flags before flushing, using the same `GF.DIRTY_*` semantics as the UFCore group runtime.
  - Handles rebuild, geometry, visual, color, font, border, aura, and targeted-spell apply modes.
  - Defers protected/group runtime work through `GF.DeferGroupRuntime()` while in combat.
  - Refreshes the native Menu2 group previews only once per coalesced flush.
- `MSUF_Menu2_Group.lua`
  - The page-local `QueueGF()` wrapper now prefers `ApplyService.RequestGroup()` for normal group setting changes.
  - Exact mask applies now use `ApplyService.RequestGroupDirtyMask()` when available.
  - The previous page-local delayed flush remains only as a fallback if the shared ApplyService is unavailable during load/runtime.
  - `GroupPage.QueueGFDirtyMask` is exported next to `GroupPage.QueueGF` so subpages can request exact dirty-mask applies without forcing rebuilds.
- `MSUF_Menu2_GroupIndicators.lua`
  - Targeted-spell setting changes now request `ApplyService.RequestGroup("party", "targetedSpells", "GF_TARGETED_SPELLS")`.
  - The service applies the targeted-spell config and the visual dirty flag in one coalesced group flush.
  - The previous direct `RefreshConfig()` + preview-refresh path remains only as fallback.
- `MSUF_AssistantRegistry_Core_Apply_Group.lua`
  - Assistant group apply now prefers `ApplyService.RequestGroup()` before falling back to older direct group refresh paths.

Performance note:
- This is configuration/menu/Assistant coldpath only.
- No group secure-click, roster event, UNIT_* event, target-swap, aura, castbar, or OnUpdate hotpath changed.
- The purpose is to keep frontend apply work batched and dirty-mask based, not to add new live runtime work.

## EditMode scoped apply helpers

Observed state:
- `EM2.Util.ApplySettingsForKeySafe(key)` only handled UnitFrame keys through `UF.Apply(key)`.
- EditMode manages UnitFrame, GroupFrame, and Castbar edit keys, so known group/castbar keys could still fall back to broad `ApplyAllSettingsSafe()` in some popup/undo paths.
- The Unit popup `CopyBoundsTo()` path applied the destination unit immediately and then still ran a full apply fallback unconditionally when the broad helper existed.

Fix applied:
- `MSUF_EditMode_Core.lua`
  - `ApplySettingsForKeySafe(key)` now recognizes:
    - unit keys: `UF.Apply(key)` or `MSUF_ApplyUnitFrameKey_Immediate(key)` fallback;
    - group keys: `gf_party`, `gf_raid`, `gf_mythicraid` through scoped `GF.RefreshGeometry(kind)`/`GF.RefreshVisuals(kind, geometryMask)`;
    - castbar keys: `castbar_player`, `castbar_target`, `castbar_focus`, `castbar_boss` through unit castbar apply/sync helpers.
- `MSUF_EditMode_Popups.lua`
  - Unit popup `CopyBoundsTo()` now applies only the copied destination frame, then refreshes the destination powerbar embed layout.
  - The broad `ApplyAllSettingsSafe()`/`MSUF_UpdateAllFrames()` fallback remains only if no scoped apply path exists.

Performance note:
- This is EditMode/menu coldpath only.
- No drag-loop OnUpdate, UNIT_* event, target, secure-click, castbar spellcast, aura, or combat runtime hotpath changed.
- The main win is removing a full unitframe apply from single-target EditMode copy-bounds operations.

## ClassPower quick-setup apply narrowing

Observed state:
- Most Advanced ClassPower page controls already route through `ApplyService.RequestClassPower()`.
- The one-click ClassPower quick setup still ended with multiple immediate calls:
  - full ClassPower apply;
  - broad detached powerbar layout apply;
  - PlayerHP ClassPower apply;
  - global UFCore config notification.

Fix applied:
- `MSUF_Menu2_AdvancedClassPower.lua`
  - `QuickRefreshAll()` now prefers one `ApplyService.RequestClassPower()` call with a merged runtime payload:
    - full ClassPower/CDM apply;
    - PlayerHP ClassPower apply;
    - player-scoped powerbar/unit apply flags.
  - The broad detached powerbar layout apply is no longer used on the normal path; player scope is carried through the apply queue.
  - Legacy fallback still uses `MSUF_ApplyPowerBarEmbedLayout_ForUnitKey("player", true)` first and only falls back to `MSUF_ApplyPowerBarEmbedLayout_All()` if the scoped export is missing.
  - UFCore fallback notification is player-scoped instead of global.

Performance note:
- This is one-click setup/undo coldpath only.
- No ClassPower live resource eventframe, UNIT_POWER, target, secure-click, castbar, aura, timer, or OnUpdate hotpath changed.
- The visible setup result stays immediate, but the final apply work is coalesced through the shared apply queue when available.

## History ClassPower apply narrowing

Observed state:
- Menu2 history/page-reset feature restore had a feature-specific branch for `classpower`, but it still queued a generic `ApplyService.RequestGeneral(... classpower=true)` apply.
- That worked, but it skipped the dedicated ClassPower queue that already merges ClassPower runtime options and prevents duplicate ClassPower work.

Fix applied:
- `MSUF_Menu2_Bindings.lua`
  - ClassPower feature restore now calls `ApplyService.RequestClassPower(reason, { full = true, cdm = true }, flags)` when available.
  - The old direct `MSUF_ClassPower_Apply({ full = true, cdm = true })` remains as fallback if the shared ApplyService is unavailable.

Performance note:
- This is Menu2 history/page-reset coldpath only.
- No ClassPower live runtime eventframe, UNIT_POWER, target, secure-click, castbar, aura, timer, or OnUpdate hotpath changed.
- It keeps ClassPower restore work on the same coalesced path as normal ClassPower page controls and quick setup.

## Group page reset queueing

Observed state:
- Menu2 page reset for Party/Raid Frames still called the group runtime directly from `MSUF_Menu2_Bindings.lua`.
- That direct path invalidated the group config cache, refreshed/rebuilt all group frames, requested aura refresh when available, and refreshed previews immediately.
- Functionally correct, but it bypassed the shared Group ApplyService queue added for normal group menu changes.

Fix applied:
- `MSUF_Menu2_ApplyService.lua`
  - Adds a `reset` mode for queued group applies.
  - `RequestGroupReset(reason)` queues an all-group reset with:
    - config-cache invalidation;
    - rebuild/dirty-all;
    - optional `GF.RequestAuraRefresh`;
    - native group preview refresh.
- `MSUF_Menu2_Bindings.lua`
  - Group page reset now prefers `ApplyService.RequestGroupReset(reason)`.
  - The old direct group runtime refresh path remains as fallback if the shared ApplyService is unavailable.

Performance note:
- This is Menu2 page-reset coldpath only.
- No group secure-click, roster event, UNIT_* event, target, aura live scan, timer, or OnUpdate hotpath changed.
- Reset behavior still touches all group frame families by design, but now goes through the same coalesced ApplyService path as normal group menu changes.

## Auras page reset queueing

Observed state:
- Menu2 page reset for Auras still called `Auras3.RequestApply("shared", reason)` directly from `MSUF_Menu2_Bindings.lua`.
- Colors page reset also reused that direct Aura apply path even though color/font aura updates already have `ApplyService.RequestAuraFonts()`.

Fix applied:
- `MSUF_Menu2_Bindings.lua`
  - `ApplyAurasPageResetRuntime()` now prefers `ApplyService.RequestAuras("shared", reason)` for aura-page resets.
  - Colors page reset calls the same helper with visual mode, which prefers `ApplyService.RequestAuraFonts("shared", reason)` so native aura visual generation is bumped through the queue.
  - Direct `Auras3.RequestApply()` / `RefreshAll()` remains only as fallback if ApplyService is unavailable.

Performance note:
- This is Menu2 page-reset coldpath only.
- No custom aura scanner, UNIT_AURA path, timer, secure-click, target, or OnUpdate hotpath changed.
- Aura reset work now shares the same queued path as normal Auras page changes and Assistant aura applies.

## Auras3 PTR4 AuraButton contract hardening

User requirement:
- Do not support both old and new AuraContainer signatures.
- Move the runtime to the new PTR4 AuraContainer/AuraButton contract from the provided screenshot.

Source state:
- The local `wow-ui-source` mirror was updated before this pass.
- `upstream/ptr` still exposes the old `AuraContainerAuraGroupsMixin:AddAuraGroup(description)` form in `Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerGroups.lua`.
- The screenshot remains the source of truth for this PTR4 pass because the mirror does not yet contain `AddAuraGroup(groupKey, filterString, options)`, `AddAuraSlot(slotKey, filterString, options)`, `AddItemEnchantment(itemEnchantmentSlot, options)`, or `SetCancelAuraButtons`.

Fix applied:
- `MSUF_Auras3_UnitFrames.lua`
  - Removed the generic `CallButtonMethod()` compatibility shim.
  - Added a hard PTR4 AuraButton contract check for the native button methods used by MSUF, including `SetCancelAuraButtons`.
  - Aura buttons now call the new native methods directly in the `initializeFrame` callback.
  - Player buff buttons register native right-click cancellation through `SetCancelAuraButtons("RightButton")`; non-player/sensor buttons clear that path.
  - Normal lanes still use only `AddAuraGroup(groupKey, filterString, options)` plus `SetAuraGroupLayout(groupKey, options)`.
  - Dispel sensors still use only `AddAuraSlot(slotKey, filterString, options)`.
  - No `AddAuraFrame`, `AddAuraFilter`, or `ClearAuraFilters` runtime path remains in active Lua code.

Performance note:
- This is container/button creation coldpath only.
- No custom aura payload scan, `UNIT_AURA` loop, target-swap fanout, secure-click handler, timer, or OnUpdate path was added.
- A stale client with only the old local-mirror AuraContainer API should now fail visibly instead of silently taking a compatibility path.

## Bar gradient apply queueing

Observed state:
- `MSUF_UpdateAllBarGradients(scope)` was already scope-aware and therefore safe for targeted unit/group/global refresh.
- Assistant bar-gradient changes still called it immediately after a general bar apply request.
- The Menu2 Global Bars page also scheduled a separate delayed gradient refresh in addition to requesting a general bar apply.

Fix applied:
- `MSUF_Menu2_ApplyService.lua`
  - Added `barGradients` as a targeted general runtime flag.
  - `RequestGeneral()` now merges `barGradients` with normal bar work and preserves the requested `barsScope`.
  - `ApplyBarRuntime()` runs `MSUF_UpdateAllBarGradients(scope)` inside the coalesced bar-runtime flush.
  - Added `RequestBarGradients(reason, scope)` for Assistant/page callers.
- `MSUF_AssistantRegistry_Core_Apply_Bars.lua`
  - Assistant gradient applies now prefer `ApplyService.RequestBarGradients()`.
  - Direct `MSUF_UpdateAllBarGradients()` remains only as service-missing fallback.
- `MSUF_Menu2_GlobalBars.lua`
  - Global Bars gradient controls now prefer the same `RequestBarGradients()` path.
  - The previous scheduled direct gradient refresh remains only as fallback for missing ApplyService support.

Performance note:
- This is settings/apply coldpath only.
- No unit event, target event, secure-click, castbar, aura, timer, or OnUpdate hotpath changed.
- Multiple gradient/bar changes in one menu/assistant tick now merge into one ApplyService flush instead of running a second immediate/delayed gradient pass.

## Bar outline, rounded, and highlight border apply queueing

Observed state:
- Assistant bar outline, rounded bars, aggro border, dispel/purge border, and boss-target border helpers still performed direct runtime calls after requesting a generic bar apply.
- Global Bars page controls had a parallel delayed scheduler for the same outline/highlight work, separate from `MSUF_Menu2_ApplyService`.
- GroupFrame runtime already exposes a `DIRTY_BORDER` path through `GF.RefreshBorder` / `GF.RefreshOutlineGeometry`.
- UnitFrame runtime already exposes scope-aware `UF.RefreshBorders(unit)` through `MSUF_ApplyBarOutlineThickness_All(unit)`.

Fix applied:
- `MSUF_Menu2_ApplyService.lua`
  - Added targeted bar-runtime flags for:
    - `barOutline`
    - `roundedBars`
    - `aggroBorder`
    - `dispelPurgeBorder`
    - `bossTargetBorder`
  - Added queue entry points:
    - `RequestBarOutline(reason, scope)`
    - `RequestRoundedBars(reason, scope)`
    - `RequestAggroBorder(reason, scope)`
    - `RequestDispelPurgeBorder(reason, scope)`
    - `RequestBossTargetBorder(reason, scope)`
    - `RequestHighlightBorders(reason, scope)`
  - `ApplyBarRuntime()` now uses the existing UnitFrame border refresh and GroupFrame `DIRTY_BORDER` refresh instead of forcing callers to run those globals directly.
  - Texture refresh stays gated behind `bars=true`; outline/highlight-only applies no longer implicitly run bar texture refreshes.
- `MSUF_AssistantRegistry_Core_Apply_Bars.lua`
  - Assistant helpers now prefer the new ApplyService queue calls.
  - `ApplyHighlightBorders()` queues aggro, dispel/purge, and boss-target border work in one flush instead of calling three immediate helper chains.
  - Direct globals remain only as fallback when ApplyService is unavailable.
- `MSUF_Menu2_GlobalBars.lua`
  - Global Bars outline, rounded, aggro, dispel/purge, boss-target, and all-highlight controls now prefer the same ApplyService queue calls.
  - The old delayed page-local runtime remains fallback only.
  - Dispel/Purge test-mode toggles remain page-local because they are preview state, not the actual UnitFrame/GroupFrame runtime apply path.

Performance note:
- This is menu/assistant settings coldpath only.
- No secure-click, target, group roster, castbar, aura, UNIT_*, timer, or OnUpdate hotpath changed.
- Bar border changes now merge with adjacent bar/apply work in one ApplyService flush and avoid unnecessary texture refreshes for outline/highlight-only changes.

## ClassPower controller local-limit reduction

Observed state:
- WoW reported `main function has more than 200 local variables` for `ClassPower/MSUF_CP_Controller.lua`.
- Local `luac` in this checkout is Lua 5.4 and does not reproduce WoW's Lua 5.1-style main-chunk local limit, so the in-game error is treated as authoritative.
- The file had a long run of public API wrapper functions at the end, declared as top-level `local function`s after the runtime had already accumulated many cached hotpath locals.

Fix applied:
- `MSUF_CP_Controller.lua`
  - Converted the end-of-file public API wrappers to fields on the existing `CP` runtime table:
    - `CP.IsRuntimeActive`
    - `CP.RefreshPublic`
    - `CP.RefreshCDMWidthBindings`
    - `CP.PlayerHPRefreshPublic`
    - `CP.PlayerHPRefreshTextures`
    - `CP.RefreshTexturesPublic`
    - `CP.ApplyFontsPublic`
    - `CP.RefreshVisualsPublic`
    - `CP.ApplyPublic`
    - `CP.SmoothPowerBarApply`
  - Kept the exported global API names unchanged through `ExportPublic(...)`.
  - Updated internal coldpath calls to use the `CP.*` methods instead of now-removed local wrapper symbols.

Performance note:
- This is a load/compile fix only.
- The ClassPower event, power tick, aura, rune, layout, and value-update hotpaths were not rewritten.
- The hotpath locals remain local for fast lookup; only public coldpath wrappers were moved off the main chunk's local-variable list.

## Detached Player Power apply queueing

Observed state:
- Advanced ClassPower detached-power controls still executed `MSUF_DetachedPowerBar_RefreshTextures()` and the scoped player power layout helper immediately, then queued ClassPower/player applies.
- Assistant detached-power apply used the same immediate texture/layout chain before queueing the ClassPower path.
- UnitFrame Visuals detached-power controls only marked generic `power=true`, so the apply queue could not distinguish a normal power layout from a detached-power texture/layout update.
- Generated Assistant AutoCoverage settings for `detachedPower*` / `powerBarDetached` keys also only inferred generic power or bars work.

Fix applied:
- `MSUF_Menu2_ApplyService.lua`
  - Added a `detachedPowerBar` apply hint for unit and targeted-general queues.
  - Added `ApplyDetachedPowerBarRuntime(unit, refreshTextures)` inside the flush path.
  - Added `RequestDetachedPowerBar(reason, runtimeOpts, applyFlags)` as a small public convenience wrapper over `RequestClassPower()`.
  - Detached-power-only ClassPower runtime now uses `{ anchor = true, cdm = true, playerHP = true, syncNow = false }` instead of forcing a full ClassPower rebuild.
- `MSUF_Menu2_AdvancedClassPower.lua`
  - Detached Player Power controls now set `detachedPowerBar=true` and stop running texture/layout helpers immediately.
  - Detached Player Power text controls stay text/power scoped and no longer force texture refresh.
  - Detached Player Power outline queues player-scoped border refresh instead of calling the all-frame outline alias.
- `MSUF_AssistantRegistry_Core_Apply_Domains.lua`
  - Assistant detached-power apply now prefers `ApplyService.RequestDetachedPowerBar()`.
  - Assistant detached-power outline queues player-scoped border refresh before the detached-power apply.
- `MSUF_Menu2_UnitFrameVisuals.lua`
  - Unitframe detached-power toggles, shape, size, position, sync, anchor, and layer controls now pass `detachedPowerBar=true` to the unit apply queue.
- `MSUF_AssistantRegistry_AutoCoverage.lua`
  - Generated unit and bars-scope settings for `detachedPower*` / `powerBarDetached` keys now add `detachedPowerBar=true`.

Performance note:
- This is frontend/menu/Assistant coldpath only.
- No UNIT_POWER, unitframe OnEvent, secure-click, target-swap, aura, castbar, timer, or OnUpdate runtime was added.
- Multiple detached-power knob changes now coalesce into one ApplyService flush, with player-scoped power layout and player-scoped detached texture refresh instead of immediate per-control helper chains.

## EditMode unit popup power-layout bridge

Observed state:
- `MSUF_EditMode_Popups.lua` still called legacy power-layout globals directly from unit popup apply, detached-power toggle, and copy-bounds flows.
- The direct calls were mostly scoped, but they bypassed the shared ApplyService logic that now owns detached-power texture/layout handling and scoped power-layout fallback order.

Fix applied:
- `MSUF_Menu2_ApplyService.lua`
  - Exposed `Apply.ApplyPowerLayout(unit, detachedPowerBar, refreshTextures)` as a coldpath helper around the existing scoped power-layout implementation.
  - Detached power uses the same `ApplyDetachedPowerBarRuntime()` helper as Menu2/Assistant queues.
- `MSUF_EditMode_Popups.lua`
  - Added a small `ApplyPowerLayoutForUnitKey()` bridge that prefers `ApplyService.ApplyPowerLayout()`.
  - Unit popup apply, detached-power toggle, and copy-bounds now use that bridge.
  - Legacy fallbacks remain scoped through `MSUF_ApplyPowerBarEmbedLayout_ForUnitKey(unit, true)` before falling back to frame/all helpers.

Performance note:
- This is EditMode popup coldpath only.
- No live UNIT_POWER, OnEvent, secure-click, target-swap, aura, castbar, timer, or OnUpdate runtime was added.
- EditMode popup power-layout behavior now shares the same scoped UFCore/ApplyService path as Menu2 and Assistant detached-power changes.

## EditMode group geometry ApplyService bridge

Observed state:
- EditMode HUD group position reset, EditMode group drag-end, and EditMode undo/apply still called `MSUF.GF.RefreshGeometry()` or legacy `MSUF_GF_*` exports directly.
- The calls were scoped where possible, but they bypassed the central Menu2 ApplyService group queue that now owns group dirty-mask merging, preview refresh, and combat deferral.

Fix applied:
- `MSUF_EditMode_HUD.lua`
  - Group position reset now prefers `ApplyService.RequestGroup(kind, "geometry")` and flushes immediately for EditMode responsiveness.
  - Scoped direct `GF`/legacy calls remain only as fallback if ApplyService is unavailable.
- `MSUF_EditMode_Layout.lua`
  - Group drag-end geometry refresh now uses the same ApplyService bridge with the captured group kind.
  - Live drag movement is unchanged; only the drag-end apply is routed through the queue.
- `MSUF_EditMode_Core.lua`
  - Group apply and undo restore now prefer the ApplyService geometry bridge before direct `GF`/legacy fallback.

Performance note:
- This is EditMode coldpath only: reset, drag-end, and undo/apply.
- No UNIT, roster, target, click, castbar, aura, timer, or live drag OnUpdate hotpath was added.
- Group geometry work now coalesces through the existing group apply queue and uses its combat-safe `GF.DeferGroupRuntime` path when needed.

## Assistant group-copy ApplyService bridge

Observed state:
- The main Assistant group apply helper already preferred `ApplyService.RequestGroup(...)`, but the group-copy fallback still refreshed the destination group directly after copying settings.
- Non-structural copies called `GF.RefreshVisuals(dstKind, dirty)` directly; structural/general copies called `GF.Rebuild(dstKind)` or scoped geometry/unit-binding refreshes directly.

Fix applied:
- `MSUF_AssistantRegistry_GroupFramesActions.lua`
  - Added `RequestGroupCopyRuntime(dstKind, dirty, structural)`.
  - Structural group-copy refreshes now prefer `ApplyService.RequestGroup(dstKind, "rebuild")`.
  - Non-structural group-copy refreshes now prefer `ApplyService.RequestGroupDirtyMask(dstKind, dirty)`, falling back to `RequestGroup(dstKind, "visual")`.
  - Existing direct `GF` and legacy scoped refreshes remain only as fallback if ApplyService is unavailable.

Performance note:
- This is Assistant explicit-action coldpath only.
- No group OnEvent, roster, click, target, castbar, aura, timer, or live drag runtime was added.
- Group-copy apply now shares the same coalesced group queue and combat deferral behavior as Menu2 group settings.

## Assistant ApplyService call-time resolution

Observed state:
- Several Assistant registry helper builders resolved `M.ApplyService` / `MSUF_Menu2_ApplyService` once while the helper was built.
- If the builder loaded before the Menu2 ApplyService was attached, later Assistant actions could stay on legacy fallback paths even though the ApplyService was available by the time the action ran.
- Affected helpers included group apply, aura apply, bar/border apply, visual/color/font/castbar apply, and the shared `CallGlobal` helper.

Fix applied:
- `MSUF_AssistantRegistry_Core_Apply_Group.lua`
  - Group apply now resolves ApplyService inside the returned apply function.
- `MSUF_AssistantRegistry_Core_Apply_Auras.lua`
  - Aura apply now resolves ApplyService at call-time before falling back to Auras3/MenuModel paths.
- `MSUF_AssistantRegistry_Core_Apply_Bars.lua`
  - Bar, gradient, outline, rounded, aggro, dispel, boss-target, and combined highlight border apply helpers now resolve ApplyService at call-time.
- `MSUF_AssistantRegistry_Core_Apply_Visuals.lua`
  - Visual, color, font, castbar, class-power color, and aura-color helper paths now resolve ApplyService at call-time.
- `MSUF_AssistantRegistry_Core_DB.lua`
  - Shared `CallGlobal` now resolves `ApplyService.CallGlobal` at call-time, preserving SafeInvoke/profiling when the service becomes available later.

Performance note:
- This is Assistant explicit-action coldpath only.
- It adds no UNIT, roster, click, target, castbar, aura, timer, or OnUpdate runtime.
- The change makes Assistant live-apply converge on the same Menu2 ApplyService/UFCore paths regardless of addon file load order.

## UFCore live-apply config invalidation

Observed state:
- Menu2 and Assistant writes reached the ApplyService queue, but some changes only became visible after `/reload`.
- Root cause was the UFCore config path: `MSUF_UFCore_NotifyConfigChanged()` called `UF.Apply(unit)` without first invalidating/recompiling the affected `UF.Config` spec outside combat.
- Reload worked because all specs were rebuilt on addon load; live apply could reuse stale compiled specs.
- The ApplyService queue also depended on the global `MSUF_ScheduleDelayOnce()` scheduler for its delayed flush, which made the menu coldpath depend on unrelated scheduler state.

Fix applied:
- `MSUF_UF_Runtime.lua`
  - Added `RefreshConfigForApply(unit)`.
  - `UF.NotifyConfigChanged(unit, applyNow, forceUpdate)` now refreshes only the affected unit/spec family before `UF.Apply()` or `UF.ForceUpdate()`.
  - Global applies still use the full config refresh; unit applies use `Config.RefreshUnit()` through `UF.UnitsForConfigKey()`.
- `MSUF_UF_Config.lua`
  - `Config.RefreshSettingsCache()` now invalidates/rebuilds only the read-mostly settings cache instead of recompiling every unit spec.
  - `BuildSettingsCache()` clears the settings-cache dirty flag after rebuild.
- `MSUF_Menu2_ApplyService.lua`
  - `Apply.QueueFlush()` no longer calls `MSUF_ScheduleDelayOnce()` or `MSUF_ScheduleOnce()`.
  - The menu apply queue now uses its own local `C_Timer.After(APPLY_FLUSH_DELAY, FlushApply)` coalescing and falls back to direct `FlushApply()` when timers are unavailable.

Performance note:
- This is option/Assistant/EditMode coldpath only.
- No UNIT event, target-change, secure-click, castbar OnEvent, aura update, roster event, or per-frame OnUpdate hotpath was added.
- Unit-scoped live apply recompiles only the affected spec family; settings-cache refresh no longer forces a full unit spec rebuild.

Follow-up:
- Scoped Menu2/Assistant runtime applies often set `applyAll=false` or `notify=false` by design to avoid full UnitFrame rebuilds.
- Those paths still need fresh read-mostly color/bar/font settings before runtime repaint helpers run.
- `MSUF_Menu2_ApplyService.lua` now detects scoped/no-notify runtime applies and calls `MSUF_UFCore_RefreshSettingsCache()` once per coalesced flush.
- This covers color, font, bar, gradient, border, power, ClassPower, visual, and frame runtime paths without promoting them to full UFCore reapply.

Performance note:
- This remains ApplyService coldpath only and is coalesced per flush.
- It does not add scheduler dependency, hot events, target/click work, or per-frame updates.
- The settings-cache refresh is intentionally lighter than `NotifyConfigChanged()` and does not rebuild unit specs.

## Advanced Colors ApplyService consolidation

Observed state:
- `MSUF_Menu2_AdvancedColors.lua` still had a page-local color apply queue using `MSUF_ScheduleDelayOnce`/`MSUF_ScheduleOnce`.
- Aura, ClassPower, and portrait color follow-up work used a second page-local delayed fanout after the main color apply.
- Boss-target highlight color used direct UFCore/settings-cache/border refresh calls instead of the shared ApplyService border path.

Fix applied:
- `ApplyColors()` now calls `ApplyService.RequestColors("MSUF2_COLORS")` directly, with a `RequestGeneral(... colors=true)` fallback only when the ApplyService is unavailable.
- Aura color changes now queue `ApplyService.RequestAuraFonts("shared", "MSUF2_AURA_COLORS")` immediately into the same ApplyService flush instead of using a second scheduler.
- ClassPower color changes now queue `ApplyService.RequestClassPower("MSUF2_CLASSPOWER_COLORS", { colors = true, playerHP = true }, ...)`.
- Portrait color changes now queue `ApplyService.RequestGeneral(reason, { applyAll = true, colors = true })` instead of calling `MSUF_UFCore_NotifyConfigChanged()` directly.
- Boss-target highlight color now uses `ApplyService.RequestBossTargetBorder("MSUF2_BOSS_TARGET_HIGHLIGHT_COLOR", "boss")`.
- The only remaining zero-delay timer in the file is the UI reload-prompt display, not a runtime/apply path.

Performance note:
- This is Menu2 color-page coldpath only.
- Rapid slider edits now converge on the same ApplyService coalescing queue as other frontend/Assistant changes.
- No UNIT, target, click, castbar event, aura event, group roster, secure-frame, or OnUpdate runtime was added.

## Menu2 History/Profile Restore ApplyService fanout

Observed state:
- Broad Menu2 history/profile restore already requested the UnitFrame general apply through Menu2, but Auras3 and GroupFrames were still refreshed directly in the same function.
- Auras used `Auras3.RequestApply()` directly.
- GroupFrames used `GF.RefreshAll()`/`GF.RefreshVisuals()` and `GF.RefreshPreviewLayout()` directly.
- Functionally this was correct for whole-snapshot restore, but it bypassed the same ApplyService queue used by normal Menu2 and Assistant live applies.

Fix applied:
- `MSUF_Menu2_Bindings.lua`
  - Added `RequestHistoryAurasRuntime(reason)`, preferring `ApplyService.RequestAuraFonts()` / `RequestAuras()` before legacy Auras3 fallback.
  - Added `RequestHistoryGroupRuntime(reason)`, preferring `ApplyService.RequestGroupReset()` / `RequestGroup("group", "reset")` before direct GF fallback.
  - Added `FlushApplyServiceNow()` so whole-snapshot restores can queue broad domains and flush them immediately for UI responsiveness.
  - Broad history/profile restore now calls those helpers instead of direct Auras3/GF refreshes.

Performance note:
- This is profile/history restore coldpath only.
- Restore remains intentionally broad because a snapshot can span several DB domains.
- The broad work now goes through the same ApplyService coalescing/combat-deferral path before legacy fallbacks.
- No UNIT, target, click, castbar event, aura event, roster event, secure-frame, or OnUpdate hotpath was added.

## Menu2 Page Reset fallback ApplyService routing

Observed state:
- Domain-specific page reset apply paths already preferred `ApplyService` for GroupFrames, Auras, bars, fonts, colors, and ClassPower.
- The final fallback block in `ApplyAfterPageReset()` still repeated direct Auras3, GroupFrame, and ClassPower refresh calls if the domain-specific path returned false.
- That fallback is rarely used, but it is still frontend coldpath behavior and should preserve the same ApplyService-first contract.

Fix applied:
- `MSUF_Menu2_Bindings.lua`
  - Fallback aura/color reset fanout now calls `ApplyAurasPageResetRuntime(reason, visuals)`.
  - Fallback group/bars/fonts/colors fanout now queues `ApplyService.RequestGroupDirtyMask("group", dirty, reason)` or `RequestGroup("group", mode, reason)` before direct GF fallbacks.
  - Fallback ClassPower reset now queues `ApplyService.RequestClassPower(... { full = true, cdm = true } ...)` before direct `MSUF_ClassPower_Apply`.
  - The fallback now calls `FlushApplyServiceNow()` after queuing broad domain work.
  - The group dirty-mask queue is guarded so missing `MSUF.GF` does not pass a nil mask into `RequestGroupDirtyMask`.

Performance note:
- This is Page Reset fallback coldpath only.
- No normal gameplay event, target/click path, secure-frame path, castbar event path, aura event path, roster event path, or OnUpdate was changed.
- The fallback remains broad when needed, but converges on the shared ApplyService queue before legacy direct refreshes.

## Assistant highlight and scale ApplyService routing

Observed state:
- Assistant boss-target highlight color changes refreshed UFCore settings/boss borders directly from `MSUF_AssistantRegistry_GlobalColorSettings_Highlight.lua`.
- Assistant MSUF scale changes called `UF.Apply(nil)` directly after writing `general.msufUiScale`.
- Both are Assistant coldpaths, but they bypassed the shared Menu2 ApplyService queue when the service was available.

Fix applied:
- `MSUF_AssistantRegistry_GlobalColorSettings_Highlight.lua`
  - Boss-target highlight color now prefers `ApplyService.RequestBossTargetBorder(reason, "boss")`.
  - Direct UFCore/boss refresh calls remain only as service-missing fallbacks.
- `MSUF_AssistantRegistry_GlobalColorSettings_Workflow.lua`
  - MSUF scale changes now call `ApplyGeneral("MSUF_ASSISTANT_MSUF_SCALE", { applyAll = true, frames = true })`.
  - The direct `UF.Apply(nil)` call was removed.

Performance note:
- This is Assistant explicit-action/settings coldpath only.
- No UNIT, target, click, castbar event, aura event, roster event, secure-frame, or OnUpdate runtime was added.
- Scale and boss-target highlight updates now coalesce with the same ApplyService flow as Menu2.

## Assistant AutoCoverage fallback tightening

Observed state:
- Generated Assistant AutoCoverage settings already preferred RegistryCore or ApplyService in most known scopes.
- Unit fallback skipped `M.RequestUnitApply()` and went directly to `ApplyService.RequestUnit()` / `UF.Apply()`.
- Unknown scope fallback still called `MSUF_RefreshAllFrames()` directly.
- Group fallback only used `RequestGroup()` from ApplyService before falling back to direct GF/legacy refreshes.

Fix applied:
- `MSUF_AssistantRegistry_AutoCoverage.lua`
  - Unit fallback now tries `M.RequestUnitApply(unit, reason, opts)` before direct ApplyService/UF fallbacks.
  - Group fallback now tries `ApplyService.RequestGroupDirtyMask(groupScope, dirty, reason)` when `RequestGroup()` is unavailable.
  - Unknown scope fallback now tries `M.RequestGeneralApply()` / `ApplyService.RequestGeneral()` with `{ applyAll = true, frames = true }` before direct `MSUF_RefreshAllFrames()`.
  - Group dirty-mask queue is guarded so missing `MSUF.GF` does not pass nil dirty masks into ApplyService.

Performance note:
- This is generated Assistant setting coldpath only.
- Existing direct GF/UF/global refreshes remain only as service-missing fallbacks.
- No UNIT, target, click, castbar event, aura event, roster event, secure-frame, or OnUpdate runtime was added.

## Remove global delay scheduler

Observed state:
- `Kernel/MSUF_Scheduler.lua` still exported `MSUF_ScheduleDelayOnce()`.
- Menu2 history refresh, Auras, Global Bars, Global Castbars, Group fallback apply, and runtime color push still referenced that global delay scheduler.
- The work was coldpath, but keeping a global delay scheduler made apply/debug ownership harder to reason about and left a second scheduling abstraction beside ApplyService.

Fix applied:
- `MSUF_ScheduleDelayOnce()` was removed from `MSUF_Scheduler.lua`.
- `Runtime/MSUF_Colors.lua` now uses its existing local pending flags and local `C_Timer.After()` delay for color/castbar-color visual pushes.
- `MSUF_Menu2_Bindings.lua`, `MSUF_Menu2_Advanced.lua`, `MSUF_Menu2_Auras.lua`, `MSUF_Menu2_GlobalBars.lua`, `MSUF_Menu2_GlobalCastbars.lua`, and `MSUF_Menu2_Group.lua` no longer call the global delay scheduler.
- Pages that need slider/colorpicker coalescing keep small file-local keyed pending maps; Group uses its existing `gfFlushQueued` gate.

Performance note:
- This removes a global scheduler API from the apply layer without making slider/colorpicker changes immediate-per-tick.
- Coalescing remains local to the coldpath owner and does not touch UNIT, target, click, castbar event, aura event, roster event, secure-frame, or OnUpdate runtime.

## Assistant/Menu2 scheduler and duplicate apply cleanup

Observed state:
- `MSUF_Assistant.lua` and `MSUF_AssistantUndo.lua` still used the global `MSUF_ScheduleOnce()` helper for assistant job yielding/broad undo apply.
- The dashboard MSUF frame-scale action requested `M.RequestGeneralApply()` and then directly called `UF.Apply(nil)`, creating duplicate broad unitframe apply work for one frontend action.
- Assistant EditMode shared apply had direct `UF.Apply(nil)` / `MSUF_RefreshAllFrames()` fallback after ApplyService/general apply fallbacks.

Fix applied:
- `MSUF_Assistant.lua`
  - Replaced global `MSUF_ScheduleOnce()` usage with an Assistant-local keyed next-frame queue stored on `A.RuntimePrivate`.
  - The queue coalesces by key and uses `C_Timer.After(0)` only as a local coldpath yield.
- `MSUF_AssistantUndo.lua`
  - Replaced global `MSUF_ScheduleOnce()` usage with an Assistant-undo-local keyed next-frame queue.
- `MSUF_Menu2_Dashboard.lua`
  - MSUF frame-scale apply now requests `M.RequestGeneralApply("MSUF2_DASH_MSUF_SCALE", { preview = true, applyAll = true, frames = true })`.
  - The direct extra `UF.Apply(nil)` call was removed.
- `MSUF_AssistantRegistry_EditMode_Shared.lua`
  - EditMode shared apply now falls back to `MSUF_UFCore_NotifyConfigChanged(nil, true, true, reason)` before failing.
  - Direct `UF.Apply(nil)` / `MSUF_RefreshAllFrames()` fallbacks were removed.

Performance note:
- This is Assistant/Menu2 explicit-action coldpath only.
- It removes duplicate broad unitframe apply for dashboard scaling and removes global scheduler ownership from Assistant yields.
- No UNIT, target, click, castbar event, aura event, roster event, secure-frame, or OnUpdate runtime was added.

## Power secret-value cache hardening

Observed state:
- PTR `Blizzard_APIDocumentationGenerated/UnitDocumentation.lua` marks `UnitPower()` and `UnitPowerPercent()` with `SecretWhenUnitPowerRestricted`, and `UnitPowerMax()` with `SecretWhenUnitPowerMaxRestricted`.
- `MSUF_UF_Elements_Power.lua` could keep a secret `UnitPowerPercent()` result in `bar._msufPowerPercentValue` from an older/current path and later compare that cached field against a new value.
- The same class of issue could happen for absolute power caches and the text runtime's `_msufTextPowerMax` cache.

Fix applied:
- `MSUF_UF_Elements_Power.lua`
  - Added small local helpers for secret checks, value-cache clearing, and direct StatusBar value application.
  - Percent power updates no longer compare or retain secret percent values.
  - Secret percent values are passed directly to `StatusBar:SetValue()` without interpolation and without text-dispatch caching.
  - Absolute power updates no longer compare cached power/minmax values when either side is secret.
  - Secret `UnitPower()` / `UnitPowerMax()` results invalidate the normal-number caches instead of becoming cache keys.
- `MSUF_UF_Text_Runtime.lua`
  - `_msufTextPowerMax` is no longer seeded or retained when `UnitPowerMax()` returns a secret value.
  - Any old secret `_msufTextPowerMax` cache is cleared before reuse.

Performance note:
- Normal non-secret power updates keep the existing event-driven dedupe and smoothing.
- Secret power updates follow the Blizzard-safe path: direct API result into the StatusBar, no Lua math, compare, or cache key.
- No polling, OnUpdate, target fanout, or extra runtime refresh was added.

## UnitSections and Assistant ToT inline apply routing

Observed state:
- Unit page preview apply still called `UF.Apply(key)` directly from `panel._msufAPI.ApplySettingsForKey`.
- Target-of-target inline text controls still called `M.RequestUnitApply()` and then forced `UF.ForceUpdate("targettarget")`.
- Assistant ToT inline apply still forced `UF.ForceUpdate("targettarget")`.
- Assistant unit apply fallback still reached the old direct `UF.Apply(unit)` path if Menu2/ApplyService helpers were unavailable.

Fix applied:
- `MSUF_Menu2_UnitSections.lua`
  - Added a small page-local `RequestUnitRuntimeApply()` helper that routes through ApplyService or `M.RequestUnitApply()` with `history=false`.
  - Unit page preview apply now requests a unit apply through that helper instead of direct `UF.Apply(key)`.
  - ToT inline live update now requests `target` and `targettarget` applies through the same helper and flushes ApplyService only for the explicit force-live case.
- `MSUF_AssistantRegistry_Unitframes_Core_TextSpecial.lua`
  - Assistant ToT inline apply now flushes ApplyService after the queued unit applies.
  - If ApplyService is unavailable, it notifies the new UFCore through `MSUF_UFCore_NotifyConfigChanged("targettarget", true, true, reason)`.
  - Direct `UF.ForceUpdate("targettarget")` was removed.
- `MSUF_AssistantRegistry_Core_Apply.lua`
  - Unit fallback now uses `MSUF_UFCore_NotifyConfigChanged(unit, true, true, reason)` instead of direct `UF.Apply(unit)`.

Performance note:
- This is Menu2/Assistant coldpath only.
- It keeps live preview behavior but avoids bypassing the ApplyService/UFCore queue and avoids unnecessary history snapshots for internal preview/runtime apply.
- No UNIT, target, click, castbar event, aura event, roster event, secure-frame, or OnUpdate runtime was added.

## Assistant group/border apply routing cleanup

Observed state:
- Assistant group apply helpers still had direct `MSUF.GF.RefreshVisuals()`, `RefreshGeometry()`, `RefreshAll()`, and global `MSUF_GF_Refresh*` branches in the normal fallback body.
- Generated Assistant auto-coverage settings could still fall back from a unit setting to direct `UF.Apply()` / `MSUF_RefreshAllFrames()`.
- Boss-target border/highlight color Assistant settings could still call `UF.RefreshBorders("boss")` directly.
- Assistant group-copy and undo paths only used ApplyService when it existed, then jumped straight to GF refresh/rebuild calls.

Fix applied:
- `MSUF_AssistantRegistry_Core_Apply_Group.lua`
  - Group apply now routes first through ApplyService, using `RequestGroupDirtyMask()` for non-structural dirty modes.
  - `RequestGroup()` is used for rebuild/reset/targeted structural modes.
  - `M.GroupPage.QueueGF()` is the secondary fallback; direct GF/global refresh calls are limited to the named legacy fallback helper.
- `MSUF_AssistantRegistry_AutoCoverage.lua`
  - Unit fallback now routes through `M.RequestUnitApply()` / ApplyService and then `MSUF_UFCore_NotifyConfigChanged()`.
  - Group fallback now uses dirty-mask ApplyService routing first, then `GroupPage.QueueGF()`, then the named legacy fallback.
  - Broad/general fallback now uses ApplyService or `MSUF_UFCore_NotifyConfigChanged(nil, true, true, reason)` instead of direct `MSUF_RefreshAllFrames()`.
- `MSUF_AssistantRegistry_Core_Apply_Bars.lua`
  - Boss-target border fallback no longer calls `UF.RefreshBorders()` directly.
  - It refreshes settings cache, then routes through ApplyService `RequestUnit()` or `MSUF_UFCore_NotifyConfigChanged()`.
- `MSUF_AssistantRegistry_GlobalColorSettings_Highlight.lua`
  - Boss target highlight color now uses ApplyService `RequestBossTargetBorder()` first.
  - Fallback is ApplyService `RequestUnit("boss", ...)` or UFCore notify, not direct border/frame refresh.
- `MSUF_AssistantRegistry_GroupFramesActions.lua`
  - Group copy runtime now tries `GroupPage.QueueGF()` before legacy direct refresh when ApplyService is missing.
- `MSUF_AssistantUndo.lua`
  - Group undo fallback now tries `GroupPage.QueueGF()` for party/raid/mythicraid rebuild before the final legacy GF fallback.

Performance note:
- These are Assistant/Menu2 coldpath routes only.
- The change narrows generated/live Assistant apply work to dirty-mask or unit-scoped requests where possible.
- Remaining direct GF calls are documented as last-resort legacy fallbacks when ApplyService/GroupPage are missing; they are not the normal runtime route.
- No UNIT, target, click, castbar event, aura event, roster event, secure-frame, or OnUpdate runtime was added.

## Menu2 GlobalBars and AdvancedColors apply routing cleanup

Observed state:
- `MSUF_Menu2_AdvancedColors.lua` boss-target highlight color still called `UF.RefreshBorders("boss")`, `MSUF_RefreshAllFrameColors("boss")`, or `MSUF_RefreshAllFrames("boss")` from the page fallback.
- `MSUF_Menu2_GlobalBars.lua` had local page fallback functions that directly refreshed unit borders, unit aura elements, group visuals, group borders, rounded previews, and boss target borders.
- Some of those paths were already behind ApplyService-specific request methods, but the page-local fallbacks still bypassed ApplyService/UFCore before reaching legacy code.

Fix applied:
- `MSUF_Menu2_AdvancedColors.lua`
  - Boss-target highlight color now uses ApplyService `RequestBossTargetBorder()` first.
  - Fallback is ApplyService `RequestUnit("boss", ...)` or `MSUF_UFCore_NotifyConfigChanged("boss", true, true, reason)`.
  - Direct page-level `UF.RefreshBorders()` / frame-color refresh fallback was removed.
- `MSUF_Menu2_GlobalBars.lua`
  - Added page-local `RequestUnitRuntime()`, `RequestUnitsRuntime()`, and `RequestGroupFrameDirty()` helpers.
  - Unit border and unit aura page fallbacks now try ApplyService/UFCore before direct frame or element refresh.
  - Boss unitframe fanout is compressed to the UFCore `boss` config family instead of manually touching every `boss1..boss5` frame when ApplyService/UFCore is available.
  - Group visual/border fallbacks now try ApplyService dirty-mask routing before direct GF refresh.
  - Rounded fallback now uses ApplyService/UFCore before `MSUF_RefreshAllFrames()`, and group preview refresh is routed through ApplyService dirty-mask when available.

Performance note:
- Normal page actions now enter the existing ApplyService queue and keep coalescing/coldpath behavior.
- Direct `UF.ApplyElementToFrame()`, `UF.RefreshBorders()`, `MSUF_RefreshAllFrames()`, and direct GF refresh calls remain only as last-resort legacy fallbacks if ApplyService/UFCore are unavailable.
- No UNIT, target, click, castbar event, aura event, roster event, secure-frame, or OnUpdate runtime was added.

## Live color, group font, and portrait apply regression

Observed state:
- Global Unitframe Coloring controls wrote the correct DB values, but `ApplyService.RequestColors(..., applyAll=false)` did not notify the new UFCore. Health class mode, health gradient stops, power color overrides, and portrait colors could therefore keep using stale compiled unit specs until another broad refresh or a preview click happened.
- Group-frame visual refresh invalidated compiled specs only for broad config/all masks. Narrow live applies such as `DIRTY_FONT` could reuse stale group specs, so Assistant font-size changes appeared to apply only after interacting with the preview.
- The Colors page still showed the old "Unitframe color changes" reload recommendation for live color-mode edits, which no longer matches the new UFCore path.
- Portraits were laid out and shown by `Portrait.Apply()`, but the initial `SetPortraitTexture(texture, unit)` / class-portrait paint was deferred until a later portrait event. Newly enabled portraits could therefore appear empty.
- Boss preview state cleared `_msufBossPreviewForced` after the runtime refresh when disabling preview. That allowed a preview portrait to remain on a real boss frame until another portrait event.

Fix applied:
- `MSUF_Menu2_ApplyService.lua`
  - `ApplyColorRuntime()` now calls `MSUF_UFCore_NotifyConfigChanged()` for global and unit-scoped color applies before falling back to legacy color refresh functions.
  - This keeps color-only edits on the ApplyService coldpath while forcing the unit specs that contain health/power/portrait colors to recompile immediately.
- `MSUF_UF_Group_Runtime.lua`
  - `GF.RefreshVisuals()` invalidates compiled group specs for every explicit settings-driven visual refresh, not only broad all/config masks.
  - This fixes narrow font/color/visual live applies without adding group runtime fanout.
- `MSUF_Menu2_AdvancedColors.lua`, `MSUF_Menu2_UnitSections.lua`, `MSUF_AssistantRegistry_Unitframes_CoreLoop.lua`
  - Removed the reload recommendation from Unitframe color-mode changes.
  - Unit health color-mode applies now request a live unit apply with color intent instead of presenting it as reload-only work.
- `MSUF_UF_Elements_Portrait.lua`
  - `Portrait.Apply()` now paints the initial 2D/class portrait immediately when the holder is visible.
  - Boss preview portraits are ignored when a real `boss1..boss5` unit exists, so stale preview globals cannot override a live boss unit.
- `MSUF_UF_Elements_LoadConditions.lua`
  - Disabling boss preview clears frame preview state before refreshing boss runtime/elements, then repaints real boss data.
  - Boss preview frame data is no longer applied over real `boss1..boss5` units; a live boss unit clears the preview-forced state instead.

Performance note:
- All fixes are menu/assistant/apply or portrait event coldpaths.
- Health gradient remains backed by `C_CurveUtil.CreateColorCurve()` and `UnitHealthPercent(unit, true, curve)` in `MSUF_UF_Elements_BarsCommon.lua`; no manual percent-gradient tick was added.
- No UNIT, target, click, castbar event, aura event, roster event, secure-frame, or OnUpdate runtime was added.

## Assistant color apply regression

Observed state:
- Menu2 live preview changes reached the new ApplyService path and refreshed live frames, but Assistant setting changes only called each setting's `apply()` callback and then returned the "Done" response.
- Assistant global `barMode` was registered with `ApplyVisuals`. That path refreshes textures/fonts/preview, but class, unified, and gradient health modes are compiled Health spec fields and must go through the color/spec apply path.
- The symptom was DB/state changing correctly through the Assistant while live unitframes stayed on the old color mode until another menu/preview interaction or reload forced a broader apply.

Fix applied:
- `MSUF_Assistant.lua`
  - `RunApplies()` now flushes `MSUF_Menu2_ApplyService` once after all changed Assistant settings have queued their work.
  - This keeps Assistant changes deterministic without adding any runtime or UNIT-event work.
- `MSUF_AssistantRegistry_Global_BaseSettings_Appearance.lua`
  - Global Bar Mode now uses `ApplyColors` instead of `ApplyVisuals`, so class/unified/gradient mode changes recompile UFCore Health specs and repaint live frames.

Performance note:
- This is Assistant-only coldpath work.
- The flush is once per Assistant response, after coalescing all setting callbacks.
- No UNIT, target, click, castbar event, aura event, roster event, secure-frame, or OnUpdate runtime was added.

## Health core color cache regression

Observed state:
- Class color, unified color, dark mode, and health gradient could leave mixed live-frame colors after a menu or Assistant apply.
- The DB and compiled specs were correct, but `Health.Apply()` first painted the health bar with the static compiled fallback color.
- `ApplyHealthStatusColor()` owns a separate runtime status-color cache (`_msufStatusR/G/B/A`). If that cache already matched the intended runtime color, the runtime repaint skipped `SetStatusBarColor()` even though the static apply had just overwritten the real bar color.
- `Runtime/MSUF_Colors.lua` also looked for `MSUF_UFCore_RefreshHealthBarColor`, but the new UFCore Health element did not export it yet. Background/missing-HP visual refresh could therefore read stale statusbar colors.

Fix applied:
- `MSUF_UF_Elements_Health.lua`
  - Direct static `SetColor()` now invalidates `_msufStatusR/G/B/A` whenever it writes the statusbar color.
  - Added `Health.RefreshColor()` and exported it as `MSUF_UFCore_RefreshHealthBarColor`.
  - Color refresh now repaints through the same Health element path that live frames use, instead of depending on a stale runtime cache.
- `MSUF_Colors.lua`
  - Unitframe colors are refreshed before bar-background/missing-HP visuals read statusbar colors.
  - Background refresh skips the extra per-frame health repaint when the UFCore color refresh has already run.

Performance note:
- This is config/menu/Assistant apply coldpath plus existing identity/color refresh only.
- Class/unified/dark modes do not add any `UNIT_HEALTH` work after the setting has been applied.
- Health gradient still uses Blizzard's PTR C-side curve path, `UnitHealthPercent(unit, true, curve)`, backed by `C_CurveUtil.CreateColorCurve()`.
- No target/click, secure-frame, roster, castbar, aura, or OnUpdate runtime was added.

## Combat-safe visual apply deferral

Observed state:
- `Runtime/MSUF_Colors.lua` still allowed a broad global visual flush to execute if a color push was scheduled just before entering combat or triggered while already in combat.
- `MSUF_Menu2_ApplyService.lua` could also flush pending Assistant/Menu2 work in combat, which meant color/font/bar/group/preview requests could still call into `MSUF_UFCore_NotifyConfigChanged`, unitframe refreshes, group refreshes, or preview refreshes during combat.
- That is not a gameplay hotpath, but it violates the current performance rule: settings/apply work should cost nothing during combat.

Fix applied:
- `MSUF_Colors.lua`
  - `PushVisualUpdates()` and `PushCastbarVisualUpdates()` now only set a pending combat flag while `InCombatLockdown()` is true.
  - If a previously scheduled color/castbar visual timer fires during combat, the flush aborts, clears its pending timer flag, and registers `PLAYER_REGEN_ENABLED`.
  - On `PLAYER_REGEN_ENABLED`, color and castbar visual changes are coalesced back into one normal post-combat flush.
- `MSUF_Menu2_ApplyService.lua`
  - `FlushApply()` now exits immediately in combat and keeps all pending work queued.
  - It registers `PLAYER_REGEN_ENABLED` once and applies the queued settings after combat.
  - Pending data is not rebuilt or scanned while in combat.

Performance note:
- In combat, these paths do not scan frames, compile specs, refresh groups, refresh previews, update fonts, update bars, or call broad visual globals.
- The only in-combat work is setting a Lua boolean and registering `PLAYER_REGEN_ENABLED`.
- The deferral pattern follows Blizzard's local PTR UI source usage of `InCombatLockdown()` plus `PLAYER_REGEN_ENABLED` for combat-safe UI work.
- No UNIT, target, click, castbar event, aura event, roster event, secure-frame, or OnUpdate runtime was added.
