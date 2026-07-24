-- Assistant ClassPower detached power bar setting registry.
-- Loaded before MSUF_AssistantRegistry_ClassPower.lua; the main domain passes registry helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ClassPowerRegistry = A.ClassPowerRegistry or {}

function A.ClassPowerRegistry.RegisterDetachedPowerSettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterBarsEnum = ctx.RegisterBarsEnum
    local RegisterBarsNumber = ctx.RegisterBarsNumber
    local ApplyDetachedPowerBar = ctx.ApplyDetachedPowerBar
    local ApplyDetachedPowerBarOutline = ctx.ApplyDetachedPowerBarOutline
    local DETACHED_POWER_WIDTH_MODE_ALIASES = ctx.DETACHED_POWER_WIDTH_MODE_ALIASES

    if type(RegisterBarsEnum) ~= "function" or type(RegisterBarsNumber) ~= "function" then return end

    RegisterBarsEnum("detachedPowerBarWidthMode", "widthMode", "Detached Power Bar Width Mode", "manual", {
        "manual", "cooldown", "utility", "tracked_buffs",
    }, {
        "detached power bar width mode", "detached power width mode", "detached mana width mode",
        "detached power bar width source", "detached power follows cooldowns", "detached power follows tracked buffs",
        "class resources player power width mode", "class resources player power bar width mode",
        "class resources player power width source", "class resources player power bar width source",
    }, {
        category = "Global / Detached Power Bar",
        frameType = "detachedPowerBar",
        apply = ApplyDetachedPowerBar,
        reason = "MSUF_ASSISTANT_DETACHED_POWER_WIDTH_MODE",
        nilValue = "manual",
        valueAliases = DETACHED_POWER_WIDTH_MODE_ALIASES,
    })
    -- The detached texture keys are retired: the Player unit page and the Bars
    -- page own power art for the detached bar too, and their settings are
    -- registered by the unit/bars registries.
    RegisterBarsNumber("detachedPowerBarOutline", "outline", "Detached Power Bar Outline", 1, 0, 8, {
        "detached power bar outline", "detached power outline", "detached mana outline", "detached power bar border",
        "class resources player power outline", "class resources player power bar outline",
        "class resource player power outline", "player power outline in class resources",
    }, {
        category = "Global / Detached Power Bar",
        frameType = "detachedPowerBar",
        apply = ApplyDetachedPowerBarOutline,
        reason = "MSUF_ASSISTANT_DETACHED_POWER_OUTLINE",
        description = "Controls only the detached Player power outline managed by Class Resources. 0 disables the outline without changing fill or background textures.",
    })
end
