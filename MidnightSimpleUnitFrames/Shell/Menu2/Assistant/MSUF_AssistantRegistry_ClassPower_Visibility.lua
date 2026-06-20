-- Assistant ClassPower visibility setting registry.
-- Loaded before MSUF_AssistantRegistry_ClassPower.lua; the main domain passes registry helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ClassPowerRegistry = A.ClassPowerRegistry or {}

function A.ClassPowerRegistry.RegisterVisibilitySettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterBarsBoolean = ctx.RegisterBarsBoolean
    local ClassPowerAliases = ctx.ClassPowerAliases
    if type(RegisterBarsBoolean) ~= "function" or type(ClassPowerAliases) ~= "function" then return end

    RegisterBarsBoolean("classPowerHideOOC", "hideOOC", "Class Resource Hide Out of Combat", false, ClassPowerAliases("hide out of combat", "hide ooc", "out of combat hide", "hide when out of combat", "hide class resource out of combat", "hide class power out of combat", "hide class bar out of combat"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_HIDE_OOC",
        exactAliases = {
            "class resource out of combat",
            "class resources out of combat",
            "class power out of combat",
            "class resource ooc",
            "class resources ooc",
            "class power ooc",
            "hide class resource out of combat",
            "hide class resources out of combat",
            "hide class power out of combat",
            "show class resource out of combat",
            "show class resources out of combat",
            "show class power out of combat",
        },
    })
    RegisterBarsBoolean("classPowerHideWhenFull", "hideFull", "Class Resource Hide When Full", false, ClassPowerAliases("hide when full", "hide full", "full hide", "hide class resource when full", "hide class power when full"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_HIDE_FULL",
        exactAliases = {
            "class resource when full",
            "class resources when full",
            "class power when full",
            "combo points when full",
            "hide class resource when full",
            "hide class resources when full",
            "hide class power when full",
            "hide combo points when full",
            "show class resource when full",
            "show class resources when full",
            "show class power when full",
            "show combo points when full",
        },
    })
    RegisterBarsBoolean("classPowerHideWhenEmpty", "hideEmpty", "Class Resource Hide When Empty", false, ClassPowerAliases("hide when empty", "hide empty", "empty hide", "hide class resource when empty", "hide class power when empty"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_HIDE_EMPTY",
        exactAliases = {
            "class resource when empty",
            "class resources when empty",
            "class power when empty",
            "combo points when empty",
            "hide class resource when empty",
            "hide class resources when empty",
            "hide class power when empty",
            "hide combo points when empty",
            "show class resource when empty",
            "show class resources when empty",
            "show class power when empty",
            "show combo points when empty",
        },
    })
end
