local _, ns = ...

local Framework = ns and ns.MSUFUnitFrames
local UF = ns and ns.UF
if not (Framework and UF) then
  error("MSUFUnitFrames API loaded before init.lua.", 2)
end

local type = type
local pairs = pairs

local function Fail(message, level)
  error("MSUFUnitFrames: " .. message, (level or 1) + 1)
end

local function Require(value, label, wanted)
  if type(value) ~= wanted then
    Fail(("%s must be a %s, got %s."):format(label, wanted, type(value)), 2)
  end
end

-- Elements a host registered through Framework:RegisterElement; AttachFrame
-- enables them on every frame that holds their region.
local publicElements = {}

local function DefaultElementMask(frame)
  local mask = {}
  for name in pairs(publicElements) do
    mask[name] = true
  end
  local order = UF.elementOrder
  if type(order) == "table" then
    for index = 1, #order do
      local name = order[index]
      if frame[name] ~= nil then mask[name] = true end
    end
  end
  return mask
end

function Framework:RegisterElement(name, element, traits)
  Require(name, "element name", "string")
  Require(element, "element", "table")
  if UF.elements and UF.elements[name] ~= nil then
    Fail(("element %q is already registered."):format(name), 2)
  end
  traits = type(traits) == "table" and traits or {}
  if traits.apply == nil then traits.apply = true end
  if traits.events == nil then traits.events = true end
  if traits.defaultApply == nil then traits.defaultApply = true end
  if traits.forceUpdate == nil then traits.forceUpdate = true end
  traits.external = true
  if UF.RegisterElement(name, element, traits) ~= true then
    Fail(("element %q was rejected by the runtime."):format(name), 2)
  end
  publicElements[name] = true
  return element
end

function Framework:AttachFrame(frame, spec, mask)
  if not frame then return nil end
  if frame.MSUFUnitFrames ~= nil and frame.MSUFUnitFrames ~= self then
    Fail("cannot attach a frame owned by another MSUFUnitFrames host.", 2)
  end
  frame.MSUFUnitFrames = self
  spec = type(spec) == "table" and spec or {
    unit = frame.MSUFUnitKey or frame.unit,
    enabled = true,
  }
  UF.ApplySpec(frame, spec, "MSUF_FRAME_ATTACH", mask or spec.elements or DefaultElementMask(frame))
  return frame
end

function Framework:DetachFrame(frame)
  return UF.DetachFrame(frame)
end

function Framework:GetFrame(unit)
  return UF.GetFrame(unit)
end
