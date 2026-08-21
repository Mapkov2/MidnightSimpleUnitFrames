--- Castbars/MSUF_CastbarStyle.lua
--- Shared castbar outline, time text layout, boss text layout, and fill-direction
--- helpers.
---
--- Style is allowed to touch existing regions, but not to create cast-state or
--- register events. Runtime/Driver own live casts; Visuals owns richer per-unit
--- detail layout.

local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

ns.MSUF_CastbarStyle = ns.MSUF_CastbarStyle or {}

local Style = ns.MSUF_CastbarStyle
local floor, ceil = math.floor, math.ceil
local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local OUTLINE_BACKDROPS = {}

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

local function FrameStateIsChanneledOrEmpowered(frame)
    if not (frame and frame.unit) then return false end
    local buildState = _G.MSUF_BuildCastState
    if type(buildState) ~= "function" then
        return UnitChannelInfo and UnitChannelInfo(frame.unit) and true or false
    end
    local state = buildState(frame.unit, frame)
    return state and (state.castType == "CHANNEL" or state.castType == "EMPOWER") or false
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

local function EffectiveScale(region)
    if region and region.GetEffectiveScale then
        local scale = region:GetEffectiveScale()
        if scale and scale > 0 then return scale end
    end
    if UIParent and UIParent.GetEffectiveScale then
        local scale = UIParent:GetEffectiveScale()
        if scale and scale > 0 then return scale end
    end
    return 1
end

local function PixelSize(region, value, minPixels)
    value = tonumber(value) or 0
    if value == 0 then return 0 end
    local scale = EffectiveScale(region)
    if _G.PixelUtil and type(_G.PixelUtil.GetNearestPixelSize) == "function" then
        local size = _G.PixelUtil.GetNearestPixelSize(value, scale, minPixels)
        if size and size ~= 0 then return size end
    end

    local factor = 1
    if type(_G.GetPhysicalScreenSize) == "function" then
        local _, physicalHeight = _G.GetPhysicalScreenSize()
        physicalHeight = tonumber(physicalHeight) or 0
        if physicalHeight > 0 then factor = 768 / physicalHeight end
    end
    local pixels = value * scale / factor
    pixels = pixels >= 0 and floor(pixels + 0.5) or ceil(pixels - 0.5)
    minPixels = tonumber(minPixels) or 0
    if minPixels > 0 and pixels == 0 then pixels = value < 0 and -minPixels or minPixels end
    return pixels * factor / scale
end

local function NormalizeOutlineThickness(general)
    return math.max(0, math.min(floor((tonumber(general and general.castbarOutlineThickness) or 1) + 0.5), 12))
end

local function OutlineEdge(frame, general)
    local thickness = NormalizeOutlineThickness(general)
    if thickness <= 0 then return 0, 0 end
    local edge = PixelSize(frame, thickness, 1)
    if edge <= 0 then edge = thickness end
    return edge, thickness
end

function Style:GetCastbarOutlineInset(frame, general)
    local edge = OutlineEdge(frame, general or GeneralDB())
    return edge
end

local function BackdropForEdge(edge)
    local key = tostring(edge)
    local backdrop = OUTLINE_BACKDROPS[key]
    if not backdrop then
        backdrop = {
            bgFile = WHITE8,
            edgeFile = WHITE8,
            edgeSize = edge,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        }
        OUTLINE_BACKDROPS[key] = backdrop
    end
    return backdrop
end

local function EnsureOutlineHost(frame)
    local host = frame and frame._msufOutlineHost
    if host and not host.SetBackdrop then
        host:Hide()
        host = nil
    end
    if not host then
        host = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        host:EnableMouse(false)
        frame._msufOutlineHost = host
    end

    host:ClearAllPoints()
    host:SetAllPoints(frame)

    if host.SetFrameLevel then
        local baseLevel = 0
        if frame.statusBar and frame.statusBar.GetFrameLevel then
            baseLevel = frame.statusBar:GetFrameLevel() or 0
        elseif frame.GetFrameLevel then
            baseLevel = frame:GetFrameLevel() or 0
        end
        local level = baseLevel + 20
        if host._msufOutlineHostLevel ~= level then
            host:SetFrameLevel(level)
            host._msufOutlineHostLevel = level
        end
    end

    return host
end

local function EnsureOutline(frame)
    if not frame then
        return
    end

    local host = EnsureOutlineHost(frame)
    if not host then
        return
    end

    local old = frame._msufOutline
    if old and old._host ~= host then
        if old.top then old.top:Hide() end
        if old.bottom then old.bottom:Hide() end
        if old.left then old.left:Hide() end
        if old.right then old.right:Hide() end
        frame._msufOutlineT = nil
        frame._msufOutlineR = nil
        frame._msufOutlineG = nil
        frame._msufOutlineB = nil
        frame._msufOutlineA = nil
    end

    frame._msufOutline = { _host = host }
end

function Style:ApplyCastbarOutline(frame, force)
    if not frame then
        return
    end

    local general = GeneralDB()
    local edge, thickness = OutlineEdge(frame, general)
    local red = tonumber(general.castbarBorderR) or 0
    local green = tonumber(general.castbarBorderG) or 0
    local blue = tonumber(general.castbarBorderB) or 0
    local alpha = tonumber(general.castbarBorderA) or 1
    local applyRounded = _G.MSUF_RoundedCastbar_ApplyOutline
    if type(applyRounded) == "function"
        and applyRounded(frame, edge, thickness, red, green, blue, alpha) then
        return
    end

    if thickness <= 0 then
        local host = frame._msufOutlineHost
        if host then
            host:SetBackdrop(nil)
            host:Hide()
        end
        frame._msufOutlineT = 0
        frame._msufOutlineEdge = 0
        frame._msufOutlineR = nil
        frame._msufOutlineG = nil
        frame._msufOutlineB = nil
        frame._msufOutlineA = nil
        return
    end

    EnsureOutline(frame)
    local host = frame._msufOutlineHost
    if not host then return end

    local backdropChanged = force or frame._msufOutlineT ~= thickness or frame._msufOutlineEdge ~= edge
    if backdropChanged then
        host:SetBackdrop(BackdropForEdge(edge))
        host:SetBackdropColor(0, 0, 0, 0)
        frame._msufOutlineT = thickness
        frame._msufOutlineEdge = edge
    end

    -- BackdropTemplateMixin:ApplyBackdrop resets every edge piece to white.
    -- Reapply the configured color whenever SetBackdrop rebuilt the outline,
    -- even when our RGB cache itself did not change.
    if backdropChanged
        or frame._msufOutlineR ~= red
        or frame._msufOutlineG ~= green
        or frame._msufOutlineB ~= blue
        or frame._msufOutlineA ~= alpha
    then
        host:SetBackdropBorderColor(red, green, blue, alpha)

        frame._msufOutlineR = red
        frame._msufOutlineG = green
        frame._msufOutlineB = blue
        frame._msufOutlineA = alpha
    end

    host:Show()
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

--- Boss castbars use a compact left-name/right-time layout. Detail-layout code
--- may refine fonts/positions afterward, but this keeps old boss callers stable.
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
        local size = tonumber(options.nameFontSize) or 12
        if size <= 0 then size = 12 end
        if size < 6 then size = 6 elseif size > 128 then size = 128 end
        if fontPath then frame.castText:SetFont(fontPath, size, fontFlags) end
    end

    if tonumber(options.timeFontSize) then
        local fontPath, _, fontFlags = frame.timeText:GetFont()
        local size = tonumber(options.timeFontSize) or 12
        if size <= 0 then size = 12 end
        if size < 6 then size = 6 elseif size > 128 then size = 128 end
        if fontPath then frame.timeText:SetFont(fontPath, size, fontFlags) end
    end

    if type(_G.MSUF_ApplyCastbarDetailTextLayout) == "function" then
        _G.MSUF_ApplyCastbarDetailTextLayout(frame, "boss")
    end
end

--- Re-apply fill direction to every existing castbar after profile changes.
--- Active timer objects are preserved and only their direction is refreshed.
local function UpdateCastbarFillDirection()
    local function Apply(frame)
        if not (frame and frame.statusBar) then
            return
        end

        local isChanneledOrEmpowered = frame.isEmpower
            or frame.MSUF_isChanneled
            or FrameStateIsChanneledOrEmpowered(frame)

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

    local applyUnit = _G.MSUF_ApplyCastbarVisualsForUnit
    if type(applyUnit) == "function" then
        applyUnit("player")
        applyUnit("target")
        applyUnit("focus")
        applyUnit("boss")
    elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals()
    end
end

ExportPublic("MSUF_UpdateCastbarFillDirection", UpdateCastbarFillDirection)

ExportPublic("MSUF_ApplyCastbarOutline", function(frame, force)
    return Style:ApplyCastbarOutline(frame, force)
end)

ExportPublic("MSUF_ApplyCastbarOutlineToAll", function(force)
    return Style:ApplyCastbarOutlineToAll(force)
end)

ExportPublic("MSUF_GetCastbarOutlineInset", function(frame, general)
    return Style:GetCastbarOutlineInset(frame, general)
end)

ExportPublic("MSUF_ApplyBossCastbarTextsLayout", function(frame, options)
    return Style:ApplyBossCastbarTextsLayout(frame, options)
end)

ExportPublic("MSUF_ApplyCastbarTimeTextLayout", function(frame, unit)
    return Style:ApplyCastbarTimeTextLayout(frame, unit)
end)
