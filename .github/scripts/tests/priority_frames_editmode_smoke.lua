_G = _G or _ENV

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

local function Region(parent)
  local r = { parent = parent, shown = true }
  function r:SetAllPoints() end
  function r:SetColorTexture() end
  function r:SetBackdrop() end
  function r:SetBackdropBorderColor() end
  function r:SetFont() end
  function r:SetShadowOffset() end
  function r:SetText(value) self.text = value end
  function r:SetTextColor() end
  function r:SetPoint() end
  function r:SetSize() end
  function r:SetShown(value) self.shown = value == true end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  return r
end

local function AnchorFraction(point)
  if point == "TOPLEFT" then return 0, 1 end
  if point == "TOP" then return 0.5, 1 end
  if point == "TOPRIGHT" then return 1, 1 end
  if point == "LEFT" then return 0, 0.5 end
  if point == "RIGHT" then return 1, 0.5 end
  if point == "BOTTOMLEFT" then return 0, 0 end
  if point == "BOTTOM" then return 0.5, 0 end
  if point == "BOTTOMRIGHT" then return 1, 0 end
  return 0.5, 0.5
end

local function Frame(name, parent)
  local f = {
    name = name,
    parent = parent,
    shown = true,
    width = 1,
    height = 1,
    left = 0,
    bottom = 0,
    scripts = {},
    events = {},
  }
  function f:SetParent(value) self.parent = value end
  function f:GetParent() return self.parent end
  function f:SetAllPoints() end
  function f:SetSize(w, h) self.width, self.height = w, h end
  function f:GetWidth() return self.width end
  function f:GetHeight() return self.height end
  function f:GetLeft() return self.left end
  function f:GetRight() return self.left + self.width end
  function f:GetBottom() return self.bottom end
  function f:GetTop() return self.bottom + self.height end
  function f:GetEffectiveScale() return 1 end
  function f:ClearAllPoints() self.point = nil end
  function f:SetPoint(point, relative, relativePoint, x, y)
    relative = relative or _G.UIParent
    relativePoint = relativePoint or point
    x, y = x or 0, y or 0
    local rfx, rfy = AnchorFraction(relativePoint)
    local fx, fy = AnchorFraction(point)
    local rx = (relative:GetLeft() or 0) + (relative:GetWidth() or 0) * rfx
    local ry = (relative:GetBottom() or 0) + (relative:GetHeight() or 0) * rfy
    self.left = rx + x - self.width * fx
    self.bottom = ry + y - self.height * fy
    self.point = { point, relative, relativePoint, x, y }
  end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:IsShown() return self.shown == true end
  function f:SetShown(value) self.shown = value == true end
  function f:EnableMouse() end
  function f:RegisterForDrag() end
  function f:RegisterForClicks() end
  function f:SetClampedToScreen() end
  function f:SetFrameStrata() end
  function f:SetFrameLevel(value) self.frameLevel = value end
  function f:GetFrameLevel() return self.frameLevel or 1 end
  function f:SetBackdrop() end
  function f:SetBackdropBorderColor() end
  function f:CreateTexture() return Region(self) end
  function f:CreateFontString() return Region(self) end
  function f:SetScript(kind, callback) self.scripts[kind] = callback end
  function f:HookScript(kind, callback) self.scripts[kind] = callback end
  function f:RegisterEvent(event) self.events[event] = true end
  function f:UnregisterEvent(event) self.events[event] = nil end
  function f:UnregisterAllEvents() for event in pairs(self.events) do self.events[event] = nil end end
  function f:IsMouseOver() return false end
  return f
end

local UIParent = Frame("UIParent")
UIParent:SetSize(1920, 1080)
UIParent.left, UIParent.bottom = 0, 0
_G.UIParent = UIParent

local raidAnchor = Frame("RaidAnchor", UIParent)
raidAnchor:SetSize(200, 100)
raidAnchor.left, raidAnchor.bottom = 100, 500
local partyAnchor = Frame("PartyAnchor", UIParent)
partyAnchor:SetSize(240, 160)
partyAnchor.left, partyAnchor.bottom = 600, 300

local priorityConf = {
  enabled = true,
  maxFrames = 5,
  growth = "DOWN",
  spacing = 2,
  anchorMode = "RAID_RIGHT",
  attachGap = 8,
  attachOffset = 0,
  point = "CENTER",
  relativePoint = "CENTER",
  offsetX = -120,
  offsetY = 0,
}
local normalConf = { enabled = false, width = 80, height = 32 }
local priorityApplyCalls = 0
local rosterResolves = 0
local registered = {}
local beginDrag
local undo
local focus
local pulses = {}
local initFrame
local combat = false
local runtimeObserver
local inRaid = true

local GF = {
  anchors = { raid = raidAnchor, party = partyAnchor },
  headers = {},
  _previewActive = {},
  _previewLayoutFrame = {},
  GetPriorityConf = function() return priorityConf end,
  GetConf = function(kind)
    if kind == "party" then return { enabled = true, width = 120, height = 40 } end
    return normalConf
  end,
  GetLiveRaidKind = function() return "raid" end,
  GetScaledFrameMetrics = function(kind)
    if kind == "party" then return 120, 40, 2 end
    return 80, 32, 2
  end,
  ResolvePrioritySelection = function()
    rosterResolves = rosterResolves + 1
    return nil, 0
  end,
  SetPreviewAnchor = function() end,
  ShowPreview = function() return true end,
  HidePreview = function() return true end,
  UpdateGroupVisibility = function() return true end,
  RegisterRuntimeObserver = function(_, callback) runtimeObserver = callback end,
  RequestPriorityApply = function(self, reason)
    Check(self and type(self.GetPriorityConf) == "function", "priority request lost its method owner")
    Check(type(reason) == "string", "priority request lost its reason")
    priorityApplyCalls = priorityApplyCalls + 1
    return true
  end,
}

local MSUF = { GF = GF, UF = { frames = {} } }
_G.MSUF_NS, _G.MSUF = MSUF, MSUF
_G.MSUF_EM2 = {
  Registry = {
    Register = function(cfg) registered[cfg.key] = cfg end,
    Get = function(key) return registered[key] end,
  },
  State = {
    IsActive = function() return true end,
    GetUnitKey = function() return "gf_priority" end,
    SetUnitKey = function() end,
  },
  Movers = {
    Show = function() end,
    SyncAll = function() end,
    Get = function()
      return Frame("PriorityMover", UIParent)
    end,
  },
  Ticker = {
    IsDragging = function() return false end,
    BeginDrag = function(_, key, cfg)
      beginDrag = { key = key, conf = cfg.getConf() }
    end,
    EndDrag = function() return true end,
  },
  Focus = {
    SetSelection = function(key, component)
      focus = { key = key, component = component }
    end,
    Pulse = function(key, component) pulses[#pulses + 1] = { key, component } end,
    NotifyPositionChanged = function() end,
  },
  Popups = { Open = function() end },
  HUD = { RefreshUnitSelector = function() end },
}

_G.C_Timer = { After = function(_, callback) callback() end }
_G.InCombatLockdown = function() return combat end
_G.MSUF_IsConfigCombatLocked = function() return combat end
_G.IsInRaid = function() return inRaid end
_G.IsInGroup = function() return true end
_G.GetNumGroupMembers = function() return 20 end
_G.GetNumSubgroupMembers = function() return 0 end
_G.GetCursorPosition = function() return 0, 0 end
_G.hooksecurefunc = function() end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.MSUF_EM_UndoBeforeChange = function(category, key)
  undo = { category = category, key = key }
end
_G.CreateFrame = function(_, name, parent)
  local frame = Frame(name, parent or UIParent)
  if not initFrame then initFrame = frame end
  return frame
end

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)
Check(initFrame and initFrame.scripts.OnEvent, "group EditMode init driver missing")
initFrame.scripts.OnEvent(initFrame, "PLAYER_LOGIN")

local cfg = registered.gf_priority
Check(cfg and cfg.popupType == "gf_priority" and cfg.canNudge == true,
  "priority mover was not registered as a first-class group mover")
local proxy = cfg.getFrame()
Check(proxy and proxy:IsShown() and proxy._msufGFKind == "priority",
  "enabled empty priority state did not expose an EditMode placeholder")
Check(proxy:GetLeft() == 308 and proxy:GetTop() == 600,
  "attached priority placeholder did not truthfully follow the raid anchor")
Check(next(proxy.events) == nil and proxy.scripts.OnUpdate == nil,
  "priority placeholder acquired event or idle OnUpdate ownership")
Check(rosterResolves == 0,
  "EditMode proxy sizing rescanned the raid roster")

inRaid = false
proxy = cfg.getFrame()
Check(proxy:GetLeft() == 848 and proxy:GetTop() == 460
  and proxy:GetWidth() == 120 and proxy:GetHeight() == 208,
  "Party Priority placeholder did not use Party metrics and the Party anchor")
Check(rosterResolves == 0,
  "Party EditMode proxy sizing rescanned the group roster")
inRaid = true

local liveAnchor = Frame("PriorityAnchor", UIParent)
liveAnchor:SetSize(80, 100)
liveAnchor.left, liveAnchor.bottom = 400, 600
liveAnchor._msufGFPriorityAnchor = true
liveAnchor._msufGFKind = "priority"
liveAnchor.msufConfigKey = "gf_priority"
GF.anchors.priority = liveAnchor
proxy = cfg.getFrame()
Check(proxy._msufGFLiveAnchor == liveAnchor,
  "priority mover did not switch from placeholder to the truthful live anchor")

Check(type(proxy.scripts.OnMouseDown) == "function", "priority proxy was not drag-wired")
proxy.scripts.OnMouseDown(proxy, "LeftButton")
Check(undo and undo.category == "gf" and undo.key == "priority",
  "priority drag did not enter the group undo domain")
Check(beginDrag and beginDrag.key == "gf_priority" and beginDrag.conf == priorityConf,
  "priority drag did not use the registered config")
Check(priorityConf.anchorMode == "FREE" and priorityConf.point == "CENTER"
  and priorityConf.relativePoint == "CENTER",
  "dragging an attached priority strip did not switch it to free placement")
Check(priorityConf.offsetX == -520 and priorityConf.offsetY == 110,
  "attached-to-free conversion did not preserve UIParent-centered coordinates")
Check(focus and focus.key == "gf_priority" and focus.component == "placement",
  "priority drag did not focus the placement controls")

priorityConf.anchorMode = "RAID_RIGHT"
priorityConf.offsetX, priorityConf.offsetY = -120, 0
local appliesBeforeNudge = priorityApplyCalls
Check(_G.MSUF_GF_EM2_NudgePreview("gf_priority", 1, 2) == true,
  "priority keyboard nudge was not consumed")
Check(priorityConf.anchorMode == "FREE" and priorityConf.offsetX == -519 and priorityConf.offsetY == 112,
  "priority keyboard nudge did not detach and preserve the live position")
Check(priorityApplyCalls == appliesBeforeNudge + 1,
  "priority nudge did not request exactly one dedicated apply")

local appliesBeforeReset = priorityApplyCalls
Check(_G.MSUF_GF_EM2_ResetPosition("priority") == true, "priority reset was not handled")
Check(priorityConf.anchorMode == "RAID_RIGHT" and priorityConf.attachGap == 8
  and priorityConf.attachOffset == 0 and priorityConf.offsetX == -120 and priorityConf.offsetY == 0,
  "priority reset did not restore the product defaults")
Check(priorityApplyCalls == appliesBeforeReset + 1,
  "priority reset did not request exactly one dedicated apply")
Check(pulses[#pulses] and pulses[#pulses][1] == "gf_priority" and pulses[#pulses][2] == "placement",
  "priority reset did not pulse the placement focus target")

priorityConf.enabled = false
GF.anchors.priority = nil
local appliesBeforeDisabledPreview = priorityApplyCalls
proxy = cfg.getFrame()
Check(cfg.isEnabled() == true and proxy and proxy:IsShown(),
  "explicitly selected disabled Priority Frames did not expose the inert placement placeholder")
Check(priorityApplyCalls == appliesBeforeDisabledPreview and next(proxy.events) == nil and proxy.scripts.OnUpdate == nil,
  "disabled placement preview acquired runtime work")

combat = true
Check(cfg.getFrame() == nil and not proxy:IsShown(),
  "combat lockdown left the priority drag proxy active")

local function Read(path)
  local handle = assert(io.open(path, "rb"))
  local source = handle:read("*a")
  handle:close()
  return source
end

local core = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Core.lua")
Check(core:find('"gf_priority"', 1, true)
  and core:find('ApplyGroupSettingsForKeySafe("priority")', 1, true),
  "EditMode cancel/undo does not retain and reapply gf_priority")
local focusSource = Read("MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Focus.lua")
Check(focusSource:find('pageKey = "gf_priority"', 1, true)
  and focusSource:find('if priorityPage then return pageKey end', 1, true),
  "priority EditMode focus does not route to its profile-wide page")

print("priority frames EditMode smoke: ok")
