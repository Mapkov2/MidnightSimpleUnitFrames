--- Unit preview render/composition.
---
--- The view file builds frames and wires controls; this module owns the hot
--- refresh path that composes the live preview visuals.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local Render = MSUF.UFPreviewRender or {}
MSUF.UFPreviewRender = Render
local Pick = (MSUF.MSUF2 or _G.MSUF2 or {}).Pick

function Render.Install(Preview, deps)
    if type(Preview) ~= "table" then return end
    deps = deps or Preview.RefreshDeps or {}
    Preview.RefreshDeps = deps

    local RuntimeSpecForPreviewKey = deps.RuntimeSpecForPreviewKey or function() return nil end
    local RuntimeVisualScaleForPreviewKey = deps.RuntimeVisualScaleForPreviewKey or function() return 1 end
    local ClampPreviewZoom = deps.ClampPreviewZoom or function(v) return tonumber(v) or 1 end
    local UpdatePreviewZoomControls = deps.UpdatePreviewZoomControls or function() end
    local ZOOM_MIN = tonumber(deps.ZOOM_MIN) or 0.35

    local ApplyPreviewRounded = deps.ApplyPreviewRounded or function() end
    local ApplyPreviewFrameBorder = deps.ApplyPreviewFrameBorder or function() end
    local PreviewRoundedOutlineThickness = deps.PreviewRoundedOutlineThickness or function() return 1 end
    local ApplyPreviewBoundsGuide = deps.ApplyPreviewBoundsGuide or function() end
    local CastbarShowIcon = deps.CastbarShowIcon or function() return true end
    local CastbarShowText = deps.CastbarShowText or function() return true, true end
    local ReadCastbarNum = deps.ReadCastbarNum or function(_, _, fallback) return tonumber(fallback) or 0 end
    local FormatCastbarPreviewTime = deps.FormatCastbarPreviewTime or function(v) return tostring(v or "") end
    local ClassColor = deps.ClassColor or function() return 1, 1, 1 end
    local HealthColor = deps.HealthColor or function() return 0.2, 0.8, 0.2 end
    local HealthBackgroundColor = deps.HealthBackgroundColor or function() return 0.02, 0.03, 0.04, 0.9 end
    local PowerBackgroundColor = deps.PowerBackgroundColor or function() return 0.02, 0.03, 0.04, 0.9 end
    local PowerColor = deps.PowerColor or function() return 0.2, 0.45, 1.0 end
    local FontColor = deps.FontColor or function() return 1, 1, 1 end
    local PreviewResolveHealPredAnchorMode = deps.PreviewResolveHealPredAnchorMode or function() return "RIGHT" end
    local PreviewResolveAbsorbAnchorMode = deps.PreviewResolveAbsorbAnchorMode or function() return "RIGHT" end
    local PreviewHealPredictionEnabled = deps.PreviewHealPredictionEnabled or function() return false end
    local PreviewAbsorbBarEnabled = deps.PreviewAbsorbBarEnabled or function() return false end
    local UnitPreviewPortraitTexture = deps.UnitPreviewPortraitTexture
    local ClassPortraitVisual = deps.ClassPortraitVisual
    local PreviewNameColor = deps.PreviewNameColor or function() return 1, 1, 1 end
    local PreviewToTInlineColor = deps.PreviewToTInlineColor or function() return 1, 1, 1 end
    local NormalizeHpMode = deps.NormalizeHpMode or function(v) return v end
    local NormalizePowerMode = deps.NormalizePowerMode or function(v) return v end
    local TextScopeGet = deps.TextScopeGet or function() return nil end
    local TextScopeHasSlots = deps.TextScopeHasSlots or function() return false end
    local TextScopeSlotGet = deps.TextScopeSlotGet or function() return nil end
    local FormatMode = deps.FormatMode or function() return "" end
    local ShortenPreviewName = deps.ShortenPreviewName or function(v) return v end
    local ToTInlineSeparator = deps.ToTInlineSeparator or function(v) return v end
    local ResolveNameAnchor = deps.ResolveNameAnchor or function(_, x) return "LEFT", "LEFT", x or 0, "LEFT" end
    local LayoutUnitPreviewOverlay = deps.LayoutUnitPreviewOverlay or function() end
    local PositionFromAnchor = deps.PositionFromAnchor or function() end
    local PositionRuntimeLayoutIconPreview = deps.PositionRuntimeLayoutIconPreview or function() end
    local PositionStatusCornerPreview = deps.PositionStatusCornerPreview or function() end
    local PositionSameAnchorPreview = deps.PositionSameAnchorPreview or function() end
    local PositionLevelPreview = deps.PositionLevelPreview or function() end
    local ResolveStatusPreviewAnchor = deps.ResolveStatusPreviewAnchor or function() return "CENTER" end
    local SetPreviewIconTexture = deps.SetPreviewIconTexture or function() end
    local NormalizeStatusPreviewId = deps.NormalizeStatusPreviewId or function(v) return v end
    local PreviewStatus = MSUF.UFPreviewStatus or {}
    local STATUS_RUNTIME_KEYS = {
        raidmarker = "raidMarker",
        leader = "leader",
        level = "level",
        elite = "elite",
        statusText = "statusText",
        statusCombat = "combat",
        statusResting = "resting",
        statusIncomingRes = "incomingRes",
    }
    local ApplyPreviewTextFocus = deps.ApplyPreviewTextFocus or function() end
    local fallbackFont = deps.FONT or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

    if type(deps.ApplyPreviewFont) ~= "function" then
        deps.ApplyPreviewFont = function(fs, size)
            if not (fs and fs.SetFont) then return end
            size = tonumber(size) or 12

            local fontPath, fontFlags, _, _, _, _, useShadow
            local gfs = _G.MSUF_GetGlobalFontSettings
            if type(gfs) == "function" then
                local ok, path, flags, _, _, _, _, shadow = pcall(gfs)
                if ok then
                    fontPath, fontFlags, useShadow = path, flags, shadow
                end
            end

            if type(fontPath) ~= "string" or fontPath == "" then
                local getPath = _G.MSUF_GetFontPath
                if type(getPath) == "function" then fontPath = getPath() end
            end
            if fontFlags == nil then
                local getFlags = _G.MSUF_GetFontFlags
                fontFlags = (type(getFlags) == "function") and getFlags() or "OUTLINE"
            end
            if fontFlags == nil then fontFlags = "OUTLINE" end

            local db = _G.MSUF_DB
            local general = db and db.general
            local fontKey = general and general.fontKey
            if type(fontPath) ~= "string" or fontPath == "" then
                local pathForKey = _G.MSUF_ResolveFontKeyPath or _G.MSUF_GetFontPathForKey or (MSUF and MSUF.MSUF_GetFontPathForKey)
                if type(pathForKey) == "function" and fontKey then
                    fontPath = pathForKey(fontKey, size, fontFlags)
                end
            end
            if type(fontPath) ~= "string" or fontPath == "" then fontPath = fallbackFont end

            local safeSetFont = _G.MSUF_SetFontSafe
            if type(safeSetFont) == "function" then
                safeSetFont(fs, fontPath, size, fontFlags, fontKey)
            else
                fs:SetFont(fontPath, size, fontFlags)
            end

            if fs.SetShadowOffset then
                if useShadow == nil then useShadow = general and general.textBackdrop == true end
                fs:SetShadowOffset(useShadow and 1 or 0, useShadow and -1 or 0)
            end
        end
    end

    local function LayoutPreviewPortraitBorder(portrait, thickness, fill, r, g, b, a)
        local border = portrait and portrait.border
        local edges = border and border.edges
        if not (border and edges) then return end
        if not r then
            for i = 1, 4 do
                if edges[i] then edges[i]:Hide() end
            end
            return
        end
        thickness = math.floor((tonumber(thickness) or 1) + 0.5)
        if thickness < 1 then thickness = 1 end
        if thickness > 30 then thickness = 30 end
        local key = thickness .. "|" .. (fill and "1" or "0")
        local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
        if portrait._previewBorderKey ~= key then
            top:ClearAllPoints()
            bottom:ClearAllPoints()
            left:ClearAllPoints()
            right:ClearAllPoints()
            if fill then
                top:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, 0)
                top:SetPoint("TOPRIGHT", portrait, "TOPRIGHT", 0, 0)
                bottom:SetPoint("BOTTOMLEFT", portrait, "BOTTOMLEFT", 0, 0)
                bottom:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, 0)
                left:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, 0)
                left:SetPoint("BOTTOMLEFT", portrait, "BOTTOMLEFT", 0, 0)
                right:SetPoint("TOPRIGHT", portrait, "TOPRIGHT", 0, 0)
                right:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, 0)
            else
                top:SetPoint("TOPLEFT", portrait, "TOPLEFT", -thickness, thickness)
                top:SetPoint("TOPRIGHT", portrait, "TOPRIGHT", thickness, thickness)
                bottom:SetPoint("BOTTOMLEFT", portrait, "BOTTOMLEFT", -thickness, -thickness)
                bottom:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", thickness, -thickness)
                left:SetPoint("TOPLEFT", portrait, "TOPLEFT", -thickness, thickness)
                left:SetPoint("BOTTOMLEFT", portrait, "BOTTOMLEFT", -thickness, -thickness)
                right:SetPoint("TOPRIGHT", portrait, "TOPRIGHT", thickness, thickness)
                right:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", thickness, -thickness)
            end
            top:SetHeight(thickness)
            bottom:SetHeight(thickness)
            left:SetWidth(thickness)
            right:SetWidth(thickness)
            portrait._previewBorderKey = key
        end
        for i = 1, 4 do
            if edges[i] then
                edges[i]:SetVertexColor(r, g, b, a or 1)
                edges[i]:Show()
            end
        end
    end

function Preview.Refresh(box, reason)
    box = box or Preview.active
    if not box or not box:IsShown() then return end
    local D = Preview.RefreshDeps
    local PreviewInCombat = D.PreviewInCombat
    if PreviewInCombat() then return end
    local TR, PortraitStyleGet, max, min, abs, floor, format, TEX_W8, ApplyPreviewFont, CastbarEnabled, ReadCastbarSize, CastbarOffsetFields, CastbarDetached, CanDetachPowerBarKey, ClampPreviewLayer, SetTex, ReadPowerBarHeight, PlaceHandle, UnitPreviewText, UnitPreviewTextMovesTogether, SetShownSafe, ApplyPreviewLayerVisibility, ApplyPreviewTransparency, RefreshHandleSelectionVisuals, Auras = Pick(D, [[TR PortraitStyleGet max min abs floor format TEX_W8 ApplyPreviewFont CastbarEnabled ReadCastbarSize CastbarOffsetFields CastbarDetached CanDetachPowerBarKey ClampPreviewLayer SetTex ReadPowerBarHeight PlaceHandle UnitPreviewText UnitPreviewTextMovesTogether SetShownSafe ApplyPreviewLayerVisibility ApplyPreviewTransparency RefreshHandleSelectionVisuals Auras]])
    local panel = box._msufPanel
    local UNIT_DATA = D.UNIT_DATA or {}
    local UNIT_LABELS = D.UNIT_LABELS or {}
    local key = D.CurrentPanelKey(panel)
    local conf, g = D.UnitDB(key)
    local data = UNIT_DATA[key] or UNIT_DATA.player or {}
    local runtimeSpec = RuntimeSpecForPreviewKey(key)
    local runtimePower = runtimeSpec and runtimeSpec.power
    local runtimeStatus = runtimeSpec and runtimeSpec.status
    local runtimeClassPower = runtimeSpec and runtimeSpec.classPower
    box.key = key
    local skipControlRefresh = (reason == "OPTIONS_APPLY_DB" or reason == "UNIT_MENU_ENTER" or reason == "UNIT_MENU_REENTER")
        or reason == "UNIT_PREVIEW_DRAG"
        or reason == "UNIT_PREVIEW_ZOOM"
        or reason == "UNIT_PREVIEW_ZOOM_STEP"
        or reason == "UNIT_PREVIEW_ZOOM_FIT"
        or reason == "UNIT_PREVIEW_ZOOM_1TO1"
        or reason == "MENU_TEXT_FOCUS"
        or reason == "MENU_TEXT_CLEAR_FOCUS"
    if panel and panel._msufRefreshUnitTextControls and not skipControlRefresh and not box._refreshingControls then
        box._refreshingControls = true
        panel._msufRefreshUnitTextControls()
        if panel._msufRefreshUnitPortraitControls then panel._msufRefreshUnitPortraitControls() end
        if panel._msufRefreshUnitPowerControls then panel._msufRefreshUnitPowerControls() end
        box._refreshingControls = nil
    end
    if box.title then box.title:SetText(TR("Unit Frame Preview") .. " - " .. TR(UNIT_LABELS[key] or key)) end
    local canvas = box.canvas
    local cw = canvas:GetWidth() or 600
    local ch = canvas:GetHeight() or 180
    if cw <= 1 then cw = 600 end
    if ch <= 1 then ch = 180 end
    local w = tonumber(runtimeSpec and runtimeSpec.width) or tonumber(conf.width or conf.frameWidth) or (key == "boss" and 180 or (key == "focus" and 180 or 275))
    local h = tonumber(runtimeSpec and runtimeSpec.height) or tonumber(conf.height or conf.frameHeight) or (key == "boss" and 30 or (key == "focus" and 30 or 40))
    if w < 60 then w = 60 elseif w > 520 then w = 520 end
    if h < 18 then h = 18 elseif h > 140 then h = 140 end
    local mode = (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.side) or conf.portraitMode
    local hasPortrait
    if runtimeSpec and runtimeSpec.portrait then
        hasPortrait = runtimeSpec.portrait.enabled == true
    else
        hasPortrait = (mode == "LEFT" or mode == "RIGHT")
    end
    if hasPortrait and mode ~= "RIGHT" then mode = "LEFT" end
    local pSize = hasPortrait and (tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.size) or tonumber(PortraitStyleGet(key, "portraitSizeOverride", 0)) or 0) or 0
    if pSize <= 0 then pSize = max(22, h - 4) end
    box._runtimePortraitBorderStyle = (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.border and runtimeSpec.portrait.border.style) or PortraitStyleGet(key, "portraitBorderStyle", "NONE") or "NONE"
    box._runtimePortraitBorderThickness = 0
    box._runtimePortraitBorderFill = false
    if hasPortrait and box._runtimePortraitBorderStyle ~= "NONE" then
        box._runtimePortraitBorderThickness = max(1, tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.border and runtimeSpec.portrait.border.thickness) or tonumber(PortraitStyleGet(key, "portraitBorderThickness", 2)) or 2)
        box._runtimePortraitBorderFill = (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.border and runtimeSpec.portrait.border.fill == true) or (not (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.border) and PortraitStyleGet(key, "portraitFillBorder", false) == true)
    end
    local castEnabled = runtimeSpec and runtimeSpec.castbar and runtimeSpec.castbar.enabled == true
    if not (runtimeSpec and runtimeSpec.castbar) then castEnabled = CastbarEnabled(key, g) end
    local castW, castBarH = ReadCastbarSize(key, g, w, key == "boss" and 12 or 18)
    local castXKey, castYKey, castDefX, castDefY = CastbarOffsetFields(key)
    local castOffsetX = castXKey and tonumber(g[castXKey]) or nil
    local castOffsetY = castYKey and tonumber(g[castYKey]) or nil
    if castOffsetX == nil then castOffsetX = tonumber(castDefX) or 0 end
    if castOffsetY == nil then castOffsetY = tonumber(castDefY) or 0 end
    local castDetached = castEnabled and CastbarDetached(key, g)
    local castPreviewVisible = castEnabled
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars or {}
    local powerAllowed = runtimePower and runtimePower.enabled == true
    if runtimePower == nil then powerAllowed = D.ReadPowerBarEnabled(conf, key) end
    local detachedPower = CanDetachPowerBarKey(key) and powerAllowed and ((runtimePower and runtimePower.detached == true) or (runtimePower == nil and conf.powerBarDetached == true))
    local classPowerOn = runtimeClassPower and runtimeClassPower.enabled == true
    if runtimeClassPower == nil then classPowerOn = key == "player" and (bars.showClassPower ~= false or detachedPower) end
    local powerFrac = tonumber(data.power) or 1
    if not detachedPower and key ~= "player" then powerFrac = 1 end
    if powerFrac < 0 then powerFrac = 0 elseif powerFrac > 1 then powerFrac = 1 end
    local cpH = classPowerOn and (tonumber(bars.classPowerHeight) or 4) or 0
    if cpH < 2 then cpH = 2 elseif cpH > 30 then cpH = 30 end
    box._runtimeDetachedPowerW = tonumber(runtimePower and runtimePower.detachedWidth) or tonumber(conf.detachedPowerBarWidth) or w
    box._runtimeDetachedPowerX = tonumber(runtimePower and runtimePower.detachedX) or tonumber(conf.detachedPowerBarOffsetX) or 0
    box._runtimeDetachedPowerY = tonumber(runtimePower and runtimePower.detachedY) or tonumber(conf.detachedPowerBarOffsetY) or -4
    box._runtimeDetachedPowerAnchorClass = key == "player" and ((runtimePower and runtimePower.detachedAnchorClass == true) or (runtimePower == nil and conf.detachedPowerBarAnchorToClassPower == true))
    box._runtimeDetachedPowerTextOnBar = (runtimePower and runtimePower.textOnDetached == true) or (runtimePower == nil and conf.detachedPowerBarTextOnBar == true)
    local detachedH = detachedPower and (tonumber(runtimePower and runtimePower.detachedHeight) or tonumber(conf.detachedPowerBarHeight) or 6) or 0
    if detachedH < 2 then detachedH = 2 elseif detachedH > 80 then detachedH = 80 end
    local wideW = w
    if classPowerOn and bars.classPowerWidthMode == "custom" then wideW = max(wideW, tonumber(bars.classPowerWidth) or w) end
    if detachedPower then wideW = max(wideW, box._runtimeDetachedPowerW) end
    local minX, maxX, minY, maxY = 0, w, 0, h
    if hasPortrait then
        local poX = tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.x) or tonumber(PortraitStyleGet(key, "portraitOffsetX", 0)) or 0
        local poY = tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.y) or tonumber(PortraitStyleGet(key, "portraitOffsetY", 0)) or 0
        local left, right
        if mode == "RIGHT" then
            left, right = w + poX, w + poX + pSize
        else
            left, right = poX - pSize, poX
        end
        if box._runtimePortraitBorderThickness > 0 and not box._runtimePortraitBorderFill then
            left, right = left - box._runtimePortraitBorderThickness, right + box._runtimePortraitBorderThickness
        end
        minX, maxX = min(minX, left), max(maxX, right)
        minY, maxY = min(minY, poY - pSize * 0.5 + h * 0.5 - (box._runtimePortraitBorderFill and 0 or box._runtimePortraitBorderThickness)), max(maxY, poY + pSize * 0.5 + h * 0.5 + (box._runtimePortraitBorderFill and 0 or box._runtimePortraitBorderThickness))
    end
    if classPowerOn then
        local cpW = (bars.classPowerWidthMode == "custom") and (tonumber(bars.classPowerWidth) or (w - 4)) or (w - 4)
        local cx = 2 + (tonumber(bars.classPowerOffsetX) or 0)
        local cy = h + 4 + (tonumber(bars.classPowerOffsetY) or 0)
        minX, maxX = min(minX, cx), max(maxX, cx + cpW)
        minY, maxY = min(minY, cy), max(maxY, cy + cpH)
    end
    if detachedPower then
        local dW = box._runtimeDetachedPowerW
        local dx = box._runtimeDetachedPowerX
        local dy = box._runtimeDetachedPowerY
        local dLeft, dBottom = (w - dW) * 0.5 + dx, -detachedH + dy
        if box._runtimeDetachedPowerAnchorClass and classPowerOn then
            local cpW = (bars.classPowerWidthMode == "custom") and (tonumber(bars.classPowerWidth) or (w - 4)) or (w - 4)
            local cx = 2 + (tonumber(bars.classPowerOffsetX) or 0)
            local cy = h + 4 + (tonumber(bars.classPowerOffsetY) or 0)
            dLeft = cx + (cpW - dW) * 0.5 + dx
            dBottom = cy - detachedH + dy
        end
        minX, maxX = min(minX, dLeft), max(maxX, dLeft + dW)
        minY, maxY = min(minY, dBottom), max(maxY, dBottom + detachedH)
    end
    if castEnabled then
        local cLeft, cBottom
        if castDetached then
            cLeft = (w - castW) * 0.5 + castOffsetX
            cBottom = (h - castBarH) * 0.5 + castOffsetY
        elseif key == "player" then
            cLeft = (w - castW) * 0.5 + castOffsetX
            cBottom = h + castOffsetY
        else
            cLeft = castOffsetX
            cBottom = h + castOffsetY + ((key == "boss") and 2 or 0)
        end
        local tooFar
        if castDetached then
            tooFar = (abs(castOffsetX) > 260 or abs(castOffsetY) > 180)
        else
            local limitX = max(w * 1.25, 180)
            local limitY = max(h * 3.0, 120)
            tooFar = (cLeft > w + limitX)
                or ((cLeft + castW) < -limitX)
                or (cBottom > h + limitY)
                or ((cBottom + castBarH) < -limitY)
        end
        castPreviewVisible = not tooFar
        if castPreviewVisible then
            wideW = max(wideW, castW)
            minX, maxX = min(minX, cLeft), max(maxX, cLeft + castW)
            minY, maxY = min(minY, cBottom), max(maxY, cBottom + castBarH)
        end
    end
    local auraPreviewState = Auras and Auras.BuildState and Auras.BuildState(key, w, h, runtimeSpec)
    local centerMinX, centerMaxX, centerMinY, centerMaxY = minX, maxX, minY, maxY
    if auraPreviewState and Auras.ExpandFootprint then
        minX, maxX, minY, maxY = Auras.ExpandFootprint(auraPreviewState, minX, maxX, minY, maxY)
    end
    local footprintW = max(wideW, maxX - minX)
    local footprintH = max(h, maxY - minY)
    local runtimeScale = RuntimeVisualScaleForPreviewKey(key)
    local autoScale = min(1.0, (cw - 60) / max(footprintW * runtimeScale, 1), (ch - 42) / max(footprintH * runtimeScale, 1))
    if autoScale < ZOOM_MIN then autoScale = ZOOM_MIN end
    local manualZoom = tonumber(box._manualZoom)
    local frozenScale = tonumber(box._dragFrozenScale)
    local previewScale = manualZoom and ClampPreviewZoom(manualZoom) or (frozenScale and ClampPreviewZoom(frozenScale) or autoScale)
    local scale = runtimeScale * previewScale
    box._mockRuntimeScale = runtimeScale
    box._mockAutoScale = autoScale
    box._mockScale = previewScale
    box._mockEffectiveScale = scale
    UpdatePreviewZoomControls(box)
    local function S(v) return floor((tonumber(v) or 0) * scale + 0.5) end
    local function StatusAnchorOffsets(spec, statusCfg)
        return (statusCfg and statusCfg.anchor) or ResolveStatusPreviewAnchor(spec, conf, g),
            S(tonumber(statusCfg and statusCfg.x) or tonumber(conf[spec.x]) or tonumber(g[spec.x]) or spec.defaultX or 0),
            S(tonumber(statusCfg and statusCfg.y) or tonumber(conf[spec.y]) or tonumber(g[spec.y]) or spec.defaultY or 0)
    end
    local sw, sh, sp = S(w), S(h), S(pSize)
    local mockOffsetX = -S(((centerMinX + centerMaxX) * 0.5) - (w * 0.5))
    local mockOffsetY = -S(((centerMinY + centerMaxY) * 0.5) - (h * 0.5))
    local panX, panY = tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
    box._mockBaseOffsetX, box._mockBaseOffsetY = mockOffsetX, mockOffsetY
    box._detachedCastPreview = nil
    box._detachedCastBaseOffsetX, box._detachedCastBaseOffsetY = nil, nil
    local mock = box.mock
    local baseLevel = (canvas.GetFrameLevel and canvas:GetFrameLevel() or 0) + 2
    if mock.SetFrameLevel then mock:SetFrameLevel(baseLevel + 4) end
    if mock.classPower and mock.classPower.SetFrameLevel then
        mock.classPower:SetFrameLevel(baseLevel + 4 + ClampPreviewLayer(bars.classPowerFrameLevelOffset, 5))
    end
    if mock.detachedPower and mock.detachedPower.SetFrameLevel then
        mock.detachedPower:SetFrameLevel(baseLevel + 4 + ClampPreviewLayer(runtimePower and runtimePower.detachedLevel or conf.detachedPowerBarFrameLevelOffset, 6))
    end
    if mock.portrait and mock.portrait.SetFrameLevel then mock.portrait:SetFrameLevel(baseLevel + 7) end
    if mock.cast and mock.cast.SetFrameLevel then mock.cast:SetFrameLevel(baseLevel + 6) end
    if mock.textFrame and mock.textFrame.SetFrameLevel then mock.textFrame:SetFrameLevel(baseLevel + 10) end
    local textBase = baseLevel + 12
    if mock.nameLayer and mock.nameLayer.SetFrameLevel then mock.nameLayer:SetFrameLevel(textBase + ClampPreviewLayer(conf.nameTextLayer, 5)) end
    if mock.hpLayer and mock.hpLayer.SetFrameLevel then mock.hpLayer:SetFrameLevel(textBase + ClampPreviewLayer(conf.hpTextLayer, 5)) end
    if mock.powerLayer and mock.powerLayer.SetFrameLevel then mock.powerLayer:SetFrameLevel(textBase + ClampPreviewLayer(conf.powerTextLayer, 2)) end
    if mock.bounds and mock.bounds.SetFrameLevel then mock.bounds:SetFrameLevel(baseLevel + 48) end
    SetTex(mock.hp, (runtimeSpec and runtimeSpec.health and runtimeSpec.health.texture) or (runtimeSpec and runtimeSpec.texture) or (type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture()) or TEX_W8)
    SetTex(mock.power, (runtimePower and runtimePower.texture) or (runtimeSpec and runtimeSpec.texture) or (type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture()) or TEX_W8)
    SetTex(mock.hpBG, (runtimeSpec and runtimeSpec.health and runtimeSpec.health.backgroundTexture) or (runtimeSpec and runtimeSpec.backgroundTexture) or (type(_G.MSUF_GetBarBackgroundTexture) == "function" and _G.MSUF_GetBarBackgroundTexture()) or TEX_W8)
    SetTex(mock.powerBG, (runtimePower and runtimePower.backgroundTexture) or (runtimeSpec and runtimeSpec.backgroundTexture) or (type(_G.MSUF_GetBarBackgroundTexture) == "function" and _G.MSUF_GetBarBackgroundTexture()) or TEX_W8)
    SetTex(mock.detachedPower.fill, (runtimePower and runtimePower.texture) or (runtimeSpec and runtimeSpec.texture) or (type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture()) or TEX_W8)
    SetTex(mock.cast.fill, type(_G.MSUF_GetCastbarTexture) == "function" and _G.MSUF_GetCastbarTexture() or TEX_W8)
    mock:SetSize(sw, sh)
    if mock.sizeTag then mock.sizeTag:SetText(format("%d x %d", w, h)) end
    mock:ClearAllPoints()
    mock:SetPoint("CENTER", canvas, "CENTER", mockOffsetX + panX, mockOffsetY + panY)
    local powerEnabled = runtimePower and runtimePower.enabled == true
    if runtimePower == nil then powerEnabled = D.ReadPowerBarEnabled(conf, key) end
    local powerOn = powerEnabled and not detachedPower
    local powerH = powerOn and S((runtimePower and runtimePower.height) or ReadPowerBarHeight(conf)) or 0
    if powerOn and powerH < 2 then powerH = 2 end
    mock.hpBG:ClearAllPoints()
    mock.hpBG:SetAllPoints(mock)
    mock.hp:ClearAllPoints()
    local hpReverse = (runtimeSpec and runtimeSpec.health and runtimeSpec.health.reverse == true) or (not (runtimeSpec and runtimeSpec.health) and conf.reverseFillBars == true)
    if hpReverse then
        mock.hp:SetPoint("TOPRIGHT", mock.hpBG, "TOPRIGHT", 0, 0)
        mock.hp:SetPoint("BOTTOMRIGHT", mock.hpBG, "BOTTOMRIGHT", 0, 0)
    else
        mock.hp:SetPoint("TOPLEFT", mock.hpBG, "TOPLEFT", 0, 0)
        mock.hp:SetPoint("BOTTOMLEFT", mock.hpBG, "BOTTOMLEFT", 0, 0)
    end
    local hpAreaW = max(1, sw)
    local hpFrac = max(0, min(1, tonumber(data.hp) or 0.6))
    mock.hp:SetWidth(max(1, hpAreaW * hpFrac))
    local healPredMode = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healAnchorMode) or PreviewResolveHealPredAnchorMode(conf, g)
    local absorbMode = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.absorbAnchorMode) or PreviewResolveAbsorbAnchorMode(conf, g)
    local healPredShown = runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.heal == true
    if not (runtimeSpec and runtimeSpec.prediction) then healPredShown = PreviewHealPredictionEnabled(conf, g) end
    local absorbShown = runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.absorb == true
    if not (runtimeSpec and runtimeSpec.prediction) then absorbShown = PreviewAbsorbBarEnabled(conf, g, key) end
    local healPredFrac = ((healPredMode == 3) and min(0.14, max(0.02, 1 - hpFrac))) or 0.14
    if healPredShown then
        local r = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healR) or tonumber(g and g.healPredColorR) or 0
        local gg = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healG) or tonumber(g and g.healPredColorG) or 1
        local b = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healB) or tonumber(g and g.healPredColorB) or 0.4
        local a = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healA) or 0.55
        mock.healPred:SetVertexColor(r, gg, b, a)
        LayoutUnitPreviewOverlay(mock.healPred, mock.hpBG, mock.hp, healPredMode, healPredFrac, hpReverse, nil, hpAreaW)
    else
        mock.healPred:Hide()
    end
    if absorbShown then
        local absorbAnchor = nil
        if healPredShown and mock.healPred:IsShown() and (healPredMode == 3 or healPredMode == 4) and (absorbMode == 3 or absorbMode == 4) then
            absorbAnchor = mock.healPred
        end
        LayoutUnitPreviewOverlay(mock.absorb, mock.hpBG, mock.hp, absorbMode, 0.10, hpReverse, absorbAnchor, hpAreaW)
    else
        mock.absorb:Hide()
    end
    local hr, hg, hb = runtimeSpec and runtimeSpec.health and runtimeSpec.health.r, runtimeSpec and runtimeSpec.health and runtimeSpec.health.g, runtimeSpec and runtimeSpec.health and runtimeSpec.health.b
    if not hr then hr, hg, hb = HealthColor(key, data) end
    local hbr, hbg, hbb, hba
    local healthBg = runtimeSpec and runtimeSpec.health and runtimeSpec.health.background
    if healthBg then
        hbr, hbg, hbb, hba = healthBg.r or hr, healthBg.g or hg, healthBg.b or hb, healthBg.a or 0.85
    else
        hbr, hbg, hbb, hba = HealthBackgroundColor(hr, hg, hb, data)
    end
    mock.hpBG:SetVertexColor(hbr, hbg, hbb, hba)
    mock.hp:SetVertexColor(hr, hg, hb, 1)
    if powerOn then
        mock.powerBG:Show(); mock.power:Show()
        mock.powerBG:ClearAllPoints()
        mock.powerBG:SetPoint("BOTTOMLEFT", mock, "BOTTOMLEFT", 0, 0)
        mock.powerBG:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", 0, 0)
        mock.powerBG:SetHeight(powerH)
        local pr, pg, pb = runtimePower and runtimePower.r, runtimePower and runtimePower.g, runtimePower and runtimePower.b
        if not pr then pr, pg, pb = PowerColor(data.powerToken) end
        local pbr, pbg, pbb, pba
        local powerBg = runtimePower and runtimePower.background
        if powerBg then
            pbr, pbg, pbb, pba = powerBg.r or pr, powerBg.g or pg, powerBg.b or pb, powerBg.a or 0.85
        else
            pbr, pbg, pbb, pba = PowerBackgroundColor(pr, pg, pb, hr, hg, hb)
        end
        mock.powerBG:SetVertexColor(pbr, pbg, pbb, pba)
        mock.power:ClearAllPoints()
        mock.power:SetPoint("TOPLEFT", mock.powerBG, "TOPLEFT", 0, 0)
        mock.power:SetPoint("BOTTOMLEFT", mock.powerBG, "BOTTOMLEFT", 0, 0)
        mock.power:SetWidth(max(1, sw * powerFrac))
        mock.power:SetVertexColor(pr, pg, pb, 1)
    else
        mock.powerBG:Hide(); mock.power:Hide()
    end
    local fr, fg, fb = FontColor()
    local pr, pg, pb = runtimePower and runtimePower.r, runtimePower and runtimePower.g, runtimePower and runtimePower.b
    if not pr then pr, pg, pb = PowerColor(data.powerToken) end
    if classPowerOn then
        mock.classPower:Show()
        local cpW
        if bars.classPowerWidthMode == "custom" then cpW = tonumber(bars.classPowerWidth) or (w - 4) else cpW = w - 4 end
        if cpW < 30 then cpW = w - 4 elseif cpW > 800 then cpW = 800 end
        mock.classPower:SetSize(S(cpW), max(2, S(cpH)))
        mock.classPower:ClearAllPoints()
        mock.classPower:SetPoint("BOTTOMLEFT", mock, "TOPLEFT", S(2 + (tonumber(bars.classPowerOffsetX) or 0)), S(4 + (tonumber(bars.classPowerOffsetY) or 0)))
        local segCount = 5
        local gap = max(0, S(tonumber(bars.classPowerGap) or 0))
        local segW = floor((S(cpW) - (segCount - 1) * gap) / segCount)
        for i = 1, #mock.classPower.segments do
            local seg = mock.classPower.segments[i]
            if i <= segCount then
                seg:Show()
                seg:ClearAllPoints()
                seg:SetPoint("TOPLEFT", mock.classPower, "TOPLEFT", (i - 1) * (segW + gap), 0)
                seg:SetPoint("BOTTOMLEFT", mock.classPower, "BOTTOMLEFT", (i - 1) * (segW + gap), 0)
                seg:SetWidth(i == segCount and (S(cpW) - (i - 1) * (segW + gap)) or segW)
                local filled = i <= 3
                seg:SetColorTexture(pr, pg, pb, filled and 0.95 or 0.28)
            else
                seg:Hide()
            end
        end
        local classTextOn = bars.classPowerShowText == true
        if classTextOn then
            local cpTextSize = S(tonumber(bars.classPowerFontSize) or 16)
            if cpTextSize < 7 then cpTextSize = 7 end
            ApplyPreviewFont(mock.classPower.text, cpTextSize)
            mock.classPower.text:SetText("3")
            mock.classPower.text:SetTextColor(fr or 1, fg or 1, fb or 1, 1)
            mock.classPower.text:ClearAllPoints()
            mock.classPower.text:SetPoint("CENTER", mock.classPower, "CENTER", S(tonumber(bars.classPowerTextOffsetX) or 0), S(tonumber(bars.classPowerTextOffsetY) or 0))
            mock.classPower.text:Show()
            box.handleClassPowerText:SetSize(max(26, mock.classPower.text:GetStringWidth() + 10), max(18, mock.classPower.text:GetStringHeight() + 6))
            if not UnitPreviewText.PlaceHandleAroundRegions(box.handleClassPowerText, canvas, { mock.classPower.text }, 3) then
                PlaceHandle(box.handleClassPowerText, mock.classPower.text)
            end
        else
            mock.classPower.text:Hide()
            box.handleClassPowerText:Hide()
        end
        box.handleClassPower:SetSize(max(36, S(cpW)), max(18, max(2, S(cpH)) + 8))
        PlaceHandle(box.handleClassPower, mock.classPower)
    else
        mock.classPower:Hide()
        for i = 1, #mock.classPower.segments do mock.classPower.segments[i]:Hide() end
        if mock.classPower.text then mock.classPower.text:Hide() end
        box.handleClassPower:Hide()
        box.handleClassPowerText:Hide()
    end
    if detachedPower then
        mock.detachedPower:Show()
        local dW = box._runtimeDetachedPowerW
        if key == "player" and bars.detachedPowerBarWidthMode and bars.detachedPowerBarWidthMode ~= "manual" then
            dW = classPowerOn and (mock.classPower:GetWidth() / max(scale, 0.01)) or w
        end
        if dW < 20 then dW = 20 elseif dW > 800 then dW = 800 end
        mock.detachedPower:SetSize(S(dW), max(2, S(detachedH)))
        mock.detachedPower:ClearAllPoints()
        local dx = S(box._runtimeDetachedPowerX)
        local dy = S(box._runtimeDetachedPowerY)
        if box._runtimeDetachedPowerAnchorClass and classPowerOn and mock.classPower:IsShown() then
            mock.detachedPower:SetPoint("TOP", mock.classPower, "BOTTOM", dx, dy)
        else
            mock.detachedPower:SetPoint("TOP", mock, "BOTTOM", dx, dy)
        end
        mock.detachedPower.fill:SetVertexColor(pr, pg, pb, 1)
        mock.detachedPower.fill:SetWidth(max(1, S(dW) * powerFrac - 2))
        box.handleDetachedPower:SetSize(max(36, S(dW)), max(18, S(detachedH) + 8))
        PlaceHandle(box.handleDetachedPower, mock.detachedPower)
    else
        mock.detachedPower:Hide()
        box.handleDetachedPower:Hide()
    end
    ApplyPreviewRounded(box, key, powerOn, PreviewRoundedOutlineThickness(key, conf, scale))
    if ApplyPreviewFrameBorder then
        ApplyPreviewFrameBorder(box, runtimeSpec and runtimeSpec.border, scale)
    end
    if ApplyPreviewBoundsGuide then
        local guideEdge = 1
        if mock._msufPreviewRoundedActive == true then
            guideEdge = PreviewRoundedOutlineThickness(key, conf, scale)
        elseif runtimeSpec and runtimeSpec.border and runtimeSpec.border.enabled == true then
            guideEdge = floor(((tonumber(runtimeSpec.border.thickness) or 1) * scale) + 0.5)
        end
        ApplyPreviewBoundsGuide(box, guideEdge)
    end
    local fr, fg, fb = FontColor()
    local baseTextSize = tonumber(g.fontSize) or 14
    local nameRawSize = tonumber(conf.nameFontSize) or tonumber(g.nameFontSize) or baseTextSize
    local nameSize = S(nameRawSize); if nameSize < 7 then nameSize = 7 end
    local hpSize = S(tonumber(conf.hpFontSize) or tonumber(g.hpFontSize) or baseTextSize); if hpSize < 7 then hpSize = 7 end
    local pwrSize = S(tonumber(conf.powerFontSize) or tonumber(g.powerFontSize) or baseTextSize); if pwrSize < 7 then pwrSize = 7 end
    ApplyPreviewFont(mock.nameText, nameSize)
    ApplyPreviewFont(mock.raidGroupNameText, nameSize)
    ApplyPreviewFont(mock.totInlineSep, nameSize)
    ApplyPreviewFont(mock.totInlineText, nameSize)
    ApplyPreviewFont(mock.hpTextLeft, hpSize)
    ApplyPreviewFont(mock.hpTextCenter, hpSize)
    ApplyPreviewFont(mock.hpText, hpSize)
    ApplyPreviewFont(mock.hpTextPct, hpSize)
    ApplyPreviewFont(mock.powerTextLeft, pwrSize)
    ApplyPreviewFont(mock.powerTextCenter, pwrSize)
    ApplyPreviewFont(mock.powerText, pwrSize)
    ApplyPreviewFont(mock.powerTextPct, pwrSize)
    mock.nameText:SetTextColor(fr, fg, fb, 1)
    mock.raidGroupNameText:SetTextColor(fr, fg, fb, 1)
    mock.totInlineSep:SetTextColor(0.72, 0.76, 0.84, 1)
    mock.totInlineText:SetTextColor(fr, fg, fb, 1)
    local hpTextR, hpTextG, hpTextB = fr, fg, fb
    local healthTextByHealth = g.colorHealthTextByHealth == true
    if conf.fontOverride == true and conf.colorHealthTextByHealth ~= nil then
        healthTextByHealth = conf.colorHealthTextByHealth == true
    end
    if healthTextByHealth then
        local pct = tonumber(data.hp) or 1
        if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
        if pct <= 0.5 then
            hpTextR, hpTextG, hpTextB = 1, pct * 2, 0
        else
            hpTextR, hpTextG, hpTextB = (1 - pct) * 2, 1, 0
        end
    end
    mock.hpTextLeft:SetTextColor(hpTextR, hpTextG, hpTextB, 1)
    mock.hpTextCenter:SetTextColor(hpTextR, hpTextG, hpTextB, 1)
    mock.hpText:SetTextColor(hpTextR, hpTextG, hpTextB, 1)
    mock.hpTextPct:SetTextColor(hpTextR, hpTextG, hpTextB, 1)
    if g.colorPowerTextByType == true then
        local prt, pgt, pbt = PowerColor(data.powerToken)
        mock.powerTextLeft:SetTextColor(prt, pgt, pbt, 1)
        mock.powerTextCenter:SetTextColor(prt, pgt, pbt, 1)
        mock.powerText:SetTextColor(prt, pgt, pbt, 1)
        mock.powerTextPct:SetTextColor(prt, pgt, pbt, 1)
    else
        mock.powerTextLeft:SetTextColor(fr, fg, fb, 1)
        mock.powerTextCenter:SetTextColor(fr, fg, fb, 1)
        mock.powerText:SetTextColor(fr, fg, fb, 1)
        mock.powerTextPct:SetTextColor(fr, fg, fb, 1)
    end
    mock.nameText:SetText(ShortenPreviewName(data.name, key, conf))
    mock.raidGroupNameText:SetText(D.PreviewRaidGroupNameText(conf))
    local hpMax, pMax = 1000000, 240000
    local hpCur, pCur = floor(hpMax * data.hp + 0.5), floor(pMax * powerFrac + 0.5)
    local hpSlots = TextScopeHasSlots(key, "textLeft", "textCenter", "textRight")
    local hpLeftMode, hpCenterMode, hpRightMode
    if hpSlots then
        hpLeftMode = TextScopeSlotGet(key, "textLeft", "NONE", NormalizeHpMode)
        hpCenterMode = TextScopeSlotGet(key, "textCenter", "NONE", NormalizeHpMode)
        hpRightMode = TextScopeSlotGet(key, "textRight", "CURPERCENT", NormalizeHpMode)
    else
        hpLeftMode, hpCenterMode, hpRightMode = "NONE", "NONE", NormalizeHpMode(TextScopeGet(key, "hpTextMode", "CURPERCENT"))
    end
    if TextScopeGet(key, "hpTextReverse", false) == true then
        local rev = { CURPERCENT = "PERCENTCUR", PERCENTCUR = "CURPERCENT", CURMAX = "MAXCUR", MAXCUR = "CURMAX", CURMAXPERCENT = "PERCENTMAXCUR", PERCENTMAXCUR = "CURMAXPERCENT", MAXPERCENT = "PERCENTMAX", PERCENTMAX = "MAXPERCENT", PERCENTCURMAX = "CURMAXPERCENT" }
        hpLeftMode, hpRightMode = hpRightMode, hpLeftMode
        hpLeftMode = rev[hpLeftMode] or hpLeftMode
        hpCenterMode = rev[hpCenterMode] or hpCenterMode
        hpRightMode = rev[hpRightMode] or hpRightMode
    end
    local hpPctValue = floor(data.hp * 100 + 0.5)
    local hpSepRaw = TextScopeGet(key, "hpTextSeparator", "")
    mock.hpTextLeft:SetText(FormatMode(hpLeftMode, hpCur, hpMax, hpPctValue, hpSepRaw, false))
    mock.hpTextCenter:SetText(FormatMode(hpCenterMode, hpCur, hpMax, hpPctValue, hpSepRaw, false))
    mock.hpText:SetText(FormatMode(hpRightMode, hpCur, hpMax, hpPctValue, hpSepRaw, false))
    mock.hpTextPct:SetText("")
    local powerSlots = TextScopeHasSlots(key, "powerTextLeft", "powerTextCenter", "powerTextRight")
    local powerLeftMode, powerCenterMode, powerRightMode
    if powerSlots then
        powerLeftMode = TextScopeSlotGet(key, "powerTextLeft", "NONE", NormalizePowerMode)
        powerCenterMode = TextScopeSlotGet(key, "powerTextCenter", "NONE", NormalizePowerMode)
        powerRightMode = TextScopeSlotGet(key, "powerTextRight", "CURPERCENT", NormalizePowerMode)
    else
        powerLeftMode, powerCenterMode, powerRightMode = "NONE", "NONE", NormalizePowerMode(TextScopeGet(key, "powerTextMode", "CURPERCENT"))
    end
    local powerPctValue = floor(powerFrac * 100 + 0.5)
    local powerSepRaw = TextScopeGet(key, "powerTextSeparator", TextScopeGet(key, "hpTextSeparator", ""))
    mock.powerTextLeft:SetText(FormatMode(powerLeftMode, pCur, pMax, powerPctValue, powerSepRaw, true))
    mock.powerTextCenter:SetText(FormatMode(powerCenterMode, pCur, pMax, powerPctValue, powerSepRaw, true))
    mock.powerText:SetText(FormatMode(powerRightMode, pCur, pMax, powerPctValue, powerSepRaw, true))
    mock.powerTextPct:SetText("")
    local showNamePreview = conf.showName ~= false
    if runtimeSpec then showNamePreview = runtimeSpec.showName ~= false end
    local hpTextOn = conf.showHP ~= false
    if runtimeSpec then hpTextOn = runtimeSpec.showHealthText ~= false end
    local powerTextOn = (key ~= "focustarget" and conf.showPower ~= false) or conf.showPower == true
    if runtimeSpec then powerTextOn = runtimeSpec.showPowerText ~= false and powerEnabled == true end
    mock.nameText:SetShown(showNamePreview)
    local raidGroupCfg = runtimeStatus and runtimeStatus.raidGroup
    local raidGroupAnchor = (raidGroupCfg and raidGroupCfg.anchor) or D.NormalizeRaidGroupNameAnchor(conf.raidGroupNameAnchor)
    if not showNamePreview and (raidGroupAnchor == "NAMERIGHT" or raidGroupAnchor == "NAMELEFT") then
        raidGroupAnchor = "CENTER"
    end
    local showRaidGroupName = (runtimeStatus and runtimeStatus.raidGroup and runtimeStatus.raidGroup.enabled == true)
        or (not runtimeStatus and conf.showRaidGroupInName == true and D.PreviewRaidGroupNameAllowed(key))
    mock.raidGroupNameText:SetShown(showRaidGroupName)
    mock.totInlineSep:Hide()
    mock.totInlineText:Hide()
    mock.hpTextLeft:SetShown(hpTextOn and hpLeftMode ~= "NONE")
    mock.hpTextCenter:SetShown(hpTextOn and hpCenterMode ~= "NONE")
    mock.hpText:SetShown(hpTextOn and hpRightMode ~= "NONE")
    mock.hpTextPct:SetShown(false)
    mock.powerTextLeft:SetShown(powerTextOn and powerLeftMode ~= "NONE")
    mock.powerTextCenter:SetShown(powerTextOn and powerCenterMode ~= "NONE")
    mock.powerText:SetShown(powerTextOn and powerRightMode ~= "NONE")
    mock.powerTextPct:SetShown(false)
    mock.nameText:ClearAllPoints()
    local npt, nrel, nx, njust = ResolveNameAnchor(conf.nameTextAnchor or "LEFT", S(tonumber(conf.nameOffsetX) or 4))
    mock.nameText:SetPoint(npt, mock.textFrame, nrel, nx, S(tonumber(conf.nameOffsetY) or -4))
    mock.nameText:SetJustifyH(njust)
    mock.raidGroupNameText:ClearAllPoints()
    local raidGroupX = S(tonumber(raidGroupCfg and raidGroupCfg.x) or tonumber(conf.raidGroupNameOffsetX) or 3)
    local raidGroupY = S(tonumber(raidGroupCfg and raidGroupCfg.y) or tonumber(conf.raidGroupNameOffsetY) or 0)
    if raidGroupAnchor == "NAMERIGHT" then
        mock.raidGroupNameText:SetPoint("LEFT", mock.nameText, "RIGHT", raidGroupX, raidGroupY)
    elseif raidGroupAnchor == "NAMELEFT" then
        mock.raidGroupNameText:SetPoint("RIGHT", mock.nameText, "LEFT", raidGroupX, raidGroupY)
    else
        mock.raidGroupNameText:SetPoint(raidGroupAnchor, mock.textFrame, raidGroupAnchor, raidGroupX, raidGroupY)
    end
    mock.raidGroupNameText:SetJustifyH("LEFT")
    do
        local totConf = (_G.MSUF_DB and _G.MSUF_DB.targettarget) or {}
        local showInline = key == "target" and conf.showName ~= false and totConf.showToTInTargetName == true
        if showInline then
            local sep = ToTInlineSeparator(totConf.totInlineSeparator, totConf.totInlineCustomSeparator)
            local totData = UNIT_DATA.targettarget or { name = "Target" }
            local tr, tg, tb = PreviewNameColor("target", data, fr, fg, fb)
            local ir, ig, ib = PreviewToTInlineColor(totConf.totInlineColorMode, totData, tr, tg, tb, fr, fg, fb)
            mock.totInlineSep:SetText(sep ~= "" and sep or " ")
            mock.totInlineText:SetText(ShortenPreviewName(totData.name, "targettarget", conf))
            mock.totInlineText:SetTextColor(ir, ig, ib, 1)
            local inlineAnchor = (showRaidGroupName and raidGroupAnchor == "NAMERIGHT") and mock.raidGroupNameText or mock.nameText
            mock.totInlineSep:ClearAllPoints()
            mock.totInlineSep:SetPoint("LEFT", inlineAnchor, "RIGHT", S(4), 0)
            mock.totInlineText:ClearAllPoints()
            mock.totInlineText:SetPoint("LEFT", mock.totInlineSep, "RIGHT", S(4), 0)
            mock.totInlineSep:Show()
            mock.totInlineText:Show()
        end
    end
    local function PlacePreviewSlot(fs, parent, point, relPoint, x, y, justify)
        if not fs then return end
        fs:ClearAllPoints()
        fs:SetPoint(point, parent, relPoint, x, y)
        fs:SetJustifyH(justify)
    end
    local function NumField(primary, alias, generalPrimary, generalAlias, fallback)
        local v = conf[primary]
        if v == nil and alias then v = conf[alias] end
        if v == nil and generalPrimary then v = g[generalPrimary] end
        if v == nil and generalAlias then v = g[generalAlias] end
        return tonumber(v) or fallback or 0
    end
    local hpOX = NumField("hpOffsetX", "hpTextOffsetX", "hpOffsetX", "hpTextOffsetX", -4)
    local hpOY = NumField("hpOffsetY", "hpTextOffsetY", "hpOffsetY", "hpTextOffsetY", -4)
    local hpLeftX = hpOX + NumField("hpTextLeftOffsetX", "hpLeftOffsetX", "hpTextLeftOffsetX", "hpLeftOffsetX", 0)
    local hpLeftY = hpOY + NumField("hpTextLeftOffsetY", "hpLeftOffsetY", "hpTextLeftOffsetY", "hpLeftOffsetY", 0)
    local hpCenterX = hpOX + NumField("hpTextCenterOffsetX", "hpCenterOffsetX", "hpTextCenterOffsetX", "hpCenterOffsetX", 0)
    local hpCenterY = hpOY + NumField("hpTextCenterOffsetY", "hpCenterOffsetY", "hpTextCenterOffsetY", "hpCenterOffsetY", 0)
    local hpRightX = hpOX + NumField("hpTextRightOffsetX", "hpRightOffsetX", "hpTextRightOffsetX", "hpRightOffsetX", 0)
    local hpRightY = hpOY + NumField("hpTextRightOffsetY", "hpRightOffsetY", "hpTextRightOffsetY", "hpRightOffsetY", 0)
    PlacePreviewSlot(mock.hpTextLeft, mock.textFrame, "LEFT", "LEFT", S(4 + hpLeftX), S(hpLeftY), "LEFT")
    PlacePreviewSlot(mock.hpTextCenter, mock.textFrame, "CENTER", "CENTER", S(hpCenterX), S(hpCenterY), "CENTER")
    PlacePreviewSlot(mock.hpText, mock.textFrame, "RIGHT", "RIGHT", S(-4 + hpRightX), S(hpRightY), "RIGHT")
    PlacePreviewSlot(mock.hpTextPct, mock.textFrame, "RIGHT", "RIGHT", S(-4 + hpRightX), S(hpRightY), "RIGHT")
    local pOX = NumField("powerOffsetX", "powerTextOffsetX", "powerOffsetX", "powerTextOffsetX", -4)
    local pOY = NumField("powerOffsetY", "powerTextOffsetY", "powerOffsetY", "powerTextOffsetY", 4)
    local pLeftX = pOX + NumField("powerTextLeftOffsetX", "powerLeftOffsetX", "powerTextLeftOffsetX", "powerLeftOffsetX", 0)
    local pLeftY = pOY + NumField("powerTextLeftOffsetY", "powerLeftOffsetY", "powerTextLeftOffsetY", "powerLeftOffsetY", 0)
    local pCenterX = pOX + NumField("powerTextCenterOffsetX", "powerCenterOffsetX", "powerTextCenterOffsetX", "powerCenterOffsetX", 0)
    local pCenterY = pOY + NumField("powerTextCenterOffsetY", "powerCenterOffsetY", "powerTextCenterOffsetY", "powerCenterOffsetY", 0)
    local pRightX = pOX + NumField("powerTextRightOffsetX", "powerRightOffsetX", "powerTextRightOffsetX", "powerRightOffsetX", 0)
    local pRightY = pOY + NumField("powerTextRightOffsetY", "powerRightOffsetY", "powerTextRightOffsetY", "powerRightOffsetY", 0)
    if detachedPower and box._runtimeDetachedPowerTextOnBar and mock.detachedPower:IsShown() then
        PlacePreviewSlot(mock.powerTextLeft, mock.detachedPower, "LEFT", "LEFT", S(4 + pLeftX), S(pLeftY), "LEFT")
        PlacePreviewSlot(mock.powerTextCenter, mock.detachedPower, "CENTER", "CENTER", S(pCenterX), S(pCenterY), "CENTER")
        PlacePreviewSlot(mock.powerText, mock.detachedPower, "RIGHT", "RIGHT", S(-4 + pRightX), S(pRightY), "RIGHT")
        PlacePreviewSlot(mock.powerTextPct, mock.detachedPower, "RIGHT", "RIGHT", S(-4 + pRightX), S(pRightY), "RIGHT")
    else
        PlacePreviewSlot(mock.powerTextLeft, mock.textFrame, "BOTTOMLEFT", "BOTTOMLEFT", S(4 + pLeftX), S(1 + pLeftY), "LEFT")
        PlacePreviewSlot(mock.powerTextCenter, mock.textFrame, "BOTTOM", "BOTTOM", S(pCenterX), S(1 + pCenterY), "CENTER")
        PlacePreviewSlot(mock.powerText, mock.textFrame, "BOTTOMRIGHT", "BOTTOMRIGHT", S(-4 + pRightX), S(1 + pRightY), "RIGHT")
        PlacePreviewSlot(mock.powerTextPct, mock.textFrame, "BOTTOMRIGHT", "BOTTOMRIGHT", S(-4 + pRightX), S(1 + pRightY), "RIGHT")
    end
    if hasPortrait then
        mock.portrait:Show()
        mock.portrait:SetSize(sp, sp)
        mock.portrait:ClearAllPoints()
        if mock.portrait.border and mock.portrait.border.SetFrameLevel and mock.portrait.GetFrameLevel then
            mock.portrait.border:SetFrameLevel((mock.portrait:GetFrameLevel() or 1) + 1)
        end
        local ox = S(tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.x) or tonumber(PortraitStyleGet(key, "portraitOffsetX", 0)) or 0)
        local oy = S(tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.y) or tonumber(PortraitStyleGet(key, "portraitOffsetY", 0)) or 0)
        if mode == "RIGHT" then mock.portrait:SetPoint("LEFT", mock, "RIGHT", ox, oy)
        else mock.portrait:SetPoint("RIGHT", mock, "LEFT", ox, oy) end
        local cr, cg, cb = ClassColor(data.class)
        local renderMode = (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.render) or PortraitStyleGet(key, "portraitRender", "2D")
        if renderMode == "CLASS" then
            local visual = ClassPortraitVisual(data.class, (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.classStyle) or PortraitStyleGet(key, "portraitClassStyle", "BLIZZARD"))
            if visual and visual.atlas and mock.portrait.tex.SetAtlas then
                mock.portrait.tex:SetAtlas(visual.atlas)
            else
                mock.portrait.tex:SetTexture(visual and visual.texture or "Interface\\ICONS\\INV_Misc_QuestionMark")
                if mock.portrait.tex.SetTexCoord then
                    mock.portrait.tex:SetTexCoord(
                        (visual and visual.left) or 0,
                        (visual and visual.right) or 1,
                        (visual and visual.top) or 0,
                        (visual and visual.bottom) or 1
                    )
                end
            end
            if mock.portrait.tex.SetVertexColor then mock.portrait.tex:SetVertexColor(1, 1, 1, 1) end
            mock.portrait.initial:Hide()
        else
            mock.portrait.tex:SetTexture(UnitPreviewPortraitTexture(key, data))
            if mock.portrait.tex.SetVertexColor then mock.portrait.tex:SetVertexColor(1, 1, 1, 1) end
            if mock.portrait.tex.SetTexCoord then
                mock.portrait.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            mock.portrait.initial:Hide()
        end
        local portraitBg = runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.bg
        if (portraitBg and portraitBg.enabled == true) or (not (runtimeSpec and runtimeSpec.portrait) and PortraitStyleGet(key, "portraitBgEnabled", false) == true) then
            if mock.portrait.bg then
                mock.portrait.bg:SetVertexColor(
                    (portraitBg and portraitBg.r) or g.portraitBgColorR or 0.05,
                    (portraitBg and portraitBg.g) or g.portraitBgColorG or 0.05,
                    (portraitBg and portraitBg.b) or g.portraitBgColorB or 0.05,
                    (portraitBg and portraitBg.a) or g.portraitBgColorA or 0.85
                )
                mock.portrait.bg:Show()
            end
            mock.portrait:SetBackdropColor(0, 0, 0, 0)
        else
            if mock.portrait.bg then mock.portrait.bg:Hide() end
            mock.portrait:SetBackdropColor(0, 0, 0, 0)
        end
        local portraitBorder = runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.border
        local bStyle = box._runtimePortraitBorderStyle or (portraitBorder and portraitBorder.style) or PortraitStyleGet(key, "portraitBorderStyle", "NONE")
        if bStyle == "NONE" then
            LayoutPreviewPortraitBorder(mock.portrait, 0, false)
        elseif bStyle == "CUSTOM" or bStyle == "SOLID" then
            LayoutPreviewPortraitBorder(
                mock.portrait,
                S(box._runtimePortraitBorderThickness),
                box._runtimePortraitBorderFill,
                (portraitBorder and portraitBorder.r) or g.portraitBorderColorR or 1,
                (portraitBorder and portraitBorder.g) or g.portraitBorderColorG or 1,
                (portraitBorder and portraitBorder.b) or g.portraitBorderColorB or 1,
                (portraitBorder and portraitBorder.a) or g.portraitBorderColorA or 1
            )
        elseif bStyle == "CLASS_COLOR" then
            LayoutPreviewPortraitBorder(mock.portrait, S(box._runtimePortraitBorderThickness), box._runtimePortraitBorderFill, cr, cg, cb, 1)
        elseif bStyle == "REACTION" then
            local hostile = (key == "target" or key == "boss" or key == "focus" or key == "focustarget")
            LayoutPreviewPortraitBorder(mock.portrait, S(box._runtimePortraitBorderThickness), box._runtimePortraitBorderFill, hostile and 1 or 0.1, hostile and 0.2 or 0.85, 0.1, 1)
        else
            LayoutPreviewPortraitBorder(mock.portrait, S(box._runtimePortraitBorderThickness), box._runtimePortraitBorderFill, 1, 1, 1, 1)
        end
        box.handlePortrait:SetSize(max(18, sp + ((box._runtimePortraitBorderFill and 0 or S(box._runtimePortraitBorderThickness)) * 2)), max(18, sp + ((box._runtimePortraitBorderFill and 0 or S(box._runtimePortraitBorderThickness)) * 2)))
        PlaceHandle(box.handlePortrait, mock.portrait)
    else
        mock.portrait:Hide()
        LayoutPreviewPortraitBorder(mock.portrait, 0, false)
        box.handlePortrait:Hide()
    end
    if castPreviewVisible then
        mock.cast:Show()
        if type(_G.MSUF_GetCastbarBackgroundColor) == "function" then
            local br, bg, bb, ba = _G.MSUF_GetCastbarBackgroundColor()
            mock.cast:SetBackdropColor(br or 0.10, bg or 0.10, bb or 0.10, ba or 0.85)
        end
        local scw, sch = max(20, S(castW)), max(6, S(castBarH))
        mock.cast:SetSize(scw, sch)
        if mock.cast.sizeTag then
            mock.cast.sizeTag:SetText(format("%d x %d", floor(castW + 0.5), floor(castBarH + 0.5)))
            mock.cast.sizeTag:Show()
        end
        mock.cast:ClearAllPoints()
        if castDetached then
            box._detachedCastPreview = true
            box._detachedCastBaseOffsetX, box._detachedCastBaseOffsetY = S(castOffsetX), S(castOffsetY)
            mock.cast:SetPoint("CENTER", canvas, "CENTER", box._detachedCastBaseOffsetX + panX, box._detachedCastBaseOffsetY + panY)
        elseif key == "player" then
            mock.cast:SetPoint("BOTTOM", mock, "TOP", S(castOffsetX), S(castOffsetY))
        else
            mock.cast:SetPoint("BOTTOMLEFT", mock, "TOPLEFT", S(castOffsetX), S(castOffsetY + ((key == "boss") and 2 or 0)))
        end
        local cr, cg, cb = 0.0, 0.9, 0.8
        if type(_G.MSUF_GetInterruptibleCastColor) == "function" then
            cr, cg, cb = _G.MSUF_GetInterruptibleCastColor()
        end
        mock.cast.fill:SetVertexColor(cr or 0.0, cg or 0.9, cb or 0.8, 1)
        local showIcon = CastbarShowIcon(key, g)
        mock.cast.icon:SetShown(showIcon)
        local iconX = ReadCastbarNum(g, key, "IconOffsetX", "bossCastIconOffsetX", 0)
        local iconY = ReadCastbarNum(g, key, "IconOffsetY", "bossCastIconOffsetY", 0)
        local iconSize = ReadCastbarNum(g, key, "IconSize", "bossCastIconSize", castBarH)
        if iconSize < 6 then iconSize = 6 elseif iconSize > 128 then iconSize = 128 end
        local sIcon = max(6, S(iconSize))
        local iconDetached = showIcon and (iconX ~= 0 or iconY ~= 0)
        if showIcon then
            mock.cast.icon:SetSize(sIcon, sIcon)
            mock.cast.icon:ClearAllPoints()
            mock.cast.icon:SetPoint("LEFT", mock.cast, "LEFT", S(iconX), S(iconY))
            box.handleCastbarIcon:SetSize(max(18, sIcon + 8), max(18, sIcon + 8))
            PlaceHandle(box.handleCastbarIcon, mock.cast.icon)
        else
            box.handleCastbarIcon:Hide()
        end
        mock.cast.fill:ClearAllPoints()
        if showIcon and not iconDetached then
            mock.cast.fill:SetPoint("TOPLEFT", mock.cast, "TOPLEFT", sIcon + S(1), -S(1))
        else
            mock.cast.fill:SetPoint("TOPLEFT", mock.cast, "TOPLEFT", S(1), -S(1))
        end
        local timeReserve = max(S(2), min(S(60), floor(scw * 0.34 + 0.5)))
        mock.cast.fill:SetPoint("BOTTOMRIGHT", mock.cast, "BOTTOMRIGHT", -timeReserve, S(1))
        local showText = CastbarShowText(key, g)
        mock.cast.text:SetShown(showText)
        if showText then
            local tr, tg, tb = fr, fg, fb
            if type(_G.MSUF_GetCastbarTextColor) == "function" then
                tr, tg, tb = _G.MSUF_GetCastbarTextColor()
            end
            mock.cast.text:SetTextColor(tr, tg, tb, 1)
            local textSize = ReadCastbarNum(g, key, "SpellNameFontSize", "bossCastSpellNameFontSize", g.castbarSpellNameFontSize or g.fontSize or 14)
            if not textSize or textSize <= 0 then textSize = g.fontSize or 14 end
            ApplyPreviewFont(mock.cast.text, max(7, S(textSize)))
            mock.cast.text:ClearAllPoints()
            local textX = ReadCastbarNum(g, key, "TextOffsetX", "bossCastTextOffsetX", 0)
            local textY = ReadCastbarNum(g, key, "TextOffsetY", "bossCastTextOffsetY", 0)
            mock.cast.text:SetPoint("LEFT", mock.cast.fill, "LEFT", S(2 + textX), S(textY))
            mock.cast.text:SetPoint("RIGHT", mock.cast.time, "LEFT", -S(6), 0)
            mock.cast.text:SetText(TR(key == "boss" and "Celestial Ruin" or "Arcane Surge"))
            box.handleCastbarText:SetSize(max(34, mock.cast.text:GetStringWidth() + 10), max(18, mock.cast.text:GetStringHeight() + 6))
            if not UnitPreviewText.PlaceHandleAroundRegions(box.handleCastbarText, canvas, { mock.cast.text }, 3) then
                PlaceHandle(box.handleCastbarText, mock.cast.text)
            end
        else
            box.handleCastbarText:Hide()
        end
        local showTime = key == "boss" and g.showBossCastTime ~= false
            or (key == "target" and g.showTargetCastTime ~= false)
            or (key == "focus" and g.showFocusCastTime ~= false)
            or (key == "player" and g.showPlayerCastTime ~= false)
        mock.cast.time:SetShown(showTime)
        mock.cast.time:SetText(FormatCastbarPreviewTime(g, key, 1.4, 2.0))
        if showTime then
            local timeX = ReadCastbarNum(g, key, "TimeOffsetX", "bossCastTimeOffsetX", g.castbarPlayerTimeOffsetX or -2)
            local timeY = ReadCastbarNum(g, key, "TimeOffsetY", "bossCastTimeOffsetY", g.castbarPlayerTimeOffsetY or 0)
            if key == "boss" then
                timeX = -2 + (tonumber(g.bossCastTimeOffsetX) or 0)
                timeY = tonumber(g.bossCastTimeOffsetY) or 0
            end
            local timeSize = ReadCastbarNum(g, key, "TimeFontSize", "bossCastTimeFontSize", g.castbarTimeFontSize or g.fontSize or 14)
            if not timeSize or timeSize <= 0 then timeSize = g.fontSize or 14 end
            ApplyPreviewFont(mock.cast.time, max(7, S(timeSize)))
            mock.cast.time:ClearAllPoints()
            mock.cast.time:SetPoint("RIGHT", mock.cast.fill, "RIGHT", S(timeX), S(timeY))
            box.handleCastbarTime:SetSize(max(28, mock.cast.time:GetStringWidth() + 10), max(18, mock.cast.time:GetStringHeight() + 6))
            if not UnitPreviewText.PlaceHandleAroundRegions(box.handleCastbarTime, canvas, { mock.cast.time }, 3) then
                PlaceHandle(box.handleCastbarTime, mock.cast.time)
            end
        else
            box.handleCastbarTime:Hide()
        end
        box.handleCastbar:SetSize(max(36, scw), max(18, sch + 8))
        PlaceHandle(box.handleCastbar, mock.cast)
    else
        mock.cast:Hide()
        if mock.cast.sizeTag then mock.cast.sizeTag:Hide() end
        box.handleCastbar:Hide()
        box.handleCastbarIcon:Hide()
        box.handleCastbarText:Hide()
        box.handleCastbarTime:Hide()
    end
    if Auras and Auras.Layout then
        Auras.Layout(box, mock, auraPreviewState, S, baseLevel)
    end
    local statusLayerAvailable = false
    for i = 1, #D.STATUS_PREVIEW do
        local spec = D.STATUS_PREVIEW[i]
        local icon = mock.icons[spec.id]
        local handle = box.statusHandles[spec.id]
        local statusCfg = runtimeStatus and runtimeStatus[STATUS_RUNTIME_KEYS[spec.id]]
        local show
        if statusCfg then
            show = statusCfg.enabled == true
        else
            local showVal = conf[spec.show]
            if showVal == nil then showVal = g[spec.show] end
            show = (showVal == nil) and (spec.defaultShow ~= false) or (showVal ~= false)
        end
        if spec.allowed and not spec.allowed(key) then show = false end
        if spec.id == "elite" and not data.elite then show = false end
        if spec.id == "statusText" and PreviewStatus.StatusTextPreviewText then
            show = show and PreviewStatus.StatusTextPreviewText(statusCfg or g) ~= nil
        end
        if Preview.GetStatusPreviewMode() ~= "all" then
            local selected = NormalizeStatusPreviewId(Preview.selectedStatusId)
            if selected == "" then selected = "raidmarker" end
            show = show and (spec.id == selected)
        end
        icon:SetShown(show)
        if show then
            statusLayerAvailable = true
            local rawSize = tonumber(statusCfg and statusCfg.size) or tonumber(conf[spec.size]) or tonumber(g[spec.size])
            if rawSize == nil then
                if spec.id == "level" then
                    rawSize = nameRawSize
                elseif spec.id == "statusText" then
                    rawSize = nameRawSize + 2
                else
                    rawSize = spec.defaultSize
                end
            end
            local sz = S(rawSize)
            if spec.id == "level" then
                if sz < 7 then sz = 7 end
            elseif sz < 10 then
                sz = 10
            end
            if icon.SetFrameLevel then
                local rawLayer = tonumber(statusCfg and statusCfg.layer) or (spec.layer and (tonumber(conf[spec.layer]) or tonumber(g[spec.layer]))) or spec.defaultLayer
                icon:SetFrameLevel(textBase + ClampPreviewLayer(rawLayer, spec.defaultLayer or 7))
            end
            SetPreviewIconTexture(icon, spec, conf, g, key, data, statusCfg)
            if spec.id == "level" then
                local anchor, x, y = StatusAnchorOffsets(spec, statusCfg)
                if icon.txt then
                    ApplyPreviewFont(icon.txt, max(7, sz))
                    icon.txt:ClearAllPoints()
                    icon.txt:SetPoint("LEFT", icon, "LEFT", 0, 0)
                    icon.txt:SetJustifyH("LEFT")
                end
                local textW = icon.txt and icon.txt.GetStringWidth and icon.txt:GetStringWidth() or sz
                local textH = icon.txt and icon.txt.GetStringHeight and icon.txt:GetStringHeight() or sz
                icon:SetSize(max(1, floor((tonumber(textW) or sz) + 0.5)), max(1, floor((tonumber(textH) or sz) + 0.5)))
                PositionLevelPreview(icon, anchor, x, y, mock, S(6))
            elseif spec.id == "statusText" then
                local anchor, x, y = StatusAnchorOffsets(spec, statusCfg)
                if icon.txt then
                    ApplyPreviewFont(icon.txt, max(7, sz))
                    icon.txt:ClearAllPoints()
                    icon.txt:SetPoint("CENTER")
                    icon.txt:SetJustifyH("CENTER")
                end
                local textW = icon.txt and icon.txt.GetStringWidth and icon.txt:GetStringWidth() or sz
                local textH = icon.txt and icon.txt.GetStringHeight and icon.txt:GetStringHeight() or sz
                icon:SetSize(max(1, floor((tonumber(textW) or sz) + 0.5)), max(1, floor((tonumber(textH) or sz) + 0.5)))
                PositionSameAnchorPreview(icon, anchor, x, y, mock)
            else
                icon:SetSize(sz, sz)
                if icon.txt then
                    ApplyPreviewFont(icon.txt, max(7, floor(sz * 0.52 + 0.5)))
                    icon.txt:ClearAllPoints()
                    icon.txt:SetPoint("CENTER")
                    icon.txt:SetJustifyH("CENTER")
                end
                local anchor, x, y = StatusAnchorOffsets(spec, statusCfg)
                if spec.id == "raidmarker" then
                    PositionRuntimeLayoutIconPreview(icon, anchor, x, y, mock, true)
                elseif spec.id == "leader" or spec.id == "elite" then
                    PositionRuntimeLayoutIconPreview(icon, anchor, x, y, mock, false)
                elseif spec.id == "statusCombat" or spec.id == "statusResting" or spec.id == "statusIncomingRes" then
                    PositionStatusCornerPreview(icon, anchor, x, y, mock, S(2))
                else
                    PositionFromAnchor(icon, anchor, x, y, mock, sz)
                end
            end
            handle:SetSize(max(18, icon:GetWidth() + 8), max(18, icon:GetHeight() + 8))
            PlaceHandle(handle, icon)
        else
            handle:Hide()
        end
    end
    if showRaidGroupName then
        statusLayerAvailable = true
    end
    box.layerAvailable = {
        guides = true,
        body = true,
        nameText = showNamePreview,
        hpText = hpTextOn,
        powerText = powerTextOn,
        portrait = hasPortrait,
        power = powerEnabled == true,
        classPower = classPowerOn,
        castbar = castEnabled,
        auras = auraPreviewState ~= nil,
        status = statusLayerAvailable,
        bounds = true,
    }
    for i = 1, #(box.layerButtons or {}) do
        if box.layerButtons[i].refresh then box.layerButtons[i]:refresh() end
    end
    local nameHandleW = mock.nameText:GetStringWidth() + 10
    if mock.totInlineSep and mock.totInlineSep:IsShown() then
        nameHandleW = nameHandleW + mock.totInlineSep:GetStringWidth() + mock.totInlineText:GetStringWidth() + S(8)
    end
    box.handleName:SetSize(max(46, nameHandleW), max(18, mock.nameText:GetStringHeight() + 6))
    if not UnitPreviewText.PlaceHandleAroundRegions(box.handleName, canvas, { mock.nameText, mock.totInlineSep, mock.totInlineText }, 3) then
        PlaceHandle(box.handleName, mock.nameText)
    end
    local function PlaceTextSlotHandle(handle, region)
        if not handle then return end
        if not (region and region.IsShown and region:IsShown()) then
            handle:Hide()
            return
        end
        local w = (region.GetStringWidth and region:GetStringWidth()) or region:GetWidth() or 36
        local h = (region.GetStringHeight and region:GetStringHeight()) or region:GetHeight() or 12
        handle:SetSize(max(26, w + 10), max(18, h + 6))
        if not UnitPreviewText.PlaceHandleAroundRegions(handle, canvas, { region }, 3) then
            PlaceHandle(handle, region)
        end
    end
    PlaceTextSlotHandle(box.handleRaidGroupName, mock.raidGroupNameText)
    if UnitPreviewTextMovesTogether(key, "hp") then
        SetShownSafe(box.handleHPLeft, false)
        SetShownSafe(box.handleHPCenter, false)
        SetShownSafe(box.handleHPRight, false)
        if not UnitPreviewText.PlaceHandleAroundRegions(box.handleHP, canvas, { mock.hpTextLeft, mock.hpTextCenter, mock.hpText }, 3) then
            if not ((mock.hpTextLeft and mock.hpTextLeft:IsShown()) or (mock.hpTextCenter and mock.hpTextCenter:IsShown()) or (mock.hpText and mock.hpText:IsShown())) then
                box.handleHP:Hide()
            else
                box.handleHP:SetSize(max(46, mock.hpText:GetStringWidth() + 10), max(18, mock.hpText:GetStringHeight() + 6))
                PlaceHandle(box.handleHP, mock.hpText)
            end
        end
    else
        if box.handleHP then box.handleHP:Hide() end
        PlaceTextSlotHandle(box.handleHPLeft, mock.hpTextLeft)
        PlaceTextSlotHandle(box.handleHPCenter, mock.hpTextCenter)
        PlaceTextSlotHandle(box.handleHPRight, mock.hpText)
    end
    if UnitPreviewTextMovesTogether(key, "power") then
        SetShownSafe(box.handlePowerLeft, false)
        SetShownSafe(box.handlePowerCenter, false)
        SetShownSafe(box.handlePowerRight, false)
        if not UnitPreviewText.PlaceHandleAroundRegions(box.handlePower, canvas, { mock.powerTextLeft, mock.powerTextCenter, mock.powerText }, 3) then
            if not ((mock.powerTextLeft and mock.powerTextLeft:IsShown()) or (mock.powerTextCenter and mock.powerTextCenter:IsShown()) or (mock.powerText and mock.powerText:IsShown())) then
                box.handlePower:Hide()
            else
                box.handlePower:SetSize(max(46, mock.powerText:GetStringWidth() + 10), max(18, mock.powerText:GetStringHeight() + 6))
                PlaceHandle(box.handlePower, mock.powerText)
            end
        end
    else
        if box.handlePower then box.handlePower:Hide() end
        PlaceTextSlotHandle(box.handlePowerLeft, mock.powerTextLeft)
        PlaceTextSlotHandle(box.handlePowerCenter, mock.powerTextCenter)
        PlaceTextSlotHandle(box.handlePowerRight, mock.powerText)
    end
    ApplyPreviewTextFocus(box, canvas, mock)
    ApplyPreviewLayerVisibility(box)
    ApplyPreviewTransparency(box, conf)
    RefreshHandleSelectionVisuals(box)
end
end
