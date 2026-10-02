local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- UnitFrames/Engine/Group/MSUF_UF_Group_Blizzard.lua
--- Ownership adapter for Blizzard party/raid frames.
---
--- When MSUF group frames are enabled, Blizzard's group-frame owners are hidden
--- without touching their secret-aware unit buttons. Returning ownership is a
--- reload-only transition; protected hide/reparent work is deferred out of combat.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic

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
  hiddenParent = PixelLayoutRegion(CreateFrame("Frame", "MSUF_GF_BlizzardHiddenParent", UIParent))
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

--- Classic flavors run Blizzard_CompactRaidFrames' Classic family files, whose
--- manager parents the raid container itself and keeps the single legacy toggle
--- button. Read once here; Mainline never enters the Classic branches below.
local IS_CLASSIC_FAMILY = MSUF.Client ~= nil and MSUF.Client.Family == "Classic"

--- Classic: the hidden-parent guard exists for foreign addons that already parked a
--- frame. Classic's CompactRaidFrameManager is hidden by default and parents the
--- container itself, so Blizzard's own hidden manager must not count as someone
--- else's owner -- otherwise a solo login keeps the container there and a
--- mid-combat raid join shows it.
if IS_CLASSIC_FAMILY then
  local IsAnyHiddenFrameParent = IsHiddenFrameParent
  IsHiddenFrameParent = function(parent)
    return parent ~= nil and parent ~= _G.CompactRaidFrameManager and IsAnyHiddenFrameParent(parent)
  end
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

--- A small raid on the Party layout hides Blizzard's raid frames only while the
--- raid has five members or fewer. That is roster state, not an ownership change,
--- so it has to reverse mid-session and in combat, and addon code must never show
--- Blizzard's frames itself: CompactUnitFrame_OnShow would run tainted on 12.1.
--- The container goes under this proxy instead of the hidden parent; a secure
--- state driver owns the proxy's visibility (SecureStateDriver.lua resolveDriver,
--- re-applied every 0.2 s and on GROUP_ROSTER_UPDATE). Raid tokens are contiguous
--- and Blizzard shows the container only in a raid (ShouldShowRaidFrames), so
--- "raid6 exists" is exactly "more than five members".
local SMALL_RAID_PROXY_VISIBILITY = "[@raid6,exists] show; hide"
local smallRaidProxy
local softParked

local function SmallRaidProxy()
  if smallRaidProxy then
    return smallRaidProxy
  end
  smallRaidProxy = PixelLayoutRegion(CreateFrame("Frame", "MSUF_GF_BlizzardSmallRaidParent", UIParent))
  smallRaidProxy:SetAllPoints()
  -- Registered while the proxy is still empty: the driver resolves once inside
  -- this call, which must not show or hide anything of Blizzard's.
  local registerStateDriver = _G.RegisterStateDriver
  if registerStateDriver then
    registerStateDriver(smallRaidProxy, "visibility", SMALL_RAID_PROXY_VISIBILITY)
  end
  return smallRaidProxy
end

--- Hard hiding prefers reparenting to a hidden parent; a soft-hidden frame goes
--- under the small-raid proxy. Protected frames cannot always be reparented in
--- combat, so those requests are queued for regen.
local function ReparentHidden(frame)
  if not (frame and frame.SetParent) or IsForbidden(frame) then
    return
  end
  if InCombat() and frame.IsProtected and frame:IsProtected() then
    DeferHide(frame)
    return
  end
  local info = ownedFrames[frame]
  local parent = info and info.soft and SmallRaidProxy() or HiddenParent()
  local current = frame.GetParent and frame:GetParent()
  if current == parent then
    return
  end
  if current ~= hiddenParent and current ~= smallRaidProxy then
    if IsHiddenFrameParent(current) then
      return
    end
    if info then info.original = current end
  end
  frame:SetParent(parent)
end

local function ResetParent(frame, parent)
  local info = ownedFrames[frame]
  if not (info and info.hidden) then
    return
  end
  if parent == hiddenParent or parent == smallRaidProxy or IsHiddenFrameParent(parent) then
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

--- Hard hide: Hide() and park under the hidden parent. Soft hide (the small-raid
--- case): park under the proxy and leave the frame's own shown state to Blizzard;
--- a hard-hidden frame moves over unchanged (no visibility edge), and Blizzard's
--- next container update shows it from secure code.
local function HideFrame(frame, soft)
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
  info.soft = soft == true or nil
  if soft then
    softParked = frame
  elseif softParked == frame then
    softParked = nil
  end

  if InCombat() and frame.IsProtected and frame:IsProtected() then
    DeferHide(frame)
    return frame
  end
  if frame.Hide and not soft then
    frame:Hide()
  end
  HookFrame(frame)
  ReparentHidden(frame)
  return frame
end

--- Give a soft-parked frame back to its own parent once the feature that parked
--- it is off. Only while the proxy is visible: then the move changes no
--- visibility and runs no Blizzard script. Otherwise the next pass retries.
local function ReleaseSoftHiddenFrame(frame)
  frame = ResolveFrame(frame)
  local info = frame and ownedFrames[frame]
  if not (info and info.soft) then
    return false
  end
  if InCombat() or not (smallRaidProxy and smallRaidProxy:IsVisible()) then
    return false
  end
  info.hidden, info.soft = false, nil
  softParked = nil
  if frame:GetParent() == smallRaidProxy then
    frame:SetParent(info.original or UIParent)
  end
  return true
end

local function HidePartyFrames()
  -- CompactPartyFrame and the classic PartyMemberFrame pool are descendants of
  -- PartyFrame on 12.1. Hide only that owner; touching individual unit buttons
  -- would taint their secret-aware health/event execution.
  HideFrame(_G.PartyFrame)
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
  HideFrame(_G.CompactRaidFrameReservationManager)
  HideFrame(_G.CompactRaidFrameContainer)
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

--- The tab's toggle buttons are child Buttons with their own mouse state, so the
--- manager's EnableMouse(false) leaves them clickable: at alpha 0 an invisible
--- button at the screen edge would open an invisible panel. Mainline 12.1 and WoW
--- Forever split the toggle into toggleButtonForward (shown while collapsed) and
--- toggleButtonBack (while expanded); the Classic branches keep one legacy
--- toggleButton (Blizzard_CompactRaidFrameManager.xml, upstream/live, upstream/forever,
--- and the Classic family files on classic_era/classic). Mainline never touches the
--- legacy key.
local SPLIT_TOGGLES = {
  { key = "toggleButtonForward", global = "CompactRaidFrameManagerToggleButtonForward" },
  { key = "toggleButtonBack", global = "CompactRaidFrameManagerToggleButtonBack" },
}
local RAID_MANAGER_TOGGLES = IS_CLASSIC_FAMILY and {
  { key = "toggleButton", global = "CompactRaidFrameManagerToggleButton" },
  SPLIT_TOGGLES[1], SPLIT_TOGGLES[2],
} or SPLIT_TOGGLES
--- Side table: each button's own mouse default, read once before the first write.
local raidManagerToggleMouseDefault = {}
--- The mode ApplyRaidManagerMode last resolved AUTO into.
local raidManagerEffectiveMode = "SHOW"

local function RaidManagerToggle(manager, index)
  local toggle = RAID_MANAGER_TOGGLES[index]
  local button = manager[toggle.key] or _G[toggle.global]
  if button and not IsForbidden(button) then return button end
  return nil
end

local function MouseScriptable(frame)
  return type(frame.EnableMouse) == "function" and type(frame.IsMouseEnabled) == "function"
end

local function MouseEnabled(frame)
  return frame:IsMouseEnabled() and true or false
end

--- HIDDEN drops mouse input from the manager and every toggle, so the invisible
--- tab stops eating clicks at the left screen edge. An expanded invisible panel
--- keeps its toggles so the user can still collapse it; the toggle hook hands them
--- back to click-through afterwards. EnableMouse is protected once the frame is,
--- so a combat request parks the wanted state for regen -- the alpha write already
--- did the visible half.
local function ApplyRaidManagerMouse(manager, enabled)
  if not (manager and MouseScriptable(manager)) then
    return
  end
  if raidManagerMouseDefault == nil then
    raidManagerMouseDefault = MouseEnabled(manager)
  end
  local wanted = enabled and raidManagerMouseDefault or false
  local keepToggles = enabled or manager.collapsed == false
  local changed = MouseEnabled(manager) ~= wanted
  local protected = manager.IsProtected and manager:IsProtected()
  for i = 1, #RAID_MANAGER_TOGGLES do
    local button = RaidManagerToggle(manager, i)
    if button and MouseScriptable(button) then
      local default = raidManagerToggleMouseDefault[button]
      if default == nil then
        default = MouseEnabled(button)
        raidManagerToggleMouseDefault[button] = default
      end
      changed = changed or MouseEnabled(button) ~= (default and keepToggles)
      protected = protected or (button.IsProtected and button:IsProtected())
    end
  end
  if not changed then
    raidManagerPendingMouse = nil
    return
  end
  if InCombat() and protected then
    raidManagerPendingMouse = enabled and true or false
    EnsureEventFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
    return
  end
  raidManagerPendingMouse = nil
  if MouseEnabled(manager) ~= wanted then
    manager:EnableMouse(wanted)
  end
  for i = 1, #RAID_MANAGER_TOGGLES do
    local button = RaidManagerToggle(manager, i)
    local default = button and raidManagerToggleMouseDefault[button]
    if default ~= nil and MouseEnabled(button) ~= (default and keepToggles) then
      button:EnableMouse(default and keepToggles)
    end
  end
end

--- A collapse click fades a MOUSEOVER panel and hands a HIDDEN panel's toggles
--- back to click-through.
local function RaidManagerOnToggleClick()
  local manager = _G.CompactRaidFrameManager
  if not manager then return end
  if raidManagerMode == "MOUSEOVER" and manager.collapsed and manager.SetAlpha then
    manager:SetAlpha(0)
  end
  if raidManagerEffectiveMode == "HIDDEN" then
    ApplyRaidManagerMouse(manager, false)
  end
end

local function EnsureRaidManagerHooks(manager)
  if raidManagerHooked or type(manager.HookScript) ~= "function" then return end
  raidManagerHooked = true
  manager:HookScript("OnEnter", RaidManagerOnEnter)
  manager:HookScript("OnLeave", RaidManagerOnLeave)
  for i = 1, #RAID_MANAGER_TOGGLES do
    local button = RaidManagerToggle(manager, i)
    if button and type(button.HookScript) == "function" then
      button:HookScript("OnClick", RaidManagerOnToggleClick)
    end
  end
end

--- Gamepad UI (WoW Forever 1.60.1.70009+, where Blizzard's manager has
--- CompactRaidFrameManager_InitializeGamepad): Blizzard's GAMEPAD_MENU_LEFT binding
--- expands the manager whenever it is shown, and every mode here keeps it shown at
--- alpha 0. The binding holds its own reference to CompactRaidFrameManager_Expand, so
--- a function hook would miss it; displayFrame shows exactly while the panel is
--- expanded. A panel the gamepad opened holds gamepad focus, so it is lit while open,
--- as in the stock UI, and closing it hands the alpha back to the mode.
local function RaidManagerGamepadUIActive()
  local inputUtil = _G.InputUtil
  return type(inputUtil) == "table" and type(inputUtil.IsGamepadUIEnabled) == "function"
    and inputUtil.IsGamepadUIEnabled() == true
end

local function RaidManagerDisplayOnShow()
  local manager = _G.CompactRaidFrameManager
  if not manager or raidManagerEffectiveMode == "SHOW" or not RaidManagerGamepadUIActive() then return end
  manager._msufGamepadLit = true
  manager:SetAlpha(1)
end

local function RaidManagerDisplayOnHide()
  local manager = _G.CompactRaidFrameManager
  if not (manager and manager._msufGamepadLit) then return end
  manager._msufGamepadLit = nil
  if raidManagerEffectiveMode == "SHOW" then return end
  if raidManagerEffectiveMode == "MOUSEOVER" and MouseIsOverRaidManager(manager) then return end
  manager:SetAlpha(0)
end

local raidManagerGamepadHooked = false
local function EnsureRaidManagerGamepadHooks(manager)
  if raidManagerGamepadHooked or type(_G.CompactRaidFrameManager_InitializeGamepad) ~= "function" then return end
  local display = manager.displayFrame
  if not (display and type(display.HookScript) == "function") or IsForbidden(display) then return end
  raidManagerGamepadHooked = true
  display:HookScript("OnShow", RaidManagerDisplayOnShow)
  display:HookScript("OnHide", RaidManagerDisplayOnHide)
end

--- Classic: Blizzard_CompactRaidFrames/Classic parents the raid container to the
--- manager (CompactRaidFrameManager_OnLoad: self.container:SetParent(self)), so a
--- mode that fades the tab would fade the raid frames with it -- invisible but still
--- clickable. The container ignores its parent's alpha while a mode lowers it, and
--- gets Blizzard's default back otherwise. Not protected, so it lands in combat too.
local raidContainerIgnoresManagerAlpha = false
local function KeepRaidContainerOpaque(lowered)
  local container = _G.CompactRaidFrameContainer
  if not (container and type(container.SetIgnoreParentAlpha) == "function") or IsForbidden(container) then
    return
  end
  if lowered == raidContainerIgnoresManagerAlpha then return end
  container:SetIgnoreParentAlpha(lowered)
  raidContainerIgnoresManagerAlpha = lowered
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
  raidManagerEffectiveMode = mode
  -- The toggle hook hands a collapsed HIDDEN panel's toggles back to click-through.
  if mode == "HIDDEN" then EnsureRaidManagerHooks(manager) end
  if IS_CLASSIC_FAMILY then
    KeepRaidContainerOpaque(mode ~= "SHOW")
  elseif mode ~= "SHOW" then
    EnsureRaidManagerGamepadHooks(manager)
  end
  -- An open gamepad panel stays lit until it closes (RaidManagerDisplayOnHide).
  local gamepadLit = manager._msufGamepadLit == true and mode ~= "SHOW"

  if mode == "HIDDEN" then
    manager:SetAlpha(gamepadLit and 1 or 0)
    ApplyRaidManagerMouse(manager, false)
    return
  end
  ApplyRaidManagerMouse(manager, true)
  if mode == "MOUSEOVER" then
    EnsureRaidManagerHooks(manager)
    manager:SetAlpha((gamepadLit or MouseIsOverRaidManager(manager)) and 1 or 0)
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
  local kind = LiveGroupKind()
  if kind == "party" then return true end
  return kind == nil and party.showSolo == true and party.showPlayer ~= false
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
  if MSUFOwnsLiveGroupFrames() or softParked ~= nil then
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
  -- A small raid on the Party layout is shown by the MSUF party frames, so
  -- Blizzard's raid frames must not show the same raid a second time -- but only
  -- while it is small. Parked on the first small raid; the proxy's driver then
  -- follows the roster for the rest of the session, combat included.
  local smallRaidWanted = partyUsesMSUF and partyConf.smallRaidAsParty == true
  local smallRaidPark = smallRaidWanted
    and (softParked ~= nil or (GF.IsSmallRaidPartyContext ~= nil and GF.IsSmallRaidPartyContext() == true))
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
    .. "|" .. tostring(smallRaidPark)
    .. "|" .. tostring(softParked ~= nil)
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
  elseif raidMode == "NONE" then
    ApplyDisabledRaidFallback(raidMode)
  elseif smallRaidPark then
    HideFrame(_G.CompactRaidFrameContainer, true)
  else
    ReleaseSoftHiddenFrame(_G.CompactRaidFrameContainer)
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
    local info = frame and ownedFrames[frame]
    if info and info.hidden then
      if frame.Hide and not info.soft and not IsForbidden(frame) then
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

ExportPublic("MSUF_NormalizeRaidManagerMode", NormalizeRaidManagerMode)
