-- Assistant EditMode preview workflow helpers.
-- Loaded before MSUF_AssistantRegistry_EditMode.lua; the main file passes shared state helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.EditModeRegistry = A.EditModeRegistry or {}

function A.EditModeRegistry.BuildPreviewControls(ctx)
    if type(ctx) ~= "table" then return {} end

    local Menu = ctx.M or M
    local Namespace = ctx.MSUF or MSUF
    local ExportPublic = ctx.ExportPublic
    local EnsureDB = ctx.EnsureDB
    local Refresh = ctx.Refresh
    local RefreshHUDControls = ctx.RefreshHUDControls
    local ToggleValue = ctx.ToggleValue
    local StateWord = ctx.StateWord
    local StateMessage = ctx.StateMessage
    local Status = ctx.Status

    if type(ExportPublic) ~= "function" or type(EnsureDB) ~= "function" then return {} end
    if type(Refresh) ~= "function" or type(RefreshHUDControls) ~= "function" then return {} end
    if type(ToggleValue) ~= "function" or type(StateWord) ~= "function" or type(StateMessage) ~= "function" then return {} end
    if type(Status) ~= "function" then return {} end

    local BuildGroupPreviewHelpers = A.EditModeRegistry and A.EditModeRegistry.BuildGroupPreviewHelpers
    local GroupPreviewHelpers = type(BuildGroupPreviewHelpers) == "function" and BuildGroupPreviewHelpers({
        M = Menu,
        MSUF = Namespace,
        Status = Status,
    }) or nil
    if type(GroupPreviewHelpers) ~= "table" then return {} end
    local NormalizeGroupPreviewScope = GroupPreviewHelpers.NormalizeGroupPreviewScope
    local GroupPreviewLabel = GroupPreviewHelpers.GroupPreviewLabel
    local PersistGroupPreviewScope = GroupPreviewHelpers.PersistGroupPreviewScope
    local IsGroupPreviewActive = GroupPreviewHelpers.IsGroupPreviewActive
    local IsEditModeActive = GroupPreviewHelpers.IsEditModeActive
    local HideMenuGroupPreview = GroupPreviewHelpers.HideMenuGroupPreview
    local ShowMenuGroupPreview = GroupPreviewHelpers.ShowMenuGroupPreview
    if type(NormalizeGroupPreviewScope) ~= "function" or type(IsEditModeActive) ~= "function" then return {} end
    if type(ShowMenuGroupPreview) ~= "function" or type(HideMenuGroupPreview) ~= "function" then return {} end

    local function SetPreview(value)
        local current = _G.MSUF_UnitPreviewActive and true or false
        value = ToggleValue(current, value)
        local changed = current ~= value
        if changed then
            ExportPublic("MSUF_UnitPreviewActive", value)
            if type(_G.MSUF_SyncAllUnitPreviews) == "function" then _G.MSUF_SyncAllUnitPreviews() end
        end
        RefreshHUDControls()
        return true, StateMessage("Edit Mode Preview", value, changed)
    end

    local function BossPreviewCombatLocked()
        return (_G.InCombatLockdown and _G.InCombatLockdown())
            or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
    end

    local function SetBossPreview(value)
        if BossPreviewCombatLocked() then
            return false, "Boss Frames preview has to wait until combat ends."
        end

        local current = _G.MSUF2_BossUnitframePreviewActive == true
        value = ToggleValue(current, value)
        local changed = current ~= value

        if value and Menu and type(Menu.SelectPage) == "function" then
            Menu.SelectPage("uf_boss")
        end

        _G.MSUF2_BossUnitframePreviewActive = value and true or nil

        local attempted
        local applied
        if type(_G.MSUF_ApplyBossUnitframePreviewState) == "function" then
            attempted = true
            applied = _G.MSUF_ApplyBossUnitframePreviewState(value and true or false, value and "MSUF_ASSISTANT_BOSS_PREVIEW" or "MSUF_ASSISTANT_BOSS_PREVIEW_OFF") ~= false
        elseif type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
            attempted = true
            applied = _G.MSUF_SyncBossUnitframePreviewWithUnitEdit() ~= false
        end

        if value and Menu and type(Menu.SyncBossPagePreviewForKey) == "function" then
            Menu.SyncBossPagePreviewForKey("uf_boss", true)
        end

        Refresh()
        RefreshHUDControls()

        if value and (not attempted or not applied) then
            return false, "Boss Frames preview is not available yet. Open Boss Frames and try again."
        end
        if changed then return true, "Done. Boss Frames preview " .. StateWord(value) .. "." end
        return true, "Already set. Boss Frames preview is " .. StateWord(value) .. "."
    end

    local function SetAuraPreview(value)
        local db = EnsureDB()
        local auras = db and db.auras3
        if type(auras) ~= "table" then
            return false, "Enter Edit Mode so I can show the Auras preview."
        end
        local shared = auras.shared
        if type(shared) ~= "table" then
            return false, "Enter Edit Mode so I can show the Auras preview."
        end
        local current = shared.showInEditMode and true or false
        value = ToggleValue(current, value)
        local changed = current ~= value
        if changed then shared.showInEditMode = value end
        if changed then
            local a3 = MSUF and MSUF.MSUF_Auras3
            local refreshPreview = a3 and type(a3.RefreshEditPreview) == "function" and a3.RefreshEditPreview or nil
            if refreshPreview then
                refreshPreview()
            elseif M and M.ApplyService and type(M.ApplyService.RequestAuras) == "function" then
                M.ApplyService.RequestAuras("shared", "MSUF_ASSISTANT_AURA_EDIT_PREVIEW")
            elseif _G.MSUF_Menu2_ApplyService and type(_G.MSUF_Menu2_ApplyService.RequestAuras) == "function" then
                _G.MSUF_Menu2_ApplyService.RequestAuras("shared", "MSUF_ASSISTANT_AURA_EDIT_PREVIEW")
            elseif a3 and type(a3.RefreshAll) == "function" then
                a3.RefreshAll()
            end
        end
        RefreshHUDControls()
        return true, StateMessage("Edit Mode Auras Preview", value, changed)
    end

    local function SetGroupPreview(value, scope)
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
            return false, "Enter Edit Mode so I can show the Group Frames preview."
        end
        local current
        if type(_G.MSUF_GF_EM2_IsPreviewShown) == "function" then
            current = _G.MSUF_GF_EM2_IsPreviewShown() and true or false
        end
        if value == nil and current == nil then
            return false, "Do you want me to show or hide the group frames preview?"
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

    return {
        SetPreview = SetPreview,
        SetBossPreview = SetBossPreview,
        SetAuraPreview = SetAuraPreview,
        SetGroupPreview = SetGroupPreview,
    }
end
