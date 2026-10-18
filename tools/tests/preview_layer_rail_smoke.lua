local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local replacement, original = os.getenv("PREVIEW_RAIL_BASELINE"), loadfile
if replacement then
    local file = assert(os.getenv("PREVIEW_RAIL_FILE"))
    loadfile = function(path)
        if path:gsub("\\", "/") == root .. "/" .. file then return original(replacement .. "/" .. file) end
        return original(path)
    end
end
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = World.Open(root, flavor, { page = "classpower", locale = arg[3] or "enUS",
    beforeOptions = function(world)
        if arg[4] then
            world.env.MSUF_EnsureDB()
            world.env.MSUF_DB.general.menuAppearancePreset = arg[4]
        end
    end,
})
local M, H = mw.M, mw.M.PreviewHelpers
local function Near(a, b) return math.abs(a - b) < .001 end

local function Tick(button, elapsed)
    local driver = button._msuf2LayerMotion
    local update = driver and driver:GetScript("OnUpdate")
    if update then update(driver, elapsed or 0.10) end
    return driver
end

local function CheckRail(box, rail, buttons)
    local width = box:GetWidth() - 24
    box:LayoutLayerRail(width)
    for _, button in ipairs(buttons) do
        if button:IsShown() then
            local _, _, _, x = button:GetPoint(1)
            assert(x >= 0 and x + button:GetWidth() <= width, "layer chip escapes its rail")
        end
    end
end
M.ClassPowerWorkspace.current:Select("class")
local box = M.ClassPowerWorkspace.current.page.ctx.entry.classPowerPreview
assert(box._msuf2LayerRailHeader:GetText() == M.Tr("Preview Layers"), "class-resource layer title is unclear")
for _, width in ipairs({ 420, 720, 1200 }) do
    box:SetSize(width, 330)
    box:ApplyCompactPreviewPresentation(false)
    CheckRail(box, box.sidebar, box.layerButtons)
    local _, relative = box.sidebar:GetPoint(1)
    assert(relative == box, "class resources still reserve a side column")
    local _, canvasRelative = box.canvas:GetPoint(2)
    assert(canvasRelative == box.sidebar, "class-resource canvas overlaps the bottom rail")
    box:ApplyCompactPreviewPresentation(true)
    assert(not box._msuf2LayerRailHeader:IsShown(), "compact popover repeats its caption")
    assert(box.sidebar:GetWidth() <= width - 24, "compact layer popover escapes the preview")
end
box:ApplyCompactPreviewPresentation(false)
local button = box.layerButtons[1]
assert(button.bar:GetWidth() == 7 and button.bar:GetHeight() == 7, "class resource layer is not a chip")
box.layerAvailable.guides = true
box.layerVisibility.guides = true
button:Refresh()
Tick(button)
assert(Near(button.bar.colorTexture[4], .94), "visible layer lacks the unit-frame highlight")
box.layerVisibility.guides = false
button:Refresh()
Tick(button)
assert(button.bar.colorTexture[4] < .5, "hidden layer is indistinguishable from visible")
local group = M.GroupPreview.CreateNative(mw.env.UIParent, { width = 720, key = "gf_layout" })
group:Show()
group:Refresh("LAYERS_TEST")
assert(group._msuf2LayerRailHeader:GetText() == M.Tr("Preview Layers"), "group layer title is unclear")
CheckRail(group, group._layers, group._layerButtons)
local textButton
for _, candidate in ipairs(group._layerButtons) do if candidate.key == "text" then textButton = candidate end end
assert(textButton and Near(textButton.bar.colorTexture[4], .94), "group visible layer lacks the shared highlight")
-- Shared real layer controls: independent state, hover -> click and hover
-- during motion all retarget the displayed colors instead of jumping.
do
    local owner = { layerVisibility = {}, layerAvailable = {} }
    local parent = mw.env.CreateFrame("Frame", nil, mw.env.UIParent)
    parent:SetSize(300, 100)
    local opts = H.LayerChipButtonOpts(M.Tr, M.Theme.colors, H.PreviewChromePalette(M.Theme), {
        OnEnter = function() end,
    })
    local a = H.CreateLayerButton(parent, owner, { key = "a", label = "A", color = { 0.2, 0.6, 0.9 } }, 1, 160, opts)
    local b = H.CreateLayerButton(parent, owner, { key = "b", label = "B", color = { 0.7, 0.4, 0.2 } }, 2, 160, opts)
    owner.layerVisibility.a = false
    a:Refresh()
    local driver = assert(a._msuf2LayerMotion, "layer fill has no interruptible motion")
    assert(driver.duration == 0.10, "layer fill lost snappy timing")
    Tick(a, 0.025)
    local color, velocity = driver.channels[1].value, driver.channels[1].velocity
    World.FireScript(a, "OnEnter")
    assert(driver.channels[1].value == color and driver.channels[1].velocity == velocity,
        "hover during layer motion reset displayed color/velocity")
    Tick(a, 0.02)
    local position = {}
    for i, channel in ipairs(driver.channels) do position[i] = { channel.value, channel.velocity } end
    World.FireScript(a, "OnClick", "LeftButton")
    assert(owner.layerVisibility.a == true and owner.layerVisibility.b ~= false, "layer click changed another layer or waited for motion")
    for i, channel in ipairs(driver.channels) do
        assert(channel.value == position[i][1] and channel.velocity == position[i][2], "hover-to-click layer motion jumped")
    end
    local age = driver.age
    a:Refresh()
    assert(driver.age == age, "repeated preview refresh restarted its fill")
    Tick(a)
    assert(not driver:GetScript("OnUpdate"), "settled layer left an update")
    local frames = mw:Frames()
    World.FireScript(a, "OnLeave")
    Tick(a)
    World.FireScript(a, "OnClick", "LeftButton")
    Tick(a, 0.02)
    World.FireScript(driver, "OnHide")
    assert(not driver:GetScript("OnUpdate"), "hidden layer retained motion")
    assert(mw:Frames() == frames, "warm layer toggle allocated more frames")
    for _, key in ipairs({ "reduceMotion", "reducedMotion" }) do
        mw.env.MSUF_DB.general[key] = true
        World.FireScript(a, "OnClick", "LeftButton")
        assert(not driver:GetScript("OnUpdate"), "reduced motion layer started work")
        local expected = { unpack(a.bg.colorTexture) }
        M.Theme.StopAllMenuAnimations()
        World.FireScript(driver, "OnHide")
        for i = 1, 4 do assert(Near(a.bg.colorTexture[i], expected[i]), "stop/hide restored stale reduced layer color") end
        mw.env.MSUF_DB.general[key] = nil
    end
    owner.layerAvailable.a = false
    a:Refresh()
    assert(not driver:GetScript("OnUpdate"), "unavailable layer still animates")
    local before = owner.layerVisibility.a
    World.FireScript(a, "OnClick", "LeftButton")
    assert(owner.layerVisibility.a == before, "unavailable layer accepted a click")
    assert(not b._msuf2LayerMotion, "untouched active layer was animated or made exclusive")
end
print("preview_layer_rail_smoke: ok (" .. flavor .. ")")
