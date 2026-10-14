-- The real badge owner must keep the original late client namespace guard.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/client_world.lua")
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = World.New(root, flavor)
    world:Boot()
    assert(not world:FirstFailure(), flavor .. ": real graph did not boot")
    local env, MSUF = world.env, world.core
    env.C_Texture = { GetAtlasInfo = function() return nil end }
    local frame = env.CreateFrame("Frame", nil, env.UIParent)
    frame.MSUFUnitKey = "target"
    local update = MSUF.UFStatusRuntime.ApplyForeverLevelBadge
    local cfg = { foreverBadge = true, layer = 7, size = 16 }
    for _, client in ipairs({ { IsForever = true }, { IsForever = false }, false }) do
        MSUF.Client = client ~= false and client or nil
        update(frame, {}, cfg)
        if client and client.IsForever == true then
            assert(frame.levelBackdrop._msufStatusAtlas == "UI-HUD-UnitFrame-SmallCircle", flavor .. ": stale client binding")
        else
            assert(frame.levelBackdrop._msufStatusAtlas == nil, flavor .. ": original nil-client atlas fallback was removed")
            assert(frame.levelBackdrop._msufStatusTexture:find("circle_mask.tga", 1, true), flavor .. ": wrong fallback texture")
        end
    end
end
print("uf_level_badge_client_binding_smoke: ok (five real graphs; current, replaced and absent client namespaces)")
