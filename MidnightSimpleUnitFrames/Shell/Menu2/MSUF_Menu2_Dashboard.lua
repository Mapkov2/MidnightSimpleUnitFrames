local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M
local T = M.Theme
local W = M.Widgets

-- Menu2 dashboard page.
-- Builds the home overview, recovery panels, changelog preview, and quick actions. Dashboard
-- widgets should call workflow/page helpers; profile/runtime mutation stays outside this file.
local floor = math.floor
local max = math.max
local min = math.min
local CreateFrame = _G.CreateFrame
local CreateColor = _G.CreateColor
local MOVED_FRAME_DEFAULTS = { player = { -256, -180 }, target = { 320, -180 }, focus = { -260, -300 }, targettarget = { 220, -300 }, pet = { -275, -250 }, boss = { 360, 230 }, gf_party = { -400, 0 }, gf_raid = { -500, 0 }, gf_mythicraid = { -500, 0 } }
local function GetBundledChangelog()
    -- Changelog data is bundled as static state. The dashboard renders it read-only and should
    -- tolerate older builds where no changelog table exists.
    local data = (type(MSUF) == "table" and MSUF.MSUF_Changelog) or _G.MSUF_Changelog
    if type(data) ~= "table" or type(data.entries) ~= "table" or type(data.entries[1]) ~= "table" then return nil end
    return data
end
local function BuildDashboardChangelog(parent, cardWidth, opts)
    opts = opts or {}
    local data = GetBundledChangelog()
    local top = opts.top or -130
    local headerH = 42
    local contentW = max(120, cardWidth or 420)
    local scrollW = max(80, contentW - 60)
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
    local header = CreateFrame("Button", nil, parent)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, top)
    header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, top)
    header:SetHeight(headerH)
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
    arrow:SetPoint("LEFT", header, "LEFT", 16, 0)
    arrow:SetTexture(T.media.collapseArrow)
    local title = T.Font(header, "GameFontNormal", M.Tr(opts.title or "Changelog"), T.colors.text)
    title:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
    title:SetPoint("RIGHT", header, "RIGHT", -94, 0)
    title:SetJustifyH("LEFT")
    local hint = T.Font(header, "GameFontDisableSmall", "", T.colors.dim)
    hint:SetPoint("RIGHT", header, "RIGHT", -16, 0)
    hint:SetJustifyH("RIGHT")
    if not data then
        header:EnableMouse(false)
        hint:SetText("")
        RawFont(parent, "GameFontHighlightSmall", M.Tr("No release notes bundled with this build."), T.colors.muted, 0)
            :SetPoint("TOPLEFT", parent, "TOPLEFT", 16, top - headerH - 8)
        if arrow.SetVertexColor then arrow:SetVertexColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.55) end
        return
    end
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, top - headerH - 10)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -34, opts.bottom or 70)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(scrollW, 1)
    scroll:SetScrollChild(child)
    local y = -2
    local function AddText(text, fontObject, color, indent, gap, translate)
        local rawText = tostring(text or "")
        if translate and type(M.Tr) == "function" then rawText = M.Tr(rawText) end
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
    M.CallIf(T.StyleScrollFrame, scroll, parent)
    local open = M.dashboardChangelogOpen == true
    local function PaintHeader(isOpen)
        M.CallIf(T.ApplyCollapseVisual, arrow, nil, isOpen)
        if headerBg.SetColorTexture then headerBg:SetColorTexture(0, 0, 0, 0) end
        if headerEdge.SetColorTexture then headerEdge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], isOpen and 0.58 or 0.34) end
        hint:SetText(isOpen and M.Tr("Hide") or M.Tr("View"))
    end
    local function RefreshOpenState()
        M.SetMenuStateValue("dashboardChangelogOpen", open)
        scroll:SetShown(open)
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
            if texture.SetVertexColor then texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1) end
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
        T.CenterButtonLabel(btn)
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
        return M.AddTooltip and M.AddTooltip(frame, title, text, {
            hook = true,
            titleAsLine = true,
            bodyColor = { 0.85, 0.85, 0.85 },
        }) or frame
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
            if arrow and arrow.SetTextColor then arrow:SetTextColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 1) end
        end)
        card:HookScript("OnLeave", function(self)
            if self._msuf2DashboardActionHover then self._msuf2DashboardActionHover:Hide() end
            local arrow = self._msuf2DashboardActionArrow
            if arrow and arrow.SetTextColor then arrow:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], T.colors.dim[4] or 1) end
        end)
        if onClick then card:SetScript("OnMouseUp", onClick) end
        AddTooltip(card, title, tooltip)
        return card
    end
    local function Select(pageKey) M.CallIf(M.SelectPage, pageKey) end
    local function IsDashboardEditModeActive()
        return M.IsMSUFEditModeActive(true)
    end
    local function IsDashboardEditModeCombatLocked()
        return M.IsEditModeCombatLocked(true)
    end
    local function RefreshDashboardEditModeButtonSafe() M.CallIf(M.RefreshDashboardEditModeButton) end
    local function RefreshMenuFramePrioritySafe() M.CallIf(M.RefreshMenuFramePriority) end
    local function RefreshDashboardFrameStatus() local f = M.frame; if f and f.RefreshStatus then f:RefreshStatus() end end
    local function ToggleEditMode()
        local active = IsDashboardEditModeActive()
        if (not active) and IsDashboardEditModeCombatLocked() then
            M.CallIf(M.BlockCombatAction)
            RefreshDashboardEditModeButtonSafe()
            RefreshDashboardFrameStatus()
            return
        end
        if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then _G.MSUF_SetMSUFEditModeDirect(not active) end
        RefreshMenuFramePrioritySafe()
        if C_Timer and C_Timer.After then C_Timer.After(0, RefreshMenuFramePrioritySafe) end
        RefreshDashboardEditModeButtonSafe()
        RefreshDashboardFrameStatus()
    end
    local function StartNewAssistantTask()
        local A = MSUF and MSUF.Assistant
        if not A then return end
        if A.Workflow and type(A.Workflow.CancelActiveWorkflow) == "function" then pcall(A.Workflow.CancelActiveWorkflow) end
        if type(A.CloseLargeTextPanel) == "function" then
            pcall(A.CloseLargeTextPanel)
        else
            A.largeTextPanel = nil
        end
        if type(A.ClearHistory) == "function" then A.ClearHistory() end
        local ui = A.dashboardUI
        if ui and ui.input then
            ui.input:SetText("")
            if ui.input.ClearFocus then ui.input:ClearFocus() end
            if ui.input._msufAssistantPlaceholder and ui.input._msufAssistantPlaceholder.SetShown then ui.input._msufAssistantPlaceholder:SetShown(true) end
        end
        if type(A.RequestRefreshUI) == "function" then
            A.RequestRefreshUI("assistant.new_task")
        elseif type(A.RefreshUI) == "function" then
            A.RefreshUI()
        end
    end
    local function CopyWagoLink()
        if type(_G.MSUF_ShowCopyLink) == "function" then _G.MSUF_ShowCopyLink("Wago MSUF Profiles", "https://wago.io/search/imports/wow/msuf") end
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
        M.CallIf(M.InvalidatePage, "home")
        M.CallIf(M.SelectPage, "home")
    end
    local function ConfirmWagoBackup()
        if WagoBackupConfirmed() then return end
        local function accept()
            SetWagoBackupConfirmed(true)
            RefreshDashboard()
        end
        if _G.StaticPopupDialogs and _G.StaticPopup_Show then
            local popup = M.InstallStaticPopup("MSUF2_WAGO_PROFILE_BACKUP_CONFIRM", {
                text = "%s",
                button1 = _G.YES or "Yes",
                button2 = _G.NO or "No",
                OnAccept = accept,
            })
            popup.button1 = _G.YES or "Yes"
            popup.button2 = _G.NO or "No"
            popup.OnAccept = accept
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
        if slider and slider._msuf2Title and slider._msuf2Title.SetFontObject then slider._msuf2Title:SetFontObject("GameFontHighlight") end
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
        for key, def in pairs(MOVED_FRAME_DEFAULTS) do
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
    local function RunMSUFSlashCommand(message)
        local slash = _G.SlashCmdList and _G.SlashCmdList["MIDNIGHTSUF"]
        if type(slash) ~= "function" then return false end
        local ok = pcall(slash, message or "")
        return ok and true or false
    end
    M.dashboardEditModeButton = nil
    local compactHeader = layoutW < 640
    local tinyHeader = layoutW < 430
    local headerH = tinyHeader and 128 or (compactHeader and 104 or 86)
    local header = Card(root, "Dashboard", x0, y0, layoutW, headerH, { 0.030, 0.036, 0.058, 0.94 }, { 0.100, 0.140, 0.220, 0.82 })
    local editW = 150
    local taskW = 96
    local headerTextW = compactHeader and (layoutW - 32) or max(180, layoutW - editW - taskW - 76)
    W.Text(header, "Ask MSUF, review setup, and open recovery tools when needed.", 16, -42, headerTextW, T.colors.muted)
    if tinyHeader then
        local available = max(160, layoutW - 32)
        local smallTaskW = min(taskW, floor((available - 10) * 0.40))
        local smallEditW = min(editW, available - smallTaskW - 10)
        Button(header, "New Task", 16, -82, smallTaskW, 26, StartNewAssistantTask)
        M.dashboardEditModeButton = Button(header, "MSUF Edit Mode", 16 + smallTaskW + 10, -82, smallEditW, 26, ToggleEditMode, "primary")
    else
        local actionY = compactHeader and -66 or -26
        local actionX = layoutW - editW - 16
        M.dashboardEditModeButton = Button(header, "MSUF Edit Mode", actionX, actionY, editW, 28, ToggleEditMode, "primary")
        Button(header, "New Task", actionX - taskW - 12, actionY, taskW, 28, StartNewAssistantTask)
    end
    M.TrackRefresh(ctx, RefreshDashboardEditModeButtonSafe)
    local mainTop = y0 - headerH - 16
    local tinyHero = mainW < 390
    local heroH = tinyHero and 398 or (mainW < 560 and 382 or 360)
    local hero = Card(root, "", x0, mainTop, mainW, heroH, { 0.024, 0.050, 0.090, 0.90 }, { 0.085, 0.230, 0.340, 0.70 })
    ApplyDashboardHeroGradient(hero, mainW, heroH)
    if MSUF and MSUF.Assistant and type(MSUF.Assistant.BuildDashboardCard) == "function" then
        MSUF.Assistant.BuildDashboardCard(hero, mainW, heroH)
    else
        Kicker(hero, "MSUF", 22, -24)
        local title = T.Font(hero, "GameFontNormalLarge", M.Tr("Dashboard unavailable"), T.colors.text)
        title:SetPoint("TOPLEFT", hero, "TOPLEFT", 22, -52)
        title:SetWidth(mainW - 44)
        W.Text(hero, "The Assistant dashboard module is not available. Use the navigation pages and search to configure MSUF.", 22, -82, mainW - 44, T.colors.muted)
    end
    local featureBlockBottom = mainTop - heroH
    local sideTop = sideBySide and mainTop or (featureBlockBottom - 16)
    local checklistTop = sideTop
    local checklistH = 236
    local checklist = Card(root, "Setup checklist", sideX, checklistTop, sideW, checklistH)
    W.Text(checklist, "Useful for first-run orientation.", 16, -38, sideW - 32, T.colors.muted)
    local function Row(i, title, body, state, color, onClick, iconText)
        local row = Card(checklist, "", 16, -60 - ((i - 1) * 42), sideW - 32, 36, { 0.080, 0.095, 0.170, 0.72 }, T.colors.borderSoft)
        Pill(row, iconText or (i < 3 and "OK" or "!"), 10, -14, 28, color or T.colors.ok)
        local label = T.Font(row, "GameFontNormal", M.Tr(title), T.colors.text)
        label:SetPoint("TOPLEFT", row, "TOPLEFT", 48, -6)
        W.Text(row, body, 48, -22, sideW - 132, T.colors.muted)
        Pill(row, state, sideW - 86, -9, 54, color or T.colors.ok)
        MakeDashboardActionCard(row, title, body, onClick, false)
    end
    local function BuildBugReportCard(x, top, width)
        local bug = M.BugReport
        if type(bug) ~= "table" or type(bug.GetStatus) ~= "function" then return 0 end
        if type(bug.IsCombatDeferred) == "function" and bug.IsCombatDeferred() then return 0 end
        local status, integration = bug.GetStatus()
        integration = type(integration) == "table" and integration or {}
        local autoReport = status == "has_error" or status == "dummy"
        local manualReport = M.dashboardBugReportOpen == true
        local hasReport = autoReport or manualReport
        local missing = status == "missing"
        local height = hasReport
            and (autoReport and (width < 330 and 282 or 262) or (width < 330 and 326 or 306))
            or (missing and 158 or 124)
        local accent = hasReport and (T.colors.danger or T.colors.accent2)
            or (missing and T.colors.accent2 or T.colors.ok)
        local bg = hasReport and { 0.032, 0.038, 0.058, 0.92 }
            or (missing and { 0.060, 0.050, 0.035, 0.86 } or { 0.030, 0.040, 0.078, 0.86 })
        local card = Card(root, "", x, top, width, height, bg, hasReport and T.colors.borderSoft or (accent or T.colors.borderSoft))
        local title = T.Font(card, "GameFontNormal", M.Tr("Bug report"), T.colors.text)
        title:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -16)
        local statusText = hasReport and (status == "dummy" and "test" or (autoReport and "error" or "manual"))
            or (missing and "setup" or "clean")
        Pill(card, statusText, width - 82, -13, 66, accent)
        local links = type(bug.GetLinks) == "function" and bug.GetLinks() or {}
        local function CopyLink(label, url)
            if type(_G.MSUF_ShowCopyLink) == "function" then
                _G.MSUF_ShowCopyLink(label, url)
            elseif M.ShowStatusFeedback then
                M.ShowStatusFeedback("Copy popup unavailable", "danger", 1.2)
            end
        end
        local function OpenManualReport()
            if type(bug.OpenManual) == "function" then
                bug.OpenManual()
            else
                M.SetMenuStateValue("dashboardBugReportOpen", true)
            end
            RefreshDashboard()
        end
        if missing and not manualReport then
            W.Text(card, "Install BugSack/BugGrabber to let MSUF include the captured Lua error and stacktrace automatically.", 16, -42, width - 32, T.colors.muted)
            local bugSack = Button(card, "BugSack", 16, -92, 86, 22, function()
                CopyLink("BugSack", links.bugsack or "https://www.curseforge.com/wow/addons/bugsack")
            end, "primary")
            AddTooltip(bugSack, "BugSack", "Copies the BugSack addon page link.")
            Button(card, "Report issue", 112, -92, 104, 22, OpenManualReport)
            return height
        end
        if not hasReport then
            local installText = integration.bugGrabberLoaded and "BugGrabber ready."
                or (integration.bugSackLoaded and "BugSack ready." or "Bug helper unavailable.")
            W.Text(card, "No MSUF errors detected. " .. installText, 16, -42, width - 32, T.colors.muted)
            Button(card, "Report issue", 16, -82, 104, 22, OpenManualReport, "primary")
            return height
        end
        local bodyText = autoReport
            and "MSUF captured the error. Three steps: select, Ctrl+C, open a link."
            or "Describe the issue briefly. MSUF adds the technical context automatically."
        W.Text(card, bodyText, 16, -42, width - 32, T.colors.muted)
        local reportBox
        local function SetManualIssue(issueType, description)
            if type(bug.SetManualIssue) == "function" then bug.SetManualIssue(issueType, description) end
        end
        local selectedIssue, selectedDescription
        if type(bug.GetManualIssue) == "function" then selectedIssue, selectedDescription = bug.GetManualIssue() end
        local actionTop = autoReport and -78 or -116
        if not autoReport then
            local descBox = CreateFrame("EditBox", nil, card, "InputBoxTemplate")
            descBox:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -76)
            descBox:SetSize(width - 32, 30)
            descBox:SetAutoFocus(false)
            descBox:SetMaxLetters(240)
            descBox:SetJustifyH("LEFT")
            if descBox.SetFont then descBox:SetFont(_G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11, "") end
            if descBox.SetTextInsets then descBox:SetTextInsets(8, 8, 0, 0) end
            M.CallIf(T.SkinEditBox, descBox)
            descBox:SetText(selectedDescription or "")
            local placeholder = descBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            placeholder:SetPoint("LEFT", descBox, "LEFT", 10, 0)
            placeholder:SetPoint("RIGHT", descBox, "RIGHT", -10, 0)
            placeholder:SetJustifyH("LEFT")
            placeholder:SetText(M.Tr("Optional note: what went wrong?"))
            if placeholder.SetTextColor then placeholder:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.82) end
            placeholder:SetShown((selectedDescription or "") == "")
            descBox:SetScript("OnTextChanged", function(self)
                local text = self:GetText() or ""
                SetManualIssue(nil, text)
                placeholder:SetShown(text == "")
            end)
            descBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            descBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        end
        local scroll
        local function RefreshReportText()
            local text = type(bug.BuildText) == "function" and bug.BuildText({ includeLoadedAddons = true }) or "Bug report unavailable."
            if reportBox then
                reportBox:SetText(text)
                reportBox:SetCursorPosition(0)
                local lineCount = 1
                for _ in tostring(text):gmatch("\n") do lineCount = lineCount + 1 end
                reportBox:SetHeight(max((scroll and scroll:GetHeight()) or 96, (lineCount * 13) + 24))
                if scroll and scroll._msuf2RefreshScrollBar then scroll:_msuf2RefreshScrollBar() end
            end
            return text
        end
        local function SelectReport()
            RefreshReportText()
            if reportBox then
                reportBox:SetFocus()
                if reportBox.HighlightText then reportBox:HighlightText() end
            end
            M.CallIf(M.ShowStatusFeedback, "Report selected. Press Ctrl+C.", "info", 1.4)
        end
        local selectBtn = Button(card, "1 Select", 16, actionTop, 96, 22, SelectReport, "primary")
        AddTooltip(selectBtn, "Select report", "Selects the full report so it can be copied with Ctrl+C.")
        Pill(card, "2 Ctrl+C", 120, actionTop + 1, 66, T.colors.accent2)
        Button(card, "3 GitHub", width - 102, actionTop, 86, 22, function()
            CopyLink("GitHub Issue", links.github or "https://github.com/Mapkov2/MidnightSimpleUnitFrames/issues/new")
        end, "primary")
        Button(card, "Discord", 16, actionTop - 30, 76, 22, function()
            CopyLink("Discord", links.discord or "https://discord.gg/2Gf9b2Wprz")
        end)
        Button(card, "Curse", 100, actionTop - 30, 76, 22, function()
            CopyLink("CurseForge", links.curseforge or "https://www.curseforge.com/wow/addons/midnightsimpleunitframes")
        end)
        Button(card, "Clear", width - 78, actionTop - 30, 62, 22, function()
            if type(bug.Clear) == "function" then bug.Clear() end
            RefreshDashboard()
        end)
        local reportText = type(bug.BuildText) == "function" and bug.BuildText({ includeLoadedAddons = true }) or "Bug report unavailable."
        local reportTop = actionTop - 62
        local reportH = max(82, height + reportTop - 16)
        scroll = CreateFrame("ScrollFrame", nil, card)
        scroll:SetPoint("TOPLEFT", card, "TOPLEFT", 16, reportTop)
        scroll:SetSize(width - 48, reportH)
        reportBox = CreateFrame("EditBox", nil, scroll, "InputBoxTemplate")
        reportBox:SetMultiLine(true)
        reportBox:SetAutoFocus(false)
        reportBox:SetMaxLetters(200000)
        reportBox:SetJustifyH("LEFT")
        reportBox:SetJustifyV("TOP")
        reportBox:EnableMouse(true)
        reportBox:SetWidth(width - 56)
        if reportBox.SetFont then reportBox:SetFont(_G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "") end
        if reportBox.SetTextInsets then reportBox:SetTextInsets(8, 8, 8, 8) end
        M.CallIf(T.SkinEditBox, reportBox)
        reportBox:SetText(reportText)
        reportBox:SetCursorPosition(0)
        local lines = 1
        for _ in tostring(reportText):gmatch("\n") do lines = lines + 1 end
        reportBox:SetHeight(max(reportH, (lines * 13) + 24))
        reportBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(reportBox)
        M.CallIf(T.StyleScrollFrame, scroll, card)
        return height
    end
    local movedFrames = HasMovedFramesInEditMode()
    Row(1, "Profile ready", "Active profile is loaded.", "done", T.colors.ok, function() Select("profiles") end)
    Row(2, "Pages available", "Use pages to tune frames.", "done", T.colors.ok, function() Select("uf_player") end)
    Row(3, "Move frames", "Recommended before detail tuning.", movedFrames and "done" or "start", movedFrames and T.colors.ok or T.colors.accent2, ToggleEditMode, movedFrames and "OK" or "!")
    local wagoBackupConfirmed = WagoBackupConfirmed()
    Row(4, "Wago backup", "Confirm backup before using the Wago MSUF page.", wagoBackupConfirmed and "done" or "start", wagoBackupConfirmed and T.colors.ok or T.colors.accent2, ConfirmWagoBackup, wagoBackupConfirmed and "OK" or "!")
    local function DashboardDisclosure(parent, title, open, stateKey, width, fillPills)
        local head = CreateFrame("Button", nil, parent)
        head:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        head:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
        head:SetHeight(42)
        local hover = head:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints()
        hover:SetColorTexture(0, 0, 0, 0)
        local arrow = head:CreateTexture(nil, "OVERLAY")
        arrow:SetTexture(T.media.collapseArrow)
        arrow:SetSize(10, 10)
        arrow:SetPoint("LEFT", head, "LEFT", 16, 0)
        M.CallIf(T.ApplyCollapseVisual, arrow, nil, open)
        local label = T.Font(head, "GameFontNormal", M.Tr(title), T.colors.text)
        label:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
        if type(fillPills) == "function" then fillPills(head, width) end
        head:SetScript("OnClick", function()
            M.SetMenuStateValue(stateKey, not open)
            M.InvalidatePage("home")
            M.SelectPage("home")
        end)
        head:SetScript("OnEnter", function()
            if hover.SetColorTexture then hover:SetColorTexture(1, 1, 1, 0.025) end
        end)
        head:SetScript("OnLeave", function()
            if hover.SetColorTexture then hover:SetColorTexture(0, 0, 0, 0) end
        end)
        return head
    end
    local bugReportTop = checklistTop - checklistH - 10
    local bugReportH = BuildBugReportCard(sideX, bugReportTop, sideW)
    local sideBottom = bugReportH > 0 and (bugReportTop - bugReportH) or (checklistTop - checklistH)
    local recoveryTop = sideBySide and (featureBlockBottom - 16) or (sideBottom - 16)
    local recoveryW = sideBySide and mainW or layoutW
    local recoveryOpen = M.dashboardRecoveryOpen == true
    local recoveryWrap = recoveryW < 620
    local recoveryNarrow = recoveryW < 520
    local recoveryH = recoveryOpen and (recoveryNarrow and 184 or (recoveryWrap and 154 or 122)) or 42
    local recovery = Card(root, "", x0, recoveryTop, recoveryW, recoveryH, { 0.030, 0.040, 0.078, 0.86 }, T.colors.borderSoft)
    local g = M.GetGeneralDB and M.GetGeneralDB() or {}
    DashboardDisclosure(recovery, "Display & recovery", recoveryOpen, "dashboardRecoveryOpen", recoveryW, function(head)
        if recoveryW >= 520 then Pill(head, "Factory reset hidden", recoveryW - 124, -11, 110, T.colors.accent2) end
    end)
    if recoveryOpen then
        W.Text(recovery, "Reset tools, Wago access, and recovery shortcuts live here.", 16, -60, recoveryW - 32, T.colors.muted)
        local resetPositions = Button(recovery, "Reset Positions", 16, -94, 118, 22, function()
            if not RunMSUFSlashCommand("reset") and M.ShowStatusFeedback then M.ShowStatusFeedback("Reset unavailable", "danger", 1.4) end
        end, "primary")
        AddTooltip(resetPositions, "Reset Positions", "Runs /msuf reset for frame positions and visibility.")
        local wagoX, helpX, discordX = 146, 270, 368
        local helpY, factoryY = -94, (recoveryWrap and -126 or -94)
        if recoveryNarrow then helpX, helpY, discordX, factoryY = 16, -126, 114, -158 end
        Button(recovery, "Wago Profiles", wagoX, -94, 112, 22, CopyWagoLink)
        Button(recovery, "Print Help", helpX, helpY, 86, 22, function()
            if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then pcall(_G.SlashCmdList["MIDNIGHTSUF"], "help") end
        end)
        Button(recovery, "Discord", discordX, helpY, 80, 22, function()
            if type(_G.MSUF_ShowCopyLink) == "function" then _G.MSUF_ShowCopyLink("Discord", "https://discord.gg/2Gf9b2Wprz") end
        end)
        Button(recovery, "Factory Reset All", recoveryWrap and 16 or (recoveryW - 152), factoryY, 136, 22, function()
            M.CallIf(M.StageFactoryReset)
        end, "danger")
        if recoveryWrap then
            local textX = recoveryNarrow and 160 or 160
            local textY = recoveryNarrow and -160 or -128
            W.Text(recovery, "Factory reset affects every MSUF setting.", textX, textY, recoveryW - textX - 16, T.colors.muted)
        end
    end
    local scalingTop = recoveryTop - recoveryH - 10
    local scalingOpen = M.dashboardScalingOpen == true
    local scalingColumns = (recoveryW >= 960) and 3 or ((recoveryW >= 680) and 2 or 1)
    local scalingH = scalingOpen and ((scalingColumns == 3) and 250 or ((scalingColumns == 2) and 382 or 548)) or 42
    local scaling = Card(root, "", x0, scalingTop, recoveryW, scalingH, { 0.030, 0.040, 0.078, 0.86 }, T.colors.borderSoft)
    DashboardDisclosure(scaling, "Scaling", scalingOpen, "dashboardScalingOpen", recoveryW, function(scaleHead)
        if recoveryW < 520 then return end
        local _, ui = GlobalState()
        local uiValue = ui.Enabled and M.Format("%d%%", Percent(ui.Scale, 1)) or M.Tr("Off")
        Pill(scaleHead, M.Format("UI %s", uiValue), recoveryW - 250, -11, 64)
        Pill(scaleHead, M.Format("Menu %d%%", Percent(g.slashMenuScale, 1)), recoveryW - 180, -11, 76)
        Pill(scaleHead, M.Format("Frames %d%%", Percent(g.msufUiScale, 1)), recoveryW - 98, -11, 84)
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
        local function BuildScaleSlider(parent, label, x, top, width, minPct, maxPct, stepPct)
            local slider = W.Slider(parent, label, minPct, maxPct, stepPct, width)
            HideSliderValueBox(slider)
            slider:ClearAllPoints()
            slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, top - 64)
            if slider._msuf2SetLayoutWidth then slider:_msuf2SetLayoutWidth(width) end
            if slider._msuf2Title then
                slider._msuf2Title:ClearAllPoints()
                slider._msuf2Title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, top)
                slider._msuf2Title:SetWidth(width)
            end
            EnablePercentWheel(slider, minPct, maxPct, stepPct)
            return slider
        end
        local function BuildSimpleScaleColumn(opts)
            W.Text(scaling, opts.help, opts.x, opts.top - 20, colW, T.colors.muted)
            local status = W.Text(scaling, "", opts.x, opts.top - 40, colW, T.colors.muted)
            local slider = BuildScaleSlider(scaling, opts.label, opts.x, opts.top, colW, opts.minPct, opts.maxPct, opts.stepPct)
            local apply, revert
            local function Refresh()
                local applied = opts.applied()
                local pending = opts.pending()
                local changed = math.abs(applied - pending) > 0.001
                status:SetText(M.Format(M.Tr("Applied: %d%%  Selected: %d%%"), Percent(applied, 1), Percent(pending, 1)))
                SetSliderValueSafe(slider, SnapPct(pending * 100, opts.minPct, opts.maxPct, opts.stepPct))
                if apply then
                    if changed then apply:Enable() else apply:Disable() end
                    if apply.SetActive then apply:SetActive(changed) end
                end
                if revert then
                    if changed then revert:Enable() else revert:Disable() end
                end
            end
            slider:HookScript("OnValueChanged", function(self, value)
                if self._msuf2Refreshing then return end
                local pct = SnapPct(value, opts.minPct, opts.maxPct, opts.stepPct)
                if pct ~= value then SetSliderValueSafe(self, pct) end
                opts.set(Clamp(pct / 100, opts.minPct / 100, opts.maxPct / 100))
                Refresh()
            end)
            apply = Button(scaling, "Apply", opts.x, opts.top - 100, 72, 20, function()
                opts.apply(opts.pending())
                Refresh()
            end, "primary")
            revert = Button(scaling, "Revert", opts.x + 82, opts.top - 100, 72, 20, function()
                opts.clear()
                Refresh()
            end)
            return Refresh
        end
        W.Text(scaling, "Changes the global WoW UI scale through MSUF presets.", globalX, globalTop - 20, colW, T.colors.muted)
        local globalStatus = W.Text(scaling, "", globalX, globalTop - 40, colW, T.colors.muted)
        local globalScale = BuildScaleSlider(scaling, "Global UI Scale", globalX, globalTop, colW, 30, 150, 1)
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
        local RefreshMsufScale = BuildSimpleScaleColumn({
            x = msufX, top = msufTop, label = "MSUF Frame Scale", help = "Changes the actual MSUF unit frames in-game.",
            minPct = 25, maxPct = 150, stepPct = 5,
            applied = AppliedMsufScale,
            pending = PendingMsufScale,
            set = function(value) pendingMsufScale = value end,
            clear = function() pendingMsufScale = nil end,
            apply = function(scaleValue)
                local dbScale = M.GetGeneralDB()
                dbScale.msufUiScale = scaleValue
                pendingMsufScale = nil
                if type(_G.MSUF_ApplyMsufScale) == "function" then pcall(_G.MSUF_ApplyMsufScale, scaleValue) end
                if M.RequestGeneralApply then M.RequestGeneralApply("MSUF2_DASH_MSUF_SCALE", { preview = true, applyAll = false }) end
                local UF = MSUF and MSUF.UF
                if UF and UF.Apply then UF.Apply(nil) end
            end,
        })
        local RefreshMenuScale = BuildSimpleScaleColumn({
            x = menuX, top = menuTop, label = "MSUF Menu Scale", help = "Changes only this configuration menu window.",
            minPct = 25, maxPct = 150, stepPct = 5,
            applied = AppliedMenuScale,
            pending = PendingMenuScale,
            set = function(value) pendingMenuScale = value end,
            clear = function() pendingMenuScale = nil end,
            apply = function(scaleValue)
                local dbScale = M.GetGeneralDB()
                dbScale.slashMenuScale = scaleValue
                pendingMenuScale = nil
                if M.frame and M.frame.SetScale then M.frame:SetScale((M.GetEffectiveMenuScale and M.GetEffectiveMenuScale(scaleValue)) or scaleValue) end
            end,
        })
        M.TrackRefresh(ctx, RefreshGlobalScale)
        M.TrackRefresh(ctx, RefreshMsufScale)
        M.TrackRefresh(ctx, RefreshMenuScale)
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
    local supportTitle = T.Font(support, "GameFontNormal", M.Tr("How to support MSUF"), T.colors.text)
    supportTitle:SetPoint("TOPLEFT", support, "TOPLEFT", 16, -16)
    local supportTextW = max(160, recoveryW - (supportCompact and 32 or 230))
    local supportDesc = W.Text(support, "If MSUF helps your UI, support links are one click away.", 16, -42, supportTextW, T.colors.muted)
    if supportDesc.SetWordWrap then supportDesc:SetWordWrap(true) end
    if supportDesc.SetNonSpaceWrap then supportDesc:SetNonSpaceWrap(true) end
    local aboutVer
    if _G.C_AddOns and type(_G.C_AddOns.GetAddOnMetadata) == "function" then aboutVer = _G.C_AddOns.GetAddOnMetadata("MidnightSimpleUnitFrames", "Version") end
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
            if type(_G.MSUF_ShowCopyLink) == "function" then _G.MSUF_ShowCopyLink(data.title, data.url) end
        end)
        AddTooltip(btn, data.title, data.tooltip)
        if type(M.RegisterSearchWidget) == "function" then
            M.RegisterSearchWidget(btn, {
                label = data.title,
                kind = "button",
                anchor = supportTitle,
                keywords = { data.tooltip, "How to support MSUF", "support links", data.url },
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
    if sideBySide then bottom = min(bottom, sideBottom) end
    ctx:SetContentHeight(math.abs(bottom) + 42)
end
M.RegisterPage("home", { title = "MSUF Menu", build = BuildDashboardUX, version = 7 })
