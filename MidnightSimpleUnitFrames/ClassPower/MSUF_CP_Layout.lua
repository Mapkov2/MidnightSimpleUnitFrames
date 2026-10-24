local _, MSUF = ...
local shared = MSUF.CPFactoryShared.Core
local builders = shared.builders
local GetProfileScopedCache = shared.GetProfileScopedCache
local GetEffectiveCooldownFrame = shared.GetEffectiveCooldownFrame
local CacheScreenPosition = shared.CacheScreenPosition
local ApplyCachedScreenPosition = shared.ApplyCachedScreenPosition
local RequestUFReanchorAfterCombat = shared.RequestUFReanchorAfterCombat
local tonumber = shared.tonumber
local math_floor = shared.math_floor
local CP_ResolveTextLayerLevel = shared.CP_ResolveTextLayerLevel
local CP_NormalizeShape = shared.CP_NormalizeShape
local CP_ShapeTextures = shared.CP_ShapeTextures
local type = shared.type
local IS_CLASSIC = shared.IS_CLASSIC
local CP_IsUsableCooldownAnchorFrame = shared.CP_IsUsableCooldownAnchorFrame
local CP_AboveCooldownGap = shared.CP_AboveCooldownGap
local CP_CooldownAnchorStacksAbove = shared.CP_CooldownAnchorStacksAbove
local PixelLayoutRegion = shared.PixelLayoutRegion
local CP_NormalizeShapeAlign = shared.CP_NormalizeShapeAlign
local CP_UseNativeShapeFill = shared.CP_UseNativeShapeFill
local CP_LayoutBackground = shared.CP_LayoutBackground
local ClearShapeEdge = shared.ClearShapeEdge
local CP_LayoutShown = shared.CP_LayoutShown
local CoreUnitFrame = shared.CoreUnitFrame
local ApplyPowerBarEmbedLayout = shared.ApplyPowerBarEmbedLayout
local CP_ApplyRoundedSurface = shared.CP_ApplyRoundedSurface
local CP_LevelOffset = shared.CP_LevelOffset
local Snap = MSUF.Require("MSUF_Snap", "ClassPower/MSUF_CP_Layout.lua")

builders.LAYOUT = function(E)
    local ApplyRoundedSurface = E.ApplyRoundedSurface or CP_ApplyRoundedSurface
    local CoreUnitFrame = E.CoreUnitFrame or CoreUnitFrame
    local CP_AboveCooldownGap = E.AboveCooldownGap or CP_AboveCooldownGap
    local GetProfileScopedCache = E.GetProfileScopedCache or GetProfileScopedCache
    local GetEffectiveCooldownFrame = E.GetCooldownFrame or GetEffectiveCooldownFrame
    local CacheScreenPosition = E.CacheScreenPosition or CacheScreenPosition
    local ApplyCachedScreenPosition = E.ApplyCachedScreenPosition or ApplyCachedScreenPosition
    local CreateFrame = E.CreateFrame or CreateFrame
    --- Bound once by LAYOUT at controller load: the shared state, the cached
    --- config and presentation collaborators.
    local CP, _cpDB, CPConst
    local ResolveClassPowerBgColor

    --- CP_Layout runs as a fixed sequence of named stages. They share one
    --- pass-state table that is allocated once here, so a layout pass adds no
    --- allocation of its own. The stages run in the order the former inline
    --- body had, and each one reads exactly the values its section read.
    local Layout = {}
    local pass = {}

    --- Stage 1: combat / hard-lock gate. Returns false when the geometry has
    --- to be replayed after combat; CP_Layout then stops before any write.
    function Layout.Gate(playerFrame, maxPower, height, powerType)
        pass.playerFrame = playerFrame
        pass.maxPower = maxPower
        pass.h = height
        pass.powerType = powerType

        local inLockdown = (InCombatLockdown and InCombatLockdown()) or false
        pass.inLockdown = inLockdown
        if CP.container._msufLayoutInitialized == true
            and inLockdown and CP.container.IsProtected and CP.container:IsProtected()
        then
            --- The container is a plain child frame: insecure SetPoint/SetSize
            --- on it is legal during combat lockdown (protection propagates to
            --- parents/anchor targets of protected frames, never to plain
            --- children). Only defer when something promoted the container
            --- into the protected anchor family; then the post-combat pass
            --- replays the geometry.
            CP._layoutDirty = true
            RequestUFReanchorAfterCombat()
            return false
        end
        return true
    end

    --- Stage 2: profile snapshot, container/text frame levels, and the
    --- separator width, pixel snapper and pip shape every later stage shares.
    function Layout.Prepare()
        local playerFrame, powerType = pass.playerFrame, pass.powerType
        local b = _cpDB.bars or {}
        pass.b = b
        pass.layoutCache = GetProfileScopedCache("classPowerLayoutCache") or nil
        local levelOffset = CP_LevelOffset(b.classPowerFrameLevelOffset, 5)
        if playerFrame.GetFrameLevel and CP.container.SetFrameLevel then
            local layers = MSUF.UF and MSUF.UF.Layers
            local targetLevel = layers and layers.ElementLevel and layers.ElementLevel(levelOffset, 5, 0)
                or ((playerFrame:GetFrameLevel() or 0) + levelOffset)
            if CP.container._msufFrameLevelStamp ~= targetLevel then
                CP.container:SetFrameLevel(targetLevel)
                CP.container._msufFrameLevelStamp = targetLevel
            end
        end
        if CP.textFrame and CP.textFrame.SetFrameLevel then
            local textLevel = CP_ResolveTextLayerLevel(CP.container, b)
            if CP.textFrame._msufFrameLevelStamp ~= textLevel then
                CP.textFrame:SetFrameLevel(textLevel)
                CP.textFrame._msufFrameLevelStamp = textLevel
            end
            if CP.textFrame.SetFrameStrata and CP.container.GetFrameStrata then
                local textStrata = CP.container:GetFrameStrata()
                if CP.textFrame._msufFrameStrataStamp ~= textStrata then
                    CP.textFrame:SetFrameStrata(textStrata)
                    CP.textFrame._msufFrameStrataStamp = textStrata
                end
            end
        end

        local tickW = tonumber(b.classPowerTickWidth) or 1
        if tickW < 0 then tickW = 0 elseif tickW > 4 then tickW = 4 end
        pass.tickW = tickW

        pass.snap = Snap

        local shape = (powerType == "WHIRLWIND" or powerType == "SWEEPING_STRIKES")
            and "BAR" or CP_NormalizeShape(b.classPowerShape)
        local shapeInfo = CP_ShapeTextures(shape)
        pass.shapeInfo = shapeInfo
        pass.shapeMode = shapeInfo ~= nil
    end

    --- Stage 3: resolve the container width from the player frame, the
    --- explicit setting, the pip auto-fit or a cooldown frame.
    function Layout.ResolveWidth()
        local playerFrame, maxPower, h, b = pass.playerFrame, pass.maxPower, pass.h, pass.b
        local inLockdown, layoutCache, snap, shapeMode = pass.inLockdown, pass.layoutCache, pass.snap, pass.shapeMode
        local widthMode = b.classPowerWidthMode or "player"
        local userW
        local playerSpecW = (playerFrame and playerFrame.MSUFSpec and tonumber(playerFrame.MSUFSpec.width)) or 275
        local autoFitGap = tonumber(b.classPowerGap) or 0
        if autoFitGap < 0 then autoFitGap = 0 elseif autoFitGap > 8 then autoFitGap = 8 end
        local snapAutoGap = (autoFitGap > 0 and type(snap) == "function") and snap(CP.container, autoFitGap) or autoFitGap

        --- Width can follow the player frame, explicit settings, or supported
        --- cooldown frames. Cooldown widths are cached so entering combat does
        --- not force protected anchor/measurement work.
        local cdmName = CPConst.CDM_FRAMES[widthMode]
        if shapeMode and widthMode == "auto_pips" then
            local slot = tonumber(h) or 1
            if slot < 1 then slot = 1 end
            slot = snap(CP.container, slot) or slot
            if slot < 1 then slot = 1 end
            userW = (slot * maxPower) + ((maxPower - 1) * snapAutoGap)
        elseif cdmName then
            local cachedW = (layoutCache and tonumber(layoutCache["width:" .. cdmName])) or tonumber(CP.container._msufStableWidth)
            if inLockdown and cachedW and cachedW >= 30 then
                userW = cachedW
            else
                local cdmFrame = GetEffectiveCooldownFrame(cdmName) or _G[cdmName]
                local cdmWidthFn = CP.cdmScaledWidth or MSUF.Require("MSUF_CDM_GetScaledWidth", "ClassPower/MSUF_CP_Layout.lua")
                userW = cdmWidthFn(cdmFrame, CP.container)
            end
            if not userW or userW < 30 then
                userW = (playerFrame and playerFrame.GetWidth and math_floor(playerFrame:GetWidth() + 0.5)) or 0
                if userW < 30 then
                    userW = playerSpecW
                end
                userW = userW - 4
            end
        elseif widthMode == "custom" then
            userW = tonumber(b.classPowerWidth) or 0
            if userW < 30 then
                userW = (playerFrame and playerFrame.GetWidth and math_floor(playerFrame:GetWidth() + 0.5)) or 0
                if userW < 30 then
                    userW = playerSpecW
                end
                userW = userW - 4
            end
        else
            userW = (playerFrame and playerFrame.GetWidth and math_floor(playerFrame:GetWidth() + 0.5)) or 0
            if userW < 30 then
                userW = playerSpecW
            end
            if widthMode ~= "player" then userW = userW - 4 end
        end
        userW = snap(CP.container, userW)
        if not userW or userW < 1 then userW = 1 end
        pass.userW = userW
        pass.cdmName = cdmName
    end

    --- Stage 4: size and anchor the container, publish the layout-dirty
    --- state and cache the cooldown-frame width for the next combat pass.
    function Layout.Position()
        local playerFrame, h, b = pass.playerFrame, pass.h, pass.b
        local inLockdown, layoutCache, userW, cdmName = pass.inLockdown, pass.layoutCache, pass.userW, pass.cdmName
        local oX = tonumber(b.classPowerOffsetX) or 0
        local insetX = (b.classPowerWidthMode or "player") == "player" and 0 or 2
        local oY = tonumber(b.classPowerOffsetY) or 0

        --- Out of combat the container keeps a live link to the Cooldown
        --- Manager provider so it follows ArcUI/Skiron/Blizzard movement 1:1.
        --- The Factory combat-edge freeze severs that link on
        --- PLAYER_REGEN_DISABLED; during lockdown the last screen point stays
        --- frozen while internal segment/value layout continues to update.
        local positionFrozen = inLockdown
        local positionDeferred = false
        CP.container:SetSize(userW, h)
        if inLockdown and CP.container._msufPositionInitialized ~= true
            and b.classPowerAnchorToCooldown == true then
            if ApplyCachedScreenPosition(CP.container, "classpower", "classpower") then
                CP.container._msufDirectCooldownAnchor = true
                CP.container._msufHardLockPoint = IS_CLASSIC
                    and (CP.container._msufHardLockPoint or "TOP") or "BOTTOM"
                CP.container._msufPositionInitialized = true
            end
        end
        if inLockdown and CP.container._msufPositionInitialized ~= true then
            positionDeferred = true
            if CP.container._msufPositionReanchorRequested ~= true then
                CP.container._msufPositionReanchorRequested = true
                RequestUFReanchorAfterCombat()
            end
        end

        if not positionFrozen then CP.container:ClearAllPoints() end
        if b.classPowerAnchorToCooldown == true and not positionFrozen then
            local ecv = not inLockdown and (
                GetEffectiveCooldownFrame("EssentialCooldownViewer") or EssentialCooldownViewer
            ) or nil
            local anchorFrame = nil
            if CP_IsUsableCooldownAnchorFrame(ecv) then
                anchorFrame = ecv
            end
            if anchorFrame then
                --- The lock point is the container edge touching the anchor;
                --- the hard lock and the screen cache record that same edge,
                --- so a combat-edge restore keeps the bar where it was.
                local lockPoint, anchorPoint = "TOP", "BOTTOM"
                if not IS_CLASSIC then
                    lockPoint, anchorPoint = "BOTTOM", "TOP"
                    oY = CP_AboveCooldownGap(anchorFrame, CP.container, b, h)
                elseif CP_CooldownAnchorStacksAbove(anchorFrame) then
                    lockPoint, anchorPoint = "BOTTOM", "TOP"
                end
                CP.container:SetPoint(lockPoint, anchorFrame, anchorPoint, oX, oY)
                if CP.container:GetCenter() ~= nil then
                    --- The link stays live; the provider chain resolves to a
                    --- real rect, so the container renders and follows it.
                    CP.container._msufDirectCooldownAnchor = true
                    CP.container._msufHardLockPoint = lockPoint
                    CP.container._msufStableExternalAnchor = anchorFrame
                    CacheScreenPosition(CP.container, "classpower", "classpower", lockPoint)
                else
                    CP.container:ClearAllPoints()
                    CP.container:SetPoint("TOPLEFT", playerFrame, "TOPLEFT", insetX + oX, -(2 - oY))
                    CP.container._msufDirectCooldownAnchor = nil
                    CP.container._msufHardLockPoint = nil
                    CP.container._msufStableExternalAnchor = nil
                end
            else
                if ApplyCachedScreenPosition(CP.container, "classpower", "classpower") then
                    CP.container._msufDirectCooldownAnchor = true
                    CP.container._msufHardLockPoint = IS_CLASSIC
                        and (CP.container._msufHardLockPoint or "TOP") or "BOTTOM"
                else
                    CP.container:SetPoint("TOPLEFT", playerFrame, "TOPLEFT", insetX + oX, -(2 - oY))
                    CP.container._msufDirectCooldownAnchor = nil
                    CP.container._msufHardLockPoint = nil
                end
                CP.container._msufStableExternalAnchor = nil
            end
        else
            if not positionFrozen then
                CP.container:SetPoint("TOPLEFT", playerFrame, "TOPLEFT", insetX + oX, -(2 - oY))
                CP.container._msufDirectCooldownAnchor = nil
                CP.container._msufHardLockPoint = nil
                CP.container._msufStableExternalAnchor = nil
            end
        end
        if not inLockdown then
            CP.container._msufPositionInitialized = true
            CP.container._msufPositionReanchorRequested = nil
            CP.container._msufExternalAnchorFrozen = nil
        end
        CP.container._msufLayoutInitialized = true
        CP.container._msufStableWidth = userW
        CP._layoutDirty = positionDeferred and true or nil
        if not inLockdown and layoutCache and cdmName and userW and userW >= 30 then
            layoutCache["width:" .. cdmName] = math_floor(userW + 0.5)
        end
    end

    --- Stage 5: the rectangular-mode outline frame around the container.
    function Layout.Outline()
        local b, snap, shapeMode = pass.b, pass.snap, pass.shapeMode
        local outlineThick = tonumber(b.classPowerOutline) or 1
        if outlineThick < 0 then outlineThick = 0 elseif outlineThick > 4 then outlineThick = 4 end

        --- Shape mode treats each resource as an independent pip. Rectangular
        --- mode divides one row into stable segments and optional separators.
        if shapeMode then
            if CP._outline then CP._outline:Hide() end
        elseif outlineThick > 0 and CP._msufRoundedOutlineSuppressed ~= true then
            if not CP._outline then
                local tpl = (BackdropTemplateMixin and "BackdropTemplate") or nil
                local ol = PixelLayoutRegion(CreateFrame("Frame", nil, CP.container, tpl))
                ol:EnableMouse(false)
                CP._outline = ol
                CP._outlineEdge = -1
            end
            local edge = snap(CP._outline, outlineThick) or outlineThick
            if not edge or edge <= 0 then
                CP._outline:Hide()
            else
                --- Frame level above bars (bars inherit container+1, outline must be higher)
                CP._outline:SetFrameLevel(CP.container:GetFrameLevel() + 3)
                if CP._outlineEdge ~= edge then
                    PixelLayoutRegion(CP._outline, "SetBackdrop", { edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = edge })
                    CP._outline:SetBackdropColor(0, 0, 0, 0)
                    CP._outline:SetBackdropBorderColor(0, 0, 0, 1)
                    CP._outlineEdge = edge
                end
                CP._outline:ClearAllPoints()
                CP._outline:SetPoint("TOPLEFT", CP.container, "TOPLEFT", -edge, edge)
                CP._outline:SetPoint("BOTTOMRIGHT", CP.container, "BOTTOMRIGHT", edge, -edge)
                CP._outline:Show()
            end
        else
            if CP._outline then CP._outline:Hide() end
        end
    end

    --- Stage 6: segment metrics - pip gap, separator width and the bar space
    --- left once the separators are budgeted.
    function Layout.Metrics()
        local maxPower, b, snap, tickW = pass.maxPower, pass.b, pass.snap, pass.tickW
        local frameW = pass.userW
        local gap = tonumber(b.classPowerGap) or 0
        if gap < 0 then gap = 0 elseif gap > 8 then gap = 8 end
        local snapGap = gap > 0 and snap(CP.container, gap) or gap

        pass.fillReverse = (b.classPowerFillReverse == true)
        local numTicks = maxPower - 1
        local snapTickW = tickW > 0 and snap(CP.container, tickW) or tickW
        local sepW = snapTickW + snapGap
        if numTicks > 0 then
            local maxSepW = math_floor((frameW - maxPower) / numTicks)
            if maxSepW < 0 then maxSepW = 0 end
            if sepW > maxSepW then
                if snapTickW > maxSepW then
                    snapTickW = maxSepW
                    snapGap = 0
                else
                    snapGap = maxSepW - snapTickW
                end
                sepW = snapTickW + snapGap
            end
        end
        local totalSepW = numTicks * sepW
        local totalBarSpace = frameW - totalSepW
        if totalBarSpace < maxPower then totalBarSpace = maxPower end
        pass.snapGap, pass.snapTickW, pass.sepW, pass.totalBarSpace = snapGap, snapTickW, sepW, totalBarSpace
    end

    --- Stage 7: background colour, pip alpha and the auto-hide gate the
    --- value updates read.
    function Layout.Surface()
        local b, powerType, shapeMode = pass.b, pass.powerType, pass.shapeMode
        local bgA = tonumber(b.classPowerBgAlpha) or 0.3
        local bgR, bgG, bgB = ResolveClassPowerBgColor(powerType or CP.powerType)
        CP.bgTex:SetVertexColor(bgR, bgG, bgB, shapeMode and 0 or bgA)
        pass.bgA, pass.bgR, pass.bgG, pass.bgB = bgA, bgR, bgG, bgB

        local filledAlpha = tonumber(b.classPowerFilledAlpha) or 1.0
        local emptyAlpha  = tonumber(b.classPowerEmptyAlpha)  or 0.3
        if filledAlpha < 0 then filledAlpha = 0 elseif filledAlpha > 1 then filledAlpha = 1 end
        if emptyAlpha  < 0 then emptyAlpha  = 0 elseif emptyAlpha  > 1 then emptyAlpha  = 1 end
        CP.filledAlpha = filledAlpha
        CP.emptyAlpha = emptyAlpha

        CP.autoHideActive = (b.classPowerHideOOC == true)
                       or (b.classPowerHideWhenFull == true)
                       or (b.classPowerHideWhenEmpty == true)
    end

    --- Stage 8: place the pips (shape mode) or the row segments and their
    --- tick separators, then hide every bar and tick past maxPower.
    function Layout.PlaceBars()
        local maxPower, h, b = pass.maxPower, pass.h, pass.b
        local snap, shapeInfo, shapeMode, fillReverse = pass.snap, pass.shapeInfo, pass.shapeMode, pass.fillReverse
        local frameW = pass.userW
        local snapGap, snapTickW, sepW, totalBarSpace = pass.snapGap, pass.snapTickW, pass.sepW, pass.totalBarSpace
        local bgA, bgR, bgG, bgB = pass.bgA, pass.bgR, pass.bgG, pass.bgB
        if shapeMode then
            local shapeFill = shapeInfo.fill
            local shapeBg = shapeInfo.bg
            local slot = h
            if slot < 1 then slot = 1 end
            slot = snap(CP.container, slot) or slot
            if slot < 1 then slot = 1 end
            local totalGap = (maxPower - 1) * snapGap
            local maxSlot = math_floor((frameW - totalGap) / maxPower)
            if maxSlot < 1 then maxSlot = 1 end
            if slot > maxSlot then slot = maxSlot end
            local rowW = (slot * maxPower) + totalGap
            if rowW > frameW then rowW = frameW end
            local align = CP_NormalizeShapeAlign(b.classPowerShapeAlign)
            local startX
            if align == "LEFT" then
                startX = 0
            elseif align == "RIGHT" then
                startX = math_floor(frameW - rowW + 0.5)
            else
                startX = math_floor((frameW - rowW) * 0.5 + 0.5)
            end
            if startX < 0 then startX = 0 end
            local rightInset = math_floor(frameW - rowW - startX + 0.5)
            if rightInset < 0 then rightInset = 0 end
            local xPos = 0
            for i = 1, maxPower do
                local bar = CP.bars[i]
                if bar then
                    bar:ClearAllPoints()
                    if bar._msufCPTexturePath ~= shapeFill then
                        bar:SetStatusBarTexture(shapeFill)
                        bar._msufCPTexturePath = shapeFill
                    end
                    CP_UseNativeShapeFill(bar, fillReverse)
                    if bar._bg then
                        if bar._bg._msufCPTexturePath ~= shapeBg then
                            bar._bg:SetTexture(shapeBg)
                            bar._bg._msufCPTexturePath = shapeBg
                        end
                        CP_LayoutBackground(bar._bg, bgR, bgG, bgB, bgA)
                    end
                    if fillReverse then
                        bar:SetPoint("TOPRIGHT", CP.container, "TOPRIGHT", -(rightInset + xPos), 0)
                    else
                        bar:SetPoint("TOPLEFT", CP.container, "TOPLEFT", startX + xPos, 0)
                    end
                    bar:SetSize(slot, h)
                    ClearShapeEdge(bar)
                    CP_LayoutShown(bar, true)
                    xPos = xPos + slot + snapGap
                end
            end
            for i = 1, #CP.ticks do
                if CP.ticks[i] then CP_LayoutShown(CP.ticks[i], false) end
            end
        else
            local xPos = 0
            local prevBoundary = 0
            for i = 1, maxPower do
                local bar = CP.bars[i]
                if bar then
                    bar:ClearAllPoints()
                    if bar.SetReverseFill then bar:SetReverseFill(false) end
                    ClearShapeEdge(bar)
                    local boundary = math_floor((totalBarSpace * i) / maxPower)
                    local thisW = boundary - prevBoundary
                    if thisW < 1 then thisW = 1 end
                    if fillReverse then
                        bar:SetPoint("TOPRIGHT", CP.container, "TOPRIGHT", -xPos, 0)
                    else
                        bar:SetPoint("TOPLEFT", CP.container, "TOPLEFT", xPos, 0)
                    end
                    bar:SetSize(thisW, h)
                    CP_LayoutBackground(bar._bg, bgR, bgG, bgB, bgA)
                    CP_LayoutShown(bar, true)
                    if snapTickW > 0 and i < maxPower then
                        local tick = CP.ticks[i]
                        if tick then
                            local tickX = xPos + thisW + math_floor(snapGap / 2)
                            tick:ClearAllPoints()
                            if fillReverse then
                                tick:SetPoint("TOPRIGHT", CP.container, "TOPRIGHT", -tickX, 0)
                            else
                                tick:SetPoint("TOPLEFT", CP.container, "TOPLEFT", tickX, 0)
                            end
                            tick:SetSize(snapTickW, h)
                            CP_LayoutShown(tick, true)
                        end
                    end
                    xPos = xPos + thisW + sepW
                    prevBoundary = boundary
                end
            end
        end

        for i = maxPower + 1, CP.maxBars do
            if CP.bars[i] then
                ClearShapeEdge(CP.bars[i])
                CP_LayoutShown(CP.bars[i], false)
            end
        end

        if not shapeMode then
            local hideFrom = (snapTickW > 0) and maxPower or 1
            for i = hideFrom, #CP.ticks do
                if CP.ticks[i] then CP_LayoutShown(CP.ticks[i], false) end
            end
        end
        --- The rune painter recolours only when its gate opens; the pip
        --- backgrounds were just repainted, so the next rune update owns them
        --- again.
        CP._runeColorVersion = nil
    end

    --- Stage 9: publish the resolved geometry to the runtime, the Devourer
    --- notches, the rounded surface and an attached detached Power bar.
    function Layout.Finish()
        local maxPower, h, powerType, shapeMode, userW = pass.maxPower, pass.h, pass.powerType, pass.shapeMode, pass.userW
        CP.currentMax = maxPower
        CP.height = h

        --- Devourer draws its fragment separators as notches over one
        --- continuous fill, so they sit on bars[1] instead of between pips and
        --- cannot be placed by the segment loop above. Hand the geometry
        --- resolved here straight to their owner: false drops them again for
        --- every other resource and for every shape mode, both of which take
        --- the same bar over.
        local refreshFragmentNotches = CP.RefreshFragmentNotches
        if refreshFragmentNotches then
            refreshFragmentNotches((not shapeMode) and (powerType or CP.powerType) == "SOUL_FRAGMENTS")
        end

        ApplyRoundedSurface()

        --- Detached player power can anchor to ClassPower. If ClassPower's
        --- anchor dimensions changed, ask the power-bar embed layout to refresh
        --- outside combat or mark it dirty for the post-combat pass.
        local needPBRefresh = false
        local pf = CoreUnitFrame("player")
        local powerSpec = pf and pf.MSUFSpec and pf.MSUFSpec.power
        if powerSpec and powerSpec.detached == true and (powerSpec.detachedSyncClass == true or powerSpec.detachedAnchorClass == true) then
            local anchorW = math_floor(userW + 0.5)
            local anchorH = math_floor(h + 0.5)
            if CP._lastDetachedPowerAnchorW ~= anchorW or CP._lastDetachedPowerAnchorH ~= anchorH then
                CP._lastDetachedPowerAnchorW = anchorW
                CP._lastDetachedPowerAnchorH = anchorH
                needPBRefresh = true
            end
        end
        if needPBRefresh then
            if pf and pf.targetPowerBar then
                local sc = pf._msufStampCache
                if sc then sc["PBEmbedLayout"] = nil end
                --- The detached power bar is an insecure child StatusBar; the
                --- element pipeline applies combat-safe elements immediately
                --- and queues anything secure for the regen driver itself.
                ApplyPowerBarEmbedLayout(pf)
            end
        end
    end

    --- Applies size, anchor, segment placement, tick separators, and outline.
    --- This is warm-path code: it can run often during option changes, but it
    --- must not be called for every power value update.
    local function CP_Layout(playerFrame, maxPower, height, powerType)
        if not CP.container or maxPower <= 0 then return end
        if not Layout.Gate(playerFrame, maxPower, height, powerType) then return end
        Layout.Prepare()
        Layout.ResolveWidth()
        Layout.Position()
        Layout.Outline()
        Layout.Metrics()
        Layout.Surface()
        Layout.PlaceBars()
        Layout.Finish()
    end

    local API = {
        CP_Layout = CP_Layout,
        MeasureWidth = function(frame, count, height, power)
            Layout.Gate(frame, count, height, power)
            Layout.Prepare()
            Layout.ResolveWidth()
            return pass.userW
        end,
    }

        CP, _cpDB, CPConst = E.CP, E._cpDB, E.CPConst
        ResolveClassPowerBgColor = E.ResolveClassPowerBgColor
    return API
end
