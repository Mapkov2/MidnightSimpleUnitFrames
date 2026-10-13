-- exports_probe.lua <root> <flavor>
-- Boots the real core + Options graph, logs in, and prints the castbar-related
-- public surface: every MSUF_* global whose name mentions a castbar concept, the
-- MSUF.KickReady / HostAPI.GetKickReady surface, and what each frame global points at.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
local env = world.env
rawset(env, "MAX_BOSS_FRAMES", 5)
rawset(env, "StaticPopupDialogs", {})
local create = env.CreateFrame
env.CreateFrame = function(kind, name, ...)
    local frame = create(kind, name, ...)
    if type(name) == "string" and name ~= "" then rawset(env, name, frame) end
    return frame
end
world:Boot()
local failure = world:FirstFailure()
assert(not failure, failure and failure.message)
local function Deliver(event, ...)
    local frames = world.widgets.frames
    local bus = world.core.EventBus
    for index = 1, #frames do
        local frame = frames[index]
        local events, scripts = rawget(frame, "events"), rawget(frame, "scripts")
        local handler = scripts and scripts.OnEvent
        if handler and events and events[event] then
            if bus and frame == bus.driver then
                local entry = bus.handlers[event]
                for _, item in ipairs(entry and entry.list or {}) do
                    if item.fn and not item.dead then pcall(item.fn, event, ...) end
                end
            else
                pcall(handler, frame, event, ...)
            end
        end
    end
end
Deliver("ADDON_LOADED", "MidnightSimpleUnitFrames")
Deliver("ADDON_LOADED", "MidnightSimpleUnitFrames_Options")
Deliver("PLAYER_LOGIN")
Deliver("PLAYER_ENTERING_WORLD", true, false)
pcall(env.MSUF_Castbars_OnSettingsChanged, "probe")
for _ = 1, 3 do pcall(world.widgets.RunTimers, world.widgets) end


local cb = world.core.Castbars
local failures = {}
local function Check(name, fn)
    local ok, why = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(why) end
end
Check("boss setup", function()
    local calls = 0
    local original = cb.Previews.SetupBossCastbarPreviewEditMode
    cb.Previews.SetupBossCastbarPreviewEditMode = function(...) calls = calls + 1 return original(...) end
    env.MSUF_UpdateCastbarVisuals("boss")
    assert(calls == 1, "boss preview setup calls=" .. calls)
    cb.Previews.SetupBossCastbarPreviewEditMode = original
end)
Check("unit frame independence", function()
    for _, kind in ipairs({ "target", "focus" }) do
        env.MSUF_DB.general["castbar" .. (kind == "target" and "Target" or "Focus") .. "Backend"] = "MSUF"
        env.MSUF_DB[kind].enabled = false
        env.MSUF_Castbars_OnSettingsChanged("test")
        assert(next(cb.Frames.Get(kind).events), kind .. " castbar lost its events")
    end
end)
Check("first apply geometry", function()
    local g = env.MSUF_DB.general
    g.castbarPlayerDetached = true
    g.castbarPlayerOffsetY = 77
    g.castbarPlayerBarHeight = 19.25
    env.MSUF_ApplyAllCastbarsAndSync()
    local _, _, _, _, y = cb.Frames.Get("player"):GetPoint(1)
    assert(y == 77, "offsetY=" .. tostring(y))
    assert(cb.Frames.Get("player"):GetHeight() == 19.25, "stale height")
end)
Check("consumer surface", function()
    local expected = { version = true, Register = true, Unregister = true, HasConsumers = true,
        SetActive = true, Look = true, RGBA = true, FillColors = true, SelectColor = true,
        SlotCount = true, Cooldown = true }
    assert(world.core.KickReady ~= cb.KickReady, "consumer table exposes internal module")
    for key in pairs(world.core.KickReady) do assert(expected[key], "extra consumer key " .. key) end
    for key in pairs(expected) do assert(world.core.KickReady[key] ~= nil, "missing consumer key " .. key) end
end)
Check("one compile per settings flush", function()
    local count = 0
    local original = cb.Config.Compile
    cb.Config.Compile = function(...) count = count + 1 return original(...) end
    env.MSUF_Castbars_OnSettingsChanged("test")
    cb.Config.Compile = original
    assert(count == 1, "settings flush compiled " .. count .. " times")
end)
Check("one compile on first settings apply", function()
    local count, original = 0, cb.Config.Compile
    cb.Config.ready = false
    cb.Config.Compile = function(...) count = count + 1 return original(...) end
    env.MSUF_Castbars_OnSettingsChanged("test")
    cb.Config.Compile = original
    assert(count == 1, "first settings apply compiled " .. count .. " times")
end)
for _, why in ipairs(failures) do print(why) end
assert(#failures == 0, #failures .. " castbar apply regressions")
print("castbar_apply_boundary_smoke: ok")
