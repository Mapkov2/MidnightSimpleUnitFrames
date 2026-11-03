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

-- The real client graphs must distinguish sacrificed Spell Lock from an absent
-- pet and from the inactive variants that can remain listed in the spellbook.
local function CheckSacrifice(flavor)
    local w = World.New(root, { flavor = flavor, playerClass = "WARLOCK" })
    local core, e = w.core, w.env
    core.Require("MSUF_EnsureDB", "sacrifice contract")(true)
    local g = e.MSUF_DB.general
    for _, key in ipairs({ "kickReadyShowTarget", "kickReadyShowFocus", "kickReadyShowBoss", "kickReadyShowArena",
        "enableFocusKickIcon", "kickReadyShowNameplates" }) do g[key] = false end
    core.Castbars.Config.Invalidate()
    local spec, override, pet, learned, reads = 267, 119910, true, false, 0
    e.Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
    e.C_SpecializationInfo.GetSpecializationInfo = function() return spec end
    e.C_SpellBook.IsSpellKnown = function(id, bank)
        reads = reads + 1
        if bank == 1 then return id == 19647 and pet end
        return id == 119898 or (id == 132409 and learned)
    end
    e.C_SpellBook.IsSpellKnownOrInSpellBook = function() return true end
    e.C_Spell.GetOverrideSpell = function(id)
        assert(id == 119898, "unexpected override query")
        reads = reads + 1
        return override
    end
    w.secretCooldowns = false
    local k, token = core.KickReady, {}
    k.Register(token, function() end, true)
    local events = assert(w:Named("MSUF_InterruptReady_EventFrame"))
    local green, red = e.CreateColor(0, 1, 0, 1), e.CreateColor(1, 0, 0, 1)
    assert(k.SlotCount() == 1 and k.Spell(1) == 19647, flavor .. ": Felhunter missing")
    pet, override = false, 119898
    w:Fire(events, "UNIT_PET", "player")
    assert(k.SlotCount() == 0, flavor .. ": dismissed pet retained")
    override = 132409
    w:Fire(events, "SPELLS_CHANGED")
    if flavor ~= "Mainline" then
        assert(k.SlotCount() == 0, flavor .. ": Retail sacrifice leaked to another client")
        k.Unregister(token)
        return
    end
    assert(k.SlotCount() == 1 and k.Spell(1) == 132409, "sacrificed Felhunter's player Spell Lock is missing")
    k.SetActive(token, true)
    assert(k.SelectSlotColor(1, green, red) == green, "ready sacrifice interrupt is red")
    local before = reads
    for i = 1, 100 do k.Spell(1); k.SelectSlotColor(1, green, red) end
    assert(reads == before, "warm sacrifice paints re-query spell availability")
    w.cooldowns[132409] = { startTime = w.clock, total = 24 }
    w:Fire(events, "SPELL_UPDATE_COOLDOWN", 132409, 119898)
    assert(k.SelectSlotColor(1, green, red) == red, "sacrifice cooldown is not red")
    w.clock = w.clock + 25
    local completions = 0
    for wake in pairs(w.cooldownFrames) do
        if wake.cooldownArmed and w.clock >= wake.cooldownEnd then
            wake.cooldownArmed = false
            wake.scripts.OnCooldownDone(wake)
            completions = completions + 1
        end
    end
    assert(completions > 0, "sacrifice cooldown completion was not armed")
    assert(k.SelectSlotColor(1, green, red) == green, "sacrifice cooldown completion stayed red")
    override, learned = 132411, true
    w:Fire(events, "UNIT_PET", "target")
    assert(k.Spell(1) == 132409, "another unit's pet changed the provider")
    w:Fire(events, "SPELLS_CHANGED")
    assert(k.SlotCount() == 0, "another sacrificed demon admitted Spell Lock")
    pet, override = true, 119910
    w.cooldowns[19647] = { startTime = w.clock, total = 24 }
    w:Fire(events, "UNIT_PET", "player")
    assert(k.Spell(1) == 19647 and k.SelectSlotColor(1, green, red) == red, "resummon kept player cooldown")
    pet, override, spec = false, 132409, 265
    w:Fire(events, "PLAYER_SPECIALIZATION_CHANGED", "player")
    assert(k.Spell(1) == 132409 and k.SelectSlotColor(1, green, red) == green, "Affliction sacrifice missing")
    local stop = w.Secrets.Watch(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_InterruptReady.lua", { strict = true })
    override = w.Secrets.New("number")
    w:Fire(events, "SPELLS_CHANGED")
    assert(k.SlotCount() == 0, "unreadable override admitted a spell")
    local violations = stop()
    assert(#violations == 0, table.concat(violations, "\n"))
    e.C_Spell.GetOverrideSpell = nil
    w:Fire(events, "SPELLS_CHANGED")
    assert(k.Spell(1) == 132409, "learned sacrifice fallback missing")
    learned = false
    w:Fire(events, "SPELLS_CHANGED")
    assert(k.SlotCount() == 0, "unlearned spellbook variant admitted by fallback")
    k.SetActive(token, false)
    k.Unregister(token)
    assert(#w.errors == 0, table.concat(w.errors, "\n"))
end
for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists", "Forever" }) do CheckSacrifice(flavor) end
print("PASS sacrifice interrupt: player/pet identity, cooldown, override, strict secrets and five client graphs")
