_G = _G or _ENV

local function Check(value, message)
  if not value then error(message or "check failed", 2) end
end

local Object = {}
Object.__index = Object

local function NewObject(parent)
  return setmetatable({
    parent = parent,
    scripts = {},
    hooks = {},
    unitEvents = {},
    genericEvents = {},
    visible = true,
    shown = true,
    frameLevel = 1,
    frameStrata = "MEDIUM",
    alpha = 1,
  }, Object)
end

function Object:SetScript(kind, callback) self.scripts[kind] = callback end
function Object:GetScript(kind) return self.scripts[kind] end
function Object:HookScript(kind, callback)
  local hooks = self.hooks[kind]
  if not hooks then hooks = {}; self.hooks[kind] = hooks end
  hooks[#hooks + 1] = callback
end
function Object:RunScript(kind, ...)
  local script = self.scripts[kind]
  if script then script(self, ...) end
  local hooks = self.hooks[kind]
  if hooks then
    for i = 1, #hooks do hooks[i](self, ...) end
  end
end
function Object:Fire(event, unit, ...)
  local script = self.scripts.OnEvent
  if script then script(self, event, unit, ...) end
end
function Object:IsVisible() return self.visible == true end
function Object:SetShown(shown)
  shown = shown == true
  if self.visible == shown then self.shown = shown; return end
  self.visible, self.shown = shown, shown
  self:RunScript(shown and "OnShow" or "OnHide")
end
function Object:Show() self:SetShown(true) end
function Object:Hide() self:SetShown(false) end
function Object:RegisterEvent(event) self.genericEvents[event] = true end
function Object:RegisterUnitEvent(event, ...)
  local units = {}
  for i = 1, select("#", ...) do units[i] = select(i, ...) end
  self.unitEvents[event] = units
end
function Object:UnregisterEvent(event)
  self.genericEvents[event] = nil
  self.unitEvents[event] = nil
end
function Object:UnregisterAllEvents()
  self.genericEvents = {}
  self.unitEvents = {}
end
function Object:SetAllPoints() end
function Object:EnableMouse() end
function Object:SetFrameLevel(level) self.frameLevel = level end
function Object:GetFrameLevel() return self.frameLevel end
function Object:SetFrameStrata(strata) self.frameStrata = strata end
function Object:GetFrameStrata() return self.frameStrata end
function Object:GetParent() return self.parent end
function Object:CreateTexture()
  local texture = NewObject(self)
  self.textures = self.textures or {}
  self.textures[#self.textures + 1] = texture
  return texture
end
function Object:SetDrawLayer(layer, subLayer) self.drawLayer, self.subLayer = layer, subLayer end
function Object:SetSize(width, height) self.width, self.height = width, height end
function Object:SetWidth(width) self.width = width end
function Object:SetHeight(height) self.height = height end
function Object:ClearAllPoints() self.points = {} end
function Object:SetPoint(...)
  self.points = self.points or {}
  self.points[#self.points + 1] = { ... }
end
function Object:SetColorTexture(...) self.colorTexture = { ... } end
function Object:SetVertexColor(...) self.vertexColor = { ... } end
function Object:SetAlpha(alpha) self.alpha = alpha end
function Object:GetAlpha() return self.alpha end
function Object:SetAlphaFromBoolean(value, trueAlpha, falseAlpha)
  self.alpha = (value == true or value == 1) and trueAlpha or falseAlpha
end

local threatByUnit = {}
local combatByUnit = {}
local threatQueries = {}
local existsQueries = {}
local roleQueries = {}
local inInstance = false
local stateDriverCalls = {}
local stateDriverUnregisterCalls = 0
local unitWatchRegisterCalls = 0
local unitWatchUnregisterCalls = 0

local createdFrames = {}
_G.CreateFrame = function(_, _, parent)
  local frame = NewObject(parent)
  createdFrames[#createdFrames + 1] = frame
  return frame
end
_G.InCombatLockdown = function() return false end
_G.UnitExists = function(unit)
  existsQueries[unit] = (existsQueries[unit] or 0) + 1
  return true
end
_G.UnitIsConnected = function() return true end
_G.UnitIsDead = function() return false end
_G.UnitIsDeadOrGhost = function() return false end
_G.UnitIsUnit = function(a, b) return a == b end
_G.UnitAffectingCombat = function(unit) return combatByUnit[unit] == true end
_G.UnitGroupRolesAssigned = function(unit)
  roleQueries[unit] = (roleQueries[unit] or 0) + 1
  return "DAMAGER"
end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.UnitReaction = function() return 5 end
_G.SetPortraitTexture = function() end
_G.issecretvalue = function() return false end
_G.IsInInstance = function() return inInstance, inInstance and "party" or "none" end
_G.RegisterStateDriver = function(frame, state, expression)
  stateDriverCalls[#stateDriverCalls + 1] = {
    frame = frame,
    state = state,
    expression = expression,
  }
end
_G.UnregisterStateDriver = function()
  stateDriverUnregisterCalls = stateDriverUnregisterCalls + 1
end
_G.RegisterUnitWatch = function(frame)
  unitWatchRegisterCalls = unitWatchRegisterCalls + 1
  frame.unitWatchRegistered = true
end
_G.UnregisterUnitWatch = function(frame)
  unitWatchUnregisterCalls = unitWatchUnregisterCalls + 1
  frame.unitWatchRegistered = nil
end
_G.UnitWatchRegistered = function(frame) return frame.unitWatchRegistered == true end
_G.UnitThreatSituation = function(unit, mobUnit)
  local key
  if mobUnit ~= nil then
    Check(unit == "player", "hostile threat query must use player as the feedback unit")
    key = unit .. ">" .. mobUnit
    threatQueries[key] = (threatQueries[key] or 0) + 1
    return threatByUnit[mobUnit]
  end
  key = unit
  threatQueries[key] = (threatQueries[key] or 0) + 1
  return threatByUnit[unit]
end

local MSUF = {
  UF = {},
  GF = {},
  Secrets = {
    IsNil = function(value) return value == nil end,
    NotSecret = function() return true end,
    UnitMissing = function() return false end,
  },
}
function MSUF.ExportPublic(name, value)
  MSUF[name] = value
  return value
end
_G.MSUF_NS = MSUF

local engineRoot = "MidnightSimpleUnitFrames/UnitFrames/Engine/"
local function LoadEngine(relativePath)
  local path = engineRoot .. relativePath
  local handle = io.open(path, "r")
  if handle then
    handle:close()
  else
    path = "UnitFrames/Engine/" .. relativePath
  end
  local chunk, err = loadfile(path)
  Check(chunk, err)
  return chunk("MidnightSimpleUnitFrames", MSUF)
end

LoadEngine("MSUF_UF_Metadata.lua")
LoadEngine("MSUF_UF_Core.lua")
LoadEngine("Elements/MSUF_UF_Visuals_Common.lua")
LoadEngine("Elements/MSUF_UF_Elements_Borders.lua")
LoadEngine("Elements/MSUF_UF_Elements_LoadConditions.lua")
LoadEngine("Group/MSUF_UF_Group_Indicators.lua")

local UF = assert(MSUF.UF)

local function NewUnitFrame(unit)
  local frame = NewObject(nil)
  frame.unit = unit
  frame.unitKey = unit
  frame.hpBar = NewObject(frame)
  frame.Health = frame.hpBar
  return frame
end

local function UnitRoute(frame, event)
  local units = frame.unitEvents[event]
  return units and units[1] or nil
end

local function RuntimeHasLabel(frame, wanted)
  local labels = frame and frame._msufRuntimeAllLabels
  for i = 1, labels and #labels or 0 do
    if labels[i] == wanted then return true end
  end
  return false
end

local function AggroBorderConfig()
  return {
    enabled = false,
    thickness = 1,
    aggro = true,
    aggroMode = "ALL",
    aggroR = 1,
    aggroG = 0.55,
    aggroB = 0,
    highlightThickness = 3,
  }
end

local target = NewUnitFrame("target")
local targetSpec = {
  enabled = true,
  unit = "target",
  key = "target",
  scope = "single",
  border = AggroBorderConfig(),
}
UF.ApplySpec(target, targetSpec, nil, { Borders = true })

Check(UnitRoute(target, "UNIT_THREAT_SITUATION_UPDATE") == "target",
  "target threat-situation route was not registered as a unit event")
Check(UnitRoute(target, "UNIT_THREAT_LIST_UPDATE") == "target",
  "target threat-list route was not registered as a unit event")
Check(target.genericEvents.UNIT_THREAT_SITUATION_UPDATE == nil
    and target.genericEvents.UNIT_THREAT_LIST_UPDATE == nil,
  "target threat routes must stay unit-filtered")
Check(target._msufBorderShown == false, "target aggro border must start hidden without threat")

threatByUnit.target = 3
target:Fire("UNIT_THREAT_LIST_UPDATE", "target")
Check(target._msufBorderShown == true, "target aggro border did not react to threat-list gain")
threatByUnit.target = 0
target:Fire("UNIT_THREAT_SITUATION_UPDATE", "target")
Check(target._msufBorderShown == false, "target aggro border did not clear status zero")
threatByUnit.target = 3
target:Fire("UNIT_THREAT_SITUATION_UPDATE", "target")
Check(target._msufBorderShown == true, "target aggro border did not react to threat-situation gain")
threatByUnit.target = nil
target:Fire("UNIT_THREAT_LIST_UPDATE", "target")
Check(target._msufBorderShown == false, "target aggro border did not clear nil threat")
Check((threatQueries["player>target"] or 0) >= 5,
  "target border did not use UnitThreatSituation(player, target)")

local player = NewUnitFrame("player")
local playerSpec = {
  enabled = true,
  unit = "player",
  key = "player",
  scope = "single",
  border = AggroBorderConfig(),
}
UF.ApplySpec(player, playerSpec, nil, { Borders = true })
Check(player.genericEvents.PLAYER_TARGET_CHANGED == true,
  "player aggro border did not register target-change catch-up")
threatByUnit.target = 3
player:Fire("PLAYER_TARGET_CHANGED")
Check(player._msufBorderShown == true,
  "player aggro border did not react to target-change threat gain")
threatByUnit.target = nil
player:Fire("PLAYER_TARGET_CHANGED")
Check(player._msufBorderShown == false,
  "player aggro border remained stale after target-change threat clear")

local cornerSlot = { category = "aggro", key = "TR", anchor = "TOPRIGHT", x = 0, y = 0 }
local party = NewUnitFrame("party1")
local partySpec = {
  enabled = true,
  unit = "party1",
  key = "party",
  scope = "group",
  border = AggroBorderConfig(),
  cornerIndicators = {
    enabled = true,
    hasWork = true,
    needsThreat = true,
    needsAura = false,
    aggroMode = "NON_TANK",
    aggroR = 1,
    aggroG = 0.55,
    aggroB = 0,
    alpha = 1,
    layer = 7,
    size = 8,
    aggroSlots = { cornerSlot },
    slotMap = { TR = cornerSlot },
  },
}
partySpec.border.aggroMode = "NON_TANK"
UF.ApplySpec(party, partySpec, nil, { Borders = true, GroupCornerIndicators = true })

local corner = assert(party.MSUFGFCornerIndicators and party.MSUFGFCornerIndicators.TR)
for _, event in ipairs({ "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "UNIT_FLAGS" }) do
  Check(UnitRoute(party, event) == "party1", event .. " was not routed to party1")
end
Check(party.genericEvents.PLAYER_REGEN_ENABLED ~= true,
  "group aggro combat-exit catch-up must not register on every frame")
Check(party._msufBorderShown == false and corner.shown == false,
  "party aggro visuals must start hidden")

combatByUnit.party1 = true
threatByUnit.party1 = 1
local partyThreatQueriesBefore = threatQueries.party1 or 0
local partyExistsQueriesBefore = existsQueries.party1 or 0
local partyRoleQueriesBefore = roleQueries.party1 or 0
party:Fire("UNIT_THREAT_LIST_UPDATE", "party1")
Check(party._msufBorderShown == true and corner.shown == true,
  "party aggro visuals did not react to threat-list gain")
Check((threatQueries.party1 or 0) - partyThreatQueriesBefore == 1,
  "border and corner indicator did not share one dispatch-local aggro result")
Check((existsQueries.party1 or 0) - partyExistsQueriesBefore == 1
    and (roleQueries.party1 or 0) - partyRoleQueriesBefore == 1,
  "border and corner indicator repeated group aggro eligibility reads")
threatByUnit.party1 = 0
party:Fire("UNIT_THREAT_SITUATION_UPDATE", "party1")
Check(party._msufBorderShown == false and corner.shown == false,
  "party aggro visuals did not clear status zero")
threatByUnit.party1 = 3
party:Fire("UNIT_THREAT_SITUATION_UPDATE", "party1")
Check(party._msufBorderShown == true and corner.shown == true,
  "party aggro visuals did not react to threat-situation gain")
threatByUnit.party1 = nil
party:Fire("UNIT_THREAT_LIST_UPDATE", "party1")
Check(party._msufBorderShown == false and corner.shown == false,
  "party aggro visuals did not clear nil threat")
Check((threatQueries.party1 or 0) >= 4,
  "party aggro visuals did not use one-argument UnitThreatSituation(party1)")

-- Hidden frames suppress runtime events. OnShow must reseed threat-driven state.
threatByUnit.party1 = 3
party:Fire("UNIT_THREAT_SITUATION_UPDATE", "party1")
Check(party._msufBorderShown == true and corner.shown == true,
  "party setup for hidden-state catch-up failed")
party:Hide()
threatByUnit.party1 = 0
party:Fire("UNIT_THREAT_SITUATION_UPDATE", "party1")
Check(party._msufBorderShown == true and corner.shown == true,
  "hidden party frame unexpectedly consumed a runtime event")
party:Show()
Check(party._msufBorderShown == false and corner.shown == false,
  "OnShow did not clear stale party aggro visuals")

-- Secure group children can be rebound without a spec apply. Rebinding must
-- replace the unit subscriptions and reseed current threat immediately.
combatByUnit.party1 = true
threatByUnit.party1 = 3
party:Fire("UNIT_THREAT_LIST_UPDATE", "party1")
Check(party._msufBorderShown == true and corner.shown == true,
  "party setup for unit rebind catch-up failed")
combatByUnit.party2 = false
threatByUnit.party2 = 0
UF.OnUnitChanged(party, "party1", "party2")
for _, event in ipairs({ "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "UNIT_FLAGS" }) do
  Check(UnitRoute(party, event) == "party2", event .. " was not rebound to party2")
end
Check(party._msufBorderShown == false and corner.shown == false,
  "group unit rebind did not clear stale aggro visuals")

combatByUnit.party2 = true
threatByUnit.party2 = 3
party:Fire("UNIT_THREAT_LIST_UPDATE", "party2")
Check(party._msufBorderShown == true and corner.shown == true,
  "rebound party aggro visuals did not update")
combatByUnit.party2 = false
MSUF.GF.ForEachFrame = function(fn, includeHidden, ...)
  Check(includeHidden == false, "shared corner catch-up must stay visibility-gated")
  return fn(party, party.MSUFUnitKey, "party", ...)
end
Check(MSUF.GF.RefreshCornerThreatState("PLAYER_REGEN_ENABLED") == true,
  "shared group runtime did not visit the active corner threat owner")
Check(corner.shown == false,
  "combat exit did not clear a stale group corner aggro indicator")

-- Default visibility belongs to Blizzard's native UnitWatch, not an active
-- Core element. Single frames arrive here after Factory has registered the
-- watch; secure group children arrive with the header-owned watch already set.
local defaultStateDriverCount = #stateDriverCalls
local defaultUnitWatchRegisterCount = unitWatchRegisterCalls
local defaultUnitWatchUnregisterCount = unitWatchUnregisterCalls
local defaultSingle = NewUnitFrame("target")
_G.RegisterUnitWatch(defaultSingle)
UF.ApplySpec(defaultSingle, {
  enabled = true,
  unit = "target",
  key = "target",
  scope = "single",
  load = { active = false },
}, nil, { LoadConditions = true })
Check(not (defaultSingle._msufActiveElements and defaultSingle._msufActiveElements.LoadConditions),
  "default single frame retained active LoadConditions ownership")
Check(not RuntimeHasLabel(defaultSingle, "LoadConditions"),
  "default single frame retained LoadConditions in its runtime sequence")
Check(defaultSingle.unitWatchRegistered == true,
  "default single frame lost its native UnitWatch")

local defaultGroup = NewUnitFrame("party1")
_G.RegisterUnitWatch(defaultGroup)
UF.ApplySpec(defaultGroup, {
  enabled = true,
  unit = "party1",
  key = "party",
  scope = "group",
  load = { active = false },
}, nil, { LoadConditions = true })
Check(not (defaultGroup._msufActiveElements and defaultGroup._msufActiveElements.LoadConditions),
  "default group frame retained active LoadConditions ownership")
Check(not RuntimeHasLabel(defaultGroup, "LoadConditions"),
  "default group frame retained LoadConditions in its runtime sequence")
Check(defaultGroup.unitWatchRegistered == true,
  "default group frame lost its native UnitWatch")
Check(#stateDriverCalls == defaultStateDriverCount,
  "default visibility registered a secure state driver")
Check(unitWatchRegisterCalls == defaultUnitWatchRegisterCount + 2,
  "default visibility mutated native UnitWatch during Core apply")
Check(unitWatchUnregisterCalls == defaultUnitWatchUnregisterCount,
  "default visibility unregistered native UnitWatch during Core apply")

-- Instance/housing load conditions resolve cold environment state into the
-- secure visibility expression. Zone-boundary events must rebuild that exact
-- expression instead of leaving the previous zone's result cached.
local loadFrame = NewUnitFrame("focus")
local loadSpec = {
  enabled = true,
  unit = "focus",
  key = "focus",
  scope = "single",
  load = {
    active = true,
    hideInInstance = true,
    unitlessEvents = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" },
  },
}
inInstance = false
UF.ApplySpec(loadFrame, loadSpec, nil, { LoadConditions = true })
Check(loadFrame.genericEvents.PLAYER_ENTERING_WORLD == true
    and loadFrame.genericEvents.ZONE_CHANGED_NEW_AREA == true,
  "load-condition zone-boundary routes were not registered")
Check(#stateDriverCalls == 1
    and stateDriverCalls[1].frame == loadFrame
    and stateDriverCalls[1].state == "visibility"
    and stateDriverCalls[1].expression:find("[@focus,exists] show", 1, true),
  "initial load-condition state-driver expression is wrong")

inInstance = true
loadFrame:Fire("PLAYER_ENTERING_WORLD")
Check(#stateDriverCalls == 2 and stateDriverCalls[2].expression == "hide",
  "PLAYER_ENTERING_WORLD did not rebuild the in-instance visibility expression")
inInstance = false
loadFrame:Fire("ZONE_CHANGED_NEW_AREA")
Check(#stateDriverCalls == 3
    and stateDriverCalls[3].expression:find("[@focus,exists] show", 1, true),
  "ZONE_CHANGED_NEW_AREA did not rebuild the out-of-instance visibility expression")

-- Removing the final real condition must leave no Core route and hand
-- existence visibility back to UnitWatch even through targeted element apply.
local stateDriverUnregisterBefore = stateDriverUnregisterCalls
local unitWatchRegisterBefore = unitWatchRegisterCalls
UF.ApplySpec(loadFrame, {
  enabled = true,
  unit = "focus",
  key = "focus",
  scope = "single",
  load = { active = false },
}, nil, { LoadConditions = true })
Check(not (loadFrame._msufActiveElements and loadFrame._msufActiveElements.LoadConditions),
  "condition teardown retained active LoadConditions ownership")
Check(not RuntimeHasLabel(loadFrame, "LoadConditions"),
  "condition teardown retained LoadConditions in its runtime sequence")
Check(loadFrame.genericEvents.PLAYER_ENTERING_WORLD == nil
    and loadFrame.genericEvents.ZONE_CHANGED_NEW_AREA == nil,
  "condition teardown retained zone-boundary routes")
Check(stateDriverUnregisterCalls == stateDriverUnregisterBefore + 1,
  "condition teardown did not unregister its secure state driver")
Check(unitWatchRegisterCalls == unitWatchRegisterBefore + 1
    and loadFrame.unitWatchRegistered == true,
  "condition teardown did not restore native UnitWatch")

-- Forced preview is still a real visibility owner even with no profile
-- conditions, and disabling preview returns to the same native default.
local previewFrame = NewUnitFrame("target")
_G.RegisterUnitWatch(previewFrame)
local previewSpec = {
  enabled = true,
  unit = "target",
  key = "target",
  scope = "single",
  load = { active = false },
}
_G.MSUF_PreviewTestMode = true
local previewDriverBefore = #stateDriverCalls
local previewUnitWatchUnregisterBefore = unitWatchUnregisterCalls
UF.ApplySpec(previewFrame, previewSpec, nil, { LoadConditions = true })
Check(previewFrame._msufActiveElements.LoadConditions == true,
  "forced preview did not activate LoadConditions")
Check(RuntimeHasLabel(previewFrame, "LoadConditions"),
  "forced preview missed LoadConditions runtime ownership")
Check(#stateDriverCalls == previewDriverBefore + 1
    and stateDriverCalls[#stateDriverCalls].expression:find("[nocombat] show", 1, true),
  "forced preview did not install its secure visibility expression")
Check(unitWatchUnregisterCalls == previewUnitWatchUnregisterBefore + 1,
  "forced preview did not replace native UnitWatch with its secure driver")
_G.MSUF_PreviewTestMode = nil
UF.ApplySpec(previewFrame, previewSpec, nil, { LoadConditions = true })
Check(not (previewFrame._msufActiveElements and previewFrame._msufActiveElements.LoadConditions)
    and previewFrame.unitWatchRegistered == true,
  "preview teardown did not return to inactive UnitWatch ownership")

-- Compact probes guard the other non-basic runtime owners that were skipped by
-- the same event-owner gate. Their rendering is tested elsewhere; this verifies
-- only Core registration and dispatch.
local visualCalls, statusCalls = {}, {}
local function CountCall(calls, event, unit)
  calls[event] = (calls[event] or 0) + 1
  calls.lastUnit = unit
end

UF.RegisterElement("GroupVisuals", {
  IsEnabled = function(_, spec) return spec and spec.routeProbe == true end,
  Apply = function() end,
  GetEvents = function() return { "UNIT_HEALTH", "UNIT_FLAGS" } end,
  Update = function(_, event, unit) CountCall(visualCalls, event, unit) end,
})
UF.RegisterElement("GroupStatusRuntime", {
  IsEnabled = function(_, spec) return spec and spec.routeProbe == true end,
  Apply = function() end,
  GetEvents = function()
    return { "UNIT_PHASE", "UNIT_FLAGS", "INCOMING_RESURRECT_CHANGED", "UNIT_FACTION" }
  end,
  Update = function(_, event, unit) CountCall(statusCalls, event, unit) end,
})

local probe = NewUnitFrame("party3")
local probeSpec = {
  enabled = true,
  unit = "party3",
  key = "party",
  scope = "group",
  routeProbe = true,
}
UF.ApplySpec(probe, probeSpec, nil, { GroupVisuals = true, GroupStatusRuntime = true })

for _, event in ipairs({
  "UNIT_HEALTH", "UNIT_FLAGS", "UNIT_PHASE", "INCOMING_RESURRECT_CHANGED", "UNIT_FACTION",
}) do
  Check(UnitRoute(probe, event) == "party3", event .. " runtime-owner route is missing")
  Check(probe.genericEvents[event] == nil, event .. " must stay unit-filtered")
end

probe:Fire("UNIT_HEALTH", "party3")
probe:Fire("UNIT_PHASE", "party3")
probe:Fire("UNIT_FLAGS", "party3")
probe:Fire("INCOMING_RESURRECT_CHANGED", "party3")
probe:Fire("UNIT_FACTION", "party3")
local groupDataDriver
for i = #createdFrames, 1, -1 do
  local candidate = createdFrames[i]
  if candidate.visible == true and candidate:GetScript("OnUpdate") then
    groupDataDriver = candidate
    break
  end
end
Check(groupDataDriver ~= nil, "deferred group health driver was not armed")
groupDataDriver:RunScript("OnUpdate")
Check(visualCalls.UNIT_HEALTH == 1 and visualCalls.UNIT_FLAGS == 1,
  "GroupVisuals probe was not dispatched exactly once per owned event")
Check(statusCalls.UNIT_PHASE == 1 and statusCalls.UNIT_FLAGS == 1
    and statusCalls.INCOMING_RESURRECT_CHANGED == 1 and statusCalls.UNIT_FACTION == 1,
  "GroupStatusRuntime probe was not dispatched exactly once per owned event")
Check(visualCalls.lastUnit == "party3" and statusCalls.lastUnit == "party3",
  "runtime-owner probes received the wrong bound unit")

-- The single-unit config compiler must carry the menu's explicit boss-target
-- outline mode into every concrete boss unit spec.
_G.MSUF_DB = {
  general = { bossTargetHighlightEnabled = true, bossTargetOutlineMode = 1 },
  bars = {},
  boss = {},
}
LoadEngine("MSUF_UF_Config.lua")
local bossSpec = assert(UF.Config.RefreshUnit("boss1"))
Check(bossSpec.border and bossSpec.border.bossTarget == true,
  "bossTargetOutlineMode=1 was not compiled into the boss border spec")
_G.MSUF_DB.general.bossTargetOutlineMode = 0
bossSpec = assert(UF.Config.RefreshUnit("boss1"))
Check(bossSpec.border and bossSpec.border.bossTarget == false,
  "bossTargetOutlineMode=0 was not compiled into the boss border spec")
_G.MSUF_DB.boss.hlOverride = true
_G.MSUF_DB.boss.bossTargetOutlineMode = 1
bossSpec = assert(UF.Config.RefreshUnit("boss1"))
Check(bossSpec.border and bossSpec.border.bossTarget == true,
  "boss-specific bossTargetOutlineMode override was not compiled")

-- Raid Group owns a status layer, but profiles from before that split must
-- continue to inherit the normal name layer until the new key is set.
_G.MSUF_DB = {
  general = {},
  bars = {},
  target = { showRaidGroupInName = true, nameTextLayer = 19 },
}
local targetSpec = assert(UF.Config.RefreshUnit("target"))
Check(targetSpec.status.raidGroup.layer == 19,
  "raid-group name did not inherit the legacy name layer")
_G.MSUF_DB.target.raidGroupNameLayer = 27
targetSpec = assert(UF.Config.RefreshUnit("target"))
Check(targetSpec.status.raidGroup.layer == 27,
  "raid-group name ignored its independent layer")
_G.MSUF_DB.target.raidGroupNameLayer = 41
targetSpec = assert(UF.Config.RefreshUnit("target"))
Check(targetSpec.status.raidGroup.layer == 30,
  "raid-group name layer was not clamped to the 0-30 contract")

print("aggro runtime routing smoke: ok")
