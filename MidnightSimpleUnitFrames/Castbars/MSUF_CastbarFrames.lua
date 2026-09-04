--- Castbars/MSUF_CastbarFrames.lua
--- Frame construction helpers for real castbars and menu/edit previews.
---
--- This file creates regions and initial visual structure only. Runtime applies
--- live cast state, Visuals applies profile-driven detail layout, and Anchors
--- moves/sizes existing frames.

local G = _G

local function Translate(text)
    local ns = G.MSUF_NS
    local locale = (type(ns) == "table" and ns.L) or G.MSUF_L

    if type(ns) == "table" and type(ns.Translate) == "function" then
        return ns.Translate(text)
    end

    return (type(locale) == "table" and rawget(locale, text)) or text
end

local function CastbarTexture()
    return (type(MSUF_GetCastbarTexture) == "function" and MSUF_GetCastbarTexture())
        or "Interface\\TargetingFrame\\UI-StatusBar"
end

local function CastbarBackgroundTexture()
    local texture = CastbarTexture()

    if type(G.MSUF_GetCastbarBackgroundTexture) == "function" then
        local backgroundTexture = G.MSUF_GetCastbarBackgroundTexture()
        if backgroundTexture and backgroundTexture ~= "" then
            texture = backgroundTexture
        end
    end

    return texture
end

local function CastbarBackgroundColor()
    if type(G.MSUF_GetCastbarBackgroundColor) == "function" then
        return G.MSUF_GetCastbarBackgroundColor()
    end

    return 0.176, 0.176, 0.176, 1
end

local function CreateSpark(statusBar, height)
    local spark = statusBar:CreateTexture(nil, "OVERLAY", nil, 6)
    spark:SetTexture(4417031)
    spark:SetTexCoord(0.222168, 0.232422, 0.294434, 0.317383)
    spark:SetDesaturated(true)
    spark:SetVertexColor(1, 1, 1, 1)
    spark:SetBlendMode("ADD")
    spark:SetSize(16, height * 2.1)

    -- Moving edge = side opposite the fill anchor; the timer apply path
    -- re-anchors on direction changes (see Runtime:ApplyTimer).
    local statusBarTexture = statusBar:GetStatusBarTexture()
    local reversed = statusBar.GetReverseFill and statusBar:GetReverseFill() and true or false
    if statusBarTexture then
        spark:SetPoint("CENTER", statusBarTexture, reversed and "LEFT" or "RIGHT", 0, 0)
    else
        spark:SetPoint("CENTER", statusBar, reversed and "RIGHT" or "LEFT", 0, 0)
    end
    spark:Hide()

    return spark
end

local function CreateText(parent, justifyH, point, relativeTo, offsetX)
    local fontPath, fontSize, fontFlags = GameFontHighlight:GetFont()
    local text = parent:CreateFontString(nil, "OVERLAY")

    text:SetFont(fontPath, fontSize, fontFlags)
    text:SetJustifyH(justifyH)
    text:SetPoint(point, relativeTo, point, offsetX or 0, 0)

    return text
end

--- Builds the common frame element set used by target/focus/boss style castbars:
--- background, status bar, icon, text, time text, spark, and outline.
function G.MSUF_BuildCastbarFrameElements(frame)
    local barHeight = 18

    frame:SetHeight(barHeight)
    if (not frame:GetWidth()) or frame:GetWidth() == 0 then
        frame:SetWidth(250)
    end

    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetAllPoints(frame)
    frame.background:SetColorTexture(0, 0, 0, 0)

    local statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetPoint("LEFT", frame, "LEFT", barHeight + 1, 0)
    statusBar:SetSize(frame:GetWidth() - barHeight - 1, frame:GetHeight())
    statusBar:SetStatusBarTexture(CastbarTexture())

    -- Statusbar art is 256px wide while castbars default to 271/272px, so tiling
    -- would repeat the texture and leave a visible seam near the right edge.
    -- Stretch instead, matching how health/power bars consume the same media.
    if statusBar:GetStatusBarTexture() then
        statusBar:GetStatusBarTexture():SetHorizTile(false)
    end

    if type(G.MSUF_ApplyCastbarTimerDirection) == "function" then
        G.MSUF_ApplyCastbarTimerDirection(
            statusBar,
            nil,
            type(MSUF_GetCastbarReverseFillForFrame) == "function" and MSUF_GetCastbarReverseFillForFrame(frame, false)
        )
    elseif statusBar.SetReverseFill and type(MSUF_GetCastbarReverseFillForFrame) == "function" then
        statusBar:SetReverseFill(MSUF_GetCastbarReverseFillForFrame(frame, false))
    end

    frame.statusBar = statusBar

    frame.icon = statusBar:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.icon:SetSize(barHeight, barHeight)
    frame.icon:SetPoint("LEFT", frame, "LEFT", 0, 0)

    frame.backgroundBar = statusBar:CreateTexture(nil, "BACKGROUND")
    frame.backgroundBar:SetAllPoints(statusBar)
    frame.backgroundBar:SetTexture(CastbarBackgroundTexture())
    frame.backgroundBar:SetVertexColor(CastbarBackgroundColor())

    frame.castText = statusBar:CreateFontString(nil, "OVERLAY")
    frame.castText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    frame.castText:SetPoint("LEFT", statusBar, "LEFT", 2, 0)

    frame.timeText = statusBar:CreateFontString(nil, "OVERLAY")
    frame.timeText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    frame.timeText:SetPoint("RIGHT", statusBar, "RIGHT", -2, 0)
    frame.timeText:SetText("")

    if frame.unit == "target" or frame.unit == "focus" or tostring(frame.unit or ""):match("^boss%d+$") then
        frame.castTargetText = statusBar:CreateFontString(nil, "OVERLAY")
        frame.CastTargetNameText = frame.castTargetText
        frame.castTargetText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        frame.castTargetText:SetJustifyH("RIGHT")
        frame.castTargetText:SetPoint("TOPLEFT", statusBar, "BOTTOMLEFT", 2, -1)
        frame.castTargetText:SetPoint("TOPRIGHT", statusBar, "BOTTOMRIGHT", -2, -1)
        frame.castTargetText:SetText("")
        frame.castTargetText:Hide()
    end

    frame.spark = CreateSpark(statusBar, barHeight)

    if type(G.MSUF_ApplyCastbarOutline) == "function" then
        G.MSUF_ApplyCastbarOutline(frame, true)
    end
end

--- Preview frames are intentionally non-secure and self-contained. They mimic
--- real castbar regions closely enough for menu/edit-mode layout without
--- subscribing to live spellcast events.
function G.MSUF_CreateCastbarPreviewFrame(unit, name, options)
    options = options or {}

    local parent = options.parent or UIParent
    local width = tonumber(options.width) or 250
    local height = tonumber(options.height) or 18
    local statusBarHeight = tonumber(options.statusBarHeight) or height

    local frame = CreateFrame("Frame", name, parent, options.template or "BackdropTemplate")
    frame.unit = unit
    frame._msufIsPreview = true
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata(options.strata or "DIALOG")
    frame:SetSize(width, height)

    frame._msufFrameBG = frame:CreateTexture(nil, "BACKGROUND")
    frame._msufFrameBG:SetAllPoints(frame)
    frame._msufFrameBG:SetColorTexture(0, 0, 0, 0)

    local statusBar = CreateFrame("StatusBar", nil, frame)
    if frame.GetFrameLevel and statusBar.SetFrameLevel then
        statusBar:SetFrameLevel(frame:GetFrameLevel() + 1)
    end

    statusBar:SetPoint("LEFT", frame, "LEFT", 0, 0)
    statusBar:SetSize(width, statusBarHeight)
    statusBar:SetStatusBarTexture(CastbarTexture())

    if statusBar:GetStatusBarTexture() then
        statusBar:GetStatusBarTexture():SetHorizTile(false)
    end

    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(tonumber(options.initialValue) or 0)
    frame.statusBar = statusBar

    frame.backgroundBar = statusBar:CreateTexture(nil, "BACKGROUND")
    frame.backgroundBar:SetAllPoints(statusBar)
    frame.backgroundBar:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.backgroundBar:SetVertexColor(CastbarBackgroundColor())
    frame.backgroundBar:SetAlpha(0.25)

    if options.hideFillTexture and statusBar:GetStatusBarTexture() then
        statusBar:GetStatusBarTexture():SetAlpha(0)
        statusBar.MSUF_hideFillTexture = true
    end

    if unit == "player" then
        frame.latencyBar = statusBar:CreateTexture(nil, "OVERLAY")
        frame.latencyBar:SetColorTexture(1, 0, 0, 0.25)
        frame.latencyBar:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT")
        frame.latencyBar:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT")
        frame.latencyBar:SetWidth(0)
        frame.latencyBar:Hide()
    end

    if options.showIcon ~= false then
        local iconSize = tonumber(options.iconSize) or height

        frame.icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        frame.icon:SetSize(iconSize, iconSize)
        frame.icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
        frame.icon:SetTexture(options.iconTexture or 136235)
    end

    local textOverlay = CreateFrame("Frame", nil, frame)
    textOverlay:SetAllPoints(statusBar)
    if textOverlay.SetFrameLevel and statusBar.GetFrameLevel then
        textOverlay:SetFrameLevel(statusBar:GetFrameLevel() + 10)
    end

    frame._msufTextOverlay = textOverlay

    local label = options.label
        or (unit == "player" and "Player castbar preview")
        or (unit == "target" and "Target castbar preview")
        or (unit == "focus" and "Focus castbar preview")
        or (unit == "boss" and "Boss castbar preview")
        or "Castbar preview"

    local castTextJustify = unit == "boss" and "LEFT" or "CENTER"
    frame.castText = CreateText(textOverlay, castTextJustify, "LEFT", textOverlay, 2)
    frame.castText:SetText(Translate(label))

    if options.showTime ~= false then
        frame.timeText = CreateText(textOverlay, "RIGHT", "RIGHT", textOverlay, -2)
        frame.timeText:SetText(options.timeLabel or "3.2")
    end

    if unit == "target" or unit == "focus" or unit == "boss" then
        frame.castTargetText = statusBar:CreateFontString(nil, "OVERLAY")
        frame.CastTargetNameText = frame.castTargetText
        frame.castTargetText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        frame.castTargetText:SetText("")
        frame.castTargetText:Hide()
    end

    frame.spark = CreateSpark(statusBar, statusBarHeight)

    if type(G.MSUF_ApplyCastbarOutline) == "function" then
        G.MSUF_ApplyCastbarOutline(frame, true)
    end

    return frame
end
