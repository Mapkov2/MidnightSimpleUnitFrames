# MSUFUnitFrames embedding

MSUFUnitFrames is a stateful unit-frame framework embedded directly by its
consumer. It intentionally has no standalone TOC and does not use LibStub.
Every host therefore receives its own styles, elements, objects, headers,
services, and factory queue.

Add the framework metadata and XML to the consumer TOC:

```toc
## X-MSUF-UnitFrames: MyAddonUnitFrames
## X-MSUF-UnitFrames-Prefix: MyAddon

Libs\MSUFUnitFrames\MSUFUnitFrames.xml
Layout.lua
```

The global name must be project-specific. Consumer code should normally use the
private addon namespace instead:

```lua
local _, ns = ...
local UnitFrames = ns.MSUFUnitFrames

UnitFrames:RegisterStyle("Default", function(frame, unit)
  -- Create the regions used by the host's registered elements.
  return { unit = unit, enabled = true }
end)

UnitFrames:SetActiveStyle("Default")
UnitFrames:Factory(function(self)
  self:Spawn("player")
  self:Spawn("target")
end)
```

Custom elements should use `RegisterElement(name, element[, traits])`. Element
tables can provide `Create`, `Apply`, `Update`, `Enable`, `Disable`,
`GetEvents`, and `GetUnitlessEvents`. `AddElement` is a smaller compatibility
helper for an oUF-shaped update/enable/disable trio.

`X-MSUF-UnitFrames-LegacyGlobals: 1` is reserved for the MSUF host adapter. A
third-party consumer should not enable it: otherwise old `MSUF_*` compatibility
globals would be published deliberately.

The framework XML is loaded from the host's TOC, so Blizzard's addon profiler
attributes its work to that host. Embedding removes a separate framework addon
row; it does not make executed CPU time disappear.
