-- Model bursts use the real portrait element and next-frame scheduler.
-- Native calls are counted; native rendering, combat and taint need an in-game check.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
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
function Widget:IsShown() return self.shown end
function Widget:SetTexture(value)
  Check(Secrets.IsSecret(value) or type(value) ~= "string" or not value:match("^RTPortrait"), "render target replay")
  self.image = value
end
function Widget:SetTexCoord(l, r, t, b) self.l, self.r, self.t, self.b = l, r, t, b end
function Widget:SetSize(width, height) self.width, self.height = width, height end
function Widget:GetWidth() return self.width end
function Widget:GetHeight() return self.height end
function Widget:GetFrameLevel() return self.level end
function Widget:SetFrameLevel(level) self.level = level end
function Widget:GetTexture() error("portrait render targets must not be read back") end
for _, name in ipairs({ "EnableMouse", "SetAllPoints", "SetVertexColor", "ClearAllPoints", "SetPoint", "SetAlpha",
  "RegisterEvent", "UnregisterEvent", "SetSnapToPixelGrid", "SetTexelSnappingBias" }) do Widget[name] = Noop end
local function NewWidget(parent)
  return setmetatable({ parent = parent, scripts = {}, hooks = {}, shown = true, width = 200, height = 40, level = 1 },
    { __index = Widget })
end
function Widget:CreateTexture() return NewWidget(self) end
local state = { identity = "A", guid = "A", connected = true, visible = true, exists = true,
  calls = 0, guidReads = 0, castReads = 0, channelReads = 0 }
local env = setmetatable({}, { __index = _G })
env._G = env
env.CreateFrame = function(_, _, parent) return NewWidget(parent) end
env.GetTime = function() return 1 end
-- Delayed timers are outside this test; model refreshes must use the next-frame driver.
env.C_Timer = { After = function() error("unexpected delayed timer") end }
env.UnitGUID = function() state.guidReads = state.guidReads + 1 return state.guid end
env.UnitExists = function() return state.exists end
env.UnitIsConnected = function() return state.connected end
env.UnitIsVisible = function() return state.visible end
env.UnitClass = function() return "Mage", "MAGE" end
env.UnitCastingInfo = function() state.castReads = state.castReads + 1 return state.castName, nil, state.castIcon end
env.UnitChannelInfo = function() state.channelReads = state.channelReads + 1 return state.channelName, nil, state.channelIcon end
env.SetPortraitTexture = function(texture, unit, bust)
  state.calls = state.calls + 1
  texture.calls = (texture.calls or 0) + 1
  texture.image = state.placeholder and "placeholder" or "RTPortrait:" .. state.identity
  texture.nativeUnit, texture.bust = unit, bust
  texture.l, texture.r, texture.t, texture.b = 0, 1, 0, 1
end
local events, dependencies = {}, {}
local core = { Client = { IsVanilla = flavor == "Vanilla" }, PublicGlobals = {}, UF = {} }
core.ExportPublic = function(name, value) dependencies[name] = value end
core.Require = function(name) return assert(dependencies[name], "missing provider " .. name) end
core.PortraitDetails = { ApplyShadow = Noop, DragonAllowed = function() return false end,
  UnitlessEvents = function(events) return events end }
local classVisual = { texture = "class:MAGE" }
core.PortraitMedia = { ResolveClassPortrait = function() return classVisual end }
core.UFVisuals = { UF = core.UF, SetShown = function(region, shown)
  if region and region._msufShown ~= shown then
    region._msufShown = shown
    if shown then region:Show() else region:Hide() end
  end
end }
dependencies.MSUF_PixelLayoutRegion = function(region) return region end
dependencies.MSUF_EventBus_Register = function(event, key, callback) events[key] = callback return true end
dependencies.MSUF_EventBus_Unregister = function(event, key) events[key] = nil end
local Portrait
core.UF.RegisterElement = function(name, element) Check(name == "Portrait", "wrong element") Portrait = element end
local function Load(path)
  local chunk = assert(loadfile(root .. "/" .. path))
  setfenv(chunk, env)
  chunk("MidnightSimpleUnitFrames", core)
end
Load("MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua")
local owned = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Portrait.lua"
Load("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Portrait.lua")
local stopSecrets = Secrets.Watch(owned, { strict = true })
local function Flush()
  local driver = core.Scheduler.frame
  if driver.scripts.OnUpdate then driver.scripts.OnUpdate(driver, 0.016) end
  Check(driver.scripts.OnUpdate == nil, "portrait scheduler must disarm after the burst")
end
local function NewFrame(unit, cast)
  local frame = NewWidget()
  frame.MSUFUnitKey, frame._msufCoreVisible = unit or "target", true
  frame.MSUFSpec = { key = unit or "target", height = 40,
    portrait = { enabled = true, render = "2D", shape = "SQUARE", castSpellIcon = cast,
      texL = 0.1, texR = 0.9, texT = 0.2, texB = 0.8, border = { style = "NONE" } } }
  Portrait.Create(frame)
  Portrait.Apply(frame, frame.MSUFSpec)
  return frame
end
local function Fire(frame, event) Portrait.Update(frame, event, frame.MSUFUnitKey) end
local function Burst(frame)
  Fire(frame, "UNIT_MODEL_CHANGED")
  Fire(frame, "UNIT_PORTRAIT_UPDATE")
  Fire(frame, "PORTRAITS_UPDATED")
end
local frame = NewFrame()
local before = state.calls
local reads = state.guidReads
Burst(frame)
Flush()
Check(state.calls - before == 1, "model burst must perform exactly one native portrait apply")
Check(state.guidReads - reads == 1, "model burst must resolve its current identity once")
Check(frame._msufPortraitAppliedRevision == frame._msufPortraitModelRevision, "latest public revision not applied")
Check(frame.portrait.l == 0.1 and frame.portrait.b == 0.8, "native refresh lost crop")
before = state.calls
Burst(frame)
Check(state.calls == before, "model invalidation must wait until the next render interval")
Flush()
Check(state.calls == before + 1, "a later model burst must not be dropped")

-- Initial config application on a hidden frame must also wait for OnShow.
local hidden = NewWidget()
hidden.MSUFUnitKey, hidden._msufCoreVisible = "boss1", false
hidden.MSUFSpec = { key = "boss", portrait = { enabled = true, render = "2D", shape = "SQUARE" } }
hidden:Hide()
before = state.calls
Portrait.Create(hidden)
Portrait.Apply(hidden, hidden.MSUFSpec)
Check(state.calls == before, "initial hidden config rendered a portrait")
state.identity, state.guid = "hidden-boss", "hidden-boss"
hidden._msufCoreVisible = true
hidden:Show()
Check(state.calls == before + 1 and hidden.portrait.image == "RTPortrait:hidden-boss", "initial hidden OnShow failed")
state.identity, state.guid = "A", "A"

-- Two owners of the same token each need their own native texture binding.
local otherTarget = NewFrame("target")
before = state.calls
Burst(frame)
Burst(otherTarget)
Flush()
Check(state.calls == before + 2, "different frames must not share one portrait application")

-- A queued refresh that becomes hidden must retain the existing OnShow repair.
before = state.calls
Burst(frame)
frame._msufCoreVisible = false
frame:Hide()
Flush()
Check(state.calls == before, "hidden frame performed native portrait work")
state.identity, state.guid = "B", "B"
Burst(frame)
Flush()
Check(state.calls == before, "hidden invalidations performed native portrait work")
Check(frame._msufPortraitNeedsVisibleRefresh == true, "hidden refresh lost OnShow repair")
frame._msufCoreVisible = true
frame:Show()
Check(state.calls == before + 1 and frame.portrait.image == "RTPortrait:B", "OnShow did not reseed latest identity")
Flush()
Check(state.calls == before + 1, "OnShow left a stale refresh queued")

-- A hidden ancestor leaves IsShown true; Core's OnHide flag is authoritative.
before = state.calls
Burst(frame)
frame._msufCoreVisible = false
Check(frame:IsShown() and frame.MSUFPortraitHolder:IsShown(), "hidden-parent fixture drift")
Flush()
Check(state.calls == before, "parent-hidden frame performed native portrait work")
frame._msufCoreVisible = true
Fire(frame, "MSUF_UF_ONSHOW")
Check(state.calls == before + 1, "core identity pass did not reseed hidden-parent portrait")
Flush()
Check(state.calls == before + 1, "core OnShow left a duplicate portrait apply")

-- Direct identities consume pending model work and never replay A's render target.
before = state.calls
Burst(frame)
state.identity, state.guid = "A", "A"
Fire(frame, "PLAYER_TARGET_CHANGED")
Check(state.calls == before + 1 and frame.portrait.image == "RTPortrait:A", "target A must render immediately")
state.identity, state.guid = "B", "B"
Fire(frame, "PLAYER_TARGET_CHANGED")
Check(state.calls == before + 2 and frame.portrait.image == "RTPortrait:B", "target B must render immediately")
state.identity, state.guid = "A", "A"
Fire(frame, "PLAYER_TARGET_CHANGED")
Check(state.calls == before + 3 and frame.portrait.image == "RTPortrait:A", "returning target A must resolve anew")
Flush()
Check(state.calls == before + 3, "identity refresh did not cancel obsolete model work")

-- Streaming placeholders are retried on the next public model revision.
state.placeholder = true
before = state.calls
Burst(frame)
Flush()
Check(state.calls == before + 1 and frame.portrait.image == "placeholder", "streaming placeholder missing")
state.placeholder = false
Burst(frame)
Flush()
Check(state.calls == before + 2 and frame.portrait.image == "RTPortrait:A", "streamed portrait was cached as placeholder")

-- GUIDs and cast values can be secret. Only public revisions drive the queue.
state.guid = Secrets.New("string")
before = state.calls
Burst(frame)
Flush()
Check(state.calls == before + 1 and frame.portrait._msufPortraitGUID == nil, "secret GUID retained")
state.guid = "A"
local caster = NewFrame("player", true)
local castReads, channelReads = state.castReads, state.channelReads
before = state.calls
Fire(caster, "UNIT_MODEL_CHANGED")
Flush()
Check(state.calls == before + 1, "single model event did not render")
Check(state.castReads == castReads + 1 and state.channelReads == channelReads + 1, "queued model refresh re-read cast natives")
before = state.calls
Burst(caster)
state.castName, state.castIcon = Secrets.New("string"), Secrets.New("number")
Fire(caster, "UNIT_SPELLCAST_START")
Check(caster._msufPortraitCastIconActive == true and caster.portrait._msufShown == false, "cast icon was delayed")
Flush()
Check(state.calls == before, "model refresh rendered under active cast icon")
state.castName, state.castIcon = nil, nil
Fire(caster, "UNIT_SPELLCAST_STOP")
Check(state.calls == before + 1 and caster.portrait._msufShown == true, "cast stop failed immediate portrait restore")
Flush()
Check(state.calls == before + 1, "cast restore left duplicate model work")

-- Disabling cancels the pending request; re-enabling still seeds native art.
before = state.calls
Burst(frame)
Check(frame._msufPortraitQueuedRevision ~= nil, "disable fixture did not queue model work")
Portrait.Disable(frame)
Check(frame._msufPortraitQueuedRevision == nil, "disable did not cancel the queued revision immediately")
Flush()
Check(state.calls == before, "disabled portrait applied queued model work")
Portrait.Apply(frame, frame.MSUFSpec)
Check(state.calls == before + 1 and frame.portrait.image == "RTPortrait:A", "re-enable failed to render")
Burst(frame)
Portrait.Disable(frame)
Portrait.Apply(frame, frame.MSUFSpec)
before = state.calls
Flush()
Check(state.calls == before, "disable/re-enable retained an old callback request")
Burst(frame)
Flush()
Check(state.calls == before + 1, "re-enable lost future refreshes")

-- A config switch consumes stale queued work, including scene previews.
Burst(frame)
frame.MSUFSpec.portrait.render = "CLASS"
Portrait.Apply(frame, frame.MSUFSpec)
before = state.calls
Flush()
Check(state.calls == before and frame.portrait.image == "class:MAGE", "class switch replayed native work")
frame.MSUFSpec.portrait.render = "2D"
Portrait.Apply(frame, frame.MSUFSpec)
Burst(frame)
frame._msufSamplePortraitArt = "scene:portrait"
Check(frame._msufPortraitQueuedRevision ~= nil, "scene fixture did not queue model work")
Portrait.SceneApply(frame, frame.MSUFSpec)
Check(frame._msufPortraitQueuedRevision == nil, "scene did not cancel the queued revision immediately")
before = state.calls
Flush()
Check(state.calls == before and frame.portrait.image == "scene:portrait", "scene preview replayed live portrait")

-- Connection and vehicle events keep their synchronous contract.
local vehicle = NewFrame("player")
for _, event in ipairs({ "UNIT_CONNECTION", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }) do
  before = state.calls
  Fire(vehicle, event)
  Check(state.calls == before + 1, event .. " must remain immediate")
end
local violations = stopSecrets()
Check(#violations == 0, "secret misuse: " .. table.concat(violations, "\n"))
print("portrait_model_refresh_smoke: ok (" .. flavor .. ", " .. checks .. " checks)")
