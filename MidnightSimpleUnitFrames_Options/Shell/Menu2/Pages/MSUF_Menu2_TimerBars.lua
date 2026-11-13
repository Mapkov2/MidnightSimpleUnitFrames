-- Additional timers live in one section of the Castbar page. Each timer has a
-- tab; the tabs and the preview chooser share one selection.
local _, MSUF = ...
local M, Bars = MSUF.MSUF2, MSUF.TimerBars
local Schema = M.ControlSchema
local Preview = {}
M.TimerBarPreview = Preview
local page
local function Selected()
    local id = M.castbarTimerSelection
    if id and Bars.IsAvailable(id) then return id end
    for _, candidate in ipairs(Bars.Order) do
        if Bars.IsAvailable(candidate) then return candidate end
    end
    return Bars.Order[1]
end
local function SetSelection(id)
    M.castbarTimerSelection = id
    local preview = M._msuf2CastbarPreview
    if preview and preview.timerKind ~= id then
        preview.timerKind, preview.progress = id, 0
        if preview.layoutUnit == "timers" then preview:Refresh() end
    end
end
local function Select(id)
    if not Bars.IsAvailable(id) then return false end
    SetSelection(id)
    if page then page.refreshTabs() end
    return true
end
Preview.Select = Select
function Preview.Build(preview, toolbar, makeButtons)
    local values = {}
    for _, id in ipairs(Bars.Order) do
        if Bars.IsAvailable(id) then values[#values + 1] = { key = id, text = Bars.Labels[id] } end
    end
    preview.timerKind = Selected()
    preview.timerButtons, preview.timerHolder = makeButtons(toolbar, values, 70, 4, function(id)
        preview.timerKind, preview.progress = id, 0
        Select(id)
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
-- A click on a timer tab shows that timer: the menu preview switches to it and
-- the enabled bars appear at their saved screen positions, ready to drag.
local function ShowSelection()
    M.SetCastbarPreviewUnit("timers")
    Bars.SetPreview(true)
    Refresh()
end
local function Meta(path, classification, exact)
    return M.GlobalPage.CastbarControlMeta(path, classification, exact)
end
local function Row(id, key, kind, args, placement)
    return { kind, key, Bars.Default(id, key), args, placement,
        meta = Meta("timers." .. id .. "." .. key, "setting", { settingKey = "general.castbarTimers." .. id .. "." .. key }),
        scope = id, domain = "castbarTimers", register = true,
        get = function() return Bars.Get(id, key) end,
        write = { call = Bars.Set, parent = true, after = Refresh },
    }
end
local function TextureRow(id, key, label, follow, x)
    return Row(id, key, "dropdown", { label, function() return M.StatusBarTextureItems(follow) end, 300 }, { x, -292, 300 })
end
-- Text settings mirror the castbar's Spell Text and Time Text controls. An empty
-- position follows the Player castbar; its offsets apply once a timer has its own.
local TEXT_POSITIONS = M.ValueTextList("", "Use castbar position", "LEFT", "Left", "CENTER", "Center", "RIGHT", "Right",
    "ABOVE", "Above", "BELOW", "Below")
local TIME_FORMATS = M.ValueTextList("CURRENT", "Remaining", "ELAPSED", "Elapsed", "ELAPSED_MAX", "Elapsed / Total",
    "CURRENT_MAX", "Remaining / Total")
-- The Fonts page list behind an entry that keeps following the castbar font.
local function TimeFontItems()
    local items = M.GlobalPage.FontValues(false)
    table.insert(items, 1, { value = "", text = "Use castbar font" })
    return items
end
local function Color(ctx, frame, id)
    Schema.ContextColors(frame, Meta("timers." .. id .. ".colors", "ephemeral").controlId, ctx.key)
    M.Widgets.AttachContextColorShortcut(frame, {
        title = "Timer bar color", historySource = "menu:timer-color:" .. id, maxTargets = 1,
        getTargets = function()
            return { { label = "Bar color", getRGB = function()
                return Bars.Get(id, "r"), Bars.Get(id, "g"), Bars.Get(id, "b")
            end, setRGB = function(r, g, b) Bars.SetColor(id, r, g, b) Refresh() end } }
        end,
    })
end
local function BuildTimer(ctx, frame, id)
    local rows = {
        Row(id, "enabled", "switch", { "Enable", 14, -10, 300 }),
        Row(id, "hideBlizzard", "flowToggle", { "Hide Blizzard timer bar" }, { 14, -42 }),
        Row(id, "ownSize", "flowToggle", { "Use own timer bar size" }, { 14, -70 }),
        Row(id, "lowWarning", "flowToggle", { "Low timer warning" }, { 392, -42 }),
        Row(id, "warningPercent", "slider", { "Warning threshold (%)", 1, 100, 1, 300 }, { 392, -80, 300 }),
        Row(id, "width", "slider", { "Width", 40, 1200, 1, 300 }, { 14, -118, 300 }),
        Row(id, "height", "slider", { "Height", 4, 100, 1, 300 }, { 392, -140, 300 }),
        Row(id, "x", "slider", { "X offset", -2000, 2000, 1, 300 }, { 14, -182, 300 }),
        Row(id, "y", "slider", { "Y offset", -1200, 1200, 1, 300 }, { 392, -204, 300 }),
        TextureRow(id, "texture", "Timer bar texture", "Use castbar texture", 14),
        TextureRow(id, "backgroundTexture", "Timer background texture", "Use castbar background texture", 392),
        Row(id, "timeFont", "dropdown", { "Timer time text font", TimeFontItems, 300 }, { 14, -346, 300 }),
        Row(id, "timeFormat", "dropdown", { "Timer time format", TIME_FORMATS, 300 }, { 392, -346, 300 }),
        Row(id, "labelPosition", "dropdown", { "Timer label position", TEXT_POSITIONS, 300 }, { 14, -400, 300 }),
        Row(id, "timePosition", "dropdown", { "Timer time position", TEXT_POSITIONS, 300 }, { 392, -400, 300 }),
        Row(id, "labelSize", "slider", { "Timer label size", 0, 48, 1, 300 }, { 14, -464, 300 }),
        Row(id, "timeSize", "slider", { "Timer time size", 0, 48, 1, 300 }, { 392, -464, 300 }),
        Row(id, "labelX", "slider", { "Timer label X offset", -300, 300, 1, 300 }, { 14, -528, 300 }),
        Row(id, "timeX", "slider", { "Timer time X offset", -300, 300, 1, 300 }, { 392, -528, 300 }),
        Row(id, "labelY", "slider", { "Timer label Y offset", -300, 300, 1, 300 }, { 14, -592, 300 }),
        Row(id, "timeY", "slider", { "Timer time Y offset", -300, 300, 1, 300 }, { 392, -592, 300 }),
    }
    if Bars.States[id].numbersAt then
        rows[#rows + 1] = Row(id, "showUnderNumbers", "flowToggle", { "Keep bar during countdown numbers" }, { 14, -254 })
    end
    local options = Schema.UnitOptions()
    options.register = function(_, widget, row)
        M.RegisterControlMetadata(widget, row.meta, row[4][1], widget._msuf2ControlSchema.kind)
    end
    local controls = Schema.Build(ctx, frame, rows, options)
    M.TrackRefresh(ctx, function()
        M.Widgets.SetControlEnabled(controls.width, Bars.Get(id, "ownSize"))
        M.Widgets.SetControlEnabled(controls.height, Bars.Get(id, "ownSize"))
        M.Widgets.SetControlEnabled(controls.warningPercent, Bars.Get(id, "lowWarning"))
        local ownLabel, ownTime = Bars.Get(id, "labelPosition") ~= "", Bars.Get(id, "timePosition") ~= ""
        M.Widgets.SetControlEnabled(controls.labelX, ownLabel)
        M.Widgets.SetControlEnabled(controls.labelY, ownLabel)
        M.Widgets.SetControlEnabled(controls.timeX, ownTime)
        M.Widgets.SetControlEnabled(controls.timeY, ownTime)
    end)
    Color(ctx, frame, id)
end
-- The tabs exist before any timer control: a control registered on a tab
-- inherits that tab as the view an exact search link has to show.
local function BuildTabs(ctx, section, width)
    local frames, values = {}, {}
    for _, id in ipairs(Bars.Order) do
        if Bars.IsAvailable(id) then
            values[#values + 1] = { value = id, text = Bars.Labels[id] }
            M.UnitSectionsShared.MakeTabFrame(section, id, -122, width, frames)
        end
    end
    local tabs, refreshTabs = M.Widgets.SegmentTabs(ctx, section, {
        label = "", values = values, width = math.min(660, width - 48),
        frames = frames, defaultTab = Selected(), get = Selected,
        customSetReason = "Changes editor selection or input state rather than a fixed profile field.",
        set = SetSelection, afterSet = ShowSelection, x = 14, y = -64,
    })
    if tabs._msuf2Title then tabs._msuf2Title:Hide() end
    M.RegisterControlMetadata(tabs, Meta("timers.selected", "ephemeral"), "Selected timer bar", "segment")
    Schema.Owned(tabs, ctx.key, "sectionNavigation")
    return frames, refreshTabs
end
function M.BuildTimerBarSections(ctx, builder)
    local section = builder:CollapsibleSection("timer_bars", "Other timer bars", 780, false)
    Schema.Section(section, ctx.key)
    local width = section._msuf2Width or ctx.width or 720
    M.Widgets.Text(section,
        "Timer bars follow the Player castbar style. Enable Preview or Edit Mode to drag them.",
        14, -12, width - 28, M.Theme.colors.muted)
    Schema.Build(ctx, section, {
        { "flowToggle", "preview", false, { "Preview timer bars" }, { 14, -36 },
            meta = Meta("timers.preview", "ephemeral"),
            domain = "castbarTimers", get = Bars.IsPreview, set = Bars.SetPreview,
            customSetReason = "Shows timer bars temporarily without writing a profile setting." },
    }, Schema.UnitOptions())
    section:HookScript("OnHide", function() Bars.SetPreview(false) end)
    local frames, refreshTabs = BuildTabs(ctx, section, width)
    page = { refreshTabs = refreshTabs }
    Preview.frames = frames
    for _, id in ipairs(Bars.Order) do
        if frames[id] then BuildTimer(ctx, frames[id], id) end
    end
    refreshTabs()
end
