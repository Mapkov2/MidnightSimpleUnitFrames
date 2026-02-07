local addonName, ns = ...
ns = ns or {}

-- Misc Options (spec-driven, single-file)
-- IMPORTANT: list this file in the .toc BEFORE MSUF_Options_Core.lua so the builder is available at panel build time.

function ns.MSUF_Options_Misc_Build(panel, miscGroup)
    if not panel or not miscGroup then return end
    if miscGroup._msufMiscSpecDrivenV1 then return end
    miscGroup._msufMiscSpecDrivenV1 = true

    -- Localize the dropdown click-expander (it is a local helper in Options_Core; exported there onto ns).
    local ExpandDropdownClickArea = (ns and ns.MSUF_ExpandDropdownClickArea) or _G.MSUF_ExpandDropdownClickArea

    local function EnsureGeneral()
        if EnsureDB then EnsureDB() end
        MSUF_DB = MSUF_DB or {}
        MSUF_DB.general = MSUF_DB.general or {}
        return MSUF_DB.general
    end
    local function EnsureGameplay()
        if EnsureDB then EnsureDB() end
        MSUF_DB = MSUF_DB or {}
        MSUF_DB.gameplay = MSUF_DB.gameplay or {}
        return MSUF_DB.gameplay
    end


    -------------------------------------------------------------------------
    -- UI helpers (kept local to this file; no feature split)
    -------------------------------------------------------------------------

    local UI = {}

    function UI:MakePanel(parent, titleText, anchorTo, x, y, w, h)
        local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        p:SetPoint("TOPLEFT", anchorTo or parent, "TOPLEFT", x or 0, y or 0)
        p:SetSize(w or 330, h or 330)

        local header = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        header:SetText(titleText or "")
        header:SetTextColor(1, 0.82, 0)
        header:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -14)

        local line = p:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.08)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
        line:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -38)

        -- Keep Misc clean (no boxed borders; match your current Misc look)
        if (not p.SetBackdrop) and BackdropTemplateMixin and Mixin then
            Mixin(p, BackdropTemplateMixin)
        end
        if p.SetBackdrop then
            p:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            p:SetBackdropColor(0, 0, 0, 0)
            p:SetBackdropBorderColor(0, 0, 0, 0)
        end

        p._msufHeader = header
        p._msufHeaderLine = line
        return p
    end

    function UI:Label(parent, text, anchor, rel, x, y, font)
        local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
        fs:SetText(text or "")
        fs:SetTextColor(1, 0.82, 0)
        if anchor and rel then
            fs:SetPoint(anchor, rel, x or 0, y or 0)
        end
        return fs
    end

    -- Normalize checkbox size/label alignment across different templates.
    local function GetToggleRefSizeAndFont()
        local ref = _G.MSUF_DisableBlizzUFCheck
        local w, h
        if ref and ref.GetSize then w, h = ref:GetSize() end
        if type(w) ~= "number" or w <= 0 then w = 24 end
        if type(h) ~= "number" or h <= 0 then h = 24 end

        local fs = ref and (ref.text or ref.Text) or nil
        if (not fs) and ref and ref.GetName and ref:GetName() and _G then
            fs = _G[ref:GetName() .. "Text"]
        end

        local font, size, flags, fo
        if fs and fs.GetFont then
            font, size, flags = fs:GetFont()
        end
        if (not font or not size) and fs and fs.GetFontObject then
            fo = fs:GetFontObject()
        end
        return w, h, font, size, flags, fo
    end

    function UI:StyleCheckbox(cb)
        if not cb then return end

        local tw, th, font, size, flags, fo = GetToggleRefSizeAndFont()

        if cb.SetSize then
            cb:SetSize(tw, th)
        elseif cb.SetHeight then
            cb:SetHeight(th)
        end

        if cb.SetHitRectInsets then
            cb:SetHitRectInsets(0, -10, 0, 0)
        end

        local fs = cb.text or cb.Text
        if (not fs) and cb.GetName and cb:GetName() and _G then
            fs = _G[cb:GetName() .. "Text"]
        end
        if fs and fs.ClearAllPoints and fs.SetPoint then
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", cb, "RIGHT", 0, 0)
        end

        if fs then
            if font and size and fs.SetFont then
                fs:SetFont(font, size, flags)
            elseif fo and fs.SetFontObject then
                fs:SetFontObject(fo)
            end
        end

        if MSUF_StyleToggleText then MSUF_StyleToggleText(cb) end
        if MSUF_StyleCheckmark then MSUF_StyleCheckmark(cb) end
    end

    function UI:MakeCheck(spec)
        local name = spec.name
        local cb = name and _G[name] or nil
        if not cb then
            cb = CreateFrame("CheckButton", name, spec.parent, spec.template or "InterfaceOptionsCheckButtonTemplate")
        end
        cb:SetParent(spec.parent)
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", spec.anchor, "BOTTOMLEFT", spec.x or 0, spec.y or 0)

        -- Label
        local label = spec.label or ""
        if cb.Text and cb.Text.SetText then
            cb.Text:SetText(label)
        elseif cb.text and cb.text.SetText then
            cb.text:SetText(label)
        else
            local t = name and _G[name .. "Text"]
            if t and t.SetText then t:SetText(label) end
        end

        self:StyleCheckbox(cb)

        cb:SetScript("OnShow", function(selfBtn)
            local v = spec.get()
            selfBtn:SetChecked(v and true or false)
            if spec.onShow then
                spec.onShow(selfBtn, v)
            end
        end)

        cb:SetScript("OnClick", function(selfBtn)
            local want = selfBtn:GetChecked() and true or false
            if spec.beforeSet then
                local ok, newWant = spec.beforeSet(selfBtn, want)
                if ok == false then return end
                if type(newWant) == "boolean" then want = newWant end
            end
            spec.set(want)
            if spec.afterSet then spec.afterSet(selfBtn, want) end
        end)

        if spec.onEnter then cb:SetScript("OnEnter", function(selfBtn) spec.onEnter(selfBtn) end) end
        if spec.onLeave then cb:SetScript("OnLeave", function(selfBtn) spec.onLeave(selfBtn) end) end

        return cb
    end

    function UI:MakeSlider(spec)
        local name = spec.name
        local sl = name and _G[name] or nil
        if not sl then
            sl = CreateFrame("Slider", name, spec.parent, "OptionsSliderTemplate")
        end
        sl:SetParent(spec.parent)
        sl:ClearAllPoints()
        sl:SetPoint("TOPLEFT", spec.anchor, "BOTTOMLEFT", spec.x or 0, spec.y or 0)
        sl:SetMinMaxValues(spec.min, spec.max)
        sl:SetValueStep(spec.step)
        sl:SetObeyStepOnDrag(true)
        sl:SetWidth(spec.width or 270)

        local low = _G[sl:GetName() .. "Low"]
        local high = _G[sl:GetName() .. "High"]
        if low and low.SetText then low:SetText(spec.lowText or tostring(spec.min)) end
        if high and high.SetText then high:SetText(spec.highText or tostring(spec.max)) end

        local textFS = _G[sl:GetName() .. "Text"]
        local function SetTextForValue(v)
            if not textFS or not textFS.SetText then return end
            if spec.formatText then
                textFS:SetText(spec.formatText(v))
            else
                textFS:SetText(tostring(v))
            end
        end

        sl:SetScript("OnShow", function(selfSl)
            local v = spec.get()
            if type(v) ~= "number" then v = spec.default end
            if v < spec.min then v = spec.min elseif v > spec.max then v = spec.max end
            selfSl:SetValue(v)
            SetTextForValue(v)
        end)

        sl:SetScript("OnValueChanged", function(selfSl, value)
            local v = tonumber(value) or spec.default
            if v < spec.min then v = spec.min elseif v > spec.max then v = spec.max end
            spec.set(v)
            SetTextForValue(v)
        end)

        return sl
    end

    function UI:MakeDropdown(spec)
        local name = spec.name
        local dd = name and _G[name] or nil
        if not dd then
            dd = CreateFrame("Frame", name, spec.parent, "UIDropDownMenuTemplate")
        end
        dd:SetParent(spec.parent)
        dd:ClearAllPoints()
        dd:SetPoint("TOPLEFT", spec.anchor, "BOTTOMLEFT", spec.x or 0, spec.y or 0)

        if ExpandDropdownClickArea then ExpandDropdownClickArea(dd) end
        UIDropDownMenu_SetWidth(dd, spec.width or 180)

        local function OnClick(btn)
            UIDropDownMenu_SetSelectedValue(dd, btn.value)
            spec.set(btn.value)
        end

        local function Initialize(self, level)
            local cur = spec.get()
            for _, opt in ipairs(spec.options) do
                local info = UIDropDownMenu_CreateInfo()
                info.func = OnClick
                info.text = opt.text
                info.value = opt.value
                info.checked = (cur == opt.value)
                UIDropDownMenu_AddButton(info, level)
            end
        end

        UIDropDownMenu_Initialize(dd, Initialize)

        dd:SetScript("OnShow", function(selfDD)
            local cur = spec.get()
            UIDropDownMenu_SetSelectedValue(selfDD, cur)
            local label = nil
            for _, opt in ipairs(spec.options) do
                if opt.value == cur then label = opt.text break end
            end
            UIDropDownMenu_SetText(selfDD, label or (spec.fallbackText or tostring(cur)))
        end)

        return dd
    end

    -------------------------------------------------------------------------
    -- Layout
    -------------------------------------------------------------------------

    local LEFT_W, RIGHT_W = 330, 330

    local leftPanel = UI:MakePanel(miscGroup, "Updates", miscGroup, 0, -110, LEFT_W, 330)
    local rightPanel = UI:MakePanel(miscGroup, "Unit info panel", leftPanel, LEFT_W, 0, RIGHT_W, 330)
    local bottomPanel = UI:MakePanel(miscGroup, "Indicators", leftPanel, 0, -(330 + 16), LEFT_W + RIGHT_W, 180)

    local centerDivider = miscGroup:CreateTexture(nil, "ARTWORK")
    centerDivider:SetColorTexture(1, 1, 1, 0.10)
    centerDivider:SetWidth(1)
    centerDivider:SetPoint("TOP", leftPanel, "TOPRIGHT", 0, -46)
    centerDivider:SetPoint("BOTTOM", bottomPanel, "BOTTOMLEFT", LEFT_W, 12)

    -------------------------------------------------------------------------
    -- Updates (left panel)
    -------------------------------------------------------------------------

    local function SetPresetButtonActive(btn, active)
        if not btn then return end
        btn._msufActive = active and true or false
        local fs = (btn.GetFontString and btn:GetFontString()) or nil
        if btn._msufActive then
            if btn.LockHighlight then btn:LockHighlight() end
            if fs and fs.SetTextColor then fs:SetTextColor(1, 0.82, 0) end
        else
            if btn.UnlockHighlight then btn:UnlockHighlight() end
            if fs and fs.SetTextColor then fs:SetTextColor(1, 1, 1) end
        end
    end

    local function RefreshPresetButtons()
        local g = EnsureGeneral()
        local preset = g.miscUpdatesPreset or "balanced"
        SetPresetButtonActive(leftPanel._msufPresetPerf, preset == "perf")
        SetPresetButtonActive(leftPanel._msufPresetBal,  preset == "balanced")
        SetPresetButtonActive(leftPanel._msufPresetAcc,  preset == "accurate")
    end

    local sliders = {}

    do
        local row = CreateFrame("Frame", nil, leftPanel)
        leftPanel._msufPresetRow = row
        row:SetSize(270, 22)
        row:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 14, -48)

        local function MakePresetButton(label, onClick)
            local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            b:SetSize(86, 20)
            b:SetText(label or "")
            if MSUF_SkinMidnightActionButton then
                MSUF_SkinMidnightActionButton(b, { textR = 1, textG = 0.85, textB = 0.1 })
            end
            b:SetScript("OnClick", onClick)
            return b
        end

        local gap = 6
        leftPanel._msufPresetPerf = MakePresetButton("Perf...", function()
            local g = EnsureGeneral()
            g.miscUpdatesPreset = "perf"
            sliders.updateInterval:SetValue(0.12)
            sliders.castbarUpdate:SetValue(0.06)
            sliders.ufcoreBudget:SetValue(1.0)
            sliders.ufcoreUrgent:SetValue(6)
            RefreshPresetButtons()
        end)
        leftPanel._msufPresetPerf:SetPoint("LEFT", row, "LEFT", 0, 0)

        leftPanel._msufPresetBal = MakePresetButton("Balanced...", function()
            local g = EnsureGeneral()
            g.miscUpdatesPreset = "balanced"
            sliders.updateInterval:SetValue(0.05)
            sliders.castbarUpdate:SetValue(0.02)
            sliders.ufcoreBudget:SetValue(2.0)
            sliders.ufcoreUrgent:SetValue(10)
            RefreshPresetButtons()
        end)
        leftPanel._msufPresetBal:SetPoint("LEFT", leftPanel._msufPresetPerf, "RIGHT", gap, 0)

        leftPanel._msufPresetAcc = MakePresetButton("Accurate...", function()
            local g = EnsureGeneral()
            g.miscUpdatesPreset = "accurate"
            sliders.updateInterval:SetValue(0.01)
            sliders.castbarUpdate:SetValue(0.01)
            sliders.ufcoreBudget:SetValue(5.0)
            sliders.ufcoreUrgent:SetValue(50)
            RefreshPresetButtons()
        end)
        leftPanel._msufPresetAcc:SetPoint("LEFT", leftPanel._msufPresetBal, "RIGHT", gap, 0)

        row:SetScript("OnShow", RefreshPresetButtons)
        RefreshPresetButtons()
    end

    sliders.updateInterval = UI:MakeSlider({
        name = "MSUF_UpdateIntervalSlider",
        parent = leftPanel,
        anchor = leftPanel._msufPresetRow,
        x = 0, y = -18,
        min = 0.01, max = 0.30, step = 0.01,
        width = 270,
        default = 0.05,
        lowText = "0.01",
        highText = "0.30",
        get = function()
            local g = EnsureGeneral()
            return g.frameUpdateInterval or MSUF_FrameUpdateInterval or 0.05
        end,
        set = function(v)
            local g = EnsureGeneral()
            g.frameUpdateInterval = v
            MSUF_FrameUpdateInterval = v
        end,
        formatText = function(v) return string.format("Unit update interval: %.2f s", v) end,
    })

    sliders.castbarUpdate = UI:MakeSlider({
        name = "MSUF_CastbarUpdateIntervalSlider",
        parent = leftPanel,
        anchor = sliders.updateInterval,
        x = 0, y = -32,
        min = 0.01, max = 0.30, step = 0.01,
        width = 270,
        default = 0.02,
        lowText = "0.01",
        highText = "0.30",
        get = function()
            local g = EnsureGeneral()
            return g.castbarUpdateInterval or MSUF_CastbarUpdateInterval or 0.02
        end,
        set = function(v)
            local g = EnsureGeneral()
            g.castbarUpdateInterval = v
            MSUF_CastbarUpdateInterval = v
        end,
        formatText = function(v) return string.format("Castbar update interval: %.2f s", v) end,
    })

    sliders.ufcoreBudget = UI:MakeSlider({
        name = "MSUF_UFCoreFlushBudgetSlider",
        parent = leftPanel,
        anchor = sliders.castbarUpdate,
        x = 0, y = -32,
        min = 0.5, max = 5.0, step = 0.1,
        width = 270,
        default = 2.0,
        lowText = "0.5",
        highText = "5.0",
        get = function()
            local g = EnsureGeneral()
            return g.ufcoreFlushBudgetMs
        end,
        set = function(v)
            local g = EnsureGeneral()
            g.ufcoreFlushBudgetMs = v
        end,
        formatText = function(v) return string.format("UFCore flush budget: %.1f ms", v) end,
    })

    sliders.ufcoreUrgent = UI:MakeSlider({
        name = "MSUF_UFCoreUrgentCapSlider",
        parent = leftPanel,
        anchor = sliders.ufcoreBudget,
        x = 0, y = -32,
        min = 1, max = 50, step = 1,
        width = 270,
        default = 10,
        lowText = "1",
        highText = "50",
        get = function()
            local g = EnsureGeneral()
            return g.ufcoreUrgentMaxPerFlush
        end,
        set = function(v)
            local g = EnsureGeneral()
            g.ufcoreUrgentMaxPerFlush = math.floor((tonumber(v) or 10) + 0.5)
        end,
        formatText = function(v)
            local n = math.floor((tonumber(v) or 10) + 0.5)
            return string.format("UFCore urgent cap: %d", n)
        end,
    })


    -------------------------------------------------------------------------
    -- Unit info panel & misc toggles (right panel)
    -------------------------------------------------------------------------

    local infoTooltipDisable = UI:MakeCheck({
        name = "MSUF_InfoTooltipDisableCheck",
        parent = rightPanel,
        template = "UICheckButtonTemplate",
        anchor = rightPanel._msufHeaderLine,
        x = 0, y = -10,
        label = "Disable MSUF unit info panel tooltips",
        get = function()
            local g = EnsureGeneral()
            return g.disableUnitInfoTooltips and true or false
        end,
        set = function(v)
            local g = EnsureGeneral()
            g.disableUnitInfoTooltips = v and true or false
        end,
    })

    local posLabel = UI:Label(rightPanel, "MSUF unit info panel position", "TOPLEFT", infoTooltipDisable, 0, -28)
    UI:MakeDropdown({
        name = "MSUF_InfoTooltipPosDropdown",
        parent = rightPanel,
        anchor = posLabel,
        x = -16, y = -8,
        width = 180,
        options = {
            { text = "Blizzard Classic", value = "classic" },
            { text = "Modern (under cursor)", value = "modern" },
        },
        fallbackText = "Blizzard Classic",
        get = function()
            local g = EnsureGeneral()
            return g.unitInfoTooltipStyle or "classic"
        end,
        set = function(v)
            local g = EnsureGeneral()
            g.unitInfoTooltipStyle = v
        end,
    })

    local blizzHeader = UI:Label(rightPanel, "Blizzard frames", "TOPLEFT", posLabel, 0, -64)
    local blizzLine = rightPanel:CreateTexture(nil, "OVERLAY")
    blizzLine:SetColorTexture(1, 1, 1, 0.10)
    blizzLine:SetHeight(1)
    blizzLine:SetPoint("TOPLEFT", blizzHeader, "BOTTOMLEFT", 0, -6)
    blizzLine:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -14, -120)

    local blizzUFDisable = UI:MakeCheck({
        name = "MSUF_DisableBlizzUFCheck",
        parent = rightPanel,
        template = "UICheckButtonTemplate",
        anchor = blizzLine,
        x = 0, y = -10,
        label = "Disable Blizzard unitframes",
        get = function()
            local g = EnsureGeneral()
            return (g.disableBlizzardUnitFrames ~= false) and true or false
        end,
        set = function(v)
            local g = EnsureGeneral()
            g.disableBlizzardUnitFrames = v and true or false
            print("|cffffd700MSUF:|r Changing Blizzard unitframes visibility requires a /reload.")
        end,
    })

    if not StaticPopupDialogs["MSUF_RELOAD_PLAYERFRAME_HIDE_MODE"] then
        StaticPopupDialogs["MSUF_RELOAD_PLAYERFRAME_HIDE_MODE"] = {
            text = "This changes how MSUF hides the Blizzard PlayerFrame.\n\nOFF: Compatibility mode (keeps PlayerFrame alive as hidden parent for resource bar addons).\nON: Hard-hide mode (fully hides PlayerFrame; may break some resource bar addons).\n\nA UI reload is required.",
            button1 = RELOADUI,
            button2 = CANCEL,
            OnAccept = function() ReloadUI() end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    local function HardKillTooltip_OnEnter(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Hide Blizzard PlayerFrame (Turn off for other addon compatibility)", 1, 0.9, 0.4)
        GameTooltip:AddLine("OFF: Keeps PlayerFrame alive as a hidden parent.", 0.95, 0.95, 0.95, true)
        GameTooltip:AddLine("ON: Fully hides PlayerFrame (may break some resource bar addons).", 1, 0.82, 0.2, true)
        GameTooltip:AddLine("Requires a UI reload.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end

    local function HardKillTooltip_OnLeave()
        if GameTooltip then GameTooltip:Hide() end
    end

    UI:MakeCheck({
        name = "MSUF_HardKillPlayerFrameCheck",
        parent = rightPanel,
        template = "UICheckButtonTemplate",
        anchor = blizzUFDisable,
        x = 0, y = -10,
        label = "Fully Hide Blizzard PlayerFrame - Turn off for resource bar compatibility",
        get = function()
            local g = EnsureGeneral()
            return (g.hardKillBlizzardPlayerFrame == true)
        end,
        set = function(v)
            local g = EnsureGeneral()
            g.hardKillBlizzardPlayerFrame = v and true or false
            if StaticPopup_Show then StaticPopup_Show("MSUF_RELOAD_PLAYERFRAME_HIDE_MODE") end
        end,
        onShow = function(selfBtn)
            local g = EnsureGeneral()
            local enabled = (g.disableBlizzardUnitFrames ~= false)
            if selfBtn.SetEnabled then selfBtn:SetEnabled(enabled) end
            selfBtn:SetAlpha(enabled and 1 or 0.4)
        end,
        onEnter = HardKillTooltip_OnEnter,
        onLeave = HardKillTooltip_OnLeave,
    })

    local minimapIconCheck = UI:MakeCheck({
        name = "MSUF_MinimapIconCheck",
        parent = rightPanel,
        template = "InterfaceOptionsCheckButtonTemplate",
        anchor = _G.MSUF_HardKillPlayerFrameCheck,
        x = 0, y = -12,
        label = "Show MSUF minimap icon",
        get = function()
            local g = EnsureGeneral()
            return (g.showMinimapIcon ~= false) and true or false
        end,
        set = function(v)
            local g = EnsureGeneral()
            local enabled = v and true or false
            g.showMinimapIcon = enabled

            if _G.MSUF_SetMinimapIconEnabled then
                _G.MSUF_SetMinimapIconEnabled(enabled)
            else
                g.minimapIconDB = g.minimapIconDB or {}
                g.minimapIconDB.hide = (not enabled) and true or false
            end
        end,
    })

    local targetSoundsCheck = UI:MakeCheck({
        name = "MSUF_TargetSoundsCheck",
        parent = rightPanel,
        template = "InterfaceOptionsCheckButtonTemplate",
        anchor = minimapIconCheck,
        x = 0, y = -12,
        label = "Play sound on Target/Target Lost",
        get = function()
            local g = EnsureGeneral()
            return (g.playTargetSelectLostSounds == true)
        end,
        set = function(v)
            local g = EnsureGeneral()
            g.playTargetSelectLostSounds = v and true or false
            if _G.MSUF_TargetSoundDriver_ResetState then _G.MSUF_TargetSoundDriver_ResetState() end
            if v and _G.MSUF_TargetSoundDriver_Ensure then _G.MSUF_TargetSoundDriver_Ensure() end
        end,
    })



    -------------------------------------------------------------------------
    -- Indicators (bottom panel)
    -------------------------------------------------------------------------

    local function GetStatusDB()
        local g = EnsureGeneral()
        g.statusIndicators = g.statusIndicators or {}
        return g.statusIndicators
    end

    local function IsBetaClient()
        local ok, v
        if type(_G.IsBetaBuild) == "function" then ok, v = pcall(_G.IsBetaBuild); if ok and v then return true end end
        if type(_G.IsTestBuild) == "function" then ok, v = pcall(_G.IsTestBuild); if ok and v then return true end end
        if type(_G.IsAlphaBuild) == "function" then ok, v = pcall(_G.IsAlphaBuild); if ok and v then return true end end
        return false
    end

    local function EnsureBetaStatusPopup()
        if not _G.StaticPopupDialogs then return end
        if _G.StaticPopupDialogs["MSUF_BETA_STATUS_AFKDND_WARNING"] then return end

        _G.StaticPopupDialogs["MSUF_BETA_STATUS_AFKDND_WARNING"] = {
            text = "BETA WARNING:\n\nAFK/DND status indicators are currently unreliable on the Beta client due to API changes.\nThey may not update correctly or may behave unexpectedly.\n\nEnable anyway?",
            button1 = "Enable",
            button2 = "Cancel",
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
            OnAccept = function(popup, data)
                local d = data or (popup and popup.data)
                if not d or not d.key or not d.cb or not d.getDB then return end
                local db = d.getDB()
                db[d.key] = true
                d.cb:SetChecked(true)
                if _G.MSUF_RefreshStatusIndicators then _G.MSUF_RefreshStatusIndicators() end
            end,
            OnCancel = function(popup, data)
                local d = data or (popup and popup.data)
                if not d or not d.key or not d.cb or not d.getDB then return end
                local db = d.getDB()
                db[d.key] = false
                d.cb:SetChecked(false)
                if _G.MSUF_RefreshStatusIndicators then _G.MSUF_RefreshStatusIndicators() end
            end,
        }
    end

    local statusHeader = UI:Label(bottomPanel, "Status indicators", "TOPLEFT", bottomPanel, 14, -34)
    local statusLine = bottomPanel:CreateTexture(nil, "ARTWORK")
    statusLine:SetColorTexture(1, 1, 1, 0.10)
    statusLine:SetHeight(1)
    statusLine:SetPoint("TOPLEFT", statusHeader, "BOTTOMLEFT", 0, -8)
    statusLine:SetPoint("TOPRIGHT", bottomPanel, "TOPRIGHT", -14, -42)

    local _, refH = GetToggleRefSizeAndFont()
    local step = (type(refH) == "number" and refH > 0) and (refH + 6) or 30
    local y0 = -10

    local statusSpecs = {
        { key = "showAFK",   label = "Show AFK",   confirmBeta = true },
        { key = "showDND",   label = "Show DND",   confirmBeta = true },
        { key = "showDead",  label = "Show Dead" },
        { key = "showGhost", label = "Show Ghost" },
    }

    bottomPanel._msufStatusCBs = bottomPanel._msufStatusCBs or {}
    for i, s in ipairs(statusSpecs) do
        local cb = CreateFrame("CheckButton", nil, bottomPanel, "InterfaceOptionsCheckButtonTemplate")
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", statusHeader, "BOTTOMLEFT", 0, y0 - ((i - 1) * step))
        if cb.Text and cb.Text.SetText then cb.Text:SetText(s.label) end
        UI:StyleCheckbox(cb)

        cb:SetScript("OnShow", function(selfBtn)
            local db = GetStatusDB()
            local v = db[s.key]
            if v == nil then v = false end
            selfBtn:SetChecked(v and true or false)
        end)

        cb:SetScript("OnClick", function(selfBtn)
            local want = selfBtn:GetChecked() and true or false

            if want and s.confirmBeta and IsBetaClient() and _G.StaticPopup_Show then
                EnsureBetaStatusPopup()
                selfBtn:SetChecked(false)
                local db = GetStatusDB()
                db[s.key] = false

                local popup = _G.StaticPopup_Show("MSUF_BETA_STATUS_AFKDND_WARNING", nil, nil, { key = s.key, cb = selfBtn, getDB = GetStatusDB })
                if popup then return end
                want = true
                selfBtn:SetChecked(true)
            end

            local db = GetStatusDB()
            db[s.key] = want and true or false
            if _G.MSUF_RefreshStatusIndicators then _G.MSUF_RefreshStatusIndicators() end
        end)

        bottomPanel._msufStatusCBs[i] = cb
    end
end
