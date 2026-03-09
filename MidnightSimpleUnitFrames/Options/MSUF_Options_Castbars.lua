-- ---------------------------------------------------------------------------
-- MSUF_Options_Castbars.lua  (Phase 4: Rewrite using ns.UI.*)
--
-- Castbar tab: shake, fill direction, GCD bar, glow, latency, texture,
-- background texture, outline, empowered casts, spell name shortening.
-- ---------------------------------------------------------------------------
local addonName, ns = ...
local TR = ns.TR
local UI = ns.UI
local EnsureDB = ns.EnsureDB

function ns.MSUF_Options_Castbar_Build(panel, castbarGroupHost, castbarGroup, castbarEnemyGroup, castbarFocusGroup, castbarPlayerGroup, castbarTargetGroup, castbarBossGroup, ctx)
    if not panel or not castbarEnemyGroup then return end
    if castbarEnemyGroup._msufBuilt then return end
    castbarEnemyGroup._msufBuilt = true

    local function G() EnsureDB(); return MSUF_DB.general end
    local function Apply(kind) if type(_G.MSUF_Options_Apply) == "function" then _G.MSUF_Options_Apply(kind) end end
    local function EnsureCastbars()
        if type(_G.MSUF_EnsureAddonLoaded) == "function" then
            _G.MSUF_EnsureAddonLoaded("MidnightSimpleUnitFrames_Castbars")
        elseif _G.C_AddOns and type(_G.C_AddOns.LoadAddOn) == "function" then
            pcall(_G.C_AddOns.LoadAddOn, "MidnightSimpleUnitFrames_Castbars")
        end
    end
    local TEX_W8 = "Interface\\Buttons\\WHITE8x8"

    ---------------------------------------------------------------------------
    -- Focus Kick button + subpage system
    ---------------------------------------------------------------------------
    local castbarFocusButton = CreateFrame("Button", "MSUF_CastbarFocusButton", castbarGroupHost or castbarGroup, "UIPanelButtonTemplate")
    castbarFocusButton:SetSize(120, 22)
    castbarFocusButton:SetPoint("TOPLEFT", castbarGroupHost or castbarGroup, "TOPLEFT", 16, -150)
    castbarFocusButton:SetText(TR("Focus Kick"))
    castbarFocusButton:SetFrameLevel(((castbarGroupHost or castbarGroup):GetFrameLevel() or 0) + 10)
    if _G.MSUF_SkinMidnightActionButton then _G.MSUF_SkinMidnightActionButton(castbarFocusButton)
    elseif _G.MSUF_SkinMidnightTabButton then _G.MSUF_SkinMidnightTabButton(castbarFocusButton) end
    local fkfs = castbarFocusButton.GetFontString and castbarFocusButton:GetFontString()
    if fkfs and fkfs.SetTextColor then fkfs:SetTextColor(1, 0.82, 0) end

    function MSUF_SetActiveCastbarSubPage(page)
        if castbarEnemyGroup then castbarEnemyGroup:Hide() end
        if castbarPlayerGroup then castbarPlayerGroup:Hide() end
        if castbarTargetGroup then castbarTargetGroup:Hide() end
        if castbarBossGroup then castbarBossGroup:Hide() end
        if castbarFocusGroup then castbarFocusGroup:Hide() end
        if page == "focus" then
            if castbarFocusGroup then castbarFocusGroup:Show() end
        else
            if castbarEnemyGroup then castbarEnemyGroup:Show() end
        end
    end
    _G.MSUF_SetActiveCastbarSubPage = MSUF_SetActiveCastbarSubPage
    MSUF_SetActiveCastbarSubPage("enemy")

    castbarFocusButton:SetScript("OnClick", function()
        if castbarFocusGroup and castbarFocusGroup:IsShown() then
            MSUF_SetActiveCastbarSubPage("enemy")
        else
            MSUF_SetActiveCastbarSubPage("focus")
        end
    end)

    -- Focus Kick icon header
    if not _G["MSUF_FocusKickHeaderRight"] then
        local fkHeader = castbarFocusGroup:CreateFontString("MSUF_FocusKickHeaderRight", "ARTWORK", "GameFontNormal")
        fkHeader:SetPoint("TOPLEFT", castbarFocusGroup, "TOPLEFT", 300, -220)
        fkHeader:SetText(TR("Focus Kick Icon"))
    end
    if _G.MSUF_InitFocusKickIconOptions then _G.MSUF_InitFocusKickIconOptions() end

    ---------------------------------------------------------------------------
    -- Panel layout (3 columns: Behavior / Style / Empowered)
    ---------------------------------------------------------------------------
    local menuPanel = _G["MSUF_CastbarMenuPanel"]
    if not menuPanel then
        menuPanel = CreateFrame("Frame", "MSUF_CastbarMenuPanel", castbarEnemyGroup, "BackdropTemplate")
        menuPanel:SetPoint("TOPLEFT", castbarEnemyGroup, "TOPLEFT", 16, -175)
        menuPanel:SetPoint("RIGHT", castbarEnemyGroup, "RIGHT", -16, 0)
        menuPanel:SetHeight(620); menuPanel:EnableMouse(false)
        menuPanel:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
        menuPanel:SetBackdropColor(0, 0, 0, 0.20); menuPanel:SetBackdropBorderColor(1, 1, 1, 0.15)
        -- Split lines
        local vLine = menuPanel:CreateTexture(nil, "ARTWORK"); vLine:SetColorTexture(1, 1, 1, 0.12); vLine:SetWidth(1)
        vLine:SetPoint("TOP", menuPanel, "TOP", 0, -16); vLine:SetPoint("BOTTOM", menuPanel, "BOTTOM", 0, 150)
        local hLine = menuPanel:CreateTexture(nil, "ARTWORK"); hLine:SetColorTexture(1, 1, 1, 0.12); hLine:SetHeight(1)
        hLine:SetPoint("LEFT", menuPanel, "LEFT", 16, 0); hLine:SetPoint("RIGHT", menuPanel, "RIGHT", -16, 0); hLine:SetPoint("BOTTOM", menuPanel, "BOTTOM", 0, 150)
        -- Columns
        local leftCol = CreateFrame("Frame", "MSUF_CastbarMenuPanelLeft", menuPanel); leftCol:EnableMouse(false)
        leftCol:SetPoint("TOPLEFT", menuPanel, "TOPLEFT", 16, -16); leftCol:SetPoint("RIGHT", vLine, "LEFT", -16, 0); leftCol:SetPoint("BOTTOM", hLine, "TOP", 0, 12)
        local rightCol = CreateFrame("Frame", "MSUF_CastbarMenuPanelRight", menuPanel); rightCol:EnableMouse(false)
        rightCol:SetPoint("TOPRIGHT", menuPanel, "TOPRIGHT", -16, -16); rightCol:SetPoint("LEFT", vLine, "RIGHT", 16, 0); rightCol:SetPoint("BOTTOM", hLine, "TOP", 0, 12)
        local emp = CreateFrame("Frame", "MSUF_CastbarMenuPanelEmpowered", menuPanel); emp:EnableMouse(false)
        emp:SetPoint("BOTTOMLEFT", menuPanel, "BOTTOMLEFT", 16, 12); emp:SetPoint("BOTTOMRIGHT", menuPanel, "BOTTOMRIGHT", -16, 12); emp:SetPoint("TOP", hLine, "BOTTOM", 0, -12)
        -- Headers
        menuPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal"):SetPoint("TOP", leftCol, "TOP", 0, 8)
        _G["MSUF_CastbarMenuPanelLeft"]:GetParent():GetRegions()  -- force creation; header text set below
        local bH = menuPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal"); bH:SetPoint("TOP", leftCol, "TOP", 0, 8); bH:SetText(TR("Behavior"))
        local sH = menuPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal"); sH:SetPoint("TOP", rightCol, "TOP", 0, 8); sH:SetText(TR("Style"))
        local eH = menuPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal"); eH:SetPoint("TOPLEFT", emp, "TOPLEFT", 0, 0); eH:SetText(TR("Empowered casts"))
    end

    local leftCol  = _G["MSUF_CastbarMenuPanelLeft"]
    local rightCol = _G["MSUF_CastbarMenuPanelRight"]
    local emp      = _G["MSUF_CastbarMenuPanelEmpowered"]

    ---------------------------------------------------------------------------
    -- BEHAVIOR (left column)
    ---------------------------------------------------------------------------
    -- Forward-declare refs for cross-widget enable/disable
    local castbarGCDTimeCheck, castbarGCDSpellCheck

    local shakeCheck = UI.Check({
        name = "MSUF_CastbarInterruptShakeCheck", parent = castbarEnemyGroup, anchorPoint = "TOPLEFT",
        anchor = leftCol, anchorPoint = "TOPLEFT", x = 0, y = -20,
        label = TR("Shake on interrupt"),
        get = function() return G().castbarInterruptShake == true end,
        set = function(v) G().castbarInterruptShake = v end,
    })

    local shakeSlider = UI.Slider({
        name = "MSUF_CastbarShakeIntensitySlider", parent = castbarEnemyGroup,
        anchor = leftCol, anchorPoint = "TOPLEFT", x = 0, y = -55, width = 260,
        label = TR("Shake intensity"), min = 0, max = 30, step = 1, default = 8,
        get = function() return G().castbarShakeStrength or 8 end,
        set = function(v) G().castbarShakeStrength = v end,
    })

    local unifiedDirCheck = UI.Check({
        name = "MSUF_CastbarUnifiedDirectionCheck", parent = castbarEnemyGroup,
        anchor = leftCol, anchorPoint = "TOPLEFT", x = 0, y = -115,
        label = TR("Always use fill direction for all casts"),
        get = function() return G().castbarUnifiedDirection == true end,
        set = function(v) G().castbarUnifiedDirection = v; Apply("castbarFillDirection") end,
    })

    local fillDirLabel = UI.Label({ parent = castbarEnemyGroup, text = TR("Castbar fill direction"), anchor = unifiedDirCheck, y = -14 })

    local fillDirDrop = UI.Dropdown({
        name = "MSUF_CastbarFillDirectionDropdown", parent = castbarEnemyGroup,
        anchor = fillDirLabel, x = -16, y = -4, width = 200,
        items = {
            { key = "RTL", label = "Right to left (default)" },
            { key = "LTR", label = "Left to right" },
        },
        get = function() return G().castbarFillDirection or "RTL" end,
        set = function(v) G().castbarFillDirection = v; if _G.MSUF_UpdateCastbarFillDirection then _G.MSUF_UpdateCastbarFillDirection() end end,
    })

    local oppositeCheck = UI.Check({
        name = "MSUF_CastbarOpositeDirectionTarget", parent = castbarEnemyGroup,
        anchor = fillDirDrop, x = 16, y = -10,
        label = TR("Use opposite fill direction for target"),
        get = function() return G().castbarOpositeDirectionTarget ~= false end,
        set = function(v) G().castbarOpositeDirectionTarget = v; Apply("castbarOpositeDirectionTarget") end,
    })

    local ticksCheck = UI.Check({
        name = "MSUF_CastbarChannelTicksCheck", parent = castbarEnemyGroup,
        anchor = oppositeCheck, x = 0, y = -10,
        label = TR("Show channel tick lines (5)"),
        get = function() return G().castbarShowChannelTicks ~= false end,
        set = function(v) G().castbarShowChannelTicks = v; Apply("castbarTicks") end,
    })

    local function SyncGCDSubs()
        local on = G().showGCDBar ~= false
        if castbarGCDTimeCheck and castbarGCDTimeCheck.SetEnabled then castbarGCDTimeCheck:SetEnabled(on) end
        if castbarGCDSpellCheck and castbarGCDSpellCheck.SetEnabled then castbarGCDSpellCheck:SetEnabled(on) end
    end

    local gcdCheck = UI.Check({
        name = "MSUF_CastbarGCDBarCheck", parent = castbarEnemyGroup,
        anchor = ticksCheck, x = 0, y = -8,
        label = TR("Show GCD bar for instant casts"),
        get = function() return G().showGCDBar ~= false end,
        set = function(v)
            G().showGCDBar = v
            EnsureCastbars()
            if type(_G.MSUF_SetGCDBarEnabled) == "function" then _G.MSUF_SetGCDBarEnabled(v) end
            SyncGCDSubs()
        end,
    })

    local function ApplyGCDVisuals()
        EnsureCastbars()
        if type(_G.MSUF_PlayerGCDBar_Stop) == "function" then
            local f = _G.MSUF_PlayerCastBar or _G.MSUF_PlayerCastbar
            if f then _G.MSUF_PlayerGCDBar_Stop(f) end
        end
    end

    castbarGCDTimeCheck = UI.Check({
        name = "MSUF_CastbarGCDTimeCheck", parent = castbarEnemyGroup,
        anchor = gcdCheck, x = 18, y = -6,
        label = TR("GCD bar: show time text"),
        get = function() return G().showGCDBarTime ~= false end,
        set = function(v) G().showGCDBarTime = v; ApplyGCDVisuals() end,
    })

    castbarGCDSpellCheck = UI.Check({
        name = "MSUF_CastbarGCDSpellCheck", parent = castbarEnemyGroup,
        anchor = castbarGCDTimeCheck, x = 0, y = -6,
        label = TR("GCD bar: show spell name + icon"),
        get = function() return G().showGCDBarSpell ~= false end,
        set = function(v) G().showGCDBarSpell = v; ApplyGCDVisuals() end,
    })

    ---------------------------------------------------------------------------
    -- STYLE (right column)
    ---------------------------------------------------------------------------
    local function ApplyTextures()
        local fn = _G.MSUF_UpdateCastbarTextures_Immediate or _G.MSUF_UpdateCastbarTextures
        if type(fn) == "function" then fn() end
        EnsureCastbars()
        local fnVis = _G.MSUF_UpdateCastbarVisuals_Immediate or _G.MSUF_UpdateCastbarVisuals
        if type(fnVis) == "function" then fnVis() end
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then pcall(_G.MSUF_UpdateBossCastbarPreview) end
    end

    local texLabel = UI.Label({ parent = castbarEnemyGroup, text = TR("Castbar texture"), anchor = rightCol, anchorPoint = "TOPLEFT", y = -20 })

    local texDrop = UI.Dropdown({
        name = "MSUF_CastbarTextureDropdown", parent = castbarEnemyGroup,
        anchor = texLabel, x = -16, y = -4, width = 200, maxVisible = 12,
        iconWidth = 80, iconHeight = 12,
        items = function() return UI.StatusBarTextureItems(nil) end,
        get = function() return G().castbarTexture or "Blizzard" end,
        set = function(v) G().castbarTexture = v; ApplyTextures() end,
    })

    local bgLabel = UI.Label({ parent = castbarEnemyGroup, text = TR("Castbar background texture"), anchor = rightCol, anchorPoint = "TOPLEFT", y = -95 })

    local bgDrop = UI.Dropdown({
        name = "MSUF_CastbarBackgroundTextureDropdown", parent = castbarEnemyGroup,
        anchor = bgLabel, x = -16, y = -4, width = 200, maxVisible = 12,
        iconWidth = 80, iconHeight = 12,
        items = function() return UI.StatusBarTextureItems(nil) end,
        get = function()
            local g = G()
            local v = g.castbarBackgroundTexture
            if type(v) ~= "string" or v == "" then v = g.castbarTexture or "Blizzard" end
            return v
        end,
        set = function(v) G().castbarBackgroundTexture = v; ApplyTextures() end,
    })

    local outlineSlider = UI.Slider({
        name = "MSUF_CastbarOutlineThicknessSlider", parent = castbarEnemyGroup,
        anchor = rightCol, anchorPoint = "TOPLEFT", x = 0, y = -155, width = 260,
        label = TR("Outline thickness"), min = 0, max = 6, step = 1, default = 1,
        get = function() return G().castbarOutlineThickness or 1 end,
        set = function(v)
            G().castbarOutlineThickness = v
            Apply("castbarVisuals")
            if type(_G.MSUF_ApplyCastbarOutlineToAll) == "function" then _G.MSUF_ApplyCastbarOutlineToAll(true) end
            if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then pcall(_G.MSUF_UpdateBossCastbarPreview) end
        end,
    })

    local glowCheck = UI.Check({
        name = "MSUF_CastbarGlowCheck", parent = castbarEnemyGroup,
        anchor = outlineSlider, x = 0, y = -18,
        label = TR("Show castbar glow effect"),
        get = function() return G().castbarShowGlow ~= false end,
        set = function(v) G().castbarShowGlow = v; Apply("castbarGlow") end,
    })

    local latencyCheck = UI.Check({
        name = "MSUF_CastbarLatencyCheck", parent = castbarEnemyGroup,
        anchor = glowCheck, x = 0, y = -8,
        label = TR("Show latency indicator"),
        get = function() return G().castbarShowLatency ~= false end,
        set = function(v) G().castbarShowLatency = v; Apply("castbarLatency") end,
    })

    ---------------------------------------------------------------------------
    -- Spell Name Shortening (right column, below latency)
    ---------------------------------------------------------------------------
    local function ApplyVisualRefresh()
        EnsureCastbars()
        if type(_G.MSUF_UpdateCastbarVisuals) == "function" then _G.MSUF_UpdateCastbarVisuals() end
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then _G.MSUF_UpdateBossCastbarPreview() end
    end

    local shortenHeader = rightCol:CreateFontString("MSUF_CastbarSpellNameShortenHeader", "ARTWORK", "GameFontNormal")
    shortenHeader:SetText(TR("Name shortening"))
    shortenHeader:SetPoint("TOPLEFT", latencyCheck, "BOTTOMLEFT", 0, -18)

    -- On/Off toggle button (not a checkbox — ON→OFF forces reload)
    local toggleBtn = CreateFrame("Button", "MSUF_CastbarSpellNameShortenToggle", castbarEnemyGroup, "UIPanelButtonTemplate")
    toggleBtn:SetSize(120, 22)
    toggleBtn:SetPoint("TOPLEFT", shortenHeader, "BOTTOMLEFT", 0, -6)
    if _G.MSUF_SkinMidnightActionButton then _G.MSUF_SkinMidnightActionButton(toggleBtn, { textR = 1, textG = 1, textB = 1 }) end
    -- Hide legacy dropdown if it exists
    local oldDrop = _G["MSUF_CastbarSpellNameShortenDropdown"]
    if oldDrop then oldDrop:Hide(); oldDrop:SetAlpha(0); oldDrop:EnableMouse(false) end

    local maxSlider = UI.Slider({
        name = "MSUF_CastbarSpellNameMaxLenSlider", parent = castbarEnemyGroup,
        anchor = toggleBtn, x = 0, y = -30, width = 260,
        label = TR("Max name length"), min = 6, max = 30, step = 1, default = 30,
        get = function() return G().castbarSpellNameMaxLen or 30 end,
        set = function(v) G().castbarSpellNameMaxLen = v; ApplyVisualRefresh() end,
    })

    local resSlider = UI.Slider({
        name = "MSUF_CastbarSpellNameReservedSlider", parent = castbarEnemyGroup,
        anchor = maxSlider, x = 0, y = -48, width = 260,
        label = TR("Reserved space"), min = 0, max = 30, step = 1, default = 8,
        get = function() return G().castbarSpellNameReservedSpace or 8 end,
        set = function(v) G().castbarSpellNameReservedSpace = v; ApplyVisualRefresh() end,
    })

    local function SetBtnColor(btn, r, g, b, a)
        if not btn then return end
        local name = btn.GetName and btn:GetName()
        for _, key in ipairs({ "Left", "Middle", "Right" }) do
            local reg = btn[key] or (name and _G[name .. key])
            if reg then reg:SetTexture(TEX_W8); reg:SetVertexColor(r, g, b, a or 1) end
        end
        local nt = btn.GetNormalTexture and btn:GetNormalTexture()
        if nt then nt:SetTexture(TEX_W8); nt:SetVertexColor(r, g, b, a or 1); nt:SetTexCoord(0, 1, 0, 1) end
    end

    local function SyncShortenToggle()
        local cur = tonumber(G().castbarSpellNameShortening) or 0
        if cur > 0 then cur = 1 else cur = 0 end
        G().castbarSpellNameShortening = cur
        local enabled = (cur == 1)
        toggleBtn:SetText(enabled and TR("On") or TR("Off"))
        SetBtnColor(toggleBtn, enabled and 0.10 or 0.55, enabled and 0.45 or 0.12, enabled and 0.10 or 0.12, 0.95)
        if maxSlider.SetEnabled then maxSlider:SetEnabled(enabled) end
        if resSlider.SetEnabled then resSlider:SetEnabled(enabled) end
        maxSlider:SetAlpha(enabled and 1 or 0.45)
        resSlider:SetAlpha(enabled and 1 or 0.45)
    end

    SyncShortenToggle()
    toggleBtn:SetScript("OnClick", function()
        local prev = tonumber(G().castbarSpellNameShortening) or 0
        if prev > 0 then prev = 1 else prev = 0 end
        local newV = (prev == 1) and 0 or 1
        G().castbarSpellNameShortening = newV
        if prev == 1 and newV == 0 then
            if ReloadUI then ReloadUI() end
            return
        end
        SyncShortenToggle()
        ApplyVisualRefresh()
    end)

    ---------------------------------------------------------------------------
    -- EMPOWERED (bottom section)
    ---------------------------------------------------------------------------
    local empColorCheck = UI.Check({
        name = "MSUF_EmpowerColorStagesCheck", parent = castbarEnemyGroup,
        anchor = emp, anchorPoint = "TOPLEFT", x = 0, y = -22,
        label = TR("Add color to stages (Empowered casts)"),
        get = function() return G().empowerColorStages ~= false end,
        set = function(v)
            G().empowerColorStages = v; Apply("castbarVisuals")
            -- Enable/disable blink based on color state
            local blinkCB = _G["MSUF_EmpowerStageBlinkCheck"]
            if blinkCB and blinkCB.SetEnabled then blinkCB:SetEnabled(v) end
        end,
    })

    local empBlinkCheck = UI.Check({
        name = "MSUF_EmpowerStageBlinkCheck", parent = castbarEnemyGroup,
        anchor = empColorCheck, x = 0, y = -10,
        label = TR("Add stage blink (Empowered casts)"),
        get = function() return G().empowerStageBlink ~= false end,
        set = function(v) G().empowerStageBlink = v; Apply("castbarVisuals") end,
    })

    local empBlinkSlider = UI.Slider({
        name = "MSUF_EmpowerStageBlinkTimeSlider", parent = castbarEnemyGroup,
        compact = true,
        anchor = emp, anchorPoint = "TOPLEFT", x = 300, y = -24, width = 260,
        label = TR("Stage blink time (sec)"), min = 0.05, max = 1.00, step = 0.01, default = 0.25,
        lowText = "0.05", highText = "1.00",
        get = function() return G().empowerStageBlinkTime or 0.25 end,
        set = function(v) G().empowerStageBlinkTime = v; Apply("castbarVisuals") end,
    })

    ---------------------------------------------------------------------------
    -- Panel store for Core LoadFromDB compat
    ---------------------------------------------------------------------------
    panel.castbarShakeIntensitySlider = shakeSlider
end
