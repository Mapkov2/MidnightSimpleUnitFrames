--- UnitFrames/Engine/Group/MSUF_UF_Group_Adapter.lua
--- Adapter between secure group-header children and the generic unit-frame
--- engine.
---
--- Headers create protected child frames. This file discovers/tracks those
--- children, applies compiled specs, indexes frames by unit, wires click-cast
--- and tooltip behavior, and schedules bounded rescans when header children
--- appear late.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF

if not (UF and UF.AttachFrame and UF.ApplySpec) then return end

local C_Timer = C_Timer
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local table_remove = table.remove
local Secrets = MSUF.Secrets or {}
local UnitMissing = Secrets.UnitMissing or function(_) return false end
local issecretvalue = _G.issecretvalue or function(_) return false end

local IsUnitToken = UF.IsUnitToken or function(unit)
  return issecretvalue(unit) ~= true and type(unit) == "string" and unit ~= ""
end

GF.frames = GF.frames or setmetatable({}, { __mode = "k" })
GF.frameList = GF.frameList or {}
GF.unitFrames = GF.unitFrames or {}
GF._scanScheduled = GF._scanScheduled or {}
GF._scanScheduledKind = GF._scanScheduledKind or {}
GF._scanScheduledKey = GF._scanScheduledKey or {}
GF._scanScheduledDue = GF._scanScheduledDue or {}
GF._scanScheduledList = GF._scanScheduledList or {}
local scanScheduled = GF._scanScheduled
local scanScheduledKind = GF._scanScheduledKind
local scanScheduledKey = GF._scanScheduledKey
local scanScheduledDue = GF._scanScheduledDue
local scanScheduledList = GF._scanScheduledList
local scanScheduledHead = 1
local scanScheduledTail = 0
local scanTimerAt
local scanSeen = setmetatable({}, { __mode = "k" })
local scanNonce = setmetatable({}, { __mode = "k" })
local scanUnit = setmetatable({}, { __mode = "k" })
local scanKind = setmetatable({}, { __mode = "k" })
local attrUnit = setmetatable({}, { __mode = "k" })
local attrHooked = setmetatable({}, { __mode = "k" })
local childKind = setmetatable({}, { __mode = "k" })
local NO_UNIT = false
local appliedSerial = setmetatable({}, { __mode = "k" })
local appliedUnit = setmetatable({}, { __mode = "k" })
local appliedKind = setmetatable({}, { __mode = "k" })
local appliedPowerEnabled = setmetatable({}, { __mode = "k" })
local appliedPowerHeight = setmetatable({}, { __mode = "k" })
local appliedRoleValue = setmetatable({}, { __mode = "k" })
local UNIT_ATTR = "unit"
local UNIT_CHANGED_REASON = "MSUF_GF_UNIT_IDENTITY"

local APPLY_MASK = {
  Health = true, Power = true, Text = true, NameText = true,
  HealthText = true, PowerText = true, StatusIndicators = true,
  GroupStatusRuntime = true, Prediction = true,
  Alpha = true,
  Borders = true, GroupRangeFade = true, GroupVisuals = true,
  GroupCornerIndicators = true, Auras = true,
}
GF.GROUP_APPLY_MASK = APPLY_MASK

local UNIT_CHANGE_FAST_MASK = {
  GroupRangeFade = true,
  Prediction = true,
}

local ApplyUnitChangeFast

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

GF.ClickCastEnabled = true

--- Clique/ClickCastFrames integration is intentionally outside the generic UF
--- engine because only secure group buttons need this registration behavior.
local function RegisterDefaultClicks(frame)
  if frame and frame.RegisterForClicks then
    frame:RegisterForClicks("AnyUp")
  end
end

local function ClickCastAvailable()
  return type(rawget(_G, "Clique")) == "table" or type(rawget(_G, "ClickCastFrames")) == "table"
end

local function WantsClickCast(frame, spec)
  if GF.ClickCastEnabled == false then return false end
  local layout = spec and spec.groupLayout
  if layout and layout.clickCastEnabled == false then return false end
  if frame and (frame._msufGFIsPreviewFrame or frame._msufGFPreviewActive) then return false end
  return ClickCastAvailable()
end

local function ClickCastFrames(create)
  local frames = rawget(_G, "ClickCastFrames")
  if type(frames) ~= "table" and create == true then
    frames = {}
    _G.ClickCastFrames = frames
  end
  return type(frames) == "table" and frames or nil
end

local function Clique()
  local clique = rawget(_G, "Clique")
  return type(clique) == "table" and clique or nil
end

local function RefreshCliqueEnterLeave(clique, frame)
  if InCombat() or not (clique and frame) then return end
  if not (type(clique.ccframes) == "table" and clique.ccframes[frame]) then return end
  if type(clique.UnwrapOnEnterOnLeave) == "function"
    and type(clique.WrapOnEnterOnLeave) == "function"
  then
    clique:UnwrapOnEnterOnLeave(frame)
    clique:WrapOnEnterOnLeave(frame)
  elseif type(clique.ApplyAttributes) == "function" then
    clique:ApplyAttributes()
  end
end

function GF.RegisterClickCastFrame(frame, refreshEnterLeave)
  if not (frame and frame.RegisterForClicks) then return false end
  if frame._msufGFIsPreviewFrame or frame._msufGFPreviewActive then return false end
  if InCombat() then return frame._msufGFClickCastRegistered == true end

  frame:RegisterForClicks("AnyUp")
  local frames = ClickCastFrames(true)
  if frames then frames[frame] = true end
  frame._msufGFClickCastRegistered = true

  local clique = Clique()
  if not (clique and type(clique.ccframes) == "table") then return true end

  if type(clique.RegisterUnitFrame) == "function" then
    clique:RegisterUnitFrame(frame)
  end
  if refreshEnterLeave == true then
    RefreshCliqueEnterLeave(clique, frame)
  end
  return true
end

function GF.UnregisterClickCastFrame(frame)
  if not frame then return false end
  local frames = ClickCastFrames(false)
  if frames then frames[frame] = nil end
  frame._msufGFClickCastRegistered = nil

  local clique = Clique()
  if not clique or InCombat() then return true end

  if type(clique.UnregisterUnitFrame) == "function" then
    clique:UnregisterUnitFrame(frame)
  else
    if type(clique.UnwrapOnEnterOnLeave) == "function"
      and type(clique.ccframes) == "table"
      and clique.ccframes[frame]
    then
      clique:UnwrapOnEnterOnLeave(frame)
    end
    if type(clique.ccframes) == "table" then
      clique.ccframes[frame] = nil
    end
    if type(clique.ApplyAttributes) == "function" then
      clique:ApplyAttributes()
    end
  end
  return true
end

local function ApplyClickCast(frame, spec)
  if InCombat() then return false end
  if not WantsClickCast(frame, spec) then
    GF.UnregisterClickCastFrame(frame)
    RegisterDefaultClicks(frame)
    return false
  end
  return GF.RegisterClickCastFrame(frame, true)
end

local function RefreshClickCastFrame(frame)
  ApplyClickCast(frame, frame and frame.MSUFSpec)
end

function GF.RefreshClickCastFrames()
  if not GF.ForEachFrame then return false end
  GF.ForEachFrame(RefreshClickCastFrame, true)
  return true
end

local function TooltipAllowed()
  local tooltips = MSUF and MSUF.Tooltips
  if tooltips and type(tooltips.Allowed) == "function" then
    return tooltips.Allowed()
  end
  return true
end

local function TooltipScriptsNeeded()
  local general = _G.MSUF_DB and _G.MSUF_DB.general
  return not (general and general.unitTooltipMode == "NEVER")
end

local function HoverScriptsNeeded(spec)
  local group = spec and spec.group
  return group and group.hoverHighlightEnabled == true
end

local function MouseScriptsNeeded(spec)
  return HoverScriptsNeeded(spec) or TooltipScriptsNeeded()
end

local function ShowTooltip(frame)
  if not (frame and frame.unit) or UnitMissing(frame.unit) then
    return
  end
  if not TooltipAllowed() then
    return
  end
  local tooltips = MSUF and MSUF.Tooltips
  if tooltips and type(tooltips.ShowUnit) == "function" then
    tooltips.ShowUnit(frame, frame.unit)
    return
  end
  if UnitFrame_OnEnter then
    UnitFrame_OnEnter(frame)
  elseif GameTooltip then
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetUnit(frame.unit)
    GameTooltip:Show()
  end
end

local function SetHoverShown(frame, shown)
  local hl = MSUF and MSUF.Highlight
  if not hl then return end
  if shown then
    hl.Show(frame)
  else
    hl.Hide(frame)
  end
end

local function ShowHoverHighlight(frame)
  SetHoverShown(frame, true)
end

local tooltipPendingFrame
local tooltipPendingToken
local tooltipPendingAt
local tooltipTimerActive

local function GroupTooltipTimerCallback()
  tooltipTimerActive = nil
  local frame = tooltipPendingFrame
  local token = tooltipPendingToken
  if not frame then return end
  local now = GetTime and GetTime() or 0
  if tooltipPendingAt and now < tooltipPendingAt then
    tooltipTimerActive = true
    C_Timer.After(tooltipPendingAt - now, GroupTooltipTimerCallback)
    return
  end
  tooltipPendingFrame = nil
  tooltipPendingToken = nil
  tooltipPendingAt = nil
  if frame._msufGFTooltipToken ~= token then return end
  if frame.IsMouseOver and not frame:IsMouseOver() then return end
  ShowTooltip(frame)
end

local function GroupButtonOnEnter(self)
  local spec = self and self.MSUFSpec
  local hover = HoverScriptsNeeded(spec)
  if hover then
    ShowHoverHighlight(self)
  end
  if hover and _G.MSUF_RoundedUF_OnGroupMouseover then
    _G.MSUF_RoundedUF_OnGroupMouseover(self, true)
  end
  if not TooltipAllowed() then return end
  self._msufGFTooltipToken = (self._msufGFTooltipToken or 0) + 1
  local token = self._msufGFTooltipToken
  tooltipPendingFrame = self
  tooltipPendingToken = token
  tooltipPendingAt = (GetTime and GetTime() or 0) + 0.12
  if tooltipTimerActive ~= true then
    tooltipTimerActive = true
    C_Timer.After(0.12, GroupTooltipTimerCallback)
  end
end

local function GroupButtonOnLeave(self)
  local spec = self and self.MSUFSpec
  if HoverScriptsNeeded(spec) and _G.MSUF_RoundedUF_OnGroupMouseover then
    _G.MSUF_RoundedUF_OnGroupMouseover(self, false)
  end
  SetHoverShown(self, false)
  self._msufGFTooltipToken = (self._msufGFTooltipToken or 0) + 1
  if tooltipPendingFrame == self then
    tooltipPendingFrame = nil
    tooltipPendingToken = nil
    tooltipPendingAt = nil
  end
  local tooltips = MSUF and MSUF.Tooltips
  if tooltips and type(tooltips.HideUnit) == "function" then tooltips.HideUnit(self)
  elseif UnitFrame_OnLeave then UnitFrame_OnLeave(self)
  elseif GameTooltip then GameTooltip:Hide() end
end

local function HookButton(frame, spec)
  if not MouseScriptsNeeded(spec) then return end
  if frame._msufGFHooked then return end
  frame._msufGFHooked = true
  frame:HookScript("OnEnter", GroupButtonOnEnter)
  frame:HookScript("OnLeave", GroupButtonOnLeave)
end

local function NormalizeAttrUnit(value)
  if type(value) == "string" and value ~= "" then
    return value
  end
  return NO_UNIT
end

local function StoredAttrUnit(frame)
  local value = attrUnit[frame]
  if value == NO_UNIT then
    return nil
  end
  if value ~= nil then
    return value
  end
  return frame and frame.unit or nil
end

local function OnChildAttributeChanged(self, name, value)
  if name ~= UNIT_ATTR then return end
  local rawUnit = NormalizeAttrUnit(value)
  local oldUnit = StoredAttrUnit(self)
  local kind = childKind[self] or self._msufGFKind

  if attrUnit[self] == rawUnit then
    if rawUnit == NO_UNIT then
      if not oldUnit and not self.unit then
        return
      end
    elseif self.MSUFSpec and scanUnit[self] == rawUnit then
      if not kind or scanKind[self] == kind then
        return
      end
    end
  end

  if rawUnit == NO_UNIT then
    if not oldUnit and not self.unit then
      return
    end
    attrUnit[self] = rawUnit
    if GF.UntrackFrame then
      GF.UntrackFrame(self)
    end
    self.unit = nil
    self.unitKey = nil
    scanUnit[self] = nil
    return
  end

  if oldUnit == rawUnit and self.MSUFSpec and scanUnit[self] == rawUnit then
    if not kind or scanKind[self] == kind then
      return
    end
  end

  UF.OnUnitChanged(self, oldUnit, rawUnit)
  local applied = kind and ApplyUnitChangeFast(self, kind, rawUnit)
  if kind and not applied then
    applied = GF.ApplyButton(self, kind, "UNIT_CHANGED")
  end
  if applied then
    attrUnit[self] = rawUnit
    return
  end
end

local function InstallChildAttrHook(child, kind)
  if not (child and child.HookScript) then return end
  if kind then childKind[child] = kind end
  if attrHooked[child] then return end
  attrHooked[child] = true
  child:HookScript("OnAttributeChanged", OnChildAttributeChanged)
end

local function HeaderLayoutNonce(frame)
  local parent = frame and frame.GetParent and frame:GetParent()
  if parent and parent.GetAttribute then
    return parent:GetAttribute("_msufLayoutNonce") or 0
  end
  return 0
end

local function IndexFrameUnit(frame, unit)
  if not frame then return end
  local old = frame._msufGFIndexedUnit
  local unitOk = IsUnitToken(unit)
  local byUnit = GF.unitFrames
  if IsUnitToken(old) and (not unitOk or old ~= unit) and byUnit[old] == frame then
    byUnit[old] = nil
  end
  if unitOk then
    byUnit[unit] = frame
    frame._msufGFIndexedUnit = unit
  else
    frame._msufGFIndexedUnit = nil
  end
end

--- Track by both frame and unit. Unit indexes are refreshed when secure child
--- attributes change, so callers can find the current frame for a roster unit.
local function TrackFrame(frame, unit)
  if GF.frames[frame] ~= true then
    GF.frames[frame] = true
    GF.frameList[#GF.frameList + 1] = frame
  end
  IndexFrameUnit(frame, unit or frame.unit)
end

function GF.FrameForUnit(unit)
  if not IsUnitToken(unit) then
    return nil
  end
  local frame = unit and GF.unitFrames and GF.unitFrames[unit]
  local frameUnit = frame and frame.unit
  if frame and GF.frames[frame] == true
    and frameUnit == unit then
    return frame
  end
  return nil
end

local function MarkApplied(frame, kind, unit, spec)
  local power = spec and spec.power
  local status = spec and spec.status
  appliedSerial[frame] = spec and spec._msufGFCompileSerial or 0
  appliedUnit[frame] = unit
  appliedKind[frame] = kind
  appliedPowerEnabled[frame] = power and power.enabled or false
  appliedPowerHeight[frame] = power and power.height or 0
  appliedRoleValue[frame] = status and status.roleValue or false
end

local function HasSameApplyState(frame, kind, unit, spec)
  local power = spec and spec.power
  local status = spec and spec.status
  return frame
    and frame.MSUFSpec
    and appliedSerial[frame] == (spec and spec._msufGFCompileSerial or 0)
    and appliedUnit[frame] == unit
    and appliedKind[frame] == kind
    and appliedPowerEnabled[frame] == (power and power.enabled or false)
    and appliedPowerHeight[frame] == (power and power.height or 0)
    and appliedRoleValue[frame] == (status and status.roleValue or false)
end

ApplyUnitChangeFast = function(frame, kind, unit)
  if not (frame and kind and type(unit) == "string" and unit ~= "" and frame.MSUFSpec and GF.CompileSpec) then
    return false
  end

  childKind[frame] = kind
  frame._msufGFKind = kind
  frame._msufIsGroupFrame = true
  frame.unit = unit
  frame.unitKey = unit
  frame.configKey = "gf_" .. kind

  local spec = GF.CompileSpec(kind, frame, unit)
  UF.SetFrameSpec(frame, spec, unit)
  if UF.InstallPingCompatibility then
    UF.InstallPingCompatibility(frame)
  end
  UF.RefreshNativePingIcon(frame)

  local power = spec and spec.power
  local sameStructure = appliedSerial[frame] == (spec and spec._msufGFCompileSerial or 0)
    and appliedKind[frame] == kind
    and appliedPowerEnabled[frame] == (power and power.enabled or false)
    and appliedPowerHeight[frame] == (power and power.height or 0)

  if sameStructure and frame.ForceUpdate then
    frame:ForceUpdate(UNIT_CHANGED_REASON)
  elseif sameStructure then
    UF.ApplySpec(frame, spec, UNIT_CHANGED_REASON, UNIT_CHANGE_FAST_MASK)
  else
    UF.ApplySpec(frame, spec, UNIT_CHANGED_REASON, APPLY_MASK)
  end
  MarkApplied(frame, kind, unit, spec)
  attrUnit[frame] = unit

  local layoutNonce = HeaderLayoutNonce(frame)
  scanNonce[frame] = layoutNonce
  scanUnit[frame] = unit
  scanKind[frame] = kind
  TrackFrame(frame, unit)
  return true
end

function GF.UntrackFrame(frame)
  if not frame then return end
  if GF.UnregisterClickCastFrame then
    GF.UnregisterClickCastFrame(frame)
  end
  if UF and UF.DetachFrame then
    UF.DetachFrame(frame)
  end
  local ping = frame.pingIconFrame or frame.PingIconFrame
  if ping and not (IsForbidden and IsForbidden(ping)) then
    frame._msufNativePingGUID = nil
    if ping.Hide then
      ping:Hide()
    end
    if type(ping.SetGUIDMatch) == "function" then
      ping:SetGUIDMatch(nil)
    end
  end
  GF.frames[frame] = nil
  local indexedUnit = frame._msufGFIndexedUnit
  if indexedUnit and GF.unitFrames and GF.unitFrames[indexedUnit] == frame then
    GF.unitFrames[indexedUnit] = nil
  end
  frame._msufGFIndexedUnit = nil
  scanNonce[frame] = nil
  scanUnit[frame] = nil
  scanKind[frame] = nil
  attrUnit[frame] = nil
  childKind[frame] = nil
  appliedSerial[frame] = nil
  appliedUnit[frame] = nil
  appliedKind[frame] = nil
  appliedPowerEnabled[frame] = nil
  appliedPowerHeight[frame] = nil
  appliedRoleValue[frame] = nil
  local unit = frame.GetAttribute and frame:GetAttribute("unit") or frame.unit
  local uf = _G.MSUF_UnitFrames
  if type(unit) == "string" and uf and uf[unit] == frame then
    uf[unit] = nil
  end
  local list = GF.frameList
  if not list then return end
  for i = #list, 1, -1 do
    if list[i] == frame then
      table_remove(list, i)
    end
  end
end

--- Apply or reapply the compiled unit-frame spec to one secure child. This is
--- the adapter's main hot/warm path, so it skips identical unit/spec states.
function GF.ApplyButton(frame, kind, reason)
  if not frame then return false end
  local unit = frame.GetAttribute and frame:GetAttribute("unit") or frame.unit
  if type(unit) ~= "string" or unit == "" then return false end
  local layoutNonce = HeaderLayoutNonce(frame)

  if reason == "MSUF_GF_SCAN"
    and frame.MSUFSpec
    and scanNonce[frame] == layoutNonce
    and scanUnit[frame] == unit
    and scanKind[frame] == kind then
    return true
  end

  childKind[frame] = kind
  frame._msufGFKind = kind
  frame._msufIsGroupFrame = true
  frame.unit = unit
  frame.unitKey = unit
  frame.configKey = "gf_" .. kind

  local spec = GF.CompileSpec(kind, frame, unit)
  UF.SetFrameSpec(frame, spec, unit)
  if UF.InstallPingCompatibility then
    UF.InstallPingCompatibility(frame)
  end
  UF.RefreshNativePingIcon(frame)
  if HasSameApplyState(frame, kind, unit, spec) then
    attrUnit[frame] = unit
    scanNonce[frame] = layoutNonce
    scanUnit[frame] = unit
    scanKind[frame] = kind
    TrackFrame(frame, unit)
    return true
  end

  UF.AttachFrame(frame, { scope = "group", ownEvents = false })
  InstallChildAttrHook(frame, kind)
  HookButton(frame, spec)

  if not InCombat() then
    if frame.SetSize then
      frame:SetSize(spec.width, spec.height)
    end
    if frame.RegisterForClicks then
      RegisterDefaultClicks(frame)
    end
    if frame.SetAttribute then
      frame:SetAttribute("*type1", "target")
      frame:SetAttribute("*type2", "togglemenu")
    end
  end
  UF.ApplySpec(frame, spec, reason or "MSUF_GF_APPLY", APPLY_MASK)
  MarkApplied(frame, kind, unit, spec)
  attrUnit[frame] = unit
  ApplyClickCast(frame, spec)
  SetHoverShown(frame, false)
  scanNonce[frame] = layoutNonce
  scanUnit[frame] = unit
  scanKind[frame] = kind

  TrackFrame(frame, unit)
  return true
end

local function ScanOneChild(child, kind, token)
  if not (child and child.GetAttribute) then return false end
  if scanSeen[child] == token then return false end
  scanSeen[child] = token
  InstallChildAttrHook(child, kind)
  if not child:GetAttribute("unit") then
    if GF.frames and GF.frames[child] == true and GF.UntrackFrame then
      GF.UntrackFrame(child)
    end
    return false
  end
  GF.ApplyButton(child, kind, "MSUF_GF_SCAN")
  return true
end

local function ScanChildVarargs(kind, token, ...)
  local found = false
  local first
  for i = 1, select("#", ...) do
    local child = select(i, ...)
    if ScanOneChild(child, kind, token) then
      found = true
    end
    if not first and child and child.GetAttribute and child:GetAttribute("unit") then
      first = child
    end
  end
  return found, first
end

local function MeasureFirstCenterDelta(header, key, kind, firstChild)
  if not (header and firstChild and header.GetCenter and firstChild.GetCenter) then
    return
  end
  local fw = firstChild.GetWidth and firstChild:GetWidth() or 0
  local fh = firstChild.GetHeight and firstChild:GetHeight() or 0
  if not (fw and fh and fw >= 1 and fh >= 1) then return end
  local hx, hy = header:GetCenter()
  local cx, cy = firstChild:GetCenter()
  if not (hx and hy and cx and cy) then return end
  local hs = (header.GetEffectiveScale and header:GetEffectiveScale()) or 1
  local cs = (firstChild.GetEffectiveScale and firstChild:GetEffectiveScale()) or 1
  if hs == 0 then hs = 1 end
  if cs == 0 then cs = 1 end
  local x = (cx * cs - hx * hs) / hs
  local y = (cy * cs - hy * hs) / hs
  local store = GF._measuredFirstCenterDelta
  if not store then
    store = {}
    GF._measuredFirstCenterDelta = store
  end
  local prev = store[kind]
  if prev and math.abs((prev.x or 0) - x) < 0.5 and math.abs((prev.y or 0) - y) < 0.5 then
    return
  end
  store[kind] = { x = x, y = y }
  if GF.SetupHeader and not InCombat() and not GF._measuringFirstCenter then
    GF._measuringFirstCenter = true
    GF.SetupHeader(key, kind)
    GF._measuringFirstCenter = false
  end
end

--- Scan one secure header's children. Header creation and roster changes can
--- produce children over several frames, so ScheduleScan below retries briefly.
function GF.ScanHeader(key, kind)
  local header = GF.headers and GF.headers[key]
  if not header then return end
  GF._scanSeenToken = (GF._scanSeenToken or 0) + 1
  local token = GF._scanSeenToken
  if header.GetChildren then
    local found, first = ScanChildVarargs(kind, token, header:GetChildren())
    if first then
      MeasureFirstCenterDelta(header, key, kind, first)
    end
    return found
  end
  return false
end

local RunScheduledHeaderScans

local function ArmScanTimer(when)
  if scanTimerAt and scanTimerAt <= when then return end
  scanTimerAt = when
  local delay = when - (GetTime and GetTime() or 0)
  C_Timer.After(delay > 0 and delay or 0, RunScheduledHeaderScans)
end

RunScheduledHeaderScans = function()
  scanTimerAt = nil
  local now = GetTime and GetTime() or 0
  local nextAt
  local out = scanScheduledHead
  local last = scanScheduledTail

  for i = scanScheduledHead, last do
    local scheduleKey = scanScheduledList[i]
    local due = scheduleKey and scanScheduledDue[scheduleKey]
    if not due then
      scanScheduledList[i] = nil
    elseif now >= due then
      scanScheduled[scheduleKey] = nil
      scanScheduledDue[scheduleKey] = nil
      local key = scanScheduledKey[scheduleKey]
      local kind = scanScheduledKind[scheduleKey]
      scanScheduledKey[scheduleKey] = nil
      scanScheduledKind[scheduleKey] = nil
      scanScheduledList[i] = nil
      GF.ScanHeader(key, kind)
    else
      if out ~= i then
        scanScheduledList[out] = scheduleKey
        scanScheduledList[i] = nil
      end
      out = out + 1
      if not nextAt or due < nextAt then
        nextAt = due
      end
    end
  end

  local appendedTail = scanScheduledTail
  if appendedTail > last then
    for i = last + 1, appendedTail do
      local scheduleKey = scanScheduledList[i]
      local due = scheduleKey and scanScheduledDue[scheduleKey]
      if due then
        if out ~= i then
          scanScheduledList[out] = scheduleKey
          scanScheduledList[i] = nil
        end
        out = out + 1
        if not nextAt or due < nextAt then
          nextAt = due
        end
      else
        scanScheduledList[i] = nil
      end
    end
  end

  scanScheduledHead = 1
  scanScheduledTail = out - 1
  if scanScheduledTail <= 0 then
    scanScheduledTail = 0
  end
  if nextAt then
    ArmScanTimer(nextAt)
  end
end

local function ScheduleScanAfter(key, kind, delay)
  local scheduleKey = tostring(key) .. ":" .. tostring(delay)
  scanScheduledKind[scheduleKey] = kind
  scanScheduledKey[scheduleKey] = key
  if scanScheduled[scheduleKey] then return end
  scanScheduled[scheduleKey] = true
  local due = (GetTime and GetTime() or 0) + delay
  scanScheduledDue[scheduleKey] = due
  scanScheduledTail = scanScheduledTail + 1
  scanScheduledList[scanScheduledTail] = scheduleKey
  ArmScanTimer(due)
end

function GF.ScheduleScan(key, kind)
  GF.ScanHeader(key, kind)
  ScheduleScanAfter(key, kind, 0.05)
end

function GF.ForEachFrame(fn, includeHidden, a, b, c)
  if type(fn) ~= "function" then return end
  local any
  for i = 1, #GF.frameList do
    local frame = GF.frameList[i]
    if frame and GF.frames[frame] == true and (includeHidden == true or not frame.IsShown or frame:IsShown()) then
      if fn(frame, frame.unit, frame._msufGFKind, a, b, c) == true then
        any = true
      end
    end
  end
  return any
end
