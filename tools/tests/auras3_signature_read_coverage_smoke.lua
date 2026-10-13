-- Observe actual initializeFrame reads and require declared signature ownership.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local namespace = { Auras3RuntimeFactories = {} }
local path = root .. "/MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_Signatures.lua"
assert(loadfile(path))("MSUF", namespace)
local schema = namespace.Auras3RuntimeFactories.Signatures("MSUF", namespace, {}, {}, function() end, {}).LaneSignatureSchema
assert(schema, "lane signature field schema is missing")
local covered = {}
for _, fields in pairs(schema.Fields) do
    for _, field in ipairs(fields) do
        local key = type(field) == "string" and field or field.path[1]
        covered[key] = true
    end
end
for field, owner in pairs(schema.EncodedBy) do
    assert(covered[owner], field .. " has no signature owner " .. owner)
    covered[field] = true
end
assert(covered.portraitOverlay and covered.appearanceKind, "portrait and appearance inputs must have declared owners")
local reads, buttons, prepare = {}, 0, nil
local finalized = {}
local configSource = assert(io.open(root .. "/MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_ConfigValues.lua", "rb"))
local configText = configSource:read("*a"):gsub("\r\n", "\n")
configSource:close()
local finalizeOffset = assert(configText:find("local function FinalizeLane(", 1, true))
local _, finalizeLine = configText:sub(1, finalizeOffset):gsub("\n", "\n")
finalizeLine = finalizeLine + 1
local function Proxy(lane)
    return setmetatable({}, {
        __index = function(_, key)
            if type(key) == "string" and not key:match("^_msuf") then reads[key] = true end
            return lane[key]
        end,
        __newindex = function(_, key, value) lane[key] = value end,
    })
end
local function Hook(event)
    local info = debug.getinfo(2, "Sn")
    if info.source:find("Runtime_ButtonVisuals.lua", 1, true) and event == "return" then
        for index = 1, 100 do
            local name, value = debug.getlocal(2, index)
            if not name then break end
            if name == "PrepareAuraButton" then prepare = value end
        end
    end
    if event == "call" and info.source:find("Runtime_ConfigValues.lua", 1, true) and info.linedefined == finalizeLine then
        local _, lane = debug.getlocal(2, 1)
        if type(lane) == "table" then finalized[#finalized + 1] = lane end
    end
end
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
debug.sethook(Hook, "cr")
local h = Harness.New(root, flavor)
local GF = h.GF
GF.GetConf("raid").enabled = true
GF.RefreshHeaderLayout()
h:SetRaid(5)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
debug.sethook()
assert(prepare, "runtime button preparer was not bound")
local methods = h.widgets.Methods
local source = assert(io.open(root .. "/MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_NativeContract.lua", "rb"))
local contract = source:read("*a")
source:close()
local methodList = assert(contract:match("local NATIVE_AURA_BUTTON_METHODS = (%b{})"))
for name in methodList:gmatch('"([^"]+)"') do methods[name] = methods[name] or function() end end
assert(#finalized > 0, "real finalized lanes were not captured")
local A3 = h.core.MSUF_Auras3
local portrait = assert(A3.Runtime.CustomConfig.CompilePortraitAuraLane(finalized[1],
    { portrait = { enabled = true, size = 24, width = 24, height = 24, shape = "SQUARE" } }, {},
    "targetDotPortrait", "TargetDotPortrait", "target", true))
assert(portrait.portraitOverlay == true and portrait.kind == "targetDotPortrait", "portrait input must be encoded by lane kind")
finalized[#finalized + 1] = portrait
for _, lane in ipairs(finalized) do
    local style = A3.Runtime.ConfigValues.SharedIconStyle(lane.appearanceKind)
    assert(lane.iconStyle.signature == style.signature, "appearance kind must resolve to the signed icon style")
    for _, durationBar in ipairs({ false, true }) do
        local copy = {}
        for key, value in pairs(lane) do copy[key] = value end
        copy.showDurationBar = durationBar
        copy.durationBarDisplay = "BAR_AND_ICON"
        local button = h.env.CreateFrame("Button", nil, h.widgets.UIParent)
        prepare(button, Proxy(copy), 1)
        buttons = buttons + 1
    end
end
assert(buttons > 0 and reads.portraitOverlay, "real native initializeFrame reads were not exercised")
for field in pairs(reads) do
    assert(covered[field], "initializeFrame reads unsigned config field: " .. field)
end
print("auras3_signature_read_coverage_smoke: ok (" .. flavor .. ", " .. buttons .. " native buttons)")
