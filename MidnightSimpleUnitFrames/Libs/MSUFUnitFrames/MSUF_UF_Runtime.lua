-- Instance-local public runtime bridge for embedded MSUFUnitFrames hosts.
local _, MSUF = ...

MSUF.UF = MSUF.UF or {}

local UF = MSUF.UF
local Metadata = UF.Metadata or {}
local ExportPublic = MSUF.ExportPublic
local GetProfileScopedCache = MSUF.Require("MSUF_GetProfileScopedCache", "Libs/MSUFUnitFrames/MSUF_UF_Runtime.lua")

local type = type
local pairs = pairs
local tostring = tostring
local tonumber = tonumber
local math_floor = math.floor
local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue

local DEFERRED_REFRESH_ALL = "*"
local EMPTY_LIST = {}

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local function QueueDeferredElementRefresh(unit, names, reason)
  local pending = UF.pendingElementRefreshes
  local key = unit or DEFERRED_REFRESH_ALL
  if key == DEFERRED_REFRESH_ALL then
    -- A global request widens the scope of every queued entry, but it must
    -- inherit their element names: the flush only ever applies the surviving
    -- entry's name set, so dropping the entries dropped that queued work.
    -- Widening per-unit names to all frames is what the branch below already
    -- does when a global entry is pending, and re-applying an element is
    -- idempotent. Creating the global entry before the walk keeps the pairs()
    -- traversal legal -- only removals happen inside it.
    local global = pending[DEFERRED_REFRESH_ALL]
    if not global then
      global = { names = {} }
      pending[DEFERRED_REFRESH_ALL] = global
    end
    for existing, entry in pairs(pending) do
      if existing ~= DEFERRED_REFRESH_ALL then
        local existingNames = entry and entry.names
        if existingNames then
          for name in pairs(existingNames) do global.names[name] = true end
        end
        if global.reason == nil and entry then global.reason = entry.reason end
        pending[existing] = nil
      end
    end
  elseif pending[DEFERRED_REFRESH_ALL] then
    key = DEFERRED_REFRESH_ALL
  end
  local entry = pending[key]
  if not entry then
    entry = { names = {} }
    pending[key] = entry
  end
  for i = 1, #names do
    local name = names[i]
    local allowed = UF.ApplyElementAllowed or UF.CoreElementAllowed
    if not allowed or allowed(name) then
      entry.names[name] = true
    end
  end
  entry.reason = reason or entry.reason or "MSUF_DEFERRED_REFRESH"
  entry.serial = (entry.serial or 0) + 1
  local factory = UF.Factory
  if factory and factory.EnsureDeferredDriver then factory.EnsureDeferredDriver() end
  return false
end

local function DeferredList(entry)
  local list = entry.list or {}
  entry.list = list
  local n = 0
  for i = 1, #UF.elementOrder do
    local name = UF.elementOrder[i]
    if entry.names[name] == true then
      n = n + 1
      list[n] = name
    end
  end
  for i = n + 1, #list do list[i] = nil end
  return list
end

-- true: applied work; nil: no eligible work; false: failed/deferred work.
function UF.RefreshElements(unit, names, reason)
  if type(names) ~= "table" then return false end
  if #names == 0 then return nil end
  if InCombat() then return QueueDeferredElementRefresh(unit, names, reason) end
  local units = unit and UF.UnitsForConfigKey and UF.UnitsForConfigKey(unit)
  if unit and not units then return nil end
  local config = UF.Config
  local refreshedAll = not unit and config and type(config.Refresh) == "function"
  if refreshedAll then config.Refresh() end
  local result
  local frames = UF.frames
  local list = units or UF.frameList
  for i = 1, #list do
    local frame
    if units then frame = frames[list[i]] else frame = list[i] end
    if frame then
      local spec = frame.MSUFSpec
      if refreshedAll and config and type(config.GetSpec) == "function" then
        spec = config.GetSpec(frame.MSUFUnitKey)
      elseif config and type(config.RefreshUnit) == "function" then
        spec = config.RefreshUnit(frame.MSUFUnitKey)
      elseif config and type(config.GetSpec) == "function" then
        spec = config.GetSpec(frame.MSUFUnitKey)
      end
      local applied = UF.ApplyElementsToFrame(frame, names, spec, reason or "MSUF_ELEMENT_REFRESH")
      if applied == false then result = false
      elseif applied == true and result == nil then result = true end
    end
  end
  if result == false then QueueDeferredElementRefresh(unit, names, reason) end
  return result
end

local deferredRefreshActive = false
local deferredKeys, deferredEntries = {}, {}

local function RunDeferredRefreshes()
  local result
  local pending = UF.pendingElementRefreshes
  local count = 0
  for key, entry in pairs(pending) do
    count = count + 1
    deferredKeys[count], deferredEntries[count] = key, entry
  end
  for i = 1, count do
    local key, entry = deferredKeys[i], deferredEntries[i]
    if pending[key] == entry then
      local list = DeferredList(entry)
      local serial = entry.serial
      local applied
      if #list > 0 then
        applied = UF.RefreshElements(key ~= DEFERRED_REFRESH_ALL and key or nil, list, entry.reason)
      end
      -- Leave the original names/reason reachable even if an error reporter raises.
      -- A global failed selection stays global; retrying successful siblings is safe.
      if applied == false then
        result = false
      else
        if pending[key] == entry and entry.serial == serial then pending[key] = nil end
        if applied == true and result == nil then result = true end
      end
    end
  end
  return result
end

local function FinishDeferredRefreshes()
  deferredRefreshActive = false
  for i = #deferredKeys, 1, -1 do deferredKeys[i], deferredEntries[i] = nil, nil end
  if next(UF.pendingElementRefreshes) then UF.Factory.EnsureDeferredDriver() end
end

function UF.FlushDeferredRefreshes()
  if InCombat() then return false end
  if deferredRefreshActive or next(UF.pendingElementRefreshes) == nil then return nil end
  deferredRefreshActive = true
  local ok, result = MSUF.RunUnitFrameApply(RunDeferredRefreshes, FinishDeferredRefreshes)
  if not ok then return false end
  return result
end

function UF.MarkDirty(unit)
  if unit then
    local units = UF.UnitsForConfigKey and UF.UnitsForConfigKey(unit)
    if units then
      for i = 1, #units do UF.pendingApply[units[i]] = true end
    else
      UF.pendingApply[unit] = true
    end
    return
  end
  for i = 1, #UF.unitOrder do UF.pendingApply[UF.unitOrder[i]] = true end
end

local function RunDirtyUnitApply(unit, factory)
  UF.pendingApply[unit] = nil
  local applied = factory.Apply(unit)
  if applied ~= true then UF.pendingApply[unit] = true end
  return applied
end

local function FinishDirtyUnitApply(ok, unit)
  if not ok then UF.pendingApply[unit] = true end
end

function UF.ApplyDirty()
  if InCombat() then return false end
  local factory = UF.Factory
  if not (factory and factory.Apply) then return false end
  -- A combat login deferred the whole lifecycle, including the spawn-only seeds.
  if factory.spawnPending then
    if not factory.SpawnAll() then return false end
    for unit in pairs(UF.pendingApply) do UF.pendingApply[unit] = nil end
    return true
  end
  -- Walk a snapshot: a failed unit is put back into pendingApply, and adding a
  -- key to a table during its own pairs() traversal is undefined in Lua 5.1.
  local units = {}
  for unit in pairs(UF.pendingApply) do units[#units + 1] = unit end
  local applied = true
  for i = 1, #units do
    local ok, result = MSUF.RunUnitFrameApply(RunDirtyUnitApply, FinishDirtyUnitApply, units[i], factory)
    if not ok or result ~= true then applied = false end
  end
  return #units > 0 and applied
end

function UF.RequestReanchorAfterCombat()
  if InCombat() then
    UF.MarkDirty(nil)
    local factory = UF.Factory
    if factory and factory.EnsureDeferredDriver then factory.EnsureDeferredDriver() end
    return false
  end
  return UF.Apply(nil)
end

local function GetUnitFrameScreenCacheKey(key, unit)
  local k = tostring(key or "")
  local u = tostring(unit or "")
  if k == "" then return u ~= "" and u or nil end
  if (k == "boss" or k == "arena") and u ~= "" then return k .. ":" .. u end
  return k
end

local function GetUnitFrameScreenCacheBucket()
  return GetProfileScopedCache("unitFrameScreenCache")
end

local function GetFramePoint(frame, point)
  if not frame then return nil, nil, nil end
  point = point or "CENTER"
  if point == "CENTER" and frame.GetCenter then
    local x, y = frame:GetCenter()
    return x, y, "CENTER"
  end
  if not (frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then
    if frame.GetCenter then
      local x, y = frame:GetCenter()
      return x, y, "CENTER"
    end
    return nil, nil, nil
  end
  local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
  if not (l and r and t and b) then return nil, nil, nil end
  local cx, cy = (l + r) * 0.5, (t + b) * 0.5
  if point == "TOPLEFT" then return l, t, point end
  if point == "TOP" then return cx, t, point end
  if point == "TOPRIGHT" then return r, t, point end
  if point == "LEFT" then return l, cy, point end
  if point == "RIGHT" then return r, cy, point end
  if point == "BOTTOMLEFT" then return l, b, point end
  if point == "BOTTOM" then return cx, b, point end
  if point == "BOTTOMRIGHT" then return r, b, point end
  return cx, cy, "CENTER"
end

local function CacheUnitFrameScreenPosition(frame, key, unit, point, allowLocked)
  local uiParent = UIParent
  if not frame or not key or not uiParent or not uiParent.GetCenter then return false end
  if allowLocked ~= true and InCombat() then return false end
  local fx, fy, usedPoint = GetFramePoint(frame, point or frame._msufHardLockPoint or "CENTER")
  local ux, uy = uiParent:GetCenter()
  if not (fx and fy and ux and uy) then return false end
  local fs = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
  local us = uiParent.GetEffectiveScale and uiParent:GetEffectiveScale() or 1
  if fs == 0 then fs = 1 end
  if us == 0 then us = 1 end
  local id = GetUnitFrameScreenCacheKey(key, unit)
  local bucket = GetUnitFrameScreenCacheBucket()
  if not (id and bucket) then return false end
  bucket[id] = {
    v = 3,
    x = math_floor(((fx * fs - ux * us) / us) + 0.5),
    y = math_floor(((fy * fs - uy * us) / us) + 0.5),
    w = frame.GetWidth and frame:GetWidth() or nil,
    h = frame.GetHeight and frame:GetHeight() or nil,
    scale = frame.GetScale and frame:GetScale() or nil,
    point = usedPoint or point or "CENTER",
  }
  return true
end

local function ApplyCachedUnitFrameScreenPosition(frame, key, unit)
  local uiParent = UIParent
  local bucket = GetUnitFrameScreenCacheBucket()
  local id = GetUnitFrameScreenCacheKey(key, unit)
  local cached = bucket and id and bucket[id]
  if not (frame and uiParent and type(cached) == "table" and (cached.v == 2 or cached.v == 3)) then
    return false
  end
  local x, y = tonumber(cached.x), tonumber(cached.y)
  if not (x and y) then return false end
  if cached.v == 3 and frame.SetScale and tonumber(cached.scale) then
    frame:SetScale(tonumber(cached.scale))
  end
  local point = type(cached.point) == "string" and cached.point ~= "" and cached.point or "CENTER"
  -- Both cache versions store UIParent-space offsets. SetPoint consumes
  -- offsets in the restored frame's coordinate space, after SetScale above.
  local frameScale = frame:GetEffectiveScale()
  local parentScale = uiParent:GetEffectiveScale()
  if frameScale <= 0 or parentScale <= 0 then return false end
  local ratio = parentScale / frameScale
  frame:ClearAllPoints()
  frame:SetPoint(point, uiParent, "CENTER", x * ratio, y * ratio)
  frame._msufPositionInitialized = true
  frame._msufHardLockedToUIParent = true
  frame._msufHardLockPoint = point
  frame._msufLoadedFromScreenCache = true
  return true
end

local function RuntimeFrame(unit)
  if unit and issecretvalue(unit) == true then return nil end
  local frame = unit and UF.frames[unit]
  if not frame then return nil end
  local spec = frame.MSUFSpec
  if spec and spec.enabled == false then return nil end
  if frame._msufIdentityCount == nil and frame._msufIdentityBarPath == nil and UF.RebuildRuntimeStatusState then
    UF.RebuildRuntimeStatusState(frame)
  end
  return (frame._msufIdentityCount or frame._msufIdentityBarPath) and frame or nil
end

local function RunIdentity(unit, reason)
  local frame = RuntimeFrame(unit)
  return frame and UF.RunLeanIdentity and UF.RunLeanIdentity(frame, reason or "MSUF_UNIT_IDENTITY") or false
end

local function RunDependentUnits(parent)
  if parent == "target" then return RunIdentity("targettarget", "MSUF_UNIT_IDENTITY_SOFT") end
  if parent == "focus" then return RunIdentity("focustarget", "MSUF_UNIT_IDENTITY_SOFT") end
  if parent == "pet" then return RunIdentity("pettarget", "MSUF_UNIT_IDENTITY_SOFT") end
  local a = RunIdentity("targettarget", "MSUF_UNIT_IDENTITY_SOFT")
  local b = RunIdentity("focustarget", "MSUF_UNIT_IDENTITY_SOFT")
  local c = RunIdentity("pettarget", "MSUF_UNIT_IDENTITY_SOFT")
  return a or b or c
end

function UF.SyncRuntimeDriver()
  local driver = UF.driver
  if driver then
    if driver.UnregisterAllEvents then driver:UnregisterAllEvents() end
    if driver.SetScript then driver:SetScript("OnEvent", nil) end
    UF.driver = nil
  end
  return true
end

local function ConfigTouchesDependentUnits(unit)
  if unit == nil or unit == "*" then return true end
  local units = UF.UnitsForConfigKey and UF.UnitsForConfigKey(unit)
  if not units then return false end
  for i = 1, #units do
    if units[i] == "targettarget" or units[i] == "focustarget" or units[i] == "pettarget" then return true end
  end
  return false
end

local function RefreshConfigForApply(unit)
  local config = UF.Config
  if not config then return false end
  if InCombat() then
    config.dirty = true
    return false
  end
  if unit and unit ~= "*" and type(config.RefreshUnit) == "function" then
    local units = UF.UnitsForConfigKey and UF.UnitsForConfigKey(unit)
    if units then
      for i = 1, #units do config.RefreshUnit(units[i]) end
      return true
    end
  end
  if type(config.Refresh) == "function" then
    config.Refresh()
    return true
  end
  config.dirty = true
  return false
end

function UF.NotifyConfigChanged(unit, applyNow, forceUpdate, _, applyMask)
  if InCombat() then
    UF.MarkDirty(unit)
    if UF.Config then UF.Config.dirty = true end
    local factory = UF.Factory
    if factory and factory.EnsureDeferredDriver then factory.EnsureDeferredDriver() end
    return false
  end
  if applyNow ~= false then
    -- Factory.Apply(nil) already performs the one required Config.Refresh().
    -- Scoped applies do not, so retain their per-unit RefreshUnit pass here.
    if unit ~= nil then RefreshConfigForApply(unit) end
    local ok = UF.Apply(unit, applyMask) and true or false
    if ConfigTouchesDependentUnits(unit) then RunDependentUnits() end
    return ok
  elseif forceUpdate ~= false then
    RefreshConfigForApply(unit)
    local ok = UF.ForceUpdate(unit) and true or false
    if ConfigTouchesDependentUnits(unit) then RunDependentUnits() end
    return ok
  end
  return true
end

function UF.RegisterVisualRefreshCallback(key, fn)
  if type(fn) ~= "function" then return false end
  UF.visualRefreshCallbacks[key or fn] = fn
  return true
end

function UF.UnregisterVisualRefreshCallback(key)
  if key == nil then return false end
  local existed = UF.visualRefreshCallbacks[key] ~= nil
  UF.visualRefreshCallbacks[key] = nil
  return existed
end

local function RunVisualRefreshCallbacks(unit)
  for _, fn in pairs(UF.visualRefreshCallbacks) do fn(unit) end
end

local refreshGroups = Metadata.refreshElementGroups or {}
local HEALTH_TEXT_BORDER_ELEMENTS = refreshGroups.healthTextBorder or EMPTY_LIST
local VISUAL_ELEMENTS = refreshGroups.visuals or EMPTY_LIST
local POWER_TEXT_ELEMENTS = refreshGroups.powerText or EMPTY_LIST
local COLOR_ELEMENTS = refreshGroups.colors or VISUAL_ELEMENTS
local TEXT_ELEMENTS = refreshGroups.text or EMPTY_LIST
local BORDER_ELEMENTS = refreshGroups.borders or EMPTY_LIST
local REVERSE_FILL_ELEMENTS = refreshGroups.reverseFill or EMPTY_LIST
local ALPHA_ELEMENTS = refreshGroups.alpha or EMPTY_LIST

function UF.RefreshVisuals(unit)
  local ok = UF.RefreshElements(unit, VISUAL_ELEMENTS, "MSUF_VISUALS")
  RunVisualRefreshCallbacks(unit)
  MSUF.EventBus:Publish("CONFIG_APPLIED", "MSUF_RefreshAllFrames")
  return ok
end

function UF.RefreshIdentityColors(unit)
  local result = UF.RefreshElements(unit, HEALTH_TEXT_BORDER_ELEMENTS, "MSUF_IDENTITY_COLORS")
  MSUF.EventBus:Publish("CONFIG_APPLIED", "MSUF_RefreshAllIdentityColors")
  return result
end

function UF.RefreshPowerTextColors(unit)
  local result = UF.RefreshElements(unit, POWER_TEXT_ELEMENTS, "MSUF_POWER_TEXT_COLORS")
  MSUF.EventBus:Publish("CONFIG_APPLIED", "MSUF_RefreshAllPowerTextColors")
  return result
end

function UF.RefreshColors(unit)
  return UF.RefreshElements(unit, COLOR_ELEMENTS, "MSUF_COLOR_CHANGE")
end

function UF.RefreshAlphas(unit)
  local result = UF.RefreshElements(unit, ALPHA_ELEMENTS, "MSUF_ALPHA")
  MSUF.EventBus:Publish("CONFIG_APPLIED", "MSUF_RefreshAllUnitAlphas")
  return result
end

function UF.RefreshBorders(unit)
  return UF.RefreshElements(unit, BORDER_ELEMENTS, "MSUF_BORDER_LAYOUT")
end

function UF.RefreshHealthLayout()
  return UF.RefreshElements(nil, REVERSE_FILL_ELEMENTS, "MSUF_REVERSE_FILL")
end

local PREDICTION_ELEMENTS = { "Prediction", "Alpha" }
local GROUP_PREDICTION_ELEMENTS = { "Prediction" }
local TEMP_MAX_HEALTH_ELEMENTS = { "TempMaxHealth" }

local function GroupPredictionScopeMatches(kind, scope)
  if scope == nil or scope == "*" or scope == "shared" then return true end
  if scope == "gf_party" then scope = "party" end
  if scope == "gf_raid" or scope == "raid" then return kind == "raid" or kind == "mythicraid" end
  if scope == "gf_mythicraid" then return kind == "mythicraid" end
  return kind == scope
end

-- The group runtime (UnitFrames/Engine/Group: Config, Adapter, RangeFade) and the
-- Alpha element belong to the MSUF host on every client and have loaded before
-- any refresh below runs, so their entry points are called directly.
local function InvalidateGroupPredictionSpecs(GF, scope)
  if scope == nil or scope == "*" or scope == "shared" then
    GF.InvalidateCompiledSpecs()
  elseif scope == "gf_party" or scope == "party" then
    GF.InvalidateCompiledSpecs("party")
  elseif scope == "gf_raid" or scope == "raid" then
    GF.InvalidateCompiledSpecs("raid")
    GF.InvalidateCompiledSpecs("mythicraid")
  elseif scope == "gf_mythicraid" or scope == "mythicraid" then
    GF.InvalidateCompiledSpecs("mythicraid")
  end
end

local function ApplyGroupPredictionSpec(frame, spec, unit, reason)
  UF.SetFrameSpec(frame, spec, unit)
  if UF.ApplyElementsToFrame(frame, GROUP_PREDICTION_ELEMENTS, spec, reason) ~= true then return false end
  UF.ApplyPredictionAlphaFills(frame, spec, true)
  UF.elements.GroupRangeFade.RecomposePredictionAlpha(frame)
  return true
end

local function ApplyGroupTempMaxHealthSpec(frame, spec, unit, reason)
  UF.SetFrameSpec(frame, spec, unit)
  return UF.ApplyElementsToFrame(frame, TEMP_MAX_HEALTH_ELEMENTS, spec, reason)
end

local function RefreshGroupSpecFrame(frame, unit, kind, state)
  if GroupPredictionScopeMatches(kind, state.scope) ~= true then return end
  if issecretvalue(unit) == true or type(unit) ~= "string" or unit == "" then return end
  local spec = MSUF.GF.CompileSpec(kind, frame, unit)
  if not spec then return false end
  return state.apply(frame, spec, unit, state.reason)
end

local function RunGroupSpecs(state)
  local GF = MSUF.GF
  InvalidateGroupPredictionSpecs(GF, state.scope)
  state.did, state.success = GF.ForEachFrame(RefreshGroupSpecFrame, true, state)
end

local function FinishGroupSpecs(ok, state)
  if ok and state.success ~= false then return end
  -- The normal group replay is a superset of this selection. Keep it reachable
  -- before reporting, including when the client's error reporter itself raises.
  local scope = state.scope
  if scope == "party" or scope == "gf_party" then scope = "party"
  elseif scope == "mythicraid" or scope == "gf_mythicraid" then scope = "mythicraid"
  else scope = nil end
  MSUF.GF.DeferGroupRuntime("refresh", scope, MSUF.GF.DIRTY_VISUAL)
end

local function RefreshGroupSpecs(scope, reason, apply)
  local state = { scope = scope, reason = reason, apply = apply }
  local ok = MSUF.RunUnitFrameApply(RunGroupSpecs, FinishGroupSpecs, state)
  if not ok or state.success == false then return false end
  if state.did then return true end
end

function UF.RefreshPredictionBars(scope, reason, skipUnitFrames)
  reason = reason or "MSUF2_ABSORB"
  local did
  if skipUnitFrames ~= true then
    local selectedValue2
    if not (scope == "shared") then selectedValue2 = scope end
    did = UF.RefreshElements(selectedValue2, PREDICTION_ELEMENTS, reason)
  end
  local group = RefreshGroupSpecs(scope, reason, ApplyGroupPredictionSpec)
  if did == false or group == false then return false end
  return group or did or false
end

function UF.RefreshTempMaxHealth(scope, reason)
  reason = reason or "MSUF2_TEMP_MAX_HEALTH"
  local selectedValue1
  if not (scope == "shared") then selectedValue1 = scope end
  local did = UF.RefreshElements(selectedValue1, TEMP_MAX_HEALTH_ELEMENTS, reason)
  local group = RefreshGroupSpecs(scope, reason, ApplyGroupTempMaxHealthSpec)
  if did == false or group == false then return false end
  return group or did or false
end

function UF.RefreshPowerLayout(unit)
  local result = UF.RefreshElements(unit, POWER_TEXT_ELEMENTS, "MSUF_POWER_LAYOUT")
  MSUF.EventBus:Publish("CONFIG_APPLIED", "MSUF_ApplyPowerBarEmbedLayout_ForUnitKey")
  return result
end

function UF.RefreshPowerLayoutForFrame(frame)
  return UF.RefreshPowerLayout(frame and frame.MSUFUnitKey or nil)
end

function UF.RefreshTextLayout(unit)
  local result = UF.RefreshElements(unit, TEXT_ELEMENTS, "MSUF_TEXT_LAYOUT")
  MSUF.EventBus:Publish("CONFIG_APPLIED", "MSUF_ForceTextLayoutForUnitKey")
  return result
end

function UF.ApplyUnitFrameKey(unit, applyMask)
  local result = UF.Apply(unit, applyMask)
  MSUF.EventBus:Publish("CONFIG_APPLIED", "MSUF_ApplyUnitFrameKey_Immediate")
  return result
end

MSUF.UnitFrames = UF
ExportPublic("MSUF_UnitFrames", UF.frames)
ExportPublic("MSUF_UnitFramesList", UF.frameList)
ExportPublic("MSUF_CacheUnitFrameScreenPosition", CacheUnitFrameScreenPosition)
ExportPublic("MSUF_ApplyCachedUnitFrameScreenPosition", ApplyCachedUnitFrameScreenPosition)
ExportPublic("MSUF_UFCore_NotifyConfigChanged", UF.NotifyConfigChanged)
ExportPublic("MSUF_RefreshAllFrames", UF.RefreshVisuals)
MSUF.MSUF_RefreshAllFrames = UF.RefreshVisuals
ExportPublic("MSUF_RefreshAllFrameColors", UF.RefreshColors)
ExportPublic("MSUF_RefreshAllIdentityColors", UF.RefreshIdentityColors)
ExportPublic("MSUF_RefreshAllPowerTextColors", UF.RefreshPowerTextColors)
ExportPublic("MSUF_ForceTextLayoutForUnitKey", UF.RefreshTextLayout)
ExportPublic("MSUF_RefreshAllUnitAlphas", UF.RefreshAlphas)
ExportPublic("MSUF_ApplyBarOutlineThickness_All", UF.RefreshBorders)
--- Deprecated compatibility alias of MSUF_ApplyBarOutlineThickness_All.
ExportPublic("MSUF_ApplyPowerBarBorder_All", UF.RefreshBorders)
ExportPublic("MSUF_ApplyReverseFillBars", UF.RefreshHealthLayout)
ExportPublic("MSUF_RefreshPredictionBars", UF.RefreshPredictionBars)
ExportPublic("MSUF_RefreshTempMaxHealth", UF.RefreshTempMaxHealth)
--- Deprecated compatibility alias of MSUF_RefreshAllUnitAlphas.
ExportPublic("MSUF_ApplyAllAlpha", UF.RefreshAlphas)
MSUF.Compat = MSUF.Compat or {}
MSUF.Compat.DeprecatedAliases = MSUF.Compat.DeprecatedAliases or {}
MSUF.Compat.DeprecatedAliases.MSUF_ApplyAllAlpha = "MSUF_RefreshAllUnitAlphas"
MSUF.Compat.DeprecatedAliases.MSUF_ApplyPowerBarBorder_All = "MSUF_ApplyBarOutlineThickness_All"
ExportPublic("MSUF_ApplyPowerBarEmbedLayout_All", UF.RefreshPowerLayout)
ExportPublic("MSUF_ApplyPowerBarEmbedLayout", UF.RefreshPowerLayoutForFrame)
ExportPublic("MSUF_ApplyPowerBarEmbedLayout_ForUnitKey", UF.RefreshPowerLayout)
ExportPublic("MSUF_ApplyUnitFrameKey_Immediate", UF.ApplyUnitFrameKey)
