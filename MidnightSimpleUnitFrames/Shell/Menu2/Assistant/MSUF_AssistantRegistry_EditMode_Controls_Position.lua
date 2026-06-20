-- Assistant EditMode position/anchor control workflow helpers.
-- Loaded before MSUF_AssistantRegistry_EditMode_Controls.lua; the control registry calls this helper.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.EditModeRegistry = A.EditModeRegistry or {}

function A.EditModeRegistry.BuildPositionControlHandlers(ctx)
    if type(ctx) ~= "table" then return {} end

    local EM2 = ctx.EM2
    local HUD = ctx.HUD
    local EnsureDB = ctx.EnsureDB
    local RefreshHUDControls = ctx.RefreshHUDControls
    local ApplyAllSettings = ctx.ApplyAllSettings
    local ScheduleEditModeSync = ctx.ScheduleEditModeSync

    if type(EM2) ~= "function" or type(HUD) ~= "function" or type(EnsureDB) ~= "function" then return {} end
    if type(RefreshHUDControls) ~= "function" or type(ApplyAllSettings) ~= "function" then return {} end
    if type(ScheduleEditModeSync) ~= "function" then return {} end

    local function CurrentEditSelectionKey()
        local em2 = EM2()
        local state = em2 and type(em2.State) == "table" and em2.State or nil
        if state and type(state.GetUnitKey) == "function" then
            local key = state.GetUnitKey()
            if type(key) == "string" and key ~= "" then return key end
        end
        local key = _G.MSUF_CurrentEditUnitKey
        if type(key) == "string" and key ~= "" then return key end
        return nil
    end

    local function EditSelectionLabel(key)
        key = tostring(key or "")
        local clean = key:gsub("^uf_", "")
        local labels = A.UnitLabels or {}
        if labels[key] then return labels[key] end
        if labels[clean] then return labels[clean] end
        clean = clean:gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
        clean = clean:gsub("^%l", string.upper)
        return clean ~= "" and clean or "selected frame"
    end

    local function Undo()
        local em2 = EM2()
        local undo = em2 and type(em2.Undo) == "table" and em2.Undo or nil
        if undo and type(undo.CanUndo) == "function" and not undo.CanUndo() then
            return true, "Edit Mode has no position change to undo."
        end
        local fn = _G.MSUF_EM_UndoUndo
        if type(fn) ~= "function" then return false, "Enter Edit Mode so I can undo the last edit." end
        fn()
        RefreshHUDControls()
        return true, "Done. Undid the last Edit Mode position change."
    end

    local function Redo()
        local em2 = EM2()
        local undo = em2 and type(em2.Undo) == "table" and em2.Undo or nil
        if undo and type(undo.CanRedo) == "function" and not undo.CanRedo() then
            return true, "Edit Mode has no position change to redo."
        end
        local fn = _G.MSUF_EM_UndoRedo
        if type(fn) ~= "function" then return false, "Enter Edit Mode so I can redo the last edit." end
        fn()
        RefreshHUDControls()
        return true, "Done. Redid the last Edit Mode position change."
    end

    local function ResetCurrentPosition()
        local hud = HUD()
        if not (hud and type(hud.ResetCurrentPosition) == "function") then
            return false, "Select a frame in Edit Mode first so I can reset it."
        end
        local key = CurrentEditSelectionKey()
        if not key then
            return false, "Select a frame in MSUF Edit Mode first so I can reset its position."
        end
        hud.ResetCurrentPosition()
        RefreshHUDControls()
        return true, "Done. Reset Edit Mode position for " .. EditSelectionLabel(key) .. "."
    end

    local function OpenAnchorPicker()
        local ensure = _G.MSUF_EnsureAnchorPicker
        if type(ensure) ~= "function" then
            return false, "Enter Edit Mode so I can open the Anchor Picker."
        end
        local overlay = ensure()
        if not overlay then return false, "Open Edit Mode first so I can use the Edit Mode Anchor Picker." end
        overlay._onPick = function(frameName)
            local db = EnsureDB()
            db.general = type(db.general) == "table" and db.general or {}
            db.general.anchorName = frameName
            db.general.anchorToCooldown = false
            ApplyAllSettings()
            local hud = HUD()
            if hud and type(hud.SetStatus) == "function" then
                hud.SetStatus("Global anchor set: " .. tostring(frameName or ""), "ok")
            end
            ScheduleEditModeSync(false)
            RefreshHUDControls()
        end
        if type(overlay.Show) == "function" then overlay:Show() end
        RefreshHUDControls()
        return true, "Opened Edit Mode Anchor picker. Pick a frame in the overlay to set the global anchor."
    end

    return {
        Undo = Undo,
        Redo = Redo,
        ResetCurrentPosition = ResetCurrentPosition,
        OpenAnchorPicker = OpenAnchorPicker,
    }
end
