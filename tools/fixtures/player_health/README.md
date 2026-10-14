The visual oracle is the byte-exact CRLF PlayerHP builder from reviewed main
`9c29a35a48d661912c64535bb221eec39da0d522`. Its SHA-256 is
`faea3a395de124bb786d2b8cbd9d4b9b3d2d8a0cadde0defcd2b631e70da6565`.
It is a test fixture, never an addon load entry. Do not regenerate it to make
a parity assertion pass.

`player_health_element_parity_smoke.lua` executes the old builder and current
UF element with real shared shape, bars, text, layer and visibility providers.
It compares actual geometry, textures, color channels, text, font/slot layout,
parents, scales and native secret sinks across five client families. Lifecycle
and provider smokes exercise the actual controller, UF attachment, optimized
dispatch identities, hidden/disabled/detached player frame, profile/font/scale,
CDM anchoring, event-edge combat refusal and deferred creation/teardown.
`uf_scoped_route_plans_smoke.lua` additionally verifies scope isolation,
immutable mutable-provider snapshots, private updates, reentrant compilation,
shared closure identities and detach against the real UF engine.

`player_health_element_cost_smoke.lua <root> measure` measures the registered
dispatcher in either the original or current source tree. The exact baseline
vectors are unchanged/changing/max/secret: 228.54/744.54/733.54/562.54 VM,
3/5/4/7 counted health/class/percent APIs and native writes, and
0/0.103/0.059/0 bytes per event. Every allocation vector is the minimum of two
samples. The tiny changing-text allocation is shared string interning, not a
new per-event table. No limit includes a margin. The normal smoke enforces
each component independently. These fixtures establish offline source/parity
and cost contracts, not live WoW rendering, combat ordering or taint safety.

`player_health_registered_delivery_smoke.lua` discovers every frame registered
for player health in the real CP/UF fixture and sums the full callbacks, with
empty-call subtraction. It enforces the untouched `9c29a35a` non-lite bound of
187 VM instructions and zero allocation minima on all five clients. The frozen
pre-correction source costs 193; consumer-based CP registration brings it to
175. This supplements the isolated host/painter vectors above.

`classpower_health_registration_smoke.lua` drives every supported class across
four spec indices, lite/non-lite, PHP on/off and CP on/off. It checks each actual
mode descriptor and health/max/modifier registration, native consumer reads,
structural spec transitions, Player frame independence and PHP hide/reshow.
Mainline Brewmaster consumes health through Stagger; Mists Monk uses Chi and
does not consume health. Other descriptors have no health dependency. The
non-lite policy keeps health events only for an active CP consumer; the UF
PlayerHP host and ResourceVisibility retain their own subscriptions.

Controller section commentary moved out of the startup source:

> Guard: only load once.

> The player-frame resolver is owned by ClassPower/MSUF_CP_Core.lua, which
> the TOC loads before this file.

> Perf locals (eliminate global lookups in hot paths)

> APIs read only to build the split modules below stay plain global reads.

> Spec API (12.0: C_SpecializationInfo preferred, fallback to global)

> Player class (resolved once, never changes)

> Phase 1 CP split: shared constants / profiles now live in ClassPower/*.lua
> Keeps the core chunk smaller and reduces WoW's top-level local pressure.

> Target-owned combo points reach this controller through one provider seam.
> WoW Forever's Game/Forever/ClassPower.lua publishes it as MSUF.CPClient,
> built from the shared Game/Shared/ClassPower/MSUF_CP_TargetCombo.lua module.
> The Classic flavors (MSUF.Client.IsClassic, read once) load this controller
> too: their flavor provider arrives adapted by
> Game/Classic/ClassPower/MSUF_CP_ClassicRouting.lua and also owns the combo
> point and display-modifier reads of every mode runner. nil on Midnight, so
> its routing and events stay unchanged.

> Cached split registries (load-time only; avoids repeated global table lookups
> and keeps the post-split core wiring easier to follow). Every builder file
> loads before this one (TOC order); the AltMana builder lives in
> ClassPower/MSUF_CP_AltMana.lua.

> The TOC-loaded AltMana builder replaces this before any consumer runs.

> Cold configuration helpers live in ClassPower/MSUF_CP_Controller_Config.lua:
> the cached DB config (_cpDB), SavedVariables defaults, feature gates,
> class/spec -> render-mode routing, the structural signature and the per-mode
> event profile. Hot paths keep _cpDB as an upvalue; everything else runs at
> FullRefresh cadence and is read through the CPConfig table.

> Colour resolution lives in ClassPower/MSUF_CP_Controller_Colors.lua. The
> resolvers cache per token; mode runners receive them by value through their
> build env and CP_CompileVisual reads them once per refresh.

> Charged / Empowered Combo Points (Echoing Reprimand, Supercharged CP, etc.)
> v6.1 behavior: rebuild the reused 1-based slot map when the charged-point
> event or a segmented structural refresh requests it.

> ClassPower visual: segmented bars (created lazily on player frame)

> The player-aura cache of the aura-driven resources lives in
> ClassPower/MSUF_CP_Controller_Auras.lua.

> Font / text-offset presentation helpers now live in the PRESENTATION
> builder of ClassPower/MSUF_CP_Core.lua.

> Active-mode dispatch (bound below); forward-declared so
> the presentation builder's colour refresh can reach it.

> Auto-Hide: visibility check after each update (OOC / Full / Empty)
> Zero overhead when all three are disabled (early-out on first check).

> Phase 7A CP split: pure presentation helpers now live in the PRESENTATION
> builder of ClassPower/MSUF_CP_Core.lua. This keeps the core smaller without
> touching build/layout/value flow.

> Legacy color-only refresh / texture refresh now live in the PRESENTATION
> builder of ClassPower/MSUF_CP_Core.lua.

> CPK.MODE.FRACTIONAL: Destruction Warlock - partial Soul Shard fill.
> UnitPower(unit, type, true) / UnitPowerDisplayMod(type) gives e.g. 3.7
> Fractional mode runner moved to ClassPower/MSUF_CP_Modes.lua (FRACTIONAL builder)

> The central OnUpdate driver (Rune, Stagger and degraded Essence ticks)
> and the per-mode OnUpdate policy live in
> ClassPower/MSUF_CP_Controller_Ticker.lua.

> Phase 5 CP split: class/resource specials now live in the SPECIALS builder
> of ClassPower/MSUF_CP_Core.lua. The core builds the handlers from a
> small feature builder so event wiring stays identical while class-specific
> logic stops bloating the orchestrator chunk.

> Phase 4 CP split: continuous + stagger mode runners now live in the
> CONTINUOUS and STAGGER builders of ClassPower/MSUF_CP_Modes.lua.
> The core keeps only orchestration and event wiring, while the heavy single-bar
> runners live outside the main chunk.
