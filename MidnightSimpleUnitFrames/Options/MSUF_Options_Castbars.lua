-- ---------------------------------------------------------------------------
-- MSUF_Options_Castbars.lua  (Phase 5: Accordion UX)
--
-- Castbar tab: collapsible sections (same pattern as Bars / Player / Auras).
-- Focus Kick integrated as section 6 (no separate subpage).
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
    local CreateFrame = CreateFrame
    local math_pi = math.pi
    local C_Timer = C_Timer

    -- Force castbarEnemyGroup visible (legacy subpage Hide/Show cycle guard)
    castbarEnemyGroup:Show()

    -- Hide legacy subpage groups — we use one flat section list now
    if castbarFocusGroup then castbarFocusGroup:Hide() end
    if castbarTargetGroup then castbarTargetGroup:Hide() end
    if castbarBossGroup then castbarBossGroup:Hide() end
    if castbarPlayerGroup then castbarPlayerGroup:Hide() end
    _G.MSUF_SetActiveCastbarSubPage = function() end

    -- Scroll update: mirrors Core's local MSUF_CastbarMenu_QueueScrollUpdate
    local function QueueScrollUpdate()
        local host = castbarGroupHost
        if not host then return end
        local scroll = host._msufCastbarScroll
        local child  = host._msufCastbarScrollChild
        if not (scroll and child and child.SetHeight) then return end
        if host._msufCastbarScrollQueued then return end
        host._msufCastbarScrollQueued = true
        local function run()
            host._msufCastbarScrollQueued = false
            if not (scroll and child) then return end
            local top = child.GetTop and child:GetTop()
            if not top then return end
            local lowest = top
            local content = host._msufCastbarContent
            if content and content.GetChildren then
                local regions = { content:GetChildren() }
                for i = 1, #regions do
                    local r = regions[i]
                    if r and r.IsShown and r:IsShown() and r.GetBottom then
                        local b = r:GetBottom()
                        if b and b < lowest then lowest = b end
                    end
                end
            end
            local h = math.ceil((top - lowest) + 32)
            if h < 500 then h = 500 end
            child:SetHeight(h)
            local w = scroll:GetWidth()
            if w and w > 1 then child:SetWidth(w) end
            if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
            if _G.UIPanelScrollFrame_Update then _G.UIPanelScrollFrame_Update(scroll) end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
    end

    -- =====================================================================
    -- Collapsible section helper (matches Player / Auras pattern)
    -- =====================================================================
    local SECTION_W = 720
    local SECTION_COLLAPSED_H = 28

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
        box._msufTitleText = title

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
            QueueScrollUpdate()
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
    -- Section 1: Shake & Fill Direction (default open)
    -- =====================================================================
    local s1Box, s1Body = MakeCollapsibleSection(castbarEnemyGroup, 200, "Shake & Fill Direction", true)
    s1Box:SetPoint("TOPLEFT", castbarEnemyGroup, "TOPLEFT", 16, -155)

    local shakeCheck = UI.Check({
        name = "MSUF_CastbarInterruptShakeCheck", parent = s1Body,
        anchor = s1Body, anchorPoint = "TOPLEFT", x = 12, y = -6,
        label = TR("Shake on interrupt"),
        get = function() return G().castbarInterruptShake == true end,
        set = function(v) G().castbarInterruptShake = v end,
    })

    local shakeSlider = UI.Slider({
        name = "MSUF_CastbarShakeIntensitySlider", parent = s1Body,
        anchor = shakeCheck, x = 18, y = -14, width = 240, compact = true,
        label = TR("Shake intensity"), min = 0, max = 30, step = 1, default = 8,
        get = function() return G().castbarShakeStrength or 8 end,
        set = function(v) G().castbarShakeStrength = v end,
    })

    local unifiedDirCheck = UI.Check({
        name = "MSUF_CastbarUnifiedDirectionCheck", parent = s1Body,
        anchor = s1Body, anchorPoint = "TOPLEFT", x = 370, y = -6,
        label = TR("Always use fill direction for all casts"),
        get = function() return G().castbarUnifiedDirection == true end,
        set = function(v) G().castbarUnifiedDirection = v; Apply("castbarFillDirection") end,
    })

    local fillDirLabel = UI.Label({ parent = s1Body, text = TR("Castbar fill direction"), anchor = unifiedDirCheck, y = -10 })

    local fillDirDrop = UI.Dropdown({
        name = "MSUF_CastbarFillDirectionDropdown", parent = s1Body,
        anchor = fillDirLabel, x = -16, y = -4, width = 220,
        items = {
            { key = "RTL", label = "Right to left (default)" },
            { key = "LTR", label = "Left to right" },
        },
        get = function() return G().castbarFillDirection or "RTL" end,
        set = function(v) G().castbarFillDirection = v; if _G.MSUF_UpdateCastbarFillDirection then _G.MSUF_UpdateCastbarFillDirection() end end,
    })

    local oppositeCheck = UI.Check({
        name = "MSUF_CastbarOpositeDirectionTarget", parent = s1Body,
        anchor = fillDirDrop, x = 16, y = -8,
        label = TR("Use opposite fill direction for target"),
        get = function() return G().castbarOpositeDirectionTarget ~= false end,
        set = function(v) G().castbarOpositeDirectionTarget = v; Apply("castbarOpositeDirectionTarget") end,
    })

    local ticksCheck = UI.Check({
        name = "MSUF_CastbarChannelTicksCheck", parent = s1Body,
        anchor = oppositeCheck, x = 0, y = -6,
        label = TR("Show channel tick lines (5)"),
        get = function() return G().castbarShowChannelTicks ~= false end,
        set = function(v) G().castbarShowChannelTicks = v; Apply("castbarTicks") end,
    })

    -- =====================================================================
    -- Section 2: GCD Bar
    -- =====================================================================
    local castbarGCDTimeCheck, castbarGCDSpellCheck

    local s2Box, s2Body = MakeCollapsibleSection(castbarEnemyGroup, 135, "GCD Bar", false)
    s2Box:SetPoint("TOPLEFT", s1Box, "BOTTOMLEFT", 0, -6)

    local function SyncGCDSubs()
        local on = G().showGCDBar ~= false
        if castbarGCDTimeCheck and castbarGCDTimeCheck.SetEnabled then castbarGCDTimeCheck:SetEnabled(on) end
        if castbarGCDSpellCheck and castbarGCDSpellCheck.SetEnabled then castbarGCDSpellCheck:SetEnabled(on) end
    end

    local gcdCheck = UI.Check({
        name = "MSUF_CastbarGCDBarCheck", parent = s2Body,
        anchor = s2Body, anchorPoint = "TOPLEFT", x = 12, y = -6,
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
        name = "MSUF_CastbarGCDTimeCheck", parent = s2Body,
        anchor = gcdCheck, x = 18, y = -4,
        label = TR("GCD bar: show time text"),
        get = function() return G().showGCDBarTime ~= false end,
        set = function(v) G().showGCDBarTime = v; ApplyGCDVisuals() end,
    })

    castbarGCDSpellCheck = UI.Check({
        name = "MSUF_CastbarGCDSpellCheck", parent = s2Body,
        anchor = castbarGCDTimeCheck, x = 0, y = -4,
        label = TR("GCD bar: show spell name + icon"),
        get = function() return G().showGCDBarSpell ~= false end,
        set = function(v) G().showGCDBarSpell = v; ApplyGCDVisuals() end,
    })

    -- =====================================================================
    -- Section 3: Textures & Outline
    -- =====================================================================
    local s3Box, s3Body = MakeCollapsibleSection(castbarEnemyGroup, 310, "Textures & Outline", false)
    s3Box:SetPoint("TOPLEFT", s2Box, "BOTTOMLEFT", 0, -6)

    local function ApplyTextures()
        local fn = _G.MSUF_UpdateCastbarTextures_Immediate or _G.MSUF_UpdateCastbarTextures
        if type(fn) == "function" then fn() end
        EnsureCastbars()
        local fnVis = _G.MSUF_UpdateCastbarVisuals_Immediate or _G.MSUF_UpdateCastbarVisuals
        if type(fnVis) == "function" then fnVis() end
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then pcall(_G.MSUF_UpdateBossCastbarPreview) end
    end

    local texLabel = UI.Label({ parent = s3Body, text = TR("Castbar texture"), anchor = s3Body, anchorPoint = "TOPLEFT", x = 12, y = -6 })

    local texDrop = UI.Dropdown({
        name = "MSUF_CastbarTextureDropdown", parent = s3Body,
        anchor = texLabel, x = -16, y = -4, width = 260, maxVisible = 12,
        iconWidth = 80, iconHeight = 12,
        items = function() return UI.StatusBarTextureItems(nil) end,
        get = function() return G().castbarTexture or "Blizzard" end,
        set = function(v) G().castbarTexture = v; ApplyTextures() end,
    })

    local bgLabel = UI.Label({ parent = s3Body, text = TR("Castbar background texture"), anchor = texDrop, x = 16, y = -10 })

    local bgDrop = UI.Dropdown({
        name = "MSUF_CastbarBackgroundTextureDropdown", parent = s3Body,
        anchor = bgLabel, x = -16, y = -4, width = 260, maxVisible = 12,
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
        name = "MSUF_CastbarOutlineThicknessSlider", parent = s3Body,
        anchor = s3Body, anchorPoint = "TOPLEFT", x = 370, y = -6, width = 260, compact = true,
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
        name = "MSUF_CastbarGlowCheck", parent = s3Body,
        anchor = outlineSlider, x = 0, y = -18,
        label = TR("Show castbar glow effect"),
        get = function() return G().castbarShowGlow ~= false end,
        set = function(v) G().castbarShowGlow = v; Apply("castbarGlow") end,
    })

    local latencyCheck = UI.Check({
        name = "MSUF_CastbarLatencyCheck", parent = s3Body,
        anchor = glowCheck, x = 0, y = -6,
        label = TR("Show latency indicator"),
        get = function() return G().castbarShowLatency ~= false end,
        set = function(v) G().castbarShowLatency = v; Apply("castbarLatency") end,
    })

    local sparkCheck = UI.Check({
        name = "MSUF_CastbarSparkCheck", parent = s3Body,
        anchor = latencyCheck, x = 0, y = -6,
        label = TR("Show spark (leading edge highlight)"),
        get = function() return G().castbarShowSpark == true end,
        set = function(v) G().castbarShowSpark = v; ApplyTextures() end,
    })

    local sparkOverflowCheck = UI.Check({
        name = "MSUF_CastbarSparkOverflowCheck", parent = s3Body,
        anchor = sparkCheck, x = 18, y = -6,
        label = TR("Spark extends beyond bar"),
        get = function() return G().castbarSparkOverflow ~= false end,
        set = function(v) G().castbarSparkOverflow = v; ApplyTextures() end,
    })

    local matchLabel = UI.Label({ parent = s3Body, text = TR("Player castbar width source"), anchor = sparkOverflowCheck, y = -12 })

    local matchDrop = UI.Dropdown({
        name = "MSUF_CastbarPlayerMatchWidthDropdown", parent = s3Body,
        anchor = matchLabel, x = -16, y = -4, width = 260,
        items = {
            { key = "manual",    label = "Manual (per-unit width)" },
            { key = "essential", label = "Essential Cooldown Row" },
            { key = "utility",   label = "Utility Cooldown Bar" },
        },
        get = function()
            local v = G().castbarPlayerMatchWidth
            if v == "essential" or v == "utility" then return v end
            return "manual"
        end,
        set = function(v)
            if v == "manual" then v = nil end
            G().castbarPlayerMatchWidth = v
            ApplyTextures()
            if type(_G.MSUF_ReanchorPlayerCastBar) == "function" then _G.MSUF_ReanchorPlayerCastBar() end
        end,
    })

    -- =====================================================================
    -- Section 4: Empowered Casts
    -- =====================================================================
    local s4Box, s4Body = MakeCollapsibleSection(castbarEnemyGroup, 110, "Empowered Casts", false)
    s4Box:SetPoint("TOPLEFT", s3Box, "BOTTOMLEFT", 0, -6)

    local empColorCheck = UI.Check({
        name = "MSUF_EmpowerColorStagesCheck", parent = s4Body,
        anchor = s4Body, anchorPoint = "TOPLEFT", x = 12, y = -6,
        label = TR("Add color to stages (Empowered casts)"),
        get = function() return G().empowerColorStages ~= false end,
        set = function(v)
            G().empowerColorStages = v; Apply("castbarVisuals")
            local blinkCB = _G["MSUF_EmpowerStageBlinkCheck"]
            if blinkCB and blinkCB.SetEnabled then blinkCB:SetEnabled(v) end
        end,
    })

    local empBlinkCheck = UI.Check({
        name = "MSUF_EmpowerStageBlinkCheck", parent = s4Body,
        anchor = empColorCheck, x = 0, y = -6,
        label = TR("Add stage blink (Empowered casts)"),
        get = function() return G().empowerStageBlink ~= false end,
        set = function(v) G().empowerStageBlink = v; Apply("castbarVisuals") end,
    })

    local empBlinkSlider = UI.Slider({
        name = "MSUF_EmpowerStageBlinkTimeSlider", parent = s4Body,
        compact = true,
        anchor = s4Body, anchorPoint = "TOPLEFT", x = 370, y = -8, width = 260,
        label = TR("Stage blink time (sec)"), min = 0.05, max = 1.00, step = 0.01, default = 0.25,
        lowText = "0.05", highText = "1.00",
        get = function() return G().empowerStageBlinkTime or 0.25 end,
        set = function(v) G().empowerStageBlinkTime = v; Apply("castbarVisuals") end,
    })

    -- =====================================================================
    -- Section 5: Name Shortening
    -- =====================================================================
    local s5Box, s5Body = MakeCollapsibleSection(castbarEnemyGroup, 140, "Name Shortening", false)
    s5Box:SetPoint("TOPLEFT", s4Box, "BOTTOMLEFT", 0, -6)

    local function ApplyVisualRefresh()
        EnsureCastbars()
        if type(_G.MSUF_UpdateCastbarVisuals) == "function" then _G.MSUF_UpdateCastbarVisuals() end
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then _G.MSUF_UpdateBossCastbarPreview() end
    end

    local toggleBtn = CreateFrame("Button", "MSUF_CastbarSpellNameShortenToggle", s5Body, "UIPanelButtonTemplate")
    toggleBtn:SetSize(120, 22)
    toggleBtn:SetPoint("TOPLEFT", s5Body, "TOPLEFT", 12, -6)
    if _G.MSUF_SkinMidnightActionButton then _G.MSUF_SkinMidnightActionButton(toggleBtn, { textR = 1, textG = 1, textB = 1 }) end

    local oldDrop = _G["MSUF_CastbarSpellNameShortenDropdown"]
    if oldDrop then oldDrop:Hide(); oldDrop:SetAlpha(0); oldDrop:EnableMouse(false) end

    local maxSlider = UI.Slider({
        name = "MSUF_CastbarSpellNameMaxLenSlider", parent = s5Body,
        anchor = s5Body, anchorPoint = "TOPLEFT", x = 370, y = -6, width = 260, compact = true,
        label = TR("Max name length"), min = 6, max = 30, step = 1, default = 30,
        get = function() return G().castbarSpellNameMaxLen or 30 end,
        set = function(v) G().castbarSpellNameMaxLen = v; ApplyVisualRefresh() end,
    })

    local resSlider = UI.Slider({
        name = "MSUF_CastbarSpellNameReservedSlider", parent = s5Body,
        anchor = maxSlider, x = 0, y = -44, width = 260, compact = true,
        label = TR("Reserved space"), min = 0, max = 30, step = 1, default = 8,
        get = function() return G().castbarSpellNameReservedSpace or 8 end,
        set = function(v) G().castbarSpellNameReservedSpace = v; ApplyVisualRefresh() end,
    })

    local function SetBtnColor(btn, r, g, b, a)
        if not btn then return end
        local bname = btn.GetName and btn:GetName()
        for _, key in ipairs({ "Left", "Middle", "Right" }) do
            local reg = btn[key] or (bname and _G[bname .. key])
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

    -- =====================================================================
    -- Section 6: Focus Kick
    -- =====================================================================
    local s6Box, s6Body = MakeCollapsibleSection(castbarEnemyGroup, 285, "Focus Kick", false)
    s6Box:SetPoint("TOPLEFT", s5Box, "BOTTOMLEFT", 0, -6)

    local _fkSyncing = false

    local function FKEnsureDB()
        EnsureDB()
        local g = _G.MSUF_DB.general
        if g.enableFocusKickIcon == nil then g.enableFocusKickIcon = false end
        if g.focusKickIconOffsetX == nil then g.focusKickIconOffsetX = 300 end
        if g.focusKickIconOffsetY == nil then g.focusKickIconOffsetY = 0 end
        if g.focusKickIconWidth == nil then g.focusKickIconWidth = 40 end
        if g.focusKickIconHeight == nil then g.focusKickIconHeight = 40 end
    end

    local function FKApply()
        if type(_G.MSUF_UpdateFocusKickIconOptions) == "function" then _G.MSUF_UpdateFocusKickIconOptions() end
    end

    local function FKApplyFont()
        if type(_G.MSUF_FocusKick_ApplyTimeTextFont) == "function" then _G.MSUF_FocusKick_ApplyTimeTextFont() end
        FKApply()
    end

    -- Left column: Enable + desc + preview
    local fkEnableCheck = UI.Check({
        name = "MSUF_FocusKickIconCheck", parent = s6Body,
        anchor = s6Body, anchorPoint = "TOPLEFT", x = 12, y = -6,
        label = TR("Enable focus interrupt tracker"),
        get = function() FKEnsureDB(); return _G.MSUF_DB.general.enableFocusKickIcon == true end,
        set = function(v)
            if _fkSyncing then return end
            FKEnsureDB()
            _G.MSUF_DB.general.enableFocusKickIcon = v
            FKApply()
            if not v and type(_G.MSUF_FocusKick_SetPreviewEnabled) == "function" then
                _G.MSUF_FocusKick_SetPreviewEnabled(false)
            end
        end,
    })

    local fkDesc = s6Body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fkDesc:SetPoint("TOPLEFT", fkEnableCheck, "BOTTOMLEFT", 20, -2)
    fkDesc:SetWidth(300)
    fkDesc:SetJustifyH("LEFT")
    fkDesc:SetText(TR("Track interrupts on your focus without showing the focus castbar."))
    fkDesc:SetTextColor(0.55, 0.55, 0.55)

    local fkPreviewCheck = UI.Check({
        name = "MSUF_FocusKickPreviewCheckInline", parent = s6Body,
        anchor = fkDesc, anchorPoint = "BOTTOMLEFT", x = -20, y = -6,
        label = TR("Show on-screen preview"),
        get = function()
            return (type(_G.MSUF_FocusKick_IsPreviewEnabled) == "function") and _G.MSUF_FocusKick_IsPreviewEnabled() or false
        end,
        set = function(v)
            if _fkSyncing then return end
            if type(_G.MSUF_FocusKick_SetPreviewEnabled) == "function" then
                _G.MSUF_FocusKick_SetPreviewEnabled(v)
            end
        end,
    })

    -- Right column: Size sliders (all aligned at x=380)
    local FK_RIGHT = 380

    local fkSizeLabel = s6Body:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fkSizeLabel:SetPoint("TOPLEFT", s6Body, "TOPLEFT", FK_RIGHT, -6)
    fkSizeLabel:SetText(TR("Size"))

    local fkWidthSlider = UI.Slider({
        name = "MSUF_FocusKickIconWidthSlider", parent = s6Body,
        anchor = fkSizeLabel, x = 0, y = -8, width = 260, compact = true,
        label = TR("Width"), min = 16, max = 128, step = 1, default = 40,
        get = function() FKEnsureDB(); return _G.MSUF_DB.general.focusKickIconWidth or 40 end,
        set = function(v) if _fkSyncing then return end; FKEnsureDB(); _G.MSUF_DB.general.focusKickIconWidth = v; FKApply() end,
    })

    local fkHeightSlider = UI.Slider({
        name = "MSUF_FocusKickIconHeightSlider", parent = s6Body,
        anchor = fkWidthSlider, x = 0, y = -36, width = 260, compact = true,
        label = TR("Height"), min = 16, max = 128, step = 1, default = 40,
        get = function() FKEnsureDB(); return _G.MSUF_DB.general.focusKickIconHeight or 40 end,
        set = function(v) if _fkSyncing then return end; FKEnsureDB(); _G.MSUF_DB.general.focusKickIconHeight = v; FKApply() end,
    })

    local fkTextSlider = UI.Slider({
        name = "MSUF_FocusKickTextSizeSlider", parent = s6Body,
        anchor = fkHeightSlider, x = 0, y = -36, width = 260, compact = true,
        label = TR("Text size"), min = 8, max = 24, step = 1, default = 12,
        get = function()
            FKEnsureDB()
            local v = tonumber(_G.MSUF_DB.general.focusKickTextSize)
            if not v then
                local h = tonumber(_G.MSUF_DB.general.focusKickIconHeight) or 40
                return h >= 48 and 14 or 12
            end
            return v
        end,
        set = function(v) if _fkSyncing then return end; FKEnsureDB(); _G.MSUF_DB.general.focusKickTextSize = v; FKApplyFont() end,
    })

    -- Divider anchors to right column bottom (text size slider extends deeper than preview check)
    local fkPosDivider = s6Body:CreateTexture(nil, "ARTWORK")
    fkPosDivider:SetPoint("TOPLEFT", fkTextSlider, "BOTTOMLEFT", -FK_RIGHT + 12, -12)
    fkPosDivider:SetPoint("RIGHT", s6Body, "RIGHT", -12, 0)
    fkPosDivider:SetHeight(1)
    fkPosDivider:SetColorTexture(1, 1, 1, 0.06)

    -- Position row: X left, Y right (same Y line)
    local fkPosLabel = s6Body:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fkPosLabel:SetPoint("TOPLEFT", fkPosDivider, "BOTTOMLEFT", 0, -8)
    fkPosLabel:SetText(TR("Position"))

    local fkOffXSlider = UI.Slider({
        name = "MSUF_FocusKickIconOffsetXSlider", parent = s6Body,
        anchor = fkPosLabel, x = 0, y = -8, width = 280, compact = true,
        label = TR("X offset"), min = -500, max = 500, step = 1, default = 300,
        get = function() FKEnsureDB(); return _G.MSUF_DB.general.focusKickIconOffsetX or 300 end,
        set = function(v) if _fkSyncing then return end; FKEnsureDB(); _G.MSUF_DB.general.focusKickIconOffsetX = v; FKApply() end,
    })

    local fkOffYSlider = UI.Slider({
        name = "MSUF_FocusKickIconOffsetYSlider", parent = s6Body,
        anchor = fkPosLabel, x = FK_RIGHT - 12, y = -8, width = 280, compact = true,
        label = TR("Y offset"), min = -500, max = 500, step = 1, default = 0,
        get = function() FKEnsureDB(); return _G.MSUF_DB.general.focusKickIconOffsetY or 0 end,
        set = function(v) if _fkSyncing then return end; FKEnsureDB(); _G.MSUF_DB.general.focusKickIconOffsetY = v; FKApply() end,
    })

    local fkResetBtn = UI.Button({
        name = "MSUF_FocusKickResetPositionButton", parent = s6Body,
        anchor = fkOffXSlider, x = 0, y = -16, width = 150, height = 22,
        text = TR("Reset Position"),
        onClick = function()
            FKEnsureDB()
            _G.MSUF_DB.general.focusKickIconOffsetX = 0
            _G.MSUF_DB.general.focusKickIconOffsetY = 0
            if fkOffXSlider.SetValueClean then fkOffXSlider:SetValueClean(0) else fkOffXSlider:SetValue(0) end
            if fkOffYSlider.SetValueClean then fkOffYSlider:SetValueClean(0) else fkOffYSlider:SetValue(0) end
            FKApply()
        end,
    })

    _G.MSUF_FocusKickOptionsBuiltInCastbar = true

    -- =====================================================================
    -- Section 7: Interrupt Ready Indicator
    -- =====================================================================
    local s7Box, s7Body = MakeCollapsibleSection(castbarEnemyGroup, 240, "Interrupt Ready Indicator", false)
    s7Box:SetPoint("TOPLEFT", s6Box, "BOTTOMLEFT", 0, -6)

    local function KickApply()
        Apply("castbarVisuals")
        if type(_G.MSUF_UpdateCastbarVisuals) == "function" then pcall(_G.MSUF_UpdateCastbarVisuals) end
    end

    local kickDesc = s7Body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    kickDesc:SetPoint("TOPLEFT", s7Body, "TOPLEFT", 12, -6)
    kickDesc:SetWidth(600)
    kickDesc:SetJustifyH("LEFT")
    kickDesc:SetText(TR("Shows a colored indicator on castbars when your interrupt is ready (green) or on cooldown (red). Only visible during interruptible casts."))

    local kickTargetCheck = UI.Check({
        name = "MSUF_KickReadyTargetCheck", parent = s7Body,
        anchor = kickDesc, x = 0, y = -10,
        label = TR("Show on Target castbar"),
        get = function() return G().kickReadyShowTarget == true end,
        set = function(v) G().kickReadyShowTarget = v; KickApply() end,
    })

    local kickFocusCheck = UI.Check({
        name = "MSUF_KickReadyFocusCheck", parent = s7Body,
        anchor = kickTargetCheck, x = 0, y = -6,
        label = TR("Show on Focus castbar"),
        get = function() return G().kickReadyShowFocus == true end,
        set = function(v) G().kickReadyShowFocus = v; KickApply() end,
    })

    local kickBossCheck = UI.Check({
        name = "MSUF_KickReadyBossCheck", parent = s7Body,
        anchor = kickFocusCheck, x = 0, y = -6,
        label = TR("Show on Boss castbars"),
        get = function() return G().kickReadyShowBoss == true end,
        set = function(v) G().kickReadyShowBoss = v; KickApply() end,
    })

    local kickSizeSlider = UI.Slider({
        name = "MSUF_KickReadySizeSlider", parent = s7Body,
        anchor = s7Body, anchorPoint = "TOPLEFT", x = 370, y = -30, width = 260, compact = true,
        label = TR("Indicator size"), min = 4, max = 24, step = 1, default = 8,
        get = function() return G().kickReadySize or 8 end,
        set = function(v) G().kickReadySize = v; KickApply() end,
    })

    local kickAnchorDrop = UI.Dropdown({
        name = "MSUF_KickReadyAnchorDropdown", parent = s7Body,
        anchor = kickSizeSlider, x = 0, y = -12, width = 260,
        items = {
            { key = "RIGHT",  label = "Right" },
            { key = "LEFT",   label = "Left" },
            { key = "TOP",    label = "Top" },
            { key = "BOTTOM", label = "Bottom" },
        },
        get = function() return G().kickReadyAnchor or "RIGHT" end,
        set = function(v) G().kickReadyAnchor = v; KickApply() end,
    })

    local kickOffXSlider = UI.Slider({
        name = "MSUF_KickReadyOffsetXSlider", parent = s7Body,
        anchor = kickAnchorDrop, x = 0, y = -12, width = 260, compact = true,
        label = TR("X offset"), min = -50, max = 50, step = 1, default = 4,
        get = function() return G().kickReadyOffsetX or 4 end,
        set = function(v) G().kickReadyOffsetX = v; KickApply() end,
    })

    local kickOffYSlider = UI.Slider({
        name = "MSUF_KickReadyOffsetYSlider", parent = s7Body,
        anchor = kickOffXSlider, x = 0, y = -36, width = 260, compact = true,
        label = TR("Y offset"), min = -50, max = 50, step = 1, default = 0,
        get = function() return G().kickReadyOffsetY or 0 end,
        set = function(v) G().kickReadyOffsetY = v; KickApply() end,
    })

    -- =====================================================================
    -- Bottom anchor (for Edit Mode button placement from Options_Core)
    -- =====================================================================
    local bottomAnchor = CreateFrame("Frame", "MSUF_CastbarMenuPanel", castbarEnemyGroup)
    bottomAnchor:SetSize(SECTION_W, 1)
    bottomAnchor:SetPoint("TOPLEFT", s7Box, "BOTTOMLEFT", 0, -4)

    -- =====================================================================
    -- SyncAll (called on OnShow)
    -- =====================================================================
    local function SyncAll()
        EnsureDB()
        SyncGCDSubs()
        SyncShortenToggle()
        QueueScrollUpdate()
    end
    SyncAll()
    if castbarEnemyGroup.HookScript then castbarEnemyGroup:HookScript("OnShow", SyncAll) end

    -- =====================================================================
    -- Panel store for Core LoadFromDB compat
    -- =====================================================================
    panel.castbarShakeIntensitySlider = shakeSlider
end
