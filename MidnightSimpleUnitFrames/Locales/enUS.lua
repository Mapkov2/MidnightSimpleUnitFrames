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

-- MSUF 5.1 Beta 1
L["Blizzard Renderer"] = "Blizzard Renderer"
L["Renderer path: Blizzard is the default native aura block. Checked types below are rendered by Blizzard; unchecked types use MSUF Custom groups. Custom mode disables the native block completely. Blizzard controls final native aura placement; MSUF only shows an approximate locked preview."] = "Renderer path: Blizzard is the default native aura block. Checked types below are rendered by Blizzard; unchecked types use MSUF Custom groups. Custom mode disables the native block completely. Blizzard controls final native aura placement; MSUF only shows an approximate locked preview."
L["Blizzard Aura Layering"] = "Blizzard Aura Layering"
L["Blizzard renders these icons on MSUF's container. If icons appear behind frames, raise the container strata or frame level."] = "Blizzard renders these icons on MSUF's container. If icons appear behind frames, raise the container strata or frame level."
L["Icon size: %d"] = "Icon size: %d"
L["Buff max: %d"] = "Buff max: %d"
L["Debuff max: %d"] = "Debuff max: %d"
L["Rendered by Blizzard"] = "Rendered by Blizzard"
L["Use Blizzard: Buffs"] = "Use Blizzard: Buffs"
L["Use Blizzard: Debuffs"] = "Use Blizzard: Debuffs"
L["Use Blizzard: Dispels"] = "Use Blizzard: Dispels"
L["Use Blizzard: Defensives"] = "Use Blizzard: Defensives"
L["Blizzard Cooldown Text"] = "Blizzard Cooldown Text"
L["Use Blizzard: Private"] = "Use Blizzard: Private"
L["Organization"] = "Organization"
L["Layering"] = "Layering"
L["Container Strata"] = "Container Strata"
L["Container level: +%d"] = "Container level: +%d"
L["Private Aura Layer Fix"] = "Private Aura Layer Fix"
L["Blizzard Position"] = "Blizzard Position"
L["Locked by Blizzard. MSUF can pass the native renderer settings above, but cannot drag or set the native block position. The preview marks the Blizzard-owned area and enabled aura types; exact placement is decided by Blizzard at runtime."] = "Locked by Blizzard. MSUF can pass the native renderer settings above, but cannot drag or set the native block position. The preview marks the Blizzard-owned area and enabled aura types; exact placement is decided by Blizzard at runtime."
L["Defensives"] = "Defensives"
L["Enable defensives"] = "Enable defensives"
L["Max defensives"] = "Max defensives"
L["Text Coloring"] = "Text Coloring"
L["MSUF timer coloring only applies to custom aura icons. Blizzard-rendered cooldown text can be shown or hidden per group, but not recolored here."] = "MSUF timer coloring only applies to custom aura icons. Blizzard-rendered cooldown text can be shown or hidden per group, but not recolored here."
L["Color aura timers by remaining time"] = "Color aura timers by remaining time"
L["Cooldown Timer Text"] = "Cooldown Timer Text"
