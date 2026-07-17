_G = _G or _ENV

local createdButtons, fullApplies, dirtyApplies, untracks, regionCreates = 0, 0, 0, 0, 0
local revision = 1
local timerQueue = {}

local function RunNextTimer()
  local callback = table.remove(timerQueue, 1)
  if callback then callback() end
  return callback ~= nil
end

local function DrainTimers()
  while RunNextTimer() do end
end

local function Frame(frameType, name, parent)
  local frame = { frameType = frameType, name = name, parent = parent, shown = false, attributes = {} }
  function frame:GetParent() return self.parent end
  function frame:SetParent(value) self.parent = value end
  function frame:EnableMouse(value) self.mouseEnabled = value == true end
  function frame:RegisterForClicks() self.clickRegistrations = (self.clickRegistrations or 0) + 1 end
  function frame:SetSize(w, h) self.width, self.height = w, h end
  function frame:GetWidth() return self.width or 0 end
  function frame:GetHeight() return self.height or 0 end
  function frame:ClearAllPoints() self.points = nil end
  function frame:SetPoint(...) self.points = { ... } end
  function frame:Show() self.shown = true end
  function frame:Hide() self.shown = false end
  function frame:IsShown() return self.shown == true end
  function frame:SetAttribute(key, value) self.attributes[key] = value end
  function frame:GetAttribute(key) return self.attributes[key] end
  return frame
end

local function FontString()
  local fs = { shown = true }
  function fs:IsShown() return self.shown == true end
  function fs:Show() self.shown = true end
  function fs:SetText(value) self.text = value end
  function fs:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
  return fs
end

local UIParent = Frame("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
function UIParent:GetLeft() return 0 end
function UIParent:GetRight() return 1920 end
function UIParent:GetBottom() return 0 end
function UIParent:GetTop() return 1080 end

_G.UIParent = UIParent
_G.InCombatLockdown = function() return false end
_G.GetNumSubgroupMembers = function() return 0 end
_G.GetNumGroupMembers = function() return 0 end
_G.UnitName = function() return "PreviewPlayer" end
_G.MSUF_UnitEditModeActive = true
_G.C_Timer = {
  After = function(_, callback)
    timerQueue[#timerQueue + 1] = callback
  end,
}
_G.CreateFrame = function(frameType, name, parent)
  if frameType == "Button" then createdButtons = createdButtons + 1 end
  return Frame(frameType, name, parent)
end

local MSUF = {
  ExportPublic = function(name, value)
    _G[name] = value
    return value
  end,
  GF = {},
}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local GF = MSUF.GF
GF.GetConf = function()
  return { offsetX = 0, offsetY = 0, anchorPoint = "CENTER", relativePoint = "CENTER" }
end
GF.GetGridMetrics = function(_, count)
  count = tonumber(count) or 1
  return 0, 0, 120, count * 37 - 1, 120, 36, 1, "DOWN", 5, nil, nil, nil, 5, nil, nil, 120, 184
end
GF.GetVisibleLayoutCount = function(_, count) return count end
GF.GetCompiledSpecRevision = function() return revision end
GF.ApplyButton = function(frame)
  fullApplies = fullApplies + 1
  frame.MSUFSpec = { health = {}, status = {} }
  frame.nameText = frame.nameText or FontString()
  if not frame._pooledRegion then
    frame._pooledRegion = {}
    regionCreates = regionCreates + 1
  end
  return true
end
GF.ApplyPreviewButtonDirty = function(frame)
  dirtyApplies = dirtyApplies + 1
  return frame.MSUFSpec ~= nil
end
GF.UntrackFrame = function(frame)
  untracks = untracks + 1
  frame._untracked = (frame._untracked or 0) + 1
end
GF.ResolveNameColor = function(kind, classToken)
  assert(kind == "party" or kind == "raid" or kind == "mythicraid", "preview name color received invalid kind")
  assert(type(classToken) == "string" and classToken ~= "", "preview name color received no class token")
  return 0.12, 0.34, 0.56
end
GF.ResolveFontTextAlpha = function() return 0.78 end

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Preview.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)

assert(GF.ShowPreview("party", 1, { immediate = true }) == true, "initial preview did not open")
local first = assert(GF._previewFrames.party[1], "initial preview button missing")
local pooledRegion = first._pooledRegion
assert(createdButtons == 1 and fullApplies == 1 and regionCreates == 1, "initial preview allocation mismatch")
assert(first:IsShown() and first._msufGFPreviewDetached ~= true, "initial preview did not become active")
assert(first.clickRegistrations == nil, "visual-only preview registered clicks")
assert(first.nameText.color[1] == 0.12 and first.nameText.color[2] == 0.34
  and first.nameText.color[3] == 0.56 and first.nameText.color[4] == 0.78,
  "preview name did not use the live group-frame name color and opacity resolvers")

assert(GF.HidePreview("party") == true, "preview did not hide")
assert(not first:IsShown() and first._msufGFPreviewDetached == true, "hidden preview stayed active")
assert(first._msufGFPreviewApplyKey == nil and first._untracked == 1, "hidden preview stayed attached")
assert(#GF._previewFrames.party == 0 and #GF._previewFreeFrames == 1,
  "hidden preview was retained in its kind array instead of the free pool")

assert(GF.ShowPreview("party", 1, { immediate = true, dirtyMask = 7 }) == true, "pooled preview did not reopen")
assert(GF._previewFrames.party[1] == first, "preview button was recreated instead of pooled")
assert(first._pooledRegion == pooledRegion and regionCreates == 1, "pooled preview regions were recreated")
assert(fullApplies == 2 and dirtyApplies == 0,
  "detached preview used a partial apply instead of a full reattach")
assert(first._msufGFPreviewDetached ~= true and first:IsShown(), "reopened preview did not reattach")

revision = revision + 1
assert(GF.ShowPreview("party", 1, { immediate = true, dirtyMask = 7 }) == true, "active preview refresh failed")
assert(dirtyApplies == 1 and fullApplies == 2, "active preview did not retain targeted dirty apply")

assert(GF.ShowPreview("party", 2, { immediate = true }) == true, "second preview button did not open")
local second = assert(GF._previewFrames.party[2], "second preview button missing")
assert(second:IsShown() and createdButtons == 2, "second preview button was not created")
assert(GF.ShowPreview("party", 1, { immediate = true }) == true, "preview shrink failed")
assert(not second:IsShown() and second._msufGFPreviewDetached == true and second._untracked == 1,
  "excess pooled preview stayed attached after shrink")

GF.HidePreview("party")
assert(untracks >= 3 and first._msufGFPreviewDetached == true, "final preview hide did not detach all visible frames")
assert(#GF._previewFrames.party == 0 and #GF._previewFreeFrames == 2, "party hide did not release both buttons")

-- Sequential kinds share the same retained buttons, while simultaneously active
-- kinds keep exclusive ownership of their current frames.
assert(GF.ShowPreview("raid", 2, { immediate = true }) == true, "raid preview did not reuse pool")
local raidFirst, raidSecond = GF._previewFrames.raid[1], GF._previewFrames.raid[2]
assert(raidFirst == first and raidSecond == second, "cross-kind reuse did not consume pooled buttons")
assert(createdButtons == 2 and #GF._previewFreeFrames == 0, "sequential kind switch increased high-water memory")
assert(raidFirst._msufGFKind == "raid" and raidFirst.configKey == "gf_raid"
  and raidFirst.unit == "player" and raidFirst:GetParent() == GF._previewLayoutFrame.raid,
  "cross-kind frame state was not rebound")

assert(GF.ShowPreview("party", 1, { immediate = true }) == true, "simultaneous party preview failed")
local simultaneousParty = GF._previewFrames.party[1]
assert(simultaneousParty ~= raidFirst and simultaneousParty ~= raidSecond,
  "active raid button was stolen by simultaneous party preview")
assert(createdButtons == 3, "simultaneous high-water button was not allocated exactly once")
GF.HidePreview("party")
GF.HidePreview("raid")
assert(#GF._previewFreeFrames == 3, "simultaneous previews did not return to shared pool")

assert(GF.ShowPreview("mythicraid", 3, { immediate = true }) == true, "mythic preview did not reuse shared pool")
assert(createdButtons == 3 and #GF._previewFreeFrames == 0,
  "visiting a third kind retained the sum of per-kind buttons")
for i = 1, 3 do
  local frame = GF._previewFrames.mythicraid[i]
  assert(frame._msufGFKind == "mythicraid" and frame._msufGFEM2Kind == "mythicraid",
    "reused mythic button kept stale kind state")
end
GF.HidePreview("mythicraid")

-- Cancel a sliced build after its first slice, reassign every released button
-- to another kind, then prove the stale callbacks cannot touch the new owner.
local fullBeforeQueued = fullApplies
assert(GF.ShowPreview("raid", 10) == true, "queued raid build did not start")
assert(#GF._previewFrames.raid == 10 and createdButtons == 10 and #timerQueue == 1,
  "queued build did not establish the expected ten-button high-water")
assert(RunNextTimer() == true and fullApplies == fullBeforeQueued + 2 and #timerQueue == 1,
  "queued build did not apply exactly one slice")
GF.HidePreview("raid")
assert(#GF._previewFrames.raid == 0 and #GF._previewFreeFrames == 10,
  "cancelled build did not release every prepared button")

assert(GF.ShowPreview("mythicraid", 10, { immediate = true }) == true,
  "cancelled-build buttons did not rebind to mythic preview")
assert(createdButtons == 10 and #GF._previewFreeFrames == 0,
  "cross-kind reuse exceeded simultaneous ten-button high-water")
local fullAfterRebind = fullApplies
DrainTimers()
assert(fullApplies == fullAfterRebind, "cancelled raid callback applied after cross-kind reassignment")
for i = 1, 10 do
  local frame = GF._previewFrames.mythicraid[i]
  assert(frame and frame:IsShown() and frame._msufGFKind == "mythicraid"
    and frame._msufGFPreviewOwnerKind == "mythicraid",
    "cancelled queue mutated a reassigned preview button")
end
GF.HidePreview("mythicraid")

-- API parity: explicit counts above 40 remain valid; the pool has no fixed cap.
assert(GF.ShowPreview("raid", 41, { immediate = true }) == true, "41-frame preview was capped")
assert(#GF._previewFrames.raid == 41 and createdButtons == 41,
  "preview pool imposed a fixed 40-button limit")
assert(GF.HidePreviewsForCombat() == true,
  "combat boundary did not force-close an owner-active preview")
assert(#GF._previewFreeFrames == 41, "high-water pool did not retain the actual maximum visible count")
assert(#GF._previewFrames.raid == 0 and GF._previewActive.raid ~= true,
  "combat boundary left preview frames attached")

print("group preview lifecycle smoke: ok")
