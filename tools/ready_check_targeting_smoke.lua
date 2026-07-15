_G = _G or _ENV

local path = "MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Status.lua"
local handle = io.open(path, "r")
if not handle then path = "UnitFrames/Engine/Group/MSUF_UF_Group_Status.lua" else handle:close() end

local elements = {}
local updates = {}
local driver
local MSUF = {
    UF = {
        RegisterElement = function(name, element) elements[name] = element end,
        IsUnitToken = function(unit) return type(unit) == "string" and unit ~= "" end,
    },
    GF = { frames = {}, unitFrames = {} },
    UFStatusRuntime = {
        UpdateReadyCheck = function(frame)
            updates[frame.unit] = (updates[frame.unit] or 0) + 1
        end,
    },
}

function MSUF.GF.FrameForUnit(unit)
    local frame = MSUF.GF.unitFrames[unit]
    return frame and frame.unit == unit and frame or nil
end

_G.MSUF_NS = MSUF
_G.MSUF = MSUF
_G.CreateFrame = function()
    local frame = { events = {} }
    function frame:SetScript(_, callback) self.script = callback end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    driver = frame
    return frame
end

local chunk, err = loadfile(path)
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", MSUF)

local element = assert(elements.GroupStatusRuntime, "group status element missing")
local status = {
    groupRuntimeEnabled = true,
    runtimeReadyCheck = true,
    groupRuntimeUnitlessEvents = { "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED" },
}
local frames = {
    { unit = "party1", MSUFSpec = { scope = "group", status = status }, _msufActiveElements = { GroupStatusRuntime = true } },
    { unit = "party2", MSUFSpec = { scope = "group", status = status }, _msufActiveElements = { GroupStatusRuntime = true } },
}
for i = 1, #frames do
    local frame = frames[i]
    MSUF.GF.frames[frame] = true
    MSUF.GF.unitFrames[frame.unit] = frame
    element.Apply(frame)
end

assert(driver and type(driver.script) == "function", "shared status driver missing")
updates = {}
driver.script(driver, "READY_CHECK_CONFIRM", "party1", true)
assert(updates.party1 == 1, "ready-check confirmation must update its target frame")
assert(updates.party2 == nil, "ready-check confirmation must not broadcast to unrelated frames")

updates = {}
MSUF.GF.unitFrames.party1 = nil
driver.script(driver, "READY_CHECK_CONFIRM", "party1", true)
assert(updates.party1 == 1 and updates.party2 == 1,
    "stale unit index must fall back to the correctness-preserving broadcast")
MSUF.GF.unitFrames.party1 = frames[1]

updates = {}
driver.script(driver, "READY_CHECK", "party1", 30)
assert(updates.party1 == 1 and updates.party2 == 1, "ready-check start must remain a broadcast")

print("ready_check_targeting_smoke: ok")
