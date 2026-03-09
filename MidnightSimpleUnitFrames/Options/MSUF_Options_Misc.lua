-- ---------------------------------------------------------------------------
-- MSUF_Options_Misc.lua  (Phase 8: Rewrite using ns.UI.*)
--
-- Miscellaneous options: update intervals, Blizzard frame toggles,
-- unit info panel, status indicators, range fade.
--
-- Uses ns.UI.* factories from Toolkit. Zero feature regression.
-- All widget names, DB paths, and anchor chains preserved.
-- ---------------------------------------------------------------------------
local addonName, ns = ...
local TR = ns.TR
local UI = ns.UI

function ns.MSUF_Options_Misc_Build(panel, miscGroup)
    if not panel or not miscGroup then return end
    if miscGroup._msufBuilt then return end
    miscGroup._msufBuilt = true

    -- Search registration
    if _G.MSUF_Search_RegisterRoots then
        _G.MSUF_Search_RegisterRoots({ "misc" }, miscGroup, "Miscellaneous")
    end

    -- DB helpers
    local function G() ns.EnsureDB(); return MSUF_DB.general end
    local function T() ns.EnsureDB(); MSUF_DB.target = MSUF_DB.target or {}; return MSUF_DB.target end
    local function F() ns.EnsureDB(); MSUF_DB.focus = MSUF_DB.focus or {}; return MSUF_DB.focus end
    local function B() ns.EnsureDB(); MSUF_DB.boss = MSUF_DB.boss or {}; return MSUF_DB.boss end
    local function GP() ns.EnsureDB(); MSUF_DB.gameplay = MSUF_DB.gameplay or {}; return MSUF_DB.gameplay end

    -------------------------------------------------------------------------
    -- Layout
    -------------------------------------------------------------------------
    local LEFT_W, RIGHT_W = 330, 330

    local leftPanel = UI.Panel({ parent = miscGroup, title = "Updates", anchor = miscGroup, anchorPoint = "TOPLEFT", x = 0, y = -110, width = LEFT_W, height = 396 })
    local rightPanel = UI.Panel({ parent = miscGroup, title = "Unit info panel", anchor = leftPanel, anchorPoint = "TOPLEFT", x = LEFT_W, y = 0, width = RIGHT_W, height = 396 })
    local bottomPanel = UI.Panel({ parent = miscGroup, title = "Indicators", anchor = leftPanel, anchorPoint = "TOPLEFT", x = 0, y = -(396 + 16), width = LEFT_W + RIGHT_W, height = 180 })

    local centerDivider = miscGroup:CreateTexture(nil, "ARTWORK")
    centerDivider:SetColorTexture(1, 1, 1, 0.10)
    centerDivider:SetWidth(1)
    centerDivider:SetPoint("TOP", leftPanel, "TOPRIGHT", 0, -46)
    centerDivider:SetPoint("BOTTOM", bottomPanel, "BOTTOMLEFT", LEFT_W, 12)

    -------------------------------------------------------------------------
    -- Updates (left panel) — preset buttons
    -------------------------------------------------------------------------
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

    local function RefreshPresetButtons()
        local preset = G().miscUpdatesPreset or "balanced"
        SetPresetButtonActive(leftPanel._presetPerf, preset == "perf")
        SetPresetButtonActive(leftPanel._presetBal,  preset == "balanced")
        SetPresetButtonActive(leftPanel._presetAcc,  preset == "accurate")
    end

    do
        local row = CreateFrame("Frame", nil, leftPanel)
        leftPanel._presetRow = row
        row:SetSize(270, 22)
        row:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 14, -48)

        local function MakePresetBtn(label, onClick)
            local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            b:SetSize(86, 20); b:SetText(label or "")
            if _G.MSUF_SkinMidnightActionButton then
                _G.MSUF_SkinMidnightActionButton(b, { textR = 1, textG = 0.85, textB = 0.1 })
            end
            b:SetScript("OnClick", onClick)
            return b
        end

        local gap = 6
        leftPanel._presetPerf = MakePresetBtn("Perf...", function()
            G().miscUpdatesPreset = "perf"
            sliders.updateInterval:SetValue(0.12); sliders.castbarUpdate:SetValue(0.06)
            sliders.ufcoreBudget:SetValue(1.0); sliders.ufcoreUrgent:SetValue(6)
            RefreshPresetButtons()
        end)
        leftPanel._presetPerf:SetPoint("LEFT", row, "LEFT", 0, 0)

        leftPanel._presetBal = MakePresetBtn("Balanced...", function()
            G().miscUpdatesPreset = "balanced"
            sliders.updateInterval:SetValue(0.05); sliders.castbarUpdate:SetValue(0.02)
            sliders.ufcoreBudget:SetValue(2.0); sliders.ufcoreUrgent:SetValue(10)
            RefreshPresetButtons()
        end)
        leftPanel._presetBal:SetPoint("LEFT", leftPanel._presetPerf, "RIGHT", gap, 0)

        leftPanel._presetAcc = MakePresetBtn("Accurate...", function()
            G().miscUpdatesPreset = "accurate"
            sliders.updateInterval:SetValue(0.01); sliders.castbarUpdate:SetValue(0.01)
            sliders.ufcoreBudget:SetValue(5.0); sliders.ufcoreUrgent:SetValue(50)
            RefreshPresetButtons()
        end)
        leftPanel._presetAcc:SetPoint("LEFT", leftPanel._presetBal, "RIGHT", gap, 0)

        row:SetScript("OnShow", RefreshPresetButtons)
        RefreshPresetButtons()
    end

    -------------------------------------------------------------------------
    -- Update sliders (left panel)
    -------------------------------------------------------------------------
    sliders.updateInterval = UI.Slider({
        name = "MSUF_UpdateIntervalSlider", parent = leftPanel, compact = true,
        anchor = leftPanel._presetRow, x = 0, y = -18,
        min = 0.01, max = 0.30, step = 0.01, width = 270, default = 0.05,
        lowText = "0.01", highText = "0.30",
        get = function() return G().frameUpdateInterval or _G.MSUF_FrameUpdateInterval or 0.05 end,
        set = function(v) G().frameUpdateInterval = v; _G.MSUF_FrameUpdateInterval = v end,
        formatText = function(v) return string.format("Unit update interval: %.2f s", v) end,
    })

    sliders.castbarUpdate = UI.Slider({
        name = "MSUF_CastbarUpdateIntervalSlider", parent = leftPanel, compact = true,
        anchor = sliders.updateInterval, x = 0, y = -32,
        min = 0.01, max = 0.30, step = 0.01, width = 270, default = 0.02,
        lowText = "0.01", highText = "0.30",
        get = function() return G().castbarUpdateInterval or _G.MSUF_CastbarUpdateInterval or 0.02 end,
        set = function(v) G().castbarUpdateInterval = v; _G.MSUF_CastbarUpdateInterval = v end,
        formatText = function(v) return string.format("Castbar update interval: %.2f s", v) end,
    })

    sliders.ufcoreBudget = UI.Slider({
        name = "MSUF_UFCoreFlushBudgetSlider", parent = leftPanel, compact = true,
        anchor = sliders.castbarUpdate, x = 0, y = -32,
        min = 0.5, max = 5.0, step = 0.1, width = 270, default = 2.0,
        lowText = "0.5", highText = "5.0",
        get = function() return G().ufcoreFlushBudgetMs end,
        set = function(v) G().ufcoreFlushBudgetMs = v end,
        formatText = function(v) return string.format("UFCore flush budget: %.1f ms", v) end,
    })

    sliders.ufcoreUrgent = UI.Slider({
        name = "MSUF_UFCoreUrgentCapSlider", parent = leftPanel, compact = true,
        anchor = sliders.ufcoreBudget, x = 0, y = -32,
        min = 1, max = 50, step = 1, width = 270, default = 10,
        lowText = "1", highText = "50",
        get = function() return G().ufcoreUrgentMaxPerFlush end,
        set = function(v) G().ufcoreUrgentMaxPerFlush = math.floor((tonumber(v) or 10) + 0.5) end,
        formatText = function(v) return string.format("UFCore urgent cap: %d", math.floor((tonumber(v) or 10) + 0.5)) end,
    })

    -------------------------------------------------------------------------
    -- Welcome & version check toggles (left panel, below sliders)
    -------------------------------------------------------------------------
    local welcomeCheck = UI.Check({
        name = "MSUF_ShowWelcomeMessageCheck", parent = leftPanel,
        anchor = sliders.ufcoreUrgent, x = 0, y = -20,
        label = TR("Show welcome message on login"),
        get = function() return G().showWelcomeMessage ~= false end,
        set = function(v) G().showWelcomeMessage = v end,
    })

    local versionCheck = UI.Check({
        name = "MSUF_VersionCheckEnabledCheck", parent = leftPanel,
        anchor = welcomeCheck, x = 0, y = -6,
        label = TR("Enable version check (peer-to-peer)"),
        get = function() return G().versionCheckEnabled ~= false end,
        set = function(v) G().versionCheckEnabled = v end,
    })

    -------------------------------------------------------------------------
    -- Unit info panel (right panel)
    -------------------------------------------------------------------------
    local infoTooltipDisable = UI.Check({
        name = "MSUF_InfoTooltipDisableCheck", parent = rightPanel,
        anchor = rightPanel._msufLine, x = 0, y = -10,
        label = TR("Disable MSUF unit info panel tooltips"),
        get = function() return G().disableUnitInfoTooltips and true or false end,
        set = function(v) G().disableUnitInfoTooltips = v end,
    })

    local posLabel = UI.Label({ parent = rightPanel, text = TR("MSUF unit info panel position"), anchor = infoTooltipDisable, y = -28 })

    UI.Dropdown({
        name = "MSUF_InfoTooltipPosDropdown", parent = rightPanel,
        anchor = posLabel, x = -16, y = -4, width = 200,
        items = {
            { key = "classic", label = "Blizzard Classic" },
            { key = "modern", label = "Modern (under cursor)" },
        },
        get = function() return G().unitInfoTooltipStyle or "classic" end,
        set = function(v) G().unitInfoTooltipStyle = v end,
    })

    -- Blizzard frames section
    local blizzHeader = UI.Label({ parent = rightPanel, text = TR("Blizzard frames"), anchor = posLabel, y = -64 })
    local blizzLine = rightPanel:CreateTexture(nil, "OVERLAY")
    blizzLine:SetColorTexture(1, 1, 1, 0.10)
    blizzLine:SetHeight(1)
    blizzLine:SetPoint("TOPLEFT", blizzHeader, "BOTTOMLEFT", 0, -6)
    blizzLine:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -14, -120)

    local blizzUFDisable = UI.Check({
        name = "MSUF_DisableBlizzUFCheck", parent = rightPanel,
        anchor = blizzLine, x = 0, y = -10,
        label = TR("Disable Blizzard unitframes"),
        get = function() return G().disableBlizzardUnitFrames ~= false end,
        set = function(v)
            G().disableBlizzardUnitFrames = v
            print("|cffffd700MSUF:|r Changing Blizzard unitframes visibility requires a /reload.")
        end,
    })

    -- Hard-kill PlayerFrame popup
    if not StaticPopupDialogs["MSUF_RELOAD_PLAYERFRAME_HIDE_MODE"] then
        StaticPopupDialogs["MSUF_RELOAD_PLAYERFRAME_HIDE_MODE"] = {
            text = "This changes how MSUF hides the Blizzard PlayerFrame.\n\nOFF: Compatibility mode (keeps PlayerFrame alive as hidden parent for resource bar addons).\nON: Hard-hide mode (fully hides PlayerFrame; may break some resource bar addons).\n\nA UI reload is required.",
            button1 = RELOADUI, button2 = CANCEL,
            OnAccept = function() ReloadUI() end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end

    UI.Check({
        name = "MSUF_HardKillPlayerFrameCheck", parent = rightPanel,
        anchor = blizzUFDisable, x = 0, y = -10,
        label = TR("Fully Hide Blizzard PlayerFrame - Turn off for resource bar compatibility"),
        tooltip = TR("OFF: Keeps PlayerFrame alive as a hidden parent.\nON: Fully hides PlayerFrame (may break some resource bar addons).\nRequires a UI reload."),
        get = function() return G().hardKillBlizzardPlayerFrame == true end,
        set = function(v)
            G().hardKillBlizzardPlayerFrame = v
            if StaticPopup_Show then StaticPopup_Show("MSUF_RELOAD_PLAYERFRAME_HIDE_MODE") end
        end,
    })

    local minimapIconCheck = UI.Check({
        name = "MSUF_MinimapIconCheck", parent = rightPanel,
        anchor = _G.MSUF_HardKillPlayerFrameCheck, x = 0, y = -12,
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

    local targetSoundsCheck = UI.Check({
        name = "MSUF_TargetSoundsCheck", parent = rightPanel,
        anchor = minimapIconCheck, x = 0, y = -12,
        label = TR("Play sound on Target/Target Lost"),
        get = function() return G().playTargetSelectLostSounds == true end,
        set = function(v)
            G().playTargetSelectLostSounds = v
            if _G.MSUF_TargetSoundDriver_ResetState then _G.MSUF_TargetSoundDriver_ResetState() end
            if v and _G.MSUF_TargetSoundDriver_Ensure then _G.MSUF_TargetSoundDriver_Ensure() end
        end,
    })

    -------------------------------------------------------------------------
    -- Indicators (bottom panel) — Status + Range Fade
    -------------------------------------------------------------------------
    local function GetStatusDB()
        local g = G(); g.statusIndicators = g.statusIndicators or {}; return g.statusIndicators
    end

    local function EnsureStatusAFKDNDPopupWarning()
        if not _G.StaticPopupDialogs then return end
        if _G.StaticPopupDialogs["MSUF_STATUS_AFKDND_WARNING"] then return end
        _G.StaticPopupDialogs["MSUF_STATUS_AFKDND_WARNING"] = {
            text = "WARNING:\n\nAFK/DND status indicators do NOT update while you are inside an instance AND in combat.\nThis is a client/API limitation.\n\nOutside of instance combat they should work normally.\n\nEnable anyway?",
            button1 = "Enable", button2 = "Cancel",
            timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
            OnAccept = function(popup, data)
                local d = data or (popup and popup.data)
                if not d then return end
                local db = d.getDB(); db[d.key] = true; d.cb:SetChecked(true)
                if _G.MSUF_RefreshStatusIndicators then _G.MSUF_RefreshStatusIndicators() end
            end,
            OnCancel = function(popup, data)
                local d = data or (popup and popup.data)
                if not d then return end
                local db = d.getDB(); db[d.key] = false; d.cb:SetChecked(false)
                if _G.MSUF_RefreshStatusIndicators then _G.MSUF_RefreshStatusIndicators() end
            end,
        }
    end

    -- Status indicators (left column of bottom panel)
    local statusHeader = UI.Label({ parent = bottomPanel, text = TR("Status indicators") })
    statusHeader:SetPoint("TOPLEFT", bottomPanel, "TOPLEFT", 14, -34)
    local statusLine = bottomPanel:CreateTexture(nil, "ARTWORK")
    statusLine:SetColorTexture(1, 1, 1, 0.10); statusLine:SetHeight(1)
    statusLine:SetPoint("TOPLEFT", statusHeader, "BOTTOMLEFT", 0, -8)
    statusLine:SetPoint("TOPRIGHT", bottomPanel, "TOPRIGHT", -14, -42)

    -- Range Fade (right column of bottom panel)
    local rangeFadeHeader = UI.Label({ parent = bottomPanel, text = TR("Range fade") })
    rangeFadeHeader:SetPoint("TOPLEFT", bottomPanel, "TOPLEFT", LEFT_W + 14, -34)
    local rangeFadeLine = bottomPanel:CreateTexture(nil, "ARTWORK")
    rangeFadeLine:SetColorTexture(1, 1, 1, 0.10); rangeFadeLine:SetHeight(1)
    rangeFadeLine:SetPoint("TOPLEFT", rangeFadeHeader, "BOTTOMLEFT", 0, -8)
    rangeFadeLine:SetPoint("TOPRIGHT", bottomPanel, "TOPRIGHT", -14, -42)

    -- Range Fade checkboxes
    local rfTarget = UI.Check({
        name = "MSUF_TargetRangeFadeCheck", parent = bottomPanel,
        anchor = rangeFadeHeader, x = 0, y = -14,
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
        name = "MSUF_FocusRangeFadeCheck", parent = bottomPanel,
        anchor = rfTarget, x = 0, y = -12,
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

    UI.Check({
        name = "MSUF_BossRangeFadeCheck", parent = bottomPanel,
        anchor = rfFocus, x = 0, y = -12,
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

    -- Status indicator checkboxes (AFK/DND with confirm popup, Dead/Ghost direct)
    local step = 30
    local statusSpecs = {
        { key = "showAFK",   label = "Show AFK",   confirm = true },
        { key = "showDND",   label = "Show DND",   confirm = true },
        { key = "showDead",  label = "Show Dead" },
        { key = "showGhost", label = "Show Ghost" },
    }

    bottomPanel._msufStatusCBs = {}
    for i, s in ipairs(statusSpecs) do
        local cb = CreateFrame("CheckButton", nil, bottomPanel, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", statusHeader, "BOTTOMLEFT", 0, -10 - ((i - 1) * step))
        local fs = cb.Text or cb.text
        if fs and fs.SetText then fs:SetText(TR(s.label)) end
        UI.StyleToggleText(cb)
        UI.StyleCheckmark(cb)

        cb:SetScript("OnShow", function(self)
            local db = GetStatusDB()
            self:SetChecked(db[s.key] and true or false)
        end)

        cb:SetScript("OnClick", function(self)
            local want = self:GetChecked() and true or false
            if want and s.confirm and _G.StaticPopup_Show then
                EnsureStatusAFKDNDPopupWarning()
                self:SetChecked(false)
                GetStatusDB()[s.key] = false
                local popup = _G.StaticPopup_Show("MSUF_STATUS_AFKDND_WARNING", nil, nil, { key = s.key, cb = self, getDB = GetStatusDB })
                if popup then return end
                want = true; self:SetChecked(true)
            end
            GetStatusDB()[s.key] = want
            if _G.MSUF_RefreshStatusIndicators then _G.MSUF_RefreshStatusIndicators() end
        end)

        bottomPanel._msufStatusCBs[i] = cb
    end
end
