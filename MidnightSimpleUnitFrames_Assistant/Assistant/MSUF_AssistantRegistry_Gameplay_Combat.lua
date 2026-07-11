-- Assistant Gameplay combat timer and combat-state text registry.
-- Loaded before MSUF_AssistantRegistry_Gameplay.lua; feature runtime remains owned by Gameplay.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GameplayRegistry = A.GameplayRegistry or {}

local GAMEPLAY_ANCHOR_VALUES = { "none", "player", "target", "focus" }
local GAMEPLAY_ANCHOR_ALIASES = {
    none = "none",
    off = "none",
    noanchor = "none",
    player = "player",
    target = "target",
    focus = "focus",
}

function A.GameplayRegistry.RegisterCombatTextSettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterGameplayBoolean = ctx.RegisterGameplayBoolean
    local RegisterGameplayNumber = ctx.RegisterGameplayNumber
    local RegisterGameplayEnum = ctx.RegisterGameplayEnum
    local RegisterGameplayString = ctx.RegisterGameplayString

    if type(RegisterGameplayBoolean) ~= "function" or type(RegisterGameplayNumber) ~= "function" then return end
    if type(RegisterGameplayEnum) ~= "function" or type(RegisterGameplayString) ~= "function" then return end

    RegisterGameplayBoolean("enableCombatTimer", "enabled", "Combat Timer", false, {
        "combat timer enabled", "combat timer display",
    }, {
        category = "Gameplay / Combat Timer",
        frameType = "combatTimer",
        reason = "MSUF_ASSISTANT_COMBAT_TIMER",
        matchLabel = false,
    })
    RegisterGameplayEnum("combatTimerAnchor", "anchor", "Combat Timer Anchor", "none", GAMEPLAY_ANCHOR_VALUES, {
        "combat timer anchor", "combat timer attach to", "combat timer anchor frame",
    }, {
        category = "Gameplay / Combat Timer",
        frameType = "combatTimer",
        reason = "MSUF_ASSISTANT_COMBAT_TIMER_ANCHOR",
        valueAliases = GAMEPLAY_ANCHOR_ALIASES,
    })
    RegisterGameplayNumber("combatFontSize", "fontSize", "Combat Timer Size", 24, 10, 64, {
        "combat timer size", "combat timer font size", "combat timer text size",
    }, {
        category = "Gameplay / Combat Timer",
        frameType = "combatTimer",
        reason = "MSUF_ASSISTANT_COMBAT_TIMER_SIZE",
    })
    RegisterGameplayBoolean("lockCombatTimer", "locked", "Combat Timer Lock Position", false, {
        "combat timer lock", "lock combat timer", "combat timer locked",
    }, {
        category = "Gameplay / Combat Timer",
        frameType = "combatTimer",
        reason = "MSUF_ASSISTANT_COMBAT_TIMER_LOCK",
    })
    RegisterGameplayBoolean("combatTimerClickThrough", "clickThrough", "Combat Timer Click Through", true, {
        "combat timer click through", "combat timer click-through", "combat timer mouse clicks", "combat timer mouse input",
    }, {
        category = "Gameplay / Combat Timer",
        frameType = "combatTimer",
        reason = "MSUF_ASSISTANT_COMBAT_TIMER_CLICK_THROUGH",
    })
    RegisterGameplayNumber("combatOffsetX", "offsetX", "Combat Timer Offset X", 0, -800, 800, {
        "combat timer x", "combat timer x offset", "combat timer horizontal offset",
    }, {
        category = "Gameplay / Combat Timer",
        frameType = "combatTimer",
        reason = "MSUF_ASSISTANT_COMBAT_TIMER_X",
    })
    RegisterGameplayNumber("combatOffsetY", "offsetY", "Combat Timer Offset Y", -200, -800, 800, {
        "combat timer y", "combat timer y offset", "combat timer vertical offset",
    }, {
        category = "Gameplay / Combat Timer",
        frameType = "combatTimer",
        reason = "MSUF_ASSISTANT_COMBAT_TIMER_Y",
    })

    RegisterGameplayBoolean("enableCombatStateText", "enabled", "Combat Enter/Leave Text", false, {
        "combat state text enabled", "combat enter leave text", "combat enter text display", "combat leave text display",
    }, {
        category = "Gameplay / Combat Enter/Leave",
        frameType = "combatState",
        reason = "MSUF_ASSISTANT_COMBAT_STATE",
        matchLabel = false,
    })
    RegisterGameplayBoolean("lockCombatState", "locked", "Combat Enter/Leave Lock Position", false, {
        "combat state lock", "lock combat state", "combat enter leave lock", "lock combat enter leave text",
    }, {
        category = "Gameplay / Combat Enter/Leave",
        frameType = "combatState",
        reason = "MSUF_ASSISTANT_COMBAT_STATE_LOCK",
    })
    RegisterGameplayString("combatStateEnterText", "enterText", "Combat Enter Text", "+Combat", {
        "combat enter text", "enter combat text", "combat state enter text",
    }, {
        category = "Gameplay / Combat Enter/Leave",
        frameType = "combatState",
        reason = "MSUF_ASSISTANT_COMBAT_STATE_ENTER_TEXT",
    })
    RegisterGameplayString("combatStateLeaveText", "leaveText", "Combat Leave Text", "-Combat", {
        "combat leave text", "leave combat text", "combat state leave text",
    }, {
        category = "Gameplay / Combat Enter/Leave",
        frameType = "combatState",
        reason = "MSUF_ASSISTANT_COMBAT_STATE_LEAVE_TEXT",
    })
    RegisterGameplayNumber("combatStateFontSize", "fontSize", "Combat Enter/Leave Text Size", 24, 10, 64, {
        "combat state text size", "combat enter leave text size", "combat state font size",
    }, {
        category = "Gameplay / Combat Enter/Leave",
        frameType = "combatState",
        reason = "MSUF_ASSISTANT_COMBAT_STATE_SIZE",
    })
    RegisterGameplayNumber("combatStateDuration", "duration", "Combat Enter/Leave Duration", 1.5, 0.5, 5.0, {
        "combat state duration", "combat enter leave duration", "combat text duration",
    }, {
        category = "Gameplay / Combat Enter/Leave",
        frameType = "combatState",
        reason = "MSUF_ASSISTANT_COMBAT_STATE_DURATION",
        step = 0.5,
    })
    RegisterGameplayNumber("combatStateOffsetX", "offsetX", "Combat Enter/Leave Offset X", 0, -800, 800, {
        "combat state x", "combat state x offset", "combat enter leave x", "combat text x offset",
    }, {
        category = "Gameplay / Combat Enter/Leave",
        frameType = "combatState",
        reason = "MSUF_ASSISTANT_COMBAT_STATE_X",
    })
    RegisterGameplayNumber("combatStateOffsetY", "offsetY", "Combat Enter/Leave Offset Y", 80, -800, 800, {
        "combat state y", "combat state y offset", "combat enter leave y", "combat text y offset",
    }, {
        category = "Gameplay / Combat Enter/Leave",
        frameType = "combatState",
        reason = "MSUF_ASSISTANT_COMBAT_STATE_Y",
    })
end
