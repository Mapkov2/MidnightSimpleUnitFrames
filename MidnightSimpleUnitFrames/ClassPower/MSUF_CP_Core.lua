-- MSUF_CP_Core.lua — Build + Layout + Presentation + Runtime + Specials (consolidated)

-- MSUF_CP_Build.lua

-- MSUF_CP_Build.lua
-- Phase 7C: move Class Power build helpers out of MSUF_ClassPower.lua with
-- minimal risk. Only CP_EnsureBars and CP_Create live here.

local builders = _G.MSUF_CP_CORE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    _G.MSUF_CP_CORE_BUILDERS = builders
end

builders.BUILD = function(E)
    local CP = E.CP
    local _cpDB = E._cpDB
    local CreateFrame = E.CreateFrame
    local CP_ResolveTexture = E.CP_ResolveTexture

local function CP_EnsureBars(parent, count)
        if count <= CP.maxBars then return end

        -- Resolve textures once for all new bars
        local b = _cpDB.bars or {}
        local fgPath = CP_ResolveTexture(b.classPowerTexture)
        local bgKey  = b.classPowerBgTexture
        local bgPath
        if bgKey and bgKey ~= "" then
            local resolve = _G.MSUF_ResolveStatusbarTextureKey
            bgPath = (type(resolve) == "function" and resolve(bgKey)) or fgPath
        else
            bgPath = fgPath
        end

        for i = CP.maxBars + 1, count do
            local bar = CreateFrame("StatusBar", nil, CP.container)
            bar:SetStatusBarTexture(fgPath)
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0)
            bar:Hide()

            local bg = bar:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(bar)
            bg:SetTexture(bgPath)
            bg:SetVertexColor(0, 0, 0, 0.3)
            bar._bg = bg

            -- Per-rune cooldown time text (DK runes only; shown/hidden in CPK.MODE.RUNE_CD)
            local rfs = bar:CreateFontString(nil, "OVERLAY")
            rfs:SetPoint("CENTER", bar, "CENTER", 0, 0)
            rfs:SetJustifyH("CENTER")
            if rfs.SetJustifyV then rfs:SetJustifyV("MIDDLE") end
            rfs:SetFontObject("GameFontHighlightSmall")
            rfs:SetTextColor(1, 1, 1, 1)
            rfs:SetShadowColor(0, 0, 0, 1)
            rfs:SetShadowOffset(1, -1)
            rfs:Hide()
            bar._runeText = rfs
            bar._runeTextQ = -1

            CP.bars[i] = bar
        end

        -- Tick separators (between bars)
        for i = CP.maxBars + 1, count - 1 do
            if not CP.ticks[i] then
                local tick = CP.container:CreateTexture(nil, "OVERLAY")
                tick:SetTexture("Interface\\Buttons\\WHITE8x8")
                tick:SetVertexColor(0, 0, 0, 1)
                tick:Hide()
                CP.ticks[i] = tick
            end
        end

        CP.maxBars = count
    end

local function CP_Create(playerFrame)
        if CP.container then return end

        local c = CreateFrame("Frame", "MSUF_ClassPowerContainer", playerFrame)
        c:SetFrameLevel(playerFrame:GetFrameLevel() + 5)  -- above hpBar (Unhalted overlay approach)
        c:Hide()
        CP.container = c

        -- Background
        local bg = c:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetAllPoints(c)
        bg:SetVertexColor(0, 0, 0, 0.3)
        CP.bgTex = bg

        -- Pre-allocate common max (6 for DK, 5 for most others)
        CP_EnsureBars(playerFrame, 8)

        -- Text overlay (MRB pattern: separate Frame at elevated level so text
        -- is always above individual bar segments and tick separators)
        local tf = CreateFrame("Frame", nil, c)
        tf:SetAllPoints(c)
        tf:SetFrameLevel(c:GetFrameLevel() + 10)
        CP.textFrame = tf

        local fs = tf:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("CENTER", tf, "CENTER", 0, 0)
        fs:SetJustifyH("CENTER")
        if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
        fs:SetFontObject("GameFontHighlightSmall")
        fs:SetTextColor(1, 1, 1, 1)
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
        fs:Hide()
        CP.text = fs
    end

    return {
        CP_EnsureBars = CP_EnsureBars,
        CP_Create = CP_Create,
    }
end

-- MSUF_CP_Layout.lua

-- MSUF_CP_Layout.lua
-- Phase 7D: move Class Power layout helper out of MSUF_ClassPower.lua with
-- minimal risk. Only CP_Layout lives here.

local builders = _G.MSUF_CP_CORE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    _G.MSUF_CP_CORE_BUILDERS = builders
end

builders.LAYOUT = function(E)
    local CP = E.CP
    local _cpDB = E._cpDB
    local CPConst = E.CPConst
    local math_floor = E.math_floor or math.floor
    local tonumber = E.tonumber or tonumber
    local CreateFrame = E.CreateFrame or CreateFrame
    local ResolveClassPowerBgColor = E.ResolveClassPowerBgColor
    local GetCDMScaledWidth = E.GetCDMScaledWidth
    local SetFilledAlpha = E.SetFilledAlpha
    local SetEmptyAlpha = E.SetEmptyAlpha
    local SetAutoHideActive = E.SetAutoHideActive

    local function CP_Layout(playerFrame, maxPower, height)
        if not CP.container or maxPower <= 0 then return end

        local inLockdown = (type(_G.MSUF_IsUnitFramePositionLocked) == "function" and _G.MSUF_IsUnitFramePositionLocked())
            or (InCombatLockdown and InCombatLockdown())
            or false
        if inLockdown and CP.container._msufLayoutInitialized == true then
            CP._layoutDirty = true
            _G.MSUF_ClassPowerLayoutDirty = true
            if type(_G.MSUF_RequestUnitFrameReanchorAfterCombat) == "function" then
                _G.MSUF_RequestUnitFrameReanchorAfterCombat()
            end
            return
        end

        local h = height
        local b = _cpDB.bars or {}
        local layoutCache = type(_G.MSUF_GetProfileScopedCache) == "function" and _G.MSUF_GetProfileScopedCache("classPowerLayoutCache") or nil

        local tickW = tonumber(b.classPowerTickWidth) or 1
        if tickW < 0 then tickW = 0 elseif tickW > 4 then tickW = 4 end

        local widthMode = b.classPowerWidthMode or "player"
        local userW

        local cdmName = CPConst.CDM_FRAMES[widthMode]
        if cdmName then
            local cachedW = (layoutCache and tonumber(layoutCache["width:" .. cdmName])) or tonumber(CP.container._msufStableWidth)
            if inLockdown and cachedW and cachedW >= 30 then
                userW = cachedW
            else
                local cdmFrame = (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame(cdmName)) or _G[cdmName]
                if cdmFrame and cdmFrame.IsShown and cdmFrame:IsShown() then
                    local cdmWidthFn = (type(GetCDMScaledWidth) == "function" and GetCDMScaledWidth()) or _G.MSUF_CDM_GetScaledWidth
                    if type(cdmWidthFn) == "function" then
                        userW = cdmWidthFn(cdmFrame, CP.container)
                    end
                end
            end
            if not userW or userW < 30 then
                userW = (playerFrame and playerFrame.GetWidth and math_floor(playerFrame:GetWidth() + 0.5)) or 0
                if userW < 30 then
                    local playerConf = MSUF_DB and MSUF_DB.player
                    userW = ((playerConf and tonumber(playerConf.width)) or 275)
                end
                userW = userW - 4
            end
        elseif widthMode == "custom" then
            userW = tonumber(b.classPowerWidth) or 0
            if userW < 30 then
                userW = (playerFrame and playerFrame.GetWidth and math_floor(playerFrame:GetWidth() + 0.5)) or 0
                if userW < 30 then
                    local playerConf = MSUF_DB and MSUF_DB.player
                    userW = ((playerConf and tonumber(playerConf.width)) or 275)
                end
                userW = userW - 4
            end
        else
            userW = (playerFrame and playerFrame.GetWidth and math_floor(playerFrame:GetWidth() + 0.5)) or 0
            if userW < 30 then
                local playerConf = MSUF_DB and MSUF_DB.player
                userW = ((playerConf and tonumber(playerConf.width)) or 275)
            end
            userW = userW - 4
        end

        local oX = tonumber(b.classPowerOffsetX) or 0
        local oY = tonumber(b.classPowerOffsetY) or 0

        local cachedCooldownAnchor = false
        if inLockdown and b.classPowerAnchorToCooldown == true then
            CP.container:SetSize(userW, h)
            if type(_G.MSUF_ApplyCachedUnitFrameScreenPosition) == "function"
                and _G.MSUF_ApplyCachedUnitFrameScreenPosition(CP.container, "classpower", "classpower")
            then
                CP.container._msufDirectCooldownAnchor = true
                CP.container._msufHardLockPoint = CP.container._msufHardLockPoint or "TOP"
                cachedCooldownAnchor = true
            else
                CP._layoutDirty = true
                _G.MSUF_ClassPowerLayoutDirty = true
                if type(_G.MSUF_RequestUnitFrameReanchorAfterCombat) == "function" then
                    _G.MSUF_RequestUnitFrameReanchorAfterCombat()
                end
                return
            end
        end

        if not cachedCooldownAnchor then
            CP.container:ClearAllPoints()
            CP.container:SetSize(userW, h)
        end
        if b.classPowerAnchorToCooldown == true and not cachedCooldownAnchor then
            local ecv = (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame("EssentialCooldownViewer")) or _G["EssentialCooldownViewer"]
            local anchorFrame = nil
            if ecv and ecv.IsShown and ecv:IsShown() then
                if not anchorFrame and not inLockdown then
                    anchorFrame = ecv
                end
            end
            if anchorFrame then
                CP.container:SetPoint("TOP", anchorFrame, "BOTTOM", oX, oY)
                CP.container._msufDirectCooldownAnchor = true
                CP.container._msufHardLockPoint = "TOP"
                if type(_G.MSUF_CacheUnitFrameScreenPosition) == "function" then
                    _G.MSUF_CacheUnitFrameScreenPosition(CP.container, "classpower", "classpower", "TOP")
                end
            else
                if inLockdown and type(_G.MSUF_RequestUnitFrameReanchorAfterCombat) == "function" then
                    _G.MSUF_RequestUnitFrameReanchorAfterCombat()
                elseif type(_G.MSUF_ScheduleLateAnchorReanchor) == "function" then
                    _G.MSUF_ScheduleLateAnchorReanchor()
                end
                CP.container:SetPoint("TOPLEFT", playerFrame, "TOPLEFT", 2 + oX, -(2 - oY))
                CP.container._msufDirectCooldownAnchor = nil
                CP.container._msufHardLockPoint = nil
            end
        else
            CP.container:SetPoint("TOPLEFT", playerFrame, "TOPLEFT", 2 + oX, -(2 - oY))
            CP.container._msufDirectCooldownAnchor = nil
            CP.container._msufHardLockPoint = nil
        end
        CP.container._msufLayoutInitialized = true
        CP.container._msufStableWidth = userW
        CP._layoutDirty = nil
        _G.MSUF_ClassPowerLayoutDirty = nil
        if not inLockdown and layoutCache and cdmName and userW and userW >= 30 then
            layoutCache["width:" .. cdmName] = math_floor(userW + 0.5)
        end

        local outlineThick = tonumber(b.classPowerOutline) or 1
        if outlineThick < 0 then outlineThick = 0 elseif outlineThick > 4 then outlineThick = 4 end
        local snap = _G.MSUF_Snap

        if outlineThick > 0 then
            local edge = (type(snap) == "function") and snap(CP.container, outlineThick) or outlineThick
            if not CP._outline then
                local tpl = (BackdropTemplateMixin and "BackdropTemplate") or nil
                local ol = CreateFrame("Frame", nil, CP.container, tpl)
                ol:EnableMouse(false)
                CP._outline = ol
                CP._outlineEdge = -1
            end
            -- Frame level above bars (bars inherit container+1, outline must be higher)
            CP._outline:SetFrameLevel(CP.container:GetFrameLevel() + 3)
            if CP._outlineEdge ~= edge then
                CP._outline:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = edge })
                CP._outline:SetBackdropColor(0, 0, 0, 0)
                CP._outline:SetBackdropBorderColor(0, 0, 0, 1)
                CP._outlineEdge = edge
            end
            CP._outline:ClearAllPoints()
            CP._outline:SetPoint("TOPLEFT", CP.container, "TOPLEFT", -edge, edge)
            CP._outline:SetPoint("BOTTOMRIGHT", CP.container, "BOTTOMRIGHT", edge, -edge)
            CP._outline:Show()
        else
            if CP._outline then CP._outline:Hide() end
        end

        local frameW = userW
        local gap = tonumber(b.classPowerGap) or 0
        if gap < 0 then gap = 0 elseif gap > 8 then gap = 8 end
        local snapGap = (gap > 0 and type(snap) == "function") and snap(CP.container, gap) or gap

        local fillReverse = (b.classPowerFillReverse == true)
        local numTicks = maxPower - 1
        local snapTickW = (tickW > 0 and type(snap) == "function") and snap(CP.container, tickW) or tickW
        local totalSepW = numTicks * (snapTickW + snapGap)
        local totalBarSpace = frameW - totalSepW
        local barW = math_floor(totalBarSpace / maxPower)

        local bgA = tonumber(b.classPowerBgAlpha) or 0.3
        local bgR, bgG, bgB = ResolveClassPowerBgColor(powerType)
        CP.bgTex:SetVertexColor(bgR, bgG, bgB, bgA)

        local filledAlpha = tonumber(b.classPowerFilledAlpha) or 1.0
        local emptyAlpha  = tonumber(b.classPowerEmptyAlpha)  or 0.3
        if filledAlpha < 0 then filledAlpha = 0 elseif filledAlpha > 1 then filledAlpha = 1 end
        if emptyAlpha  < 0 then emptyAlpha  = 0 elseif emptyAlpha  > 1 then emptyAlpha  = 1 end
        SetFilledAlpha(filledAlpha)
        SetEmptyAlpha(emptyAlpha)

        SetAutoHideActive((b.classPowerHideOOC == true)
                       or (b.classPowerHideWhenFull == true)
                       or (b.classPowerHideWhenEmpty == true))

        local xPos = 0
        for i = 1, maxPower do
            local bar = CP.bars[i]
            if bar then
                bar:ClearAllPoints()
                local thisW = (i == maxPower) and (frameW - xPos) or barW
                if fillReverse then
                    bar:SetPoint("TOPRIGHT", CP.container, "TOPRIGHT", -xPos, 0)
                else
                    bar:SetPoint("TOPLEFT", CP.container, "TOPLEFT", xPos, 0)
                end
                bar:SetSize(thisW, h)
                bar._bg:SetVertexColor(bgR, bgG, bgB, bgA)
                bar:Show()
                xPos = xPos + thisW + snapTickW + snapGap
            end
        end

        for i = maxPower + 1, CP.maxBars do
            if CP.bars[i] then CP.bars[i]:Hide() end
        end

        if snapTickW > 0 then
            local tickX = barW + math_floor(snapGap / 2)
            local tickStride = barW + snapTickW + snapGap
            for i = 1, numTicks do
                local tick = CP.ticks[i]
                if tick then
                    tick:ClearAllPoints()
                    if fillReverse then
                        tick:SetPoint("TOPRIGHT", CP.container, "TOPRIGHT", -(tickX), 0)
                    else
                        tick:SetPoint("TOPLEFT", CP.container, "TOPLEFT", tickX, 0)
                    end
                    tick:SetSize(snapTickW, h)
                    tick:Show()
                end
                tickX = tickX + tickStride
            end
        end
        local hideFrom = (snapTickW > 0) and maxPower or 1
        for i = hideFrom, #CP.ticks do
            if CP.ticks[i] then CP.ticks[i]:Hide() end
        end

        CP.currentMax = maxPower
        CP.height = h

        local conf = MSUF_DB and MSUF_DB.player
        local needPBRefresh = false
        if conf and conf.powerBarDetached == true then
            if conf.detachedPowerBarSyncClassPower == true then
                if not inLockdown then
                    conf.detachedPowerBarWidth = math_floor(userW + 0.5)
                end
                needPBRefresh = true
            end
            if conf.detachedPowerBarAnchorToClassPower == true then
                needPBRefresh = true
            end
        end
        if needPBRefresh and type(_G.MSUF_ApplyPowerBarEmbedLayout) == "function" then
            local uf = _G.MSUF_UnitFrames
            local pf = uf and uf.player
            if pf and pf.targetPowerBar then
                local sc = pf._msufStampCache
                if sc then sc["PBEmbedLayout"] = nil end
                if inLockdown then
                    pf._msufPowerBarLayoutDirty = true
                    _G.MSUF_PowerBarLayoutDirty = true
                    if type(_G.MSUF_RequestUnitFrameReanchorAfterCombat) == "function" then
                        _G.MSUF_RequestUnitFrameReanchorAfterCombat()
                    end
                else
                    _G.MSUF_ApplyPowerBarEmbedLayout(pf)
                end
            end
        end
    end

    return {
        CP_Layout = CP_Layout,
    }
end

-- MSUF_CP_Presentation.lua

-- MSUF_CP_Presentation.lua
-- Pure presentation helpers for Class Power (phase 7A split).
-- Intentionally low-risk: no build/layout/value-flow logic moves here.

local builders = _G.MSUF_CP_CORE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    _G.MSUF_CP_CORE_BUILDERS = builders
end

builders.PRESENTATION = function(E)
    local CP = E.CP
    local _cpDB = E._cpDB
    local PT = E.PT
    local math_floor = E.math_floor or math.floor
    local tonumber = E.tonumber or tonumber
    local ResolveClassPowerColor = E.ResolveClassPowerColor
    local CP_ResolveTexture = E.CP_ResolveTexture
    local GetUpdateFn = E.GetUpdateFn

    local _cpFontRev = 0

    local function CDM_GetScaledWidth(cdmFrame, targetFrame)
        if not cdmFrame or not cdmFrame.GetWidth then return nil end
        local w = cdmFrame:GetWidth()
        if not w or w < 1 then return nil end
        local cdmScale = (cdmFrame.GetEffectiveScale and cdmFrame:GetEffectiveScale()) or 1
        local tgtScale = (targetFrame and targetFrame.GetEffectiveScale and targetFrame:GetEffectiveScale()) or 1
        if cdmScale <= 0 then cdmScale = 1 end
        if tgtScale <= 0 then tgtScale = 1 end
        if cdmScale == tgtScale then return math_floor(w + 0.5) end
        return math_floor(w * cdmScale / tgtScale + 0.5)
    end

    local function CP_ApplyTextOffset()
        local fs = CP.text
        local tf = CP.textFrame
        if not fs or not tf then return end
        local b = _cpDB.bars
        local ox = (b and tonumber(b.classPowerTextOffsetX)) or 0
        local oy = (b and tonumber(b.classPowerTextOffsetY)) or 0
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", tf, "CENTER", ox, oy)
    end

    local function CP_ApplyFont()
        local fs = CP.text
        if not fs then return end

        local path, flags, fr, fg, fb, baseSize, useShadow
        if type(_G.MSUF_GetGlobalFontSettings) == "function" then
            path, flags, fr, fg, fb, baseSize, useShadow = _G.MSUF_GetGlobalFontSettings()
        end
        path     = path or "Fonts\\FRIZQT__.TTF"
        flags    = flags or "OUTLINE"
        fr       = fr or 1
        fg       = fg or 1
        fb       = fb or 1
        baseSize = baseSize or 14

        local fontSize = baseSize
        if _cpDB.bars then
            fontSize = _cpDB.fontSize or baseSize
        end
        if fontSize < 6 then fontSize = 6 end

        local rev = (_G.MSUF_FontPathSerial or 0) + fontSize * 1000003
        if _cpFontRev ~= rev then
            fs:SetFont(path, fontSize, flags)
            _cpFontRev = rev
        end

        local runeSize = fontSize - 2
        if runeSize < 6 then runeSize = 6 end
        for i = 1, (CP.maxBars or 0) do
            local bar = CP.bars[i]
            local rfs = bar and bar._runeText
            if rfs then
                rfs:SetFont(path, runeSize, flags)
            end
        end

        local tr, tg, tb = fr, fg, fb
        if _cpDB.general then
            local ov = _cpDB.colorOverrides
            if type(ov) == "table" then
                local c = ov["RESOURCE_TEXT"]
                if type(c) == "table" then
                    local cr = c[1] or c.r
                    local cg = c[2] or c.g
                    local cb = c[3] or c.b
                    if type(cr) == "number" and type(cg) == "number" and type(cb) == "number" then
                        tr, tg, tb = cr, cg, cb
                    end
                end
            end
        end

        fs:SetTextColor(tr, tg, tb, 1)

        if useShadow then
            fs:SetShadowColor(0, 0, 0, 1)
            fs:SetShadowOffset(1, -1)
        else
            fs:SetShadowOffset(0, 0)
        end
        CP_ApplyTextOffset()
    end

    local function CP_ApplyColors(powerType)
        local updateFn = GetUpdateFn and GetUpdateFn() or nil
        if type(updateFn) == "function" then
            updateFn(powerType, CP.currentMax)
        end
    end

    local function CP_RefreshTexture()
        local b = _cpDB.bars or {}
        local fgKey = b.classPowerTexture
        local bgKey = b.classPowerBgTexture

        local fgPath = CP_ResolveTexture(fgKey)
        local bgPath
        if bgKey and bgKey ~= "" then
            local resolve = _G.MSUF_ResolveStatusbarTextureKey
            bgPath = (type(resolve) == "function" and resolve(bgKey)) or fgPath
        else
            bgPath = fgPath
        end

        for i = 1, CP.maxBars do
            local bar = CP.bars[i]
            if bar then
                bar:SetStatusBarTexture(fgPath)
                if bar._bg then bar._bg:SetTexture(bgPath) end
            end
        end
        if CP.bgTex then CP.bgTex:SetTexture(bgPath) end
    end

    return {
        CDM_GetScaledWidth = CDM_GetScaledWidth,
        CP_ApplyTextOffset = CP_ApplyTextOffset,
        CP_ApplyFont = CP_ApplyFont,
        CP_ApplyColors = CP_ApplyColors,
        CP_RefreshTexture = CP_RefreshTexture,
    }
end

-- MSUF_CP_Runtime.lua

-- MSUF_CP_Runtime.lua — hot-path runtime/light-refresh handlers for the CP core
-- Loaded before Core/MSUF_ClassPower.lua and exposes lightweight runtime builders.
local builders = _G.MSUF_CP_FEATURE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    _G.MSUF_CP_FEATURE_BUILDERS = builders
end

builders.RUNTIME = function(env)
    local CP = env.CP
    local AM = env.AM
    local CPK = env.CPK
    local PT = env.PT
    local TIP = env.TIP
    local WW = env.WW
    local CPConst = env.CPConst
    local POWER_TYPE_TOKENS = env.POWER_TYPE_TOKENS
    local PLAYER_CLASS = env.PLAYER_CLASS
    local UnitPowerMax = env.UnitPowerMax
    local NotSecret = env.NotSecret
    local C_Spell = env.C_Spell
    local tonumber = env.tonumber
    local math_floor = env.math_floor
    local C_Timer = env.C_Timer

    local GetPlayerFrame = env.GetPlayerFrame
    local CP_EnsureBars = env.CP_EnsureBars
    local CP_Layout = env.CP_Layout
    local RefreshChargedPoints = env.RefreshChargedPoints
    local RunActiveUpdate = env.RunActiveUpdate
    local RunAuraSegmentedUpdate = env.RunAuraSegmentedUpdate
    local AM_UpdateValue = env.AM_UpdateValue
    local CP_ComputeStructuralSignature = env.CP_ComputeStructuralSignature
    local CP_RefreshEventBindings = env.CP_RefreshEventBindings
    local ThrottledFullRefresh = env.ThrottledFullRefresh
    local FullRefresh = env.FullRefresh
    local SetTimerBarOnUpdate = env.SetTimerBarOnUpdate
    local CP_SyncRuntimeOnUpdates = env.CP_SyncRuntimeOnUpdates
    local CP_ShouldUseLiteBindings = env.CP_ShouldUseLiteBindings
    local CP_UpdateValues_TimerBar = env.CP_UpdateValues_TimerBar
    local CP_UpdateValues_Stagger = env.CP_UpdateValues_Stagger
    local OnWarlockCastStart = env.OnWarlockCastStart
    local OnWarlockCastEnd = env.OnWarlockCastEnd
    local OnTipOfTheSpearSpellCast = env.OnTipOfTheSpearSpellCast
    local OnSpellTrackerReset = env.OnSpellTrackerReset

    local function GetResolvedVisibleMax()
        if not CP.visible or not CP.powerType then return CP.currentMax end
        local mode = CP.renderMode
        local powerType = CP.powerType
        local maxP = CP.currentMax or 1

        if mode == CPK.MODE.RUNE_CD then
            maxP = 6
        elseif mode == CPK.MODE.AURA_SINGLE or mode == CPK.MODE.CONTINUOUS or mode == CPK.MODE.STAGGER or mode == CPK.MODE.TIMER_BAR then
            maxP = 1
        elseif mode == CPK.MODE.AURA_SEGMENTED then
            if powerType == "MAELSTROM_WEAPON" then
                maxP = 10
                if C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications then
                    local spellMax = C_Spell.GetSpellMaxCumulativeAuraApplications(CPK.SPELL.MAELSTROM_WEAPON)
                    if type(spellMax) == "number" and spellMax > 0 then maxP = spellMax end
                end
            elseif powerType == "SOUL_FRAGMENTS_VENG" then
                maxP = 6
            elseif powerType == "WHIRLWIND" then
                maxP = WW.MAX_STACKS
            elseif powerType == "TIP_OF_THE_SPEAR" then
                maxP = TIP.MAX_STACKS
            elseif powerType == "ICICLES" then
                maxP = CPConst.ICICLES and CPConst.ICICLES.MAX_STACKS or 5
            else
                maxP = 10
            end
        elseif mode == CPK.MODE.SEGMENTED or mode == CPK.MODE.FRACTIONAL then
            maxP = UnitPowerMax("player", powerType)
            if not NotSecret(maxP) or maxP == nil then
                if powerType == PT.Runes then maxP = 6
                elseif powerType == PT.ComboPoints then maxP = 7
                else maxP = CP.currentMax or 5 end
            end
        end

        maxP = math_floor(tonumber(maxP) or 0)
        if maxP < 1 then maxP = 1 end
        if maxP > CPConst.MAX_CLASS_POWER then maxP = CPConst.MAX_CLASS_POWER end
        return maxP
    end

    local function RefreshVisibleModeLight(newMax)
        if not CP.visible or not CP.powerType then return end
        local maxP = tonumber(newMax) or tonumber(CP.currentMax) or 1
        if maxP < 1 then maxP = 1 end

        if maxP ~= CP.currentMax then
            local pf = CP._pf or GetPlayerFrame()
            if pf then
                CP_EnsureBars(pf, maxP)
                CP_Layout(pf, maxP, CP._layoutH or ((env._cpDB.bars and env._cpDB.bars.classPowerHeight) or 4))
            else
                CP.currentMax = maxP
            end
        end

        if CP.renderMode == CPK.MODE.SEGMENTED then
            RefreshChargedPoints()
        end

        RunActiveUpdate(CP.powerType, CP.currentMax)
    end

    local function OnManaUpdate(powerToken)
        if not AM.visible then return end
        if powerToken ~= nil and powerToken ~= "MANA" then return end
        AM_UpdateValue()
    end

    local function HandleMaxPowerEvent(powerToken)
        OnManaUpdate(powerToken)

        if not CP.visible or not CP.powerType then return end
        local mode = CP.renderMode
        if mode ~= CPK.MODE.SEGMENTED and mode ~= CPK.MODE.FRACTIONAL then return end

        local expectedToken = CP.powerToken or POWER_TYPE_TOKENS[CP.powerType]
        if powerToken and expectedToken and powerToken ~= expectedToken then return end

        RefreshVisibleModeLight(GetResolvedVisibleMax())
    end

    local function HandleDisplayPowerEvent()
        local newSig = CP_ComputeStructuralSignature()
        if newSig ~= CP.structuralSig then
            ThrottledFullRefresh()
            return
        end

        if AM.visible then
            AM_UpdateValue()
        end
        if CP.visible then
            RunActiveUpdate(CP.powerType, CP.currentMax)
        end
    end

    local function HandleRareStructuralEvent(useTimer)
        if CP_ShouldUseLiteBindings() then
            local newSig = CP_ComputeStructuralSignature()
            if newSig ~= CP.structuralSig then
                if useTimer and C_Timer and C_Timer.After then
                    C_Timer.After(0.1, FullRefresh)
                else
                    ThrottledFullRefresh()
                end
                return
            end

            CP_RefreshEventBindings()
            if AM.visible then
                AM_UpdateValue()
            end
            if CP.visible then
                RefreshVisibleModeLight(GetResolvedVisibleMax())
            end
            return
        end

        if useTimer and C_Timer and C_Timer.After then
            C_Timer.After(0.1, FullRefresh)
        else
            FullRefresh()
        end
    end

    local function OnPowerUpdate(powerToken)
        if not CP.visible or not CP.powerType then return end
        if CP.isAuraPower then return end
        if CP.renderMode == CPK.MODE.RUNE_CD then return end
        if CP.renderMode == CPK.MODE.TIMER_BAR then return end
        if CP.renderMode == CPK.MODE.STAGGER then return end

        local expectedToken = CP.powerToken or POWER_TYPE_TOKENS[CP.powerType]
        if powerToken and expectedToken and powerToken ~= expectedToken then return end

        RunActiveUpdate(CP.powerType, CP.currentMax)
    end

    local function OnAuraUpdate(unit)
        if CP.visible and CP.isAuraPower then
            RunActiveUpdate(CP.powerType, CP.currentMax)
        end
        if CP.visible and CP.renderMode == CPK.MODE.TIMER_BAR then
            CP.tbCachedQ = -1
            local timerActive = CP_UpdateValues_TimerBar and CP_UpdateValues_TimerBar(CP.powerType, CP.currentMax)
            CP_SyncRuntimeOnUpdates(timerActive)
        end
        if CP.visible and CP.renderMode == CPK.MODE.STAGGER then
            CP_UpdateValues_Stagger(CP.powerType, CP.currentMax)
        end
    end

    local function OnRuneUpdate(runeID, energize)
        if not CP.visible or CP.renderMode ~= CPK.MODE.RUNE_CD then return end
        if RunActiveUpdate then
            RunActiveUpdate(CP.powerType, CP.currentMax)
        elseif env.CP_UpdateValues_RuneCD then
            env.CP_UpdateValues_RuneCD(CP.powerType, CP.currentMax)
            if CP_SyncRuntimeOnUpdates then CP_SyncRuntimeOnUpdates(false) end
        end
    end

    local function OnSpellcastStart(spellID)
        if not CP.visible then return end
        if PLAYER_CLASS == "WARLOCK" and (CP.renderMode == CPK.MODE.SEGMENTED or CP.renderMode == CPK.MODE.FRACTIONAL) then
            OnWarlockCastStart(spellID)
        end
    end

    local function OnSpellcastEnd()
        if not CP.visible then return end
        if CP.wlPredDelta ~= 0 then
            OnWarlockCastEnd()
        end
    end

    return {
        GetResolvedVisibleMax = GetResolvedVisibleMax,
        RefreshVisibleModeLight = RefreshVisibleModeLight,
        OnManaUpdate = OnManaUpdate,
        HandleMaxPowerEvent = HandleMaxPowerEvent,
        HandleDisplayPowerEvent = HandleDisplayPowerEvent,
        HandleRareStructuralEvent = HandleRareStructuralEvent,
        OnPowerUpdate = OnPowerUpdate,
        OnAuraUpdate = OnAuraUpdate,
        OnRuneUpdate = OnRuneUpdate,
        OnSpellcastStart = OnSpellcastStart,
        OnSpellcastEnd = OnSpellcastEnd,
    }
end

-- MSUF_CP_Specials.lua

-- MSUF_CP_Specials.lua — class/resource special handlers for the CP core
-- Loaded before Core/MSUF_ClassPower.lua and exposes lightweight feature builders.
local builders = _G.MSUF_CP_FEATURE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    _G.MSUF_CP_FEATURE_BUILDERS = builders
end

builders.SPECIALS = function(env)
    local CP = env.CP
    local _cpDB = env._cpDB
    local CPConst = env.CPConst
    local TIP = env.TIP
    local PLAYER_CLASS = env.PLAYER_CLASS
    local GetSpec = env.GetSpec
    local GetTime = env.GetTime
    local math_min = env.math_min
    local C_SpellBook = env.C_SpellBook
    local RunActiveUpdate = env.RunActiveUpdate
    local RunAuraSegmentedUpdate = env.RunAuraSegmentedUpdate

    local function OnWarlockCastStart(spellID)
        if PLAYER_CLASS ~= "WARLOCK" then return end
        if _cpDB.showPrediction == false then return end
        local spec = GetSpec and GetSpec()
        local deltaTable = spec and CPConst.WL_SHARD_DELTAS[spec]
        local delta = deltaTable and deltaTable[spellID]
        if delta then
            CP.wlPredDelta = delta
            RunActiveUpdate()
        end
    end

    local function OnWarlockCastEnd()
        if CP.wlPredDelta == 0 then return end
        CP.wlPredDelta = 0
        RunActiveUpdate()
    end

    local function OnTipOfTheSpearSpellCast(spellID)
        local known = C_SpellBook and C_SpellBook.IsSpellKnown
        if not known then return end
        if not known(TIP.TALENT_ID) then return end
        if spellID == TIP.KILL_COMMAND then
            local gain = known(TIP.PRIMAL_SURGE) and 2 or 1
            CP.spStacks = math_min(TIP.MAX_STACKS, CP.spStacks + gain)
            CP.spExpires = GetTime() + TIP.DURATION
            CP.spCachedQ = -1
            RunAuraSegmentedUpdate()
            return
        end
        if spellID == TIP.TAKEDOWN and known(TIP.TWIN_FANG) then
            CP.spStacks = math_min(TIP.MAX_STACKS, CP.spStacks + 2)
            CP.spExpires = GetTime() + TIP.DURATION
            CP.spCachedQ = -1
            RunAuraSegmentedUpdate()
            return
        end
        if TIP.SPENDERS[spellID] and CP.spStacks > 0 then
            CP.spStacks = CP.spStacks - 1
            if CP.spStacks == 0 then CP.spExpires = nil end
            CP.spCachedQ = -1
            RunAuraSegmentedUpdate()
        end
    end

    local function OnSpellTrackerReset()
        CP.spStacks = 0
        CP.spExpires = nil
        CP.spCachedQ = -1
    end

    return {
        OnWarlockCastStart = OnWarlockCastStart,
        OnWarlockCastEnd = OnWarlockCastEnd,
        OnTipOfTheSpearSpellCast = OnTipOfTheSpearSpellCast,
        OnSpellTrackerReset = OnSpellTrackerReset,
    }
end
