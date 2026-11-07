-- Real core/Options graph: embedded Swing samples, visible-only refresh and ephemeral hand selector.
local root = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local function Check(value, message) if not value then error(message, 2) end; return value end
local function NoNativeTimer() error("embedded Swing preview used a native timer", 2) end
local mw = MenuWorld.Open(root, "Forever", {
    page = "swingtimers",
    beforeCore = function(world)
        world.env.Enum.PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 }
        world.env.C_DurationUtil = { CreateDuration = NoNativeTimer, CreateDurationTextBinding = NoNativeTimer }
        -- Native visibility checks include ancestors, unlike the shared harness.
        world.widgets.Methods.IsVisible = function(frame)
            while frame do
                if not frame:IsShown() then return false end
                frame = frame:GetParent()
            end
            return true
        end
    end,
})
local M, env, Swing = mw.M, mw.env, mw.core.SwingTimer
local ctx = Check(Swing.menuContext, "Swing menu did not build")
local ui = Check(ctx._msuf2SwingTimerPreview, "embedded Swing preview missing")
Check(ui.section._msuf2FixedPagePreview, "preview must use the shared fixed header")
Check(ui.selected == "main" and ui.samples.main:IsShown(), "main-hand sample not selected initially")
Check(not ui.samples.off:IsShown() and not ui.samples.ranged:IsShown(), "inactive samples are visible")
Check(not Swing.GetEnabled(), "opening the embedded preview enabled the module")
Check(ui.samples.main.Bar:GetValue() == 0.65, "disabled module has no visible sample")
Check(ui.samples.main.Time:GetText() == "1.2", "sample timer text missing")
-- Refresh uses the real menu binder and the shared runtime painter.
Swing.Set("main", "width", 470)
Swing.Set("main", "texture", "Interface\\Buttons\\WHITE8X8")
Swing.Set("main", "backgroundTexture", "Interface\\TargetingFrame\\UI-StatusBar")
Swing.Set("main", "color", { 0.1, 0.3, 0.7 })
Swing.Set("main", "fontSize", 24)
Swing.Set("main", "fill", "remaining")
Swing.Set("main", "direction", "DOWN")
Swing.Set("main", "offhandLane", true)
Swing.Set("off", "color", { 0.2, 0.8, 0.4 })
M.Refresh(ctx)
local main, off = ui.samples.main, ui.samples.off
Check(main:GetWidth() == 470 and main.Bar:GetValue() == 0.35, "settings refresh did not repaint the sample")
Check(main.Bar.orientation == "VERTICAL" and main.Bar.reverseFill, "preview direction differs from settings")
Check(main.Bar.statusBarTexturePath == "Interface\\Buttons\\WHITE8X8", "preview texture differs from settings")
Check(main.Bar.color[3] == 0.7, "preview colour differs from settings")
Check(off.Lane and off.Lane:GetParent() == main and off.Lane:IsShown(), "embedded off-hand lane missing")
Check(off.Lane.color[2] == 0.8, "embedded lane did not use off-hand colour")
local font, size = main.Time:GetFont()
Check(size == 24, "font setting did not repaint")
local function Control(key)
    for _, widget in ipairs(mw.world.widgets.frames) do
        if widget._msuf2CommandAction and widget._msuf2CommandAction.settingKey == key then return widget end
    end
    error("missing Swing control " .. key)
end
local slider = Control("swingTimers.main.width")
slider:GetScript("OnValueChanged")(slider, 501)
Check(main:GetWidth() == 501, "native slider change did not immediately repaint the embedded sample")
local colorTargets = ui.handSections.main.appearance._msuf2ContextColorShortcut._msuf2ContextColorOptions.getTargets()
colorTargets[1].setRGB(0.9, 0.6, 0.1)
Check(main.Bar.color[1] == 0.9, "live colour picker change did not repaint the preview")
-- Layer chips control the embedded surfaces independently of saved visibility.
local chips = {}
for _, chip in ipairs(ui.layerButtons) do chips[chip.key] = chip end
Check(#ui.layerButtons == 7 and chips.guides, "Swing preview or Guides layer missing")
Check(ui.rail:IsShown() and ui.railTitle:IsShown(), "layers should be visible without opening another view")
Check(not ui.section._msuf2FixedPreviewExpanderRecord, "single preview still has an expander")
Check(ui.rail.points[1].point == "BOTTOMLEFT" and ui.rail.points[1].relativeTo == ui.section,
    "layers are not docked under the sample")
Check(ui.canvas.points[2].relativeTo == ui.rail and ui.canvas.points[2].relativePoint == "TOPRIGHT",
    "canvas does not leave room for the layer rail")
Check(ui.canvasHeight >= 148, "initial Swing preview canvas is too short")
local previewHeight = ui.section:GetHeight()
local previewWidth = ui.section:GetWidth()
local header = ui.section._msuf2FixedPagePreviewRecord
Check(header.hostHeight == header.headerTopInset + previewHeight + header.stickyGap,
    "fixed header did not reserve the full preview height on page entry")
header._activating = true
ui.section:SetWidth(380)
ui.section:GetScript("OnSizeChanged")(ui.section, 380, previewHeight)
Check(ui.rail._msuf2ChipRows > 1 and ui.canvasHeight >= 148, "wrapped layers squeezed out the preview canvas")
ui.section:SetWidth(previewWidth)
ui.section:GetScript("OnSizeChanged")(ui.section, previewWidth, ui.section:GetHeight())
header._activating = nil
local targets = main.hitTargets
Check(targets.bar.allPoints == main.Bar:GetStatusBarTexture() and targets.background.allPoints == main.Bar.Background,
    "fill and background click targets are not anchored to their surfaces")
Check(targets.bar:GetFrameLevel() > targets.background:GetFrameLevel()
    and targets.lane:GetFrameLevel() > targets.bar:GetFrameLevel(), "overlapping targets have the wrong hit priority")
env.GameTooltip.SetOwner = function() end
env.GameTooltip.AddLine = function() end
local function Hover(widget, active)
    widget:GetScript(active and "OnEnter" or "OnLeave")(widget)
end
Check(not ui.guide:IsShown(), "guide starts visible with no hover")
Hover(targets.title, true)
Check(ui.guide:IsShown() and ui.guide.points[1].relativeTo == targets.title
    and ui._msuf2SelectedPreviewLayerKey == "title", "title hover did not show its guide and highlight its layer")
chips.guides:Click("LeftButton")
Check(not ui.guide:IsShown() and targets.title:IsShown(), "turning off Guides hid the element or left its guide")
chips.guides:Click("LeftButton")
Check(ui.guide:IsShown(), "turning Guides back on did not restore the hovered guide")
Hover(targets.title, false)
Check(not ui.guide:IsShown(), "title guide survived mouse leave")
Hover(chips.border, true)
Check(ui.guide:IsShown() and ui.guide.points[1].relativeTo == main.PreviewBorder,
    "hovering the border layer did not outline the whole border")
chips.border:Click("LeftButton")
Check(not ui.guide:IsShown(), "hidden layer kept its guide")
chips.border:Click("LeftButton")
Hover(chips.border, false)
Hover(targets.time, true)
ui.SelectHand("off")
Check(not ui.guide:IsShown(), "a hand change kept the previous hand's guide")
ui.SelectHand("main")
Check(env.MSUF_DB.swingTimers.guides == nil, "guide preference leaked into the profile")
chips.bar:Click("LeftButton")
Check(not main.Bar:IsShown() and main.Bar.Background:IsVisible() and off.Lane:IsShown(), "fill and background are not independent")
chips.bar:Click("LeftButton")
chips.background:Click("LeftButton")
Check(main.Bar:IsShown() and not main.Bar.Background:IsShown() and not targets.background:IsShown(), "background toggle hid the fill")
chips.background:Click("LeftButton")
chips.border:Click("LeftButton")
Check(not main.PreviewBorder:IsShown() and main.Bar:IsShown() and not targets.borders[1]:IsShown(),
    "border toggle affected the fill or left its click targets active")
chips.border:Click("LeftButton")
chips.lane:Click("LeftButton")
Check(not off.Lane:IsShown() and not targets.lane:IsShown() and Swing.Get("main", "offhandLane"),
    "lane layer changed the profile or left its hit target active")
chips.lane:Click("LeftButton")
chips.title:Click("LeftButton")
Check(not main.Title:IsShown() and not targets.title:IsShown() and Swing.Get("main", "title"), "title layer changed the profile")
chips.title:Click("LeftButton")
chips.time:Click("LeftButton")
Check(not main.Time:IsShown() and not targets.time:IsShown() and Swing.Get("main", "time"), "time layer changed the profile")
chips.time:Click("LeftButton")
local openExact, focusedKey, focusedExact = M.OpenExactSettingControl
M.OpenExactSettingControl = function(key, ...)
    focusedKey, focusedExact = key, openExact(key, ...)
    return focusedExact
end
for _, link in ipairs({
    { targets.bar, "texture", "appearance" },
    { targets.background, "backgroundTexture", "appearance" },
    { targets.borders[1], "borderSize", "appearance" },
    { targets.title, "title", "text" },
    { targets.time, "time", "text" },
    { targets.lane, "offhandLane", "behavior" },
    { ui.rangeButton, "reachOpacity", "reach", "RightButton" },
    { chips.background, "backgroundTexture", "appearance", "RightButton" },
}) do
    local target, key, group, mouse = unpack(link)
    target:Click(mouse or "LeftButton")
    Check(focusedKey == "swingTimers.main." .. key and focusedExact, "preview did not focus " .. key)
    Check(ui.handSections.main[group]._msuf2CollapsibleEntry.open, "preview did not open " .. group)
    Check(ui.rail:IsVisible(), "opening a setting hid the preview layers")
end
Swing.Set("main", "time", false)
M.Refresh(ctx)
Check(not main.Time:IsShown() and not targets.time:IsShown(), "timer setting did not hide its preview and click target")
chips.time:Click("LeftButton")
Check(focusedKey == "swingTimers.main.time" and focusedExact and not Swing.Get("main", "time"),
    "disabled time layer did not navigate to its setting")
Swing.Set("main", "time", true)
M.Refresh(ctx)
M.OpenExactSettingControl = openExact
mw.world.widgets:RunTimers()

local opacity = Control("swingTimers.main.opacity")
local reachOpacity = Control("swingTimers.main.reachOpacity")
opacity:GetScript("OnValueChanged")(opacity, 80)
reachOpacity:GetScript("OnValueChanged")(reachOpacity, 25)
Check(math.abs(main:GetAlpha() - 0.2) < 1e-6 and main.Bar.color[1] == Swing.Get("main", "reachColor")[1],
    "dragging reach opacity did not paint the simulated out-of-reach state")
Check(not Swing.Get("main", "reachCheck"), "preview changed the live range-check setting")
Check(ui.rangeButton._msuf2PreviewPillActive and ui.rangeButton._msuf2Label:GetText():find("25%%"),
    "range simulation did not show its active percentage")
reachOpacity:GetScript("OnValueChanged")(reachOpacity, 0)
Check(main:GetAlpha() == 0 and not targets.title:IsShown() and ui.rangeButton:IsVisible(),
    "zero opacity hid the recovery control or left an invisible target")
ui.SelectHand("off")
Check(off:GetAlpha() == 1 and not ui.rangeButton._msuf2PreviewPillActive, "range simulation leaked to the other hand")
ui.SelectHand("main")
Check(main:GetAlpha() == 0 and ui.rangeButton._msuf2PreviewPillActive, "returning to the hand lost its simulated state")
ui.rangeButton:Click("LeftButton")
Check(main:GetAlpha() == 0.8 and main.Bar.color[1] == 0.9, "range layer did not restore normal appearance")
local backgroundOpacity = Control("swingTimers.main.backgroundOpacity")
backgroundOpacity:GetScript("OnValueChanged")(backgroundOpacity, 30)
Check(main.Bar.Background:GetAlpha() == 0.3, "background opacity did not repaint")

-- Selector owns no saved setting, and clicking a sample opens only its accordion.
ui.selector.buttons[2]:Click("LeftButton")
Check(ui.selected == "off" and off:IsShown() and not main:IsShown(), "hand selector did not switch sample")
Check(env.MSUF_DB.swingTimers.previewHand == nil, "hand selection wrote into the profile")
ui.handSections.off.appearance._msuf2CollapsibleEntry.SetOpenImmediate(false)
off.hitTargets.background:Click("LeftButton")
Check(ui.handSections.off.appearance._msuf2CollapsibleEntry.open, "off-hand background did not open its settings")
Check(not chips.lane:IsShown(), "off-hand sample exposes the main-hand-only lane")
-- The shared selector controls both the sample and the visible accordion stack.
Check(ui.selector:GetValue() == "off", "top selector lost its selected state")
for hand, entries in pairs(ui.handEntries) do
    for _, entry in ipairs(entries) do
        Check(entry.outer:IsShown() == (hand == "off"), "inactive hand left visible accordions")
    end
end
Check(#ui.builder.layoutEntries == 1 + #ui.handEntries.off, "inactive accordions leave layout gaps")
Check(not ui.selector._msuf2Title:IsShown(), "selection strip exposes a duplicate title")
Check(ui.selector.points[1].y == ui.copyButton.points[1].y, "selection and Copy To are not aligned")
local lastY
for _, entry in ipairs(ui.builder.layoutEntries) do
    local y = entry.outer.points[1].y
    if lastY then Check(y < lastY, "selected accordion flow overlaps") end
    lastY = y
end
-- Exact search hooks reveal a hidden hand before its setting is focused.
slider._msuf2PrepareExactSearchTarget()
Check(ui.selected == "main", "exact width search did not reveal the main hand")
Check(ui.handEntries.main[1].featureSwitch, "hand enable missing from accordion header")
Check(ui.builder.layoutEntries[1].featureSwitch, "module enable missing from accordion header")
ui.SelectHand("ranged")
Check(#ui.handEntries.ranged == 5, "ranged leaked main-hand-only controls")
Check(ctx.entry.sections.swing_next:GetParent():IsShown() == false, "next-swing options leaked into ranged")
ui.SelectHand("off")
-- Page ownership: collapsing a card does not run the preview stop hook.
local previewStops, setPreview = 0, Swing.SetPreview
Swing.SetPreview = function(value) if value == false then previewStops = previewStops + 1 end end
local moduleEntry = ui.builder.layoutEntries[1]
moduleEntry.SetOpenImmediate(true)
moduleEntry.SetOpenImmediate(false)
Check(previewStops == 0, "collapsing module stopped the gameplay preview")
-- No work is done for an inactive page, then reactivation paints current settings.
Hover(off.hitTargets.time, true)
Check(ui.guide:IsShown(), "off-hand hover did not show a guide")
mw:Select("home")
Check(M.activeKey ~= "swingtimers", "page switch did not leave Swing settings")
-- The shared frame fixture does not fire inherited child OnHide bindings.
ui.section:GetScript("OnHide")(ui.section)
Check(previewStops >= 1, "leaving the page did not stop the gameplay drag preview")
Check(not ui.guide:IsShown(), "leaving the page retained a hover guide")
Swing.SetPreview = setPreview
Swing.Set("off", "width", 600)
ui.Paint()
Check(off:GetWidth() ~= 600, "hidden preview still repaints")
mw:Select("swingtimers")
ui.Paint()
Check(off:GetWidth() == 600, "returning to Swing settings did not refresh")
Swing.Set("off", "enabled", false)
Swing.Set("off", "display", "text")
Swing.Set("off", "time", false)
M.Refresh(ctx)
Check(off:IsShown() and not off.Bar:IsShown() and off.Time:IsShown(), "disabled hand / number-only preview missing")
Swing.Set("off", "width", 1200)
Swing.Set("off", "height", 100)
Swing.Set("off", "scale", 200)
Swing.Set("off", "fontSize", 72)
Swing.Set("off", "textX", 300)
Swing.Set("off", "textY", 200)
Swing.Set("off", "x", 2000)
Swing.Set("off", "y", -1200)
M.Refresh(ctx)
Check(off:GetScale() <= (ui.canvasHeight - 8) / 322 and off:GetScale() > 0, "extreme text offsets escape the preview canvas")
Check(off.points[1].relativeTo == ui.canvas, "sample was positioned on the screen")
Check(math.abs(off.points[1].y + 111) < 1, "scaled text bounds were not centered in frame-local units")
Check((-50 + off.points[1].y) * off:GetScale() >= -ui.canvasHeight / 2 and (272 + off.points[1].y) * off:GetScale() <= ui.canvasHeight / 2,
    "scaled timer text is clipped by the preview canvas")
Check(env.MSUF_DB.swingTimers.off.scale == 200 and env.MSUF_DB.swingTimers.off.y == -1200,
    "preview fit changed saved settings")
for _, sample in pairs(ui.samples) do
    Check(not sample:GetName() and not sample.duration and not sample.binding, "sample registered a gameplay timer")
    Check(not sample:GetScript("OnUpdate") and not sample:GetScript("OnDragStop"), "embedded sample polls or saves a position")
end
ui.SelectHand("main")
-- Copy uses selectable categories, clones colours, retains positions and opt-ins, and participates in Undo.
Swing.Set("off", "width", 333)
Swing.Set("off", "x", 120)
Swing.Set("off", "y", -360)
Swing.Set("off", "enabled", false)
Swing.Set("off", "nextSwingText", true)
M.SyncExternalHistoryState()
ui.copyButton:Click("LeftButton")
local copy = Check(ui.copyPopup.GetPopup(), "Copy To popup missing")
Check(not copy._targetBtns.main:IsShown(), "copy offers the current hand as a destination")
copy._targetBtns.off:Click("LeftButton")
copy._runBtn:Click("LeftButton")
Check(Swing.Get("off", "width") == Swing.Get("main", "width"), "copy did not transfer size")
Check(Swing.Get("off", "color")[1] == 0.9 and Swing.Get("off", "color") ~= Swing.Get("main", "color"),
    "copy shared a mutable colour table")
Check(Swing.Get("off", "x") == 120 and Swing.Get("off", "y") == -360, "copy moved the destination")
Check(not Swing.Get("off", "enabled") and Swing.Get("off", "nextSwingText"), "copy overwrote enable or main-hand-only state")
Check(not copy:IsShown(), "completed copy did not close")
M.Undo()
Check(Swing.Get("off", "width") == 333, "copy cannot be undone as one action")
-- An empty category selection changes nothing; Text only leaves size intact.
ui.copyButton:Click("LeftButton")
for key in pairs(ui.copyScopes) do ui.copyScopes[key] = false end
copy._runBtn:Click("LeftButton")
Check(copy:IsShown() and Swing.Get("off", "width") == 333, "empty copy applied or closed")
ui.copyScopes.text = true
copy._runBtn:Click("LeftButton")
Check(Swing.Get("off", "width") == 333 and Swing.Get("off", "fontSize") == 24, "Text copy changed size or skipped text")
ui.copyButton:Click("LeftButton")
ui.copyScopes.layout = true
copy._targetBtns.all:Click("LeftButton")
copy._runBtn:Click("LeftButton")
Check(Swing.Get("ranged", "width") == Swing.Get("main", "width"), "All destination skipped ranged")
ui.copyButton:Click("LeftButton")
ui.SelectHand("off")
Check(not copy:IsShown(), "changing source leaves a stale Copy To popup")
print("forever_swing_menu_preview_smoke: OK")
