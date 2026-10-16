# MSUF multi-client codebase

This repository is the only source of the MSUF addon for every supported
client: Retail Midnight, WoW Forever and the Classic clients (Classic Era,
TBC Classic, Mists Classic). `main` is its only branch. It is an independent
codebase: no file mirrors, or is compared with, another repository, and the
load graph of every client is pinned by `tools/load-graph.lock` (see "Load
graph lock"). `VERSION` identifies this prerelease as `7.0-alpha1`; the shared release
channel resolver selects alpha, and release tags keep the
`classic-v<version>` format. How the
codebase got here (the Retail mirror era, the 2026-10-13 cutover and the 7.0
split) is recorded in `docs/HISTORY.md`; nothing there is an instruction.

In file and test names, "Retail" means the Midnight (Mainline) client or code
that was first written for it. It does not name a second repository.

The 6.5 line combines the Texture Layer on every client (Text background,
Highlight, and an MSUF textures button for the 50 original assets) with the
Midnight feature set. It follows the same
multi-client packaging shape used by ElvUI: client-suffixed TOCs plus a real
`Game/Shared`, `Game/Classic`, `Game/Vanilla`, `Game/TBC`, `Game/Mists`, and
`Game/Forever` source boundary. There is no `Game/Mainline` folder: the Mainline
build loads the shared tree plus `Game/Shared` and `Game/Forever`, and never
`Game/Classic`, `Game/Vanilla`, `Game/TBC`, or `Game/Mists`.
`MidnightSimpleUnitFrames_Mainline.toc` names its `Game\Forever\...` (the alias
catalog partitions and `Game\Forever\ClassPower.lua`) and `Game\Shared\...`
paths directly; `MSUF_UFCore_Elements.xml` adds the remaining `Game/Forever`
files and the shared unit-frame modules, and `tools/load-graph.lock` lists the
resolved set. Every `Game/Forever` file returns at once on a client that is not
WoW Forever, and the shared unit-frame modules return at once where their
`MSUF.Client` capability is false, so Midnight behaviour is unchanged.

`tools/classic-client-matrix.tsv` is the authoritative list of supported
clients: TOC suffixes, interface numbers, `X-MSUF-Client` tokens, project
globals, game types, Blizzard UI source mirror branches and CurseForge game
version names. The gate, the UI source audit, the release scripts and the
CurseForge workflows all read it, and it wins wherever this summary disagrees:

- Classic Era: `11509`, suffix `_Vanilla.toc`
- Mists of Pandaria Classic: `50504`, suffix `_Mists.toc`
- The Burning Crusade Classic: `20506`, suffix `_TBC.toc`
- Retail Midnight ships through `_Mainline.toc`

Every core TOC loads `Game/Shared/Initialize.lua` before `Kernel/MSUF_Bootstrap.lua`.
It places the client by its project ID and its `X-MSUF-Client` TOC tag and
builds `MSUF.Client`: the flavor flags, `SupportsEvent`, `SupportsUnit`,
`SupportsGroupKind`, and a one-line login diagnostic for a client it cannot
fully place, and it builds no API aliases. `MSUF.Client` is the single client
surface: the short `MSUF.Retail`, `MSUF.Vanilla`, `MSUF.Era`, `MSUF.Mists`,
`MSUF.TBC`, `MSUF.Classic` and `MSUF.Forever` shortcuts and the
`MSUF.Compat.Client` bridge were removed on 2026-09-19 because no reader in
either shipped addon used them (`Game/Shared/Initialize.lua:512-515`); do not
reintroduce them. `tools/tests/classic_client_bootstrap_smoke.lua:137` fails if
the bridge comes back. New code branches on `MSUF.Client.Is*` or, better, on a
named capability. The Classic TOCs load `Game/Classic/Initialize.lua` after it and
before the bootstrap. That file builds the local adapters `MSUF.Compat.AddOns`,
`MSUF.Compat.Spell`, and `MSUF.Compat.SpellBook`: a native `C_*` function wins,
a legacy global fills the gap, and no Blizzard `C_*` table is ever written.
The Classic TOCs additionally load `Game/Classic/BlizzardFrames.lua`, which owns
Classic-only Blizzard frame suppression such as the target-anchored
`ComboFrame` while MSUF's replacement class resource is active.

Auras use a client-selected backend. Mainline loads the Retail Auras3 runtime
unchanged, including its native 12.1 `Blizzard_AuraContainer` path. The
Vanilla, TBC, and Mists manifests (`Game/<Flavor>/Auras.xml`) load
`Game/Classic/Auras/MSUF_Auras3_Compile.lua` immediately before the unit-frame
aura backend, six files in this order: `MSUF_Auras3_Buttons.lua` (button pool
and per-aura visuals), `_Filters` (filter-token membership, ownership and lane
filters), `_FrameVisuals` (frame-level dispel border, overlay, stripe and
symbols), `_Lanes` (lane state, full scans, deltas and rendering),
`_UnitFrames` (the Auras element: `UNIT_AURA` and identity dispatch, enable and
disable, event lists) and `_Requests` (the refresh and apply service and its
combat deferral). `_Preview` follows them (the menu dispel overlay and symbol
previews). They share internals only through `A3._ClassicCompile` and
`A3._ClassicBackend`. The compile file owns lane config compilation: the one
lane schema that unit, group and custom-container lanes all fill, lane specs,
filters, blacklist hashes, dispel visuals and sort comparators. The backend
owns `UNIT_AURA`, uses the Classic `C_UnitAuras`/`AuraUtil` scan contract, and
reuses MSUF's pooled aura buttons. Its lifecycle binds the factory's
`MSUFUnitKey`/`unitKey` to the legacy backend unit field and resolves tooltip
aura indices when the AuraInstanceID tooltip APIs do not exist.

Vanilla, TBC and Mists ship no SpellName alias catalog. Their aura payloads
are readable, so every lane that carries `includeSpellIDs` also carries
`includeSpellNames` (`ClassicFeatures.NameHash`, resolved through the
synchronous legacy `GetSpellInfo`), and the backend matches the aura name
whenever the ID misses (`ShouldShowAura`, `Features.MatchAura`,
`Features.IsAutoExcluded`). That covers spell ranks on Vanilla/TBC and
cast-versus-aura ID drift on Mists on whatever build the client runs, the way
WeakAuras matches auras by name. `A3.AddAuraSpellIDAndAliases` adds only the
configured ID plus explicit `A3.AuraSpellIDAliases` entries, which are
reserved for pairs whose names differ. The generated per-flavor catalogs these
clients shipped earlier could only add IDs sharing the exact same name, so the
name match already covered everything they did, while they cost 85-280 KB of
startup parsing per client and had to be regenerated for every client build.
`tools/tests/classic_aura_rank_name_match_smoke.lua` pins the manifests and
the name match on the real feature compiler.

Mainline and WoW Forever keep their catalogs, because the native
AuraContainer path cannot read aura names at runtime. The core Mainline TOC
places them between `MSUF_UFCore_Elements.xml` and `MSUF_UFCore_Auras.xml`
(the shared resolver `Auras3/MSUF_Auras3_AuraAliases.lua` loads there). Native
`AllowLoadTextLocale` TOC conditions exclude inactive partitions before Lua
parsing. The owner verified on Retail 12.x (2026-10-14) that only the first
bracket condition on a TOC line is honored. `tools/load-graph.lua` rejects
stacked conditions. The Retail common catalog keeps its camelot exclusion;
its localized partitions guard Forever in Lua before touching the catalog.
Forever therefore parses the client-language Retail partition as well as its
own data, while retaining only its own catalog. The Forever files keep their
`MSUF.Client.IsForever` guard for every other Mainline game type.
Regenerate the Forever catalog with
`.github/scripts/generate_classic_aura_alias_catalog.py` from wago.tools
`SpellName` CSV exports, one `<locale>/SpellName.csv` per locale.
Alias `enGB` shares `enUS` and `ptPT` shares `ptBR`.
Core TOCs load the resolved client menu pack (`ptPT` uses `enUS`; `enGB` also gets `enUS`). Saved menu
choices remain independent: finalization requests the LoadOnDemand companion
`MidnightSimpleUnitFrames_Locales` when the selected loader is absent, before
sealing registration. It reuses the twelve core pack files by relative path.
A missing/disabled companion or combat falls back to the client pack/English
with one chat hint and leaves the saved choice untouched. Classic directive
support is unproven in game; ignoring it safely restores all-pack loading.
The release packager includes all three addon folders and twelve suffixed TOCs.
Gates and packages inventory the union of all locale and game-type branches;
boot simulations select their actual client locale and, for WoW Forever, the
camelot game type. `tools/tests/startup_locale_manifest_smoke.lua` checks all
five clients across fourteen locale cases against the all-branch catalogs and
compiled aliases. The native locale condition is used in Blizzard's
`upstream/live` and `upstream/forever` `Blizzard_FullscreenBrowser.toc`; the
trailing form is also used by [BigWigs Classic](https://github.com/BigWigsMods/BigWigs_Classic/blob/master/BigWigs_Classic_Vanilla.toc).

`Game/Shared/Initialize.lua` also exposes `MSUF.Client.SupportsUnit(unit)`:
Classic Era has no focus, boss or arena units and TBC has no boss units. The
unit config compiler compiles those units disabled on Classic clients (a hunk of
`UnitFrames/Engine/MSUF_UF_Config.lua` gated on `MSUF.Client.Family`), the Unit
page (`Pages/MSUF_Menu2_Unit.lua`, which every client loads) drops them from its unit
pills and copy targets there, and the Classic-era interrupt-ready tables in
`Castbars/MSUF_InterruptReady.lua` only name spells that exist on each client.
A client build without `C_Spell.GetSpellCooldownDuration` reads the plain
`C_Spell.GetSpellCooldown` table (what Blizzard's Classic action buttons call)
and ignores the global cooldown, like the Duration API's ignoreGCD argument.
Where a unit kind is unsupported, a castbar settings refresh keeps the profile's
stored backend for that kind instead of rewriting it to hidden, so a profile made
there still shows those castbars on a client that has the units: arena on Classic
Era and WoW Forever, boss on Classic Era and TBC. Both guards read
`MSUF.Client.SupportsUnit` once at load, and
`tools/tests/arena_castbar_backend_keep_smoke.lua` pins both pools on every client. Blizzard's LoadOnDemand `Blizzard_ArenaUI` frames are suppressed
by a flavor pass in `Game/Classic/BlizzardFrames.lua`, which the Kernel runs
through `MSUF.BlizzardFrameSuppressionPasses`. When MSUF owns arena frames, the
pass hides the `ArenaEnemyFrames`/`ArenaPrepFrames` containers and exactly the
MSUF arena slots (`ArenaEnemyFrame1..N`/`ArenaPrepFrame1..N`, N =
`MSUF_MAX_ARENA_FRAMES`). It stands down when there are no slots (Vanilla), or
when `MAX_ARENA_ENEMIES`, read through tonumber because it is nil until
Blizzard_ArenaUI loads, is greater than the slot count. It re-runs once on that
addon's ADDON_LOADED. `tools/tests/classic_arena_legacy_hider_smoke.lua` pins
this.

Leaving MSUF Edit Mode (normal exit, Cancel All, or the combat exit flushed on
`PLAYER_REGEN_ENABLED`) clears the arena preview flags (`MSUF_ArenaTestMode`,
`MSUF2_ArenaUnitframePreviewActive`). It then runs the arena preview owner's
off-sync and the arena prep display sync, so arena1-N, their castbar previews
and aura previews return to the fresh-load state: hidden unless an opponent
exists or arena preparation is active.
`tools/tests/arena_editmode_exit_restore_smoke.lua` pins this for Mainline, TBC
and Mists.

The Classic backend implements the complete MSUF aura presentation contract:
buff/debuff lanes, custom containers, target DoTs, player defensives, portrait
auras, group spell/corner indicators, cooldowns, stacks, sorting, frame/icon
effects, dispel borders/overlays/symbols, tooltips, previews, blacklist and
duration rules.

Classic aura filters are Only mine and Hide permanent. The Classic compile
keeps every other Retail filter setting off and the Classic Aura page builds no
controls for them; the settings stay untouched in SavedVariables so a profile
can move between clients without losing them. The one carry-over is a
Non-player debuff flag imported from a Retail profile: it still applies to that
unit lane, and turning Only mine on clears it. Every client loads the Retail
aura page (`Shell/Menu2/Pages/MSUF_Menu2_Auras.lua` with its `_Group` and
`_Preview` siblings); its Classic differences (these two filters, a Non-player
group token read as All, no lane Full-Frame Effect, no native stealable-marker
note, the atlas dispel border on a rectangular preview icon, the Auras-only
apply of a group blacklist change, the group blacklist Preset opening on the
lane's default set) key on the page's `M.CLASSIC_AURA_FILTERS_REDUCED`, and
`tools/tests/classic_aura_page_client_gates_smoke.lua` pins both sides. Raw
Retail filter tokens are compiled once into a Classic-safe plan.
Vanilla/Mists/TBC scan only with tokens
their AuraUtil accepts; `IMPORTANT`, `DISPELLABLE`, `BOSS`, `STEALABLE`,
`!PLAYER`, and related requirements use equivalent AuraData/C_Spell
predicates. No polling is added. Debuffs the player can dispel (the dispel
border, overlay and symbols, and the "Dispellable by Group" filter) are
scanned with `MSUF.Client.DispellableDebuffFilter`: Classic Era uses
`HARMFUL|RAID`, the filter Blizzard's Era party frames scan for dispellable
debuffs, because it does not honour `RAID_PLAYER_DISPELLABLE`; TBC and Mists
use `HARMFUL|RAID_PLAYER_DISPELLABLE`.

Every client runs the optional Extra Health surface through the independent UF `PlayerHP` element
(`UnitFrames/Engine/Elements/MSUF_UF_PlayerHP.lua`). Its state, attachment,
enable/disable, health subscriptions, and combat-deferred apply belong to UF;
ClassPower forwards cold settings, font, media, and anchor refreshes. The
element registers a `resource` scope recipe, leaving ordinary single/group
element orders unchanged. Cold route builders reuse temporary maps while
retained shared and frame-specific plans own immutable snapshots; nested
compilation acquires another scratch entry. This keeps roster CPU/allocation
costs below the reviewed baseline without changing event dispatch closures.
The
`ClassPower/MSUF_CP_PlayerHP.xml` load unit retains the original injection and
font/media readiness boundary: the native visual/text provider loads first,
then the UF owner, before the controller. ResourceVisibility still owns its
configured parent, scale, alpha gates and outline sibling. Extra Health uses
only its own option; disabling, hiding, or detaching the Player unit button
does not change that option or its independent resource host. The real native
health/secret sinks and Class Resources shape/text getters are shared with
previews. `player_health_element_*` smokes cover actual ownership, a frozen
old/new visual oracle, named dependencies, and exact dispatcher costs.

Class resources have separate providers per client. Every client runs the
shared ClassPower core (`ClassPower/MSUF_CP_Constants.lua`,
`MSUF_CP_Modes.lua`, `MSUF_CP_Core.lua` and `MSUF_CP_Controller.lua`). Mode
traits live in the constants' descriptor registry, renderers share pip painters,
and split builders read the controller's CP state directly. The Power element
loads first and establishes `MSUF.ClassPowerOwnership`, then subscribes itself
to its change notifications. ClassPower publishes state before notifying it;
Aug entry orders Power before the sensor and exit orders the sensor before Power.
Its Classic behaviour sits in small hunks gated on `MSUF.Client.IsClassic`, read
once per file, so Mainline never enters them. The Classic TOCs add `Game/<Flavor>/ClassPower.lua` and
`Game/Classic/ClassPower/MSUF_CP_ClassicRouting.lua`, which adapts the flavor
provider's `Resolve(env)` contract to the provider seam the controller reads at
load; WoW Forever's provider fills that seam directly. Mists maps
the era-specific resources, including target-owned combo points, Shadow Orbs,
Chi, Arcane Charge aura 36032, Demonic Fury, Burning Embers, and signed
Eclipse power. TBC deliberately exposes only the era-valid target-owned
Rogue/Druid combo points. The Retail-only modules
`ClassPower/MSUF_CP_BalanceDruid.lua`, `ClassPower/MSUF_CP_Ironfur.lua`,
`ClassPower/MSUF_CP_EbonMight.lua`, `ClassPower/MSUF_CP_NativeAuras.lua`, and
`Castbars/MSUF_CastbarEmpower.lua` are loaded only by
`MidnightSimpleUnitFrames_Mainline.toc`.

Heal prediction, damage absorbs, and heal absorbs intentionally use Blizzard's
native APIs and events on all supported Classic clients. The current Blizzard
branches use `UnitGetIncomingHeals`, `UnitGetTotalAbsorbs`, and
`UnitGetTotalHealAbsorbs` in their own unitframes and publish
`UNIT_HEAL_PREDICTION`, `UNIT_ABSORB_AMOUNT_CHANGED`, and
`UNIT_HEAL_ABSORB_AMOUNT_CHANGED`; maintaining a second spell-by-spell absorb
calculator would be less correct and more expensive.

## Client boundaries

- Every client's load graph is pinned by `tools/load-graph.lock`, and
  `tools/classic-addon-tombstones.txt` names the files this tree retired. The
  files that Classic clients also use, or that only the Forever and Arena builds
  need, include `Game/Shared/Initialize.lua`,
  `Game/Shared/UnitFrames/MSUF_UF_PetHappiness.lua` (hunter pet happiness,
  which applies only when `MSUF.Client.SupportsPetHappiness` is true, so on
  WoW Forever), `Game/Shared/UnitFrames/MSUF_UF_ThreatText.lua` (the threat
  percentage text, only when `MSUF.Client.SupportsThreatText` is true, so on
  WoW Forever), `Game/Forever/UnitFrames/MSUF_UF_CharacterNames.lua` (the
  first name or surname option, only when `MSUF.Client.HasCharacterSurnames`
  is true), `State/MSUF_AuraDefaults.lua`, the three
  Defaults shells (`State/Defaults/MSUF_Defaults_Shell.lua`,
  `State/Defaults/MSUF_Defaults_Bars.lua`,
  `State/Defaults/MSUF_Defaults_Units.lua`),
  `Auras3/MSUF_Auras3_IconShape.lua`, `Auras3/MSUF_Auras3_MockAuraPainter.lua` (the
  shared mock aura painter of the preview surfaces), the Options files
  `Shell/Menu2/MSUF_Menu2_ColorPicker.lua` and
  `Shell/Menu2/MSUF_Menu2_Theme_Forever.lua` (Classic Glass and Midnight menu
  presets, selectable on every client; only Forever defaults to Classic Glass), the WoW Forever aura
  data (`Game/Forever/Auras/MSUF_Auras3_ForeverData.lua` and the
  `Game/Forever/Auras/AliasData` files, which return at once on every other
  client), the four Arena modules
  (`Castbars/MSUF_ArenaCastbars.lua`, `Castbars/MSUF_ArenaCastbars_Preview.lua`,
  `Features/Gameplay/MSUF_Feature_ArenaMatch.lua`,
  `Features/Gameplay/MSUF_Feature_ArenaTrinkets.lua`), the boss/arena castbar
  pool and preview modules (`Castbars/MSUF_CastbarPools.lua`,
  `Castbars/MSUF_CastbarPoolPreviews.lua`) and the ClassPower controller modules
  (`ClassPower/MSUF_CP_Controller_Auras.lua`, `_Ticker.lua`, `_Events.lua`;
  the lock lists every load). Mainline and WoW Forever never parse
  `Game/Classic`, `Game/Vanilla`, `Game/Mists`, `Game/TBC` or a `*_Classic.lua`
  file; the load-graph check fails the gate otherwise. A module that Classic clients and Mainline both
  need therefore lives in `Game/Shared`, as the pet happiness module does:
  Vanilla and TBC load it from their own manifests, Mainline from
  `MSUF_UFCore_Elements.xml`, and
  `tools/classic-flavor-load-exclusions.tsv` keeps it out of Mists.
- Vanilla, Mists, and TBC load their own aura datasets, group indicator datasets,
  ClassPower providers, Blizzard-frame ownership, and compatibility adapters.
- Compatibility code never assigns to Blizzard `C_*` namespace tables. This is
  an enforced taint gate because doing so can later poison secure action-button
  clicks and surface as `ADDON_ACTION_FORBIDDEN` at `UseAction()`.
- Options keeps its original zero-idle LoadOnDemand architecture and has a
  suffixed TOC for every supported client. Core `State/MSUF_History.lua` owns
  the shared diff cursor, sessions and undo/redo; `State/MSUF_ApplyService.lua`
  owns coalesced runtime execution. Edit Mode enters and edits without loading
  Options. The companion attaches explicit UI bridges to the existing services,
  retaining the same stacks when opened during an edit session. Internal apply
  requests use named domain flags and typed builders; historical public request
  signatures retain their separate compatibility seam. The in-game Assistant
  (`MidnightSimpleUnitFrames_Assistant`) was retired in 6.5: no client ships it,
  and `State/MSUF_RetiredData.lua` removes its saved history once per account.

## Client model: family and game mode

`Game/Shared/Initialize.lua` describes a client on three levels, and code keys
on these facts instead of repeating project checks:

- `Client.Family` is the code family, `Mainline` or `Classic` (`Unknown` when
  detection cannot place the client). It decides which build runs: Mainline
  loads the shared tree plus `Game/Shared` and `Game/Forever`, Classic adds
  `Game/Classic` and its flavor folder.
- `Client.Flavor` is the client inside the family: `Mainline`, `Vanilla`, `TBC`
  or `Mists`, placed by project ID and the `X-MSUF-Client` tag.
- `Client.GameMode` and `Client.GameModeName` come from
  `C_GameRules.GetActiveGameMode()` and its `Enum.GameMode` key, read once at
  load; Blizzard's own code reads the mode at file scope. `IsStandardGameMode`
  is true for Standard and for clients without the API, and
  `GameModeRecognized` covers Standard, Plunderstorm and WoWHack.

Game modes are not TOC game types: Classic clients run the Standard mode while
their TOCs use `vanilla`, `tbc` or `mists`, and Plunderstorm ships its own TOC
suffix. A Mainline client in a game mode MSUF does not recognize keeps full
Mainline behaviour and prints one login line naming the mode.

WoW Forever is such a split, not a game mode. It runs Blizzard's Mainline code
on the 12.1.5 engine under its own TOC game type (`camelot` in the 1.60.1
beta), reads the `_Mainline.toc` files and reports the Standard game mode.
`Client.IsForever` therefore comes from
`GameEvent.RegisterCamelotEvents`, which the LoadFirst Blizzard_Game addon
defines only in its camelot-gated file, before any addon loads. On Forever,
`Family` and `Flavor` stay `Mainline` and `IsRetail` stays true, whatever
project ID the client reports; a Classic `X-MSUF-Client` tag still wins. Build
1.60.1.70170 declares `WOW_PROJECT_CAMELOT` (18). With the Forever marker,
that declared project is recognized without a login warning; earlier builds
using the Mainline project remain supported. The project constant alone does
not replace the marker. Forever
has no arena UI, so arena units are unsupported there (0 arena slots). It has
5-player groups and raids only, so `Client.SupportsGroupKind("mythicraid")` is
false there and the Mythic Raid scope stays out of the menu. Hunter pet
happiness exists again (`C_PetInfo.GetPetHappiness` plus `UNIT_HAPPINESS`), so
`Client.SupportsPetHappiness` is true on Forever, Classic Era and TBC.
`Client.SupportsThreatText` (same three clients, owner decision 2026-09-19) offers
the threat percentage text on the target, focus and boss frames: the scaled
percentage of `UnitDetailedThreatSituation("player", unit)`, default on in the
bottom-left corner of the frame. Forever makes a boss's values secret
(`SecretWhenUnitThreatValuesRestricted`); the text then goes through
`C_StringUtil.TruncateWhenZero` and `WrapString` and is never compared.
"Color by threat" blends the text from green through yellow to light pink across
three global colors (Colors > Status Text Colors); pink rather than red, because
red digits vanish on red enemy bars. A secret value is colored by threat state
instead, because a color curve cannot evaluate it. A dark plate behind the number
("Background") keeps it readable on any bar color; it is a status bar the percentage
itself fills, so a secret zero, which prints as nothing, leaves no empty plate
either. The party and raid frames show
each member's threat on the player's target (Party on, Raid off by default; the
plate likewise), repainted together by one driver at most every half second.
Forever has nine classes and no Evoker, so `Client.HasEmpoweredCasts` is true on
Midnight only and the Empowered Casts castbar section follows it. A Mainline client
below interface 100000 without the Forever marker prints one login line (the marker
was probably renamed); behaviour stays Midnight, detection never keys on the number.
Forever characters carry a surname (`Client.HasCharacterSurnames`): the Fonts
page offers Full name, First name or Surname for every unit and group frame
(`general.characterNameParts`). `Game/Forever/UnitFrames/MSUF_UF_CharacterNames.lua`
applies it through the unit text module's display-name resolver, calls the
nickname integration's resolver first, reads the separator from Blizzard's
`Constants.CharacterNameSeparatorConsts`, and never searches or compares a
secret name.
Shared group loaders also include `GroupFrames/MSUF_GroupFrames_Additional.lua`
and its XML template after the main group runtime. They own optional party-target,
pet, friendly-boss and healer-mana frames; secure layout changes wait until combat
ends. The group configuration compiler owns tier sizes, class ordering, small-raid
party styling, independent indicator scaling and the separate name strip.
`Game/Forever/GroupFrames/MSUF_GroupFrames_BuffCoverage.lua` (Mainline manifest only,
returns outside Forever) draws the buff coverage icons: UNIT_AURA per group token,
spell-ID matching from the Forever SpellName data, incremental payloads, and no aura
reads while aura data is restricted unless a buff is flagged never secret.
The optional detached GCD bar stays behind the existing native duration capability
probe and does not add a Classic timer emulation; the separate bar and its Edit Mode
mover also need the Duration API (and spell 61304 on WoW Forever).

The optional resource helpers follow capabilities, not client flags: Ignore Pain
and the Arcane Surge window need the aura container and the spell in the client's
spell data; the Mana regeneration pause and the Mana return pulse are game rules
of Classic Era, TBC and WoW Forever and need the duration API
(`MSUF.CPBuilders.ManaRegenTimersSupported`), and the menu, preview samples and
search filter ask the same predicate. The Arcane window has one slot per phase
(Arcane Surge, Arcane Soul above it, each in its own colour); its text shows
seconds, the global cooldowns that can still start, or both, can stay blank until
a chosen number of seconds is left, and can warn during the last global cooldown.
Settings saved under the former names of these helpers move over once.

Forever-only behaviour keys on `Client.IsForever`, read once at file load.
`Client.AddonVersion` is the MSUF version of the running client, also read once
at file load; every version display, the version check and the analytics read
that field instead of asking the TOC again. Every client TOC's `## Version` carries `VERSION`. WoW Forever shares the Mainline TOCs, so the core
Mainline TOC names its version in `## X-MSUF-Version-Forever`, which the gate
and the release-line contract hold equal to `VERSION`. A game mode that shares
a TOC later gets its own `X-MSUF-Version-<Mode>` field the same way.
So that Blizzard's AddOn list shows the right number too, each `_Mainline.toc`
carries two conditioned lines, `## Version: <release> [AllowLoadGameType standard]`
and `## Version: <release> [ExcludeLoadGameType standard]`. Blizzard's own TOCs
repeat a metadata key with game type conditions the same way, and only the
`standard` token is used because every client knows it. `Client.AddonVersion`
cuts off a condition a client hands back as text.
`Client.IsGameRuleActive(ruleKey)` reads Blizzard's game rules, such as
`EditModeDisabled`, and returns nil when a client has no such rule.
`/msuf clientinfo` prints every fact above plus the state of the Blizzard addons
MSUF integrates with, which pet happiness API exists, and the character name
facts (regional unique names, the surname setting, the name separators and
whether `UnitName` returns a second value; never a name), so the first bug
report from a new client carries what is needed to support it.

### Reading a client fact: the house idiom

A client fact never changes while the client runs, so it is read once when the
file loads, never per event. Two positions, one form each:

- A module-level constant, when the fact gates a whole block, a definition or a
  hot path:

  ```lua
  local IS_FOREVER = MSUF.Client.IsForever == true
  ```

  `MSUF.Client.<Fact> == true`, UPPER_SNAKE name; never nil-guard `MSUF.Client` (ratchet).

- An inline condition, when one decision point needs the fact:

  ```lua
  if MSUF.Client.SupportsThreatText == true then
  ```

- `local Client = MSUF.Client` when a file reads three or more facts or calls
  the capability functions (`SupportsEvent`, `SupportsUnit`,
  `SupportsGroupKind`, `SupportsClassResource`, `IsGameRuleActive`). It is the
  companion of the two forms above, not a third dialect.

Pick the fact that names the question. `Client.Family` answers "which build
runs" and is what a Classic hunk in a shared file gates on
(`IS_CLASSIC_FAMILY`); `Client.IsVanilla`/`IsTBC`/`IsMists` name one flavor;
a `Supports*`/`Has*` capability is better than either wherever one exists,
because it survives a new client. `Client.Family == "Classic"` and
`Client.IsClassic` are equivalent by construction
(`Game/Shared/Initialize.lua:89,136`) but are not interchangeable in intent,
so neither is rewritten into the other.

Two checks keep the model honest. `tools/tests/classic_project_id_reads_smoke.lua`
limits raw `WOW_PROJECT_ID` reads in every tracked Lua file of both
shipped addons (core and Options; vendored libraries aside) to a reviewed allowlist; that
allowlist has been empty since 2026-09-19 (`ALLOWED = {}` at line 92), so
outside `Game/Shared/Initialize.lua` no raw project-ID read is left.
`tools/audit-classic-ui-source.ps1` pins every TOC
game-type token and every `C_GameRules` `Is*` function on the mirror branches,
so a refreshed mirror that brings a new client or game mode fails the full gate
until the client model handles it.

## Install for testing

Copy these two folders into the selected client's `Interface/AddOns`
directory:

- `MidnightSimpleUnitFrames`
- `MidnightSimpleUnitFrames_Options`

Do not rename the addon folders or the suffixed TOCs. WoW selects the matching
TOC for the running client. Enable "Load out of date AddOns" only when testing
against a newer point build than the interface values above. A
`MidnightSimpleUnitFrames_Assistant` folder left from an older build can be
deleted: 6.5 no longer ships or loads it, and a CurseForge app update removes
it by itself.

## Validation boundary

`tools/test-classic-prototype.ps1` validates every addon TOC for every client in
the matrix, recursive XML load graphs, Lua 5.1 syntax, client bootstrap,
Blizzard resource ownership, ClassPower providers, legacy cast/channel tuples,
native prediction events, Classic aura compilation/rendering/filter plans,
group indicator datasets, forbidden Blizzard namespace writes, and the load
graph of every client (`tools/load-graph.lock`, below). This repository is an
independent codebase: no file is a mirror of another repository, so editing any
addon file needs no manifest row. This document records no counts: every gate
run prints the live numbers on its `Load-graph lock:`, `Load graph:`,
`Unloaded addon Lua:`, `Classic flavor load coverage:` and `Smoke inventory:`
lines. When the local UI mirror is present it also runs
`tools/audit-classic-ui-source.ps1` against the relevant Blizzard client
branches.

Every rule has one authority, and no rule is checked a second time with another
threshold:

| Rule | Authority |
| --- | --- |
| Which Lua files each client loads, and the load-order invariants | `tools/load-graph.lock`, `tools/load-graph.lua` |
| TOC identity lines | `tools/classic-toc-identity.tsv` |
| Lua 5.1 compiler limits and code-shape defects | `tools/quality_ratchet.py` |
| Removed settings, labels, commands, bindings, defaults, exports | `tools/feature_inventory.py` |
| Global names and namespace fields other addons read | `tools/public-globals.tsv`, `tools/public_globals_ledger.py` |
| Old profiles keep their effective settings | `tools/fixtures/profiles`, `tools/profile_corpus_golden.lua` |
| Startup source size | `tools/tests/startup_locale_manifest_smoke.lua` |
| Blizzard UI contracts | `tools/audit-classic-ui-source.ps1` (full gate only) |

The TOCs are held to one set of identity fields. Per addon, every client's TOC
carries the same metadata lines except `Interface`, `Title`, `Notes`,
`Category`, `Version`, `X-MSUF-Version-Forever`, `OptionalDeps` and
`X-MSUF-Client`. Agreement between the clients cannot notice a line that
disappears from all of them, so `tools/classic-toc-identity.tsv`
(`Addon<TAB>Rule<TAB>Line`) pins them: every client TOC of the core addon
declares exactly the `SavedVariables` line (renaming a saved variable orphans
every profile), the Curse and Wago IDs, the `X-MSUF-UnitFrames*` fields
`Libs/MSUFUnitFrames/init.lua` reads and the `AddonCompartmentFunc*` names; every
Options TOC declares `LoadOnDemand: 1`, its `Dependencies` and `X-MSUF-Options`
and has no `SavedVariables`. Changing one of these values is a deliberate edit of
that file. The core TOCs also keep the `OptionalDeps` they name today (every
client the four shared names, Mainline also `Blizzard_AuraContainer`,
`Blizzard_PingUI`, `EllesmereUI`, `Grid2` and `Details`); adding a dependency is
free, dropping one fails the gate. The same block of the gate rejects a
malformed addon file path and two paths that differ only by case, and
`tools/tests/gate_manifest_rules_smoke.py` pins both rules on fixtures and
removes every pinned line from the real TOCs.

### Load graph lock

`tools/load-graph.lock` lists, for each client and each shipped addon, the Lua
files that client loads, in load order. The clients are the rows of
`tools/classic-client-matrix.tsv` plus WoW Forever, which reads the Mainline
TOCs and differs only by the `camelot` game type (Midnight is `standard`); every
text locale is listed. `tools/load-graph.lua` generates it with the same
TOC/XML reader the client smokes use (`tools/tests/client_manifest.lua`):

```powershell
lua tools/load-graph.lua --write    # after adding, removing or moving a TOC or XML manifest entry
lua tools/load-graph.lua --check    # what the gate runs
```

Adding a Lua file to a manifest without regenerating the lock turns the gate
red with the clients and the file named; regenerate and review the diff of the
lock. The gate also walks the same TOCs with `Get-MsufLoadGraph` and requires
the lock to match, so the two readers cannot drift apart. Editing a Lua file
that is already loaded changes nothing in the lock.

`--check` and `--write` hold three invariants (`--write` refuses to bless a
violation): Mainline and Forever never load a Classic-only tree
(`Game/Classic`, `Game/Vanilla`, `Game/TBC`, `Game/Mists`) or a `*_Classic.lua` /
`*_Classic.xml` file, Lua or XML, under any game type a Mainline TOC line names
(the check walks every conditional line, so `[AllowLoadGameType plunderstorm]` is
covered); no Classic client loads the Retail Auras3 runtime
(`Auras3/MSUF_Auras3_DotData.lua`, `_DefensiveData.lua`, `_AuraNameResolver.lua`,
`_SpellIndicators.lua`, `_UnitFrames.lua`); and no client loads one Lua file
twice across the core and the Options addon. `tools/tests/load_graph_lock_smoke.py`
pins the generator and these rules on fixtures.

### Retired addons and files

`tools/classic-addon-tombstones.txt` records what this tree retired on purpose.
A line with one field names a retired addon folder (today
`MidnightSimpleUnitFrames_Assistant`); a line `<addon><TAB><path>` names a
file of a shipped addon that retired with it (today the Options bridge
`Shell/Menu2/MSUF_AssistantBridge.lua` and `Locales/MSUF_PriorityFrames_FAQ.lua`,
whose only consumer went with the Assistant). The gate decides presence through git: it fails when git tracks a file
below a retired folder, when a retired folder still holds a TOC, or when a
retired path is tracked or loaded by any TOC or XML manifest. An empty retired
folder that `git rm` leaves on a Windows checkout is fine. The PowerShell reader
(`Import-MsufAddonTombstones` in `.github/scripts/ClassicGate.Common.psm1`) and
the Python reader (`.github/scripts/classic_tombstones.py`) follow the same rules,
and `tools/tests/classic_no_assistant_contract_smoke.py` checks every fixture
with both.

### Global name resolution

`tools/tests/unresolved_global_reads_smoke.py` compiles every Lua file of both
shipped addons with `luac -l -p` and reads the GETGLOBAL and SETGLOBAL
instructions out of the listing, which is the compiler's own answer to which
names are read from and written to the global table. A read must resolve to a
Lua 5.1 name, to a global this tree defines (a SETGLOBAL, an assignment to `_G`
or to a `local G = _G` alias, or an `ExportPublic`/`ExportGlobal`/`ExportCompat`
registration that publishes it), or to a reviewed row of
`tools/lua-global-reads.tsv`; a write must be an MSUF-owned name (`MSUF_*`, the
`BINDING_*` keybinding strings, the `SLASH_*` commands) or a reviewed `write`
row. The TSV carries `Global<TAB>Kind<TAB>Reason`, stays sorted, and fails when
a row names something nothing reads or writes any more, exactly like
`tools/client-boot-globals.tsv`. A new unresolved name therefore fails the gate
until someone reviews it; `Kind` `defect` and `vestigial` mark reads that are
known bugs or leftovers, each with its reason in the row.

### Public globals ledger

`tools/public-globals.tsv` records which exported global names and which fields of exported tables something
outside the core and Options addons reads, and who. It is evidence from a fixed set of local sources, not a
census: absence from the ledger means none of the scanned sources reads the name, not that nobody does.

The core TOCs declare both profile SavedVariables so every legacy standalone
`MSUF_DB` loads reliably for the one-time migration. The startup lifecycle settles,
migrates and binds at `ADDON_LOADED`; `MSUF_DB` remains the public profile alias
through the session. Native logout handlers registered after login restore the
variant base and flush profile synchronization before clearing that alias, so the
client saves the profile pool only once in `MSUF_GlobalDB`. Spec auto-switching
keeps its original `PLAYER_ENTERING_WORLD` phase. Locale finalization invalidates
aura inputs; frame startup applies them without building group headers early.

Scanned: the MSUF Suite, MapkoSkin and MidnightCooldownManager repositories, and every other addon installed
under the author's WoW client folders (the first client folder holding a file wins; MSUF's own folders and
installed copies of the repositories are skipped). Counted as a read: a bare global read the compiler sees,
`_G.NAME`, `_G["NAME"]`, `rawget(_G, "NAME")`, `getglobal("NAME")` and a quoted MSUF-looking name. A field
read off a local that holds an exported table (`local host = _G.MSUF_NS ... host.MSUF_Auras3`,
`local menu = assert(_G.MSUF2)`, a small accessor function) is a `nsfield` row such as `MSUF_NS.L` or
`MSUF2.Undo`, kept only when a source line writes the field or a booted client holds it. A quoted prefix that
can build exported names (`"MSUF_boss" .. i`) is a `dynamic` row. Besides readers, the ledger lists what the
client itself looks up (`SLASH_*`, `BINDING_*`, Bindings.xml actions, XML names and the `function=` and
`mixin=` names of XML attributes, `UISpecialFrames`, AddonCompartment functions), the SavedVariables
`MSUF_DB` and `MSUF_GlobalDB`, and the names an `Integrations/` bridge publishes for other addons (those have
no reader found and are kept as a designed surface). Columns are `name`, `kind`, `exporter`, `consumers`,
`readers`, `addons`, `evidence`, `clients` and `note`.

Not covered: names built from computed strings (`_G[prefix .. x]` with a prefix the code does not spell),
addons that are not installed on the author's machine, user macros and key bindings, reads of fields through
a local the scanner cannot resolve to a table, registry tables read with a computed key
(`MSUF_UnitFrames[unit]` is guarded by the table row and the literal-key rows only), fields of frames
(`MSUF_player.Background`), and the Options addon, which ships with the core. A name that only a run-time
export site can publish is found through the sites `--write` lists, not through a booted client alone.

`tools/public_globals_ledger.py` checks the ledger by default and needs nothing outside the repository: the
file is well formed, every evidence class is backed by a consumer entry, every ledgered name has an exporter
in the source and every ledgered field a line that writes it. Only code vouches for a name; one left in a
comment or a string does not. A failure names the readers that would break. `--write` rebuilds the ledger
from the local external sources, `--refresh-exporters` re-reads exporters and clients after a refactor, and
`--inventory` prints every name the source text exports and the run-time export sites.
`tools/tests/public_globals_smoke.lua` boots each client and asserts that every ledgered name and field is
present after login with the recorded kind (a stubbed client, not the game);
`tools/tests/public_globals_ledger_smoke.py` runs the check and proves both halves, the scanner and the
outside-reader scan can fail. A refactor that renames or moves a ledgered name or field must update the
ledger in the same change.

### Unloaded and retained files

The tree deliberately retains the 48 `Media/Shapes` files plus
`Runtime/MSUF_UIThemeBridge.lua` and `Shell/Menu2/MSUF_Menu2_ThemeSkin.lua` from the old
MidnightSkin experiment. Their former canonical loader/consumer wiring no
longer exists, so they are preserved historical source/assets, not claimed as
runtime-reachable. Restoring or retiring that feature is a separate explicit
decision. The two Lua files are `retained` rows of
`tools/classic-unloaded-addon-lua.tsv`, which records that decision for the
gate's dead-Lua check below.

Every versioned addon Lua file must be loaded by a shipped TOC: the gate fails
on one that no TOC or XML manifest of any client reaches, because it would ship
as dead payload. The exceptions are rows of `tools/classic-unloaded-addon-lua.tsv`
(`Path<TAB>Kind<TAB>Reason`): `diagnostic` for a developer diagnostic that no TOC
loads (today `Features/Diagnostics/MSUF_Feature_DebugPosition.lua`),
and `retained` for a file the owner keeps unloaded on purpose
(today the two theme-bridge files), whose reason must cite the owner decision.
An unlisted file that no TOC loads fails, and a row whose file a TOC loads is stale.
The pixel layout coverage smoke skips the listed files, and
`tools/tests/unloaded_addon_lua_smoke.py` pins the rules on fixtures.

### Flavor load coverage

Classic flavors load hand-kept copies of several Mainline manifests, so a Lua
file added to one of them could otherwise never load on Classic while
every other check stays green. The gate resolves the Mainline core and Options
TOC load graphs and, for each Classic flavor in the client matrix, puts every
Mainline Lua path into one of two classes:

- loaded: that flavor's core or Options TOC loads the same path;
- excluded: `tools/classic-flavor-load-exclusions.tsv` lists the path for that
  flavor with a reason.

Any other path fails the gate with the flavor and the path. The exclusions
file is tracked, starts with the header `MainlinePath<TAB>Flavors<TAB>Reason`,
and holds one ordinal-sorted row per Mainline path. `Flavors` is `*` for every
Classic flavor, including one added later, or a comma list of matrix suffixes.
Every row must stay needed: it fails as stale when Mainline no longer loads its
path or when a listed flavor loads it. Each reason says why Classic
does without the file and names the Classic file that takes its place, if any.
Full and `-SelfContained` runs both print the totals on the
`Classic flavor load coverage:` line.

### Quality ratchet

`tools/quality_ratchet.py` measures every owned Lua file (both addons and the
MSUF-owned `Libs/MSUFUnitFrames`; vendored libraries are skipped, and the data
files `tools/quality_ratchet_allowlist.json` declares are held to the compiler
limits only) and compares it with `tools/quality_ratchet_baseline.json`. The gate
runs it as `tools/tests/quality_ratchet_gate_smoke.py`;
`tools/tests/quality_ratchet_smoke.py` is the tool's own self-test. It is the
only authority for Lua's compiler limits: the gate holds no second limit block.

- Size metrics (`lines`, `max_function`, `main_locals`, `max_locals`,
  `max_upvalues`, `max_slots`) may grow up to the Classic profile limit: 160
  main-chunk locals, 160 locals in any other function, 45 upvalues, 230 stack
  slots and 150 lines per function. A file or function already over a limit may
  not grow past its baseline, reflow included. A factory wrapper (a top-level
  `Factories.X = function(...)` or `return function(deps)` that covers most of
  the file) counts as a module: its inner functions are measured as functions
  and its own locals count as main-chunk locals.
- Defect metrics (`g_reads`, `type_guards`, `fallback_lambdas`, `client_guards`,
  `semicolon_lines`, `long_lines` over 160 characters, `long_functions`,
  `clone_windows`) fail on any increase. A file the baseline does not know is
  held to the profile limits and starts with no `;` statements, no line over
  160 characters, no fallback lambda and no client guard. A failure names the
  lines and the remedy.
- A justified exception is an entry in `tools/quality_ratchet_allowlist.json`
  (file, metric, max, reason, date). After a merge, rebaseline with
  `python tools/quality_ratchet.py --update`; `--accept-regressions` is a
  deliberate call. `--report` prints the headroom to Lua's hard limits.

### Feature inventory

`tools/feature_inventory.py` compares the tree with the frozen
`tools/feature_inventory_baseline.json`: enUS locale keys, slash commands,
bindings, the Menu2 search index (settings, rows, actions), defaults keys and
exported names. Every item the baseline has and the tree lacks fails the gate
unless `tools/feature_inventory_allowlist.json` lists it with a basis
(`migration`, `owner`, `dead` or `moved`), evidence, a reason and a date; the
gate runs it as `tools/tests/feature_inventory_gate_smoke.py`, and `--diff` lists
every removal and addition. A feature is never deleted to pass it.

### Profile data migration boundaries

`State/MSUF_Defaults.lua` owns `MSUF.ProfileMigrations`, an ordered ledger ending
in `_msufStateSchema = 700`. The existing `_msufProfileSchema = 600` and native
export schema stay portable to 6.50. FirstLoad still applies the same pre-6
archive and standalone precedence decisions before migration. Fresh profiles
receive their authored factory seed before the ledger can write any stamp.

The cold lifecycle translates aliases and migrates the selected profile before
binding it. Profile init migrates the pool once; create, copy, reset, switch,
detached export and import staging also finish their own profile at mutation
boundaries. `MSUF_EnsureDB` never walks inactive profiles. The revision-17 fast
path materializes only the missing portrait dragon, GCD, interrupt-marker,
arena trinket and capability-dependent pet happiness fallbacks. Explicit false,
zero and customized values survive. Group buff `trackedStrata` follows its old
runtime inheritance (`trackedFrameStrata`, then spell indicators, then AUTO).
Group tooltip removal is one-shot. Legacy media names have one State mapping;
the existing late-LSM timer still delegates to that owner and remains retained.

Import candidates receive one heavy defaults pass before commit. Commit adopts
the completed table without a second pass; selected-owner imports still commit
only their explicit owners. A narrow group-font completion keeps the previous
post-repair ownership decision. Staging, rollback, runtime and Suite notification
order stay at their original boundaries. Valid beta native schema-1 full profiles
are admitted only through decoded import migration with real frame geometry;
invalid beta wrappers and pre-6 saved installs keep their refusals/archive policy.

The MSUF2 print reader inspects length and raw transport heads before allocating
decoded print-byte tables. Compressed payloads retain the 192 KiB cap; raw legacy
CBOR/Ace/text tables retain the larger decoded-size allowance and both print bit
orders. The print alphabet also admits external representations (including a
reversible alphanumeric hex transport), so rejecting an oversized own stream does
not reject an external interpretation. If an external decoder is installed, its
inverse decode is conditionally required before the unchanged 192 KiB compressed
and 32 MiB decoded checks. Alphabet/encoded length cannot universally bound that
decoder's work or allocation; the existing 8 MiB input cap still applies. Without
an external decoder, identifiable oversized own streams stop before full Lua
byte-table or native base64 decoding. Decoded-size rejection happens after inflate
because neither supported decompressor accepts an output ceiling.
Behaviour guards: `profile_data_boundaries_smoke`, `profile_printsafe_bound_smoke`,
`profile_external_transport_smoke`, the existing transaction suite and the 31-case
profile corpus. The complete external smoke uses real reversible transport, CBOR,
deflate and public import, including compressed-limit refusal and rollback. It
pins the production decoded limit and exercises that branch at a smaller test
ceiling to fit the numeric output tables of the 32-bit offline inflater; it does
not claim a full 32 MiB native allocation or live-client bound.

### Old-profile corpus

`tools/fixtures/profiles` holds anonymized SavedVariables files and genuine
profile strings from every 5.x and 6.x era, and `golden/*.golden` records the
effective settings each one must give. `tools/profile_corpus_golden.lua` runs
the real login, migration, create, switch, reset, import and export paths in a
fake client; the gate runs it once per client (Mainline, Forever, Vanilla, TBC,
Mists) as `tools/tests/profile_corpus_golden_smoke.lua`, plus the codec emulator
smoke `tools/tests/encoding_util_emulator_smoke.lua`. A refactor is accepted
only while the golden files stay byte-identical. They change only for a
deliberate, reviewed behaviour change, in the same change, with a reason for
every changed line; `tools/fixtures/profiles/README.md` has the format, the
entries and the regeneration command.

### Startup source budget

`tools/tests/startup_locale_manifest_smoke.lua` sums the LF bytes of the startup
files each client and language actually parses and fails above a ceiling for
Mainline and one for the Classic clients. It is a tripwire for whole catalogs
and the Options addon, not for ordinary growth, and its comment keeps a dated
line for every raise. The 7.0 wave-1 bug fixes share one bounded allowance
(Mainline 16,925,000 and Classic 14,805,000 bytes, up from the 6.50 values
16,905,000 and 14,785,000). Wave 2 removes dead code and owes both ceilings back
under the 6.50 values; until then no change raises them again without a dated
line explaining why.

### Menu translations

Every menu-facing string exists in all ten translated packs and differs from
the English key. `tools/tests/menu_page_labels_locale_smoke.lua` boots each
client and records every string the built menu resolves through the locale
table (a helper that captured `MSUF.Translate` at load time is seen too): the
default build of every page, every segment tab, every Aura workspace view (unit
page x lane or container x tool, group scope x lane x tool, the Appearance
products), the selectable status indicators and Class Resources workspaces,
plus tooltips and dropdown entries, which are translated only on hover or open.
`tools/tests/locale_static_strings_smoke.lua` covers what no page build
reaches: every label and breadcrumb segment of both baked search indexes and
every literal handed to a translation call (prompts, chat lines). A string may
stay English only through a reasoned row in
`tools/locale-same-text-allowlist.tsv` (a name, a token that passes through the
locale table, a word the language shares); the static smoke fails a row that no
longer excuses a real omission. The last argument of either smoke names a file
that receives every failing string with the packs that lack it and the first
state that produced it, for translators. The bundled release notes
(`State/MSUF_Changelog.lua`) are not scanned: most of their entries were never
translated. Search breadcrumb segments are derived from control paths; one used
by fewer than 8 index rows stays English (allowlist) until breadcrumbs are built
from real section titles.

The internal [unit-frame return-value text contract](docs/UNITFRAME_TEXT_CONTRACT.md)
records group preview compatibility and the shared engine formatter/name owners.
The strict secret smoke and native/instruction/allocation budgets cover that seam.

### What the gate does not prove

These are source/runtime-mock gates, not a substitute for logging into every
class/spec on all game clients. Release certification still requires the live
matrix: clean install and migrated profile, combat and reload, every
class-resource owner, cast/channel/interrupt states, aura/filter/tooltip
combination, party/raid secure headers, Options, and action-button taint
checks. A source build must not be described as live-certified until that
matrix has actually passed.

## Running the gate and single smokes

Run the gate from the repository root before a change reaches `main` and before
any tag. `tools/run-classic-gate.ps1` is the entry point. It resolves Lua 5.1,
`luac` 5.1 and Python 3 (`-LuaPath`, `-LuacPath`, `-PythonPath`, then
`MSUF_LUA`, `MSUF_LUAC`, `MSUF_PYTHON`, then `PATH`), prints the versions it will
use, refuses with a remediation message when one is missing or the wrong
version, and forwards the other parameters to `tools/test-classic-prototype.ps1`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-classic-gate.ps1 -SelfContained -Jobs 4
```

A local run takes 4 to 15 minutes, depending on the machine's load and `-Jobs`;
it took 30 minutes on 2026-10-13 while several other gates ran in parallel.

| Parameter | Effect |
| --- | --- |
| `-SelfContained` | Everything except the Blizzard UI source audit (the CI subset). It never replaces the full gate. |
| `-Jobs <n>` | Smokes run in parallel on `n` workers (default: the processor count, at most 8). Use 4 when other gates share the machine. |
| `-Only <regex>` | Runs only the smokes whose file or label matches. It adds a `SKIPPED:` line, so a narrowed run is never a pass. |
| `-ListSmokes` | Prints every expanded invocation as `LISTSMOKE nnn \| ...`, runs none and stops before the static checks. |
| `-FailFast` | Aborts at the first failing smoke. By default failures are collected and printed together at the end. |
| `-AllowMissingTools` | Lets a structure-only run continue without `luac`, `lua` or the UI source mirror; each skipped step prints a `SKIPPED:` line. |
| `-RequireNoSkippedSteps` | Fails when any step was skipped. The CI full gate passes it. |
| `-SkipTier <tier>` | Leaves one smoke tier out (`nightly` holds the slowest smokes) and prints one `SKIPPED:` line naming the tier and its invocation count. The default runs every tier. |
| `-Shard <k>/<n>` | Runs the k-th of n slices of the smokes; shard 1 also runs the static checks. See below. |
| `-TimingsOut <file>` | Writes the seconds each invocation took, in the format of `tools/classic-gate-weights.tsv`. |

A pass is: exit code 0, no output line containing `WARNING`, a `Smoke inventory:`
line that accounts for every tracked smoke (ran plus retired), and, for
`-SelfContained`, exactly one `SKIPPED:` line (the Blizzard UI source audit). A
full run with the mirror prints no `SKIPPED:` line. Any other `SKIPPED:` line
means the run proved less than a pass. A push-tier run (`-SkipTier nightly`) or a shard prints
further `SKIPPED:` lines naming the tier and the shard; it is the CI subset, not a full pass.

The full gate needs the Blizzard UI source mirror at
`_local_workflows/references/wow-ui-source`: a clone of `Gethe/wow-ui-source`
with every branch, remote name `upstream` (git-ignored, read-only for MSUF work;
a fresh checkout has none). Create it with the clone command of
`.github/workflows/classic-full-gate.yml`, or reuse an existing copy, and
refresh it with `git -C _local_workflows/references/wow-ui-source fetch upstream`.
The audit reads the branch tips through git only.

Smokes come in tiers. The `Tier` column of `tools/classic-gate-smokes.tsv` is
the last one and may be left out of a row: no value means `push`, the tier every
push and pull request runs. `nightly` holds the slowest smokes. The default
local run executes every tier. `-SkipTier nightly` leaves one out and prints a
single `SKIPPED:` line naming the tier and how many invocations it holds; the
smoke inventory still accounts for every smoke, counting one that only a skipped
tier covers as deferred, never as unrun. Move a smoke between tiers by editing
its `Tier` cell: the gate prints the slowest invocations of every run, and that
list is the evidence.

`-Shard <k>/<n>` runs the k-th of n slices of the smoke plan (what is left after
`-Only` and `-SkipTier`), so CI can spread the push tier over n jobs. The slices
are balanced by `tools/classic-gate-weights.tsv` (Name, Seconds): each
invocation, longest first, goes to the shard with the least weight so far, and
one the table does not know weighs the median. Every shard computes the same
split from the same commit, so all must get the same `-Only` and `-SkipTier`.
Shard 1 also runs the static checks (syntax, load-graph lock, error paths, TOC
invariants, ledgers); shards 2 and up run smokes only, and every shard prints
one `SKIPPED:` line naming itself. The inventory counts the other shards'
smokes as deferred. Refresh the weights table from a full run with `-TimingsOut`
when the plan changes much. `tools/tests/gate_shard_union_smoke.py` proves that the
shards of the workflow's n together hold every push-tier invocation exactly
once, that no shard is empty or lopsided, and that the workflow's matrix names
shards 1 to n.

CI runs these jobs. `.github/workflows/classic-gate.yml` has two kinds
of job for every push and pull request to `main` that touches the addon folders,
`tools/`, `.github/`, `VERSION` or `CHANGELOG.md` (a push that changes only other
documents runs neither): `push-gate` is a matrix of six shards, each running
`run-classic-gate.ps1 -SelfContained -SkipTier nightly -Shard <k>/6` with every
core the runner has, and `source-audit` clones
`Gethe/wow-ui-source` (depth 1, every branch, no working tree) into
`_local_workflows/references/wow-ui-source`, runs
`tools/audit-classic-ui-source.ps1` and the one smoke that reads the mirror
(`group_raid_header_blizzard_smoke.lua`; `push-gate` runs it on its attribute
contracts only). The audit reads Blizzard's live branches, so `source-audit` can
turn red without any change here; `push-gate` reads nothing but the commit.
Neither job re-runs the other's work.

`.github/workflows/classic-nightly.yml` runs the full gate once a day and on
demand: every tier plus the source audit. Its steps live in the reusable workflow
`.github/workflows/classic-full-gate.yml`, which `classic-nightly.yml` and
`release-classic.yml` both call, so a release runs exactly the nightly gate.
`release-classic.yml` runs three jobs for a `classic-v*` tag: `preflight` (tag
freshness against `origin/main`, the CurseForge secret and the push-tier gate), then `classic-full-gate`
on the tag, then `publish-classic`, which packages and uploads only when both
are green. The push-tier subset cannot see drift of Blizzard's source or the
nightly tier, so it is a pre-check, never the only gate on a published build.
The full-gate job passes `-RequireNoSkippedSteps`, which makes the gate refuse
to pass when any of its own steps was skipped: on a runner a missing Blizzard
mirror or a skipped tier is otherwise a skip, not a failure.

`.github/scripts/assert-classic-release-line.ps1` runs in every gate and in the
packager. It takes the release line from `VERSION`: the shared channel resolver
(`resolve_classic_release_channel.ps1`) must accept it, a stable release spells
its minor with two digits (`7.00`), a prerelease names `<major>.<minor>`
(`7.0-beta1`), and every TOC, the changelog section and the two generated
changelog payloads must carry that version. `tools/tests/release_line_version_smoke.py`
pins it on a fixture repository for several release lines.

Requirements:

- Lua 5.1 `lua` and `luac` first on `PATH`; the gate checks both versions. Lua
  5.4 cannot run the smokes (they use `unpack()` and `loadstring()`).
- A real Python 3 as `python`. On Windows a bare `python` can be the Store alias
  stub, which exits without running anything.
- The Blizzard UI source mirror, for the source audit only.

A single smoke runs with the repository root as the working directory. Most
Lua smokes take the root as their first argument; the `lua+driver` ones run
through `.github/scripts/auras3_test_driver.lua`:

```powershell
lua .github/scripts/auras3_test_driver.lua tools/tests/classic_aura_backend_smoke.lua <repository root>
```

Each smoke's row in `tools/classic-gate-smokes.tsv` (columns Matrix, Runner,
Smoke, Arguments, Label, Tier) is the reference for its runner and arguments, and
`-ListSmokes` shows the expansion. Tier is optional (blank means `push`). Matrix values such as `clients`, `classics`
and `clients+Forever` repeat a row per client; the tokens `{root}`, `{root/}`,
`{flavor}` and `{clientToken}` expand per run. Two traps:

- `tools/tests/classic_client_detection_smoke.lua` must not run through the
  driver: the driver stubs `issecretvalue`, which hides the missing
  secret-value API case this smoke pins.
- `tools/tests/classic_client_bootstrap_smoke.lua` takes a spec name first (a
  matrix suffix, `FutureTaggedVanilla`, `FutureProjectVanilla`,
  `UnknownUntagged`, or `TagOnly<Suffix>` plus the token), then the root.

`tools/tests/classic_menu_atlas_smoke.lua` takes the root, a matrix suffix,
`FutureVanilla` or `Forever` (a simulated WoW Forever client), and optionally a
menu look (`classicGlass`, `midnight`, `midnightDark`, `tinted`). All looks are
selectable on every client; only a fresh profile's default differs, Classic
Glass on `Forever` and Midnight elsewhere.

The four golden parity smokes (`health_background_sample_parity_smoke`,
`health_runtime_equivalence_smoke`, `text_runtime_value_parity_smoke` and
`castbar_tint_parity_smoke`) compare the current source with observable
behavior recorded in `.github/scripts/golden/<smoke>.golden` (the files were
recorded from the last Retail commit before the cutover). Native arguments,
order, displayed values, call and allocation counts must stay equal, and Lua
instruction and secret-probe counts may not exceed the recorded ones. Logs are
stored as chunk digests (`.github/scripts/golden_baseline.lua`), so a failure
names the first differing chunk and shows its current lines. Their rows pass
only `{root/}`. A change that is meant to alter observable behavior re-records
the file from the source whose behavior is now intended, and the golden diff is
reviewed like any other behavior change: `lua .github/scripts/auras3_test_driver.lua
.github/scripts/<smoke>.lua <repo> <source root> record "<label>"`. With a source
root and no `record` the smoke compares against that live tree instead of the
golden file.

Every tracked smoke either has a row in `tools/classic-gate-smokes.tsv` or is
listed with a recorded reason in `$retiredSmokes` in
`tools/test-classic-prototype.ps1`. `Invoke-GateSmoke` records each smoke it
starts. After the last smoke the gate fails on a tracked smoke that neither ran
nor is retired, on a retired smoke that still runs, and on a smoke that ran but
is not tracked by git. A smoke is registered as a row of the TSV, never as a
hand-written call in the gate. `tools/` is git-ignored except for the paths
`.gitignore` re-includes (`tools/tests/` among them), so a new file directly
under `tools/` needs `git add -f`.
A smoke that only a skipped tier or another shard covers counts as deferred, and the
inventory line says how many there are.

## Preview visual rule ownership

Menu2 unit, group and resource previews consume core portrait painters, resource
colour resolvers, health background geometry and castbar detail rules. Their
scale, sample identity and chrome stay local. See
[shared runtime rules](docs/PREVIEW_RUNTIME_RULES.md) for input contracts,
remaining scene boundaries and validation limits. No TOC/XML load order changes
are needed: each provider already loads in core before the Options addon.

## Regenerating the Menu2 search index

The nightly gate also runs the generator with `--check` for both client-family
catalogs. It compares all generated bytes after CRLF normalization and writes
nothing; a harness error or stale row fails independently of the recorded hash.
The fast source-hash check still runs on every push.
The preflight forwards its resolved Lua interpreter to child tools, including
an explicit `-LuaPath` override. Each generator child must also report a zero
process exit status; complete rows alone do not prove a successful build.

The five-page Options schema pilot keeps the existing binding, history, lazy
section and apply owners. See [control schema](docs/MENU_CONTROL_SCHEMA.md) for
default sources, explicit compatibility adapters and immutable built-control
inventories. Its search generation must preserve all rows and identities.

Both `MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex_Data*.lua`
files are generated, never hand-edited. The generator and everything it loads
are tracked, so a clean clone can reproduce both files byte for byte:

| path | role |
| --- | --- |
| `.github/scripts/search_static_index_project.lua` | the generator |
| `tools/search_catalog_harness.lua` | the harness that builds every Menu2 page headlessly; the generator splices it in |
| `tools/MenuTest/wow_stubs.lua` | the WoW API stubs the generator and the harness run on |
| `.github/scripts/auras3_test_loader.lua` | the aura model loader the harness installs |
| `.github/quality/service_ports.lua` | the runtime service ports the harness installs |
| `.github/scripts/msuf_source_slice.lua` | the source slicer the harness reads the profile module with |
| `tools/classic-client-matrix.tsv` | the client facts the generator installs per flavor |

The generator does not run the harness file as it is: it cuts the harness at two
marker lines and splices its own manifest and client facts in (`HARNESS_CUT` and
`HARNESS_MANIFEST_HOOK` at the top of the generator). Keep both marker lines of
`tools/search_catalog_harness.lua` byte for byte, or regeneration fails.

`MSUF_SEARCH_SOURCE_SHA256` is the hash the index records: the SHA256 over every
Lua and XML file under `Shell/Menu2`, relative path and normalized content
separated by NUL bytes, in path order. `.github/scripts/menu2_search_index_hash_smoke.py`
computes exactly that and is what the gate checks, so run it first and take the
hash it prints on a mismatch. The Classic file excludes both index files from the
hash and the Mainline file excludes only itself, so the Classic file is always
stamped first; the Mainline hash then covers the settled Classic file.

From the repository root, with Lua 5.1 on `PATH` (about 100 s per file):

```powershell
$env:MSUF_SEARCH_SOURCE_SHA256 = "<hash with both index files excluded>"
lua .github/scripts/search_static_index_project.lua --flavor Vanilla
$env:MSUF_SEARCH_SOURCE_SHA256 = "<hash with only the Mainline index excluded>"
lua .github/scripts/search_static_index_project.lua
```

`--flavor Vanilla` writes the Classic file as the union over the Classic flavors
in the client matrix; no `--flavor` writes the Mainline file. `--stdout` prints
instead of writing, which is how a regeneration is diffed without touching the
worktree. Regenerating without a content change reproduces the committed bytes,
so the two index files are also the reference for what each menu builds.

A file this repository writes may only claim a generator it tracks:
`tools/tests/classic_no_assistant_contract_smoke.py` reads the first lines of
every tracked file and fails on a "generated by" claim naming an untracked
file (the Mainline alias catalogs that name the Retail-only generator are the one
recorded exception). The changelog payloads
(`Options/State/MSUF_Changelog.lua`, `Options/State/MSUF_ChangelogFull.lua`) are
generated from `CHANGELOG.md` by the tracked `tools/update-addon-changelog.ps1`;
after editing `CHANGELOG.md` run it with `-Version <VERSION>`, and the gate runs
its `-Check` mode, which fails on a stale or hand-edited payload.

## Adding a client flavor

Use only values Blizzard has shipped: a released interface number, TOC suffix
and project ID (`WOW_PROJECT_*` global). Never invent one for an announced but
unreleased client. Checklist:

1. Add a row to `tools/classic-client-matrix.tsv`: suffix, interface list,
   `X-MSUF-Client` token, project global, game type, mirror branch, CurseForge
   game version names and `IsClassic`.
2. Add the two suffixed TOCs (core and Options) by following the
   closest existing Classic flavor. Each carries the matrix interface list and
   an `X-MSUF-Client` line with the matrix token; the core TOC loads
   `Game/Shared/Initialize.lua` and its flavor manifests.
3. Add `Game/<Flavor>` with its manifests and data, following an existing
   flavor: `UnitFrames.xml`, `Auras.xml`, `UnitFrames/GroupFrames.xml`, `ClassPower.lua`,
   the aura data under `Auras` (no alias catalog: the Classic backend matches
   ranks by aura name) and the group indicator data under `UnitFrames/Group`.
4. In `Game/Shared/Initialize.lua`, recognise the flavor by its project global
   and its lowercased `X-MSUF-Client` token, set its `Client` flags, and add an
   `UNSUPPORTED_UNITS_BY_FLAVOR` row for every unit token the client lacks.
5. Extend the per-flavor spec tables in the smokes that key by flavor, for
   example `tools/tests/classic_client_bootstrap_smoke.lua` and
   `tools/tests/classic_aura_rank_name_match_smoke.lua`. The gate derives a
   `TagOnly<Suffix>` bootstrap spec from the new matrix token, and
   `tools/tests/classic_client_detection_smoke.lua` reads the tokens itself.
6. Make sure the matrix mirror branch exists in
   `_local_workflows/references/wow-ui-source`; the source audit reads it.
7. Confirm that the matrix CurseForge game version names exist for the project
   the TOCs declare in `X-Curse-Project-ID`.
8. Add the new flavor's files to its manifests, regenerate
   `tools/load-graph.lock` (`lua tools/load-graph.lua --write`), review the
   lock diff, add any new file directly under `tools/` with `git add -f`, and
   run the full gate.
9. Review `tools/classic-flavor-load-exclusions.tsv`: its `*` rows now cover the
   new flavor as well, and the flavor load coverage check names every Mainline
   Lua path the new flavor does not load.

ElvUI reference inspected locally at commit
`6c164caaa3d34f5c8ca29d2948ce7d9abde828a6`: its `ElvUI_Mists.toc` and
`ElvUI_TBC.toc` select `Game/load_mists.xml` and `Game/load_tbc.xml`, which then
combine shared modules with client-only files. MSUF now uses the same
shared/classic/client-folder pattern and keeps a dedicated unit-frame manifest
for each supported client.

## Adding a game mode or a Mainline-family client

A new game mode or client inside the Mainline family is added only with values
its client has shipped. Nothing is prepared under a guessed project ID,
interface number, TOC suffix or `Enum.GameMode` key. WoW Forever went through
these steps on 2026-09-16 from Blizzard's `forever` source branch (1.60.1.69876)
and the `wow_classic_beta` CDN build: interface 16001 in the Mainline row, the
Blizzard_Game marker in step 4, the `camelot` and `wowlabs` tokens and
`IsSDHDToggleEnabled` pinned in step 5, and a marker contract in the audit that
fails if Blizzard renames the placeholder name "Camelot". Once a build exists:

1. Run `/msuf clientinfo` on it and record the project ID, interface number,
   build, game mode key and number, the `C_GameRules` `Is*` functions, the game
   rules and the Blizzard addon states.
2. If the client loads `MidnightSimpleUnitFrames_Mainline.toc`, add its interface
   number to the Mainline row of `tools/classic-client-matrix.tsv` and to the
   two `_Mainline.toc` files.
3. If the client needs its own TOC suffix instead, add a matrix row and the two
   suffixed TOCs. The gate currently accepts exactly one non-Classic client, so
   `tools/test-classic-prototype.ps1` first needs a second Mainline-family client
   in its single-Mainline check and the Mainline load graph, and
   `tools/load-graph.lua` needs a second Mainline-family view.
4. Identify the client in `Game/Shared/Initialize.lua`. A new `Enum.GameMode`
   key goes into the recognized game modes. A client that reports an existing
   mode (WoW Forever reports Standard) needs a marker instead: a global that
   only a LoadFirst or FrameXML Blizzard file gated to its TOC game type
   defines. Extend `tools/tests/classic_client_detection_smoke.lua` and
   `tools/tests/classic_client_bootstrap_smoke.lua`.
5. Refresh the Blizzard UI source mirror. When the new client's TOC tokens or
   `C_GameRules` functions appear, the audit tripwire names them; pin them in
   `tools/audit-classic-ui-source.ps1` once the client model handles them.
6. Check the Blizzard addons gated by game type. `Blizzard_CooldownViewer` loads
   for `standard, camelot` on the Forever branch, so the cooldown anchor in
   `Integrations/MSUF_Integration_ThirdPartyAnchors.lua` works there; a new
   client that lacks it needs a check.
7. Confirm the CurseForge game version names exist before a release lists the
   new client.

## Forever data validation: 1.60.1.70009

The 2026-09-25 refresh checked `upstream/forever` at `bd2470ae` and the
1.60.1.70009 DB2 exports. Blizzard changed Pet Happiness to three atlases in
`Interface/AddOns/Blizzard_FrameXML/PetHappiness.lua` and fixed restricted
snippet initialization through the `Blizzard_EnvironmentCleanup.toc` dependency.
The Forever indicator now selects those atlases when present, and group headers
again use their secure initialization snippet. The source audit also pins the
Forever marker and checks for new game-type tokens.

All eleven 70009 SpellName locales are available and contain 31,716 rows each,
down from 31,767. Their alias groups changed, so the shipped Forever catalog
was regenerated from those exact exports. The 55 unique curated aura IDs keep
their expected enUS names; none of their SpellEffect rows changed by spell ID
since 69913, and none of the changed SkillLineAbility rows refers to one of
them. SkillLine and ChrSpecialization exports are byte-identical to 69913.
Export hashes and per-locale source builds are recorded in
`.github/auras3-alias-catalog-forever.json`; the table and UI source comparison
is in `.github/forever-client-data-validation.json`. These are offline checks;
combat, taint, SavedVariables and appearance still need a live beta client.

## Class resource availability

`Client.SupportsClassResource(token)` describes the resources implemented by
the active MSUF provider; `SupportsClassResourceSetting(settingKey)` gates
resource-specific behavior controls and cold search results. The preview and
Class Power color menus use the same model. Saved profile keys are preserved.

MSUF Edit Mode exposes a mover for a visible Class Resource bar and separate
movers for detached unit Power Bars. Their quick popup edits X/Y, width and
height. Player Power can remain anchored to Class Resources and follow a
Combo Point move, while dragging Player Power changes only its own offset.
The popup's Anchor class and Sync class controls keep those two relationships
independent. Manual width changes select the matching manual width source.
No mover is shown for an embedded or unavailable bar.

Edit Mode shares Geometry, the UNIT_CASTBAR schema, eight element strategies
and one dormant drag driver. Each owner callback uses native isolated dispatch;
nested internal state publication invalidates superseded deliveries without
changing native EventBus dispatch. Aura and Gameplay strategies use their real
engines' release/history paths. Held native Gameplay drags are stopped before
Cancel/combat/close restore, and late releases cannot write position or history. See [Edit Mode engine delta](docs/EDITMODE_ENGINE_DELTA.md)
for the allocation sampler's collected cold/steady controls and live checks.

- Vanilla, TBC and Forever: Rogue and Cat Form combo points, five uncharged pips.
- Mists: combo points, runes, Holy Power, Chi, Arcane Charges, Shadow Orbs,
  Soul Shards, Burning Embers, Demonic Fury and Eclipse. Previews use the Mists
  counts and resource names. The provider implements Monk Chi; it does not
  implement a separate Stagger bar or Frost Icicles, so those Retail previews
  are not advertised.
- Midnight: its existing resource previews and behavior remain available.

Charged-combo event profiles and API reads are disabled on the Classic and
Forever clients even if the client exposes the Retail API name. Cooldown
anchoring independently follows `HostsCooldownManager` (including Forever).
The source contracts come from `upstream/classic_era`,
`upstream/classic_anniversary` and `upstream/classic`
`Interface/AddOns/Blizzard_UnitFrame/Blizzard_UnitFrame_Classic.toc`, and
`upstream/forever` `Interface/AddOns/Blizzard_UnitFrame/Blizzard_UnitFrame.toc`
with its camelot exclusions, checked against `Game/<Flavor>/ClassPower.lua`.
`tools/tests/classpower_client_resource_gates_smoke.lua` boots all five
clients, checks the actual preview and color catalogs, exercises the behavior
builder and charged API refresh, and verifies cold search results.

### Pixel layout on Midnight and Forever

`MSUF_PixelLayoutRegion` is the shared creation/configuration boundary for
MSUF-owned frames, textures, font strings and lines in Core and Options. It uses
native `SetRoundLayoutToNearestPixel` only on Mainline-family clients with that
API (12.1.5 and Forever); Era, TBC and Mists retain their requested layout.

The boundary returns the original object and keeps constructor/setter arguments
and return values intact. Native template children are included on creation and
after backdrop/button/slider texture setters. Engine-created AuraButtons opt in
before native initialization restricts them; secure unit buttons also opt in at
`UF.ApplySpec`. It never replaces Blizzard globals or widget methods, adds no
polling/OnUpdate/timer, and does not modify profile coordinates or migrate profiles.

Logical movers, drag handles and anchor/measurement proxies opt out of layout
rounding while their visible children opt in. Existing smooth-art opt-outs remain
in force. Masks and native interpolated StatusBar fill textures are excluded;
otherwise a later template refresh could undo the intentional art policy. Native
rounding follows effective-scale changes without rewriting saved UI coordinates.
Borrowed Blizzard/third-party frames are not enrolled by skin/configuration calls.

Pixel setup is absent from repeated text/status/icon layout. Existing frame
structural reapply skips the pixel helper once its template was visited; blocked
protected owners remain eligible for retry. Backdrop setup finishes only after
all nine persistent native pieces were initialized (or intentionally excluded).
Subsequent backdrop setters forward directly without walking pieces or invoking
pixel APIs; clear-only runtime calls use the native setter directly. Smooth
rounded art opts out at creation rather than enabling then disabling rounding.
New/rebuilt regions still need one-time setup, which may occur during combat for
unprotected objects. This does not claim zero engine rendering cost or a measured
FPS improvement.

`pixel_layout_profile_smoke.lua` covers five clients, template children, native
setter semantics, borrowed frames, masks, smooth art and 200 ClassPower layout
pairs with unchanged requested geometry/settings. It also exercises 15,000 warm
layout calls with zero pixel-helper calls and 2,500 backdrop clear/reapply calls
without pixel setup, including blocked-setup retry. `pixel_layout_coverage_smoke.py`
checks every executable owned constructor against explicit nonvisual exceptions
in `tools/pixel-layout-exclusions.json`, so new unrounded preview/widget paths fail
the gate. Lua strings (including secure snippets) are not treated as constructors.
Reference: Blizzard `upstream/ptr2` and `upstream/forever`, SharedXML `PixelUtil.lua`
and `Backdrop.lua`. Offline checks do not prove final in-game rendering or taint.

### Forever Swing Timers

Game/Forever/SwingTimer.lua registers the independent SwingTimers module.
The Combat > Swing Timers page stores per-hand visibility, layout, textures,
colors and typography in MSUF_DB.swingTimers. Main Hand and Off Hand are enabled
together by default; Ranged is optional. The former native master switch is
migrated once. Enabling takes ownership of all three Blizzard bars and temporarily
disables showSwingTimer; disabling or logging out restores its prior value.
Native Edit Mode layouts are never rewritten. Preview mode supports dragging and
is cleared on menu close or combat entry. Profile application refreshes the module.
A one-shot PLAYER_ENTERING_WORLD handler applies saved module enablement after
login/reload; initial profile binding does not run the profile-change fanout. It
reuses the runtime driver and leaves no event subscription when disabled.
Each hand supports bar-plus-timer or number-only display, four spatial fill
directions, and independent fill-up/drain progression. Colors live exclusively in
the hand's three-dot menu. Texture selections store the same asset shown in the
shared media preview, including unregistered built-in choices. A lazy static bar
previews textures without inheriting a live duration driver. Number-only display
keeps the native text binding and hides the bar, background, border and title.

PLAYER_SWING and weapon/combat events follow upstream/forever
Blizzard_SwingTimer/Blizzard_SwingTimer.lua. StatusBar:SetTimerDuration and duration
text bindings follow Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua. Vertical
status bars follow Blizzard_UIWidgets/Blizzard_UIWidgetTemplateFillUpFrames.xml
and Blizzard_OverrideActionBar/OverrideActionBar.xml on the same branch. No Lua
OnUpdate, polling or Combat Log parser is used. The dedicated Swing Timer smoke
checks ownership, concurrent hands, duration delivery, equipment, profile changes,
real media-choice paths, preview isolation, number-only display and fill direction.
Offline tests do not establish live visuals, taint safety or measured performance.

Optional extras: the off-hand lane draws the off-hand timer as a strip in the
main-hand bar in the off-hand colour; out of reach, a bar takes its reach colour
and fades to its reach opacity; a queued next-swing attack (Heroic Strike,
Cleave, Maul, Raptor Strike, matched by spell name so every rank counts) shows
its icon beside the main-hand bar and tints the border, and with the cue text on
the bar's title names it (the spell name, or the player's own text per attack).
Settings saved under the former extras names move to the current ones once.
C_SwingTimer.EnableRangeCheck
is one switch per hand shared with Blizzard's bars, which drop it when their
CVar turns off, so the module re-asserts it after that CVar changes and on every
apply. A target change only re-reads the range of checked hands, a haste proc
does nothing unless a weapon was equipped or removed, and spell-state events are
registered only for classes with next-swing attacks.

### Shared Runtime media, fonts and colors

`Runtime/MSUF_Fonts.lua` loads immediately after the Kernel library adapter,
before State. It owns the catalogue, key/path normalization, resolution,
application caches and diagnostics, plus the active-profile font/flags getters.
Defaults and Profiles share this path; registry availability remains a forward
provider resolved at use time. No profile is read while the font owner loads.
`Runtime/MSUF_FontRegistry.lua` owns availability metadata and preview objects.
The Kernel adapter retains library registration and its one coalesced media callback.

`Runtime/MSUF_MediaRuntime.lua` owns built-in statusbar media and its resolution
cache. Castbars consume that service and retain castbar styling/revision caches.
`Runtime/MSUF_Colors.lua` owns palette and font/color resolution, including the
existing public color APIs. Public font/media globals, Host API and Suite readers
retain their names; the old Castbars.Core and Castbars font slots are aliases.
Ownership and real-client-graph parity probes cover these boundaries without
replacing their providers. Live font metrics, textures and profile-switch rendering
still require client verification.

Colors retains two established palette contracts within this single owner.
The namespace palette and configured-font/object/RGB accessors keep the original
default RGB values and namespace-table mutation behavior. The existing public
`MSUF_FONT_COLORS` table is preserved at load; Colors global/castbar and cast-color
palette getters read that public binding on each call, so same-table edits,
missing entries and later table replacement keep their previous effect.
Configured custom RGB wins over palette selection, and complete castbar RGB
wins over the global color. Root-profile or `general` replacement refreshes
the cached Colors profile resolver. These contracts differ when another addon
provides a public palette: using the configured-font getter for the Colors
global getter changed effective colors, so the original Colors resolution
body is retained. The lifecycle smoke exercises actual shipped getters on every
client; optional immutable-base comparison checks the old owner directly.

### Unit-frame region visibility cache

A region's shown state is cached once, in `region._msufShown`: true or false, and
nil when unknown so the next write repaints. Every unit-frame module that caches a
region's visibility shares that field: Apply, the status runtime and AFK timer,
the load-conditions fallback, the prediction over-absorb glow, group corner
indicators and visuals, pet happiness, and the text, bar, portrait and power
regions that already used it. `Apply.ShownPlain` is the trusted entry for plain
Lua flags and `Apply.Invalidate` clears the field. `Apply.Shown` stays public and
also takes a secret flag, which reaches the native region as it is and is never
cached; a plain call through it costs one extra `issecretvalue` query, so core
callers use `ShownPlain`. The threat text keeps `_msufThreatShown` because its
background plate follows that flag. The rounded-surface interval and art tables,
border source state and group target and focus verdicts are semantic state, not
region caches. A direct native Show or Hide must reset the field. The region
visibility smokes pin the cross-owner behavior and the parent's per-operation cost.

## Bundled media and legacy profile selections

State owns legacy bar-texture names at the migrate-to-bind boundary and repairs
activated, copied and imported profiles before runtime apply. The State700
normalizer also repairs media names on previously stamped profiles. Bundled
media registration retains its asset/readiness work and schedules no separate
profile-migration timer. The texture migration phase smoke pins all nine legacy,
current and third-party selections on each supported client, including later
activation and every import boundary before late media registration.

The five Menu2 pilot pages preserve legacy UI fallbacks through the compatibility
owner documented in docs/MENU_CONTROL_SCHEMA.md. It does not seed saved keys or
normalize a profile. Extra-aura callbacks bind shared defaults to scalars at load;
their exact pre-schema VM/native/allocation budgets remain unchanged. Real
control declarations, sparse/imported reads and profile switches have focused
guards; live layout and combat/taint checks remain client-side validation.

### Unit-frame responsibility owners

The Status, Text and Factory engine files at the Lua local ceiling are split into eleven
provider files that load before their coordinators in every client graph. Moved bodies keep
their statements and upvalue captures. Budget-sensitive bodies stay in the coordinator: the
over-absorb painter, the Boss number updater and every optional-callable probe with its
captured local `type`. Ownership, binding model and the cost pins are in
`docs/uf-responsibility-split.md`; relocated rationale comments are in
`docs/uf-responsibility-notes.md`.

Unit-frame preview request ownership, early dependency order, family handoff and
the retained core animation boundary are documented in [docs/PREVIEW_REQUESTS.md](docs/PREVIEW_REQUESTS.md).

Profile defaults remain materialised on every client. The typed factory/repair catalog in
`tools/fixtures/defaults/schema.lua` verifies the existing providers; certified scalar
defaults are omitted only at terminal persistence. See `docs/PROFILE_STORAGE.md`.

Cold settings providers publish the internal EventBus `CONFIG_APPLIED` signal.
The Options unit preview subscribes while its visible page or floating owner is
active, and releases that subscription on hide or owner cancellation. Public
refresh functions retain their identities across preview lifecycle changes;
the Options addon no longer scans or replaces them. The existing refresh
delays and combat predicate remain in the preview API. Explicit requests still
defer to combat exit, while settings notifications remain suppressed in combat.
