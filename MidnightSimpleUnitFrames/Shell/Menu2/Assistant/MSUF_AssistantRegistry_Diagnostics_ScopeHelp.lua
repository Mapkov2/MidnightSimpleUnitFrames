-- Scoped Assistant help workflow for diagnostics actions.
-- Pure text/registry lookup logic; it stays out of the heavier diagnostic checks.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A
A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

local Registry = C.Registry
local UNIT_LABELS = C.UNIT_LABELS or {}

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

local function CommandSubject(key, label)
    key = tostring(key or "")
    if key == "targettarget" then return "target of target" end
    if key == "focustarget" then return "focus target" end
    if key == "mythicraid" then return "mythic raid" end
    label = tostring(label or key)
    if label == "" then return "player" end
    return label:lower()
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
        local scope = CommandSubject(group or "raid", UNIT_LABELS[group or "raid"])
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
            "hide spell 12345 for player auras",
            "show hidden raid buff categories",
        }
    end
    local subject = CommandSubject(unit or "player", UNIT_LABELS[unit or "player"])
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
    local lines = { "Assistant help for " .. tostring(label) .. ":" }
    if #settings > 0 then
        lines[#lines + 1] = "Available options: " .. tostring(#settings)
        local preview = SettingPreviewLines(settings, 8)
        for i = 1, #preview do lines[#lines + 1] = preview[i] end
    else
        lines[#lines + 1] = "I don't have a focused list for that yet, but I can still navigate and run known tasks."
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Examples:"
    local examples = ScopeHelpExamples(frameType, unit, group, page)
    for i = 1, #examples do lines[#lines + 1] = "- " .. examples[i] end
    return table.concat(lines, "\n")
end
