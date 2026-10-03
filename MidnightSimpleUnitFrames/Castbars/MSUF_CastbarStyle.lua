local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Castbars/MSUF_CastbarStyle.lua
--- Shared castbar outline helpers (the outline host, its inset and colour).
---
--- Style is allowed to touch existing regions, but not to create cast-state or
--- register events. Runtime/Driver own live casts; Visuals owns the per-unit
--- icon, spell text and time text layout.

local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic

ns.MSUF_CastbarStyle = ns.MSUF_CastbarStyle or {}

local Style = ns.MSUF_CastbarStyle
local floor, ceil = math.floor, math.ceil
local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local OUTLINE_BACKDROPS = {}

local function GeneralDB()
    if type(_G.MSUF_EnsureDB) == "function" then
        _G.MSUF_EnsureDB()
    end

    return (_G.MSUF_DB and _G.MSUF_DB.general) or {}
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
        host = PixelLayoutRegion(CreateFrame("Frame", nil, frame, "BackdropTemplate"))
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

local function RefreshInterruptOutline(frame)
    if not frame._kickReadyBorderTinted then return end
    -- The style owner just rebuilt/recolored the actual edges. A cached
    -- readiness key no longer proves that its tint is on those edges.
    local refresh = _G.MSUF_KickReady_RefreshOutline
    if type(refresh) == "function" then refresh(frame) end
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
        RefreshInterruptOutline(frame)
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
        frame._msufKickReadyVisualKey = nil
        frame._kickReadyBorderTinted = nil
        return
    end

    EnsureOutline(frame)
    local host = frame._msufOutlineHost
    if not host then return end

    local backdropChanged = force or frame._msufOutlineT ~= thickness or frame._msufOutlineEdge ~= edge
    if backdropChanged then
        PixelLayoutRegion(host, "SetBackdrop", BackdropForEdge(edge))
        host:SetBackdropColor(0, 0, 0, 0)
        frame._msufOutlineT = thickness
        frame._msufOutlineEdge = edge
    end

    -- BackdropTemplateMixin:ApplyBackdrop resets every edge piece to white.
    -- Reapply the configured color whenever SetBackdrop rebuilt the outline,
    -- even when our RGB cache itself did not change.
    local colorChanged = backdropChanged
        or frame._msufOutlineR ~= red
        or frame._msufOutlineG ~= green
        or frame._msufOutlineB ~= blue
        or frame._msufOutlineA ~= alpha
    if colorChanged then
        host:SetBackdropBorderColor(red, green, blue, alpha)

        frame._msufOutlineR = red
        frame._msufOutlineG = green
        frame._msufOutlineB = blue
        frame._msufOutlineA = alpha
    end

    host:Show()
    if colorChanged then RefreshInterruptOutline(frame) end
end

ExportPublic("MSUF_ApplyCastbarOutline", function(frame, force)
    return Style:ApplyCastbarOutline(frame, force)
end)

ExportPublic("MSUF_GetCastbarOutlineInset", function(frame, general)
    return Style:GetCastbarOutlineInset(frame, general)
end)
