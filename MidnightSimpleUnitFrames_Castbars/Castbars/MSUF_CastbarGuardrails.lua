-- MSUF Castbar Guardrails (Step 15 - Weg A)
-- Purpose:
--   1) Warn when MSUF castbars call StatusBar:SetTimerDuration / SetReverseFill directly
--      (outside the shared helper) to prevent "direction drift" regressions.
--   2) Keep behavior unchanged; this is a guard + dev hint, not a logic rewrite.
--
-- Load AFTER CastbarStyle (so MSUF_ApplyCastbarTimerDirection exists)

local _G = _G

-- Lightweight toggle (optional): MSUF_DB.general.castbarGuardrails = false
local function GuardrailsEnabled()
  local db = _G.MSUF_DB
  if not db or not db.general then return true end
  return db.general.castbarGuardrails ~= false
end

local function SafeName(obj)
  if type(obj) ~= "table" then return tostring(obj) end
  if obj.GetName then
    local ok, name = pcall(obj.GetName, obj)
    if ok and name then return name end
  end
  return tostring(obj)
end

local function WarnOnce(statusBar, msg)
  if not GuardrailsEnabled() then return end
  if type(statusBar) ~= "table" then return end
  statusBar.__msufWarned = statusBar.__msufWarned or {}
  if statusBar.__msufWarned[msg] then return end
  statusBar.__msufWarned[msg] = true
  print("|cffff5555MSUF Castbar Guardrails:|r " .. msg)

  -- Record offenders (one stack per unique message).
  _G.__MSUF_CastbarGuardrails_Hits = _G.__MSUF_CastbarGuardrails_Hits or {}
  local hit = _G.__MSUF_CastbarGuardrails_Hits[msg]
  if not hit then
    local stack = ""
    if type(debugstack) == "function" then
      stack = debugstack(3, 20, 20)
    end
    _G.__MSUF_CastbarGuardrails_Hits[msg] = { count = 1, stack = stack }
  else
    hit.count = (hit.count or 0) + 1
  end
end

function _G.MSUF_PrintCastbarGuardrailHits()
  local t = _G.__MSUF_CastbarGuardrails_Hits
  if not t then
    print("MSUF Castbar Guardrails: no hits recorded.")
    return
  end
  print("|cffff5555MSUF Castbar Guardrails hits:|r")
  for msg, info in pairs(t) do
    print("- " .. msg .. " (" .. tostring(info and info.count or 0) .. ")")
    if info and info.stack and info.stack ~= "" then
      print(info.stack)
    end
  end
end

-- Track wrapped functions safely (functions can't be indexed like tables).
local function GetWrapTable()
  _G.__MSUF_CastbarGuardrails_Wrapped = _G.__MSUF_CastbarGuardrails_Wrapped or {}
  return _G.__MSUF_CastbarGuardrails_Wrapped
end

-- Install per-statusbar wrappers (only for MSUF castbars / previews).
function _G.MSUF_InstallTimerDurationGuard(statusBar, label)
  if not GuardrailsEnabled() then return end
  if not statusBar or type(statusBar) ~= "table" then return end
  if statusBar.__msufGuardInstalled then return end
  if not statusBar.SetTimerDuration and not statusBar.SetReverseFill then return end

  statusBar.__msufGuardInstalled = true
  statusBar.__msufGuardLabel = label or SafeName(statusBar)

  -- Wrap SetTimerDuration
  if statusBar.SetTimerDuration and not statusBar.__msufOrigSetTimerDuration then
    statusBar.__msufOrigSetTimerDuration = statusBar.SetTimerDuration
    statusBar.SetTimerDuration = function(self, duration, interpolation, direction)
	      if (self.__msufAllowTimerDuration or 0) <= 0 then
        WarnOnce(self, ("Direct SetTimerDuration on %s (label=%s). Use MSUF_ApplyCastbarTimerDirection().")
          :format(SafeName(self), tostring(self.__msufGuardLabel)))
      end
      return self:__msufOrigSetTimerDuration(duration, interpolation, direction)
    end
  end

  -- Wrap SetReverseFill
  if statusBar.SetReverseFill and not statusBar.__msufOrigSetReverseFill then
    statusBar.__msufOrigSetReverseFill = statusBar.SetReverseFill
    statusBar.SetReverseFill = function(self, reverseFill)
	      if (self.__msufAllowReverseFill or 0) <= 0 then
        WarnOnce(self, ("Direct SetReverseFill on %s (label=%s). Use MSUF_ApplyCastbarTimerDirection().")
          :format(SafeName(self), tostring(self.__msufGuardLabel)))
      end
      return self:__msufOrigSetReverseFill(reverseFill)
    end
  end
end

-- Wrap the shared helper so it "authorizes" internal SetTimerDuration/SetReverseFill calls.
local function WrapApplyHelper()
  local wrapped = GetWrapTable()
  local old = _G.MSUF_ApplyCastbarTimerDirection
  if type(old) ~= "function" then return end
  if wrapped[old] then return end

  local function newApply(statusBar, durationObj, reverseFill)
    if statusBar and type(statusBar) == "table" then
	      statusBar.__msufAllowTimerDuration = (statusBar.__msufAllowTimerDuration or 0) + 1
	      statusBar.__msufAllowReverseFill = (statusBar.__msufAllowReverseFill or 0) + 1
    end

    local ok, a, b, c = pcall(old, statusBar, durationObj, reverseFill)

	    if statusBar and type(statusBar) == "table" then
	      statusBar.__msufAllowTimerDuration = (statusBar.__msufAllowTimerDuration or 1) - 1
	      statusBar.__msufAllowReverseFill = (statusBar.__msufAllowReverseFill or 1) - 1
    end

    if ok then return a, b, c end
    WarnOnce(statusBar or {}, "MSUF_ApplyCastbarTimerDirection() error: " .. tostring(a))
  end

  wrapped[old] = true
  wrapped[newApply] = true
  _G.MSUF_ApplyCastbarTimerDirection = newApply
end

-- Wrap global builders so guards are installed automatically on MSUF castbar statusbars.
local function WrapBuilders()
  local wrapped = GetWrapTable()

  local oldBuild = _G.MSUF_BuildCastbarFrameElements
  if type(oldBuild) == "function" and not wrapped[oldBuild] then
    local function newBuild(frame, ...)
      local r = oldBuild(frame, ...)
      if frame and frame.statusBar then
        _G.MSUF_InstallTimerDurationGuard(frame.statusBar, SafeName(frame))
      end
      return r
    end
    wrapped[oldBuild] = true
    wrapped[newBuild] = true
    _G.MSUF_BuildCastbarFrameElements = newBuild
  end

  local oldPreview = _G.MSUF_CreateCastbarPreviewFrame
  if type(oldPreview) == "function" and not wrapped[oldPreview] then
    local function newPreview(kind, frameName, opts, ...)
      local frame = oldPreview(kind, frameName, opts, ...)
      if frame and frame.statusBar then
        _G.MSUF_InstallTimerDurationGuard(frame.statusBar, tostring(frameName or kind or "preview"))
      end
      return frame
    end
    wrapped[oldPreview] = true
    wrapped[newPreview] = true
    _G.MSUF_CreateCastbarPreviewFrame = newPreview
  end
end

-- One-time scan to catch any already-built castbars (boss bars, older frames, etc.)
local function OneTimeScanGlobals()
  if not GuardrailsEnabled() then return end
  local scanned = 0
  for k, v in pairs(_G) do
    if type(k) == "string" and (k:find("MSUF") or k:find("Castbar") or k:find("CASTBAR")) then
      if type(v) == "table" and v.statusBar and (v.statusBar.SetTimerDuration or v.statusBar.SetReverseFill) then
        _G.MSUF_InstallTimerDurationGuard(v.statusBar, k)
      end
      scanned = scanned + 1
      if scanned > 2500 then break end
    end
  end
end

local function InitGuardrails()
  WrapApplyHelper()
  WrapBuilders()
  if _G.C_Timer and _G.C_Timer.After then
    _G.C_Timer.After(1.0, OneTimeScanGlobals)
    _G.C_Timer.After(5.0, OneTimeScanGlobals)
  else
    OneTimeScanGlobals()
  end
end

InitGuardrails()
