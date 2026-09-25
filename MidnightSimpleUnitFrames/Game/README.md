# MSUF client layout

This directory is the client boundary for MSUF, following ElvUI's layout:
`Game/Shared` plus one folder per client family or flavor that needs its own
source. `Classic`, `Vanilla`, `TBC` and `Mists` belong to the Classic family;
`Forever` is Mainline-family source and loads in the Mainline build.

- `Shared` contains bootstrap code that must behave identically everywhere,
  plus the modules that Classic clients and the Mainline build both load
  (`Shared/UnitFrames/MSUF_UF_PetHappiness.lua` and
  `Shared/UnitFrames/MSUF_UF_ThreatText.lua`: Classic Era, TBC and WoW
  Forever). Such a module checks its `MSUF.Client` fact first and returns at
  once where the client has no such feature.
- `Classic` contains implementations shared by Vanilla, TBC, and Mists.
- `Vanilla`, `TBC`, and `Mists` contain the loader manifests, adapters and data
  selected only by that client's suffixed TOC.
- `Forever` contains what only WoW Forever needs inside the Mainline build: the
  curated aura datasets, the spell name catalog for rank broadening, and the
  character names option (first name, surname or both). Every file returns at
  once on any other client.
- Mainline has no folder here. `MidnightSimpleUnitFrames_Mainline.toc` loads
  the Retail tree plus `Shared` and `Forever`, and never loads `Classic`,
  `Vanilla`, `TBC`, or `Mists`.

Client-only code that has no Retail counterpart belongs here. A Classic
difference inside a Retail file is not copied here: the Retail-named file
carries it as a reviewed override hunk that branches on an `MSUF.Client` fact
resolved once when the file loads (a file-level upvalue such as
`IS_CLASSIC_FAMILY`), never on a client check per event, so a shared hot path
pays one upvalue test at most and Mainline never enters the Classic branch.
The former whole-file Classic copies of Retail files (owned shadows) were
collapsed that way on 2026-09-19, thirteen of fourteen; the one row left in
`tools/classic-owned-shadows.tsv` is `Classic/State/MSUF_Defaults.lua`. Do not
add a shadow. Vanilla, TBC, and Mists include implementations from `Classic`, but
they keep separate loader manifests so their contracts can diverge without
copying the backend.

Vanilla, TBC, and Mists ship no aura alias catalog: their backend reads aura
payloads and matches ranked and cast-versus-aura IDs by aura name at runtime.
The Mainline core TOC places the Retail and Forever catalogs (common part plus
client-language partition) between `MSUF_UFCore_Elements.xml` and
`MSUF_UFCore_Auras.xml`. Native TOC `AllowLoadTextLocale` conditions skip
inactive alias partitions before Lua parsing, and `[ExcludeLoadGameType
camelot]` keeps the Retail catalog off WoW Forever; the Forever files keep
their runtime guard. Menu translations remain independent: all twelve still
load for the saved menu language. Gate/package inventories include all locale
and game-type branches, while boot simulations filter by client locale and
game type.

`tools/classic-client-matrix.tsv` maps each client to the branch of the local
Blizzard UI source mirror (`_local_workflows/references/wow-ui-source`) that
its contracts are checked against:

- `upstream/classic_era`: Vanilla (Classic Era)
- `upstream/classic_anniversary`: TBC Classic
- `upstream/classic`: Mists Classic
- `upstream/live`: Mainline

The ptr branches (`upstream/ptr`, `upstream/ptr2`, `upstream/classic_ptr`,
`upstream/classic_era_ptr`) are drift sentinels only. The source audit checks
their aura API contracts when they exist; no client is packaged from them.

Warning: `Blizzard_APIDocumentationGenerated` is nearly identical across the
Classic branches, so it proves nothing about whether one flavor has an API.
Look for a call site in a file that the flavor's TOC actually loads, checking
its `AllowLoadGameType` tags the way `tools/audit-classic-ui-source.ps1` does,
or follow the client gates ElvUI applies.

Game modes (`MSUF.Client.GameMode`, such as Standard or Plunderstorm) get no
folder here. A Mainline game mode shares the Mainline build, and a folder is
only warranted once its data really diverges. WoW Forever is that case: it
runs the Mainline build with a Classic Era spell database, so its aura data
lives in `Forever` while its code stays in the Retail tree. Code branches on
`MSUF.Client` facts and capabilities, never on client names.

## Forever data validation: 1.60.1.70009

Checked on 2026-09-25: the Forever UI source changed Pet Happiness artwork
and repaired secure group snippet initialization. All eleven 70009 SpellName
exports changed their alias groups, and the Forever catalog was regenerated
from them. The curated aura IDs retain their expected names. See
[the validation notes](../../CLASSIC_PROTOTYPE.md#forever-data-validation-160170009)
and `.github/forever-client-data-validation.json` for scope and source hashes.

Class-resource UI follows `Client.SupportsClassResource` and
`Client.SupportsClassResourceSetting`, matching the active `CPClient` provider.
Era/TBC/Forever offer only Rogue and Cat Form combo-point previews; Mists uses
its own resources and counts. Search and Class Power colors apply the same
gates, and older clients do not bind or query charged-combo updates. Unsupported
profile settings are retained so shared profiles keep their data across clients.

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
