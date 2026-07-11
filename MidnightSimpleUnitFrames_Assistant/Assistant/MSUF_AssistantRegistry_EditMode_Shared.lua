-- Assistant EditMode shared workflow helpers.
-- Loaded before the preview/control/action registry files; keeps common lifecycle glue in one place.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.EditModeRegistry = A.EditModeRegistry or {}

function A.EditModeRegistry.BuildSharedHelpers(ctx)
    if type(ctx) ~= "table" then return {} end

    local Menu = ctx.M or M
    local Namespace = ctx.MSUF or MSUF
    local ExportPublic = type(ctx.ExportPublic) == "function" and ctx.ExportPublic or function(name, value)
        _G[name] = value
        return value
    end

    local function Status()
        if Menu and type(Menu.EditModeLifecycleStatus) == "function" then
            return Menu.EditModeLifecycleStatus(true)
        end
        return {
            active = _G.MSUF_UnitEditModeActive == true,
            combatLocked = ((_G.InCombatLockdown and _G.InCombatLockdown()) or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) and true or false,
            unitKey = _G.MSUF_CurrentEditUnitKey,
            hasDirectHelper = type(_G.MSUF_SetMSUFEditModeDirect) == "function" or type(_G.MSUF_SetEditMode) == "function",
            hasStateEnter = false,
            hasStateExit = false,
            hasStateCancel = false,
        }
    end

    local function Refresh()
        if Menu and type(Menu.RefreshMenuFramePriority) == "function" then Menu.RefreshMenuFramePriority() end
        if Menu and type(Menu.RefreshDashboardEditModeButton) == "function" then Menu.RefreshDashboardEditModeButton() end
        if Menu and Menu.frame and type(Menu.frame.RefreshStatus) == "function" then Menu.frame:RefreshStatus() end
    end

    local function EnsureDB()
        if Menu and type(Menu.EnsureDB) == "function" then return Menu.EnsureDB() end
        ExportPublic("MSUF_DB", type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {})
        _G.MSUF_DB.general = type(_G.MSUF_DB.general) == "table" and _G.MSUF_DB.general or {}
        return _G.MSUF_DB
    end

    local function EM2()
        return type(_G.MSUF_EM2) == "table" and _G.MSUF_EM2 or nil
    end

    local function HUD()
        local em2 = EM2()
        return em2 and type(em2.HUD) == "table" and em2.HUD or nil
    end

    local function Grid()
        local em2 = EM2()
        return em2 and type(em2.Grid) == "table" and em2.Grid or nil
    end

    local function RefreshHUDControls()
        local hud = HUD()
        if hud and type(hud.RefreshControls) == "function" then hud.RefreshControls() end
        Refresh()
    end

    local function ApplyAllSettings()
        local em2 = EM2()
        local util = em2 and type(em2.Util) == "table" and em2.Util or nil
        if util and type(util.ApplyAllSettingsSafe) == "function" and util.ApplyAllSettingsSafe() then
            return true
        end
        if Menu and type(Menu.RequestGeneralApply) == "function" then
            Menu.RequestGeneralApply("MSUF_ASSISTANT_EDIT_MODE_CONTROL", { preview = true, applyAll = true })
            return true
        end
        local apply = (Menu and Menu.ApplyService) or _G.MSUF_Menu2_ApplyService
        if apply and type(apply.RequestGeneral) == "function" then
            apply.RequestGeneral("MSUF_ASSISTANT_EDIT_MODE_CONTROL", { preview = true, applyAll = true })
            return true
        end
        if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
            _G.MSUF_UFCore_NotifyConfigChanged(nil, true, true, "MSUF_ASSISTANT_EDIT_MODE_CONTROL")
            return true
        end
        return false
    end

    local function SyncEditModeMovers(includePreviewForce)
        local em2 = EM2()
        if em2 and em2.Movers and type(em2.Movers.SyncAll) == "function" then em2.Movers.SyncAll() end
        if includePreviewForce ~= false and type(_G.MSUF_EM2_ReforcePreviewFrames) == "function" then
            _G.MSUF_EM2_ReforcePreviewFrames()
        end
    end

    local function InCombat()
        return ((_G.InCombatLockdown and _G.InCombatLockdown())
            or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) and true or false
    end

    local function ScheduleEditModeSync(includePreviewForce)
        if InCombat() or A._menuRuntimeActive == false then return false end
        if _G.C_Timer and type(_G.C_Timer.NewTimer) == "function" then
            local timer
            timer = _G.C_Timer.NewTimer(0.1, function()
                if type(A.UntrackMenuRuntimeTimer) == "function" then A.UntrackMenuRuntimeTimer("assistant.edit_mode.sync", timer) end
                if InCombat() or A._menuRuntimeActive == false then return end
                SyncEditModeMovers(includePreviewForce)
            end)
            if type(A.TrackMenuRuntimeTimer) == "function" then A.TrackMenuRuntimeTimer("assistant.edit_mode.sync", timer) end
        else
            SyncEditModeMovers(includePreviewForce)
        end
        return true
    end

    local function ToggleValue(current, requested)
        if requested == nil then return not (current and true or false) end
        return requested and true or false
    end

    local function StateWord(value)
        return value and "enabled" or "disabled"
    end

    local function StateMessage(label, value, changed)
        if changed then
            return "Done. " .. tostring(label) .. " " .. StateWord(value) .. "."
        end
        return "Already set. " .. tostring(label) .. " is " .. StateWord(value) .. "."
    end

    local function Clamp(value, minValue, maxValue)
        value = tonumber(value)
        if value == nil then return nil end
        if value < minValue then return minValue end
        if value > maxValue then return maxValue end
        return value
    end

    local function Round(value)
        value = tonumber(value)
        if value == nil then return nil end
        return math.floor(value + 0.5)
    end

    local function FormatPercent(value)
        value = tonumber(value) or 0
        return tostring(math.floor(value * 100 + 0.5)) .. "%"
    end

    return {
        Status = Status,
        Refresh = Refresh,
        EnsureDB = EnsureDB,
        EM2 = EM2,
        HUD = HUD,
        Grid = Grid,
        RefreshHUDControls = RefreshHUDControls,
        ApplyAllSettings = ApplyAllSettings,
        ScheduleEditModeSync = ScheduleEditModeSync,
        ToggleValue = ToggleValue,
        StateWord = StateWord,
        StateMessage = StateMessage,
        Clamp = Clamp,
        Round = Round,
        FormatPercent = FormatPercent,
    }
end
