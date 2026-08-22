-- Assistant ClassPower display text setting registry.
-- Loaded before MSUF_AssistantRegistry_ClassPower_Display.lua; keeps text-mode aliases out of the display shard.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ClassPowerRegistry = A.ClassPowerRegistry or {}

function A.ClassPowerRegistry.RegisterDisplayTextSetting(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterBarsBoolean = ctx.RegisterBarsBoolean
    local RegisterBarsEnum = ctx.RegisterBarsEnum
    local ClassPowerAliases = ctx.ClassPowerAliases
    if type(RegisterBarsBoolean) ~= "function" or type(RegisterBarsEnum) ~= "function"
        or type(ClassPowerAliases) ~= "function" then return end

    RegisterBarsBoolean("classPowerShowText", "text", "Class Resource Text", false, ClassPowerAliases("text", "resource text", "class resource numbers", "class power numbers"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_TEXT",
        valueAliases = {
            ["astext"] = true,
            ["showtext"] = true,
            ["shownumbers"] = true,
            ["shownumber"] = true,
            ["numbersonly"] = true,
            ["textonly"] = true,
            ["aspips"] = false,
            ["asdots"] = false,
            ["asbars"] = false,
            ["showpips"] = false,
            ["showdots"] = false,
            ["showbars"] = false,
            ["pipsonly"] = false,
            ["dotsonly"] = false,
            ["hide numbers"] = false,
            ["hide number"] = false,
            ["hidetext"] = false,
            ["turnoffnumbers"] = false,
            ["turnoffnumber"] = false,
            ["turnofftext"] = false,
            ["disablenumbers"] = false,
            ["disablenumber"] = false,
            ["disabletext"] = false,
            ["withoutnumbers"] = false,
            ["nonumbers"] = false,
        },
        companionChanges = {
            { key = "bars.showClassPower", value = true, whenTextHas = { "show", "turn on", "enable" }, prepend = true },
        },
        exactAliases = {
            "class resource text",
            "class resources text",
            "class power text",
            "class resource numbers",
            "class resources numbers",
            "class power numbers",
            "resource numbers",
            "resource number",
            "show class resources as text",
            "show class resource as text",
            "show class resources as pips",
            "show class resource as pips",
            "show class resources as dots",
            "show class resource as dots",
            "show class resources as bars",
            "show class resource as bars",
            "show combo point numbers",
            "show combo points numbers",
            "hide combo point numbers",
            "hide combo points numbers",
            "show resource numbers",
            "show resource number",
            "hide resource numbers",
            "hide resource number",
            "combo point numbers",
            "combo points numbers",
            "resource text",
        },
    })
    RegisterBarsEnum("classPowerTextMode", "textMode", "Class Resource Text Mode", "AUTO", {
        "AUTO", "CURRENT", "MAX", "CURMAX",
    }, ClassPowerAliases("text mode", "resource text mode", "number format", "resource number format"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_TEXT_MODE",
        description = "Chooses the central Class Resource value format. Rune timers, Ebon Might duration and the Ironfur stack counter keep their native formats.",
        valueAliases = {
            automatic = "AUTO", auto = "AUTO", default = "AUTO", ["resource default"] = "AUTO",
            current = "CURRENT", value = "CURRENT", ["current value"] = "CURRENT",
            maximum = "MAX", max = "MAX", ["maximum value"] = "MAX",
            ["current max"] = "CURMAX", ["current maximum"] = "CURMAX",
            ["current / max"] = "CURMAX", ["current / maximum"] = "CURMAX",
        },
        companionChanges = {
            { key = "bars.showClassPower", value = true, prepend = true },
            { key = "bars.classPowerShowText", value = true, prepend = true },
        },
    })
end
