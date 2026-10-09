--- Shell/Menu2/Pages/MSUF_Menu2_UnitArenaTrinket.lua
--- Arena page: the "PvP Trinket" section and the trinket icon of the arena unit
--- preview. Both read MSUF.ArenaTrinkets (Features/Gameplay/
--- MSUF_Feature_ArenaTrinkets.lua): the resolver, factory values and show rule
--- the live holders use, so the menu preview, the arena frame preview (menu and
--- Edit Mode show the live holders themselves) and the match agree exactly.
local _, MSUF = ...
-- The Options bootstrap links this namespace to the core one and creates MSUF2;
-- the unit page registry (Pages/MSUF_Menu2_UnitLazy.lua) loads before this file.
local M = MSUF.MSUF2
local W, UP = M.Widgets, M.UnitPage
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Shell/Menu2/Pages/MSUF_Menu2_UnitArenaTrinket.lua")
local floor = math.floor

local SECTION_ID = "pvp_trinket"
-- Control identities; search shows the segment as the breadcrumb "Unit > Trinket".
local CONTROL_PATH = "trinket."
local SECTION_HEIGHT = 270
local CARD_HEIGHT = 216
local APPLY_REASON = "MSUF2_ARENA_TRINKET"
local SIDE_CHOICES = {
    { value = "RIGHT", text = "Right" },
    { value = "LEFT", text = "Left" },
    { value = "TOP", text = "Top" },
    { value = "BOTTOM", text = "Bottom" },
}
-- Share of the sample icon the static swipe darkens: 78 of 120 seconds left.
local SAMPLE_SWIPE_SHARE = 0.65

--- Section fields for Reset section (Unit page section actions); the trinket is
--- arena-only, so the section has nothing to copy to another frame.
UP.ARENA_TRINKET_FIELDS = "showTrinket trinketSize trinketAnchor trinketOffsetX trinketOffsetY trinketLayer"

local function BuildArenaTrinket(ctx, builder, unit)
    local runtime = MSUF.ArenaTrinkets
    local defaults, limits = runtime.DEFAULTS, runtime.LIMITS
    local ReadBool, SetBool, ReadNumber, SetNumber = UP.ReadBool, UP.SetBool, UP.ReadNumber, UP.SetNumber
    local GetConf, SetString, SettingMeta = UP.GetConf, UP.SetString, UP.SettingMeta
    local sec = builder:CollapsibleSection(SECTION_ID, "PvP Trinket", SECTION_HEIGHT, false)
    local width = math.max(340, ((sec and sec._msuf2Width) or (ctx and ctx.width) or 720) - 40)
    local half = floor((width - 16) / 2)
    local iconCard = W.ControlCard(sec, "Icon", nil, 20, -38, half, CARD_HEIGHT)
    local placeCard = W.ControlCard(sec, "Position", nil, 36 + half, -38, width - half - 16, CARD_HEIGHT)
    local controlW = half - 32
    local opts = { preview = true }

    local function Meta(path, key)
        local meta = SettingMeta(ctx, CONTROL_PATH .. path, unit, key)
        meta.step, meta.roundStep = 1, true
        return meta
    end
    local function NumberRow(card, label, key, low, high, fallback, y, path)
        return M.BindSliderAt(ctx, card, label, 16, y, low, high, 1, controlW,
            function() return ReadNumber(unit, key, fallback) end,
            function(value) SetNumber(unit, key, value, APPLY_REASON, opts) end,
            Meta(path, key))
    end

    local RefreshGate = M.RefreshProxy()
    local shown = M.BindToggleAt(ctx, iconCard, "Show PvP trinket", 16, -54, controlW,
        function() return ReadBool(unit, "showTrinket", true) end,
        function(value)
            SetBool(unit, "showTrinket", value, APPLY_REASON, opts)
            RefreshGate()
        end,
        SettingMeta(ctx, CONTROL_PATH .. "show", unit, "showTrinket"))
    M.AddTooltip(shown, "Show PvP trinket",
        "Shows each opponent's PvP trinket and its cooldown next to the arena frame. The arena frame preview of this page and Edit Mode shows it too.",
        { hook = true, owner = "ANCHOR_RIGHT" })
    local size = NumberRow(iconCard, "Size", "trinketSize", limits.sizeMin, limits.sizeMax, defaults.size, -96, "size")
    local layer = NumberRow(iconCard, "Layer", "trinketLayer", 0, 30, defaults.layer, -150, "layer")

    local side = M.BindDropdownAt(ctx, placeCard, "Anchor", 16, -54, SIDE_CHOICES, controlW,
        function() return GetConf(unit).trinketAnchor or defaults.anchor end,
        function(value) SetString(unit, "trinketAnchor", value, APPLY_REASON, opts) end,
        SettingMeta(ctx, CONTROL_PATH .. "anchor", unit, "trinketAnchor"))
    local offsetX = NumberRow(placeCard, "X offset", "trinketOffsetX", -limits.offset, limits.offset, defaults.x, -108, "offset_x")
    local offsetY = NumberRow(placeCard, "Y offset", "trinketOffsetY", -limits.offset, limits.offset, defaults.y, -162, "offset_y")

    RefreshGate(M.BindGateGroup(ctx, function() return GetConf(unit) end, {
        { on = function(conf) return conf.showTrinket ~= false end, controls = { size, layer, side, offsetX, offsetY } },
    }))
end

-- After Portrait, Power Bar and Castbar (orders 10-30), before Status.
UP.RegisterSection({
    id = SECTION_ID,
    title = "PvP Trinket",
    height = SECTION_HEIGHT,
    placement = "after_inline_text",
    order = 40,
    units = { arena = true },
    build = BuildArenaTrinket,
})

--- The arena unit preview's trinket: the mock icon follows the runtime layout,
--- scaled with the mock, and a static half swipe stands in for the cooldown.
local TrinketPreview = {}
M.ArenaTrinketPreview = TrinketPreview

--- Grows the preview footprint (frame units) by the trinket rectangle, so the
--- fit zoom keeps an icon placed far from the frame on the canvas.
function TrinketPreview.Footprint(minX, maxX, minY, maxY, frameW, frameH, expandAnchoredRect)
    local runtime = MSUF.ArenaTrinkets
    if not runtime.Shown() then return minX, maxX, minY, maxY end
    local iconSize, point, relativePoint, x, y = runtime.Layout()
    return expandAnchoredRect(minX, maxX, minY, maxY, point, relativePoint, x, y, iconSize, iconSize, frameW, frameH)
end

local function EnsurePreviewIcon(mock)
    local icon = mock._msufArenaTrinketPreview
    if icon then return icon end
    icon = PixelLayoutRegion(CreateFrame("Frame", nil, mock))
    icon.art = PixelLayoutRegion(icon:CreateTexture(nil, "ARTWORK"))
    icon.art:SetAllPoints(icon)
    icon.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.art:SetTexture(MSUF.ArenaTrinkets.FallbackTexture)
    icon.dim = PixelLayoutRegion(icon:CreateTexture(nil, "OVERLAY"))
    icon.dim:SetColorTexture(0, 0, 0, 0.6)
    icon.dim:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
    icon.dim:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    mock._msufArenaTrinketPreview = icon
    return icon
end

--- Paints the icon on the arena mock. Returns whether the trinket exists on
--- this preview (the arena page with the switch on), so the Status layer stays
--- offered while its layer toggle hides the icon.
function TrinketPreview.Paint(mock, key, wanted, scale)
    local runtime = MSUF.ArenaTrinkets
    local available = key == "arena" and runtime.Shown()
    local icon = mock._msufArenaTrinketPreview
    if not (available and wanted) then
        if icon then icon:Hide() end
        return available
    end
    icon = icon or EnsurePreviewIcon(mock)
    local iconSize, point, relativePoint, x, y, layer = runtime.Layout()
    local side = math.max(1, scale(iconSize))
    icon:SetSize(side, side)
    icon:ClearAllPoints()
    icon:SetPoint(point, mock, relativePoint, scale(x), scale(y))
    icon:SetFrameLevel(MSUF.UF.Layers.ElementLevel(layer, runtime.DEFAULTS.layer, 0))
    icon.dim:SetWidth(math.max(1, floor(side * SAMPLE_SWIPE_SHARE + 0.5)))
    icon:Show()
    return true
end
