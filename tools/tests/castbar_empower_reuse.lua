-- Real reset bodies; cast -> channel -> empower reuse, visual sinks and bounded cost.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local function Read(name)
    local f = assert(io.open(root .. "/MidnightSimpleUnitFrames/Castbars/" .. name, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n") f:close() return s
end
local utils, empower, manager = {}, {}, {}
local native = 0
local function Hide() native = native + 1 end
function manager.UnregisterCastbar() native = native + 1 end
local function SetText(_, _) native = native + 1 end
local u = Read("MSUF_CastbarUtils.lua")
local body = assert(u:match("local function ClearEmpowerState.-\nend\nUtils.ClearEmpowerState = ClearEmpowerState"))
local env = setmetatable({ Utils = utils, Manager = manager, Castbars = { Manager = manager }, SetTextIfChanged = SetText }, { __index = _G })
local fn = assert(loadstring(body, "@empower-reset")) setfenv(fn, env)()
local e = Read("MSUF_CastbarEmpower.lua")
local playerBody = e:match("local function PlayerCastbarClearEmpower.-\nend\n")
if playerBody then
    local chunk = assert(loadstring(playerBody .. "return PlayerCastbarClearEmpower", "@player-reset"))
    setfenv(chunk, env) empower.Clear = chunk()
else
    assert(e:find("Empower.PlayerCastbar_ClearEmpower = Utils.ClearEmpowerState", 1, true), "player reset is not the shared owner")
    empower.Clear = utils.ClearEmpowerState
end
local fields = { "isEmpower", "empowerStartTime", "empowerStageEnds", "empowerTotalBase", "empowerTotalWithGrace",
    "empowerNextStage", "MSUF_empowerLayoutPending", "MSUF_wantsEmpower", "MSUF_empowerRetryCount",
    "MSUF_empowerRetryActive", "_msufEmpowerTotalNum", "_msufEmpowerStartNum", "_msufEmpowerBaseNum",
    "_msufEmpowerStageEndsNum", "_msufEmpowerMinMaxSet", "_msufEmpowerElapsed", "_msufEmpowerTimerDriven" }
local frame = { empowerTicks = { { Hide = Hide, MSUF_glow = { Hide = Hide }, MSUF_flash = { Hide = Hide } } },
    empowerSegments = { { Hide = Hide } }, timeText = {}, latencyBar = { Hide = Hide }, Hide = Hide,
    SetScript = function() native = native + 1 end }
for resetIndex, reset in ipairs({ utils.ClearEmpowerState, empower.Clear }) do
    for _ = 1, 20 do reset(frame, false) end
    local vm = 0
    debug.sethook(function()
        local s = debug.getinfo(2, "S").source
        if s == "@empower-reset" or s == "@player-reset" then vm = vm + 1 end
    end, "", 1)
    native = 0
    for _ = 1, 100 do reset(frame, false) end
    debug.sethook()
    local minimum = math.huge
    for _ = 1, 2 do
        collectgarbage("collect") collectgarbage("stop")
        local kb = collectgarbage("count")
        for _ = 1, 1000 do reset(frame, false) end
        minimum = math.min(minimum, collectgarbage("count") - kb)
        collectgarbage("restart")
    end
    print(string.format("empower %s: %.0f VM/reset, 4 native hides, %.3f KB/1000", resetIndex == 1 and "shared" or "player", vm / 100, minimum))
    assert(vm / 100 <= (resetIndex == 1 and 57 or 62), "reset exceeded original VM budget")
    assert(minimum <= 0.001, "reset allocated")
end
for _, kind in ipairs({ "cast", "channel", "empower" }) do
    for _, key in ipairs(fields) do frame[key] = 7 end
    frame.kind = kind
    empower.Clear(frame, false)
    for _, key in ipairs(fields) do assert(frame[key] == nil, kind .. " reuse retained " .. key) end
    assert(frame.kind == kind, "reset changed unrelated cast state")
end
native = 0
empower.Clear(frame, true)
assert(native == 9, "player hide sinks changed: " .. native)
assert(empower.Clear == utils.ClearEmpowerState, "two reset owners remain")
print("castbar_empower_reuse: PASS")

-- Exercise the real player event routes on the same frame, with plain and
-- restricted cast tuples. Timings belong to the existing runtime unchanged.
local World = dofile(root .. "/tools/tests/castbar_secret_world.lua")
for _, secret in ipairs({ false, true }) do
    local world = World.New(root, { budget = true, playerClass = "EVOKER" })
    local env = world.env
    world.core.Require("MSUF_EnsureDB", "empower reuse test")(true)
    env.MSUF_DB.general.showGCDBar = false
    world.core.Require("MSUF_Castbars_OnSettingsChanged", "empower reuse test")()
    world:Advance(0.5)
    for i = #world.errors, 1, -1 do world.errors[i] = nil end
    world.secretCasts = secret
    local player = assert(world.core.Castbars.Frames.Get("player"))
    local function Fire(event, id) world:Fire(player, event, world:Payload(event, "player", id)) end
    local watch = world:Watch(world:CastbarPaths())
    world:StartCast("player", "Normal cast", 2, 501)
    Fire("UNIT_SPELLCAST_START", 501)
    assert(player:IsShown() and player.MSUF_castActive == true, "initial cast missing")
    world.casting.player = nil
    Fire("UNIT_SPELLCAST_STOP", 501)
    world:StartChannel("player", "Channel", 3, 502)
    Fire("UNIT_SPELLCAST_CHANNEL_START", 502)
    assert(player:IsShown() and player.MSUF_isChanneled == true, "channel reuse missing")
    world.channeling.player = nil
    Fire("UNIT_SPELLCAST_CHANNEL_STOP", 502)
    world:StartChannel("player", "Fire Breath", 1.2, 503, { empowered = true, spellID = 357208 })
    Fire("UNIT_SPELLCAST_EMPOWER_START", 503)
    assert(player:IsShown() and player.isEmpower == true and player._msufCountsDown == false, "empower reuse retained channel drain")
    world:Advance(0.1)
    world.channeling.player = nil
    Fire("UNIT_SPELLCAST_EMPOWER_STOP", 503)
    world:Advance(0.1)
    for _, key in ipairs(fields) do assert(player[key] == nil, "real empower stop retained " .. key) end
    world:StartCast("player", "Next cast", 2, 504)
    Fire("UNIT_SPELLCAST_START", 504)
    assert(player:IsShown() and player.MSUF_castActive == true and not player.isEmpower, "post-empower cast missing")
    local violations = watch()
    assert(#violations == 0, table.concat(violations, " | "))
    assert(#world.errors == 0, table.concat(world.errors, " | "))
end
print("castbar_empower_reuse: real cast/channel/empower routes PASS")
