--- EditMode/MSUF_EditMode_HUD.lua - Edit Mode HUD and guided tour
-- Builds EditMode HUD widgets only; secure frame mutation stays behind EditMode helpers.
local _, MSUFRoot = ...
MSUFRoot = MSUFRoot or _G.MSUF_NS or {}
local ExportPublic = MSUFRoot.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local function InstallEditModeHUD(...)
local addonName, MSUF = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local HUD = {}; EM2.HUD = HUD

local L     = (MSUF and MSUF.L) or _G.MSUF_L or setmetatable({}, { __index = function(_, k) return k end })
local FONT  = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
local W8    = "Interface/Buttons/WHITE8X8"
local MEDIA = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\"
local floor, max, min = math.floor, math.max, math.min
local U = EM2.Util or {}
local ApplyAllSettingsSafe = U.ApplyAllSettingsSafe
local ApplySettingsForKeySafe = U.ApplySettingsForKeySafe
local SharedUI = U.SharedUI
local function Space(role, fallback)
    local ui = SharedUI and SharedUI()
    return ui and ui.Space and ui.Space(role, fallback) or fallback
end

local hudFrame, row2Frame
local DockUI = {}
local ApplyDockLayout, RefreshPositionPopup, SetDockExpanded, ScheduleDockAutoHide, StopDockDrag
local previewBtn, previewAnimBtn, auraBtn, snapToggle, resetBtn, settingsBtn, cdmBtn, anchorBtn
local previewAddonSlot

local function InvokeHUDOptional(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, r1 = pcall(fn, ...)
    if not ok then
        local handler = _G.geterrorhandler and _G.geterrorhandler()
        if type(handler) == "function" then pcall(handler, r1) end
        return false, r1
    end
    return true, r1
end
local previewAnimRefreshRegistered
local undoBtn, redoBtn, cancelAllBtn, exitBtn
local alphaFS, stepFS
local selectionFS, hintFS
local hudStatusText, hudStatusKind, hudStatusUntil
local selectionLastText, hintLastText, hintLastR, hintLastG, hintLastB, hintLastA
local helpBtn
local guidedTourBridgeRequested = false
local bgWidget, gridWidget
local HelpText

--- Reached through DockUI on purpose: EnsureHUD sits at Lua's 60-upvalue
--- ceiling, so a direct FONT reference from a function nested inside it fails
--- to compile.
DockUI.baseFont = FONT
DockUI.controlH = 36
DockUI.inspectorH = 40
DockUI.inspectorLabelW = 176
DockUI.inspectorMetricW = 60
local BTN_H   = DockUI.controlH
local BTN_H2  = DockUI.controlH
local BTN_GAP = Space("sm", 8)
local SEP_W   = 8
local CLUSTER_H     = 52
local CLUSTER_BTN_H = BTN_H
local CLUSTER_GAP   = Space("sm", 8)
local CLUSTER_PAD_X = Space("sm", 8)
local DOCK_HORIZONTAL_W = 1428
local DOCK_HORIZONTAL_H = 68
local DOCK_VERTICAL_W   = 82
local DOCK_EDGE_DEFAULT = 12
local DOCK_SNAP_EDGE_PX = 24
local DOCK_ALLOWED = { TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, FREE = true }
-- Edit controls must stay above every stationary mover/hitbox, including Aura3
-- preview groups on TOOLTIP level 900-930.  The active full-screen aura drag
-- capture intentionally remains above the dock at level 1500.

local TH = {
    r1Bg   = { 0.026, 0.032, 0.052, 0.94 },
    r2Bg   = { 0.022, 0.028, 0.046, 0.88 },
    edge   = { 0.105, 0.130, 0.220, 0.38 },
    titleR=0.56, titleG=0.63, titleB=0.76,
    textR=0.78, textG=0.82, textB=0.92,
    mutedR=0.50, mutedG=0.56, mutedB=0.68,
    onR=0.18, onG=0.72, onB=0.90,
    okR=0.24, okG=0.82, okB=0.46,
    warnR=0.96, warnG=0.76, warnB=0.15,
    offR=0.40, offG=0.44, offB=0.54,
    exitR=0.90, exitG=0.32, exitB=0.32,
}

local function RefreshHUDTheme()
    local ui = SharedUI()
    local function CKey(key, fallback)
        if ui and ui.Color then return ui.Color(key, fallback) end
        return fallback
    end
    local function RGB(prefix, c, fallback)
        c = c or fallback
        TH[prefix .. "R"], TH[prefix .. "G"], TH[prefix .. "B"] = c[1] or fallback[1], c[2] or fallback[2], c[3] or fallback[3]
    end
    TH.r1Bg = CKey("popup", TH.r1Bg)
    TH.r2Bg = CKey("card", TH.r2Bg)
    TH.edge = CKey("borderSoft", TH.edge)
    RGB("title", CKey("dim", { TH.titleR, TH.titleG, TH.titleB, 1 }), { TH.titleR, TH.titleG, TH.titleB, 1 })
    RGB("text", CKey("text", { TH.textR, TH.textG, TH.textB, 1 }), { TH.textR, TH.textG, TH.textB, 1 })
    RGB("muted", CKey("muted", { TH.mutedR, TH.mutedG, TH.mutedB, 1 }), { TH.mutedR, TH.mutedG, TH.mutedB, 1 })
    RGB("on", CKey("accent", { TH.onR, TH.onG, TH.onB, 1 }), { TH.onR, TH.onG, TH.onB, 1 })
    RGB("ok", CKey("ok", { TH.okR, TH.okG, TH.okB, 1 }), { TH.okR, TH.okG, TH.okB, 1 })
    RGB("warn", CKey("accent2", { TH.warnR, TH.warnG, TH.warnB, 1 }), { TH.warnR, TH.warnG, TH.warnB, 1 })
    RGB("exit", CKey("danger", { TH.exitR, TH.exitG, TH.exitB, 1 }), { TH.exitR, TH.exitG, TH.exitB, 1 })
end

local function ApplyHUDMaterial(frame, material)
    local ui = SharedUI()
    if ui and ui.ApplyMaterial then return ui.ApplyMaterial(frame, material or "card") end
    return frame
end

local function MakeFS(p, fontRole, r, g, b, a)
    local fs = p:CreateFontString(nil, "OVERLAY")
    local ui = SharedUI()
    if ui and ui.ApplyFontRole then
        ui.ApplyFontRole(fs, fontRole or "body", FONT, "")
    else
        local size = ui and ui.FontSize and ui.FontSize(fontRole or "body") or 13
        fs:SetFont(FONT, size, "")
    end
    fs:SetShadowOffset(1, -1)
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.35) end
    fs:SetTextColor(r or 1, g or 1, b or 1, a or 1); return fs
end

local function SetActive(btn, on)
    if not btn or not btn._label then return end
    on = on == true
    if btn._msufActive == on then return end
    btn._msufActive = on
    if btn.SetActive then btn:SetActive(on) end
    if on then
        btn._label:SetTextColor(TH.textR, TH.textG, TH.textB, 1)
        if btn._dot then
            if btn.SetActive then btn._dot:Hide() else btn._dot:Show() end
        end
    else
        btn._label:SetTextColor(TH.offR, TH.offG, TH.offB, 0.85)
        if btn._dot then btn._dot:Hide() end
    end
end

function HUD.AutomaticCooldownProvider()
    local getter = _G.MSUF_GetAutomaticCooldownAnchorProvider
    if type(getter) ~= "function" then return nil, nil end
    return getter()
end

function HUD.CooldownAnchorEnabled(general)
    local getter = _G.MSUF_IsCooldownAnchorEnabled
    if type(getter) == "function" then return getter(general) == true end
    return general and general.anchorToCooldown == true or false
end

local function SetControlEnabled(btn, enabled)
    if not btn or not btn._label then return end
    enabled = enabled == true
    if btn._msufControlEnabled == enabled then return end
    btn._msufControlEnabled = enabled
    btn:SetAlpha(enabled and 1 or 0.45)
    btn._label:SetTextColor(
        enabled and TH.textR or TH.offR,
        enabled and TH.textG or TH.offG,
        enabled and TH.textB or TH.offB,
        enabled and 0.92 or 0.55
    )
end

local function SetHistoryEnabled(btn, enabled)
    if not (btn and btn._historyIcon) then return end
    enabled = enabled == true
    if btn._msufHistoryEnabled == enabled then return end
    btn._msufHistoryEnabled = enabled
    btn._historyIcon:SetAlpha(enabled and 1 or 0.35)
end

local function RegisterPreviewAnimationRefreshOwner()
    if previewAnimRefreshRegistered or not previewAnimBtn then return end
    local register = _G.MSUF_RegisterPreviewAnimationRefreshOwner
    if type(register) ~= "function" then return end
    register(previewAnimBtn, function(btn, active)
        SetActive(btn, active == true)
    end)
    previewAnimRefreshRegistered = true
end

--- Hooks rather than SetScript: the shared themed button installs its hover
--- repaint through SetScript("OnEnter"/"OnLeave"), and Menu2's ButtonSetScript
--- only chains OnClick -- everything else is passed straight to the raw setter.
--- Replacing those handlers here silently removed the hover styling from every
--- toolbar button that carries a tooltip. Keeping the text on the widget makes
--- re-tipping cheap and keeps exactly one handler pair installed.
--- The toolbar deliberately sits at TOOLTIP level 1200 to beat Edit Mode
--- hitboxes, and GameTooltip shares that strata at a far lower level - so a tip
--- would draw underneath the bar and its X/Y row.  Raise it while an MSUF Edit
--- Mode tip is up and hand the level straight back on leave, so no other
--- addon's tooltip inherits our ordering.
DockUI.tooltipLevel = 1620
DockUI.OwnTooltip = function(widget, anchor, x, y)
    if not (GameTooltip and widget and GameTooltip.SetOwner) then return false end
    GameTooltip:SetOwner(widget, anchor or "ANCHOR_BOTTOM", x or 0, y or -6)
    if not (GameTooltip.SetFrameLevel and GameTooltip.GetFrameLevel) then return true end
    if DockUI.tooltipRestoreLevel == nil then
        DockUI.tooltipRestoreLevel = tonumber(GameTooltip:GetFrameLevel()) or 0
        DockUI.tooltipRestoreStrata = GameTooltip.GetFrameStrata and GameTooltip:GetFrameStrata() or nil
    end
    if GameTooltip.SetFrameStrata then GameTooltip:SetFrameStrata("TOOLTIP") end
    GameTooltip:SetFrameLevel(DockUI.tooltipLevel)
    return true
end
DockUI.ReleaseTooltip = function()
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    if DockUI.tooltipRestoreLevel == nil then return end
    if GameTooltip and GameTooltip.SetFrameLevel then
        if DockUI.tooltipRestoreStrata and GameTooltip.SetFrameStrata then
            GameTooltip:SetFrameStrata(DockUI.tooltipRestoreStrata)
        end
        GameTooltip:SetFrameLevel(DockUI.tooltipRestoreLevel)
    end
    DockUI.tooltipRestoreLevel, DockUI.tooltipRestoreStrata = nil, nil
end

local function SetTip(widget, text)
    if not widget or not text then return end
    widget._msufTipText = text
    if widget._msufTipHooked or not widget.HookScript then return end
    widget._msufTipHooked = true
    widget:HookScript("OnEnter", function(self)
        local tip = self._msufTipText
        if not tip then return end
        if not DockUI.OwnTooltip(self, "ANCHOR_BOTTOM", 0, -6) then return end
        GameTooltip:SetText(HelpText(tip), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() DockUI.ReleaseTooltip() end)
end

local UNIT_KEYS = { player = true, target = true, focus = true, focustarget = true, targettarget = true, pet = true, boss = true }

local GROUP_KEY_TO_KIND = {
    gf_party = "party",
    gf_raid = "raid",
    gf_mythicraid = "mythicraid",
    gf_priority = "priority",
}

local function GroupGeometryMask(gf)
    return (gf and (gf.DIRTY_GEOMETRY or gf.DIRTY_LAYOUT or gf.DIRTY_VISUAL)) or nil
end

local function RequestGroupGeometryApply(kind, reason)
    if not kind then return false end
    local menu = (MSUF and MSUF.MSUF2) or _G.MSUF2
    local apply = (menu and menu.ApplyService) or _G.MSUF_Menu2_ApplyService
    if not (apply and type(apply.RequestGroup) == "function") then return false end
    apply.RequestGroup(kind, "geometry", reason or "EM2_GROUP_GEOMETRY")
    if type(apply.Flush) == "function" then apply.Flush() end
    return true
end

local function RefreshGroupGeometryScoped(kind)
    if not kind then return false end
    if RequestGroupGeometryApply(kind, "EM2_HUD_GROUP_GEOMETRY") then
        return true
    end
    local gf = MSUF and MSUF.GF
    if gf and type(gf.RefreshGeometry) == "function" then
        gf.RefreshGeometry(kind)
        return true
    end
    if type(_G.MSUF_GF_RefreshGeometry) == "function" then
        _G.MSUF_GF_RefreshGeometry(kind)
        if type(_G.MSUF_GF_RefreshUnitBindings) == "function" then
            _G.MSUF_GF_RefreshUnitBindings(kind)
        end
        if type(_G.MSUF_GF_RefreshVisuals) == "function" then
            _G.MSUF_GF_RefreshVisuals(kind, GroupGeometryMask(gf))
        end
        return true
    end
    if gf and type(gf.RefreshVisuals) == "function" then
        gf.RefreshVisuals(kind, GroupGeometryMask(gf))
        return true
    end
    if type(_G.MSUF_GF_RefreshVisuals) == "function" then
        _G.MSUF_GF_RefreshVisuals(kind)
        return true
    end
    if type(_G.MSUF_GF_RefreshAll) == "function" then
        _G.MSUF_GF_RefreshAll()
        return true
    end
    if type(_G.MSUF_GF_Refresh) == "function" then
        _G.MSUF_GF_Refresh()
        return true
    end
    return false
end

local LABEL_BY_KEY = {
    player = "Player",
    target = "Target",
    focus = "Focus",
    focustarget = "Focus Target",
    targettarget = "ToT",
    pet = "Pet",
    boss = "Boss",
    gf_party = "Party Frames",
    gf_raid = "Raid Frames",
    gf_mythicraid = "Mythic Raid Frames",
    gf_priority = "Priority Frames",
}

local COMPONENT_LABEL = {
    frame = "Frame",
    layout = "Layout",
    bounds = "Frame",
    size = "Size",
    name = "Name",
    hp = "Health Text",
    power = "Power Text",
    text = "Text",
    auras = "Auras",
    castbar = "Castbar",
    cast = "Castbar",
    bars = "Bars",
    status = "Status & Indicators",
    indicators = "Status & Indicators",
    sicons = "Status Icons",
}

local function CurrentSelectionKey()
    local key = (EM2.State and EM2.State.GetUnitKey and EM2.State.GetUnitKey()) or _G.MSUF_CurrentEditUnitKey
    if not key and EM2.Focus and EM2.Focus.GetSelection then
        key = EM2.Focus.GetSelection()
    end
    return key
end

local function CurrentFocusSelection()
    local auraPopup = EM2.AuraPopup
    if auraPopup and type(auraPopup.IsOpen) == "function" and auraPopup.IsOpen() then
        local unit = rawget(_G, "MSUF_EM2_ActiveAuraUnit")
        if type(unit) == "string" then
            local key = unit:match("^boss%d+$") and "boss" or unit
            if UNIT_KEYS[key] then return key, "auras", nil end
        end
    end
    if EM2.Focus and EM2.Focus.GetSelection then
        local key, component, slot = EM2.Focus.GetSelection()
        if key then return key, component, slot end
    end
    return CurrentSelectionKey(), nil, nil
end

local function SelectionDetail(component, slot)
    local label = component and (COMPONENT_LABEL[component] or component) or nil
    if label and slot then return label .. " " .. tostring(slot) end
    return label
end

local function AuraSelectionFrame(key, component)
    if component ~= "auras" then return nil end
    local unit = rawget(_G, "MSUF_EM2_ActiveAuraUnit")
    local kind = rawget(_G, "MSUF_EM2_ActiveAuraGroup")
    if type(unit) ~= "string" or type(kind) ~= "string" then return nil end
    local selectionUnit = unit:match("^boss%d+$") and "boss" or unit
    if selectionUnit ~= key then return nil end
    local a3 = MSUF and MSUF.MSUF_Auras3
    local edit = a3 and a3.EditMode
    local groups = edit and edit.groups
    local group = groups and groups[unit] and groups[unit][kind]
    return group and (group.Body or group) or nil
end

local function SelectionValues(key, component, slot)
    if not key then return HelpText("No selection") end
    local cfg = EM2.Registry and EM2.Registry.Get and EM2.Registry.Get(key) or nil
    if cfg and cfg.externalPublicElement == true then
        local external = EM2.ExternalElements
        if external and type(external.GetInspectorValues) == "function" then
            return external.GetInspectorValues(key)
        end
        return HelpText(cfg.label or key)
    end
    local db = _G.MSUF_DB
    local conf
    local groupKind = GROUP_KEY_TO_KIND[key]
    if groupKind then
        conf = db and db[key]
    elseif UNIT_KEYS[key] then
        conf = db and db[key]
    end

    local label = HelpText(LABEL_BY_KEY[key] or key)
    local detail = SelectionDetail(component, slot)
    if detail then label = label .. " / " .. HelpText(detail) end
    local frame = AuraSelectionFrame(key, component)
    if not frame and cfg and type(cfg.getFrame) == "function" then
        local ok, resolved = pcall(cfg.getFrame)
        if ok then frame = resolved end
    end
    if frame and type(U.FramePositionValues) == "function" then
        local x, y, width, height = U.FramePositionValues(frame)
        if x ~= nil then return label, x, y, width, height end
    end
    if not conf then return label end
    local x = floor((tonumber(conf.offsetX) or 0) + 0.5)
    local y = floor((tonumber(conf.offsetY) or 0) + 0.5)
    local w = tonumber(conf.width)
    local h = tonumber(conf.height)
    return label, x, y, w and floor(w + 0.5), h and floor(h + 0.5)
end

local function FormatSelectionSummary(label, x, y, w, h)
    if x == nil or y == nil then return label end
    if w and h then
        return string.format("%s   X %d   Y %d   W %d   H %d", label, x, y, w, h)
    end
    return string.format("%s   X %d   Y %d", label, x, y)
end

local function SelectionSummary(key, component, slot)
    return FormatSelectionSummary(SelectionValues(key, component, slot))
end

local function SetHint(text, r, g, b, a)
    if not hintFS then return end
    text = text or ""
    r, g, b, a = r or TH.mutedR, g or TH.mutedG, b or TH.mutedB, a or 0.78
    if hintLastText ~= text then
        hintFS:SetText(text)
        hintLastText = text
    end
    if hintLastR ~= r or hintLastG ~= g or hintLastB ~= b or hintLastA ~= a then
        hintFS:SetTextColor(r, g, b, a)
        hintLastR, hintLastG, hintLastB, hintLastA = r, g, b, a
    end
end

local function DefaultHintText(hasSelection)
    if EM2.Popups and EM2.Popups.IsAnyOpen and EM2.Popups.IsAnyOpen() then
        return HelpText("EM_HINT_POPUP")
    end
    if hasSelection then
        return HelpText("EM_HINT_SELECTED")
    end
    return HelpText("EM_HINT_NONE")
end

function HUD.SetStatus(text, kind, seconds)
    seconds = seconds or 1.6
    hudStatusText = text
    hudStatusKind = kind
    hudStatusUntil = (GetTime and GetTime() or 0) + seconds
    HUD.RefreshControls()
    C_Timer.After(seconds, function()
        if HUD.IsShown and HUD.IsShown() then HUD.RefreshControls() end
    end)
end

local function BlockHUDConfigLocked()
    if type(_G.MSUF_BlockConfigCombatLocked) == "function" then
        return _G.MSUF_BlockConfigCombatLocked() and true or false
    end
    if InCombatLockdown and InCombatLockdown() then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
        return true
    end
    return false
end

function HUD.OpenSelectedSettings()
    if BlockHUDConfigLocked() then return end
    local key, component, slot = CurrentFocusSelection()
    key = key or CurrentSelectionKey()
    if not key then
        HUD.SetStatus(HelpText("EM_SELECT_FIRST"), "warn")
        return
    end
    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(key, component, slot, { source = "hud-settings", openSettings = true })
    end
    local opener = (EM2.Focus and EM2.Focus.OpenFullSettings) or _G.MSUF_EM2_OpenFocusSettings
    if type(opener) == "function" and opener() then
        HUD.SetStatus(HelpText("Opened settings"), "ok")
    else
        HUD.SetStatus(HelpText("Settings unavailable"), "warn")
    end
end

function HUD.ResetCurrentPosition()
    if BlockHUDConfigLocked() then return end

    local key = CurrentSelectionKey()
    if not key then HUD.SetStatus(HelpText("EM_SELECT_FIRST"), "warn"); return end
    local cfg = EM2.Registry and EM2.Registry.Get and EM2.Registry.Get(key) or nil
    if cfg and cfg.externalPublicElement == true then
        local external = EM2.ExternalElements
        if external and type(external.Reset) == "function" and external.Reset(key) then
            HUD.SetStatus(HelpText("Reset") .. " " .. HelpText(cfg.label or key), "ok")
        else
            HUD.SetStatus(HelpText("Reset unavailable"), "warn")
        end
        HUD.RefreshControls()
        return
    end
    local groupKind = GROUP_KEY_TO_KIND[key]
    if groupKind then
        if type(_G.MSUF_GF_EM2_ResetPosition) == "function" then
            _G.MSUF_GF_EM2_ResetPosition(groupKind)
        else
            local db = _G.MSUF_DB
            local conf = db and db[key]
            if conf then
                if type(_G.MSUF_EM_UndoBeforeChange) == "function" then
                    _G.MSUF_EM_UndoBeforeChange("gf", groupKind)
                end
                conf.offsetX = groupKind == "party" and -400 or groupKind == "priority" and -120 or -500
                conf.offsetY = 0
                if groupKind == "priority" then
                    conf.anchorMode = "RAID_RIGHT"
                    conf.attachGap = 8
                    conf.attachOffset = 0
                    conf.point = "CENTER"
                    conf.relativePoint = "CENTER"
                end
                RefreshGroupGeometryScoped(groupKind)
                if type(_G.MSUF_EM2_SyncGFPopups) == "function" then _G.MSUF_EM2_SyncGFPopups() end
                if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
            end
        end
        if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(key, true) end
        if EM2.Focus and EM2.Focus.Pulse then EM2.Focus.Pulse(key, "layout", nil, { source = "hud-reset", duration = 0.32 }) end
        HUD.SetStatus(HelpText("Reset") .. " " .. HelpText(LABEL_BY_KEY[key] or key), "ok")
        HUD.RefreshControls()
        return
    end

    if not UNIT_KEYS[key] then HUD.SetStatus(HelpText("EM_SELECT_FIRST"), "warn"); return end
    local db = _G.MSUF_DB
    local conf = db and db[key]
    if not conf then return end
    if type(_G.MSUF_EM_UndoBeforeChange) == "function" then
        _G.MSUF_EM_UndoBeforeChange("unit", key)
    end
    conf.offsetX = 0
    conf.offsetY = 0
    if not ApplySettingsForKeySafe(key) then
        ApplyAllSettingsSafe()
    end
    if type(_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey) == "function" then
        _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey(key, true)
    elseif type(_G.MSUF_ApplyPowerBarEmbedLayout_All) == "function" then
        _G.MSUF_ApplyPowerBarEmbedLayout_All()
    end
    if EM2.UnitPopup and EM2.UnitPopup.Sync then EM2.UnitPopup.Sync() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(key, true) end
    if EM2.Focus and EM2.Focus.Pulse then EM2.Focus.Pulse(key, "frame", nil, { source = "hud-reset", duration = 0.32 }) end
    if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then _G.MSUF_UFPreview_RequestRefresh("EM2_HUD_RESET_POSITION") end
    HUD.SetStatus(HelpText("Reset") .. " " .. HelpText(LABEL_BY_KEY[key] or key), "ok")
    HUD.RefreshControls()
end

--- The nav rail tints a hovered entry's label instead of only brightening it, so
--- the toolbar controls do the same. Themed buttons carry a flag the shared
--- painter reads (that survives SetActive/RefreshVisual repaints mid-hover);
--- plain font strings on frames get a hook that captures and restores their own
--- resting color, so theme swaps never bake in a stale base.
local HOVER_TEXT_ACCENT = { 0.357, 0.608, 1.000, 1.000 }
local function HoverTextAccentColor()
    local ui = SharedUI()
    if ui and ui.Color then return ui.Color("navHeaderHover", HOVER_TEXT_ACCENT) end
    return HOVER_TEXT_ACCENT
end

local function AttachHoverTextAccent(widget, label)
    if not widget or widget._msufHoverAccentHooked then return widget end
    widget._msufHoverAccentHooked = true
    widget._msuf2HoverTextAccent = true
    --- Anything that owns a painter (themed button or the shared UI fallback)
    --- repaints its label on OnLeave itself. Hooking on top of that would capture
    --- the accent as the resting color and leave the label tinted for good.
    if widget._msuf2Label or widget._msufUIFill then return widget end
    label = label or widget._label
    if not (label and label.SetTextColor and widget.HookScript) then return widget end
    widget._msufHoverAccentLabel = label
    widget:HookScript("OnEnter", function(self)
        local fs = self._msufHoverAccentLabel
        if not fs or self._msufHoverAccentActive then return end
        self._msufHoverAccentActive = true
        self._msufHoverAccentBase = { fs:GetTextColor() }
        local c = HoverTextAccentColor()
        fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end)
    widget:HookScript("OnLeave", function(self)
        local fs = self._msufHoverAccentLabel
        local base = self._msufHoverAccentBase
        self._msufHoverAccentActive = nil
        if fs and base then fs:SetTextColor(base[1], base[2], base[3], base[4] or 1) end
    end)
    return widget
end

local function MakeBtn(parent, text, w, h, fontRole, onClick)
    w = w or (#text * 8 + 18); h = h or BTN_H
    local ui = (type(MSUF) == "table" and MSUF.UI) or _G.MSUF_UI
    local btn = ui and ui.Button and ui.Button(parent, HelpText(text), w, h, {
        align = "CENTER",
        skipHistory = true,
        onClick = onClick,
    }) or CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)
    local label = btn._msuf2Label or btn._label
    if not label then
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.05)
        label = MakeFS(btn, fontRole or "body", TH.textR, TH.textG, TH.textB, 0.92)
        label:SetPoint("CENTER"); label:SetText(HelpText(text))
    elseif ui and ui.ApplyFontRole then
        --- Shared buttons build their label from a Blizzard font object, which
        --- carries Blizzard's face and ignores the configured menu font that
        --- every MakeFS string in this toolbar already follows.  Re-apply the
        --- role so button text matches the labels next to it.
        ui.ApplyFontRole(label, fontRole or "body", FONT, "")
    end
    btn._label = label
    local dot = btn:CreateTexture(nil, "OVERLAY")
    dot:SetSize(w - 8, 2); dot:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)
    dot:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.90); dot:Hide()
    btn._dot = dot
    if onClick and not (ui and ui.Button) then btn:SetScript("OnClick", onClick) end
    AttachHoverTextAccent(btn, label)
    return btn
end

local function AttachHistoryIcon(btn, texturePath)
    if not btn then return end
    if btn._label then btn._label:Hide() end
    if btn._dot then btn._dot:Hide() end
    local icon = btn:CreateTexture(nil, "ARTWORK", nil, 5)
    icon:SetTexture(texturePath)
    icon:SetSize(17, 17)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn._historyIcon = icon
    return icon
end

local function RowItemsWidth(items, gap, sepW)
    local totalW = 0
    for i, b in ipairs(items) do
        totalW = totalW + (b._isSep and sepW or b:GetWidth())
        if i < #items then totalW = totalW + gap end
    end
    return totalW
end

local function MakeCluster(parent, label, height, showLabel)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(1, height or CLUSTER_H)
    f:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    f:SetBackdropColor(TH.r2Bg[1], TH.r2Bg[2], TH.r2Bg[3], 0.38)
    f:SetBackdropBorderColor(TH.edge[1], TH.edge[2], TH.edge[3], 0.34)

    if showLabel ~= false and label then
        local fs = MakeFS(f, "micro", TH.mutedR, TH.mutedG, TH.mutedB, 0.70)
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -3)
        fs:SetText(HelpText(label))
        f._clusterLabel = fs
    end
    return f
end

local function AddCluster(row, parent, label, height, showLabel)
    local cluster = MakeCluster(parent, label, height, showLabel)
    row[#row + 1] = cluster
    return cluster, {}
end

local function FinishCluster(cluster, items, height, yOff)
    cluster._dockItems = items
    cluster._dockHorizontalHeight = height or CLUSTER_H
    cluster._dockHorizontalYOffset = yOff or 0
    local w = RowItemsWidth(items, BTN_GAP, SEP_W) + CLUSTER_PAD_X * 2
    cluster:SetSize(w, height or CLUSTER_H)
    local x = CLUSTER_PAD_X
    for _, b in ipairs(items) do
        if not b._dockHorizontalWidth then
            b._dockHorizontalWidth = b:GetWidth()
            b._dockHorizontalHeight = b:GetHeight()
        end
        local bw = b._isSep and SEP_W or b:GetWidth()
        b:ClearAllPoints()
        if b._isSep then
            b:SetPoint("LEFT", cluster, "LEFT", x + bw * 0.5, yOff or 0)
        else
            b:SetPoint("LEFT", cluster, "LEFT", x, yOff or 0)
        end
        x = x + bw + BTN_GAP
    end
    return cluster
end

local function AddRowButton(row, parent, text, width, height, fontRole, onClick, tip)
    local btn = MakeBtn(parent, text, width, height, fontRole, onClick)
    if tip then SetTip(btn, tip) end
    row[#row + 1] = btn
    return btn
end

local function AddAdjustWidget(row, parent, width, height, withStateBg, onMouseWheel, onMouseUp, tip)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, height); f:EnableMouse(true); f:EnableMouseWheel(true)
    if withStateBg then
        local stateBg = f:CreateTexture(nil, "BACKGROUND")
        stateBg:SetAllPoints(); stateBg:SetColorTexture(0, 0, 0, 0)
        f._stateBg = stateBg
    end
    local fs = MakeFS(f, "caption", TH.mutedR, TH.mutedG, TH.mutedB, 0.80)
    fs:SetPoint("CENTER")
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.04)
    if onMouseUp then f:SetScript("OnMouseUp", onMouseUp) end
    if onMouseWheel then f:SetScript("OnMouseWheel", onMouseWheel) end
    if tip then SetTip(f, tip) end
    --- After SetTip: it installs OnEnter/OnLeave with SetScript, which would drop
    --- an earlier hook chain.
    AttachHoverTextAccent(f, fs)
    row[#row + 1] = f
    return f, fs
end

local HELP_KEYS = {
    "EM_HELP_DRAG", "EM_HELP_NUDGE", "EM_HELP_POPUP", "EM_HELP_SNAP", "EM_HELP_OPACITY",
    "EM_HELP_PREVIEW", "EM_HELP_UNDO", "EM_HELP_CDM", "EM_HELP_COPYTO", "EM_HELP_EXIT",
    "EM_HELP_TITLE", "EM_TOUR_START", "EM_TOUR_NEXT", "EM_TOUR_BACK", "EM_TOUR_SKIP",
    "EM_TOUR_DONE", "EM_TOUR_STEP", "EM_HELP_BTN", "EM_HELP_BTN_TIP", "EM_HINT_NONE",
    "EM_HINT_SELECTED", "EM_HINT_POPUP", "EM_SELECT_FIRST", "EM_PREVIEW_ON", "EM_PREVIEW_OFF",
    "EM_AURAS_ON", "EM_AURAS_OFF", "EM_SNAP_ON", "EM_SNAP_OFF", "EM_GRID_ON", "EM_GRID_OFF",
    "EM_CDM_ON", "EM_CDM_OFF", "EM_ANCHOR_SET", "Drag & Move", "Arrow Key Nudge",
    "Click Popup", "Grid & Snap", "Background Opacity", "Preview & Auras", "Undo / Cancel All",
    "CDM & Anchor", "Copy Settings", "Exit Edit Mode", "Discard", "Edit Mode", "Groups", "Frames",
    "Position", "Toolbar position", "Top", "Bottom", "Left", "Right", "Snap to screen edge",
    "Auto-hide", "Edge offset", "Drag the six-dot handle to move and dock the toolbar.",
    "Dock the Edit Mode toolbar at any screen edge.",
    "Pick the frame or group to edit, including ones hidden behind another frame.",
    "Choose which frame's settings page to open.",
    "Selected", "No frames to select",
}

local EN_HELP = (type(MSUF) == "table" and MSUF.LocaleRegistry and MSUF.LocaleRegistry.enUS) or {}

function HelpText(key)
    if type(key) ~= "string" then return key end
    local value = type(L) == "table" and rawget(L, key) or nil
    if type(value) == "string" and value ~= "" and value ~= key then
        return value
    end
    value = EN_HELP[key]
    return (type(value) == "string" and value ~= "" and value ~= key) and value or key
end

--- Seed the current locale table for old callers, but all Help/Tour rendering
--- uses HelpText() so MSUF.SetLocale() rebuilds cannot expose raw keys again.
do
    for _, key in ipairs(HELP_KEYS) do
        local text = EN_HELP[key]
        local current = rawget(L, key)
        if type(text) == "string" and (current == nil or current == key) then L[key] = text end
    end
end

--- The toolbar is a cold, event-driven workspace preference.  It deliberately
--- lives outside the active unit-frame profile so switching/importing profiles
--- cannot move the user's Edit Mode chrome around the screen.
local function DockCharKey()
    local fn = rawget(_G, "MSUF_GetCharKey")
    if type(fn) == "function" then
        local key = fn()
        if type(key) == "string" and key ~= "" then return key end
    end
    local name = (_G.UnitName and _G.UnitName("player")) or "Unknown"
    local realm = (_G.GetRealmName and _G.GetRealmName()) or "Realm"
    return tostring(name) .. "-" .. tostring(realm)
end

local function ClampDockNumber(value, low, high, fallback)
    value = tonumber(value)
    if not value then value = fallback end
    if value < low then return low end
    if value > high then return high end
    return value
end

local function EnsureDockState()
    if DockUI.state then return DockUI.state end
    ExportPublic("MSUF_GlobalDB", type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or {})
    local global = _G.MSUF_GlobalDB
    global.char = type(global.char) == "table" and global.char or {}
    local charKey = DockCharKey()
    local charDB = type(global.char[charKey]) == "table" and global.char[charKey] or {}
    global.char[charKey] = charDB
    local state = type(charDB.editModeHUDState) == "table" and charDB.editModeHUDState or {}
    charDB.editModeHUDState = state
    state.version = 1
    state.dock = DOCK_ALLOWED[state.dock] and state.dock or "TOP"
    state.snapToEdge = state.snapToEdge ~= false
    state.autoHide = state.autoHide == true
    state.edgeOffset = ClampDockNumber(state.edgeOffset, 0, 64, DOCK_EDGE_DEFAULT)
    state.freeX = ClampDockNumber(state.freeX, -4096, 4096, 0)
    state.freeY = ClampDockNumber(state.freeY, -4096, 4096, 0)
    DockUI.state = state
    return state
end

local function IsVerticalDock(dock)
    return dock == "LEFT" or dock == "RIGHT"
end

local function DockContextLabel(key)
    if key == nil then key = CurrentSelectionKey() end
    if GROUP_KEY_TO_KIND[key] then return HelpText("Groups") end
    if key and LABEL_BY_KEY[key] then return HelpText(LABEL_BY_KEY[key]) end
    return HelpText("Frames")
end

local function RefreshDockContext(key)
    local btn = DockUI.contextBtn
    if not (btn and btn._label) then return end
    local text = DockContextLabel(key)
    if btn._msufContextText == text then return end
    btn._msufContextText = text
    btn._label:SetText(text)
end

--- Frame picker
---
--- Clicking a mover is the normal way to select something, but a frame that sits
--- underneath another one cannot be clicked at all - which leaves the user with no
--- way to move it back out. The toolbar's context button therefore opens this list
--- of every placeable element, so selection never depends on hitting a mover.
local PICKER_ROW_H = 24
local PICKER_WIDTH = 190

--- Rows for the picker: everything the Edit Mode registry can currently place.
--- Elements without a live frame have no mover on screen, so listing them would
--- offer a selection that cannot go anywhere.
local function FramePickerRows()
    local registry = EM2.Registry
    local rows = {}
    if not (registry and registry.Order) then return rows end
    local selected = CurrentSelectionKey()
    local keys = registry.Order()
    for i = 1, #keys do
        local key = keys[i]
        local cfg = registry.Get and registry.Get(key)
        local frame = cfg and cfg.getFrame and cfg.getFrame()
        local enabled = not (cfg and cfg.isEnabled) or cfg.isEnabled() ~= false
        if cfg and frame and enabled then
            rows[#rows + 1] = {
                key = key,
                label = HelpText(cfg.label or LABEL_BY_KEY[key] or key),
                selected = key == selected,
            }
        end
    end
    return rows
end

local function SelectFrameFromPicker(key)
    if BlockHUDConfigLocked() then return end
    if not key then return end
    if EM2.State and EM2.State.SetUnitKey then EM2.State.SetUnitKey(key) end
    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(key, nil, nil, { source = "hud-picker" })
    end
    --- Anchoring to the mover puts the popup next to the frame it edits, exactly
    --- like clicking the mover would.
    local mover = EM2.Movers and EM2.Movers.Get and EM2.Movers.Get(key)
    if EM2.Popups and EM2.Popups.Open then EM2.Popups.Open(key, mover) end
    if EM2.Focus and EM2.Focus.Pulse then
        EM2.Focus.Pulse(key, "frame", nil, { source = "hud-picker", duration = 0.32 })
    end
    local cfg = EM2.Registry and EM2.Registry.Get and EM2.Registry.Get(key) or nil
    HUD.SetStatus(HelpText("Selected") .. " " .. HelpText((cfg and cfg.label) or LABEL_BY_KEY[key] or key), "ok")
    HUD.RefreshControls()
end

--- The inspector row's picker: jump straight into a frame's settings page and do
--- nothing else. No mover popup, no pulse - this is pure menu navigation, which is
--- what the row's chevron has always advertised.
local function OpenSettingsForKey(key)
    if BlockHUDConfigLocked() then return end
    if not key then return end
    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(key, nil, nil, { source = "hud-menu-picker", openSettings = true })
    end
    local opener = (EM2.Focus and EM2.Focus.OpenFullSettings) or _G.MSUF_EM2_OpenFocusSettings
    if type(opener) == "function" and opener() then
        HUD.SetStatus(HelpText("Opened settings"), "ok")
    else
        HUD.SetStatus(HelpText("Settings unavailable"), "warn")
    end
    HUD.RefreshControls()
end

local function PositionFramePicker(picker, btn)
    picker:ClearAllPoints()
    local dock = EnsureDockState().dock
    if dock == "BOTTOM" then
        picker:SetPoint("BOTTOM", btn, "TOP", 0, 4)
    elseif dock == "LEFT" then
        picker:SetPoint("TOPLEFT", btn, "TOPRIGHT", 6, 0)
    elseif dock == "RIGHT" then
        picker:SetPoint("TOPRIGHT", btn, "TOPLEFT", -6, 0)
    else
        picker:SetPoint("TOP", btn, "BOTTOM", 0, -4)
    end
end

--- One list frame serves both dropdowns; the owning button and the action to run
--- are set per open, so the toolbar picker and the inspector menu picker cannot be
--- on screen at once and share all chrome.
local function EnsureFramePicker()
    if DockUI.framePicker then return DockUI.framePicker end
    local picker = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    picker:SetFrameStrata("TOOLTIP")
    picker:SetFrameLevel(1300)
    picker:SetClampedToScreen(true)
    picker:EnableMouse(true)
    picker:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1,
                         insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    picker:SetBackdropColor(TH.r1Bg[1], TH.r1Bg[2], TH.r1Bg[3], 0.98)
    picker:SetBackdropBorderColor(TH.edge[1], TH.edge[2], TH.edge[3], 0.90)
    picker:Hide()
    picker._rows = {}
    --- Close once the pointer has left both the button and the list, the same
    --- forgiving behaviour the quick popups use for their small menus.
    picker:SetScript("OnUpdate", function(self)
        if not self:IsShown() then return end
        local owner = self._owner
        if (owner and owner:IsMouseOver()) or self:IsMouseOver() then
            self._closeAt = nil
        elseif not self._closeAt then
            self._closeAt = GetTime() + 0.4
        elseif GetTime() >= self._closeAt then
            self:Hide()
        end
    end)
    DockUI.framePicker = picker
    return picker
end

local function BuildFramePickerRows(picker)
    local rows = FramePickerRows()
    local widgets = picker._rows
    for i = 1, #rows do
        local data = rows[i]
        local item = widgets[i]
        if not item then
            item = CreateFrame("Button", nil, picker)
            item:SetSize(PICKER_WIDTH - 6, PICKER_ROW_H)
            item._bg = item:CreateTexture(nil, "BACKGROUND")
            item._bg:SetAllPoints()
            item._fs = MakeFS(item, "caption", TH.textR, TH.textG, TH.textB, 0.94)
            --- Both edges anchored plus no wrapping: a long localized label is
            --- truncated inside its row instead of spilling out of the list.
            item._fs:SetPoint("LEFT", item, "LEFT", 9, 0)
            item._fs:SetPoint("RIGHT", item, "RIGHT", -8, 0)
            item._fs:SetJustifyH("LEFT")
            item._fs:SetWordWrap(false)
            local hl = item:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.18)
            item:SetScript("OnClick", function(self)
                local action = picker._onPick
                picker:Hide()
                if action then action(self._msufKey) end
            end)
            widgets[i] = item
        end
        item:SetPoint("TOPLEFT", picker, "TOPLEFT", 3, -(3 + (i - 1) * PICKER_ROW_H))
        item._msufKey = data.key
        item._fs:SetText(data.label)
        if data.selected then
            item._bg:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.16)
            item._fs:SetTextColor(TH.onR, TH.onG, TH.onB, 1)
        else
            item._bg:SetColorTexture(0, 0, 0, 0)
            item._fs:SetTextColor(TH.textR, TH.textG, TH.textB, 0.94)
        end
        item:Show()
    end
    for i = #rows + 1, #widgets do widgets[i]:Hide() end
    picker:SetSize(PICKER_WIDTH, math.max(PICKER_ROW_H, #rows * PICKER_ROW_H) + 6)
    return #rows
end

local function TogglePicker(owner, onPick)
    if not owner then return end
    local picker = EnsureFramePicker()
    --- Clicking the button that already owns the open list closes it; clicking the
    --- other one hands the list over instead of stacking a second menu.
    if picker:IsShown() then
        picker:Hide()
        if picker._owner == owner then return end
    end
    picker._owner, picker._onPick = owner, onPick
    if BuildFramePickerRows(picker) == 0 then
        HUD.SetStatus(HelpText("No frames to select"), "warn")
        return
    end
    picker._closeAt = nil
    PositionFramePicker(picker, owner)
    picker:Show()
end

--- Deliberately reached through HUD rather than file-scope locals: the toolbar
--- builder and the refresh path are both close to the Lua 5.1 upvalue ceiling, and
--- every new local they capture counts against it.
function HUD.ToggleFramePicker()
    TogglePicker(DockUI.contextBtn, SelectFrameFromPicker)
end

--- The inspector row's chevron: choose which settings page to open, nothing else.
function HUD.ToggleMenuPicker()
    TogglePicker(DockUI.inspectorSelection, OpenSettingsForKey)
end

--- Re-renders the open list so its highlight follows the current selection.
function HUD.RefreshFramePicker()
    local picker = DockUI.framePicker
    if picker and picker:IsShown() then BuildFramePickerRows(picker) end
end

function HUD.CloseFramePicker()
    if DockUI.framePicker then DockUI.framePicker:Hide() end
end

local function ApplyButtonRole(btn, role)
    if not btn then return end
    local ui = SharedUI()
    if ui and ui.ApplyButtonRole then
        ui.ApplyButtonRole(btn, role)
        return
    end
    local menu = type(MSUF) == "table" and MSUF.MSUF2 or nil
    local theme = menu and menu.Theme
    if theme and theme.ApplyButtonRole then theme.ApplyButtonRole(btn, role) end
end

local function LayoutClusterHorizontal(cluster)
    if not (cluster and type(cluster._dockItems) == "table") then return 0 end
    local items = cluster._dockItems
    local x = CLUSTER_PAD_X
    local visibleCount = 0
    if cluster._clusterLabel then cluster._clusterLabel:Show() end
    for _, item in ipairs(items) do
        item:Show()
        item:ClearAllPoints()
        local width = item._dockHorizontalWidth or item:GetWidth()
        local height = item._dockHorizontalHeight or item:GetHeight()
        if item.SetSize then item:SetSize(width, height) end
        local slotWidth = item._isSep and SEP_W or width
        if item._isSep then
            item:SetSize(1, height - 8)
            item:SetPoint("LEFT", cluster, "LEFT", x + slotWidth * 0.5, cluster._dockHorizontalYOffset or 0)
        else
            item:SetPoint("LEFT", cluster, "LEFT", x, cluster._dockHorizontalYOffset or 0)
        end
        x = x + slotWidth + BTN_GAP
        visibleCount = visibleCount + 1
    end
    if visibleCount > 0 then x = x - BTN_GAP end
    local width = x + CLUSTER_PAD_X
    cluster:SetSize(width, cluster._dockHorizontalHeight or CLUSTER_H)
    return width
end

local function LayoutClusterVertical(cluster)
    if not (cluster and type(cluster._dockItems) == "table") then return 0 end
    local items = cluster._dockItems
    local y = cluster._clusterLabel and -17 or -6
    local visibleCount = 0
    if cluster._clusterLabel then
        cluster._clusterLabel:Show()
        cluster._clusterLabel:ClearAllPoints()
        cluster._clusterLabel:SetPoint("TOP", cluster, "TOP", 0, -4)
    end
    for _, item in ipairs(items) do
        item:ClearAllPoints()
        if item._isSep then
            item:Hide()
        else
            item:Show()
            local height = item._dockHorizontalHeight or item:GetHeight()
            item:SetSize(58, height)
            item:SetPoint("TOP", cluster, "TOP", 0, y)
            y = y - height - BTN_GAP
            visibleCount = visibleCount + 1
        end
    end
    if visibleCount > 0 then y = y + BTN_GAP end
    local height = max(34, -y + 6)
    cluster:SetSize(66, height)
    return height
end

local function LayoutClusterRow(container, clusters)
    local total = 0
    for i, cluster in ipairs(clusters or {}) do
        total = total + LayoutClusterHorizontal(cluster)
        if i < #clusters then total = total + CLUSTER_GAP end
    end
    container:SetSize(max(1, total), CLUSTER_H)
    local x = -total * 0.5
    for _, cluster in ipairs(clusters or {}) do
        cluster:ClearAllPoints()
        cluster:SetPoint("LEFT", container, "CENTER", x, 0)
        x = x + cluster:GetWidth() + CLUSTER_GAP
    end
    return total
end

local function LayoutClusterColumn(container, clusters)
    local total = 0
    for i, cluster in ipairs(clusters or {}) do
        total = total + LayoutClusterVertical(cluster)
        if i < #clusters then total = total + CLUSTER_GAP end
    end
    container:SetSize(66, max(1, total))
    local y = total * 0.5
    for _, cluster in ipairs(clusters or {}) do
        cluster:ClearAllPoints()
        cluster:SetPoint("TOP", container, "CENTER", 0, y)
        y = y - cluster:GetHeight() - CLUSTER_GAP
    end
    return total
end

local function DockMouseOver(frame)
    return frame and frame.IsShown and frame:IsShown() and frame.IsMouseOver and frame:IsMouseOver()
end

local autoHideGeneration = 0
function DockUI.ScheduleLayoutSettle()
    DockUI.layoutGeneration = (DockUI.layoutGeneration or 0) + 1
    local generation = DockUI.layoutGeneration
    C_Timer.After(0, function()
        if generation ~= DockUI.layoutGeneration then return end
        if not (hudFrame and hudFrame:IsShown()) then return end
        if InCombatLockdown and InCombatLockdown() then return end
        --- The entry slide owns the anchor from the moment it is armed until it
        --- lands; FinishDockIntro re-arms this settle so the measured widths
        --- still get applied.
        if DockUI.introPlaying or DockUI.introArmed then return end
        ApplyDockLayout()
    end)
end

SetDockExpanded = function(expanded)
    if not hudFrame then return end
    local state = EnsureDockState()
    --- Both dropdowns hang off UIParent, so the pointer sitting in one of them no
    --- longer counts as hovering the toolbar. Without this the dock fades out from
    --- under an open list.
    if not state.autoHide or expanded
        or DockMouseOver(DockUI.positionPopup) or DockMouseOver(DockUI.framePicker)
    then
        hudFrame:SetAlpha(1)
        if row2Frame and hudFrame:IsShown() then row2Frame:Show() end
    else
        hudFrame:SetAlpha(0.12)
        if row2Frame then row2Frame:Hide() end
    end
end

ScheduleDockAutoHide = function()
    autoHideGeneration = autoHideGeneration + 1
    local generation = autoHideGeneration
    if not (hudFrame and hudFrame:IsShown()) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local state = EnsureDockState()
    if not state.autoHide then SetDockExpanded(true); return end
    C_Timer.After(0.45, function()
        if generation ~= autoHideGeneration then return end
        if not (hudFrame and hudFrame:IsShown()) then return end
        if InCombatLockdown and InCombatLockdown() then return end
        if DockMouseOver(hudFrame) or DockMouseOver(row2Frame)
            or DockMouseOver(DockUI.positionPopup) or DockMouseOver(DockUI.framePicker)
        then
            return
        end
        SetDockExpanded(false)
    end)
end

local function AttachDockHover(frame)
    if not (frame and frame.HookScript) or frame._msufDockHoverHooked then return end
    frame._msufDockHoverHooked = true
    frame:HookScript("OnEnter", function()
        autoHideGeneration = autoHideGeneration + 1
        SetDockExpanded(true)
    end)
    frame:HookScript("OnLeave", function() ScheduleDockAutoHide() end)
end

--- Dock anchor and entry slide
---
--- One authority places the toolbar against its screen edge.  The entry slide
--- reuses it with a displaced start offset, so the animation can never drift
--- away from the layout geometry - and FREE (a dragged, undocked bar) keeps its
--- own centre offsets.
DockUI.introTravel = 34
DockUI.introDuration = 0.34

DockUI.AnchorDock = function(dock, edge, offsetX, offsetY)
    if not (hudFrame and UIParent) then return end
    offsetX = tonumber(offsetX) or 0
    offsetY = tonumber(offsetY) or 0
    edge = tonumber(edge) or 0
    hudFrame:ClearAllPoints()
    if dock == "LEFT" then
        hudFrame:SetPoint("LEFT", UIParent, "LEFT", edge + offsetX, offsetY)
    elseif dock == "RIGHT" then
        hudFrame:SetPoint("RIGHT", UIParent, "RIGHT", -edge + offsetX, offsetY)
    elseif dock == "BOTTOM" then
        hudFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", offsetX, edge + offsetY)
    elseif dock == "FREE" then
        local state = EnsureDockState()
        hudFrame:SetPoint("CENTER", UIParent, "CENTER", state.freeX + offsetX, state.freeY + offsetY)
    else
        hudFrame:SetPoint("TOP", UIParent, "TOP", offsetX, -edge + offsetY)
    end
end

--- Where the bar starts before sliding home: outward, past its docked edge.
--- An undocked bar has no edge to come from and only fades.
DockUI.IntroOffset = function(dock)
    local travel = tonumber(DockUI.introTravel) or 0
    if dock == "BOTTOM" then return 0, -travel end
    if dock == "LEFT" then return -travel, 0 end
    if dock == "RIGHT" then return travel, 0 end
    if dock == "FREE" then return 0, 0 end
    return 0, travel
end

--- Restores the toolbar's own anchor, clamping and alpha authority.  Kept
--- idempotent because both OnFinished and an explicit Stop() land here.
DockUI.FinishDockIntro = function()
    if not DockUI.introPlaying then return end
    DockUI.introPlaying = nil
    if not hudFrame then return end
    if DockUI.introUnclamped then
        DockUI.introUnclamped = nil
        hudFrame:SetClampedToScreen(true)
    end
    local state = EnsureDockState()
    DockUI.AnchorDock(state.dock, state.edgeOffset)
    if hudFrame:IsShown() then
        SetDockExpanded(true)
        ScheduleDockAutoHide()
        --- The settle relayout skips itself while the slide owns the anchor,
        --- so re-arm it now that the measured widths matter again.
        DockUI.ScheduleLayoutSettle()
    end
end

DockUI.StopDockIntro = function()
    DockUI.introArmed = nil
    local group = DockUI.introGroup
    if group and DockUI.introPlaying then group:Stop() end
    DockUI.FinishDockIntro()
end

--- The toolbar fades in from whichever screen edge it is docked to.  The whole
--- move is one C-side animation group: no OnUpdate, no per-frame Lua, and no
--- cost at all once it has landed.  Edit Mode exits on PLAYER_REGEN_DISABLED,
--- so none of this can exist during combat.
DockUI.PlayDockIntro = function()
    local group = DockUI.introGroup
    if not (group and hudFrame and hudFrame:IsShown()) then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    local db = _G.MSUF_DB
    local general = type(db) == "table" and db.general or nil
    if type(general) == "table" and (general.reduceMotion == true or general.reducedMotion == true) then
        return false
    end
    local state = EnsureDockState()
    local offsetX, offsetY = DockUI.IntroOffset(state.dock)
    if DockUI.introPlaying then group:Stop() end
    DockUI.introPlaying = true
    --- Clamping is derived from the anchor, so a start point past the screen
    --- edge would be pulled back before the slide could play.
    if not DockUI.introUnclamped then
        DockUI.introUnclamped = true
        hudFrame:SetClampedToScreen(false)
    end
    DockUI.AnchorDock(state.dock, state.edgeOffset, offsetX, offsetY)
    if DockUI.introSlide then DockUI.introSlide:SetOffset(-offsetX, -offsetY) end
    group:Play()
    return true
end

--- Consumers add their own controls to the toolbar *after* HUD.Show returns -
--- the group-frame bridge wraps it, and the Dominos/Danders slots fill in the
--- same way.  A child anchored into an already-moving parent resolves against
--- the in-flight position and then drifts, so the slide waits one frame until
--- the bar is fully assembled.  Cost is one zero-delay timer per Edit Mode
--- entry, and combat cannot reach any of it.
DockUI.ArmDockIntro = function()
    if not (DockUI.introGroup and hudFrame and hudFrame:IsShown()) then return false end
    if not (C_Timer and C_Timer.After) then return DockUI.PlayDockIntro() end
    DockUI.introArmed = (DockUI.introArmed or 0) + 1
    local token = DockUI.introArmed
    C_Timer.After(0, function()
        if token ~= DockUI.introArmed then return end
        DockUI.introArmed = nil
        DockUI.PlayDockIntro()
    end)
    return true
end

--- The full guided tour now lives inside the native MSUF menu.  Keep this
--- bridge late-bound because Menu2 can be installed after the Edit Mode HUD.
local function ResolveMenu2()
    local menu = type(MSUF) == "table" and MSUF.MSUF2 or nil
    if type(menu) ~= "table" then menu = _G.MSUF2 end
    return type(menu) == "table" and menu or nil
end

local function HideLegacyFrame(frame)
    if frame and type(frame.Hide) == "function" then frame:Hide() end
end

local function CleanupLegacyTourFrames()
    HideLegacyFrame(_G.MSUF_EM2_TutorialPanel)
    HideLegacyFrame(_G.MSUF_EM2_TourCard)
end

local function OpenMenuGuidedTourAtEditMode()
    CleanupLegacyTourFrames()
    guidedTourBridgeRequested = false

    local menu = ResolveMenu2()
    local menuOpened = false
    if menu and type(menu.Open) == "function" then
        local ok, result = InvokeHUDOptional(menu.Open)
        menuOpened = ok and result ~= false
    elseif type(_G.MSUF2_Open) == "function" then
        local ok, result = InvokeHUDOptional(_G.MSUF2_Open)
        menuOpened = ok and result ~= false
    end

    -- Resolve again after opening: lazy menu installation may have populated
    -- MSUF.MSUF2 during the call above.
    menu = ResolveMenu2()
    local openStage = menu and menu.OpenGuidedTourAtStage
    if type(openStage) == "function" then
        local ok, result = InvokeHUDOptional(openStage, "edit_mode")
        if ok and result ~= false then
            guidedTourBridgeRequested = true
            return true
        end
    end
    return menuOpened
end

--- The former floating Help reference panel has intentionally been removed.
--- Help now enters the complete, menu-native guided tour above.

function HUD.TourStep(idx)
    -- Legacy callers may still supply an overlay step number.  The menu tour
    -- owns its own progress and maps this entry to its Edit Mode stage.
    return OpenMenuGuidedTourAtEditMode()
end

function HUD.StartTour()
    return OpenMenuGuidedTourAtEditMode()
end

function HUD.StopTour()
    CleanupLegacyTourFrames()
    guidedTourBridgeRequested = false
    return true
end

-- Readable lifecycle helpers for non-visual controllers (for example the
-- load-on-demand Assistant).  Keep these on the existing HUD owner so callers
-- never need to retain HUD frames or reproduce button click side effects.
function HUD.IsHelpShown()
    return guidedTourBridgeRequested
end

function HUD.SetHelpShown(shown)
    shown = shown == true
    if shown then
        return OpenMenuGuidedTourAtEditMode()
    end
    HUD.StopTour()
    return true
end

function HUD.IsTourActive()
    return guidedTourBridgeRequested
end

function HUD.GetTourStep()
    return HUD.IsTourActive() and 1 or 0
end

function HUD.SetTourActive(active)
    if active == true then
        return HUD.StartTour()
    end
    HUD.StopTour()
    return true
end

function HUD.SetTourStep(step)
    return OpenMenuGuidedTourAtEditMode()
end

local function UpdateDockSwitch(row, enabled)
    if not row then return end
    row._enabled = enabled and true or false
    local r, g, b = TH.onR, TH.onG, TH.onB
    if row._track then
        if enabled then row._track:SetColorTexture(r * 0.42, g * 0.42, b * 0.42, 0.98)
        else row._track:SetColorTexture(0.16, 0.19, 0.26, 0.98) end
    end
    if row._knob then
        row._knob:ClearAllPoints()
        row._knob:SetPoint(enabled and "RIGHT" or "LEFT", row, enabled and "RIGHT" or "LEFT", enabled and -3 or 3, 0)
        row._knob:SetColorTexture(enabled and 0.92 or 0.66, enabled and 0.97 or 0.70, enabled and 1.00 or 0.76, 1)
    end
end

local function CreateDockSwitch(parent, labelText, y, stateKey)
    local label = MakeFS(parent, "caption", TH.textR, TH.textG, TH.textB, 0.92)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, y)
    label:SetText(HelpText(labelText))
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(40, 20)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, y + 3)
    row:RegisterForClicks("LeftButtonUp")
    local track = row:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    local knob = row:CreateTexture(nil, "ARTWORK")
    knob:SetSize(14, 14)
    row._track, row._knob = track, knob
    row:SetScript("OnClick", function()
        local state = EnsureDockState()
        state[stateKey] = not state[stateKey]
        if stateKey == "autoHide" then SetDockExpanded(true) end
        if RefreshPositionPopup then RefreshPositionPopup() end
        if stateKey == "autoHide" then ScheduleDockAutoHide() end
    end)
    AttachDockHover(row)
    return row
end

local function PlacePositionPopup()
    local positionPopup, positionBtn = DockUI.positionPopup, DockUI.positionBtn
    if not (positionPopup and positionBtn) then return end
    local dock = EnsureDockState().dock
    positionPopup:ClearAllPoints()
    if dock == "BOTTOM" then
        positionPopup:SetPoint("BOTTOM", positionBtn, "TOP", 0, 10)
    elseif dock == "LEFT" then
        positionPopup:SetPoint("LEFT", positionBtn, "RIGHT", 10, 0)
    elseif dock == "RIGHT" then
        positionPopup:SetPoint("RIGHT", positionBtn, "LEFT", -10, 0)
    else
        positionPopup:SetPoint("TOP", positionBtn, "BOTTOM", 0, -10)
    end
end

local function EnsurePositionPopup()
    if DockUI.positionPopup then return DockUI.positionPopup end
    local popup = CreateFrame("Frame", "MSUF_EM2_HUD_PositionPopup", UIParent, "BackdropTemplate")
    popup:SetSize(356, 326)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetFrameLevel(1300)
    popup:SetClampedToScreen(true)
    popup:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1} })
    popup:SetBackdropColor(TH.r1Bg[1], TH.r1Bg[2], TH.r1Bg[3], 0.985)
    popup:SetBackdropBorderColor(TH.onR, TH.onG, TH.onB, 0.62)
    ApplyHUDMaterial(popup, "popup")
    popup:EnableMouse(true)
    popup:Hide()
    DockUI.positionPopup = popup

    local heading = MakeFS(popup, "body", TH.textR, TH.textG, TH.textB, 1)
    heading:SetPoint("TOPLEFT", popup, "TOPLEFT", 18, -15)
    heading:SetText(HelpText("Toolbar position"))

    local monitor = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    monitor:SetSize(170, 96)
    monitor:SetPoint("TOPLEFT", popup, "TOPLEFT", 18, -46)
    monitor:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=2,right=2,top=2,bottom=2} })
    monitor:SetBackdropColor(0.025, 0.055, 0.090, 0.96)
    monitor:SetBackdropBorderColor(TH.edge[1], TH.edge[2], TH.edge[3], 0.85)
    local screen = monitor:CreateTexture(nil, "BACKGROUND", nil, 1)
    screen:SetPoint("TOPLEFT", monitor, "TOPLEFT", 10, -10)
    screen:SetPoint("BOTTOMRIGHT", monitor, "BOTTOMRIGHT", -10, 10)
    screen:SetColorTexture(0.07, 0.12, 0.18, 0.96)
    popup._dockPreviewDots = {}
    local dotAnchors = {
        TOP = { "TOP", monitor, "TOP", 0, -6 }, BOTTOM = { "BOTTOM", monitor, "BOTTOM", 0, 6 },
        LEFT = { "LEFT", monitor, "LEFT", 6, 0 }, RIGHT = { "RIGHT", monitor, "RIGHT", -6, 0 },
    }
    for dock, point in pairs(dotAnchors) do
        local dot = monitor:CreateTexture(nil, "OVERLAY")
        dot:SetSize(10, 10)
        dot:SetPoint(unpack(point))
        dot:SetColorTexture(0.45, 0.53, 0.64, 0.92)
        popup._dockPreviewDots[dock] = dot
    end

    popup._dockButtons = {}
    local choices = { { "TOP", "Top" }, { "BOTTOM", "Bottom" }, { "LEFT", "Left" }, { "RIGHT", "Right" } }
    for i, choice in ipairs(choices) do
        local dock, label = choice[1], choice[2]
        local button = MakeBtn(popup, label, 122, 26, "caption", function()
            local state = EnsureDockState()
            state.dock = dock
            state.snapToEdge = true
            if ApplyDockLayout then ApplyDockLayout(); DockUI.ScheduleLayoutSettle() end
            if RefreshPositionPopup then RefreshPositionPopup() end
        end)
        button:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -18, -43 - (i - 1) * 30)
        popup._dockButtons[dock] = button
        AttachDockHover(button)
    end

    local divider = popup:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", popup, "TOPLEFT", 18, -158)
    divider:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -18, -158)
    divider:SetColorTexture(TH.edge[1], TH.edge[2], TH.edge[3], 0.52)

    popup._snapSwitch = CreateDockSwitch(popup, "Snap to screen edge", -178, "snapToEdge")
    popup._autoHideSwitch = CreateDockSwitch(popup, "Auto-hide", -211, "autoHide")

    local offsetLabel = MakeFS(popup, "caption", TH.textR, TH.textG, TH.textB, 0.92)
    offsetLabel:SetPoint("TOPLEFT", popup, "TOPLEFT", 18, -249)
    offsetLabel:SetText(HelpText("Edge offset"))
    local minus = MakeBtn(popup, "-", 28, 24, "body", function()
        local state = EnsureDockState()
        state.edgeOffset = ClampDockNumber(state.edgeOffset - 2, 0, 64, DOCK_EDGE_DEFAULT)
        if ApplyDockLayout then ApplyDockLayout(); DockUI.ScheduleLayoutSettle() end
        RefreshPositionPopup()
    end)
    minus:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -102, -243)
    local plus = MakeBtn(popup, "+", 28, 24, "body", function()
        local state = EnsureDockState()
        state.edgeOffset = ClampDockNumber(state.edgeOffset + 2, 0, 64, DOCK_EDGE_DEFAULT)
        if ApplyDockLayout then ApplyDockLayout(); DockUI.ScheduleLayoutSettle() end
        RefreshPositionPopup()
    end)
    plus:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -18, -243)
    local offsetValue = MakeFS(popup, "caption", TH.onR, TH.onG, TH.onB, 1)
    offsetValue:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -52, -249)
    offsetValue:SetWidth(46)
    offsetValue:SetJustifyH("CENTER")
    popup._offsetValue = offsetValue
    AttachDockHover(minus); AttachDockHover(plus)

    local dragHelp = MakeFS(popup, "micro", TH.mutedR, TH.mutedG, TH.mutedB, 0.76)
    dragHelp:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 18, 14)
    dragHelp:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -18, 14)
    dragHelp:SetJustifyH("LEFT")
    dragHelp:SetText(HelpText("Drag the six-dot handle to move and dock the toolbar."))

    DockUI.positionPopupEventFrame = CreateFrame("Frame")
    DockUI.positionPopupEventFrame:SetScript("OnEvent", function()
        C_Timer.After(0, function()
            local openPopup, button = DockUI.positionPopup, DockUI.positionBtn
            if openPopup and openPopup:IsShown()
                and not DockMouseOver(openPopup) and not DockMouseOver(button) then
                openPopup:Hide()
            end
        end)
    end)
    popup:SetScript("OnShow", function()
        PlacePositionPopup()
        RefreshPositionPopup()
        DockUI.positionPopupEventFrame:RegisterEvent("GLOBAL_MOUSE_DOWN")
        SetDockExpanded(true)
    end)
    popup:SetScript("OnHide", function()
        DockUI.positionPopupEventFrame:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        local button = DockUI.positionBtn
        if button and button.SetActive then button:SetActive(false) end
        ScheduleDockAutoHide()
    end)
    AttachDockHover(popup); AttachDockHover(monitor)
    return popup
end

RefreshPositionPopup = function()
    local positionPopup, positionBtn = DockUI.positionPopup, DockUI.positionBtn
    if not positionPopup then return end
    local state = EnsureDockState()
    for dock, button in pairs(positionPopup._dockButtons or {}) do
        if button.SetActive then button:SetActive(state.dock == dock) end
        local dot = positionPopup._dockPreviewDots and positionPopup._dockPreviewDots[dock]
        if dot then
            if state.dock == dock then dot:SetColorTexture(TH.onR, TH.onG, TH.onB, 1)
            else dot:SetColorTexture(0.45, 0.53, 0.64, 0.92) end
        end
    end
    UpdateDockSwitch(positionPopup._snapSwitch, state.snapToEdge)
    UpdateDockSwitch(positionPopup._autoHideSwitch, state.autoHide)
    if positionPopup._offsetValue then positionPopup._offsetValue:SetText(floor(state.edgeOffset + 0.5) .. " px") end
    if positionBtn and positionBtn.SetActive then positionBtn:SetActive(positionPopup:IsShown()) end
    PlacePositionPopup()
end

local function NearestDockEdge()
    if not (hudFrame and UIParent) then return "TOP" end
    local left, right = hudFrame:GetLeft(), hudFrame:GetRight()
    local top, bottom = hudFrame:GetTop(), hudFrame:GetBottom()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if not (left and right and top and bottom and width and height) then return "TOP" end
    local distances = { LEFT = left, RIGHT = width - right, TOP = height - top, BOTTOM = bottom }
    local nearest, best = "TOP", math.huge
    for dock, distance in pairs(distances) do
        distance = math.abs(tonumber(distance) or math.huge)
        if distance < best then nearest, best = dock, distance end
    end
    return nearest, best
end

local function CursorPositionInUIParent()
    if not (UIParent and UIParent.GetEffectiveScale and GetCursorPosition) then return nil, nil end
    local scale = tonumber(UIParent:GetEffectiveScale()) or 1
    if scale == 0 then scale = 1 end
    local x, y = GetCursorPosition()
    if not (x and y) then return nil, nil end
    return x / scale, y / scale
end

local function ClampDockDragOffset(offsetX, offsetY)
    local screenW = tonumber(UIParent and UIParent:GetWidth()) or 1920
    local screenH = tonumber(UIParent and UIParent:GetHeight()) or 1080
    local frameW = tonumber(hudFrame and hudFrame:GetWidth()) or DOCK_HORIZONTAL_W
    local frameH = tonumber(hudFrame and hudFrame:GetHeight()) or DOCK_HORIZONTAL_H
    local maxX = max(0, (screenW - frameW) * 0.5)
    local maxY = max(0, (screenH - frameH) * 0.5)
    return ClampDockNumber(offsetX, -maxX, maxX, 0), ClampDockNumber(offsetY, -maxY, maxY, 0)
end

local function UpdateDockDrag()
    local drag = DockUI.drag
    if not (drag and hudFrame and UIParent) then return end
    if (InCombatLockdown and InCombatLockdown())
        or (IsMouseButtonDown and not IsMouseButtonDown("LeftButton")) then
        StopDockDrag()
        return
    end
    local cursorX, cursorY = CursorPositionInUIParent()
    if not cursorX then return end
    local offsetX = drag.frameX + cursorX - drag.cursorX
    local offsetY = drag.frameY + cursorY - drag.cursorY
    offsetX, offsetY = ClampDockDragOffset(offsetX, offsetY)
    hudFrame:ClearAllPoints()
    hudFrame:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
end

StopDockDrag = function()
    if not hudFrame then return end
    DockUI.drag = nil
    hudFrame:SetScript("OnUpdate", nil)
    if DockUI.grip then DockUI.grip._dockDragging = nil end
    local state = EnsureDockState()
    local nearestDock, nearestDistance = NearestDockEdge()
    if state.snapToEdge and nearestDistance <= DOCK_SNAP_EDGE_PX then
        state.dock = nearestDock
    else
        local cx, cy = hudFrame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and cy and ux and uy then
            state.freeX = ClampDockNumber(cx - ux, -4096, 4096, 0)
            state.freeY = ClampDockNumber(cy - uy, -4096, 4096, 0)
        end
        state.dock = "FREE"
    end
    ApplyDockLayout()
    DockUI.ScheduleLayoutSettle()
    RefreshPositionPopup()
end

DockUI.BeginDrag = function()
    if not (hudFrame and UIParent) or (InCombatLockdown and InCombatLockdown()) then return false end
    --- Dragging measures the frame's live centre, so the slide has to land
    --- before the first sample is taken.
    DockUI.StopDockIntro()
    local cursorX, cursorY = CursorPositionInUIParent()
    local frameX, frameY = hudFrame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not (cursorX and cursorY and frameX and frameY and parentX and parentY) then return false end
    DockUI.drag = {
        cursorX = cursorX,
        cursorY = cursorY,
        frameX = frameX - parentX,
        frameY = frameY - parentY,
    }
    hudFrame:SetScript("OnUpdate", UpdateDockDrag)
    return true
end

ApplyDockLayout = function()
    if not (hudFrame and UIParent) then return end
    --- A relayout re-anchors the frame, and a running Translation renders
    --- relative to that anchor - so land the entry slide first, or the toolbar
    --- would jump by whatever travel was left.
    if DockUI.introPlaying then DockUI.StopDockIntro() end
    local state = EnsureDockState()
    local dock = state.dock
    local vertical = IsVerticalDock(dock)
    local screenW = tonumber(UIParent:GetWidth()) or 1920
    local screenH = tonumber(UIParent:GetHeight()) or 1080
    local edge = state.edgeOffset

    hudFrame:ClearAllPoints()
    DockUI.primaryContainer:ClearAllPoints()
    DockUI.historyContainer:ClearAllPoints()
    DockUI.grip:ClearAllPoints(); DockUI.logo:ClearAllPoints(); DockUI.title:ClearAllPoints(); DockUI.contextBtn:ClearAllPoints()
    helpBtn:ClearAllPoints(); cancelAllBtn:ClearAllPoints(); exitBtn:ClearAllPoints()
    row2Frame:ClearAllPoints()
    DockUI.inspectorSelection:ClearAllPoints(); hintFS:ClearAllPoints()
    for _, cell in ipairs(DockUI.inspectorMetrics or {}) do cell:ClearAllPoints() end
    if DockUI.primaryContainer.SetScale then DockUI.primaryContainer:SetScale(1) end
    if vertical then
        DockUI.inspectorCompact = true
        local historyHeight = LayoutClusterColumn(DockUI.historyContainer, DockUI.row2 or {})
        local primaryHeight = LayoutClusterColumn(DockUI.primaryContainer, DockUI.row1 or {})
        local totalHeight = min(screenH - 32, 38 + 34 + 32 + historyHeight + primaryHeight + 78)
        hudFrame:SetSize(DOCK_VERTICAL_W, max(390, totalHeight))
        DockUI.AnchorDock(dock, edge)

        DockUI.grip:SetSize(58, 16); DockUI.grip:SetPoint("TOP", hudFrame, "TOP", 0, -8)
        DockUI.logo:SetSize(30, 30); DockUI.logo:SetPoint("TOP", DockUI.grip, "BOTTOM", 0, -4)
        DockUI.title:Hide(); DockUI.contextBtn:Hide()
        helpBtn:SetSize(58, 26); helpBtn:SetPoint("TOP", DockUI.logo, "BOTTOM", 0, -5)
        DockUI.historyContainer:SetPoint("TOP", helpBtn, "BOTTOM", 0, -7)
        DockUI.primaryContainer:SetPoint("TOP", DockUI.historyContainer, "BOTTOM", 0, -7)
        exitBtn:SetSize(58, 28); exitBtn:SetPoint("BOTTOM", hudFrame, "BOTTOM", 0, 8)
        cancelAllBtn:SetSize(58, 28); cancelAllBtn:SetPoint("BOTTOM", exitBtn, "TOP", 0, 4)

        row2Frame:SetSize(320, 34)
        if dock == "LEFT" then row2Frame:SetPoint("LEFT", hudFrame, "RIGHT", 8, 0)
        else row2Frame:SetPoint("RIGHT", hudFrame, "LEFT", -8, 0) end
        DockUI.inspectorSelection:SetSize(145, 30)
        DockUI.inspectorSelection:SetPoint("LEFT", row2Frame, "LEFT", 4, 0)
        for _, cell in ipairs(DockUI.inspectorMetrics or {}) do cell:Hide() end
        hintFS:SetPoint("RIGHT", row2Frame, "RIGHT", -12, 0)
        hintFS:SetWidth(145)
    else
        DockUI.inspectorCompact = false
        LayoutClusterRow(DockUI.historyContainer, DockUI.row2 or {})
        LayoutClusterRow(DockUI.primaryContainer, DockUI.row1 or {})
        local targetWidth = DockUI.horizontalWidth or DOCK_HORIZONTAL_W
        local dockWidth = min(targetWidth, max(320, screenW - 32))
        hudFrame:SetSize(dockWidth, DOCK_HORIZONTAL_H)
        if dock == "FREE" then
            local maxFreeX = max(0, (screenW - dockWidth) * 0.5)
            local maxFreeY = max(0, (screenH - DOCK_HORIZONTAL_H) * 0.5)
            state.freeX = ClampDockNumber(state.freeX, -maxFreeX, maxFreeX, 0)
            state.freeY = ClampDockNumber(state.freeY, -maxFreeY, maxFreeY, 0)
        end
        DockUI.AnchorDock(dock, edge)

        DockUI.grip:SetSize(20, BTN_H); DockUI.grip:SetPoint("LEFT", hudFrame, "LEFT", 12, 0)
        DockUI.logo:SetSize(32, 32); DockUI.logo:SetPoint("LEFT", DockUI.grip, "RIGHT", 4, 0)
        local compact = dockWidth < 1080
        DockUI.title:SetShown(not compact)
        if not compact then DockUI.title:SetPoint("LEFT", DockUI.logo, "RIGHT", 7, 0) end
        DockUI.contextBtn:Show(); DockUI.contextBtn:SetSize(compact and 80 or 96, BTN_H)
        DockUI.contextBtn:SetPoint("LEFT", compact and DockUI.logo or DockUI.title, "RIGHT", 8, 0)
        helpBtn:SetSize(BTN_H, BTN_H); helpBtn:SetPoint("LEFT", DockUI.contextBtn, "RIGHT", 8, 0)
        DockUI.historyContainer:SetPoint("LEFT", helpBtn, "RIGHT", 8, 0)
        exitBtn:SetSize(80, BTN_H); exitBtn:SetPoint("RIGHT", hudFrame, "RIGHT", -16, -7)
        cancelAllBtn:SetSize(88, BTN_H); cancelAllBtn:SetPoint("RIGHT", exitBtn, "LEFT", -8, 0)

        -- Keep the task clusters physically anchored after History.  Merely
        -- centering a scaled container inside an estimated lane allowed its
        -- left edge to slide back over Redo even while the right edge passed
        -- the clipping check.  The relative LEFT anchor makes that collision
        -- impossible; the measured lane is used when WoW has resolved it and
        -- the deterministic width remains the safe first-pass fallback.
        local titleWidth = 0
        if not compact then
            titleWidth = DockUI.title.GetStringWidth and tonumber(DockUI.title:GetStringWidth()) or 72
            titleWidth = min(160, max(56, titleWidth or 72))
        end
        local contextWidth = compact and 80 or 96
        local historyWidth = max(1, tonumber(DockUI.historyContainer:GetWidth()) or 1)
        local laneLeft = 12 + 20 + 4 + 32
            + (compact and 8 or (7 + titleWidth + 8))
            + contextWidth + 8 + BTN_H + 8 + historyWidth
        local laneRight = dockWidth - 16 - 80 - 8 - 88
        local laneWidth = max(1, laneRight - laneLeft - 16)
        local measuredLeft = DockUI.historyContainer:GetRight()
        local measuredRight = cancelAllBtn:GetLeft()
        if measuredLeft and measuredRight and measuredRight > measuredLeft + 16 then
            laneWidth = measuredRight - measuredLeft - 16
        end
        local contentWidth = max(1, tonumber(DockUI.primaryContainer:GetWidth()) or 1)
        if DockUI.primaryContainer.SetScale then
            DockUI.primaryContainer:SetScale(min(1, laneWidth / contentWidth))
        end
        DockUI.primaryContainer:SetPoint("LEFT", DockUI.historyContainer, "RIGHT", 8, 0)

        local inspectorWidth = min(800, max(240, dockWidth - 80))
        row2Frame:SetSize(inspectorWidth, DockUI.inspectorH)
        if dock == "BOTTOM" then row2Frame:SetPoint("BOTTOM", hudFrame, "TOP", 0, 4)
        else row2Frame:SetPoint("TOP", hudFrame, "BOTTOM", 0, -4) end
        DockUI.inspectorSelection:SetSize(DockUI.inspectorLabelW, BTN_H)
        DockUI.inspectorSelection:SetPoint("LEFT", row2Frame, "LEFT", 4, 0)
        local previous = DockUI.inspectorSelection
        for _, cell in ipairs(DockUI.inspectorMetrics or {}) do
            cell:Show()
            cell:SetSize(DockUI.inspectorMetricW, BTN_H)
            cell:SetPoint("LEFT", previous, "RIGHT", 0, 0)
            previous = cell
        end
        hintFS:SetPoint("RIGHT", row2Frame, "RIGHT", -16, 0)
        hintFS:SetWidth(max(140, inspectorWidth - DockUI.inspectorLabelW - DockUI.inspectorMetricW * 4 - 36))
    end

    RefreshDockContext()
    PlacePositionPopup()
    if DockUI.positionPopup and DockUI.positionPopup:IsShown() then RefreshPositionPopup() end
    if hudFrame:IsShown() and HUD.RefreshControls then
        selectionLastText = nil
        HUD.RefreshControls(true)
    end
    SetDockExpanded(true)
    if state.autoHide then ScheduleDockAutoHide() end
end

function HUD.GetDockState()
    local state = EnsureDockState()
    return state.dock, state.snapToEdge, state.autoHide, state.edgeOffset, state.freeX, state.freeY
end

function HUD.SetDockPosition(dock)
    dock = type(dock) == "string" and dock:upper() or nil
    if not (dock and dock ~= "FREE" and DOCK_ALLOWED[dock]) then return false end
    local state = EnsureDockState()
    state.dock = dock
    state.snapToEdge = true
    if hudFrame then ApplyDockLayout(); DockUI.ScheduleLayoutSettle() end
    return true
end

function HUD.SetDockSnap(enabled)
    EnsureDockState().snapToEdge = enabled ~= false
    if DockUI.positionPopup then RefreshPositionPopup() end
    return true
end

function HUD.SetDockAutoHide(enabled)
    EnsureDockState().autoHide = enabled == true
    SetDockExpanded(true)
    if DockUI.positionPopup then RefreshPositionPopup() end
    if enabled == true then ScheduleDockAutoHide() end
    return true
end

function HUD.SetDockEdgeOffset(offset)
    local state = EnsureDockState()
    state.edgeOffset = ClampDockNumber(offset, 0, 64, DOCK_EDGE_DEFAULT)
    if hudFrame then ApplyDockLayout(); DockUI.ScheduleLayoutSettle() end
    if DockUI.positionPopup then RefreshPositionPopup() end
    return state.edgeOffset
end

local function EnsureHUD()
    if hudFrame then return false end
    RefreshHUDTheme()
    local db = _G.MSUF_DB
    local advancedHUD = db and db.general and db.general.hideAdvancedMenu == false
    DockUI.horizontalWidth = advancedHUD and 1480 or DOCK_HORIZONTAL_W

    --- Compact MSUF command dock.  The existing actions remain unchanged;
    --- only their chrome and cold-path layout are owned here.
    hudFrame = CreateFrame("Frame", "MSUF_EM2_HUD", UIParent, "BackdropTemplate")
    hudFrame:SetFrameStrata("TOOLTIP"); hudFrame:SetFrameLevel(1200)
    hudFrame:SetSize(DockUI.horizontalWidth, DOCK_HORIZONTAL_H)
    hudFrame:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=2,right=2,top=2,bottom=2} })
    hudFrame:SetBackdropColor(unpack(TH.r1Bg))
    hudFrame:SetBackdropBorderColor(TH.onR, TH.onG, TH.onB, 0.48)
    ApplyHUDMaterial(hudFrame, "status")
    hudFrame:SetMovable(true)
    hudFrame:SetClampedToScreen(true)
    hudFrame:EnableMouse(true); hudFrame:Hide()

    --- Entry slide: built once, driven entirely C-side.  Both animations share
    --- order 1 so the fade and the move run together.
    if hudFrame.CreateAnimationGroup then
        local intro = hudFrame:CreateAnimationGroup()
        local slide = intro:CreateAnimation("Translation")
        slide:SetDuration(DockUI.introDuration); slide:SetOrder(1); slide:SetSmoothing("OUT")
        local fade = intro:CreateAnimation("Alpha")
        fade:SetFromAlpha(0); fade:SetToAlpha(1)
        fade:SetDuration(DockUI.introDuration); fade:SetOrder(1); fade:SetSmoothing("OUT")
        intro:SetScript("OnFinished", function() DockUI.FinishDockIntro() end)
        intro:SetScript("OnStop", function() DockUI.FinishDockIntro() end)
        DockUI.introGroup = intro
        DockUI.introSlide = slide
    end

    DockUI.grip = CreateFrame("Button", nil, hudFrame)
    DockUI.grip:RegisterForDrag("LeftButton")
    DockUI.grip:SetScript("OnDragStart", function()
        if DockUI.positionPopup then DockUI.positionPopup:Hide() end
        SetDockExpanded(true)
        DockUI.grip._dockDragging = DockUI.BeginDrag() or nil
    end)
    DockUI.grip:SetScript("OnDragStop", function()
        if not DockUI.grip._dockDragging then return end
        DockUI.grip._dockDragging = nil
        StopDockDrag()
    end)
    for row = 0, 2 do
        for col = 0, 1 do
            local dot = DockUI.grip:CreateTexture(nil, "ARTWORK")
            dot:SetSize(2, 2)
            dot:SetPoint("CENTER", DockUI.grip, "CENTER", (col - 0.5) * 6, (row - 1) * 6)
            dot:SetColorTexture(TH.mutedR, TH.mutedG, TH.mutedB, 0.86)
        end
    end

    DockUI.logo = CreateFrame("Frame", nil, hudFrame)
    local logoTexture = DockUI.logo:CreateTexture(nil, "ARTWORK")
    logoTexture:SetAllPoints(DockUI.logo)
    logoTexture:SetTexture(MEDIA .. "MSUF_EditModeIcon.png")
    if logoTexture.SetSnapToPixelGrid then
        logoTexture:SetSnapToPixelGrid(false)
        logoTexture:SetTexelSnappingBias(0)
    end

    DockUI.title = MakeFS(hudFrame, "body", TH.onR, TH.onG, TH.onB, 1)
    DockUI.title:SetText(HelpText("Edit Mode"))

    DockUI.contextBtn = MakeBtn(hudFrame, "Groups", 96, BTN_H, "caption", function()
        HUD.ToggleFramePicker()
    end)
    if DockUI.contextBtn._label then
        DockUI.contextBtn._label:ClearAllPoints()
        DockUI.contextBtn._label:SetPoint("LEFT", DockUI.contextBtn, "LEFT", 9, 0)
        DockUI.contextBtn._label:SetPoint("RIGHT", DockUI.contextBtn, "RIGHT", -18, 0)
        DockUI.contextBtn._label:SetJustifyH("LEFT")
    end
    local contextChevron = MakeFS(DockUI.contextBtn, "micro", TH.mutedR, TH.mutedG, TH.mutedB, 0.88)
    contextChevron:SetPoint("RIGHT", DockUI.contextBtn, "RIGHT", -7, 1)
    contextChevron:SetText("v")
    SetTip(DockUI.contextBtn, "Pick the frame or group to edit, including ones hidden behind another frame.")

    --- Guided help remains available, but no longer dominates the toolbar.
    helpBtn = CreateFrame("Button", nil, hudFrame, "BackdropTemplate")
    helpBtn:SetSize(BTN_H, BTN_H)
    helpBtn:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1,
                          insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    helpBtn:SetBackdropColor(TH.onR * 0.20, TH.onG * 0.20, TH.onB * 0.20, 0.85)
    helpBtn:SetBackdropBorderColor(TH.onR, TH.onG, TH.onB, 0.60)
    do
        local glow = helpBtn:CreateTexture(nil, "BACKGROUND", nil, -1)
        glow:SetPoint("TOPLEFT", -3, 3); glow:SetPoint("BOTTOMRIGHT", 3, -3)
        glow:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.08)
        helpBtn._glow = glow

        local hl = helpBtn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.12)

        local lbl = MakeFS(helpBtn, "body", TH.onR, TH.onG, TH.onB, 1)
        lbl:SetPoint("CENTER", 0, 0); lbl:SetText("?")
        helpBtn._label = lbl

        local pulse = helpBtn:CreateAnimationGroup()
        local fadeOut = pulse:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0.45)
        fadeOut:SetDuration(0.8); fadeOut:SetOrder(1); fadeOut:SetSmoothing("IN_OUT")
        local fadeIn = pulse:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.45); fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.8); fadeIn:SetOrder(2); fadeIn:SetSmoothing("IN_OUT")
        pulse:SetLooping("REPEAT")
        helpBtn._pulse = pulse
    end
    helpBtn:SetScript("OnClick", function()
        HUD.StartTour()
    end)
    helpBtn:SetScript("OnEnter", function(self)
        if self._pulse then self._pulse:Stop() end
        self:SetAlpha(1)
        if not DockUI.OwnTooltip(self, "ANCHOR_BOTTOM", 0, -6) then return end
        GameTooltip:SetText(HelpText("EM_HELP_BTN_TIP"), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    helpBtn:SetScript("OnLeave", function()
        DockUI.ReleaseTooltip()
    end)

    --- Right-side: Cancel All | Exit
    exitBtn = MakeBtn(hudFrame, "EM_TOUR_DONE", 80, BTN_H, "body", function()
        if EM2.State then EM2.State.Exit("hud_exit") end
    end)
    ApplyButtonRole(exitBtn, "primary")
    exitBtn._dot:Hide()
    SetTip(exitBtn, "Keep the current positions and exit Edit Mode.")

    cancelAllBtn = MakeBtn(hudFrame, "Discard", 88, BTN_H, "body", function()
        if not EM2.State or not EM2.State.CancelAll then return end
        local cf = _G["MSUF_EM2_CancelConfirm"]
        if cf then cf:Show(); return end
        cf = CreateFrame("Frame", "MSUF_EM2_CancelConfirm", UIParent, "BackdropTemplate")
        cf:SetSize(320, 120)
        cf:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        cf:SetFrameStrata("TOOLTIP"); cf:SetFrameLevel(1400)
        cf:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1} })
        cf:SetBackdropColor(TH.r1Bg[1], TH.r1Bg[2], TH.r1Bg[3], TH.r1Bg[4] or 0.97)
        cf:SetBackdropBorderColor(TH.edge[1], TH.edge[2], TH.edge[3], 0.90)
        ApplyHUDMaterial(cf, "popup")
        cf:SetBackdropBorderColor(TH.edge[1], TH.edge[2], TH.edge[3], 0.90)
        cf:EnableMouse(true)
        local msg = MakeFS(cf, "body", TH.textR, TH.textG, TH.textB, 1)
        msg:SetPoint("TOP", cf, "TOP", 0, -24)
        msg:SetText(HelpText("Discard all changes and exit?"))
        local function ConfBtn(text, xOff, role, onClick)
            local ui = SharedUI()
            local b = ui and ui.Button and ui.Button(cf, HelpText(text), 112, 32, {
                align = "CENTER",
                skipHistory = true,
                variant = role == "danger" and "danger" or nil,
                onClick = onClick,
            }) or CreateFrame("Button", nil, cf, "BackdropTemplate")
            b:SetSize(112, 32)
            b:SetPoint("BOTTOM", cf, "BOTTOM", xOff, 16)
            if ui and ui.ApplyButtonRole then ui.ApplyButtonRole(b, role or "normal") end
            --- Same Blizzard-font-object inheritance as the toolbar buttons.
            local sharedLabel = b._msuf2Label or b._label
            if sharedLabel and ui and ui.ApplyFontRole then
                ui.ApplyFontRole(sharedLabel, "body", DockUI.baseFont, "")
            end
            if not (ui and ui.Button) then
                b:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1 })
                b:SetBackdropColor(TH.r2Bg[1], TH.r2Bg[2], TH.r2Bg[3], TH.r2Bg[4] or 0.90)
                b:SetBackdropBorderColor(TH.edge[1], TH.edge[2], TH.edge[3], 0.65)
                local hl = b:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
                local fs = MakeFS(b, "body", TH.textR, TH.textG, TH.textB, 1)
                fs:SetPoint("CENTER"); fs:SetText(HelpText(text))
                b:SetScript("OnClick", onClick)
            end
            return b
        end
        ConfBtn("Yes, discard", -64, "danger", function() cf:Hide(); EM2.State.CancelAll() end)
        ConfBtn("No, keep", 64, "normal", function() cf:Hide() end)
        cf:EnableKeyboard(true)
        cf:SetScript("OnKeyDown", function(s, k)
            if k == "ESCAPE" then s:SetPropagateKeyboardInput(false); cf:Hide()
            else s:SetPropagateKeyboardInput(true) end
        end)
        cf:HookScript("OnHide", function(s)
            if s.SetPropagateKeyboardInput then s:SetPropagateKeyboardInput(true) end
        end)
        cf:Show()
    end)
    ApplyButtonRole(cancelAllBtn, "normal")
    cancelAllBtn._label:SetTextColor(TH.mutedR, TH.mutedG, TH.mutedB, 0.90)
    cancelAllBtn._dot:Hide()
    SetTip(cancelAllBtn, "Discard ALL changes made in Edit Mode\nand restore settings to the state\nbefore Edit Mode was opened.")

    --- Center controls: grouped by task so the HUD scans as Preview | Layout | Tools.
    DockUI.primaryContainer = CreateFrame("Frame", nil, hudFrame)
    DockUI.primaryContainer:SetSize(1, CLUSTER_H)
    DockUI.row1 = {}

    local previewCluster, previewItems = AddCluster(DockUI.row1, DockUI.primaryContainer, "Preview", CLUSTER_H, true)
    previewBtn = AddRowButton(previewItems, previewCluster, "Preview", 72, CLUSTER_BTN_H, "caption", function()
        ExportPublic("MSUF_UnitPreviewActive", not (_G.MSUF_UnitPreviewActive and true or false))
        if _G.MSUF_SyncAllUnitPreviews then _G.MSUF_SyncAllUnitPreviews() end
        SetActive(previewBtn, _G.MSUF_UnitPreviewActive)
        HUD.SetStatus(HelpText(_G.MSUF_UnitPreviewActive and "EM_PREVIEW_ON" or "EM_PREVIEW_OFF"), "info")
    end, "Show placeholder data on unitframes\nwithout real units (target, focus, etc.)")

    previewAddonSlot = CreateFrame("Frame", "MSUF_EM2_HUD_PreviewAddonSlot", previewCluster)
    previewAddonSlot:SetSize(72, CLUSTER_BTN_H)
    previewItems[#previewItems+1] = previewAddonSlot

    if advancedHUD then
    previewAnimBtn = AddRowButton(previewItems, previewCluster, "Motion", 64, CLUSTER_BTN_H, "caption", function()
        local toggle = _G.MSUF_TogglePreviewAnimation
        if type(toggle) ~= "function" then
            HUD.SetStatus(HelpText("Preview animation unavailable"), "warn")
            return
        end
        local ok, reason = toggle("edit_mode")
        local active = type(_G.MSUF_IsPreviewAnimationEnabled) == "function" and _G.MSUF_IsPreviewAnimationEnabled() == true
        SetActive(previewAnimBtn, active)
        if previewBtn then SetActive(previewBtn, _G.MSUF_UnitPreviewActive and true or false) end
        if ok == false and reason == "combat" then
            HUD.SetStatus(HelpText("Preview animation pauses during combat."), "warn")
        else
            HUD.SetStatus(HelpText(active and "Preview animation on" or "Preview animation off"), "info")
        end
    end, "Animate visible preview dummy frames.\nStops automatically in combat\nor when previews are hidden.")
    RegisterPreviewAnimationRefreshOwner()

    auraBtn = AddRowButton(previewItems, previewCluster, "Auras", 64, CLUSTER_BTN_H, "caption", function()
        local db = _G.MSUF_DB; if not db then return end
        local a2 = db.auras3; if not a2 then return end
        local sh = a2.shared; if not sh then return end
        sh.showInEditMode = not (sh.showInEditMode and true or false)
        SetActive(auraBtn, sh.showInEditMode and _G.MSUF_UnitPreviewActive == true)
        local a3 = MSUF and MSUF.MSUF_Auras3
        if a3 and type(a3.RefreshEditPreview) == "function" then
            a3.RefreshEditPreview()
        elseif a3 and type(a3.RefreshAll) == "function" then
            a3.RefreshAll()
        end
        HUD.SetStatus(HelpText(sh.showInEditMode and "EM_AURAS_ON" or "EM_AURAS_OFF"), "info")
    end, "Toggle aura preview icons\nand aura mover boxes.")
    end
    FinishCluster(previewCluster, previewItems, CLUSTER_H, -7)

    local layoutCluster, layoutItems = AddCluster(DockUI.row1, DockUI.primaryContainer, "Layout", CLUSTER_H, true)
    snapToggle = AddRowButton(layoutItems, layoutCluster, "Snap", 56, CLUSTER_BTN_H, "caption", function()
        if EM2.Snap then
            local on = not EM2.Snap.IsEnabled()
            EM2.Snap.SetEnabled(on); SetActive(snapToggle, on)
            HUD.SetStatus(HelpText(on and "EM_SNAP_ON" or "EM_SNAP_OFF"), "info")
        end
    end, "Snap frames to edges of\nother frames while dragging.")

    gridWidget, stepFS = AddAdjustWidget(layoutItems, layoutCluster, 72, CLUSTER_BTN_H, true, function(_, d)
        if not EM2.Grid then return end
        EM2.Grid.SetGridStep(max(4, min(80, EM2.Grid.GetGridStep() + d * 4)))
        HUD.RefreshControls()
    end, function(_, button)
        if button ~= "LeftButton" or not EM2.Grid or not EM2.Grid.ToggleEnabled then return end
        EM2.Grid.ToggleEnabled()
        HUD.SetStatus(HelpText((not EM2.Grid.GetEnabled or EM2.Grid.GetEnabled()) and "EM_GRID_ON" or "EM_GRID_OFF"), "info")
        HUD.RefreshControls()
    end, "Left-click to toggle grid lines.\nScroll to adjust spacing.")

    bgWidget, alphaFS = AddAdjustWidget(layoutItems, layoutCluster, 68, CLUSTER_BTN_H, false, function(_, d)
        if not EM2.Grid then return end
        EM2.Grid.SetBgAlpha(max(0, min(1, EM2.Grid.GetBgAlpha() + d * 0.05)))
        HUD.RefreshControls()
    end, nil, "Background overlay opacity.\nScroll to adjust.")

    resetBtn = AddRowButton(layoutItems, layoutCluster, "Reset", 56, CLUSTER_BTN_H, "caption", function()
        HUD.ResetCurrentPosition()
    end, "Reset the selected frame position.\nSize stays unchanged.")
    FinishCluster(layoutCluster, layoutItems, CLUSTER_H, -7)
    layoutCluster._stepFS = stepFS
    layoutCluster._alphaFS = alphaFS
    layoutCluster._gridWidget = gridWidget
    layoutCluster._bgWidget = bgWidget
    ExportPublic("MSUF_EditModeGridTools", layoutCluster)

    local linksCluster, linksItems = AddCluster(DockUI.row1, DockUI.primaryContainer, "Tools", CLUSTER_H, true)
    DockUI.positionBtn = AddRowButton(linksItems, linksCluster, "Position", 76, CLUSTER_BTN_H, "caption", function()
        local popup = EnsurePositionPopup()
        if popup:IsShown() then popup:Hide() else popup:Show() end
    end, "Dock the Edit Mode toolbar at any screen edge.")
    settingsBtn = AddRowButton(linksItems, linksCluster, "Settings", 76, CLUSTER_BTN_H, "caption", function()
        HUD.OpenSelectedSettings()
    end, "Open Menu2 at the selected\nframe or component settings.")

    cdmBtn = AddRowButton(linksItems, linksCluster, "Cooldown", 116, CLUSTER_BTN_H, "caption", function()
        local db = _G.MSUF_DB; if not db then return end
        db.general = db.general or {}
        local enabled = not HUD.CooldownAnchorEnabled(db.general)
        local setter = _G.MSUF_SetCooldownAnchorEnabled
        if type(setter) == "function" then
            setter(enabled, true)
        else
            db.general.anchorToCooldown = enabled
        end
        SetActive(cdmBtn, HUD.CooldownAnchorEnabled(db.general))
        ApplyAllSettingsSafe()
        HUD.SetStatus(HelpText(enabled and "EM_CDM_ON" or "EM_CDM_OFF"), "info")
        C_Timer.After(0.1, function()
            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
            if _G.MSUF_EM2_ReforcePreviewFrames then _G.MSUF_EM2_ReforcePreviewFrames() end
        end)
    end, "Anchor all unitframes to the\nEssential Cooldown Manager.")

    anchorBtn = AddRowButton(linksItems, linksCluster, "Anchor", 60, CLUSTER_BTN_H, "caption", function()
        local ov = type(_G.MSUF_EnsureAnchorPicker) == "function" and _G.MSUF_EnsureAnchorPicker()
        if not ov then return end
        ov._isCandidateAllowed = function(frame)
            local factory = MSUF and MSUF.UF and MSUF.UF.Factory
            return not factory or type(factory.IsAnchorCandidateAllowed) ~= "function"
                or factory.IsAnchorCandidateAllowed(frame)
        end
        ov._onPick = function(frameName)
            local db = _G.MSUF_DB; if not db then return end
            db.general = db.general or {}
            db.general.anchorName = frameName
            local setter = _G.MSUF_SetCooldownAnchorEnabled
            if type(setter) == "function" then
                setter(false, true)
            else
                db.general.anchorToCooldown = false
            end
            SetActive(cdmBtn, false)
            ApplyAllSettingsSafe()
            HUD.SetStatus(HelpText("EM_ANCHOR_SET") .. ": " .. tostring(frameName or ""), "ok")
            C_Timer.After(0.1, function()
                if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
            end)
        end
        ov:Show()
    end, "Pick any frame as global anchor\nfor all unitframes.\nOverrides CDM anchor.")
    FinishCluster(linksCluster, linksItems, CLUSTER_H, -7)

    LayoutClusterRow(DockUI.primaryContainer, DockUI.row1)

    --- Compact contextual status capsule.  History lives in the main dock.
    row2Frame = CreateFrame("Frame", "MSUF_EM2_HUD_Row2", hudFrame, "BackdropTemplate")
    row2Frame:SetSize(800, DockUI.inspectorH)
    row2Frame:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=2,right=2,top=2,bottom=2} })
    row2Frame:SetBackdropColor(unpack(TH.r2Bg))
    row2Frame:SetBackdropBorderColor(unpack(TH.edge))
    ApplyHUDMaterial(row2Frame, "status")
    row2Frame:EnableMouse(true)

    DockUI.inspectorSelection = CreateFrame("Button", nil, row2Frame)
    DockUI.inspectorSelection:SetSize(DockUI.inspectorLabelW, BTN_H)
    local selectionBg = DockUI.inspectorSelection:CreateTexture(nil, "BACKGROUND")
    selectionBg:SetAllPoints()
    selectionBg:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.055)
    local selectionHL = DockUI.inspectorSelection:CreateTexture(nil, "HIGHLIGHT")
    selectionHL:SetAllPoints()
    selectionHL:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.10)
    DockUI.inspectorSelection:SetScript("OnClick", function() HUD.ToggleMenuPicker() end)
    SetTip(DockUI.inspectorSelection, "Choose which frame's settings page to open.")

    selectionFS = MakeFS(DockUI.inspectorSelection, "caption", TH.textR, TH.textG, TH.textB, 0.92)
    selectionFS:SetPoint("LEFT", DockUI.inspectorSelection, "LEFT", 12, 0)
    selectionFS:SetPoint("RIGHT", DockUI.inspectorSelection, "RIGHT", -24, 0)
    selectionFS:SetJustifyH("LEFT")
    selectionFS:SetText("")

    local selectionChevron = MakeFS(DockUI.inspectorSelection, "micro", TH.mutedR, TH.mutedG, TH.mutedB, 0.82)
    selectionChevron:SetPoint("RIGHT", DockUI.inspectorSelection, "RIGHT", -10, 1)
    selectionChevron:SetText("v")

    DockUI.inspectorMetrics = {}
    DockUI.inspectorMetricFS = {}
    for i, prefix in ipairs({ "X", "Y", "W", "H" }) do
        local cell = CreateFrame("Frame", nil, row2Frame)
        cell:SetSize(DockUI.inspectorMetricW, BTN_H)
        local divider = cell:CreateTexture(nil, "BORDER")
        divider:SetSize(1, BTN_H - 8)
        divider:SetPoint("LEFT", cell, "LEFT", 0, 0)
        divider:SetColorTexture(TH.edge[1], TH.edge[2], TH.edge[3], 0.70)
        local valueFS = MakeFS(cell, "caption", TH.textR, TH.textG, TH.textB, 0.90)
        valueFS:SetPoint("CENTER")
        valueFS:SetText(prefix .. " --")
        cell._metricPrefix = prefix
        cell._valueFS = valueFS
        DockUI.inspectorMetrics[i] = cell
        DockUI.inspectorMetricFS[i] = valueFS
    end
    row2Frame._inspectorSelection = DockUI.inspectorSelection
    row2Frame._inspectorSelectionFS = selectionFS
    row2Frame._inspectorMetrics = DockUI.inspectorMetrics

    hintFS = MakeFS(row2Frame, "caption", TH.mutedR, TH.mutedG, TH.mutedB, 0.78)
    hintFS:SetPoint("RIGHT", row2Frame, "RIGHT", -16, 0)
    hintFS:SetWidth(300)
    hintFS:SetJustifyH("RIGHT")
    hintFS:SetText("")

    DockUI.historyContainer = CreateFrame("Frame", nil, hudFrame)
    DockUI.historyContainer:SetSize(1, BTN_H2)
    DockUI.row2 = {}

    local historyItems
    DockUI.historyCluster, historyItems = AddCluster(DockUI.row2, DockUI.historyContainer, nil, BTN_H2 + 4, false)
    undoBtn = AddRowButton(historyItems, DockUI.historyCluster, "", BTN_H, BTN_H2, "caption", function()
        if EM2.Undo and EM2.Undo.DoUndo then
            EM2.Undo.DoUndo()
        elseif _G.MSUF_EM_UndoUndo then
            _G.MSUF_EM_UndoUndo()
        end
        HUD.RefreshControls()
    end, "Undo the last MSUF change from Edit Mode or the in-game menu.")
    ExportPublic("MSUF_EditModeUndoBtn", undoBtn)
    AttachHistoryIcon(undoBtn, MEDIA .. "msuf_history_undo_red.png")

    redoBtn = AddRowButton(historyItems, DockUI.historyCluster, "", BTN_H, BTN_H2, "caption", function()
        if EM2.Undo and EM2.Undo.DoRedo then
            EM2.Undo.DoRedo()
        elseif _G.MSUF_EM_UndoRedo then
            _G.MSUF_EM_UndoRedo()
        end
        HUD.RefreshControls()
    end, "Redo the last MSUF change from Edit Mode or the in-game menu.")
    ExportPublic("MSUF_EditModeRedoBtn", redoBtn)
    AttachHistoryIcon(redoBtn, MEDIA .. "msuf_history_redo_green.png")
    FinishCluster(DockUI.historyCluster, historyItems, BTN_H2 + 4, 0)

    LayoutClusterRow(DockUI.historyContainer, DockUI.row2)

    ApplyButtonRole(DockUI.positionBtn, "primary")
    AttachDockHover(hudFrame); AttachDockHover(row2Frame); AttachDockHover(DockUI.grip)
    AttachDockHover(DockUI.logo); AttachDockHover(DockUI.contextBtn); AttachDockHover(helpBtn)
    AttachDockHover(exitBtn); AttachDockHover(cancelAllBtn); AttachDockHover(DockUI.positionBtn)
    for _, cluster in ipairs(DockUI.row1) do
        AttachDockHover(cluster)
        for _, item in ipairs(cluster._dockItems or {}) do AttachDockHover(item) end
    end
    for _, cluster in ipairs(DockUI.row2) do
        AttachDockHover(cluster)
        for _, item in ipairs(cluster._dockItems or {}) do AttachDockHover(item) end
    end
    DockUI.layoutEvents = CreateFrame("Frame", "MSUF_EM2_HUD_LayoutEvents")
    DockUI.layoutEvents:SetScript("OnEvent", function()
        if hudFrame and hudFrame:IsShown() and not (InCombatLockdown and InCombatLockdown()) then
            ApplyDockLayout()
            DockUI.ScheduleLayoutSettle()
        end
    end)
    return true
end

local function SetLayoutEventsEnabled(enabled)
    local frame = DockUI.layoutEvents
    if not frame or frame._msufEnabled == (enabled == true) then return end
    frame._msufEnabled = enabled == true
    if enabled then
        frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
        frame:RegisterEvent("UI_SCALE_CHANGED")
    else
        frame:UnregisterEvent("DISPLAY_SIZE_CHANGED")
        frame:UnregisterEvent("UI_SCALE_CHANGED")
    end
end

function HUD.RefreshUnitSelector()
    HUD.RefreshControls()
end

function HUD.RefreshControls(force)
    if not hudFrame or (not force and not hudFrame:IsShown()) then return end
    local key, component, slot = CurrentFocusSelection()
    local label, x, y, w, h = SelectionValues(key, component, slot)
    local text = DockUI.inspectorCompact and FormatSelectionSummary(label, x, y, w, h) or label
    if selectionLastText ~= text then
        selectionFS:SetText(text)
        selectionLastText = text
    end
    for i, fs in ipairs(DockUI.inspectorMetricFS or {}) do
        local value = i == 1 and x or (i == 2 and y or (i == 3 and w or h))
        local rendered = (DockUI.inspectorMetrics[i]._metricPrefix or "") .. " " .. (value == nil and "--" or tostring(value))
        if force or fs._msufValue ~= rendered then
            fs._msufValue = rendered
            fs:SetText(rendered)
        end
    end
    RefreshDockContext(key)
    --- Keep the open list's highlight on whatever is selected now, even when the
    --- selection changed through a mover click instead of the list itself.
    HUD.RefreshFramePicker()
    if hintFS then
        local now = GetTime and GetTime() or 0
        if InCombatLockdown and InCombatLockdown() then
            SetHint(HelpText("Combat locked"), TH.exitR, TH.exitG, TH.exitB, 0.95)
        elseif hudStatusText and hudStatusUntil and now <= hudStatusUntil then
            if hudStatusKind == "ok" then
                SetHint(hudStatusText, TH.okR, TH.okG, TH.okB, 0.95)
            elseif hudStatusKind == "warn" then
                SetHint(hudStatusText, TH.warnR, TH.warnG, TH.warnB, 0.95)
            else
                SetHint(hudStatusText, TH.onR, TH.onG, TH.onB, 0.95)
            end
        else
            hudStatusText, hudStatusKind, hudStatusUntil = nil, nil, nil
            SetHint(DefaultHintText(key ~= nil), TH.mutedR, TH.mutedG, TH.mutedB, 0.78)
        end
    end
    if alphaFS and EM2.Grid then
        local value = floor(EM2.Grid.GetBgAlpha() * 100 + 0.5)
        if force or alphaFS._msufValue ~= value then
            alphaFS._msufValue = value
            alphaFS:SetText(HelpText("BG") .. " " .. value .. "%")
        end
    end
    if stepFS and EM2.Grid then
        local enabled = not EM2.Grid.GetEnabled or EM2.Grid.GetEnabled()
        local value = floor(EM2.Grid.GetGridStep())
        if force or stepFS._msufValue ~= value then
            stepFS._msufValue = value
            stepFS:SetText(HelpText("Grid") .. " " .. value .. "px")
        end
        if gridWidget._msufEnabled ~= enabled then
            gridWidget._msufEnabled = enabled
            if enabled then
                stepFS:SetTextColor(TH.okR, TH.okG, TH.okB, 0.95)
                if gridWidget._stateBg then gridWidget._stateBg:SetColorTexture(TH.okR, TH.okG, TH.okB, 0.18) end
            else
                stepFS:SetTextColor(TH.exitR, TH.exitG, TH.exitB, 0.95)
                if gridWidget._stateBg then gridWidget._stateBg:SetColorTexture(TH.exitR, TH.exitG, TH.exitB, 0.20) end
            end
        end
    end
    if snapToggle and EM2.Snap then SetActive(snapToggle, EM2.Snap.IsEnabled()) end
    local selectedCfg = key and EM2.Registry and EM2.Registry.Get and EM2.Registry.Get(key) or nil
    local external = selectedCfg and selectedCfg.externalPublicElement == true and EM2.ExternalElements or nil
    SetControlEnabled(resetBtn, key and (UNIT_KEYS[key] == true or GROUP_KEY_TO_KIND[key] ~= nil
        or (external and external.CanReset and external.CanReset(key))))
    SetControlEnabled(settingsBtn, key ~= nil and (not external
        or (external.CanOpenSettings and external.CanOpenSettings(key))))
    if settingsBtn then
        settingsBtn._msufTipText = external
            and ((selectedCfg.label or key) .. " settings")
            or "Choose which frame's settings page to open."
    end
    RegisterPreviewAnimationRefreshOwner()
    if previewBtn then SetActive(previewBtn, _G.MSUF_UnitPreviewActive and true or false) end
    if previewAnimBtn then
        local active = type(_G.MSUF_IsPreviewAnimationEnabled) == "function" and _G.MSUF_IsPreviewAnimationEnabled() == true
        SetActive(previewAnimBtn, active)
    end
    if cdmBtn then
        local db = _G.MSUF_DB
        local general = db and db.general
        local providerId, providerLabel = HUD.AutomaticCooldownProvider()
        local detected = providerId ~= nil
        local verticalDock = IsVerticalDock(EnsureDockState().dock)
        local providerAnchorText = detected and (providerLabel .. (verticalDock and "" or " Anchor")) or HelpText("Cooldown")
        if force or cdmBtn._msufProviderAnchorText ~= providerAnchorText then
            cdmBtn._msufProviderAnchorText = providerAnchorText
            if cdmBtn._label and cdmBtn._label.SetText then cdmBtn._label:SetText(providerAnchorText) end
        end
        if force or cdmBtn._msufAutomaticProviderId ~= providerId then
            cdmBtn._msufAutomaticProviderId = providerId
            cdmBtn._msufTipText = detected
                and string.format(L["%s detected. Toggle the %s Anchor for all global Unitframes."], providerLabel, providerLabel)
                or L["Anchor all unitframes to the\nEssential Cooldown Manager."]
        end
        SetActive(cdmBtn, HUD.CooldownAnchorEnabled(general))
        SetControlEnabled(anchorBtn, true)
    end
    if auraBtn then
        local db = _G.MSUF_DB; local a2 = db and db.auras3; local sh = a2 and a2.shared
        SetActive(auraBtn, sh and sh.showInEditMode and _G.MSUF_UnitPreviewActive == true)
    end
    SetHistoryEnabled(undoBtn, EM2.Undo and EM2.Undo.CanUndo())
    SetHistoryEnabled(redoBtn, EM2.Undo and EM2.Undo.CanRedo())
    if DockUI.positionPopup and DockUI.positionPopup:IsShown() then RefreshPositionPopup() end
end

function HUD.Show()
    if InCombatLockdown and InCombatLockdown() then return false end
    EnsureHUD()
    --- Only a real entry animates.  The group-frame bridge wraps HUD.Show and
    --- calls it again while the toolbar is already on screen, which must not
    --- replay the slide.
    local entering = not hudFrame:IsShown()
    hudFrame:Show(); if row2Frame then row2Frame:Show() end
    ApplyDockLayout()
    DockUI.ScheduleLayoutSettle()
    HUD.RefreshControls(true)
    SetLayoutEventsEnabled(true)
    if helpBtn and helpBtn._pulse then helpBtn._pulse:Play() end
    SetDockExpanded(true)
    if entering then DockUI.ArmDockIntro() end
    if EnsureDockState().autoHide then ScheduleDockAutoHide() end
    return true
end

function HUD.ShowPositionSettings(shown)
    if InCombatLockdown and InCombatLockdown() then return false end
    EnsureHUD()
    ApplyDockLayout()
    DockUI.ScheduleLayoutSettle()
    local popup = EnsurePositionPopup()
    if shown == false then popup:Hide() else popup:Show() end
    return popup:IsShown()
end

function HUD.Hide()
    HUD.StopTour()
    if DockUI.drag then StopDockDrag() end
    local cf = _G["MSUF_EM2_CancelConfirm"]; if cf then cf:Hide() end
    SetLayoutEventsEnabled(false)
    if helpBtn and helpBtn._pulse then helpBtn._pulse:Stop() end
    if row2Frame then row2Frame:Hide() end; if hudFrame then hudFrame:Hide() end
    --- After the Hide: the slide gives back the anchor and clamping without
    --- reviving alpha or auto-hide work for a toolbar that just left.
    DockUI.StopDockIntro()
    if DockUI.positionPopup then DockUI.positionPopup:Hide() end
    HUD.CloseFramePicker()
    autoHideGeneration = autoHideGeneration + 1
end

function HUD.IsShown() return hudFrame and hudFrame:IsShown() or false end

local function MSUF_EM2_SetHUDStatus(text, kind, seconds)
    return HUD.SetStatus(text, kind, seconds)
end
ExportPublic("MSUF_EM2_SetHUDStatus", MSUF_EM2_SetHUDStatus)

end

ExportPublic("MSUF_InstallEditModeHUD", InstallEditModeHUD)
