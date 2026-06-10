# MSUF UnitFrame Shapes - Lessons Learned

Status: experiment reverted.

This document captures the lessons from the failed UnitFrame shape experiment
so the same mistakes are not repeated.

## Goal

The target visual was a real circular UnitFrame similar to the reference image:

- Health as a circular area fill, defaulting to bottom-to-top like a fishbowl.
- Optional health ring around the area.
- Power, class power, prediction, borders, aggro and preview/edit mode aligned
  to the same circular geometry.
- UnitFrame-only. GroupFrames must stay untouched.
- BAR mode must keep the existing hot path and performance profile.

## What Failed

The implementation tried to retrofit circles into the existing rectangular
UnitFrame frame tree:

- Existing rectangular frame bounds stayed active.
- Health and power backgrounds still had rectangular ownership and layout.
- Masked StatusBars and Cooldown radial regions were mixed in the same frame
  hierarchy.
- Preview/edit bounds were derived from the old rectangular UnitFrame size.
- Rounded-frame and border systems had to be suppressed after the fact.
- Prediction, power, class power and borders became separate special cases.

The result was not a real circular UnitFrame. It was a rectangular UnitFrame
with circular textures inside it. In game this produced visible rectangular
backgrounds, wrong mover bounds and inconsistent preview/runtime geometry.

## Do Not Repeat

Do not build Circle/Arc by patching the existing rectangular Health/Power bars
in place.

Do not use the circle mask texture as a visible background texture. It must only
be used as a mask.

Do not let the old UnitFrame root remain the visual geometry owner for circle
mode. If the visual is circular, the visible shape container must own the size,
layers, hit/mover geometry and child layout.

Do not add a parallel hidden shape path while the rectangular path is still
visible or still participates in layout.

Do not try to make every dependent feature work in one pass. Prediction,
Power, ClassPower, borders, aggro, preview and edit mode need to be integrated
one layer at a time.

## Better Future Design

Use a clean shape-specific visual root while preserving the existing runtime
event/update model.

Recommended V1:

- Keep the existing rectangular BAR path unchanged.
- When `shapeMode == CIRCLE`, create a dedicated square visual container:
  `shapeRoot` sized `shapeSize x shapeSize`.
- Move the visual Health surface into `shapeRoot`.
- Hide the rectangular Health/Power background regions completely for circle
  mode.
- Make mover bounds and preview bounds use `shapeRoot`, not the old frame
  width/height.
- Implement only Circle AREA bottom-to-top first.
- Add the health ring only after AREA is stable.
- Add Power after Health geometry is correct.
- Add Prediction after Health and Power are correct.
- Add ClassPower after Prediction.
- Add ARC last.

The rectangular UnitFrame can still exist as the logical owner for events,
text anchors and database identity, but it must not be the visible silhouette in
circle mode.

## Performance Rule

BAR mode must not create shape regions and must not call shape update code.

Circle mode may use additional regions, but only in cold/layout paths. Runtime
value updates should update exactly the active native visual region. No Lua
OnUpdate, no segment emulation, no parallel hidden statusbar updates.

## Preview And Edit Mode

Preview and Edit Mode must use the same compiled geometry as runtime.

If runtime uses `shapeRoot`, preview and edit mode must also use a square
shape-root equivalent for:

- visible frame bounds
- hover outline
- mover handles
- detached power mover
- text/portrait/aura relative placement

If the preview still shows the old rectangular UnitFrame bounds, the runtime
implementation is not complete.

## Validation Checklist

Do not call the feature done until all of these are true in game:

- Circle silhouette has no visible rectangular background.
- Health AREA fills bottom-to-top.
- 40%, 80% and 100% health all look correct.
- Ring does not pixelate or expose texture edges.
- Power attached/detached does not create rectangular remnants.
- Aggro/border/highlight follows the circle.
- Prediction/test mode follows the circle.
- Preview and edit mode bounds match the runtime circle.
- BAR mode remains visually and behaviorally unchanged.

## Reference: oUF_Diablo / rModelOrbTemplate

Reference archive inspected:

- `oUF_Diablo-12.07.zip`
- Addons inside archive: `oUF_Diablo`, `rModelOrbTemplate`,
  `rModelOrbConfig`
- License: MIT

The important implementation is not in oUF itself. oUF only drives value
updates. The visible orb is a separate `rModelOrbTemplate` frame.

### Actual Orb Structure

`rModelOrbTemplate.xml` defines one fixed square 256 x 256 virtual frame:

- `FillingStatusBar`
- `ClipFrame`
- `ClipFrame.ModelFrame`
- `OverlayFrame`
- background and overlay textures

The visible silhouette is owned by this square orb template, not by a normal
rectangular health bar.

The `FillingStatusBar` is a normal vertical StatusBar with a pre-rendered orb
fill texture. The texture itself already has transparent circular alpha. That
means WoW only has to clip a normal vertical status bar; it does not have to
compute a circle at runtime.

The `ClipFrame` has `SetClipsChildren(true)` and is anchored to the current
StatusBar texture bounds. This makes the model scene and spark follow the fill
height. The spark is anchored to the top of the statusbar texture, so it moves
with the liquid line.

The `OverlayFrame` draws gloss, glow, low-health glow and spark effects over
the fill. Only the spark uses an additional mask.

### Data Path

In `oUF_Diablo/style/player.lua`, `self.Health` and `self.Power` are still oUF
elements, but they are not the visible orb. They are logical update elements.

The visual update is:

- oUF health update fires.
- Health `PostUpdate` reads percent.
- It calls `orbFrame.FillingStatusBar:SetValue(percent, interpolation)`.
- Power does the same with `UnitPowerPercent`.

This separation is the key lesson for MSUF:

- logical element receives the event
- visible shape is a dedicated child/root
- the old rectangular bar does not stay visible

### Absorb Path

Custom absorbs use the same idea:

- create an invisible vertical StatusBar
- anchor a clipping frame to the StatusBar texture bounds
- draw a full 256 x 256 absorb texture inside the clip frame

The absorb texture is not recalculated or segmented. The StatusBar texture is
only a native clipping driver.

### Why This Works

It avoids the failure mode from the MSUF experiment:

- no old rectangular health background remains visible
- the mover is a 256 x 256 square around the orb
- fill is a normal C-side StatusBar update
- the circle comes from alpha-tested art, not from Lua geometry
- overlays are built for the same square coordinate system

### MSUF Fit

For MSUF, the closest safe design is an `OrbRoot` path, not a generic shape
patch inside the existing bar path.

Recommended MSUF V1 based on this reference:

- keep BAR exactly as it is
- add `shapeMode = ORB` or `CIRCLE_ORB` rather than reusing the failed generic
  `CIRCLE`
- create `frame._msufOrbRoot` sized `shapeSize x shapeSize`
- create `orbRoot.healthDriver` as the logical native StatusBar fill
- use MSUF-owned 256/512 orb alpha textures for fill, background, gloss and ring
- hide rectangular health/power backgrounds while ORB is active
- anchor text, portrait, aura clusters and status icons to `orbRoot`
- make preview/edit movers use `orbRoot` bounds
- add power as either a second orb or an explicit attached ring after health is
  stable
- add prediction by the same invisible-driver-plus-clip method

Do not start with ARC, ring power, detached power and class power all at once.
Start with one working health orb and correct bounds.

### Open Technical Questions For MSUF

- Whether to include orb assets in MSUF or generate neutral MSUF-native orb
  textures.
- Whether ModelScene is acceptable for MSUF. It looks good but is heavier and
  more specialized than a pure texture orb.
- Whether the orb should be a new visual mode only for player/target first, or
  all UnitFrames.
- How to map existing text/auras/portrait anchors when the visible owner is a
  square orb but the logical UnitFrame still has old dimensions.

