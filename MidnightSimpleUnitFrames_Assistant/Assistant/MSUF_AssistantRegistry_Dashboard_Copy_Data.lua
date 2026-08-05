-- Assistant Dashboard copy-scope fallback data.
-- Shared by copy selector helpers when the Menu2 pages have not published category metadata yet.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.DashboardRegistry = A.DashboardRegistry or {}

A.DashboardRegistry.CopyCategoryFallbacks = {
    unit = {
        { key = "basics", label = "Frame Basics", default = true, aliases = { "frame basics", "basic settings", "basics", "enable state", "smooth fill", "reverse fill" } },
        { key = "text", label = "Text", default = true, aliases = { "text", "name", "hp", "health text", "hp text", "power text", "font", "fonts" } },
        { key = "portrait", label = "Portrait", default = true, aliases = { "portrait", "portrait settings" } },
        { key = "power", label = "Power Bar", default = true, aliases = { "power", "power bar", "powerbar", "detached power", "detached power bar", "resource bar" } },
        { key = "auras", label = "Aura Options", default = true, aliases = { "auras", "aura options", "buff options", "debuff options", "aura layout", "aura filters" } },
        { key = "aurastyle", label = "Aura Style", default = true, aliases = { "aura style", "aura styling", "buff style", "debuff style", "defensive style", "dot style" } },
        { key = "castbar", label = "Cast Bar", default = true, aliases = { "castbar", "cast bar" } },
        { key = "status", label = "Status Icons", default = true, aliases = { "status", "status icon", "status icons", "status indicator", "status indicators", "indicator", "indicators", "level indicator", "raid marker", "pvp flag", "pvp indicator" } },
        { key = "load", label = "Load Conditions", default = true, aliases = { "load", "load condition", "load conditions", "hide mounted", "hide out of combat" } },
        { key = "transparency", label = "Transparency", default = true, aliases = { "transparency", "opacity", "alpha", "range fade" } },
        -- Placement deliberately has no alias here: Copy To only ever moves width and
        -- height, so "position"/"anchor" must not route a user into this category.
        { key = "layout", label = "Frame Size", default = false, aliases = { "layout", "frame size", "size", "width", "height" } },
    },
    group = {
        { key = "general", label = "Basics", aliases = { "general", "basics", "basic", "layout", "size", "spacing", "growth", "sort", "sorting" } },
        { key = "health", label = "Health & Bars", aliases = { "health", "health bars", "bars", "power", "power bar", "opacity", "alpha", "transparency", "background opacity" } },
        { key = "dispel", label = "Dispel Overlay", aliases = { "dispel overlay", "group dispel overlay", "party dispel overlay", "raid dispel overlay" } },
        { key = "text", label = "Text & Name", aliases = { "text", "name", "health text", "hp text", "text and name" } },
        { key = "font", label = "Font Override", aliases = { "font", "fonts", "font override", "font color", "font outline" } },
        { key = "range", label = "Range Fade", aliases = { "range", "range fade", "offline alpha" } },
        { key = "indicators", label = "Status & Indicators", aliases = { "indicators", "status and indicators", "status icons", "status icon", "role icon", "leader icon", "assist icon", "raid marker", "pvp flag", "pvp indicator" } },
        { key = "auras", label = "Aura Options", aliases = { "auras", "aura options", "buff options", "debuff options", "aura layout", "aura filters" } },
        { key = "aurastyle", label = "Aura Style", default = true, aliases = { "aura style", "aura styling", "buff style", "debuff style", "spell icon style", "spell indicator style", "spell styling" } },
        { key = "highlight", label = "Highlight & Aggro", aliases = { "highlight", "aggro", "dispel border", "purge border" } },
        { key = "dstripe", label = "Debuff Stripe", aliases = { "debuff stripe", "stripe" } },
        { key = "features", label = "Corner/Spell", aliases = { "corner", "corner indicator", "corner indicators", "spell indicator", "spell indicators", "corner spell" } },
    },
}
