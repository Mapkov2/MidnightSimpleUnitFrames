-- Standalone regression for stable group-frame Edit Mode/runtime positioning.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function Near(actual, expected, message)
    if math.abs((actual or 0) - (expected or 0)) > 0.001 then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function Read(relativePath)
    local file = assert(io.open(root .. "/" .. relativePath, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function Count(text, needle)
    local count, from = 0, 1
    while true do
        local at = text:find(needle, from, true)
        if not at then return count end
        count = count + 1
        from = at + #needle
    end
end

local MSUF = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}
_G.MSUF_NS = MSUF

local dbChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua"))
dbChunk("MidnightSimpleUnitFrames", MSUF)
local GF = assert(MSUF.GF)
Check(type(GF.GetGridMetrics) == "function", "GetGridMetrics missing")
Check(type(GF.EnsureStableGridPosition) == "function", "stable-position migration missing")

local function RaidConf(growth, legacyX, legacyY)
    return {
        width = 80,
        height = 32,
        spacing = 1,
        growth = growth,
        unitsPerColumn = 5,
        maxColumns = 8,
        preserveRaidGroups = false,
        frameScaleMode = "off",
        point = "CENTER",
        offsetX = legacyX,
        offsetY = legacyY,
        positionMode = "GRID_CENTER_V1",
    }
end

local expected30 = {
    DOWN = { 242.5, -82, 485, 164 },
    UP = { 242.5, 50, 485, 164 },
    RIGHT = { 202, -98.5, 404, 197 },
    LEFT = { -122, -98.5, 404, 197 },
}

for growth, expected in pairs(expected30) do
    local conf = RaidConf(growth, 0, 0)
    _G.MSUF_DB = { gf_raid = conf }
    GF.InvalidateConfCache()
    local dx, dy, width, height = GF.GetGridMetrics("raid", 30)
    Near(dx, expected[1], growth .. " dx")
    Near(dy, expected[2], growth .. " dy")
    Near(width, expected[3], growth .. " width")
    Near(height, expected[4], growth .. " height")

    local wantedX, wantedY = 173, -91
    conf.offsetX, conf.offsetY = wantedX + dx, wantedY + dy
    Check(GF.EnsureStableGridPosition("raid", 30, conf) == true, growth .. " did not migrate")
    Near(conf.offsetX, wantedX, growth .. " X was not visually preserved")
    Near(conf.offsetY, wantedY, growth .. " Y was not visually preserved")
    Check(conf.positionMode == "GRID_BOUNDS_V2", growth .. " mode was not upgraded")
    Check(GF.EnsureStableGridPosition("raid", 40, conf) == false, growth .. " migrated twice")
    Near(conf.offsetX, wantedX, growth .. " X drifted when roster count changed")
    Near(conf.offsetY, wantedY, growth .. " Y drifted when roster count changed")
end

-- The old delta must vary with roster count; the stable saved point must not.
local countDeltas = {}
local conf = RaidConf("DOWN", 0, 0)
_G.MSUF_DB = { gf_raid = conf }
GF.InvalidateConfCache()
for _, count in ipairs({ 5, 10, 20, 30, 40 }) do
    local dx = GF.GetGridMetrics("raid", count)
    countDeltas[#countDeltas + 1] = dx
end
Check(countDeltas[1] ~= countDeltas[#countDeltas], "legacy raid delta unexpectedly count-independent")

local headers = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Headers.lua")
Check(headers:find('header:SetPoint(point, anchor, point, 0, 0)', 1, true), "live header is not aligned to the stable anchor")
Check(not headers:find('header:SetPoint(point, anchor, point, -dx, -dy)', 1, true), "legacy live double-offset remains")
Check(headers:find('actualW = header.GetWidth', 1, true), "live clamp does not measure Blizzard's real footprint")

local preview = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua")
Check(preview:find('layout:SetPoint(layoutPoint, container, layoutPoint, 0, 0)', 1, true), "preview layout is not aligned to its container")
Check(not preview:find('layout:SetPoint(layoutPoint, container, layoutPoint, -(dx or 0), -(dy or 0))', 1, true), "legacy preview double-offset remains")

local em2 = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua")
Check(em2:find('local gridDX, gridDY = 0, 0', 1, true), "group drag does not start from stable bounds")
Check(Count(em2, 'positionMode = STABLE_GRID_POSITION_MODE') >= 5, "not every Edit Mode position writer stamps V2")

local runtime = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua")
Check(runtime:find('event == "GROUP_ROSTER_UPDATE"', 1, true), "roster layout refresh missing")
Check(runtime:find('GF.EnsureStableGridPosition(kind, count, conf)', 1, true), "runtime nudge does not normalize legacy positions")

local profiles = Read("MidnightSimpleUnitFrames/State/MSUF_Profiles.lua")
Check(Count(profiles, 'MSUF_ProfileIO_CallGlobal("MSUF_GF_InvalidateConfCache")') >= 4, "profile DB swaps leave stale group config refs")
Check(profiles:find('MSUF_ProfileIO_CallGlobal("MSUF_GF_RebuildAll")', 1, true), "profile apply does not rebuild group frames")

local assistant = Read("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_GroupFrames_Core_Register.lua")
Check(assistant:find('gf.EnsureStableGridPosition(scope, count, db)', 1, true), "assistant position writes do not normalize the untouched axis")

print("PASS group frame position: V1 preservation, count-stable V2 bounds, live/preview alignment, roster/profile bridges")
