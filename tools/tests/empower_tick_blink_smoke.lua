-- empower_tick_blink_smoke.lua <repoRoot> [print]
--
-- An empowered cast blinks a stage tick when the cast reaches that stage
-- (MSUF_BlinkEmpowerTick, Castbars/MSUF_CastbarEmpower.lua): the tick turns
-- red and wide, and one stage-blink time later it returns to its base width
-- and colour. A tick that blinks again before that keeps the blink until the
-- later blink ends. Pinned:
--   * the blink and its reset, on the exact deadline;
--   * a re-blink defers the reset to the last blink's deadline;
--   * budget: one blink, Lua VM instructions and bytes with the collector
--     stopped (frozen 2026-10-02 from the cost before the reset callback was
--     hoisted out of the blink, plus 2 %).
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local printOnly = arg[2] == "print"

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

-- C_Timer.After in deadline order; parallel arrays so the fake client itself
-- allocates nothing per timer.
local now = 10
local dues, fns, count = {}, {}, 0
_G.GetTime = function() return now end
_G.C_Timer = {
    After = function(delay, fn)
        count = count + 1
        dues[count], fns[count] = now + delay, fn
    end,
}
local function Advance(seconds)
    now = now + seconds
    local index = 1
    while index <= count do
        if dues[index] <= now + 1e-9 then
            local fn = fns[index]
            for move = index, count - 1 do dues[move], fns[move] = dues[move + 1], fns[move + 1] end
            dues[count], fns[count] = nil, nil
            count = count - 1
            fn()
        else
            index = index + 1
        end
    end
end

_G.MSUF_DB = { general = { empowerStageBlinkTime = 0.2 } }
_G.MSUF_EnsureDBLazy = function() end
_G.MSUF_Castbar_PlainNumber = function(value) return tonumber(value) end
local ns = { ExportPublic = function(name, value) _G[name] = value return value end }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarEmpower.lua"))("MidnightSimpleUnitFrames", ns)
local blink = assert(_G.MSUF_BlinkEmpowerTick, "MSUF_BlinkEmpowerTick missing")
local blinkTime = assert(_G.MSUF_GetEmpowerStageBlinkTime, "MSUF_GetEmpowerStageBlinkTime missing")()

local tick = { width = 2, red = 1, green = 1, blue = 1, alpha = 0.9 }
function tick:SetWidth(width) self.width = width end
function tick:SetVertexColor(r, g, b, a) self.red, self.green, self.blue, self.alpha = r, g, b, a end
local frame = { empowerTicks = { tick } }

-- One blink and its reset.
blink(frame, 1)
local blinkWidth, baseWidth = tick.width, nil
Check(tick.red == 1.0 and tick.green == 0.10, "the blink did not turn the tick red")
Advance(blinkTime - 0.01)
Check(tick.width == blinkWidth and tick.green == 0.10, "the blink ended early")
Advance(0.02)
baseWidth = tick.width
Check(baseWidth ~= blinkWidth and tick.green == 1.0, "the blink did not end on its deadline")

-- A re-blink before the reset keeps the tick lit until the last blink ends.
blink(frame, 1)
Advance(blinkTime * 0.5)
blink(frame, 1)
Advance(blinkTime * 0.5 + 0.01)
Check(tick.width == blinkWidth and tick.green == 0.10, "the first blink's reset ended the second blink")
Advance(blinkTime * 0.5)
Check(tick.width == baseWidth and tick.green == 1.0, "the second blink did not end on its own deadline")
Check(count == 0, "a blink left a timer behind")

-- Budget ------------------------------------------------------------------
-- Before the hoist: 164 instructions and 164 bytes (a reset closure per blink).
local BUDGET = { 167, 8 }
local function Blink()
    blink(frame, 1)
    Advance(blinkTime + 0.01)
end
for _ = 1, 50 do Blink() end
local ticks = 0
debug.sethook(function() ticks = ticks + 1 end, "", 1)
for _ = 1, 200 do Blink() end
debug.sethook()
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 2000 do Blink() end
local bytes = (collectgarbage("count") - before) * 1024 / 2000
collectgarbage("restart")
local line = string.format("empower tick blink %8.1f instructions %8.1f bytes  (budget %d / %d)",
    ticks / 200, bytes, BUDGET[1], BUDGET[2])
if printOnly then print(line) return end
Check(ticks / 200 <= BUDGET[1] and bytes <= BUDGET[2], "empower tick blink over budget: " .. line)
print("empower_tick_blink_smoke: ok (" .. line .. ")")
