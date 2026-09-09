_G = _G or _ENV

local overlayCount, fontStringCount, animationCount = 0, 0, 0

local function FontString(parent)
  fontStringCount = fontStringCount + 1
  local fs = { parent = parent, shown = false }
  function fs:GetParent() return self.parent end
  function fs:SetParent(value) self.parent = value end
  function fs:ClearAllPoints() self.points = nil end
  function fs:SetPoint(...) self.points = { ... } end
  function fs:SetJustifyH(value) self.justify = value end
  function fs:SetWordWrap(value) self.wordWrap = value end
  function fs:SetNonSpaceWrap(value) self.nonSpaceWrap = value end
  function fs:SetDrawLayer(layer, subLayer) self.drawLayer, self.subLayer = layer, subLayer end
  function fs:SetTextColor(...) self.color = { ... } end
  function fs:SetText(value) self.text = value end
  function fs:SetWidth(value) self.width = value end
  function fs:SetShown(value) self.shown = value == true end
  function fs:IsShown() return self.shown == true end
  function fs:Show() self.shown = true end
  function fs:Hide() self.shown = false end
  return fs
end

local function Overlay(parent)
  overlayCount = overlayCount + 1
  local overlay = { parent = parent, alpha = 1 }
  function overlay:SetAllPoints(value) self.allPoints = value or true end
  function overlay:EnableMouse(value) self.mouseEnabled = value == true end
  function overlay:SetClipsChildren(value) self.clipsChildren = value == true end
  function overlay:SetFrameLevel(value) self.frameLevel = value end
  function overlay:GetFrameLevel() return self.frameLevel or 0 end
  function overlay:SetAlpha(value) self.alpha = value; self.alphaWrites = (self.alphaWrites or 0) + 1 end
  function overlay:CreateFontString() return FontString(self) end
  function overlay:CreateAnimationGroup()
    animationCount = animationCount + 1
    local group = { parent = self }
    function group:GetParent() return self.parent end
    function group:SetToFinalAlpha(value) self.finalAlpha = value end
    function group:SetScript(event, fn)
      assert(event == "OnFinished" or event == "OnStop")
      if event == "OnFinished" then self.finished = fn else self.stopped = fn end
    end
    function group:IsPlaying() self.playingQueries = (self.playingQueries or 0) + 1; return self.playing == true end
    function group:Play() self.plays = (self.plays or 0) + 1; self.playing = true; self.anim.progress = 0 end
    function group:Stop()
      self.stops = (self.stops or 0) + 1
      self.playing = false
      if self.stopped then self.stopped(self) end
    end
    function group:Finish() self.playing = false; self.finished(self) end
    function group:CreateAnimation(kind)
      assert(kind == "Alpha")
      local anim = {}
      function anim:SetSmoothing(value) assert(value == "NONE") end
      function anim:SetFromAlpha(value) self.from = value end
      function anim:SetToAlpha(value) self.to = value end
      function anim:SetDuration(value) self.duration = value end
      function anim:GetProgress() self.queries = (self.queries or 0) + 1; return self.progress end
      self.anim = anim
      return anim
    end
    return group
  end
  return overlay
end

local Text = {
  CreateFrame = function(_, _, parent) return Overlay(parent) end,
  UF = { Layers = {}, elements = {} },
  tonumber = tonumber,
  floor = math.floor,
  max = math.max,
  EMPTY_EVENTS = {},
  DrawSubLayer = function(layer, fallback) return tonumber(layer) or fallback end,
  ClampFrameLayer = function(layer, fallback) return tonumber(layer) or fallback end,
  GetLayerBaseLevel = function() return 0 end,
  SetFrameLevelCached = function(frame, level) frame:SetFrameLevel(level) end,
  SetShownCached = function(region, shown) if region then region:SetShown(shown) end end,
  SetFont = function() end,
  SetNameTextColor = function() end,
  NameTextColor = function() return 1, 1, 1, 1 end,
  ResolveHealthTextModes = function(text)
    text = text or {}
    local left, center, right = text.healthLeft, text.healthCenter, text.healthRight
    if text.healthReverse == true then left, right = right, left end
    return left, center, right
  end,
  CompileTextRuntime = function() return {} end,
  UpdateHealthTextColor = function() end,
}

local MSUF = { UF = Text.UF, UFText = Text }
assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Layout.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)

local function Frame()
  local frame = { unit = "party1" }
  function frame:GetFrameLevel() return 1 end
  function frame:GetWidth() return 120 end
  function frame:IsMouseOver() self.mouseQueries = (self.mouseQueries or 0) + 1; return self.mouseOver == true end
  function frame:HookScript(event, fn)
    self.hooks = self.hooks or {}
    self.hooks[event] = self.hooks[event] or {}
    table.insert(self.hooks[event], fn)
  end
  function frame:Fire(event)
    for _, fn in ipairs(self.hooks and self.hooks[event] or {}) do fn(self) end
  end
  return frame
end

local frame = Frame()
local firstSpec = {
  key = "gf_party",
  width = 120,
  height = 36,
  showName = true,
  showHealthText = true,
  showPowerText = false,
  _msufTextLayoutRevision = 1,
  text = {
    nameLayer = 5,
    healthLayer = 5,
    powerLayer = 2,
    healthLeft = "CURRENT",
    healthCenter = "NONE",
    healthRight = "NONE",
    powerLeft = "NONE",
    powerCenter = "NONE",
    powerRight = "NONE",
  },
}

Text.Create(frame, firstSpec)
assert(frame.nameText and frame.hpTextLeft, "configured name/health sinks were not created")
assert(not frame.hpTextCenter and not frame.hpTextRight, "disabled health sinks were eagerly created")
assert(not frame.powerTextLeft and not frame.powerTextCenter and not frame.powerTextRight,
  "disabled power sinks were eagerly created")
assert(frame.MSUFNameTextLayer and frame.MSUFHealthTextLayer and not frame.MSUFPowerTextLayer,
  "text overlays were not created lazily")
assert(overlayCount == 2 and fontStringCount == 2, "unexpected initial text allocation count")

local nameSink, healthSink = frame.nameText, frame.hpTextLeft
Text.Apply(frame, firstSpec)
assert(overlayCount == 2 and fontStringCount == 2, "initial apply recreated configured sinks")

local powerSpec = {
  key = "gf_party",
  width = 120,
  height = 36,
  showName = true,
  showHealthText = true,
  showPowerText = true,
  _msufTextLayoutRevision = 2,
  text = {
    nameLayer = 5,
    healthLayer = 5,
    powerLayer = 2,
    healthLeft = "CURRENT",
    healthCenter = "NONE",
    healthRight = "NONE",
    powerLeft = "NONE",
    powerCenter = "NONE",
    powerRight = "PERCENT",
  },
}

Text.Apply(frame, powerSpec)
assert(frame.powerTextRight and frame.MSUFPowerTextLayer, "newly enabled power sink was not cold-created")
assert(frame.nameText == nameSink and frame.hpTextLeft == healthSink, "existing text sinks were not reused")
assert(overlayCount == 3 and fontStringCount == 3, "cold apply created more than the missing power sink")

frame.nameText:Hide()
frame.hpTextLeft:Hide()
frame.powerTextRight:Hide()
frame._msufGFPreviewDetached = true
Text.Apply(frame, powerSpec)
assert(frame.nameText:IsShown() and frame.hpTextLeft:IsShown() and frame.powerTextRight:IsShown(),
  "detached preview text sinks were not reactivated on pooled reopen")
frame._msufGFPreviewDetached = nil

-- Augmentation gives the Player Power bar to Ebon Might, whose native duration
-- binding owns the text on it. The mode flag is independent of the compiled
-- text revision, so both entry and exit must bypass the normal
-- unchanged-layout early return.
frame._msufPowerEbonMight = true
Text.Apply(frame, powerSpec)
assert(not frame.powerTextRight:IsShown(),
  "Ebon Might mode did not hide the ordinary Power text")
frame._msufPowerEbonMight = nil
Text.Apply(frame, powerSpec)
assert(frame.powerTextRight:IsShown(),
  "leaving Ebon Might mode did not restore Power text with an unchanged layout revision")

local empty = Frame()
Text.Create(empty, {
  key = "gf_party",
  showName = false,
  showHealthText = true,
  showPowerText = true,
  text = {
    healthLeft = "NONE", healthCenter = "NONE", healthRight = "NONE",
    powerLeft = "NONE", powerCenter = "NONE", powerRight = "NONE",
  },
})
assert(not empty.MSUFNameTextLayer and not empty.MSUFHealthTextLayer and not empty.MSUFPowerTextLayer,
  "fully disabled text configuration allocated overlays")
assert(overlayCount == 3 and fontStringCount == 3, "fully disabled text configuration allocated regions")

print("text lazy sinks smoke: ok")

-- Hover gating must survive cached Apply, hidden/re-shown frames, ordinary text
-- writers, profile switches, and disabled slots without allocating new regions.
assert(not frame.hooks, "default text installed mouse hooks")
assert(not frame.MSUFHealthTextLayer.alphaWrites, "default text wrote overlay alpha")
frame._msufGFPreviewDetached = nil
local existingEnters = 0
frame:HookScript("OnEnter", function() existingEnters = existingEnters + 1 end)
powerSpec.text.healthMouseover = true
Text.Apply(frame, powerSpec)
assert(frame.MSUFHealthTextLayer.alpha == 0, "HP was visible without hover")
assert(not frame.MSUFNameTextLayer.alphaWrites, "HP toggle changed name alpha")
assert(frame.hpTextLeft:IsShown(), "hover gate overwrote slot visibility")
assert(#frame.hooks.OnEnter == 2, "hover replaced existing scripts")
frame.mouseOver = true
frame:Fire("OnEnter")
assert(existingEnters == 1 and frame.MSUFHealthTextLayer.alpha == 1, "enter did not coexist with other hooks")
frame:Fire("OnHide")
assert(frame.MSUFHealthTextLayer.alpha == 0, "hide retained hover state")
frame.mouseOver = false
frame:Fire("OnShow")
assert(frame.MSUFHealthTextLayer.alpha == 0, "show retained stale hover")
frame.mouseOver = true
frame:Fire("OnShow")
assert(frame.MSUFHealthTextLayer.alpha == 1, "stationary cursor on show was missed")
powerSpec.text.nameMouseover, powerSpec.text.powerMouseover = true, true
Text.Apply(frame, powerSpec)
assert(frame.MSUFNameTextLayer.alpha == 1 and frame.MSUFPowerTextLayer.alpha == 1,
  "enabling while hovered did not reveal the newly gated layers")
frame.mouseOver = false
frame:Fire("OnLeave")
frame.hpTextLeft:SetText("updated while hidden")
frame.hpTextLeft:Show()
Text.Apply(frame, powerSpec)
assert(frame.MSUFNameTextLayer.alpha == 0 and frame.MSUFHealthTextLayer.alpha == 0
  and frame.MSUFPowerTextLayer.alpha == 0, "cached Apply/text writer bypassed hover gate")
frame._msufPowerEbonMight = true
Text.Apply(frame, powerSpec)
frame:Fire("OnEnter")
assert(not frame.powerTextRight:IsShown(), "hover revealed power text suppressed by Ebon Might")
frame._msufPowerEbonMight = nil
Text.Apply(frame, powerSpec)
powerSpec.text.nameMouseover, powerSpec.text.healthMouseover, powerSpec.text.powerMouseover = false, false, false
Text.Apply(frame, powerSpec)
assert(frame.MSUFNameTextLayer.alpha == 1 and frame.MSUFHealthTextLayer.alpha == 1
  and frame.MSUFPowerTextLayer.alpha == 1, "disabled/new profile retained hidden overlays")
local writes = frame.MSUFHealthTextLayer.alphaWrites
frame:Fire("OnLeave")
frame:Fire("OnShow")
assert(frame.MSUFHealthTextLayer.alphaWrites == writes, "disabled hooks still touched overlays")
powerSpec.text.healthMouseover = true
Text.Apply(frame, powerSpec)
assert(#frame.hooks.OnEnter == 2 and #frame.hooks.OnLeave == 1, "re-enable stacked hooks")
frame._msufGFPreviewDetached = true
Text.Apply(frame, powerSpec)
assert(frame.MSUFHealthTextLayer.alpha == 1 and not frame._msufHoverHealth,
  "detached preview retained gameplay hover gate")
assert(overlayCount == 3 and fontStringCount == 3, "hover allocated extra rendering regions")
print("text mouseover lifecycle smoke: ok")
assert(animationCount == 0, "instant/default hover allocated animations")
frame._msufGFPreviewDetached = nil
powerSpec.text.healthMouseoverFadeIn = 0.8
powerSpec.text.healthMouseoverFadeOut = 0.4
Text.Apply(frame, powerSpec)
local layer = frame.MSUFHealthTextLayer
local group, anim = layer._msufHoverAnimation, layer._msufHoverAnim
assert(animationCount == 1 and not group:IsPlaying() and layer.alpha == 0,
  "fade setup animated initial visibility or allocated unrelated animations")
frame.mouseOver = true
frame:Fire("OnEnter")
assert(group:IsPlaying() and anim.from == 0 and anim.to == 1 and anim.duration == 0.8)
anim.progress = 0.25
frame:Fire("OnEnter")
assert(anim.progress == 0.25, "duplicate enter restarted fade")
frame.mouseOver = false
frame:Fire("OnLeave")
assert(anim.from == 0.25 and anim.to == 0 and anim.duration == 0.1,
  "rapid reversal jumped alpha or ignored fade-out speed")
group:Finish()
assert(layer.alpha == 0, "fade out did not retain its final alpha")
frame.mouseOver = true
frame:Fire("OnEnter")
group:Finish()
assert(layer.alpha == 1, "fade in did not retain its final alpha")
frame.mouseOver = false
frame:Fire("OnLeave")
anim.progress = 0.5
frame:Fire("OnHide")
assert(not group:IsPlaying() and layer.alpha == 0, "hidden frame retained an active fade")
frame.mouseOver = true
frame:Fire("OnShow")
assert(not group:IsPlaying() and layer.alpha == 1, "show did not settle stationary hover")
frame.mouseOver = false
frame:Fire("OnLeave")
powerSpec.text.healthMouseover = false
Text.Apply(frame, powerSpec)
assert(not group:IsPlaying() and layer.alpha == 1, "disabling hover left a fade running")
powerSpec.text.healthMouseover = true
powerSpec.text.healthMouseoverFadeIn, powerSpec.text.healthMouseoverFadeOut = 0, 0
Text.Apply(frame, powerSpec)
frame.mouseOver = true
frame:Fire("OnEnter")
assert(layer.alpha == 1 and not group:IsPlaying() and animationCount == 1,
  "zero duration did not restore instant hover/reuse its animation")
print("text mouseover native fade smoke: ok")

-- Repeated events and cached Apply must not cross into native rendering or
-- query the cursor/timeline. Preserve in-flight fades when another text type
-- is enabled or its geometry/settings are reapplied.
local alphaWrites = layer.alphaWrites
for i = 1, 100 do frame:Fire("OnEnter") end
assert(layer.alphaWrites == alphaWrites, "settled duplicate enters rewrote alpha")
powerSpec.text.healthMouseoverFadeIn, powerSpec.text.healthMouseoverFadeOut = 0.8, 0.4
Text.Apply(frame, powerSpec)
frame.mouseOver = false
frame:Fire("OnLeave")
anim.progress = 0.3
local mouseQueries, plays, stops = frame.mouseQueries, group.plays, group.stops
local progressQueries, playingQueries = anim.queries or 0, group.playingQueries or 0
alphaWrites = layer.alphaWrites
for i = 1, 100 do
  frame:Fire("OnLeave")
  Text.Apply(frame, powerSpec)
end
assert(group.playing and anim.progress == 0.3 and group.plays == plays and group.stops == stops,
  "cached Apply or duplicate leave interrupted/restarted fade")
assert(frame.mouseQueries == mouseQueries and layer.alphaWrites == alphaWrites
  and (anim.queries or 0) == progressQueries and (group.playingQueries or 0) == playingQueries,
  "unchanged hover performed native work")
powerSpec.text.healthMouseoverFadeOut = 1
powerSpec.text.nameMouseover = true
Text.Apply(frame, powerSpec)
assert(group.playing and anim.progress == 0.3 and group.stops == stops,
  "duration/peer visibility change snapped an existing fade")
assert(frame.MSUFNameTextLayer.alpha == 0, "newly gated peer did not synchronize to mouse")
frame:Fire("OnHide")
assert((anim.queries or 0) == progressQueries and not group.playing and layer.alpha == 0,
  "instant hide queried progress or failed to stop fade")
frame.mouseOver = true
frame:Fire("OnEnter")
-- Native/external stop must clear the cached playing state as well.
group:Stop()
assert(not layer._msufHoverFading, "native stop retained cached fade activity")
frame:Fire("OnEnter")
assert(group.playing, "stopped animation could not restart")
powerSpec.text.healthMouseover, powerSpec.text.nameMouseover = false, false
Text.Apply(frame, powerSpec)
mouseQueries, alphaWrites = frame.mouseQueries, layer.alphaWrites
for i = 1, 100 do
  frame:Fire("OnEnter"); frame:Fire("OnLeave"); frame:Fire("OnShow"); frame:Fire("OnHide")
  Text.Apply(frame, powerSpec)
end
assert(frame.mouseQueries == mouseQueries and layer.alphaWrites == alphaWrites and not group.playing,
  "disabled hover performed native work")
assert(animationCount == 1, "optimization allocated replacement animations")
print("text mouseover idle/duplicate/apply native work: zero (100 repetitions each)")
