local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF
local Highlight = MSUF.Highlight

if not (UF and UF.AttachFrame and UF.ApplySpec) then return end

local type = type
local table_remove = table.remove
local next = next
local InCombatLockdown = InCombatLockdown
local issecretvalue = _G.issecretvalue or function(_) return false end

GF.frames = GF.frames or setmetatable({}, { __mode = "k" })
GF.frameList = GF.frameList or {}
GF.unitFrames = GF.unitFrames or {}
-- Priority frames are additional views of an existing group unit. Keep their
-- index separate so the normal party/raid child remains the authoritative
-- O(1) result for FrameForUnit and every existing primary-frame consumer.
-- Buckets use weak frame keys and are removed eagerly when their last tracked
-- duplicate moves or retires. The outer registry itself stays lazy so an
-- account that never enables Priority Frames pays no allocation for it.

local attrUnit = setmetatable({}, { __mode = "k" })
local attrHooked = setmetatable({}, { __mode = "k" })
local childKind = setmetatable({}, { __mode = "k" })
local appliedSerial = setmetatable({}, { __mode = "k" })
local appliedUnit = setmetatable({}, { __mode = "k" })
local appliedKind = setmetatable({}, { __mode = "k" })
local appliedWidth = setmetatable({}, { __mode = "k" })
local appliedHeight = setmetatable({}, { __mode = "k" })
local appliedPowerEnabled = setmetatable({}, { __mode = "k" })
local secureClicksConfigured = setmetatable({}, { __mode = "k" })
local unitIndexRebindDepth = 0
local headerLayoutRebindHeader
local headerLayoutRebindDepth = 0

local UNIT_ATTR = "unit"
local NO_UNIT = false
local UNIT_CHANGED_REASON = "MSUF_GF_UNIT_IDENTITY"
local UNIT_STRUCTURE_REASON = "MSUF_GF_UNIT_STRUCTURE"

local BASIC_GROUP_MASK = {
  LoadConditions = true,
  Health = true,
  Power = true,
  Text = true,
  Portrait = true,
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

--- Mark the one secure header whose synchronous Show will be followed by an
--- MSUF child scan. Visibility hooks may keep their cheap bookkeeping, while
--- the scan becomes the single authoritative state/apply barrier.
function GF.BeginHeaderLayoutRebind(header)
  if not header then return false end
  if headerLayoutRebindHeader and headerLayoutRebindHeader ~= header then return false end
  headerLayoutRebindHeader = header
  headerLayoutRebindDepth = headerLayoutRebindDepth + 1
  return true
end

function GF.EndHeaderLayoutRebind(header)
  if not header or headerLayoutRebindHeader ~= header then return false end
  headerLayoutRebindDepth = headerLayoutRebindDepth - 1
  if headerLayoutRebindDepth <= 0 then
    headerLayoutRebindHeader = nil
    headerLayoutRebindDepth = 0
  end
  return true
end

function GF.IsHeaderLayoutRebindActive(frame)
  local header = headerLayoutRebindHeader
  if not (header and frame) then return false end
  local shell = ShellFrame(frame)
  return shell and shell.GetParent and shell:GetParent() == header or false
end

local function IsPreviewFrame(shell, visual)
  return (shell and shell._msufGFIsPreviewFrame == true)
    or (visual and visual._msufGFIsPreviewFrame == true)
end

local function IsPriorityFrame(frame)
  if not frame then return false end
  if frame._msufGFPriorityFrame == true then return true end
  local shell = ShellFrame(frame)
  if shell and shell._msufGFPriorityFrame == true then return true end
  local visual = VisualFrame(shell)
  return visual and visual._msufGFPriorityFrame == true or false
end
GF.IsPriorityFrame = IsPriorityFrame

local function EnsureGroupVisual(shell)
  if not shell then return nil end
  local visual = shell
  visual._msufSecureShell = nil
  visual._msufIsGroupFrame = true
  shell._msufVisualFrame = visual
  shell._msufIsGroupFrameShell = true
  return visual
end

-- Group-frame tooltip handlers, assigned in the do-block lower in this file
-- (they need StoredAttrUnit). The file loads fully before any group child is
-- created, so these upvalues are non-nil by the time EnsureMouseoverHooks runs.
local GroupShowTooltip, GroupHideTooltip

local function EnsureMouseoverHooks(frame)
  if not (frame and frame.HookScript) or frame._msufGFMouseoverHighlightHooked == true then return end
  if Highlight then
    frame:HookScript("OnEnter", Highlight.GroupEnter)
    frame:HookScript("OnLeave", Highlight.GroupLeave)
  end
  frame:HookScript("OnEnter", GroupShowTooltip)
  frame:HookScript("OnLeave", GroupHideTooltip)
  frame._msufGFMouseoverHighlightHooked = true
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
  return frame and frame.MSUFUnitKey or nil
end

-- Group-frame tooltip on hover (party/raid). A short hover-delay debounce means
-- sweeping the cursor across many raid frames never builds a tooltip for a
-- frame the mouse only passes over -- only the frame it settles on pays the
-- gt:SetUnit cost. All mode/anchor/dedupe and the NEVER fast-path live in
-- Tooltips.ShowUnit; the unit token comes from the adapter's own cached
-- attribute index (StoredAttrUnit), so there is no secure read per hover.
do
  local C_Timer, GetTime = C_Timer, GetTime
  local HOVER_DELAY = 0.12
  local pendingFrame, pendingToken, pendingAt, timerActive

  local function TooltipAllowed()
    local tooltips = MSUF.Tooltips
    return not tooltips or type(tooltips.Allowed) ~= "function" or tooltips.Allowed()
  end

  local function TimerCallback()
    timerActive = nil
    local frame, token = pendingFrame, pendingToken
    if not frame then return end
    local now = GetTime and GetTime() or 0
    if pendingAt and now < pendingAt then
      timerActive = true
      C_Timer.After(pendingAt - now, TimerCallback)
      return
    end
    pendingFrame, pendingToken, pendingAt = nil, nil, nil
    if frame._msufGFTooltipToken ~= token then return end
    if frame.IsMouseOver and not frame:IsMouseOver() then return end
    local tooltips = MSUF.Tooltips
    if tooltips and not tooltips.hoverInert and tooltips.ShowUnit then
      tooltips.ShowUnit(frame, StoredAttrUnit(frame))
    end
  end

  GroupShowTooltip = function(self)
    -- Combat fast-path: hoverInert is true when a tooltip cannot show right now
    -- (NEVER, or OOC in combat), so an in-combat hover in those modes costs one
    -- field read and returns before TooltipAllowed / scheduling any timer.
    local tooltips = MSUF.Tooltips
    if not tooltips or tooltips.hoverInert then return end
    if not TooltipAllowed() then return end
    local token = (self._msufGFTooltipToken or 0) + 1
    self._msufGFTooltipToken = token
    pendingFrame, pendingToken = self, token
    pendingAt = (GetTime and GetTime() or 0) + HOVER_DELAY
    if timerActive ~= true then
      timerActive = true
      C_Timer.After(HOVER_DELAY, TimerCallback)
    end
  end

  GroupHideTooltip = function(self)
    local tooltips = MSUF.Tooltips
    if not tooltips or tooltips.hoverInert then return end
    self._msufGFTooltipToken = (self._msufGFTooltipToken or 0) + 1
    if pendingFrame == self then
      pendingFrame, pendingToken, pendingAt = nil, nil, nil
    end
    if tooltips.HideUnit then tooltips.HideUnit(self) end
  end
end

local function RemovePriorityUnitIndex(frame, unit)
  if not (frame and IsUnitToken(unit)) then return end
  local buckets = GF.priorityUnitFrames
  local bucket = buckets and buckets[unit]
  if not (bucket and bucket[frame] == true) then return end
  bucket[frame] = nil
  if next(bucket) == nil then
    buckets[unit] = nil
    if next(buckets) == nil then GF.priorityUnitFrames = nil end
  end
end

local function AddPriorityUnitIndex(frame, unit)
  local buckets = GF.priorityUnitFrames
  if not buckets then
    buckets = {}
    GF.priorityUnitFrames = buckets
  end
  local bucket = buckets[unit]
  if not bucket then
    bucket = setmetatable({}, { __mode = "k" })
    buckets[unit] = bucket
  end
  bucket[frame] = true
end

local function IndexFrameUnit(frame, unit)
  if not frame then return end
  local old = frame._msufGFIndexedUnit
  local wasPriority = frame._msufGFIndexedPriority == true
  local isPriority = IsPriorityFrame(frame)
  if IsUnitToken(old)
    and (not IsUnitToken(unit) or old ~= unit or wasPriority ~= isPriority) then
    if wasPriority then
      RemovePriorityUnitIndex(frame, old)
    elseif GF.unitFrames[old] == frame then
      GF.unitFrames[old] = nil
    end
  end
  if IsUnitToken(unit) then
    if isPriority then
      AddPriorityUnitIndex(frame, unit)
      frame._msufGFIndexedPriority = true
    else
      GF.unitFrames[unit] = frame
      frame._msufGFIndexedPriority = nil
    end
    frame._msufGFIndexedUnit = unit
  else
    frame._msufGFIndexedUnit = nil
    frame._msufGFIndexedPriority = nil
  end
end

local function UnindexFrameUnit(frame)
  if not frame then return end
  local indexed = frame._msufGFIndexedUnit
  if IsUnitToken(indexed) then
    if frame._msufGFIndexedPriority == true then
      RemovePriorityUnitIndex(frame, indexed)
    elseif GF.unitFrames[indexed] == frame then
      GF.unitFrames[indexed] = nil
    end
  end
  frame._msufGFIndexedUnit = nil
  frame._msufGFIndexedPriority = nil
end

local function TrackFrame(frame, unit)
  if not frame then return end
  if frame._msufGFInFrameList ~= true then
    frame._msufGFInFrameList = true
    GF.frameList[#GF.frameList + 1] = frame
  end
  GF.frames[frame] = true
  IndexFrameUnit(frame, unit or frame.MSUFUnitKey)
end
GF.TrackFrame = TrackFrame

function GF.FrameForUnit(unit)
  if not IsUnitToken(unit) then return nil end
  local frame = GF.unitFrames and GF.unitFrames[unit]
  if frame and frame.MSUFUnitKey == unit then return frame end
  return nil
end

--- Visit the authoritative group frame followed by exact tracked priority
--- duplicates for a plain unit token. The common no-duplicate path allocates
--- nothing and performs no frame-list scan. Return true when any callback
--- reports successful handling, matching GF.ForEachFrame semantics.
function GF.ForEachFrameForUnit(unit, fn, ...)
  if not IsUnitToken(unit) or type(fn) ~= "function" then return false end
  local any = false
  local primary = GF.FrameForUnit(unit)
  if primary and GF.frames[primary] == true then
    if fn(primary, unit, ...) == true then any = true end
  end

  local bucket = GF.priorityUnitFrames and GF.priorityUnitFrames[unit]
  if not bucket then return any end
  for frame in next, bucket do
    if frame ~= primary
      and GF.frames[frame] == true
      and frame._msufGFIndexedPriority == true
      and frame._msufGFIndexedUnit == unit
      and frame.MSUFUnitKey == unit
      and IsPriorityFrame(frame) then
      if fn(frame, unit, ...) == true then any = true end
    end
  end
  return any
end

local function BeginUnitIndexRebind()
  unitIndexRebindDepth = unitIndexRebindDepth + 1
end

local function EndUnitIndexRebind()
  unitIndexRebindDepth = unitIndexRebindDepth - 1
  if unitIndexRebindDepth < 1 then
    unitIndexRebindDepth = 0
  end
end

--- Resolve a PARTY_MEMBER_ENABLE/DISABLE target only when the secure child,
--- adapter index and visual binding all agree on the exact same plain token.
--- Core falls back to a full group barrier for every non-exact result.
local function IsExactLifecycleFrame(frame, unit)
  if not frame
    or GF.frames[frame] ~= true
    or frame.MSUFUnitKey ~= unit
    or frame._msufGFIndexedUnit ~= unit
    or frame._msufGFIsPreviewFrame == true then
    return false
  end
  local shell = ShellFrame(frame)
  if shell and shell._msufGFIsPreviewFrame == true then return false end
  if shell and shell.GetAttribute then
    local secureUnit = shell:GetAttribute(UNIT_ATTR)
    if not IsUnitToken(secureUnit) or secureUnit ~= unit then return false end
  end
  return true
end

function GF.ResolveLifecycleFrame(unit)
  if unitIndexRebindDepth > 0 or not IsUnitToken(unit) then
    return nil, false
  end
  local primary = GF.unitFrames and GF.unitFrames[unit]
  if primary then
    if not IsExactLifecycleFrame(primary, unit) then
      -- A stale authoritative index is a rebind hazard even when a priority
      -- copy already looks current. Force Core's full correctness barrier.
      return nil, false
    end
    local priorityBucket = GF.priorityUnitFrames and GF.priorityUnitFrames[unit]
    if priorityBucket then
      local foundPriority
      for frame in next, priorityBucket do
        if GF.frames[frame] == true and frame._msufGFIndexedPriority == true then
          if not IsExactLifecycleFrame(frame, unit) or not IsPriorityFrame(frame) then
            return nil, false
          end
          foundPriority = true
        end
      end
      if not foundPriority then return nil, false end
    end
    return primary, true
  end

  -- A priority header may legitimately expose a member that the active main
  -- header filters out. Accept that exact duplicate-only target, but require
  -- every live duplicate in its bucket to agree with the secure unit binding.
  local bucket = GF.priorityUnitFrames and GF.priorityUnitFrames[unit]
  if not bucket then return nil, false end
  local exact
  for frame in next, bucket do
    if GF.frames[frame] == true and frame._msufGFIndexedPriority == true then
      if not IsExactLifecycleFrame(frame, unit) or not IsPriorityFrame(frame) then
        return nil, false
      end
      exact = exact or frame
    end
  end
  return exact, exact ~= nil
end

function GF.ValidateUnitFrameMap(frame, unit)
  local visual = VisualFrame(frame)
  return IsUnitToken(unit) and visual ~= nil and GF.unitFrames[unit] == visual and visual.MSUFUnitKey == unit
end

local function MarkApplied(frame, kind, unit, spec)
  local power = spec and spec.power
  appliedSerial[frame] = spec and spec._msufGFCompileSerial or 0
  appliedUnit[frame] = unit
  appliedKind[frame] = kind
  appliedWidth[frame] = spec and spec.width or 0
  appliedHeight[frame] = spec and spec.height or 0
  appliedPowerEnabled[frame] = power and power.enabled == true
end

local function SameApplied(frame, kind, unit, spec)
  local power = spec and spec.power
  return frame
    and frame.MSUFSpec
    and appliedSerial[frame] == (spec and spec._msufGFCompileSerial or 0)
    and appliedUnit[frame] == unit
    and appliedKind[frame] == kind
    and appliedWidth[frame] == (spec and spec.width or 0)
    and appliedHeight[frame] == (spec and spec.height or 0)
    -- Per-role enablement is frame-owned and mutates without bumping the
    -- shared kind serial. Height itself is config-owned by that serial.
    and appliedPowerEnabled[frame] == (power and power.enabled == true)
end

local function NotifyGroupRangeUnitIdentity(frame)
  local update = frame and frame._msufUpdateGroupRangeFade
  if type(update) == "function" then
    update(frame, UNIT_CHANGED_REASON, frame.MSUFUnitKey)
  end
end

local function RefreshGroupUnitState(frame, reason)
  local refresh = UF and UF.RefreshGroupFrameState
  if type(refresh) == "function" then
    return refresh(frame, reason or UNIT_CHANGED_REASON)
  end
  if UF and UF.RunLeanIdentity then UF.RunLeanIdentity(frame, reason or UNIT_CHANGED_REASON) end
  NotifyGroupRangeUnitIdentity(frame)
  return false
end

local function FlushDeferredHeaderOnShow(frame, structureApplied)
  if not frame then return false end
  local deferred = frame._msufGFHeaderOnShowDeferred == true
  frame._msufGFHeaderOnShowDeferred = nil
  if deferred and structureApplied ~= true then
    RefreshGroupUnitState(frame, "MSUF_GF_ONSHOW")
  end
  local flushRange = UF and UF.FlushDeferredGroupRangeSettle
  if type(flushRange) == "function" then flushRange(frame) end
  return deferred
end

local function DiscardDeferredHeaderOnShow(frame)
  if not frame then return end
  frame._msufGFHeaderOnShowDeferred = nil
  local discardRange = UF and UF.DiscardDeferredGroupRangeSettle
  if type(discardRange) == "function" then discardRange(frame) end
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
  secureClicksConfigured[frame] = true
  return true
end

local function SetButtonBasics(shell, visual, unit, spec)
  local preview = IsPreviewFrame(shell, visual)
  shell._msufIsGroupFrameShell = true
  shell.MSUFUnitKey = unit
  shell.unitKey = unit
  visual._msufIsGroupFrame = true
  visual.MSUFUnitKey = unit
  visual.unitKey = unit
  if preview then
    -- Preview buttons are visual-only. Keep them out of ClickCastFrames and do
    -- not configure secure/default click handling that can never be used while
    -- mouse input is disabled.
    GF.UnregisterClickCastFrame(shell)
  else
    ConfigureSecureClicks(shell)
    GF.RegisterClickCastFrame(shell)
  end
  if shell.SetSize and not InCombat() then
    local w = spec and spec.width
    local h = spec and spec.height
    local sizeChanged = w and h and (shell._msufGFWidth ~= w or shell._msufGFHeight ~= h)
    if sizeChanged then
      shell:SetSize(w, h)
      shell._msufGFWidth = w
      shell._msufGFHeight = h
      if visual ~= shell and visual.SetSize then
        visual:SetSize(w, h)
      end
    end
  end
  if not preview then
    RegisterDefaultClicks(shell)
  end
end

function GF.UntrackFrame(frame)
  if not frame then return end
  local shell = ShellFrame(frame)
  local visual = VisualFrame(shell)
  GF.UnregisterClickCastFrame(shell)
  if UF and UF.DetachFrame then UF.DetachFrame(visual) end
  if UF and UF.DisablePingCompatibility then UF.DisablePingCompatibility(shell) end
  GF.frames[visual] = nil
  UnindexFrameUnit(visual)
  attrUnit[shell] = nil
  childKind[shell] = nil
  appliedSerial[visual] = nil
  appliedUnit[visual] = nil
  appliedKind[visual] = nil
  appliedWidth[visual] = nil
  appliedHeight[visual] = nil
  secureClicksConfigured[shell] = nil
  visual._msufGFInFrameList = nil
  for i = #GF.frameList, 1, -1 do
    if GF.frameList[i] == visual then table_remove(GF.frameList, i) end
  end
end

local function SuspendUnitBinding(frame)
  if not frame then return end
  local shell = ShellFrame(frame)
  local visual = VisualFrame(shell)
  -- Secure headers recycle children. Once a child has no unit, its old
  -- RegisterUnitEvent subscriptions must not keep crossing into Lua for the
  -- previous party/raid token; the normal rebind path rebuilds them exactly.
  if visual and visual.UnregisterAllEvents then visual:UnregisterAllEvents() end
  GF.frames[visual] = nil
  UnindexFrameUnit(visual)
  appliedUnit[visual] = nil
  visual._msufEventRouteUnit = nil
  attrUnit[shell] = NO_UNIT
  if visual then
    visual.MSUFUnitKey = nil
    visual.unitKey = nil
    DiscardDeferredHeaderOnShow(visual)
    NotifyGroupRangeUnitIdentity(visual)
  end
end

local function ApplyUnitFrame(frame, kind, unit, reason, applyMask, forceApply)
  if not (frame and kind and IsUnitToken(unit) and GF.CompileSpec) then return false end
  local shell = ShellFrame(frame)
  local visual = EnsureGroupVisual(shell)
  if not visual then return false end
  EnsureMouseoverHooks(shell)
  childKind[shell] = kind
  shell._msufGFKind = kind
  visual._msufGFKind = kind
  visual.configKey = "gf_" .. kind

  local spec = GF.CompileSpec(kind, visual, unit)
  if not spec then
    FlushDeferredHeaderOnShow(visual, false)
    return false
  end
  UF.SetFrameSpec(visual, spec, unit)
  SetButtonBasics(shell, visual, unit, spec)

  if forceApply ~= true and SameApplied(visual, kind, unit, spec) then
    attrUnit[shell] = unit
    TrackFrame(visual, unit)
    if not FlushDeferredHeaderOnShow(visual, false)
      and (reason == "UNIT_CHANGED" or reason == UNIT_CHANGED_REASON) then
      RefreshGroupUnitState(visual, UNIT_CHANGED_REASON)
    end
    return true
  end

  UF.AttachFrame(visual, { scope = "group" })
  GF.ApplyStructureSpec(visual, spec, reason == "UNIT_CHANGED" and UNIT_CHANGED_REASON or (reason or UNIT_STRUCTURE_REASON), applyMask or BASIC_GROUP_MASK)
  MarkApplied(visual, kind, unit, spec)
  attrUnit[shell] = unit
  TrackFrame(visual, unit)
  FlushDeferredHeaderOnShow(visual, true)
  -- Rounded masks otherwise arrive only through bulk ApplyAll passes; a visual
  -- built after the startup pass (login roster races, later joins) must adopt
  -- them itself. The callback is nil while the module is disabled and defers
  -- to the regen edge in combat.
  local rounded = _G.MSUF_RoundedUF_OnGroupFrameApplied
  if rounded then rounded(visual, kind) end
  return true
end

function GF.ApplyButton(frame, kind, reason)
  if not frame then return false end
  local unit = frame.GetAttribute and frame:GetAttribute("unit") or frame.MSUFUnitKey
  if not IsUnitToken(unit) then
    SuspendUnitBinding(frame)
    return false
  end
  return ApplyUnitFrame(frame, kind or frame._msufGFKind or "party", unit, reason)
end

--- Preview-only targeted apply. Live group refreshes already use the same dirty
--- mask resolver through Group_Runtime; this entry point lets cached menu/edit
--- preview frames keep that precision without changing the normal button path.
--- Unknown masks deliberately fall back to the full group mask.
function GF.ApplyPreviewButtonDirty(frame, kind, reason, dirtyMask)
  if not frame then return false end
  local unit = frame.GetAttribute and frame:GetAttribute("unit") or frame.MSUFUnitKey
  if not IsUnitToken(unit) then
    SuspendUnitBinding(frame)
    return false
  end
  local resolveMask = GF.ApplyMaskForDirtyMask
  local applyMask = type(resolveMask) == "function" and resolveMask(dirtyMask) or BASIC_GROUP_MASK
  return ApplyUnitFrame(frame, kind or frame._msufGFKind or "party", unit, reason, applyMask, true)
end

local function OnChildAttributeChanged(self, name, value)
  if name ~= UNIT_ATTR then return end
  BeginUnitIndexRebind()
  local visual = EnsureGroupVisual(self)
  local rawUnit = NormalizeAttrUnit(value)
  local oldUnit = StoredAttrUnit(self)
  local kind = childKind[self] or self._msufGFKind

  if rawUnit == NO_UNIT then
    SuspendUnitBinding(self)
    EndUnitIndexRebind()
    return
  end

  if oldUnit == rawUnit and visual and visual.MSUFSpec and appliedUnit[visual] == rawUnit then
    -- SecureGroupHeader rewrites unchanged partyN attributes on roster updates.
    -- Treat that write as the event-driven catch-up barrier instead of dropping
    -- it; raid headers stay on their normal per-unit paths to avoid 40 refreshes.
    -- Headers rewrite attributes in per-frame sweeps (several writes per child
    -- per roster/scenario tick), and each catch-up is a FULL compiled lifecycle
    -- pass. One catch-up per rendered frame per visual keeps the barrier
    -- semantics at a fraction of the cost; GetTime is frame-constant.
    if (kind or visual._msufGFKind) == "party" or IsPriorityFrame(visual) then
      local now = _G.GetTime and _G.GetTime()
      if now == nil or visual._msufGFCatchupFrameStamp ~= now then
        visual._msufGFCatchupFrameStamp = now
        RefreshGroupUnitState(visual, UNIT_CHANGED_REASON)
      end
    end
    EndUnitIndexRebind()
    return
  end

  if not (visual and visual.MSUFSpec) then
    ApplyUnitFrame(self, kind or "party", rawUnit, "UNIT_CHANGED")
    EndUnitIndexRebind()
    return
  end

  if visual.MSUFUnitKey == rawUnit then
    visual.MSUFSpec.unit = rawUnit
    visual.MSUFUnitKey = rawUnit
    visual.unitKey = rawUnit
    self.MSUFUnitKey = rawUnit
    self.unitKey = rawUnit
    attrUnit[self] = rawUnit
    appliedUnit[visual] = rawUnit
    if kind then appliedKind[visual] = kind end
    TrackFrame(visual, rawUnit)
    RefreshGroupUnitState(visual, UNIT_CHANGED_REASON)
    EndUnitIndexRebind()
    return
  end

  visual.MSUFSpec.unit = rawUnit
  if UF.OnUnitChanged then
    UF.OnUnitChanged(visual, oldUnit, rawUnit)
  else
    visual.MSUFUnitKey = rawUnit
    visual.unitKey = rawUnit
  end
  self.MSUFUnitKey = rawUnit
  self.unitKey = rawUnit
  visual.MSUFUnitKey = rawUnit
  attrUnit[self] = rawUnit
  appliedUnit[visual] = rawUnit
  if kind then appliedKind[visual] = kind end
  TrackFrame(visual, rawUnit)
  EndUnitIndexRebind()
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
      if fn(frame, frame.MSUFUnitKey, frame._msufGFKind, a, b, c) == true then any = true end
    end
  end
  return any
end
