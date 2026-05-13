-- ============================================================================
-- MSUF - enGB
--
-- British English. Shares all strings with enUS (fallback handles it).
-- Only override spelling differences here if desired.
-- ============================================================================
local addonName, ns = ...

ns = ns or {}
local L = (ns.RegisterLocale and ns.RegisterLocale("enGB")) or (ns.L or {})

-- enGB uses enUS keys as fallback. Add British spelling overrides below:
-- L["Color player names by class"] = "Colour player names by class"
L["Language"] = "Language"
L["Menu language"] = "Menu language"
L["Follow Blizzard"] = "Follow Blizzard"
L["Follow Blizzard uses the WoW client language. Manual selection affects only MSUF menus."] = "Follow Blizzard uses the WoW client language. Manual selection affects only MSUF menus."
