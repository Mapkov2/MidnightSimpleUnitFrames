# Frozen preview render observations

This corpus records the actual legacy preview renderer output at
`3feb8c771f6d2f32d3fd8a475a0134faf40beb4f`. It is a baseline for later scene
migrations, not an assertion that every legacy value is correct. No addon source,
profile corpus, previous golden, renderer, gate implementation or budget changes
are part of this harness.

Each file represents **one preview**. Its `case` contains the explicit config and
state inputs; unspecified settings come from this revision's real profile defaults.
Its `provenance` records the actual loaded build/render function sources and entry
points. `provenance.json` records the base, native mock inputs, generation command,
and source/harness SHA-256 values (LF normalized). `capture.log` is actual capture
output; `fixture-sha256.json` protects the completed fixture inventory and bytes.

## Execution

Use Lua 5.1, Python 3, and the absolute path of this detached checkout:

```powershell
& $LUA51 tools/tests/preview_render_oracle_smoke.lua $ROOT Mainline
& $LUA51 tools/tests/preview_oracle_contract_smoke.lua $ROOT
& $PYTHON tools/tests/preview_oracle_mutation_smoke.py $ROOT
& $PYTHON tools/tests/preview_oracle_corpus_smoke.py $ROOT
```

The first command runs independently for Mainline, Forever, Vanilla, TBC and Mists.
It boots the real core and Options TOC graphs with `menu_core_world.lua`, configures
the actual profile/compiler, and invokes the real legacy builder and refresher.
There is no expected-value painter or source-text comparison. No game installation
or SavedVariables file is read or written.

To reproduce the original capture, use a separate checkout at the exact base with
these harness files and unchanged addon files, and an output directory that does
**not** exist:

```powershell
& $PYTHON tools/tests/preview_oracle_capture.py --root $ROOT --lua $LUA51 --base 3feb8c771f6d2f32d3fd8a475a0134faf40beb4f --output $NEW_CANDIDATE_DIRECTORY
```

Capture refuses a different HEAD, modified addon source, an existing output
directory, or an existing fixture file. Capture never updates this corpus. A
candidate comparison is a separate, explicit review; neither rebasing nor a failed
comparison authorizes replacing expected values. In particular, corrected drift
from subsequent baseline packages needs property-level red/green evidence and a
reason for each accepted change. Historical provenance stays historical.

## Group scene re-baseline

The Options group preview now paints its cell with the engine's group preview scene
(`GF.NewPreviewScene`) instead of its own mock-cell renderer. That is a deliberate change of the
observed structure, so the twenty group fixtures (Party default, Party hidden layers, Party
custom portrait/aura config, Raid default; five clients) were recaptured with the same cases and
inputs. The bytes they replace are in the history of the commit before this re-baseline, and
`evidence/pre-scene-group-sha256.json` records their (LF-normalised) hashes. Everything outside
the cell subtree (the stage, handles, aura lanes, spell indicators, the portrait and status
handles) is unchanged except two handle sizes that follow the stub's constant font height, and on
TBC and Mists the anchor target of the spell-preview edges (the health fill texture is now the
engine's). Inside the cell the roles `group/_health`, `_power`, `_healPred`, `_absorb`,
`_healAbsorb`, `_nameFS`, `_hpCenterFS` and `_cell` keep their names; the cell is a scaled
container, so sizes are the engine's spec sizes with the zoom in `effectiveScale` (a name drawn at
18 with scale 0.864 is drawn at 12 with scale 1.296: the same 15.55), statusbar ranges are the
engine's (health 0..1e6, power/prediction 0..100) and the cell gains the engine's own regions. The
engine text draws names and small texts in the SemiBold face where the old mock drew Regular, and
gives the name the live clip window; the 68 other fixtures are untouched.

## Scope and matrix

| Client | Previews | Conditional coverage |
| --- | ---: | --- |
| Mainline | 20 | Boss, Arena, empowered cast, continuous Shadow resource |
| Forever | 17 | Boss; no Arena or empowered casts |
| Vanilla | 16 | No Boss, Arena or empowered casts |
| TBC | 17 | Arena; no Boss or empowered casts |
| Mists | 18 | Boss and Arena; no empowered casts |

All five clients cover Player default, Target custom size/class portrait/custom
health gradient, Player native 2D portrait, Pet all-status, Player combo resource,
hidden preview layers, a real animation driver tick, Party default, Party custom
portrait/aura config, Raid default, Party hidden layers, normal/channel/interrupted
Castbars page states, and circle/bar combo Class Resources page states. Conditional
rows use the loaded client capabilities. Every case starts a fresh world. Time is
100 (animation also samples 101.25), locale enUS, random seed 1701. Native fixtures
provide explicit stock class RGBs, a 4x4 class-icon UV grid and a fixed standard font.
These are declared test inputs, not measurements of a running game client.
The native portrait case explicitly makes only the mocked player unit exist, so
the real renderer calls SetPortraitTexture rather than its sample-texture fallback.

The Unit collector includes actual owned body regions **and sibling** class power,
portrait, detached power, castbar, status and aura visuals. The Menu2 group stage,
Class Resources stage, and Castbars page row are separate surfaces. Hidden regions
and retained pools participate. Toolbar/window chrome outside those roots stays
under the existing menu UI smokes. The collector never filters a property because
it differs from the fixture.

Observed state includes raw size, anchors/all-points/parent, own and inherited
visibility/alpha/scale, frame levels/strata, texture layers/sublevels, fonts/text,
colors/gradients, texture/atlas/UV/rotation/blend, masks, statusbar min/max/value and
fill texture, backdrop, cooldown/swipe settings, and portrait API arguments. CP,
auras and castbars are observed through their actual constituent native regions.
Opaque native-property stubs fail capture instead of becoming empty values.
Property families follow native object types: a Frame's child `.text`/`.texture`
references are ownership metadata, not painted FontString/Texture properties.
Referenced masks and statusbar fill textures participate even when parented
outside the selected scene tree. Text escaping preserves newlines, carriage
returns, zero bytes, quotes and backslashes when fixtures are loaded again.

## Matching and later migrations

`preview_oracle_regions.lua` is renderer-independent. `Capture(world, roots,
aliases)` returns role-to-property observations, and `Compare(old, new)` returns
all differing property paths. The legacy adapter is `preview_oracle_world.lua`;
case configuration is `preview_oracle_cases.lua`. Future scene adapters must drive
the new actual render entry point with those same inputs and compare each preview
against its own frozen file. Fixture provenance is not compared to the new entry
point, so moving code alone does not fail visual-property parity.

Named roots and owned region fields supply semantic role IDs. Alias matching never
uses memory addresses, source lines or global allocation indices. Anchor references
use the same IDs or explicit host names. Named anchors are keyed by anchor point,
so setter call order is irrelevant; repeated SetPoint replaces that same point.
Ownership metadata is excluded from **naming traversal**, not from observed output.
Unnamed native decorations get a parent-local type ordinal and remain included.
A migration that changes anonymous construction order must explicitly bind those
old semantic roles in its adapter; deleting or ignoring them is not a parity fix.
There is no alias-by-color/position heuristic that could conceal a changed value.
Numbers use twelve significant digits; no pixel rounding or broad tolerances apply.

`preview_oracle_mutation_smoke.py` changes real captured widgets through native
setters and requires an actual comparison failure. It covers color, position,
size, UV, visibility, font, layer, texture, mask, statusbar value, portrait source,
text, alpha and extra regions across all four surface families. Only shown regions
with positive inherited alpha are selected. Captured failure paths are in
`evidence/mutations.log`; `evidence/verification.log` records direct green checks.
The twenty mutation probes run on Mainline; complete fixture replays run on all
five clients.
`evidence/comparator-absent-red.log` records a negative control: an actual size
mutation escaped with the comparison function absent in a disposable wrapper,
and the guard assertion failed. No checked-in check was disabled for that control.
`evidence/serialization-red.log` and `evidence/external-mask-red.log` record the
contract failing before the respective observation fixes; the final contract
passes with both guards. `evidence/ratchet.log` is the direct quality check.
`evidence/native-property-types-red.log` guards the object-type distinction;
`evidence/native-property-normalization.log` proves all 88 role inventories and
every retained native value stayed identical when 139 unsupported cache fields
were excluded. Mutation actions live in `preview_oracle_mutations.lua`, are
loaded only for negative probes, and invoke setters supported by their targets.

## Evidence boundary and gaps

This proves deterministic **offline native setter/anchor-state parity** for these
previews. The shared mocks do not resolve native anchor geometry or rasterize
fonts, atlases, masks, portraits, statusbar fills or model lighting. Native template
creation and texture/atlas replacement semantics are limited to the mock surface.
It does not establish live pixels, GPU behavior, secret values, combat or taint.
It does not systematically compare previews to live engine frames, nor certify
all features or configurations. Existing runtime-rule parity smokes remain needed.

Uncovered examples include every class/spec resource, arbitrary aura configuration,
all rounded/slanted/texture decorators, every portrait shape, group animation,
group additional blocks, Edit Mode on-screen group scenes, all unit scopes,
all castbar scopes/types/options, localization, solo/focus/drag interactions and
combat lifecycle. No EventBus, aura consolidation or scene implementation is here.
