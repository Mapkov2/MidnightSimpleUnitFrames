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
local UP, Schema = M.UnitPage, M.ControlSchema
local ROW_OPTIONS = Schema.UnitOptions()
local floor = math.floor

local SECTION_ID = "pvp_trinket"
-- Control identities; search shows the segment as the breadcrumb "Unit > Trinket".
local CONTROL_PATH = "trinket."
local SECTION_HEIGHT = 282
local CARD_HEIGHT = 228
local APPLY_REASON = "MSUF2_ARENA_TRINKET"
local SIDE_CHOICES = {
    { value = "RIGHT", text = "Right" },
    { value = "LEFT", text = "Left" },
    { value = "TOP", text = "Top" },
    { value = "BOTTOM", text = "Bottom" },
}

--- Section fields for Reset section (Unit page section actions); the trinket is
--- arena-only, so the section has nothing to copy to another frame.
UP.ARENA_TRINKET_FIELDS = "showTrinket trinketSize trinketAnchor trinketOffsetX trinketOffsetY trinketLayer"

local function BuildArenaTrinket(ctx, builder, unit)
    local runtime = MSUF.ArenaTrinkets
    local defaults, limits = runtime.DEFAULTS, runtime.LIMITS
    local sec = Schema.Section(builder:CollapsibleSection(SECTION_ID, "PvP Trinket", SECTION_HEIGHT, false), unit)
    local width = math.max(340, ((sec and sec._msuf2Width) or (ctx and ctx.width) or 720) - 40)
    local half = floor((width - 16) / 2)
    local cards = Schema.Build(ctx, sec, {
        { "card", "trinket.icon_card", nil, { "Icon", nil, 20, -38, half, CARD_HEIGHT }, scope = unit, domain = "layout" },
        { "card", "trinket.place_card", nil, { "Position", nil, 36 + half, -38, width - half - 16, CARD_HEIGHT },
            scope = unit, domain = "layout" },
    })
    local controlW = half - 32
    local RefreshGate = M.RefreshProxy()
    local offset = limits.offset
    local function Rows(card, rows, controls)
        for _, row in ipairs(rows) do
            local key, fallback, kind = row[2], row[3], row[1]
            row.meta = UP.SettingMeta(ctx, CONTROL_PATH .. row.path, unit, key)
            row.scope, row.domain, row.roundStep = unit, "arenaTrinket", kind == "slider"
            row.get = function()
                if kind == "toggle" then return UP.ReadBool(unit, key, fallback) end
                if kind == "slider" then return UP.ReadNumber(unit, key, fallback) end
                return UP.GetConf(unit)[key] or fallback
            end
            row.write = { unitDomain = "arenaTrinket", reason = APPLY_REASON,
                after = function() if kind == "toggle" then RefreshGate() end end } --[[schema setter: UnitArenaTrinket.1]]
            -- The original trinket number binding commits invalid text as zero.
            if kind == "slider" then row[3] = 0 end
        end
        return Schema.Build(ctx, card, rows, ROW_OPTIONS, controls)
    end
    local controls = Rows(cards["trinket.icon_card"], {
        { "toggle", "showTrinket", true, { "Show PvP trinket", 16, -54, controlW }, path = "show" },
        { "slider", "trinketSize", defaults.size, { "Size", limits.sizeMin, limits.sizeMax, 1, controlW }, { 16, -100, controlW }, path = "size" },
        { "slider", "trinketLayer", defaults.layer, { "Layer", 0, 30, 1, controlW }, { 16, -154, controlW }, path = "layer" },
    })
    Rows(cards["trinket.place_card"], {
        { "dropdown", "trinketAnchor", defaults.anchor, { "Anchor", SIDE_CHOICES, controlW }, { 16, -54, controlW }, path = "anchor" },
        { "slider", "trinketOffsetX", defaults.x, { "X offset", -offset, offset, 1, controlW }, { 16, -112, controlW }, path = "offset_x" },
        { "slider", "trinketOffsetY", defaults.y, { "Y offset", -offset, offset, 1, controlW }, { 16, -166, controlW }, path = "offset_y" },
    }, controls)
    M.AddTooltip(controls.showTrinket, "Show PvP trinket",
        "Shows each opponent's PvP trinket and its cooldown next to the arena frame. The arena frame preview of this page and Edit Mode shows it too.",
        { hook = true, owner = "ANCHOR_RIGHT" })
    RefreshGate(M.BindGateGroup(ctx, function() return UP.GetConf(unit) end, {
        { on = function(conf) return conf.showTrinket ~= false end, controls = { controls.trinketSize, controls.trinketLayer,
            controls.trinketAnchor, controls.trinketOffsetX, controls.trinketOffsetY } },
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
--- scaled with the mock, and a static dark band stands in for the cooldown swipe.
--- It is a preview element like the others: its handle selects, drags, nudges
--- and Tab-cycles through the shared unit preview machinery, the selection bar
--- edits and resets its offset, and the Trinket legend entry shows or hides it.
local TrinketPreview = {}
M.ArenaTrinketPreview = TrinketPreview
TrinketPreview.LAYER = "trinket"
local HANDLE_COLOR = { 1.00, 0.45, 0.30 }

--- The preview writes offset = stored offset + delta. Keep the result inside
--- the runtime's offset range, so the stored value always equals what the icon
--- shows and a drag past the edge never leaves a dead zone behind.
local function ClampedOffsetDelta(handle, dx, dy)
    local limits, defaults = MSUF.ArenaTrinkets.LIMITS, MSUF.ArenaTrinkets.DEFAULTS
    local conf = UP.GetConf("arena")
    local baseX = handle._dragging and tonumber(handle._startX) or tonumber(conf.trinketOffsetX) or defaults.x
    local baseY = handle._dragging and tonumber(handle._startY) or tonumber(conf.trinketOffsetY) or defaults.y
    local limit = limits.offset
    local x = math.max(-limit, math.min(limit, baseX + (tonumber(dx) or 0)))
    local y = math.max(-limit, math.min(limit, baseY + (tonumber(dy) or 0)))
    return x - baseX, y - baseY
end

--- The unit preview builds this handle with its own MakeHandle (View), so the
--- trinket shares selection, drag, nudge, history, the selection bar and the
--- element list with every other preview element. Clients without arena
--- frames build none.
function TrinketPreview.CreateHandle(box, makeHandle)
    if not (M.SupportsFrameScope and M.SupportsFrameScope("arena")) then return nil end
    local defaults = MSUF.ArenaTrinkets.DEFAULTS
    box.handleArenaTrinket = makeHandle(box, "arenaTrinket", {
        x = "trinketOffsetX", y = "trinketOffsetY", defaultX = defaults.x, defaultY = defaults.y,
        section = SECTION_ID, previewLayer = TrinketPreview.LAYER, resolveOffsetDelta = ClampedOffsetDelta,
    }, "PvP Trinket", HANDLE_COLOR)
    Schema.Custom(box.handleArenaTrinket, { id = "unit.preview.arenaTrinket", kind = "unitPreviewHandle",
        scope = "arena", applyDomain = "preview", owner = box.handleArenaTrinket })
    return box.handleArenaTrinket
end

--- Grows the preview footprint (frame units) by the trinket rectangle, so the
--- fit zoom keeps an icon placed far from the frame on the canvas.
function TrinketPreview.Footprint(minX, maxX, minY, maxY, frameW, frameH, expandAnchoredRect)
    local runtime = MSUF.ArenaTrinkets
    if not runtime.Shown() then return minX, maxX, minY, maxY end
    local iconSize, point, relativePoint, x, y = runtime.Layout()
    return expandAnchoredRect(minX, maxX, minY, maxY, point, relativePoint, x, y, iconSize, iconSize, frameW, frameH)
end



function TrinketPreview.Paint(mock, key, wanted, scale, rawScale)
    local runtime = MSUF.ArenaTrinkets
    local available = key == "arena" and runtime.Shown()
    local icon = mock._msufArenaTrinketPreview
    if not (available and wanted) then
        if icon then icon.cooldown:Clear() icon:Hide() end
        return available, nil
    end
    if not icon then
        icon = runtime.CreateSurface(mock)
        mock._msufArenaTrinketPreview = icon
    end
    runtime.PaintSurface(icon, mock)
    -- Native scaling preserves the runtime geometry, masks and cooldown swipe.
    icon:SetScale(rawScale or 1)
    icon.cooldown:SetCooldown(GetTime() - 48, 120)
    icon:Show()
    return true, icon
end
