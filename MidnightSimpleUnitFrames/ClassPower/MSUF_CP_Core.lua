--- ClassPower/MSUF_CP_Core.lua
--- Builder bundle for the ClassPower controller.
---
--- The controller owns events and live state; this file contributes closures for
--- build, layout, presentation, runtime routing, and class-specific prediction.
--- Keep the split intact when extending ClassPower: frame creation belongs in
--- BUILD, anchoring and sizing in LAYOUT, texture/font refresh in PRESENTATION,
--- event handlers in RUNTIME, and speculative class mechanics in SPECIALS.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local function CoreUnitFrame(unit)
    local UF = MSUF and MSUF.UF
    if UF and type(UF.GetFrame) == "function" then
        local frame = UF.GetFrame(unit)
        if frame then return frame end
    end
    local frames = UF and UF.frames
    return unit and frames and frames[unit] or nil
end

local function CP_IsUsableCooldownAnchorFrame(frame)
    if not (frame and frame.GetWidth) or frame._msufLegacyCooldownAnchor == true then return false end
    if frame.IsShown and not frame:IsShown() then return false end
    local width = frame:GetWidth()
    return type(width) == "number" and width > 0
end

local builders = _G.MSUF_CP_CORE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    ExportPublic("MSUF_CP_CORE_BUILDERS", builders)
end

--- Layout can be blocked while unit frames are protected. Queue the shared
--- unit-frame reanchor instead of attempting to move ClassPower immediately.
local function RequestUFReanchorAfterCombat()
    local MSUF = _G.MSUF_NS
    local UF = MSUF and MSUF.UF
    if UF and UF.RequestReanchorAfterCombat then
        UF.RequestReanchorAfterCombat()
    end
end

local CP_SHAPE_MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\ClassPower\\"
local CP_SHAPE_TEXTURES = {
    CIRCLE = {
        fill = CP_SHAPE_MEDIA .. "pip_circle_fill.tga",
        bg = CP_SHAPE_MEDIA .. "pip_circle_bg.tga",
        edge = CP_SHAPE_MEDIA .. "pip_circle_edge.tga",
    },
    DIAMOND = {
        fill = CP_SHAPE_MEDIA .. "pip_diamond_fill.tga",
        bg = CP_SHAPE_MEDIA .. "pip_diamond_bg.tga",
        edge = CP_SHAPE_MEDIA .. "pip_diamond_edge.tga",
    },
    HEX = {
        fill = CP_SHAPE_MEDIA .. "pip_hex_fill.tga",
        bg = CP_SHAPE_MEDIA .. "pip_hex_bg.tga",
        edge = CP_SHAPE_MEDIA .. "pip_hex_edge.tga",
    },
}

local function CP_NormalizeShape(value)
    value = tostring(value or "BAR"):upper()
    if value == "CIRCLE" or value == "DIAMOND" or value == "HEX" then return value end
    return "BAR"
end

local function CP_NormalizeShapeAlign(value)
    value = tostring(value or "CENTER"):upper()
    if value == "LEFT" or value == "RIGHT" then return value end
    return "CENTER"
end

local function CP_ShapeTextures(shape)
    return CP_SHAPE_TEXTURES[CP_NormalizeShape(shape)]
end

local function CP_UseNativeShapeFill(bar, reverse)
    if bar and bar.SetReverseFill then
        bar:SetReverseFill(reverse == true)
    end
end

local function ClearShapeEdge(bar)
    if bar and bar._shapeEdge then
        bar._shapeEdge:Hide()
    end
end

local function CP_ResolveTextLayerLevel(frame, bars)
    local textLayer = tonumber(bars and bars.classPowerTextLayer) or 5
    if textLayer < 0 then textLayer = 0 elseif textLayer > 30 then textLayer = 30 end
    textLayer = math.floor(textLayer + 0.5)
    local layers = MSUF.UF and MSUF.UF.Layers
    if layers and type(layers.TextLevel) == "function" then
        return layers.TextLevel(frame, textLayer, 5)
    end
    if layers and type(layers.ElementLevel) == "function" then
        return layers.ElementLevel(textLayer, 5, 8)
    end
    local baseLevel = frame and frame.GetFrameLevel and (frame:GetFrameLevel() or 0) or 0
    return baseLevel + 10
end

--- BUILD is the only block that creates ClassPower frames. It is cold-path code:
--- create reusable bars and text once, then let layout/runtime reuse them.
builders.BUILD = function(E)
    local CP = E.CP
    local _cpDB = E._cpDB
    local CreateFrame = E.CreateFrame
    local CP_ResolveTexture = E.CP_ResolveTexture
    local math_floor = E.math_floor or math.floor

    local function CP_EnsureTextFrame()
        if CP.textFrame then return CP.textFrame end
        local c = CP.container
        if not c then return nil end

        local tf = CreateFrame("Frame", nil, c)
        tf:SetAllPoints(c)
        local textLevel = CP_ResolveTextLayerLevel(c, _cpDB.bars)
        tf:SetFrameLevel(textLevel)
        tf._msufFrameLevelStamp = textLevel
        if tf.SetFrameStrata and c.GetFrameStrata then tf:SetFrameStrata(c:GetFrameStrata()) end
        if tf.EnableMouse then tf:EnableMouse(false) end
        CP.textFrame = tf
        return tf
    end

    local function CP_EnsureRuneText(bar)
        if not bar then return nil, false end
        if bar._runeText then return bar._runeText, false end
        local tf = CP_EnsureTextFrame()
        if not tf then return nil, false end

        local rfs = tf:CreateFontString(nil, "OVERLAY")
        rfs:SetPoint("CENTER", bar, "CENTER", 0, 0)
        rfs:SetJustifyH("CENTER")
        if rfs.SetJustifyV then rfs:SetJustifyV("MIDDLE") end
        rfs:SetFontObject("GameFontHighlightSmall")
        rfs:SetTextColor(1, 1, 1, 1)
        rfs:SetShadowColor(0, 0, 0, 1)
        rfs:SetShadowOffset(1, -1)
        rfs:Hide()
        bar._runeText = rfs
        return rfs, true
    end

    local function CP_EnsureMainText()
        if CP.text then return CP.text, false end
        local tf = CP_EnsureTextFrame()
        if not tf then return nil, false end

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
        return fs, true
    end

    local function CP_EnsureBars(parent, count)
        if count <= CP.maxBars then return end

        --- Resolve textures once for all new bars. Existing bars are refreshed
        --- by PRESENTATION so this path only pays setup cost for newly needed
        --- resource slots.
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
            bar._msufCPTexturePath = fgPath
            bar:SetMinMaxValues(0, 1)
            bar._msufCPMin, bar._msufCPMax = 0, 1
            bar:SetValue(0)
            bar._msufCPValue = 0
            bar:Hide()

            local bg = bar:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(bar)
            bg:SetTexture(bgPath)
            bg._msufCPTexturePath = bgPath
            bg:SetVertexColor(0, 0, 0, 0.3)
            bar._bg = bg

            CP.bars[i] = bar
        end

        --- Tick separators (between bars)
        for i = math.max(1, CP.maxBars), count - 1 do
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

        --- Parent to the player frame so ClassPower follows scale, strata, and
        --- secure visibility rules from the owning unit frame.
        local c = CreateFrame("Frame", "MSUF_ClassPowerContainer", playerFrame)
        c._msufOwnedAnchorRoot = true
        local b = _cpDB.bars or {}
        local levelOffset = tonumber(b.classPowerFrameLevelOffset) or 5
        if levelOffset < 0 then levelOffset = 0 elseif levelOffset > 30 then levelOffset = 30 end
        levelOffset = math_floor(levelOffset + 0.5)
        local layers = MSUF.UF and MSUF.UF.Layers
        c:SetFrameLevel(layers and layers.ElementLevel and layers.ElementLevel(levelOffset, 5, 0)
            or (playerFrame:GetFrameLevel() + levelOffset))
        c:Hide()
        CP.container = c

        --- Background
        local bg = c:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetAllPoints(c)
        bg:SetVertexColor(0, 0, 0, 0.3)
        CP.bgTex = bg

        --- Pre-allocate common max (6 for DK, 5 for most others)
        CP_EnsureBars(playerFrame, 8)

    end

    return {
        CP_EnsureBars = CP_EnsureBars,
        CP_Create = CP_Create,
        CP_EnsureRuneText = CP_EnsureRuneText,
        CP_EnsureMainText = CP_EnsureMainText,
    }
end

--- LAYOUT computes geometry and anchoring for the already-created bars.
--- The function also coordinates with detached power bars and external cooldown
--- anchors, so keep combat-deferred work here rather than in value updates.

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

    --- Applies size, anchor, segment placement, tick separators, and outline.
    --- This is warm-path code: it can run often during option changes, but it
    --- must not be called for every power value update.
    local function CP_Layout(playerFrame, maxPower, height, powerType)
        if not CP.container or maxPower <= 0 then return end

        local hardLocked = (type(_G.MSUF_IsUnitFramePositionLocked) == "function" and _G.MSUF_IsUnitFramePositionLocked())
            or false
        local inLockdown = hardLocked
            or (InCombatLockdown and InCombatLockdown())
            or false
        if CP.container._msufLayoutInitialized == true
            and (hardLocked or (inLockdown and CP.container.IsProtected and CP.container:IsProtected()))
        then
            --- The container is a plain child frame: insecure SetPoint/SetSize
            --- on it is legal during combat lockdown (protection propagates to
            --- parents/anchor targets of protected frames, never to plain
            --- children). Only defer when a hard position lock is active or
            --- something promoted the container into the protected anchor
            --- family; then the post-combat pass replays the geometry.
            CP._layoutDirty = true
            ExportPublic("MSUF_ClassPowerLayoutDirty", true)
            RequestUFReanchorAfterCombat()
            return
        end

        local h = height
        local b = _cpDB.bars or {}
        local augPowerBar = CP.augCompositeActive == true
            and playerFrame._msufAugPowerReplacementActive == true
            and playerFrame.targetPowerBar or nil
        if augPowerBar then
            h = tonumber(playerFrame._msufAugPowerReplacementEssenceHeight) or h
        end
        local layoutCache = type(_G.MSUF_GetProfileScopedCache) == "function" and _G.MSUF_GetProfileScopedCache("classPowerLayoutCache") or nil
        local levelOffset = tonumber(b.classPowerFrameLevelOffset) or 5
        if levelOffset < 0 then levelOffset = 0 elseif levelOffset > 30 then levelOffset = 30 end
        levelOffset = math_floor(levelOffset + 0.5)
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

        local snap = _G.MSUF_Snap

        local shape = CP_NormalizeShape(b.classPowerShape)
        local shapeInfo = CP_ShapeTextures(shape)
        local shapeMode = shapeInfo ~= nil
        local widthMode = b.classPowerWidthMode or "player"
        local userW
        local playerSpecW = (playerFrame and playerFrame.MSUFSpec and tonumber(playerFrame.MSUFSpec.width)) or 275
        local autoFitGap = tonumber(b.classPowerGap) or 0
        if autoFitGap < 0 then autoFitGap = 0 elseif autoFitGap > 8 then autoFitGap = 8 end
        local snapAutoGap = (autoFitGap > 0 and type(snap) == "function") and snap(CP.container, autoFitGap) or autoFitGap

        --- Width can follow the player frame, explicit settings, or supported
        --- cooldown frames. Cooldown widths are cached so entering combat does
        --- not force protected anchor/measurement work.
        local cdmName = not augPowerBar and CPConst.CDM_FRAMES[widthMode] or nil
        if augPowerBar and augPowerBar.GetWidth then
            userW = augPowerBar:GetWidth()
            if not userW or userW < 1 then
                userW = (playerFrame.GetWidth and playerFrame:GetWidth()) or playerSpecW
            end
        elseif shapeMode and widthMode == "auto_pips" then
            local slot = tonumber(h) or 1
            if slot < 1 then slot = 1 end
            if type(snap) == "function" then slot = snap(CP.container, slot) or slot end
            if slot < 1 then slot = 1 end
            userW = (slot * maxPower) + ((maxPower - 1) * snapAutoGap)
        elseif cdmName then
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
            userW = userW - 4
        end
        if not augPowerBar and type(snap) == "function" then
            userW = snap(CP.container, userW)
        end
        if not userW or userW < 1 then userW = 1 end

        local oX = tonumber(b.classPowerOffsetX) or 0
        local oY = tonumber(b.classPowerOffsetY) or 0

        --- Out of combat the container keeps a live link to the Cooldown
        --- Manager provider so it follows ArcUI/Skiron/Blizzard movement 1:1.
        --- The Factory combat-edge freeze severs that link on
        --- PLAYER_REGEN_DISABLED; during lockdown the last screen point stays
        --- frozen while internal segment/value layout continues to update.
        local positionFrozen = inLockdown
        local positionDeferred = false
        CP.container:SetSize(userW, h)
        if not augPowerBar and inLockdown and CP.container._msufPositionInitialized ~= true
            and b.classPowerAnchorToCooldown == true then
            if type(_G.MSUF_ApplyCachedUnitFrameScreenPosition) == "function"
                and _G.MSUF_ApplyCachedUnitFrameScreenPosition(CP.container, "classpower", "classpower")
            then
                CP.container._msufDirectCooldownAnchor = true
                CP.container._msufHardLockPoint = CP.container._msufHardLockPoint or "TOP"
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
        if augPowerBar and not positionFrozen then
            CP.container:SetPoint("TOPLEFT", augPowerBar, "TOPLEFT", 0, 0)
            CP.container:SetPoint("TOPRIGHT", augPowerBar, "TOPRIGHT", 0, 0)
            CP.container._msufDirectCooldownAnchor = nil
            CP.container._msufHardLockPoint = nil
            CP.container._msufStableExternalAnchor = nil
        elseif b.classPowerAnchorToCooldown == true and not positionFrozen then
            local ecv = not inLockdown and (
                (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame("EssentialCooldownViewer"))
                or _G["EssentialCooldownViewer"]
            ) or nil
            local anchorFrame = nil
            if CP_IsUsableCooldownAnchorFrame(ecv) then
                anchorFrame = ecv
            end
            if anchorFrame then
                CP.container:SetPoint("TOP", anchorFrame, "BOTTOM", oX, oY)
                if CP.container:GetCenter() ~= nil then
                    --- The link stays live; the provider chain resolves to a
                    --- real rect, so the container renders and follows it.
                    CP.container._msufDirectCooldownAnchor = true
                    CP.container._msufHardLockPoint = "TOP"
                    CP.container._msufStableExternalAnchor = anchorFrame
                    if type(_G.MSUF_CacheUnitFrameScreenPosition) == "function" then
                        _G.MSUF_CacheUnitFrameScreenPosition(CP.container, "classpower", "classpower", "TOP")
                    end
                else
                    CP.container:ClearAllPoints()
                    CP.container:SetPoint("TOPLEFT", playerFrame, "TOPLEFT", 2 + oX, -(2 - oY))
                    CP.container._msufDirectCooldownAnchor = nil
                    CP.container._msufHardLockPoint = nil
                    CP.container._msufStableExternalAnchor = nil
                end
            else
                if type(_G.MSUF_ApplyCachedUnitFrameScreenPosition) == "function"
                    and _G.MSUF_ApplyCachedUnitFrameScreenPosition(CP.container, "classpower", "classpower")
                then
                    CP.container._msufDirectCooldownAnchor = true
                    CP.container._msufHardLockPoint = CP.container._msufHardLockPoint or "TOP"
                else
                    CP.container:SetPoint("TOPLEFT", playerFrame, "TOPLEFT", 2 + oX, -(2 - oY))
                    CP.container._msufDirectCooldownAnchor = nil
                    CP.container._msufHardLockPoint = nil
                end
                CP.container._msufStableExternalAnchor = nil
            end
        else
            if not positionFrozen then
                CP.container:SetPoint("TOPLEFT", playerFrame, "TOPLEFT", 2 + oX, -(2 - oY))
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
        ExportPublic("MSUF_ClassPowerLayoutDirty", positionDeferred and true or nil)
        if not inLockdown and layoutCache and cdmName and userW and userW >= 30 then
            layoutCache["width:" .. cdmName] = math_floor(userW + 0.5)
        end

        local outlineThick = tonumber(b.classPowerOutline) or 1
        if outlineThick < 0 then outlineThick = 0 elseif outlineThick > 4 then outlineThick = 4 end

        --- Shape mode treats each resource as an independent pip. Rectangular
        --- mode divides one row into stable segments and optional separators.
        if shapeMode then
            if CP._outline then CP._outline:Hide() end
        elseif outlineThick > 0 and CP._msufRoundedOutlineSuppressed ~= true then
            if not CP._outline then
                local tpl = (BackdropTemplateMixin and "BackdropTemplate") or nil
                local ol = CreateFrame("Frame", nil, CP.container, tpl)
                ol:EnableMouse(false)
                CP._outline = ol
                CP._outlineEdge = -1
            end
            local edge = (type(snap) == "function") and snap(CP._outline, outlineThick) or outlineThick
            if not edge or edge <= 0 then
                CP._outline:Hide()
            else
                --- Frame level above bars (bars inherit container+1, outline must be higher)
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
            end
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

        local bgA = tonumber(b.classPowerBgAlpha) or 0.3
        local bgR, bgG, bgB = ResolveClassPowerBgColor(powerType or CP.powerType)
        CP.bgTex:SetVertexColor(bgR, bgG, bgB, shapeMode and 0 or bgA)

        local filledAlpha = tonumber(b.classPowerFilledAlpha) or 1.0
        local emptyAlpha  = tonumber(b.classPowerEmptyAlpha)  or 0.3
        if filledAlpha < 0 then filledAlpha = 0 elseif filledAlpha > 1 then filledAlpha = 1 end
        if emptyAlpha  < 0 then emptyAlpha  = 0 elseif emptyAlpha  > 1 then emptyAlpha  = 1 end
        SetFilledAlpha(filledAlpha)
        SetEmptyAlpha(emptyAlpha)

        SetAutoHideActive((b.classPowerHideOOC == true)
                       or (b.classPowerHideWhenFull == true)
                       or (b.classPowerHideWhenEmpty == true))

        if shapeMode then
            local shapeFill = shapeInfo.fill
            local shapeBg = shapeInfo.bg
            local slot = h
            if slot < 1 then slot = 1 end
            if type(snap) == "function" then slot = snap(CP.container, slot) or slot end
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
                        bar._bg:SetVertexColor(bgR, bgG, bgB, bgA)
                    end
                    if fillReverse then
                        bar:SetPoint("TOPRIGHT", CP.container, "TOPRIGHT", -(rightInset + xPos), 0)
                    else
                        bar:SetPoint("TOPLEFT", CP.container, "TOPLEFT", startX + xPos, 0)
                    end
                    bar:SetSize(slot, h)
                    ClearShapeEdge(bar)
                    bar:Show()
                    xPos = xPos + slot + snapGap
                end
            end
            for i = 1, #CP.ticks do
                if CP.ticks[i] then CP.ticks[i]:Hide() end
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
                    bar._bg:SetVertexColor(bgR, bgG, bgB, bgA)
                    bar:Show()
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
                            tick:Show()
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
                CP.bars[i]:Hide()
            end
        end

        if not shapeMode then
            local hideFrom = (snapTickW > 0) and maxPower or 1
            for i = hideFrom, #CP.ticks do
                if CP.ticks[i] then CP.ticks[i]:Hide() end
            end
        end

        CP.currentMax = maxPower
        CP.height = h

        local applyRounded = _G.MSUF_ClassPower_ApplyRoundedSurface
        if type(applyRounded) == "function" then applyRounded() end

        --- Detached player power can anchor to ClassPower. If ClassPower's
        --- anchor dimensions changed, ask the power-bar embed layout to refresh
        --- outside combat or mark it dirty for the post-combat pass.
        local needPBRefresh = false
        local pf = CoreUnitFrame("player") or _G.MSUF_player
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
        if needPBRefresh and type(_G.MSUF_ApplyPowerBarEmbedLayout) == "function" then
            if pf and pf.targetPowerBar then
                local sc = pf._msufStampCache
                if sc then sc["PBEmbedLayout"] = nil end
                --- The detached power bar is an insecure child StatusBar; the
                --- element pipeline applies combat-safe elements immediately
                --- and queues anything secure for the regen driver itself.
                _G.MSUF_ApplyPowerBarEmbedLayout(pf)
            end
        end
    end

    return {
        CP_Layout = CP_Layout,
    }
end

--- PRESENTATION owns visual refresh that does not change geometry or values:
--- fonts, text offsets, colors, textures, and media swaps.

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
        local b = _cpDB.bars
        local ox = (b and tonumber(b.classPowerTextOffsetX)) or 0
        local oy = (b and tonumber(b.classPowerTextOffsetY)) or 0
        local function ApplyOffset(region, anchor)
            if not (region and anchor) then return end
            if region._msufCPTextAnchor ~= anchor or region._msufCPTextOffsetX ~= ox
                or region._msufCPTextOffsetY ~= oy then
                region._msufCPTextAnchor = anchor
                region._msufCPTextOffsetX, region._msufCPTextOffsetY = ox, oy
                region:ClearAllPoints()
                region:SetPoint("CENTER", anchor, "CENTER", ox, oy)
            end
        end
        ApplyOffset(fs, tf)
        for i = 1, (CP.maxBars or 0) do
            local bar = CP.bars[i]
            ApplyOffset(bar and bar._runeText, bar)
        end
    end

    local function ApplyClassPowerTextStyle(region, r, g, b, a, useShadow, shadowAlpha, shadowX, shadowY)
        if not region then return end
        if region._msufCPTextColorR ~= r or region._msufCPTextColorG ~= g
            or region._msufCPTextColorB ~= b or region._msufCPTextColorA ~= a then
            region._msufCPTextColorR, region._msufCPTextColorG = r, g
            region._msufCPTextColorB, region._msufCPTextColorA = b, a
            region:SetTextColor(r, g, b, a)
        end
        local targetShadowAlpha = useShadow and shadowAlpha or 0
        local targetShadowX = useShadow and shadowX or 0
        local targetShadowY = useShadow and shadowY or 0
        if useShadow and region._msufCPShadowAlpha ~= targetShadowAlpha then
            region:SetShadowColor(0, 0, 0, targetShadowAlpha)
        end
        if region._msufCPShadowX ~= targetShadowX or region._msufCPShadowY ~= targetShadowY then
            region:SetShadowOffset(targetShadowX, targetShadowY)
        end
        region._msufCPShadowAlpha = targetShadowAlpha
        region._msufCPShadowX, region._msufCPShadowY = targetShadowX, targetShadowY
    end

    local function ClassPowerFontApplied(region, fontPath, size, fontFlags)
        if type(region.GetFont) ~= "function" then return true end
        local actual, actualSize, actualFlags = region:GetFont()
        if not actual then return false end
        if actualSize and math.abs((tonumber(actualSize) or 0) - size) > 0.01 then return false end
        if (actualFlags or "") ~= (fontFlags or "") then return false end
        if actual == fontPath then return true end
        if type(_G.MSUF_FontPathMatches) == "function" and _G.MSUF_FontPathMatches(fontPath, actual) == true then return true end
        if type(_G.MSUF_FontPathEquals) == "function" and _G.MSUF_FontPathEquals(fontPath, actual) == true then return true end
        return tostring(actual or ""):gsub("/", "\\"):lower() == tostring(fontPath or ""):gsub("/", "\\"):lower()
    end

    local function ApplyClassPowerFont(region, fontPath, size, fontFlags)
        if not (region and region.SetFont) then return false end
        local applyResolved = _G.MSUF_ApplyResolvedFont
        if type(applyResolved) == "function" then
            local ok, _, source = applyResolved(region, fontPath, size, fontFlags)
            return ok == true and source ~= "fallback"
        end
        local ok, applied = pcall(region.SetFont, region, fontPath, size, fontFlags)
        if ok and applied ~= false and ClassPowerFontApplied(region, fontPath, size, fontFlags) then return true end
        local fallback = _G.MSUF_ResolveSafeFontPath and _G.MSUF_ResolveSafeFontPath("Fonts\\FRIZQT__.TTF", size, fontFlags, "FRIZQT") or "Fonts\\FRIZQT__.TTF"
        pcall(region.SetFont, region, fallback, size, fontFlags)
        if type(_G.MSUF_MarkFontApplyFailed) == "function" then _G.MSUF_MarkFontApplyFailed() end
        return false
    end

    --- Font refresh is driven by global font serials and ClassPower options.
    --- Keep it stamped so profile/font changes repaint once instead of during
    --- every class-resource event.
    local function CP_ApplyFont()
        local fs = CP.text

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
        local textAlpha = 1
        local shadowAlpha, shadowX, shadowY = 1, 1, -1
        local general = _cpDB.general
        if type(general) == "table" then
            textAlpha = tonumber(general.fontTextAlpha) or 1
            if textAlpha < 0.7 then textAlpha = 0.7 elseif textAlpha > 1 then textAlpha = 1 end
            shadowAlpha, shadowX, shadowY = _G.MSUF_ResolveFontShadowMetrics(
                general.fontShadowOpacity, general.fontShadowDistance, general.fontShadowStrength)
        end

        local fontSize = baseSize
        if _cpDB.bars then
            fontSize = _cpDB.fontSize or baseSize
        end
        if fontSize < 6 then fontSize = 6 end

        local rev = (_G.MSUF_FontPathSerial or 0) + fontSize * 1000003
        local fontEpoch = tonumber(_G.MSUF_FontApplyEpoch) or 0
        if fs and (_cpFontRev ~= rev or fs._msufCPFontEpoch ~= fontEpoch) then
            ApplyClassPowerFont(fs, path, fontSize, flags)
            -- Stamp the bounded attempt, including fallback. Epoch transition
            -- owns the next retry and prevents class-resource hotpath retries.
            _cpFontRev = rev
            fs._msufCPFontEpoch = fontEpoch
        end

        local runeSize = fontSize - 2
        if runeSize < 6 then runeSize = 6 end
        for i = 1, (CP.maxBars or 0) do
            local bar = CP.bars[i]
            local rfs = bar and bar._runeText
            if rfs and (rfs._msufCPFontRev ~= rev or rfs._msufCPFontEpoch ~= fontEpoch) then
                ApplyClassPowerFont(rfs, path, runeSize, flags)
                rfs._msufCPFontRev = rev
                rfs._msufCPFontEpoch = fontEpoch
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

        ApplyClassPowerTextStyle(fs, tr, tg, tb, textAlpha, useShadow, shadowAlpha, shadowX, shadowY)
        for i = 1, (CP.maxBars or 0) do
            local bar = CP.bars[i]
            ApplyClassPowerTextStyle(bar and bar._runeText, tr, tg, tb, textAlpha,
                useShadow, shadowAlpha, shadowX, shadowY)
        end
        CP_ApplyTextOffset()
    end

    local function CP_ApplyColors(powerType)
        local updateFn = GetUpdateFn and GetUpdateFn() or nil
        if type(updateFn) == "function" then
            updateFn(powerType, CP.currentMax)
        end
    end

    --- Texture refresh is shared by bar and shape modes. Layout decides sizes;
    --- this function only replaces media and native reverse-fill state.
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
        local shapeInfo = CP_ShapeTextures(b.classPowerShape)
        local activeFgPath = (shapeInfo and shapeInfo.fill) or fgPath
        local activeBgPath = (shapeInfo and shapeInfo.bg) or bgPath

        for i = 1, CP.maxBars do
            local bar = CP.bars[i]
            if bar then
                local textureChanged = bar._msufCPTexturePath ~= activeFgPath
                if textureChanged then
                    bar:SetStatusBarTexture(activeFgPath)
                    bar._msufCPTexturePath = activeFgPath
                    if shapeInfo then
                        local reverse = (_cpDB.bars and _cpDB.bars.classPowerFillReverse) == true
                        CP_UseNativeShapeFill(bar, reverse)
                    else
                        if bar.SetReverseFill then bar:SetReverseFill(false) end
                    end
                end
                if bar._bg and bar._bg._msufCPTexturePath ~= activeBgPath then
                    bar._bg:SetTexture(activeBgPath)
                    bar._bg._msufCPTexturePath = activeBgPath
                end
                ClearShapeEdge(bar)
            end
        end
        if CP.bgTex and CP._msufCPBgTexturePath ~= activeBgPath then
            CP.bgTex:SetTexture(activeBgPath)
            CP._msufCPBgTexturePath = activeBgPath
        end
        local applyRounded = _G.MSUF_ClassPower_ApplyRoundedSurface
        if type(applyRounded) == "function" then applyRounded() end
    end

    return {
        CDM_GetScaledWidth = CDM_GetScaledWidth,
        CP_ApplyTextOffset = CP_ApplyTextOffset,
        CP_ApplyFont = CP_ApplyFont,
        CP_ApplyColors = CP_ApplyColors,
        CP_RefreshTexture = CP_RefreshTexture,
    }
end

--- RUNTIME exposes hot-path event handlers back to the controller. These
--- handlers should update values or request a throttled structural refresh; they
--- should not allocate frames or perform full option normalization.
local builders = _G.MSUF_CP_FEATURE_BUILDERS
if type(builders) ~= "table" then
    builders = {}
    ExportPublic("MSUF_CP_FEATURE_BUILDERS", builders)
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
    local CP_SyncRuntimeOnUpdates = env.CP_SyncRuntimeOnUpdates
    local CP_ShouldUseLiteBindings = env.CP_ShouldUseLiteBindings
    local CP_UpdateValues_Stagger = env.CP_UpdateValues_Stagger
    local OnWarlockCastStart = env.OnWarlockCastStart
    local OnWarlockCastEnd = env.OnWarlockCastEnd
    local OnTipOfTheSpearSpellCast = env.OnTipOfTheSpearSpellCast
    local OnSpellTrackerReset = env.OnSpellTrackerReset

    --- Resolve the visible segment count for the active render mode. This is
    --- intentionally separate from layout so rare max-power changes can be
    --- handled without a full ClassPower rebuild.
    local function GetResolvedVisibleMax()
        if not CP.visible or not CP.powerType then return CP.currentMax end
        local mode = CP.renderMode
        local powerType = CP.powerType
        local maxP = CP.currentMax or 1

        if mode == CPK.MODE.RUNE_CD then
            maxP = 6
        elseif mode == CPK.MODE.AURA_SINGLE then
            maxP = 1
        elseif mode == CPK.MODE.CONTINUOUS or mode == CPK.MODE.STAGGER or mode == CPK.MODE.TIMER_BAR then
            maxP = 1
        elseif mode == CPK.MODE.AURA_SEGMENTED then
            if powerType == "MAELSTROM_WEAPON" then
                maxP = 10
                local spellMax = C_Spell.GetSpellMaxCumulativeAuraApplications(CPK.SPELL.MAELSTROM_WEAPON)
                if NotSecret(spellMax) and type(spellMax) == "number" and spellMax > 0 then maxP = spellMax end
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

    --- Lightweight refresh for cases where the mode is still valid but the
    --- visible max or displayed values changed.
    local function RefreshVisibleModeLight(newMax)
        if not CP.visible or not CP.powerType then return end
        local maxP = tonumber(newMax) or tonumber(CP.currentMax) or 1
        if maxP < 1 then maxP = 1 end

        if maxP ~= CP.currentMax then
            local pf = CP._pf or GetPlayerFrame()
            if pf then
                CP_EnsureBars(pf, maxP)
                CP_Layout(pf, maxP, CP._layoutH or ((env._cpDB.bars and env._cpDB.bars.classPowerHeight) or 4), CP.powerType)
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
        local flags, powerType, renderMode = CP_ComputeStructuralSignature()
        if flags ~= CP.structuralFlags
            or powerType ~= CP.structuralPowerType
            or renderMode ~= CP.structuralRenderMode then
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

    --- Talent/spec/display events can invalidate render mode. Compare the
    --- structural signature first; only fall back to FullRefresh when the shape
    --- of the resource display actually changed.
    local function HandleRareStructuralEvent(useTimer)
        if CP_ShouldUseLiteBindings() then
            local flags, powerType, renderMode = CP_ComputeStructuralSignature()
            if flags ~= CP.structuralFlags
                or powerType ~= CP.structuralPowerType
                or renderMode ~= CP.structuralRenderMode then
                if useTimer then
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

        if useTimer then
            C_Timer.After(0.1, FullRefresh)
        else
            FullRefresh()
        end
    end

    --- Frequent UNIT_POWER path. Filter by token and render mode before calling
    --- RunActiveUpdate so aura/timer/stagger modes do not do duplicate work.
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

    --- Aura-backed class resources keep their own player-only UNIT_AURA traffic.
    --- Ebon Might is native AuraContainer-owned in 12.1 and never enters this
    --- path; only segmented aura resources and Stagger update here.
    local function OnAuraUpdate(unit)
        if CP.visible and CP.isAuraPower then
            RunActiveUpdate(CP.powerType, CP.currentMax)
        end
        if CP.visible and CP.renderMode == CPK.MODE.STAGGER then
            RunActiveUpdate(CP.powerType, CP.currentMax)
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

--- SPECIALS contains class-specific prediction/state that is not a generic
--- power-token event. Keeping these rules isolated prevents RUNTIME from turning
--- into a spec-by-spec rules table.
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
    local C_Timer = env.C_Timer
    local RunActiveUpdate = env.RunActiveUpdate
    local RunAuraSegmentedUpdate = env.RunAuraSegmentedUpdate
    local tipExpiryGeneration = 0

    --- Warlock shard prediction is speculative UI only; it is cleared on cast
    --- end and never writes profile/runtime structure.
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

    local function ResetTipState(render)
        tipExpiryGeneration = tipExpiryGeneration + 1
        CP.spStacks = 0
        CP.spExpires = nil
        if render and CP.visible and CP.powerType == "TIP_OF_THE_SPEAR" then
            RunAuraSegmentedUpdate()
        end
    end

    local function ScheduleTipExpiry()
        tipExpiryGeneration = tipExpiryGeneration + 1
        local generation = tipExpiryGeneration
        if not (C_Timer and type(C_Timer.After) == "function") then return end
        C_Timer.After(TIP.DURATION + 0.05, function()
            if generation ~= tipExpiryGeneration then return end
            if CP.spExpires and GetTime() >= CP.spExpires then
                ResetTipState(true)
            end
        end)
    end

    local function NormalizeExpiredTipState()
        if CP.spExpires and GetTime() >= CP.spExpires then
            ResetTipState(false)
        end
    end

    --- Secret-safe contract: Tip is derived exclusively from successful
    --- player casts. No aura lookup, UNIT_AURA parsing, polling, or OnUpdate.
    local function OnTipOfTheSpearSpellCast(spellID)
        local isRelevant = spellID == TIP.KILL_COMMAND
            or spellID == TIP.TAKEDOWN
            or TIP.SPENDERS[spellID] == true
        if not isRelevant then return end
        local known = C_SpellBook and C_SpellBook.IsSpellKnown
        if not known then return end
        if not known(TIP.TALENT_ID) then return end
        NormalizeExpiredTipState()
        if spellID == TIP.KILL_COMMAND then
            local gain = known(TIP.PRIMAL_SURGE) and 2 or 1
            CP.spStacks = math_min(TIP.MAX_STACKS, CP.spStacks + gain)
            CP.spExpires = GetTime() + TIP.DURATION
            ScheduleTipExpiry()
            RunAuraSegmentedUpdate()
            return
        end
        if spellID == TIP.TAKEDOWN and known(TIP.TWIN_FANG) then
            --- Twin Fangs grants three, then its impact spends one. Resolve the
            --- net result here so same-frame event ordering cannot leave +1.
            CP.spStacks = math_min(TIP.MAX_STACKS,
                CP.spStacks + (TIP.TWIN_FANG_GAIN or 3)) - 1
            CP.spExpires = GetTime() + TIP.DURATION
            ScheduleTipExpiry()
            RunAuraSegmentedUpdate()
            return
        end
        if TIP.SPENDERS[spellID] and CP.spStacks > 0 then
            if spellID == TIP.TAKEDOWN_HIT and known(TIP.TWIN_FANG) then return end
            CP.spStacks = CP.spStacks - 1
            if CP.spStacks == 0 then
                tipExpiryGeneration = tipExpiryGeneration + 1
                CP.spExpires = nil
            end
            RunAuraSegmentedUpdate()
        end
    end

    local function OnSpellTrackerReset()
        ResetTipState(false)
    end

    return {
        OnWarlockCastStart = OnWarlockCastStart,
        OnWarlockCastEnd = OnWarlockCastEnd,
        OnTipOfTheSpearSpellCast = OnTipOfTheSpearSpellCast,
        OnSpellTrackerReset = OnSpellTrackerReset,
    }
end
