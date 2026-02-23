-- ============================================================================
-- MSUF - enGB
--
-- British English. Shares all strings with enUS (fallback handles it).
-- Only override spelling differences here if desired.
-- ============================================================================
local addonName, ns = ...

local loc = (ns and ns.LOCALE) or ((type(GetLocale) == "function" and GetLocale()) or "enUS")
if loc ~= "enGB" then return end

ns = ns or {}
ns.LOCALE = loc
ns.L = ns.L or (_G and _G.MSUF_L) or {}
local L = ns.L
if not getmetatable(L) then
    setmetatable(L, { __index = function(t, k) return k end })
end
if _G then _G.MSUF_L = L end

-- enGB uses enUS keys as fallback. Add British spelling overrides below:
-- L["Color player names by class"] = "Colour player names by class"
