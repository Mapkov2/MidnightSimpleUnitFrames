local _, ns = ...

local Framework = ns and ns.MSUFUnitFrames
local Private = Framework and Framework.Private
local UF = Framework and Framework.UF
if not (Framework and Private and UF) then
  error("MSUFUnitFrames API loaded before init.lua.", 2)
end

local type = type
local pairs = pairs
local next = next
local tostring = tostring
local select = select
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local RegisterUnitWatch = _G.RegisterUnitWatch

local function Fail(message, level)
  error("MSUFUnitFrames: " .. message, (level or 1) + 1)
end

local function Require(value, label, wanted)
  if type(value) ~= wanted then
    Fail(("%s must be a %s, got %s."):format(label, wanted, type(value)), 2)
  end
end

local function InCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function FrameParent()
  local parent = Private.services.FrameParent
  if type(parent) == "function" then parent = parent(Framework) end
  return parent or _G.UIParent
end

local function UniqueName(base)
  local name = base
  local index = 2
  while _G[name] ~= nil do
    name = base .. index
    index = index + 1
  end
  return name
end

local function UnitNamePart(unit)
  unit = tostring(unit or "Unit")
  return unit:gsub("^%l", string.upper):gsub("[^%w_]", "")
end

local function ApplyMetaFunctions(frame)
  for name, func in pairs(Private.metaFunctions) do
    if frame[name] == nil then frame[name] = func end
  end
end

local function DefaultElementMask(frame)
  local mask = {}
  for name in pairs(Private.publicElements) do
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

local function ApplyStyle(frame, unit, styleName)
  if frame.MSUFUnitFrames ~= nil and frame.MSUFUnitFrames ~= Framework then
    Fail("cannot adopt a frame owned by another MSUFUnitFrames host.", 2)
  end
  styleName = styleName or Private.activeStyle
  local style = styleName and Private.styles[styleName]
  if not style then
    Fail("cannot create a frame before a style is registered and activated.", 2)
  end

  ApplyMetaFunctions(frame)
  frame.MSUFUnitFrames = Framework
  frame.MSUFStyle = styleName
  frame.unit = unit
  frame.MSUFUnitKey = unit

  local spec, mask = style(frame, unit)
  if type(spec) ~= "table" then spec = frame.MSUFSpec end
  if type(spec) ~= "table" then spec = { unit = unit, enabled = true } end
  if spec.unit == nil then spec.unit = unit end
  if spec.enabled == nil then spec.enabled = true end
  mask = mask or spec.elements or DefaultElementMask(frame)

  UF.ApplySpec(frame, spec, "MSUF_FRAME_SPAWN", mask)
  return frame
end
Private.ApplyStyle = ApplyStyle

function Framework:RegisterStyle(name, style)
  Require(name, "style name", "string")
  if type(style) ~= "function" and type(style) ~= "table" then
    Fail("style must be a function or callable table.", 2)
  end
  if Private.styles[name] ~= nil then
    Fail(("style %q is already registered."):format(name), 2)
  end
  if type(style) == "table" then
    local callable = getmetatable(style)
    if not (callable and type(callable.__call) == "function") then
      Fail("table styles need a __call metamethod.", 2)
    end
  end
  Private.styles[name] = style
  if Private.activeStyle == nil then Private.activeStyle = name end
  return style
end

function Framework:SetActiveStyle(name)
  Require(name, "style name", "string")
  if Private.styles[name] == nil then
    Fail(("style %q is not registered."):format(name), 2)
  end
  Private.activeStyle = name
  return name
end

function Framework:GetActiveStyle()
  return Private.activeStyle
end

function Framework.IterateStyles()
  return next, Private.styles, nil
end

function Framework:SetService(name, service)
  Require(name, "service name", "string")
  Private.services[name] = service
  return service
end

function Framework:GetService(name)
  Require(name, "service name", "string")
  return Private.services[name]
end

function Framework:SetHostValue(name, value)
  Require(name, "host value name", "string")
  if Private.legacyGlobals == true then
    _G[name] = value
  else
    Private.hostValues[name] = value
  end
  return value
end

function Framework:GetHostValue(name)
  Require(name, "host value name", "string")
  return UF.GetHostValue(name)
end

function Framework:RegisterMetaFunction(name, func)
  Require(name, "meta function name", "string")
  Require(func, "meta function", "function")
  if Private.metaFunctions[name] ~= nil then
    Fail(("meta function %q is already registered."):format(name), 2)
  end
  Private.metaFunctions[name] = func
  for index = 1, #Framework.objects do
    local frame = Framework.objects[index]
    if frame and frame[name] == nil then frame[name] = func end
  end
  return func
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
  Private.publicElements[name] = true
  return element
end

function Framework:AddElement(name, update, enable, disable, events, unitlessEvents)
  Require(name, "element name", "string")
  if update ~= nil then Require(update, "element update", "function") end
  Require(enable, "element enable", "function")
  Require(disable, "element disable", "function")

  local element = {
    Update = update,
    events = events,
    unitlessEvents = unitlessEvents,
  }
  element.IsEnabled = function(frame)
    return frame[name] ~= nil
  end
  element.Enable = function(frame)
    if frame[name] == nil then return false end
    return enable(frame, frame.MSUFUnitKey)
  end
  element.Disable = function(frame)
    return disable(frame)
  end
  return self:RegisterElement(name, element)
end

function Framework:Spawn(unit, overrideName)
  Require(unit, "unit", "string")
  if InCombat() then return nil, "combat lockdown" end
  if type(CreateFrame) ~= "function" then
    Fail("CreateFrame is unavailable.", 2)
  end

  unit = unit:lower()
  local styleName = Private.activeStyle
  if not styleName then
    Fail("cannot spawn a frame before a style is active.", 2)
  end
  local name = overrideName
  if name ~= nil then Require(name, "frame name", "string") end
  if name and _G[name] ~= nil then
    Fail(("frame name %q is already in use."):format(name), 2)
  end
  name = name or UniqueName(
    Framework.framePrefix .. "_" .. styleName:gsub("[^%w_]", "") .. UnitNamePart(unit))

  local frame = CreateFrame(
    "Button", name, FrameParent(),
    "SecureUnitButtonTemplate, PingableUnitFrameTemplate")
  if frame.SetAttribute then
    frame:SetAttribute("unit", unit)
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
  end
  if frame.RegisterForClicks then frame:RegisterForClicks("AnyUp") end
  ApplyStyle(frame, unit, styleName)
  if type(RegisterUnitWatch) == "function" then RegisterUnitWatch(frame) end

  UF.frames = UF.frames or {}
  if UF.frames[unit] == nil then UF.frames[unit] = frame end
  local disableBlizzard = Private.services.DisableBlizzard
  if type(disableBlizzard) == "function" then disableBlizzard(unit, Framework) end
  return frame
end

local HEADER_INITIAL_CONFIG = [[
  self:SetAttribute("*type1", "target")
  self:SetAttribute("*type2", "togglemenu")
  RegisterUnitWatch(self)
  local header = self:GetParent()
  header:CallMethod("MSUFUnitFramesStyleChild", self:GetName())
]]

function Framework:SpawnHeader(overrideName, template, ...)
  if InCombat() then return nil, "combat lockdown" end
  if not Private.activeStyle then
    Fail("cannot spawn a header before a style is active.", 2)
  end
  if type(CreateFrame) ~= "function" then
    Fail("CreateFrame is unavailable.", 2)
  end
  if overrideName ~= nil then Require(overrideName, "header name", "string") end
  if template ~= nil then Require(template, "header template", "string") end
  if overrideName and _G[overrideName] ~= nil then
    Fail(("header name %q is already in use."):format(overrideName), 2)
  end

  local name = overrideName or UniqueName(
    Framework.framePrefix .. "_" .. Private.activeStyle:gsub("[^%w_]", "") .. "Header")
  local header = CreateFrame("Frame", name, FrameParent(), template or "SecureGroupHeaderTemplate")
  local styleName = Private.activeStyle

  header.MSUFUnitFramesStyleChild = function(_, childName)
    local child = childName and _G[childName]
    if not child then return end
    local unit = child.GetAttribute and child:GetAttribute("unit") or child.unit
    ApplyStyle(child, unit or "group", styleName)
  end

  if header.SetAttribute then
    header:SetAttribute(
      "template",
      "SecureUnitButtonTemplate, PingableUnitFrameTemplate")
    if select("#", ...) == 1 and type((...)) == "table" then
      for attribute, value in pairs((...)) do
        header:SetAttribute(attribute, value)
      end
    else
      for index = 1, select("#", ...), 2 do
        local attribute, value = select(index, ...)
        if attribute == nil then break end
        header:SetAttribute(attribute, value)
      end
    end
    header:SetAttribute("initialConfigFunction", HEADER_INITIAL_CONFIG)
  end

  header.MSUFUnitFrames = Framework
  header.MSUFStyle = styleName
  Private.headers[#Private.headers + 1] = header
  return header
end

local function LoggedIn()
  return type(_G.IsLoggedIn) ~= "function" or _G.IsLoggedIn() == true
end

local function RunFactoryQueue()
  if Private.factoryActive ~= true or not LoggedIn() then return false end
  local queue = Private.factoryQueue
  for index = 1, #queue do
    queue[index](Framework)
    queue[index] = nil
  end
  if Private.factoryDriver and Private.factoryDriver.UnregisterAllEvents then
    Private.factoryDriver:UnregisterAllEvents()
  end
  return true
end

local function EnsureFactoryDriver()
  if Private.factoryDriver or type(CreateFrame) ~= "function" then return end
  local driver = CreateFrame("Frame")
  Private.factoryDriver = driver
  if driver.SetScript then
    driver:SetScript("OnEvent", function() RunFactoryQueue() end)
  end
  if driver.RegisterEvent then driver:RegisterEvent("PLAYER_LOGIN") end
end

function Framework:Factory(func)
  Require(func, "factory callback", "function")
  if Private.factoryActive == true and LoggedIn() then
    return func(self)
  end
  Private.factoryQueue[#Private.factoryQueue + 1] = func
  EnsureFactoryDriver()
end

function Framework:EnableFactory()
  Private.factoryActive = true
  if #Private.factoryQueue > 0 then
    if LoggedIn() then return RunFactoryQueue() end
    EnsureFactoryDriver()
  end
end

function Framework:DisableFactory()
  Private.factoryActive = false
end

function Framework:RunFactoryQueue()
  return RunFactoryQueue()
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
