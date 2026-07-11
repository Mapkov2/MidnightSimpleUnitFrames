-- Assistant ClassPower base setting registry.
-- Loaded before MSUF_AssistantRegistry_ClassPower.lua; the main ClassPower hub passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ClassPowerRegistry = A.ClassPowerRegistry or {}

function A.ClassPowerRegistry.RegisterBaseSettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterBarsBoolean = ctx.RegisterBarsBoolean
    local RegisterBarsNumber = ctx.RegisterBarsNumber
    local RegisterBarsEnum = ctx.RegisterBarsEnum
    local ClassPowerAliases = ctx.ClassPowerAliases
    local CLASS_POWER_WIDTH_MODE_ALIASES = ctx.CLASS_POWER_WIDTH_MODE_ALIASES
    local CLASS_POWER_SHAPE_ALIASES = ctx.CLASS_POWER_SHAPE_ALIASES
    local CLASS_POWER_SHAPE_ALIGN_ALIASES = ctx.CLASS_POWER_SHAPE_ALIGN_ALIASES
    local RegisterBaseGeometrySettings = A.ClassPowerRegistry and A.ClassPowerRegistry.RegisterBaseGeometrySettings

    if type(RegisterBarsBoolean) ~= "function" or type(RegisterBarsNumber) ~= "function" then return end
    if type(RegisterBarsEnum) ~= "function" or type(ClassPowerAliases) ~= "function" then return end
    if type(RegisterBaseGeometrySettings) ~= "function" then return end

    RegisterBarsBoolean("showClassPower", "enabled", "Class Resource", true, {
        "class power enabled", "class resource enabled", "class resources enabled",
        "class power bar enabled", "class resource bar enabled", "resource bar enabled",
    }, {
        reason = "MSUF_ASSISTANT_CLASSPOWER_ENABLED",
        matchLabel = false,
        exactAliases = {
            "show class resource",
            "show class resources",
            "show class power",
            "show class power bar",
            "show class resource bar",
            "show class resources bar",
            "show combo points",
            "turn on class resource",
            "turn on class resources",
            "turn on class power",
            "turn on class power bar",
            "turn on class resource bar",
            "enable class resource",
            "enable class resources",
            "enable class power",
            "enable class power bar",
            "enable class resource bar",
            "class resource on",
            "class resources on",
            "class power on",
            "hide class resource",
            "hide class resources",
            "hide class power",
            "hide class power bar",
            "hide class resource bar",
            "hide class resources bar",
            "hide combo points",
            "turn off class resource",
            "turn off class resources",
            "turn off class power",
            "turn off class power bar",
            "turn off class resource bar",
            "disable class resource",
            "disable class resources",
            "disable class power",
            "disable class power bar",
            "disable class resource bar",
            "class resource off",
            "class resources off",
            "class power off",
        },
        description = "Enables or disables MSUF Class Resources live outside combat.",
    })
    RegisterBarsNumber("classPowerHeight", "height", "Class Resource Height", 4, 1, 40, ClassPowerAliases("height", "class resource bar height"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_HEIGHT",
        exactAliases = {
            "class resource height",
            "class resources height",
            "class power height",
            "class resource bar height",
            "class resources bar height",
            "class resource size",
            "class resources size",
            "class power size",
            "class resource bigger",
            "class resources bigger",
            "class resource larger",
            "class resources larger",
            "class resource smaller",
            "class resources smaller",
            "combo point bigger",
            "combo point smaller",
            "combo points bigger",
            "combo points smaller",
            "holy power bigger",
            "holy power smaller",
            "soul shards bigger",
            "soul shards smaller",
            "chi bigger",
            "chi smaller",
            "arcane charges bigger",
            "arcane charges smaller",
            "runes bigger",
            "runes smaller",
            "essence bigger",
            "essence smaller",
        },
    })
    RegisterBarsEnum("classPowerShape", "shape", "Class Resource Shape", "BAR", {
        "BAR", "CIRCLE", "DIAMOND", "HEX",
    }, ClassPowerAliases(
        "shape", "class resource shape", "class resources shape", "class power shape",
        "combo point shape", "combo points shape", "holy power shape", "soul shard shape", "chi shape",
        "arcane charge shape", "rune shape", "essence shape"
    ), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_SHAPE",
        valueAliases = CLASS_POWER_SHAPE_ALIASES,
    })
    RegisterBarsEnum("classPowerWidthMode", "widthMode", "Class Resource Width Mode", "player", {
        "player", "cooldown", "utility", "tracked_buffs", "custom", "auto_pips",
    }, ClassPowerAliases("width mode", "class resource width source", "class power width source", "auto fit pips", "fit pips", "compact pips"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_WIDTH_MODE",
        valueAliases = CLASS_POWER_WIDTH_MODE_ALIASES,
        exactAliases = {
            "class resource width mode",
            "class resources width mode",
            "class power width mode",
            "class resource width source",
            "class power width source",
            "class resources width",
            "class resource width to player",
            "class resources to player width",
            "class resource same width as player",
            "class resource match player",
            "class resource match player frame",
            "class resource width to cooldowns",
            "class resource width to essential cooldowns",
            "class resource width to cooldownmanager",
            "class resource width to utility cooldowns",
            "class resource width to tracked buffs",
            "class resources width to cooldowns",
            "class resources width to essential cooldowns",
            "class resources width to cooldownmanager",
            "class resources width to utility cooldowns",
            "class resources width to tracked buffs",
            "class resource width mode custom",
            "class resource width mode manual",
            "class resource auto fit pips",
            "class resource fit pips",
            "class resource compact pips",
        },
    })
    RegisterBarsEnum("classPowerShapeAlign", "shapeAlign", "Class Resource Shape Alignment", "CENTER", {
        "LEFT", "CENTER", "RIGHT",
    }, ClassPowerAliases("shape alignment", "pip alignment", "align pips", "class resource alignment", "class power alignment"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_SHAPE_ALIGN",
        valueAliases = CLASS_POWER_SHAPE_ALIGN_ALIASES,
    })
    RegisterBaseGeometrySettings(ctx)
end
