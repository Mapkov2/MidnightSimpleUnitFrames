-- ============================================================================
-- MSUF_CP_Layout.lua
-- Phase 7D: move Class Power layout helper out of MSUF_ClassPower.lua with
-- minimal risk. Only CP_Layout lives here.
-- ============================================================================

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

        local h = height
        local b = _cpDB.bars or {}

        local tickW = tonumber(b.classPowerTickWidth) or 1
        if tickW < 0 then tickW = 0 elseif tickW > 4 then tickW = 4 end

        local widthMode = b.classPowerWidthMode or "player"
        local userW

        local cdmName = CPConst.CDM_FRAMES[widthMode]
        if cdmName then
            local cdmFrame = _G[cdmName]
            if cdmFrame and cdmFrame.IsShown and cdmFrame:IsShown() then
                local cdmWidthFn = (type(GetCDMScaledWidth) == "function" and GetCDMScaledWidth()) or _G.MSUF_CDM_GetScaledWidth
                if type(cdmWidthFn) == "function" then
                    userW = cdmWidthFn(cdmFrame, CP.container)
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

        CP.container:ClearAllPoints()
        CP.container:SetSize(userW, h)
        if b.classPowerAnchorToCooldown == true then
            local ecv = _G["EssentialCooldownViewer"]
            if ecv and ecv.IsShown and ecv:IsShown() then
                CP.container:SetPoint("TOP", ecv, "BOTTOM", oX, oY)
            else
                CP.container:SetPoint("TOPLEFT", playerFrame, "TOPLEFT", 2 + oX, -(2 - oY))
            end
        else
            CP.container:SetPoint("TOPLEFT", playerFrame, "TOPLEFT", 2 + oX, -(2 - oY))
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
                ol:SetFrameLevel(CP.container:GetFrameLevel() + 1)
                CP._outline = ol
                CP._outlineEdge = -1
            end
            if CP._outlineEdge ~= edge then
                CP._outline:SetBackdrop({ edgeFile = "Interface\Buttons\WHITE8x8", edgeSize = edge })
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
                conf.detachedPowerBarWidth = math_floor(userW + 0.5)
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
                _G.MSUF_ApplyPowerBarEmbedLayout(pf)
            end
        end
    end

    return {
        CP_Layout = CP_Layout,
    }
end
