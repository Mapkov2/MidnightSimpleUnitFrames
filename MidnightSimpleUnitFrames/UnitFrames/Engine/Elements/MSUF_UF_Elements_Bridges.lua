local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

local UF = MSUF.UF
local type = type
local ExportPublic = MSUF.ExportPublic

-- UnitFrame element bridge helpers.
-- Queues cross-module refreshes from unitframe events into castbar/classpower/aura runtimes
-- without making those runtimes direct dependencies of every element file.
-- The castbar and class power owners load after the elements, so each one is
-- resolved when a spec applies or a queued refresh runs, after the core loaded.
local function Dep(name)
  return MSUF.Require(name, "UnitFrames/Engine/Elements/MSUF_UF_Elements_Bridges.lua")
end
local function CastbarUnit(unit)
  if type(unit) == "string" and unit:match("^boss%d+$") then
    return "boss"
  end
  if type(unit) == "string" and unit:match("^arena%d+$") then
    return "arena"
  end
  return unit
end

local function IsCastbarUnit(unit)
  unit = CastbarUnit(unit)
  return unit == "player" or unit == "target" or unit == "focus" or unit == "boss"
    or unit == "arena"
end

local function HideFrame(frame)
  if frame and frame.Hide then
    frame:Hide()
  end
end

local function Queue(fn, tokenName)
  if type(fn) ~= "function" then
    return
  end
  if UF[tokenName] then
    return
  end
  UF[tokenName] = true
  local function flush()
    UF[tokenName] = nil
    fn()
  end
  local scheduleOnce = _G.MSUF_ScheduleOnce
  if type(scheduleOnce) == "function" then
    scheduleOnce(tokenName, flush)
  elseif _G.C_Timer and _G.C_Timer.After then
    _G.C_Timer.After(0, flush)
  else
    flush()
  end
end

local function QueueCastbarRefresh(unit)
  unit = CastbarUnit(unit)
  Queue(function()
    -- Castbars/MSUF_Castbars_Core.lua is part of every core TOC, so the boss
    -- and arena preview refresh that stood in for a missing owner never ran.
    if unit then
      Dep("MSUF_ApplyCastbarUnitAndSync")(unit)
    else
      Dep("MSUF_UpdateCastbarVisuals")(unit)
    end
    if not unit or unit == "player" then
      Dep("MSUF_ApplyPlayerChannelTickMarkers")()
    end
  end, "_msufCastbarRefreshQueued_" .. tostring(unit or "all"))
end

local function HideMSUFCastbar(unit)
  unit = CastbarUnit(unit)
  if unit == "player" then
    HideFrame(_G.MSUF_PlayerCastBar)
    HideFrame(_G.MSUF_PlayerCastbar)
  elseif unit == "target" then
    HideFrame(_G.MSUF_TargetCastbar)
    HideFrame(_G.MSUF_TargetCastBar)
    HideFrame((_G.TargetCastBar and _G.TargetCastBar._msufCastbarDriver == true) and _G.TargetCastBar)
  elseif unit == "focus" then
    HideFrame(_G.MSUF_FocusCastbar)
    HideFrame(_G.MSUF_FocusCastBar)
    HideFrame((_G.FocusCastBar and _G.FocusCastBar._msufCastbarDriver == true) and _G.FocusCastBar)
  elseif unit == "boss" then
    for i = 1, 10 do
      HideFrame(_G["MSUF_boss" .. i .. "CastBar"])
      HideFrame(_G["MSUF_Boss" .. i .. "CastBar"])
    end
  elseif unit == "arena" then
    for i = 1, tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3 do
      HideFrame(_G["MSUF_arena" .. i .. "CastBar"])
      HideFrame(_G["MSUF_Arena" .. i .. "CastBar"])
    end
  end
end

local Castbars = {}

function Castbars.IsEnabled(frame, spec)
  return IsCastbarUnit(frame.MSUFUnitKey) and spec and spec.castbar and spec.castbar.enabled == true
end

function Castbars.Enable(frame)
  if not IsCastbarUnit(frame.MSUFUnitKey) then
    return
  end
  local unit = CastbarUnit(frame.MSUFUnitKey)
  if type(UF.ClaimBlizzardCastbarOwnership) == "function" then
    UF.ClaimBlizzardCastbarOwnership("MSUF", unit)
  end
  if unit == "player" then
    Dep("MSUF_SuppressBlizzardPlayerCastbars")()
  end
  QueueCastbarRefresh(unit)
end

function Castbars.Disable(frame)
  if not IsCastbarUnit(frame.MSUFUnitKey) then
    return
  end
  HideMSUFCastbar(frame.MSUFUnitKey)
  QueueCastbarRefresh(frame.MSUFUnitKey)
end

function Castbars.Apply(frame, spec)
  if not IsCastbarUnit(frame.MSUFUnitKey) then
    return
  end
  if spec and spec.castbar and spec.castbar.enabled == true then
    Castbars.Enable(frame, spec)
  else
    Castbars.Disable(frame)
  end
end

local ClassPower = {}

local function RefreshPlayerPowerBar()
  if UF and type(UF.RefreshPowerLayout) == "function" then
    return UF.RefreshPowerLayout("player")
  end
  return false
end

ExportPublic("MSUF_RefreshPlayerPowerBar", RefreshPlayerPowerBar)

function ClassPower.IsEnabled(frame, spec)
  return frame.MSUFUnitKey == "player" and spec and spec.classPower and spec.classPower.enabled == true
end

local function ApplyClassPowerCold(opts)
  Dep("MSUF_ClassPower_Apply")(opts)
  return true
end

function ClassPower.Enable(frame, full)
  if frame and frame.MSUFUnitKey ~= "player" then
    return
  end
  Queue(function()
    ApplyClassPowerCold(full and { full = true, cdm = true, syncNow = false } or { anchor = true, syncNow = false })
    Dep("MSUF_ApplyPowerBarEmbedLayout_ForUnitKey")("player")
  end, "_msufClassPowerRefreshQueued")
end

function ClassPower.Disable(frame)
  if frame and frame.MSUFUnitKey ~= "player" then
    return
  end
  HideFrame(_G.MSUF_ClassPowerContainer)
  if not Dep("MSUF_ClassPower_IsRuntimeActive")() then
    return
  end
  Queue(function()
    ApplyClassPowerCold({ full = true, cdm = true, syncNow = false })
  end, "_msufClassPowerRefreshQueued")
end

function ClassPower.Apply(frame, spec)
  if frame.MSUFUnitKey ~= "player" then
    return
  end
  local enabled = ClassPower.IsEnabled(frame, spec)
  local full = frame._msufClassPowerCoreEnabled ~= enabled
  frame._msufClassPowerCoreEnabled = enabled
  if enabled then
    ClassPower.Enable(frame, full)
  else
    if full then
      ClassPower.Disable(frame)
    end
  end
end

UF.RegisterElement("Castbars", Castbars)
UF.RegisterElement("ClassPower", ClassPower)

do
  local order = UF.elementOrder
  if type(order) == "table" then
    for i = 1, #order do
      if order[i] == "Alpha" then
        table.remove(order, i)
        order[#order + 1] = "Alpha"
        break
      end
    end
  end
end
