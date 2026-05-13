-- ============================================================================
-- MSUF - enUS (base)
-- This file is optional. The fallback is the key itself.
-- Keeping this as a template makes it easier to add "special-case" wording.
-- ============================================================================
local addonName, ns = ...
ns = ns or {}
local L = (ns.RegisterLocale and ns.RegisterLocale("enUS")) or (ns.L or {})

-- Put overrides here if you ever want to change wording without touching code.
-- local T = { ["Old"] = "New" }
-- for k, v in pairs(T) do L[k] = v end
L["Language"] = "Language"
L["Menu language"] = "Menu language"
L["Follow Blizzard"] = "Follow Blizzard"
L["Follow Blizzard uses the WoW client language. Manual selection affects only MSUF menus."] = "Follow Blizzard uses the WoW client language. Manual selection affects only MSUF menus."
