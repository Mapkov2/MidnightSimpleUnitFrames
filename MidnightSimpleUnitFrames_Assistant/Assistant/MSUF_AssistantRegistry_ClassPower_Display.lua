-- Assistant ClassPower display setting registry.
-- Loaded before MSUF_AssistantRegistry_ClassPower.lua; the main domain passes registry helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ClassPowerRegistry = A.ClassPowerRegistry or {}

function A.ClassPowerRegistry.RegisterDisplaySettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterBarsBoolean = ctx.RegisterBarsBoolean
    local RegisterBarsNumber = ctx.RegisterBarsNumber
    local RegisterBarsEnum = ctx.RegisterBarsEnum
    local ClassPowerAliases = ctx.ClassPowerAliases
    local COMBO_POINT_COLOR_MODE_ALIASES = ctx.COMBO_POINT_COLOR_MODE_ALIASES
    if type(RegisterBarsBoolean) ~= "function" or type(RegisterBarsNumber) ~= "function" then return end
    if type(RegisterBarsEnum) ~= "function" or type(ClassPowerAliases) ~= "function" then return end

    RegisterBarsBoolean("showChargedComboPoints", "chargedComboPoints", "Empowered Combo Points", true, ClassPowerAliases("empowered combo points", "charged combo points", "combo point charges"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_CHARGED_COMBO_POINTS",
    })
    local RegisterDisplayTextSetting = A.ClassPowerRegistry and A.ClassPowerRegistry.RegisterDisplayTextSetting
    if type(RegisterDisplayTextSetting) == "function" then
        RegisterDisplayTextSetting({
            RegisterBarsBoolean = RegisterBarsBoolean,
            ClassPowerAliases = ClassPowerAliases,
        })
    end
    RegisterBarsBoolean("runeShowTime", "runeTime", "Rune Time", true, ClassPowerAliases("rune time", "rune timers", "rune timer text"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_RUNE_TIME",
    })
    RegisterBarsBoolean("classPowerFillReverse", "reverseFill", "Class Resource Reverse Fill", false, ClassPowerAliases(
        "reverse fill", "reverse direction", "fill right to left", "right to left fill",
        "fill backwards", "backwards fill", "fill backward", "class resource fill normal",
        "class resource normal direction", "class resource fill left to right"
    ), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_REVERSE_FILL",
        exactAliases = {
            "class resource fill",
            "class resources fill",
            "class power fill",
            "class resource fill direction",
            "class resources fill direction",
            "class power fill direction",
            "class resource fill right to left",
            "class resources fill right to left",
            "class power fill right to left",
            "class resource fill backwards",
            "class resources fill backwards",
            "class power fill backwards",
            "class resource reverse fill",
            "class resources reverse fill",
            "class power reverse fill",
            "reverse class resource fill",
            "reverse class resources fill",
            "reverse class power fill",
            "class resource fill normal direction",
            "class resources fill normal direction",
            "class power fill normal direction",
            "class resource fill left to right",
            "class resources fill left to right",
            "class power fill left to right",
        },
        valueAliases = {
            ["right to left"] = true,
            ["fill right to left"] = true,
            ["class resource fill right to left"] = true,
            ["class resources fill right to left"] = true,
            ["class power fill right to left"] = true,
            backwards = true,
            backward = true,
            ["fill backwards"] = true,
            ["fill backward"] = true,
            ["reverse fill"] = true,
            ["reverse direction"] = true,
            ["class resource reverse fill"] = true,
            ["class resources reverse fill"] = true,
            ["class power reverse fill"] = true,
            ["reverse class resource fill"] = true,
            ["reverse class resources fill"] = true,
            ["reverse class power fill"] = true,
            ["turn off class resource reverse fill"] = false,
            ["turn off class resources reverse fill"] = false,
            ["turn off class power reverse fill"] = false,
            ["disable class resource reverse fill"] = false,
            ["left to right"] = false,
            ["fill left to right"] = false,
            ["normal direction"] = false,
            ["normal fill"] = false,
            ["fill normal"] = false,
            ["class resource fill normal direction"] = false,
            ["class resources fill normal direction"] = false,
            ["class power fill normal direction"] = false,
            ["class resource fill left to right"] = false,
            ["class resources fill left to right"] = false,
            ["class power fill left to right"] = false,
        },
    })
    RegisterBarsBoolean("showEleMaelstrom", "elementalMaelstrom", "Elemental Maelstrom Bar", false, ClassPowerAliases("elemental maelstrom", "maelstrom bar", "ele maelstrom bar"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_ELE_MAELSTROM",
    })
    RegisterBarsBoolean("showEbonMight", "ebonMight", "Ebon Might Timer", true, ClassPowerAliases("ebon might", "ebon might timer", "augmentation ebon might"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_EBON_MIGHT",
    })
    RegisterBarsBoolean("showShadowMana", "shadowMana", "Shadow Insanity Bar", false, ClassPowerAliases("shadow insanity", "insanity bar", "shadow mana", "shadow resource bar"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_SHADOW_MANA",
    })
    RegisterBarsBoolean("showGuardianIronfur", "guardianIronfur", "Guardian Ironfur Tracker", false, ClassPowerAliases("ironfur", "ironfur tracker", "ironfur bar", "guardian ironfur"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_GUARDIAN_IRONFUR",
    })
    -- The markers only exist while the tracker itself is on, so the Assistant
    -- turns the tracker on with them instead of writing a dead setting.
    RegisterBarsBoolean("guardianIronfurShowHashLines", "ironfurMarkers", "Ironfur Cast Markers", true, ClassPowerAliases("ironfur markers", "ironfur cast markers", "ironfur hash lines"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_IRONFUR_MARKERS",
        companionChanges = {
            { key = "bars.showGuardianIronfur", value = true, whenValue = true,
              whenTextHas = { "show", "turn on", "enable" }, prepend = true },
        },
    })
    RegisterBarsBoolean("classPowerShowPrediction", "prediction", "Class Resource Prediction", true, ClassPowerAliases("prediction", "resource prediction", "incoming resource"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_PREDICTION",
        exactAliases = {
            "class resource prediction",
            "class resources prediction",
            "class power prediction",
            "resource prediction",
            "incoming resource",
            "show class resource prediction",
            "show class resources prediction",
            "turn on class resource prediction",
            "turn on class resources prediction",
            "enable class resource prediction",
            "enable class resources prediction",
            "hide class resource prediction",
            "hide class resources prediction",
            "turn off class resource prediction",
            "turn off class resources prediction",
            "disable class resource prediction",
            "disable class resources prediction",
        },
    })
    RegisterBarsBoolean("classPowerSmoothFill", "smoothFill", "Class Resource Smooth Fill", false, ClassPowerAliases(
        "smooth fill", "smooth resource fill", "smooth class resource", "smooth class power"
    ), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_SMOOTH_FILL",
        description = "Uses native StatusBar interpolation for value-driven Class Resource fills.",
    })

    RegisterBarsBoolean("classPowerColorByType", "colorByType", "Class Resource Color by Type", true, ClassPowerAliases("color by type", "resource type colors", "class resource class colors"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_COLOR_TYPE",
    })
    RegisterBarsEnum("classPowerComboPointColorMode", "comboPointColorMode", "Combo Point Color Mode", "default", {
        "default", "ramp", "custom",
    }, ClassPowerAliases("combo point color mode", "combo point slot mode", "combo slot mode", "combo point colors", "combo colors"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_COMBO_COLOR_MODE",
        valueAliases = COMBO_POINT_COLOR_MODE_ALIASES,
    })

    local RegisterDisplayNumberSettings = A.ClassPowerRegistry and A.ClassPowerRegistry.RegisterDisplayNumberSettings
    if type(RegisterDisplayNumberSettings) == "function" then
        RegisterDisplayNumberSettings({
            RegisterBarsNumber = RegisterBarsNumber,
            ClassPowerAliases = ClassPowerAliases,
        })
    end
end
