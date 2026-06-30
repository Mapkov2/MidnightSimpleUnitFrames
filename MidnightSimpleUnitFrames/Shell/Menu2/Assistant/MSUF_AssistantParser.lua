local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

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

local P = A.Parser or {}
A.Parser = P
local Trim = P.Trim
local Normalize = P.Normalize
local ContainsAny = P.ContainsAny
local ParseWorkflowLifecycle = P.ParseWorkflowLifecycle
local ParseProfileStagingState = P.ParseProfileStagingState
local ParseGroupCopyScopeState = P.ParseGroupCopyScopeState
local ParseUnitCopyScopeState = P.ParseUnitCopyScopeState
local ParseProfile = P.ParseProfile
local ParseGroupCopy = P.ParseGroupCopy
local ParseCopy = P.ParseCopy
local BuildContextReset = P.BuildContextReset
local ParseGroupSpellIndicatorAction = P.ParseGroupSpellIndicatorAction
local ParseGroupCornerIndicatorSetting = P.ParseGroupCornerIndicatorSetting
local ParseGroupCornerIndicatorReset = P.ParseGroupCornerIndicatorReset
local ParseGroupStatusIconReset = P.ParseGroupStatusIconReset
local ParseGroupStatusPreview = P.ParseGroupStatusPreview
local ParseUnitStatusIndicatorReset = P.ParseUnitStatusIndicatorReset
local ParseUnitStatusPreview = P.ParseUnitStatusPreview
local ParseUnitStatusIndicatorMove = P.ParseUnitStatusIndicatorMove
local ParseCustomAnchorWorkflow = P.ParseCustomAnchorWorkflow
local ParseCustomAnchorSet = P.ParseCustomAnchorSet
local ParseCustomAnchorClear = P.ParseCustomAnchorClear
local ParseReset = P.ParseReset
local ParseOpen = P.ParseOpen
local ParseDashboardPanelAction = P.ParseDashboardPanelAction
local ParseNavRailAction = P.ParseNavRailAction
local ParseMenuWindowAction = P.ParseMenuWindowAction
local ParseScopedFontTextColorShortcut = P.ParseScopedFontTextColorShortcut
local ParseRegistryAlias = P.ParseRegistryAlias
local ParseScopedOnlyOverride = P.ParseScopedOnlyOverride
local ParseFontColorAction = P.ParseFontColorAction
local ParseColorAction = P.ParseColorAction
local ParseDiagnostic = P.ParseDiagnostic
local ParseScopedHelp = P.ParseScopedHelp
local ParseSupportWorkflow = P.ParseSupportWorkflow
local ParsePresetWorkflow = P.ParsePresetWorkflow
local ParseScopedOverrideReset = P.ParseScopedOverrideReset
local ParseGameplayRootToggle = P.ParseGameplayRootToggle
local ParseGameplayAction = P.ParseGameplayAction
local ParseClassPowerRootToggle = P.ParseClassPowerRootToggle
local ParseClassPowerAction = P.ParseClassPowerAction
local ParseGlobalBarsAction = P.ParseGlobalBarsAction
local ParseDarkModeBrightnessShortcut = P.ParseDarkModeBrightnessShortcut
local ParseCastbarPreviewAction = P.ParseCastbarPreviewAction
local ParseCastbarGlobalDetail = P.ParseCastbarGlobalDetail
local ParseGuidedSetup = P.ParseGuidedSetup
local ParseGuidedSetupFollowup = P.ParseGuidedSetupFollowup
local ParseUnsupportedDetailShortcut = P.ParseUnsupportedDetailShortcut
local ParsePortraitDetailShortcut = P.ParsePortraitDetailShortcut
local ParseUnitDetailMove = P.ParseUnitDetailMove
local ParseGroupDetailMove = P.ParseGroupDetailMove
local ParseBorderThicknessShortcut = P.ParseBorderThicknessShortcut
local ParseUnitDetailOffsetShortcut = P.ParseUnitDetailOffsetShortcut
local ParseCastbarTextMoveShortcut = P.ParseCastbarTextMoveShortcut
local ParseUnitOpacityShortcut = P.ParseUnitOpacityShortcut
local ParseMenuSelectorState = P.ParseMenuSelectorState
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
                "set", "change", "make", "size", "count", "max", "maximum", "cap", "caps", "limit", "limits",
                "icon", "icons", "per row", "growth", "spacing", "gap", "x offset", "y offset", "layer", "z layer", "frame level",
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
                    summary = "Aura option fallback.",
                    text = "I don't see an MSUF aura option for that request yet. I can change aura icon size, caps/count, X/Y offsets, spacing, growth, layer, cooldown and stack text, filters, hidden aura lists, quick presets, and group aura copy when those options exist in MSUF. Aura areas I can't match will stay as they are.",
                }
            end
        end
    end
end
P.InitUnsupportedAuraCommand()

local function EarlyAuraShortcut(normalized)
    return (P.ParseAuraScopeOverrideShortcut and P.ParseAuraScopeOverrideShortcut(normalized))
        or (P.ParseAuraCooldownSwipeDirectionShortcut and P.ParseAuraCooldownSwipeDirectionShortcut(normalized))
        or (P.ParseAuraDebuffBorderModeShortcut and P.ParseAuraDebuffBorderModeShortcut(normalized))
end

local function CopyRequest(normalized)
    return ParseGroupCopy(normalized)
        or (P.ParseUnsupportedMixedCopy and P.ParseUnsupportedMixedCopy(normalized))
        or ParseCopy(normalized)
end

local function ExactTextDetailShortcut(normalized)
    return (A._ParseTextLayerShortcut and A._ParseTextLayerShortcut(normalized))
        or (A._ParseTextSlotDropdownShortcut and A._ParseTextSlotDropdownShortcut(normalized))
        or (A._ParseTextDetailExactOffset and A._ParseTextDetailExactOffset(normalized))
end

--- Pipeline order matters. Specific workflows and follow-up answers must win
--- before broad registry matching, otherwise "yes", copy/profile flows, and
--- exact assistant keys can be swallowed by generic setting aliases.
function A._ParsePipelineWorkflow(normalized, raw, ctx)
    local result = ParseGuidedSetupFollowup(normalized, ctx); if result then return result end
    result = A._ParseFollowupAnswer(normalized, ctx); if result then return result end
    result = BuildFollowup(normalized, ctx); if result then return result end
    result = BuildBooleanCorrection(normalized, ctx); if result then return result end
    result = P.ParseBroadHumanAnchorTargetAnswer and P.ParseBroadHumanAnchorTargetAnswer(normalized, raw); if result then return result end
    result = ParseWorkflowLifecycle(normalized); if result then return result end
    result = P.ParseProfileRepairShortcut and P.ParseProfileRepairShortcut(normalized); if result then return result end
    result = ParseGroupCornerIndicatorSetting and ParseGroupCornerIndicatorSetting(normalized, raw); if result then return result end
    result = ParseDiagnostic(normalized); if result then return result end
    result = CopyRequest(normalized); if result then return result end
    result = ParseProfileStagingState(normalized, raw); if result then return result end
    result = ParseProfile(normalized, raw); if result then return result end
    result = P.ParseBossFramePreviewShortcut and P.ParseBossFramePreviewShortcut(normalized); if result then return result end
    result = P.ParseExactRegistryKeyShortcut and P.ParseExactRegistryKeyShortcut(normalized, raw); if result then return result end
    result = P.ParseExactActionKeyShortcut and P.ParseExactActionKeyShortcut(normalized, raw); if result then return result end
    result = P.ParseRegistryActionAliasShortcut and P.ParseRegistryActionAliasShortcut(normalized, raw); if result then return result end
    result = P.ParseRegistryExactAliasShortcut and P.ParseRegistryExactAliasShortcut(normalized, raw); if result then return result end
    result = A._ParseClassPowerDetachedPlayerPowerShortcut and A._ParseClassPowerDetachedPlayerPowerShortcut(normalized, raw); if result then return result end
    result = ParseClassPowerRootToggle and ParseClassPowerRootToggle(normalized); if result then return result end
    result = A._ParseClassPowerWidthModeShortcut and A._ParseClassPowerWidthModeShortcut(normalized); if result then return result end
    result = A._ParseClassPowerVisibilityShortcut and A._ParseClassPowerVisibilityShortcut(normalized); if result then return result end
    result = A._ParseClassPowerAnchorShortcut and A._ParseClassPowerAnchorShortcut(normalized); if result then return result end
    result = A._ParseClassPowerPlacementShortcut and A._ParseClassPowerPlacementShortcut(normalized); if result then return result end
    result = A._ParseClassPowerDisplayStyleShortcut and A._ParseClassPowerDisplayStyleShortcut(normalized); if result then return result end
    result = A._ParseClassPowerFillDirectionShortcut and A._ParseClassPowerFillDirectionShortcut(normalized); if result then return result end
    result = A._ParseClassPowerTextSizeShortcut and A._ParseClassPowerTextSizeShortcut(normalized); if result then return result end
    result = A._ParseClassPowerSizeShortcut and A._ParseClassPowerSizeShortcut(normalized); if result then return result end
    result = A._ParseClassPowerSeparatorShortcut and A._ParseClassPowerSeparatorShortcut(normalized); if result then return result end
    result = A._ParseClassPowerGapShortcut and A._ParseClassPowerGapShortcut(normalized); if result then return result end
    result = A._ParseClassPowerBackgroundShortcut and A._ParseClassPowerBackgroundShortcut(normalized); if result then return result end
    result = A._ParseClassPowerMoveShortcut and A._ParseClassPowerMoveShortcut(normalized); if result then return result end
    result = ParseGameplayRootToggle(normalized); if result then return result end
    result = A._ParseGameplayBooleanShortcut(normalized); if result then return result end
    result = A._ParseGameplayAnchorShortcut(normalized); if result then return result end
    result = A._ParseGameplayNumberShortcut(normalized); if result then return result end
    result = A._ParseGameplayPositionPreset(normalized); if result then return result end
    result = A._ParseGameplayMoveShortcut(normalized); if result then return result end
    result = ParsePresetWorkflow(normalized); if result then return result end
    result = P.ParseNameShorteningShortcut and P.ParseNameShorteningShortcut(normalized, ctx); if result then return result end
    result = ParseGuidedSetup(normalized); if result then return result end
    result = ParseScopedHelp(normalized); if result then return result end
    result = P.ParseGroupPowerBarSizeShortcut and P.ParseGroupPowerBarSizeShortcut(normalized); if result then return result end
    result = P.ParsePowerBarSizeShortcut and P.ParsePowerBarSizeShortcut(normalized); if result then return result end
    result = P.ParseMiscRegistryShortcut(normalized, raw); if result then return result end
    result = ParseDashboardPanelAction(normalized); if result then return result end
    result = ParseNavRailAction(normalized); if result then return result end
    result = ParseSupportWorkflow(normalized); if result then return result end
    result = ParseMenuWindowAction(normalized); if result then return result end
    result = ParseScopedFontTextColorShortcut(normalized); if result then return result end
    result = ParseUnitCopyScopeState(normalized); if result then return result end
    return P.ParseDashboardScaleShortcut and P.ParseDashboardScaleShortcut(normalized)
end

--- Geometry commands often share words with visual feature commands ("move",
--- "size", "left", "right"). Keep exact/positional parsers before fallback
--- setting lookup so directional phrases stay actionable.
function A._ParsePipelineGeometry(normalized, raw)
    local result = P.ParseTextVisibilityShortcut and P.ParseTextVisibilityShortcut(normalized); if result then return result end
    result = A._ParseNameTextAnchorShortcut(normalized); if result then return result end
    result = A._ParseNameTextVerticalPlacementShortcut(normalized); if result then return result end
    result = A._ParseTextSlotValueMoveShortcut(normalized); if result then return result end
    result = A._ParseTextSlotOffsetShortcut(normalized); if result then return result end
    result = P.ParseHumanAnchorTarget and P.ParseHumanAnchorTarget(normalized, raw); if result then return result end
    result = P.ParseGroupScaleBreakpointShortcut and P.ParseGroupScaleBreakpointShortcut(normalized); if result then return result end
    result = P.ParseCastbarTextSizeShortcut and P.ParseCastbarTextSizeShortcut(normalized); if result then return result end
    result = P.ParseCastbarSizeShortcut and P.ParseCastbarSizeShortcut(normalized); if result then return result end
    result = P.ParseCastbarPlacementShortcut and P.ParseCastbarPlacementShortcut(normalized); if result then return result end
    result = P.ParseAuraCooldownSwipeDirectionShortcut and P.ParseAuraCooldownSwipeDirectionShortcut(normalized); if result then return result end
    result = P.ParseAuraDebuffBorderModeShortcut and P.ParseAuraDebuffBorderModeShortcut(normalized); if result then return result end
    result = P.AuraGeometryShortcut and P.AuraGeometryShortcut(normalized); if result then return result end
    result = P.ParseGroupPowerBarSizeShortcut and P.ParseGroupPowerBarSizeShortcut(normalized); if result then return result end
    result = P.ParsePowerBarSizeShortcut and P.ParsePowerBarSizeShortcut(normalized); if result then return result end
    result = A._ParseTextFontSizeShortcut(normalized); if result then return result end
    result = P.ParseGroupStatusIconDetail and P.ParseGroupStatusIconDetail(normalized); if result then return result end
    result = P.ParseUnitStatusIndicatorDetail and P.ParseUnitStatusIndicatorDetail(normalized); if result then return result end
    result = P.ParseUnitStatusIndicatorMove and P.ParseUnitStatusIndicatorMove(normalized); if result then return result end
    result = P.ParseFrameResizeShortcut and P.ParseFrameResizeShortcut(normalized); if result then return result end
    result = P.ParseUnitSizeMatchShortcut(normalized); if result then return result end
    result = P.ParseDetachedPowerBarMoveShortcut and P.ParseDetachedPowerBarMoveShortcut(normalized); if result then return result end
    result = P.ParseBossFrameSpacingShortcut and P.ParseBossFrameSpacingShortcut(normalized); if result then return result end
    result = P.ParsePairwiseFrameSpacingShortcut and P.ParsePairwiseFrameSpacingShortcut(normalized); if result then return result end
    result = P.ParseGroupFrameSpacingShortcut and P.ParseGroupFrameSpacingShortcut(normalized); if result then return result end
    result = ParseUnitDetailMove(normalized); if result then return result end
    result = ParseGroupDetailMove(normalized); if result then return result end
    result = P.ParseGroupFrameRootMove and P.ParseGroupFrameRootMove(normalized); if result then return result end
    result = P.ParseUnitFrameRootMove and P.ParseUnitFrameRootMove(normalized); if result then return result end
    result = P.ParseGenericOffsetMove(normalized); if result then return result end
    result = ParseUnsupportedDetailShortcut(normalized); if result then return result end
    result = ParseScopedOnlyOverride(normalized, raw); if result then return result end
    result = A._ParseTextLayerShortcut(normalized); if result then return result end
    result = A._ParseTextSlotDropdownShortcut(normalized); if result then return result end
    result = ParseMenuSelectorState(normalized); if result then return result end
    result = ParsePortraitDetailShortcut(normalized); if result then return result end
    result = ParseBorderThicknessShortcut(normalized); if result then return result end
    result = A._ParseTextDetailExactOffset(normalized); if result then return result end
    result = ParseUnitDetailOffsetShortcut(normalized); if result then return result end
    result = ParseCastbarTextMoveShortcut(normalized); if result then return result end
    result = A._ParseGroupRangeFadeShortcut(normalized); if result then return result end
    result = A._ParseGroupOpacityShortcut(normalized); if result then return result end
    return ParseUnitOpacityShortcut(normalized)
end

--- Feature pipeline handles domain toggles and richer actions that are not
--- pure geometry. It runs after workflow/geometry in A.Parse, then falls back
--- to generic setting parsing if no domain-specific action matched.
function A._ParsePipelineFeature(normalized, raw, ctx)
    local result = ParseGameplayAction(normalized, raw); if result then return result end
    result = ParseClassPowerAction and ParseClassPowerAction(normalized); if result then return result end
    result = A._ParseClassPowerColorShortcut and A._ParseClassPowerColorShortcut(normalized, raw); if result then return result end
    result = ParseDarkModeBrightnessShortcut(normalized); if result then return result end
    result = ParseGlobalBarsAction(normalized); if result then return result end
    result = P.ParseNameShorteningShortcut and P.ParseNameShorteningShortcut(normalized, ctx); if result then return result end
    result = EarlyAuraShortcut(normalized); if result then return result end
    result = ParseCastbarGlobalDetail(normalized); if result then return result end
    result = P.ParseCastbarDirectionClarification and P.ParseCastbarDirectionClarification(normalized); if result then return result end
    result = ParseCastbarPreviewAction(normalized); if result then return result end
    result = ParseScopedOverrideReset(normalized); if result then return result end
    result = ParseGroupCopyScopeState(normalized); if result then return result end
    result = CopyRequest(normalized); if result then return result end
    result = BuildContextReset(normalized, ctx); if result then return result end
    result = ParseColorAction(normalized); if result then return result end
    result = ParseGroupSpellIndicatorAction(normalized, raw); if result then return result end
    result = ParseGroupCornerIndicatorSetting and ParseGroupCornerIndicatorSetting(normalized, raw); if result then return result end
    result = ParseGroupCornerIndicatorReset(normalized); if result then return result end
    result = ParseGroupStatusPreview(normalized); if result then return result end
    result = P.ParseGroupStatusIconDetail and P.ParseGroupStatusIconDetail(normalized); if result then return result end
    result = ParseUnitStatusPreview(normalized, ctx); if result then return result end
    result = P.ParseUnitStatusIconStyle and P.ParseUnitStatusIconStyle(normalized); if result then return result end
    result = ParseGroupStatusIconReset(normalized); if result then return result end
    result = ParseUnitStatusIndicatorReset(normalized, ctx); if result then return result end
    result = P.ParseUnitStatusIndicatorDetail and P.ParseUnitStatusIndicatorDetail(normalized); if result then return result end
    return ParseUnitStatusIndicatorMove(normalized)
end

function A._ParsePipelineFallback(normalized, raw, ctx)
    return A._ParseGroupAnchorTargetShortcut(normalized)
        or ParseCustomAnchorSet(normalized, raw)
        or ParseCustomAnchorWorkflow(normalized)
        or ParseCustomAnchorClear(normalized)
        or ParseReset(normalized)
        or ParseOpen(normalized, raw)
        or ParseFontColorAction(normalized, raw)
        or (P.ParseExactActionPhraseShortcut and P.ParseExactActionPhraseShortcut(normalized, raw))
        or ParseRegistryAlias(normalized, raw)
        or ParseSetting(normalized, ctx)
end

function A.ParseSimpleChange(text, ctxOverride)
    local raw = Trim(text)
    local normalized = Normalize(raw)
    local ctx = type(ctxOverride) == "table" and ctxOverride or (A.GetContext and A.GetContext() or {})
    if normalized == "" then return nil end
    local parsed = EarlyAuraShortcut(normalized)
        or (P.ParseExactRegistryKeyShortcut and P.ParseExactRegistryKeyShortcut(normalized, raw))
        or (P.ParseRegistryExactAliasShortcut and P.ParseRegistryExactAliasShortcut(normalized, raw))
        or ExactTextDetailShortcut(normalized)
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

function A.Parse(text, ctxOverride)
    local raw = Trim(text)
    local normalized = Normalize(raw)
    local ctx = type(ctxOverride) == "table" and ctxOverride or (A.GetContext and A.GetContext() or {})
    if normalized == "" then return { kind = "empty" } end
    local earlyAuraParsed = EarlyAuraShortcut(normalized)
    if earlyAuraParsed then
        earlyAuraParsed.raw = raw
        earlyAuraParsed.normalized = normalized
        return earlyAuraParsed
    end
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
    local guidedSetupFollowup = ParseGuidedSetupFollowup(normalized, ctx)
    if guidedSetupFollowup then
        guidedSetupFollowup.raw = raw
        guidedSetupFollowup.normalized = normalized
        return guidedSetupFollowup
    end
    local directFollowupAnswer = A._ParseFollowupAnswer and A._ParseFollowupAnswer(normalized, ctx)
    if directFollowupAnswer then
        directFollowupAnswer.raw = raw
        directFollowupAnswer.normalized = normalized
        return directFollowupAnswer
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
        text = "Which page and option do you want me to use? Example: 'set target cast bar height to 20'.",
        status = "failed",
    }
end

local function ParserContext(ctxOverride)
    if type(ctxOverride) == "table" then return ctxOverride end
    return A.GetContext and A.GetContext() or {}
end
A.ParserContext = ParserContext

A.ParsePlan = A.Parse
A.ParseForTest = A.Parse
MSUF.Public = MSUF.Public or {}
MSUF.Public.Assistant = MSUF.Public.Assistant or {}
MSUF.Public.Assistant.Parse = A.Parse
MSUF.Public.Assistant.ParseSimpleChange = A.ParseSimpleChange
