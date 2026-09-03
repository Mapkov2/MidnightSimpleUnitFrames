local repo = assert(arg[1], "repo root required")

-- Retail 12.1.0 has none of the new TimedSignalMap surface. The shared
-- scheduler must retain keyed replacement and cancellation semantics through
-- its allocation-bearing C_Timer.After compatibility path.
TimerUtil = nil
local timers = {}
C_Timer = {
    After = function(delay, callback)
        timers[#timers + 1] = { delay = delay, callback = callback }
    end,
}

local schedulerFrame = {}
function schedulerFrame:SetScript(script, callback)
    assert(script == "OnUpdate")
    self.onUpdate = callback
end
function CreateFrame()
    return schedulerFrame
end

local namespace = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua"))(
    "MidnightSimpleUnitFrames", namespace)

local scheduler = assert(namespace.Scheduler)
local fired = {}
assert(scheduler.ScheduleAfter("castbar", 0.4, function() fired[#fired + 1] = "stale" end))
assert(scheduler.ScheduleAfter("castbar", 0.1, function() fired[#fired + 1] = "latest" end))
assert(#timers == 2, "12.1.0 scheduler did not use C_Timer.After")
timers[1].callback()
assert(#fired == 0, "replaced 12.1.0 callback was not retired")
timers[2].callback()
assert(#fired == 1 and fired[1] == "latest", "latest 12.1.0 callback did not fire")
assert(scheduler.IsScheduled("castbar") == false, "fired 12.1.0 key stayed pending")

assert(scheduler.ScheduleAfter("cancel", 0.2, function() fired[#fired + 1] = "cancelled" end))
assert(scheduler.CancelScheduled("cancel") == true, "12.1.0 key was not cancelled")
timers[#timers].callback()
assert(#fired == 1, "cancelled 12.1.0 callback still fired")

-- The aura-caster CVar does not exist in 12.1.0. Both login restore and an
-- explicit setting application must fail closed without writing an unknown
-- CVar or preventing the pre-existing spell-ID option from working.
local cvarWrites = {}
local availableCVars = { tooltipShowAuraSpellIDs = "0" }
C_CVar = {
    GetCVar = function(name) return availableCVars[name] end,
    SetCVar = function(name, value)
        cvarWrites[#cvarWrites + 1] = { name = name, value = value }
    end,
}
MSUF_DB = {
    general = {
        tooltipShowAuraSpellIDs = true,
        tooltipShowAuraCasterNames = true,
    },
}
local loginFrame = {}
function loginFrame:RegisterEvent(event) self.event = event end
function loginFrame:UnregisterEvent(event) assert(event == self.event) end
function loginFrame:SetScript(script, callback)
    assert(script == "OnEvent")
    self.onEvent = callback
end
CreateFrame = function() return loginFrame end
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Runtime/MSUF_TooltipSpellIDs.lua"))(
    "MidnightSimpleUnitFrames", namespace)
loginFrame.onEvent(loginFrame)
assert(#cvarWrites == 1, "12.1.0 login wrote the unavailable caster-name CVar")
assert(cvarWrites[1].name == "tooltipShowAuraSpellIDs" and cvarWrites[1].value == "1")
assert(MSUF_ApplyTooltipCasterNames(true) == false,
    "12.1.0 accepted the unavailable caster-name CVar")
assert(#cvarWrites == 1, "12.1.0 caster-name fallback wrote an unknown CVar")

local function Read(relative)
    local file = assert(io.open(repo .. "/" .. relative, "rb"))
    local text = file:read("*a") or ""
    file:close()
    return text
end

-- Pin the feature-detection boundaries for the 12.1.5-only methods. Retail
-- 12.1.0 simply skips these branches and keeps MSUF's established owners.
local auras = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua")
for _, guard in ipairs({
    'type(container.SetEditModePreviewEnabled) == "function"',
    'type(button.AddPandemicRegion) == "function"',
}) do
    assert(auras:find(guard, 1, true), "missing 12.1.0 aura fallback guard: " .. guard)
end
local effects = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua")
assert(effects:find('type(button.AddPandemicActiveAnimation) == "function"', 1, true),
    "missing 12.1.0 Pandemic animation fallback guard")
local util = Read("MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua")
assert(util:find('type(frame.SetRoundLayoutToNearestPixel) == "function"', 1, true),
    "missing 12.1.0 pixel-rounding fallback guard")

print("Retail 12.1.0 fallback smoke passed")
