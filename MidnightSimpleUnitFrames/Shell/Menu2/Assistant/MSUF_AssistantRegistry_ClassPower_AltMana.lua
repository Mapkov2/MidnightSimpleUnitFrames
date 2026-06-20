-- Assistant ClassPower alternative mana setting registry.
-- Loaded before MSUF_AssistantRegistry_ClassPower.lua; the main domain passes registry helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ClassPowerRegistry = A.ClassPowerRegistry or {}

function A.ClassPowerRegistry.RegisterAltManaSettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterBarsBoolean = ctx.RegisterBarsBoolean
    local RegisterBarsNumber = ctx.RegisterBarsNumber
    if type(RegisterBarsBoolean) ~= "function" or type(RegisterBarsNumber) ~= "function" then return end

    RegisterBarsBoolean("showAltMana", "altMana", "Alternative Mana Bar", false, {
        "alternative mana bar", "alt mana bar", "dual resource mana bar", "secondary mana bar",
        "show alternative mana", "show alt mana", "hide alternative mana", "hide alt mana",
    }, {
        category = "Global / Class Resources / Alternative Mana",
        frameType = "altMana",
        reason = "MSUF_ASSISTANT_ALT_MANA",
    })
    RegisterBarsNumber("altManaHeight", "height", "Alternative Mana Height", 4, 2, 30, {
        "alternative mana height", "alt mana height", "secondary mana height", "dual resource mana height",
    }, {
        category = "Global / Class Resources / Alternative Mana",
        frameType = "altMana",
        reason = "MSUF_ASSISTANT_ALT_MANA_HEIGHT",
    })
    RegisterBarsNumber("altManaOffsetY", "offsetY", "Alternative Mana Offset Y", -2, -50, 50, {
        "alternative mana y", "alternative mana y offset", "alt mana y", "alt mana y offset", "secondary mana y offset",
    }, {
        category = "Global / Class Resources / Alternative Mana",
        frameType = "altMana",
        reason = "MSUF_ASSISTANT_ALT_MANA_Y",
    })
end
