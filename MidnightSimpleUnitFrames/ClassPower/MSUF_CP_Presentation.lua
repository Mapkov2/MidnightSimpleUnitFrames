local _, MSUF = ...
local shared = MSUF.CPFactoryShared.Core
local builders = shared.builders
local type = shared.type
local math_floor = shared.math_floor
local tonumber = shared.tonumber
local math_abs = shared.math_abs
local FontPathEquals = shared.FontPathEquals
local tostring = shared.tostring
local MarkFontApplyFailed = shared.MarkFontApplyFailed
local GetGlobalFontSettings = shared.GetGlobalFontSettings
local OverrideRGB = shared.OverrideRGB
local CP_ShapeTextures = shared.CP_ShapeTextures
local CP_UseNativeShapeFill = shared.CP_UseNativeShapeFill
local ClearShapeEdge = shared.ClearShapeEdge

builders.PRESENTATION = function(E)
    local _G = E.globals or _G
    --- Bound once by PRESENTATION at controller load. RunActiveUpdate is the
    --- controller's active-mode dispatch (CP_RunActiveUpdate): Stagger, runes,
    --- aura, continuous and native modes each repaint with their own painter,
    --- never the segmented one.
    local CP, _cpDB, PT, CP_ResolveTexture, RunActiveUpdate

    local _cpFontRev

    local function CDM_GetScaledWidth(cdmFrame, targetFrame)
        local getScaledWidth = _G.MSUF_GetCooldownAnchorScaledWidth
        local width = type(getScaledWidth) == "function" and getScaledWidth(cdmFrame, targetFrame) or nil
        return width and math_floor(width + 0.5) or nil
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
        if actualSize and math_abs((tonumber(actualSize) or 0) - size) > 0.01 then return false end
        if (actualFlags or "") ~= (fontFlags or "") then return false end
        if actual == fontPath then return true end
        if FontPathEquals(fontPath, actual) == true then return true end
        return tostring(actual or ""):gsub("/", "\\"):lower() == tostring(fontPath or ""):gsub("/", "\\"):lower()
    end

    local function ApplyClassPowerFont(region, fontPath, size, fontFlags)
        if not (region and region.SetFont) then return false end
        local applyResolved = _G.MSUF_ApplyResolvedFont
        if type(applyResolved) == "function" then
            local ok, _, source = applyResolved(region, fontPath, size, fontFlags)
            return ok == true and source ~= "fallback"
        end
        if _G.MSUF_SetFontChecked(region, fontPath, size, fontFlags) and ClassPowerFontApplied(region, fontPath, size, fontFlags) then return true end
        local fallback = _G.MSUF_ResolveSafeFontPath and _G.MSUF_ResolveSafeFontPath("Fonts\\FRIZQT__.TTF", size, fontFlags, "FRIZQT") or "Fonts\\FRIZQT__.TTF"
        _G.MSUF_SetFontChecked(region, fallback, size, fontFlags)
        MarkFontApplyFailed()
        return false
    end

    --- Font refresh is driven by global font serials and ClassPower options.
    --- Keep it stamped so profile/font changes repaint once instead of during
    --- every class-resource event.
    local function CP_ApplyFont()
        local fs = CP.text

        local path, flags, fr, fg, fb, baseSize, useShadow
        path, flags, fr, fg, fb, baseSize, useShadow = GetGlobalFontSettings()
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
            local cr, cg, cb = OverrideRGB(_cpDB.colorOverrides, "RESOURCE_TEXT")
            if cr then tr, tg, tb = cr, cg, cb end
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
        if RunActiveUpdate then RunActiveUpdate(powerType, CP.currentMax) end
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
        local shapeInfo = not (CP.powerType == "WHIRLWIND" or CP.powerType == "SWEEPING_STRIKES")
            and CP_ShapeTextures(b.classPowerShape) or nil
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

    local API = {
        CDM_GetScaledWidth = CDM_GetScaledWidth,
        CP_ApplyTextOffset = CP_ApplyTextOffset,
        CP_ApplyFont = CP_ApplyFont,
        CP_ApplyColors = CP_ApplyColors,
        CP_RefreshTexture = CP_RefreshTexture,
    }

        CP, _cpDB, PT = E.CP, E._cpDB, E.PT
        CP_ResolveTexture, RunActiveUpdate = E.CP_ResolveTexture, E.RunActiveUpdate
        _cpFontRev = 0
    return API
end
