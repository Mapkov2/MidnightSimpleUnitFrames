-- Real client boot: private frame lookup has one named global per built frame.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, "Mainline")
local env = world.env
rawset(env, "MAX_BOSS_FRAMES", 5)
local create = env.CreateFrame
env.CreateFrame = function(kind, name, ...)
    local frame = create(kind, name, ...)
    if name then rawset(env, name, frame) end
    return frame
end
world:Boot()
assert(not world:FirstFailure(), "real core graph must load")
env.MSUF_EnsureDB(true)
env.MSUF_Castbars_OnSettingsChanged()
local driver = world.core.Castbars.Driver
driver.CreateCastBar("MSUF_TargetCastbar", "target")
driver.CreateCastBar("MSUF_FocusCastbar", "focus")
world.core.Castbars.Pools.kinds.boss.ApplyEnabled()
world.core.Castbars.Pools.kinds.arena.ApplyEnabled()
local castbars = world.core.Castbars
for _, kind in ipairs({ "Engine", "Runtime", "Driver", "Pools", "Manager", "Style", "Config", "KickReady" }) do
    assert(type(castbars[kind]) == "table", kind .. " must have a namespace provider")
end
for _, name in ipairs({ "MSUF_CastbarEngine", "MSUF_CastbarRuntime", "MSUF_CreateCastBar", "MSUF__castTimeGlobalRev" }) do
    assert(rawget(env, name) == nil, name .. " must remain namespace-local")
end
local checked = 0
local function Check(frame)
    if not frame then return end
    local names = 0
    for _, value in pairs(env) do if value == frame then names = names + 1 end end
    assert(names == 1, "a castbar frame must have exactly one global name, found " .. names)
    checked = checked + 1
end
for _, kind in ipairs({ "player", "target", "focus", "playerPreview", "targetPreview", "focusPreview", "focusKick", "gcd" }) do
    Check(castbars.Frames.Get(kind))
end
for _, kind in ipairs({ "boss", "arena", "bossPreview", "arenaPreview" }) do
    for i = 1, 5 do Check(castbars.Frames.Get(kind, i)) end
end
assert(checked >= 8, "the real client must build individual and pooled castbars")
assert(world.core.KickReady and type(world.core.PublicGlobals.MSUF_KickReady_IsReady) == "function", "Suite consumers must keep their API")
print("castbar_frame_identity_smoke: ok (" .. checked .. " frames, one global each)")
