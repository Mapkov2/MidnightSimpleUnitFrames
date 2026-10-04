-- Independent Forever Swing Timer module settings.
local _, MSUF = ...
if not (MSUF.Client and MSUF.Client.IsForever) then return end
local M = MSUF.MSUF2
local W, AP = M.Widgets, M.AdvancedPage
local Swing = MSUF.SwingTimer
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
    { "visibility", "dropdown", "Visibility", function() return M.ValueTextList("always", "Always", "combat", "In combat") end },
    { "display", "dropdown", "Display mode", function() return M.ValueTextList("bar", "Bar and timer", "text", "Number only") end },
    { "width", "number", "Width", 40, 1200 },
    { "height", "number", "Height", 4, 100 },
    { "scale", "number", "Scale %", 50, 200 },
    { "opacity", "number", "Opacity %", 0, 100 },
    { "x", "number", "X offset", -2000, 2000 },
    { "y", "number", "Y offset", -1200, 1200 },
    { "texture", "dropdown", "Bar texture", function() return TextureItems() end },
    { "backgroundTexture", "dropdown", "Background texture", function() return TextureItems("Use foreground texture") end },
    { "backgroundOpacity", "number", "Background opacity", 0, 100 },
    { "borderSize", "number", "Border thickness", 0, 8 },
    { "fill", "dropdown", "Timer progression", function() return M.ValueTextList("elapsed", "Fill up", "remaining", "Drain") end },
    { "direction", "dropdown", "Fill direction", function() return M.ValueTextList(
            "RIGHT", "Horizontal (left -> right)", "LEFT", "Horizontal (right -> left)",
            "UP", "Vertical (bottom -> top)", "DOWN", "Vertical (top -> bottom)") end },
    { "title", "boolean", "Show bar title" },
    { "time", "boolean", "Show remaining time" },
    { "font", "dropdown", "Timer font", function() return M.GlobalPage.FontValues(true) end },
    { "fontSize", "number", "Font size", 6, 72 },
    { "outline", "dropdown", "Font outline", function() return M.ValueTextList("", "None", "OUTLINE", "Outline", "THICKOUTLINE", "Thick outline") end },
    { "textAlign", "dropdown", "Timer text alignment", function() return M.ValueTextList(
            "AUTO", "Automatic", "LEFT", "Left", "CENTER", "Center", "RIGHT", "Right") end },
    { "textX", "number", "Timer text X offset", -300, 300 },
    { "textY", "number", "Timer text Y offset", -200, 200 },
    { "reachCheck", "boolean", "Grey out while the target is out of reach" },
    { "reachOpacity", "number", "Out-of-reach opacity (%)", 0, 100 },
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
local function Position(widget, section, index, layout)
    local column = (index - 1) % layout.columns
    local row = math.floor((index - 1) / layout.columns)
    AP.MoveWidget(widget, section, 28 + column * (layout.controlWidth + 36), -44 - row * 58, layout.controlWidth)
end
local function BindSetting(ctx, section, hand, spec, ui, layout, index)
    local key, kind, label = spec[1], spec[2], spec[3]
    local meta = Meta(hand .. "." .. key, "swingTimers." .. hand .. "." .. key, nil,
        function() ui.SelectHand(hand) return true end)
    local function Get()
        local value = Swing.Get(hand, key)
        if (key == "texture" or key == "backgroundTexture") and value ~= "" then
            return Swing.ResolveTexture(value, "Interface\\TargetingFrame\\UI-StatusBar")
        end
        return value
    end
    local function Set(value)
        Swing.Set(hand, key, value)
        ui.Paint()
    end
    local widget
    if kind == "number" then
        widget = W.Slider(section, label, spec[4], spec[5], 1, layout.controlWidth)
        M.BindNumberWidget(ctx, widget, Get, Set, Get(), meta)
    elseif kind == "boolean" then
        widget = W.Toggle(section, label)
        M.BindBoolWidget(ctx, widget, Get, Set, meta)
    else
        widget = W.Dropdown(section, label, spec[4], layout.controlWidth)
        M.BindDropdownWidget(ctx, widget, Get, Set, meta)
    end
    AP.RegisterControl(widget, meta, label, kind == "number" and "slider" or kind == "boolean" and "toggle" or kind)
    Position(widget, section, index, layout)
    if M.AddTooltip and (key == "texture" or key == "backgroundTexture") then
        M.AddTooltip(widget, label, "Use Preview and drag Swing Timers to see textures without attacking.")
    end
end
local function BindHeader(ctx, section, hand, key, label, ui)
    local toggle = W.SectionSwitch(section, label)
    local meta = Meta(hand .. "." .. key, "swingTimers." .. hand .. "." .. key, nil,
        function() ui.SelectHand(hand) return true end)
    M.BindBoolWidget(ctx, toggle, function() return Swing.Get(hand, key) end,
        function(value) Swing.Set(hand, key, value) ui.Paint() end, meta)
    AP.RegisterControl(toggle, meta, label, "toggle")
end
local function AddHandSection(ctx, b, hand, id, title, height, open, ui)
    local section = b:CollapsibleSection(id, title, height, open)
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
        for j = 1, #group.indices do
            BindSetting(ctx, section, hand, SPECS[group.indices[j]], ui, layout, j)
        end
        if extra > 0 then
            local lane = W.Toggle(section, "Show the off-hand timer as a lane in the main-hand bar")
            M.BindBoolWidget(ctx, lane, function() return Swing.Get("main", "offhandLane") end,
                function(value) Swing.Set("main", "offhandLane", value) ui.Paint() end,
                Meta("main.offhandLane", "swingTimers.main.offhandLane", nil, function() ui.SelectHand("main") return true end))
            AP.RegisterControl(lane, Meta("main.offhandLane", "swingTimers.main.offhandLane", nil,
                function() ui.SelectHand("main") return true end),
                "Show the off-hand timer as a lane in the main-hand bar", "toggle")
            Position(lane, section, count, layout)
        end
    end
end
local function BuildCue(ctx, b, ui, width)
    local attacks = Swing.CueAttacks()
    local cue = AddHandSection(ctx, b, "main", "swing_next", "Next-swing attacks", 90 + #attacks * 58, false, ui)
    BindHeader(ctx, cue, "main", "nextSwingCue", "Show the queued next-swing attack", ui)
    AttachColors(cue, "main", { 6 }, ui)
    local cueText = W.Toggle(cue, "Name the queued attack on the main-hand bar")
    M.BindBoolWidget(ctx, cueText, function() return Swing.Get("main", "nextSwingText") end,
        function(value) Swing.Set("main", "nextSwingText", value) ui.Paint() end,
        Meta("main.nextSwingText", "swingTimers.main.nextSwingText", nil, function() ui.SelectHand("main") return true end))
    AP.RegisterControl(cueText, Meta("main.nextSwingText", "swingTimers.main.nextSwingText", nil,
        function() ui.SelectHand("main") return true end), "Name the queued attack on the main-hand bar", "toggle")
    AP.MoveWidget(cueText, cue, 28, -42)
    for i, attack in ipairs(attacks) do
        local key = attack.key
        local label = M.Format("Text for %s (empty: spell name)", attack.name or tostring(attack.id))
        local edit = M.BindTextInputAt(ctx, cue, M.Format("Text for %s (empty: spell name)", attack.name or tostring(attack.id)),
            28, -82 - (i - 1) * 58, math.min(400, width - 80),
            function() return Swing.Get("main", key) end,
            function(value) Swing.Set("main", key, value) ui.Paint() end,
            true, Meta("main." .. key, "swingTimers.main." .. key, nil, function() ui.SelectHand("main") return true end))
        AP.RegisterControl(edit, Meta("main." .. key, "swingTimers.main." .. key, nil,
            function() ui.SelectHand("main") return true end), label, "textinput")
    end
    if M.AddTooltip then
        M.AddTooltip(cueText, "Name the queued attack on the main-hand bar",
            "While an attack waits for your next swing, the main-hand bar's title shows its name in the cue color, or the text you set for that attack below.")
    end
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
    M.ShowStatusFeedback(M.Format("Copied to %s", target == "all" and M.Tr("All") or M.Tr(LABELS[target])), "ok", 1.8)
    return true
end
local function BuildCopy(ctx, ui, width)
    local button = M.Theme.Button(ui.section, "Copy To", 92, 24, { history = false })
    button:SetPoint("TOPRIGHT", ui.section, "TOPRIGHT", -16, -38)
    local scopes = { layout = true, appearance = true, text = true, behavior = true }
    local target = "off"
    local popup = M.UnitSectionsShared.MakeScopeCopyPopup(button, {
        controlDomain = "swing", controlPageKey = "swingtimers", controlPath = "copy",
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
    button:SetScript("OnClick", function() popup.Show(button) end)
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
    local enabled = W.SectionSwitch(module, "Enable Swing Timer module")
    M.BindBoolWidget(ctx, enabled, Swing.GetEnabled, function(value)
        Swing.SetEnabled(value)
        M.Refresh(ctx)
    end, Meta("enabled", "swingTimers.enabled"))
    local preview = W.Toggle(module, "Preview and drag Swing Timers")
    M.BindBoolWidget(ctx, preview, Swing.GetPreview, Swing.SetPreview, Meta("preview", nil, "ephemeral"))
    AP.MoveWidget(preview, module, 28, -42)
    if M.AddTooltip then
        M.AddTooltip(enabled, "Swing Timers (Forever)",
            "Replaces all Blizzard swing bars while enabled, even when only one hand is selected. Disabling restores Blizzard's previous visibility.")
        M.AddTooltip(preview, "Preview and drag Swing Timers",
            "Enable the module, then drag the selected bars outside combat. Main Hand and Off Hand can be shown together. Positions are saved in this MSUF profile.")
    end
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
    ui.selector = W.Segment(ui.section, "Swing Timers (Forever)",
        M.ValueTextList("main", "Main Hand", "off", "Off Hand", "ranged", "Ranged"), math.min(420, width - 150))
    AP.MoveWidget(ui.selector, ui.section, 16, -14, math.min(420, width - 150), "LEFT")
    ui.selector._msuf2Title:Hide()
    M.BindSegment(ctx, ui.selector, function() return ui.selected end, SelectHand, Meta("previewHand", nil, "ephemeral"))
    BuildCopy(ctx, ui, width)
    ui.builder = b
    SelectHand(ui.selected)
end
M.RegisterPage("swingtimers", { title = "Swing Timers (Forever)", build = Build, version = 4 })
