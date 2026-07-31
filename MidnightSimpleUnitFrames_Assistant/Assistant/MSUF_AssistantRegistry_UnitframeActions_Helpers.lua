-- Assistant unitframe action helpers.
-- Loaded before MSUF_AssistantRegistry_UnitframeActions.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

function A.UnitframesRegistry.BuildUnitframeActionHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local UnitDB = ctx.UnitDB
    if type(UnitDB) ~= "function" then return nil end

    local POSITION_FIELDS = { "offsetX", "offsetY", "point", "relativePoint", "anchorFrameName", "anchorToUnitframe" }

    local function ResetUnitPositionFromDefaults(unit, defaults)
        local src = type(defaults) == "table" and defaults[unit] or nil
        if type(src) ~= "table" then return false end
        local dst = UnitDB(unit)
        for i = 1, #POSITION_FIELDS do
            local key = POSITION_FIELDS[i]
            dst[key] = src[key]
        end
        return true
    end

    local UNIT_COPY_SCOPE_LABELS = {
        { key = "basics", label = "Frame Basics" },
        { key = "text", label = "Text" },
        { key = "portrait", label = "Portrait" },
        { key = "power", label = "Power Bar" },
        { key = "castbar", label = "Cast Bar" },
        { key = "status", label = "Status Icons" },
        { key = "load", label = "Load Conditions" },
        { key = "transparency", label = "Transparency" },
        { key = "layout", label = "Frame Size" },
    }

    local function UnitCopyScopeSummary(scopes)
        if type(scopes) ~= "table" then return "" end
        local selected, total = {}, 0
        for i = 1, #UNIT_COPY_SCOPE_LABELS do
            local row = UNIT_COPY_SCOPE_LABELS[i]
            total = total + 1
            if scopes[row.key] == true then selected[#selected + 1] = row.label end
        end
        if #selected == 0 then return " Which unit-frame parts do you want me to copy?" end
        if #selected == total then return " Categories: all unit copy categories." end
        return " Categories: " .. table.concat(selected, ", ") .. "."
    end

    return {
        ResetUnitPositionFromDefaults = ResetUnitPositionFromDefaults,
        UnitCopyScopeSummary = UnitCopyScopeSummary,
    }
end
