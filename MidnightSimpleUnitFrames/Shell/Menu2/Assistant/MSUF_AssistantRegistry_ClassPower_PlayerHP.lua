-- Assistant ClassPower player-HP bridge registry.
-- Loaded before MSUF_AssistantRegistry_ClassPower.lua; the main domain passes helper context.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ClassPowerRegistry = A.ClassPowerRegistry or {}

local function PlayerHPOpts(applyFn, reason, opts)
    opts = opts or {}
    opts.category = "Global / Class Resources / Player HP Bar"
    opts.frameType = "classPowerPlayerHP"
    opts.apply = applyFn
    opts.reason = reason
    return opts
end

function A.ClassPowerRegistry.RegisterPlayerHPSettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterBarsBoolean = ctx.RegisterBarsBoolean
    local RegisterBarsString = ctx.RegisterBarsString
    local RegisterBarsNumber = ctx.RegisterBarsNumber
    local RegisterBarsEnum = ctx.RegisterBarsEnum
    local ApplyClassPower = ctx.ApplyClassPower
    local NormalizeInheritedTexture = ctx.NormalizeInheritedTexture
    local NormalizeForegroundTexture = ctx.NormalizeForegroundTexture

    if type(RegisterBarsBoolean) ~= "function" or type(RegisterBarsString) ~= "function" then return end
    if type(RegisterBarsNumber) ~= "function" or type(RegisterBarsEnum) ~= "function" then return end
    if type(ApplyClassPower) ~= "function" then return end

    local Data = A.ClassPowerRegistryData or {}
    local PLAYER_HP_ANCHOR_ALIASES = Data.PLAYER_HP_ANCHOR_ALIASES or {}
    local PLAYER_HP_WIDTH_MODE_ALIASES = Data.PLAYER_HP_WIDTH_MODE_ALIASES or {}
    local PLAYER_HP_SHAPE_ALIASES = Data.PLAYER_HP_SHAPE_ALIASES or {}
    local PLAYER_HP_COLOR_MODE_ALIASES = Data.PLAYER_HP_COLOR_MODE_ALIASES or {}

    RegisterBarsBoolean("playerHPBarEnabled", "enabled", "Class Resources Player HP Bar", false, {
        "player hp bar", "second player hp bar", "duplicate hp bar", "duplicate health bar",
        "class resource hp bar", "class resources hp bar", "show player hp twice",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_ENABLED", {
        description = "Enables the optional second Player health bar managed by Class Resources.",
    }))
    RegisterBarsEnum("playerHPBarAnchor", "anchor", "Class Resources Player HP Anchor", "CLASS_TOP", {
        "CLASS_TOP", "CLASS_BOTTOM", "POWER_TOP", "POWER_BOTTOM",
    }, {
        "player hp anchor", "second hp anchor", "duplicate hp anchor", "class resource hp anchor",
        "above class resource", "below class resource", "above player power", "below player power",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_ANCHOR", {
        valueAliases = PLAYER_HP_ANCHOR_ALIASES,
    }))
    RegisterBarsEnum("playerHPBarWidthMode", "widthMode", "Class Resources Player HP Width Mode", "class", {
        "class", "power", "player", "custom",
    }, {
        "player hp width mode", "second hp width mode", "duplicate hp width mode",
        "player hp follows class resource", "player hp follows power", "player hp custom width",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_WIDTH_MODE", {
        valueAliases = PLAYER_HP_WIDTH_MODE_ALIASES,
    }))
    RegisterBarsNumber("playerHPBarWidth", "width", "Class Resources Player HP Width", 0, 20, 1200, {
        "player hp width", "second hp width", "duplicate hp width",
        "class resource hp width", "class resources player hp width",
        "class resources player hp bar width", "second player hp bar width",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_WIDTH"))
    RegisterBarsNumber("playerHPBarHeight", "height", "Class Resources Player HP Height", 6, 2, 80, {
        "player hp height", "second hp height", "duplicate hp height",
        "class resource hp height", "class resources player hp height",
        "class resources player hp bar height", "second player hp bar height",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_HEIGHT"))
    RegisterBarsNumber("playerHPBarGap", "gap", "Class Resources Player HP Gap", 2, 0, 60, {
        "player hp gap", "second hp gap", "duplicate hp gap", "class resource hp gap",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_GAP"))
    RegisterBarsNumber("playerHPBarOffsetX", "offsetX", "Class Resources Player HP Offset X", 0, -1000, 1000, {
        "player hp x", "player hp offset x", "second hp x", "duplicate hp x",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_X"))
    RegisterBarsNumber("playerHPBarOffsetY", "offsetY", "Class Resources Player HP Offset Y", 0, -1000, 1000, {
        "player hp y", "player hp offset y", "second hp y", "duplicate hp y",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_Y"))
    RegisterBarsNumber("playerHPBarFrameLevelOffset", "frameLevel", "Class Resources Player HP Frame Level", 7, 0, 30, {
        "player hp frame level", "player hp layer", "second hp frame level", "duplicate hp layer",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_LAYER"))
    RegisterBarsEnum("playerHPBarShape", "shape", "Class Resources Player HP Shape", "BAR", {
        "BAR", "FOLLOW_POWER", "ROUND", "CRYSTAL", "ORB",
    }, {
        "player hp shape", "second hp shape", "duplicate hp shape", "class resources player hp shape",
        "class resource hp shape", "second player hp bar shape", "player hp follow power shape",
        "second hp follow player power", "player hp orb", "second hp orb", "player hp round",
        "player hp crystal", "health orb", "hp orb",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_SHAPE", {
        valueAliases = PLAYER_HP_SHAPE_ALIASES,
        description = "Controls the second Player HP bar shape. Follow Player Power mirrors the effective detached Player power shape; Orb uses a single vertical fill.",
    }))
    RegisterBarsNumber("playerHPBarOrbSize", "orbSize", "Class Resources Player HP Orb Size", 54, 20, 160, {
        "player hp orb size", "second hp orb size", "duplicate hp orb size",
        "class resources player hp orb size", "health orb size", "hp orb size",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_ORB_SIZE", {
        description = "Controls the explicit Orb size for the second Player HP bar. Follow Player Power inherits the Player power orb size.",
    }))
    RegisterBarsString("playerHPBarTexture", "texture", "Class Resources Player HP Foreground Texture", "", {
        "player hp foreground texture", "player hp texture", "second hp texture", "duplicate hp texture",
        "class resource hp texture",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_TEXTURE", {
        normalizeValue = NormalizeInheritedTexture,
        description = "Sets the second Player HP foreground texture, or leaves it empty to inherit the global bar texture.",
    }))
    RegisterBarsString("playerHPBarBgTexture", "backgroundTexture", "Class Resources Player HP Background Texture", "", {
        "player hp background texture", "player hp bg texture", "second hp background texture",
        "duplicate hp background texture", "class resource hp background texture",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_BG_TEXTURE", {
        normalizeValue = NormalizeForegroundTexture,
        description = "Sets the second Player HP background texture, or leaves it empty to follow the foreground texture.",
    }))
    RegisterBarsNumber("playerHPBarBgAlpha", "backgroundAlpha", "Class Resources Player HP Background Opacity", 0.35, 0, 1, {
        "player hp background opacity", "player hp bg alpha", "second hp background opacity",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_BG_ALPHA", {
        percent = true,
        step = 0.01,
    }))
    RegisterBarsNumber("playerHPBarOutline", "outline", "Class Resources Player HP Outline", 1, 0, 8, {
        "player hp outline", "player hp border", "second hp outline", "duplicate hp outline",
        "class resources player hp outline", "class resources player hp border",
        "class resources player hp bar outline", "second player hp bar outline",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_OUTLINE", {
        description = "Controls only the second Player HP bar outline. 0 disables the outline without changing fill or background textures.",
    }))
    RegisterBarsEnum("playerHPBarColorMode", "colorMode", "Class Resources Player HP Color Mode", "GLOBAL", {
        "GLOBAL", "CLASS", "DARK", "GRADIENT",
    }, {
        "player hp color", "player hp color mode", "second hp color", "second hp color mode",
        "duplicate hp color", "duplicate health color", "class resources player hp color",
        "second player hp class color", "second player hp class colour",
        "second player hp dark mode", "second player hp hp gradient", "second player hp gradient",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_COLOR_MODE", {
        valueAliases = PLAYER_HP_COLOR_MODE_ALIASES,
        description = "Controls the color source for the second Player HP bar: Global, Class Color, Dark Mode, or HP Gradient.",
    }))
    RegisterBarsBoolean("playerHPBarSmoothFill", "smoothFill", "Class Resources Player HP Smooth Fill", false, {
        "player hp smooth fill", "second hp smooth fill", "duplicate hp smooth fill",
        "class resources player hp smooth fill", "smooth second player hp bar",
    }, PlayerHPOpts(ApplyClassPower, "MSUF_ASSISTANT_CLASSPOWER_PLAYER_HP_SMOOTH", {
        description = "Enables optional smooth interpolation for the second Player HP bar. Off uses direct native SetValue updates.",
    }))
    local RegisterPlayerHPTextSettings = A.ClassPowerRegistry and A.ClassPowerRegistry.RegisterPlayerHPTextSettings
    if type(RegisterPlayerHPTextSettings) == "function" then
        RegisterPlayerHPTextSettings(ctx)
    end
end
