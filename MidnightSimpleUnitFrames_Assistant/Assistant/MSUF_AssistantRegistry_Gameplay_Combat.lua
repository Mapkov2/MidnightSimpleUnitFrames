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

    RegisterGameplayBoolean("enableApexItDevAura", "enabled", "Subtlety Rogue APEX IT / SECTECH", false, {
        "apex it", "apex sectech", "apex secret technique", "apex it dev aura",
        "apex it stack counter", "shadow techniques stacks", "darkest night ancient arts warning",
        "subtlety rogue apex warning", "four targets secret technique",
        "secret technique ready", "sectech ready without darkest night",
    }, {
        category = "Gameplay / Developer Auras",
        frameType = "apexItDevAura",
        reason = "MSUF_ASSISTANT_APEX_IT_DEV_AURA",
        matchLabel = false,
    })
    RegisterGameplayBoolean("enableApexNameplateRangeDetection", "enabled", "APEX Nameplate Target Detection", true, {
        "apex nameplate detection", "apex target count detection", "apex range scan",
        "apex nameplate performance", "disable apex target counter",
    }, {
        category = "Gameplay / Developer Auras",
        frameType = "apexTargetDetection",
        reason = "MSUF_ASSISTANT_APEX_TARGET_DETECTION",
        matchLabel = false,
    })
    RegisterGameplayBoolean("enableApexRangeCounter", "enabled", "Subtlety Rogue Nameplate Range Counter", false, {
        "apex range counter", "nameplate range counter", "subtlety rogue range diagnostic",
        "eviscerate range counter", "enemy nameplates in range",
    }, {
        category = "Gameplay / Developer Auras",
        frameType = "apexRangeCounter",
        reason = "MSUF_ASSISTANT_APEX_RANGE_COUNTER",
        matchLabel = false,
    })
    RegisterGameplayNumber("apexRangeCounterFontSize", "fontSize", "Nameplate Range Counter Text Size", 18, 10, 36, {
        "range counter size", "nameplate counter text size", "apex range counter font size",
    }, {
        category = "Gameplay / Developer Auras",
        frameType = "apexRangeCounter",
        reason = "MSUF_ASSISTANT_APEX_RANGE_COUNTER_SIZE",
    })
    RegisterGameplayNumber("apexRangeCounterOffsetX", "offsetX", "Nameplate Range Counter Offset X", 0, -800, 800, {
        "range counter x", "nameplate counter x offset", "apex range counter horizontal offset",
    }, {
        category = "Gameplay / Developer Auras",
        frameType = "apexRangeCounter",
        reason = "MSUF_ASSISTANT_APEX_RANGE_COUNTER_X",
    })
    RegisterGameplayNumber("apexRangeCounterOffsetY", "offsetY", "Nameplate Range Counter Offset Y", 70, -800, 800, {
        "range counter y", "nameplate counter y offset", "apex range counter vertical offset",
    }, {
        category = "Gameplay / Developer Auras",
        frameType = "apexRangeCounter",
        reason = "MSUF_ASSISTANT_APEX_RANGE_COUNTER_Y",
    })
    RegisterGameplayBoolean("enableShadowTechniquesStackHighlight", "enabled", "Shadow Techniques 5+ Stack Glow", false, {
        "shadow techniques glow", "shadow techniques stack highlight", "shadow techniques 5 stacks",
        "subtlety rogue stack glow", "cooldown manager shadow techniques highlight",
    }, {
        category = "Gameplay / Developer Auras",
        frameType = "shadowTechniquesStackHighlight",
        reason = "MSUF_ASSISTANT_SHADOW_TECHNIQUES_STACK_HIGHLIGHT",
        matchLabel = false,
    })
    RegisterGameplayNumber("shadowTechniquesGlowScale", "glowScale", "Shadow Techniques Glow Size", 100, 75, 175, {
        "shadow techniques glow size", "shadow techniques glow scale", "stack glow size",
    }, {
        category = "Gameplay / Developer Auras",
        frameType = "shadowTechniquesStackHighlight",
        reason = "MSUF_ASSISTANT_SHADOW_TECHNIQUES_GLOW_SIZE",
        step = 5,
    })
    RegisterGameplayNumber("shadowTechniquesGlowStrength", "glowStrength", "Shadow Techniques Glow Strength", 80, 10, 100, {
        "shadow techniques glow strength", "shadow techniques glow opacity", "stack glow strength",
    }, {
        category = "Gameplay / Developer Auras",
        frameType = "shadowTechniquesStackHighlight",
        reason = "MSUF_ASSISTANT_SHADOW_TECHNIQUES_GLOW_STRENGTH",
        step = 5,
    })
    RegisterGameplayNumber("apexItFontSize", "fontSize", "APEX IT Text Size", 32, 10, 64, {
        "apex it size", "apex it text size", "apex it font size",
    }, {
        category = "Gameplay / Developer Auras",
        frameType = "apexItDevAura",
        reason = "MSUF_ASSISTANT_APEX_IT_SIZE",
    })
    RegisterGameplayNumber("apexItOffsetX", "offsetX", "APEX IT Offset X", 0, -800, 800, {
        "apex it x", "apex it x offset", "apex it horizontal offset",
    }, {
        category = "Gameplay / Developer Auras",
        frameType = "apexItDevAura",
        reason = "MSUF_ASSISTANT_APEX_IT_X",
    })
    RegisterGameplayNumber("apexItOffsetY", "offsetY", "APEX IT Offset Y", 140, -800, 800, {
        "apex it y", "apex it y offset", "apex it vertical offset",
    }, {
        category = "Gameplay / Developer Auras",
        frameType = "apexItDevAura",
        reason = "MSUF_ASSISTANT_APEX_IT_Y",
    })
end
