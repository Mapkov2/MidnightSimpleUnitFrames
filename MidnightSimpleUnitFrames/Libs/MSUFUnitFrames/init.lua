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

local runtime = type(ns.UF) == "table" and ns.UF or {}
runtime.Elements = type(runtime.Elements) == "table" and runtime.Elements or {}
runtime.elements = type(runtime.elements) == "table" and runtime.elements or {}
runtime.attachedFrameList = type(runtime.attachedFrameList) == "table" and runtime.attachedFrameList or {}
runtime.frameNamePrefix = runtime.frameNamePrefix or CleanName(GetMetadata("X-MSUF-UnitFrames-Prefix"), parent)

-- The host-facing handle: element registration and frame attachment (api.lua).
-- embedTarget names the addon that embeds the framework.
local framework = {
  embedTarget = GetMetadata("X-MSUF-UFCore") or parent,
}

ns.MSUFUnitFrames = framework
ns.UFCore = framework
ns.UF = runtime
ns.GF = type(ns.GF) == "table" and ns.GF or {}
