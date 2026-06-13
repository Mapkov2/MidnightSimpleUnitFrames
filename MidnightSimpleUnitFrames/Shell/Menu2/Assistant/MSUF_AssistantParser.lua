local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

--- Shell/Menu2/Assistant/MSUF_AssistantParser.lua
---
--- High-level parse pipeline for assistant commands. The many P.* helpers are
--- loaded from registry/domain parser files; this module orders them from most
--- specific workflow/geometry matches to broader registry fallback.
---
--- New parser work should usually live in the owning domain file and be called
--- from one of the _ParsePipeline* functions below. Avoid applying settings here:
--- return a plan/action and let MSUF_Assistant.lua execute it.

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
local AuraBlacklistPresetForText = P.AuraBlacklistPresetForText
local AuraGroupBlacklistScope = P.AuraGroupBlacklistScope
local AuraGroupBlacklistLane = P.AuraGroupBlacklistLane
local AuraGroupBlacklistCategoryForText = P.AuraGroupBlacklistCategoryForText
local AuraBlacklistSpellValue = P.AuraBlacklistSpellValue
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
local ParseScopedFontTextColorShortcut = P.ParseScopedFontTextColorShortcut
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
local ContextUnits = P.ContextUnits
local GROUP_CONTEXT_UNITS = P.GROUP_CONTEXT_UNITS
local IsGroupContextUnit = P.IsGroupContextUnit
local ContextGroups = P.ContextGroups
local ShouldUseLastUnitContext = P.ShouldUseLastUnitContext
local BuildFollowup = P.BuildFollowup
local BuildBooleanCorrection = P.BuildBooleanCorrection
local ParseSetting = P.ParseSetting

if not P.InitUnsupportedAuraCommand then
    function P.InitUnsupportedAuraCommand()
        if not P.AURA_OUT_OF_SCOPE_TERMS then
            P.AURA_OUT_OF_SCOPE_TERMS = {
                "aura", "auras", "auren",
                "group aura", "group auras", "gruppen aura", "gruppenauren",
            }
        end
        if not P.AURA_BUFF_TERMS then
            P.AURA_BUFF_TERMS = { "buff", "buffs", "debuff", "debuffs" }
        end
        if not P.AURA_BUFF_CONTEXT_TERMS then
            P.AURA_BUFF_CONTEXT_TERMS = {
                "filter", "filters", "blacklist", "whitelist", "preset", "quick setup", "setup",
                "hidden", "hide", "show", "open", "help", "why", "where", "settings",
                "turn", "turn on", "turn off", "on", "off", "enable", "disable", "enabled", "disabled",
                "set", "change", "make", "size", "count", "max", "icon", "icons", "per row", "growth",
                "copy", "use", "kopieren", "kopiere", "uebernehme", "uebernehmen",
                "own", "mine", "only mine", "only player", "raid filter", "player filter",
                "stack", "cooldown", "pandemic",
            }
        end
        if not P.AURA_COPY_COMMAND_TERMS then
            P.AURA_COPY_COMMAND_TERMS = {
                "copy", "use", "kopieren", "kopiere", "uebernehme", "uebernehmen",
                "look like", "looks like", "same as", "the same as", "match", "mirror", "clone",
            }
        end
        if not P.AURA_COPY_EXCLUDE_TERMS then
            P.AURA_COPY_EXCLUDE_TERMS = {
                "not aura", "not auras", "no aura", "no auras",
                "without aura", "without auras", "except aura", "except auras",
                "excluding aura", "excluding auras", "exclude aura", "exclude auras",
                "but not aura", "but not auras", "aber keine aura", "aber keine auren",
                "ohne aura", "ohne auras", "ohne auren",
            }
        end
        if not P.AURA_DEBUFF_STRIPE_TERMS then
            P.AURA_DEBUFF_STRIPE_TERMS = { "debuff stripe", "debuff stripes" }
        end
        if not P.AURA_DISPEL_OVERLAY_TERMS then
            P.AURA_DISPEL_OVERLAY_TERMS = { "dispel overlay", "unitframe dispel overlay", "unit frame dispel overlay" }
        end

        if not P.CopyCommandExcludesAuras then
            function P.CopyCommandExcludesAuras(text)
                if not ContainsAny(text, P.AURA_COPY_COMMAND_TERMS) then return false end
                return ContainsAny(text, P.AURA_COPY_EXCLUDE_TERMS)
            end
        end

        if not P.ParseUnsupportedAuraCommand then
            function P.ParseUnsupportedAuraCommand(text)
                if P.CopyCommandExcludesAuras and P.CopyCommandExcludesAuras(text) then return nil end
                if ContainsAny(text, P.AURA_DEBUFF_STRIPE_TERMS) then return nil end
                if ContainsAny(text, P.AURA_DISPEL_OVERLAY_TERMS) then return nil end
                if not ContainsAny(text, P.AURA_OUT_OF_SCOPE_TERMS)
                    and not (ContainsAny(text, P.AURA_BUFF_TERMS) and ContainsAny(text, P.AURA_BUFF_CONTEXT_TERMS))
                then
                    return nil
                end
                return {
                    kind = "unsupported",
                    status = "info",
                    summary = "Aura command is not registered yet.",
                    text = "I could not safely match that Aura command yet. Registered Aura controls such as icon size, count, growth, cooldown and stack text, filters, blacklist, quick presets, and Group Aura copy can be changed. Aura backend areas that are not registered yet stay blocked.",
                }
            end
        end
    end
end
P.InitUnsupportedAuraCommand()

--- Pipeline order matters. Specific workflows and follow-up answers must win
--- before broad registry matching, otherwise "yes", copy/profile flows, and
--- exact assistant keys can be swallowed by generic setting aliases.
function A._ParsePipelineWorkflow(normalized, raw, ctx)
    return ParseGuidedSetupFollowup(normalized, ctx)
        or A._ParseFollowupAnswer(normalized, ctx)
        or BuildFollowup(normalized, ctx)
        or BuildBooleanCorrection(normalized, ctx)
        or (P.ParseBroadHumanAnchorTargetAnswer and P.ParseBroadHumanAnchorTargetAnswer(normalized, raw))
        or ParseWorkflowLifecycle(normalized)
        or (P.ParseProfileRepairShortcut and P.ParseProfileRepairShortcut(normalized))
        or ParseDiagnostic(normalized)
        or ParseGroupCopy(normalized)
        or P.ParseUnsupportedMixedCopy(normalized)
        or ParseCopy(normalized)
        or ParseProfileStagingState(normalized, raw)
        or ParseProfile(normalized, raw)
        or (P.ParseExactRegistryKeyShortcut and P.ParseExactRegistryKeyShortcut(normalized, raw))
        or (P.ParseExactActionKeyShortcut and P.ParseExactActionKeyShortcut(normalized, raw))
        or (P.ParseRegistryActionAliasShortcut and P.ParseRegistryActionAliasShortcut(normalized, raw))
        or (P.ParseRegistryExactAliasShortcut and P.ParseRegistryExactAliasShortcut(normalized, raw))
        or ParseClassPowerAction(normalized)
        or A._ParseClassPowerPlacementShortcut(normalized)
        or A._ParseClassPowerColorShortcut(normalized, raw)
        or A._ParseClassPowerDisplayStyleShortcut(normalized)
        or A._ParseClassPowerBackgroundShortcut(normalized)
        or A._ParseClassPowerAnchorShortcut(normalized)
        or ParseClassPowerRootToggle(normalized)
        or A._ParseClassPowerMoveShortcut(normalized)
        or ParseGameplayRootToggle(normalized)
        or A._ParseGameplayBooleanShortcut(normalized)
        or A._ParseGameplayAnchorShortcut(normalized)
        or A._ParseGameplayNumberShortcut(normalized)
        or A._ParseGameplayPositionPreset(normalized)
        or A._ParseGameplayMoveShortcut(normalized)
        or ParsePresetWorkflow(normalized)
        or (P.ParseNameShorteningShortcut and P.ParseNameShorteningShortcut(normalized, ctx))
        or ParseGuidedSetup(normalized)
        or ParseScopedHelp(normalized)
        or (P.ParseGroupGrowthDirectionShortcut and P.ParseGroupGrowthDirectionShortcut(normalized))
        or (P.ParseGroupPowerBarSizeShortcut and P.ParseGroupPowerBarSizeShortcut(normalized))
        or (P.ParsePowerBarSizeShortcut and P.ParsePowerBarSizeShortcut(normalized))
        or P.ParseMiscRegistryShortcut(normalized, raw)
        or ParseDashboardPanelAction(normalized)
        or ParseNavRailAction(normalized)
        or ParseSupportWorkflow(normalized)
        or ParseMenuWindowAction(normalized)
        or ParseGroupFrameColorMode(normalized)
        or ParseScopedFontTextColorShortcut(normalized)
        or ParseUnitCopyScopeState(normalized)
        or (P.ParseDashboardScaleShortcut and P.ParseDashboardScaleShortcut(normalized))
end

--- Geometry commands often share words with visual feature commands ("move",
--- "size", "left", "right"). Keep exact/positional parsers before fallback
--- setting lookup so directional phrases stay actionable.
function A._ParsePipelineGeometry(normalized, raw)
    return (P.ParseTextVisibilityShortcut and P.ParseTextVisibilityShortcut(normalized))
        or A._ParseNameTextAnchorShortcut(normalized)
        or A._ParseNameTextVerticalPlacementShortcut(normalized)
        or A._ParseTextSlotValueMoveShortcut(normalized)
        or A._ParseTextSlotOffsetShortcut(normalized)
        or (P.ParseHumanAnchorTarget and P.ParseHumanAnchorTarget(normalized, raw))
        or (P.ParseGroupScaleBreakpointShortcut and P.ParseGroupScaleBreakpointShortcut(normalized))
        or (P.ParseGroupGrowthDirectionShortcut and P.ParseGroupGrowthDirectionShortcut(normalized))
        or (P.ParseGroupFrameFillDirectionShortcut and P.ParseGroupFrameFillDirectionShortcut(normalized))
        or (P.ParseCastbarTextSizeShortcut and P.ParseCastbarTextSizeShortcut(normalized))
        or (P.ParseCastbarSizeShortcut and P.ParseCastbarSizeShortcut(normalized))
        or (P.ParseCastbarPlacementShortcut and P.ParseCastbarPlacementShortcut(normalized))
        or (P.ParseGroupPowerBarSizeShortcut and P.ParseGroupPowerBarSizeShortcut(normalized))
        or (P.ParsePowerBarSizeShortcut and P.ParsePowerBarSizeShortcut(normalized))
        or A._ParseTextFontSizeShortcut(normalized)
        or (P.ParseGroupStatusIconDetail and P.ParseGroupStatusIconDetail(normalized))
        or (P.ParseUnitStatusIndicatorDetail and P.ParseUnitStatusIndicatorDetail(normalized))
        or (P.ParseUnitStatusIndicatorMove and P.ParseUnitStatusIndicatorMove(normalized))
        or (P.ParseFrameResizeShortcut and P.ParseFrameResizeShortcut(normalized))
        or P.ParseUnitSizeMatchShortcut(normalized)
        or (P.ParseDetachedPowerBarMoveShortcut and P.ParseDetachedPowerBarMoveShortcut(normalized))
        or (P.ParsePairwiseFrameSpacingShortcut and P.ParsePairwiseFrameSpacingShortcut(normalized))
        or (P.ParseGroupFrameSpacingShortcut and P.ParseGroupFrameSpacingShortcut(normalized))
        or ParseUnitDetailMove(normalized)
        or ParseGroupDetailMove(normalized)
        or (P.ParseGroupFrameRootMove and P.ParseGroupFrameRootMove(normalized))
        or (P.ParseUnitFrameRootMove and P.ParseUnitFrameRootMove(normalized))
        or P.ParseGenericOffsetMove(normalized)
        or ParseUnsupportedDetailShortcut(normalized)
        or ParseScopedOnlyOverride(normalized, raw)
        or ParseGroupFrameColorMode(normalized)
        or A._ParseTextLayerShortcut(normalized)
        or A._ParseTextSlotDropdownShortcut(normalized)
        or ParseMenuSelectorState(normalized)
        or ParsePortraitDetailShortcut(normalized)
        or ParseBorderThicknessShortcut(normalized)
        or A._ParseTextDetailExactOffset(normalized)
        or ParseUnitDetailOffsetShortcut(normalized)
        or ParseCastbarTextMoveShortcut(normalized)
        or A._ParseGroupRangeFadeShortcut(normalized)
        or A._ParseGroupOpacityShortcut(normalized)
        or ParseUnitOpacityShortcut(normalized)
end

--- Feature pipeline handles domain toggles and richer actions that are not
--- pure geometry. It runs after workflow/geometry in A.Parse, then falls back
--- to generic setting parsing if no domain-specific action matched.
function A._ParsePipelineFeature(normalized, raw, ctx)
    return ParseClassPowerAction(normalized)
        or ParseGameplayAction(normalized, raw)
        or ParseDarkModeBrightnessShortcut(normalized)
        or ParseGlobalBarsAction(normalized)
        or (P.ParseNameShorteningShortcut and P.ParseNameShorteningShortcut(normalized, ctx))
        or ParseCastbarGlobalDetail(normalized)
        or (P.ParseCastbarDirectionClarification and P.ParseCastbarDirectionClarification(normalized))
        or ParseCastbarPreviewAction(normalized)
        or ParseScopedOverrideReset(normalized)
        or ParseGuidedSetup(normalized)
        or ParseGroupCopyScopeState(normalized)
        or ParseGroupCopy(normalized)
        or P.ParseUnsupportedMixedCopy(normalized)
        or ParseCopy(normalized)
        or BuildContextReset(normalized, ctx)
        or ParseColorAction(normalized)
        or ParseGroupSpellIndicatorAction(normalized, raw)
        or ParseGroupCornerIndicatorReset(normalized)
        or ParseGroupStatusPreview(normalized)
        or (P.ParseGroupStatusIconDetail and P.ParseGroupStatusIconDetail(normalized))
        or ParseUnitStatusPreview(normalized, ctx)
        or ParseGroupStatusIconReset(normalized)
        or ParseUnitStatusIndicatorReset(normalized, ctx)
        or (P.ParseUnitStatusIconStyle and P.ParseUnitStatusIconStyle(normalized))
        or (P.ParseUnitStatusIndicatorDetail and P.ParseUnitStatusIndicatorDetail(normalized))
        or ParseUnitStatusIndicatorMove(normalized)
end

function A._ParsePipelineFallback(normalized, raw, ctx)
    return A._ParseGroupAnchorTargetShortcut(normalized)
        or ParseCustomAnchorSet(normalized, raw)
        or ParseCustomAnchorWorkflow(normalized)
        or ParseCustomAnchorClear(normalized)
        or ParseReset(normalized)
        or ParseOpen(normalized, raw)
        or ParseFontColorAction(normalized, raw)
        or ParseRegistryAlias(normalized, raw)
        or ParseSetting(normalized, ctx)
end

function A.ParseSimpleChange(text)
    local raw = Trim(text)
    local normalized = Normalize(raw)
    local ctx = A.GetContext and A.GetContext() or {}
    if normalized == "" then return nil end
    local parsed = (P.ParseExactRegistryKeyShortcut and P.ParseExactRegistryKeyShortcut(normalized, raw))
        or (P.ParseRegistryExactAliasShortcut and P.ParseRegistryExactAliasShortcut(normalized, raw))
        or (A._ParseTextLayerShortcut and A._ParseTextLayerShortcut(normalized))
        or (A._ParseTextSlotDropdownShortcut and A._ParseTextSlotDropdownShortcut(normalized))
        or (A._ParseTextDetailExactOffset and A._ParseTextDetailExactOffset(normalized))
        or (A._ParseGroupOpacityShortcut and A._ParseGroupOpacityShortcut(normalized))
        or (ParseUnitOpacityShortcut and ParseUnitOpacityShortcut(normalized))
        or ParseScopedFontTextColorShortcut(normalized, raw)
        or ParseFontColorAction(normalized, raw)
        or ParseColorAction(normalized)
        or ParseRegistryAlias(normalized, raw)
        or ParseSetting(normalized, ctx)
    if parsed then
        parsed.raw = raw
        parsed.normalized = normalized
    end
    return parsed
end

function A.Parse(text)
    local raw = Trim(text)
    local normalized = Normalize(raw)
    local ctx = A.GetContext and A.GetContext() or {}
    if normalized == "" then return { kind = "empty" } end
    local exactKeyParsed = (P.ParseExactRegistryKeyShortcut and P.ParseExactRegistryKeyShortcut(normalized, raw))
        or (P.ParseExactActionKeyShortcut and P.ParseExactActionKeyShortcut(normalized, raw))
        or (P.ParseRegistryActionAliasShortcut and P.ParseRegistryActionAliasShortcut(normalized, raw))
    if exactKeyParsed then
        exactKeyParsed.raw = raw
        exactKeyParsed.normalized = normalized
        return exactKeyParsed
    end
    local broadHumanAnchor = P.ParseBroadHumanAnchorTargetAnswer and P.ParseBroadHumanAnchorTargetAnswer(normalized, raw)
    if broadHumanAnchor then
        broadHumanAnchor.raw = raw
        broadHumanAnchor.normalized = normalized
        return broadHumanAnchor
    end
    local historyAction = A._ParseMenuHistoryAction(normalized)
    if historyAction then
        historyAction.raw = raw
        historyAction.normalized = normalized
        return historyAction
    end
    local hasEditModeContext = ContainsAny(normalized, {
        "edit mode", "editmode", "msuf edit mode", "bearbeitungsmodus", "frame edit mode",
    })
    if not hasEditModeContext and ContainsAny(normalized, {
        "undo", "undo that", "undo this", "undo last", "undo last change",
        "revert", "revert that", "revert this", "revert last", "revert last change",
        "rollback", "roll back", "roll back that", "roll back last change",
        "take it back", "take that back", "back out that change", "restore previous value",
        "put it back", "put that back", "make it like before",
        "rueckgaengig", "rueckgaengig machen", "mach das rueckgaengig", "das rueckgaengig machen",
        "zuruecknehmen", "nimm das zurueck", "mach das zurueck", "wieder zurueck",
    }) then
        return { kind = "undo" }
    end
    if not hasEditModeContext and ContainsAny(normalized, {
        "redo", "redo last", "redo that", "redo this", "reapply", "reapply that",
        "apply it again", "do it again", "repeat undo", "wiederholen", "erneut anwenden",
    }) then
        return { kind = "redo" }
    end
    local lookupQuestion = P.ParseLookupQuestion and P.ParseLookupQuestion(normalized, raw)
    if lookupQuestion then
        lookupQuestion.raw = raw
        lookupQuestion.normalized = normalized
        return lookupQuestion
    end
    local parsed = A._ParsePipelineWorkflow(normalized, raw, ctx)
    if A and type(A.MaybeYield) == "function" then A.MaybeYield() end
    if not parsed then parsed = A._ParsePipelineGeometry(normalized, raw) end
    if A and type(A.MaybeYield) == "function" then A.MaybeYield() end
    if not parsed then parsed = A._ParsePipelineFeature(normalized, raw, ctx) end
    if A and type(A.MaybeYield) == "function" then A.MaybeYield() end
    local parsedByEarlyCompound = false
    if not parsed and P.ParseCompound then
        parsed = P.ParseCompound(normalized, raw, nil)
        parsedByEarlyCompound = parsed ~= nil
    end
    if A and type(A.MaybeYield) == "function" then A.MaybeYield() end
    if not parsed then parsed = A._ParsePipelineFallback(normalized, raw, ctx) end
    if A and type(A.MaybeYield) == "function" then A.MaybeYield() end
    if not parsedByEarlyCompound and not (parsed and parsed.compoundComplete == true) then
        local compound = P.ParseCompound and P.ParseCompound(normalized, raw, parsed)
        if compound then parsed = compound end
    end
    if parsed then
        parsed.raw = raw
        parsed.normalized = normalized
        return parsed
    end
    if P.ParseUnsupportedAuraCommand then
        local auraUnsupported = P.ParseUnsupportedAuraCommand(normalized)
        if auraUnsupported then
            auraUnsupported.raw = raw
            auraUnsupported.normalized = normalized
            return auraUnsupported
        end
    end
    return {
        kind = "unknown",
        raw = raw,
        normalized = normalized,
        text = "I do not know that setting yet.",
        status = "failed",
    }
end
