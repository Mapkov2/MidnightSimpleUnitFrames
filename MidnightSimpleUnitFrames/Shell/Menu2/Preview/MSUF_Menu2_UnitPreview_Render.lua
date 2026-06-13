--- Unit preview render/composition.
---
--- The view file builds frames and wires controls; this module owns the hot
--- refresh path that composes the live preview visuals.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF
local Render = MSUF.UFPreviewRender or {}
MSUF.UFPreviewRender = Render
local MenuState = MSUF.MSUF2 or _G.MSUF2 or {}
local Pick, PickFallbackTable = MenuState.Pick, MenuState.PickFallbackTable
local F = MenuState.Fallbacks or {}
local PreviewHelpers = MenuState.PreviewHelpers or {}
local CPPreview = MenuState.ClassPowerPreview or {}
local function CastbarPreviewDetailPrefix(unitKey)
    if unitKey == "player" then return "castbarPlayer" end
    if unitKey == "target" then return "castbarTarget" end
    if unitKey == "focus" then return "castbarFocus" end
    if unitKey == "boss" then return "bossCast" end
    return nil
end
local function ReadCastbarPreviewString(g, key, detailPrefix, suffix, bossKey, fallback)
    local value = detailPrefix and g[detailPrefix .. suffix] or nil
    if (value == nil or value == "") and key == "boss" and bossKey then value = g[bossKey] end
    if value == nil or value == "" then value = fallback end
    return tostring(value or fallback or "")
end
local function NormalizeCastbarPreviewIconPos(value)
    value = tostring(value or "LEFT"):upper():gsub("%s+", "_"):gsub("-", "_")
    if value == "INSIDELEFT" then value = "INSIDE_LEFT" end
    if value == "INSIDERIGHT" then value = "INSIDE_RIGHT" end
    if value == "RIGHT" or value == "INSIDE_LEFT" or value == "INSIDE_RIGHT" then return value end
    return "LEFT"
end
local function NormalizeCastbarPreviewTextPos(value, fallback)
    value = tostring(value or fallback or "LEFT"):upper():gsub("%s+", "_"):gsub("-", "_")
    if value == "CENTER" or value == "RIGHT" or value == "ABOVE" or value == "BELOW" then return value end
    return "LEFT"
end
local function NormalizeCastbarPreviewJustify(value, fallback)
    value = tostring(value or fallback or "LEFT"):upper()
    if value == "CENTER" or value == "RIGHT" then return value end
    return "LEFT"
end
local PREVIEW_CLASS_POWER_SHAPES = CPPreview.CLASS_SHAPES
local PREVIEW_POWER_SHAPES = CPPreview.POWER_SHAPES
local NormalizePreviewClassPowerShape = CPPreview.NormalizeClassShape
local function NormalizePreviewClassPowerShapeAlign(value)
    value = tostring(value or "CENTER"):upper()
    if value == "LEFT" or value == "RIGHT" then return value end
    return "CENTER"
end
local function PreviewClassPowerSegmentCount(spec, limit)
    local count = math.floor(tonumber(spec and spec.segments) or 5)
    if count < 1 then count = 1 end
    limit = tonumber(limit) or 10
    if count > limit then count = limit end
    return count
end
local function PreviewClassPowerAutoFitWidth(segCount, height, gap)
    segCount = math.floor(tonumber(segCount) or 1)
    if segCount < 1 then segCount = 1 elseif segCount > 10 then segCount = 10 end
    height = math.floor(tonumber(height) or 1)
    if height < 1 then height = 1 end
    gap = math.floor(tonumber(gap) or 0)
    if gap < 0 then gap = 0 elseif gap > 8 then gap = 8 end
    return (segCount * height) + ((segCount - 1) * gap)
end
local function PreviewClassPowerWidth(bars, frameW, cpH, segCount)
    bars = bars or {}
    local shape = NormalizePreviewClassPowerShape(bars.classPowerShape)
    if PREVIEW_CLASS_POWER_SHAPES[shape] and bars.classPowerWidthMode == "auto_pips" then
        local w = PreviewClassPowerAutoFitWidth(segCount, cpH, bars.classPowerGap)
        if w < 1 then w = 1 elseif w > 800 then w = 800 end
        return w
    end
    local w = (bars.classPowerWidthMode == "custom") and (tonumber(bars.classPowerWidth) or (frameW - 4)) or (frameW - 4)
    if w < 30 then w = frameW - 4 elseif w > 800 then w = 800 end
    return w
end
local ResolvePreviewPowerShape = CPPreview.ResolvePowerShape
local function PreviewShapeOutlineAlpha(value)
    value = tonumber(value) or 0
    if value <= 0 then return 0 end
    if value >= 8 then return 1 end
    return 0.49 + (value * 0.065)
end
local function NormalizeCastbarPreviewTruncate(value)
    value = tostring(value or "AUTO"):upper()
    if value == "CLIP" or value == "NONE" then return value end
    return "AUTO"
end
local function ShortenCastbarPreviewSpellName(key, text, truncate)
    if truncate ~= "AUTO" then return text end
    local shorten = _G.MSUF_ShortenCastbarSpellName
    if type(shorten) ~= "function" then return text end
    return shorten({ unit = key == "boss" and "boss1" or key }, text)
end
local function ApplyCastbarPreviewIconBorder(icon, style, g)
    if not (icon and icon.SetBackdropBorderColor) then return end
    style = tostring(style or "NONE"):upper()
    if style == "DARK" then
        icon:SetBackdropBorderColor(0, 0, 0, 0.95)
    elseif style == "CASTBAR" then
        icon:SetBackdropBorderColor(g.castbarBorderR or 0, g.castbarBorderG or 0, g.castbarBorderB or 0, g.castbarBorderA or 1)
    else
        icon:SetBackdropBorderColor(0, 0, 0, 0)
    end
end
local function AnchorCastbarPreviewText(fs, relativeTo, position, x, y, justify, S)
    fs:ClearAllPoints()
    if position == "CENTER" then
        fs:SetPoint("CENTER", relativeTo, "CENTER", S(x), S(y))
        fs:SetJustifyH(justify or "CENTER")
    elseif position == "RIGHT" then
        fs:SetPoint("RIGHT", relativeTo, "RIGHT", S(x), S(y))
        fs:SetJustifyH(justify or "RIGHT")
    elseif position == "ABOVE" then
        fs:SetPoint("BOTTOM", relativeTo, "TOP", S(x), S(y + 2))
        fs:SetJustifyH(justify or "CENTER")
    elseif position == "BELOW" then
        fs:SetPoint("TOP", relativeTo, "BOTTOM", S(x), S(y - 2))
        fs:SetJustifyH(justify or "CENTER")
    else
        fs:SetPoint("LEFT", relativeTo, "LEFT", S(2 + x), S(y))
        fs:SetJustifyH(justify or "LEFT")
    end
end
local function ApplyPreviewFontSet(apply, size, ...)
    for i = 1, select("#", ...) do apply(select(i, ...), size) end
end
local function SetTextColorSet(r, g, b, a, ...)
    for i = 1, select("#", ...) do select(i, ...):SetTextColor(r, g, b, a) end
end
local function SetLeftSpan(region, parent, x, y) region:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0); region:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x or 0, y or 0) end
local function SetRightSpan(region, parent, x, y) region:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x or 0, y or 0); region:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", x or 0, y or 0) end
local function SetBottomSpan(region, parent, leftX, rightX, y) region:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", leftX or 0, y or 0); region:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", rightX or 0, y or 0) end
local function NumberOrOne(value) return tonumber(value) or 1 end
local function CastbarNumFallback(_, _, fallback) return tonumber(fallback) or 0 end
local function CastbarTimeFallback(value) return tostring(value or "") end
local function ResolveNameAnchorFallback(_, x) return "LEFT", "LEFT", x or 0, "LEFT" end
local UNIT_RENDER_FALLBACKS = {
    RuntimeSpecForPreviewKey = F.Nil, RuntimeVisualScaleForPreviewKey = F.One, ClampPreviewZoom = NumberOrOne, UpdatePreviewZoomControls = F.Noop,
    ApplyPreviewRounded = F.Noop, ApplyPreviewFrameBorder = F.Noop, PreviewRoundedOutlineThickness = F.One, ApplyPreviewBoundsGuide = F.Noop,
    CastbarShowIcon = F.True, CastbarShowText = F.TruePair, ReadCastbarNum = CastbarNumFallback, FormatCastbarPreviewTime = CastbarTimeFallback,
    ClassColor = F.WhiteRGB, HealthColor = F.HealthRGB, HealthBackgroundColor = F.DarkRGBA, PowerBackgroundColor = F.DarkRGBA, PowerColor = F.PowerRGB, FontColor = F.WhiteRGB,
    PreviewResolveHealPredAnchorMode = F.Right, PreviewResolveAbsorbAnchorMode = F.Right, PreviewHealPredictionEnabled = F.False, PreviewAbsorbBarEnabled = F.False,
    PreviewNameColor = F.WhiteRGB, PreviewToTInlineColor = F.WhiteRGB, NormalizeHpMode = F.Identity, NormalizePowerMode = F.Identity,
    TextScopeGet = F.Nil, TextScopeHasSlots = F.False, TextScopeSlotGet = F.Nil, FormatMode = F.Empty, ShortenPreviewName = F.Identity, ToTInlineSeparator = F.Identity,
    ResolveNameAnchor = ResolveNameAnchorFallback, LayoutUnitPreviewOverlay = F.Noop, PositionFromAnchor = F.Noop, PositionRuntimeLayoutIconPreview = F.Noop,
    PositionStatusCornerPreview = F.Noop, PositionSameAnchorPreview = F.Noop, PositionLevelPreview = F.Noop, ResolveStatusPreviewAnchor = F.Center,
    SetPreviewIconTexture = F.Noop, NormalizeStatusPreviewId = F.Identity, ApplyPreviewTextFocus = F.Noop,
}

--- Castbar preview detail layout mirrors the live CastbarVisuals rules without
--- subscribing to spellcast events. Keep all data reads profile/local here.
local function ApplyCastbarPreviewDetails(box, mock, canvas, g, key, castBarH, scw, S, max, min, floor, fr, fg, fb, TR, ApplyPreviewFont, CastbarShowIcon, CastbarShowText, ReadCastbarNum, FormatCastbarPreviewTime, UnitPreviewText, PlaceHandle)
    local detailPrefix = CastbarPreviewDetailPrefix(key)
    local showIcon = CastbarShowIcon(key, g)
    mock.cast.icon:SetShown(showIcon)
    local iconX = ReadCastbarNum(g, key, "IconOffsetX", "bossCastIconOffsetX", 0)
    local iconY = ReadCastbarNum(g, key, "IconOffsetY", "bossCastIconOffsetY", 0)
    local iconSize = ReadCastbarNum(g, key, "IconSize", "bossCastIconSize", castBarH)
    if iconSize < 6 then iconSize = 6 elseif iconSize > 128 then iconSize = 128 end
    local sIcon = max(6, S(iconSize))
    local iconPosition = NormalizeCastbarPreviewIconPos(ReadCastbarPreviewString(g, key, detailPrefix, "IconPosition", "bossCastIconPosition", "LEFT"))
    local iconSpacing = max(0, min(40, ReadCastbarNum(g, key, "IconSpacing", "bossCastIconSpacing", 1)))
    local iconBorderStyle = ReadCastbarPreviewString(g, key, detailPrefix, "IconBorderStyle", "bossCastIconBorderStyle", "NONE")
    if showIcon then
        ApplyCastbarPreviewIconBorder(mock.cast.icon, iconBorderStyle, g)
        mock.cast.icon:SetSize(sIcon, sIcon)
        mock.cast.icon:ClearAllPoints()
        if iconPosition == "RIGHT" then
            mock.cast.icon:SetPoint("RIGHT", mock.cast, "RIGHT", S(iconX), S(iconY))
        elseif iconPosition == "INSIDE_RIGHT" then
            mock.cast.icon:SetPoint("RIGHT", mock.cast, "RIGHT", S(iconX - iconSpacing), S(iconY))
        elseif iconPosition == "INSIDE_LEFT" then
            mock.cast.icon:SetPoint("LEFT", mock.cast, "LEFT", S(iconX + iconSpacing), S(iconY))
        else
            mock.cast.icon:SetPoint("LEFT", mock.cast, "LEFT", S(iconX), S(iconY))
        end
        box.handleCastbarIcon:SetSize(max(18, sIcon + 8), max(18, sIcon + 8))
        PlaceHandle(box.handleCastbarIcon, mock.cast.icon)
    else
        box.handleCastbarIcon:Hide()
    end
    mock.cast.fill:ClearAllPoints()
    if showIcon and iconPosition == "LEFT" then
        mock.cast.fill:SetPoint("TOPLEFT", mock.cast, "TOPLEFT", sIcon + S(iconSpacing), -S(1))
    else
        mock.cast.fill:SetPoint("TOPLEFT", mock.cast, "TOPLEFT", S(1), -S(1))
    end
    local timeReserve = max(S(2), min(S(60), floor(scw * 0.34 + 0.5)))
    if showIcon and iconPosition == "RIGHT" then
        mock.cast.fill:SetPoint("BOTTOMRIGHT", mock.cast, "BOTTOMRIGHT", -(sIcon + S(iconSpacing)), S(1))
    else
        mock.cast.fill:SetPoint("BOTTOMRIGHT", mock.cast, "BOTTOMRIGHT", -timeReserve, S(1))
    end
    local showText = CastbarShowText(key, g)
    mock.cast.text:SetShown(showText)
    if showText then
        local tr, tg, tb = fr, fg, fb
        if type(_G.MSUF_GetCastbarTextColor) == "function" then tr, tg, tb = _G.MSUF_GetCastbarTextColor() end
        tr = g[(detailPrefix or "") .. "SpellNameColorR"] or tr
        tg = g[(detailPrefix or "") .. "SpellNameColorG"] or tg
        tb = g[(detailPrefix or "") .. "SpellNameColorB"] or tb
        mock.cast.text:SetTextColor(tr, tg, tb, 1)
        local textSize = ReadCastbarNum(g, key, "SpellNameFontSize", "bossCastSpellNameFontSize", g.castbarSpellNameFontSize or g.fontSize or 14)
        if not textSize or textSize <= 0 then textSize = g.fontSize or 14 end
        ApplyPreviewFont(mock.cast.text, max(7, S(textSize)))
        local textX = ReadCastbarNum(g, key, "TextOffsetX", "bossCastTextOffsetX", 0)
        local textY = ReadCastbarNum(g, key, "TextOffsetY", "bossCastTextOffsetY", 0)
        local textPosition = NormalizeCastbarPreviewTextPos(ReadCastbarPreviewString(g, key, detailPrefix, "SpellNamePosition", "bossCastSpellNamePosition", "LEFT"), "LEFT")
        local textJustify = NormalizeCastbarPreviewJustify(ReadCastbarPreviewString(g, key, detailPrefix, "SpellNameAlign", "bossCastSpellNameAlign", textPosition == "RIGHT" and "RIGHT" or textPosition == "CENTER" and "CENTER" or "LEFT"), "LEFT")
        AnchorCastbarPreviewText(mock.cast.text, mock.cast.fill, textPosition, textX, textY, textJustify, S)
        local textMaxWidth = ReadCastbarNum(g, key, "SpellNameMaxWidth", "bossCastSpellNameMaxWidth", 0)
        local truncate = NormalizeCastbarPreviewTruncate(ReadCastbarPreviewString(g, key, detailPrefix, "SpellNameTruncate", "bossCastSpellNameTruncate", "AUTO"))
        local spellName = ShortenCastbarPreviewSpellName(key, TR(key == "boss" and "Celestial Ruin" or "Arcane Surge"), truncate)
        mock.cast.text:SetText(spellName)
        if truncate == "NONE" then
            local naturalWidth = (mock.cast.text.GetStringWidth and mock.cast.text:GetStringWidth()) or scw
            mock.cast.text:SetWidth(max(20, scw, naturalWidth + 10))
        elseif textMaxWidth and textMaxWidth > 0 then
            mock.cast.text:SetWidth(textMaxWidth)
        else
            mock.cast.text:SetWidth(max(20, scw - timeReserve - 10))
        end
        box.handleCastbarText:SetSize(max(34, mock.cast.text:GetStringWidth() + 10), max(18, mock.cast.text:GetStringHeight() + 6))
        if not UnitPreviewText.PlaceHandleAroundRegions(box.handleCastbarText, canvas, { mock.cast.text }, 3) then PlaceHandle(box.handleCastbarText, mock.cast.text) end
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
        local tr, tg, tb = g[(detailPrefix or "") .. "TimeColorR"], g[(detailPrefix or "") .. "TimeColorG"], g[(detailPrefix or "") .. "TimeColorB"]
        if tr or tg or tb then mock.cast.time:SetTextColor(tr or fr, tg or fg, tb or fb, 1) else mock.cast.time:SetTextColor(fr, fg, fb, 1) end
        local timePosition = NormalizeCastbarPreviewTextPos(ReadCastbarPreviewString(g, key, detailPrefix, "TimePosition", "bossCastTimePosition", "RIGHT"), "RIGHT")
        AnchorCastbarPreviewText(mock.cast.time, mock.cast.fill, timePosition, timeX, timeY, timePosition == "LEFT" and "LEFT" or timePosition == "CENTER" and "CENTER" or "RIGHT", S)
        box.handleCastbarTime:SetSize(max(28, mock.cast.time:GetStringWidth() + 10), max(18, mock.cast.time:GetStringHeight() + 6))
        if not UnitPreviewText.PlaceHandleAroundRegions(box.handleCastbarTime, canvas, { mock.cast.time }, 3) then PlaceHandle(box.handleCastbarTime, mock.cast.time) end
    else
        box.handleCastbarTime:Hide()
    end
end

--- Install render helpers onto the shared unit-preview object. View owns frame
--- construction; this module owns repeated visual composition.
function Render.Install(Preview, deps)
    if type(Preview) ~= "table" then return end
    deps = deps or Preview.RefreshDeps or {}
    Preview.RefreshDeps = deps
    local renderState = PickFallbackTable(deps, UNIT_RENDER_FALLBACKS, [[
        RuntimeSpecForPreviewKey RuntimeVisualScaleForPreviewKey ClampPreviewZoom UpdatePreviewZoomControls
        ApplyPreviewRounded ApplyPreviewFrameBorder PreviewRoundedOutlineThickness ApplyPreviewBoundsGuide CastbarShowIcon CastbarShowText ReadCastbarNum FormatCastbarPreviewTime
        ClassColor HealthColor HealthBackgroundColor PowerBackgroundColor PowerColor FontColor PreviewResolveHealPredAnchorMode PreviewResolveAbsorbAnchorMode PreviewHealPredictionEnabled PreviewAbsorbBarEnabled
        PreviewNameColor PreviewToTInlineColor NormalizeHpMode NormalizePowerMode TextScopeGet TextScopeHasSlots TextScopeSlotGet FormatMode ShortenPreviewName ToTInlineSeparator ResolveNameAnchor
        LayoutUnitPreviewOverlay PositionFromAnchor PositionRuntimeLayoutIconPreview PositionStatusCornerPreview PositionSameAnchorPreview PositionLevelPreview ResolveStatusPreviewAnchor SetPreviewIconTexture NormalizeStatusPreviewId
    ]])
    renderState.ZOOM_MIN = tonumber(deps.ZOOM_MIN) or 0.35
    renderState.UnitPreviewPortraitTexture = deps.UnitPreviewPortraitTexture
    renderState.ClassPortraitVisual = deps.ClassPortraitVisual
    renderState.PreviewStatus = MSUF.UFPreviewStatus or {}
    renderState.STATUS_RUNTIME_KEYS = { raidmarker = "raidMarker", leader = "leader", level = "level", elite = "elite", statusText = "statusText", statusCombat = "combat", statusResting = "resting", statusIncomingRes = "incomingRes", statusPvp = "pvp" }
    renderState.ApplyPreviewTextFocus = deps.ApplyPreviewTextFocus or UNIT_RENDER_FALLBACKS.ApplyPreviewTextFocus
    local PowerColor = renderState.PowerColor
    local SharedCPPreview = MenuState.ClassPowerPreview or {}
    local function FallbackBase(_, _, r, g, b) return r or 1, g or 1, b or 1 end
    local function FallbackColor(_, r, g, b) return r or 1, g or 1, b or 1 end
    local function FallbackText(r, g, b) return r or 1, g or 1, b or 1 end
    local function FallbackFill(spec, index) return spec and index <= math.floor(tonumber(spec.value) or 0) and 1 or 0 end
    local function FallbackCombo(_, _, r, g, b) return r, g, b end
    local CPPreview = {
        BuildRuneOrder = SharedCPPreview.BuildRuneOrder or F.Nil,
        ColorOverride = SharedCPPreview.ColorOverride or F.Nil,
        FillForSegment = SharedCPPreview.FillForSegment or FallbackFill,
        FormatSeconds = SharedCPPreview.FormatSeconds or F.Empty,
        IsCharged = SharedCPPreview.IsCharged or F.False,
        ResolveComboColor = SharedCPPreview.ResolveComboColor or FallbackCombo,
        ResolveBaseColor = function(spec, bars, fallbackR, fallbackG, fallbackB)
            return (SharedCPPreview.ResolveBaseColor or FallbackBase)(spec, bars, fallbackR, fallbackG, fallbackB, PowerColor)
        end,
        ResolveColor = function(token, fallbackR, fallbackG, fallbackB)
            return (SharedCPPreview.ResolveColor or FallbackColor)(token, fallbackR, fallbackG, fallbackB, PowerColor)
        end,
        ResolveTextColor = function(fallbackR, fallbackG, fallbackB)
            return (SharedCPPreview.ResolveTextColor or FallbackText)(fallbackR, fallbackG, fallbackB, PowerColor)
        end,
    }
    local fallbackFont = deps.FONT or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    if type(deps.ApplyPreviewFont) ~= "function" then
        deps.ApplyPreviewFont = function(fs, size)
            if not (fs and fs.SetFont) then return end
            size = tonumber(size) or 12
            local fontPath, fontFlags, _, _, _, _, useShadow
            local gfs = _G.MSUF_GetGlobalFontSettings
            if type(gfs) == "function" then
                local ok, path, flags, _, _, _, _, shadow = pcall(gfs)
                if ok then fontPath, fontFlags, useShadow = path, flags, shadow end
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
                if type(pathForKey) == "function" and fontKey then fontPath = pathForKey(fontKey, size, fontFlags) end
            end
            if type(fontPath) ~= "string" or fontPath == "" then fontPath = fallbackFont end
            local safeSetFont = _G.MSUF_SetFontSafe
            if type(safeSetFont) == "function" then
                safeSetFont(fs, fontPath, size, fontFlags, fontKey)
            else
                fs:SetFont(fontPath, size, fontFlags)
            end
            if fs.SetShadowOffset then
                if useShadow == nil then useShadow = not (general and general.textBackdrop == false) end
                if useShadow then
                    local strength = tostring(general and general.fontShadowStrength or "NORMAL"):upper()
                    local shadowAlpha, shadowX, shadowY = 1, 1, -1
                    if strength == "SOFT" then shadowAlpha, shadowX, shadowY = 0.55, 1, -1
                    elseif strength == "DEEP" then shadowAlpha, shadowX, shadowY = 1, 2, -2 end
                    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, shadowAlpha) end
                    fs:SetShadowOffset(shadowX, shadowY)
                else
                    fs:SetShadowOffset(0, 0)
                end
            end
        end
    end
    local function LayoutPreviewPortraitBorder(portrait, thickness, fill, r, g, b, a)
        local border = portrait and portrait.border
        if not border then return end
        if not r then
            if PreviewHelpers.SetEdgeLinesShown then PreviewHelpers.SetEdgeLinesShown(border, false, border._msufPreviewEdgeOpts) end
            border:Hide()
            return
        end
        thickness = math.floor((tonumber(thickness) or 1) + 0.5)
        if thickness < 1 then thickness = 1 end
        if thickness > 30 then thickness = 30 end
        local key = thickness .. "|" .. (fill and "1" or "0")
        if portrait._previewBorderKey ~= key then
            border:ClearAllPoints()
            if fill then
                border:SetAllPoints(portrait)
            else
                border:SetPoint("TOPLEFT", portrait, "TOPLEFT", -thickness, thickness)
                border:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", thickness, -thickness)
            end
            portrait._previewBorderKey = key
        end
        border._msufPreviewEdgeR, border._msufPreviewEdgeG, border._msufPreviewEdgeB, border._msufPreviewEdgeA = r, g, b, a or 1
        border._msufPreviewEdgeOpts = border._msufPreviewEdgeOpts or {
            linesKey = "edges",
            maxEdgeSize = 30,
            color = function(frame)
                return frame._msufPreviewEdgeR or 1, frame._msufPreviewEdgeG or 1, frame._msufPreviewEdgeB or 1, frame._msufPreviewEdgeA or 1
            end,
        }
        if PreviewHelpers.LayoutEdgeLines then PreviewHelpers.LayoutEdgeLines(border, thickness, border._msufPreviewEdgeOpts) end
        border:Show()
    end
    renderState.CPPreview = CPPreview
    renderState.LayoutPreviewPortraitBorder = LayoutPreviewPortraitBorder
    deps._RenderState = renderState

--- Hot refresh for the unit preview. It composes current DB/model values into
--- mock regions and handle positions, but never mutates live unit frames.
function Preview.Refresh(box, reason)
    box = box or Preview.active
    if not box or not box:IsShown() then return end
    local D = Preview.RefreshDeps
    local R = D._RenderState or {}
    local PreviewInCombat = D.PreviewInCombat
    if PreviewInCombat() then return end
    local TR, PortraitStyleGet, max, min, abs, floor, format, TEX_W8, ApplyPreviewFont, CastbarEnabled, ReadCastbarSize, CastbarOffsetFields, CastbarDetached, CanDetachPowerBarKey, ClampPreviewLayer, SetTex, ReadPowerBarHeight, PlaceHandle, UnitPreviewText, UnitPreviewTextMovesTogether, SetShownSafe, ApplyPreviewLayerVisibility, ApplyPreviewTransparency, RefreshHandleSelectionVisuals, Auras = Pick(D, [[TR PortraitStyleGet max min abs floor format TEX_W8 ApplyPreviewFont CastbarEnabled ReadCastbarSize CastbarOffsetFields CastbarDetached CanDetachPowerBarKey ClampPreviewLayer SetTex ReadPowerBarHeight PlaceHandle UnitPreviewText UnitPreviewTextMovesTogether SetShownSafe ApplyPreviewLayerVisibility ApplyPreviewTransparency RefreshHandleSelectionVisuals Auras]])
    local panel = box._msufPanel
    local UNIT_DATA = D.UNIT_DATA or {}
    local UNIT_LABELS = D.UNIT_LABELS or {}
    local key = D.CurrentPanelKey(panel)
    local conf, g = D.UnitDB(key)
    local data = UNIT_DATA[key] or UNIT_DATA.player or {}
    local runtimeSpec = R.RuntimeSpecForPreviewKey(key)
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
    local classPowerPreviewSpec
    if key == "player" then
        classPowerPreviewSpec = MSUF.MSUF2 or _G.MSUF2 or MenuState
        if classPowerPreviewSpec.activeKey == "classpower" and type(classPowerPreviewSpec.GetClassPowerPreviewSpec) == "function" then
            classPowerPreviewSpec = classPowerPreviewSpec.GetClassPowerPreviewSpec()
        else
            classPowerPreviewSpec = nil
        end
    end
    if classPowerPreviewSpec then
        local previewClass = type(MenuState.GetClassPowerPreviewClassToken) == "function" and MenuState.GetClassPowerPreviewClassToken() or nil
        previewClass = previewClass or classPowerPreviewSpec.classToken or classPowerPreviewSpec.class
        if previewClass and data.class ~= previewClass then
            local copy = {}
            for k, v in pairs(data) do copy[k] = v end
            copy.class = tostring(previewClass):upper()
            data = copy
        end
    end
    local powerAllowed = runtimePower and runtimePower.enabled == true
    if runtimePower == nil then powerAllowed = D.ReadPowerBarEnabled(conf, key) end
    local detachedPower = CanDetachPowerBarKey(key) and powerAllowed and ((runtimePower and runtimePower.detached == true) or (runtimePower == nil and conf.powerBarDetached == true))
    local classPowerOn = runtimeClassPower and runtimeClassPower.enabled == true
    if runtimeClassPower == nil then classPowerOn = key == "player" and bars.showClassPower ~= false end
    if classPowerPreviewSpec then classPowerOn = bars.showClassPower ~= false and classPowerPreviewSpec.enabled ~= false and classPowerPreviewSpec.mode ~= "none" end
    local powerFrac = tonumber(data.power) or 1
    if not detachedPower and key ~= "player" then powerFrac = 1 end
    if powerFrac < 0 then powerFrac = 0 elseif powerFrac > 1 then powerFrac = 1 end
    local cpH = classPowerOn and (tonumber(bars.classPowerHeight) or 4) or 0
    if cpH < 2 then cpH = 2 elseif cpH > 30 then cpH = 30 end
    local classPowerSegCount = PreviewClassPowerSegmentCount(classPowerPreviewSpec, 10)
    box._runtimeClassPowerW = classPowerOn and PreviewClassPowerWidth(bars, w, cpH, classPowerSegCount) or 0
    box._runtimeDetachedPowerW = tonumber(runtimePower and runtimePower.detachedWidth) or tonumber(conf.detachedPowerBarWidth) or w
    box._runtimeDetachedPowerSyncClass = key == "player" and ((runtimePower and runtimePower.detachedSyncClass == true) or (runtimePower == nil and conf.detachedPowerBarSyncClassPower ~= false)) or false
    if detachedPower and box._runtimeDetachedPowerSyncClass then box._runtimeDetachedPowerW = classPowerOn and (box._runtimeClassPowerW or w) or w end
    box._runtimeDetachedPowerX = tonumber(runtimePower and runtimePower.detachedX) or tonumber(conf.detachedPowerBarOffsetX) or 0
    box._runtimeDetachedPowerY = tonumber(runtimePower and runtimePower.detachedY) or tonumber(conf.detachedPowerBarOffsetY) or -4
    box._runtimeDetachedPowerAnchorClass = key == "player" and ((runtimePower and runtimePower.detachedAnchorClass == true) or (runtimePower == nil and conf.detachedPowerBarAnchorToClassPower == true))
    box._runtimeDetachedPowerTextOnBar = (runtimePower and runtimePower.textOnDetached == true) or (runtimePower == nil and conf.detachedPowerBarTextOnBar == true)
    box._runtimeDetachedPowerShape = key == "player"
        and ResolvePreviewPowerShape((runtimePower and runtimePower.shape) or conf.detachedPowerBarShape or "FOLLOW_CLASS", bars.classPowerShape)
        or "BAR"
    local detachedH = detachedPower and (tonumber(runtimePower and runtimePower.detachedHeight) or tonumber(conf.detachedPowerBarHeight) or 6) or 0
    if detachedH < 2 then detachedH = 2 elseif detachedH > 80 then detachedH = 80 end
    if detachedPower and box._runtimeDetachedPowerShape == "ORB" then
        local orbSize = tonumber(runtimePower and runtimePower.orbSize) or tonumber(conf.detachedPowerOrbSize) or 54
        if orbSize < 20 then orbSize = 20 elseif orbSize > 160 then orbSize = 160 end
        box._runtimeDetachedPowerW = orbSize
        detachedH = orbSize
    end
    local detachedPowerManagedByClassPreview = detachedPower and key == "player" and box._runtimeDetachedPowerAnchorClass == true
    local detachedPowerInUnitPreview = detachedPower and not detachedPowerManagedByClassPreview
    local wideW = w
    if classPowerOn then wideW = max(wideW, box._runtimeClassPowerW or w) end
    if detachedPowerInUnitPreview then wideW = max(wideW, box._runtimeDetachedPowerW) end
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
        if box._runtimePortraitBorderThickness > 0 and not box._runtimePortraitBorderFill then left, right = left - box._runtimePortraitBorderThickness, right + box._runtimePortraitBorderThickness end
        minX, maxX = min(minX, left), max(maxX, right)
        minY, maxY = min(minY, poY - pSize * 0.5 + h * 0.5 - (box._runtimePortraitBorderFill and 0 or box._runtimePortraitBorderThickness)), max(maxY, poY + pSize * 0.5 + h * 0.5 + (box._runtimePortraitBorderFill and 0 or box._runtimePortraitBorderThickness))
    end
    if classPowerOn then
        local cpW = box._runtimeClassPowerW or PreviewClassPowerWidth(bars, w, cpH, classPowerSegCount)
        local cx = 2 + (tonumber(bars.classPowerOffsetX) or 0)
        local cy = h + 4 + (tonumber(bars.classPowerOffsetY) or 0)
        minX, maxX = min(minX, cx), max(maxX, cx + cpW)
        minY, maxY = min(minY, cy), max(maxY, cy + cpH)
    end
    if detachedPowerInUnitPreview then
        local dW = box._runtimeDetachedPowerW
        local dx = box._runtimeDetachedPowerX
        local dy = box._runtimeDetachedPowerY
        local dLeft, dBottom = (w - dW) * 0.5 + dx, -detachedH + dy
        if box._runtimeDetachedPowerAnchorClass and classPowerOn then
            local cpW = box._runtimeClassPowerW or PreviewClassPowerWidth(bars, w, cpH, classPowerSegCount)
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
    local centerX = ((minX + maxX) * 0.5) - (w * 0.5)
    local centerY = ((minY + maxY) * 0.5) - (h * 0.5)
    if auraPreviewState and Auras.ExpandFootprint then minX, maxX, minY, maxY = Auras.ExpandFootprint(auraPreviewState, minX, maxX, minY, maxY) end
    if classPowerOn or detachedPowerInUnitPreview or castPreviewVisible or auraPreviewState then
        minX, maxX = minX - 18, maxX + 18
        minY, maxY = minY - 18, maxY + 18
    end
    local runtimeScale = R.RuntimeVisualScaleForPreviewKey(key)
    local autoScale = min(1.0, (cw - 60) / max(max(wideW, maxX - minX) * runtimeScale, 1), (ch - 42) / max(max(h, maxY - minY) * runtimeScale, 1))
    if autoScale < R.ZOOM_MIN then autoScale = R.ZOOM_MIN end
    local manualZoom = tonumber(box._manualZoom)
    local frozenScale = tonumber(box._dragFrozenScale)
    local previewScale = manualZoom and R.ClampPreviewZoom(manualZoom) or (frozenScale and R.ClampPreviewZoom(frozenScale) or autoScale)
    local scale = runtimeScale * previewScale
    box._mockRuntimeScale = runtimeScale
    box._mockAutoScale = autoScale
    box._mockScale = previewScale
    box._mockEffectiveScale = scale
    R.UpdatePreviewZoomControls(box)
    local function S(v) return floor((tonumber(v) or 0) * scale + 0.5) end
    local function StatusAnchorOffsets(spec, statusCfg)
        return (statusCfg and statusCfg.anchor) or R.ResolveStatusPreviewAnchor(spec, conf, g),
            S(tonumber(statusCfg and statusCfg.x) or tonumber(conf[spec.x]) or tonumber(g[spec.x]) or spec.defaultX or 0),
            S(tonumber(statusCfg and statusCfg.y) or tonumber(conf[spec.y]) or tonumber(g[spec.y]) or spec.defaultY or 0)
    end
    local sw, sh, sp = S(w), S(h), S(pSize)
    local mockOffsetX = -S(centerX)
    local mockOffsetY = -S(centerY)
    local panX, panY = tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
    box._mockBaseOffsetX, box._mockBaseOffsetY = mockOffsetX, mockOffsetY
    box._detachedCastPreview = nil
    box._detachedCastBaseOffsetX, box._detachedCastBaseOffsetY = nil, nil
    local mock = box.mock
    local baseLevel = (canvas.GetFrameLevel and canvas:GetFrameLevel() or 0) + 2
    if mock.SetFrameLevel then mock:SetFrameLevel(baseLevel + 4) end
    if mock.classPower and mock.classPower.SetFrameLevel then mock.classPower:SetFrameLevel(baseLevel + 4 + ClampPreviewLayer(bars.classPowerFrameLevelOffset, 5)) end
    if mock.detachedPower and mock.detachedPower.SetFrameLevel then mock.detachedPower:SetFrameLevel(baseLevel + 4 + ClampPreviewLayer(runtimePower and runtimePower.detachedLevel or conf.detachedPowerBarFrameLevelOffset, 6)) end
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
    local detachedPowerTexture = (runtimePower and runtimePower.texture) or (runtimeSpec and runtimeSpec.texture) or (type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture()) or TEX_W8
    local detachedPowerBgTexture = (runtimePower and runtimePower.backgroundTexture) or (runtimeSpec and runtimeSpec.backgroundTexture) or (type(_G.MSUF_GetBarBackgroundTexture) == "function" and _G.MSUF_GetBarBackgroundTexture()) or detachedPowerTexture
    SetTex(mock.detachedPower.fill, detachedPowerTexture)
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
        SetRightSpan(mock.hp, mock.hpBG)
    else
        SetLeftSpan(mock.hp, mock.hpBG)
    end
    local hpAreaW = max(1, sw)
    local hpFrac = max(0, min(1, tonumber(data.hp) or 0.6))
    mock.hp:SetWidth(max(1, hpAreaW * hpFrac))
    local healPredMode = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healAnchorMode) or R.PreviewResolveHealPredAnchorMode(conf, g)
    local absorbMode = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.absorbAnchorMode) or R.PreviewResolveAbsorbAnchorMode(conf, g)
    local healPredShown = runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.heal == true
    if not (runtimeSpec and runtimeSpec.prediction) then healPredShown = R.PreviewHealPredictionEnabled(conf, g) end
    local absorbShown = runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.absorb == true
    if not (runtimeSpec and runtimeSpec.prediction) then absorbShown = R.PreviewAbsorbBarEnabled(conf, g, key) end
    local healPredFrac = ((healPredMode == 3) and min(0.14, max(0.02, 1 - hpFrac))) or 0.14
    if healPredShown then
        local r = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healR) or tonumber(g and g.healPredColorR) or 0
        local gg = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healG) or tonumber(g and g.healPredColorG) or 1
        local b = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healB) or tonumber(g and g.healPredColorB) or 0.4
        local a = tonumber(runtimeSpec and runtimeSpec.prediction and runtimeSpec.prediction.healA) or 0.55
        mock.healPred:SetVertexColor(r, gg, b, a)
        R.LayoutUnitPreviewOverlay(mock.healPred, mock.hpBG, mock.hp, healPredMode, healPredFrac, hpReverse, nil, hpAreaW)
    else
        mock.healPred:Hide()
    end
    if absorbShown then
        local absorbAnchor = nil
        if healPredShown and mock.healPred:IsShown() and (healPredMode == 3 or healPredMode == 4) and (absorbMode == 3 or absorbMode == 4) then absorbAnchor = mock.healPred end
        R.LayoutUnitPreviewOverlay(mock.absorb, mock.hpBG, mock.hp, absorbMode, 0.10, hpReverse, absorbAnchor, hpAreaW)
    else
        mock.absorb:Hide()
    end
    local hr, hg, hb = runtimeSpec and runtimeSpec.health and runtimeSpec.health.r, runtimeSpec and runtimeSpec.health and runtimeSpec.health.g, runtimeSpec and runtimeSpec.health and runtimeSpec.health.b
    if not hr then hr, hg, hb = R.HealthColor(key, data) end
    local hbr, hbg, hbb, hba
    local healthBg = runtimeSpec and runtimeSpec.health and runtimeSpec.health.background
    if healthBg then
        hbr, hbg, hbb, hba = healthBg.r or hr, healthBg.g or hg, healthBg.b or hb, healthBg.a or 0.85
    else
        hbr, hbg, hbb, hba = R.HealthBackgroundColor(hr, hg, hb, data)
    end
    mock.hpBG:SetVertexColor(hbr, hbg, hbb, hba)
    mock.hp:SetVertexColor(hr, hg, hb, 1)
    if powerOn then
        mock.powerBG:Show(); mock.power:Show()
        mock.powerBG:ClearAllPoints()
        SetBottomSpan(mock.powerBG, mock)
        mock.powerBG:SetHeight(powerH)
        local pr, pg, pb = runtimePower and runtimePower.r, runtimePower and runtimePower.g, runtimePower and runtimePower.b
        if not pr then pr, pg, pb = R.PowerColor(data.powerToken) end
        local pbr, pbg, pbb, pba
        local powerBg = runtimePower and runtimePower.background
        if powerBg then
            pbr, pbg, pbb, pba = powerBg.r or pr, powerBg.g or pg, powerBg.b or pb, powerBg.a or 0.85
        else
            pbr, pbg, pbb, pba = R.PowerBackgroundColor(pr, pg, pb, hr, hg, hb)
        end
        mock.powerBG:SetVertexColor(pbr, pbg, pbb, pba)
        mock.power:ClearAllPoints()
        SetLeftSpan(mock.power, mock.powerBG)
        mock.power:SetWidth(max(1, sw * powerFrac))
        mock.power:SetVertexColor(pr, pg, pb, 1)
    else
        mock.powerBG:Hide(); mock.power:Hide()
    end
    local fr, fg, fb = R.FontColor()
    local pr, pg, pb = runtimePower and runtimePower.r, runtimePower and runtimePower.g, runtimePower and runtimePower.b
    if not pr then pr, pg, pb = R.PowerColor(data.powerToken) end
    if classPowerOn then
        mock.classPower:Show()
        local cpW = box._runtimeClassPowerW or PreviewClassPowerWidth(bars, w, cpH, classPowerSegCount)
        mock.classPower:SetSize(S(cpW), max(2, S(cpH)))
        mock.classPower:ClearAllPoints()
        mock.classPower:SetPoint("BOTTOMLEFT", mock, "TOPLEFT", S(2 + (tonumber(bars.classPowerOffsetX) or 0)), S(4 + (tonumber(bars.classPowerOffsetY) or 0)))
        local cp = box._msufClassPowerPreviewScratch
        if not cp then cp = {}; box._msufClassPowerPreviewScratch = cp end
        cp.preview = classPowerPreviewSpec
        cp.token = cp.preview and cp.preview.token
        cp.isRune = cp.preview and cp.preview.mode == "rune"
        cp.r, cp.g, cp.b = pr, pg, pb
        if cp.token then cp.r, cp.g, cp.b = R.CPPreview.ResolveBaseColor(cp.preview, bars, pr, pg, pb) end
        cp.filledAlpha = tonumber(bars.classPowerFilledAlpha) or 0.95
        if cp.filledAlpha < 0 then cp.filledAlpha = 0 elseif cp.filledAlpha > 1 then cp.filledAlpha = 1 end
        cp.emptyAlpha = tonumber(bars.classPowerEmptyAlpha) or 0.28
        if cp.emptyAlpha < 0 then cp.emptyAlpha = 0 elseif cp.emptyAlpha > 1 then cp.emptyAlpha = 1 end
        cp.bgAlpha = tonumber(bars.classPowerBgAlpha) or 0.30
        if cp.bgAlpha < 0 then cp.bgAlpha = 0 elseif cp.bgAlpha > 1 then cp.bgAlpha = 1 end
        cp.shape = NormalizePreviewClassPowerShape(bars.classPowerShape)
        cp.shapeInfo = PREVIEW_CLASS_POWER_SHAPES[cp.shape]
        if mock.classPower.SetBackdropColor then
            cp.bgr, cp.bgg, cp.bgb = R.CPPreview.ColorOverride("classPowerBgColorOverrides", cp.token)
            mock.classPower:SetBackdropColor(cp.bgr or 0, cp.bgg or 0, cp.bgb or 0, cp.shapeInfo and 0 or cp.bgAlpha)
            mock.classPower:SetBackdropBorderColor(0, 0, 0, cp.shapeInfo and 0 or 1)
        end
        cp.segCount = floor(tonumber(cp.preview and cp.preview.segments) or 5)
        if cp.segCount < 1 then cp.segCount = 1 end
        if mock.classPower.segments and cp.segCount > #mock.classPower.segments then cp.segCount = #mock.classPower.segments end
        local previewW = S(cpW)
        local rawGap = cp.shapeInfo and (tonumber(bars.classPowerGap) or 0) or ((tonumber(bars.classPowerTickWidth) or 1) + (tonumber(bars.classPowerGap) or 0))
        local gap = max(0, S(rawGap))
        if cp.segCount > 1 then
            local maxGap = floor((previewW - cp.segCount) / (cp.segCount - 1))
            if maxGap < 0 then maxGap = 0 end
            if gap > maxGap then gap = maxGap end
        end
        local segSpace = previewW - (cp.segCount - 1) * gap
        if segSpace < cp.segCount then segSpace = cp.segCount end
        local slot = nil
        local startX = 0
        if cp.shapeInfo then
            slot = max(1, S(cpH))
            local maxSlot = floor((previewW - (cp.segCount - 1) * gap) / cp.segCount)
            if maxSlot < 1 then maxSlot = 1 end
            if slot > maxSlot then slot = maxSlot end
            segSpace = slot * cp.segCount
            local rowW = segSpace + (cp.segCount - 1) * gap
            local align = NormalizePreviewClassPowerShapeAlign(bars.classPowerShapeAlign)
            if align == "LEFT" then
                startX = 0
            elseif align == "RIGHT" then
                startX = floor(previewW - rowW + 0.5)
            else
                startX = floor((previewW - rowW) * 0.5 + 0.5)
            end
            if startX < 0 then startX = 0 end
            cp.rightInset = floor(previewW - rowW - startX + 0.5)
            if cp.rightInset < 0 then cp.rightInset = 0 end
        else
            cp.rightInset = 0
        end
        local xPos, prevBoundary = 0, 0
        cp.runeOrder = cp.isRune and R.CPPreview.BuildRuneOrder(cp, bars, cp.preview) or nil
        cp.runeShowTime = bars.runeShowTime ~= false
        if bars.runeShowTime == nil and bars.runeShowTimeText ~= nil then cp.runeShowTime = bars.runeShowTimeText == true end
        cp.runeTextSize = max(6, S((tonumber(bars.classPowerFontSize) or 16) - 2))
        for i = 1, #mock.classPower.segments do
            local seg = mock.classPower.segments[i]
            local segBg = mock.classPower.segmentBgs and mock.classPower.segmentBgs[i]
            local segEdge = mock.classPower.segmentEdges and mock.classPower.segmentEdges[i]
            local runeText = mock.classPower.runeTexts and mock.classPower.runeTexts[i]
            if i <= cp.segCount then
                local boundary, segW
                if cp.shapeInfo then
                    boundary = i * slot
                    segW = slot
                else
                    boundary = floor((segSpace * i) / cp.segCount)
                    segW = boundary - prevBoundary
                    if segW < 1 then segW = 1 end
                end
                seg:Show()
                seg:ClearAllPoints()
                cp.rune = cp.runeOrder and cp.runeOrder[i] or nil
                cp.fill = cp.rune and ((cp.rune.elapsed or 0) / (cp.rune.total or 1)) or R.CPPreview.FillForSegment(cp.preview, i)
                cp.drawW = segW
                cp.mode = cp.preview and cp.preview.mode
                if (cp.mode == "continuous" or cp.mode == "timer_bar" or cp.mode == "stagger" or cp.mode == "aura_single" or cp.mode == "fractional") and cp.fill > 0 and cp.fill < 1 then
                    cp.drawW = max(1, floor(segW * cp.fill + 0.5))
                elseif cp.rune and cp.fill > 0 and cp.fill < 1 then
                    cp.drawW = max(1, floor(segW * cp.fill + 0.5))
                end
                local visualW = cp.shapeInfo and segW or cp.drawW
                seg:SetWidth(visualW)
                seg:SetHeight(max(2, S(cpH)))
                local anchorX = startX + xPos
                if bars.classPowerFillReverse == true then
                    anchorX = (cp.rightInset or 0) + xPos
                    SetRightSpan(seg, mock.classPower, -anchorX)
                else
                    SetLeftSpan(seg, mock.classPower, anchorX)
                end
                if segBg then
                    if cp.shapeInfo then
                        segBg:SetTexture(cp.shapeInfo.bg)
                        segBg:SetVertexColor(cp.bgr or 0, cp.bgg or 0, cp.bgb or 0, cp.bgAlpha)
                        segBg:ClearAllPoints()
                        if bars.classPowerFillReverse == true then
                            SetRightSpan(segBg, mock.classPower, -anchorX)
                        else
                            SetLeftSpan(segBg, mock.classPower, anchorX)
                        end
                        segBg:SetSize(segW, max(2, S(cpH)))
                        segBg:Show()
                    else
                        segBg:Hide()
                    end
                end
                if segEdge then segEdge:Hide() end
                cp.sr, cp.sg, cp.sb = cp.r, cp.g, cp.b
                cp.charged = R.CPPreview.IsCharged(cp.preview, bars, i)
                if cp.charged then
                    cp.sr, cp.sg, cp.sb = R.CPPreview.ResolveColor("CHARGED", 0.60, 0.20, 0.80)
                elseif cp.token == "COMBO_POINTS" then
                    cp.sr, cp.sg, cp.sb = R.CPPreview.ResolveComboColor(bars, i, cp.r, cp.g, cp.b)
                end
                if cp.preview and cp.preview.threshold and cp.fill > 0 and i > cp.preview.threshold then cp.sr, cp.sg, cp.sb = R.CPPreview.ResolveColor(cp.preview.thresholdToken, cp.sr, cp.sg, cp.sb) end
                cp.alpha = cp.fill > 0 and cp.filledAlpha or cp.emptyAlpha
                if cp.charged and cp.fill <= 0 then cp.alpha = max(cp.alpha, 0.55) end
                if cp.shapeInfo then
                    seg:SetTexture(cp.shapeInfo.fill)
                    if cp.fill > 0 and cp.fill < 1 then
                        seg:SetWidth(max(1, floor(segW * cp.fill + 0.5)))
                        if bars.classPowerFillReverse == true then
                            seg:SetTexCoord(1 - cp.fill, 1, 0, 1)
                        else
                            seg:SetTexCoord(0, cp.fill, 0, 1)
                        end
                    else
                        seg:SetTexCoord(0, 1, 0, 1)
                    end
                    seg:SetVertexColor(cp.sr, cp.sg, cp.sb, cp.fill > 0 and cp.alpha or 0)
                else
                    seg:SetTexCoord(0, 1, 0, 1)
                    seg:SetColorTexture(cp.sr, cp.sg, cp.sb, cp.alpha)
                end
                if runeText then
                    if cp.rune and cp.runeShowTime and not cp.rune.ready then
                        cp.runeText = R.CPPreview.FormatSeconds(cp.rune.remaining)
                        if cp.runeText ~= "" then
                            ApplyPreviewFont(runeText, cp.runeTextSize)
                            cp.tr, cp.tg, cp.tb = R.CPPreview.ResolveTextColor(fr or 1, fg or 1, fb or 1)
                            runeText:SetText(cp.runeText)
                            runeText:SetTextColor(cp.tr, cp.tg, cp.tb, 1)
                            runeText:ClearAllPoints()
                            if bars.classPowerFillReverse == true then
                                runeText:SetPoint("CENTER", mock.classPower, "TOPRIGHT", -(anchorX + floor(segW * 0.5 + 0.5)), -floor(max(2, S(cpH)) * 0.5 + 0.5))
                            else
                                runeText:SetPoint("CENTER", mock.classPower, "TOPLEFT", anchorX + floor(segW * 0.5 + 0.5), -floor(max(2, S(cpH)) * 0.5 + 0.5))
                            end
                            runeText:Show()
                        else
                            runeText:SetText("")
                            runeText:Hide()
                        end
                    else
                        runeText:SetText("")
                        runeText:Hide()
                    end
                end
                xPos = xPos + segW + gap
                prevBoundary = boundary
            else
                seg:Hide()
                if segBg then segBg:Hide() end
                if segEdge then segEdge:Hide() end
                if runeText then runeText:Hide() end
            end
        end
        local classTextOn = bars.classPowerShowText == true
        if classTextOn then
            local cpTextSize = S(tonumber(bars.classPowerFontSize) or 16)
            if cpTextSize < 7 then cpTextSize = 7 end
            ApplyPreviewFont(mock.classPower.text, cpTextSize)
            mock.classPower.text:SetText((cp.preview and cp.preview.previewText) or "3")
            cp.tr, cp.tg, cp.tb = R.CPPreview.ResolveTextColor(fr or 1, fg or 1, fb or 1)
            mock.classPower.text:SetTextColor(cp.tr, cp.tg, cp.tb, 1)
            mock.classPower.text:ClearAllPoints()
            mock.classPower.text:SetPoint("CENTER", mock.classPower, "CENTER", S(tonumber(bars.classPowerTextOffsetX) or 0), S(tonumber(bars.classPowerTextOffsetY) or 0))
            mock.classPower.text:Show()
            box.handleClassPowerText:SetSize(max(26, mock.classPower.text:GetStringWidth() + 10), max(18, mock.classPower.text:GetStringHeight() + 6))
            if not UnitPreviewText.PlaceHandleAroundRegions(box.handleClassPowerText, canvas, { mock.classPower.text }, 3) then PlaceHandle(box.handleClassPowerText, mock.classPower.text) end
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
    if detachedPowerInUnitPreview then
        mock.detachedPower:Show()
        local dW = box._runtimeDetachedPowerW
        if box._runtimeDetachedPowerShape ~= "ORB" and key == "player" and (box._runtimeDetachedPowerSyncClass or (bars.detachedPowerBarWidthMode and bars.detachedPowerBarWidthMode ~= "manual")) then dW = classPowerOn and (mock.classPower:GetWidth() / max(scale, 0.01)) or w end
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
        local powerShapeInfo = PREVIEW_POWER_SHAPES[box._runtimeDetachedPowerShape or "BAR"]
        local powerOutline = floor((tonumber(bars.detachedPowerBarOutline) or 1) + 0.5)
        if powerOutline < 0 then powerOutline = 0 elseif powerOutline > 8 then powerOutline = 8 end
        if mock.detachedPower.SetBackdropColor then
            if mock.detachedPower.SetBackdrop then mock.detachedPower:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = max(1, powerOutline) }) end
            mock.detachedPower:SetBackdropColor(0, 0, 0, 0)
            mock.detachedPower:SetBackdropBorderColor(0, 0, 0, (not powerShapeInfo and powerOutline > 0) and 1 or 0)
        end
        mock.detachedPower.fill:ClearAllPoints()
        if powerShapeInfo then
            if mock.detachedPower.bg then
                mock.detachedPower.bg:SetTexture(powerShapeInfo.bg)
                mock.detachedPower.bg:SetVertexColor(pr, pg, pb, 0.28)
                mock.detachedPower.bg:ClearAllPoints()
                mock.detachedPower.bg:SetAllPoints(mock.detachedPower)
                mock.detachedPower.bg:Show()
            end
            mock.detachedPower.fill:SetTexture(powerShapeInfo.fill)
            mock.detachedPower.fill:SetVertexColor(pr, pg, pb, powerFrac > 0 and 1 or 0)
            if powerShapeInfo.axis == "VERTICAL" then
                local shapeW = S(dW)
                local shapeH = max(2, S(detachedH))
                if powerFrac > 0 and powerFrac < 1 then
                    mock.detachedPower.fill:SetTexCoord(0, 1, 1 - powerFrac, 1)
                    mock.detachedPower.fill:SetHeight(max(1, floor(shapeH * powerFrac + 0.5)))
                else
                    mock.detachedPower.fill:SetTexCoord(0, 1, 0, 1)
                    mock.detachedPower.fill:SetHeight(shapeH)
                end
                mock.detachedPower.fill:SetWidth(shapeW)
                SetBottomSpan(mock.detachedPower.fill, mock.detachedPower)
            else
                if powerFrac > 0 and powerFrac < 1 then
                    mock.detachedPower.fill:SetTexCoord(0, powerFrac, 0, 1)
                    mock.detachedPower.fill:SetWidth(max(1, floor(S(dW) * powerFrac + 0.5)))
                else
                    mock.detachedPower.fill:SetTexCoord(0, 1, 0, 1)
                    mock.detachedPower.fill:SetWidth(S(dW))
                end
                SetLeftSpan(mock.detachedPower.fill, mock.detachedPower)
            end
            if mock.detachedPower.edge then
                if powerOutline > 0 then
                    mock.detachedPower.edge:ClearAllPoints()
                    mock.detachedPower.edge:SetAllPoints(mock.detachedPower)
                    mock.detachedPower.edge:SetTexture(powerShapeInfo.edge)
                    mock.detachedPower.edge:SetVertexColor(0, 0, 0, PreviewShapeOutlineAlpha(powerOutline))
                    mock.detachedPower.edge:Show()
                else
                    mock.detachedPower.edge:Hide()
                end
            end
        else
            if mock.detachedPower.bg then
                local powerBg = runtimePower and runtimePower.background
                local pbr, pbg, pbb, pba
                if powerBg then
                    pbr, pbg, pbb, pba = powerBg.r or pr, powerBg.g or pg, powerBg.b or pb, powerBg.a or 0.85
                else
                    pbr, pbg, pbb, pba = R.PowerBackgroundColor(pr, pg, pb, hr, hg, hb)
                end
                SetTex(mock.detachedPower.bg, detachedPowerBgTexture)
                mock.detachedPower.bg:SetVertexColor(pbr, pbg, pbb, pba)
                mock.detachedPower.bg:ClearAllPoints()
                mock.detachedPower.bg:SetAllPoints(mock.detachedPower)
                mock.detachedPower.bg:Show()
            end
            if mock.detachedPower.edge then mock.detachedPower.edge:Hide() end
            SetTex(mock.detachedPower.fill, detachedPowerTexture)
            mock.detachedPower.fill:SetTexCoord(0, 1, 0, 1)
            mock.detachedPower.fill:SetVertexColor(pr, pg, pb, 1)
            mock.detachedPower.fill:SetWidth(max(1, S(dW) * powerFrac))
            SetLeftSpan(mock.detachedPower.fill, mock.detachedPower)
        end
        box.handleDetachedPower:SetSize(max(36, S(dW)), max(18, S(detachedH) + 8))
        PlaceHandle(box.handleDetachedPower, mock.detachedPower)
    else
        mock.detachedPower:Hide()
        box.handleDetachedPower:Hide()
    end
    R.ApplyPreviewRounded(box, key, powerOn, R.PreviewRoundedOutlineThickness(key, conf, scale))
    if R.ApplyPreviewFrameBorder then R.ApplyPreviewFrameBorder(box, runtimeSpec and runtimeSpec.border, scale) end
    if R.ApplyPreviewBoundsGuide then
        local guideEdge = 1
        if mock._msufPreviewRoundedActive == true then
            guideEdge = R.PreviewRoundedOutlineThickness(key, conf, scale)
        elseif runtimeSpec and runtimeSpec.border and runtimeSpec.border.enabled == true then
            guideEdge = floor(((tonumber(runtimeSpec.border.thickness) or 1) * scale) + 0.5)
        end
        R.ApplyPreviewBoundsGuide(box, guideEdge)
    end
    local fr, fg, fb = R.FontColor()
    local baseTextSize = tonumber(g.fontSize) or 14
    local nameRawSize = tonumber(conf.nameFontSize) or tonumber(g.nameFontSize) or baseTextSize
    local nameSize = S(nameRawSize); if nameSize < 7 then nameSize = 7 end
    local hpSize = S(tonumber(conf.hpFontSize) or tonumber(g.hpFontSize) or baseTextSize); if hpSize < 7 then hpSize = 7 end
    local pwrSize = S(tonumber(conf.powerFontSize) or tonumber(g.powerFontSize) or baseTextSize); if pwrSize < 7 then pwrSize = 7 end
    box._fontPreviewTextAlpha = tonumber(runtimeSpec and runtimeSpec.textColor and runtimeSpec.textColor.a)
        or tonumber(conf.fontOverride == true and conf.fontTextAlpha)
        or tonumber(g.fontTextAlpha)
        or 1
    if box._fontPreviewTextAlpha < 0.7 then box._fontPreviewTextAlpha = 0.7 elseif box._fontPreviewTextAlpha > 1 then box._fontPreviewTextAlpha = 1 end
    box._fontPreviewBaselineOffset = tonumber(conf.fontOverride == true and conf.fontBaselineOffset) or tonumber(g.fontBaselineOffset) or 0
    if box._fontPreviewBaselineOffset < -4 then box._fontPreviewBaselineOffset = -4 elseif box._fontPreviewBaselineOffset > 4 then box._fontPreviewBaselineOffset = 4 end
    ApplyPreviewFontSet(ApplyPreviewFont, nameSize, mock.nameText, mock.raidGroupNameText, mock.totInlineSep, mock.totInlineText)
    ApplyPreviewFontSet(ApplyPreviewFont, hpSize, mock.hpTextLeft, mock.hpTextCenter, mock.hpText, mock.hpTextPct)
    ApplyPreviewFontSet(ApplyPreviewFont, pwrSize, mock.powerTextLeft, mock.powerTextCenter, mock.powerText, mock.powerTextPct)
    SetTextColorSet(fr, fg, fb, box._fontPreviewTextAlpha, mock.nameText, mock.raidGroupNameText)
    mock.totInlineSep:SetTextColor(0.72, 0.76, 0.84, box._fontPreviewTextAlpha)
    mock.totInlineText:SetTextColor(fr, fg, fb, box._fontPreviewTextAlpha)
    local hpTextR, hpTextG, hpTextB = fr, fg, fb
    local healthTextByHealth = g.colorHealthTextByHealth == true
    if conf.fontOverride == true and conf.colorHealthTextByHealth ~= nil then healthTextByHealth = conf.colorHealthTextByHealth == true end
    if healthTextByHealth then
        local pct = tonumber(data.hp) or 1
        if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
        if pct <= 0.5 then
            hpTextR, hpTextG, hpTextB = 1, pct * 2, 0
        else
            hpTextR, hpTextG, hpTextB = (1 - pct) * 2, 1, 0
        end
    end
    SetTextColorSet(hpTextR, hpTextG, hpTextB, box._fontPreviewTextAlpha, mock.hpTextLeft, mock.hpTextCenter, mock.hpText, mock.hpTextPct)
    if g.colorPowerTextByType == true then
        local prt, pgt, pbt = R.PowerColor(data.powerToken)
        SetTextColorSet(prt, pgt, pbt, box._fontPreviewTextAlpha, mock.powerTextLeft, mock.powerTextCenter, mock.powerText, mock.powerTextPct)
    else
        SetTextColorSet(fr, fg, fb, box._fontPreviewTextAlpha, mock.powerTextLeft, mock.powerTextCenter, mock.powerText, mock.powerTextPct)
    end
    mock.nameText:SetText(R.ShortenPreviewName(data.name, key, conf))
    mock.raidGroupNameText:SetText(D.PreviewRaidGroupNameText(conf))
    local hpMax, pMax = 1000000, 240000
    local hpCur, pCur = floor(hpMax * data.hp + 0.5), floor(pMax * powerFrac + 0.5)
    local hpSlots = R.TextScopeHasSlots(key, "textLeft", "textCenter", "textRight")
    local hpLeftMode, hpCenterMode, hpRightMode
    if hpSlots then
        hpLeftMode = R.TextScopeSlotGet(key, "textLeft", "NONE", R.NormalizeHpMode)
        hpCenterMode = R.TextScopeSlotGet(key, "textCenter", "NONE", R.NormalizeHpMode)
        hpRightMode = R.TextScopeSlotGet(key, "textRight", "CURPERCENT", R.NormalizeHpMode)
    else
        hpLeftMode, hpCenterMode, hpRightMode = "NONE", "NONE", R.NormalizeHpMode(R.TextScopeGet(key, "hpTextMode", "CURPERCENT"))
    end
    if R.TextScopeGet(key, "hpTextReverse", false) == true then
        local rev = { CURPERCENT = "PERCENTCUR", PERCENTCUR = "CURPERCENT", CURMAX = "MAXCUR", MAXCUR = "CURMAX", CURMAXPERCENT = "PERCENTMAXCUR", PERCENTMAXCUR = "CURMAXPERCENT", MAXPERCENT = "PERCENTMAX", PERCENTMAX = "MAXPERCENT", PERCENTCURMAX = "CURMAXPERCENT" }
        hpLeftMode, hpRightMode = hpRightMode, hpLeftMode
        hpLeftMode = rev[hpLeftMode] or hpLeftMode
        hpCenterMode = rev[hpCenterMode] or hpCenterMode
        hpRightMode = rev[hpRightMode] or hpRightMode
    end
    local hpPctValue = floor(data.hp * 100 + 0.5)
    local hpSepRaw = R.TextScopeGet(key, "hpTextSeparator", "")
    mock.hpTextLeft:SetText(R.FormatMode(hpLeftMode, hpCur, hpMax, hpPctValue, hpSepRaw, false))
    mock.hpTextCenter:SetText(R.FormatMode(hpCenterMode, hpCur, hpMax, hpPctValue, hpSepRaw, false))
    mock.hpText:SetText(R.FormatMode(hpRightMode, hpCur, hpMax, hpPctValue, hpSepRaw, false))
    mock.hpTextPct:SetText("")
    local powerSlots = R.TextScopeHasSlots(key, "powerTextLeft", "powerTextCenter", "powerTextRight")
    local powerLeftMode, powerCenterMode, powerRightMode
    if powerSlots then
        powerLeftMode = R.TextScopeSlotGet(key, "powerTextLeft", "NONE", R.NormalizePowerMode)
        powerCenterMode = R.TextScopeSlotGet(key, "powerTextCenter", "NONE", R.NormalizePowerMode)
        powerRightMode = R.TextScopeSlotGet(key, "powerTextRight", "CURPERCENT", R.NormalizePowerMode)
    else
        powerLeftMode, powerCenterMode, powerRightMode = "NONE", "NONE", R.NormalizePowerMode(R.TextScopeGet(key, "powerTextMode", "CURPERCENT"))
    end
    local powerPctValue = floor(powerFrac * 100 + 0.5)
    local powerSepRaw = R.TextScopeGet(key, "powerTextSeparator", R.TextScopeGet(key, "hpTextSeparator", ""))
    mock.powerTextLeft:SetText(R.FormatMode(powerLeftMode, pCur, pMax, powerPctValue, powerSepRaw, true))
    mock.powerTextCenter:SetText(R.FormatMode(powerCenterMode, pCur, pMax, powerPctValue, powerSepRaw, true))
    mock.powerText:SetText(R.FormatMode(powerRightMode, pCur, pMax, powerPctValue, powerSepRaw, true))
    mock.powerTextPct:SetText("")
    local showNamePreview = conf.showName ~= false
    if runtimeSpec then showNamePreview = runtimeSpec.showName ~= false end
    local hpTextOn = conf.showHP ~= false
    if runtimeSpec then hpTextOn = runtimeSpec.showHealthText ~= false end
    local powerTextOn = (key ~= "focustarget" and conf.showPower ~= false) or conf.showPower == true
    if runtimeSpec then powerTextOn = runtimeSpec.showPowerText ~= false and powerEnabled == true end
    if detachedPowerManagedByClassPreview and box._runtimeDetachedPowerTextOnBar then powerTextOn = false end
    mock.nameText:SetShown(showNamePreview)
    local raidGroupCfg = runtimeStatus and runtimeStatus.raidGroup
    local raidGroupAnchor = (raidGroupCfg and raidGroupCfg.anchor) or D.NormalizeRaidGroupNameAnchor(conf.raidGroupNameAnchor)
    if not showNamePreview and (raidGroupAnchor == "NAMERIGHT" or raidGroupAnchor == "NAMELEFT") then raidGroupAnchor = "CENTER" end
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
    local npt, nrel, nx, njust = R.ResolveNameAnchor(conf.nameTextAnchor or "LEFT", S(tonumber(conf.nameOffsetX) or 4))
    mock.nameText:SetPoint(npt, mock.textFrame, nrel, nx, S((tonumber(conf.nameOffsetY) or -4) + box._fontPreviewBaselineOffset))
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
            local sep = R.ToTInlineSeparator(totConf.totInlineSeparator, totConf.totInlineCustomSeparator)
            local totData = UNIT_DATA.targettarget or { name = "Target" }
            local tr, tg, tb = R.PreviewNameColor("target", data, fr, fg, fb)
            local ir, ig, ib = R.PreviewToTInlineColor(totConf.totInlineColorMode, totData, tr, tg, tb, fr, fg, fb)
            mock.totInlineSep:SetText(sep ~= "" and sep or " ")
            mock.totInlineText:SetText(R.ShortenPreviewName(totData.name, "targettarget", conf))
            mock.totInlineText:SetTextColor(ir, ig, ib, box._fontPreviewTextAlpha)
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
    local function TextOffsets(prefix, fallbackY)
        local baseX = NumField(prefix .. "OffsetX", prefix .. "TextOffsetX", prefix .. "OffsetX", prefix .. "TextOffsetX", -4)
        local baseY = NumField(prefix .. "OffsetY", prefix .. "TextOffsetY", prefix .. "OffsetY", prefix .. "TextOffsetY", fallbackY) + box._fontPreviewBaselineOffset
        local function Slot(side, axis)
            return NumField(prefix .. "Text" .. side .. "Offset" .. axis, prefix .. side .. "Offset" .. axis, prefix .. "Text" .. side .. "Offset" .. axis, prefix .. side .. "Offset" .. axis, 0)
        end
        return {
            leftX = baseX + Slot("Left", "X"),
            leftY = baseY + Slot("Left", "Y"),
            centerX = baseX + Slot("Center", "X"),
            centerY = baseY + Slot("Center", "Y"),
            rightX = baseX + Slot("Right", "X"),
            rightY = baseY + Slot("Right", "Y"),
        }
    end
    local function PlaceTextSet(left, center, right, pct, parent, lPoint, lRel, cPoint, cRel, rPoint, rRel, offsets, yAdd)
        yAdd = yAdd or 0
        PlacePreviewSlot(left, parent, lPoint, lRel, S(4 + offsets.leftX), S(yAdd + offsets.leftY), "LEFT")
        PlacePreviewSlot(center, parent, cPoint, cRel, S(offsets.centerX), S(yAdd + offsets.centerY), "CENTER")
        PlacePreviewSlot(right, parent, rPoint, rRel, S(-4 + offsets.rightX), S(yAdd + offsets.rightY), "RIGHT")
        PlacePreviewSlot(pct, parent, rPoint, rRel, S(-4 + offsets.rightX), S(yAdd + offsets.rightY), "RIGHT")
    end
    PlaceTextSet(mock.hpTextLeft, mock.hpTextCenter, mock.hpText, mock.hpTextPct, mock.textFrame, "LEFT", "LEFT", "CENTER", "CENTER", "RIGHT", "RIGHT", TextOffsets("hp", -4))
    local powerOffsets = TextOffsets("power", 4)
    if detachedPowerInUnitPreview and box._runtimeDetachedPowerTextOnBar and mock.detachedPower:IsShown() then
        PlaceTextSet(mock.powerTextLeft, mock.powerTextCenter, mock.powerText, mock.powerTextPct, mock.detachedPower, "LEFT", "LEFT", "CENTER", "CENTER", "RIGHT", "RIGHT", powerOffsets)
    else
        PlaceTextSet(mock.powerTextLeft, mock.powerTextCenter, mock.powerText, mock.powerTextPct, mock.textFrame, "BOTTOMLEFT", "BOTTOMLEFT", "BOTTOM", "BOTTOM", "BOTTOMRIGHT", "BOTTOMRIGHT", powerOffsets, 1)
    end
    if hasPortrait then
        mock.portrait:Show()
        mock.portrait:SetSize(sp, sp)
        mock.portrait:ClearAllPoints()
        if mock.portrait.border and mock.portrait.border.SetFrameLevel and mock.portrait.GetFrameLevel then mock.portrait.border:SetFrameLevel((mock.portrait:GetFrameLevel() or 1) + 1) end
        local ox = S(tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.x) or tonumber(PortraitStyleGet(key, "portraitOffsetX", 0)) or 0)
        local oy = S(tonumber(runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.y) or tonumber(PortraitStyleGet(key, "portraitOffsetY", 0)) or 0)
        if mode == "RIGHT" then mock.portrait:SetPoint("LEFT", mock, "RIGHT", ox, oy)
        else mock.portrait:SetPoint("RIGHT", mock, "LEFT", ox, oy) end
        local cr, cg, cb = R.ClassColor(data.class)
        local renderMode = (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.render) or PortraitStyleGet(key, "portraitRender", "2D")
        if renderMode == "CLASS" then
            local visual = R.ClassPortraitVisual(data.class, (runtimeSpec and runtimeSpec.portrait and runtimeSpec.portrait.classStyle) or PortraitStyleGet(key, "portraitClassStyle", "BLIZZARD"))
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
            mock.portrait.tex:SetTexture(R.UnitPreviewPortraitTexture(key, data))
            if mock.portrait.tex.SetVertexColor then mock.portrait.tex:SetVertexColor(1, 1, 1, 1) end
            if mock.portrait.tex.SetTexCoord then mock.portrait.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
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
            R.LayoutPreviewPortraitBorder(mock.portrait, 0, false)
        elseif bStyle == "CUSTOM" or bStyle == "SOLID" then
            R.LayoutPreviewPortraitBorder(
                mock.portrait,
                S(box._runtimePortraitBorderThickness),
                box._runtimePortraitBorderFill,
                (portraitBorder and portraitBorder.r) or g.portraitBorderColorR or 1,
                (portraitBorder and portraitBorder.g) or g.portraitBorderColorG or 1,
                (portraitBorder and portraitBorder.b) or g.portraitBorderColorB or 1,
                (portraitBorder and portraitBorder.a) or g.portraitBorderColorA or 1
            )
        elseif bStyle == "CLASS_COLOR" then
            R.LayoutPreviewPortraitBorder(mock.portrait, S(box._runtimePortraitBorderThickness), box._runtimePortraitBorderFill, cr, cg, cb, 1)
        elseif bStyle == "REACTION" then
            local hostile = (key == "target" or key == "boss" or key == "focus" or key == "focustarget")
            R.LayoutPreviewPortraitBorder(mock.portrait, S(box._runtimePortraitBorderThickness), box._runtimePortraitBorderFill, hostile and 1 or 0.1, hostile and 0.2 or 0.85, 0.1, 1)
        else
            R.LayoutPreviewPortraitBorder(mock.portrait, S(box._runtimePortraitBorderThickness), box._runtimePortraitBorderFill, 1, 1, 1, 1)
        end
        box.handlePortrait:SetSize(max(18, sp + ((box._runtimePortraitBorderFill and 0 or S(box._runtimePortraitBorderThickness)) * 2)), max(18, sp + ((box._runtimePortraitBorderFill and 0 or S(box._runtimePortraitBorderThickness)) * 2)))
        PlaceHandle(box.handlePortrait, mock.portrait)
    else
        mock.portrait:Hide()
        R.LayoutPreviewPortraitBorder(mock.portrait, 0, false)
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
        if type(_G.MSUF_GetInterruptibleCastColor) == "function" then cr, cg, cb = _G.MSUF_GetInterruptibleCastColor() end
        mock.cast.fill:SetVertexColor(cr or 0.0, cg or 0.9, cb or 0.8, 1)
        ApplyCastbarPreviewDetails(box, mock, canvas, g, key, castBarH, scw, S, max, min, floor, fr, fg, fb, TR, ApplyPreviewFont, R.CastbarShowIcon, R.CastbarShowText, R.ReadCastbarNum, R.FormatCastbarPreviewTime, UnitPreviewText, PlaceHandle)
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
    if Auras and Auras.Layout then Auras.Layout(box, mock, auraPreviewState, S, baseLevel) end
    local statusLayerAvailable = false
    for i = 1, #D.STATUS_PREVIEW do
        local spec = D.STATUS_PREVIEW[i]
        local icon = mock.icons[spec.id]
        local handle = box.statusHandles[spec.id]
        local statusCfg = runtimeStatus and runtimeStatus[R.STATUS_RUNTIME_KEYS[spec.id]]
        local show
        if statusCfg then
            show = statusCfg.enabled == true
            if not show and spec.id == "statusPvp" and statusCfg.contextDisabled == true then show = true end
        else
            local showVal = conf[spec.show]
            if showVal == nil then showVal = g[spec.show] end
            show = (showVal == nil) and (spec.defaultShow ~= false) or (showVal ~= false)
        end
        if spec.allowed and not spec.allowed(key) then show = false end
        if spec.id == "elite" and not data.elite then show = false end
        if spec.id == "statusText" and R.PreviewStatus.StatusTextPreviewText then show = show and R.PreviewStatus.StatusTextPreviewText(statusCfg or g) ~= nil end
        if Preview.GetStatusPreviewMode() ~= "all" then
            local selected = R.NormalizeStatusPreviewId(Preview.selectedStatusId)
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
            R.SetPreviewIconTexture(icon, spec, conf, g, key, data, statusCfg)
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
                R.PositionLevelPreview(icon, anchor, x, y, mock, S(6))
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
                R.PositionSameAnchorPreview(icon, anchor, x, y, mock)
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
                    R.PositionRuntimeLayoutIconPreview(icon, anchor, x, y, mock, true)
                elseif spec.id == "leader" or spec.id == "elite" then
                    R.PositionRuntimeLayoutIconPreview(icon, anchor, x, y, mock, false)
                elseif spec.id == "statusCombat" or spec.id == "statusResting" or spec.id == "statusIncomingRes" or spec.id == "statusPvp" then
                    R.PositionStatusCornerPreview(icon, anchor, x, y, mock, S(2))
                else
                    R.PositionFromAnchor(icon, anchor, x, y, mock, sz)
                end
            end
            handle:SetSize(max(18, icon:GetWidth() + 8), max(18, icon:GetHeight() + 8))
            PlaceHandle(handle, icon)
        else
            handle:Hide()
        end
    end
    if showRaidGroupName then statusLayerAvailable = true end
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
    if mock.totInlineSep and mock.totInlineSep:IsShown() then nameHandleW = nameHandleW + mock.totInlineSep:GetStringWidth() + mock.totInlineText:GetStringWidth() + S(8) end
    box.handleName:SetSize(max(46, nameHandleW), max(18, mock.nameText:GetStringHeight() + 6))
    if not UnitPreviewText.PlaceHandleAroundRegions(box.handleName, canvas, { mock.nameText, mock.totInlineSep, mock.totInlineText }, 3) then PlaceHandle(box.handleName, mock.nameText) end
    local function PlaceTextSlotHandle(handle, region)
        if not handle then return end
        if not (region and region.IsShown and region:IsShown()) then
            handle:Hide()
            return
        end
        local w = (region.GetStringWidth and region:GetStringWidth()) or region:GetWidth() or 36
        local h = (region.GetStringHeight and region:GetStringHeight()) or region:GetHeight() or 12
        handle:SetSize(max(26, w + 10), max(18, h + 6))
        if not UnitPreviewText.PlaceHandleAroundRegions(handle, canvas, { region }, 3) then PlaceHandle(handle, region) end
    end
    PlaceTextSlotHandle(box.handleRaidGroupName, mock.raidGroupNameText)
    local function PlaceValueTextHandles(kind, mainHandle, leftHandle, centerHandle, rightHandle, leftRegion, centerRegion, rightRegion)
        if UnitPreviewTextMovesTogether(key, kind) then
            SetShownSafe(leftHandle, false)
            SetShownSafe(centerHandle, false)
            SetShownSafe(rightHandle, false)
            if UnitPreviewText.PlaceHandleAroundRegions(mainHandle, canvas, { leftRegion, centerRegion, rightRegion }, 3) then return end
            if not ((leftRegion and leftRegion:IsShown()) or (centerRegion and centerRegion:IsShown()) or (rightRegion and rightRegion:IsShown())) then
                mainHandle:Hide()
                return
            end
            mainHandle:SetSize(max(46, rightRegion:GetStringWidth() + 10), max(18, rightRegion:GetStringHeight() + 6))
            PlaceHandle(mainHandle, rightRegion)
            return
        end
        if mainHandle then mainHandle:Hide() end
        PlaceTextSlotHandle(leftHandle, leftRegion)
        PlaceTextSlotHandle(centerHandle, centerRegion)
        PlaceTextSlotHandle(rightHandle, rightRegion)
    end
    PlaceValueTextHandles("hp", box.handleHP, box.handleHPLeft, box.handleHPCenter, box.handleHPRight, mock.hpTextLeft, mock.hpTextCenter, mock.hpText)
    PlaceValueTextHandles("power", box.handlePower, box.handlePowerLeft, box.handlePowerCenter, box.handlePowerRight, mock.powerTextLeft, mock.powerTextCenter, mock.powerText)
    R.ApplyPreviewTextFocus(box, canvas, mock)
    ApplyPreviewLayerVisibility(box)
    ApplyPreviewTransparency(box, conf)
    RefreshHandleSelectionVisuals(box)
end
end
