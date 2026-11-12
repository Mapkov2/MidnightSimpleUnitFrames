-- Bars > Textures & Gradient live preview: the health and power lanes paint the
-- runtime unit scene at half value, and every material write repaints them.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MW.Open(root, flavor, { page = "home", clientScriptBindings = true })
local M = mw.M
local function Settle() mw:RunTimers(); M.Theme.StopAllMenuAnimations() end
local function Descends(frame, parent)
    while frame do
        if frame == parent then return true end
        frame = frame:GetParent()
    end
end
local function Find(predicate)
    local found
    for _, frame in ipairs(mw.world.widgets.frames) do
        if predicate(frame) and Descends(frame, mw.win) then
            assert(not found, "more than one match")
            found = frame
        end
    end
    return found
end
local function Control(key)
    return assert(Find(function(frame)
        local schema = frame._msuf2ControlSchema
        return schema and schema.key == key and schema.set ~= nil
    end), "control missing: " .. key)._msuf2ControlSchema
end
local function Half(bar, label)
    assert(bar and bar.GetValue, label .. " bar missing")
    local low, high = bar:GetMinMaxValues()
    local value = bar:GetValue()
    assert(high > low and math.abs((value - low) / (high - low) - 0.5) < 0.001,
        ("%s is not half full: %s of %s..%s"):format(label, tostring(value), tostring(low), tostring(high)))
end

local db = M.EnsureDB()
db.general.hpPowerTextSelectedKey = "shared"
assert(M.Open("opt_bars")); Settle()
local panel = assert(Find(function(frame) return frame._msuf2BarMaterialPreview ~= nil end),
    "Textures & Gradient has no live preview")
local lanes = panel._msuf2BarMaterialPreview
panel:Refresh()
local health = assert(lanes.health.scene, "health lane never painted"):Frame()
local power = assert(lanes.power.scene, "power lane never painted"):Frame()
assert(health:GetParent() and Descends(health, panel) and Descends(power, panel), "preview escaped its panel")

-- Health lane: the runtime health bar alone, half full; power lane: a full-height
-- embedded power bar, half full. No prediction overlays muddy either sample.
local hs, ps = health.MSUFSpec, power.MSUFSpec
assert(hs.power.enabled == false and hs.prediction.enabled == false, "health lane drew power or prediction")
assert(ps.power.enabled and ps.power.embed and not ps.power.detached and ps.power.height == ps.height,
    "power lane is not one full-height embedded power bar")
assert(ps.prediction.enabled == false, "power lane drew prediction")
Half(health.hpBar, "health")
Half(power.targetPowerBar or power.powerBar, "power")

-- Each write repaints at once, through the same compile the live frames use.
Control("enableGradient").set(true)
Settle()
assert(lanes.health.scene:Frame().MSUFSpec.health.barGradient.enabled == true, "health gradient did not reach the preview")
local grads = health.hpGradients
assert(grads and grads.right and grads.right:IsShown(), "health gradient was not painted")
Control("enablePowerGradient").set(true)
Settle()
assert(power.MSUFSpec.power.barGradient.enabled == true, "power gradient did not reach the preview")
Control("healthGlossEnabled").set(true)
Settle()
assert(health.MSUFSpec.health.barGloss.enabled == true and health.hpGloss and health.hpGloss.upper:IsShown(),
    "health gloss was not painted")
Control("powerGlossEnabled").set(true)
Settle()
assert(power.MSUFSpec.power.barGloss.enabled == true and power.powerGloss and power.powerGloss.upper:IsShown(),
    "power gloss was not painted")

-- An idle page refresh does not repaint; a scope switch does.
local paints, scene = 0, lanes.health.scene
local refresh = scene.Refresh
function scene:Refresh()
    paints = paints + 1
    return refresh(self)
end
panel:RefreshIfStale()
assert(paints == 0, "idle page refresh repainted the preview")
scene.Refresh = nil
db.general.hpPowerTextSelectedKey = "gf_party"
panel:RefreshIfStale()
Settle()
local group = assert(lanes.health.scene, "party scope lost the preview")
local frames = group.Frames and group:Frames()
local body = frames and frames[1]
assert(body and body._msufGFKind == "party", "party scope did not show a party frame")
assert(not lanes.power.root.parent:IsShown(), "party scope kept the unit power lane")
db.general.hpPowerTextSelectedKey = "shared"
panel:RefreshIfStale()
assert(lanes.power.root.parent:IsShown(), "unit scope did not restore the power lane")
print("bars_material_preview_smoke: ok " .. flavor)
