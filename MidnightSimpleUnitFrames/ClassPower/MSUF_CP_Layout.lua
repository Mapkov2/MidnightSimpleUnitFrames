local _, MSUF = ...
local shared = MSUF.CPFactoryShared.Core
local builders = shared.builders
local GetProfileScopedCache = shared.GetProfileScopedCache
local GetEffectiveCooldownFrame = shared.GetEffectiveCooldownFrame
local CacheScreenPosition = shared.CacheScreenPosition
local ApplyCachedScreenPosition = shared.ApplyCachedScreenPosition
local RequestUFReanchorAfterCombat = shared.RequestUFReanchorAfterCombat
local tonumber = shared.tonumber
local math_floor, math_max = shared.math_floor, shared.math_max
local math_min = math.min
local NotSecret = MSUF.Secrets.NotSecret
local CP_ResolveTextLayerLevel = shared.CP_ResolveTextLayerLevel
local CP_NormalizeShape = shared.CP_NormalizeShape
local CP_ShapeTextures = shared.CP_ShapeTextures
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
local PixelSize = MSUF.Require("MSUF_GetPhysicalPixelSize", "ClassPower/MSUF_CP_Layout.lua")
local GetCooldownAnchorScaledWidth = MSUF.Require("MSUF_GetCooldownAnchorScaledWidth", "ClassPower/MSUF_CP_Layout.lua")

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
    --- pixel grid, divider widths and pip shape every later stage shares.
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
                if CP.druidVisual then CP.druidVisual:SetFrameLevel(targetLevel) end
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

        local pixel = PixelSize(CP.container, 1)
        local gap = math_min(8, math_max(0, tonumber(b.classPowerGap) or 0))
        local tick = math_min(4, math_max(0, tonumber(b.classPowerTickWidth) or 1))
        pass.pixel = pixel
        pass.gapPixels = math_floor(gap / pixel + 0.5)
        pass.tickPixels = math_floor(tick / pixel + 0.5)

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
        local inLockdown, layoutCache, pixel = pass.inLockdown, pass.layoutCache, pass.pixel
        local widthMode = b.classPowerWidthMode or "player"
        local cdmName = CPConst.CDM_FRAMES[widthMode]
        local widthPixels
        pass.cdmWidthMeasured = false
        if pass.shapeMode and widthMode == "auto_pips" then
            local slot = math_max(1, math_floor(h / pixel + 0.5))
            widthPixels = slot * maxPower + (maxPower - 1) * pass.gapPixels
        else
            local userW
            --- Keep the measured width in layout units until converting once
            --- to pixels. During combat the cached cooldown width is reused.
            if cdmName then
                local cachedW = (layoutCache and tonumber(layoutCache["width:" .. cdmName])) or tonumber(CP.container._msufStableWidth)
                if inLockdown and cachedW and cachedW > 0 then
                    userW = cachedW
                else
                    local cdmFrame = GetEffectiveCooldownFrame(cdmName) or _G[cdmName]
                    local measured = GetCooldownAnchorScaledWidth(cdmFrame, CP.container)
                    -- Keep the previous eligibility cutoff for rounded CDM widths.
                    if measured and measured >= 29.5 then
                        userW = measured
                        pass.cdmWidthMeasured = true
                    end
                end
            elseif widthMode == "custom" then
                local custom = tonumber(b.classPowerWidth)
                if custom and custom >= 30 then userW = custom end
            end
            if not userW then
                userW = playerFrame.GetWidth and playerFrame:GetWidth()
                if not NotSecret(userW) or type(userW) ~= "number" or userW < 29.5 then
                    userW = (playerFrame.MSUFSpec and tonumber(playerFrame.MSUFSpec.width)) or 275
                end
                if widthMode ~= "player" then userW = userW - 4 end
            end
            widthPixels = math_max(maxPower, math_floor(userW / pixel + 0.5))
        end
        pass.widthPixels = widthPixels
        pass.userW = widthPixels * pixel
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
        if not inLockdown and layoutCache and pass.cdmWidthMeasured then
            layoutCache["width:" .. cdmName] = userW
        end
    end

    --- Stage 5: the rectangular-mode outline frame around the container.
    function Layout.Outline()
        local b, shapeMode = pass.b, pass.shapeMode
        local outlineThick = tonumber(b.classPowerOutline) or 1
        if outlineThick < 0 then outlineThick = 0 elseif outlineThick > 4 then outlineThick = 4 end

        --- Shape mode treats each resource as an independent pip. Rectangular
        --- mode divides one row into stable segments and optional separators.
        if shapeMode then
            if CP._outline then CP._outline:Hide() end
        elseif outlineThick > 0 and CP._msufRoundedOutlineSuppressed ~= true then
            if not CP._outline then
                local tpl = (BackdropTemplateMixin and "BackdropTemplate") or nil
                local ol = PixelLayoutRegion(CreateFrame("Frame", nil, CP.druidVisual or CP.container, tpl))
                ol:EnableMouse(false)
                CP._outline = ol
                CP._outlineEdge = -1
            end
            local edge = Snap(CP._outline, outlineThick) or outlineThick
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
        local maxPower, framePixels = pass.maxPower, pass.widthPixels
        local gapPixels = pass.gapPixels
        local tickPixels = pass.shapeMode and 0 or pass.tickPixels
        local numTicks = maxPower - 1

        pass.fillReverse = pass.b.classPowerFillReverse == true
        if numTicks > 0 then
            local budget = math_floor((framePixels - maxPower) / numTicks)
            tickPixels = math_min(tickPixels, budget)
            gapPixels = math_min(gapPixels, budget - tickPixels)
        end
        local sepPixels = gapPixels + tickPixels
        pass.gapPixels, pass.tickPixels, pass.sepPixels = gapPixels, tickPixels, sepPixels
        pass.barPixels = framePixels - numTicks * sepPixels
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
        local shapeInfo, shapeMode, fillReverse = pass.shapeInfo, pass.shapeMode, pass.fillReverse
        local pixel, framePixels = pass.pixel, pass.widthPixels
        local gapPixels, tickPixels, sepPixels, barPixels = pass.gapPixels, pass.tickPixels, pass.sepPixels, pass.barPixels
        local bgA, bgR, bgG, bgB = pass.bgA, pass.bgR, pass.bgG, pass.bgB
        if shapeMode then
            local shapeFill = shapeInfo.fill
            local shapeBg = shapeInfo.bg
            local slot = math_max(1, math_floor(h / pixel + 0.5))
            slot = math_min(slot, math_floor(barPixels / maxPower))
            local spare = framePixels - (slot * maxPower + (maxPower - 1) * gapPixels)
            local align = CP_NormalizeShapeAlign(b.classPowerShapeAlign)
            local startX = 0
            if align == "RIGHT" then
                startX = spare
            elseif align ~= "LEFT" then
                startX = math_floor(spare / 2 + 0.5)
            end
            local rightInset = spare - startX
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
                        bar:SetPoint("TOPRIGHT", CP.container, "TOPRIGHT", -(rightInset + xPos) * pixel, 0)
                    else
                        bar:SetPoint("TOPLEFT", CP.container, "TOPLEFT", (startX + xPos) * pixel, 0)
                    end
                    bar:SetSize(slot * pixel, h)
                    ClearShapeEdge(bar)
                    CP_LayoutShown(bar, true)
                    xPos = xPos + slot + gapPixels
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
                    --- Distribute remainder pixels across the row, keeping every
                    --- gap identical and the final pip flush with the container.
                    local boundary = math_floor(barPixels * i / maxPower + 0.5)
                    local thisW = boundary - prevBoundary
                    if fillReverse then
                        bar:SetPoint("TOPRIGHT", CP.container, "TOPRIGHT", -xPos * pixel, 0)
                    else
                        bar:SetPoint("TOPLEFT", CP.container, "TOPLEFT", xPos * pixel, 0)
                    end
                    bar:SetSize(thisW * pixel, h)
                    CP_LayoutBackground(bar._bg, bgR, bgG, bgB, bgA)
                    CP_LayoutShown(bar, true)
                    if tickPixels > 0 and i < maxPower then
                        local tick = CP.ticks[i]
                        if tick then
                            local tickX = (xPos + thisW + math_floor(gapPixels / 2)) * pixel
                            tick:ClearAllPoints()
                            if fillReverse then
                                tick:SetPoint("TOPRIGHT", CP.container, "TOPRIGHT", -tickX, 0)
                            else
                                tick:SetPoint("TOPLEFT", CP.container, "TOPLEFT", tickX, 0)
                            end
                            tick:SetSize(tickPixels * pixel, h)
                            CP_LayoutShown(tick, true)
                        end
                    end
                    xPos = xPos + thisW + sepPixels
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
            local hideFrom = (tickPixels > 0) and maxPower or 1
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
            local anchorW = userW
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
        return true
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
