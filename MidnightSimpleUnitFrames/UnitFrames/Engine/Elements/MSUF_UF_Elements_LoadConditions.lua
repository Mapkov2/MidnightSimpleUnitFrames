-- UF load-condition element: applies profile visibility rules to unit frames.
-- Protected visibility or secure state changes must stay behind combat-safe helpers.
local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic

local UF = MSUF.UF
if not UF then return end
local Preview = MSUF.Require("MSUF", "UnitFrames/Engine/Elements/MSUF_UF_Elements_LoadConditions.lua").UF.Preview
local previewKind = type(Preview)
assert(previewKind == "table",
  "MSUF: missing required dependency 'UF.Preview' required by UnitFrames/Engine/Elements/MSUF_UF_Elements_LoadConditions.lua")
local validateKind = type(Preview.Validate)
assert(validateKind == "function",
  "MSUF: missing required dependency 'UF.Preview.Validate' required by UnitFrames/Engine/Elements/MSUF_UF_Elements_LoadConditions.lua")
Preview.Validate("UnitFrames/Engine/Elements/MSUF_UF_Elements_LoadConditions.lua")
local previewState, forcedUnits = Preview.State, Preview.ForcedUnits

-- Unitframe load-condition element.
-- Owns secure state-driver visibility rules for mounted/combat/group/instance/resting style
-- conditions. Protected state changes are deferred or expressed through secure snippets.
local RegisterStateDriver = _G.RegisterStateDriver
local UnregisterStateDriver = _G.UnregisterStateDriver
local SecureCmdOptionParse = _G.SecureCmdOptionParse
local InCombatLockdown = _G.InCombatLockdown
local UnitAffectingCombat = _G.UnitAffectingCombat
local IsInInstance = _G.IsInInstance
local C_Housing = _G.C_Housing
local Secrets = MSUF.Secrets or {}
local UnitExistsPlain = Secrets.UnitExistsPlain
local type = type
local tonumber = tonumber
local next = next

local EMPTY_EVENTS = {}
local HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH" }
local UnitHealthPercent = _G.UnitHealthPercent
local CurveAPI = _G.C_CurveUtil
local LuaCurveType = _G.Enum and _G.Enum.LuaCurveType
local FALLBACK_EVENTS = {
  "PLAYER_ENTERING_WORLD",
  "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED",
  "PLAYER_MOUNT_DISPLAY_CHANGED",
  "UNIT_ENTERED_VEHICLE",
  "UNIT_EXITED_VEHICLE",
  "PLAYER_UPDATE_RESTING",
  "GROUP_ROSTER_UPDATE",
  "UPDATE_STEALTH",
  "ZONE_CHANGED_NEW_AREA",
}
local BOSS_PREVIEW_UNITS = {
  boss1 = true,
  boss2 = true,
  boss3 = true,
  boss4 = true,
  boss5 = true,
}
local LoadConditions = {}
local healthVisibilityCurve

local function HealthVisibilityEnabled(frame, spec)
  return frame and frame._msufHealthVisualRoot and type(frame.MSUFUnitKey) == "string"
    and spec and spec.load and spec.load.showWhenInjured == true
    and UnitHealthPercent ~= nil and CurveAPI and CurveAPI.CreateCurve ~= nil
    and LuaCurveType and LuaCurveType.Step ~= nil
end

local function ApplyHealthAlpha(frame)
  -- Only Edit Mode bypasses the HP gate so the frame remains editable.
  -- Combat and target state must never reveal a full-health unit.
  -- Secret health is evaluated inside Blizzard's native curve and passed
  -- straight to SetAlpha (upstream/live 12.1).
  if previewState.editMode == true
    or (BOSS_PREVIEW_UNITS[frame.MSUFUnitKey] and previewState.bossHealth == true)
    or frame._msufArenaPreviewForced == true then
    frame._msufHealthVisualRoot:SetAlpha(1)
    if frame._msufHealthIndependentVisualRoot then frame._msufHealthIndependentVisualRoot:SetAlpha(1) end
    return
  end
  local alpha = UnitHealthPercent(frame.MSUFUnitKey, false, healthVisibilityCurve)
  frame._msufHealthVisualRoot:SetAlpha(alpha)
  if frame._msufHealthIndependentVisualRoot then frame._msufHealthIndependentVisualRoot:SetAlpha(alpha) end
end

local function RefreshHealthAlpha(frame)
  if frame and frame._msufLoadHealthAlphaApply then
    ApplyHealthAlpha(frame)
  end
end

local function ClearHealthAlpha(frame)
  if not (frame and frame._msufLoadHealthAlphaApply) then return end
  frame._msufLoadHealthAlphaApply = nil
  frame._msufHealthVisualRoot:SetAlpha(1)
  if frame._msufHealthIndependentVisualRoot then frame._msufHealthIndependentVisualRoot:SetAlpha(1) end
end

local function ConfigureHealthAlpha(frame, spec)
  if not HealthVisibilityEnabled(frame, spec) then
    ClearHealthAlpha(frame)
    return
  end
  if not healthVisibilityCurve then
    local curve = CurveAPI.CreateCurve()
    curve:SetType(LuaCurveType.Step)
    curve:AddPoint(0, 1)
    curve:AddPoint(1, 0)
    healthVisibilityCurve = curve
  end
  frame._msufLoadHealthAlphaApply = ApplyHealthAlpha
  RefreshHealthAlpha(frame)
end

local function InInstance()
  if not IsInInstance then
    return false
  end
  local inside = IsInInstance()
  return inside == true or inside == 1
end

local function InHousing()
  local fn = C_Housing and C_Housing.IsInsideHouseOrPlot
  if type(fn) ~= "function" then
    return false
  end
  return fn() == true
end

local function ArenaPrepForcesUnit(unit)
  if _G.MSUF_ArenaPrepVisibilityActive ~= true then return false end
  local index = type(unit) == "string" and tonumber(unit:match("^arena(%d+)$")) or nil
  local count = tonumber(_G.MSUF_ArenaPrepVisibilityCount) or 0
  return index ~= nil and index >= 1 and index <= count
end

local function ShouldForcePreview(frame)
  if not frame then
    return false
  end
  -- MSUFUnitKey is the engine's fixed configured token, never a unit API value.
  local unit = frame.MSUFUnitKey
  local forced = forcedUnits[unit]
  -- An arena slot that is not forced still follows the live arena-prep facts.
  if forced == "prep" then return ArenaPrepForcesUnit(unit) end
  return forced or false
end

local function BuildRuntimeVisibility(frame, spec)
  local load = spec.load
  if load and load.hideInInstance == true and InInstance() then
    return "hide"
  end
  if load and load.hideInHousing == true and InHousing() then
    return "hide"
  end

  local unit = spec.unit or frame.MSUFUnitKey
  if type(unit) ~= "string" or unit == "" then
    unit = "player"
  end

  local rules = frame._msufLoadRules
  if not rules then
    rules = {}
    frame._msufLoadRules = rules
  end
  local n = 0
  if load then
    if load.hideMounted == true then n = n + 1; rules[n] = "[mounted] hide" end
    if load.hideInVehicle == true then
      n = n + 1; rules[n] = "[@player,unithasvehicleui] hide"
      n = n + 1; rules[n] = "[vehicleui] hide"
    end
    if load.hideResting == true then n = n + 1; rules[n] = "[resting] hide" end
    if load.hideInCombat == true then n = n + 1; rules[n] = "[combat] hide" end
    if not HealthVisibilityEnabled(frame, spec) then
      if load.hideOutOfCombat == true then n = n + 1; rules[n] = "[nocombat] hide" end
      if load.hideNoTarget == true then n = n + 1; rules[n] = "[@target,noexists] hide" end
      if load.hideOutOfCombatNoTarget == true then n = n + 1; rules[n] = "[nocombat,@target,noexists] hide" end
    end
    if load.hideStealthed == true then n = n + 1; rules[n] = "[stealth] hide" end
    if load.hideSolo == true then n = n + 1; rules[n] = "[nogroup] hide" end
    if load.hideInGroup == true then n = n + 1; rules[n] = "[group] hide" end
  end
  n = n + 1
  rules[n] = "[@" .. unit .. ",exists] show"
  n = n + 1
  rules[n] = "hide"
  for i = n + 1, #rules do
    rules[i] = nil
  end
  return table.concat(rules, "; ")
end

local function BuildVisibility(frame, spec)
  if not (frame and spec) or spec.enabled == false then
    return "hide"
  end

  local visibility = BuildRuntimeVisibility(frame, spec)
  if ShouldForcePreview(frame) then
    -- Preview must not stay force-shown when combat starts. The secure driver
    -- falls back to normal runtime visibility in combat without Lua work.
    return "[nocombat] show; " .. visibility
  end
  return visibility
end

local RegisterUnitWatch = _G.RegisterUnitWatch
local UnregisterUnitWatch = _G.UnregisterUnitWatch
local UnitWatchRegistered = _G.UnitWatchRegistered

-- A frame with no load conditions resolves to "[@unit,exists] show; hide",
-- which is exactly what RegisterUnitWatch does natively -- and far cheaper.
-- Stacking a RegisterStateDriver("visibility") on top makes the secure
-- macro-conditional engine re-evaluate that expression on state changes
-- (including target changes for @target-relative frames). That secure
-- evaluation is billed to MSUF and was the per-click profiler spike that no
-- Lua probe could see.
-- So: only install the state driver when there is REAL conditional work;
-- otherwise hand visibility to RegisterUnitWatch.
local function VisibilityNeedsDriver(spec)
  local load = spec and spec.load
  if load and load.active == true then
    return true
  end
  if load and load.hideInInstance == true then
    return true
  end
  if load and load.hideInHousing == true then
    return true
  end
  return false
end

-- Existence-only visibility is structural frame ownership, not an active
-- LoadConditions feature. Factory/SecureGroupHeader keep the native unit watch
-- alive, while this element enters Core routing only for real conditional
-- visibility or a forced unit-frame preview.
function LoadConditions.IsEnabled(frame, spec)
  return VisibilityNeedsDriver(spec) or ShouldForcePreview(frame)
end

local function RegisterVisibility(frame, spec)
  if UnitWatchRegistered then
    frame._msufUnitWatched = UnitWatchRegistered(frame) == true and true or nil
  end
  -- Existence-only visibility: use the lightweight unit watch, never a secure
  -- state driver. Tear down any driver left from a previous conditional config.
  if not VisibilityNeedsDriver(spec) and not ShouldForcePreview(frame) and RegisterUnitWatch then
    if InCombatLockdown and InCombatLockdown() then
      -- Combat: don't touch secure registration. If a driver is currently
      -- installed we must defer the swap-out; otherwise the unit watch from
      -- spawn already covers us and there is nothing to do.
      if frame._msufVisibilityExpr ~= nil then
        UF.MarkDirty(frame.MSUFUnitKey)
        if UF.Factory and UF.Factory.EnsureDeferredDriver then
          UF.Factory.EnsureDeferredDriver()
        end
        return false
      end
    elseif frame._msufVisibilityExpr ~= nil then
      if UnregisterStateDriver then
        UnregisterStateDriver(frame, "visibility")
      end
      frame._msufVisibilityExpr = nil
    end
    if frame._msufUnitWatched ~= true then
      RegisterUnitWatch(frame)
      frame._msufUnitWatched = true
    end
    frame._msufVisibilityManaged = nil
    return true
  end

  local visibility = BuildVisibility(frame, spec)
  frame._msufVisibilityManaged = true
  if RegisterStateDriver then
    if frame._msufVisibilityExpr ~= visibility then
      if InCombatLockdown and InCombatLockdown() then
        UF.MarkDirty(frame.MSUFUnitKey)
        if UF.Factory and UF.Factory.EnsureDeferredDriver then
          UF.Factory.EnsureDeferredDriver()
        end
        return false
      end
      -- Swapping from unit-watch to driver: the watch and the driver both
      -- manage visibility, so drop the watch first to avoid double control.
      if frame._msufUnitWatched == true then
        UnregisterUnitWatch(frame)
        frame._msufUnitWatched = nil
      end
      RegisterStateDriver(frame, "visibility", visibility)
      frame._msufVisibilityExpr = visibility
    end
    return true
  end

  local show = visibility == "show"
  if visibility ~= "hide" and SecureCmdOptionParse then
    show = SecureCmdOptionParse(visibility) == "show"
  elseif visibility ~= "hide" then
    show = UnitExistsPlain(frame.MSUFUnitKey)
  end
  if frame._msufShown ~= show then
    frame:SetShown(show)
    frame._msufShown = show
  end
  return true
end

-- "Hide in instance" and "Hide in housing" resolve into a constant "hide"
-- while inside, so the frame is hidden, and its events are suspended by the
-- core, exactly when leaving has to bring it back. One shared EventBus
-- subscription, which no frame's visibility can silence, rebuilds those
-- drivers on every zone and housing-plot boundary instead of frame routes.
local ZONE_EVENT_KEY = "MSUF_UF_LOAD_CONDITIONS_ZONE"
local ZONE_EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }
-- Walking onto or off a plot changes C_Housing.IsInsideHouseOrPlot without a
-- zone change; Blizzard_HousingControls follows these two events for it.
local HOUSING_PLOT_EVENTS = { "HOUSE_PLOT_ENTERED", "HOUSE_PLOT_EXITED" }
local zoneFrames = {}
local zoneEventsRegistered = false

local function OnZoneBoundary()
  for frame in next, zoneFrames do
    RegisterVisibility(frame, frame.MSUFSpec)
  end
end

local function SetZoneEvents(list, wanted, register, unregister)
  local client = MSUF.Client
  local supports = client and client.SupportsEvent
  for i = 1, #list do
    local event = list[i]
    if not wanted then
      unregister(event, ZONE_EVENT_KEY)
    elseif type(supports) ~= "function" or supports(event) == true then
      register(event, ZONE_EVENT_KEY, OnZoneBoundary)
    end
  end
end

local function SyncZoneFrame(frame, spec)
  local load = spec and spec.enabled ~= false and spec.load
  if frame then
    zoneFrames[frame] = load and (load.hideInInstance == true or load.hideInHousing == true) or nil
  end
  local wanted = next(zoneFrames) ~= nil
  if wanted == zoneEventsRegistered then return end
  local register, unregister = _G.MSUF_EventBus_Register, _G.MSUF_EventBus_Unregister
  SetZoneEvents(ZONE_EVENTS, wanted, register, unregister)
  if type(C_Housing and C_Housing.IsInsideHouseOrPlot) == "function" then
    SetZoneEvents(HOUSING_PLOT_EVENTS, wanted, register, unregister)
  end
  zoneEventsRegistered = wanted
end

function LoadConditions.GetEvents(frame, spec)
  return HealthVisibilityEnabled(frame, spec) and HEALTH_EVENTS or EMPTY_EVENTS
end

LoadConditions.UpdateHealthVisibility = RefreshHealthAlpha
function LoadConditions.SelectEventUpdate(frame, spec, event, update)
  if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then return RefreshHealthAlpha end
  return update
end

function LoadConditions.GetUnitlessEvents(frame, spec)
  local load = spec and spec.load
  if not load or load.active ~= true then
    return EMPTY_EVENTS
  end
  if not RegisterStateDriver then
    return FALLBACK_EVENTS
  end
  return load.unitlessEvents or EMPTY_EVENTS
end

function LoadConditions.Apply(frame, spec)
  ConfigureHealthAlpha(frame, spec)
  RegisterVisibility(frame, spec)
  SyncZoneFrame(frame, spec)
end

function LoadConditions.Update(frame, event)
  RefreshHealthAlpha(frame)
  if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then return end
  if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
    -- Instance/housing checks are resolved into the visibility expression, so
    -- these zone boundaries must rebuild it. RegisterVisibility already defers
    -- protected changes when combat lockdown makes that necessary.
    return RegisterVisibility(frame, frame and frame.MSUFSpec)
  end
  -- Identity refreshes (target/focus swap) call this on every unit change, but a
  -- unit swap NEVER changes the visibility expression: BuildRuntimeVisibility
  -- depends only on the spec (load rules + the frame's fixed unit token like
  -- "target"), not on which GUID is currently targeted. The secure state driver
  -- was already registered at Apply and re-evaluates itself natively in the
  -- engine on the conditions that matter (combat/resting/instance/exists). So
  -- re-running RegisterVisibility here just rebuilds an identical string and
  -- throws it away -- pure per-swap waste (this was a large chunk of the
  -- target-swap cost). Skip once the driver/watch is installed; a real config
  -- change goes through LoadConditions.Apply / UF.RefreshVisibilityDrivers,
  -- which call RegisterVisibility directly and are not gated by this.
  if frame and (frame._msufVisibilityExpr ~= nil or frame._msufUnitWatched == true) then
    return
  end
  RegisterVisibility(frame, frame and frame.MSUFSpec)
end

function LoadConditions.Disable(frame)
  if not frame then
    return
  end
  SyncZoneFrame(frame, nil)
  ClearHealthAlpha(frame)
  if UnregisterStateDriver and InCombatLockdown and InCombatLockdown() then
    UF.MarkDirty(frame.MSUFUnitKey)
    if UF.Factory and UF.Factory.EnsureDeferredDriver then
      UF.Factory.EnsureDeferredDriver()
    end
    return false
  end
  frame._msufVisibilityManaged = nil
  frame._msufVisibilityExpr = nil
  if UnregisterStateDriver then
    UnregisterStateDriver(frame, "visibility")
  end
  -- A conditional driver replaces RegisterUnitWatch while active. Restore the
  -- native existence owner immediately when the last condition is removed;
  -- targeted RefreshElements calls do not pass through Factory's post-apply
  -- fallback that normally performs this hand-off for fresh single frames.
  if RegisterUnitWatch and not (frame.MSUFSpec and frame.MSUFSpec.enabled == false) then
    local watched = UnitWatchRegistered and UnitWatchRegistered(frame) == true
    if not watched then
      RegisterUnitWatch(frame)
    end
    frame._msufUnitWatched = true
  end
  return true
end

-- Reuse Core's existing identity/OnShow plan so a target, focus, pet, or boss
-- replacement refreshes its HP gate even without a UNIT_HEALTH notification.
LoadConditions.Routes = { basic = true, identity = true }
UF.RegisterElement("LoadConditions", LoadConditions, { identity = true })

function UF.RefreshVisibilityDrivers(unit)
  return UF.RefreshElements(unit, { "LoadConditions" }, "MSUF_LOAD_CONDITIONS")
end

local function MSUF_RefreshAllUnitVisibilityDrivers()
  return UF.RefreshVisibilityDrivers(nil)
end
ExportPublic("MSUF_RefreshAllUnitVisibilityDrivers", MSUF_RefreshAllUnitVisibilityDrivers)

if UF.RouteCompiler then
  local Compiler = UF.RouteCompiler
  local RouteCache = setmetatable({ healthVisibility = {} }, { __index = Compiler.Cache })
  local SharedSingleRoute = Compiler.SharedSingleRoute
  local HEALTH_EVENTS = { UNIT_HEALTH = true, UNIT_MAXHEALTH = true, UNIT_CONNECTION = true,
    PARTY_MEMBER_ENABLE = true, PARTY_MEMBER_DISABLE = true }
  local function Compile(frame, event, list)
    -- Strip the optional rendering gate before compiling the existing optimized
    -- health route. No extra dispatch context or option check when disabled.
    local loadConditions = UF.elements.LoadConditions
    local gate = HEALTH_EVENTS[event] and loadConditions and loadConditions.UpdateHealthVisibility
    if gate then
      for i = 1, #list, 2 do
        if list[i] == gate then
          local remaining = {}
          for j = 1, #list, 2 do
            if j ~= i then
              remaining[#remaining + 1] = list[j]
              remaining[#remaining + 1] = list[j + 1]
            end
          end
          if #remaining == 0 then return SharedSingleRoute(gate, false, nil) end
          local base = Compiler.CompileEventPath(frame, event, remaining)
          local route = RouteCache.healthVisibility[base]
          if not route then
            route = function(self, ev, unit, ...)
              base(self, ev, unit, ...)
              gate(self)
            end
            if RouteCache.sharedRoutes[base] then RouteCache.healthVisibility[base] = route end
          end
          if RouteCache.sharedRoutes[base] then RouteCache.sharedRoutes[route] = true end
          return route
        end
      end
    end
  end
  UF.RegisterRoute("visibility", Compile, 10, HEALTH_EVENTS)
end
