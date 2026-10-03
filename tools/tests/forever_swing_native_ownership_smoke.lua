-- forever_swing_native_ownership_smoke.lua <repoRoot>
--
-- MSUF's WoW Forever swing timers replace Blizzard_SwingTimer's three bars.
-- Blizzard owns those bars' visibility through the showSwingTimer CVar:
-- CVarCallbackRegistry (Blizzard_SharedXMLBase/CvarUtil.lua) handles
-- CVAR_UPDATE in its own secure handler and calls
-- SwingTimerManagerMixin:OnShowSwingTimerCVarChanged, which runs
-- UpdateFrameState on every bar (upstream/forever Blizzard_SwingTimer.lua).
-- Only Blizzard's Edit Mode shows a bar while the CVar is off
-- (ShouldBeShown: isInEditMode).
--
-- Pinned:
--   * MSUF never writes a field onto a Blizzard bar (side table instead);
--   * MSUF never shows, hides or re-registers a Blizzard bar itself, Edit
--     Mode included (each would run the BottomManagedFrame container layout,
--     which also lays out ExtraAbilityContainer, from addon code: the bars
--     inherit BottomManagedFrameTemplate); setting the CVar is enough, on
--     enable, apply, a user re-enabling the CVar, Blizzard_SwingTimer loading
--     late, and disable. Before the fix MSUF hid a bar Blizzard's Edit Mode
--     showed (red without the fix);
--   * the bars end hidden while MSUF owns them; in Edit Mode, where only
--     Blizzard can hide them, they are invisible (alpha 0) and Blizzard hides
--     them itself on exit;
--   * Blizzard restores them when MSUF releases a CVar that was on, with the
--     alpha Blizzard had set (the Edit Mode opacity).
--
-- Plain Lua 5.1, repo root as arg 1.
local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local now, combat, cvarOn = 100, false, true
local objects, named, driver = {}, {}, nil
local function noop() end

-- MSUF's own widgets: a permissive model, as in the settings smoke.
local methods = {}
for _, name in ipairs({
    "SetMovable", "SetClampedToScreen", "RegisterForDrag", "SetAllPoints", "SetJustifyH",
    "SetBackdropBorderColor", "ClearAllPoints", "SetTextColor", "SetWidth", "SetHeight",
    "StopMovingOrSizing", "StartMoving", "SetUpdateInterval", "SetExpiredText", "SetZeroDurationText",
    "SetTexCoord", "SetMinMaxValues", "SetFrameLevel", "SetOrientation", "SetRotatesTexture",
    "SetHorizTile", "SetVertTile", "SetSize", "SetScale", "SetAlpha", "SetPoint", "SetBackdrop",
    "SetStatusBarColor", "SetStatusBarTexture", "SetTexture", "SetVertexColor", "SetReverseFill",
    "SetText", "SetValue", "EnableMouse", "SetTimerDuration",
}) do methods[name] = noop end
function methods:GetFrameLevel() return 1 end
function methods:GetStatusBarTexture() return self end
function methods:GetScale() return 1 end
function methods:GetCenter() return 500, 400 end
function methods:SetFont() return true end
function methods:SetScript(key, value) self.scripts[key] = value end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value and true or false end
function methods:IsShown() return self.shown == true end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:RegisterUnitEvent(event) self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:UnregisterAllEvents() self.events = {} end
local function object(name, parent)
    local o = setmetatable({ scripts = {}, events = {}, name = name, parent = parent, shown = true },
        { __index = methods })
    objects[#objects + 1] = o
    if name then named[name] = o end
    return o
end
function methods:CreateTexture() return object(nil, self) end
function methods:CreateFontString() return object(nil, self) end
_G.CreateFrame = function(kind, name, parent)
    local o = object(name, parent)
    if kind == "Frame" and not name and not parent then driver = o end
    return o
end

-- Blizzard's bars: strict proxies. Blizzard's own model code works on the
-- private state; everything MSUF does goes through the proxy and is logged.
local nativeBars, nativeState, addonCalls = {}, {}, {}
local editMode = false

local function ShouldBeShown(state)
    if state.fields.isInEditMode then return true end
    return cvarOn
end

-- The client running a Show on a bar: OnShow scripts and hooks follow.
local function ClientSetShown(bar, shown)
    local state = nativeState[bar]
    local was = state.shown
    state.shown = shown and true or false
    if state.shown and not was then
        for _, hook in ipairs(state.onShowHooks) do hook(bar) end
    end
end

-- SwingTimerMixin:UpdateFrameState / UpdateShownState, run by Blizzard.
local function BlizzardUpdateShownState(bar)
    ClientSetShown(bar, ShouldBeShown(nativeState[bar]))
end

local NATIVE_METHODS = {}
function NATIVE_METHODS.IsShown(bar) return nativeState[bar].shown == true end
function NATIVE_METHODS.GetAlpha(bar) return nativeState[bar].alpha end
-- A frame's alpha runs no script and no container layout.
function NATIVE_METHODS.SetAlpha(bar, alpha) nativeState[bar].alpha = alpha end
function NATIVE_METHODS.HookScript(bar, script, handler)
    Check(script == "OnShow", "unexpected native hook " .. tostring(script))
    local state = nativeState[bar]
    state.onShowHooks[#state.onShowHooks + 1] = handler
end
for _, name in ipairs({ "Show", "Hide", "SetShown", "UpdateShownStateAndRegistration", "UpdateFrameState",
                        "UpdateShownState" }) do
    NATIVE_METHODS[name] = function(bar, ...)
        addonCalls[#addonCalls + 1] = { bar = bar, method = name, editMode = editMode }
        if name == "Show" then ClientSetShown(bar, true)
        elseif name == "Hide" then ClientSetShown(bar, false)
        elseif name == "SetShown" then ClientSetShown(bar, (...))
        else BlizzardUpdateShownState(bar) end
    end
end

for _, hand in ipairs({ "MainHand", "OffHand", "Ranged" }) do
    local bar = setmetatable({}, {
        __index = function(_, key)
            local method = NATIVE_METHODS[key]
            if method then return method end
            return nativeState[_G["SwingTimer" .. hand .. "Frame"]].fields[key]
        end,
        __newindex = function(_, key)
            error("MSUF wrote the field " .. tostring(key) .. " onto Blizzard's SwingTimer" .. hand .. "Frame", 2)
        end,
    })
    -- 0.8: the bar's Edit Mode opacity (EditModeSwingTimerSystemMixin SetAlpha).
    nativeState[bar] = { shown = false, alpha = 0.8, onShowHooks = {}, fields = { isInEditMode = false } }
    _G["SwingTimer" .. hand .. "Frame"] = bar
    nativeBars[#nativeBars + 1] = bar
    BlizzardUpdateShownState(bar)
end

local function DriverEvent(event, ...)
    if driver and driver.events[event] and driver.scripts.OnEvent then driver.scripts.OnEvent(driver, event, ...) end
end

-- CVAR_UPDATE reaches CVarCallbackRegistry (registered at Blizzard load, so
-- first) and then MSUF's driver.
_G.GetCVarBool = function(key) Check(key == "showSwingTimer", key) return cvarOn end
_G.SetCVar = function(key, value)
    Check(key == "showSwingTimer", key)
    local on = value == "1"
    if on == cvarOn then return end
    cvarOn = on
    for _, bar in ipairs(nativeBars) do BlizzardUpdateShownState(bar) end
    DriverEvent("CVAR_UPDATE", key, value)
end

local function SetEditMode(active)
    editMode = active
    for _, bar in ipairs(nativeBars) do
        -- SwingTimerMixin:SetIsInEditMode: the field first, then the show state.
        nativeState[bar].fields.isInEditMode = active
        BlizzardUpdateShownState(bar)
    end
end

_G.UIParent = object("UIParent")
_G.GetTime = function() return now end
_G.InCombatLockdown = function() return combat end
_G.UnitAffectingCombat = function() return combat end
_G.UnitAttackSpeed = function() return 2, 2.5, 2.8 end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.STANDARD_TEXT_FONT = "test-font"
_G.Enum = {
    PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 },
    StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 }, StatusBarInterpolation = { Immediate = 0 },
    NumericRuleFormatRounding = { Nearest = 0 }, DurationTextBindingProperty = { RemainingDuration = 0 },
}
_G.C_DurationUtil = {
    CreateDuration = function()
        return { Reset = noop, SetTimeFromEnd = noop }
    end,
    CreateDurationTextBinding = function()
        return { SetEnabled = noop, SetFontString = noop, SetDuration = noop, SetTextFormat = noop,
            SetUpdateInterval = noop, SetExpiredText = noop, SetZeroDurationText = noop }
    end,
}
_G.C_StringUtil = { CreateNumericRuleFormatter = function() return { SetBreakpoints = noop } end }
_G.C_SwingTimer = { EnableRangeCheck = noop, IsTargetWithinSwingRange = function() return nil end }
_G.C_Spell = { GetSpellName = function() return nil end, IsCurrentSpell = function() return false end }

local ns = { Client = { IsForever = true } }
ns.ExportPublic = function(key, value) _G[key] = value end
ns.LSM = { Fetch = function() return nil end, List = function() return {} end, HashTable = function() return {} end }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Libs.lua"))("MSUF", ns)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Modules.lua"))("MSUF", ns)
_G.MSUF_DB = {}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Game/Forever/SwingTimer.lua"))("MSUF", ns)
local swing = assert(ns.SwingTimer, "SwingTimer module missing")

local function AssertNoAddonLayout(step)
    for _, call in ipairs(addonCalls) do
        Check(false, step .. ": MSUF called " .. call.method .. " on a Blizzard swing bar"
            .. (call.editMode and " in Edit Mode" or ""))
    end
end
local function AssertNativeInvisible(step)
    for index, bar in ipairs(nativeBars) do
        Check(not bar:IsShown() or nativeState[bar].alpha == 0,
            step .. ": Blizzard swing bar " .. index .. " is visible while MSUF owns it")
    end
end
local function AssertNativeHidden(step)
    for index, bar in ipairs(nativeBars) do
        Check(not bar:IsShown(), step .. ": Blizzard swing bar " .. index .. " is shown while MSUF owns it")
    end
end

-- Login: MSUF takes over; the CVar path hides Blizzard's bars.
for _, bar in ipairs(nativeBars) do Check(bar:IsShown(), "harness: native bars start shown") end
DriverEvent("PLAYER_ENTERING_WORLD")
Check(not cvarOn, "MSUF did not turn the native CVar off")
AssertNativeHidden("enable")
AssertNoAddonLayout("enable")

-- A settings apply keeps ownership without touching the bars.
Check(swing.Set("main", "width", 300), "settings apply failed")
AssertNativeHidden("apply")
AssertNoAddonLayout("apply")

-- The user turns Blizzard's swing timer on in the game options.
_G.SetCVar("showSwingTimer", "1")
Check(not cvarOn, "MSUF did not reclaim the native CVar")
AssertNativeHidden("user CVar")
AssertNoAddonLayout("user CVar")

-- Blizzard_SwingTimer loading after MSUF.
DriverEvent("ADDON_LOADED", "Blizzard_SwingTimer")
AssertNativeHidden("late Blizzard_SwingTimer")
AssertNoAddonLayout("late Blizzard_SwingTimer")

-- Blizzard's Edit Mode shows its bars although the CVar is off; MSUF makes
-- them invisible there (the one case the CVar cannot cover), never hidden.
SetEditMode(true)
AssertNativeInvisible("Edit Mode")
AssertNoAddonLayout("Edit Mode")
-- A settings apply while Edit Mode shows them keeps them invisible.
Check(swing.Set("main", "height", 20), "Edit Mode settings apply failed")
AssertNativeInvisible("Edit Mode apply")
AssertNoAddonLayout("Edit Mode apply")
SetEditMode(false)
AssertNativeHidden("after Edit Mode")
AssertNoAddonLayout("after Edit Mode")

-- Release with the CVar originally on: Blizzard restores its bars itself,
-- at the alpha Blizzard had set.
Check(swing.SetEnabled(false), "disable failed")
Check(cvarOn, "MSUF did not restore the native CVar")
for index, bar in ipairs(nativeBars) do
    Check(bar:IsShown(), "release: Blizzard swing bar " .. index .. " stayed hidden")
    Check(nativeState[bar].alpha == 0.8, "release: Blizzard swing bar " .. index .. " kept alpha "
        .. tostring(nativeState[bar].alpha))
end
AssertNoAddonLayout("release")

-- Release with the CVar originally off: the bars stay hidden.
_G.SetCVar("showSwingTimer", "0")
Check(swing.SetEnabled(true), "re-enable failed")
Check(swing.SetEnabled(false), "second disable failed")
Check(not cvarOn, "MSUF turned on a CVar that was off")
AssertNativeHidden("release with the CVar off")
AssertNoAddonLayout("release with the CVar off")

print("forever_swing_native_ownership_smoke: ok")
