--- UnitFrames/Engine/Group/MSUF_UF_Group_Blizzard.lua
--- Ownership adapter for Blizzard party/raid frames.
---
--- When MSUF group frames are enabled, Blizzard's group-frame owners are hidden
--- without touching their secret-aware unit buttons. Returning ownership is a
--- reload-only transition; protected hide/reparent work is deferred out of combat.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local GF = MSUF.GF or {}
MSUF.GF = GF

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local hooksecurefunc = hooksecurefunc
local type = type
local next = next
local tostring = tostring

local hiddenParent
local eventFrame
local applyScheduled
local hookedSetParent = {}
local ownedFrames = {}
local pendingHide = {}
local lastOwnershipSig
local rosterEventRegistered = false
local BlizzardRosterEventWanted
local MSUFOwnsLiveGroupFrames
local blizzardEventsActive = false

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local function HiddenParent()
  if hiddenParent then
    return hiddenParent
  end
  hiddenParent = CreateFrame("Frame", "MSUF_GF_BlizzardHiddenParent", UIParent)
  hiddenParent:SetAllPoints()
  hiddenParent:Hide()
  return hiddenParent
end

local function IsForbidden(frame)
  return frame and frame.IsForbidden and frame:IsForbidden()
end

local function ResolveFrame(frame)
  if type(frame) == "string" then
    return _G[frame]
  end
  return frame
end

local function IsHiddenFrameParent(parent)
  return parent
    and parent ~= UIParent
    and parent.IsShown
    and not parent:IsShown()
end

local function EnsureEventFrame()
  if eventFrame then
    return eventFrame
  end
  eventFrame = CreateFrame("Frame")
  return eventFrame
end

local function RegisterRosterEvent()
  if not rosterEventRegistered and not InCombat()
    and (type(BlizzardRosterEventWanted) ~= "function" or BlizzardRosterEventWanted() == true) then
    EnsureEventFrame():RegisterEvent("GROUP_ROSTER_UPDATE")
    rosterEventRegistered = true
  end
end

local function UnregisterRosterEvent()
  if eventFrame and rosterEventRegistered then
    eventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
    rosterEventRegistered = false
  end
end

local function RefreshRosterEventRegistration()
  if InCombat() or (type(BlizzardRosterEventWanted) == "function" and BlizzardRosterEventWanted() ~= true) then
    UnregisterRosterEvent()
    return false
  end
  RegisterRosterEvent()
  return rosterEventRegistered == true
end

local function DeferHide(frame)
  pendingHide[frame] = true
  EnsureEventFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
end

--- Hard hiding prefers reparenting to a hidden parent. Protected frames cannot
--- always be reparented in combat, so those requests are queued for regen.
local function ReparentHidden(frame)
  if not (frame and frame.SetParent) or IsForbidden(frame) then
    return
  end
  local parent = HiddenParent()
  if InCombat() and frame.IsProtected and frame:IsProtected() then
    DeferHide(frame)
    return
  end
  if frame.GetParent and not IsHiddenFrameParent(frame:GetParent()) then
    frame:SetParent(parent)
  end
end

local function ResetParent(frame, parent)
  local info = ownedFrames[frame]
  if not (info and info.hidden) then
    return
  end
  local hidden = HiddenParent()
  if parent == hidden or IsHiddenFrameParent(parent) or IsHiddenFrameParent(frame:GetParent()) then
    return
  end
  ReparentHidden(frame)
end

local function HookFrame(frame)
  if not frame or IsForbidden(frame) then
    return
  end
  if frame.SetParent and not hookedSetParent[frame] then
    hooksecurefunc(frame, "SetParent", ResetParent)
    hookedSetParent[frame] = true
  end
end

local function HardHideFrame(frame)
  frame = ResolveFrame(frame)
  if not frame or IsForbidden(frame) then
    return nil
  end

  local info = ownedFrames[frame]
  if not info then
    info = {}
    ownedFrames[frame] = info
  end
  info.hidden = true

  if InCombat() and frame.IsProtected and frame:IsProtected() then
    DeferHide(frame)
    return frame
  end
  if frame.Hide then
    frame:Hide()
  end
  HookFrame(frame)
  ReparentHidden(frame)
  return frame
end

local function HidePartyFrames()
  -- CompactPartyFrame and the classic PartyMemberFrame pool are descendants of
  -- PartyFrame on 12.1. Hide only that owner; touching individual unit buttons
  -- would taint their secret-aware health/event execution.
  HardHideFrame(_G.PartyFrame)
end

--- CompactRaidFrameManager is deliberately absent here. The tab is a tool panel
--- (ready check, raid markers, role filters, difficulty), not a unit frame, and it is
--- owned end-to-end by raidManagerMode below. Hard-hiding it here used to win over that
--- setting -- reparenting it makes later alpha writes ineffective -- so the dropdown did
--- nothing whenever MSUF owned any group frames. Its AUTO mode reproduces the old "gone
--- while MSUF owns the frames" behavior.
local function HideRaidFrames()
  -- All generated CompactRaidGroup/CompactRaidFrame unit buttons are children
  -- of CompactRaidFrameContainer. Hide only the owners and leave Blizzard's
  -- unit-button scripts, events, colors and secret values completely untouched.
  HardHideFrame(_G.CompactRaidFrameReservationManager)
  HardHideFrame(_G.CompactRaidFrameContainer)
end

--- Blizzard Raid Manager visibility.
---
--- The Raid Manager tab is its own top-level frame (Blizzard_CompactRaidFrames/
--- Mainline/Blizzard_CompactRaidFrameManager.xml, upstream/ptr): CompactRaidFrameContainer
--- is parented to UIParent, not to the manager, so the tab can be steered without
--- touching the raid frames. The ownership pass above already hides the manager while
--- MSUF owns the raid frames; this layer covers the scopes where it does not, which is
--- party and every Blizzard-provider scope.
---
--- Both non-default modes work through SetAlpha/EnableMouse instead of Hide(). Neither
--- is protected, so the visible part never has to wait for regen, and Blizzard writes
--- the manager's own alpha nowhere (only a child button's, in
--- CompactRaidFrameManager_UpdateOptionsFlowContainer) -- a value set once survives the
--- SetShown() in CompactRaidFrameManager_UpdateShown without a single re-apply. Hide()
--- would be undone by that same SetShown on every GROUP_ROSTER_UPDATE.
local RAID_MANAGER_KINDS = { "party", "raid", "mythicraid" }
local raidManagerMode = "AUTO"
local raidManagerHooked = false
local raidManagerMouseDefault
local raidManagerPendingMouse

--- "DEFAULT" is the pre-release spelling of AUTO and is mapped rather than dropped, so a
--- profile written by an in-between build keeps working instead of silently resetting.
local function NormalizeRaidManagerMode(value)
  if value == "MOUSEOVER" then return "MOUSEOVER" end
  if value == "HIDDEN" then return "HIDDEN" end
  if value == "SHOW" then return "SHOW" end
  return "AUTO"
end

--- One shared piece of Blizzard chrome, so the three group scopes hold one synchronized
--- value. Reading the first scope that carries the key keeps a partially migrated or
--- imported profile on the user's choice instead of silently falling back to DEFAULT.
local function ResolveRaidManagerMode()
  local getConf = GF.GetConf
  if type(getConf) ~= "function" then return "AUTO" end
  for i = 1, #RAID_MANAGER_KINDS do
    local conf = getConf(RAID_MANAGER_KINDS[i])
    local value = conf and conf.raidManagerMode
    if value ~= nil then return NormalizeRaidManagerMode(value) end
  end
  return "AUTO"
end

local function MouseIsOverRaidManager(manager)
  local getFoci = _G.GetMouseFoci
  if type(getFoci) ~= "function" then return false end
  local foci = getFoci()
  if type(foci) ~= "table" then return false end
  for i = 1, #foci do
    local region = foci[i]
    while type(region) == "table" and type(region.GetParent) == "function" do
      if region == manager then return true end
      region = region:GetParent()
    end
  end
  return false
end

local function RaidManagerOnEnter(self)
  if raidManagerMode == "MOUSEOVER" then
    self:SetAlpha(1)
  end
end

--- Mirrors Blizzard's own collapse model: an expanded panel is one the user is working
--- in, so it stays lit until they collapse it again. GetMouseFoci keeps it lit while the
--- pointer sits on a child region (dropdown, marker button) that fires the parent OnLeave.
local function RaidManagerOnLeave(self)
  if raidManagerMode ~= "MOUSEOVER" then return end
  if self.collapsed == false then return end
  if MouseIsOverRaidManager(self) then return end
  self:SetAlpha(0)
end

local function RaidManagerOnToggleClick()
  local manager = _G.CompactRaidFrameManager
  if raidManagerMode == "MOUSEOVER" and manager and manager.collapsed and manager.SetAlpha then
    manager:SetAlpha(0)
  end
end

local function EnsureRaidManagerHooks(manager)
  if raidManagerHooked or type(manager.HookScript) ~= "function" then return end
  raidManagerHooked = true
  manager:HookScript("OnEnter", RaidManagerOnEnter)
  manager:HookScript("OnLeave", RaidManagerOnLeave)
  --- 12.1 split the single toggleButton into a forward/back pair.
  local buttons = {
    manager.toggleButtonBack or _G.CompactRaidFrameManagerToggleButtonBack,
    manager.toggleButtonForward or _G.CompactRaidFrameManagerToggleButtonForward,
  }
  for i = 1, #buttons do
    local button = buttons[i]
    if button and type(button.HookScript) == "function" and not IsForbidden(button) then
      button:HookScript("OnClick", RaidManagerOnToggleClick)
    end
  end
end

--- HIDDEN also drops mouse input, so the invisible tab stops eating clicks at the left
--- screen edge. EnableMouse is protected once the frame is, so a combat request parks the
--- wanted state for regen -- the alpha write above already did the visible half.
local function ApplyRaidManagerMouse(manager, enabled)
  if not (manager and type(manager.EnableMouse) == "function" and type(manager.IsMouseEnabled) == "function") then
    return
  end
  if raidManagerMouseDefault == nil then
    raidManagerMouseDefault = manager:IsMouseEnabled() and true or false
  end
  local wanted = enabled and raidManagerMouseDefault or false
  if (manager:IsMouseEnabled() and true or false) == wanted then
    raidManagerPendingMouse = nil
    return
  end
  if InCombat() and manager.IsProtected and manager:IsProtected() then
    raidManagerPendingMouse = enabled and true or false
    EnsureEventFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
    return
  end
  raidManagerPendingMouse = nil
  manager:EnableMouse(wanted)
end

--- The single owner of the tab's visibility. Every mode resolves to a plain
--- alpha + mouse pair, so switching between them is always fully reversible and never
--- needs a protected call for the part the user actually sees.
---   AUTO      gone while MSUF owns the live group frames, untouched otherwise
---   SHOW      always visible, even with MSUF group frames on
---   MOUSEOVER invisible until hovered
---   HIDDEN    invisible and click-through
local function ApplyRaidManagerMode()
  local manager = _G.CompactRaidFrameManager
  if not manager or IsForbidden(manager) or type(manager.SetAlpha) ~= "function" then
    return
  end
  raidManagerMode = ResolveRaidManagerMode()

  local mode = raidManagerMode
  if mode == "AUTO" then
    mode = (type(MSUFOwnsLiveGroupFrames) == "function" and MSUFOwnsLiveGroupFrames())
      and "HIDDEN" or "SHOW"
  end

  if mode == "HIDDEN" then
    manager:SetAlpha(0)
    ApplyRaidManagerMouse(manager, false)
    return
  end
  ApplyRaidManagerMouse(manager, true)
  if mode == "MOUSEOVER" then
    EnsureRaidManagerHooks(manager)
    manager:SetAlpha(MouseIsOverRaidManager(manager) and 1 or 0)
    return
  end
  manager:SetAlpha(1)
end

--- Menu entry point. The alpha half lands immediately even in combat, so the dropdown
--- always looks like it did something.
function GF.ApplyBlizzardRaidManagerMode()
  ApplyRaidManagerMode()
  return raidManagerMode
end

function GF.GetBlizzardRaidManagerMode()
  return ResolveRaidManagerMode()
end

local BASE_EVENTS = {
  "ADDON_LOADED",
  "PLAYER_LOGIN",
  "PLAYER_ENTERING_WORLD",
  "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED",
}

local function SetBlizzardEventsEnabled()
  local frame = EnsureEventFrame()
  frame:UnregisterAllEvents()
  rosterEventRegistered = false
  blizzardEventsActive = true
  for i = 1, #BASE_EVENTS do frame:RegisterEvent(BASE_EVENTS[i]) end
  RefreshRosterEventRegistration()
end

local function NormalizeBlizzardFallbackMode(mode)
  if mode == "SHOW" or mode == "BLIZZARD" or mode == true then
    return "SHOW"
  end
  if mode == "NONE" or mode == "HIDE" or mode == false then
    return "NONE"
  end
  return "AUTO"
end

function GF.AnyMSUFGroupFrameEnabled()
  local party = GF.GetConf and GF.GetConf("party") or nil
  local raid = GF.GetConf and GF.GetConf("raid") or nil
  local mythic = GF.GetConf and GF.GetConf("mythicraid") or nil
  return (party and party.enabled == true)
    or (raid and raid.enabled == true)
    or (mythic and mythic.enabled == true)
    or false
end

local function LiveRaidKind()
  return GF.GetLiveRaidKind and GF.GetLiveRaidKind() or "raid"
end

local function LiveGroupKind()
  if type(GF.GetLiveGroupKind) == "function" then return GF.GetLiveGroupKind() end
  if IsInRaid and IsInRaid() then return LiveRaidKind() end
  if IsInGroup and IsInGroup() then return "party" end
  return nil
end

local function PartyScopeActive()
  local party = GF.GetConf and GF.GetConf("party") or nil
  if not (party and party.enabled == true) then return false end
  if LiveGroupKind() == "party" then return true end
  return party.showSolo == true and party.showPlayer ~= false
end

local function RaidScopeActive()
  local kind = LiveGroupKind()
  if kind ~= "raid" and kind ~= "mythicraid" then return false end
  local raid = GF.GetConf and GF.GetConf(kind) or nil
  return raid and raid.enabled == true
end

function MSUFOwnsLiveGroupFrames()
  return PartyScopeActive() or RaidScopeActive()
end

local function ApplyDisabledPartyFallback(mode)
  mode = NormalizeBlizzardFallbackMode(mode)
  if mode == "NONE" then
    HidePartyFrames()
  end
  -- AUTO/SHOW deliberately leave Blizzard untouched. Returning a frame that
  -- MSUF hid earlier in this session requires /reload; the provider control
  -- already presents that requirement. Calling Blizzard's Show/update paths
  -- here would run secret-aware CompactUnitFrame code under addon taint.
end

local function ApplyDisabledRaidFallback(mode)
  mode = NormalizeBlizzardFallbackMode(mode)
  if mode == "NONE" then
    HideRaidFrames()
  end
  -- AUTO/SHOW are Blizzard-owned until reload; see the Party path above.
end

BlizzardRosterEventWanted = function()
  if MSUFOwnsLiveGroupFrames() then
    return true
  end
  local party = GF.GetConf and GF.GetConf("party") or {}
  local raid = GF.GetConf and GF.GetConf(LiveRaidKind()) or {}
  return NormalizeBlizzardFallbackMode(party.blizzardFallbackMode) == "NONE"
    or NormalizeBlizzardFallbackMode(raid.blizzardFallbackMode) == "NONE"
end

function GF.HideBlizzardPartyFrames()
  HidePartyFrames()
end

function GF.HideBlizzardRaidFrames()
  HideRaidFrames()
end

function GF.RestoreBlizzardGroupFrames()
  -- Restoring/rebuilding Blizzard CompactUnitFrames from addon execution is
  -- not secret-safe on 12.1. Provider changes are applied by the clean native
  -- load path after /reload instead.
  return false
end

--- Main ownership reconciliation. It compares MSUF group-frame state and the
--- configured Blizzard fallback mode, then hides only frames owned by MSUF.
function GF.ApplyBlizzardGroupFrameOwnership(reason)
  if not blizzardEventsActive then SetBlizzardEventsEnabled() end
  if InCombat() then
    GF._pendingBlizzardGroupOwnership = reason or true
    EnsureEventFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
    return false
  end
  if GF.EnsureDB then
    GF.EnsureDB()
  end
  local force = type(reason) == "string" and reason:sub(1, 12) == "addon-loaded"
  local groupCount = GetNumGroupMembers and GetNumGroupMembers() or 0
  local inRaid = IsInRaid and IsInRaid() and true or false

  local partyConf = GF.GetConf and GF.GetConf("party") or {}
  local raidKind = LiveRaidKind()
  local raidConf = GF.GetConf and GF.GetConf(raidKind) or {}
  local msufOwnsGroupFrames = MSUFOwnsLiveGroupFrames()
  local partyUsesMSUF = partyConf.enabled == true
  local raidUsesMSUF = raidConf.enabled == true
  local partyActive = PartyScopeActive()
  local raidActive = RaidScopeActive()
  local partyMode = NormalizeBlizzardFallbackMode(partyConf.blizzardFallbackMode)
  local raidMode = NormalizeBlizzardFallbackMode(raidConf.blizzardFallbackMode)
  local sig = "on|" .. tostring(groupCount)
    .. "|" .. tostring(inRaid)
    .. "|" .. tostring(raidKind)
    .. "|" .. tostring(msufOwnsGroupFrames)
    .. "|" .. tostring(partyUsesMSUF)
    .. "|" .. tostring(raidUsesMSUF)
    .. "|" .. tostring(partyActive)
    .. "|" .. tostring(raidActive)
    .. "|" .. tostring(partyMode)
    .. "|" .. tostring(raidMode)
    .. "|" .. tostring(ResolveRaidManagerMode())

  if not force and lastOwnershipSig == sig and not next(pendingHide) then
    return true
  end
  lastOwnershipSig = sig

  if partyUsesMSUF then
    HidePartyFrames()
  else
    ApplyDisabledPartyFallback(partyMode)
  end

  if raidUsesMSUF then
    HideRaidFrames()
  else
    ApplyDisabledRaidFallback(raidMode)
  end

  --- The manager tab is independent from the secret-aware unit-frame owners.
  ApplyRaidManagerMode()

  RefreshRosterEventRegistration()
  return true
end

local function ScheduleApply(reason)
  if applyScheduled then
    return
  end
  applyScheduled = reason or true
  C_Timer.After(0, function()
    local r = applyScheduled
    applyScheduled = nil
    GF.ApplyBlizzardGroupFrameOwnership(r)
  end)
end

local function FlushPending()
  for frame in next, pendingHide do
    pendingHide[frame] = nil
    if frame and ownedFrames[frame] and ownedFrames[frame].hidden then
      if frame.Hide and not IsForbidden(frame) then
        frame:Hide()
      end
      HookFrame(frame)
      ReparentHidden(frame)
    end
  end
  if raidManagerPendingMouse ~= nil then
    local wanted = raidManagerPendingMouse
    raidManagerPendingMouse = nil
    ApplyRaidManagerMouse(_G.CompactRaidFrameManager, wanted)
  end
end

local function OnEvent(self, event, arg1)
  if event == "PLAYER_REGEN_ENABLED" then
    RefreshRosterEventRegistration()
    FlushPending()
    if GF._pendingBlizzardGroupOwnership then
      local reason = GF._pendingBlizzardGroupOwnership
      GF._pendingBlizzardGroupOwnership = nil
      ScheduleApply(reason)
    else
      ScheduleApply("regen-enabled")
    end
  elseif event == "PLAYER_REGEN_DISABLED" then
    UnregisterRosterEvent()
  elseif event == "ADDON_LOADED" then
    if arg1 == "Blizzard_CompactRaidFrames" or arg1 == "Blizzard_UnitFrame" or arg1 == addonName then
      ScheduleApply("addon-loaded:" .. tostring(arg1))
    end
  else
    if event == "GROUP_ROSTER_UPDATE" and InCombat() then
      return
    end
    ScheduleApply(event)
  end
end

eventFrame = EnsureEventFrame()
eventFrame:SetScript("OnEvent", OnEvent)
SetBlizzardEventsEnabled()

ExportPublic("MSUF_GF_DisableBlizzard", function()
  return GF.ApplyBlizzardGroupFrameOwnership("legacy-global")
end)
