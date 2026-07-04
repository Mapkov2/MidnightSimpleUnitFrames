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

local hudFrame, row2Frame
local previewBtn, previewAnimBtn, auraBtn, snapToggle, resetBtn, settingsBtn, cdmBtn, anchorBtn
local previewAddonSlot
local previewAnimRefreshRegistered
local undoBtn, redoBtn, cancelAllBtn, exitBtn
local alphaFS, stepFS
local selectionFS, hintFS
local hudStatusText, hudStatusKind, hudStatusUntil
local selectionLastText, hintLastText, hintLastR, hintLastG, hintLastB, hintLastA
local helpBtn, tutorialPanel, tourState
local bgWidget, gridWidget
local HelpText

local R1_H    = 44
local R2_H    = 34
local BTN_H   = 32
local BTN_H2  = 26
local BTN_GAP = 5
local SEP_W   = 16
local CLUSTER_H     = 42
local CLUSTER_BTN_H = 27
local CLUSTER_GAP   = 8
local CLUSTER_PAD_X = 6

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

local function MakeFS(p, sz, r, g, b, a)
    local fs = p:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, sz or 12, ""); fs:SetShadowOffset(1, -1)
    fs:SetTextColor(r or 1, g or 1, b or 1, a or 1); return fs
end

local function SetActive(btn, on)
    if not btn or not btn._label then return end
    if on then
        btn._label:SetTextColor(TH.onR, TH.onG, TH.onB, 1)
        if btn._dot then btn._dot:Show() end
    else
        btn._label:SetTextColor(TH.offR, TH.offG, TH.offB, 0.85)
        if btn._dot then btn._dot:Hide() end
    end
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

local function SetTip(widget, text)
    if not widget or not text then return end
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -6)
        GameTooltip:SetText(HelpText(text), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local UNIT_KEYS = { player = true, target = true, focus = true, focustarget = true, targettarget = true, pet = true, boss = true }

local GROUP_KEY_TO_KIND = {
    gf_party = "party",
    gf_raid = "raid",
    gf_mythicraid = "mythicraid",
}

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

local function SelectionSummary()
    local key, component, slot = CurrentFocusSelection()
    if not key then return HelpText("No selection") end
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
    if not conf then return label end
    local x = floor((tonumber(conf.offsetX) or 0) + 0.5)
    local y = floor((tonumber(conf.offsetY) or 0) + 0.5)
    local w = tonumber(conf.width)
    local h = tonumber(conf.height)
    if w and h then
        return string.format("%s   X %d   Y %d   W %d   H %d", label, x, y, floor(w + 0.5), floor(h + 0.5))
    end
    return string.format("%s   X %d   Y %d", label, x, y)
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

local function DefaultHintText()
    if EM2.Popups and EM2.Popups.IsAnyOpen and EM2.Popups.IsAnyOpen() then
        return HelpText("EM_HINT_POPUP")
    end
    if CurrentSelectionKey() then
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
                conf.offsetX = (groupKind == "party") and -400 or -500
                conf.offsetY = 0
                if type(_G.MSUF_GF_RefreshAll) == "function" then
                    _G.MSUF_GF_RefreshAll()
                elseif type(_G.MSUF_GF_RebuildAll) == "function" then
                    _G.MSUF_GF_RebuildAll()
                end
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
    if type(_G.MSUF_ApplyUnitFrameKey_Immediate) == "function" then
        _G.MSUF_ApplyUnitFrameKey_Immediate(key)
    elseif not ApplySettingsForKeySafe(key) then
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

local function MakeBtn(parent, text, w, h, fontSize, onClick)
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
        label = MakeFS(btn, fontSize or 12, TH.textR, TH.textG, TH.textB, 0.92)
        label:SetPoint("CENTER"); label:SetText(HelpText(text))
    end
    btn._label = label
    local dot = btn:CreateTexture(nil, "OVERLAY")
    dot:SetSize(w - 8, 2); dot:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)
    dot:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.90); dot:Hide()
    btn._dot = dot
    if onClick and not (ui and ui.Button) then btn:SetScript("OnClick", onClick) end
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

local function MakeSep(parent, h)
    local s = parent:CreateTexture(nil, "OVERLAY")
    s:SetSize(1, (h or BTN_H) - 8); s:SetColorTexture(0.35, 0.38, 0.45, 0.28)
    return s
end

local function LayoutCenter(anchor, items, gap, sepW)
    local totalW = 0
    for i, b in ipairs(items) do
        totalW = totalW + (b._isSep and sepW or b:GetWidth())
        if i < #items then totalW = totalW + gap end
    end
    local x = -totalW / 2
    for _, b in ipairs(items) do
        local w = b._isSep and sepW or b:GetWidth()
        b:SetPoint("LEFT", anchor, "CENTER", b._isSep and (x + w/2) or x, 0)
        x = x + w + gap
    end
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
        local fs = MakeFS(f, 8, TH.mutedR, TH.mutedG, TH.mutedB, 0.70)
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
    local w = RowItemsWidth(items, BTN_GAP, SEP_W) + CLUSTER_PAD_X * 2
    cluster:SetSize(w, height or CLUSTER_H)
    local x = CLUSTER_PAD_X
    for _, b in ipairs(items) do
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

local function AddRowButton(row, parent, text, width, height, fontSize, onClick, tip)
    local btn = MakeBtn(parent, text, width, height, fontSize, onClick)
    if tip then SetTip(btn, tip) end
    row[#row + 1] = btn
    return btn
end

local function AddRowSep(row, parent, height)
    local sep = MakeSep(parent, height); sep._isSep = true; row[#row + 1] = sep
    return sep
end

local function AddAdjustWidget(row, parent, width, height, withStateBg, onMouseWheel, onMouseUp, tip)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, height); f:EnableMouse(true); f:EnableMouseWheel(true)
    if withStateBg then
        local stateBg = f:CreateTexture(nil, "BACKGROUND")
        stateBg:SetAllPoints(); stateBg:SetColorTexture(0, 0, 0, 0)
        f._stateBg = stateBg
    end
    local fs = MakeFS(f, 11, TH.mutedR, TH.mutedG, TH.mutedB, 0.80)
    fs:SetPoint("CENTER")
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.04)
    if onMouseUp then f:SetScript("OnMouseUp", onMouseUp) end
    if onMouseWheel then f:SetScript("OnMouseWheel", onMouseWheel) end
    if tip then SetTip(f, tip) end
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
    "CDM & Anchor", "Copy Settings", "Exit Edit Mode",
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

--- Tutorial / Help Reference Panel (lazy init)
local HELP_SECTIONS = {
    { title = "Drag & Move",        body = "EM_HELP_DRAG" },
    { title = "Click Popup",        body = "EM_HELP_POPUP" },
    { title = "Arrow Key Nudge",    body = "EM_HELP_NUDGE" },
    { title = "Grid & Snap",        body = "EM_HELP_SNAP" },
    { title = "Background Opacity", body = "EM_HELP_OPACITY" },
    { title = "Preview & Auras",    body = "EM_HELP_PREVIEW" },
    { title = "CDM & Anchor",       body = "EM_HELP_CDM" },
    { title = "Copy Settings",      body = "EM_HELP_COPYTO" },
    { title = "Undo / Cancel All",  body = "EM_HELP_UNDO" },
    { title = "Exit Edit Mode",     body = "EM_HELP_EXIT" },
}

local PANEL_W     = 340
local PANEL_PAD   = 16
local SEC_GAP     = 6
local TITLE_SZ    = 12
local BODY_SZ     = 11
local BODY_W      = PANEL_W - PANEL_PAD * 2
local HEADER_H    = 36
local CLOSE_SZ    = 20

local function EnsureTutorialPanel()
    if tutorialPanel then return tutorialPanel end
    RefreshHUDTheme()

    local p = CreateFrame("Frame", "MSUF_EM2_TutorialPanel", UIParent, "BackdropTemplate")
    p:SetFrameStrata("TOOLTIP"); p:SetFrameLevel(950)
    p:SetWidth(PANEL_W)
    p:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    p:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    p:SetBackdropColor(TH.r1Bg[1], TH.r1Bg[2], TH.r1Bg[3], TH.r1Bg[4] or 0.97)
    p:SetBackdropBorderColor(TH.edge[1], TH.edge[2], TH.edge[3], 0.90)
    ApplyHUDMaterial(p, "popup")
    p:EnableMouse(true); p:Hide()

    p:EnableKeyboard(true)
    p:SetScript("OnKeyDown", function(self, k)
        if k == "ESCAPE" then
            self:SetPropagateKeyboardInput(false); self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    p:HookScript("OnHide", function(self)
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
    end)

    local hdr = MakeFS(p, 13, TH.textR, TH.textG, TH.textB, 1)
    hdr:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD, -12)
    hdr:SetText(HelpText("EM_HELP_TITLE"))

    local closeBtn = CreateFrame("Button", nil, p)
    closeBtn:SetSize(CLOSE_SZ, CLOSE_SZ)
    closeBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -8)
    local closeFS = MakeFS(closeBtn, 14, TH.mutedR, TH.mutedG, TH.mutedB, 0.70)
    closeFS:SetPoint("CENTER"); closeFS:SetText("x")
    closeBtn:SetScript("OnEnter", function() closeFS:SetTextColor(1, 1, 1, 1) end)
    closeBtn:SetScript("OnLeave", function() closeFS:SetTextColor(TH.mutedR, TH.mutedG, TH.mutedB, 0.70) end)
    closeBtn:SetScript("OnClick", function() p:Hide() end)

    local y = -(HEADER_H)

    for i, sec in ipairs(HELP_SECTIONS) do
        if i > 1 then
            local div = p:CreateTexture(nil, "ARTWORK")
            div:SetSize(BODY_W, 1)
            div:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD, y - SEC_GAP * 0.5)
            div:SetColorTexture(TH.edge[1], TH.edge[2], TH.edge[3], 0.25)
            y = y - SEC_GAP
        end

        local tFS = MakeFS(p, TITLE_SZ, TH.onR, TH.onG, TH.onB, 1.00)
        tFS:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD, y)
        tFS:SetText(HelpText(sec.title))

        y = y - (TITLE_SZ + 4)

        local bFS = MakeFS(p, BODY_SZ, TH.textR, TH.textG, TH.textB, 0.90)
        bFS:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD, y)
        bFS:SetWidth(BODY_W); bFS:SetWordWrap(true); bFS:SetJustifyH("LEFT")
        bFS:SetText(HelpText(sec.body))

        local bH = bFS:GetStringHeight() or 14
        y = y - bH - SEC_GAP
    end

    y = y - 4
    local tourBtn = CreateFrame("Button", nil, p, "BackdropTemplate")
    tourBtn:SetSize(BODY_W, 28)
    tourBtn:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD, y)
    tourBtn:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1,
                          insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    tourBtn:SetBackdropColor(TH.onR * 0.25, TH.onG * 0.25, TH.onB * 0.25, 0.90)
    tourBtn:SetBackdropBorderColor(TH.onR, TH.onG, TH.onB, 0.50)
    local tbHL = tourBtn:CreateTexture(nil, "HIGHLIGHT")
    tbHL:SetAllPoints(); tbHL:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.10)
    local tbFS = MakeFS(tourBtn, 12, TH.onR, TH.onG, TH.onB, 1)
    tbFS:SetPoint("CENTER"); tbFS:SetText(HelpText("EM_TOUR_START"))
    tourBtn:SetScript("OnClick", function()
        p:Hide()
        HUD.StartTour()
    end)

    y = y - 28 - 4
    p:SetHeight(-y + PANEL_PAD * 0.5)

    tutorialPanel = p
    return p
end

--- Phase 2: Guided Tour ? spotlight mask + step cards
local MASK_ALPHA = 0.65
local CARD_W     = 300
local CARD_PAD   = 14
local SPOT_PAD   = 6

local function GetTourSteps()
    return {
        {
            title  = HelpText("Drag & Move"),
            body   = HelpText("EM_HELP_DRAG"),
            anchor = "CENTER",
        },
        {
            target = function() return previewBtn end,
            title  = HelpText("Preview & Auras"),
            body   = HelpText("EM_HELP_PREVIEW"),
            anchor = "BOTTOM",
        },
        {
            title  = HelpText("Click Popup"),
            body   = HelpText("EM_HELP_POPUP"),
            anchor = "CENTER",
        },
        {
            title  = HelpText("Arrow Key Nudge"),
            body   = HelpText("EM_HELP_NUDGE"),
            anchor = "CENTER",
        },
        {
            target = function() return snapToggle end,
            title  = HelpText("Grid & Snap"),
            body   = HelpText("EM_HELP_SNAP"),
            anchor = "BOTTOM",
        },
        {
            target = function() return bgWidget end,
            title  = HelpText("Background Opacity"),
            body   = HelpText("EM_HELP_OPACITY"),
            anchor = "BOTTOM",
        },
        {
            target = function() return cdmBtn end,
            title  = HelpText("CDM & Anchor"),
            body   = HelpText("EM_HELP_CDM"),
            anchor = "BOTTOM",
        },
        {
            title  = HelpText("Copy Settings"),
            body   = HelpText("EM_HELP_COPYTO"),
            anchor = "CENTER",
        },
        {
            target = function() return undoBtn end,
            title  = HelpText("Undo / Cancel All"),
            body   = HelpText("EM_HELP_UNDO"),
            anchor = "BOTTOM",
        },
        {
            target = function() return exitBtn end,
            title  = HelpText("Exit Edit Mode"),
            body   = HelpText("EM_HELP_EXIT"),
            anchor = "BOTTOM",
        },
    }
end

local function EnsureTourFrames()
    if tourState then return tourState end
    RefreshHUDTheme()

    local ts = {}
    tourState = ts
    ts.step = 0

    ts.masks = {}
    for i = 1, 4 do
        local m = CreateFrame("Frame", nil, UIParent)
        m:SetFrameStrata("TOOLTIP"); m:SetFrameLevel(940)
        local tex = m:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints(); tex:SetColorTexture(0, 0, 0, MASK_ALPHA)
        m:EnableMouse(true); m:Hide()
        ts.masks[i] = m
    end

    ts.ring = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    ts.ring:SetFrameStrata("TOOLTIP"); ts.ring:SetFrameLevel(941)
    ts.ring:SetBackdrop({ edgeFile = W8, edgeSize = 2 })
    ts.ring:SetBackdropBorderColor(TH.onR, TH.onG, TH.onB, 0.85)
    ts.ring:Hide()

    ts.card = CreateFrame("Frame", "MSUF_EM2_TourCard", UIParent, "BackdropTemplate")
    ts.card:SetFrameStrata("TOOLTIP"); ts.card:SetFrameLevel(945)
    ts.card:SetWidth(CARD_W)
    ts.card:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1,
                          insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    ts.card:SetBackdropColor(TH.r1Bg[1], TH.r1Bg[2], TH.r1Bg[3], TH.r1Bg[4] or 0.97)
    ts.card:SetBackdropBorderColor(TH.onR, TH.onG, TH.onB, 0.70)
    ApplyHUDMaterial(ts.card, "popup")
    ts.card:SetBackdropBorderColor(TH.onR, TH.onG, TH.onB, 0.70)
    ts.card:EnableMouse(true); ts.card:Hide()

    ts.card:EnableKeyboard(true)
    ts.card:SetScript("OnKeyDown", function(self, k)
        if k == "ESCAPE" then
            self:SetPropagateKeyboardInput(false); HUD.StopTour()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    ts.card:HookScript("OnHide", function(self)
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
    end)

    ts.stepFS = MakeFS(ts.card, 10, TH.mutedR, TH.mutedG, TH.mutedB, 0.70)
    ts.stepFS:SetPoint("TOPRIGHT", ts.card, "TOPRIGHT", -CARD_PAD, -10)

    ts.titleFS = MakeFS(ts.card, 13, TH.onR, TH.onG, TH.onB, 1.00)
    ts.titleFS:SetPoint("TOPLEFT", ts.card, "TOPLEFT", CARD_PAD, -10)

    ts.bodyFS = MakeFS(ts.card, 11, TH.textR, TH.textG, TH.textB, 0.90)
    ts.bodyFS:SetPoint("TOPLEFT", ts.card, "TOPLEFT", CARD_PAD, -28)
    ts.bodyFS:SetWidth(CARD_W - CARD_PAD * 2)
    ts.bodyFS:SetWordWrap(true); ts.bodyFS:SetJustifyH("LEFT")

    local NAV_H = 26
    local NAV_W = 68

    local function NavBtn(text)
        local b = CreateFrame("Button", nil, ts.card, "BackdropTemplate")
        b:SetSize(NAV_W, NAV_H)
        b:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1,
                        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        b:SetBackdropColor(TH.r2Bg[1], TH.r2Bg[2], TH.r2Bg[3], TH.r2Bg[4] or 0.90)
        b:SetBackdropBorderColor(TH.edge[1], TH.edge[2], TH.edge[3], 0.65)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
        b._fs = MakeFS(b, 11, TH.textR, TH.textG, TH.textB, 1)
        b._fs:SetPoint("CENTER"); b._fs:SetText(text)
        return b
    end

    ts.skipBtn = NavBtn(HelpText("EM_TOUR_SKIP"))
    ts.skipBtn:SetScript("OnClick", function() HUD.StopTour() end)

    ts.backBtn = NavBtn(HelpText("EM_TOUR_BACK"))
    ts.backBtn:SetScript("OnClick", function() HUD.TourStep(ts.step - 1) end)

    ts.nextBtn = NavBtn(HelpText("EM_TOUR_NEXT"))
    ts.nextBtn:SetScript("OnClick", function()
        local steps = GetTourSteps()
        if ts.step >= #steps then
            HUD.StopTour()
        else
            HUD.TourStep(ts.step + 1)
        end
    end)

    return ts
end

local function PositionMask(ts, tgt)
    local uiW, uiH = UIParent:GetWidth(), UIParent:GetHeight()
    local m1, m2, m3, m4 = ts.masks[1], ts.masks[2], ts.masks[3], ts.masks[4]

    if not tgt then
        m1:ClearAllPoints(); m1:SetAllPoints(UIParent); m1:Show()
        m2:Hide(); m3:Hide(); m4:Hide()
        ts.ring:Hide()
        return
    end

    local sl = tgt:GetLeft() or 0
    local sr = tgt:GetRight() or 0
    local st = tgt:GetTop() or 0
    local sb = tgt:GetBottom() or 0
    local ratio = tgt:GetEffectiveScale() / UIParent:GetEffectiveScale()
    sl = sl * ratio - SPOT_PAD
    sr = sr * ratio + SPOT_PAD
    st = st * ratio + SPOT_PAD
    sb = sb * ratio - SPOT_PAD

    m1:ClearAllPoints()
    m1:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    m1:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", uiW, -(uiH - st))
    m1:Show()

    m2:ClearAllPoints()
    m2:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -(uiH - sb))
    m2:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
    m2:Show()

    m3:ClearAllPoints()
    m3:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -(uiH - st))
    m3:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", sl, -(uiH - sb))
    m3:Show()

    m4:ClearAllPoints()
    m4:SetPoint("TOPLEFT", UIParent, "TOPLEFT", sr, -(uiH - st))
    m4:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", uiW, -(uiH - sb))
    m4:Show()

    ts.ring:ClearAllPoints()
    ts.ring:SetPoint("TOPLEFT", UIParent, "TOPLEFT", sl, -(uiH - st))
    ts.ring:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", sr, -(uiH - sb))
    ts.ring:Show()
end

local function PositionCard(ts, tgt, anchorHint)
    local card = ts.card
    card:ClearAllPoints()

    if not tgt or anchorHint == "CENTER" then
        card:SetPoint("CENTER", UIParent, "CENTER", 0, -20)
        return
    end

    local ratio = tgt:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local uiH = UIParent:GetHeight()
    local t = (tgt:GetTop() or 0) * ratio
    local b = (tgt:GetBottom() or 0) * ratio
    local cx = ((tgt:GetLeft() or 0) + (tgt:GetRight() or 0)) * 0.5 * ratio

    if (uiH - t) < uiH * 0.3 then
        card:SetPoint("TOP", UIParent, "TOPLEFT", cx, -(uiH - b) - 14)
    else
        card:SetPoint("BOTTOM", UIParent, "TOPLEFT", cx, (uiH - t) + 14)
    end
end

function HUD.TourStep(idx)
    local ts = EnsureTourFrames()
    local steps = GetTourSteps()
    if idx < 1 then idx = 1 end
    if idx > #steps then idx = #steps end
    ts.step = idx

    local s = steps[idx]
    local tgt = s.target and s.target() or nil

    PositionMask(ts, tgt)
    PositionCard(ts, tgt, s.anchor)

    ts.titleFS:SetText(s.title)
    ts.bodyFS:SetText(s.body)
    ts.stepFS:SetText(HelpText("EM_TOUR_STEP"):format(idx, #steps))

    local bH = ts.bodyFS:GetStringHeight() or 14
    ts.card:SetHeight(28 + bH + 12 + 26 + 12)

    ts.skipBtn:ClearAllPoints()
    ts.skipBtn:SetPoint("BOTTOMLEFT", ts.card, "BOTTOMLEFT", CARD_PAD, 10)

    ts.backBtn:ClearAllPoints()
    ts.nextBtn:ClearAllPoints()
    ts.nextBtn:SetPoint("BOTTOMRIGHT", ts.card, "BOTTOMRIGHT", -CARD_PAD, 10)
    ts.backBtn:SetPoint("RIGHT", ts.nextBtn, "LEFT", -6, 0)

    if idx <= 1 then ts.backBtn:Hide() else ts.backBtn:Show() end

    local isLast = idx >= #steps
    ts.nextBtn._fs:SetText(isLast and HelpText("EM_TOUR_DONE") or HelpText("EM_TOUR_NEXT"))
    if isLast then
        ts.nextBtn._fs:SetTextColor(TH.onR, TH.onG, TH.onB, 1)
    else
        ts.nextBtn._fs:SetTextColor(TH.textR, TH.textG, TH.textB, 1)
    end

    ts.card:Show()
end

function HUD.StartTour()
    local ts = EnsureTourFrames()
    for i = 1, 4 do ts.masks[i]:Show() end
    HUD.TourStep(1)
end

function HUD.StopTour()
    if not tourState then return end
    for i = 1, 4 do tourState.masks[i]:Hide() end
    tourState.ring:Hide()
    tourState.card:Hide()
    tourState.step = 0
end

local function EnsureHUD()
    if hudFrame then return end
    RefreshHUDTheme()

    --- --- ROW 1 ---
    hudFrame = CreateFrame("Frame", "MSUF_EM2_HUD", UIParent, "BackdropTemplate")
    hudFrame:SetFrameStrata("FULLSCREEN"); hudFrame:SetFrameLevel(100)
    hudFrame:SetHeight(R1_H)
    hudFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    hudFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    hudFrame:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=0,right=0,top=0,bottom=0} })
    hudFrame:SetBackdropColor(unpack(TH.r1Bg))
    hudFrame:SetBackdropBorderColor(unpack(TH.edge))
    ApplyHUDMaterial(hudFrame, "status")
    hudFrame:EnableMouse(true); hudFrame:Hide()

    local title = MakeFS(hudFrame, 11, TH.titleR, TH.titleG, TH.titleB, 0.50)
    title:SetPoint("LEFT", hudFrame, "LEFT", 14, 0)
    title:SetText(HelpText("EDIT MODE"))

    --- --- Prominent HELP button ---
    helpBtn = CreateFrame("Button", nil, hudFrame, "BackdropTemplate")
    helpBtn:SetSize(72, 26)
    helpBtn:SetPoint("LEFT", title, "RIGHT", 10, 0)
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

        local lbl = MakeFS(helpBtn, 12, TH.onR, TH.onG, TH.onB, 1)
        lbl:SetPoint("CENTER", 0, 0); lbl:SetText(HelpText("EM_HELP_BTN"))
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
        local panel = EnsureTutorialPanel()
        if panel:IsShown() then panel:Hide() else panel:Show() end
    end)
    helpBtn:SetScript("OnEnter", function(self)
        if self._pulse then self._pulse:Stop() end
        self:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -6)
        GameTooltip:SetText(HelpText("EM_HELP_BTN_TIP"), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    helpBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    --- Right-side: Cancel All | Exit
    exitBtn = MakeBtn(hudFrame, "Exit", 48, BTN_H, 12, function()
        if EM2.State then EM2.State.Exit("hud_exit") end
    end)
    exitBtn:SetPoint("RIGHT", hudFrame, "RIGHT", -12, 0)
    exitBtn._label:SetTextColor(TH.exitR, TH.exitG, TH.exitB, 1)
    exitBtn._dot:Hide()
    SetTip(exitBtn, "Lock positions and exit Edit Mode.")

    local rSep = MakeSep(hudFrame, BTN_H)
    rSep:SetPoint("RIGHT", exitBtn, "LEFT", -BTN_GAP, 0)

    cancelAllBtn = MakeBtn(hudFrame, "Cancel All", 78, BTN_H, 12, function()
        if not EM2.State or not EM2.State.CancelAll then return end
        local cf = _G["MSUF_EM2_CancelConfirm"]
        if cf then cf:Show(); return end
        cf = CreateFrame("Frame", "MSUF_EM2_CancelConfirm", UIParent, "BackdropTemplate")
        cf:SetSize(322, 118)
        cf:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        cf:SetFrameStrata("TOOLTIP"); cf:SetFrameLevel(999)
        cf:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1} })
        cf:SetBackdropColor(TH.r1Bg[1], TH.r1Bg[2], TH.r1Bg[3], TH.r1Bg[4] or 0.97)
        cf:SetBackdropBorderColor(TH.edge[1], TH.edge[2], TH.edge[3], 0.90)
        ApplyHUDMaterial(cf, "popup")
        cf:SetBackdropBorderColor(TH.edge[1], TH.edge[2], TH.edge[3], 0.90)
        cf:EnableMouse(true)
        local msg = MakeFS(cf, 13, TH.textR, TH.textG, TH.textB, 1)
        msg:SetPoint("TOP", cf, "TOP", 0, -24)
        msg:SetText(HelpText("Discard all changes and exit?"))
        local function ConfBtn(text, xOff, role, onClick)
            local ui = SharedUI()
            local b = ui and ui.Button and ui.Button(cf, HelpText(text), 112, 30, {
                align = "CENTER",
                skipHistory = true,
                variant = role == "danger" and "danger" or nil,
                onClick = onClick,
            }) or CreateFrame("Button", nil, cf, "BackdropTemplate")
            b:SetSize(112, 30)
            b:SetPoint("BOTTOM", cf, "BOTTOM", xOff, 18)
            if ui and ui.ApplyButtonRole then ui.ApplyButtonRole(b, role or "normal") end
            if not (ui and ui.Button) then
                b:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1 })
                b:SetBackdropColor(TH.r2Bg[1], TH.r2Bg[2], TH.r2Bg[3], TH.r2Bg[4] or 0.90)
                b:SetBackdropBorderColor(TH.edge[1], TH.edge[2], TH.edge[3], 0.65)
                local hl = b:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
                local fs = MakeFS(b, 12, TH.textR, TH.textG, TH.textB, 1)
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
    cancelAllBtn:SetPoint("RIGHT", rSep, "LEFT", -BTN_GAP, 0)
    cancelAllBtn._label:SetTextColor(TH.warnR, TH.warnG, TH.warnB, 0.90)
    cancelAllBtn._dot:Hide()
    SetTip(cancelAllBtn, "Discard ALL changes made in Edit Mode\nand restore settings to the state\nbefore Edit Mode was opened.")

    --- Center controls: grouped by task so the HUD scans as Preview | Layout | Tools.
    local c1 = CreateFrame("Frame", nil, hudFrame)
    c1:SetSize(1, CLUSTER_H); c1:SetPoint("CENTER", hudFrame, "CENTER", 0, 0)
    local r1 = {}

    local previewCluster, previewItems = AddCluster(r1, c1, "Preview", CLUSTER_H, true)
    previewBtn = AddRowButton(previewItems, previewCluster, "Preview", 64, CLUSTER_BTN_H, 11, function()
        ExportPublic("MSUF_UnitPreviewActive", not (_G.MSUF_UnitPreviewActive and true or false))
        if _G.MSUF_SyncAllUnitPreviews then _G.MSUF_SyncAllUnitPreviews() end
        SetActive(previewBtn, _G.MSUF_UnitPreviewActive)
        HUD.SetStatus(HelpText(_G.MSUF_UnitPreviewActive and "EM_PREVIEW_ON" or "EM_PREVIEW_OFF"), "info")
    end, "Show placeholder data on unitframes\nwithout real units (target, focus, etc.)")

    previewAddonSlot = CreateFrame("Frame", "MSUF_EM2_HUD_PreviewAddonSlot", previewCluster)
    previewAddonSlot:SetSize(62, CLUSTER_BTN_H)
    previewItems[#previewItems+1] = previewAddonSlot

    previewAnimBtn = AddRowButton(previewItems, previewCluster, "Motion", 58, CLUSTER_BTN_H, 11, function()
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

    auraBtn = AddRowButton(previewItems, previewCluster, "Auras", 52, CLUSTER_BTN_H, 11, function()
        local db = _G.MSUF_DB; if not db then return end
        local a2 = db.auras3; if not a2 then return end
        local sh = a2.shared; if not sh then return end
        sh.showInEditMode = not (sh.showInEditMode and true or false)
        SetActive(auraBtn, sh.showInEditMode)
        local a3 = MSUF and MSUF.MSUF_Auras3
        if a3 and type(a3.RefreshAll) == "function" then
            a3.RefreshAll()
        elseif a3 and type(a3.RefreshEditPreview) == "function" then
            a3.RefreshEditPreview()
        end
        HUD.SetStatus(HelpText(sh.showInEditMode and "EM_AURAS_ON" or "EM_AURAS_OFF"), "info")
    end, "Toggle aura preview icons\nand aura mover boxes.")
    FinishCluster(previewCluster, previewItems, CLUSTER_H, -6)

    local layoutCluster, layoutItems = AddCluster(r1, c1, "Layout", CLUSTER_H, true)
    snapToggle = AddRowButton(layoutItems, layoutCluster, "Snap", 48, CLUSTER_BTN_H, 11, function()
        if EM2.Snap then
            local on = not EM2.Snap.IsEnabled()
            EM2.Snap.SetEnabled(on); SetActive(snapToggle, on)
            HUD.SetStatus(HelpText(on and "EM_SNAP_ON" or "EM_SNAP_OFF"), "info")
        end
    end, "Snap frames to edges of\nother frames while dragging.")

    resetBtn = AddRowButton(layoutItems, layoutCluster, "Reset", 52, CLUSTER_BTN_H, 11, function()
        HUD.ResetCurrentPosition()
    end, "Reset the selected frame position.\nSize stays unchanged.")
    FinishCluster(layoutCluster, layoutItems, CLUSTER_H, -6)

    local linksCluster, linksItems = AddCluster(r1, c1, "Tools", CLUSTER_H, true)
    settingsBtn = AddRowButton(linksItems, linksCluster, "Settings", 66, CLUSTER_BTN_H, 11, function()
        HUD.OpenSelectedSettings()
    end, "Open Menu2 at the selected\nframe or component settings.")

    cdmBtn = AddRowButton(linksItems, linksCluster, "Cooldown", 72, CLUSTER_BTN_H, 11, function()
        local db = _G.MSUF_DB; if not db then return end
        db.general = db.general or {}
        db.general.anchorToCooldown = not (db.general.anchorToCooldown and true or false)
        SetActive(cdmBtn, db.general.anchorToCooldown)
        ApplyAllSettingsSafe()
        HUD.SetStatus(HelpText(db.general.anchorToCooldown and "EM_CDM_ON" or "EM_CDM_OFF"), "info")
        C_Timer.After(0.1, function()
            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
            if _G.MSUF_EM2_ReforcePreviewFrames then _G.MSUF_EM2_ReforcePreviewFrames() end
        end)
    end, "Anchor all unitframes to the\nEssential Cooldown Manager.")

    anchorBtn = AddRowButton(linksItems, linksCluster, "Anchor", 58, CLUSTER_BTN_H, 11, function()
        local ov = type(_G.MSUF_EnsureAnchorPicker) == "function" and _G.MSUF_EnsureAnchorPicker()
        if not ov then return end
        ov._onPick = function(frameName)
            local db = _G.MSUF_DB; if not db then return end
            db.general = db.general or {}
            db.general.anchorName = frameName
            db.general.anchorToCooldown = false
            SetActive(cdmBtn, false)
            ApplyAllSettingsSafe()
            HUD.SetStatus(HelpText("EM_ANCHOR_SET") .. ": " .. tostring(frameName or ""), "ok")
            C_Timer.After(0.1, function()
                if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
            end)
        end
        ov:Show()
    end, "Pick any frame as global anchor\nfor all unitframes.\nOverrides CDM anchor.")
    FinishCluster(linksCluster, linksItems, CLUSTER_H, -6)

    LayoutCenter(c1, r1, CLUSTER_GAP, SEP_W)

    --- --- ROW 2 ---
    row2Frame = CreateFrame("Frame", "MSUF_EM2_HUD_Row2", hudFrame, "BackdropTemplate")
    row2Frame:SetHeight(R2_H)
    row2Frame:SetPoint("TOPLEFT", hudFrame, "BOTTOMLEFT", 0, 0)
    row2Frame:SetPoint("TOPRIGHT", hudFrame, "BOTTOMRIGHT", 0, 0)
    row2Frame:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=0,right=0,top=0,bottom=0} })
    row2Frame:SetBackdropColor(unpack(TH.r2Bg))
    row2Frame:SetBackdropBorderColor(unpack(TH.edge))
    ApplyHUDMaterial(row2Frame, "status")
    row2Frame:EnableMouse(true)

    selectionFS = MakeFS(row2Frame, 11, TH.textR, TH.textG, TH.textB, 0.88)
    selectionFS:SetPoint("LEFT", row2Frame, "LEFT", 14, 0)
    selectionFS:SetWidth(420)
    selectionFS:SetJustifyH("LEFT")
    selectionFS:SetText("")

    hintFS = MakeFS(row2Frame, 11, TH.mutedR, TH.mutedG, TH.mutedB, 0.78)
    hintFS:SetPoint("RIGHT", row2Frame, "RIGHT", -14, 0)
    hintFS:SetWidth(420)
    hintFS:SetJustifyH("RIGHT")
    hintFS:SetText("")

    local c2 = CreateFrame("Frame", nil, row2Frame)
    c2:SetSize(1, BTN_H2); c2:SetPoint("CENTER", row2Frame, "CENTER", 0, 0)
    local r2 = {}

    local historyCluster, historyItems = AddCluster(r2, c2, nil, BTN_H2 + 4, false)
    undoBtn = AddRowButton(historyItems, historyCluster, "", 42, BTN_H2, 11, function()
        if _G.MSUF_EM_UndoUndo then _G.MSUF_EM_UndoUndo() end
        HUD.RefreshControls()
    end, "Undo last position change.")
    ExportPublic("MSUF_EditModeUndoBtn", undoBtn)
    AttachHistoryIcon(undoBtn, MEDIA .. "msuf_history_undo_red.png")

    redoBtn = AddRowButton(historyItems, historyCluster, "", 42, BTN_H2, 11, function()
        if _G.MSUF_EM_UndoRedo then _G.MSUF_EM_UndoRedo() end
        HUD.RefreshControls()
    end, "Redo last undone change.")
    ExportPublic("MSUF_EditModeRedoBtn", redoBtn)
    AttachHistoryIcon(redoBtn, MEDIA .. "msuf_history_redo_green.png")
    FinishCluster(historyCluster, historyItems, BTN_H2 + 4, 0)

    local gridCluster, gridItems = AddCluster(r2, c2, nil, BTN_H2 + 4, false)
    do
        gridWidget, stepFS = AddAdjustWidget(gridItems, gridCluster, 80, BTN_H2, true, function(_, d)
            if not EM2.Grid then return end
            EM2.Grid.SetGridStep(max(4, min(80, EM2.Grid.GetGridStep() + d * 4)))
            HUD.RefreshControls()
        end, function(_, button)
            if button ~= "LeftButton" or not EM2.Grid or not EM2.Grid.ToggleEnabled then return end
            EM2.Grid.ToggleEnabled()
            HUD.SetStatus(HelpText((not EM2.Grid.GetEnabled or EM2.Grid.GetEnabled()) and "EM_GRID_ON" or "EM_GRID_OFF"), "info")
            HUD.RefreshControls()
        end, "Left-click to toggle grid lines.\nScroll to adjust spacing.")
    end

    do
        bgWidget, alphaFS = AddAdjustWidget(gridItems, gridCluster, 74, BTN_H2, false, function(_, d)
            if not EM2.Grid then return end
            EM2.Grid.SetBgAlpha(max(0, min(1, EM2.Grid.GetBgAlpha() + d * 0.05)))
            HUD.RefreshControls()
        end, nil, "Background overlay opacity.\nScroll to adjust.")
    end
    FinishCluster(gridCluster, gridItems, BTN_H2 + 4, 0)

    LayoutCenter(c2, r2, CLUSTER_GAP, SEP_W)
end

function HUD.RefreshUnitSelector()
    HUD.RefreshControls()
end

function HUD.RefreshControls(force)
    if not force and hudFrame and hudFrame.IsShown and not hudFrame:IsShown() then return end
    if selectionFS then
        local text = SelectionSummary()
        if selectionLastText ~= text then
            selectionFS:SetText(text)
            selectionLastText = text
        end
    end
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
            SetHint(DefaultHintText(), TH.mutedR, TH.mutedG, TH.mutedB, 0.78)
        end
    end
    if alphaFS and EM2.Grid then alphaFS:SetText(HelpText("BG") .. " " .. floor(EM2.Grid.GetBgAlpha() * 100 + 0.5) .. "%") end
    if stepFS and EM2.Grid then
        local enabled = not EM2.Grid.GetEnabled or EM2.Grid.GetEnabled()
        stepFS:SetText(HelpText("Grid") .. " " .. floor(EM2.Grid.GetGridStep()) .. "px")
        if enabled then
            stepFS:SetTextColor(TH.okR, TH.okG, TH.okB, 0.95)
            if gridWidget and gridWidget._stateBg then gridWidget._stateBg:SetColorTexture(TH.okR, TH.okG, TH.okB, 0.18) end
        else
            stepFS:SetTextColor(TH.exitR, TH.exitG, TH.exitB, 0.95)
            if gridWidget and gridWidget._stateBg then gridWidget._stateBg:SetColorTexture(TH.exitR, TH.exitG, TH.exitB, 0.20) end
        end
    end
    if snapToggle and EM2.Snap then SetActive(snapToggle, EM2.Snap.IsEnabled()) end
    if resetBtn and resetBtn._label then
        local key = CurrentSelectionKey()
        local canReset = key and ((UNIT_KEYS[key] == true) or (GROUP_KEY_TO_KIND[key] ~= nil)) or false
        resetBtn:SetAlpha(canReset and 1 or 0.45)
        resetBtn._label:SetTextColor(
            canReset and TH.textR or TH.offR,
            canReset and TH.textG or TH.offG,
            canReset and TH.textB or TH.offB,
            canReset and 0.92 or 0.55
        )
    end
    if settingsBtn and settingsBtn._label then
        local key = CurrentFocusSelection()
        local canOpen = key ~= nil
        settingsBtn:SetAlpha(canOpen and 1 or 0.45)
        settingsBtn._label:SetTextColor(
            canOpen and TH.textR or TH.offR,
            canOpen and TH.textG or TH.offG,
            canOpen and TH.textB or TH.offB,
            canOpen and 0.92 or 0.55
        )
    end
    RegisterPreviewAnimationRefreshOwner()
    if previewBtn then SetActive(previewBtn, _G.MSUF_UnitPreviewActive and true or false) end
    if previewAnimBtn then
        local active = type(_G.MSUF_IsPreviewAnimationEnabled) == "function" and _G.MSUF_IsPreviewAnimationEnabled() == true
        SetActive(previewAnimBtn, active)
    end
    if cdmBtn then
        local db = _G.MSUF_DB
        SetActive(cdmBtn, db and db.general and db.general.anchorToCooldown and true or false)
    end
    if auraBtn then
        local db = _G.MSUF_DB; local a2 = db and db.auras3; local sh = a2 and a2.shared
        SetActive(auraBtn, sh and sh.showInEditMode and true or false)
    end
    local canUndo = EM2.Undo and EM2.Undo.CanUndo() or false
    local canRedo = EM2.Undo and EM2.Undo.CanRedo() or false
    if undoBtn and undoBtn._historyIcon then
        undoBtn._historyIcon:SetAlpha(canUndo and 1 or 0.35)
    end
    if redoBtn and redoBtn._historyIcon then
        redoBtn._historyIcon:SetAlpha(canRedo and 1 or 0.35)
    end
end

function HUD.Show()
    EnsureHUD(); HUD.RefreshControls(true)
    hudFrame:Show(); if row2Frame then row2Frame:Show() end
    if helpBtn and helpBtn._pulse then helpBtn._pulse:Play() end

    local db = _G.MSUF_DB
    if db then
        db.general = db.general or {}
        if not db.general.emTutorialSeen then
            db.general.emTutorialSeen = true
            C_Timer.After(0.3, function()
                if HUD.IsShown() then
                    local panel = EnsureTutorialPanel()
                    if panel and not panel:IsShown() then panel:Show() end
                end
            end)
        end
    end
end

function HUD.Hide()
    HUD.StopTour()
    if tutorialPanel then tutorialPanel:Hide() end
    local cf = _G["MSUF_EM2_CancelConfirm"]; if cf then cf:Hide() end
    if helpBtn and helpBtn._pulse then helpBtn._pulse:Stop() end
    if row2Frame then row2Frame:Hide() end; if hudFrame then hudFrame:Hide() end
end

function HUD.IsShown() return hudFrame and hudFrame:IsShown() or false end

local function MSUF_EM2_SetHUDStatus(text, kind, seconds)
    return HUD.SetStatus(text, kind, seconds)
end
ExportPublic("MSUF_EM2_SetHUDStatus", MSUF_EM2_SetHUDStatus)

end

ExportPublic("MSUF_InstallEditModeHUD", InstallEditModeHUD)
