-- Additional timers live alongside the shared castbar controls.
local _, MSUF = ...
local M, Bars = MSUF.MSUF2, MSUF.TimerBars
local Schema = M.ControlSchema
local Preview = {}
M.TimerBarPreview = Preview
function Preview.Build(preview, toolbar, makeButtons)
    local values = {}
    for _, id in ipairs(Bars.Order) do
        if Bars.IsAvailable(id) then values[#values + 1] = { key = id, text = Bars.Labels[id] } end
    end
    preview.timerKind = "breath"
    preview.timerButtons, preview.timerHolder = makeButtons(toolbar, values, 70, 4, function(id)
        preview.timerKind = id
        preview.progress = 0
        preview:Refresh()
    end, "preview.timer")
    preview.timerHolder:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 16, -10)
    preview.timerHolder:Hide()
end
local function SetTimerMode(preview, active)
    preview.timerHolder:SetShown(active)
    preview.typeHolder:SetShown(not active)
    preview.interruptButton:SetShown(not active)
    preview.box:ClearAllPoints()
    preview.box:SetPoint("TOPLEFT", preview.section, "TOPLEFT", 14, (active or preview.compactControls) and -82 or -52)
end
function Preview.Refresh(preview)
    local active = preview.layoutUnit == "timers"
    SetTimerMode(preview, active)
    if not active then
        if preview.timerSample then preview.timerSample.frame:Hide() end
        return false
    end
    if preview.scene then preview.scene:Hide() end
    local id = preview.timerKind
    local sample = preview.timerSample
    if not sample then sample = Bars.CreateMenuPreview(preview.castRow, id) preview.timerSample = sample end
    Bars.RefreshMenuPreview(sample, id)
    sample.frame:SetScale(math.min(1, (preview.castRow:GetWidth() - 8) / math.max(1, sample.frame:GetWidth()),
        (preview.castRow:GetHeight() - 8) / math.max(1, sample.frame:GetHeight())))
    for key, button in pairs(preview.timerButtons) do button:SetActive(key == id) end
    for key, button in pairs(preview.unitButtons) do button:SetActive(key == "timers") end
    Preview.Animate(preview)
    return true
end
function Preview.Animate(preview)
    local sample = preview.timerSample
    if not sample then return end
    sample.value = sample.maximum * math.max(0, 1 - (preview.progress or 0))
    Bars.Paint(sample, GetTime(), false)
end
local function Refresh()
    local entry = M.cache and M.cache.opt_castbar
    if entry then M.Refresh(entry.ctx) end
end
local function Row(id, key, kind, args, placement)
    return { kind, key, Bars.Default(id, key), args, placement,
        meta = M.GlobalPage.CastbarControlMeta("timers." .. id .. "." .. key, "setting", {
            settingKey = "general.castbarTimers." .. id .. "." .. key,
        }), scope = id, domain = "castbarTimers", register = true,
        get = function() return Bars.Get(id, key) end,
        write = { call = Bars.Set, parent = true, after = Refresh },
    }
end
local function Color(section, id)
    M.Widgets.AttachContextColorShortcut(section, {
        title = "Timer bar color", historySource = "menu:timer-color:" .. id, maxTargets = 1,
        getTargets = function()
            return { { label = "Bar color", getRGB = function()
                return Bars.Get(id, "r"), Bars.Get(id, "g"), Bars.Get(id, "b")
            end, setRGB = function(r, g, b) Bars.SetColor(id, r, g, b) Refresh() end } }
        end,
    })
end
local function BuildTimer(ctx, builder, id)
    local section = builder:CollapsibleSection("timer_" .. id, Bars.Labels[id], 340, false)
    Schema.Section(section, ctx.key)
    local rows = {
        Row(id, "enabled", "sectionSwitch", { "Enable" }),
        Row(id, "hideBlizzard", "flowToggle", { "Hide Blizzard timer bar" }, { 14, -42 }),
        Row(id, "ownSize", "flowToggle", { "Use own timer bar size" }, { 14, -70 }),
        Row(id, "lowWarning", "flowToggle", { "Low timer warning" }, { 392, -42 }),
        Row(id, "warningPercent", "slider", { "Warning threshold (%)", 1, 100, 1, 300 }, { 392, -80, 300 }),
        Row(id, "width", "slider", { "Width", 40, 1200, 1, 300 }, { 14, -118, 300 }),
        Row(id, "height", "slider", { "Height", 4, 100, 1, 300 }, { 392, -140, 300 }),
        Row(id, "x", "slider", { "X offset", -2000, 2000, 1, 300 }, { 14, -182, 300 }),
        Row(id, "y", "slider", { "Y offset", -1200, 1200, 1, 300 }, { 392, -204, 300 }),
    }
    if Bars.States[id].numbersAt then
        rows[#rows + 1] = Row(id, "showUnderNumbers", "flowToggle", { "Keep bar during countdown numbers" }, { 14, -254 })
    end
    local options = Schema.UnitOptions()
    options.register = function(_, widget, row)
        M.RegisterControlMetadata(widget, row.meta, row[4][1], widget._msuf2ControlSchema.kind)
    end
    local controls = Schema.Build(ctx, section, rows, options)
    M.TrackRefresh(ctx, function()
        M.Widgets.SetControlEnabled(controls.width, Bars.Get(id, "ownSize"))
        M.Widgets.SetControlEnabled(controls.height, Bars.Get(id, "ownSize"))
        M.Widgets.SetControlEnabled(controls.warningPercent, Bars.Get(id, "lowWarning"))
    end)
    Color(section, id)
end
function M.BuildTimerBarSections(ctx, builder)
    local intro = builder:CollapsibleSection("timer_bars", "Other timer bars", 108, false)
    Schema.Section(intro, ctx.key)
    local description = M.Widgets.Text(intro,
        "Timer bars follow the Player castbar style. Enable Preview or Edit Mode to drag them.",
        14, -40, (ctx.width or 720) - 28, M.Theme.colors.muted)
    Schema.Build(ctx, intro, {
        { "flowToggle", "preview", false, { "Preview timer bars" }, { 14, -76 },
            meta = M.GlobalPage.CastbarControlMeta("timers.preview", "ephemeral"),
            domain = "castbarTimers", get = Bars.IsPreview,
            set = function(value) Bars.SetPreview(value) end },
    }, Schema.UnitOptions())
    intro:HookScript("OnHide", function() Bars.SetPreview(false) end)
    for _, id in ipairs(Bars.Order) do
        if Bars.IsAvailable(id) then BuildTimer(ctx, builder, id) end
    end
end
