# MSUFUnitFrames embedding

MSUFUnitFrames is the unit-frame engine, embedded directly by its consumer. It
intentionally has no standalone TOC and does not use LibStub. Every host
therefore receives its own element registry and frame list.

Add the framework metadata and XML to the consumer TOC:

```toc
## X-MSUF-UnitFrames-Prefix: MyAddon

Libs\MSUFUnitFrames\MSUFUnitFrames.xml
Layout.lua
```

`X-MSUF-UnitFrames-Prefix` names the frames the engine creates
(`UF.FrameName`). The framework publishes no global of its own. Consumer code
reaches it through the private addon namespace:

```lua
local _, ns = ...
local UnitFrames = ns.MSUFUnitFrames
```

The handle carries the frame-side surface:

- `RegisterElement(name, element[, traits])` registers a custom element.
  Element tables can provide `Create`, `Apply`, `Update`, `Enable`, `Disable`,
  `GetEvents`, and `GetUnitlessEvents`.
- `AttachFrame(frame[, spec, mask])` runs the engine's spec apply on a frame
  the host created, `DetachFrame(frame)` releases it and `GetFrame(unit)`
  answers the frame attached for a unit.

Styles, spawning, secure headers, services and host values were removed in
7.0: nothing called them. A host creates its own frames and attaches them.

The framework XML is loaded from the host's TOC, so Blizzard's addon profiler
attributes its work to that host. Embedding removes a separate framework addon
row; it does not make executed CPU time disappear.

The engine namespace `ns.UF` also owns the compile-time extension contracts.
Elements declare `Routes` alongside their event providers: `basic`, `events`,
`identity`, `identityBar`, `forceUpdate` and `reshow` choose their lifecycle
plans. `CompileNeeds` publishes scalar requirements before `SelectNeeds`
resolves the updater, so a text layout never switches another element's
implementation. Dispatch samples are consumed within their original event.

`UF.RegisterRoute(name, compile, priority, events)` registers a cold route
compiler. It receives the frame, event, handler list and optional target and
returns a route or nil for the generic fallback. Health, power, visibility
and threat own their specializations; cached plans and unrolled closures
remain immutable and are never compiled on a value tick.

`UF.RegisterDecorator(name, descriptor)` accepts `Apply`, `OnIdentity`,
`OnShow`, `OnVisualChanged` and `OwnsMask`. Owners deliver their original
triggers through `UF.Surface`; element transactions, identity reseeds and
OnShow add no automatic effect apply. Visual callbacks preserve their full
argument list. Mask ownership remains queryable while combat defers a disabled
owner's cleanup. `Surface.IsDecoratorActive(name)` exposes activity without
reading another owner's descriptor. `Surface.SetEvent` owns lazy native event
recipes and invokes the dedicated `OnEvent(driver, event, unit)` callback;
`OnIdentity` always takes a unit frame. A factory batch invokes the original
scoped texture refresh after its frames are ready. Existing rounded globals
remain compatibility adapters for callers outside the unit engine.
