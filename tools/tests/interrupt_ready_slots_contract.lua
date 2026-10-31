-- Per-interrupt consumer contract, with the real core and strict native sinks.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/castbar_secret_world.lua")
local world = World.New(root, { flavor = "Mainline", playerClass = "PALADIN" })
local ns, env = world.core, world.env
ns.Require("MSUF_EnsureDB", "interrupt slots contract")(true)
local general = env.MSUF_DB.general
for _, key in ipairs({ "kickReadyShowTarget", "kickReadyShowFocus", "kickReadyShowBoss", "kickReadyShowArena",
    "enableFocusKickIcon", "kickReadyShowNameplates" }) do general[key] = false end
ns.Castbars.Config.Invalidate()
local engine = ns.KickReady
assert(engine and engine.Spell and engine.SelectSlotColor,
    "host does not expose per-interrupt identity/readiness")
assert(engine.version == 2, "the per-interrupt consumer contract is not versioned")
local owner, changes = {}, {}
assert(engine.Register(owner, function(reason) changes[#changes + 1] = reason end, true))
assert(engine.SlotCount() == 2 and engine.Spell(1) == 96231 and engine.Spell(2) == 31935,
    "primary and secondary identities must come from the resolved provider slots")
local unavailableIndexColor = env.CreateColor(0, 0, 0, 0)
for _, index in ipairs({ 0, 3 }) do
    assert(engine.Spell(index) == nil, "out-of-range slot exposed an identity")
    assert(engine.SelectSlotColor(index, env.CreateColor(1, 1, 1, 1), unavailableIndexColor) == unavailableIndexColor,
        "out-of-range slot did not fail closed")
end
local frame = assert(world:Named("MSUF_InterruptReady_EventFrame"))
assert(frame.events.PLAYER_ENTERING_WORLD, "independent consumer did not start the disabled engine")
local ready, unavailable = env.CreateColor(0, 1, 0, 1), env.CreateColor(1, 0, 0, 0)
world.secretCooldowns = false
world.cooldowns[96231] = { startTime = world.clock, total = 20 }
world:Fire(frame, "SPELL_UPDATE_COOLDOWN", 96231)
assert(engine.SelectSlotColor(1, ready, unavailable) == unavailable
    and engine.SelectSlotColor(2, ready, unavailable) == ready,
    "secondary readiness was incorrectly used for the primary interrupt")
engine.SetActive(owner, true)
assert(frame.events.SPELL_UPDATE_COOLDOWN, "active independent consumer has no cooldown events")
world.cooldowns[31935] = { startTime = world.clock, total = 30 }
world:Fire(frame, "SPELL_UPDATE_COOLDOWN", 31935)
assert(engine.SelectSlotColor(1, ready, unavailable) == unavailable
    and engine.SelectSlotColor(2, ready, unavailable) == unavailable,
    "one slot retained stale readiness")
world.cooldowns[96231] = nil
world:Fire(frame, "SPELL_UPDATE_COOLDOWN", 96231)
world.cooldowns[31935] = nil
world:Fire(frame, "SPELL_UPDATE_COOLDOWN", 31935)
assert(changes[#changes] == "projection", "unchanged aggregate readiness lost its slot-change notification")
assert(engine.SelectSlotColor(1, ready, unavailable) == ready
    and engine.SelectSlotColor(2, ready, unavailable) == ready, "slot readiness did not refresh")
local stop = world.Secrets.Watch(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_InterruptReady_Consumers.lua", { strict = true })
world.secretCooldowns = true
world:Fire(frame, "SPELL_UPDATE_COOLDOWN", 96231)
for i = 1, 2 do
    local color = engine.SelectSlotColor(i, ready, unavailable)
    local _, _, _, alpha = color:GetRGBA()
    frame:SetAlpha(alpha)
end
local violations = stop()
assert(#violations == 0, table.concat(violations, "\n"))
engine.SetActive(owner, false)
engine.Unregister(owner)
assert(not engine.HasConsumers() and not frame.events.SPELL_UPDATE_COOLDOWN and not frame.events.PLAYER_ENTERING_WORLD,
    "last independent consumer retained engine events")
-- A v1-style registration still obeys the nameplate owner switch.
engine.Register(owner, function() end)
assert(not frame.events.PLAYER_ENTERING_WORLD, "legacy consumer bypassed the nameplate switch")
engine.Unregister(owner)
-- A previous empty spell set can stay cached while every engine owner is off.
env.C_SpellBook.IsSpellKnownOrInSpellBook = function() return false end
engine.Register(owner, function() end, true)
assert(engine.SlotCount() == 0, "cold no-interrupt fixture did not resolve empty")
engine.Unregister(owner)
env.C_SpellBook.IsSpellKnownOrInSpellBook = function(spell) return spell == 96231 or spell == 31935 end
assert(engine.SlotCount() == 0, "fixture did not retain the disabled empty cache")
engine.Register(owner, function() end, true)
assert(engine.SlotCount() == 2 and engine.Spell(2) == 31935,
    "independent registration did not refresh an unsubscribed learned spell set")
engine.Unregister(owner)
print("PASS interrupt slots: identity, independent lifecycle, primary/secondary, projection, strict secrets, legacy opt-in")
