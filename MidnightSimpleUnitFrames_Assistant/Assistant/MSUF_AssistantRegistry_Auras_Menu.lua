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

    RegisterBlacklistMenuSettings(ctx)

end
