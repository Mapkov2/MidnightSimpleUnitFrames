-- Real page builders and translated controls; evaluate their anchor rectangles
-- because the shared client fixture does not resolve native frame geometry.
local root = assert(arg[1], "root required")
local flavor, locale = assert(arg[2], "flavor required"), arg[3] or "enUS"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { locale = locale, open = false })
local M, W = mw.M, mw.M.Widgets
local ctx, builder, toolbar
local fixed = W.FixedPreviewSection
W.FixedPreviewSection = function(c, b, spec)
    local section, bar, record = fixed(c, b, spec)
    if c.key == "opt_castbar" then ctx, builder, toolbar = c, b, bar end
    return section, bar, record
end
assert(M.Open("opt_castbar") ~= false, "castbar page did not open")
mw:RunTimers()
assert(ctx and builder and toolbar, "real fixed preview did not build")
local function Check(value, message)
    assert(value, flavor .. "/" .. locale .. ": " .. message)
end
local function Factor(point, low, high)
    if point:find(low, 1, true) then return 0 end
    if point:find(high, 1, true) then return 1 end
    return 0.5
end
local function Rect(region, section)
    if region == section then return 0, 0, section._msuf2Width, section:GetHeight() end
    local point, relative, relativePoint, x, y = region:GetPoint(1)
    Check(point and relative, "unanchored preview control")
    local rx, ry, rw, rh = Rect(relative, section)
    local width, height = region:GetWidth() or 0, region:GetHeight() or 0
    if region == toolbar then width = section._msuf2Width end
    return rx + rw * Factor(relativePoint, "LEFT", "RIGHT") + x - width * Factor(point, "LEFT", "RIGHT"),
        ry + rh * Factor(relativePoint, "TOP", "BOTTOM") - y - height * Factor(point, "TOP", "BOTTOM"), width, height
end
local function Interrupt()
    for _, frame in ipairs(mw.world.widgets.frames) do
        if (frame:GetParent() == toolbar or frame:GetParent() == toolbar:GetParent()) and frame._msuf2Label
            and frame._msuf2Label:GetText() == M.Tr("Interrupt") then return frame end
    end
    error("interrupt control missing")
end
local function Verify(preview, section, width)
    local interrupt = Interrupt()
    local controls = { interrupt }
    for _, group in ipairs({ preview.unitButtons, preview.typeButtons }) do
        for _, button in pairs(group) do controls[#controls + 1] = button end
    end
    local canvas = preview.castRow:GetParent()
    local bx, by, bw, bh = Rect(canvas, section)
    Check(bx >= 12 and bx + bw <= width - 12, "preview canvas escapes section margins")
    Check(by + bh <= section:GetHeight() - 12, "preview canvas clips below fixed section")
    local _, dividerY = Rect(toolbar.divider, section)
    for i, button in ipairs(controls) do
        local x, y, w, h = Rect(button, section)
        Check(x >= 12 and x + w <= width - 12, "control escapes section at width " .. width)
        Check(y >= 3 and y + h < by, "control overlaps preview canvas")
        Check(y + h < dividerY or y > dividerY + 2, "toolbar divider cuts through a button")
        Check(button._msuf2AllowCombatClick and button._msuf2SkipHistoryCheckpoint,
            "preview control lost ephemeral interaction flags")
        Check(w >= M.Theme.MeasureButtonWidth(button, 0), "translated label is clipped")
        for j = 1, i - 1 do
            local ox, oy, ow, oh = Rect(controls[j], section)
            Check(x + w <= ox or ox + ow <= x or y + h <= oy or oy + oh <= y,
                "preview controls overlap at width " .. width)
        end
    end
    preview.unitButtons.target:Click()
    Check(M._msuf2CastbarPreviewUnit == "target", "unit selection broke")
    preview.typeButtons.channel:Click()
    Check(M._msuf2CastbarPreviewType == "channel", "cast type selection broke")
    interrupt:Click()
    Check(preview.interruptUntil > 0, "interrupt preview broke")
end
local fields = mw.core.ProfileFields
local before = fields.CopySnapshot(mw.env.MSUF_DB)
local original, originalToolbar = M._msuf2CastbarPreview, toolbar
local originalWidth, originalY, originalCtxWidth = builder.width, builder.y, ctx.width
local originalSection = toolbar:GetParent()
Verify(original, originalSection, originalSection._msuf2Width)
for _, width in ipairs({ 600, 648, 694, 720, 800, 1000, 1200 }) do
    builder.width, ctx.width = width, width
    local preview, section, record = M.GlobalPage.BuildCastbarPagePreview(ctx, builder)
    Verify(preview, section, width)
    if record then record:Dispose() end
end
builder.width, builder.y, ctx.width = originalWidth, originalY, originalCtxWidth
toolbar, M._msuf2CastbarPreview = originalToolbar, original
mw:Select("home")
mw:Select("opt_castbar")
Verify(original, originalSection, originalSection._msuf2Width)
Check(fields.Equal(before, mw.env.MSUF_DB), "preview interactions changed profile settings")
print("castbar_preview_toolbar_layout_smoke: ok " .. flavor .. "/" .. locale .. " (8 layouts, selection and interrupt)")
