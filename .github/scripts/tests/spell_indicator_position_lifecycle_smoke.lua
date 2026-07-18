-- Regression: group Spell Indicator preview/live anchors stay on the same
-- geometry contract, and world-entry/zone events can repair native AuraSlot
-- point drift without disabling the normal cached geometry fast path.
local root = arg and arg[1] or "."

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function Read(relativePath)
  local file = assert(io.open(root .. "/" .. relativePath, "rb"))
  local text = file:read("*a")
  file:close()
  return text
end

local mockRemaining = 0
local Frame = {}
Frame.__index = Frame

function Frame:GetParent() return self.parent end
function Frame:ClearAllPoints()
  self.clearPointCalls = (self.clearPointCalls or 0) + 1
  self.point = nil
end
function Frame:SetPoint(point, relativeTo, relativePoint, x, y)
  self.setPointCalls = (self.setPointCalls or 0) + 1
  self.point = { point, relativeTo, relativePoint, x or 0, y or 0 }
end
function Frame:SetAllPoints(relativeTo) self.allPoints = relativeTo or true end
function Frame:SetSize(width, height)
  self.setSizeCalls = (self.setSizeCalls or 0) + 1
  self.width, self.height = width, height
end
function Frame:GetFrameLevel() return self.frameLevel or 0 end
function Frame:SetFrameLevel(level) self.frameLevel = level end
function Frame:GetFrameStrata() return self.frameStrata or "MEDIUM" end
function Frame:SetFrameStrata(strata) self.frameStrata = strata end
function Frame:SetAlpha(alpha) self.alpha = alpha end
function Frame:SetVertexColor() end
function Frame:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a } end
function Frame:GetTextColor()
  local color = self.textColor or { 1, 1, 1, 1 }
  return color[1], color[2], color[3], color[4]
end
function Frame:SetText(value) self.text = value end
function Frame:GetText() return self.text or "" end
function Frame:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function Frame:SetFont() end
function Frame:GetJustifyH() return "LEFT" end
function Frame:GetJustifyV() return "MIDDLE" end
function Frame:SetJustifyH() end
function Frame:SetJustifyV() end
function Frame:GetShadowColor() return 0, 0, 0, 1 end
function Frame:GetShadowOffset() return 1, -1 end
function Frame:SetShadowColor() end
function Frame:SetShadowOffset() end
function Frame:SetTexture() end
function Frame:SetTexCoord() end
function Frame:SetDesaturated() end
function Frame:SetBlendMode() end
function Frame:GetStatusBarTexture() return self.statusBarTexture end
function Frame:SetHeight(height) self.height = height end
function Frame:SetWidth(width) self.width = width end
function Frame:SetScript(script, handler) self.scripts = self.scripts or {}; self.scripts[script] = handler end
function Frame:GetScript(script) return self.scripts and self.scripts[script] or nil end
function Frame:Show()
  local changed = self.shown ~= true
  self.shown = true
  local effectivelyShown = true
  local parent = self.parent
  while parent do
    if parent.shown ~= true then effectivelyShown = false; break end
    parent = parent.parent
  end
  if changed and effectivelyShown and self:GetScript("OnShow") then self:GetScript("OnShow")(self) end
end
function Frame:Hide()
  local changed = self.shown == true
  self.shown = false
  if changed and self:GetScript("OnHide") then self:GetScript("OnHide")(self) end
end
function Frame:EnableMouse() end
function Frame:SetMouseMotionEnabled() end
function Frame:ClearIcon() end
function Frame:ClearApplicationCount() self.clearApplicationCountCalls = (self.clearApplicationCountCalls or 0) + 1 end
function Frame:ClearDurationCooldown() self.clearDurationCooldownCalls = (self.clearDurationCooldownCalls or 0) + 1 end
function Frame:ClearDurationText()
  self.clearDurationTextCalls = (self.clearDurationTextCalls or 0) + 1
  self.durationText = nil
end
function Frame:ClearDurationBar()
  self.clearDurationBarCalls = (self.clearDurationBarCalls or 0) + 1
  self._mockPrivateDurationBar = nil
end
function Frame:ClearAuraBorder() end
function Frame:ClearAuraSymbol() end
function Frame:CreateTexture() return NewFrame(self) end
function Frame:CreateFontString() return NewFrame(self) end
function Frame:GetTimerDuration() return self.timerDuration end
function Frame:SetTimerDuration(duration) self.timerDuration = duration end
function Frame:CreateAnimationGroup()
  local group = { playing = false }
  function group:SetLooping() end
  function group:IsPlaying() return self.playing == true end
  function group:Play() self.playing = true end
  function group:Stop() self.playing = false end
  function group:CreateAnimation()
    return setmetatable({}, {
      __index = function()
        return function() end
      end,
    })
  end
  return group
end

function NewFrame(parent)
  return setmetatable({ parent = parent, shown = true, frameLevel = 20, frameStrata = "MEDIUM" }, Frame)
end

local function NewHealthBar(parent)
  local bar = NewFrame(parent)
  local fill = NewFrame(bar)
  bar.statusBarTexture = fill
  return bar, fill
end

local createdFrames = {}
_G.CreateFrame = function(_, _, parent)
  local frame = NewFrame(parent)
  createdFrames[#createdFrames + 1] = frame
  return frame
end
_G.hooksecurefunc = function(target, method, hook)
  local original = assert(target[method], "mock secure hook target missing")
  target[method] = function(self, ...)
    original(self, ...)
    hook(self, ...)
  end
end
_G.issecretvalue = function() return false end
_G.Enum = {
  LuaCurveType = { Step = 1 },
  StatusBarInterpolation = { Immediate = 0 },
  StatusBarTimerDirection = { RemainingTime = 1 },
}
local Curve = {}
Curve.__index = Curve
function Curve:SetType(curveType) self.curveType = curveType end
function Curve:AddPoint(x, value) self.points[#self.points + 1] = { x, value } end
function Curve:Evaluate(x)
  local value = self.points[1] and self.points[1][2] or 0
  for i = 1, #self.points do
    if x < self.points[i][1] then break end
    value = self.points[i][2]
  end
  return value
end
_G.C_CurveUtil = {
  CreateCurve = function() return setmetatable({ points = {} }, Curve) end,
}
_G.MSUF_FRAME_STRATA_RANK = {
  BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
  FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}
local mockDuration = {
  EvaluateRemainingDuration = function(_, curve) return curve:Evaluate(mockRemaining) end,
}
function Frame:SetDurationBar(bar, options)
  self.setDurationBarCalls = (self.setDurationBarCalls or 0) + 1
  -- Blizzard stores this ownership in the forbidden/private button partition.
  -- Do not expose a public DurationBar field in the mock.
  self._mockPrivateDurationBar = bar
  self._mockPrivateDurationBarOptions = options
  bar:SetTimerDuration(mockDuration)
  -- PTR makes the delegated StatusBar forbidden immediately. Any later method
  -- access reproduces the live error reported by the client.
  bar.GetTimerDuration = function()
    error("attempt to access forbidden delegated StatusBar", 2)
  end
end
local MSUF = { MSUF_Auras3 = {}, UF = {} }
_G.MSUF_NS = MSUF
local layersChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Layers.lua"))
layersChunk("MidnightSimpleUnitFrames", MSUF)
local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)

local Runtime = assert(MSUF.MSUF_Auras3.SpellIndicators)
local Layers = assert(MSUF.UF.Layers)
Check(Layers.SPELL_FRAME_EFFECT_BASE_OFFSET + 10 < Layers.DISPEL_OVERLAY_EFFECT_OFFSET,
  "strongest Spell frame effect is not below the Dispel overlay AUTO level")
Check(Layers.DISPEL_OVERLAY_EFFECT_OFFSET < Layers.TEXT_BASE_OFFSET + 5,
  "health effects escaped above the default text layer")
-- Imported filters must never pass unknown components to Blizzard's asserted
-- AuraUtil.IsValidFilterString boundary.
local compiled = assert(Runtime.CompileSlots("party1", {
  enabled = true,
  items = {{
    enabled = true,
    nativeFilter = "HELPFUL|BOGUS|!PLAYER|!HARMFUL",
    includeSpellIDs = { [355941] = true },
    placed = { type = "icon", anchor = "BOTTOMRIGHT", x = 17, y = -9, size = 23 },
  }},
}))
Equal(compiled.slots[1].nativeFilter, "HELPFUL|!PLAYER", "invalid native filter tokens survived normalization")

-- Native button recreation must not resurrect pre-edit geometry. The
-- initializeFrame closure outlives config edits (it runs on every aura
-- reapplication), so it has to prepare with the container's CURRENT slot,
-- not the compiled slot table captured when the container was created.
do
  local capturedOptions = {}
  Runtime.Install({
    ValidateAuraButton = function() end,
    PrepareAuraButton = function(button, slot)
      if slot.showCooldownText == true then
        button.visibleDurationTextOwned = true
      end
    end,
    EnsureLoaded = function() return true end,
    CreateContainer = function(containerRoot)
      local c = NewFrame(containerRoot)
      c.AddAuraSlot = function(_, slotKey, _, options)
        capturedOptions[slotKey] = options
      end
      return c
    end,
    ConfigureContainer = function() end,
    RegisterContainer = function() return true end,
    HideContainer = function() end,
  })

  local function LiveSlot(x)
    return {
      slotKey = "msuf_si_live", itemKey = "spec:aura", display = "aura",
      unit = "party1", enabled = true,
      nativeFilter = "HELPFUL|PLAYER",
      candidateFilters = { includeSpellIDs = { [355941] = true } },
      candidateFilterSignature = "includeSpellIDs:355941",
      visual = "icon", hiddenVisual = false, showWhenMissing = false,
      color = { 1, 1, 1, 1 }, iconEffect = "none",
      size = 20, width = 20, height = 20,
      anchor = "BOTTOMLEFT", x = x, y = 1,
      layer = 9, strata = "AUTO",
      showCooldownText = true, showCooldownSwipe = true, showStacks = true,
    }
  end
  local function LiveRoot(x, layoutTag)
    return {
      spellIndicatorRoot = true, kind = "spellIndicators", rootKey = "SpellIndicators",
      unit = "party1", enabled = true, max = 1, layer = 9, strata = "AUTO",
      slots = { LiveSlot(x) },
      _msufA3TrackingSignature = "track-1",
      _msufA3StructuralSignature = "struct-" .. layoutTag,
      _msufA3LayoutSignature = layoutTag,
    }
  end

  local liveParent = NewFrame(nil)
  local liveAuraRoot = NewFrame(liveParent)
  local liveContainer = assert(Runtime.Apply(liveAuraRoot, LiveRoot(17, "layout-a"), liveParent),
    "live container creation failed")
  local options = assert(capturedOptions.msuf_si_live, "AddAuraSlot options were not captured")

  local button1 = NewFrame(liveContainer)
  button1.Icon = NewFrame(button1)
  options.initializeFrame(button1)
  Equal(button1.point and button1.point[4], 17, "initial native button X")

  -- Config edits are structural on PTR: replace the native container rather
  -- than mutating an initialized forbidden AuraButton.
  local editedContainer = assert(Runtime.Apply(liveAuraRoot, LiveRoot(40, "layout-b"), liveParent),
    "structural edit did not create a replacement container")
  Check(editedContainer ~= liveContainer, "structural edit reused the native container")
  local editedOptions = assert(capturedOptions.msuf_si_live, "replacement AddAuraSlot options were not captured")
  local editedButton = NewFrame(editedContainer)
  editedButton.Icon = NewFrame(editedButton)
  editedOptions.initializeFrame(editedButton)
  Equal(editedButton.point and editedButton.point[4], 40, "edited X did not reach the replacement button")

  -- Aura reapplication: native recreates the slot button through the closure
  -- captured at container creation. It must use the edited slot, not x=17.
  local button2 = NewFrame(editedContainer)
  button2.Icon = NewFrame(button2)
  editedOptions.initializeFrame(button2)
  Equal(button2.point and button2.point[4], 40,
    "recreated native button resurrected pre-edit geometry")
  Equal(editedContainer._msufA3SpellIndicatorButtonSlots[1].x, 40,
    "recreated native button re-installed the stale slot table")

  -- World-transition recovery follows the same safe replacement path. A
  -- direct SyncGeometry pass must leave the request pending while a native
  -- button exists; Runtime.Recreate consumes it by replacing the container.
  editedContainer[1] = editedButton
  editedContainer._msufA3ForceSpellIndicatorGeometry = true
  local pointCalls = editedButton.setPointCalls or 0
  Check(Runtime.SyncGeometry(editedContainer, LiveRoot(40, "layout-b"), liveParent, true) == true,
    "pending recovery sync failed")
  Equal(editedButton.setPointCalls or 0, pointCalls, "recovery touched an initialized native AuraButton")
  Equal(editedContainer._msufA3ForceSpellIndicatorGeometry, true, "recovery request was cleared without replacement")
  local recoveredContainer = assert(Runtime.Recreate(editedContainer), "safe recovery did not recreate the container")
  Check(recoveredContainer ~= editedContainer, "safe recovery returned the stale container")
  Equal(recoveredContainer._msufA3ForceSpellIndicatorGeometry, nil, "replacement retained the recovery marker")

  -- Expiration timing stays secret-safe: the duration object evaluates a
  -- public step curve and the frame consumes only the resulting alpha. Build
  -- it while the owner is hidden to ensure driver registration does not rely
  -- on an OnShow transition that Blizzard cannot deliver yet.
  local timedParent = NewFrame(nil)
  timedParent:Hide()
  local timedHealthFill
  timedParent.hpBar, timedHealthFill = NewHealthBar(timedParent)
  Check(timedHealthFill ~= timedParent.hpBar,
    "expiration smoke did not model a distinct StatusBar fill")
  timedParent.nameText = NewFrame(timedParent)
  timedParent.nameText:SetText("Initial Name")
  local timedAuraRoot = NewFrame(timedParent)
  local timedRoot = assert(Runtime.CompileSlots("party1", {
    enabled = true,
    items = {{
      enabled = true,
      key = "timed:aura",
      includeSpellIDs = { [355941] = true },
      placed = {
        type = "icon", anchor = "BOTTOMLEFT", x = 0, y = 1, size = 20,
        iconEffect = "glow",
        showCooldown = true, showCooldownSwipe = true, showStacks = true,
      },
      frame = {
        type = "namecolor", timing = "expiring", expireThreshold = 5,
        priority = 1, strata = "AUTO",
        color = { 0.56, 0.93, 0.56, 0.8 },
      },
    }},
  }), "timed Spell Indicator root did not compile")
  Equal(#timedRoot.slots, 2, "timed frame effect did not receive an isolated expiration sensor")
  Equal(timedRoot.slots[1].iconEffect, "glow",
    "visible icon lost its normal animated glow")
  Equal(timedRoot.slots[2].iconEffect, "none",
    "frame-effect sensor unexpectedly received an icon glow")
  local timedContainer = assert(Runtime.Apply(timedAuraRoot, timedRoot, timedParent),
    "timed-effect container creation failed")
  local visibleOptions = assert(capturedOptions[timedRoot.slots[1].slotKey],
    "visible timed-icon AddAuraSlot options were not captured")
  local sensorOptions = assert(capturedOptions[timedRoot.slots[2].slotKey],
    "expiration-sensor AddAuraSlot options were not captured")
  local visibleButton = NewFrame(timedContainer)
  visibleButton.Icon = NewFrame(visibleButton)
  visibleOptions.initializeFrame(visibleButton)
  Equal(visibleButton.visibleDurationTextOwned, true,
    "visible timed icon lost its normal duration-text owner")
  Equal(visibleButton.clearDurationTextCalls or 0, 0,
    "expiration setup cleared the visible icon's duration text")
  Equal(visibleButton.clearDurationCooldownCalls or 0, 0,
    "expiration setup cleared the visible icon's cooldown swipe")
  Equal(visibleButton.clearDurationBarCalls or 0, 0,
    "expiration setup cleared the visible icon's duration bar")
  Equal(visibleButton.clearApplicationCountCalls or 0, 0,
    "expiration setup cleared the visible icon's aura stacks")
  Check(visibleButton._msufA3SpellIndicatorIconEffectRoot ~= nil,
    "visible icon did not create its normal animated glow")
  Equal(timedParent._msufA3SpellIndicatorExpiringEffectGates, nil,
    "visible icon incorrectly created the expiration gate")
  local sensorButton = NewFrame(timedContainer)
  sensorButton.Icon = NewFrame(sensorButton)
  mockRemaining = 4
  sensorOptions.initializeFrame(sensorButton)
  local durationSensor = sensorButton._msufA3ExpiringEffectDurationBar
  Check(durationSensor ~= nil,
    "expiration sensor did not install its native duration StatusBar")
  Equal(sensorButton.DurationBar, nil,
    "expiration smoke incorrectly exposed Blizzard's private DurationBar owner")
  Equal(sensorButton.DurationTextBinding, nil,
    "expiration smoke incorrectly exposed Blizzard's private duration binding")
  Equal(sensorButton._mockPrivateDurationBarOptions.interpolation, 0,
    "expiration StatusBar does not use immediate timer interpolation")
  Equal(sensorButton._mockPrivateDurationBarOptions.direction, 1,
    "expiration StatusBar does not use remaining-time direction")
  Equal(durationSensor.shown, false,
    "expiration StatusBar sensor was left on the render path")
  Equal(durationSensor.alpha, 0,
    "expiration StatusBar sensor became visually visible")
  local firstBindingSetupCalls = sensorButton.setDurationBarCalls
  sensorOptions.initializeFrame(sensorButton)
  Equal(sensorButton.setDurationBarCalls, firstBindingSetupCalls,
    "expiration setup touched the forbidden StatusBar binding a second time")
  Equal(sensorButton._msufA3ExpiringEffectDurationBridge.duration, mockDuration,
    "secure SetTimerDuration hook did not capture Blizzard's LuaDuration")
  local gates = assert(timedParent._msufA3SpellIndicatorExpiringEffectGates,
    "expiring frame-effect gate was not created")
  local gate = next(gates)
  Check(gate ~= nil, "expiring frame-effect gate was not registered")
  Equal(sensorButton._msufA3SpellIndicatorIconEffectRoot, nil,
    "hidden frame-effect sensor created an icon glow")
  Equal(gate.alpha, 1,
    "expiring frame effect was not evaluated immediately during registration")
  local driver
  for i = 1, #createdFrames do
    if createdFrames[i]:GetScript("OnUpdate") then driver = createdFrames[i] end
  end
  Check(driver ~= nil, "expiring frame-effect driver did not start")
  mockRemaining = 10
  driver:GetScript("OnUpdate")(driver, 0.2)
  Equal(gate.alpha, 0, "frame effect activated above its expiration threshold")
  mockRemaining = 4
  timedParent.nameText:SetText("Updated Name")
  driver:GetScript("OnUpdate")(driver, 0.2)
  Equal(gate.alpha, 1, "frame effect did not activate below its expiration threshold")
  local effectRoot = assert(gate._msufA3ExpiringEffectRoot,
    "expiring effect root was not created")
  Equal(gate.allPoints, timedParent.hpBar,
    "expiring effect gate is not attached to the health bar")
  Equal(effectRoot.allPoints, timedParent.hpBar,
    "expiring frame-effect owner is not attached to the health bar")
  Equal(effectRoot.frameLevel,
    timedParent:GetFrameLevel() + Layers.SPELL_FRAME_EFFECT_BASE_OFFSET + 10,
    "strongest Spell frame effect did not use the shared layer contract")
  Equal(effectRoot.frameStrata, timedParent:GetFrameStrata(),
    "AUTO Spell frame effect did not inherit the unit-frame strata")
  local nameOverlay = assert(effectRoot._msufA3SpellIndicatorNameOverlay,
    "expiring Name Color overlay was not created")
  Equal(nameOverlay.text, "Updated Name",
    "expiring Name Color overlay did not follow the current unit name")
  mockRemaining = 0
  driver:GetScript("OnUpdate")(driver, 0.2)
  Equal(gate.alpha, 0, "missing or permanent aura left the expiration effect active")
  Runtime.HideFrameEffects(timedParent)
  Equal(driver:GetScript("OnUpdate"), nil, "expiration driver kept running without active gates")

  -- Profiles can retain removed timer keys. They must be ignored so the
  -- normal animated icon glow remains active after upgrading or reloading.
  local legacyParent = NewFrame(nil)
  local legacyAuraRoot = NewFrame(legacyParent)
  local legacyRoot = assert(Runtime.CompileSlots("party1", {
    enabled = true,
    items = {{
      enabled = true,
      key = "legacy:timed-icon",
      includeSpellIDs = { [355941] = true },
      placed = {
        type = "icon", anchor = "TOPRIGHT", x = -3, y = -2, size = 24,
        iconEffect = "glow", iconEffectTiming = "expiring", iconExpireThreshold = 6,
      },
    }},
  }), "legacy timed-icon profile did not compile")
  Equal(#legacyRoot.slots, 1, "removed icon timer still creates a sensor sibling")
  Equal(legacyRoot.slots[1].iconEffect, "glow", "legacy timer keys disabled the normal icon glow")
  Equal(legacyRoot.slots[1].iconEffectTiming, nil, "legacy icon timing leaked into runtime state")
  local legacyContainer = assert(Runtime.Apply(legacyAuraRoot, legacyRoot, legacyParent),
    "legacy timed-icon container creation failed")
  local legacyOptions = assert(capturedOptions[legacyRoot.slots[1].slotKey],
    "legacy timed-icon options were not captured")
  local legacyButton = NewFrame(legacyContainer)
  legacyButton.Icon = NewFrame(legacyButton)
  legacyOptions.initializeFrame(legacyButton)
  Check(legacyButton._msufA3SpellIndicatorIconEffectRoot ~= nil,
    "legacy timer keys prevented the normal animated glow")
  Equal(legacyButton.setDurationBarCalls, nil,
    "removed icon timer still installed a StatusBar bridge")
  Equal(legacyParent._msufA3SpellIndicatorExpiringEffectGates, nil,
    "removed icon timer still installed a Lua-polled effect gate")
  Equal(driver:GetScript("OnUpdate"), nil,
    "removed icon timer restarted the Lua expiration driver")

  -- Every effect owner stays on the stable HP rectangle while every visible
  -- tint/edge/glow follows the distinct C-side current-health fill.
  local frameEffectKinds = { "healthtint", "border", "glow", "pulse", "namecolor" }
  for i = 1, #frameEffectKinds do
    local kind = frameEffectKinds[i]
    local effectStrata = kind == "border" and "HIGH" or "AUTO"
    local parent = NewFrame(nil)
    local healthFill
    parent.hpBar, healthFill = NewHealthBar(parent)
    parent.nameText = NewFrame(parent)
    parent.nameText:SetText("Name")
    local auraRoot = NewFrame(parent)
    local compiledRoot = assert(Runtime.CompileSlots("party1", {
      enabled = true,
      items = {{
        enabled = true,
        key = "effect:" .. kind,
        includeSpellIDs = { [355941] = true },
        placed = { type = "icon", size = 20, anchor = "TOPLEFT" },
        frame = {
          type = kind, timing = "always", priority = 1, strata = effectStrata,
          layer = i, thickness = 2, color = { 0.2, 0.8, 1, 0.7 },
        },
      }},
    }), kind .. " frame effect did not compile")
    local container = assert(Runtime.Apply(auraRoot, compiledRoot, parent),
      kind .. " frame-effect container creation failed")
    local options = assert(capturedOptions[compiledRoot.slots[1].slotKey],
      kind .. " AddAuraSlot options were not captured")
    local button = NewFrame(container)
    button.Icon = NewFrame(button)
    options.initializeFrame(button)
    local rootFrame = assert(button._msufA3SpellIndicatorEffectRoot,
      kind .. " effect root was not created")
    Equal(rootFrame.allPoints, parent.hpBar,
      kind .. " effect root escaped the health bar")
    Equal(rootFrame.frameLevel,
      parent:GetFrameLevel() + Layers.SPELL_FRAME_EFFECT_BASE_OFFSET + 10 + i,
      kind .. " effect root ignored its compiled 0..30 Layer")
    Equal(rootFrame.frameStrata, effectStrata == "AUTO" and parent:GetFrameStrata() or effectStrata,
      kind .. " effect did not apply its configured strata")
    if kind == "healthtint" then
      Equal(button._msufA3SpellIndicatorHealthTint.allPoints, healthFill,
        "Health Tint did not follow the current-health fill")
    elseif kind == "border" or kind == "pulse" then
      Equal(button._msufA3SpellIndicatorEdges[1].point[2], healthFill,
        kind .. " top edge did not follow the current-health fill")
      Equal(button._msufA3SpellIndicatorEdges[2].point[2], healthFill,
        kind .. " bottom edge did not follow the current-health fill")
    elseif kind == "glow" then
      Equal(rootFrame._msufA3AnimatedGlow.halo.point[2], healthFill,
        "Glow did not follow the current-health fill")
    elseif kind == "namecolor" then
      Equal(button._msufA3SpellIndicatorNameOverlay.allPoints, parent.nameText,
        "Name Color lost its name-text target")
    end
    Runtime.HideFrameEffects(parent)
  end
end

-- Static preview/live parity guard: both paths pin the same configured anchor
-- to the same anchor on their frame. Preview offsets alone are magnified by its
-- display zoom; dividing by previewScale yields the live X/Y values above.
local liveSource = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua")
local previewSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua")
local previewHandlesSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua")
local indicatorMenuSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators.lua")
local groupBarsMenuSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua")
local editModeSource = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_EditMode.lua")
Check(liveSource:find("button:SetPoint(anchor, parentFrame, anchor, x, y)", 1, true),
  "live Spell Indicator no longer anchors point-to-identical-point")
Check(previewSource:find("handle:SetPoint(anchor, mock, anchor, ConfigToOffset(x or 0, previewScale), ConfigToOffset(y or 0, previewScale))", 1, true),
  "preview Spell Indicator no longer anchors point-to-identical-point with zoomed offsets")
Check(previewSource:find('LayoutHandle(handle, placed.anchor, placed.x, placed.y, "TOPLEFT")', 1, true),
  "preview Spell Indicator no longer feeds the compiled anchor/X/Y into LayoutHandle")
Check(previewHandlesSource:find("function box:DropSpellIndicatorAtCursor(specKey, auraName)", 1, true),
  "group preview lost tracked-spell drop placement")
Check(previewHandlesSource:find("placed.anchor, placed.x, placed.y = anchor, nextX, nextY", 1, true),
  "tracked-spell drop no longer writes the live placement contract")
Check(previewHandlesSource:find('M.RunWithHistory("Place Spell Indicator"', 1, true),
  "tracked-spell drop is no longer undoable")
Check(indicatorMenuSource:find("preview.DropSpellIndicatorAtCursor(tile._specKey, tile._auraName)", 1, true),
  "tracked spell tiles no longer drop into the Group Frame Preview")
Check(indicatorMenuSource:find("preview.UpdateSpellDropTarget(true", 1, true),
  "tracked spell drag lost its visible preview drop target")
Check(previewSource:find("local function SpellPreviewHealthFill()", 1, true),
  "group preview has no current-health fill resolver")
Check(previewSource:find("root:SetAllPoints(healthBar)", 1, true),
  "group preview frame-effect owner is not attached to the health bar")
Check(previewSource:find("tint:SetAllPoints(target)", 1, true),
  "group preview Health Tint does not follow the current-health fill")
Check(editModeSource:find("local target = health and health.GetStatusBarTexture and health:GetStatusBarTexture()", 1, true),
  "Edit Mode frame effects do not resolve the current-health fill")
Check(editModeSource:find('top:SetPoint("TOPLEFT", target', 1, true),
  "Edit Mode border/glow effects escaped the current-health fill")
Check(previewSource:find("LayoutSpellPreviewEdges(root, target, effect", 1, true),
  "group preview border/pulse effects no longer use the health-bar target")
Check(indicatorMenuSource:find('Tr("Highlight Health Bar")', 1, true),
  "Spell frame-effect card does not describe its health-bar target")
Check(indicatorMenuSource:find('"Effect Layer (0-30)", 0, 30, 1, "layer", 0', 1, true),
  "Spell frame-effect Layer 0-30 control is missing")
Check(groupBarsMenuSource:find('"dispelOverlayLayer", 0, "visual"', 1, true),
  "Dispel overlay effect Layer 0-30 control is missing")
local indicatorConfigSource = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config_Indicators.lua")
Check(indicatorConfigSource:find("iconZoom = IconZoom(siCfg.iconZoom)", 1, true),
  "Spell Indicator root Icon Zoom is missing from the compiled Group scope")
Check(liveSource:find("tostring(slot.iconZoom)", 1, true)
  and liveSource:find("iconZoom = ClampNumber(fallbackIconZoom, 100, 100, 200)", 1, true),
  "Spell Indicator Icon Zoom is missing from the live slot layout signature")
Check(previewSource:find("ApplyPreviewIconZoom(spellTex, scene.spellIconZoom, 0)", 1, true),
  "Spell Indicator preview does not mirror its Group-scope Icon Zoom")
Check(indicatorMenuSource:find('W.Slider(spells, Tr("Icon Zoom (%)"), 100, 200, 1', 1, true)
  and indicatorMenuSource:find("cfg.iconZoom = tonumber(value) or 100", 1, true)
  and indicatorMenuSource:find('"gf_party.spellIndicators.iconZoom"', 1, true)
  and indicatorMenuSource:find('"gf_mythicraid.spellIndicators.iconZoom"', 1, true),
  "Spell Indicator scope-aware Icon Zoom slider is missing")

-- PLAYER_ENTERING_WORLD must opt into the exceptional repair path. The native
-- aura update settles first so later lifecycle work cannot immediately replace
-- the repaired point.
local unitFramesSource = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua")
Check(unitFramesSource:find("A3._ScheduleDirectIdentityRefreshAll(false, true)", 1, true),
  "PLAYER_ENTERING_WORLD direct refresh does not request forced geometry")
Check(unitFramesSource:find("ZONE_CHANGED_NEW_AREA = true", 1, true),
  "zone-change direct refresh does not request the world-entry repair path")
Check(unitFramesSource:find('frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")', 1, true),
  "zone-change lifecycle event is not registered")
local unitStart = assert(unitFramesSource:find("A3._DirectIdentityRefreshUnit = function", 1, true))
local unitStop = assert(unitFramesSource:find("A3._DirectIdentityRefreshAll = function", unitStart, true))
local unitBlock = unitFramesSource:sub(unitStart, unitStop - 1)
local updateAt = unitBlock:find("container:UpdateAllAuras()", 1, true)
Check(updateAt ~= nil, "direct identity refresh lost UpdateAllAuras")
Check(unitBlock:find("forceSpellIndicatorGeometry", 1, true),
  "direct identity refresh does not gate the exceptional repair")
Check(unitBlock:find("SpellIndicatorsRuntime.Recreate", 1, true),
  "world-transition repair no longer recreates Spell Indicator containers")
Check(unitBlock:find("the set is never mutated", 1, true),
  "Spell Indicator replacement is not deferred until after container iteration")

print("PASS spell indicator position lifecycle: validated filters, preview/live parity, scope-aware icon zoom, structural edits, safe zone recreation")
