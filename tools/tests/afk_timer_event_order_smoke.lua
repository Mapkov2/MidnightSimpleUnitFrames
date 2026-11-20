-- The AFK timer must repaint even if the group driver sees a flag before the timer listener.
local root, flavor = assert(arg[1]), arg[2] or "Forever"
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local secret = Secrets.New("boolean")
local afk, now, ticker, timerDriver = {}, 100
local tickerStarts = 0
local ledgerFile = "/MSUF_UF_Elements_StatusAFKTimer.lua"
local h = Harness.New(root, flavor, { beforeBoot = function(world)
    local env = world.env
    env.issecretvalue = issecretvalue
    env.UnitIsAFK = function(unit) return afk[unit] end
    env.GetTime = function() return now end
    env.C_Timer.NewTicker = function(interval, callback)
        assert(interval == 10 and not ticker, "expected one shared AFK ticker")
        tickerStarts = tickerStarts + 1
        ticker = callback
        return { Cancel = function() ticker = nil end }
    end
end, afterFile = function(world, path)
    if not path:find(ledgerFile, 1, true) then return end
    for _, frame in ipairs(world.widgets.frames) do
        local handler = frame.scripts and frame.scripts.OnEvent
        if handler and debug.getinfo(handler, "S").source:find(ledgerFile, 1, true) then
            timerDriver = frame
            break
        end
    end
end })
local driver = assert(timerDriver, "missing AFK-timer event listener")
local handleTimerEvent = driver.scripts.OnEvent
local GF = h.GF
local unit, other = "party1", "party2"
local conf = GF.GetConf("party")
conf.enabled, conf.statusAFKText, conf.statusAFKTimerText = true, true, true
GF.InvalidateCompiledSpecs("party")
GF.RefreshHeaderLayout()
h:SetRoster({ "player", unit, other })
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local frame = assert(GF.FrameForUnit(unit))
local otherFrame = assert(GF.FrameForUnit(other))
local groupDriver
for _, candidate in ipairs(h.widgets.frames) do
    local handler = candidate.scripts and candidate.scripts.OnEvent
    if handler and candidate.events.PLAYER_FLAGS_CHANGED
        and debug.getinfo(handler, "S").source:find("/MSUF_UF_Group_Status.lua", 1, true) then
        groupDriver = candidate
        break
    end
end
assert(groupDriver, "group status runtime did not subscribe to flags")
local function GroupFlags(token)
    h.RunInsecure(groupDriver.scripts.OnEvent, groupDriver, "PLAYER_FLAGS_CHANGED", token)
end
local function TimerFlags(token)
    assert(driver.events.PLAYER_FLAGS_CHANGED, "timer listener suspended")
    h.RunInsecure(handleTimerEvent, driver, "PLAYER_FLAGS_CHANGED", token)
end
local function Expect(frame, expected)
    local region = frame.statusAFKTimerText
    local text = region and region:IsShown() and region:GetText() or nil
    assert(text == expected, flavor .. ": expected " .. tostring(expected) .. ", got " .. tostring(text))
end

local stop = Secrets.Watch(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements" .. ledgerFile, { strict = true })
afk[other] = true
assert(GF.ApplyButton(otherFrame, "party", "MSUF_GF_AFK_TEST"))
Expect(otherFrame, nil)
assert(tickerStarts == 0, "an unknown AFK start must not arm a ticker")
afk[unit] = true
GroupFlags(unit)
assert(frame.statusIndicatorText:IsShown() and frame.statusIndicatorText:GetText() == h.core.Translate("AFK"),
    "the group driver must paint AFK before the timer listener")
Expect(frame, nil)
TimerFlags(unit)
Expect(frame, "<1m")
Expect(otherFrame, nil)
assert(tickerStarts == 1, "the known start must arm exactly one ticker")
now = 161
ticker()
Expect(frame, "1m")
TimerFlags(unit)
Expect(frame, "1m")

h:EnterCombat(function()
    Expect(frame, nil)
    assert(not ticker and not driver.events.PLAYER_FLAGS_CHANGED, "combat entry must suspend AFK tracking")
end)
h:LeaveCombat()
Expect(frame, "1m")

afk[unit] = false
TimerFlags(unit)
GroupFlags(unit)
Expect(frame, nil)
assert(not ticker, "last AFK timer must stop ticking")

-- The timer-first order also works, including with AFK Text disabled.
conf.statusAFKText = false
GF.InvalidateCompiledSpecs("party")
assert(GF.ApplyButton(frame, "party", "MSUF_GF_AFK_TEST"))
afk[unit] = true
TimerFlags(unit)
GroupFlags(unit)
Expect(frame, "<1m")
assert(not frame.statusIndicatorText:IsShown(), "separately disabled AFK text must stay hidden")
afk[unit] = false
GroupFlags(unit)
TimerFlags(unit)
Expect(frame, nil)

afk[unit] = secret
TimerFlags(unit)
GroupFlags(unit)
Expect(frame, nil)
assert(not ticker, "a secret AFK flag must not create a stamp")
stop()
print("AFK timer event order passed (" .. flavor .. ")")
