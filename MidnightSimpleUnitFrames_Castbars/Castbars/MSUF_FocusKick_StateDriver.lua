-- MSUF_FocusKick_StateDriver.lua 
-- Drives the Focus Interrupt Tracker icon using the Castbar Engine state.
--
-- Goals:
--   * Coalesced updates (events -> update next tick)
--   * Single source of truth: MSUF_BuildCastState("focus")
--   * Keep the FocusKick UI module lightweight (no duplicate spellcast logic)

local _G = _G

-- Tell the UI module to avoid its legacy event/watch logic.
_G.MSUF_FocusKickUseEngineDriver = true

local CreateFrame = CreateFrame
local C_Timer_After = (_G.C_Timer and _G.C_Timer.After) or nil

local function IsEnabled()
  local db = _G.MSUF_DB
  if not db or not db.general then return false end

  -- Kill switch: if Focus unitframe is disabled, treat FocusKick as disabled.
  if db.focus and db.focus.enabled == false then
    return false
  end

  return db.general.enableFocusKickIcon == true
end

local function SetFocusCastbarHidden(hidden)
  -- Focus castbar name in MSUF is typically FocusCastBar.
  local bar = _G.FocusCastBar or _G.MSUF_FocusCastBar or _G["MSUF_FocusCastBar"]
  if bar and bar.SetAlpha then
    bar:SetAlpha(hidden and 0 or 1)
  end
end

local function EnsureUI()
  if _G.__MSUF_FocusKickUIInit then return end
  if type(_G.MSUF_InitFocusKickIcon) ~= "function" then return end
  _G.__MSUF_FocusKickUIInit = true
  pcall(_G.MSUF_InitFocusKickIcon)
end

local pending = false

local function UpdateNow()
  if IsEnabled() then
    EnsureUI()
  end

  if not IsEnabled() then
    SetFocusCastbarHidden(false)

    if type(_G.MSUF_FocusKick_ApplyCastState) == "function" then
      _G.MSUF_FocusKick_ApplyCastState(nil)
    else
      local fr = _G.MSUF_FocusKickIcon
      if fr and fr.Hide then fr:Hide() end
    end
    return
  end

  -- Enabled
  SetFocusCastbarHidden(true)

  local state
  if type(_G.MSUF_BuildCastState) == "function" then
    local ok, s = pcall(_G.MSUF_BuildCastState, "focus")
    if ok then state = s end
  end

  if type(_G.MSUF_FocusKick_ApplyCastState) == "function" then
    _G.MSUF_FocusKick_ApplyCastState(state)
  end
end

-- PERF: Pre-build the timer callback once (avoids closure allocation per event).
local function _FocusKickTimerCB()
  pending = false
  UpdateNow()
end

local function ScheduleUpdate()
  if pending then return end
  pending = true

  if C_Timer_After then
    C_Timer_After(0, _FocusKickTimerCB)
  else
    pending = false
    UpdateNow()
  end
end

-- Driver frame
local f = CreateFrame("Frame")

-- System events
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_FOCUS_CHANGED")

-- Focus spellcast triggers (schedule-only)
f:RegisterUnitEvent("UNIT_SPELLCAST_START", "focus")
f:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "focus")
f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "focus")
f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "focus")
f:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "focus")

f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "focus")
f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "focus")
f:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "focus")

f:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "focus")
f:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "focus")
-- Some clients use EMPOWER_UPDATE; if not present, RegisterUnitEvent will ignore silently.
f:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "focus")

f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "focus")
f:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "focus")

f:SetScript("OnEvent", function(self, event, unit)
  -- Optional: show interrupt feedback even though the focus castbar is hidden.
  if event == "UNIT_SPELLCAST_INTERRUPTED" and unit == "focus" then
    if IsEnabled() and type(_G.MSUF_FocusKick_PlayInterruptFeedback) == "function" then
      pcall(_G.MSUF_FocusKick_PlayInterruptFeedback)
    end
  end
  ScheduleUpdate()
end)

-- Public helper for debugging / manual resync
_G.MSUF_FocusKickDriver_ForceUpdate = ScheduleUpdate

-- Initial sync a moment later (ensures DB + frames exist)
if C_Timer_After then
  C_Timer_After(0.2, ScheduleUpdate)
else
  ScheduleUpdate()
end
