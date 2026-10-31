--- Preview frame acquisition, detachment and compiled-spec cache ownership.
local addonName, MSUF = ...
local GF = MSUF.GF
local Samples = assert(GF.PreviewSamples, "Group preview requires PreviewSamples")
local ApplyPreviewData = Samples.ApplyPreviewData
local ClearPreviewData = Samples.ClearPreviewData
local PREVIEW_CLASSES = Samples.PREVIEW_CLASSES
local PREVIEW_NAMES = Samples.PREVIEW_NAMES
local PreviewMember = Samples.PreviewMember
local Layout = assert(GF.PreviewLayout, "Group preview requires PreviewLayout")
local PositionPreviewFrame = Layout.PositionPreviewFrame
local SetPreviewFrameSize = Layout.SetPreviewFrameSize
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "GroupFrames/Preview")
local CreateFrame = CreateFrame
local type = type
local tostring = tostring

-- Resolve forward/cold exports at use time, preserving the existing dependency boundary.
local function Dep(name)
  return MSUF.Require(name, "UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua")
end

local function DeactivatePreviewFrame(frame)
  if not frame then return end
  ClearPreviewData(frame)
  if frame.Hide then frame:Hide() end

  -- Preview regions stay pooled on the button, but a hidden preview must not
  -- stay attached to unit-frame routing, events, group iteration, or ClickCast.
  if type(GF.UntrackFrame) == "function" then
    GF.UntrackFrame(frame)
  else
    if type(GF.UnregisterClickCastFrame) == "function" then
      GF.UnregisterClickCastFrame(frame)
    end
    local UF = MSUF and MSUF.UF
    if UF and type(UF.DetachFrame) == "function" then
      UF.DetachFrame(frame)
    elseif frame.UnregisterAllEvents then
      frame:UnregisterAllEvents()
    end
  end

  frame._msufGFPreviewDetached = true
  frame._msufGFPreviewApplyKey = nil
end

local function ReleasePreviewFrame(scene, frames, index)
  local frame = frames[index]
  if not frame then return false end
  frames[index] = nil
  DeactivatePreviewFrame(frame)

  frame._msufGFPreviewScene = nil
  frame._msufPreviewLevelBase = nil
  frame._msufGFPreviewPooled = true
  frame._msufGFPreviewOwnerKind = nil
  frame._msufGFPreviewClass = nil
  frame._msufGFPreviewRole = nil
  frame._msufGFPreviewAnimState = nil
  frame._msufGFKind = nil
  frame._msufGFEM2Kind = nil
  frame.configKey = nil
  frame.msufConfigKey = nil
  frame.MSUFSpec = nil
  frame.MSUFUnitKey = nil
  frame.unitKey = nil
  if scene.default and frame.SetAttribute then frame:SetAttribute("unit", nil) end
  if frame.ClearAllPoints then frame:ClearAllPoints() end

  local free = scene.free
  free[#free + 1] = frame
  return true
end
local function PreviewApplyRevision(kind)
  if GF.GetCompiledSpecRevision then return GF.GetCompiledSpecRevision(kind) end
  return tostring(GF._compiledSpecRevision or "") .. ":" .. tostring(GF._compiledSpecSerial or "")
end

local function PreviewApplyKey(frame, kind, w, h, revision)
  local unit = (frame.GetAttribute and frame:GetAttribute("unit")) or frame.MSUFUnitKey or "player"
  return tostring(kind) .. "\030" .. tostring(unit) .. "\030" .. tostring(revision or PreviewApplyRevision(kind))
    .. "\030" .. tostring(w) .. "\030" .. tostring(h)
end

local function ApplyPreviewSpecIfNeeded(frame, kind, reason, w, h, dirtyMask, expectedRevision)
  if not frame then return false end
  local currentRevision = PreviewApplyRevision(kind)
  local key = PreviewApplyKey(frame, kind, w, h, currentRevision)
  if dirtyMask == nil and frame._msufGFPreviewDetached ~= true
    and frame._msufGFPreviewApplyKey == key and frame.MSUFSpec then
    return true
  end
  local revisionCurrent = expectedRevision == nil or currentRevision == expectedRevision
  local canApplyDirty = frame._msufGFPreviewDetached ~= true
    and frame.MSUFSpec ~= nil
    and dirtyMask ~= nil
    and revisionCurrent
    and type(GF.ApplyPreviewButtonDirty) == "function"
  local ok
  if frame._msufPreviewScope == true then
    local owner = frame._msufPreviewScene
    frame._msufPreviewLevelBase = MSUF.UF.Layers.ELEMENT_LEVEL_BASE + (owner.levelBase or 0)
    ok = GF.ApplySceneButton(frame, kind, canApplyDirty and dirtyMask or nil, owner.ignoreOocFade)
  elseif canApplyDirty then
    ok = GF.ApplyPreviewButtonDirty(frame, kind, reason, dirtyMask)
  elseif GF.ApplyButton then
    ok = GF.ApplyButton(frame, kind, reason)
  else
    return false
  end
  if ok then
    frame._msufGFPreviewDetached = nil
    frame._msufGFPreviewApplyKey = PreviewApplyKey(frame, kind, w, h)
  end
  return ok
end
local function AcquirePreviewFrame(scene, parent)
  local free = scene.free
  local freeCount = #free
  local frame = free[freeCount]
  if frame then
    free[freeCount] = nil
  elseif scene.default then
    GF._previewFrameSerial = GF._previewFrameSerial + 1
    frame = PixelLayoutRegion(CreateFrame("Button", nil, parent, "BackdropTemplate"))
    MSUF.PublicGlobals["MSUF_GFPreviewButton_" .. GF._previewFrameSerial] = frame
    if frame.EnableMouse then frame:EnableMouse(false) end
  else
    frame = PixelLayoutRegion(CreateFrame("Button", nil, parent, "BackdropTemplate"))
    frame:EnableMouse(false)
    -- No show/hide hooks mark it visible, so the scene does.
    frame._msufPreviewScope, frame._msufPreviewScene, frame._msufCoreVisible = true, scene, true
  end

  frame._msufGFPreviewScene = scene
  frame._msufPreviewLevelBase = not scene.default and (MSUF.UF.Layers.ELEMENT_LEVEL_BASE + (scene.levelBase or 0)) or nil
  frame._msufGFPreviewPooled = nil
  frame._msufGFPreviewDetached = true
  frame._msufGFPreviewApplyKey = nil
  frame._msufGFPreviewPositionKey = nil
  if frame:GetParent() ~= parent then frame:SetParent(parent) end
  return frame
end

local function EnsurePreviewFrame(scene, index, parent)
  local kind, t = scene.kind, scene.t
  local frames = t.frames[kind]
  if not frames then
    frames = {}
    t.frames[kind] = frames
  end
  local frame = frames[index]
  if not frame then
    frame = AcquirePreviewFrame(scene, parent)
    frames[index] = frame
  elseif frame:GetParent() ~= parent then
    frame:SetParent(parent)
  end

  frame._msufGFIsPreviewFrame = true
  frame._msufGFPreviewOwnerKind = kind
  local member = PreviewMember(scene, index)
  frame._msufGFPreviewIndex = member
  frame._msufGFKind = kind
  frame._msufGFEM2Kind = kind
  frame._msufIsGroupFrame = true
  frame.msufConfigKey = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ("gf_" .. kind)
  frame.configKey = "gf_" .. kind
  if scene.default then
    frame.MSUFUnitKey = "player"
    frame.unitKey = "player"
    if frame.SetAttribute then frame:SetAttribute("unit", "player") end
  else
    -- A scene frame holds no unit at all; its class portrait is its sample class.
    frame.MSUFUnitKey, frame.unitKey = nil, nil
    frame._msufPortraitSampleClass = PREVIEW_CLASSES[((member - 1) % #PREVIEW_CLASSES) + 1]
    -- The sample name is the frame's name from its first apply: the text runtime never asks who "player" is.
    frame._msufPreviewNameText = PREVIEW_NAMES[((member - 1) % #PREVIEW_NAMES) + 1]
  end
  return frame
end

local function PreparePreviewFrame(scene, index, layout, w, h, spacing, growth, upc, primary, blockW, blockH)
  local frame = EnsurePreviewFrame(scene, index, layout)
  SetPreviewFrameSize(frame, w, h)
  PositionPreviewFrame(frame, layout, index, scene.kind, w, h, spacing, growth, upc, primary, blockW, blockH)
  if not frame.MSUFSpec and frame.Hide then frame:Hide() end
  return frame
end

local function ApplyPreviewFrame(scene, index, reason, layout, w, h, spacing, growth, upc, primary, blockW, blockH, dirtyMask, expectedRevision)
  local kind = scene.kind
  local frame = PreparePreviewFrame(scene, index, layout, w, h, spacing, growth, upc, primary, blockW, blockH)
  ApplyPreviewSpecIfNeeded(frame, kind, reason, w, h, dirtyMask, expectedRevision)
  ApplyPreviewData(frame, index, kind, scene)
  -- Menu dispel-overlay preview: only row 1 owns a native aura container, so
  -- the MSUF-drawn preview has to be re-stamped per row on every rebuild.
  -- One boolean read when no preview is active.
  if MSUF.PublicGlobals.MSUF_DispelOverlayPreviewMode == true then
    Dep("MSUF_ApplyDispelOverlayPreviewToFrame")(frame)
  end
  return true
end
local function PreviewSpecsCurrent(frames, visibleCount, kind, w, h, revision)
  for i = 1, visibleCount do
    local frame = frames[i]
    if not (frame and frame.MSUFSpec and frame._msufGFPreviewApplyKey == PreviewApplyKey(frame, kind, w, h, revision)) then
      return false
    end
  end
  return true
end

--- An embedded scene sits at its owner's frame level: container, layout and frames take the one base, and a frame
--- whose level moved applies its spec again so every element level follows (the root frame owns its element-level base).
local function SeatSceneLevels(scene, container, layout, frames, count)
  local base = scene.levelBase
  if container._msufGFLevelBase ~= base then
    container._msufGFLevelBase = base
    container:SetFrameLevel(base)
    layout:SetFrameLevel(base)
  end
  for i = 1, count do
    local frame = frames[i]
    if frame and frame._msufGFLevelBase ~= base then
      frame._msufGFLevelBase = base
      frame._msufPreviewLevelBase = MSUF.UF.Layers.ELEMENT_LEVEL_BASE + base
      frame:SetFrameLevel(base)
      frame._msufGFPreviewApplyKey = nil
    end
  end
end

local function InvalidateFrames(frames)
  for i = 1, frames and #frames or 0 do frames[i]._msufGFPreviewApplyKey = nil end
end

GF.PreviewPool = {
  ReleasePreviewFrame = ReleasePreviewFrame,
  PreviewApplyRevision = PreviewApplyRevision,
  PreparePreviewFrame = PreparePreviewFrame,
  ApplyPreviewFrame = ApplyPreviewFrame,
  PreviewSpecsCurrent = PreviewSpecsCurrent,
  SeatSceneLevels = SeatSceneLevels,
  InvalidateFrames = InvalidateFrames,
}
