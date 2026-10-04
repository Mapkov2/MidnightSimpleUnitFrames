-- Embedded samples use the gameplay painter without native timers or DB writes.
local _, MSUF = ...
if not (MSUF.Client and MSUF.Client.IsForever) then return end
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Shell/Menu2/Pages/MSUF_Menu2_SwingTimersPreview.lua")
local M, Swing = MSUF.MSUF2, MSUF.SwingTimer
local W, AP = M.Widgets, M.AdvancedPage
local Preview = {}
M.SwingTimerPreview = Preview
local HANDS = { "main", "off", "ranged" }

function Preview.Build(ctx, builder)
    local ui
    local section = W.FixedPreviewSection(ctx, builder, {
        title = "Preview", height = 180,
        onActivate = function() if ui then ui.Paint() end end,
    })
    local width = builder.width or ctx.width or 700
    local canvas = PixelLayoutRegion(CreateFrame("Frame", nil, section))
    canvas:SetPoint("TOPLEFT", section, "TOPLEFT", 16, -90)
    canvas:SetPoint("TOPRIGHT", section, "TOPRIGHT", -16, -90)
    canvas:SetHeight(70)
    canvas:SetClipsChildren(true)
    ui = { section = section, canvas = canvas, samples = {}, sections = {}, selected = "main" }
    for i = 1, #HANDS do
        local hand = HANDS[i]
        local sample = Swing.CreateMenuPreview(canvas, hand)
        sample:EnableMouse(true)
        sample:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" and ui.sections[hand] then
                W.FocusCollapsibleSection(ui.sections[hand], { flash = true })
            end
        end)
        ui.samples[hand] = sample
    end
    function ui.Paint()
        if not section:IsVisible() then return end
        Swing.PaintMenuPreview(ui.samples)
        for i = 1, #HANDS do
            local hand = HANDS[i]
            ui.samples[hand]:SetShown(hand == ui.selected)
        end
        local frame = ui.samples[ui.selected]
        local cfg = frame.config
        -- Fit the bar and offset timer text together; screen offsets belong
        -- to gameplay positioning, never to the embedded reference canvas.
        local left, right, bottom, top = -cfg.width / 2, cfg.width / 2, -cfg.height / 2, cfg.height / 2
        if frame.Title:IsShown() then
            bottom, top = math.min(bottom, -cfg.fontSize), math.max(top, cfg.fontSize)
        end
        if frame.Time:IsShown() then
            local align = cfg.textAlign
            if align == "AUTO" then align = cfg.display == "text" and "CENTER" or "RIGHT" end
            local textWidth = frame.Time:GetStringWidth()
            local padding = cfg.display == "bar" and (align == "LEFT" and 5 or align == "RIGHT" and -5 or 0) or 0
            local anchor = align == "LEFT" and left or align == "RIGHT" and right - textWidth or -textWidth / 2
            local textLeft = cfg.textX + padding + anchor
            left, right = math.min(left, textLeft), math.max(right, textLeft + textWidth)
            bottom, top = math.min(bottom, cfg.textY - cfg.fontSize), math.max(top, cfg.textY + cfg.fontSize)
        end
        local scale = math.min(cfg.scale / 100, (width - 48) / (right - left), 62 / (top - bottom))
        frame:SetScale(scale)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", canvas, "CENTER", -(left + right) / 2, -(bottom + top) / 2)
    end
    section:HookScript("OnShow", ui.Paint)
    M.TrackRefresh(ctx, ui.Paint)
    ctx._msuf2SwingTimerPreview = ui
    return ui
end
