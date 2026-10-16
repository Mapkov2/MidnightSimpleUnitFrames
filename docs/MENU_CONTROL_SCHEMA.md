The Options addon loads `MSUF_Menu2_ControlSchema.lua` after the existing
bindings. SwingTimers, ResourceExtras, Gameplay, UnitAlpha and UnitRangeFade use
named declarations with stable IDs, kinds, labels, setting routes or custom
getters/setters, ranges/values, default sources, scope and apply domain. The
renderer creates the existing widgets and delegates input, combat refusal,
refresh and history to the existing bindings. Resource extras use its flow
renderer; custom tabs, color shortcuts, copy actions and dynamic marks retain
their existing owners. Lazy sections and reset/custom-badge ownership remain.
The text-input widget accepts a narrow pretranslated-label flag so Swing's
formatted attack labels use the existing raw text setter without another lookup.
Its obsolete translation-smoke exception is removed.

UI fallback policy deliberately preserves the original page owners (before-page
sources at 9c29a35a). ControlSchema's `UI_DEFAULTS` is the single compatibility owner
for Gameplay and unit alpha/range rows and the unseeded resource settings. These
are UI read fallbacks, not a normalized runtime profile or a migration. In
particular absent/bad Totem size is 24, Y is -6, crosshair thickness is 3, combat
text is +Combat/-Combat, and anchors are TOPLEFT/BOTTOMLEFT. Explicit stored
false, zero, empty strings and invalid dropdown values retain each old binder's
policy; false dropdown commits retain the old default substitution. Unit reads
still use UnitPage's boolean/number adapters; strict resource headers retain
their own getter and unconditional preview/apply setter.

Every `Schema.Default` caller uses that compatibility owner: Gameplay controls,
text, preview and Totem reset; unit alpha/range rows and their OOC projection;
and resource setting rows. The six native aura-resource defaults use the
existing `CPBuilders.ExtraAuraDefaults` owner. Runtime binds its five accessed
values to scalars once at load. Swing defaults still come from Swing.Get, as
before; attack inputs delegate to the existing Support text adapter shared by
BindTextInputAt. Selected-rule rows use Schema.MarkDefaults or the existing
dropdown value owner (first choice), retaining absent-rule toggle semantics.
Color shortcuts, copy widgets, and borrowed ClassPower visibility getters keep
their existing owners. No saved key is seeded or profile migrated by schema
construction, refresh or getter reads. Explicit unit-domain adapters
call the current UnitPage/ApplyService interfaces with their existing flags;
Gameplay, class resources and Swing keep their current apply callbacks.

The pilot does not move History/ApplyService into core or import pending profile
migration work. The generator remains the tracked stdout generator from the
base. Its approved check-mode tooling is integrated separately by the lead.
Both generated catalogs retain every row, identity, alias and navigation field;
only their source hashes change.

`tools/fixtures/menu-pilot` holds the real before-migration inventories.
`menu_pilot_inventory_smoke` checks every client, supported unit scope, lazy
section, narrow Gameplay layout, resource-mark state and Swing hand. Deletion,
kind, range, metadata-route and actual setter-route mutations all fail.
The inventory check also requires matching declarations for every real control,
including borrowed preview/visibility and section navigation owners. Totem
Preview and Reset declare their real callbacks, gate, scope, apply domain and
reset action key. `menu_legacy_fallback_smoke` covers cold rev17 partial profiles,
all read types, selected rules, all four attack labels, real staged import and
cached getters after real profile switching. Frozen old builders pass the same
test; the unfixed candidate fails. `resource_extra_aura_defaults_smoke` pins exact
pre-schema VM instructions, C calls and uninstrumented allocations on both live
sensor callbacks, Refresh and haste gates for missing, bad and normal keys.
The missing/bad overhead (3 VM/callback, 12/Refresh, 1/haste gate) is eliminated;
native and allocation budgets are unchanged. Source guards forbid hot table
default reads and preserve the existing text adapter.
`menu_control_schema_smoke` exercises central inputs, DB/apply requests, gating,
refresh, combat refusal, undo/redo, reset and cold exact OOC navigation. Existing
workspace and Swing smokes cover scoped copy and reset behavior.

Cold Classic unit navigation initializes adjacent aura defaults in the unchanged
base too; `.checks/cold-navigation-Vanilla-baseline.log` records that boundary.
The pilot navigation smoke pins all pilot-owned roots, without suppressing those
native page initialization steps. Offline checks do not establish live WoW
layout, exact navigation, undo interaction or combat/taint behavior.

The Swing Copy To button declares its existing OnClick owner without adding a
search/catalog row. Its stable declaration ID is menu2.swingtimers.swing.copy.button;
the twelve lazy popup IDs remain unchanged. The shared popup has an opt-in
declareControl callback after each real control's script and metadata exist.
Only Swing opts in; copy/filter/include scripts, source invalidation and target
selection stay with their original owners. Schema.Owned retains their actual
OnClick references and registered metadata without a second input binding.

The alpha state declaration delegates getter/setter to the existing
ScopeOverrideBar GetValue/SetValue methods. The owner retains normalization,
same-value handling, active buttons, card visibility, refresh and return values.
The declaration carries that selector's existing values table.

Supplementary original-9c inventories live in tools/fixtures/menu-pilot-lazy;
the original five menu-pilot fixtures remain byte-identical. The alpha selector
smoke checks every supported unit/client and missing, false, number, invalid,
empty and supported string inputs from both initial states. It records actual
setter/getter, refresh, visibility and repaint counts through cold/reopen,
sparse profile, real profile switch, combat, history and window reopen states.
The Swing smoke opens the actual lazy popup, checks all thirteen controls'
identity/type/range/metadata/ownership, and exercises every category, target,
All/None, copy filters, open/close/reopen, source changes, undo/redo, refusal and
late profile callbacks. Other clients assert the Swing page remains absent.
Native rendering callbacks are fixture seams; ancestor OnHide propagation is
explicit in the popup fixture because the widget harness lacks that propagation.
These checks do not establish live rendering, navigation, combat or taint.

Pilot contextual color/text shortcuts opt in through their existing section or
card owners. Schema.Section installs a cold declaration callback on its body
and header; UnitAlpha names its two existing cards explicitly. The shared
shortcut calls that callback only when present, after installing or updating
the real widget. Schema.ContextColors retains the actual OnClick wrapper,
widget owner, current options getter and relevance method. It does not bind a
command, resolve targets, translate labels again, or add refresh/event work.
Existing unconverted callers and automatic card-color attachment retain their
original behavior. The borrowed ResourceExtras visibility header and cold
pilot lazy shells now declare through the existing prepareShell owner.

Previously unregistered shortcut IDs append .colors to the existing section
header ID; UnitAlpha's card IDs are menu2.<page>.section.transparency.colors.health
and .resource. These are scoped declarations for existing noSearch buttons,
not new catalog/search rows. Every prior control ID and every 3885/4275 catalog
body field remains unchanged; generated source-hash headers intentionally move
because the declaration owner sources changed. No other source pin is relaxed.

The supplementary menu-pilot-actions fixtures were captured from immutable
production 9c29a35a before this correction's product edits. All five original
main inventories and ten lazy popup/selector receipts remain blob-identical.
The new inventory scans real interactive frames and existing component owners,
independently of the catalog. It pins raw labels, object kind, existing control
IDs, command/setting paths, ranges, choices, values, enabled/visible states,
installed callback source, options/capabilities, actual color targets and full
setting diffs across cold/warm, close/reopen, supported scopes/clients, health
modes, resource matching/marks, hands, combat and real profile switching.

The real old/new picker opens during this replay. Only native ColorSelect
texture/rendering methods are fixture adapters; Blizzard's loaded ColorPicker
XML uses the same wheel/value engine. Targets, picker controls, context/text
resolution, history and profile identity remain production owners. The opt-in
smoke uses a real unconverted automatic Misc color card and checks unchanged
callbacks plus late options. Section delegation probes exercise the real
shared popup, Custom badge, reset, close/reopen, undo/redo and refusal. Their
factory fixture explicitly seeds alpha so the existing Custom policy has a
comparison field; sparse factory fields correctly have no Custom badge.
Shared section chrome and global editors keep their separate architectures.
The derived ratchet baseline is remeasured against the exact c263 parent with
zero absorbed regressions. Its untouched SwingTimers and UnitSectionShared
length/locals rows also catch up to that parent's already shipped copy-owner
correction; no source, limits, allowlist, budgets or original fixture changes
accompany those inherited measurement updates.


## Complete pilot button dispatch

A declared button action calls Click on its actual widget at use time. The
native button owns current SetScript handlers, separate HookScript callbacks,
disabled input and the installed Theme/binding/protocol wrappers. Mark Add and
Remove expose that same action as their custom setter; Totem Preview/Reset,
section headers (including late ResourceExtras hooks), scoped chrome, lazy
Copy To controls and color/text shortcuts use the same dispatch seam. Composite
command getters/setters read the current registered widget command at use time.
No new binding, history, refusal or normalization owner is installed.

The former GetScript-only equality pins in menu_control_schema_smoke,
menu_pilot_action_owner_smoke, menu_pilot_section_delegate_smoke and
menu_swing_copy_owner_smoke were incomplete: GetScript excludes separate
hooks, including Theme's history checkpoint. They now require executable
current native-owner dispatch, exact widget/arguments, full return tuples and
an unchanged installed handler. The inventory additionally tests replacement
composite commands. These stronger assertions reject a no-op declared mark
setter and primary-handler-only, raw-callback and captured-owner actions.
The immutable original main/lazy/action inventory fixtures remain unchanged.

Only the opt-in nativeButtonLifecycle test model adds PreClick/OnClick/PostClick,
separate persistent hooks, disabled input, mouse/down defaults and complete
return tuples. Ordinary harness dispatch remains unchanged. The minimal Swing
fixture implements the same button API locally and exercises its actual owner;
production has no GetScript or raw-callback fallback for incomplete fakes.
The lifecycle smoke tests real mark/profile/reopen/refusal/undo/redo state and
counts, Totem Reset history, and every declared pilot button with late scripts
and hooks. Passing these offline models does not prove live WoW rendering,
combat/taint or the engine's callback return policy.


## Unit sections (batch 1)

PvP Trinket, Dispel Overlay, Dispel Symbol, Visibility, Boss/Arena Layout and
Boss target highlight declare their rows through the same renderer. A row with
`unit` set reads and writes through the UnitPage adapters (`Schema.SetUnit`, new
`arenaTrinket` and `layout` apply flags); rows with their own `get`/`set` keep the
old owner's fallback rules (Dispel reads the stored value, then `general`). Toggles
with `view = "at"` are created at their position. `roundStep` derives the old
`step`/`roundStep` metadata from the range. Section headers declare in `prepareShell`
and again inside the build, so hidden search-index builds are covered.

`tools/fixtures/menu-section-parity` holds receipts captured from the pre-schema
builders (base 32ee2629). `menu_section_parity_world.lua` replays them per section,
client and unit scope: control records, tooltip text, a layout digest of every owned
widget, and inputs with their profile diffs, apply requests, enabled states, undo/redo,
combat refusal and Reset section. Offline checks do not establish live rendering.
