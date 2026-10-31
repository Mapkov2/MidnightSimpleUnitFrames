# Shared runtime rules for menu previews

The core owns visual rules. Options adapts plain settings, sample identity and
resolved dimensions to those rules while retaining its own frames, handles,
selection chrome, layers, animation and combat lifecycle. No mock surface joins
the live unit registry or subscribes to unit events.

| Owner | Shared interface | Preview inputs |
| --- | --- | --- |
| `UF.elements.Portrait` | `PaintBorder`, `PaintBlizzardBorder`, `PaintMask`, `RingInflation` | Holder, compiled portrait fields, resolved width/height and scaled border thickness; class/reaction colours still use `BorderColor` |
| `UFVisuals` | `PORTRAIT_MASKS`, `PORTRAIT_SOFT_EDGE_MASKS`, `PORTRAIT_RING_ART`, `PORTRAIT_RING_ROTATION` | The same tables used by the live portrait painter |
| `ClassPowerColors` | `ResolveSlotColor`, `ResolveFullColor`, `OverrideRGB`, ramp tables | Optional final config argument with slot modes, legacy combo mode, overrides and full-colour enables |
| `UF.Config` | `DarkTint`, `ResolveDarkColor`, `ResolveBarBackgroundColorMode`, `ClassColor` | Plain configuration and explicit class token; portrait border colours keep their separate stock-colour rule |
| `UF.elements.Health` | `LayoutBackgroundFill` | Background bar, foreground bar, owner, missing/full, orientation, reverse and optional name-bar inset |
| `Castbars.Visuals` | `DetailNum`, `DetailString`, visibility rules, `ApplyIconZoom`, `AnchorText`, `PaintIconBorder` | Plain settings; optional text scaling; an already scaled pixel edge and preview-owned visibility for a border drawn on its icon host |

The live colour resolvers retain their cached-controller calling convention.
Previews reuse a scratch config and translate a default slot result of nil into
their base colour. They do not replace the controller's config or colour caches.
The Options unit body is `root:Unit(unitKey):Frame()`. The stage owns only its parent,
scale and position; engine regions own the health, power, prediction, texts, portraits,
status, shapes, aura lanes, texture layers and dispel samples. Handles refer to these
real regions. Castbar and ClassPower use their standalone engine surfaces and
anchor to the scene body. Text focus, layer/solo controls, animation, background,
selection, guides and zoom/pan remain stage chrome. Drag deltas divide by each real
region's effective-scale ratio to the outer stage before moving its anchors.

Health geometry is shared independently from value ownership. Live health keeps
its native inverse percentage, secret handling, interpolation and surface masks.
Mocks provide public sample fractions without unit API reads. Castbar padding is
scaled after the runtime resolves the anchor offset, preserving fractional zoom.

Menu health animation opts into discrete 0.8-second sample steps when Chunked Health Loss is enabled.
Unit and group scenes send those samples through the native loss trail; static samples clear it.
The shared animation clock retains its existing waveform for other preview owners.

Chunked Power Loss uses the same 0.8-second sample cadence for embedded and detached power bars.
Power sample writers retain native interpolation only while the owner clock animates; static samples clear loss snapshots.

## Group preview scenes

`GF.NewPreviewScene(parent)` returns a scene root; `root:Group(kind, count)` makes the
isolated group scene of a kind and shows `count` plain Buttons in a container parented
to `parent`. Whoever owns `parent` places and scales it (a new parent takes effect at
the next `Show` or `Refresh`). The frames are applied with
the compiled group spec through `GF.ApplySceneButton` and painted with the same fake
roster data as the Edit Mode dummies, so a scene frame paints exactly what the
on-screen dummy of the same index paints. The scene keeps its own frame pool,
container, layout frame, count, build serial and layer filter. The on-screen and Edit
Mode previews are the three default scenes (one per kind) and keep their state in the
`GF._preview*` tables the Edit Mode, header and aura code read; the two kinds of scene
never share a frame, a container or a layout count (`GF.GetActivePreviewCount(kind,
frame)` answers for the frame's own scene).

A scene frame carries `_msufPreviewScope` and holds no unit: `MSUFUnitKey` is nil. It is
applied by `UF.ApplySceneSpec`, not by the live apply. The scene wires the element
methods but installs no event script or show/hide hook, keeps the frame out of
`UF.attachedFrames`, builds no event routing and runs no update on apply. The group adapter keeps it out
of `GF.frames`, `GF.frameList`, the unit index, click casting and the secure unit
attribute. A scene never reads or migrates the saved grid position and never clamps its
container to the screen. `GF.HidePreviewsForCombat` hides every scene and a scene
refuses to show in combat; its result is true only when a default preview hid (those
retire a live header, which the runtime then hands back at REGEN_DISABLED), never for
an isolated scene, which retires none. While its root is inactive a group's `Show` only
records the wanted count, which `Activate` paints.

A scene frame is static: no scene paint calls a unit, roster or aura-of-a-unit API.
The live code carries no scene check at all (the live frame-apply budgets stay exact);
the scene variants live beside the live functions instead. An element whose apply asks
the client or joins a registry names its scene form `SceneApply` (status regions, group
visuals, group status, range fade, portrait). A nil unit already makes the other elements
read nothing. Names, levels, roles and hp come from the sample data
(`PREVIEW_NAMES`, the sample role of the row or the one `group:SetRole(role)` pins, the
row's sample hp, health text by health from the sample values); the threat sample is
painted by the scene's own preview data. The row's sample class (`_msufPortraitSampleClass`)
is its identity wherever a unit would be asked: `Portrait.SceneApply` draws the class icon
by default in either render mode (a supplied portrait sample replaces the class art;
the scene never calls `SetPortraitTexture`), takes
the class border colour from it and uses the friendly colour for the reaction border, and
the name colour with class name colour on is the same class colour
(`Text.PaintSampleName`, `NameTextColorFor` for a frame with no unit).
Compiling the group spec is the one shared settings pass left: it reads the player's
class to select spell-indicator specs, and runs once per configuration revision. The
scene never asks the client who the player is: row 1 draws its sample name where the
on-screen dummy draws the player's own. A change to a live element that makes its apply
read a unit must keep the scene form in step; `group_preview_scene_lifecycle_smoke`
fails on the first unit API a scene calls.

A grid slot and the sample member it shows are two things. `PreviewMember(scene, slot)`
(MSUF_UF_Group_Preview_Samples.lua) is the one place that maps the first to the second; it stores the member
in `frame._msufGFPreviewIndex`, and the sample role (`GF.PreviewSampleRole`), the portrait
class, the sample name and everything `ApplyPreviewData` paints read that field, never the
slot. A sorted preview order changes only `PreviewMember`.

The scene root is a preview kit host (`UnitFrames/Engine/MSUF_UF_PreviewKit.lua`, the
same shape the Suite implements: `NewHost`, `Activate`/`Deactivate`, `Acquire`/`ReleaseAll`,
`Request`). Nothing shows or listens until `root:Activate()`. While active the root
listens for `CONFIG_APPLIED`, `PLAYER_REGEN_ENABLED` and `PLAYER_REGEN_DISABLED` and answers the first two with one
coalesced repaint (`root:Request`) on the next frame; combat defers the repaint and the
regen edge brings the groups back (`group.want` keeps the count the owner asked for, an
explicit `group:Hide()` forgets it). A scene shows its static sample state: it never
follows the shared preview animation, only a clock its owner hands over (`root:SetClock`,
below). `root:Deactivate()` hides every group and drops all three
subscriptions. The owner still calls `group:Refresh()` after a change the signals do not
carry, `group:SetLayerFilter(visible, solo)` for the layer chips and `group:SetRole(role)`
to lay the frames out for one role.

The entry file owns the public kit root. Its named group domains own style primitives,
geometry, aura and indicator artwork, sample painting, frame pools and scene lifecycle.
Painters receive their scene, sample and clock explicitly. Default scenes keep the
legacy `GF._preview*` tables; every group preview frame names its scene through
`_msufGFPreviewScene`. The older `_msufPreviewScene` marker remains exclusive to isolated
frames. A scene frame's element-level base stays on that frame, so nested paints and
errors cannot alter another preview or the absolute live/Suite layer contract.

An owner embeds a scene in its own window: `group:Configure({ scale, level, role, sample,
bodyOnly, layerVisible, layerSolo, ignoreOocFade, fit })` sets, without a repaint, the zoom of the whole
container (`SetScale`: the frames keep their spec size), the frame level the scene sits at
(`SetLevel`: container, layout and frames take the one base, and every element level is
shifted by its frame-owned base, `Layers.FrameElementLevel`), the role the row lays out for, one pinned
sample for every row (`SetSample`: `name`, `class`, `hpPct`, `powerPct`, `hpMax`, `powerMax`,
`absorb`, `healPct`, `absorbPct`, `healAbsorbPct`, `tempMaxPct`, `powerColor`; the prediction and
reduced max health bars take their fractions from it, the absorb text and the combined health
text take the absorb amount) and `bodyOnly` (`SetBodyOnly`: the scene paints
the frame body, texts, prediction and border and leaves status icons, portrait, auras and
spell indicators to the owner's own handles). A pinned `class` is the identity of the row
wherever a unit would be asked: the portrait art and the class name colour follow it, not the
member the slot holds. `root:SetClock(elapsed, noRefresh)` hands over a clock when the owner
runs its own animation driver: every group animates at that elapsed time exactly as the
shared animation state builder computes it (another root and the shared animation clock stay
put), and `nil` returns the static sample. `ignoreOocFade` is for an owner whose window is
always open out of combat: the scene shows no out-of-combat fade (`GF.ApplySceneButton`
gives the scene frame an alpha lane of its own that inherits every other alpha setting from
the shared compiled one, so the health bar opacity and the text and portrait exclusions stay
live, the compiled spec stays shared, and the live Alpha and range fade elements know
nothing of it). `fit` makes the container the size of the one frame the owner shows: a layout
that keeps the raid groups apart sizes its grid as a whole group column and puts the lone frame
at its corner, away from the owner's centre (the Raid and Mythic Raid previews lost their body
that way). A scene lays such a grid out for the configured number of groups, never the roster's.

The Options group preview is such an owner. Its mock frame keeps the container, pan/zoom and
handles; the engine scene paints the cell, so the cell looks like a live group frame (the
SemiBold name face, the live name clip window, texts dimmed with the health bar opacity,
prediction height and offset). The cell mirrors the player: the Options stage reads
`MSUF.UFPreview.LiveUnitData("player")` during a refresh (pull-based, nothing in combat) and
hands the scene its name, class, exact health and power with their maxima and the absorb
amount, each field backed by the stylized sample when the player cannot give it; the scene
itself still reads no unit. A live-state driver on the preview box (`ArmLiveStateDriver`)
refreshes the cell when the player's health, power, absorb or name change while the menu is
open, with zero combat overhead: `PLAYER_REGEN_DISABLED` drops every listener for the fight
and only the re-arm signal stays. A text drag moves the engine texts by the delta divided by
the cell's scale ratio, so the text and its handle stay together at any zoom. The scene root is built by the first paint of the preview, not
when the Options file loads (sections 7 to 9 of
`menu_preview_runtime_drift_smoke`). Its old mock-cell renderer is gone; the oracle fixtures
of that preview were recaptured (see `tools/fixtures/preview-render-oracle/README.md`).

The unit, group, castbar and class-resource frame bodies belong to engine scenes. Options
keeps viewport layout and interaction chrome. The smaller standalone painter contracts
listed below deliberately demonstrate one product or setting without constructing a full
unit scene.

## Unit preview scenes

`root:Unit(unitKey, opts)` on a scene root (the root `GF.NewPreviewScene` returns) makes the static scene of one unit
frame: player, target, focus, targettarget, focustarget, pet, pettarget, boss1..5 and arena1..N, as far as the client has
them (`root:Unit` answers nil for a frame the client lacks; "boss" and "arena" mean their first slot). `opts.sample`
overrides fields of the unit's sample, `opts.show` shows it at once. The scene object has `Show`, `Hide`, `Frame()`,
`Refresh` (spec and paint), `RefreshData` (paint only), `SetSample(sample)` (merged over the unit's own, nil restores it)
and `IsActive`. The frame is a plain Button parented to the root's parent, centred on it once; whoever owns the parent
places and scales it, and may move the frame, which a repaint does not re-anchor.

A scene frame is a paint target, like a group scene frame, with the same rules: it is in no registry, the unit index,
click casting or event route, installs no secure attribute, event or script of its own (the portrait's inert repaint-on-show
hook is the one script it carries), and no engine cache or driver holds it. It is applied by `UF.ApplySceneSpec(frame,
spec, mask, "single", unit)` with a **private** spec: `UF.Config.CompileSpec(unit, out)` resolves the saved settings now into
the scene's own table, so a preview never wipes a live spec and never lags behind a pending apply. The mask names the unit
elements a scene paints; castbar and class power use the separate surfaces described below, the
auras are drawn as stand-ins (below), and the load conditions and the range fade drive live visibility and range.

**The frame holds no unit.** `MSUFUnitKey` is nil while the elements apply, so no element's apply can ask the client about
a unit; the unit token reaches only an element's `IsEnabled` (which decides, for example, that the resting icon is the
player's). An element whose apply still reads the unit names a scene form: `Power.SceneApply` (class colour mode),
`Alpha.SceneApply` (the opacity of the layers **without the out-of-combat fade**, which a menu preview is always inside of,
and without the fade registry). The shared inline target-of-target driver is a registry of one live frame; a scene
never claims it because its apply runs without the unit it is keyed on, and the isolation smoke would find it if it did.

**The mock source.** `MSUF_UF_UnitScene.lua` carries one static sample per unit family (name, class or NPC reaction and
type, level, health and power fractions, power type, classification, absorb, status flags, the picture an NPC portrait
stands in with). A sample is data only; its fields are `player` (true for a player: class colour and icon; nil for an
NPC), `class` (token), `reaction` (friendly, neutral or enemy), `npcKind` (the NPC type the type colour mode grades by:
npcRegular, npcCaster, npcMelee, npcBoss; none for a rare, which keeps its reaction colour), `level` (a number, -1 for
"??"), `levelTier`, `hp` and `power` (fractions of the nominal maxima, `UnitScene.HEALTH_MAX` and the sample's
`powerMax`), `incoming`, `absorb`, `healAbsorb` (fractions of the health maximum), `reducedMax` (the temporary
maximum-health bar), `classification` (elite, rareelite, rare, worldboss), `leader`, `assist`, `raidTarget` (1..8),
`raidGroup`, `pvp` (Alliance, Horde, FFA), `resting`, `combat`, `inline` (the target-of-target name of a target frame's
inline text) and `portrait` (the picture an NPC stands in with in a 2D portrait). The paint opens a *window* around the frame: the frame stands for its unit and its identity state
(`_msufUnitState`, the cache every identity reader of the engine consults first: exists, dead, connected, player, class,
NPC kind, tapped, boss disposition) is the sample, with a dispatch token the readers accept. Inside the window the
engine's own routines run on the sample: the health colour pass (`Health.PaintSample`, whose gradient takes the sample's
fraction; the dynamic background, health gradient or match health, is its scene form `Health.PaintSampleBackground`, also
run by the group scene, because the live refreshers read the unit's own health percent or paint a fixed tint without a
unit), the power colour, the name and its colour, the text slots and their colours, the portrait art and its border
(`Portrait.SceneApply`, `Portrait.PaintSample` for the classification art), the prediction bars
(`Prediction.PaintSample`), the status icons and identity texts (`Runtime.PaintSampleIndicators`,
`Runtime.PaintSampleIdentityTexts`, the live textures, packs and symbols), and the elements that have a sample mode of
their own (threat percent, pet happiness, pet experience: their `status.testMode`, set on the private spec for the length of
the update). No unit API is called inside or outside the window. A new element that reads a unit in its apply or update
needs a scene form, and `unit_preview_scene_isolation_smoke` fails on the first client call.

A few reads of the *local player's own class* are settings, not paint, and stay: the pet colour of the unit health
compile, the defensive spell hash of the Classic aura compile and the custom aura container compile, each once per
configuration revision, and the class background's once-per-session fallback token for NPC units. The isolation smoke
lets exactly `UnitClass("player")` under those four named functions through; any other API, argument or caller counts,
including an API the sandbox has no entry for and the functions of `C_UnitAuras` and `C_PlayerInfo`.

**Auras** are the shared stand-ins: `GF.PreviewUnitFrameAuras` lays the buff and debuff lanes of the unit's compiled aura
configuration out and paints them with the same regions and the same `MockAuraPainter` as a group scene frame.

**Intended differences from a live frame** (pinned by the smokes): the portrait draws the sample's picture (a player's class
icon, an NPC's own picture in a 2D portrait) where a live frame draws the client's bust; the out-of-combat fade is ignored;
the colour-by-health text and the difficulty-graded level colour use the sample's fraction and tier (`levelTier`, default
the standard band; "??" is the top band), where a live frame reads the client's colour curves. Nothing else differs: the
twin comparison in the isolation smoke covers every named region in text, colour, state and resolved geometry. A boss or
arena scene is snapped to physical pixels like its live frame (the frame carries its unit token as `_msufSceneUnit`, which
the boss bar geometry reads in place of the unit it does not hold), so those bars and borders follow the scene's real
position; a repaint re-snaps them, a move by the owner is picked up by the next repaint.

**Lifecycle.** Nothing is created at file load and a scene object builds no frame until it shows or `Frame()` is asked. The
root is the host: a closed root holds no timer and no subscription and a scene asked to show only remembers it; an open root
repaints every wanted scene once per burst of `CONFIG_APPLIED` signals, on the next frame. Combat hides every unit scene at once
(the root's own `PLAYER_REGEN_DISABLED` subscription; the group runtime's `GF.HidePreviewsForCombat` hides the group scenes),
touches no live header or frame, and the scenes do no work in combat; `PLAYER_REGEN_ENABLED` brings back the scenes that were wanted. Pools are per scene: the
frame, its regions and the aura stand-ins are reused by every repaint and by close and reopen. Nothing in the addon
catches an error inside a paint (no protected call), so a paint that fails leaves its window open until the next one;
every full refresh closes a stale window before it applies the spec.

The Options adapter samples `UFPreview.LiveUnitData` outside the scene and feeds
`scene:SetSample(sample, true)` before showing it. Exact `hpCur`, `hpMax`, `powerCur`
and `powerMax` take priority over fractions. Missing/secret fields use the stylized
sample independently; zero absorb uses the visible 10% sample shield. A hidden
per-box portrait texture samples the native bust and passes its plain texture resource as `portraitTexture`.
The scene never reads the unit. The existing per-box live-state driver pulls at most
once per 0.2 seconds, drops unit listeners in combat and releases them on hide.

`root:SetClock(elapsed)` drives the unit's native bars/value texts and MockAuraPainter
regions with that owner's clock; nil restores the static sample. Animated fractions
retain live maxima. `scene:SetLayerFilter(visible)` filters the actual regions after
painting. The scene reuses its private compiled spec while saved inputs match; a full
refresh applies layout, while clock updates paint values without layout. The Options
sample also carries `statusSelection`, `auraStyleKey`, `auraForceStandard`, `frameEffect`
and `frameEffectLayer` for the retained status/style tools. Disabled/zero-cap Style
lanes use private sample geometry and never enable their saved/runtime lane.

`runtime_preview_shared_rules_smoke.lua` boots the shipped graphs, checks live
and preview call identity, changed shared assets, fixed geometry/colour samples,
hide/restore transitions and mock inputs. Existing portrait, drift, repaint,
profile and per-event budget checks remain unchanged. These checks do not prove
game pixels, anchors, combat/taint behaviour or graphics-driver rendering.

## Preview kit

`UnitFrames/Engine/MSUF_UF_PreviewKit.lua` is the lifecycle and frame pool every preview
surface shares. Client-neutral on purpose: the kit reads no addon setting, knows no
unit-frame concept and registers no event or OnUpdate script of its own. A change signal
calls `host:Request` while the host is active; the owner subscribes to the signal in its
`activate` hook and drops it in `deactivate`, so a closed preview costs nothing. The one
repaint timer is a single-shot `C_Timer.After` per coalesced repaint request.
An animated castbar uses the elapsed time handed over by `root:SetClock(elapsed)`.
Passing nil restores its static sample; inactive or combat-suspended surfaces do no work.

```
Host (Kit.NewHost(parent, opts)):
  opts.build(host)             once, on the first Activate
  opts.activate(host)          on every Activate, before the first paint (subscribe to change signals here)
  opts.paint(host, reason)     repaint everything the surface shows; only ever called while active
  opts.deactivate(host)        on Deactivate, before the pools are released (drop signals, hide extras)
  opts.allowed(host)           optional gate; false defers a repaint (combat) until the next Request
  opts.create(kind, host)      a new pooled object; opts.reset(kind, object) on release (default: Hide)
  opts.after(delay, fn)        timer (default C_Timer.After)
host:Activate() / host:Deactivate()     build once, hide and release on Deactivate, no timers while closed
host:Acquire(kind) / host:Release(kind, object) / host:ReleaseAll(kind)     frame pools
host:Request(reason)                    coalesced repaint on the next frame; ignored while inactive or disallowed
host:Refresh(reason)                    repaint now; same gate
```

The kit ships only what its current consumers use. A handle controller (select, drag, arrow-key nudge)
belongs to the first surface that needs it. An arrow-key handler does nothing under lockdown (neither a
nudge nor a `SetPropagateKeyboardInput` call, which is blocked in combat), and a host
`Deactivate` cancels a running drag and deselects, so a closed preview holds no key
script and no keyboard capture.

## Standalone castbar and ClassPower scenes

Use the existing `GF.NewPreviewScene(parent)` root. Creating the root or asking for a
surface while it is closed allocates no frame. Activate it when the page opens,
deactivate it when it closes, and retain it for pool reuse. Release is terminal.

```lua
local root = GF.NewPreviewScene(parent)
local cast = root:Castbar("player", {
  sample = { class = "MAGE", name = "Frostbolt", icon = 136048,
    kind = "CAST", duration = 4, progress = .6, notInterruptible = false },
  animate = false,
})
local resource = root:ClassPower({
  sample = { class = "ROGUE", spec = 1, count = 3, maximum = 5 },
  playerWidth = 275,
})
root:Activate()
-- Both: SetOptions(fullReplacement), Refresh, Show, Hide, Frame, IsActive.
root:Deactivate()
```

Both options tables accept `point`, `x`, `y`, and `scale`; all inputs are copied plain
data. Secret inputs are rejected before indexing or comparison. Castbars accept
`width`/`height` overrides (otherwise the core size rule), `CHANNEL` or `EMPOWER`
samples where the client supports them, cumulative `stages`, `spellID`, `knownSpells`,
`latency` as a fraction, `targetName`/`targetClass`, `kickReady`, `kickRecovery`
(an array of recovery fractions on the cast interval), and `interrupted`/`interruptLabel`. Progress is
static unless `animate` is true. No live cast acquisition, event registration, native
duration bindings, or runtime-manager registration belongs to these surfaces.

ClassPower uses a second instance of the core build/layout/presentation/mode factories,
the shared config/slot/full-colour resolvers, and the same class/spec routing. Optional
sample fields include `primaryPower`, `formID`, `modifier`, `partial`, `charged`,
`predicted`, `knownSpells`, `auras`, `runes`, `runeTypes`, `ironfur`, and `time`.
`playerWidth`/`playerHeight` describe the player surface. `cooldowns` is a map keyed by
EssentialCooldownViewer, UtilityCooldownViewer, or BuffIconCooldownViewer, each with
plain `width`, `height`, `scale`, `x`, `y`. The core computes its width and anchor from
these projected rectangles, including the full 275-pixel Player width. These proxy
frames and all controller caches belong to that scene. No live cooldown anchor moves.
Out-of-combat auto-hide is ignored; configured full/empty and feature visibility remain.
Ebon Might belongs to the Player Power surface, not the standalone Essence surface.

The root subscribes only while active. Combat suspends surfaces and cancels their
clocks without requesting a live-header rebuild; regen repaints wanted surfaces.
Each class's painters and each root's frames are retained independently. Static
native-aura samples use the core native slot's regions/style with plain sample values.

The Options previews paint these scenes. Each preview box makes its root on its first
visible paint (parent: the castbar slot, the unit body holder, or the Class Resources stage),
reuses it, deactivates it when the box hides, and never builds one at load. Options feeds a
sample, `width`/`height`/`scale`/`point` and the `cooldowns` rectangles of the shown Cooldown
Manager viewers; it keeps the selection, zoom, viewport, help, replay, animation and layer
controls, the text and selection handles, the castbar slot, and the detached GCD strip, which
is not part of the castbar. A changed setting reaches the scene through `SetOptions`.

Preview-only additions to the scene contract:

- `scene:Tick(fields)` copies scalar sample fields into the scene's own sample and repaints
  only what they drive (a castbar's progress and time text, a resource's mode painter), so an
  animation tick allocates nothing beyond the painters' own text.
- Castbar samples accept `latencyMS` (the "50 ms" text of `castbarShowLatencyText`, player) and
  `blinkStage`/`blinkPhase` (the empower stage flash of `empowerStageBlink`, driven by the
  owner's clock through `Empower.PaintSampleBlink`).
- ClassPower samples accept `bars`, a table that overlays the profile's `bars` for this scene
  only. The preview forces the resource gates the picker ignores (`showShadowMana`,
  `showEleMaelstrom`, `showGuardianIronfur`, `showSweepingStrikes`, `showStagger`) and carries
  its Border and Res Text layers (`classPowerOutline = 0`, `classPowerShowText = false`).
- `scene.CP.container`, `scene.CP.text`, `scene.CP.bars` and `scene.CP.currentMax` are the
  retained regions Options places handles, bounds and the threshold tint around.

The new smokes compare native visual properties and resolved screen rectangles with
real core castbar/controller surfaces. They cover all five graphs, supported resources,
width sources, colour rules, pools, closure, combat and a whole-family unit-API spy.
This is offline contract evidence; live WoW pixels, combat/taint and GPU rendering
still require in-client verification.

Unit scenes also hide native aura sensors, spell indicators and frame-effect registrations on deactivation. Dispel handles and footprint geometry remain locally bound Options chrome; all visible sample effect painting belongs to the engine.

Selected group spell samples use `GF.PreviewSpellSample(frame, owner, slot)`.
The engine owns the retained icon/bar/square/number visual; Options translates
the editor placement into slot fields and adopts the visual into its handle.
`GF.HidePreviewSpellSample` retires the sample and its native glow when a
refresh restores the scene parent. Configured slots use their separate scene
pool, so placing or disabling a selection cannot leave the insertion sample
visible. Native icon glows reuse `SpellIndicators.ApplyPreviewIconEffect` and
its paired hide without joining the live icon-effect registry. Classic keeps
its existing halo fallback when that native renderer is absent. No new event
listener, ticker or live update call is installed by these sample APIs.

The ClassPower workspace allocates its sample's `bars` overlay once with the scene
root. Border and resource-text layer switches reuse that table; the scene overlays
it on the saved configuration without changing the profile.

`tools/scorecard.py` checks the reviewed F1 preview-render census in
`tools/preview_render_census.json`: 2303 physical / 2176 code lines in the ten
reviewed files have zero remaining preview-only render lines. Normalized source
hashes pin that review; any file change requires reviewing and renewing its
receipt. This source census does not establish in-game visual equivalence.

## Group portrait and status sample contract

The group sample optionally carries `portrait = { shown, texture, l, r, t, b }` and
`statusRegions = { { field, shown, text, texture, l, r, t, b }, ... }`. These are retained,
public sample values, never live regions or callbacks. The existing sample identity fields
(`player`, `leader`, `assist`, `raidTarget`, `raidGroup`, `incomingRes`, `pvp`, `level`,
`statusSelection`) seed the runtime's status painters first. Each status record then supplies
the selected editor example for the named runtime region. Configured custom art, icon-pack
coordinates, role style, status text and the selected status mode come from the existing
Options selectors. The engine applies the portrait/status layer gates and status alpha.
Absent records preserve the ordinary group-scene samples used by Edit Mode and other owners.

Options samples a 2D player portrait into a hidden donor texture outside the scene, checks
that the resource is public, and passes that resource and coordinates. An animated cast
portrait passes the selected spell resource instead; a class portrait stays with the engine's
class art. The scene paints its own holder and portrait through `Portrait.SceneApply` and retained
spec views; the portrait provider owns its texture/UV caches, including return to class art. After paint, Options only binds the
portrait and status interaction handles; it does not replace their content or visibility.
The records survive configuration repaint, owner-clock repaint and close/reopen. Private menu
spec copies retain the binding spec's inherited compiler fields as well as its own fields.

## Intentional standalone painter contracts

Reviewed at the H3 source change on 2026-10-24 against the G2b inventory. Paths below are
relative to `MidnightSimpleUnitFrames_Options/Shell/Menu2`; names identify functions rather
than line numbers, which move during page refactoring. These are bounded demonstrations,
asset selectors or explanatory samples. They are excluded from a claim that every preview
is a full scene. A painter contract shares the runtime renderer and configuration rules;
Options owns only the sample inputs, local host and interaction chrome. A diagram or text
sample makes no claim to reproduce a complete frame.

| Surface and source owner | Shared painter or resolver | Explicit sample and ownership boundary |
| --- | --- | --- |
| Detached/attached GCD, `Preview/MSUF_Menu2_UnitPreview_Render.lua:ApplyGcdSample` | `CastbarGCD.CreateSurface`, `LayoutSurface`, `PaintSample` | Retained local surface and feature-sample progress; shared GCD settings determine layout/style. This strip is separate from the castbar scene and never acquires a live spell or native duration. |
| Arena trinket, `Pages/MSUF_Menu2_UnitArenaTrinket.lua:TrinketPreview.Paint` | Arena trinket runtime `PaintSurface` | A local icon projects the configured trinket appearance onto the selected arena mock; it neither registers a live cooldown nor chooses a real opponent. |
| Aura workbench, `Pages/MSUF_Menu2_Auras_Preview.lua:WorkbenchRefresh` | `MockAuraPainter.NewWorkbench`, native `ButtonVisuals` or Classic backend sample painters | The unit/group menu readers supply the selected scope's geometry/style; the retained buff/debuff texture lists and special-product entries supply fake auras. Sample capacity is bounded; icon dimensions, spacing and per-row wrapping are preserved. Only the whole workbench canvas is fitted/zoomed. Appearance-only special-product strips deliberately use four 32px icons at spacing 4. |
| Resource auxiliaries, `Preview/MSUF_Menu2_ClassPowerPreview.lua:RenderDetachedPower`, `RenderPlayerHP`, `RenderAlternativeMana`, `RenderExtraSamples`, `UpdateSampleThresholds` | Runtime auxiliary `PaintEbon`, `PaintHP`, `PaintMana`, `PaintExtras`, `marks.PaintSample` | The scene's class/spec and retained sample/config overlays own values and eligibility. These painters supplement the core ClassPower/Player surfaces with Ebon Might, PlayerHP, alternate mana, Ignore Pain, Arcane Window and thresholds. The owner hands over its clock; no live controller or native resource subscription is acquired. Bounds and text handles are chrome. |
| Dispel example, `MSUF_Menu2_Preview_Scenes.lua:PaintGroupSceneDispel` | Aura `PaintSceneEffects`, or Classic `UpdateDispelOverlay`/`UpdateDispelSymbols` | Engine-owned effect regions use the scene's resolved sensor/visual configuration. Classic's retained set of dispel types intentionally demonstrates every symbol. Options binds the footprint/handle and selects the example; no aura of a unit is queried. |
| Crosshair, `Pages/MSUF_Menu2_AdvancedGameplay.lua:previewRefresh` | `Gameplay.PaintCrosshairGeometry` | The saved size and thickness feed the gameplay painter on a local host. The example has no cursor tracking or gameplay driver. |
| Swing timers, `Pages/MSUF_Menu2_SwingTimersPreview.lua:Preview.Build` | `Swing.CreateMenuPreview`, `Swing.PaintMenuPreview` | The gameplay module owns sample bars and their paint/config rules. Options selects the main/off/ranged example and its section; these samples start no native swing timer and write no profile while painting. |
| Icon skin strip and gallery, `Pages/MSUF_Menu2_IconSkins.lua:Page.PaintSample`, `P.RefreshGallery` | `IconShape.ApplyIconShape`, `IconSkins.AttachPreview`, `ApplyIconStyleSkinned` | Fixed local icon/tile sizes and selected product skin/look are deliberate catalog examples. No aura acquisition or alternate skin renderer is installed. |
| Dragon/elite preview selector, `Pages/MSUF_Menu2_UnitFrameVisuals.lua:p.DragonPreview` | Portrait element `GetClassificationPreview`/`SetClassificationPreview` | The control selects ephemeral classification state owned by the runtime portrait element. It has no local dragon painter and does not persist a fake unit classification. |

## Diagrams, asset strips and typography samples

These intentional examples have a narrower contract than the painters above. Their sample
geometry or text is explanatory; the shared setting/asset resolver remains authoritative.

| Surface and source owner | Contract |
| --- | --- |
| Group growth tiles, `Pages/MSUF_Menu2_Group.lua:DrawGrowthMiniPreview` | Colored cells and a direction arrow explain the growth choice using the tile's direction/layout descriptor. They are a diagram, without health, texts, unit regions or a roster. |
| Boss/arena growth tiles, `Pages/MSUF_Menu2_UnitSections.lua:DrawMiniBossPreview` | A fixed number of colored rectangles and the shared tile direction arrow explain stacking. The selected direction descriptor drives the diagram; its tile dimensions are illustrative. |
| Group status strip, `Pages/MSUF_Menu2_GroupIndicators.lua:StatusIcons.RefreshIconPreviewStrip` | `PreviewEntries` enumerates example variants; `ResolvePreviewIcon` resolves the selected runtime style/custom art. The strip previews assets and coordinates, with dimming for a disabled setting; it is not a status-state simulation. |
| Unit status strip, `Pages/MSUF_Menu2_UnitStatusSection.lua:RefreshIconPreviewStrip` | `StatusPreviewEntries`/`ResolvePreviewStatusIcon` select the same icon assets, atlas or shared resting flipbook. A page refresh stops the previous strip animation before replacing it. Labels, spacing and disabled alpha belong to the catalog chrome. |
| Font/shadow samples, `Pages/MSUF_Menu2_GlobalFonts.lua:ApplyPreviewFont`, `RefreshFontPreview`, `RefreshShadowPreview` | Fixed sample text demonstrates the selected font, flags, color, scale-animation mode and shadow through the core font resolvers. It does not emulate a unit's name/health-text layout. |
| Dropdown font specimens, `MSUF_Menu2_Dropdowns.lua:ApplyDropdownItemFont` | A font-choice item supplies its font key/object to the safe runtime font resolver; the dropdown label is the specimen. The item does not create a unit scene. |
| Number samples, `Pages/MSUF_Menu2_GlobalMisc.lua:RefreshAbbrevSample` | A fixed list of numbers passes through `NumberFormat.FormatWith` and the selected settings. Separators merely place the examples beside one another. No copied abbreviation algorithm is permitted. |
| Guided tour images, `MSUF_Menu2_Widgets.lua:W.PreviewImage`, `MSUF_Menu2_GuidedTour_Pages.lua:PreviewCard` | Static texture/UV metadata displays a packaged screenshot in explanatory chrome. It is not a live preview and is never evidence of the current runtime render. |
| Layer tutorial, `MSUF_Menu2_UpgradeHighlights.lua:BuildLayerDummyPreview` | A fixed range track, knob and layer-name rows explain ordering. This tutorial diagram has no runtime regions, scene selection or saved-setting write. |

For all entries, sample constants stay with their named owner and shared rendering/configuration
logic stays with the runtime provider. A new renderer or a changed sample meaning requires
updating this contract and a behavioral regression. These source contracts and offline tests
do not establish live WoW pixels, combat/taint safety or native CPU/GPU behavior. The bounded
render census is an inventory receipt, not a broader rendering-equivalence claim.
