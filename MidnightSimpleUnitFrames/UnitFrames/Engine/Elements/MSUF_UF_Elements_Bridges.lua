local _, MSUF = ...

local UF = MSUF.UF
local type = type
local ExportPublic = MSUF.ExportPublic
local PublicGlobals = MSUF.PublicGlobals
local ScheduleOnce = MSUF.Require("MSUF_ScheduleOnce", "UnitFrames/Engine/Elements/MSUF_UF_Elements_Bridges.lua")

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
  ScheduleOnce(tokenName, flush)
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
    HideFrame(MSUF.Castbars.Frames.Get("player"))
  elseif unit == "target" then
    HideFrame(MSUF.Castbars.Frames.Get("target"))
  elseif unit == "focus" then
    HideFrame(MSUF.Castbars.Frames.Get("focus"))
  elseif unit == "boss" or unit == "arena" then
    -- Every built bar of the pool (Castbars/MSUF_CastbarPools.lua).
    local pools = MSUF.Castbars and MSUF.Castbars.Pools
    local pool = pools and pools.kinds and pools.kinds[unit]
    if pool then
      for i = 1, pool.maxFrames do
        HideFrame(pool.Bar(i))
      end
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
  HideFrame(MSUF.Optional("MSUF_ClassPowerContainer"))
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

-- Identity payload and lifecycle adapters keep owner-specific contracts out
-- of the generic dispatcher. The cached plans and closures are unchanged.
if UF.RouteCompiler then
  local Compiler = UF.RouteCompiler
  local RouteCache, Intern = Compiler.Cache, Compiler.Intern
  local NIL_ROUTE_KEY = Compiler.NilKey
  local IsRegisteredElementFunction = Compiler.IsRegisteredFunction
  local GetUpdateKey = Compiler.GetUpdateKey
  local ElementUpdateFunction = Compiler.ElementUpdateFunction
  local BeginFrameEvent, EndFrameEvent = Compiler.BeginFrameEvent, Compiler.EndFrameEvent
  local CompileGroupLifecyclePlan
  local function LifecycleCachedHealth(frame, unit)
    local hpBar = frame.hpBar
    local hp = hpBar and hpBar._msufHealthValueUnit == unit and hpBar._msufHealthValue or nil
    local hpMax = hpBar and hpBar._msufHealthMaxUnit == unit and hpBar._msufHealthMax or nil
    if issecretvalue(hp) == true then hp = nil end
    if issecretvalue(hpMax) == true then hpMax = nil end
    return hp, hpMax
  end

  local function BuildLifecycleFullPath(healthPath, powerUpdate, powerTextUpdate,
      nameUpdate, portraitUpdate, statusUpdate, rangeUpdate, visualsUpdate,
      bordersUpdate, cornerUpdate)
    return function(frame, event)
      local unit = frame.MSUFUnitKey
      frame._msufGroupStateRefresh = true
      -- Keep open only the dispatch this refresh starts (the health route or the
      -- Begin below takes the next token), so every follower shares its snapshot.
      frame._msufDeferDispatchEnd = (frame._msufDispatchToken or 0) + 1
      if healthPath then healthPath(frame, event, nil) else BeginFrameEvent(frame, event) end

      local power, powerMax, powerType, powerToken, powerMetaChanged
      if powerUpdate then
        power, powerMax, powerType, powerToken, powerMetaChanged = powerUpdate(frame, event, unit)
      end
      if powerTextUpdate then
        powerTextUpdate(frame, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
      end
      if nameUpdate then nameUpdate(frame, event, unit) end
      if portraitUpdate then portraitUpdate(frame, event, unit) end

      local hp, hpMax = LifecycleCachedHealth(frame, unit)
      if statusUpdate then statusUpdate(frame, event, unit, hp) end
      if rangeUpdate then rangeUpdate(frame, event, unit) end
      if visualsUpdate then visualsUpdate(frame, event, unit, hp, hpMax) end
      if bordersUpdate then bordersUpdate(frame, event, unit) end
      if cornerUpdate then cornerUpdate(frame, event, unit) end

      frame._msufDeferDispatchEnd = nil
      EndFrameEvent(frame)
      frame._msufGroupStateRefresh = nil
    end
  end

  local function BuildLifecycleGlobalPath(powerUpdate, powerTextUpdate,
      namePresenceUpdate, statusUpdate, rangeUpdate, visualsUpdate)
    return function(frame, event)
      local unit = frame.MSUFUnitKey
      BeginFrameEvent(frame, event)

      -- Blizzard treats PARTY_MEMBER_ENABLE/DISABLE as a group-wide alternate
      -- power and presence invalidation. These are the intentionally global
      -- followers; name/portrait and health stay target-only. If the lifecycle
      -- unit cannot be resolved safely, the driver selects fullPath for every
      -- frame instead of entering this minimal path.
      local power, powerMax, powerType, powerToken, powerMetaChanged
      if powerUpdate then
        power, powerMax, powerType, powerToken, powerMetaChanged = powerUpdate(frame, event, unit)
      end
      if powerTextUpdate then
        powerTextUpdate(frame, event, unit, power, powerMax, powerType, powerToken, powerMetaChanged)
      end
      if namePresenceUpdate then namePresenceUpdate(frame, event, unit) end

      local hp, hpMax = LifecycleCachedHealth(frame, unit)
      if statusUpdate then statusUpdate(frame, event, unit, hp) end
      if rangeUpdate then rangeUpdate(frame, event, unit) end
      if visualsUpdate then visualsUpdate(frame, event, unit, hp, hpMax) end

      EndFrameEvent(frame)
    end
  end

  local function NewGroupLifecyclePlan(healthPath, powerUpdate,
      powerTextUpdate, nameUpdate, namePresenceUpdate, portraitUpdate, statusUpdate,
      rangeUpdate, visualsUpdate, bordersUpdate, cornerUpdate)
    return {
      fullPath = BuildLifecycleFullPath(healthPath, powerUpdate, powerTextUpdate,
        nameUpdate, portraitUpdate, statusUpdate, rangeUpdate, visualsUpdate,
        bordersUpdate, cornerUpdate),
      globalPath = BuildLifecycleGlobalPath(powerUpdate,
        powerTextUpdate, namePresenceUpdate, statusUpdate, rangeUpdate, visualsUpdate),
    }
  end

  local function InternLifecycleNode(node, value)
    local key = value or NIL_ROUTE_KEY
    local nextNode = node[key]
    if not nextNode then
      nextNode = {}
      node[key] = nextNode
    end
    return nextNode
  end

  local function InternGroupLifecyclePlan(healthPath, powerUpdate,
      powerTextUpdate, nameUpdate, namePresenceUpdate, portraitUpdate, statusUpdate,
      rangeUpdate, visualsUpdate, bordersUpdate, cornerUpdate)
    local shared = (not healthPath or RouteCache.sharedRoutes[healthPath] == true)
    shared = shared
      and (not powerUpdate or IsRegisteredElementFunction(powerUpdate))
      and (not powerTextUpdate or IsRegisteredElementFunction(powerTextUpdate))
      and (not nameUpdate or IsRegisteredElementFunction(nameUpdate))
      and (not namePresenceUpdate or IsRegisteredElementFunction(namePresenceUpdate))
      and (not portraitUpdate or IsRegisteredElementFunction(portraitUpdate))
      and (not statusUpdate or IsRegisteredElementFunction(statusUpdate))
      and (not rangeUpdate or IsRegisteredElementFunction(rangeUpdate))
      and (not visualsUpdate or IsRegisteredElementFunction(visualsUpdate))
      and (not bordersUpdate or IsRegisteredElementFunction(bordersUpdate))
      and (not cornerUpdate or IsRegisteredElementFunction(cornerUpdate))
    if not shared then
      return NewGroupLifecyclePlan(healthPath, powerUpdate,
        powerTextUpdate, nameUpdate, namePresenceUpdate, portraitUpdate, statusUpdate,
        rangeUpdate, visualsUpdate, bordersUpdate, cornerUpdate)
    end

    local node = InternLifecycleNode(Intern.groupLifecyclePlans, healthPath)
    node = InternLifecycleNode(node, powerUpdate)
    node = InternLifecycleNode(node, powerTextUpdate)
    node = InternLifecycleNode(node, nameUpdate)
    node = InternLifecycleNode(node, namePresenceUpdate)
    node = InternLifecycleNode(node, portraitUpdate)
    node = InternLifecycleNode(node, statusUpdate)
    node = InternLifecycleNode(node, rangeUpdate)
    node = InternLifecycleNode(node, visualsUpdate)
    node = InternLifecycleNode(node, bordersUpdate)
    node = InternLifecycleNode(node, cornerUpdate)
    if not node.plan then
      node.plan = NewGroupLifecyclePlan(healthPath, powerUpdate,
        powerTextUpdate, nameUpdate, namePresenceUpdate, portraitUpdate, statusUpdate,
        rangeUpdate, visualsUpdate, bordersUpdate, cornerUpdate)
    end
    return node.plan
  end

  local function ActiveLifecycleUpdate(frame, name)
    local active = frame and frame._msufActiveElements
    if not (active and active[name] == true) then return nil end
    local key = GetUpdateKey(name)
    return key and frame[key] or nil
  end

  CompileGroupLifecyclePlan = function(frame)
    if not (frame and frame._msufCoreScope == "group") then
      if frame then frame._msufGroupLifecyclePlan = nil end
      return nil
    end
    local healthPath = frame.PARTY_MEMBER_ENABLE
    local nameUpdate = ActiveLifecycleUpdate(frame, "NameText")
    local text = frame.MSUFSpec and frame.MSUFSpec.text
    local namePresenceUpdate = text and text.hideNameOnDeadOffline == true and nameUpdate or nil
    local plan = InternGroupLifecyclePlan(
      healthPath,
      ActiveLifecycleUpdate(frame, "Power"),
      ActiveLifecycleUpdate(frame, "PowerText"),
      nameUpdate,
      namePresenceUpdate,
      ActiveLifecycleUpdate(frame, "Portrait"),
      ActiveLifecycleUpdate(frame, "GroupStatusRuntime"),
      ActiveLifecycleUpdate(frame, "GroupRangeFade"),
      ActiveLifecycleUpdate(frame, "GroupVisuals"),
      ActiveLifecycleUpdate(frame, "Borders"),
      ActiveLifecycleUpdate(frame, "GroupCornerIndicators")
    )
    frame._msufGroupLifecyclePlan = plan
    return plan
  end

  local function RefreshIdentityHealthBackground(frame)
    local active = frame and frame._msufActiveElements
    if not (active and active.Health == true) then return false end
    local health = UF.elements and UF.elements.Health
    local refresh = health and health.UpdateIdentityBackground
    if refresh == nil then return false end
    return refresh(frame) == true
  end

  local IDENTITY_STEP_NORMAL = 0
  local IDENTITY_STEP_HEALTH_TEXT = 1
  local IDENTITY_STEP_POWER_TEXT = 2
  local IDENTITY_STEP_PREDICTION = 3

  -- Identity bars run before the element sequence. Forward their ephemeral
  -- values to the matching text elements so restricted/secret payloads do not
  -- need a second native read. The values stay on the Lua stack and are never
  -- retained on the frame. Every other element keeps its original three-arg
  -- contract and the compiled elementOrder remains unchanged.
  local function CompileIdentityRuntimePath(list, labels, count)
    if not count or count <= 0 then return nil end
    local kinds = {}
    local inlineToTScheduled = false
    for i = 1, count do
      local label = labels[i]
      if label == "HealthText" then
        kinds[i] = IDENTITY_STEP_HEALTH_TEXT
      elseif label == "PowerText" then
        kinds[i] = IDENTITY_STEP_POWER_TEXT
      elseif label == "Prediction" then
        kinds[i] = IDENTITY_STEP_PREDICTION
      else
        kinds[i] = IDENTITY_STEP_NORMAL
      end
      if label == "InlineToT" then
        inlineToTScheduled = true
      end
    end

    return function(frame, event, unit,
        hp, hpMax, healthPercentReady,
        power, powerMax, powerType, powerToken, powerMetaChanged)
      -- NameText color updates normally keep InlineToT in sync. Identity plans
      -- already contain InlineToT as their own step, so mark the batch and let
      -- that one authoritative step do the work instead of updating it twice.
      if inlineToTScheduled then
        frame._msufIdentityInlineToTScheduled = true
      end
      for i = 1, count do
        local update = list[i]
        local kind = kinds[i]
        if kind == IDENTITY_STEP_HEALTH_TEXT then
          if healthPercentReady == true then
            -- Match BuildHealthRoute: the Health element already seeded the
            -- dispatch-percent slot consumed by HealthText.
            update(frame, event, unit, nil, nil)
          else
            update(frame, event, unit, hp, hpMax)
          end
        elseif kind == IDENTITY_STEP_POWER_TEXT then
          update(frame, event, unit,
            power, powerMax, powerType, powerToken, powerMetaChanged)
        elseif kind == IDENTITY_STEP_PREDICTION then
          if healthPercentReady == true then
            update(frame, event, unit)
          else
            update(frame, event, unit, hp, hpMax)
          end
        else
          update(frame, event, unit)
        end
      end
      if inlineToTScheduled then
        frame._msufIdentityInlineToTScheduled = nil
      end
    end
  end

  local function CompileIdentityBarPath(frame)
    local active = frame and frame._msufActiveElements
    if not active then return nil end
    local health = active.Health == true and ElementUpdateFunction(frame, "Health") or nil
    local power = active.Power == true and ElementUpdateFunction(frame, "Power") or nil
    if not (health or power) then return nil end

    local shared = (not health or IsRegisteredElementFunction(health))
      and (not power or IsRegisteredElementFunction(power))
    local byPower, key
    if shared then
      local healthKey = health or NIL_ROUTE_KEY
      byPower = Intern.identityBarPaths[healthKey]
      if not byPower then
        byPower = {}
        Intern.identityBarPaths[healthKey] = byPower
      end
      key = power or NIL_ROUTE_KEY
      local path = byPower[key]
      if path then return path end
    end

    -- Always wrap, including health-only and power-only plans, so every
    -- archetype returns the same fixed tuple:
    -- hp, hpMax, healthPercentReady, power, powerMax, type, token, metaChanged.
    local path = function(self, event, unit)
      local hp, hpMax, healthPercentReady
      if health then
        hp, hpMax, healthPercentReady = health(self, event, unit)
      end
      local powerValue, powerMax, powerType, powerToken, powerMetaChanged
      if power then
        powerValue, powerMax, powerType, powerToken, powerMetaChanged = power(self, event, unit)
      end
      return hp, hpMax, healthPercentReady,
        powerValue, powerMax, powerType, powerToken, powerMetaChanged
    end
    if shared then byPower[key] = path end
    return path
  end

  Compiler.SetLifecycleCompiler(CompileGroupLifecyclePlan)
  Compiler.RefreshIdentitySurface = RefreshIdentityHealthBackground
  Compiler.CompileIdentityPath = CompileIdentityRuntimePath
  Compiler.CompileIdentityBars = CompileIdentityBarPath
  Compiler.OnUnitChanged = function(frame, oldUnit, newUnit)
    local A3 = MSUF and MSUF.MSUF_Auras3
    local active = frame._msufActiveElements
    if active and active.Auras == true and A3 and type(A3.OnFrameUnitChanged) == "function" then
      -- One rebind re-registers every native owner of this frame. Batch the
      -- identity event topology the way GF.ScanHeader does so the shared driver
      -- and the four-token shards resync once per rebind, not once per owner.
      local batchTopology = type(A3.BeginTopologyBatch) == "function"
        and type(A3.EndTopologyBatch) == "function"
      if batchTopology then A3.BeginTopologyBatch() end
      A3.OnFrameUnitChanged(frame, oldUnit, newUnit)
      if batchTopology then A3.EndTopologyBatch() end
    end
  end
  Compiler.AfterApply = function(frame)
    -- Menu dispel-overlay preview. The stand-in tint is MSUF-drawn and therefore
    -- outside the element/dirty-mask system, so re-stamp it here: this is the one
    -- funnel both full spec applies (UF.ApplySpec) and targeted element refreshes
    -- (UF.ApplyElementsToFrame, which is how unit-frame aura settings apply) pass
    -- through. A single boolean read whenever no preview is active.
    -- Both preview painters belong to the aura preview, which loads after the core.
    if PublicGlobals.MSUF_DispelOverlayPreviewMode == true then
      MSUF.Require("MSUF_ApplyDispelOverlayPreviewToFrame", "UnitFrames/Engine/Elements/MSUF_UF_Elements_Bridges.lua")(frame)
    end
    if PublicGlobals.MSUF_DispelSymbolPreviewMode == true then
      MSUF.Require("MSUF_ApplyDispelSymbolPreviewToFrame", "UnitFrames/Engine/Elements/MSUF_UF_Elements_Bridges.lua")(frame)
    end
  end
end
