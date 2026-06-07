local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets or {}
local UP = M.UnitPage or {}

local max = math.max

local AlphaLabel = M.AlphaLabel

-- Unified, simple transparency: one slider for the HP bar fill, one for the bar
-- background, and one toggle that keeps the frame texts + portrait fully opaque while
-- the bars dim. Range fade multiplies these at runtime. All coldpath.
local function BuildAlpha(ctx, builder, unit)
    local ReadBool = UP.ReadBool
    local SetBool = UP.SetBool
    local ReadNumber = UP.ReadNumber
    local SetNumber = UP.SetNumber
    if not (ReadBool and SetBool and ReadNumber and SetNumber) then return end

    local sec = builder:CollapsibleSection("transparency", "Transparency", 188, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local gap = 16
    local leftX = 20
    local innerW = max(320, sectionW - 40)
    local leftW = math.floor((innerW - gap) * 0.5)
    local rightX = leftX + leftW + gap
    local rightW = innerW - leftW - gap

    local barsCard = W.ControlCard(sec, "Opacity", "Fade the health bar and its background.", leftX, -38, leftW, 130)
    local optionsCard = W.ControlCard(sec, "Options", "Keep text and portrait readable while bars fade.", rightX, -38, rightW, 130)

    -- HP bar fill opacity.
    local hpAlpha = W.Slider(barsCard, "", 0, 1, 0.05, leftW)
    M.BindSlider(ctx, hpAlpha,
        function() return ReadNumber(unit, "hpBarAlpha", 1) end,
        function(v) SetNumber(unit, "hpBarAlpha", v, "MSUF2_ALPHA_HP", { alpha = true, preview = true }) end)
    M.BindSliderLiveLabel(ctx, hpAlpha, function() return ReadNumber(unit, "hpBarAlpha", 1) end,
        function(value) return AlphaLabel("HP Bar", value) end, true)
    W.MoveWidget(hpAlpha, barsCard, 16, -62, leftW - 58, "LEFT")

    -- Background texture opacity. Background opacity lives in the bar background colour,
    -- so a normal visual reapply (preview) repaints it -- no alpha refresh needed.
    local bgAlpha = W.Slider(barsCard, "", 0, 1, 0.05, leftW)
    M.BindSlider(ctx, bgAlpha,
        function() return ReadNumber(unit, "hpBgAlpha", 0.85) end,
        function(v) SetNumber(unit, "hpBgAlpha", v, "MSUF2_ALPHA_BG", { preview = true }) end)
    M.BindSliderLiveLabel(ctx, bgAlpha, function() return ReadNumber(unit, "hpBgAlpha", 0.85) end,
        function(value) return AlphaLabel("Background", value) end, true)
    W.MoveWidget(bgAlpha, barsCard, 16, -100, leftW - 58, "LEFT")

    local exclude = W.ToggleAt(optionsCard, "Keep text + portrait visible", 16, -62, rightW - 32)
    M.BindToggle(ctx, exclude,
        function() return ReadBool(unit, "alphaExcludeTextPortrait", false) end,
        function(v)
            SetBool(unit, "alphaExcludeTextPortrait", v, "MSUF2_ALPHA_EXCLUDE", { alpha = true, preview = true })
        end)

    local hint = W.Text(optionsCard, "", 16, -94, rightW - 32, nil)
    if hint and hint.SetWordWrap then hint:SetWordWrap(true) end
    if hint and hint.SetText then
        hint:SetText(M.Tr("On: only the HP bar and background fade. Off: text and portrait fade with them."))
    end
end

if type(UP.RegisterSection) == "function" then
    UP.RegisterSection({
        id = "transparency",
        placement = "after_load_conditions",
        order = 20,
        build = BuildAlpha,
    })
end
