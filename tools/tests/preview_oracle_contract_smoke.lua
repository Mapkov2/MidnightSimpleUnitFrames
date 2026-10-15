-- The observation contract itself: roles survive allocation order, and every stored property participates.
local root = assert(arg[1], "root required")
local Regions = assert(loadfile(root .. "/tools/tests/preview_oracle_regions.lua"))()
local Stubs = assert(loadfile(root .. "/.github/scripts/msuf_test_stubs.lua"))()

local function Scene(reversed)
    local widgets = Stubs.New({ shown = true })
    local world = { widgets = widgets, env = { UIParent = widgets.UIParent } }
    Regions.Install(world)
    local body = widgets:CreateFrame("Frame", nil, widgets.UIParent)
    body:SetSize(275, 40)
    local order = reversed and { "power", "health" } or { "health", "power" }
    for _, role in ipairs(order) do
        body[role] = widgets:CreateFrame("StatusBar", nil, body)
        body[role]:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -3)
        body[role]:SetMinMaxValues(0, 100)
        body[role]:SetValue(role == "health" and 72 or 40)
    end
    body.health:SetPoint("TOPLEFT", body, "TOPLEFT", 7, -5)
    assert(#body.health.points == 1, "native anchor replacement was not modelled")
    body.health:SetAlpha(0.7)
    body:SetAlpha(0.5)
    return world, body
end

local world, body = Scene(false)
local expected = Regions.Capture(world, { body = body })
local reordered, other = Scene(true)
local actual = Regions.Capture(reordered, { body = other })
assert(#Regions.Compare(expected, actual) == 0, "semantic roles depend on global allocation order")
assert(expected["body/health"].effectiveAlpha == 0.35, "parent alpha was lost")
body.health:SetIgnoreParentAlpha(true)
actual = Regions.Capture(world, { body = body })
assert(actual["body/health"].effectiveAlpha == 0.7, "ignore-parent alpha was lost")
assert(#Regions.Compare(expected, actual) > 0, "alpha change escaped")
body.health:SetIgnoreParentAlpha(false)
local before = Regions.Capture(world, { body = body })
body.health:SetParent(world.widgets.UIParent)
-- A region removed from the selected surface must appear as a deletion.
actual = Regions.Capture(world, { body = body })
assert(#Regions.Compare(before, actual) > 0, "removed region escaped")
local tiny = Regions.Compare({ x = 0.123456789123 }, { x = 0.123456789124 })
assert(#tiny == 1, "numeric normalization hides a representable property change")
assert(#Regions.Compare({ missing = false }, {}) == 1, "false and missing were conflated")
local multiline = "line one" .. string.char(10, 13, 0) .. '"line two\\42'
assert(assert(loadstring("return " .. Regions.Encode(multiline)))() == multiline, "fixture text serialization changed native text")
local sharedMask = world.widgets.UIParent:CreateMaskTexture("SharedMask")
sharedMask:SetTexture("first-mask")
body.power:GetStatusBarTexture():AddMaskTexture(sharedMask)
local masked = Regions.Capture(world, { body = body })
sharedMask:SetTexture("second-mask")
assert(#Regions.Compare(masked, Regions.Capture(world, { body = body })) > 0, "external mask texture change escaped")
body.text, body.texture, body.color = body.power, body.health, { 1, 0, 0, 1 }
local typed = Regions.Capture(world, { body = body })
assert(typed.body.text == nil and typed.body.texture == nil and typed.body.color == nil,
    "Frame ownership/cache fields were mistaken for native text/texture/statusbar properties")
print("preview_oracle_contract_smoke: ok (semantic roles, anchors, inheritance, removal, numeric precision)")
