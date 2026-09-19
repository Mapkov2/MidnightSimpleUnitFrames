-- classic_unit_preview_texture_layer_order_smoke.lua <repoRoot> <flavor>
--
-- Vanilla, TBC and Mists load the Retail-named unit preview render
-- (Preview/MSUF_Menu2_UnitPreview_Render.lua). On these clients Preview.Refresh
-- stamps texture layers once the health bar, the power bar and the portrait
-- have their geometry for this refresh, as Factory.Apply does on live frames.
-- A layer anchored to Player Power or to the Portrait must therefore follow
-- what this refresh shows, not what the previous refresh left behind.
--
-- The smoke boots the flavor's whole shipped core and Options graph through
-- tools/tests/client_world.lua, builds the real unit preview and drives its
-- real Refresh twice per case: the first refresh shows the opposite power bar
-- and portrait state, the second one is measured.
--
-- Plain Lua 5.1 with the repo root and a Classic flavor as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a Classic matrix Suffix)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "classic_unit_preview_texture_layer_order_smoke boots the real TOC graph; run it with plain Lua 5.1")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "classic_unit_preview_texture_layer_order_smoke: tools/tests/client_world.lua is missing")()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
end

local world = World.New(root, flavor)
Check(world.client.isClassic == true, "is not a Classic flavor")
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))

-- Widget calls the preview makes that the shared stubs do not model.
local Methods = world.widgets.Methods
for name, method in pairs({
    SetStartPoint = function(self, ...) self.startPoint = { ... } end,
    SetEndPoint = function(self, ...) self.endPoint = { ... } end,
    SetThickness = function(self, value) self.thickness = value end,
    SetAutoFocus = function(self, value) self.autoFocus = value end,
    SetMaxLetters = function(self, value) self.maxLetters = value end,
    EnableKeyboard = function(self, value) self.keyboardEnabled = value end,
}) do
    if Methods[name] == nil then Methods[name] = method end
end

local env, MSUF = world.env, world.core
env.MSUF_EnsureDB(true)
local Preview = MSUF.UFPreview
Check(type(Preview) == "table" and type(Preview._BuildPreview) == "function", "no unit preview builder")
local refreshSource = debug.getinfo(Preview.Refresh, "S").source
Check(refreshSource:find("MSUF_Menu2_UnitPreview_Render.lua", 1, true) ~= nil,
    "Preview.Refresh does not come from the unit preview render: " .. refreshSource)

local parent = env.CreateFrame("Frame", nil, env.UIParent)
parent:SetSize(900, 400)
local panel = env.CreateFrame("Frame", nil, env.UIParent)
panel._msufGetCurrentKey = function() return "player" end
local box = Preview._BuildPreview(parent, panel, 900, 400)
Check(type(box) == "table" and type(box.mock) == "table", "the unit preview did not build")
box:Show()
box.canvas:SetSize(400, 200)
local mock = box.mock
Check(type(mock.texLayers) == "table" and mock.texLayers[1] and mock.texLayers[2], "the preview has no texture layer holders")

local player = env.MSUF_DB.player
local function Refresh()
    MSUF.UF.Config.Refresh()
    Preview.Refresh(box, "CLASSIC_TEXTURE_LAYER_ORDER_SMOKE")
end
local function Show(powerAndPortrait)
    player.showPowerBar = powerAndPortrait
    player.portraitMode = powerAndPortrait and "LEFT" or "OFF"
end
local function Anchor(holder)
    local _, relativeTo = holder:GetPoint(1)
    return relativeTo
end
local function Shown(region) return region ~= nil and region:IsShown() == true end

-- Layer 1 follows Player Power, layer 2 the Portrait, both sized by their target.
player.texLayerEnabled = true
player.texLayerAnchorTarget = "POWER"
player.texLayerAnchor = "LEFT"
player.texLayer2Enabled = true
player.texLayer2AnchorTarget = "PORTRAIT"
player.texLayer2Anchor = "CENTER"
for _, prefix in ipairs({ "texLayer", "texLayer2" }) do
    player[prefix .. "Width"] = 0
    player[prefix .. "Height"] = 0
end

-- 1. The previous refresh hid the power bar and the portrait; this one shows them.
Show(false)
Refresh()
Check(not Shown(mock.powerBG) and not Shown(mock.portrait), "harness: the first refresh still shows power or the portrait")
Show(true)
Refresh()
Check(Shown(mock.powerBG) and Shown(mock.portrait), "harness: the measured refresh shows no power bar or portrait")
Check(Anchor(mock.texLayers[1]) == mock.powerBG,
    "a texture layer anchored to Player Power follows the previous refresh instead of the power bar shown now")
Check(Anchor(mock.texLayers[2]) == mock.portrait,
    "a texture layer anchored to the Portrait follows the previous refresh instead of the portrait shown now")

-- 2. The previous refresh showed both; this one hides them, so both layers
-- fall back to the frame instead of a bar or portrait that is gone.
Show(false)
Refresh()
Check(not Shown(mock.powerBG) and not Shown(mock.portrait), "harness: the measured refresh still shows power or the portrait")
Check(Anchor(mock.texLayers[1]) == mock,
    "a texture layer stays on the Player Power bar this refresh hid")
Check(Anchor(mock.texLayers[2]) == mock,
    "a texture layer stays on the Portrait this refresh hid")

print(string.format("classic_unit_preview_texture_layer_order_smoke: ok (%s)", flavor))
