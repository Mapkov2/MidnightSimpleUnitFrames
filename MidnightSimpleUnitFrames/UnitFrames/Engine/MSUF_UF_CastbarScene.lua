local _, MSUF = ...
local Surface = {}
local EMPTY_SAMPLE, DEFAULT_STAGES = {}, { 1, 2, 3 }
local function Noop() end
local function TargetInfo(sample) return sample.targetName, sample.targetClass, sample.targetName ~= nil end
local function HasTarget(sample) return sample.targetName ~= nil end
MSUF.UF.PreviewSurfaces.Castbar = Surface

function Surface.Create(scene)
  local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "CastbarScene")
  local frame = PixelLayoutRegion(CreateFrame("Frame", nil, scene.root.parent))
  frame.unit, frame._msufIsPreview = scene.key, true
  frame._msufPreviewScope, frame._msufPreviewScene = true, scene
  frame.MSUF_latencyHooked, frame._msufPlayerChannelHasteMarkersHooked = true, true
  local C = MSUF.Castbars
  scene.paintTarget = C.Driver.CreateTargetPainter(TargetInfo, HasTarget)
  scene.paintPlayerColor = C.Player.CreateColorPainter(function()
    local sample = scene.opts.sample or EMPTY_SAMPLE
    return sample.class, sample.class
  end, nil)
  scene.paintChannelTicks = C.ChannelTicks.CreateSamplePainter(function(id)
    local known = (scene.opts.sample or EMPTY_SAMPLE).knownSpells
    return known and known[id]
  end)
  if C.Empower.CreateSampleLayout then scene.layoutEmpower = C.Empower.CreateSampleLayout() end
  scene.paintInterrupt = C.Runtime.ApplyInterruptValues
  scene.interruptRuntime = { ReleaseActive = Noop, SetPhase = Noop, Phase = C.Runtime.Phase }
  scene.kickStatus = { resolved = true, sample = true }
  local frames = MSUF.Castbars.Frames
  if scene.key == "player" then frames.BuildPlayerCastbarElements(frame)
  else frames.BuildCastbarFrameElements(frame) end
  return frame
end

local function ProjectionEnd(self) return self.value end
local function ProjectionStart() return 0 end
local function Projection(scene, sample)
  local status = scene.kickStatus
  local projection = status.projection
  if not projection then
    projection = { duration = { GetStartTime = ProjectionStart, GetEndTime = ProjectionEnd }, cooldowns = {} }
    status.projection = projection
  end
  local total = math.max(0.01, tonumber(sample.duration) or 4)
  projection.duration.value = total
  local recoveries = sample.kickRecovery
  local count = recoveries and #recoveries or 0
  for i = 1, count do
    local cooldown = projection.cooldowns[i]
    if not cooldown then
      cooldown = { GetEndTime = ProjectionEnd }
      projection.cooldowns[i] = cooldown
    end
    cooldown.value = recoveries[i] * total
  end
  for i = #projection.cooldowns, count + 1, -1 do projection.cooldowns[i] = nil end
end

local function Progress(scene)
  local C, frame, sample = MSUF.Castbars, scene.frame, scene.opts.sample or EMPTY_SAMPLE
  local total = math.max(0.01, tonumber(sample.duration) or 4)
  local fraction = tonumber(sample.progress) or 0.6
  if scene.opts.animate and scene.root.animating then
    fraction = (fraction + scene.root.elapsed / total) % 1
  end
  fraction = math.max(0, math.min(1, fraction))
  local channel = sample.kind == "CHANNEL"
  local reverse = C.Utils.GetReverseFillSafe(frame, channel)
  local down = channel and C.Utils.GetCastbarCountsDown(frame, true) == true
  frame.MSUF_isChanneled, frame._msufStripeReverseFill = channel, reverse == true
  frame._msufCountsDown, frame._msufTimerAssumeCountdown = down, down
  frame._msufPlainTotal = total
  frame.statusBar:SetReverseFill(reverse == true)
  frame.statusBar:SetMinMaxValues(0, total)
  frame.statusBar:SetValue((down and (1 - fraction) or fraction) * total)
  C.Driver.UpdateCastTimeText_FromStatusBar(frame)
end

function Surface.Paint(scene)
  local C, frame, opts = MSUF.Castbars, scene.frame, scene.opts
  local sample, g = opts.sample or EMPTY_SAMPLE, C.Config.Read().general
  scene.kickStatus.ready = sample.kickReady == true
  Projection(scene, sample)
  scene.paintKick = scene.paintKick or C.KickReady.CreateSamplePainter(scene.kickStatus)
  frame:SetScale(opts.scale or 1)
  local width, height = C.Anchors.GetCastbarDesiredSize(scene.key, g, frame, 250, 18)
  frame:SetSize(opts.width or width, opts.height or height)
  frame:ClearAllPoints()
  frame:SetPoint(opts.point or "CENTER", scene.root.parent, opts.point or "CENTER", opts.x or 0, opts.y or 0)
  if C.Empower.PlayerCastbar_ClearEmpower then C.Empower.PlayerCastbar_ClearEmpower(frame, false) end
  frame.isNotInterruptible = sample.notInterruptible == true
  frame.icon:SetTexture(sample.icon or 136048)
  C.Utils.CB_ApplyTexts(frame, nil, sample.name or "Frostbolt", nil)
  frame.MSUF_castActive = false
  if frame._kickReadyBorderTinted then
    frame._kickReadyBorderTinted = nil
    C.Style.ApplyCastbarOutline(frame, true)
  end
  C.Visuals.RefreshCastbarFrame(frame, scene.key, g)
  C.KickReady.KickReady_ApplyLayout(frame)
  scene.paintTarget(frame, sample)
  C.Core.ApplyCastbarFrameLayer(frame, g, scene.key)
  Progress(scene)
  C.Core.ApplyCastbarSparkVisual(frame, g)
  if scene.key == "player" then
    scene.paintPlayerColor(frame)
    C.Player.ApplyLatencySample(frame, g.castbarShowLatency ~= false and sample.latency or 0,
      sample.kind == "CHANNEL")
    local text = frame.latencyText
    if g.castbarShowLatencyText and sample.latencyMS then
      if not text then
        local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "CastbarScene")
        text = PixelLayoutRegion(frame.statusBar:CreateFontString(nil, "OVERLAY"))
        text:SetPoint("TOPRIGHT", frame.statusBar, "BOTTOMRIGHT", 0, -2)
        frame.latencyText = text
      end
      text:SetFont(frame.timeText:GetFont())
      text:SetTextColor(1, 1, 1)
      text:SetFormattedText("%d ms", sample.latencyMS)
      text:Show()
    elseif text then text:Hide() end
  else
    local r, green, b, nr, ng, nb = C.Utils.ResolveCastbarColors()
    C.Utils.Castbar_ApplyNonInterruptibleTint(frame, frame.isNotInterruptible, nr, ng, nb, 1,
      r, green, b, 1, frame.isNotInterruptible)
  end
  if sample.kind == "EMPOWER" and C.Empower.LayoutEmpowerTicks then
    frame.isEmpower = true
    frame.empowerStageEnds = sample.stages or DEFAULT_STAGES
    frame.empowerTotalWithGrace = math.max(0.01, tonumber(sample.duration) or 4)
    scene.layoutEmpower(frame)
    if sample.blinkStage or scene.blinking then
      C.Empower.PaintSampleBlink(frame, sample.blinkStage, sample.blinkPhase)
      scene.blinking = sample.blinkStage ~= nil
    end
  end
  frame._msufActiveSpellID = sample.spellID
  if C.ChannelTicks.PlayerChannelHasteMarkers_Update then
    scene.paintChannelTicks(frame, true)
  end
  frame.MSUF_castActive = true
  scene.paintKick(frame, nil, g)
  if sample.interrupted then
    scene.paintInterrupt(scene.interruptRuntime, frame, 1, false, sample.interruptLabel, nil, nil, nil, true)
  end
  frame:Show()
end

--- Light clock/sample tick: progress and time text only; the layout of the last full paint stands.
function Surface.Tick(scene)
  Progress(scene)
end
