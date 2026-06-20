-- Assistant gameplay color setting registry.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings.lua; the main domain passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterGameplayColorSettings(ctx)
    if type(ctx) ~= "table" then return end

    local ColorSetting = ctx.ColorSetting
    local GameplayDB = ctx.GameplayDB
    local TableRGB = ctx.TableRGB
    local SetTableRGB = ctx.SetTableRGB
    local RegisterGameplayBoolean = ctx.RegisterGameplayBoolean
    local ApplyGameplayColors = ctx.ApplyGameplayColors

    if type(ColorSetting) ~= "function" or type(GameplayDB) ~= "function" then return end
    if type(TableRGB) ~= "function" or type(SetTableRGB) ~= "function" then return end
    if type(RegisterGameplayBoolean) ~= "function" then return end

    ColorSetting("gameplay.combatTimerColor", "Combat Timer Text Color", {
        "combat timer text color", "combat timer color",
    }, function()
        return TableRGB(GameplayDB(), "combatTimerColor", 1, 1, 1)
    end, function(r, g, b)
        SetTableRGB(GameplayDB(), "combatTimerColor", r, g, b)
    end, { category = "Colors / Gameplay", frameType = "gameplay", attribute = "combatTimerColor", apply = ApplyGameplayColors })
    ColorSetting("gameplay.combatStateEnterColor", "Combat Enter Text Color", {
        "combat enter text color", "combat enter color", "combat state enter color",
    }, function()
        return TableRGB(GameplayDB(), "combatStateEnterColor", 1, 1, 1)
    end, function(r, g, b)
        local gp = GameplayDB()
        SetTableRGB(gp, "combatStateEnterColor", r, g, b)
        if gp.combatStateColorSync then SetTableRGB(gp, "combatStateLeaveColor", r, g, b) end
    end, { category = "Colors / Gameplay", frameType = "gameplay", attribute = "combatStateEnterColor", apply = ApplyGameplayColors })
    ColorSetting("gameplay.combatStateLeaveColor", "Combat Leave Text Color", {
        "combat leave text color", "combat leave color", "combat state leave color",
    }, function()
        return TableRGB(GameplayDB(), "combatStateLeaveColor", 0.7, 0.7, 0.7)
    end, function(r, g, b)
        SetTableRGB(GameplayDB(), "combatStateLeaveColor", r, g, b)
    end, { category = "Colors / Gameplay", frameType = "gameplay", attribute = "combatStateLeaveColor", defaultR = 0.7, defaultG = 0.7, defaultB = 0.7, apply = ApplyGameplayColors })
    RegisterGameplayBoolean("combatStateColorSync", "combatStateColorSync", "Sync Combat State Colors", false, {
        "sync combat state colors", "sync combat enter leave colors", "same combat state colors",
    }, { category = "Colors / Gameplay", frameType = "gameplay", apply = ApplyGameplayColors, reason = "MSUF_ASSISTANT_COMBAT_STATE_COLOR_SYNC" })
    ColorSetting("gameplay.crosshairInRangeColor", "Crosshair In-Range Color", {
        "crosshair in range color", "combat crosshair in range color", "melee range in color",
    }, function()
        return TableRGB(GameplayDB(), "crosshairInRangeColor", 0, 1, 0)
    end, function(r, g, b)
        SetTableRGB(GameplayDB(), "crosshairInRangeColor", r, g, b)
    end, { category = "Colors / Gameplay", frameType = "gameplay", attribute = "crosshairInRangeColor", defaultR = 0, defaultG = 1, defaultB = 0, apply = ApplyGameplayColors })
    ColorSetting("gameplay.crosshairOutRangeColor", "Crosshair Out-of-Range Color", {
        "crosshair out of range color", "crosshair out-of-range color", "combat crosshair out range color", "melee range out color",
    }, function()
        return TableRGB(GameplayDB(), "crosshairOutRangeColor", 1, 0, 0)
    end, function(r, g, b)
        SetTableRGB(GameplayDB(), "crosshairOutRangeColor", r, g, b)
    end, { category = "Colors / Gameplay", frameType = "gameplay", attribute = "crosshairOutRangeColor", defaultR = 1, defaultG = 0, defaultB = 0, apply = ApplyGameplayColors })
end
