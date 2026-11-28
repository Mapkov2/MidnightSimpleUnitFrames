-- Ensure the opaque Flat art of health backgrounds does not sample a
-- transparent border. Observe the real bindings without emulating the GPU.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local World = dofile(root .. "/tools/tests/health_tick_world.lua")
local world = World.New(root, flavor)
local UF, GF = world.UF, world.GF
local db = UF.Config.GetDB()
local flat = "Interface\\Buttons\\WHITE8x8"
local custom = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Bars\\MSUF_Lucent_v2.tga"
local methods = world.h.widgets.Methods
local SetTexture = methods.SetTexture
function methods:SetTexture(path, horizontal, vertical, filter, ...)
    self.edgeTestBinding = { path, horizontal, vertical, filter }
    return SetTexture(self, path, horizontal, vertical, filter, ...)
end

local function Check(texture, path, flatHealth, label)
    local args = assert(texture and texture.edgeTestBinding, label .. " did not bind a texture")
    assert(args[1] == path, label .. " bound the wrong source: " .. tostring(args[1]))
    if flatHealth then
        assert(args[2] == "CLAMP" and args[3] == "CLAMP" and args[4] == "NEAREST",
            label .. " sampled the Flat health texture without clamped nearest filtering")
    else
        assert(args[2] == nil and args[3] == nil and args[4] == nil, label .. " changed non-Flat-health texture sampling")
    end
end

db.general.barBackgroundTexture = "Flat"
db.general.barBgFillMode, db.general.barBgColorMode = "missing", "match_health"
db.target.barBackgroundTexture, db.bars.powerBarBgTexture = "Flat", "Flat"
UF.Config.Refresh()
assert(UF.ApplySpec(world.single, UF.Config.GetSpec("target"), "MSUF_APPLY", true))
Check(world.single.hpBarBG, flat, true, "target health background")
world.single.MSUFSpec.health.backgroundTexture = custom
world.core.Bars.ApplyBarBackgroundVisual(world.single)
Check(world.single.hpBarBG, custom, false, "target custom health background")
world.single.MSUFSpec.health.backgroundTexture = flat
world.core.UFBarTextCommon.ApplyBackgrounds(world.single, true, false)
Check(world.single.hpBarBG, flat, true, "target interleaved health backdrop refresh")

local function ApplyGroup(frame, kind, unit, key)
    local conf = GF.GetConf(kind)
    conf.barTextureOverride, conf.barBackgroundTexture = true, key
    conf.barBgFillMode, conf.barBgColorMode = "missing", "match_health"
    conf.powerBarEnabled, conf.powerHeight, conf.deadBgEnabled = true, 5, true
    conf.powerShowTank, conf.powerShowHealer, conf.powerShowDamager = true, true, true
    GF.InvalidateCompiledSpecs(kind)
    assert(UF.ApplySpec(frame, GF.CompileSpec(kind, frame, unit), "MSUF_APPLY", true))
end

local function CheckDeadTint(frame, kind)
    local group = frame.MSUFSpec.group
    local r, g, b, a = frame.hpBarBG:GetVertexColor()
    assert(r == group.deadBgR and g == group.deadBgG and b == group.deadBgB and a == group.deadBgA,
        kind .. " death tint did not own the sampled backdrop")
end

local function CheckGroup(frame, kind, unit)
    ApplyGroup(frame, kind, unit, "Flat")
    local texture = frame.hpBarBG
    Check(texture, flat, true, kind .. " health cold apply")
    Check(frame.powerBarBG, flat, false, kind .. " power background")

    -- The standalone color/texture refresh can rebind an existing texture.
    local health = frame.MSUFSpec.health
    health.backgroundTexture = custom
    world.core.Bars.ApplyBarBackgroundVisual(frame)
    Check(texture, custom, false, kind .. " custom health backdrop refresh")
    health.backgroundTexture = flat
    world.core.UFBarTextCommon.ApplyBackgrounds(frame, true, false)
    Check(texture, flat, true, kind .. " interleaved health backdrop refresh")
    health.backgroundTexture = custom
    world.core.UFBarTextCommon.ApplyBackgrounds(frame, true, false)
    Check(texture, custom, false, kind .. " custom health backdrop apply")
    health.backgroundTexture = flat
    world.core.Bars.ApplyBarBackgroundVisual(frame)
    Check(texture, flat, true, kind .. " Flat health backdrop refresh")

    -- Force the tint to take over on a real health event. Its art is bound
    -- already, even when Match Health would otherwise repaint its tint.
    ApplyGroup(frame, kind, unit, "Flat")
    world.S.dead, world.S.pct = true, 0
    local before = texture.edgeTestBinding
    world:Fire(frame, unit, "UNIT_HEALTH")
    assert(texture.edgeTestBinding == before, kind .. " death tint rebound unchanged art")
    CheckDeadTint(frame, kind)

    world:StartCounting()
    for _ = 1, 6 do world:Fire(frame, unit, "UNIT_HEALTH") end
    local calls = world:StopCounting()
    assert(texture.edgeTestBinding == before and (calls.SetTexture or 0) == 0,
        kind .. " warmed dead health rebound unchanged art")
    CheckDeadTint(frame, kind)

    -- Simulate a native art reset without touching the product cache. Cold
    -- reapply must still restore the asset and its sampler.
    texture:SetTexture(custom)
    ApplyGroup(frame, kind, unit, "Flat")
    Check(texture, flat, true, kind .. " cold reapply after art reset")
    world.S.dead, world.S.pct = false, 0.46
    world:Fire(frame, unit, "UNIT_HEALTH")
    Check(texture, flat, true, kind .. " revived health backdrop")
end

CheckGroup(world.group, "raid", "raid1")
GF.GetConf("party").enabled = true
GF.RefreshHeaderLayout()
world.h:SetRoster({ "player", "party1" })
world.h:Event("GROUP_ROSTER_UPDATE")
world.h:RunTimers()
assert(GF.FrameForUnit("party1"), "party unit was not created")
CheckGroup(GF.FrameForUnit("party1"), "party", "party1")

print(flavor .. " unit, party and raid Flat health backdrop bindings passed")
