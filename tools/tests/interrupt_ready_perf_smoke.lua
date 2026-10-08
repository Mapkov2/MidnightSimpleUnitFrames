-- interrupt_ready_perf_smoke.lua <repoRoot>
--
-- Classic port of the Retail repository's tools/interrupt_ready_perf_smoke.lua:
-- secret-safe readiness tint, one shared native cooldown driver, no Lua timer
-- fallback, no Duration read for unrelated cooldown events, and one readiness
-- snapshot per rendered frame. The namespace carries ExportPublic as the
-- client TOC provides it. Instruction and allocation budgets close the file.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
_G = _G or _ENV

local eventHandler
local cooldownDoneHandler
local cooldownReads = 0
local cooldownFrameCreates = 0
local cooldownSetCalls = 0
local cooldownClearCalls = 0
local timerAfterCalls = 0
local focusReadyRefreshes = 0
local lastIgnoreGCD
local frameStamp = 100
_G.GetTime = function() return frameStamp end

local secretReady = { secret = true, value = true }
local secretRemaining = { secret = true }

_G.MSUF_DB = {
    general = {
        kickReadyShowTarget = true,
        kickReadyStyle = "border",
        kickReadyColor = { ["1"] = 0.1, ["2"] = 0.8, ["3"] = 0.2 },
        kickNotReadyColor = { ["1"] = 0.9, ["2"] = 0.1, ["3"] = 0.2 },
    },
}
_G.MSUF_EnsureDB = function() end
_G.UnitClass = function() return "Mage", "MAGE" end
_G.IsPlayerSpell = function(spellID) return spellID == 2139 end
_G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
_G.CreateColor = function(red, green, blue, alpha)
    return { GetRGBA = function() return red, green, blue, alpha end }
end
_G.C_Timer = {
    After = function()
        timerAfterCalls = timerAfterCalls + 1
    end,
}

local cooldownObject = {
    GetRemainingDuration = function() return secretRemaining end,
    IsZero = function() return secretReady end,
}
_G.C_Spell = {
    GetSpellCooldownDuration = function(_, ignoreGCD)
        cooldownReads = cooldownReads + 1
        lastIgnoreGCD = ignoreGCD
        return cooldownObject
    end,
}

local scalarCalls = 0
_G.C_CurveUtil = {
    EvaluateColorValueFromBoolean = function(value, ifTrue, ifFalse)
        scalarCalls = scalarCalls + 1
        return value.value and ifTrue or ifFalse
    end,
    EvaluateColorFromBoolean = function(value, ifTrue, ifFalse)
        return value.value and ifTrue or ifFalse
    end,
}

_G.CreateFrame = function(frameType)
    if frameType == "Cooldown" then
        cooldownFrameCreates = cooldownFrameCreates + 1
        return {
            SetSize = function() end,
            SetAlpha = function() end,
            SetDrawSwipe = function() end,
            SetDrawEdge = function() end,
            SetDrawBling = function() end,
            SetHideCountdownNumbers = function() end,
            Show = function() end,
            Clear = function()
                cooldownClearCalls = cooldownClearCalls + 1
            end,
            SetCooldownFromDurationObject = function(_, duration, clearIfZero)
                assert(duration == cooldownObject)
                assert(clearIfZero == true)
                cooldownSetCalls = cooldownSetCalls + 1
            end,
            SetScript = function(_, script, callback)
                if script == "OnCooldownDone" then
                    cooldownDoneHandler = callback
                end
            end,
        }
    end

    return {
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        UnregisterAllEvents = function() end,
        SetScript = function(_, script, callback)
            if script == "OnEvent" then eventHandler = callback end
        end,
    }
end

local interruptNamespace = { ExportPublic = function(name, value) _G[name] = value return value end,
    Scheduler = { ScheduleAfter = function() return true end, CancelScheduled = function() return false end } }
-- Castbars/MSUF_CastbarStyle.lua (not loaded here) owns the castbar outline the
-- border style restores; every TOC loads it before the indicator.
_G.MSUF_ApplyCastbarOutline = function() end
-- Castbars/MSUF_CastbarUtils.lua loads first in every TOC (the interrupt-ready unit rule).
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua"))(
    "MidnightSimpleUnitFrames", interruptNamespace)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_InterruptReady.lua"))(
    "MidnightSimpleUnitFrames", interruptNamespace)
-- The utilities' own next-frame refresh at load is not a cooldown timer.
timerAfterCalls = 0

-- Preserve the existing scalar-composition contract for secret
-- interruptibility values.
local secretTrue = { secret = true, value = true }
local secretFalse = { secret = true, value = false }
local red, green, blue, alpha = _G.MSUF_KickReady_EvaluateRGBA(true, secretTrue)
assert(red == 0.6 and green == 0.6 and blue == 0.6 and alpha == 1)
assert(scalarCalls == 3, "secret RGB must use three scalar evaluations")

red, green, blue, alpha = _G.MSUF_KickReady_EvaluateRGBA(true, secretFalse)
assert(red == 0.1 and green == 0.8 and blue == 0.2 and alpha == 1)
assert(scalarCalls == 6)

red, green, blue, alpha = _G.MSUF_KickReady_EvaluateRGBA(false, false)
assert(red == 0.9 and green == 0.1 and blue == 0.2 and alpha == 1)
assert(scalarCalls == 6, "plain values must bypass curve evaluation")

local lastBorderColor
local function Edge()
    return {
        SetVertexColor = function(_, r, g, b, a)
            lastBorderColor = { r, g, b, a }
        end,
    }
end

local targetFrame = {
    unit = "target",
    MSUF_castActive = true,
    isNotInterruptible = false,
    _msufApiNotInterruptibleRaw = false,
    statusBar = {},
    _msufOutline = {
        top = Edge(),
        bottom = Edge(),
        left = Edge(),
        right = Edge(),
    },
}
_G.MSUF_TargetCastbar = targetFrame
_G.MSUF_FocusKick_RefreshReadyColor = function()
    focusReadyRefreshes = focusReadyRefreshes + 1
end

-- A secret true readiness value must paint green without being inspected in
-- Lua, and it must arm exactly one native cooldown completion driver.
_G.MSUF_KickReady_RefreshFrame(targetFrame, {
    active = true,
    apiNotInterruptibleRaw = false,
})
assert(lastBorderColor[1] == 0.1 and lastBorderColor[2] == 0.8 and lastBorderColor[3] == 0.2)
assert(lastIgnoreGCD == true, "interrupt readiness must ignore unrelated GCD timing")
assert(cooldownFrameCreates == 1 and cooldownSetCalls == 1)
assert(type(cooldownDoneHandler) == "function")
assert(timerAfterCalls == 0, "native cooldown wakeup must not fall back to a Lua timer")

assert(type(eventHandler) == "function")
local readsBefore = cooldownReads
eventHandler(nil, "SPELL_UPDATE_COOLDOWN", 42, 42, nil, 1337)
assert(cooldownReads == readsBefore, "unrelated spell/GCD events must not read the interrupt Duration")

-- The exact interrupt event paints red through the secret boolean. A native
-- completion callback then repaints green once without polling.
secretReady.value = false
eventHandler(nil, "SPELL_UPDATE_COOLDOWN", 2139, 2139)
assert(lastBorderColor[1] == 0.9 and lastBorderColor[2] == 0.1 and lastBorderColor[3] == 0.2)
assert(cooldownFrameCreates == 1, "all indicator frames must share one cooldown driver")
assert(cooldownSetCalls == 2)
assert(focusReadyRefreshes == 1)

secretReady.value = true
cooldownDoneHandler()
assert(lastBorderColor[1] == 0.1 and lastBorderColor[2] == 0.8 and lastBorderColor[3] == 0.2)
assert(focusReadyRefreshes == 2)
assert(timerAfterCalls == 0)

-- Fill style reuses the same driver and receives one event repaint plus one
-- cooldown-end repaint. The readiness value stays secret throughout.
_G.MSUF_DB.general.kickReadyStyle = "fill"
local fillRefreshes = 0
local lastFillReady
targetFrame.UpdateColorForInterruptible = function()
    fillRefreshes = fillRefreshes + 1
    lastFillReady = _G.MSUF_KickReady_GetReadyBoolForTint()
end
_G.MSUF_KickReady_RefreshFrame(targetFrame, { active = true })

secretReady.value = false
eventHandler(nil, "SPELL_UPDATE_COOLDOWN", 2139, 2139)
assert(fillRefreshes == 1 and _G.issecretvalue(lastFillReady) == true and lastFillReady.value == false,
    "fill refreshes=" .. tostring(fillRefreshes)
        .. " secret=" .. tostring(_G.issecretvalue(lastFillReady))
        .. " value=" .. tostring(lastFillReady and lastFillReady.value))

secretReady.value = true
cooldownDoneHandler()
assert(fillRefreshes == 2 and lastFillReady.value == true)
assert(cooldownFrameCreates == 1 and timerAfterCalls == 0)

-- Once no indicator is active, event registration and the native driver are
-- cleared; a stale completion callback becomes a no-op.
targetFrame.MSUF_castActive = false
_G.MSUF_KickReady_RefreshFrame(targetFrame, nil)
assert(cooldownClearCalls >= 1)
readsBefore = cooldownReads
cooldownDoneHandler()
assert(cooldownReads == readsBefore)

-- Plain readiness is safe to share across the target/focus/boss burst in one
-- rendered frame. The next frame must resolve a fresh status while retaining
-- the existing one-Duration-per-frame contract.
local remainingReads = 0
cooldownObject.GetRemainingDuration = function()
    remainingReads = remainingReads + 1
    return 0
end
cooldownObject.IsZero = function() error("plain remaining should decide readiness") end
_G.GetTime = function() return frameStamp end
frameStamp = frameStamp + 1
assert(_G.MSUF_KickReady_GetReadyBoolForTint() == true)
assert(_G.MSUF_KickReady_GetReadyBoolForTint() == true)
assert(remainingReads == 1, "same-frame plain interrupt status was resolved more than once")
frameStamp = frameStamp + 1
assert(_G.MSUF_KickReady_GetReadyBoolForTint() == true)
assert(remainingReads == 2, "next-frame interrupt status reused a stale snapshot")

-- Budgets (Classic addition): Lua VM instructions and bytes per operation with
-- the collector stopped, frozen 2026-10-01 at the measured cost plus 2 %.
-- "print" as arg 2 reports the measured values instead of asserting.
local BUDGETS = {
    ["refresh active border frame"] = { 808, 8 },
    ["unrelated cooldown event"] = { 43, 8 },
    ["interrupt cooldown event"] = { 1061, 8 },
    ["same-frame readiness read"] = { 199, 8 },
}
-- Instructions over 200 operations; bytes over 2,000 more with the collector
-- stopped, after a warm-up, so one-off table growth amortizes away.
local WARMUP, INSTRUCTION_REPS, ALLOCATION_REPS = 50, 200, 2000
local function Measure(label, operation)
    for _ = 1, WARMUP do operation() end
    local ticks = 0
    debug.sethook(function() ticks = ticks + 1 end, "", 1)
    for _ = 1, INSTRUCTION_REPS do operation() end
    debug.sethook()
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, ALLOCATION_REPS do operation() end
    local bytes = (collectgarbage("count") - before) * 1024 / ALLOCATION_REPS
    collectgarbage("restart")
    local instructions = ticks / INSTRUCTION_REPS
    local budget = assert(BUDGETS[label], "no budget for " .. label)
    local line = string.format("%-30s %8.1f instructions %8.1f bytes  (budget %d / %d)",
        label, instructions, bytes, budget[1], budget[2])
    if arg[2] == "print" then
        print(line)
    else
        assert(instructions <= budget[1] and bytes <= budget[2], "interrupt-ready hot path over budget: " .. line)
    end
end

_G.MSUF_DB.general.kickReadyStyle = "border"
targetFrame.MSUF_castActive = true
targetFrame.UpdateColorForInterruptible = nil
-- Edges that record without allocating, so the bytes are the module's own.
local function QuietEdge()
    return { SetVertexColor = function(self, r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end }
end
targetFrame._msufOutline = { top = QuietEdge(), bottom = QuietEdge(), left = QuietEdge(), right = QuietEdge() }
local activeState = { active = true, apiNotInterruptibleRaw = false }
cooldownObject.GetRemainingDuration = function() return secretRemaining end
cooldownObject.IsZero = function() return secretReady end
Measure("refresh active border frame", function()
    frameStamp = frameStamp + 1
    _G.MSUF_KickReady_RefreshFrame(targetFrame, activeState)
end)
Measure("unrelated cooldown event", function()
    eventHandler(nil, "SPELL_UPDATE_COOLDOWN", 42, 42, nil, 1337)
end)
Measure("interrupt cooldown event", function()
    frameStamp = frameStamp + 1
    eventHandler(nil, "SPELL_UPDATE_COOLDOWN", 2139, 2139)
end)
Measure("same-frame readiness read", function()
    _G.MSUF_KickReady_GetReadyBoolForTint()
end)

print("interrupt ready perf smoke: ok")
