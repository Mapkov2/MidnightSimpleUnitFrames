local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local path = root .. "/MidnightSimpleUnitFrames/Features/Versioning/MSUF_VersionCheck.lua"
local function World(version)
    local events, messages, sent = {}, {}, {}
    local env = setmetatable({ MSUF_DB = { general = {} } }, { __index = _G })
    env._G = env
    env.print = function(message) messages[#messages + 1] = message end
    env.C_Timer = { After = function(_, callback) callback() end }
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(_, payload) sent[#sent + 1] = payload end,
    }
    env.IsInGuild = function() return true end
    env.IsInGroup = function() return false end
    local bus = {}
    function bus:Register(event, _, callback) events[event] = callback end
    function bus:Unregister(event) events[event] = nil end
    local ns = {
        ExportPublic = function() end,
        Translate = function(text) return text end,
        GetAddonVersion = function() return version end,
        MSUF_EventBus = bus,
        MSUF_RegisterModule = function() end,
    }
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    chunk("MidnightSimpleUnitFrames", ns)
    assert(events.PLAYER_LOGIN)()
    local world = { ns = ns, messages = messages, sent = sent }
    function world:Receive(payload) events.CHAT_MSG_ADDON(nil, "MSUF", payload, "GUILD") end
    function world:Broadcast() events.PLAYER_ENTERING_WORLD() end
    return world
end
local function Epoch(label)
    local world = World(label)
    return select(2, world.ns.VersionCheck.GetMyVersion())
end
local oldEpoch = Epoch("7.021")
assert(oldEpoch == 7021000400000, "historical wire epoch changed")
local newEpoch = Epoch("7.0.3-beta1")
assert(newEpoch == 7000003200001, "patch Beta wire epoch changed")
for _, payload in ipairs({ "V:7.021", "V2:" .. oldEpoch .. ":7.021" }) do
    local world = World("7.0.3-beta1")
    world:Receive(payload)
    assert(#world.messages == 0, "7.0.3 Beta recommends the older 7.021 hotfix")
    assert(world.ns.VersionCheck.GetNewestSeen() == "7.0.3-beta1", "older hotfix replaced newest label")
    world:Receive("V:7.0.3-beta2")
    assert(#world.messages == 1 and world.messages[1]:find("7.0.3-beta2", 1, true), "next Beta was suppressed")
end
for _, label in ipairs({ "7.0.2", "7.021" }) do
    local world = World(label)
    world:Receive("V2:" .. newEpoch .. ":7.0.3-beta1")
    assert(#world.messages == 1, label .. " failed to recognize the newer patch Beta")
end
local parent = World("7.0.2")
parent:Receive("V2:" .. oldEpoch .. ":7.021")
local newestLabel, newestEpoch = parent.ns.VersionCheck.GetNewestSeen()
assert(newestLabel == "7.021" and newestEpoch == oldEpoch, "newest API must retain the validated raw epoch")
for _, label in ipairs({ "7.0.3-alpha0", "7.0.3-beta0", "7.0.3-rc0", "7.0.3" }) do
    local world = World("7.021")
    world:Receive("V:" .. label)
    assert(#world.messages == 1, "historical hotfix failed to recognize " .. label)
end
local hotfix = World("7.021")
hotfix:Receive("V:7.0.2")
assert(#hotfix.messages == 0, "historical hotfix recommends its older parent")
hotfix:Receive("V2:1:7.0.3-beta1")
assert(#hotfix.messages == 0, "forged V2 epoch was accepted")
local remapped = World("7.0.2")
remapped:Receive("V2:" .. (Epoch("7.0.2") + 99999) .. ":7.021")
assert(#remapped.messages == 0, "local sort key was accepted as a wire epoch")
local stable = World("7.0.3")
stable:Receive("V:7.0.3-beta99")
assert(#stable.messages == 0, "stable recommends a prerelease")
local legacy = World("6.511")
legacy:Receive("V:6.50")
assert(#legacy.messages == 0, "legacy decimal ordering changed")
legacy:Receive("V:6.52")
assert(#legacy.messages == 1, "newer legacy decimal version was ignored")
local wire = World("7.0.3-beta1")
wire:Broadcast()
assert(wire.sent[1] == "V2:" .. newEpoch .. ":7.0.3-beta1", "broadcast wire epoch changed")
assert(wire.sent[2] == "V:7.00.3-beta1", "legacy broadcast changed")
local oldWire = World("7.021")
oldWire:Broadcast()
assert(oldWire.sent[1] == "V2:" .. oldEpoch .. ":7.021" and oldWire.sent[2] == "V:7.021", "historical broadcasts changed")
print("version_patch_order_smoke: historical hotfix, patch Beta/stable, raw V2 validation and broadcasts passed")
