local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = _G.MSUF_NS or MSUF
_G.MSUF = _G.MSUF or MSUF

local function AddOnMetadata(key)
  local addons = _G.C_AddOns
  if addons and addons.GetAddOnMetadata then
    local value = addons.GetAddOnMetadata(addonName, key)
    if value ~= nil then return value end
  end
  if _G.GetAddOnMetadata then
    return _G.GetAddOnMetadata(addonName, key)
  end
end

local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end
MSUF.ExportPublic = ExportPublic

local Core = MSUF.UFCore or {}
MSUF.UFCore = Core

Core.addonName = addonName
Core.embedTarget = AddOnMetadata("X-MSUF-UFCore") or addonName
Core.embedded = true
Core.UF = Core.UF or MSUF.UF or {}
Core.GF = Core.GF or MSUF.GF or {}

MSUF.UF = Core.UF
MSUF.GF = Core.GF

ExportPublic("MSUF_UFCore", Core)
