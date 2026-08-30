-- Assistant Auras blacklist menu registry settings.
-- Loaded before MSUF_AssistantRegistry_Auras_Menu.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

local function ActiveAuraContentWorkspace(Menu)
    local page = tostring(Menu and Menu.activeKey or "")
    local ownsAuraContent = page == "gf_auras"
        or page == "uf_player" or page == "uf_target"
        or page == "uf_focus" or page == "uf_boss"
    return ownsAuraContent and page or nil
end

local function RefreshAuraContentWorkspace(Menu)
    local page = ActiveAuraContentWorkspace(Menu)
    -- These two registry entries model selectors inside a frame-owned Aura
    -- editor. They must never manufacture Player ownership when no such
    -- workspace is active; the conversational layer can then ask for scope.
    if not page then return false end
    if type(Menu.InvalidatePage) == "function" then Menu.InvalidatePage(page) end
    if type(Menu.SelectPage) == "function" then
        Menu.SelectPage(page)
    elseif type(Menu.Open) == "function" then
        Menu.Open(page)
    end
    if type(Menu.Refresh) == "function" then Menu.Refresh() end
end

function A.AurasRegistry.RegisterBlacklistMenuSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local Menu = ctx.M or M
    local AURA_BLACKLIST_PRESET_VALUES = ctx.AURA_BLACKLIST_PRESET_VALUES or {}
    local AURA_BLACKLIST_PRESET_ALIASES = ctx.AURA_BLACKLIST_PRESET_ALIASES or {}

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end

    Registry:RegisterSetting({
        key = "menu.auraBlacklistPreset",
        label = "Hidden Aura Preset",
        category = "Menu / Auras",
        unit = "shared",
        frameType = "aura",
        contextualMenuState = "auraContent",
        attribute = "auraBlacklistPreset",
        type = "enum",
        aliases = { "aura blacklist preset", "blacklist preset", "aura preset group", "aura blacklist group preset" },
        values = AURA_BLACKLIST_PRESET_VALUES,
        valueAliases = AURA_BLACKLIST_PRESET_ALIASES,
        get = function() return tostring(Menu.auraBlacklistPreset or "RAID_BUFFS") end,
        set = function(value)
            Menu.auraBlacklistPreset = tostring(value or "RAID_BUFFS")
            Menu.auraBlacklistSpell = nil
        end,
        apply = function() RefreshAuraContentWorkspace(Menu) end,
        combatSafe = true,
    })

    Registry:RegisterSetting({
        key = "menu.auraBlacklistSpell",
        label = "Hidden Aura Spell",
        category = "Menu / Auras",
        unit = "shared",
        frameType = "aura",
        contextualMenuState = "auraContent",
        attribute = "auraBlacklistSpell",
        type = "string",
        aliases = { "aura blacklist spell", "blacklist spell", "selected aura blacklist spell", "aura spell preset" },
        valuePrefixes = { "aura blacklist spell", "blacklist spell", "selected aura blacklist spell", "aura spell preset" },
        get = function() return tostring(Menu.auraBlacklistSpell or "") end,
        set = function(value) Menu.auraBlacklistSpell = tostring(value or "") end,
        apply = function() RefreshAuraContentWorkspace(Menu) end,
        combatSafe = true,
    })
end
