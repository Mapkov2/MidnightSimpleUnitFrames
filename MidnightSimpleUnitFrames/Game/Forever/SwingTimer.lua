--- Forever Swing Timer settings use Blizzard's own frames and Edit Mode layout.
--- Blizzard_SwingTimer owns swing events, range checks, and bar animation.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
if not (MSUF.Client and MSUF.Client.IsForever == true) then return end

local Swing = {}
MSUF.SwingTimer = Swing

local FRAME_NAMES = {
    main = "SwingTimerMainHandFrame",
    off = "SwingTimerOffHandFrame",
    ranged = "SwingTimerRangedFrame",
}
local INDEX_NAMES = { main = "MainHand", off = "OffHand", ranged = "Ranged" }
local SETTING_NAMES = {
    scale = "Scale", opacity = "Opacity", visibility = "Visibility",
    width = "Width", height = "Height",
    title = "ShowBarTitle", time = "ShowTime",
}
local LIMITS = {
    scale = { 50, 200, 10 }, opacity = { 50, 100, 1 },
    width = { 213, 852, 1 }, height = { 15, 60, 1 },
}

local function Blocked()
    return (_G.InCombatLockdown and _G.InCombatLockdown())
        or (MSUF.Client.IsGameRuleActive and MSUF.Client.IsGameRuleActive("EditModeDisabled"))
end

local function Native(hand)
    local enum = _G.Enum
    local system = enum and enum.EditModeSystem and enum.EditModeSystem.SwingTimer
    local indices = enum and enum.EditModeSwingTimerSystemIndices
    local settings = enum and enum.EditModeSwingTimerSetting
    local manager = _G.EditModeManagerFrame
    local index = indices and indices[INDEX_NAMES[hand]]
    local frame = FRAME_NAMES[hand] and _G[FRAME_NAMES[hand]]
    if system == nil or index == nil or type(settings) ~= "table"
        or not (manager and frame and manager.GetRegisteredSystemFrame)
        or manager:GetRegisteredSystemFrame(system, index) ~= frame then return nil end
    return manager, frame, settings
end

function Swing.IsAvailable(hand)
    return Native(hand or "main") ~= nil
end

function Swing.GetEnabled()
    local registry = _G.CVarCallbackRegistry
    if registry and registry.GetCVarValueBool then
        return registry:GetCVarValueBool("showSwingTimer") == true
    end
    return _G.GetCVarBool and _G.GetCVarBool("showSwingTimer") == true or false
end

function Swing.SetEnabled(enabled)
    if Blocked() or not Swing.IsAvailable() or type(_G.SetCVar) ~= "function" then return false end
    _G.SetCVar("showSwingTimer", enabled and "1" or "0")
    return true
end

function Swing.Get(hand, key)
    local manager, frame, settings = Native(hand)
    local setting = settings and settings[SETTING_NAMES[key]]
    if setting == nil or not (manager and frame.GetSettingValue) then return nil end
    return frame:GetSettingValue(setting)
end

function Swing.Set(hand, key, value)
    if Blocked() then return false end
    local manager, frame, settings = Native(hand)
    local setting = settings and settings[SETTING_NAMES[key]]
    if setting == nil or not (manager and manager.OnSystemSettingChange and manager.SaveLayouts) then return false end
    if key == "title" or key == "time" then
        value = value and 1 or 0
    elseif key == "visibility" then
        local visibility = _G.Enum and _G.Enum.EditModeSwingTimerVisibility
        if type(visibility) ~= "table" or (value ~= visibility.Always
            and value ~= visibility.InCombat and value ~= visibility.Hidden) then return false end
    else
        local limit = LIMITS[key]
        value = tonumber(value)
        if not (limit and value and value >= limit[1] and value <= limit[2]) then return false end
        value = math.floor((value - limit[1]) / limit[3] + 0.5) * limit[3] + limit[1]
    end
    if frame:GetSettingValue(setting) == value then return true end
    if manager.IsActiveLayoutPreset and manager:IsActiveLayoutPreset() then
        local ensure = _G.MSUF_BlizzardEditMode_EnsureLayout
        if type(ensure) ~= "function" or ensure() ~= true then return false end
        manager, frame, settings = Native(hand)
        if not manager or (manager.IsActiveLayoutPreset and manager:IsActiveLayoutPreset()) then return false end
    end
    manager:OnSystemSettingChange(frame, setting, value)
    -- A running Blizzard Edit Mode session owns its Save/Discard decision.
    if not (manager.IsEditModeActive and manager:IsEditModeActive()) then
        manager:SaveLayouts()
    end
    return true
end

function Swing.OpenEditMode(hand)
    if Blocked() then return false end
    local manager, frame = Native(hand or "main")
    if not (manager and type(_G.ShowUIPanel) == "function") then return false end
    if manager.CanEnterEditMode and not manager:CanEnterEditMode() then return false end
    _G.ShowUIPanel(manager)
    if manager.IsEditModeActive and manager:IsEditModeActive()
        and type(manager.SelectSystem) == "function" then
        manager:SelectSystem(frame)
    end
    return true
end
