-- Global castbar behavior assistant settings.
-- Loaded before MSUF_AssistantRegistry_Global.lua; the main global registry passes shared helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.RegisterCastbarSettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterGeneralBoolean = ctx.RegisterGeneralBoolean
    local RegisterGeneralNumberSetting = ctx.RegisterGeneralNumberSetting
    local RegisterGeneralEnum = ctx.RegisterGeneralEnum
    local ApplyCastbar = ctx.ApplyCastbar

    if type(RegisterGeneralBoolean) ~= "function" or type(RegisterGeneralNumberSetting) ~= "function" then return end
    if type(RegisterGeneralEnum) ~= "function" or type(ApplyCastbar) ~= "function" then return end

    RegisterGeneralBoolean("castbarShowGlow", "glow", "Cast Bar Glow", false, {
        "castbar glow", "cast bar glow", "castbar glow effect", "zauberleiste glow",
    }, { category = "Global / Cast Bar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_GLOW" })
    RegisterGeneralBoolean("castbarShowLatency", "latency", "Cast Bar Latency Indicator", true, {
        "castbar latency", "latency indicator", "castbar latency indicator", "latenz anzeige",
    }, { category = "Global / Cast Bar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_LATENCY" })
    RegisterGeneralBoolean("castbarShowSpark", "spark", "Cast Bar Spark", false, {
        "castbar spark", "spark", "leading edge highlight", "zauberleiste spark",
    }, { category = "Global / Cast Bar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_SPARK" })
    RegisterGeneralBoolean("castbarSparkOverflow", "sparkOverflow", "Cast Bar Spark Overflow", true, {
        "spark overflow", "castbar spark overflow", "spark extends beyond bar",
    }, { category = "Global / Cast Bar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_SPARK_OVERFLOW" })
    RegisterGeneralBoolean("castbarShowChannelTicks", "channelTicks", "Spell-Specific Channel Tick Markers", false, {
        "channel ticks", "castbar ticks", "tick lines", "kanal ticks",
    }, { category = "Global / Cast Bar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_TICKS" })
    RegisterGeneralBoolean("castbarInterruptShake", "interruptShake", "Cast Bar Interrupt Shake", false, {
        "interrupt shake", "castbar shake", "shake on interrupt", "unterbrechung wackeln",
    }, { category = "Global / Cast Bar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_SHAKE" })
    RegisterGeneralBoolean("castbarUnifiedDirection", "unifiedDirection", "Unified Cast Bar Fill Direction", false, {
        "castbar unified direction", "same castbar direction", "all castbars same direction",
    }, { category = "Global / Cast Bar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_UNIFIED_DIRECTION" })
    RegisterGeneralBoolean("castbarOpositeDirectionTarget", "oppositeTargetDirection", "Opposite Fill Direction for Target", false, {
        "opposite target castbar direction", "target opposite fill direction", "target castbar opposite direction",
        "target castbar normal direction", "target castbar same direction", "target castbar not opposite",
    }, { category = "Global / Cast Bar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_TARGET_DIRECTION" })
    RegisterGeneralNumberSetting("castbarShakeStrength", "shakeStrength", "Cast Bar Shake Strength", 8, 0, 30, {
        "castbar shake strength", "shake strength", "interrupt shake strength",
    }, { category = "Global / Cast Bar", frameType = "castbarGlobal", apply = ApplyCastbar, reason = "MSUF_ASSISTANT_CASTBAR_SHAKE_STRENGTH" })
    RegisterGeneralEnum("castbarFillDirection", "fillDirection", "Cast Bar Fill Direction", "RTL", { "RTL", "LTR" }, {
        "castbar fill direction", "fill direction", "cast direction", "zauberleiste fuellrichtung",
        "castbar reverse fill", "castbar fill backwards", "castbar fill normal", "castbar normal direction",
    }, {
        category = "Global / Cast Bar",
        frameType = "castbarGlobal",
        apply = ApplyCastbar,
        reason = "MSUF_ASSISTANT_CASTBAR_FILL_DIRECTION",
        valueAliases = {
            left = "RTL",
            rtl = "RTL",
            righttoleft = "RTL",
            backwards = "RTL",
            backward = "RTL",
            reverse = "RTL",
            reversed = "RTL",
            links = "RTL",
            right = "LTR",
            ltr = "LTR",
            lefttoright = "LTR",
            normal = "LTR",
            forward = "LTR",
            rechts = "LTR",
        },
    })
end
