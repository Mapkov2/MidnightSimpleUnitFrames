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

function A.GlobalRegistry.CreateAuraAndPortraitColorSettings(ctx)
    if type(ctx) ~= "table" then return nil end

    local ColorSetting = ctx.ColorSetting
    local GeneralRGB = ctx.GeneralRGB
    local GeneralDB = ctx.GeneralDB
    local EnsureDB = ctx.EnsureDB
    local TableRGB = ctx.TableRGB
    local SetTableRGB = ctx.SetTableRGB
    local AuraSharedDB = ctx.AuraSharedDB
    local RegisterGeneralBoolean = ctx.RegisterGeneralBoolean
    local RegisterGeneralNumberSetting = ctx.RegisterGeneralNumberSetting
    local ApplyAuraColors = ctx.ApplyAuraColors
    local ApplyPortraitColors = ctx.ApplyPortraitColors
    local AURA_COOLDOWN_TEXT_COLOR_ROWS = ctx.AURA_COOLDOWN_TEXT_COLOR_ROWS or {}
    local AURA_COOLDOWN_TEXT_THRESHOLD_ROWS = ctx.AURA_COOLDOWN_TEXT_THRESHOLD_ROWS or {}

    if type(ColorSetting) ~= "function" or type(GeneralRGB) ~= "function" then return nil end
    if type(GeneralDB) ~= "function" or type(EnsureDB) ~= "function" then return nil end
    if type(TableRGB) ~= "function" or type(SetTableRGB) ~= "function" then return nil end
    if type(AuraSharedDB) ~= "function" or type(RegisterGeneralBoolean) ~= "function" then return nil end
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

    -- Shared Auras3 icon style colors. These match the Colors page defaults in
    -- MSUF_Menu2_AdvancedColors.lua; the fourth component is the alpha the Auras
    -- page sliders own.
    local ICON_STYLE_BORDER_DEFAULT = { 0, 0, 0, 1 }
    local ICON_STYLE_SHADOW_DEFAULT = { 0, 0, 0, 0.8 }
    local function IconStyleRGB(key, default)
        local stored = AuraSharedDB()[key]
        if type(stored) ~= "table" then stored = default end
        return tonumber(stored[1]) or default[1],
            tonumber(stored[2]) or default[2],
            tonumber(stored[3]) or default[3]
    end
    local function SetIconStyleRGB(key, default, r, g, b)
        local shared = AuraSharedDB()
        local stored = shared[key]
        local alpha = (type(stored) == "table" and tonumber(stored[4])) or default[4]
        shared[key] = { r, g, b, alpha }
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
        ColorSetting("auras3.shared.pandemicColor", "Pandemic Window Color", {
            "pandemic window color", "pandemic color", "aura pandemic color",
        }, function()
            local sh = AuraSharedDB()
            return tonumber(sh.pandemicR) or 0, tonumber(sh.pandemicG) or 0.4, tonumber(sh.pandemicB) or 1
        end, function(r, g, b)
            local sh = AuraSharedDB()
            sh.pandemicR, sh.pandemicG, sh.pandemicB = r, g, b
        end, { category = "Colors / Auras", attribute = "pandemicColor", defaultR = 0, defaultG = 0.4, defaultB = 1, apply = ApplyAuraColors,
            menuControlDisposition = "standalone", menuControlDispositionReason = "This color is edited through contextual top-card color shortcuts rather than a dedicated scalar Colors-page row.",
            menuControlDispositionEvidence = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua:2173-2187" })
        -- The icon border and shadow colors are the only shared aura colors
        -- stored as a single {r,g,b,a} table instead of the R/G/B scalar triple
        -- the rest of this domain uses. Alpha belongs to the Auras page sliders,
        -- so a color change must carry the stored alpha through untouched --
        -- writing a bare triple here would silently reset the icon to opaque.
        ColorSetting("auras3.shared.styleBorderColor", "Aura Icon Border Color", {
            "aura icon border color", "aura border color", "icon border color",
            "buff border color", "debuff border color", "aura icon border colour",
        }, function()
            return IconStyleRGB("styleBorderColor", ICON_STYLE_BORDER_DEFAULT)
        end, function(r, g, b)
            SetIconStyleRGB("styleBorderColor", ICON_STYLE_BORDER_DEFAULT, r, g, b)
        end, { category = "Colors / Auras", attribute = "auraIconBorderColor",
            defaultR = ICON_STYLE_BORDER_DEFAULT[1], defaultG = ICON_STYLE_BORDER_DEFAULT[2], defaultB = ICON_STYLE_BORDER_DEFAULT[3],
            apply = ApplyAuraColors,
            exactAliases = { "aura icon border color", "aura border color", "icon border color" } })
        ColorSetting("auras3.shared.styleShadowColor", "Aura Icon Shadow Color", {
            "aura icon shadow color", "aura shadow color", "icon shadow color",
            "aura icon drop shadow color", "buff shadow color", "debuff shadow color",
        }, function()
            return IconStyleRGB("styleShadowColor", ICON_STYLE_SHADOW_DEFAULT)
        end, function(r, g, b)
            SetIconStyleRGB("styleShadowColor", ICON_STYLE_SHADOW_DEFAULT, r, g, b)
        end, { category = "Colors / Auras", attribute = "auraIconShadowColor",
            defaultR = ICON_STYLE_SHADOW_DEFAULT[1], defaultG = ICON_STYLE_SHADOW_DEFAULT[2], defaultB = ICON_STYLE_SHADOW_DEFAULT[3],
            apply = ApplyAuraColors,
            exactAliases = { "aura icon shadow color", "aura shadow color", "icon shadow color" } })
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
