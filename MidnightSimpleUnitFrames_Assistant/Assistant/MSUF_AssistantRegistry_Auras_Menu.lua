-- Assistant Auras menu registry: root Aura system and menu state settings.
-- Loaded before MSUF_AssistantRegistry_Auras.lua; the main domain passes its local helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterMenuSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local Menu = ctx.M or M
    local AURA_LANE_MENU_VALUES = ctx.AURA_LANE_MENU_VALUES or {}
    local AURA_LANE_MENU_ALIASES = ctx.AURA_LANE_MENU_ALIASES or {}
    local AURA_STYLE_LANE_ALIASES = ctx.AURA_STYLE_LANE_ALIASES or {}
    local AURA_STYLE_LANE_EXACT_ALIASES = ctx.AURA_STYLE_LANE_EXACT_ALIASES or {}
    local AURA_FILTER_LANE_ALIASES = ctx.AURA_FILTER_LANE_ALIASES or {}
    local AURA_FILTER_LANE_EXACT_ALIASES = ctx.AURA_FILTER_LANE_EXACT_ALIASES or {}
    local AURA_UX_MODE_VALUES = ctx.AURA_UX_MODE_VALUES or {}
    local AURA_UX_MODE_ALIASES = ctx.AURA_UX_MODE_ALIASES or {}
    local AURA_UX_MODE_EXACT_ALIASES = ctx.AURA_UX_MODE_EXACT_ALIASES or {}
    local AURA_UX_MODE_VALUE_ALIASES = ctx.AURA_UX_MODE_VALUE_ALIASES or {}
    local RegisterAuraRootMenuSettings = A.AurasRegistry and A.AurasRegistry.RegisterAuraRootMenuSettings
    local RegisterBlacklistMenuSettings = A.AurasRegistry and A.AurasRegistry.RegisterBlacklistMenuSettings

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(RegisterAuraRootMenuSettings) ~= "function" then return end
    if type(RegisterBlacklistMenuSettings) ~= "function" then return end

    RegisterAuraRootMenuSettings(ctx)

    Registry:RegisterSetting({
        key = "menu.auraStyleGFLane",
        label = "Aura Style Lane",
        category = "Menu / Auras",
        unit = "global",
        frameType = "aura",
        attribute = "auraStyleLane",
        type = "enum",
        aliases = AURA_STYLE_LANE_ALIASES,
        exactAliases = AURA_STYLE_LANE_EXACT_ALIASES,
        values = AURA_LANE_MENU_VALUES,
        valueAliases = AURA_LANE_MENU_ALIASES,
        get = function()
            local lane = Menu.auraStyleGFLane
            return lane == "buff" and "buff" or "debuff"
        end,
        set = function(value)
            value = value == "buff" and "buff" or "debuff"
            if type(Menu.PersistMenuStateValue) == "function" then Menu.PersistMenuStateValue("auraStyleGFLane", value) else Menu.auraStyleGFLane = value end
        end,
        apply = function()
            if type(Menu.SelectPage) == "function" then Menu.SelectPage("auras3_styling") elseif type(Menu.Open) == "function" then Menu.Open("auras3_styling") end
            if type(Menu.Refresh) == "function" then Menu.Refresh() end
            if type(Menu.InvalidatePage) == "function" then Menu.InvalidatePage("auras3_styling") end
        end,
        combatSafe = true,
    })

    Registry:RegisterSetting({
        key = "menu.auraFilterLane",
        label = "Aura Filter Lane",
        category = "Menu / Auras",
        unit = "global",
        frameType = "aura",
        attribute = "auraFilterLane",
        type = "enum",
        aliases = AURA_FILTER_LANE_ALIASES,
        exactAliases = AURA_FILTER_LANE_EXACT_ALIASES,
        values = AURA_LANE_MENU_VALUES,
        valueAliases = AURA_LANE_MENU_ALIASES,
        get = function()
            local lane = Menu.auraFilterLane
            return lane == "debuff" and "debuff" or "buff"
        end,
        set = function(value)
            value = value == "debuff" and "debuff" or "buff"
            if type(Menu.PersistMenuStateValue) == "function" then Menu.PersistMenuStateValue("auraFilterLane", value) else Menu.auraFilterLane = value end
        end,
        apply = function()
            if type(Menu.SelectPage) == "function" then Menu.SelectPage("auras3_filters") elseif type(Menu.Open) == "function" then Menu.Open("auras3_filters") end
            if type(Menu.Refresh) == "function" then Menu.Refresh() end
            if type(Menu.InvalidatePage) == "function" then Menu.InvalidatePage("auras3_filters") end
        end,
        combatSafe = true,
    })

    RegisterBlacklistMenuSettings(ctx)

    Registry:RegisterSetting({
        key = "menu.aurasUXMode",
        label = "Aura Options View",
        category = "Menu / Auras",
        unit = "global",
        frameType = "aura",
        attribute = "auraSettingsView",
        type = "enum",
        aliases = AURA_UX_MODE_ALIASES,
        exactAliases = AURA_UX_MODE_EXACT_ALIASES,
        values = AURA_UX_MODE_VALUES,
        valueAliases = AURA_UX_MODE_VALUE_ALIASES,
        get = function() return Menu.aurasUXMode == "advanced" and "advanced" or "basic" end,
        set = function(value)
            value = value == "advanced" and "advanced" or "basic"
            if type(Menu.PersistMenuStateValue) == "function" then Menu.PersistMenuStateValue("aurasUXMode", value) else Menu.aurasUXMode = value end
        end,
        apply = function()
            if type(Menu.SelectPage) == "function" then Menu.SelectPage("auras3") elseif type(Menu.Open) == "function" then Menu.Open("auras3") end
            if type(Menu.Refresh) == "function" then Menu.Refresh() end
            if type(Menu.InvalidatePage) == "function" then Menu.InvalidatePage("auras3") end
        end,
        combatSafe = true,
    })
end
