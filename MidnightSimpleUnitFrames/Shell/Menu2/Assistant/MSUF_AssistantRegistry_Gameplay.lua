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

RegisterGameplayBoolean("enableFirstDanceTimer", "enabled", "First Dance Tracker", false, {
    "first dance tracker enabled", "first dance timer enabled", "rogue first dance tracker",
    "erster tanz", "erster tanz tracker", "erster tanz timer", "erster tanz anzeigen",
}, {
    category = "Gameplay / First Dance",
    frameType = "firstDance",
    reason = "MSUF_ASSISTANT_FIRST_DANCE",
    matchLabel = false,
})
RegisterGameplayBoolean("lockFirstDance", "locked", "First Dance Lock Position", false, {
    "first dance lock", "lock first dance", "first dance locked",
    "erster tanz sperren", "erster tanz position sperren",
}, {
    category = "Gameplay / First Dance",
    frameType = "firstDance",
    reason = "MSUF_ASSISTANT_FIRST_DANCE_LOCK",
})
RegisterGameplayBoolean("firstDanceClickThrough", "clickThrough", "First Dance Click Through", true, {
    "first dance click through", "first dance click-through", "first dance mouse input",
    "erster tanz durchklickbar", "erster tanz klick durch", "erster tanz mauseingabe",
}, {
    category = "Gameplay / First Dance",
    frameType = "firstDance",
    reason = "MSUF_ASSISTANT_FIRST_DANCE_CLICK_THROUGH",
})
RegisterGameplayBoolean("firstDanceShowIcon", "icon", "First Dance Icon Mode", true, {
    "first dance icon", "first dance icon mode", "first dance cooldown swipe",
    "erster tanz symbol", "erster tanz symbol modus", "erster tanz cooldown swipe",
}, {
    category = "Gameplay / First Dance",
    frameType = "firstDance",
    reason = "MSUF_ASSISTANT_FIRST_DANCE_ICON",
})
RegisterGameplayBoolean("firstDanceShowReady", "showReady", "First Dance Show Ready", true, {
    "first dance show ready", "first dance ready visible", "first dance keep visible",
    "erster tanz bereit anzeigen", "erster tanz bereit sichtbar", "erster tanz sichtbar wenn bereit",
}, {
    category = "Gameplay / First Dance",
    frameType = "firstDance",
    reason = "MSUF_ASSISTANT_FIRST_DANCE_READY",
})
RegisterGameplayNumber("firstDanceIconSize", "size", "First Dance Icon Size", 40, 16, 96, {
    "first dance size", "first dance icon size", "first dance tracker size",
    "erster tanz groesse", "erster tanz symbol groesse", "erster tanz tracker groesse",
}, {
    category = "Gameplay / First Dance",
    frameType = "firstDance",
    reason = "MSUF_ASSISTANT_FIRST_DANCE_SIZE",
})
RegisterGameplayNumber("firstDanceOffsetX", "offsetX", "First Dance Offset X", 0, -800, 800, {
    "first dance x", "first dance x offset", "first dance tracker x",
    "erster tanz x", "erster tanz x versatz", "erster tanz tracker x",
}, {
    category = "Gameplay / First Dance",
    frameType = "firstDance",
    reason = "MSUF_ASSISTANT_FIRST_DANCE_X",
})
RegisterGameplayNumber("firstDanceOffsetY", "offsetY", "First Dance Offset Y", 80, -800, 800, {
    "first dance y", "first dance y offset", "first dance tracker y",
    "erster tanz y", "erster tanz y versatz", "erster tanz tracker y",
}, {
    category = "Gameplay / First Dance",
    frameType = "firstDance",
    reason = "MSUF_ASSISTANT_FIRST_DANCE_Y",
})

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
