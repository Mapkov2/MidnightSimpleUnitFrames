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
local DetectBoolean = P.DetectBoolean
local FirstNumber = P.FirstNumber
local HasPhrase = P.HasPhrase
local DetectUnits = P.DetectUnits
local DetectGroups = P.DetectGroups
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
local ParseUnitStatusSymbolRegistryShortcut = P.ParseUnitStatusSymbolRegistryShortcut
local ParseStatusIconTestModeRegistryShortcut = P.ParseStatusIconTestModeRegistryShortcut
local ParseUnitLoadConditionShortcut = P.ParseUnitLoadConditionShortcut
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
local ParseEditModeHUDControl = P.ParseEditModeHUDControl
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
local ParseBarOutlineHighlightShortcut = P.ParseBarOutlineHighlightShortcut
local ParseAbsorbBarShortcut = P.ParseAbsorbBarShortcut
local ParseBarBorderEnumShortcut = P.ParseBarBorderEnumShortcut
local ParseUnitDetailOffsetShortcut = P.ParseUnitDetailOffsetShortcut
local ParseCastbarTextMoveShortcut = P.ParseCastbarTextMoveShortcut
local ParseUnitOpacityShortcut = P.ParseUnitOpacityShortcut
local ParseMenuSelectorState = P.ParseMenuSelectorState
local BuildFollowup = P.BuildFollowup
local BuildBooleanCorrection = P.BuildBooleanCorrection
local ParseSetting = P.ParseSetting

local function LooksLikeAbsorbBarCommand(text)
    text = tostring(text or "")
    return text:find("absorb", 1, true)
        or text:find("heal prediction", 1, true)
        or text:find("incoming heal", 1, true)
end

local function LooksLikeBarBorderEnumCommand(text)
    text = tostring(text or "")
    return text:find("aggro", 1, true)
        or text:find("threat", 1, true)
        or text:find("dispel", 1, true)
        or text:find("dispellable", 1, true)
        or text:find("purge", 1, true)
        or text:find("purgeable", 1, true)
        or text:find("boss target", 1, true)
end

local function LooksLikeBarOutlineHighlightCommand(text)
    text = tostring(text or "")
    return text:find("outline", 1, true)
        or text:find("border", 1, true)
        or text:find("highlight", 1, true)
        or text:find("prio", 1, true)
        or text:find("priority", 1, true)
end

local function LooksLikeAlphaExcludeTextPortraitCommand(text)
    text = tostring(text or "")
    return text:find("keep text", 1, true)
        or text:find("keep portrait", 1, true)
        or text:find("exclude text", 1, true)
        or text:find("exclude portrait", 1, true)
        or text:find("names visible", 1, true)
        or text:find("name visible", 1, true)
        or text:find("text visible", 1, true)
end

local function ParseCastbarInterruptVisibilityShortcut(text)
    if not ContainsAny(text, { "show interrupt", "castbar interrupt", "cast bar interrupt", "show castbar interrupt", "show cast bar interrupt" }) then return nil end
    if ContainsAny(text, {
        "ready", "tracker", "focus kick", "focus interrupt", "indicator", "preview", "test",
        "color", "colors", "colour", "colours", "interruptible", "uninterruptible",
        "non interruptible", "noninterruptible", "kickable", "unkickable", "feedback",
        "shake", "strength", "size", "width", "height", "anchor", "offset",
    }) then return nil end
    local value = DetectBoolean(text)
    if value == nil then return nil end
    local units = DetectUnits(text)
    if #units == 0 then return nil end

    local changes = {}
    local Registry = A.Registry
    for i = 1, #units do
        local setting = Registry and Registry:GetSetting(tostring(units[i]) .. ".showInterrupt")
        if setting then changes[#changes + 1] = { setting = setting, value = value } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Cast Bar interrupt visibility",
        bulkSafe = #changes > 1,
        summary = "Changes per-unit Show Cast Bar Interrupt options.",
    }
end

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
                "stack", "cooldown", "duration", "duration bar", "timer bar", "pandemic",
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
            P.AURA_DISPEL_OVERLAY_TERMS = {
                "dispel overlay", "unitframe dispel overlay", "unit frame dispel overlay",
                "debuff overlay", "dispellable overlay", "dispellable debuff overlay",
                "dispel health overlay", "dispellable health overlay",
            }
        end
        if not P.AURA_GROUP_BLACKLIST_SCOPE_TERMS then
            P.AURA_GROUP_BLACKLIST_SCOPE_TERMS = {
                "group aura", "group auras", "group frame aura", "group frame auras",
                "party aura", "party auras", "party buff", "party buffs", "party debuff", "party debuffs",
                "raid aura", "raid auras", "raid buff", "raid buffs", "raid debuff", "raid debuffs",
                "mythic raid aura", "mythic raid auras", "mythic raid buff", "mythic raid buffs", "mythic raid debuff", "mythic raid debuffs",
            }
        end
        if not P.AURA_GROUP_BLACKLIST_TERMS then
            P.AURA_GROUP_BLACKLIST_TERMS = {
                "blacklist", "blacklisted", "whitelist", "whitelisted",
                "block", "blocked", "ignore", "ignored", "exclude", "excluded",
                "hide", "hidden", "allow", "unblacklist", "unblock", "unhide",
            }
        end
        if not P.AURA_GROUP_BLACKLIST_DETAIL_TERMS then
            P.AURA_GROUP_BLACKLIST_DETAIL_TERMS = {
                "spell", "spells", "spell id", "spellid", "spell link",
                "category", "categories", "public category", "public categories",
                "preset", "presets", "exact", "specific",
            }
        end
        if not P.AURA_UNIT_BLACKLIST_SCOPE_TERMS then
            P.AURA_UNIT_BLACKLIST_SCOPE_TERMS = {
                "aura blacklist", "blacklist aura", "blacklist spell", "hidden aura", "hidden auras",
                "player aura", "player auras", "target aura", "target auras",
                "focus aura", "focus auras", "boss aura", "boss auras",
                "shared aura", "shared auras", "unit aura", "unit auras",
            }
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
                local groupBlacklistScope = ContainsAny(text, P.AURA_GROUP_BLACKLIST_SCOPE_TERMS)
                local groupBlacklistIntent = ContainsAny(text, P.AURA_GROUP_BLACKLIST_TERMS)
                local groupBlacklistDetail = ContainsAny(text, P.AURA_GROUP_BLACKLIST_DETAIL_TERMS) or text:match("#?%d%d%d+") ~= nil
                if groupBlacklistScope and groupBlacklistIntent and (groupBlacklistDetail or text:find("blacklist", 1, true)) then
                    return {
                        kind = "unsupported",
                        status = "info",
                        summary = "Explains native group aura blacklist limitation.",
                        text = "Group aura exact spell/category blacklist data is legacy read-only in the native 12.1 backend, so I will not edit it as if it could affect live aura display. I can change live group aura filter tokens instead, such as All, Raid, or Dispellable, plus icon size, count, spacing, growth, layer, cooldown text, stack text, duration bars, and private aura options.",
                    }
                end
                local unitBlacklistScope = ContainsAny(text, P.AURA_UNIT_BLACKLIST_SCOPE_TERMS)
                if unitBlacklistScope and groupBlacklistIntent and (groupBlacklistDetail or text:find("blacklist", 1, true)) then
                    return {
                        kind = "unsupported",
                        status = "info",
                        summary = "Explains native unit aura blacklist limitation.",
                        text = "Exact aura blacklist edits are legacy read-only while the native 12.1 backend is active, so I will not edit them as if they could affect live aura display. I can change live Aura Filter options instead, such as player-only, raid, dispellable, crowd-control, exclusive filters, icon size, count, spacing, growth, cooldown text, stack text, and duration bars.",
                    }
                end
                if ContainsAny(text, { "target of target", "targettarget", "target target", "targets target", "focus target", "focustarget" })
                    and ContainsAny(text, { "aura", "auras", "buff", "buffs", "debuff", "debuffs" })
                then
                    return {
                        kind = "unsupported",
                        status = "info",
                        summary = "Explains dependent target aura limitation.",
                        text = "Target of Target and Focus Target do not expose Auras3 settings in MSUF, so I did not change anything. Their unit pages can still change frame visibility, size, health/text, cast bar, range fade, colors, and position. For aura changes, use Player, Target, Focus, Boss, or group aura scopes, such as 'hide target buffs' or 'show only dispellable raid debuffs'.",
                    }
                end
                if not ContainsAny(text, P.AURA_OUT_OF_SCOPE_TERMS)
                    and not (ContainsAny(text, P.AURA_BUFF_TERMS) and ContainsAny(text, P.AURA_BUFF_CONTEXT_TERMS))
                then
                    return nil
                end
                return {
                    kind = "unsupported",
                    status = "info",
                    summary = "Aura option fallback.",
                    text = "I don't see an MSUF aura option for that request yet. I can change aura icon size, caps/count, X/Y offsets, spacing, growth, layer, cooldown text, stack text, duration bars, live filter tokens, quick presets, private aura options, and group aura copy when those options exist in MSUF. Saved exact SpellID blacklist data can be listed, but it is read-only while the native 12.1 backend is active. Aura areas I can't match will stay as they are.",
                }
            end
        end
    end
end
P.InitUnsupportedAuraCommand()

local function EarlyAuraShortcut(normalized, raw)
    return (P.ParseAuraScopeOverrideShortcut and P.ParseAuraScopeOverrideShortcut(normalized))
        or (P.ParseAuraDirectSettingShortcut and P.ParseAuraDirectSettingShortcut(normalized, raw))
        or (P.ParseUnitAuraFilterBooleanShortcut and P.ParseUnitAuraFilterBooleanShortcut(normalized))
        or (P.ParseGroupAuraLiveFilterShortcut and P.ParseGroupAuraLiveFilterShortcut(normalized))
        or (P.ParseUnitAuraLiveFilterShortcut and P.ParseUnitAuraLiveFilterShortcut(normalized))
        or (P.ParseAuraCooldownSwipeDirectionShortcut and P.ParseAuraCooldownSwipeDirectionShortcut(normalized))
        or (P.ParseAuraDurationBarShortcut and P.ParseAuraDurationBarShortcut(normalized))
        or (P.ParseAuraDebuffBorderModeShortcut and P.ParseAuraDebuffBorderModeShortcut(normalized))
        or (P.AuraGeometryShortcut and P.AuraGeometryShortcut(normalized))
        or (P.ParseGroupAuraRootSettingShortcut and P.ParseGroupAuraRootSettingShortcut(normalized))
        or (P.ParseGroupAuraVisibilityShortcut and P.ParseGroupAuraVisibilityShortcut(normalized))
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

local GLOBAL_STATUS_TEXT_STATES = {
    {
        key = "showGhost",
        label = "Dead Text Shows Ghost Units",
        terms = { "dead text ghost units", "status text ghost units", "show ghost text", "ghost text", "ghost status text" },
    },
    {
        key = "showAFK",
        label = "Dead Text Shows AFK Units",
        terms = { "dead text afk", "status text afk", "show afk text", "afk text", "afk status text", "away text" },
    },
    {
        key = "showDND",
        label = "Dead Text Shows DND Units",
        terms = { "dead text dnd", "status text dnd", "show dnd text", "dnd text", "dnd status text" },
    },
    {
        key = "showDead",
        label = "Dead Text Shows Dead/Offline Units",
        terms = {
            "dead text dead units", "status text dead units", "show dead text for dead",
            "offline text", "offline status text", "disconnected text", "connection text",
        },
    },
}

local function ParseGlobalStatusTextStateShortcut(text)
    if ContainsAny(text, { "party", "raid", "mythic raid", "mythicraid", "group frame", "group frames" }) then return nil end
    local value = DetectBoolean and DetectBoolean(text) or nil
    if value == nil then return nil end
    for i = 1, #GLOBAL_STATUS_TEXT_STATES do
        local spec = GLOBAL_STATUS_TEXT_STATES[i]
        if ContainsAny(text, spec.terms) then
            local Registry = A.Registry
            local setting = Registry and Registry.GetSetting and Registry:GetSetting("general.statusIndicators." .. spec.key)
            return setting and {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = spec.label,
                summary = value and "Enables a global Dead Text runtime state." or "Disables a global Dead Text runtime state.",
            } or nil
        end
    end
    return nil
end

local function ParseClassPowerTextOffsetShortcut(text)
    if not ContainsAny(text, { "class power", "class powers", "class resource", "class resources", "combo point", "combo points" }) then return nil end
    if ContainsAny(text, { "player hp", "player health", "second hp", "duplicate hp" }) then return nil end
    if not ContainsAny(text, { "text", "number", "numbers" }) then return nil end
    local axis
    if ContainsAny(text, { "x offset", "offset x", "text x", "number x", "numbers x" }) or HasPhrase and HasPhrase(text, "x") then
        axis = "X"
    elseif ContainsAny(text, { "y offset", "offset y", "text y", "number y", "numbers y" }) or HasPhrase and HasPhrase(text, "y") then
        axis = "Y"
    end
    if not axis then return nil end

    local Registry = A.Registry
    local setting = Registry and Registry.GetSetting and Registry:GetSetting("bars.classPowerTextOffset" .. axis)
    if not setting then return nil end
    local relativeDelta = P.RelativeNumberDeltaForText and P.RelativeNumberDeltaForText(setting, text, 1) or nil
    local value
    if relativeDelta == nil then
        value = FirstNumber and FirstNumber(text) or nil
        if value == nil then return nil end
    end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = setting.label or ("Class Resource Text Offset " .. axis),
        summary = "Changes the Class Resource text X/Y offset.",
    }
end

local UNIT_ROOT_FRAME_DETAIL_BLOCKERS = {
    "name", "names", "text", "hp", "health", "power", "mana", "castbar", "cast bar",
    "buff", "buffs", "debuff", "debuffs", "aura", "auras", "icon", "icons",
    "indicator", "indicators", "portrait", "range fade", "alpha", "opacity",
    "width", "height", "size", "anchor", "position", "move", "offset",
    "load condition", "load conditions", "visibility condition", "when", "while",
    "in group", "grouped", "solo", "mounted", "vehicle", "instance", "combat",
    "resting", "stealth", "housing",
}

local function UnitRootVisibilityValue(text)
    if ContainsAny(text, { "hide", "hidden", "disable", "disabled", "turn off", "off", "not show", "dont show", "do not show" }) then return false end
    if ContainsAny(text, { "show", "enable", "enabled", "turn on", "on" }) then return true end
    return DetectBoolean and DetectBoolean(text) or nil
end

local function UnitRootLabel(unit)
    if A and type(A.DisplayUnitLabel) == "function" then return A.DisplayUnitLabel(unit) end
    if unit == "targettarget" then return "Target of Target" end
    if unit == "focustarget" then return "Focus Target" end
    return tostring(unit or "Unit"):gsub("^%l", string.upper)
end

local function ParseUnitRootVisibilityShortcut(text)
    if not ContainsAny(text, { "frame", "frames", "unit frame", "unit frames", "unitframe", "unitframes" }) then return nil end
    if ContainsAny(text, UNIT_ROOT_FRAME_DETAIL_BLOCKERS) then return nil end
    local value = UnitRootVisibilityValue(text)
    if value == nil then return nil end
    local units = DetectUnits and DetectUnits(text) or {}
    if #units == 0 then return nil end
    local Registry = A.Registry
    local changes = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        local setting = Registry and Registry.GetSetting and Registry:GetSetting(unit .. ".enabled")
        if setting then changes[#changes + 1] = { setting = setting, value = value } end
    end
    if #changes == 0 then return nil end
    local label = #changes == 1 and (UnitRootLabel(units[1]) .. " Frame Enabled") or "Unit Frames Enabled"
    return {
        kind = "changes",
        changes = changes,
        label = label,
        bulkSafe = #changes > 1,
        summary = "Changes root Unit Frame visibility.",
    }
end

local function ParseGroupDebuffStripeShortcut(text, raw)
    if not ContainsAny(text, { "debuff stripe", "debuff stripes", "stripe edge", "stripe opacity", "stripe alpha", "stripe height" }) then return nil end
    if ContainsAny(text, { "color", "colors", "colour", "colours", "farbe", "farben" }) then return nil end

    local groups = DetectGroups and DetectGroups(text) or {}
    if #groups == 0 then return nil end

    local attr
    local title = "Group Debuff Stripe"
    if ContainsAny(text, { "edge", "position", "top", "bottom", "upper", "lower" }) then
        attr = "debuffStripeEdge"
        title = "Debuff Stripe Edge"
    elseif ContainsAny(text, { "opacity", "alpha", "transparency", "transparent" }) then
        attr = "debuffStripeAlpha"
        title = "Debuff Stripe Opacity"
    elseif ContainsAny(text, { "height", "size", "thickness", "tall" }) then
        attr = "debuffStripeHeight"
        title = "Debuff Stripe Height"
    else
        attr = "debuffStripeEnabled"
    end

    local changes = {}
    local Registry = A.Registry
    for i = 1, #groups do
        local setting = Registry and Registry:GetSetting("gf_" .. tostring(groups[i]) .. "." .. attr)
        if setting then
            local value
            if setting.type == "boolean" then
                value = DetectBoolean(text)
            elseif setting.type == "enum" then
                value = P.EnumValueForText and P.EnumValueForText(setting, text) or nil
            elseif setting.type == "number" then
                value = A._NumberValueForText and A._NumberValueForText(setting, text) or FirstNumber(text)
                if setting.percent == true and value and value > 1 then value = value / 100 end
            end
            if value ~= nil then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end

    if #changes == 0 then return nil end
    local concrete = true
    if P.GroupShortcutScopes then
        local scopes, scopedConcrete = P.GroupShortcutScopes(text)
        concrete = scopedConcrete
        if type(scopes) ~= "table" or #scopes == 0 then concrete = true end
    end
    if P.GroupShortcutResponse then
        return P.GroupShortcutResponse(text, changes, concrete, title, "Changes Group Frame Debuff Stripe settings.")
    end
    return {
        kind = "changes",
        changes = changes,
        label = title,
        bulkSafe = #changes > 1,
        summary = "Changes Group Frame Debuff Stripe settings.",
    }
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
    result = ParseGroupCornerIndicatorReset and ParseGroupCornerIndicatorReset(normalized); if result then return result end
    result = ParseGroupCornerIndicatorSetting and ParseGroupCornerIndicatorSetting(normalized, raw); if result then return result end
    result = ParseDiagnostic(normalized); if result then return result end
    result = CopyRequest(normalized); if result then return result end
    result = ParseProfileStagingState(normalized, raw); if result then return result end
    result = ParseProfile(normalized, raw); if result then return result end
    result = P.ParseBossFramePreviewShortcut and P.ParseBossFramePreviewShortcut(normalized); if result then return result end
    result = P.ParseGroupStatusIconDetail and P.ParseGroupStatusIconDetail(normalized); if result then return result end
    result = P.ParseExactRegistryKeyShortcut and P.ParseExactRegistryKeyShortcut(normalized, raw); if result then return result end
    result = P.ParseExactActionKeyShortcut and P.ParseExactActionKeyShortcut(normalized, raw); if result then return result end
    result = P.ParseRegistryActionAliasShortcut and P.ParseRegistryActionAliasShortcut(normalized, raw); if result then return result end
    result = P.ParseRegistryPriorityShortcut and P.ParseRegistryPriorityShortcut(normalized, raw); if result then return result end
    result = P.ParseRegistryExactAliasShortcut and P.ParseRegistryExactAliasShortcut(normalized, raw); if result then return result end
    result = A._ParseClassPowerDetachedPlayerPowerShortcut and A._ParseClassPowerDetachedPlayerPowerShortcut(normalized, raw); if result then return result end
    result = ParseClassPowerRootToggle and ParseClassPowerRootToggle(normalized); if result then return result end
    result = A._ParseClassPowerWidthModeShortcut and A._ParseClassPowerWidthModeShortcut(normalized); if result then return result end
    result = A._ParseClassPowerVisibilityShortcut and A._ParseClassPowerVisibilityShortcut(normalized); if result then return result end
    result = A._ParseClassPowerAnchorShortcut and A._ParseClassPowerAnchorShortcut(normalized); if result then return result end
    result = A._ParseClassPowerPlacementShortcut and A._ParseClassPowerPlacementShortcut(normalized); if result then return result end
    result = A._ParseClassPowerDisplayStyleShortcut and A._ParseClassPowerDisplayStyleShortcut(normalized); if result then return result end
    result = A._ParseClassPowerFillDirectionShortcut and A._ParseClassPowerFillDirectionShortcut(normalized); if result then return result end
    result = P.ParseGroupFrameFillDirectionShortcut and P.ParseGroupFrameFillDirectionShortcut(normalized); if result then return result end
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
    result = ParseSupportWorkflow(normalized); if result then return result end
    result = ParseDashboardPanelAction(normalized); if result then return result end
    result = ParseNavRailAction(normalized); if result then return result end
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
    result = A._ParseTextSlotDropdownValueShortcut(normalized); if result then return result end
    result = A._ParseHPTextOptionShortcut(normalized); if result then return result end
    result = A._ParsePowerTextOptionShortcut(normalized); if result then return result end
    result = A._ParseTextAreaOffsetShortcut(normalized); if result then return result end
    result = A._ParseTextSlotValueMoveShortcut(normalized); if result then return result end
    result = A._ParseTextSlotOffsetShortcut(normalized); if result then return result end
    result = P.ParseHumanAnchorTarget and P.ParseHumanAnchorTarget(normalized, raw); if result then return result end
    result = P.ParseGroupScaleBreakpointShortcut and P.ParseGroupScaleBreakpointShortcut(normalized); if result then return result end
    result = P.ParseCastbarTextSizeShortcut and P.ParseCastbarTextSizeShortcut(normalized); if result then return result end
    result = P.ParseCastbarSizeShortcut and P.ParseCastbarSizeShortcut(normalized); if result then return result end
    result = P.ParseCastbarPlacementShortcut and P.ParseCastbarPlacementShortcut(normalized); if result then return result end
    result = P.ParseGroupAuraLiveFilterShortcut and P.ParseGroupAuraLiveFilterShortcut(normalized); if result then return result end
    result = P.ParseUnitAuraLiveFilterShortcut and P.ParseUnitAuraLiveFilterShortcut(normalized); if result then return result end
    result = P.ParseAuraCooldownSwipeDirectionShortcut and P.ParseAuraCooldownSwipeDirectionShortcut(normalized); if result then return result end
    result = P.ParseAuraDurationBarShortcut and P.ParseAuraDurationBarShortcut(normalized); if result then return result end
    result = P.ParseAuraDebuffBorderModeShortcut and P.ParseAuraDebuffBorderModeShortcut(normalized); if result then return result end
    result = P.AuraGeometryShortcut and P.AuraGeometryShortcut(normalized); if result then return result end
    result = P.ParseGroupPowerBarSizeShortcut and P.ParseGroupPowerBarSizeShortcut(normalized); if result then return result end
    result = P.ParsePowerBarSizeShortcut and P.ParsePowerBarSizeShortcut(normalized); if result then return result end
    result = A._ParseTextFontSizeShortcut(normalized); if result then return result end
    result = ParseUnitStatusSymbolRegistryShortcut and ParseUnitStatusSymbolRegistryShortcut(normalized); if result then return result end
    result = ParseStatusIconTestModeRegistryShortcut and ParseStatusIconTestModeRegistryShortcut(normalized); if result then return result end
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
    if LooksLikeAbsorbBarCommand(normalized) then
        result = ParseAbsorbBarShortcut and ParseAbsorbBarShortcut(normalized); if result then return result end
    end
    if LooksLikeBarBorderEnumCommand(normalized) then
        result = ParseBarBorderEnumShortcut and ParseBarBorderEnumShortcut(normalized); if result then return result end
    end
    if LooksLikeBarOutlineHighlightCommand(normalized) then
        result = ParseBarOutlineHighlightShortcut and ParseBarOutlineHighlightShortcut(normalized); if result then return result end
    end
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
    result = A._ParsePowerColorShortcut and A._ParsePowerColorShortcut(normalized, raw); if result then return result end
    result = ParseDarkModeBrightnessShortcut(normalized); if result then return result end
    result = ParseGlobalBarsAction(normalized); if result then return result end
    result = P.ParseNameShorteningShortcut and P.ParseNameShorteningShortcut(normalized, ctx); if result then return result end
    result = EarlyAuraShortcut(normalized, raw); if result then return result end
    result = ParseCastbarGlobalDetail(normalized); if result then return result end
    result = P.ParseCastbarDirectionClarification and P.ParseCastbarDirectionClarification(normalized); if result then return result end
    result = ParseCastbarPreviewAction(normalized); if result then return result end
    result = ParseScopedOverrideReset(normalized); if result then return result end
    result = ParseGroupCopyScopeState(normalized); if result then return result end
    result = CopyRequest(normalized); if result then return result end
    result = BuildContextReset(normalized, ctx); if result then return result end
    result = ParseColorAction(normalized); if result then return result end
    result = ParseGroupSpellIndicatorAction(normalized, raw); if result then return result end
    result = ParseGroupCornerIndicatorReset(normalized); if result then return result end
    result = ParseGroupCornerIndicatorSetting and ParseGroupCornerIndicatorSetting(normalized, raw); if result then return result end
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
    local parsed = EarlyAuraShortcut(normalized, raw)
        or (P.ParseTextVisibilityShortcut and P.ParseTextVisibilityShortcut(normalized))
        or (A._ParseNameTextAnchorShortcut and A._ParseNameTextAnchorShortcut(normalized))
        or (A._ParseNameTextOffsetShortcut and A._ParseNameTextOffsetShortcut(normalized))
        or (A._ParseNameTextVerticalPlacementShortcut and A._ParseNameTextVerticalPlacementShortcut(normalized))
        or (A._ParseTextSlotDropdownValueShortcut and A._ParseTextSlotDropdownValueShortcut(normalized))
        or (A._ParseHPTextOptionShortcut and A._ParseHPTextOptionShortcut(normalized))
        or (A._ParsePowerTextOptionShortcut and A._ParsePowerTextOptionShortcut(normalized))
        or (A._ParseTextAreaOffsetShortcut and A._ParseTextAreaOffsetShortcut(normalized))
        or (A._ParseTextSlotValueMoveShortcut and A._ParseTextSlotValueMoveShortcut(normalized))
        or (A._ParseTextSlotOffsetShortcut and A._ParseTextSlotOffsetShortcut(normalized))
        or (A._ParseTextFontSizeShortcut and A._ParseTextFontSizeShortcut(normalized))
        or ParseCustomAnchorSet(normalized, raw)
        or ParsePortraitDetailShortcut(normalized)
        or (LooksLikeAbsorbBarCommand(normalized) and ParseAbsorbBarShortcut and ParseAbsorbBarShortcut(normalized, raw))
        or (LooksLikeBarBorderEnumCommand(normalized) and ParseBarBorderEnumShortcut and ParseBarBorderEnumShortcut(normalized))
        or (LooksLikeBarOutlineHighlightCommand(normalized) and ParseBarOutlineHighlightShortcut and ParseBarOutlineHighlightShortcut(normalized))
        or (P.ParsePowerBarSizeShortcut and P.ParsePowerBarSizeShortcut(normalized))
        or (P.ParseUnitPowerBarBorderThicknessShortcut and P.ParseUnitPowerBarBorderThicknessShortcut(normalized))
        or (P.ParseUnitPowerBarBooleanShortcut and P.ParseUnitPowerBarBooleanShortcut(normalized))
        or (P.ParsePlayerPowerBarShapeShortcut and P.ParsePlayerPowerBarShapeShortcut(normalized))
        or (P.ParsePlayerPowerOrbSizeShortcut and P.ParsePlayerPowerOrbSizeShortcut(normalized))
        or (A._ParseClassPowerDetachedPlayerPowerShortcut and A._ParseClassPowerDetachedPlayerPowerShortcut(normalized, raw))
        or (P.ParseDetachedPowerBarRegistryShortcut and P.ParseDetachedPowerBarRegistryShortcut(normalized, raw))
        or (ParseUnitStatusSymbolRegistryShortcut and ParseUnitStatusSymbolRegistryShortcut(normalized))
        or (ParseStatusIconTestModeRegistryShortcut and ParseStatusIconTestModeRegistryShortcut(normalized))
        or (P.ParseUnitStatusIndicatorDetail and P.ParseUnitStatusIndicatorDetail(normalized))
        or (ParseUnitLoadConditionShortcut and ParseUnitLoadConditionShortcut(normalized))
        or (A._ParseTextLayerShortcut and A._ParseTextLayerShortcut(normalized))
        or (P.ParseFrameSizeExactShortcut and P.ParseFrameSizeExactShortcut(normalized))
        or (P.ParseUnitFrameRootMove and P.ParseUnitFrameRootMove(normalized))
        or (P.ParseGroupFrameRootMove and P.ParseGroupFrameRootMove(normalized))
        or (P.ParseUnitRangeFadeShortcut and P.ParseUnitRangeFadeShortcut(normalized))
        or (A._ParseGroupRangeFadeShortcut and A._ParseGroupRangeFadeShortcut(normalized))
        or (P.ParseUnitHealthColorSchemeShortcut and P.ParseUnitHealthColorSchemeShortcut(normalized))
        or (LooksLikeAlphaExcludeTextPortraitCommand(normalized) and P.ParseAlphaExcludeTextPortraitShortcut and P.ParseAlphaExcludeTextPortraitShortcut(normalized))
        or ParseCastbarInterruptVisibilityShortcut(normalized)
        or ParseGroupDebuffStripeShortcut(normalized, raw)
        or (P.ParseUnitAnchorTargetShortcut and P.ParseUnitAnchorTargetShortcut(normalized))
        or (P.ParseUnitAnchorPointShortcut and P.ParseUnitAnchorPointShortcut(normalized))
        or (P.ParseExactRegistryKeyShortcut and P.ParseExactRegistryKeyShortcut(normalized, raw))
        or (P.ParseRegistryPriorityShortcut and P.ParseRegistryPriorityShortcut(normalized, raw))
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
    local actionExplainParsed = P.ParseRegistryActionExplainShortcut and P.ParseRegistryActionExplainShortcut(normalized, raw)
    if actionExplainParsed then
        actionExplainParsed.raw = raw
        actionExplainParsed.normalized = normalized
        return actionExplainParsed
    end
    local editModeControlParsed = ParseEditModeHUDControl and ParseEditModeHUDControl(normalized)
    if editModeControlParsed then
        editModeControlParsed.raw = raw
        editModeControlParsed.normalized = normalized
        return editModeControlParsed
    end
    local customAnchorActionParsed
    if ContainsAny(normalized, { "custom anchor picker", "anchor frame picker", "clear custom anchor", "remove custom anchor", "reset custom anchor" })
        or (ContainsAny(normalized, { "custom anchor", "custom anchor frame" })
            and ContainsAny(normalized, { "clear", "remove", "reset", "restore", "default", "defaults", "zuruecksetzen" }))
    then
        customAnchorActionParsed = ParseCustomAnchorWorkflow(normalized) or ParseCustomAnchorClear(normalized)
        if customAnchorActionParsed then
            customAnchorActionParsed.raw = raw
            customAnchorActionParsed.normalized = normalized
            return customAnchorActionParsed
        end
    end
    if ContainsAny(normalized, {
        "target of target inline text", "target target inline text", "target inline text",
        "target of target inline name", "target of target name inline", "tot inline text",
        "tot inline name", "target inline color", "target of target inline color", "tot inline color",
        "target inline separator", "target of target inline separator", "tot inline separator",
        "target inline custom separator", "target of target inline custom separator", "tot inline custom separator",
    }) then
        local setting
        local value
        if ContainsAny(normalized, { "inline color", "inline colour" }) then
            setting = A.Registry and A.Registry:GetSetting("targettarget.totInlineColorMode")
            value = setting and P.EnumValueForText and P.EnumValueForText(setting, normalized) or nil
        elseif ContainsAny(normalized, { "custom separator", "custom seperator", "custom delimiter" }) then
            setting = A.Registry and A.Registry:GetSetting("targettarget.totInlineCustomSeparator")
            value = P.RawAfterLastConnector and P.RawAfterLastConnector(raw, { " to ", " as ", " value ", " separator " }) or nil
            value = value or tostring(raw or ""):match("[Tt][Oo]%s+(.+)$")
        elseif ContainsAny(normalized, { "separator", "seperator", "delimiter" }) then
            setting = A.Registry and A.Registry:GetSetting("targettarget.totInlineSeparator")
            value = setting and P.EnumValueForText and P.EnumValueForText(setting, normalized) or nil
            value = value or (P.RawAfterLastConnector and P.RawAfterLastConnector(raw, { " to ", " as ", " value " }) or nil)
        else
            setting = A.Registry and A.Registry:GetSetting("targettarget.showToTInTargetName")
            value = DetectBoolean(normalized)
            if value == nil and ContainsAny(normalized, { "show", "display", "enable", "turn on", "on" }) then value = true end
            if value == nil and ContainsAny(normalized, { "hide", "disable", "turn off", "off" }) then value = false end
        end
        if setting and value ~= nil then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = setting.label or "Target Target Inline Text",
                summary = "Changes Target of Target inline text settings.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if ContainsAny(normalized, { "boss", "boss frame", "boss frames", "bossframe", "bossframes" })
        and ContainsAny(normalized, { "spacing", "frame spacing", "gap between frames", "distance between frames", "frame layout", "layout" })
        and not ContainsAny(normalized, { "aura", "auras", "buff", "debuff", "castbar", "cast bar" })
    then
        local setting
        local value
        if ContainsAny(normalized, { "frame layout", "layout" }) then
            setting = A.Registry and A.Registry:GetSetting("boss.bossLayoutMode")
            value = setting and P.EnumValueForText and P.EnumValueForText(setting, normalized) or nil
        else
            setting = A.Registry and A.Registry:GetSetting("boss.spacing")
            value = FirstNumber(normalized)
        end
        if setting and value ~= nil then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = setting.label or "Boss Layout",
                summary = "Changes Boss frame layout settings.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if ContainsAny(normalized, { "castbar", "cast bar", "zauberleiste" })
        and ContainsAny(normalized, { "move", "nudge", "shift" })
        and ContainsAny(normalized, { "left", "right", "up", "down", "links", "rechts", "oben", "unten" })
    then
        local castbarUnits = DetectUnits(normalized)
        local castbarOffsetKeys = {
            player = { x = "general.castbarPlayerOffsetX", y = "general.castbarPlayerOffsetY" },
            target = { x = "general.castbarTargetOffsetX", y = "general.castbarTargetOffsetY" },
            focus = { x = "general.castbarFocusOffsetX", y = "general.castbarFocusOffsetY" },
        }
        local unit
        for i = 1, #castbarUnits do
            if castbarOffsetKeys[castbarUnits[i]] then
                unit = castbarUnits[i]
                break
            end
        end
        local direction
        if normalized:find("to left", 1, true) or normalized:find("to the left", 1, true) or normalized:find("nach links", 1, true) then
            direction = "left"
        elseif normalized:find("to right", 1, true) or normalized:find("to the right", 1, true) or normalized:find("nach rechts", 1, true) then
            direction = "right"
        elseif normalized:find("up", 1, true) or normalized:find("oben", 1, true) then
            direction = "up"
        elseif normalized:find("down", 1, true) or normalized:find("unten", 1, true) then
            direction = "down"
        elseif normalized:find("left", 1, true) or normalized:find("links", 1, true) then
            direction = "left"
        elseif normalized:find("right", 1, true) or normalized:find("rechts", 1, true) then
            direction = "right"
        end
        local axis = (direction == "left" or direction == "right") and "x" or ((direction == "up" or direction == "down") and "y" or nil)
        local key = unit and axis and castbarOffsetKeys[unit] and castbarOffsetKeys[unit][axis]
        local setting = key and A.Registry and A.Registry:GetSetting(key)
        if setting then
            local amount = FirstNumber(normalized) or 10
            if direction == "left" or direction == "down" then amount = -amount end
            return {
                kind = "changes",
                changes = { { setting = setting, relativeDelta = amount, direction = direction } },
                label = "Move position offset",
                summary = "Moves the matching Cast Bar X/Y offset option.",
                raw = raw,
                normalized = normalized,
            }
        end
        local earlyCastbarMoveParsed = P.ParseGenericOffsetMove and P.ParseGenericOffsetMove(normalized)
        if earlyCastbarMoveParsed then
            earlyCastbarMoveParsed.raw = raw
            earlyCastbarMoveParsed.normalized = normalized
            return earlyCastbarMoveParsed
        end
    end
    if ContainsAny(normalized, { "castbar", "cast bar", "zauberleiste" })
        and ContainsAny(normalized, { "provider", "backend", "source", "renderer", "owner", "quelle", "besitzer" })
    then
        local setting = A.Registry and A.Registry:GetSetting("general.castbarPlayerBackend")
        local value = setting and P.EnumValueForText and P.EnumValueForText(setting, normalized) or nil
        if setting and value ~= nil then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = setting.label or "Player Cast Bar Provider",
                summary = "Changes the Player Cast Bar provider.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if ContainsAny(normalized, { "castbar", "cast bar", "zauberleiste" })
        and ContainsAny(normalized, { "focus kick", "focus interrupt tracker", "fokus kick", "fokus interrupt tracker" })
        and not ContainsAny(normalized, { "ready", "interrupt ready", "kick ready", "color", "colour" })
    then
        local key
        local value
        if ContainsAny(normalized, { "preview", "on-screen preview", "onscreen preview", "vorschau" }) then
            key = "runtime.focusKickPreview"
            value = DetectBoolean(normalized)
            if value == nil then value = true end
        elseif ContainsAny(normalized, { "width", "breite" }) then
            key = "general.focusKickIconWidth"
            value = FirstNumber(normalized)
        elseif ContainsAny(normalized, { "height", "hoehe" }) then
            key = "general.focusKickIconHeight"
            value = FirstNumber(normalized)
        elseif ContainsAny(normalized, { "text size", "font size", "schriftgroesse" }) then
            key = "general.focusKickTextSize"
            value = FirstNumber(normalized)
        elseif ContainsAny(normalized, { "x offset", "offset x", " x", "x ", "x versatz" }) then
            key = "general.focusKickIconOffsetX"
            value = FirstNumber(normalized)
        elseif ContainsAny(normalized, { "y offset", "offset y", " y", "y ", "y versatz" }) then
            key = "general.focusKickIconOffsetY"
            value = FirstNumber(normalized)
        else
            key = "general.enableFocusKickIcon"
            value = DetectBoolean(normalized)
            if value == nil then value = true end
        end
        local setting = key and A.Registry and A.Registry:GetSetting(key)
        if setting and value ~= nil then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = setting.label or "Focus Kick Tracker",
                summary = "Changes Focus Kick Tracker visibility, preview, size, or offset.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if ContainsAny(normalized, { "interrupt ready", "kick ready", "interrupt bereit" })
        and not ContainsAny(normalized, { "color", "colors", "colour", "colours", "farbe", "farben", "tint" })
    then
        local key
        local value
        if ContainsAny(normalized, { "auto size", "autosize", "automatic size", "auto-size" }) then
            key = "general.kickReadyAutoSize"
            value = DetectBoolean(normalized)
            if value == nil then value = true end
        elseif ContainsAny(normalized, { "style", "border", "box", "fill", "outline", "square", "unavailable fill" }) then
            key = "general.kickReadyStyle"
        elseif ContainsAny(normalized, { "anchor", "anchor point", "anchor position", "position dropdown" }) then
            key = "general.kickReadyAnchor"
        elseif ContainsAny(normalized, { "x offset", "offset x", " x", "x " }) then
            key = "general.kickReadyOffsetX"
            value = FirstNumber(normalized)
        elseif ContainsAny(normalized, { "y offset", "offset y", " y", "y " }) then
            key = "general.kickReadyOffsetY"
            value = FirstNumber(normalized)
        elseif ContainsAny(normalized, { "size", "scale", "groesse", "grosse" }) then
            key = "general.kickReadySize"
            value = FirstNumber(normalized)
        elseif ContainsAny(normalized, { "target", "target castbar", "target cast bar", "ziel" }) then
            key = "general.kickReadyShowTarget"
        elseif ContainsAny(normalized, { "focus", "focus castbar", "focus cast bar", "fokus" }) then
            key = "general.kickReadyShowFocus"
        elseif ContainsAny(normalized, { "boss", "boss castbar", "boss castbars", "boss cast bar", "boss cast bars" }) then
            key = "general.kickReadyShowBoss"
        end
        local setting = key and A.Registry and A.Registry:GetSetting(key)
        if setting and value == nil then
            if setting.type == "enum" then
                value = P.EnumValueForText and P.EnumValueForText(setting, normalized) or nil
            elseif setting.type == "boolean" then
                value = DetectBoolean(normalized)
                if value == nil then value = true end
            end
        end
        if setting and value ~= nil then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = setting.label or "Interrupt Ready",
                summary = "Changes Cast Bar Interrupt Ready visibility or indicator details.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if ContainsAny(normalized, { "castbar", "cast bar", "zauberleiste" })
        and ContainsAny(normalized, {
            "interrupt shake", "shake on interrupt", "shake strength",
            "unified fill direction", "same fill direction", "same castbar direction",
            "target opposite fill direction", "opposite target direction", "target castbar opposite direction",
            "fill direction", "channel ticks", "channel tick lines",
            "castbar texture", "cast bar texture", "foreground texture", "background texture",
            "outline thickness", "border thickness", "castbar glow", "cast bar glow",
            "castbar latency", "latency indicator", "castbar spark", "spark overflow",
            "empowered stage colors", "empower color stages", "empowered stage blink",
            "empower stage blink", "stage blink time", "empowered blink time",
            "spell name shortening", "shorten spell names", "max spell name length",
            "spell name max length", "reserved spell name space", "spell name reserved space",
        })
        and not ContainsAny(normalized, { "interrupt ready", "kick ready", "focus kick", "tracker" })
        and not (ContainsAny(normalized, { "color", "colors", "colour", "colours" })
            and ContainsAny(normalized, { "interrupt", "kick", "interruptible", "uninterruptible", "non interruptible", "noninterruptible" }))
    then
        local key
        local value
        if ContainsAny(normalized, { "shake strength" }) then
            key = "general.castbarShakeStrength"
            value = FirstNumber(normalized)
        elseif ContainsAny(normalized, { "interrupt shake", "shake on interrupt" }) then
            key = "general.castbarInterruptShake"
            value = DetectBoolean(normalized)
            if value == nil then value = true end
        elseif ContainsAny(normalized, { "unified fill direction", "same fill direction", "same castbar direction" }) then
            key = "general.castbarUnifiedDirection"
            value = DetectBoolean(normalized)
            if value == nil then value = true end
        elseif ContainsAny(normalized, { "target opposite fill direction", "opposite target direction", "target castbar opposite direction" }) then
            key = "general.castbarOpositeDirectionTarget"
            value = DetectBoolean(normalized)
            if value == nil then
                value = not ContainsAny(normalized, { "normal", "same", "not opposite", "disable", "off" })
            end
        elseif ContainsAny(normalized, { "fill direction" }) then
            key = "general.castbarFillDirection"
            local setting = A.Registry and A.Registry:GetSetting(key)
            value = setting and P.EnumValueForText and P.EnumValueForText(setting, normalized) or nil
        elseif ContainsAny(normalized, { "channel ticks", "channel tick lines" }) then
            key = "general.castbarShowChannelTicks"
            value = DetectBoolean(normalized)
            if value == nil then value = true end
        elseif ContainsAny(normalized, { "background texture" }) then
            key = "general.castbarBackgroundTexture"
            value = P.RawAfterLastConnector and P.RawAfterLastConnector(raw, { " to ", " as ", " = " }) or nil
        elseif ContainsAny(normalized, { "castbar texture", "cast bar texture", "foreground texture" }) then
            key = "general.castbarTexture"
            value = P.RawAfterLastConnector and P.RawAfterLastConnector(raw, { " to ", " as ", " = " }) or nil
        elseif ContainsAny(normalized, { "outline thickness", "border thickness" }) then
            key = "general.castbarOutlineThickness"
            value = FirstNumber(normalized)
        elseif ContainsAny(normalized, { "castbar glow", "cast bar glow", "glow effect" }) then
            key = "general.castbarShowGlow"
            value = DetectBoolean(normalized)
            if value == nil then value = true end
        elseif ContainsAny(normalized, { "castbar latency", "latency indicator" }) then
            key = "general.castbarShowLatency"
            value = DetectBoolean(normalized)
            if value == nil then value = true end
        elseif ContainsAny(normalized, { "spark overflow" }) then
            key = "general.castbarSparkOverflow"
            value = DetectBoolean(normalized)
            if value == nil then value = true end
        elseif ContainsAny(normalized, { "castbar spark", "cast bar spark" }) then
            key = "general.castbarShowSpark"
            value = DetectBoolean(normalized)
            if value == nil then value = true end
        elseif ContainsAny(normalized, { "stage blink time", "empowered blink time" }) then
            key = "general.empowerStageBlinkTime"
            value = FirstNumber(normalized)
        elseif ContainsAny(normalized, { "empowered stage colors", "empower color stages" }) then
            key = "general.empowerColorStages"
            value = DetectBoolean(normalized)
            if value == nil then value = true end
        elseif ContainsAny(normalized, { "empowered stage blink", "empower stage blink" }) then
            key = "general.empowerStageBlink"
            value = DetectBoolean(normalized)
            if value == nil then value = true end
        elseif ContainsAny(normalized, { "spell name shortening", "shorten spell names" }) then
            key = "general.castbarSpellNameShortening"
            value = DetectBoolean(normalized)
            if value == nil then value = true end
        elseif ContainsAny(normalized, { "max spell name length", "spell name max length" }) then
            key = "general.castbarSpellNameMaxLen"
            value = FirstNumber(normalized)
        elseif ContainsAny(normalized, { "reserved spell name space", "spell name reserved space" }) then
            key = "general.castbarSpellNameReservedSpace"
            value = FirstNumber(normalized)
        end
        local setting = key and A.Registry and A.Registry:GetSetting(key)
        if setting and value ~= nil then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = setting.label or "Cast Bar Behavior",
                summary = "Changes a global Cast Bar behavior option.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if ContainsAny(normalized, { "castbar", "cast bar", "zauberleiste" })
        and ContainsAny(normalized, {
            "icon size", "spell icon size", "icon x", "icon y", "icon offset", "symbol groesse",
            "spell name font size", "spell text font size", "spell text size", "castbar text font size",
            "time font size", "timer font size", "time text size", "castbar time font size",
        })
        and not DetectUnits(normalized)[1]
        and not ContainsAny(normalized, { "aura", "buff", "debuff", "focus kick", "kick icon", "interrupt icon" })
    then
        local key
        if ContainsAny(normalized, { "spell name font size", "spell text font size", "spell text size", "castbar text font size" }) then
            key = "general.castbarSpellNameFontSize"
        elseif ContainsAny(normalized, { "time font size", "timer font size", "time text size", "castbar time font size" }) then
            key = "general.castbarTimeFontSize"
        elseif ContainsAny(normalized, { "icon size", "spell icon size", "symbol groesse" }) then
            key = "general.castbarIconSize"
        elseif ContainsAny(normalized, { "icon x", "icon x offset", "x offset" }) then
            key = "general.castbarIconOffsetX"
        elseif ContainsAny(normalized, { "icon y", "icon y offset", "y offset" }) then
            key = "general.castbarIconOffsetY"
        end
        local setting = key and A.Registry and A.Registry:GetSetting(key)
        local value = setting and FirstNumber(normalized) or nil
        if setting and value ~= nil then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value } },
                label = setting.label or "Castbar Detail",
                summary = "Changes a global Cast Bar detail size or offset.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if ContainsAny(normalized, { "castbar", "cast bar", "zauberleiste" })
        and ContainsAny(normalized, {
            "icon size", "spell icon size", "icon position", "spell icon position",
            "icon x", "icon y", "icon offset", "icon spacing", "spell icon spacing",
            "icon border", "icon border style", "symbol groesse",
        })
        and not ContainsAny(normalized, { "aura", "buff", "debuff", "focus kick", "kick icon", "interrupt icon" })
    then
        local attr
        if ContainsAny(normalized, { "icon border", "icon border style" }) then
            attr = "border"
        elseif ContainsAny(normalized, { "icon spacing", "spell icon spacing" }) then
            attr = "spacing"
        elseif ContainsAny(normalized, { "icon position", "spell icon position" }) then
            attr = "position"
        elseif ContainsAny(normalized, { "icon x", "icon x offset" }) then
            attr = "x"
        elseif ContainsAny(normalized, { "icon y", "icon y offset" }) then
            attr = "y"
        elseif ContainsAny(normalized, { "icon size", "spell icon size", "symbol groesse" }) then
            attr = "size"
        end

        local keyMap = {
            player = {
                size = "general.castbarPlayerIconSize",
                position = "general.castbarPlayerIconPosition",
                x = "general.castbarPlayerIconOffsetX",
                y = "general.castbarPlayerIconOffsetY",
                spacing = "general.castbarPlayerIconSpacing",
                border = "general.castbarPlayerIconBorderStyle",
            },
            target = {
                size = "general.castbarTargetIconSize",
                position = "general.castbarTargetIconPosition",
                x = "general.castbarTargetIconOffsetX",
                y = "general.castbarTargetIconOffsetY",
                spacing = "general.castbarTargetIconSpacing",
                border = "general.castbarTargetIconBorderStyle",
            },
            focus = {
                size = "general.castbarFocusIconSize",
                position = "general.castbarFocusIconPosition",
                x = "general.castbarFocusIconOffsetX",
                y = "general.castbarFocusIconOffsetY",
                spacing = "general.castbarFocusIconSpacing",
                border = "general.castbarFocusIconBorderStyle",
            },
            boss = {
                size = "general.bossCastIconSize",
                position = "general.bossCastIconPosition",
                x = "general.bossCastIconOffsetX",
                y = "general.bossCastIconOffsetY",
                spacing = "general.bossCastIconSpacing",
                border = "general.bossCastIconBorderStyle",
            },
        }

        local units = DetectUnits(normalized)
        local changes = {}
        if attr then
            for i = 1, #units do
                local key = keyMap[units[i]] and keyMap[units[i]][attr]
                local setting = key and A.Registry and A.Registry:GetSetting(key)
                if setting then
                    local value
                    if setting.type == "enum" then
                        value = P.EnumValueForText and P.EnumValueForText(setting, normalized) or nil
                    else
                        value = FirstNumber(normalized)
                    end
                    if value ~= nil then changes[#changes + 1] = { setting = setting, value = value } end
                end
            end
        end
        if #changes > 0 then
            return {
                kind = "changes",
                changes = changes,
                label = #changes == 1 and (changes[1].setting.label or "Castbar Icon Detail") or "Castbar Icon Details",
                bulkSafe = #changes > 1,
                summary = "Changes unit Cast Bar icon size, position, spacing, or border options.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if ContainsAny(normalized, { "castbar", "cast bar", "zauberleiste" })
        and ContainsAny(normalized, {
            "spell name position", "spell text position", "text position",
            "text x", "text y", "spell name x", "spell name y", "spell text x", "spell text y",
            "spell name alignment", "spell text alignment", "text alignment",
            "spell name font size", "spell text font size", "spell text size",
            "spell name manual width", "spell text manual width", "text manual width",
            "spell name max width", "spell text max width", "text max width",
            "spell name width behavior", "spell text width behavior", "text width behavior",
            "spell name truncate", "spell text truncate", "text truncate",
            "time format", "timer format", "cast time format",
            "time position", "timer position", "time text position",
            "time x", "time y", "timer x", "timer y", "time text x", "time text y",
            "time font size", "timer font size", "time text size",
        })
        and not ContainsAny(normalized, { "aura", "buff", "debuff", "focus kick", "kick icon", "interrupt icon" })
    then
        local attr
        if ContainsAny(normalized, { "time format", "timer format", "cast time format" }) then
            attr = "timeFormat"
        elseif ContainsAny(normalized, { "time position", "timer position", "time text position" }) then
            attr = "timePosition"
        elseif ContainsAny(normalized, { "time x", "timer x", "time text x" }) then
            attr = "timeX"
        elseif ContainsAny(normalized, { "time y", "timer y", "time text y" }) then
            attr = "timeY"
        elseif ContainsAny(normalized, { "time font size", "timer font size", "time text size" }) then
            attr = "timeFontSize"
        elseif ContainsAny(normalized, { "spell name width behavior", "spell text width behavior", "text width behavior", "spell name truncate", "spell text truncate", "text truncate" }) then
            attr = "spellTruncate"
        elseif ContainsAny(normalized, { "spell name manual width", "spell text manual width", "text manual width", "spell name max width", "spell text max width", "text max width" }) then
            attr = "spellMaxWidth"
        elseif ContainsAny(normalized, { "spell name font size", "spell text font size", "spell text size" }) then
            attr = "spellFontSize"
        elseif ContainsAny(normalized, { "spell name alignment", "spell text alignment", "text alignment" }) then
            attr = "spellAlign"
        elseif ContainsAny(normalized, { "spell name position", "spell text position", "text position" }) then
            attr = "spellPosition"
        elseif ContainsAny(normalized, { "text x", "spell name x", "spell text x" }) then
            attr = "textX"
        elseif ContainsAny(normalized, { "text y", "spell name y", "spell text y" }) then
            attr = "textY"
        end

        local keyMap = {
            player = {
                spellPosition = "general.castbarPlayerSpellNamePosition",
                textX = "general.castbarPlayerTextOffsetX",
                textY = "general.castbarPlayerTextOffsetY",
                spellAlign = "general.castbarPlayerSpellNameAlign",
                spellFontSize = "general.castbarPlayerSpellNameFontSize",
                spellMaxWidth = "general.castbarPlayerSpellNameMaxWidth",
                spellTruncate = "general.castbarPlayerSpellNameTruncate",
                timeFormat = "general.castbarPlayerTimeFormat",
                timePosition = "general.castbarPlayerTimePosition",
                timeX = "general.castbarPlayerTimeOffsetX",
                timeY = "general.castbarPlayerTimeOffsetY",
                timeFontSize = "general.castbarPlayerTimeFontSize",
            },
            target = {
                spellPosition = "general.castbarTargetSpellNamePosition",
                textX = "general.castbarTargetTextOffsetX",
                textY = "general.castbarTargetTextOffsetY",
                spellAlign = "general.castbarTargetSpellNameAlign",
                spellFontSize = "general.castbarTargetSpellNameFontSize",
                spellMaxWidth = "general.castbarTargetSpellNameMaxWidth",
                spellTruncate = "general.castbarTargetSpellNameTruncate",
                timeFormat = "general.castbarTargetTimeFormat",
                timePosition = "general.castbarTargetTimePosition",
                timeX = "general.castbarTargetTimeOffsetX",
                timeY = "general.castbarTargetTimeOffsetY",
                timeFontSize = "general.castbarTargetTimeFontSize",
            },
            focus = {
                spellPosition = "general.castbarFocusSpellNamePosition",
                textX = "general.castbarFocusTextOffsetX",
                textY = "general.castbarFocusTextOffsetY",
                spellAlign = "general.castbarFocusSpellNameAlign",
                spellFontSize = "general.castbarFocusSpellNameFontSize",
                spellMaxWidth = "general.castbarFocusSpellNameMaxWidth",
                spellTruncate = "general.castbarFocusSpellNameTruncate",
                timeFormat = "general.castbarFocusTimeFormat",
                timePosition = "general.castbarFocusTimePosition",
                timeX = "general.castbarFocusTimeOffsetX",
                timeY = "general.castbarFocusTimeOffsetY",
                timeFontSize = "general.castbarFocusTimeFontSize",
            },
            boss = {
                spellPosition = "general.bossCastSpellNamePosition",
                textX = "general.bossCastTextOffsetX",
                textY = "general.bossCastTextOffsetY",
                spellAlign = "general.bossCastSpellNameAlign",
                spellFontSize = "general.bossCastSpellNameFontSize",
                spellMaxWidth = "general.bossCastSpellNameMaxWidth",
                spellTruncate = "general.bossCastSpellNameTruncate",
                timeFormat = "general.bossCastTimeFormat",
                timePosition = "general.bossCastTimePosition",
                timeX = "general.bossCastTimeOffsetX",
                timeY = "general.bossCastTimeOffsetY",
                timeFontSize = "general.bossCastTimeFontSize",
            },
        }

        local units = DetectUnits(normalized)
        local changes = {}
        if attr then
            for i = 1, #units do
                local key = keyMap[units[i]] and keyMap[units[i]][attr]
                local setting = key and A.Registry and A.Registry:GetSetting(key)
                if setting then
                    local value
                    if setting.type == "enum" then
                        value = P.EnumValueForText and P.EnumValueForText(setting, normalized) or nil
                    else
                        value = FirstNumber(normalized)
                    end
                    if value ~= nil then changes[#changes + 1] = { setting = setting, value = value } end
                end
            end
        end
        if #changes > 0 then
            return {
                kind = "changes",
                changes = changes,
                label = #changes == 1 and (changes[1].setting.label or "Castbar Text Detail") or "Castbar Text Details",
                bulkSafe = #changes > 1,
                summary = "Changes unit Cast Bar spell text or time text detail options.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if ContainsAny(normalized, { "castbar", "cast bar", "zauberleiste" })
        and ContainsAny(normalized, { "time", "cast time", "icon", "spell icon", "text", "spell text", "spell name" })
        and not ContainsAny(normalized, {
            "width", "height", "size", "position", "anchor", "align", "alignment", "format",
            "x offset", "y offset", " icon x", " icon y", " text x", " text y",
            "manual width", "truncate", "border", "spacing",
        })
    then
        local attr
        if ContainsAny(normalized, { "time", "cast time" }) then
            attr = "time"
        elseif ContainsAny(normalized, { "icon", "spell icon" }) then
            attr = "icon"
        elseif ContainsAny(normalized, { "text", "spell text", "spell name" }) then
            attr = "text"
        end
        local value = DetectBoolean(normalized)
        local units = DetectUnits(normalized)
        local keys = {
            player = { time = "general.showPlayerCastTime", icon = "general.castbarPlayerShowIcon", text = "general.castbarPlayerShowSpellName" },
            target = { time = "general.showTargetCastTime", icon = "general.castbarTargetShowIcon", text = "general.castbarTargetShowSpellName" },
            focus = { time = "general.showFocusCastTime", icon = "general.castbarFocusShowIcon", text = "general.castbarFocusShowSpellName" },
            boss = { time = "general.showBossCastTime", icon = "general.showBossCastIcon", text = "general.showBossCastName" },
        }
        local changes = {}
        if attr and value ~= nil then
            for i = 1, #units do
                local key = keys[units[i]] and keys[units[i]][attr]
                local setting = key and A.Registry and A.Registry:GetSetting(key)
                if setting then changes[#changes + 1] = { setting = setting, value = value } end
            end
        end
        if #changes > 0 then
            return {
                kind = "changes",
                changes = changes,
                label = #changes == 1 and (changes[1].setting.label or "Cast Bar Detail") or "Cast Bar Details",
                bulkSafe = #changes > 1,
                summary = "Changes Cast Bar time, icon, or spell text visibility.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if ContainsAny(normalized, { "castbar", "cast bar", "zauberleiste" })
        and ContainsAny(normalized, { "width", "height", "wide", "tall", "breite", "hoehe" })
        and not ContainsAny(normalized, {
            "text", "time", "icon", "aura", "buff", "debuff", "spell name",
            "manual width", "focus kick", "kick icon", "interrupt icon",
        })
    then
        local axis
        if ContainsAny(normalized, { "width", "wide", "breite" }) then
            axis = "w"
        elseif ContainsAny(normalized, { "height", "tall", "hoehe" }) then
            axis = "h"
        end
        local value = FirstNumber(normalized)
        local units = DetectUnits(normalized)
        local keys = {
            player = { w = "general.castbarPlayerBarWidth", h = "general.castbarPlayerBarHeight" },
            target = { w = "general.castbarTargetBarWidth", h = "general.castbarTargetBarHeight" },
            focus = { w = "general.castbarFocusBarWidth", h = "general.castbarFocusBarHeight" },
            boss = { w = "general.bossCastbarWidth", h = "general.bossCastbarHeight" },
        }
        local changes = {}
        if axis and value ~= nil then
            for i = 1, #units do
                local key = keys[units[i]] and keys[units[i]][axis]
                local setting = key and A.Registry and A.Registry:GetSetting(key)
                if setting then changes[#changes + 1] = { setting = setting, value = value } end
            end
        end
        if #changes > 0 then
            return {
                kind = "changes",
                changes = changes,
                label = #changes == 1 and (changes[1].setting.label or "Cast Bar Size") or "Cast Bar Size",
                bulkSafe = #changes > 1,
                summary = "Changes unit Cast Bar width or height.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if ContainsAny(normalized, { "castbar", "cast bar", "zauberleiste" })
        and ContainsAny(normalized, { " x", "x ", "x offset", " y", "y ", "y offset", "links", "rechts", "oben", "unten" })
        and not ContainsAny(normalized, {
            "text", "time", "icon", "aura", "buff", "debuff", "spell name",
            "manual width", "focus kick", "kick icon", "interrupt icon",
        })
    then
        local axis
        if ContainsAny(normalized, { "x offset", "offset x", " x", "x ", "links", "rechts" }) then
            axis = "x"
        elseif ContainsAny(normalized, { "y offset", "offset y", " y", "y ", "oben", "unten" }) then
            axis = "y"
        end
        local value = FirstNumber(normalized)
        local units = DetectUnits(normalized)
        local keys = {
            player = { x = "general.castbarPlayerOffsetX", y = "general.castbarPlayerOffsetY" },
            target = { x = "general.castbarTargetOffsetX", y = "general.castbarTargetOffsetY" },
            focus = { x = "general.castbarFocusOffsetX", y = "general.castbarFocusOffsetY" },
            boss = { x = "general.bossCastbarOffsetX", y = "general.bossCastbarOffsetY" },
        }
        local changes = {}
        if axis and value ~= nil then
            for i = 1, #units do
                local key = keys[units[i]] and keys[units[i]][axis]
                local setting = key and A.Registry and A.Registry:GetSetting(key)
                if setting then changes[#changes + 1] = { setting = setting, value = value } end
            end
        end
        if #changes > 0 then
            return {
                kind = "changes",
                changes = changes,
                label = #changes == 1 and (changes[1].setting.label or "Cast Bar Offset") or "Cast Bar Offset",
                bulkSafe = #changes > 1,
                summary = "Changes unit Cast Bar X/Y offset.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if ContainsAny(normalized, { "castbar", "cast bar", "zauberleiste" })
        and not ContainsAny(normalized, {
            "text", "time", "icon", "width", "height", "size", "x", "y", "offset",
            "move", "nudge", "shift", "position", "anchor", "color", "colour", "backend",
            "provider", "interrupt", "spell", "test", "preview", "fill", "direction",
        })
    then
        local value = DetectBoolean(normalized)
        if value ~= nil then
            local units = DetectUnits(normalized)
            local keys = {
                player = "general.enablePlayerCastbar",
                target = "general.enableTargetCastbar",
                focus = "general.enableFocusCastbar",
                boss = "general.enableBossCastbar",
            }
            local changes = {}
            for i = 1, #units do
                local key = keys[units[i]]
                local setting = key and A.Registry and A.Registry:GetSetting(key)
                if setting then changes[#changes + 1] = { setting = setting, value = value } end
            end
            if #changes > 0 then
                return {
                    kind = "changes",
                    changes = changes,
                    label = #changes == 1 and (changes[1].setting.label or "Cast Bar") or "Cast Bars",
                    bulkSafe = #changes > 1,
                    summary = "Changes unit Cast Bar visibility.",
                    raw = raw,
                    normalized = normalized,
                }
            end
        end
    end
    if ContainsAny(normalized, {
        "confirm wago backup", "clear wago backup", "reset wago backup", "unconfirm wago backup",
        "profile backup confirmed", "backup confirmed",
        "open dashboard panel", "show dashboard panel", "close dashboard panel", "hide dashboard panel",
        "toggle dashboard panel", "dashboard panels",
        "navigation section", "nav section", "sidebar section", "navigation group", "nav group",
        "reset search intro", "show search intro", "hide search intro", "mark search intro seen",
        "open recovery tools", "show recovery tools", "display recovery", "dashboard recovery",
        "open scaling tools", "show scaling tools", "dashboard scaling", "open changelog",
        "show changelog", "release notes", "latest changes", "build notes",
        "enter edit mode", "exit edit mode", "leave edit mode", "cancel edit mode", "toggle edit mode",
        "edit mode status", "am i in edit mode", "is edit mode on", "why can't i exit edit mode",
        "why cant i exit edit mode", "why can not i exit edit mode",
    }) and not ContainsAny(normalized, { " help", "help ", "how do i", "how can i", "what is", "what are", "explain", "describe" }) then
        local actionKey
        local args = {}
        local label
        local summary
        local confirmRequired = false
        if ContainsAny(normalized, { "confirm wago backup", "clear wago backup", "reset wago backup", "unconfirm wago backup", "profile backup confirmed", "backup confirmed" }) then
            local clear = ContainsAny(normalized, { "clear", "reset", "unconfirm", "not confirmed" })
            actionKey = "confirm_wago_backup"
            args.confirmed = not clear
            label = clear and "Clear Wago backup confirmation" or "Confirm Wago backup"
            summary = "Marks the Wago backup checklist for the active profile."
        elseif ContainsAny(normalized, { "open recovery tools", "show recovery tools", "display recovery", "dashboard recovery" }) then
            actionKey = "open_recovery_tools"
            label = "Open recovery tools"
            summary = "Opens the Dashboard recovery area."
        elseif ContainsAny(normalized, { "open dashboard panel", "show dashboard panel", "close dashboard panel", "hide dashboard panel", "toggle dashboard panel", "dashboard panels" }) then
            actionKey = "set_dashboard_panel"
            if ContainsAny(normalized, { "close", "hide", "collapse" }) then
                args.open = false
            elseif ContainsAny(normalized, { "toggle" }) then
                args.open = nil
            else
                args.open = true
            end
            label = "Set Dashboard panel"
            summary = "Asks which Dashboard panel to open, such as recovery tools, scaling tools, or changelog."
        elseif ContainsAny(normalized, { "reset search intro", "show search intro", "hide search intro", "mark search intro seen", "search intro" }) then
            actionKey = "set_nav_search_intro"
            if ContainsAny(normalized, { "hide", "close", "dismiss", "mark seen", "mark as seen", "mark search intro seen", "dont show" }) then
                args.command = "seen"
            elseif ContainsAny(normalized, { "reset", "show again", "next time" }) then
                args.command = "reset"
            else
                args.command = "show"
            end
            label = "Set search intro"
            summary = "Shows or hides the menu search intro."
        elseif ContainsAny(normalized, { "navigation section", "nav section", "sidebar section", "navigation group", "nav group" }) then
            actionKey = "set_nav_section"
            if ContainsAny(normalized, { "group frames", "groupframes", "raid frames", "party frames", "group frame", "groups" }) then
                args.section = "groupframes"
                label = "Group Frames"
            elseif ContainsAny(normalized, { "unit frames", "unitframes", "unit frame", "frames", "frame list" }) then
                args.section = "unitframes"
                label = "Frames"
            elseif ContainsAny(normalized, { "appearance", "global style", "globalstyle", "style section", "look section" }) then
                args.section = "globalstyle"
                label = "Appearance"
            elseif ContainsAny(normalized, { "advanced", "modules", "module section", "advanced menu" }) then
                args.section = "modules"
                label = "Advanced"
            elseif ContainsAny(normalized, { "auras", "aura section", "buffs section", "debuffs section" }) then
                args.section = "auras"
                label = "Auras"
            end
            if ContainsAny(normalized, { "close", "hide", "collapse" }) then
                args.open = false
            elseif ContainsAny(normalized, { "toggle" }) then
                args.open = nil
            else
                args.open = true
            end
            if label then
                label = (args.open == false and "Close " or (args.open == nil and "Toggle " or "Open ")) .. label .. " navigation section"
            else
                label = "Set navigation section"
            end
            summary = "Expands or collapses a menu section."
        elseif ContainsAny(normalized, { "open scaling tools", "show scaling tools", "dashboard scaling" }) then
            actionKey = "open_dashboard_panel"
            args.panel = "scaling"
            label = "Open scaling tools"
            summary = "Opens the Dashboard scaling area."
        elseif ContainsAny(normalized, { "open changelog", "show changelog", "release notes", "latest changes", "build notes" }) then
            actionKey = "open_dashboard_panel"
            args.panel = "changelog"
            label = "Open changelog"
            summary = "Opens the Dashboard changelog."
        elseif ContainsAny(normalized, { "edit mode", "editmode", "msuf edit mode", "bearbeitungsmodus", "editmodus" }) then
            if ContainsAny(normalized, {
                "am i in edit mode", "is edit mode on", "is edit mode active", "edit mode status",
                "why can't i exit edit mode", "why cant i exit edit mode", "why can not i exit edit mode",
            }) then
                actionKey = "assistant.diagnostic.editMode.status"
                if ContainsAny(normalized, { "why can't", "why cant", "why can not" }) then args.reason = "why_exit" end
                label = "Show MSUF Edit Mode status"
            elseif ContainsAny(normalized, { "cancel edit mode", "discard edit mode", "cancel msuf edit mode" }) then
                actionKey = "assistant.action.editMode.cancel"
                confirmRequired = true
                label = "Cancel MSUF Edit Mode"
            elseif ContainsAny(normalized, { "toggle edit mode", "toggle msuf edit mode" }) then
                actionKey = "assistant.action.editMode.toggle"
                label = "Toggle MSUF Edit Mode"
            elseif ContainsAny(normalized, {
                "stop edit mode", "exit edit mode", "exit msuf edit mode", "leave edit mode", "leave msuf edit mode",
                "close edit mode", "disable edit mode", "turn off edit mode", "edit mode off",
            }) then
                actionKey = "assistant.action.editMode.exit"
                label = "Exit MSUF Edit Mode"
            elseif ContainsAny(normalized, { "enter edit mode", "start edit mode", "open edit mode", "turn on edit mode", "edit mode on" }) then
                actionKey = "assistant.action.editMode.enter"
                label = "Enter MSUF Edit Mode"
            end
            summary = "Starts, stops, or checks MSUF Edit Mode."
        end
        local action = actionKey and A.Registry and A.Registry:GetAction(actionKey)
        if action then
            return {
                kind = "action",
                action = action,
                args = args,
                confirmRequired = confirmRequired,
                label = label or (action.label or "Assistant shortcut"),
                summary = summary or "Runs the matched Assistant shortcut.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if ContainsAny(normalized, {
        "copy category", "copy categories", "copy scope", "copy scopes",
        "select unit copy", "select group copy", "set unit copy", "set group copy",
        "select all group copy categories", "select all unit copy categories",
    }) then
        local earlyMenuSelectorParsed = (ParseGroupCopyScopeState and ParseGroupCopyScopeState(normalized))
            or (ParseUnitCopyScopeState and ParseUnitCopyScopeState(normalized))
            or (ParseMenuSelectorState and ParseMenuSelectorState(normalized))
        if earlyMenuSelectorParsed then
            earlyMenuSelectorParsed.raw = raw
            earlyMenuSelectorParsed.normalized = normalized
            return earlyMenuSelectorParsed
        end
    end
    if ContainsAny(normalized, { "copy " })
        and ContainsAny(normalized, { " to ", " into ", "onto " })
        and not ContainsAny(normalized, {
            "profile", "profiles", "profil", "wago", "support link", "discord", "github",
            "patreon", "paypal", "kofi", "ko-fi",
        })
    then
        local earlyCopyParsed = CopyRequest(normalized)
        if earlyCopyParsed then
            earlyCopyParsed.raw = raw
            earlyCopyParsed.normalized = normalized
            return earlyCopyParsed
        end
    end
    if ContainsAny(normalized, {
        "close msuf menu", "hide msuf menu", "minimize msuf menu", "minimise msuf menu",
        "maximize msuf menu", "maximise msuf menu", "restore msuf menu",
        "close menu", "hide menu", "minimize menu", "minimise menu", "maximize menu",
        "maximise menu", "restore menu",
    }) then
        local earlyMenuWindowParsed = ParseMenuWindowAction and ParseMenuWindowAction(normalized)
        if earlyMenuWindowParsed then
            earlyMenuWindowParsed.raw = raw
            earlyMenuWindowParsed.normalized = normalized
            return earlyMenuWindowParsed
        end
    end
    if ContainsAny(normalized, {
        "open ", "go to ", "show settings", "show me ", "find ", "search ", "where ",
        " frame page", " settings page", " option page", " options page", " config page",
    }) and not ContainsAny(normalized, {
        "profile import", "import profile", "open profile import", "profile export",
        "export profile", "profile string", "import string", "export string",
    }) then
        local earlyOpenParsed = ParseOpen and ParseOpen(normalized, raw)
        if earlyOpenParsed then
            earlyOpenParsed.raw = raw
            earlyOpenParsed.normalized = normalized
            return earlyOpenParsed
        end
    end
    if normalized == "help" or normalized == "hilfe" or ContainsAny(normalized, {
        "assistant help", "command help", "commands help", "help commands",
        "print help", "show help", "what can you do", "what settings can you change",
        "command examples",
    }) then
        local action = A.Registry and A.Registry:GetAction("assistant_help")
        if action then
            return {
                kind = "action",
                action = action,
                args = {},
                label = "Show Assistant help",
                summary = "Shows Assistant examples handled locally by MSUF.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if ContainsAny(normalized, { "help for", "help with", "player frame help", "target frame help", "group frame help", "edit mode help" }) then
        local earlyScopedHelpParsed = ParseScopedHelp and ParseScopedHelp(normalized)
        if earlyScopedHelpParsed then
            earlyScopedHelpParsed.raw = raw
            earlyScopedHelpParsed.normalized = normalized
            return earlyScopedHelpParsed
        end
    end
    if ContainsAny(normalized, {
        "support link", "support links", "discord support", "discord link", "copy discord",
        "copy support", "show support links", "donate links", "development links",
        "github link", "repo link", "repository link", "patreon link", "paypal link",
        "ko fi", "kofi", "ko-fi",
    }) then
        local earlySupportParsed = ParseSupportWorkflow and ParseSupportWorkflow(normalized)
        if earlySupportParsed then
            earlySupportParsed.raw = raw
            earlySupportParsed.normalized = normalized
            return earlySupportParsed
        end
    end
    if ContainsAny(normalized, {
        "guided setup", "setup guide", "start guide", "start tour", "guide me",
        "guided setup next", "setup next", "next setup", "continue setup",
        "cancel setup", "finish setup", "skip setup", "setup status",
    }) then
        local earlyGuidedSetupParsed = (ParseGuidedSetupFollowup and ParseGuidedSetupFollowup(normalized, ctx))
            or (ParseGuidedSetup and ParseGuidedSetup(normalized))
        if earlyGuidedSetupParsed then
            earlyGuidedSetupParsed.raw = raw
            earlyGuidedSetupParsed.normalized = normalized
            return earlyGuidedSetupParsed
        end
    end
    if ContainsAny(normalized, {
        "assistant status", "msuf status", "status report", "diagnostic report",
        "run checks", "run diagnostics", "health check", "assistant support text",
        "no match telemetry", "nomatch telemetry", "no match worklist", "nomatch worklist",
        "clear no match telemetry", "clear nomatch telemetry", "assistant misses",
        "diagnose ", "diagnostics", "debug report", "performance report",
    }) then
        local actionKey
        local args = {}
        local label
        local summary
        local confirmRequired = false
        if ContainsAny(normalized, { "clear no match telemetry", "clear nomatch telemetry", "clear assistant no match", "reset no match telemetry" }) then
            actionKey = "assistant_nomatch_clear"
            label = "Clear Assistant learning phrases"
            summary = "Clears stored Assistant learning/no-match phrases."
            confirmRequired = true
        elseif ContainsAny(normalized, { "no match worklist", "nomatch worklist", "action no match worklist", "show action no match worklist" }) then
            actionKey = "assistant_nomatch_worklist"
            if ContainsAny(normalized, { "action no match", "action nomatch", "action review" }) then args.owner = "action-parser" end
            label = "Show Assistant learning list"
            summary = "Shows phrases that still need better Assistant answers."
        elseif ContainsAny(normalized, { "no match telemetry", "nomatch telemetry", "show no match", "show nomatch", "assistant misses" }) then
            actionKey = "assistant_nomatch_telemetry"
            label = "Show Assistant phrases to improve"
            summary = "Shows stored phrases that still need better Assistant answers."
        elseif ContainsAny(normalized, { "assistant status", "msuf status", "status report", "diagnostic report", "assistant support text", "debug report", "performance report" }) then
            actionKey = "assistant_status"
            label = "Show MSUF status"
            summary = "Shows read-only MSUF and Assistant details."
        end
        local action = actionKey and A.Registry and A.Registry:GetAction(actionKey)
        local earlyDiagnosticParsed = action and {
            kind = "action",
            action = action,
            args = args,
            confirmRequired = confirmRequired,
            label = label or action.label or "Assistant diagnostic",
            summary = summary or "Runs an Assistant diagnostic.",
        } or (ParseDiagnostic and ParseDiagnostic(normalized))
        if earlyDiagnosticParsed then
            earlyDiagnosticParsed.raw = raw
            earlyDiagnosticParsed.normalized = normalized
            return earlyDiagnosticParsed
        end
    end
    if ContainsAny(normalized, {
        "blacklist", "unblacklist", "hidden aura", "aura spell", "spell blacklist",
        "aura preset", "category blacklist", "blacklist category",
    }) then
        local auraActionParsed = P.ParseRegistryActionAliasShortcut and P.ParseRegistryActionAliasShortcut(normalized, raw)
        if auraActionParsed then
            auraActionParsed.raw = raw
            auraActionParsed.normalized = normalized
            return auraActionParsed
        end
    end
    local actionFirstParsed
    if ContainsAny(normalized, { "crosshair", "fadenkreuz", "totem frame", "totemframe", "blizzard totem", "statue frame", "totem rahmen" }) then
        actionFirstParsed = ParseGameplayAction(normalized, raw)
    end
    actionFirstParsed = actionFirstParsed or ParsePresetWorkflow(normalized) or ParseGlobalBarsAction(normalized)
    if not actionFirstParsed and ContainsAny(normalized, { "global font color", "main font color", "default font color", "globale schriftfarbe" }) then
        actionFirstParsed = ParseFontColorAction(normalized, raw)
    end
    if not actionFirstParsed
        and ContainsAny(normalized, { "reset", "restore", "zuruecksetzen", "zurucksetzen" })
        and ContainsAny(normalized, { "color", "colors", "colour", "colours", "farbe", "farben", "tint" })
    then
        actionFirstParsed = ParseColorAction(normalized)
    end
    actionFirstParsed = actionFirstParsed
        or ParseScopedOverrideReset(normalized)
        or (not ContainsAny(normalized, { "focus kick", "focus interrupt", "kick preview", "interrupt preview" }) and ParseCastbarPreviewAction(normalized))
        or ParseGroupSpellIndicatorAction(normalized, raw)
        or ParseGroupCornerIndicatorReset(normalized)
        or ParseGroupStatusPreview(normalized)
        or ParseUnitStatusPreview(normalized, ctx)
        or (P.ParseGroupStatusIconDetail and P.ParseGroupStatusIconDetail(normalized))
        or (P.ParsePowerBarGradientRegistryShortcut and P.ParsePowerBarGradientRegistryShortcut(normalized))
        or (P.ParseDetachedPowerBarMoveShortcut and P.ParseDetachedPowerBarMoveShortcut(normalized))
    if not actionFirstParsed
        and ContainsAny(normalized, { "reset", "restore", "zuruecksetzen", "zurucksetzen" })
        and not ContainsAny(normalized, { "set", "change", "make", "to default", "as default", "auf default", "zu default" })
    then
        actionFirstParsed = ParseGroupStatusIconReset(normalized)
            or ParseUnitStatusIndicatorReset(normalized, ctx)
    end
    if not actionFirstParsed
        and ContainsAny(normalized, { "reset", "restore", "zuruecksetzen", "zurucksetzen", "default", "defaults", "werksreset", "werkseinstellungen", "vollreset" })
        and ContainsAny(normalized, {
            "position", "positions", "pos", "placement", "x", "y", "offscreen", "off screen",
            "all positions", "frame positions", "reset positions", "reset movers", "broken layout",
            "factory reset", "full reset", "fullreset", "reset all settings", "reset all profiles",
            "profile", "profil", "werksreset", "werkseinstellungen", "vollreset",
        })
    then
        actionFirstParsed = ParseReset(normalized)
    end
    if not actionFirstParsed
        and ContainsAny(normalized, { "reset", "restore", "zuruecksetzen", "zurucksetzen", "default", "defaults" })
        and ContainsAny(normalized, { "options", "settings", "page", "option page", "setting page" })
        and not ContainsAny(normalized, {
            "name", "hp", "health", "power", "mana", "text", "font", "color", "colour",
            "aura", "auras", "buff", "buffs", "debuff", "debuffs", "castbar", "cast bar",
            "portrait", "range fade", "raid marker", "status", "indicator", "icon", "border",
            "opacity", "alpha", "width", "height", "position", "offset", "x", "y",
        })
    then
        actionFirstParsed = ParseReset(normalized)
    end
    if actionFirstParsed then
        actionFirstParsed.raw = raw
        actionFirstParsed.normalized = normalized
        return actionFirstParsed
    end
    local earlyAuraParsed = EarlyAuraShortcut(normalized, raw)
    if earlyAuraParsed then
        earlyAuraParsed.raw = raw
        earlyAuraParsed.normalized = normalized
        return earlyAuraParsed
    end
    local earlyTextVisibilityParsed = P.ParseTextVisibilityShortcut and P.ParseTextVisibilityShortcut(normalized)
    if earlyTextVisibilityParsed then
        earlyTextVisibilityParsed.raw = raw
        earlyTextVisibilityParsed.normalized = normalized
        return earlyTextVisibilityParsed
    end
    local earlyTextDetailParsed = (A._ParseNameTextAnchorShortcut and A._ParseNameTextAnchorShortcut(normalized))
        or (A._ParseNameTextOffsetShortcut and A._ParseNameTextOffsetShortcut(normalized))
        or (A._ParseNameTextVerticalPlacementShortcut and A._ParseNameTextVerticalPlacementShortcut(normalized))
        or (A._ParseTextSlotDropdownValueShortcut and A._ParseTextSlotDropdownValueShortcut(normalized))
        or (A._ParseHPTextOptionShortcut and A._ParseHPTextOptionShortcut(normalized))
        or (A._ParsePowerTextOptionShortcut and A._ParsePowerTextOptionShortcut(normalized))
        or (A._ParseTextAreaOffsetShortcut and A._ParseTextAreaOffsetShortcut(normalized))
        or (A._ParseTextSlotValueMoveShortcut and A._ParseTextSlotValueMoveShortcut(normalized))
        or (A._ParseTextSlotOffsetShortcut and A._ParseTextSlotOffsetShortcut(normalized))
        or (A._ParseTextFontSizeShortcut and A._ParseTextFontSizeShortcut(normalized))
    if earlyTextDetailParsed then
        earlyTextDetailParsed.raw = raw
        earlyTextDetailParsed.normalized = normalized
        return earlyTextDetailParsed
    end
    local earlyCustomAnchorSetParsed = ParseCustomAnchorSet(normalized, raw)
    if earlyCustomAnchorSetParsed then
        earlyCustomAnchorSetParsed.raw = raw
        earlyCustomAnchorSetParsed.normalized = normalized
        return earlyCustomAnchorSetParsed
    end
    local earlyPortraitDetailParsed = ParsePortraitDetailShortcut(normalized)
    if earlyPortraitDetailParsed then
        earlyPortraitDetailParsed.raw = raw
        earlyPortraitDetailParsed.normalized = normalized
        return earlyPortraitDetailParsed
    end
    local earlyPowerBarDetailParsed = (P.ParsePowerBarSizeShortcut and P.ParsePowerBarSizeShortcut(normalized))
        or (P.ParseUnitPowerBarBorderThicknessShortcut and P.ParseUnitPowerBarBorderThicknessShortcut(normalized))
        or (P.ParseUnitPowerBarBooleanShortcut and P.ParseUnitPowerBarBooleanShortcut(normalized))
        or (P.ParsePlayerPowerBarShapeShortcut and P.ParsePlayerPowerBarShapeShortcut(normalized))
        or (P.ParsePlayerPowerOrbSizeShortcut and P.ParsePlayerPowerOrbSizeShortcut(normalized))
        or (A._ParseClassPowerDetachedPlayerPowerShortcut and A._ParseClassPowerDetachedPlayerPowerShortcut(normalized, raw))
        or (P.ParseDetachedPowerBarRegistryShortcut and P.ParseDetachedPowerBarRegistryShortcut(normalized, raw))
    if earlyPowerBarDetailParsed then
        earlyPowerBarDetailParsed.raw = raw
        earlyPowerBarDetailParsed.normalized = normalized
        return earlyPowerBarDetailParsed
    end
    local earlyUnitStatusDetailParsed = (ParseUnitStatusSymbolRegistryShortcut and ParseUnitStatusSymbolRegistryShortcut(normalized))
        or (ParseStatusIconTestModeRegistryShortcut and ParseStatusIconTestModeRegistryShortcut(normalized))
        or (P.ParseUnitStatusIndicatorDetail and P.ParseUnitStatusIndicatorDetail(normalized))
    if earlyUnitStatusDetailParsed then
        earlyUnitStatusDetailParsed.raw = raw
        earlyUnitStatusDetailParsed.normalized = normalized
        return earlyUnitStatusDetailParsed
    end
    local earlyUnitLoadConditionParsed = ParseUnitLoadConditionShortcut and ParseUnitLoadConditionShortcut(normalized)
    if earlyUnitLoadConditionParsed then
        earlyUnitLoadConditionParsed.raw = raw
        earlyUnitLoadConditionParsed.normalized = normalized
        return earlyUnitLoadConditionParsed
    end
    local earlyTextLayerParsed = A._ParseTextLayerShortcut and A._ParseTextLayerShortcut(normalized)
    if earlyTextLayerParsed then
        earlyTextLayerParsed.raw = raw
        earlyTextLayerParsed.normalized = normalized
        return earlyTextLayerParsed
    end
    local earlyFrameSizeParsed = P.ParseFrameSizeExactShortcut and P.ParseFrameSizeExactShortcut(normalized)
    if earlyFrameSizeParsed then
        earlyFrameSizeParsed.raw = raw
        earlyFrameSizeParsed.normalized = normalized
        return earlyFrameSizeParsed
    end
    local earlyRootMoveParsed = (P.ParseUnitFrameRootMove and P.ParseUnitFrameRootMove(normalized))
        or (P.ParseGroupFrameRootMove and P.ParseGroupFrameRootMove(normalized))
    if earlyRootMoveParsed then
        earlyRootMoveParsed.raw = raw
        earlyRootMoveParsed.normalized = normalized
        return earlyRootMoveParsed
    end
    local earlyRangeFadeParsed = (P.ParseUnitRangeFadeShortcut and P.ParseUnitRangeFadeShortcut(normalized))
        or (A._ParseGroupRangeFadeShortcut and A._ParseGroupRangeFadeShortcut(normalized))
    if earlyRangeFadeParsed then
        earlyRangeFadeParsed.raw = raw
        earlyRangeFadeParsed.normalized = normalized
        return earlyRangeFadeParsed
    end
    if LooksLikeAlphaExcludeTextPortraitCommand(normalized) then
        local earlyAlphaExcludeParsed = P.ParseAlphaExcludeTextPortraitShortcut and P.ParseAlphaExcludeTextPortraitShortcut(normalized)
        if earlyAlphaExcludeParsed then
            earlyAlphaExcludeParsed.raw = raw
            earlyAlphaExcludeParsed.normalized = normalized
            return earlyAlphaExcludeParsed
        end
    end
    local earlyCastbarInterruptVisibilityParsed = ParseCastbarInterruptVisibilityShortcut(normalized)
    if earlyCastbarInterruptVisibilityParsed then
        earlyCastbarInterruptVisibilityParsed.raw = raw
        earlyCastbarInterruptVisibilityParsed.normalized = normalized
        return earlyCastbarInterruptVisibilityParsed
    end
    local earlyOpacityParsed = (A._ParseGroupOpacityShortcut and A._ParseGroupOpacityShortcut(normalized))
        or (ParseUnitOpacityShortcut and ParseUnitOpacityShortcut(normalized))
    if earlyOpacityParsed then
        earlyOpacityParsed.raw = raw
        earlyOpacityParsed.normalized = normalized
        return earlyOpacityParsed
    end
    if LooksLikeAbsorbBarCommand(normalized) then
        local earlyAbsorbBarParsed = ParseAbsorbBarShortcut and ParseAbsorbBarShortcut(normalized, raw)
        if earlyAbsorbBarParsed then
            earlyAbsorbBarParsed.raw = raw
            earlyAbsorbBarParsed.normalized = normalized
            return earlyAbsorbBarParsed
        end
    end
    if LooksLikeBarBorderEnumCommand(normalized) then
        local earlyBarBorderEnumParsed = ParseBarBorderEnumShortcut and ParseBarBorderEnumShortcut(normalized)
        if earlyBarBorderEnumParsed then
            earlyBarBorderEnumParsed.raw = raw
            earlyBarBorderEnumParsed.normalized = normalized
            return earlyBarBorderEnumParsed
        end
    end
    if LooksLikeBarOutlineHighlightCommand(normalized) then
        local earlyBarOutlineHighlightParsed = ParseBarOutlineHighlightShortcut and ParseBarOutlineHighlightShortcut(normalized)
        if earlyBarOutlineHighlightParsed then
            earlyBarOutlineHighlightParsed.raw = raw
            earlyBarOutlineHighlightParsed.normalized = normalized
            return earlyBarOutlineHighlightParsed
        end
    end
    local earlyHealthColorParsed = P.ParseUnitHealthColorSchemeShortcut and P.ParseUnitHealthColorSchemeShortcut(normalized)
    if earlyHealthColorParsed then
        earlyHealthColorParsed.raw = raw
        earlyHealthColorParsed.normalized = normalized
        return earlyHealthColorParsed
    end
    local earlyUnitAnchorParsed = P.ParseUnitAnchorTargetShortcut and P.ParseUnitAnchorTargetShortcut(normalized)
        or (P.ParseUnitAnchorPointShortcut and P.ParseUnitAnchorPointShortcut(normalized))
    if earlyUnitAnchorParsed then
        earlyUnitAnchorParsed.raw = raw
        earlyUnitAnchorParsed.normalized = normalized
        return earlyUnitAnchorParsed
    end
    if ContainsAny(normalized, { "color", "colors", "colour", "colours", "tint", "farbe", "farben" }) then
        local directColorParsed
        if ContainsAny(normalized, {
            "power text", "powertext", "mana text", "resource text", "power value", "mana value", "resource value",
            "color of power text", "colour of power text", "color of powertext", "colour of powertext",
            "name text color", "name text colour", "name color", "name colour",
            "color of name text", "colour of name text", "color name by class", "name text by class",
            "health text color", "health text colour", "hp text color", "hp text colour",
            "color of health text", "colour of health text", "color text by health", "text color by health",
        }) then
            directColorParsed = ParseScopedFontTextColorShortcut(normalized)
        end
        if ContainsAny(normalized, {
            "class resource color", "class resource colors", "class power color", "class power colors",
            "combo point", "combo points", "holy power", "soul shard", "soul shards", "arcane charge",
            "arcane charges", "maelstrom power", "resource color",
        }) then
            directColorParsed = A._ParseClassPowerColorShortcut and A._ParseClassPowerColorShortcut(normalized, raw)
        end
        if not directColorParsed and ContainsAny(normalized, {
            "color of mana", "colour of mana", "mana color", "mana colour", "mana power color", "mana power colour",
            "color of rage", "colour of rage", "rage color", "rage colour", "rage power color", "rage power colour",
            "color of energy", "colour of energy", "color energy", "energy color", "energy colour", "energy power color", "energy power colour",
            "color of runic power", "colour of runic power", "runic power color", "runic power colour",
            "color of insanity", "colour of insanity", "insanity color", "insanity colour", "insanity power color", "insanity power colour",
            "color of fury", "colour of fury", "fury color", "fury colour", "fury power color", "fury power colour",
            "color of pain", "colour of pain", "pain color", "pain colour", "pain power color", "pain power colour",
            "color of essence", "colour of essence", "essence color", "essence colour", "essence power color", "essence power colour",
            "color of astral power", "colour of astral power", "astral power color", "astral power colour",
            "color of lunar power", "colour of lunar power", "lunar power color", "lunar power colour",
            "color of maelstrom", "colour of maelstrom", "maelstrom color", "maelstrom colour", "maelstrom power color", "maelstrom power colour",
            "color of focus power", "colour of focus power", "focus power color", "focus power colour", "hunter focus color", "hunter focus colour",
        }) then
            directColorParsed = A._ParsePowerColorShortcut and A._ParsePowerColorShortcut(normalized, raw)
        end
        if directColorParsed then
            directColorParsed.raw = raw
            directColorParsed.normalized = normalized
            return directColorParsed
        end
    end
    if ContainsAny(normalized, { "detached power", "detached power bar", "detached mana", "detached mana bar" })
        and ContainsAny(normalized, {
            "width", "wide", "height", "tall", "frame level", "framelevel", "layer",
            "text on bar", "text on detached",
        })
    then
        local detachedPowerDetail = P.ParseDetachedPowerBarRegistryShortcut
            and P.ParseDetachedPowerBarRegistryShortcut(normalized, raw)
        if detachedPowerDetail then
            detachedPowerDetail.raw = raw
            detachedPowerDetail.normalized = normalized
            return detachedPowerDetail
        end
    end
    if ContainsAny(normalized, {
        "group border thickness", "group border size", "full group border",
        "border around group", "border around frames", "group border padding",
    }) then
        local groupNumberParsed = P.ParseGroupNumberRegistryShortcut and P.ParseGroupNumberRegistryShortcut(normalized)
        if groupNumberParsed then
            groupNumberParsed.raw = raw
            groupNumberParsed.normalized = normalized
            return groupNumberParsed
        end
    end
    if ContainsAny(normalized, {
        "castbar", "cast bar", "cast color", "cast colour", "zauberleiste",
        "interrupt color", "interrupt colour", "interrupt feedback", "interrupted cast",
        "interruptible", "kickable", "unkickable", "non interruptible", "noninterruptible",
    }) and ContainsAny(normalized, {
        "color", "colors", "colour", "colours", "green", "red", "blue", "yellow", "white", "black",
        "interrupt", "kick", "ready", "available", "cooldown",
    }) then
        local castbarColorParsed = P.ParseCastbarColorShortcut and P.ParseCastbarColorShortcut(normalized, raw)
        if castbarColorParsed then
            castbarColorParsed.raw = raw
            castbarColorParsed.normalized = normalized
            return castbarColorParsed
        end
    end
    if ContainsAny(normalized, { "castbar", "cast bar", "zauberleiste" })
        and ContainsAny(normalized, { "move", "nudge", "shift" })
        and ContainsAny(normalized, { "left", "right", "up", "down", "links", "rechts", "oben", "unten" })
    then
        local castbarMoveParsed = P.ParseGenericOffsetMove and P.ParseGenericOffsetMove(normalized)
        if castbarMoveParsed then
            castbarMoveParsed.raw = raw
            castbarMoveParsed.normalized = normalized
            return castbarMoveParsed
        end
    end
    if ContainsAny(normalized, {
        "dead text", "status text", "ghost text", "afk text", "dnd text", "offline text",
        "disconnected text", "connection text", "status icon midnight", "status icons midnight",
        "midnight status icon", "midnight status icons", "classic status icon", "classic status icons",
    }) and not ContainsAny(normalized, {
        "party", "raid", "mythic raid", "mythicraid", "group frame", "group frames",
    }) then
        local statusTextParsed = ParseGlobalStatusTextStateShortcut(normalized)
            or (P.ParseUnitStatusIconStyle and P.ParseUnitStatusIconStyle(normalized))
            or (P.ParseUnitStatusIndicatorDetail and P.ParseUnitStatusIndicatorDetail(normalized))
        if statusTextParsed then
            statusTextParsed.raw = raw
            statusTextParsed.normalized = normalized
            return statusTextParsed
        end
    end
    if ContainsAny(normalized, { "class power", "class powers", "class resource", "class resources", "combo point", "combo points" })
        and ContainsAny(normalized, { "text x", "text y", "number x", "number y", "numbers x", "numbers y", "x offset", "y offset" })
    then
        local classPowerTextOffsetParsed = ParseClassPowerTextOffsetShortcut(normalized)
        if classPowerTextOffsetParsed then
            classPowerTextOffsetParsed.raw = raw
            classPowerTextOffsetParsed.normalized = normalized
            return classPowerTextOffsetParsed
        end
    end
    if ContainsAny(normalized, {
        "party frame", "party frames", "raid frame", "raid frames",
        "mythic raid frame", "mythic raid frames", "mythicraid frame", "mythicraid frames",
        "group frame", "group frames",
    }) and ContainsAny(normalized, {
        "move", "nudge", "shift", "offset", "position", "pos", "x", "y",
    }) then
        local groupRootMoveParsed = P.ParseGroupFrameRootMove and P.ParseGroupFrameRootMove(normalized)
        if groupRootMoveParsed then
            groupRootMoveParsed.raw = raw
            groupRootMoveParsed.normalized = normalized
            return groupRootMoveParsed
        end
    end
    local groupDebuffStripeParsed = ParseGroupDebuffStripeShortcut(normalized, raw)
    if groupDebuffStripeParsed then
        groupDebuffStripeParsed.raw = raw
        groupDebuffStripeParsed.normalized = normalized
        return groupDebuffStripeParsed
    end
    if ContainsAny(normalized, {
        "party frames", "party frame", "raid frames", "raid frame",
        "mythic raid frames", "mythic raid frame", "mythicraid frames", "mythicraid frame",
        "group frames", "group frame", "preserve raid groups", "keep raid groups",
    }) then
        local groupFrameParsed = P.ParseGroupPreserveRaidGroupsShortcut
            and P.ParseGroupPreserveRaidGroupsShortcut(normalized)
        if not groupFrameParsed and ContainsAny(normalized, {
            "show", "hide", "enable", "disable", "enabled", "disabled", "turn on", "turn off",
            "from off to on", "from on to off", "off to on", "on to off",
        }) then
            groupFrameParsed = P.ParseGroupAvailabilityIntent and P.ParseGroupAvailabilityIntent(normalized)
        end
        if groupFrameParsed then
            groupFrameParsed.raw = raw
            groupFrameParsed.normalized = normalized
            return groupFrameParsed
        end
    end
    if ContainsAny(normalized, {
        "player frame", "target frame", "focus frame", "pet frame", "boss frame",
        "targettarget frame", "target target frame", "target of target frame",
        "focustarget frame", "focus target frame", "unit frame", "unit frames",
    }) then
        local unitRootParsed = ParseUnitRootVisibilityShortcut(normalized)
        if unitRootParsed then
            unitRootParsed.raw = raw
            unitRootParsed.normalized = normalized
            return unitRootParsed
        end
    end
    local exactKeyParsed = (P.ParseExactRegistryKeyShortcut and P.ParseExactRegistryKeyShortcut(normalized, raw))
        or (P.ParseExactActionKeyShortcut and P.ParseExactActionKeyShortcut(normalized, raw))
        or (P.ParseRegistryActionAliasShortcut and P.ParseRegistryActionAliasShortcut(normalized, raw))
    if exactKeyParsed then
        exactKeyParsed.raw = raw
        exactKeyParsed.normalized = normalized
        return exactKeyParsed
    end
    local priorityRegistryParsed = P.ParseRegistryPriorityShortcut and P.ParseRegistryPriorityShortcut(normalized, raw)
    if priorityRegistryParsed then
        priorityRegistryParsed.raw = raw
        priorityRegistryParsed.normalized = normalized
        return priorityRegistryParsed
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
