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

local function ParseDispelOverlayOpacityShortcut(normalized)
    if not ContainsAny(normalized, { "dispel overlay opacity", "dispel overlay alpha", "unitframe dispel overlay opacity", "unit frame dispel overlay opacity" }) then return nil end
    if ContainsAny(normalized, { "increase", "decrease", "raise", "lower", "more ", "less ", "relative", "by " }) then return nil end
    local value = FirstNumber(normalized)
    if value == nil then return nil end
    if value > 1 then value = value / 100 end

    local changes = {}
    local units = DetectUnits(normalized)
    local groups = DetectGroups(normalized)
    for i = 1, #units do
        local unit = tostring(units[i])
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
    if ContainsAny(normalized, { "manual", "manual width", "custom", "fixed" }) then return "manual" end
    if ContainsAny(normalized, { "unitframe", "unit frame", "follow unit frame", "auto unit frame", "own width" }) then return "unitframe" end
    if ContainsAny(normalized, { "essential", "essential cooldown", "essential cooldowns", "cooldown", "cooldowns", "cdm" }) then return "essential" end
    if ContainsAny(normalized, { "utility", "utility cooldown", "utility cooldowns" }) then return "utility" end
    return nil
end

local function ParseCastbarWidthModeShortcut(normalized)
    if not ContainsAny(normalized, { "castbar", "cast bar", "zauberleiste" }) then return nil end
    if not ContainsAny(normalized, {
        "width mode", "width source", "width behavior", "match width", "auto width",
        "breite modus", "breite quelle",
    }) then return nil end
    if ContainsAny(normalized, {
        "spell name", "spell text", "text width", "manual width", "truncate", "aura", "buff", "debuff",
        "focus kick", "kick icon", "interrupt icon",
    }) and not ContainsAny(normalized, { "width mode", "width source", "width behavior" }) then
        return nil
    end

    local value = CastbarWidthModeValue(normalized)
    if value == nil then return nil end

    local units = DetectUnits(normalized)
    if #units == 0 and ContainsAny(normalized, { "all castbars", "all cast bars", "every castbar", "every cast bar", "all unit castbars", "all unit cast bars" }) then
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
    if not ContainsAny(normalized, { "buff", "buffs", "debuff", "debuffs" }) then return nil end
    if ContainsAny(normalized, {
        "cooldown", "timer", "stack", "stack count", "text", "font", "filter", "blacklist",
        "anchor", "growth", "grow", "size", "spacing", "per row", "max", "count",
    }) then return nil end

    local lane
    if ContainsAny(normalized, { "buff", "buffs" }) then lane = "buff" end
    if ContainsAny(normalized, { "debuff", "debuffs" }) then
        if lane ~= nil then return nil end
        lane = "debuff"
    end
    if not lane then return nil end

    local axis
    if ContainsAny(normalized, { "x offset", "offset x", "horizontal offset", " x ", " x", "x " }) then
        axis = "x"
    elseif ContainsAny(normalized, { "y offset", "offset y", "vertical offset", " y ", " y", "y " }) then
        axis = "y"
    end
    if not axis then return nil end

    local value = FirstNumber(normalized)
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, {
        "all group", "all group aura", "all group auras", "all group buffs", "all group debuffs",
        "every group", "every group aura", "every group buff", "every group debuff",
    }) then
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
    if not ContainsAny(normalized, { "buff", "buffs", "debuff", "debuffs" }) then return nil end
    if not ContainsAny(normalized, { "cooldown", "timer", "stack", "stack count" }) then return nil end
    if ContainsAny(normalized, {
        "font", "size", "anchor", "filter", "blacklist", "growth", "grow", "text size",
        "cooldown size", "timer size", "stack size",
    }) then return nil end

    local lane
    if ContainsAny(normalized, { "buff", "buffs" }) then lane = "buff" end
    if ContainsAny(normalized, { "debuff", "debuffs" }) then
        if lane ~= nil then return nil end
        lane = "debuff"
    end
    if not lane then return nil end

    local prefix
    if ContainsAny(normalized, { "cooldown", "timer" }) then
        prefix = "cooldown"
    elseif ContainsAny(normalized, { "stack", "stack count" }) then
        prefix = "stack"
    end
    if not prefix then return nil end

    local axis
    if ContainsAny(normalized, { "x offset", "offset x", "horizontal offset", " x ", " x", "x " }) then
        axis = "X"
    elseif ContainsAny(normalized, { "y offset", "offset y", "vertical offset", " y ", " y", "y " }) then
        axis = "Y"
    end
    if not axis then return nil end

    local value = FirstNumber(normalized)
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, {
        "all group", "all group aura", "all group auras", "all group buffs", "all group debuffs",
        "every group", "every group aura", "every group buff", "every group debuff",
    }) then
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
    if not ContainsAny(normalized, { "buff", "buffs", "debuff", "debuffs" }) then return nil end
    if not ContainsAny(normalized, { "cooldown", "timer", "stack", "stack count" }) then return nil end
    if not ContainsAny(normalized, { "font", "font size", "text size", "size" }) then return nil end
    if ContainsAny(normalized, { "anchor", " x", "x ", "x offset", " y", "y ", "y offset", "offset", "filter", "blacklist" }) then return nil end

    local lane
    if ContainsAny(normalized, { "buff", "buffs" }) then lane = "buff" end
    if ContainsAny(normalized, { "debuff", "debuffs" }) then
        if lane ~= nil then return nil end
        lane = "debuff"
    end
    if not lane then return nil end

    local attr
    if ContainsAny(normalized, { "cooldown", "timer" }) then
        attr = "cooldownSize"
    elseif ContainsAny(normalized, { "stack", "stack count" }) then
        attr = "stackSize"
    end
    if not attr then return nil end

    local value = FirstNumber(normalized)
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, {
        "all group", "all group aura", "all group auras", "all group buffs", "all group debuffs",
        "every group", "every group aura", "every group buff", "every group debuff",
    }) then
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
    if not ContainsAny(normalized, { "buff", "buffs", "debuff", "debuffs" }) then return nil end
    if ContainsAny(normalized, {
        "font", "size", "anchor", "direction", "reverse", " x", "x ", "x offset", " y", "y ", "y offset",
        "offset", "filter", "blacklist", "darken", "darkens", "loss", "lost",
    }) then return nil end

    local attr
    if ContainsAny(normalized, { "cooldown text", "timer text" }) then
        attr = "showCooldown"
    elseif ContainsAny(normalized, { "stack count", "stacks", "stack text" }) then
        attr = "showStacks"
    elseif ContainsAny(normalized, { "cooldown swipe", "timer swipe" }) then
        attr = "showCooldownSwipe"
    end
    if not attr then return nil end

    local lane
    if ContainsAny(normalized, { "buff", "buffs" }) then lane = "buff" end
    if ContainsAny(normalized, { "debuff", "debuffs" }) then
        if lane ~= nil then return nil end
        lane = "debuff"
    end
    if not lane then return nil end

    local value = DetectBoolean(normalized)
    if value == nil and ContainsAny(normalized, { "show", "enable", "enabled", "turn on", "on" }) then value = true end
    if value == nil and ContainsAny(normalized, { "hide", "disable", "disabled", "turn off", "off" }) then value = false end
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, {
        "all group", "all group aura", "all group auras", "all group buffs", "all group debuffs",
        "every group", "every group aura", "every group buff", "every group debuff",
    }) then
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
    if not ContainsAny(normalized, { "cooldown", "swipe", "aura", "auras", "buff", "debuff" }) then return nil end
    if not ContainsAny(normalized, { "darken", "darkens", "darkened", "dim", "dims", "dunkelt" }) then return nil end
    if not ContainsAny(normalized, { "loss", "lost", "missing", "expire", "expired", "verlust" }) then return nil end
    if ContainsAny(normalized, { "color", "colour", "size", "font", "text", "anchor", "x offset", "y offset" }) then return nil end

    local value = DetectBoolean(normalized)
    if value == nil and ContainsAny(normalized, { "turn on", "enable", "enabled", "on", "darken", "darkens", "dim", "dims" }) then value = true end
    if value == nil and ContainsAny(normalized, { "turn off", "disable", "disabled", "off", "dont", "do not" }) then value = false end
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group", "all groups", "all group frames", "every group", "every group frame" }) then
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
    if not ContainsAny(normalized, { "alpha", "opacity", "transparency" }) then return nil end
    if ContainsAny(normalized, {
        "increase", "decrease", "raise", "lower", "more ", "less ", "more transparent", "less transparent",
        "more opaque", "less opaque", "relative", "by ",
    }) then return nil end
    if ContainsAny(normalized, {
        "text opacity", "text alpha", "font opacity", "font alpha", "aura", "auras", "buff", "debuff",
        "castbar", "cast bar", "absorb", "heal absorb", "range fade", "dispel", "overlay",
        "outline", "border",
        "portrait", "edit mode", "editmode",
    }) then return nil end

    local units = DetectUnits(normalized)
    if #units == 0 then return nil end
    local value = FirstNumber(normalized)
    if value == nil then return nil end
    if value > 1 then value = value / 100 end

    local powerOpacity = ContainsAny(normalized, {
        "power bar", "powerbar", "power opacity", "power alpha",
        "mana bar", "mana opacity", "mana alpha",
        "resource bar", "resource opacity", "resource alpha",
    })
    local backgroundOpacity = ContainsAny(normalized, {
        "background", "backdrop", "track", "hp track", "health track", "bg", "bar background",
    })
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
    if not ContainsAny(normalized, {
        "party", "raid", "mythic raid", "mythicraid", "group frame", "group frames",
        "gruppenframe", "gruppenframes",
    }) then
        return nil
    end
    if not ContainsAny(normalized, {
        "show player", "player in group", "show player in group", "show player when solo",
        "show solo", "show while solo", "show group while solo", "hide while solo",
        "client scene", "hide during client scene", "hide in client scene",
        "housing", "hide in housing", "hide during housing",
        "offline members", "offline in combat", "hide offline",
        "click casting", "clique",
        "group frames enabled", "frames enabled", "party frames", "raid frames",
        "mythic raid frames", "turn on group frames", "turn off group frames",
        "enable group frames", "disable group frames",
    }) then
        return nil
    end
    if ContainsAny(normalized, {
        "aura", "auras", "buff", "buffs", "debuff", "debuffs",
        "spell indicator", "spell indicators", "corner indicator", "corner indicators",
        "power bar", "power bars", "mana bar", "mana bars", "resource bar", "resource bars",
        "health bar", "hp bar", "health text", "hp text", "power text", "mana text",
        "castbar", "cast bar", "raid marker", "status icon", "status icons",
        "role icon", "ready check", "summon", "resurrection", "phase", "pvp",
        "texture", "gradient", "color", "colors", "colour", "colours",
        "opacity", "alpha", "font", "text size", "font size", "anchor", "offset",
        "delay", "after", "tint", "dead background", "background",
    }) then
        return nil
    end

    local attr
    local hideSemantic = false
    if ContainsAny(normalized, { "offline in combat", "hide offline in combat" }) then
        attr = "hideOfflineInCombat"
        hideSemantic = true
    elseif ContainsAny(normalized, { "offline members", "offline member", "offline players", "hide offline members", "hide offline" }) then
        attr = "hideOfflineEnabled"
        hideSemantic = true
    elseif ContainsAny(normalized, { "client scene", "hide during client scene", "hide in client scene" }) then
        attr = "hideInClientScene"
        hideSemantic = true
    elseif ContainsAny(normalized, { "housing", "hide in housing", "hide during housing" }) then
        attr = "hideInHousing"
        hideSemantic = true
    elseif ContainsAny(normalized, {
        "show player", "player in group", "show player in group",
        "show player when solo", "show player in group when solo",
    }) then
        attr = "showPlayer"
    elseif ContainsAny(normalized, {
        "show solo", "show while solo", "show group while solo", "show group frame while solo",
        "show group frames while solo", "hide while solo", "hide solo", "hide group frame while solo",
        "show party frame while solo", "show raid frame while solo", "show mythic raid frame while solo",
    }) then
        attr = "showSolo"
    elseif ContainsAny(normalized, { "click casting", "clique" }) then
        attr = "clickCastEnabled"
    elseif ContainsAny(normalized, {
        "group frames enabled", "frames enabled", "party frames", "raid frames", "mythic raid frames",
        "turn on group frames", "turn off group frames", "enable group frames", "disable group frames",
    }) then
        attr = "enabled"
    end
    if not attr then return nil end

    local fromToValue
    if ContainsAny(normalized, { "from off to on", "off to on", "from disabled to enabled", "disabled to enabled", "from hidden to shown", "hidden to shown" }) then
        fromToValue = true
    elseif ContainsAny(normalized, { "from on to off", "on to off", "from enabled to disabled", "enabled to disabled", "from shown to hidden", "shown to hidden" }) then
        fromToValue = false
    end

    local value
    if fromToValue ~= nil then
        value = fromToValue
    elseif hideSemantic then
        if ContainsAny(normalized, { "turn off", "disable", "disabled", "off", "false", "no", "dont hide", "do not hide", "never hide", "always show", "show", "display", "visible" }) then
            value = false
        elseif ContainsAny(normalized, { "turn on", "enable", "enabled", "on", "true", "yes", "hide", "hidden", "not show", "dont show", "do not show", "never show" }) then
            value = true
        end
        if value == nil then value = true end
    else
        if ContainsAny(normalized, { "turn off", "disable", "disabled", "off", "false", "no", "hide", "hidden", "not show", "dont show", "do not show", "never show" }) then
            value = false
        elseif ContainsAny(normalized, { "turn on", "enable", "enabled", "on", "true", "yes", "show", "display", "visible" }) then
            value = true
        end
        if value == nil and DetectBoolean then value = DetectBoolean(normalized) end
    end
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group", "all party and raid", "party and raid" }) then
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
        if ContainsAny(text, { "auto", "automatic", "default", "standard", "normal", "blizzard default", "blizzard standard" }) then
            return "AUTO"
        end
        if ContainsAny(text, { "show", "visible", "force", "force blizzard", "show blizzard", "anzeigen", "einblenden", "sichtbar", "erzwingen" }) then
            return "SHOW"
        end
        if ContainsAny(text, { "none", "hide all", "hide blizzard", "no blizzard", "off", "aus", "ausblenden", "verstecken", "keiner", "keine", "nichts" }) then
            return "NONE"
        end
        return nil
    end

    local value = valueIn(target)
    if value then return value end
    if ContainsAny(normalized, {
        "show blizzard group frames", "show blizzard party frames", "show blizzard raid frames",
        "force blizzard group frames", "force blizzard party frames", "force blizzard raid frames",
        "blizzard frames when disabled show", "default frames when disabled show",
    }) then
        return "SHOW"
    end
    if ContainsAny(normalized, {
        "hide blizzard group frames", "hide blizzard party frames", "hide blizzard raid frames",
        "no blizzard group frames", "no blizzard party frames", "no blizzard raid frames",
        "hide default group frames", "hide default party frames", "hide default raid frames",
    }) then
        return "NONE"
    end
    return valueIn(normalized)
end

local function ParseGroupBlizzardFallbackFastShortcut(normalized)
    if not ContainsAny(normalized, {
        "blizzard fallback", "fallback mode", "fallback modus", "disabled group frame behavior",
        "disabled group frame blizzard behavior", "when group frames are disabled",
        "if this switch is off", "blizzard group frames when disabled",
        "blizzard party frames when disabled", "blizzard raid frames when disabled",
        "blizzard mythic raid frames when disabled", "blizzard mythicraid frames when disabled",
        "default group frames when disabled", "standard group frames when disabled",
        "default party frames when disabled", "default raid frames when disabled",
        "standard party frames when disabled", "standard raid frames when disabled",
    }) then
        return nil
    end
    if ContainsAny(normalized, {
        "aura", "auras", "buff", "debuff", "spell indicator", "spell indicators",
        "power", "health", "hp", "text", "font", "color", "colour", "opacity", "alpha",
        "anchor", "offset", "scale", "scaling",
    }) then
        return nil
    end

    local value = GroupBlizzardFallbackValue(normalized)
    if not value then return nil end
    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group", "party and raid" }) then
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
    if not ContainsAny(normalized, { "offline", "hide offline" }) then return nil end
    if not ContainsAny(normalized, { "delay", "after", "seconds", "sec", "verzoegerung", "verzogerung" }) then return nil end
    if ContainsAny(normalized, {
        "tint", "dead background", "background", "color", "colour", "opacity", "alpha",
        "name", "text", "font", "aura", "buff", "debuff", "spell indicator", "spell indicators",
    }) then
        return nil
    end
    local value = FirstNumber(normalized)
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group", "party and raid" }) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local changes = {}
    local seen = {}
    for i = 1, #groups do
        local scope = tostring(groups[i])
        if (scope == "party" or scope == "raid" or scope == "mythicraid") and not seen[scope] then
            seen[scope] = true
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
    if not ContainsAny(normalized, {
        "reverse fill", "reverse health fill", "fill backwards", "backwards fill",
        "right to left fill", "fill right to left", "normal fill", "left to right fill",
    }) then
        return nil
    end
    if ContainsAny(normalized, {
        "text", "hp text", "health text", "power text", "mana text", "aura", "buff", "debuff",
        "castbar", "cast bar", "spell indicator", "spell indicators", "color", "colour",
    }) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group", "party and raid" }) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local value
    local boolValue = DetectBoolean(normalized)
    if ContainsAny(normalized, { "normal fill", "left to right fill", "fill left to right" }) then
        value = false
    elseif boolValue ~= nil then
        value = boolValue
    elseif ContainsAny(normalized, { "reverse", "backwards", "right to left", "fill right to left" }) then
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

local function GroupNameClipSideValue(normalized)
    local target = P.TargetAfterLastConnector and P.TargetAfterLastConnector(normalized) or nil
    local function valueIn(text)
        if not text or text == "" then return nil end
        if ContainsAny(text, { "left", "keep end", "endletters", "end letters", "from left", "truncate start", "remove start" }) then
            return "LEFT"
        end
        if ContainsAny(text, { "right", "keep start", "startletters", "start letters", "from right", "truncate end", "remove end" }) then
            return "RIGHT"
        end
        return nil
    end
    return valueIn(target) or valueIn(normalized)
end

local function ParseGroupNameTextFastShortcut(normalized)
    if not ContainsAny(normalized, { "name", "names", "group name", "group names", "namen", "ellipsis", "without dots", "truncate without dots" }) then return nil end
    local hideNameDeadOffline = ContainsAny(normalized, {
        "hide name on dead", "hide name when dead", "hide name on offline", "hide name when offline",
        "hide name on dead offline", "hide name on dead or offline", "hide name when dead or offline",
        "dead offline", "dead or offline",
    })
    if ContainsAny(normalized, {
        "health", "hp", "power", "mana", "castbar", "cast bar", "aura", "buff", "debuff",
        "spell indicator", "spell indicators", "raid marker", "status icon", "role icon",
        "anchor", "offset", " x", "x ", " y", "y ", "layer", "font size", "name size",
        "color", "colour",
    }) then
        return nil
    end

    local attr
    local value
    if hideNameDeadOffline then
        attr = "hideNameOnDeadOffline"
        if ContainsAny(normalized, {
            "turn off", "disable", "disabled", "off", "false", "show name", "show names",
            "dont hide", "do not hide", "never hide",
        }) then
            value = false
        elseif ContainsAny(normalized, {
            "turn on", "enable", "enabled", "on", "true", "hide name", "hide names",
            "hide name on dead", "hide name on offline", "dead offline", "dead or offline",
        }) then
            value = true
        end
        if value == nil then value = true end
    elseif ContainsAny(normalized, { "name max chars", "name max characters", "max chars", "max characters", "name length", "name laenge", "name länge" }) then
        attr = "nameMaxChars"
        value = FirstNumber(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, { "shorten group names", "shorten names", "name shortening" }) then
        attr = "nameShortenEnabled"
        value = DetectBoolean(normalized)
        if value == nil then value = not ContainsAny(normalized, { "turn off", "disable", "disabled", "off", "false", "no", "dont", "do not" }) end
    elseif ContainsAny(normalized, { "name truncation style", "truncation style", "name clip side" }) then
        attr = "nameClipSide"
        value = GroupNameClipSideValue(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, { "name no ellipsis", "no ellipsis", "truncate without dots", "without dots", "without ellipsis" }) then
        attr = "nameNoEllipsis"
        if ContainsAny(normalized, { "turn off", "disable", "disabled", "off", "false", "show dots", "use dots", "ellipsis on" }) then
            value = false
        elseif ContainsAny(normalized, { "turn on", "enable", "enabled", "on", "true", "hide dots", "remove dots", "without dots", "without ellipsis", "no ellipsis" }) then
            value = true
        end
        if value == nil then value = DetectBoolean(normalized) end
    end
    if not attr then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group", "party and raid" }) then
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
    if not ContainsAny(normalized, { "power bar", "power bars", "mana bar", "mana bars", "resource bar", "resource bars", "secondary bar", "secondary bars" }) then return nil end
    if ContainsAny(normalized, {
        "text", "font", "delimiter", "separator", " x", "x ", " y", "y ", "offset",
        "height", "smooth", "smooth fill", "tank", "healer", "dps", "damager",
        "role", "color", "colour", "gradient", "texture", "opacity", "alpha",
        "detached", "class power", "class resource", "player hp",
    }) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group", "party and raid" }) then
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
    if not ContainsAny(normalized, { "power", "power bar", "power bars", "mana", "resource" }) then return nil end
    if not ContainsAny(normalized, { "tank", "healer", "dps", "damager", "damage dealer" }) then return nil end
    if ContainsAny(normalized, {
        "text", "font", "delimiter", "separator", "offset", "height", "smooth",
        "color", "colour", "gradient", "texture", "opacity", "alpha",
        "detached", "class power", "class resource",
    }) then
        return nil
    end

    local attr
    if ContainsAny(normalized, { "tank", "tanks" }) then
        attr = "powerShowTank"
    elseif ContainsAny(normalized, { "healer", "healers", "heal" }) then
        attr = "powerShowHealer"
    elseif ContainsAny(normalized, { "dps", "damager", "damagers", "damage dealer", "damage dealers" }) then
        attr = "powerShowDamager"
    end
    if not attr then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group", "party and raid" }) then
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
    if not ContainsAny(normalized, {
        "spacing", "frame spacing", "space between frames", "gap between frames",
        "units per column", "members per column", "players per column", "frames per column",
        "max columns", "columns", "number of columns", "power height", "power bar height",
        "frame width", "frame height",
    }) then
        return nil
    end
    if ContainsAny(normalized, {
        "aura", "auras", "buff", "buffs", "debuff", "debuffs", "private aura", "private auras",
        "text", "font", "name", "health text", "hp text", "power text", "mana text",
        "spell indicator", "spell indicators", "color", "colour", "opacity", "alpha",
    }) then
        return nil
    end

    local attr
    if ContainsAny(normalized, { "units per column", "members per column", "players per column", "frames per column" }) then
        attr = "unitsPerColumn"
    elseif ContainsAny(normalized, { "max columns", "number of columns", "columns" }) then
        attr = "maxColumns"
    elseif ContainsAny(normalized, { "power height", "power bar height" }) then
        attr = "powerHeight"
    elseif ContainsAny(normalized, { "spacing", "frame spacing", "space between frames", "gap between frames" }) then
        attr = "spacing"
    elseif ContainsAny(normalized, { "frame width" }) then
        attr = "width"
    elseif ContainsAny(normalized, { "frame height" }) then
        attr = "height"
    end
    if not attr then return nil end

    local value = FirstNumber(normalized)
    if value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group", "party and raid" }) then
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
        if ContainsAny(text, { "down", "down first", "grow down", "vertical", "vertically", "runter", "unten" }) then return "DOWN" end
        if ContainsAny(text, { "up", "up first", "grow up", "upwards", "hoch", "oben" }) then return "UP" end
        if ContainsAny(text, { "right", "right first", "grow right", "to the right", "horizontal", "horizontally", "rechts" }) then return "RIGHT" end
        if ContainsAny(text, { "left", "left first", "grow left", "to the left", "links" }) then return "LEFT" end
        return nil
    end
    return valueIn(target) or valueIn(normalized)
end

local function GroupSortModeValue(normalized)
    local target = P.TargetAfterLastConnector and P.TargetAfterLastConnector(normalized) or nil
    local function valueIn(text)
        if not text or text == "" then return nil end
        if ContainsAny(text, { "group role", "group and role", "group plus role", "group_role", "grouprole" }) then return "GROUP_ROLE" end
        if ContainsAny(text, { "index", "default", "simple", "off", "disabled" }) then return "INDEX" end
        if ContainsAny(text, { "role", "roles", "by role" }) then return "ROLE" end
        if ContainsAny(text, { "raid group", "by group", "group" }) then return "GROUP" end
        if ContainsAny(text, { "name", "alphabetical", "alpha" }) then return "NAME" end
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
    if ContainsAny(normalized, { "aura", "auras", "buff", "buffs", "debuff", "debuffs", "private aura", "private auras" }) then return nil end

    local attr
    local value
    if ContainsAny(normalized, { "role priority order", "role order", "role sorting order" }) then
        attr = "roleOrder"
        value = GroupRoleOrderValue(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, { "growth", "growth direction", "grow", "grow direction", "frames grow", "frames to grow" }) then
        attr = "growth"
        value = GroupGrowthValue(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, { "sort mode", "sort order", "sortierung", "sortiermodus" }) then
        attr = "sortMode"
        value = GroupSortModeValue(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, { "sort by role", "role sorting", "sort roles" }) then
        attr = "sortByRole"
        value = DetectBoolean(normalized)
        if value == nil then value = not ContainsAny(normalized, { "turn off", "disable", "disabled", "off", "false", "no", "dont", "do not" }) end
    elseif ContainsAny(normalized, {
        "player first in role", "player first", "me first", "myself first",
        "put me first", "keep me first", "me at top", "me at the top",
    }) then
        attr = "playerFirstInRole"
        value = DetectBoolean(normalized)
        if value == nil then value = not ContainsAny(normalized, { "turn off", "disable", "disabled", "off", "false", "no", "dont", "do not" }) end
    elseif ContainsAny(normalized, {
        "preserve raid groups", "keep raid groups", "keep raid groups together",
        "keep groups together", "preserve groups", "preserve group order",
    }) then
        attr = "preserveRaidGroups"
        value = DetectBoolean(normalized)
        if value == nil then value = not ContainsAny(normalized, { "turn off", "disable", "disabled", "off", "false", "no", "dont", "do not" }) end
    end
    if not attr then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group", "party and raid" }) then
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
        if ContainsAny(text, { "auto", "automatic", "breakpoint", "breakpoints" }) then return "auto" end
        if ContainsAny(text, { "manual", "custom" }) then return "manual" end
        if ContainsAny(text, { "off", "none", "disable", "disabled", "false", "no scaling" }) then return "off" end
        if ContainsAny(text, { "on", "enable", "enabled" }) then return "manual" end
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
    if not ContainsAny(normalized, { "scale", "scaling", "skalierung", "skalierungsmodus" }) then return nil end
    if ContainsAny(normalized, {
        "aura", "auras", "buff", "buffs", "debuff", "debuffs", "private aura", "private auras",
        "font", "text", "ui scale", "global ui scale", "wow ui scale", "edit mode", "editmode",
        "class power", "class resource",
    }) then
        return nil
    end

    local attr
    local value
    if ContainsAny(normalized, { "scale mode", "scaling mode", "frame scale mode", "frame scaling mode", "group scale mode", "group scaling mode" }) then
        attr = "frameScaleMode"
        value = GroupScaleModeValue(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, { "frame scaling", "group frame scaling", "scaling" }) and FirstNumber(normalized) == nil then
        attr = "frameScaleEnabled"
        value = DetectBoolean(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, { "scale over 25", "26 plus player scale", "large raid scale", "scale when over 25", "scale for more than 25", "26 players" }) then
        attr = "scaleOver25"
        value = NumberAfterLastConnector(normalized)
    elseif ContainsAny(normalized, { "scale at 25", "21-25 player scale", "scale when 25", "scale for 25", "25 players" }) then
        attr = "scaleAt25"
        value = NumberAfterLastConnector(normalized)
    elseif ContainsAny(normalized, { "scale at 20", "11-20 player scale", "scale when 20", "scale for 20", "20 players" }) then
        attr = "scaleAt20"
        value = NumberAfterLastConnector(normalized)
    elseif ContainsAny(normalized, { "scale at 10", "1-10 player scale", "small group scale", "scale when 10", "scale for 10", "10 players" }) then
        attr = "scaleAt10"
        value = NumberAfterLastConnector(normalized)
    elseif ContainsAny(normalized, { "manual scale", "frame scale", "scale percent", "frame scale percent" }) then
        attr = "frameScaleManual"
        value = NumberAfterLastConnector(normalized)
    end
    if not attr or value == nil then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group", "party and raid" }) then
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
    if not ContainsAny(normalized, {
        "global ui scale", "wow ui scale", "global scale", "ui scale",
        "scale the ui", "scale ui", "ui skalierung",
        "ui scale override", "global scale override",
    }) then return nil end
    if ContainsAny(normalized, { "preset", "1080p", "1440p", "4k", "apply" }) then return nil end
    if ContainsAny(normalized, {
        "party", "raid", "mythic raid", "mythicraid", "group frame", "group frames",
        "edit mode", "editmode", "menu scale", "msuf frame scale", "unit frame scale", "frame scale",
    }) then return nil end

    local key
    local value
    if ContainsAny(normalized, { "override", "ui scale override", "global scale override", "wow ui scale override" }) then
        key = "general.globalUiScaleEnabled"
        value = DetectBoolean(normalized)
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
    if not ContainsAny(normalized, { "spell indicator", "spell indicators" }) then return nil end
    if ContainsAny(normalized, {
        "specific", "multi spec", "multi-spec",
        "slot", "order", "move", "reset", "aura", "auras", "buff", "buffs", "debuff", "debuffs",
        "beacon", "earth shield", "lifebloom", "rejuvenation", "renew", "spell id", "spellid",
    }) then
        return nil
    end
    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group" }) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    if ContainsAny(normalized, { "layer", "draw layer" }) then
        attr = "spellIndicators.layer"
        label = "Spell Indicator Layer"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "spec", "specialization", "specialisation" }) then
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
    if ContainsAny(normalized, {
        "text color", "text colour", "font color", "font colour",
        "health text", "hp text", "power text", "mana text", "resource text",
        "power color", "power colour", "power bar color", "power bar colour",
        "powerbar color", "powerbar colour", "mana color", "mana colour",
        "mana bar color", "mana bar colour", "resource color", "resource colour",
        "resource bar color", "resource bar colour", "class power", "class resource",
        "castbar", "cast bar", "status icon", "status icons", "status indicator",
        "raid marker", "role icon", "ready check", "summon", "resurrection",
        "targeted spell", "targeted spells", "texture", "textures",
        "gradient", "gradients", "health gradient", "bar gradient",
    }) then
        return nil
    end
    if ContainsAny(normalized, { "aura", "auras", "buff", "buffs" }) then return nil end
    if ContainsAny(normalized, { "debuff", "debuffs" })
        and not ContainsAny(normalized, { "debuff stripe", "debuff stripes" })
    then
        return nil
    end
    if P.GroupColorTargetForText and not P.GroupColorTargetForText(normalized) then return nil end

    return P.ParseGroupFrameColorShortcut(normalized, raw)
end

local function ParseGroupDeadBackgroundFastShortcut(normalized)
    if not ContainsAny(normalized, {
        "dead background", "dead member background", "dead offline background", "dead bg",
        "tint offline members", "also tint offline members", "dead background offline members", "dead offline tint",
    }) then
        return nil
    end
    if ContainsAny(normalized, { "color", "colors", "colour", "colours", "farbe", "farben" }) then return nil end
    if ContainsAny(normalized, {
        "aura", "auras", "buff", "buffs", "debuff", "debuffs",
        "text", "font", "spell indicator", "status icon", "raid marker", "role icon",
    }) then
        return nil
    end

    local attr
    local label
    local value
    if ContainsAny(normalized, {
        "tint offline members", "also tint offline members", "dead background offline members", "dead offline tint",
    }) then
        attr = "deadBgOffline"
        label = "Tint Offline Members"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, {
        "dead background opacity", "dead background alpha", "dead member background opacity",
        "dead offline background opacity", "dead bg opacity", "dead bg alpha",
    }) then
        attr = "deadBgA"
        label = "Dead Background Opacity"
        if ContainsAny(normalized, { "increase", "decrease", "raise", "lower", "more ", "less ", "relative", "by " }) then return nil end
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
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group" }) then
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
    if ContainsAny(normalized, { "free", "none", "clear", "uiparent", "ui parent" }) then return "FREE" end
    if ContainsAny(normalized, { "targettarget", "target of target", "tot" }) then return "targettarget" end
    if ContainsAny(normalized, { "focustarget", "focus target" }) then return "focustarget" end
    if ContainsAny(normalized, { "player" }) then return "player" end
    if ContainsAny(normalized, { "target" }) then return "target" end
    if ContainsAny(normalized, { "focus" }) then return "focus" end
    return nil
end

local function GroupFrameAnchorPointValue(normalized)
    if ContainsAny(normalized, { "top left", "topleft" }) then return "TOPLEFT" end
    if ContainsAny(normalized, { "top right", "topright" }) then return "TOPRIGHT" end
    if ContainsAny(normalized, { "bottom left", "bottomleft" }) then return "BOTTOMLEFT" end
    if ContainsAny(normalized, { "bottom right", "bottomright" }) then return "BOTTOMRIGHT" end
    if ContainsAny(normalized, { "top" }) then return "TOP" end
    if ContainsAny(normalized, { "bottom" }) then return "BOTTOM" end
    if ContainsAny(normalized, { "left" }) then return "LEFT" end
    if ContainsAny(normalized, { "right" }) then return "RIGHT" end
    if ContainsAny(normalized, { "center", "centre", "middle" }) then return "CENTER" end
    return nil
end

local TARGETED_SPELL_TERMS = {
    "targeted spell", "targeted spells", "targeted spell indicator",
    "targeted spell indicators", "targeted spell tracker",
    "targeted spells tracker", "enemy targeted spell",
    "enemy targeted spells", "enemy nameplate cast tracker",
}

local function TargetedSpellPartyScope(normalized)
    if not ContainsAny(normalized, TARGETED_SPELL_TERMS) then return false, false end
    local groups = DetectGroups(normalized)
    local hasParty = false
    local hasOther = false
    for i = 1, #groups do
        if groups[i] == "party" then
            hasParty = true
        elseif groups[i] == "raid" or groups[i] == "mythicraid" then
            hasOther = true
        end
    end
    return hasParty, hasOther
end

local function TargetedSpellModeValue(normalized)
    if ContainsAny(normalized, { "whenhealing", "when healing", "healing only", "healer", "healing", "smart" }) then return "whenHealing" end
    if ContainsAny(normalized, { "always", "all the time" }) then return "always" end
    return nil
end

local function TargetedSpellGrowValue(normalized)
    if ContainsAny(normalized, { "center", "centre", "middle", "centered" }) then return "CENTER" end
    if ContainsAny(normalized, { "right" }) then return "RIGHT" end
    if ContainsAny(normalized, { "left" }) then return "LEFT" end
    if ContainsAny(normalized, { "up", "above" }) then return "UP" end
    if ContainsAny(normalized, { "down", "below" }) then return "DOWN" end
    return nil
end

local function ParsePartyTargetedSpellFastShortcut(normalized, raw)
    local hasParty, hasOther = TargetedSpellPartyScope(normalized)
    if hasOther then
        return {
            kind = "answer",
            status = "clarify",
            text = "Targeted Spell Indicators are a Party-only MSUF option. I can change party targeted spell settings, but I should not apply that to Raid or Mythic Raid because those frames do not own this setting.",
            summary = "Explains targeted spell indicator scope.",
        }
    end
    if not hasParty then return nil end

    local attr
    local label
    local value
    local valueLabel
    if ContainsAny(normalized, { "color by time", "colour by time", "timer color by time", "timer colour by time" }) then
        attr = "targetedSpellsTextColorByTime"
        label = "Targeted Spell Cooldown Color by Time"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, { "color", "colors", "colour", "colours", "farbe", "farben", "tint" }) then
        if ContainsAny(normalized, { "safe color", "safe timer color", "safe colour", "safe timer colour" }) then
            attr = "targetedSpellsTextSafeColor"
            label = "Targeted Spell Safe Color"
        elseif ContainsAny(normalized, { "warning color", "warning timer color", "warning colour", "warning timer colour" }) then
            attr = "targetedSpellsTextWarningColor"
            label = "Targeted Spell Warning Color"
        elseif ContainsAny(normalized, { "urgent color", "urgent timer color", "urgent colour", "urgent timer colour" }) then
            attr = "targetedSpellsTextUrgentColor"
            label = "Targeted Spell Urgent Color"
        else
            return {
                kind = "answer",
                status = "ambiguous",
                text = "Which Party Targeted Spell color should I change: Safe, Warning, or Urgent? Examples: 'set party targeted spell safe color to white', 'set party targeted spell warning color to yellow', or 'set party targeted spell urgent color to orange'.",
                summary = "Clarifies which targeted spell timer color to change.",
            }
        end
        local colorValue, colorLabel
        if P.ColorShortcutValue then
            colorValue, colorLabel = P.ColorShortcutValue(normalized, raw)
        end
        if not colorValue then return nil end
        value = colorValue
        valueLabel = colorLabel
    elseif ContainsAny(normalized, { "cooldown text size", "timer text size" }) then
        attr = "targetedSpellsTextSize"
        label = "Targeted Spell Cooldown Text Size"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "cooldown text", "timer text" }) then
        attr = "targetedSpellsTextEnabled"
        label = "Targeted Spell Cooldown Text"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, { "cooldown decimals", "timer decimals", "decimal threshold", "decimals below" }) then
        attr = "targetedSpellsTextDecimalBelow"
        label = "Targeted Spell Cooldown Decimal Threshold"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "safe seconds", "safe timer threshold" }) then
        attr = "targetedSpellsTextSafeSeconds"
        label = "Targeted Spell Safe Seconds"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "warning seconds", "warning timer threshold" }) then
        attr = "targetedSpellsTextWarningSeconds"
        label = "Targeted Spell Warning Seconds"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "urgent seconds", "urgent timer threshold" }) then
        attr = "targetedSpellsTextUrgentSeconds"
        label = "Targeted Spell Urgent Seconds"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "icon size", "targeted spell size", "targeted spells size" }) then
        attr = "targetedSpellsIconSize"
        label = "Targeted Spell Icon Size"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "max icons", "maximum icons", "icon count" }) then
        attr = "targetedSpellsMaxIcons"
        label = "Targeted Spell Max Icons"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "layer", "draw layer" }) then
        attr = "targetedSpellsLayer"
        label = "Targeted Spell Layer"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "anchor", "position" }) then
        attr = "targetedSpellsAnchor"
        label = "Targeted Spell Anchor"
        value = GroupFrameAnchorPointValue(normalized)
    elseif ContainsAny(normalized, { "growth", "grow" }) then
        attr = "targetedSpellsGrow"
        label = "Targeted Spell Growth"
        value = TargetedSpellGrowValue(normalized)
    elseif ContainsAny(normalized, { "x offset", "offset x", "targeted spell x", "targeted spells x" }) then
        attr = "targetedSpellsX"
        label = "Targeted Spell X Offset"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "y offset", "offset y", "targeted spell y", "targeted spells y" }) then
        attr = "targetedSpellsY"
        label = "Targeted Spell Y Offset"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "mode" }) then
        attr = "targetedSpellsMode"
        label = "Targeted Spell Mode"
        value = TargetedSpellModeValue(normalized)
    else
        attr = "targetedSpellsEnabled"
        label = "Targeted Spell Indicators"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    end
    if value == nil then return nil end

    local setting = A.Registry and A.Registry:GetSetting("gf_party." .. attr)
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, valueLabel = valueLabel } },
        label = setting.label or label,
        summary = "Changes Party Targeted Spell Indicator settings.",
    }
end
A._ParsePartyTargetedSpellFastShortcut = ParsePartyTargetedSpellFastShortcut

local function ParseGroupFrameAnchorFastShortcut(normalized)
    if not ContainsAny(normalized, {
        "anchor to", "attach to", "anchored to", "anchor target", "anchor frame",
        "anchor point", "anchor position",
    }) then
        return nil
    end
    if ContainsAny(normalized, {
        "custom anchor", "custom anchor frame", "anchor frame name", "clear custom anchor",
        "remove custom anchor", "reset custom anchor", "picker",
        "portrait", "castbar", "cast bar", "name text", "hp text", "health text", "power text",
        "text", "icon", "indicator", "raid marker", "status", "level", "level indicator",
        "raid group name", "group number", "leader", "assist", "elite", "rare",
        "combat indicator", "rested", "resting", "incoming rez", "incoming resurrection",
        "aura", "auras", "buff", "buffs", "debuff", "debuffs",
    }) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group" }) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    if ContainsAny(normalized, { "anchor point", "anchor position" }) then
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
    if ContainsAny(normalized, { "global", "global color", "global colors", "inherit", "inherit color", "default", "default color" }) then return "GLOBAL" end
    if ContainsAny(normalized, { "dark", "dark mode", "darkmode" }) then return "dark" end
    if ContainsAny(normalized, { "unified", "unified color", "unifiedcolor" }) then return "unified" end
    if ContainsAny(normalized, { "gradient", "health gradient", "healthgradient" }) then return "GRADIENT" end
    if ContainsAny(normalized, { "custom", "manual" }) then return "CUSTOM" end
    if ContainsAny(normalized, { "class", "class color", "class colors", "classcolor", "class colored", "colored by class", "coloured by class" }) then return "CLASS" end
    return nil
end

local function ParseGroupBarColorModeFastShortcut(normalized)
    if ContainsAny(normalized, {
        "text", "font", "name", "power text", "health text", "hp text", "mana text",
        "class power", "class resource", "resource text", "castbar", "cast bar",
        "aura", "auras", "buff", "buffs", "debuff", "debuffs",
    }) then
        return nil
    end
    if not ContainsAny(normalized, {
        "bar color mode", "health bar color mode", "group bar style",
        "use class colors", "class colored bars", "colored by class", "coloured by class",
        "use global colors", "use default colors", "health color mode", "health mode",
        "class color", "class colors", "global color", "global colors",
    }) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group" }) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    if ContainsAny(normalized, { "health color mode", "health mode" }) then
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
    if ContainsAny(text, { "double space", "doublespace" }) then return "  " end
    if ContainsAny(text, { "space", "single" }) then return " " end
    if ContainsAny(text, { "slash", "forward slash", "forwardslash" }) then return " / " end
    if ContainsAny(text, { "hyphen", "dash", "minus" }) then return " - " end
    if ContainsAny(text, { "colon" }) then return " : " end
    if ContainsAny(text, { "pipe", "vertical bar", "verticalbar" }) then return " | " end
    if text:find("/", 1, true) then return " / " end
    if text:find("-", 1, true) then return " - " end
    if text:find(":", 1, true) then return " : " end
    if text:find("|", 1, true) then return " | " end
    if normalized:match("%s+to$") or normalized:match("%s+as$") or normalized:match("%s+is$") then return false end
    return nil
end

local function ParseGroupTextFormatFastShortcut(normalized)
    if ContainsAny(normalized, {
        "castbar", "cast bar", "aura", "auras", "buff", "buffs", "debuff", "debuffs",
        "class power", "class resource", "class resources", "name text", "name color",
        "font", "color", "colour", "slot", "left text", "right text", "center text", "centre text",
    }) then
        return nil
    end
    if not ContainsAny(normalized, {
        "hp text delimiter", "health text delimiter", "health delimiter",
        "power text delimiter", "mana text delimiter", "power delimiter", "mana delimiter",
        "hp text x", "hp text y", "health text x", "health text y",
        "power text x", "power text y", "mana text x", "mana text y",
        "hp text layer", "health text layer", "power text layer", "mana text layer",
        "reverse hp text", "hp text reverse", "reverse health text", "health text reverse",
        "health text decimals", "hp text decimals", "decimal percent",
    }) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group" }) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    if ContainsAny(normalized, { "power text delimiter", "mana text delimiter", "power delimiter", "mana delimiter" }) then
        attr = "powerTextDelimiter"
        label = "Power Text Delimiter"
        value = GroupTextDelimiterValue(normalized)
    elseif ContainsAny(normalized, { "hp text delimiter", "health text delimiter", "health delimiter" }) then
        attr = "textDelimiter"
        label = "HP Text Delimiter"
        value = GroupTextDelimiterValue(normalized)
    elseif ContainsAny(normalized, { "power text x", "power text x offset", "mana text x", "mana text x offset" }) then
        attr = "powerOffsetX"
        label = "Power Text X Offset"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "power text y", "power text y offset", "mana text y", "mana text y offset" }) then
        attr = "powerOffsetY"
        label = "Power Text Y Offset"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "power text layer", "mana text layer" }) then
        attr = "powerTextLayer"
        label = "Power Text Layer"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "hp text x", "hp text x offset", "health text x", "health text x offset" }) then
        attr = "hpOffsetX"
        label = "HP Text X Offset"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "hp text y", "hp text y offset", "health text y", "health text y offset" }) then
        attr = "hpOffsetY"
        label = "HP Text Y Offset"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "hp text layer", "health text layer" }) then
        attr = "textLayer"
        label = "HP Text Layer"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, {
        "reverse hp text", "hp text reverse", "reverse health text", "health text reverse",
        "reverse hp text order", "hp text reverse order", "reverse health text order", "health text reverse order",
    }) then
        attr = "hpTextReverse"
        label = "Reverse HP Text"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, { "health text decimals", "hp text decimals", "health decimals", "hp decimals", "decimal percent" }) then
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
    if ContainsAny(normalized, { "by me", "byme", "dispellable by me", "dispellable" }) then return "BY_ME" end
    if ContainsAny(normalized, { "dispel type", "dispeltype", "type" }) then return "DISPEL_TYPE" end
    if ContainsAny(normalized, { "any debuff", "all debuffs", "any", "debuff" }) then return "ANY_DEBUFF" end
    if ContainsAny(normalized, { "border", "dispel border", "inherit", "same" }) then return "BORDER" end
    return nil
end

local function GroupDispelOverlayStyleValue(normalized)
    if ContainsAny(normalized, { "full frame", "full" }) then return "FULL" end
    if ContainsAny(normalized, { "bottom" }) then return "BOTTOM" end
    if ContainsAny(normalized, { "top" }) then return "TOP" end
    if ContainsAny(normalized, { "left" }) then return "LEFT" end
    if ContainsAny(normalized, { "right" }) then return "RIGHT" end
    return nil
end

local function ParseGroupDispelOverlayFastShortcut(normalized)
    if not ContainsAny(normalized, {
        "dispel overlay", "debuff overlay", "dispellable overlay", "dispellable debuff overlay",
        "dispel health overlay", "dispellable health overlay",
    }) then
        return nil
    end
    if ContainsAny(normalized, { "opacity", "alpha", "color", "colors", "colour", "colours", "aura filter", "aura filters", "debuff stripe" }) then return nil end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group" }) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    if ContainsAny(normalized, { "current health only", "current health", "on current health", "on health only", "on health" }) then
        attr = "dispelOverlayOnHealth"
        label = "Dispel Overlay on Current Health"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, { "detects", "trigger" }) then
        attr = "dispelOverlayTrigger"
        label = "Dispel Overlay Detects"
        value = GroupDispelOverlayTriggerValue(normalized)
    elseif ContainsAny(normalized, { "style" }) then
        attr = "dispelOverlayStyle"
        label = "Dispel Overlay Style"
        value = GroupDispelOverlayStyleValue(normalized)
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
    if ContainsAny(normalized, { "health only", "hp only", "current health", "health" }) then return "health" end
    if ContainsAny(normalized, { "whole frame", "entire frame", "full frame", "frame" }) then return "frame" end
    return nil
end

local function ParseGroupRangeFadeFastShortcut(normalized)
    if ContainsAny(normalized, { "aura", "auras", "buff", "buffs", "debuff", "debuffs", "castbar", "cast bar" }) then return nil end
    if ContainsAny(normalized, { "keep text visible", "keep names visible", "text visible", "names visible" }) then return nil end
    if not ContainsAny(normalized, {
        "range fade", "range fading", "out of range", "outside range",
        "offline alpha", "offline opacity", "offline member opacity", "offline transparency",
        "fade offline members", "offline member fade",
        "health fade", "healthy fade", "healer health fade", "fade healthy members",
        "dim healthy members", "dim healthy frames", "fade full health", "dim full health",
    }) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group" }) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    if ContainsAny(normalized, {
        "offline alpha", "offline opacity", "offline member opacity", "offline transparency",
        "fade offline members", "offline member fade",
    }) then
        attr = "offlineAlpha"
        label = "Offline Opacity"
        value = FirstNumber(normalized)
        if value == nil then return nil end
        if value > 1 then value = value / 100 end
    elseif ContainsAny(normalized, {
        "health fade", "healthy fade", "healer health fade", "fade healthy members",
        "dim healthy members", "dim healthy frames", "fade full health", "dim full health",
    }) then
        if ContainsAny(normalized, {
            "health fade threshold", "health fade percent", "fade above health",
            "fade above health percent", "dim above health", "dim above health percent",
            "healthy frame threshold",
        }) then
            attr = "healthFadeThreshold"
            label = "Health Fade Threshold"
            value = FirstNumber(normalized)
        elseif ContainsAny(normalized, {
            "health fade opacity", "health fade alpha", "healthy frame opacity",
            "healthy member opacity", "dimmed health opacity", "dimmed healthy opacity",
        }) then
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
    elseif ContainsAny(normalized, { "affects", "layer", "mode", "health only", "hp only", "whole frame", "entire frame", "full frame" }) then
        attr = "rangeFadeLayerMode"
        label = "Range Fade Affects"
        value = GroupRangeFadeLayerValue(normalized)
    elseif ContainsAny(normalized, { "alpha", "opacity", "transparency", "transparent" }) or FirstNumber(normalized) ~= nil then
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
        summary = "Changes group-frame range, offline, or health fade options.",
    }
end

local function GroupCornerAnchorValue(normalized)
    if ContainsAny(normalized, { "top left", "topleft" }) then return "TOPLEFT" end
    if ContainsAny(normalized, { "top right", "topright" }) then return "TOPRIGHT" end
    if ContainsAny(normalized, { "bottom left", "bottomleft" }) then return "BOTTOMLEFT" end
    if ContainsAny(normalized, { "bottom right", "bottomright" }) then return "BOTTOMRIGHT" end
    if ContainsAny(normalized, { "top" }) then return "TOPLEFT" end
    if ContainsAny(normalized, { "bottom" }) then return "BOTTOMRIGHT" end
    return nil
end

local function ParseGroupNumberFastShortcut(normalized)
    if not ContainsAny(normalized, { "group number", "group index", "group number label" }) then return nil end
    if ContainsAny(normalized, {
        "style", "raid group style", "raid group name style",
        "aura", "auras", "buff", "buffs", "debuff", "debuffs",
        "status icon", "spell indicator", "raid marker", "role icon",
    }) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group" }) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    if ContainsAny(normalized, { "anchor", "position" }) then
        attr = "groupNumberAnchor"
        label = "Group Number Anchor"
        value = GroupCornerAnchorValue(normalized)
    elseif ContainsAny(normalized, { "x offset", "offset x", "group number x", "group index x", " x", "x " }) then
        attr = "groupNumberX"
        label = "Group Number X Offset"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "y offset", "offset y", "group number y", "group index y", " y", "y " }) then
        attr = "groupNumberY"
        label = "Group Number Y Offset"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "size", "font size", "group number size", "group index size" }) then
        attr = "groupNumberSize"
        label = "Group Number Size"
        value = FirstNumber(normalized)
    else
        attr = "showGroupNumber"
        label = "Group Number"
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
        summary = "Changes group-frame group-number display settings.",
    }
end

local function GroupAggroModeValue(normalized)
    if ContainsAny(normalized, { "non tank", "non tanks", "not tank", "not tanks", "non-tank", "non-tanks", "nontank" }) then return "NON_TANK" end
    if ContainsAny(normalized, { "healer", "healers" }) then return "HEALER" end
    if ContainsAny(normalized, { "tank", "tanks" }) then return "TANK" end
    if ContainsAny(normalized, { "all", "everyone", "all roles" }) then return "ALL" end
    return nil
end

local function ParseGroupHighlightFastShortcut(normalized)
    if ContainsAny(normalized, {
        "color", "colors", "colour", "colours", "priority", "custom highlight priority",
        "bar outline", "outline color", "aura", "auras", "buff", "buffs", "debuff", "debuffs",
    }) then
        return nil
    end
    if not ContainsAny(normalized, {
        "hover highlight", "mouseover highlight", "hover border",
        "fallback aggro border", "fallback threat border", "group fallback aggro border", "group fallback threat border",
        "fallback aggro shows for", "fallback aggro role filter", "fallback threat role filter",
        "fallback aggro non tanks", "fallback aggro not tanks", "fallback threat non tanks",
        "fallback dispel border", "fallback dispellable border", "group fallback dispel border", "group fallback dispellable border",
        "target highlight", "target border", "selected target border",
        "focus highlight", "focus border", "focus glow",
    }) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group" }) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    if ContainsAny(normalized, { "hover highlight thickness", "mouseover highlight thickness", "hover border thickness" }) then
        attr = "hlHoverSize"
        label = "Hover Highlight Thickness"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "fallback aggro shows for", "fallback aggro role filter", "fallback threat role filter", "fallback aggro non tanks", "fallback aggro not tanks", "fallback threat non tanks" }) then
        attr = "aggroMode"
        label = "Aggro Shows For"
        value = GroupAggroModeValue(normalized)
    elseif ContainsAny(normalized, { "fallback aggro border", "fallback threat border", "group fallback aggro border", "group fallback threat border" }) then
        attr = "aggroEnabled"
        label = "Aggro Border"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, { "fallback dispel border", "fallback dispellable border", "group fallback dispel border", "group fallback dispellable border" }) then
        attr = "dispelEnabled"
        label = "Dispel Border"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, { "target highlight", "target border", "selected target border" }) then
        attr = "targetIndicator"
        label = "Target Highlight"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, { "focus highlight thickness", "focus border thickness", "focus glow thickness" }) then
        attr = "hlFocusSize"
        label = "Focus Highlight Thickness"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "focus highlight offset", "focus border offset", "focus glow offset" }) then
        attr = "hlFocusOffset"
        label = "Focus Highlight Offset"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "focus highlight", "focus border", "focus glow" }) then
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
    if not ContainsAny(normalized, {
        "group border", "full group border", "whole group border", "outer group border", "group block border",
        "border around group", "border around frames",
    }) then
        return nil
    end
    if ContainsAny(normalized, {
        "color", "colors", "colour", "colours", "bar outline", "frame outline",
        "highlight border", "fallback aggro", "fallback threat", "fallback dispel",
        "aura", "auras", "buff", "buffs", "debuff", "debuffs",
    }) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group" }) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    if ContainsAny(normalized, { "padding", "border padding", "padding around", "padding around frames", "padding around group", "frame padding" }) then
        attr = "groupBorderPadding"
        label = "Group Border Padding"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "opacity", "alpha", "transparency" }) then
        attr = "groupBorderA"
        label = "Group Border Opacity"
        value = FirstNumber(normalized)
        if value and value > 1 then value = value / 100 end
    elseif ContainsAny(normalized, { "thickness", "size", "border size", "border thickness", "thicker", "thinner", "bigger", "smaller" }) then
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
    if ContainsAny(normalized, { "midnight", "msuf" }) then return "MIDNIGHT" end
    if ContainsAny(normalized, { "classic", "old" }) then return "CLASSIC" end
    if ContainsAny(normalized, { "blizzard", "default" }) then return "BLIZZARD" end
    return nil
end

local function ParseGroupStatusIconStyleFastShortcut(normalized)
    if ContainsAny(normalized, {
        "icon pack", "role icon", "leader icon", "assist icon", "ready check",
        "raid marker", "pvp", "summon", "phase", "resurrection", "incoming",
        "anchor", "offset", " x", "x ", " y", "y ", "size", "layer",
    }) then
        return nil
    end
    if not ContainsAny(normalized, {
        "status icon style", "status icons style", "group icon style",
        "midnight status icons", "midnight icon style", "use midnight icons",
        "status icons midnight style", "status icon midnight style", "midnight status icon style",
    }) then
        return nil
    end

    local groups = DetectGroups(normalized)
    if #groups == 0 and ContainsAny(normalized, { "all group frames", "all groups", "every group frame", "every group" }) then
        groups = { "party", "raid", "mythicraid" }
    end
    if #groups == 0 then return nil end

    local attr
    local label
    local value
    if ContainsAny(normalized, { "use midnight icons", "midnight status icons" })
        and not ContainsAny(normalized, { "classic", "blizzard", "default", "old" })
    then
        attr = "useMidnightIcons"
        label = "Use Midnight Status Icons"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    else
        attr = "iconStyle"
        label = "Status Icon Style"
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
    return (P.ParseAuraFilterGuidanceShortcut and P.ParseAuraFilterGuidanceShortcut(normalized))
        or (A.RouterTryAuraFilterStatusShortcut and A.RouterTryAuraFilterStatusShortcut(normalized))
        or (P.ParseAuraScopeOverrideShortcut and P.ParseAuraScopeOverrideShortcut(normalized))
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
    "gradient", "gradients", "bar gradient", "bar gradients", "gradient direction",
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

local function ParseBarGradientPriorityShortcut(normalized)
    return (P.ParseBarGradientRegistryShortcut and P.ParseBarGradientRegistryShortcut(normalized))
        or (P.ParsePowerBarGradientRegistryShortcut and P.ParsePowerBarGradientRegistryShortcut(normalized))
end
A._ParseBarGradientPriorityShortcut = ParseBarGradientPriorityShortcut

local function ParseGlobalBarModePriorityShortcut(normalized)
    if ContainsAny(normalized, {
        "party", "raid", "mythic raid", "mythicraid", "group frame", "group frames",
        "player", "target", "focus", "pet", "boss", "targettarget", "focustarget",
        "text", "font", "name", "power text", "health text", "hp text", "mana text",
        "class power", "class resource", "class resources", "castbar", "cast bar",
        "aura", "auras", "buff", "buffs", "debuff", "debuffs",
    }) then
        return nil
    end
    if not ContainsAny(normalized, { "bar mode", "bar color mode", "health bar mode", "bars mode", "global bar mode" }) then
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
    if not ContainsAny(normalized, {
        "bar texture", "bars texture", "health bar texture", "power bar texture",
        "foreground bar texture", "foreground texture", "bar background texture",
        "global bar texture", "global bars texture", "global bar background texture",
        "background bar texture", "bar bg texture", "background texture",
    }) then return nil end
    if ContainsAny(normalized, {
        "party", "raid", "mythic raid", "mythicraid", "group frame", "group frames",
        "player", "target", "focus", "pet", "boss", "targettarget", "focustarget",
        "castbar", "cast bar", "class power", "class resource", "class resources",
        "detached power", "second hp", "player hp", "absorb", "heal absorb",
        "gradient", "color", "colour", "opacity", "alpha", "outline", "border",
    }) then
        return nil
    end

    local key
    if ContainsAny(normalized, { "bar background texture", "global bar background texture", "background bar texture", "bar bg texture", "background texture" }) then
        key = "general.barBackgroundTexture"
    else
        key = "general.barTexture"
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
    if not ContainsAny(normalized, { "gradient strength", "bar gradient strength", "health gradient strength", "power gradient strength" }) then return nil end
    if ContainsAny(normalized, {
        "party", "raid", "mythic raid", "mythicraid", "group frame", "group frames",
        "player", "target", "focus", "pet", "boss", "targettarget", "focustarget",
        "castbar", "cast bar", "class power", "class resource", "class resources",
        "detached power", "second hp", "player hp", "absorb", "heal absorb",
        "texture", "color", "colour", "opacity", "alpha", "outline", "border",
    }) then
        return nil
    end
    local setting = A.Registry and A.Registry:GetSetting("general.gradientStrength")
    if not setting then return nil end
    local value = FirstNumber(normalized)
    if value == nil then return nil end
    if value > 1 and tostring(normalized):find("%%") then
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

local function ParseGlobalRoundedBarsPriorityShortcut(normalized)
    if not ContainsAny(normalized, {
        "rounded frame texture", "rounded frames", "round corners", "rounded corners", "rounded texture",
        "rounded unit frames", "rounded unitframes", "unit frame corners", "unitframe corners",
        "rounded group frames", "rounded party frames", "rounded raid frames", "group frame corners",
        "rounded power bars", "rounded powerbar", "power bar corners", "powerbar corners",
        "rounded mouseover", "rounded hover", "rounded hover border", "mouseover rounded", "rounded mouseover highlights",
    }) then return nil end
    if ContainsAny(normalized, {
        "portrait", "aura", "auras", "buff", "debuff", "icon", "icons",
        "castbar", "cast bar", "class power", "class resource", "class resources",
        "combo point", "combo points", "shape",
    }) then
        return nil
    end

    local key
    if ContainsAny(normalized, { "rounded mouseover", "rounded hover", "rounded hover border", "mouseover rounded", "rounded mouseover highlights" }) then
        key = "bars.roundedMouseover"
    elseif ContainsAny(normalized, { "rounded power bars", "rounded powerbar", "power bar corners", "powerbar corners" }) then
        key = "bars.roundedPowerBars"
    elseif ContainsAny(normalized, { "rounded group frames", "rounded party frames", "rounded raid frames", "group frame corners" }) then
        key = "bars.roundedGroupFrames"
    elseif ContainsAny(normalized, { "rounded unit frames", "rounded unitframes", "unit frame corners", "unitframe corners" }) then
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
    if not ContainsAny(normalized, {
        "unitframe dispel overlay", "unit frame dispel overlay", "dispel overlay", "health bar dispel overlay",
    }) then return nil end
    if ContainsAny(normalized, {
        "party", "raid", "mythic raid", "mythicraid", "group frame", "group frames",
        "player", "target", "focus", "pet", "boss", "targettarget", "focustarget",
        "aura", "auras", "buff", "debuff", "corner", "stripe", "filter",
    }) then
        return nil
    end

    local key
    local value
    if ContainsAny(normalized, { "detects", "trigger", "detection" }) then
        key = "general.unitDispelOverlayTrigger"
    elseif ContainsAny(normalized, { "style" }) then
        key = "general.unitDispelOverlayStyle"
    elseif ContainsAny(normalized, { "current health only", "current health", "on health only", "on current health", "on current health only" }) then
        key = "general.unitDispelOverlayOnHealth"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, { "opacity", "alpha" }) then
        key = "general.unitDispelOverlayAlpha"
        value = FirstNumber(normalized)
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
    if not ContainsAny(normalized, {
        "unitframe dispel overlay", "unit frame dispel overlay", "dispel overlay", "health bar dispel overlay",
    }) then return nil end
    if ContainsAny(normalized, {
        "party", "raid", "mythic raid", "mythicraid", "group frame", "group frames",
        "aura", "auras", "buff", "debuff", "corner", "stripe", "filter",
    }) then
        return nil
    end

    local units = DetectUnits and DetectUnits(normalized) or {}
    if #units == 0 then return nil end

    local suffix
    local value
    if ContainsAny(normalized, { "detects", "trigger", "detection" }) then
        suffix = "unitDispelOverlayTrigger"
    elseif ContainsAny(normalized, { "style" }) then
        suffix = "unitDispelOverlayStyle"
    elseif ContainsAny(normalized, { "current health only", "current health", "on health only", "on current health", "on current health only" }) then
        suffix = "unitDispelOverlayOnHealth"
        value = DetectBoolean(normalized)
        if value == nil then value = true end
    elseif ContainsAny(normalized, { "opacity", "alpha" }) then
        suffix = "unitDispelOverlayAlpha"
        value = FirstNumber(normalized)
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
    if not ContainsAny(normalized, {
        "smooth power bar", "smooth power", "smooth mana bar", "power bar smoothing",
        "realtime power text", "real time power text", "instant power text", "accurate power text",
    }) then return nil end
    if ContainsAny(normalized, {
        "party", "raid", "mythic raid", "mythicraid", "group frame", "group frames",
        "player", "target", "focus", "pet", "boss", "targettarget", "focustarget",
        "class power", "class resource", "class resources", "detached power",
        "color", "colour", "font", "size", "offset", "anchor", "position",
    }) then
        return nil
    end

    local key = ContainsAny(normalized, { "realtime power text", "real time power text", "instant power text", "accurate power text" })
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
    if not ContainsAny(normalized, { "bars override", "bar override", "custom bars", "custom bar settings", "bar custom settings" }) then return nil end
    if ContainsAny(normalized, { "reset", "clear", "remove" }) then return nil end
    if ContainsAny(normalized, {
        "texture", "gradient", "strength", "direction", "color", "colour", "opacity", "alpha",
        "outline", "border", "dispel", "aggro", "purge", "absorb", "heal absorb",
        "power text", "health text", "hp text", "font", "size", "height", "width",
    }) then
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
    if not ContainsAny(normalized, { "gradient strength", "bar gradient strength", "health gradient strength", "power gradient strength" }) then return nil end
    if ContainsAny(normalized, {
        "castbar", "cast bar", "class power", "class resource", "class resources",
        "detached power", "second hp", "player hp", "absorb", "heal absorb",
        "texture", "color", "colour", "opacity", "alpha", "outline", "border",
    }) then
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
    if value > 1 and tostring(normalized):find("%%") then
        value = value / 100
    end

    local changes = {}
    local seen = {}
    for i = 1, #scopes do
        local scope = tostring(scopes[i])
        if not seen[scope] then
            seen[scope] = true
            local setting = A.Registry and A.Registry:GetSetting("barScope." .. scope .. ".gradientStrength")
            if setting then changes[#changes + 1] = { setting = setting, value = value } end
        end
    end
    if #changes == 0 then return nil end
    return {
        kind = "changes",
        changes = changes,
        label = "Bar Gradient Strength",
        bulkSafe = #changes > 1,
        summary = "Changes scoped MSUF bar gradient strength.",
    }
end
A._ParseScopedGradientStrengthPriorityShortcut = ParseScopedGradientStrengthPriorityShortcut

local function ParseGlobalFontPriorityShortcut(normalized, raw)
    if ContainsAny(normalized, {
        "party", "raid", "mythic raid", "mythicraid", "group frame", "group frames",
        "player", "target", "focus", "pet", "boss", "targettarget", "focustarget",
        "combat", "timer", "crosshair", "totem",
        "name text", "hp text", "health text", "power text", "mana text",
        "class power", "class resource", "class resources", "castbar", "cast bar",
        "aura", "auras", "buff", "buffs", "debuff", "debuffs",
    }) then
        return nil
    end

    local key
    local label
    local value
    if ContainsAny(normalized, { "font size", "text size", "schrift groesse", "schriftgroesse", "globale schriftgroesse" }) then
        key = "general.fontSize"
        label = "Global Font Size"
        value = FirstNumber(normalized)
    elseif ContainsAny(normalized, { "font color", "font colour", "schriftfarbe", "textfarbe" }) then
        if ContainsAny(normalized, { "custom", "global font color", "global font colour" }) then return nil end
        key = "general.fontColor"
        label = "Global Font Palette Color"
    elseif ContainsAny(normalized, { "font family", "global font", "shared font", "sharedmedia font" }) then
        key = "general.fontKey"
        label = "Global Font"
    else
        return nil
    end

    local setting = A.Registry and A.Registry:GetSetting(key)
    if not setting then return nil end
    if value == nil then
        value = P.ValueForRegistrySetting and P.ValueForRegistrySetting(setting, normalized, raw or normalized) or nil
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
    if not ContainsAny(normalized, {
        "font override", "font size", "font outline", "font rendering",
        "text opacity", "text baseline", "text shadow", "shadow strength",
        "shorten names", "truncate names", "name shortening", "name truncation",
        "truncation style", "clip side", "max name length", "name max length",
        "max chars", "no ellipsis", "without ellipsis", "without dots",
    }) then return nil end
    if ContainsAny(normalized, {
        "name text", "name font", "hp text", "hp font", "health text", "health font",
        "power text", "power font", "mana text", "mana font",
        "left text", "right text", "center text", "centre text", "text slot",
        "castbar", "cast bar", "aura", "buff", "debuff",
        "reset", "clear", "remove",
    }) then
        return nil
    end

    local scopes = {}
    local units = DetectUnits and DetectUnits(normalized) or {}
    for i = 1, #units do scopes[#scopes + 1] = tostring(units[i]) end
    local groups = DetectGroups and DetectGroups(normalized) or {}
    for i = 1, #groups do scopes[#scopes + 1] = "gf_" .. tostring(groups[i]) end
    if #scopes == 0 and ContainsAny(normalized, { "shared", "global", "all frames", "all unitframes", "all unit frames" }) then
        scopes[#scopes + 1] = "shared"
    end
    if #scopes == 0 and ContainsAny(normalized, { "font outline", "font rendering", "text opacity", "text baseline", "text shadow", "shadow strength" }) then
        scopes[#scopes + 1] = "shared"
    end
    if #scopes == 0 and ContainsAny(normalized, {
        "shorten names", "truncate names", "name shortening", "name truncation",
        "truncation style", "clip side", "max name length", "name max length",
        "max chars", "no ellipsis", "without ellipsis", "without dots",
    }) then
        scopes[#scopes + 1] = "shared"
    end
    if #scopes == 0 then return nil end

    local suffix
    local value
    if ContainsAny(normalized, { "font override" }) then
        suffix = "override"
    elseif ContainsAny(normalized, { "font size" }) then
        suffix = "fontSize"
        value = FirstNumber(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, { "font outline" }) then
        suffix = "outline"
    elseif ContainsAny(normalized, { "font rendering" }) then
        suffix = "fontMonochrome"
    elseif ContainsAny(normalized, { "text opacity" }) then
        suffix = "fontTextAlpha"
    elseif ContainsAny(normalized, { "text baseline" }) then
        suffix = "fontBaselineOffset"
    elseif ContainsAny(normalized, { "text shadow" }) then
        suffix = "textBackdrop"
    elseif ContainsAny(normalized, { "shadow strength" }) then
        suffix = "fontShadowStrength"
    elseif ContainsAny(normalized, { "shorten names", "truncate names", "name shortening" }) then
        suffix = "shortenNames"
    elseif ContainsAny(normalized, { "truncation style", "name truncation", "clip side", "name clip side", "truncate side", "shorten name side" }) then
        suffix = "shortenNameClipSide"
    elseif ContainsAny(normalized, { "max name length", "name max length", "max chars", "max characters", "name max characters", "short name length" }) then
        suffix = "shortenNameMaxChars"
        value = FirstNumber(normalized)
        if value == nil then return nil end
    elseif ContainsAny(normalized, { "no ellipsis", "without ellipsis", "without dots", "truncate without dots", "truncate without ellipsis" }) then
        suffix = "shortenNameNoEllipsis"
        if ContainsAny(normalized, { "turn off", "disable", "disabled", "off", "false", "show ellipsis", "show dots", "use dots", "ellipsis on" }) then
            value = false
        elseif ContainsAny(normalized, { "turn on", "enable", "enabled", "on", "true", "hide ellipsis", "hide dots", "remove dots", "without ellipsis", "without dots", "no ellipsis" }) then
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

local function ParseGlobalUIShellPriorityShortcut(normalized)
    local specs = {
        { key = "general.slashMenuSnapEnabled", label = "Menu Edge Snap", terms = { "menu edge snap", "edge snap", "snap menu", "menu snapping" } },
        { key = "general.hideAdvancedMenu", label = "Advanced Menu", terms = { "advanced menu", "hide advanced menu", "show advanced menu" } },
        { key = "general.reduceMotion", label = "Reduce Motion", terms = { "reduce motion", "reduced motion", "less motion" } },
        { key = "general.showNavigationIcons", label = "Navigation Icons", terms = { "navigation icons", "nav icons" } },
        { key = "general.navHoverScale", label = "Navigation Hover Size", terms = { "navigation hover size", "nav hover size", "navigation hover scale", "nav hover scale" } },
        { key = "general.showWelcomeMessage", label = "Welcome Message", terms = { "welcome message", "startup message" } },
        { key = "general.versionCheckEnabled", label = "Version Check", terms = { "version check", "version checker" } },
        { key = "general.showMinimapIcon", label = "Minimap Icon", terms = { "minimap icon", "minimap button" } },
        { key = "general.playTargetSelectLostSounds", label = "Target Sounds", terms = { "target sounds", "target select sound", "target lost sound" } },
        { key = "general.disableBlizzardUnitFrames", label = "Blizzard Unitframes", terms = { "blizzard unitframes", "blizzard unit frames" } },
        { key = "general.hardKillBlizzardPlayerFrame", label = "Fully Hide Blizzard Playerframe", terms = { "fully hide blizzard playerframe", "hard hide blizzard playerframe", "hard kill blizzard playerframe" } },
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
    return (ParseClassPowerRootToggle and ParseClassPowerRootToggle(normalized))
        or (A._ParseClassPowerPreviewResourceShortcut and A._ParseClassPowerPreviewResourceShortcut(normalized))
        or (A._ParseClassPowerWidthModeShortcut and A._ParseClassPowerWidthModeShortcut(normalized))
        or (A._ParseClassPowerVisibilityShortcut and A._ParseClassPowerVisibilityShortcut(normalized))
        or (A._ParseClassPowerDisplayStyleShortcut and A._ParseClassPowerDisplayStyleShortcut(normalized))
        or (A._ParseClassPowerFillDirectionShortcut and A._ParseClassPowerFillDirectionShortcut(normalized))
        or (A._ParseClassPowerEmpoweredComboShortcut and A._ParseClassPowerEmpoweredComboShortcut(normalized))
        or (A._ParseClassPowerRuneTimeShortcut and A._ParseClassPowerRuneTimeShortcut(normalized))
        or (A._ParseClassPowerDisplayBooleanShortcut and A._ParseClassPowerDisplayBooleanShortcut(normalized))
        or (A._ParseClassPowerColorModeShortcut and A._ParseClassPowerColorModeShortcut(normalized))
        or (A._ParseClassPowerDetachedPowerBarDetailShortcut and A._ParseClassPowerDetachedPowerBarDetailShortcut(normalized, raw))
        or (A._ParseClassPowerAltManaShortcut and A._ParseClassPowerAltManaShortcut(normalized, raw))
        or (A._ParseClassPowerPlayerHPDetailShortcut and A._ParseClassPowerPlayerHPDetailShortcut(normalized, raw))
        or (A._ParseClassPowerAnchorShortcut and A._ParseClassPowerAnchorShortcut(normalized))
        or (A._ParseClassPowerPlacementShortcut and A._ParseClassPowerPlacementShortcut(normalized))
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
A._ParseGroupNameTextFastShortcut = ParseGroupNameTextFastShortcut
A._ParseGroupRolePowerFastShortcut = ParseGroupRolePowerFastShortcut
A._ParseGroupPowerBarEnabledFastShortcut = ParseGroupPowerBarEnabledFastShortcut
A._ParseGroupOrderingFastShortcut = ParseGroupOrderingFastShortcut
A._ParseGlobalUiScaleFastShortcut = ParseGlobalUiScaleFastShortcut
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
    if ContainsAny(normalized, {
        "gradient", "color", "colour", "alpha", "opacity", "scale", "width", "height",
        "x offset", "y offset", "anchor", "position", "font size", "text size",
    }) then return nil end

    local broadIntent = ContainsAny(normalized, {
        "prettier", "make prettier", "look better", "make it better", "make them better",
        "less cluttered", "declutter", "cluttered", "too noisy", "too busy",
        "clean this up", "clean that up", "clean it up", "cleaner",
        "easier to read", "more readable", "readable", "hard to read",
    })
    if not broadIntent then return nil end
    if not ContainsAny(normalized, {
        "msuf", "ui", "frame", "frames", "unitframe", "unitframes", "unit frame", "unit frames",
        "bar", "bars", "party", "raid", "mythic", "target", "player", "focus", "boss",
        "aura", "auras", "buff", "buffs", "debuff", "debuffs", "text",
    }) then return nil end

    local area = "that area"
    local examples = "open player; open bars; set target health bar height to 24; set target buff icon count to 8"
    if ContainsAny(normalized, { "raid", "mythic" }) then
        area = "raid frames"
        examples = "open raid frames; set raid debuff filter to RAID_IN_COMBAT; set raid name max chars to 12; set raid frame scale to 90"
    elseif ContainsAny(normalized, { "party" }) then
        area = "party frames"
        examples = "open party frames; set party buff count to 4; set party frame spacing to 8; turn on party range fade"
    elseif ContainsAny(normalized, { "aura", "auras", "buff", "buffs", "debuff", "debuffs" }) then
        area = "auras"
        examples = "open aura filters; set target buff icon count to 8; set target debuff filter to RAID; set party buff icon size to 24"
    elseif ContainsAny(normalized, { "bar", "bars" }) then
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

function A.ParseSimpleChange(text, ctxOverride)
    local raw = Trim(text)
    local normalized = Normalize(raw)
    local ctx = type(ctxOverride) == "table" and ctxOverride or (A.GetContext and A.GetContext() or {})
    if normalized == "" then return nil end
    local parsed = (A._ParseHumanSafetyGuidanceShortcut and A._ParseHumanSafetyGuidanceShortcut(normalized))
        or (P.ParseAmbiguousFontTextColorShortcut and P.ParseAmbiguousFontTextColorShortcut(normalized))
        or (P.ParseAmbiguousColorShortcut and P.ParseAmbiguousColorShortcut(normalized, raw))
        or (P.ParseScopedFontTextColorShortcut and P.ParseScopedFontTextColorShortcut(normalized, raw))
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
        or (A._ParseGlobalUIShellPriorityShortcut and A._ParseGlobalUIShellPriorityShortcut(normalized))
        or (A._ParseBarGradientPriorityShortcut and A._ParseBarGradientPriorityShortcut(normalized))
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
    local humanSafetyParsed = A._ParseHumanSafetyGuidanceShortcut and A._ParseHumanSafetyGuidanceShortcut(normalized)
    if humanSafetyParsed then
        humanSafetyParsed.raw = raw
        humanSafetyParsed.normalized = normalized
        return humanSafetyParsed
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
    local globalUIShellPriorityParsed = A._ParseGlobalUIShellPriorityShortcut and A._ParseGlobalUIShellPriorityShortcut(normalized)
    if globalUIShellPriorityParsed then
        globalUIShellPriorityParsed.raw = raw
        globalUIShellPriorityParsed.normalized = normalized
        return globalUIShellPriorityParsed
    end
    local barGradientPriorityParsed = A._ParseBarGradientPriorityShortcut and A._ParseBarGradientPriorityShortcut(normalized)
    if barGradientPriorityParsed then
        barGradientPriorityParsed.raw = raw
        barGradientPriorityParsed.normalized = normalized
        return barGradientPriorityParsed
    end
    local classPowerPriorityParsed = A._ParseClassPowerPriorityShortcut and A._ParseClassPowerPriorityShortcut(normalized, raw)
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
    local partyTargetedSpellParsed = A._ParsePartyTargetedSpellFastShortcut and A._ParsePartyTargetedSpellFastShortcut(normalized, raw)
    if partyTargetedSpellParsed then
        partyTargetedSpellParsed.raw = raw
        partyTargetedSpellParsed.normalized = normalized
        return partyTargetedSpellParsed
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
    if ContainsAny(normalized, { "alpha", "opacity", "transparency", "transparent", "opaque" }) then
        local opacityUnits = DetectUnits(normalized)
        local opacityGroups = DetectGroups(normalized)
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
    local actionExplainParsed = P.ParseRegistryActionExplainShortcut and P.ParseRegistryActionExplainShortcut(normalized, raw)
    if actionExplainParsed then
        actionExplainParsed.raw = raw
        actionExplainParsed.normalized = normalized
        return actionExplainParsed
    end
    local editModeControlParsed = A._ParseEditModeHUDControl and A._ParseEditModeHUDControl(normalized)
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
        or (P.ParseBarGradientRegistryShortcut and P.ParseBarGradientRegistryShortcut(normalized))
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
        local statusTextParsed = A._ParseGlobalStatusTextStateShortcut and A._ParseGlobalStatusTextStateShortcut(normalized)
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
        local classPowerTextOffsetParsed = A._ParseClassPowerTextOffsetShortcut and A._ParseClassPowerTextOffsetShortcut(normalized)
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
