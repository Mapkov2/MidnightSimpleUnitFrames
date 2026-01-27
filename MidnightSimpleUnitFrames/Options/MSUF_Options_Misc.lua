local addonName, ns = ...
ns = ns or {}

-- Misc Options (split from MSUF_Options_Core.lua)
-- IMPORTANT: list this file in the .toc BEFORE MSUF_Options_Core.lua so the builder is available at panel build time.

function ns.MSUF_Options_Misc_Build(panel, miscGroup)
    if not panel or not miscGroup then return end
    -- Localize the dropdown click-expander (it is a local helper in Options_Core; exported there onto ns).
    local MSUF_ExpandDropdownClickArea = (ns and ns.MSUF_ExpandDropdownClickArea) or _G.MSUF_ExpandDropdownClickArea
    -- Keep misc locals from leaking into the global environment.
    local miscTitle, miscLeftHeader, miscLeftLine, miscRightHeader, miscRightLine

    local updateThrottleLabel, updateThrottleSlider
    local MSUF_CastbarUpdateLabel, MSUF_CastbarUpdateIntervalSlider
    local infoTooltipDisableCheck, infoTooltipPosLabel, infoTooltipPosDrop
    local blizzUFCheck, minimapIconCheck
    local targetSoundsCheck

    miscTitle = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    miscTitle:SetPoint("TOPLEFT", miscGroup, "TOPLEFT", 16, -120)
    miscLeftHeader = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    miscLeftHeader:SetPoint("TOPLEFT", miscGroup, "TOPLEFT", 16, -160)
    miscLeftHeader:SetText("Mouseover & updates")

    miscLeftLine = miscGroup:CreateTexture(nil, "ARTWORK")
    miscLeftLine:SetColorTexture(1, 1, 1, 0.2)
    miscLeftLine:SetSize(320, 1)
    miscLeftLine:SetPoint("TOPLEFT", miscLeftHeader, "BOTTOMLEFT", -16, -4)

    miscRightHeader = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    miscRightHeader:SetPoint("TOPLEFT", miscGroup, "TOPLEFT", 420, -160)
    miscRightHeader:SetText("Unit info panel")

    miscRightLine = miscGroup:CreateTexture(nil, "ARTWORK")
    miscRightLine:SetColorTexture(1, 1, 1, 0.2)
    miscRightLine:SetSize(260, 1)
    miscRightLine:SetPoint("TOPLEFT", miscRightHeader, "BOTTOMLEFT", -16, -4)

    updateThrottleLabel = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    updateThrottleLabel:SetPoint("TOPLEFT", miscLeftLine, "BOTTOMLEFT", 16, -18)
    updateThrottleLabel:SetText("Unit update interval (seconds)")

    updateThrottleSlider = CreateFrame("Slider", "MSUF_UpdateIntervalSlider", miscGroup, "OptionsSliderTemplate")
    updateThrottleSlider:SetPoint("TOPLEFT", updateThrottleLabel, "BOTTOMLEFT", 0, -8)
    updateThrottleSlider:SetMinMaxValues(0.01, 0.30)
    updateThrottleSlider:SetValueStep(0.01)
    updateThrottleSlider:SetObeyStepOnDrag(true)
    updateThrottleSlider:SetWidth(200)

    _G[updateThrottleSlider:GetName() .. "Low"]:SetText("0.01")
    _G[updateThrottleSlider:GetName() .. "High"]:SetText("0.30")

    updateThrottleSlider:SetScript("OnShow", function(self)
        EnsureDB()
        local v = MSUF_DB.general and MSUF_DB.general.frameUpdateInterval or MSUF_FrameUpdateInterval or 0.05
        if type(v) ~= "number" then v = 0.05 end
        if v < 0.01 then v = 0.01 elseif v > 0.30 then v = 0.30 end
        self:SetValue(v)
    end)

    updateThrottleSlider:SetScript("OnValueChanged", function(self, value)
        EnsureDB()
        local v = tonumber(value) or 0.05
        if v < 0.01 then v = 0.01 elseif v > 0.30 then v = 0.30 end
        MSUF_DB.general.frameUpdateInterval = v
        MSUF_FrameUpdateInterval = v
    end)

    MSUF_CastbarUpdateLabel = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    MSUF_CastbarUpdateLabel:SetPoint("TOPLEFT", updateThrottleLabel, "BOTTOMLEFT", 0, -40)
    MSUF_CastbarUpdateLabel:SetText("Castbar update")

    MSUF_CastbarUpdateIntervalSlider = CreateFrame("Slider", "MSUF_CastbarUpdateIntervalSlider", miscGroup, "OptionsSliderTemplate")
    MSUF_CastbarUpdateIntervalSlider:SetPoint("TOPLEFT", MSUF_CastbarUpdateLabel, "BOTTOMLEFT", 0, -8)
    MSUF_CastbarUpdateIntervalSlider:SetMinMaxValues(0.01, 0.30)
    MSUF_CastbarUpdateIntervalSlider:SetValueStep(0.01)
    MSUF_CastbarUpdateIntervalSlider:SetObeyStepOnDrag(true)
    MSUF_CastbarUpdateIntervalSlider:SetWidth(200)
    _G[MSUF_CastbarUpdateIntervalSlider:GetName() .. "Low"]:SetText("0.01")
    _G[MSUF_CastbarUpdateIntervalSlider:GetName() .. "High"]:SetText("0.30")

    MSUF_CastbarUpdateIntervalSlider:SetScript("OnShow", function(self)
        EnsureDB()
        local v = MSUF_DB.general and MSUF_DB.general.castbarUpdateInterval or MSUF_CastbarUpdateInterval or 0.02
        self:SetValue(v)
        _G[self:GetName() .. "Text"]:SetText(string.format("%.2f", v))
    end)

    MSUF_CastbarUpdateIntervalSlider:SetScript("OnValueChanged", function(self, value)
        EnsureDB()
        local v = tonumber(value) or 0.02
        if v < 0.01 then v = 0.01 elseif v > 0.30 then v = 0.30 end
        MSUF_DB.general.castbarUpdateInterval = v
        MSUF_CastbarUpdateInterval = v
        _G[self:GetName() .. "Text"]:SetText(string.format("%.2f", v))
    end)

    -- Indicators
    local indicatorsLabel = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    indicatorsLabel:SetPoint("TOPLEFT", MSUF_CastbarUpdateIntervalSlider, "BOTTOMLEFT", 0, -22)
    indicatorsLabel:SetText("Indicators")
    -- Hidden: boxed misc layout defines its own "Indicators" header.
    indicatorsLabel:Hide()

    local indicatorsLine = miscGroup:CreateTexture(nil, "ARTWORK")
    indicatorsLine:SetColorTexture(1, 0.82, 0, 1)
    indicatorsLine:SetHeight(1)
    indicatorsLine:SetPoint("TOPLEFT", indicatorsLabel, "BOTTOMLEFT", -16, -4)
    indicatorsLine:SetPoint("RIGHT", miscGroup, "RIGHT", -16, 0)
    -- Hidden: boxed misc layout already separates sections via boxed panels.
    indicatorsLine:Hide()
    -- Incoming resurrection indicator toggle removed (moved to per-unit Status icons UI)

infoTooltipDisableCheck = CreateFrame("CheckButton", "MSUF_InfoTooltipDisableCheck", miscGroup, "UICheckButtonTemplate")
infoTooltipDisableCheck:SetPoint("TOPLEFT", miscRightLine, "BOTTOMLEFT", 16, -16)

infoTooltipDisableCheck.text = infoTooltipDisableCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
infoTooltipDisableCheck.text:SetPoint("LEFT", infoTooltipDisableCheck, "RIGHT", 2, 0)
infoTooltipDisableCheck.text:SetText("Disable MSUF unit info panel tooltips")

    infoTooltipDisableCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.disableUnitInfoTooltips = self:GetChecked() and true or false
    end)

    infoTooltipDisableCheck:SetScript("OnShow", function(self)
        EnsureDB()
        g = MSUF_DB.general or {}
        self:SetChecked(g.disableUnitInfoTooltips and true or false)
    end)

    infoTooltipPosLabel = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    infoTooltipPosLabel:SetPoint("TOPLEFT", infoTooltipDisableCheck, "BOTTOMLEFT", 0, -16)
    infoTooltipPosLabel:SetText("MSUF unit info panel position")

    infoTooltipPosDrop = CreateFrame("Frame", "MSUF_InfoTooltipPosDropdown", miscGroup, "UIDropDownMenuTemplate")
    MSUF_ExpandDropdownClickArea(infoTooltipPosDrop)
    infoTooltipPosDrop:SetPoint("TOPLEFT", infoTooltipPosLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(infoTooltipPosDrop, 180)

    local function InfoTooltipPosDropdown_OnClick(self)
        EnsureDB()
        UIDropDownMenu_SetSelectedValue(infoTooltipPosDrop, self.value)
        MSUF_DB.general.unitInfoTooltipStyle = self.value
    end

    local function InfoTooltipPosDropdown_Initialize(self, level)
        EnsureDB()
        g = MSUF_DB.general or {}
        current = g.unitInfoTooltipStyle or "classic"

        info = UIDropDownMenu_CreateInfo()
        info.func = InfoTooltipPosDropdown_OnClick

        info.text = "Blizzard Classic"
        info.value = "classic"
        info.checked = (current == "classic")
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.func = InfoTooltipPosDropdown_OnClick
        info.text = "Modern (under cursor)"
        info.value = "modern"
        info.checked = (current == "modern")
        UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_Initialize(infoTooltipPosDrop, InfoTooltipPosDropdown_Initialize)

    infoTooltipPosDrop:SetScript("OnShow", function(self)
        EnsureDB()
        g = MSUF_DB.general or {}
        current = g.unitInfoTooltipStyle or "classic"
        UIDropDownMenu_SetSelectedValue(self, current)
        if current == "modern" then
            UIDropDownMenu_SetText(self, "Modern (under cursor)")
        else
            UIDropDownMenu_SetText(self, "Blizzard Classic")
        end
    end)

    blizzUFCheck = CreateFrame("CheckButton", "MSUF_DisableBlizzUFCheck", miscGroup, "UICheckButtonTemplate")
    blizzUFCheck:SetPoint("TOPLEFT", infoTooltipPosDrop, "BOTTOMLEFT", 16, -24)

    blizzUFCheck.text = blizzUFCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    blizzUFCheck.text:SetPoint("LEFT", blizzUFCheck, "RIGHT",0, 0)
    blizzUFCheck.text:SetText("Disable Blizzard unitframes")

    blizzUFCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.disableBlizzardUnitFrames = self:GetChecked() and true or false
        print("|cffffd700MSUF:|r Changing Blizzard unitframes visibility requires a /reload.")
    end)

    -- Hard-hide Blizzard PlayerFrame (compatibility OFF; may break addons that parent resource bars to PlayerFrame)
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

    local hardKillPFCheck = CreateFrame("CheckButton", "MSUF_HardKillPlayerFrameCheck", miscGroup, "UICheckButtonTemplate")
    hardKillPFCheck:SetPoint("TOPLEFT", blizzUFCheck, "BOTTOMLEFT", 0, -10)

    hardKillPFCheck.text = hardKillPFCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hardKillPFCheck.text:SetPoint("LEFT", hardKillPFCheck, "RIGHT", 0, 0)
    hardKillPFCheck.text:SetText("Fully Hide Blizzard PlayerFrame - Turn off for resource bar compatibility")

    if MSUF_StyleToggleText then MSUF_StyleToggleText(hardKillPFCheck) end
    if MSUF_StyleCheckmark then MSUF_StyleCheckmark(hardKillPFCheck) end

    hardKillPFCheck:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Hide Blizzard PlayerFrame (Turn off for other addon compatibility)", 1, 0.9, 0.4)
        GameTooltip:AddLine("OFF: Keeps PlayerFrame alive as a hidden parent.", 0.95, 0.95, 0.95, true)
        GameTooltip:AddLine("ON: Fully hides PlayerFrame (may break some resource bar addons).", 1, 0.82, 0.2, true)
        GameTooltip:AddLine("Requires a UI reload.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    hardKillPFCheck:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    hardKillPFCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.hardKillBlizzardPlayerFrame = self:GetChecked() and true or false
        StaticPopup_Show("MSUF_RELOAD_PLAYERFRAME_HIDE_MODE")
    end)

    hardKillPFCheck:SetScript("OnShow", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}
        self:SetChecked(g.hardKillBlizzardPlayerFrame == true)

        local enabled = (g.disableBlizzardUnitFrames ~= false)
        if self.SetEnabled then self:SetEnabled(enabled) end
        self:SetAlpha(enabled and 1 or 0.4)
    end)

    blizzUFCheck:SetScript("OnShow", function(self)
        EnsureDB()
        g = MSUF_DB.general or {}
        self:SetChecked(g.disableBlizzardUnitFrames ~= false)
    end)

    -- Minimap icon toggle (backend in MidnightSimpleUnitFrames_MinimapButton.lua)
    minimapIconCheck = CreateFrame("CheckButton", "MSUF_MinimapIconCheck", miscGroup, "InterfaceOptionsCheckButtonTemplate")
    -- Extra vertical spacing to avoid overlapping the PlayerFrame hide-mode toggle.
    minimapIconCheck:SetPoint("TOPLEFT", hardKillPFCheck, "BOTTOMLEFT", 0, -12)
    if minimapIconCheck.Text then
        minimapIconCheck.Text:SetText("Show MSUF minimap icon")
    elseif minimapIconCheck.text and minimapIconCheck.text.SetText then
        minimapIconCheck.text:SetText("Show MSUF minimap icon")
    end

    minimapIconCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local enabled = self:GetChecked() and true or false
        MSUF_DB.general.showMinimapIcon = enabled

        if _G.MSUF_SetMinimapIconEnabled then
            _G.MSUF_SetMinimapIconEnabled(enabled)
        else
            -- Safe fallback if the minimap icon file (LDB/LibDBIcon) isn't loaded yet.
            MSUF_DB.general.minimapIconDB = MSUF_DB.general.minimapIconDB or {}
            MSUF_DB.general.minimapIconDB.hide = (not enabled) and true or false
        end
    end)

    minimapIconCheck:SetScript("OnShow", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}
        local enabled = (g.showMinimapIcon ~= false)
        self:SetChecked(enabled and true or false)
    end)


    -- Target select / target lost sounds (matches default Blizzard UI behavior)
    targetSoundsCheck = CreateFrame("CheckButton", "MSUF_TargetSoundsCheck", miscGroup, "InterfaceOptionsCheckButtonTemplate")
    targetSoundsCheck:SetPoint("TOPLEFT", minimapIconCheck, "BOTTOMLEFT", 0, -10)
    do
        local t = _G[targetSoundsCheck:GetName() .. "Text"]
        if t and t.SetText then
            t:SetText("Play sound on Target/Target Lost")
        end
    end

    if MSUF_StyleToggleText then MSUF_StyleToggleText(targetSoundsCheck) end
    if MSUF_StyleCheckmark then MSUF_StyleCheckmark(targetSoundsCheck) end

    targetSoundsCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.playTargetSelectLostSounds = self:GetChecked() and true or false

        -- Reset cached target state so enabling/disabling doesn't instantly fire a "lost" sound.
        if _G.MSUF_TargetSoundDriver_ResetState then
            _G.MSUF_TargetSoundDriver_ResetState()
        end
        if self:GetChecked() and _G.MSUF_TargetSoundDriver_Ensure then
            _G.MSUF_TargetSoundDriver_Ensure()
        end
    end)

    targetSoundsCheck:SetScript("OnShow", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}
        self:SetChecked(g.playTargetSelectLostSounds == true)
    end)




    -- Misc menu style: boxed layout (to match Bars/Fonts)
    do
        if miscGroup and not miscGroup._msufMiscBoxedLayoutV1 then
            miscGroup._msufMiscBoxedLayoutV1 = true

            -- Hide old headers/lines/labels that were anchored directly to miscGroup
            local hideText = {
                ["Mouseover & updates"] = true,
                ["Unit info panel"] = true,
                ["Indicators"] = true,
                ["Unit update interval (seconds)"] = true,
                ["Castbar update"] = true,
                ["Unit info panel position"] = true,
                ["MSUF unit info panel position"] = true,
                ["Disable MSUF unit info panel tooltips"] = true,
                ["Disable Blizzard unitframes"] = true,
                                            }

            for i = 1, miscGroup:GetNumRegions() do
                local r = select(i, miscGroup:GetRegions())
                if r and r.IsObjectType then
                    if r:IsObjectType("FontString") then
                        local t = r:GetText()
                        if t and hideText[t] then
                            r:Hide()
                        end
                    elseif r:IsObjectType("Texture") then
                        -- Likely old divider lines
                        local w, h = r:GetSize()
                        local a = r:GetAlpha()
                        if h and h <= 2 and w and w >= 200 then
                            r:Hide()
                        end
                    end
                end
            end

            -- Panel helpers (same as Bars boxed layout)
            local function SetupPanel(panel, titleText)
                -- Some frames may be created without BackdropTemplate; mix it in at runtime.
                if (not panel.SetBackdrop) and BackdropTemplateMixin and Mixin then
                    Mixin(panel, BackdropTemplateMixin)
                end
                if panel.SetBackdrop then
                    panel:SetBackdrop({
                        bgFile = "Interface\\Buttons\\WHITE8x8",
                        edgeFile = "Interface\\Buttons\\WHITE8x8",
                        edgeSize = 1,
                        insets = { left = 1, right = 1, top = 1, bottom = 1 },
                    })
                    panel:SetBackdropColor(0, 0, 0, 0.20)
                    panel:SetBackdropBorderColor(1, 1, 1, 0.12)
                end

                local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                header:SetText(titleText or "")
                header:SetTextColor(1, 0.82, 0)
                header:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -14)

                local line = panel:CreateTexture(nil, "ARTWORK")
                line:SetColorTexture(1, 1, 1, 0.08)
                line:SetHeight(1)
                line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
                line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -38)

                panel._msufHeader = header
                panel._msufHeaderLine = line
                return header, line
            end

            local function MakeLabel(parent, text, anchor, rel, x, y)
                local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                fs:SetText(text or "")
                fs:SetTextColor(1, 0.82, 0)
                if anchor and rel then
                    fs:SetPoint(anchor, rel, x or 0, y or 0)
                end
                return fs
            end

            -- Normalize all Misc toggles to the same checkbox size and label alignment.
            -- Reference size = "Disable Blizzard unitframes" (blizzUFDisable). This avoids
            -- mixed templates producing different checkbox box sizes (and prevents clipping).
            local function MSUF_GetMiscToggleTargetSize()
                local w, h
                local ref = _G.MSUF_DisableBlizzUFCheck
                if ref and ref.GetSize then
                    w, h = ref:GetSize()
                end
                if type(w) ~= "number" or w <= 0 then w = 24 end
                if type(h) ~= "number" or h <= 0 then h = 24 end
                return w, h
            end

            local function MSUF_GetMiscToggleTargetFont()
                local ref = _G.MSUF_DisableBlizzUFCheck
                local rfs = ref and (ref.text or ref.Text)
                if (not rfs) and ref and ref.GetName and ref:GetName() and _G then
                    rfs = _G[ref:GetName() .. "Text"]
                end
                if rfs and rfs.GetFont then
                    local font, size, flags = rfs:GetFont()
                    if font and size then
                        return font, size, flags
                    end
                end
                if rfs and rfs.GetFontObject then
                    return nil, nil, nil, rfs:GetFontObject()
                end
            end

            local function StyleCheckbox(cb)
                if not cb then return end

                -- Match checkbox size.
                local tw, th = MSUF_GetMiscToggleTargetSize()
                if cb.SetSize then
                    cb:SetSize(tw, th)
                elseif cb.SetHeight then
                    cb:SetHeight(th)
                end

                -- Expand click area slightly to the right.
                if cb.SetHitRectInsets then
                    cb:SetHitRectInsets(0, -10, 0, 0)
                end

                -- Normalize label placement (avoid template differences).
                local fs = cb.text or cb.Text
                if (not fs) and cb.GetName and cb:GetName() and _G then
                    fs = _G[cb:GetName() .. "Text"]
                end
                if fs and fs.ClearAllPoints and fs.SetPoint then
                    fs:ClearAllPoints()
                    fs:SetPoint("LEFT", cb, "RIGHT", 0, 0)
                end

                -- Match label font (some templates default to smaller font objects).
                local font, size, flags, fo = MSUF_GetMiscToggleTargetFont()
                if fs then
                    if font and size and fs.SetFont then
                        fs:SetFont(font, size, flags)
                    elseif fo and fs.SetFontObject then
                        fs:SetFontObject(fo)
                    end
                end
            end

            -- Create panels
            local leftPanel = CreateFrame("Frame", nil, miscGroup, "BackdropTemplate")
            leftPanel:SetPoint("TOPLEFT", miscGroup, "TOPLEFT", 0, -110)
            leftPanel:SetSize(330, 330)
            SetupPanel(leftPanel, "Updates")

            local rightPanel = CreateFrame("Frame", nil, miscGroup, "BackdropTemplate")
            rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 0, 0)
            rightPanel:SetSize(330, 330)
            SetupPanel(rightPanel, "Unit info panel")
            -- Panel width helpers (avoid nil math when adding divider lines)
            local leftW  = 330
            local rightW = 330

            -- Section divider between top blocks and Indicators (matches other menus)
  local sectionDivider = miscGroup:CreateTexture(nil, "ARTWORK")
  sectionDivider:SetColorTexture(1, 1, 1, 0.10)
  sectionDivider:SetHeight(1)
  sectionDivider:SetPoint("TOPLEFT", leftPanel, "BOTTOMLEFT", 0, -8)
  sectionDivider:SetPoint("TOPRIGHT", rightPanel, "BOTTOMRIGHT", 0, -8)
  -- Box borders already separate sections; remove this extra horizontal line.
  sectionDivider:Hide()

local bottomPanel = CreateFrame("Frame", nil, miscGroup, "BackdropTemplate")
            bottomPanel:SetPoint("TOPLEFT", leftPanel, "BOTTOMLEFT", 0, -16)
            bottomPanel:SetPoint("TOPRIGHT", rightPanel, "BOTTOMRIGHT", 0, -16)
            bottomPanel:SetHeight(180)
            SetupPanel(bottomPanel, "Indicators")

  -- Misc menu should be clean (no extra boxed borders; use only header lines + dividers)
  local function ClearPanelBackdrop(p)
    if p and p.SetBackdropColor then
      p:SetBackdropColor(0, 0, 0, 0)
      p:SetBackdropBorderColor(0, 0, 0, 0)
    end
  end
  ClearPanelBackdrop(leftPanel)
  ClearPanelBackdrop(rightPanel)
  ClearPanelBackdrop(bottomPanel)

            -- Vertical divider inside indicators panel

  -- Shared center divider (matches top + bottom columns)
  local centerDivider = miscGroup:CreateTexture(nil, "ARTWORK")
  centerDivider:SetColorTexture(1, 1, 1, 0.10)
  centerDivider:SetWidth(1)
  centerDivider:SetPoint("TOP", leftPanel, "TOPRIGHT", 0, -46)
  centerDivider:SetPoint("BOTTOM", bottomPanel, "BOTTOMLEFT", leftW, 12)

            -- Grab existing widgets
            local updateSlider = _G.MSUF_UpdateIntervalSlider
            local castbarUpdateSlider = _G.MSUF_CastbarUpdateIntervalSlider


            -- UFCore spike-cap tuning (advanced)
            local ufcoreBudgetSlider = _G.MSUF_UFCoreFlushBudgetSlider
            if not ufcoreBudgetSlider then
                ufcoreBudgetSlider = CreateFrame("Slider", "MSUF_UFCoreFlushBudgetSlider", miscGroup, "OptionsSliderTemplate")
                ufcoreBudgetSlider:SetMinMaxValues(0.5, 5.0)
                ufcoreBudgetSlider:SetValueStep(0.1)
                ufcoreBudgetSlider:SetObeyStepOnDrag(true)
                ufcoreBudgetSlider:SetWidth(200)
                _G[ufcoreBudgetSlider:GetName() .. "Low"]:SetText("0.5")
                _G[ufcoreBudgetSlider:GetName() .. "High"]:SetText("5.0")
                ufcoreBudgetSlider.tooltipText = "Limits UFCore work per frame (ms). Lower = smoother (less spikes), higher = more immediate updates."

                ufcoreBudgetSlider:SetScript("OnShow", function(self)
                    if EnsureDB then EnsureDB() end
                    local g = (MSUF_DB and MSUF_DB.general) or {}
                    local v = g.ufcoreFlushBudgetMs
                    if type(v) ~= "number" then v = 2.0 end
                    if v < 0.5 then v = 0.5 elseif v > 5.0 then v = 5.0 end
                    self:SetValue(v)
                    _G[self:GetName() .. "Text"]:SetText(string.format("%.1f ms", v))
                end)

                ufcoreBudgetSlider:SetScript("OnValueChanged", function(self, value)
                    if EnsureDB then EnsureDB() end
                    local v = tonumber(value) or 2.0
                    if v < 0.5 then v = 0.5 elseif v > 5.0 then v = 5.0 end
                    MSUF_DB.general.ufcoreFlushBudgetMs = v
                    _G[self:GetName() .. "Text"]:SetText(string.format("%.1f ms", v))
                end)
            end

            local ufcoreUrgentSlider = _G.MSUF_UFCoreUrgentCapSlider
            if not ufcoreUrgentSlider then
                ufcoreUrgentSlider = CreateFrame("Slider", "MSUF_UFCoreUrgentCapSlider", miscGroup, "OptionsSliderTemplate")
                ufcoreUrgentSlider:SetMinMaxValues(1, 50)
                ufcoreUrgentSlider:SetValueStep(1)
                ufcoreUrgentSlider:SetObeyStepOnDrag(true)
                ufcoreUrgentSlider:SetWidth(200)
                _G[ufcoreUrgentSlider:GetName() .. "Low"]:SetText("1")
                _G[ufcoreUrgentSlider:GetName() .. "High"]:SetText("50")
                ufcoreUrgentSlider.tooltipText = "Caps urgent unit updates per flush. Lower = smaller spikes, higher = faster catch-up."

                ufcoreUrgentSlider:SetScript("OnShow", function(self)
                    if EnsureDB then EnsureDB() end
                    local g = (MSUF_DB and MSUF_DB.general) or {}
                    local v = g.ufcoreUrgentMaxPerFlush
                    if type(v) ~= "number" then v = 10 end
                    v = math.floor(v + 0.5)
                    if v < 1 then v = 1 elseif v > 50 then v = 50 end
                    self:SetValue(v)
                    _G[self:GetName() .. "Text"]:SetText(tostring(v))
                end)

                ufcoreUrgentSlider:SetScript("OnValueChanged", function(self, value)
                    if EnsureDB then EnsureDB() end
                    local v = tonumber(value) or 10
                    v = math.floor(v + 0.5)
                    if v < 1 then v = 1 elseif v > 50 then v = 50 end
                    MSUF_DB.general.ufcoreUrgentMaxPerFlush = v
                    _G[self:GetName() .. "Text"]:SetText(tostring(v))
                end)
            end


            -- Presets: Maximum performance / Balanced / Max accuracy (drives the sliders)
            local function MSUF_Misc_SetPresetButtonActive(btn, active)
                if not btn then return end
                btn._msufActive = active and true or false

                local fs = (btn.GetFontString and btn:GetFontString()) or btn._msufText
                if btn._msufActive then
                    if btn.LockHighlight then btn:LockHighlight() end
                    if fs and fs.SetTextColor then fs:SetTextColor(1, 0.82, 0) end
                else
                    if btn.UnlockHighlight then btn:UnlockHighlight() end
                    if fs and fs.SetTextColor then fs:SetTextColor(1, 1, 1) end
                end
            end

            local function MSUF_Misc_RefreshUpdatePresetButtons()
                if EnsureDB then EnsureDB() end
                local g = (MSUF_DB and MSUF_DB.general) or {}
                local preset = g.miscUpdatesPreset or "balanced"
                if leftPanel and leftPanel._msufPresetPerf then
                    MSUF_Misc_SetPresetButtonActive(leftPanel._msufPresetPerf, preset == "perf")
                    MSUF_Misc_SetPresetButtonActive(leftPanel._msufPresetBal,  preset == "balanced")
                    MSUF_Misc_SetPresetButtonActive(leftPanel._msufPresetAcc,  preset == "accurate")
                end
            end

            local function MSUF_Misc_ApplyUpdatePreset(presetKey)
                if EnsureDB then EnsureDB() end
                MSUF_DB.general = MSUF_DB.general or {}
                local g = MSUF_DB.general

                local unitInterval, castInterval, budgetMs, urgentCap
                if presetKey == "perf" then
                    -- Maximum performance: fewer updates, smaller spikes
                    unitInterval = 0.12
                    castInterval = 0.06
                    budgetMs     = 1.0
                    urgentCap    = 6
                elseif presetKey == "accurate" then
                    -- Max accuracy: very frequent updates, fastest catch-up
                    unitInterval = 0.01
                    castInterval = 0.01
                    budgetMs     = 5.0
                    urgentCap    = 50
                else
                    -- Balanced (sane default)
                    presetKey    = "balanced"
                    unitInterval = 0.05
                    castInterval = 0.02
                    budgetMs     = 2.0
                    urgentCap    = 10
                end

                g.miscUpdatesPreset = presetKey

                -- Drive the sliders (their OnValueChanged handlers already write DB + runtime globals)
                if updateSlider and updateSlider.SetValue then updateSlider:SetValue(unitInterval) end
                if castbarUpdateSlider and castbarUpdateSlider.SetValue then castbarUpdateSlider:SetValue(castInterval) end
                if ufcoreBudgetSlider and ufcoreBudgetSlider.SetValue then ufcoreBudgetSlider:SetValue(budgetMs) end
                if ufcoreUrgentSlider and ufcoreUrgentSlider.SetValue then ufcoreUrgentSlider:SetValue(urgentCap) end

                MSUF_Misc_RefreshUpdatePresetButtons()
            end

            local function MSUF_Misc_MakePresetButton(parent, w, h, label)
                local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
                b:SetSize(w, h)
                b:SetText(label or "")

                -- Match Midnight-styled action buttons used elsewhere (if available)
                if MSUF_SkinMidnightActionButton then
                    MSUF_SkinMidnightActionButton(b, { textR = 1, textG = 0.85, textB = 0.1 })
                end

                return b
            end

            -- Build the preset button row once (under the "Updates" header)
            if leftPanel and not leftPanel._msufPresetRow then
                local row = CreateFrame("Frame", nil, leftPanel)
                row:SetSize(270, 22)
                row:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 14, -48)
                leftPanel._msufPresetRow = row

                local bw, bh, gap = 86, 20, 6
                local btnPerf = MSUF_Misc_MakePresetButton(row, bw, bh, "Perf...")
                btnPerf:SetPoint("LEFT", row, "LEFT", 0, 0)
                btnPerf:SetScript("OnClick", function() MSUF_Misc_ApplyUpdatePreset("perf") end)

                local btnBal = MSUF_Misc_MakePresetButton(row, bw, bh, "Balanced...")
                btnBal:SetPoint("LEFT", btnPerf, "RIGHT", gap, 0)
                btnBal:SetScript("OnClick", function() MSUF_Misc_ApplyUpdatePreset("balanced") end)

                local btnAcc = MSUF_Misc_MakePresetButton(row, bw, bh, "Accurate...")
                btnAcc:SetPoint("LEFT", btnBal, "RIGHT", gap, 0)
                btnAcc:SetScript("OnClick", function() MSUF_Misc_ApplyUpdatePreset("accurate") end)

                leftPanel._msufPresetPerf = btnPerf
                leftPanel._msufPresetBal  = btnBal
                leftPanel._msufPresetAcc  = btnAcc

                row:SetScript("OnShow", MSUF_Misc_RefreshUpdatePresetButtons)
                MSUF_Misc_RefreshUpdatePresetButtons()
            end

            local infoTooltipDisable = _G.MSUF_InfoTooltipDisableCheck
            local infoTooltipPosDrop = _G.MSUF_InfoTooltipPosDropdown
            local blizzUFDisable = _G.MSUF_DisableBlizzUFCheck
            local minimapIconCheck = _G.MSUF_MinimapIconCheck
            local targetSoundsCheck = _G.MSUF_TargetSoundsCheck
            -- LEFT: Updates

            if updateSlider then
                updateSlider:ClearAllPoints()
                updateSlider:SetParent(leftPanel)

                local lbl = MakeLabel(leftPanel, "Unit update interval (seconds)", "TOPLEFT", leftPanel, 14, -78)
                updateSlider:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -10)
                updateSlider:SetWidth(270)
            end

            if castbarUpdateSlider then
                castbarUpdateSlider:ClearAllPoints()
                castbarUpdateSlider:SetParent(leftPanel)

                local rel = updateSlider or leftPanel
                local lbl = MakeLabel(leftPanel, "Castbar update", "TOPLEFT", rel, (rel == leftPanel and 14) or 0, (rel == leftPanel and -158) or -36)
                if rel ~= leftPanel then
                    lbl:ClearAllPoints()
                    lbl:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 0, -16)
                end
                castbarUpdateSlider:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -10)
                castbarUpdateSlider:SetWidth(270)
            end

            if ufcoreBudgetSlider then
                ufcoreBudgetSlider:ClearAllPoints()
                ufcoreBudgetSlider:SetParent(leftPanel)

                local rel = castbarUpdateSlider or updateSlider or leftPanel
                local lbl = MakeLabel(leftPanel, "UFCore flush budget", "TOPLEFT", rel, (rel == leftPanel and 14) or 0, (rel == leftPanel and -158) or -36)
                if rel ~= leftPanel then
                    lbl:ClearAllPoints()
                    lbl:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 0, -16)
                end
                ufcoreBudgetSlider:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -10)
                ufcoreBudgetSlider:SetWidth(270)
            end

            if ufcoreUrgentSlider then
                ufcoreUrgentSlider:ClearAllPoints()
                ufcoreUrgentSlider:SetParent(leftPanel)

                local rel = ufcoreBudgetSlider or castbarUpdateSlider or updateSlider or leftPanel
                local lbl = MakeLabel(leftPanel, "UFCore urgent cap", "TOPLEFT", rel, (rel == leftPanel and 14) or 0, (rel == leftPanel and -158) or -36)
                if rel ~= leftPanel then
                    lbl:ClearAllPoints()
                    lbl:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 0, -16)
                end
                ufcoreUrgentSlider:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -10)
                ufcoreUrgentSlider:SetWidth(270)
            end

            -- RIGHT: Unit info panel
            if infoTooltipDisable then
                infoTooltipDisable:ClearAllPoints()
                infoTooltipDisable:SetParent(rightPanel)
                infoTooltipDisable:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 14, -50)
                StyleCheckbox(infoTooltipDisable)
            end

            if infoTooltipPosDrop then
                infoTooltipPosDrop:ClearAllPoints()
                infoTooltipPosDrop:SetParent(rightPanel)

                local rel = infoTooltipDisable or rightPanel
                local lbl = MakeLabel(rightPanel, "MSUF unit info panel position", "TOPLEFT", rel, 0, (rel == rightPanel and -50) or -28)
                if rel ~= rightPanel then
                    lbl:ClearAllPoints()
                    lbl:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 0, -16)
                end
                infoTooltipPosDrop:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", -16, -8)
            end

            if blizzUFDisable then
                blizzUFDisable:ClearAllPoints()
                blizzUFDisable:SetParent(rightPanel)

                local rel = infoTooltipPosDrop or infoTooltipDisable or rightPanel
                -- Subheader + divider line (style-only; wiring comes later)
                if not rightPanel._msufBlizzHeader then
                    rightPanel._msufBlizzHeader = MakeLabel(rightPanel, "Blizzard frames", "TOPLEFT", rel, 0, -35)
                    rightPanel._msufBlizzLine = rightPanel:CreateTexture(nil, "OVERLAY")
                    rightPanel._msufBlizzLine:SetColorTexture(1, 1, 1, 0.10)
                    rightPanel._msufBlizzLine:SetHeight(1)
                    rightPanel._msufBlizzLine:SetPoint("TOPLEFT", rightPanel._msufBlizzHeader, "BOTTOMLEFT", 0, -6)
                    rightPanel._msufBlizzLine:SetWidth(rightW - 28)
                else
                    rightPanel._msufBlizzHeader:ClearAllPoints()
                    rightPanel._msufBlizzHeader:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 0, -26)
                    rightPanel._msufBlizzLine:ClearAllPoints()
                    rightPanel._msufBlizzLine:SetPoint("TOPLEFT", rightPanel._msufBlizzHeader, "BOTTOMLEFT", 0, -6)
                    rightPanel._msufBlizzLine:SetWidth(rightW - 28)
                end

                blizzUFDisable:SetPoint("TOPLEFT", rightPanel._msufBlizzLine, "BOTTOMLEFT", 0, -10)
                StyleCheckbox(blizzUFDisable)
            end

if minimapIconCheck then
    minimapIconCheck:ClearAllPoints()
    minimapIconCheck:SetParent(rightPanel)

    -- PlayerFrame hide-mode toggle belongs in the Blizzard frames section.
    -- Anchor minimap toggle underneath it with a little extra spacing to avoid overlap.
    if hardKillPFCheck then
        hardKillPFCheck:ClearAllPoints()
        hardKillPFCheck:SetParent(rightPanel)

        if blizzUFDisable then
            hardKillPFCheck:SetPoint("TOPLEFT", blizzUFDisable, "BOTTOMLEFT", 0, -10)
        else
            local rel = rightPanel._msufBlizzLine or rightPanel
            hardKillPFCheck:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 0, -10)
        end
        StyleCheckbox(hardKillPFCheck)
    end

    local anchor = hardKillPFCheck or blizzUFDisable or (rightPanel._msufBlizzLine or rightPanel)
    minimapIconCheck:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    StyleCheckbox(minimapIconCheck)

    -- Place Target sounds toggle under the minimap icon toggle
    if targetSoundsCheck then
        targetSoundsCheck:ClearAllPoints()
        targetSoundsCheck:SetParent(rightPanel)
        targetSoundsCheck:SetPoint("TOPLEFT", minimapIconCheck, "BOTTOMLEFT", 0, -12)
        StyleCheckbox(targetSoundsCheck)
    end


end

            -- BOTTOM: Indicators
            local leftX = 14
            local rightX = 14
            -- Left column removed: Incoming resurrection controls moved to per-unit Status icons UI

            -- Right column: Status indicators (placeholders, wiring later)
            local rightHeader = MakeLabel(bottomPanel, "Status indicators", "TOPLEFT", bottomPanel, leftX, -34)
            rightHeader:ClearAllPoints()
            rightHeader:SetPoint("TOPLEFT", bottomPanel, "TOPLEFT", leftX, -34)
            local rightLine = bottomPanel:CreateTexture(nil, "ARTWORK")
            rightLine:SetColorTexture(1, 1, 1, 0.10)
            rightLine:SetHeight(1)
            rightLine:SetPoint("TOPLEFT", rightHeader, "BOTTOMLEFT", 0, -8)
            rightLine:SetPoint("TOPRIGHT", bottomPanel, "TOPRIGHT", -14, -42)

            local function GetStatusDB()
                EnsureDB()
                MSUF_DB.general = MSUF_DB.general or {}
                MSUF_DB.general.statusIndicators = MSUF_DB.general.statusIndicators or {}
                return MSUF_DB.general.statusIndicators
            end

            local function MSUF_IsBetaClient()
                -- Use the client's build flags when available. These APIs differ across branches, so guard each call.
                local ok, v
                if type(_G.IsBetaBuild) == "function" then ok, v = pcall(_G.IsBetaBuild); if ok and v then return true end end
                if type(_G.IsTestBuild) == "function" then ok, v = pcall(_G.IsTestBuild); if ok and v then return true end end
                if type(_G.IsAlphaBuild) == "function" then ok, v = pcall(_G.IsAlphaBuild); if ok and v then return true end end
                return false
            end

            -- Anchor for the status-indicator checkboxes (kept simple; popup warning handles Beta messaging)
            local statusAnchor = rightHeader

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
                        if _G.MSUF_RefreshStatusIndicators then
                            _G.MSUF_RefreshStatusIndicators()
                        end
                    end,
                    OnCancel = function(popup, data)
                        local d = data or (popup and popup.data)
                        if not d or not d.key or not d.cb or not d.getDB then return end
                        local db = d.getDB()
                        db[d.key] = false
                        d.cb:SetChecked(false)
                        if _G.MSUF_RefreshStatusIndicators then
                            _G.MSUF_RefreshStatusIndicators()
                        end
                    end,
                }
            end

            local function MakeStatusCB(key, label, yOff)
                local cb = CreateFrame("CheckButton", nil, bottomPanel, "InterfaceOptionsCheckButtonTemplate")
                cb:SetPoint("TOPLEFT", statusAnchor, "BOTTOMLEFT", 0, yOff)
                cb.Text:SetText(label)
                StyleCheckbox(cb)

                cb:SetScript("OnShow", function(self)
                    local db = GetStatusDB()
                    local v = db[key]
                    if v == nil then v = false end
                    self:SetChecked(v)
                end)

                cb:SetScript("OnClick", function(self)
                    local want = self:GetChecked() and true or false

                    -- Beta: show a confirmation popup when enabling AFK/DND (still allow usage if confirmed).
                    if want and MSUF_IsBetaClient() and (key == "showAFK" or key == "showDND") and _G.StaticPopup_Show then
                        EnsureBetaStatusPopup()
                        -- Don't flip the DB until the user confirms. Revert the check until then.
                        self:SetChecked(false)
                        local db = GetStatusDB()
                        db[key] = false

                        local popup = _G.StaticPopup_Show("MSUF_BETA_STATUS_AFKDND_WARNING", nil, nil, { key = key, cb = self, getDB = GetStatusDB })
                        if popup then
                            return
                        end
                        -- Fallback if popup failed for any reason: proceed.
                        want = true
                        self:SetChecked(true)
                    end

                    local db = GetStatusDB()
                    db[key] = want and true or false
                    if _G.MSUF_RefreshStatusIndicators then
                        _G.MSUF_RefreshStatusIndicators()
                    end
                end)

                return cb
            end

            -- Space checkboxes based on the actual checkbox height to prevent overlap/clipping.
            local _, th = MSUF_GetMiscToggleTargetSize()
            local step = (type(th) == "number" and th > 0) and (th + 6) or 30
            local y0 = -10
            local cbAFK   = MakeStatusCB("showAFK",   "Show AFK",   y0)
            local cbDND   = MakeStatusCB("showDND",   "Show DND",   y0 - step)
            local cbDead  = MakeStatusCB("showDead",  "Show Dead",  y0 - (step * 2))
            local cbGhost = MakeStatusCB("showGhost", "Show Ghost", y0 - (step * 3))

            bottomPanel._msufStatusCBs = { cbAFK, cbDND, cbDead, cbGhost }
        end
    end

end
