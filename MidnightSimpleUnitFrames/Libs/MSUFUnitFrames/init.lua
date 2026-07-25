local parent, ns = ...

if type(ns) ~= "table" then
  error("MSUFUnitFrames must be loaded from an addon's TOC/XML namespace.", 2)
end

local function GetMetadata(key)
  local addons = _G.C_AddOns
  if addons and type(addons.GetAddOnMetadata) == "function" then
    local value = addons.GetAddOnMetadata(parent, key)
    if value ~= nil then return value end
  end
  if type(_G.GetAddOnMetadata) == "function" then
    return _G.GetAddOnMetadata(parent, key)
  end
end

local function MetadataEnabled(key)
  local value = GetMetadata(key)
  return value == true or value == 1 or value == "1" or value == "true"
end

local function CleanName(value, fallback)
  value = type(value) == "string" and value:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if value == "" then value = fallback or "MSUFUnitFrames" end
  value = value:gsub("[^%w_]", "")
  if value:match("^%d") then value = "_" .. value end
  return value ~= "" and value or "MSUFUnitFrames"
end

if ns.MSUFUnitFrames then
  error(("MSUFUnitFrames was loaded more than once by %s."):format(tostring(parent)), 2)
end

local globalName = GetMetadata("X-MSUF-UnitFrames")
if type(globalName) ~= "string" or globalName == "" then globalName = nil end

local legacyGlobals = MetadataEnabled("X-MSUF-UnitFrames-LegacyGlobals")
  or parent == "MidnightSimpleUnitFrames"
local prefix = CleanName(
  GetMetadata("X-MSUF-UnitFrames-Prefix"),
  globalName or parent or "MSUFUnitFrames")

local legacyCore = type(ns.UFCore) == "table" and ns.UFCore or nil
local framework = legacyCore or {}
if globalName == "MSUFUnitFrames" then
  error(("%s must choose a project-specific X-MSUF-UnitFrames global."):format(tostring(parent)), 2)
end
if globalName and _G[globalName] ~= nil and _G[globalName] ~= framework then
  error(("%s sets X-MSUF-UnitFrames to the existing global %q."):format(
    tostring(parent), globalName), 2)
end
if legacyGlobals and _G.MSUF_UFCore ~= nil and _G.MSUF_UFCore ~= framework then
  error("MSUFUnitFrames cannot replace the existing MSUF_UFCore global.", 2)
end

if legacyCore and type(legacyCore.UF) == "table"
  and type(ns.UF) == "table"
  and legacyCore.UF ~= ns.UF then
  error("MSUFUnitFrames found conflicting ns.UF and ns.UFCore.UF tables.", 2)
end
local runtime = type(ns.UF) == "table" and ns.UF
  or (legacyCore and type(legacyCore.UF) == "table" and legacyCore.UF)
  or {}
runtime.Elements = type(runtime.Elements) == "table" and runtime.Elements or {}
runtime.elements = type(runtime.elements) == "table" and runtime.elements or {}
runtime.attachedFrameList = type(runtime.attachedFrameList) == "table" and runtime.attachedFrameList or {}
runtime.frameNamePrefix = runtime.frameNamePrefix or prefix
runtime._hostValues = legacyGlobals and _G or nil

local groupRuntime = type(ns.GF) == "table" and ns.GF
  or (legacyCore and type(legacyCore.GF) == "table" and legacyCore.GF)
  or {}
if legacyCore and type(legacyCore.GF) == "table"
  and type(ns.GF) == "table"
  and legacyCore.GF ~= ns.GF then
  error("MSUFUnitFrames found conflicting ns.GF and ns.UFCore.GF tables.", 2)
end

local private = {
  styles = {},
  activeStyle = nil,
  headers = {},
  services = {},
  hostValues = {},
  metaFunctions = {},
  publicElements = {},
  factoryQueue = {},
  factoryActive = true,
  legacyGlobals = legacyGlobals,
}
if runtime._hostValues == nil then runtime._hostValues = private.hostValues end

framework.version = "0.1.0"
framework.apiVersion = 1
framework.addonName = parent
framework.embedded = true
framework.globalName = globalName
framework.embedTarget = GetMetadata("X-MSUF-UFCore") or globalName or parent
framework.framePrefix = prefix
framework.publishLegacyGlobals = legacyGlobals
framework.UF = runtime
framework.Runtime = runtime
framework.GF = groupRuntime
framework.elements = runtime.elements
framework.objects = runtime.attachedFrameList
framework.headers = private.headers
framework.legacyAPI = type(framework.legacyAPI) == "table" and framework.legacyAPI or {}
framework.Private = private

ns.MSUFUnitFrames = framework
ns.UFCore = framework
ns.UF = runtime
ns.GF = framework.GF
runtime.Framework = framework

function runtime.GetHostValue(name)
  local value = private.hostValues[name]
  if value ~= nil then return value end
  if private.legacyGlobals == true then return _G[name] end
end

function runtime.GetService(name)
  return private.services[name]
end

if globalName then
  _G[globalName] = framework
end

if legacyGlobals then
  local export = ns.ExportPublic
  if type(export) == "function" then
    export("MSUF_UFCore", framework)
  else
    _G.MSUF_UFCore = framework
  end
end
