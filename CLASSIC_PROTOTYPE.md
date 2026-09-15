# MSUF Classic 6.5 Alpha Build

This local branch was created from Retail `main` commit `7cf4e711`. Every
Retail sync commit records the Retail commit it ported in a `Retail-Source:`
trailer. The current one is `ace807b7`; `git log -1 --grep=Retail-Source`
shows the latest. The public 6.5 Alpha line combines the complete responsive
texture-layer design system, 100 editable looks, 50 original assets,
class-fantasy recipes, modular no-portrait layouts and Edge Softness with the
current Retail feature and bug-fix set. It follows the same
multi-client packaging shape used by ElvUI: client-suffixed TOCs plus a real
`Game/Shared`, `Game/Classic`, `Game/Vanilla`, `Game/TBC`, and `Game/Mists`
source boundary. Mainline has no `Game` folder of its own; it loads the Retail
tree plus `Game/Shared`.

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
fully place. It also sets the `MSUF.Retail`, `MSUF.Vanilla`, `MSUF.Era`,
`MSUF.Mists`, `MSUF.TBC`, and `MSUF.Classic` shortcuts, and it builds no API
aliases. The Classic TOCs load `Game/Classic/Initialize.lua` after it and
before the bootstrap. That file builds the local adapters `MSUF.Compat.AddOns`,
`MSUF.Compat.Spell`, and `MSUF.Compat.SpellBook`: a native `C_*` function wins,
a legacy global fills the gap, and no Blizzard `C_*` table is ever written.
The Classic TOCs additionally load `Game/Classic/BlizzardFrames.lua`, which owns
Classic-only Blizzard frame suppression such as the target-anchored
`ComboFrame` while MSUF's replacement class resource is active.

Auras use a client-selected backend. Mainline loads the Retail Auras3 runtime
unchanged, including its native 12.1 `Blizzard_AuraContainer` path. The
Vanilla, TBC, and Mists manifests (`Game/<Flavor>/UnitFrames.xml`) load
`Game/Classic/Auras/MSUF_Auras3_Compile.lua` immediately before
`Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua`. The compile file owns lane
config compilation: lane specs, filters, blacklist hashes, dispel visuals and
sort comparators. The runtime file owns `UNIT_AURA`, uses the Classic
`C_UnitAuras`/`AuraUtil` scan contract, and reuses MSUF's pooled aura buttons.
Its lifecycle binds the factory's
`MSUFUnitKey`/`unitKey` to the legacy backend unit field and resolves tooltip
aura indices when the AuraInstanceID tooltip APIs do not exist.

Every Classic flavor ships a generated SpellName alias catalog under
`Game/<Flavor>/Auras/AliasData` (Vanilla 1.15.9.68940, TBC 2.5.6.68941, Mists
5.5.4.68806; regenerate with
`.github/scripts/generate_classic_aura_alias_catalog.py` from wago.tools
`SpellName` CSV exports of the flavor build, one `<locale>/SpellName.csv` per
locale). The flavor manifests load the catalog right after
`Game/Classic/Auras/MSUF_Auras3_DataShared.lua` and then the shared Retail resolver
`Auras3/MSUF_Auras3_AuraAliases.lua`. `A3.AddAuraSpellIDAndAliases` resolves
every ID it expands against that catalog, so curated DoT/defensive lists, group
spell indicators and user whitelists match all same-name IDs: spell ranks on
Vanilla/TBC and cast-versus-aura ID drift on Mists, the way WeakAuras matches
auras by name. Unlike Retail, Classic deliberately broadens curated data too.
`tools/tests/classic_aura_alias_catalog_smoke.lua` pins the manifests, the
build headers and representative expansions per flavor.

`Game/Shared/Initialize.lua` also exposes `MSUF.Client.SupportsUnit(unit)`:
Classic Era has no focus, boss or arena units and TBC has no boss units. The
Classic unit config compiles those units disabled, the Classic Unit page drops
them from its unit pills and copy targets, and the Classic-era interrupt-ready
tables in `Castbars/MSUF_InterruptReady.lua` only name spells that exist on
each client. Blizzard's LoadOnDemand `Blizzard_ArenaUI` frames are suppressed
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
unit lane, and turning Only mine on clears it. Raw Retail filter tokens are
compiled once into a Classic-safe plan. Vanilla/Mists/TBC scan only with tokens
their AuraUtil accepts; `IMPORTANT`, `DISPELLABLE`, `BOSS`, `STEALABLE`,
`!PLAYER`, and related requirements use equivalent AuraData/C_Spell
predicates. No polling is added.

Class resources have separate providers per client. Classic loads the shared
`Game/Classic/ClassPower` core (constants, modes, core and controller) plus
`Game/<Flavor>/ClassPower.lua`. Mists maps
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
  `Game/Shared/Initialize.lua`, `State/MSUF_AuraDefaults.lua`, the three
  Defaults shells (`State/Defaults/MSUF_Defaults_Shell.lua`,
  `State/Defaults/MSUF_Defaults_Bars.lua`,
  `State/Defaults/MSUF_Defaults_Units.lua`),
  `Auras3/MSUF_Auras3_IconShape.lua`, the Options file
  `Shell/Menu2/MSUF_Menu2_ColorPicker.lua`, and the four Arena modules
  (`Castbars/MSUF_ArenaCastbars.lua`, `Castbars/MSUF_ArenaCastbars_Preview.lua`,
  `Features/Gameplay/MSUF_Feature_ArenaMatch.lua`,
  `Features/Gameplay/MSUF_Feature_ArenaTrinkets.lua`). No other owned file may
  enter Mainline, and it never parses `Game/Classic`, `Game/Vanilla`,
  `Game/Mists`, or `Game/TBC`.
- Vanilla, Mists, and TBC load their own aura datasets, group indicator datasets,
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

### Owned shadows

Some `O` files are whole-file Classic copies of a Retail file; for example
`Game/Classic/ClassPower/MSUF_CP_Core.lua` shadows `ClassPower/MSUF_CP_Core.lua`.
`tools/classic-owned-shadows.tsv` records each one as a sorted
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

`-SelfContained` is the subset CI runs (`.github/workflows/release-classic.yml`):
syntax, load order, error paths, ownership manifests, flavor load coverage and
the Lua smokes, without Retail parity, override-base or shadow-drift checks and
without the Blizzard UI source audit. It never replaces the full gate.
`-AllowMissingTools` lets a
structure-only run continue without `luac`, `lua` or the UI source mirror; each
step it skips is printed as a `SKIPPED:` line, so a partial run never reads as
a full pass.

Requirements:

- Lua 5.1 `lua` and `luac` first on `PATH`; the gate checks both versions.
- A real Python 3 as `python`; the load-order and error-path checks run first.
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
- `.github/scripts/rounded_border_highlight_smoke.lua`: no argument, or
  `--startup-disabled`.
- No argument: `.github/scripts/rounded_forbidden_mask_owner_smoke.lua`,
  `tools/castbar_refresh_ownership_smoke.lua`, the eight Arena smokes, the four
  v6.04 parity smokes, `tools/tests/classic_unit_availability_smoke.lua`,
  `tools/tests/classic_portrait_gold_smoke.lua` and
  `tools/tests/classic_minimap_click_smoke.lua`.

These run without the driver:

- `.github/scripts/classic_refactor_load_order_smoke.py`: `python`, no argument.
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
- `tools/tests/classic_menu_atlas_smoke.lua`: the root, then a matrix suffix or
  `FutureVanilla`, then optionally `tinted` (the gate runs it for Vanilla) or
  `midnight` (for each Classic suffix).

The health, text and castbar-tint parity smokes also accept a pre-refactor
source root as a second argument. That mode asserts strictly less Lua work than
the baseline, so it fits only a one-off refactor review; the gate passes the
root alone.

Every tracked smoke either runs through `Invoke-GateSmoke` or is listed with a
recorded reason in `$retiredSmokes` in `tools/test-classic-prototype.ps1`.
`Invoke-GateSmoke` records each smoke it starts. After the last smoke the gate
fails on a tracked smoke that neither ran nor is retired, on a retired smoke
that still runs, and on a smoke that ran but is not tracked by git.

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
   flavor: `UnitFrames.xml`, `UnitFrames/GroupFrames.xml`, `ClassPower.lua`,
   the aura data under `Auras` (including the generated `AliasData` catalog)
   and the group indicator data under `UnitFrames/Group`.
4. In `Game/Shared/Initialize.lua`, recognise the flavor by its project global
   and its lowercased `X-MSUF-Client` token, set its `Client` flags, and add an
   `UNSUPPORTED_UNITS_BY_FLAVOR` row for every unit token the client lacks.
5. Extend the per-flavor spec tables in the smokes that key by flavor, for
   example `tools/tests/classic_client_bootstrap_smoke.lua` and
   `tools/tests/classic_aura_alias_catalog_smoke.lua`. The gate derives a
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
