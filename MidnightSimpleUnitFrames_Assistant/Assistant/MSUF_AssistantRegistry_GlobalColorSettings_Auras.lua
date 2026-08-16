-- Assistant global aura and portrait color setting registry.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings.lua; the main domain passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

local PORTRAIT_COLOR_UNITS = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
local DISPEL_COLOR_ROWS = {
    { key = "Magic", label = "Magic Dispel Color", dr = 0.20, dg = 0.60, db = 1.00, aliases = { "magic dispel color", "magic debuff color", "magic aura color" } },
    { key = "Curse", label = "Curse Dispel Color", dr = 0.60, dg = 0.00, db = 1.00, aliases = { "curse dispel color", "curse debuff color", "curse aura color" } },
    { key = "Disease", label = "Disease Dispel Color", dr = 0.60, dg = 0.40, db = 0.00, aliases = { "disease dispel color", "disease debuff color", "disease aura color" } },
    { key = "Poison", label = "Poison Dispel Color", dr = 0.00, dg = 0.60, db = 0.00, aliases = { "poison dispel color", "poison debuff color", "poison aura color" } },
    { key = "Bleed", label = "Bleed Dispel Color", dr = 0.80, dg = 0.10, db = 0.10, aliases = { "bleed dispel color", "bleed debuff color", "bleed aura color" } },
}

function A.GlobalRegistry.CreateAuraAndPortraitColorSettings(ctx)
    if type(ctx) ~= "table" then return nil end

    local ColorSetting = ctx.ColorSetting
    local GeneralRGB = ctx.GeneralRGB
    local GeneralDB = ctx.GeneralDB
    local EnsureDB = ctx.EnsureDB
    local TableRGB = ctx.TableRGB
    local SetTableRGB = ctx.SetTableRGB
    local RegisterGeneralBoolean = ctx.RegisterGeneralBoolean
    local RegisterGeneralNumberSetting = ctx.RegisterGeneralNumberSetting
    local ApplyAuraColors = ctx.ApplyAuraColors
    local ApplyPortraitColors = ctx.ApplyPortraitColors
    local AURA_COOLDOWN_TEXT_COLOR_ROWS = ctx.AURA_COOLDOWN_TEXT_COLOR_ROWS or {}
    local AURA_COOLDOWN_TEXT_THRESHOLD_ROWS = ctx.AURA_COOLDOWN_TEXT_THRESHOLD_ROWS or {}

    if type(ColorSetting) ~= "function" or type(GeneralRGB) ~= "function" then return nil end
    if type(GeneralDB) ~= "function" or type(EnsureDB) ~= "function" then return nil end
    if type(TableRGB) ~= "function" or type(SetTableRGB) ~= "function" then return nil end
    if type(RegisterGeneralBoolean) ~= "function" then return nil end
    if type(RegisterGeneralNumberSetting) ~= "function" then return nil end

    local function SetAllPortraitRGB(prefix, r, gCol, b)
        local general = GeneralDB()
        general[prefix .. "R"], general[prefix .. "G"], general[prefix .. "B"] = r, gCol, b
        local db = EnsureDB()
        for i = 1, #PORTRAIT_COLOR_UNITS do
            local unit = PORTRAIT_COLOR_UNITS[i]
            db[unit] = type(db[unit]) == "table" and db[unit] or {}
            db[unit][prefix .. "R"], db[unit][prefix .. "G"], db[unit][prefix .. "B"] = r, gCol, b
        end
    end

    local function DispelDefaultRGB(row)
        local a3 = MSUF and MSUF.MSUF_Auras3
        if a3 and type(a3.GetDispelTypeColor) == "function" then
            return a3.GetDispelTypeColor(row.key, false)
        end
        return row.dr, row.dg, row.db
    end

    local function DispelRGB(row)
        local r, g, b = DispelDefaultRGB(row)
        return TableRGB(GeneralDB().dispelTypeColorOverrides, row.key, r, g, b)
    end

    local function SetDispelRGB(row, r, g, b)
        local general = GeneralDB()
        general.dispelTypeColorOverrides = type(general.dispelTypeColorOverrides) == "table"
            and general.dispelTypeColorOverrides or {}
        general.dispelTypeColorOverrides[row.key] = { r, g, b }
        local a3 = MSUF and MSUF.MSUF_Auras3
        if a3 and type(a3.SetDispelColorPreviewType) == "function" then
            a3.SetDispelColorPreviewType(row.key)
        end
    end

    local function RegisterSettings()
        ColorSetting("general.aurasOwnBuffHighlightColor", "Own Buff Highlight Color", {
            "own buff highlight color", "my buff highlight color", "aura own buff color", "own buff aura highlight color", "buff aura highlight color",
        }, function()
            return TableRGB(GeneralDB(), "aurasOwnBuffHighlightColor", 1, 0.85, 0.2)
        end, function(r, g, b)
            SetTableRGB(GeneralDB(), "aurasOwnBuffHighlightColor", r, g, b)
        end, { category = "Colors / Auras", attribute = "ownBuffHighlightColor", defaultR = 1, defaultG = 0.85, defaultB = 0.2, apply = ApplyAuraColors,
            menuControlDisposition = "standalone", menuControlDispositionReason = "This color is edited through contextual top-card color shortcuts rather than a dedicated scalar Colors-page row.",
            menuControlDispositionEvidence = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua:2173-2187",
            exactAliases = { "own buff highlight color", "my buff highlight color", "aura own buff color", "own buff aura highlight color", "buff aura highlight color" } })
        ColorSetting("general.aurasOwnDebuffHighlightColor", "Own Debuff Highlight Color", {
            "own debuff highlight color", "my debuff highlight color", "aura own debuff color", "own debuff aura highlight color", "debuff aura highlight color",
        }, function()
            return TableRGB(GeneralDB(), "aurasOwnDebuffHighlightColor", 1, 0.30, 0.30)
        end, function(r, g, b)
            SetTableRGB(GeneralDB(), "aurasOwnDebuffHighlightColor", r, g, b)
        end, { category = "Colors / Auras", attribute = "ownDebuffHighlightColor", defaultR = 1, defaultG = 0.30, defaultB = 0.30, apply = ApplyAuraColors,
            menuControlDisposition = "standalone", menuControlDispositionReason = "This color is edited through contextual top-card color shortcuts rather than a dedicated scalar Colors-page row.",
            menuControlDispositionEvidence = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua:2173-2187",
            exactAliases = { "own debuff highlight color", "my debuff highlight color", "aura own debuff color", "own debuff aura highlight color", "debuff aura highlight color" } })
        ColorSetting("general.aurasStackCountColor", "Aura Stack Count Text Color", {
            "stack count text color", "aura stack color", "aura stack count color", "aura stacks color", "aura stack text color", "aura count color",
        }, function()
            return TableRGB(GeneralDB(), "aurasStackCountColor", 1, 1, 1)
        end, function(r, g, b)
            SetTableRGB(GeneralDB(), "aurasStackCountColor", r, g, b)
        end, { category = "Colors / Auras", attribute = "auraStackColor", apply = ApplyAuraColors,
            menuControlDisposition = "standalone", menuControlDispositionReason = "This color is edited through contextual top-card color shortcuts rather than a dedicated scalar Colors-page row.",
            menuControlDispositionEvidence = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua:2173-2187",
            exactAliases = { "stack count text color", "aura stack color", "aura stack count color", "aura stacks color", "aura stack text color", "aura count color" } })
        RegisterGeneralBoolean("aurasCooldownTextUseBuckets", "auraCooldownBuckets", "Color Aura Timers By Remaining Time", false, {
            "color aura timers by remaining time", "aura timer bucket colors", "aura timer color buckets", "aura cooldown bucket colors", "aura cooldown color buckets", "aura cooldown buckets", "aura timer buckets",
        }, { category = "Colors / Auras", frameType = "colors", apply = ApplyAuraColors, reason = "MSUF_ASSISTANT_AURA_TIMER_BUCKETS",
            exactAliases = { "color aura timers by remaining time", "aura timer bucket colors", "aura timer color buckets", "aura cooldown bucket colors", "aura cooldown color buckets", "aura cooldown buckets", "aura timer buckets" } })
        for i = 1, #AURA_COOLDOWN_TEXT_COLOR_ROWS do
            local row = AURA_COOLDOWN_TEXT_COLOR_ROWS[i]
            ColorSetting("general." .. row.key, row.label, row.aliases, function()
                return TableRGB(GeneralDB(), row.key, row.dr, row.dg, row.db)
            end, function(r, g, b)
                SetTableRGB(GeneralDB(), row.key, r, g, b)
            end, { category = "Colors / Auras", attribute = row.key, defaultR = row.dr, defaultG = row.dg, defaultB = row.db, apply = ApplyAuraColors, exactAliases = row.aliases })
        end
        for i = 1, #AURA_COOLDOWN_TEXT_THRESHOLD_ROWS do
            local row = AURA_COOLDOWN_TEXT_THRESHOLD_ROWS[i]
            RegisterGeneralNumberSetting(row.key, row.attr, row.label, row.defaultValue, row.minValue, row.maxValue, row.aliases, {
                category = "Colors / Auras",
                frameType = "colors",
                apply = ApplyAuraColors,
                reason = "MSUF_ASSISTANT_AURA_TIMER_THRESHOLDS",
                description = "Aura cooldown text bucket threshold.",
                exactAliases = row.aliases,
            })
        end
        for i = 1, #DISPEL_COLOR_ROWS do
            local row = DISPEL_COLOR_ROWS[i]
            ColorSetting("general.dispelTypeColorOverrides." .. row.key, row.label, row.aliases, function()
                return DispelRGB(row)
            end, function(r, g, b)
                SetDispelRGB(row, r, g, b)
            end, { category = "Colors / Auras", attribute = "dispel" .. row.key .. "Color",
                defaultR = row.dr, defaultG = row.dg, defaultB = row.db,
                apply = ApplyAuraColors, exactAliases = row.aliases })
        end

        ColorSetting("general.portraitBorderColor", "Portrait Border Color", {
            "portrait border color", "portrait custom border color",
        }, function()
            return GeneralRGB("portraitBorderColor", 1, 1, 1)
        end, function(r, g, b)
            SetAllPortraitRGB("portraitBorderColor", r, g, b)
        end, { category = "Colors / Portrait", attribute = "portraitBorderColor", apply = ApplyPortraitColors })
        ColorSetting("general.portraitBgColor", "Portrait Background Color", {
            "portrait background color", "portrait bg color",
        }, function()
            return GeneralRGB("portraitBgColor", 0.05, 0.05, 0.05)
        end, function(r, g, b)
            SetAllPortraitRGB("portraitBgColor", r, g, b)
        end, { category = "Colors / Portrait", attribute = "portraitBackgroundColor", defaultR = 0.05, defaultG = 0.05, defaultB = 0.05, apply = ApplyPortraitColors })
    end

    return {
        RegisterSettings = RegisterSettings,
        SetAllPortraitRGB = SetAllPortraitRGB,
    }
end
