--- MSUF_EditMode_CastPopup.lua - Menu2-style quick castbar bounds popup

local addonName, MSUF = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local floor = math.floor
local max, min = math.max, math.min
local Style = _G.MSUF_EM2_Menu2Style or {}
local Quick = EM2.QuickPopup or Style.QuickPopup
if not Quick then return end

local UNIT_PAGE_KEYS = {
    player = "uf_player",
    target = "uf_target",
    focus = "uf_focus",
    boss = "uf_boss",
}

local TEST_FUNCS = {
    player = "MSUF_SetPlayerCastbarTestMode",
    target = "MSUF_SetTargetCastbarTestMode",
    focus = "MSUF_SetFocusCastbarTestMode",
    boss = "MSUF_SetBossCastbarTestMode",
}

local pf
local Sync

local function ButtonOpts(sync)
    return {
        hoverWash = true,
        hoverKey = "_msufEM2CastHoverWash",
        sync = sync,
    }
end

local function NormalizeUnit(unit)
    if unit == "player" or unit == "target" or unit == "focus" or unit == "boss" then return unit end
    if type(unit) == "string" and unit:match("^boss%d+$") then return "boss" end
    return nil
end

local function General()
    local db = _G.MSUF_DB
    return db and db.general or {}
end

local function EditableGeneral()
    local db = _G.MSUF_DB
    if not db then return nil end
    db.general = db.general or {}
    return db.general
end

local function UnitLabel(unit)
    if unit == "player" then return "Player" end
    if unit == "target" then return "Target" end
    if unit == "focus" then return "Focus" end
    if unit == "boss" then return "Boss" end
    return tostring(unit or "")
end

local function Prefix(unit)
    local fn = _G.MSUF_GetCastbarPrefix
    return type(fn) == "function" and fn(unit) or nil
end

local function DefaultOffsets(unit)
    local fn = _G.MSUF_GetCastbarDefaultOffsets
    if type(fn) == "function" then return fn(unit) end
    if unit == "player" then return 0, 5 end
    if unit == "target" or unit == "focus" then return 65, -15 end
    return 0, 0
end

local function OffsetKeys(unit)
    if unit == "boss" then return "bossCastbarOffsetX", "bossCastbarOffsetY" end
    local pre = Prefix(unit)
    if pre then return pre .. "OffsetX", pre .. "OffsetY" end
end

local function WidthKey(unit)
    if unit == "boss" then return "bossCastbarWidth" end
    local pre = Prefix(unit)
    if pre then return pre .. "BarWidth" end
end

local function HeightKey(unit)
    if unit == "boss" then return "bossCastbarHeight" end
    local pre = Prefix(unit)
    if pre then return pre .. "BarHeight" end
end

local function WidthSourceKey(unit)
    local fn = _G.MSUF_GetCastbarWidthSourceKey
    if type(fn) == "function" then
        local key = fn(unit)
        if key then return key end
    end
    if unit == "player" then return "castbarPlayerMatchWidth" end
    if unit == "target" then return "castbarTargetMatchWidth" end
    if unit == "focus" then return "castbarFocusMatchWidth" end
    if unit == "boss" then return "bossCastbarMatchWidth" end
end

local function DetachedKey(unit)
    local fn = _G.MSUF_GetCastbarDetachedKey
    if type(fn) == "function" then
        local key = fn(unit)
        if key then return key end
    end
    if unit == "player" then return "castbarPlayerDetached" end
    if unit == "target" then return "castbarTargetDetached" end
    if unit == "focus" then return "castbarFocusDetached" end
    if unit == "boss" then return "bossCastbarDetached" end
end

local function ManualWidth(g, unit)
    local key = WidthKey(unit)
    return tonumber(key and g and g[key]) or tonumber(g and g.castbarGlobalWidth) or (unit == "boss" and 176 or 271)
end

local function ManualHeight(g, unit)
    local key = HeightKey(unit)
    return tonumber(key and g and g[key]) or tonumber(g and g.castbarGlobalHeight) or (unit == "boss" and 12 or 18)
end

local function CastbarFrame(unit)
    if unit == "player" then return _G.MSUF_PlayerCastbarPreview or _G.MSUF_PlayerCastbar end
    if unit == "target" then return _G.MSUF_TargetCastbarPreview or _G.MSUF_TargetCastbar end
    if unit == "focus" then return _G.MSUF_FocusCastbarPreview or _G.MSUF_FocusCastbar end
    if unit == "boss" then return _G.MSUF_BossCastbarPreview or _G["MSUF_BossCastbarPreview1"] end
end

local function EffectiveSize(g, unit)
    local fn = _G.MSUF_GetCastbarDesiredSize
    if type(fn) == "function" then
        local w, h = fn(unit, g, CastbarFrame(unit), ManualWidth(g, unit), ManualHeight(g, unit))
        if w and h then return floor(w + 0.5), floor(h + 0.5) end
    end
    return floor(ManualWidth(g, unit) + 0.5), floor(ManualHeight(g, unit) + 0.5)
end

local function RefreshUFPreview(reason)
    local fn = _G.MSUF_UFPreview_RequestRefresh
    if type(fn) == "function" then fn(reason or "EM2_CASTBAR_POPUP") end
end

local function ReapplyCastbar(unit)
    if type(_G.MSUF_UpdateCastbarWidthSourceSync) == "function" then
        _G.MSUF_UpdateCastbarWidthSourceSync(General(), unit)
    end
    if type(_G.MSUF_ApplyCastbarEffectiveSizeUnit) == "function" then
        _G.MSUF_ApplyCastbarEffectiveSizeUnit(unit)
    end
    if type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
        _G.MSUF_ApplyCastbarUnitAndSync(unit)
    else
        local fn = (unit == "player" and "MSUF_ReanchorPlayerCastBar")
            or (unit == "target" and "MSUF_ReanchorTargetCastBar")
            or (unit == "focus" and "MSUF_ReanchorFocusCastBar")
            or (unit == "boss" and "MSUF_ReanchorBossCastBar")
        if type(_G[fn]) == "function" then _G[fn]() end
        if type(_G.MSUF_UpdateCastbarVisuals) == "function" then _G.MSUF_UpdateCastbarVisuals() end
    end
    if type(_G.MSUF_PositionCastbarPreviewUnit) == "function" then _G.MSUF_PositionCastbarPreviewUnit(unit) end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    RefreshUFPreview("EM2_CASTBAR_POPUP_APPLY")
end

local function Apply(mode)
    if Quick.BlockConfigCombatLocked() or not (pf and pf.unit) then return end
    local g = EditableGeneral()
    if not g then return end
    local unit = pf.unit
    local xKey, yKey = OffsetKeys(unit)
    local wKey, hKey = WidthKey(unit), HeightKey(unit)
    if not (xKey and yKey and wKey and hKey) then return end

    if type(_G.MSUF_EM_UndoBeforeChange) == "function" then _G.MSUF_EM_UndoBeforeChange("castbar", unit) end

    if mode == "position" or mode == "all" then
        local dx, dy = DefaultOffsets(unit)
        g[xKey] = Quick.San(pf.xBox and pf.xBox:GetText(), dx)
        g[yKey] = Quick.San(pf.yBox and pf.yBox:GetText(), dy)
    end

    if mode == "width" or mode == "all" then
        local w = tonumber(pf.wBox and pf.wBox:GetText())
        if w then
            g[wKey] = floor(max(50, min(600, w)) + 0.5)
            local sourceKey = WidthSourceKey(unit)
            if sourceKey then g[sourceKey] = nil end
        end
    end

    if mode == "height" or mode == "all" then
        local h = tonumber(pf.hBox and pf.hBox:GetText())
        if h then g[hKey] = floor(max(8, min(100, h)) + 0.5) end
    end

    ReapplyCastbar(unit)
    if pf and pf:IsShown() then Sync() end
end

local function ApplyDetach(checked)
    if Quick.BlockConfigCombatLocked() or not (pf and pf.unit) then return end
    local g = EditableGeneral()
    if not g then return end
    local key = DetachedKey(pf.unit)
    if not key then return end

    if type(_G.MSUF_EM_UndoBeforeChange) == "function" then _G.MSUF_EM_UndoBeforeChange("castbar", pf.unit) end
    g[key] = checked and true or false
    ReapplyCastbar(pf.unit)
    if pf and pf:IsShown() then Sync() end
end

local function SetTest(unit, on)
    for key, fnName in pairs(TEST_FUNCS) do
        local fn = _G[fnName]
        if type(fn) == "function" then fn(key == unit and on, true) end
    end
end

local function CommitShortcutFields()
    Quick.ClearFocusedBoxes(pf and pf.xBox, pf and pf.yBox, pf and pf.wBox, pf and pf.hBox)
    Apply("position")
end

local function OpenUnitCastbar()
    if not (pf and pf.unit) then return end
    CommitShortcutFields()
    local unit = pf.unit
    local pageKey = UNIT_PAGE_KEYS[unit] or "uf_player"
    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(unit == "boss" and "boss" or unit, "castbar", nil, { source = "cast-popup", menu = false })
    end
    _G.MSUF_EM2_MenuFocusRequest = {
        key = unit == "boss" and "boss" or unit,
        component = "castbar",
        pageKey = pageKey,
        sectionId = "castbar",
        source = "cast-popup",
        explicit = true,
        changedAt = GetTime and GetTime() or 0,
    }
    local M = _G.MSUF2 or (MSUF and MSUF.MSUF2)
    if M then M.editModeSelection = _G.MSUF_EM2_MenuFocusRequest end
    Quick.OpenPage(pageKey, pf)
end

local function OpenGeneralCastbars()
    if not (pf and pf.unit) then return end
    CommitShortcutFields()
    _G.MSUF_EM2_MenuFocusRequest = {
        key = "castbar",
        component = "general",
        pageKey = "opt_castbar",
        sectionId = "castbar_behavior",
        source = "cast-popup",
        explicit = true,
        changedAt = GetTime and GetTime() or 0,
    }
    Quick.OpenPage("opt_castbar", pf)
end

local function WirePopupFocus(btn)
    if not (btn and btn.HookScript) then return btn end
    btn:HookScript("OnEnter", function()
        if pf and pf.unit and EM2.Focus and EM2.Focus.SetHover then
            EM2.Focus.SetHover(pf.unit == "boss" and "boss" or pf.unit, "castbar", nil, { source = "cast-popup" })
        end
    end)
    btn:HookScript("OnLeave", function()
        if EM2.Focus and EM2.Focus.ClearHover then EM2.Focus.ClearHover("cast-popup") end
    end)
    return btn
end

function Sync()
    if not (pf and pf.unit) then return end
    local g, unit = General(), pf.unit
    local xKey, yKey = OffsetKeys(unit)
    local dx, dy = DefaultOffsets(unit)
    local w, h = EffectiveSize(g, unit)

    if pf._titleFS then pf._titleFS:SetText(Quick.Tr(UnitLabel(unit) .. " - Castbar")) end
    Quick.SetBoxText(pf.xBox, Quick.San(xKey and g[xKey], dx))
    Quick.SetBoxText(pf.yBox, Quick.San(yKey and g[yKey], dy))
    Quick.SetBoxText(pf.wBox, w)
    Quick.SetBoxText(pf.hBox, h)
    if pf.detachBtn and pf.detachBtn.SetCheckedVisual then
        local dKey = DetachedKey(unit)
        pf.detachBtn:SetCheckedVisual(dKey and g[dKey] == true)
    end
end

local function Build()
    if pf then return pf end

    pf = Quick.CreateShell("MSUF_EM2_CastPopup", {
        subtitle = "Castbar bounds",
        hoverSource = "cast-popup",
        hoverWash = true,
        hoverKey = "_msufEM2CastHoverWash",
        onHide = function()
            if pf.unit and not _G.MSUF_UnitPreviewActive then SetTest(pf.unit, false) end
        end,
    })

    Quick.ValuePair(pf, pf, -72, "X", "xBox", function() Apply("position") end, "Y", "yBox", function() Apply("position") end, ButtonOpts())
    Quick.ValuePair(pf, pf, -102, "Width", "wBox", function() Apply("width") end, "Height", "hBox", function() Apply("height") end, ButtonOpts())

    pf.detachBtn = Quick.ToggleButton(pf, "Detach castbar from unitframe", 394, 30, ApplyDetach, ButtonOpts(function()
        if pf and pf:IsShown() then Sync() end
    end))
    pf.detachBtn:SetPoint("TOPLEFT", pf, "TOPLEFT", 20, -140)

    WirePopupFocus(Quick.Button(pf, "Unitframe castbar", 190, 30, OpenUnitCastbar, ButtonOpts())):SetPoint("TOPLEFT", pf, "TOPLEFT", 20, -190)
    WirePopupFocus(Quick.Button(pf, "General castbar", 190, 30, OpenGeneralCastbars, ButtonOpts())):SetPoint("TOPLEFT", pf, "TOPLEFT", 224, -190)

    if EM2.AttachPopupScaleGrip then EM2.AttachPopupScaleGrip(pf) end
    return pf
end

local CastPopup = {}
EM2.CastPopup = CastPopup

function CastPopup.Open(unit, parent)
    if Quick.BlockConfigCombatLocked() then return false end
    unit = NormalizeUnit(unit)
    if not unit then return false end
    Build()
    pf.unit, pf.parent = unit, parent
    Sync()
    pf:Show()
    SetTest(unit, true)
    if Style.FadeIn then Style.FadeIn(pf, 0.12, 0.86, 1) end
    return true
end

function CastPopup.Close()
    if pf then
        if pf.unit and not _G.MSUF_UnitPreviewActive then SetTest(pf.unit, false) end
        pf:Hide()
    end
end

function CastPopup.IsOpen()
    return pf and pf:IsShown() or false
end

function CastPopup.GetUnit()
    return pf and pf.unit or nil
end

function CastPopup.Sync()
    if pf and pf:IsShown() then Sync() end
end
