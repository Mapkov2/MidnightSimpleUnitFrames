local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
local P = A.Parser or {}
A.Parser = P
local Trim = P.Trim
local Normalize = P.Normalize
local HasPhrase = P.HasPhrase
local ContainsAny = P.ContainsAny
local UNIT_ORDER = P.UNIT_ORDER
local GROUP_ORDER = P.GROUP_ORDER
local ALL_UNITFRAMES = P.ALL_UNITFRAMES
local ALL_GROUPS = P.ALL_GROUPS
local CLASS_POWER_TERMS = P.CLASS_POWER_TERMS
local GAMEPLAY_TERMS = P.GAMEPLAY_TERMS
local GLOBAL_BARS_TERMS = P.GLOBAL_BARS_TERMS
local CASTBAR_ROOT_DETAIL_TERMS = P.CASTBAR_ROOT_DETAIL_TERMS
local PAGE_TEXT_TARGETS = P.PAGE_TEXT_TARGETS
local AddUnique = P.AddUnique
local DetectUnits = P.DetectUnits
local DetectGroups = P.DetectGroups
local DetectGlobalScope = P.DetectGlobalScope
local OFF_WORDS = P.OFF_WORDS
local ON_WORDS = P.ON_WORDS
local DetectBoolean = P.DetectBoolean
local FirstNumber = P.FirstNumber
local Compact = P.Compact
local AliasRelationText = P.AliasRelationText
local TextMatchesAlias = P.TextMatchesAlias
local ExtractColor = P.ExtractColor
local DetectFrameType = P.DetectFrameType
local DetectDirection = P.DetectDirection
local DetectAttribute = P.DetectAttribute
local PageForText = P.PageForText
local FrameTypeForPage = P.FrameTypeForPage
local UnitPageKey = P.UnitPageKey
local COPY_SCOPE_DEFAULTS = P.COPY_SCOPE_DEFAULTS
local UNIT_COPY_SCOPE_SPECS = P.UNIT_COPY_SCOPE_SPECS
local GROUP_COPY_SCOPE_DEFAULTS = P.GROUP_COPY_SCOPE_DEFAULTS
local GROUP_COPY_SCOPE_SPECS = P.GROUP_COPY_SCOPE_SPECS
local CopyScopeDefaults = P.CopyScopeDefaults
local CopyScopeMatches = P.CopyScopeMatches
local ApplyCopyScopeMatches = P.ApplyCopyScopeMatches
local CopyScopesForText = P.CopyScopesForText
local GroupCopyScopeDefaults = P.GroupCopyScopeDefaults
local GroupCopyScopesForText = P.GroupCopyScopesForText
local CleanProfileName = P.CleanProfileName
local RawAfterPrefix = P.RawAfterPrefix
local RawBetween = P.RawBetween
local RawCreateProfileName = P.RawCreateProfileName
local RawCopyProfileName = P.RawCopyProfileName
local RawRenameProfileNames = P.RawRenameProfileNames
local PROFILE_EXPORT_KIND_LABELS = P.PROFILE_EXPORT_KIND_LABELS
local ProfileExportKindForText = P.ProfileExportKindForText
local RawAfterLastConnector = P.RawAfterLastConnector
local CleanSpecName = P.CleanSpecName
local ImportNewProfileName = P.ImportNewProfileName
local BuildSpecAutoSwitch = P.BuildSpecAutoSwitch
local BuildSpecProfileAction = P.BuildSpecProfileAction
local ParseWorkflowLifecycle = P.ParseWorkflowLifecycle
local BuildMenuSelectorState = P.BuildMenuSelectorState
local ParseProfileStagingState = P.ParseProfileStagingState
local ParseGroupCopyScopeState = P.ParseGroupCopyScopeState
local ParseUnitCopyScopeState = P.ParseUnitCopyScopeState
local ParseProfile = P.ParseProfile
local AURA_BLACKLIST_PRESETS = P.AURA_BLACKLIST_PRESETS
local AuraBlacklistScope = P.AuraBlacklistScope
local AURA_QUICK_PRESETS = P.AURA_QUICK_PRESETS
local AuraQuickPresetForText = P.AuraQuickPresetForText
local ParseAuraQuickPreset = P.ParseAuraQuickPreset
local AuraBlacklistPresetForText = P.AuraBlacklistPresetForText
local AuraGroupBlacklistScope = P.AuraGroupBlacklistScope
local AuraGroupBlacklistLane = P.AuraGroupBlacklistLane
local AuraGroupBlacklistCategoryForText = P.AuraGroupBlacklistCategoryForText
local ParseAuraGroupCategoryBlacklist = P.ParseAuraGroupCategoryBlacklist
local AuraBlacklistSpellValue = P.AuraBlacklistSpellValue
local ParseAuraBlacklist = P.ParseAuraBlacklist
local CopyTextParts = P.CopyTextParts
local RemoveUnit = P.RemoveUnit
local CopyTargetsForText = P.CopyTargetsForText
local CopyGroupTargetsForText = P.CopyGroupTargetsForText
local ParseGroupCopy = P.ParseGroupCopy
local ParseCopy = P.ParseCopy
local BuildContextReset = P.BuildContextReset
local GROUP_STATUS_ICON_ALIASES = P.GROUP_STATUS_ICON_ALIASES
local GroupStatusIconForText = P.GroupStatusIconForText
local GROUP_STATUS_ICON_TERMS = P.GROUP_STATUS_ICON_TERMS
local FirstGroupOrDefault = P.FirstGroupOrDefault
local AliasValueForText = P.AliasValueForText
local GROUP_SPELL_PLACED_ALIASES = P.GROUP_SPELL_PLACED_ALIASES
local GROUP_SPELL_FRAME_ALIASES = P.GROUP_SPELL_FRAME_ALIASES
local GROUP_SPELL_GROWTH_ALIASES = P.GROUP_SPELL_GROWTH_ALIASES
local GROUP_SPELL_ANCHOR_ALIASES = P.GROUP_SPELL_ANCHOR_ALIASES
local ParseGroupSpellIndicatorAction = P.ParseGroupSpellIndicatorAction
local ParseGroupCornerIndicatorReset = P.ParseGroupCornerIndicatorReset
local ParseGroupStatusIconReset = P.ParseGroupStatusIconReset
local ParseGroupStatusPreview = P.ParseGroupStatusPreview
local UNIT_STATUS_RESET_TERMS = P.UNIT_STATUS_RESET_TERMS
local ParseUnitStatusIndicatorReset = P.ParseUnitStatusIndicatorReset
local ParseUnitStatusPreview = P.ParseUnitStatusPreview
local ParseUnitStatusIndicatorMove = P.ParseUnitStatusIndicatorMove
local ParseCustomAnchorWorkflow = P.ParseCustomAnchorWorkflow
local CleanCustomAnchorFrameName = P.CleanCustomAnchorFrameName
local RawCustomAnchorFrameName = P.RawCustomAnchorFrameName
local ParseCustomAnchorSet = P.ParseCustomAnchorSet
local ParseCustomAnchorClear = P.ParseCustomAnchorClear
local ParseReset = P.ParseReset
local ParseOpen = P.ParseOpen
local DashboardPanelForText = P.DashboardPanelForText
local ParseDashboardPanelAction = P.ParseDashboardPanelAction
local NAV_SECTION_TEXT_TARGETS = P.NAV_SECTION_TEXT_TARGETS
local NavSectionForText = P.NavSectionForText
local ParseNavRailAction = P.ParseNavRailAction
local ParseMenuWindowAction = P.ParseMenuWindowAction
local SettingMatchesText = P.SettingMatchesText
local SettingMatchScore = P.SettingMatchScore
local EnumValueForText = P.EnumValueForText
local StringValueForText = P.StringValueForText
local RELATIVE_INCREASE_TERMS = P.RELATIVE_INCREASE_TERMS
local RELATIVE_DECREASE_TERMS = P.RELATIVE_DECREASE_TERMS
local RelativeNumberDeltaForText = P.RelativeNumberDeltaForText
local NumberSettingSupportsBooleanToggle = P.NumberSettingSupportsBooleanToggle
local BooleanValueForNumberSetting = P.BooleanValueForNumberSetting
local ValueForRegistrySetting = P.ValueForRegistrySetting
local AddMediaResolverChanges = P.AddMediaResolverChanges
local ParseRegistryAlias = P.ParseRegistryAlias
local ScopedOnlyKind = P.ScopedOnlyKind
local ScopedOnlyOverrideKey = P.ScopedOnlyOverrideKey
local ParseScopedOnlyOverride = P.ParseScopedOnlyOverride
local CLASS_POWER_DETAIL_TERMS = P.CLASS_POWER_DETAIL_TERMS
local ParseClassPowerRootToggle = P.ParseClassPowerRootToggle
local ParseFontColorAction = P.ParseFontColorAction
local BuildColorResetAction = P.BuildColorResetAction
local POWER_TOKEN_EXTRA_ALIASES = P.POWER_TOKEN_EXTRA_ALIASES
local PowerColorTokenForText = P.PowerColorTokenForText
local CP_TOKEN_EXTRA_ALIASES = P.CP_TOKEN_EXTRA_ALIASES
local ClassPowerColorTokenForText = P.ClassPowerColorTokenForText
local ParseColorAction = P.ParseColorAction
local ParseDiagnostic = P.ParseDiagnostic
local ParseScopedHelp = P.ParseScopedHelp
local SupportLinkForText = P.SupportLinkForText
local ParseSupportWorkflow = P.ParseSupportWorkflow
local GlobalScalePresetForText = P.GlobalScalePresetForText
local ParsePresetWorkflow = P.ParsePresetWorkflow
local ParseScopedOverrideReset = P.ParseScopedOverrideReset
local ParseClassPowerAction = P.ParseClassPowerAction
local GAMEPLAY_ROOT_TOGGLES = P.GAMEPLAY_ROOT_TOGGLES
local ParseGameplayRootToggle = P.ParseGameplayRootToggle
local ParseGameplayAction = P.ParseGameplayAction
local ParseGlobalBarsAction = P.ParseGlobalBarsAction
local ParseDarkModeBrightnessShortcut = P.ParseDarkModeBrightnessShortcut
local ParseCastbarPreviewAction = P.ParseCastbarPreviewAction
local CASTBAR_GLOBAL_BOOLEAN_DETAILS = P.CASTBAR_GLOBAL_BOOLEAN_DETAILS
local ParseCastbarGlobalDetail = P.ParseCastbarGlobalDetail
local ParseGuidedSetup = P.ParseGuidedSetup
local ParseGuidedSetupFollowup = P.ParseGuidedSetupFollowup
local BuildChanges = P.BuildChanges
local ParseUnsupportedDetailShortcut = P.ParseUnsupportedDetailShortcut
local CurrentPageUnit = P.CurrentPageUnit
local DetailUnitsOrCurrentPage = P.DetailUnitsOrCurrentPage
local BuildUnitDetailChoices = P.BuildUnitDetailChoices
local ParsePortraitDetailShortcut = P.ParsePortraitDetailShortcut
local DETAIL_MOVE_SPECS = P.DETAIL_MOVE_SPECS
local GROUP_DETAIL_MOVE_SPECS = P.GROUP_DETAIL_MOVE_SPECS
local ParseUnitDetailMove = P.ParseUnitDetailMove
local GroupScopesOrCurrentPage = P.GroupScopesOrCurrentPage
local ParseGroupDetailMove = P.ParseGroupDetailMove
local OutlineScopeSettingForText = P.OutlineScopeSettingForText
local ParseBorderThicknessShortcut = P.ParseBorderThicknessShortcut
local ParseUnitDetailOffsetShortcut = P.ParseUnitDetailOffsetShortcut
local CASTBAR_DETAIL_PREFIXES = P.CASTBAR_DETAIL_PREFIXES
local CastbarDetailUnitsOrCurrentPage = P.CastbarDetailUnitsOrCurrentPage
local ParseCastbarTextMoveShortcut = P.ParseCastbarTextMoveShortcut
local ParseUnitOpacityShortcut = P.ParseUnitOpacityShortcut
local GroupColorModeScopes = P.GroupColorModeScopes
local GroupBarColorModeForText = P.GroupBarColorModeForText
local ParseGroupFrameColorMode = P.ParseGroupFrameColorMode
local MENU_SELECTOR_VERBS = P.MENU_SELECTOR_VERBS
local HasMenuSelectorVerb = P.HasMenuSelectorVerb
local MenuSelectorAction = P.MenuSelectorAction
local SelectorUnit = P.SelectorUnit
local SelectorGroupScope = P.SelectorGroupScope
local TextSelectorTab = P.TextSelectorTab
local TextSelectorSlot = P.TextSelectorSlot
local TextSelectorIntent = P.TextSelectorIntent
local TextMoveTogetherIntent = P.TextMoveTogetherIntent
local TextMoveTogetherValue = P.TextMoveTogetherValue
local StatusSelectorTab = P.StatusSelectorTab
local StatusSelectorIntent = P.StatusSelectorIntent
local ParseMenuSelectorState = P.ParseMenuSelectorState

local function ContextUnits(ctx)
    local units = {}
    if ctx and type(ctx.lastUnit) == "string" then units[#units + 1] = ctx.lastUnit end
    return units
end

local GROUP_CONTEXT_UNITS = { party = true, raid = true, mythicraid = true }

local function IsGroupContextUnit(unit)
    return type(unit) == "string" and GROUP_CONTEXT_UNITS[unit] == true
end

local function ContextGroups(ctx)
    local groups = {}
    if ctx and IsGroupContextUnit(ctx.lastUnit) then groups[#groups + 1] = ctx.lastUnit end
    return groups
end

local function ShouldUseLastUnitContext(text)
    return ContainsAny(text, {
        "it", "that", "this", "das", "same", "again", "wieder", "back", "more", "mehr",
        "frame", "unitframe", "name", "text", "health", "hp", "power", "width", "height",
        "size", "alpha", "opacity", "position", "offset", "anchor",
    })
end

function A._ParseFollowupAnswer(text, ctx)
    if not ContainsAny(text, {
        "what did you change", "what changed", "what was changed", "what did you do",
        "what did you set", "last change", "previous change", "what is it now",
        "what is it set to", "current value", "value now", "show last change",
    }) then return nil end
    if not ctx then return nil end

    if type(ctx.lastChangeBundle) == "table" and #ctx.lastChangeBundle > 0 then
        local key = ctx.lastSetting
        if type(key) ~= "string" or key == "" then
            local first = ctx.lastChangeBundle[1]
            key = first and first.key
        end
        local setting = key and Registry and Registry:GetSetting(key) or nil
        if setting then
            local value = type(setting.get) == "function" and setting.get() or ctx.lastValue
            return {
                kind = "answer",
                status = "info",
                text = tostring(setting.label or setting.key or "Last setting") .. " is " .. tostring(value) .. ".",
                summary = "Reports the last Assistant setting and current value from context.",
            }
        end
    end

    local actionKey = type(ctx.lastAction) == "string" and ctx.lastAction or nil
    if actionKey and actionKey ~= "" and actionKey ~= "change" then
        local action = Registry and type(Registry.GetAction) == "function" and Registry:GetAction(actionKey) or nil
        local label = ctx.lastActionLabel or (action and action.label) or actionKey
        local message = tostring(ctx.lastActionMessage or "")
        local lines = { "Last Assistant action: " .. tostring(label) .. "." }
        if message ~= "" then lines[#lines + 1] = "Result: " .. message end
        if ctx.lastActionUndoable == true then
            lines[#lines + 1] = "You can type 'undo' to revert it."
        end
        return {
            kind = "answer",
            status = "info",
            text = table.concat(lines, "\n"),
            summary = "Reports the last Assistant action from context.",
        }
    end

    if actionKey == "change" then
        return {
            kind = "answer",
            status = "info",
            text = "No previous Assistant setting change is available yet.",
            summary = "Reports the last Assistant change from context.",
        }
    end
    return nil
end

local function BuildFollowup(text, ctx)
    if not (ctx and type(ctx.lastChangeBundle) == "table") then return nil end
    local positiveTerms = {
        "bigger", "larger", "higher", "thicker", "wider", "taller", "increase", "raise", "up", "grow", "stronger",
        "brighter", "lighter", "more opaque", "more visible",
        "groesser", "hoeher", "dicker", "breiter", "heller", "hoch",
    }
    local negativeTerms = {
        "smaller", "lower", "thinner", "narrower", "shorter", "less", "decrease", "reduce", "down", "shrink", "weaker",
        "darker", "dimmer", "more transparent", "less opaque", "fainter",
        "kleiner", "tiefer", "duenner", "weniger", "dunkler", "runter",
    }
    local neutralTerms = {
        "more", "mehr", "weiter", "further", "farther", "again", "do it again", "same again", "once more", "one more",
        "another", "repeat", "keep going", "continue", "nochmal", "noch mal",
    }
    local oppositeTerms = {
        "opposite", "opposite way", "other way", "reverse", "reverse it", "undo direction", "andersrum", "umgekehrt",
    }
    local reverseCorrectionTerms = {
        "too much", "too far", "not that much", "went too far", "go back a bit", "back a bit", "a bit back",
        "zu viel", "zu weit", "etwas zurueck",
    }
    local tooPositiveTerms = {
        "too high", "too big", "too large", "too thick", "too wide", "too tall", "too bright", "too visible", "too opaque",
        "zu hoch", "zu gross", "zu dick", "zu breit", "zu hell",
    }
    local tooNegativeTerms = {
        "too low", "too small", "too thin", "too narrow", "too short", "too dark", "too transparent", "not visible enough",
        "zu niedrig", "zu klein", "zu duenn", "zu schmal", "zu dunkel",
    }
    local notEnoughTerms = {
        "not enough", "needs more", "need more", "more still", "still more", "not far enough",
        "not big enough", "not high enough", "not wide enough", "not visible enough",
        "nicht genug", "mehr noch",
    }
    local replayTerms = {
        "too", "also", "as well", "same", "same for", "same on", "same to",
        "do the same", "do that", "do it", "apply that", "apply it", "copy that", "copy it",
        "auch", "auch fuer", "auch fur", "genauso", "genauso fuer", "genauso fur",
        "das auch", "mach das", "mach das gleiche", "das gleiche fuer", "das gleiche fur",
    }
    local rightIntent = ContainsAny(text, { "right", "rechts" })
    local leftIntent = ContainsAny(text, { "left", "links" })
    local upIntent = ContainsAny(text, { "up", "higher", "hoch", "oben", "hoeher" })
    local downIntent = ContainsAny(text, { "down", "lower", "tiefer", "runter", "unten" })
    local followDirection = rightIntent and "right" or (leftIntent and "left" or (upIntent and "up" or (downIntent and "down" or nil)))
    local forcePositive = ContainsAny(text, { "more opaque", "less transparent", "more visible", "brighter", "lighter", "heller" })
    local forceNegative = ContainsAny(text, { "more transparent", "less opaque", "darker", "dimmer", "fainter", "dunkler" })
    local positiveIntent = forcePositive or (ContainsAny(text, positiveTerms) and not forceNegative)
    local negativeIntent = forceNegative or (ContainsAny(text, negativeTerms) and not forcePositive)
    local neutralIntent = ContainsAny(text, neutralTerms)
    local neutralIncreaseIntent = ContainsAny(text, { "more", "mehr", "weiter", "further", "farther", "once more", "one more", "another", "keep going", "continue" })
    local oppositeIntent = ContainsAny(text, oppositeTerms)
    local reverseCorrectionIntent = ContainsAny(text, reverseCorrectionTerms)
    local tooPositiveIntent = ContainsAny(text, tooPositiveTerms)
    local tooNegativeIntent = ContainsAny(text, tooNegativeTerms)
    local notEnoughIntent = ContainsAny(text, notEnoughTerms)
    local targetReplayIntent = ContainsAny(text, replayTerms)
    local pureNumberIntent = tostring(text or ""):match("^[-+]?%d+%.?%d*$") ~= nil
    local exactValueReference = ContainsAny(text, {
        "it", "that", "this", "last setting", "last value", "actually", "instead", "rather",
        "no", "nope", "wait", "oops", "set it", "make it", "change it", "use",
    })
    local exactValueIntent = pureNumberIntent
        or ContainsAny(text, { "min", "minimum", "max", "maximum" })
        or (exactValueReference and FirstNumber(text) ~= nil)
    local commandIntent = ContainsAny(text, {
        "set", "change", "make", "turn", "enable", "disable", "show", "hide", "move", "nudge", "shift",
        "create", "select", "use", "reset", "copy", "open", "import", "export", "rename", "delete", "remove", "switch", "assign",
        "setze", "stelle", "aktivieren", "deaktivieren", "einschalten", "ausschalten", "anzeigen", "verstecken", "einblenden", "ausblenden", "verschiebe", "verschieben",
    })
    local explicitFollowupReference = ContainsAny(text, { "it", "that", "this", "same", "do it", "do that", "again", "more", "less", "opposite", "other way" })
    local wordCount = 0
    for _ in tostring(text or ""):gmatch("%S+") do wordCount = wordCount + 1 end
    local bareDirectionalFollowup = ContainsAny(text, {
        "left", "right", "up", "down",
        "move left", "move right", "move up", "move down",
        "nudge left", "nudge right", "nudge up", "nudge down",
        "shift left", "shift right", "shift up", "shift down",
    }) and wordCount <= 3 and not ContainsAny(text, { "anchor", "attach", "point", "bottom left", "bottom right", "top left", "top right" })
    local hasIntent = positiveIntent or negativeIntent or neutralIntent or oppositeIntent or reverseCorrectionIntent
        or tooPositiveIntent or tooNegativeIntent or notEnoughIntent or exactValueIntent
        or leftIntent or rightIntent or targetReplayIntent
    if not hasIntent then return nil end
    local units = DetectUnits(text)
    local groups = DetectGroups(text)

    local function FollowupSiblingKey(key, direction)
        key = tostring(key or "")
        if direction == "left" or direction == "right" then
            if key:find("Y$") then return (key:gsub("Y$", "X")) end
            if key:find("X$") then return key end
        elseif direction == "up" or direction == "down" then
            if key:find("X$") then return (key:gsub("X$", "Y")) end
            if key:find("Y$") then return key end
        end
        return nil
    end

    local function FollowupExactValue(setting)
        if not (setting and setting.type == "number") then return nil end
        if ContainsAny(text, { "maximum", "max" }) and setting.max ~= nil then return setting.max end
        if ContainsAny(text, { "minimum", "min" }) and setting.min ~= nil then return setting.min end
        local value = A._ExplicitNumberValue(text)
        if value == nil then value = FirstNumber(text) end
        if value == nil then return nil end
        if setting.percent == true and value > 1 then value = value / 100 end
        return value
    end

    local function FollowupAmount(setting, prevDelta, explicitAmount)
        local amount = explicitAmount
        local step = (setting and tonumber(setting.step)) or 1
        if amount == nil and prevDelta ~= nil and prevDelta ~= 0 then amount = math.abs(prevDelta) end
        if amount == nil or amount == 0 then amount = step end
        if explicitAmount == nil and ContainsAny(text, { "a bit", "bit", "a little", "little", "slightly", "tiny", "small step", "etwas" }) then
            amount = amount / 2
            if amount < step then amount = step end
        elseif explicitAmount == nil and ContainsAny(text, { "half", "half as much" }) then
            amount = amount / 2
            if amount < step then amount = step end
        elseif explicitAmount == nil and not reverseCorrectionIntent and ContainsAny(text, { "a lot", "much", "way more", "way less", "far more", "far less", "big step", "large step", "twice", "double" }) then
            amount = amount * 2
        end
        if setting and setting.percent == true and amount > 1 then amount = amount / 100 end
        return amount
    end

    if #units == 0 and #groups == 0 and exactValueIntent then
        local exactChanges = {}
        for i = 1, #ctx.lastChangeBundle do
            local prev = ctx.lastChangeBundle[i]
            local setting = prev and prev.key and Registry:GetSetting(prev.key)
            local value = FollowupExactValue(setting)
            if value ~= nil then
                exactChanges[#exactChanges + 1] = { setting = setting, value = value }
            end
        end
        if #exactChanges > 0 then
            return {
                kind = "changes",
                changes = exactChanges,
                label = "Set previous numeric value",
                summary = "Uses the previous Assistant numeric setting as context.",
            }
        end
    end

    if #units == 0 and #groups == 0
        and (positiveIntent or negativeIntent or neutralIntent or oppositeIntent or reverseCorrectionIntent
            or tooPositiveIntent or tooNegativeIntent or notEnoughIntent or leftIntent or rightIntent)
        and (not commandIntent or explicitFollowupReference or bareDirectionalFollowup)
    then
        local repeatChanges = {}
        for i = 1, #ctx.lastChangeBundle do
            local prev = ctx.lastChangeBundle[i]
            local setting = prev and prev.key and Registry:GetSetting(prev.key)
            if setting and setting.type == "number" then
                local direction = followDirection or prev.direction
                local siblingKey = followDirection and FollowupSiblingKey(prev.key, followDirection) or nil
                local sibling = siblingKey and Registry:GetSetting(siblingKey) or nil
                if sibling and sibling.type == "number" then setting = sibling end
                local relativeDelta = nil
                local prevDelta = tonumber(prev.relativeDelta)
                local explicitAmount = A._RelativeNumberAmountForText(text)
                local amount = FollowupAmount(setting, prevDelta, explicitAmount)
                local previousNegative = (prev.direction == "left" or prev.direction == "down") or (prevDelta ~= nil and prevDelta < 0)
                local sign = nil
                if (oppositeIntent or reverseCorrectionIntent) and prevDelta ~= nil and prevDelta ~= 0 then
                    sign = previousNegative and 1 or -1
                elseif reverseCorrectionIntent or tooPositiveIntent then
                    sign = -1
                elseif tooNegativeIntent then
                    sign = 1
                elseif notEnoughIntent and prevDelta ~= nil and prevDelta ~= 0 then
                    sign = previousNegative and -1 or 1
                elseif notEnoughIntent then
                    sign = 1
                elseif followDirection == "left" or followDirection == "down" then
                    sign = -1
                elseif followDirection == "right" or followDirection == "up" then
                    sign = 1
                elseif negativeIntent then
                    sign = -1
                elseif positiveIntent then
                    sign = 1
                elseif neutralIntent and (prevDelta ~= nil or neutralIncreaseIntent) then
                    sign = previousNegative and -1 or 1
                end
                if sign ~= nil then
                    relativeDelta = amount * sign
                end
                if relativeDelta ~= nil then
                    repeatChanges[#repeatChanges + 1] = { setting = setting, relativeDelta = relativeDelta, direction = direction }
                end
            end
        end
        if #repeatChanges > 0 then
            return {
                kind = "changes",
                changes = repeatChanges,
                label = "Repeat previous adjustment",
                summary = "Uses the previous Assistant numeric adjustment as context.",
            }
        end
    end
    if #units == 0 and #groups == 0 then return nil end
    if not targetReplayIntent then return nil end

    local function GlobalScopeForGroup(scope)
        if scope == "party" then return "gf_party" end
        if scope == "raid" or scope == "mythicraid" then return "gf_raid" end
        return scope
    end

    local function AddReplayTarget(out, settingUnit, frameType, attribute, value)
        if not (settingUnit and frameType and attribute) then return end
        local found = Registry:FindSettings({ unit = settingUnit, frameType = frameType, attribute = attribute })
        if found[1] then
            out[#out + 1] = { setting = found[1], value = value }
        end
    end

    local changes = {}
    for i = 1, #ctx.lastChangeBundle do
        local prev = ctx.lastChangeBundle[i]
        if prev and prev.attribute ~= nil and prev.value ~= nil then
            for j = 1, #units do
                local targetFrameType = prev.frameType == "group" and "unitframe" or prev.frameType
                AddReplayTarget(changes, units[j], targetFrameType, prev.attribute, prev.value)
            end
            for j = 1, #groups do
                local scope = groups[j]
                local targetFrameType = prev.frameType == "unitframe" and "group" or prev.frameType
                local settingUnit = scope
                if targetFrameType == "globalBars" or targetFrameType == "fonts" then
                    settingUnit = GlobalScopeForGroup(scope)
                end
                AddReplayTarget(changes, settingUnit, targetFrameType, prev.attribute, prev.value)
            end
        end
    end
    if #changes == 0 then
        for i = 1, #ctx.lastChangeBundle do
            local prev = ctx.lastChangeBundle[i]
            if prev and prev.attribute ~= nil and prev.value ~= nil and (prev.frameType == "unitframe" or prev.frameType == "group") then
                for j = 1, #units do
                    AddReplayTarget(changes, units[j], "unitframe", prev.attribute, prev.value)
                end
                for j = 1, #groups do
                    AddReplayTarget(changes, groups[j], "group", prev.attribute, prev.value)
                end
            end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Apply previous change to another frame",
        summary = "Uses the last Assistant change as context.",
    }
end

local function BuildBooleanCorrection(text, ctx)
    if not (ctx and type(ctx.lastSetting) == "string") then return nil end
    local value = DetectBoolean(text)
    if value == nil then return nil end
    if not ContainsAny(text, {
        "again", "wieder", "doch", "actually", "ne",
        "it", "that", "this", "back", "back on", "back off",
        "turn it", "turn that", "same setting", "last setting",
    }) then return nil end
    local setting = Registry:GetSetting(ctx.lastSetting)
    if not setting or setting.type ~= "boolean" then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = "Correct previous setting",
        summary = "Uses the last Assistant setting as context.",
    }
end

local function ParseSetting(text, ctx)
    local frameType = DetectFrameType(text, ctx)
    local direction = DetectDirection(text, ctx)
    local movementIntent = direction and ContainsAny(text, { "move", "nudge", "shift", "verschiebe", "offset", "position", "x", "y" }) and not ContainsAny(text, { "anchor" })
    local attr = movementIntent and ((direction == "left" or direction == "right") and "offsetX" or "offsetY") or DetectAttribute(text, frameType)
    if not attr then return nil end
    if attr == "enabled" and ContainsAny(text, {
        "in group", "when solo", "while solo", "show player", "hide player", "player in group",
        "show while solo", "while in group", "group when solo",
        "out of combat", "outside combat", "in combat", "while mounted", "when mounted", "mounted",
        "in vehicle", "while in vehicle", "when in vehicle", "resting", "stealthed", "load condition",
        "dispel overlay", "unitframe dispel", "debuff overlay",
    }) then
        return nil
    end
    if (attr == "width" or attr == "height") and ContainsAny(text, {
        "width mode", "height mode", "width source", "height source",
        "power bar height", "mana bar height", "energy bar height",
        "portrait height", "portrait width", "castbar height", "castbar width",
        "icon height", "icon width", "text height", "text width",
    }) then
        return nil
    end
    local useLastUnit = ShouldUseLastUnitContext(text)
    if useLastUnit and frameType == "unitframe" and ctx and IsGroupContextUnit(ctx.lastUnit) then
        frameType = "group"
    end

    local units = {}
    if frameType == "group" then
        units = DetectGroups(text)
    else
        units = DetectUnits(text)
    end
    if #units == 0 and useLastUnit then
        if frameType == "group" then
            units = ContextGroups(ctx)
        else
            units = ContextUnits(ctx)
        end
    end

    local value
    local relativeDelta
    if attr == "offsetX" or attr == "offsetY" then
        local amount = FirstNumber(text) or 10
        if direction == "left" or direction == "down" then amount = -amount end
        value = nil
        relativeDelta = amount
    elseif attr == "width" or attr == "height" then
        relativeDelta = RelativeNumberDeltaForText(nil, text, 10)
        if relativeDelta == nil then value = FirstNumber(text) end
    else
        value = DetectBoolean(text)
    end

    if value == nil and relativeDelta == nil and (attr == "width" or attr == "height") then
        local candidates
        if #units > 0 then
            candidates = Registry:FindSettings({ units = units, frameType = frameType, attribute = attr })
        else
            candidates = Registry:FindSettings({ frameType = frameType, attribute = attr })
        end
        if #candidates == 1 then
            local setting = candidates[1]
            local parts = {}
            if setting.min ~= nil then parts[#parts + 1] = "min " .. tostring(setting.min) end
            if setting.max ~= nil then parts[#parts + 1] = "max " .. tostring(setting.max) end
            if setting.step ~= nil then parts[#parts + 1] = "step " .. tostring(setting.step) end
            local hint = #parts > 0 and ("Use a number (" .. table.concat(parts, ", ") .. ").") or "Use a number."
            return {
                kind = "answer",
                status = "ambiguous",
                text = "What should " .. tostring(setting.label or "this setting") .. " be set to? " .. hint,
                summary = "Registry-backed value clarification.",
            }
        end
    end

    if value == nil and relativeDelta == nil and attr ~= "enabled" then return nil end
    if value == nil and relativeDelta == nil and attr == "enabled" then value = DetectBoolean(text) end
    if value == nil and relativeDelta == nil then return nil end

    local candidates
    if #units > 0 then
        candidates = Registry:FindSettings({ units = units, frameType = frameType, attribute = attr })
    else
        candidates = Registry:FindSettings({ frameType = frameType, attribute = attr })
    end
    if #candidates == 0 then
        return {
            kind = "unknown",
            text = "That setting exists conceptually, but it is not registered for Assistant control yet.",
            status = "failed",
        }
    end
    if #units == 0 and #candidates > 1 then
        if ContainsAny(text, { "all", "all of", "every", "each", "alle", "alles", "jede", "jeder", "jedes" }) then
            return {
                kind = "changes",
                changes = BuildChanges(candidates, value, relativeDelta, direction),
                label = "Assistant setting change",
                bulkSafe = true,
                summary = "Registry-backed settings change.",
            }
        end
        return {
            kind = "ambiguous",
            choices = BuildChanges(candidates, value, relativeDelta, direction),
            label = "Multiple matching settings",
        }
    end
    return {
        kind = "changes",
        changes = BuildChanges(candidates, value, relativeDelta, direction),
        label = "Assistant setting change",
        summary = "Registry-backed settings change.",
    }
end

P.ContextUnits = ContextUnits
P.GROUP_CONTEXT_UNITS = GROUP_CONTEXT_UNITS
P.IsGroupContextUnit = IsGroupContextUnit
P.ContextGroups = ContextGroups
P.ShouldUseLastUnitContext = ShouldUseLastUnitContext
P.BuildFollowup = BuildFollowup
P.BuildBooleanCorrection = BuildBooleanCorrection
P.ParseSetting = ParseSetting
