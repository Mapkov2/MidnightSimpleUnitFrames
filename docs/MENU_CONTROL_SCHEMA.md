The Options addon loads `MSUF_Menu2_ControlSchema.lua` after the existing
bindings. SwingTimers, ResourceExtras, Gameplay and UnitRangeFade use
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
Swing and Group opt in; copy/filter/include scripts, source invalidation and target
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
smoke uses the pinned pre-conversion Misc page's automatic color card, unchanged
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

## Replacing rows for new pages

New page migrations use `Schema.Build(ctx, parent, rows, opts, refs)` with ordered
rows. `Schema.Render` and `Schema.Flow` retain their existing named declarations
for the already converted pilot sections; new pages do not mix the two formats.
Additional row kinds require a concrete page consumer and its tests. The shared
chrome kinds below consolidate the adapters in the four pending page migrations;
those pages adopt them after the shared package is approved.

The replacing tuple is `{ kind, key, UI fallback, { native arguments }, placement }`.
The optional placement is `{ x, y, width, alignment }`; absence keeps native placement.
Native argument and tooltip arrays are ordinary dense Lua arrays, without an `n` field.
Normal kinds are switch/toggle, slider, dropdown, textinput and color; buttons use
the existing theme constructor and their declared action. Labels, tooltips, flags,
input, history and combat refusal stay in the row and its typed binding adapter.

`GroupOptions` delegates ordinary rows to the existing GroupPage scope binders,
including toggle context refresh and slider integer rounding. Explicit
`binding = "scopeValue"` selects the original corner opacity/selected-field scalar
policy. `GroupRecordOptions`, `GroupSelectedOptions` and `GroupCommands` resolve
the current scope and selected record at input time; they keep the existing
false/zero/nil, raw-number and companion-write policies.

Record, selected-field and `scopeValue` adapters use ONE `afterSet()` signature:
no arguments, synchronously after the existing write/apply request. Ordinary
scope rows retain their GroupPage binder refresh and do not consume `afterSet`. A callback reads
current scope or selection through its existing owner closure rather than receiving
cached input or selection arguments. The record owner's `afterToggle()` fallback
has the same zero-argument contract. This is distinct from the older named-row
`spec.after(value)` interface retained by Render/Flow's unit adapters.

Preview and spell-tile factories are called directly with their existing
arguments. They keep their own controllers and lifecycle; there is no host row,
`factory` field or `opts.builder`. Build's fifth argument may be an existing refs
collector, as used by the Style owner's dependent-control refresh.

### Replacing row and owner options

| Field | Existing owner or order preserved |
| --- | --- |
| Row positions 1/2/3 | Native control type, stable field/ref key, UI read fallback. |
| Row position 4 | Dense native label/values/range/size arguments. |
| Row position 5 | Optional x/y/width/alignment passed to MoveWidget. |
| parent | An existing native widget for this row; constructor and placement use it, ctx and row order remain unchanged. |
| anchor, center | Native SetPoint tuple and button-label centering. |
| flagsBefore, flagsAfter | Widget flags before/after central binding. |
| beforeBind | Existing widget lifecycle preparation before binding. |
| tip | Dense AddTooltip arguments, including its optional options table. |
| action | Button OnClick callback, before placement. |
| register | Calls the page's opts.register(ctx, widget, row). |
| opts.bind | Typed binding function: ctx, widget, row, normalized kind. |
| opts.beforeBind | Owner preparation before the row's beforeBind hook. |
| opts.register | Page-owned registry; Build has no implicit group registry. |
| path, classification, exact | Group metadata identity/classification/navigation. |
| domain | Existing apply domain; group helpers default to visual. |
| binding = scopeValue | Explicit corner scalar getter/setter policy. |
| target, writeDefault | Selected corner field and original commit fallback. |
| scale, fallback, select, afterSet | Scaling, state selection and ordered zero-argument callback. |
| bind | GroupRecord/Selected/Commands special owner, including GroupNestedBinding; never rebound. |
| lifecycle | Widget-dependent factory for an existing command tuple. |
| source | Existing record provider; otherwise the record owner's config. |
| get/set, convert, afterWrite | Exceptional accessors or conversion and companion write. |
| accept, requireRecord | Input refusal and missing-record refusal. |
| subtype, defaults | False-or-record subtype and default initializer. |
| channels, uncheckedNil | RGB named fields and unchecked-to-nil policy. |
| identitySuffix, clamp, commitOnBlur | Metadata suffix, range clamp, text commit. |

Record owners supply config, scope, changed, path, meta and stepMeta, with optional
strictToggles/rawNumber/afterToggle. Selected owners supply selected, scope, default,
bool, number, value and write. GroupCommands receives the actual commands table
plus meta/stepMeta providers. An explicit row.get/set pair uses row[3] as its
fallback; otherwise the existing lifecycle factory or command-table entry owns
the accessors. Rows do not carry a separate command object.
GroupNestedBinding delegates to the existing nested-number binder. Colors forwards
named title/note/historyLabel/historySource/offsetX/textSettings options unchanged
to the original shortcut/reference controller, without a second binding owner.

### Shared native chrome and unit rows

| Kind | Native constructor / binding |
| --- | --- |
| sectionSwitch | `W.SectionSwitch`; normalizes to toggle for opts.bind. Reuses the header switch. |
| flowToggle | `W.Toggle`; reserves the native 32-pixel row exactly once, then binds as toggle. |
| segment | `W.Segment`; opts.bind receives segment, retaining central combat/history ownership. |
| scopebar | `W.ScopeOverrideBar(ctx, parent, row[4][1])`; the one argument is its existing options table. Its own selection/refresh/history controller remains the only owner; opts.bind is not called. |
| text / font | `W.Text` / `M.Theme.Font`, including heading template, color and role arguments. |
| card | `W.ControlCard` with title/subtitle/x/y/width/height/style. Fixed seven argument positions preserve a nil subtitle or style. |
| topButton / roleButton | Native `W.TopButton` / `W.RoleButton`; styles, active false and current click scripts remain native. |

Static and styled-button rows declare their stable row key (or row.meta.controlId),
row.scope (otherwise ctx.key/shared) and row.domain (otherwise presentation).
A scopebar retains its native catalog identity and live GetValue/SetValue/values;
row.domain defaults to menuState. Build a scopebar before the rows it scopes:
`Schema.Build` constructs and binds rows in array order, without a later scope pass.
Give cards domain=layout when that is their existing page declaration.
Card headings/geometry stay inside ControlCard;
ContextColors declares existing or later-attached shortcuts without creating them.
The page still calls Colors with the original shortcut options at its original time.
Font labels are native argument 2; other text labels are argument 1.

`Schema.UnitOptions()` returns `{ bind = Schema.UnitBinding }`, supplying the
former UnitSections typed binding policy. `Schema.UnitBinding(ctx, widget, row, kind)`
requires `row.meta` for ordinary rows, using its controlId and settingKey for identity.
Rows carry meta, scope/domain, get/set or unit, reason, commitOnBlur and roundStep;
slider ranges come from native arguments 2/3/4. Fallback row[3] retains false and 0.
Ordinary unit rows default scope to ctx.key and domain to unit. Custom get/set
pairs keep their accessors; otherwise unit rows use UnitPage's typed accessors.
The existing UnitPage readers/setters resolve profile data at input time. A unit
row without custom get/set must name a supported SetUnit domain (e.g. layout).
A unit `row.bind(widget)` callback keeps its original binding and declaration;
if it supplies no declaration, the shared adapter uses row[2] as the ID,
row.scope or shared as scope, and menuState as domain, without rebinding.
ClassPower workspace policies and the Group fixed-Party adapter remain page-owned.
Existing kinds and hook order are unchanged. No row construction seeds saved data.

`Schema.Build` calls `opts.bind(ctx, widget, row, kind)` for input rows, with
sectionSwitch and flowToggle normalized to toggle; segment stays segment.
For ordinary rows, UnitBinding delegates to `Schema.Bind(ctx, widget, spec)`, whose
central signatures are below (`get` and `set` are value accessors, `meta` is metadata).

| Kind | Central binding signature |
| --- | --- |
| toggle | `M.BindBoolWidget(ctx, widget, get, set, meta)` |
| slider | `M.BindNumberWidget(ctx, widget, get, set, fallback, meta)` |
| dropdown | `M.BindDropdownWidget(ctx, widget, get, set, meta)` |
| segment | `M.BindSegment(ctx, widget, get, set, meta)` |
| textinput | `M.BindTextInput(ctx, widget, get, set, commitOnBlur, meta)` |
| color | `M.BindColor(ctx, widget, get, set, meta)` |

Scopebars and static/styled chrome bypass opts.bind.
`Schema.GroupBinding(ctx, widget, row, kind)`, supplied by GroupOptions for ordinary scope rows, accepts
only toggle, slider and dropdown; segment needs an explicit typed policy such as
scopeValue. GroupRecord/Selected/Commands call their custom
`row.bind(ctx, widget, row)` instead, preserving the existing group owner.

### Verification tiers

The existing full `menu_group_indicators_parity_smoke.py` is NIGHTLY ONLY. Its
unchanged authentic fixture covers all five clients, two widths, three profile
states, every selected status/spec, inputs, history, combat refusal, tooltips,
section reset and scoped copy. The previous lead run cost 3,260 seconds at Jobs 1;
it is intentionally excluded by `-SkipTier nightly` on normal push/focused runs.
Normal push coverage keeps the existing typed input/DB/apply/refresh/history/combat
and section-inventory smokes. A focused correction run uses those changed contracts;
it does not repeat the unchanged full matrix. The train's full/nightly run retains
all existing cases and digests; no parity assertion or feature coverage is removed.
See tools/fixtures/menu-group-indicators/README.md for the full replay's cost.
Offline checks do not establish live WoW rendering, taint, engine timing or CPU cost.
