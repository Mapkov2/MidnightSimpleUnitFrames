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
local mw = World.Open(root, flavor, { page = "classpower", locale = arg[3] or "enUS" })
local M, H = mw.M, mw.M.PreviewHelpers
local function Near(a, b) return math.abs(a - b) < .001 end
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
assert(Near(button.bar.colorTexture[4], .94), "visible layer lacks the unit-frame highlight")
box.layerVisibility.guides = false
button:Refresh()
assert(button.bar.colorTexture[4] < .5, "hidden layer is indistinguishable from visible")
local group = M.GroupPreview.CreateNative(mw.env.UIParent, { width = 720, key = "gf_layout" })
group:Show()
group:Refresh("LAYERS_TEST")
assert(group._msuf2LayerRailHeader:GetText() == M.Tr("Preview Layers"), "group layer title is unclear")
CheckRail(group, group._layers, group._layerButtons)
local textButton
for _, candidate in ipairs(group._layerButtons) do if candidate.key == "text" then textButton = candidate end end
assert(textButton and Near(textButton.bar.colorTexture[4], .94), "group visible layer lacks the shared highlight")
print("preview_layer_rail_smoke: ok (" .. flavor .. ")")
