-- Complete the deferred login spawn before any later world/scale event.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local world = assert(loadfile(root .. "/tools/tests/client_world.lua"))().New(root, flavor)
local env = world.env
env.MAX_BOSS_FRAMES = 5
if not world.client.isClassic then
    local provider = env.CreateFrame("Frame", nil, env.UIParent)
    provider:SetSize(240, 40)
    env.MSUFSuite = { CooldownManager = { GetAnchorFrame = function() return provider end } }
end
-- Install sink guards before files capture the native API aliases.
local create = env.CreateFrame
env.CreateFrame = function(kind, name, parent, template)
    assert(not (env.InCombatLockdown() and template and template:find("Secure", 1, true)), "secure creation in combat")
    return create(kind, name, parent, template)
end
for _, key in ipairs({ "RegisterUnitWatch", "UnregisterUnitWatch", "RegisterStateDriver", "UnregisterStateDriver" }) do
    local original = env[key]
    env[key] = function(...)
        assert(not env.InCombatLockdown(), key .. " in combat")
        return original(...)
    end
end
local methods = getmetatable(world.widgets.UIParent).__index
for _, key in ipairs({ "Show", "Hide", "SetPoint", "ClearAllPoints", "SetParent", "SetSize", "SetAttribute", "EnableMouse" }) do
    local original = methods[key]
    methods[key] = function(frame, ...)
        local owner = frame
        while owner do
            local template = rawget(owner, "template")
            assert(not (env.InCombatLockdown() and template and template:find("Secure", 1, true)), key .. " in combat")
            owner = rawget(owner, "parent")
        end
        return original(frame, ...)
    end
end
world:Boot()
local failure = world:FirstFailure()
assert(not failure, failure and failure.message)
env.MSUF_InitProfiles()
env.MSUF_EnsureDB(true)
local UF = assert(world.core.UF)
local Factory = assert(UF.Factory)
-- Frame names owned by the embedded framework also start absent in a real client.
for _, unit in ipairs(UF.unitOrder) do rawset(env, UF.FrameName(unit), false) end
local counts, units = {}, {}
-- Element behavior is covered separately; keep fake widget slot fields out of this lifecycle test.
UF.ApplySpec = function(frame, spec)
    assert(not env.InCombatLockdown(), "spec applied in combat")
    frame.MSUFSpec = spec
end
local spawning = false
local function Observe(owner, key, label, fullLayout)
    local original = assert(owner[key], key .. " missing")
    owner[key] = function(...)
        if spawning then
            counts[label] = (counts[label] or 0) + 1
            if fullLayout then
                assert(select("#", ...) == 1 and (...) == nil, label .. " must refresh all units")
                assert(UF.spawned and UF.initialized and counts.ApplyOne == #UF.unitOrder,
                    label .. " refreshed before the full spawn completed")
            end
        end
        return original(...)
    end
end
Observe(world.core.Highlight, "Refresh", "highlight")
Observe(UF, "DisableBlizzardFrames", "blizzard")
Observe(UF, "FlushDeferredRefreshes", "refreshes")
-- Audit all four Factory.Apply tail effects on the complete spawn path.
Observe(env, "MSUF_RefreshUnitTextureLayers", "textures", true)
Observe(env, "MSUF_ArenaTrinkets_RefreshLayout", "trinkets", true)
Observe(env, "MSUF_FocusKickDriver_ForceUpdate", "focusKick")
Observe(env, "MSUF_KickReady_RefreshAll", "kickReady")
local spawn = Factory.SpawnAll
for i = 1, 60 do
    local name, original = debug.getupvalue(spawn, i)
    if not name then break end
    if name == "ResolveConfig" or name == "EnsureCooldownWidthObservers" or name == "ApplyOne" then
        debug.setupvalue(spawn, i, function(...)
            if spawning then
                counts[name] = (counts[name] or 0) + 1
                if name == "ApplyOne" then
                    local unit = ...
                    units[unit] = (units[unit] or 0) + 1
                end
            end
            return original(...)
        end)
    end
end
local completed = 0
Factory.SpawnAll = function(...)
    spawning = not env.InCombatLockdown()
    local result = spawn(...)
    spawning = false
    if result then completed = completed + 1 end
    return result
end
world.widgets:SetCombat(true)
world:FireEvent("PLAYER_LOGIN")
assert(not UF.spawned and not UF.initialized and #UF.frameList == 0, "login spawned frames in combat")
assert(completed == 0 and next(counts) == nil, "SpawnAll steps ran in combat")
UF.Initialize()
Factory.SpawnAll()
UF.ApplyDirty()
world:FireEvent("PLAYER_REGEN_ENABLED")
assert(not UF.spawned and completed == 0, "regen touched frames while lockdown remained true")
world.widgets:SetCombat(false)
world:FireEvent("PLAYER_REGEN_ENABLED")
assert(UF.spawned and UF.initialized, "combat login never completed SpawnAll")
assert(completed == 1, "deferred SpawnAll must complete once")
local function AssertSpawnStepsOnce()
    for _, key in ipairs({ "ResolveConfig", "highlight", "blizzard", "refreshes", "EnsureCooldownWidthObservers",
        "textures", "trinkets", "focusKick", "kickReady" }) do
        assert(counts[key] == 1, "SpawnAll step must run once: " .. key .. " (" .. tostring(counts[key]) .. ")")
    end
end
AssertSpawnStepsOnce()
assert(counts.ApplyOne == #UF.unitOrder, "SpawnAll omitted managed units")
for _, unit in ipairs(UF.unitOrder) do assert(units[unit] == 1, "unit spawn must run once: " .. unit) end
assert(next(UF.pendingApply) == nil, "spawn left pending unit applies")
local db = env.MSUF_DB
if not world.client.isClassic then
    db.target.anchorFrameName = "EssentialCooldownViewer"
    UF.Config.Refresh()
    Factory.Apply("target")
    assert(Factory.RefreshExternalAnchor("EssentialCooldownViewer"), "external anchor skipped the spawned unit frames: "
        .. tostring(UF.frames.target and UF.frames.target.MSUFSpec and UF.frames.target.MSUFSpec.anchorFrameName)
        .. " supported=" .. tostring(env.MSUF_CooldownAnchorSupported()) .. " sameDB=" .. tostring(db == UF.Config.GetDB()))
end
world:FireEvent("PLAYER_REGEN_ENABLED")
UF.Initialize()
UF.ApplyDirty()
assert(completed == 1, "later flush/initialize repeated deferred SpawnAll")
AssertSpawnStepsOnce()
print("uf_combat_login_spawn_smoke: ok (" .. flavor .. ")")
