-- 3D portrait render: the real portrait element and model module with a
-- counting PlayerModel stub. Checks the SetUnit budget, that open world never
-- falls back to 2D (secret GUID, refused SetUnit, offline, unit swaps), the
-- instanced-combat fallback per unit (player and pet keep 3D), the party
-- opt-out, Classic without the combat rule, previews, the cast icon, render
-- switches, camera/inset layout, the ring hole, the background tint and the dependent units' model-event filter. Native rendering, real restriction behaviour,
-- alpha inheritance and frame-level draw order need an in-game check.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local retail = flavor == "Mainline" or flavor == "Forever"
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
Secrets.Install()
local checks = 0
local function Check(value, message)
  checks = checks + 1
  assert(value, message)
end
local function Noop() end

local Widget = {}
function Widget:SetScript(event, callback) self.scripts[event] = callback end
function Widget:HookScript(event, callback)
  local hooks = self.hooks[event] or {}
  self.hooks[event] = hooks
  hooks[#hooks + 1] = callback
end
function Widget:Show()
  if self.shown then return end
  self.shown = true
  for _, callback in ipairs(self.hooks.OnShow or {}) do callback(self) end
end
function Widget:Hide() self.shown = false end
function Widget:SetShown(show) if show then self:Show() else self:Hide() end end
function Widget:IsShown() return self.shown end
function Widget:SetTexture(value, wrapH, wrapV) self.image, self.wrapH, self.wrapV = value, wrapH, wrapV end
function Widget:SetAtlas(atlas) self.atlas = atlas end
function Widget:SetTexCoord(l, r, t, b) self.l, self.r, self.t, self.b = l, r, t, b end
function Widget:SetSize(width, height) self.width, self.height = width, height end
function Widget:GetWidth() return self.width end
function Widget:GetHeight() return self.height end
function Widget:GetFrameLevel() return self.level end
function Widget:SetFrameLevel(level) self.level = level end
function Widget:ClearAllPoints() self.points = {} end
function Widget:SetPoint(point, _, _, x, y) self.points = self.points or {}; self.points[point] = { x, y } end
function Widget:AddMaskTexture(mask) self.masks[mask] = true end
function Widget:RemoveMaskTexture(mask) self.masks[mask] = nil end
for _, name in ipairs({ "EnableMouse", "SetAllPoints", "SetVertexColor", "SetAlpha",
  "RegisterEvent", "UnregisterEvent", "SetSnapToPixelGrid", "SetTexelSnappingBias", "SetDrawLayer" }) do Widget[name] = Noop end
local function NewWidget(parent)
  return setmetatable({ parent = parent, scripts = {}, hooks = {}, masks = {}, points = {}, shown = true,
    width = 40, height = 40, level = 1 }, { __index = Widget })
end
function Widget:CreateTexture() return NewWidget(self) end
function Widget:CreateMaskTexture() return NewWidget(self) end

local state = { guid = "A", connected = true, visible = true, exists = true,
  nativeCalls = 0, setUnits = 0, canSetCalls = 0, inInstance = false, inCombat = false }
local models = {}
local Model3D = setmetatable({}, { __index = Widget })
-- Client camera rules the stub keeps: a model load (SetUnit) starts on the
-- full-body camera, and a portrait camera set on a hidden model does not stick.
function Model3D:SetUnit(unit)
  state.setUnits = state.setUnits + 1
  self.unit = unit
  self.portraitZoom = 0
  if self.scripts.OnModelLoaded then self.scripts.OnModelLoaded(self) end
  return state.setUnitResult ~= false
end
-- nil answers "allowed" (a client without a verdict), false refuses.
function Model3D:CanSetUnit() state.canSetCalls = state.canSetCalls + 1 return state.canSet end
function Model3D:SetKeepModelOnHide(keep) self.keep = keep end
function Model3D:SetPortraitZoom(zoom) if self.shown then self.portraitZoom = zoom end end
function Model3D:SetPosition(x, y, z) self.position = x + y + z end
function Model3D:Show()
  if self.shown then return end
  self.shown = true
  if self.scripts.OnShow then self.scripts.OnShow(self) end
  for _, callback in ipairs(self.hooks.OnShow or {}) do callback(self) end
end
function Model3D:SetShown(show) if show then self:Show() else self:Hide() end end
function Model3D:SetCamDistanceScale(scale) self.camScale = scale end
function Model3D:SetViewTranslation(x, y) self.transX, self.transY = x, y end
function Model3D:SetFacing(facing) self.facing = facing end

local env = setmetatable({}, { __index = _G })
env._G = env
env.CreateFrame = function(kind, _, parent)
  if kind == "PlayerModel" then
    local model = setmetatable(NewWidget(parent), { __index = Model3D })
    models[#models + 1] = model
    return model
  end
  return NewWidget(parent)
end
-- Each event happens on its own client frame (the element dedupes per frame).
local clock = 0
env.GetTime = function() clock = clock + 1 return clock end
env.C_Timer = { After = function() error("unexpected delayed timer") end }
local FIXED_GUIDS = { player = "PLAYER", party1 = "P1", party2 = "P2", boss1 = "B1" }
env.UnitGUID = function(unit) return FIXED_GUIDS[unit] or state.guid end
env.UnitExists = function(unit) if unit == "player" then return true end return state.exists end
env.UnitIsConnected = function() return state.connected end
env.UnitIsVisible = function() return state.visible end
env.UnitIsPlayer = function(unit) return state.players ~= nil and state.players[unit] == true end
env.UnitReaction = function() return state.reaction end
env.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
env.UnitClassification = function() return "normal" end
env.C_Texture = { GetAtlasInfo = function() return { width = 64, height = 64 } end }
env.UnitClass = function() return "Mage", "MAGE" end
env.UnitCastingInfo = function() return state.castName, nil, state.castIcon end
env.UnitChannelInfo = function() return nil end
env.IsInInstance = function() return state.inInstance end
env.InCombatLockdown = function() return state.inCombat end
env.SetPortraitTexture = function(texture, unit)
  state.nativeCalls = state.nativeCalls + 1
  texture.image = "RTPortrait:" .. tostring(unit)
end

local events, dependencies = {}, {}
local core = { Client = { IsVanilla = flavor == "Vanilla", IsForever = flavor == "Forever", IsRetail = retail },
  PublicGlobals = {}, UF = {} }
core.ExportPublic = function(name, value) dependencies[name] = value end
core.Require = function(name) return assert(dependencies[name], "missing provider " .. name) end
core.PortraitMedia = { ResolveClassPortrait = function() return { texture = "class:MAGE" } end }
core.UFVisuals = { UF = core.UF, SetShown = function(region, shown)
  if region and region._msufShown ~= shown then
    region._msufShown = shown
    if shown then region:Show() else region:Hide() end
  end
end }
dependencies.MSUF_PixelLayoutRegion = function(region) return region end
dependencies.MSUF_EventBus_Register = function(event, key, callback)
  events[key] = events[key] or {}
  events[key][event] = callback
  return true
end
dependencies.MSUF_EventBus_Unregister = function(event, key)
  if events[key] then events[key][event] = nil end
  if events[key] and next(events[key]) == nil then events[key] = nil end
end
local Portrait
core.UF.RegisterElement = function(name, element) Check(name == "Portrait", "wrong element") Portrait = element end
-- Route compiler seam: dependent units' model events are filtered by payload.
local routes = {}
core.UF.dependentUnitParents = { targettarget = "target", focustarget = "focus", pettarget = "pet" }
core.UF.RouteCompiler = { BeginFrameEvent = Noop, EndFrameEvent = Noop }
core.UF.RegisterRoute = function(name, compile, _, routeEvents) routes[name] = { compile = compile, events = routeEvents } end
env.UnitIsUnit = function(a, b)
  if state.unitIsUnitSecret then return Secrets.New("boolean") end
  return a == b or (state.sameUnits ~= nil and state.sameUnits[a] == b)
end
local function Load(path)
  local chunk = assert(loadfile(root .. "/" .. path))
  setfenv(chunk, env)
  chunk("MidnightSimpleUnitFrames", core)
end
Load("MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua")
Load("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_PortraitDetails.lua")
local modelFile = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_PortraitModel.lua"
local elementFile = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Portrait.lua"
Load("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_PortraitModel.lua")
Load("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Portrait.lua")
local Model = assert(core.PortraitModel, "model module did not register")
local stopModelSecrets = Secrets.Watch(modelFile, { strict = true })
local stopElementSecrets = Secrets.Watch(elementFile, { strict = true })

local function Flush()
  local driver = core.Scheduler.frame
  if driver.scripts.OnUpdate then driver.scripts.OnUpdate(driver, 0.016) end
end
local function Spec(unit, extra)
  local p = { enabled = true, render = "3D", shape = "SQUARE", width = 40, height = 40,
    texL = 0.1, texR = 0.9, texT = 0.1, texB = 0.9, border = { style = "NONE" },
    modelCamScale = 1, modelPanX = 0, modelPanY = 0, modelFacing = 0, modelInset = 1 }
  for k, v in pairs(extra or {}) do p[k] = v end
  return { key = unit, height = 40, portrait = p }
end
local function NewFrame(unit, extra, group)
  local frame = NewWidget()
  frame.MSUFUnitKey, frame._msufCoreVisible = unit, true
  frame.MSUFSpec = Spec(unit, extra)
  if group then frame.MSUFSpec.scope = "group" end
  Portrait.Create(frame)
  Portrait.Apply(frame, frame.MSUFSpec)
  return frame
end
local function Fire(frame, event) Portrait.Update(frame, event, frame.MSUFUnitKey) end
local function ModelOf(frame) return frame.MSUFPortraitHolder.model3D end
local function Rule(event)
  local handlers = events.MSUF_UF_PORTRAIT_MODEL_COMBAT
  if handlers and handlers[event] then handlers[event](event) end
end
-- Every shown model must sit on the portrait camera, not the full-body one.
local function CheckCameras(where)
  for _, model in ipairs(models) do
    if model.shown then
      Check(model.portraitZoom == 1, where .. ": a shown model kept the full-body camera")
    end
  end
end

-- Apply binds the model once and hides the 2D image.
local target = NewFrame("target")
local model = ModelOf(target)
Check(model and model.unit == "target" and state.setUnits == 1, "3D apply did not bind the model once")
Check(model.keep == true and model.shown == true and target.portrait._msufShown == false, "model/image visibility wrong")
Check(state.nativeCalls == 0, "3D apply resolved a native 2D portrait")
Check(model.portraitZoom == 1 and model.camScale == 1, "camera not replayed on model load")
Check(model.level == target.MSUFPortraitHolder._msufLevel, "model is not on the holder level")

-- Unchanged identity costs nothing; a new GUID costs exactly one SetUnit.
local before = state.setUnits
for _ = 1, 20 do Fire(target, "MSUF_UNIT_IDENTITY_SOFT") end
Check(state.setUnits == before and state.nativeCalls == 0, "soft identity events rebound an unchanged model")
state.guid = "B"
Fire(target, "PLAYER_TARGET_CHANGED")
Check(state.setUnits == before + 1, "target change must bind the new unit once")
for _ = 1, 20 do Fire(target, "MSUF_UNIT_IDENTITY_SOFT") end
Check(state.setUnits == before + 1, "soft identity after a target change rebound the model")

-- Model/portrait bursts collapse into one forced SetUnit on the next frame.
before = state.setUnits
Fire(target, "UNIT_MODEL_CHANGED")
Fire(target, "UNIT_PORTRAIT_UPDATE")
Fire(target, "UNIT_MODEL_CHANGED")
Check(state.setUnits == before, "model refresh must wait for the next frame")
Flush()
Check(state.setUnits == before + 1 and state.nativeCalls == 0, "model burst must cost one SetUnit and no 2D work")

-- Open world never falls back: a secret GUID keeps the bound model, and a new
-- unit behind a secret GUID binds through the identity generation.
state.guid = Secrets.New("string")
before = state.setUnits
for _ = 1, 5 do Fire(target, "MSUF_UNIT_IDENTITY_SOFT") end
Check(state.setUnits == before and state.nativeCalls == 0 and model.shown == true and target.portrait._msufShown == false,
  "a secret GUID dropped or rebound the already bound model")
-- OnShow may follow a consumed target event, so it rebinds once, still in 3D.
Fire(target, "MSUF_UF_ONSHOW")
Check(state.setUnits == before + 1 and state.nativeCalls == 0 and model.shown == true, "OnShow left 3D")
before = state.setUnits
Fire(target, "PLAYER_TARGET_CHANGED")
Check(state.setUnits == before + 1 and model.shown == true and state.nativeCalls == 0,
  "secret target change did not bind the new unit in 3D")
-- A refused or slow SetUnit keeps the model frame; the next unit binds again.
state.setUnitResult = false
Fire(target, "PLAYER_TARGET_CHANGED")
Check(state.setUnits == before + 2 and model.shown == true and state.nativeCalls == 0,
  "a refused SetUnit fell back to 2D in the open world")
state.setUnitResult, state.guid = nil, "C"
CheckCameras("open-world target swaps")

-- Offline and out-of-range units keep their model (a connection change
-- reloads it once, as Blizzard's portrait does).
state.connected, state.visible = false, false
before = state.setUnits
Fire(target, "UNIT_CONNECTION")
Check(state.nativeCalls == 0 and model.shown == true and state.setUnits == before + 1, "offline unit left 3D")
state.connected, state.visible = true, true
Fire(target, "UNIT_CONNECTION")
Check(model.shown == true and target.portrait._msufShown == false, "reconnect hid the model")

-- A previewed frame without a unit shows the player as its stand-in.
state.exists = false
local preview = NewFrame("boss1")
Check(ModelOf(preview).unit == "player" and ModelOf(preview).shown == true, "preview stand-in missing")
state.exists = true

-- Compiled specs: player and pet keep 3D in instanced combat, other unit
-- frames do not; party frames follow their option.
local player = NewFrame("player", { modelInstanceCombat = true })
local pet = NewFrame("pet", { modelInstanceCombat = true })
local tot = NewFrame("targettarget")
local petTarget = NewFrame("pettarget")
local focus = NewFrame("focus")
local focusTarget = NewFrame("focustarget")
local party = NewFrame("party1", nil, true)
local partyKeep = NewFrame("party2", { modelInstanceCombat = true }, true)
local fallbackFrames = { target, tot, petTarget, focus, focusTarget, preview, party }
local keepFrames = { player, pet, partyKeep }

-- Open-world combat and quick unit swaps stay 3D on every frame.
state.inCombat = true
Rule("PLAYER_REGEN_DISABLED")
for i = 1, 10 do
  state.guid = "OW" .. i
  for _, frame in ipairs(fallbackFrames) do Fire(frame, "PLAYER_TARGET_CHANGED") end
  for _, frame in ipairs(keepFrames) do Fire(frame, "MSUF_UNIT_IDENTITY_SOFT") end
  Fire(tot, "UNIT_TARGET")
  Fire(petTarget, "UNIT_TARGET")
end
Flush()
for _, frame in ipairs(fallbackFrames) do
  Check(ModelOf(frame).shown == true and frame.portrait._msufShown == false, frame.MSUFUnitKey .. " left 3D in the open world")
end
for _, frame in ipairs(keepFrames) do
  Check(ModelOf(frame).shown == true, frame.MSUFUnitKey .. " left 3D in the open world")
end
Check(state.nativeCalls == 0, "open-world combat resolved a native 2D portrait")
CheckCameras("open-world combat")
state.inCombat = false
Rule("PLAYER_REGEN_ENABLED")

-- Instanced combat (Retail/Forever): the restricted units go 2D, player, pet
-- and opted-in party frames keep 3D, leaving combat restores everything.
local registered = Model.RuleState()
Check(registered == retail, "combat rule registration does not match the client")
state.inInstance = true
Rule("PLAYER_ENTERING_WORLD")
for _, frame in ipairs(fallbackFrames) do
  Check(ModelOf(frame).shown == true, frame.MSUFUnitKey .. " left 3D inside an instance out of combat")
end
local calls
before, calls = state.setUnits, state.nativeCalls
state.inCombat = true
Rule("PLAYER_REGEN_DISABLED")
if retail then
  for _, frame in ipairs(fallbackFrames) do
    Check(ModelOf(frame).shown == false and frame.portrait._msufShown == true,
      frame.MSUFUnitKey .. " kept 3D in instanced combat")
  end
  for _, frame in ipairs(keepFrames) do
    Check(ModelOf(frame).shown == true and frame.portrait._msufShown == false,
      frame.MSUFUnitKey .. " lost 3D in instanced combat")
  end
  Check(state.nativeCalls == calls + #fallbackFrames and state.setUnits == before,
    "combat switch cost unexpected native or model work")
  -- Swaps in combat stay 2D without touching the models; player stays 3D.
  state.guid = "D"
  Fire(target, "PLAYER_TARGET_CHANGED")
  Fire(focus, "PLAYER_FOCUS_CHANGED")
  for _ = 1, 10 do Fire(player, "MSUF_UNIT_IDENTITY_SOFT") end
  Fire(player, "UNIT_MODEL_CHANGED")
  Flush()
  Check(ModelOf(target).shown == false and ModelOf(focus).shown == false, "combat swap brought a model back")
  Check(ModelOf(player).shown == true and player.portrait._msufShown == false, "player fell back to 2D in instanced combat")
  Check(state.setUnits == before + 1, "only the player's model refresh may bind in combat")
  before = state.setUnits
  state.inCombat = false
  Rule("PLAYER_REGEN_ENABLED")
  for _, frame in ipairs(fallbackFrames) do
    Check(ModelOf(frame).shown == true and frame.portrait._msufShown == false,
      frame.MSUFUnitKey .. " did not get 3D back after combat")
  end
  Check(ModelOf(target).unit == "target" and ModelOf(party).unit == "party1", "restored models bound the wrong unit")
  CheckCameras("combat end")
  -- The stub's shared GUID moved target, ToT, focus, focus target and pet
  -- target to "D" in combat; boss1 and party1 come back without a SetUnit.
  Check(state.setUnits == before + 5, "combat end must rebind only the identities that changed")
  Check(ModelOf(preview).unit == "boss1", "boss frame lost its real unit")
else
  for _, frame in ipairs(fallbackFrames) do
    Check(ModelOf(frame).shown == true, "Classic dropped 3D in instanced combat")
  end
  Check(state.nativeCalls == calls, "Classic resolved a native 2D portrait in instanced combat")
  Check(events.MSUF_UF_PORTRAIT_MODEL_COMBAT == nil, "Classic registered the combat rule")
  state.inCombat = false
end
state.inInstance = false

-- The cast icon covers the model and gives it back.
local caster = NewFrame("focus", { castSpellIcon = true })
state.castName, state.castIcon = "Frostbolt", 135846
Fire(caster, "UNIT_SPELLCAST_START")
Check(ModelOf(caster).shown == false and caster.MSUFPortraitCastIcon._msufShown == true, "cast icon did not cover the model")
state.castName, state.castIcon = nil, nil
Fire(caster, "UNIT_SPELLCAST_STOP")
Check(ModelOf(caster).shown == true and caster.portrait._msufShown == false, "cast stop did not restore the model")

-- Render switches: 3D -> 2D resolves the native portrait, back reuses the model.
calls, before = state.nativeCalls, state.setUnits
target.MSUFSpec.portrait.render = "2D"
Portrait.Apply(target, target.MSUFSpec)
Check(state.nativeCalls == calls + 1 and ModelOf(target).shown == false and target.portrait._msufShown == true,
  "switch to 2D did not hand back to the native portrait")
target.MSUFSpec.portrait.render = "3D"
Portrait.Apply(target, target.MSUFSpec)
Check(ModelOf(target).shown == true and state.setUnits == before, "switch back to 3D rebound an unchanged model")

-- Layout: shape inset, camera and pan come from the compiled spec.
local shaped = NewFrame("targettarget", { shape = "CIRCLE", modelInset = 0.70, modelCamScale = 0.75,
  modelPanX = 1, modelPanY = -1, modelFacing = 0.5, border = { style = "SOLID", thickness = 2, art = "FLAT" } })
local m = ModelOf(shaped)
Check(m.points.TOPLEFT[1] == 6 and m.points.TOPLEFT[2] == -6, "circle inset not applied")
Check(m.camScale == 0.75 and m.facing == 0.5, "camera numbers not replayed")
Check(m.transX == -(28 * 0.25) and m.transY == 28 * 0.25, "pan translation wrong")
local holder = shaped.MSUFPortraitHolder
local hole = holder.ringHoleMask
Check(hole and holder.ring.masks[hole] and hole.wrapH == "CLAMP", "3D circle ring lost its hole")
Check(hole.image:find("portrait_model_hole_circle", 1, true) ~= nil, "wrong hole art")
shaped.MSUFSpec.portrait.render = "2D"
Portrait.Apply(shaped, shaped.MSUFSpec)
Check(not holder.ring.masks[hole], "2D ring kept the 3D hole")

-- Preview scenes bind the sample unit (or the player) once per identity.
local scene = NewWidget()
scene.MSUFUnitKey = "target"
scene.MSUFSpec = Spec("target")
Portrait.Create(scene)
before = state.setUnits
Portrait.SceneApply(scene, scene.MSUFSpec)
Check(ModelOf(scene).unit == "player" and state.setUnits == before + 1, "scene without a sample unit needs the player")
for _ = 1, 10 do Portrait.SceneApply(scene, scene.MSUFSpec) end
Check(state.setUnits == before + 1 and scene.portrait._msufShown == false, "slider repaint reloaded the scene model")
scene._msufSamplePortraitUnit = "target"
Portrait.SceneApply(scene, scene.MSUFSpec)
Check(ModelOf(scene).unit == "target" and state.setUnits == before + 2, "live sample unit not bound")

-- Disabling every 3D portrait releases the combat rule.
-- Background behind the model: the custom colour, the class colour of a player,
-- the reaction colour; NPCs in class mode and secret reactions keep the custom
-- colour, and unit changes repaint only the dynamic tints.
local function Bg(frame)
  local bg = frame.MSUFPortraitHolder.bg
  return bg._msufShown == true, bg._msufVertexR, bg._msufVertexG, bg._msufVertexB, bg._msufVertexA
end
local function BgSpec(mode)
  return { bg = { enabled = true, r = 0.1, g = 0.2, b = 0.3, a = 0.5, mode = mode, dynamic = mode ~= "CUSTOM" } }
end
state.players, state.reaction, state.guid = { player = true }, 2, "BG1"
local bgClass = NewFrame("player", BgSpec("CLASS"))
local bgNpc = NewFrame("targettarget", BgSpec("CLASS"))
local bgReaction = NewFrame("target", BgSpec("REACTION"))
local bgCustom = NewFrame("focus", BgSpec("CUSTOM"))
local shown, r, g, b, a = Bg(bgClass)
Check(shown and r == 0.25 and g == 0.78 and b == 0.92 and a == 0.5, "class background did not use the class colour")
Check(ModelOf(bgClass).shown == true, "background hid the 3D model")
shown, r, g, b = Bg(bgNpc)
Check(shown and r == 0.1 and g == 0.2 and b == 0.3, "an NPC in class mode left the custom colour")
shown, r, g, b = Bg(bgReaction)
Check(shown and r == 1 and g == 0 and b == 0, "hostile reaction background is not red")
shown, r, g, b = Bg(bgCustom)
Check(shown and r == 0.1 and g == 0.2 and b == 0.3 and a == 0.5, "custom background colour wrong")
state.reaction = 5
Fire(bgReaction, "PLAYER_TARGET_CHANGED")
shown, r, g, b = Bg(bgReaction)
Check(r == 0 and g == 1 and b == 0, "reaction background did not follow the new target")
state.reaction = Secrets.New("number")
Fire(bgReaction, "PLAYER_TARGET_CHANGED")
shown, r, g, b = Bg(bgReaction)
Check(shown and r == 0.1 and g == 0.2 and b == 0.3, "a secret reaction did not fall back to the custom colour")
state.reaction = 4
Fire(bgReaction, "UNIT_FACTION")
shown, r, g, b = Bg(bgReaction)
Check(r == 1 and g == 0.6 and b == 0, "faction change did not repaint the reaction background")
bgCustom.MSUFSpec.portrait.bg.enabled = false
Portrait.Apply(bgCustom, bgCustom.MSUFSpec)
Check(Bg(bgCustom) == false, "disabled background stayed visible")
-- Only a reaction tint (border or background) listens to UNIT_FACTION.
local function HasEvent(list, name)
  for i = 1, #list do if list[i] == name then return true end end
  return false
end
Check(HasEvent(Portrait.GetEvents(bgReaction, bgReaction.MSUFSpec), "UNIT_FACTION"),
  "a reaction background does not register UNIT_FACTION")
Check(not HasEvent(Portrait.GetEvents(bgClass, bgClass.MSUFSpec), "UNIT_FACTION"),
  "a class background registered UNIT_FACTION")
-- A cast does not change the unit, so it never repaints the tint.
local paints = bgReaction.MSUFPortraitHolder.bg
local vertex = paints.SetVertexColor
local castPaints = 0
paints.SetVertexColor = function(...) castPaints = castPaints + 1 return vertex(...) end
paints._msufVertexR = nil
Fire(bgReaction, "UNIT_SPELLCAST_START")
Fire(bgReaction, "UNIT_SPELLCAST_STOP")
Check(castPaints == 0, "cast events repainted the reaction background")
paints.SetVertexColor = vertex
state.players, state.reaction = nil, nil
for _, frame in ipairs({ bgClass, bgNpc, bgReaction, bgCustom }) do Portrait.Disable(frame) end

-- Target of target, focus target and pet target get every unit's model events;
-- the route refreshes them only for their own unit (or an answer it cannot read).
do
  local route = assert(routes["portrait-dependent-model"], "dependent model route not registered")
  Check(route.events.UNIT_PORTRAIT_UPDATE and route.events.UNIT_MODEL_CHANGED, "dependent route events")
  local calls = {}
  local function Update(_, ev, unit) calls[#calls + 1] = ev .. ":" .. tostring(unit) end
  Check(route.compile({}, "UNIT_MODEL_CHANGED", { Update, false }, nil) == nil, "route claimed a frame's own events")
  Check(route.compile({}, "UNIT_MODEL_CHANGED", { Update, false }, "party1") == nil, "route claimed a non-dependent unit")
  local path = assert(route.compile({}, "UNIT_MODEL_CHANGED", { Update, false }, "targettarget"))
  local self = { MSUFUnitKey = "targettarget" }
  path(self, "UNIT_MODEL_CHANGED", "nameplate3")
  Check(#calls == 0, "another unit's model change refreshed the target of target")
  state.sameUnits = { player = "targettarget" }
  path(self, "UNIT_PORTRAIT_UPDATE", "player")
  Check(#calls == 1 and calls[1] == "UNIT_PORTRAIT_UPDATE:targettarget", "the dependent unit's own change was dropped")
  state.unitIsUnitSecret = true
  path(self, "UNIT_MODEL_CHANGED", "nameplate3")
  Check(#calls == 2, "a secret UnitIsUnit answer must still refresh")
  state.unitIsUnitSecret, state.sameUnits = nil, nil
  path(self, "UNIT_MODEL_CHANGED", Secrets.New("string"))
  Check(#calls == 3, "a secret payload must still refresh")
end

for _, frame in ipairs(fallbackFrames) do Portrait.Disable(frame) end
for _, frame in ipairs(keepFrames) do Portrait.Disable(frame) end
Portrait.Disable(caster)
registered = Model.RuleState()
Check(registered == false, "combat rule stayed registered without 3D portraits")
Check(ModelOf(target).shown == false, "disable left the model visible")

-- Compiler: "3D" survives normalization and bakes camera, pan, facing and inset.
do
  local providers = {}
  local sharedCore = { UF = {
    NumberWithFallback = function(value, fallback) return tonumber(value) or fallback end,
    Clamp01 = function(value, fallback)
      value = tonumber(value) or fallback
      return value < 0 and 0 or value > 1 and 1 or value
    end,
  } }
  sharedCore.ExportPublic = function(name, value) providers[name] = value end
  sharedCore.Optional = function() return nil end
  sharedCore.Require = function(name) return providers[name] or function() end end
  local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua"))
  chunk("MidnightSimpleUnitFrames", sharedCore)
  local Shared = sharedCore.UF.Shared
  Check(Shared.NormalizePortraitRender("3D") == "3D" and Shared.NormalizePortraitRender("CLASS") == "CLASS"
    and Shared.NormalizePortraitRender("model") == "2D", "render normalization")
  local p = { render = "3D", shape = "DIAMOND", flip = true }
  Shared.CompilePortraitModel(p, 300, 50, -100)
  Check(p.modelCamScale == 0.5 and p.modelPanX == 0.5 and p.modelPanY == -1, "zoom/pan not baked")
  Check(p.modelFacing == 0.5 and p.modelInset == 0.49, "flip/inset not baked")
  -- 3D rotation turns the head on top of Flip's quarter turn, clamped to +-180.
  Shared.CompilePortraitModel(p, 100, 0, 0, 90)
  Check(math.abs(p.modelFacing - (0.5 + math.pi / 2)) < 1e-9, "3D rotation not added to the facing")
  p.flip = false
  Shared.CompilePortraitModel(p, 100, 0, 0, -720)
  Check(math.abs(p.modelFacing + math.pi) < 1e-9, "3D rotation not clamped")
  Shared.CompilePortraitModel(p, 100, 0, 0, "bogus")
  Check(p.modelFacing == 0, "unknown 3D rotation not reset")
  Check(Shared.NormalizePortraitBgColorMode("CLASS") == "CLASS" and Shared.NormalizePortraitBgColorMode("x") == "CUSTOM",
    "background mode normalization")
  Check(Shared.PortraitBgAlpha(40, 0.85) == 0.4 and Shared.PortraitBgAlpha(nil, 0.85) == 0.85
    and Shared.PortraitBgAlpha(250, nil) == 1, "background opacity resolution")
  p.render = "2D"
  Shared.CompilePortraitModel(p, 300, 50, -100)
  Check(p.modelCamScale == nil and p.modelInset == nil, "2D spec kept 3D camera fields")
end

Check(state.canSetCalls == 0, "CanSetUnit must not gate the model")
local violations = stopModelSecrets()
for _, v in ipairs(stopElementSecrets()) do violations[#violations + 1] = v end
Check(#violations == 0, "secret misuse: " .. table.concat(violations, "\n"))
print("portrait_model_3d_smoke: ok (" .. flavor .. ", " .. checks .. " checks)")
