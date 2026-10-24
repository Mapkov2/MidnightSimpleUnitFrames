-- Independent Forever Swing Timer module settings.
local _, MSUF = ...
if not MSUF.Client.IsForever then return end
local M = MSUF.MSUF2
local W, AP = M.Widgets, M.AdvancedPage
local Swing = MSUF.SwingTimer
local Schema = M.ControlSchema
local HANDS = { "main", "off", "ranged" }
local LABELS = { main = "Main Hand", off = "Off Hand", ranged = "Ranged" }
local COLORS = {
    { "color", "Bar color" }, { "backgroundColor", "Background color" },
    { "borderColor", "Border color" }, { "textColor", "Text color" },
    { "reachColor", "Out-of-reach color" }, { "nextSwingColor", "Next-swing cue color" },
}
local function Meta(path, key, classification, prepare)
    return AP.ControlMeta("swingtimers", "swing", path, classification or "setting", {
        pageKey = "swingtimers", settingKey = key, prepareExactSearchTarget = prepare,
        searchPrepareKind = prepare and "swingTimerHand" or nil, searchPrepareValue = prepare and path:match("^(%w+)%.") or nil,
    })
end
local function TextureItems(followText)
    local items = M.StatusBarTextureItems(followText)
    for i = 1, #items do
        if items[i].texture then items[i].value = items[i].texture end
    end
    return items
end
local SPECS = {
    { key = "visibility", kind = "dropdown", labelKey = "Visibility",
        values = function() return M.ValueTextList("always", "Always", "combat", "In combat") end },
    { key = "display", kind = "dropdown", labelKey = "Display mode",
        values = function() return M.ValueTextList("bar", "Bar and timer", "text", "Number only") end },
    { key = "width", kind = "slider", labelKey = "Width", range = { 40, 1200, 1 } },
    { key = "height", kind = "slider", labelKey = "Height", range = { 4, 100, 1 } },
    { key = "scale", kind = "slider", labelKey = "Scale %", range = { 50, 200, 1 } },
    { key = "opacity", kind = "slider", labelKey = "Opacity %", range = { 0, 100, 1 } },
    { key = "x", kind = "slider", labelKey = "X offset", range = { -2000, 2000, 1 } },
    { key = "y", kind = "slider", labelKey = "Y offset", range = { -1200, 1200, 1 } },
    { key = "texture", kind = "dropdown", labelKey = "Bar texture", values = function() return TextureItems() end },
    { key = "backgroundTexture", kind = "dropdown", labelKey = "Background texture", values = function() return TextureItems("Use foreground texture") end },
    { key = "backgroundOpacity", kind = "slider", labelKey = "Background opacity", range = { 0, 100, 1 } },
    { key = "borderSize", kind = "slider", labelKey = "Border thickness", range = { 0, 8, 1 } },
    { key = "fill", kind = "dropdown", labelKey = "Timer progression",
        values = function() return M.ValueTextList("elapsed", "Fill up", "remaining", "Drain") end },
    { key = "direction", kind = "dropdown", labelKey = "Fill direction", values = function() return M.ValueTextList(
            "RIGHT", "Horizontal (left -> right)", "LEFT", "Horizontal (right -> left)",
            "UP", "Vertical (bottom -> top)", "DOWN", "Vertical (top -> bottom)") end },
    { key = "title", kind = "toggle", labelKey = "Show bar title" },
    { key = "time", kind = "toggle", labelKey = "Show remaining time" },
    { key = "font", kind = "dropdown", labelKey = "Timer font", values = function() return M.GlobalPage.FontValues(true) end },
    { key = "fontSize", kind = "slider", labelKey = "Font size", range = { 6, 72, 1 } },
    { key = "outline", kind = "dropdown", labelKey = "Font outline",
        values = function() return M.ValueTextList("", "None", "OUTLINE", "Outline", "THICKOUTLINE", "Thick outline") end },
    { key = "textAlign", kind = "dropdown", labelKey = "Timer text alignment", values = function() return M.ValueTextList(
            "AUTO", "Automatic", "LEFT", "Left", "CENTER", "Center", "RIGHT", "Right") end },
    { key = "textX", kind = "slider", labelKey = "Timer text X offset", range = { -300, 300, 1 } },
    { key = "textY", kind = "slider", labelKey = "Timer text Y offset", range = { -200, 200, 1 } },
    { key = "reachCheck", kind = "toggle", labelKey = "Grey out while the target is out of reach" },
    { key = "reachOpacity", kind = "slider", labelKey = "Out-of-reach opacity (%)", range = { 0, 100, 1 } },
}
local GROUPS = {
    { key = "behavior", title = false, indices = { 1, 2 } },
    { key = "layout", title = "Size and position", indices = { 3, 4, 5, 7, 8 } },
    { key = "appearance", title = "Appearance", indices = { 6, 9, 10, 11, 12, 13, 14 },
        colors = { 1, 2, 3 } },
    { key = "text", title = "Text", indices = { 15, 16, 17, 18, 19, 20, 21, 22 }, colors = { 4 } },
    { key = "reach", title = "Out of reach", indices = { 24 }, colors = { 5 } },
}
local COPY_CATEGORIES = {
    { key = "layout", label = "Size", fields = { "width", "height", "scale" } },
    { key = "appearance", label = "Appearance", fields = {
        "opacity", "texture", "backgroundTexture", "backgroundOpacity", "borderSize", "fill", "direction",
        "color", "backgroundColor", "borderColor" } },
    { key = "text", label = "Text", fields = {
        "title", "time", "font", "fontSize", "outline", "textAlign", "textX", "textY", "textColor" } },
    { key = "behavior", label = "Behavior", fields = { "visibility", "display", "reachCheck", "reachOpacity", "reachColor" } },
}
local function AttachColors(section, hand, indices, ui)
    W.AttachContextColorShortcut(section, {
        title = "Swing Timer colors", historySource = "menu:swing-colors-" .. hand, maxTargets = #indices,
        getTargets = function()
            local targets = {}
            for i = 1, #indices do
                local key, label = COLORS[indices[i]][1], COLORS[indices[i]][2]
                targets[i] = {
                    label = label,
                    getRGB = function() return unpack(Swing.Get(hand, key)) end,
                    setRGB = function(r, g, blue)
                        Swing.Set(hand, key, { r, g, blue })
                        ui.Paint()
                    end,
                }
            end
            return targets
        end,
    })
end
local ROW_OPTIONS = Schema.UnitOptions()
ROW_OPTIONS.register = function(_, widget, row)
    M.RegisterControlMetadata(widget, row.meta, row[4][1], widget._msuf2ControlSchema.kind)
end
local function Position(index, layout)
    local column = (index - 1) % layout.columns
    local row = math.floor((index - 1) / layout.columns)
    return { 28 + column * (layout.controlWidth + 36), -44 - row * 58, layout.controlWidth }
end
local function HandRow(hand, key, kind, args, ui, placement)
    return { kind, key, Swing.Get(hand, key), args, placement,
        meta = Meta(hand .. "." .. key, "swingTimers." .. hand .. "." .. key, nil,
            function() ui.SelectHand(hand) return true end),
        scope = hand, domain = "swing", register = true,
        get = function()
            local value = Swing.Get(hand, key)
            if (key == "texture" or key == "backgroundTexture") and value ~= "" then
                return Swing.ResolveTexture(value, "Interface\\TargetingFrame\\UI-StatusBar")
            end
            return value
        end,
        set = function(value) Swing.Set(hand, key, value) ui.Paint() end,
    }
end
local function SettingRow(hand, spec, ui, layout, index)
    local kind = spec.kind == "toggle" and "flowToggle" or spec.kind
    local args = { spec.labelKey }
    if spec.range then
        args = { spec.labelKey, spec.range[1], spec.range[2], spec.range[3], layout.controlWidth }
    elseif spec.values then args = { spec.labelKey, spec.values, layout.controlWidth } end
    local row = HandRow(hand, spec.key, kind, args, ui, Position(index, layout))
    if spec.key == "texture" or spec.key == "backgroundTexture" then
        row.tip = { spec.labelKey, "Use Preview and drag Swing Timers to see textures without attacking." }
    end
    return row
end
local function BindHeader(ctx, section, hand, key, label, ui)
    Schema.Build(ctx, section, { HandRow(hand, key, "sectionSwitch", { label }, ui) }, ROW_OPTIONS)
end
local function AddHandSection(ctx, b, hand, id, title, height, open, ui)
    local section = b:CollapsibleSection(id, title, height, open)
    Schema.Section(section, hand)
    local entry = section._msuf2CollapsibleEntry
    ui.handEntries[hand][#ui.handEntries[hand] + 1] = entry
    entry._msuf2EnsureVisible = function() ui.SelectHand(hand) end
    return section
end
local function BuildHand(ctx, b, hand, ui, layout)
    for i = 1, #GROUPS do
        local group = GROUPS[i]
        local extra = group.key == "behavior" and hand == "main" and 1 or 0
        local count = #group.indices + extra
        local id = group.key == "behavior" and ("swing_" .. hand) or ("swing_" .. hand .. "_" .. group.key)
        local section = AddHandSection(ctx, b, hand, id, group.title or LABELS[hand],
            50 + math.ceil(count / layout.columns) * 58, i == 1, ui)
        if group.colors then AttachColors(section, hand, group.colors, ui) end
        if group.key == "appearance" then ui.sections[hand] = section end
        if group.key == "behavior" then
            BindHeader(ctx, section, hand, "enabled", LABELS[hand], ui)
        elseif group.key == "reach" then
            BindHeader(ctx, section, hand, "reachCheck", "Grey out while the target is out of reach", ui)
        end
        local rows = {}
        for j = 1, #group.indices do
            rows[#rows + 1] = SettingRow(hand, SPECS[group.indices[j]], ui, layout, j)
        end
        if extra > 0 then
            rows[#rows + 1] = HandRow("main", "offhandLane", "flowToggle",
                { "Show the off-hand timer as a lane in the main-hand bar" }, ui, Position(count, layout))
        end
        Schema.Build(ctx, section, rows, ROW_OPTIONS)
    end
end
local function BuildCue(ctx, b, ui, width)
    local attacks = Swing.CueAttacks()
    local cue = AddHandSection(ctx, b, "main", "swing_next", "Next-swing attacks", 90 + #attacks * 58, false, ui)
    BindHeader(ctx, cue, "main", "nextSwingCue", "Show the queued next-swing attack", ui)
    AttachColors(cue, "main", { 6 }, ui)
    local text = HandRow("main", "nextSwingText", "flowToggle",
        { "Name the queued attack on the main-hand bar" }, ui, { 28, -42 })
    text.tip = { "Name the queued attack on the main-hand bar",
        "While an attack waits for your next swing, the main-hand bar's title shows its name in the cue color, or the text you set for that attack below." }
    local rows = { text }
    for i, attack in ipairs(attacks) do
        local label = M.Format("Text for %s (empty: spell name)", attack.name or tostring(attack.id))
        local row = HandRow("main", attack.key, "textinput", { label, math.min(400, width - 80), true },
            ui, { 28, -82 - (i - 1) * 58 })
        row.commitOnBlur = true
        -- Keep the Support text adapter's empty-string policy in the row's own accessors.
        local get, set = row.get, row.set
        row.get = function() return get() or "" end
        row.set = function(value) set(value or "") end
        rows[#rows + 1] = row
    end
    Schema.Build(ctx, cue, rows, ROW_OPTIONS)
end
local function CopySettings(ctx, ui, target, scopes)
    if (target ~= "all" and not LABELS[target]) or target == ui.selected then return false end
    local selected = false
    for i = 1, #COPY_CATEGORIES do
        if scopes[COPY_CATEGORIES[i].key] then selected = true break end
    end
    if not selected then
        M.ShowStatusFeedback("No copy categories selected.", "warning", 2)
        return false
    end
    M.RunWithHistory("Copy Swing Timer settings", "swing:copy:" .. ui.selected, function()
        for i = 1, #HANDS do
            local hand = HANDS[i]
            if hand ~= ui.selected and (target == "all" or target == hand) then
                for j = 1, #COPY_CATEGORIES do
                    local category = COPY_CATEGORIES[j]
                    if scopes[category.key] then
                        for k = 1, #category.fields do
                            local key = category.fields[k]
                            Swing.Set(hand, key, Swing.Get(ui.selected, key))
                        end
                    end
                end
            end
        end
    end)
    M.Refresh(ctx)
    M.ShowStatusFeedback(M.Format("Copied to %s", target == "all" and M.Tr("All") or M.Tr(LABELS[target])), "ok", 1.8, true)
    return true
end
local function BuildCopy(ctx, ui, width)
    local button = M.Theme.Button(ui.section, "Copy To", 92, 24, { history = false })
    button:SetPoint("TOPRIGHT", ui.section, "TOPRIGHT", -16, -38)
    local scopes = { layout = true, appearance = true, text = true, behavior = true }
    local target = "off"
    local popup = M.UnitSectionsShared.MakeScopeCopyPopup(button, {
        controlDomain = "swing", controlPageKey = "swingtimers", controlPath = "copy",
        declareControl = function(widget) Schema.Owned(widget, "swing", "copyNavigation") end,
        width = 420, height = 260, categories = COPY_CATEGORIES, scopes = scopes,
        categoryRowsPerColumn = 2, targets = { "main", "off", "ranged", "all" },
        targetWidths = { main = 90, off = 90, ranged = 80, all = 48 },
        sourceKey = function() return ui.selected end,
        sourceLabel = function(hand) return M.Tr(LABELS[hand]) end,
        targetLabelText = function(hand) return hand == "all" and "All" or LABELS[hand] end,
        selectedTarget = function()
            if target == ui.selected then target = ui.selected == "main" and "off" or "main" end
            return target
        end,
        isTargetVisible = function(hand, source) return hand ~= source end,
        onTargetClick = function(hand) target = hand end,
        runLabel = "Copy Selected", runWidth = 128,
        onRun = function(_, frame)
            if M.BlockCombatAction() then return false end
            if CopySettings(ctx, ui, target, scopes) then frame:Hide() return true end
            return false
        end,
    })
    local function ShowCopy() popup.Show(button) end
    button:SetScript("OnClick", ShowCopy)
    Schema.Custom(button, {
        id = "menu2.swingtimers.swing.copy.button", kind = "button", labelKey = "Copy To",
        scope = "swing", applyDomain = "copyNavigation", action = Schema.ButtonAction(button), owner = button,
    })
    ui.section:HookScript("OnHide", popup.Hide)
    ui.HideCopy = popup.Hide
    if M.AddTooltip then
        M.AddTooltip(button, "Copy To", "Copies selected settings. Positions, enabled states and main-hand-only options stay unchanged.")
    end
    ui.copyButton, ui.copyPopup, ui.copyScopes = button, popup, scopes
end
local function Build(ctx)
    local b = W.PageBuilder(ctx)
    Swing.menuContext = ctx
    local ui = M.SwingTimerPreview.Build(ctx, b)
    local width = b.width or ctx.width or 700
    local columns = width >= 660 and 2 or 1
    local layout = { columns = columns, controlWidth = math.min(300, (width - 80) / columns) }
    ui.handEntries = { main = {}, off = {}, ranged = {} }
    ui.selected = LABELS[M.swingTimerHand] and M.swingTimerHand or "main"
    local module = b:CollapsibleSection("swing_module", "Swing Timers (Forever)", 90, false)
    Schema.Section(module, "swing")
    Schema.Build(ctx, module, {
        { "sectionSwitch", "enabled", nil, { "Enable Swing Timer module" },
            meta = Meta("enabled", "swingTimers.enabled"), scope = "swing", domain = "swingModule",
            get = Swing.GetEnabled, set = function(value) Swing.SetEnabled(value) M.Refresh(ctx) end,
            tip = { "Swing Timers (Forever)",
                "Replaces all Blizzard swing bars while enabled, even when only one hand is selected. Disabling restores Blizzard's previous visibility." } },
        { "flowToggle", "preview", nil, { "Preview and drag Swing Timers" }, { 28, -42 },
            meta = Meta("preview", nil, "ephemeral"), scope = "swing", domain = "preview",
            get = Swing.GetPreview, set = Swing.SetPreview,
            tip = { "Preview and drag Swing Timers",
                "Enable the module, then drag the selected bars outside combat. "
                    .. "Main Hand and Off Hand can be shown together. Positions are saved in this MSUF profile." } },
    }, ROW_OPTIONS)
    ui.section:HookScript("OnHide", function() Swing.SetPreview(false) end)
    local function SelectHand(hand)
        if not LABELS[hand] then return false end
        if ui.HideCopy and ui.selected ~= hand then ui.HideCopy() end
        ui.selected = hand
        M.swingTimerHand = hand
        local visible = { module._msuf2CollapsibleEntry }
        for i = 1, #HANDS do
            local key = HANDS[i]
            for j = 1, #ui.handEntries[key] do
                local entry = ui.handEntries[key][j]
                entry.outer:SetShown(key == hand)
                if key == hand then visible[#visible + 1] = entry end
            end
        end
        b.layoutEntries = visible
        b:RequestRelayoutCollapsibles()
        if ui.selector then ui.selector:SetValue(hand) end
        ui.Paint()
        return true
    end
    ui.SelectHand = SelectHand
    for i = 1, #HANDS do BuildHand(ctx, b, HANDS[i], ui, layout) end
    BuildCue(ctx, b, ui, width)
    ui.selector = Schema.Build(ctx, ui.section, {
        { "segment", "hand", nil, { "Swing Timers (Forever)",
            M.ValueTextList("main", "Main Hand", "off", "Off Hand", "ranged", "Ranged"), math.min(420, width - 150) },
            { 16, -14, math.min(420, width - 150), "LEFT" },
            meta = Meta("previewHand", nil, "ephemeral"), scope = "swing", domain = "navigation",
            get = function() return ui.selected end, set = SelectHand },
    }, ROW_OPTIONS).hand
    ui.selector._msuf2Title:Hide()
    BuildCopy(ctx, ui, width)
    ui.builder = b
    SelectHand(ui.selected)
end
M.RegisterPage("swingtimers", { title = "Swing Timers (Forever)", build = Build, version = 4 })
