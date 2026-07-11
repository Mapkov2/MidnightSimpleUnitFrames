-- Assistant ClassPower texture setting registry.
-- Loaded before MSUF_AssistantRegistry_ClassPower.lua; the main domain passes registry helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ClassPowerRegistry = A.ClassPowerRegistry or {}

function A.ClassPowerRegistry.RegisterTextureSettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterBarsString = ctx.RegisterBarsString
    local ApplyClassPower = ctx.ApplyClassPower
    local NormalizeInheritedTexture = ctx.NormalizeInheritedTexture
    local NormalizeForegroundTexture = ctx.NormalizeForegroundTexture
    if type(RegisterBarsString) ~= "function" then return end

    RegisterBarsString("classPowerTexture", "texture", "Class Resource Foreground Texture", "", {
        "class resource foreground texture", "class resource texture", "class power foreground texture",
        "class power texture", "resource foreground texture", "resource bar foreground texture",
    }, {
        category = "Global / Class Resources",
        frameType = "classPower",
        apply = ApplyClassPower,
        reason = "MSUF_ASSISTANT_CLASSPOWER_TEXTURE",
        normalizeValue = NormalizeInheritedTexture,
        description = "Sets the Class Resource foreground texture, or leaves it empty to inherit the global bar texture.",
    })
    RegisterBarsString("classPowerBgTexture", "backgroundTexture", "Class Resource Background Texture", "", {
        "class resource background texture", "class resource bg texture", "class power background texture",
        "class power bg texture", "resource background texture", "resource bar background texture",
    }, {
        category = "Global / Class Resources",
        frameType = "classPower",
        apply = ApplyClassPower,
        reason = "MSUF_ASSISTANT_CLASSPOWER_BG_TEXTURE",
        normalizeValue = NormalizeForegroundTexture,
        description = "Sets the Class Resource background texture, or leaves it empty to follow the foreground texture.",
    })
end
