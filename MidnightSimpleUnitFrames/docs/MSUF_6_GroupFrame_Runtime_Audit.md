# MSUF 6.0 GroupFrame Runtime Audit

## File Shape

The new GroupFrame runtime is split by responsibility:

- `MSUF_UF_Group_Config.lua`: compiles DB/profile data into UF specs.
- `MSUF_UF_Group_Config_Indicators.lua`: compiles corner/spell indicator data.
- `MSUF_UF_Group_SpellRegistry.lua`: lightweight SpellIndicator registry bridge.
- `MSUF_UF_Group_AuraCache.lua`: single aura snapshot source.
- `MSUF_UF_Group_Status.lua`: role/leader/assist/ready/summon/phase/status/range.
- `MSUF_UF_Group_Visuals.lua`: target, health fade, debuff stripe, dispel overlay.
- `MSUF_UF_Group_Auras.lua`: group aura lanes.
- `MSUF_UF_Group_Indicators.lua`: corner and spell indicator rendering.
- `MSUF_UF_Group_Headers.lua`: secure header creation/layout.
- `MSUF_UF_Group_Adapter.lua`: secure child attachment to `MSUF.UF`.
- `MSUF_UF_Group_Runtime.lua`: public APIs, events, and compatibility shims.

No file except `MSUF_UF_Group_Config.lua` is currently above 200 lines; config is
kept larger because it is the single DB-to-spec compiler.

## Performance Checks

- No GroupFrame `OnUpdate` remains in `UnitFrames/Core/Group`.
- `C_UnitAuras.GetAuraSlots` / `GetAuraDataBySlot` are only called by
  `MSUF_UF_Group_AuraCache.lua`.
- `UNIT_AURA` builds one shared snapshot per group frame; visuals, aura lanes,
  corner indicators, and spell indicators consume that snapshot.
- Runtime group elements do not call `GF.GetConf()` or `GF.EnsureDB()` inside
  unit-event handlers. DB reads happen during spec compilation, header rebuild,
  tooltip entry, and explicit refresh paths.
- `C_Timer.After` is only used for secure header child discovery after rebuild.
- Header rebuilds are combat-deferred through `GF.DeferGroupRuntime`.

## Feature Wiring

Connected through the new runtime:

- Secure Party/Raid/MythicRaid headers.
- `MSUF.UF.AttachFrame` / `MSUF.UF.ApplySpec` adapter path.
- Health, power, text, prediction, status indicators, borders.
- Role, leader, assist, ready check, summon, phase, incoming resurrection.
- Raid marker, group number, status text.
- Range/offline fade, target indicator, health fade.
- Debuff stripe and dispel overlay.
- Basic group aura lanes.
- Corner indicators and spell indicators using compiled spellId/name lookup,
  placed icon/square/bar/number renderers, cooldown frames, and frame effects.
- Dirty refresh shims: `MarkDirty`, `MarkAllDirty`, `RefreshOverlays`,
  `RefreshBorder`, `RefreshOutlineGeometry`, `RefreshColors`, `RefreshFonts`.
- EditMode/Menu2 compatibility shims: preview refresh, active preview kind,
  nudge preview.

## Known Limits

- SpellIndicator defaults are restored as cold registry data; runtime rendering
  remains in the UF-core group indicator element.
- Private-aura anchors and Masque integration are still pending.
- In-game validation is still required for secure header behavior in combat,
  party/raid/mythic transitions, and live aura rendering.
