-- Assistant Gameplay registry: exposes optional gameplay helper controls and diagnostics.
-- Actions should call feature-owned helpers so parser metadata does not own live state.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Registry = Registry
A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- Gameplay registry domain.
-- Covers combat timer/crosshair, totems/statues, and related gameplay helpers. These settings
-- bridge into gameplay runtimes instead of editing frames directly from the assistant.
local Registry = C.Registry
local RegisterGameplayBoolean = C.RegisterGameplayBoolean
local RegisterGameplayNumber = C.RegisterGameplayNumber
local RegisterGameplayEnum = C.RegisterGameplayEnum
local RegisterGameplayString = C.RegisterGameplayString
local GameplayAliases = C.GameplayAliases
local GameplayDB = C.GameplayDB
local ApplyGameplay = C.ApplyGameplay

if not (Registry and type(Registry.RegisterSetting) == "function" and type(Registry.RegisterAction) == "function") then return end
if type(RegisterGameplayBoolean) ~= "function" or type(RegisterGameplayNumber) ~= "function" then return end
if type(RegisterGameplayEnum) ~= "function" or type(RegisterGameplayString) ~= "function" then return end
if type(GameplayDB) ~= "function" or type(ApplyGameplay) ~= "function" then return end

local RegisterCombatTextSettings = A.GameplayRegistry and A.GameplayRegistry.RegisterCombatTextSettings
if type(RegisterCombatTextSettings) == "function" then
    RegisterCombatTextSettings({
        RegisterGameplayBoolean = RegisterGameplayBoolean,
        RegisterGameplayNumber = RegisterGameplayNumber,
        RegisterGameplayEnum = RegisterGameplayEnum,
        RegisterGameplayString = RegisterGameplayString,
    })
end

local RegisterPlayerTotemSettings = A.GameplayRegistry and A.GameplayRegistry.RegisterPlayerTotemSettings
if type(RegisterPlayerTotemSettings) == "function" then
    RegisterPlayerTotemSettings({
        RegisterGameplayBoolean = RegisterGameplayBoolean,
        RegisterGameplayNumber = RegisterGameplayNumber,
        RegisterGameplayEnum = RegisterGameplayEnum,
        GameplayAliases = GameplayAliases,
    })
end

local RegisterCrosshairSettings = A.GameplayRegistry and A.GameplayRegistry.RegisterCrosshairSettings
if type(RegisterCrosshairSettings) == "function" then
    RegisterCrosshairSettings({
        Registry = Registry,
        RegisterGameplayBoolean = RegisterGameplayBoolean,
        RegisterGameplayNumber = RegisterGameplayNumber,
        ApplyGameplay = ApplyGameplay,
        Menu = M,
    })
end

Registry:RegisterAction({
    key = "preview_player_totems",
    label = "Preview Totem Frame",
    type = "gameplay",
    aliases = {
        "preview totem frame",
        "totem frame preview",
        "preview statue frame",
        "totem rahmen vorschau",
        "totemrahmen vorschau",
        "statuen rahmen vorschau",
        "statue rahmen vorschau",
    },
    combatSafe = false,
    run = function()
        local fn = MSUF and MSUF.MSUF_PlayerTotems_TogglePreview
        if type(fn) ~= "function" then return false, "Open Gameplay first so I can show the Totem Frame preview." end
        fn()
        return true, "Done. Toggled the Totem Frame preview."
    end,
})

Registry:RegisterAction({
    key = "reset_player_totems_layout",
    label = "Reset Totem Frame Layout",
    type = "gameplay",
    aliases = {
        "reset totem frame layout",
        "reset totem frame",
        "reset statue frame",
        "totem frame reset",
        "totem rahmen zuruecksetzen",
        "totemrahmen zuruecksetzen",
        "statuen rahmen zuruecksetzen",
        "statue rahmen zuruecksetzen",
    },
    combatSafe = false,
    confirmRequired = true,
    captureSnapshot = true,
    run = function()
        local g = GameplayDB()
        g.playerTotemsIconSize = 24
        g.playerTotemsOffsetX = 0
        g.playerTotemsOffsetY = -6
        g.playerTotemsAnchorFrom = "TOPLEFT"
        g.playerTotemsAnchorTo = "BOTTOMLEFT"
        ApplyGameplay("MSUF_ASSISTANT_PLAYER_TOTEMS_RESET")
        return true, "Done. Reset Totem Frame layout."
    end,
})
