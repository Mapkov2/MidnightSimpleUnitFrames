# UF responsibility rationale

Longer original explanations moved from runtime source to preserve the unchanged startup byte limits.
Short contract comments remain beside the code; the complete original paragraphs follow.

## MSUF_UF_Status_GroupRuntime.lua

```lua
    -- Only a PLAYER can be in the raid roster, so a mob target never needs the
    -- roster lookup at all; this keeps rapid target-swaps over mobs cheap.
    -- Bail only on a positive "not a player": an unknown identity has to fall
    -- through, or a frame whose identity was never resolved silently loses its
    -- number.
```

## MSUF_UF_Factory_Anchors.lua

```lua
  -- The name is free text (Custom Anchor Frame), so it can hit any global:
  -- only a region (a UI object with SetPoint: frames, textures, font strings)
  -- can be an anchor. Fonts and animation groups are UI objects without it;
  -- anything else counts as missing.
```

## MSUF_UF_Factory_Anchors.lua

```lua
--- Keep the visible root inside the screen without replacing its configured
--- anchor. Blizzard performs the final clamp in physical screen space, so this
--- remains correct for CDM/custom anchors with a different effective scale.
--- The flag makes this a creation/cold-path cost only.
```

## MSUF_UF_Prediction_Glow.lua

```lua
    -- A protected absorb cannot participate in the optional partial-health
    -- threshold. Its only renderable result is the native full-health stripe:
    -- the holder value gates absorb presence and its cached alpha gates health.
    -- Once both gates are warm, an absorb-data event needs no UnitHealth/
    -- UnitHealthMax recovery at all.
```

## MSUF_UF_Prediction_Glow.lua

```lua
  -- Absorb is immutable for this render pass. Determine its protection state
  -- once instead of re-entering issecretvalue at every native-gate branch.
  -- The steady UNIT_HEALTH follower can pass the plain classification cached
  -- by the absorb-data owner, including false as a meaningful known value.
```

## MSUF_UF_Text_Format.lua

```lua
--- Absorbs come back secret on every 12.x client, and a secret number can be
--- neither compared to zero nor formatted in Lua. TruncateWhenZero is the only
--- tainted-callable API that collapses a zero to an empty string, but it always
--- writes the raw integer - which is why the absorb value ignored "Short
--- numbers" while every other health slot honored it.
---
--- Parking that raw integer in the data section of a hyperlink keeps the zero
--- test (WrapString still drops prefix and suffix for an empty infix) while the
--- client renders the link body only, and the body carries the value formatted
--- exactly like the health slots next to it. The inner WrapString is a plain
--- secret-safe join: a formatted number is never the empty string.
```

## MSUF_UF_Text_Layout.lua

```lua
    -- Keep TOP/FRAMECENTER names optically centered even when the actual unit
    -- name is restricted and cannot be measured. The oversized FontString is
    -- centered behind the clip window, so short and long names share one
    -- secret-safe center without GetStringWidth or string slicing. The warm
    -- name path (Text.RefreshNameCenterClipFit) re-anchors measurable names
    -- that overflow the window so only the configured clip side is cut instead
    -- of both ends; this cold pass replays its last verdict without measuring.
```

## MSUF_UF_Text_Runtime.lua

```lua
    -- Flat inline write: a group frame with a single percent-only power
    -- slot writes its text synchronously in the same compiled route pass as the
    -- bar (which just published the plain percent to rt._dispatchPowerPercent),
    -- consuming that value with the existing bucket dedup. This drops the
    -- deferred dirty-text machinery (MarkDirty -> C_Timer ticker -> FlushDirtyText
    -- -> per-frame state re-fetch) that an inline SetFormattedText
    -- never pays. Any other text shape keeps the deferred coalescer.
```

## MSUF_UF_Elements_Status.lua

```lua
-- Registration data, read once at load by RegisterStatusIndicator and never
-- touched again. Field meanings:
--   name / key            element name and spec.status key
--   events / unitlessEvents   static unit / unitless event lists
--   getEvents / getUnitlessEvents   resolvers (spec, frame) for dynamic lists
--   playerUnitlessEvents  unitless list that only the player frame receives
--   update / hide         updater (frame, status[, event, seedHP]) and the
--                         region field(s) hidden on Disable
--   noGroup / playerOnly  IsEnabled gates
--   routes                declared engine event and lifecycle participation
--   updateWithEvent       forward (event, seedHP) into the updater
```

## MSUF_UF_Elements_Prediction.lua

```lua
-- Over-absorb glow with protected values (Midnight absorbs, and often health,
-- are secret). The prediction calculator's MissingHealth clamp reports whether
-- the absorb overflows the missing health, incoming heals counted: `clamped`,
-- approximately the plain rule (hp + incoming + absorb >= max) as a possibly
-- secret boolean. Incoming heals: the plain path adds the player's own
-- (ReadIncomingHeals) unless "all healers" is on; the clamp subtracts the
-- calculator's incoming heals, most likely the all-units amount (the healer
-- passed to UnitGetDetailedHealPrediction only selects amountFromHealer;
-- UnitDocumentation, UnitHealPredictionCalculatorAPIDocumentation); Blizzard's
-- rule (CompactUnitFrame.lua:1257) adds all incoming heals less heal absorbs,
-- so the plain path shares only its >= with it.
-- The calculator documents `clamped` as "in excess of the clamp boundary"
-- (UnitHealPredictionCalculatorAPIDocumentation). When the health and
-- incoming-heal inputs agree with the plain path's, an absorb that exactly
-- fills the missing health is the case where it differs from the plain rule's
-- >=; no secret-safe API reports that edge. Its inputs need not agree: see
-- the next paragraph on its health source. Without the full-health
-- stripe a step curve keeps the plain rule that full health shows no partial
-- glow; with the stripe, `clamped` is already the union of both, because at
-- full health every positive absorb is clamped.
--
-- The step curve reads PREDICTED health, like the plain path, the stripe and
-- the health bar (UnitHealthPercent usePredicted): the calculator's own health
-- source is undocumented, so it supplies only the overflow flag. A health tick
-- costs four native calls (2026-10-02 raid trace: six, about 30 % of core CPU):
-- one calculator fill, its flag, the curve, and one SetAlphaFromBoolean that
-- takes the curve result as its alphaIfTrue (SecretArguments
-- AllowedWhenTainted, SimpleRegionAPIDocumentation), so the texture alpha is
-- clamped AND partial in one sink and the holder stays at full alpha. The glow
-- texture handle is the one EnsureOverAbsorbGlow created.
-- Lua never compares, adds or branches on a protected value here.
```

## MSUF_UF_Elements_Prediction.lua

```lua
-- Overflow host for anchor mode 4.
--
-- Mode 4 overlays keep the HP bar's full scale (value/max over one bar width) so
-- the heal/absorb segment stays proportional, which means an amount larger than
-- the missing health would otherwise draw arbitrarily far past the frame -- into
-- the neighbouring group frame. Blizzard bounds the same overflow at
-- MAX_INCOMING_HEAL_OVERFLOW (1.05) by clamping the amount, but that arithmetic
-- needs current health, which is a secret value here. A clipping host reaches
-- the identical result natively: the bar keeps its true scale and the client
-- trims whatever leaves the allowance. The cross axis is left effectively
-- unclipped so stripe heights and vertical offsets are never cut.
```

## MSUF_UF_Elements_Prediction.lua

```lua
-- FLAT prediction writer for the plain-bar archetype: any combination of an
-- incoming-heal bar, an absorb bar, and a heal-absorb bar with STATIC anchors
-- and NO over-absorb overlay/stripe and NO mixed follow-clamp. This is exactly
-- the flat absorb+heal-prediction shape. It skips the general
-- ApplyPredictionValues state machine (per-lane show/refresh branch pairs,
-- follow-layout checks, over-absorb glow) and does the one thing a data event
-- changes: read the dirty lane(s) from the mask and write the bar(s) with
-- ShowValue's own dedup. Only the lanes flagged in the mask are read, matching
-- the general path's refresh gating so a heal event never reads the absorb API
-- and vice versa. Compiled onto the frame only when the archetype matches.
```

## MSUF_UF_Elements_Prediction.lua

```lua
  -- Flat archetype (plain heal/absorb bars, no health-gated glow/stripe): the
  -- writer is cheaper than the coalescer's own queue bookkeeping + OnUpdate
  -- driver arm/disarm, so a same-frame burst that "collapses" to one flush
  -- still costs more queued than just flushing each lane on the spot. Measured
  -- net-negative for this archetype -- so render this lane synchronously, which
  -- is exactly the flat per-event model. Every bar write is value-deduped
  -- downstream, and the flush touches only StatusBar values (combat-safe).
```

## MSUF_UF_Elements_Prediction.lua

```lua
  -- Steady-tick dedupe (pure overlay, plain absorb). The overshield verdict is
  -- a function of the exact health percentage and absorb amount. Fractional
  -- health changes can cross the spill threshold inside a display bucket.
  -- Skip only an identical input, without reimplementing the show
  -- test: a cache miss falls through to the authoritative UpdateOverAbsorbGlow,
  -- which owns the full-health / partial-spill decision. Every prediction data
  -- event clears this key (ApplyPredictionValues) so the next tick re-syncs.
  -- CompilePredictionRuntime binds this function only to non-stripe frames.
```

## Additional startup rationale

### MSUF_UF_Text_Format.lua

```lua
--- Format a percent value into "42%" or "42" (respects hidePercentSymbol).
--- Handles secret percent (rare) via C_StringUtil.RoundToNearestString. The
--- second result is a plain boolean "has a percent": a secret text may be
--- concatenated but never truth-tested.
```

### MSUF_UF_Text_Format.lua

```lua
  -- A single-value slot has no runtime format dispatch or unused value needs.
  -- Keep NUM_OPTS live inside the abbreviated writers: changing number style
  -- must affect existing compiled slots without a new frame/spec application.
```

### MSUF_UF_Text_Format.lua

```lua
--- Global abbreviation style: nil lets the client decide (locale-dependent),
--- a table switches the C abbreviator to MSUF's locale-independent breakpoints.
--- Runtime/MSUF_NumberFormat.lua pushes it on the cold path, so every call site
--- below stays one direct C call with a constant second argument. Only the
--- short/abbreviating calls take it - BreakUpLargeNumbers never does.
```

### MSUF_UF_Text_Format.lua

```lua
--- UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua
--- Allocation-light formatting helpers for unitframe text strings.
---
--- Called from frequent UNIT_* events, so number formatting, fallback strings,
--- and secret-safe branches stay local and avoid per-refresh table churn.
```

### MSUF_UF_Text_Runtime.lua

```lua
  -- Static text still needs its initial color after a spec/region replacement.
  -- Resource identity (including Player's displayed Mana) stays with the same
  -- native reader as the general runtime whenever no public bar value exists.
```

### MSUF_UF_Text_Runtime.lua

```lua
    -- Same contract the power bar applies (MSUF_UF_Elements_Power.lua SetColor):
    -- metadata counts as known only once a read actually produced a resource.
    -- The flag alone means "already asked", and PowerColor answers a known but
    -- empty pair with Mana, claiming a resource this unit never reported.
```

### MSUF_UF_Text_Runtime.lua

```lua
  -- Single-unit frames never see the synthetic MSUF_UNIT_IDENTITY reasons:
  -- AddIdentityLifecycleHandlers routes their swaps into the identity path
  -- under the raw Blizzard event name. Without these the cached power type
  -- outlives the unit it was read for, and a frame whose power bar is disabled
  -- has no bar-fed seed to correct it.
```

### MSUF_UF_Text_Runtime.lua

```lua
--- UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua
--- Runtime dispatcher for unitframe text slots.
---
--- Decides which text slots refresh for each unit/event, keeps combat-safe
--- visibility updates isolated, and separates secret-value branches from cache hits.
```

### MSUF_UF_Text_Layout.lua

```lua
-- The separator follows the rendered end of a left-justified name. A
-- self-sized name ends at its own right edge; a bar-anchored name spans the bar,
-- so the invisible auto-width twin (_msufNameAnchorText, EnsureNameAnchorProxy)
-- marks its glyph end. Anchoring to that edge lets the UI engine carry a
-- restricted name's geometry: GetStringWidth() is SecretWhenAnchoringSecret,
-- and SetPoint and the anchor cache below must never see that secret width.
```

### MSUF_UF_Elements_Prediction.lua

```lua
--- Reseed live prediction values after Blizzard has finalized world/unit data.
--- This is a cold lifecycle path: it touches only visible frames with an active
--- Prediction element and does not rebuild specs, layouts, or event routing.
```

### MSUF_UF_Elements_Prediction.lua

```lua
-- The HP bar's own size changes only on layout/apply -- never on a combat
-- event -- so measuring it inside the per-event layout guard is pure overhead.
-- Measure once and let the widget invalidate the cache itself. Two independent
-- invalidation sources keep this exact: the bar's own OnSizeChanged (covers any
-- resize, including live Edit Mode drags) and Prediction.Apply (deterministic
-- for every config/layout apply, and the path that installs the hook).
```

### MSUF_UF_Elements_Prediction.lua

```lua
-- SetParent resets a frame's strata and level to the new parent's, so this must
-- run AFTER any re-parenting and re-apply unconditionally when the parent just
-- changed -- otherwise the cached level below still reports the wanted layer
-- while the widget sits one level lower, and the layout guard never repairs it.
-- Overflow (mode 4) re-parents the overlay from the HP bar to the frame, which
-- is exactly where that mismatch drops the bar behind neighbouring group frames.
```

### MSUF_UF_Elements_Prediction.lua

```lua
-- Heal/absorb prediction element.
-- Owns incoming heal, absorb, and heal-absorb overlays for unitframes. The code supports
-- both modern detailed prediction APIs and older fallbacks, and it must tolerate secret unit
-- tokens without leaking or doing math on protected values.
```

### MSUF_UF_Elements_Prediction.lua

```lua
--- UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua
--- Heal/absorb prediction element for unitframes.
---
--- WoW prediction APIs can return unknown/secret values during protected states;
--- native StatusBars and clip geometry consume them without unsafe Lua math.
```

### MSUF_UF_Elements_Status.lua

```lua
-- Unitframe status indicator element.
-- Owns level/classification/PvP/ready-check/role/raid-marker style icons for normal unit
-- frames. This is an event-hot path, so helpers prefer cached unit state, secret-safe reads,
-- and cached region mutation instead of rebuilding textures every event.
```

### MSUF_UF_Factory.lua

```lua
-- Out of combat external providers move one shared unitframe proxy, plus the
-- independent Group/ClassPower consumers, natively with zero recurring work.
-- PLAYER_REGEN_DISABLED delivers before lockdown: sever those links there so
-- nothing can passively move a protected chain mid-fight, then restore them
-- once on the existing post-combat driver. If the event ever arrived after
-- lockdown, freezing is skipped and the frames simply stay live.
```

### MSUF_UF_Text_Common.lua

```lua
  -- Bucket non-secret health percentages to avoid text-color churn on every
  -- health tick while preserving exact updates for secret/runtime-only values.
  -- With native secrets present, plain values are detected via issecretvalue so
  -- fully-readable units keep the bucket fast path; secret values always take
  -- the exact update below.
```

### MSUF_UF_Text_Common.lua

```lua
-- UF text common export shim.
-- Pulls the shared bar/text helper bundle into local symbols for legacy split modules. Keep
-- behavioral changes in MSUF_UF_Elements_BarsCommon.lua so the text runtime stays consistent.
```

### MSUF_UF_Factory_Anchors.lua

```lua
-- Unitframes that share one foreign provider also share one MSUF-owned proxy.
-- The proxy follows the provider natively out of combat (no polling or Lua
-- callbacks), while every protected unit root remains attached to the stable
-- MSUF-owned frame. At the combat edge only this one rectangle has to be
-- materialized on UIParent, regardless of the number of unit consumers.
```

### MSUF_UF_Factory_CooldownWidth.lua

```lua
-- Rebind consumers after a supported provider changes while out of combat.
-- Unitframes keep their points on a stable shared proxy, so an identity change
-- only reattaches that proxy; Group/ClassPower retain their own direct links.
```


## Retained phase contracts

### MSUF_UF_Elements_Prediction.lua

```lua
-- Five shared absorb-only writers cover static/follow anchors and glow/stripe
-- combinations beyond the existing flat writer. The cache guard is identical
-- to the general drain: identity, disable and reseed still use UpdateFull.
-- A valid plan for this archetype always reads and displays absorb, so there
-- are no heal lanes or six plan flags to unpack on each event.
```

### MSUF_UF_Elements_Prediction.lua

```lua
-- Data events enter only through the compiled queue. Apply installs this
-- pointer for a live non-test plan, while Disable/Suspend clears it. Consume
-- the numeric dirty mask directly instead of re-entering UpdateFull's cold
-- unit/config/test/event-plan state machine on every rendered-frame drain.
-- Recovery alone falls back to UpdateFull so a stale/missing cache can rebuild
-- the authoritative runtime before the next hot drain.
```

### MSUF_UF_Elements_Prediction.lua

```lua
  -- The live health-bar size -- never a stale spec width -- owns prediction
  -- geometry. Authoritative refreshes (UNIT_MAXHEALTH / UNIT_CONNECTION / full
  -- plan) therefore drop the cached measurement so both overlay types repair
  -- themselves here, exactly as they did when every event measured natively.
  -- High-frequency absorb/heal data events keep serving from the cache, which
  -- the bar's own OnSizeChanged invalidates the moment it actually resizes.
```

### MSUF_UF_Elements_Prediction.lua

```lua
  -- This compiled non-stripe route opens for the plain-positive absorb verdict
  -- published by the data-event owner, and for a protected absorb while the
  -- partial overlay is on: that one renders through the calculator flag and
  -- must never reach the plain dedupe compare below. With the glow anchored
  -- for the live layout, a protected tick is exactly the calculator render;
  -- anything else takes the authoritative UpdateOverAbsorbGlow.
```

### MSUF_UF_Elements_Prediction.lua

```lua
  -- The flat baseline renders absorb synchronously on the event (one UpdateAbsorb
  -- call, no render-frame driver). Opt-in parity: flush the accumulated mask
  -- immediately instead of queuing onto the OnUpdate coalescer. Every bar write
  -- downstream is value-deduped, so a same-frame burst still collapses to the
  -- writes that actually changed -- it just drops the per-frame driver arm +
  -- queue bookkeeping. Default keeps the coalescer (off unless the test toggle
  -- sets _G.MSUF_GF_PredictionSync).
```

### MSUF_UF_Elements_Prediction.lua

```lua
-- Blizzard's CompactUnitFrame defers the three expensive prediction payload
-- events and resolves them at most once per rendered frame. Keep the same
-- contract here with a dedicated, allocation-free hot path: two reusable
-- arrays allow events raised during a flush to land in the next batch without
-- extending the active loop or allocating closures/tables per event.
```

### MSUF_UF_Elements_Prediction.lua

```lua
  -- No reseed-cache bookkeeping here: the cache fields are read only by the
  -- health-gated glow/stripe and general reseed paths, none of which run for a
  -- flat frame (no health-dependent visual). A cold general refresh finding the
  -- cache unset simply reseeds fully -- the safe direction -- so keeping it
  -- unset costs nothing and saves three field writes + an issecretvalue on
  -- every per-event flush, which is the whole point of this archetype.
```

### MSUF_UF_Elements_Prediction.lua

```lua
  -- Resolve which lanes this event touches before doing any work: the mask
  -- selects heal(1)/absorb(2)/heal-absorb(4), gated on the lane being active
  -- and its bar existing. Reading the plain HP max is deferred until we know at
  -- least one lane will render -- and read at most once, with no per-call
  -- closure (this is a per-member, per-event hot path; a boxed upvalue frame
  -- here is pure GC churn a flat writer never pays).
```

### MSUF_UF_Elements_Status.lua

```lua
--- Player stance / form / aura text from the native stance bar. Data comes
--- from MSUF.UFStance (spellID -> name cache, immutable per session); the
--- reads are the player's own action-bar state, so they stay valid in combat
--- and the text updates live while stance-dancing. Region creation, font,
--- color and anchoring are owned by ApplyConfiguredRegions - this only moves
--- the text. Lives on Status, like the per-indicator updaters on Runtime.
```

### MSUF_UF_Elements_Status.lua

```lua
  -- 12.x SetRaidTargetIconTexture is texture:SetSpriteSheetCell(): it slices whatever texture is
  -- currently set and moves the real tex coords behind the SetTexCoord dedupe cache. Re-assert the
  -- stock marker sheet first (cached no-op while it is already set, and required after a custom
  -- icon or pack texture was on this region), then drop the coord cache so a later custom/pack
  -- application cannot be dedupe-skipped against coords the sprite-cell call changed underneath.
```

### MSUF_UF_Elements_Status.lua

```lua
--- Lay out the round level medallion behind the existing level text. Forever
--- and clients that expose its atlas use the native art; older clients use the
--- bundled circle mask plus gold relief ring so the style remains available.
--- This is cold configuration work: UNIT_LEVEL only toggles the already-built
--- texture with the text and never recreates or reanchors it.
```

### MSUF_UF_Text_Layout.lua

```lua
-- A separate alpha gate on the existing overlays preserves slot visibility,
-- clipping, text opacity and secret-backed value/color writers. Blizzard live
-- TextStatusBar.lua uses the same enter/leave lifecycle for status text.
-- Hooks are installed once, only for frames that opt in. No polling or DB reads
-- in the mouse path; disabled frames retain no active overlay references.
```

### MSUF_UF_Text_Layout.lua

```lua
  -- Shortened names render inside a fixed maxChars-wide window, so the window
  -- edge is not the glyph edge for names that fit it. Hang the twin off the
  -- same window corner the visible run starts from; its auto-sized far edge
  -- then coincides with the rendered glyphs without measuring the (possibly
  -- secret) name. Status anchoring falls back to the window's cut edge only
  -- while the warm fit reports a real overflow.
```

### MSUF_UF_Text_Layout.lua

```lua
--- UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua
---
--- Cold/warm text layout and FontString apply code. Text formatting/runtime
--- lives in the companion text modules; this file positions FontStrings, applies
--- font/color/layer settings, and rebuilds compiled text runtime after layout
--- changes. Hot text updates should use the compiled functions, not layout work.
```

### MSUF_UF_Factory_Anchors.lua

```lua
-- Materialize the current screen point on UIParent. Out of combat MSUF keeps
-- live SetPoint links to external providers so consumers follow them 1:1; this
-- runs at the combat edge (PLAYER_REGEN_DISABLED delivers before lockdown) to
-- sever that link for the duration of a fight. Callers position the frame
-- logically first, so old profile priorities, offsets, scaling and clamping
-- remain authoritative.
```

### MSUF_UF_Factory_Spawn.lua

```lua
-- Unit-frame tooltip on hover. The UFCore refactor (f17590e5) split the
-- mouseover highlight into MSUF.Highlight and dropped the tooltip trigger that
-- used to live beside it, so unit-frame tooltips stopped firing entirely. These
-- handlers restore it and stay branch-thin: all mode/anchor/dedupe work and the
-- NEVER fast-path live in Tooltips.ShowUnit, and the unit token is a cached
-- plain field (no secure GetAttribute per hover).
```

### MSUF_UF_Factory_Spawn.lua

```lua
--- Thank you R41z0r
--- 12.1 extends unit ping target information with `isPlayerResource`. Blizzard
--- deliberately keeps the choice of health versus the occasionally supported
--- mana callout inside C_PingSecure; addons can only opt the player frame into
--- that native resource decision. These callbacks run only for an actual ping
--- gesture -- there is no event, timer, or steady-state combat work.
```

## Retained-body and measurement notes

Bodies that stay in a coordinator do so because a forwarding adapter measurably added
instructions on a real path:

- `UpdateOverAbsorbGlow` keeps the original statement order. Phase dispatch added 13 to 25
  instructions per exported force update; `Prediction_Glow` owns only holder construction and
  positioning.
- `UpdateBossNumber` keeps its inline `type` guard. Routing it through `IsCallable` added six
  instructions per call. Status, Text Runtime and Factory keep the original local `type` capture
  for every optional-callable boundary, so the binding survives a later change of the global.
- The Factory layout callback calls `ScheduleCooldownAnchorMask` directly with the configured
  mask. A forwarding helper cost three instructions per layout event.
- `UpdatePowerRuntime` keeps the plain power reads and the deduplication inline: an added
  `UpdatePlainPowerText` call charged the cached early returns. `WritePowerValueSlots` owns the
  general slot writer and receives the secret classification and reader bindings.
- The name updater's missing-unit and configured-hidden branches share one cleanup instead of a
  helper that added four instructions per call.

Cost measurements run in two separate native Lua processes. The first counts addon VM
instructions and addon-attributed client calls under a count hook. The second installs no hook and
reads `collectgarbage("count")` on a fresh coroutine with the 192-value sampler argument area after
a full collection, twice, and keeps the smaller delta. Heap minima carry no tolerance. When a
heap difference appears between two trees, rule out these artifacts first: a count hook grows
Lua 5.1's shared concatenation buffer from 65 to 68 bytes, and the interpreter stack resizes in
16-byte value slots depending on the caller context. The name-proxy layout route measured
either 24.74 or 25.33 KiB on TBC and Mists across runs of the same source; its pin is the larger
value.

### Retained power metadata explanations

```lua
  -- One client read per dispatch: an identity or tick refresh below already
  -- asked, and a second ask in the same event returns the same answer.
    -- A bar-fed identity event already carries authoritative metadata for the
    -- new unit, so seeding it over the old values is enough. Only a frame with
    -- no power bar arrives here empty-handed, and for it the cached type still
    -- belongs to the previous unit behind this token: drop it and read once.
    -- Power already resolved this metadata for a normal value tick. Preserve
    -- the seed for text-only/bar-missing and unknown/secret payloads, but do
    -- not rewrite four identical cache fields on every bar-fed update.
    -- "Known" with nothing cached is a failed read, not knowledge: UnitPowerType
    -- returns nothing for a restricted unit token, and PowerColor trusts the
    -- known flag and settles on Mana. Retry here, where the gate already only
    -- opens on colour events, never on a value tick.
    -- Same contract the power bar applies (MSUF_UF_Elements_Power.lua SetColor):
      -- Nothing to colour by, so render the configured text colour instead of
      -- guessing: what these slots show with colour-by-type switched off.
```
