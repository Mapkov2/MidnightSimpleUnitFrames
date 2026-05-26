# MSUF 6.0 GroupFrame Clean Cut

This branch now keeps the GroupFrame database/profile surface while replacing
the old GroupFrame runtime loader with a UF-core-backed runtime path.

## Loader State

- `MSUF_GroupFrames.xml` loads only:
  - `GroupFrames/MSUF_GroupFrames_DB.lua`
  - `GroupFrames/MSUF_GroupFrames_DB_SpellIndicators.lua`
  - `UnitFrames/Core/Group/MSUF_UF_Group_SpellRegistry.lua`
  - `UnitFrames/Core/Group/MSUF_UF_Group_Config_Indicators.lua`
  - `UnitFrames/Core/Group/MSUF_UF_Group_Config.lua`
  - `UnitFrames/Core/Group/MSUF_UF_Group_AuraCache.lua`
  - `UnitFrames/Core/Group/MSUF_UF_Group_Status.lua`
  - `UnitFrames/Core/Group/MSUF_UF_Group_Visuals.lua`
  - `UnitFrames/Core/Group/MSUF_UF_Group_Auras.lua`
  - `UnitFrames/Core/Group/MSUF_UF_Group_Indicators.lua`
  - `UnitFrames/Core/Group/MSUF_UF_Group_Headers.lua`
  - `UnitFrames/Core/Group/MSUF_UF_Group_Adapter.lua`
  - `UnitFrames/Core/Group/MSUF_UF_Group_Runtime.lua`
- `Auras3/MSUF_Auras3_Runtime.xml` keeps `MSUF_Auras3_GroupFiltering.lua`.
- Old GroupFrame runtime, preview bridge, fallback, and group aura runtime files
  have been removed from the repository.

## New Runtime Shape

- `MSUF.GF.CompileSpec(kind, frame, unit)` compiles `gf_party`, `gf_raid`, and
  `gf_mythicraid` profile data into UF-compatible specs outside unit-event
  hotpaths.
- SecureGroupHeaders create the secure unit buttons.
- Header children are attached through `MSUF.UF.AttachFrame(..., { scope =
  "group", ownEvents = false })` and applied through `MSUF.UF.ApplySpec`.
- Runtime APIs restored:
  - `MSUF.GF.RebuildAll()`
  - `MSUF.GF.RefreshAll()`
  - `MSUF.GF.RefreshVisuals(kind)`
  - `MSUF.GF.UpdateGroupVisibility()`
  - `MSUF.GF.ForEachFrame(fn, includeHidden)`

## Implemented First Pass

- Health, power, text, heal prediction, borders, status icon layout, and status
  updates reuse the central UF core.
- Group-specific runtime elements cover role/assist/ready/summon/phase,
  raid marker, incoming resurrect, group number, range/offline fade, target
  indicator, debuff stripe, dispel overlay, health fade, corner indicators,
  spell-indicator icons, and basic aura lanes.
- Aura scanning uses Blizzard aura slot/data APIs and does not compare live
  aura names, tooltips, or hidden payloads.
- Spell/corner matching is compiled from restored spell registry data and saved
  configs into spellId/name lookup tables consumed by the shared AuraCache.

## Remaining Work

- Dedicated private-aura anchors and Masque integration need a second pass.
- In-game parity validation is still needed for all restored spell-indicator
  defaults across supported specs.
- Native Menu2 preview can remain visible, but live preview/edit-mode bridge
  APIs should be reconnected to the new runtime instead of restoring legacy
  bridge files.
