-- MSUF_Presets.lua
-- Defines built-in presets used by the Dashboard/SlashMenu.

local addonName, addonNS = ...
local ns = (_G and _G.MSUF_NS) or addonNS or {}
if _G then _G.MSUF_NS = ns end

-- Always use a shared table reference so load-order doesn't break the Dashboard.
local presets = nil
if type(ns.MSUF_PRESETS) == "table" then
    presets = ns.MSUF_PRESETS
elseif _G and type(_G.MSUF_PRESETS) == "table" then
    presets = _G.MSUF_PRESETS
else
    presets = {}
end

ns.MSUF_PRESETS = presets
if _G then _G.MSUF_PRESETS = presets end

-- Seed: Factory Default (uses the same compact profile string that fresh installs seed from).
local factory = (type(ns.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT) == "string" and ns.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT)
    or (_G and type(_G.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT) == "string" and _G.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT)

if type(factory) == "string" and factory ~= "" then
    if type(presets["Factory Default"]) ~= "table" then
        presets["Factory Default"] = {
            _msufImportString = factory,
            _msufWarning = "This will overwrite your current profile settings.",
        }
    end
end

-- NOTE:
-- Add more presets by inserting tables into ns.MSUF_PRESETS.
-- A preset can either contain an _msufImportString (MSUF2/MSUF3 export string)
-- or a full table payload with allowed keys (general/player/target/focus/...)
