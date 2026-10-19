local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Core.lua
--- Cold-path shared helpers for the MSUF2 unit frame preview.
local addonName, addonNS = ...
local MSUF = addonNS or (_G.MSUF_NS) or {}
local ExportPublic = MSUF.ExportPublic
local floor = math.floor
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"
local Preview = MSUF.UFPreview or {}
MSUF.UFPreview = Preview
ExportPublic("MSUF_UFPreview", Preview)
local PreviewHelpers = (MSUF.MSUF2 and MSUF.MSUF2.PreviewHelpers) or {}
local Layers = MSUF.UF and MSUF.UF.Layers or {}
local Core = MSUF.UFPreviewCore or {}
MSUF.UFPreviewCore = Core
function Core.MenuTheme()
    local m = MSUF and MSUF.MSUF2
    return m and m.Theme
end
function Core.ApplyBackdrop(frame, bg, border, fallback)
    local T = Core.MenuTheme()
    if T and type(T.ApplyBackdrop) == "function" then
        T.ApplyBackdrop(frame, bg, border)
        return
    end
    if not (frame and frame.SetBackdrop) then return end
    fallback = fallback or {}
    PixelLayoutRegion(frame, "SetBackdrop", fallback.backdrop or {
        bgFile = TEX_W8,
        edgeFile = TEX_W8,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    local b = bg or fallback.bg or { 0.035, 0.043, 0.058, 0.96 }
    local e = border or fallback.border or { 0.19, 0.25, 0.34, 0.95 }
    frame:SetBackdropColor(b[1], b[2], b[3], b[4] or 1)
    frame:SetBackdropBorderColor(e[1], e[2], e[3], e[4] or 1)
end
function Core.RoundOffset(v)
    v = tonumber(v) or 0
    if v >= 0 then return floor(v + 0.5) end
    return -floor((-v) + 0.5)
end
function Core.ClampLayer(v, fallback)
    v = floor((tonumber(v) or fallback or 0) + 0.5)
    if v < 0 then return 0 end
    if v > 30 then return 30 end
    return v
end
function Core.PlaceHandle(handle, target, pad)
    if not handle or not target or not target.GetCenter then return end
    handle:ClearAllPoints()
    handle:SetPoint("CENTER", target, "CENTER", pad or 0, 0)
    handle:SetShown(target:IsShown())
end
function Core.InteractionFrameLevel(parent, extra)
    local parentLevel = parent and parent.GetFrameLevel and tonumber(parent:GetFrameLevel()) or 0
    local level = parentLevel + 30
    if Layers.ElementLevel then
        local absoluteTop = tonumber(Layers.ElementLevel(30, 30, Layers.ELEMENT_DETAIL_MAX or 31))
        if absoluteTop then
            absoluteTop = absoluteTop
                + (tonumber(parent and parent._msufPreviewElementLevelBias) or 0)
            -- Share the interaction plane already used by Aura handles: one
            -- complete level slot above every configurable visual layer.
            absoluteTop = absoluteTop + (tonumber(Layers.ELEMENT_LEVEL_STRIDE) or 32)
            if absoluteTop > level then level = absoluteTop end
        end
    end
    return floor(level + (tonumber(extra) or 0) + 0.5)
end
function Core.SetShownSafe(region, shown)
    if region and region.SetShown then region:SetShown(shown and true or false) end
end
local BOUNDS_GUIDE_OPTS = {
    keys = { "top", "bottom", "left", "right" }, linesKey = "_msufGuideLines", texture = TEX_W8,
    snapOff = PreviewHelpers.SnapOff, color = function() return 0.25, 0.75, 0.88, 0.92 end,
}
function Core.ApplyBoundsGuide(box, edgeSize)
    local mock = box and box.mock
    local bounds = mock and mock.bounds
    if not bounds then return end
    edgeSize = floor((tonumber(edgeSize) or 1) + 0.5)
    if edgeSize < 1 then edgeSize = 1 elseif edgeSize > 30 then edgeSize = 30 end
    if bounds.SetBackdropColor then bounds:SetBackdropColor(0, 0, 0, 0) end
    if bounds.SetBackdropBorderColor then bounds:SetBackdropBorderColor(0, 0, 0, 0) end
    bounds:ClearAllPoints()
    bounds:SetPoint("TOPLEFT", mock, "TOPLEFT", -edgeSize, edgeSize)
    bounds:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", edgeSize, -edgeSize)
    if PreviewHelpers.LayoutEdgeLines then PreviewHelpers.LayoutEdgeLines(bounds, edgeSize, BOUNDS_GUIDE_OPTS) end
end
function Core.ApplyLayerVisibility(box)
    if not box or not box.mock then return end
    local visible, available = box.layerVisibility or {}, box.layerAvailable or {}
    local function On(key) return visible[key] ~= false and available[key] ~= false end
    local mock = box.mock
    if box._unitScene then box._unitScene:SetLayerFilter(visible) end
    local layers = {
        nameText = { box.handleName }, hpText = { box.handleHP, box.handleHPLeft, box.handleHPCenter, box.handleHPRight },
        powerText = { box.handlePower, box.handlePowerLeft, box.handlePowerCenter, box.handlePowerRight },
        power = { box.handleDetachedPower }, portrait = { box.handlePortrait },
        classPower = { mock.classPower, box.handleClassPower, box.handleClassPowerText },
        castbar = { mock.cast, box.handleCastbar, box.handleCastbarIcon, box.handleCastbarText, box.handleCastbarTarget, box.handleCastbarTime },
        buff = { box.handleAuraBuffs }, debuff = { box.handleAuraDebuffs },
        auras = { box.handleAuraCustom1, box.handleAuraCustom2, box.handleAuraCustom3, box.handleAuraCustom4 },
        dispelSymbol = { box.handleDispelSymbol },
    }
    for key, regions in pairs(layers) do
        if not On(key) then for _, region in pairs(regions) do Core.SetShownSafe(region, false) end end
    end
    if not On("status") then
        for _, handle in pairs(box.statusHandles or {}) do handle:Hide() end
    end
    if not On("texLayer") then for _, handle in pairs(box.texLayerHandles or {}) do handle:Hide() end end
    if not On("trinket") then
        Core.SetShownSafe(mock._msufArenaTrinketPreview, false)
        Core.SetShownSafe(box.handleArenaTrinket, false)
    end
    Core.SetShownSafe(mock.bounds, On("bounds"))
    Core.SetShownSafe(mock.sizeTag, On("bounds"))
    if mock.cast and mock.cast.sizeTag then Core.SetShownSafe(mock.cast.sizeTag, On("guides") and On("castbar")) end
end
function Core.InCombat()
    -- Blizzard's live lockdown state is authoritative for preview deferral.
    -- MSUF_InCombat is runtime-owned and can briefly remain latched after combat;
    -- consulting it first would strand the preview waiting for an event that has
    -- already fired. Keep it only as a fallback for non-client/test environments.
    local inCombatLockdown = _G.InCombatLockdown
    if type(inCombatLockdown) == "function" then
        return inCombatLockdown() == true
    end
    return _G.MSUF_InCombat == true
end
