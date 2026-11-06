-- Tagged screen positions follow the resolved anchor, including factory aliases.
local root = assert(arg[1], "repository root required")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local checks = 0
local function Check(ok, label)
    assert(ok, label)
    checks = checks + 1
end
local function Near(a, b) return type(a) == "number" and math.abs(a - b) < 0.000001 end
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local world = World.New(root, flavor)
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, failure and failure.message)
    local env, config = world.env, world.core.UF.Config
    local db = config.GetDB()
    local conf, general = db.pet, db.general
    env.UIParent:SetSize(1366, 768)
    local function Case(named, unit, global, cooldown, adapts, label, mode)
        general.anchorName, general.anchorToCooldown = global or "UIParent", cooldown == true
        conf.anchorFrameName, conf.anchorToUnitframe = named, unit
        conf.screenPositionMode, conf.screenPositionHeight = mode or "relativeHeight", 1440
        conf.offsetX, conf.offsetY, conf.x, conf.y = -785, -294, nil, nil
        conf.point, conf.relativePoint = "CENTER", "CENTER"
        local expectedX, expectedY = -785, -294
        if adapts then expectedX, expectedY = expectedX * 768 / 1440, expectedY * 768 / 1440 end
        local spec = config.RefreshUnit("pet")
        local prefix = flavor .. ": " .. label
        Check(Near(spec.x, expectedX) and Near(spec.y, expectedY), prefix .. " compiled the wrong offsets")
        Check(Near(conf.offsetX, expectedX) and Near(conf.offsetY, expectedY), prefix .. " stored the wrong offsets")
        Check(conf.screenPositionHeight == (adapts and 768 or 1440), prefix .. " changed the wrong reference height")
        for _ = 1, 20 do spec = config.RefreshUnit("pet") end
        Check(db.pet == conf and Near(spec.x, expectedX) and Near(spec.y, expectedY), prefix .. " drifted on repeated compile")
        Check(Near(conf.offsetX, expectedX) and Near(conf.offsetY, expectedY), prefix .. " drifted in saved offsets")
    end
    Case(nil, "GLOBAL", nil, false, true, "factory GLOBAL anchor")
    Case(nil, "global", nil, false, true, "legacy global anchor")
    Case(nil, "FREE", nil, false, true, "free screen anchor")
    Case(nil, "UIParent", nil, false, true, "literal screen unit anchor")
    Case(nil, "UI_Parent", nil, false, true, "legacy literal screen unit anchor")
    Case(nil, "", nil, false, true, "empty unit anchor")
    Case(nil, nil, nil, false, true, "implicit screen anchor")
    Case("UIParent", "player", "CustomFrame", true, true, "explicit screen overrides unit and global anchors")
    Case("UI_Parent", "player", nil, false, true, "legacy screen name overrides unit anchor")
    Case(nil, "player", nil, false, false, "player-relative offsets")
    Case("CustomFrame", "GLOBAL", nil, false, false, "explicit custom frame")
    Case(nil, "GLOBAL", "CustomFrame", false, false, "global custom frame")
    Case("EssentialCooldownViewer", "GLOBAL", nil, false, false, "explicit cooldown frame")
    Case(nil, "GLOBAL", nil, true, false, "global cooldown frame")
    Case(nil, "EssentialCooldownViewer", nil, false, false, "legacy cooldown anchor")
    Case(nil, "GLOBAL", nil, false, false, "manual untagged profile", "manual")
    conf.screenPositionMode = nil
    config.RefreshUnit("pet")
    Check(conf.offsetX == -785 and conf.offsetY == -294, flavor .. ": untagged saved position moved")
    conf.screenPositionMode = "relativeHeight"
    config.RefreshUnit("pet")
    env.UIParent:SetSize(2560, 1440)
    local spec = config.RefreshUnit("pet")
    Check(Near(spec.x, -785) and Near(spec.y, -294) and conf.screenPositionHeight == 1440,
        flavor .. ": returning to the reference resolution drifted")
end
print("Unitframe screen position anchors: " .. checks .. " checks passed")
