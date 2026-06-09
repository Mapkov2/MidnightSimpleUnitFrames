local _, ns = ...
ns = ns or {}

ns.MSUF_CastbarStyle = ns.MSUF_CastbarStyle or {}

local Style = ns.MSUF_CastbarStyle

local function GeneralDB()
    if type(EnsureDB) == "function" then
        EnsureDB()
    end

    return (_G.MSUF_DB and _G.MSUF_DB.general) or {}
end

local function NormalizeUnit(unit)
    unit = unit and tostring(unit) or ""
    if unit:match("^boss") then
        return "boss"
    end

    return unit
end

local function PrefixForUnit(unit)
    unit = NormalizeUnit(unit)

    if unit == "player" then
        return "castbarPlayer"
    end

    if unit == "target" then
        return "castbarTarget"
    end

    if unit == "focus" then
        return "castbarFocus"
    end

    return nil
end

local function SetAlpha(frame, alpha)
    if type(_G.MSUF_SetAlphaIfChanged) == "function" then
        _G.MSUF_SetAlphaIfChanged(frame, alpha)
    else
        frame:SetAlpha(alpha)
    end
end

local function SetText(fontString, text)
    if type(_G.MSUF_SetTextIfChanged) == "function" then
        _G.MSUF_SetTextIfChanged(fontString, text or "")
    else
        fontString:SetText(text or "")
    end
end

local function EnsureOutline(frame)
    if not frame or frame._msufOutline then
        return
    end

    local function CreateEdge()
        local texture = frame:CreateTexture(nil, "OVERLAY")
        texture:SetColorTexture(1, 1, 1, 1)
        texture:Hide()
        return texture
    end

    frame._msufOutline = {
        top = CreateEdge(),
        bottom = CreateEdge(),
        left = CreateEdge(),
        right = CreateEdge(),
    }
end

function Style:ApplyCastbarOutline(frame, force)
    if not frame then
        return
    end

    EnsureOutline(frame)

    local outline = frame._msufOutline
    local general = GeneralDB()
    local thickness = math.max(0, math.min(math.floor((tonumber(general.castbarOutlineThickness) or 1) + 0.5), 12))

    if thickness <= 0 then
        outline.top:Hide()
        outline.bottom:Hide()
        outline.left:Hide()
        outline.right:Hide()
        frame._msufOutlineT = 0
        return
    end

    local red = tonumber(general.castbarBorderR) or 0
    local green = tonumber(general.castbarBorderG) or 0
    local blue = tonumber(general.castbarBorderB) or 0
    local alpha = tonumber(general.castbarBorderA) or 1

    if force or frame._msufOutlineT ~= thickness then
        outline.top:ClearAllPoints()
        outline.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, thickness)
        outline.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, thickness)
        outline.top:SetHeight(thickness)

        outline.bottom:ClearAllPoints()
        outline.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, -thickness)
        outline.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, -thickness)
        outline.bottom:SetHeight(thickness)

        outline.left:ClearAllPoints()
        outline.left:SetPoint("TOPLEFT", frame, "TOPLEFT", -thickness, thickness)
        outline.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -thickness, -thickness)
        outline.left:SetWidth(thickness)

        outline.right:ClearAllPoints()
        outline.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", thickness, thickness)
        outline.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", thickness, -thickness)
        outline.right:SetWidth(thickness)

        frame._msufOutlineT = thickness
    end

    if force
        or frame._msufOutlineR ~= red
        or frame._msufOutlineG ~= green
        or frame._msufOutlineB ~= blue
        or frame._msufOutlineA ~= alpha
    then
        outline.top:SetVertexColor(red, green, blue, alpha)
        outline.bottom:SetVertexColor(red, green, blue, alpha)
        outline.left:SetVertexColor(red, green, blue, alpha)
        outline.right:SetVertexColor(red, green, blue, alpha)

        frame._msufOutlineR = red
        frame._msufOutlineG = green
        frame._msufOutlineB = blue
        frame._msufOutlineA = alpha
    end

    outline.top:Show()
    outline.bottom:Show()
    outline.left:Show()
    outline.right:Show()
end

function Style:ApplyCastbarOutlineToAll(force)
    local frames = {
        _G.MSUF_PlayerCastbar,
        _G.MSUF_TargetCastbar,
        _G.MSUF_FocusCastbar,
        _G.MSUF_PlayerCastbarPreview,
        _G.MSUF_TargetCastbarPreview,
        _G.MSUF_FocusCastbarPreview,
        _G.MSUF_BossCastbarPreview,
    }

    for bossIndex = 2, tonumber(_G.MAX_BOSS_FRAMES) or 5 do
        frames[#frames + 1] = _G["MSUF_BossCastbarPreview" .. bossIndex]
    end

    local bossCastbars = _G.MSUF_BossCastbars
    if type(bossCastbars) == "table" then
        for index = 1, #bossCastbars do
            frames[#frames + 1] = bossCastbars[index]
        end
    end

    for index = 1, #frames do
        if frames[index] then
            self:ApplyCastbarOutline(frames[index], force)
        end
    end
end

local function IsCastTimeEnabled(frame, unit, general)
    if type(_G.MSUF_IsCastTimeEnabled) == "function" then
        return _G.MSUF_IsCastTimeEnabled(frame or { unit = unit })
    end

    if unit == "player" then
        return general.showPlayerCastTime ~= false
    end

    if unit == "target" then
        return general.showTargetCastTime ~= false
    end

    if unit == "focus" then
        return general.showFocusCastTime ~= false
    end

    if unit == "boss" then
        return general.showBossCastTime ~= false
    end

    return true
end

local function TimeOffsets(general, unit)
    local prefix = PrefixForUnit(unit)
    local offsetX
    local offsetY

    if prefix then
        offsetX = general[prefix .. "TimeOffsetX"]
        offsetY = general[prefix .. "TimeOffsetY"]
    end

    if unit == "boss" then
        offsetX = general.bossCastTimeOffsetX
        offsetY = general.bossCastTimeOffsetY
    end

    if offsetX == nil then
        offsetX = general.castbarPlayerTimeOffsetX
    end

    if offsetY == nil then
        offsetY = general.castbarPlayerTimeOffsetY
    end

    return tonumber(offsetX) or -2, tonumber(offsetY) or 0
end

function Style:ApplyCastbarTimeTextLayout(frame, unit)
    if not (frame and frame.timeText and frame.statusBar) then
        return
    end

    local general = GeneralDB()
    unit = NormalizeUnit(unit or frame.unit)

    local showTime = IsCastTimeEnabled(frame, unit, general)
    frame.timeText:Show()
    SetAlpha(frame.timeText, showTime and 1 or 0)

    if not showTime then
        SetText(frame.timeText, "")
    end

    local offsetX, offsetY = TimeOffsets(general, unit)
    frame.timeText:ClearAllPoints()
    frame.timeText:SetPoint("RIGHT", frame.statusBar, "RIGHT", offsetX, offsetY)
    frame.timeText:SetJustifyH("RIGHT")

    if type(_G.MSUF_ApplyCastbarDetailTextLayout) == "function" then
        _G.MSUF_ApplyCastbarDetailTextLayout(frame, unit)
    end
end

function Style:ApplyBossCastbarTextsLayout(frame, options)
    if not (frame and frame.statusBar and frame.castText and frame.timeText) then
        return
    end

    options = options or {}

    local baselineTimeX = tonumber(options.baselineTimeX) or -2
    local baselineTimeY = tonumber(options.baselineTimeY) or 0
    local textOffsetX = tonumber(options.textOffsetX) or 0
    local textOffsetY = tonumber(options.textOffsetY) or 0
    local timeOffsetX = tonumber(options.timeOffsetX) or baselineTimeX
    local timeOffsetY = tonumber(options.timeOffsetY) or baselineTimeY

    frame.castText:ClearAllPoints()
    frame.timeText:ClearAllPoints()
    frame.castText:SetJustifyH("LEFT")
    frame.timeText:SetJustifyH("RIGHT")
    frame.castText:SetPoint("LEFT", frame.statusBar, "LEFT", 2 + textOffsetX, textOffsetY)
    frame.timeText:SetPoint("RIGHT", frame.statusBar, "RIGHT", timeOffsetX, timeOffsetY)
    frame.castText:SetPoint("RIGHT", frame.timeText, "LEFT", -6, 0)

    if options.showName ~= nil then
        frame.castText:Show()
        SetAlpha(frame.castText, options.showName and 1 or 0)

        if not options.showName and options.clearIfHidden ~= false then
            SetText(frame.castText, "")
        end
    end

    if options.showTime ~= nil then
        frame.timeText:Show()
        SetAlpha(frame.timeText, options.showTime and 1 or 0)

        if not options.showTime and options.clearIfHidden ~= false then
            SetText(frame.timeText, "")
        end
    end

    if tonumber(options.nameFontSize) then
        local fontPath, _, fontFlags = frame.castText:GetFont()
        frame.castText:SetFont(fontPath, tonumber(options.nameFontSize), fontFlags)
    end

    if tonumber(options.timeFontSize) then
        local fontPath, _, fontFlags = frame.timeText:GetFont()
        frame.timeText:SetFont(fontPath, tonumber(options.timeFontSize), fontFlags)
    end

    if type(_G.MSUF_ApplyCastbarDetailTextLayout) == "function" then
        _G.MSUF_ApplyCastbarDetailTextLayout(frame, "boss")
    end
end

function _G.MSUF_UpdateCastbarFillDirection()
    local function Apply(frame)
        if not (frame and frame.statusBar) then
            return
        end

        local isChanneledOrEmpowered = frame.isEmpower
            or frame.MSUF_isChanneled
            or (frame.unit and UnitChannelInfo and UnitChannelInfo(frame.unit))

        local reverseFill = type(_G.MSUF_GetReverseFillSafe) == "function"
            and _G.MSUF_GetReverseFillSafe(frame, isChanneledOrEmpowered and true or false)
            or false

        if type(_G.MSUF_ApplyCastbarTimerDirection) == "function" then
            _G.MSUF_ApplyCastbarTimerDirection(
                frame.statusBar,
                frame.MSUF_durationObj,
                reverseFill,
                isChanneledOrEmpowered
            )
        elseif frame.statusBar.SetReverseFill then
            frame.statusBar:SetReverseFill(reverseFill and true or false)
        end
    end

    Apply(_G.MSUF_PlayerCastbar)
    Apply(_G.MSUF_TargetCastbar)
    Apply(_G.MSUF_FocusCastbar)
    Apply(_G.MSUF_PlayerCastbarPreview)
    Apply(_G.MSUF_TargetCastbarPreview)
    Apply(_G.MSUF_FocusCastbarPreview)

    local bossCastbars = _G.MSUF_BossCastbars
    if type(bossCastbars) == "table" then
        for index = 1, #bossCastbars do
            Apply(bossCastbars[index])
        end
    end

    if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals()
    end
end

_G.MSUF_ApplyCastbarOutline = function(frame, force)
    return Style:ApplyCastbarOutline(frame, force)
end

_G.MSUF_ApplyCastbarOutlineToAll = function(force)
    return Style:ApplyCastbarOutlineToAll(force)
end

_G.MSUF_ApplyBossCastbarTextsLayout = function(frame, options)
    return Style:ApplyBossCastbarTextsLayout(frame, options)
end

_G.MSUF_ApplyCastbarTimeTextLayout = function(frame, unit)
    return Style:ApplyCastbarTimeTextLayout(frame, unit)
end
