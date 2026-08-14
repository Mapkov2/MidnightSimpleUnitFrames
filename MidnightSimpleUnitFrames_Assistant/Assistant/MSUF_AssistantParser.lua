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
P.RootPhrases = (((A.ParserData or {}).ROOT_PARSER or {}).PHRASES or {})
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

function A._DispelOverlayAlphaValue(normalized)
    local value = FirstNumber(normalized)
    if value ~= nil then
        if value > 1 then value = value / 100 end
        if value > 1 then value = 1 end
        if value < 0.05 then value = 0.05 end
        return value
    end
    if ContainsAny(normalized, { "max", "maximum", "full opacity", "full alpha", "strongest", "highest" }) then return 1 end
    if ContainsAny(normalized, { "min", "minimum", "lowest", "weakest" }) then return 0.05 end
    if ContainsAny(normalized, { "half", "50 percent", "50%" }) then return 0.5 end
    return nil
end

local function ParseDispelOverlayOpacityShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[1]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[2]) then return nil end
    local value = A._DispelOverlayAlphaValue(normalized)
    if value == nil then return nil end

    local changes = {}
    local units = DetectUnits(normalized)
    local groups = DetectGroups(normalized)
    for i = 1, #units do
        local unit = tostring(units[i])
        local override = A.Registry and A.Registry:GetSetting("barScope." .. unit .. ".override")
        if override then changes[#changes + 1] = { setting = override, value = true } end
        local setting = A.Registry and A.Registry:GetSetting("barScope." .. unit .. ".unitDispelOverlayAlpha")
        if setting then changes[#changes + 1] = { setting = setting, value = value } end
    end
    for i = 1, #groups do
        local scope = groups[i] == "mythicraid" and "gf_mythicraid" or ("gf_" .. tostring(groups[i]))
        local setting = A.Registry and A.Registry:GetSetting(scope .. ".dispelOverlayAlpha")
        if setting then changes[#changes + 1] = { setting = setting, value = value } end
    end
    if #changes == 0 then
        local setting = A.Registry and A.Registry:GetSetting("general.unitDispelOverlayAlpha")
        if setting then changes[#changes + 1] = { setting = setting, value = value } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Dispel Overlay Opacity") or "Dispel Overlay Opacity",
        bulkSafe = #changes > 1,
        summary = "Changes dispel overlay opacity for the requested scope.",
    }
end

local function CastbarWidthModeValue(normalized)
    if ContainsAny(normalized, P.RootPhrases[3]) then return "manual" end
    if ContainsAny(normalized, P.RootPhrases[4]) then return "unitframe" end
    if ContainsAny(normalized, P.RootPhrases[5]) then return "essential" end
    if ContainsAny(normalized, P.RootPhrases[6]) then return "utility" end
    return nil
end

local function ParseCastbarWidthModeShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[7]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[8]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[9]) and not ContainsAny(normalized, P.RootPhrases[10]) then
        return nil
    end

    local value = CastbarWidthModeValue(normalized)
    if value == nil then return nil end

    local units = DetectUnits(normalized)
    if #units == 0 and ContainsAny(normalized, P.RootPhrases[11]) then
        units = { "player", "target", "focus", "boss" }
    end
    if #units == 0 then return nil end

    local keys = {
        player = "general.castbarPlayerMatchWidth",
        target = "general.castbarTargetMatchWidth",
        focus = "general.castbarFocusMatchWidth",
        boss = "general.bossCastbarMatchWidth",
    }
    local changes = {}
    local seen = {}
    for i = 1, #units do
        local key = keys[units[i]]
        if key and not seen[key] then
            seen[key] = true
            local setting = A.Registry and A.Registry:GetSetting(key)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Castbar Width Mode") or "Castbar Width Mode",
        bulkSafe = #changes > 1,
        summary = "Changes unit Cast Bar width mode.",
    }
end

local function ParseGroupAuraLaneOffsetShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[12]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[13]) then return nil end

    local lane
    if ContainsAny(normalized, P.RootPhrases[14]) then lane = "buff" end
    if ContainsAny(normalized, P.RootPhrases[15]) then
        if lane ~= nil then return nil end
        lane = "debuff"
    end
    if not lane then return nil end

    local axis
    if ContainsAny(normalized, P.RootPhrases[16]) then
        axis = "x"
    elseif ContainsAny(normalized, P.RootPhrases[17]) then
        axis = "y"
    end
    if not axis then return nil end

    local value = FirstNumber(normalized)
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[18]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. ".auras." .. lane .. "." .. axis)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Group Aura Offset") or "Group Aura Offsets",
        bulkSafe = #changes > 1,
        summary = "Changes group aura lane X/Y offset.",
    }
end

local function ParseGroupAuraLaneTextOffsetShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[19]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[20]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[21]) then return nil end

    local lane
    if ContainsAny(normalized, P.RootPhrases[22]) then lane = "buff" end
    if ContainsAny(normalized, P.RootPhrases[23]) then
        if lane ~= nil then return nil end
        lane = "debuff"
    end
    if not lane then return nil end

    local prefix
    if ContainsAny(normalized, P.RootPhrases[24]) then
        prefix = "cooldown"
    elseif ContainsAny(normalized, P.RootPhrases[25]) then
        prefix = "stack"
    end
    if not prefix then return nil end

    local axis
    if ContainsAny(normalized, P.RootPhrases[26]) then
        axis = "X"
    elseif ContainsAny(normalized, P.RootPhrases[27]) then
        axis = "Y"
    end
    if not axis then return nil end

    local value = FirstNumber(normalized)
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[28]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr = prefix .. axis
    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. ".auras." .. lane .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Group Aura Text Offset") or "Group Aura Text Offsets",
        bulkSafe = #changes > 1,
        summary = "Changes group aura cooldown/stack text X/Y offset.",
    }
end

local function ParseGroupAuraLaneTextSizeShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[29]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[30]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[31]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[32]) then return nil end

    local lane
    if ContainsAny(normalized, P.RootPhrases[33]) then lane = "buff" end
    if ContainsAny(normalized, P.RootPhrases[34]) then
        if lane ~= nil then return nil end
        lane = "debuff"
    end
    if not lane then return nil end

    local attr
    if ContainsAny(normalized, P.RootPhrases[35]) then
        attr = "cooldownSize"
    elseif ContainsAny(normalized, P.RootPhrases[36]) then
        attr = "stackSize"
    end
    if not attr then return nil end

    local value = FirstNumber(normalized)
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[37]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. ".auras." .. lane .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Group Aura Text Size") or "Group Aura Text Sizes",
        bulkSafe = #changes > 1,
        summary = "Changes group aura cooldown/stack text font size.",
    }
end

local function ParseGroupAuraLaneBooleanShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[38]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[39]) then return nil end

    local attr
    if ContainsAny(normalized, P.RootPhrases[40]) then
        attr = "showCooldown"
    elseif ContainsAny(normalized, P.RootPhrases[41]) then
        attr = "showStacks"
    elseif ContainsAny(normalized, P.RootPhrases[42]) then
        attr = "showCooldownSwipe"
    end
    if not attr then return nil end

    local lane
    if ContainsAny(normalized, P.RootPhrases[43]) then lane = "buff" end
    if ContainsAny(normalized, P.RootPhrases[44]) then
        if lane ~= nil then return nil end
        lane = "debuff"
    end
    if not lane then return nil end

    local value = DetectBoolean(normalized)
    if value == nil and ContainsAny(normalized, P.RootPhrases[45]) then value = true end
    if value == nil and ContainsAny(normalized, P.RootPhrases[46]) then value = false end
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[47]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. ".auras." .. lane .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Group Aura Toggle") or "Group Aura Toggles",
        bulkSafe = #changes > 1,
        summary = "Changes group aura cooldown/stack visibility.",
    }
end

local function ParseGroupAuraCooldownDarkenShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[48]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[49]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[50]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[51]) then return nil end

    local value = DetectBoolean(normalized)
    if value == nil and ContainsAny(normalized, P.RootPhrases[52]) then value = true end
    if value == nil and ContainsAny(normalized, P.RootPhrases[53]) then value = false end
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[54]) then
        groups = { "party", "raid" }
    end
    if #groups == 0 then return nil end

    local changes = {}
    local seen = {}
    local unsupportedMythic = false
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if scope == "party" or scope == "raid" then
            local key = "gf_" .. scope .. ".cooldownSwipeDarkenOnLoss"
            if not seen[key] then
                seen[key] = true
                local setting = A.Registry and A.Registry:GetSetting(key)
                if setting then changes[#changes + 1] = { setting = setting, value = value } end
            end
        elseif scope == "mythicraid" then
            unsupportedMythic = true
        end
    end
    if #changes == 0 and unsupportedMythic then
        return {
            kind = "answer",
            status = "info",
            text = "Aura Cooldown Darkens on Loss exists for Party and Raid group aura settings. Mythic Raid does not expose a separate toggle for that option, so I did not guess or change another setting.",
            summary = "Explains that Mythic Raid has no separate aura cooldown darken-on-loss toggle.",
        }
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Aura Cooldown Darkens on Loss") or "Aura Cooldown Darkens on Loss",
        bulkSafe = #changes > 1,
        summary = "Changes whether group aura cooldown swipes darken when an aura is missing or lost.",
    }
end

local function ParseExplicitUnitBarOpacityShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[55]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[56]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[57]) then return nil end

    local units = DetectUnits(normalized)
    if #units == 0 then return nil end
    local value = FirstNumber(normalized)
    if value == nil then return nil end
    if value > 1 then value = value / 100 end

    local powerOpacity = ContainsAny(normalized, P.RootPhrases[58])
    local backgroundOpacity = ContainsAny(normalized, P.RootPhrases[59])
    local attr = powerOpacity and backgroundOpacity and "powerBarBgAlpha"
        or powerOpacity and "powerBarAlpha"
        or backgroundOpacity and "hpBgAlpha"
        or "hpBarAlpha"

    local changes = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        local setting = A.Registry and A.Registry:GetSetting(unit .. "." .. attr)
        if setting then changes[#changes + 1] = { setting = setting, value = value } end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = powerOpacity and backgroundOpacity and "Set unit resource background opacity"
            or powerOpacity and "Set unit power bar opacity"
            or backgroundOpacity and "Set unit background opacity"
            or "Set unit opacity",
        bulkSafe = #changes > 1,
        summary = powerOpacity and backgroundOpacity and "Sets the resource bar background opacity for the requested unit frame."
            or powerOpacity and "Sets the power bar opacity for the requested unit frame."
            or backgroundOpacity and "Sets the bar background opacity for the requested unit frame."
            or "Sets the HP bar opacity for the requested unit frame.",
    }
end

local function ParseGroupAvailabilityFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[60]) then
        return nil
    end
    if not ContainsAny(normalized, P.RootPhrases[61]) then
        return nil
    end
    if ContainsAny(normalized, P.RootPhrases[62]) then
        return nil
    end

    local attr
    local hideSemantic = false
    if ContainsAny(normalized, P.RootPhrases[63]) then
        attr = "hideOfflineInCombat"
        hideSemantic = true
    elseif ContainsAny(normalized, P.RootPhrases[64]) then
        attr = "hideOfflineEnabled"
        hideSemantic = true
    elseif ContainsAny(normalized, P.RootPhrases[65]) then
        attr = "hideInClientScene"
        hideSemantic = true
    elseif ContainsAny(normalized, P.RootPhrases[66]) then
        attr = "hideInHousing"
        hideSemantic = true
    elseif ContainsAny(normalized, P.RootPhrases[67]) then
        attr = "showPlayer"
    elseif ContainsAny(normalized, P.RootPhrases[68]) then
        attr = "showSolo"
    elseif ContainsAny(normalized, P.RootPhrases[69]) then
        attr = "clickCastEnabled"
    elseif ContainsAny(normalized, P.RootPhrases[70]) then
        attr = "enabled"
    end
    if not attr then return nil end

    local fromToValue
    if ContainsAny(normalized, P.RootPhrases[71]) then
        fromToValue = true
    elseif ContainsAny(normalized, P.RootPhrases[72]) then
        fromToValue = false
    end

    local value
    if fromToValue ~= nil then
        value = fromToValue
    elseif hideSemantic then
        if ContainsAny(normalized, P.RootPhrases[73]) then
            value = false
        elseif ContainsAny(normalized, P.RootPhrases[74]) then
            value = true
        end
        if value == nil then value = true end
    else
        if ContainsAny(normalized, P.RootPhrases[75]) then
            value = false
        elseif ContainsAny(normalized, P.RootPhrases[76]) then
            value = true
        end
        if value == nil and DetectBoolean then value = DetectBoolean(normalized) end
    end
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[77]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Group availability") or "Group availability",
        bulkSafe = #changes > 1,
        summary = "Changes group-frame visibility.",
    }
end

local function GroupBlizzardFallbackValue(normalized)
    local target = P.TargetAfterLastConnector and P.TargetAfterLastConnector(normalized) or nil
    local function valueIn(text)
        if not text or text == "" then return nil end
        if ContainsAny(text, P.RootPhrases[78]) then
            return "AUTO"
        end
        if ContainsAny(text, P.RootPhrases[79]) then
            return "SHOW"
        end
        if ContainsAny(text, P.RootPhrases[80]) then
            return "NONE"
        end
        return nil
    end

    local value = valueIn(target)
    if value then return value end
    if ContainsAny(normalized, P.RootPhrases[81]) then
        return "SHOW"
    end
    if ContainsAny(normalized, P.RootPhrases[82]) then
        return "NONE"
    end
    return valueIn(normalized)
end

local function ParseGroupBlizzardFallbackFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[83]) then
        return nil
    end
    if ContainsAny(normalized, P.RootPhrases[84]) then
        return nil
    end

    local value = GroupBlizzardFallbackValue(normalized)
    if not value then return nil end
    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[85]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. ".blizzardFallbackMode")
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Blizzard Fallback Mode") or "Blizzard Fallback Mode",
        bulkSafe = #changes > 1,
        summary = "Changes what Blizzard group frames do when MSUF group frames are disabled.",
    }
end

local function ParseGroupHideOfflineDelayFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[86]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[87]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[88]) then
        return nil
    end
    local value = FirstNumber(normalized)
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[89]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local enabled = A.Registry and A.Registry:GetSetting("gf_" .. scope .. ".hideOfflineEnabled")
            if enabled then changes[#changes + 1] = { setting = enabled, value = true } end
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. ".hideOfflineDelay")
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Hide Offline Delay") or "Hide Offline Delay",
        bulkSafe = #changes > 1,
        summary = "Changes how long group frames wait before hiding offline members.",
    }
end

local function ParseGroupReverseFillFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[90]) then
        return nil
    end
    if ContainsAny(normalized, P.RootPhrases[91]) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[92]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local value
    local boolValue = DetectBoolean(normalized)
    if ContainsAny(normalized, P.RootPhrases[93]) then
        value = false
    elseif boolValue ~= nil then
        value = boolValue
    elseif ContainsAny(normalized, P.RootPhrases[94]) then
        value = true
    end
    if value == nil then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. ".reverseFill")
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Reverse Health Fill") or "Reverse Health Fill",
        bulkSafe = #changes > 1,
        summary = "Changes group-frame health bar fill direction.",
    }
end

local function ParseUnitReverseFillFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[95]) then
        return nil
    end
    if ContainsAny(normalized, P.RootPhrases[96]) then
        return nil
    end

    local units = DetectUnits(normalized)
    if #units == 0 then return nil end

    local value
    local boolValue = DetectBoolean(normalized)
    if ContainsAny(normalized, P.RootPhrases[97]) then
        value = false
    elseif boolValue ~= nil then
        value = boolValue
    elseif ContainsAny(normalized, P.RootPhrases[98]) then
        value = true
    end
    if value == nil then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        if unit ~= "" and not seen[unit] then
            seen[unit] = true
            local setting = A.Registry and A.Registry:GetSetting(unit .. ".reverseFillBars")
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Reverse Fill Direction") or "Reverse Fill Direction",
        bulkSafe = #changes > 1,
        summary = "Changes unit-frame health bar reverse fill direction.",
    }
end

local function ParseUnitSimpleBooleanFastShortcut(normalized)
    if ContainsAny(normalized, P.RootPhrases[99]) then
        return nil
    end
    if ContainsAny(normalized, P.RootPhrases[100]) then
        return nil
    end

    local attr
    local label
    if ContainsAny(normalized, P.RootPhrases[101]) then
        attr = "powerSmoothFill"
        label = "Power Bar Smooth Fill"
    elseif ContainsAny(normalized, P.RootPhrases[102]) then
        attr = "smoothFill"
        label = "Smooth Health Fill"
    elseif ContainsAny(normalized, P.RootPhrases[103]) then
        attr = "showName"
        label = "Name"
    else
        return nil
    end

    local value = DetectBoolean(normalized)
    if value == nil then return nil end

    local units = DetectUnits(normalized)
    if #units == 0 then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        if unit ~= "" and not seen[unit] then
            seen[unit] = true
            local setting = A.Registry and A.Registry:GetSetting(unit .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or label) or label,
        bulkSafe = #changes > 1,
        summary = "Changes a simple unit-frame visibility/fill toggle.",
    }
end

local function ParseUnitStatusDetailFastShortcut(normalized)
    if ContainsAny(normalized, P.RootPhrases[104]) then
        return nil
    end
    if not ContainsAny(normalized, P.RootPhrases[105]) then
        return nil
    end

    local wantsAnchor = ContainsAny(normalized, P.RootPhrases[106])
    local wantsX = ContainsAny(normalized, P.RootPhrases[107])
    local wantsY = ContainsAny(normalized, P.RootPhrases[108])
    local wantsSize = ContainsAny(normalized, P.RootPhrases[109])
    local wantsLayer = ContainsAny(normalized, P.RootPhrases[110])
    local wantsStyle = ContainsAny(normalized, P.RootPhrases[111])
    local wantsVisibility = ContainsAny(normalized, P.RootPhrases[112])
    if not (wantsAnchor or wantsX or wantsY or wantsSize or wantsLayer or wantsStyle or wantsVisibility) then return nil end

    local units = DetectUnits(normalized)
    if #units == 0 then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        if unit ~= "" and not seen[unit] then
            seen[unit] = true
            local spec = A.ResolveUnitStatusSpec and A.ResolveUnitStatusSpec(unit, normalized) or nil
            local attr
            if spec then
                if wantsX then
                    attr = spec.x
                elseif wantsY then
                    attr = spec.y
                elseif wantsAnchor then
                    attr = spec.anchor
                elseif wantsSize then
                    attr = spec.size
                elseif wantsLayer then
                    attr = spec.layer
                elseif wantsStyle then
                    attr = "raidGroupNameStyle"
                elseif wantsVisibility then
                    attr = spec.show
                end
            end
            local setting = attr and A.Registry and A.Registry:GetSetting(unit .. "." .. tostring(attr)) or nil
            if setting then
                local value
                local relativeDelta
                if wantsLayer then
                    local amount = FirstNumber(normalized) or 1
                    if ContainsAny(normalized, P.RootPhrases[113]) then
                        relativeDelta = -amount
                    elseif ContainsAny(normalized, P.RootPhrases[114]) then
                        relativeDelta = amount
                    end
                end
                if setting.type == "boolean" then
                    value = DetectBoolean(normalized)
                    if value == nil then value = true end
                elseif setting.type == "number" then
                    if relativeDelta == nil then
                        value = FirstNumber(normalized)
                    end
                elseif P.ValueForRegistrySetting then
                    value = P.ValueForRegistrySetting(setting, normalized, normalized)
                end
                if value ~= nil or relativeDelta ~= nil then
                    changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta }
                end
            end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Unit Frame Status Detail") or "Unit Frame Status Detail",
        bulkSafe = #changes > 1,
        summary = "Changes a unit-frame status indicator detail option.",
    }
end

local function ParseGroupSimpleBooleanFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[115]) then
        return nil
    end
    if ContainsAny(normalized, P.RootPhrases[116]) then
        return nil
    end

    local attr
    local label
    if ContainsAny(normalized, P.RootPhrases[117]) then
        attr = "powerSmoothFill"
        label = "Power Smooth Fill"
    elseif ContainsAny(normalized, P.RootPhrases[118]) then
        attr = "smoothFill"
        label = "Smooth Health Fill"
    elseif ContainsAny(normalized, P.RootPhrases[119]) then
        attr = "ciEnabled"
        label = "Corner Indicators"
    elseif ContainsAny(normalized, P.RootPhrases[120]) then
        attr = "showGroupNumber"
        label = "Group Number"
    else
        return nil
    end

    local value = DetectBoolean(normalized)
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or label) or label,
        bulkSafe = #changes > 1,
        summary = "Changes a simple group-frame visibility/fill toggle.",
    }
end

local function GroupCornerCustomFilterValue(text)
    if ContainsAny(text, P.RootPhrases[121]) then return "HELPFUL|PLAYER" end
    if ContainsAny(text, P.RootPhrases[122]) then return "HARMFUL|PLAYER" end
    if ContainsAny(text, P.RootPhrases[123]) then return "HELPFUL" end
    if ContainsAny(text, P.RootPhrases[124]) then return "HARMFUL" end
    return nil
end

local function GroupCornerCustomValueAfterTo(raw, normalized)
    local source = tostring(raw or "")
    local value = source:match("%s+[Tt][Oo]%s+(.+)$")
        or source:match("%s+[Aa][Ss]%s+(.+)$")
        or tostring(normalized or ""):match("%s+to%s+(.+)$")
        or tostring(normalized or ""):match("%s+as%s+(.+)$")
    value = Trim(value or "")
    if value == "" then return nil end
    return value
end

local function ParseGroupCornerCustomFastShortcut(normalized, raw)
    if not ContainsAny(normalized, P.RootPhrases[125]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[126]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[127]) then return nil end

    local groups = DetectGroups(normalized)
    if #groups ~= 1 then return nil end

    local slot = A.ResolveGroupCornerSlot and A.ResolveGroupCornerSlot(normalized) or nil
    local slotKey = slot and slot.key
    if not slotKey or slotKey == "" then return nil end

    local attr
    local value
    if ContainsAny(normalized, P.RootPhrases[128]) then
        attr = "filter"
        value = GroupCornerCustomFilterValue(tostring(raw or ""):lower() .. " " .. normalized)
    elseif ContainsAny(normalized, P.RootPhrases[129]) then
        attr = "mode"
        if ContainsAny(normalized, P.RootPhrases[130]) then
            value = "missing"
        elseif ContainsAny(normalized, P.RootPhrases[131]) then
            value = "present"
        end
    elseif ContainsAny(normalized, P.RootPhrases[132]) then
        attr = "spells"
        value = GroupCornerCustomValueAfterTo(raw, normalized)
    end
    if not attr or value == nil then return nil end

    local setting = A.Registry and A.Registry:GetSetting("gf_" .. tostring(groups[1]) .. ".ciCustom" .. tostring(slotKey) .. "." .. attr)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Corner Custom " .. tostring(attr),
        summary = "Changes a group-frame corner custom spell indicator field.",
    }
end

local function ParseGroupTextureFastShortcut(normalized, raw)
    if not ContainsAny(normalized, P.RootPhrases[133]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[134]) then return nil end

    local groups = DetectGroups(normalized)
    if #groups ~= 1 then return nil end

    local key
    if ContainsAny(normalized, P.RootPhrases[135]) then
        key = "barScope.gf_" .. tostring(groups[1]) .. ".barBackgroundTexture"
    elseif ContainsAny(normalized, P.RootPhrases[136]) then
        key = "gf_" .. tostring(groups[1]) .. ".barBackgroundTexture"
    elseif ContainsAny(normalized, P.RootPhrases[137]) then
        key = "gf_" .. tostring(groups[1]) .. ".barTexture"
    elseif ContainsAny(normalized, P.RootPhrases[138]) then
        key = "barScope.gf_" .. tostring(groups[1]) .. ".barTexture"
    else
        return nil
    end

    local value = GroupCornerCustomValueAfterTo(raw, normalized)
    if value == nil then return nil end
    local setting = A.Registry and A.Registry:GetSetting(key)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Group Texture",
        summary = "Changes a group-frame texture setting.",
    }
end

local function GroupNameClipSideValue(normalized)
    local target = P.TargetAfterLastConnector and P.TargetAfterLastConnector(normalized) or nil
    local function valueIn(text)
        if not text or text == "" then return nil end
        if ContainsAny(text, P.RootPhrases[139]) then
            return "LEFT"
        end
        if ContainsAny(text, P.RootPhrases[140]) then
            return "RIGHT"
        end
        return nil
    end
    return valueIn(target) or valueIn(normalized)
end

local function ParseGroupNameTextFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[141]) then return nil end
    local hideNameDeadOffline = ContainsAny(normalized, P.RootPhrases[142])
    if ContainsAny(normalized, P.RootPhrases[143]) then
        return nil
    end

    local attr
    local value
    if hideNameDeadOffline then
        attr = "hideNameOnDeadOffline"
        if ContainsAny(normalized, P.RootPhrases[144]) then
            value = false
        elseif ContainsAny(normalized, P.RootPhrases[145]) then
            value = true
        end
        if value == nil then value = true end
    elseif ContainsAny(normalized, P.RootPhrases[146]) then
        attr = "nameMaxChars"
        value = FirstNumber(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, P.RootPhrases[147]) then
        attr = "nameShortenEnabled"
        value = DetectBoolean(normalized)
        if value == nil then value = not ContainsAny(normalized, P.RootPhrases[148]) end
    elseif ContainsAny(normalized, P.RootPhrases[149]) then
        attr = "nameClipSide"
        value = GroupNameClipSideValue(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, P.RootPhrases[150]) then
        attr = "nameNoEllipsis"
        if ContainsAny(normalized, P.RootPhrases[151]) then
            value = false
        elseif ContainsAny(normalized, P.RootPhrases[152]) then
            value = true
        end
        if value == nil then value = DetectBoolean(normalized) end
    end
    if not attr then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[153]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Group Name Text") or "Group Name Text",
        bulkSafe = #changes > 1,
        summary = "Changes group-frame name shortening settings.",
    }
end

local function ParseGroupPowerBarEnabledFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[154]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[155]) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[156]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local value = DetectBoolean(normalized)
    if value == nil then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. ".powerBarEnabled")
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Power Bar") or "Power Bars",
        bulkSafe = #changes > 1,
        summary = "Changes the group-frame power/resource bar master toggle.",
    }
end

local function ParseGroupRolePowerFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[157]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[158]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[159]) then
        return nil
    end

    local attr
    if ContainsAny(normalized, P.RootPhrases[160]) then
        attr = "powerShowTank"
    elseif ContainsAny(normalized, P.RootPhrases[161]) then
        attr = "powerShowHealer"
    elseif ContainsAny(normalized, P.RootPhrases[162]) then
        attr = "powerShowDamager"
    end
    if not attr then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[163]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local value = DetectBoolean(normalized)
    if value == nil then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Role Power") or "Role Power",
        bulkSafe = #changes > 1,
        summary = "Changes which group member roles show power/resource bars.",
    }
end

local function ParseGroupLayoutNumberFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[164]) then
        return nil
    end
    if ContainsAny(normalized, P.RootPhrases[165]) then
        return nil
    end

    local attr
    if normalized:find("column", 1, true) and normalized:find("after", 1, true)
        and (normalized:find("member", 1, true) or normalized:find("player", 1, true))
    then
        attr = "unitsPerColumn"
    elseif ContainsAny(normalized, P.RootPhrases[166]) then
        attr = "unitsPerColumn"
    elseif ContainsAny(normalized, P.RootPhrases[167]) then
        attr = "maxColumns"
    elseif ContainsAny(normalized, P.RootPhrases[168]) then
        attr = "powerHeight"
    elseif ContainsAny(normalized, P.RootPhrases[169]) then
        attr = "spacing"
    elseif ContainsAny(normalized, P.RootPhrases[170]) then
        attr = "width"
    elseif ContainsAny(normalized, P.RootPhrases[171]) then
        attr = "height"
    end
    if not attr then return nil end

    local value = FirstNumber(normalized)
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    local allGroups = false
    for i = 1, #(P.RootPhrases[172] or {}) do
        if HasPhrase(normalized, P.RootPhrases[172][i]) then
            allGroups = true
            break
        end
    end
    -- Fuzzy matching must not turn unrelated scopes such as "boss frames"
    -- into "all group frames" and silently default the mutation to Party.
    if #groups == 0 and allGroups then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Group Layout") or "Group Layout",
        bulkSafe = #changes > 1,
        summary = "Changes group-frame layout numeric settings.",
    }
end

local function GroupGrowthValue(normalized)
    local target = P.TargetAfterLastConnector and P.TargetAfterLastConnector(normalized) or nil
    local function valueIn(text)
        if not text or text == "" then return nil end
        if text:find("right then down", 1, true) or text:find("right and down", 1, true) then return "RIGHT" end
        if text:find("left then down", 1, true) or text:find("left and down", 1, true) then return "LEFT" end
        if text:find("down then right", 1, true) or text:find("down and right", 1, true) then return "DOWN" end
        if text:find("up then right", 1, true) or text:find("up and right", 1, true) then return "UP" end
        if ContainsAny(text, P.RootPhrases[173]) then return "DOWN" end
        if ContainsAny(text, P.RootPhrases[174]) then return "UP" end
        if ContainsAny(text, P.RootPhrases[175]) then return "RIGHT" end
        if ContainsAny(text, P.RootPhrases[176]) then return "LEFT" end
        return nil
    end
    return valueIn(target) or valueIn(normalized)
end

local function GroupSortModeValue(normalized)
    local target = P.TargetAfterLastConnector and P.TargetAfterLastConnector(normalized) or nil
    local function valueIn(text)
        if not text or text == "" then return nil end
        if ContainsAny(text, P.RootPhrases[177]) then return "GROUP_ROLE" end
        if ContainsAny(text, P.RootPhrases[178]) then return "INDEX" end
        if ContainsAny(text, P.RootPhrases[179]) then return "ROLE" end
        if ContainsAny(text, P.RootPhrases[180]) then return "GROUP" end
        if ContainsAny(text, P.RootPhrases[181]) then return "NAME" end
        return nil
    end
    return valueIn(target) or valueIn(normalized)
end

local function GroupRoleOrderValue(normalized)
    local target = P.TargetAfterLastConnector and P.TargetAfterLastConnector(normalized) or nil
    local function compactOrder(text)
        text = tostring(text or ""):lower()
        local out = {}
        for word in text:gmatch("%w+") do
            if word == "tank" or word == "tanks" then
                out[#out + 1] = "TANK"
            elseif word == "healer" or word == "healers" or word == "heal" then
                out[#out + 1] = "HEALER"
            elseif word == "dps" or word == "damager" or word == "damagers" or word == "damage" then
                out[#out + 1] = "DAMAGER"
            end
            if #out == 3 then break end
        end
        if #out ~= 3 then return nil end
        local seen = {}
        for i = 1, 3 do
            if seen[out[i]] then return nil end
            seen[out[i]] = true
        end
        return table.concat(out, ",")
    end
    return compactOrder(target) or compactOrder(normalized)
end

local function ParseGroupOrderingFastShortcut(normalized)
    if ContainsAny(normalized, P.RootPhrases[182]) then return nil end

    local attr
    local value
    if normalized:find("myself", 1, true)
        and (normalized:find("first", 1, true) or normalized:find("at the top", 1, true))
    then
        attr = "playerFirstInRole"
        value = true
    elseif ContainsAny(normalized, P.RootPhrases[183]) then
        attr = "roleOrder"
        value = GroupRoleOrderValue(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, P.RootPhrases[184]) then
        attr = "growth"
        value = GroupGrowthValue(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, P.RootPhrases[185]) then
        attr = "sortMode"
        value = GroupSortModeValue(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, P.RootPhrases[188]) then
        attr = "playerFirstInRole"
        value = DetectBoolean(normalized)
        if value == nil then value = not ContainsAny(normalized, P.RootPhrases[189]) end
    elseif ContainsAny(normalized, P.RootPhrases[186]) then
        attr = "sortByRole"
        value = DetectBoolean(normalized)
        if value == nil then value = not ContainsAny(normalized, P.RootPhrases[187]) end
    elseif ContainsAny(normalized, P.RootPhrases[190]) then
        attr = "preserveRaidGroups"
        value = DetectBoolean(normalized)
        if value == nil then value = not ContainsAny(normalized, P.RootPhrases[191]) end
    end
    if not attr then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[192]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Group Ordering") or "Group Ordering",
        bulkSafe = #changes > 1,
        summary = "Changes group-frame ordering options.",
    }
end

local function GroupScaleModeValue(normalized)
    local target = P.TargetAfterLastConnector and P.TargetAfterLastConnector(normalized) or nil
    local function valueIn(text)
        if not text or text == "" then return nil end
        if ContainsAny(text, P.RootPhrases[193]) then return "auto" end
        if ContainsAny(text, P.RootPhrases[194]) then return "manual" end
        if ContainsAny(text, P.RootPhrases[195]) then return "off" end
        if ContainsAny(text, P.RootPhrases[196]) then return "manual" end
        return nil
    end
    return valueIn(target) or valueIn(normalized)
end

local function NumberAfterLastConnector(normalized)
    local target = P.TargetAfterLastConnector and P.TargetAfterLastConnector(normalized) or nil
    local value = target and FirstNumber(target) or nil
    if value ~= nil then return value end
    return FirstNumber(normalized)
end

local function ParseGroupScalingFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[197]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[198]) then
        return nil
    end

    local attr
    local value
    if normalized:find("automatic", 1, true) or normalized:find("auto scaling", 1, true) then
        attr = "frameScaleMode"
        value = "auto"
    elseif ContainsAny(normalized, P.RootPhrases[199]) then
        attr = "frameScaleMode"
        value = GroupScaleModeValue(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, P.RootPhrases[200]) and FirstNumber(normalized) == nil then
        attr = "frameScaleEnabled"
        value = DetectBoolean(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, P.RootPhrases[201]) then
        attr = "scaleOver25"
        value = NumberAfterLastConnector(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[202]) then
        attr = "scaleAt25"
        value = NumberAfterLastConnector(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[203]) then
        attr = "scaleAt20"
        value = NumberAfterLastConnector(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[204]) then
        attr = "scaleAt10"
        value = NumberAfterLastConnector(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[205]) then
        attr = "frameScaleManual"
        value = NumberAfterLastConnector(normalized)
    end
    if not attr or value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[206]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Group Frame Scaling") or "Group Frame Scaling",
        bulkSafe = #changes > 1,
        summary = "Changes group-frame scaling settings.",
    }
end

local function ParseGlobalUiScaleFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[207]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[208]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[209]) then return nil end

    local key
    local value
    local booleanValue = DetectBoolean(normalized)
    if ContainsAny(normalized, P.RootPhrases[210])
        or (booleanValue ~= nil and FirstNumber(normalized) == nil)
    then
        key = "general.globalUiScaleEnabled"
        value = booleanValue
        if value == nil then return nil end
    else
        key = "general.globalUiScale"
        value = NumberAfterLastConnector(normalized)
        if value == nil then return nil end
        if value > 1.5 then value = value / 100 end
    end

    local setting = A.Registry and A.Registry:GetSetting(key)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Global UI Scale",
        summary = key == "general.globalUiScaleEnabled" and "Changes the global UI scale override toggle." or "Changes the global UI scale value.",
    }
end

local function ParseDashboardScaleFastShortcut(normalized)
    if ContainsAny(normalized, P.RootPhrases[211]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[212]) then return nil end

    local key
    local label
    if ContainsAny(normalized, P.RootPhrases[213]) then
        key = "general.slashMenuScale"
        label = "MSUF Menu Scale"
    elseif ContainsAny(normalized, P.RootPhrases[214]) then
        key = "general.msufUiScale"
        label = "MSUF Frame Scale"
    else
        return nil
    end

    local setting = A.Registry and A.Registry:GetSetting(key)
    if not setting then return nil end
    local relativeDelta = P.RelativeNumberDeltaForText and P.RelativeNumberDeltaForText(setting, normalized, 5) or nil
    local value
    if relativeDelta == nil then
        value = FirstNumber(normalized)
        if value ~= nil and value > 1.5 then value = value / 100 end
    end
    if value == nil and relativeDelta == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
        label = label,
        summary = "Adjusts Dashboard scale.",
    }
end

local function ParseGlobalFontColorFastShortcut(normalized, raw)
    if not ContainsAny(normalized, P.RootPhrases[215]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[216]) then return nil end
    local setting = A.Registry and A.Registry:GetSetting("general.customFontColor")
    if not setting then return nil end
    local extract = P.ExtractColor
    if type(extract) ~= "function" then return nil end
    local r, g, b, label = extract(raw or normalized, normalized)
    if not r then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = { r = r, g = g, b = b, label = label } } },
        label = setting.label or "Global Font Color",
        summary = "Changes the global custom font color.",
    }
end

local CLASS_COLOR_FAST_TOKENS = {
    { "death knight", "DEATHKNIGHT" },
    { "demon hunter", "DEMONHUNTER" },
    { "warrior", "WARRIOR" },
    { "paladin", "PALADIN" },
    { "hunter", "HUNTER" },
    { "rogue", "ROGUE" },
    { "priest", "PRIEST" },
    { "deathknight", "DEATHKNIGHT" },
    { "shaman", "SHAMAN" },
    { "mage", "MAGE" },
    { "warlock", "WARLOCK" },
    { "monk", "MONK" },
    { "druid", "DRUID" },
    { "demonhunter", "DEMONHUNTER" },
    { "evoker", "EVOKER" },
}

local function ParseClassColorFastShortcut(normalized, raw)
    local hasClassColorPhrase = ContainsAny(normalized, P.RootPhrases[217])
    local hasMutationVerb = ContainsAny(normalized, P.RootPhrases[218])
    local token
    for i = 1, #CLASS_COLOR_FAST_TOKENS do
        if HasPhrase(normalized, CLASS_COLOR_FAST_TOKENS[i][1]) then
            token = CLASS_COLOR_FAST_TOKENS[i][2]
            break
        end
    end
    if not token then return nil end
    if not hasClassColorPhrase and not hasMutationVerb then return nil end
    -- A numbered resource pip ("Arcane Mage Arcane Charges 1 Color") is its own
    -- classPowerColorOverrides setting, which the exact-alias lane resolves.
    -- This lane owns only the single class BAR colour, so claiming that wording
    -- wrote Mage Class Bar Color and left the named charge untouched.
    if normalized:find("%f[%w]charges?%s+%d")
        or normalized:find("%f[%w]points?%s+%d")
        or normalized:find("%f[%w]runes?%s+%d")
        or normalized:find("%f[%w]shards?%s+%d")
        or normalized:find("%f[%w]chi%s+%d")
        or normalized:find("%f[%w]essences?%s+%d")
        or normalized:find("%f[%w]orbs?%s+%d")
        or normalized:find("%f[%w]holy%s+power%s+%d")
    then
        return nil
    end
    local setting = A.Registry and A.Registry:GetSetting("classColors." .. token)
    if not setting then return nil end
    local extract = P.ExtractColor
    if type(extract) ~= "function" then return nil end
    local r, g, b, label = extract(raw or normalized, normalized)
    if not r then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = { r = r, g = g, b = b, label = label } } },
        label = setting.label or "Class Bar Color",
        summary = "Changes a class bar color override.",
    }
end

local function ParseGlobalBarBackgroundFastShortcut(normalized, raw)
    if ContainsAny(normalized, P.RootPhrases[220]) then
        if ContainsAny(normalized, P.RootPhrases[221]) then return nil end
        local setting = A.Registry and A.Registry:GetSetting("general.powerBarBgMatchBarColor")
        if not setting then return nil end
        local value = DetectBoolean(normalized)
        if value == nil then value = true end
        return {
            kind = "changes",
            changes = { { setting = setting, value = value } },
            label = setting.label or "Power Background Matches HP",
            summary = "Changes whether the power-bar background follows the HP bar color.",
        }
    end

    if ContainsAny(normalized, P.RootPhrases[222]) then return nil end

    local key
    local value
    if ContainsAny(normalized, P.RootPhrases[223]) then
        key = "general.classBarBgColor"
        local extract = P.ExtractColor
        if type(extract) ~= "function" then return nil end
        local r, g, b, label = extract(raw or normalized, normalized)
        if not r then return nil end
        value = { r = r, g = g, b = b, label = label }
    elseif ContainsAny(normalized, P.RootPhrases[224]) then
        key = "general.barBgMatchHPColor"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, P.RootPhrases[225]) then
        key = "general.barBgClassColor"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    else
        return nil
    end

    local setting = A.Registry and A.Registry:GetSetting(key)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Bar Background",
        summary = "Changes global bar background color behavior.",
    }
end

local function ParseDarkModeCustomColorFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[226]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[227]) then return nil end
    local value = DetectBoolean(normalized)
    if value == nil then return nil end
    local setting = A.Registry and A.Registry:GetSetting("general.darkBgCustomColor")
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Custom Color In Dark Mode",
        summary = "Changes the dark-mode custom background color toggle.",
    }
end

local GLOBAL_BAR_COLOR_SCOPE_BLOCKERS = {
    "player", "target", "focus", "pet", "boss", "targettarget", "target of target", "focustarget", "focus target",
    "party", "raid", "mythic raid", "mythicraid", "group frame", "group frames",
    "castbar", "cast bar", "class power", "class resource",
}

P.BAR_OUTLINE_COLOR_SEMANTIC_BLOCKERS = P.BAR_OUTLINE_COLOR_SEMANTIC_BLOCKERS or {
    "castbar", "cast bar", "font", "text", "portrait", "highlight", "aggro",
    "dispel", "purge", "aura", "buff", "debuff", "spell",
    -- In "bar outline color blue channel" the colour word names the channel,
    -- not a value to write. Without this the composite-colour path claimed the
    -- sentence and then declined it, so the exact channel setting was never
    -- reached and could not report why it is read-only. The same words already
    -- block the composite path through BAR_OUTLINE_COLOR_CONFLICT_TERMS.
    "channel", "channels", "component", "components",
}
P.BAR_OUTLINE_COLOR_CONFLICT_TERMS = P.BAR_OUTLINE_COLOR_CONFLICT_TERMS or {
    "thickness", "thicker", "thinner", "size", "width", "strata", "layer", "offset", "style",
    "texture", "gradient", "opacity", "alpha", "name", "show", "hide", "enable", "disable",
    "move", "position", "anchor", "rounded", "rounding", "dicke", "breite", "textur",
    "deckkraft", "anzeigen", "verstecken", "aktivieren", "deaktivieren",
    -- Component/channel requests are not composite color requests. Class
    -- Resources do not expose an independent reviewed outline-color control.
    "channel", "channels", "component", "components", "class power", "class resource",
}
P.BAR_OUTLINE_COLOR_MUTATION_WORDS = P.BAR_OUTLINE_COLOR_MUTATION_WORDS or {
    set = true, change = true, make = true, use = true, paint = true, want = true,
    turn = true, give = true,
    -- The Router already treats these as setting-mutation verbs
    -- (OPEN_ENDED_SETTING_MUTATION_VERBS). Omitting them here made the same
    -- request succeed or be refused as "a statement" purely by verb choice:
    -- "set bar outline color to blue" applied, "adjust ... to blue" did not.
    adjust = true, update = true, switch = true, modify = true, edit = true,
    alter = true, tweak = true, configure = true, put = true, choose = true,
    setze = true, stelle = true, aendere = true, mach = true, mache = true, verwende = true,
}
P.BAR_OUTLINE_COLOR_SHORTHAND_OBJECTS = P.BAR_OUTLINE_COLOR_SHORTHAND_OBJECTS or {
    "bar outline", "bar outlines", "bars outline", "bars outlines",
    "bar border", "bar borders", "bars border", "bars borders",
    "balken kontur", "balken konturfarbe", "leiste kontur", "leisten kontur",
    "balkenkontur", "balkenkonturen", "leistenkontur", "leistenkonturen",
}

local function ParseGlobalUnitFrameColorFastShortcut(normalized, raw)
    if ContainsAny(normalized, GLOBAL_BAR_COLOR_SCOPE_BLOCKERS) then return nil end
    if ContainsAny(normalized, P.RootPhrases[228]) then return nil end

    local key
    local value
    if ContainsAny(normalized, P.RootPhrases[229]) then
        key = "general.unifiedBarColor"
        local extract = P.ExtractColor
        if type(extract) ~= "function" then return nil end
        local r, g, b, label = extract(raw or normalized, normalized)
        if not r then return nil end
        value = { r = r, g = g, b = b, label = label }
    elseif ContainsAny(normalized, P.RootPhrases[230]) then
        key = "general.darkBarGray"
        value = FirstNumber(normalized)
        if value == nil then return nil end
        if value > 1 then value = value / 100 end
    elseif ContainsAny(normalized, P.RootPhrases[231]) then
        key = "general.powerBarBgColor"
        local extract = P.ExtractColor
        if type(extract) ~= "function" then return nil end
        local r, g, b, label = extract(raw or normalized, normalized)
        if not r then return nil end
        value = { r = r, g = g, b = b, label = label }
    elseif ContainsAny(normalized, P.RootPhrases[232]) then
        key = "general.healAbsorbBarColor"
        local extract = P.ExtractColor
        if type(extract) ~= "function" then return nil end
        local r, g, b, label = extract(raw or normalized, normalized)
        if not r then return nil end
        value = { r = r, g = g, b = b, label = label }
    elseif ContainsAny(normalized, P.RootPhrases[233]) then
        key = "general.absorbBarColor"
        local extract = P.ExtractColor
        if type(extract) ~= "function" then return nil end
        local r, g, b, label = extract(raw or normalized, normalized)
        if not r then return nil end
        value = { r = r, g = g, b = b, label = label }
    elseif ContainsAny(normalized, P.RootPhrases[234]) then
        key = "general.aggroBorderColor"
        local extract = P.ExtractColor
        if type(extract) ~= "function" then return nil end
        local r, g, b, label = extract(raw or normalized, normalized)
        if not r then return nil end
        value = { r = r, g = g, b = b, label = label }
    elseif ContainsAny(normalized, P.RootPhrases[235]) then
        key = "general.purgeBorderColor"
        local extract = P.ExtractColor
        if type(extract) ~= "function" then return nil end
        local r, g, b, label = extract(raw or normalized, normalized)
        if not r then return nil end
        value = { r = r, g = g, b = b, label = label }
    elseif ContainsAny(normalized, P.RootPhrases[236]) then
        key = "general.barOutlineColor"
        local extract = P.ExtractColor
        if type(extract) ~= "function" then return nil end
        local r, g, b, label = extract(raw or normalized, normalized)
        if not r then return nil end
        value = { r = r, g = g, b = b, label = label }
    else
        return nil
    end

    local setting = A.Registry and A.Registry:GetSetting(key)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Global Bar Color",
        summary = "Changes global unit-frame bar color behavior.",
    }
end

local function FollowupGradientDirection(normalized)
    if ContainsAny(normalized, P.RootPhrases[237]) then return "RIGHT" end
    if ContainsAny(normalized, P.RootPhrases[238]) then return "LEFT" end
    if ContainsAny(normalized, P.RootPhrases[239]) then return "UP" end
    if ContainsAny(normalized, P.RootPhrases[240]) then return "DOWN" end
    return nil
end

local function LastBarGradientIntent(ctx)
    local bundle = ctx and ctx.lastChangeBundle
    if type(bundle) ~= "table" then return nil end
    local healthValue
    local powerValue
    local direction
    for i = 1, #bundle do
        local item = bundle[i]
        local key = tostring(item and item.key or "")
        local value = item and item.value
        local attr = key:match("^barScope%.[^.]+%.([^.]+)$")
        if key == "general.enableGradient" or attr == "enableGradient" then
            healthValue = value and true or false
        elseif key == "general.enablePowerGradient" or attr == "enablePowerGradient" then
            powerValue = value and true or false
        elseif key == "general.gradientDirection" or attr == "gradientDirection" then
            if value ~= nil then direction = tostring(value) end
        end
    end
    if healthValue == nil and powerValue == nil and direction == nil then return nil end
    return healthValue, powerValue, direction
end

local function ParseLastBarGradientGroupFollowup(normalized, ctx)
    -- "too" is a continuation only as a trailing reply ("raid too"). In a
    -- natural problem such as "raid frames are too faded" it is an adjective,
    -- and must never reuse an unrelated previous gradient change.
    local continuationIntent = ContainsAny(normalized, { "also", "same", "as well", "auch", "ebenfalls" })
        or normalized == "too"
        or normalized:sub(-4) == " too"
    if not continuationIntent then return nil end
    if not ContainsAny(normalized, P.RootPhrases[242]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[243]) then return nil end

    local healthValue, powerValue, direction = LastBarGradientIntent(ctx)
    if healthValue == nil and powerValue == nil and direction == nil then
        return {
            kind = "unknown",
            status = "ambiguous",
            text = "I can apply a bar-gradient change to group frames, but I need the previous gradient change first so I do not guess. Example: 'turn off bar gradient for all group frames' or 'turn on power bar gradient from right for all group frames'.",
            summary = "Asks for explicit group-frame gradient context.",
        }
    end

    local override = DetectBoolean(normalized)
    if override ~= nil then
        if healthValue ~= nil then healthValue = override end
        if powerValue ~= nil then powerValue = override end
    end
    local overrideDirection = FollowupGradientDirection(normalized)
    if overrideDirection then direction = overrideDirection end

    local scopes = {}
    local function addScope(scope)
        if scope and not scopes[scope] then scopes[scope] = true end
    end
    if ContainsAny(normalized, P.RootPhrases[244]) then addScope("gf_party") end
    if ContainsAny(normalized, P.RootPhrases[245]) then addScope("gf_raid") end
    if ContainsAny(normalized, P.RootPhrases[246]) then
        addScope("gf_party")
        addScope("gf_raid")
    end

    local changes = {}
    local function addChange(key, value)
        local setting = A.Registry and A.Registry:GetSetting(key)
        if setting then changes[#changes + 1] = { setting = setting, value = value } end
    end
    for scope in pairs(scopes) do
        if healthValue ~= nil then addChange("barScope." .. scope .. ".enableGradient", healthValue) end
        if powerValue ~= nil then addChange("barScope." .. scope .. ".enablePowerGradient", powerValue) end
        if direction ~= nil then addChange("barScope." .. scope .. ".gradientDirection", direction) end
    end
    if #changes == 0 then return nil end

    local label
    if healthValue ~= nil and powerValue ~= nil then
        label = "Group Bar Gradients"
    elseif powerValue ~= nil then
        label = "Group Power Bar Gradient"
    elseif healthValue ~= nil then
        label = "Group HP Bar Gradient"
    else
        label = "Group Bar Gradient Direction"
    end
    return {
        kind = "changes",
        changes = changes,
        label = label,
        bulkSafe = #changes > 1,
        summary = "Applies the previous bar-gradient change to group frames.",
    }
end

local function ParseHealthColorGradientFastShortcut(normalized, raw)
    if ContainsAny(normalized, P.RootPhrases[247]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[248]) then return nil end

    local key
    local value
    if ContainsAny(normalized, P.RootPhrases[249]) then
        key = "general.healthGradientLow"
    elseif ContainsAny(normalized, P.RootPhrases[250]) then
        key = "general.healthGradientMid"
    elseif ContainsAny(normalized, P.RootPhrases[251]) then
        key = "general.healthGradientHigh"
    else
        key = "general.enableHealthGradient"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    end

    if value == nil then
        local extract = P.ExtractColor
        if type(extract) ~= "function" then return nil end
        local r, g, b, label = extract(raw or normalized, normalized)
        if not r then return nil end
        value = { r = r, g = g, b = b, label = label }
    end

    local setting = A.Registry and A.Registry:GetSetting(key)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Health Color Gradient",
        summary = "Changes global health color gradient options.",
    }
end

local function ParseNPCReactionColorFastShortcut(normalized, raw)
    if ContainsAny(normalized, P.RootPhrases[252]) then return nil end
    local suffix
    if ContainsAny(normalized, P.RootPhrases[253]) then
        suffix = "friendly"
    elseif ContainsAny(normalized, P.RootPhrases[254]) then
        suffix = "neutral"
    elseif ContainsAny(normalized, P.RootPhrases[255]) then
        suffix = "enemy"
    elseif ContainsAny(normalized, P.RootPhrases[256]) then
        suffix = "dead"
    else
        return nil
    end

    local extract = P.ExtractColor
    if type(extract) ~= "function" then return nil end
    local r, g, b, label = extract(raw or normalized, normalized)
    if not r then return nil end
    local setting = A.Registry and A.Registry:GetSetting("npcColors." .. suffix)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = { r = r, g = g, b = b, label = label } } },
        label = setting.label or "NPC Color",
        summary = "Changes global NPC reaction colors.",
    }
end

local function ParsePetFrameColorFastShortcut(normalized, raw)
    if ContainsAny(normalized, P.RootPhrases[257]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[258]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[259]) then return nil end

    local extract = P.ExtractColor
    if type(extract) ~= "function" then return nil end
    local r, g, b, label = extract(raw or normalized, normalized)
    if not r then return nil end
    local setting = A.Registry and A.Registry:GetSetting("general.petFrameColor")
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = { r = r, g = g, b = b, label = label } } },
        label = setting.label or "Pet Frame Color",
        summary = "Changes the global pet frame color.",
    }
end

local function ParsePowerColorTokenFastShortcut(normalized, raw)
    if ContainsAny(normalized, P.RootPhrases[260]) then return nil end

    local specs = {
        { "MANA", { "mana power color", "mana color", "color of mana" } },
        { "RAGE", { "rage power color", "rage color", "color of rage" } },
        { "ENERGY", { "energy power color", "energy color", "color of energy", "color energy" } },
        { "FOCUS", { "focus power color", "hunter focus color", "color of focus power" } },
        { "RUNIC_POWER", { "runic power color", "color of runic power" } },
        { "INSANITY", { "insanity power color", "insanity color", "color of insanity" } },
        { "FURY", { "fury power color", "fury color", "color of fury" } },
        { "PAIN", { "pain power color", "pain color", "color of pain" } },
        { "ESSENCE", { "essence power color", "essence color", "color of essence" } },
        { "LUNAR_POWER", { "astral power color", "lunar power color", "color of astral power", "color of lunar power" } },
        { "MAELSTROM", { "maelstrom power color", "maelstrom color", "color of maelstrom" } },
    }
    local token
    for i = 1, #specs do
        if ContainsAny(normalized, specs[i][2]) then
            token = specs[i][1]
            break
        end
    end
    if not token then return nil end

    if ContainsAny(normalized, P.RootPhrases[261]) then
        local action = A.Registry and A.Registry:GetAction("reset_power_color_token")
        return action and {
            kind = "action",
            action = action,
            args = { token = token },
            label = "Reset power bar color",
            summary = "Resets a single Power Bar color.",
        } or nil
    end

    local extract = P.ExtractColor
    if type(extract) ~= "function" then return nil end
    local r, g, b, label = extract(raw or normalized, normalized)
    if not r then return nil end
    local setting = A.Registry and A.Registry:GetSetting("general.powerColorOverrides." .. token)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = { r = r, g = g, b = b, label = label } } },
        label = setting.label or "Power Bar Color",
        summary = "Changes a global power-bar color token.",
    }
end

P.CastbarColorFastTerms = P.CastbarColorFastTerms or {
    blocked = { "what", "which", "where", "why", "help", "explain", "how", "current", "active", "reset", "restore", "default", "defaults" },
    aura = { "aura", "auras", "buff", "buffs", "debuff", "debuffs", "filter", "filters" },
    root = {
        "castbar", "cast bar", "cast color", "cast colour", "interruptible", "non interruptible", "noninterruptible",
        "uninterruptible", "unkickable", "interrupt unavailable", "unavailable fill", "interrupt feedback",
        "interrupted cast", "kick ready", "kick not ready", "spell name color", "spell text color",
    },
    kickNotReady = { "not ready", "notready", "kick cooldown", "interrupt cooldown" },
    kick = { "kick", "interrupt" },
    kickReady = { "kick ready", "interrupt ready" },
    interruptUnavailable = { "interrupt unavailable fill color", "interrupt unavailable fill", "unavailable cast fill color", "unavailable cast fill", "unavailable fill color", "kick unavailable fill color", "castbar unavailable fill color", "cast bar unavailable fill color" },
    interruptFeedback = { "interrupt feedback color", "castbar interrupt feedback color", "cast bar interrupt feedback color", "interrupted cast color", "interrupted castbar color", "interrupted cast bar color", "after interrupt cast color" },
    nonInterruptible = { "non interruptible", "noninterruptible", "not interruptible", "uninterruptible", "unkickable", "not kickable", "cannot interrupt", "cant interrupt" },
    playerOverride = { "player castbar override color", "player cast bar override color", "player castbar custom color", "player cast custom color", "custom player castbar color" },
    targetName = { "castbar target name color", "cast bar target name color", "cast target name color", "cast target text color", "target name on castbar color", "target name on cast bar color", "castbar target text color" },
    text = { "castbar text color", "castbar font color", "cast bar text color", "cast bar font color", "castbar spell name color", "castbar spell text color", "spell name color", "spell text color" },
    border = { "castbar border color", "cast bar border color", "castbar outline color", "cast bar outline color" },
    background = { "castbar background color", "cast bar background color", "castbar bg color", "cast bar bg color" },
    interruptible = { "interruptible cast color", "interruptible castbar color", "interruptible cast bar color", "castbar interruptible color", "cast bar interruptible color", "interrupt castbar color", "interrupt cast bar color", "kickable cast color", "kickable castbar color" },
}

local function ParseCastbarColorFastShortcut(normalized, raw)
    local terms = P.CastbarColorFastTerms
    if ContainsAny(normalized, terms.blocked) then return nil end
    if ContainsAny(normalized, terms.aura) then return nil end
    local targetNameIntent = ContainsAny(normalized, terms.targetName)
    if not targetNameIntent and not ContainsAny(normalized, terms.root) then return nil end

    local extract = P.ExtractColor
    if type(extract) ~= "function" then return nil end
    local r, g, b, label = extract(raw or normalized, normalized)
    if not r then return nil end

    local key
    if ContainsAny(normalized, terms.kickNotReady)
        and ContainsAny(normalized, terms.kick) then
        key = "general.kickNotReadyColor"
    elseif ContainsAny(normalized, terms.kickReady) then
        key = "general.kickReadyColor"
    elseif ContainsAny(normalized, terms.interruptUnavailable) then
        key = "general.castbarInterruptUnavailableColor"
    elseif ContainsAny(normalized, terms.interruptFeedback) then
        key = "general.castbarInterruptFeedbackColor"
    elseif ContainsAny(normalized, terms.nonInterruptible) then
        key = "general.castbarNonInterruptibleColor"
    elseif ContainsAny(normalized, terms.playerOverride) then
        key = "general.playerCastbarOverrideColor"
    elseif targetNameIntent then
        key = "general.castbarTargetNameColor"
    elseif ContainsAny(normalized, terms.text) then
        key = "general.castbarFontColor"
    elseif ContainsAny(normalized, terms.border) then
        key = "general.castbarBorderColor"
    elseif ContainsAny(normalized, terms.background) then
        key = "general.castbarBackgroundColor"
    elseif ContainsAny(normalized, terms.interruptible) then
        key = "general.castbarInterruptibleColor"
    end

    local setting = key and A.Registry and A.Registry:GetSetting(key) or nil
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = { r = r, g = g, b = b, label = label } } },
        label = setting.label or "Castbar Color",
        summary = "Changes a Castbar color option.",
    }
end

local function ParseCastbarOverrideModeFastShortcut(normalized)
    if ContainsAny(normalized, P.RootPhrases[270]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[271]) then return nil end

    local value
    if ContainsAny(normalized, P.RootPhrases[272]) then
        value = "CLASS"
    elseif ContainsAny(normalized, P.RootPhrases[273]) then
        value = "CUSTOM"
    end
    if value == nil then return nil end

    local setting = A.Registry and A.Registry:GetSetting("general.playerCastbarOverrideMode")
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Player Castbar Override Mode",
        summary = "Changes whether the player castbar override uses class color or a custom color.",
    }
end

A._ParseMouseoverHighlightFastShortcut = A._ParseMouseoverHighlightFastShortcut or function(normalized, raw)
    if ContainsAny(normalized, P.RootPhrases[274]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[275]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[276]) then return nil end

    local key
    local value
    if ContainsAny(normalized, P.RootPhrases[277]) then
        key = "general.highlightColor"
        local extract = P.ExtractColor
        if type(extract) ~= "function" then return nil end
        local r, g, b, label = extract(raw or normalized, normalized)
        if not r then return nil end
        value = { r = r, g = g, b = b, label = label }
    else
        key = "general.highlightEnabled"
        value = DetectBoolean(normalized)
        if value == nil then return nil end
    end

    local setting = A.Registry and A.Registry:GetSetting(key)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Mouseover Highlight",
        summary = "Changes the global unit-frame mouseover highlight.",
    }
end

P.GlobalHighlightColorFastSpecs = P.GlobalHighlightColorFastSpecs or {
    { key = "general.bossTargetHighlightColor", label = "Boss Target Highlight Color", terms = { "boss target highlight color", "boss target color", "boss target border highlight color" } },
    { key = "gameplay.combatTimerColor", label = "Combat Timer Text Color", terms = { "combat timer text color", "combat timer color" } },
    { key = "gameplay.combatStateEnterColor", label = "Combat Enter Text Color", terms = { "combat enter text color", "combat enter color", "combat state enter color" } },
    { key = "gameplay.combatStateLeaveColor", label = "Combat Leave Text Color", terms = { "combat leave text color", "combat leave color", "combat state leave color" } },
    { key = "gameplay.crosshairInRangeColor", label = "Crosshair In-Range Color", terms = { "crosshair in range color", "combat crosshair in range color", "melee range in color" } },
    { key = "gameplay.crosshairOutRangeColor", label = "Crosshair Out-of-Range Color", terms = { "crosshair out of range color", "crosshair out-of-range color", "combat crosshair out range color", "melee range out color" } },
    { key = "general.aurasOwnBuffHighlightColor", label = "Own Buff Highlight Color", terms = { "own buff highlight color", "my buff highlight color", "aura own buff color", "own buff aura highlight color", "buff aura highlight color" } },
    { key = "general.aurasOwnDebuffHighlightColor", label = "Own Debuff Highlight Color", terms = { "own debuff highlight color", "my debuff highlight color", "aura own debuff color", "own debuff aura highlight color", "debuff aura highlight color" } },
}

A._ParseGlobalHighlightColorFastShortcut = A._ParseGlobalHighlightColorFastShortcut or function(normalized, raw)
    if ContainsAny(normalized, P.RootPhrases[278]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[279]) then return nil end

    local specs = P.GlobalHighlightColorFastSpecs
    local matched
    for i = 1, #(specs or {}) do
        local spec = specs[i]
        if ContainsAny(normalized, spec.terms) then
            matched = spec
            break
        end
    end
    if not matched then return nil end

    local extract = P.ExtractColor
    if type(extract) ~= "function" then return nil end
    local r, g, b, label = extract(raw or normalized, normalized)
    if not r then return nil end
    local setting = A.Registry and A.Registry:GetSetting(matched.key)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = { r = r, g = g, b = b, label = label } } },
        label = setting.label or matched.label,
        summary = "Changes a global MSUF highlight color.",
    }
end

P._EnsureExactColorSettingIndex = P._EnsureExactColorSettingIndex or function(settings)
    settings = settings or {}
    if P._exactColorSettingIndexSettings == settings
        and P._exactColorSettingIndexCount == #settings
        and type(P._exactColorSettingIndex) == "table" then
        return P._exactColorSettingIndex
    end

    local index = { byLength = {}, maxTokens = 0 }
    local function addPhrase(setting, phrase)
        phrase = Normalize(phrase)
        if phrase == "" then return end
        local tokens = {}
        for token in phrase:gmatch("%S+") do tokens[#tokens + 1] = token end
        if #tokens == 0 or #tokens > 12 then return end
        index.byLength[#tokens] = index.byLength[#tokens] or {}
        index.byLength[#tokens][phrase] = index.byLength[#tokens][phrase] or {}
        index.byLength[#tokens][phrase][#index.byLength[#tokens][phrase] + 1] = setting
        if #tokens > index.maxTokens then index.maxTokens = #tokens end
    end

    for i = 1, #settings do
        if i % 64 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local setting = settings[i]
        if type(setting) == "table" and setting.type == "color" then
            if setting.matchLabel ~= false then addPhrase(setting, setting.label) end
            for j = 1, #(setting.aliases or {}) do addPhrase(setting, setting.aliases[j]) end
            for j = 1, #(setting.exactAliases or {}) do addPhrase(setting, setting.exactAliases[j]) end
        end
    end

    P._exactColorSettingIndexSettings = settings
    P._exactColorSettingIndexCount = #settings
    P._exactColorSettingIndex = index
    return index
end

A._ParseExactColorSettingFastShortcut = A._ParseExactColorSettingFastShortcut or function(normalized, raw)
    if ContainsAny(normalized, P.RootPhrases[280]) then return nil end
    local extract = P.ExtractColor
    if type(extract) ~= "function" then return nil end
    local r, g, b, label
    if not ContainsAny(normalized, P.RootPhrases[281]) then
        r, g, b, label = extract(raw or normalized, normalized)
        if not r then return nil end
    end

    if ContainsAny(normalized, P.RootPhrases[282])
        and not ContainsAny(normalized, P.RootPhrases[283])
    then
        local fontAction = ParseFontColorAction and ParseFontColorAction(normalized, raw)
        if fontAction then return fontAction end
    end

    if not ContainsAny(normalized, P.RootPhrases[284]) then
        local powerParsed = A._ParsePowerColorTokenFastShortcut and A._ParsePowerColorTokenFastShortcut(normalized, raw)
        if powerParsed then return powerParsed end
    end

    if not r then
        r, g, b, label = extract(raw or normalized, normalized)
        if not r then return nil end
    end

    local registry = A.Registry
    local settings = registry and type(registry.AllSettings) == "function" and registry:AllSettings() or nil
    if type(settings) ~= "table" or #settings == 0 then return nil end
    local index = P._EnsureExactColorSettingIndex and P._EnsureExactColorSettingIndex(settings) or nil
    if type(index) ~= "table" or (tonumber(index.maxTokens) or 0) <= 0 then return nil end

    local matchText = Normalize(normalized)
    while true do
        local first, rest = matchText:match("^(%S+)%s+(.+)$")
        local second = rest and rest:match("^(%S+)")
        if first and second and first == second and (first == "set" or first == "change" or first == "make") then
            matchText = rest
        else
            break
        end
    end

    local tokens = {}
    for token in matchText:gmatch("%S+") do tokens[#tokens + 1] = token end
    local bestLen = 0
    local best = {}
    local seen = {}
    local maxLen = math.min(tonumber(index.maxTokens) or 0, #tokens)
    for len = maxLen, 1, -1 do
        local bucket = index.byLength and index.byLength[len]
        if bucket then
            for startIndex = 1, (#tokens - len + 1) do
                local phrase = table.concat(tokens, " ", startIndex, startIndex + len - 1)
                local matches = bucket[phrase]
                if matches then
                    for i = 1, #matches do
                        local setting = matches[i]
                        local key = tostring(setting and setting.key or "")
                        local allowed = key ~= ""
                        if allowed and type(P.RegistrySettingMayMatchExactAlias) == "function" then
                            allowed = P.RegistrySettingMayMatchExactAlias(setting, matchText) == true
                        end
                        if allowed and not seen[key] then
                            seen[key] = true
                            best[#best + 1] = setting
                            bestLen = len
                        end
                    end
                end
            end
        end
        if bestLen > 0 then break end
    end
    if #best ~= 1 then return nil end

    local setting = best[1]
    return {
        kind = "changes",
        changes = { { setting = setting, value = { r = r, g = g, b = b, label = label } } },
        label = setting.label or "Color",
        summary = "Changes the exact matched MSUF color setting.",
    }
end

local function ParseScopedBarOutlineColorFastShortcut(normalized, raw)
    -- Resolve the bounded semantic frame behind ordinary bar-outline color
    -- wording without making the full registry matcher order-insensitive.
    -- Explicit bar/bars language owns the global domain unless the user also
    -- names a concrete frame scope; the open Party/Raid page is not a scope.
    local padded = " " .. Normalize(normalized):gsub("[-_/]", " ") .. " "
    if not (padded:find(" bar ", 1, true) or padded:find(" bars ", 1, true)
        or padded:find(" balken ", 1, true) or padded:find(" leiste ", 1, true)
        or padded:find(" leisten ", 1, true) or padded:find(" spielerbalken ", 1, true)
        or padded:find(" gruppenbalken ", 1, true) or padded:find(" gruppenleisten ", 1, true)
        or padded:find(" balkenkontur ", 1, true) or padded:find(" balkenkonturen ", 1, true)
        or padded:find(" leistenkontur ", 1, true) or padded:find(" leistenkonturen ", 1, true)
        or (padded:find(" konturfarbe ", 1, true)
            and (padded:find(" spieler ", 1, true) or padded:find(" gruppe ", 1, true)
                or padded:find(" spielers ", 1, true) or padded:find(" gruppen ", 1, true))))
    then return nil end
    if not (padded:find(" outline ", 1, true) or padded:find(" outlines ", 1, true)
        or padded:find(" border ", 1, true) or padded:find(" borders ", 1, true)
        or padded:find(" kontur ", 1, true) or padded:find(" konturen ", 1, true)
        or padded:find(" konturfarbe ", 1, true) or padded:find(" balkenkontur ", 1, true)
        or padded:find(" balkenkonturen ", 1, true) or padded:find(" leistenkontur ", 1, true)
        or padded:find(" leistenkonturen ", 1, true))
    then return nil end
    -- A second, fully named color control belongs to the established value-
    -- token compound parser. Deferring only these reviewed aliases preserves
    -- valid atomic commands such as "player border color red bar background
    -- color black" without weakening fail-closed handling for color
    -- alternatives or incomplete clauses such as "and thickness 2".
    if padded:find(" bar background color ", 1, true)
        or padded:find(" bar background tint ", 1, true)
        or padded:find(" class bar background color ", 1, true)
        or padded:find(" class bar background tint ", 1, true)
    then return nil end
    local extract = P.ExtractColor
    if type(extract) ~= "function" then return nil end
    local r, g, b, label = extract(raw or normalized, normalized)
    if not r and type(A.ColorFromName) == "function" then
        for word in Normalize(normalized):gmatch("%S+") do
            r, g, b, label = A.ColorFromName(word)
            if r then break end
        end
        if not r and padded:find(" rote ", 1, true) then r, g, b, label = A.ColorFromName("rot") end
    end
    if not r then return nil end
    if ContainsAny(normalized, P.BAR_OUTLINE_COLOR_SEMANTIC_BLOCKERS) then return nil end

    local semanticText = Normalize(normalized)
    local distinctColors, distinctColorCount = {}, 0
    if type(A.ColorFromName) == "function" then
        for word in semanticText:gmatch("%S+") do
            local cr, cg, cb, colorLabel = A.ColorFromName(word)
            if cr then
                local colorKey = tostring(colorLabel or (tostring(cr) .. ":" .. tostring(cg) .. ":" .. tostring(cb)))
                if not distinctColors[colorKey] then
                    distinctColors[colorKey] = true
                    distinctColorCount = distinctColorCount + 1
                end
            end
        end
    end
    local rawColorText = tostring(raw or normalized):lower()
    local _, hashHexCount = rawColorText:gsub("#%x%x%x%x%x%x", "")
    local _, prefixedHexCount = rawColorText:gsub("0x%x%x%x%x%x%x", "")
    local rgbSpecCount = 0
    for _ in semanticText:gmatch("rgb%s+[-+]?%d") do rgbSpecCount = rgbSpecCount + 1 end
    local bareRgbSpecCount = 0
    for _ in rawColorText:gmatch("[-+]?%d+%.?%d*%s*,%s*[-+]?%d+%.?%d*%s*,%s*[-+]?%d+%.?%d*") do
        bareRgbSpecCount = bareRgbSpecCount + 1
    end
    local explicitColorSpecCount = distinctColorCount + hashHexCount + prefixedHexCount
        + math.max(rgbSpecCount, bareRgbSpecCount)
    local metaOrConditional = semanticText:match("^if%s+")
        or semanticText:match("^when%s+")
        or semanticText:match("^should%s+")
        or semanticText:match("^do%s+you%s+")
        or semanticText:match("^say%s+")
        or semanticText:match("^quote%s+")
        or semanticText:match("^pretend%s+")
        or semanticText:find(" example ", 1, true)
        or semanticText:find(" example command ", 1, true)
        or semanticText:find(" when i say ", 1, true)
        or semanticText:find(" do nothing ", 1, true)
        or semanticText:find(" dont do ", 1, true)
        or semanticText:find(" hypothetical ", 1, true)
    local readOnlyOrNegated = explicitColorSpecCount > 1 or metaOrConditional
        or padded:find(" or ", 1, true)
        or padded:find(" oder ", 1, true)
        or semanticText:find(" instead of ", 1, true)
        or rawColorText:find("/", 1, true)
        or padded:find(" do not ", 1, true)
        or padded:find(" dont ", 1, true)
        or padded:find(" never ", 1, true)
        or padded:find(" not ", 1, true)
        or padded:find(" anything but ", 1, true)
        or padded:find(" except ", 1, true)
        or padded:find(" nicht ", 1, true)
        or padded:find(" kein ", 1, true)
        or padded:find(" keine ", 1, true)
        or padded:find(" ohne ", 1, true)
        or padded:find(" want to know ", 1, true)
        or padded:find(" would like to know ", 1, true)
        or padded:find(" whether ", 1, true)
        or padded:find(" possible ", 1, true)
    if readOnlyOrNegated or (P.NonMutatingIntent and P.NonMutatingIntent(normalized)) then
        return {
            kind = "unknown",
            status = "info",
            text = "I read that as a question or statement, so I kept MSUF unchanged. If you want the change, say 'set the bar outline color to " .. tostring(label or "that color") .. "'.",
            summary = "Keeps non-mutating bar-outline color language read-only.",
        }
    end

    local actionable = P.ActionableText and P.ActionableText(normalized) or Normalize(normalized)
    local mutation = false
    -- Politeness and sequencing words sit in front of the verb ("just set ...",
    -- "now set ..."). Reading only the very first word saw "just" and refused
    -- the request as declarative, so skip that filler before looking for the
    -- verb.
    local verbScan = tostring(actionable or "")
    for _ = 1, 3 do
        local previous = verbScan
        verbScan = verbScan:gsub("^please%s+", ""):gsub("^just%s+", ""):gsub("^now%s+", "")
            :gsub("^kindly%s+", ""):gsub("^hey%s+", ""):gsub("^ok%s+", ""):gsub("^okay%s+", "")
            :gsub("^also%s+", ""):gsub("^then%s+", "")
        if verbScan == previous then break end
    end
    local firstActionWord = verbScan:match("^(%S+)")
    if firstActionWord and P.BAR_OUTLINE_COLOR_MUTATION_WORDS[firstActionWord] then mutation = true end
    if tostring(actionable or ""):match("^i%s+want%s+")
        or tostring(actionable or ""):match("^ich%s+will%s+")
        or tostring(actionable or ""):match("^for%s+.-%s+use%s+")
        or tostring(actionable or "") == "rote balkenkontur"
        or tostring(actionable or "") == "rote balkenkonturen"
        or tostring(actionable or "") == "rote leistenkontur"
        or tostring(actionable or "") == "rote leistenkonturen"
    then mutation = true end
    local firstWord = tostring(actionable or ""):match("^(%S+)")
    if firstWord == "color" or firstWord == "colour" or firstWord == "faerbe" then mutation = true end
    if not mutation then
        local colorToken = Normalize(label)
        local shorthandAction = tostring(actionable or ""):gsub("%s*=%s*", " "):gsub("%s+", " ")
        for i = 1, #P.BAR_OUTLINE_COLOR_SHORTHAND_OBJECTS do
            local object = P.BAR_OUTLINE_COLOR_SHORTHAND_OBJECTS[i]
            if shorthandAction == object .. " " .. colorToken
                or shorthandAction == colorToken .. " " .. object
                or shorthandAction == object .. " color " .. colorToken
                or shorthandAction == object .. " colour " .. colorToken
            then
                mutation = true
                break
            end
        end
    end
    if not mutation then
        return {
            kind = "unknown",
            status = "info",
            text = "I read that as a statement, so I kept MSUF unchanged. To apply it, say 'set the bar outline color to " .. tostring(label or "that color") .. "'.",
            summary = "Keeps declarative bar-outline color language read-only.",
        }
    end

    if padded:find(" here ", 1, true)
        or padded:find(" this page ", 1, true)
        or padded:find(" this pages ", 1, true)
        or padded:find(" this frame ", 1, true)
        or padded:find(" this frames ", 1, true)
        or padded:find(" current frame ", 1, true)
        or padded:find(" selected frame ", 1, true)
    then
        return {
            kind = "unknown",
            status = "info",
            text = "I kept MSUF unchanged because that wording points at the current page or frame. Name Player, Target, Party, Raid, or say shared bars so I do not change the wrong outline.",
            summary = "Keeps deictic bar-outline scope fail-closed until the user names a frame.",
        }
    end

    local scopeKeys, seen = {}, {}
    local function AddScope(key)
        if not seen[key] then seen[key] = true; scopeKeys[#scopeKeys + 1] = key end
    end
    -- Scope detection here is deliberately text-only. Generic bar/bars words
    -- must not inherit the currently open Unit or Group page.
    local scopeText = padded
    if scopeText:find(" target of target ", 1, true) or scopeText:find(" targettarget ", 1, true) then
        AddScope("barScope.targettarget.barOutlineColor")
        scopeText = scopeText:gsub(" target of target ", " "):gsub(" targettarget ", " ")
    end
    if scopeText:find(" focus target ", 1, true) or scopeText:find(" focustarget ", 1, true) then
        AddScope("barScope.focustarget.barOutlineColor")
        scopeText = scopeText:gsub(" focus target ", " "):gsub(" focustarget ", " ")
    end
    if scopeText:find(" player ", 1, true) or scopeText:find(" spieler ", 1, true)
        or scopeText:find(" spielers ", 1, true)
        or scopeText:find(" spielerbalken ", 1, true)
    then AddScope("barScope.player.barOutlineColor") end
    if scopeText:find(" target ", 1, true) or scopeText:find(" ziel ", 1, true) then AddScope("barScope.target.barOutlineColor") end
    if scopeText:find(" focus ", 1, true) or scopeText:find(" fokus ", 1, true) then AddScope("barScope.focus.barOutlineColor") end
    if scopeText:find(" pet ", 1, true) or scopeText:find(" begleiter ", 1, true) then AddScope("barScope.pet.barOutlineColor") end
    if scopeText:find(" boss ", 1, true) then AddScope("barScope.boss.barOutlineColor") end
    if scopeText:find(" mythic raid ", 1, true) or scopeText:find(" mythicraid ", 1, true) then
        AddScope("barScope.gf_raid.barOutlineColor")
        scopeText = scopeText:gsub(" mythic raid ", " "):gsub(" mythicraid ", " ")
    end
    local explicitParty = scopeText:find(" party ", 1, true) ~= nil
    local explicitRaid = scopeText:find(" raid ", 1, true) ~= nil or scopeText:find(" schlachtzug ", 1, true) ~= nil
    if explicitParty then AddScope("barScope.gf_party.barOutlineColor") end
    if explicitRaid then AddScope("barScope.gf_raid.barOutlineColor") end
    if scopeText:find(" group frame ", 1, true) or scopeText:find(" group frames ", 1, true) then
        AddScope("barScope.gf_party.barOutlineColor")
        AddScope("barScope.gf_raid.barOutlineColor")
    end
    local genericGroup = (scopeText:find(" group ", 1, true) ~= nil
        or scopeText:find(" groups ", 1, true) ~= nil
        or scopeText:find(" gruppe ", 1, true) ~= nil
        or scopeText:find(" gruppen ", 1, true) ~= nil
        or scopeText:find(" gruppenbalken ", 1, true) ~= nil
        or scopeText:find(" gruppenleisten ", 1, true) ~= nil)
        and not explicitParty and not explicitRaid
    if genericGroup then
        AddScope("barScope.gf_party.barOutlineColor")
        AddScope("barScope.gf_raid.barOutlineColor")
    end

    local _, joinCount = Normalize(normalized):gsub(" and ", " ")
    local conflict = ContainsAny(normalized, P.BAR_OUTLINE_COLOR_CONFLICT_TERMS)
        or padded:find(" then ", 1, true) ~= nil
        or (joinCount > 0 and (#scopeKeys < 2 or joinCount > 1))
    if conflict then
        return {
            kind = "unknown",
            status = "info",
            text = "I understood the " .. tostring(label or "requested") .. " bar-outline color, but that sentence also asks for another detail. I kept MSUF unchanged. Send the color and the other change as separate requests.",
            summary = "Keeps a compound bar-outline request fail-closed instead of dropping a clause.",
        }
    end
    if #scopeKeys == 0 then scopeKeys[1] = "general.barOutlineColor" end

    local choices = {}
    for i = 1, #scopeKeys do
        local setting = A.Registry and A.Registry:GetSetting(scopeKeys[i])
        if setting then
            choices[#choices + 1] = {
                setting = setting,
                value = { r = r, g = g, b = b, label = label },
                valueLabel = label,
                label = tostring(setting.label or "Bar Outline Color") .. ": " .. tostring(label or "custom color"),
            }
        end
    end
    if #choices == 0 then return nil end
    if #choices > 1 then
        return {
            kind = "ambiguous",
            choices = choices,
            label = "Choose which bar outline color to change",
            choiceIntro = genericGroup
                and "'Group' can mean Party or Raid. Choose one; I retained the requested " .. tostring(label or "custom") .. " color."
                or "You named more than one bar scope. Choose one; I retained the requested " .. tostring(label or "custom") .. " color.",
            summary = "Retains the requested color while asking for one explicit bar scope.",
        }
    end
    return {
        kind = "changes",
        changes = choices,
        label = choices[1].setting.label or "Bar Outline Color",
        summary = "Changes the requested bar outline color independent of word order.",
    }
end

local function ParseNPCTypeColorFastShortcut(normalized)
    if ContainsAny(normalized, P.RootPhrases[288]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[289]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[290]) then return nil end

    local colorKey
    if ContainsAny(normalized, P.RootPhrases[291]) then
        colorKey = "npcBoss"
    elseif ContainsAny(normalized, P.RootPhrases[292]) then
        colorKey = "npcMiniboss"
    elseif ContainsAny(normalized, P.RootPhrases[293]) then
        colorKey = "npcCaster"
    elseif ContainsAny(normalized, P.RootPhrases[294]) then
        colorKey = "npcMelee"
    elseif ContainsAny(normalized, P.RootPhrases[295]) then
        colorKey = "npcRegular"
    end
    if colorKey then
        local extract = P.ExtractColor
        if type(extract) == "function" then
            local r, g, b, label = extract(normalized, normalized)
            if r then
                local setting = A.Registry and A.Registry:GetSetting("npcColors." .. colorKey)
                if setting then
                    return {
                        kind = "changes",
                        changes = { { setting = setting, value = { r = r, g = g, b = b, label = label } } },
                        label = setting.label or "NPC Type Color",
                        summary = "Changes NPC type colors.",
                    }
                end
            end
        end
    end

    local key
    if ContainsAny(normalized, P.RootPhrases[296]) then
        key = "general.npcTypeToT"
    elseif ContainsAny(normalized, P.RootPhrases[297]) then
        key = "general.npcTypeTarget"
    elseif ContainsAny(normalized, P.RootPhrases[298]) then
        key = "general.npcTypeFocus"
    elseif ContainsAny(normalized, P.RootPhrases[299]) then
        key = "general.npcTypeBoss"
    elseif ContainsAny(normalized, P.RootPhrases[300]) then
        key = "general.npcTypeColorBar"
    elseif ContainsAny(normalized, P.RootPhrases[301]) then
        key = "general.npcTypeColorText"
    else
        key = "general.npcColorMode"
    end

    local value = DetectBoolean(normalized)
    if value == nil then value = true end
    local setting = A.Registry and A.Registry:GetSetting(key)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "NPC Type Colors",
        summary = "Changes NPC type color options.",
    }
end

local function ParseClassResourceHPBarFastShortcut(normalized)
    if ContainsAny(normalized, P.RootPhrases[302]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[303]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[304]) then return nil end

    local value = DetectBoolean(normalized)
    if value == nil then value = true end
    local setting = A.Registry and A.Registry:GetSetting("bars.playerHPBarEnabled")
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Class Resources Player HP Bar",
        summary = "Changes the class-resource Player HP bar visibility.",
    }
end

local function ParseGlobalColorModeBooleanFastShortcut(normalized)
    if ContainsAny(normalized, P.RootPhrases[305]) then return nil end
    local key
    local value
    if ContainsAny(normalized, P.RootPhrases[309]) then
        if ContainsAny(normalized, P.RootPhrases[310]) then return nil end
        key = "general.playerCastbarOverrideEnabled"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    else
        return nil
    end

    local setting = A.Registry and A.Registry:GetSetting(key)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Color Setting",
        summary = "Changes global color mode options.",
    }
end

local function ParseRaidMarkerNumberFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[311]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[312]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[313]) then return nil end

    local attr
    if ContainsAny(normalized, P.RootPhrases[314]) then
        attr = "x"
    elseif ContainsAny(normalized, P.RootPhrases[315]) then
        attr = "y"
    elseif ContainsAny(normalized, P.RootPhrases[316]) then
        attr = "size"
    elseif ContainsAny(normalized, P.RootPhrases[317]) then
        attr = "layer"
    else
        return nil
    end

    local value = NumberAfterLastConnector(normalized)
    if value == nil then return nil end
    local groups = DetectGroups(normalized)
    local units = {}
    if #groups == 0 then units = DetectUnits(normalized) end
    if (#groups + #units) ~= 1 then return nil end

    local key
    if #groups == 1 then
        local groupAttr = attr == "x" and "raidMarkerX"
            or attr == "y" and "raidMarkerY"
            or attr == "size" and "raidMarkerSize"
            or "raidMarkerLayer"
        key = "gf_" .. tostring(groups[1]) .. "." .. groupAttr
    else
        local unitAttr = attr == "x" and "raidMarkerOffsetX"
            or attr == "y" and "raidMarkerOffsetY"
            or attr == "size" and "raidMarkerSize"
            or "raidMarkerLayer"
        key = tostring(units[1]) .. "." .. unitAttr
    end

    local setting = A.Registry and A.Registry:GetSetting(key)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Raid Marker",
        summary = "Changes raid-marker numeric settings for the requested frame.",
    }
end

local function ParseExactTextSlotOffsetFastShortcut(normalized)
    if P.LooksLikeExactKeyLookup and P.LooksLikeExactKeyLookup(normalized) then return nil end
    if ContainsAny(normalized, P.RootPhrases[318]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[319]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[320]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[321]) then return nil end

    local tab
    if ContainsAny(normalized, P.RootPhrases[322]) then
        tab = "hp"
    elseif ContainsAny(normalized, P.RootPhrases[323]) then
        tab = "power"
    else
        return nil
    end

    local slot
    if ContainsAny(normalized, P.RootPhrases[324])
        or HasPhrase(normalized, tab .. " left slot")
        or HasPhrase(normalized, "left " .. tab .. " slot")
    then
        slot = "Left"
    elseif ContainsAny(normalized, P.RootPhrases[325])
        or HasPhrase(normalized, tab .. " center slot")
        or HasPhrase(normalized, tab .. " centre slot")
        or HasPhrase(normalized, tab .. " middle slot")
    then
        slot = "Center"
    elseif ContainsAny(normalized, P.RootPhrases[326])
        or HasPhrase(normalized, tab .. " right slot")
        or HasPhrase(normalized, "right " .. tab .. " slot")
    then
        slot = "Right"
    else
        return nil
    end

    local axis
    if ContainsAny(normalized, P.RootPhrases[327]) then axis = "X" end
    if ContainsAny(normalized, P.RootPhrases[328]) then
        if axis then return nil end
        axis = "Y"
    end
    if not axis then return nil end

    local value = NumberAfterLastConnector(normalized)
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    local units = {}
    if #groups == 0 then units = DetectUnits(normalized) end
    if (#groups + #units) ~= 1 then return nil end

    local attr = (tab == "hp" and "hpText" or "powerText") .. slot .. "Offset" .. axis
    local key = #groups == 1 and ("gf_" .. tostring(groups[1]) .. "." .. attr) or (tostring(units[1]) .. "." .. attr)
    local setting = A.Registry and A.Registry:GetSetting(key)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = "Set text slot offset",
        summary = "Changes the HP/Power left/center/right text-slot offset for the selected unit or group.",
    }
end

local function SpellIndicatorSpecValue(normalized)
    local data = A.GroupFramesRegistry and A.GroupFramesRegistry.SpellIndicatorData
    local aliases = data and data.SPEC_ALIASES or nil
    local values = data and data.SPEC_VALUES or nil
    local displays = data and data.SPEC_DISPLAY_LABELS or nil
    local compact = tostring(normalized or ""):lower():gsub("[^%w]+", "")
    local bestValue
    local bestScore = 0
    if type(aliases) == "table" then
        for alias, value in pairs(aliases) do
            local aliasKey = tostring(alias or ""):lower():gsub("[^%w]+", "")
            if aliasKey ~= "" and compact:find(aliasKey, 1, true) then
                local score = #aliasKey
                if compact == aliasKey then score = score + 10000 end
                if score > bestScore then
                    bestValue = value
                    bestScore = score
                end
            end
        end
    end
    if bestValue then return bestValue end
    if type(values) == "table" then
        for i = 1, #values do
            local value = tostring(values[i] or "")
            local valueKey = value:lower():gsub("[^%w]+", "")
            local displayKey = tostring(displays and displays[value] or ""):lower():gsub("[^%w]+", "")
            if valueKey ~= "" and compact:find(valueKey, 1, true) then return value end
            if displayKey ~= "" and compact:find(displayKey, 1, true) then return value end
        end
    end
    return nil
end

local function ParseGroupSpellIndicatorsEnabledFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[329]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[330]) then
        return nil
    end
    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[331]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    if ContainsAny(normalized, P.RootPhrases[332]) then
        attr = "spellIndicators.layer"
        label = "Spell Indicator Layer"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[333]) then
        attr = "spellIndicators.spec"
        label = "Spell Indicator Spec"
        value = SpellIndicatorSpecValue(normalized)
    else
        attr = "spellIndicators.enabled"
        label = "Spell Indicators"
        value = DetectBoolean(normalized)
    end
    if value == nil then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or label) or label,
        bulkSafe = #changes > 1,
        summary = attr == "spellIndicators.enabled" and "Changes the group-frame Spell Indicators master toggle."
            or "Changes the group-frame Spell Indicators " .. tostring(label) .. " option.",
    }
end

local function ParseGroupFrameColorFastShortcut(normalized, raw)
    if not P.ParseGroupFrameColorShortcut then return nil end
    if P.HasGroupFrameColorIntent and not P.HasGroupFrameColorIntent(normalized) then return nil end
    if ContainsAny(normalized, P.RootPhrases[334]) then
        return nil
    end
    if ContainsAny(normalized, P.RootPhrases[335]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[336])
        and not ContainsAny(normalized, P.RootPhrases[337])
    then
        return nil
    end
    if P.GroupColorTargetForText and not P.GroupColorTargetForText(normalized) then return nil end

    return P.ParseGroupFrameColorShortcut(normalized, raw)
end

local function ParseGroupDeadBackgroundFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[338]) then
        return nil
    end
    if ContainsAny(normalized, P.RootPhrases[339]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[340]) then
        return nil
    end

    local attr
    local label
    local value
    if ContainsAny(normalized, P.RootPhrases[341]) then
        attr = "deadBgOffline"
        label = "Tint Offline Members"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, P.RootPhrases[342]) then
        attr = "deadBgA"
        label = "Dead Background Opacity"
        if ContainsAny(normalized, P.RootPhrases[343]) then return nil end
        value = FirstNumber(normalized)
        if value == nil then return nil end
        if value > 1 then value = value / 100 end
    else
        attr = "deadBgEnabled"
        label = "Dead Background"
        value = DetectBoolean(normalized)
        if value == nil then return nil end
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[344]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or label) or label,
        bulkSafe = #changes > 1,
        summary = attr == "deadBgA" and "Changes group-frame dead background opacity."
            or attr == "deadBgOffline" and "Changes whether offline group members also get the dead background tint."
            or "Changes the group-frame dead background tint toggle.",
    }
end

local function GroupFrameAnchorTargetValue(normalized)
    if ContainsAny(normalized, P.RootPhrases[345]) then return "FREE" end
    if ContainsAny(normalized, P.RootPhrases[346]) then return "targettarget" end
    if ContainsAny(normalized, P.RootPhrases[347]) then return "focustarget" end
    if ContainsAny(normalized, P.RootPhrases[348]) then return "player" end
    if ContainsAny(normalized, P.RootPhrases[349]) then return "target" end
    if ContainsAny(normalized, P.RootPhrases[350]) then return "focus" end
    return nil
end

local function GroupFrameAnchorPointValue(normalized)
    if ContainsAny(normalized, P.RootPhrases[351]) then return "TOPLEFT" end
    if ContainsAny(normalized, P.RootPhrases[352]) then return "TOPRIGHT" end
    if ContainsAny(normalized, P.RootPhrases[353]) then return "BOTTOMLEFT" end
    if ContainsAny(normalized, P.RootPhrases[354]) then return "BOTTOMRIGHT" end
    if ContainsAny(normalized, P.RootPhrases[355]) then return "TOP" end
    if ContainsAny(normalized, P.RootPhrases[356]) then return "BOTTOM" end
    if ContainsAny(normalized, P.RootPhrases[357]) then return "LEFT" end
    if ContainsAny(normalized, P.RootPhrases[358]) then return "RIGHT" end
    if ContainsAny(normalized, P.RootPhrases[359]) then return "CENTER" end
    return nil
end

local function ParseGroupFrameAnchorFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[386]) then
        return nil
    end
    if ContainsAny(normalized, P.RootPhrases[387]) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[388]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    if ContainsAny(normalized, P.RootPhrases[389]) then
        attr = "anchorPoint"
        label = "Anchor Point"
        value = GroupFrameAnchorPointValue(normalized)
    else
        attr = "anchorToFrame"
        label = "Anchor To"
        value = GroupFrameAnchorTargetValue(normalized)
    end
    if value == nil then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or label) or label,
        bulkSafe = #changes > 1,
        summary = attr == "anchorPoint" and "Changes the group-frame Anchor Point dropdown."
            or "Changes the group-frame Anchor To dropdown.",
    }
end

local function GroupBarColorModeValue(normalized)
    if ContainsAny(normalized, P.RootPhrases[390]) then return "GLOBAL" end
    if ContainsAny(normalized, P.RootPhrases[391]) then return "dark" end
    if ContainsAny(normalized, P.RootPhrases[392]) then return "unified" end
    if ContainsAny(normalized, P.RootPhrases[393]) then return "GRADIENT" end
    if ContainsAny(normalized, P.RootPhrases[394]) then return "CUSTOM" end
    if ContainsAny(normalized, P.RootPhrases[395]) then return "CLASS" end
    return nil
end

local function ParseGroupBarColorModeFastShortcut(normalized)
    if ContainsAny(normalized, P.RootPhrases[396]) then
        return nil
    end
    if not ContainsAny(normalized, P.RootPhrases[397]) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[398]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    if ContainsAny(normalized, P.RootPhrases[399]) then
        attr = "healthColorMode"
        label = "Health Color Mode"
    else
        attr = "gfBarMode"
        label = "Bar Color Mode"
    end
    local value = GroupBarColorModeValue(normalized)
    if value == nil then return nil end
    if attr == "healthColorMode" and (value == "GLOBAL" or value == "dark" or value == "unified") then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or label) or label,
        bulkSafe = #changes > 1,
        summary = attr == "healthColorMode" and "Changes the group health color mode dropdown."
            or "Changes the group bar color mode dropdown.",
    }
end

local function GroupTextDelimiterValue(normalized)
    local target = P.TargetAfterLastConnector and P.TargetAfterLastConnector(normalized) or nil
    local text = target or normalized
    if ContainsAny(text, P.RootPhrases[400]) then return "  " end
    if ContainsAny(text, P.RootPhrases[401]) then return " " end
    if ContainsAny(text, P.RootPhrases[402]) then return " / " end
    if ContainsAny(text, P.RootPhrases[403]) then return " - " end
    if ContainsAny(text, P.RootPhrases[404]) then return " : " end
    if ContainsAny(text, P.RootPhrases[405]) then return " | " end
    if text:find("/", 1, true) then return " / " end
    if text:find("-", 1, true) then return " - " end
    if text:find(":", 1, true) then return " : " end
    if text:find("|", 1, true) then return " | " end
    if normalized:match("%s+to$") or normalized:match("%s+as$") or normalized:match("%s+is$") then return false end
    return nil
end

A._ParseGroupTextDirectFastShortcut = function(normalized)
    if ContainsAny(normalized, P.RootPhrases[406]) then
        return nil
    end
    if not ContainsAny(normalized, P.RootPhrases[407]) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[408]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local numeric = false
    if ContainsAny(normalized, P.RootPhrases[409]) then
        attr = "hpFontSize"
        label = "HP Font Size"
        numeric = true
    elseif ContainsAny(normalized, P.RootPhrases[410]) then
        attr = "powerFontSize"
        label = "Power Font Size"
        numeric = true
    elseif ContainsAny(normalized, P.RootPhrases[411]) then
        attr = "powerTextLeft"
        label = "Left Power Text"
    elseif ContainsAny(normalized, P.RootPhrases[412]) then
        attr = "powerTextCenter"
        label = "Center Power Text"
    elseif ContainsAny(normalized, P.RootPhrases[413]) then
        attr = "powerTextRight"
        label = "Right Power Text"
    elseif ContainsAny(normalized, P.RootPhrases[414]) then
        attr = "textLeft"
        label = "Left HP Text"
    elseif ContainsAny(normalized, P.RootPhrases[415]) then
        attr = "textCenter"
        label = "Center HP Text"
    elseif ContainsAny(normalized, P.RootPhrases[416]) then
        attr = "textRight"
        label = "Right HP Text"
    elseif ContainsAny(normalized, P.RootPhrases[417]) then
        attr = "showPowerText"
        label = "Power Text"
        numeric = false
    elseif ContainsAny(normalized, P.RootPhrases[418]) then
        attr = "showHPText"
        label = "HP Text"
        numeric = false
    end
    if not attr then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            local value
            if setting then
                if numeric then
                    value = FirstNumber(normalized)
                elseif setting.type == "boolean" then
                    value = DetectBoolean(normalized)
                elseif P.ValueForRegistrySetting then
                    value = P.ValueForRegistrySetting(setting, normalized, normalized)
                end
            end
            if setting and value ~= nil then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or label) or label,
        bulkSafe = #changes > 1,
        summary = "Changes group-frame HP/Power text controls.",
    }
end

local function ParseGroupTextFormatFastShortcut(normalized)
    if ContainsAny(normalized, P.RootPhrases[419]) then
        return nil
    end
    if not ContainsAny(normalized, P.RootPhrases[420]) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[421]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    if ContainsAny(normalized, P.RootPhrases[422]) then
        attr = "powerTextDelimiter"
        label = "Power Text Delimiter"
        value = GroupTextDelimiterValue(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[423]) then
        attr = "textDelimiter"
        label = "HP Text Delimiter"
        value = GroupTextDelimiterValue(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[424]) then
        attr = "powerOffsetX"
        label = "Power Text X Offset"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[425]) then
        attr = "powerOffsetY"
        label = "Power Text Y Offset"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[426]) then
        attr = "powerTextLayer"
        label = "Power Text Layer"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[427]) then
        attr = "hpOffsetX"
        label = "HP Text X Offset"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[428]) then
        attr = "hpOffsetY"
        label = "HP Text Y Offset"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[429]) then
        attr = "textLayer"
        label = "HP Text Layer"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[430]) then
        attr = "hpTextReverse"
        label = "Reverse HP Text"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, P.RootPhrases[431]) then
        attr = "healthTextDecimals"
        label = "Health Text Decimals"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    end
    if not attr or value == nil then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or label) or label,
        bulkSafe = #changes > 1,
        summary = "Changes group-frame HP/Power text formatting.",
    }
end

local function GroupDispelOverlayTriggerValue(normalized)
    if ContainsAny(normalized, P.RootPhrases[434]) then return "BY_RAID" end
    if ContainsAny(normalized, P.RootPhrases[432]) then return "BY_ME" end
    if ContainsAny(normalized, P.RootPhrases[433]) then return "DISPEL_TYPE" end
    if ContainsAny(normalized, P.RootPhrases[435]) then return "BORDER" end
    return nil
end

local function GroupDispelOverlayStyleValue(normalized)
    if ContainsAny(normalized, P.RootPhrases[436]) then return "FULL" end
    if ContainsAny(normalized, P.RootPhrases[437]) then return "BOTTOM" end
    if ContainsAny(normalized, P.RootPhrases[438]) then return "TOP" end
    if ContainsAny(normalized, P.RootPhrases[439]) then return "LEFT" end
    if ContainsAny(normalized, P.RootPhrases[440]) then return "RIGHT" end
    return nil
end

function A._HasDispelOverlayAlphaIntent(normalized)
    return ContainsAny(normalized, { "opacity", "alpha", "max", "maximum", "min", "minimum", "half", "50 percent", "50%" })
        and not ContainsAny(normalized, { "style", "detects", "trigger", "detection", "current health", "on health" })
end

function A._HasDispelOverlayImplicitTriggerIntent(normalized)
    return ContainsAny(normalized, { "by me", "byme", "dispellable by me", "by group", "by raid", "dispellable by group", "any debuff", "all debuffs", "any dispel type", "dispel type", "dispeltype" })
        and not ContainsAny(normalized, { "turn on", "enable", "enabled", "on", "turn off", "disable", "disabled", "off" })
end

local function ParseGroupDispelOverlayFastShortcut(normalized)
    if ContainsAny(normalized, { "unitframe", "unit frame" }) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[441]) then
        return nil
    end
    -- A named copy category is still a copy request. Do not let the broad
    -- overlay fast path reinterpret "copy party dispel overlay to raid" as
    -- two enable-setting mutations before the action pipeline can preserve
    -- the requested source, target, transaction, and undo semantics.
    if P.ParseGroupCopy and P.ParseGroupCopy(normalized) then return nil end
    -- Page-navigation requests must reach ParseOpen; "open" is not an enable verb.
    if normalized:match("^open%s+") then return nil end
    if ContainsAny(normalized, P.RootPhrases[442]) then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[443]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    if A._HasDispelOverlayAlphaIntent(normalized) then
        attr = "dispelOverlayAlpha"
        label = "Dispel Overlay Opacity"
        value = A._DispelOverlayAlphaValue(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[444]) then
        attr = "dispelOverlayOnHealth"
        label = "Dispel Overlay on Current Health"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, P.RootPhrases[445]) then
        attr = "dispelOverlayTrigger"
        label = "Dispel Overlay Detects"
        value = GroupDispelOverlayTriggerValue(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[446]) then
        attr = "dispelOverlayStyle"
        label = "Dispel Overlay Style"
        value = GroupDispelOverlayStyleValue(normalized)
    elseif GroupDispelOverlayStyleValue(normalized) and DetectBoolean(normalized) == nil then
        attr = "dispelOverlayStyle"
        label = "Dispel Overlay Style"
        value = GroupDispelOverlayStyleValue(normalized)
    elseif A._HasDispelOverlayImplicitTriggerIntent(normalized) then
        attr = "dispelOverlayTrigger"
        label = "Dispel Overlay Detects"
        value = GroupDispelOverlayTriggerValue(normalized)
    else
        attr = "dispelOverlayEnabled"
        label = "Dispel Overlay"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    end
    if value == nil then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or label) or label,
        bulkSafe = #changes > 1,
        summary = "Changes group-frame dispel overlay options.",
    }
end

local function GroupRangeFadeLayerValue(normalized)
    if ContainsAny(normalized, P.RootPhrases[447]) then return "health" end
    if ContainsAny(normalized, P.RootPhrases[448]) then return "frame" end
    return nil
end

local function ParseGroupRangeFadeFastShortcut(normalized)
    if ContainsAny(normalized, P.RootPhrases[449]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[450]) then return nil end
    if not ContainsAny(normalized, P.RootPhrases[451]) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[452]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    if ContainsAny(normalized, P.RootPhrases[453]) then
        attr = "offlineAlpha"
        label = "Offline Opacity"
        value = FirstNumber(normalized)
        if value and value > 1 then value = value / 100 end
    elseif ContainsAny(normalized, P.RootPhrases[454]) then
        if ContainsAny(normalized, P.RootPhrases[455]) then
            attr = "healthFadeThreshold"
            label = "Health Fade Threshold"
            value = FirstNumber(normalized)
        elseif ContainsAny(normalized, P.RootPhrases[456]) then
            attr = "healthFadeAlpha"
            label = "Health Fade Opacity"
            value = FirstNumber(normalized)
            if value and value > 1 then value = value / 100 end
        else
            attr = "healthFadeEnabled"
            label = "Health Fade"
            value = DetectBoolean(normalized)
            if value == nil then value = true end
        end
    elseif ContainsAny(normalized, P.RootPhrases[457]) then
        attr = "rangeFadeLayerMode"
        label = "Range Fade Affects"
        value = GroupRangeFadeLayerValue(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[458]) or FirstNumber(normalized) ~= nil then
        attr = "rangeFadeAlpha"
        label = "Range Fade Alpha"
        value = FirstNumber(normalized)
        if value == nil then return nil end
        if value > 1 then value = value / 100 end
    else
        attr = "rangeFadeEnabled"
        label = "Range Fade"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    end
    if value == nil and attr ~= "offlineAlpha" then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then
                local relativeDelta = value == nil and P.RelativeNumberDeltaForText
                    and P.RelativeNumberDeltaForText(setting, normalized, 0.05) or nil
                if value ~= nil or relativeDelta ~= nil then
                    changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta }
                end
            end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or label) or label,
        bulkSafe = #changes > 1,
        summary = "Changes group-frame range, offline, or health fade options.",
    }
end

local function GroupCornerAnchorValue(normalized)
    if ContainsAny(normalized, P.RootPhrases[459]) then return "TOPLEFT" end
    if ContainsAny(normalized, P.RootPhrases[460]) then return "TOPRIGHT" end
    if ContainsAny(normalized, P.RootPhrases[461]) then return "BOTTOMLEFT" end
    if ContainsAny(normalized, P.RootPhrases[462]) then return "BOTTOMRIGHT" end
    if ContainsAny(normalized, P.RootPhrases[463]) then return "TOPLEFT" end
    if ContainsAny(normalized, P.RootPhrases[464]) then return "BOTTOMRIGHT" end
    return nil
end

local function ParseGroupNumberFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[465]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[466]) then
        return nil
    end

    local groups = DetectGroups(normalized)
    local hasConcreteGroupScope = ContainsAny(normalized, {
        "party", "party frame", "raid", "raid frame", "mythic raid", "mythicraid", "schlachtzug",
    })
    local explicitUnits = DetectUnits(normalized)
    if #explicitUnits > 0 and not hasConcreteGroupScope then
        -- Unit-frame "group number in name" is a different setting. An
        -- explicit Player/Target/etc. scope must not fan out to every group.
        local isLayer = ContainsAny(normalized, {
            "layer", "draw layer", "frame level", "strata", "frame strata", "ebene", "schicht",
        })
        local unitValue = isLayer and FirstNumber(normalized) or DetectBoolean(normalized)
        if unitValue == nil and not isLayer then unitValue = true end
        if unitValue == nil then return nil end
        local unitChanges = {}
        for i = 1, #explicitUnits do
            local suffix = isLayer and ".raidGroupNameLayer" or ".showRaidGroupInName"
            local setting = A.Registry and A.Registry:GetSetting(tostring(explicitUnits[i]) .. suffix)
            if setting then unitChanges[#unitChanges + 1] = { setting = setting, value = unitValue } end
        end
        if #unitChanges == 0 then return nil end
        return {
            kind = "changes",
            changes = unitChanges,
            label = #unitChanges == 1 and (unitChanges[1].setting.label or (isLayer and "Raid Group Name Layer" or "Raid Group Name")) or (isLayer and "Raid Group Name Layers" or "Raid Group Names"),
            bulkSafe = #unitChanges > 1,
            summary = isLayer and "Changes the unit-frame raid-group number layer."
                or "Changes the unit-frame raid-group number shown with the name.",
        }
    end
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[467]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    local relativeDelta
    if normalized:find("bigger", 1, true) or normalized:find("larger", 1, true)
        or normalized:find("smaller", 1, true)
    then
        attr = "groupNumberSize"
        label = "Group Number Size"
        relativeDelta = normalized:find("smaller", 1, true) and -1 or 1
    elseif ContainsAny(normalized, P.RootPhrases[468]) then
        attr = "groupNumberAnchor"
        label = "Group Number Anchor"
        value = GroupCornerAnchorValue(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[469]) then
        attr = "groupNumberX"
        label = "Group Number X Offset"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[470]) then
        attr = "groupNumberY"
        label = "Group Number Y Offset"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[471]) then
        attr = "groupNumberSize"
        label = "Group Number Size"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, {
        "layer", "draw layer", "frame level", "strata", "frame strata", "ebene", "schicht",
    }) then
        attr = "groupNumberLayer"
        label = "Group Number Layer"
        value = FirstNumber(normalized)
    else
        attr = "showGroupNumber"
        label = "Group Number"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    end
    if value == nil and relativeDelta == nil then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value, relativeDelta = relativeDelta } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or label) or label,
        bulkSafe = #changes > 1,
        summary = "Changes group-frame group-number display settings.",
    }
end

local function GroupAggroModeValue(normalized)
    if ContainsAny(normalized, P.RootPhrases[472]) then return "NON_TANK" end
    if ContainsAny(normalized, P.RootPhrases[473]) then return "HEALER" end
    if ContainsAny(normalized, P.RootPhrases[474]) then return "TANK" end
    if ContainsAny(normalized, P.RootPhrases[475]) then return "ALL" end
    return nil
end

local function ParseGroupHighlightFastShortcut(normalized)
    if ContainsAny(normalized, P.RootPhrases[476]) then
        return nil
    end
    if not ContainsAny(normalized, P.RootPhrases[477]) then
        return nil
    end

    if ContainsAny(normalized, P.RootPhrases[479]) then
        local value = FirstNumber(normalized)
        local setting = A.Registry and A.Registry:GetSetting("general.highlightThickness")
        if not (setting and value) then return nil end
        return {
            kind = "changes",
            changes = { { setting = setting, value = value } },
            label = setting.label or "Mouseover Highlight Size",
            summary = "Changes the global mouseover highlight size for unit and group frames.",
        }
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[478]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    if ContainsAny(normalized, P.RootPhrases[480]) then
        attr = "aggroMode"
        label = "Aggro Shows For"
        value = GroupAggroModeValue(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[481]) then
        attr = "aggroEnabled"
        label = "Aggro Border"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, P.RootPhrases[482]) then
        attr = "dispelEnabled"
        label = "Dispel Border"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, P.RootPhrases[483]) then
        attr = "targetIndicator"
        label = "Target Highlight"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, P.RootPhrases[484]) then
        attr = "hlFocusSize"
        label = "Focus Highlight Thickness"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[485]) then
        attr = "hlFocusOffset"
        label = "Focus Highlight Offset"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[486]) then
        attr = "hlFocusEnabled"
        label = "Focus Highlight"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    end
    if not attr or value == nil then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or label) or label,
        bulkSafe = #changes > 1,
        summary = "Changes group-frame highlight and fallback border settings.",
    }
end

local function ParseFullGroupBorderFastShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[487]) then
        return nil
    end
    if ContainsAny(normalized, P.RootPhrases[488]) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[489]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    if ContainsAny(normalized, P.RootPhrases[490]) then
        attr = "groupBorderPadding"
        label = "Group Border Padding"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[491]) then
        attr = "groupBorderA"
        label = "Group Border Opacity"
        value = FirstNumber(normalized)
        if value and value > 1 then value = value / 100 end
    elseif ContainsAny(normalized, P.RootPhrases[492]) then
        attr = "groupBorderSize"
        label = "Group Border Thickness"
        value = FirstNumber(normalized)
    else
        attr = "groupBorderEnabled"
        label = "Group Border"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    end
    if value == nil then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or label) or label,
        bulkSafe = #changes > 1,
        summary = "Changes the optional border around the whole group-frame block.",
    }
end

local function GroupStatusIconStyleValue(normalized)
    if ContainsAny(normalized, P.RootPhrases[493]) then return "MIDNIGHT" end
    if ContainsAny(normalized, P.RootPhrases[494]) then return "CLASSIC" end
    if ContainsAny(normalized, P.RootPhrases[495]) then return "BLIZZARD" end
    return nil
end

local function ParseGroupStatusIconStyleFastShortcut(normalized)
    if ContainsAny(normalized, P.RootPhrases[496]) then
        return nil
    end
    if not ContainsAny(normalized, P.RootPhrases[497]) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, P.RootPhrases[498]) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    if ContainsAny(normalized, P.RootPhrases[499])
        and not ContainsAny(normalized, P.RootPhrases[500])
    then
        attr = "useMidnightIcons"
        label = "Use Midnight Status Icons"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    else
        attr = "iconStyle"
        label = "Default Role Icon Style"
        value = GroupStatusIconStyleValue(normalized)
    end
    if value == nil then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. attr)
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or label) or label,
        bulkSafe = #changes > 1,
        summary = "Changes group-frame status icon style options.",
    }
end
local ParseUnitDetailMove = P.ParseUnitDetailMove
local ParseGroupDetailMove = P.ParseGroupDetailMove
local ParseAmbiguousGroupOutlineBorderShortcut = P.ParseAmbiguousGroupOutlineBorderShortcut
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
    if not ContainsAny(text, P.RootPhrases[501]) then return nil end
    if ContainsAny(text, P.RootPhrases[502]) then return nil end
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
                "unit aura", "unit auras",
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
                        summary = "Guides an incomplete group aura blacklist request.",
                        text = "MSUF can edit live group exact-SpellID and category exclusions. Tell me Party, Raid, or Mythic Raid; Buffs or Debuffs; and the SpellID/category. Example: 'blacklist spell 12345 in raid debuffs'. Blizzard can restrict identity-based filtering for some friendly harmful or hostile helpful auras, so I will report that instead of hiding a whole lane.",
                    }
                end
                local unitBlacklistScope = ContainsAny(text, P.AURA_UNIT_BLACKLIST_SCOPE_TERMS)
                if unitBlacklistScope and groupBlacklistIntent and (groupBlacklistDetail or text:find("blacklist", 1, true)) then
                    return {
                        kind = "unsupported",
                        status = "info",
                        summary = "Guides an incomplete unit aura blacklist request.",
                        text = "MSUF can edit live exact-SpellID exclusions for Player, Target, Focus, and Boss Buff or Debuff lanes. Give the frame, lane, and SpellID—for example, 'blacklist spell 12345 in target buffs'. Blizzard can restrict identity-based filtering for some friendly harmful or hostile helpful auras; that never authorizes hiding the whole lane.",
                    }
                end
                if ContainsAny(text, P.RootPhrases[503])
                    and ContainsAny(text, P.RootPhrases[504])
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
                    text = "I don't see a precise MSUF aura option in that wording yet. I can change lane visibility, permanent/no-expiration filtering, live tokens, exact SpellID/category lists, Custom Aura include lists, icon layout, timer/stack styling, presets, and group aura copy. Name the frame or group, Buffs or Debuffs, and what should be kept or hidden; if more than one control fits, I will offer choices.",
                }
            end
        end
    end
end
P.InitUnsupportedAuraCommand()

local function EarlyAuraShortcut(normalized, raw)
    local ctx = type(A.GetContext) == "function" and A.GetContext() or {}
    return (P.ParseAuraFilteringConversationShortcut and P.ParseAuraFilteringConversationShortcut(normalized, ctx, raw))
        or (P.ParseAuraFilterGuidanceShortcut and P.ParseAuraFilterGuidanceShortcut(normalized))
        or (A.RouterTryAuraFilterStatusShortcut and A.RouterTryAuraFilterStatusShortcut(normalized))
        or (P.ParseAuraScopeOverrideShortcut and P.ParseAuraScopeOverrideShortcut(normalized))
        -- Aura geometry owns words such as "grow". Resolve it before broad
        -- lane visibility so an open-ended request can offer Growth choices
        -- instead of treating "grow" as an implicit request to show buffs.
        or (P.AuraGeometryShortcut and P.AuraGeometryShortcut(normalized))
        or (P.ParseAuraDirectSettingShortcut and P.ParseAuraDirectSettingShortcut(normalized, raw))
        or (P.ParseUnitAuraFilterBooleanShortcut and P.ParseUnitAuraFilterBooleanShortcut(normalized))
        or (P.ParseGroupAuraLiveFilterShortcut and P.ParseGroupAuraLiveFilterShortcut(normalized))
        or (P.ParseUnitAuraLiveFilterShortcut and P.ParseUnitAuraLiveFilterShortcut(normalized))
        or (P.ParseAuraCooldownSwipeDirectionShortcut and P.ParseAuraCooldownSwipeDirectionShortcut(normalized))
        or (P.ParseAuraDurationBarShortcut and P.ParseAuraDurationBarShortcut(normalized))
        or (P.ParseAuraDebuffBorderModeShortcut and P.ParseAuraDebuffBorderModeShortcut(normalized))
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
    if ContainsAny(text, P.RootPhrases[505]) then return nil end
    local value
    if DetectBoolean then value = DetectBoolean(text) end
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

A._ParseGlobalStatusIconsStyleFastShortcut = function(text)
    if not ContainsAny(text, P.RootPhrases[506]) then
        return nil
    end
    if ContainsAny(text, P.RootPhrases[507]) then return nil end
    local setting = A.Registry and A.Registry:GetSetting("general.statusIconsUseMidnightStyle")
    if not setting then return nil end
    local value
    if DetectBoolean then value = DetectBoolean(text) end
    if value == nil then value = not ContainsAny(text, P.RootPhrases[508]) end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Status Icons Midnight Style",
        summary = "Changes the global unit-frame status icon Midnight style.",
    }
end

A._ParseUnitAnchorPointFastShortcut = function(text)
    if not ContainsAny(text, P.RootPhrases[509]) then return nil end
    if ContainsAny(text, P.RootPhrases[510]) then
        return nil
    end
    local units = DetectUnits and DetectUnits(text) or {}
    if #units == 0 then return nil end
    local changes = {}
    local seen = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        if unit ~= "" and not seen[unit] then
            seen[unit] = true
            local setting = A.Registry and A.Registry:GetSetting(unit .. ".point")
            local value = setting and P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, text, text) or nil
            if setting and value ~= nil then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Anchor Point") or "Anchor Point",
        bulkSafe = #changes > 1,
        summary = "Changes unit-frame anchor point.",
    }
end

A._ParseBossTargetHighlightFastShortcut = function(text)
    if not ContainsAny(text, P.RootPhrases[511]) then return nil end
    if ContainsAny(text, P.RootPhrases[512]) then return nil end
    local setting = A.Registry and A.Registry:GetSetting("general.bossTargetHighlightEnabled")
    if not setting then return nil end
    local value
    if DetectBoolean then value = DetectBoolean(text) end
    if value == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Boss Target Highlight",
        summary = "Changes Boss Target Highlight visibility.",
    }
end

A._ParseHumanIndicatorMoveFastShortcut = function(text)
    if not ContainsAny(text, P.RootPhrases[513]) then return nil end
    if ContainsAny(text, P.RootPhrases[514]) then return nil end
    local direction
    if ContainsAny(text, P.RootPhrases[515]) then
        direction = "right"
    elseif ContainsAny(text, P.RootPhrases[516]) then
        direction = "left"
    elseif ContainsAny(text, P.RootPhrases[517]) then
        direction = "up"
    elseif ContainsAny(text, P.RootPhrases[518]) then
        direction = "down"
    end
    if not direction then return nil end

    local axis = (direction == "left" or direction == "right") and "x" or "y"
    local amount = FirstNumber(text) or 10
    if direction == "left" or direction == "down" then amount = -amount end

    local unitSpecs = {
        { terms = { "raid group name", "raid group indicator", "raid group", "group number in name", "group number indicator", "subgroup indicator" }, x = "raidGroupNameOffsetX", y = "raidGroupNameOffsetY", label = "Raid Group Name" },
        { terms = { "raid marker", "raid marker icon", "raid marker indicator", "target marker", "target marker icon", "target marker indicator" }, x = "raidMarkerOffsetX", y = "raidMarkerOffsetY", label = "Raid Marker" },
        { terms = { "leader icon", "leader indicator", "assist icon", "assist indicator", "leader assist icon", "leader assist indicator" }, x = "leaderIconOffsetX", y = "leaderIconOffsetY", label = "Leader/Assist Icon" },
        { terms = { "level", "level indicator", "level text" }, x = "levelIndicatorOffsetX", y = "levelIndicatorOffsetY", label = "Level Indicator" },
        { terms = { "elite icon", "rare icon", "elite indicator", "rare indicator", "elite rare icon" }, x = "eliteIconOffsetX", y = "eliteIconOffsetY", label = "Elite / Rare Icon" },
        { terms = { "dead text", "status text", "offline text", "dead indicator", "offline indicator" }, x = "statusTextOffsetX", y = "statusTextOffsetY", label = "Dead Text" },
        { terms = { "combat indicator", "combat state indicator", "combat status indicator", "combat icon" }, x = "combatStateIndicatorOffsetX", y = "combatStateIndicatorOffsetY", label = "Combat Indicator" },
        { terms = { "rested indicator", "resting indicator", "rested icon", "resting icon" }, x = "restedStateIndicatorOffsetX", y = "restedStateIndicatorOffsetY", label = "Rested Indicator" },
        { terms = { "incoming rez", "incoming rez indicator", "incoming resurrection", "incoming resurrection indicator", "resurrection indicator", "resurrection icon", "rez indicator" }, x = "incomingResIndicatorOffsetX", y = "incomingResIndicatorOffsetY", label = "Incoming Rez Indicator" },
        { terms = { "pvp flag", "pvp indicator", "pvp icon", "war mode indicator", "flagged indicator" }, x = "pvpIndicatorOffsetX", y = "pvpIndicatorOffsetY", label = "PvP Flag Indicator" },
    }
    local groupSpecs = {
        { terms = { "ready check", "ready check icon", "ready check indicator", "ready icon", "ready indicator" }, x = "readyCheckX", y = "readyCheckY", label = "Ready Check" },
        { terms = { "role icon", "role indicator", "role symbol", "tank icon", "healer icon", "dps icon" }, x = "roleIconX", y = "roleIconY", label = "Role Icon" },
        { terms = { "leader icon", "leader indicator", "leader symbol" }, x = "leaderIconX", y = "leaderIconY", label = "Leader Icon" },
        { terms = { "assist icon", "assistant icon", "assist indicator", "assistant indicator" }, x = "assistIconX", y = "assistIconY", label = "Assist Icon" },
        { terms = { "raid marker", "raid marker icon", "raid marker indicator", "target marker", "target marker icon", "target marker indicator" }, x = "raidMarkerX", y = "raidMarkerY", label = "Raid Marker" },
        { terms = { "summon icon", "summon indicator", "summon symbol" }, x = "summonX", y = "summonY", label = "Summon Icon" },
        { terms = { "resurrect icon", "resurrect indicator", "resurrection icon", "resurrection indicator", "incoming resurrection", "incoming rez", "rez icon", "rez indicator" }, x = "resurrectX", y = "resurrectY", label = "Resurrection Icon" },
        { terms = { "phase icon", "phasing icon", "phase indicator", "phasing indicator" }, x = "phaseX", y = "phaseY", label = "Phase Icon" },
        { terms = { "pvp flag", "pvp icon", "pvp indicator", "war mode indicator", "flagged indicator" }, x = "pvpIconX", y = "pvpIconY", label = "PvP Icon" },
        { terms = { "dead text", "status text", "offline text", "offline indicator" }, x = "statusOffsetX", y = "statusOffsetY", label = "Status Text" },
        { terms = { "ghost text", "ghost indicator", "ghost status" }, x = "statusGhostOffsetX", y = "statusGhostOffsetY", label = "Ghost Text" },
        { terms = { "afk text", "dnd text", "afk indicator", "dnd indicator", "away text" }, x = "statusAFKOffsetX", y = "statusAFKOffsetY", label = "AFK/DND Text" },
    }
    local function matchSpec(specs)
        for i = 1, #specs do
            if ContainsAny(text, specs[i].terms) then return specs[i] end
        end
        return nil
    end

    -- A word that several specs share ("icon", "indicator", "marker" vs
    -- "target marker") identifies none of them, and the unit/scope nouns are in
    -- every request anyway. Only a word owned by exactly one spec can name it.
    local SUBJECT_WORD_STOPLIST = {
        icon = true, text = true, indicator = true, symbol = true, status = true,
        player = true, target = true, focus = true, pet = true, boss = true,
        party = true, raid = true, group = true, frame = true, name = true,
        number = true, incoming = true, check = true, state = true,
    }
    local function distinctiveSpecWords(specs)
        local owners = {}
        for i = 1, #specs do
            for j = 1, #specs[i].terms do
                for word in tostring(specs[i].terms[j]):gmatch("%a%a%a%a+") do
                    if not SUBJECT_WORD_STOPLIST[word] then
                        if owners[word] == nil then owners[word] = i
                        elseif owners[word] ~= i then owners[word] = false end
                    end
                end
            end
        end
        return owners
    end

    -- Players shorten the indicator once the conversation is already about it:
    -- "enable target leader icon" then "now move target leader up". The bare
    -- word is far too weak on its own -- "move target leader up" with no such
    -- history must keep meaning the frame -- so require the same distinctive
    -- word to appear both in this request and in the subject the previous turn
    -- established. That makes the shorthand a continuation of a named subject
    -- rather than a guess from an ambiguous noun.
    local function matchSpecFromSubject(specs)
        local ctx = type(A.GetContext) == "function" and A.GetContext() or nil
        if type(ctx) ~= "table" then return nil end
        -- A subject the player stopped talking about turns back into an
        -- ordinary noun. Use the same three-turn window every other follow-up
        -- honours (P.ContextSubjectRecent) so the shorthand cannot resurrect a
        -- stale topic. Computed inline rather than borrowed, because this file
        -- loads before Followups and a missing helper must not read as "fresh".
        local currentTurn = tonumber(ctx.turnSerial or ctx.lastTurnSerial) or 0
        local subjectTurn = tonumber(ctx.lastSubjectTurn or ctx.lastMentionedTurn)
        if not subjectTurn then return nil end
        local age = currentTurn - subjectTurn
        if age < 0 or age > 3 then return nil end
        local subject = Normalize(tostring(ctx.lastSetting or "") .. " " .. tostring(ctx.lastActionLabel or ""))
        if subject == "" then return nil end
        -- Walk the specs in their declared order, not the owners table's hash
        -- order, so two subjects that both qualify resolve the same way twice.
        local owners = distinctiveSpecWords(specs)
        for i = 1, #specs do
            for j = 1, #specs[i].terms do
                for word in tostring(specs[i].terms[j]):gmatch("%a%a%a%a+") do
                    if owners[word] == i and subject:find(word, 1, true)
                        and ContainsAny(text, { word }) then
                        return specs[i]
                    end
                end
            end
        end
        return nil
    end

    local units = DetectUnits(text)
    local groups = DetectGroups(text)
    local unitSpec = matchSpec(unitSpecs) or matchSpecFromSubject(unitSpecs)
    local groupSpec = matchSpec(groupSpecs) or matchSpecFromSubject(groupSpecs)
    local changes = {}
    local label
    if #units > 0 and unitSpec
        and (#groups == 0 or ContainsAny(text, P.RootPhrases[519]))
    then
        local spec = unitSpec
        if not spec then return nil end
        local key = axis == "x" and spec.x or spec.y
        local seen = {}
        for i = 1, #units do
            local unit = tostring(units[i])
            if unit ~= "" and not seen[unit] then
                seen[unit] = true
                local setting = A.Registry and A.Registry:GetSetting(unit .. "." .. key)
                if setting then changes[#changes + 1] = { setting = setting, relativeDelta = amount, direction = direction } end
            end
        end
        label = spec.label
    elseif #groups > 0 and groupSpec and #units == 0 then
        local spec = groupSpec
        if not spec then return nil end
        local key = axis == "x" and spec.x or spec.y
        local seen = {}
        for i = 1, #groups do
            local scope = tostring(groups[i])
            if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
                seen[scope] = true
                local setting = A.Registry and A.Registry:GetSetting("gf_" .. scope .. "." .. key)
                if setting then changes[#changes + 1] = { setting = setting, relativeDelta = amount, direction = direction } end
            end
        end
        label = spec.label
    else
        return nil
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or label or "Indicator Position") or (label or "Indicator Position"),
        bulkSafe = #changes > 1,
        summary = "Moves the requested unit/group-frame indicator with its X/Y offset.",
    }
end

local function ParseClassResourceFillFastShortcut(text)
    if not ContainsAny(text, P.RootPhrases[520]) then return nil end
    if ContainsAny(text, P.RootPhrases[521]) and not ContainsAny(text, P.RootPhrases[522]) then
        local direction = DetectDirection and DetectDirection(text, {}) or nil
        local key
        local fallback = 10
        if ContainsAny(text, P.RootPhrases[523]) then
            key = "bars.classPowerFrameLevelOffset"
            fallback = 1
        elseif direction == "left" or direction == "right" or ContainsAny(text, P.RootPhrases[524]) then
            key = "bars.classPowerOffsetX"
        elseif direction == "up" or direction == "down" or ContainsAny(text, P.RootPhrases[525]) then
            key = "bars.classPowerOffsetY"
        end
        local setting = key and A.Registry and A.Registry:GetSetting(key) or nil
        if setting then
            local relativeDelta = P.RelativeNumberDeltaForText and P.RelativeNumberDeltaForText(setting, text, fallback) or nil
            local value
            if relativeDelta == nil then value = FirstNumber and FirstNumber(text) or nil end
            if value ~= nil or relativeDelta ~= nil then
                return {
                    kind = "changes",
                    changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
                    label = setting.label or "Class Resource Position",
                    summary = "Moves or layers the Class Resource frame.",
                }
            end
        end
    end
    if ContainsAny(text, P.RootPhrases[526]) then
        return nil
    end
    if not ContainsAny(text, P.RootPhrases[527]) then return nil end

    local value
    local boolValue
    if DetectBoolean then boolValue = DetectBoolean(text) end
    if ContainsAny(text, P.RootPhrases[528]) then
        value = false
    elseif ContainsAny(text, P.RootPhrases[529]) then
        value = true
    elseif ContainsAny(text, P.RootPhrases[530]) then
        value = boolValue
        if value == nil and ContainsAny(text, P.RootPhrases[531]) then value = true end
        if value == nil and ContainsAny(text, P.RootPhrases[532]) then value = false end
    end
    if value == nil then return nil end

    local setting = A.Registry and A.Registry:GetSetting("bars.classPowerFillReverse")
    return setting and {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Class Resource Reverse Fill",
        summary = "Changes the Class Resource fill direction.",
    } or nil
end

local function ParseAuraBlacklistPresetFastShortcut(text)
    if not ContainsAny(text, P.RootPhrases[533]) then return nil end
    if ContainsAny(text, P.RootPhrases[534]) then return nil end
    if not ContainsAny(text, P.RootPhrases[535]) then return nil end
    local setting = A.Registry and A.Registry:GetSetting("menu.auraBlacklistPreset")
    if not setting then return nil end
    local value = P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, text, text) or nil
    if value == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Aura Blacklist Preset",
        summary = "Changes the aura blacklist preset selector.",
    }
end

local function ParseDispelBorderTriggerFastShortcut(text)
    if not ContainsAny(text, P.RootPhrases[536]) then return nil end
    if ContainsAny(text, P.RootPhrases[537]) then return nil end
    if #(DetectUnits and DetectUnits(text) or {}) > 0 or #(DetectGroups and DetectGroups(text) or {}) > 0 then return nil end
    local setting = A.Registry and A.Registry:GetSetting("general.dispelBorderTrigger")
    if not setting then return nil end
    local value = P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, text, text) or nil
    if value == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Dispel Border Detects",
        summary = "Changes which dispellable auras can trigger the global dispel border.",
    }
end

function A._DispelBorderTriggerValue(setting, text)
    local value = GroupDispelOverlayTriggerValue(text)
    if value == "BORDER" then value = nil end
    if value == nil and setting and P.EnumValueForText then value = P.EnumValueForText(setting, text) end
    if value == nil and setting and P.ValueForRegistrySetting then value = P.ValueForRegistrySetting(setting, text, text) end
    return value
end

function A._ParseScopedDispelBorderTriggerFastShortcut(text)
    if not ContainsAny(text, P.RootPhrases[536]) then return nil end
    if ContainsAny(text, P.RootPhrases[537]) then return nil end
    local units = DetectUnits and DetectUnits(text) or {}
    if #units == 0 then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        if unit ~= "" and not seen[unit] then
            seen[unit] = true
            local setting = A.Registry and A.Registry:GetSetting("barScope." .. unit .. ".dispelBorderTrigger")
            local value = setting and A._DispelBorderTriggerValue(setting, text) or nil
            if setting and value ~= nil then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Dispel Border Detects") or "Dispel Border Detects",
        bulkSafe = #changes > 1,
        summary = "Changes which dispellable auras can trigger scoped unit-frame dispel borders.",
    }
end

local function ParseUnitPortraitShapeFastShortcut(text)
    if not ContainsAny(text, P.RootPhrases[538]) then return nil end
    if ContainsAny(text, P.RootPhrases[539]) then return nil end
    local units = DetectUnits and DetectUnits(text) or {}
    if #units == 0 then return nil end
    local changes = {}
    local seen = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        if unit ~= "" and not seen[unit] then
            seen[unit] = true
            local setting = A.Registry and A.Registry:GetSetting(unit .. ".portraitShape")
            local value = setting and P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, text, text) or nil
            if setting and value ~= nil then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = #changes == 1 and (changes[1].setting.label or "Portrait Shape") or "Portrait Shape",
        bulkSafe = #changes > 1,
        summary = "Changes unit-frame portrait shape.",
    }
end

local function ParseClassPowerTextOffsetShortcut(text)
    if not ContainsAny(text, P.RootPhrases[540]) then return nil end
    if ContainsAny(text, P.RootPhrases[541]) then return nil end
    if not ContainsAny(text, P.RootPhrases[542]) then return nil end
    local axis
    if ContainsAny(text, P.RootPhrases[543]) or HasPhrase and HasPhrase(text, "x") then
        axis = "X"
    elseif ContainsAny(text, P.RootPhrases[544]) or HasPhrase and HasPhrase(text, "y") then
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
    "indicator", "indicators", "marker", "markers", "raid marker", "target marker",
    "symbol", "symbols", "star", "circle", "diamond", "triangle", "moon", "square",
    "cross", "skull", "portrait", "range fade", "alpha", "opacity",
    "width", "height", "size", "anchor", "position", "move", "offset",
    "gradient", "gradients", "bar gradient", "bar gradients", "gradient direction",
    "load condition", "load conditions", "visibility condition", "when", "while",
    "in group", "grouped", "solo", "mounted", "vehicle", "instance", "combat",
    "resting", "stealth", "housing",
}

A.UnitRaidMarkerSymbolTerms = A.UnitRaidMarkerSymbolTerms or {
    "star", "circle", "diamond", "triangle", "moon", "square", "cross", "skull",
}

A._ParseUnitRaidMarkerVisibilityShortcut = A._ParseUnitRaidMarkerVisibilityShortcut or function(text)
    local hasNamedMarker = ContainsAny(text, { "raid marker", "raidmarker", "target marker" })
    local hasWoWSymbol = ContainsAny(text, A.UnitRaidMarkerSymbolTerms)
        and ContainsAny(text, { "marker", "icon", "symbol", "mark" })
    if not hasNamedMarker and not hasWoWSymbol then return nil end
    if ContainsAny(text, {
        "size", "width", "height", "position", "move", "offset", "anchor", "layer",
        "style", "preview", "test", "which", "what", "where", "how", "help", "explain",
    }) then
        return nil
    end
    local value
    if DetectBoolean then value = DetectBoolean(text) end
    if value == nil then return nil end
    local units = DetectUnits and DetectUnits(text) or {}
    if #units == 0 then return nil end

    local Registry = A.Registry
    local changes = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        local setting = Registry and Registry.GetSetting and Registry:GetSetting(unit .. ".showRaidMarker")
        if setting then changes[#changes + 1] = { setting = setting, value = value } end
    end
    if #changes == 0 then return nil end
    local unitLabel = tostring(units[1] or "Unit"):gsub("^%l", string.upper)
    if A and type(A.DisplayUnitLabel) == "function" then unitLabel = A.DisplayUnitLabel(units[1]) end
    local label = #changes == 1 and (unitLabel .. " Raid Marker") or "Unit Raid Markers"
    return {
        kind = "changes",
        changes = changes,
        label = label,
        bulkSafe = #changes > 1,
        summary = "Changes whether the actual WoW raid-target marker is shown on the requested unit frame.",
    }
end

local function UnitRootVisibilityValue(text)
    if ContainsAny(text, P.RootPhrases[545]) then return false end
    if ContainsAny(text, P.RootPhrases[546]) then return true end
    if DetectBoolean then return DetectBoolean(text) end
    return nil
end

local function UnitRootLabel(unit)
    if A and type(A.DisplayUnitLabel) == "function" then return A.DisplayUnitLabel(unit) end
    if unit == "targettarget" then return "Target of Target" end
    if unit == "focustarget" then return "Focus Target" end
    return tostring(unit or "Unit"):gsub("^%l", string.upper)
end

local function ParseUnitRootVisibilityShortcut(text)
    if not ContainsAny(text, P.RootPhrases[547]) then return nil end
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
    if not ContainsAny(text, P.RootPhrases[548]) then return nil end
    if ContainsAny(text, P.RootPhrases[549]) then return nil end

    local groups = DetectGroups and DetectGroups(text) or {}
    if #groups == 0 then return nil end

    local attr
    local title = "Group Debuff Stripe"
    if ContainsAny(text, P.RootPhrases[550]) then
        attr = "debuffStripeEdge"
        title = "Debuff Stripe Edge"
    elseif ContainsAny(text, P.RootPhrases[551]) then
        attr = "debuffStripeAlpha"
        title = "Debuff Stripe Opacity"
    elseif ContainsAny(text, P.RootPhrases[552]) then
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
    result = P.BuildContinuationFollowup and P.BuildContinuationFollowup(normalized, ctx); if result then return result end
    result = BuildBooleanCorrection(normalized, ctx); if result then return result end
    result = P.ParseFrameRecovery and P.ParseFrameRecovery(normalized); if result then return result end
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
    result = ParseCastbarGlobalDetail(normalized); if result then return result end
    result = P.ParseGroupStatusIconDetail and P.ParseGroupStatusIconDetail(normalized); if result then return result end
    if HasPhrase(normalized, "portrait") or HasPhrase(normalized, "portraits") then
        result = P.ParseGenericOffsetMove and P.ParseGenericOffsetMove(normalized); if result then return result end
    end
    result = P.ParseExactRegistryKeyShortcut and P.ParseExactRegistryKeyShortcut(normalized, raw); if result then return result end
    result = P.ParseExactActionKeyShortcut and P.ParseExactActionKeyShortcut(normalized, raw); if result then return result end
    result = P.ParseExactActionPhraseShortcut and P.ParseExactActionPhraseShortcut(normalized, raw); if result then return result end
    result = P.ParseRegistryActionAliasShortcut and P.ParseRegistryActionAliasShortcut(normalized, raw); if result then return result end
    -- The phrase "Class Resources Player Power" names the detached Player
    -- power controls on that page. Resolve it before broad Class Resource
    -- registry aliases can consume only "class resource width/anchor".
    result = A._ParseClassPowerDetachedPlayerPowerShortcut and A._ParseClassPowerDetachedPlayerPowerShortcut(normalized, raw); if result then return result end
    result = P.ParseRegistryPriorityShortcut and P.ParseRegistryPriorityShortcut(normalized, raw); if result then return result end
    result = P.ParseRegistryExactAliasShortcut and P.ParseRegistryExactAliasShortcut(normalized, raw); if result then return result end
    result = ParseClassPowerRootToggle and ParseClassPowerRootToggle(normalized); if result then return result end
    result = A._ParseClassPowerWidthModeShortcut and A._ParseClassPowerWidthModeShortcut(normalized); if result then return result end
    result = A._ParseClassPowerVisibilityShortcut and A._ParseClassPowerVisibilityShortcut(normalized); if result then return result end
    result = A._ParseClassPowerAnchorShortcut and A._ParseClassPowerAnchorShortcut(normalized); if result then return result end
    result = A._ParseClassPowerPlacementShortcut and A._ParseClassPowerPlacementShortcut(normalized); if result then return result end
    result = A._ParseClassPowerDisplayStyleShortcut and A._ParseClassPowerDisplayStyleShortcut(normalized); if result then return result end
    result = A._ParseClassPowerShapeShortcut and A._ParseClassPowerShapeShortcut(normalized); if result then return result end
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
    result = P.ParseNameShorteningShortcut and P.ParseNameShorteningShortcut(normalized, ctx, raw); if result then return result end
    result = ParseGuidedSetup(normalized); if result then return result end
    result = ParseScopedHelp(normalized); if result then return result end
    result = P.ParseGroupPowerBarSizeShortcut and P.ParseGroupPowerBarSizeShortcut(normalized); if result then return result end
    result = P.ParsePowerBarSizeShortcut and P.ParsePowerBarSizeShortcut(normalized); if result then return result end
    result = P.ParseMiscRegistryShortcut(normalized, raw); if result then return result end
    result = ParseSupportWorkflow(normalized, raw); if result then return result end
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
    result = A._ParseTextSlotValueMoveShortcut(normalized); if result then return result end
    result = A._ParseTextSlotOffsetShortcut(normalized); if result then return result end
    result = A._ParseTextAreaOffsetShortcut(normalized); if result then return result end
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
    result = ParseAmbiguousGroupOutlineBorderShortcut and ParseAmbiguousGroupOutlineBorderShortcut(normalized); if result then return result end
    if LooksLikeBarOutlineHighlightCommand(normalized) then
        result = ParseBarOutlineHighlightShortcut and ParseBarOutlineHighlightShortcut(normalized); if result then return result end
    end
    result = ParseBorderThicknessShortcut(normalized); if result then return result end
    result = A._ParseTextDetailExactOffset(normalized); if result then return result end
    result = ParseUnitDetailOffsetShortcut(normalized); if result then return result end
    result = ParseCastbarTextMoveShortcut(normalized); if result then return result end
    result = A._ParseGroupRangeFadeShortcut(normalized); if result then return result end
    result = A._ParseGroupOpacityShortcut(normalized); if result then return result end
    -- Last geometry attempt: a bare "name to the left/right" (no move verb, no
    -- anchor/align word) is genuinely ambiguous between anchor and offset, so
    -- ask instead of letting it fall through to a generic no-match.
    if A._ParseNameDirectionAmbiguityShortcut then
        result = A._ParseNameDirectionAmbiguityShortcut(normalized); if result then return result end
    end
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
    result = P.ParseNameShorteningShortcut and P.ParseNameShorteningShortcut(normalized, ctx, raw); if result then return result end
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

local function ParseBarGradientPriorityShortcut(normalized)
    return (P.ParseBarGradientRegistryShortcut and P.ParseBarGradientRegistryShortcut(normalized))
        or (P.ParsePowerBarGradientRegistryShortcut and P.ParsePowerBarGradientRegistryShortcut(normalized))
end
A._ParseBarGradientPriorityShortcut = ParseBarGradientPriorityShortcut

local function ParseGlobalBarModePriorityShortcut(normalized)
    if ContainsAny(normalized, P.RootPhrases[553]) then
        return nil
    end
    if not ContainsAny(normalized, P.RootPhrases[554]) then
        return nil
    end
    local setting = A.Registry and A.Registry:GetSetting("general.barMode")
    local value = setting and P.EnumValueForText and P.EnumValueForText(setting, normalized) or nil
    if value == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = "Global Bar Mode",
        summary = "Changes the global Unit Frame bar color mode.",
    }
end
A._ParseGlobalBarModePriorityShortcut = ParseGlobalBarModePriorityShortcut

local function ParseGlobalBarTexturePriorityShortcut(normalized, raw)
    if not ContainsAny(normalized, P.RootPhrases[555]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[556]) then
        return nil
    end

    -- Power art is a separate shared pair in the bars table. This shortcut
    -- owns the whole "<something> bar texture" phrasing family, so it resolves
    -- the power keys here rather than letting them fall through to alias
    -- matching, where they would tie with the per-unit power textures.
    local power = ContainsAny(normalized, P.RootPhrases[813])
    local background = ContainsAny(normalized, P.RootPhrases[557])
    local key
    if background then
        key = power and "bars.powerBarBgTexture" or "general.barBackgroundTexture"
    else
        key = power and "bars.powerBarTexture" or "general.barTexture"
    end

    local setting = A.Registry and A.Registry:GetSetting(key)
    if not setting then return nil end
    local value = P.RawAfterLastConnector and P.RawAfterLastConnector(raw or normalized, { " to ", " as ", " = " }) or nil
    if value == nil or value == "" then
        value = P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, normalized, raw or normalized) or nil
    end
    if value == nil or value == "" then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Global Bar Texture",
        summary = "Changes the shared MSUF bar texture.",
    }
end
A._ParseGlobalBarTexturePriorityShortcut = ParseGlobalBarTexturePriorityShortcut

local function ParseGlobalGradientStrengthPriorityShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[558]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[559]) then
        return nil
    end
    local setting = A.Registry and A.Registry:GetSetting("general.gradientStrength")
    if not setting then return nil end
    local value = FirstNumber(normalized)
    if value == nil then return nil end
    -- Gradient strength is stored 0..1. Requiring a literal "%" made this lane
    -- disagree with the central value path, which converts whenever the number
    -- exceeds the range: "set ... to 50" resolved to 0.5 while "i want ... to
    -- be 50" kept 50 and clamped to full strength. Nobody means 1.0 by "50".
    if value > 1 then
        value = value / 100
    end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Bar Gradient Strength",
        summary = "Changes the shared MSUF bar gradient strength.",
    }
end
A._ParseGlobalGradientStrengthPriorityShortcut = ParseGlobalGradientStrengthPriorityShortcut

-- [560] spells the adjective ("rounded party frames"). Players just as often
-- use "round" as a verb with the frames as its object -- "don't round my party
-- and raid frames" -- and that sentence then fell through to a two-word alias
-- match on "raid frames" that planned to DISABLE the raid frames. Matching the
-- bare word would also hit "background" and "surround", so require it as a
-- whole word.
local ROUNDED_VERB_PATTERN = "%f[%w]rounds?%f[%W]"

local function ParseGlobalRoundedBarsPriorityShortcut(normalized)
    local verbForm = false
    if not ContainsAny(normalized, P.RootPhrases[560]) then
        if not normalized:find(ROUNDED_VERB_PATTERN) then return nil end
        verbForm = true
    end
    if ContainsAny(normalized, P.RootPhrases[561]) then
        return nil
    end

    local key
    if ContainsAny(normalized, P.RootPhrases[562]) then
        key = "bars.roundedMouseover"
    elseif ContainsAny(normalized, P.RootPhrases[563]) then
        key = "bars.roundedPowerBars"
    elseif ContainsAny(normalized, P.RootPhrases[564]) then
        key = "bars.roundedGroupFrames"
    elseif ContainsAny(normalized, P.RootPhrases[565]) then
        key = "bars.roundedUnitFrames"
    -- The verb form names its object as a bare noun, so the adjective lists
    -- above cannot see it. Consulted only in that case: a sentence they already
    -- placed keeps the control they chose.
    elseif verbForm and ContainsAny(normalized, P.RootPhrases[814]) then
        key = "bars.roundedMouseover"
    elseif verbForm and ContainsAny(normalized, P.RootPhrases[815]) then
        key = "bars.roundedPowerBars"
    elseif verbForm and ContainsAny(normalized, P.RootPhrases[816]) then
        key = "bars.roundedGroupFrames"
    elseif verbForm and ContainsAny(normalized, P.RootPhrases[817]) then
        key = "bars.roundedUnitFrames"
    else
        key = "bars.roundedFramesEnabled"
    end

    local setting = A.Registry and A.Registry:GetSetting(key)
    if not setting then return nil end
    local value = DetectBoolean(normalized)
    if value == nil then value = true end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Rounded Frame Texture",
        summary = "Changes MSUF rounded bar/frame texture options.",
    }
end
A._ParseGlobalRoundedBarsPriorityShortcut = ParseGlobalRoundedBarsPriorityShortcut

local function ParseGlobalUnitDispelOverlayPriorityShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[566]) then return nil end
    if normalized:match("^open%s+") then return nil end
    if ContainsAny(normalized, P.RootPhrases[567]) then
        return nil
    end

    local key
    local value
    if A._HasDispelOverlayAlphaIntent(normalized) then
        key = "general.unitDispelOverlayAlpha"
        value = A._DispelOverlayAlphaValue(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[568]) or A._HasDispelOverlayImplicitTriggerIntent(normalized) then
        key = "general.unitDispelOverlayTrigger"
    elseif ContainsAny(normalized, P.RootPhrases[569]) then
        key = "general.unitDispelOverlayStyle"
    elseif GroupDispelOverlayStyleValue(normalized) and DetectBoolean(normalized) == nil then
        key = "general.unitDispelOverlayStyle"
    elseif ContainsAny(normalized, P.RootPhrases[570]) then
        key = "general.unitDispelOverlayOnHealth"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, P.RootPhrases[571]) then
        key = "general.unitDispelOverlayAlpha"
        value = A._DispelOverlayAlphaValue(normalized)
        if value == nil then return nil end
    else
        key = "general.unitDispelOverlayEnabled"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    end

    local setting = A.Registry and A.Registry:GetSetting(key)
    if not setting then return nil end
    if value == nil then
        if setting.type == "enum" then
            value = P.EnumValueForText and P.EnumValueForText(setting, normalized) or nil
        else
            value = P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, normalized, normalized) or nil
        end
    end
    if value == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "UnitFrame Dispel Overlay",
        summary = "Changes the global unit-frame dispel overlay option.",
    }
end
A._ParseGlobalUnitDispelOverlayPriorityShortcut = ParseGlobalUnitDispelOverlayPriorityShortcut

local function ParseScopedUnitDispelOverlayPriorityShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[572]) then return nil end
    if normalized:match("^open%s+") then return nil end
    if ContainsAny(normalized, P.RootPhrases[573]) then
        return nil
    end

    local units = DetectUnits and DetectUnits(normalized) or {}
    if #units == 0 then return nil end

    local suffix
    local value
    if A._HasDispelOverlayAlphaIntent(normalized) then
        suffix = "unitDispelOverlayAlpha"
        value = A._DispelOverlayAlphaValue(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[574]) or A._HasDispelOverlayImplicitTriggerIntent(normalized) then
        suffix = "unitDispelOverlayTrigger"
    elseif ContainsAny(normalized, P.RootPhrases[575]) then
        suffix = "unitDispelOverlayStyle"
    elseif GroupDispelOverlayStyleValue(normalized) and DetectBoolean(normalized) == nil then
        suffix = "unitDispelOverlayStyle"
    elseif ContainsAny(normalized, P.RootPhrases[576]) then
        suffix = "unitDispelOverlayOnHealth"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, P.RootPhrases[577]) then
        suffix = "unitDispelOverlayAlpha"
        value = A._DispelOverlayAlphaValue(normalized)
        if value == nil then return nil end
    else
        suffix = "unitDispelOverlayEnabled"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    end

    local changes = {}
    local seen = {}
    for i = 1, #units do
        local unit = tostring(units[i])
        if not seen[unit] then
            seen[unit] = true
            local setting = A.Registry and A.Registry:GetSetting("barScope." .. unit .. "." .. suffix)
            if setting then
                local settingValue = value
                if settingValue == nil then
                    if setting.type == "enum" then
                        settingValue = P.EnumValueForText and P.EnumValueForText(setting, normalized) or nil
                    else
                        settingValue = P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, normalized, normalized) or nil
                    end
                end
                if settingValue ~= nil then changes[#changes + 1] = { setting = setting, value = settingValue } end
            end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "UnitFrame Dispel Overlay",
        bulkSafe = #changes > 1,
        summary = "Changes scoped unit-frame dispel overlay options.",
    }
end
A._ParseScopedUnitDispelOverlayPriorityShortcut = ParseScopedUnitDispelOverlayPriorityShortcut

local function ParseGlobalPowerBarDetailPriorityShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[578]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[579]) then
        return nil
    end

    local key = ContainsAny(normalized, P.RootPhrases[580])
        and "bars.realtimePowerText"
        or "bars.smoothPowerBar"
    local setting = A.Registry and A.Registry:GetSetting(key)
    if not setting then return nil end
    local value = DetectBoolean(normalized)
    if value == nil then value = true end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = setting.label or "Power Bar",
        summary = "Changes the shared MSUF power bar detail option.",
    }
end
A._ParseGlobalPowerBarDetailPriorityShortcut = ParseGlobalPowerBarDetailPriorityShortcut

local function ParseScopedBarOverridePriorityShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[581]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[582]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[583]) then
        return nil
    end

    local scopes = {}
    local units = DetectUnits and DetectUnits(normalized) or {}
    for i = 1, #units do scopes[#scopes + 1] = tostring(units[i]) end
    local groups = DetectGroups and DetectGroups(normalized) or {}
    for i = 1, #groups do scopes[#scopes + 1] = "gf_" .. tostring(groups[i]) end
    if #scopes == 0 then return nil end

    local value = DetectBoolean(normalized)
    if value == nil then value = true end
    local changes = {}
    local seen = {}
    for i = 1, #scopes do
        local scope = tostring(scopes[i])
        if not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("barScope." .. scope .. ".override")
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Bars Override",
        bulkSafe = #changes > 1,
        summary = "Changes scoped Global Bars override toggles.",
    }
end
A._ParseScopedBarOverridePriorityShortcut = ParseScopedBarOverridePriorityShortcut

local function ParseScopedGradientStrengthPriorityShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[584]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[585]) then
        return nil
    end

    local scopes = {}
    local units = DetectUnits and DetectUnits(normalized) or {}
    for i = 1, #units do scopes[#scopes + 1] = tostring(units[i]) end
    local groups = DetectGroups and DetectGroups(normalized) or {}
    for i = 1, #groups do scopes[#scopes + 1] = "gf_" .. tostring(groups[i]) end
    if #scopes == 0 then return nil end

    local value = FirstNumber(normalized)
    if value == nil then return nil end
    -- Gradient strength is stored 0..1. Requiring a literal "%" made this lane
    -- disagree with the central value path, which converts whenever the number
    -- exceeds the range: "set ... to 50" resolved to 0.5 while "i want ... to
    -- be 50" kept 50 and clamped to full strength. Nobody means 1.0 by "50".
    if value > 1 then
        value = value / 100
    end

    -- "power gradient strength" names the power bar's own key; the unsuffixed
    -- one belongs to the health bar (see P.PowerGradientKeyForScope).
    local powerOnly = ContainsAny(normalized, {
        "power", "power bar", "mana", "energy", "rage", "focus bar", "resource",
        "energieleiste", "manaleiste", "ressource",
    }) and not ContainsAny(normalized, { "health", "hp", "hitpoints", "leben", "lebensleiste" })

    local changes = {}
    local seen = {}
    for i = 1, #scopes do
        local scope = tostring(scopes[i])
        if not seen[scope] then
            seen[scope] = true
            local key = P.PowerGradientKeyForScope
                and P.PowerGradientKeyForScope(scope, "powerGradientStrength", powerOnly, false)
                or nil
            local setting = A.Registry and A.Registry:GetSetting(key or ("barScope." .. scope .. ".gradientStrength"))
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = powerOnly and "Power Bar Gradient Strength" or "Bar Gradient Strength",
        bulkSafe = #changes > 1,
        summary = "Changes scoped MSUF bar gradient strength.",
    }
end
A._ParseScopedGradientStrengthPriorityShortcut = ParseScopedGradientStrengthPriorityShortcut

local function ParseGlobalFontPriorityShortcut(normalized, raw)
    if ContainsAny(normalized, P.RootPhrases[586]) then
        return nil
    end

    local key
    local label
    local value
    if ContainsAny(normalized, P.RootPhrases[587]) then
        key = "general.fontSize"
        label = "Global Font Size"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, P.RootPhrases[588]) then
        if ContainsAny(normalized, P.RootPhrases[589]) then return nil end
        key = "general.fontColor"
        label = "Global Font Palette Color"
    elseif ContainsAny(normalized, P.RootPhrases[590]) then
        key = "general.fontKey"
        label = "Global Font"
    else
        return nil
    end

    local setting = A.Registry and A.Registry:GetSetting(key)
    if not setting then return nil end
    if value == nil then
        if key == "general.fontKey" and A.MediaResolver and type(A.MediaResolver.Find) == "function" then
            local query = P.RawAfterLastConnector and P.RawAfterLastConnector(raw or normalized) or nil
            if query and query ~= "" then
                local media = A.MediaResolver.Find("font", query, { limit = 8 })
                if media and media.status == "exact" and media.value ~= nil then
                    value = media.value
                elseif media and media.status == "none" then
                    local textOut = A.MediaResolver.NoMatchMessage and A.MediaResolver.NoMatchMessage(media.mediaType, media.query) or "That font is not in the current MSUF media list."
                    return { kind = "unknown", text = textOut, status = "failed" }
                elseif media and media.status == "choices" and type(media.choices) == "table" then
                    local choices = {}
                    for i = 1, #media.choices do
                        local item = media.choices[i]
                        choices[#choices + 1] = {
                            setting = setting,
                            value = item.value,
                            valueLabel = item.label or item.value,
                            label = type(A.DisplaySettingValueLabel) == "function" and A.DisplaySettingValueLabel(setting, item.label or item.value, "Option") or (tostring(setting.label or "Option") .. ": " .. tostring(item.label or item.value)),
                            mediaType = "font",
                            mediaChoice = true,
                        }
                    end
                    if #choices > 0 then
                        return { kind = "ambiguous", choices = choices, label = "Which font?", summary = "Asks which matching font should be used." }
                    end
                end
            end
        end
        if value == nil then value = P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, normalized, raw or normalized) or nil end
    end
    if value == nil then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value } },
        label = label,
        summary = "Changes a global font option.",
    }
end
A._ParseGlobalFontPriorityShortcut = ParseGlobalFontPriorityShortcut

local function ParseFontScopePriorityShortcut(normalized)
    if not ContainsAny(normalized, P.RootPhrases[591]) then return nil end
    if ContainsAny(normalized, P.RootPhrases[592]) then
        return nil
    end

    local scopes = {}
    local units = DetectUnits and DetectUnits(normalized) or {}
    for i = 1, #units do scopes[#scopes + 1] = tostring(units[i]) end
    local groups = DetectGroups and DetectGroups(normalized) or {}
    for i = 1, #groups do scopes[#scopes + 1] = "gf_" .. tostring(groups[i]) end
    if #scopes == 0 and ContainsAny(normalized, P.RootPhrases[593]) then
        scopes[#scopes + 1] = "shared"
    end
    if #scopes == 0 and ContainsAny(normalized, P.RootPhrases[594]) then
        scopes[#scopes + 1] = "shared"
    end
    if #scopes == 0 and ContainsAny(normalized, P.RootPhrases[595]) then
        scopes[#scopes + 1] = "shared"
    end
    if #scopes == 0 then return nil end

    local suffix
    local value
    if ContainsAny(normalized, P.RootPhrases[596]) then
        suffix = "override"
    elseif ContainsAny(normalized, P.RootPhrases[597]) then
        suffix = "fontSize"
        value = FirstNumber(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, P.RootPhrases[598]) then
        suffix = "outline"
    elseif ContainsAny(normalized, P.RootPhrases[599]) then
        suffix = "fontMonochrome"
    elseif ContainsAny(normalized, P.RootPhrases[600]) then
        suffix = "fontTextAlpha"
    elseif ContainsAny(normalized, P.RootPhrases[601]) then
        suffix = "fontBaselineOffset"
    elseif ContainsAny(normalized, P.RootPhrases[602]) then
        suffix = "textBackdrop"
    elseif ContainsAny(normalized, P.RootPhrases[603]) then
        value = FirstNumber(normalized)
        if value ~= nil then
            suffix = "fontShadowOpacity"
            if value > 1 then value = value / 100 end
        else
            suffix = "fontShadowStrength"
        end
    elseif ContainsAny(normalized, P.RootPhrases[604]) then
        suffix = "shortenNames"
    elseif ContainsAny(normalized, P.RootPhrases[605]) then
        suffix = "shortenNameClipSide"
    elseif ContainsAny(normalized, P.RootPhrases[606]) then
        suffix = "shortenNameMaxChars"
        value = FirstNumber(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, P.RootPhrases[607]) then
        suffix = "shortenNameNoEllipsis"
        if ContainsAny(normalized, P.RootPhrases[608]) then
            value = false
        elseif ContainsAny(normalized, P.RootPhrases[609]) then
            value = true
        end
    else
        return nil
    end

    local changes = {}
    local seen = {}
    for i = 1, #scopes do
        local scope = tostring(scopes[i])
        if not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("fontScope." .. scope .. "." .. suffix)
            if setting then
                local settingValue = value
                if settingValue == nil then
                    settingValue = P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, normalized, normalized) or nil
                end
                if settingValue ~= nil then changes[#changes + 1] = { setting = setting, value = settingValue } end
            end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = suffix == "override" and "Font Override" or "Font Rendering",
        bulkSafe = #changes > 1,
        summary = "Changes scoped MSUF font options.",
    }
end
A._ParseFontScopePriorityShortcut = ParseFontScopePriorityShortcut

local function ParseGlobalUIShellPriorityShortcut(normalized, raw)
    local specs = {
        { key = "general.menuFontKey", label = "MSUF Menu Font", terms = { "msuf menu font", "menu font", "options menu font", "font of the msuf menu", "font for the msuf menu", "menu typeface" }, mediaType = "font" },
        { key = "general.slashMenuSnapEnabled", label = "Menu Edge Snap", terms = { "menu edge snap", "edge snap", "snap menu", "menu snapping" } },
        { key = "general.hideAdvancedMenu", label = "Advanced Menu", terms = { "advanced menu", "hide advanced menu", "show advanced menu" } },
        { key = "general.reduceMotion", label = "Reduce Motion", terms = { "reduce motion", "reduced motion", "less motion" } },
        { key = "general.previewDragHintAnimationEnabled", label = "Preview Drag Hint Animation", terms = { "preview drag hint", "preview drag animation", "drag hint animation", "preview move tutorial" } },
        { key = "general.showNavigationIcons", label = "Navigation Icons", terms = { "navigation icons", "nav icons" } },
        { key = "general.showGameMenuButton", label = "MSUF Game Menu Button", terms = { "msuf button in game menu", "game menu button", "msuf game menu button", "escape menu button" } },
        { key = "general.showWelcomeMessage", label = "Welcome Message", terms = { "welcome message", "startup message" } },
        { key = "general.grid2EditModeIntegration", label = "Grid2 Edit Mode Integration", terms = { "grid2 edit mode", "grid2 mover", "move grid2", "grid2 integration" } },
        { key = "general.detailsEditModeIntegration", label = "Details! Edit Mode Integration", terms = { "details edit mode", "details mover", "move details", "details integration" } },
        { key = "general.dominosEditModeIntegration", label = "Dominos Edit Mode Integration", terms = { "dominos edit mode", "dominos mover", "move dominos", "dominos integration" } },
        { key = "general.dandersEditModeIntegration", label = "DandersFrames Edit Mode Integration", terms = { "dandersframes edit mode", "danders edit mode", "danders mover", "move dandersframes", "danders integration" } },
        { key = "general.blizzardEditModeIntegration", label = "Blizzard Edit Mode Integration", terms = { "blizzard edit mode", "move minimap", "move chat", "move micro menu", "blizzard integration" } },
        { key = "general.versionCheckEnabled", label = "Version Check", terms = { "version check", "version checker" } },
        { key = "general.showMinimapIcon", label = "Minimap Icon", terms = { "minimap icon", "minimap button" } },
        { key = "general.playTargetSelectLostSounds", label = "Target Sounds", terms = { "target sounds", "target select sound", "target lost sound" } },
        { key = "general.menuLocale", label = "Menu Language", terms = { "menu language", "menu locale" } },
        { key = "general.unitTooltipProvider", label = "Tooltip Source", terms = { "tooltip source", "tooltip provider" } },
        { key = "general.unitTooltipAnchor", label = "Tooltip Anchor", terms = { "tooltip anchor" } },
        { key = "general.unitTooltipMode", label = "Show Unitframe Tooltips", terms = { "show unitframe tooltips", "unitframe tooltips", "unit frame tooltips" } },
        { key = "general.unitTooltipModifier", label = "Tooltip Modifier", terms = { "tooltip modifier" } },
        { key = "general.styleEnabled", label = "MSUF Style", terms = { "msuf style" } },
        { key = "general.dropdownStyleMode", label = "Dropdown Style", terms = { "dropdown style", "dropdown mode" } },
    }
    for i = 1, #specs do
        local spec = specs[i]
        if ContainsAny(normalized, spec.terms) then
            local setting = A.Registry and A.Registry:GetSetting(spec.key)
            if setting and spec.mediaType then
                local resolver = A.MediaResolver
                local media = resolver and resolver.ResolveSetting and resolver.ResolveSetting(setting, normalized, raw)
                if media and media.status == "exact" and media.value ~= nil then
                    return {
                        kind = "changes",
                        changes = { { setting = setting, value = media.value, valueLabel = media.label or media.value, mediaType = media.mediaType } },
                        label = spec.label,
                        summary = "Changes the font used by the MSUF options menu.",
                    }
                elseif media and media.status == "choices" and type(media.choices) == "table" then
                    local choices = {}
                    for choiceIndex = 1, #media.choices do
                        local item = media.choices[choiceIndex]
                        choices[#choices + 1] = {
                            setting = setting,
                            value = item.value,
                            valueLabel = item.label or item.value,
                            label = tostring(setting.label or spec.label) .. ": " .. tostring(item.label or item.value),
                            mediaType = media.mediaType,
                        }
                    end
                    if #choices > 0 then
                        return { kind = "ambiguous", choices = choices, label = "Which menu font?", summary = "Choose the exact font for the MSUF menu." }
                    end
                elseif media and media.status == "none" then
                    local message = resolver.NoMatchMessage and resolver.NoMatchMessage(media.mediaType, media.query)
                    return { kind = "unknown", status = "failed", text = message or "That font is not in the current font list." }
                end
                return nil
            end
            local value = setting and P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, normalized, normalized) or nil
            if value ~= nil then
                return {
                    kind = "changes",
                    changes = { { setting = setting, value = value } },
                    label = spec.label,
                    summary = "Changes a global MSUF menu/UI option.",
                }
            end
        end
    end
    return nil
end
A._ParseGlobalUIShellPriorityShortcut = ParseGlobalUIShellPriorityShortcut

local function ParseClassPowerPriorityShortcut(normalized, raw)
    return (A._ParseClassPowerDisplayStyleShortcut and A._ParseClassPowerDisplayStyleShortcut(normalized))
        or (A._ParseClassPowerPreviewResourceShortcut and A._ParseClassPowerPreviewResourceShortcut(normalized))
        or (ParseClassPowerRootToggle and ParseClassPowerRootToggle(normalized))
        or (A._ParseClassPowerPlacementShortcut and A._ParseClassPowerPlacementShortcut(normalized))
        or (A._ParseClassPowerWidthModeShortcut and A._ParseClassPowerWidthModeShortcut(normalized))
        or (A._ParseClassPowerVisibilityShortcut and A._ParseClassPowerVisibilityShortcut(normalized))
        or (A._ParseClassPowerFillDirectionShortcut and A._ParseClassPowerFillDirectionShortcut(normalized))
        or (A._ParseClassPowerEmpoweredComboShortcut and A._ParseClassPowerEmpoweredComboShortcut(normalized))
        or (A._ParseClassPowerRuneTimeShortcut and A._ParseClassPowerRuneTimeShortcut(normalized))
        or (A._ParseClassPowerDisplayBooleanShortcut and A._ParseClassPowerDisplayBooleanShortcut(normalized))
        or (A._ParseClassPowerColorModeShortcut and A._ParseClassPowerColorModeShortcut(normalized))
        or (A._ParseClassPowerDetachedPowerBarDetailShortcut and A._ParseClassPowerDetachedPowerBarDetailShortcut(normalized, raw))
        or (A._ParseClassPowerAltManaShortcut and A._ParseClassPowerAltManaShortcut(normalized, raw))
        or (A._ParseClassPowerPlayerHPDetailShortcut and A._ParseClassPowerPlayerHPDetailShortcut(normalized, raw))
        or (A._ParseClassPowerAnchorShortcut and A._ParseClassPowerAnchorShortcut(normalized))
        or (A._ParseClassPowerShapeShortcut and A._ParseClassPowerShapeShortcut(normalized))
        or (A._ParseClassPowerTextSizeShortcut and A._ParseClassPowerTextSizeShortcut(normalized))
        or (A._ParseClassPowerSizeShortcut and A._ParseClassPowerSizeShortcut(normalized))
        or (A._ParseClassPowerFrameLevelShortcut and A._ParseClassPowerFrameLevelShortcut(normalized))
        or (A._ParseClassPowerSeparatorShortcut and A._ParseClassPowerSeparatorShortcut(normalized))
        or (A._ParseClassPowerGapShortcut and A._ParseClassPowerGapShortcut(normalized))
        or (A._ParseClassPowerBackgroundShortcut and A._ParseClassPowerBackgroundShortcut(normalized))
        or (A._ParseClassPowerOutlineOpacityShortcut and A._ParseClassPowerOutlineOpacityShortcut(normalized))
        or (A._ParseClassPowerTextureShortcut and A._ParseClassPowerTextureShortcut(normalized, raw))
        or (A._ParseClassPowerMoveShortcut and A._ParseClassPowerMoveShortcut(normalized))
end
A._ParseClassPowerPriorityShortcut = ParseClassPowerPriorityShortcut

local function ParseGameplayPriorityShortcut(normalized, raw)
    return (ParseGameplayRootToggle and ParseGameplayRootToggle(normalized))
        or (A._ParseGameplayTextValueShortcut and A._ParseGameplayTextValueShortcut(normalized, raw))
        or (A._ParseGameplayBooleanShortcut and A._ParseGameplayBooleanShortcut(normalized))
        or (A._ParseGameplayAnchorShortcut and A._ParseGameplayAnchorShortcut(normalized))
        or (A._ParseGameplaySpellIDShortcut and A._ParseGameplaySpellIDShortcut(normalized))
        or (A._ParseGameplayNumberShortcut and A._ParseGameplayNumberShortcut(normalized))
        or (A._ParseGameplayPositionPreset and A._ParseGameplayPositionPreset(normalized))
        or (A._ParseGameplayMoveShortcut and A._ParseGameplayMoveShortcut(normalized))
end
A._ParseGameplayPriorityShortcut = ParseGameplayPriorityShortcut

A._ParseCastbarWidthModeShortcut = ParseCastbarWidthModeShortcut
A._ParseGroupSpellIndicatorsFastShortcut = ParseGroupSpellIndicatorsEnabledFastShortcut
A._ParseGroupBlizzardFallbackFastShortcut = ParseGroupBlizzardFallbackFastShortcut
A._ParseGroupHideOfflineDelayFastShortcut = ParseGroupHideOfflineDelayFastShortcut
A._ParseGroupReverseFillFastShortcut = ParseGroupReverseFillFastShortcut
A._ParseUnitReverseFillFastShortcut = ParseUnitReverseFillFastShortcut
A._ParseUnitSimpleBooleanFastShortcut = ParseUnitSimpleBooleanFastShortcut
A._ParseUnitStatusDetailFastShortcut = ParseUnitStatusDetailFastShortcut
A._ParseGroupSimpleBooleanFastShortcut = ParseGroupSimpleBooleanFastShortcut
A._ParseGroupCornerCustomFastShortcut = ParseGroupCornerCustomFastShortcut
A._ParseGroupTextureFastShortcut = ParseGroupTextureFastShortcut
A._ParseGroupNameTextFastShortcut = ParseGroupNameTextFastShortcut
A._ParseGroupRolePowerFastShortcut = ParseGroupRolePowerFastShortcut
A._ParseGroupPowerBarEnabledFastShortcut = ParseGroupPowerBarEnabledFastShortcut
A._ParseGroupOrderingFastShortcut = ParseGroupOrderingFastShortcut
A._ParseGlobalUiScaleFastShortcut = ParseGlobalUiScaleFastShortcut
A._ParseDashboardScaleFastShortcut = ParseDashboardScaleFastShortcut
A._ParseGlobalFontColorFastShortcut = ParseGlobalFontColorFastShortcut
A._ParseClassColorFastShortcut = ParseClassColorFastShortcut
A._ParseGlobalBarBackgroundFastShortcut = ParseGlobalBarBackgroundFastShortcut
A._ParseDarkModeCustomColorFastShortcut = ParseDarkModeCustomColorFastShortcut
A._ParseGlobalUnitFrameColorFastShortcut = ParseGlobalUnitFrameColorFastShortcut
A._ParseLastBarGradientGroupFollowup = ParseLastBarGradientGroupFollowup
A._ParseHealthColorGradientFastShortcut = ParseHealthColorGradientFastShortcut
A._ParseNPCReactionColorFastShortcut = ParseNPCReactionColorFastShortcut
A._ParsePetFrameColorFastShortcut = ParsePetFrameColorFastShortcut
A._ParsePowerColorTokenFastShortcut = ParsePowerColorTokenFastShortcut
A._ParseCastbarColorFastShortcut = ParseCastbarColorFastShortcut
A._ParseCastbarOverrideModeFastShortcut = ParseCastbarOverrideModeFastShortcut
A._ParseScopedBarOutlineColorFastShortcut = ParseScopedBarOutlineColorFastShortcut
A._ParseNPCTypeColorFastShortcut = ParseNPCTypeColorFastShortcut
A._ParseClassResourceHPBarFastShortcut = ParseClassResourceHPBarFastShortcut
A._ParseGlobalColorModeBooleanFastShortcut = ParseGlobalColorModeBooleanFastShortcut
A._ParseRaidMarkerNumberFastShortcut = ParseRaidMarkerNumberFastShortcut
A._ParseExactTextSlotOffsetFastShortcut = ParseExactTextSlotOffsetFastShortcut
A._ParseGroupScalingFastShortcut = ParseGroupScalingFastShortcut
A._ParseGroupFrameAnchorFastShortcut = ParseGroupFrameAnchorFastShortcut
A._ParseGroupLayoutNumberFastShortcut = ParseGroupLayoutNumberFastShortcut
A._ParseGroupTextFormatFastShortcut = ParseGroupTextFormatFastShortcut
A._ParseGroupDispelOverlayFastShortcut = ParseGroupDispelOverlayFastShortcut
A._ParseGroupRangeFadeFastShortcut = ParseGroupRangeFadeFastShortcut
A._ParseGroupNumberFastShortcut = ParseGroupNumberFastShortcut
A._ParseGroupHighlightFastShortcut = ParseGroupHighlightFastShortcut
A._ParseFullGroupBorderFastShortcut = ParseFullGroupBorderFastShortcut
A._ParseGroupStatusIconStyleFastShortcut = ParseGroupStatusIconStyleFastShortcut
A._ParseGroupBarColorModeFastShortcut = ParseGroupBarColorModeFastShortcut
A._ParseGroupFrameColorFastShortcut = ParseGroupFrameColorFastShortcut
A._ParseGroupDeadBackgroundFastShortcut = ParseGroupDeadBackgroundFastShortcut
A._ParseGroupAvailabilityFastShortcut = ParseGroupAvailabilityFastShortcut
A._ParseGroupAuraCooldownDarkenShortcut = ParseGroupAuraCooldownDarkenShortcut
A._ParseGroupAuraLaneBooleanShortcut = ParseGroupAuraLaneBooleanShortcut
A._ParseGroupAuraLaneTextSizeShortcut = ParseGroupAuraLaneTextSizeShortcut
A._ParseGroupAuraLaneTextOffsetShortcut = ParseGroupAuraLaneTextOffsetShortcut
A._ParseGroupAuraLaneOffsetShortcut = ParseGroupAuraLaneOffsetShortcut
A._ParseDispelOverlayOpacityShortcut = ParseDispelOverlayOpacityShortcut
A._ParseExplicitUnitBarOpacityShortcut = ParseExplicitUnitBarOpacityShortcut
A._ParseEditModeHUDControl = ParseEditModeHUDControl
A._ParseGlobalStatusTextStateShortcut = ParseGlobalStatusTextStateShortcut
A._ParseClassPowerTextOffsetShortcut = ParseClassPowerTextOffsetShortcut
A._ParseUnitRootVisibilityShortcut = ParseUnitRootVisibilityShortcut

local function ParseHumanSafetyGuidanceShortcut(normalized)
    if FirstNumber(normalized) ~= nil then return nil end
    if ContainsAny(normalized, P.RootPhrases[610]) then return nil end

    local broadIntent = ContainsAny(normalized, P.RootPhrases[611])
    if not broadIntent then return nil end
    if not ContainsAny(normalized, P.RootPhrases[612]) then return nil end

    local area = "that area"
    local examples = "open player; open bars; set target health bar height to 24; set target buff icon count to 8"
    if ContainsAny(normalized, P.RootPhrases[613]) then
        area = "raid frames"
        examples = "open raid frames; set raid debuff filter to RAID_IN_COMBAT; set raid name max chars to 12; set raid frame scale to 90"
    elseif ContainsAny(normalized, P.RootPhrases[614]) then
        area = "party frames"
        examples = "open party frames; set party buff count to 4; set party frame spacing to 8; turn on party range fade"
    elseif ContainsAny(normalized, P.RootPhrases[615]) then
        area = "auras"
        examples = "open aura filters; set target buff icon count to 8; set target debuff filter to RAID; set party buff icon size to 24"
    elseif ContainsAny(normalized, P.RootPhrases[616]) then
        area = "bars"
        examples = "open bars; turn on gradient from right for all unitframes; set gradient strength to 0.45; set bar texture to Minimalist"
    end

    return {
        kind = "answer",
        status = "ambiguous",
        result = "ambiguous",
        text = "I did not change " .. area .. " from that broad request. Tell me which exact setting to adjust, or start by opening the relevant page.\nSafe examples: " .. examples .. ".",
        summary = "Gives safe MSUF guidance for a broad visual request instead of guessing settings.",
    }
end
A._ParseHumanSafetyGuidanceShortcut = ParseHumanSafetyGuidanceShortcut

function P.ShouldTryEarlyCompound(text)
    text = tostring(text or "")
    local numberCount = 0
    for _ in text:gmatch("[-+]?%d+%.?%d*") do
        numberCount = numberCount + 1
        if numberCount >= 2 then return true end
    end
    if text:find(" but ", 1, true) then return true end

    local colorCount = 0
    for _ in text:gmatch("%f[%a]colou?r%f[%A]") do colorCount = colorCount + 1 end
    for _ in text:gmatch("%f[%a]farbe%f[%A]") do colorCount = colorCount + 1 end
    if colorCount >= 2 then return true end

    if ContainsAny(text, { "hp text", "health text", "power text", "mana text" }) then
        local slots = 0
        if HasPhrase(text, "left") then slots = slots + 1 end
        if HasPhrase(text, "right") then slots = slots + 1 end
        if HasPhrase(text, "center") or HasPhrase(text, "centre") or HasPhrase(text, "middle") then slots = slots + 1 end
        if slots >= 2 then return true end
        local textValueWords = {
            current = true, actual = true, max = true, maximum = true,
            percent = true, percentage = true, deficit = true, missing = true, none = true,
        }
        local valueCount = 0
        for word in text:gmatch("%S+") do
            if textValueWords[word] then valueCount = valueCount + 1 end
        end
        if valueCount >= 2 then
            local scopeCount = #(DetectUnits(text) or {}) + #(DetectGroups(text) or {})
            if scopeCount >= 2 then return true end
        end
    end

    if ContainsAny(text, { "portrait", "portraet" }) then
        local details = 0
        local detailGroups = {
            { "shape", "form" }, { "size", "groesse" }, { "border", "outline", "rand" },
            { "background", "hintergrund" }, { "zoom" }, { "render", "2d", "class portrait" },
        }
        for i = 1, #detailGroups do
            if ContainsAny(text, detailGroups[i]) then details = details + 1 end
        end
        if details >= 2 then return true end
    end

    local itemCount = 0
    local itemGroups = {
        { "name", "names", "namen" }, { "portrait", "portraits", "portraet", "portraets" }, { "power bar", "power bars" },
        { "health bar", "health bars" }, { "castbar", "cast bar" }, { "buff", "buffs" },
        { "debuff", "debuffs" }, { "border", "outline" }, { "background" },
    }
    for i = 1, #itemGroups do
        if ContainsAny(text, itemGroups[i]) then itemCount = itemCount + 1 end
    end
    if itemCount >= 1 then
        local scopeCount = #(DetectUnits(text) or {}) + #(DetectGroups(text) or {})
        local hasTrailingBoolean = text:match("%s+on$") or text:match("%s+off$")
            or text:match("%s+true$") or text:match("%s+false$")
            or text:match("%s+enabled$") or text:match("%s+disabled$")
            or text:match("%s+an$") or text:match("%s+aus$")
            or text:match("%s+aktiviert$") or text:match("%s+deaktiviert$")
        if scopeCount >= 2 and hasTrailingBoolean then return true end
        if scopeCount >= 2 and (
            text:match("^turn%s+off%s+") or text:match("^turn%s+on%s+")
            or text:match("^disable%s+") or text:match("^enable%s+")
            or text:match("^hide%s+") or text:match("^show%s+")
            or text:match("^deaktivieren%s+") or text:match("^deaktiviere%s+")
            or text:match("^aktivieren%s+") or text:match("^aktiviere%s+")
            or text:match("^verstecken%s+") or text:match("^verstecke%s+")
            or text:match("^anzeigen%s+") or text:match("^zeige%s+")
        ) then
            return true
        end
    end
    if itemCount >= 2 and (
        text:match("^turn%s+off%s+") or text:match("^turn%s+on%s+")
        or text:match("^disable%s+") or text:match("^enable%s+")
        or text:match("^hide%s+") or text:match("^show%s+")
        or text:match("^deaktivieren%s+") or text:match("^aktivieren%s+")
        or text:match("^verstecken%s+") or text:match("^anzeigen%s+")
    ) then
        return true
    end

    -- ParseCompound accepts adjacent Boolean value pairs without an explicit
    -- join (for example, "name off portrait on"). Let those proven pairs run
    -- before a single-detail shortcut can return only the first requested
    -- change. Requiring two values and two distinct details keeps ordinary
    -- one-setting prompts off the more expensive compound path.
    local booleanCount = 0
    local booleanWords = {
        on = true, off = true, ["true"] = true, ["false"] = true,
        enable = true, enabled = true, disable = true, disabled = true,
        an = true, aus = true, aktivieren = true, deaktivieren = true,
    }
    for word in text:gmatch("%S+") do
        if booleanWords[word] then
            booleanCount = booleanCount + 1
            if booleanCount >= 2 then
                if itemCount >= 2 then return true end
                local scopeCount = #(DetectUnits(text) or {}) + #(DetectGroups(text) or {})
                if scopeCount >= 2 then return true end
            end
        end
    end

    if text:find(" and ", 1, true) or text:find(" und ", 1, true) then
        local hasBoolean = ContainsAny(text, {
            "on", "off", "true", "false", "enable", "enabled", "disable", "disabled",
            "show", "hide", "an", "aus", "aktivieren", "deaktivieren", "anzeigen", "verstecken",
        })
        if hasBoolean and itemCount >= 2 then return true end
        if hasBoolean and itemCount >= 1 then
            local scopeCount = #(DetectUnits(text) or {}) + #(DetectGroups(text) or {})
            if scopeCount >= 2 then return true end
        end
    end
    return false
end

function A.ParseSimpleChange(text, ctxOverride)
    local raw = Trim(text)
    local normalized = Normalize(raw)
    local ctx = type(ctxOverride) == "table" and ctxOverride or (A.GetContext and A.GetContext() or {})
    if normalized == "" then return nil end
    -- ParseSimpleChange is used by the direct mutation fast path. Read-only
    -- intents must fall through to the Router instead of being returned here,
    -- so page/location/problem specialists can give their richer answer.
    if P.NonMutatingIntent and P.NonMutatingIntent(normalized) then return nil end
    -- Visual words such as "dots" and "ellipsis" belong to name shortening,
    -- not to a coincidental frame/name alias. Resolve this narrow semantic
    -- owner before exact aliases and text visibility in compound fragments.
    local nameDots = P.ParseNameShorteningDotsShortcut
        and P.ParseNameShorteningDotsShortcut(normalized, ctx, raw)
    -- An exact full registry label is stronger evidence than a broad topical
    -- shortcut.  Resolve it first so words such as "anchor", "name", "scale",
    -- or "power text" cannot redirect a generated or human exact-label command
    -- to the parent frame control.
    local exactFullAlias = (P.ParseTargetGateLoadConditionShortcut and P.ParseTargetGateLoadConditionShortcut(normalized))
        or (P.ParseRegistryExactAliasShortcut
            and P.ParseRegistryExactAliasShortcut(normalized, raw, { minTokens = 3, fullPhrase = true }))
    if normalized:find(" text anchor ", 1, true) and not normalized:find("custom value", 1, true) then exactFullAlias = nil end
    local parsed = nameDots or exactFullAlias
        or (A._ParseHumanSafetyGuidanceShortcut and A._ParseHumanSafetyGuidanceShortcut(normalized))
        or (A._ParseUnitRaidMarkerVisibilityShortcut and A._ParseUnitRaidMarkerVisibilityShortcut(normalized))
        or (A._ParseDispelOverlayOpacityShortcut and A._ParseDispelOverlayOpacityShortcut(normalized))
        or (A._ParseScopedDispelBorderTriggerFastShortcut and A._ParseScopedDispelBorderTriggerFastShortcut(normalized))
        or (A._ParsePowerColorTokenFastShortcut and A._ParsePowerColorTokenFastShortcut(normalized, raw))
        or (A._ParseExactColorSettingFastShortcut and A._ParseExactColorSettingFastShortcut(normalized, raw))
        or (P.ParseAmbiguousFontTextColorShortcut and P.ParseAmbiguousFontTextColorShortcut(normalized))
        or (P.ParseAmbiguousColorShortcut and P.ParseAmbiguousColorShortcut(normalized, raw))
        or (P.ParseScopedFontTextColorShortcut and P.ParseScopedFontTextColorShortcut(normalized, raw))
        or (A._ParseGroupDispelOverlayFastShortcut and A._ParseGroupDispelOverlayFastShortcut(normalized))
        or (A._ParseGlobalBarModePriorityShortcut and A._ParseGlobalBarModePriorityShortcut(normalized))
        or (A._ParseGlobalBarTexturePriorityShortcut and A._ParseGlobalBarTexturePriorityShortcut(normalized, raw))
        or (A._ParseGlobalGradientStrengthPriorityShortcut and A._ParseGlobalGradientStrengthPriorityShortcut(normalized))
        or (A._ParseGlobalRoundedBarsPriorityShortcut and A._ParseGlobalRoundedBarsPriorityShortcut(normalized))
        or (A._ParseGlobalUnitDispelOverlayPriorityShortcut and A._ParseGlobalUnitDispelOverlayPriorityShortcut(normalized))
        or (A._ParseScopedUnitDispelOverlayPriorityShortcut and A._ParseScopedUnitDispelOverlayPriorityShortcut(normalized))
        or (A._ParseGlobalPowerBarDetailPriorityShortcut and A._ParseGlobalPowerBarDetailPriorityShortcut(normalized))
        or (A._ParseScopedBarOverridePriorityShortcut and A._ParseScopedBarOverridePriorityShortcut(normalized))
        or (A._ParseScopedGradientStrengthPriorityShortcut and A._ParseScopedGradientStrengthPriorityShortcut(normalized))
        or (A._ParseGlobalFontPriorityShortcut and A._ParseGlobalFontPriorityShortcut(normalized, raw))
        or (A._ParseFontScopePriorityShortcut and A._ParseFontScopePriorityShortcut(normalized))
        or (A._ParseGlobalUIShellPriorityShortcut and A._ParseGlobalUIShellPriorityShortcut(normalized, raw))
        or (A._ParseBarGradientPriorityShortcut and A._ParseBarGradientPriorityShortcut(normalized))
        or (A._ParseClassPowerDetachedPlayerPowerShortcut and A._ParseClassPowerDetachedPlayerPowerShortcut(normalized, raw))
        or (A._ParseClassPowerPriorityShortcut and A._ParseClassPowerPriorityShortcut(normalized, raw))
        or (A._ParseGameplayPriorityShortcut and A._ParseGameplayPriorityShortcut(normalized, raw))
        or EarlyAuraShortcut(normalized, raw)
        or (P.ParseTextVisibilityShortcut and P.ParseTextVisibilityShortcut(normalized))
        or (A._ParseNameTextAnchorShortcut and A._ParseNameTextAnchorShortcut(normalized))
        or (A._ParseNameTextOffsetShortcut and A._ParseNameTextOffsetShortcut(normalized))
        or (A._ParseNameTextVerticalPlacementShortcut and A._ParseNameTextVerticalPlacementShortcut(normalized))
        or (A._ParseTextSlotDropdownValueShortcut and A._ParseTextSlotDropdownValueShortcut(normalized))
        or (A._ParseHPTextOptionShortcut and A._ParseHPTextOptionShortcut(normalized))
        or (A._ParsePowerTextOptionShortcut and A._ParsePowerTextOptionShortcut(normalized))
        or (A._ParseTextSlotValueMoveShortcut and A._ParseTextSlotValueMoveShortcut(normalized))
        or (A._ParseTextSlotOffsetShortcut and A._ParseTextSlotOffsetShortcut(normalized))
        or (A._ParseTextAreaOffsetShortcut and A._ParseTextAreaOffsetShortcut(normalized))
        or (A._ParseTextFontSizeShortcut and A._ParseTextFontSizeShortcut(normalized))
        or ParseCustomAnchorSet(normalized, raw)
        or ParsePortraitDetailShortcut(normalized)
        or (LooksLikeAbsorbBarCommand(normalized) and ParseAbsorbBarShortcut and ParseAbsorbBarShortcut(normalized, raw))
        or (LooksLikeBarBorderEnumCommand(normalized) and ParseBarBorderEnumShortcut and ParseBarBorderEnumShortcut(normalized))
        or (ParseAmbiguousGroupOutlineBorderShortcut and ParseAmbiguousGroupOutlineBorderShortcut(normalized))
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

function P.ReadOnlyQuestionCandidate(parsed)
    if type(parsed) ~= "table" then return false end
    if parsed.kind == "answer" then return true end
    if parsed.kind ~= "action" or type(parsed.action) ~= "table" then return false end
    local action = parsed.action
    return action.readOnly == true
        or action.mutability == "readOnly"
        or action.mutability == "navigation"
end

function P.ReadOnlyQuestionContext(ctx)
    local out = {}
    for key, value in pairs(type(ctx) == "table" and ctx or {}) do out[key] = value end
    out._nonMutatingSafeParse = true
    return out
end

function A.Parse(text, ctxOverride)
    local autoCoverage = A.AutoCoverage
    if autoCoverage and type(autoCoverage.EnsureFilled) == "function" then
        autoCoverage.EnsureFilled()
    end
    local raw = P.Trim(text)
    local normalized = P.Normalize(raw)
    local ctx = type(ctxOverride) == "table" and ctxOverride or (A.GetContext and A.GetContext() or {})
    if normalized == "" then return { kind = "empty" } end
    local semanticBarOutlineColor = A._ParseScopedBarOutlineColorFastShortcut
        and A._ParseScopedBarOutlineColorFastShortcut(normalized, raw)
    if semanticBarOutlineColor then
        semanticBarOutlineColor.raw = raw
        semanticBarOutlineColor.normalized = normalized
        return semanticBarOutlineColor
    end
    local textPositionCopy = A._ParseUnitTextPositionCopyShortcut and A._ParseUnitTextPositionCopyShortcut(normalized)
    if textPositionCopy then
        textPositionCopy.raw = raw
        textPositionCopy.normalized = normalized
        return textPositionCopy
    end
    -- "Dots on party frame" describes a visual symptom and must not be
    -- reduced to the unrelated exact alias "party frame" (X/Y position) or
    -- "party name" (name visibility). This specialist also returns safe
    -- choices when the current shortening state does not make the meaning
    -- certain.
    local nameDotsPriority = P.ParseNameShorteningDotsShortcut
        and P.ParseNameShorteningDotsShortcut(normalized, ctx, raw)
    if nameDotsPriority then
        nameDotsPriority.raw = raw
        nameDotsPriority.normalized = normalized
        return nameDotsPriority
    end
    local hpTextColorPriority = P.ParseHPTextColorModePriority and P.ParseHPTextColorModePriority(normalized)
    if hpTextColorPriority then
        hpTextColorPriority.raw = raw
        hpTextColorPriority.normalized = normalized
        return hpTextColorPriority
    end
    -- Aura-filter language has several deliberately separate controls with
    -- overlapping labels. Resolve its semantic owner before an exact alias can
    -- toggle lane visibility or the live-filter master by accident.
    local auraFilteringPriority = P.ParseAuraFilteringConversationShortcut
        and P.ParseAuraFilteringConversationShortcut(normalized, ctx, raw)
    if auraFilteringPriority then
        auraFilteringPriority.raw = raw
        auraFilteringPriority.normalized = normalized
        return auraFilteringPriority
    end
    -- Aura layout terms such as growth and spacing own both lane-specific
    -- controls. Resolve them before generated exact aliases (for example the
    -- legacy Party Aura Spacing field) can collapse a reviewed Buff+Debuff
    -- request into one unrelated/generated setting.
    local auraGeometryPriority = P.AuraGeometryShortcut and P.AuraGeometryShortcut(normalized)
    if auraGeometryPriority then
        auraGeometryPriority.raw = raw
        auraGeometryPriority.normalized = normalized
        return auraGeometryPriority
    end
    -- Slot color-mode settings intentionally use resource names such as
    -- "maelstrom" too. Keep reset-color phrases out of the broad exact-setting
    -- alias pass so the existing explanation guard and action-first color
    -- parser can decide between "explain Reset ... Color" and execution.
    local colorResetIntent = P.ParseColorAction
        and P.ContainsAny(normalized, P.RootPhrases[779])
        and P.ContainsAny(normalized, P.RootPhrases[780])
    local exactFullAlias = (P.ParseTargetGateLoadConditionShortcut and P.ParseTargetGateLoadConditionShortcut(normalized))
        or (not colorResetIntent and P.ParseRegistryExactAliasShortcut
            and P.ParseRegistryExactAliasShortcut(normalized, raw, { minTokens = 3, fullPhrase = true }))
    if normalized:find(" text anchor ", 1, true) and not normalized:find("custom value", 1, true) then exactFullAlias = nil end
    if exactFullAlias then
        exactFullAlias.raw = raw
        exactFullAlias.normalized = normalized
        return exactFullAlias
    end
    if P.ParseRegistryActionAliasShortcut and normalized:find("blacklist", 1, true)
        and (normalized:find("what is", 1, true) or normalized:find("show", 1, true)
            or normalized:find("list", 1, true) or normalized:find("current", 1, true))
    then
        local summaryAction = P.ParseRegistryActionAliasShortcut(normalized, raw)
        local key = summaryAction and summaryAction.action and tostring(summaryAction.action.key or "") or ""
        if key:find("_summary$") then
            summaryAction.raw = raw
            summaryAction.normalized = normalized
            return summaryAction
        end
    end
    if normalized:find("player", 1, true) and normalized:find("range fade", 1, true) then
        return {
            kind = "unknown",
            status = "info",
            text = "Player range fade is not a runtime-supported MSUF option. Choose Target, Focus, Pet, Target of Target, Focus Target, or Boss instead.",
            summary = "Explains that Player range fade is unsupported instead of changing an unrelated global option.",
            raw = raw,
            normalized = normalized,
        }
    end
    -- An exact registry-action explanation is always a lookup, even when the
    -- public action label contains diagnostic words such as "Hidden" or
    -- "Broken". Resolve this before NonMutatingIntent can reinterpret those
    -- label tokens as a live problem report and return an executable
    -- diagnostic action.
    local actionExplainParsed = P.ParseRegistryActionExplainShortcut
        and P.ParseRegistryActionExplainShortcut(normalized, raw)
    if actionExplainParsed then
        actionExplainParsed.raw = raw
        actionExplainParsed.normalized = normalized
        return actionExplainParsed
    end
    local nonMutatingIntent = not ctx._nonMutatingSafeParse
        and P.NonMutatingIntent and P.NonMutatingIntent(normalized)
    -- Tour requests are executable onboarding commands even when phrased as a
    -- polite question ("can you show me around MSUF"). Only override the
    -- question guard here; imperative setup commands continue through the
    -- normal action priorities so "quick setup class resources" keeps its
    -- more specific action owner.
    if nonMutatingIntent then
        local guidedSetupParsed = (P.ParseGuidedSetupFollowup and P.ParseGuidedSetupFollowup(normalized, ctx))
            or (P.ParseGuidedSetup and P.ParseGuidedSetup(normalized))
        if guidedSetupParsed then
            guidedSetupParsed.raw = raw
            guidedSetupParsed.normalized = normalized
            return guidedSetupParsed
        end
    end
    if nonMutatingIntent then
        -- Procedural/capability questions must remain read-only, but should
        -- still get the most specific help available instead of a generic
        -- safety banner. Scope help is a read-only registry action; Knowledge
        -- answers are explanatory data only. Neither path applies a setting.
        if nonMutatingIntent == "problem" and P.ParseDiagnostic then
            local diagnostic = P.ParseDiagnostic(normalized)
            if diagnostic then
                diagnostic.raw = raw
                diagnostic.normalized = normalized
                return diagnostic
            end
        end
        local scopedHelp = nonMutatingIntent == "capability"
            and P.ParseScopedHelp and P.ParseScopedHelp(normalized)
        if scopedHelp then
            scopedHelp.raw = raw
            scopedHelp.normalized = normalized
            return scopedHelp
        end
        local locationQuestion = normalized:match("^where%s") or normalized:match("^wo%s")
        if locationQuestion and P.ParseOpen then
            local openResult = P.ParseOpen(normalized, raw)
            if openResult then
                openResult.raw = raw
                openResult.normalized = normalized
                return openResult
            end
        end
        -- Preserve specific read-only actions and contextual answers (profile
        -- summary, blacklist summary, diagnostics, history follow-ups, ...)
        -- without allowing the same normal parser pass to return a setting
        -- plan. The marker prevents recursion; mutation candidates are rejected
        -- and fall through to Knowledge or the generic read-only explanation.
        local safeCandidate = A.Parse(raw, P.ReadOnlyQuestionContext(ctx))
        if P.ReadOnlyQuestionCandidate(safeCandidate) then return safeCandidate end
        if A.Knowledge and type(A.Knowledge.Answer) == "function" then
            local ok, knowledgeAnswer = pcall(A.Knowledge.Answer, raw, { currentPage = M and M.activeKey })
            if ok and type(knowledgeAnswer) == "table" then
                knowledgeAnswer.kind = knowledgeAnswer.kind or "answer"
                knowledgeAnswer.status = knowledgeAnswer.status == "applied" and "info" or (knowledgeAnswer.status or "info")
                knowledgeAnswer.raw = raw
                knowledgeAnswer.normalized = normalized
                return knowledgeAnswer
            end
        end
        local nonMutatingIntentParsed = P.NonMutatingIntentAnswer and P.NonMutatingIntentAnswer(normalized)
        if nonMutatingIntentParsed then
            nonMutatingIntentParsed.raw = raw
            nonMutatingIntentParsed.normalized = normalized
            return nonMutatingIntentParsed
        end
    end
    if normalized:find("only", 1, true) and ParseScopedOnlyOverride then
        local scopedOnly = ParseScopedOnlyOverride(normalized, raw)
        if scopedOnly then
            scopedOnly.raw = raw
            scopedOnly.normalized = normalized
            return scopedOnly
        end
    end
    -- Exact aura-list edits are more specific than broad visibility toggles.
    -- The semantic Aura-filter owner above handles no-expiration language;
    -- explicit SpellIDs remain on their registered list-action path.
    if P.ParseRegistryActionAliasShortcut and P.AuraBlacklistSpellValue
        and (normalized:find("blacklist", 1, true) or normalized:find("whitelist", 1, true)
            or normalized:find("buff", 1, true) or normalized:find("debuff", 1, true)
            or normalized:find("aura", 1, true))
        and P.AuraBlacklistSpellValue(raw)
    then
        local auraListAction = P.ParseRegistryActionAliasShortcut(normalized, raw)
        local actionKey = auraListAction and auraListAction.action and tostring(auraListAction.action.key or "") or ""
        if actionKey:find("^aura_blacklist_") or actionKey:find("^aura_group_blacklist_")
            or actionKey:find("^aura_group_category_blacklist_") or actionKey:find("^aura_custom_whitelist_")
        then
            auraListAction.raw = raw
            auraListAction.normalized = normalized
            return auraListAction
        end
    end
    if P.ParseAuraGeometryShortcut
        and (normalized:find("aura", 1, true) or normalized:find("buff", 1, true)
            or normalized:find("debuff", 1, true))
    then
        local auraGeometryPriority = P.ParseAuraGeometryShortcut(normalized)
        if auraGeometryPriority then
            auraGeometryPriority.raw = raw
            auraGeometryPriority.normalized = normalized
            return auraGeometryPriority
        end
    end
    if P.ParseAuraDebuffBorderModeShortcut and normalized:find("dispel border", 1, true) then
        local borderModePriority = P.ParseAuraDebuffBorderModeShortcut(normalized)
        if borderModePriority then
            borderModePriority.raw = raw
            borderModePriority.normalized = normalized
            return borderModePriority
        end
    end
    if (normalized:find("kick ready", 1, true) or normalized:find("interrupt ready", 1, true))
        and (normalized:find("indicator", 1, true) or normalized:find("icon", 1, true))
    then
        local setting, value, relativeDelta
        local amount = P.FirstNumber(normalized) or 1
        if normalized:find("anchor", 1, true) or normalized:find("put ", 1, true) == 1 then
            setting = A.Registry and A.Registry:GetSetting("general.kickReadyAnchor")
            if normalized:find("left", 1, true) then value = "LEFT"
            elseif normalized:find("right", 1, true) then value = "RIGHT"
            elseif normalized:find("top", 1, true) then value = "TOP"
            elseif normalized:find("bottom", 1, true) then value = "BOTTOM" end
        elseif normalized:find("move", 1, true) then
            local vertical = normalized:find("up", 1, true) or normalized:find("down", 1, true)
            setting = A.Registry and A.Registry:GetSetting(vertical and "general.kickReadyOffsetY" or "general.kickReadyOffsetX")
            local negative = normalized:find("left", 1, true) or normalized:find("down", 1, true)
            relativeDelta = negative and -math.abs(amount) or math.abs(amount)
        elseif normalized:find("size", 1, true) and P.FirstNumber(normalized) then
            setting = A.Registry and A.Registry:GetSetting("general.kickReadySize")
            value = P.FirstNumber(normalized)
        elseif normalized:find("bigger", 1, true) or normalized:find("larger", 1, true)
            or normalized:find("smaller", 1, true)
        then
            setting = A.Registry and A.Registry:GetSetting("general.kickReadySize")
            relativeDelta = normalized:find("smaller", 1, true) and -math.abs(amount) or math.abs(amount)
        end
        if setting and (value ~= nil or relativeDelta ~= nil) then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
                label = setting.label or "Interrupt Ready Indicator",
                summary = "Changes only the Interrupt Ready indicator.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if normalized:find("focus kick", 1, true)
        and (normalized:find("tracker", 1, true) or normalized:find("icon", 1, true))
    then
        local changes = {}
        local amount = P.FirstNumber(normalized) or 1
        if normalized:find("left", 1, true) or normalized:find("right", 1, true)
            or normalized:find("up", 1, true) or normalized:find("down", 1, true)
        then
            local vertical = normalized:find("up", 1, true) or normalized:find("down", 1, true)
            local key = vertical and "general.focusKickIconOffsetY" or "general.focusKickIconOffsetX"
            local setting = A.Registry and A.Registry:GetSetting(key)
            if setting then
                local negative = normalized:find("left", 1, true) or normalized:find("down", 1, true)
                changes[1] = { setting = setting, relativeDelta = negative and -math.abs(amount) or math.abs(amount) }
            end
        elseif normalized:find("bigger", 1, true) or normalized:find("larger", 1, true)
            or normalized:find("smaller", 1, true)
        then
            local delta = normalized:find("smaller", 1, true) and -math.abs(amount) or math.abs(amount)
            for _, key in ipairs({ "general.focusKickIconWidth", "general.focusKickIconHeight" }) do
                local setting = A.Registry and A.Registry:GetSetting(key)
                if setting then changes[#changes + 1] = { setting = setting, relativeDelta = delta } end
            end
        end
        if #changes > 0 then
            return {
                kind = "changes",
                changes = changes,
                label = "Focus Kick Tracker",
                bulkSafe = #changes > 1,
                summary = "Changes only the Focus Kick Tracker position or size.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if (normalized:find("scale", 1, true) or normalized:find("scaling", 1, true))
        and (normalized:find("party", 1, true) or normalized:find("raid", 1, true)
            or normalized:find("group frame", 1, true))
    then
        local autoModeIntent = normalized:find("based on raid size", 1, true)
            or normalized:find("by player count", 1, true)
        if autoModeIntent then
            local changes = {}
            for _, scope in ipairs(P.DetectGroups(normalized) or {}) do
                local setting = A.Registry and A.Registry:GetSetting("gf_" .. tostring(scope) .. ".frameScaleMode")
                if setting then changes[#changes + 1] = { setting = setting, value = "auto" } end
            end
            if #changes > 0 then
                return { kind = "changes", changes = changes, label = "Automatic Group Scaling",
                    bulkSafe = #changes > 1, summary = "Scales group frames automatically by group size.",
                    raw = raw, normalized = normalized }
            end
        end
        local hasBreakpoint = normalized:find("player", 1, true) or normalized:find("people", 1, true)
            or normalized:find("raider", 1, true) or normalized:find("when ", 1, true)
            or normalized:find(" at ", 1, true) or normalized:find(" for ", 1, true)
            or normalized:find(" if ", 1, true)
        if not hasBreakpoint then
            local groups = P.DetectGroups(normalized)
            local value = P.FirstNumber(normalized)
            local changes = {}
            for _, scope in ipairs(groups or {}) do
                local setting = A.Registry and A.Registry:GetSetting("gf_" .. tostring(scope) .. ".frameScaleManual")
                if setting and value ~= nil then changes[#changes + 1] = { setting = setting, value = value } end
            end
            if #changes > 0 then
                return {
                    kind = "changes", changes = changes,
                    label = "Group Frame Scale", bulkSafe = #changes > 1,
                    summary = "Changes the requested manual group-frame scale.", raw = raw, normalized = normalized,
                }
            end
        end
        local groupScalePriority = hasBreakpoint and P.ParseGroupScaleBreakpointShortcut
            and P.ParseGroupScaleBreakpointShortcut(normalized)
            or (A._ParseGroupScalingFastShortcut and A._ParseGroupScalingFastShortcut(normalized))
        if groupScalePriority then
            groupScalePriority.raw = raw
            groupScalePriority.normalized = normalized
            return groupScalePriority
        end
    end
    if normalized:find("offline", 1, true)
        and (normalized:find("party", 1, true) or normalized:find("raid", 1, true))
    then
        if normalized:find("in combat", 1, true) and normalized:find("hide", 1, true) then
            local changes = {}
            for _, scope in ipairs(P.DetectGroups(normalized) or {}) do
                local setting = A.Registry and A.Registry:GetSetting("gf_" .. tostring(scope) .. ".hideOfflineInCombat")
                if setting then changes[#changes + 1] = { setting = setting, value = true } end
            end
            if #changes > 0 then
                return { kind = "changes", changes = changes, label = "Hide Offline In Combat",
                    bulkSafe = #changes > 1, summary = "Hides offline group members only while in combat.",
                    raw = raw, normalized = normalized }
            end
        end
        if normalized:find("transparent", 1, true) or normalized:find("opacity", 1, true)
            or normalized:find("alpha", 1, true) or normalized:find("fade offline", 1, true)
        then
            local changes = {}
            local number = P.FirstNumber(normalized)
            if number and number > 1 then number = number / 100 end
            for _, scope in ipairs(P.DetectGroups(normalized) or {}) do
                local setting = A.Registry and A.Registry:GetSetting("gf_" .. tostring(scope) .. ".offlineAlpha")
                if setting then
                    local delta = number == nil and P.RelativeNumberDeltaForText
                        and P.RelativeNumberDeltaForText(setting, normalized, 0.05) or nil
                    if number == nil and normalized:find("more transparent", 1, true) then delta = -0.05 end
                    if number == nil and normalized:find("less transparent", 1, true) then delta = 0.05 end
                    if number ~= nil or delta ~= nil then
                        changes[#changes + 1] = { setting = setting, value = number, relativeDelta = delta }
                    end
                end
            end
            if #changes > 0 then
                return { kind = "changes", changes = changes, label = "Offline Opacity",
                    bulkSafe = #changes > 1, summary = "Changes only offline group-member opacity.",
                    raw = raw, normalized = normalized }
            end
        end
        local offlinePriority = A._ParseGroupRangeFadeFastShortcut and A._ParseGroupRangeFadeFastShortcut(normalized)
        if offlinePriority then
            offlinePriority.raw = raw
            offlinePriority.normalized = normalized
            return offlinePriority
        end
    end
    if normalized:find("name", 1, true) and normalized:find("visible", 1, true)
        and normalized:find("transparent", 1, true)
        and (normalized:find("party", 1, true) or normalized:find("raid", 1, true))
    then
        local changes = {}
        for _, scope in ipairs(P.DetectGroups(normalized) or {}) do
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. tostring(scope) .. ".alphaExcludeTextPortrait")
            if setting then changes[#changes + 1] = { setting = setting, value = true } end
        end
        if #changes > 0 then
            return { kind = "changes", changes = changes, label = "Keep Group Text Visible",
                bulkSafe = #changes > 1, summary = "Keeps text and portraits visible while the frame is faded.",
                raw = raw, normalized = normalized }
        end
    end
    if normalized:find("out of range", 1, true)
        and (normalized:find("party", 1, true) or normalized:find("raid", 1, true))
        and normalized:find("transparent", 1, true)
    then
        local changes = {}
        for _, scope in ipairs(P.DetectGroups(normalized) or {}) do
            local enabled = A.Registry and A.Registry:GetSetting("gf_" .. tostring(scope) .. ".rangeFadeEnabled")
            if enabled then changes[#changes + 1] = { setting = enabled, value = true } end
            local delta
            if normalized:find("more transparent", 1, true) then delta = -0.05 end
            if normalized:find("less transparent", 1, true) then delta = 0.05 end
            if delta then
                local alpha = A.Registry and A.Registry:GetSetting("gf_" .. tostring(scope) .. ".rangeFadeAlpha")
                if alpha then changes[#changes + 1] = { setting = alpha, relativeDelta = delta } end
            end
        end
        if #changes > 0 then
            return { kind = "changes", changes = changes, label = "Group Range Fade",
                bulkSafe = #changes > 1, summary = "Enables group range fade and adjusts its out-of-range opacity.",
                raw = raw, normalized = normalized }
        end
    end
    if normalized:find("solo", 1, true)
        and (normalized:find("party frame", 1, true) or normalized:find("raid frame", 1, true)
            or normalized:find("show while solo", 1, true))
        and not normalized:find("player in group", 1, true)
    then
        local value = not (normalized:find("hide", 1, true) or normalized:find("dont show", 1, true)
            or normalized:find("do not show", 1, true) or normalized:find("not show", 1, true)
            or normalized:find("turn off", 1, true))
        local changes = {}
        for _, scope in ipairs(P.DetectGroups(normalized) or {}) do
            local setting = A.Registry and A.Registry:GetSetting("gf_" .. tostring(scope) .. ".showSolo")
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
        if #changes > 0 then
            return { kind = "changes", changes = changes, label = "Show Group Frames While Solo",
                bulkSafe = #changes > 1, summary = "Changes only solo visibility for the requested group frame.",
                raw = raw, normalized = normalized }
        end
    end
    if normalized:find("bar outline thickness", 1, true)
        and not normalized:find("castbar", 1, true)
        and not normalized:find("cast bar", 1, true)
        and not P.DetectUnits(normalized)[1]
        and not P.DetectGroups(normalized)[1]
    then
        local setting = A.Registry and A.Registry:GetSetting("bars.barOutlineThickness")
        local value = P.FirstNumber(normalized)
        if setting and value ~= nil then
            return { kind = "changes", changes = { { setting = setting, value = value } },
                label = setting.label or "Global Bar Outline Thickness",
                summary = "Changes global unit-frame bar outline thickness.", raw = raw, normalized = normalized }
        end
    end
    if normalized:find("font sizes", 1, true)
        and not P.DetectUnits(normalized)[1] and not P.DetectGroups(normalized)[1]
    then
        local setting = A.Registry and A.Registry:GetSetting("general.fontSize")
        local value = P.FirstNumber(normalized)
        if setting and value ~= nil then
            return { kind = "changes", changes = { { setting = setting, value = value } },
                label = setting.label or "Global Font Size", summary = "Changes the global MSUF font size.",
                raw = raw, normalized = normalized }
        end
    end
    -- "cast target name" also looks like a scoped unit-frame name-color
    -- request. Resolve the explicit Castbar phrase first so it cannot be
    -- consumed by the broader target-name font shortcut.
    local castbarTargetNameColorPriorityParsed = ContainsAny(normalized, P.CastbarColorFastTerms.targetName)
        and A._ParseCastbarColorFastShortcut and A._ParseCastbarColorFastShortcut(normalized, raw)
    if castbarTargetNameColorPriorityParsed then
        castbarTargetNameColorPriorityParsed.raw = raw
        castbarTargetNameColorPriorityParsed.normalized = normalized
        return castbarTargetNameColorPriorityParsed
    end
    local multiFontColorIntent = normalized:find("name", 1, true)
        and (normalized:find("health text", 1, true) or normalized:find("hp text", 1, true)
            or normalized:find("power text", 1, true))
    if P.ParseScopedFontTextColorShortcut and not multiFontColorIntent then
        local fontColorPriority = P.ParseScopedFontTextColorShortcut(normalized)
        if fontColorPriority then
            fontColorPriority.raw = raw
            fontColorPriority.normalized = normalized
            return fontColorPriority
        end
    end
    if (normalized:find("shorten", 1, true) or normalized:find("truncat", 1, true)
        or normalized:find("ellipsis", 1, true))
        and (normalized:find("party", 1, true) or normalized:find("raid", 1, true))
    then
        if normalized:find("shorten", 1, true) then
            local value = not (normalized:find("do not", 1, true) or normalized:find("dont", 1, true)
                or normalized:find("turn off", 1, true) or normalized:find("disable", 1, true))
            local changes = {}
            for _, scope in ipairs(P.DetectGroups(normalized) or {}) do
                local setting = A.Registry and A.Registry:GetSetting("gf_" .. tostring(scope) .. ".nameShortenEnabled")
                if setting then changes[#changes + 1] = { setting = setting, value = value } end
            end
            if #changes > 0 then
                return { kind = "changes", changes = changes, label = "Group Name Shortening",
                    bulkSafe = #changes > 1, summary = "Changes group-frame name shortening.", raw = raw, normalized = normalized }
            end
        end
        local groupNamePriority = A._ParseGroupNameTextFastShortcut and A._ParseGroupNameTextFastShortcut(normalized)
        if groupNamePriority then
            groupNamePriority.raw = raw
            groupNamePriority.normalized = normalized
            return groupNamePriority
        end
    end
    local humanSafetyParsed = A._ParseHumanSafetyGuidanceShortcut and A._ParseHumanSafetyGuidanceShortcut(normalized)
    if humanSafetyParsed then
        humanSafetyParsed.raw = raw
        humanSafetyParsed.normalized = normalized
        return humanSafetyParsed
    end
    local unitRaidMarkerVisibilityParsed = A._ParseUnitRaidMarkerVisibilityShortcut and A._ParseUnitRaidMarkerVisibilityShortcut(normalized)
    if unitRaidMarkerVisibilityParsed then
        unitRaidMarkerVisibilityParsed.raw = raw
        unitRaidMarkerVisibilityParsed.normalized = normalized
        return unitRaidMarkerVisibilityParsed
    end
    local replayFollowupParsed = (normalized:find("same", 1, true) or normalized:find("gleich", 1, true))
        and BuildFollowup and BuildFollowup(normalized, ctx)
    if replayFollowupParsed then
        replayFollowupParsed.raw = raw
        replayFollowupParsed.normalized = normalized
        return replayFollowupParsed
    end
    local continuationPriorityParsed = P.BuildContinuationFollowup and P.BuildContinuationFollowup(normalized, ctx)
    if continuationPriorityParsed then
        continuationPriorityParsed.raw = raw
        continuationPriorityParsed.normalized = normalized
        return continuationPriorityParsed
    end
    -- A destructive action alias is more specific than a setting alias with
    -- the same noun phrase (for example, "reset target aura scope" must reset
    -- the scope overrides, not set the Aura Editing Scope dropdown to Target).
    if P.ContainsAny(normalized, P.RootPhrases[779]) and P.ParseRegistryActionAliasShortcut then
        local actionText = normalized
        if P.HasPhrase(normalized, "restore") then
            actionText = normalized:gsub("%f[%a]restore%f[%A]", "reset")
        end
        local destructiveAction = P.ParseRegistryActionAliasShortcut(actionText, raw)
        local actionKey = destructiveAction and destructiveAction.action and tostring(destructiveAction.action.key or "") or ""
        if destructiveAction and (destructiveAction.action.type == "reset" or actionKey:find("^reset[_%.]")) then
            destructiveAction.raw = raw
            destructiveAction.normalized = normalized
            return destructiveAction
        end
    end
    -- Menu selectors change editing context; they must win over an exact
    -- setting alias for the selected dropdown (for example, "select player
    -- HP left slot" is not a request to choose an HP text format yet).
    local shouldTryEarlyCompound = P.ShouldTryEarlyCompound and P.ShouldTryEarlyCompound(normalized)
    local menuSelectorPriorityParsed = P.ParseMenuSelectorState and P.ParseMenuSelectorState(normalized)
    if menuSelectorPriorityParsed then
        menuSelectorPriorityParsed.raw = raw
        menuSelectorPriorityParsed.normalized = normalized
        return menuSelectorPriorityParsed
    end
    local hpTextOptionPriorityParsed = not shouldTryEarlyCompound
        and A._ParseHPTextOptionShortcut and A._ParseHPTextOptionShortcut(normalized)
    if hpTextOptionPriorityParsed then
        hpTextOptionPriorityParsed.raw = raw
        hpTextOptionPriorityParsed.normalized = normalized
        return hpTextOptionPriorityParsed
    end
    local textVisibilityPriorityParsed = not shouldTryEarlyCompound
        and P.ParseTextVisibilityShortcut and P.ParseTextVisibilityShortcut(normalized)
    if textVisibilityPriorityParsed then
        textVisibilityPriorityParsed.raw = raw
        textVisibilityPriorityParsed.normalized = normalized
        return textVisibilityPriorityParsed
    end
    local explicitTextSlotContent = normalized:find("text", 1, true)
        or normalized:find("slot", 1, true) or normalized:find("label", 1, true)
    local textSlotContentPriorityParsed = not shouldTryEarlyCompound and explicitTextSlotContent
        and A._ParseTextSlotDropdownShortcut and A._ParseTextSlotDropdownShortcut(normalized)
    if textSlotContentPriorityParsed then
        textSlotContentPriorityParsed.raw = raw
        textSlotContentPriorityParsed.normalized = normalized
        return textSlotContentPriorityParsed
    end
    if P.ContainsAny(normalized, P.RootPhrases[759]) then
        local copySelectorPriorityParsed = (P.ParseUnitCopyScopeState and P.ParseUnitCopyScopeState(normalized))
            or (P.ParseGroupCopyScopeState and P.ParseGroupCopyScopeState(normalized))
        if copySelectorPriorityParsed then
            copySelectorPriorityParsed.raw = raw
            copySelectorPriorityParsed.normalized = normalized
            return copySelectorPriorityParsed
        end
    end
    local nameAnchorPriorityParsed = (A._ParseNameTextAnchorShortcut and A._ParseNameTextAnchorShortcut(normalized))
        or (A._ParseNameTextVerticalPlacementShortcut and A._ParseNameTextVerticalPlacementShortcut(normalized))
        or (A._ParseNameTextOffsetShortcut and A._ParseNameTextOffsetShortcut(normalized))
    if nameAnchorPriorityParsed then
        nameAnchorPriorityParsed.raw = raw
        nameAnchorPriorityParsed.normalized = normalized
        return nameAnchorPriorityParsed
    end
    local humanAnchorPriorityParsed = P.ParseHumanAnchorTarget
        and P.ParseHumanAnchorTarget(normalized, raw)
    if humanAnchorPriorityParsed then
        humanAnchorPriorityParsed.raw = raw
        humanAnchorPriorityParsed.normalized = normalized
        return humanAnchorPriorityParsed
    end
    local castbarPositionPriorityParsed = P.ParseCastbarPositionRegistryShortcut
        and P.ParseCastbarPositionRegistryShortcut(normalized)
    if castbarPositionPriorityParsed then
        castbarPositionPriorityParsed.raw = raw
        castbarPositionPriorityParsed.normalized = normalized
        return castbarPositionPriorityParsed
    end
    local castbarFillPriorityParsed = P.ParseCastbarFillDirectionRegistryShortcut
        and P.ParseCastbarFillDirectionRegistryShortcut(normalized)
    if castbarFillPriorityParsed then
        castbarFillPriorityParsed.raw = raw
        castbarFillPriorityParsed.normalized = normalized
        return castbarFillPriorityParsed
    end
    if normalized:find("group number", 1, true) or normalized:find("subgroup", 1, true) then
        local groupNumberMovePriorityParsed = P.ParseGenericOffsetMove and P.ParseGenericOffsetMove(normalized)
        if groupNumberMovePriorityParsed then
            groupNumberMovePriorityParsed.raw = raw
            groupNumberMovePriorityParsed.normalized = normalized
            return groupNumberMovePriorityParsed
        end
    end
    local globalUiScalePriority = A._ParseGlobalUiScaleFastShortcut
        and A._ParseGlobalUiScaleFastShortcut(normalized)
    if globalUiScalePriority then
        globalUiScalePriority.raw = raw
        globalUiScalePriority.normalized = normalized
        return globalUiScalePriority
    end
    -- Long exact-alias phrases are the most specific statement of intent a
    -- sentence can carry; resolve them before every topical fast path so a
    -- broad parent shortcut (including absorb/heal prediction or Aura lane
    -- visibility) cannot swallow a precisely named child/root option.
    -- Full-phrase mode requires the whole command minus verb and value to be
    -- exactly one alias; anything less precise continues through the pipeline.
    local exactAliasPriorityParsed = (P.ParseTargetGateLoadConditionShortcut and P.ParseTargetGateLoadConditionShortcut(normalized))
        or (not colorResetIntent and P.ParseRegistryExactAliasShortcut
            and P.ParseRegistryExactAliasShortcut(normalized, raw, { minTokens = 3, fullPhrase = true }))
    if exactAliasPriorityParsed then
        exactAliasPriorityParsed.raw = raw
        exactAliasPriorityParsed.normalized = normalized
        return exactAliasPriorityParsed
    end
    -- Resolve a proven multi-change sentence before any single-setting fast
    -- path can consume only its first item. ParseCompound internally rejects
    -- ordinary one-setting commands and uses ParseSimpleChange recursively.
    local earlyCompoundParsed = shouldTryEarlyCompound
        and P.ParseCompound and P.ParseCompound(normalized, raw, nil)
    if earlyCompoundParsed then
        earlyCompoundParsed.raw = raw
        earlyCompoundParsed.normalized = normalized
        return earlyCompoundParsed
    end
    local earlyDispelOverlayOpacityParsed = A._ParseDispelOverlayOpacityShortcut and A._ParseDispelOverlayOpacityShortcut(normalized)
    if earlyDispelOverlayOpacityParsed then
        earlyDispelOverlayOpacityParsed.raw = raw
        earlyDispelOverlayOpacityParsed.normalized = normalized
        return earlyDispelOverlayOpacityParsed
    end
    local earlyScopedDispelBorderTriggerParsed = A._ParseScopedDispelBorderTriggerFastShortcut and A._ParseScopedDispelBorderTriggerFastShortcut(normalized)
    if earlyScopedDispelBorderTriggerParsed then
        earlyScopedDispelBorderTriggerParsed.raw = raw
        earlyScopedDispelBorderTriggerParsed.normalized = normalized
        return earlyScopedDispelBorderTriggerParsed
    end
    if LooksLikeAbsorbBarCommand(normalized) then
        local earlyAbsorbBarParsed = P.ParseAbsorbBarShortcut and P.ParseAbsorbBarShortcut(normalized, raw)
        if earlyAbsorbBarParsed then
            earlyAbsorbBarParsed.raw = raw
            earlyAbsorbBarParsed.normalized = normalized
            return earlyAbsorbBarParsed
        end
    end
    local earlyPowerColorTokenParsed = not colorResetIntent and A._ParsePowerColorTokenFastShortcut
        and A._ParsePowerColorTokenFastShortcut(normalized, raw)
    if earlyPowerColorTokenParsed then
        earlyPowerColorTokenParsed.raw = raw
        earlyPowerColorTokenParsed.normalized = normalized
        return earlyPowerColorTokenParsed
    end
    -- A complete status-indicator anchor preset ("move ... to the top
    -- right") is more specific than the generic directional nudge fast path.
    -- Plain "move ... right" still falls through because the detail parser
    -- only returns an anchor plan for an explicit anchor/preset intent.
    local humanIndicatorMovePriorityParsed = (P.ParseUnitStatusIndicatorDetail and P.ParseUnitStatusIndicatorDetail(normalized))
        or (A._ParseHumanIndicatorMoveFastShortcut and A._ParseHumanIndicatorMoveFastShortcut(normalized))
    if humanIndicatorMovePriorityParsed then
        humanIndicatorMovePriorityParsed.raw = raw
        humanIndicatorMovePriorityParsed.normalized = normalized
        return humanIndicatorMovePriorityParsed
    end
    local globalStatusTextPriorityParsed = ParseGlobalStatusTextStateShortcut(normalized)
    if globalStatusTextPriorityParsed then
        globalStatusTextPriorityParsed.raw = raw
        globalStatusTextPriorityParsed.normalized = normalized
        return globalStatusTextPriorityParsed
    end
    local classResourceFillPriorityParsed = ParseClassResourceFillFastShortcut(normalized)
    if classResourceFillPriorityParsed then
        classResourceFillPriorityParsed.raw = raw
        classResourceFillPriorityParsed.normalized = normalized
        return classResourceFillPriorityParsed
    end
    local auraBlacklistPresetPriorityParsed = ParseAuraBlacklistPresetFastShortcut(normalized)
    if auraBlacklistPresetPriorityParsed then
        auraBlacklistPresetPriorityParsed.raw = raw
        auraBlacklistPresetPriorityParsed.normalized = normalized
        return auraBlacklistPresetPriorityParsed
    end
    local dispelBorderTriggerPriorityParsed = ParseDispelBorderTriggerFastShortcut(normalized)
    if dispelBorderTriggerPriorityParsed then
        dispelBorderTriggerPriorityParsed.raw = raw
        dispelBorderTriggerPriorityParsed.normalized = normalized
        return dispelBorderTriggerPriorityParsed
    end
    local unitPortraitShapePriorityParsed = ParseUnitPortraitShapeFastShortcut(normalized)
    if unitPortraitShapePriorityParsed then
        unitPortraitShapePriorityParsed.raw = raw
        unitPortraitShapePriorityParsed.normalized = normalized
        return unitPortraitShapePriorityParsed
    end
    local directSettingPriorityParsed = (A._ParseGlobalStatusIconsStyleFastShortcut and A._ParseGlobalStatusIconsStyleFastShortcut(normalized))
        or (A._ParseUnitAnchorPointFastShortcut and A._ParseUnitAnchorPointFastShortcut(normalized))
        or (A._ParseBossTargetHighlightFastShortcut and A._ParseBossTargetHighlightFastShortcut(normalized))
    if directSettingPriorityParsed then
        directSettingPriorityParsed.raw = raw
        directSettingPriorityParsed.normalized = normalized
        return directSettingPriorityParsed
    end
    local globalFontColorPriorityParsed = A._ParseGlobalFontColorFastShortcut and A._ParseGlobalFontColorFastShortcut(normalized, raw)
    if globalFontColorPriorityParsed then
        globalFontColorPriorityParsed.raw = raw
        globalFontColorPriorityParsed.normalized = normalized
        return globalFontColorPriorityParsed
    end
    local specResourceColorPriorityParsed = A._ParseSpecResourceColorShortcut and A._ParseSpecResourceColorShortcut(normalized, raw)
    if specResourceColorPriorityParsed then
        specResourceColorPriorityParsed.raw = raw
        specResourceColorPriorityParsed.normalized = normalized
        return specResourceColorPriorityParsed
    end
    local classResourceColorPriorityParsed = A._ParseClassPowerColorPriorityShortcut and A._ParseClassPowerColorPriorityShortcut(normalized, raw)
    if classResourceColorPriorityParsed then
        classResourceColorPriorityParsed.raw = raw
        classResourceColorPriorityParsed.normalized = normalized
        return classResourceColorPriorityParsed
    end
    local classColorPriorityParsed = A._ParseClassColorFastShortcut and A._ParseClassColorFastShortcut(normalized, raw)
    if classColorPriorityParsed then
        classColorPriorityParsed.raw = raw
        classColorPriorityParsed.normalized = normalized
        return classColorPriorityParsed
    end
    local globalBarBackgroundPriorityParsed = A._ParseGlobalBarBackgroundFastShortcut and A._ParseGlobalBarBackgroundFastShortcut(normalized, raw)
    if globalBarBackgroundPriorityParsed then
        globalBarBackgroundPriorityParsed.raw = raw
        globalBarBackgroundPriorityParsed.normalized = normalized
        return globalBarBackgroundPriorityParsed
    end
    local darkModeCustomColorPriorityParsed = A._ParseDarkModeCustomColorFastShortcut and A._ParseDarkModeCustomColorFastShortcut(normalized)
    if darkModeCustomColorPriorityParsed then
        darkModeCustomColorPriorityParsed.raw = raw
        darkModeCustomColorPriorityParsed.normalized = normalized
        return darkModeCustomColorPriorityParsed
    end
    local globalUnitFrameColorPriorityParsed = A._ParseGlobalUnitFrameColorFastShortcut and A._ParseGlobalUnitFrameColorFastShortcut(normalized, raw)
    if globalUnitFrameColorPriorityParsed then
        globalUnitFrameColorPriorityParsed.raw = raw
        globalUnitFrameColorPriorityParsed.normalized = normalized
        return globalUnitFrameColorPriorityParsed
    end
    local exactColorSettingPriorityParsed = A._ParseExactColorSettingFastShortcut and A._ParseExactColorSettingFastShortcut(normalized, raw)
    if exactColorSettingPriorityParsed then
        exactColorSettingPriorityParsed.raw = raw
        exactColorSettingPriorityParsed.normalized = normalized
        return exactColorSettingPriorityParsed
    end
    local lastBarGradientGroupFollowupParsed = A._ParseLastBarGradientGroupFollowup and A._ParseLastBarGradientGroupFollowup(normalized, ctx)
    if lastBarGradientGroupFollowupParsed then
        lastBarGradientGroupFollowupParsed.raw = raw
        lastBarGradientGroupFollowupParsed.normalized = normalized
        return lastBarGradientGroupFollowupParsed
    end
    local healthColorGradientPriorityParsed = A._ParseHealthColorGradientFastShortcut and A._ParseHealthColorGradientFastShortcut(normalized, raw)
    if healthColorGradientPriorityParsed then
        healthColorGradientPriorityParsed.raw = raw
        healthColorGradientPriorityParsed.normalized = normalized
        return healthColorGradientPriorityParsed
    end
    local npcReactionColorPriorityParsed = A._ParseNPCReactionColorFastShortcut and A._ParseNPCReactionColorFastShortcut(normalized, raw)
    if npcReactionColorPriorityParsed then
        npcReactionColorPriorityParsed.raw = raw
        npcReactionColorPriorityParsed.normalized = normalized
        return npcReactionColorPriorityParsed
    end
    local petFrameColorPriorityParsed = A._ParsePetFrameColorFastShortcut and A._ParsePetFrameColorFastShortcut(normalized, raw)
    if petFrameColorPriorityParsed then
        petFrameColorPriorityParsed.raw = raw
        petFrameColorPriorityParsed.normalized = normalized
        return petFrameColorPriorityParsed
    end
    local powerColorTokenPriorityParsed = not colorResetIntent and A._ParsePowerColorTokenFastShortcut
        and A._ParsePowerColorTokenFastShortcut(normalized, raw)
    if powerColorTokenPriorityParsed then
        powerColorTokenPriorityParsed.raw = raw
        powerColorTokenPriorityParsed.normalized = normalized
        return powerColorTokenPriorityParsed
    end
    local castbarColorPriorityParsed = A._ParseCastbarColorFastShortcut and A._ParseCastbarColorFastShortcut(normalized, raw)
    if castbarColorPriorityParsed then
        castbarColorPriorityParsed.raw = raw
        castbarColorPriorityParsed.normalized = normalized
        return castbarColorPriorityParsed
    end
    local castbarOverrideModePriorityParsed = A._ParseCastbarOverrideModeFastShortcut and A._ParseCastbarOverrideModeFastShortcut(normalized)
    if castbarOverrideModePriorityParsed then
        castbarOverrideModePriorityParsed.raw = raw
        castbarOverrideModePriorityParsed.normalized = normalized
        return castbarOverrideModePriorityParsed
    end
    local globalHighlightColorPriorityParsed = A._ParseGlobalHighlightColorFastShortcut and A._ParseGlobalHighlightColorFastShortcut(normalized, raw)
    if globalHighlightColorPriorityParsed then
        globalHighlightColorPriorityParsed.raw = raw
        globalHighlightColorPriorityParsed.normalized = normalized
        return globalHighlightColorPriorityParsed
    end
    local mouseoverHighlightPriorityParsed = A._ParseMouseoverHighlightFastShortcut and A._ParseMouseoverHighlightFastShortcut(normalized, raw)
    if mouseoverHighlightPriorityParsed then
        mouseoverHighlightPriorityParsed.raw = raw
        mouseoverHighlightPriorityParsed.normalized = normalized
        return mouseoverHighlightPriorityParsed
    end
    local scopedBarOutlineColorPriorityParsed = A._ParseScopedBarOutlineColorFastShortcut and A._ParseScopedBarOutlineColorFastShortcut(normalized, raw)
    if scopedBarOutlineColorPriorityParsed then
        scopedBarOutlineColorPriorityParsed.raw = raw
        scopedBarOutlineColorPriorityParsed.normalized = normalized
        return scopedBarOutlineColorPriorityParsed
    end
    local npcTypeColorPriorityParsed = A._ParseNPCTypeColorFastShortcut and A._ParseNPCTypeColorFastShortcut(normalized)
    if npcTypeColorPriorityParsed then
        npcTypeColorPriorityParsed.raw = raw
        npcTypeColorPriorityParsed.normalized = normalized
        return npcTypeColorPriorityParsed
    end
    local classResourceHPBarPriorityParsed = A._ParseClassResourceHPBarFastShortcut and A._ParseClassResourceHPBarFastShortcut(normalized)
    if classResourceHPBarPriorityParsed then
        classResourceHPBarPriorityParsed.raw = raw
        classResourceHPBarPriorityParsed.normalized = normalized
        return classResourceHPBarPriorityParsed
    end
    local globalColorModeBooleanPriorityParsed = A._ParseGlobalColorModeBooleanFastShortcut and A._ParseGlobalColorModeBooleanFastShortcut(normalized)
    if globalColorModeBooleanPriorityParsed then
        globalColorModeBooleanPriorityParsed.raw = raw
        globalColorModeBooleanPriorityParsed.normalized = normalized
        return globalColorModeBooleanPriorityParsed
    end
    local raidMarkerNumberPriorityParsed = A._ParseRaidMarkerNumberFastShortcut and A._ParseRaidMarkerNumberFastShortcut(normalized)
    if raidMarkerNumberPriorityParsed then
        raidMarkerNumberPriorityParsed.raw = raw
        raidMarkerNumberPriorityParsed.normalized = normalized
        return raidMarkerNumberPriorityParsed
    end
    local exactTextSlotOffsetPriorityParsed = A._ParseExactTextSlotOffsetFastShortcut and A._ParseExactTextSlotOffsetFastShortcut(normalized)
    if exactTextSlotOffsetPriorityParsed then
        exactTextSlotOffsetPriorityParsed.raw = raw
        exactTextSlotOffsetPriorityParsed.normalized = normalized
        return exactTextSlotOffsetPriorityParsed
    end
    local ambiguousFontTextColorParsed = P.ParseAmbiguousFontTextColorShortcut and P.ParseAmbiguousFontTextColorShortcut(normalized)
    if ambiguousFontTextColorParsed then
        ambiguousFontTextColorParsed.raw = raw
        ambiguousFontTextColorParsed.normalized = normalized
        return ambiguousFontTextColorParsed
    end
    local ambiguousColorParsed = P.ParseAmbiguousColorShortcut and P.ParseAmbiguousColorShortcut(normalized, raw)
    if ambiguousColorParsed then
        ambiguousColorParsed.raw = raw
        ambiguousColorParsed.normalized = normalized
        return ambiguousColorParsed
    end
    local fontTextColorParsed = P.ParseScopedFontTextColorShortcut and P.ParseScopedFontTextColorShortcut(normalized, raw)
    if fontTextColorParsed then
        fontTextColorParsed.raw = raw
        fontTextColorParsed.normalized = normalized
        return fontTextColorParsed
    end
    local globalBarModePriorityParsed = A._ParseGlobalBarModePriorityShortcut and A._ParseGlobalBarModePriorityShortcut(normalized)
    if globalBarModePriorityParsed then
        globalBarModePriorityParsed.raw = raw
        globalBarModePriorityParsed.normalized = normalized
        return globalBarModePriorityParsed
    end
    local globalBarTexturePriorityParsed = A._ParseGlobalBarTexturePriorityShortcut and A._ParseGlobalBarTexturePriorityShortcut(normalized, raw)
    if globalBarTexturePriorityParsed then
        globalBarTexturePriorityParsed.raw = raw
        globalBarTexturePriorityParsed.normalized = normalized
        return globalBarTexturePriorityParsed
    end
    local globalGradientStrengthPriorityParsed = A._ParseGlobalGradientStrengthPriorityShortcut and A._ParseGlobalGradientStrengthPriorityShortcut(normalized)
    if globalGradientStrengthPriorityParsed then
        globalGradientStrengthPriorityParsed.raw = raw
        globalGradientStrengthPriorityParsed.normalized = normalized
        return globalGradientStrengthPriorityParsed
    end
    local globalRoundedBarsPriorityParsed = A._ParseGlobalRoundedBarsPriorityShortcut and A._ParseGlobalRoundedBarsPriorityShortcut(normalized)
    if globalRoundedBarsPriorityParsed then
        globalRoundedBarsPriorityParsed.raw = raw
        globalRoundedBarsPriorityParsed.normalized = normalized
        return globalRoundedBarsPriorityParsed
    end
    local groupDispelOverlayPriorityParsed = A._ParseGroupDispelOverlayFastShortcut and A._ParseGroupDispelOverlayFastShortcut(normalized)
    if groupDispelOverlayPriorityParsed then
        groupDispelOverlayPriorityParsed.raw = raw
        groupDispelOverlayPriorityParsed.normalized = normalized
        return groupDispelOverlayPriorityParsed
    end
    local globalUnitDispelOverlayPriorityParsed = A._ParseGlobalUnitDispelOverlayPriorityShortcut and A._ParseGlobalUnitDispelOverlayPriorityShortcut(normalized)
    if globalUnitDispelOverlayPriorityParsed then
        globalUnitDispelOverlayPriorityParsed.raw = raw
        globalUnitDispelOverlayPriorityParsed.normalized = normalized
        return globalUnitDispelOverlayPriorityParsed
    end
    local scopedUnitDispelOverlayPriorityParsed = A._ParseScopedUnitDispelOverlayPriorityShortcut and A._ParseScopedUnitDispelOverlayPriorityShortcut(normalized)
    if scopedUnitDispelOverlayPriorityParsed then
        scopedUnitDispelOverlayPriorityParsed.raw = raw
        scopedUnitDispelOverlayPriorityParsed.normalized = normalized
        return scopedUnitDispelOverlayPriorityParsed
    end
    local globalPowerBarDetailPriorityParsed = A._ParseGlobalPowerBarDetailPriorityShortcut and A._ParseGlobalPowerBarDetailPriorityShortcut(normalized)
    if globalPowerBarDetailPriorityParsed then
        globalPowerBarDetailPriorityParsed.raw = raw
        globalPowerBarDetailPriorityParsed.normalized = normalized
        return globalPowerBarDetailPriorityParsed
    end
    local scopedBarOverridePriorityParsed = A._ParseScopedBarOverridePriorityShortcut and A._ParseScopedBarOverridePriorityShortcut(normalized)
    if scopedBarOverridePriorityParsed then
        scopedBarOverridePriorityParsed.raw = raw
        scopedBarOverridePriorityParsed.normalized = normalized
        return scopedBarOverridePriorityParsed
    end
    local scopedGradientStrengthPriorityParsed = A._ParseScopedGradientStrengthPriorityShortcut and A._ParseScopedGradientStrengthPriorityShortcut(normalized)
    if scopedGradientStrengthPriorityParsed then
        scopedGradientStrengthPriorityParsed.raw = raw
        scopedGradientStrengthPriorityParsed.normalized = normalized
        return scopedGradientStrengthPriorityParsed
    end
    local globalFontPriorityParsed = A._ParseGlobalFontPriorityShortcut and A._ParseGlobalFontPriorityShortcut(normalized, raw)
    if globalFontPriorityParsed then
        globalFontPriorityParsed.raw = raw
        globalFontPriorityParsed.normalized = normalized
        return globalFontPriorityParsed
    end
    local fontScopePriorityParsed = A._ParseFontScopePriorityShortcut and A._ParseFontScopePriorityShortcut(normalized)
    if fontScopePriorityParsed then
        fontScopePriorityParsed.raw = raw
        fontScopePriorityParsed.normalized = normalized
        return fontScopePriorityParsed
    end
    local globalUIShellPriorityParsed = A._ParseGlobalUIShellPriorityShortcut and A._ParseGlobalUIShellPriorityShortcut(normalized, raw)
    if globalUIShellPriorityParsed then
        globalUIShellPriorityParsed.raw = raw
        globalUIShellPriorityParsed.normalized = normalized
        return globalUIShellPriorityParsed
    end
    local dashboardScalePriorityParsed = A._ParseDashboardScaleFastShortcut and A._ParseDashboardScaleFastShortcut(normalized)
    if dashboardScalePriorityParsed then
        dashboardScalePriorityParsed.raw = raw
        dashboardScalePriorityParsed.normalized = normalized
        return dashboardScalePriorityParsed
    end
    local barGradientPriorityParsed = A._ParseBarGradientPriorityShortcut and A._ParseBarGradientPriorityShortcut(normalized)
    if barGradientPriorityParsed then
        barGradientPriorityParsed.raw = raw
        barGradientPriorityParsed.normalized = normalized
        return barGradientPriorityParsed
    end
    -- Keep the more specific detached Player Power surface ahead of the broad
    -- "class resources" shortcuts.  Both vocabularies intentionally overlap,
    -- but an explicit "class resources player power" request must retain the
    -- Player Power qualifier instead of falling back to the class-resource bar.
    local detachedPlayerPowerPriorityParsed = not colorResetIntent and A._ParseClassPowerDetachedPlayerPowerShortcut
        and A._ParseClassPowerDetachedPlayerPowerShortcut(normalized, raw)
    if detachedPlayerPowerPriorityParsed then
        detachedPlayerPowerPriorityParsed.raw = raw
        detachedPlayerPowerPriorityParsed.normalized = normalized
        return detachedPlayerPowerPriorityParsed
    end
    local classPowerPriorityParsed = not colorResetIntent and A._ParseClassPowerPriorityShortcut
        and A._ParseClassPowerPriorityShortcut(normalized, raw)
    if classPowerPriorityParsed then
        classPowerPriorityParsed.raw = raw
        classPowerPriorityParsed.normalized = normalized
        return classPowerPriorityParsed
    end
    local gameplayPriorityParsed = A._ParseGameplayPriorityShortcut and A._ParseGameplayPriorityShortcut(normalized, raw)
    if gameplayPriorityParsed then
        gameplayPriorityParsed.raw = raw
        gameplayPriorityParsed.normalized = normalized
        return gameplayPriorityParsed
    end
    local castbarWidthModeParsed = A._ParseCastbarWidthModeShortcut and A._ParseCastbarWidthModeShortcut(normalized)
    if castbarWidthModeParsed then
        castbarWidthModeParsed.raw = raw
        castbarWidthModeParsed.normalized = normalized
        return castbarWidthModeParsed
    end
    local groupSpellIndicatorsParsed = A._ParseGroupSpellIndicatorsFastShortcut and A._ParseGroupSpellIndicatorsFastShortcut(normalized)
    if groupSpellIndicatorsParsed then
        groupSpellIndicatorsParsed.raw = raw
        groupSpellIndicatorsParsed.normalized = normalized
        return groupSpellIndicatorsParsed
    end
    local groupBlizzardFallbackParsed = A._ParseGroupBlizzardFallbackFastShortcut and A._ParseGroupBlizzardFallbackFastShortcut(normalized)
    if groupBlizzardFallbackParsed then
        groupBlizzardFallbackParsed.raw = raw
        groupBlizzardFallbackParsed.normalized = normalized
        return groupBlizzardFallbackParsed
    end
    local groupHideOfflineDelayParsed = A._ParseGroupHideOfflineDelayFastShortcut and A._ParseGroupHideOfflineDelayFastShortcut(normalized)
    if groupHideOfflineDelayParsed then
        groupHideOfflineDelayParsed.raw = raw
        groupHideOfflineDelayParsed.normalized = normalized
        return groupHideOfflineDelayParsed
    end
    local groupReverseFillParsed = A._ParseGroupReverseFillFastShortcut and A._ParseGroupReverseFillFastShortcut(normalized)
    if groupReverseFillParsed then
        groupReverseFillParsed.raw = raw
        groupReverseFillParsed.normalized = normalized
        return groupReverseFillParsed
    end
    local unitReverseFillParsed = A._ParseUnitReverseFillFastShortcut and A._ParseUnitReverseFillFastShortcut(normalized)
    if unitReverseFillParsed then
        unitReverseFillParsed.raw = raw
        unitReverseFillParsed.normalized = normalized
        return unitReverseFillParsed
    end
    local unitSimpleBooleanParsed = A._ParseUnitSimpleBooleanFastShortcut and A._ParseUnitSimpleBooleanFastShortcut(normalized)
    if unitSimpleBooleanParsed then
        unitSimpleBooleanParsed.raw = raw
        unitSimpleBooleanParsed.normalized = normalized
        return unitSimpleBooleanParsed
    end
    local unitStatusDetailParsed = A._ParseUnitStatusDetailFastShortcut and A._ParseUnitStatusDetailFastShortcut(normalized)
    if unitStatusDetailParsed then
        unitStatusDetailParsed.raw = raw
        unitStatusDetailParsed.normalized = normalized
        return unitStatusDetailParsed
    end
    local groupSimpleBooleanParsed = A._ParseGroupSimpleBooleanFastShortcut and A._ParseGroupSimpleBooleanFastShortcut(normalized)
    if groupSimpleBooleanParsed then
        groupSimpleBooleanParsed.raw = raw
        groupSimpleBooleanParsed.normalized = normalized
        return groupSimpleBooleanParsed
    end
    local groupCornerCustomParsed = A._ParseGroupCornerCustomFastShortcut and A._ParseGroupCornerCustomFastShortcut(normalized, raw)
    if groupCornerCustomParsed then
        groupCornerCustomParsed.raw = raw
        groupCornerCustomParsed.normalized = normalized
        return groupCornerCustomParsed
    end
    local groupTextureParsed = A._ParseGroupTextureFastShortcut and A._ParseGroupTextureFastShortcut(normalized, raw)
    if groupTextureParsed then
        groupTextureParsed.raw = raw
        groupTextureParsed.normalized = normalized
        return groupTextureParsed
    end
    local groupNameTextParsed = A._ParseGroupNameTextFastShortcut and A._ParseGroupNameTextFastShortcut(normalized)
    if groupNameTextParsed then
        groupNameTextParsed.raw = raw
        groupNameTextParsed.normalized = normalized
        return groupNameTextParsed
    end
    local groupRolePowerParsed = A._ParseGroupRolePowerFastShortcut and A._ParseGroupRolePowerFastShortcut(normalized)
    if groupRolePowerParsed then
        groupRolePowerParsed.raw = raw
        groupRolePowerParsed.normalized = normalized
        return groupRolePowerParsed
    end
    local groupPowerBarParsed = A._ParseGroupPowerBarEnabledFastShortcut and A._ParseGroupPowerBarEnabledFastShortcut(normalized)
    if groupPowerBarParsed then
        groupPowerBarParsed.raw = raw
        groupPowerBarParsed.normalized = normalized
        return groupPowerBarParsed
    end
    local groupOrderingParsed = A._ParseGroupOrderingFastShortcut and A._ParseGroupOrderingFastShortcut(normalized)
    if groupOrderingParsed then
        groupOrderingParsed.raw = raw
        groupOrderingParsed.normalized = normalized
        return groupOrderingParsed
    end
    local globalUiScaleParsed = A._ParseGlobalUiScaleFastShortcut and A._ParseGlobalUiScaleFastShortcut(normalized)
    if globalUiScaleParsed then
        globalUiScaleParsed.raw = raw
        globalUiScaleParsed.normalized = normalized
        return globalUiScaleParsed
    end
    local groupScalingParsed = A._ParseGroupScalingFastShortcut and A._ParseGroupScalingFastShortcut(normalized)
    if groupScalingParsed then
        groupScalingParsed.raw = raw
        groupScalingParsed.normalized = normalized
        return groupScalingParsed
    end
    local groupFrameAnchorParsed = A._ParseGroupFrameAnchorFastShortcut and A._ParseGroupFrameAnchorFastShortcut(normalized)
    if groupFrameAnchorParsed then
        groupFrameAnchorParsed.raw = raw
        groupFrameAnchorParsed.normalized = normalized
        return groupFrameAnchorParsed
    end
    local groupLayoutNumberParsed = A._ParseGroupLayoutNumberFastShortcut and A._ParseGroupLayoutNumberFastShortcut(normalized)
    if groupLayoutNumberParsed then
        groupLayoutNumberParsed.raw = raw
        groupLayoutNumberParsed.normalized = normalized
        return groupLayoutNumberParsed
    end
    local groupTextDirectParsed = A._ParseGroupTextDirectFastShortcut and A._ParseGroupTextDirectFastShortcut(normalized)
    if groupTextDirectParsed then
        groupTextDirectParsed.raw = raw
        groupTextDirectParsed.normalized = normalized
        return groupTextDirectParsed
    end
    local groupTextFormatParsed = A._ParseGroupTextFormatFastShortcut and A._ParseGroupTextFormatFastShortcut(normalized)
    if groupTextFormatParsed then
        groupTextFormatParsed.raw = raw
        groupTextFormatParsed.normalized = normalized
        return groupTextFormatParsed
    end
    local groupDispelOverlayParsed = A._ParseGroupDispelOverlayFastShortcut and A._ParseGroupDispelOverlayFastShortcut(normalized)
    if groupDispelOverlayParsed then
        groupDispelOverlayParsed.raw = raw
        groupDispelOverlayParsed.normalized = normalized
        return groupDispelOverlayParsed
    end
    local groupRangeFadeParsed = A._ParseGroupRangeFadeFastShortcut and A._ParseGroupRangeFadeFastShortcut(normalized)
    if groupRangeFadeParsed then
        groupRangeFadeParsed.raw = raw
        groupRangeFadeParsed.normalized = normalized
        return groupRangeFadeParsed
    end
    local groupNumberParsed = A._ParseGroupNumberFastShortcut and A._ParseGroupNumberFastShortcut(normalized)
    if groupNumberParsed then
        groupNumberParsed.raw = raw
        groupNumberParsed.normalized = normalized
        return groupNumberParsed
    end
    local groupHighlightParsed = A._ParseGroupHighlightFastShortcut and A._ParseGroupHighlightFastShortcut(normalized)
    if groupHighlightParsed then
        groupHighlightParsed.raw = raw
        groupHighlightParsed.normalized = normalized
        return groupHighlightParsed
    end
    local fullGroupBorderParsed = A._ParseFullGroupBorderFastShortcut and A._ParseFullGroupBorderFastShortcut(normalized)
    if fullGroupBorderParsed then
        fullGroupBorderParsed.raw = raw
        fullGroupBorderParsed.normalized = normalized
        return fullGroupBorderParsed
    end
    local groupStatusIconStyleParsed = A._ParseGroupStatusIconStyleFastShortcut and A._ParseGroupStatusIconStyleFastShortcut(normalized)
    if groupStatusIconStyleParsed then
        groupStatusIconStyleParsed.raw = raw
        groupStatusIconStyleParsed.normalized = normalized
        return groupStatusIconStyleParsed
    end
    local groupBarColorModeParsed = A._ParseGroupBarColorModeFastShortcut and A._ParseGroupBarColorModeFastShortcut(normalized)
    if groupBarColorModeParsed then
        groupBarColorModeParsed.raw = raw
        groupBarColorModeParsed.normalized = normalized
        return groupBarColorModeParsed
    end
    local groupFrameColorParsed = A._ParseGroupFrameColorFastShortcut and A._ParseGroupFrameColorFastShortcut(normalized, raw)
    if groupFrameColorParsed then
        groupFrameColorParsed.raw = raw
        groupFrameColorParsed.normalized = normalized
        return groupFrameColorParsed
    end
    local groupDeadBackgroundParsed = A._ParseGroupDeadBackgroundFastShortcut and A._ParseGroupDeadBackgroundFastShortcut(normalized)
    if groupDeadBackgroundParsed then
        groupDeadBackgroundParsed.raw = raw
        groupDeadBackgroundParsed.normalized = normalized
        return groupDeadBackgroundParsed
    end
    local groupAvailabilityParsed = A._ParseGroupAvailabilityFastShortcut and A._ParseGroupAvailabilityFastShortcut(normalized)
    if groupAvailabilityParsed then
        groupAvailabilityParsed.raw = raw
        groupAvailabilityParsed.normalized = normalized
        return groupAvailabilityParsed
    end
    local groupAuraCooldownDarkenParsed = A._ParseGroupAuraCooldownDarkenShortcut and A._ParseGroupAuraCooldownDarkenShortcut(normalized)
    if groupAuraCooldownDarkenParsed then
        groupAuraCooldownDarkenParsed.raw = raw
        groupAuraCooldownDarkenParsed.normalized = normalized
        return groupAuraCooldownDarkenParsed
    end
    local groupAuraLaneOffsetParsed = (A._ParseGroupAuraLaneBooleanShortcut and A._ParseGroupAuraLaneBooleanShortcut(normalized))
        or (A._ParseGroupAuraLaneTextSizeShortcut and A._ParseGroupAuraLaneTextSizeShortcut(normalized))
        or (A._ParseGroupAuraLaneTextOffsetShortcut and A._ParseGroupAuraLaneTextOffsetShortcut(normalized))
        or (A._ParseGroupAuraLaneOffsetShortcut and A._ParseGroupAuraLaneOffsetShortcut(normalized))
    if groupAuraLaneOffsetParsed then
        groupAuraLaneOffsetParsed.raw = raw
        groupAuraLaneOffsetParsed.normalized = normalized
        return groupAuraLaneOffsetParsed
    end
    local fontRenderingParsed = P.ParseFontRenderingShortcut and P.ParseFontRenderingShortcut(normalized)
    if fontRenderingParsed then
        fontRenderingParsed.raw = raw
        fontRenderingParsed.normalized = normalized
        return fontRenderingParsed
    end
    local fontTextOpacityParsed = P.ParseFontTextOpacityShortcut and P.ParseFontTextOpacityShortcut(normalized)
    if fontTextOpacityParsed then
        fontTextOpacityParsed.raw = raw
        fontTextOpacityParsed.normalized = normalized
        return fontTextOpacityParsed
    end
    local globalFontFamilyParsed = P.ParseGlobalFontFamilyShortcut and P.ParseGlobalFontFamilyShortcut(normalized, raw)
    if globalFontFamilyParsed then
        globalFontFamilyParsed.raw = raw
        globalFontFamilyParsed.normalized = normalized
        return globalFontFamilyParsed
    end
    local dispelOverlayOpacityParsed = A._ParseDispelOverlayOpacityShortcut and A._ParseDispelOverlayOpacityShortcut(normalized)
    if dispelOverlayOpacityParsed then
        dispelOverlayOpacityParsed.raw = raw
        dispelOverlayOpacityParsed.normalized = normalized
        return dispelOverlayOpacityParsed
    end
    if P.ContainsAny(normalized, P.RootPhrases[617]) then
        local opacityUnits = P.DetectUnits(normalized)
        local opacityGroups = P.DetectGroups(normalized)
        local scopedOpacityParsed
        if #opacityUnits > 0 then
            scopedOpacityParsed = A._ParseExplicitUnitBarOpacityShortcut and A._ParseExplicitUnitBarOpacityShortcut(normalized)
                or (P.ParseUnitOpacityShortcut and P.ParseUnitOpacityShortcut(normalized))
        elseif #opacityGroups > 0 then
            scopedOpacityParsed = A._ParseGroupOpacityShortcut and A._ParseGroupOpacityShortcut(normalized)
        end
        if scopedOpacityParsed then
            scopedOpacityParsed.raw = raw
            scopedOpacityParsed.normalized = normalized
            return scopedOpacityParsed
        end
    end
    local editModeControlParsed = A._ParseEditModeHUDControl and A._ParseEditModeHUDControl(normalized)
    if editModeControlParsed then
        editModeControlParsed.raw = raw
        editModeControlParsed.normalized = normalized
        return editModeControlParsed
    end
    local customAnchorActionParsed
    if P.ContainsAny(normalized, P.RootPhrases[618])
        or (P.ContainsAny(normalized, P.RootPhrases[619])
            and P.ContainsAny(normalized, P.RootPhrases[620]))
    then
        customAnchorActionParsed = P.ParseCustomAnchorWorkflow(normalized) or P.ParseCustomAnchorClear(normalized)
        if customAnchorActionParsed then
            customAnchorActionParsed.raw = raw
            customAnchorActionParsed.normalized = normalized
            return customAnchorActionParsed
        end
    end
    if P.ContainsAny(normalized, P.RootPhrases[621]) then
        local setting
        local value
        if P.ContainsAny(normalized, P.RootPhrases[622]) then
            setting = A.Registry and A.Registry:GetSetting("targettarget.totInlineColorMode")
            value = setting and P.EnumValueForText and P.EnumValueForText(setting, normalized) or nil
        elseif P.ContainsAny(normalized, P.RootPhrases[623]) then
            setting = A.Registry and A.Registry:GetSetting("targettarget.totInlineCustomSeparator")
            value = P.RawAfterLastConnector and P.RawAfterLastConnector(raw, { " to ", " as ", " value ", " separator " }) or nil
            value = value or tostring(raw or ""):match("[Tt][Oo]%s+(.+)$")
        elseif P.ContainsAny(normalized, P.RootPhrases[624]) then
            local separatorSetting = A.Registry and A.Registry:GetSetting("targettarget.totInlineSeparator")
            local enumValue = separatorSetting and P.EnumValueForText and P.EnumValueForText(separatorSetting, normalized) or nil
            if enumValue ~= nil then
                setting = separatorSetting
                value = enumValue
            else
                local customValue = P.RawAfterLastConnector
                    and P.RawAfterLastConnector(raw, { " to ", " as ", " value " }) or nil
                if customValue ~= nil and customValue ~= "" then
                    setting = A.Registry and A.Registry:GetSetting("targettarget.totInlineCustomSeparator")
                    value = customValue
                end
            end
        else
            setting = A.Registry and A.Registry:GetSetting("targettarget.showToTInTargetName")
            value = P.DetectBoolean(normalized)
            if value == nil and P.ContainsAny(normalized, P.RootPhrases[625]) then value = true end
            if value == nil and P.ContainsAny(normalized, P.RootPhrases[626]) then value = false end
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
    if P.ContainsAny(normalized, P.RootPhrases[627])
        and P.ContainsAny(normalized, P.RootPhrases[628])
        and not P.ContainsAny(normalized, P.RootPhrases[629])
    then
        local setting
        local value
        if P.ContainsAny(normalized, P.RootPhrases[630]) then
            setting = A.Registry and A.Registry:GetSetting("boss.bossLayoutMode")
            value = setting and P.EnumValueForText and P.EnumValueForText(setting, normalized) or nil
        else
            setting = A.Registry and A.Registry:GetSetting("boss.spacing")
            value = P.FirstNumber(normalized)
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
    if P.ContainsAny(normalized, P.RootPhrases[631])
        and P.ContainsAny(normalized, P.RootPhrases[632])
        and P.ContainsAny(normalized, P.RootPhrases[633])
        and not normalized:find("icon", 1, true)
    then
        local castbarUnits = P.DetectUnits(normalized)
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
            local amount = P.FirstNumber(normalized) or 10
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
    if P.ContainsAny(normalized, P.RootPhrases[634])
        and P.ContainsAny(normalized, P.RootPhrases[635])
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
    if P.ContainsAny(normalized, P.RootPhrases[636])
        and P.ContainsAny(normalized, P.RootPhrases[637])
        and not P.ContainsAny(normalized, P.RootPhrases[638])
    then
        local key
        local value
        if P.ContainsAny(normalized, P.RootPhrases[639]) then
            key = "runtime.focusKickPreview"
            value = P.DetectBoolean(normalized)
            if value == nil then value = true end
        elseif P.ContainsAny(normalized, P.RootPhrases[640]) then
            key = "general.focusKickIconWidth"
            value = P.FirstNumber(normalized)
        elseif P.ContainsAny(normalized, P.RootPhrases[641]) then
            key = "general.focusKickIconHeight"
            value = P.FirstNumber(normalized)
        elseif P.ContainsAny(normalized, P.RootPhrases[642]) then
            key = "general.focusKickTextSize"
            value = P.FirstNumber(normalized)
        elseif P.ContainsAny(normalized, P.RootPhrases[643]) then
            key = "general.focusKickIconOffsetX"
            value = P.FirstNumber(normalized)
        elseif P.ContainsAny(normalized, P.RootPhrases[644]) then
            key = "general.focusKickIconOffsetY"
            value = P.FirstNumber(normalized)
        else
            key = "general.enableFocusKickIcon"
            value = P.DetectBoolean(normalized)
            if value == nil then value = true end
        end
        local setting = key and A.Registry and A.Registry:GetSetting(key)
        local relativeDelta = setting and setting.type == "number" and P.RelativeNumberDeltaForText
            and P.RelativeNumberDeltaForText(setting, normalized, 1) or nil
        if relativeDelta ~= nil then value = nil end
        if setting and (value ~= nil or relativeDelta ~= nil) then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
                label = setting.label or "Focus Kick Tracker",
                summary = "Changes Focus Kick Tracker visibility, preview, size, or offset.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if P.ContainsAny(normalized, P.RootPhrases[645])
        and not P.ContainsAny(normalized, P.RootPhrases[646])
    then
        local key
        local value
        if P.ContainsAny(normalized, P.RootPhrases[647]) then
            key = "general.kickReadyAutoSize"
            value = P.DetectBoolean(normalized)
            if value == nil then value = true end
        elseif P.ContainsAny(normalized, P.RootPhrases[648]) then
            key = "general.kickReadyStyle"
        elseif P.ContainsAny(normalized, P.RootPhrases[649]) then
            key = "general.kickReadyAnchor"
        elseif P.ContainsAny(normalized, P.RootPhrases[650]) then
            key = "general.kickReadyOffsetX"
            value = P.FirstNumber(normalized)
        elseif P.ContainsAny(normalized, P.RootPhrases[651]) then
            key = "general.kickReadyOffsetY"
            value = P.FirstNumber(normalized)
        elseif P.ContainsAny(normalized, P.RootPhrases[652]) then
            key = "general.kickReadySize"
            value = P.FirstNumber(normalized)
        elseif P.ContainsAny(normalized, P.RootPhrases[653]) then
            key = "general.kickReadyShowTarget"
        elseif P.ContainsAny(normalized, P.RootPhrases[654]) then
            key = "general.kickReadyShowFocus"
        elseif P.ContainsAny(normalized, P.RootPhrases[655]) then
            key = "general.kickReadyShowBoss"
        end
        local setting = key and A.Registry and A.Registry:GetSetting(key)
        if setting and value == nil then
            if setting.type == "enum" then
                value = P.EnumValueForText and P.EnumValueForText(setting, normalized) or nil
            elseif setting.type == "boolean" then
                value = P.DetectBoolean(normalized)
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
    if P.ContainsAny(normalized, P.RootPhrases[656])
        and P.ContainsAny(normalized, P.RootPhrases[657])
        and not P.ContainsAny(normalized, P.RootPhrases[658])
        and not (P.ContainsAny(normalized, P.RootPhrases[659])
            and P.ContainsAny(normalized, P.RootPhrases[660]))
    then
        local key
        local value
        if P.ContainsAny(normalized, P.RootPhrases[661]) then
            key = "general.castbarShakeStrength"
            value = P.FirstNumber(normalized)
        elseif P.ContainsAny(normalized, P.RootPhrases[662]) then
            key = "general.castbarInterruptShake"
            value = P.DetectBoolean(normalized)
            if value == nil then value = true end
        elseif P.ContainsAny(normalized, P.RootPhrases[663]) then
            key = "general.castbarUnifiedDirection"
            value = P.DetectBoolean(normalized)
            if value == nil then value = true end
        elseif P.ContainsAny(normalized, P.RootPhrases[664]) then
            key = "general.castbarOpositeDirectionTarget"
            value = P.DetectBoolean(normalized)
            if value == nil then
                value = not P.ContainsAny(normalized, P.RootPhrases[665])
            end
        elseif P.ContainsAny(normalized, P.RootPhrases[666]) then
            key = "general.castbarFillDirection"
            local setting = A.Registry and A.Registry:GetSetting(key)
            value = setting and P.EnumValueForText and P.EnumValueForText(setting, normalized) or nil
        elseif P.ContainsAny(normalized, P.RootPhrases[667]) then
            key = "general.castbarShowChannelTicks"
            value = P.DetectBoolean(normalized)
            if value == nil then value = true end
        elseif P.ContainsAny(normalized, P.RootPhrases[668]) then
            key = "general.castbarBackgroundTexture"
            value = P.RawAfterLastConnector and P.RawAfterLastConnector(raw, { " to ", " as ", " = " }) or nil
        elseif P.ContainsAny(normalized, P.RootPhrases[669]) then
            key = "general.castbarTexture"
            value = P.RawAfterLastConnector and P.RawAfterLastConnector(raw, { " to ", " as ", " = " }) or nil
        elseif P.ContainsAny(normalized, P.RootPhrases[670]) then
            key = "general.castbarOutlineThickness"
            value = P.FirstNumber(normalized)
        elseif P.ContainsAny(normalized, P.RootPhrases[671]) then
            key = "general.castbarShowGlow"
            value = P.DetectBoolean(normalized)
            if value == nil then value = true end
        elseif P.ContainsAny(normalized, P.RootPhrases[672]) then
            key = "general.castbarShowLatency"
            value = P.DetectBoolean(normalized)
            if value == nil then value = true end
        elseif P.ContainsAny(normalized, P.RootPhrases[673]) then
            key = "general.castbarSparkOverflow"
            value = P.DetectBoolean(normalized)
            if value == nil then value = true end
        elseif P.ContainsAny(normalized, P.RootPhrases[674]) then
            key = "general.castbarShowSpark"
            value = P.DetectBoolean(normalized)
            if value == nil then value = true end
        elseif P.ContainsAny(normalized, P.RootPhrases[675]) then
            key = "general.empowerStageBlinkTime"
            value = P.FirstNumber(normalized)
        elseif P.ContainsAny(normalized, P.RootPhrases[676]) then
            key = "general.empowerColorStages"
            value = P.DetectBoolean(normalized)
            if value == nil then value = true end
        elseif P.ContainsAny(normalized, P.RootPhrases[677]) then
            key = "general.empowerStageBlink"
            value = P.DetectBoolean(normalized)
            if value == nil then value = true end
        elseif P.ContainsAny(normalized, P.RootPhrases[678]) then
            key = "general.castbarSpellNameShortening"
            value = P.DetectBoolean(normalized)
            if value == nil then value = true end
        elseif P.ContainsAny(normalized, P.RootPhrases[679]) then
            key = "general.castbarSpellNameMaxLen"
            value = P.FirstNumber(normalized)
        elseif P.ContainsAny(normalized, P.RootPhrases[680]) then
            key = "general.castbarSpellNameReservedSpace"
            value = P.FirstNumber(normalized)
        end
        local setting = key and A.Registry and A.Registry:GetSetting(key)
        local relativeDelta = setting and setting.type == "number" and P.RelativeNumberDeltaForText
            and P.RelativeNumberDeltaForText(setting, normalized, 1) or nil
        if relativeDelta ~= nil then value = nil end
        if setting and (value ~= nil or relativeDelta ~= nil) then
            return {
                kind = "changes",
                changes = { { setting = setting, value = value, relativeDelta = relativeDelta } },
                label = setting.label or "Cast Bar Behavior",
                summary = "Changes a global Cast Bar behavior option.",
                raw = raw,
                normalized = normalized,
            }
        end
    end
    if P.ContainsAny(normalized, P.RootPhrases[681])
        and P.ContainsAny(normalized, P.RootPhrases[682])
        and not P.DetectUnits(normalized)[1]
        and not P.ContainsAny(normalized, P.RootPhrases[683])
    then
        local key
        if P.ContainsAny(normalized, P.RootPhrases[684]) then
            key = "general.castbarSpellNameFontSize"
        elseif P.ContainsAny(normalized, P.RootPhrases[685]) then
            key = "general.castbarTimeFontSize"
        elseif P.ContainsAny(normalized, P.RootPhrases[686]) then
            key = "general.castbarIconSize"
        elseif P.ContainsAny(normalized, P.RootPhrases[687]) then
            key = "general.castbarIconOffsetX"
        elseif P.ContainsAny(normalized, P.RootPhrases[688]) then
            key = "general.castbarIconOffsetY"
        end
        local setting = key and A.Registry and A.Registry:GetSetting(key)
        local value = setting and P.FirstNumber(normalized) or nil
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
    if P.ContainsAny(normalized, P.RootPhrases[689])
        and P.ContainsAny(normalized, P.RootPhrases[690])
        and not P.ContainsAny(normalized, P.RootPhrases[691])
    then
        local attr
        if P.ContainsAny(normalized, P.RootPhrases[692]) then
            attr = "border"
        elseif P.ContainsAny(normalized, P.RootPhrases[693]) then
            attr = "spacing"
        elseif P.ContainsAny(normalized, P.RootPhrases[694]) then
            attr = "position"
        elseif P.ContainsAny(normalized, P.RootPhrases[695]) then
            attr = "x"
        elseif P.ContainsAny(normalized, P.RootPhrases[696]) then
            attr = "y"
        elseif P.ContainsAny(normalized, P.RootPhrases[697]) then
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

        local units = P.DetectUnits(normalized)
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
                        value = P.FirstNumber(normalized)
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
    if P.ContainsAny(normalized, P.RootPhrases[698])
        and P.ContainsAny(normalized, P.RootPhrases[699])
        and not P.ContainsAny(normalized, P.RootPhrases[700])
    then
        local attr
        if P.ContainsAny(normalized, P.RootPhrases[701]) then
            attr = "timeFormat"
        elseif P.ContainsAny(normalized, P.RootPhrases[702]) then
            attr = "timePosition"
        elseif P.ContainsAny(normalized, P.RootPhrases[703]) then
            attr = "timeX"
        elseif P.ContainsAny(normalized, P.RootPhrases[704]) then
            attr = "timeY"
        elseif P.ContainsAny(normalized, P.RootPhrases[705]) then
            attr = "timeFontSize"
        elseif P.ContainsAny(normalized, P.RootPhrases[706]) then
            attr = "spellTruncate"
        elseif P.ContainsAny(normalized, P.RootPhrases[707]) then
            attr = "spellMaxWidth"
        elseif P.ContainsAny(normalized, P.RootPhrases[708]) then
            attr = "spellFontSize"
        -- SpellNameAlign is retired: SpellNamePosition owns anchor and justify.
        -- Keep alignment wording non-executable instead of targeting legacy DB.
        elseif P.ContainsAny(normalized, P.RootPhrases[710]) then
            attr = "spellPosition"
        elseif P.ContainsAny(normalized, P.RootPhrases[711]) then
            attr = "textX"
        elseif P.ContainsAny(normalized, P.RootPhrases[712]) then
            attr = "textY"
        end

        local keyMap = {
            player = {
                spellPosition = "general.castbarPlayerSpellNamePosition",
                textX = "general.castbarPlayerTextOffsetX",
                textY = "general.castbarPlayerTextOffsetY",
                -- Retired SpellNameAlign intentionally has no executable route.
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
                -- Retired SpellNameAlign intentionally has no executable route.
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
                -- Retired SpellNameAlign intentionally has no executable route.
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
                -- Retired SpellNameAlign intentionally has no executable route.
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

        local units = P.DetectUnits(normalized)
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
                        value = P.FirstNumber(normalized)
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
    if P.ContainsAny(normalized, P.RootPhrases[713])
        and P.ContainsAny(normalized, P.RootPhrases[714])
        and not P.ContainsAny(normalized, P.RootPhrases[715])
    then
        local attr
        if P.ContainsAny(normalized, P.RootPhrases[716]) then
            attr = "time"
        elseif P.ContainsAny(normalized, P.RootPhrases[717]) then
            attr = "icon"
        elseif P.ContainsAny(normalized, P.RootPhrases[718]) then
            attr = "text"
        end
        local value = P.DetectBoolean(normalized)
        local units = P.DetectUnits(normalized)
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
    if P.ContainsAny(normalized, P.RootPhrases[719])
        and P.ContainsAny(normalized, P.RootPhrases[720])
        and not P.ContainsAny(normalized, P.RootPhrases[721])
    then
        local axis
        if P.ContainsAny(normalized, P.RootPhrases[722]) then
            axis = "w"
        elseif P.ContainsAny(normalized, P.RootPhrases[723]) then
            axis = "h"
        end
        local value = P.FirstNumber(normalized)
        local units = P.DetectUnits(normalized)
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
    if P.ContainsAny(normalized, P.RootPhrases[724])
        and P.ContainsAny(normalized, P.RootPhrases[725])
        and not P.ContainsAny(normalized, P.RootPhrases[726])
    then
        local axis
        if P.ContainsAny(normalized, P.RootPhrases[727]) then
            axis = "x"
        elseif P.ContainsAny(normalized, P.RootPhrases[728]) then
            axis = "y"
        end
        local value = P.FirstNumber(normalized)
        local units = P.DetectUnits(normalized)
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
    if P.ContainsAny(normalized, P.RootPhrases[729])
        and not P.ContainsAny(normalized, P.RootPhrases[730])
    then
        local value = P.DetectBoolean(normalized)
        if value ~= nil then
            local units = P.DetectUnits(normalized)
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
    if P.ContainsAny(normalized, P.RootPhrases[731]) and not P.ContainsAny(normalized, P.RootPhrases[732]) then
        local actionKey
        local args = {}
        local label
        local summary
        local confirmRequired = false
        if P.ContainsAny(normalized, P.RootPhrases[735]) then
            actionKey = "open_recovery_tools"
            label = "Open recovery tools"
            summary = "Opens the Dashboard recovery area."
        elseif P.ContainsAny(normalized, P.RootPhrases[736]) then
            actionKey = "set_dashboard_panel"
            if P.ContainsAny(normalized, P.RootPhrases[737]) then
                args.open = false
                args.panel = "all"
            elseif P.ContainsAny(normalized, P.RootPhrases[738]) then
                args.open = nil
            else
                args.open = true
            end
            label = "Set Dashboard panel"
            summary = "Asks which Dashboard panel to open, such as recovery tools, scaling tools, or changelog."
        elseif P.ContainsAny(normalized, P.RootPhrases[739]) then
            actionKey = "set_nav_search_intro"
            if P.ContainsAny(normalized, P.RootPhrases[740]) then
                args.command = "seen"
            elseif P.ContainsAny(normalized, P.RootPhrases[741]) then
                args.command = "reset"
            else
                args.command = "show"
            end
            label = "Set search intro"
            summary = "Shows or hides the menu search intro."
        elseif P.ContainsAny(normalized, P.RootPhrases[742]) then
            actionKey = "set_nav_section"
            if P.ContainsAny(normalized, P.RootPhrases[743]) then
                args.section = "groupframes"
                label = "Group Frames"
            elseif P.ContainsAny(normalized, P.RootPhrases[744]) then
                args.section = "unitframes"
                label = "Frames"
            elseif P.ContainsAny(normalized, P.RootPhrases[745]) then
                args.section = "globalstyle"
                label = "Appearance"
            elseif P.ContainsAny(normalized, P.RootPhrases[746]) then
                args.section = "modules"
                label = "Advanced"
            elseif P.ContainsAny(normalized, P.RootPhrases[747]) then
                args.section = "auras"
                label = "Auras"
            end
            if P.ContainsAny(normalized, P.RootPhrases[748]) then
                args.open = false
            elseif P.ContainsAny(normalized, P.RootPhrases[749]) then
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
        elseif P.ContainsAny(normalized, P.RootPhrases[750]) then
            args.panel = "scaling"
            if P.ContainsAny(normalized, P.RootPhrases[737]) or P.ContainsAny(normalized, P.RootPhrases[738]) then
                actionKey = "set_dashboard_panel"
                args.open = P.ContainsAny(normalized, P.RootPhrases[737]) and false or nil
                label = args.open == false and "Close scaling tools" or "Toggle scaling tools"
                summary = "Changes whether the Dashboard scaling area is open."
            else
                actionKey = "open_dashboard_panel"
                label = "Open scaling tools"
                summary = "Opens the Dashboard scaling area."
            end
        elseif P.ContainsAny(normalized, P.RootPhrases[751]) then
            args.panel = "changelog"
            if P.ContainsAny(normalized, P.RootPhrases[737]) or P.ContainsAny(normalized, P.RootPhrases[738]) then
                actionKey = "set_dashboard_panel"
                args.open = P.ContainsAny(normalized, P.RootPhrases[737]) and false or nil
                label = args.open == false and "Close changelog" or "Toggle changelog"
                summary = "Changes whether the Dashboard changelog is open."
            else
                actionKey = "open_dashboard_panel"
                label = "Open changelog"
                summary = "Opens the Dashboard changelog."
            end
        elseif P.ContainsAny(normalized, P.RootPhrases[752]) then
            if P.ContainsAny(normalized, P.RootPhrases[753]) then
                actionKey = "assistant.diagnostic.editMode.status"
                if P.ContainsAny(normalized, P.RootPhrases[754]) then args.reason = "why_exit" end
                label = "Show MSUF Edit Mode status"
            elseif P.ContainsAny(normalized, P.RootPhrases[755]) then
                actionKey = "assistant.action.editMode.cancel"
                confirmRequired = true
                label = "Cancel MSUF Edit Mode"
            elseif P.ContainsAny(normalized, P.RootPhrases[756]) then
                actionKey = "assistant.action.editMode.toggle"
                label = "Toggle MSUF Edit Mode"
            elseif P.ContainsAny(normalized, P.RootPhrases[757]) then
                actionKey = "assistant.action.editMode.exit"
                label = "Exit MSUF Edit Mode"
            elseif P.ContainsAny(normalized, P.RootPhrases[758]) then
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
    if P.ContainsAny(normalized, P.RootPhrases[760])
        and P.ContainsAny(normalized, P.RootPhrases[761])
        and not P.ContainsAny(normalized, P.RootPhrases[762])
    then
        local earlyCopyParsed = CopyRequest(normalized)
        if earlyCopyParsed then
            earlyCopyParsed.raw = raw
            earlyCopyParsed.normalized = normalized
            return earlyCopyParsed
        end
    end
    if P.ContainsAny(normalized, P.RootPhrases[763]) then
        local earlyMenuWindowParsed = P.ParseMenuWindowAction and P.ParseMenuWindowAction(normalized)
        if earlyMenuWindowParsed then
            earlyMenuWindowParsed.raw = raw
            earlyMenuWindowParsed.normalized = normalized
            return earlyMenuWindowParsed
        end
    end
    if P.ContainsAny(normalized, P.RootPhrases[764]) and not P.ContainsAny(normalized, P.RootPhrases[765]) then
        local earlyOpenParsed = P.ParseOpen and P.ParseOpen(normalized, raw)
        if earlyOpenParsed then
            earlyOpenParsed.raw = raw
            earlyOpenParsed.normalized = normalized
            return earlyOpenParsed
        end
    end
    if normalized == "help" or normalized == "hilfe" or P.ContainsAny(normalized, P.RootPhrases[766]) then
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
    if P.ContainsAny(normalized, P.RootPhrases[767]) then
        local earlyScopedHelpParsed = P.ParseScopedHelp and P.ParseScopedHelp(normalized)
        if earlyScopedHelpParsed then
            earlyScopedHelpParsed.raw = raw
            earlyScopedHelpParsed.normalized = normalized
            return earlyScopedHelpParsed
        end
    end
    if P.ContainsAny(normalized, P.RootPhrases[768]) then
        local earlySupportParsed = P.ParseSupportWorkflow and P.ParseSupportWorkflow(normalized, raw)
        if earlySupportParsed then
            earlySupportParsed.raw = raw
            earlySupportParsed.normalized = normalized
            return earlySupportParsed
        end
    end
    if P.ContainsAny(normalized, P.RootPhrases[769]) then
        local earlyGuidedSetupParsed = (P.ParseGuidedSetupFollowup and P.ParseGuidedSetupFollowup(normalized, ctx))
            or (P.ParseGuidedSetup and P.ParseGuidedSetup(normalized))
        if earlyGuidedSetupParsed then
            earlyGuidedSetupParsed.raw = raw
            earlyGuidedSetupParsed.normalized = normalized
            return earlyGuidedSetupParsed
        end
    end
    if P.ContainsAny(normalized, P.RootPhrases[770]) then
        local diagnosticParsed = P.ParseDiagnostic and P.ParseDiagnostic(normalized)
        if diagnosticParsed then
            diagnosticParsed.raw = raw
            diagnosticParsed.normalized = normalized
            return diagnosticParsed
        end
        local supportWorkflowParsed = P.ParseSupportWorkflow and P.ParseSupportWorkflow(normalized, raw)
        if supportWorkflowParsed then
            supportWorkflowParsed.raw = raw
            supportWorkflowParsed.normalized = normalized
            return supportWorkflowParsed
        end
        local actionKey
        local args = {}
        local label
        local summary
        local confirmRequired = false
        if P.ContainsAny(normalized, P.RootPhrases[771]) then
            actionKey = "assistant_nomatch_clear"
            label = "Clear Assistant learning phrases"
            summary = "Clears stored Assistant learning/no-match phrases."
            confirmRequired = true
        elseif P.ContainsAny(normalized, P.RootPhrases[772]) then
            actionKey = "assistant_nomatch_worklist"
            if P.ContainsAny(normalized, P.RootPhrases[773]) then args.owner = "action-parser" end
            label = "Show Assistant learning list"
            summary = "Shows phrases that still need better Assistant answers."
        elseif P.ContainsAny(normalized, P.RootPhrases[774]) then
            actionKey = "assistant_nomatch_telemetry"
            label = "Show Assistant phrases to improve"
            summary = "Shows stored phrases that still need better Assistant answers."
        elseif P.ContainsAny(normalized, P.RootPhrases[775])
            -- ContainsAny matches "msuf status" anywhere, so "set msuf status
            -- afk text offset x to 0" was answered with the Assistant overview
            -- and the control was never touched. A status report never carries
            -- a value, so a number or a "to <value>" tail means this request is
            -- about a setting that merely contains the words.
            and not tostring(normalized or ""):find("%d")
            and not tostring(normalized or ""):find("%sto%s")
        then
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
        } or (P.ParseDiagnostic and P.ParseDiagnostic(normalized))
        if earlyDiagnosticParsed then
            earlyDiagnosticParsed.raw = raw
            earlyDiagnosticParsed.normalized = normalized
            return earlyDiagnosticParsed
        end
    end
    if P.ContainsAny(normalized, P.RootPhrases[776]) then
        local auraActionParsed = P.ParseRegistryActionAliasShortcut and P.ParseRegistryActionAliasShortcut(normalized, raw)
        if auraActionParsed then
            auraActionParsed.raw = raw
            auraActionParsed.normalized = normalized
            return auraActionParsed
        end
    end
    local actionFirstParsed
    if P.ContainsAny(normalized, P.RootPhrases[777]) then
        actionFirstParsed = P.ParseGameplayAction(normalized, raw)
    end
    actionFirstParsed = actionFirstParsed or P.ParsePresetWorkflow(normalized) or P.ParseGlobalBarsAction(normalized)
    if not actionFirstParsed and P.ContainsAny(normalized, P.RootPhrases[778]) then
        actionFirstParsed = P.ParseFontColorAction(normalized, raw)
    end
    if not actionFirstParsed
        and P.ContainsAny(normalized, P.RootPhrases[779])
        and P.ContainsAny(normalized, P.RootPhrases[780])
    then
        actionFirstParsed = P.ParseColorAction(normalized)
    end
    actionFirstParsed = actionFirstParsed
        or P.ParseScopedOverrideReset(normalized)
        or (not P.ContainsAny(normalized, P.RootPhrases[781]) and P.ParseCastbarPreviewAction(normalized))
        or P.ParseGroupSpellIndicatorAction(normalized, raw)
        or P.ParseGroupCornerIndicatorReset(normalized)
        or P.ParseGroupStatusPreview(normalized)
        or P.ParseUnitStatusPreview(normalized, ctx)
        or (P.ParseGroupStatusIconDetail and P.ParseGroupStatusIconDetail(normalized))
        or (P.ParseBarGradientRegistryShortcut and P.ParseBarGradientRegistryShortcut(normalized))
        or (P.ParsePowerBarGradientRegistryShortcut and P.ParsePowerBarGradientRegistryShortcut(normalized))
        or (P.ParseDetachedPowerBarMoveShortcut and P.ParseDetachedPowerBarMoveShortcut(normalized))
    if not actionFirstParsed
        and P.ContainsAny(normalized, P.RootPhrases[782])
        and not P.ContainsAny(normalized, P.RootPhrases[783])
    then
        actionFirstParsed = P.ParseGroupStatusIconReset(normalized)
            or P.ParseUnitStatusIndicatorReset(normalized, ctx)
    end
    if not actionFirstParsed
        and P.ContainsAny(normalized, P.RootPhrases[784])
        and P.ContainsAny(normalized, P.RootPhrases[785])
    then
        actionFirstParsed = P.ParseReset(normalized)
    end
    if not actionFirstParsed
        and P.ContainsAny(normalized, P.RootPhrases[786])
        and P.ContainsAny(normalized, P.RootPhrases[787])
        and not P.ContainsAny(normalized, P.RootPhrases[788])
    then
        actionFirstParsed = P.ParseReset(normalized)
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
        or (A._ParseTextSlotValueMoveShortcut and A._ParseTextSlotValueMoveShortcut(normalized))
        or (A._ParseTextSlotOffsetShortcut and A._ParseTextSlotOffsetShortcut(normalized))
        or (A._ParseTextAreaOffsetShortcut and A._ParseTextAreaOffsetShortcut(normalized))
        or (A._ParseTextFontSizeShortcut and A._ParseTextFontSizeShortcut(normalized))
    if earlyTextDetailParsed then
        earlyTextDetailParsed.raw = raw
        earlyTextDetailParsed.normalized = normalized
        return earlyTextDetailParsed
    end
    local earlyCustomAnchorSetParsed = P.ParseCustomAnchorSet(normalized, raw)
    if earlyCustomAnchorSetParsed then
        earlyCustomAnchorSetParsed.raw = raw
        earlyCustomAnchorSetParsed.normalized = normalized
        return earlyCustomAnchorSetParsed
    end
    local earlyPortraitDetailParsed = P.ParsePortraitDetailShortcut(normalized)
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
    local earlyUnitStatusDetailParsed = (P.ParseUnitStatusSymbolRegistryShortcut and P.ParseUnitStatusSymbolRegistryShortcut(normalized))
        or (P.ParseStatusIconTestModeRegistryShortcut and P.ParseStatusIconTestModeRegistryShortcut(normalized))
        or (P.ParseUnitStatusIndicatorDetail and P.ParseUnitStatusIndicatorDetail(normalized))
    if earlyUnitStatusDetailParsed then
        earlyUnitStatusDetailParsed.raw = raw
        earlyUnitStatusDetailParsed.normalized = normalized
        return earlyUnitStatusDetailParsed
    end
    local earlyUnitLoadConditionParsed = P.ParseUnitLoadConditionShortcut and P.ParseUnitLoadConditionShortcut(normalized)
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
    local earlyPairwiseSpacingParsed = P.ParsePairwiseFrameSpacingShortcut
        and P.ParsePairwiseFrameSpacingShortcut(normalized)
    if earlyPairwiseSpacingParsed then
        earlyPairwiseSpacingParsed.raw = raw
        earlyPairwiseSpacingParsed.normalized = normalized
        return earlyPairwiseSpacingParsed
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
        or (P.ParseUnitOpacityShortcut and P.ParseUnitOpacityShortcut(normalized))
    if earlyOpacityParsed then
        earlyOpacityParsed.raw = raw
        earlyOpacityParsed.normalized = normalized
        return earlyOpacityParsed
    end
    if LooksLikeAbsorbBarCommand(normalized) then
        local earlyAbsorbBarParsed = P.ParseAbsorbBarShortcut and P.ParseAbsorbBarShortcut(normalized, raw)
        if earlyAbsorbBarParsed then
            earlyAbsorbBarParsed.raw = raw
            earlyAbsorbBarParsed.normalized = normalized
            return earlyAbsorbBarParsed
        end
    end
    if LooksLikeBarBorderEnumCommand(normalized) then
        local earlyBarBorderEnumParsed = P.ParseBarBorderEnumShortcut and P.ParseBarBorderEnumShortcut(normalized)
        if earlyBarBorderEnumParsed then
            earlyBarBorderEnumParsed.raw = raw
            earlyBarBorderEnumParsed.normalized = normalized
            return earlyBarBorderEnumParsed
        end
    end
    local earlyAmbiguousGroupOutlineParsed = P.ParseAmbiguousGroupOutlineBorderShortcut and P.ParseAmbiguousGroupOutlineBorderShortcut(normalized)
    if earlyAmbiguousGroupOutlineParsed then
        earlyAmbiguousGroupOutlineParsed.raw = raw
        earlyAmbiguousGroupOutlineParsed.normalized = normalized
        return earlyAmbiguousGroupOutlineParsed
    end
    if LooksLikeBarOutlineHighlightCommand(normalized) then
        local earlyBarOutlineHighlightParsed = P.ParseBarOutlineHighlightShortcut and P.ParseBarOutlineHighlightShortcut(normalized)
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
    if P.ContainsAny(normalized, P.RootPhrases[789]) then
        local directColorParsed
        if P.ContainsAny(normalized, P.RootPhrases[790]) then
            directColorParsed = P.ParseScopedFontTextColorShortcut(normalized)
        end
        if P.ContainsAny(normalized, P.RootPhrases[791]) then
            directColorParsed = A._ParseClassPowerColorShortcut and A._ParseClassPowerColorShortcut(normalized, raw)
        end
        if not directColorParsed and P.ContainsAny(normalized, P.RootPhrases[792]) then
            directColorParsed = A._ParsePowerColorShortcut and A._ParsePowerColorShortcut(normalized, raw)
        end
        if directColorParsed then
            directColorParsed.raw = raw
            directColorParsed.normalized = normalized
            return directColorParsed
        end
    end
    if P.ContainsAny(normalized, P.RootPhrases[793])
        and P.ContainsAny(normalized, P.RootPhrases[794])
    then
        local detachedPowerDetail = P.ParseDetachedPowerBarRegistryShortcut
            and P.ParseDetachedPowerBarRegistryShortcut(normalized, raw)
        if detachedPowerDetail then
            detachedPowerDetail.raw = raw
            detachedPowerDetail.normalized = normalized
            return detachedPowerDetail
        end
    end
    if P.ContainsAny(normalized, P.RootPhrases[795]) then
        local groupNumberParsed = P.ParseGroupNumberRegistryShortcut and P.ParseGroupNumberRegistryShortcut(normalized)
        if groupNumberParsed then
            groupNumberParsed.raw = raw
            groupNumberParsed.normalized = normalized
            return groupNumberParsed
        end
    end
    if P.ContainsAny(normalized, P.RootPhrases[796]) and P.ContainsAny(normalized, P.RootPhrases[797]) then
        local castbarColorParsed = P.ParseCastbarColorShortcut and P.ParseCastbarColorShortcut(normalized, raw)
        if castbarColorParsed then
            castbarColorParsed.raw = raw
            castbarColorParsed.normalized = normalized
            return castbarColorParsed
        end
    end
    if P.ContainsAny(normalized, P.RootPhrases[798])
        and P.ContainsAny(normalized, P.RootPhrases[799])
        and P.ContainsAny(normalized, P.RootPhrases[800])
    then
        local castbarMoveParsed = P.ParseGenericOffsetMove and P.ParseGenericOffsetMove(normalized)
        if castbarMoveParsed then
            castbarMoveParsed.raw = raw
            castbarMoveParsed.normalized = normalized
            return castbarMoveParsed
        end
    end
    if P.ContainsAny(normalized, P.RootPhrases[801]) and not P.ContainsAny(normalized, P.RootPhrases[802]) then
        local statusTextParsed = A._ParseGlobalStatusTextStateShortcut and A._ParseGlobalStatusTextStateShortcut(normalized)
            or (P.ParseUnitStatusIconStyle and P.ParseUnitStatusIconStyle(normalized))
            or (P.ParseUnitStatusIndicatorDetail and P.ParseUnitStatusIndicatorDetail(normalized))
        if statusTextParsed then
            statusTextParsed.raw = raw
            statusTextParsed.normalized = normalized
            return statusTextParsed
        end
    end
    if P.ContainsAny(normalized, P.RootPhrases[803])
        and P.ContainsAny(normalized, P.RootPhrases[804])
    then
        local classPowerTextOffsetParsed = A._ParseClassPowerTextOffsetShortcut and A._ParseClassPowerTextOffsetShortcut(normalized)
        if classPowerTextOffsetParsed then
            classPowerTextOffsetParsed.raw = raw
            classPowerTextOffsetParsed.normalized = normalized
            return classPowerTextOffsetParsed
        end
    end
    if P.ContainsAny(normalized, P.RootPhrases[805]) and P.ContainsAny(normalized, P.RootPhrases[806]) then
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
    if P.ContainsAny(normalized, P.RootPhrases[807]) then
        local groupFrameParsed = P.ParseGroupPreserveRaidGroupsShortcut
            and P.ParseGroupPreserveRaidGroupsShortcut(normalized)
        if not groupFrameParsed and P.ContainsAny(normalized, P.RootPhrases[808]) then
            groupFrameParsed = P.ParseGroupAvailabilityIntent and P.ParseGroupAvailabilityIntent(normalized)
        end
        if groupFrameParsed then
            groupFrameParsed.raw = raw
            groupFrameParsed.normalized = normalized
            return groupFrameParsed
        end
    end
    if P.ContainsAny(normalized, P.RootPhrases[809]) then
        local unitRootParsed = A._ParseUnitRootVisibilityShortcut and A._ParseUnitRootVisibilityShortcut(normalized)
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
    local hasEditModeContext = P.ContainsAny(normalized, P.RootPhrases[810])
    if not hasEditModeContext and P.ContainsAny(normalized, P.RootPhrases[811]) then
        return { kind = "undo" }
    end
    if not hasEditModeContext and P.ContainsAny(normalized, P.RootPhrases[812]) then
        return { kind = "redo" }
    end
    local guidedSetupFollowup = P.ParseGuidedSetupFollowup(normalized, ctx)
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
