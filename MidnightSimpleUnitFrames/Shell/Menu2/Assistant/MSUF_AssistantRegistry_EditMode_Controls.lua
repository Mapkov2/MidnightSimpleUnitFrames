-- Assistant EditMode control workflow helpers.
-- Loaded before MSUF_AssistantRegistry_EditMode.lua; the main file passes shared helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.EditModeRegistry = A.EditModeRegistry or {}

function A.EditModeRegistry.BuildControlHandlers(ctx)
    if type(ctx) ~= "table" then return {} end

    local EM2 = ctx.EM2
    local HUD = ctx.HUD
    local Grid = ctx.Grid
    local EnsureDB = ctx.EnsureDB
    local RefreshHUDControls = ctx.RefreshHUDControls
    local ToggleValue = ctx.ToggleValue
    local StateMessage = ctx.StateMessage
    local Clamp = ctx.Clamp
    local Round = ctx.Round
    local FormatPercent = ctx.FormatPercent
    local ApplyAllSettings = ctx.ApplyAllSettings
    local ScheduleEditModeSync = ctx.ScheduleEditModeSync

    if type(EM2) ~= "function" or type(HUD) ~= "function" or type(Grid) ~= "function" then return {} end
    if type(EnsureDB) ~= "function" or type(RefreshHUDControls) ~= "function" then return {} end
    if type(ToggleValue) ~= "function" or type(StateMessage) ~= "function" then return {} end
    if type(Clamp) ~= "function" or type(Round) ~= "function" or type(FormatPercent) ~= "function" then return {} end
    if type(ApplyAllSettings) ~= "function" or type(ScheduleEditModeSync) ~= "function" then return {} end

    local function SetSnap(value)
        local em2 = EM2()
        local snap = em2 and type(em2.Snap) == "table" and em2.Snap or nil
        if not (snap and type(snap.IsEnabled) == "function" and type(snap.SetEnabled) == "function") then
            return false, "Enter Edit Mode so I can toggle Snap."
        end
        local current = snap.IsEnabled() and true or false
        value = ToggleValue(current, value)
        local changed = current ~= value
        if changed then snap.SetEnabled(value) end
        RefreshHUDControls()
        return true, StateMessage("Edit Mode Snap", value, changed)
    end

    local function SetGrid(value)
        local grid = Grid()
        if not (grid and type(grid.GetEnabled) == "function" and type(grid.SetEnabled) == "function") then
            return false, "Enter Edit Mode so I can toggle the grid."
        end
        local current = grid.GetEnabled() and true or false
        value = ToggleValue(current, value)
        local changed = current ~= value
        if changed then grid.SetEnabled(value) end
        RefreshHUDControls()
        return true, StateMessage("Edit Mode Grid", value, changed)
    end

    local function SetGridStep(value)
        local grid = Grid()
        if not (grid and type(grid.GetGridStep) == "function" and type(grid.SetGridStep) == "function") then
            return false, "Enter Edit Mode so I can change grid spacing."
        end
        value = Round(value)
        if value == nil then
            return false, "What grid spacing should Edit Mode use? Example: 'set edit mode grid to 24'."
        end
        value = Clamp(value, 8, 64)
        local current = Round(grid.GetGridStep())
        local changed = current == nil or current ~= value
        if changed then grid.SetGridStep(value) end
        RefreshHUDControls()
        if changed then return true, "Done. Edit Mode grid spacing set to " .. tostring(value) .. "px." end
        return true, "Already set. Edit Mode grid spacing is " .. tostring(value) .. "px."
    end

    local function SetBackgroundOpacity(value)
        local grid = Grid()
        if not (grid and type(grid.GetBgAlpha) == "function" and type(grid.SetBgAlpha) == "function") then
            return false, "Enter Edit Mode so I can change background opacity."
        end
        value = tonumber(value)
        if value == nil then
            return false, "What background opacity should Edit Mode use? Example: 'set edit mode background opacity to 50%'."
        end
        if value > 1 then value = value / 100 end
        value = Clamp(value, 0.05, 0.85)
        local current = tonumber(grid.GetBgAlpha())
        local changed = current == nil or math.abs(current - value) > 0.0001
        if changed then grid.SetBgAlpha(value) end
        RefreshHUDControls()
        if changed then return true, "Done. Edit Mode background opacity set to " .. FormatPercent(value) .. "." end
        return true, "Already set. Edit Mode background opacity is " .. FormatPercent(value) .. "."
    end

    local function SetCooldownAnchor(value)
        local db = EnsureDB()
        db.general = type(db.general) == "table" and db.general or {}
        local current = db.general.anchorToCooldown and true or false
        value = ToggleValue(current, value)
        local changed = current ~= value
        if changed then
            db.general.anchorToCooldown = value
            ApplyAllSettings()
            ScheduleEditModeSync(true)
        end
        RefreshHUDControls()
        return true, StateMessage("Edit Mode CDM Anchor", value, changed)
    end

    local BuildPositionControlHandlers = A.EditModeRegistry and A.EditModeRegistry.BuildPositionControlHandlers
    local PositionHandlers = type(BuildPositionControlHandlers) == "function" and BuildPositionControlHandlers(ctx) or {}

    return {
        SetSnap = SetSnap,
        SetGrid = SetGrid,
        SetGridStep = SetGridStep,
        SetBackgroundOpacity = SetBackgroundOpacity,
        SetCooldownAnchor = SetCooldownAnchor,
        Undo = PositionHandlers.Undo,
        Redo = PositionHandlers.Redo,
        ResetCurrentPosition = PositionHandlers.ResetCurrentPosition,
        OpenAnchorPicker = PositionHandlers.OpenAnchorPicker,
    }
end
