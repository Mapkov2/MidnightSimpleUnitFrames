local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Registry = Registry
A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- Diagnostics registry domain.
-- Read-only assistant actions that summarize state for support and self-check workflows.
-- Keep this file observational; repair actions belong in explicit workflows with confirmation.
local Registry = C.Registry
local UNIT_LABELS = C.UNIT_LABELS
local AddAliasesForUnit = C.AddAliasesForUnit
local GeneralDB = C.GeneralDB
local BarsDB = C.BarsDB or function() return (_G.MSUF_DB and _G.MSUF_DB.bars) or {} end
local GameplayDB = C.GameplayDB or function() return (_G.MSUF_DB and _G.MSUF_DB.gameplay) or {} end
local UnitDB = C.UnitDB
local GroupDB = C.GroupDB
local AuraSharedBool = C.AuraSharedBool
local AuraModel = C.AuraModel
local AuraUnitEnabled = C.AuraUnitEnabled
local AuraLaneShown = C.AuraLaneShown
local AuraFiltersEnabled = C.AuraFiltersEnabled
local AuraReadFilter = C.AuraReadFilter
local GFAuraLaneShown = C.GFAuraLaneShown
local GFReadAuraValue = C.GFReadAuraValue
local GlobalScopeLabel = C.GlobalScopeLabel
local GlobalScopeHasOverride = C.GlobalScopeHasOverride
local GlobalScopeRead = C.GlobalScopeRead
local CASTBAR_KEYS = C.CASTBAR_KEYS
local GetCastbarBackend = C.GetCastbarBackend

local function ActiveProfileName()
    if A and type(A.ActiveProfileName) == "function" then return A.ActiveProfileName() end
    local name = tostring(_G.MSUF_ActiveProfile or "Default")
    if name == "" then return "Default" end
    return name
end

A.Workflow = A.Workflow or {}
A.Workflow.SupportLinks = {
    discord = { title = "Discord", parts = { "h", "tt", "ps", "://discord.gg/2Gf9b2Wprz" } },
    patreon = { title = "Patreon", parts = { "h", "tt", "ps", "://www.patreon.com/cw/MidnightSimpleUnitframes" } },
    paypal = { title = "PayPal", parts = { "h", "tt", "ps", "://www.paypal.com/ncp/payment/H3N2P87S53KBQ" } },
    kofi = { title = "Ko-fi", parts = { "h", "tt", "ps", "://ko-fi.com/midnightsimpleunitframes#linkModal" } },
    github = { title = "GitHub", parts = { "h", "tt", "ps", "://github.com/Mapkov2/MidnightSimpleUnitFrames" } },
}

function A.Workflow.SupportURL(key)
    local spec = A.Workflow.SupportLinks and A.Workflow.SupportLinks[key]
    if type(spec) ~= "table" or type(spec.parts) ~= "table" then return nil end
    return table.concat(spec.parts, "")
end

function A.Workflow.CopyText(title, value, help)
    if type(value) ~= "string" or value == "" then return false end
    if type(_G.MSUF_ShowCopyLink) == "function" then
        _G.MSUF_ShowCopyLink(title or "MSUF", value)
        return true
    end
    if A and type(A.ShowLargeTextPanel) == "function" then
        A.ShowLargeTextPanel({
            kind = "export",
            title = title or "MSUF",
            help = help or "Copy this value.",
            text = value,
            status = "Press Select all, then Ctrl+C.",
        })
        return true
    end
    return false
end

function A.Workflow.SupportSummaryText()
    local lines = { "MSUF support links:" }
    for _, key in ipairs({ "discord", "patreon", "paypal", "kofi", "github" }) do
        local spec = A.Workflow.SupportLinks[key]
        local value = A.Workflow.SupportURL(key)
        if spec and value then lines[#lines + 1] = "- " .. tostring(spec.title) .. ": " .. value end
    end
    return table.concat(lines, "\n")
end

function A.Workflow.StatusText()
    local lines = {}
    local version = (type(_G.GetAddOnMetadata) == "function" and _G.GetAddOnMetadata(addonName, "Version"))
        or (MSUF and (MSUF.version or MSUF.Version))
        or M.version
        or M.VERSION
        or "unknown"
    local locale = type(_G.GetLocale) == "function" and _G.GetLocale() or "unknown"
    local combat = ((_G.InCombatLockdown and _G.InCombatLockdown()) or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) and "yes" or "no"
    local edit = "unknown"
    if M and type(M.IsMSUFEditModeActive) == "function" then
        edit = M.IsMSUFEditModeActive(true) and "on" or "off"
    elseif _G.MSUF_UnitEditModeActive ~= nil then
        edit = _G.MSUF_UnitEditModeActive == true and "on" or "off"
    end
    lines[#lines + 1] = "MSUF status"
    lines[#lines + 1] = "Version: " .. tostring(version)
    lines[#lines + 1] = "Locale: " .. tostring(locale)
    lines[#lines + 1] = "Active page: " .. tostring((M and M.activeKey) or "unknown")
    lines[#lines + 1] = "Active profile: " .. ActiveProfileName()
    lines[#lines + 1] = "Combat lockdown: " .. combat
    lines[#lines + 1] = "Edit mode: " .. edit
    lines[#lines + 1] = "Assistant registry: " .. tostring(#(Registry.settings or {})) .. " settings, " .. tostring(#(Registry.actions or {})) .. " actions"
    local parser = A.Parser or {}
    local actionAliasCandidates = tonumber(parser._lastRegistryActionAliasCandidateCount)
    local actionAliasTotal = tonumber(parser._lastRegistryActionAliasTotalCount)
    if actionAliasCandidates and actionAliasTotal and actionAliasTotal > 0 then
        lines[#lines + 1] = "Registry action alias candidates: " .. tostring(actionAliasCandidates) .. "/" .. tostring(actionAliasTotal)
    end
    lines[#lines + 1] = "Queued Assistant changes: " .. tostring(type(A.queuedPlans) == "table" and #A.queuedPlans or 0)
    local jobSummary = A.GetJobSummary and A.GetJobSummary() or nil
    if type(jobSummary) == "table" then
        local detail = ""
        if type(jobSummary.labels) == "table" and #jobSummary.labels > 0 then detail = " (" .. table.concat(jobSummary.labels, ", ") .. ")" end
        lines[#lines + 1] = "Assistant jobs: " .. tostring(tonumber(jobSummary.count) or 0) .. detail
    end
    if A.PerformanceWarmupStatusText then
        lines[#lines + 1] = "Assistant warmup: " .. A.PerformanceWarmupStatusText()
    end
    local perf = A.GetLastPerfSample and A.GetLastPerfSample() or nil
    if type(perf) == "table" then
        lines[#lines + 1] = "Last Assistant timing: " .. tostring(perf.label or "assistant") .. " " .. tostring(math.floor((tonumber(perf.ms) or 0) + 0.5)) .. " ms"
    end
    local slow = A.GetLastSlowPerfSample and A.GetLastSlowPerfSample() or nil
    if type(slow) == "table" then
        lines[#lines + 1] = "Last slow Assistant timing: " .. tostring(slow.label or "assistant") .. " " .. tostring(math.floor((tonumber(slow.ms) or 0) + 0.5)) .. " ms"
    end
    return table.concat(lines, "\n")
end

function A.Workflow.HelpText()
    return table.concat({
        "Assistant command examples:",
        "- show profile summary",
        "- export colors profile",
        "- browse Wago profiles",
        "- start edit mode",
        "- hide player name",
        "- move target 10 down",
        "- copy player layout to target",
        "- reset target position",
        "- diagnose target castbar",
        "- diagnose raid frames",
        "- what can I change here",
        "- copy Discord link",
        "- show MSUF status",
    }, "\n")
end

local function LowOpacity(value)
    value = tonumber(value)
    return value ~= nil and value <= 0.05
end

local function AddFixChoice(choices, key, value, label, valueLabel)
    if type(choices) ~= "table" or type(key) ~= "string" or key == "" then return end
    if not (Registry and type(Registry.GetSetting) == "function") then return end
    local setting = Registry:GetSetting(key)
    if not setting then return end
    choices[#choices + 1] = {
        setting = setting,
        value = value,
        label = label,
        valueLabel = valueLabel,
        diagnosticFix = true,
    }
end

local function AddActionChoice(choices, key, args, label, summary, confirmRequired, diagnosticFix)
    if type(choices) ~= "table" or type(key) ~= "string" or key == "" then return end
    if not (Registry and type(Registry.GetAction) == "function") then return end
    local action = Registry:GetAction(key)
    if not action then return end
    choices[#choices + 1] = {
        action = action,
        args = type(args) == "table" and args or {},
        label = label,
        summary = summary,
        confirmRequired = confirmRequired,
        diagnosticFix = diagnosticFix == true,
    }
end

local function AppendFixChoices(text, choices)
    if type(choices) ~= "table" or #choices == 0 then return text end
    local choiceText
    if A and type(A.SetPendingChoices) == "function" then
        choiceText = A.SetPendingChoices(choices)
    elseif A and type(A._ChoiceTextForTest) == "function" then
        A.pendingChoices = choices
        choiceText = A._ChoiceTextForTest(choices)
    end
    if type(choiceText) == "string" and choiceText ~= "" then
        return tostring(text or "") .. "\n\nSuggested fixes:\n" .. choiceText
    end
    return text
end

local function UnitDefaultWidth(unit)
    if unit == "boss" or unit == "focus" then return 180 end
    return 275
end

local function UnitDefaultHeight(unit)
    if unit == "boss" or unit == "focus" then return 30 end
    return 40
end

local function GroupDefaultWidth(scope)
    return scope == "party" and 120 or 80
end

local function GroupDefaultHeight(scope)
    return scope == "party" and 40 or 32
end

local LOAD_CONDITION_FIXES = {
    { key = "loadCondHideMounted", label = "Hide Mounted" },
    { key = "loadCondHideOutOfCombat", label = "Hide Out Of Combat" },
    { key = "loadCondHideSolo", label = "Hide Solo" },
    { key = "loadCondHideInVehicle", label = "Hide In Vehicle" },
    { key = "loadCondHideInGroup", label = "Hide In Group" },
    { key = "loadCondHideInInstance", label = "Hide In Instance" },
    { key = "loadCondHideResting", label = "Hide Resting" },
    { key = "loadCondHideInCombat", label = "Hide In Combat" },
    { key = "loadCondHideStealthed", label = "Hide Stealthed" },
}

local function SettingPreviewLines(settings, limit)
    local lines = {}
    local seen = {}
    limit = tonumber(limit) or 8
    for i = 1, #(settings or {}) do
        local setting = settings[i]
        local label = setting and setting.label
        if type(label) == "string" and label ~= "" and not seen[label] then
            lines[#lines + 1] = "- " .. label
            seen[label] = true
            if #lines >= limit then break end
        end
    end
    return lines
end

local function ScopeHelpExamples(frameType, unit, group, page)
    if frameType == "editMode" then
        return {
            "start edit mode",
            "show edit mode grid",
            "set edit mode grid spacing to 20",
            "turn on edit mode snap",
            "cancel edit mode",
        }
    end
    if frameType == "castbar" or page == "opt_castbar" then
        return {
            "show target castbar",
            "move player castbar 20 down",
            "set castbar height to 28",
            "reset castbar colors",
            "diagnose target castbar",
        }
    end
    if frameType == "group" or frameType == "groupAura" or group then
        local scope = group or "raid"
        return {
            "show " .. scope .. " group frames",
            "make " .. scope .. " width 90",
            "set " .. scope .. " growth right",
            "blacklist raid buffs category for " .. scope .. " buffs",
            "diagnose " .. scope .. " frames",
        }
    end
    if frameType == "profiles" or page == "profiles" then
        return {
            "show profile summary",
            "export current profile",
            "import profile",
            "copy current profile to Backup",
            "switch profile to Healer",
        }
    end
    if frameType == "aura" or page == "auras3" then
        return {
            "show player buffs",
            "set target debuff size 32",
            "apply clean aura preset",
            "blacklist spell 12345 for player auras",
            "show raid buff category blacklist",
        }
    end
    local subject = unit or "player"
    return {
        "show " .. subject .. " frame",
        "hide " .. subject .. " name",
        "make " .. subject .. " width 300",
        "move " .. subject .. " 20 down",
        "reset " .. subject .. " position",
    }
end

function A.Workflow.ScopeHelpText(args)
    args = args or {}
    local frameType = args.frameType
    local unit = args.unit
    local group = args.group
    local page = args.page
    local label = args.label or (unit and UNIT_LABELS[unit]) or (group and UNIT_LABELS[group]) or frameType or page or "current area"
    local filter = {}
    if unit then filter.unit = unit end
    if group then filter.unit = group end
    if frameType then filter.frameType = frameType end
    local settings = Registry and Registry.FindSettings and Registry:FindSettings(filter) or {}
    local lines = { "Assistant controls for " .. tostring(label) .. ":" }
    if #settings > 0 then
        lines[#lines + 1] = "Registered settings: " .. tostring(#settings)
        local preview = SettingPreviewLines(settings, 8)
        for i = 1, #preview do lines[#lines + 1] = preview[i] end
    else
        lines[#lines + 1] = "No narrow setting list matched, but the Assistant can still navigate and run known actions."
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Try:"
    local examples = ScopeHelpExamples(frameType, unit, group, page)
    for i = 1, #examples do lines[#lines + 1] = "- " .. examples[i] end
    return table.concat(lines, "\n")
end

local function UnitFrameDiagnosticText(unit)
    unit = UNIT_LABELS[unit] and unit or "player"
    local conf = UnitDB(unit)
    local label = UNIT_LABELS[unit] or unit
    local issues = {}
    local choices = {}
    if conf.enabled == false then
        issues[#issues + 1] = label .. " frame is disabled. Say 'show " .. tostring(unit) .. " frame' to enable it."
        AddFixChoice(choices, unit .. ".enabled", true, "Show " .. label .. " frame")
    end
    local width = tonumber(conf.width)
    local height = tonumber(conf.height)
    if width ~= nil and width < 10 then
        issues[#issues + 1] = label .. " width is extremely small. Say 'make " .. tostring(unit) .. " width " .. tostring(UnitDefaultWidth(unit)) .. "'."
        AddFixChoice(choices, unit .. ".width", UnitDefaultWidth(unit), "Set " .. label .. " width to " .. tostring(UnitDefaultWidth(unit)))
    end
    if height ~= nil and height < 6 then
        issues[#issues + 1] = label .. " height is extremely small. Say 'make " .. tostring(unit) .. " height " .. tostring(UnitDefaultHeight(unit)) .. "'."
        AddFixChoice(choices, unit .. ".height", UnitDefaultHeight(unit), "Set " .. label .. " height to " .. tostring(UnitDefaultHeight(unit)))
    end
    if LowOpacity(conf.hpBarAlpha) then
        issues[#issues + 1] = label .. " HP bar opacity is near zero. It may be hard to see. Set HP bar opacity back to 100%."
        AddFixChoice(choices, unit .. ".hpBarAlpha", 1, "Set " .. label .. " HP bar opacity to 100%")
    end
    for i = 1, #LOAD_CONDITION_FIXES do
        local spec = LOAD_CONDITION_FIXES[i]
        if conf[spec.key] == true then
            issues[#issues + 1] = label .. " has load condition '" .. spec.label .. "' enabled; the frame can hide when that condition matches."
            AddFixChoice(choices, unit .. "." .. spec.key, false, "Turn off " .. label .. " " .. spec.label)
        end
    end
    if unit == "pet" then
        issues[#issues + 1] = "Pet frames also require an active pet; this diagnostic only checks MSUF settings."
    elseif unit == "targettarget" then
        issues[#issues + 1] = "Target of Target only appears when your target has a target."
    elseif unit == "focustarget" then
        issues[#issues + 1] = "Focus Target only appears when your focus has a target."
    elseif unit == "boss" then
        issues[#issues + 1] = "Boss frames also require boss units from the encounter or preview context."
    end
    if #issues == 0 then
        return label .. " frame is enabled in MSUF and has no obvious hidden-size or opacity problem. Open " .. label .. " settings or Edit Mode to inspect position."
    end
    return AppendFixChoices(table.concat(issues, "\n"), choices)
end

local function GroupFrameDiagnosticText(scope)
    scope = scope == "mythicraid" and "mythicraid" or (scope == "raid" and "raid" or "party")
    local conf = GroupDB(scope)
    local label = UNIT_LABELS[scope] or scope
    local issues = {}
    local choices = {}
    if conf.enabled ~= true then
        issues[#issues + 1] = label .. " Group Frames are disabled. Say 'show " .. tostring(scope) .. " group frames' to enable them."
        AddFixChoice(choices, "gf_" .. scope .. ".enabled", true, "Show " .. label .. " group frames")
    end
    if scope == "party" and conf.showSolo ~= true then
        issues[#issues + 1] = "Party frames are set to hide while solo. This is normal outside a group unless Show While Solo is enabled."
        AddFixChoice(choices, "gf_party.showSolo", true, "Show Party frames while solo")
    end
    local width = tonumber(conf.width)
    local height = tonumber(conf.height)
    if width ~= nil and width < 10 then
        issues[#issues + 1] = label .. " frame width is extremely small. Say 'make " .. tostring(scope) .. " width " .. tostring(GroupDefaultWidth(scope)) .. "'."
        AddFixChoice(choices, "gf_" .. scope .. ".width", GroupDefaultWidth(scope), "Set " .. label .. " frame width to " .. tostring(GroupDefaultWidth(scope)))
    end
    if height ~= nil and height < 6 then
        issues[#issues + 1] = label .. " frame height is extremely small. Say 'make " .. tostring(scope) .. " height " .. tostring(GroupDefaultHeight(scope)) .. "'."
        AddFixChoice(choices, "gf_" .. scope .. ".height", GroupDefaultHeight(scope), "Set " .. label .. " frame height to " .. tostring(GroupDefaultHeight(scope)))
    end
    if LowOpacity(conf.hpBarAlpha) then
        issues[#issues + 1] = label .. " HP bar opacity is near zero. It may be hard to see. Set HP bar opacity back to 100%."
        AddFixChoice(choices, "gf_" .. scope .. ".hpBarAlpha", 1, "Set " .. label .. " HP bar opacity to 100%")
    end
    if conf.hideInClientScene == true then
        issues[#issues + 1] = label .. " frames hide during client scenes by setting; that only applies during those scenes."
        AddFixChoice(choices, "gf_" .. scope .. ".hideInClientScene", false, "Turn off " .. label .. " Hide During Client Scene")
    end
    if #issues == 0 then
        return label .. " Group Frames are enabled and have no obvious hidden-size or opacity problem. Open Group Frames or Edit Mode to inspect position and current group context."
    end
    return AppendFixChoices(table.concat(issues, "\n"), choices)
end

local function AuraLaneLabel(lane)
    return lane == "debuff" and "Debuffs" or "Buffs"
end

local function AuraDiagnosticLanes(kind)
    if kind == "buff" or kind == "buffs" then return { "buff" } end
    if kind == "debuff" or kind == "debuffs" then return { "debuff" } end
    return { "buff", "debuff" }
end

local function SafeSettingValue(key)
    if not (Registry and type(Registry.GetSetting) == "function") then return nil end
    local setting = Registry:GetSetting(key)
    if not (setting and type(setting.get) == "function") then return nil end
    local ok, value = pcall(setting.get)
    if ok then return value end
    return nil
end

local UNIT_AURA_FILTER_WARNINGS = {
    buff = {
        { key = "onlyMine", label = "only your buffs" },
        { key = "raid", label = "only raid buffs" },
        { key = "cancelable", label = "only cancelable buffs" },
        { key = "notCancelable", label = "only non-cancelable buffs" },
    },
    debuff = {
        { key = "onlyMine", label = "only your debuffs" },
        { key = "raid", label = "only raid debuffs" },
        { key = "includeDispellable", label = "only dispellable debuffs" },
        { key = "notDispellable", label = "only non-dispellable debuffs" },
        { key = "boss", label = "only boss debuffs" },
    },
}

local function AddUnitAuraFilterDiagnostics(scope, label, lane, issues, choices)
    local filtersOn = true
    if AuraFiltersEnabled then
        local ok, value = pcall(AuraFiltersEnabled, scope)
        if ok and value == false then filtersOn = false end
    end
    if filtersOn == false then return end

    local laneLabel = AuraLaneLabel(lane)
    local exclusive
    if AuraReadFilter then
        local ok, value = pcall(AuraReadFilter, scope, lane, "exclusive", "none")
        if ok then exclusive = value end
    end
    if exclusive == nil then exclusive = SafeSettingValue("auras3." .. scope .. "." .. lane .. ".filter.exclusive") end
    exclusive = tostring(exclusive or "none")
    if exclusive ~= "none" and exclusive ~= "" then
        issues[#issues + 1] = label .. " " .. laneLabel .. " exclusive filter is set to " .. exclusive .. ", which can hide normal auras."
        AddFixChoice(choices, "auras3." .. scope .. "." .. lane .. ".filter.exclusive", "none", "Set " .. label .. " " .. laneLabel .. " exclusive filter to none")
    end

    local specs = UNIT_AURA_FILTER_WARNINGS[lane] or {}
    for i = 1, #specs do
        local spec = specs[i]
        local key = "auras3." .. scope .. "." .. lane .. ".filter." .. spec.key
        if SafeSettingValue(key) == true then
            issues[#issues + 1] = label .. " " .. laneLabel .. " filter is limited to " .. spec.label .. "."
            AddFixChoice(choices, key, false, "Turn off " .. label .. " " .. laneLabel .. " " .. spec.label .. " filter")
        end
    end
end

local function AddUnitAuraBlacklistDiagnostics(scope, label, issues, choices)
    local ignoreKey = "auras3." .. scope .. ".overrideIgnore"
    if SafeSettingValue(ignoreKey) == true then
        issues[#issues + 1] = label .. " uses a custom Aura ignore list. A specific spell may be hidden there."
        AddFixChoice(choices, ignoreKey, false, "Turn off " .. label .. " custom Aura ignore list")
    end

    local Model = AuraModel and AuraModel() or nil
    if not (Model and type(Model.BlacklistSummary) == "function") then return end
    local ok, summary = pcall(Model.BlacklistSummary, scope)
    summary = ok and tostring(summary or "") or ""
    if summary ~= "" and not summary:find("No blacklisted", 1, true) then
        issues[#issues + 1] = label .. " Aura blacklist has entries. A specific missing aura may be blacklisted."
        AddActionChoice(choices, "aura_blacklist_summary", { scope = scope }, "Show " .. label .. " aura blacklist", "Shows the current blacklist entries for this aura scope.", nil, true)
        AddActionChoice(choices, "aura_blacklist_clear_spells", { scope = scope }, "Allow all " .. label .. " aura spells", "Clears every spell entry from this aura blacklist scope.", nil, true)
    end
end

local function GroupAuraDefaultMax(lane)
    return lane == "buff" and 6 or 6
end

local function AddGroupAuraFilterDiagnostics(scope, label, lane, issues, choices)
    local laneLabel = AuraLaneLabel(lane)
    local maxKey = "gf_" .. scope .. ".auras." .. lane .. ".max"
    local maxValue = SafeSettingValue(maxKey)
    if tonumber(maxValue) ~= nil and tonumber(maxValue) <= 0 then
        issues[#issues + 1] = label .. " " .. laneLabel .. " max icon count is zero."
        AddFixChoice(choices, maxKey, GroupAuraDefaultMax(lane), "Set " .. label .. " " .. laneLabel .. " max icons to " .. tostring(GroupAuraDefaultMax(lane)))
    end

    local sizeKey = "gf_" .. scope .. ".auras." .. lane .. ".size"
    local sizeValue = SafeSettingValue(sizeKey)
    if tonumber(sizeValue) ~= nil and tonumber(sizeValue) < 8 then
        local defaultSize = lane == "buff" and 22 or 20
        issues[#issues + 1] = label .. " " .. laneLabel .. " icon size is extremely small."
        AddFixChoice(choices, sizeKey, defaultSize, "Set " .. label .. " " .. laneLabel .. " icon size to " .. tostring(defaultSize))
    end

    local tokenKey = "gf_" .. scope .. ".auras." .. lane .. ".filterToken"
    local token = SafeSettingValue(tokenKey)
    token = tostring(token or "")
    if token ~= "" and token ~= "ALL" then
        issues[#issues + 1] = label .. " " .. laneLabel .. " filter is set to " .. token .. ", so normal auras outside that filter may be hidden."
        AddFixChoice(choices, tokenKey, "ALL", "Show all " .. label .. " " .. laneLabel)
    elseif GFReadAuraValue then
        local ok, raw = pcall(GFReadAuraValue, scope, lane, "filterToken", nil)
        raw = ok and raw or nil
        if raw ~= nil and tostring(raw) ~= "ALL" then
            issues[#issues + 1] = label .. " " .. laneLabel .. " filter is set to " .. tostring(raw) .. ", so normal auras outside that filter may be hidden."
            AddFixChoice(choices, tokenKey, "ALL", "Show all " .. label .. " " .. laneLabel)
        end
    end

    if A and type(A.GroupAuraCategorySummary) == "function" then
        local ok, summary = pcall(A.GroupAuraCategorySummary, scope, lane)
        summary = ok and tostring(summary or "") or ""
        if summary ~= "" and not summary:find("No blacklisted", 1, true) then
            issues[#issues + 1] = label .. " " .. laneLabel .. " category blacklist has entries."
            AddActionChoice(choices, "aura_group_category_blacklist_summary", { scope = scope, lane = lane }, "Show " .. label .. " " .. laneLabel .. " category blacklist", "Shows the public aura categories currently blocked for this group scope.", nil, true)
            AddActionChoice(choices, "aura_group_category_blacklist_clear", { scope = scope, lane = lane }, "Allow all " .. label .. " " .. laneLabel .. " categories", "Clears the public aura category blacklist for this group scope and lane.", nil, true)
        end
    end
end

local function AuraDiagnosticText(args)
    args = type(args) == "table" and args or {}
    local scope = tostring(args.scope or "target")
    local lanes = AuraDiagnosticLanes(args.lane)
    local issues = {}
    local choices = {}

    if scope == "party" or scope == "raid" or scope == "mythicraid" then
        local conf = GroupDB(scope)
        local label = UNIT_LABELS[scope] or scope
        if conf.enabled ~= true then
            issues[#issues + 1] = label .. " Group Frames are disabled, so their auras cannot be visible."
            AddFixChoice(choices, "gf_" .. scope .. ".enabled", true, "Show " .. label .. " group frames")
        end
        if scope == "party" and conf.showSolo ~= true then
            issues[#issues + 1] = "Party frames hide while solo unless Show While Solo is enabled."
            AddFixChoice(choices, "gf_party.showSolo", true, "Show Party frames while solo")
        end
        for i = 1, #lanes do
            local lane = lanes[i]
            if GFAuraLaneShown and not GFAuraLaneShown(scope, lane) then
                issues[#issues + 1] = label .. " " .. AuraLaneLabel(lane) .. " are disabled or still owned by Blizzard aura rendering."
                AddFixChoice(choices, "gf_" .. scope .. ".auras." .. lane .. ".enabled", true, "Show " .. label .. " " .. AuraLaneLabel(lane))
            end
            AddGroupAuraFilterDiagnostics(scope, label, lane, issues, choices)
        end
        if #issues == 0 then
            return label .. " Group Auras diagnostic: requested aura lanes are enabled in MSUF, max icon counts are above zero, and no obvious category/filter blocker was found. If they are still missing, check active group context and whether the aura exists on party/raid members."
        end
        return AppendFixChoices(label .. " Group Auras diagnostic:\n" .. table.concat(issues, "\n"), choices)
    end

    if scope ~= "player" and scope ~= "target" and scope ~= "focus" and scope ~= "boss" then scope = "target" end
    local label = UNIT_LABELS[scope] or scope
    local root = Registry:GetSetting("auras3.enabled")
    if root and type(root.get) == "function" and root.get() == false then
        issues[#issues + 1] = "Unit Auras are disabled globally."
        AddFixChoice(choices, "auras3.enabled", true, "Turn on Unit Auras")
    end
    if AuraUnitEnabled and not AuraUnitEnabled(scope) then
        issues[#issues + 1] = label .. " Unit Auras are disabled."
        for i = 1, #lanes do
            AddFixChoice(choices, "auras3." .. scope .. "." .. lanes[i] .. ".visible", true, "Show " .. label .. " " .. AuraLaneLabel(lanes[i]))
        end
    end
    for i = 1, #lanes do
        local lane = lanes[i]
        local sharedKey = lane == "buff" and "auras3.shared.showBuffs" or "auras3.shared.showDebuffs"
        local shared = Registry:GetSetting(sharedKey)
        if shared and type(shared.get) == "function" and shared.get() == false then
            issues[#issues + 1] = "Shared Aura " .. AuraLaneLabel(lane) .. " are turned off."
            AddFixChoice(choices, sharedKey, true, "Show shared Aura " .. AuraLaneLabel(lane))
        end
        if AuraLaneShown and not AuraLaneShown(scope, lane) then
            issues[#issues + 1] = label .. " " .. AuraLaneLabel(lane) .. " are hidden or their max icon count is zero."
            AddFixChoice(choices, "auras3." .. scope .. "." .. lane .. ".visible", true, "Show " .. label .. " " .. AuraLaneLabel(lane))
        end
        AddUnitAuraFilterDiagnostics(scope, label, lane, issues, choices)
    end
    local customFilters = Registry:GetSetting("auras3." .. scope .. ".overrideFilters")
    if customFilters and type(customFilters.get) == "function" and customFilters.get() == true then
        issues[#issues + 1] = label .. " uses custom Aura filters. If only some auras are missing, inspect that scope's filter settings or turn custom filters off."
        AddFixChoice(choices, "auras3." .. scope .. ".overrideFilters", false, "Turn off " .. label .. " custom Aura filters")
    end
    AddUnitAuraBlacklistDiagnostics(scope, label, issues, choices)
    if #issues == 0 then
        return label .. " Auras diagnostic: requested aura lanes are enabled in MSUF and no obvious filter, custom ignore, or blacklist blocker was found. If a specific aura is still missing, check whether that aura is currently active and allowed by Blizzard/unit ownership rules."
    end
    return AppendFixChoices(label .. " Auras diagnostic:\n" .. table.concat(issues, "\n"), choices)
end

local function CountKeys(tbl)
    local count = 0
    if type(tbl) ~= "table" then return 0 end
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

local function FirstExistingProfile(profiles, preferred)
    if type(profiles) ~= "table" then return nil end
    if type(preferred) == "string" and type(profiles[preferred]) == "table" then return preferred end
    if type(profiles.Default) == "table" then return "Default" end
    local names = {}
    for name, profile in pairs(profiles) do
        if type(name) == "string" and type(profile) == "table" then names[#names + 1] = name end
    end
    table.sort(names, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
    return names[1]
end

local function CharProfileState()
    local global = type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or nil
    local chars = global and type(global.char) == "table" and global.char or nil
    local key
    if type(_G.MSUF_GetCharKey) == "function" then
        key = _G.MSUF_GetCharKey()
    elseif type(_G.UnitName) == "function" and type(_G.GetRealmName) == "function" then
        key = tostring(_G.UnitName("player") or "Player") .. "-" .. tostring(_G.GetRealmName() or "Realm")
    end
    local char = key and chars and chars[key] or nil
    return key, type(char) == "table" and char or nil
end

local function ClearBrokenSpecProfileMappings()
    local global = type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or nil
    local profiles = global and type(global.profiles) == "table" and global.profiles or nil
    local _, char = CharProfileState()
    local map = char and type(char.specProfileMap) == "table" and char.specProfileMap or nil
    if type(profiles) ~= "table" or type(map) ~= "table" then return 0 end
    local broken = {}
    for specID, profileName in pairs(map) do
        if type(profileName) == "string" and type(profiles[profileName]) ~= "table" then broken[#broken + 1] = specID end
    end
    table.sort(broken, function(a, b) return tostring(a) < tostring(b) end)
    for i = 1, #broken do
        local specID = broken[i]
        if type(_G.MSUF_SetSpecProfile) == "function" then
            _G.MSUF_SetSpecProfile(specID, nil)
        else
            map[specID] = nil
        end
    end
    return #broken
end

local function ProfileDiagnosticText()
    local global = type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or nil
    local profiles = global and type(global.profiles) == "table" and global.profiles or nil
    local active = ActiveProfileName()
    local activeTable = profiles and profiles[active] or nil
    local charKey, char = CharProfileState()
    local map = char and type(char.specProfileMap) == "table" and char.specProfileMap or nil
    local brokenSpecs = 0
    if map and profiles then
        for _, profileName in pairs(map) do
            if type(profileName) == "string" and type(profiles[profileName]) ~= "table" then brokenSpecs = brokenSpecs + 1 end
        end
    end

    local lines = {
        "Profile diagnostic:",
        "Active profile: " .. tostring(active),
        "Profiles loaded: " .. tostring(CountKeys(profiles)),
        "Active profile table: " .. (type(activeTable) == "table" and "ok" or "missing"),
        "Active DB reference: " .. ((type(activeTable) == "table" and _G.MSUF_DB == activeTable) and "ok" or "check"),
        "Character profile key: " .. tostring(charKey or "unknown"),
        "Spec auto-switch: " .. ((char and char.specAutoSwitch == true) and "on" or "off"),
        "Spec mappings: " .. tostring(CountKeys(map)),
    }
    if brokenSpecs > 0 then
        lines[#lines + 1] = "Broken spec mappings: " .. tostring(brokenSpecs) .. " point to missing profiles."
    end
    lines[#lines + 1] = "Profile staging:"
    lines[#lines + 1] = "- Create/copy name: " .. tostring((M and M.profileCreateCopyName ~= "" and M.profileCreateCopyName) or "empty")
    lines[#lines + 1] = "- Export kind: " .. tostring((M and M.profileExportKind) or "all")
    lines[#lines + 1] = "- Import string: " .. (((M and type(M.profileImportString) == "string" and M.profileImportString ~= "") and "present") or "empty")
    lines[#lines + 1] = "- Import as new profile: " .. ((M and M.profileImportCreateNew == true) and "on" or "off")
    lines[#lines + 1] = "Available helpers:"
    lines[#lines + 1] = "- create/switch/copy/delete/rename: "
        .. ((type(_G.MSUF_CreateProfile) == "function") and "create " or "")
        .. ((type(_G.MSUF_SwitchProfile) == "function") and "switch " or "")
        .. ((type(_G.MSUF_CopyProfile) == "function") and "copy " or "")
        .. ((type(_G.MSUF_DeleteProfile) == "function") and "delete " or "")
        .. ((type(_G.MSUF_RenameProfile) == "function") and "rename" or "")
    lines[#lines + 1] = "- import/export: "
        .. ((type(_G.MSUF_ImportFromString) == "function") and "import " or "")
        .. ((type(_G.MSUF_ExportSelectionToString) == "function") and "export" or "")
    if type(activeTable) ~= "table" then
        lines[#lines + 1] = "Next safe fix: switch to an existing profile or create/copy a new profile before importing."
    elseif brokenSpecs > 0 then
        lines[#lines + 1] = "Next safe fix: clear or reassign the broken spec profile mappings."
    else
        lines[#lines + 1] = "No obvious profile storage problem was found."
    end
    local choices = {}
    if type(activeTable) ~= "table" then
        local fallback = FirstExistingProfile(profiles)
        if fallback then
            AddActionChoice(choices, "switch_profile", { name = fallback }, "Switch to existing profile " .. tostring(fallback), "Rebinds MSUF to an existing profile after a missing active-profile reference.", nil, true)
        end
    elseif _G.MSUF_DB ~= activeTable then
        AddActionChoice(choices, "switch_profile", { name = active }, "Rebind active profile " .. tostring(active), "Runs the real profile switch helper for the current active profile again.", nil, true)
    end
    if brokenSpecs > 0 then
        AddActionChoice(choices, "clear_broken_spec_profile_mappings", {}, "Clear broken spec profile mappings", "Removes spec profile assignments that point to profiles that no longer exist.", nil, true)
    end
    AddActionChoice(choices, "open_page", { page = "profiles", label = "Profiles" }, "Open Profiles page", "Opens the real Profiles page for review.")
    return AppendFixChoices(table.concat(lines, "\n"), choices)
end

local function ClassPowerDiagnosticText()
    local bars = BarsDB()
    local player = UnitDB("player")
    local issues = {}
    local choices = {}
    if bars.showClassPower == false then
        issues[#issues + 1] = "Class Resources are disabled. Say 'turn on class resources' to enable them."
        AddFixChoice(choices, "bars.showClassPower", true, "Turn on Class Resources")
    end
    if tonumber(bars.classPowerHeight) ~= nil and tonumber(bars.classPowerHeight) < 1 then
        issues[#issues + 1] = "Class Resource height is extremely small. Say 'set class resource height to 4'."
        AddFixChoice(choices, "bars.classPowerHeight", 4, "Set Class Resource height to 4")
    end
    if (bars.classPowerWidthMode == "custom" or bars.classPowerWidthMode == "manual") and (tonumber(bars.classPowerWidth) or 0) <= 0 then
        issues[#issues + 1] = "Class Resource width mode is custom but width is zero. Set a width or use player/cooldown width mode."
        AddFixChoice(choices, "bars.classPowerWidth", 120, "Set Class Resource width to 120")
        AddFixChoice(choices, "bars.classPowerWidthMode", "player", "Use Player width mode for Class Resources")
    end
    if LowOpacity(bars.classPowerFilledAlpha) and LowOpacity(bars.classPowerEmptyAlpha) then
        issues[#issues + 1] = "Filled and empty Class Resource opacity are both near zero."
        AddFixChoice(choices, "bars.classPowerFilledAlpha", 1, "Set Class Resource filled opacity to 100%")
        AddFixChoice(choices, "bars.classPowerEmptyAlpha", 0.3, "Set Class Resource empty opacity to 30%")
    elseif LowOpacity(bars.classPowerFilledAlpha) then
        issues[#issues + 1] = "Filled Class Resource opacity is near zero."
        AddFixChoice(choices, "bars.classPowerFilledAlpha", 1, "Set Class Resource filled opacity to 100%")
    end
    if bars.classPowerHideOOC == true then
        issues[#issues + 1] = "Class Resources hide out of combat by setting."
        AddFixChoice(choices, "bars.classPowerHideOOC", false, "Turn off Class Resource Hide Out Of Combat")
    end
    if bars.classPowerHideWhenFull == true and bars.classPowerHideWhenEmpty == true then
        issues[#issues + 1] = "Class Resources are configured to hide when full and when empty."
        AddFixChoice(choices, "bars.classPowerHideWhenFull", false, "Turn off Class Resource Hide When Full")
        AddFixChoice(choices, "bars.classPowerHideWhenEmpty", false, "Turn off Class Resource Hide When Empty")
    elseif bars.classPowerHideWhenFull == true then
        issues[#issues + 1] = "Class Resources hide when full by setting."
        AddFixChoice(choices, "bars.classPowerHideWhenFull", false, "Turn off Class Resource Hide When Full")
    elseif bars.classPowerHideWhenEmpty == true then
        issues[#issues + 1] = "Class Resources hide when empty by setting."
        AddFixChoice(choices, "bars.classPowerHideWhenEmpty", false, "Turn off Class Resource Hide When Empty")
    end
    if player.powerBarDetached == true then
        issues[#issues + 1] = "Player power bar is detached. If it should align with Class Resources, check detached power sync/anchor settings."
    end

    local lines = {
        "Class Resources diagnostic:",
        "Enabled: " .. (bars.showClassPower == false and "off" or "on"),
        "Height: " .. tostring(bars.classPowerHeight or "default"),
        "Width mode: " .. tostring(bars.classPowerWidthMode or "player"),
        "Width: " .. tostring(bars.classPowerWidth or "auto"),
        "Hide rules: OOC=" .. tostring(bars.classPowerHideOOC == true) .. ", full=" .. tostring(bars.classPowerHideWhenFull == true) .. ", empty=" .. tostring(bars.classPowerHideWhenEmpty == true),
    }
    if #issues == 0 then
        lines[#lines + 1] = "No obvious Class Resource settings problem was found. Some specs have no class-resource bar until the relevant resource exists."
    else
        for i = 1, #issues do lines[#lines + 1] = issues[i] end
    end
    return AppendFixChoices(table.concat(lines, "\n"), choices)
end

local function DashboardSetupDiagnosticText()
    local ctx = A.GetContext and A.GetContext() or {}
    local global = type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or nil
    local dashRoot = global and type(global.global) == "table" and global.global or nil
    local dash = dashRoot and type(dashRoot.dashboard) == "table" and dashRoot.dashboard or {}
    local hasPending = A.pendingConfirmation or (type(A.pendingChoices) == "table" and #A.pendingChoices > 0) or type(A.pendingFlow) == "table"
    local recoveryOpen = dash.dashboardRecoveryOpen == true or (M and M.dashboardRecoveryOpen == true)
    local scalingOpen = dash.dashboardScalingOpen == true or (M and M.dashboardScalingOpen == true)
    local changelogOpen = dash.dashboardChangelogOpen == true or (M and M.dashboardChangelogOpen == true)
    local lines = {
        "Dashboard setup diagnostic:",
        "Active page: " .. tostring((M and M.activeKey) or "unknown"),
        "Open/select helper: " .. (((M and type(M.Open) == "function") or (M and type(M.SelectPage) == "function")) and "available" or "missing"),
        "Assistant page stack: " .. tostring(A.Workflow and type(A.Workflow.navStack) == "table" and #A.Workflow.navStack or 0),
        "Pending confirmation: " .. tostring(A.pendingConfirmation ~= nil),
        "Pending choices: " .. tostring(type(A.pendingChoices) == "table" and #A.pendingChoices or 0),
        "Pending flow: " .. tostring(type(A.pendingFlow) == "table" and (A.pendingFlow.label or A.pendingFlow.kind) or "none"),
        "Guided setup: " .. tostring(type(ctx.guidedSetup) == "table" and "active" or "inactive"),
        "Recovery panel: " .. tostring(recoveryOpen),
        "Scaling panel: " .. tostring(scalingOpen),
        "Changelog panel: " .. tostring(changelogOpen),
        "Search intro seen: " .. tostring(M and M.searchIntroSeen == true),
    }
    if not (M and (type(M.Open) == "function" or type(M.SelectPage) == "function")) then
        lines[#lines + 1] = "Next safe fix: open Menu2 once so navigation helpers are initialized."
    elseif hasPending then
        lines[#lines + 1] = "Next safe fix: answer the pending prompt or say 'cancel workflow'."
    else
        lines[#lines + 1] = "No obvious Dashboard setup blocker was found."
    end
    local choices = {}
    if hasPending then
        AddActionChoice(choices, "assistant.workflow.cancel", {}, "Cancel active Assistant workflow", "Clears the current pending Assistant prompt, choice, flow, or panel.")
    end
    if M and M.searchIntroSeen == true then
        AddActionChoice(choices, "set_nav_search_intro", { command = "reset" }, "Reset Search Intro", "Makes the Ask MSUF search intro eligible to show again.")
    end
    if M and M.activeKey ~= "home" then
        AddActionChoice(choices, "open_page", { page = "home", label = "Dashboard" }, "Open Dashboard page", "Returns to the Dashboard home page.")
    end
    if not recoveryOpen then
        AddActionChoice(choices, "open_recovery_tools", {}, "Open Recovery Tools", "Opens the Dashboard recovery tools.")
    end
    if not scalingOpen then
        AddActionChoice(choices, "open_dashboard_panel", { panel = "scaling" }, "Open Scaling Tools", "Opens the Dashboard scaling tools.")
    end
    if not changelogOpen then
        AddActionChoice(choices, "open_dashboard_panel", { panel = "changelog" }, "Open Changelog", "Opens the Dashboard changelog panel.")
    end
    return AppendFixChoices(table.concat(lines, "\n"), choices)
end

local function OnOff(value)
    return value == true and "on" or "off"
end

local function GameplayFeatureLabel(feature)
    if feature == "combatTimer" then return "Combat Timer" end
    if feature == "combatState" then return "Combat Enter Leave Text" end
    if feature == "playerTotems" then return "Totem Frame" end
    if feature == "firstDance" then return "First Dance Tracker" end
    if feature == "combatCrosshair" then return "Combat Crosshair" end
    return "Gameplay helpers"
end

local function GameplayDiagnosticText(feature)
    local g = GameplayDB()
    feature = tostring(feature or "all")
    local focus = feature ~= "all" and feature or nil
    local lines = {
        "Gameplay helpers diagnostic:",
        "Focused helper: " .. GameplayFeatureLabel(focus or "all"),
        "Combat Timer: " .. OnOff(g.enableCombatTimer) .. ", size=" .. tostring(g.combatFontSize or 24) .. ", anchor=" .. tostring(g.combatTimerAnchor or "none"),
        "Combat Enter Leave Text: " .. OnOff(g.enableCombatStateText) .. ", size=" .. tostring(g.combatStateFontSize or 24) .. ", duration=" .. tostring(g.combatStateDuration or 1.5),
        "Totem Frame: " .. OnOff(g.enablePlayerTotems) .. ", icon size=" .. tostring(g.playerTotemsIconSize or 24),
        "First Dance Tracker: " .. OnOff(g.enableFirstDanceTimer) .. ", ready=" .. OnOff(g.firstDanceShowReady ~= false),
        "Combat Crosshair: " .. OnOff(g.enableCombatCrosshair) .. ", size=" .. tostring(g.crosshairSize or 40) .. ", thickness=" .. tostring(g.crosshairThickness or 3) .. ", melee spell=" .. tostring(g.nameplateMeleeSpellID or 0),
    }
    local issues = {}
    local choices = {}

    if focus == "combatTimer" then
        if g.enableCombatTimer ~= true then
            issues[#issues + 1] = "Combat Timer is disabled. It only appears when enabled and combat timing is active."
            AddFixChoice(choices, "gameplay.enableCombatTimer", true, "Turn on Combat Timer")
        end
        if tonumber(g.combatFontSize) ~= nil and tonumber(g.combatFontSize) < 10 then
            issues[#issues + 1] = "Combat Timer text size is extremely small."
            AddFixChoice(choices, "gameplay.combatFontSize", 24, "Set Combat Timer size to 24")
        end
    elseif focus == "combatState" then
        if g.enableCombatStateText ~= true then
            issues[#issues + 1] = "Combat Enter Leave Text is disabled."
            AddFixChoice(choices, "gameplay.enableCombatStateText", true, "Turn on Combat Enter Leave Text")
        end
        if tonumber(g.combatStateDuration) ~= nil and tonumber(g.combatStateDuration) <= 0 then
            issues[#issues + 1] = "Combat Enter Leave duration is zero or negative."
            AddFixChoice(choices, "gameplay.combatStateDuration", 1.5, "Set Combat Enter Leave duration to 1.5")
        end
        if tonumber(g.combatStateFontSize) ~= nil and tonumber(g.combatStateFontSize) < 10 then
            issues[#issues + 1] = "Combat Enter Leave text size is extremely small."
            AddFixChoice(choices, "gameplay.combatStateFontSize", 24, "Set Combat Enter Leave text size to 24")
        end
    elseif focus == "playerTotems" then
        if g.enablePlayerTotems ~= true then
            issues[#issues + 1] = "Totem Frame is disabled. It also only has useful runtime content for classes or states with totems/statues."
            AddFixChoice(choices, "gameplay.enablePlayerTotems", true, "Turn on Totem Frame")
        end
        if tonumber(g.playerTotemsIconSize) ~= nil and tonumber(g.playerTotemsIconSize) < 8 then
            issues[#issues + 1] = "Totem Frame icon size is extremely small."
            AddFixChoice(choices, "gameplay.playerTotemsIconSize", 24, "Set Totem Frame icon size to 24")
        end
    elseif focus == "firstDance" then
        if g.enableFirstDanceTimer ~= true then
            issues[#issues + 1] = "First Dance Tracker is disabled. It is a rogue helper and only has meaningful runtime state for that gameplay."
            AddFixChoice(choices, "gameplay.enableFirstDanceTimer", true, "Turn on First Dance Tracker")
        end
        if g.firstDanceShowReady == false then
            issues[#issues + 1] = "First Dance Show Ready is off, so the tracker can disappear while ready/inactive."
            AddFixChoice(choices, "gameplay.firstDanceShowReady", true, "Show First Dance ready state")
        end
        if tonumber(g.firstDanceIconSize) ~= nil and tonumber(g.firstDanceIconSize) < 16 then
            issues[#issues + 1] = "First Dance icon size is extremely small."
            AddFixChoice(choices, "gameplay.firstDanceIconSize", 40, "Set First Dance icon size to 40")
        end
    elseif focus == "combatCrosshair" then
        if g.enableCombatCrosshair ~= true then
            issues[#issues + 1] = "Combat Crosshair is disabled."
            AddFixChoice(choices, "gameplay.enableCombatCrosshair", true, "Turn on Combat Crosshair")
        end
        if tonumber(g.crosshairSize) ~= nil and tonumber(g.crosshairSize) < 20 then
            issues[#issues + 1] = "Combat Crosshair size is extremely small."
            AddFixChoice(choices, "gameplay.crosshairSize", 40, "Set Combat Crosshair size to 40")
        end
        if tonumber(g.crosshairThickness) ~= nil and tonumber(g.crosshairThickness) < 1 then
            issues[#issues + 1] = "Combat Crosshair thickness is zero."
            AddFixChoice(choices, "gameplay.crosshairThickness", 3, "Set Combat Crosshair thickness to 3")
        end
        if g.enableCombatCrosshairMeleeRangeColor == true and (tonumber(g.nameplateMeleeSpellID) or 0) <= 0 then
            issues[#issues + 1] = "Crosshair range color is on but no melee range spell is set. Use 'set crosshair spell to 12345' with a real spell ID."
        end
    else
        local enabledCount = 0
        if g.enableCombatTimer == true then enabledCount = enabledCount + 1 end
        if g.enableCombatStateText == true then enabledCount = enabledCount + 1 end
        if g.enablePlayerTotems == true then enabledCount = enabledCount + 1 end
        if g.enableFirstDanceTimer == true then enabledCount = enabledCount + 1 end
        if g.enableCombatCrosshair == true then enabledCount = enabledCount + 1 end
        lines[#lines + 1] = "Enabled optional helpers: " .. tostring(enabledCount) .. " of 5."
        if enabledCount == 0 then
            issues[#issues + 1] = "All optional Gameplay helpers are off. That is valid if you do not use them; ask for a focused diagnostic such as 'diagnose combat timer' if one should be visible."
        end
    end

    if #issues == 0 then
        lines[#lines + 1] = "No obvious Gameplay helper settings problem was found. Some helpers only appear in combat, with a matching class/spec, or when a real gameplay state exists."
    else
        for i = 1, #issues do lines[#lines + 1] = issues[i] end
    end
    AddActionChoice(choices, "open_page", { page = "gameplay", label = "Gameplay" }, "Open Gameplay page", "Opens the real Gameplay helper page for review.")
    return AppendFixChoices(table.concat(lines, "\n"), choices)
end

local GUIDED_SETUP_STEPS = {
    {
        key = "frame_size",
        title = "Main Frame Size",
        page = "uf_player",
        goal = "Start with readable Player and Target frames before tuning details.",
        body = "A solid baseline is Player width 275 and height 40, then Target can copy the same size.",
        examples = {
            "make player width 275",
            "make player height 40",
            "copy player layout to target",
        },
    },
    {
        key = "placement",
        title = "Player And Target Placement",
        page = "uf_player",
        goal = "Put the main frames where your eyes naturally rest in combat.",
        body = "Use Edit Mode for broad placement. Small nudges are easier to control than one big jump.",
        examples = {
            "start edit mode",
            "move player 20 left",
            "move target 20 right",
        },
    },
    {
        key = "castbars",
        title = "Castbars",
        page = "opt_castbar",
        goal = "Make important casts obvious without crowding the center.",
        body = "Target castbar is usually the first one to verify. After that, add Player, Focus, or Boss castbars only if you need them.",
        examples = {
            "show target castbar",
            "move target castbar 20 down",
            "set castbar height to 28",
        },
    },
    {
        key = "text",
        title = "Text Visibility",
        page = "uf_player",
        goal = "Keep the text you actually read and remove repeated noise.",
        body = "Clean layouts usually keep names and one clear health value, then reduce redundant power or HP text.",
        examples = {
            "hide player power text",
            "show target name",
            "set global font size 14",
        },
    },
    {
        key = "power",
        title = "Power Bars And Resources",
        page = "opt_bars",
        goal = "Make resource information clear without mistaking it for class resources.",
        body = "Power Bar controls live on unit and group frames. Class Resources are separate global controls.",
        examples = {
            "set target power bar height to 8",
            "detach target power bar",
            "turn on class resources",
        },
    },
    {
        key = "group_frames",
        title = "Group Frames",
        page = "gf_layout",
        goal = "Build Party and Raid after the main frames feel stable.",
        body = "Group frames need dense but readable sizing. Start with Party/Raid visibility, then tune width, text, and indicators.",
        examples = {
            "show party group frames",
            "make raid width 80",
            "turn off ready check symbol for all group frames",
        },
    },
    {
        key = "boss_frames",
        title = "Boss Frames And Final Check",
        page = "uf_boss",
        goal = "Finish with encounter information and a quick diagnostic pass.",
        body = "Boss frames and boss castbars should be readable without covering your main layout.",
        examples = {
            "show boss frame",
            "show boss castbar",
            "diagnose boss frames",
        },
    },
}

local GUIDED_SETUP_GUIDES = {
    main = {
        label = "MSUF layout setup",
        steps = GUIDED_SETUP_STEPS,
    },
    group_frames = {
        label = "Group Frames setup",
        steps = {
            {
                key = "group_visibility",
                title = "Party And Raid Visibility",
                page = "gf_layout",
                goal = "Decide which group frames should exist before tuning dense details.",
                body = "Start with Party and Raid visibility, then diagnose anything that should be visible but is not.",
                examples = {
                    "show party group frames",
                    "show raid group frames",
                    "diagnose party frames",
                },
            },
            {
                key = "group_geometry",
                title = "Group Size And Growth",
                page = "gf_layout",
                goal = "Make group frames scan cleanly at the roster sizes you actually play.",
                body = "Tune width, scale, growth, and breakpoint scale before text and indicators.",
                examples = {
                    "make raid width 80",
                    "set raid scale to 90",
                    "set raid frames to grow right",
                },
            },
            {
                key = "group_text",
                title = "Group Health And Text",
                page = "gf_bars",
                goal = "Keep readable health information without crowding each group cell.",
                body = "Use explicit Party/Raid wording when you are not already on the group page.",
                examples = {
                    "move party frame name down",
                    "set party power center text to current percent",
                    "set party power text size to 11",
                },
            },
            {
                key = "group_indicators",
                title = "Group Indicators",
                page = "gf_indicators",
                goal = "Verify group status icons and editor selections after layout and text feel stable.",
                body = "Use selector commands for editor state, then diagnose visibility if an icon still looks wrong.",
                examples = {
                    "turn off ready check symbol for all group frames",
                    "select party leader icon indicator",
                    "select bottom right corner editor slot",
                },
            },
        },
    },
    castbars = {
        label = "Castbars setup",
        steps = {
            {
                key = "castbar_visibility",
                title = "Castbar Visibility",
                page = "opt_castbar",
                goal = "Make the castbars you care about visible before adjusting detail controls.",
                body = "Target is usually the first castbar to verify; Player, Focus, and Boss can be added as needed.",
                examples = {
                    "show target castbar",
                    "show player castbar",
                    "diagnose target castbar",
                },
            },
            {
                key = "castbar_layout",
                title = "Castbar Layout",
                page = "opt_castbar",
                goal = "Place castbars and attached icons where they do not fight the unit frames.",
                body = "Move the bar or its text/icon parts separately when only one piece is wrong.",
                examples = {
                    "move target castbar icon right 4",
                    "move focus kick icon down 3",
                    "set target castbar height to 18",
                },
            },
            {
                key = "castbar_details",
                title = "Castbar Details",
                page = "opt_castbar",
                goal = "Keep important cast information visible and hide detail noise you do not read.",
                body = "Detail commands target the registered castbar controls instead of toggling the whole castbar.",
                examples = {
                    "turn off target castbar icon",
                    "turn off target castbar interrupt",
                    "set castbar text color red",
                },
            },
        },
    },
    profiles = {
        label = "Profiles setup",
        steps = {
            {
                key = "profile_backup",
                title = "Backup Current Profile",
                page = "profiles",
                goal = "Create an export point before doing broad layout work.",
                body = "Profile exports use the real MSUF profile export helper when it is available.",
                examples = {
                    "export current profile",
                    "select profile export kind group frames",
                    "copy discord link",
                },
            },
            {
                key = "profile_create",
                title = "Create Or Stage A Profile",
                page = "profiles",
                goal = "Prepare a named profile before switching or importing.",
                body = "The Assistant can stage profile fields and will ask for confirmation on destructive profile actions.",
                examples = {
                    "set profile name field to Raid Draft",
                    "copy profile Raid Draft",
                    "turn on profile import and create new profile",
                },
            },
            {
                key = "profile_import",
                title = "Import And Spec Routing",
                page = "profiles",
                goal = "Keep imports and automatic spec switching explicit and reversible where helpers support snapshots.",
                body = "Ask for profile diagnostics after imports, switches, or spec assignments.",
                examples = {
                    "import profile",
                    "enable spec auto-switch",
                    "diagnose profiles",
                },
            },
        },
    },
    class_resources = {
        label = "Class Resources setup",
        steps = {
            {
                key = "class_resource_baseline",
                title = "Enable And Place Resources",
                page = "classpower",
                goal = "Make class resources visible without confusing them with normal power bars.",
                body = "Class Resources are global controls; unit Power Bar controls are separate.",
                examples = {
                    "quick setup class resources",
                    "turn on class resources",
                    "move class resource down 5",
                },
            },
            {
                key = "class_resource_shape",
                title = "Shape And Readability",
                page = "classpower",
                goal = "Tune width mode, opacity, and prediction once placement is stable.",
                body = "Page-local commands work on the Class Resources page, but explicit wording also works from Dashboard.",
                examples = {
                    "set width mode to custom",
                    "set background opacity to 40",
                    "turn off prediction",
                },
            },
            {
                key = "class_resource_extras",
                title = "Class-Specific Extras",
                page = "classpower",
                goal = "Handle optional overlays such as Alternative Mana after the main resource is readable.",
                body = "Use diagnostics if the Class Resource page looks enabled but the runtime state does not match.",
                examples = {
                    "set alt mana height to 12",
                    "diagnose class resources",
                    "open class resources",
                },
            },
        },
    },
    gameplay = {
        label = "Gameplay helpers setup",
        steps = {
            {
                key = "combat_timer",
                title = "Combat Timer",
                page = "gameplay",
                goal = "Place the combat timer where it gives timing context without blocking frames.",
                body = "The Gameplay page supports short page-local commands while it is active.",
                examples = {
                    "turn on timer",
                    "move timer down 5",
                    "set timer anchor to target",
                },
            },
            {
                key = "combat_state_text",
                title = "Combat State Text",
                page = "gameplay",
                goal = "Use combat enter/leave text only if the extra signal helps you react.",
                body = "Text, size, duration, and movement are separate registered controls.",
                examples = {
                    "turn on combat enter leave text",
                    "set combat enter text to Pulling",
                    "set combat state duration to 2.5",
                },
            },
            {
                key = "gameplay_frames",
                title = "Totem, First Dance, And Crosshair",
                page = "gameplay",
                goal = "Enable only the helper frames that match your class or role.",
                body = "Unsupported controls are reported explicitly instead of faking success.",
                examples = {
                    "turn on totem frame",
                    "turn on first dance",
                    "turn on combat crosshair",
                },
            },
        },
    },
    appearance = {
        label = "Bars and Fonts setup",
        steps = {
            {
                key = "bars_baseline",
                title = "Bars Baseline",
                page = "opt_bars",
                goal = "Set textures, outlines, and bar readability before per-frame overrides.",
                body = "Shared settings apply broadly; ONLY wording enables scoped overrides for one target.",
                examples = {
                    "set bars texture to Smooth",
                    "set global bar outline thickness to 2",
                    "set only player bar outline thickness to 3",
                },
            },
            {
                key = "fonts_baseline",
                title = "Fonts Baseline",
                page = "opt_fonts",
                goal = "Make text readable first, then tune scoped font overrides only where needed.",
                body = "Rendering, baseline, outline, and name-shortening controls use real Global Fonts settings.",
                examples = {
                    "set font baseline to 2",
                    "set global font size 14",
                    "set target font outline only to THICKOUTLINE",
                },
            },
            {
                key = "colors_baseline",
                title = "Colors And Follow-Ups",
                page = "opt_colors",
                goal = "Use exact color commands and follow-ups for consistent non-aura colors.",
                body = "Registered color pickers support named colors, RGB values, hex values, and same-for follow-ups.",
                examples = {
                    "set player border color to rgb 255 128 0",
                    "same for target",
                    "change party health bar color to blue",
                },
            },
        },
    },
}

local function SetupNormalize(text)
    if A and type(A.Normalize) == "function" then return A.Normalize(text) end
    text = tostring(text or ""):lower()
    text = text:gsub("[,;:!?%(%)]", " ")
    text = text:gsub("%s+", " ")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function SetupHasAny(text, terms)
    text = " " .. SetupNormalize(text) .. " "
    for i = 1, #(terms or {}) do
        local term = SetupNormalize(terms[i])
        if term ~= "" and text:find(" " .. term .. " ", 1, true) then return true end
    end
    return false
end

local function GuidedSetupGuideKey(style)
    local text = SetupNormalize(style)
    if text == "" then return "main" end
    if SetupHasAny(text, { "group frames", "group frame", "party frames", "raid frames", "mythic raid frames", "gruppenframes", "gruppe setup", "raid setup", "party setup" }) then return "group_frames" end
    if SetupHasAny(text, { "castbar", "castbars", "cast bar", "cast bars", "zauberleiste", "kick bar", "focus kick" }) then return "castbars" end
    if SetupHasAny(text, { "profile", "profiles", "profil", "profile setup", "profile guide", "spec profile", "import profile", "export profile" }) then return "profiles" end
    if SetupHasAny(text, { "class resource", "class resources", "class power", "class bar", "resource bar", "klassenressource", "klassenressourcen" }) then return "class_resources" end
    if SetupHasAny(text, { "gameplay", "combat timer", "combat text", "totem", "first dance", "crosshair", "spielhilfe" }) then return "gameplay" end
    if SetupHasAny(text, { "appearance", "bars and fonts", "fonts and bars", "global bars", "global fonts", "font setup", "bar setup", "color setup", "farben", "schrift" }) then return "appearance" end
    return "main"
end

local function GuidedSetupGuideForFlow(flow)
    local key = type(flow) == "table" and flow.guide or "main"
    local guide = GUIDED_SETUP_GUIDES[key]
    return guide or GUIDED_SETUP_GUIDES.main, guide and key or "main"
end

local function GuidedSetupStyleLabel(style)
    style = tostring(style or ""):lower()
    if style:find("healer", 1, true) or style:find("raid", 1, true) then return "healer raid" end
    if style:find("rogue", 1, true) then return "clean rogue" end
    if style:find("minimal", 1, true) then return "minimal" end
    return "clean"
end

local function GuidedSetupFlow()
    local ctx = A.GetContext and A.GetContext()
    if not ctx then return nil end
    ctx.guidedSetup = type(ctx.guidedSetup) == "table" and ctx.guidedSetup or nil
    return ctx.guidedSetup
end

local function SetGuidedSetupFlow(flow)
    local ctx = A.GetContext and A.GetContext()
    if not ctx then return nil end
    ctx.guidedSetup = flow
    return flow
end

local function CloseGuidedSetupPanel()
    if A and A.largeTextPanel ~= nil then
        if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() end
    end
end

local function GuidedSetupPageHint(step)
    if not step or type(step.page) ~= "string" or step.page == "" then return nil end
    return "I will stay on the current page. Ask me to open the matching page when you want to go there."
end

local function GuidedSetupStepText(flow)
    flow = flow or GuidedSetupFlow()
    if type(flow) ~= "table" then return "No guided setup is active. Say 'help me build a clean layout' to start." end
    local guide = GuidedSetupGuideForFlow(flow)
    local steps = (guide and guide.steps) or GUIDED_SETUP_STEPS
    local index = tonumber(flow.step) or 1
    if index < 1 then index = 1 end
    if index > #steps then
        SetGuidedSetupFlow(nil)
        CloseGuidedSetupPanel()
        return "Guided setup complete. You can keep typing normal MSUF commands, use 'undo' for the last Assistant change, or ask me to diagnose anything that is not visible."
    end
    flow.step = index
    local step = steps[index]
    local lines = {
        "Guided setup - " .. tostring(flow.guideTitle or (guide and guide.label) or "MSUF layout setup"),
        "Step " .. tostring(index) .. "/" .. tostring(#steps) .. ": " .. step.title,
        "Goal: " .. tostring(step.goal or ""),
        tostring(step.body or ""),
    }
    local pageHint = GuidedSetupPageHint(step)
    if pageHint then lines[#lines + 1] = pageHint end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Useful commands to try:"
    for i = 1, #(step.examples or {}) do
        lines[#lines + 1] = tostring(i) .. ". " .. step.examples[i]
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Normal MSUF commands still work while this guide is active. Say 'next', 'back', 'show setup', 'done', or 'cancel setup' when you want to steer the tour."
    local text = table.concat(lines, "\n")
    CloseGuidedSetupPanel()
    return text
end

function A.Workflow.StartGuidedSetup(style)
    local guideKey = GuidedSetupGuideKey(style)
    local guide = GUIDED_SETUP_GUIDES[guideKey] or GUIDED_SETUP_GUIDES.main
    local label = GuidedSetupStyleLabel(style)
    local title = guide.label
    if guideKey == "main" then title = tostring(label or "clean") .. " layout" end
    local flow = SetGuidedSetupFlow({ style = tostring(style or "clean"), styleLabel = label, guide = guideKey, guideTitle = title, step = 1 })
    return GuidedSetupStepText(flow)
end

function A.Workflow.GuidedSetupStep(command)
    command = tostring(command or "show")
    local flow = GuidedSetupFlow()
    if type(flow) ~= "table" then
        return "No guided setup is active. Say 'help me build a clean layout' to start."
    end
    if command == "cancel" then
        SetGuidedSetupFlow(nil)
        CloseGuidedSetupPanel()
        return "Cancelled guided setup. You can keep typing normal MSUF commands."
    end
    if command == "finish" or command == "done" then
        SetGuidedSetupFlow(nil)
        CloseGuidedSetupPanel()
        return "Guided setup marked complete. You can still ask for diagnostics or use 'undo' for the last Assistant change."
    end
    if command == "back" or command == "previous" then
        flow.step = (tonumber(flow.step) or 1) - 1
    elseif command == "next" or command == "skip" then
        flow.step = (tonumber(flow.step) or 1) + 1
    end
    if flow.step < 1 then flow.step = 1 end
    local guide = GuidedSetupGuideForFlow(flow)
    local steps = (guide and guide.steps) or GUIDED_SETUP_STEPS
    if flow.step > #steps then
        SetGuidedSetupFlow(nil)
        CloseGuidedSetupPanel()
        return "Guided setup marked complete. You can still ask for diagnostics or use 'undo' for the last Assistant change."
    end
    return GuidedSetupStepText(flow)
end

Registry:RegisterAction({
    key = "open_page",
    label = "Open Dashboard Page",
    type = "navigation",
    combatSafe = true,
    run = function(args)
        local page = args and args.page
        if type(page) ~= "string" or page == "" then return false, "I do not know which page to open." end
        local previousPage = M and M.activeKey
        local label = tostring(args.label or page)
        local opened = false
        local bridge = M and M.SearchBridge
        local query = args and args.query
        if bridge and type(bridge.OpenSearchTarget) == "function" and type(query) == "string" and query ~= "" then
            bridge.OpenSearchTarget(page, query, label, args and args.anchor)
            opened = M and M.activeKey == page
        end
        if not opened and M and type(M.Open) == "function" then
            opened = M.Open(page) ~= false
        elseif not opened and M and type(M.SelectPage) == "function" then
            opened = M.SelectPage(page) ~= false
        end
        if opened then
            if previousPage and previousPage ~= page and A.Workflow and type(A.Workflow.PushNavigationPage) == "function" then
                A.Workflow.PushNavigationPage(previousPage)
            end
            return true, "Opened " .. label .. "."
        end
        return false, "Dashboard navigation is not available right now."
    end,
})

Registry:RegisterAction({
    key = "assistant_status",
    label = "Show MSUF Status",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        local text = A.Workflow.StatusText()
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "MSUF Status",
                help = "Read-only diagnostic status for the current menu and Assistant registry.",
                text = text,
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "assistant_nomatch_telemetry",
    label = "Show Assistant NoMatch Telemetry",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        local text = A.NoMatchTelemetryText and A.NoMatchTelemetryText(12) or "Assistant NoMatch telemetry is not available."
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "Assistant NoMatch Telemetry",
                help = "Read-only list of unmatched wording captured by the local Assistant.",
                text = text,
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "assistant_nomatch_worklist",
    label = "Show Assistant NoMatch Worklist",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local owner = args and (args.owner or args.ownerFilter)
        local resolution = args and (args.resolution or args.resolutionFilter)
        local priority = args and (args.priority or args.priorityFilter)
        local tag = args and (args.tag or args.tagFilter)
        local text = A.NoMatchWorklistText and A.NoMatchWorklistText(20, owner, resolution, priority, tag) or "Assistant NoMatch worklist is not available."
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "Assistant NoMatch Worklist",
                help = "Prioritized local Assistant misses for alias, registry-intent, action, Aura, media, or Knowledge follow-up work.",
                text = text,
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "assistant_nomatch_clear",
    label = "Clear Assistant NoMatch Telemetry",
    type = "diagnostic",
    combatSafe = true,
    confirmRequired = true,
    run = function()
        local total = A.ClearNoMatchTelemetry and A.ClearNoMatchTelemetry() or 0
        return true, "Cleared Assistant NoMatch telemetry. Removed " .. tostring(total) .. " recorded misses."
    end,
})

Registry:RegisterAction({
    key = "assistant_help",
    label = "Show Assistant Help",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        local text = A.Workflow.HelpText()
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "Assistant Help",
                help = "Deterministic command examples that are handled locally by MSUF.",
                text = text,
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "assistant_scope_help",
    label = "Show Scoped Assistant Help",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local text = A.Workflow.ScopeHelpText(args or {})
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "Assistant Controls",
                help = "Registry-backed settings and examples for the requested area.",
                text = text,
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})

Registry:RegisterAction({
    key = "copy_support_link",
    label = "Copy Support Link",
    type = "support",
    combatSafe = true,
    run = function(args)
        local key = tostring(args and args.link or "")
        local spec = A.Workflow.SupportLinks and A.Workflow.SupportLinks[key]
        local value = A.Workflow.SupportURL(key)
        if not (spec and value) then return false, "I do not know that support link." end
        if not A.Workflow.CopyText(spec.title, value, "Copy this MSUF support link.") then
            return false, "Support link copy UI is not available right now."
        end
        return true, "Done. The " .. tostring(spec.title) .. " link is ready to copy."
    end,
})

Registry:RegisterAction({
    key = "support_links_summary",
    label = "Show Support Links",
    type = "support",
    combatSafe = true,
    run = function()
        local text = A.Workflow.SupportSummaryText()
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "MSUF Support Links",
                help = "Copy a specific link by asking for Discord, Patreon, PayPal, Ko-fi, or GitHub.",
                text = text,
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})


Registry:RegisterAction({
    key = "diagnose_castbar_visibility",
    label = "Diagnose Castbar Visibility",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local unit = args and args.unit or "target"
        if not CASTBAR_KEYS[unit] then return false, "I can only diagnose player, target, focus, or boss castbars right now." end
        local g = GeneralDB()
        local backend = GetCastbarBackend(unit, g)
        local unitEnabled = true
        if unit ~= "boss" then unitEnabled = UnitDB(unit).enabled ~= false end
        local label = UNIT_LABELS[unit] or unit
        local choices = {}
        if backend == "HIDE" then
            AddFixChoice(choices, "general." .. tostring(CASTBAR_KEYS[unit].enable), true, "Show " .. label .. " castbar")
            return true, AppendFixChoices(label .. " castbar is hidden by its backend setting. Say 'show " .. tostring(unit) .. " castbar' or open Castbar settings.", choices)
        end
        if unitEnabled == false then
            AddFixChoice(choices, unit .. ".enabled", true, "Show " .. label .. " frame")
            return true, AppendFixChoices(label .. " frame is disabled, so its attached castbar may not be visible. Say 'show " .. tostring(unit) .. " frame' first.", choices)
        end
        if unit == "player" and backend == "BLIZZARD" then
            AddFixChoice(choices, "general.castbarPlayerBackend", "MSUF", "Use the MSUF Player castbar backend")
            return true, AppendFixChoices("Player castbar is assigned to the Blizzard castbar. Say 'show player castbar' to use the MSUF castbar backend.", choices)
        end
        return true, label .. " castbar is enabled in MSUF. If it still is not visible, check Edit Mode position, castbar text/icon settings, and whether the unit is currently casting."
    end,
})

Registry:RegisterAction({
    key = "diagnose_unit_visibility",
    label = "Diagnose Unit Frame Visibility",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local unit = args and args.unit or "player"
        if not UNIT_LABELS[unit] then return false, "I do not know which unit frame to diagnose." end
        return true, UnitFrameDiagnosticText(unit)
    end,
})

Registry:RegisterAction({
    key = "diagnose_group_visibility",
    label = "Diagnose Group Frame Visibility",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        local scope = args and args.scope or "party"
        if scope ~= "party" and scope ~= "raid" and scope ~= "mythicraid" then scope = "party" end
        return true, GroupFrameDiagnosticText(scope)
    end,
})

Registry:RegisterAction({
    key = "diagnose_aura_visibility",
    label = "Diagnose Aura Visibility",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        return true, AuraDiagnosticText(args)
    end,
})

Registry:RegisterAction({
    key = "clear_broken_spec_profile_mappings",
    label = "Clear Broken Spec Profile Mappings",
    type = "profile",
    combatSafe = false,
    captureSnapshot = true,
    captureProfileSnapshot = true,
    run = function()
        local count = ClearBrokenSpecProfileMappings()
        if A and type(A.ApplyBroad) == "function" then A.ApplyBroad("MSUF_ASSISTANT_PROFILE_SPEC_MAPPING_REPAIR") end
        if M and type(M.Refresh) == "function" then M.Refresh() end
        if count <= 0 then return true, "No broken spec profile mappings were found." end
        return true, "Done. Cleared " .. tostring(count) .. " broken spec profile mapping" .. (count == 1 and "." or "s.")
    end,
})

Registry:RegisterAction({
    key = "diagnose_profile_status",
    label = "Diagnose Profiles",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        return true, ProfileDiagnosticText()
    end,
})

Registry:RegisterAction({
    key = "diagnose_class_power_status",
    label = "Diagnose Class Resources",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        return true, ClassPowerDiagnosticText()
    end,
})

Registry:RegisterAction({
    key = "diagnose_gameplay_helpers",
    label = "Diagnose Gameplay Helpers",
    type = "diagnostic",
    combatSafe = true,
    run = function(args)
        return true, GameplayDiagnosticText(args and args.feature or "all")
    end,
})

Registry:RegisterAction({
    key = "diagnose_dashboard_setup",
    label = "Diagnose Dashboard Setup",
    type = "diagnostic",
    combatSafe = true,
    run = function()
        return true, DashboardSetupDiagnosticText()
    end,
})

Registry:RegisterAction({
    key = "guided_setup",
    label = "Guided Setup",
    type = "setup",
    combatSafe = true,
    run = function(args)
        return true, A.Workflow.StartGuidedSetup(args and args.style or "clean")
    end,
})

Registry:RegisterAction({
    key = "guided_setup_step",
    label = "Guided Setup Step",
    type = "setup",
    combatSafe = true,
    run = function(args)
        return true, A.Workflow.GuidedSetupStep(args and args.command or "show")
    end,
})

Registry:RegisterTodo("Auras3 remaining advanced work: whitelist-style operations where the UI exposes them beyond the registered filters, blacklists, color controls, and group category blacklists.")
Registry:RegisterTodo("Profiles remaining work: spec-profile edge cases should keep expanding as new public helpers appear.")
Registry:RegisterTodo("Preset operations remaining work: add Assistant routes for any future UI preset buttons only after they expose public shared helpers.")
Registry:RegisterTodo("Diagnostic/setup workflows remaining work: aura-specific troubleshooters, deeper branch-specific diagnostic repair flows as new helpers appear, and any future public factory-reset helper routed without slash-command execution.")
