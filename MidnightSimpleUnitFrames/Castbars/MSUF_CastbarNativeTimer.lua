--- Castbars/MSUF_CastbarNativeTimer.lua - PTR 7 spike: C-side castbar timers.
---
--- 12.1 exposes C_DurationUtil duration objects that StatusBars and text
--- FontStrings bind to directly (StatusBar:SetTimerDuration +
--- CreateDurationTextBinding). Bound this way, fill AND time text advance
--- entirely C-side: no per-frame Lua OnUpdate tick for the cast.
---
--- Flag: MSUF_DB.general.castbarNativeTimer == true (default OFF - module is
--- fully dark and cost-free until enabled AND wired). Dev spike: enable only
--- for a measuring session; any API-shape mismatch surfaces as a loud error
--- at the exact call site - deliberately NO pcall anywhere (hard perf rule).
--- Call shapes mirror Blizzard's only known consumers 1:1
--- (Blizzard_AuraButton.lua UpdateAuraDuration / Blizzard_CustomAuraButton.lua
--- ApplyDurationBar).
---
--- Wiring contract for the cast runtime (one hook pair per bar):
---   at cast/channel START, after the bar min/max is configured:
---       if MSUF.CastbarNativeTimer.Attach(bar, timeFS, startMS, endMS, isChannel) then
---           -- native path owns fill + time text: do NOT install the Lua
---           -- OnUpdate fill/text tick for this cast.
---       end
---   at STOP / INTERRUPTED / FAILED / CHANNEL_STOP:
---       MSUF.CastbarNativeTimer.Detach(bar)
--- Empower stages and channel ticks keep their existing Lua drivers.
local _addonName, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

local NT = MSUF.CastbarNativeTimer or {}
MSUF.CastbarNativeTimer = NT

local function Enabled()
    local db = _G.MSUF_DB
    local general = db and db.general
    if not (general and general.castbarNativeTimer == true) then return false end
    local du = _G.C_DurationUtil
    return du ~= nil
        and type(du.CreateDuration) == "function"
        and type(du.CreateDurationTextBinding) == "function"
end

--- Returns true when the native path took over fill (and text when timeFS is
--- given) for this cast; false leaves the caller on the Lua tick.
function NT.Attach(bar, timeFS, startMS, endMS, isChannel)
    if not (bar and type(bar.SetTimerDuration) == "function" and Enabled()) then return false end
    local du = _G.C_DurationUtil
    local duration = bar._msufNTDuration
    if not duration then
        duration = du.CreateDuration()
        if not (duration and type(duration.SetTimeFromEnd) == "function"
            and type(duration.SetTimeSpan) == "function") then
            return false
        end
        bar._msufNTDuration = duration
    end
    -- Blizzard pattern: SetTimeFromEnd(expiration, duration[, timeMod]) in
    -- GetTime-based seconds (AuraButton passes aura expirationTime/duration).
    local endSec = (tonumber(endMS) or 0) / 1000
    local durSec = endSec - ((tonumber(startMS) or 0) / 1000)
    duration:SetTimeFromEnd(endSec, durSec)
    local enum = _G.Enum
    local interp = enum and enum.StatusBarInterpolation
    local direction = enum and enum.StatusBarTimerDirection
    bar:SetTimerDuration(duration,
        interp and interp.Immediate or nil,
        direction and (isChannel and direction.RemainingTime or direction.ElapsedTime) or nil)
    if timeFS then
        local binding = bar._msufNTBinding
        if not binding then
            binding = du.CreateDurationTextBinding()
            bar._msufNTBinding = binding
        end
        if binding and type(binding.SetFontString) == "function" then
            binding:SetFontString(timeFS)
            binding:SetDuration(duration)
            if type(binding.SetEnabled) == "function" then binding:SetEnabled(true) end
        end
    end
    bar._msufNTActive = true
    return true
end

function NT.Detach(bar)
    if not (bar and bar._msufNTActive) then return end
    bar._msufNTActive = nil
    local binding = bar._msufNTBinding
    if binding and type(binding.SetEnabled) == "function" then binding:SetEnabled(false) end
    local duration = bar._msufNTDuration
    if duration then duration:SetTimeSpan(0, 0) end
end
