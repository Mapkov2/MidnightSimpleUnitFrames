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
    return ContainsAny(text, CLASS_POWER_TERMS) and not ClassPowerMentionIsNegated(text)
end

local function ParseClassPowerRootToggle(text)
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
        summary = "Moves the registered Class Resource Offset X/Y slider by pixels.",
    }
end

A._GameplayShortcutSpecs = A._GameplayShortcutSpecs or {
    {
        id = "combatTimer",
        label = "Combat Timer",
        terms = { "combat timer" },
        pageTerms = { "timer" },
        enable = "gameplay.enableCombatTimer",
        x = "gameplay.combatOffsetX",
        y = "gameplay.combatOffsetY",
        size = "gameplay.combatFontSize",
        anchor = "gameplay.combatTimerAnchor",
        booleans = {
            { key = "gameplay.lockCombatTimer", terms = { "lock", "locked", "lock position" } },
            { key = "gameplay.combatTimerClickThrough", terms = { "click through", "click-through", "mouse clicks", "mouse input" } },
        },
    },
    {
        id = "combatState",
        label = "Combat Enter Leave Text",
        terms = { "combat state", "combat enter leave", "combat enter", "combat leave" },
        pageTerms = { "enter leave", "enter text", "leave text", "combat text", "state text" },
        enable = "gameplay.enableCombatStateText",
        x = "gameplay.combatStateOffsetX",
        y = "gameplay.combatStateOffsetY",
        size = "gameplay.combatStateFontSize",
        duration = "gameplay.combatStateDuration",
        booleans = {
            { key = "gameplay.lockCombatState", terms = { "lock", "locked", "lock position" } },
            { key = "gameplay.combatStateColorSync", terms = { "sync color", "sync colors", "color sync" } },
        },
    },
    {
        id = "playerTotems",
        label = "Totem Frame",
        terms = { "totem frame", "totemframe", "blizzard totem", "statue frame" },
        pageTerms = { "totem", "totems", "statue" },
        enable = "gameplay.enablePlayerTotems",
        x = "gameplay.playerTotemsOffsetX",
        y = "gameplay.playerTotemsOffsetY",
        size = "gameplay.playerTotemsIconSize",
        anchorFrom = "gameplay.playerTotemsAnchorFrom",
        anchorTo = "gameplay.playerTotemsAnchorTo",
    },
    {
        id = "firstDance",
        label = "First Dance Tracker",
        terms = { "first dance" },
        pageTerms = { "dance tracker" },
        enable = "gameplay.enableFirstDanceTimer",
        x = "gameplay.firstDanceOffsetX",
        y = "gameplay.firstDanceOffsetY",
        size = "gameplay.firstDanceIconSize",
        booleans = {
            { key = "gameplay.lockFirstDance", terms = { "lock", "locked", "lock position" } },
            { key = "gameplay.firstDanceClickThrough", terms = { "click through", "click-through", "mouse input" } },
            { key = "gameplay.firstDanceShowIcon", terms = { "icon", "icon mode", "cooldown swipe" } },
            { key = "gameplay.firstDanceShowReady", terms = { "show ready", "ready visible", "keep visible", "ready" } },
        },
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
            { key = "gameplay.enableCombatCrosshairMeleeRangeColor", terms = { "range color", "melee range color", "in range color", "color mode" } },
            { key = "gameplay.meleeSpellPerClass", terms = { "per class", "class spell", "spell per class" } },
            { key = "gameplay.meleeSpellPerSpec", terms = { "per spec", "spec spell", "spell per spec" } },
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
        if ContainsAny(text, { "timer" }) and not ContainsAny(text, { "first dance", "dance", "enter", "leave", "state" }) then
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
        summary = summary or "Changes a registered Gameplay control.",
    } or nil
end

function A._ParseGameplayBooleanShortcut(text)
    local value = DetectBoolean(text)
    if value == nil then return nil end
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
    if not key then
        if ContainsAny(text, { "anchor", "attach", "size", "font", "duration", "offset", "position", "move", "x", "y", "thickness", "thick", "thin", "spell" }) then
            return nil
        end
        key = spec.enable
    end
    return A._GameplayShortcutChange(key, value, nil, nil, spec.label, "Toggles a registered Gameplay control.")
end

function A._ParseGameplayAnchorShortcut(text)
    if not ContainsAny(text, { "anchor", "attach", "attached", "from point", "to point" }) then return nil end
    local spec = A._GameplayShortcutSpec(text)
    if not spec then return nil end
    local key
    if spec.id == "combatTimer" then
        key = spec.anchor
    elseif spec.id == "playerTotems" then
        if ContainsAny(text, { "from anchor", "anchor from", "from point" }) then
            key = spec.anchorFrom
        elseif ContainsAny(text, { "to anchor", "anchor to", "to point", "attach to" }) then
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
        summary = "Changes a registered Gameplay anchor selector.",
    }
end

function A._ParseGameplayNumberShortcut(text)
    local spec = A._GameplayShortcutSpec(text)
    if not spec then return nil end
    if ContainsAny(text, { "spell", "spell id", "range check spell" }) then return nil end
    local key
    if spec.id == "combatState" and ContainsAny(text, { "duration", "time visible", "visible time" }) then
        key = spec.duration
    elseif spec.id == "combatCrosshair" and ContainsAny(text, { "thickness", "thick", "thicker", "thin", "thinner" }) then
        key = spec.thickness
    elseif ContainsAny(text, { "size", "font size", "text size", "icon size", "bigger", "larger", "smaller", "grow", "shrink", "groesser", "kleiner" }) then
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
        summary = "Changes a registered Gameplay number slider.",
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
            text = tostring(spec.label or "That Gameplay element") .. " position is not exposed by the current MSUF UI/DB. The Assistant can only change registered safe UI controls.",
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
        summary = "Moves a registered Gameplay element through its real X/Y offset setting.",
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

local function ParseColorAction(text)
    if not ContainsAny(text, { "reset", "default", "defaults", "restore", "zuruecksetzen" }) then return nil end
    if not ContainsAny(text, { "color", "colors", "colour", "colours", "farbe", "farben", "tint" }) then return nil end
    if ContainsAny(text, { "combo point slot", "combo point slots", "combo slot", "combo slots" }) then
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
            label = "Reset power bar token color",
            summary = "Resets a single Power Bar color token.",
        } or nil
    end
    local cpToken = ClassPowerColorTokenForText(text)
    if cpToken and ContainsAny(text, { "class power", "class resource", "resource", "combo", "soul", "maelstrom", "astral", "eclipse", "stagger", "icicles", "ebon", "whirlwind", "tip of the spear", "insanity", "runes", "chi", "essence" }) then
        local action = Registry and Registry:GetAction("reset_class_power_color_token")
        return action and {
            kind = "action",
            action = action,
            args = { token = cpToken, background = ContainsAny(text, { "background", "bg" }) },
            label = "Reset class resource token color",
            summary = "Resets a single Class Resource foreground or background token color.",
        } or nil
    end
    if ContainsAny(text, { "castbar", "cast bar" }) then
        return BuildColorResetAction("reset_castbar_colors", "Reset castbar colors", "Resets castbar colors through the existing Colors page state.")
    end
    if ContainsAny(text, { "npc type", "npc role" }) then
        return BuildColorResetAction("reset_npc_type_colors", "Reset NPC type colors", "Resets NPC type colors.")
    end
    if ContainsAny(text, { "unitframe", "unit frame", "npc reaction", "reaction color" }) then
        return BuildColorResetAction("reset_unitframe_colors", "Reset unitframe colors", "Resets unitframe NPC reaction colors.")
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
        return BuildColorResetAction("reset_gameplay_colors", "Reset gameplay colors", "Resets Gameplay color settings.")
    end
    if ContainsAny(text, { "aura", "auras", "buff", "debuff", "pandemic" }) then
        return BuildColorResetAction("reset_aura_colors", "Reset aura colors", "Resets Aura color settings.")
    end
    if ContainsAny(text, { "portrait" }) then
        return BuildColorResetAction("reset_portrait_colors", "Reset portrait colors", "Resets portrait color settings.")
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
    if not ContainsAny(text, { "diagnose", "diagnostic", "troubleshoot", "why", "wieso", "warum", "not showing", "not visible", "missing", "doesnt show", "does not show", "hidden", "nicht sichtbar", "zeigt nicht" }) then return nil end
    if ContainsAny(text, { "profile", "profiles", "profil", "profile import", "profile export", "spec profile" }) then
        local action = Registry and Registry:GetAction("diagnose_profile_status")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Diagnose Profiles",
            summary = "Inspects profile storage, active profile, spec mappings, staging fields, and helper availability.",
        } or nil
    end
    if ContainsAny(text, { "class resource", "class resources", "class power", "class bar", "resource bar" }) then
        local action = Registry and Registry:GetAction("diagnose_class_power_status")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Diagnose Class Resources",
            summary = "Inspects Class Resource visibility, sizing, opacity, width mode, and hide rules.",
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
            label = "Diagnose " .. tostring((A.UnitLabels or {})[unit] or unit) .. " castbar",
            summary = "Inspects current castbar settings and suggests the next safe fix.",
        } or nil
    end
    local groups = DetectGroups(text)
    if #groups > 0 or ContainsAny(text, { "group frames", "gruppenframes", "party frames", "raid frames", "mythic raid frames" }) then
        local scope = groups[1] or "party"
        if scope == "mythicraid" then scope = "mythicraid" end
        local action = Registry and Registry:GetAction("diagnose_group_visibility")
        return action and {
            kind = "action",
            action = action,
            args = { scope = scope },
            label = "Diagnose " .. tostring((A.UnitLabels or {})[scope] or scope) .. " group frames",
            summary = "Inspects current group-frame settings and suggests the next safe fix.",
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
            label = "Diagnose " .. tostring((A.UnitLabels or {})[unit] or unit) .. " frame",
            summary = "Inspects current unit-frame settings and suggests the next safe fix.",
        } or nil
    end
    if ContainsAny(text, { "dashboard", "assistant setup", "menu setup", "navigation", "page stack", "workflow", "setup checklist", "guided setup" })
        or text == "diagnose setup"
        or text == "diagnostic setup"
        or text == "troubleshoot setup"
    then
        local action = Registry and Registry:GetAction("diagnose_dashboard_setup")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Diagnose Dashboard setup",
            summary = "Inspects Assistant pending state, Dashboard panels, page stack, and navigation helper availability.",
        } or nil
    end
    return nil
end

local function ParseScopedHelp(text)
    if not ContainsAny(text, {
        "what can i change", "what can change", "what settings can i change",
        "what can i do here", "what can i change here", "commands for",
        "show commands for", "help for", "help with", "help me with",
    }) then return nil end
    local action = Registry and Registry:GetAction("assistant_scope_help")
    if not action then return nil end
    local page, label = PageForText(text)
    if not page and ContainsAny(text, { "here", "current page", "this page" }) then
        page = M and M.activeKey
        label = "current page"
    end
    local units = DetectUnits(text)
    local groups = DetectGroups(text)
    local unit = units[1]
    local group = groups[1]
    local frameType = FrameTypeForPage(page)
    if group then
        frameType = ContainsAny(text, { "aura", "auras", "buff", "debuff" }) and "groupAura" or "group"
        label = (A.UnitLabels and A.UnitLabels[group]) or label
    elseif unit then
        frameType = ContainsAny(text, { "castbar", "cast bar" }) and "castbar" or "unitframe"
        label = (A.UnitLabels and A.UnitLabels[unit]) or label
    elseif not frameType then
        frameType = DetectFrameType(text, {})
    end
    return {
        kind = "action",
        action = action,
        args = { page = page, label = label, frameType = frameType, unit = unit, group = group },
        label = "Show scoped Assistant help",
        summary = "Shows registry-backed commands for the requested area.",
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
    "edit mode", "editmode", "msuf edit mode", "bearbeitungsmodus", "frame edit mode",
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
        summary = summary or "Controls a real MSUF Edit Mode HUD control.",
    } or nil
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

local function ParseEditModeHUDControl(text)
    local hasEditContext = HasEditModeContext(text)
    local hasAuraPreview = ContainsAny(text, {
        "preview auras", "preview aura", "aura preview", "aura previews", "aura icons",
        "aura preview icons", "aura mover", "aura movers", "aura mover boxes",
        "auren vorschau", "vorschau auren", "auren symbole", "auren icons",
    }) or (hasEditContext and ContainsAny(text, { "auras", "aura", "auren" }))
    local hasUnitPreview = ContainsAny(text, {
        "unit preview", "unit previews", "preview frames", "preview frame", "frame preview",
        "frame previews", "placeholder data", "preview placeholders", "vorschau frames",
        "frame vorschau",
    }) or (hasEditContext and ContainsAny(text, { "preview", "vorschau" }) and not hasAuraPreview)
    local hasGroupPreview = ContainsAny(text, {
        "gf preview", "group frame preview", "group frames preview", "group preview",
        "party frame preview", "party frames preview", "party preview",
        "raid frame preview", "raid frames preview", "raid preview",
        "mythic raid frame preview", "mythic raid frames preview", "mythic raid preview",
        "party raid preview", "gruppenframes preview", "gruppen preview",
    }) or (hasEditContext and ContainsAny(text, { "gf" }) and (DetectBoolean(text) ~= nil or ContainsAny(text, { "toggle", "umschalten" })))
    local hasSnap = ContainsAny(text, {
        "snap", "snapping", "grid snap", "snap frames", "snap to grid", "einrasten",
        "raster snap", "raster einrasten",
    })
    local hasCDM = ContainsAny(text, {
        "cdm", "cooldown manager", "essential cooldown manager", "anchor to cooldown",
        "cooldown anchor", "cooldown manager anchor",
    })
    local hasAnchorPicker = ContainsAny(text, {
        "anchor picker", "global anchor picker", "pick anchor", "select anchor",
        "choose anchor", "open anchor", "anker picker", "anker auswahl", "anker waehlen",
    }) and (hasEditContext or ContainsAny(text, { "global anchor picker", "anchor picker" }))
    local hasResetPosition = hasEditContext and ContainsAny(text, { "reset", "restore", "default", "zuruecksetzen" })
        and ContainsAny(text, { "position", "selected frame", "current frame", "selected", "selection", "frame position", "mover" })

    if hasAnchorPicker then
        return EditModeAction("assistant.action.editMode.anchorPicker", {}, "Open Edit Mode Anchor picker")
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
    if hasUnitPreview then
        return EditModeAction("assistant.action.editMode.preview", { value = value }, "Set Edit Mode Preview")
    end
    if hasSnap and (hasEditContext or ContainsAny(text, { "snap frames", "grid snap", "snap to grid" })) then
        return EditModeAction("assistant.action.editMode.snap", { value = value }, "Set Edit Mode Snap")
    end
    if hasCDM then
        return EditModeAction("assistant.action.editMode.cdm", { value = value }, "Set Edit Mode CDM Anchor")
    end
    return nil
end

local function ParseSupportWorkflow(text)
    if ContainsAny(text, {
        "msuf status", "assistant status", "status report", "diagnostic report",
        "diagnostics", "debug summary", "version info", "locale info",
    }) then
        local action = Registry and Registry:GetAction("assistant_status")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Show MSUF status",
            summary = "Shows read-only MSUF and Assistant diagnostic status.",
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
            summary = "Shows deterministic Assistant command examples.",
        } or nil
    end

    local editModeControl = ParseEditModeHUDControl(text)
    if editModeControl then return editModeControl end

    if ContainsAny(text, { "edit mode", "move frames", "drag frames", "position frames" }) then
        local actionKey = "assistant.action.editMode.enter"
        local label = "Enter MSUF Edit Mode"
        local args = {}
        if ContainsAny(text, {
            "am i in edit mode", "is edit mode on", "is edit mode active", "edit mode status",
            "why can't i exit edit mode", "why cant i exit edit mode", "why can not i exit edit mode",
            "why can't leave edit mode", "why cant leave edit mode",
        }) then
            actionKey = "assistant.diagnostic.editMode.status"
            label = "Show MSUF Edit Mode status"
            if ContainsAny(text, { "why can't", "why cant", "why can not" }) then args.reason = "why_exit" end
        elseif ContainsAny(text, { "cancel edit mode", "discard edit mode", "cancel msuf edit mode", "cancel all edit mode" }) then
            actionKey = "assistant.action.editMode.cancel"
            label = "Cancel MSUF Edit Mode"
        elseif ContainsAny(text, { "toggle edit mode", "toggle msuf edit mode" }) then
            actionKey = "assistant.action.editMode.toggle"
            label = "Toggle MSUF Edit Mode"
        elseif ContainsAny(text, {
            "stop edit mode", "exit edit mode", "exit msuf edit mode", "leave edit mode", "leave msuf edit mode",
            "close edit mode", "close msuf edit mode", "disable edit mode", "turn off edit mode", "edit mode off",
        }) then
            actionKey = "assistant.action.editMode.exit"
            label = "Exit MSUF Edit Mode"
        end
        local action = Registry and Registry:GetAction(actionKey)
        return action and {
            kind = "action",
            action = action,
            args = args,
            confirmRequired = actionKey == "assistant.action.editMode.cancel",
            label = label,
            summary = "Controls the shared MSUF Edit Mode lifecycle helpers.",
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
            summary = "Updates the Dashboard Wago backup checklist state for the active profile.",
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

    if ContainsAny(text, { "support links", "support msuf", "donate links", "development links" }) then
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
    if ContainsAny(text, { "turn off", "disable", "off", "auto" }) then return "off" end
    return nil
end

local function ParsePresetWorkflow(text)
    if not ContainsAny(text, { "preset", "global ui scale", "wow ui scale", "global scale", "scale preset" }) then return nil end
    if not ContainsAny(text, { "global ui scale", "wow ui scale", "global scale", "scale preset" }) then return nil end
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
        label = all and "Reset all scoped overrides" or "Reset scoped override",
        summary = "Uses the same scoped override flags as Global Style.",
    } or nil
end

local function ParseClassPowerAction(text)
    if not ContainsAny(text, { "quick setup", "quicksetup", "setup" }) then return nil end
    if not HasClassPowerIntent(text) then return nil end
    local action = Registry and Registry:GetAction("class_power_quick_setup")
    return action and {
        kind = "action",
        action = action,
        args = {},
        confirmRequired = true,
        label = "Quick setup class bar",
        summary = "Runs the Class Resources quick setup workflow.",
    } or nil
end

local GAMEPLAY_ROOT_TOGGLES = {
    {
        key = "gameplay.enableCombatTimer",
        label = "Combat Timer",
        terms = { "combat timer" },
        details = { "anchor", "attach", "size", "font", "text size", "lock", "locked", "click through", "click-through", "x", "y", "offset", "move", "color", "colors" },
    },
    {
        key = "gameplay.enableCombatStateText",
        label = "Combat Enter Leave Text",
        terms = { "combat state", "combat enter leave", "combat enter", "combat leave" },
        details = { "size", "font", "duration", "lock", "locked", "x", "y", "offset", "move", "color", "colors", "sync" },
    },
    {
        key = "gameplay.enablePlayerTotems",
        label = "Blizzard Totem Frame",
        terms = { "totem frame", "totemframe", "blizzard totem", "statue frame" },
        details = { "icon", "size", "x", "y", "offset", "anchor", "from", "to", "preview", "reset", "layout", "move" },
    },
    {
        key = "gameplay.enableFirstDanceTimer",
        label = "First Dance Tracker",
        terms = { "first dance" },
        details = { "icon", "ready", "size", "lock", "locked", "click through", "click-through", "x", "y", "offset", "move" },
    },
    {
        key = "gameplay.enableCombatCrosshair",
        label = "Combat Crosshair",
        terms = { "combat crosshair", "crosshair", "fadenkreuz" },
        details = { "range", "melee", "color", "colors", "spell", "size", "thickness", "x", "y", "offset", "move", "class", "spec" },
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
                summary = "Toggles a Gameplay setting.",
            } or nil
        end
    end
    return nil
end

local function ParseGameplayAction(text, raw)
    if ContainsAny(text, { "crosshair", "fadenkreuz", "melee range spell", "range check spell" }) and ContainsAny(text, { "spell", "range check" }) then
        local rawText = tostring(raw or "")
        local value
        if ContainsAny(text, { "clear", "reset", "none", "no spell" }) then
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
    if ContainsAny(text, { "preview", "test" }) and ContainsAny(text, { "totem frame", "totemframe", "blizzard totem", "statue frame" }) then
        local action = Registry and Registry:GetAction("preview_player_totems")
        return action and {
            kind = "action",
            action = action,
            args = {},
            label = "Preview Totem Frame",
            summary = "Toggles the TotemFrame preview.",
        } or nil
    end
    if ContainsAny(text, { "reset", "restore", "default", "defaults" }) and ContainsAny(text, { "totem frame", "totemframe", "blizzard totem", "statue frame" }) then
        local action = Registry and Registry:GetAction("reset_player_totems_layout")
        return action and {
            kind = "action",
            action = action,
            args = {},
            confirmRequired = true,
            label = "Reset Totem Frame Layout",
            summary = "Restores the TotemFrame layout defaults.",
        } or nil
    end
    return nil
end

local function ParseGlobalBarsAction(text)
    if ContainsAny(text, { "dispel test type", "dispel border test type", "dispel border preview type" }) then
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
    if ContainsAny(text, { "test", "preview" }) and ContainsAny(text, { "absorb bar", "absorb bars", "prediction bars", "heal absorb" }) then
        local action = Registry and Registry:GetAction("toggle_absorb_bar_test")
        return action and {
            kind = "action",
            action = action,
            args = { value = not ContainsAny(text, { "off", "disable", "stop", "clear" }) },
            label = "Toggle absorb bar test",
            summary = "Toggles the absorb prediction bar test display.",
        } or nil
    end
    if ContainsAny(text, { "clear", "stop", "disable", "off" }) and ContainsAny(text, { "absorb test", "prediction bar test" }) then
        local action = Registry and Registry:GetAction("toggle_absorb_bar_test")
        return action and {
            kind = "action",
            action = action,
            args = { value = false },
            label = "Disable absorb bar test",
            summary = "Turns off the absorb prediction bar test display.",
        } or nil
    end
    if ContainsAny(text, { "test", "preview" }) and ContainsAny(text, { "aggro border", "threat border" }) then
        local action = Registry and Registry:GetAction("toggle_highlight_border_test")
        return action and { kind = "action", action = action, args = { kind = "aggro", value = not ContainsAny(text, { "off", "disable", "stop", "clear" }) }, label = "Test aggro border", summary = "Toggles the aggro border test." } or nil
    end
    if ContainsAny(text, { "test", "preview" }) and ContainsAny(text, { "dispel border", "dispellable border" }) then
        local action = Registry and Registry:GetAction("toggle_highlight_border_test")
        return action and { kind = "action", action = action, args = { kind = "dispel", value = not ContainsAny(text, { "off", "disable", "stop", "clear" }) }, label = "Test dispel border", summary = "Toggles the dispel border test." } or nil
    end
    if ContainsAny(text, { "test", "preview" }) and ContainsAny(text, { "purge border", "purgeable border" }) then
        local action = Registry and Registry:GetAction("toggle_highlight_border_test")
        return action and { kind = "action", action = action, args = { kind = "purge", value = not ContainsAny(text, { "off", "disable", "stop", "clear" }) }, label = "Test purge border", summary = "Toggles the purge border test." } or nil
    end
    if ContainsAny(text, { "test", "preview" }) and ContainsAny(text, { "boss target border", "boss target highlight" }) then
        local action = Registry and Registry:GetAction("toggle_highlight_border_test")
        return action and { kind = "action", action = action, args = { kind = "bossTarget", value = not ContainsAny(text, { "off", "disable", "stop", "clear" }) }, label = "Test boss target border", summary = "Toggles the boss target border test." } or nil
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
        summary = "Adjusts the real Colors > Unitframe Global Coloring dark-mode bar color slider.",
    }
end

local function ParseCastbarPreviewAction(text)
    if not ContainsAny(text, { "test", "preview", "show preview" }) then return nil end
    if not ContainsAny(text, { "castbar", "cast bar" }) then return nil end
    local action = Registry and Registry:GetAction("preview_castbar")
    if not action then return nil end
    local units = DetectUnits(text)
    local unit = units[1] or "player"
    local kind = "normal"
    if ContainsAny(text, { "channel", "channeled", "channelled" }) then
        kind = "channel"
    elseif ContainsAny(text, { "empowered", "empower", "evoker" }) then
        kind = "empowered"
    end
    return {
        kind = "action",
        action = action,
        args = {
            unit = unit,
            kind = kind,
            interrupt = ContainsAny(text, { "interrupt", "interrupted", "shake" }),
        },
        label = "Preview castbar",
        summary = "Opens the Castbar page and selects the requested transient preview.",
    }
end

local CASTBAR_GLOBAL_BOOLEAN_DETAILS = {
    { key = "general.castbarShowChannelTicks", terms = { "channel ticks", "channel tick lines", "castbar ticks", "tick lines" } },
    { key = "general.castbarShowGlow", terms = { "glow", "glow effect" } },
    { key = "general.castbarShowSpark", terms = { "spark", "castbar spark" } },
    { key = "general.castbarSparkOverflow", terms = { "spark overflow", "spark beyond bar" } },
    { key = "general.castbarShowLatency", terms = { "latency", "latency indicator" } },
    { key = "general.castbarUnifiedDirection", terms = { "unified direction", "unified fill direction", "same fill direction" } },
    { key = "general.castbarOpositeDirectionTarget", terms = { "target opposite direction", "opposite target direction", "target opposite fill direction" } },
    { key = "general.empowerColorStages", terms = { "empower color stages", "empowered stage colors", "empower stage colors" } },
    { key = "general.empowerStageBlink", terms = { "empower stage blink", "empowered stage blink", "stage blink" } },
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
                label = setting.label or "Castbar detail",
                summary = "Changes a global Castbar detail setting without toggling the unit castbar root.",
            } or nil
        end
    end
    return nil
end

local function ParseGuidedSetup(text)
    if not ContainsAny(text, { "help me build", "guided setup", "setup", "build a clean", "clean layout", "rogue layout", "layout bauen", "setup hilfe" }) then return nil end
    local action = Registry and Registry:GetAction("guided_setup")
    return action and {
        kind = "action",
        action = action,
        args = { style = text },
        label = "Guided setup",
        summary = "Starts a deterministic setup workflow.",
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
    })
    if not active and not explicit then return nil end
    local command
    if ContainsAny(text, { "cancel setup", "stop setup", "abort setup", "setup cancel" }) or (active and HasPhrase(text, "cancel")) then
        command = "cancel"
    elseif ContainsAny(text, { "finish setup", "done setup", "setup done", "complete setup", "setup complete" }) or (active and HasPhrase(text, "done")) then
        command = "finish"
    elseif ContainsAny(text, { "skip setup", "skip setup step", "setup skip" }) or (active and HasPhrase(text, "skip")) then
        command = "skip"
    elseif ContainsAny(text, { "next setup", "next setup step", "setup next", "continue setup" }) or (active and ContainsAny(text, { "next", "continue" })) then
        command = "next"
    elseif ContainsAny(text, { "back setup", "back setup step", "setup back", "previous setup", "previous setup step", "setup previous" }) or (active and ContainsAny(text, { "back", "previous" })) then
        command = "back"
    elseif ContainsAny(text, { "show setup", "show setup step", "repeat setup", "current setup step", "setup status" }) then
        command = "show"
    end
    if not command then return nil end
    local action = Registry and Registry:GetAction("guided_setup_step")
    return action and {
        kind = "action",
        action = action,
        args = { command = command },
        label = "Guided setup step",
        summary = "Continues the active deterministic setup workflow.",
    } or nil
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
P.SupportLinkForText = SupportLinkForText
P.ParseSupportWorkflow = ParseSupportWorkflow
P.GlobalScalePresetForText = GlobalScalePresetForText
P.ParsePresetWorkflow = ParsePresetWorkflow
P.ParseScopedOverrideReset = ParseScopedOverrideReset
P.ParseClassPowerAction = ParseClassPowerAction
P.GAMEPLAY_ROOT_TOGGLES = GAMEPLAY_ROOT_TOGGLES
P.ParseGameplayRootToggle = ParseGameplayRootToggle
P.ParseGameplayAction = ParseGameplayAction
P.ParseGlobalBarsAction = ParseGlobalBarsAction
P.ParseDarkModeBrightnessShortcut = ParseDarkModeBrightnessShortcut
P.ParseCastbarPreviewAction = ParseCastbarPreviewAction
P.CASTBAR_GLOBAL_BOOLEAN_DETAILS = CASTBAR_GLOBAL_BOOLEAN_DETAILS
P.ParseCastbarGlobalDetail = ParseCastbarGlobalDetail
P.ParseGuidedSetup = ParseGuidedSetup
P.ParseGuidedSetupFollowup = ParseGuidedSetupFollowup
