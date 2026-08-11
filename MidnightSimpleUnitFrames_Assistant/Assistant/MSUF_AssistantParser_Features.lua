--- Shell/Menu2/Assistant/MSUF_AssistantParser_Features.lua
--- Feature shortcut parser for Assistant workflows.
---
--- Narrows broad class-power/gameplay/global-bars phrasing into registry plans
--- without bypassing confirmation, undo, or combat handling.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
local P = A.Parser or {}
A.Parser = P
local Data = A.ParserData or {}
A.ParserData = Data
local FeaturesData = Data.FEATURES_PARSER or {}
local FeaturesPhrases = FeaturesData.PHRASES or {}
local Normalize = P.Normalize
local HasPhrase = P.HasPhrase
local ContainsAny = P.ContainsAny
local CLASS_POWER_TERMS = P.CLASS_POWER_TERMS
local DetectUnits = P.DetectUnits
local DetectGroups = P.DetectGroups
local DetectGlobalScope = P.DetectGlobalScope
local DetectBoolean = P.DetectBoolean
local FirstNumber = P.FirstNumber
local Compact = P.Compact
local ExtractColor = P.ExtractColor
local DetectFrameType = P.DetectFrameType
local DetectDirection = P.DetectDirection
local PageForText = P.PageForText
local FrameTypeForPage = P.FrameTypeForPage
local CleanProfileName = P.CleanProfileName
local ParseOpen = P.ParseOpen
local ParseDashboardPanelAction = P.ParseDashboardPanelAction
local ParseMenuWindowAction = P.ParseMenuWindowAction
local EnumValueForText = P.EnumValueForText
local RelativeNumberDeltaForText = P.RelativeNumberDeltaForText
local ValueForRegistrySetting = P.ValueForRegistrySetting
local ClassPowerSlotResourceForText
local ClassPowerSlotIndexForText

local CLASS_POWER_SLOT_MODE_TERMS = {
    "slot mode", "slot color mode", "slot colour mode", "slot colors", "slot colours",
    "individual colors", "individual colours", "individual slots", "per slot",
    "custom slots", "color ramp", "colour ramp", "gradient", "farbverlauf",
    "einzelne farben", "individual", "custom", "ramp", "einzeln", "individuell",
    "gleiche farbe", "same color", "resource color",
}
local CLASS_POWER_SLOT_THRESHOLD_TERMS = { "above 5", "over 5", "5+", "five plus", "über 5", "ueber 5" }
local CLASS_POWER_FULL_COLOR_TERMS = {
    "full", "max", "at max", "maximum", "max resource", "capped", "when full",
    "voll", "volle", "voller", "volles", "bei maximum", "maximal", "maximale", "maximaler",
    "maximale ressourcen", "wenn voll",
}
local CLASS_POWER_SLOT_RESET_TERMS = {
    "slot", "slots", "individual", "per slot", "custom slots",
    "einzeln", "einzelne", "individuell", "plätze", "plaetze",
}

local function UnitDisplayLabel(unit)
    if A and type(A.DisplayUnitLabel) == "function" then return A.DisplayUnitLabel(unit) end
    local label = (A.UnitLabels or {})[unit]
    if label ~= nil and tostring(label) ~= "" then return tostring(label) end
    if unit == "targettarget" then return "Target of Target" end
    if unit == "focustarget" then return "Focus Target" end
    return tostring(unit or "Unit Frame")
end

local function GroupDisplayLabel(scope)
    if A and type(A.DisplayGroupLabel) == "function" then return A.DisplayGroupLabel(scope) end
    if scope == "mythicraid" then return "Mythic Raid" end
    if scope == "raid" then return "Raid" end
    if scope == "party" then return "Party" end
    return UnitDisplayLabel(scope)
end

local function UnitForPage(page)
    if page == "uf_player" then return "player" end
    if page == "uf_target" then return "target" end
    if page == "uf_focus" then return "focus" end
    if page == "uf_pet" then return "pet" end
    if page == "uf_targettarget" then return "targettarget" end
    if page == "uf_focustarget" then return "focustarget" end
    if page == "uf_boss" then return "boss" end
    return nil
end

local function DisplayValueLabel(setting, value)
    if P and type(P.ValueDisplay) == "function" then
        local label = P.ValueDisplay(setting, value)
        if label ~= nil then return tostring(label) end
    end
    if setting and (setting.type == "enum" or type(setting.values) == "table") and type(A.HumanizeDisplayKey) == "function" then
        return A.HumanizeDisplayKey(value)
    end
    return tostring(value)
end

local CLASS_POWER_DETAIL_TERMS = {
    "height", "width", "mode", "x", "y", "offset", "frame level",
    "anchor", "cooldown", "combo", "text", "rune", "reverse", "fill",
    "maelstrom", "ebon", "insanity", "shadow", "prediction", "color",
    "font", "opacity", "alpha", "background", "foreground", "texture", "separator", "tick",
    "outline", "border", "gap", "hide out of combat", "hide when full",
    "hide when empty", "out of combat", "full", "empty", "alt mana",
    "alternative mana", "detached power", "hp", "health", "hp bar", "health bar",
    "player hp", "player health", "second hp", "duplicate hp",
}

local function ClassPowerMentionIsNegated(text)
    return ContainsAny(text, FeaturesPhrases[1])
end

local function HasClassPowerIntent(text)
    if ClassPowerMentionIsNegated(text) then return false end
    return ContainsAny(text, CLASS_POWER_TERMS)
        or ContainsAny(text, FeaturesPhrases[2])
end

local function ParseClassPowerRootToggle(text)
    if ContainsAny(text, FeaturesPhrases[3])
        and ContainsAny(text, FeaturesPhrases[4]) then
        return nil
    end
    local value = DetectBoolean(text)
    if value == nil then return nil end
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, CLASS_POWER_DETAIL_TERMS) then return nil end
    local setting = Registry and Registry:GetSetting("bars.showClassPower")
    return setting and {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = "Class Resource",
        summary = "Toggles MSUF Class Resources.",
    } or nil
end

local CLASS_POWER_COOLDOWN_TARGET_TERMS = {
    "essential cooldown", "essential cooldowns", "essential cooldown manager", "essential cooldownmanager",
    "cooldown manager", "cooldownmanager", "cooldowns manager", "cdm", "cooldowns",
}

local CLASS_POWER_PLAYER_TARGET_TERMS = {
    "player frame", "player unitframe", "player unit frame", "player width", "player frame width",
    "same width as player", "match player", "match player frame", "to player",
}

local function ClassPowerSetting(key)
    return Registry and Registry:GetSetting(key)
end

local function ClassPowerWidthModeForText(text)
    if ContainsAny(text, FeaturesPhrases[5]) then return "auto_pips" end
    if ContainsAny(text, CLASS_POWER_COOLDOWN_TARGET_TERMS) then return "cooldown" end
    if ContainsAny(text, FeaturesPhrases[6]) then return "utility" end
    if ContainsAny(text, FeaturesPhrases[7]) then return "tracked_buffs" end
    if ContainsAny(text, FeaturesPhrases[8]) then return "custom" end
    if ContainsAny(text, CLASS_POWER_PLAYER_TARGET_TERMS) then return "player" end
    return nil
end

function A._ParseClassPowerWidthModeShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, FeaturesPhrases[9]) then return nil end
    local mode = ClassPowerWidthModeForText(text)
    if not mode then return nil end
    local widthIntent = ContainsAny(text, FeaturesPhrases[10])
    if not widthIntent then return nil end
    if FirstNumber(text) and not ContainsAny(text, FeaturesPhrases[11]) then
        return nil
    end
    local setting = ClassPowerSetting("bars.classPowerWidthMode")
    return setting and {
        kind = "changes",
        changes = { { setting = setting, value = mode } },
        label = "Class Resource Width Mode",
        summary = "Sets the Class Resources width source.",
    } or nil
end

local function ClassPowerHideRuleValue(text)
    local explicitHideIntent = ContainsAny(text, FeaturesPhrases[12])
    if (ContainsAny(text, FeaturesPhrases[13]) or (ContainsAny(text, FeaturesPhrases[14]) and not explicitHideIntent)) and ContainsAny(text, FeaturesPhrases[15]) then
        return false
    end
    if ContainsAny(text, FeaturesPhrases[16]) then
        return false
    end
    if ContainsAny(text, FeaturesPhrases[17]) then
        return true
    end
    if ContainsAny(text, FeaturesPhrases[18]) then
        return true
    end
    local value = DetectBoolean(text)
    if value == false then return false end
    if value == true then return true end
    return nil
end

function A._ParseClassPowerVisibilityShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    -- "turn on <resource> full color" addresses the per-resource full-color
    -- setting. Do not let the broad word "full" reinterpret it as the global
    -- Hide Class Resource When Full toggle; the exact registry alias pass owns
    -- the explicit resource setting immediately after this shortcut.
    if ClassPowerSlotResourceForText
        and ClassPowerSlotResourceForText(text)
        and ContainsAny(text, CLASS_POWER_FULL_COLOR_TERMS)
        and ContainsAny(text, FeaturesPhrases[198])
    then
        return nil
    end
    local rule
    if ContainsAny(text, FeaturesPhrases[19]) then
        rule = { key = "bars.classPowerHideOOC", label = "Class Resource Hide Out of Combat" }
    elseif ContainsAny(text, FeaturesPhrases[20]) then
        rule = { key = "bars.classPowerHideWhenFull", label = "Hide Class Resource When Full" }
    elseif ContainsAny(text, FeaturesPhrases[21]) then
        rule = { key = "bars.classPowerHideWhenEmpty", label = "Hide Class Resource When Empty" }
    end
    if not rule then return nil end
    local value = ClassPowerHideRuleValue(text)
    if value == nil then return nil end
    local setting = ClassPowerSetting(rule.key)
    return setting and {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = rule.label,
        summary = "Changes the Class Resources auto-hide toggle using show/hide wording.",
    } or nil
end

function A._ParseClassPowerAnchorShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, FeaturesPhrases[22]) then return nil end
    local hasAnchorIntent = ContainsAny(text, FeaturesPhrases[23])
    if not hasAnchorIntent then return nil end
    local targetCooldown = ContainsAny(text, CLASS_POWER_COOLDOWN_TARGET_TERMS)
    local targetPlayer = ContainsAny(text, CLASS_POWER_PLAYER_TARGET_TERMS)
    local value = DetectBoolean(text)
    if targetCooldown and ContainsAny(text, FeaturesPhrases[24]) then
        value = false
    elseif targetCooldown then
        value = value ~= false
    elseif targetPlayer then
        value = false
    elseif value == nil and ContainsAny(text, FeaturesPhrases[25]) then
        value = true
    end
    if value == nil then return nil end
    local anchor = ClassPowerSetting("bars.classPowerAnchorToCooldown")
    if not anchor then return nil end
    local changes = { { setting = anchor, value = value } }
    if targetPlayer then
        local widthMode = ClassPowerSetting("bars.classPowerWidthMode")
        if widthMode then changes[#changes + 1] = { setting = widthMode, value = "player" } end
    elseif value == true and ContainsAny(text, FeaturesPhrases[26]) then
        local widthMode = ClassPowerSetting("bars.classPowerWidthMode")
        if widthMode then changes[#changes + 1] = { setting = widthMode, value = "cooldown" } end
    end
    return {
        kind = "changes",
        changes = changes,
        label = value and "Anchor Class Resource to Essential Cooldowns" or "Anchor Class Resource to Player Frame",
        summary = "Changes the Class Resources cooldown-anchor toggle.",
    }
end

local function ClassPowerPlacement(text)
    if ContainsAny(text, FeaturesPhrases[27]) then return "below" end
    if ContainsAny(text, FeaturesPhrases[28]) then return "above" end
    if ContainsAny(text, FeaturesPhrases[29]) then return "top" end
    return nil
end

local function ClassPowerPlacementOffsets(placement)
    local db = _G.MSUF_DB or {}
    local player = type(db.player) == "table" and db.player or {}
    local bars = type(db.bars) == "table" and db.bars or {}
    local playerH = tonumber(player.height) or 40
    local cpH = tonumber(bars.classPowerHeight) or 4
    if placement == "below" then return 0, -math.floor(playerH + cpH + 6 + 0.5) end
    if placement == "above" then return 0, math.floor(cpH + 6 + 0.5) end
    return 0, 0
end

function A._ParseClassPowerPlacementShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, FeaturesPhrases[30]) then return nil end
    local placement = ClassPowerPlacement(text)
    if not placement then return nil end
    local units = DetectUnits(text)
    if units[1] and units[1] ~= "player" then
        return {
            kind = "unknown",
            text = "Class Resources are attached to the Player frame in MSUF. I can place them above or below the Player frame, or anchor them to Essential Cooldowns.",
            status = "failed",
        }
    end
    local anchor = ClassPowerSetting("bars.classPowerAnchorToCooldown")
    local widthMode = ClassPowerSetting("bars.classPowerWidthMode")
    local xSetting = ClassPowerSetting("bars.classPowerOffsetX")
    local ySetting = ClassPowerSetting("bars.classPowerOffsetY")
    if not xSetting or not ySetting then return nil end
    local x, y = ClassPowerPlacementOffsets(placement)
    local changes = {}
    if anchor then changes[#changes + 1] = { setting = anchor, value = false } end
    if widthMode then changes[#changes + 1] = { setting = widthMode, value = "player" } end
    changes[#changes + 1] = { setting = xSetting, value = x }
    changes[#changes + 1] = { setting = ySetting, value = y }
    return {
        kind = "changes",
        changes = changes,
        label = placement == "below" and "Place Class Resource Below Player" or "Place Class Resource Near Player",
        summary = "Positions Class Resources relative to the Player frame with Class Resource offsets.",
    }
end

function A._ParseClassPowerDisplayStyleShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, FeaturesPhrases[31]) then return nil end
    if ContainsAny(text, FeaturesPhrases[32]) then return nil end
    local value
    if ContainsAny(text, FeaturesPhrases[33])
        or (ContainsAny(text, FeaturesPhrases[34]) and ContainsAny(text, FeaturesPhrases[35])) then
        value = true
    elseif ContainsAny(text, FeaturesPhrases[36]) or (ContainsAny(text, FeaturesPhrases[37]) and ContainsAny(text, FeaturesPhrases[38])) then
        value = false
    else
        return nil
    end
    local textSetting = ClassPowerSetting("bars.classPowerShowText")
    if not textSetting then return nil end
    local changes = {}
    if value == true or ContainsAny(text, FeaturesPhrases[39]) then
        local root = ClassPowerSetting("bars.showClassPower")
        if root then changes[#changes + 1] = { setting = root, value = true } end
    end
    changes[#changes + 1] = { setting = textSetting, value = value }
    return {
        kind = "changes",
        changes = changes,
        label = value and "Show Class Resource Text" or "Show Class Resource Pips",
        bulkSafe = #changes > 1,
        summary = "Switches Class Resources between text and pips.",
    }
end

function A._ParseClassPowerShapeShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, FeaturesPhrases[40]) then return nil end
    if ContainsAny(text, FeaturesPhrases[41]) then return nil end
    if not ContainsAny(text, FeaturesPhrases[42]) then return nil end

    local key
    local label
    if ContainsAny(text, FeaturesPhrases[43])
        and ContainsAny(text, FeaturesPhrases[44])
        and not ContainsAny(text, FeaturesPhrases[45])
    then
        key = "bars.classPowerShapeAlign"
        label = "Class Resource Shape Alignment"
    elseif ContainsAny(text, FeaturesPhrases[46]) then
        key = "bars.classPowerShape"
        label = "Class Resource Shape"
    end
    if not key then return nil end

    local setting = ClassPowerSetting(key)
    local value = setting and EnumValueForText and EnumValueForText(setting, text) or nil
    if value == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or label,
        summary = "Changes the Class Resource shape option.",
    }
end

function A._ParseClassPowerFillDirectionShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, FeaturesPhrases[47]) then return nil end
    if not ContainsAny(text, FeaturesPhrases[48]) then return nil end

    local value
    local boolValue = DetectBoolean(text)
    if boolValue == false and ContainsAny(text, FeaturesPhrases[49]) then
        value = false
    elseif ContainsAny(text, FeaturesPhrases[50]) then
        value = true
    elseif ContainsAny(text, FeaturesPhrases[51]) then
        value = false
    elseif ContainsAny(text, FeaturesPhrases[52]) then
        value = boolValue
        if value == nil then value = true end
    end
    if value == nil then return nil end

    local setting = ClassPowerSetting("bars.classPowerFillReverse")
    return setting and {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Class Resource Reverse Fill",
        summary = "Changes the Class Resource fill direction.",
    } or nil
end

P.ParseGroupFrameFillDirectionShortcut = function(text)
    local scopes = DetectGroups(text)
    if #scopes == 0 then return nil end
    if not ContainsAny(text, FeaturesPhrases[53]) then return nil end

    local value
    local boolValue = DetectBoolean(text)
    if boolValue == false and ContainsAny(text, FeaturesPhrases[54]) then
        value = false
    elseif ContainsAny(text, FeaturesPhrases[55]) then
        value = true
    elseif ContainsAny(text, FeaturesPhrases[56]) then
        value = false
    elseif ContainsAny(text, FeaturesPhrases[57]) then
        value = boolValue
        if value == nil then value = true end
    end
    if value == nil then return nil end

    local changes = {}
    for i = 1, #scopes do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scopes[i]) .. ".reverseFill")
        if setting then changes[#changes + 1] = { setting = setting, value = value } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Group Frame Reverse Fill",
        bulkSafe = #changes > 1,
        summary = "Changes the Group Frame health fill direction.",
    }
end

function A._ParseClassPowerTextSizeShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, FeaturesPhrases[58]) then return nil end
    if ContainsAny(text, FeaturesPhrases[59]) then return nil end
    if not ContainsAny(text, FeaturesPhrases[60]) then return nil end
    if not ContainsAny(text, FeaturesPhrases[61]) then return nil end
    local setting = ClassPowerSetting("bars.classPowerFontSize")
    if not setting then return nil end
    local relativeDelta = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text, 1)
    local value
    if relativeDelta == nil then
        value = FirstNumber(text)
        if value == nil then return nil end
    end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = "Class Resource Font Size",
        summary = "Adjusts Class Resource text size.",
    }
end

function A._ParseClassPowerSizeShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, FeaturesPhrases[62]) then return nil end
    if ContainsAny(text, FeaturesPhrases[63]) then return nil end
    if not ContainsAny(text, FeaturesPhrases[64]) then return nil end
    local key
    local fallback
    if ContainsAny(text, FeaturesPhrases[65]) then
        key = "bars.classPowerWidth"
        fallback = 10
    else
        key = "bars.classPowerHeight"
        fallback = 1
    end
    local setting = ClassPowerSetting(key)
    if not setting then return nil end
    local relativeDelta = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text, fallback)
    local value
    if relativeDelta == nil then
        value = FirstNumber(text)
        if value == nil then return nil end
    end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = key == "bars.classPowerWidth" and "Class Resource Width" or "Class Resource Height",
        summary = "Adjusts Class Resource width or height.",
    }
end

function A._ParseClassPowerFrameLevelShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, FeaturesPhrases[66]) then return nil end
    if not ContainsAny(text, FeaturesPhrases[67]) then return nil end
    if ContainsAny(text, FeaturesPhrases[68]) then return nil end
    local setting = ClassPowerSetting("bars.classPowerFrameLevelOffset")
    if not setting then return nil end
    local relativeDelta = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text, 1)
    local value
    if relativeDelta == nil then
        value = FirstNumber(text)
        if value == nil then return nil end
    end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = "Class Resource Frame Level",
        summary = "Adjusts the Class Resource frame level offset.",
    }
end

function A._ParseClassPowerPlayerHPDetailShortcut(text, raw)
    if not ContainsAny(text, FeaturesPhrases[69]) then return nil end
    if ContainsAny(text, FeaturesPhrases[70])
        and not ContainsAny(text, FeaturesPhrases[71]) then
        return nil
    end

    local key
    local label
    local summary
    local fallback = 1

    if ContainsAny(text, FeaturesPhrases[72]) then
        key = "bars.playerHPBarUsePlayerText"
        label = "Class Resources Player HP Use Player Text"
    elseif ContainsAny(text, FeaturesPhrases[73]) then
        key = "bars.playerHPBarTextReverse"
        label = "Class Resources Player HP Reverse Text"
    elseif ContainsAny(text, FeaturesPhrases[74]) then
        key = "bars.playerHPBarTextLeft"
        label = "Class Resources Player HP Left Text"
    elseif ContainsAny(text, FeaturesPhrases[75]) then
        key = "bars.playerHPBarTextCenter"
        label = "Class Resources Player HP Center Text"
    elseif ContainsAny(text, FeaturesPhrases[76]) then
        key = "bars.playerHPBarTextRight"
        label = "Class Resources Player HP Right Text"
    elseif ContainsAny(text, FeaturesPhrases[77]) then
        key = "bars.playerHPBarTextSeparator"
        label = "Class Resources Player HP Text Delimiter"
    elseif ContainsAny(text, FeaturesPhrases[78]) then
        key = "bars.playerHPBarTextSize"
        label = "Class Resources Player HP Text Size"
    elseif ContainsAny(text, FeaturesPhrases[79]) then
        key = "bars.playerHPBarTextOffsetX"
        label = "Class Resources Player HP Text Offset X"
    elseif ContainsAny(text, FeaturesPhrases[80]) then
        key = "bars.playerHPBarTextOffsetY"
        label = "Class Resources Player HP Text Offset Y"
    elseif ContainsAny(text, FeaturesPhrases[81]) then
        key = "bars.playerHPBarTextEnabled"
        label = "Class Resources Player HP Text"
    elseif ContainsAny(text, FeaturesPhrases[82]) then
        key = "bars.playerHPBarBgTexture"
        label = "Class Resources Player HP Background Texture"
    elseif ContainsAny(text, FeaturesPhrases[83]) then
        key = "bars.playerHPBarTexture"
        label = "Class Resources Player HP Foreground Texture"
    elseif ContainsAny(text, FeaturesPhrases[84]) then
        key = "bars.playerHPBarBgAlpha"
        label = "Class Resources Player HP Background Opacity"
        fallback = 0.05
    elseif ContainsAny(text, FeaturesPhrases[85]) then
        key = "bars.playerHPBarWidthMode"
        label = "Class Resources Player HP Width Mode"
    elseif ContainsAny(text, FeaturesPhrases[86]) then
        key = "bars.playerHPBarAnchor"
        label = "Class Resources Player HP Anchor"
    elseif ContainsAny(text, FeaturesPhrases[87]) then
        key = "bars.playerHPBarSmoothFill"
        label = "Class Resources Player HP Smooth Fill"
    elseif ContainsAny(text, FeaturesPhrases[88]) then
        key = "bars.playerHPBarColorMode"
        label = "Class Resources Player HP Color Mode"
    elseif ContainsAny(text, FeaturesPhrases[89]) then
        key = "bars.playerHPBarOrbSize"
        label = "Class Resources Player HP Orb Size"
    elseif ContainsAny(text, FeaturesPhrases[90]) then
        key = "bars.playerHPBarShape"
        label = "Class Resources Player HP Shape"
    elseif ContainsAny(text, FeaturesPhrases[91]) then
        key = "bars.playerHPBarFrameLevelOffset"
        label = "Class Resources Player HP Frame Level"
    elseif ContainsAny(text, FeaturesPhrases[92]) then
        key = "bars.playerHPBarGap"
        label = "Class Resources Player HP Gap"
    elseif ContainsAny(text, FeaturesPhrases[93]) then
        key = "bars.playerHPBarOutline"
        label = "Class Resources Player HP Outline"
    elseif ContainsAny(text, FeaturesPhrases[94]) then
        key = "bars.playerHPBarOffsetX"
        label = "Class Resources Player HP Offset X"
    elseif ContainsAny(text, FeaturesPhrases[95]) then
        key = "bars.playerHPBarOffsetY"
        label = "Class Resources Player HP Offset Y"
    elseif ContainsAny(text, FeaturesPhrases[96]) then
        key = "bars.playerHPBarWidth"
        label = "Class Resources Player HP Width"
        fallback = 10
    elseif ContainsAny(text, FeaturesPhrases[97]) then
        key = "bars.playerHPBarHeight"
        label = "Class Resources Player HP Height"
    elseif ContainsAny(text, FeaturesPhrases[98]) then
        key = "bars.playerHPBarEnabled"
        label = "Class Resources Player HP Bar"
    else
        return nil
    end

    local setting = ClassPowerSetting(key)
    if not setting then return nil end
    local relativeDelta
    local value
    if setting.type == "number" then
        relativeDelta = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text, fallback)
        if relativeDelta == nil then
            value = ValueForRegistrySetting and ValueForRegistrySetting(setting, text, raw or text) or nil
        end
    else
        value = ValueForRegistrySetting and ValueForRegistrySetting(setting, text, raw or text) or nil
    end
    if value == nil and relativeDelta == nil then return nil end
    summary = "Changes the optional second Player HP bar shown with Class Resources."
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = label,
        summary = summary,
    }
end

function A._ParseClassPowerEmpoweredComboShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if not ContainsAny(text, FeaturesPhrases[99]) then return nil end
    if ContainsAny(text, FeaturesPhrases[100]) then return nil end
    local value = DetectBoolean(text)
    if value == nil then return nil end
    local setting = ClassPowerSetting("bars.showChargedComboPoints")
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = "Empowered Combo Points",
        summary = "Controls whether Class Resources show empowered combo point states.",
    }
end

function A._ParseClassPowerRuneTimeShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if not ContainsAny(text, FeaturesPhrases[101]) then return nil end
    if ContainsAny(text, FeaturesPhrases[102]) then return nil end
    local value = DetectBoolean(text)
    if value == nil then return nil end
    local setting = ClassPowerSetting("bars.runeShowTime")
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = "Rune Time",
        summary = "Controls whether Class Resources show rune timing per rune.",
    }
end

local CLASS_POWER_DISPLAY_BOOLEAN_SHORTCUTS = {
    {
        terms = { "elemental maelstrom", "maelstrom bar", "ele maelstrom" },
        key = "bars.showEleMaelstrom",
        label = "Elemental Maelstrom Bar",
        summary = "Controls whether Class Resources show the Elemental Maelstrom bar.",
    },
    {
        terms = { "ebon might", "ebon might timer", "augmentation ebon might" },
        key = "bars.showEbonMight",
        label = "Ebon Might Timer",
        summary = "Controls whether Class Resources show the Ebon Might timer.",
    },
    {
        terms = { "shadow insanity", "insanity bar", "shadow mana", "shadow resource bar" },
        key = "bars.showShadowMana",
        label = "Shadow Insanity Bar",
        summary = "Controls whether Class Resources show the Shadow Insanity bar.",
    },
    {
        terms = { "resource prediction", "class resource prediction", "class power prediction", "incoming resource" },
        key = "bars.classPowerShowPrediction",
        label = "Class Resource Prediction",
        summary = "Controls whether Class Resources show incoming resource prediction.",
    },
}

function A._ParseClassPowerDisplayBooleanShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, FeaturesPhrases[103]) then return nil end
    local value = DetectBoolean(text)
    if value == nil then return nil end
    for i = 1, #CLASS_POWER_DISPLAY_BOOLEAN_SHORTCUTS do
        local spec = CLASS_POWER_DISPLAY_BOOLEAN_SHORTCUTS[i]
        if ContainsAny(text, spec.terms) then
            local setting = ClassPowerSetting(spec.key)
            if setting then
                return {
                    kind = "changes",
                    changes = { { setting = setting, value = value } },
                    label = spec.label,
                    summary = spec.summary,
                }
            end
        end
    end
    return nil
end

function A._ParseClassPowerColorModeShortcut(text)
    local slotResource = ClassPowerSlotResourceForText and ClassPowerSlotResourceForText(text) or nil
    if not HasClassPowerIntent(text) and not slotResource then return nil end
    if ContainsAny(text, FeaturesPhrases[104]) then return nil end

    if ContainsAny(text, FeaturesPhrases[105]) then
        local value = DetectBoolean(text)
        if value == nil then return nil end
        local setting = ClassPowerSetting("bars.classPowerColorByType")
        if not setting then return nil end
        return {
            kind = "changes",
            changes = { { setting = setting, value = value } },
            label = "Class Resource Color by Type",
            summary = "Controls whether Class Resources use resource-type coloring.",
        }
    end

    if ContainsAny(text, FeaturesPhrases[106]) or (slotResource and ContainsAny(text, CLASS_POWER_SLOT_MODE_TERMS)) then
        if ExtractColor and ExtractColor(text) ~= nil then return nil end
        local settingKey = slotResource and ("bars.classPowerSlotColorModes." .. slotResource.token)
            or "bars.classPowerComboPointColorMode"
        local setting = ClassPowerSetting(settingKey)
        if not setting then return nil end
        local value = EnumValueForText and EnumValueForText(setting, text) or nil
        if value == nil then return nil end
        local resourceLabel = slotResource and (tostring(slotResource.className) .. " " .. tostring(slotResource.label)) or "Combo Points"
        return {
            kind = "changes",
            changes = { { setting = setting, value = value } },
            label = resourceLabel .. " Slot Color Mode",
            summary = "Changes how individual " .. resourceLabel .. " slot colors are chosen.",
        }
    end

    return nil
end

function A._ParseClassPowerSeparatorShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if not ContainsAny(text, FeaturesPhrases[107]) then return nil end
    if ContainsAny(text, FeaturesPhrases[108]) then return nil end
    local setting = ClassPowerSetting("bars.classPowerTickWidth")
    if not setting then return nil end
    local relativeDelta = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text, 1)
    local value
    if relativeDelta == nil then
        value = FirstNumber(text)
        if value == nil then return nil end
    end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = "Class Resource Separator Width",
        summary = "Adjusts the Class Resource separator width.",
    }
end

function A._ParseClassPowerGapShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, FeaturesPhrases[109]) then return nil end
    if not ContainsAny(text, FeaturesPhrases[110]) then return nil end
    if ContainsAny(text, FeaturesPhrases[111]) then return nil end
    local setting = ClassPowerSetting("bars.classPowerGap")
    if not setting then return nil end
    local relativeDelta = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text, 1)
    local value
    if relativeDelta == nil then
        value = FirstNumber(text)
        if value == nil then return nil end
    end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = "Class Resource Pip Gap",
        summary = "Adjusts Class Resource pip spacing.",
    }
end

function A._ParseClassPowerBackgroundShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, FeaturesPhrases[112])
        and not ContainsAny(text, FeaturesPhrases[113]) then
        return nil
    end
    if not ContainsAny(text, FeaturesPhrases[114]) then return nil end
    if ContainsAny(text, FeaturesPhrases[115]) then return nil end
    local setting = ClassPowerSetting("bars.classPowerBgAlpha")
    if not setting then return nil end
    local relativeDelta = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text, 0.05)
    local value
    if relativeDelta == nil then
        value = FirstNumber(text)
        if value ~= nil and value > 1 then value = value / 100 end
    end
    if value == nil and relativeDelta == nil then
        local bool = DetectBoolean(text)
        if bool == nil and ContainsAny(text, FeaturesPhrases[116]) then bool = false end
        if bool == nil and ContainsAny(text, FeaturesPhrases[117]) then bool = true end
        if bool == nil then return nil end
        value = bool and 0.3 or 0
    end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = "Class Resource Background Opacity",
        summary = "Adjusts Class Resource background visibility.",
    }
end

function A._ParseClassPowerOutlineOpacityShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, FeaturesPhrases[118]) then return nil end

    local key
    local label
    local summary
    local fallback = 1
    if ContainsAny(text, FeaturesPhrases[119]) then
        key = "bars.classPowerOutline"
        label = "Class Resource Outline"
        summary = "Adjusts Class Resource outline thickness."
    elseif ContainsAny(text, FeaturesPhrases[120]) then
        key = "bars.classPowerFilledAlpha"
        label = "Class Resource Filled Opacity"
        summary = "Adjusts the opacity of filled Class Resource pips."
        fallback = 0.05
    elseif ContainsAny(text, FeaturesPhrases[121]) then
        key = "bars.classPowerEmptyAlpha"
        label = "Class Resource Empty Opacity"
        summary = "Adjusts the opacity of empty Class Resource pips."
        fallback = 0.05
    else
        return nil
    end

    local setting = ClassPowerSetting(key)
    if not setting then return nil end
    local relativeDelta = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text, fallback)
    local value
    if relativeDelta == nil then
        value = FirstNumber(text)
        if value ~= nil and (key == "bars.classPowerFilledAlpha" or key == "bars.classPowerEmptyAlpha") and value > 1 then
            value = value / 100
        end
    end
    if value == nil and relativeDelta == nil and key == "bars.classPowerOutline" then
        local bool = DetectBoolean(text)
        if bool == nil then return nil end
        value = bool and 1 or 0
    end
    if value == nil and relativeDelta == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = label,
        summary = summary,
    }
end

function A._ParseClassPowerTextureShortcut(text, raw)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, FeaturesPhrases[122]) then return nil end
    if not ContainsAny(text, FeaturesPhrases[123]) then return nil end

    local key
    local label
    if ContainsAny(text, FeaturesPhrases[124]) then
        key = "bars.classPowerBgTexture"
        label = "Class Resource Background Texture"
    else
        key = "bars.classPowerTexture"
        label = "Class Resource Foreground Texture"
    end

    local setting = ClassPowerSetting(key)
    if not setting then return nil end
    local value = ValueForRegistrySetting and ValueForRegistrySetting(setting, text, raw or text) or nil
    if value == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = label,
        summary = "Changes the Class Resource SharedMedia texture.",
    }
end

function A._ParseClassPowerDetachedPowerBarDetailShortcut(text, raw)
    if not ContainsAny(text, FeaturesPhrases[125]) then return nil end
    if ContainsAny(text, FeaturesPhrases[126]) then return nil end

    local key
    local label
    local value
    local relativeDelta

    if ContainsAny(text, FeaturesPhrases[127]) then
        key = "bars.detachedPowerBarWidthMode"
        label = "Detached Power Bar Width Mode"
        local setting = ClassPowerSetting(key)
        value = setting and EnumValueForText(setting, text) or nil
    -- Detached texture phrases fall through to the generic parser: power art is
    -- owned by the Player unit page / Bars page settings now.
    elseif ContainsAny(text, FeaturesPhrases[130]) then
        key = "bars.detachedPowerBarOutline"
        label = "Detached Power Bar Outline"
        local setting = ClassPowerSetting(key)
        relativeDelta = setting and RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text, 1) or nil
        if relativeDelta == nil then
            value = FirstNumber(text)
            if value == nil then
                local bool = DetectBoolean(text)
                if bool ~= nil then value = bool and 1 or 0 end
            end
        end
    else
        return nil
    end

    local setting = ClassPowerSetting(key)
    if not setting then return nil end
    if value == nil and relativeDelta == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = label,
        summary = "Changes the detached Player Power Bar options managed by Class Resources.",
    }
end

function A._ParseClassPowerAltManaShortcut(text, raw)
    if not ContainsAny(text, FeaturesPhrases[131]) then return nil end
    if ContainsAny(text, FeaturesPhrases[132]) then return nil end

    local key
    local label
    local fallback = 1
    if ContainsAny(text, FeaturesPhrases[133]) then
        key = "bars.altManaHeight"
        label = "Alternative Mana Height"
    elseif ContainsAny(text, FeaturesPhrases[427]) then
        key = "bars.altManaWidth"
        label = "Alternative Mana Width"
    elseif ContainsAny(text, FeaturesPhrases[428]) then
        key = "bars.altManaOffsetX"
        label = "Alternative Mana Offset X"
    elseif ContainsAny(text, FeaturesPhrases[134]) then
        key = "bars.altManaOffsetY"
        label = "Alternative Mana Offset Y"
    else
        key = "bars.showAltMana"
        label = "Alternative Mana Bar"
    end

    local setting = ClassPowerSetting(key)
    if not setting then return nil end
    local relativeDelta
    local value
    if setting.type == "number" then
        relativeDelta = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text, fallback)
        if relativeDelta == nil then value = ValueForRegistrySetting and ValueForRegistrySetting(setting, text, raw or text) or nil end
    else
        value = ValueForRegistrySetting and ValueForRegistrySetting(setting, text, raw or text) or nil
    end
    if value == nil and relativeDelta == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = label,
        summary = "Changes the Alternative Mana bar shown on the Class Resources page.",
    }
end

function A._ParseClassPowerMoveShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, FeaturesPhrases[135]) then return nil end
    if not ContainsAny(text, FeaturesPhrases[136]) then return nil end
    local direction = DetectDirection(text, {})
    if not direction then return nil end
    local key = (direction == "left" or direction == "right") and "bars.classPowerOffsetX" or "bars.classPowerOffsetY"
    local setting = Registry and Registry:GetSetting(key)
    if not setting then return nil end
    local amount = FirstNumber(text) or 10
    if direction == "left" or direction == "down" then amount = -amount end
    return {
        kind = "changes",
        changes = { { setting = setting, relativeDelta = amount, direction = direction } },
        label = "Move Class Resource",
        summary = "Moves the Class Resource offset by pixels.",
    }
end

local function HasClassPowerDetachedPlayerPowerIntent(text)
    if ContainsAny(text, FeaturesPhrases[137]) then return false end
    if ContainsAny(text, FeaturesPhrases[138]) then
        return true
    end
    if HasClassPowerIntent(text) and ContainsAny(text, FeaturesPhrases[139]) then
        return true
    end
    if M and M.activeKey == "classpower" and ContainsAny(text, FeaturesPhrases[140]) then
        return true
    end
    return false
end

local function PlayerSetting(key)
    return Registry and Registry:GetSetting("player." .. tostring(key or ""))
end

local function PlayerChange(key, value, relativeDelta, direction)
    local setting = PlayerSetting(key)
    if not setting then return nil end
    return {
        setting = setting,
        value = value,
        relativeDelta = relativeDelta,
        direction = direction,
        valueLabel = value ~= nil and (P.ValueDisplay and P.ValueDisplay(setting, value) or nil) or nil,
    }
end

local function NumberPlayerChange(key, text, fallback, direction)
    local setting = PlayerSetting(key)
    if not setting then return nil end
    local relativeDelta
    local value
    if direction then
        local amount = FirstNumber(text) or fallback or 1
        if direction == "left" or direction == "down" then amount = -amount end
        relativeDelta = amount
    else
        relativeDelta = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text, fallback)
        if relativeDelta == nil then
            value = FirstNumber(text)
            if value == nil then return nil end
        end
    end
    return PlayerChange(key, value, relativeDelta, direction)
end

function A._ParseClassPowerDetachedPlayerPowerShortcut(text, raw)
    if not HasClassPowerDetachedPlayerPowerIntent(text) then return nil end

    local key
    local value
    local relativeDelta
    local direction = DetectDirection(text, {})
    local change

    if ContainsAny(text, FeaturesPhrases[141]) then
        key = "detachedPowerBarAnchorToClassPower"
        value = DetectBoolean(text)
        if value == nil then value = not ContainsAny(text, FeaturesPhrases[142]) end
        change = PlayerChange(key, value)
    elseif ContainsAny(text, FeaturesPhrases[143]) then
        key = "detachedPowerBarSyncClassPower"
        value = DetectBoolean(text)
        if value == nil then value = not ContainsAny(text, FeaturesPhrases[144]) end
        change = PlayerChange(key, value)
    elseif ContainsAny(text, FeaturesPhrases[145]) then
        key = "powerBarDetached"
        if ContainsAny(text, FeaturesPhrases[146]) then
            value = false
        elseif ContainsAny(text, FeaturesPhrases[147]) then
            value = true
        else
            value = DetectBoolean(text)
        end
        if value ~= nil then change = PlayerChange(key, value) end
    elseif ContainsAny(text, FeaturesPhrases[148]) then
        key = "detachedPowerBarTextOnBar"
        value = DetectBoolean(text)
        if value == nil then value = true end
        change = PlayerChange(key, value)
    elseif ContainsAny(text, FeaturesPhrases[149]) then
        change = NumberPlayerChange("detachedPowerBarWidth", text, 10)
    elseif ContainsAny(text, FeaturesPhrases[150])
        and not ContainsAny(text, FeaturesPhrases[151]) then
        key = "detachedPowerBarShape"
        local setting = PlayerSetting(key)
        value = setting and EnumValueForText(setting, text) or nil
        if value ~= nil then change = PlayerChange(key, value) end
    elseif ContainsAny(text, FeaturesPhrases[152]) then
        change = NumberPlayerChange("detachedPowerOrbSize", text, 4)
    elseif ContainsAny(text, FeaturesPhrases[153]) then
        change = NumberPlayerChange("powerFontSize", text, 1)
    elseif ContainsAny(text, FeaturesPhrases[154]) then
        change = NumberPlayerChange("detachedPowerBarFrameLevelOffset", text, 1)
    elseif ContainsAny(text, FeaturesPhrases[155]) then
        change = NumberPlayerChange("detachedPowerBarHeight", text, 1)
    elseif direction or ContainsAny(text, FeaturesPhrases[156]) then
        local axis
        if ContainsAny(text, FeaturesPhrases[157]) then axis = "x" end
        if ContainsAny(text, FeaturesPhrases[158]) then axis = "y" end
        if not axis and direction then axis = (direction == "left" or direction == "right") and "x" or "y" end
        if axis == "x" then
            change = NumberPlayerChange("detachedPowerBarOffsetX", text, 10, direction)
        elseif axis == "y" then
            change = NumberPlayerChange("detachedPowerBarOffsetY", text, 10, direction)
        end
    end

    if not change then return nil end
    return {
        kind = "changes",
        changes = { change },
        label = change.setting and change.setting.label or "Class Resources Player Power",
        summary = "Changes the Player detached Power Bar options shown on the Class Resources page.",
    }
end

A._GameplayShortcutSpecs = A._GameplayShortcutSpecs or {
    {
        id = "combatTimer",
        label = "Combat Timer",
        terms = { "combat timer", "kampf timer", "kampftimer" },
        pageTerms = { "timer", "kampf timer", "kampftimer" },
        enable = "gameplay.enableCombatTimer",
        x = "gameplay.combatOffsetX",
        y = "gameplay.combatOffsetY",
        size = "gameplay.combatFontSize",
        anchor = "gameplay.combatTimerAnchor",
        booleans = {
            { key = "gameplay.lockCombatTimer", terms = { "lock", "locked", "unlock", "unlocked", "lock position", "sperren", "entsperren", "position sperren" } },
            { key = "gameplay.combatTimerClickThrough", terms = { "click through", "click-through", "clickable", "mouse clicks", "mouse input", "accept clicks", "durchklickbar", "klick durch", "mausklicks", "mauseingabe" } },
        },
    },
    {
        id = "combatState",
        label = "Combat Enter/Leave Text",
        terms = { "combat state", "combat enter leave", "combat enter", "combat leave", "kampf text", "kampf status", "kampfstatus", "kampfanzeige" },
        -- This feature is a TEXT that flashes on entering or leaving combat. The
        -- per-unit "Combat Indicator" is a different control whose name starts
        -- with the same two words, so "enable target combat state indicator"
        -- matched here and toggled a global text instead. An indicator word is
        -- decisive: this feature never has one.
        notTerms = { "indicator", "icon", "symbol", "anzeige symbol" },
        pageTerms = { "enter leave", "enter text", "leave text", "combat text", "state text", "kampf text", "kampfstatus", "kampfanzeige" },
        enable = "gameplay.enableCombatStateText",
        x = "gameplay.combatStateOffsetX",
        y = "gameplay.combatStateOffsetY",
        size = "gameplay.combatStateFontSize",
        duration = "gameplay.combatStateDuration",
        booleans = {
            { key = "gameplay.lockCombatState", terms = { "lock", "locked", "unlock", "unlocked", "lock position", "sperren", "entsperren", "position sperren" } },
            { key = "gameplay.combatStateColorSync", terms = {
                "sync color", "sync colors", "color sync",
                "sync combat state colors", "sync combat enter leave colors",
                "same combat state colors", "combat state color sync", "farben synchron", "gleiche farben",
            } },
        },
    },
    {
        id = "playerTotems",
        label = "Totem Frame",
        terms = { "totem frame", "totemframe", "blizzard totem", "statue frame", "totem icon", "totem icons", "totem", "totems", "totem rahmen", "totemrahmen", "statuen rahmen", "statuenrahmen", "statue rahmen" },
        pageTerms = { "totem", "totems", "statue", "totem rahmen", "totemrahmen", "statuen rahmen", "statuenrahmen", "statue rahmen" },
        enable = "gameplay.enablePlayerTotems",
        x = "gameplay.playerTotemsOffsetX",
        y = "gameplay.playerTotemsOffsetY",
        size = "gameplay.playerTotemsIconSize",
        anchorFrom = "gameplay.playerTotemsAnchorFrom",
        anchorTo = "gameplay.playerTotemsAnchorTo",
    },
    {
        id = "combatCrosshair",
        label = "Combat Crosshair",
        terms = { "combat crosshair", "crosshair", "fadenkreuz" },
        pageTerms = { "crosshair", "fadenkreuz" },
        enable = "gameplay.enableCombatCrosshair",
        size = "gameplay.crosshairSize",
        thickness = "gameplay.crosshairThickness",
        booleans = {
            { key = "gameplay.enableCombatCrosshairMeleeRangeColor", terms = { "range color", "melee range color", "in range color", "color mode", "reichweitenfarbe", "reichweite farbe", "nahkampf reichweite farbe", "farbe nach reichweite" } },
            { key = "gameplay.meleeSpellPerClass", terms = { "per class", "class spell", "spell per class", "pro klasse", "je klasse", "zauber pro klasse" } },
            { key = "gameplay.meleeSpellPerSpec", terms = { "per spec", "spec spell", "spell per spec", "pro spec", "pro spezialisierung", "je spec", "je spezialisierung", "zauber pro spec" } },
        },
    },
}

function A._GameplayShortcutSpec(text)
    local specs = A._GameplayShortcutSpecs or {}
    for i = 1, #specs do
        local spec = specs[i]
        if ContainsAny(text, spec.terms)
            and not (spec.notTerms and ContainsAny(text, spec.notTerms)) then
            return spec
        end
    end
    if M and M.activeKey == "gameplay" then
        for i = 1, #specs do
            local spec = specs[i]
            if ContainsAny(text, spec.pageTerms)
                and not (spec.notTerms and ContainsAny(text, spec.notTerms)) then
                return spec
            end
        end
        if ContainsAny(text, FeaturesPhrases[159]) and not ContainsAny(text, FeaturesPhrases[160]) then
            return specs[1]
        end
    end
    return nil
end

function A._GameplayShortcutChange(key, value, relativeDelta, direction, label, summary)
    local setting = Registry and Registry:GetSetting(key)
    return setting and {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta, direction = direction } },
        label = label or setting.label,
        summary = summary or "Changes a Gameplay option.",
    } or nil
end

function A._ParseGameplayTextValueShortcut(text, raw)
    if ContainsAny(text, FeaturesPhrases[161]) then return nil end
    local key
    local label
    if ContainsAny(text, FeaturesPhrases[162]) then
        key = "gameplay.combatStateEnterText"
        label = "Combat Enter Text"
    elseif ContainsAny(text, FeaturesPhrases[163]) then
        key = "gameplay.combatStateLeaveText"
        label = "Combat Leave Text"
    else
        return nil
    end
    local setting = Registry and Registry:GetSetting(key)
    if not setting then return nil end
    local value = ValueForRegistrySetting and ValueForRegistrySetting(setting, text, raw or text) or nil
    if value == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = label,
        summary = "Changes a Gameplay text value.",
    }
end

function A._ParseGameplayBooleanShortcut(text)
    local value = DetectBoolean(text)
    local spec = A._GameplayShortcutSpec(text)
    if not spec then return nil end
    local key
    local booleans = spec.booleans or {}
    for i = 1, #booleans do
        if ContainsAny(text, booleans[i].terms) then
            key = booleans[i].key
            break
        end
    end
    if key and value == nil then
        if ContainsAny(text, FeaturesPhrases[164]) then
            value = false
        elseif ContainsAny(text, FeaturesPhrases[165]) and tostring(key):find("ClickThrough", 1, true) then
            value = false
        elseif ContainsAny(text, FeaturesPhrases[166]) then
            value = true
        end
    end
    if value == nil then return nil end
    if not key then
        if ContainsAny(text, FeaturesPhrases[167]) then
            return nil
        end
        key = spec.enable
    end
    return A._GameplayShortcutChange(key, value, nil, nil, spec.label, "Toggles a Gameplay option.")
end

function A._ParseGameplayAnchorShortcut(text)
    if not ContainsAny(text, FeaturesPhrases[168]) then return nil end
    local spec = A._GameplayShortcutSpec(text)
    if not spec then return nil end
    local key
    if spec.id == "combatTimer" then
        key = spec.anchor
    elseif spec.id == "playerTotems" then
        if ContainsAny(text, FeaturesPhrases[169]) then
            key = spec.anchorFrom
        elseif ContainsAny(text, FeaturesPhrases[170]) then
            key = spec.anchorTo
        end
    end
    if not key then return nil end
    local setting = Registry and Registry:GetSetting(key)
    if not setting then return nil end
    local value = EnumValueForText(setting, text)
    if value == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or spec.label,
        summary = "Changes the selected Gameplay anchor.",
    }
end

function A._ParseGameplaySpellIDShortcut(text)
    if not ContainsAny(text, FeaturesPhrases[171]) then return nil end
    if ContainsAny(text, FeaturesPhrases[172]) then return nil end
    local setting = Registry and Registry:GetSetting("gameplay.nameplateMeleeSpellID")
    if not setting then return nil end
    local value
    if ContainsAny(text, FeaturesPhrases[173]) then
        value = 0
    else
        value = FirstNumber(text)
    end
    if value == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = "Crosshair Melee Range Spell",
        summary = "Changes the Combat Crosshair melee range spell ID.",
    }
end

function A._ParseGameplayNumberShortcut(text)
    local spec = A._GameplayShortcutSpec(text)
    if not spec then return nil end
    if ContainsAny(text, FeaturesPhrases[174]) then return nil end
    local key
    if spec.id == "combatState" and ContainsAny(text, FeaturesPhrases[175]) then
        key = spec.duration
    elseif spec.id == "combatCrosshair" and ContainsAny(text, FeaturesPhrases[176]) then
        key = spec.thickness
    elseif ContainsAny(text, FeaturesPhrases[177]) then
        key = spec.size
    end
    if not key then return nil end
    local setting = Registry and Registry:GetSetting(key)
    if not setting then return nil end
    local relativeDelta = RelativeNumberDeltaForText(setting, text)
    local value
    if relativeDelta == nil then
        value = FirstNumber(text)
        if value == nil then return nil end
    end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = setting.label or spec.label,
        summary = "Changes a Gameplay number option.",
    }
end

local GAMEPLAY_PRESET_BOUNDS = {
    combatTimer = { width = 180, height = 42 },
    combatState = { width = 220, height = 42 },
}

local UNIT_PRESET_DEFAULTS = {
    player = { x = -256, y = -180, width = 275, height = 40 },
    target = { x = 320, y = -180, width = 275, height = 40 },
    focus = { x = -260, y = -300, width = 250, height = 40 },
    pet = { x = -275, y = -250, width = 160, height = 36 },
    targettarget = { x = 220, y = -300, width = 250, height = 40 },
    focustarget = { x = 260, y = 180, width = 250, height = 40 },
    boss = { x = 0, y = 160, width = 250, height = 40 },
    gf_party = { x = -400, y = 0, width = 120, height = 40 },
    gf_raid = { x = -500, y = 0, width = 80, height = 32 },
    gf_mythicraid = { x = -500, y = 0, width = 80, height = 32 },
}

local function GameplayPresetPlacement(text)
    if ContainsAny(text, FeaturesPhrases[178]) then return "below" end
    if ContainsAny(text, FeaturesPhrases[179]) then return "above" end
    if ContainsAny(text, FeaturesPhrases[180]) then return "left" end
    if ContainsAny(text, FeaturesPhrases[181]) then return "right" end
    if ContainsAny(text, FeaturesPhrases[182]) then return "center" end
    return nil
end

function A._GameplayPresetPointOffset(point, width, height)
    point = tostring(point or "CENTER"):upper()
    local x = 0
    local y = 0
    if point:find("LEFT", 1, true) then
        x = -(tonumber(width) or 0) / 2
    elseif point:find("RIGHT", 1, true) then
        x = (tonumber(width) or 0) / 2
    end
    if point:find("TOP", 1, true) then
        y = (tonumber(height) or 0) / 2
    elseif point:find("BOTTOM", 1, true) then
        y = -(tonumber(height) or 0) / 2
    end
    return x, y
end

function A._GameplayPresetFrameFromDB(dbKey, fallback)
    local db = _G.MSUF_DB
    local conf = db and type(db[dbKey]) == "table" and db[dbKey] or {}
    return {
        x = tonumber(conf.offsetX) or (fallback and fallback.x) or 0,
        y = tonumber(conf.offsetY) or (fallback and fallback.y) or 0,
        width = tonumber(conf.width) or (fallback and fallback.width) or 250,
        height = tonumber(conf.height) or (fallback and fallback.height) or 40,
        point = tostring(conf.point or conf.anchorPoint or "CENTER"),
        relativePoint = tostring(conf.relativePoint or conf.point or conf.anchorPoint or "CENTER"),
        anchorToUnitframe = conf.anchorToUnitframe,
        anchorToFrame = conf.anchorToFrame,
    }
end

local function UnitPresetFrame(unit, seen)
    unit = tostring(unit or "")
    local frame = A._GameplayPresetFrameFromDB(unit, UNIT_PRESET_DEFAULTS[unit])
    local anchorUnit = tostring(frame.anchorToUnitframe or "")
    if anchorUnit ~= "" and anchorUnit ~= "GLOBAL" and anchorUnit ~= "global" and anchorUnit ~= "FREE"
        and anchorUnit ~= unit and UNIT_PRESET_DEFAULTS[anchorUnit] and not (seen and seen[anchorUnit])
    then
        seen = seen or {}
        seen[unit] = true
        local anchor = UnitPresetFrame(anchorUnit, seen)
        local relX, relY = A._GameplayPresetPointOffset(frame.relativePoint, anchor.width, anchor.height)
        local pointX, pointY = A._GameplayPresetPointOffset(frame.point, frame.width, frame.height)
        frame.x = anchor.x + relX + frame.x - pointX
        frame.y = anchor.y + relY + frame.y - pointY
    else
        local pointX, pointY = A._GameplayPresetPointOffset(frame.point, frame.width, frame.height)
        frame.x = frame.x - pointX
        frame.y = frame.y - pointY
    end
    return frame
end

function A._GameplayPresetGroupFrame(scope)
    scope = tostring(scope or "")
    local frame = A._GameplayPresetFrameFromDB("gf_" .. scope, UNIT_PRESET_DEFAULTS["gf_" .. scope])
    local anchorUnit = tostring(frame.anchorToFrame or "")
    if anchorUnit ~= "" and anchorUnit ~= "FREE" and UNIT_PRESET_DEFAULTS[anchorUnit] then
        local anchor = UnitPresetFrame(anchorUnit)
        local relX, relY = A._GameplayPresetPointOffset(frame.point, anchor.width, anchor.height)
        local pointX, pointY = A._GameplayPresetPointOffset(frame.point, frame.width, frame.height)
        frame.x = anchor.x + relX + frame.x - pointX
        frame.y = anchor.y + relY + frame.y - pointY
    else
        local pointX, pointY = A._GameplayPresetPointOffset(frame.point, frame.width, frame.height)
        frame.x = frame.x - pointX
        frame.y = frame.y - pointY
    end
    return frame
end

function A._GameplayPresetReference(text)
    local groups = DetectGroups(text)
    if groups[1] then return A._GameplayPresetGroupFrame(groups[1]), groups[1], "group" end
    local units = DetectUnits(text)
    local unit = units[1] or "player"
    return UnitPresetFrame(unit), unit, "unit"
end

local function GameplayPresetPosition(spec, text, placement)
    local frame, key, frameType = A._GameplayPresetReference(text)
    local bounds = GAMEPLAY_PRESET_BOUNDS[spec and spec.id] or { width = 180, height = 42 }
    local anchorUnit = frameType == "unit" and spec and spec.id == "combatTimer"
        and (key == "player" or key == "target" or key == "focus") and key or nil
    local gap = 8
    local x, y = anchorUnit and 0 or frame.x, anchorUnit and 0 or frame.y
    if placement == "below" then
        y = y - (frame.height / 2) - (bounds.height / 2) - gap
    elseif placement == "above" then
        y = y + (frame.height / 2) + (bounds.height / 2) + gap
    elseif placement == "left" then
        x = x - (frame.width / 2) - (bounds.width / 2) - gap
    elseif placement == "right" then
        x = x + (frame.width / 2) + (bounds.width / 2) + gap
    end
    return math.floor(x + 0.5), math.floor(y + 0.5), anchorUnit, frameType
end

function A._ParseGameplayPositionPreset(text)
    if not ContainsAny(text, FeaturesPhrases[183]) then return nil end
    local placement = GameplayPresetPlacement(text)
    if not placement then return nil end
    local spec = A._GameplayShortcutSpec(text)
    if not spec or not spec.x or not spec.y then return nil end
    if spec.id ~= "combatTimer" and spec.id ~= "combatState" then
        return {
            kind = "unknown",
            text = tostring(spec.label or "That Gameplay element") .. " uses its own anchoring. I can still move it with pixel nudges or change its anchor options.",
            status = "failed",
        }
    end
    local x, y, anchorUnit = GameplayPresetPosition(spec, text, placement)
    local xSetting = Registry and Registry:GetSetting(spec.x)
    local ySetting = Registry and Registry:GetSetting(spec.y)
    if not xSetting or not ySetting then return nil end
    local changes = {}
    if spec.id == "combatTimer" and spec.anchor then
        local anchorSetting = Registry and Registry:GetSetting(spec.anchor)
        if anchorSetting then
            changes[#changes + 1] = { setting = anchorSetting, value = anchorUnit or "none" }
        end
    end
    changes[#changes + 1] = { setting = xSetting, value = x }
    changes[#changes + 1] = { setting = ySetting, value = y }
    return {
        kind = "changes",
        changes = changes,
        label = "Position " .. tostring(spec.label or "Gameplay element"),
        summary = "Positions a Gameplay tracker near the selected MSUF frame with the right anchor.",
    }
end

function A._ParseGameplayMoveShortcut(text)
    local direction = DetectDirection(text, {})
    local movementIntent = ContainsAny(text, FeaturesPhrases[184]) or (direction and FirstNumber(text) ~= nil)
    if not movementIntent then return nil end
    local spec = A._GameplayShortcutSpec(text)
    if not spec then return nil end
    local axis
    if ContainsAny(text, FeaturesPhrases[185]) then axis = "x" end
    if ContainsAny(text, FeaturesPhrases[186]) then axis = "y" end
    if not axis and direction then
        axis = (direction == "left" or direction == "right") and "x" or "y"
    end
    if not axis then return nil end
    local key = axis == "x" and spec.x or spec.y
    if not key then
        return {
            kind = "unknown",
            text = tostring(spec.label or "That Gameplay element") .. " has no position option in MSUF. I can still help with safe UI options.",
            status = "failed",
        }
    end
    local setting = Registry and Registry:GetSetting(key)
    if not setting then return nil end
    local value
    local relativeDelta
    if direction then
        local amount = FirstNumber(text) or 10
        if direction == "left" or direction == "down" then amount = -amount end
        relativeDelta = amount
    else
        value = FirstNumber(text)
        if value == nil then return nil end
    end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta, direction = direction or axis } },
        label = "Move " .. tostring(spec.label or "Gameplay element"),
        summary = "Moves a Gameplay element through its X/Y offset option.",
    }
end

local function ParseFontColorAction(text, raw)
    if not ContainsAny(text, FeaturesPhrases[187]) then return nil end
    if ContainsAny(text, FeaturesPhrases[188])
        and not ContainsAny(text, FeaturesPhrases[189])
    then
        return nil
    end
    if ContainsAny(text, FeaturesPhrases[190]) then
        local action = Registry and Registry:GetAction("reset_global_font_color")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Reset global font color",
            summary = "Returns global font color to palette behavior.",
        } or nil
    end
    local r, g, b, label = ExtractColor(raw, text)
    if not r then return nil end
    local action = Registry and Registry:GetAction("set_global_font_color")
    return action and {
        kind = "action",
        action = action,
        args = { r = r, g = g, b = b, label = label },
        label = "Set global font color",
        summary = "Applies a global custom font color.",
    } or nil
end

local function BuildColorResetAction(key, label, summary)
    local action = Registry and Registry:GetAction(key)
    return action and {
        kind = "action",
        action = action,
        args = {},
        confirmRequired = true,
        label = label,
        summary = summary or "Resets an MSUF color section.",
    } or nil
end

local POWER_TOKEN_EXTRA_ALIASES = {
    MANA = { "mana" },
    RAGE = { "rage" },
    ENERGY = { "energy" },
    FOCUS = { "focus power", "hunter focus" },
    RUNIC_POWER = { "runic power" },
    INSANITY = { "insanity power" },
    FURY = { "fury power" },
    PAIN = { "pain power" },
    ESSENCE = { "essence power" },
    LUNAR_POWER = { "astral power", "lunar power" },
    MAELSTROM = { "maelstrom power" },
}

local function PowerColorTokenForText(text)
    local tokens = A.PowerColorTokens or {}
    local bestToken
    local bestLen = 0
    local function Consider(token, alias)
        if not token or not alias then return end
        if HasPhrase(text, alias) then
            local len = #Compact(alias)
            if len > bestLen then
                bestLen = len
                bestToken = token
            end
        end
    end
    for i = 1, #(tokens or {}) do
        local spec = tokens[i]
        local token = spec and spec.key
        Consider(token, spec and spec.label)
        Consider(token, token and token:gsub("_", " "))
        local extra = token and POWER_TOKEN_EXTRA_ALIASES[token]
        for j = 1, #(extra or {}) do Consider(token, extra[j]) end
    end
    return bestToken
end

local CP_TOKEN_EXTRA_ALIASES = {
    COMBO_POINTS = { "combo point", "combo points" },
    CHARGED = { "charged combo point", "charged combo points", "empowered combo point", "empowered combo points" },
    SOUL_FRAGMENTS_META = { "soul fragments void meta", "void meta soul fragments" },
    MAELSTROM = { "maelstrom", "maelstrom weapon" },
    MAELSTROM_ABOVE_5 = { "maelstrom above 5", "maelstrom weapon above 5", "maelstrom 5+", "maelstrom weapon 5+" },
    ASTRAL_POWER = { "astral power" },
    AP_PREDICTION = { "astral prediction", "astral power prediction" },
    ECLIPSE_CA = { "celestial alignment", "ca eclipse" },
    STAGGER_GREEN = { "stagger light", "light stagger", "green stagger" },
    STAGGER_YELLOW = { "stagger moderate", "moderate stagger", "yellow stagger" },
    STAGGER_RED = { "stagger heavy", "heavy stagger", "red stagger" },
    SOUL_FRAGMENTS_VENG = { "soul fragments vengeance", "vengeance soul fragments" },
    MAELSTROM_POWER = { "maelstrom power" },
    TIP_OF_THE_SPEAR = { "tip of the spear" },
    EBON_MIGHT = { "ebon might" },
    RESOURCE_TEXT = { "resource text", "class resource text", "class power text" },
}

local SLOT_ORDINAL_ALIASES = {
    [1] = { "1", "1st", "first", "one", "erste", "erster", "erstes" },
    [2] = { "2", "2nd", "second", "two", "zweite", "zweiter", "zweites" },
    [3] = { "3", "3rd", "third", "three", "dritte", "dritter", "drittes" },
    [4] = { "4", "4th", "fourth", "four", "vierte", "vierter", "viertes" },
    [5] = { "5", "5th", "fifth", "five", "fünfte", "fuenfte", "fünfter", "fuenfter" },
    [6] = { "6", "6th", "sixth", "six", "sechste", "sechster", "sechstes" },
    [7] = { "7", "7th", "seventh", "seven", "siebte", "siebter", "siebtes" },
    [8] = { "8", "8th", "eighth", "eight", "achte", "achter", "achtes" },
    [9] = { "9", "9th", "ninth", "nine", "neunte", "neunter", "neuntes" },
    [10] = { "10", "10th", "tenth", "ten", "zehnte", "zehnter", "zehntes" },
}

local function ConsiderSlotResourceAlias(text, spec, alias, current, bestLen)
    alias = tostring(alias or ""):lower()
    if alias ~= "" and HasPhrase(text, alias) then
        local len = #Compact(alias)
        if len > bestLen then return spec, len end
    end
    return current, bestLen
end

ClassPowerSlotResourceForText = function(text)
    local resources = A.ClassPowerSlotResources or {}
    local best, bestLen = nil, 0
    for i = 1, #resources do
        local spec = resources[i]
        best, bestLen = ConsiderSlotResourceAlias(text, spec, spec.label, best, bestLen)
        best, bestLen = ConsiderSlotResourceAlias(text, spec, spec.token and spec.token:gsub("_", " "), best, bestLen)
        for j = 1, #(spec.aliases or {}) do
            best, bestLen = ConsiderSlotResourceAlias(text, spec, spec.aliases[j], best, bestLen)
        end
    end
    return best, bestLen
end

ClassPowerSlotIndexForText = function(text, maxSlot)
    maxSlot = tonumber(maxSlot) or 0
    if ContainsAny(text, CLASS_POWER_SLOT_THRESHOLD_TERMS) then return nil end
    for slot = math.min(maxSlot, 10), 1, -1 do
        local aliases = SLOT_ORDINAL_ALIASES[slot]
        for i = 1, #(aliases or {}) do
            if HasPhrase(text, aliases[i]) then return slot end
        end
    end
    return nil
end

local function ClassPowerColorTokenForText(text)
    local tokens = A.ClassPowerColorTokens or {}
    local bestToken
    local bestLen = 0
    local function Consider(token, alias)
        if not token or not alias then return end
        if HasPhrase(text, alias) then
            local len = #Compact(alias)
            if len > bestLen then
                bestLen = len
                bestToken = token
            end
        end
    end
    for i = 1, #(tokens or {}) do
        local spec = tokens[i]
        local token = spec and spec.key
        Consider(token, spec and spec.label)
        Consider(token, token and token:gsub("_", " "))
        local extra = token and CP_TOKEN_EXTRA_ALIASES[token]
        for j = 1, #(extra or {}) do Consider(token, extra[j]) end
    end
    local slotResource, resourceMatchLen = ClassPowerSlotResourceForText(text)
    if slotResource and ContainsAny(text, CLASS_POWER_FULL_COLOR_TERMS) and ((resourceMatchLen or 0) + 12) > bestLen then
        bestLen = (resourceMatchLen or 0) + 12
        bestToken = tostring(slotResource.token) .. "_FULL"
    end
    local slot = slotResource and ClassPowerSlotIndexForText(text, slotResource.count) or nil
    if slot and bestToken ~= tostring(slotResource.token) .. "_FULL" and ((resourceMatchLen or 0) + 8) > bestLen then
        bestLen = (resourceMatchLen or 0) + 8
        bestToken = tostring(slotResource.token) .. "_" .. tostring(slot)
    end
    for i = 1, 7 do
        local token = "COMBO_POINTS_" .. tostring(i)
        Consider(token, "combo point " .. tostring(i))
        Consider(token, "combo point slot " .. tostring(i))
        Consider(token, "cp " .. tostring(i))
    end
    return bestToken
end

function A._ParseClassPowerColorShortcut(text, raw)
    local slotResource = ClassPowerSlotResourceForText and ClassPowerSlotResourceForText(text) or nil
    if not HasClassPowerIntent(text) and not slotResource then return nil end
    if ContainsAny(text, FeaturesPhrases[191]) then return nil end
    local token = ClassPowerColorTokenForText(text)
    local r, g, b, label = ExtractColor(raw, text)
    local asksForColor = ContainsAny(text, { "color", "colour", "recolor", "recolour" })
    if slotResource and asksForColor and DetectBoolean(text) == nil and not r then
        return {
            kind = "answer",
            status = "info",
            result = "info",
            text = "Yes. Which " .. tostring(slotResource.className) .. " " .. tostring(slotResource.label)
                .. " color do you want, and should it apply to all slots, one slot, or only when the resource is full?\n"
                .. "Examples: set all " .. tostring(slotResource.label) .. " slots cyan | set "
                .. tostring(slotResource.label) .. " 3 blue | set full " .. tostring(slotResource.label) .. " purple",
            summary = "Asks which class-resource color and slot scope to change.",
        }
    end
    if not r then return nil end
    local background = ContainsAny(text, FeaturesPhrases[192])
    local allSlots = slotResource
        and not background
        and not ClassPowerSlotIndexForText(text, slotResource.count)
        and not ContainsAny(text, CLASS_POWER_FULL_COLOR_TERMS)
        and ContainsAny(text, { "all", "all slots", "every", "each" })
    if allSlots then
        local changes = {}
        for slot = 1, tonumber(slotResource.count) or 0 do
            local setting = ClassPowerSetting("general.classPowerColorOverrides." .. tostring(slotResource.token) .. "_" .. tostring(slot))
            if setting then
                changes[#changes + 1] = { setting = setting, value = { r = r, g = g, b = b, label = label } }
            end
        end
        if #changes > 0 then
            return {
                kind = "changes",
                changes = changes,
                bulkSafe = true,
                label = tostring(slotResource.className) .. " " .. tostring(slotResource.label) .. " Slot Colors",
                summary = "Changes every " .. tostring(slotResource.className) .. " " .. tostring(slotResource.label) .. " slot color.",
            }
        end
    end
    if not token then return nil end
    local key = (background and "general.classPowerBgColorOverrides." or "general.classPowerColorOverrides.") .. token
    local setting = ClassPowerSetting(key)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = { r = r, g = g, b = b, label = label } } },
        label = background and "Class Resource Background Color" or "Class Resource Color",
        summary = slotResource
            and ("Changes a " .. tostring(slotResource.className) .. " " .. tostring(slotResource.label) .. " color.")
            or "Changes a Class Resource foreground or background color.",
    }
end

function A._ParseClassPowerColorPriorityShortcut(text, raw)
    local hasBulkScope = ContainsAny(text, { "all", "all slots", "every", "each" })
    local asksWithoutValue = ContainsAny(text, { "color", "colour", "recolor", "recolour" })
        and DetectBoolean(text) == nil
        and ExtractColor(raw, text) == nil
    if not hasBulkScope and not asksWithoutValue then return nil end
    return A._ParseClassPowerColorShortcut(text, raw)
end

local SPEC_RESOURCE_COLOR_ROUTES = {
    WARRIOR = {
        aliases = { "warrior" },
        specs = {
            { aliases = { "arms", "arms warrior" } }, { aliases = { "fury warrior" } }, { aliases = { "protection warrior", "prot warrior" } },
        },
        targets = {
            { label = "Rage (Player Power Bar)", keys = { "general.powerColorOverrides.RAGE" } },
            { label = "Whirlwind (Class Resources)", keys = { "general.classPowerColorOverrides.WHIRLWIND" } },
        },
    },
    PALADIN = {
        aliases = { "paladin" }, specs = { { aliases = { "holy paladin" } }, { aliases = { "protection paladin", "prot paladin" } }, { aliases = { "retribution", "retribution paladin", "ret paladin" } } },
        targets = {
            { label = "Mana (Player Power Bar)", keys = { "general.powerColorOverrides.MANA" } },
            { label = "Holy Power (Class Resources)", keys = { "general.classPowerColorOverrides.HOLY_POWER" } },
        },
    },
    HUNTER = {
        aliases = { "hunter" },
        specs = {
            { aliases = { "beast mastery", "beast mastery hunter", "bm hunter" }, targets = { { label = "Focus (Player Power Bar)", keys = { "general.powerColorOverrides.FOCUS" } } } },
            { aliases = { "marksmanship", "marksmanship hunter", "mm hunter" }, targets = { { label = "Focus (Player Power Bar)", keys = { "general.powerColorOverrides.FOCUS" } } } },
            { aliases = { "survival", "survival hunter" }, targets = {
                { label = "Focus (Player Power Bar)", keys = { "general.powerColorOverrides.FOCUS" } },
                { label = "Tip of the Spear (Class Resources)", keys = { "general.classPowerColorOverrides.TIP_OF_THE_SPEAR" } },
            } },
        },
    },
    ROGUE = {
        aliases = { "rogue" }, specs = { { aliases = { "assassination", "assassination rogue" } }, { aliases = { "outlaw", "outlaw rogue" } }, { aliases = { "subtlety", "subtlety rogue", "sub rogue" } } },
        targets = {
            { label = "Energy (Player Power Bar)", keys = { "general.powerColorOverrides.ENERGY" } },
            { label = "Combo Points (Class Resources)", keys = { "general.classPowerColorOverrides.COMBO_POINTS" } },
        },
    },
    PRIEST = {
        aliases = { "priest" },
        specs = {
            { aliases = { "discipline", "discipline priest", "disc priest" }, targets = { { label = "Mana (Player Power Bar)", keys = { "general.powerColorOverrides.MANA" } } } },
            { aliases = { "holy priest" }, targets = { { label = "Mana (Player Power Bar)", keys = { "general.powerColorOverrides.MANA" } } } },
            { aliases = { "shadow", "shadow priest" }, targets = {
                { label = "Insanity (Player Power Bar or Class Resources)", keys = { "general.powerColorOverrides.INSANITY", "general.classPowerColorOverrides.INSANITY" } },
                { label = "Mana (when Shadow Mana mode is active)", keys = { "general.powerColorOverrides.MANA" } },
            } },
        },
    },
    DEATHKNIGHT = {
        aliases = { "death knight", "deathknight", "dk" }, specs = { { aliases = { "blood death knight", "blood dk" } }, { aliases = { "frost death knight", "frost dk" } }, { aliases = { "unholy", "unholy death knight", "unholy dk" } } },
        targets = {
            { label = "Runic Power (Player Power Bar)", keys = { "general.powerColorOverrides.RUNIC_POWER" } },
            { label = "Runes (Class Resources)", keys = { "general.classPowerColorOverrides.RUNES" } },
        },
    },
    SHAMAN = {
        aliases = { "shaman" },
        specs = {
            { aliases = { "elemental", "elemental shaman", "ele shaman" }, targets = {
                { label = "Maelstrom (Player Power Bar or Class Resources)", keys = { "general.powerColorOverrides.MAELSTROM", "general.classPowerColorOverrides.MAELSTROM" } },
                { label = "Mana (when Elemental Maelstrom mode is active)", keys = { "general.powerColorOverrides.MANA" } },
            } },
            { aliases = { "enhancement", "enhancement shaman", "enh shaman" }, targets = {
                { label = "Mana (Player Power Bar)", keys = { "general.powerColorOverrides.MANA" } },
                { label = "Maelstrom Weapon (Class Resources)", keys = { "general.classPowerColorOverrides.MAELSTROM" } },
            } },
            { aliases = { "restoration shaman", "resto shaman" }, targets = { { label = "Mana (Player Power Bar)", keys = { "general.powerColorOverrides.MANA" } } } },
        },
    },
    MAGE = {
        aliases = { "mage" },
        specs = {
            { aliases = { "arcane", "arcane mage" }, targets = {
                { label = "Mana (Player Power Bar)", keys = { "general.powerColorOverrides.MANA" } },
                { label = "Arcane Charges (Class Resources)", keys = { "general.classPowerColorOverrides.ARCANE_CHARGES" } },
            } },
            { aliases = { "fire mage" }, targets = { { label = "Mana (Player Power Bar)", keys = { "general.powerColorOverrides.MANA" } } } },
            { aliases = { "frost mage" }, targets = {
                { label = "Mana (Player Power Bar)", keys = { "general.powerColorOverrides.MANA" } },
                { label = "Icicles (Class Resources)", keys = { "general.classPowerColorOverrides.ICICLES" } },
            } },
        },
    },
    WARLOCK = {
        aliases = { "warlock" }, specs = { { aliases = { "affliction", "affliction warlock" } }, { aliases = { "demonology", "demonology warlock", "demo warlock" } }, { aliases = { "destruction", "destruction warlock", "destro warlock" } } },
        targets = {
            { label = "Mana (Player Power Bar)", keys = { "general.powerColorOverrides.MANA" } },
            { label = "Soul Shards (Class Resources)", keys = { "general.classPowerColorOverrides.SOUL_SHARDS" } },
        },
    },
    MONK = {
        aliases = { "monk" },
        specs = {
            { aliases = { "brewmaster", "brewmaster monk", "brew monk" }, targets = {
                { label = "Energy (Player Power Bar)", keys = { "general.powerColorOverrides.ENERGY" } },
                { label = "Stagger tiers (Class Resources)", keys = { "general.classPowerColorOverrides.STAGGER_GREEN", "general.classPowerColorOverrides.STAGGER_YELLOW", "general.classPowerColorOverrides.STAGGER_RED" } },
            } },
            { aliases = { "mistweaver", "mistweaver monk", "mw monk" }, targets = { { label = "Mana (Player Power Bar)", keys = { "general.powerColorOverrides.MANA" } } } },
            { aliases = { "windwalker", "windwalker monk", "ww monk" }, targets = {
                { label = "Energy (Player Power Bar)", keys = { "general.powerColorOverrides.ENERGY" } },
                { label = "Chi (Class Resources)", keys = { "general.classPowerColorOverrides.CHI" } },
            } },
        },
    },
    DRUID = {
        aliases = { "druid" },
        specs = {
            { aliases = { "balance", "balance druid", "boomkin" }, targets = { { label = "Astral Power (Player Power Bar and Balance resources)", keys = { "general.powerColorOverrides.LUNAR_POWER", "general.classPowerColorOverrides.ASTRAL_POWER" } } } },
            { aliases = { "feral", "feral druid" }, targets = {
                { label = "Energy (Player Power Bar)", keys = { "general.powerColorOverrides.ENERGY" } },
                { label = "Combo Points (Class Resources)", keys = { "general.classPowerColorOverrides.COMBO_POINTS" } },
            } },
            { aliases = { "guardian", "guardian druid", "bear druid" }, targets = { { label = "Rage (Player Power Bar)", keys = { "general.powerColorOverrides.RAGE" } } } },
            { aliases = { "restoration druid", "resto druid" }, targets = { { label = "Mana (Player Power Bar)", keys = { "general.powerColorOverrides.MANA" } } } },
        },
    },
    DEMONHUNTER = {
        aliases = { "demon hunter", "demonhunter", "dh" },
        specs = {
            { aliases = { "havoc", "havoc demon hunter", "havoc dh" }, targets = { { label = "Fury (Player Power Bar)", keys = { "general.powerColorOverrides.FURY" } } } },
            { aliases = { "vengeance", "vengeance demon hunter", "vengeance dh" }, targets = {
                { label = "Fury (Player Power Bar)", keys = { "general.powerColorOverrides.FURY" } },
                { label = "Soul Fragments (Class Resources)", keys = { "general.classPowerColorOverrides.SOUL_FRAGMENTS_VENG" } },
            } },
            { aliases = { "devourer", "devourer demon hunter", "devourer dh" }, targets = {
                { label = "Fury (Player Power Bar)", keys = { "general.powerColorOverrides.FURY" } },
                { label = "Soul Fragments (Class Resources)", keys = { "general.classPowerColorOverrides.SOUL_FRAGMENTS" } },
            } },
        },
    },
    EVOKER = {
        aliases = { "evoker" },
        specs = {
            { aliases = { "devastation", "devastation evoker", "dev evoker" }, targets = {
                { label = "Mana (Player Power Bar)", keys = { "general.powerColorOverrides.MANA" } },
                { label = "Essence (Class Resources)", keys = { "general.classPowerColorOverrides.ESSENCE" } },
            } },
            { aliases = { "preservation", "preservation evoker", "pres evoker" }, targets = {
                { label = "Mana (Player Power Bar)", keys = { "general.powerColorOverrides.MANA" } },
                { label = "Essence (Class Resources)", keys = { "general.classPowerColorOverrides.ESSENCE" } },
            } },
            { aliases = { "augmentation", "augmentation evoker", "aug evoker" }, targets = {
                { label = "Essence (Player Power Bar)", keys = { "general.powerColorOverrides.ESSENCE" } },
                { label = "Ebon Might (Class Resources)", keys = { "general.classPowerColorOverrides.EBON_MIGHT" } },
                { label = "Mana (Alternative Mana Bar)", keys = { "general.powerColorOverrides.MANA" } },
            } },
        },
    },
}

local function SpecResourcePhrase(text)
    return ContainsAny(text, { "resource", "resources", "class resource", "class resources", "power resource", "power resources" })
end

local function CurrentClassAndSpec()
    local classToken, specName
    if type(_G.UnitClass) == "function" then
        local _, token = _G.UnitClass("player")
        classToken = token
    end
    if type(_G.GetSpecialization) == "function" and type(_G.GetSpecializationInfo) == "function" then
        local index = _G.GetSpecialization()
        if index then
            local _, name = _G.GetSpecializationInfo(index)
            specName = name and tostring(name):lower() or nil
        end
    end
    return classToken, specName
end

local function SpecResourceRouteForText(text)
    local currentClass, currentSpec = CurrentClassAndSpec()
    local wantsCurrent = ContainsAny(text, { "my resource", "my resources", "my class resource", "my class resources" })
    local classToken
    if wantsCurrent and SPEC_RESOURCE_COLOR_ROUTES[currentClass] then classToken = currentClass end
    if not classToken then
        local bestLength = 0
        for token, route in pairs(SPEC_RESOURCE_COLOR_ROUTES) do
            for i = 1, #(route.aliases or {}) do
                local alias = route.aliases[i]
                if HasPhrase(text, alias) and #Compact(alias) > bestLength then
                    classToken, bestLength = token, #Compact(alias)
                end
            end
        end
    end
    if not classToken then
        local bestLength = 0
        for token, route in pairs(SPEC_RESOURCE_COLOR_ROUTES) do
            for i = 1, #(route.specs or {}) do
                local aliases = route.specs[i].aliases or {}
                for j = 1, #aliases do
                    local alias = aliases[j]
                    if HasPhrase(text, alias) and #Compact(alias) > bestLength then
                        classToken, bestLength = token, #Compact(alias)
                    end
                end
            end
        end
    end
    local route = classToken and SPEC_RESOURCE_COLOR_ROUTES[classToken] or nil
    if not route then return nil end

    local selectedSpec, selectedSpecLength
    for i = 1, #(route.specs or {}) do
        local spec = route.specs[i]
        for j = 1, #(spec.aliases or {}) do
            local alias = spec.aliases[j]
            local length = #Compact(alias)
            if HasPhrase(text, alias) and (not selectedSpecLength or length > selectedSpecLength) then
                selectedSpec, selectedSpecLength = spec, length
            end
        end
    end
    if not selectedSpec and wantsCurrent and currentSpec then
        for i = 1, #(route.specs or {}) do
            local spec = route.specs[i]
            if ContainsAny(currentSpec, spec.aliases) then selectedSpec = spec break end
        end
    end

    local targets, seen = {}, {}
    local function AddTargets(list)
        for i = 1, #(list or {}) do
            local target = list[i]
            local signature = table.concat(target.keys or {}, "|")
            if signature ~= "" and not seen[signature] then seen[signature] = true; targets[#targets + 1] = target end
        end
    end
    if selectedSpec then AddTargets(selectedSpec.targets or route.targets) else
        AddTargets(route.targets)
        for i = 1, #(route.specs or {}) do AddTargets(route.specs[i].targets) end
    end
    return classToken, selectedSpec, targets
end

local function ChangesForResourceTarget(target, r, g, b, label)
    local changes = {}
    for i = 1, #(target.keys or {}) do
        local setting = Registry and Registry:GetSetting(target.keys[i])
        if setting then changes[#changes + 1] = { setting = setting, value = { r = r, g = g, b = b, label = label } } end
    end
    return changes
end

function A._ParseSpecResourceColorShortcut(text, raw)
    if not SpecResourcePhrase(text) then return nil end
    local r, g, b, colorLabel = ExtractColor(raw, text)
    if not r and not ContainsAny(text, { "color", "colour", "recolor", "recolour" }) then return nil end
    if ContainsAny(text, {
        "combo point", "combo points", "holy power", "soul shard", "soul shards", "chi", "arcane charge", "arcane charges",
        "rune", "runes", "essence", "essences", "soul fragment", "soul fragments", "maelstrom weapon", "whirlwind",
        "tip of the spear", "icicle", "icicles", "ebon might", "stagger", "insanity", "astral power",
    }) or ContainsAny(text, { "rage power", "energy power", "mana power", "focus power", "runic power", "fury power", "maelstrom power" }) then
        return nil
    end
    local classToken, selectedSpec, targets = SpecResourceRouteForText(text)
    if not classToken or #targets == 0 then return nil end
    local routeLabel = selectedSpec and tostring((selectedSpec.aliases or {})[1] or classToken) or tostring(classToken)
    if not r then
        local lines = { "Which " .. routeLabel .. " resource color do you want to change?" }
        for i = 1, #targets do lines[#lines + 1] = tostring(i) .. ". " .. tostring(targets[i].label) end
        if #targets > 1 then lines[#lines + 1] = tostring(#targets + 1) .. ". All listed resources" end
        lines[#lines + 1] = "Name the target and color, for example: set " .. tostring(targets[1].label):lower() .. " to cyan."
        return { kind = "answer", status = "info", result = "info", text = table.concat(lines, "\n"), summary = "Offers spec-aware resource color targets." }
    end

    local applyAll = #targets == 1 or ContainsAny(text, { "all resources", "both resources", "every resource", "all class resources", "resources" })
    if applyAll then
        local changes = {}
        for i = 1, #targets do
            local targetChanges = ChangesForResourceTarget(targets[i], r, g, b, colorLabel)
            for j = 1, #targetChanges do changes[#changes + 1] = targetChanges[j] end
        end
        if #changes == 0 then return nil end
        return { kind = "changes", changes = changes, bulkSafe = #changes > 1, label = routeLabel .. " Resource Colors", summary = "Changes every requested spec-aware Player Power Bar and Class Resource color target." }
    end

    local choices = {}
    for i = 1, #targets do
        local targetChanges = ChangesForResourceTarget(targets[i], r, g, b, colorLabel)
        if #targetChanges > 0 then choices[#choices + 1] = { changes = targetChanges, bulkSafe = #targetChanges > 1, label = targets[i].label, summary = "Changes " .. targets[i].label .. "." } end
    end
    local allChanges = {}
    for i = 1, #choices do for j = 1, #(choices[i].changes or {}) do allChanges[#allChanges + 1] = choices[i].changes[j] end end
    if #allChanges > 1 then choices[#choices + 1] = { changes = allChanges, bulkSafe = true, label = "All listed resources", summary = "Changes every listed resource color for this class/spec." } end
    if #choices == 1 then return { kind = "changes", changes = choices[1].changes, bulkSafe = choices[1].bulkSafe, label = choices[1].label, summary = choices[1].summary } end
    return { kind = "ambiguous", choices = choices, label = "Which " .. routeLabel .. " resource?", summary = "Separates Player Power Bar and Class Resource color targets." }
end

function A._ParsePowerColorShortcut(text, raw)
    local token = PowerColorTokenForText(text)
    if not token then return nil end
    if ContainsAny(text, FeaturesPhrases[193]) then return nil end
    if ContainsAny(text, FeaturesPhrases[194]) then return nil end
    if not ContainsAny(text, FeaturesPhrases[195]) then return nil end

    if ContainsAny(text, FeaturesPhrases[196]) then
        local action = Registry and Registry:GetAction("reset_power_color_token")
        return action and {
            kind = "action",
            action = action,
            args = { token = token },
            label = "Reset power bar color",
            summary = "Resets a single Power Bar color.",
        } or nil
    end

    local r, g, b, label = ExtractColor(raw, text)
    if not r then return nil end
    local setting = Registry and Registry:GetSetting("general.powerColorOverrides." .. token)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = { r = r, g = g, b = b, label = label } } },
        label = "Power Bar Color",
        summary = "Changes a global Power Bar color token.",
    }
end

local function ParseColorAction(text)
    if not ContainsAny(text, FeaturesPhrases[197]) then return nil end
    if not ContainsAny(text, FeaturesPhrases[198]) then return nil end
    local slotResource = ClassPowerSlotResourceForText and ClassPowerSlotResourceForText(text) or nil
    -- Combo Points have a dedicated no-argument reset action. Resolve that
    -- phrase before the generic per-resource slot reset, which can also infer
    -- COMBO_POINTS and would otherwise shadow this stable action key.
    if ContainsAny(text, FeaturesPhrases[199]) then
        local action = Registry and Registry:GetAction("reset_class_power_combo_slot_colors")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Reset combo point slot colors",
            summary = "Resets the custom Class Resource combo point slot colors.",
        } or nil
    end
    if slotResource and ContainsAny(text, CLASS_POWER_SLOT_RESET_TERMS) then
        local action = Registry and Registry:GetAction("reset_class_power_slot_colors")
        return action and {
            kind = "action",
            action = action,
            args = { resourceToken = slotResource.token },
            label = "Reset " .. tostring(slotResource.label) .. " slot colors",
            summary = "Resets individual " .. tostring(slotResource.className) .. " " .. tostring(slotResource.label) .. " slot colors.",
        } or nil
    end
    local powerToken = PowerColorTokenForText(text)
    if powerToken
        and ContainsAny(text, FeaturesPhrases[200])
        and not ContainsAny(text, FeaturesPhrases[201])
    then
        local action = Registry and Registry:GetAction("reset_power_color_token")
        return action and {
            kind = "action",
            action = action,
            args = { token = powerToken },
            label = "Reset power bar color",
            summary = "Resets a single Power Bar color.",
        } or nil
    end
    local cpToken = ClassPowerColorTokenForText(text)
    if cpToken and ContainsAny(text, FeaturesPhrases[202]) then
        local action = Registry and Registry:GetAction("reset_class_power_color_token")
        return action and {
            kind = "action",
            action = action,
            args = { token = cpToken, background = ContainsAny(text, FeaturesPhrases[203]) },
            label = "Reset class resource color",
            summary = "Resets a single Class Resource foreground or background color.",
        } or nil
    end
    if ContainsAny(text, FeaturesPhrases[204]) then
        return BuildColorResetAction("reset_castbar_colors", "Reset cast bar colors", "Resets cast bar colors through the existing Colors page state.")
    end
    if ContainsAny(text, FeaturesPhrases[205]) then
        return BuildColorResetAction("reset_npc_type_colors", "Reset NPC type colors", "Resets NPC type colors.")
    end
    if ContainsAny(text, FeaturesPhrases[206]) then
        return BuildColorResetAction("reset_health_gradient_colors", "Reset health gradient colors", "Resets the low, mid, and high Health Gradient color stops.")
    end
    if ContainsAny(text, FeaturesPhrases[207]) then
        return BuildColorResetAction("reset_unitframe_colors", "Reset unit frame colors", "Resets unit frame NPC reaction colors.")
    end
    if ContainsAny(text, FeaturesPhrases[208]) then
        return BuildColorResetAction("reset_class_colors", "Reset class bar colors", "Resets class bar color overrides.")
    end
    if ContainsAny(text, FeaturesPhrases[209]) then
        return BuildColorResetAction("reset_bar_background_color", "Reset bar background tint", "Resets the global bar background tint.")
    end
    if ContainsAny(text, FeaturesPhrases[210]) then
        return BuildColorResetAction("reset_bar_colors", "Reset bar colors", "Resets bar overlay and border colors.")
    end
    if ContainsAny(text, FeaturesPhrases[212]) then
        return BuildColorResetAction("reset_gameplay_colors", "Reset gameplay colors", "Resets Gameplay color options.")
    end
    if ContainsAny(text, FeaturesPhrases[213]) then
        return BuildColorResetAction("reset_aura_colors", "Reset aura colors", "Resets Aura color options.")
    end
    if ContainsAny(text, FeaturesPhrases[214]) then
        return BuildColorResetAction("reset_portrait_colors", "Reset portrait colors", "Resets portrait color options.")
    end
    if ContainsAny(text, FeaturesPhrases[215]) then
        return BuildColorResetAction("reset_resource_colors", "Reset resource colors", "Resets power and class-resource color overrides.")
    end
    return nil
end

local function ParseDiagnostic(text)
    local norm = Normalize(text)
    local exactDashboardSetupCheck = norm == "check dashboard"
        or norm == "check setup"
        or norm == "diagnose setup"
        or norm == "diagnostic setup"
        or norm == "troubleshoot setup"
    if exactDashboardSetupCheck then
        local action = Registry and Registry:GetAction("diagnose_dashboard_setup")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Check Dashboard setup",
            summary = "Checks the Assistant state, Dashboard panels, and menu navigation.",
        } or nil
    end

    local directChangeIntent = ContainsAny(text, FeaturesPhrases[216])
    local explicitTroubleIntent = ContainsAny(text, FeaturesPhrases[217])
    if directChangeIntent and not explicitTroubleIntent then return nil end
    if not ContainsAny(text, FeaturesPhrases[218]) then return nil end
    if ContainsAny(text, FeaturesPhrases[219]) and ContainsAny(text, FeaturesPhrases[220]) then
        return nil
    end
    local gameplayFeature
    if ContainsAny(text, FeaturesPhrases[221]) then
        gameplayFeature = "combatTimer"
    elseif ContainsAny(text, FeaturesPhrases[222]) then
        gameplayFeature = "combatState"
    elseif ContainsAny(text, FeaturesPhrases[223]) then
        gameplayFeature = "playerTotems"
    elseif ContainsAny(text, FeaturesPhrases[224]) then
        gameplayFeature = "combatCrosshair"
    elseif ContainsAny(text, FeaturesPhrases[225]) then
        gameplayFeature = "all"
    elseif M and M.activeKey == "gameplay" and ContainsAny(text, FeaturesPhrases[226]) then
        gameplayFeature = "all"
    end
    if gameplayFeature then
        local action = Registry and Registry:GetAction("diagnose_gameplay_helpers")
        return action and {
            kind = "action",
            action = action,
            args = { feature = gameplayFeature },
            label = "Check " .. (gameplayFeature == "all" and "Gameplay features" or "Gameplay feature"),
            summary = "Checks Gameplay options and suggests clear next steps.",
        } or nil
    end
    if ContainsAny(text, FeaturesPhrases[227]) then
        local action = Registry and Registry:GetAction("diagnose_profile_status")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Check Profiles",
            summary = "Checks the active profile, saved profiles, specialization links, and prepared profile values.",
        } or nil
    end
    if ContainsAny(text, CLASS_POWER_TERMS)
        or ContainsAny(text, FeaturesPhrases[228])
    then
        local action = Registry and Registry:GetAction("diagnose_class_power_status")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Check Class Resources",
            summary = "Checks Class Resource visibility, sizing, opacity, width mode, and hide rules.",
        } or nil
    end
    if ContainsAny(text, FeaturesPhrases[229]) then
        local groups = DetectGroups(text)
        local units = DetectUnits(text)
        local scope = groups[1] or units[1] or "target"
        if scope == "targettarget" or scope == "focustarget" or scope == "pet" then scope = "target" end
        local lane
        if ContainsAny(text, FeaturesPhrases[230]) then lane = "debuff" elseif ContainsAny(text, FeaturesPhrases[231]) then lane = "buff" end
        local action = Registry and Registry:GetAction("diagnose_aura_visibility")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, lane = lane },
            label = "Check Auras",
            summary = "Checks Aura visibility options and suggests clear next steps.",
        } or nil
    end
    if ContainsAny(text, FeaturesPhrases[232]) then
        local units = DetectUnits(text)
        local unit = units[1] or "target"
        local action = Registry and Registry:GetAction("diagnose_castbar_visibility")
        return action and {
            kind = "action",
            action = action,
            args = { unit = unit },
            label = "Check " .. UnitDisplayLabel(unit) .. " cast bar",
            summary = "Checks current cast bar options and suggests the next step.",
        } or nil
    end
    if ContainsAny(text, FeaturesPhrases[233]) then
        local units = DetectUnits(text)
        if #units == 0 then
            return {
                kind = "answer",
                status = "info",
                text = "Which unit-frame power bar do you want me to check? For example: 'why is target detached power bar gone' or 'check player power bar'.",
                summary = "Asks which unit's detached Power Bar to check.",
            }
        end
    end
    local groups = DetectGroups(text)
    if ContainsAny(text, FeaturesPhrases[234])
        and ContainsAny(text, FeaturesPhrases[235])
        and (#groups > 0 or ContainsAny(text, FeaturesPhrases[236]))
    then
        local action = Registry and Registry:GetAction("assistant_scope_help")
        return action and {
            kind = "action",
            action = action,
            args = { page = "gf_indicators", frameType = "group" },
            label = "Group Status & Indicators help",
            summary = "Shows Group Indicator help instead of running a visibility diagnosis.",
        } or nil
    end
    if #groups > 0 or ContainsAny(text, FeaturesPhrases[237]) then
        local scope = groups[1] or "party"
        if scope == "mythicraid" then scope = "mythicraid" end
        local action = Registry and Registry:GetAction("diagnose_group_visibility")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope },
            label = "Check " .. GroupDisplayLabel(scope) .. " group frames",
            summary = "Checks current group-frame options and suggests the next step.",
        } or nil
    end
    local units = DetectUnits(text)
    if #units > 0 then
        local unit = units[1]
        local action = Registry and Registry:GetAction("diagnose_unit_visibility")
        return action and {
            kind = "action",
            action = action,
            args = { unit = unit },
            label = "Check " .. UnitDisplayLabel(unit) .. " frame",
            summary = "Checks current unit-frame options and suggests the next step.",
        } or nil
    end
    if ContainsAny(text, FeaturesPhrases[238])
        or text == "diagnose setup"
        or text == "diagnostic setup"
        or text == "troubleshoot setup"
        or text == "diagnostik setup"
        or text == "pruefe setup"
        or text == "setup pruefen"
    then
        local action = Registry and Registry:GetAction("diagnose_dashboard_setup")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Check Dashboard setup",
            summary = "Checks the Assistant state, Dashboard panels, and menu navigation.",
        } or nil
    end
    return nil
end

local function HasScopedHelpIntent(text, page)
    if ContainsAny(text, FeaturesPhrases[239]) then
        return false
    end
    if ContainsAny(text, FeaturesPhrases[240]) then
        return true
    end
    if not page and not ContainsAny(text, FeaturesPhrases[241]) then return false end
    if ContainsAny(text, FeaturesPhrases[242]) then
        return true
    end
    if page and ContainsAny(text, FeaturesPhrases[243])
        and ContainsAny(text, FeaturesPhrases[244])
    then
        return true
    end
    return page == "profiles" and ContainsAny(text, FeaturesPhrases[245])
end

local function ParseScopedHelp(text)
    local action = Registry and Registry:GetAction("assistant_scope_help")
    if not action then return nil end
    local page, label = PageForText(text)
    local editModeHelp = ContainsAny(text, FeaturesPhrases[246])
        and ContainsAny(text, FeaturesPhrases[247])
    if not HasScopedHelpIntent(text, page) and not editModeHelp then return nil end
    if not page and ContainsAny(text, FeaturesPhrases[248]) then
        page = M and M.activeKey
        label = "current page"
    end
    if editModeHelp then
        page = "home"
        label = "Edit Mode"
    end
    local units = DetectUnits(text)
    local groups = DetectGroups(text)
    local unit = units[1] or UnitForPage(page)
    local group = groups[1]
    local frameType = FrameTypeForPage(page)
    if editModeHelp then frameType = "editMode" end
    if group then
        frameType = ContainsAny(text, FeaturesPhrases[249]) and "groupAura" or "group"
        label = GroupDisplayLabel(group)
    elseif unit then
        frameType = ContainsAny(text, FeaturesPhrases[250]) and "castbar" or "unitframe"
        label = UnitDisplayLabel(unit)
    elseif not frameType then
        frameType = DetectFrameType(text, {})
    end
    return {
        kind = "action",
        action = action,
        args = { page = page, label = label, frameType = frameType, unit = unit, group = group },
        label = "Show target-specific Assistant help",
        summary = "Shows what the Assistant can do for the requested area.",
    }
end

local function SupportLinkForText(text)
    if ContainsAny(text, FeaturesPhrases[251]) then return "discord" end
    if ContainsAny(text, FeaturesPhrases[252]) then return "patreon" end
    if ContainsAny(text, FeaturesPhrases[253]) then return "paypal" end
    if ContainsAny(text, FeaturesPhrases[254]) then return "kofi" end
    if ContainsAny(text, FeaturesPhrases[255]) then return "github" end
    return nil
end

local EDIT_MODE_CONTEXT_TERMS = {
    "edit mode", "editmode", "msuf edit mode", "bearbeitungsmodus", "bearbeitungs modus",
    "editmodus", "frame edit mode", "rahmen bearbeiten", "rahmen verschieben",
}

local function HasEditModeContext(text)
    return ContainsAny(text, EDIT_MODE_CONTEXT_TERMS)
end

local function EditModeAction(actionKey, args, label, summary)
    local action = Registry and Registry:GetAction(actionKey)
    return action and {
        kind = "action",
        action = action,
        args = args or {},
        label = label,
        summary = summary or "Changes a real MSUF Edit Mode HUD option.",
    } or nil
end

local function IsBossFramePreviewText(text)
    return ContainsAny(text, FeaturesPhrases[256]) and not ContainsAny(text, FeaturesPhrases[257])
end

local function ParseBossFramePreviewShortcut(text)
    if not IsBossFramePreviewText(text) then return nil end
    return EditModeAction("assistant.action.editMode.bossPreview", { value = DetectBoolean(text) }, "Set Boss Frames Preview", "Shows or hides the Boss Frames unit preview outside encounters.")
end

local function GroupPreviewScopeForText(text)
    if ContainsAny(text, FeaturesPhrases[258]) then
        return "mythicraid"
    end
    if ContainsAny(text, FeaturesPhrases[259]) then
        return "raid"
    end
    if ContainsAny(text, FeaturesPhrases[260]) then
        return "party"
    end
    local groups = DetectGroups(text)
    return groups and groups[1] or nil
end

local function HasEditModeHUDControlIntent(text)
    if not HasEditModeContext(text) then return false end
    return ContainsAny(text, FeaturesPhrases[261])
end

local function ParseEditModeHUDControl(text, raw)
    local hasEditContext = HasEditModeContext(text)
    local previewWord = ContainsAny(text, FeaturesPhrases[262])
    local hasExplicitAuraPreview = ContainsAny(text, FeaturesPhrases[263]) and (hasEditContext or previewWord or ContainsAny(text, FeaturesPhrases[264]))
    local hasAuraPreview = hasExplicitAuraPreview
        or (hasEditContext and ContainsAny(text, FeaturesPhrases[265]) and (previewWord or DetectBoolean(text) ~= nil or ContainsAny(text, FeaturesPhrases[266])))
    local hasGroupPreview = ContainsAny(text, FeaturesPhrases[267]) or (hasEditContext and previewWord and ContainsAny(text, FeaturesPhrases[268]))
        or (hasEditContext and ContainsAny(text, FeaturesPhrases[269]) and (DetectBoolean(text) ~= nil or ContainsAny(text, FeaturesPhrases[270])))
    local hasBossPreview = previewWord and IsBossFramePreviewText(text)
    local hasUnitPreview = ContainsAny(text, FeaturesPhrases[271]) or (hasEditContext and previewWord and not hasAuraPreview and not hasGroupPreview)
    local hasSnap = ContainsAny(text, FeaturesPhrases[272])
    local hasGrid = (hasEditContext and ContainsAny(text, FeaturesPhrases[273])) or ContainsAny(text, FeaturesPhrases[274])
    local hasGridStep = hasGrid and FirstNumber(text) ~= nil and ContainsAny(text, FeaturesPhrases[275])
    local hasBackgroundOpacity = (hasEditContext and ContainsAny(text, FeaturesPhrases[276])) or ContainsAny(text, FeaturesPhrases[277])
    local hasCDM = ContainsAny(text, FeaturesPhrases[278])
    local hasAnchorPicker = ContainsAny(text, FeaturesPhrases[279]) and not ContainsAny(text, FeaturesPhrases[280])
        and (hasEditContext or ContainsAny(text, FeaturesPhrases[281]))
    local hasResetPosition = hasEditContext and ContainsAny(text, FeaturesPhrases[282])
        and ContainsAny(text, FeaturesPhrases[283])
    local hasUndo = hasEditContext and ContainsAny(text, FeaturesPhrases[284])
    local hasRedo = hasEditContext and ContainsAny(text, FeaturesPhrases[285])

    if hasAnchorPicker then
        return EditModeAction("assistant.action.editMode.anchorPicker", {}, "Open Edit Mode Anchor picker")
    end
    if hasUndo then
        return EditModeAction("assistant.action.editMode.undo", {}, "Undo Edit Mode position change")
    end
    if hasRedo then
        return EditModeAction("assistant.action.editMode.redo", {}, "Redo Edit Mode position change")
    end
    if hasResetPosition then
        return EditModeAction("assistant.action.editMode.resetPosition", {}, "Reset selected Edit Mode position")
    end

    local value = DetectBoolean(text)
    if hasAuraPreview then
        return EditModeAction("assistant.action.editMode.auras", { value = value }, "Set Edit Mode Auras Preview")
    end
    if hasGroupPreview then
        return EditModeAction("assistant.action.editMode.groupPreview", { value = value, scope = GroupPreviewScopeForText(text) }, "Set Group Frames Preview")
    end
    if hasBossPreview then
        return EditModeAction("assistant.action.editMode.bossPreview", { value = value }, "Set Boss Frames Preview")
    end
    if hasUnitPreview then
        return EditModeAction("assistant.action.editMode.preview", { value = value }, "Set Edit Mode Preview")
    end
    if hasSnap and (hasEditContext or ContainsAny(text, FeaturesPhrases[286])) then
        return EditModeAction("assistant.action.editMode.snap", { value = value }, "Set Edit Mode Snap")
    end
    if hasGridStep then
        return EditModeAction("assistant.action.editMode.gridStep", { value = FirstNumber(text) }, "Set Edit Mode Grid spacing")
    end
    if hasGrid and not hasSnap then
        return EditModeAction("assistant.action.editMode.grid", { value = value }, "Set Edit Mode Grid")
    end
    if hasBackgroundOpacity then
        local number = FirstNumber(text)
        if number == nil and value ~= nil then number = value and 85 or 5 end
        local rawText = tostring(raw or text or ""):lower()
        local explicitPercent = rawText:find("%%") ~= nil
            or rawText:find("%f[%a]percent%f[%A]") ~= nil
            or rawText:find("%f[%a]prozent%f[%A]") ~= nil
        if number ~= nil and (number > 1 or explicitPercent) then number = number / 100 end
        return EditModeAction("assistant.action.editMode.backgroundOpacity", { value = number }, "Set Edit Mode Background opacity")
    end
    if hasCDM and hasEditContext then
        return EditModeAction("assistant.action.editMode.cdm", { value = value }, "Set Edit Mode CDM Anchor")
    end
    return nil
end

local function ParseSupportWorkflow(text, raw)
    if ContainsAny(text, FeaturesPhrases[287]) then
        local action = Registry and Registry:GetAction("assistant_nomatch_clear")
        return action and {
            kind = "action",
            action = action,
            args = {},
            confirmRequired = true,
            label = "Clear Assistant learning phrases",
            summary = "Clears stored phrases that still need better Assistant answers.",
        } or nil
    end

    local function NoMatchOwnerFilterForText(value)
        if ContainsAny(value, FeaturesPhrases[288]) then return nil end
        if ContainsAny(value, FeaturesPhrases[289]) then return "aura-action/backend" end
        if ContainsAny(value, FeaturesPhrases[290]) then return "aura-registry/backend" end
        if ContainsAny(value, FeaturesPhrases[291]) then return "anchor-intent" end
        if ContainsAny(value, FeaturesPhrases[292]) then return "registry-alias" end
        if ContainsAny(value, FeaturesPhrases[293]) then return "media-alias" end
        if ContainsAny(value, FeaturesPhrases[294]) then return "knowledge/help" end
        if ContainsAny(value, FeaturesPhrases[295]) then return "action-parser" end
        if ContainsAny(value, FeaturesPhrases[296]) then return "parser-or-help" end
        return nil
    end

    local function NoMatchResolutionFilterForText(value)
        if ContainsAny(value, FeaturesPhrases[297]) then return nil end
        if ContainsAny(value, FeaturesPhrases[298]) then return "unresolved" end
        if ContainsAny(value, FeaturesPhrases[299]) then return "needs-clarification" end
        if ContainsAny(value, FeaturesPhrases[300]) then return "resolved" end
        return nil
    end

    local function NoMatchPriorityFilterForText(value)
        if ContainsAny(value, FeaturesPhrases[301]) then return nil end
        if ContainsAny(value, FeaturesPhrases[302]) then return "high" end
        if ContainsAny(value, FeaturesPhrases[303]) then return "medium" end
        if ContainsAny(value, FeaturesPhrases[304]) then return "low" end
        return nil
    end

    local function NoMatchTagFilterForText(value)
        if ContainsAny(value, FeaturesPhrases[305]) then return nil end
        if ContainsAny(value, FeaturesPhrases[306]) then return "uncategorized" end
        if ContainsAny(value, FeaturesPhrases[307]) then return "geometry" end
        if ContainsAny(value, FeaturesPhrases[308]) then return "media" end
        if ContainsAny(value, FeaturesPhrases[309]) then return "setting" end
        if ContainsAny(value, FeaturesPhrases[310]) then return "scope" end
        if ContainsAny(value, FeaturesPhrases[311]) then return "aura" end
        if ContainsAny(value, FeaturesPhrases[312]) then return "anchor" end
        if ContainsAny(value, FeaturesPhrases[313]) then return "action" end
        if ContainsAny(value, FeaturesPhrases[314]) then return "knowledge" end
        return nil
    end

    if ContainsAny(text, FeaturesPhrases[315]) then
        local action = Registry and Registry:GetAction("assistant_nomatch_worklist")
        local owner = NoMatchOwnerFilterForText(text)
        local resolution = NoMatchResolutionFilterForText(text)
        local priority = NoMatchPriorityFilterForText(text)
        local tag = NoMatchTagFilterForText(text)
        local args = {}
        if owner then args.owner = owner end
        if resolution then args.resolution = resolution end
        if priority then args.priority = priority end
        if tag then args.tag = tag end
        return action and {
            kind = "action",
            action = action,
            args = args,
            label = "Show Assistant learning list",
            summary = "Shows phrases that still need better Assistant answers.",
        } or nil
    end

    if ContainsAny(text, FeaturesPhrases[316]) then
        local action = Registry and Registry:GetAction("assistant_nomatch_telemetry")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show Assistant phrases to improve",
            summary = "Shows stored phrases that still need better Assistant answers.",
        } or nil
    end

    -- "msuf status" is a report request, but ContainsAny matches it anywhere:
    -- "set msuf status afk text offset x to 0" names the Status AFK Text Offset
    -- X control and was answered with the Assistant overview panel instead. A
    -- status report never carries a value, so a number or a "to <value>" tail
    -- means this is a setting request that merely contains the words.
    if ContainsAny(text, FeaturesPhrases[317])
        and not tostring(text or ""):find("%d")
        and not tostring(text or ""):lower():find("%sto%s")
    then
        local action = Registry and Registry:GetAction("assistant_status")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show MSUF status",
            summary = "Shows read-only MSUF and Assistant details.",
        } or nil
    end

    if text == "help" or text == "hilfe" or ContainsAny(text, FeaturesPhrases[318]) then
        local action = Registry and Registry:GetAction("assistant_help")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show Assistant help",
            summary = "Shows Assistant examples handled locally by MSUF.",
        } or nil
    end

    local editModeControl = ParseEditModeHUDControl(text, raw)
    if editModeControl then return editModeControl end

    if ContainsAny(text, FeaturesPhrases[319]) then
        local actionKey
        local label
        local args = {}
        if ContainsAny(text, FeaturesPhrases[320]) then
            actionKey = "assistant.diagnostic.editMode.status"
            label = "Show MSUF Edit Mode status"
            if ContainsAny(text, FeaturesPhrases[321]) then args.reason = "why_exit" end
        elseif ContainsAny(text, FeaturesPhrases[322]) then
            actionKey = "assistant.action.editMode.cancel"
            label = "Cancel MSUF Edit Mode"
        elseif ContainsAny(text, FeaturesPhrases[323]) then
            actionKey = "assistant.action.editMode.toggle"
            label = "Toggle MSUF Edit Mode"
        elseif ContainsAny(text, FeaturesPhrases[324]) then
            actionKey = "assistant.action.editMode.exit"
            label = "Exit MSUF Edit Mode"
        elseif not HasEditModeHUDControlIntent(text) then
            actionKey = "assistant.action.editMode.enter"
            label = "Enter MSUF Edit Mode"
        end
        if not actionKey then return nil end
        local action = Registry and Registry:GetAction(actionKey)
        return action and {
            kind = "action",
            action = action,
            args = args,
            confirmRequired = actionKey == "assistant.action.editMode.cancel",
            label = label,
            summary = "Starts, stops, or checks MSUF Edit Mode.",
        } or nil
    end

    if ContainsAny(text, FeaturesPhrases[327]) then
        local action = Registry and Registry:GetAction("open_recovery_tools")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Open recovery tools",
            summary = "Opens the Dashboard recovery area.",
        } or nil
    end

    if ContainsAny(text, FeaturesPhrases[328]) then
        local action = Registry and Registry:GetAction("open_dashboard_panel")
        return action and {
            kind = "action",
            action = action,
            args = { panel = "scaling" },
            label = "Open scaling tools",
            summary = "Opens the Dashboard scaling area.",
        } or nil
    end

    if ContainsAny(text, FeaturesPhrases[329]) then
        local action = Registry and Registry:GetAction("open_dashboard_panel")
        return action and {
            kind = "action",
            action = action,
            args = { panel = "changelog" },
            label = "Open changelog",
            summary = "Opens the Dashboard changelog.",
        } or nil
    end

    local link = SupportLinkForText(text)
    if link and ContainsAny(text, FeaturesPhrases[330]) then
        local action = Registry and Registry:GetAction("copy_support_link")
        return action and {
            kind = "action",
            action = action,
            args = { link = link },
            label = "Copy support link",
            summary = "Opens a copyable MSUF support link.",
        } or nil
    end

    if ContainsAny(text, FeaturesPhrases[331]) then
        local action = Registry and Registry:GetAction("support_links_summary")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show support links",
            summary = "Lists MSUF support links.",
        } or nil
    end
    return nil
end

local function GlobalScalePresetForText(text)
    if ContainsAny(text, FeaturesPhrases[332]) then return "1080p" end
    if ContainsAny(text, FeaturesPhrases[333]) then return "1440p" end
    if ContainsAny(text, FeaturesPhrases[334]) then return "4k" end
    if ContainsAny(text, FeaturesPhrases[335]) then return "pixel" end
    if ContainsAny(text, FeaturesPhrases[336]) then return "off" end
    if ContainsAny(text, FeaturesPhrases[337]) and ContainsAny(text, FeaturesPhrases[338]) then return "off" end
    return nil
end

local function ParsePresetWorkflow(text)
    if not ContainsAny(text, FeaturesPhrases[339]) then return nil end
    if not ContainsAny(text, FeaturesPhrases[340]) then return nil end
    local preset = GlobalScalePresetForText(text)
    if not preset then return nil end
    local action = Registry and Registry:GetAction("apply_global_scale_preset")
    return action and {
        kind = "action",
        action = action,
        args = { preset = preset },
        label = "Apply global UI scale preset",
        summary = "Applies one of the Dashboard global WoW UI scale presets.",
    } or nil
end

local function DashboardScaleTargetForText(text)
    if ContainsAny(text, FeaturesPhrases[341]) then return nil end
    if ContainsAny(text, FeaturesPhrases[342]) then
        return "general.slashMenuScale", "MSUF Menu Scale"
    end
    if ContainsAny(text, FeaturesPhrases[343]) then
        return "general.msufUiScale", "MSUF Frame Scale"
    end
    if ContainsAny(text, FeaturesPhrases[344]) then
        return "general.globalUiScale", "Global WoW UI Scale"
    end
    return nil
end

local function ParseDashboardScaleShortcut(text)
    local key, label = DashboardScaleTargetForText(text)
    if not key then return nil end
    if not ContainsAny(text, FeaturesPhrases[345]) then
        return nil
    end
    local setting = Registry and Registry:GetSetting(key)
    if not setting then return nil end
    local relativeDelta = RelativeNumberDeltaForText and RelativeNumberDeltaForText(setting, text, 5)
    local value
    if relativeDelta == nil then
        value = FirstNumber(text)
        if value ~= nil and setting.percent == true and value > 1 then value = value / 100 end
    end
    if value == nil and relativeDelta == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = label,
        summary = "Adjusts Dashboard scale.",
    }
end

local function ParseScopedOverrideReset(text)
    local font = ContainsAny(text, FeaturesPhrases[346])
    local bars = ContainsAny(text, FeaturesPhrases[347])
    if not font and not bars then return nil end
    local reset = ContainsAny(text, FeaturesPhrases[348])
    if not reset then return nil end
    local all = ContainsAny(text, FeaturesPhrases[349])
    local explicitOverride = ContainsAny(text, FeaturesPhrases[350])
    if not all and not explicitOverride then return nil end
    local scope = DetectGlobalScope(text)
    if not all and (not scope or scope == "shared") then return nil end
    local actionKey
    if font and not bars then
        actionKey = all and "reset_all_scoped_global_font_overrides" or "reset_scoped_global_font_override"
    elseif bars and not font then
        actionKey = all and "reset_all_scoped_global_bars_overrides" or "reset_scoped_global_bars_override"
    else
        return nil
    end
    local action = Registry and Registry:GetAction(actionKey)
    return action and {
        kind = "action",
        action = action,
        args = { scope = scope },
        confirmRequired = all == true,
        label = all and "Reset all section overrides" or "Reset section override",
        summary = "Enables the matching target-specific style override before applying the change.",
    } or nil
end

local function HasClassPowerPreviewResourceIntent(text)
    return ContainsAny(text, FeaturesPhrases[351])
end

local function ParseClassPowerPreviewResource(text)
    local setting = Registry and Registry:GetSetting("menu.classPowerPreviewResource")
    if not setting then return nil end
    local value = P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, text, text) or nil
    if value == nil then return nil end
    if not (HasClassPowerPreviewResourceIntent(text) or HasPhrase(text, "preview")) then return nil end
    return {
        kind = "changes",
        changes = {
            {
                setting = setting,
                value = value,
                valueLabel = DisplayValueLabel(setting, value),
            },
        },
        label = "Class resource preview",
        summary = "Selects the Class Resources preview without changing saved layout options.",
    }
end
A._ParseClassPowerPreviewResourceShortcut = ParseClassPowerPreviewResource

local function ParseClassPowerAction(text)
    text = tostring(text or "")
    if not (text:find("class", 1, true) or text:find("resource", 1, true)
        or text:find("power", 1, true) or text:find("combo", 1, true)
        or text:find("rune", 1, true) or text:find("pip", 1, true)
        or text:find("separator", 1, true)) then
        return nil
    end
    local previewResource = ParseClassPowerPreviewResource(text)
    if previewResource then return previewResource end

    if (HasClassPowerIntent(text) or ContainsAny(text, FeaturesPhrases[352]))
        and ContainsAny(text, FeaturesPhrases[353])
        and ContainsAny(text, FeaturesPhrases[354]) then
        local action = Registry and Registry:GetAction("class_power_preview_animate")
        local value = DetectBoolean(text)
        if ContainsAny(text, FeaturesPhrases[355]) then
            value = false
        elseif ContainsAny(text, FeaturesPhrases[356]) then
            value = true
        end
        if ContainsAny(text, FeaturesPhrases[357]) then value = nil end
        return action and {
            kind = "action",
            action = action,
            args = { value = value },
            label = "Animate class resource preview",
            summary = "Changes the Class Resources inline preview animation.",
        } or nil
    end
    if not ContainsAny(text, FeaturesPhrases[358]) then return nil end
    if not HasClassPowerIntent(text) then return nil end
    local action = Registry and Registry:GetAction("class_power_quick_setup")
    return action and {
        kind = "action",
        action = action,
        args = {},
        confirmRequired = true,
        label = "Quick setup Class Resources",
        summary = "Starts the Class Resources quick setup.",
    } or nil
end

local GAMEPLAY_ROOT_TOGGLES = {
    {
        key = "gameplay.enableCombatTimer",
        label = "Combat Timer",
        terms = { "combat timer", "kampf timer", "kampftimer" },
        details = { "anchor", "attach", "size", "groesse", "font", "text size", "lock", "locked", "sperren", "click through", "click-through", "durchklickbar", "x", "y", "offset", "move", "verschiebe", "color", "colors", "farbe", "farben" },
    },
    {
        key = "gameplay.enableCombatStateText",
        label = "Combat Enter/Leave Text",
        terms = { "combat state", "combat enter leave", "combat enter", "combat leave", "kampf text", "kampf status", "kampfstatus", "kampfanzeige" },
        -- "indicator"/"icon"/"symbol" belong to the per-unit Combat Indicator,
        -- whose name begins with the same two words; see the matching notTerms
        -- on the combatState entry in A._GameplayShortcutSpecs.
        details = { "indicator", "icon", "symbol", "size", "groesse", "font", "duration", "dauer", "lock", "locked", "sperren", "x", "y", "offset", "move", "verschiebe", "color", "colors", "farbe", "farben", "sync", "synchron" },
    },
    {
        key = "gameplay.enablePlayerTotems",
        label = "Blizzard Totem Frame",
        terms = { "totem frame", "totemframe", "blizzard totem", "statue frame", "totem", "totems", "totem rahmen", "statuen rahmen", "statue rahmen" },
        details = { "icon", "symbol", "size", "groesse", "x", "y", "offset", "anchor", "anker", "from", "to", "preview", "vorschau", "reset", "zuruecksetzen", "zurucksetzen", "layout", "move", "verschiebe" },
    },
    {
        key = "gameplay.enableCombatCrosshair",
        label = "Combat Crosshair",
        terms = { "combat crosshair", "crosshair", "fadenkreuz" },
        details = { "range", "reichweite", "reichweitenfarbe", "melee", "nahkampf", "color", "colors", "farbe", "farben", "farbe nach reichweite", "spell", "zauber", "size", "groesse", "thickness", "dicke", "staerke", "x", "y", "offset", "move", "verschiebe", "class", "klasse", "spec", "spezialisierung" },
    },
}

local function ParseGameplayRootToggle(text)
    local value = DetectBoolean(text)
    if value == nil then return nil end
    for i = 1, #GAMEPLAY_ROOT_TOGGLES do
        local item = GAMEPLAY_ROOT_TOGGLES[i]
        if ContainsAny(text, item.terms) and not ContainsAny(text, item.details) then
            local setting = Registry and Registry:GetSetting(item.key)
            return setting and {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = item.label,
                summary = "Toggles a Gameplay option.",
            } or nil
        end
    end
    return nil
end

local function ParseGameplayAction(text, raw)
    if ContainsAny(text, FeaturesPhrases[359]) and ContainsAny(text, FeaturesPhrases[360]) then
        local rawText = tostring(raw or "")
        local value
        if ContainsAny(text, FeaturesPhrases[361]) then
            value = "0"
        else
            value = rawText:match("([Ss][Pp][Ee][Ll][Ll]:%d+)") or rawText:match("#%s*(%d+)") or rawText:match("(%d%d+)")
            if not value then
                local patterns = {
                    "[Ss]et%s+[Cc]rosshair%s+[Ss]pell%s+[Tt]o%s+(.+)",
                    "[Ss]et%s+[Cc]rosshair%s+.+[Ss]pell%s+[Tt]o%s+(.+)",
                    "[Cc]hange%s+[Cc]rosshair%s+.+[Ss]pell%s+[Tt]o%s+(.+)",
                    "[Ss]et%s+[Mm]elee%s+[Rr]ange%s+[Ss]pell%s+[Tt]o%s+(.+)",
                    "[Ss]et%s+.+[Mm]elee%s+[Rr]ange%s+[Ss]pell%s+[Tt]o%s+(.+)",
                    "[Cc]hange%s+.+[Mm]elee%s+[Rr]ange%s+[Ss]pell%s+[Tt]o%s+(.+)",
                    "[Uu]se%s+(.+)%s+[Ff]or%s+.+[Cc]rosshair",
                    "[Uu]se%s+(.+)%s+[Ff]or%s+.+[Mm]elee%s+[Rr]ange",
                    "[Ss]etze%s+[Ff]adenkreuz%s+[Zz]auber%s+[Aa]uf%s+(.+)",
                    "[Ss]etze%s+.+[Ff]adenkreuz%s+.+[Zz]auber%s+[Aa]uf%s+(.+)",
                    "[Aa]endere%s+.+[Ff]adenkreuz%s+.+[Zz]auber%s+[Aa]uf%s+(.+)",
                    "[Ss]etze%s+[Nn]ahkampf%s+[Rr]eichweiten%s+[Zz]auber%s+[Aa]uf%s+(.+)",
                    "[Ss]etze%s+[Nn]ahkampf%s+[Zz]auber%s+[Aa]uf%s+(.+)",
                    "[Ff]adenkreuz%s+[Zz]auber%s+[Aa]uf%s+(.+)",
                    "[Nn]utze%s+(.+)%s+[Ff]uer%s+.+[Ff]adenkreuz",
                    "[Nn]utze%s+(.+)%s+[Ff]uer%s+.+[Nn]ahkampf%s+[Rr]eichweite",
                }
                for i = 1, #patterns do
                    value = rawText:match(patterns[i])
                    value = CleanProfileName(value)
                    if value then break end
                end
            end
        end
        if value then
            local action = Registry and Registry:GetAction("set_crosshair_melee_spell")
            return action and {
                kind = "action",
                action = action,
                args = { value = value },
                label = "Set Crosshair Melee Range Spell",
                summary = "Resolves a spell ID, spell link, or spell name for the Combat Crosshair range check.",
            } or nil
        end
    end
    if ContainsAny(text, FeaturesPhrases[362]) and ContainsAny(text, FeaturesPhrases[363]) then
        local action = Registry and Registry:GetAction("preview_player_totems")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Preview Totem Frame",
            summary = "Toggles the Totem Frame preview.",
        } or nil
    end
    if ContainsAny(text, FeaturesPhrases[364]) and ContainsAny(text, FeaturesPhrases[365]) then
        local action = Registry and Registry:GetAction("reset_player_totems_layout")
        return action and {
            kind = "action",
            action = action,
            args = {},
            confirmRequired = true,
            label = "Reset Totem Frame Layout",
            summary = "Restores the Totem Frame layout defaults.",
        } or nil
    end
    return nil
end

local function ParseGlobalBarsAction(text)
    local previewTerms = { "test", "preview", "vorschau" }
    local offTerms = { "off", "disable", "stop", "clear", "aus", "deaktiviere", "deaktivieren", "beende", "beenden" }

    if ContainsAny(text, FeaturesPhrases[366]) then
        local value
        if ContainsAny(text, FeaturesPhrases[367]) then value = "Curse"
        elseif ContainsAny(text, FeaturesPhrases[368]) then value = "Disease"
        elseif ContainsAny(text, FeaturesPhrases[369]) then value = "Poison"
        elseif ContainsAny(text, FeaturesPhrases[370]) then value = "Bleed"
        elseif ContainsAny(text, FeaturesPhrases[371]) then value = "Magic" end
        local action = Registry and Registry:GetAction("set_dispel_border_test_type")
        return action and {
            kind = "action",
            action = action,
            args = { value = value or "Magic" },
            label = "Set dispel border test type",
            summary = "Changes the transient dispel border preview type.",
        } or nil
    end
    if ContainsAny(text, previewTerms) and ContainsAny(text, FeaturesPhrases[372]) then
        local action = Registry and Registry:GetAction("toggle_absorb_bar_test")
        return action and {
            kind = "action",
            action = action,
            args = { value = not ContainsAny(text, offTerms) },
            label = "Toggle absorb bar test",
            summary = "Toggles the absorb prediction bar test display.",
        } or nil
    end
    if ContainsAny(text, offTerms) and ContainsAny(text, FeaturesPhrases[373]) then
        local action = Registry and Registry:GetAction("toggle_absorb_bar_test")
        return action and {
            kind = "action",
            action = action,
            args = { value = false },
            label = "Disable absorb bar test",
            summary = "Turns off the absorb prediction bar test display.",
        } or nil
    end
    if ContainsAny(text, previewTerms) and ContainsAny(text, FeaturesPhrases[374]) then
        local action = Registry and Registry:GetAction("toggle_highlight_border_test")
        return action and { kind = "action", action = action, args = { kind = "aggro", value = not ContainsAny(text, offTerms) }, label = "Test aggro border", summary = "Toggles the aggro border test." } or nil
    end
    if ContainsAny(text, previewTerms) and ContainsAny(text, FeaturesPhrases[375]) then
        local action = Registry and Registry:GetAction("toggle_highlight_border_test")
        return action and { kind = "action", action = action, args = { kind = "dispel", value = not ContainsAny(text, offTerms) }, label = "Test dispel border", summary = "Toggles the dispel border test." } or nil
    end
    if ContainsAny(text, previewTerms) and ContainsAny(text, FeaturesPhrases[376]) then
        local action = Registry and Registry:GetAction("toggle_highlight_border_test")
        return action and { kind = "action", action = action, args = { kind = "purge", value = not ContainsAny(text, offTerms) }, label = "Test purge border", summary = "Toggles the purge border test." } or nil
    end
    if ContainsAny(text, previewTerms) and ContainsAny(text, FeaturesPhrases[377]) then
        local action = Registry and Registry:GetAction("toggle_highlight_border_test")
        return action and { kind = "action", action = action, args = { kind = "bossTarget", value = not ContainsAny(text, offTerms) }, label = "Test boss target border", summary = "Toggles the boss target border test." } or nil
    end
    return nil
end

local function ParseDarkModeBrightnessShortcut(text)
    if not ContainsAny(text, FeaturesPhrases[378]) then return nil end
    if not ContainsAny(text, FeaturesPhrases[379]) then
        return nil
    end
    local setting = Registry and Registry:GetSetting("general.darkBarGray")
    if not setting then return nil end

    local value
    local relativeDelta
    local amount = FirstNumber(text)
    local relativeIntent = ContainsAny(text, FeaturesPhrases[380])
    local exactIntent = amount ~= nil and not relativeIntent and (ContainsAny(text, FeaturesPhrases[381]) or text:find("%%", 1, true) ~= nil)
    if exactIntent then
        value = amount > 1 and (amount / 100) or amount
    elseif ContainsAny(text, FeaturesPhrases[382]) then
        value = 0.01
    elseif ContainsAny(text, FeaturesPhrases[383]) then
        local fallback = ContainsAny(text, FeaturesPhrases[384]) and 0.03 or 0.08
        relativeDelta = amount and (amount > 1 and amount / 100 or amount) or fallback
    elseif ContainsAny(text, FeaturesPhrases[385]) then
        local fallback = ContainsAny(text, FeaturesPhrases[386]) and 0.03 or 0.08
        relativeDelta = -((amount and (amount > 1 and amount / 100 or amount)) or fallback)
    end
    if value == nil and relativeDelta == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = "Set dark mode bar color",
        summary = "Adjusts the Colors > Unit Frame Global Coloring dark-mode bar color.",
    }
end

local NAME_SHORTENING_TERMS = {
    "shorten names", "shorten name", "short names", "short name", "name shortening",
    "truncate names", "truncate name", "name truncation", "unit name shortening",
    "unit names short", "names short", "names shorter", "shortened name", "shortened names",
    "name is cut off", "name gets cut off", "names are cut off", "names get cut off",
}

local NAME_SHORTENING_DOT_TERMS = {
    "dots", "dot", "ellipsis", "ellipses", "name dots", "name ellipsis",
    "truncate dots", "truncate ellipsis", "shortening dots", "shortening ellipsis",
    "trailing dots", "trailing dot", "trailing ellipsis", "three dots", "two dots",
}

local NAME_SHORTENING_NON_NAME_DOT_TERMS = {
    "corner dot", "corner dots", "corner indicator", "corner indicators",
    "status dot", "status dots", "status indicator", "status indicators",
    "spell indicator", "spell indicators", "combo point", "combo points", "combo dots",
    "class resource", "class resources", "class power", "holy power", "soul shard", "soul shards",
    "chi point", "chi points", "rune", "runes", "resource point", "resource points",
    "damage over time", "damage-over-time", "aura", "auras", "buff", "buffs", "debuff", "debuffs",
}

local NAME_SHORTENING_DOT_HIDE_TERMS = {
    "turn off", "switch off", "disable", "hide", "remove", "remove only", "get rid of",
    "take away", "without dots", "without ellipsis", "no dots", "no more dots",
    "without the dots", "without the ellipsis", "not have dots", "not have the dots",
    "hide dots", "hide ellipsis", "dont want dots", "dont want the dots",
    "do not want dots", "do not want the dots", "stop showing dots",
}

local NAME_SHORTENING_DOT_SHOW_TERMS = {
    "turn on", "switch on", "enable", "show dots", "show ellipsis", "display dots",
    "with dots", "with ellipsis", "keep dots", "keep the dots", "add dots", "restore dots",
}

local NAME_SHORTENING_LOCATION_TERMS = {
    "where", "where is", "where are", "where do", "where can", "how do", "how can",
    "which setting", "what setting", "which option", "what option", "help me find",
    "help me locate", "show me where", "tell me where", "open the setting", "open the option",
}

local NAME_SHORTENING_SCOPE_ORDER = {
    "shared", "target", "targettarget", "focus", "focustarget", "pet", "boss",
    "gf_party", "gf_raid", "gf_mythicraid",
}

local NAME_SHORTENING_ALL_TERMS = {
    "all shortened names", "every shortened name", "every shortened names",
}

local NAME_SHORTENING_SCOPE_LABELS = {
    shared = "Shared", target = "Target", targettarget = "Target of Target",
    focus = "Focus", focustarget = "Focus Target", pet = "Pet", boss = "Boss",
    gf_party = "Party", gf_raid = "Raid", gf_mythicraid = "Mythic Raid", player = "Player",
}

local NAME_SHORTENING_KEEP_START_TERMS = {
    "keep start", "keep the start", "keep beginning", "keep the beginning",
    "keep first", "keep first letters", "first letters", "start letters",
    "beginning letters", "from right", "from the right", "remove end",
    "remove the end", "cut end", "cut the end", "truncate end", "truncate the end",
    "shorten from right", "shorten from the right",
}

local NAME_SHORTENING_KEEP_END_TERMS = {
    "keep end", "keep the end", "keep ending", "keep the ending",
    "keep last", "keep last letters", "last letters", "end letters",
    "ending letters", "from left", "from the left", "remove start",
    "remove the start", "remove beginning", "remove the beginning",
    "cut start", "cut the start", "cut beginning", "cut the beginning",
    "truncate start", "truncate the start", "shorten from left", "shorten from the left",
}

local function HasNameShorteningIntent(text)
    if ContainsAny(text, NAME_SHORTENING_TERMS) then return true end
    if ContainsAny(text, FeaturesPhrases[387])
        and ContainsAny(text, FeaturesPhrases[388]) then
        return true
    end
    return false
end

local function NameShorteningContextScope(ctx)
    if type(ctx) ~= "table" then return nil end
    local function ScopeForKey(key)
        key = tostring(key or "")
        local scope, suffix = key:match("^fontScope%.([^.]+)%.(.+)$")
        if scope and (suffix:find("shortenName", 1, true) or suffix == "shortenNames") then return scope end
        scope, suffix = key:match("^(gf_[^.]+)%.(.+)$")
        if scope and (suffix == "nameShortenEnabled" or suffix == "nameMaxChars"
            or suffix == "nameClipSide" or suffix == "nameNoEllipsis") then
            return scope
        end
        return nil
    end
    local scope = ScopeForKey(ctx.lastSetting)
    if scope then return scope end
    local bundle = ctx.lastChangeBundle
    if type(bundle) == "table" then
        for i = #bundle, 1, -1 do
            scope = ScopeForKey(bundle[i] and bundle[i].key)
            if scope then return scope end
        end
    end
    return nil
end

local function AddNameShorteningScope(scopes, seen, scope)
    if scope and scope ~= "" and not seen[scope] then
        seen[scope] = true
        scopes[#scopes + 1] = scope
    end
end

local function NameShorteningScopes(text, ctx)
    if ContainsAny(text, FeaturesPhrases[389])
        or ContainsAny(text, NAME_SHORTENING_ALL_TERMS)
        or ContainsAny(text, { "all scopes", "every scope" }) then
        return {}, true, true
    end
    local scopes, seen = {}, {}
    local groups = DetectGroups and DetectGroups(text) or {}
    for i = 1, #groups do AddNameShorteningScope(scopes, seen, "gf_" .. tostring(groups[i])) end
    local units = DetectUnits and DetectUnits(text) or {}
    for i = 1, #units do AddNameShorteningScope(scopes, seen, units[i]) end
    if #scopes == 0 then
        local scope = DetectGlobalScope and DetectGlobalScope(text) or nil
        AddNameShorteningScope(scopes, seen, scope)
    end
    if #scopes > 0 then return scopes, false, true end
    AddNameShorteningScope(scopes, seen, NameShorteningContextScope(ctx))
    return scopes, false, false
end

local function NameShorteningScope(text, ctx)
    local scopes, allRequested, explicit = NameShorteningScopes(text, ctx)
    return scopes[1], explicit, allRequested
end

local function NameShorteningSetting(scope, suffix)
    if scope == "gf_party" or scope == "gf_raid" or scope == "gf_mythicraid" then
        local groupSuffix = ({
            shortenNames = "nameShortenEnabled",
            shortenNameMaxChars = "nameMaxChars",
            shortenNameClipSide = "nameClipSide",
            shortenNameNoEllipsis = "nameNoEllipsis",
        })[suffix]
        if groupSuffix and Registry then
            local setting = Registry:GetSetting(tostring(scope) .. "." .. groupSuffix)
            if setting then return setting end
        end
        if scope == "gf_mythicraid" then scope = "gf_raid" end
    end
    return Registry and Registry:GetSetting("fontScope." .. tostring(scope or "shared") .. "." .. suffix) or nil
end

local function AddNameShorteningChange(changes, scope, suffix, value, valueLabel)
    local setting = NameShorteningSetting(scope, suffix)
    if setting then
        changes[#changes + 1] = { setting = setting, value = value, valueLabel = valueLabel }
    end
    return setting
end

local function NameShorteningSide(text)
    if ContainsAny(text, NAME_SHORTENING_KEEP_START_TERMS) then
        return "RIGHT", "Keep start (first letters)"
    end
    if ContainsAny(text, NAME_SHORTENING_KEEP_END_TERMS) then
        return "LEFT", "Keep end (last letters)"
    end
    if ContainsAny(text, FeaturesPhrases[390]) then
        if ContainsAny(text, FeaturesPhrases[391]) then return "LEFT", "Left" end
        if ContainsAny(text, FeaturesPhrases[392]) then return "RIGHT", "Right" end
    end
    return nil
end

local function NameShorteningLength(text, setting)
    local requested = FirstNumber(text)
    if not requested then return nil, nil, nil end
    local value = math.floor((tonumber(requested) or 0) + 0.5)
    local minValue = tonumber(setting and setting.min)
    local maxValue = tonumber(setting and setting.max)
    local clampLabel
    if minValue and value < minValue then
        value = minValue
        clampLabel = "minimum"
    end
    if maxValue and value > maxValue then
        value = maxValue
        clampLabel = "maximum"
    end
    return value, math.floor((tonumber(requested) or value) + 0.5), clampLabel
end

local function NameShorteningValueLabel(value, requested, clampLabel)
    local label = tostring(value) .. " letters"
    if clampLabel and requested and requested ~= value then
        label = label .. " (" .. clampLabel .. ")"
    end
    return label
end

local function NameShorteningSideChoice(scope, sideValue, sideLabel, maxChars, requestedChars, clampLabel)
    local changes = {}
    AddNameShorteningChange(changes, scope, "shortenNames", true, "enabled")
    AddNameShorteningChange(changes, scope, "shortenNameMaxChars", maxChars, NameShorteningValueLabel(maxChars, requestedChars, clampLabel))
    AddNameShorteningChange(changes, scope, "shortenNameClipSide", sideValue, sideLabel)
    if #changes == 0 then return nil end
    return {
        changes = changes,
        valueLabel = sideLabel,
        label = sideLabel .. ", max " .. NameShorteningValueLabel(maxChars, requestedChars, clampLabel),
        summary = "Applies name shortening length and direction together.",
    }
end

local function IsNameShorteningContext(ctx)
    return NameShorteningContextScope(ctx) ~= nil
end

local function NameShorteningDotsRawToken(raw)
    raw = tostring(raw or "")
    return raw:find("%.%.") ~= nil or raw:find("…", 1, true) ~= nil
end

local function NameShorteningRawAuraDoT(raw)
    raw = tostring(raw or "")
    return raw:find("%f[%a]DoT[sS]?%f[%A]") ~= nil
end

local function NameShorteningDotsPolarity(text)
    if ContainsAny(text, {
        "do not hide", "dont hide", "do not turn off", "dont turn off",
        "do not remove", "dont remove", "not hide the dots", "not turn off the dots",
        "do not show", "dont show", "do not turn on", "dont turn on",
    }) then
        return nil, true
    end
    local negativeSetting = ContainsAny(text, { "no ellipsis", "name no ellipsis" })
    if negativeSetting then
        if ContainsAny(text, { "turn off", "switch off", "disable", "set off", "to off", "to false", "= false" })
            or text:match("%sfalse%s*$") or text:match("%soff%s*$") then
            return false
        end
        if ContainsAny(text, { "turn on", "switch on", "enable", "set on", "to on", "to true", "= true" })
            or text:match("%strue%s*$") or text:match("%son%s*$") then
            return true
        end
        -- Naming the positive No Ellipsis option without a separate boolean
        -- value means the user wants that option enabled.
        return true
    end
    if ContainsAny(text, { "keep dots off", "keep the dots off", "leave dots off", "leave the dots off" }) then return true end
    if ContainsAny(text, NAME_SHORTENING_DOT_HIDE_TERMS) or ContainsAny(text, FeaturesPhrases[395]) then return true end
    if ContainsAny(text, NAME_SHORTENING_DOT_SHOW_TERMS) or ContainsAny(text, FeaturesPhrases[396]) then return false end
    local value = DetectBoolean(text)
    if value ~= nil then return not value end
    return nil
end

local function NameShorteningDotsChanges(scope, noEllipsis)
    local changes = {}
    local setting = AddNameShorteningChange(changes, scope, "shortenNameNoEllipsis", noEllipsis,
        noEllipsis and "hidden" or "shown")
    return setting, changes
end

local function NameShorteningDotsChangesForScopes(scopes, noEllipsis)
    local changes, validScopes = {}, {}
    for i = 1, #(scopes or {}) do
        local scope = scopes[i]
        local setting = AddNameShorteningChange(changes, scope, "shortenNameNoEllipsis", noEllipsis,
            noEllipsis and "hidden" or "shown")
        if setting then validScopes[#validScopes + 1] = scope end
    end
    return changes, validScopes
end

local function NameShorteningScopeListLabel(scopes)
    local labels = {}
    for i = 1, #(scopes or {}) do
        labels[#labels + 1] = NAME_SHORTENING_SCOPE_LABELS[scopes[i]] or tostring(scopes[i])
    end
    if #labels == 0 then return "Shortened names" end
    if #labels == 1 then return labels[1] end
    if #labels == 2 then return labels[1] .. " and " .. labels[2] end
    return table.concat(labels, ", ", 1, #labels - 1) .. ", and " .. labels[#labels]
end

local function NameShorteningCustomScopes()
    local db = _G.MSUF_DB
    local scopes = {}
    if type(db) ~= "table" then return scopes end
    for i = 1, #NAME_SHORTENING_SCOPE_ORDER do
        local scope = NAME_SHORTENING_SCOPE_ORDER[i]
        if scope ~= "shared" and scope ~= "player"
            and type(db[scope]) == "table" and db[scope].fontOverride == true then
            scopes[#scopes + 1] = scope
        end
    end
    return scopes
end

local function NameShorteningAllDotsPlan(noEllipsis, navigation)
    if navigation then
        local setting = NameShorteningSetting("shared", "shortenNameNoEllipsis")
        local action = setting and Registry and Registry:GetAction("open_setting_control") or nil
        return action and {
            kind = "action",
            action = action,
            args = { settingKey = setting.key, label = "Shared Shortened-Name Dots", page = "opt_fonts" },
            label = "Open shortened-name dots",
            summary = "Opens the Fonts control where Shared and custom name-shortening scopes are managed.",
        } or nil
    end
    if noEllipsis == nil then return nil end
    local sharedScopes = { "shared" }
    local customScopes = NameShorteningCustomScopes()
    if #customScopes == 0 then
        local changes = NameShorteningDotsChangesForScopes(sharedScopes, noEllipsis)
        return {
            kind = "changes",
            changes = changes,
            label = "All Shortened-Name Dots",
            summary = "Changes Shared because every current scope follows it.",
            successText = noEllipsis
                and "Done. Shortened names no longer show trailing dots on any current scope."
                or "Done. Shortened names show trailing dots on every current scope.",
        }
    end
    local everyScope = { "shared" }
    for i = 1, #customScopes do everyScope[#everyScope + 1] = customScopes[i] end
    local sharedChanges = NameShorteningDotsChangesForScopes(sharedScopes, noEllipsis)
    local everyChanges = NameShorteningDotsChangesForScopes(everyScope, noEllipsis)
    return {
        kind = "ambiguous",
        choices = {
            {
                changes = sharedChanges,
                label = (noEllipsis and "Hide" or "Show") .. " dots for Shared and scopes following it",
                summary = "Leaves current custom scope overrides unchanged.",
            },
            {
                changes = everyChanges,
                label = (noEllipsis and "Hide" or "Show") .. " dots on every current scope",
                summary = "Updates Shared plus every scope that currently has a custom font override.",
            },
        },
        label = "Does all include custom font overrides?",
        summary = "Clarifies whether current custom scopes should change too.",
    }
end

local function NameShorteningDotsScopeChoices(noEllipsis, navigation)
    local choices = {}
    local action = (navigation or noEllipsis == nil) and Registry and Registry:GetAction("open_setting_control") or nil
    for i = 1, #NAME_SHORTENING_SCOPE_ORDER do
        local scope = NAME_SHORTENING_SCOPE_ORDER[i]
        local setting = NameShorteningSetting(scope, "shortenNameNoEllipsis")
        local scopeLabel = NAME_SHORTENING_SCOPE_LABELS[scope] or tostring(scope)
        if setting then
            if action then
                choices[#choices + 1] = {
                    action = action,
                    args = { settingKey = setting.key, label = scopeLabel .. " Shortened-Name Dots", page = "opt_fonts" },
                    label = "Open " .. scopeLabel .. " shortened-name dots",
                    summary = "Opens the exact Fonts control without changing it.",
                }
            elseif noEllipsis ~= nil then
                local _, changes = NameShorteningDotsChanges(scope, noEllipsis)
                choices[#choices + 1] = {
                    changes = changes,
                    label = (noEllipsis and "Hide " or "Show ") .. scopeLabel .. " shortened-name dots",
                    summary = "Changes only the ellipsis on shortened " .. scopeLabel .. " names.",
                }
            end
        end
    end
    return choices
end

local function NameShorteningDotsDomainChoices(scope, noEllipsis, auraFirst, statusFirst)
    local choices = {}
    local openPage = Registry and Registry:GetAction("open_page")
    local scopeLabel = NAME_SHORTENING_SCOPE_LABELS[scope] or "that frame"
    local function AddPage(page, label, query)
        if openPage then
            choices[#choices + 1] = {
                action = openPage,
                args = { page = page, label = label, query = query },
                label = label,
                summary = "Opens the likely MSUF page without changing a setting.",
            }
        end
    end
    local function AddNameDots()
        local setting = scope and NameShorteningSetting(scope, "shortenNameNoEllipsis") or nil
        if setting and noEllipsis ~= nil then
            local _, changes = NameShorteningDotsChanges(scope, noEllipsis)
            choices[#choices + 1] = {
                changes = changes,
                label = (noEllipsis and "Hide " or "Show ") .. scopeLabel .. " shortened-name dots",
                summary = "Changes only the ellipsis on shortened names.",
            }
        elseif setting and Registry then
            local openSetting = Registry:GetAction("open_setting_control")
            if openSetting then
                choices[#choices + 1] = {
                    action = openSetting,
                    args = { settingKey = setting.key, label = scopeLabel .. " Shortened-Name Dots", page = "opt_fonts" },
                    label = "Shortened-name ellipsis on " .. scopeLabel,
                    summary = "Opens the exact Fonts control without changing it.",
                }
            end
        else
            AddPage("opt_fonts", "Shortened-name ellipsis", "name shortening no ellipsis")
        end
    end
    local auraPage = scope and scope:find("^gf_") and "gf_auras" or "auras3"
    local indicatorPage = scope and scope:find("^gf_") and "gf_indicators"
        or (scope and scope ~= "shared" and ("uf_" .. tostring(scope)) or "uf_player")
    if auraFirst then AddPage(auraPage, "DoTs / debuff auras", "debuff aura filters") end
    if statusFirst then AddPage(indicatorPage, "Status or corner indicators", "status corner indicators") end
    AddNameDots()
    if not statusFirst then
        AddPage(indicatorPage, "Status or corner indicators", "status corner indicators")
    end
    AddPage("classpower", "Class-resource dots", "class resource display")
    if not auraFirst then AddPage(auraPage, "DoTs / debuff auras", "debuff aura filters") end
    return {
        kind = "ambiguous",
        choices = choices,
        label = "Which dots?",
        summary = "Asks which visual dots the user means before changing MSUF.",
    }
end

local function ParseNameShorteningDots(text, ctx, raw)
    -- AutoCoverage exposes the underlying saved-variable field as an exact
    -- compatibility setting (for example "Target Shorten Name Show Dots").
    -- Keep exact generated-label commands owned by the registry; the semantic
    -- No Ellipsis intent below is for natural wording such as "turn off the
    -- dots on shortened party names". Both controls reach the same visible
    -- behavior, but exact-label callers must retain exact-key parity.
    if ContainsAny(text, { "shorten name show dots", "shorten names show dots" }) then return nil end
    local explicitNameContext = HasNameShorteningIntent(text)
        or ContainsAny(text, FeaturesPhrases[394])
    local hasDotNoun = ContainsAny(text, NAME_SHORTENING_DOT_TERMS)
    local rawDots = NameShorteningDotsRawToken(raw)
    -- Two periods attached to an ordinary sentence can just be punctuation.
    -- Treat raw '..'/'...' as the setting noun only when the user also names
    -- shortened/unit names; explicit words such as dots/ellipsis remain enough.
    if not hasDotNoun and not (rawDots and explicitNameContext) then return nil end
    if ContainsAny(text, FeaturesPhrases[393]) then return nil end
    local auraDoT = NameShorteningRawAuraDoT(raw)
    local scopes, allRequested = NameShorteningScopes(text, ctx)
    local scope = scopes[1]
    local noEllipsis, negatedAction = NameShorteningDotsPolarity(text)
    if noEllipsis == nil and rawDots and explicitNameContext then
        if ContainsAny(text, { "without", "without the", "remove", "take away", "get rid of" }) then
            noEllipsis = true
        elseif ContainsAny(text, { "with", "with the", "show", "restore", "put back" }) then
            noEllipsis = false
        end
    end
    local nonNameDots = ContainsAny(text, NAME_SHORTENING_NON_NAME_DOT_TERMS)
    if nonNameDots and not auraDoT then
        if ContainsAny(text, { "status dot", "status dots", "status indicator", "status indicators" }) then
            return NameShorteningDotsDomainChoices(scope, noEllipsis, false, true)
        end
        if ContainsAny(text, { "damage over time", "damage-over-time", "aura", "auras", "buff", "buffs", "debuff", "debuffs" }) then
            return NameShorteningDotsDomainChoices(scope, noEllipsis, true)
        end
        return nil
    end
    local contextual = IsNameShorteningContext(ctx)

    if auraDoT and not explicitNameContext then
        return NameShorteningDotsDomainChoices(scope, noEllipsis, true)
    end
    if allRequested then
        local strongAllEvidence = explicitNameContext or contextual
            or ContainsAny(text, { "ellipsis", "ellipses", "trailing dots", "trailing dot", "three dots", "two dots" })
        if not strongAllEvidence then
            local sharedEnabled = NameShorteningSetting("shared", "shortenNames")
            local ok, current = false, nil
            if sharedEnabled and type(sharedEnabled.get) == "function" then ok, current = pcall(sharedEnabled.get) end
            if ok and type(current) ~= "boolean" then current = nil end
            if current ~= true then return NameShorteningDotsDomainChoices(nil, noEllipsis, false) end
        end
        local allPlan = NameShorteningAllDotsPlan(noEllipsis, ContainsAny(text, NAME_SHORTENING_LOCATION_TERMS))
        if allPlan then return allPlan end
        return NameShorteningDotsDomainChoices(nil, noEllipsis, false)
    end
    if #scopes == 0 then
        if explicitNameContext or contextual then
            return {
                kind = "ambiguous",
                choices = NameShorteningDotsScopeChoices(noEllipsis, ContainsAny(text, NAME_SHORTENING_LOCATION_TERMS)),
                label = "Which shortened names?",
                summary = "Asks which name-shortening scope should change instead of assuming Shared.",
            }
        end
        return NameShorteningDotsDomainChoices(nil, noEllipsis, false)
    end

    local hasPlayer
    for i = 1, #scopes do if scopes[i] == "player" then hasPlayer = true break end end
    if hasPlayer then
        return {
            kind = "ambiguous",
            choices = NameShorteningDotsScopeChoices(noEllipsis, ContainsAny(text, NAME_SHORTENING_LOCATION_TERMS)),
            label = "Player uses Shared name-shortening options; choose a supported scope",
            summary = "Player has no independent name-shortening control.",
        }
    end

    local settings = {}
    for i = 1, #scopes do
        local setting = NameShorteningSetting(scopes[i], "shortenNameNoEllipsis")
        if not setting then return NameShorteningDotsDomainChoices(scopes[i], noEllipsis, false) end
        settings[#settings + 1] = setting
    end

    local strongNameEvidence = explicitNameContext or contextual
        or ContainsAny(text, { "ellipsis", "ellipses", "trailing dots", "trailing dot", "three dots", "two dots" })
        or (rawDots and explicitNameContext)
    if not strongNameEvidence then
        for i = 1, #scopes do
            local enabled = NameShorteningSetting(scopes[i], "shortenNames")
            local ok, current = false, nil
            if enabled and type(enabled.get) == "function" then ok, current = pcall(enabled.get) end
            if not ok or current ~= true then return NameShorteningDotsDomainChoices(scopes[i], noEllipsis, false) end
        end
    end

    if ContainsAny(text, NAME_SHORTENING_LOCATION_TERMS) then
        local action = Registry and Registry:GetAction("open_setting_control")
        if action and #settings == 1 then
            return {
                kind = "action",
                action = action,
                args = { settingKey = settings[1].key, label = (NAME_SHORTENING_SCOPE_LABELS[scope] or "Name") .. " Shortened-Name Dots", page = "opt_fonts" },
                label = "Open shortened-name dots",
                summary = "Opens Appearance > Fonts > Name Shortening > No Ellipsis without changing it.",
            }
        end
        return {
            kind = "ambiguous",
            choices = NameShorteningDotsScopeChoices(nil, true),
            label = "Which shortened-name dots control should I open?",
            summary = "Offers exact Fonts controls without changing them.",
        }
    end

    if noEllipsis == nil or negatedAction then
        local hideChanges = NameShorteningDotsChangesForScopes(scopes, true)
        local showChanges = NameShorteningDotsChangesForScopes(scopes, false)
        return {
            kind = "ambiguous",
            choices = {
                { changes = hideChanges, label = "Hide the shortened-name dots" },
                { changes = showChanges, label = "Show the shortened-name dots" },
            },
            label = "Hide or show the shortened-name dots?",
            summary = "Asks whether name-shortening ellipsis dots should be shown.",
        }
    end
    local changes, validScopes = NameShorteningDotsChangesForScopes(scopes, noEllipsis)
    local scopeLabel = NameShorteningScopeListLabel(validScopes)
    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = scopeLabel .. " Shortened-Name Dots",
        summary = "Changes only whether shortened names show trailing dots while preserving the shortening setup.",
        successText = noEllipsis
            and ("Done. " .. scopeLabel .. " shortened names no longer show trailing dots. The name, shortening length, and kept side stay unchanged.")
            or ("Done. " .. scopeLabel .. " shortened names show trailing dots again. The shortening length and kept side stay unchanged."),
    }
end

local function ParseNameShorteningShortcut(text, ctx, raw)
    local dots = ParseNameShorteningDots(text, ctx, raw)
    if dots then return dots end
    if ContainsAny(text, FeaturesPhrases[397]) then return nil end
    if not HasNameShorteningIntent(text) then return nil end

    local scope = NameShorteningScope(text, ctx) or "shared"
    local enabledSetting = NameShorteningSetting(scope, "shortenNames")
    local maxSetting = NameShorteningSetting(scope, "shortenNameMaxChars")
    local sideSetting = NameShorteningSetting(scope, "shortenNameClipSide")
    if (scope == "gf_party" or scope == "gf_raid") and not (enabledSetting and maxSetting and sideSetting) then
        return nil
    end
    if scope == "player" or not (enabledSetting and maxSetting and sideSetting) then
        local message = "Name shortening is available for Shared, Target, Focus, Pet, Boss, Party, or Raid."
        if scope == "player" then
            message = "Global Font name shortening is available for Shared, Target, Focus, Pet, Boss, Party, or Raid."
        end
        return {
            kind = "unknown",
            status = "failed",
            text = message,
        }
    end

    local bool = DetectBoolean(text)
    local maxChars, requestedChars, clampLabel = NameShorteningLength(text, maxSetting)
    local sideValue, sideLabel = NameShorteningSide(text)
    if sideValue and not maxChars then
        local changes = {}
        if bool ~= nil then AddNameShorteningChange(changes, scope, "shortenNames", bool, bool and "enabled" or "disabled") end
        AddNameShorteningChange(changes, scope, "shortenNameClipSide", sideValue, sideLabel)
        if #changes == 0 then return nil end
        return {
            kind = "changes",
            changes = changes,
            label = sideSetting.label or "Name Truncation Style",
            summary = "Changes the name-shortening side option without changing the length.",
        }
    end
    if bool ~= nil and not maxChars and not sideValue then
        return {
            kind = "changes",
            changes = { { setting = enabledSetting, value = bool, valueLabel = bool and "enabled" or "disabled" } },
            label = enabledSetting.label or "Name Shortening",
            summary = "Toggles name shortening without changing its length or direction.",
        }
    end

    if maxChars and sideValue then
        local changes = {}
        AddNameShorteningChange(changes, scope, "shortenNames", true, "enabled")
        AddNameShorteningChange(changes, scope, "shortenNameMaxChars", maxChars, NameShorteningValueLabel(maxChars, requestedChars, clampLabel))
        AddNameShorteningChange(changes, scope, "shortenNameClipSide", sideValue, sideLabel)
        if #changes == 0 then return nil end
        return {
            kind = "changes",
            changes = changes,
            label = "Set name shortening",
            summary = "Enables name shortening and sets its length and direction.",
        }
    end

    if maxChars then
        local choices = {}
        local keepStart = NameShorteningSideChoice(scope, "RIGHT", "Keep start (first letters)", maxChars, requestedChars, clampLabel)
        local keepEnd = NameShorteningSideChoice(scope, "LEFT", "Keep end (last letters)", maxChars, requestedChars, clampLabel)
        if keepStart then choices[#choices + 1] = keepStart end
        if keepEnd then choices[#choices + 1] = keepEnd end
        if #choices > 0 then
            return {
                kind = "ambiguous",
                choices = choices,
                label = "Which side should name shortening keep?",
                summary = "Asks which side of the unit name should remain visible before applying name shortening.",
            }
        end
    end

    return {
        kind = "answer",
        status = "ambiguous",
        text = "How many letters should names keep, and which side should remain visible? For example: 'shorten names to 10 letters keeping first letters' or 'shorten names to 10 letters keeping last letters'.",
        summary = "Asks which name-shortening length or direction to use.",
    }
end

local function ParseCastbarPreviewAction(text)
    if not ContainsAny(text, FeaturesPhrases[398]) then return nil end
    if not ContainsAny(text, FeaturesPhrases[399]) then return nil end
    local units = DetectUnits(text)
    local unit = units[1] or "player"
    local castbarTestMode = ContainsAny(text, {
        "test mode", "testmode", "castbar test", "cast bar test", "test cast",
        "testmodus", "zauberleisten test", "test zauberleiste",
    })
    if castbarTestMode then
        local action = Registry and Registry:GetAction("set_castbar_test_mode")
        if not action then return nil end
        local disabled = ContainsAny(text, FeaturesPhrases[409])
            or ContainsAny(text, { "disable", "off", "hide", "stoppe", "stoppen", "deaktivieren", "ausschalten" })
        return {
            kind = "action",
            action = action,
            args = { unit = unit, value = not disabled },
            label = (disabled and "Stop " or "Start ") .. UnitDisplayLabel(unit) .. " Cast Bar Test",
            summary = "Starts or stops the requested Cast Bar test in MSUF Edit Mode.",
        }
    end
    local action = Registry and Registry:GetAction("preview_castbar")
    if not action then return nil end
    local kind = "normal"
    if ContainsAny(text, FeaturesPhrases[400]) then
        kind = "channel"
    elseif ContainsAny(text, FeaturesPhrases[401]) then
        kind = "empowered"
    end
    return {
        kind = "action",
        action = action,
        args = {
            unit = unit,
            kind = kind,
            interrupt = ContainsAny(text, FeaturesPhrases[402]),
        },
        label = "Preview Cast Bar",
        summary = "Opens the Cast Bar page and selects the requested preview.",
    }
end

local CASTBAR_GLOBAL_BOOLEAN_DETAILS = {
    { key = "general.castbarShowChannelTicks", terms = { "channel ticks", "channel tick lines", "castbar ticks", "tick lines", "kanal ticks", "kanal tick linien", "kanal ticks anzeigen" } },
    { key = "general.castbarShowGlow", terms = { "glow", "glow effect", "gluehen", "glow effekt" } },
    { key = "general.castbarShowSpark", terms = { "spark", "castbar spark", "funke", "zauberleisten funke" } },
    { key = "general.castbarSparkOverflow", terms = { "spark overflow", "spark beyond bar", "funke ausserhalb", "spark ausserhalb" } },
    { key = "general.castbarShowLatency", terms = { "latency", "latency indicator", "latenz", "latenzanzeige", "latenz anzeige" } },
    { key = "general.castbarUnifiedDirection", terms = { "unified direction", "unified fill direction", "same fill direction", "gleiche fuellrichtung", "einheitliche fuellrichtung", "gleiche richtung" } },
    { key = "general.castbarOpositeDirectionTarget", terms = { "target opposite direction", "opposite target direction", "target opposite fill direction", "ziel entgegengesetzte richtung", "ziel umgekehrte richtung", "ziel andere fuellrichtung" } },
    { key = "general.empowerColorStages", terms = { "empower color stages", "empowered stage colors", "empower stage colors", "empower stufen farben", "ermaechtigen stufen farben", "verstaerkte stufen farben" } },
    { key = "general.empowerStageBlink", terms = { "empower stage blink", "empowered stage blink", "stage blink", "empower stufen blinken", "ermaechtigen stufen blinken", "stufen blinken" } },
}

local function ParseCastbarGlobalDetail(text)
    if not ContainsAny(text, FeaturesPhrases[403]) then return nil end
    local value = DetectBoolean(text)
    if value == nil then return nil end
    for i = 1, #CASTBAR_GLOBAL_BOOLEAN_DETAILS do
        local spec = CASTBAR_GLOBAL_BOOLEAN_DETAILS[i]
        if ContainsAny(text, spec.terms) then
            local setting = Registry and Registry:GetSetting(spec.key)
            return setting and {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = setting.label or "Cast Bar detail",
                summary = "Changes a global Cast Bar detail option without toggling the unit cast bar.",
            } or nil
        end
    end
    return nil
end

local function ParseCastbarDirectionClarification(text)
    if not ContainsAny(text, FeaturesPhrases[404]) then return nil end
    if not ContainsAny(text, FeaturesPhrases[405]) then return nil end
    if not ContainsAny(text, FeaturesPhrases[406]) then return nil end

    local opposite = Registry and Registry:GetSetting("general.castbarOpositeDirectionTarget")
    if not opposite then return nil end
    local value = DetectBoolean(text)
    if value == nil and ContainsAny(text, FeaturesPhrases[407]) then
        value = true
    end
    if value == nil and ContainsAny(text, FeaturesPhrases[408]) then
        value = false
    end
    if value == nil and ContainsAny(text, FeaturesPhrases[409]) and ContainsAny(text, FeaturesPhrases[410]) then
        value = false
    end
    if value ~= nil then
        return {
            kind = "changes",
            changes = { { setting = opposite, value = value } },
            label = opposite.label or "Use Opposite Fill Direction for Target",
            summary = "Changes the Target cast bar opposite-fill checkbox.",
        }
    end

    local choices = {
        {
            setting = opposite,
            value = true,
            valueLabel = "enabled",
            label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(opposite, "enabled", "Use Opposite Fill Direction for Target") or "Use Opposite Fill Direction for Target: enabled",
        },
    }
    local fill = Registry and Registry:GetSetting("general.castbarFillDirection")
    if fill then
        choices[#choices + 1] = {
            setting = fill,
            value = "RTL",
            valueLabel = "rtl",
            label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(fill, "right to left", "Cast Bar Fill Direction") or "Cast Bar Fill Direction: right to left",
        }
        choices[#choices + 1] = {
            setting = fill,
            value = "LTR",
            valueLabel = "ltr",
            label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(fill, "left to right", "Cast Bar Fill Direction") or "Cast Bar Fill Direction: left to right",
        }
    end
    return {
        kind = "ambiguous",
        choices = choices,
        label = "Which Target cast bar direction option?",
        summary = "That could mean the Target opposite-fill checkbox or the global Cast Bar Fill Direction.",
    }
end
local function UpgradeHighlightTourWasSkipped()
    local controller = MSUF and MSUF.UpgradeHighlights
    if not (type(controller) == "table" and type(controller.GetDebugSummary) == "function") then return false end
    local ok, _, status = pcall(controller.GetDebugSummary, controller)
    return ok and status == "skipped"
end

local function ParseUpgradeHighlightTour(text)
    local explicit = ContainsAny(text, FeaturesPhrases[429])
    local skippedReplay = UpgradeHighlightTourWasSkipped() and ContainsAny(text, FeaturesPhrases[430])
    if not explicit and not skippedReplay then return nil end
    local action = Registry and Registry:GetAction("restart_upgrade_highlight_tour")
    return action and {
        kind = "action",
        action = action,
        args = {},
        label = "Restart upgrade highlight tour",
        summary = "Restarts the skipped release-highlight tour at highlight 1.",
    } or nil
end

local function ParseGuidedSetup(text)
    local highlightTour = ParseUpgradeHighlightTour(text)
    if highlightTour then return highlightTour end
    if not ContainsAny(text, FeaturesPhrases[411]) then return nil end
    local action = Registry and Registry:GetAction("guided_setup")
    return action and {
        kind = "action",
        action = action,
        -- The native tour owns all setup personalization and progress.  The
        -- old text wizard used the raw prompt as a `style` argument, but that
        -- field is intentionally absent from the saved-state action contract.
        args = {},
        label = "Guided setup",
        summary = "Starts the guided setup flow.",
    } or nil
end

local function ParseGuidedSetupFollowup(text, ctx)
    if not ContainsAny(text, FeaturesPhrases[418]) then return nil end
    local action = Registry and Registry:GetAction("guided_setup_step")
    return action and {
        kind = "action",
        action = action,
        -- A bare follow-up only reopens the native tour.  Actual guided-bar
        -- steps use the explicit, validated `step` field.
        args = {},
        label = "Open guided setup",
        summary = "Returns to the native guided setup.",
    } or nil
end

function P.ParseProfileBackupImportQuestion(text)
    if not ContainsAny(text, FeaturesPhrases[423]) then return nil end
    return {
        kind = "answer",
        status = "info",
        text = table.concat({
            "Before importing a profile, export your current profile first.",
            "Ask for 'backup before importing profile' to create a copyable full-profile backup string. Then add or import the new profile string from the Profiles page.",
        }, "\n"),
        summary = "Shows the safe profile backup-before-import steps without changing options.",
    }
end

function P.ParseCustomAnchorLookupQuestion(text)
    if not ContainsAny(text, FeaturesPhrases[424]) then return nil end
    return {
        kind = "answer",
        status = "info",
        text = "Pick a concrete MSUF frame or open a Unit/Group page for the custom anchor picker. Examples: open player custom anchor picker, open target custom anchor picker, open raid custom anchor picker, or set target custom anchor to Cooldown Manager.",
        summary = "Shows custom anchor picker usage without guessing a frame.",
    }
end

function P.ParseGroupScaleLookupQuestion(text)
    if ContainsAny(text, FeaturesPhrases[425]) then return nil end
    if not ContainsAny(text, FeaturesPhrases[426]) then return nil end
    if type(P.GroupScaleBreakpointAttrForText) ~= "function" then return nil end
    local attr, playerCount = P.GroupScaleBreakpointAttrForText(text)
    if not attr then return nil end
    local groups = DetectGroups(text)
    if #groups == 0 and type(P.GroupScopesOrCurrentPage) == "function" then
        groups = P.GroupScopesOrCurrentPage(text)
    end
    if #groups == 0 then return nil end
    local scope = groups[1]
    local label = type(P.FrameResizeGroupLabel) == "function" and P.FrameResizeGroupLabel(scope) or GroupDisplayLabel(scope)
    local breakpoint = ({ scaleAt10 = "1-10 players", scaleAt20 = "11-20 players", scaleAt25 = "21-25 players", scaleOver25 = "26+ players" })[attr] or "that player count"
    local targetText = playerCount
        and ("at " .. tostring(playerCount) .. " players (" .. tostring(breakpoint) .. " breakpoint)")
        or ("for " .. tostring(breakpoint))
    local scopeText = scope == "mythicraid" and "mythic raid" or (scope or "raid")
    return {
        kind = "answer",
        status = "info",
        text = table.concat({
            "Group frame scaling breakpoints",
            "I can change " .. tostring(label) .. " scaling " .. targetText .. " with the Group Layout scaling sliders.",
            "Examples: set " .. tostring(scopeText) .. " scale for 20 players to 80; make " .. tostring(scopeText) .. " frames smaller when 20 people; increase " .. tostring(scopeText) .. " scale for 20m by 5.",
        }, "\n"),
        summary = "Shows group player-count scaling without changing options.",
    }
end

local function ParseLookupQuestion(text, raw)
    if not (P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(text)) then return nil end
    return ParseDiagnostic(text)
        or P.ParseProfileBackupImportQuestion(text)
        or P.ParseCustomAnchorLookupQuestion(text)
        or P.ParseGroupScaleLookupQuestion(text)
        or ParseGuidedSetup(text)
        or ParseScopedHelp(text)
        or ParseDashboardPanelAction(text)
        or ParseOpen(text, raw)
        or ParseSupportWorkflow(text, raw)
        or ParseMenuWindowAction(text)
        or {
            kind = "unknown",
            status = "info",
            text = "I read that as a question, so MSUF stayed as it was. Open the Assistant Dashboard or include the frame/page and option, for example 'where can I change target power text'.",
            summary = "Lookup question was not treated as an option change.",
        }
end

P.CLASS_POWER_DETAIL_TERMS = CLASS_POWER_DETAIL_TERMS
P.ParseClassPowerRootToggle = ParseClassPowerRootToggle
P.ParseFontColorAction = ParseFontColorAction
P.BuildColorResetAction = BuildColorResetAction
P.POWER_TOKEN_EXTRA_ALIASES = POWER_TOKEN_EXTRA_ALIASES
P.PowerColorTokenForText = PowerColorTokenForText
P.CP_TOKEN_EXTRA_ALIASES = CP_TOKEN_EXTRA_ALIASES
P.ClassPowerColorTokenForText = ClassPowerColorTokenForText
P.ParseColorAction = ParseColorAction
P.ParseDiagnostic = ParseDiagnostic
P.ParseScopedHelp = ParseScopedHelp
P.ParseLookupQuestion = ParseLookupQuestion
P.SupportLinkForText = SupportLinkForText
P.ParseSupportWorkflow = ParseSupportWorkflow
P.GlobalScalePresetForText = GlobalScalePresetForText
P.ParsePresetWorkflow = ParsePresetWorkflow
P.ParseBossFramePreviewShortcut = ParseBossFramePreviewShortcut
P.ParseEditModeHUDControl = ParseEditModeHUDControl
P.ParseDashboardScaleShortcut = ParseDashboardScaleShortcut
P.ParseScopedOverrideReset = ParseScopedOverrideReset
P.ParseClassPowerAction = ParseClassPowerAction
P.GAMEPLAY_ROOT_TOGGLES = GAMEPLAY_ROOT_TOGGLES
P.ParseGameplayRootToggle = ParseGameplayRootToggle
P.ParseGameplayAction = ParseGameplayAction
P.ParseGlobalBarsAction = ParseGlobalBarsAction
P.ParseDarkModeBrightnessShortcut = ParseDarkModeBrightnessShortcut
P.ParseNameShorteningDotsShortcut = ParseNameShorteningDots
P.ParseNameShorteningShortcut = ParseNameShorteningShortcut
P.ParseCastbarPreviewAction = ParseCastbarPreviewAction
P.CASTBAR_GLOBAL_BOOLEAN_DETAILS = CASTBAR_GLOBAL_BOOLEAN_DETAILS
P.ParseCastbarGlobalDetail = ParseCastbarGlobalDetail
P.ParseCastbarDirectionClarification = ParseCastbarDirectionClarification
P.ParseUpgradeHighlightTour = ParseUpgradeHighlightTour
P.ParseGuidedSetup = ParseGuidedSetup
P.ParseGuidedSetupFollowup = ParseGuidedSetupFollowup
