-- The actual fallback/capture reset prefixes, including caller-only fields.
-- <repoRoot> [measure]: measure records the original duplicate owners.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local measure = arg[2] == "measure"
local dir = arg[3] or root .. "/MidnightSimpleUnitFrames/Castbars/"
local function Read(name)
    local f = assert(io.open(dir .. name, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n") f:close() return s
end
local utils, env = {}, {}
setmetatable(env, { __index = _G })
env.Utils = utils
local shared = Read("MSUF_CastbarUtils.lua"):match("local function ResetTimingScalars.-\nUtils.ResetTimingScalars = ResetTimingScalars")
if shared then local chunk = assert(loadstring(shared, "@timing-owner")) setfenv(chunk, env)() end
local sharedFields = { "endTime", "_msufPlainEndTime", "_msufPlainTotal", "_msufRemaining", "_msufLastTimeDecimal",
    "_msufTimerAssumeCountdown", "_msufCountsDown", "_msufPushbackMS", "_msufZeroCount" }
local preserved = { "_msufPushbackCastID", "_msufPushbackStartMS", "_msufStableDurationObj", "MSUF_durationObj",
    "MSUF_castDuration", "isManagedFrame", "_msufStopPending" }
local function Compile(file, name, caller, finish)
    local s = Read(file)
    local definition = s:match("local function " .. name .. "%b().-\nend\n")
        or assert(s:match("local " .. name .. " = [^\n]+\n"))
    local prefix = assert(s:match("local function " .. caller .. "%b()%s*\n(.-)" .. finish))
    local chunk = assert(loadstring(definition .. "return function(frame)\n" .. prefix .. "end, " .. name, "@" .. file))
    setfenv(chunk, env)
    return chunk()
end
local fallback, fallbackOwner = Compile("MSUF_CastbarDriver.lua", "ResetFallbackTiming", "ApplyFallbackActiveDuration", "    local remaining, total")
local player, playerOwner = Compile("MSUF_PlayerCastbarRuntime.lua", "ResetTimingFields", "CaptureCastTimes", "    startMS = PlainNumber")
for index, reset in ipairs({ fallback, player }) do
    local frame = {}
    for _, key in ipairs(sharedFields) do frame[key] = 7 end
    for _, key in ipairs(preserved) do frame[key] = 9 end
    frame._msufLastDurationObj, frame._msufLastTimeTotalDecimal, frame._msufLastSBValue = 8, 8, 8
    reset(frame)
    for _, key in ipairs(sharedFields) do assert(frame[key] == nil, key .. " retained") end
    for _, key in ipairs(preserved) do assert(frame[key] == 9, key .. " changed") end
    assert(frame._msufLastDurationObj == (index == 1 and 8 or nil), "player-only field changed")
    assert(frame._msufLastTimeTotalDecimal == (index == 2 and 8 or nil), "driver-only total changed")
    assert(frame._msufLastSBValue == (index == 2 and 8 or nil), "driver-only value changed")
    local vm = 0
    debug.sethook(function()
        local source = debug.getinfo(2, "S").source
        if source == "@timing-owner" or source == "@MSUF_CastbarDriver.lua" or source == "@MSUF_PlayerCastbarRuntime.lua" then
            vm = vm + 1
        end
    end, "", 1)
    for _ = 1, 100 do reset(frame) end
    debug.sethook()
    print(string.format("timing %d: %.0f VM/reset", index, vm / 100))
    if not measure then assert(vm / 100 <= 16, "reset VM budget exceeded") end
    local minKB = math.huge
    for _ = 1, 2 do
        collectgarbage("collect") collectgarbage("stop")
        local kb = collectgarbage("count")
        for _ = 1, 1000 do reset(frame) end
        minKB = math.min(minKB, collectgarbage("count") - kb)
        collectgarbage("restart")
    end
    assert(minKB <= .001, "reset allocated")
end
if not measure then
    assert(utils.ResetTimingScalars and fallbackOwner == utils.ResetTimingScalars and playerOwner == fallbackOwner,
        "duplicate timing reset owners remain")
    local s = Read("MSUF_PlayerCastbarRuntime.lua")
    assert(s:find("ResetTimingFields(frame)\n    frame._msufLastDurationObj = nil\n    ClearActiveCastIdentity", 1, true),
        "stop reset lost player-only field")
end
print("castbar_timing_reset_owner: PASS")
