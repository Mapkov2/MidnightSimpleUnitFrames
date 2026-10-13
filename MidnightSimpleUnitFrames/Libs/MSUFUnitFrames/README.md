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
