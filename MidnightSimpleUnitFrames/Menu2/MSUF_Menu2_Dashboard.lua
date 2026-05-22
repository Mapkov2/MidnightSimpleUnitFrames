local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local T = M.Theme
local W = M.Widgets

local floor = math.floor
local max = math.max
local min = math.min
local CreateFrame = _G.CreateFrame
local CreateColor = _G.CreateColor
local GameTooltip = _G.GameTooltip
local UIParent = _G.UIParent

local function GetBundledChangelog()
    local data = (type(ns) == "table" and ns.MSUF_Changelog) or _G.MSUF_Changelog
    if type(data) ~= "table" or type(data.entries) ~= "table" or type(data.entries[1]) ~= "table" then
        return nil
    end
    return data
end

local function BuildDashboardChangelog(parent, cardWidth, opts)
    opts = opts or {}
    local data = GetBundledChangelog()
    local sectionHeader = opts.sectionHeader == true
    local left, right = sectionHeader and 0 or 14, sectionHeader and 0 or 14
    local bodyLeft = opts.bodyLeft or (sectionHeader and 16 or left)
    local top = opts.top or -130
    local headerH = sectionHeader and 42 or 48
    local contentW = max(120, (cardWidth or 420) - left - right)
    local scrollW = max(80, (cardWidth or 420) - bodyLeft - 44)

    local function RawFont(parentFrame, template, text, color, bump)
        local fs = parentFrame:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
        if T.StyleFontString then
            T.StyleFontString(fs, color or T.colors.muted, bump or 0)
        elseif color and fs.SetTextColor then
            fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        end
        fs:SetText(tostring(text or ""))
        return fs
    end

    if not sectionHeader then
        local line = parent:CreateTexture(nil, "BORDER")
        line:SetPoint("TOPLEFT", parent, "TOPLEFT", left, top + 4)
        line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -right, top + 4)
        line:SetHeight(1)
        line:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.38)
    end

    local header = CreateFrame("Button", nil, parent)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", left, top)
    if sectionHeader then
        header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -right, top)
        header:SetHeight(headerH)
    else
        header:SetSize(contentW, headerH)
    end

    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints()
    headerBg:SetColorTexture(0, 0, 0, 0)

    local headerEdge = header:CreateTexture(nil, "BORDER")
    headerEdge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    headerEdge:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerEdge:SetHeight(1)
    headerEdge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.44)

    local hover = header:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.025)

    local arrow = header:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(10, 10)
    if sectionHeader then
        arrow:SetPoint("LEFT", header, "LEFT", 16, 0)
    else
        arrow:SetPoint("TOPRIGHT", header, "TOPRIGHT", -54, -9)
    end
    arrow:SetTexture(T.media.collapseArrow)

    local title = T.Font(header, "GameFontNormal", M.Tr(opts.title or "Changelog"), T.colors.text)
    if sectionHeader then
        title:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
        title:SetPoint("RIGHT", header, "RIGHT", -94, 0)
    else
        title:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -3)
        title:SetPoint("RIGHT", header, "RIGHT", -92, 0)
    end
    title:SetJustifyH("LEFT")

    local current = data and (data.currentVersion or (data.entries[1] and data.entries[1].version)) or nil
    local range = data and (data.rangeLabel or current or "") or M.Tr("No release notes bundled with this build.")
    local subtitle = RawFont(header, "GameFontDisableSmall", range, T.colors.dim, 0)
    if sectionHeader then
        subtitle:SetPoint("RIGHT", header, "RIGHT", -72, 0)
        subtitle:SetWidth(max(80, min(210, contentW - 190)))
        subtitle:SetJustifyH("RIGHT")
        subtitle:Hide()
    else
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
        subtitle:SetPoint("RIGHT", header, "RIGHT", -8, 0)
        subtitle:SetJustifyH("LEFT")
    end

    local hint = T.Font(header, "GameFontDisableSmall", "", T.colors.dim)
    if sectionHeader then
        hint:SetPoint("RIGHT", header, "RIGHT", -16, 0)
    else
        hint:SetPoint("TOPRIGHT", header, "TOPRIGHT", -8, -5)
    end
    hint:SetJustifyH("RIGHT")

    local summary = RawFont(parent, "GameFontHighlightSmall", "", T.colors.muted, 0)
    summary:SetPoint("TOPLEFT", parent, "TOPLEFT", bodyLeft + 10, top - headerH - 8)
    summary:SetWidth(max(80, (cardWidth or contentW) - bodyLeft - 28))
    summary:SetJustifyH("LEFT")
    if summary.SetWordWrap then summary:SetWordWrap(true) end

    if not data then
        header:EnableMouse(false)
        hint:SetText("")
        summary:SetText(M.Tr("No release notes bundled with this build."))
        if arrow.SetVertexColor then arrow:SetVertexColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.55) end
        return
    end

    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", bodyLeft + 2, top - headerH - 12)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -34, opts.bottom or 70)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(scrollW, 1)
    scroll:SetScrollChild(child)

    local y = -2
    local function AddText(text, fontObject, color, indent, gap, translate)
        local rawText = tostring(text or "")
        if translate and type(M.Tr) == "function" then
            rawText = M.Tr(rawText)
        end
        local fs = RawFont(child, fontObject or "GameFontHighlightSmall", rawText, color or T.colors.muted, 0)
        indent = indent or 0
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", indent, y)
        fs:SetWidth(max(40, scrollW - indent - 2))
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(true) end
        if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
        fs:SetText(rawText)
        local h = (fs.GetStringHeight and fs:GetStringHeight()) or 0
        if h < 10 then h = 12 end
        y = y - h - (gap or 4)
        return fs
    end

    local function AddBullet(text, dotColor, textColor)
        dotColor = dotColor or T.colors.accent
        textColor = textColor or T.colors.muted
        local dot = child:CreateTexture(nil, "ARTWORK")
        dot:SetSize(3, 3)
        dot:SetPoint("TOPLEFT", child, "TOPLEFT", 8, y - 6)
        dot:SetColorTexture(dotColor[1], dotColor[2], dotColor[3], 0.88)
        return AddText(text, "GameFontHighlightSmall", textColor, 18, 5, true)
    end

    local entries = data.entries
    local maxEntries = min(#entries, 4)
    for entryIndex = 1, maxEntries do
        local entry = entries[entryIndex]
        if type(entry) == "table" then
            local version = tostring(entry.version or "")
            local date = tostring(entry.date or "")
            local heading = (date ~= "" and (version .. " - " .. date)) or version
            AddText(heading, "GameFontNormalSmall", T.colors.accent, 0, 8)

            local sections = entry.sections
            if type(sections) == "table" then
                for sectionIndex = 1, #sections do
                    local section = sections[sectionIndex]
                    if type(section) == "table" and type(section.bullets) == "table" and #section.bullets > 0 then
                        if sectionIndex > 1 then y = y - 3 end
                        local sectionTitle = tostring(section.title or "")
                        local isHighlights = sectionTitle == "Highlights"
                        AddText(sectionTitle, "GameFontNormalSmall", isHighlights and T.colors.accent or T.colors.accent2, 0, 4, true)
                        for bulletIndex = 1, #section.bullets do
                            AddBullet(
                                tostring(section.bullets[bulletIndex] or ""),
                                isHighlights and T.colors.accent2 or nil,
                                isHighlights and T.colors.text or nil
                            )
                        end
                    end
                end
            end
        end
    end

    child:SetHeight(max(1, math.abs(y) + 8))
    if T.StyleScrollFrame then T.StyleScrollFrame(scroll, parent) end

    local latest = entries[1]
    local sectionCount = 0
    if latest and type(latest.sections) == "table" then sectionCount = #latest.sections end
    local currentLabel = current or "Latest build"
    summary:SetText(M.Format(M.Tr("%s  -  %d sections. Click to view the bundled changelog."), currentLabel, sectionCount))

    local open = M.dashboardChangelogOpen == true
    local function PaintHeader(isOpen)
        if T.ApplyCollapseVisual then T.ApplyCollapseVisual(arrow, nil, isOpen) end
        if headerBg.SetColorTexture then
            headerBg:SetColorTexture(0, 0, 0, 0)
        end
        if headerEdge.SetColorTexture then
            headerEdge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], isOpen and 0.58 or 0.34)
        end
        hint:SetText(isOpen and M.Tr("Hide") or M.Tr("View"))
    end
    local function RefreshOpenState()
        M.dashboardChangelogOpen = open
        M.PersistMenuStateValue("dashboardChangelogOpen", open)
        scroll:SetShown(open)
        summary:SetShown((not open) and not opts.hideSummaryWhenClosed)
        PaintHeader(open)
        if open then
            if scroll._msuf2RefreshScrollBar then scroll:_msuf2RefreshScrollBar() end
        elseif scroll._msuf2ScrollBar then
            scroll._msuf2ScrollBar:Hide()
        end
    end

    header:SetScript("OnClick", function()
        open = not open
        RefreshOpenState()
        if type(opts.onToggle) == "function" then opts.onToggle(open) end
    end)
    header:SetScript("OnEnter", function()
        if headerBg.SetColorTexture then headerBg:SetColorTexture(1, 1, 1, 0.025) end
    end)
    header:SetScript("OnLeave", function()
        PaintHeader(open)
    end)
    RefreshOpenState()
end

local function BuildDashboardUX(ctx)
    local root = ctx.wrapper
    local width = ctx.width or 760
    local x0, y0, gap = 12, -12, 16
    local layoutW = max(1, width - x0)
    local sideBySide = layoutW >= 760
    local sideW = sideBySide and min(330, max(300, math.floor(layoutW * 0.31))) or layoutW
    local mainW = sideBySide and (layoutW - sideW - gap) or layoutW
    local sideX = sideBySide and (x0 + mainW + gap) or x0

    local function Card(parent, title, x, y, w, h, bg, border)
        local card = T.Panel(parent or root, nil, bg or T.colors.panel2, border or T.colors.cardBorder or T.colors.borderSoft)
        card:SetPoint("TOPLEFT", parent or root, "TOPLEFT", x, y)
        card:SetSize(w, h)
        if title and title ~= "" then
            local label = T.Font(card, "GameFontNormal", M.Tr(title), T.colors.text)
            label:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -14)
            card._msuf2Title = label
        end
        return card
    end

    local function SetDashboardGradient(texture, orientation, from, to)
        if not texture then return end
        from = from or { 1, 1, 1, 0 }
        to = to or { 1, 1, 1, 1 }
        local fromA = from[4] or 1
        local toA = to[4] or 1
        local media = T and T.media
        local horizontal = (orientation or "HORIZONTAL") == "HORIZONTAL"
        local path
        local color

        if horizontal then
            path = (toA >= fromA) and (media and media.gradHRev) or (media and media.gradH)
            color = (toA >= fromA) and to or from
        else
            path = (fromA >= toA) and (media and media.gradV) or (media and media.gradVRev)
            color = (fromA >= toA) and from or to
        end

        if path and path ~= "" then
            texture:SetTexture(path)
            texture:SetTexCoord(0, 1, 0, 1)
            if texture.SetVertexColor then
                texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
            end
        elseif texture.SetGradientAlpha then
            texture:SetTexture("Interface\\Buttons\\WHITE8X8")
            texture:SetGradientAlpha(orientation or "HORIZONTAL", from[1], from[2], from[3], fromA, to[1], to[2], to[3], toA)
        elseif texture.SetGradient and CreateColor then
            texture:SetTexture("Interface\\Buttons\\WHITE8X8")
            texture:SetGradient(orientation or "HORIZONTAL", CreateColor(from[1], from[2], from[3], fromA), CreateColor(to[1], to[2], to[3], toA))
        elseif texture.SetColorTexture then
            texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        end
    end

    local function ApplyDashboardHeroGradient(card, w, h)
        if not (card and card.CreateTexture) or card._msuf2DashboardHeroGradient then return end
        card._msuf2DashboardHeroGradient = true

        local wash = card:CreateTexture(nil, "BACKGROUND", nil, 1)
        wash:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        wash:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
        SetDashboardGradient(wash, "HORIZONTAL", { 0.020, 0.026, 0.064, 0.00 }, { 0.030, 0.210, 0.285, 0.16 })

        local top = card:CreateTexture(nil, "BACKGROUND", nil, 2)
        top:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        top:SetPoint("TOPRIGHT", card, "TOPRIGHT", -2, -2)
        top:SetHeight(max(54, min(96, floor((h or 190) * 0.42))))
        SetDashboardGradient(top, "VERTICAL", { 0.080, 0.320, 0.430, 0.08 }, { 0.020, 0.030, 0.070, 0.00 })

        local focus = card:CreateTexture(nil, "BACKGROUND", nil, 3)
        focus:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        focus:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
        SetDashboardGradient(focus, "HORIZONTAL", { 0.080, 0.420, 0.560, 0.00 }, { 0.080, 0.420, 0.560, 0.05 })
    end

    local function Button(parent, text, x, y, w, h, onClick, skin)
        local btn = T.Button(parent, M.Tr(text or ""), w, h or 24)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        if btn._msuf2Label then
            btn._msuf2Label:ClearAllPoints()
            btn._msuf2Label:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn._msuf2Label:SetJustifyH("CENTER")
        end
        if skin == "primary" and T.SkinPrimaryButton then T.SkinPrimaryButton(btn) end
        if skin == "danger" and T.SkinDangerButton then T.SkinDangerButton(btn) end
        if onClick then btn:SetScript("OnClick", onClick) end
        return btn
    end

    local function Kicker(parent, text, x, y, color)
        local fs = T.Font(parent, "GameFontDisableSmall", string.upper(M.Tr(text or "")), color or T.colors.accent)
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 16, y or -14)
        return fs
    end

    local function Pill(parent, text, x, y, w, color)
        local pill = T.Panel(parent, nil, { 0.055, 0.070, 0.135, 0.92 }, { 0.160, 0.220, 0.430, 0.70 })
        pill:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        pill:SetSize(w or 82, 20)
        local label = T.Font(pill, "GameFontDisableSmall", M.Tr(text or ""), color or T.colors.muted)
        label:SetPoint("CENTER", pill, "CENTER", 0, 0)
        label:SetJustifyH("CENTER")
        pill._msuf2Label = label
        return pill
    end

    local function AddTooltip(frame, title, text)
        if not (frame and frame.HookScript) then return end
        frame:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(M.Tr(title or ""), 1, 1, 1)
            if text and text ~= "" then GameTooltip:AddLine(M.Tr(text), 0.85, 0.85, 0.85, true) end
            GameTooltip:Show()
        end)
        frame:HookScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end

    local function MakeDashboardActionCard(card, title, tooltip, onClick, showArrow)
        if not (card and card.CreateTexture and card.HookScript) then return card end
        card:EnableMouse(true)

        local hover = card:CreateTexture(nil, "BORDER", nil, 4)
        hover:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        hover:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
        hover:SetColorTexture(0.240, 0.780, 0.940, 0.055)
        hover:Hide()
        card._msuf2DashboardActionHover = hover

        if showArrow then
            local arrow = T.Font(card, "GameFontNormal", ">", T.colors.dim)
            arrow:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -18)
            arrow:SetJustifyH("RIGHT")
            card._msuf2DashboardActionArrow = arrow
        end

        card:HookScript("OnEnter", function(self)
            if self._msuf2DashboardActionHover then self._msuf2DashboardActionHover:Show() end
            local arrow = self._msuf2DashboardActionArrow
            if arrow and arrow.SetTextColor then
                arrow:SetTextColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 1)
            end
        end)
        card:HookScript("OnLeave", function(self)
            if self._msuf2DashboardActionHover then self._msuf2DashboardActionHover:Hide() end
            local arrow = self._msuf2DashboardActionArrow
            if arrow and arrow.SetTextColor then
                arrow:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], T.colors.dim[4] or 1)
            end
        end)
        if onClick then card:SetScript("OnMouseUp", onClick) end
        AddTooltip(card, title, tooltip)
        return card
    end

    local function Select(pageKey)
        if M.SelectPage then M.SelectPage(pageKey) end
    end

    local function ToggleEditMode()
        local active = ((_G.MSUF_IsMSUFEditModeActive and _G.MSUF_IsMSUFEditModeActive()) or _G.MSUF_UnitEditModeActive) and true or false
        if (not active) and ((_G.InCombatLockdown and _G.InCombatLockdown()) or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) then
            if M.BlockCombatAction then M.BlockCombatAction() end
            if type(M.RefreshDashboardEditModeButton) == "function" then M.RefreshDashboardEditModeButton() end
            if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
            return
        end
        if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
            _G.MSUF_SetMSUFEditModeDirect(not active)
        end
        if type(M.RefreshMenuFramePriority) == "function" then M.RefreshMenuFramePriority() end
        if C_Timer and C_Timer.After and type(M.RefreshMenuFramePriority) == "function" then C_Timer.After(0, M.RefreshMenuFramePriority) end
        if type(M.RefreshDashboardEditModeButton) == "function" then M.RefreshDashboardEditModeButton() end
        if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
    end

    local function CopyWagoLink()
        if type(_G.MSUF_ShowCopyLink) == "function" then
            _G.MSUF_ShowCopyLink("Wago MSUF Profiles", "https://wago.io/search/imports/wow/msuf")
        end
    end

    local function ExportBackup()
        local fn = _G.MSUF_ExportSelectionToString
        if type(fn) == "function" then
            local ok, value = pcall(fn, "all")
            if ok and type(value) == "string" and value ~= "" and type(_G.MSUF_ShowCopyLink) == "function" then
                _G.MSUF_ShowCopyLink("MSUF Profile Backup", value)
                return
            end
        end
        Select("profiles")
    end

    local function DashboardGlobalState()
        _G.MSUF_GlobalDB = _G.MSUF_GlobalDB or {}
        local gdb = _G.MSUF_GlobalDB
        gdb.global = (type(gdb.global) == "table") and gdb.global or {}
        gdb.global.dashboard = (type(gdb.global.dashboard) == "table") and gdb.global.dashboard or {}
        return gdb.global.dashboard
    end

    local function ActiveProfileKey()
        local key = tostring(_G.MSUF_ActiveProfile or "Default")
        if key == "" then key = "Default" end
        return key
    end

    local function WagoBackupConfirmed()
        local dash = DashboardGlobalState()
        local byProfile = dash.wagoProfileBackupConfirmed
        return type(byProfile) == "table" and byProfile[ActiveProfileKey()] == true
    end

    local function SetWagoBackupConfirmed(confirmed)
        local dash = DashboardGlobalState()
        dash.wagoProfileBackupConfirmed = (type(dash.wagoProfileBackupConfirmed) == "table") and dash.wagoProfileBackupConfirmed or {}
        local byProfile = dash.wagoProfileBackupConfirmed
        if confirmed == true then
            byProfile[ActiveProfileKey()] = true
        else
            byProfile[ActiveProfileKey()] = nil
        end
    end

    local function RefreshDashboard()
        if M.InvalidatePage then M.InvalidatePage("home") end
        if M.SelectPage then M.SelectPage("home") end
    end

    local function ConfirmWagoBackup()
        if WagoBackupConfirmed() then return end

        local function accept()
            SetWagoBackupConfirmed(true)
            RefreshDashboard()
        end

        if _G.StaticPopupDialogs and _G.StaticPopup_Show then
            local popup = _G.StaticPopupDialogs.MSUF2_WAGO_PROFILE_BACKUP_CONFIRM or {
                text = "%s",
                button1 = _G.YES or "Yes",
                button2 = _G.NO or "No",
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
                OnAccept = accept,
            }
            popup.button1 = _G.YES or "Yes"
            popup.button2 = _G.NO or "No"
            popup.OnAccept = accept
            _G.StaticPopupDialogs.MSUF2_WAGO_PROFILE_BACKUP_CONFIRM = popup
            _G.StaticPopup_Show("MSUF2_WAGO_PROFILE_BACKUP_CONFIRM", M.Tr("Have you backed up this MSUF profile before using the Wago MSUF page?"))
            return
        end

        accept()
    end

    local function Percent(value, fallback)
        return math.floor(((tonumber(value) or fallback or 1) * 100) + 0.5)
    end

    local function Clamp(v, minV, maxV)
        v = tonumber(v) or minV
        if v < minV then return minV end
        if v > maxV then return maxV end
        return v
    end

    local function SnapPct(value, minPct, maxPct, stepPct)
        stepPct = stepPct or 1
        local pct = math.floor((tonumber(value) or 100) / stepPct + 0.5) * stepPct
        return Clamp(pct, minPct or 25, maxPct or 150)
    end

    local function SetSliderValueSafe(slider, value)
        if not (slider and slider.SetValue) then return end
        slider._msuf2Refreshing = true
        slider:SetValue(value)
        if slider.editBox and slider._msuf2FormatValue then slider.editBox:SetText(slider._msuf2FormatValue(value)) end
        if slider._msuf2UpdateFill then slider:_msuf2UpdateFill() end
        slider._msuf2Refreshing = nil
    end

    local function HideSliderValueBox(slider)
        if slider and slider.editBox then slider.editBox:Hide() end
        if slider and slider._msuf2StepButtons then
            for i = 1, #slider._msuf2StepButtons do
                slider._msuf2StepButtons[i]:Hide()
            end
        end
        if slider and slider._msuf2Title and slider._msuf2Title.SetFontObject then
            slider._msuf2Title:SetFontObject("GameFontHighlight")
        end
    end

    local function EnablePercentWheel(slider, minPct, maxPct, stepPct)
        if not slider then return end
        slider:EnableMouseWheel(true)
        slider:SetScript("OnMouseWheel", function(self, delta)
            if not delta then return end
            local value = tonumber((self.GetValue and self:GetValue()) or 100) or 100
            value = value + ((delta > 0) and stepPct or -stepPct)
            self:SetValue(SnapPct(value, minPct, maxPct, stepPct))
        end)
    end

    local function PixelScale()
        if type(_G.MSUF_GetPixelPerfectScale) == "function" then
            local ok, v = pcall(_G.MSUF_GetPixelPerfectScale)
            if ok and tonumber(v) then return Clamp(v, 0.3, 1.5) end
        end
        if type(GetPhysicalScreenSize) == "function" then
            local _, h = GetPhysicalScreenSize()
            h = tonumber(h)
            if h and h > 0 then return Clamp(768 / h, 0.3, 1.5) end
        end
        return 1
    end

    local function GlobalState()
        local g = M.GetGeneralDB()
        g.UIScale = (type(g.UIScale) == "table") and g.UIScale or { Enabled = false, Scale = 1 }
        local ui = g.UIScale
        ui.Enabled = ui.Enabled == true
        ui.Scale = Clamp(ui.Scale, 0.3, 1.5)
        return g, ui
    end

    local function HasMovedFramesInEditMode()
        local g = M.GetGeneralDB and M.GetGeneralDB()
        if type(g) == "table" and g.hasMovedFramesInEditMode == true then return true end
        local st = rawget(_G, "MSUF_EditState")
        if type(st) == "table" and st.hasMovedFramesInEditMode == true then return true end

        local db = M.EnsureDB and M.EnsureDB() or _G.MSUF_DB
        if type(db) ~= "table" then return false end
        local defaults = {
            player = { -256, -180 },
            target = { 320, -180 },
            focus = { -260, -300 },
            targettarget = { 220, -300 },
            pet = { -275, -250 },
            boss = { 360, 230 },
            gf_party = { -400, 0 },
            gf_raid = { -500, 0 },
            gf_mythicraid = { -500, 0 },
        }
        for key, def in pairs(defaults) do
            local conf = db[key]
            if type(conf) == "table" then
                local x, y = tonumber(conf.offsetX), tonumber(conf.offsetY)
                if x and y and (math.abs(x - def[1]) > 0.5 or math.abs(y - def[2]) > 0.5) then
                    if type(g) == "table" then g.hasMovedFramesInEditMode = true end
                    return true
                end
            end
        end
        return false
    end

    local compactHeader = layoutW < 620
    local tinyHeader = layoutW < 430
    local headerH = tinyHeader and 184 or (compactHeader and 150 or 92)
    local header = Card(root, "Dashboard", x0, y0, layoutW, headerH, { 0.055, 0.070, 0.145, 0.82 }, T.colors.border)
    local actionX = compactHeader and 16 or max(16, layoutW - 456)
    local textW = compactHeader and (layoutW - 32) or max(110, actionX - 34)
    W.Text(header, "A calmer setup command center: start with movement, frames, group frames, or a safe profile import.", 16, -42, textW, T.colors.muted)
    local editW = tinyHeader and (layoutW - 32) or (compactHeader and floor((layoutW - 48) / 2) or 126)
    local importW = editW
    local resetW = tinyHeader and (layoutW - 32) or (compactHeader and (layoutW - 32) or 150)
    local actionY = compactHeader and -86 or -31
    local edit = Button(header, "Edit frames", actionX, actionY, editW, 28, ToggleEditMode, "primary")
    M.dashboardEditModeButton = edit
    AddTooltip(edit, "MSUF Edit Mode", "Drag frames to move them before tuning detailed settings.")
    M.RefreshDashboardEditModeButton()
    M.AddRefresher(ctx, M.RefreshDashboardEditModeButton)
    local import = Button(header, "Import profile", tinyHeader and actionX or (actionX + editW + 12), tinyHeader and (actionY - 36) or actionY, importW, 28, function() Select("profiles") end)
    AddTooltip(import, "Import profile", "Opens Profiles so you can back up first, then import safely.")
    local reset = Button(header, "Reset positions...", compactHeader and actionX or (actionX + editW + importW + 24), tinyHeader and (actionY - 72) or (compactHeader and (actionY - 36) or actionY), resetW, 28, function()
        if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then
            pcall(_G.SlashCmdList["MIDNIGHTSUF"], "reset")
        end
    end, "danger")
    AddTooltip(reset, "Reset Frame Positions", "Resets frame positions only. Profiles and menu settings stay intact.")

    local mainTop = y0 - headerH - 16
    local tinyHero = mainW < 390
    local heroH = tinyHero and 282 or (mainW < 560 and 218 or 190)
    local hero = Card(root, "", x0, mainTop, mainW, heroH, { 0.024, 0.050, 0.090, 0.90 }, { 0.085, 0.230, 0.340, 0.70 })
    ApplyDashboardHeroGradient(hero, mainW, heroH)
    Kicker(hero, "Recommended Start", 22, -24)
    local heroTitle = T.Font(hero, "GameFontNormalLarge", M.Tr("Build your unit frames in three clean steps."), T.colors.text)
    heroTitle:SetPoint("TOPLEFT", hero, "TOPLEFT", 22, -52)
    heroTitle:SetWidth(mainW - 44)
    heroTitle:SetJustifyH("LEFT")
    W.Text(hero, "Move frames first, tune the player frame, then configure group frames and auras. Advanced controls stay available without competing with the first-run path.", 22, -86, mainW - 44, T.colors.muted)
    if mainW >= 560 then
        Button(hero, "Edit frames", 22, -132, 104, 28, ToggleEditMode, "primary")
        Button(hero, "Set up Player", 138, -132, 118, 28, function() Select("uf_player") end)
        Button(hero, "Set up Group Frames", 268, -132, 156, 28, function() Select("gf_layout") end)
        Button(hero, "Import safely", 436, -132, 116, 28, function() Select("profiles") end)
    elseif tinyHero then
        Button(hero, "Edit frames", 22, -130, mainW - 44, 26, ToggleEditMode, "primary")
        Button(hero, "Set up Player", 22, -162, mainW - 44, 26, function() Select("uf_player") end)
        Button(hero, "Group Frames", 22, -194, mainW - 44, 26, function() Select("gf_layout") end)
        Button(hero, "Import safely", 22, -226, mainW - 44, 26, function() Select("profiles") end)
    else
        local actionW = max(96, math.floor((mainW - 56) / 2))
        Button(hero, "Edit frames", 22, -130, actionW, 26, ToggleEditMode, "primary")
        Button(hero, "Set up Player", 34 + actionW, -130, actionW, 26, function() Select("uf_player") end)
        Button(hero, "Group Frames", 22, -162, actionW, 26, function() Select("gf_layout") end)
        Button(hero, "Import safely", 34 + actionW, -162, actionW, 26, function() Select("profiles") end)
    end

    local featureTop = mainTop - heroH - 16
    local stackFeatures = mainW < 560
    local featureW = stackFeatures and mainW or math.floor((mainW - gap * 2) / 3)
    local function Feature(index, title, body, icon, pageKey)
        local x = stackFeatures and x0 or (x0 + ((index - 1) * (featureW + gap)))
        local y = stackFeatures and (featureTop - ((index - 1) * (142 + gap))) or featureTop
        local card = Card(root, "", x, y, featureW, 142)
        local ic = T.Font(card, "GameFontNormalLarge", icon, T.colors.accent)
        ic:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -20)
        local label = T.Font(card, "GameFontNormal", M.Tr(title), T.colors.text)
        label:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -58)
        W.Text(card, body, 18, -86, featureW - 36, T.colors.muted)
        MakeDashboardActionCard(card, title, body, function() Select(pageKey) end, true)
    end
    Feature(1, "Unit Frames", "Player, target, focus, pet, and boss frame setup with one preview language.", "U", "uf_player")
    Feature(2, "Group Frames", "Party, Raid, and Mythic scopes with visible summaries.", "G", "gf_layout")
    Feature(3, "Auras", "Shared defaults plus per-unit overrides explained inline.", "A", "auras2")

    local featureBlockBottom = featureTop - (stackFeatures and ((142 * 3) + (gap * 2)) or 142)
    local sideTop = sideBySide and mainTop or (featureBlockBottom - 16)
    local profile = Card(root, "Active profile", sideX, sideTop, sideW, 108)
    local pText = T.Font(profile, "GameFontDisableSmall", "", T.colors.muted)
    pText:SetPoint("TOPLEFT", profile, "TOPLEFT", 16, -38)
    pText:SetWidth(sideW - 86)
    Pill(profile, "Safe", sideW - 56, -26, 42, T.colors.ok)
    local manageProfile = Button(profile, "Manage", 16, -66, 70, 22, function() Select("profiles") end)
    local exportProfile = Button(profile, "Export backup", 94, -66, 104, 22, ExportBackup)
    local duplicateProfile = Button(profile, "Duplicate", sideW - 98, -66, 82, 22, function() Select("profiles") end)
    AddTooltip(manageProfile, "Manage profile", "Open Profiles for rename, import, export, and profile maintenance.")
    AddTooltip(exportProfile, "Export backup", "Copies a full backup string for the current setup.")
    AddTooltip(duplicateProfile, "Duplicate profile", "Open Profiles to copy this setup into another profile.")
    local function RefreshProfileCard()
        pText:SetText(M.Format(M.Tr("%s - manual profile"), tostring(_G.MSUF_ActiveProfile or "Default")))
    end
    RefreshProfileCard()
    M.AddRefresher(ctx, RefreshProfileCard)

    local wagoTop = sideTop - 124
    local wago = Card(root, "Wago profile hub", sideX, wagoTop, sideW, 164, { 0.040, 0.080, 0.125, 0.92 }, { 0.140, 0.320, 0.430, 0.82 })
    W.Text(wago, "Browse shared MSUF imports, copy a backup first, then import on the Profiles page.", 16, -40, sideW - 32, T.colors.muted)
    Button(wago, "Browse Wago profiles", 16, -78, sideW - 32, 30, CopyWagoLink, "primary")
    Button(wago, "Backup current profile", 16, -116, math.floor((sideW - 40) / 2), 24, ExportBackup)
    Button(wago, "Import safely", 24 + math.floor((sideW - 40) / 2), -116, math.floor((sideW - 40) / 2), 24, function() Select("profiles") end)
    AddTooltip(wago, "Wago profile imports", "The Wago button opens a copyable search link. Importing stays on the Profiles page so backup and new-profile import are visible.")

    local checklistTop = wagoTop - 180
    local checklistH = 292
    local checklist = Card(root, "Setup checklist", sideX, checklistTop, sideW, checklistH)
    W.Text(checklist, "Useful for first-run orientation.", 16, -38, sideW - 32, T.colors.muted)
    local function Row(i, title, body, state, color, onClick, iconText)
        local row = Card(checklist, "", 16, -68 - ((i - 1) * 56), sideW - 32, 48, { 0.080, 0.095, 0.170, 0.72 }, T.colors.borderSoft)
        Pill(row, iconText or (i < 3 and "OK" or "!"), 10, -14, 28, color or T.colors.ok)
        local label = T.Font(row, "GameFontNormal", M.Tr(title), T.colors.text)
        label:SetPoint("TOPLEFT", row, "TOPLEFT", 48, -9)
        W.Text(row, body, 48, -28, sideW - 132, T.colors.muted)
        Pill(row, state, sideW - 86, -14, 54, color or T.colors.ok)
        MakeDashboardActionCard(row, title, body, onClick, false)
    end
    local movedFrames = HasMovedFramesInEditMode()
    Row(1, "Profile ready", "Active profile is loaded.", "done", T.colors.ok, function() Select("profiles") end)
    Row(2, "Preview available", "Use pages to tune frames.", "done", T.colors.ok, function() Select("uf_player") end)
    Row(3, "Move frames", "Recommended before detail tuning.", movedFrames and "done" or "start", movedFrames and T.colors.ok or T.colors.accent2, ToggleEditMode, movedFrames and "OK" or "!")
    local wagoBackupConfirmed = WagoBackupConfirmed()
    Row(4, "Wago backup", "Confirm backup before using the Wago MSUF page.", wagoBackupConfirmed and "done" or "start", wagoBackupConfirmed and T.colors.ok or T.colors.accent2, ConfirmWagoBackup, wagoBackupConfirmed and "OK" or "!")

    local previewTop = checklistTop - checklistH - 16
    local preview = Card(root, "", sideX, previewTop, sideW, 150)
    Kicker(preview, "Live preview", 16, -18)
    local stage = T.Panel(preview, nil, { 0.015, 0.020, 0.038, 0.96 }, { 0.075, 0.105, 0.190, 0.75 })
    stage:SetPoint("TOPLEFT", preview, "TOPLEFT", 0, -48)
    stage:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", 0, 0)
    local sample = CreateFrame("Frame", nil, stage, T.Template and T.Template() or nil)
    local db = M.EnsureDB and M.EnsureDB() or _G.MSUF_DB or {}
    local playerConf = (type(db.player) == "table") and db.player or {}
    local bars = (type(db.bars) == "table") and db.bars or {}
    local rawW = Clamp(tonumber(playerConf.width) or 220, 90, 420)
    local rawH = Clamp(tonumber(playerConf.height) or 44, 20, 110)
    local classPowerH = (bars.showClassPower == true) and Clamp(tonumber(bars.classPowerHeight) or 4, 2, 18) or 0
    local frameScale = min(1.35, (sideW - 88) / rawW, 72 / (rawH + classPowerH + 8))
    if frameScale < 0.7 then frameScale = 0.7 end
    local function S(v) return math.floor((tonumber(v) or 0) * frameScale + 0.5) end
    local sampleW, sampleH = S(rawW), S(rawH)
    sample:SetSize(sampleW, sampleH)
    sample:SetPoint("CENTER", stage, "CENTER", 0, 0)
    if sample.SetBackdrop then
        sample:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        sample:SetBackdropColor(0.02, 0.02, 0.025, 0.96)
        sample:SetBackdropBorderColor(0, 0, 0, 1)
    end
    local hpBg = sample:CreateTexture(nil, "BORDER")
    hpBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    hpBg:SetPoint("TOPLEFT", sample, "TOPLEFT", S(2), -S(2))
    hpBg:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", -S(2), S(6))
    hpBg:SetVertexColor(0.08, 0.08, 0.085, 1)
    local hp = sample:CreateTexture(nil, "ARTWORK")
    hp:SetTexture(type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or "Interface\\Buttons\\WHITE8X8")
    hp:SetPoint("TOPLEFT", hpBg, "TOPLEFT", 0, 0)
    hp:SetPoint("BOTTOMLEFT", hpBg, "BOTTOMLEFT", 0, 0)
    hp:SetWidth(max(1, (sampleW - S(4)) * 0.72))
    hp:SetVertexColor(0.12, 0.12, 0.13, 1)
    local powerH = Clamp(tonumber(playerConf.powerBarHeight) or tonumber(bars.powerBarHeight) or 3, 2, 12)
    local powerBg = sample:CreateTexture(nil, "BORDER")
    powerBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    powerBg:SetPoint("BOTTOMLEFT", sample, "BOTTOMLEFT", S(2), S(2))
    powerBg:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", -S(2), S(2))
    powerBg:SetHeight(max(2, S(powerH)))
    powerBg:SetVertexColor(0.06, 0.02, 0.08, 1)
    local power = sample:CreateTexture(nil, "ARTWORK")
    power:SetTexture(type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or "Interface\\Buttons\\WHITE8X8")
    power:SetPoint("TOPLEFT", powerBg, "TOPLEFT", 0, 0)
    power:SetPoint("BOTTOMLEFT", powerBg, "BOTTOMLEFT", 0, 0)
    power:SetWidth(max(1, (sampleW - S(4)) * 0.82))
    power:SetVertexColor(0.55, 0.17, 0.78, 1)
    if classPowerH > 0 then
        local cp = CreateFrame("Frame", nil, stage)
        cp:SetSize(sampleW, max(2, S(classPowerH)))
        cp:SetPoint("BOTTOM", sample, "TOP", 0, S(4))
        local gapPx = max(0, S(tonumber(bars.classPowerGap) or 0))
        local segW = math.floor((sampleW - (4 * gapPx)) / 5)
        for i = 1, 5 do
            local seg = cp:CreateTexture(nil, "ARTWORK")
            seg:SetTexture("Interface\\Buttons\\WHITE8X8")
            seg:SetPoint("TOPLEFT", cp, "TOPLEFT", (i - 1) * (segW + gapPx), 0)
            seg:SetPoint("BOTTOMLEFT", cp, "BOTTOMLEFT", (i - 1) * (segW + gapPx), 0)
            seg:SetWidth(i == 5 and (sampleW - ((i - 1) * (segW + gapPx))) or segW)
            seg:SetVertexColor(0.55, 0.17, 0.78, i <= 3 and 0.96 or 0.28)
        end
    end
    local sampleName = T.Font(sample, "GameFontNormal", tostring(_G.UnitName and _G.UnitName("player") or M.Tr("Player")), { 1, 1, 1, 1 })
    sampleName:SetPoint("LEFT", sample, "LEFT", S(10), 0)
    local sampleHp = T.Font(sample, "GameFontNormal", "439K - 100.0%", { 1, 1, 1, 1 })
    sampleHp:SetPoint("RIGHT", sample, "RIGHT", -S(8), 0)

    local recoveryTop = sideBySide and (featureBlockBottom - 16) or (previewTop - 166)
    local recoveryW = sideBySide and mainW or layoutW
    local recoveryOpen = M.dashboardRecoveryOpen == true
    local recoveryWrap = recoveryW < 620
    local recoveryH = recoveryOpen and (recoveryWrap and 154 or 122) or 42
    local recovery = Card(root, "", x0, recoveryTop, recoveryW, recoveryH, { 0.030, 0.040, 0.078, 0.86 }, T.colors.borderSoft)
    local head = CreateFrame("Button", nil, recovery)
    head:SetPoint("TOPLEFT", recovery, "TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", recovery, "TOPRIGHT", 0, 0)
    head:SetHeight(42)
    local headHover = head:CreateTexture(nil, "BACKGROUND")
    headHover:SetAllPoints()
    headHover:SetColorTexture(0, 0, 0, 0)
    local arrow = head:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture(T.media.collapseArrow)
    arrow:SetSize(10, 10)
    arrow:SetPoint("LEFT", head, "LEFT", 16, 0)
    if T.ApplyCollapseVisual then T.ApplyCollapseVisual(arrow, nil, recoveryOpen) end
    local recTitle = T.Font(head, "GameFontNormal", M.Tr("Display & recovery"), T.colors.text)
    recTitle:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
    local g = M.GetGeneralDB and M.GetGeneralDB() or {}
    if recoveryW >= 520 then
        Pill(head, "Factory reset hidden", recoveryW - 124, -11, 110, T.colors.accent2)
    end
    head:SetScript("OnClick", function()
        M.PersistMenuStateValue("dashboardRecoveryOpen", not recoveryOpen)
        M.InvalidatePage("home")
        M.SelectPage("home")
    end)
    head:SetScript("OnEnter", function()
        if headHover.SetColorTexture then headHover:SetColorTexture(1, 1, 1, 0.025) end
    end)
    head:SetScript("OnLeave", function()
        if headHover.SetColorTexture then headHover:SetColorTexture(0, 0, 0, 0) end
    end)

    if recoveryOpen then
        local row3 = recoveryW < 520
        W.Text(recovery, "Reset tools, Wago access, and recovery shortcuts live here.", 16, -60, recoveryW - 32, T.colors.muted)
        Button(recovery, "Wago Profiles", 16, -94, 112, 22, CopyWagoLink, "primary")
        Button(recovery, "Print Help", 140, -94, 86, 22, function()
            if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then pcall(_G.SlashCmdList["MIDNIGHTSUF"], "help") end
        end)
        Button(recovery, "Discord", 238, -94, 80, 22, function()
            if type(_G.MSUF_ShowCopyLink) == "function" then _G.MSUF_ShowCopyLink("Discord", "https://discord.gg/JQnhZXnTAK") end
        end)
        Button(recovery, "Factory Reset All", recoveryWrap and 16 or (recoveryW - 152), recoveryWrap and -126 or -94, 136, 22, function()
            if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then pcall(_G.SlashCmdList["MIDNIGHTSUF"], "fullreset confirm") end
        end, "danger")
        if row3 then
            W.Text(recovery, "Factory reset affects every MSUF setting.", 160, -128, recoveryW - 176, T.colors.muted)
        end
    end

    local scalingTop = recoveryTop - recoveryH - 10
    local scalingOpen = M.dashboardScalingOpen == true
    local scalingColumns = (recoveryW >= 960) and 3 or ((recoveryW >= 680) and 2 or 1)
    local scalingH = scalingOpen and ((scalingColumns == 3) and 250 or ((scalingColumns == 2) and 382 or 548)) or 42
    local scaling = Card(root, "", x0, scalingTop, recoveryW, scalingH, { 0.030, 0.040, 0.078, 0.86 }, T.colors.borderSoft)
    local scaleHead = CreateFrame("Button", nil, scaling)
    scaleHead:SetPoint("TOPLEFT", scaling, "TOPLEFT", 0, 0)
    scaleHead:SetPoint("TOPRIGHT", scaling, "TOPRIGHT", 0, 0)
    scaleHead:SetHeight(42)
    local scaleHeadHover = scaleHead:CreateTexture(nil, "BACKGROUND")
    scaleHeadHover:SetAllPoints()
    scaleHeadHover:SetColorTexture(0, 0, 0, 0)
    local scaleArrow = scaleHead:CreateTexture(nil, "OVERLAY")
    scaleArrow:SetTexture(T.media.collapseArrow)
    scaleArrow:SetSize(10, 10)
    scaleArrow:SetPoint("LEFT", scaleHead, "LEFT", 16, 0)
    if T.ApplyCollapseVisual then T.ApplyCollapseVisual(scaleArrow, nil, scalingOpen) end
    local scaleTitle = T.Font(scaleHead, "GameFontNormal", M.Tr("Scaling"), T.colors.text)
    scaleTitle:SetPoint("LEFT", scaleArrow, "RIGHT", 8, 0)
    if recoveryW >= 520 then
        local _, ui = GlobalState()
        local uiValue = ui.Enabled and M.Format("%d%%", Percent(ui.Scale, 1)) or M.Tr("Off")
        Pill(scaleHead, M.Format("UI %s", uiValue), recoveryW - 250, -11, 64)
        Pill(scaleHead, M.Format("Menu %d%%", Percent(g.slashMenuScale, 1)), recoveryW - 180, -11, 76)
        Pill(scaleHead, M.Format("Frames %d%%", Percent(g.msufUiScale, 1)), recoveryW - 98, -11, 84)
    end
    scaleHead:SetScript("OnClick", function()
        M.PersistMenuStateValue("dashboardScalingOpen", not scalingOpen)
        M.InvalidatePage("home")
        M.SelectPage("home")
    end)
    scaleHead:SetScript("OnEnter", function()
        if scaleHeadHover.SetColorTexture then scaleHeadHover:SetColorTexture(1, 1, 1, 0.025) end
    end)
    scaleHead:SetScript("OnLeave", function()
        if scaleHeadHover.SetColorTexture then scaleHeadHover:SetColorTexture(0, 0, 0, 0) end
    end)

    if scalingOpen then
        W.Text(scaling, "Use sliders for exact scale changes. Apply commits the selected value; Revert returns to the active value.", 16, -60, recoveryW - 32, T.colors.muted)

        local pendingGlobalEnabled, pendingGlobalScale, pendingMsufScale, pendingMenuScale
        local colGap = 24
        local colW = (scalingColumns == 3) and math.floor((recoveryW - 32 - (colGap * 2)) / 3)
            or ((scalingColumns == 2) and math.floor((recoveryW - 32 - colGap) / 2) or (recoveryW - 32))
        local globalX, globalTop = 16, -94
        local msufX = (scalingColumns == 3) and (16 + colW + colGap) or ((scalingColumns == 2) and (16 + colW + colGap) or 16)
        local msufTop = (scalingColumns == 3 or scalingColumns == 2) and -94 or -242
        local menuX = (scalingColumns == 3) and (16 + ((colW + colGap) * 2)) or 16
        local menuTop = (scalingColumns == 3) and -94 or ((scalingColumns == 2) and -242 or -390)

        local function AppliedGlobalScale()
            local _, ui = GlobalState()
            return ui.Enabled, Clamp(ui.Scale, 0.3, 1.5)
        end
        local function SelectedGlobalScale()
            local enabled, appliedScale = AppliedGlobalScale()
            local selectedEnabled = (pendingGlobalEnabled ~= nil) and pendingGlobalEnabled or enabled
            local selectedScale = Clamp(pendingGlobalScale or appliedScale, 0.3, 1.5)
            return selectedEnabled, selectedScale, enabled, appliedScale
        end

        local function AppliedMsufScale()
            local dbScale = M.GetGeneralDB()
            return Clamp(tonumber(dbScale.msufUiScale) or 1, 0.25, 1.5)
        end
        local function PendingMsufScale()
            return Clamp(pendingMsufScale or AppliedMsufScale(), 0.25, 1.5)
        end
        local function AppliedMenuScale()
            local dbScale = M.GetGeneralDB()
            return Clamp(tonumber(dbScale.slashMenuScale) or 1, 0.25, 1.5)
        end
        local function PendingMenuScale()
            return Clamp(pendingMenuScale or AppliedMenuScale(), 0.25, 1.5)
        end

        W.Text(scaling, "Changes the global WoW UI scale through MSUF presets.", globalX, globalTop - 20, colW, T.colors.muted)
        local globalStatus = W.Text(scaling, "", globalX, globalTop - 40, colW, T.colors.muted)
        local globalScale = W.Slider(scaling, "Global UI Scale", 30, 150, 1, colW)
        HideSliderValueBox(globalScale)
        globalScale:ClearAllPoints()
        globalScale:SetPoint("TOPLEFT", scaling, "TOPLEFT", globalX, globalTop - 64)
        if globalScale._msuf2SetLayoutWidth then globalScale:_msuf2SetLayoutWidth(colW) end
        if globalScale._msuf2Title then
            globalScale._msuf2Title:ClearAllPoints()
            globalScale._msuf2Title:SetPoint("TOPLEFT", scaling, "TOPLEFT", globalX, globalTop)
            globalScale._msuf2Title:SetWidth(colW)
        end
        EnablePercentWheel(globalScale, 30, 150, 1)

        local globalApply, globalRevert
        local function RefreshGlobalScale()
            local selectedEnabled, selectedScale, appliedEnabled, appliedScale = SelectedGlobalScale()
            local applied = appliedEnabled and (Percent(appliedScale, 1) .. "%") or M.Tr("Off")
            local selected = selectedEnabled and (Percent(selectedScale, 1) .. "%") or M.Tr("Off")
            local changed = (selectedEnabled ~= appliedEnabled) or math.abs(selectedScale - appliedScale) > 0.001
            globalStatus:SetText(M.Format(M.Tr("Applied: %s   Selected: %s"), applied, selected))
            SetSliderValueSafe(globalScale, SnapPct(selectedScale * 100, 30, 150, 1))
            if globalApply then
                if changed then globalApply:Enable() else globalApply:Disable() end
                if globalApply.SetActive then globalApply:SetActive(changed) end
            end
            if globalRevert then
                if changed then globalRevert:Enable() else globalRevert:Disable() end
            end
        end
        globalScale:HookScript("OnValueChanged", function(self, value)
            if self._msuf2Refreshing then return end
            local pct = SnapPct(value, 30, 150, 1)
            if pct ~= value then SetSliderValueSafe(self, pct) end
            pendingGlobalEnabled = true
            pendingGlobalScale = Clamp(pct / 100, 0.3, 1.5)
            RefreshGlobalScale()
        end)
        local function ApplyGlobalScale(enabled, value, preset)
            local dbScale, ui = GlobalState()
            ui.Enabled = enabled == true
            ui.Scale = Clamp(value or ui.Scale, 0.3, 1.5)
            dbScale.globalUiScalePreset = preset or (ui.Enabled and "custom" or "auto")
            dbScale.globalUiScaleValue = ui.Enabled and ui.Scale or nil
            pendingGlobalEnabled, pendingGlobalScale = nil, nil
            if ui.Enabled and type(_G.MSUF_SetGlobalUiScale) == "function" then
                pcall(_G.MSUF_SetGlobalUiScale, ui.Scale, true)
            elseif (not ui.Enabled) and type(_G.MSUF_ResetGlobalUiScale) == "function" then
                pcall(_G.MSUF_ResetGlobalUiScale, true)
            end
            if M.RequestGeneralApply then M.RequestGeneralApply("MSUF2_DASH_GLOBAL_SCALE", { preview = true, applyAll = false }) end
            RefreshGlobalScale()
        end
        Button(scaling, "1080p", globalX, globalTop - 100, 52, 20, function() ApplyGlobalScale(true, 768 / 1080, "1080p") end)
        Button(scaling, "1440p", globalX + 60, globalTop - 100, 52, 20, function() ApplyGlobalScale(true, 768 / 1440, "1440p") end)
        Button(scaling, "4K", globalX + 120, globalTop - 100, 42, 20, function() ApplyGlobalScale(true, 768 / 2160, "4k") end)
        Button(scaling, "Pixel", globalX + 170, globalTop - 100, 52, 20, function() ApplyGlobalScale(true, PixelScale(), "pixel") end)
        globalApply = Button(scaling, "Apply", globalX, globalTop - 126, 72, 20, function()
            local selectedEnabled, selectedScale = SelectedGlobalScale()
            ApplyGlobalScale(selectedEnabled, selectedScale, selectedEnabled and "custom" or "auto")
        end, "primary")
        globalRevert = Button(scaling, "Revert", globalX + 82, globalTop - 126, 72, 20, function()
            pendingGlobalEnabled, pendingGlobalScale = nil, nil
            RefreshGlobalScale()
        end)
        Button(scaling, "Off", globalX + 164, globalTop - 126, 52, 20, function()
            pendingGlobalEnabled = false
            RefreshGlobalScale()
        end)

        W.Text(scaling, "Changes the actual MSUF unit frames in-game.", msufX, msufTop - 20, colW, T.colors.muted)
        local msufStatus = W.Text(scaling, "", msufX, msufTop - 40, colW, T.colors.muted)
        local msufScale = W.Slider(scaling, "MSUF Frame Scale", 25, 150, 5, colW)
        HideSliderValueBox(msufScale)
        msufScale:ClearAllPoints()
        msufScale:SetPoint("TOPLEFT", scaling, "TOPLEFT", msufX, msufTop - 64)
        if msufScale._msuf2SetLayoutWidth then msufScale:_msuf2SetLayoutWidth(colW) end
        if msufScale._msuf2Title then
            msufScale._msuf2Title:ClearAllPoints()
            msufScale._msuf2Title:SetPoint("TOPLEFT", scaling, "TOPLEFT", msufX, msufTop)
            msufScale._msuf2Title:SetWidth(colW)
        end
        EnablePercentWheel(msufScale, 25, 150, 5)

        local msufApply, msufRevert
        local function RefreshMsufScale()
            local applied = AppliedMsufScale()
            local pending = PendingMsufScale()
            local changed = math.abs(applied - pending) > 0.001
            msufStatus:SetText(M.Format(M.Tr("Applied: %d%%  Selected: %d%%"), Percent(applied, 1), Percent(pending, 1)))
            SetSliderValueSafe(msufScale, SnapPct(pending * 100, 25, 150, 5))
            if msufApply then
                if changed then msufApply:Enable() else msufApply:Disable() end
                if msufApply.SetActive then msufApply:SetActive(changed) end
            end
            if msufRevert then
                if changed then msufRevert:Enable() else msufRevert:Disable() end
            end
        end
        msufScale:HookScript("OnValueChanged", function(self, value)
            if self._msuf2Refreshing then return end
            local pct = SnapPct(value, 25, 150, 5)
            if pct ~= value then SetSliderValueSafe(self, pct) end
            pendingMsufScale = pct / 100
            RefreshMsufScale()
        end)
        msufApply = Button(scaling, "Apply", msufX, msufTop - 100, 72, 20, function()
            local dbScale = M.GetGeneralDB()
            local scaleValue = PendingMsufScale()
            dbScale.msufUiScale = scaleValue
            pendingMsufScale = nil
            if type(_G.MSUF_ApplyMsufScale) == "function" then pcall(_G.MSUF_ApplyMsufScale, scaleValue) end
            if M.RequestGeneralApply then M.RequestGeneralApply("MSUF2_DASH_MSUF_SCALE", { preview = true, applyAll = false }) end
            local applyAll = _G.MSUF_ApplyAllSettings
            if type(applyAll) == "function" then pcall(applyAll) end
            RefreshMsufScale()
        end, "primary")
        msufRevert = Button(scaling, "Revert", msufX + 82, msufTop - 100, 72, 20, function()
            pendingMsufScale = nil
            RefreshMsufScale()
        end)

        W.Text(scaling, "Changes only this configuration menu window.", menuX, menuTop - 20, colW, T.colors.muted)
        local menuStatus = W.Text(scaling, "", menuX, menuTop - 40, colW, T.colors.muted)
        local menuScale = W.Slider(scaling, "MSUF Menu Scale", 25, 150, 5, colW)
        HideSliderValueBox(menuScale)
        menuScale:ClearAllPoints()
        menuScale:SetPoint("TOPLEFT", scaling, "TOPLEFT", menuX, menuTop - 64)
        if menuScale._msuf2SetLayoutWidth then menuScale:_msuf2SetLayoutWidth(colW) end
        if menuScale._msuf2Title then
            menuScale._msuf2Title:ClearAllPoints()
            menuScale._msuf2Title:SetPoint("TOPLEFT", scaling, "TOPLEFT", menuX, menuTop)
            menuScale._msuf2Title:SetWidth(colW)
        end
        EnablePercentWheel(menuScale, 25, 150, 5)

        local menuApply, menuRevert
        local function RefreshMenuScale()
            local applied = AppliedMenuScale()
            local pending = PendingMenuScale()
            local changed = math.abs(applied - pending) > 0.001
            menuStatus:SetText(M.Format(M.Tr("Applied: %d%%  Selected: %d%%"), Percent(applied, 1), Percent(pending, 1)))
            SetSliderValueSafe(menuScale, SnapPct(pending * 100, 25, 150, 5))
            if menuApply then
                if changed then menuApply:Enable() else menuApply:Disable() end
                if menuApply.SetActive then menuApply:SetActive(changed) end
            end
            if menuRevert then
                if changed then menuRevert:Enable() else menuRevert:Disable() end
            end
        end
        menuScale:HookScript("OnValueChanged", function(self, value)
            if self._msuf2Refreshing then return end
            local pct = SnapPct(value, 25, 150, 5)
            if pct ~= value then SetSliderValueSafe(self, pct) end
            pendingMenuScale = pct / 100
            RefreshMenuScale()
        end)
        menuApply = Button(scaling, "Apply", menuX, menuTop - 100, 72, 20, function()
            local dbScale = M.GetGeneralDB()
            local scaleValue = PendingMenuScale()
            dbScale.slashMenuScale = scaleValue
            pendingMenuScale = nil
            if M.frame and M.frame.SetScale then M.frame:SetScale((M.GetEffectiveMenuScale and M.GetEffectiveMenuScale(scaleValue)) or scaleValue) end
            RefreshMenuScale()
        end, "primary")
        menuRevert = Button(scaling, "Revert", menuX + 82, menuTop - 100, 72, 20, function()
            pendingMenuScale = nil
            RefreshMenuScale()
        end)

        RefreshGlobalScale()
        RefreshMsufScale()
        RefreshMenuScale()
        M.AddRefresher(ctx, RefreshGlobalScale)
        M.AddRefresher(ctx, RefreshMsufScale)
        M.AddRefresher(ctx, RefreshMenuScale)
    end

    local changelogTop = scalingTop - scalingH - 10
    local changelogOpen = M.dashboardChangelogOpen == true
    local changelogH = changelogOpen and 360 or 42
    local changelog = Card(root, "", x0, changelogTop, recoveryW, changelogH, { 0.030, 0.040, 0.078, 0.86 }, T.colors.borderSoft)
    BuildDashboardChangelog(changelog, recoveryW, {
        title = "Changelog",
        sectionHeader = true,
        top = 0,
        bottom = 18,
        hideSummaryWhenClosed = true,
        onToggle = function()
            M.InvalidatePage("home")
            M.SelectPage("home")
        end,
    })

    local supportTop = changelogTop - changelogH - 10
    local supportCompact = recoveryW < 560
    local supportH = supportCompact and 116 or 78
    local support = Card(root, "", x0, supportTop, recoveryW, supportH, { 0.030, 0.040, 0.078, 0.86 }, T.colors.borderSoft)
    local supportTitle = T.Font(support, "GameFontNormal", M.Tr("Support MSUF Development"), T.colors.text)
    supportTitle:SetPoint("TOPLEFT", support, "TOPLEFT", 16, -16)
    local supportTextW = max(160, recoveryW - (supportCompact and 32 or 230))
    local supportDesc = W.Text(support, "If MSUF helps your UI, support links are one click away.", 16, -42, supportTextW, T.colors.muted)
    if supportDesc.SetWordWrap then supportDesc:SetWordWrap(true) end
    if supportDesc.SetNonSpaceWrap then supportDesc:SetNonSpaceWrap(true) end

    local aboutVer
    if _G.C_AddOns and type(_G.C_AddOns.GetAddOnMetadata) == "function" then
        aboutVer = _G.C_AddOns.GetAddOnMetadata("MidnightSimpleUnitFrames", "Version")
    end
    local aboutText = M.Tr("by Mapko with the help from R41z0r")
    if type(aboutVer) == "string" and aboutVer ~= "" then
        local displayVersion = aboutVer:match("^%d") and ("v" .. aboutVer) or aboutVer
        aboutText = M.Format(M.Tr("%s  -  by Mapko with the help from R41z0r"), displayVersion)
    end
    local supportDescH = (supportDesc.GetStringHeight and supportDesc:GetStringHeight()) or 0
    if supportDescH < 12 then supportDescH = 12 end
    local aboutY = -42 - supportDescH - 5
    local supportAbout = W.Text(support, aboutText, 16, aboutY, supportTextW, T.colors.muted)
    if supportAbout.SetWordWrap then supportAbout:SetWordWrap(true) end
    if supportAbout.SetNonSpaceWrap then supportAbout:SetNonSpaceWrap(true) end

    local supportAboutH = (supportAbout.GetStringHeight and supportAbout:GetStringHeight()) or 0
    if supportAboutH < 12 then supportAboutH = 12 end
    local supportTextBottom = math.abs(aboutY - supportAboutH)
    if supportCompact then
        supportH = max(supportH, floor(supportTextBottom + 24 + 24))
    else
        supportH = max(supportH, floor(supportTextBottom + 14))
    end
    support:SetHeight(supportH)

    local iconDir = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\"
    local supportLinks = {
        { texture = "Patreon.png", title = "Patreon", tooltip = "Click to copy the Patreon support link.", url = "https://www.patreon.com/cw/MidnightSimpleUnitframes" },
        { texture = "PayPal.png", title = "PayPal", tooltip = "Click to copy the PayPal support link.", url = "https://www.paypal.com/ncp/payment/H3N2P87S53KBQ" },
        { texture = "Ko-Fi.png", title = "Ko-fi", tooltip = "Click to copy the Ko-fi link.", url = "https://ko-fi.com/midnightsimpleunitframes#linkModal" },
        { texture = "GitHub.png", title = "GitHub", tooltip = "Click to copy the GitHub repository link.", url = "https://github.com/Mapkov2/MidnightSimpleUnitFrames" },
    }
    local iconRow = CreateFrame("Frame", nil, support)
    iconRow:SetSize(160, 24)
    if supportCompact then
        iconRow:SetPoint("BOTTOMLEFT", support, "BOTTOMLEFT", 16, 12)
    else
        iconRow:SetPoint("RIGHT", support, "RIGHT", -16, 0)
    end
    local previous
    for i = 1, #supportLinks do
        local data = supportLinks[i]
        local btn = CreateFrame("Button", nil, iconRow)
        btn:SetSize(24, 24)
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(iconDir .. data.texture)
        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.10)
        btn:SetScript("OnClick", function()
            if type(_G.MSUF_ShowCopyLink) == "function" then
                _G.MSUF_ShowCopyLink(data.title, data.url)
            end
        end)
        AddTooltip(btn, data.title, data.tooltip)
        if type(M.RegisterSearchWidget) == "function" then
            M.RegisterSearchWidget(btn, {
                label = data.title,
                kind = "button",
                anchor = supportTitle,
                keywords = { data.tooltip, "Support MSUF Development", "support links", data.url },
                help = data.tooltip,
            })
        end
        if previous then
            btn:SetPoint("LEFT", previous, "RIGHT", 10, 0)
        else
            btn:SetPoint("LEFT", iconRow, "LEFT", 0, 0)
        end
        previous = btn
    end

    local bottom = supportTop - supportH
    if sideBySide then bottom = min(bottom, previewTop - 150) end
    ctx:SetContentHeight(math.abs(bottom) + 42)
end

M.RegisterPage("home", { title = "MSUF Menu", build = BuildDashboardUX, version = 6 })
