-- Phase 7 CP split: layout/texture helpers for class power core
_G.MSUF_CP_CORE_BUILDERS = _G.MSUF_CP_CORE_BUILDERS or {}

_G.MSUF_CP_CORE_BUILDERS.LAYOUT = function(env)
    local CP = env.CP
    local _cpDB = env._cpDB
    local CPConst = env.CPConst
    local CreateFrame = env.CreateFrame
    local math_floor = env.math_floor or math.floor
    local tonumber = env.tonumber or tonumber
    local CP_ResolveTexture = env.CP_ResolveTexture
    local CP_ApplyRuneSortOrder = env.CP_ApplyRuneSortOrder
    local CP_CheckAutoHide = env.CP_CheckAutoHide
    local RunUpdate = env.RunUpdate

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
                userW = CDM_GetScaledWidth(cdmFrame, CP.container)
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
                ol:SetPoint("TOPLEFT", CP.container, "TOPLEFT", -edge, edge)
                ol:SetPoint("BOTTOMRIGHT", CP.container, "BOTTOMRIGHT", edge, -edge)
                ol:SetBackdrop({ edgeFile = "Interface\Buttons\WHITE8x8", edgeSize = edge })
                ol:SetBackdropBorderColor(0, 0, 0, 1)
                CP._outline = ol
            else
                CP._outline:ClearAllPoints()
                CP._outline:SetPoint("TOPLEFT", CP.container, "TOPLEFT", -edge, edge)
                CP._outline:SetPoint("BOTTOMRIGHT", CP.container, "BOTTOMRIGHT", edge, -edge)
                CP._outline:SetBackdrop({ edgeFile = "Interface\Buttons\WHITE8x8", edgeSize = edge })
                CP._outline:SetBackdropBorderColor(0, 0, 0, 1)
                CP._outline:Show()
            end
        elseif CP._outline then
            CP._outline:Hide()
        end
        local gap = tonumber(b.classPowerGap) or 0
        if gap < 0 then gap = 0 elseif gap > 8 then gap = 8 end
        local reverse = (b.classPowerFillReverse == true)
        CP_ApplyRuneSortOrder(b.runeSortOrder)
        local totalTicks = (maxPower > 1 and tickW > 0) and ((maxPower - 1) * tickW) or 0
        local totalGaps  = (maxPower > 1 and gap > 0) and ((maxPower - 1) * gap) or 0
        local segW = (userW - totalTicks - totalGaps) / maxPower
        if segW < 1 then segW = 1 end
        for i = 1, CP.maxBars do
            local bar = CP.bars[i]
            if bar then
                if i <= maxPower then
                    bar:ClearAllPoints()
                    bar:SetHeight(h)
                    bar:SetWidth(segW)
                    local logicalIndex = reverse and (maxPower - i + 1) or i
                    if logicalIndex == 1 then
                        if reverse then bar:SetPoint("RIGHT", CP.container, "RIGHT", 0, 0) else bar:SetPoint("LEFT", CP.container, "LEFT", 0, 0) end
                    else
                        local prevLogical = logicalIndex - 1
                        local prevVisual = reverse and (maxPower - prevLogical + 1) or prevLogical
                        local prev = CP.bars[prevVisual]
                        if reverse then bar:SetPoint("RIGHT", prev, "LEFT", -(gap + tickW), 0) else bar:SetPoint("LEFT", prev, "RIGHT", gap + tickW, 0) end
                    end
                    bar:Show()
                else
                    bar:Hide()
                    if bar._runeText then bar._runeText:Hide() end
                end
            end
        end
        for i = 1, CP.maxBars - 1 do
            local tick = CP.ticks[i]
            if tick then
                if i < maxPower and tickW > 0 then
                    local leftLogical = reverse and (maxPower - i + 1) or i
                    local leftVisual  = reverse and (maxPower - leftLogical + 1) or leftLogical
                    local leftBar = CP.bars[leftVisual]
                    if leftBar then
                        tick:ClearAllPoints()
                        if reverse then
                            tick:SetPoint("TOPRIGHT", leftBar, "TOPLEFT", -gap, 0)
                            tick:SetPoint("BOTTOMRIGHT", leftBar, "BOTTOMLEFT", -gap, 0)
                        else
                            tick:SetPoint("TOPLEFT", leftBar, "TOPRIGHT", gap, 0)
                            tick:SetPoint("BOTTOMLEFT", leftBar, "BOTTOMRIGHT", gap, 0)
                        end
                        tick:SetWidth(tickW)
                        tick:Show()
                    else
                        tick:Hide()
                    end
                else
                    tick:Hide()
                end
            end
        end
        if CP.bgTex then CP.bgTex:SetVertexColor(0, 0, 0, _cpDB.bgAlpha or 0.3) end
        local curVal, maxVal
        if CP.powerType == "EBON_MIGHT" then
            curVal, maxVal = 1, 1
        else
            curVal = UnitPower("player", CP.powerType) or 0
            maxVal = maxPower
        end
        CP_CheckAutoHide(curVal, maxVal)
    end

    local function CP_ApplyColors(powerType)
        RunUpdate(powerType, CP.currentMax)
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
        CP_Layout = CP_Layout,
        CP_ApplyColors = CP_ApplyColors,
        CP_RefreshTexture = CP_RefreshTexture,
    }
end
