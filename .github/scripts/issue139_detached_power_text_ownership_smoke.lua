-- Issue #139: detachedPowerBarTextOnBar owns placement only. Neither Menu2
-- surface may couple it to the separate showPowerText visibility setting.

local root = arg and arg[1] or "."

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a") or ""
    file:close()
    return source
end

local function Block(source, firstMarker, nextMarker, label)
    local first = assert(source:find(firstMarker, 1, true), "missing " .. label)
    local nextAt = assert(source:find(nextMarker, first + #firstMarker, true),
        "missing end of " .. label)
    return source:sub(first, nextAt - 1)
end

local function Compact(source)
    return (source:gsub("%s+", " "))
end

local visuals = Read(
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua")
local unitBlock = Block(visuals,
    "local detachedTextFields = BuildPowerControls",
    "detachedTextToggle =",
    "Unit Frames detached Power text descriptor")
local compactUnit = Compact(unitBlock)

assert(compactUnit:find(
    '"detachedPowerBarTextOnBar", false, "MSUF2_POWER_DETACHED_TEXT", nil, nil, POWER_TEXT_OPTS }',
    1, true),
    "Unit Frames detached placement must use reason, nil, nil, POWER_TEXT_OPTS")
assert(not unitBlock:find("showPowerText", 1, true),
    "Unit Frames detached placement still reads or writes showPowerText")

local advanced = Read(
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua")
local binderBlock = Block(advanced,
    "detachedTextOnBar = function",
    "detachedTextPreset = function",
    "Class Resources detached Power text binder")
local compactBinder = Compact(binderBlock)

assert(compactBinder:find(
    "M.BindBoolWidget(self.ctx, control, function() return BoolValue(source(), key, default) end,",
    1, true),
    "Class Resources detached placement getter must read the raw BoolValue")
assert(compactBinder:find(
    "if player[key] ~= value then player[key], changed = value, true end",
    1, true),
    "Class Resources detached placement setter must write only its own key")

for _, forbidden in ipairs({
    "showPowerText",
    "PlayerPowerTextShown",
    "SetPlayerPowerTextShown",
}) do
    assert(not binderBlock:find(forbidden, 1, true),
        "Class Resources detached placement binder still couples " .. forbidden)
end

print("issue139 detached Power text ownership smoke: ok")
