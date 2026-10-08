-- probe_a3_empower_kick.lua <repoRoot>
-- Another unit's empowered cast that is kicked ends with
-- UNIT_SPELLCAST_EMPOWER_STOP(unit, castGUID, spellID, complete=false, interruptedBy, castBarID).
-- Blizzard's CastingBarMixin:HandleCastStop treats not complete as an interrupt;
-- the driver normalizes it to a plain STOP and completes the bar.
local root = arg[1]
local World = assert(loadfile(root .. "/tools/tests/castbar_world.lua"))()
local world = World.New(root, "timer", { flavor = "Mainline" })
_G.INTERRUPTED = "Interrupted"
local bar = world:Driver("target")
world:StartChannel("target", "Fire Breath", 3, 51, true)
world:Fire(bar, "UNIT_SPELLCAST_EMPOWER_START", "FB-guid", 357208, 51)
print("after EMPOWER_START: text=" .. tostring(bar.castText.text) .. " castActive=" .. tostring(bar.MSUF_castActive))
world:Advance(0.5)
world.channeling.target = nil
world:Fire(bar, "UNIT_SPELLCAST_EMPOWER_STOP", "FB-guid", 357208, false, "Player-1-00000001", 51)
print("right after kicked EMPOWER_STOP: text=" .. tostring(bar.castText.text) .. " interrupted=" .. tostring(bar.interrupted))
world:Advance(0.5)
print("+0.5 s: text=" .. tostring(bar.castText.text) .. " interrupted=" .. tostring(bar.interrupted)
    .. " shown=" .. tostring(bar.shown) .. " completions=" .. #bar.completedAt)

assert(#bar.completedAt == 0, "interrupted empower completed successfully")
