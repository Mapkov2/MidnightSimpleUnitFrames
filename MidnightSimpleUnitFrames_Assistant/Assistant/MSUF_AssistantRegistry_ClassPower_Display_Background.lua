-- Assistant ClassPower background display setting registry.
-- Loaded before MSUF_AssistantRegistry_ClassPower_Display_Numbers.lua; the numeric display registry calls this helper.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ClassPowerRegistry = A.ClassPowerRegistry or {}

function A.ClassPowerRegistry.RegisterDisplayBackgroundSetting(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterBarsNumber = ctx.RegisterBarsNumber
    local ClassPowerAliases = ctx.ClassPowerAliases
    if type(RegisterBarsNumber) ~= "function" or type(ClassPowerAliases) ~= "function" then return end

    RegisterBarsNumber("classPowerBgAlpha", "backgroundAlpha", "Class Resource Background Opacity", 0.3, 0, 1, ClassPowerAliases("background opacity", "background alpha", "empty background opacity", "bg alpha"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_BG_ALPHA",
        percent = true,
        step = 0.01,
        relativeStep = 0.05,
        booleanOnValue = 0.3,
        booleanOffValue = 0,
        booleanAliases = {
            ["show"] = 0.3,
            ["enable"] = 0.3,
            ["turnon"] = 0.3,
            ["withbackground"] = 0.3,
            ["backgroundon"] = 0.3,
            ["hide"] = 0,
            ["remove"] = 0,
            ["turnoff"] = 0,
            ["without"] = 0,
            ["withoutbackground"] = 0,
            ["nobackground"] = 0,
            ["backgroundoff"] = 0,
        },
        exactAliases = {
            "class resource background",
            "class resources background",
            "class power background",
            "show class resource background",
            "show class resources background",
            "turn on class resource background",
            "turn on class resources background",
            "enable class resource background",
            "enable class resources background",
            "hide class resource background",
            "hide class resources background",
            "turn off class resource background",
            "turn off class resources background",
            "disable class resource background",
            "disable class resources background",
            "combo point background",
            "combo points background",
            "show combo point background",
            "show combo points background",
            "hide combo point background",
            "hide combo points background",
            "turn off combo point background",
            "turn off combo points background",
            "resource background",
            "class resource background opacity",
            "class resources background opacity",
            "class power background opacity",
            "class resource background alpha",
            "class resources background alpha",
            "class power background alpha",
            "class resource empty background",
            "class resource empty background opacity",
            "class resources empty background opacity",
            "class resource bg",
            "class resource bg alpha",
            "class resources bg alpha",
            "class resource bg opacity",
            "class resources bg opacity",
        },
    })
end
