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
    local RegisterBarsString = ctx.RegisterBarsString
    local RegisterBarsNumber = ctx.RegisterBarsNumber
    local ApplyDetachedPowerBar = ctx.ApplyDetachedPowerBar
    local ApplyDetachedPowerBarOutline = ctx.ApplyDetachedPowerBarOutline
    local NormalizeInheritedTexture = ctx.NormalizeInheritedTexture
    local NormalizeForegroundTexture = ctx.NormalizeForegroundTexture
    local DETACHED_POWER_WIDTH_MODE_ALIASES = ctx.DETACHED_POWER_WIDTH_MODE_ALIASES

    if type(RegisterBarsEnum) ~= "function" or type(RegisterBarsString) ~= "function" then return end
    if type(RegisterBarsNumber) ~= "function" or type(NormalizeInheritedTexture) ~= "function" then return end
    if type(NormalizeForegroundTexture) ~= "function" then return end

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
    RegisterBarsString("detachedPowerBarTexture", "texture", "Detached Power Bar Foreground Texture", "", {
        "detached power bar foreground texture", "detached power bar texture", "detached power texture",
        "detached mana foreground texture", "detached mana texture",
        "class resources player power foreground texture", "class resources player power bar foreground texture",
        "class resources player power texture", "class resources player power bar texture",
        "class resource player power foreground texture", "class resource player power bar texture",
        "player power texture in class resources", "player power bar texture in class resources",
    }, {
        category = "Global / Detached Power Bar",
        frameType = "detachedPowerBar",
        apply = ApplyDetachedPowerBar,
        reason = "MSUF_ASSISTANT_DETACHED_POWER_TEXTURE",
        normalizeValue = NormalizeInheritedTexture,
        description = "Sets the detached power bar foreground texture, or leaves it empty to inherit the global bar texture.",
    })
    RegisterBarsString("detachedPowerBarBgTexture", "backgroundTexture", "Detached Power Bar Background Texture", "", {
        "detached power bar background texture", "detached power bar bg texture", "detached power background texture",
        "detached mana background texture", "detached mana bg texture",
        "class resources player power background texture", "class resources player power bar background texture",
        "class resources player power bg texture", "class resources player power bar bg texture",
        "class resource player power background texture", "player power background texture in class resources",
    }, {
        category = "Global / Detached Power Bar",
        frameType = "detachedPowerBar",
        apply = ApplyDetachedPowerBar,
        reason = "MSUF_ASSISTANT_DETACHED_POWER_BG_TEXTURE",
        normalizeValue = NormalizeForegroundTexture,
        description = "Sets the detached power bar background texture, or leaves it empty to follow the foreground texture.",
    })
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
