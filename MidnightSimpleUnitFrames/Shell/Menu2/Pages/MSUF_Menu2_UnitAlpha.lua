local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
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
    local function AddAlphaSlider(spec)
        local slider = W.Slider(barsCard, "", 0, 1, 0.05, leftW)
        M.BindNumberWidget(ctx, slider,
            function() return ReadNumber(unit, spec.key, spec.default) end,
            function(v) SetNumber(unit, spec.key, v, spec.reason, spec.flags) end,
            spec.default)
        M.BindSliderLiveLabel(ctx, slider, function() return ReadNumber(unit, spec.key, spec.default) end,
            function(value) return AlphaLabel(spec.label, value) end, true)
        W.MoveWidget(slider, barsCard, 16, spec.y, leftW - 58, "LEFT")
    end
    AddAlphaSlider({ label = "HP Bar", key = "hpBarAlpha", default = 1, reason = "MSUF2_ALPHA_HP", flags = { alpha = true, preview = true }, y = -62 })
    AddAlphaSlider({ label = "Background", key = "hpBgAlpha", default = 0.85, reason = "MSUF2_ALPHA_BG", flags = { preview = true }, y = -100 })
    local exclude = W.ToggleAt(optionsCard, "Keep text + portrait visible", 16, -62, rightW - 32)
    M.BindBoolWidget(ctx, exclude,
        function() return ReadBool(unit, "alphaExcludeTextPortrait", false) end,
        function(v)
            SetBool(unit, "alphaExcludeTextPortrait", v, "MSUF2_ALPHA_EXCLUDE", { alpha = true, preview = true })
        end)
    local hint = W.Text(optionsCard, "", 16, -94, rightW - 32, nil)
    if hint and hint.SetWordWrap then hint:SetWordWrap(true) end
    if hint and hint.SetText then hint:SetText(M.Tr("On: only the HP bar and background fade. Off: text and portrait fade with them.")) end
end
if type(UP.RegisterSection) == "function" then
    UP.RegisterSection({
        id = "transparency",
        title = "Transparency",
        height = 188,
        placement = "after_load_conditions",
        order = 20,
        build = BuildAlpha,
    })
end
