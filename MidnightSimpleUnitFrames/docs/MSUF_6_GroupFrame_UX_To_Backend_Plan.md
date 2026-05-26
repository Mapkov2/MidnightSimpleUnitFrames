# MSUF 6.0 GroupFrame UX-to-Backend Plan

This plan treats Menu2 Group UX as the contract and the new `MSUF.UF` core as
the engine. Group code should only own secure group headers, roster layout, and
features that are inherently group-specific.

## Non-Negotiables

- Keep UX and saved DB compatible with `gf_party`, `gf_raid`, and
  `gf_mythicraid`.
- Do not port old 5.53 backend architecture. Use 5.53 only as behavioral
  reference.
- Compile DB into `MSUFSpec` before runtime events. No `GF.GetConf()` or DB
  table reads inside `UNIT_HEALTH`, `UNIT_POWER_*`, `UNIT_AURA`,
  `UNIT_IN_RANGE_UPDATE`, or status hotpaths.
- Reuse existing UF elements first: health, power, prediction, text, alpha,
  borders, backgrounds, status text, raid marker, leader, incoming res.
- Implement group-only behavior as small UF elements under
  `UnitFrames/Core/Group/`.
- No broad per-button event ownership. Group buttons attach with
  `UF.AttachFrame(frame, { scope = "group", ownEvents = false })` and consume
  the central UF event driver.
- Avoid `OnUpdate` in group frames. Only bounded animation/timer cases are
  allowed and must be documented.
- Secret/declassified API rule: never branch on secret booleans in Lua. Use
  Blizzard-safe APIs, pass secret values through to C-safe setters, or skip.
- Secure rule: no secure header layout or attribute changes in combat. Queue and
  replay on `PLAYER_REGEN_ENABLED`.

## File Ownership

| File | Owns | Must not own |
| --- | --- | --- |
| `MSUF_UF_Group_Config.lua` | DB-to-`MSUFSpec` compile, scaled metrics, UF element config | event handlers, frame creation |
| `MSUF_UF_Group_Config_Indicators.lua` | compiled corner/spell indicator specs | aura scanning, icon drawing |
| `MSUF_UF_Group_Headers.lua` | secure headers, anchors, group grid attributes | visual element logic |
| `MSUF_UF_Group_Adapter.lua` | attach header children to UF core, `ApplySpec`, frame iteration | feature logic |
| `MSUF_UF_Group_Blizzard.lua` | Blizzard group-frame ownership and fallback | MSUF frame layout |
| `MSUF_UF_Group_Runtime.lua` | public APIs, event coalescing, dirty refresh routing | feature rendering |
| `MSUF_UF_Group_Status.lua` | role/leader/assist/ready/summon/phase/res/range/offline status elements | aura filtering |
| `MSUF_UF_Group_Visuals.lua` | target, health fade, dispel overlay, debuff stripe | secure header attributes |
| `MSUF_UF_Group_AuraCache.lua` | one aura snapshot per frame/unit | rendering decisions |
| `MSUF_UF_Group_Auras.lua` | buff/debuff/external/private aura lanes | spell indicator matching |
| `MSUF_UF_Group_Indicators.lua` | corner indicators and spell indicator rendering | DB normalization |

Target size: keep hot/warm runtime files around 100-250 lines. `Config` and DB
files may be larger because they are cold compile/default surfaces.

## Implementation Flow

1. Pick one Menu2 section.
2. List every visible control and DB key.
3. Compile the keys into `MSUFSpec` in `MSUF_UF_Group_Config.lua` or the focused
   config module.
4. Wire the spec into an existing UF element if possible.
5. If no UF element fits, add one focused group element.
6. Add refresh routing: `rebuild`, `geometry`, `visual`, `font`, `auras`.
7. Compare live behavior against 5.53 and the Menu2 preview.
8. Run static checks: XML file exists, `luac -p`, no hotpath DB reads.
9. In-game test the section before starting the next one.

## Phase Order

1. Runtime foundation and header parity.
2. Layout, anchoring, scaling, visibility, Blizzard fallback.
3. Base visuals: health, power, text, fonts, textures, alpha, borders.
4. Group status: role, leader, assist, ready, summon, resurrect, phase,
   raid marker, group number, offline and range fade.
5. Aura lanes: buffs, debuffs, externals, private auras, cooldown text, Masque.
6. Indicators: corner indicators, spell indicators, frame effects.
7. Preview/EditMode parity using the same compiled spec path.
8. Performance pass and 5.53 parity signoff.

## Current Group Layout Backend Status

Implemented in the UF-core-backed runtime:

- `enabled`, `showPlayer`, `showSolo`, Blizzard fallback, combat-deferred
  rebuilds, and client-scene hiding.
- `width`, `height`, `spacing`, growth, scaling, `unitsPerColumn`,
  `maxColumns`, raid group filtering, and secure header child sizing.
- `sortMode`, `sortByRole`, `roleOrder`, `preserveRaidGroups`, and name/index
  sorting through SecureGroupHeader-supported attributes.
- `anchorToFrame`, `anchorPoint`, `offsetX`, and `offsetY`.
- `tooltipMode` and `tooltipModifier` through cold-path mouse scripts.
- `smoothFill`, `reverseFill`, backdrop color/opacity, HP fill/track opacity,
  HP text opacity behavior, and UF alpha layer mapping.
- Offline hide/fade with delay and range fade driven only by
  `UNIT_IN_RANGE_UPDATE`, `UNIT_OTHER_PARTY_CHANGED`, `UNIT_PHASE`, and
  `UNIT_CTR_OPTIONS`.
- Growth direction follows the 5.53/oUF-style SecureGroupHeader contract:
  `xOffset`/`yOffset` are spacing-only values because the secure header already
  accounts for child width and height. Outside combat, layout-affecting changes
  are applied while the header is hidden and then nudged with a nonce so existing
  children are repositioned immediately; in combat the rebuild is deferred.

SecureHeader sorting note:

- `playerFirstInRole` is implemented for role sort with a cold-built
  `nameList` and `sortMethod = "NAMELIST"`. The list is rebuilt outside combat
  on menu/layout/roster changes and cleared when native sort modes are used.
- True nested `Group + Role` secondary sorting still cannot be forced inside one
  SecureGroupHeader without moving to a multi-header raid layout.

## UX Feature Matrix

### Group Layout: General

| UX | DB keys | Backend owner | Implementation rule |
| --- | --- | --- | --- |
| Use MSUF group frames | `enabled` | `Runtime`, `Headers`, `Blizzard` | Show/hide MSUF header; call Blizzard ownership after visibility changes. |
| If this switch is off | `blizzardFallbackMode` | `Group_Blizzard` | Preserve `AUTO/SHOW/NONE`; AUTO hides Blizzard if any MSUF group scope is active. |
| Show player | `showPlayer` | `Headers` | SecureGroupHeader attribute only, combat deferred. |
| Show while solo | `showSolo` | `Headers` | SecureGroupHeader attribute only, combat deferred. |
| Smooth health fill | `smoothFill` | UF health element | Compile into health spec; no group renderer. |
| Reverse fill direction | `reverseFill` | UF health/power element | Compile once into bar orientation spec. |
| Hide during client scene | `hideInClientScene` | `Runtime` | Gate header visibility on scene events; coalesce refresh. |
| Offline Members | `hideOfflineEnabled`, `hideOfflineInCombat`, `hideOfflineDelay`, `offlineAlpha` | `GroupRangeFade` / group status | Event-driven; no polling; no DB reads after spec compile. |

### Group Layout: Layout And Sorting

| UX | DB keys | Backend owner | Implementation rule |
| --- | --- | --- | --- |
| Frame size | `width`, `height`, `spacing` | `Config`, `Headers` | Compile scaled metrics; SecureHeader initial config sets child size. |
| Growth direction | `growth` | `Headers` | Map to `point`, `xOffset`, `yOffset`, `columnAnchorPoint`. |
| Raid grid | `unitsPerColumn`, `maxColumns`, `preserveRaidGroups`, `groupFilter` | `Headers`, DB metrics | Secure attributes only; no combat mutation. |
| Sort mode | `sortMode`, `sortByRole` | `Headers` | Use secure `sortMethod`, `groupBy` where supported. |
| Role priority | `roleOrder` | `Headers` | Compile to `groupingOrder`. |
| Player first in role | `playerFirstInRole` | `Headers` | For ROLE mode, build a secure `nameList` outside combat; fallback to native role sort if roster data is unavailable. |

### Group Layout: Scaling, Anchor, Tooltip

| UX | DB keys | Backend owner | Implementation rule |
| --- | --- | --- | --- |
| Frame scaling | `frameScaleMode`, `frameScaleManual`, `scaleAt10`, `scaleAt20`, `scaleAt25`, `scaleOver25` | `Config`, DB helpers, `Headers` | Apply during metric compile only. |
| Transparency | `alphaInCombat`, `alphaOutOfCombat`, `alphaSync`, `alphaExcludeTextPortrait`, `alphaLayerMode`, `alphaFG*`, `alphaHP*`, `alphaBG*` | UF alpha/visual spec | Use UF alpha layers; group-specific code only maps DB keys. |
| Backdrop opacity/color | `bgR`, `bgG`, `bgB`, `bgA` | UF background/health spec | Compile color/alpha into spec. |
| Health opacity | `hpBarAlpha`, `hpBgAlpha`, `alphaPreserveHPColor`, `hpTextIgnoreAlpha` | UF health/text spec | No per-event DB reads. |
| Anchor to frame | `anchorToFrame`, `anchorPoint`, `point`, `offsetX`, `offsetY` | `Headers` | Resolve anchor cold; combat defer changes. |
| Tooltip | `tooltipMode`, `tooltipModifier` | `Adapter` / tooltip element | Mouse scripts only; no status/aura logic. |

### Health, Power, Text

| UX | DB keys | Backend owner | Implementation rule |
| --- | --- | --- | --- |
| Dispel overlay | `dispelOverlayEnabled`, `dispelOverlayTrigger`, `dispelOverlayStyle`, `dispelOverlayOnHealth`, `dispelOverlayAlpha` | `GroupVisuals` + `AuraCache` | Consume compiled dispel state from aura snapshot. |
| Global health colors | `gfBarMode`, global color keys | `Config`, UF health | Resolve once in spec; global changes trigger visual refresh. |
| Custom bars | `barTexture`, `barBgTexture`, `healthColorMode`, custom RGB | UF health/background | Use shared texture resolver; no custom drawing path. |
| Power bar | `powerBarEnabled`, `powerHeight`, `powerSmoothFill`, `powerShowTank`, `powerShowHealer`, `powerShowDamager` | `Config`, UF power | Role visibility compiled per frame/spec. |
| Name text | `showName`, `hideNameOnDeadOffline`, `nameAnchor`, `nameOffsetX`, `nameOffsetY`, `nameFontSize`, name color/truncation keys | UF text | Reuse UF text layout; status hiding is a group status flag in spec. |
| Health text slots | `showHPText`, `textLeft`, `textCenter`, `textRight`, `textDelimiter`, `hpTextReverse`, offsets, per-slot offsets, `hpFontSize`, `textLayer` | UF text | Compile three slots; use secret-safe formatter helpers. |
| Power text slots | `showPower`, `showPowerText`, `powerTextLeft`, `powerTextCenter`, `powerTextRight`, `powerTextDelimiter`, offsets, per-slot offsets, `powerFontSize`, `powerTextLayer` | UF text | Same slot system as health text. |
| Debuff stripe | `debuffStripeEnabled`, `debuffStripeEdge`, `debuffStripeHeight`, `debuffStripeAlpha`, RGB | `GroupVisuals` + `AuraCache` | Render from compiled aura snapshot flags. |
| Range Fade | `rangeFadeEnabled`, `rangeFadeAlpha`, `rangeFadeLayerMode` | `GroupRangeFade` | Only use `UNIT_IN_RANGE_UPDATE`, `UNIT_OTHER_PARTY_CHANGED`, `UNIT_PHASE`, `UNIT_CTR_OPTIONS`. |

### Indicators And Status Icons

| UX | DB keys | Backend owner | Implementation rule |
| --- | --- | --- | --- |
| Group number | `showGroupNumber`, `groupNumberSize`, `groupNumberAnchor`, `groupNumberX`, `groupNumberY` | `GroupStatusRuntime` | Update on roster/header scan. |
| Focus highlight | `hlFocusEnabled`, `hlFocusSize`, focus color keys | UF border/visual or `GroupVisuals` | Event-driven target/focus updates. |
| Group border | `groupBorderEnabled`, `groupBorderSize`, `groupBorderPadding`, RGB/A | `Headers` anchor visuals | Draw on anchor, not every child. |
| Icon style | `iconStyle`, `useMidnightIcons`, external pack keys | DB resolver + status spec | Resolve texture paths during compile. |
| Role icon | `roleIcon*`, `roleIconShowTank`, `roleIconShowHealer`, `roleIconShowDPS` | `GroupStatusRuntime` | Compile filters; update on role/roster events. |
| Leader/assist | `leaderIcon*`, `assistIcon*` | `GroupStatusRuntime` | Update on group roster/leader events. |
| Raid marker | `raidMarker*` | UF raid marker or group status | Reuse existing UF marker if compatible. |
| Ready check | `readyCheckIcon*` | `GroupStatusRuntime` | `READY_CHECK`, `READY_CHECK_CONFIRM`, `READY_CHECK_FINISHED`. |
| Summon | `summonIcon*` | `GroupStatusRuntime` | Use safe summon-status APIs only. |
| Resurrect | `resurrectIcon*` | UF incoming res / group status | Prefer existing UF incoming res element. |
| Phase | `phaseIcon*` | `GroupStatusRuntime` | Use safe phase APIs/events; avoid secret branching. |
| Dead/Ghost/AFK text | `statusText*`, `statusGhostText*`, `statusAFKText*` | `GroupStatusRuntime` + UF text | Compile separate text settings; update on unit status events. |

### Spell Indicators

| UX | DB keys/tables | Backend owner | Implementation rule |
| --- | --- | --- | --- |
| Master enable | `spellIndicators.enabled` | `Config_Indicators`, `GroupSpellIndicators` | Compile to immutable lookup tables. |
| Spec mode | `spellIndicators.spec`, `specs` | `SpellRegistry`, `Config_Indicators` | Resolve current spec outside aura hotpath. |
| Layer | `spellIndicators.layer` | `GroupSpellIndicators` | Clamp to valid sublevel range before creating textures. |
| Aura selection | `spellIndicators.specs[spec][spellId]` | `Config_Indicators` | Runtime matching must be spellId/hash based. |
| Only mine | `onlyOwn` | `AuraCache` matching | Use aura source/unit token from declassified aura data only. |
| Placed display | placed type, anchor, size, x/y, bar width, growth | `GroupSpellIndicators` | Icon/bar rendering from compiled item specs. |
| Frame effects | frame type, color, priority, alpha, thickness | `GroupVisuals` or dedicated `GroupIndicatorEffects` | One priority resolver per frame, not per indicator render pass. |
| Missing state | missing toggle | `GroupSpellIndicators` | Evaluate against compiled aura snapshot, not live tooltip/name scans. |
| Cooldown display | cooldown swipe/text/size | `GroupSpellIndicators` | Use cooldown frame pool; no per-frame OnUpdate text loop. |

### Corner Indicators

| UX | DB keys/tables | Backend owner | Implementation rule |
| --- | --- | --- | --- |
| Master enable | `ciEnabled` | `Config_Indicators`, `GroupCornerIndicators` | Compile once into slot specs. |
| Size/alpha | `ciSize`, `ciAlpha` | `GroupCornerIndicators` | Clamp layer/sublevel and alpha. |
| Slot assignment | `ciSlotTL`, `ciSlotTR`, `ciSlotBL`, `ciSlotBR`, center slot if present | `Config_Indicators` | Slot config decides category; renderer only draws compiled result. |
| Custom spell editor | custom spell IDs/mode/filter/color | `Config_Indicators`, `AuraCache` | Numeric spell IDs only for runtime matching. |
| Aggro/dispel/status categories | category keys | `GroupCornerIndicators`, `GroupVisuals` | Use central threat/dispel/status snapshot helpers. |

### Auras

| UX | DB keys/tables | Backend owner | Implementation rule |
| --- | --- | --- | --- |
| Buff lane | `auras.buff.*` | `GroupAuraLanes`, `AuraCache` | Use `C_UnitAuras.GetAuraSlots` / `GetAuraDataBySlot`. |
| Debuff lane | `auras.debuff.*` | `GroupAuraLanes`, `AuraCache` | Consume one shared snapshot per frame. |
| External/defensive lane | `auras.externals.*` | `GroupAuraLanes`, `AuraCache` | Compile filters from retained Auras3 group filtering data. |
| Lane layout | `enabled`, `anchor`, `growth`, `x`, `y`, `max`, `size`, `perRow`, `spacing`, `layer` | `GroupAuraLanes` | Pool icons; geometry refresh only when layout keys change. |
| Behind HP bar | `behindBar`, `behindBarAlpha` | `GroupAuraLanes` / UF layer target | Render on compiled layer target; no reparent churn per aura event. |
| Private auras | `privateAuras.enabled`, `max`, `size`, `anchor`, `x`, `y` | dedicated private aura lane | Use Blizzard private aura APIs only; no old bridge restore. |
| Masque | `masqueEnabled` and skin data | `GroupAuraLanes` integration | Apply on icon creation/reuse, not per aura update. |

### Preview And EditMode

| UX | DB keys | Backend owner | Implementation rule |
| --- | --- | --- | --- |
| Native Group Preview | all visible group scope keys | Menu2 preview + `GF.GetCompiledSpec` | Preview must render the same spec as live with mock units. |
| Hide Preview | preview UI state | Menu2 only | Never affect live runtime. |
| EditMode mover | `offsetX`, `offsetY`, anchor keys | `Runtime`, `Headers` | Use `GF.EM2_NudgePreview`; combat-safe live apply. |
| Scope switching/copy | `gf_party`, `gf_raid`, `gf_mythicraid` | DB + `Runtime` | Invalidate spec/cache and rebuild. |

## Current Priority Checklist

1. Confirm `MSUF_UF_Group_Config.lua` emits every key listed above into either
   a UF spec or a group-only spec.
2. Add a `docs` parity checklist row per UX section with `Done / Partial /
   Missing / Blocked`.
3. Fix any options that currently exist in Menu2 but are ignored by the new
   runtime before adding new features.
4. Run the in-game smoke matrix after each section:
   - solo party preview
   - real party
   - raid
   - mythic raid context
   - combat lockdown rebuild attempt
   - profile switch
5. After feature parity, run performance traces with Party, 20-player raid, and
   40-player raid.

## Definition Of Done Per Feature

- The Menu2 control changes the same visible behavior as 5.53.
- DB values survive `/reload`.
- Spec compile contains all DB reads.
- Hotpath code consumes only `frame.MSUFSpec`, aura snapshots, or event payload.
- The feature has no broad per-frame `OnUpdate`.
- Secure changes defer in combat.
- `luac -p` passes for touched files.
- XML/TOC references exist.
- In-game `/reload` has no Lua errors.
