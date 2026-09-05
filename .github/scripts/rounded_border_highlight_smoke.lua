-- Regression: rounded highlights must retain their resolved frame level.
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
local roleByUnit = {}
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
local inCombat = false
_G.InCombatLockdown = function() return inCombat end
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
  return roleByUnit[unit] or "DAMAGER"
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
  MSUF[name] = value; _G[name] = value
  return value
end
_G.MSUF_NS = MSUF

local engineRoot = "MidnightSimpleUnitFrames/UnitFrames/Engine/"
local libraryRoot = "MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/"
local libraryFiles = {
  ["MSUF_UF_Metadata.lua"] = true,
  ["MSUF_UF_Core.lua"] = true,
}
local function LoadEngine(relativePath)
  local inLibrary = libraryFiles[relativePath] == true
  local path = (inLibrary and libraryRoot or engineRoot) .. relativePath
  local handle = io.open(path, "r")
  if handle then
    handle:close()
  else
    path = (inLibrary and "Libs/MSUFUnitFrames/" or "UnitFrames/Engine/") .. relativePath
  end
  local chunk, err = loadfile(path)
  Check(chunk, err)
  return chunk("MidnightSimpleUnitFrames", MSUF)
end

LoadEngine("MSUF_UF_Metadata.lua")
LoadEngine("MSUF_UF_Core.lua")
assert(loadfile(libraryRoot .. "MSUF_UF_Layers.lua"))("MidnightSimpleUnitFrames", MSUF)
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

-- Load the complete rounded runtime: no extracted replacement renderer.
local texturesCreated, combatLayoutWrites = 0, 0
local createTexture = Object.CreateTexture
function Object:CreateTexture(name, layer, template, sublevel)
  Check(not inCombat, 'rounded highlight allocated a texture in combat')
  texturesCreated = texturesCreated + 1
  local t = createTexture(self)
  t.drawLayer, t.subLayer = layer, sublevel
  return t
end
function Object:CreateMaskTexture(...) return self:CreateTexture(...) end
function Object:SetTexture(path) self.texture = path end
function Object:SetTextureSliceMargins() end
function Object:SetTextureSliceMode() end
function Object:SetSnapToPixelGrid() end
function Object:SetTexelSnappingBias() end
function Object:AddMaskTexture(mask) self.mask = mask end
function Object:RemoveMaskTexture(mask) if self.mask == mask then self.mask = nil end end
function Object:GetWidth() return self.width or 180 end
function Object:GetHeight() return self.height or 40 end
function Object:GetSize() return self:GetWidth(), self:GetHeight() end
function Object:GetStatusBarTexture() return self.fill end
function Object:SetBackdropColor(...) self.backdrop = {...} end
function Object:SetBackdrop() end
local setPoint = Object.SetPoint
function Object:SetPoint(...)
  if inCombat and self.texture and self.texture:find("rounded_clean_edge", 1, true) then
    combatLayoutWrites = combatLayoutWrites + 1
  end
  return setPoint(self, ...)
end
local units, groups, module = {}, {}, nil
local disabledStartup = arg and arg[1] == '--startup-disabled'
UF.ForEachFrame = function(fn) for _, f in ipairs(units) do fn(f) end end
MSUF.GF.ForEachFrame = function(fn) for _, f in ipairs(groups) do fn(f, f.unit, 'party') end end
MSUF.GF.GetConf = function() return {} end
MSUF.GF.GetBarOutlineThickness = function() return 2 end
MSUF.MSUF_RegisterModule = function(_, value) module = value end
_G.MSUF_DB = {
 general = {highlightStyle='BORDER', highlightThickness=4},
 bars = {roundedFramesEnabled=not disabledStartup, roundedUnitFrames=true, roundedGroupFrames=true,
 roundedMouseover=true, roundedPowerBars=false, barOutlineThickness=2},
}
local function AssertRounded(f, color, shown)
 local edge = f._msufRoundedBorderEdge or f._msufRUF_Edge or f._msufRGF_Edge
 Check(edge ~= nil, 'rounded outline was not prewarmed')
 Check(edge:GetParent() == f.MSUFBorderOverlay, 'rounded highlight lost the shared outline host')
 Check(edge.drawLayer == 'OVERLAY', 'rounded highlight is below the host surface')
 Check(edge.shown == shown, 'wrong rounded highlight visibility')
 if shown then
  Check(edge.vertexColor[1]==color[1] and edge.vertexColor[2]==color[2] and edge.vertexColor[3]==color[3], 'rounded highlight lost its color')
 end
 for _, square in pairs(f.MSUFBorderEdges) do Check(not square.shown, 'square highlight overlaps rounded highlight') end
 return edge
end

-- The real login path only registers optional modules; it does not call their
-- Init/Enable/Apply hooks. Exercise that path before the matrix below can wire
-- anything manually. A global rounded callback alone is insufficient: Borders
-- retains its own callback and must receive it during enabled startup.
local deferredCallbacks = {}
_G.C_Timer = { After = function(_, callback)
 deferredCallbacks[#deferredCallbacks+1] = callback
end }
local function NewStartupFrame(unit, kind)
 local f = NewUnitFrame(unit); f.frameLevel = 10
 if kind then
  f._msufGFKind = kind; f.health = f.hpBar
  groups[#groups+1] = f
 else units[#units+1] = f end
 local cfg = AggroBorderConfig()
 cfg.enabled = true; cfg.thickness = 2; cfg.highlightThickness = 4
 cfg.r,cfg.g,cfg.b,cfg.a = 0,0,0,1
 threatByUnit[unit] = 0
 UF.ApplySpec(f,{enabled=true,unit=unit,key=unit,
  scope=kind and 'group' or 'single',groupKind=kind,border=cfg},nil,{Borders=true})
 return f
end
local startupFrames = {
 NewStartupFrame('target'), NewStartupFrame('party1','party'),
}
assert(loadfile(arg and arg[2] or 'MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_RoundedFrames.lua'))('MidnightSimpleUnitFrames',MSUF)
MSUF.__msufRoundedEventFrame:Fire('ADDON_LOADED','MidnightSimpleUnitFrames')
Check(module ~= nil, 'rounded module was not registered')
-- The deferred login pass must also cover frames created after registration.
startupFrames[#startupFrames+1] = NewStartupFrame('focus')
startupFrames[#startupFrames+1] = NewStartupFrame('raid1','raid')
if disabledStartup then
 Check(not MSUF.__msufRoundedEventFrame.genericEvents.PLAYER_LOGIN
  and not MSUF.__msufRoundedEventFrame.genericEvents.PLAYER_REGEN_ENABLED,
  'disabled rounded startup armed runtime events')
 Check(_G.MSUF_RoundedUF_OnBorderVisualChanged == nil and _G.MSUF_RoundedUF_Active == nil,
  'disabled rounded startup published active callbacks')
 Check(#deferredCallbacks == 0, 'disabled rounded startup queued work')
 for _, f in ipairs(startupFrames) do
  Check(f._msufRoundedBorderEdge == nil, 'disabled rounded startup allocated outline art')
 end
 _G.MSUF_DB.bars.roundedFramesEnabled = true
 _G.MSUF_ApplyRoundedUnitframes()
else
 MSUF.__msufRoundedEventFrame:Fire('PLAYER_LOGIN')
 Check(#deferredCallbacks == 1, 'enabled rounded startup did not queue one cold login apply')
 Check(not MSUF.__msufRoundedEventFrame.genericEvents.PLAYER_LOGIN,
  'rounded startup retained its one-shot login event')
 for i=1,#deferredCallbacks do deferredCallbacks[i]() end
end
for _, f in ipairs(startupFrames) do
 AssertRounded(f,{0,0,0},true)
 local before, beforeLayout = texturesCreated, combatLayoutWrites
 inCombat = true
 threatByUnit[f.unit] = 3; f:Fire('UNIT_THREAT_SITUATION_UPDATE',f.unit)
 Check(f._msufBorderVisualSource == 'aggro', 'startup threat did not reach Borders')
 local edge = f._msufRoundedBorderEdge
 Check(edge and edge.vertexColor[1] == 1 and edge.vertexColor[2] == 0.55
  and edge.vertexColor[3] == 0,
  'login-only '..f.unit..' aggro changed Borders but did not recolor the rounded highlight')
 AssertRounded(f,{1,0.55,0},true)
 threatByUnit[f.unit] = 0; f:Fire('UNIT_THREAT_SITUATION_UPDATE',f.unit)
 AssertRounded(f,{0,0,0},true)
 Check(texturesCreated == before and combatLayoutWrites == beforeLayout,
  'login-only threat transition allocated or laid out rounded combat art')
 inCombat = false
end
-- The Bars > Border Highlights test button must use its public transaction,
-- through the real Borders element and rounded owner, for both frame scopes.
UF.RefreshBorders = function()
 for _, f in ipairs(units) do UF.ApplySpec(f,f.MSUFSpec,nil,{Borders=true}) end
end
MSUF.GF.RefreshBorder = function()
 for _, f in ipairs(groups) do UF.ApplySpec(f,f.MSUFSpec,nil,{Borders=true}) end
end
_G.MSUF_SetAggroBorderTestMode(true,'shared')
for _, f in ipairs(startupFrames) do AssertRounded(f,{1,0.55,0},true) end
_G.MSUF_SetAggroBorderTestMode(false,'shared')
for _, f in ipairs(startupFrames) do AssertRounded(f,{0,0,0},true) end
_G.MSUF_SetDispelBorderTestMode(true,'shared')
for _, f in ipairs(startupFrames) do AssertRounded(f,{0.25,0.75,1},true) end
_G.MSUF_SetDispelBorderTestMode(false,'shared')
for _, f in ipairs(startupFrames) do AssertRounded(f,{0,0,0},true) end
_G.MSUF_SetPurgeBorderTestMode(true,'shared')
for _, f in ipairs(startupFrames) do
 AssertRounded(f,f._msufGFKind and {0,0,0} or {1,0.85,0},true)
end
_G.MSUF_SetPurgeBorderTestMode(false,'shared')
for _, f in ipairs(startupFrames) do AssertRounded(f,{0,0,0},true) end

local tested = 0
for _, scenario in ipairs({
 {'target'}, {'focus'}, {'boss1'},
 {'party1', 'party'}, {'raid1', 'raid'}, {'party1', 'party', true},
}) do
 local scope = scenario[2] and 'group' or 'single'
 for _, layer in ipairs({0,30}) do
  for _, overlayEnabled in ipairs({false,true}) do
   local unit = scenario[1]
   local f = NewUnitFrame(unit); f.frameLevel=10
   if scope=='group' then
    f._msufGFKind = scenario[2]
    if scenario[3] then f.barGroup=NewObject(f); f.barGroup.frameLevel=11 end
    f.health=f.hpBar; groups[#groups+1]=f
   else units[#units+1]=f end
   local cfg = AggroBorderConfig()
   cfg.enabled=true; cfg.thickness=2; cfg.highlightThickness=4; cfg.layer=layer
   cfg.r,cfg.g,cfg.b,cfg.a=0,0,0,1
   local spec={enabled=true,unit=unit,key=unit,scope=scope,border=cfg,
    group=scope=='group' and {dispelOverlayEnabled=overlayEnabled} or nil}
   threatByUnit[unit]=0
   UF.ApplySpec(f,spec,nil,{Borders=true})
   module.Apply()
   local edge=AssertRounded(f,{0,0,0},true)
   Check(f.MSUFBorderOverlay:GetFrameLevel()==MSUF.UF.Layers.ElementLevel(layer,0,8),'normal outline level differs')
   local hover=scope=='group' and f._msufRGF_HoverContainer or f._msufRUF_HoverContainer
   Check(hover and hover:GetFrameLevel()==f:GetFrameLevel()+5,'rounded mouseover lost the normal highlight band')
   f:SetFrameLevel(17); module.Apply()
   Check(hover:GetFrameLevel()==f:GetFrameLevel()+5,'rounded mouseover level was not refreshed after an owner level change')
   local before, beforeLayout=texturesCreated,combatLayoutWrites
   inCombat=true
   for _, visual in ipairs({
    {'aggro',1,0.55,0}, {'dispel',0.25,0.75,1}, {'purge',1,0.85,0}, {'bossTarget',1,0.82,0},
   }) do
    Check(_G.MSUF_RoundedUF_OnBorderVisualChanged(f,true,visual[1],4,visual[2],visual[3],visual[4],1),'shared highlight callback did not handle '..visual[1])
    AssertRounded(f,{visual[2],visual[3],visual[4]},true)
   end
   threatByUnit[unit]=3; f:Fire('UNIT_THREAT_SITUATION_UPDATE',unit)
   AssertRounded(f,{1,0.55,0},true)
   Check(f.MSUFBorderOverlay:GetFrameLevel()==MSUF.UF.Layers.ElementLevel(layer,0,23),'aggro outline level differs')
   threatByUnit[unit]=0; f:Fire('UNIT_THREAT_SITUATION_UPDATE',unit)
   AssertRounded(f,{0,0,0},true)
   local hoverCallback=scope=='group' and _G.MSUF_RoundedUF_OnGroupMouseover or _G.MSUF_RoundedUF_OnUnitMouseover
   hoverCallback(f,true); Check(hover.shown,'rounded mouseover did not show')
   hoverCallback(f,false); Check(not hover.shown,'rounded mouseover did not hide')
   Check(before==texturesCreated,'combat highlight created texture')
   Check(beforeLayout==combatLayoutWrites,'combat highlight changed layout')
   inCombat=false
   -- Normal border disabled: highlighting still works and clears entirely.
   cfg.enabled=false
   UF.ApplySpec(f,spec,nil,{Borders=true}); module.Apply()
   AssertRounded(f,{0,0,0},false)
   inCombat=true
   threatByUnit[unit]=3; f:Fire('UNIT_THREAT_SITUATION_UPDATE',unit)
   AssertRounded(f,{1,0.55,0},true)
   threatByUnit[unit]=0; f:Fire('UNIT_THREAT_SITUATION_UPDATE',unit)
   AssertRounded(f,{0,0,0},false)
   inCombat=false
   cfg.enabled=true
   UF.ApplySpec(f,spec,nil,{Borders=true}); module.Apply()
   module.Disable()
   Check(not edge.shown,'rounded border survived disable')
   Check(f.MSUFBorderEdges.top.shown,'square border did not return')
   module.Enable()
   AssertRounded(f,{0,0,0},true)
   tested=tested+1
  end
 end
end
-- A frame without a prewarmed rounded pool must retain its square highlight
-- until the next cold apply, rather than going blank or creating combat art.
module.Disable()
local cold = NewUnitFrame('player')
local coldCfg = AggroBorderConfig()
UF.ApplySpec(cold,{enabled=true,unit='player',key='player',scope='single',border=coldCfg},nil,{Borders=true})
module.Enable()
Check(cold._msufRoundedBorderEdge == nil,'fallback frame was unexpectedly prewarmed')
local before = texturesCreated
inCombat=true
threatByUnit.player=3; threatByUnit.target=3; cold:Fire('UNIT_THREAT_SITUATION_UPDATE','player')
Check(cold.MSUFBorderEdges.top.shown,'unprewarmed combat highlight vanished instead of falling back')
Check(texturesCreated==before,'unprewarmed combat highlight allocated art')
inCombat=false
units[#units+1]=cold; module.Apply()
AssertRounded(cold,{1,0.55,0},true)
-- The Bars slider supports 1..30; thick highlights must not stop at 16.
for _, f in ipairs(startupFrames) do
 for _, thickness in ipairs({1,4,16,23,30}) do
  threatByUnit[f.unit]=0
  f.MSUFSpec.border.highlightThickness=thickness
  UF.ApplySpec(f,f.MSUFSpec,nil,{Borders=true}); module.Apply()
  local beforeTextures,beforeLayout=texturesCreated,combatLayoutWrites
  inCombat=true
  threatByUnit[f.unit]=3; f:Fire('UNIT_THREAT_SITUATION_UPDATE',f.unit)
  local stack=assert(f._msufRoundedBorderEdgeStack)
  Check(stack._msufCount==thickness,'rounded '..f.unit..' thickness '..thickness..' was clamped')
  Check(stack[thickness]._msufRUFEdgePad==thickness,'rounded outer edge ignored thickness')
  Check(stack[thickness].shown,'rounded outer edge stayed hidden')
  threatByUnit[f.unit]=0; f:Fire('UNIT_THREAT_SITUATION_UPDATE',f.unit)
  Check(texturesCreated==beforeTextures and combatLayoutWrites==beforeLayout,
   'thick combat border allocated or changed geometry')
  inCombat=false
 end
end
print('PASS rounded border highlights: '..(disabledStartup and 'disabled startup and public enable' or 'login-only')..' unit/group threat and Bars test lifecycle; '..tested..' unit/group/layer/overlay cases; thickness 1/4/16/23/30; shared highlight colors, threat transitions, combat prewarm/fallback, mouseover and disable/enable')
