-- <repoRoot> [measure] [runtimePath]: required provider, real resolver, bounded ApplyActive cost.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local measure = arg[2] == "measure"
local path = arg[3] or root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarRuntime.lua"
local utilsPath = root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua"
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local function Read(file)
    local f = assert(io.open(file, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return s
end
local source, utilsSource = Read(path), Read(utilsPath)
local first, last = utilsSource:find("local function ResolveCastbarPushbackMS%b().-\nend\n")
local _, lines = utilsSource:sub(1, first - 1):gsub("\n", "\n")
local function PlainNumber(value)
    if issecretvalue(value) then return nil end
    if type(value) == "number" and value == value and value > -math.huge and value < math.huge then return value end
end
local providerChunk = assert(loadstring(string.rep("\n", lines) .. utilsSource:sub(first, last)
    .. "return ResolveCastbarPushbackMS", "@" .. utilsPath))
setfenv(providerChunk, setmetatable({ PlainNumber = PlainNumber, IsSecretValue = issecretvalue }, { __index = _G }))
local provider = providerChunk()
local nativeCalls, providerCalls = 0, 0
local function Resolve(frame, state)
    providerCalls = providerCalls + 1
    return provider(frame, state)
end
local function Load(value)
    local utils = { Castbar_ResolvePushbackMS = value, Castbar_PlainNumber = PlainNumber,
        GetCastbarReverseFillForFrame = function() return false end }
    local ns = { Scheduler = {}, Castbars = { Config = { Read = function() return { general = {} } end },
        Driver = {}, Engine = {}, Manager = {}, PublicAPI = {}, Runtime = {}, Utils = utils } }
    ns.Require = function(name)
        if name == "MSUF" then return ns end
        assert(name == "MSUF_UF_ApplyCastbarRangeAlpha", name)
        return function() end
    end
    local env = setmetatable({ issecretvalue = issecretvalue }, { __index = _G })
    local chunk = assert(loadstring(source, "@" .. path))
    setfenv(chunk, env)
    chunk("MidnightSimpleUnitFrames", ns)
    return ns.Castbars.Runtime, utils
end
local runtime, utils = Load(Resolve)
local frame = { unit = "target", statusBar = {}, castText = { SetText = function(self, text) self.text = text end } }
local state = { active = true, durationObj = {}, spellName = "Cast", castType = "CAST", castID = 12,
    startTimeMS = 1000, spellSequenceID = 12 }
local options = { skipSnapshot = true, skipCastState = true, skipColor = true, skipShow = true,
    skipRegister = true, skipTimeText = true }
local function Apply() assert(runtime:ApplyActive(frame, state, options)) end
Apply()
assert(frame._msufPushbackMS == nil and frame.MSUF_timerDriven == false, "initial legacy/no-native path changed")
state.startTimeMS = 1250
Apply()
assert(frame._msufPushbackMS == 250, "legacy pushback missing")
state.delayTimeMS = 400
Apply()
assert(frame._msufPushbackMS == 400, "native pushback did not win")
state.delayTimeMS = nil
state.castType = "CHANNEL"
Apply()
assert(frame._msufPushbackMS == nil and frame._msufPushbackCastID == nil, "channel retained legacy pushback")
state.castType, state.castBarID = "CAST", 18
Apply()
assert(frame._msufPushbackMS == nil, "modern cast used legacy pushback")
state.castBarID = nil
frame.statusBar.SetTimerDuration = function() nativeCalls = nativeCalls + 1 end
Apply()
assert(frame.MSUF_timerDriven == true, "native timer capability was dropped")
state.delayTimeMS = Secrets.New("number")
local stop = Secrets.Watch({ path, utilsPath }, { strict = true })
Apply()
local violations = stop()
assert(#violations == 0 and frame._msufPushbackMS == nil, table.concat(violations, "\n"))
state.delayTimeMS = 400
for _ = 1, 30 do Apply() end
local vm = 0
debug.sethook(function()
    local file = debug.getinfo(2, "S").source
    if file == "@" .. path or file == "@" .. utilsPath then vm = vm + 1 end
end, "", 1)
local nativesBefore, callsBefore = nativeCalls, providerCalls
for _ = 1, 100 do Apply() end
debug.sethook()
assert(nativeCalls - nativesBefore == 100 and providerCalls - callsBefore == 100, "apply call budget changed")
local minimum = math.huge
for _ = 1, 2 do
    collectgarbage("collect")
    for _ = 1, 30 do Apply() end
    collectgarbage("stop")
    local kb = collectgarbage("count")
    for _ = 1, 1000 do Apply() end
    minimum = math.min(minimum, collectgarbage("count") - kb)
    collectgarbage("restart")
end
print(string.format("ApplyActive: %.0f VM/apply, %.3f KB/1000, 1 provider + 1 native timer/apply", vm / 100, minimum))
assert(minimum <= .001, "ApplyActive allocated")
if measure then return end
-- Before binding: 222 VM/apply; direct binding: 215, with identical native calls.
assert(vm / 100 <= 215, "ApplyActive exceeded the bound-provider VM budget")
-- A required provider must fail at load, with an actionable diagnostic.
for _, invalid in ipairs({ false, true, 42, "provider", {} }) do
    local ok, message = pcall(Load, invalid)
    assert(not ok and tostring(message):find("Castbar_ResolvePushbackMS", 1, true), "invalid provider was not rejected at load")
end
local ok, message = pcall(Load, nil)
assert(not ok and tostring(message):find("Castbar_ResolvePushbackMS", 1, true), "missing provider was not rejected at load")
-- After loading, neither a namespace lookup nor a replacement provider may affect ApplyActive.
utils.Castbar_ResolvePushbackMS = nil
setmetatable(utils, { __index = function(_, key)
    assert(key ~= "Castbar_ResolvePushbackMS", "ApplyActive looked up its guaranteed provider again")
end })
local before = providerCalls
Apply()
assert(providerCalls == before + 1 and frame._msufPushbackMS == 400, "bound provider was bypassed")
local World = dofile(root .. "/tools/tests/client_world.lua")
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local graph = World.Graph(root, World.CoreTOC(flavor == "Forever" and "Mainline" or flavor),
        "enUS", flavor == "Forever" and "camelot" or nil)
    local providerIndex, consumerIndex
    for i, file in ipairs(graph) do
        if file:find("Castbars/MSUF_CastbarUtils.lua", 1, true) then providerIndex = i end
        if file:find("Castbars/MSUF_CastbarRuntime.lua", 1, true) then consumerIndex = i end
    end
    assert(providerIndex and consumerIndex and providerIndex < consumerIndex, flavor .. " provider must load first")
end
print("castbar_pushback_provider: PASS")
