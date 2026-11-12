-- Timer surfaces share the player castbar's painter, fonts, textures and border.
-- A timer may name its own bar and background texture and its own text settings
-- (label and time position, size and offsets, time font and format); an empty
-- choice follows the castbar.
local _, MSUF = ...
local Bars, Castbars = MSUF.TimerBars, MSUF.Castbars
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Castbars/MSUF_TimerBarVisuals.lua")
local ResolveTexture = Castbars.Core.ResolveStatusbarTextureKey
local function ApplyOwnTextures(state, frame)
    local texture, background = state.texture, state.backgroundTexture
    if texture and texture ~= "" then
        frame.statusBar:SetStatusBarTexture(ResolveTexture(texture))
        -- Keep the fill stretched, as the castbar media swap does.
        local fill = frame.statusBar:GetStatusBarTexture()
        if fill then fill:SetHorizTile(false) end
    end
    if background and background ~= "" then frame.backgroundBar:SetTexture(ResolveTexture(background)) end
end
-- The castbar painter lays its texts out from the Player castbar's profile keys.
-- A timer's own text choices answer for those keys in a view of the profile;
-- every other key, and every choice left empty, reads the profile itself.
local function TextSource(state, general)
    local view = state.textSource
    if not view then
        view = setmetatable({}, { __index = general })
        state.textSource = view
    end
    getmetatable(view).__index = general
    local ownLabel, ownTime = state.labelPosition ~= "", state.timePosition ~= ""
    view.castbarPlayerSpellNamePosition = ownLabel and state.labelPosition or nil
    view.castbarPlayerTextOffsetX = ownLabel and state.labelX or nil
    view.castbarPlayerTextOffsetY = ownLabel and state.labelY or nil
    view.castbarPlayerSpellNameFontSize = state.labelSize > 0 and state.labelSize or nil
    view.castbarPlayerTimePosition = ownTime and state.timePosition or nil
    -- Own time offsets sit on the castbar's 2 px edge padding, like boss and arena.
    view.castbarPlayerTimeOffsetX = ownTime and state.timeX - 2 or nil
    view.castbarPlayerTimeOffsetY = ownTime and state.timeY or nil
    view.castbarPlayerTimeFontSize = state.timeSize > 0 and state.timeSize or nil
    view.castbarPlayerTimeFont = state.timeFont ~= "" and state.timeFont or nil
    -- The painter reserves the time text's room by format.
    view.castbarPlayerTimeFormat = state.timeFormat
    return view
end
local function Clock(seconds)
    if seconds >= 60 then return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60) end
    return string.format("%d", seconds)
end
-- Whole seconds like the default Remaining text; built once per shown second.
local function TimeText(format, remaining, total)
    if format == "CURRENT_MAX" then return Clock(remaining) .. " / " .. Clock(total) end
    local elapsed = math.max(0, total - remaining)
    if format == "ELAPSED_MAX" then return Clock(elapsed) .. " / " .. Clock(total) end
    return Clock(elapsed)
end
local function DragStart(frame)
    if not Bars.IsPreview() or MSUF.Util.InCombat() then return end
    frame:StartMoving()
end
local function DragStop(frame)
    frame:StopMovingOrSizing()
    if not Bars.IsPreview() or MSUF.Util.InCombat() then return end
    local x, y = frame:GetCenter()
    local cx, cy = UIParent:GetCenter()
    if Bars.IsPublicNumber(x) and Bars.IsPublicNumber(y) and Bars.IsPublicNumber(cx) and Bars.IsPublicNumber(cy) then
        Bars.SavePosition(frame.timerID, x - cx, y - cy)
    end
end
function Bars.Create(state, parent)
    local frame = Castbars.Frames.CreateCastbarPreviewFrame("player", nil, {
        parent = parent, showIcon = false, label = Bars.Labels[state.id], strata = "MEDIUM",
    })
    frame.backgroundBar:SetAlpha(1)
    frame.timerID = state.id
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", DragStart)
    frame:SetScript("OnDragStop", DragStop)
    PixelLayoutRegion(frame)
    return frame
end
function Bars.ApplyStyle(state)
    local frame = state.frame
    local source = Castbars.Config.Source(false)
    local general = source and source.general or {}
    local width, height = Castbars.Anchors.GetCastbarDesiredSize("player", general, frame, 250, 18)
    if state.ownSize then width, height = state.width, state.height end
    frame:SetSize(width, height)
    frame:ClearAllPoints()
    if state.previewOnly then frame:SetPoint("CENTER", frame:GetParent(), "CENTER", 0, 0)
    else frame:SetPoint("CENTER", UIParent, "CENTER", state.x, state.y) end
    frame:EnableMouse(not state.previewOnly and Bars.IsPreview())
    Castbars.Visuals.RefreshCastbarFrame(frame, "player", TextSource(state, general))
    ApplyOwnTextures(state, frame)
    Castbars.Core.ApplyCastbarFrameLayer(frame, general, "player")
    if state.previewOnly then
        local owner = frame:GetParent()
        frame:SetFrameStrata(owner:GetFrameStrata())
        frame:SetFrameLevel(owner:GetFrameLevel() + 1)
    end
    frame.statusBar:SetMinMaxValues(0, 1)
    frame.statusBar:SetReverseFill(Castbars.Utils.GetReverseFillSafe(frame, true) == true)
    Castbars.Core.ApplyCastbarSparkVisual(frame, general)
    state.lastSecond, state.lastLabel = nil, nil
end
function Bars.CreateMenuPreview(parent, id)
    local state = { previewOnly = true, id = id }
    state.frame = Bars.Create(state, parent)
    return state
end
function Bars.RefreshMenuPreview(state, id)
    Bars.CopySettings(state, id)
    state.frame.timerID = id
    state.active, state.rising, state.paused = true, false, false
    state.maximum = (id == "feign" and 360 or 120) * 1000
    state.value = state.maximum * 0.65
    state.label = MSUF.Translate(Bars.Labels[id])
    Bars.ApplyStyle(state)
    state.frame:Show()
end
function Bars.Paint(state, now, preview)
    local frame = state.frame
    local fraction = preview and 0.65 or math.max(0, math.min(1, state.value / state.maximum))
    local label = preview and MSUF.Translate(Bars.Labels[state.id]) or state.label
    if state.lastLabel ~= label then
        frame.castText:SetText(label)
        state.lastLabel = label
    end
    local seconds = math.max(0, math.ceil(preview and 65 or state.value / 1000))
    if state.lastSecond ~= seconds then
        local format = state.timeFormat
        if format and format ~= "CURRENT" then
            frame.timeText:SetText(TimeText(format, seconds, math.ceil((preview and 100000 or state.maximum) / 1000)))
        elseif seconds >= 60 then frame.timeText:SetFormattedText("%d:%02d", math.floor(seconds / 60), seconds % 60)
        else frame.timeText:SetFormattedText("%d", seconds) end
        state.lastSecond = seconds
    end
    frame.statusBar:SetValue(fraction)
    local r, g, b, alpha = state.r, state.g, state.b, 1
    if state.lowWarning and (preview or not state.rising) and fraction * 100 <= state.warningPercent then
        r, g, b = 1, 0.1, 0.1
        if not preview and not state.paused then alpha = 0.45 + 0.55 * math.abs(math.sin(now * 6)) end
    end
    frame.statusBar:SetStatusBarColor(r, g, b)
    frame:SetAlpha(alpha)
end
