-- group_raid_manager_toggles_smoke.lua <repoRoot>
--
-- Raid Manager "Hidden" must leave nothing clickable on Midnight and WoW Forever.
-- Blizzard_CompactRaidFrameManager.xml (upstream/live:123-160, upstream/forever)
-- gives the Mainline manager two child Buttons, toggleButtonForward (shown while
-- collapsed) and toggleButtonBack (while expanded). Buttons own their mouse
-- state, so the manager's EnableMouse(false) left them clickable at alpha 0: an
-- invisible button at the left screen edge opened an invisible panel. The
-- Classic family keeps its single legacy toggle (classic_raid_manager_mode_smoke).
--
-- Contract on the Mainline family:
--   * HIDDEN (and AUTO while MSUF owns the frames) makes the manager and both
--     toggles click-through; SHOW and MOUSEOVER hand back each one's default;
--   * an expanded invisible panel keeps its toggles so it can be collapsed, and
--     the collapse click hands them back to click-through;
--   * EnableMouse on a protected manager or toggle waits for PLAYER_REGEN_ENABLED
--     and lands there; the alpha half lands at once.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local inCombat = false
local violations = {}

local function NewFrame(name, mouse)
    local frame = { name = name, hooks = {}, mouseEnabled = mouse, protected = false, alpha = 1 }
    function frame:HookScript(kind, callback) self.hooks[kind] = callback end
    function frame:IsForbidden() return false end
    function frame:IsProtected() return self.protected end
    function frame:IsMouseEnabled() return self.mouseEnabled end
    function frame:EnableMouse(enabled)
        if inCombat and self.protected then violations[#violations + 1] = self.name .. ":EnableMouse" end
        self.mouseEnabled = enabled and true or false
    end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    function frame:GetParent() return _G.UIParent end
    return frame
end

local configs = {
    party = { enabled = false, showSolo = false, showPlayer = true, blizzardFallbackMode = "SHOW", raidManagerMode = "SHOW" },
    raid = { enabled = false, blizzardFallbackMode = "SHOW" },
    mythicraid = { enabled = false, blizzardFallbackMode = "SHOW" },
}

local eventFrame = { events = {} }
function eventFrame:RegisterEvent(event) self.events[event] = true end
function eventFrame:UnregisterEvent(event) self.events[event] = nil end
function eventFrame:UnregisterAllEvents() self.events = {} end
function eventFrame:SetScript(kind, callback) self[kind] = callback end
function eventFrame:SetAllPoints() end
function eventFrame:Hide() end

local forward = NewFrame("toggleButtonForward", true)
local back = NewFrame("toggleButtonBack", true)
local legacy = NewFrame("toggleButton", true)
local manager = NewFrame("CompactRaidFrameManager", true)
manager.collapsed = true
manager.displayFrame = NewFrame("displayFrame", true)
local gamepad = false
_G.InputUtil = { IsGamepadUIEnabled = function() return gamepad end }
_G.CompactRaidFrameManager_InitializeGamepad = function() end
manager.toggleButtonForward, manager.toggleButtonBack = forward, back

_G.MSUF_NS = {
    Client = { Family = "Mainline", IsRetail = true },
    ExportPublic = function(name, value) _G[name] = value; return value end,
    GF = {
        GetConf = function(kind) return configs[kind] end,
        GetLiveRaidKind = function() return "raid" end,
        IsSmallRaidPartyContext = function() return false end,
    },
}
_G.CreateFrame = function() return eventFrame end
_G.UIParent = {}
_G.InCombatLockdown = function() return inCombat end
_G.IsInGroup = function() return false end
_G.IsInRaid = function() return false end
_G.GetNumGroupMembers = function() return 0 end
_G.GetMouseFoci = function() return {} end
_G.hooksecurefunc = function() end
_G.C_Timer = { After = function(_, callback) callback() end }
_G.CompactRaidFrameManager = manager
-- A legacy global must never be touched on Mainline.
_G.CompactRaidFrameManagerToggleButton = legacy

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Blizzard.lua"))(
    "MidnightSimpleUnitFrames", _G.MSUF_NS)
local GF = assert(_G.MSUF_NS.GF)

local function SetMode(mode)
    configs.party.raidManagerMode = mode
    return GF.ApplyBlizzardRaidManagerMode()
end

local function Mouse()
    return manager.mouseEnabled, forward.mouseEnabled, back.mouseEnabled
end

Check(SetMode("SHOW") == "SHOW", "SHOW did not resolve")
local m, f, b = Mouse()
Check(m and f and b and manager.alpha == 1, "SHOW must keep the manager and both toggles interactive")

-- Collapsed HIDDEN: nothing at the screen edge may take a click.
Check(SetMode("HIDDEN") == "HIDDEN", "HIDDEN did not resolve")
m, f, b = Mouse()
Check(manager.alpha == 0 and m == false, "HIDDEN must be invisible and click-through")
Check(f == false, "HIDDEN left the invisible toggleButtonForward clickable")
Check(b == false, "HIDDEN left toggleButtonBack clickable")
Check(type(forward.hooks.OnClick) == "function" and type(back.hooks.OnClick) == "function",
    "HIDDEN must hook both split toggles")
Check(legacy.hooks.OnClick == nil and legacy.mouseEnabled == true, "Mainline touched the legacy toggle button")

-- An expanded invisible panel keeps its toggles; collapsing hands them back.
manager.collapsed = false
SetMode("HIDDEN")
m, f, b = Mouse()
Check(m == false and b == true, "an expanded HIDDEN panel must keep toggleButtonBack clickable to collapse it")
manager.collapsed = true -- what CompactRaidFrameManager_Collapse does before our hook runs
back.hooks.OnClick(back)
m, f, b = Mouse()
Check(f == false and b == false, "the collapse click did not hand the toggles back to click-through")

Check(SetMode("MOUSEOVER") == "MOUSEOVER", "MOUSEOVER did not resolve")
m, f, b = Mouse()
Check(m and f and b and manager.alpha == 0, "MOUSEOVER must restore every default and stay transparent")

-- Reapplying a mode must respect an already expanded panel, including a
-- gamepad panel opened while SHOW had not installed the display hooks yet.
manager.collapsed = false
SetMode("MOUSEOVER")
Check(manager.alpha == 1, "MOUSEOVER reapply hid the expanded panel")
manager.collapsed = true
SetMode("MOUSEOVER")
Check(manager.alpha == 0, "collapsed MOUSEOVER did not fade")
SetMode("SHOW")
gamepad, manager.collapsed = true, false
SetMode("HIDDEN")
Check(manager.alpha == 1, "HIDDEN hid an already-open gamepad panel")
manager.collapsed = true
manager.displayFrame.hooks.OnHide(manager.displayFrame)
Check(manager.alpha == 0, "gamepad close did not restore HIDDEN")
gamepad = false

-- AUTO while MSUF owns the live group frames resolves to HIDDEN.
configs.party.enabled, configs.party.showSolo = true, true
Check(SetMode("AUTO") == "AUTO", "AUTO did not resolve")
m, f, b = Mouse()
Check(manager.alpha == 0 and not m and not f and not b, "AUTO with MSUF frames must make every toggle click-through")
configs.party.enabled, configs.party.showSolo = false, false
SetMode("SHOW")
m, f, b = Mouse()
Check(m and f and b, "SHOW after AUTO must restore every default")

-- Combat: a protected toggle's mouse waits for regen; the alpha lands at once.
for _, protectedFrame in ipairs({ manager, forward }) do
    protectedFrame.protected = true
    inCombat = true
    SetMode("HIDDEN")
    Check(#violations == 0, "EnableMouse ran in lockdown on " .. tostring(violations[1]))
    Check(manager.alpha == 0, "the alpha half must land in combat")
    Check(forward.mouseEnabled == true, "a protected " .. protectedFrame.name .. " changed mouse state in lockdown")
    Check(eventFrame.events.PLAYER_REGEN_ENABLED == true, "the mouse change was not parked for regen")
    inCombat = false
    eventFrame.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
    m, f, b = Mouse()
    Check(not m and not f and not b, "the parked HIDDEN mouse state did not land at regen (" .. protectedFrame.name .. ")")
    protectedFrame.protected = false
    SetMode("SHOW")
end

print("group_raid_manager_toggles_smoke: ok (Mainline split toggles: HIDDEN, expanded, AUTO, combat deferral)")
