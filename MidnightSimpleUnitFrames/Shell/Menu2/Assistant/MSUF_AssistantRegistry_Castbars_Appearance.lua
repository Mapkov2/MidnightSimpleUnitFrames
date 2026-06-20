-- Assistant Castbars appearance/interrupt setting registry.
-- Loaded before MSUF_AssistantRegistry_Castbars.lua; the main castbar registry passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.CastbarsRegistry = A.CastbarsRegistry or {}

function A.CastbarsRegistry.RegisterAppearanceSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local CastbarAliases = ctx.CastbarAliases
    local RegisterCastbarBoolean = ctx.RegisterCastbarBoolean
    local RegisterCastbarNumber = ctx.RegisterCastbarNumber
    local RegisterCastbarEnum = ctx.RegisterCastbarEnum
    local RegisterCastbarString = ctx.RegisterCastbarString
    local RegisterCastbarNumericBoolean = ctx.RegisterCastbarNumericBoolean
    local ApplyCastbarTextures = ctx.ApplyCastbarTextures
    local ApplyCastbarOutline = ctx.ApplyCastbarOutline

    if type(Registry) ~= "table" or type(Registry.RegisterSetting) ~= "function" then return end
    if type(CastbarAliases) ~= "function" then return end
    if type(RegisterCastbarBoolean) ~= "function" or type(RegisterCastbarNumber) ~= "function" then return end
    if type(RegisterCastbarEnum) ~= "function" or type(RegisterCastbarString) ~= "function" then return end
    if type(RegisterCastbarNumericBoolean) ~= "function" then return end

    RegisterCastbarBoolean("castbarInterruptShake", "interruptShake", "Shake on Interrupt", false, CastbarAliases("interrupt shake", "shake on interrupt", "unterbrechen schuetteln", "unterbrechung schuetteln"), {
        reason = "MSUF2_CASTBAR_SHAKE",
    })
    RegisterCastbarNumber("castbarShakeStrength", "shakeStrength", "Shake Strength", 8, 0, 30, CastbarAliases("shake strength", "interrupt shake strength"), {
        reason = "MSUF2_CASTBAR_SHAKE_STRENGTH",
    })
    RegisterCastbarBoolean("castbarUnifiedDirection", "unifiedDirection", "Always Use Fill Direction for All Casts", false, CastbarAliases("unified fill direction", "same fill direction for channels"), {
        reason = "MSUF2_CASTBAR_UNIFIED_DIRECTION",
    })
    RegisterCastbarEnum("castbarFillDirection", "fillDirection", "Castbar Fill Direction", "RTL", { "RTL", "LTR" }, CastbarAliases("fill direction", "direction"), {
        reason = "MSUF2_CASTBAR_FILL_DIRECTION",
        valueAliases = {
            left = "RTL",
            ["right to left"] = "RTL",
            rtl = "RTL",
            default = "RTL",
            right = "LTR",
            ["left to right"] = "LTR",
            ltr = "LTR",
        },
    })
    RegisterCastbarBoolean("castbarOpositeDirectionTarget", "targetOppositeDirection", "Use Opposite Fill Direction for Target", false, CastbarAliases("target opposite fill direction", "opposite target direction"), {
        reason = "MSUF2_CASTBAR_TARGET_DIRECTION",
    })
    RegisterCastbarBoolean("castbarShowChannelTicks", "channelTicks", "Show Channel Tick Lines", false, CastbarAliases("channel ticks", "channel tick lines", "kanal ticks", "kanal tick linien"), {
        reason = "MSUF2_CASTBAR_TICKS",
    })

    RegisterCastbarString("castbarTexture", "texture", "Castbar Texture", "Blizzard", CastbarAliases("texture", "foreground texture", "sharedmedia texture"), {
        reason = "MSUF2_CASTBAR_TEXTURE",
        apply = ApplyCastbarTextures,
        description = "SharedMedia texture name; values are provided dynamically by the UI.",
    })
    RegisterCastbarString("castbarBackgroundTexture", "backgroundTexture", "Castbar Background Texture", "Blizzard", CastbarAliases("background texture", "background texture", "bg texture"), {
        reason = "MSUF2_CASTBAR_BG_TEXTURE",
        apply = ApplyCastbarTextures,
        description = "SharedMedia texture name; values are provided dynamically by the UI.",
    })
    RegisterCastbarNumber("castbarOutlineThickness", "outline", "Castbar Outline Thickness", 1, 0, 6, CastbarAliases("outline thickness", "border thickness"), {
        reason = "MSUF2_CASTBAR_OUTLINE",
        apply = ApplyCastbarOutline,
    })
    RegisterCastbarBoolean("castbarShowGlow", "glow", "Show Castbar Glow Effect", false, CastbarAliases("glow", "glow effect", "gluehen", "glow effekt"), {
        reason = "MSUF2_CASTBAR_GLOW",
        apply = ApplyCastbarTextures,
    })
    RegisterCastbarBoolean("castbarShowLatency", "latency", "Show Latency Indicator", true, CastbarAliases("latency", "latency indicator", "latenz", "latenzanzeige", "latenz anzeige"), {
        reason = "MSUF2_CASTBAR_LATENCY",
        apply = ApplyCastbarTextures,
    })
    RegisterCastbarBoolean("castbarShowSpark", "spark", "Show Spark", false, CastbarAliases("spark", "leading edge highlight", "funke", "zauberleisten funke"), {
        reason = "MSUF2_CASTBAR_SPARK",
        apply = ApplyCastbarTextures,
    })
    RegisterCastbarBoolean("castbarSparkOverflow", "sparkOverflow", "Spark Extends Beyond Bar", true, CastbarAliases("spark overflow", "spark beyond bar", "funke ausserhalb", "spark ausserhalb"), {
        reason = "MSUF2_CASTBAR_SPARK_OVERFLOW",
        apply = ApplyCastbarTextures,
    })

    RegisterCastbarBoolean("empowerColorStages", "empoweredStageColor", "Add Color to Empowered Stages", true, CastbarAliases("empowered stage colors", "empower color stages", "empower stufen farben", "ermaechtigen stufen farben"), {
        reason = "MSUF2_CASTBAR_EMPOWER_COLOR",
    })
    RegisterCastbarBoolean("empowerStageBlink", "empoweredStageBlink", "Add Stage Blink for Empowered Casts", true, CastbarAliases("empowered stage blink", "empower stage blink", "empower stufen blinken", "ermaechtigen stufen blinken"), {
        reason = "MSUF2_CASTBAR_EMPOWER_BLINK",
    })
    RegisterCastbarNumber("empowerStageBlinkTime", "empoweredStageBlinkTime", "Stage Blink Time", 0.25, 0.05, 1.00, CastbarAliases("stage blink time", "empowered blink time"), {
        step = 0.01,
        reason = "MSUF2_CASTBAR_EMPOWER_TIME",
    })

    RegisterCastbarNumericBoolean("castbarSpellNameShortening", "spellNameShortening", "Spell Name Shortening", false, CastbarAliases("spell name shortening", "shorten spell names", "zaubernamen kuerzen", "spell namen kuerzen"), {
        reason = "MSUF2_CASTBAR_NAME_SHORTEN",
    })
    RegisterCastbarNumber("castbarSpellNameMaxLen", "spellNameMaxLength", "Max Spell Name Length", 30, 6, 30, CastbarAliases("max spell name length", "spell name max length"), {
        reason = "MSUF2_CASTBAR_NAME_MAX",
    })
    RegisterCastbarNumber("castbarSpellNameReservedSpace", "spellNameReservedSpace", "Reserved Spell Name Space", 8, 0, 30, CastbarAliases("reserved spell name space", "spell name reserved space"), {
        reason = "MSUF2_CASTBAR_NAME_RESERVED",
    })

    local RegisterInterruptAppearanceSettings = A.CastbarsRegistry and A.CastbarsRegistry.RegisterInterruptAppearanceSettings
    if type(RegisterInterruptAppearanceSettings) == "function" then
        RegisterInterruptAppearanceSettings(ctx)
    end
end
