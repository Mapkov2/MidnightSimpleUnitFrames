# MSUF Classic prototype

This local branch was created from Retail `main` commit `7cf4e711` and is now
synchronized with the adjacent Retail 6.0 RC5 working tree. It follows the same
multi-client packaging shape used by ElvUI: client-suffixed TOCs plus a real
`Game/Shared`, `Game/Classic`, `Game/Mainline`, `Game/Mists`, and `Game/TBC`
source boundary.

Supported bootstrap targets:

- Mists of Pandaria Classic: `50504`, suffix `_Mists.toc`
- The Burning Crusade Classic: `20506`, suffix `_TBC.toc`
- Retail remains available for comparison through `_Mainline.toc`

The core TOCs load `Game/Shared/Initialize.lua` before the regular MSUF bootstrap.
It exposes `MSUF.Client`, `MSUF.Mists`, `MSUF.TBC`, and `MSUF.Classic`, and only
fills a small set of missing legacy API aliases. Native client APIs always win.
The Classic TOCs additionally load `Game/Classic/BlizzardFrames.lua`, which owns
Classic-only Blizzard frame suppression such as the target-anchored
`ComboFrame` while MSUF's replacement class resource is active.

Auras use a client-selected backend. Mainline's loader keeps the native 12.1
`Blizzard_AuraContainer` runtime under `Game/Mainline/Auras`. The Mists and
TBC loaders select `Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua`; it owns
`UNIT_AURA`, uses the Classic `C_UnitAuras`/`AuraUtil` scan contract, and
reuses MSUF's pooled aura buttons. Its lifecycle binds the factory's
`MSUFUnitKey`/`unitKey` to the legacy backend unit field and resolves tooltip
aura indices when the AuraInstanceID tooltip APIs do not exist.

The Classic backend implements the complete MSUF aura presentation contract:
buff/debuff lanes, custom containers, target DoTs, player defensives, portrait
auras, group spell/corner indicators, cooldowns, stacks, sorting, frame/icon
effects, dispel borders/overlays/symbols, tooltips, previews, blacklist and
duration rules. Retail-only native filter tokens are compiled once into a
Classic-safe plan. Mists/TBC scan only with tokens their AuraUtil accepts;
`IMPORTANT`, `DISPELLABLE`, `BOSS`, `STEALABLE`, `!PLAYER`, and related
requirements use equivalent AuraData/C_Spell predicates. No polling is added.

Class resources have separate providers in every client folder. Mists maps
the era-specific resources, including target-owned combo points, Shadow Orbs,
Chi, Arcane Charge aura 36032, Demonic Fury, Burning Embers, and signed
Eclipse power. TBC deliberately exposes only the era-valid target-owned
Rogue/Druid combo points. Retail-only class-resource and empower-cast modules
are loaded only from `Game/Mainline`.

Heal prediction, damage absorbs, and heal absorbs intentionally use Blizzard's
native APIs and events on both supported Classic clients. The current Blizzard
branches use `UnitGetIncomingHeals`, `UnitGetTotalAbsorbs`, and
`UnitGetTotalHealAbsorbs` in their own unitframes and publish
`UNIT_HEAL_PREDICTION`, `UNIT_ABSORB_AMOUNT_CHANGED`, and
`UNIT_HEAL_ABSORB_AMOUNT_CHANGED`; maintaining a second spell-by-spell absorb
calculator would be less correct and more expensive.

## Client boundaries

- Mainline loads one direct unit-frame manifest with the same Lua module count
  and order as the source Retail checkout. It never parses `Game/Classic`,
  `Game/Mists`, or `Game/TBC`.
- Mists and TBC load their own aura datasets, group indicator datasets,
  ClassPower providers, Blizzard-frame ownership, and compatibility adapters.
- Compatibility code never assigns to Blizzard `C_*` namespace tables. This is
  an enforced taint gate because doing so can later poison secure action-button
  clicks and surface as `ADDON_ACTION_FORBIDDEN` at `UseAction()`.
- Options and Assistant keep their original zero-idle LoadOnDemand architecture
  and have suffix TOCs for every supported client.

## Install for testing

Copy these three folders into the selected Classic client's
`Interface/AddOns` directory:

- `MidnightSimpleUnitFrames`
- `MidnightSimpleUnitFrames_Options`
- `MidnightSimpleUnitFrames_Assistant`

Do not rename the addon folders or the suffixed TOCs. WoW selects the matching
TOC for the running client. Enable "Load out of date AddOns" only when testing
against a newer point build than the interface values above.

## Validation boundary

`tools/test-classic-prototype.ps1` validates all nine TOCs, recursive XML load
graphs, Lua 5.1 syntax, client bootstrap, Blizzard resource ownership,
ClassPower providers, legacy cast/channel tuples, native prediction events,
Classic aura compilation/rendering/filter plans, group indicator datasets,
forbidden Blizzard namespace writes, and the zero-overhead Retail load graph.
When the adjacent Retail checkout is present, the parity gate compares the
current Core, Options, and Assistant Mainline load sequences and Lua blobs
against that working tree; otherwise it falls back to this repository's HEAD.
When the local UI mirror is present it also runs
`tools/audit-classic-ui-source.ps1` against both Blizzard branches.

These are source/runtime-mock gates, not a substitute for logging into every
class/spec on both game clients. Release certification still requires the live
matrix: clean install and migrated profile, combat and reload, every
class-resource owner, cast/channel/interrupt states, aura/filter/tooltip
combination, party/raid secure headers, Options, Assistant, and action-button
taint checks. A source build must not be described as live-certified until that
matrix has actually passed.

ElvUI reference inspected locally at commit
`6c164caaa3d34f5c8ca29d2948ce7d9abde828a6`: its `ElvUI_Mists.toc` and
`ElvUI_TBC.toc` select `Game/load_mists.xml` and `Game/load_tbc.xml`, which then
combine shared modules with client-only files. MSUF now uses the same
shared/classic/client-folder pattern and keeps a dedicated unit-frame manifest
for each supported client.
