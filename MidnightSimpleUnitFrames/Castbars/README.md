## Castbars modules

Every client loads `MSUF_Castbars_PublicAPI.lua`, Backend and Config before the castbar providers.
Providers resolve the required MSUF namespace through `MSUF.Require` and retain module upvalues.
Engine normalizes cast state; Runtime applies stable durations and cleans frames; Driver owns hostile
cast events; Pools owns boss/arena lifecycles; Manager owns registration and shared update work;
Style owns outlines; Config compiles reused unit records; KickReady owns readiness snapshots and wakes.
Player retains its separate event runtime. Font and texture services remain in Core.

`/msuf castdebug` toggles session-only player event diagnostics, including completion,
interrupter, castBarID and the resulting feedback/visibility decision. Secret arguments
print as `<secret>`. SUCCEEDED is observed only while tracing; it does not decide player
completion. Tracing off retains the normal event dispatch without diagnostic work.
The player preserves empower state across preliminary STOP/FAILED events until the
authoritative empower stop or interrupt. Restricted completion uses the Driver's
interrupter-presence rule. CHANNEL_STOP also terminates empower, matching native
reverse-channel handling; an interrupter produces feedback on that route too.
Blizzard's Lua defines the payload and reverse-channel handling, not engine event order;
the player terminal-event smoke covers competing orders and needs an in-game trace.

Only PublicAPI publishes the compatibility functions required by other subsystems, the public ledger
and Suite. Suite's `MSUF.KickReady` retains its own consumer table and its original eleven-key surface;
`MSUF.Castbars.KickReady` holds the internal readiness providers.
Named frames are created once; consumers use `Castbars.Frames.Get(kind, index)` for live/preview identity.
Kinds are player, target, focus, boss and arena; append Preview for preview frames. Indexed kinds use
index 1 by default. Existing CreateFrame names remain the client-visible names, without global aliases.

Config reads the live profile at login and cold apply/revision boundaries, and keeps reused records for
each unit kind. Backend setters synchronize modern backend keys and legacy enable flags in the source;
preview/test-mode resets also write the source. Hot paths consume the compiled records and revision
fields. Config.Source provides the writable profile; Config.Invalidate (also named Config.Refresh) only
advances the configuration revision after a write. Config.Read(unit) compares the record revision and
compiles the reused shared snapshot once on first access; Config.Read() returns the same snapshot DB.
No apply bracket or state survives across callbacks. Internal apply calls pass current=true because
their writers already invalidated; public settings/profile apply boundaries invalidate before fanout
when they affect compiled settings.
Target/focus ownership follows the backend independently of unit-frame visibility. Both Focus Kick
consumers additionally respect focus.enabled=false; nil retains its enabled default. Cold Edit Mode
reads use the live source. Pool anchors use Config.Geometry(), including replaced general/unit tables;
geometry-only public calls need no invalidation and compile no records. Menu duration and focus-display
writers refresh before their immediate readers.

The castbar, interrupt, kick, empower, GCD, pool, preview and Edit Mode smokes cover behavior. Partial
test worlds seed their absent providers into the namespace without re-exporting internal globals;
client boot/public-global smokes
load the actual TOC and exercise the production compatibility boundary.

## Fixture and pin maintenance

The namespace refactor changes internal provider and frame ownership. Focused fixtures therefore
resolve their old test handles through Castbars modules; real client/public-export tests load the TOC.
Partial integration fixtures load Config/Backend and the actual providers they exercise, rather than
restoring retired exports. Pure follower fixtures still isolate foreign notification sinks.

Source pins and export ledgers follow those intentional ownership changes: the public compatibility
boundary retains Suite's readiness consumer identity; internal functions and frame identities move
to named modules. Generated load order and menu source hashes follow the actual provider graph.
The scanner's old `>800 ExportPublic literals` pin measured the internal globals being removed;
it now requires the profile, public castbar apply and font anchors. The complete literal inventory,
compiler-written global inventory, missing-name assertions and malformed-ledger cases remain enforced.
None of these fixture/pin updates changes profile/parity goldens, startup ceilings, native budgets,
cast-path expectations or the original arena position oracle. That oracle deliberately calls the
existing public geometry-only signature after a direct settings write, with no test invalidation.

The full-graph focus regression tests each consumer independently, including the nil default and
re-enable. Public pool geometry covers boss/arena normal and geometry-only applies, repeated no-ops,
drag, replaced profile tables, dimensions/attachment, errors and reentrancy. Replacing each corrected
provider with its original source makes these behavior tests fail independently.

## Pool descriptors

```text
One parameterized module for the indexed hostile-unit castbar pools.

Boss and arena castbars reuse the generic castbar frame/runtime stack (the
driver owns every spellcast event). What a pool adds is the same for both
kinds: a frame pool, pool-specific anchoring, a unit lifecycle (encounter or
opponent events) and the menu-facing enable/position entry points. Each
kind is a descriptor (MSUF_BossCastbars.lua, MSUF_ArenaCastbars.lua) passed
to Pools.Define, which builds the kind's closures once; the per-cast paths
read only upvalues, never the descriptor.

Descriptor fields:
  kind            castbar config/backend key ("boss", "arena")
  unitPrefix      unit token prefix; unit = unitPrefix .. index
  maxFrames       pool size (client fact, read once)
  hasUnits        false where the client has no such units: the pool is never
                  built and the profile keeps its backend
  framePrefix     global frame name prefix (MSUF_BossCastbar1 ...)
  poolGlobal      global pool table name (MSUF_BossCastbars)
  kindFlag        frame flag other castbar modules read (_msufIsBossCastbar)
  indexField      optional per-frame index field (_msufArenaIndex)
  frameLevelBase  frame level of the bar at index 0 (bars are HIGH strata)
  fallbackY       TOPRIGHT-of-UIParent y offset of bar 1 without a unit frame
  enableKey       legacy general.<key> switch when no backend resolver exists
  db              general keys: offsetX, offsetY, detached, width, height
  layoutDelta     global name of the detached per-index layout resolver
  previewUpdate   global name of the kind's preview refresh
  lifecycle       { event, key, action = "pass"|"unit"|"terminal", prewarm,
                    once, units, supported, terminalWhen, unitFallback }
  scheduleKeys    { pass = "...", prewarm = "..." } (prewarm optional)
  publishPool     function(castbars) exporting the built pool table under
                  the kind's documented global (MSUF_BossCastbars)

Returns the kind's module table (also MSUF.Castbars.Pools.kinds[kind]). Its
ApplyPositionSetting, ApplyEnabled, Stop and SyncLifecycle are the entry
points; the descriptor file exports them under the kind's documented global
names as compatibility aliases.

```

## Runtime frame fields

```text
 Applies normalized cast-state to visible castbar frames.

 Runtime is the shared mutation layer: timer duration, reverse fill, icon/text,
 registration with the castbar manager, interrupt visuals, and stop cleanup all
 pass through here. Keep API reads in Engine/Driver and keep static frame
 construction in Frames.

 Frame-field contract. Fields the runtime writes on a castbar frame (all
 cleared by Stop / ReleaseActive unless noted):
   MSUF_castActive               a cast or channel is currently displayed
   MSUF_durationObj              stable LuaDurationObject driving bar and text
   MSUF_isChanneled              the active cast is a channel
   MSUF_channelDirect            target/focus channel fed directly from events
   MSUF_timerDriven              the client StatusBar timer owns the fill
   _msufActiveDurationSeq/Type   sequence id and cast type of the applied cast
   _msufStableDurationObj        per-frame duration container reused via Assign
   _msufLastIncomingDuration     last duration object handed to StableDuration
   _msufPlainEndTime/_msufRemaining/_msufPlainTotal
                                 plain-number snapshot for Lua fallback paths
   _msufDurationSnapshotUnsafe   duration is secret; no Lua snapshot exists
   _msufCountsDown               bar value counts down (non-unified channel)
   _msufTimerAssumeCountdown     timer-driven bar known to count down
   _msufStripeReverseFill        reverse fill resolved for this cast
   _msufPushbackMS               NeverSecret pushback delay captured per cast
                                 (shared resolver) before the castText write
   _msufCastbarWorkMask          WorkMask bits still owed to the Lua manager
   _msufCastbarGlowTick          glow fade is part of the current work mask
   _msufCastTimeEnabled/_msufCastTimeFormat/_msufCastTimeRev/_msufCastbarConfigMask
                                 compiled cast-time settings for one revision
   _msufLastTimeDecimal/_msufLastTimeTotalDecimal/_msufLastTimeFormat
                                 last Lua time text written (duplicate skip)
   _msufDurationTextBinding/_msufDurationTextConfigured/
   _msufDurationTextFormat/_msufDurationTextDuration
                                 native DurationTextBinding and its last config
   _msufNativeTimeBound          native text binding is enabled on timeText
   _msufNativeTextUnsafe         binding lacks a method; Lua time text instead
   _msufNativeTimerUnsafe        no SetTimerDuration: manager drives only time text + completion (legacy casts: endTime Lua fill)
   _msufNativeCompletionTimer/_msufNativeCompletionDeadline/
   _msufNativeCompletionCallback completion deadline for native casts (a
                                 Kernel-scheduler key: armed flag true/false,
                                 deadline number/false, per-frame callback)
   _msufNativeCompletionUnsafe   the duration turned unreadable; stay on the manager
   The *Unsafe and armed/bound flags are false when clear, never nil: they
   flip every cast, and a key cleared to nil is re-inserted (a table
   regrowth once the collector has seen it) on the next cast.
   _msufCastState/_msufCastPhase published cast-state table and phase
   _msufHideToken                bumped to invalidate pending hide timers
   _msufInUnregister             re-entrancy guard around Hide inside Stop
 Cleared here but written elsewhere: hideTimer/succeededTimer (driver),
 _msufFastText (manager), _msufLastSBValue (driver Lua fill),
 _msufHardStopNoChannelSince (manager hard stop), MSUF_timerRangeSet,
 _msufHardStopNoCastSince, castDuration, castElapsed (legacy). Read-only
 here: _msufCastLifecycleOwned (driver/boss), _msufBarKey, _msufIsBossCastbar,
 _msufTimeTextFollower, _msufForceLuaTimeTextFollower, _msufFocusKickSuppressed.
```

## Pool preview descriptors

```text
 Edit Mode and menu previews of the indexed castbar pools (MSUF_CastbarPools.lua).

 A preview is a non-combat, non-event copy of a pool castbar that mirrors its
 geometry and styling. It never subscribes to UNIT_SPELLCAST events; the live
 pool castbars own live state. One prototype serves every pool kind:
 MSUF_BossCastbars_Preview.lua and MSUF_ArenaCastbars_Preview.lua each pass
 their pool and the preview-only fields to Pools.DefinePreview.

 Read from the pool descriptor: kind, unitPrefix, maxFrames, framePrefix,
 poolGlobal, kindFlag, fallbackY, enableKey, db, layoutDelta.
 Preview descriptor fields:
   namePrefix      global preview name prefix (MSUF_BossCastbarPreview)
   firstUnsuffixed true when slot 1 is named namePrefix itself (boss)
   publishFirstSlot  function(frame) exporting slot 1 under the kind's
                   documented global (MSUF_BossCastbarPreview)
   indexField      per-preview slot index field (_msufBossIndex)
   label           sample spell name
   targetLabel     sample cast target name
   showTargetKey   general key of the cast target name toggle
   showTimeKey     general key of the cast time toggle (test mode)
   testModeKey     general key of the persistent test mode switch

 Returns the kind's preview object (also Pools.previews[kind]); its api table
 holds the bound functions the descriptor file exports under the kind's
 documented global names.
```

## Native GCD lifecycle

```text
 Castbars/MSUF_CastbarGCD.lua - GCD bar (instant casts) on the Player castbar.

 12.1 rebuild of the 5.x GCD bar. Everything time-driven runs C-side:
 UNIT_SPELLCAST_SUCCEEDED (player/vehicle only) resolves the active global
 cooldown as a native duration object (C_Spell.GetSpellCooldownDuration on
 the GCD dummy spell 61304) and binds it to the player castbar through the
 shared castbar Runtime (StatusBar timer + DurationTextBinding). No OnUpdate
 tick exists anywhere in this module; fill and time text advance in C, and
 teardown is one keyed Kernel-scheduler deadline from the plain remaining
 time. When the cooldown values are secret, a hidden Cooldown frame's native
 OnCooldownDone ends the bar instead (a bounded deadline force-clears a stuck
 state); a client without that frame API polls SpellCooldownInfo.isActive,
 which is NeverSecret in the 12.1 API contract. No path creates a C_Timer
 handle, and a readable GCD never builds the SpellCooldownInfo table.

 Unlike 5.x this is haste-correct: the duration object describes the real
 scaled GCD, so no base-GCD approximation and no GetHaste() taint hazard.

 The event is unregistered while the feature is disabled - true zero cost.

 DB keys (Config.Source().general, seeded in State/MSUF_Defaults.lua):
   showGCDBar       - master toggle
   showGCDBarTime   - remaining-time text on the GCD bar
   showGCDBarSpell  - spell name + icon on the GCD bar
```

## Width-source layout ownership

```text
Castbars/MSUF_CastbarAnchors.lua

Pure castbar layout logic: positioning (ClearAllPoints/SetPoint), sizing
(SetWidth/SetHeight) and the "width source" sync machinery that keeps a
castbar's width matched to another frame (the MSUF unitframe, or a Cooldown
Viewer container). No combat-path/secret reads happen here.

This file was previously shipped minified (single-letter names, one statement
per line). It has been de-minified for maintainability; behavior is unchanged.

"Width source" overview:
  A unit's castbar can either use a manually configured width, or match the
  width of another frame ("unitframe" / "essential" / "utility"). When a
  match is configured we hook the source frame's size/show/hide events and
  re-apply the castbar size whenever the source changes. Because the source
  frame may not exist yet at login, a bounded retry schedule keeps trying to
  install the hooks. All of this is deferred out of combat.
```

## Arena descriptor lifecycle

```text
 Live arena castbar pool: the arena descriptor of MSUF_CastbarPools.lua.

 arena1..N follow the opponent lifecycle instead of encounter events.
 ARENA_OPPONENT_UPDATE refreshes the one bar it names (seen, unseen,
 destroyed, cleared and Solo Shuffle round rebinds) and queues a pool pass
 when the token is unknown or secret; ARENA_PREP_OPPONENT_SPECIALIZATIONS and
 PVP_MATCH_STATE_CHANGED queue a pool pass, and a completed match stops every
 bar. The menu-facing globals (MSUF_ApplyArenaCastbarPositionSetting,
 MSUF_ApplyArenaCastbarsEnabled, MSUF_ArenaCastbar_Stop,
 MSUF_ArenaCastbars_SyncLifecycle, MSUF_ArenaCastbars) stay as compatibility
 aliases of the pool module.
```

## Public readiness consumer contract

```text
--------------------------------------------------------------- consumers
MSUF.KickReady: this engine and MSUF's indicator look for consumers that
draw on castbars MSUF does not own (the MSUF Suite's nameplates), handed
out by MSUF_HostAPI.GetKickReady() (Runtime/MSUF_HostAPI.lua). Version 1:
  Register(owner, onChange) -> true    onChange(reason): "readiness" and
      "projection" while the owner is active, "settings" always
      (NotifyConsumers above)
  Unregister(owner)
  HasConsumers() -> boolean   a consumer is registered (MSUF's menu gates the
      nameplate switch on it)
  SetActive(owner, active)    the owner shows readiness on a running cast
  Look() -> table             MSUF's indicator settings (ConsumerLook below)
  RGBA(rawNotInterruptible) -> r, g, b, a    MSUF's border and box color
  FillColors() -> interruptible, notInterruptible, unavailable (ColorMixin)
  SelectColor(readyColor, notReadyColor) -> ColorMixin   readyColor while any
      interrupt is ready; a restricted readiness is selected natively
  SlotCount() -> 0..2         tracked interrupts (0: the class has none)
  Cooldown(index) -> Duration | nil   that interrupt's cooldown, this frame
```

## Consumer look fields

```text
MSUF's indicator settings for a consumer that draws the indicator the way
MSUF's castbars do. One reused table, refreshed from the profile per call:
  show        the nameplate switch
  style       "border" | "box" | "fill" (IndicatorStyle)
  marker, segment             the time marker and shade
  readyR, readyG, readyB, readyA   their color
  outline     the castbar outline's width (MSUF_CastbarStyle.lua's clamp)
  boxSize     0 = the castbar's height (ApplyBoxLayout), then clamped 8..80
  boxAnchor, boxOffsetX, boxOffsetY
  texture     MSUF's castbar texture (the fill style)
```
