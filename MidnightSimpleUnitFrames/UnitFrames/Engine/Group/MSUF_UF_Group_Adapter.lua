local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF

if not (UF and UF.AttachFrame and UF.ApplySpec) then return end

local type = type
local table_remove = table.remove
local InCombatLockdown = InCombatLockdown
local issecretvalue = _G.issecretvalue or function(_) return false end

GF.frames = GF.frames or setmetatable({}, { __mode = "k" })
GF.frameList = GF.frameList or {}
GF.unitFrames = GF.unitFrames or {}

local attrUnit = setmetatable({}, { __mode = "k" })
local attrHooked = setmetatable({}, { __mode = "k" })
local childKind = setmetatable({}, { __mode = "k" })
local appliedSerial = setmetatable({}, { __mode = "k" })
local appliedUnit = setmetatable({}, { __mode = "k" })
local appliedKind = setmetatable({}, { __mode = "k" })
local appliedWidth = setmetatable({}, { __mode = "k" })
local appliedHeight = setmetatable({}, { __mode = "k" })
local secureClicksConfigured = setmetatable({}, { __mode = "k" })

local UNIT_ATTR = "unit"
local NO_UNIT = false
local UNIT_CHANGED_REASON = "MSUF_GF_UNIT_IDENTITY"
local UNIT_STRUCTURE_REASON = "MSUF_GF_UNIT_STRUCTURE"

local BASIC_GROUP_MASK = {
  LoadConditions = true,
  Health = true,
  Power = true,
  Text = true,
  NameText = true,
  HealthText = true,
  PowerText = true,
  InlineToT = true,
  StatusIndicators = true,
  Prediction = true,
  Alpha = true,
  Borders = true,
  Auras = true,
  GroupStatusRuntime = true,
  GroupRangeFade = true,
  GroupVisuals = true,
  GroupCornerIndicators = true,
}
GF.GROUP_APPLY_MASK = BASIC_GROUP_MASK

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local function IsUnitToken(unit)
  return issecretvalue(unit) ~= true and type(unit) == "string" and unit ~= ""
end

local function ShellFrame(frame)
  return frame and (frame._msufSecureShell or frame) or frame
end

local function VisualFrame(frame)
  return frame and (frame._msufVisualFrame or frame) or frame
end

local function EnsureGroupVisual(shell)
  if not shell then return nil end
  local visual = shell
  visual._msufSecureShell = nil
  visual._msufIsGroupFrame = true
  shell._msufVisualFrame = visual
  shell._msufIsGroupFrameShell = true
  return visual
end

local function RegisterDefaultClicks(frame)
  if InCombat() then return end
  if frame and frame.RegisterForClicks and frame._msufGFClicksRegistered ~= true then
    frame:RegisterForClicks("AnyUp")
    frame._msufGFClicksRegistered = true
  end
end

function GF.RegisterClickCastFrame(frame)
  RegisterDefaultClicks(frame)
  if not frame then return false end
  _G.ClickCastFrames = type(_G.ClickCastFrames) == "table" and _G.ClickCastFrames or {}
  _G.ClickCastFrames[frame] = true
  frame._msufGFClickCastRegistered = true
  frame._msufClickCastDisabledForClickSpikeTest = nil
  return true
end

function GF.UnregisterClickCastFrame(frame)
  if not frame then return false end
  local frames = rawget(_G, "ClickCastFrames")
  if type(frames) == "table" then frames[frame] = nil end
  frame._msufGFClickCastRegistered = nil
  return true
end

function GF.RefreshClickCastFrames()
  return false
end

local function NormalizeAttrUnit(value)
  if type(value) == "string" and value ~= "" then return value end
  return NO_UNIT
end

local function StoredAttrUnit(frame)
  local value = attrUnit[frame]
  if value == NO_UNIT then return nil end
  if value ~= nil then return value end
  return frame and frame.unit or nil
end

local function IndexFrameUnit(frame, unit)
  if not frame then return end
  local old = frame._msufGFIndexedUnit
  if IsUnitToken(old) and (not IsUnitToken(unit) or old ~= unit) and GF.unitFrames[old] == frame then
    GF.unitFrames[old] = nil
  end
  if IsUnitToken(unit) then
    GF.unitFrames[unit] = frame
    frame._msufGFIndexedUnit = unit
  else
    frame._msufGFIndexedUnit = nil
  end
end

local function UnindexFrameUnit(frame)
  if not frame then return end
  local indexed = frame._msufGFIndexedUnit
  if IsUnitToken(indexed) and GF.unitFrames[indexed] == frame then
    GF.unitFrames[indexed] = nil
  end
  frame._msufGFIndexedUnit = nil
end

local function TrackFrame(frame, unit)
  if not frame then return end
  if GF.frames[frame] ~= true then
    GF.frames[frame] = true
    GF.frameList[#GF.frameList + 1] = frame
  end
  IndexFrameUnit(frame, unit or frame.unit)
end
GF.TrackFrame = TrackFrame

function GF.FrameForUnit(unit)
  if not IsUnitToken(unit) then return nil end
  local frame = GF.unitFrames and GF.unitFrames[unit]
  if frame and frame.unit == unit then return frame end
  return nil
end

function GF.ValidateUnitFrameMap(frame, unit)
  local visual = VisualFrame(frame)
  return IsUnitToken(unit) and visual ~= nil and GF.unitFrames[unit] == visual and visual.unit == unit
end

local function MarkApplied(frame, kind, unit, spec)
  appliedSerial[frame] = spec and spec._msufGFCompileSerial or 0
  appliedUnit[frame] = unit
  appliedKind[frame] = kind
  appliedWidth[frame] = spec and spec.width or 0
  appliedHeight[frame] = spec and spec.height or 0
end

local function SameApplied(frame, kind, unit, spec)
  return frame
    and frame.MSUFSpec
    and appliedSerial[frame] == (spec and spec._msufGFCompileSerial or 0)
    and appliedUnit[frame] == unit
    and appliedKind[frame] == kind
    and appliedWidth[frame] == (spec and spec.width or 0)
    and appliedHeight[frame] == (spec and spec.height or 0)
end

function GF.RebindGroupHotRuntime(frame)
  if UF and UF.OptimizeFrameHotpaths then UF.OptimizeFrameHotpaths(frame) end
  return nil
end

function GF.ApplyStructureSpec(frame, spec, reason, mask)
  UF.ApplySpec(frame, spec, reason or UNIT_STRUCTURE_REASON, mask or BASIC_GROUP_MASK)
  GF.RebindGroupHotRuntime(frame, spec)
  return true
end

local function ConfigureSecureClicks(frame)
  if not (frame and frame.SetAttribute) or InCombat() then return false end
  if secureClicksConfigured[frame] == true then return true end
  frame:SetAttribute("type1", nil)
  frame:SetAttribute("*type1", "target")
  if UF and type(UF.AttachSecureUnitMenu) == "function" then
    UF.AttachSecureUnitMenu(frame)
  else
    frame:SetAttribute("type2", nil)
    frame:SetAttribute("*type2", "togglemenu")
    frame:SetAttribute("*clickbutton2", nil)
  end
  if UF and type(UF.ConfigurePingableUnitFrame) == "function" then
    UF.ConfigurePingableUnitFrame(frame)
  else
    frame:SetAttribute("ping-receiver", true)
  end
  secureClicksConfigured[frame] = true
  return true
end

local function SetButtonBasics(shell, visual, unit, spec)
  shell._msufIsGroupFrameShell = true
  shell.unit = unit
  shell.unitKey = unit
  shell.MSUFUnitKey = unit
  visual._msufIsGroupFrame = true
  visual.unit = unit
  visual.unitKey = unit
  visual.MSUFUnitKey = unit
  ConfigureSecureClicks(shell)
  GF.RegisterClickCastFrame(shell)
  if shell.SetSize and not InCombat() then
    local w = spec and spec.width
    local h = spec and spec.height
    if w and h and (shell._msufGFWidth ~= w or shell._msufGFHeight ~= h) then
      shell:SetSize(w, h)
      shell._msufGFWidth = w
      shell._msufGFHeight = h
    end
    if w and h and visual.SetSize then
      visual:SetSize(w, h)
    end
  end
  RegisterDefaultClicks(shell)
end

function GF.UntrackFrame(frame)
  if not frame then return end
  local shell = ShellFrame(frame)
  local visual = VisualFrame(shell)
  GF.UnregisterClickCastFrame(shell)
  if UF and UF.DetachFrame then UF.DetachFrame(visual) end
  if UF and UF.DisablePingCompatibility then UF.DisablePingCompatibility(shell) end
  GF.frames[visual] = nil
  local indexed = visual._msufGFIndexedUnit
  if indexed and GF.unitFrames[indexed] == visual then GF.unitFrames[indexed] = nil end
  visual._msufGFIndexedUnit = nil
  attrUnit[shell] = nil
  childKind[shell] = nil
  appliedSerial[visual] = nil
  appliedUnit[visual] = nil
  appliedKind[visual] = nil
  appliedWidth[visual] = nil
  appliedHeight[visual] = nil
  secureClicksConfigured[shell] = nil
  for i = #GF.frameList, 1, -1 do
    if GF.frameList[i] == visual then table_remove(GF.frameList, i) end
  end
end

local function SuspendUnitBinding(frame)
  if not frame then return end
  local shell = ShellFrame(frame)
  local visual = VisualFrame(shell)
  UnindexFrameUnit(visual)
  attrUnit[shell] = NO_UNIT
  if visual then
    visual.unit = nil
    visual.unitKey = nil
  end
end

local function ApplyUnitFrame(frame, kind, unit, reason)
  if not (frame and kind and IsUnitToken(unit) and GF.CompileSpec) then return false end
  local shell = ShellFrame(frame)
  local visual = EnsureGroupVisual(shell)
  if not visual then return false end
  childKind[shell] = kind
  shell._msufGFKind = kind
  visual._msufGFKind = kind
  visual.configKey = "gf_" .. kind

  local spec = GF.CompileSpec(kind, visual, unit)
  if not spec then return false end
  UF.SetFrameSpec(visual, spec, unit)
  SetButtonBasics(shell, visual, unit, spec)

  if SameApplied(visual, kind, unit, spec) then
    attrUnit[shell] = unit
    TrackFrame(visual, unit)
    if reason == "UNIT_CHANGED" or reason == UNIT_CHANGED_REASON then
      if UF.RunLeanIdentity then UF.RunLeanIdentity(visual, UNIT_CHANGED_REASON) end
    end
    return true
  end

  UF.AttachFrame(visual, { scope = "group" })
  GF.ApplyStructureSpec(visual, spec, reason == "UNIT_CHANGED" and UNIT_CHANGED_REASON or (reason or UNIT_STRUCTURE_REASON), BASIC_GROUP_MASK)
  MarkApplied(visual, kind, unit, spec)
  attrUnit[shell] = unit
  TrackFrame(visual, unit)
  return true
end

function GF.ApplyButton(frame, kind, reason)
  if not frame then return false end
  local unit = frame.GetAttribute and frame:GetAttribute("unit") or frame.unit
  if not IsUnitToken(unit) then
    SuspendUnitBinding(frame)
    return false
  end
  return ApplyUnitFrame(frame, kind or frame._msufGFKind or "party", unit, reason)
end

local function OnChildAttributeChanged(self, name, value)
  if name ~= UNIT_ATTR then return end
  local visual = EnsureGroupVisual(self)
  local rawUnit = NormalizeAttrUnit(value)
  local oldUnit = StoredAttrUnit(self)
  local kind = childKind[self] or self._msufGFKind

  if rawUnit == NO_UNIT then
    SuspendUnitBinding(self)
    return
  end

  if oldUnit == rawUnit and visual and visual.MSUFSpec and appliedUnit[visual] == rawUnit then
    return
  end

  if not (visual and visual.MSUFSpec) then
    ApplyUnitFrame(self, kind or "party", rawUnit, "UNIT_CHANGED")
    return
  end

  if visual.unit == rawUnit then
    visual.MSUFSpec.unit = rawUnit
    visual.MSUFUnitKey = rawUnit
    visual.unitKey = rawUnit
    self.unit = rawUnit
    self.MSUFUnitKey = rawUnit
    self.unitKey = rawUnit
    attrUnit[self] = rawUnit
    appliedUnit[visual] = rawUnit
    if kind then appliedKind[visual] = kind end
    TrackFrame(visual, rawUnit)
    if UF.RunLeanIdentity then UF.RunLeanIdentity(visual, UNIT_CHANGED_REASON) end
    return
  end

  visual.MSUFSpec.unit = rawUnit
  if UF.OnUnitChanged then
    UF.OnUnitChanged(visual, oldUnit, rawUnit)
  else
    visual.unit = rawUnit
    visual.unitKey = rawUnit
  end
  self.unit = rawUnit
  self.unitKey = rawUnit
  self.MSUFUnitKey = rawUnit
  visual.MSUFUnitKey = rawUnit
  attrUnit[self] = rawUnit
  appliedUnit[visual] = rawUnit
  if kind then appliedKind[visual] = kind end
  TrackFrame(visual, rawUnit)
end

local function InstallChildAttrHook(child, kind)
  if not (child and child.HookScript) then return end
  if kind then childKind[child] = kind end
  if attrHooked[child] then return end
  attrHooked[child] = true
  child:HookScript("OnAttributeChanged", OnChildAttributeChanged)
end

local function ScanOneChild(child, kind)
  if not (child and child.GetAttribute) then return false end
  InstallChildAttrHook(child, kind)
  local unit = child:GetAttribute("unit")
  if not IsUnitToken(unit) then
    SuspendUnitBinding(child)
    return false
  end
  return GF.ApplyButton(child, kind, "MSUF_GF_SCAN")
end

function GF.ScanHeader(key, kind)
  local header = GF.headers and GF.headers[key]
  if not (header and header.GetChildren) then return false end
  local found = false
  if UF.BeginEventRegistrationBatch then UF.BeginEventRegistrationBatch() end
  for i = 1, select("#", header:GetChildren()) do
    found = ScanOneChild(select(i, header:GetChildren()), kind) or found
  end
  if UF.EndEventRegistrationBatch then UF.EndEventRegistrationBatch() end
  return found
end

function GF.ScheduleScan(key, kind)
  return GF.ScanHeader(key, kind)
end

function GF.ForEachFrame(fn, includeHidden, a, b, c)
  if type(fn) ~= "function" then return false end
  local any = false
  for i = 1, #GF.frameList do
    local frame = GF.frameList[i]
    if frame and GF.frames[frame] == true and (includeHidden == true or not frame.IsShown or frame:IsShown()) then
      if fn(frame, frame.unit, frame._msufGFKind, a, b, c) == true then any = true end
    end
  end
  return any
end
