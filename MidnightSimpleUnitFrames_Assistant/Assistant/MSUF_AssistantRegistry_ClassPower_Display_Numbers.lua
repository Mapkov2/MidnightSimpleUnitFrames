-- Assistant ClassPower numeric display setting registry.
-- Loaded before MSUF_AssistantRegistry_ClassPower_Display.lua; the display registry calls this helper.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ClassPowerRegistry = A.ClassPowerRegistry or {}

function A.ClassPowerRegistry.RegisterDisplayNumberSettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterBarsNumber = ctx.RegisterBarsNumber
    local ClassPowerAliases = ctx.ClassPowerAliases
    if type(RegisterBarsNumber) ~= "function" or type(ClassPowerAliases) ~= "function" then return end

    RegisterBarsNumber("classPowerFontSize", "fontSize", "Class Resource Font Size", 16, 6, 32, ClassPowerAliases("font size", "text size", "number size"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_FONT_SIZE",
        exactAliases = {
            "class resource font",
            "class resource font size",
            "class resources font",
            "class resources font size",
            "class power font",
            "class power font size",
            "class resource text size",
            "class resources text size",
            "class power text size",
            "class resource number size",
            "class resources number size",
            "class resource numbers size",
            "class resource text bigger",
            "class resource text smaller",
            "class resource text larger",
            "class resource text size bigger",
            "class resource text size smaller",
            "class resource numbers bigger",
            "class resource numbers smaller",
            "resource text size",
            "resource number size",
            "combo point text size",
            "combo point number size",
            "combo point numbers size",
            "combo points text size",
            "combo points number size",
            "combo points numbers size",
        },
    })
    RegisterBarsNumber("classPowerTextLayer", "textLayer", "Class Resource Text Layer", 5, 0, 30, ClassPowerAliases("text layer", "number layer"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_TEXT_LAYER",
        exactAliases = {
            "class resource text layer",
            "class resources text layer",
            "class power text layer",
            "class resource number layer",
            "rune text layer",
            "essence text layer",
            "ebon might text layer",
        },
        description = "Orders Class Resource numeric text, Rune times, and Ebon Might duration text independently from the Class Resource bar and Player Power text.",
    })
    RegisterBarsNumber("classPowerTextOffsetX", "textOffsetX", "Class Resource Text Offset X", 0, -200, 200, ClassPowerAliases("text x", "text x offset", "number x offset"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_TEXT_X",
    })
    RegisterBarsNumber("classPowerTextOffsetY", "textOffsetY", "Class Resource Text Offset Y", 0, -200, 200, ClassPowerAliases("text y", "text y offset", "number y offset"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_TEXT_Y",
    })
    local RegisterDisplayBackgroundSetting = A.ClassPowerRegistry and A.ClassPowerRegistry.RegisterDisplayBackgroundSetting
    if type(RegisterDisplayBackgroundSetting) == "function" then
        RegisterDisplayBackgroundSetting(ctx)
    end
    RegisterBarsNumber("classPowerTickWidth", "separator", "Class Resource Separator Width", 1, 0, 4, ClassPowerAliases("separator", "separator width", "tick width", "pip separator", "divider", "divider width", "divider line width"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_SEPARATOR",
        exactAliases = {
            "class resource separator",
            "class resource separators",
            "class resource separator width",
            "class resources separator",
            "class resources separators",
            "class resources separator width",
            "class power separator",
            "class power separators",
            "class power separator width",
            "class resource pip separator",
            "class resource pip separators",
            "class resources pip separator",
            "class resources pip separators",
            "class resource divider",
            "class resource divider width",
            "class resource tick",
            "class resource tick width",
            "resource separator width",
            "combo point separator",
            "combo point separators",
            "combo point separator width",
            "combo point separators width",
            "combo points separator",
            "combo points separators",
            "combo points separator width",
            "combo points separators width",
            "holy power separator",
            "soul shard separator",
            "chi separator",
            "arcane charge separator",
            "rune separator",
            "essence separator",
        },
    })
    RegisterBarsNumber("classPowerOutline", "outline", "Class Resource Outline", 1, 0, 4, ClassPowerAliases(
        "outline", "border", "outline width", "border width",
        "outline thickness", "border thickness", "class resource outline thickness", "class resource border thickness",
        "make outline bigger", "make outline smaller", "make class resource outline bigger", "make class resource outline smaller",
        "turn off outline", "turn on outline", "turn off class resource outline", "turn on class resource outline"
    ), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_OUTLINE",
    })
    RegisterBarsNumber("classPowerFilledAlpha", "filledAlpha", "Class Resource Filled Opacity", 1.0, 0, 1, ClassPowerAliases("filled opacity", "filled alpha", "active opacity"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_FILLED_ALPHA",
        percent = true,
        step = 0.05,
    })
    RegisterBarsNumber("classPowerEmptyAlpha", "emptyAlpha", "Class Resource Empty Opacity", 0.3, 0, 1, ClassPowerAliases("empty opacity", "empty alpha", "inactive opacity"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_EMPTY_ALPHA",
        percent = true,
        step = 0.05,
    })
    RegisterBarsNumber("classPowerGap", "gap", "Class Resource Pip Gap", 0, 0, 8, ClassPowerAliases("pip gap", "gap", "resource gap", "point gap", "divider gap", "divider spacing", "separator spacing"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_GAP",
        exactAliases = {
            "class resource gap",
            "class resources gap",
            "class power gap",
            "class resource spacing",
            "class resources spacing",
            "class power spacing",
            "class resource pip gap",
            "class resource pip spacing",
            "class resources pip gap",
            "class resources pip spacing",
            "resource gap",
            "resource spacing",
            "combo point gap",
            "combo point gaps",
            "combo point spacing",
            "combo points gap",
            "combo points gaps",
            "combo points spacing",
            "holy power gap",
            "soul shard gap",
            "chi gap",
            "arcane charge gap",
            "rune gap",
            "essence gap",
        },
    })
end
