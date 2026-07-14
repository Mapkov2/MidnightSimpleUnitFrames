-- Assistant diagnostics support/status workflow helpers.
-- Loaded before MSUF_AssistantRegistry_Diagnostics.lua so actions can use A.Workflow helpers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A
A.Workflow = A.Workflow or {}

local C = A.RegistryCore
local Registry = (type(C) == "table" and C.Registry) or A.Registry or { settings = {}, actions = {} }

local function ActiveProfileName()
    if A and type(A.ActiveProfileName) == "function" then return A.ActiveProfileName() end
    local name = tostring(_G.MSUF_ActiveProfile or "Default")
    if name == "" then return "Default" end
    return name
end

local function ActivePageLabel()
    local page = M and M.activeKey
    if type(page) ~= "string" or page == "" then return "not open" end
    if A and type(A.DisplayPageLabel) == "function" then return A.DisplayPageLabel(page, "MSUF page") end
    return "MSUF page"
end

local LOCALE_DISPLAY_LABELS = {
    enUS = "English (US)",
    enGB = "English (UK)",
    deDE = "German (deDE)",
    esES = "Spanish (EU)",
    esMX = "Spanish (MX)",
    frFR = "French",
    itIT = "Italian",
    ptBR = "Portuguese (BR)",
    ruRU = "Russian",
    koKR = "Korean",
    zhCN = "Chinese (Simplified)",
    zhTW = "Chinese (Traditional)",
}

local function LocaleDisplayLabel(locale)
    locale = tostring(locale or "")
    if locale == "" or locale == "not reported" then return "not reported" end
    return LOCALE_DISPLAY_LABELS[locale] or ("Unknown (" .. locale .. ")")
end

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
    if A and type(A.ShowLargeTextPanel) == "function" then
        A.ShowLargeTextPanel({
            kind = "export",
            title = title or "MSUF",
            help = help or "Copy this value.",
            text = value,
            status = "Click Copy text, press Ctrl+C, then Close.",
        })
        return true
    end
    if type(_G.MSUF_ShowCopyLink) == "function" then
        _G.MSUF_ShowCopyLink(title or "MSUF", value)
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
        or "not reported"
    local locale = type(_G.GetLocale) == "function" and _G.GetLocale() or "not reported"
    local combat = ((_G.InCombatLockdown and _G.InCombatLockdown()) or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) and "yes" or "no"
    local edit = "not detected"
    if M and type(M.IsMSUFEditModeActive) == "function" then
        edit = M.IsMSUFEditModeActive(true) and "on" or "off"
    elseif _G.MSUF_UnitEditModeActive ~= nil then
        edit = _G.MSUF_UnitEditModeActive == true and "on" or "off"
    end
    lines[#lines + 1] = "MSUF Assistant details"
    lines[#lines + 1] = "Version: " .. tostring(version)
    lines[#lines + 1] = "Locale: " .. LocaleDisplayLabel(locale)
    lines[#lines + 1] = "Active page: " .. ActivePageLabel()
    lines[#lines + 1] = "Active profile: " .. ActiveProfileName()
    lines[#lines + 1] = "In combat: " .. combat
    lines[#lines + 1] = "Edit mode: " .. edit
    -- Status must not be the operation that cold-builds the full knowledge
    -- index. Reuse detailed counts only after an explicit knowledge request
    -- has already materialized it.
    local knowledgeCounts = A.Knowledge and type(A.Knowledge.summaryCache) == "table"
        and A.Knowledge.summaryCache or nil
    if type(knowledgeCounts) == "table" then
        lines[#lines + 1] = "Registry inventory: " .. tostring(knowledgeCounts.setting or 0)
            .. " indexed settings (" .. tostring(knowledgeCounts.directSetting or 0)
            .. " reviewed direct-write, " .. tostring(knowledgeCounts.guidedSetting or 0)
            .. " guidance/read-only) and "
            .. tostring((knowledgeCounts.action or 0) + (knowledgeCounts.diagnostic or 0))
            .. " indexed tasks or checks"
    else
        lines[#lines + 1] = "Registry inventory: " .. tostring(#(Registry.settings or {}))
            .. " indexed settings and " .. tostring(#(Registry.actions or {}))
            .. " indexed tasks or checks; direct mutation still requires a reviewed write contract"
    end
    local parser = A.Parser or {}
    local actionAliasCandidates = tonumber(parser._lastRegistryActionAliasCandidateCount)
    local actionAliasTotal = tonumber(parser._lastRegistryActionAliasTotalCount)
    if actionAliasCandidates and actionAliasTotal and actionAliasTotal > 0 then
        lines[#lines + 1] = "Task phrases checked: " .. tostring(actionAliasCandidates) .. "/" .. tostring(actionAliasTotal)
    end
    lines[#lines + 1] = "Changes waiting: " .. tostring(type(A.queuedPlans) == "table" and #A.queuedPlans or 0)
    local jobSummary = A.GetJobSummary and A.GetJobSummary() or nil
    if type(jobSummary) == "table" then
        local detail = ""
        if type(jobSummary.labels) == "table" and #jobSummary.labels > 0 then detail = " (" .. table.concat(jobSummary.labels, ", ") .. ")" end
        lines[#lines + 1] = "Work in progress: " .. tostring(tonumber(jobSummary.count) or 0) .. detail
    end
    return table.concat(lines, "\n")
end

function A.Workflow.HelpText()
    return table.concat({
        "Examples:",
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
