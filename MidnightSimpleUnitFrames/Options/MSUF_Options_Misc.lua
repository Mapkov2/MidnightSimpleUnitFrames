-- ---------------------------------------------------------------------------
-- MSUF_Options_Misc.lua  (Phase 9: Accordion UX)
--
-- Miscellaneous options: 4 collapsible sections.
-- 1. Update Intervals   2. Unitframe Tooltips   3. Blizzard Frames
-- 4. Range Fade
-- ---------------------------------------------------------------------------
local addonName, ns = ...
local TR = ns.TR
local UI = ns.UI

function ns.MSUF_Options_Misc_Build(panel, miscGroup)
    if not panel or not miscGroup then return end
    if miscGroup._msufBuilt then return end
    miscGroup._msufBuilt = true

    if _G.MSUF_Search_RegisterRoots then
        _G.MSUF_Search_RegisterRoots({ "misc" }, miscGroup, "Miscellaneous")
    end

    local function G() ns.EnsureDB(); return MSUF_DB.general end
    local function T() ns.EnsureDB(); MSUF_DB.target = MSUF_DB.target or {}; return MSUF_DB.target end
    local function F() ns.EnsureDB(); MSUF_DB.focus = MSUF_DB.focus or {}; return MSUF_DB.focus end
    local function B() ns.EnsureDB(); MSUF_DB.boss = MSUF_DB.boss or {}; return MSUF_DB.boss end

    local TEX_W8 = "Interface\\Buttons\\WHITE8x8"
    local CreateFrame = CreateFrame
    local math_pi = math.pi
    local SECTION_W = 680
    local SECTION_COLLAPSED_H = 28

    local scrollFrame = CreateFrame("ScrollFrame", "MSUF_MiscScrollFrame", miscGroup, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", miscGroup, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", miscGroup, "BOTTOMRIGHT", -28, 0)
    if scrollFrame.EnableMouseWheel then scrollFrame:EnableMouseWheel(true) end

    local scrollChild = CreateFrame("Frame", "MSUF_MiscScrollChild", scrollFrame)
    scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    scrollChild:SetSize(SECTION_W + 32, 1)
    scrollFrame:SetScrollChild(scrollChild)

    if scrollFrame.SetScript then
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local step = 40
            local current = self.GetVerticalScroll and self:GetVerticalScroll() or 0
            local newValue = current - ((tonumber(delta) or 0) * step)
            if newValue < 0 then newValue = 0 end
            local maxScroll = 0
            if self.GetVerticalScrollRange then
                maxScroll = self:GetVerticalScrollRange() or 0
            end
            if newValue > maxScroll then newValue = maxScroll end
            if self.SetVerticalScroll then self:SetVerticalScroll(newValue) end
        end)
    end

    local RefreshMiscScrollLayout

    -- =====================================================================
    -- Collapsible section helper
    -- =====================================================================
    local function MakeCollapsibleSection(parent, expandedH, titleText, defaultOpen)
        local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        box:SetSize(SECTION_W, defaultOpen and expandedH or SECTION_COLLAPSED_H)
        box:SetBackdrop({
            bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        box:SetBackdropColor(0, 0, 0, 0.25)
        box:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)
        box._msufExpandedH = expandedH
        box._msufCollapsedH = SECTION_COLLAPSED_H
        box._msufCollapsed = not defaultOpen

        local hdr = CreateFrame("Button", nil, box)
        hdr:SetHeight(24)
        hdr:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
        hdr:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)

        local chevron = hdr:CreateTexture(nil, "OVERLAY")
        chevron:SetSize(12, 12)
        chevron:SetPoint("LEFT", hdr, "LEFT", 12, 0)
        chevron:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        MSUF_ApplyCollapseVisual(chevron, nil, defaultOpen)

        local title = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("LEFT", chevron, "RIGHT", 6, 0)
        title:SetText(TR(titleText))

        local hint = hdr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("RIGHT", hdr, "RIGHT", -12, 0)
        hint:SetText(defaultOpen and "" or TR("click to expand"))
        hint:SetTextColor(0.45, 0.52, 0.65)

        local divider = box:CreateTexture(nil, "ARTWORK")
        divider:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -28)
        divider:SetPoint("TOPRIGHT", box, "TOPRIGHT", -8, -28)
        divider:SetHeight(1)
        divider:SetColorTexture(1, 1, 1, 0.08)

        local body = CreateFrame("Frame", nil, box)
        body:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -30)
        body:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
        body:SetShown(defaultOpen)
        box._msufBody = body

        local function ApplyState()
            local open = not box._msufCollapsed
            body:SetShown(open)
            box:SetHeight(open and box._msufExpandedH or box._msufCollapsedH)
            MSUF_ApplyCollapseVisual(chevron, hint, open)
            if type(RefreshMiscScrollLayout) == "function" then
                RefreshMiscScrollLayout()
            end
        end

        hdr:SetScript("OnClick", function()
            box._msufCollapsed = not box._msufCollapsed
            ApplyState()
        end)
        do
            local hl = hdr:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.03)
        end

        box._msufApplyCollapseState = ApplyState
        return box, body
    end

    -- =====================================================================
    -- Section 1: Update Intervals (default open)
    -- =====================================================================
    local s1Box, s1Body = MakeCollapsibleSection(scrollChild, 340, "Update Intervals", true)
    s1Box:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, -115)

    local sliders = {}

    local function SetPresetButtonActive(btn, active)
        if not btn then return end
        btn._msufActive = active and true or false
        local fs = btn.GetFontString and btn:GetFontString()
        if btn._msufActive then
            if btn.LockHighlight then btn:LockHighlight() end
            if fs and fs.SetTextColor then fs:SetTextColor(1, 0.82, 0) end
        else
            if btn.UnlockHighlight then btn:UnlockHighlight() end
            if fs and fs.SetTextColor then fs:SetTextColor(1, 1, 1) end
        end
    end

    local presetPerf, presetBal, presetAcc

    local function RefreshPresetButtons()
        local preset = G().miscUpdatesPreset or "balanced"
        SetPresetButtonActive(presetPerf, preset == "perf")
        SetPresetButtonActive(presetBal,  preset == "balanced")
        SetPresetButtonActive(presetAcc,  preset == "accurate")
    end

    do
        local row = CreateFrame("Frame", nil, s1Body)
        row:SetSize(332, 22)
        row:SetPoint("TOPLEFT", s1Body, "TOPLEFT", 14, -6)

        local function MakePresetBtn(label, onClick)
            local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            b:SetSize(104, 20); b:SetText(label or "")
            if _G.MSUF_SkinMidnightActionButton then
                _G.MSUF_SkinMidnightActionButton(b, { textR = 1, textG = 0.85, textB = 0.1 })
            end
            b:SetScript("OnClick", onClick)
            return b
        end

        local gap = 8
        presetPerf = MakePresetBtn("Performance", function()
            G().miscUpdatesPreset = "perf"
            sliders.updateInterval:SetValue(0.12); sliders.castbarUpdate:SetValue(0.06)
            sliders.ufcoreBudget:SetValue(1.0); sliders.ufcoreUrgent:SetValue(6)
            RefreshPresetButtons()
        end)
        presetPerf:SetPoint("LEFT", row, "LEFT", 0, 0)

        presetBal = MakePresetBtn("Balanced", function()
            G().miscUpdatesPreset = "balanced"
            sliders.updateInterval:SetValue(0.05); sliders.castbarUpdate:SetValue(0.02)
            sliders.ufcoreBudget:SetValue(2.0); sliders.ufcoreUrgent:SetValue(10)
            RefreshPresetButtons()
        end)
        presetBal:SetPoint("LEFT", presetPerf, "RIGHT", gap, 0)

        presetAcc = MakePresetBtn("Accurate", function()
            G().miscUpdatesPreset = "accurate"
            sliders.updateInterval:SetValue(0.01); sliders.castbarUpdate:SetValue(0.01)
            sliders.ufcoreBudget:SetValue(5.0); sliders.ufcoreUrgent:SetValue(50)
            RefreshPresetButtons()
        end)
        presetAcc:SetPoint("LEFT", presetBal, "RIGHT", gap, 0)

        sliders.updateInterval = UI.Slider({
            name = "MSUF_UpdateIntervalSlider", parent = s1Body, compact = true,
            anchor = row, x = 0, y = -18,
            min = 0.01, max = 0.30, step = 0.01, width = 270, default = 0.05,
            lowText = "0.01", highText = "0.30",
            get = function() return G().frameUpdateInterval or _G.MSUF_FrameUpdateInterval or 0.05 end,
            set = function(v) G().frameUpdateInterval = v; _G.MSUF_FrameUpdateInterval = v end,
            formatText = function(v) return string.format("Unit update interval: %.2f s", v) end,
        })

        sliders.castbarUpdate = UI.Slider({
            name = "MSUF_CastbarUpdateIntervalSlider", parent = s1Body, compact = true,
            anchor = sliders.updateInterval, x = 0, y = -32,
            min = 0.01, max = 0.30, step = 0.01, width = 270, default = 0.02,
            lowText = "0.01", highText = "0.30",
            get = function() return G().castbarUpdateInterval or _G.MSUF_CastbarUpdateInterval or 0.02 end,
            set = function(v) G().castbarUpdateInterval = v; _G.MSUF_CastbarUpdateInterval = v end,
            formatText = function(v) return string.format("Castbar update interval: %.2f s", v) end,
        })

        sliders.ufcoreBudget = UI.Slider({
            name = "MSUF_UFCoreFlushBudgetSlider", parent = s1Body, compact = true,
            anchor = sliders.castbarUpdate, x = 0, y = -32,
            min = 0.5, max = 5.0, step = 0.1, width = 270, default = 2.0,
            lowText = "0.5", highText = "5.0",
            get = function() return G().ufcoreFlushBudgetMs end,
            set = function(v) G().ufcoreFlushBudgetMs = v end,
            formatText = function(v) return string.format("UFCore flush budget: %.1f ms", v) end,
        })

        sliders.ufcoreUrgent = UI.Slider({
            name = "MSUF_UFCoreUrgentCapSlider", parent = s1Body, compact = true,
            anchor = sliders.ufcoreBudget, x = 0, y = -32,
            min = 1, max = 50, step = 1, width = 270, default = 10,
            lowText = "1", highText = "50",
            get = function() return G().ufcoreUrgentMaxPerFlush end,
            set = function(v) G().ufcoreUrgentMaxPerFlush = math.floor((tonumber(v) or 10) + 0.5) end,
            formatText = function(v) return string.format("UFCore urgent cap: %d", math.floor((tonumber(v) or 10) + 0.5)) end,
        })

        row:SetScript("OnShow", RefreshPresetButtons)
        RefreshPresetButtons()
    end

    UI.Check({
        name = "MSUF_ShowWelcomeMessageCheck", parent = s1Body,
        anchor = sliders.ufcoreUrgent, x = 0, y = -20,
        label = TR("Show welcome message on login"),
        get = function() return G().showWelcomeMessage ~= false end,
        set = function(v) G().showWelcomeMessage = v end,
    })

    local versionCheck = UI.Check({
        name = "MSUF_VersionCheckEnabledCheck", parent = s1Body,
        anchor = _G.MSUF_ShowWelcomeMessageCheck, x = 0, y = -6,
        label = TR("Enable version check (peer-to-peer)"),
        get = function() return G().versionCheckEnabled ~= false end,
        set = function(v) G().versionCheckEnabled = v end,
    })

    -- =====================================================================
    -- Section 2: Unitframe Tooltips
    -- =====================================================================
    local s2Box, s2Body = MakeCollapsibleSection(scrollChild, 130, "Unitframe Tooltips", false)
    s2Box:SetPoint("TOPLEFT", s1Box, "BOTTOMLEFT", 0, -6)

    local infoTooltipDisable = UI.Check({
        name = "MSUF_InfoTooltipDisableCheck", parent = s2Body,
        anchor = s2Body, anchorPoint = "TOPLEFT", x = 12, y = -6,
        label = TR("Disable MSUF unitframe tooltips"),
        get = function() return G().disableUnitInfoTooltips and true or false end,
        set = function(v) G().disableUnitInfoTooltips = v end,
    })

    local posLabel = UI.Label({ parent = s2Body, text = TR("MSUF unitframe tooltip position"), anchor = infoTooltipDisable, y = -18 })

    UI.Dropdown({
        name = "MSUF_InfoTooltipPosDropdown", parent = s2Body,
        anchor = posLabel, x = -16, y = -4, width = 200,
        items = {
            { key = "classic", label = "Blizzard Classic" },
            { key = "modern", label = "Modern (under cursor)" },
        },
        get = function() return G().unitInfoTooltipStyle or "classic" end,
        set = function(v) G().unitInfoTooltipStyle = v end,
    })

    -- =====================================================================
    -- Section 3: Blizzard Frames
    -- =====================================================================
    local s3Box, s3Body = MakeCollapsibleSection(scrollChild, 190, "Blizzard Frames", false)
    s3Box:SetPoint("TOPLEFT", s2Box, "BOTTOMLEFT", 0, -6)

    local blizzUFDisable = UI.Check({
        name = "MSUF_DisableBlizzUFCheck", parent = s3Body,
        anchor = s3Body, anchorPoint = "TOPLEFT", x = 12, y = -6,
        label = TR("Disable Blizzard unitframes"),
        get = function() return G().disableBlizzardUnitFrames ~= false end,
        set = function(v)
            G().disableBlizzardUnitFrames = v
            print("|cffffd700MSUF:|r Changing Blizzard unitframes visibility requires a /reload.")
        end,
    })

    if not StaticPopupDialogs["MSUF_RELOAD_PLAYERFRAME_HIDE_MODE"] then
        StaticPopupDialogs["MSUF_RELOAD_PLAYERFRAME_HIDE_MODE"] = {
            text = "This changes how MSUF hides the Blizzard PlayerFrame.\n\nOFF: Compatibility mode (keeps PlayerFrame alive as hidden parent for resource bar addons).\nON: Hard-hide mode (fully hides PlayerFrame; may break some resource bar addons).\n\nA UI reload is required.",
            button1 = RELOADUI, button2 = CANCEL,
            OnAccept = function() ReloadUI() end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end

    UI.Check({
        name = "MSUF_HardKillPlayerFrameCheck", parent = s3Body,
        anchor = blizzUFDisable, x = 0, y = -8,
        label = TR("Fully Hide Blizzard PlayerFrame - Turn off for resource bar compatibility"),
        tooltip = TR("OFF: Keeps PlayerFrame alive as a hidden parent.\nON: Fully hides PlayerFrame (may break some resource bar addons).\nRequires a UI reload."),
        get = function() return G().hardKillBlizzardPlayerFrame == true end,
        set = function(v)
            G().hardKillBlizzardPlayerFrame = v
            if StaticPopup_Show then StaticPopup_Show("MSUF_RELOAD_PLAYERFRAME_HIDE_MODE") end
        end,
    })

    UI.Check({
        name = "MSUF_MinimapIconCheck", parent = s3Body,
        anchor = _G.MSUF_HardKillPlayerFrameCheck, x = 0, y = -8,
        label = TR("Show MSUF minimap icon"),
        get = function() return G().showMinimapIcon ~= false end,
        set = function(v)
            G().showMinimapIcon = v
            if _G.MSUF_SetMinimapIconEnabled then
                _G.MSUF_SetMinimapIconEnabled(v)
            else
                G().minimapIconDB = G().minimapIconDB or {}
                G().minimapIconDB.hide = not v
            end
        end,
    })

    UI.Check({
        name = "MSUF_TargetSoundsCheck", parent = s3Body,
        anchor = _G.MSUF_MinimapIconCheck, x = 0, y = -8,
        label = TR("Play sound on Target/Target Lost"),
        get = function() return G().playTargetSelectLostSounds == true end,
        set = function(v)
            G().playTargetSelectLostSounds = v
            if _G.MSUF_TargetSoundDriver_ResetState then _G.MSUF_TargetSoundDriver_ResetState() end
            if v and _G.MSUF_TargetSoundDriver_Ensure then _G.MSUF_TargetSoundDriver_Ensure() end
        end,
    })

    -- =====================================================================
    -- Section 4: Range Fade
    -- =====================================================================
    local s5Box, s5Body = MakeCollapsibleSection(scrollChild, 285, "Range Fade", false)
    s5Box:SetPoint("TOPLEFT", s3Box, "BOTTOMLEFT", 0, -6)

    local function ClampRangeFadeAlphaPercent(v)
        v = tonumber(v) or 60
        if v < 0 then v = 0 elseif v > 60 then v = 60 end
        return math.floor(v + 0.5)
    end

    local function PercentToRangeFadeAlpha(v)
        return ClampRangeFadeAlphaPercent(v) / 100
    end

    local function AlphaToRangeFadePercent(a)
        a = tonumber(a) or 0.6
        if a < 0 then a = 0 elseif a > 0.6 then a = 0.6 end
        return ClampRangeFadeAlphaPercent(a * 100)
    end

    local function RefreshRangeFadeRuntime()
        if _G.MSUF_RangeFade_Reset then _G.MSUF_RangeFade_Reset() end
        if _G.MSUF_RangeFade_EvaluateActive then
            _G.MSUF_RangeFade_EvaluateActive(true)
        elseif _G.MSUF_RangeFade_ApplyCurrent then
            _G.MSUF_RangeFade_ApplyCurrent(true)
        end

        if _G.MSUF_RangeFadeFB_Reset then _G.MSUF_RangeFadeFB_Reset() end
        if _G.MSUF_RangeFadeFB_EvaluateActive then
            _G.MSUF_RangeFadeFB_EvaluateActive(true)
        elseif _G.MSUF_RangeFadeFB_ApplyCurrent then
            _G.MSUF_RangeFadeFB_ApplyCurrent(true)
        end
    end

    local rfTarget = UI.Check({
        name = "MSUF_TargetRangeFadeCheck", parent = s5Body,
        anchor = s5Body, anchorPoint = "TOPLEFT", x = 12, y = -6,
        label = TR("Enable Target Range Fade"),
        get = function() return T().rangeFadeEnabled == true end,
        set = function(v)
            T().rangeFadeEnabled = v
            if _G.MSUF_RangeFade_Reset then _G.MSUF_RangeFade_Reset() end
            if _G.MSUF_RangeFade_EvaluateActive then _G.MSUF_RangeFade_EvaluateActive(true)
            elseif _G.MSUF_RangeFade_RebuildSpells then _G.MSUF_RangeFade_RebuildSpells() end
        end,
    })

    local rfFocus = UI.Check({
        name = "MSUF_FocusRangeFadeCheck", parent = s5Body,
        anchor = rfTarget, x = 0, y = -8,
        label = TR("Enable Focus Range Fade"),
        get = function() return F().rangeFadeEnabled == true end,
        set = function(v)
            F().rangeFadeEnabled = v
            if _G.MSUF_RangeFadeFB_Reset then _G.MSUF_RangeFadeFB_Reset() end
            if _G.MSUF_RangeFadeFB_EvaluateActive then _G.MSUF_RangeFadeFB_EvaluateActive(true)
            else
                if _G.MSUF_RangeFadeFB_RebuildSpells then _G.MSUF_RangeFadeFB_RebuildSpells() end
                if _G.MSUF_RangeFadeFB_ApplyCurrent then _G.MSUF_RangeFadeFB_ApplyCurrent(true) end
            end
        end,
    })

    local rfBoss = UI.Check({
        name = "MSUF_BossRangeFadeCheck", parent = s5Body,
        anchor = rfFocus, x = 0, y = -8,
        label = TR("Enable Boss Range Fade"),
        get = function() return B().rangeFadeEnabled == true end,
        set = function(v)
            B().rangeFadeEnabled = v
            if _G.MSUF_RangeFadeFB_Reset then _G.MSUF_RangeFadeFB_Reset() end
            if _G.MSUF_RangeFadeFB_EvaluateActive then _G.MSUF_RangeFadeFB_EvaluateActive(true)
            else
                if _G.MSUF_RangeFadeFB_RebuildSpells then _G.MSUF_RangeFadeFB_RebuildSpells() end
                if _G.MSUF_RangeFadeFB_ApplyCurrent then _G.MSUF_RangeFadeFB_ApplyCurrent(true) end
            end
        end,
    })

    local rfBossCB = UI.Check({
        name = "MSUF_BossRFCastbarCheck", parent = s5Body,
        anchor = rfBoss, x = 38, y = -6,
        label = TR("Also Fade Castbar"),
        get = function() return B().rangeFadeCastbar == true end,
        set = function(v)
            B().rangeFadeCastbar = v
            if _G.MSUF_RangeFadeFB_ApplyCurrent then _G.MSUF_RangeFadeFB_ApplyCurrent(true) end
        end,
    })

    local rfBossAuras = UI.Check({
        name = "MSUF_BossRFAurasCheck", parent = s5Body,
        anchor = rfBossCB, x = 0, y = -6,
        label = TR("Also Fade Auras"),
        get = function() return B().rangeFadeAuras == true end,
        set = function(v)
            B().rangeFadeAuras = v
            if _G.MSUF_RangeFadeFB_ApplyCurrent then _G.MSUF_RangeFadeFB_ApplyCurrent(true) end
        end,
    })

    local rfAlphaSlider = UI.Slider({
        name = "MSUF_MiscRangeFadeStrengthSlider", parent = s5Body, compact = true,
        compactInput = true, compactInputWidth = 48,
        anchor = s5Body, anchorPoint = "TOPLEFT", x = 365, y = -72,
        min = 0, max = 60, step = 5, width = 280, default = 60,
        lowText = "0%", highText = "60%",
        label = TR("Out of range alpha"),
        get = function()
            local a = T().rangeFadeAlpha
            if a == nil then a = F().rangeFadeAlpha end
            if a == nil then a = B().rangeFadeAlpha end
            return AlphaToRangeFadePercent(a)
        end,
        set = function(v)
            local a = PercentToRangeFadeAlpha(v)
            T().rangeFadeAlpha = a
            F().rangeFadeAlpha = a
            B().rangeFadeAlpha = a
            RefreshRangeFadeRuntime()
        end,
        formatText = function(v)
            return string.format("Out of range alpha: %d%%", ClampRangeFadeAlphaPercent(v))
        end,
    })

    UI.Check({
        name = "MSUF_RangeFadePortraitCheck", parent = s5Body,
        anchor = rfAlphaSlider, x = 0, y = -18,
        label = TR("Also Fade Portrait"),
        get = function() return G().rangeFadePortrait == true end,
        set = function(v)
            G().rangeFadePortrait = v and true or false
            RefreshRangeFadeRuntime()
            if _G.MSUF_RefreshAllUnitAlphas then _G.MSUF_RefreshAllUnitAlphas() end
        end,
    })

    RefreshMiscScrollLayout = function()
        local contentH = 115
            + (s1Box.GetHeight and s1Box:GetHeight() or 0)
            + 6
            + (s2Box.GetHeight and s2Box:GetHeight() or 0)
            + 6
            + (s3Box.GetHeight and s3Box:GetHeight() or 0)
            + 6
            + (s5Box.GetHeight and s5Box:GetHeight() or 0)
            + 24
        if contentH < 1 then
            contentH = 1
        end
        scrollChild:SetHeight(contentH)
        if scrollFrame.UpdateScrollChildRect then
            scrollFrame:UpdateScrollChildRect()
        end
    end

    RefreshMiscScrollLayout()
end
