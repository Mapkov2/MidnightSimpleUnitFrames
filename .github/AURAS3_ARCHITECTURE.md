# Auras3 ownership and maintenance

Auras3 delegates aura tracking, filtering, sorting and assignment to Blizzard's
native AuraContainer. MSUF compiles settings, creates the visual owners, styles
buttons during initialization and reconciles frame identity/lifecycle changes.
The addon must not introduce a parallel `UNIT_AURA` scanner.

## Entry points and loading

`UnitFrames/Embeds/MSUF_UFCore/MSUF_UFCore_Elements.xml` is the authoritative load
order. Each group of modules registers one-time factories immediately before its
existing entry point. There is no in-game `require`, `loadfile`, generated code or
environment replacement.

| Entry point | Responsibility |
| --- | --- |
| `MSUF_Auras3_Core.lua` | Persisted model initialization and runtime generation |
| `MSUF_Auras3_SpellIndicators.lua` | Compose slot configuration, effects and reminders; preserve the native `Install` API |
| `MSUF_Auras3_UnitFrames.lua` | Compose the runtime owners and register the established public A3/UF surface |
| `MSUF_Auras3_EditMode.lua` | Compose preview configuration, layout, drag capture and preview lifecycle |
| `MSUF_Auras3_Menu_Model.lua` | Compose menu schema, storage, presets, appearance, custom containers and filters |

Factories receive explicit dependency owners (for example `Platform` and
`ConfigValues`); their import headers list the exact symbols they consume.
Factory and dependency tables are initialization objects. Consumers capture
their functions as local references; they do not dispatch through dependency
tables during events. Factories are released after composition. Do not retain a
general mutable environment containing every module's private state.

## Runtime owners

The files in `Auras3/Runtime/` have the `MSUF_Auras3_Runtime_` prefix.

| Owner | What belongs here |
| --- | --- |
| Platform | Client availability latch, numeric/frame primitives and native tooltip setup |
| Schema | Lane defaults and the single persistence-field ownership map |
| Appearance | Shared icon shapes, dispel assets and color maps |
| Sort / Signatures | Native sort rules and canonical tracking/structural/layout signatures |
| ConfigValues | Shared configuration readers, filter composition and lane finalization |
| DispelConfig / LaneConfig / CustomConfig | Compile independent sensors, ordinary lanes and custom/curated/reminder descriptors |
| UnitConfig / GroupConfig | Configuration caches, invalidation, diagnostics and shared preview metrics |
| DurationText | Duration formatter/binding cache, locale invalidation and text placement |
| NativeContract | Native capability validation, MSUF root creation and reuse predicates |
| OwnerConfig | Cached native owner plan, reaction partitions and compatible lane sharing |
| ButtonVisuals / DispelVisuals | Pre-handoff button/sensor art, rounded masks and border thickness |
| EffectPreview | Mutable addon-owned overlay/symbol preview regions |
| Containers | Native group/slot creation, filter updates and desired geometry |
| Identity | Unit and group reaction gates and deferred reveal |
| Presence | Group token generations, connection, phase and out-of-combat presence |
| IdentityEvents | Shared owner registry, narrow event topology and coalesced refresh |
| NativeApply | Reuse, replacement, retirement and native configuration application |
| Facade | Established public requests, refreshes and the UF Auras element |

The bootstrap resolves four genuine backward references once: root refresh,
container registration, lane application and consolidated group replacement.
These local callbacks are bound before `NativeApply.Initialize` and before the
Facade registers the UF element. A new cyclic dependency must be explicit here;
do not replace it with recurring wrappers or opportunistic global lookups.

`GetNativeOwnerPlan` compiles one ownership map per configuration. Apply, identity
refresh and reuse validation all consume it. A Unit Dispel owner can also own
ordinary fixed one-icon lanes and one flowing lane with the same identity policy.
Portrait, custom-priority, weapon-enchantment and name-alias lanes retain their
independent lifecycle. The historical root keys remain stable; Edit Mode resolves
each button's lane and enumerates flow buttons through Blizzard's public
`GetAuraGroupFrame` / `GetAuraGroupFrameCount` APIs.

Within an owner, Dispel visuals share one selection only when their native filter,
candidate signature and reaction policy are identical. Each visual keeps its own
child host, geometry, alpha, layer and native texture binding. An ALL-type symbol
still needs separate per-type selections. Build the whole selection plan before
the first `AddAuraSlot`: its initializer can run synchronously and seal children.
Changing an input that can change this partition recreates the immutable owner.
This removes live selection/cache work but may recreate more attached lane art
during an appearance edit. Cold creation is not a per-event CPU improvement.

Custom source spell names can correspond to different aura IDs. `AuraAliases`
resolves their locale-exact SpellName catalog groups during custom configuration
compilation, after DoT eligibility pruning and before creating any native owner.
Only configured custom IDs acquire aliases; curated defaults retain their explicit
ID rules. Native candidate filters own all subsequent selection. There is no
MSUF name resolver event stream, aura query, protected call or live retry driver.
The original `sourceSpellIDs` remain separate from expanded candidates so each
priority entry or reminder still owns exactly one position and its original
click binding. Custom owner isolation and identity gating remain unchanged.
See [alias catalog maintenance](AURAS3_ALIAS_CATALOG.md) for provenance, language
coverage, regeneration and the boundary for new client/hotfix data.

## Contracts that must survive a change

* Native `initializeFrame` runs before access restrictions are applied. Complete
  regions, masks, bindings and geometry before handoff. Never query or mutate a
  sealed native child to restyle it; recreate its owner when immutable inputs change.
* Unit reaction gates intentionally control alpha and native enablement. Group
  reaction gates intentionally retain enabled native tracking and change alpha.
  Native `SetEnabled`/`SetUnit` trigger a full update when their value changes.
* Schema tables exported to the menu are shared references, not copied field lists.
  Persisted keys, scope inheritance, migration rules and defaults remain stable.
* Cache identity includes configuration/visual generations, spec revision and
  unit token. Group caches also check group kind. Explicit invalidation must
  reach previews and shared compiled-spec caches.
* Dispel border enablement is independent of aura-icon visibility. Its Show on
  filter does not alter overlay, symbol, purge or threat policy. Both frame shapes
  use the configured highlight thickness.
* Reused party/raid tokens cannot inherit another member's absence state. Presence
  gates hide output without interrupting incremental native tracking.
* Protected reminder-click retirement, combat deferral, next-frame reveal and
  event-topology batching retain their existing owners and ordering.

These native contracts were checked against local `upstream/live` at `8ea15b61e`,
especially `Blizzard_AuraContainer.lua`, `Blizzard_AuraContainerFrameProviders.lua`
and `Blizzard_AuraContainerUtil.lua` in `Interface/AddOns/Blizzard_AuraContainer/`.
Sharing also follows `Blizzard_ManagedAuraContainer.lua` (per-owner aura cache),
`Blizzard_AuraContainerSlots.lua` (per-slot delta processing) and
`Blizzard_CustomAuraButton.lua` (multiple native Dispel texture bindings).

## Configuration work and ownership

Group edits advance only their group's revision. Raid edits intentionally also
invalidate Mythic Raid, while frames without a known kind use a conservative
fallback revision. Global/profile and visual changes still invalidate every
scope. The effective Group config generation is the sum of the global and scope
revisions: both must only increase, never reset. This keeps a single generation
comparison on cache hits; the separate group-kind check prevents a pooled frame
from reusing an equal-numbered revision belonging to another scope.

Global Appearance edits must request the shared scope. `MenuModel.Apply` uses
scoped Group invalidation when the runtime is available, with the historical
global fallback for standalone menu consumers. Unit invalidation retains its
existing frame-spec and unit-cache paths.

Spell-filter normalization accepts the legacy persisted forms and keeps stable
sorted signatures. Canonical numeric IDs skip string parsing. Combined include
and exclude filters allocate one outer options table, but their mutable ID maps
remain private: automatic blacklists and learned name aliases can extend them.
Only explicitly versioned static catalogs may share their include map. Do not
memoize mutable maps merely by table identity or global configuration revision.

Group Spell Icons reuse their original item list unless enabled corner slots
actually require a merge. Preserve item indices on that unmerged path; merged
lists retain spell-before-corner ordering. Empty owners skip unused style/slot
compilation. The source list and its items remain owned by the compiled spec.

Preview reads resolve storage once before runtime compilation and once after it.
The second resolution handles profile changes or migration during compilation;
one short-lived context then supplies all typed reads. It is never stored in
module state, so later writes, profile replacement and nested calls cannot reuse
a stale read context. Lane schema constructors also run only at module load and
produce the same concrete tables used by the runtime and menu.

## Extending and checking Auras3

Add a setting to its schema/storage owner, compile it into a descriptor, include
it in the appropriate existing signature, then consume that descriptor in its
visual or lifecycle owner. Keep expensive work on the configuration/creation
path. Bind a cross-module helper once; do not duplicate normalization or filters.

The repository's focused Auras3 tests use the same XML order and real module
factories. Local broader smoke tests additionally cover profile migration, menu
apply, preview/drag, native ownership, geometry, secret-value guards and churn.
Function-body comparisons and operation traces are useful refactor evidence but
do not establish live WoW combat/taint correctness or measured CPU improvement.
Use equivalent before/after workloads for a performance claim. A new Perfy build
or capture requires a separate explicit request.
