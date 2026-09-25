# MSUF Classic 6.5 Alpha Build

This local branch was created from Retail `main` commit `7cf4e711`. Every
Retail sync commit records the Retail commit it ported in a `Retail-Source:`
trailer. The current one is `72c50ac4`; `git log -1 --grep=Retail-Source`
shows the latest. The public 6.5 Alpha line combines the Retail Texture Layer
on every client (Text background, Highlight, and an MSUF textures button for
the 50 original assets) with the current Retail feature and bug-fix set. It
follows the same
multi-client packaging shape used by ElvUI: client-suffixed TOCs plus a real
`Game/Shared`, `Game/Classic`, `Game/Vanilla`, `Game/TBC`, `Game/Mists`, and
`Game/Forever` source boundary. There is no `Game/Mainline` folder: the Mainline
build loads the Retail tree plus `Game/Shared` and `Game/Forever`, and never
`Game/Classic`, `Game/Vanilla`, `Game/TBC`, or `Game/Mists`.
`MidnightSimpleUnitFrames_Mainline.toc` names 13 `Game\Forever\...` paths
directly (the 12 alias catalog partitions and `Game\Forever\ClassPower.lua`) and
2 `Game\Shared\...` paths; `MSUF_UFCore_Elements.xml` adds the two remaining
`Game/Forever` files and the two shared unit-frame modules, so the resolved
Mainline graph holds 15 `Game/Forever` and 4 `Game/Shared` files. Every
`Game/Forever` file returns at once on a client that is not WoW Forever, and the
two shared unit-frame modules return at once where their `MSUF.Client`
capability is false, so Midnight behaviour is unchanged.

`tools/classic-client-matrix.tsv` is the authoritative list of supported
clients: TOC suffixes, interface numbers, `X-MSUF-Client` tokens, project
globals, game types, Blizzard UI source mirror branches and CurseForge game
version names. The gate, the UI source audit, the release scripts and the
CurseForge workflows all read it, and it wins wherever this summary disagrees:

- Classic Era: `11509`, suffix `_Vanilla.toc`
- Mists of Pandaria Classic: `50504`, suffix `_Mists.toc`
- The Burning Crusade Classic: `20506`, suffix `_TBC.toc`
- Retail remains available for comparison through `_Mainline.toc`

Every core TOC loads `Game/Shared/Initialize.lua` before `Kernel/MSUF_Bootstrap.lua`.
It places the client by its project ID and its `X-MSUF-Client` TOC tag and
builds `MSUF.Client`: the flavor flags, `SupportsEvent`, `SupportsUnit`,
`SupportsGroupKind`, and a one-line login diagnostic for a client it cannot
fully place, and it builds no API aliases. `MSUF.Client` is the single client
surface: the short `MSUF.Retail`, `MSUF.Vanilla`, `MSUF.Era`, `MSUF.Mists`,
`MSUF.TBC`, `MSUF.Classic` and `MSUF.Forever` shortcuts and the
`MSUF.Compat.Client` bridge were removed on 2026-09-19 because no reader in any
of the three addons used them (`Game/Shared/Initialize.lua:512-515`); do not
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
`Game/Classic/Auras/MSUF_Auras3_Compile.lua` immediately before
`Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua`. The compile file owns lane
config compilation: lane specs, filters, blacklist hashes, dispel visuals and
sort comparators. The runtime file owns `UNIT_AURA`, uses the Classic
`C_UnitAuras`/`AuraUtil` scan contract, and reuses MSUF's pooled aura buttons.
Its lifecycle binds the factory's
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
parsing, and the Retail catalog lines also carry `[ExcludeLoadGameType
camelot]`, so WoW Forever parses only its own catalog (about 1.4 MB less at
every login). The Forever files keep their `MSUF.Client.IsForever` runtime
guard for every other Mainline game type. Blizzard's own Forever TOCs stack
conditions on one line the same way (`[AllowLoadTextLocale ruRU] [AllowLoad
glue] [ExcludeLoadGameType camelot]`); a client that ignored the game-type
condition would simply load both catalogs, as before. Regenerate the Forever
catalog with `.github/scripts/generate_classic_aura_alias_catalog.py` from
wago.tools `SpellName` CSV exports, one `<locale>/SpellName.csv` per locale.
`enGB` shares `enUS` and `ptPT` shares `ptBR`. All twelve menu translations
still load because saved menu language is independent of client language.
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
the `UnitFrames/Engine/MSUF_UF_Config.lua` override gated on
`MSUF.Client.Family`), the Unit page (the Retail-named
`Pages/MSUF_Menu2_Unit.lua`, which every client loads) drops them from its unit
pills and copy targets there, and the Classic-era interrupt-ready tables in
`Castbars/MSUF_InterruptReady.lua` only name spells that exist on each client.
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

Class resources have separate providers per client. Every client runs the
Retail-named ClassPower core (`ClassPower/MSUF_CP_Constants.lua`,
`MSUF_CP_Modes.lua`, `MSUF_CP_Core.lua` and `MSUF_CP_Controller.lua`, all
reviewed overrides). Its Classic behaviour sits in small hunks gated on
`MSUF.Client.IsClassic`, read once per file, so Mainline runs exactly the
Retail statements. The Classic TOCs add `Game/<Flavor>/ClassPower.lua` and
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

- Mainline preserves every Core, Options, and Assistant Retail Lua path in its
  original order. Its only additional Lua loads are exactly the Classic-owned
  files listed in `$mainlineOwnedLuaExtras` in
  `tools/test-classic-prototype.ps1`, each loaded once:
  `Game/Shared/Initialize.lua`,
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
  `Auras3/MSUF_Auras3_IconShape.lua`, the Options files
  `Shell/Menu2/MSUF_Menu2_ColorPicker.lua` and
  `Shell/Menu2/MSUF_Menu2_Theme_Forever.lua` (Classic Glass and Midnight menu
  presets, selectable on every client; only Forever defaults to Classic Glass), the WoW Forever aura
  data (`Game/Forever/Auras/MSUF_Auras3_ForeverData.lua` and the thirteen
  `Game/Forever/Auras/AliasData` files, which return at once on every other
  client), and the four Arena modules
  (`Castbars/MSUF_ArenaCastbars.lua`, `Castbars/MSUF_ArenaCastbars_Preview.lua`,
  `Features/Gameplay/MSUF_Feature_ArenaMatch.lua`,
  `Features/Gameplay/MSUF_Feature_ArenaTrinkets.lua`). No other owned file may
  enter Mainline, and it never parses `Game/Classic`, `Game/Vanilla`,
  `Game/Mists`, or `Game/TBC`. A module that Classic clients and Mainline both
  need therefore lives in `Game/Shared`, as the pet happiness module does:
  Vanilla and TBC load it from their own manifests, Mainline from
  `MSUF_UFCore_Elements.xml`, and
  `tools/classic-flavor-load-exclusions.tsv` keeps it out of Mists.
- Vanilla, Mists, and TBC load their own aura datasets, group indicator datasets,
  ClassPower providers, Blizzard-frame ownership, and compatibility adapters.
- Compatibility code never assigns to Blizzard `C_*` namespace tables. This is
  an enforced taint gate because doing so can later poison secure action-button
  clicks and surface as `ADDON_ACTION_FORBIDDEN` at `UseAction()`.
- Options and Assistant keep their original zero-idle LoadOnDemand architecture
  and have suffix TOCs for every supported client.

## Client model: family and game mode

`Game/Shared/Initialize.lua` describes a client on three levels, and code keys
on these facts instead of repeating project checks:

- `Client.Family` is the code family, `Mainline` or `Classic` (`Unknown` when
  detection cannot place the client). It decides which build runs: Mainline
  loads the Retail tree plus `Game/Shared` and `Game/Forever`, Classic adds
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
project ID the client reports; a Classic `X-MSUF-Client` tag still wins. Forever
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
("Background") keeps it readable on any bar color. The party and raid frames show
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
Forever-only behaviour keys on `Client.IsForever`, read once at file load.
`Client.AddonVersion` is the MSUF version of the running client, also read once
at file load; every version display, the version check and the analytics read
that field instead of asking the TOC again. Each client TOC owns its
`## Version`, so clients can follow their own patch cycle: Midnight keeps
Retail's version in the `_Mainline.toc` files and the Classic TOCs carry the
`VERSION` file's release. WoW Forever shares the Mainline TOCs, so the core
Mainline TOC names its version in `## X-MSUF-Version-Forever`, which the gate
and the release-line contract hold equal to `VERSION`. A game mode that shares
a TOC later gets its own `X-MSUF-Version-<Mode>` field the same way.
So that Blizzard's AddOn list shows the right number too, each `_Mainline.toc`
carries two conditioned lines, `## Version: <Retail> [AllowLoadGameType standard]`
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
  local IS_FOREVER = MSUF.Client ~= nil and MSUF.Client.IsForever == true
  ```

  `MSUF.Client ~= nil and MSUF.Client.<Fact> == true`, UPPER_SNAKE name. The
  `~= nil` guard is for harnesses that load one file without
  `Game/Shared/Initialize.lua`; on a real client `MSUF.Client` always exists.

- An inline condition, when one decision point needs the fact:

  ```lua
  if MSUF.Client and MSUF.Client.SupportsThreatText == true then
  ```

- `local Client = MSUF.Client` when a file reads three or more facts or calls
  the capability functions (`SupportsEvent`, `SupportsUnit`,
  `SupportsGroupKind`, `SupportsClassResource`, `IsGameRuleActive`). It is the
  companion of the two forms above, not a third dialect.

A second guard is not repeated inside a block an enclosing constant already
gated: `MSUF_UF_Config.lua:899` reads `MSUF.Client.SupportsEvent` bare inside
`if IS_CLASSIC_FAMILY then`, and `MSUF_Menu2_Unit.lua:30` reads
`MSUF.Client.SupportsUnit` bare behind `DROP_UNSUPPORTED_UNITS`. Both are
reachable only when `MSUF.Client ~= nil`, so the bare read is correct there.

Pick the fact that names the question. `Client.Family` answers "which build
runs" and is what a Classic hunk in a Retail-named file gates on
(`IS_CLASSIC_FAMILY`); `Client.IsVanilla`/`IsTBC`/`IsMists` name one flavor;
a `Supports*`/`Has*` capability is better than either wherever one exists,
because it survives a new client. `Client.Family == "Classic"` and
`Client.IsClassic` are equivalent by construction
(`Game/Shared/Initialize.lua:82-88,133`) but are not interchangeable in intent,
so neither is rewritten into the other.

Two checks keep the model honest. `tools/tests/classic_project_id_reads_smoke.lua`
limits raw `WOW_PROJECT_ID` reads in Classic-owned and override files of all
three addons (core, Options and Assistant) to a reviewed allowlist; that
allowlist has been empty since 2026-09-19 (`ALLOWED = {}` at line 99), so
outside `Game/Shared/Initialize.lua` no raw project-ID read is left.
`tools/audit-classic-ui-source.ps1` pins every TOC
game-type token and every `C_GameRules` `Is*` function on the mirror branches,
so a refreshed mirror that brings a new client or game mode fails the full gate
until the client model handles it.

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

`tools/test-classic-prototype.ps1` validates every addon TOC for every client in
the matrix, recursive XML load graphs, Lua 5.1 syntax, client bootstrap,
Blizzard resource ownership,
ClassPower providers, legacy cast/channel tuples, native prediction events,
Classic aura compilation/rendering/filter plans, group indicator datasets,
forbidden Blizzard namespace writes, and the zero-overhead Retail load graph.
The parity gate requires the current Retail Git checkout whenever reviewed
overrides exist. It divides the addon inventory into three disjoint classes:

- Normal mapped Retail paths (`R minus P`) remain byte-identical to the current
  Retail Git blobs.
- `tools/classic-retail-overrides.tsv` is `P`: each sorted, unique
  `path<TAB>Retail-base-blob` row permits Classic to differ at that existing
  Retail path only while the recorded base blob still equals current Retail.
- `tools/classic-owned-addon-paths.txt` is `O`: sorted, unique additive files
  owned entirely by Classic. `O` cannot collide with `R` or `P`.

The complete addon inventory must equal `R union O`;
`P` is a strict subset of `R`, not another source of files. Mainline preserves
the Retail Lua path sequence, accepts hash differences only at `P`, and accepts
additional Lua only for the declared shared/Arena additions in `O`. This
document records no counts: every gate run prints the live numbers on its
`Retail exact paths:`, `Retail override paths:`, `Classic-owned paths:`,
`Classic-owned shadows:`, `Classic flavor load coverage:`, and `Smoke inventory:`
lines. When the local UI mirror is present it also runs
`tools/audit-classic-ui-source.ps1` against the relevant Blizzard client branches.

Both manifests and every referenced Classic file must be tracked, normalized,
ordinal-sorted, unique without case collisions, and mutually disjoint. Missing
or malformed manifests, a stale `P` base blob, an undeclared path, ownership
collision, mirrored-byte drift, Mainline order/load leakage, or final inventory
drift fails closed before an automated commit or push. The sync also protects
owned and overridden bytes across copying and the complete existing full gate.

When Retail changes a path in `P`, do not merely replace its recorded blob.
Review the old-to-new Retail delta, manually rebase that delta into the Classic
override without losing its intentional behavior, run the ownership suite and
the complete Classic gate, and only then update the TSV blob. If the divergence
is no longer required, remove the `P` row and restore normal byte-identical
mirroring. A new Retail path colliding with `O` likewise requires an explicit
ownership decision and reviewed rebase; it is never resolved automatically.

### Global name resolution

`tools/tests/unresolved_global_reads_smoke.py` compiles every Lua file of the
three addons with `luac -l -p` and reads the GETGLOBAL and SETGLOBAL
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

### Owned shadows

A shadow is an `O` file that is a whole-file Classic copy of a Retail file; a
Retail sync never touches it, so Retail fixes silently stop reaching Classic.
Do not add one. A Classic difference in a Retail file belongs in that file as
a reviewed `P` override whose Classic hunks branch on `MSUF.Client` facts read
once when the file loads (for example `IS_CLASSIC_FAMILY` in
`UnitFrames/Engine/MSUF_UF_Config.lua`): every Retail sync then rebases them,
and Mainline never enters them. Classic-only code without a Retail
counterpart stays an ordinary owned file (for example
`Game/Classic/ClassPower/MSUF_CP_ClassicRouting.lua`). Every shadow has been
collapsed this way: the last one, `Game/Classic/State/MSUF_Defaults.lua` for
`State/MSUF_Defaults.lua`, went on 2026-09-20, so every client now loads one
Defaults file and a Retail defaults fix can no longer miss Classic.
`tools/classic-owned-shadows.tsv` is therefore empty, and the rules below stay
in force for a shadow that is ever added again: each one is a sorted
`owned-path<TAB>Retail-path<TAB>Retail-base-blob` row. Every owned path must be
declared in `O`, its Retail counterpart must not be, and a malformed manifest
fails the gate. Drift is reported by the gate, not enforced: a run with a
Retail reference lists every shadow whose Retail counterpart changed or no
longer exists under its `Classic-owned shadows:` line, and still passes. The
recorded Retail blobs were taken on 2026-09-14 from Retail-Source `ace807b7`.
They mark where drift tracking starts and do not certify that earlier Retail
changes had been ported into the shadows.

Rebase rule: when a shadow's Retail counterpart changes, review the old-to-new
Retail delta, port it into the shadow or consciously reject it, run the
complete Classic gate, and only then update the recorded blob. When the
counterpart is removed, decide whether the shadow is still needed and update or
remove its row. Never refresh a recorded blob without that review.

The manifest deliberately retains the 48 `Media/Shapes` files plus
`Runtime/MSUF_UIThemeBridge.lua` and `Shell/Menu2/MSUF_Menu2_ThemeSkin.lua` from the old
MidnightSkin experiment. Their former canonical loader/consumer wiring no
longer exists, so they are preserved historical source/assets, not claimed as
runtime-reachable. Restoring or retiring that feature is a separate explicit
decision.

### Flavor load coverage

Classic flavors load hand-kept copies of several Retail manifests, so a Lua
file Retail adds to one of them could otherwise never load on Classic while
every other check stays green. The gate resolves the Mainline core and Options
TOC load graphs and, for each Classic flavor in the client matrix, puts every
Mainline Lua path into one of three classes:

- loaded: that flavor's core or Options TOC loads the same path;
- replaced: that flavor loads an owned shadow whose Retail counterpart in
  `tools/classic-owned-shadows.tsv` is the path;
- excluded: `tools/classic-flavor-load-exclusions.tsv` lists the path for that
  flavor with a reason.

Any other path fails the gate with the flavor and the path. The exclusions
file is tracked, starts with the header `RetailPath<TAB>Flavors<TAB>Reason`,
and holds one ordinal-sorted row per Retail path. `Flavors` is `*` for every
Classic flavor, including one added later, or a comma list of matrix suffixes.
Every row must stay needed: it fails as stale when Mainline no longer loads its
path or when a listed flavor loads or replaces it. Each reason says why Classic
does without the file and names the Classic file that takes its place, if any.
The Assistant addon is outside this check. Full and `-SelfContained` runs both
print the totals on the `Classic flavor load coverage:` line.

These are source/runtime-mock gates, not a substitute for logging into every
class/spec on all game clients. Release certification still requires the live
matrix: clean install and migrated profile, combat and reload, every
class-resource owner, cast/channel/interrupt states, aura/filter/tooltip
combination, party/raid secure headers, Options, Assistant, and action-button
taint checks. A source build must not be described as live-certified until that
matrix has actually passed.

## Running the gate and single smokes

Run the full gate from the repository root before a tag or a sync commit,
naming the Git root of a clean Retail checkout at the Retail commit being
mirrored:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-classic-prototype.ps1 -RetailReferenceRoot <clean Retail checkout>
```

No tracked file records that Retail commit: the `Retail-Source:` trailer goes
stale as soon as a later rebase commit moves an override.
`.github/scripts/resolve_classic_retail_source.py` derives it. It walks a Retail
revision's history newest first and prints the newest commit whose addon tree
matches this tree under the gate's rules: an override matches on its recorded
base blob, every other mapped path on its blob, the three TOCs through the
`_Mainline.toc` mapping, and the addon inventory must equal mapped Retail plus
the owned paths. No Retail path may collide with an owned path, compared
without case and folder by folder, and the Retail tree may hold only the three
TOCs and regular, non-executable files. When nothing matches it exits 2 and
names the nearest commit with its mismatching paths:

```powershell
python .github/scripts/resolve_classic_retail_source.py --retail <Retail clone> --retail-rev <Retail main>
```

`-SelfContained` is the subset that needs neither a Retail checkout nor the
mirror: syntax, load order, error paths, ownership manifests, flavor load
coverage and the smokes, without Retail parity, override-base or shadow-drift
checks and without the Blizzard UI source audit. It never replaces the full
gate. `-AllowMissingTools` lets a
structure-only run continue without `luac`, `lua` or the UI source mirror; each
step it skips is printed as a `SKIPPED:` line, so a partial run never reads as
a full pass. `-RequireNoSkippedSteps` turns those lines into a failure, which is
how CI proves a full run really ran everything.

CI runs both. `.github/workflows/classic-gate.yml` has two jobs for every push
and pull request to `classic` that touches the addon folders, `tools/` or
`.github/` (a push that changes only `VERSION` or a document runs neither):
`classic-gate` runs `-SelfContained`, and
`classic-full-gate` makes a blob-less clone of Retail `main` of this repository,
checks out the commit the resolver names, clones `Gethe/wow-ui-source` (depth
1, every branch, no working tree) into `_local_workflows/references/wow-ui-source`
and runs the full gate with the source audit. The audit reads Blizzard's live
branches, so the full job can turn red without any change here; the
self-contained job reads nothing but the commit.

Both full-gate runs are the same steps: they live in the reusable workflow
`.github/workflows/classic-full-gate.yml`, which `classic-gate.yml` and
`release-classic.yml` both call. `release-classic.yml` runs three jobs for a
`classic-v*` tag: `preflight` (tag freshness, CurseForge secret and the
self-contained gate, about a minute), then `classic-full-gate` on the tag, then
`publish-classic`, which packages and uploads only when both are green. The
self-contained subset cannot see a mirrored Retail file that was edited without
an override row, so it is a pre-check, never the only gate on a published
build. The full-gate job passes `-RequireNoSkippedSteps`, which makes the gate
refuse to pass when any of its own steps was skipped: on a runner a missing
Blizzard mirror is otherwise a skip, not a failure, and an unresolvable Retail
reference aborts the release instead of gating against a guess.

Requirements:

- Lua 5.1 `lua` and `luac` first on `PATH`; the gate checks both versions.
- A real Python 3 as `python`. The error-path check runs early; the python
  smokes share the smoke pool with the Lua smokes (without `lua` they run on
  their own, just before the error-path check).
- The Blizzard UI source mirror at `_local_workflows/references/wow-ui-source`
  for the source audit.

A single smoke runs with the repository root as the working directory. Most
run through `.github/scripts/auras3_test_driver.lua`:

```powershell
lua .github/scripts/auras3_test_driver.lua tools/tests/classic_aura_backend_smoke.lua <repository root>
```

Each smoke's `Invoke-GateSmoke` line in the gate is the reference. Driver smokes
take the repository root, except:

- `tools/tests/classic_client_bootstrap_smoke.lua`: a spec name (a matrix
  suffix, `FutureTaggedVanilla`, `FutureProjectVanilla` or `UnknownUntagged`),
  then the root. A `TagOnly<Suffix>` spec, which the gate builds for every
  matrix `X-MSUF-Client` token, takes that token as a third argument.
- `tools/tests/classic_profile_cross_flavor_smoke.lua`: a matrix suffix, then
  the root.
- `tools/tests/classic_aura_render_smoke.lua`: the root, then the paths of
  `Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua`,
  `Game/Classic/Auras/MSUF_Auras3_Features.lua`, `Auras3/MSUF_Auras3_Core.lua`
  and `Game/Classic/Auras/MSUF_Auras3_Visuals.lua`.
- `tools/tests/classic_aura_faction_smoke.lua`: the root, then a Classic
  suffix.
- `.github/scripts/rounded_border_highlight_smoke.lua`: no argument, or
  `--startup-disabled`.
- No argument: `.github/scripts/rounded_forbidden_mask_owner_smoke.lua`,
  `tools/castbar_refresh_ownership_smoke.lua`, the eight Arena smokes, the four
  v6.04 parity smokes, `tools/tests/classic_unit_availability_smoke.lua`,
  `tools/tests/classic_portrait_gold_smoke.lua` and
  `tools/tests/classic_minimap_click_smoke.lua`.

These run without the driver:

- `.github/scripts/classic_refactor_load_order_smoke.py`: `python`, no argument.
- `tools/tests/rebase_classic_overrides_smoke.py`, the self-test of
  `tools/rebase-classic-overrides.py`: `python`, no argument.
- `tools/tests/resolve_classic_retail_source_smoke.py`: `python`, the root.
  Both build throwaway git repositories in the system temp directory; they need
  `git` on `PATH`, no Retail checkout and no network.
- `tools/tests/classic_client_detection_smoke.lua`: the root. Never run it
  through the driver: the driver stubs `issecretvalue`, which hides the missing
  secret-value API case this smoke pins.
- `tools/tests/classic_scheduler_contract_smoke.lua`,
  `tools/tests/classic_texture_layer_contract_smoke.lua`,
  `tools/tests/classic_font_return_smoke.lua`,
  `tools/tests/classic_defaults_refactor_smoke.lua`,
  `tools/tests/classic_range_fade_smoke.lua` and
  `tools/tests/mainline_classpower_ooc_autohide_smoke.lua`: the root.
- `tools/tests/classic_shared_definitions_smoke.lua` and
  `tools/tests/classic_optional_integrations_smoke.lua`: the root, then a matrix
  suffix.
- `tools/tests/classic_classpower_runtime_smoke.lua` and
  `tools/tests/classic_classpower_enabled_smoke.lua`: the root, then a Classic
  suffix.
- `tools/tests/classic_menu_atlas_smoke.lua`: the root, then a matrix suffix,
  `FutureVanilla` or `Forever` (a simulated WoW Forever client), then
  optionally `tinted` or `midnight` (the gate runs both for `Forever`). Every
  shipped client must keep the stock menu; only `Forever` gets Classic Glass.

The four Retail-shared runtime smokes (`health_background_sample_parity_smoke`,
`health_runtime_equivalence_smoke`, `text_runtime_value_parity_smoke` and
`castbar_tint_parity_smoke`) replay a Classic override and its Retail base side
by side. Their rows pass `{root/} {retailRoot/} parity-only`: `{retailRoot/}` is
the Retail reference root, or `-` when there is none, and `parity-only` keeps
every equality assertion (native arguments, order, displayed values, call and
allocation counts) while dropping the strict improvement assertions, which only
fit the one-off refactor review the smokes were written for. A full run
therefore really compares; a self-contained run prints a `SKIPPED baseline
comparison` line per smoke and the gate reports the whole comparison as a
`SKIPPED:` step.

Every tracked smoke either runs through `Invoke-GateSmoke` or is listed with a
recorded reason in `$retiredSmokes` in `tools/test-classic-prototype.ps1`.
`Invoke-GateSmoke` records each smoke it starts. After the last smoke the gate
fails on a tracked smoke that neither ran nor is retired, on a retired smoke
that still runs, and on a smoke that ran but is not tracked by git.

## Regenerating the Menu2 search index

Both `MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex_Data*.lua`
files are generated, never hand-edited. The generator and everything it loads
are tracked, so a clean clone can reproduce both files byte for byte:

| path | role |
| --- | --- |
| `.github/scripts/search_static_index_project.lua` | the generator |
| `tools/assistant_v1_catalog_crosswalk.lua` | the harness that builds every Menu2 page headlessly |
| `tools/AssistantTraining/wow_stubs.lua` | the WoW API stubs the harness runs on |
| `tools/assistant_runtime_manifest_loader.lua` | runtime manifest loader the harness requires |
| `tools/assistant_graphify_inventory.lua` | inventory module the harness requires |
| `.github/scripts/assistant_graphify_setting_dispositions.lua` | disposition ledger the harness loads |

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
so the two index files are also the reference for what the Classic menu builds
(`tools/tests/classic_assistant_control_schema_smoke.py` uses the Classic one).

`MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantControlSchema_Data_Classic.lua`
is NOT generated here: the Retail generator was never ported, so the file is
reviewed snapshot data and says so in its header. The smoke above pins its shape
and its recorded divergence from the built controls, and refuses any tracked
Classic-owned file that claims a generator this repository does not contain.
`tools/assistant_graphify_inventory_data.lua` made the same false claim and was
retired on 2026-09-20: no gate step read it, its generator was never ported, and
about 145 of its 2179 records pointed past the end of the file they named.

## Adding a client flavor

Use only values Blizzard has shipped: a released interface number, TOC suffix
and project ID (`WOW_PROJECT_*` global). Never invent one for an announced but
unreleased client. Checklist:

1. Add a row to `tools/classic-client-matrix.tsv`: suffix, interface list,
   `X-MSUF-Client` token, project global, game type, mirror branch, CurseForge
   game version names and `IsClassic`.
2. Add the three suffixed TOCs (core, Options, Assistant) by following the
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
8. Declare every new addon file in `tools/classic-owned-addon-paths.txt`, track
   it with `git add -f`, and run the full gate.
9. Review `tools/classic-flavor-load-exclusions.tsv`: its `*` rows now cover the
   new flavor as well, and the flavor load coverage check names every Mainline
   Lua path the new flavor neither loads nor replaces.

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
   three `_Mainline.toc` files. The gate already allows the Mainline
   `## Interface` line to differ from Retail.
3. If the client needs its own TOC suffix instead, add a matrix row and the three
   suffixed TOCs. The gate currently accepts exactly one non-Classic client, so
   `tools/test-classic-prototype.ps1` first needs a second Mainline-family client
   in its single-Mainline check, the Retail TOC name mapping, the Mainline load
   graph and the Retail parity targets.
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
