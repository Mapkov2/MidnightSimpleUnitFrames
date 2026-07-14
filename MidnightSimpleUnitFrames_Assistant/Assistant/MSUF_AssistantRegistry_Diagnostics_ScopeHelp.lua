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

local PAGE_LABEL_OVERRIDES = {
    home = "Dashboard",
    profiles = "Profiles",
    gameplay = "Gameplay",
    classpower = "Class Resources",
    modules = "Modules",
    search = "Search",
    opt_castbar = "Cast Bars",
    opt_bars = "Bars",
    opt_colors = "Colors",
    opt_fonts = "Fonts",
    opt_misc = "Miscellaneous",
    gf_layout = "Group Layout",
    gf_bars = "Group Dispel Overlay",
    gf_indicators = "Group Status & Indicators",
    gf_auras = "Group Auras",
    auras3 = "Auras",
    auras3_buffs = "Aura Buffs",
    auras3_debuffs = "Aura Debuffs",
    auras3_filters = "Aura Filters",
    auras3_styling = "Aura Style",
}

local function UnitForPage(page)
    if page == "uf_player" then return "player" end
    if page == "uf_target" then return "target" end
    if page == "uf_focus" then return "focus" end
    if page == "uf_pet" then return "pet" end
    if page == "uf_targettarget" then return "targettarget" end
    if page == "uf_focustarget" then return "focustarget" end
    if page == "uf_boss" then return "boss" end
    return nil
end

local function PageLabel(page, fallback)
    page = tostring(page or "")
    if page ~= "" then
        if A and type(A.DisplayPageLabel) == "function" then return A.DisplayPageLabel(page, "current area") end
        if PAGE_LABEL_OVERRIDES[page] then return PAGE_LABEL_OVERRIDES[page] end
        return "current area"
    end
    fallback = tostring(fallback or "")
    if fallback ~= "" and fallback ~= "current page" then return "current area" end
    return fallback ~= "" and fallback or nil
end

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
            "set target debuff dispellable filter on",
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
    local unit = args.unit or UnitForPage(args.page)
    local group = args.group
    local page = args.page
    local explicitLabel = tostring(args.label or "")
    if explicitLabel == "current page" then explicitLabel = "" end
    local label
    if frameType == "editMode" then
        label = "Edit Mode"
    else
        label = (unit and UNIT_LABELS[unit]) or (group and UNIT_LABELS[group]) or PageLabel(page, explicitLabel) or frameType or page or "current area"
    end
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
    elseif frameType == "editMode" then
        lines[#lines + 1] = "I can run Edit Mode tasks for entering, exiting, toggling, previews, grid, snap, anchor picking, status checks, and position undo/redo."
    else
        lines[#lines + 1] = "I don't have a focused list for that yet, but I can still navigate and run known tasks."
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Examples:"
    local examples = ScopeHelpExamples(frameType, unit, group, page)
    for i = 1, #examples do lines[#lines + 1] = "- " .. examples[i] end
    return table.concat(lines, "\n")
end
