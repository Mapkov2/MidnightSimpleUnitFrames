local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry
if not (Registry and type(Registry.RegisterAction) == "function") then return end

A.Workflow = A.Workflow or {}
A.Workflow.EditMode = A.Workflow.EditMode or {}

local EditMode = A.Workflow.EditMode
local SOURCE_FILE = "Shell/Menu2/Assistant/MSUF_AssistantRegistry_EditMode.lua"
local SOURCE_CONTROL = "M.SetMSUFEditModeActive / M.CancelMSUFEditMode / M.ToggleMSUFEditMode"
local SOURCE_HUD = "Shell/UI/EditMode/MSUF_EditMode_HUD.lua"

local function Status()
    if M and type(M.EditModeLifecycleStatus) == "function" then
        return M.EditModeLifecycleStatus(true)
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
    if M and type(M.RefreshMenuFramePriority) == "function" then M.RefreshMenuFramePriority() end
    if M and type(M.RefreshDashboardEditModeButton) == "function" then M.RefreshDashboardEditModeButton() end
    if M and M.frame and type(M.frame.RefreshStatus) == "function" then M.frame:RefreshStatus() end
end

local function EnsureDB()
    if M and type(M.EnsureDB) == "function" then return M.EnsureDB() end
    _G.MSUF_DB = type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {}
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
    local UF = MSUF and MSUF.UF
    if UF and type(UF.Apply) == "function" then
        UF.Apply(nil)
        return true
    end
    if M and type(M.RequestGeneralApply) == "function" then
        M.RequestGeneralApply("MSUF_ASSISTANT_EDIT_MODE_CONTROL", { preview = true, applyAll = true })
        return true
    end
    if type(_G.MSUF_RefreshAllFrames) == "function" then
        _G.MSUF_RefreshAllFrames()
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

local function ScheduleEditModeSync(includePreviewForce)
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0.1, function() SyncEditModeMovers(includePreviewForce) end)
    else
        SyncEditModeMovers(includePreviewForce)
    end
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

local GROUP_PREVIEW_COUNTS = { party = 5, raid = 30, mythicraid = 20 }
local GROUP_PREVIEW_LABELS = { party = "Party Group Frame Preview", raid = "Raid Group Frame Preview", mythicraid = "Mythic Raid Group Frame Preview" }
local GROUP_PREVIEW_PAGES = { gf_layout = true, gf_bars = true, gf_indicators = true }

local function NormalizeGroupPreviewScope(scope)
    scope = tostring(scope or ""):lower():gsub("%s+", "")
    if scope == "mythic" or scope == "mythicraid" then return "mythicraid" end
    if scope == "raid" then return "raid" end
    if scope == "party" or scope == "group" then return "party" end
    local current = M and M.gfScope
    if current == "party" or current == "raid" or current == "mythicraid" then return current end
    return "party"
end

local function GroupPreviewLabel(scope)
    return GROUP_PREVIEW_LABELS[scope] or "Group Frames Preview"
end

local function PersistGroupPreviewScope(scope)
    if not scope then return end
    if M and type(M.PersistMenuStateValue) == "function" then
        M.PersistMenuStateValue("gfScope", scope)
    elseif M then
        M.gfScope = scope
    end
end

local function OpenMenuPage(pageKey)
    if pageKey and M and type(M.InvalidatePage) == "function" then M.InvalidatePage(pageKey) end
    if M and type(M.Open) == "function" then return M.Open(pageKey) ~= false end
    if M and type(M.SelectPage) == "function" then return M.SelectPage(pageKey) ~= false end
    return true
end

local function IsGroupPreviewActive(scope)
    if _G.MSUF2_GFPagePreviewActive == true then
        local activeKind = _G.MSUF2_GFPagePreviewKind
        if activeKind == nil or activeKind == scope then return true end
    end
    local gf = MSUF and MSUF.GF
    local active = gf and gf._previewActive
    return type(active) == "table" and active[scope] == true
end

local function IsEditModeActive()
    if M and type(M.IsMSUFEditModeActive) == "function" then
        local ok, active = pcall(M.IsMSUFEditModeActive, true)
        if ok then return active and true or false end
    end
    return Status().active == true
end

local function HideMenuGroupPreview(scope)
    local gf = MSUF and MSUF.GF
    if gf and type(gf.HidePreview) == "function" then
        if scope then
            gf.HidePreview(scope)
        else
            gf.HidePreview("party")
            gf.HidePreview("raid")
            gf.HidePreview("mythicraid")
        end
    end
    if _G.MSUF2_GFPagePreviewKind == nil or _G.MSUF2_GFPagePreviewKind == scope or scope == nil then
        _G.MSUF2_GFPagePreviewActive = nil
        _G.MSUF2_GFPagePreviewKind = nil
    end
    if type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then _G.MSUF_GF_EM2_SetActivePreviewKind(nil) end
end

local function ShowMenuGroupPreview(scope)
    PersistGroupPreviewScope(scope)
    OpenMenuPage(GROUP_PREVIEW_PAGES[M and M.activeKey] and M.activeKey or "gf_layout")

    local synced = false
    if M and type(M.SyncGFPagePreviewForKey) == "function" then
        M.SyncGFPagePreviewForKey(M.activeKey or "gf_layout", true)
        synced = true
    end

    local gf = MSUF and MSUF.GF
    local shown = false
    if gf and type(gf.ShowPreview) == "function" then
        _G.MSUF2_GFPagePreviewActive = true
        _G.MSUF2_GFPagePreviewKind = scope
        if gf.SetPreviewAnchor then
            gf.SetPreviewAnchor("party", nil)
            gf.SetPreviewAnchor("raid", nil)
            gf.SetPreviewAnchor("mythicraid", nil)
        end
        if scope ~= "party" and type(gf.HidePreview) == "function" then gf.HidePreview("party") end
        if scope ~= "raid" and type(gf.HidePreview) == "function" then gf.HidePreview("raid") end
        if scope ~= "mythicraid" and type(gf.HidePreview) == "function" then gf.HidePreview("mythicraid") end
        shown = gf.ShowPreview(scope, GROUP_PREVIEW_COUNTS[scope] or 5) ~= false
        if shown and type(gf.RefreshPreviewLayout) == "function" then gf.RefreshPreviewLayout(scope) end
    end

    if type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then _G.MSUF_GF_EM2_SetActivePreviewKind(scope) end
    if not (synced or shown) then
        return false, "Group Frame Preview is unavailable because the Menu2 preview bridge is not loaded."
    end
    return true
end

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

function EditMode.SetPreview(value)
    local current = _G.MSUF_UnitPreviewActive and true or false
    value = ToggleValue(current, value)
    local changed = current ~= value
    if changed then
        _G.MSUF_UnitPreviewActive = value
        if type(_G.MSUF_SyncAllUnitPreviews) == "function" then _G.MSUF_SyncAllUnitPreviews() end
    end
    RefreshHUDControls()
    return true, StateMessage("Edit Mode Preview", value, changed)
end

function EditMode.SetAuraPreview(value)
    local db = EnsureDB()
    local auras = db and db.auras3
    if type(auras) ~= "table" then
        return false, "Edit Mode Auras preview is unavailable because MSUF_DB.auras3 is not loaded."
    end
    local shared = auras.shared
    if type(shared) ~= "table" then
        return false, "Edit Mode Auras preview is unavailable because MSUF_DB.auras3.shared is not loaded."
    end
    local current = shared.showInEditMode and true or false
    value = ToggleValue(current, value)
    local changed = current ~= value
    if changed then shared.showInEditMode = value end
    if changed then
        local refreshAll = type(_G.MSUF_Auras3_RefreshAll) == "function" and _G.MSUF_Auras3_RefreshAll or nil
        local refreshPreview = type(_G.MSUF_Auras3_RefreshEditPreview) == "function" and _G.MSUF_Auras3_RefreshEditPreview or nil
        if IsEditModeActive() and refreshAll then
            refreshAll()
        else
            if refreshPreview then refreshPreview() end
            if refreshAll then refreshAll() end
        end
    end
    RefreshHUDControls()
    return true, StateMessage("Edit Mode Auras Preview", value, changed)
end

function EditMode.SetGroupPreview(value, scope)
    scope = NormalizeGroupPreviewScope(scope)
    local label = GroupPreviewLabel(scope)
    PersistGroupPreviewScope(scope)

    if not IsEditModeActive() then
        local current = IsGroupPreviewActive(scope)
        value = ToggleValue(current, value)
        local changed = current ~= value or (value and _G.MSUF2_GFPagePreviewKind ~= scope)
        if value then
            local ok, reason = ShowMenuGroupPreview(scope)
            if not ok then return false, reason end
        elseif changed then
            HideMenuGroupPreview(scope)
        end
        Refresh()
        if changed then return true, "Done. " .. label .. " " .. StateWord(value) .. " outside Edit Mode." end
        return true, "Already set. " .. label .. " is " .. StateWord(value) .. " outside Edit Mode."
    end

    local show = _G.MSUF_GF_EM2_ShowPreview
    local hide = _G.MSUF_GF_EM2_HidePreview
    if not (type(show) == "function" and type(hide) == "function") then
        return false, "Edit Mode Group Frames preview is unavailable because the MSUF group frame Edit Mode bridge is not loaded."
    end
    local current
    if type(_G.MSUF_GF_EM2_IsPreviewShown) == "function" then
        current = _G.MSUF_GF_EM2_IsPreviewShown() and true or false
    end
    if value == nil and current == nil then
        return false, "I cannot toggle Edit Mode Group Frames preview because the bridge does not expose its current state. Say show or hide group frames preview."
    end
    value = ToggleValue(current, value)
    local changed = current == nil or current ~= value or (value and scope ~= nil)
    if changed then
        if value and scope and type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then _G.MSUF_GF_EM2_SetActivePreviewKind(scope) end
        if value then show() else hide() end
    end
    RefreshHUDControls()
    if current == nil then
        return true, "Done. " .. label .. " " .. StateWord(value) .. " in Edit Mode."
    end
    if changed then return true, "Done. " .. label .. " " .. StateWord(value) .. " in Edit Mode." end
    return true, "Already set. " .. label .. " is " .. StateWord(value) .. " in Edit Mode."
end

function EditMode.SetSnap(value)
    local em2 = EM2()
    local snap = em2 and type(em2.Snap) == "table" and em2.Snap or nil
    if not (snap and type(snap.IsEnabled) == "function" and type(snap.SetEnabled) == "function") then
        return false, "Edit Mode Snap is unavailable because MSUF_EM2.Snap is not loaded."
    end
    local current = snap.IsEnabled() and true or false
    value = ToggleValue(current, value)
    local changed = current ~= value
    if changed then snap.SetEnabled(value) end
    RefreshHUDControls()
    return true, StateMessage("Edit Mode Snap", value, changed)
end

function EditMode.SetGrid(value)
    local grid = Grid()
    if not (grid and type(grid.GetEnabled) == "function" and type(grid.SetEnabled) == "function") then
        return false, "Edit Mode Grid is unavailable because MSUF_EM2.Grid is not loaded."
    end
    local current = grid.GetEnabled() and true or false
    value = ToggleValue(current, value)
    local changed = current ~= value
    if changed then grid.SetEnabled(value) end
    RefreshHUDControls()
    return true, StateMessage("Edit Mode Grid", value, changed)
end

function EditMode.SetGridStep(value)
    local grid = Grid()
    if not (grid and type(grid.GetGridStep) == "function" and type(grid.SetGridStep) == "function") then
        return false, "Edit Mode Grid spacing is unavailable because MSUF_EM2.Grid is not loaded."
    end
    value = Round(value)
    if value == nil then
        return false, "Tell me the Edit Mode grid spacing in pixels, for example 'set edit mode grid to 24'."
    end
    value = Clamp(value, 8, 64)
    local current = Round(grid.GetGridStep())
    local changed = current == nil or current ~= value
    if changed then grid.SetGridStep(value) end
    RefreshHUDControls()
    if changed then return true, "Done. Edit Mode Grid spacing set to " .. tostring(value) .. "px." end
    return true, "Already set. Edit Mode Grid spacing is " .. tostring(value) .. "px."
end

function EditMode.SetBackgroundOpacity(value)
    local grid = Grid()
    if not (grid and type(grid.GetBgAlpha) == "function" and type(grid.SetBgAlpha) == "function") then
        return false, "Edit Mode background opacity is unavailable because MSUF_EM2.Grid is not loaded."
    end
    value = tonumber(value)
    if value == nil then
        return false, "Tell me the Edit Mode background opacity, for example 'set edit mode background opacity to 50%'."
    end
    if value > 1 then value = value / 100 end
    value = Clamp(value, 0.05, 0.85)
    local current = tonumber(grid.GetBgAlpha())
    local changed = current == nil or math.abs(current - value) > 0.0001
    if changed then grid.SetBgAlpha(value) end
    RefreshHUDControls()
    if changed then return true, "Done. Edit Mode Background opacity set to " .. FormatPercent(value) .. "." end
    return true, "Already set. Edit Mode Background opacity is " .. FormatPercent(value) .. "."
end

function EditMode.SetCooldownAnchor(value)
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

function EditMode.Undo()
    local em2 = EM2()
    local undo = em2 and type(em2.Undo) == "table" and em2.Undo or nil
    if undo and type(undo.CanUndo) == "function" and not undo.CanUndo() then
        return true, "Edit Mode has no position change to undo."
    end
    local fn = _G.MSUF_EM_UndoUndo
    if type(fn) ~= "function" then return false, "Edit Mode Undo is unavailable because MSUF_EM_UndoUndo is not loaded." end
    fn()
    RefreshHUDControls()
    return true, "Done. Undid the last Edit Mode position change."
end

function EditMode.Redo()
    local em2 = EM2()
    local undo = em2 and type(em2.Undo) == "table" and em2.Undo or nil
    if undo and type(undo.CanRedo) == "function" and not undo.CanRedo() then
        return true, "Edit Mode has no position change to redo."
    end
    local fn = _G.MSUF_EM_UndoRedo
    if type(fn) ~= "function" then return false, "Edit Mode Redo is unavailable because MSUF_EM_UndoRedo is not loaded." end
    fn()
    RefreshHUDControls()
    return true, "Done. Redid the last Edit Mode position change."
end

function EditMode.ResetCurrentPosition()
    local hud = HUD()
    if not (hud and type(hud.ResetCurrentPosition) == "function") then
        return false, "I cannot reset the selected Edit Mode frame because MSUF_EM2.HUD.ResetCurrentPosition is not loaded."
    end
    local key = CurrentEditSelectionKey()
    if not key then
        return false, "Select a frame in MSUF Edit Mode first, then ask me to reset its position."
    end
    local ok, err = pcall(hud.ResetCurrentPosition)
    if not ok then return false, "Edit Mode reset failed: " .. tostring(err) end
    RefreshHUDControls()
    return true, "Done. Reset Edit Mode position for " .. tostring(key) .. "."
end

function EditMode.OpenAnchorPicker()
    local ensure = _G.MSUF_EnsureAnchorPicker
    if type(ensure) ~= "function" then
        return false, "I cannot open the Edit Mode Anchor picker because MSUF_EnsureAnchorPicker is unavailable."
    end
    local overlay = ensure()
    if not overlay then return false, "I cannot open the Edit Mode Anchor picker because the overlay was not created." end
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

function EditMode.StatusText(reason)
    local st = Status()
    local lines = {}
    lines[#lines + 1] = st.active and "MSUF Edit Mode is enabled." or "MSUF Edit Mode is disabled."
    if st.unitKey then lines[#lines + 1] = "Focused unit: " .. tostring(st.unitKey) end
    lines[#lines + 1] = "Combat locked: " .. (st.combatLocked and "yes" or "no")
    lines[#lines + 1] = "Enter/exit helper: " .. ((st.hasDirectHelper or st.hasStateEnter or st.hasStateExit) and "available" or "missing")
    lines[#lines + 1] = "Cancel helper: " .. (st.hasStateCancel and "available" or "missing")
    if reason == "why_exit" then
        if not st.active then
            lines[#lines + 1] = "Exit is not needed because MSUF Edit Mode is already disabled."
        elseif st.hasDirectHelper or st.hasStateExit then
            lines[#lines + 1] = "Exit should be available through the shared MSUF Edit Mode helper."
        else
            lines[#lines + 1] = "I could not exit Edit Mode because no shared helper is available."
        end
    end
    return table.concat(lines, "\n")
end

local function EditModeFailureText(kind, reason)
    if reason == "combat_locked" then return "Edit Mode is locked in combat." end
    if reason == "missing_enter_helper" then return "I could not enter Edit Mode because no shared helper is available." end
    if reason == "missing_exit_helper" then return "I could not exit Edit Mode because no shared helper is available." end
    if reason == "missing_cancel_helper" then return "I could not cancel Edit Mode because no shared cancel helper is available." end
    if kind == "exit" then return "I could not exit Edit Mode because no shared helper is available." end
    if kind == "cancel" then return "I could not cancel Edit Mode because no shared cancel helper is available." end
    return "Edit Mode control is not available right now."
end

function EditMode.Set(active, unitKey)
    if not (M and type(M.SetMSUFEditModeActive) == "function") then
        return false, active and "missing_enter_helper" or "missing_exit_helper"
    end
    local ok, reason = M.SetMSUFEditModeActive(active and true or false, unitKey, {
        includeBlizzard = true,
        source = "assistant",
    })
    Refresh()
    return ok, reason
end

function EditMode.Cancel()
    if not (M and type(M.CancelMSUFEditMode) == "function") then
        return false, "missing_cancel_helper"
    end
    local ok, reason = M.CancelMSUFEditMode({ includeBlizzard = true, source = "assistant_cancel" })
    Refresh()
    return ok, reason
end

function EditMode.Toggle(unitKey)
    if not (M and type(M.ToggleMSUFEditMode) == "function") then
        return false, "missing_enter_helper"
    end
    local ok, reason = M.ToggleMSUFEditMode(unitKey, {
        includeBlizzard = true,
        source = "assistant_toggle",
    })
    Refresh()
    return ok, reason
end

local LIFECYCLE = {
    workflow = "editMode",
    canStart = true,
    canConfirmApply = true,
    canCancel = true,
    canExitStop = true,
    canToggle = true,
    canReportStatus = true,
    existingHelper = "M.SetMSUFEditModeActive / M.CancelMSUFEditMode / M.ToggleMSUFEditMode",
}

Registry:RegisterAction({
    key = "assistant.action.editMode.enter",
    label = "Enter MSUF Edit Mode",
    type = "setup",
    combatSafe = false,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_CONTROL,
    lifecycle = LIFECYCLE,
    run = function(args)
        local ok, reason = EditMode.Set(true, args and args.unit)
        if not ok then return false, EditModeFailureText("enter", reason) end
        if reason == "already_enabled" then return true, "MSUF Edit Mode is already enabled." end
        return true, "Done. MSUF Edit Mode enabled."
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.exit",
    label = "Exit MSUF Edit Mode",
    type = "setup",
    combatSafe = true,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_CONTROL,
    lifecycle = LIFECYCLE,
    run = function()
        local ok, reason = EditMode.Set(false)
        if not ok then return false, EditModeFailureText("exit", reason) end
        if reason == "already_disabled" then return true, "MSUF Edit Mode is already disabled." end
        return true, "Done. MSUF Edit Mode disabled."
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.cancel",
    label = "Cancel MSUF Edit Mode",
    type = "setup",
    combatSafe = true,
    confirmRequired = true,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_CONTROL,
    lifecycle = LIFECYCLE,
    run = function()
        local ok, reason = EditMode.Cancel()
        if not ok then return false, EditModeFailureText("cancel", reason) end
        if reason == "already_disabled" then return true, "MSUF Edit Mode is already disabled." end
        return true, "Done. MSUF Edit Mode canceled."
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.toggle",
    label = "Toggle MSUF Edit Mode",
    type = "setup",
    combatSafe = false,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_CONTROL,
    lifecycle = LIFECYCLE,
    run = function(args)
        local wasActive = Status().active == true
        local ok, reason = EditMode.Toggle(args and args.unit)
        if not ok then return false, EditModeFailureText(wasActive and "exit" or "enter", reason) end
        if wasActive then return true, "Done. MSUF Edit Mode disabled." end
        return true, "Done. MSUF Edit Mode enabled."
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.preview",
    label = "Toggle Edit Mode Preview",
    type = "setup",
    combatSafe = false,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " Preview",
    lifecycle = LIFECYCLE,
    run = function(args)
        return EditMode.SetPreview(args and args.value)
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.auras",
    label = "Toggle Edit Mode Auras Preview",
    type = "setup",
    combatSafe = false,
    captureSnapshot = true,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " Auras",
    lifecycle = LIFECYCLE,
    run = function(args)
        return EditMode.SetAuraPreview(args and args.value)
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.groupPreview",
    label = "Toggle Edit Mode Group Frames Preview",
    type = "setup",
    combatSafe = false,
    sourceFile = SOURCE_FILE,
    sourceControl = "UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua GF",
    lifecycle = LIFECYCLE,
    run = function(args)
        return EditMode.SetGroupPreview(args and args.value, args and args.scope)
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.snap",
    label = "Toggle Edit Mode Snap",
    type = "setup",
    combatSafe = false,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " Snap",
    lifecycle = LIFECYCLE,
    run = function(args)
        return EditMode.SetSnap(args and args.value)
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.grid",
    label = "Toggle Edit Mode Grid",
    type = "setup",
    combatSafe = false,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " Grid",
    lifecycle = LIFECYCLE,
    run = function(args)
        return EditMode.SetGrid(args and args.value)
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.gridStep",
    label = "Set Edit Mode Grid Spacing",
    type = "setup",
    combatSafe = false,
    captureSnapshot = true,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " Grid spacing",
    lifecycle = LIFECYCLE,
    run = function(args)
        return EditMode.SetGridStep(args and args.value)
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.backgroundOpacity",
    label = "Set Edit Mode Background Opacity",
    type = "setup",
    combatSafe = false,
    captureSnapshot = true,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " BG opacity",
    lifecycle = LIFECYCLE,
    run = function(args)
        return EditMode.SetBackgroundOpacity(args and args.value)
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.cdm",
    label = "Toggle Edit Mode CDM Anchor",
    type = "setup",
    combatSafe = false,
    captureSnapshot = true,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " CDM",
    lifecycle = LIFECYCLE,
    run = function(args)
        return EditMode.SetCooldownAnchor(args and args.value)
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.undo",
    label = "Undo Edit Mode Position Change",
    type = "undo",
    combatSafe = false,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " Undo",
    lifecycle = LIFECYCLE,
    run = function()
        return EditMode.Undo()
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.redo",
    label = "Redo Edit Mode Position Change",
    type = "redo",
    combatSafe = false,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " Redo",
    lifecycle = LIFECYCLE,
    run = function()
        return EditMode.Redo()
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.resetPosition",
    label = "Reset Selected Edit Mode Position",
    type = "reset",
    combatSafe = false,
    captureSnapshot = true,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " Reset",
    lifecycle = LIFECYCLE,
    run = function()
        return EditMode.ResetCurrentPosition()
    end,
})

Registry:RegisterAction({
    key = "assistant.action.editMode.anchorPicker",
    label = "Open Edit Mode Anchor Picker",
    type = "setup",
    combatSafe = false,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_HUD .. " Anchor",
    lifecycle = LIFECYCLE,
    run = function()
        return EditMode.OpenAnchorPicker()
    end,
})

Registry:RegisterAction({
    key = "assistant.diagnostic.editMode.status",
    label = "Show MSUF Edit Mode Status",
    type = "diagnostic",
    combatSafe = true,
    sourceFile = SOURCE_FILE,
    sourceControl = SOURCE_CONTROL,
    lifecycle = LIFECYCLE,
    run = function(args)
        local text = EditMode.StatusText(args and args.reason)
        if A and type(A.ShowLargeTextPanel) == "function" then
            A.ShowLargeTextPanel({
                kind = "text",
                title = "MSUF Edit Mode",
                help = "Read-only lifecycle status for the shared MSUF Edit Mode helpers.",
                text = text,
                status = "No settings changed.",
            })
        end
        return true, text
    end,
})
