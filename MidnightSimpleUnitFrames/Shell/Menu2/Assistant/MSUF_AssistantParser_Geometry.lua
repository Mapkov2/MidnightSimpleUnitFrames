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

local function BuildChanges(settings, value, relativeDelta, direction)
    local changes = {}
    for i = 1, #settings do
        changes[#changes + 1] = {
            setting = settings[i],
            value = value,
            relativeDelta = relativeDelta,
            direction = direction,
        }
    end
    return changes
end

function P.ParseUnitSizeMatchShortcut(text)
    if not ContainsAny(text, {
        "as big as", "same size as", "the same size as", "same width and height as",
        "so gross wie", "gleich gross wie", "gleiche groesse wie", "dieselbe groesse wie",
    }) then
        return nil
    end
    if DetectGroups(text)[1] or ContainsAny(text, { "castbar", "cast bar", "class power", "class resource", "aura", "auras" }) then
        return nil
    end

    local unitTerms = {
        targettarget = { "targettarget", "target of target", "tot", "ziel des ziels" },
        focustarget = { "focustarget", "focus target", "fokus ziel" },
        player = { "player", "player frame", "spieler", "spieler frame", "self", "ich" },
        target = { "target", "target frame", "ziel", "ziel frame" },
        focus = { "focus", "focus frame", "fokus", "fokus frame" },
        pet = { "pet", "pet frame", "begleiter", "begleiter frame" },
        boss = { "boss", "boss frame", "boss frames", "bossframe", "bossframes" },
    }
    local function unitInFragment(fragment)
        fragment = Normalize(fragment or "")
        if fragment == "" then return nil end
        for i = 1, #UNIT_ORDER do
            local unit = UNIT_ORDER[i]
            local terms = unitTerms[unit] or { unit }
            for j = 1, #terms do
                if HasPhrase(fragment, terms[j]) then return unit end
            end
        end
        return nil
    end
    local target, source
    local patterns = {
        "^(.-)%s+as big as%s+(.+)$",
        "^(.-)%s+the same size as%s+(.+)$",
        "^(.-)%s+same size as%s+(.+)$",
        "^(.-)%s+same width and height as%s+(.+)$",
        "^(.-)%s+so gross wie%s+(.+)$",
        "^(.-)%s+gleich gross wie%s+(.+)$",
        "^(.-)%s+gleiche groesse wie%s+(.+)$",
        "^(.-)%s+dieselbe groesse wie%s+(.+)$",
    }
    for i = 1, #patterns do
        local before, after = text:match(patterns[i])
        target = unitInFragment(before)
        source = unitInFragment(after)
        if target and source and target ~= source then break end
        target, source = nil, nil
    end
    if not target or not source then return nil end

    local widthSetting = Registry and Registry:GetSetting(target .. ".width")
    local heightSetting = Registry and Registry:GetSetting(target .. ".height")
    if not widthSetting or not heightSetting then return nil end

    local sourceWidth = Registry and Registry:GetSetting(source .. ".width")
    sourceWidth = sourceWidth and type(sourceWidth.get) == "function" and tonumber(sourceWidth.get()) or nil
    local sourceHeight = Registry and Registry:GetSetting(source .. ".height")
    sourceHeight = sourceHeight and type(sourceHeight.get) == "function" and tonumber(sourceHeight.get()) or nil
    if sourceWidth == nil or sourceHeight == nil then return nil end

    return {
        kind = "changes",
        changes = {
            { setting = widthSetting, value = sourceWidth, valueLabel = tostring(sourceWidth) },
            { setting = heightSetting, value = sourceHeight, valueLabel = tostring(sourceHeight) },
        },
        label = "Match unitframe size",
        summary = "Sets the target unitframe width and height to the current source unitframe size.",
        bulkSafe = true,
    }
end

local function ParseUnsupportedDetailShortcut(text)
    if ContainsAny(text, { "combat timer alpha", "combat timer opacity", "combat timer transparency" }) then
        return {
            kind = "unknown",
            text = "Combat Timer alpha is not exposed by the current MSUF UI/DB. The Assistant can change real Combat Timer controls like enable, size, position, anchor, lock, and colors.",
            status = "failed",
        }
    end
    return nil
end

local function CurrentPageUnit()
    local page = M and M.activeKey
    if type(page) ~= "string" then return nil end
    for i = 1, #ALL_UNITFRAMES do
        local unit = ALL_UNITFRAMES[i]
        if UnitPageKey(unit) == page then return unit end
    end
    return nil
end

local function DetailUnitsOrCurrentPage(text)
    local units = DetectUnits(text)
    if #units > 0 then return units, false end
    local pageUnit = CurrentPageUnit()
    if pageUnit then return { pageUnit }, false end
    return {}, true
end

local function BuildUnitDetailChoices(attr, value, relativeDelta, direction)
    local settings = {}
    for i = 1, #ALL_UNITFRAMES do
        local setting = Registry and Registry:GetSetting(tostring(ALL_UNITFRAMES[i]) .. "." .. attr)
        if setting then settings[#settings + 1] = setting end
    end
    return {
        kind = "ambiguous",
        choices = BuildChanges(settings, value, relativeDelta, direction),
        label = "Multiple matching unitframe detail settings",
    }
end

local function HasAllUnitDetailScopeIntent(text)
    return ContainsAny(text, {
        "all", "all of", "for all", "every", "each",
        "alle", "alles", "fuer alle", "jede", "jeder", "jedes", "jeweils",
    })
end

local function AllUnitDetailUnits()
    local units = {}
    for i = 1, #ALL_UNITFRAMES do units[#units + 1] = ALL_UNITFRAMES[i] end
    return units
end

local function ParsePortraitDetailShortcut(text)
    if not ContainsAny(text, { "portrait", "portraits" }) then return nil end
    if ContainsAny(text, { "color", "colour", "farbe", "reset" }) then return nil end
    if ContainsAny(text, { "move", "nudge", "shift", "verschiebe", "offset" }) and DetectDirection(text, {}) then return nil end

    local attr
    local value
    local relativeDelta
    local direction

    if ContainsAny(text, { "border thickness", "border size", "border thicker", "border thinner", "thicker", "thinner", "dicker", "duenner" }) then
        attr = "portraitBorderThickness"
        relativeDelta = RelativeNumberDeltaForText({ step = 1 }, text, 1)
        if relativeDelta == nil then value = FirstNumber(text) end
    elseif ContainsAny(text, { "size", "size override", "bigger", "smaller", "larger", "groesser", "kleiner" }) then
        attr = "portraitSizeOverride"
        relativeDelta = RelativeNumberDeltaForText({ step = 1 }, text, 4)
        if relativeDelta == nil then value = FirstNumber(text) end
    elseif ContainsAny(text, { "border" }) then
        attr = "portraitBorderStyle"
        if ContainsAny(text, { "off", "disable", "disabled", "hide", "none", "no border", "aus", "deaktivieren" }) then
            value = "NONE"
        elseif ContainsAny(text, { "on", "enable", "enabled", "show", "solid", "an", "aktivieren" }) then
            value = "SOLID"
        elseif ContainsAny(text, { "class color", "class" }) then
            value = "CLASS_COLOR"
        elseif ContainsAny(text, { "reaction" }) then
            value = "REACTION"
        elseif ContainsAny(text, { "custom" }) then
            value = "CUSTOM"
        end
    else
        attr = "portraitMode"
        if ContainsAny(text, { "off", "disable", "disabled", "hide", "aus", "deaktivieren" }) then
            value = "OFF"
        elseif ContainsAny(text, { "right" }) then
            value = "RIGHT"
        elseif ContainsAny(text, { "on", "enable", "enabled", "show", "left", "an", "aktivieren" }) then
            value = "LEFT"
        end
    end

    if not attr or (value == nil and relativeDelta == nil) then return nil end
    local units, ambiguous
    if HasAllUnitDetailScopeIntent(text) then
        units = AllUnitDetailUnits()
        ambiguous = false
    else
        units, ambiguous = DetailUnitsOrCurrentPage(text)
    end
    if ambiguous then return BuildUnitDetailChoices(attr, value, relativeDelta, direction) end
    local changes = {}
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, direction = direction } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Portrait detail",
        bulkSafe = #changes > 1,
        summary = "Changes a registered portrait detail control.",
    }
end

local DETAIL_MOVE_SPECS = {
    { terms = { "portrait" }, x = "portraitOffsetX", y = "portraitOffsetY", label = "Move portrait" },
    { terms = { "name text", "frame name text", "unit name text", "unitframe name", "unit name", "name label", "name labels", "names", "name" }, x = "nameOffsetX", y = "nameOffsetY", label = "Move name text" },
    { terms = { "hp text", "health text", "health value", "hp value", "hp number", "health number", "hp label", "health label", "life text", "hp", "health", "leben", "gesundheit", "lebenspunkte", "lebensanzeige" }, x = "hpOffsetX", y = "hpOffsetY", label = "Move HP text" },
    { terms = { "power text", "mana text", "power value", "mana value", "power number", "mana number", "power label", "mana label", "energie text", "energie", "ressource", "ressourcen", "power", "mana" }, x = "powerOffsetX", y = "powerOffsetY", label = "Move power text" },
}

local GROUP_DETAIL_MOVE_SPECS = {
    { terms = { "name text", "frame name text", "unit name text", "unit name", "frame name", "name label", "name labels", "party name", "raid name", "group name", "names", "name" }, x = "nameOffsetX", y = "nameOffsetY", label = "Move group name text" },
    { terms = { "hp text", "health text", "health value", "hp value", "hp number", "health number", "hp label", "health label", "life text", "party hp", "party health", "raid hp", "raid health", "group hp", "group health", "hp", "health", "leben", "gesundheit", "lebenspunkte", "lebensanzeige" }, x = "hpOffsetX", y = "hpOffsetY", label = "Move group HP text" },
    { terms = { "power text", "mana text", "power value", "mana value", "power number", "mana number", "power label", "mana label", "energie text", "energie", "ressource", "ressourcen", "party power", "party mana", "raid power", "raid mana", "group power", "group mana", "power", "mana" }, x = "powerOffsetX", y = "powerOffsetY", label = "Move group power text" },
}

local OM = A._OffsetMoveHelpers or {}
A._OffsetMoveHelpers = OM

OM.moveTerms = OM.moveTerms or {
    "move", "nudge", "shift", "verschiebe", "offset", "x offset", "y offset",
    "x position", "y position", "x pos", "y pos",
    "closer", "nearer", "farther", "further", "away from",
    "naeher", "weiter weg", "ran", "heran",
}

OM.excludeTerms = OM.excludeTerms or {
    "aura", "auras", "buff", "buffs", "debuff", "debuffs",
    "cooldown spiral", "cooldown text", "stack text",
}

OM.closerTerms = OM.closerTerms or { "closer", "nearer", "naeher", "ran", "heran" }
OM.fartherTerms = OM.fartherTerms or { "farther", "further", "away from", "weiter weg" }

function OM.HasIntent(text)
    if ContainsAny(text, OM.excludeTerms) then return false end
    if ContainsAny(text, OM.moveTerms) then return true end
    return false
end

function OM.Clean(text)
    text = Normalize(text)
    text = text:gsub("[^%w%s]", " ")
    return Trim(text:gsub("%s+", " "))
end

function OM.AxislessPhrase(text)
    text = " " .. OM.Clean(text) .. " "
    text = text:gsub(" x ", " ")
    text = text:gsub(" y ", " ")
    text = text:gsub(" offset ", " ")
    text = text:gsub(" position ", " ")
    text = text:gsub(" pos ", " ")
    return Trim(text:gsub("%s+", " "))
end

function OM.RootDetailBlocked(setting, text)
    local attr = tostring(setting and setting.attribute or "")
    if attr ~= "offsetX" and attr ~= "offsetY" then return false end
    local label = OM.Clean(tostring(setting and setting.label or ""))
    for _, term in ipairs({
        "name", "health", "hp", "power", "mana", "portrait", "icon", "label", "text",
        "ready check", "group number", "raid marker", "kick", "interrupt", "status", "indicator",
        "leben", "gesundheit", "lebenspunkte", "lebensanzeige", "energie", "ressource", "ressourcen",
    }) do
        if ContainsAny(text, { term }) and not HasPhrase(label, term) then return true end
    end
    return false
end

function OM.ScopeBlocked(setting, text)
    if type(setting) ~= "table" then return true end
    local frameType = tostring(setting.frameType or "")
    if frameType == "group" then
        local wanted
        if HasPhrase(text, "mythicraid") or HasPhrase(text, "mythic raid") then
            wanted = "mythicraid"
        elseif HasPhrase(text, "party") then
            wanted = "party"
        elseif HasPhrase(text, "raid") then
            wanted = "raid"
        end
        if wanted then return tostring(setting.unit or OM.UnitFromSetting(setting) or "") ~= wanted end
        return false
    end
    local units = DetectUnits(text)
    if #units == 0 then return false end
    local unit = tostring(setting.unit or OM.UnitFromSetting(setting) or "")
    if unit == "" or unit == "global" then return false end
    for i = 1, #units do
        if units[i] == unit then return false end
    end
    return true
end

function OM.PhraseScore(cleanText, phrase)
    phrase = OM.AxislessPhrase(phrase)
    if #phrase < 3 then return 0 end
    if HasPhrase(cleanText, phrase) then return #Compact(phrase) end
    local matched = 0
    for token in phrase:gmatch("%S+") do
        if #token >= 2 then
            if not HasPhrase(cleanText, token) then return 0 end
            matched = matched + 1
        end
    end
    return matched > 1 and #Compact(phrase) or 0
end

function OM.Axis(setting)
    if type(setting) ~= "table" or setting.type ~= "number" then return nil end
    local key = tostring(setting.key or "")
    local attr = tostring(setting.attribute or "")
    local label = tostring(setting.label or "")
    local hay = (key .. " " .. attr .. " " .. label):lower()
    if hay:find("offsetx", 1, true)
        or hay:find(" offset x", 1, true)
        or hay:find(" x offset", 1, true)
        or hay:find(" x position", 1, true)
        or hay:find("x pos", 1, true)
        or ((key:match("X$") or attr:match("X$")) and hay:find("offset", 1, true))
    then
        return "x"
    end
    if hay:find("offsety", 1, true)
        or hay:find(" offset y", 1, true)
        or hay:find(" y offset", 1, true)
        or hay:find(" y position", 1, true)
        or hay:find("y pos", 1, true)
        or ((key:match("Y$") or attr:match("Y$")) and hay:find("offset", 1, true))
    then
        return "y"
    end
    return nil
end

function OM.IsNonAuraSetting(setting)
    if type(setting) ~= "table" then return false end
    local frameType = tostring(setting.frameType or "")
    if frameType == "aura" or frameType == "groupAura" then return false end
    local key = tostring(setting.key or ""):lower()
    local label = tostring(setting.label or ""):lower()
    local category = tostring(setting.category or ""):lower()
    if key:find("aura", 1, true) or label:find("aura", 1, true) or category:find("aura", 1, true) then return false end
    return OM.Axis(setting) ~= nil
end

function OM.RegisteredSettings()
    if not (Registry and type(Registry.AllSettings) == "function") then return {} end
    local settings = Registry:AllSettings()
    local count = #(settings or {})
    if OM.cache and OM.cacheCount == count then return OM.cache end
    local out = {}
    for i = 1, count do
        local setting = settings[i]
        local axis = OM.Axis(setting)
        if axis and OM.IsNonAuraSetting(setting) then
            out[#out + 1] = { setting = setting, axis = axis }
        end
    end
    OM.cache = out
    OM.cacheCount = count
    return out
end

function OM.AxisForDirection(direction)
    if direction == "left" or direction == "right" then return "x" end
    if direction == "up" or direction == "down" then return "y" end
    return nil
end

function OM.SignedDelta(text, direction, fallback)
    local amount = FirstNumber(text) or fallback or 10
    if direction == "left" or direction == "down" then amount = -amount end
    return amount
end

function OM.ReadValue(setting)
    if setting and type(setting.get) == "function" then
        local ok, value = pcall(setting.get)
        if ok then return value end
    end
    return nil
end

function OM.UnitFromSetting(setting)
    local unit = setting and setting.unit
    if type(unit) == "string" and unit ~= "" and unit ~= "global" then return unit end
    local key = tostring(setting and setting.key or "")
    local prefix = key:match("^([^%.]+)")
    if prefix == "gf_party" then return "party" end
    if prefix == "gf_raid" then return "raid" end
    if prefix == "gf_mythicraid" then return "mythicraid" end
    return prefix
end

function OM.PortraitCloserDelta(setting, text)
    if not ContainsAny(text, OM.closerTerms) and not ContainsAny(text, OM.fartherTerms) then return nil end
    if not setting or tostring(setting.attribute or "") ~= "portraitOffsetX" then return nil end
    local unit = OM.UnitFromSetting(setting)
    local modeSetting = unit and Registry and Registry:GetSetting(tostring(unit) .. ".portraitMode")
    local mode = tostring(OM.ReadValue(modeSetting) or "LEFT")
    local leftSide = mode ~= "RIGHT"
    local closer = ContainsAny(text, OM.closerTerms)
    local amount = FirstNumber(text) or 10
    local delta = closer and (leftSide and amount or -amount) or (leftSide and -amount or amount)
    return delta, delta >= 0 and "right" or "left"
end

function OM.Score(row, text, axis)
    if not row or not row.setting or row.axis ~= axis then return 0 end
    if OM.ScopeBlocked(row.setting, text) then return 0 end
    if OM.RootDetailBlocked(row.setting, text) then return 0 end
    local suffix = axis == "x" and " x offset" or " y offset"
    local score = SettingMatchScore and SettingMatchScore(row.setting, text .. suffix) or 0
    if score == 0 then
        suffix = axis == "x" and " x position" or " y position"
        score = SettingMatchScore and SettingMatchScore(row.setting, text .. suffix) or 0
    end
    if score and score > 0 then return score end

    local cleanText = OM.Clean(text)
    local best = 0
    local aliases = row.setting.aliases or {}
    for i = 1, #aliases do
        local len = OM.PhraseScore(cleanText, aliases[i])
        if len > best then best = len end
    end
    if row.setting.matchLabel ~= false and row.setting.label then
        local len = OM.PhraseScore(cleanText, row.setting.label)
        if len > best then best = len end
    end
    return best
end

function OM.BestRows(text, axis)
    local rows = OM.RegisteredSettings()
    local best = 0
    local matches = {}
    for i = 1, #rows do
        local row = rows[i]
        local score = OM.Score(row, text, axis)
        if score > best then
            best = score
            matches = { row }
        elseif score > 0 and score == best then
            matches[#matches + 1] = row
        end
    end
    return matches, best
end

function OM.ExplicitMultiIntent(text)
    if HasAllUnitDetailScopeIntent(text) then return true end
    return #DetectUnits(text) + #DetectGroups(text) > 1
end

local function ParseGenericOffsetMove(text)
    if not OM.HasIntent(text) then return nil end

    local direction = DetectDirection(text, {})
    local axis = OM.AxisForDirection(direction) or A._DetailOffsetAxis(text)
    local value
    local relativeDelta

    if direction then
        relativeDelta = OM.SignedDelta(text, direction, 10)
    elseif axis then
        value = FirstNumber(text)
        if value == nil then return nil end
    elseif ContainsAny(text, OM.closerTerms) or ContainsAny(text, OM.fartherTerms) then
        axis = "x"
    else
        return nil
    end

    local rows = {}
    local score = 0
    if axis then
        rows, score = OM.BestRows(text, axis)
    end
    if score <= 0 or #rows == 0 then return nil end

    local changes = {}
    for i = 1, #rows do
        local setting = rows[i].setting
        local delta = relativeDelta
        local moveDirection = direction or axis
        if delta == nil and value == nil then
            delta, moveDirection = OM.PortraitCloserDelta(setting, text)
        end
        if value ~= nil or delta ~= nil then
            changes[#changes + 1] = {
                setting = setting,
                value = value,
                relativeDelta = delta,
                direction = moveDirection,
            }
        end
    end
    if #changes == 0 then return nil end

    if #changes > 1 and not OM.ExplicitMultiIntent(text) then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Which position offset should I move?",
            summary = "The command matched more than one registered non-Aura X/Y offset.",
        }
    end

    return {
        kind = "changes",
        changes = changes,
        label = "Move position offset",
        bulkSafe = #changes > 1,
        summary = "Moves the matching registered non-Aura X/Y offset control.",
    }
end

local function ParseUnitDetailMove(text)
    if ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) then return nil end
    if not ContainsAny(text, { "move", "nudge", "shift", "verschiebe", "offset" }) then return nil end
    local direction = DetectDirection(text, {})
    if not direction then return nil end
    local units = DetectUnits(text)
    if #units == 0 then
        local pageUnit = CurrentPageUnit()
        if pageUnit then
            units = { pageUnit }
        else
            return nil
        end
    end
    local spec
    for i = 1, #DETAIL_MOVE_SPECS do
        if ContainsAny(text, DETAIL_MOVE_SPECS[i].terms) then
            spec = DETAIL_MOVE_SPECS[i]
            break
        end
    end
    if not spec then return nil end
    local attr = (direction == "left" or direction == "right") and spec.x or spec.y
    local amount = FirstNumber(text) or 10
    if direction == "left" or direction == "down" then amount = -amount end
    local changes = {}
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, relativeDelta = amount, direction = direction } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = spec.label,
        summary = "Moves a unitframe detail control by pixels.",
    }
end

local function GroupScopesOrCurrentPage(text)
    local groups = DetectGroups(text)
    if #groups > 0 then return groups end
    local page = M and M.activeKey
    if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
        if M and (M.gfScope == "party" or M.gfScope == "raid" or M.gfScope == "mythicraid") then return { M.gfScope } end
        return { "party" }
    end
    return {}
end

P.TEXT_VISIBILITY_VALUE_TERMS = {
    "current", "actual", "max", "maximum", "percent", "percentage", "pct", "%",
    "current max", "current maximum", "current percent", "current percentage",
    "current/max", "current / max", "current/percent", "current / percent",
    "deficit", "missing", "only percent", "only percentage", "only %",
    "just percent", "just percentage", "percent only", "percentage only",
    "left hp text", "hp left text", "hp text left", "right hp text", "hp right text", "hp text right",
    "center hp text", "centre hp text", "middle hp text", "hp center text", "hp centre text", "hp middle text",
    "left power text", "power left text", "power text left", "right power text", "power right text", "power text right",
    "center power text", "centre power text", "middle power text", "power center text", "power centre text", "power middle text",
    "left mana text", "mana left text", "mana text left", "right mana text", "mana right text", "mana text right",
    "center mana text", "centre mana text", "middle mana text", "mana center text", "mana centre text", "mana middle text",
    "slot", "slots", "text slot", "anchor", "anchoring", "side", "left side", "right side",
    "offset", "position", "pos", "x offset", "y offset", "move", "nudge", "shift",
    "layer", "size", "font size", "color", "colour", "by health", "by power", "by resource", "by mana",
}

P.TEXT_VISIBILITY_VERBS = {
    "turn off", "turn on", "disable", "disabled", "enable", "enabled", "hide", "hidden",
    "show", "display", "visible", "aus", "deaktivieren", "deaktiviert", "ausschalten",
    "ausgeschaltet", "ausblenden", "verstecken", "an", "aktivieren", "aktiviert",
    "einschalten", "eingeschaltet", "anzeigen", "zeigen", "einblenden", "sichtbar",
}

function P.ParseTextVisibilityShortcut(text)
    if ContainsAny(text, { "castbar", "cast bar", "aura", "auras", "buff", "debuff", "class power", "class resource", "class resources" }) then return nil end
    if ContainsAny(text, { "power bar", "powerbar", "mana bar", "mana balken", "power balken" }) then return nil end
    if ContainsAny(text, P.TEXT_VISIBILITY_VALUE_TERMS) then return nil end
    if not ContainsAny(text, P.TEXT_VISIBILITY_VERBS) then return nil end
    local value = DetectBoolean(text)
    if value == nil then return nil end
    local spec
    if ContainsAny(text, { "power text", "mana text", "energy text", "resource text", "energie text", "ressource text" }) then
        spec = { unitAttr = "showPower", groupAttr = "showPowerText", label = "Power Text" }
    elseif ContainsAny(text, { "hp text", "health text", "life text", "leben text", "gesundheit text" }) then
        spec = { unitAttr = "showHP", groupAttr = "showHPText", label = "HP Text" }
    elseif ContainsAny(text, { "name text" }) then
        spec = { unitAttr = "showName", groupAttr = "showName", label = "Name Text" }
    end
    if not spec then return nil end

    local allScope = ContainsAny(text, {
        "all", "all of", "for all", "every", "each",
        "alle", "alles", "fuer alle", "jede", "jeder", "jedes", "jeweils",
    })
    local explicitUnits = DetectUnits(text)
    local explicitGroups = DetectGroups(text)
    local units = {}
    local groups = {}

    if allScope then
        if #explicitGroups > 0 and #explicitUnits == 0 then
            for i = 1, #ALL_GROUPS do groups[#groups + 1] = ALL_GROUPS[i] end
        else
            for i = 1, #ALL_UNITFRAMES do units[#units + 1] = ALL_UNITFRAMES[i] end
        end
    else
        for i = 1, #explicitUnits do units[#units + 1] = explicitUnits[i] end
        for i = 1, #explicitGroups do groups[#groups + 1] = explicitGroups[i] end
    end

    if #units == 0 and #groups == 0 and not allScope then
        local pageGroups = GroupScopesOrCurrentPage(text)
        if #pageGroups > 0 then
            for i = 1, #pageGroups do groups[#groups + 1] = pageGroups[i] end
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units[1] = pageUnit end
        end
    end

    local changes = {}
    local function AddTextVisibilityChange(key)
        local setting = Registry and Registry:GetSetting(key)
        if not setting then return end
        local valueLabel = value and "on" or "off"
        changes[#changes + 1] = {
            setting = setting,
            value = value,
            valueLabel = valueLabel,
            label = tostring(setting.label or "Text visibility") .. " -> " .. valueLabel,
        }
    end
    if #units == 0 and #groups == 0 then
        for i = 1, #ALL_UNITFRAMES do
            AddTextVisibilityChange(tostring(ALL_UNITFRAMES[i]) .. "." .. spec.unitAttr)
        end
    else
        for i = 1, #units do
            AddTextVisibilityChange(tostring(units[i]) .. "." .. spec.unitAttr)
        end
        for i = 1, #groups do
            AddTextVisibilityChange("gf_" .. tostring(groups[i]) .. "." .. spec.groupAttr)
        end
    end
    if #changes == 0 then return nil end

    if (#units + #groups > 1 and not allScope) or (#units == 0 and #groups == 0) then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Which " .. spec.label .. "?",
            summary = "The command names more than one frame, so the Assistant asks which real text visibility toggle to change.",
        }
    end

    return {
        kind = "changes",
        changes = changes,
        label = spec.label .. " Visibility",
        bulkSafe = #changes > 1,
        summary = "Changes the registered text visibility toggle instead of a text-slot value or color mode.",
    }
end

function A._ParseGroupAnchorTargetShortcut(text)
    if ContainsAny(text, { "custom anchor", "custom anchor frame", "anchor frame name", "anchor point", "anchor position" }) then return nil end
    if not ContainsAny(text, { "anchor to", "attach to", "anchored to", "anchor target", "anchor frame" }) then return nil end
    local groups = GroupScopesOrCurrentPage(text)
    if #groups == 0 then return nil end
    local changes = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        local setting = Registry and Registry:GetSetting("gf_" .. scope .. ".anchorToFrame")
        local value = setting and EnumValueForText(setting, text)
        if setting and value ~= nil then changes[#changes + 1] = { setting = setting, value = value } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Set group anchor target",
        summary = "Changes the registered Group Layout Anchor To dropdown.",
    }
end

local function ParseGroupDetailMove(text)
    if ContainsAny(text, { "castbar", "cast bar", "zauberleiste", "portrait" }) then return nil end
    if not ContainsAny(text, { "move", "nudge", "shift", "verschiebe", "offset" }) then return nil end
    local direction = DetectDirection(text, {})
    if not direction then return nil end
    local groups = GroupScopesOrCurrentPage(text)
    if #groups == 0 then return nil end
    local spec
    for i = 1, #GROUP_DETAIL_MOVE_SPECS do
        if ContainsAny(text, GROUP_DETAIL_MOVE_SPECS[i].terms) then
            spec = GROUP_DETAIL_MOVE_SPECS[i]
            break
        end
    end
    if not spec then return nil end
    local attr = (direction == "left" or direction == "right") and spec.x or spec.y
    local amount = FirstNumber(text) or 10
    if direction == "left" or direction == "down" then amount = -amount end
    local changes = {}
    for i = 1, #groups do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, relativeDelta = amount, direction = direction } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = spec.label,
        summary = "Moves a registered group-frame text control by pixels.",
    }
end

function A._DetailOffsetAxis(text)
    if ContainsAny(text, { "x offset", "x position", "x pos", "horizontal", "left right" }) or HasPhrase(text, "x") then return "x" end
    if ContainsAny(text, { "y offset", "y position", "y pos", "vertical", "up down" }) or HasPhrase(text, "y") then return "y" end
    return nil
end

function A._DetailSpecForText(text, specs)
    for i = 1, #(specs or {}) do
        if ContainsAny(text, specs[i].terms) then return specs[i] end
    end
    return nil
end

function A._ParseTextDetailExactOffset(text)
    if ContainsAny(text, { "castbar", "cast bar", "zauberleiste", "portrait" }) then return nil end
    if not ContainsAny(text, { "offset", "position", "pos", "x", "y" }) then return nil end
    local axis = A._DetailOffsetAxis(text)
    if not axis then return nil end
    local value = FirstNumber(text)
    if value == nil then return nil end

    local groupSpec = A._DetailSpecForText(text, GROUP_DETAIL_MOVE_SPECS)
    local unitSpec = A._DetailSpecForText(text, DETAIL_MOVE_SPECS)
    if not groupSpec and not unitSpec then return nil end

    local groups = groupSpec and DetectGroups(text) or {}
    local units = unitSpec and DetectUnits(text) or {}
    local useGroups = #groups > 0
    local useUnits = #units > 0

    if not useGroups and not useUnits then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
            useGroups = #groups > 0
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then
                units = { pageUnit }
                useUnits = true
            end
        end
    end

    local changes = {}
    if useGroups and groupSpec then
        local attr = axis == "x" and groupSpec.x or groupSpec.y
        for i = 1, #groups do
            local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value, direction = axis } end
        end
    elseif useUnits and unitSpec then
        local attr = axis == "x" and unitSpec.x or unitSpec.y
        for i = 1, #units do
            local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value, direction = axis } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Set text offset",
        summary = "Sets a registered unit/group text offset slider value.",
    }
end

local function OutlineScopeSettingForText(text)
    local explicitScope = DetectGlobalScope(text)
    local scope = explicitScope
    if not scope or scope == "shared" then
        local pageUnit = CurrentPageUnit()
        if pageUnit then scope = pageUnit end
    end
    if scope and scope ~= "shared" then
        local scoped = Registry and Registry:GetSetting("barScope." .. tostring(scope) .. ".barOutlineThickness")
        if scoped then return scoped, scope end
    end
    return Registry and Registry:GetSetting("bars.barOutlineThickness"), "shared"
end

local function ParseBorderThicknessShortcut(text)
    if not ContainsAny(text, { "border", "outline" }) then return nil end
    if ContainsAny(text, { "portrait", "castbar", "cast bar", "class power", "class resource" }) then return nil end
    if ContainsAny(text, { "color", "colour", "farbe", "reset" }) then return nil end
    if ContainsAny(text, { "aggro", "threat", "dispel", "dispellable", "purge", "purgeable", "boss target", "highlight" }) then return nil end

    local explicitDetail = ContainsAny(text, {
        "frame outline", "frame border", "bar outline", "bar border", "border outline", "outline border",
        "outline thickness", "border thickness", "outline size", "border size", "outline width", "border width",
        "outline thicker", "outline thinner", "border thicker", "border thinner",
        "thicker", "thinner", "bigger", "larger", "smaller", "dicker", "duenner",
    })
    local toggleIntent = DetectBoolean(text) ~= nil
    local numberIntent = FirstNumber(text) ~= nil
    if not (explicitDetail or toggleIntent or numberIntent) then return nil end

    local setting = OutlineScopeSettingForText(text)
    if not setting then return nil end

    local value
    local relativeDelta
    local bool = DetectBoolean(text)
    if bool ~= nil and not numberIntent and not ContainsAny(text, { "thicker", "thinner", "bigger", "larger", "smaller", "increase", "decrease", "dicker", "duenner" }) then
        value = bool and 1 or 0
    else
        relativeDelta = RelativeNumberDeltaForText({ step = 1 }, text, 1)
        if relativeDelta == nil then value = FirstNumber(text) end
    end
    if value == nil and relativeDelta == nil then return nil end

    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = setting.label or "Frame outline thickness",
        summary = "Changes the registered frame/bar outline thickness control instead of toggling the whole unit frame.",
    }
end

local function ParseUnitDetailOffsetShortcut(text)
    if ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) then return nil end
    if not ContainsAny(text, { "offset" }) then return nil end
    if DetectDirection(text, {}) then return nil end
    local value = FirstNumber(text)
    if value == nil then return nil end
    local spec
    for i = 1, #DETAIL_MOVE_SPECS do
        if ContainsAny(text, DETAIL_MOVE_SPECS[i].terms) then
            spec = DETAIL_MOVE_SPECS[i]
            break
        end
    end
    if not spec then return nil end
    local units = DetectUnits(text)
    if #units == 0 then
        local pageUnit = CurrentPageUnit()
        if pageUnit then
            units = { pageUnit }
        else
            units = ALL_UNITFRAMES
        end
    end
    local changes = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        local sx = Registry and Registry:GetSetting(unit .. "." .. spec.x)
        local sy = Registry and Registry:GetSetting(unit .. "." .. spec.y)
        if sx then changes[#changes + 1] = { setting = sx, value = value, direction = "x" } end
        if sy then changes[#changes + 1] = { setting = sy, value = value, direction = "y" } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "ambiguous",
        choices = changes,
        label = "Which " .. tostring(spec.label or "detail") .. " offset should I set?",
        summary = "The command names an offset but not X/Y or a movement direction.",
    }
end

local CASTBAR_DETAIL_PREFIXES = {
    player = "castbarPlayer",
    target = "castbarTarget",
    focus = "castbarFocus",
    boss = "bossCast",
}

local function CastbarDetailUnitsOrCurrentPage(text)
    local units = DetectUnits(text)
    local filtered = {}
    for i = 1, #units do
        local unit = units[i]
        if CASTBAR_DETAIL_PREFIXES[unit] then filtered[#filtered + 1] = unit end
    end
    if #filtered > 0 then return filtered end
    local pageUnit = CurrentPageUnit()
    if pageUnit and CASTBAR_DETAIL_PREFIXES[pageUnit] then return { pageUnit } end
    return { "player", "target", "focus", "boss" }
end

local function ParseCastbarTextMoveShortcut(text)
    if not ContainsAny(text, { "castbar", "cast bar", "zauberleiste" }) then return nil end
    if not ContainsAny(text, { "move", "nudge", "shift", "verschiebe", "offset" }) then return nil end
    local direction = DetectDirection(text, {})
    if not direction then return nil end
    local field
    local label
    if ContainsAny(text, { "time text", "castbar time", "cast time", "timer", "time" }) then
        field = (direction == "left" or direction == "right") and "TimeOffsetX" or "TimeOffsetY"
        label = "Move castbar time text"
    elseif ContainsAny(text, { "spell name", "spell text", "castbar text", "castbar name", "text" }) then
        field = (direction == "left" or direction == "right") and "TextOffsetX" or "TextOffsetY"
        label = "Move castbar spell text"
    else
        return nil
    end
    local amount = FirstNumber(text) or 5
    if direction == "left" or direction == "down" then amount = -amount end
    local units = CastbarDetailUnitsOrCurrentPage(text)
    local changes = {}
    for i = 1, #units do
        local prefix = CASTBAR_DETAIL_PREFIXES[units[i]]
        local setting = prefix and Registry and Registry:GetSetting("general." .. prefix .. field)
        if setting then changes[#changes + 1] = { setting = setting, relativeDelta = amount, direction = direction } end
    end
    if #changes == 0 then return nil end
    if #changes > 1 and #DetectUnits(text) == 0 and not CurrentPageUnit() then
        return { kind = "ambiguous", choices = changes, label = "Which castbar text should I move?" }
    end
    return {
        kind = "changes",
        changes = changes,
        label = label,
        summary = "Moves a registered castbar text detail control by pixels.",
    }
end

local function ParseUnitOpacityShortcut(text)
    if not ContainsAny(text, { "alpha", "opacity", "transparency", "transparent", "opaque" }) then return nil end
    if ContainsAny(text, { "class power", "class resource", "class resources", "resource bar", "alt mana", "alternative mana", "secondary mana", "dual resource mana" }) then return nil end
    if DetectGroups(text)[1] then return nil end
    if ContainsAny(text, { "range fade", "in combat", "out of combat", "outside combat", "sync", "affects", "fade target", "preserve hp", "dispel overlay", "debuff overlay", "unitframe dispel overlay", "unit frame dispel overlay" }) then return nil end
    local relativeDelta
    if ContainsAny(text, { "more transparent", "more transparency", "more see through", "transparenter" }) then
        local amount = FirstNumber(text) or 0.05
        if amount > 1 then amount = amount / 100 end
        relativeDelta = -amount
    elseif ContainsAny(text, { "less transparent", "less transparency", "more opaque", "opaquer" }) then
        local amount = FirstNumber(text) or 0.05
        if amount > 1 then amount = amount / 100 end
        relativeDelta = amount
    else
        relativeDelta = RelativeNumberDeltaForText({ percent = true, step = 0.05 }, text)
    end
    local value
    if relativeDelta == nil then
        value = FirstNumber(text)
        if value == nil then return nil end
        if value > 1 then value = value / 100 end
    end
    local units = DetectUnits(text)
    if #units == 0 then
        local pageUnit = CurrentPageUnit()
        if pageUnit then
            units = { pageUnit }
        else
            return {
                kind = "unknown",
                text = "Which unitframe alpha should I change? Try 'set player alpha to 50' or open a unit page and say 'set alpha to 50'.",
                status = "failed",
            }
        end
    end
    local changes = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        local inCombat = Registry and Registry:GetSetting(unit .. ".alphaInCombat")
        local outCombat = Registry and Registry:GetSetting(unit .. ".alphaOutOfCombat")
        if inCombat then changes[#changes + 1] = { setting = inCombat, value = value, relativeDelta = relativeDelta } end
        if outCombat then changes[#changes + 1] = { setting = outCombat, value = value, relativeDelta = relativeDelta } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Set unit opacity",
        summary = "Sets both in-combat and out-of-combat opacity for the requested unitframe.",
    }
end

function A._ParseGroupOpacityShortcut(text)
    if not ContainsAny(text, { "alpha", "opacity", "transparency", "transparent", "opaque" }) then return nil end
    if ContainsAny(text, { "range fade", "in combat", "out of combat", "outside combat", "sync", "affects", "fade target", "preserve hp", "background", "backdrop", "hp fill", "health fill", "hp track", "health track", "text ignores", "dispel overlay", "debuff overlay" }) then return nil end

    local groups = DetectGroups(text)
    if #groups == 0 then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        end
    end
    if #groups == 0 then return nil end

    local relativeDelta
    if ContainsAny(text, { "more transparent", "more transparency", "more see through", "transparenter" }) then
        local amount = FirstNumber(text) or 0.05
        if amount > 1 then amount = amount / 100 end
        relativeDelta = -amount
    elseif ContainsAny(text, { "less transparent", "less transparency", "more opaque", "opaquer" }) then
        local amount = FirstNumber(text) or 0.05
        if amount > 1 then amount = amount / 100 end
        relativeDelta = amount
    else
        relativeDelta = RelativeNumberDeltaForText({ percent = true, step = 0.05 }, text)
    end
    local value
    if relativeDelta == nil then
        value = FirstNumber(text)
        if value == nil then return nil end
        if value > 1 then value = value / 100 end
    end

    local changes = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        local inCombat = Registry and Registry:GetSetting("gf_" .. scope .. ".alphaCurrentInCombat")
        local outCombat = Registry and Registry:GetSetting("gf_" .. scope .. ".alphaCurrentOutOfCombat")
        if inCombat then changes[#changes + 1] = { setting = inCombat, value = value, relativeDelta = relativeDelta } end
        if outCombat then changes[#changes + 1] = { setting = outCombat, value = value, relativeDelta = relativeDelta } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Set group opacity",
        summary = "Sets both in-combat and out-of-combat opacity for the requested group-frame scope.",
    }
end

local function GroupColorModeScopes(text)
    local scopes = {}
    local explicitGroupGeneric = ContainsAny(text, { "group frames", "group frame", "gruppenframes", "groups" })
    local explicitNamed = false
    if ContainsAny(text, { "party", "party frame", "party frames", "partyframe" }) then AddUnique(scopes, "party"); explicitNamed = true end
    if ContainsAny(text, { "mythic raid", "mythicraid", "mythic raid frame", "mythic raid frames", "mythicraidframe" }) then AddUnique(scopes, "mythicraid"); explicitNamed = true end
    if ContainsAny(text, { "raid", "raid frame", "raid frames", "raidframe" }) and not ContainsAny(text, { "mythic raid", "mythicraid", "mythicraidframe" }) then
        AddUnique(scopes, "raid")
        explicitNamed = true
    end
    if not explicitNamed and explicitGroupGeneric then
        return { "party", "raid", "mythicraid" }
    end
    if #scopes == 0 then
        local detected = DetectGroups(text)
        for i = 1, #detected do AddUnique(scopes, detected[i]) end
    end
    return scopes
end

local function GroupBarColorModeForText(text)
    local bool = DetectBoolean(text)
    if ContainsAny(text, { "class color", "class colors", "class colored", "class mode" }) then
        return bool == false and "GLOBAL" or "CLASS"
    end
    if ContainsAny(text, { "gradient", "health gradient" }) then return bool == false and "GLOBAL" or "GRADIENT" end
    if ContainsAny(text, { "custom", "manual" }) then return bool == false and "GLOBAL" or "CUSTOM" end
    if ContainsAny(text, { "dark mode", "dark bars", "dark" }) then return bool == false and "GLOBAL" or "dark" end
    if ContainsAny(text, { "unified", "unified color", "unified bars" }) then return bool == false and "GLOBAL" or "unified" end
    if ContainsAny(text, { "global", "global style", "inherit", "default" }) then return "GLOBAL" end
    return nil
end

local function ParseGroupFrameColorMode(text)
    if not ContainsAny(text, {
        "group frames", "group frame", "gruppenframes", "party", "party frame", "party frames", "partyframe",
        "raid", "raid frame", "raid frames", "raidframe", "mythic raid", "mythicraid",
    }) then
        return nil
    end
    if not ContainsAny(text, {
        "bar color mode", "health bar color mode", "class color mode", "health color mode",
        "group bar style", "bar mode", "class colored health", "class color health",
    }) then
        return nil
    end
    local value = GroupBarColorModeForText(text)
    if not value then return nil end
    local scopes = GroupColorModeScopes(text)
    if #scopes == 0 then return nil end

    local changes = {}
    for i = 1, #scopes do
        local scope = scopes[i]
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(scope) .. ".gfBarMode")
        if setting then changes[#changes + 1] = { setting = setting, value = value } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Set group-frame bar color mode",
        summary = "Changes the real Group Frames > Health & Text Bar Color Mode instead of the global unitframe bar mode.",
    }
end

local MENU_SELECTOR_VERBS = {
    "select", "choose", "pick", "open", "show", "switch to", "go to", "focus", "edit",
}

local function HasMenuSelectorVerb(text)
    return ContainsAny(text, MENU_SELECTOR_VERBS)
end

local function MenuSelectorAction(args, label, summary)
    local action = Registry and Registry:GetAction("set_menu_selector_state")
    return action and {
        kind = "action",
        action = action,
        args = args,
        label = label or "Set menu selector state",
        summary = summary or "Selects a visible Menu2 tab, dropdown entry, or editor slot without changing the underlying setting value.",
    } or nil
end

local function SelectorUnit(text)
    local units = DetectUnits(text)
    return units[1] or CurrentPageUnit()
end

local function SelectorGroupScope(text)
    local groups = DetectGroups(text)
    if groups[1] then return groups[1] end
    if M and (M.gfScope == "party" or M.gfScope == "raid" or M.gfScope == "mythicraid") then return M.gfScope end
    return "party"
end

local function TextSelectorTab(text)
    if ContainsAny(text, { "advanced text tab", "advanced text", "text advanced", "text layers", "advanced tab" }) then return "advanced" end
    if ContainsAny(text, { "power text tab", "power text", "mana text", "power tab", "mana tab", "power", "mana" }) then return "power" end
    if ContainsAny(text, { "hp text tab", "health text tab", "hp text", "health text", "hp tab", "health tab", "hp", "health" }) then return "hp" end
    if ContainsAny(text, { "name text tab", "name text", "name tab", "name" }) then return "name" end
    return nil
end

local function TextSelectorSlot(text)
    if ContainsAny(text, { "left slot", "slot left", "left text slot", "left anchor", "anchor left", "anchor to left", "to left", "on left", "on the left", "left side" })
        or (HasPhrase(text, "left") and ContainsAny(text, { "slot", "text slot", "anchor", "anchoring", "align", "alignment" }))
    then
        return "left"
    end
    if ContainsAny(text, { "center slot", "centre slot", "middle slot", "slot center", "slot centre", "slot middle", "center text slot", "centre text slot", "middle text slot" })
        or ContainsAny(text, { "center anchor", "centre anchor", "middle anchor", "anchor center", "anchor centre", "anchor middle", "anchor to center", "anchor to centre", "anchor to middle", "to center", "to centre", "to middle", "on center", "on centre", "on middle", "on the center", "on the centre", "on the middle", "center side", "centre side", "middle" })
        or ((HasPhrase(text, "center") or HasPhrase(text, "centre") or HasPhrase(text, "middle")) and ContainsAny(text, { "slot", "text slot", "anchor", "anchoring", "align", "alignment" }))
    then
        return "center"
    end
    if ContainsAny(text, { "right slot", "slot right", "right text slot", "right anchor", "anchor right", "anchor to right", "to right", "on right", "on the right", "right side" })
        or (HasPhrase(text, "right") and ContainsAny(text, { "slot", "text slot", "anchor", "anchoring", "align", "alignment" }))
    then
        return "right"
    end
    return nil
end

local function TextSelectorIntent(text, tab, slot)
    if tab == "name" and ContainsAny(text, { "anchor", "anchoring", "align", "alignment" }) then return false end
    if (tab == "hp" or tab == "power") and slot and ContainsAny(text, { "anchor", "anchoring", "align", "alignment" }) then return true end
    if ContainsAny(text, {
        "text area", "text tab", "text tabs", "text editor", "text slot", "slot selector", "slot dropdown",
        "selected slot", "left slot", "center slot", "centre slot", "right slot",
    }) then
        return true
    end
    return tab and ContainsAny(text, { "name text", "hp text", "health text", "power text", "mana text" }) and (HasPhrase(text, "tab") or slot ~= nil)
end

function A._ParseTextFontSizeShortcut(text)
    if ContainsAny(text, { "castbar", "cast bar", "aura", "auras", "buff", "debuff" }) then return nil end
    if not ContainsAny(text, {
        "font size", "text size", "name size", "name font size", "hp font size", "health font size",
        "power font size", "mana font size", "schriftgroesse", "schrift groesse",
    }) then
        return nil
    end
    local tab = TextSelectorTab(text)
    if tab ~= "name" and tab ~= "hp" and tab ~= "power" then return nil end
    local attr = tab == "name" and "nameFontSize" or (tab == "hp" and "hpFontSize" or "powerFontSize")
    local relativeDelta = RelativeNumberDeltaForText({ step = 1 }, text, 1)
    local value
    if relativeDelta == nil then value = FirstNumber(text) end
    if value == nil and relativeDelta == nil then return nil end

    local groups = DetectGroups(text)
    local units = {}
    if #groups == 0 then units = DetectUnits(text) end

    if #groups == 0 and #units == 0 then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units = { pageUnit } end
        end
    end

    local changes = {}
    for i = 1, #groups do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta } end
    end
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta } end
    end
    if #changes == 0 then return nil end
    if #changes > 1 and #groups > 1 then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching group text font-size settings",
        }
    end
    return {
        kind = "changes",
        changes = changes,
        label = "Set text font size",
        summary = "Changes the registered Name/HP/Power text font-size slider for the selected unit or group scope.",
    }
end

function A._ParseTextLayerShortcut(text)
    if ContainsAny(text, { "castbar", "cast bar", "aura", "auras", "buff", "debuff" }) then return nil end
    if ContainsAny(text, { "class power", "class resource", "class resources", "resource bar" }) then return nil end
    if not ContainsAny(text, { "text layer", "draw layer", "text level", "draw level", "layer" }) then return nil end
    local tab = TextSelectorTab(text)
    if tab ~= "name" and tab ~= "hp" and tab ~= "power" then return nil end

    local relativeDelta = RelativeNumberDeltaForText({ step = 1 }, text, 1)
    if relativeDelta == nil then
        if ContainsAny(text, { "bring forward", "move forward", "raise forward", "forward", "front", "above", "up" }) then
            relativeDelta = 1
        elseif ContainsAny(text, { "send back", "move back", "backward", "behind", "below" }) then
            relativeDelta = -1
        end
    end
    local value
    if relativeDelta == nil then value = FirstNumber(text) end
    if value == nil and relativeDelta == nil then return nil end

    local unitAttr = tab == "name" and "nameTextLayer" or (tab == "hp" and "hpTextLayer" or "powerTextLayer")
    local groupAttr = tab == "name" and "nameTextLayer" or (tab == "hp" and "textLayer" or "powerTextLayer")
    local groups = DetectGroups(text)
    local units = {}
    if #groups == 0 then units = DetectUnits(text) end

    if #groups == 0 and #units == 0 then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units = { pageUnit } end
        end
    end

    local changes = {}
    for i = 1, #groups do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. "." .. groupAttr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta } end
    end
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. unitAttr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta } end
    end
    if #changes == 0 then return nil end
    if #changes > 1 and #groups > 1 then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching group text-layer settings",
        }
    end
    return {
        kind = "changes",
        changes = changes,
        label = "Set text layer",
        summary = "Changes the registered Name/HP/Power text-layer slider for the selected unit or group scope.",
    }
end

function A._TextSlotForDetail(text, tab)
    if tab ~= "hp" and tab ~= "power" then return nil end
    if tab == "hp" then
        if ContainsAny(text, { "left hp text", "hp left text", "hp text left", "left health text", "health left text", "health text left", "left hp slot", "hp left slot", "hp slot left", "left health slot", "health left slot", "health slot left", "left hp label", "hp left label", "hp label left", "left health label", "health left label", "health label left" }) then return "Left" end
        if ContainsAny(text, { "center hp text", "centre hp text", "middle hp text", "hp center text", "hp centre text", "hp middle text", "hp text center", "hp text centre", "hp text middle", "center health text", "centre health text", "middle health text", "health center text", "health centre text", "health middle text", "health text center", "health text centre", "health text middle", "center hp slot", "centre hp slot", "middle hp slot", "hp center slot", "hp centre slot", "hp middle slot", "hp slot center", "hp slot centre", "hp slot middle", "center health slot", "centre health slot", "middle health slot", "health center slot", "health centre slot", "health middle slot", "health slot center", "health slot centre", "health slot middle", "center hp label", "centre hp label", "middle hp label", "hp center label", "hp centre label", "hp middle label", "hp label center", "hp label centre", "hp label middle", "center health label", "centre health label", "middle health label", "health center label", "health centre label", "health middle label", "health label center", "health label centre", "health label middle" }) then return "Center" end
        if ContainsAny(text, { "right hp text", "hp right text", "hp text right", "right health text", "health right text", "health text right", "right hp slot", "hp right slot", "hp slot right", "right health slot", "health right slot", "health slot right", "right hp label", "hp right label", "hp label right", "right health label", "health right label", "health label right" }) then return "Right" end
    else
        if ContainsAny(text, { "left power text", "power left text", "power text left", "left mana text", "mana left text", "mana text left", "left power slot", "power left slot", "power slot left", "left mana slot", "mana left slot", "mana slot left", "left power label", "power left label", "power label left", "left mana label", "mana left label", "mana label left" }) then return "Left" end
        if ContainsAny(text, { "center power text", "centre power text", "middle power text", "power center text", "power centre text", "power middle text", "power text center", "power text centre", "power text middle", "center mana text", "centre mana text", "middle mana text", "mana center text", "mana centre text", "mana middle text", "mana text center", "mana text centre", "mana text middle", "center power slot", "centre power slot", "middle power slot", "power center slot", "power centre slot", "power middle slot", "power slot center", "power slot centre", "power slot middle", "center mana slot", "centre mana slot", "middle mana slot", "mana center slot", "mana centre slot", "mana middle slot", "mana slot center", "mana slot centre", "mana slot middle", "center power label", "centre power label", "middle power label", "power center label", "power centre label", "power middle label", "power label center", "power label centre", "power label middle", "center mana label", "centre mana label", "middle mana label", "mana center label", "mana centre label", "mana middle label", "mana label center", "mana label centre", "mana label middle" }) then return "Center" end
        if ContainsAny(text, { "right power text", "power right text", "power text right", "right mana text", "mana right text", "mana text right", "right power slot", "power right slot", "power slot right", "right mana slot", "mana right slot", "mana slot right", "right power label", "power right label", "power label right", "right mana label", "mana right label", "mana label right" }) then return "Right" end
    end
    local slot = TextSelectorSlot(text)
    if (slot == "left" or slot == "center" or slot == "right")
        and ContainsAny(text, { "slot", "text slot", "anchor", "anchoring", "side", "left side", "right side", "center side", "centre side", "middle side" })
    then
        return slot == "left" and "Left" or (slot == "right" and "Right" or "Center")
    end
    return nil
end

function A._TextSlotName(slot)
    slot = tostring(slot or ""):lower()
    if slot == "left" then return "Left" end
    if slot == "center" or slot == "centre" or slot == "middle" then return "Center" end
    if slot == "right" then return "Right" end
    return nil
end

function A._TextSlotLower(slot)
    slot = A._TextSlotName(slot)
    if slot == "Left" then return "left" end
    if slot == "Center" then return "center" end
    if slot == "Right" then return "right" end
    return nil
end

function A._TextSlotSettingKey(tab, slot)
    slot = A._TextSlotName(slot)
    if not slot then return nil end
    if tab == "hp" then
        return slot == "Left" and "textLeft" or (slot == "Center" and "textCenter" or "textRight")
    elseif tab == "power" then
        return "powerText" .. slot
    end
    return nil
end

local function ReadSettingValue(setting)
    if setting and type(setting.get) == "function" then
        local ok, value = pcall(setting.get)
        if ok then return value end
    end
    return nil
end

local function TextSlotSetting(frameType, unitOrScope, tab, slotName)
    local keyName = A._TextSlotSettingKey(tab, slotName)
    if not keyName or not Registry then return nil end
    local prefix = frameType == "group" and ("gf_" .. tostring(unitOrScope)) or tostring(unitOrScope)
    return Registry:GetSetting(prefix .. "." .. keyName)
end

local function ActiveTextSlotsForTarget(frameType, unitOrScope, tab)
    local active = {}
    for _, slotName in ipairs({ "Left", "Center", "Right" }) do
        local setting = TextSlotSetting(frameType, unitOrScope, tab, slotName)
        local value = ReadSettingValue(setting)
        if setting and value ~= nil and value ~= "NONE" then
            active[#active + 1] = slotName
        end
    end
    return active
end

local function InferSingleActiveTextSlot(frameType, unitOrScope, tab)
    local active = ActiveTextSlotsForTarget(frameType, unitOrScope, tab)
    return #active == 1 and active[1] or nil, active
end

function A._TextGroupScopeName(scope)
    scope = tostring(scope or "")
    if scope == "gf_party" then return "party" end
    if scope == "gf_raid" then return "raid" end
    if scope == "gf_mythicraid" then return "mythicraid" end
    return scope
end

function A._SelectedTextSlotFromContext(frameType, unitOrScope, tab)
    if tab ~= "hp" and tab ~= "power" then return nil end
    if frameType == "group" then unitOrScope = A._TextGroupScopeName(unitOrScope) end
    local ctx = A.GetContext and A.GetContext() or nil
    local selected = ctx and ctx.selectedTextEditorTarget
    if type(selected) == "table"
        and selected.tab == tab
        and selected.frameType == frameType
        and tostring(frameType == "group" and A._TextGroupScopeName(selected.unit) or selected.unit or "") == tostring(unitOrScope or "")
    then
        return A._TextSlotName(selected.slot)
    end
    if ctx and ctx.lastTextArea == tab
        and ctx.lastTextFrameType == frameType
        and tostring(frameType == "group" and A._TextGroupScopeName(ctx.lastTextUnit) or ctx.lastTextUnit or "") == tostring(unitOrScope or "")
    then
        return A._TextSlotName(ctx.lastTextSlot)
    end
    if frameType == "group" then
        local byScope = M and M.gfTextSlotSelection and M.gfTextSlotSelection[unitOrScope]
        return A._TextSlotName(byScope and byScope[tab])
    end
    local byUnit = M and M.unitTextSlotSelection and M.unitTextSlotSelection[unitOrScope]
    return A._TextSlotName(byUnit and byUnit[tab])
end

function A._SelectedTextTargetFromContext(tab)
    local ctx = A.GetContext and A.GetContext() or nil
    local selected = ctx and ctx.selectedTextEditorTarget
    if type(selected) == "table" and (not tab or selected.tab == tab) then
        return selected.frameType, selected.frameType == "group" and A._TextGroupScopeName(selected.unit) or selected.unit, selected.tab, A._TextSlotName(selected.slot)
    end
    if ctx and ctx.lastTextArea and (not tab or ctx.lastTextArea == tab) then
        return ctx.lastTextFrameType, ctx.lastTextFrameType == "group" and A._TextGroupScopeName(ctx.lastTextUnit) or ctx.lastTextUnit, ctx.lastTextArea, A._TextSlotName(ctx.lastTextSlot)
    end
    return nil
end

function A._EnumAllowsValue(setting, value)
    local values = setting and setting.values
    if type(values) ~= "table" then return false end
    for i = 1, #values do
        if values[i] == value then return true end
    end
    return false
end

function A._TextSlotDropdownValueForText(setting, text)
    local aliases = {
        { "current max percent", "CURMAXPERCENT" },
        { "current maximum percent", "CURMAXPERCENT" },
        { "current max percentage", "CURMAXPERCENT" },
        { "current maximum percentage", "CURMAXPERCENT" },
        { "percent current max", "PERCENTCURMAX" },
        { "percent current maximum", "PERCENTCURMAX" },
        { "percent max current", "PERCENTCURMAX" },
        { "percent maximum current", "PERCENTCURMAX" },
        { "current and max", "CURMAX" },
        { "current and maximum", "CURMAX" },
        { "current/max", "CURMAX" },
        { "current / max", "CURMAX" },
        { "current max", "CURMAX" },
        { "current maximum", "CURMAX" },
        { "current and percent", "CURPERCENT" },
        { "current and percentage", "CURPERCENT" },
        { "current/percent", "CURPERCENT" },
        { "current / percent", "CURPERCENT" },
        { "current percent", "CURPERCENT" },
        { "current percentage", "CURPERCENT" },
        { "max percent", "MAXPERCENT" },
        { "maximum percent", "MAXPERCENT" },
        { "max percentage", "MAXPERCENT" },
        { "maximum percentage", "MAXPERCENT" },
        { "percent current", "PERCENTCUR" },
        { "percentage current", "PERCENTCUR" },
        { "percent max", "PERCENTMAX" },
        { "percentage max", "PERCENTMAX" },
        { "percent maximum", "PERCENTMAX" },
        { "percentage maximum", "PERCENTMAX" },
        { "current health", "CURRENT" },
        { "current hp", "CURRENT" },
        { "hp current", "CURRENT" },
        { "health current", "CURRENT" },
        { "current power", "CURRENT" },
        { "current mana", "CURRENT" },
        { "power current", "CURRENT" },
        { "mana current", "CURRENT" },
        { "current", "CURRENT" },
        { "actual", "CURRENT" },
        { "max health", "MAX" },
        { "maximum health", "MAX" },
        { "health max", "MAX" },
        { "health maximum", "MAX" },
        { "max hp", "MAX" },
        { "maximum hp", "MAX" },
        { "hp max", "MAX" },
        { "hp maximum", "MAX" },
        { "max power", "MAX" },
        { "maximum power", "MAX" },
        { "power max", "MAX" },
        { "power maximum", "MAX" },
        { "max mana", "MAX" },
        { "maximum mana", "MAX" },
        { "mana max", "MAX" },
        { "mana maximum", "MAX" },
        { "maximum", "MAX" },
        { "max", "MAX" },
        { "missing health", "DEFICIT" },
        { "missing hp", "DEFICIT" },
        { "health deficit", "DEFICIT" },
        { "hp deficit", "DEFICIT" },
        { "deficit", "DEFICIT" },
        { "missing", "DEFICIT" },
        { "only %", "PERCENT" },
        { "% only", "PERCENT" },
        { "%", "PERCENT" },
        { "only percent", "PERCENT" },
        { "only percentage", "PERCENT" },
        { "just percent", "PERCENT" },
        { "just percentage", "PERCENT" },
        { "percent only", "PERCENT" },
        { "percentage only", "PERCENT" },
        { "percentage", "PERCENT" },
        { "percent", "PERCENT" },
        { "pct", "PERCENT" },
        { "clear", "NONE" },
        { "remove", "NONE" },
        { "removed", "NONE" },
        { "nothing", "NONE" },
        { "empty", "NONE" },
        { "none", "NONE" },
        { "hidden", "NONE" },
        { "hide", "NONE" },
        { "off", "NONE" },
    }
    for i = 1, #aliases do
        local alias, value = aliases[i][1], aliases[i][2]
        if HasPhrase(text, alias) then
            if A._EnumAllowsValue(setting, value) then return value end
            return nil, value
        end
    end
    local value = EnumValueForText(setting, text)
    if value ~= nil and A._EnumAllowsValue(setting, value) then return value end
    return nil
end

function A._ParseTextSlotDropdownShortcut(text)
    if ContainsAny(text, { "castbar", "cast bar", "aura", "auras", "buff", "debuff", "class power", "class resource", "class resources" }) then return nil end
    if ContainsAny(text, { "power bar", "powerbar", "mana bar", "mana balken", "power balken" }) then return nil end
    if ContainsAny(text, { "dispel overlay", "debuff overlay", "current health only", "on current health only", "on health only" }) then return nil end
    if ContainsAny(text, { "dark mode", "dark bars", "dark bar", "bar color", "brightness" }) then return nil end
    if not ContainsAny(text, { "set", "show", "display", "use", "put", "make", "change", "hide", "turn off", "turn on", "create", "create new", "add", "new", "remove", "clear" }) then return nil end
    local tab = TextSelectorTab(text)
    local ctxFrame, ctxUnit, ctxTab, ctxSlot = A._SelectedTextTargetFromContext(tab)
    local contextReference = ContainsAny(text, { "it", "that", "this", "selected", "here", "there", "same", "now" })
    if not tab and contextReference then tab = ctxTab end
    if tab ~= "hp" and tab ~= "power" then return nil end
    local slot = A._TextSlotForDetail(text, tab)
    if ContainsAny(text, { "offset", "position", "pos", "x", "y", "up", "down", "move", "nudge", "shift", "layer", "size", "font size" }) then return nil end

    local groups = DetectGroups(text)
    local units = {}
    if #groups == 0 then units = DetectUnits(text) end
    if #groups == 0 and #units == 0 and contextReference and ctxFrame and ctxUnit and ctxTab == tab then
        if ctxFrame == "group" then
            groups = { tostring(ctxUnit) }
        else
            units = { tostring(ctxUnit) }
        end
    end
    if #groups == 0 and #units == 0 then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units = { pageUnit } end
        end
    end
    if #groups == 0 and #units == 0 and ctxFrame and ctxUnit and ctxTab == tab then
        if ctxFrame == "group" then
            groups = { tostring(ctxUnit) }
        else
            units = { tostring(ctxUnit) }
        end
    end

    local clearAllSlots = slot == nil
        and ContainsAny(text, { "remove", "clear", "hide", "turn off", "disable", "empty", "none", "off" })
        and not ContainsAny(text, { "it", "that", "this", "selected", "here" })
    local ambiguousActiveSlots

    if not slot and contextReference then
        if #groups == 1 then
            slot = A._SelectedTextSlotFromContext("group", groups[1], tab)
        elseif #units == 1 then
            slot = A._SelectedTextSlotFromContext("unitframe", units[1], tab)
        end
        if not slot and ctxSlot and ctxTab == tab then slot = ctxSlot end
    end
    if not slot and not clearAllSlots then
        if #groups == 1 then
            slot = A._SelectedTextSlotFromContext("group", groups[1], tab)
        elseif #units == 1 then
            slot = A._SelectedTextSlotFromContext("unitframe", units[1], tab)
        end
    end
    if not slot and not clearAllSlots then
        local active
        if #groups == 1 then
            slot, active = InferSingleActiveTextSlot("group", groups[1], tab)
        elseif #units == 1 then
            slot, active = InferSingleActiveTextSlot("unitframe", units[1], tab)
        end
        if not slot and type(active) == "table" and #active > 1 then
            ambiguousActiveSlots = active
        end
    end
    if not slot and ctxSlot and ctxTab == tab and contextReference then slot = ctxSlot end

    local slots = {}
    if slot then
        slots[1] = slot
    elseif ambiguousActiveSlots and #ambiguousActiveSlots > 0 then
        slots = ambiguousActiveSlots
    else
        slots[1], slots[2], slots[3] = "Left", "Center", "Right"
    end

    local function AddTextSlotChange(out, setting, slotName)
        if not setting then return nil end
        local value, invalid = A._TextSlotDropdownValueForText(setting, text)
        if value ~= nil then
            out[#out + 1] = {
                setting = setting,
                value = value,
                textArea = tab,
                textSlot = A._TextSlotLower(slotName),
                label = tostring(setting.label or "Text slot") .. " -> " .. tostring(value),
                valueLabel = value,
            }
        end
        return invalid
    end

    local changes = {}
    local invalidValue
    for i = 1, #groups do
        for j = 1, #slots do
            local keyName = A._TextSlotSettingKey(tab, slots[j])
            local setting = keyName and Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. "." .. keyName)
            invalidValue = AddTextSlotChange(changes, setting, slots[j]) or invalidValue
        end
    end
    for i = 1, #units do
        for j = 1, #slots do
            local keyName = A._TextSlotSettingKey(tab, slots[j])
            local setting = keyName and Registry and Registry:GetSetting(tostring(units[i]) .. "." .. keyName)
            invalidValue = AddTextSlotChange(changes, setting, slots[j]) or invalidValue
        end
    end
    if #changes == 0 and invalidValue then
        return {
            kind = "unknown",
            text = "That text-slot value is not available for the selected MSUF dropdown.",
            status = "failed",
        }
    end
    if #changes == 0 then return nil end
    if #changes > 1 and not clearAllSlots then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching text-slot dropdown settings",
            summary = "The command did not identify one concrete text slot, so the Assistant is asking which real slot to change.",
        }
    end
    return {
        kind = "changes",
        changes = changes,
        label = "Set text slot content",
        summary = "Changes the registered HP/Power left/center/right text-slot dropdown for the selected unit or group scope.",
    }
end

function A._ParseTextSlotOffsetShortcut(text)
    if ContainsAny(text, { "castbar", "cast bar", "aura", "auras", "buff", "debuff", "class power", "class resource", "class resources" }) then return nil end
    if not ContainsAny(text, { "move", "nudge", "shift", "offset", "position", "pos", "x", "y", "up", "down" }) then return nil end
    local tab = TextSelectorTab(text)
    if tab ~= "hp" and tab ~= "power" then return nil end
    local slot = A._TextSlotForDetail(text, tab)
    if not slot then return nil end

    local axis = A._DetailOffsetAxis(text)
    local direction
    if ContainsAny(text, { "down", "lower", "tiefer", "runter", "unten" }) then
        direction = "down"
    elseif ContainsAny(text, { "up", "higher", "hoeher", "hoch", "oben" }) then
        direction = "up"
    else
        direction = DetectDirection(text, {})
    end
    if (direction == "left" or direction == "right") and (slot == "Left" or slot == "Right")
        and not ContainsAny(text, {
            "left hp text", "hp left text", "left health text", "health left text", "left power text", "power left text", "left mana text", "mana left text",
            "right hp text", "hp right text", "right health text", "health right text", "right power text", "power right text", "right mana text", "mana right text",
            "left slot", "slot left", "right slot", "slot right", "left side", "right side", "left label", "right label",
        })
    then
        return nil
    end
    if not axis and direction then
        axis = (direction == "left" or direction == "right") and "x" or "y"
    end
    if not axis then return nil end

    local value
    local relativeDelta
    if ContainsAny(text, { "move", "nudge", "shift" }) and direction then
        relativeDelta = FirstNumber(text) or 10
        if direction == "left" or direction == "down" then relativeDelta = -relativeDelta end
    else
        value = FirstNumber(text)
    end
    if value == nil and relativeDelta == nil then return nil end

    local prefix = (tab == "hp" and "hpText" or "powerText") .. slot
    local attr = prefix .. (axis == "x" and "OffsetX" or "OffsetY")
    local groups = DetectGroups(text)
    local units = {}
    if #groups == 0 then units = DetectUnits(text) end

    if #groups == 0 and #units == 0 then
        local page = M and M.activeKey
        if page == "gf_layout" or page == "gf_bars" or page == "gf_indicators" then
            groups = GroupScopesOrCurrentPage(text)
        else
            local pageUnit = CurrentPageUnit()
            if pageUnit then units = { pageUnit } end
        end
    end

    local changes = {}
    for i = 1, #groups do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, direction = direction or axis } end
    end
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta, direction = direction or axis } end
    end
    if #changes == 0 then return nil end
    if #changes > 1 and #groups > 1 then
        return {
            kind = "ambiguous",
            choices = changes,
            label = "Multiple matching text-slot offset settings",
        }
    end
    return {
        kind = "changes",
        changes = changes,
        label = "Set text slot offset",
        summary = "Changes the registered HP/Power left/center/right text-slot offset slider for the selected unit or group scope.",
    }
end

local function TextMoveTogetherIntent(text)
    if ContainsAny(text, { "individual", "separate", "separately", "each" })
        and ContainsAny(text, { "hp text", "health text", "power text", "mana text" })
        and ContainsAny(text, { "unit", "units", "slot", "slots", "text unit", "text units", "text slot", "text slots" })
    then
        return true
    end
    return ContainsAny(text, {
        "move text as one group", "move as one group", "text as one group",
        "move text together", "text move together", "move together",
        "move text per slot", "text per slot", "per slot", "selected slot mode",
        "individual slot", "individual slots", "separate slot", "separate slots",
        "move text separately", "text separately", "individual text unit", "individual text units",
        "separate text unit", "separate text units", "move individual text", "move each text",
    })
end

local function TextMoveTogetherValue(text)
    if ContainsAny(text, { "individual", "separate", "separately", "each" })
        and ContainsAny(text, { "hp text", "health text", "power text", "mana text" })
        and ContainsAny(text, { "unit", "units", "slot", "slots", "text unit", "text units", "text slot", "text slots" })
    then
        return false
    end
    if ContainsAny(text, {
        "per slot", "selected slot mode", "individual slot", "individual slots",
        "separate slot", "separate slots", "separately", "text separately",
        "individual text unit", "individual text units", "separate text unit", "separate text units",
        "move individual text", "move each text",
    }) then
        return false
    end
    local value = DetectBoolean(text)
    if value ~= nil then return value end
    return true
end

local function StatusSelectorTab(text)
    if ContainsAny(text, { "advanced status tab", "advanced status icon tab", "advanced indicator tab", "advanced status controls", "advanced status" }) then return "advanced" end
    if ContainsAny(text, { "basic status tab", "basic status icon tab", "basic indicator tab", "basic status controls", "basic status" }) then return "basic" end
    return nil
end

local function StatusSelectorIntent(text)
    if ContainsAny(text, {
        "status tab", "status icon tab", "status indicator tab", "indicator tab",
        "status selector", "status dropdown", "indicator selector", "indicator dropdown",
        "status controls", "status icon controls", "selected indicator",
    }) then
        return true
    end
    return ContainsAny(text, { "indicator", "status icon" })
end

local function ParseMenuSelectorState(text)
    if TextMoveTogetherIntent(text) then
        local textTab = TextSelectorTab(text)
        if textTab == "hp" or textTab == "power" then
            local groups = DetectGroups(text)
            if groups[1] or ContainsAny(text, { "group text", "group health and text", "party text", "raid text", "mythic raid text" }) then
                return MenuSelectorAction({
                    selector = "group_text_move_together",
                    scope = groups[1] or SelectorGroupScope(text),
                    tab = textTab,
                    value = TextMoveTogetherValue(text),
                }, "Set group text move mode")
            end
            local unit = SelectorUnit(text)
            if unit then
                return MenuSelectorAction({
                    selector = "unit_text_move_together",
                    unit = unit,
                    tab = textTab,
                    value = TextMoveTogetherValue(text),
                }, "Set unit text move mode")
            end
        end
    end

    local anchorTextTab = TextSelectorTab(text)
    local anchorTextSlot = TextSelectorSlot(text)
    if (anchorTextTab == "hp" or anchorTextTab == "power") and TextSelectorIntent(text, anchorTextTab, anchorTextSlot) then
        local groups = DetectGroups(text)
        if groups[1] or ContainsAny(text, { "group text", "group health and text", "party text", "raid text", "mythic raid text" }) then
            return MenuSelectorAction({
                selector = "group_text",
                scope = groups[1] or SelectorGroupScope(text),
                tab = anchorTextTab,
                slot = anchorTextSlot,
            }, "Select group text editor state")
        end
        local unit = SelectorUnit(text)
        if unit then
            return MenuSelectorAction({
                selector = "unit_text",
                unit = unit,
                tab = anchorTextTab,
                slot = anchorTextSlot,
            }, "Select unit text editor state")
        end
    end

    if not HasMenuSelectorVerb(text) then return nil end

    if ContainsAny(text, { "class power color token", "class resource color token", "class power token", "class resource token" }) then
        local token = ClassPowerColorTokenForText(text)
        if token then
            return MenuSelectorAction({ selector = "color_token", kind = "classPower", token = token }, "Select class resource color token")
        end
    end
    if ContainsAny(text, { "power color token", "power token", "power type", "resource type", "resource color token" })
        and not ContainsAny(text, { "class power", "class resource", "combo point", "combo points" })
    then
        local token = PowerColorTokenForText(text)
        if token then
            return MenuSelectorAction({ selector = "color_token", kind = "power", token = token }, "Select power color token")
        end
    end

    local textTab = TextSelectorTab(text)
    local textSlot = TextSelectorSlot(text)
    if textTab and TextSelectorIntent(text, textTab, textSlot) then
        local groups = DetectGroups(text)
        if groups[1] or ContainsAny(text, { "group text", "group health and text", "party text", "raid text", "mythic raid text" }) then
            return MenuSelectorAction({
                selector = "group_text",
                scope = groups[1] or SelectorGroupScope(text),
                tab = textTab,
                slot = textSlot,
            }, "Select group text editor state")
        end
        local unit = SelectorUnit(text)
        if unit then
            return MenuSelectorAction({
                selector = "unit_text",
                unit = unit,
                tab = textTab,
                slot = textSlot,
            }, "Select unit text editor state")
        end
    end

    if ContainsAny(text, { "spell indicator selector", "spell indicator dropdown", "spell indicator spec", "tracked spell selector", "tracked spells selector", "tracked spell", "multi spec entry", "multi-spec entry" }) then
        local spec = A.ResolveGroupSpellSpec and A.ResolveGroupSpellSpec(text) or nil
        local aura, resolvedSpec = A.ResolveGroupSpellAura and A.ResolveGroupSpellAura(spec, text) or nil
        spec = spec or resolvedSpec
        if spec or aura then
            return MenuSelectorAction({
                selector = "group_spell",
                scope = SelectorGroupScope(text),
                spec = spec,
                aura = aura,
                text = text,
            }, "Select group spell indicator editor state")
        end
    end

    if ContainsAny(text, { "corner editor slot", "editor slot", "corner slot", "custom spell editor" }) then
        local slot = A.ResolveGroupCornerSlot and A.ResolveGroupCornerSlot(text) or nil
        if slot then
            return MenuSelectorAction({
                selector = "group_corner",
                scope = SelectorGroupScope(text),
                slot = slot.key or slot.value or text,
                text = text,
            }, "Select group corner editor slot")
        end
    end

    local statusTab = StatusSelectorTab(text)
    local statusIntent = StatusSelectorIntent(text)
    if statusIntent then
        local groups = DetectGroups(text)
        local groupStatusIcon = GroupStatusIconForText(text)
        if groups[1] or ContainsAny(text, { "group status", "group indicator", "party indicator", "raid indicator", "mythic raid indicator" }) then
            if statusTab or groupStatusIcon then
                return MenuSelectorAction({
                    selector = "group_status",
                    scope = groups[1] or SelectorGroupScope(text),
                    tab = statusTab,
                    icon = groupStatusIcon,
                    text = text,
                }, "Select group status icon editor state")
            end
        end

        local unit = SelectorUnit(text)
        local unitStatus = unit and A.ResolveUnitStatusSpec and A.ResolveUnitStatusSpec(unit, text) or nil
        if unit and (statusTab or unitStatus) then
            return MenuSelectorAction({
                selector = "unit_status",
                unit = unit,
                tab = statusTab,
                status = unitStatus and unitStatus.value,
                text = text,
            }, "Select unit status editor state")
        end

        if groupStatusIcon then
            return MenuSelectorAction({
                selector = "group_status",
                scope = SelectorGroupScope(text),
                icon = groupStatusIcon,
                text = text,
            }, "Select group status icon editor state")
        end
    end

    return nil
end

P.BuildChanges = BuildChanges
P.ParseUnsupportedDetailShortcut = ParseUnsupportedDetailShortcut
P.CurrentPageUnit = CurrentPageUnit
P.DetailUnitsOrCurrentPage = DetailUnitsOrCurrentPage
P.BuildUnitDetailChoices = BuildUnitDetailChoices
P.ParsePortraitDetailShortcut = ParsePortraitDetailShortcut
P.DETAIL_MOVE_SPECS = DETAIL_MOVE_SPECS
P.GROUP_DETAIL_MOVE_SPECS = GROUP_DETAIL_MOVE_SPECS
P.ParseGenericOffsetMove = ParseGenericOffsetMove
P.ParseUnitDetailMove = ParseUnitDetailMove
P.GroupScopesOrCurrentPage = GroupScopesOrCurrentPage
P.ParseGroupDetailMove = ParseGroupDetailMove
P.OutlineScopeSettingForText = OutlineScopeSettingForText
P.ParseBorderThicknessShortcut = ParseBorderThicknessShortcut
P.ParseUnitDetailOffsetShortcut = ParseUnitDetailOffsetShortcut
P.CASTBAR_DETAIL_PREFIXES = CASTBAR_DETAIL_PREFIXES
P.CastbarDetailUnitsOrCurrentPage = CastbarDetailUnitsOrCurrentPage
P.ParseCastbarTextMoveShortcut = ParseCastbarTextMoveShortcut
P.ParseUnitOpacityShortcut = ParseUnitOpacityShortcut
P.GroupColorModeScopes = GroupColorModeScopes
P.GroupBarColorModeForText = GroupBarColorModeForText
P.ParseGroupFrameColorMode = ParseGroupFrameColorMode
P.MENU_SELECTOR_VERBS = MENU_SELECTOR_VERBS
P.HasMenuSelectorVerb = HasMenuSelectorVerb
P.MenuSelectorAction = MenuSelectorAction
P.SelectorUnit = SelectorUnit
P.SelectorGroupScope = SelectorGroupScope
P.TextSelectorTab = TextSelectorTab
P.TextSelectorSlot = TextSelectorSlot
P.TextSelectorIntent = TextSelectorIntent
P.TextMoveTogetherIntent = TextMoveTogetherIntent
P.TextMoveTogetherValue = TextMoveTogetherValue
P.StatusSelectorTab = StatusSelectorTab
P.StatusSelectorIntent = StatusSelectorIntent
P.ParseMenuSelectorState = ParseMenuSelectorState
