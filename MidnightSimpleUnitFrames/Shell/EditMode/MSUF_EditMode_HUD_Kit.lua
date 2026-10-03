--- EditMode/MSUF_EditMode_HUD_Kit.lua - Edit Mode toolbar theme and widget kit
--- Theme colours, the toolbar dimensions, buttons, clusters with their
--- horizontal and vertical layouts, tooltips and the HelpText lookup.
--- First of the toolbar files in MSUF_EditMode.xml (Kit, Selection, Dock,
--- Picker, then the toolbar in MSUF_EditMode_HUD.lua). It creates EM2.HUD
--- and the dock view EM2.HUDDock that the others extend.
local _, MSUF = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

EM2.HUD = {}
local Kit = {}
EM2.HUDKit = Kit

local L     = (MSUF and MSUF.L) or _G.MSUF_L or setmetatable({}, { __index = function(_, k) return k end })
local FONT  = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
local W8    = "Interface/Buttons/WHITE8X8"
local max = math.max
local U = EM2.Util or {}
local SharedUI = U.SharedUI
local function Space(role, fallback)
    local ui = SharedUI and SharedUI()
    return ui and ui.Space and ui.Space(role, fallback) or fallback
end

local DockUI = { PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region,
    ...) end return region end }
EM2.HUDDock = DockUI

local function HelpText(key)
    if type(key) ~= "string" then return key end
    local value = type(L) == "table" and rawget(L, key) or nil
    if type(value) == "string" and value ~= "" and value ~= key then
        return value
    end
    return key
end

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
    local fs = DockUI.PixelLayoutRegion(p:CreateFontString(nil, "OVERLAY"))
    local ui = SharedUI()
    if ui and ui.ApplyFontRole then
        ui.ApplyFontRole(fs, fontRole or "body", FONT, "")
    else
        local size = ui and ui.FontSize and ui.FontSize(fontRole or "body") or 13
        fs:SetFont(FONT, size, "")
    end
    fs:SetShadowOffset(1, -1)
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.35) end
    fs:SetTextColor(r or 1, g or 1, b or 1, a or 1)
    return fs
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
    w = w or (#text * 8 + 18)
    h = h or BTN_H
    local ui = (type(MSUF) == "table" and MSUF.UI) or _G.MSUF_UI
    local btn = ui and ui.Button and ui.Button(parent, HelpText(text), w, h, {
        align = "CENTER",
        skipHistory = true,
        onClick = onClick,
    }) or DockUI.PixelLayoutRegion(CreateFrame("Button", nil, parent))
    btn:SetSize(w, h)
    local label = btn._msuf2Label or btn._label
    if not label then
        local hl = DockUI.PixelLayoutRegion(btn:CreateTexture(nil, "HIGHLIGHT"))
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
        label = MakeFS(btn, fontRole or "body", TH.textR, TH.textG, TH.textB, 0.92)
        label:SetPoint("CENTER")
        label:SetText(HelpText(text))
    elseif ui and ui.ApplyFontRole then
        --- Shared buttons build their label from a Blizzard font object, which
        --- carries Blizzard's face and ignores the configured menu font that
        --- every MakeFS string in this toolbar already follows.  Re-apply the
        --- role so button text matches the labels next to it.
        ui.ApplyFontRole(label, fontRole or "body", FONT, "")
    end
    btn._label = label
    local dot = DockUI.PixelLayoutRegion(btn:CreateTexture(nil, "OVERLAY"))
    dot:SetSize(w - 8, 2)
    dot:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)
    dot:SetColorTexture(TH.onR, TH.onG, TH.onB, 0.90)
    dot:Hide()
    btn._dot = dot
    if onClick and not (ui and ui.Button) then btn:SetScript("OnClick", onClick) end
    AttachHoverTextAccent(btn, label)
    return btn
end

local function AttachHistoryIcon(btn, texturePath)
    if not btn then return end
    if btn._label then btn._label:Hide() end
    if btn._dot then btn._dot:Hide() end
    local icon = DockUI.PixelLayoutRegion(btn:CreateTexture(nil, "ARTWORK", nil, 5))
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
    local f = DockUI.PixelLayoutRegion(CreateFrame("Frame", nil, parent, "BackdropTemplate"))
    f:SetSize(1, height or CLUSTER_H)
    DockUI.PixelLayoutRegion(f, "SetBackdrop", { bgFile = W8, edgeFile = W8, edgeSize = 1,
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
    local f = DockUI.PixelLayoutRegion(CreateFrame("Frame", nil, parent))
    f:SetSize(width, height)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    if withStateBg then
        local stateBg = DockUI.PixelLayoutRegion(f:CreateTexture(nil, "BACKGROUND"))
        stateBg:SetAllPoints()
        stateBg:SetColorTexture(0, 0, 0, 0)
        f._stateBg = stateBg
    end
    local fs = MakeFS(f, "caption", TH.mutedR, TH.mutedG, TH.mutedB, 0.80)
    fs:SetPoint("CENTER")
    local hl = DockUI.PixelLayoutRegion(f:CreateTexture(nil, "HIGHLIGHT"))
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.04)
    if onMouseUp then f:SetScript("OnMouseUp", onMouseUp) end
    if onMouseWheel then f:SetScript("OnMouseWheel", onMouseWheel) end
    if tip then SetTip(f, tip) end
    --- After SetTip: it installs OnEnter/OnLeave with SetScript, which would drop
    --- an earlier hook chain.
    AttachHoverTextAccent(f, fs)
    row[#row + 1] = f
    return f, fs
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

--- The other toolbar files read the kit through EM2.HUDKit.
Kit.L, Kit.FONT, Kit.W8, Kit.SharedUI, Kit.HelpText, Kit.TH = L, FONT, W8, SharedUI, HelpText, TH
Kit.BTN_H, Kit.BTN_H2, Kit.CLUSTER_H, Kit.CLUSTER_BTN_H = BTN_H, BTN_H2, CLUSTER_H, CLUSTER_BTN_H
Kit.DOCK_HORIZONTAL_W, Kit.DOCK_HORIZONTAL_H, Kit.DOCK_VERTICAL_W = DOCK_HORIZONTAL_W, DOCK_HORIZONTAL_H, DOCK_VERTICAL_W
Kit.DOCK_EDGE_DEFAULT, Kit.DOCK_SNAP_EDGE_PX, Kit.DOCK_ALLOWED = DOCK_EDGE_DEFAULT, DOCK_SNAP_EDGE_PX, DOCK_ALLOWED
Kit.RefreshHUDTheme, Kit.ApplyHUDMaterial, Kit.MakeFS, Kit.MakeBtn = RefreshHUDTheme, ApplyHUDMaterial, MakeFS, MakeBtn
Kit.SetActive, Kit.SetControlEnabled, Kit.SetHistoryEnabled = SetActive, SetControlEnabled, SetHistoryEnabled
Kit.SetTip, Kit.AttachHistoryIcon, Kit.ApplyButtonRole = SetTip, AttachHistoryIcon, ApplyButtonRole
Kit.AddCluster, Kit.FinishCluster, Kit.AddRowButton, Kit.AddAdjustWidget = AddCluster, FinishCluster, AddRowButton, AddAdjustWidget
Kit.LayoutClusterRow, Kit.LayoutClusterColumn = LayoutClusterRow, LayoutClusterColumn
