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
        or (P.ParseGroupPowerBarSizeShortcut and P.ParseGroupPowerBarSizeShortcut(normalized))
        or (P.ParsePowerBarSizeShortcut and P.ParsePowerBarSizeShortcut(normalized))
        or P.ParseMiscRegistryShortcut(normalized, raw)
        or ParseDashboardPanelAction(normalized)
        or ParseNavRailAction(normalized)
        or ParseSupportWorkflow(normalized)
        or ParseMenuWindowAction(normalized)
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
    return ParseGameplayAction(normalized, raw)
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
