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
    "alternative mana", "detached power",
}

local function ClassPowerMentionIsNegated(text)
    return ContainsAny(text, {
        "not class resource", "not class resources", "not class power", "not class bar", "not resource bar",
        "no class resource", "no class resources", "no class power", "no class bar", "no resource bar",
        "dont class resource", "do not class resource",
        "nicht class resource", "nicht class power", "nicht klassenressource", "keine class resource",
        "kein class resource", "keine klassenressource", "nicht ressourcenleiste",
    })
end

local function HasClassPowerIntent(text)
    if ClassPowerMentionIsNegated(text) then return false end
    return ContainsAny(text, CLASS_POWER_TERMS)
        or ContainsAny(text, { "resource numbers", "resource number", "resource text", "resource texts" })
end

local function ParseClassPowerRootToggle(text)
    if ContainsAny(text, { "setting", "settings", "option", "options", "page", "menu" })
        and ContainsAny(text, { "show me", "show", "open", "where", "find", "help" }) then
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
    if ContainsAny(text, { "auto fit", "autofit", "auto-fit", "auto fit pips", "fit pips", "compact pips", "pip width" }) then return "auto_pips" end
    if ContainsAny(text, CLASS_POWER_COOLDOWN_TARGET_TERMS) then return "cooldown" end
    if ContainsAny(text, { "utility cooldown", "utility cooldowns", "utility cooldown manager", "utility cooldownmanager" }) then return "utility" end
    if ContainsAny(text, { "tracked buff", "tracked buffs", "buff tracker", "tracked-buffs" }) then return "tracked_buffs" end
    if ContainsAny(text, { "custom width", "manual width", "custom mode", "manual mode" }) then return "custom" end
    if ContainsAny(text, CLASS_POWER_PLAYER_TARGET_TERMS) then return "player" end
    return nil
end

function A._ParseClassPowerWidthModeShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, { "detached power", "alt mana", "alternative mana" }) then return nil end
    local mode = ClassPowerWidthModeForText(text)
    if not mode then return nil end
    local widthIntent = ContainsAny(text, {
        "width", "wide", "match", "same width", "width mode", "width source", "match width",
        "player width", "player frame width", "auto fit", "fit pips", "pip width",
    })
    if not widthIntent then return nil end
    if FirstNumber(text) and not ContainsAny(text, { "width mode", "width source", "match", "same width", "player width", "cooldown", "cooldowns", "tracked buff", "utility", "auto fit", "fit pips", "pip width" }) then
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
    if ContainsAny(text, { "show", "visible", "turn on" }) and ContainsAny(text, {
        "when full", "if full", "full resource", "full resources",
        "when empty", "if empty", "empty resource", "empty resources",
        "out of combat", "ooc",
    }) then
        return false
    end
    if ContainsAny(text, {
        "turn off hide", "disable hide", "dont hide", "do not hide", "never hide",
        "always show", "show when", "show while", "show out of combat", "show class resource",
    }) then
        return false
    end
    if ContainsAny(text, { "turn on hide", "enable hide", "hide when", "hide while", "hide out of combat", "hide ooc" }) then
        return true
    end
    if ContainsAny(text, { "hide class resource", "hide class resources", "hide class power", "hide class bar", "hide resource bar", "hide" }) then
        return true
    end
    local value = DetectBoolean(text)
    if value == false then return false end
    if value == true then return true end
    return nil
end

function A._ParseClassPowerVisibilityShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    local rule
    if ContainsAny(text, { "out of combat", "ooc" }) then
        rule = { key = "bars.classPowerHideOOC", label = "Class Resource Hide Out of Combat" }
    elseif ContainsAny(text, { "when full", "if full", "full resource", "full resources", "full" }) then
        rule = { key = "bars.classPowerHideWhenFull", label = "Hide Class Resource When Full" }
    elseif ContainsAny(text, { "when empty", "if empty", "empty resource", "empty resources", "empty" }) then
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
    if ContainsAny(text, { "detached power", "alt mana", "alternative mana", "text anchor" }) then return nil end
    local hasAnchorIntent = ContainsAny(text, {
        "anchor", "anchored", "follow", "attach", "attached", "dock", "to cooldown", "to cooldowns",
        "to player", "player frame", "cooldownmanager", "cooldown manager",
    })
    if not hasAnchorIntent then return nil end
    local targetCooldown = ContainsAny(text, CLASS_POWER_COOLDOWN_TARGET_TERMS)
    local targetPlayer = ContainsAny(text, CLASS_POWER_PLAYER_TARGET_TERMS)
    local value = DetectBoolean(text)
    if targetCooldown and ContainsAny(text, {
        "detach", "detach from", "undock", "undock from", "disconnect", "disconnect from",
        "stop following", "dont follow", "do not follow", "remove from",
    }) then
        value = false
    elseif targetCooldown then
        value = value ~= false
    elseif targetPlayer then
        value = false
    elseif value == nil and ContainsAny(text, { "anchor", "follow", "attach", "dock" }) then
        value = true
    end
    if value == nil then return nil end
    local anchor = ClassPowerSetting("bars.classPowerAnchorToCooldown")
    if not anchor then return nil end
    local changes = { { setting = anchor, value = value } }
    if targetPlayer then
        local widthMode = ClassPowerSetting("bars.classPowerWidthMode")
        if widthMode then changes[#changes + 1] = { setting = widthMode, value = "player" } end
    elseif value == true and ContainsAny(text, { "width", "match width", "same width" }) then
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
    if ContainsAny(text, { "under", "below", "beneath", "bottom of", "underneath", "unter", "darunter" }) then return "below" end
    if ContainsAny(text, { "above", "over", "top of", "ueber", "darueber" }) then return "above" end
    if ContainsAny(text, { "on player", "on the player", "inside player", "inside the player" }) then return "top" end
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
    if ContainsAny(text, { "detached power", "alt mana", "alternative mana", "text" }) then return nil end
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
    if ContainsAny(text, { "color", "colour", "background", "font size", "text size", "move", "offset" }) then return nil end
    local value
    if ContainsAny(text, { "as text", "show text", "show numbers", "show number", "numbers only", "text only" })
        or (ContainsAny(text, { "show", "turn on", "enable" }) and ContainsAny(text, { "number", "numbers", "text" })) then
        value = true
    elseif ContainsAny(text, {
        "as pips", "as dots", "as bars", "show pips", "show dots", "show bars",
        "pips only", "dots only", "hide numbers", "hide number", "hide text",
        "turn off numbers", "turn off number", "turn off text", "disable numbers",
        "disable number", "disable text", "without numbers", "no numbers",
    }) or (ContainsAny(text, { "hide", "turn off", "disable", "without", "no" }) and ContainsAny(text, { "number", "numbers", "text" })) then
        value = false
    else
        return nil
    end
    local textSetting = ClassPowerSetting("bars.classPowerShowText")
    if not textSetting then return nil end
    local changes = { { setting = textSetting, value = value } }
    if ContainsAny(text, { "show", "turn on", "enable" }) then
        local root = ClassPowerSetting("bars.showClassPower")
        if root then table.insert(changes, 1, { setting = root, value = true }) end
    end
    return {
        kind = "changes",
        changes = changes,
        label = value and "Show Class Resource Text" or "Show Class Resource Pips",
        bulkSafe = #changes > 1,
        summary = "Switches Class Resources between text and pips.",
    }
end

function A._ParseClassPowerFillDirectionShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, { "detached power", "alternative mana", "alt mana" }) then return nil end
    if not ContainsAny(text, {
        "fill", "direction", "reverse", "reversed", "backwards", "backward",
        "right to left", "left to right", "normal", "forward",
    }) then return nil end

    local value
    local boolValue = DetectBoolean(text)
    if boolValue == false and ContainsAny(text, { "reverse", "reversed", "backwards", "backward", "right to left" }) then
        value = false
    elseif ContainsAny(text, {
        "right to left", "fill right", "fill backwards", "fill backward",
        "fills backwards", "fills backward", "reverse fill", "reverse direction",
        "fill reverse", "fill reversed", "other way",
    }) then
        value = true
    elseif ContainsAny(text, {
        "left to right", "fill left", "normal direction", "normal fill",
        "fill normal", "forward fill", "fill forward", "same direction",
    }) then
        value = false
    elseif ContainsAny(text, { "reverse", "reversed" }) then
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
    if not ContainsAny(text, {
        "fill", "direction", "reverse", "reversed", "backwards", "backward",
        "right to left", "left to right", "normal", "forward",
    }) then return nil end

    local value
    local boolValue = DetectBoolean(text)
    if boolValue == false and ContainsAny(text, { "reverse", "reversed", "backwards", "backward", "right to left" }) then
        value = false
    elseif ContainsAny(text, {
        "right to left", "fill right", "fill backwards", "fill backward",
        "fills backwards", "fills backward", "reverse fill", "reverse direction",
        "fill reverse", "fill reversed", "other way",
    }) then
        value = true
    elseif ContainsAny(text, {
        "left to right", "fill left", "normal direction", "normal fill",
        "fill normal", "forward fill", "fill forward", "same direction",
    }) then
        value = false
    elseif ContainsAny(text, { "reverse", "reversed" }) then
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
    if ContainsAny(text, { "move", "nudge", "shift", "offset", "position" }) then return nil end
    if not ContainsAny(text, { "text", "number", "numbers", "font", "font size", "text size", "number size" }) then return nil end
    if not ContainsAny(text, { "size", "bigger", "larger", "smaller", "increase", "decrease", "raise", "reduce", "set", "make" }) then return nil end
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
    if ContainsAny(text, { "player hp", "player hp bar", "second hp", "duplicate hp" }) then return nil end
    if ContainsAny(text, {
        "text", "number", "numbers", "font", "outline", "border", "gap", "gaps", "spacing",
        "space", "spaces", "distance", "separator", "separators", "divider", "dividers", "tick",
        "ticks", "background", "opacity", "alpha", "texture",
    }) then return nil end
    if not ContainsAny(text, { "width", "wide", "wider", "narrower", "height", "tall", "taller", "shorter", "size", "bigger", "larger", "smaller" }) then return nil end
    local key
    local fallback
    if ContainsAny(text, { "width", "wide", "wider", "narrower" }) then
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

function A._ParseClassPowerSeparatorShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if not ContainsAny(text, { "separator", "separators", "divider", "dividers", "tick", "ticks" }) then return nil end
    if ContainsAny(text, { "gap", "gaps", "spacing", "space", "spaces", "distance", "text", "font" }) then return nil end
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
    if not ContainsAny(text, { "gap", "gaps", "spacing", "space", "spaces", "distance", "pip gap", "point gap" }) then return nil end
    if ContainsAny(text, { "text", "font", "outline", "border" }) then return nil end
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
    if not ContainsAny(text, { "background", "bg", "empty background" }) then return nil end
    if ContainsAny(text, { "color", "colour", "texture" }) then return nil end
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
        if bool == nil and ContainsAny(text, { "hide", "remove", "without", "no background" }) then bool = false end
        if bool == nil and ContainsAny(text, { "show", "enable", "turn on", "with background" }) then bool = true end
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

function A._ParseClassPowerMoveShortcut(text)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, { "text", "number", "font", "detached power", "alt mana", "alternative mana" }) then return nil end
    if not ContainsAny(text, { "move", "nudge", "shift", "verschiebe" }) then return nil end
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
    if ContainsAny(text, { "player hp", "player health", "second hp", "second player hp", "duplicate hp", "alt mana", "alternative mana" }) then return false end
    if ContainsAny(text, {
        "class resources player power", "class resource player power", "class power player power",
        "class resources player power bar", "class resource player power bar", "class power player power bar",
        "attached player power", "attached player power bar", "detached player power", "detached player power bar",
        "klassenressourcen spieler energie", "klassenressourcen spieler energieleiste",
    }) then
        return true
    end
    if HasClassPowerIntent(text) and ContainsAny(text, {
        "detached power", "detached power bar", "detached mana", "detached mana bar",
        "player power", "player power bar", "player mana", "player mana bar",
        "spieler energie", "spieler energieleiste", "abgekoppelte energie", "abgekoppelte energieleiste",
    }) then
        return true
    end
    if M and M.activeKey == "classpower" and ContainsAny(text, {
        "detached power", "detached power bar", "player power", "player power bar",
        "power area", "power section", "spieler energie", "energieleiste",
    }) then
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

    if ContainsAny(text, {
        "anchor to class", "anchor to class resource", "anchor to class resources",
        "anchor player power to class", "anchor player power bar to class",
        "anchor class resources player power", "anchor class resource player power", "anchor class power player power",
        "anchor class resources player power bar", "anchor class resource player power bar", "anchor class power player power bar",
        "player power to class resource", "player power to class resources", "player power bar to class resource",
        "power bar to class resource", "attached to class resource", "follow class resource",
        "an klassenressource ankern", "an klassenressourcen ankern",
    }) then
        key = "detachedPowerBarAnchorToClassPower"
        value = DetectBoolean(text)
        if value == nil then value = not ContainsAny(text, { "off", "disable", "disabled", "no", "not", "detach", "disconnect", "aus", "deaktivieren", "nicht" }) end
        change = PlayerChange(key, value)
    elseif ContainsAny(text, {
        "sync width", "sync to class", "sync with class", "match class resource width", "same width as class resource",
        "class resources player power sync", "class resources player power sync width",
        "class resources player power bar sync", "class resources player power bar sync width",
        "player power sync class resource", "player power bar sync class resource",
        "sync class resources player power", "sync class resources player power width",
        "sync class resources player power bar", "sync class resources player power bar width",
        "breite synchron", "gleiche breite",
    }) then
        key = "detachedPowerBarSyncClassPower"
        value = DetectBoolean(text)
        if value == nil then value = not ContainsAny(text, { "manual", "off", "disable", "disabled", "no", "not", "aus", "deaktivieren", "nicht" }) end
        change = PlayerChange(key, value)
    elseif ContainsAny(text, { "detach", "detached", "undock", "separate", "separated", "enable", "show", "attach", "reattach", "dock", "hide", "disable", "abkoppeln", "abgekoppelt", "ankoppeln", "anzeigen", "ausblenden" }) then
        key = "powerBarDetached"
        if ContainsAny(text, { "attach", "reattach", "dock", "ankoppeln" }) then
            value = false
        elseif ContainsAny(text, { "detach", "detached", "undock", "separate", "separated", "abkoppeln", "abgekoppelt" }) then
            value = true
        else
            value = DetectBoolean(text)
        end
        if value ~= nil then change = PlayerChange(key, value) end
    elseif ContainsAny(text, { "text on bar", "power text on bar", "text inside", "text auf leiste", "text in leiste" }) then
        key = "detachedPowerBarTextOnBar"
        value = DetectBoolean(text)
        if value == nil then value = true end
        change = PlayerChange(key, value)
    elseif ContainsAny(text, { "width", "wide", "wider", "narrower", "breite", "breiter", "schmaler" }) then
        change = NumberPlayerChange("detachedPowerBarWidth", text, 10)
    elseif ContainsAny(text, { "shape", "form", "orb", "round", "crystal", "bar", "follow class", "sphere", "kugel", "rund", "kristall" })
        and not ContainsAny(text, { "texture", "foreground", "background", "outline", "border", "color", "colour", "textur", "vordergrund", "hintergrund", "rahmen", "farbe" }) then
        key = "detachedPowerBarShape"
        local setting = PlayerSetting(key)
        value = setting and EnumValueForText(setting, text) or nil
        if value ~= nil then change = PlayerChange(key, value) end
    elseif ContainsAny(text, { "orb size", "sphere size", "kugel groesse", "orb groesse" }) then
        change = NumberPlayerChange("detachedPowerOrbSize", text, 4)
    elseif ContainsAny(text, { "text size", "font size", "power text size", "schriftgroesse", "textgroesse" }) then
        change = NumberPlayerChange("powerFontSize", text, 1)
    elseif ContainsAny(text, { "frame level", "framelevel", "layer", "strata", "ebene", "schicht" }) then
        change = NumberPlayerChange("detachedPowerBarFrameLevelOffset", text, 1)
    elseif ContainsAny(text, { "height", "tall", "higher", "lower", "hoehe", "hoeher", "niedriger" }) then
        change = NumberPlayerChange("detachedPowerBarHeight", text, 1)
    elseif direction or ContainsAny(text, { "x", "y", "offset", "move", "nudge", "shift", "verschiebe", "versatz", "position" }) then
        local axis
        if ContainsAny(text, { "x", "x offset", "offset x", "horizontal", "x versatz" }) then axis = "x" end
        if ContainsAny(text, { "y", "y offset", "offset y", "vertical", "y versatz" }) then axis = "y" end
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
        if ContainsAny(text, spec.terms) then return spec end
    end
    if M and M.activeKey == "gameplay" then
        for i = 1, #specs do
            local spec = specs[i]
            if ContainsAny(text, spec.pageTerms) then return spec end
        end
        if ContainsAny(text, { "timer" }) and not ContainsAny(text, { "enter", "leave", "state" }) then
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
        if ContainsAny(text, { "unlock", "unlocked" }) then
            value = false
        elseif ContainsAny(text, { "clickable", "mouse input on", "enable mouse input", "accept clicks" }) and tostring(key):find("ClickThrough", 1, true) then
            value = false
        elseif ContainsAny(text, { "lock", "locked", "click through", "click-through", "sync", "same", "ready", "icon", "cooldown swipe" }) then
            value = true
        end
    end
    if value == nil then return nil end
    if not key then
        if ContainsAny(text, { "anchor", "attach", "size", "groesse", "grosse", "font", "duration", "dauer", "offset", "position", "move", "verschiebe", "x", "y", "thickness", "thick", "thin", "dicke", "staerke", "spell", "zauber" }) then
            return nil
        end
        key = spec.enable
    end
    return A._GameplayShortcutChange(key, value, nil, nil, spec.label, "Toggles a Gameplay option.")
end

function A._ParseGameplayAnchorShortcut(text)
    if not ContainsAny(text, { "anchor", "attach", "attached", "from point", "to point", "anker", "ankerpunkt", "anhaengen", "anhaengen an", "von punkt", "zu punkt" }) then return nil end
    local spec = A._GameplayShortcutSpec(text)
    if not spec then return nil end
    local key
    if spec.id == "combatTimer" then
        key = spec.anchor
    elseif spec.id == "playerTotems" then
        if ContainsAny(text, { "from anchor", "anchor from", "from point", "von anker", "anker von", "von punkt" }) then
            key = spec.anchorFrom
        elseif ContainsAny(text, { "to anchor", "anchor to", "to point", "attach to", "zu anker", "anker zu", "zu punkt", "anhaengen an" }) then
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

function A._ParseGameplayNumberShortcut(text)
    local spec = A._GameplayShortcutSpec(text)
    if not spec then return nil end
    if ContainsAny(text, { "spell", "spell id", "range check spell" }) then return nil end
    local key
    if spec.id == "combatState" and ContainsAny(text, { "duration", "time visible", "visible time", "dauer", "anzeigedauer", "sichtbar dauer" }) then
        key = spec.duration
    elseif spec.id == "combatCrosshair" and ContainsAny(text, { "thickness", "thick", "thicker", "thin", "thinner", "dicke", "staerke", "strichstaerke", "duenner", "dunner" }) then
        key = spec.thickness
    elseif ContainsAny(text, { "size", "font size", "text size", "icon size", "bigger", "larger", "smaller", "grow", "shrink", "groesse", "grosse", "groesser", "kleiner" }) then
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
    if ContainsAny(text, { "under", "below", "beneath", "bottom of", "unter", "darunter" }) then return "below" end
    if ContainsAny(text, { "above", "over", "top of", "ueber", "darueber", "oben" }) then return "above" end
    if ContainsAny(text, { "left of", "to the left of", "links von" }) then return "left" end
    if ContainsAny(text, { "right of", "to the right of", "rechts von" }) then return "right" end
    if ContainsAny(text, { "center on", "centered on", "middle of", "zentriert", "mitte" }) then return "center" end
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
    if not ContainsAny(text, { "move", "place", "put", "position", "set", "verschiebe", "stelle", "setze" }) then return nil end
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
    local movementIntent = ContainsAny(text, { "move", "nudge", "shift", "verschiebe", "offset", "position", "x", "y", "horizontal", "vertical" }) or (direction and FirstNumber(text) ~= nil)
    if not movementIntent then return nil end
    local spec = A._GameplayShortcutSpec(text)
    if not spec then return nil end
    local axis
    if ContainsAny(text, { "x", "x offset", "offset x", "horizontal" }) then axis = "x" end
    if ContainsAny(text, { "y", "y offset", "offset y", "vertical" }) then axis = "y" end
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
    if not ContainsAny(text, { "font color", "text color", "global font color", "schriftfarbe", "textfarbe" }) then return nil end
    if ContainsAny(text, {
            "castbar", "combat", "aura", "stack", "cooldown", "power", "hp", "health",
            "name", "boss target", "mouseover", "dispel", "bar", "npc", "portrait",
        })
        and not ContainsAny(text, { "global", "main", "default" })
    then
        return nil
    end
    if ContainsAny(text, { "reset", "default", "palette", "zuruecksetzen" }) then
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
    for i = 1, 7 do
        local token = "COMBO_POINTS_" .. tostring(i)
        Consider(token, "combo point " .. tostring(i))
        Consider(token, "combo point slot " .. tostring(i))
        Consider(token, "cp " .. tostring(i))
    end
    return bestToken
end

function A._ParseClassPowerColorShortcut(text, raw)
    if not HasClassPowerIntent(text) then return nil end
    if ContainsAny(text, { "reset", "default", "defaults", "restore", "zuruecksetzen" }) then return nil end
    local token = ClassPowerColorTokenForText(text)
    if not token then return nil end
    local r, g, b, label = ExtractColor(raw, text)
    if not r then return nil end
    local background = ContainsAny(text, { "background", "bg", "backdrop" })
    local key = (background and "general.classPowerBgColorOverrides." or "general.classPowerColorOverrides.") .. token
    local setting = ClassPowerSetting(key)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = { r = r, g = g, b = b, label = label } } },
        label = background and "Class Resource Background Color" or "Class Resource Color",
        summary = "Changes a Class Resource foreground or background color.",
    }
end

local function ParseColorAction(text)
    if not ContainsAny(text, { "reset", "default", "defaults", "restore", "zuruecksetzen" }) then return nil end
    if not ContainsAny(text, { "color", "colors", "colour", "colours", "farbe", "farben", "tint" }) then return nil end
    if ContainsAny(text, {
        "combo point slot", "combo point slots", "combo slot", "combo slots",
        "combo point colors", "combo colors", "all combo point colors",
    }) then
        local action = Registry and Registry:GetAction("reset_class_power_combo_slot_colors")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Reset combo point slot colors",
            summary = "Resets the custom Class Resource combo point slot colors.",
        } or nil
    end
    local powerToken = PowerColorTokenForText(text)
    if powerToken
        and ContainsAny(text, { "power color", "power bar", "powerbar", "resource color", "resource bar", "mana color", "rage color", "energy color", "runic power", "astral power", "maelstrom color" })
        and not ContainsAny(text, { "class power", "class resource", "combo point", "combo points", "holy power", "soul shard", "soul shards", "chi", "arcane charge", "arcane charges", "runes" })
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
    if cpToken and ContainsAny(text, {
        "class power", "class resource", "resource", "combo", "holy power", "soul", "soul shard",
        "maelstrom", "astral", "arcane charge", "arcane charges", "eclipse", "stagger",
        "icicles", "ebon", "whirlwind", "tip of the spear", "insanity", "runes", "chi", "essence",
    }) then
        local action = Registry and Registry:GetAction("reset_class_power_color_token")
        return action and {
            kind = "action",
            action = action,
            args = { token = cpToken, background = ContainsAny(text, { "background", "bg" }) },
            label = "Reset class resource color",
            summary = "Resets a single Class Resource foreground or background color.",
        } or nil
    end
    if ContainsAny(text, { "castbar", "cast bar" }) then
        return BuildColorResetAction("reset_castbar_colors", "Reset cast bar colors", "Resets cast bar colors through the existing Colors page state.")
    end
    if ContainsAny(text, { "npc type", "npc role" }) then
        return BuildColorResetAction("reset_npc_type_colors", "Reset NPC type colors", "Resets NPC type colors.")
    end
    if ContainsAny(text, { "unitframe", "unit frame", "npc reaction", "reaction color" }) then
        return BuildColorResetAction("reset_unitframe_colors", "Reset unit frame colors", "Resets unit frame NPC reaction colors.")
    end
    if ContainsAny(text, { "bar background", "background tint", "bar tint" }) then
        return BuildColorResetAction("reset_bar_background_color", "Reset bar background tint", "Resets the global bar background tint.")
    end
    if ContainsAny(text, { "bar color", "bar colors", "absorb", "aggro", "purge", "outline", "border" }) then
        return BuildColorResetAction("reset_bar_colors", "Reset bar colors", "Resets bar overlay and border colors.")
    end
    if ContainsAny(text, { "dispel", "debuff type" }) then
        return BuildColorResetAction("reset_dispel_colors", "Reset dispel colors", "Resets dispel border and debuff-type colors.")
    end
    if ContainsAny(text, { "gameplay", "combat timer", "combat state", "crosshair" }) then
        return BuildColorResetAction("reset_gameplay_colors", "Reset gameplay colors", "Resets Gameplay color options.")
    end
    if ContainsAny(text, { "aura", "auras", "buff", "debuff", "pandemic" }) then
        return BuildColorResetAction("reset_aura_colors", "Reset aura colors", "Resets Aura color options.")
    end
    if ContainsAny(text, { "portrait" }) then
        return BuildColorResetAction("reset_portrait_colors", "Reset portrait colors", "Resets portrait color options.")
    end
    if ContainsAny(text, { "resource", "power color", "class power", "class resource", "combo point" }) then
        return BuildColorResetAction("reset_resource_colors", "Reset resource colors", "Resets power and class-resource color overrides.")
    end
    if ContainsAny(text, { "class color", "class colors", "class bar" }) then
        return BuildColorResetAction("reset_class_colors", "Reset class bar colors", "Resets class bar color overrides.")
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

    local directChangeIntent = ContainsAny(text, {
        "turn on", "turn off", "enable", "disable", "show", "hide", "set", "make",
        "move", "put", "send", "bring", "increase", "decrease", "raise", "lower",
        "an", "aus", "einschalten", "ausschalten", "aktivieren", "deaktivieren",
        "einblenden", "ausblenden", "zeige", "anzeigen", "verstecke", "setze",
        "stelle", "mach", "mache", "verschiebe", "erhoehe", "reduziere", "senke",
    })
    local explicitTroubleIntent = ContainsAny(text, {
        "diagnose", "diagnostic", "troubleshoot", "why", "wieso", "warum",
        "diagnostik", "diagnosebericht", "fehlersuche", "fehleranalyse",
        "not showing", "not visible", "not appearing", "not displayed", "not there",
        "doesnt show", "does not show", "doesnt appear", "does not appear",
        "cant see", "can't see", "cannot see", "can not see", "missing", "hidden", "invisible",
        "filtered out", "filtered", "blacklisted", "blocked",
        "disappeared", "disappear", "gone", "vanished", "broken", "not working", "doesnt work",
        "does not work", "won't work", "wont work", "fails", "failed", "failure", "error", "errors", "stuck",
        "nicht sichtbar", "zeigt nicht", "verschwunden", "kaputt", "haengt",
        "fehlt", "versteckt", "unsichtbar", "funktioniert nicht", "geht nicht", "fehler",
    })
    if directChangeIntent and not explicitTroubleIntent then return nil end
    if not ContainsAny(text, {
        "diagnose", "diagnostic", "troubleshoot", "why", "wieso", "warum",
        "diagnostik", "diagnosebericht", "fehlersuche", "fehleranalyse",
        "pruefe", "pruefen", "ueberpruefe", "ueberpruefen", "checke", "check",
        "not showing", "not visible", "not appearing", "not displayed", "not there",
        "doesnt show", "does not show", "doesnt appear", "does not appear",
        "cant see", "can't see", "cannot see", "can not see", "missing", "hidden", "invisible",
        "filtered out", "filtered", "blacklisted", "blocked",
        "disappeared", "disappear", "gone", "vanished", "broken", "not working", "doesnt work",
        "does not work", "won't work", "wont work", "fails", "failed", "failure", "error", "errors", "stuck",
        "nicht sichtbar", "zeigt nicht", "verschwunden", "kaputt", "haengt",
        "fehlt", "versteckt", "unsichtbar", "funktioniert nicht", "geht nicht", "fehler",
    }) then return nil end
    if ContainsAny(text, {
        "profile mapping", "profile mappings", "spec profile mapping", "spec profile mappings",
        "broken profile mapping", "broken profile mappings", "broken spec mapping", "broken spec mappings",
    }) and ContainsAny(text, { "fix", "repair", "clear", "remove", "delete", "loeschen", "reparieren", "beheben" }) then
        return nil
    end
    local gameplayFeature
    if ContainsAny(text, { "combat timer", "kampf timer", "kampftimer" }) then
        gameplayFeature = "combatTimer"
    elseif ContainsAny(text, { "combat enter", "combat leave", "combat state", "combat text", "enter leave", "kampf text", "kampfanzeige" }) then
        gameplayFeature = "combatState"
    elseif ContainsAny(text, { "totem", "totem frame", "statue", "statue frame" }) then
        gameplayFeature = "playerTotems"
    elseif ContainsAny(text, { "crosshair", "combat crosshair", "fadenkreuz" }) then
        gameplayFeature = "combatCrosshair"
    elseif ContainsAny(text, { "gameplay", "gameplay helper", "gameplay helpers", "spielhilfe", "spielhilfen" }) then
        gameplayFeature = "all"
    elseif M and M.activeKey == "gameplay" and ContainsAny(text, { "timer", "helper", "helpers", "not visible", "missing", "hidden", "nicht sichtbar" }) then
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
    if ContainsAny(text, { "profile", "profiles", "profil", "profile import", "profile export", "spec profile", "profil import", "profil export", "spec profil" }) then
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
        or ContainsAny(text, { "class resource", "class resources", "class power", "class bar", "resource bar", "combo point", "combo points", "holy power", "soul shard", "soul shards", "rune", "runes" })
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
    if ContainsAny(text, { "aura", "auras", "buff", "buffs", "debuff", "debuffs" }) then
        local groups = DetectGroups(text)
        local units = DetectUnits(text)
        local scope = groups[1] or units[1] or "target"
        if scope == "targettarget" or scope == "focustarget" or scope == "pet" then scope = "target" end
        local lane
        if ContainsAny(text, { "debuff", "debuffs" }) then lane = "debuff" elseif ContainsAny(text, { "buff", "buffs" }) then lane = "buff" end
        local action = Registry and Registry:GetAction("diagnose_aura_visibility")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope, lane = lane },
            label = "Check Auras",
            summary = "Checks Aura visibility options and suggests clear next steps.",
        } or nil
    end
    if ContainsAny(text, { "castbar", "zauberleiste" }) then
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
    if ContainsAny(text, { "detached power", "detached power bar", "power bar", "powerbar", "resource bar" }) then
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
    if ContainsAny(text, { "how", "where", "where can", "where do", "help", "explain", "what", "which" })
        and ContainsAny(text, {
            "ready check", "readycheck", "status icon", "status icons", "indicator", "indicators",
            "role icon", "leader icon", "assist icon", "summon icon", "phase icon", "pvp icon",
            "war mode", "spell indicator", "corner indicator", "raid marker",
        })
        and (#groups > 0 or ContainsAny(text, { "group frames", "party frames", "raid frames", "mythic raid frames" }))
    then
        local action = Registry and Registry:GetAction("assistant_scope_help")
        return action and {
            kind = "action",
            action = action,
            args = { page = "gf_indicators", frameType = "group" },
            label = "Group Indicators help",
            summary = "Shows Group Indicator help instead of running a visibility diagnosis.",
        } or nil
    end
    if #groups > 0 or ContainsAny(text, { "group frames", "gruppenframes", "party frames", "raid frames", "mythic raid frames" }) then
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
    if ContainsAny(text, { "dashboard", "assistant", "menu", "menu2", "setup", "assistant setup", "menu setup", "navigation", "page stack", "workflow", "setup checklist", "guided setup", "assistent", "menue", "einrichtung", "setup checkliste" })
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
    if ContainsAny(text, {
        "help me setup", "help me set up", "help me configure", "help me build",
        "guide me", "setup guide", "guided setup", "start guide", "start tour",
    }) then
        return false
    end
    if ContainsAny(text, {
        "what can i change", "what can change", "what settings can i change",
        "what can i do here", "what can i change here", "commands for",
        "show commands for", "help for", "help with", "help me with",
        "what can i do on this page", "what can i do on current page",
        "what can i change on this page", "what can i change on current page",
        "explain this page", "explain current page", "page help",
        "help on this page", "help for this page", "commands on this page",
        "how can i configure this page", "how do i configure this page",
        "how can i use this page",
    }) then
        return true
    end
    if not page and not ContainsAny(text, { "edit mode", "editmode" }) then return false end
    if ContainsAny(text, {
        "help", "hilfe", "explain", "erklaere", "what is", "what are", "what can",
        "commands", "command examples",
    }) then
        return true
    end
    if page and ContainsAny(text, { "how", "how do", "how can", "how to", "where", "where do", "where can", "where is" })
        and ContainsAny(text, {
            "change", "set", "make", "move", "hide", "show", "turn on", "turn off", "enable", "disable",
            "configure", "adjust", "bigger", "larger", "smaller", "wider", "taller", "lock", "unlock",
        })
    then
        return true
    end
    return page == "profiles" and ContainsAny(text, { "how", "how do", "how to", "why" })
end

local function ParseScopedHelp(text)
    local action = Registry and Registry:GetAction("assistant_scope_help")
    if not action then return nil end
    local page, label = PageForText(text)
    local editModeHelp = ContainsAny(text, { "edit mode", "editmode" })
        and ContainsAny(text, { "help", "hilfe", "explain", "erklaere", "what is", "what can", "how", "how do", "how to", "commands" })
    if not HasScopedHelpIntent(text, page) and not editModeHelp then return nil end
    if not page and ContainsAny(text, { "here", "current page", "this page" }) then
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
        frameType = ContainsAny(text, { "aura", "auras", "buff", "debuff" }) and "groupAura" or "group"
        label = GroupDisplayLabel(group)
    elseif unit then
        frameType = ContainsAny(text, { "castbar", "cast bar" }) and "castbar" or "unitframe"
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
    if ContainsAny(text, { "discord", "discord link", "support discord" }) then return "discord" end
    if ContainsAny(text, { "patreon", "patreon link" }) then return "patreon" end
    if ContainsAny(text, { "paypal", "pay pal", "paypal link" }) then return "paypal" end
    if ContainsAny(text, { "ko fi", "kofi", "ko-fi" }) then return "kofi" end
    if ContainsAny(text, { "github", "repository", "repo link" }) then return "github" end
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
    return ContainsAny(text, {
        "boss preview", "boss previews", "boss frame preview", "boss frame previews",
        "boss frames preview", "boss frames previews", "boss unit preview",
        "boss unit previews", "boss unitframe preview", "boss unitframe previews",
        "boss unit frame preview", "boss unit frame previews", "boss vorschau",
        "boss frames vorschau", "boss frame vorschau",
    }) and not ContainsAny(text, {
        "castbar", "cast bar", "castbars", "cast bars", "zauberleiste",
        "boss target", "target border", "target highlight",
    })
end

local function ParseBossFramePreviewShortcut(text)
    if not IsBossFramePreviewText(text) then return nil end
    return EditModeAction("assistant.action.editMode.bossPreview", { value = DetectBoolean(text) }, "Set Boss Frames Preview", "Shows or hides the Boss Frames unit preview outside encounters.")
end

local function GroupPreviewScopeForText(text)
    if ContainsAny(text, { "mythic raid", "mythicraid", "mythic raid frame", "mythic raid frames", "mythicraid frame", "mythicraid frames" }) then
        return "mythicraid"
    end
    if ContainsAny(text, { "raid", "raid frame", "raid frames", "raidframe", "raidframes", "schlachtzug" }) then
        return "raid"
    end
    if ContainsAny(text, { "party", "party frame", "party frames", "partyframe", "partyframes", "gruppe" }) then
        return "party"
    end
    local groups = DetectGroups(text)
    return groups and groups[1] or nil
end

local function HasEditModeHUDControlIntent(text)
    if not HasEditModeContext(text) then return false end
    return ContainsAny(text, {
        "preview", "previews", "aura", "auras", "group preview", "group previews",
        "party preview", "party previews", "raid preview", "raid previews",
        "mythic raid preview", "mythic raid previews", "snap", "snapping",
        "grid", "grid lines", "grid spacing", "grid size", "raster", "raster groesse", "raster abstand",
        "rasterlinien", "hilfsraster", "background opacity",
        "background alpha", "bg opacity", "bg alpha", "background overlay",
        "hintergrund transparenz", "hintergrund deckkraft", "hintergrund overlay",
        "cdm", "cooldown manager", "anchor picker", "pick anchor", "select anchor",
        "ankerwahl", "anker auswahl", "reset", "undo", "redo",
    })
end

local function ParseEditModeHUDControl(text)
    local hasEditContext = HasEditModeContext(text)
    local previewWord = ContainsAny(text, { "preview", "previews", "preview mode", "preview modes", "vorschau", "platzhalter", "testdaten" })
    local hasExplicitAuraPreview = ContainsAny(text, {
        "preview auras", "preview aura", "preview aura icons", "preview auras icons",
        "aura preview", "aura previews", "aura icon preview", "aura icon previews", "aura icons",
        "aura preview icons", "aura mover", "aura movers", "aura mover boxes",
        "auren vorschau", "vorschau auren", "auren symbole", "auren icons",
        "auren platzhalter", "aura platzhalter",
    }) and (hasEditContext or previewWord or ContainsAny(text, { "mover", "movers", "vorschau", "toggle", "umschalten" }))
    local hasAuraPreview = hasExplicitAuraPreview
        or (hasEditContext and ContainsAny(text, { "auras", "aura", "auren" }) and (previewWord or DetectBoolean(text) ~= nil or ContainsAny(text, { "toggle", "umschalten" })))
    local hasGroupPreview = ContainsAny(text, {
        "gf preview", "gf previews", "group frame preview", "group frame previews",
        "group frames preview", "group frames previews", "group preview", "group previews",
        "party frame preview", "party frame previews", "party frames preview",
        "party frames previews", "party preview", "party previews",
        "raid frame preview", "raid frame previews", "raid frames preview",
        "raid frames previews", "raid preview", "raid previews",
        "mythic raid frame preview", "mythic raid frame previews",
        "mythic raid frames preview", "mythic raid frames previews",
        "mythic raid preview", "mythic raid previews",
        "party raid preview", "party raid previews", "gruppenframes preview",
        "gruppenframes previews", "gruppen preview", "gruppen previews",
        "gruppenframes vorschau", "gruppen vorschau", "gruppe vorschau",
        "party vorschau", "raid vorschau", "schlachtzug vorschau",
    }) or (hasEditContext and previewWord and ContainsAny(text, {
        "gf", "group frame", "group frames", "party", "party frame", "party frames",
        "raid", "raid frame", "raid frames", "mythic raid", "mythicraid",
    }))
        or (hasEditContext and ContainsAny(text, { "gf" }) and (DetectBoolean(text) ~= nil or ContainsAny(text, { "toggle", "umschalten" })))
    local hasBossPreview = previewWord and IsBossFramePreviewText(text)
    local hasUnitPreview = ContainsAny(text, {
        "edit mode preview", "edit mode previews", "unit preview", "unit previews",
        "unit frame preview", "unit frame previews", "unitframe preview", "unitframe previews",
        "preview frames", "preview frame", "frame preview", "frame previews",
        "mover preview", "mover previews", "placeholder data", "placeholder frame",
        "placeholder frames", "preview placeholders", "fake frame", "fake frames",
        "test frame", "test frames", "vorschau frames", "frame vorschau",
        "platzhalter", "platzhalter frames", "testdaten", "vorschau daten",
    }) or (hasEditContext and previewWord and not hasAuraPreview and not hasGroupPreview)
    local hasSnap = ContainsAny(text, {
        "snap", "snapping", "grid snap", "snap frames", "snap to grid", "einrasten",
        "raster snap", "raster einrasten", "am raster ausrichten", "einrasten am raster", "rasterfang",
    })
    local hasGrid = (hasEditContext and ContainsAny(text, {
        "grid", "grid line", "grid lines", "grid overlay", "grid overlays",
        "edit mode grid", "raster", "raster lines", "rasterlinien", "hilfsraster",
    })) or ContainsAny(text, { "edit mode grid", "msuf edit mode grid", "grid lines in edit mode", "raster groesse", "raster abstand", "rasterweite", "rasterlinien im bearbeitungsmodus" })
    local hasGridStep = hasGrid and FirstNumber(text) ~= nil and ContainsAny(text, {
        "grid", "grid spacing", "grid size", "grid step", "spacing", "space",
        "size", "groesse", "abstand", "rasterweite", "step", "pixel", "pixels", "px",
    })
    local hasBackgroundOpacity = (hasEditContext and ContainsAny(text, {
        "background opacity", "background alpha", "bg opacity", "bg alpha",
        "background overlay", "overlay opacity", "edit mode background", "edit mode bg",
        "hintergrund transparenz", "hintergrund deckkraft", "hintergrund alpha", "overlay transparenz",
    })) or ContainsAny(text, { "edit mode background opacity", "edit mode bg opacity", "bearbeitungsmodus hintergrund transparenz", "bearbeitungsmodus hintergrund deckkraft" })
    local hasCDM = ContainsAny(text, {
        "cdm", "cooldown manager", "essential cooldown manager", "anchor to cooldown",
        "cooldown anchor", "cooldown manager anchor", "cooldownmanager", "cooldownmanager anker", "cdm anker",
    })
    local hasAnchorPicker = ContainsAny(text, {
        "anchor picker", "global anchor picker", "pick anchor", "select anchor",
        "choose anchor", "open anchor", "anker picker", "anker auswahl", "anker auswaehlen",
        "anker waehlen", "ankerwahl", "anker waehler",
    }) and not ContainsAny(text, {
        "custom anchor", "custom anchor picker", "custom anchor frame", "anchor frame picker",
        "status", "active", "is picker", "show picker",
    })
        and (hasEditContext or ContainsAny(text, { "global anchor picker", "anchor picker", "anker picker", "anker auswahl" }))
    local hasResetPosition = hasEditContext and ContainsAny(text, { "reset", "restore", "default", "zuruecksetzen", "zurucksetzen" })
        and ContainsAny(text, { "position", "selected frame", "current frame", "selected", "selection", "frame position", "mover", "auswahl", "ausgewaehlter frame", "aktueller frame", "rahmen position" })
    local hasUndo = hasEditContext and ContainsAny(text, {
        "edit mode undo", "undo edit mode", "undo in edit mode", "undo last edit mode",
        "undo edit mode position", "undo last position", "undo position change",
        "undo last change", "undo edit mode change", "rueckgaengig", "rueckgaengig machen", "position rueckgaengig", "bearbeitungsmodus rueckgaengig",
    })
    local hasRedo = hasEditContext and ContainsAny(text, {
        "edit mode redo", "redo edit mode", "redo in edit mode", "redo last edit mode",
        "redo edit mode position", "redo last position", "redo position change",
        "redo last change", "redo edit mode change", "wiederholen", "erneut anwenden", "bearbeitungsmodus wiederholen",
    })

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
    if hasSnap and (hasEditContext or ContainsAny(text, { "snap frames", "grid snap", "snap to grid", "raster snap", "raster einrasten" })) then
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
        return EditModeAction("assistant.action.editMode.backgroundOpacity", { value = number }, "Set Edit Mode Background opacity")
    end
    if hasCDM and hasEditContext then
        return EditModeAction("assistant.action.editMode.cdm", { value = value }, "Set Edit Mode CDM Anchor")
    end
    return nil
end

local function ParseSupportWorkflow(text)
    if ContainsAny(text, {
        "clear no match telemetry", "clear nomatch telemetry", "clear assistant no match telemetry",
        "reset no match telemetry", "reset nomatch telemetry", "reset assistant misses",
        "clear unmatched commands", "clear missed commands",
        "loesche unbekannte befehle", "loesche nicht erkannte befehle",
        "leere nomatch telemetry", "leere no match telemetry", "assistant misses loeschen",
    }) then
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
        if ContainsAny(value, { "all no match", "all nomatch", "all missed", "all unmatched" }) then return nil end
        if ContainsAny(value, { "aura action", "aura actions", "aura workflow", "aura workflows" }) then return "aura-action/backend" end
        if ContainsAny(value, { "aura", "auras", "buff", "buffs", "debuff", "debuffs" }) then return "aura-registry/backend" end
        if ContainsAny(value, { "anchor", "anchors", "anchoring", "cooldownmanager", "cooldown manager", "cdm" }) then return "anchor-intent" end
        if ContainsAny(value, { "registry", "registry alias", "aliases", "alias", "setting", "settings", "intent metadata" }) then return "registry-alias" end
        if ContainsAny(value, { "media", "font", "texture", "sound", "sharedmedia" }) then return "media-alias" end
        if ContainsAny(value, { "knowledge", "help", "search", "faq", "where", "explain" }) then return "knowledge/help" end
        if ContainsAny(value, { "action", "actions", "workflow", "workflows", "copy", "profile", "preset" }) then return "action-parser" end
        if ContainsAny(value, { "parser", "triage", "generic" }) then return "parser-or-help" end
        return nil
    end

    local function NoMatchResolutionFilterForText(value)
        if ContainsAny(value, { "all no match", "all nomatch", "all missed", "all unmatched" }) then return nil end
        if ContainsAny(value, { "unresolved", "open no match", "open nomatch", "open misses", "not resolved", "still failing" }) then return "unresolved" end
        if ContainsAny(value, { "needs clarification", "needs-clarification", "ambiguous no match", "ambiguous nomatch" }) then return "needs-clarification" end
        if ContainsAny(value, { "resolved", "fixed no match", "fixed nomatch", "solved no match", "covered no match" }) then return "resolved" end
        return nil
    end

    local function NoMatchPriorityFilterForText(value)
        if ContainsAny(value, { "all no match", "all nomatch", "all missed", "all unmatched" }) then return nil end
        if ContainsAny(value, { "high priority", "high-priority", "urgent no match", "urgent nomatch", "top priority", "top misses" }) then return "high" end
        if ContainsAny(value, { "medium priority", "medium-priority", "normal priority" }) then return "medium" end
        if ContainsAny(value, { "low priority", "low-priority", "minor no match", "minor nomatch" }) then return "low" end
        return nil
    end

    local function NoMatchTagFilterForText(value)
        if ContainsAny(value, { "all no match", "all nomatch", "all missed", "all unmatched" }) then return nil end
        if ContainsAny(value, { "uncategorized", "untagged" }) then return "uncategorized" end
        if ContainsAny(value, { "geometry tag", "geometry tagged", "geometry no match", "geometry misses", "movement no match", "movement misses", "layout no match", "layout misses" }) then return "geometry" end
        if ContainsAny(value, { "media tag", "media tagged", "media no match", "media misses", "texture no match", "texture misses", "font no match", "font misses" }) then return "media" end
        if ContainsAny(value, { "setting tag", "setting tagged", "setting no match", "setting misses", "control no match", "control misses" }) then return "setting" end
        if ContainsAny(value, { "scope tag", "scope tagged", "scope no match", "scope misses", "unit no match", "unit misses", "frame no match", "frame misses" }) then return "scope" end
        if ContainsAny(value, { "aura tag", "aura tagged", "aura no match", "aura misses", "buff no match", "debuff no match" }) then return "aura" end
        if ContainsAny(value, { "anchor tag", "anchor tagged", "anchor no match", "anchor misses" }) then return "anchor" end
        if ContainsAny(value, { "action tag", "action tagged", "action no match", "action misses", "workflow no match", "workflow misses" }) then return "action" end
        if ContainsAny(value, { "knowledge tag", "knowledge tagged", "knowledge no match", "knowledge misses", "help no match", "help misses" }) then return "knowledge" end
        return nil
    end

    if ContainsAny(text, {
        "no match worklist", "nomatch worklist", "assistant no match worklist",
        "assistant learning worklist", "learning worklist", "missed command worklist",
        "unmatched command worklist", "unmatched wording worklist",
        "alias review worklist", "alias worklist", "registry alias worklist",
        "registry alias candidates", "registry review candidates",
        "anchor review candidates", "anchor no match worklist", "anchor nomatch worklist",
        "aura review candidates", "aura no match worklist", "aura nomatch worklist",
        "knowledge review candidates", "knowledge no match worklist", "knowledge nomatch worklist",
        "media review candidates", "media no match worklist", "media nomatch worklist",
        "action review candidates", "action no match worklist", "action nomatch worklist",
        "geometry review candidates", "geometry no match worklist", "geometry nomatch worklist",
        "scope review candidates", "scope no match worklist", "scope nomatch worklist",
        "tagged no match worklist", "tagged nomatch worklist", "tagged misses",
        "show learning candidates", "show review candidates", "show alias candidates",
        "unbekannte befehle arbeitsliste", "nicht erkannte befehle arbeitsliste",
        "assistant arbeitsliste", "alias arbeitsliste", "fehlende aliases",
        "zeige unbekannte befehle", "zeige nicht erkannte befehle",
    }) then
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

    if ContainsAny(text, {
        "no match telemetry", "nomatch telemetry", "assistant no match telemetry",
        "assistant misses", "assistant missed commands", "missed commands",
        "unmatched commands", "unmatched wording", "show no match", "show nomatch",
        "assistant learning report", "learning report", "no match report",
        "unbekannte befehle", "nicht erkannte befehle", "nicht erkannte eingaben",
        "assistant lernbericht", "no match bericht", "nomatch bericht",
    }) then
        local action = Registry and Registry:GetAction("assistant_nomatch_telemetry")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show Assistant phrases to improve",
            summary = "Shows stored phrases that still need better Assistant answers.",
        } or nil
    end

    if ContainsAny(text, {
        "msuf status", "assistant status", "status report", "diagnostic report",
        "run checks", "run check", "run diagnostics", "health check", "run health check",
        "assistant support text", "support text", "support report", "support summary", "build support text", "make support text",
        "diagnostics", "diagnose", "diagnosen", "diagnose starten", "diagnosebericht", "debug summary", "debug report", "debug info", "debug bericht", "status bericht",
        "diagnostik", "fehlerbericht", "statusbericht", "diagnostik bericht",
        "assistant debug report", "version info", "locale info",
        "assistant performance", "assistant timing", "assistant slow",
        "is the assistant slow", "performance report", "perf report", "lag report",
        "assistant leistung", "assistant langsam", "performance bericht", "lag bericht",
    }) then
        local action = Registry and Registry:GetAction("assistant_status")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show MSUF status",
            summary = "Shows read-only MSUF and Assistant details.",
        } or nil
    end

    if text == "help" or text == "hilfe" or ContainsAny(text, {
        "assistant help", "command help", "commands help", "help commands",
        "print help", "show help", "what can you do", "what settings can you change",
        "command examples",
    }) then
        local action = Registry and Registry:GetAction("assistant_help")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show Assistant help",
            summary = "Shows Assistant examples handled locally by MSUF.",
        } or nil
    end

    local editModeControl = ParseEditModeHUDControl(text)
    if editModeControl then return editModeControl end

    if ContainsAny(text, {
        "edit mode", "editmode", "msuf edit mode", "bearbeitungsmodus", "bearbeitungs modus",
        "editmodus", "move frames", "drag frames", "position frames", "frames verschieben",
        "rahmen verschieben", "frames bewegen", "rahmen bewegen",
    }) then
        local actionKey
        local label
        local args = {}
        if ContainsAny(text, {
            "am i in edit mode", "is edit mode on", "is edit mode active", "edit mode status", "bearbeitungsmodus status", "ist bearbeitungsmodus an", "ist edit mode an",
            "why can't i exit edit mode", "why cant i exit edit mode", "why can not i exit edit mode",
            "why can't leave edit mode", "why cant leave edit mode",
            "bin ich im bearbeitungsmodus", "ist der bearbeitungsmodus aktiv", "ist editmodus aktiv",
            "warum kann ich bearbeitungsmodus nicht verlassen", "warum kann ich bearbeitungsmodus nicht beenden",
        }) then
            actionKey = "assistant.diagnostic.editMode.status"
            label = "Show MSUF Edit Mode status"
            if ContainsAny(text, { "why can't", "why cant", "why can not", "warum kann" }) then args.reason = "why_exit" end
        elseif ContainsAny(text, { "cancel edit mode", "discard edit mode", "cancel msuf edit mode", "cancel all edit mode", "bearbeitungsmodus abbrechen", "edit mode abbrechen", "bearbeitungsmodus verwerfen", "editmodus abbrechen" }) then
            actionKey = "assistant.action.editMode.cancel"
            label = "Cancel MSUF Edit Mode"
        elseif ContainsAny(text, { "toggle edit mode", "toggle msuf edit mode", "bearbeitungsmodus umschalten", "edit mode umschalten", "editmodus umschalten", "bearbeitungsmodus toggeln" }) then
            actionKey = "assistant.action.editMode.toggle"
            label = "Toggle MSUF Edit Mode"
        elseif ContainsAny(text, {
            "stop edit mode", "exit edit mode", "exit msuf edit mode", "leave edit mode", "leave msuf edit mode",
            "close edit mode", "close msuf edit mode", "disable edit mode", "turn off edit mode", "edit mode off", "edit mode aus", "bearbeitungsmodus aus", "bearbeitungsmodus beenden", "bearbeitungsmodus verlassen", "bearbeitungsmodus deaktivieren",
            "editmodus aus", "editmodus beenden", "editmodus verlassen", "rahmen verschieben beenden",
        }) then
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

    if ContainsAny(text, { "wago backup", "profile backup confirmed", "backup confirmed" }) then
        local clear = ContainsAny(text, { "clear", "reset", "unconfirm", "not confirmed" })
        local action = Registry and Registry:GetAction("confirm_wago_backup")
        return action and {
            kind = "action",
            action = action,
            args = { confirmed = not clear },
            label = clear and "Clear Wago backup confirmation" or "Confirm Wago backup",
            summary = "Marks the Wago backup checklist for the active profile.",
        } or nil
    end

    if ContainsAny(text, { "recovery tools", "display recovery", "recover menu", "reset tools", "dashboard recovery" }) then
        local action = Registry and Registry:GetAction("open_recovery_tools")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Open recovery tools",
            summary = "Opens the Dashboard recovery area.",
        } or nil
    end

    if ContainsAny(text, { "scaling tools", "dashboard scaling", "scale tools", "ui scale tools", "open scaling" }) then
        local action = Registry and Registry:GetAction("open_dashboard_panel")
        return action and {
            kind = "action",
            action = action,
            args = { panel = "scaling" },
            label = "Open scaling tools",
            summary = "Opens the Dashboard scaling area.",
        } or nil
    end

    if ContainsAny(text, { "changelog", "change log", "release notes", "latest changes", "build notes" }) then
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
    if link and ContainsAny(text, { "copy", "open", "link", "support", "join", "repo", "repository", "donate" }) then
        local action = Registry and Registry:GetAction("copy_support_link")
        return action and {
            kind = "action",
            action = action,
            args = { link = link },
            label = "Copy support link",
            summary = "Opens a copyable MSUF support link.",
        } or nil
    end

    if ContainsAny(text, {
        "support links", "support msuf", "donate links", "development links",
        "hilfe links", "support link liste", "spenden links", "entwicklungs links",
    }) then
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
    if ContainsAny(text, { "1080p", "1080" }) then return "1080p" end
    if ContainsAny(text, { "1440p", "1440" }) then return "1440p" end
    if ContainsAny(text, { "4k", "2160p", "2160" }) then return "4k" end
    if ContainsAny(text, { "pixel perfect", "pixel" }) then return "pixel" end
    if ContainsAny(text, { "auto" }) then return "off" end
    if ContainsAny(text, { "turn off", "disable", "off" }) and ContainsAny(text, { "preset", "scale preset" }) then return "off" end
    return nil
end

local function ParsePresetWorkflow(text)
    if not ContainsAny(text, { "preset", "global ui scale", "wow ui scale", "global scale", "scale preset", "ui preset", "ui scale preset" }) then return nil end
    if not ContainsAny(text, { "global ui scale", "wow ui scale", "global scale", "scale preset", "ui preset", "ui scale preset" }) then return nil end
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
    if ContainsAny(text, { "preset", "panel", "section", "tools", "open", "close", "toggle" }) then return nil end
    if ContainsAny(text, {
        "msuf menu", "menu scale", "dashboard scale", "options menu", "config menu",
        "configuration menu", "assistant menu",
    }) then
        return "general.slashMenuScale", "MSUF Menu Scale"
    end
    if ContainsAny(text, {
        "msuf frame scale", "msuf frames", "all msuf frames", "msuf ui scale",
        "unit frame scale", "unitframes scale", "frames globally", "all frames globally",
    }) then
        return "general.msufUiScale", "MSUF Frame Scale"
    end
    if ContainsAny(text, {
        "wow ui", "global ui", "global scale", "wow scale", "whole ui",
        "ui scale", "interface scale",
    }) then
        return "general.globalUiScale", "Global WoW UI Scale"
    end
    return nil
end

local function ParseDashboardScaleShortcut(text)
    local key, label = DashboardScaleTargetForText(text)
    if not key then return nil end
    if not ContainsAny(text, {
        "scale", "bigger", "larger", "smaller", "increase", "decrease", "raise", "lower",
        "grow", "shrink", "set", "make",
    }) then
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
    local font = ContainsAny(text, { "font", "fonts", "text style", "name color", "text color" })
    local bars = ContainsAny(text, { "bars", "bar", "bar texture", "global bars", "gradient", "absorb", "highlight border", "dispel overlay", "aggro border", "purge border" })
    if not font and not bars then return nil end
    local reset = ContainsAny(text, {
        "reset", "clear", "restore", "default", "defaults", "follow shared", "use shared",
        "remove override", "remove custom", "disable custom", "turn off custom",
    })
    if not reset then return nil end
    local all = ContainsAny(text, {
        "all overrides", "every override", "all custom", "all scopes",
        "all bar overrides", "all bars overrides", "all global bar overrides", "all global bars overrides",
        "all font overrides", "all fonts overrides", "all global font overrides", "all global fonts overrides",
        "every bar override", "every bars override", "every font override", "every fonts override",
    })
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
    return ContainsAny(text, {
        "preview resource", "resource preview", "preview class resource", "preview class resources",
        "preview class power", "preview class bar", "class resource preview", "class resources preview",
        "class power preview", "class bar preview", "class resource preview resource",
        "class power preview resource",
    })
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

    if (HasClassPowerIntent(text) or ContainsAny(text, { "resource preview animation", "preview resource animation" }))
        and ContainsAny(text, {
            "preview animation", "animate preview", "animate", "animation", "start preview", "stop preview",
            "play preview", "pause preview", "toggle preview animation", "start", "stop", "play", "pause",
        })
        and ContainsAny(text, { "preview", "animate", "animation" }) then
        local action = Registry and Registry:GetAction("class_power_preview_animate")
        local value = DetectBoolean(text)
        if ContainsAny(text, { "stop", "pause", "off", "disable" }) then
            value = false
        elseif ContainsAny(text, { "start", "play", "animate", "on", "enable" }) then
            value = true
        end
        if ContainsAny(text, { "toggle", "switch", "umschalten" }) then value = nil end
        return action and {
            kind = "action",
            action = action,
            args = { value = value },
            label = "Animate class resource preview",
            summary = "Changes the Class Resources inline preview animation.",
        } or nil
    end
    if not ContainsAny(text, { "quick setup", "quicksetup", "setup" }) then return nil end
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
        details = { "size", "groesse", "font", "duration", "dauer", "lock", "locked", "sperren", "x", "y", "offset", "move", "verschiebe", "color", "colors", "farbe", "farben", "sync", "synchron" },
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
    if ContainsAny(text, { "crosshair", "fadenkreuz", "melee range spell", "range check spell", "nahkampf zauber", "reichweiten zauber" }) and ContainsAny(text, { "spell", "zauber", "range check", "reichweite" }) then
        local rawText = tostring(raw or "")
        local value
        if ContainsAny(text, { "clear", "reset", "none", "no spell", "loeschen", "zuruecksetzen", "kein zauber", "ohne zauber" }) then
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
    if ContainsAny(text, { "preview", "test", "vorschau" }) and ContainsAny(text, { "totem frame", "totemframe", "blizzard totem", "statue frame", "totem", "totems", "totem rahmen", "statuen rahmen", "statue rahmen" }) then
        local action = Registry and Registry:GetAction("preview_player_totems")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Preview Totem Frame",
            summary = "Toggles the Totem Frame preview.",
        } or nil
    end
    if ContainsAny(text, { "reset", "restore", "default", "defaults", "zuruecksetzen", "zurucksetzen", "standard" }) and ContainsAny(text, { "totem frame", "totemframe", "blizzard totem", "statue frame", "totem", "totems", "totem rahmen", "statuen rahmen", "statue rahmen" }) then
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

    if ContainsAny(text, { "dispel test type", "dispel border test type", "dispel border preview type", "dispel vorschau typ", "dispel border vorschau typ", "dispel rand vorschau typ" }) then
        local value
        if ContainsAny(text, { "curse" }) then value = "Curse"
        elseif ContainsAny(text, { "disease" }) then value = "Disease"
        elseif ContainsAny(text, { "poison" }) then value = "Poison"
        elseif ContainsAny(text, { "bleed" }) then value = "Bleed"
        elseif ContainsAny(text, { "magic" }) then value = "Magic" end
        local action = Registry and Registry:GetAction("set_dispel_border_test_type")
        return action and {
            kind = "action",
            action = action,
            args = { value = value or "Magic" },
            label = "Set dispel border test type",
            summary = "Changes the transient dispel border preview type.",
        } or nil
    end
    if ContainsAny(text, previewTerms) and ContainsAny(text, {
        "absorb bar", "absorb bars", "absorb test", "absorb test bar", "absorb test bars",
        "test absorb bar", "test absorb bars", "absorb prediction bar", "absorb prediction bars",
        "prediction bars", "heal absorb", "absorb vorschau", "absorb balken",
        "absorb balken test", "absorb balken vorschau", "heil absorb", "heal absorb vorschau",
    }) then
        local action = Registry and Registry:GetAction("toggle_absorb_bar_test")
        return action and {
            kind = "action",
            action = action,
            args = { value = not ContainsAny(text, offTerms) },
            label = "Toggle absorb bar test",
            summary = "Toggles the absorb prediction bar test display.",
        } or nil
    end
    if ContainsAny(text, offTerms) and ContainsAny(text, { "absorb test", "prediction bar test", "absorb vorschau", "absorb balken", "absorb balken test", "absorb balken vorschau" }) then
        local action = Registry and Registry:GetAction("toggle_absorb_bar_test")
        return action and {
            kind = "action",
            action = action,
            args = { value = false },
            label = "Disable absorb bar test",
            summary = "Turns off the absorb prediction bar test display.",
        } or nil
    end
    if ContainsAny(text, previewTerms) and ContainsAny(text, {
        "aggro border", "threat border", "aggro test border", "aggro border test",
        "threat test border", "threat border test", "border test aggro", "border test for aggro",
        "border test threat", "border test for threat", "aggro rand", "aggro rand test",
        "aggro rand vorschau", "bedrohung rand", "bedrohung rand test",
        "bedrohung rand vorschau", "bedrohungsrand",
    }) then
        local action = Registry and Registry:GetAction("toggle_highlight_border_test")
        return action and { kind = "action", action = action, args = { kind = "aggro", value = not ContainsAny(text, offTerms) }, label = "Test aggro border", summary = "Toggles the aggro border test." } or nil
    end
    if ContainsAny(text, previewTerms) and ContainsAny(text, {
        "dispel border", "dispellable border", "dispel test border", "dispel border test",
        "dispellable test border", "dispellable border test", "border test dispel",
        "border test for dispel", "border test dispellable", "border test for dispellable",
        "dispel rand", "dispel rand test", "dispel rand vorschau", "dispellable rand",
        "entzauber rand", "entzauber rand vorschau", "entzauberbar rand",
    }) then
        local action = Registry and Registry:GetAction("toggle_highlight_border_test")
        return action and { kind = "action", action = action, args = { kind = "dispel", value = not ContainsAny(text, offTerms) }, label = "Test dispel border", summary = "Toggles the dispel border test." } or nil
    end
    if ContainsAny(text, previewTerms) and ContainsAny(text, {
        "purge border", "purgeable border", "purge test border", "purge border test",
        "purgeable test border", "purgeable border test", "border test purge",
        "border test for purge", "border test purgeable", "border test for purgeable",
        "purge rand", "purge rand test", "purge rand vorschau", "purgeable rand",
        "offensiv dispel rand", "offensiv dispel rand vorschau",
    }) then
        local action = Registry and Registry:GetAction("toggle_highlight_border_test")
        return action and { kind = "action", action = action, args = { kind = "purge", value = not ContainsAny(text, offTerms) }, label = "Test purge border", summary = "Toggles the purge border test." } or nil
    end
    if ContainsAny(text, previewTerms) and ContainsAny(text, {
        "boss target border", "boss target highlight", "boss target test border",
        "boss target border test", "boss target highlight test", "border test boss target",
        "border test for boss target", "boss ziel border", "boss ziel rand",
        "boss ziel rand test", "boss ziel rand vorschau", "bossziel rand",
    }) then
        local action = Registry and Registry:GetAction("toggle_highlight_border_test")
        return action and { kind = "action", action = action, args = { kind = "bossTarget", value = not ContainsAny(text, offTerms) }, label = "Test boss target border", summary = "Toggles the boss target border test." } or nil
    end
    return nil
end

local function ParseDarkModeBrightnessShortcut(text)
    if not ContainsAny(text, { "dark mode", "dark bars", "dark bar", "dark mode bar color", "dark bar brightness" }) then return nil end
    if not ContainsAny(text, {
        "lighter", "brighter", "brighten", "heller",
        "darker", "darken", "dunkler", "super dark", "very dark", "black", "almost black",
        "brightness", "bar color", "percent", "percentage", "slider", "value", "set", "make", "change", "adjust",
    }) then
        return nil
    end
    local setting = Registry and Registry:GetSetting("general.darkBarGray")
    if not setting then return nil end

    local value
    local relativeDelta
    local amount = FirstNumber(text)
    local relativeIntent = ContainsAny(text, { "lighter", "brighter", "brighten", "heller", "darker", "darken", "dunkler" })
    local exactIntent = amount ~= nil and not relativeIntent and (ContainsAny(text, {
        "to", "set", "value", "percent", "percentage", "slider", "brightness", "bar color", "make", "change", "adjust",
    }) or text:find("%%", 1, true) ~= nil)
    if exactIntent then
        value = amount > 1 and (amount / 100) or amount
    elseif ContainsAny(text, { "super dark", "very dark", "almost black", "black" }) then
        value = 0.01
    elseif ContainsAny(text, { "lighter", "brighter", "brighten", "heller" }) then
        local fallback = ContainsAny(text, { "bit", "a bit", "slightly", "little", "etwas" }) and 0.03 or 0.08
        relativeDelta = amount and (amount > 1 and amount / 100 or amount) or fallback
    elseif ContainsAny(text, { "darker", "darken", "dunkler" }) then
        local fallback = ContainsAny(text, { "bit", "a bit", "slightly", "little", "etwas" }) and 0.03 or 0.08
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
    "unit names short", "names short", "names shorter",
}

local NAME_SHORTENING_DOT_TERMS = {
    "dots", "dot", "ellipsis", "ellipses", "name dots", "name ellipsis",
    "truncate dots", "truncate ellipsis", "shortening dots", "shortening ellipsis",
}

local NAME_SHORTENING_NON_NAME_DOT_TERMS = {
    "corner dot", "corner dots", "corner indicator", "corner indicators",
    "status dot", "status dots", "status indicator", "status indicators",
    "spell indicator", "spell indicators",
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
    if ContainsAny(text, { "shorten", "truncate", "truncation" })
        and ContainsAny(text, { "name", "names", "unit name", "unit names" }) then
        return true
    end
    return false
end

local function NameShorteningScope(text)
    if ContainsAny(text, {
        "everything", "all names", "all unit names", "all unitframes", "all unitframe",
        "every unitframe", "every unitframes", "all frames", "every frame",
    }) then
        return "shared"
    end
    local groups = DetectGroups and DetectGroups(text) or {}
    if groups[1] then return "gf_" .. tostring(groups[1]) end
    local scope = DetectGlobalScope and DetectGlobalScope(text) or nil
    return scope or "shared"
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
    if ContainsAny(text, { "truncation style", "name truncation", "name clip side", "shortening side", "clip side" }) then
        if ContainsAny(text, { "left", "to left", "left side" }) then return "LEFT", "Left" end
        if ContainsAny(text, { "right", "to right", "right side" }) then return "RIGHT", "Right" end
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
    if not ctx then return false end
    local key = tostring(ctx.lastSetting or "")
    if key:find("shortenName", 1, true) or key:find("shortenNames", 1, true) then return true end
    if key:find("nameShorten", 1, true) or key:find("nameNoEllipsis", 1, true) then return true end
    local bundle = ctx.lastChangeBundle
    if type(bundle) == "table" then
        for i = 1, #bundle do
            local item = bundle[i]
            key = tostring(item and item.key or "")
            if key:find("shortenName", 1, true) or key:find("shortenNames", 1, true)
                or key:find("nameShorten", 1, true) or key:find("nameNoEllipsis", 1, true) then
                return true
            end
        end
    end
    return false
end

local function ParseNameShorteningDots(text, ctx)
    if not ContainsAny(text, NAME_SHORTENING_DOT_TERMS) then return nil end
    if ContainsAny(text, NAME_SHORTENING_NON_NAME_DOT_TERMS) and not HasNameShorteningIntent(text) then return nil end
    if ContainsAny(text, { "castbar", "spell name", "spell names" }) then return nil end
    local explicitNameContext = HasNameShorteningIntent(text)
        or ContainsAny(text, { "name", "names", "unit name", "unit names", "truncate", "truncation" })
    if not explicitNameContext and not IsNameShorteningContext(ctx) then
        local value = DetectBoolean(text)
        if value == nil then return nil end
    end

    local value = DetectBoolean(text)
    local noEllipsis
    if ContainsAny(text, { "no dots", "without dots", "hide dots", "no ellipsis", "without ellipsis", "hide ellipsis" }) then
        noEllipsis = true
    elseif ContainsAny(text, { "show dots", "with dots", "dots on", "show ellipsis", "with ellipsis", "ellipsis on" }) then
        noEllipsis = false
    elseif value ~= nil then
        noEllipsis = not value
    else
        return {
            kind = "answer",
            status = "ambiguous",
            text = "Do you want shortened names to show trailing dots? For hidden dots: 'turn off name dots'. For visible dots: 'turn on name dots'.",
            summary = "Asks whether name-shortening ellipsis dots should be shown.",
        }
    end

    local scope = NameShorteningScope(text)
    local setting = NameShorteningSetting(scope, "shortenNameNoEllipsis")
    if not setting then
        return {
            kind = "unknown",
            status = "failed",
            text = "Name-shortening dots work for Shared, Target, Focus, Pet, Boss, Party, or Raid.",
        }
    end
    return {
        kind = "changes",
        changes = { { setting = setting, value = noEllipsis, valueLabel = noEllipsis and "hidden" or "shown" } },
        label = setting.label or "Name No Ellipsis",
        summary = "Changes whether shortened names show trailing dots.",
    }
end

local function ParseNameShorteningShortcut(text, ctx)
    local dots = ParseNameShorteningDots(text, ctx)
    if dots then return dots end
    if ContainsAny(text, { "castbar", "spell name", "spell names" }) then return nil end
    if not HasNameShorteningIntent(text) then return nil end

    local scope = NameShorteningScope(text)
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
    if not ContainsAny(text, { "test", "preview", "show preview", "vorschau", "zeige vorschau", "preview anzeigen" }) then return nil end
    if not ContainsAny(text, { "castbar", "cast bar", "zauberleiste", "zauberleisten" }) then return nil end
    local action = Registry and Registry:GetAction("preview_castbar")
    if not action then return nil end
    local units = DetectUnits(text)
    local unit = units[1] or "player"
    local kind = "normal"
    if ContainsAny(text, { "channel", "channeled", "channelled", "kanal", "kanalisiert" }) then
        kind = "channel"
    elseif ContainsAny(text, { "empowered", "empower", "evoker", "verstaerkt", "verstaerken", "ermaechtigt", "ermaechtigen" }) then
        kind = "empowered"
    end
    return {
        kind = "action",
        action = action,
        args = {
            unit = unit,
            kind = kind,
            interrupt = ContainsAny(text, { "interrupt", "interrupted", "shake", "kick", "unterbrechen", "unterbrochen", "schuetteln", "schutteln" }),
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
    if not ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) then return nil end
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
    if not ContainsAny(text, { "castbar", "cast bar", "zauberleiste", "zauberleisten" }) then return nil end
    if not ContainsAny(text, { "target", "target castbar", "target cast bar", "ziel", "ziel castbar", "ziel zauberleiste" }) then return nil end
    if not ContainsAny(text, {
        "other direction", "opposite direction", "opposite fill direction", "fill in the other direction",
        "fill the other direction", "other way", "opposite way", "reverse direction", "fill opposite", "opposite fill",
        "filling opposite", "fills opposite", "normal direction", "normal fill", "same direction", "same fill",
        "not opposite", "no opposite", "stop opposite", "stop filling opposite",
        "andere richtung", "entgegengesetzte richtung", "umgekehrte richtung", "andere fuellrichtung",
        "normal richtung", "normale richtung", "gleiche richtung", "gleiche fuellrichtung",
    }) then return nil end

    local opposite = Registry and Registry:GetSetting("general.castbarOpositeDirectionTarget")
    if not opposite then return nil end
    local value = DetectBoolean(text)
    if value == nil and ContainsAny(text, {
        "use opposite", "use opposite direction", "use opposite fill direction",
        "use target opposite", "use target opposite direction", "fill opposite", "opposite fill",
        "entgegengesetzte richtung", "umgekehrte richtung", "andere fuellrichtung",
    }) then
        value = true
    end
    if value == nil and ContainsAny(text, {
        "normal direction", "normal fill", "same direction", "same fill",
        "not opposite", "no opposite", "stop opposite", "stop filling opposite",
        "normal richtung", "normale richtung", "gleiche richtung", "gleiche fuellrichtung",
    }) then
        value = false
    end
    if value == nil and ContainsAny(text, { "stop", "clear", "remove", "aus", "deaktiviere", "beende" }) and ContainsAny(text, { "opposite", "other way", "reverse", "entgegengesetzt", "umgekehrt" }) then
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
local function ParseGuidedSetup(text)
    if not ContainsAny(text, {
        "help me build", "guided setup", "setup", "setup guide", "start guide", "start tour",
        "tour guide", "guide me", "show me around", "walk me through", "getting started",
        "start with msuf", "how do i start with msuf", "first time msuf", "new to msuf",
        "never used msuf", "never used this addon", "new user", "beginner guide",
        "beginner setup", "onboarding", "build a clean", "clean layout", "rogue layout",
        "layout bauen", "setup hilfe", "fuehre mich", "fuehr mich", "fuehrung",
        "einsteiger", "anfanger", "neu in msuf", "noch nie msuf", "zeig mir msuf",
        "hilf mir einrichten", "hilf mir beim einrichten", "einrichtungshilfe",
        "schritt fuer schritt", "fuehre mich durch msuf", "msuf einrichten",
        "assistant einrichtung", "assistent einrichtung",
    }) then return nil end
    local action = Registry and Registry:GetAction("guided_setup")
    return action and {
        kind = "action",
        action = action,
        args = { style = text },
        label = "Guided setup",
        summary = "Starts the guided setup flow.",
    } or nil
end

local function ParseGuidedSetupFollowup(text, ctx)
    local active = ctx and type(ctx.guidedSetup) == "table"
    local explicit = ContainsAny(text, {
        "cancel setup", "stop setup", "abort setup", "setup cancel",
        "finish setup", "done setup", "setup done", "complete setup", "setup complete",
        "skip setup", "skip setup step", "setup skip",
        "next setup", "next setup step", "setup next", "continue setup",
        "back setup", "back setup step", "setup back", "previous setup", "previous setup step", "setup previous",
        "show setup", "show setup step", "repeat setup", "current setup step", "setup status",
        "setup weiter", "weiter setup", "naechster setup schritt", "naechster schritt",
        "setup zurueck", "zurueck setup", "vorheriger setup schritt", "vorheriger schritt",
        "setup abbrechen", "einrichtung abbrechen", "setup fertig", "einrichtung fertig",
        "setup ueberspringen", "schritt ueberspringen", "setup anzeigen", "zeige setup",
        "setup wiederholen", "schritt wiederholen", "setup status",
    })
    if not active and not explicit then return nil end
    local exact
    if active then
        if text == "cancel" or text == "stop" or text == "abort" or text == "abbrechen" then
            exact = "cancel"
        elseif text == "finish" or text == "done" or text == "complete" or text == "fertig" then
            exact = "finish"
        elseif text == "skip" or text == "ueberspringen" then
            exact = "skip"
        elseif text == "next" or text == "continue" or text == "weiter" then
            exact = "next"
        elseif text == "back" or text == "previous" or text == "zurueck" then
            exact = "back"
        elseif text == "show" or text == "repeat" or text == "status" or text == "anzeigen" or text == "wiederholen" then
            exact = "show"
        elseif text == "why" or text == "why this" or text == "explain" or text == "details"
            or text == "tell me more" or text == "more details" or text == "what is it for" then
            exact = "explain"
        elseif text == "examples" or text == "show examples" or text == "show me examples" or text == "commands" then
            exact = "examples"
        elseif text == "open" or text == "open it" or text == "open this" or text == "open that"
            or text == "show me where" or text == "take me there" or text == "go there" then
            exact = "open"
        elseif text == "do it" or text == "do that" or text == "apply it" or text == "use it" or text == "run it" then
            exact = "apply"
        end
    end
    local command
    if ContainsAny(text, { "cancel setup", "stop setup", "abort setup", "setup cancel", "setup abbrechen", "einrichtung abbrechen" }) then
        command = "cancel"
    elseif ContainsAny(text, { "finish setup", "done setup", "setup done", "complete setup", "setup complete", "setup fertig", "einrichtung fertig" }) then
        command = "finish"
    elseif ContainsAny(text, { "skip setup", "skip setup step", "setup skip", "setup ueberspringen", "schritt ueberspringen" }) then
        command = "skip"
    elseif ContainsAny(text, { "next setup", "next setup step", "setup next", "continue setup", "setup weiter", "weiter setup", "naechster setup schritt", "naechster schritt" }) then
        command = "next"
    elseif ContainsAny(text, { "back setup", "back setup step", "setup back", "previous setup", "previous setup step", "setup previous", "setup zurueck", "zurueck setup", "vorheriger setup schritt", "vorheriger schritt" }) then
        command = "back"
    elseif ContainsAny(text, { "show setup", "show setup step", "repeat setup", "current setup step", "setup status", "setup anzeigen", "zeige setup", "setup wiederholen", "schritt wiederholen" }) then
        command = "show"
    elseif active and ContainsAny(text, {
        "why this", "tell me more", "more details",
        "what is it for", "why this step", "what does this step do",
    }) then
        command = "explain"
    elseif active and ContainsAny(text, { "show examples", "show me examples", "example commands" }) then
        command = "examples"
    elseif active and ContainsAny(text, {
        "open it", "open this", "open that", "show me where", "take me there", "go there",
    }) then
        command = "open"
    elseif active and ContainsAny(text, { "do it", "do that", "apply it", "use it", "run it" }) then
        command = "apply"
    elseif exact then
        command = exact
    end
    if not command then return nil end
    local action = Registry and Registry:GetAction("guided_setup_step")
    return action and {
        kind = "action",
        action = action,
        args = { command = command },
        label = "Guided setup step",
        summary = "Continues the active guided setup.",
    } or nil
end

function P.ParseProfileBackupImportQuestion(text)
    if not ContainsAny(text, {
        "backup before import", "backup before importing", "backup before profile import", "backup before importing profile",
        "make backup before import", "make a backup before import", "make backup before importing", "make a backup before importing",
    }) then return nil end
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
    if not ContainsAny(text, { "custom anchor", "custom anchor picker", "anchor picker", "anchor settings" }) then return nil end
    return {
        kind = "answer",
        status = "info",
        text = "Pick a concrete MSUF frame or open a Unit/Group page for the custom anchor picker. Examples: open player custom anchor picker, open target custom anchor picker, open raid custom anchor picker, or set target custom anchor to Cooldown Manager.",
        summary = "Shows custom anchor picker usage without guessing a frame.",
    }
end

function P.ParseGroupScaleLookupQuestion(text)
    if ContainsAny(text, { "aura", "auras", "buff", "debuff" }) then return nil end
    if not ContainsAny(text, {
        "scale", "scaling", "frame scale", "raid scale", "party scale", "mythic raid scale",
        "players", "raider", "raiders", "people", "members", "player count", "raid size",
        "full raid", "when full", "large raid", "small raid", "five man", "5 man", "5m",
    }) then return nil end
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
        or ParseSupportWorkflow(text)
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
P.ParseDashboardScaleShortcut = ParseDashboardScaleShortcut
P.ParseScopedOverrideReset = ParseScopedOverrideReset
P.ParseClassPowerAction = ParseClassPowerAction
P.GAMEPLAY_ROOT_TOGGLES = GAMEPLAY_ROOT_TOGGLES
P.ParseGameplayRootToggle = ParseGameplayRootToggle
P.ParseGameplayAction = ParseGameplayAction
P.ParseGlobalBarsAction = ParseGlobalBarsAction
P.ParseDarkModeBrightnessShortcut = ParseDarkModeBrightnessShortcut
P.ParseNameShorteningShortcut = ParseNameShorteningShortcut
P.ParseCastbarPreviewAction = ParseCastbarPreviewAction
P.CASTBAR_GLOBAL_BOOLEAN_DETAILS = CASTBAR_GLOBAL_BOOLEAN_DETAILS
P.ParseCastbarGlobalDetail = ParseCastbarGlobalDetail
P.ParseCastbarDirectionClarification = ParseCastbarDirectionClarification
P.ParseGuidedSetup = ParseGuidedSetup
P.ParseGuidedSetupFollowup = ParseGuidedSetupFollowup
