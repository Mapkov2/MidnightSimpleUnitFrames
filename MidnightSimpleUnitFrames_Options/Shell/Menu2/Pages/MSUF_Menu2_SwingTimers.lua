-- Independent Forever Swing Timer module settings.
local _, MSUF = ...
if not (MSUF.Client and MSUF.Client.IsForever) then return end
local M = MSUF.MSUF2
local W, AP = M.Widgets, M.AdvancedPage
local Swing = MSUF.SwingTimer
local HANDS = { "main", "off", "ranged" }
local LABELS = { "Main Hand", "Off Hand", "Ranged" }
local function Meta(path, key, classification)
    return AP.ControlMeta("swingtimers", "swing", path, classification or "setting", {
        settingKey = key,
    })
end

local function TextureItems(followText)
    local items = M.StatusBarTextureItems(followText)
    -- Store the same file that the dropdown actually previews, including built-ins.
    for i = 1, #items do
        if items[i].texture then items[i].value = items[i].texture end
    end
    return items
end

local COLORS = {
    { "color", "Bar color" }, { "backgroundColor", "Background color" },
    { "borderColor", "Border color" }, { "textColor", "Text color" },
    { "reachColor", "Out-of-reach color" }, { "nextSwingColor", "Next-swing cue color" },
}
local function AttachColors(section, hand)
    W.AttachContextColorShortcut(section, {
        title = "Swing Timer colors", historySource = "menu:swing-colors-" .. hand, maxTargets = 6,
        getTargets = function()
            local targets = {}
            for i = 1, #COLORS do
                local key, label = COLORS[i][1], COLORS[i][2]
                targets[i] = {
                    label = label,
                    getRGB = function() return unpack(Swing.Get(hand, key)) end,
                    setRGB = function(r, g, blue) Swing.Set(hand, key, { r, g, blue }) end,
                }
            end
            return targets
        end,
    })
end

local function Build(ctx)
    local b = W.PageBuilder(ctx)
    Swing.menuContext = ctx
    local width = b.width or ctx.width or 700
    local columns = width >= 660 and 2 or 1
    local controlWidth = math.min(300, (width - 80) / columns)
    local function Position(widget, section, index)
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        AP.MoveWidget(widget, section, 28 + column * (controlWidth + 36), -48 - row * 58)
    end
    local module = b:CollapsibleSection("swing_module", "Swing Timers (Forever)", 286, true)
    local enabled = W.Toggle(module, "Enable Swing Timer module")
    M.BindBoolWidget(ctx, enabled, Swing.GetEnabled, function(value)
        Swing.SetEnabled(value)
        M.Refresh(ctx)
    end, Meta("enabled", "swingTimers.enabled"))
    AP.MoveWidget(enabled, module, 28, -44)
    for i = 1, #HANDS do
        local hand = HANDS[i]
        local toggle = W.Toggle(module, LABELS[i])
        M.BindBoolWidget(ctx, toggle, function() return Swing.Get(hand, "enabled") end,
            function(value) Swing.Set(hand, "enabled", value) end,
            Meta(hand .. ".enabled", "swingTimers." .. hand .. ".enabled"))
        AP.MoveWidget(toggle, module, 28, -80 - (i - 1) * 32)
    end
    local preview = W.Toggle(module, "Preview and drag Swing Timers")
    M.BindBoolWidget(ctx, preview, Swing.GetPreview, Swing.SetPreview, Meta("preview", nil, "ephemeral"))
    AP.MoveWidget(preview, module, 28, -182)
    local lane = W.Toggle(module, "Show the off-hand timer as a lane in the main-hand bar")
    M.BindBoolWidget(ctx, lane, function() return Swing.Get("main", "offhandLane") end,
        function(value) Swing.Set("main", "offhandLane", value) end,
        Meta("main.offhandLane", "swingTimers.main.offhandLane"))
    AP.MoveWidget(lane, module, 28, -222)
    if M.AddTooltip then
        M.AddTooltip(enabled, "Swing Timers (Forever)",
            "Replaces all Blizzard swing bars while enabled, even when only one hand is selected. Disabling restores Blizzard's previous visibility.")
        M.AddTooltip(preview, "Preview and drag Swing Timers",
            "Enable the module, then drag the selected bars outside combat. Main Hand and Off Hand can be shown together. Positions are saved in this MSUF profile.")
    end
    module:HookScript("OnHide", function() Swing.SetPreview(false) end)

    local specs = {
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
    for i = 1, #HANDS do
        local hand = HANDS[i]
        local section = b:CollapsibleSection("swing_" .. hand, LABELS[i],
            70 + math.ceil(#specs / columns) * 58, i == 1)
        AttachColors(section, hand)
        for j = 1, #specs do
            local spec = specs[j]
            local key, kind, label = spec[1], spec[2], spec[3]
            local meta = Meta(hand .. "." .. key, "swingTimers." .. hand .. "." .. key)
            local function Get()
                local value = Swing.Get(hand, key)
                if (key == "texture" or key == "backgroundTexture") and value ~= "" then
                    return Swing.ResolveTexture(value, "Interface\\TargetingFrame\\UI-StatusBar")
                end
                return value
            end
            local function Set(value) Swing.Set(hand, key, value) end
            local widget
            if kind == "number" then
                widget = W.Slider(section, label, spec[4], spec[5], 1, controlWidth)
                M.BindNumberWidget(ctx, widget, Get, Set, Get(), meta)
            elseif kind == "boolean" then
                widget = W.Toggle(section, label)
                M.BindBoolWidget(ctx, widget, Get, Set, meta)
            else
                widget = W.Dropdown(section, label, spec[4], controlWidth)
                M.BindDropdownWidget(ctx, widget, Get, Set, meta)
            end
            Position(widget, section, j)
            if M.AddTooltip and (key == "texture" or key == "backgroundTexture") then
                M.AddTooltip(widget, label, "Use Preview and drag Swing Timers to see textures without attacking.")
            end
        end
    end
    local attacks = Swing.CueAttacks()
    local cue = b:CollapsibleSection("swing_next", "Next-swing attacks", 150 + #attacks * 58, false)
    local cueToggle = W.Toggle(cue, "Show the queued next-swing attack")
    M.BindBoolWidget(ctx, cueToggle, function() return Swing.Get("main", "nextSwingCue") end,
        function(value) Swing.Set("main", "nextSwingCue", value) end,
        Meta("main.nextSwingCue", "swingTimers.main.nextSwingCue"))
    AP.MoveWidget(cueToggle, cue, 28, -42)
    local cueText = W.Toggle(cue, "Name the queued attack on the main-hand bar")
    M.BindBoolWidget(ctx, cueText, function() return Swing.Get("main", "nextSwingText") end,
        function(value) Swing.Set("main", "nextSwingText", value) end,
        Meta("main.nextSwingText", "swingTimers.main.nextSwingText"))
    AP.MoveWidget(cueText, cue, 28, -74)
    -- One text per next-swing attack, labelled with the client's spell name.
    for i, attack in ipairs(attacks) do
        local key = attack.key
        M.BindTextInputAt(ctx, cue, M.Format("Text for %s (empty: spell name)", attack.name or tostring(attack.id)), 28, -116 - (i - 1) * 58,
            math.min(400, width - 80),
            function() return Swing.Get("main", key) end,
            function(value) Swing.Set("main", key, value) end,
            true, Meta("main." .. key, "swingTimers.main." .. key))
    end
    if M.AddTooltip then
        M.AddTooltip(cueText, "Name the queued attack on the main-hand bar",
            "While an attack waits for your next swing, the main-hand bar's title shows its name in the cue color, or the text you set for that attack below.")
    end
    ctx:SetContentHeight(math.abs(b.y) + 32)
end

M.RegisterPage("swingtimers", { title = "Swing Timers (Forever)", build = Build, version = 2 })
