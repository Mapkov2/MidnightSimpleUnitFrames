# MSUF 6.0: Party Frames as Arena Opponent Frames

Date: 2026-07-19  
Checkout: `6.0-beta-branch`  
Scope: read-only feasibility and architecture deep dive; no addon source was changed.

## Verdict

Yes. MSUF can expose a Party > Basics switch that replaces the live friendly Party block with Arena opponent frames while the player is in an Arena.

This is a medium-sized runtime feature, not a one-line `SecureGroupHeader` option. The current Party frame is driven by `SecureGroupHeaderTemplate`, and Blizzard's secure header can only enumerate `player`, `party1..4`, or `raid1..40`. Arena opponents use the independent fixed tokens `arena1..5`.

The robust design is therefore:

1. Keep Party configuration as the visual source of truth.
2. Create five fixed protected Arena unit buttons, one per `arena1..5`.
3. Use the Party anchor, size, spacing, growth, textures, colors, fonts, texts, and compatible indicators.
4. Retire/hide the friendly MSUF Party header while the replacement mode is active in an Arena.
5. Restore the normal Party header immediately after leaving the Arena.
6. Hide Blizzard's `CompactArenaFrame` while MSUF owns the Arena opponent frames.

Recommended default: `false`.

Recommended label: **Replace Party Frames with Arena opponents**.

Recommended tooltip: **In Arenas, show enemy Arena units in the Party Frame position and style instead of your friendly Party Frames. This hides your normal Party Frames while active.**

That wording is important: a healer enabling literal replacement would otherwise unexpectedly lose friendly Party frames.

## Source-grounded findings

### Current MSUF architecture

- Party defaults live in `GroupFrames/MSUF_GroupFrames_DB.lua:162-522`. Party is a five-unit layout with independent enable, position, geometry, visual, aura, range, and click-cast settings.
- The Party Basics UI already owns `Use MSUF group frames`, `Show player`, `Show while solo`, and click-cast behavior in `Shell/Menu2/Pages/MSUF_Menu2_GroupLayout.lua:49-149`.
- Live Party/Raid creation is owned by `UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua`. The header is explicitly created with `SecureGroupHeaderTemplate` at lines 1181-1188.
- MSUF configures that header with `showPlayer`, `showSolo`, `showParty`, and `showRaid` at lines 934-950. There is no Arena attribute.
- Runtime visibility currently considers only Party, Raid/Mythic Raid, and Priority frames in `UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua:145-320`.
- The adapter is already generic enough to skin a valid unit token through the shared unit-frame engine: it reads the protected button's `unit` attribute and compiles/applies a Group spec in `UnitFrames/Engine/Group/MSUF_UF_Group_Adapter.lua:479-519`.
- `GF.GetConfigDBKey()` deliberately falls back to `gf_party` for non-Raid kinds in `GroupFrames/MSUF_GroupFrames_DB.lua:1368-1385`. That makes Party style inheritance possible, although a dedicated Arena runtime flag is still preferable to pretending Arena enemies are ordinary Party members.

### Blizzard 12.1 evidence

The local PTR mirror is `12.1.0.68675`, commit `3ea5134b14c626b09de1dcb1b0acf8f665460a53` from 2026-07-14.

- Blizzard's `SecureGroupHeaders.lua:261-315` constructs only Raid, Party, or Solo tokens. Party becomes `partyN`/`player`; Raid becomes `raidN`. `nameList` filters roster members by name and cannot introduce `arenaN` units.
- Blizzard's own current Arena implementation does not use a secure group header. `CompactArenaFrame.lua:53-59` maps five fixed indices to `arenaN`/`arenapetN`.
- It registers `ARENA_OPPONENT_UPDATE`, `ARENA_PREP_OPPONENT_SPECIALIZATIONS`, and `PVP_MATCH_STATE_CHANGED` at `CompactArenaFrame.lua:82-93`.
- It binds each member frame directly to `arena1..5` at `CompactArenaFrame.lua:239-274`.
- It detects Arena context with `C_PvP.IsMatchConsideredArena()` plus active/complete match state at `CompactArenaFrame.lua:45-51`.
- It determines the visible Arena size from opponent specs before the match, then live opponents once the match begins, at `CompactArenaFrame.lua:27-43`.
- Blizzard's Arena container inherits the Party layout template (`CompactPartyFrameTemplate`) at `CompactArenaFrame.xml:169-185`. This validates the product concept: Arena units can reuse Party-style layout, but they still require a distinct unit-binding/runtime owner.

### External implementation cross-check

The local UUF/oUF reference reaches the same conclusion:

- `oUF/units.lua:176-181` adds Arena-specific events for `arenaN` units.
- `oUF/units.lua:88-161` has a dedicated pre-match path that supplies fake health/power presentation from opponent specialization data, hides irrelevant elements during preparation, and switches back when the real Arena unit appears.
- `oUF/blizzard.lua:153-168` separately suppresses Blizzard's modern Arena container and its children.

This confirms that pre-match presentation and Blizzard ownership are real feature requirements, not optional polish around an otherwise complete Party-header toggle.

## Recommended behavior contract

When all conditions are true:

- `gf_party.enabled == true`
- `gf_party.arenaReplacementEnabled == true`
- `C_PvP.IsMatchConsideredArena() == true`
- the match is active/complete, or Arena opponent specializations are available

MSUF should:

- retire the normal secure Party header;
- show up to five Arena opponent slots using Party geometry and styling;
- occupy the same Party anchor/mover position;
- suppress Blizzard's `CompactArenaFrame`;
- use left-click target and right-click focus as the safe Arena defaults;
- restore all normal Party behavior after leaving the Arena.

When the option is off, the Arena module should create no buttons, register no Arena-specific events, and leave Blizzard Arena UI untouched.

## What can inherit Party settings safely

These domains can be reused directly:

- frame width, height, scale, spacing, growth, and position;
- health/power bar textures and backgrounds;
- class/custom/gradient health colors;
- fonts, name text, health text, and power text;
- opacity, border, target highlight, focus highlight, and mouseover highlight;
- raid target marker;
- compatible Buff/Debuff rendering after Arena-specific filtering is verified.

## What must not be inherited blindly

The following Party behaviors are friendly-roster concepts and need to be disabled or patched for Arena enemy frames:

- heal prediction and absorbs intended for assistable units;
- dispel overlays and healer-oriented corner/spell indicators;
- external-defensive tracking;
- Party range/offline fade (`UnitInRange` is not the correct enemy-Arena range source);
- ready check, incoming summon, incoming resurrection, leader/assist, phase, and Raid-group number;
- `UnitGroupRolesAssigned()` as the role source;
- friendly Party click-casting/Clique registration.

Role can instead be cached from `GetArenaOpponentSpec(index)` and `GetSpecializationInfoByID()` during Arena preparation. Raid marker, dead status, class color, target/focus state, health/power, and ordinary enemy Aura information remain useful.

## Pre-match behavior

A polished implementation should show Party-styled placeholder bars before gates open:

- number of slots from `GetNumArenaOpponentSpecs()`;
- class color, specialization name/icon, and inferred role from `GetArenaOpponentSpec()`;
- fake full health/power presentation;
- no Auras, cast state, prediction, or other live-unit-only regions.

At the first `ARENA_OPPONENT_UPDATE`, each placeholder switches to its already assigned fixed `arenaN` unit and performs one full identity/state refresh.

An MVP could omit the placeholders and rely on secure unit existence watching, but the frames would appear only when real `arenaN` units become available. That would feel incomplete compared with Blizzard and established Arena implementations.

## Secure/combat design

The safe shape is five fixed `SecureUnitButtonTemplate, PingableUnitFrameTemplate` buttons. Their `unit` attributes are assigned once out of combat and never retargeted.

- Create/configure protected buttons only out of combat.
- Use `RegisterUnitWatch` or an equivalent secure existence mechanism for live `arenaN` visibility.
- Keep unit attributes fixed through the match.
- Route `ARENA_OPPONENT_UPDATE` only into visual/identity refreshes; do not perform protected layout mutations from it in combat.
- Defer menu changes, layout changes, Party/Arena ownership swaps, and Blizzard frame reparenting through the existing `GF.DeferGroupRuntime()`/`PLAYER_REGEN_ENABLED` path.
- Reuse MSUF's existing compiled unit-frame engine instead of adding an `OnUpdate` loop.

Special edge to validate in game: `/reload` during an already engaged Arena match. The creation path must not assume every login occurs outside combat lockdown.

## Runtime and performance shape

The feature can remain event-driven with zero recurring polling:

- option off: zero Arena buttons and zero Arena event subscriptions;
- option on, outside Arena: at most the existing group runtime plus conditional zone/match detection; no `OnUpdate`;
- inside Arena: five existing unit-frame event routes plus three Arena lifecycle events;
- `ARENA_OPPONENT_UPDATE`: refresh only the matching `arenaN` frame;
- Party menu changes: reuse the current coalesced Group apply path and refresh the Arena views as Party-style dependents;
- leaving Arena: detach/hide the five Arena frames and restore Party/Blizzard ownership once.

Avoid treating Arena as a new fourth configurable Group scope. It should be a Party-style dependent mode so there is no duplicate Arena configuration tree and no extra cold-path/menu complexity.

## Proposed code boundary

1. `GroupFrames/MSUF_GroupFrames_DB.lua`
   - add `arenaReplacementEnabled = false` to Party defaults;
   - ensure reset/import/profile paths preserve the boolean.

2. `Shell/Menu2/Pages/MSUF_Menu2_GroupLayout.lua`
   - add the Party-only switch under Frame Basics;
   - add explicit warning/help text that friendly Party frames are replaced;
   - bind to a `rebuild` request and register assistant/control metadata.

3. New `UnitFrames/Engine/Group/MSUF_UF_Group_Arena.lua`
   - own Arena context detection, fixed buttons, pre-match state, same-anchor layout, Arena lifecycle events, and retirement;
   - mark Arena views so friendly-only Party runtime can exclude them;
   - expose small `IsArenaReplacementConfigured`, `WantArenaReplacement`, `SetupArenaFrames`, `RetireArenaFrames`, and `RefreshArenaOpponent` entry points.

4. `UnitFrames/Embeds/MSUF_UFCore/MSUF_UFCore_Group.xml`
   - load the Arena owner after Adapter and before Runtime.

5. `UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua`
   - make Party and Arena replacement mutually exclusive in the literal replacement mode;
   - conditionally register Arena lifecycle events;
   - refresh exact Arena units without broad Group scans;
   - include Arena retirement in the disabled path.

6. `UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua`
   - apply a frame-specific Arena capability patch to the inherited Party spec;
   - use cached opponent specialization role rather than Party assignment role.

7. `UnitFrames/Engine/Group/MSUF_UF_Group_Adapter.lua`
   - install Arena click semantics and keep hostile Arena buttons out of friendly click-cast registration unless a future explicit option enables it.

8. `UnitFrames/Engine/Group/MSUF_UF_Group_Blizzard.lua`
   - manage `CompactArenaFrame` independently of Party/Raid ownership;
   - hook lazy Blizzard Arena-frame creation;
   - restore its events/visibility correctly when MSUF Arena replacement is disabled;
   - do not hide deprecated Arena/flag-carrier frames globally, because those still serve Battleground use cases.

9. Locales and search/assistant catalog
   - add the new label, tooltip, search route, and setting key across supported locales.

## Required validation

### Automated

- option-off inertness: no Arena event registration/button allocation;
- five fixed tokens exactly `arena1..5`;
- no protected mutation when combat lockdown is true;
- Party rebuild also refreshes active Arena views;
- Party header retires only in a real considered-Arena context;
- leaving Arena restores Party header and Blizzard ownership;
- Blizzard `CompactArenaFrame` lazy generation cannot create a duplicate;
- Arena frames are excluded from range/offline fade, prediction, ready/summon/resurrection, and friendly click casts;
- 2v2, 3v3, 5-slot fallback, Solo Shuffle, skirmish, rated Arena, and non-Arena Battleground context mocks;
- profile export/import/reset and Menu2 control-schema coverage.

### In game

- enter/leave Arena normally;
- gates/preparation presentation;
- combat start and opponent reveal/stealth transitions;
- opponent death/disconnect/reconnect;
- target/focus clicks and key-modified clicks;
- class colors and secret values in Midnight restricted combat;
- Edit Mode/menu preview before Arena and during preparation;
- enable/disable option in and out of combat;
- `/reload` during preparation and during an engaged match;
- verify Blizzard Arena UI is restored when MSUF is disabled or the option is turned off.

## Product boundary

This feature creates Party-styled Arena opponent unit frames. It does not automatically create a full Gladius/sArena replacement. These would remain separate follow-up features:

- diminishing-return trackers;
- PvP trinket/CC-removal cooldowns;
- Arena-specific castbars;
- enemy cooldown tracking;
- pet frames;
- separate Arena-only layout/style configuration.

## Recommendation

Implement the literal switch exactly as requested, but label it unambiguously and keep it off by default. Build the polished pre-match path in the first release rather than shipping live-only bars: the local Blizzard and oUF sources both demonstrate that Arena frames need a preparation state to avoid appearing broken before the gates open.

Architecturally, reuse Party style, not the Party `SecureGroupHeader`. Five fixed protected Arena buttons plus an Arena-specific event/capability layer is the narrowest correct implementation.
