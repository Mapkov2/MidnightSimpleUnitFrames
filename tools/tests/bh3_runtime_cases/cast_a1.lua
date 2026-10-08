-- probe_a1_interruptible.lua <repoRoot>
-- Target castbar: a NOT_INTERRUPTIBLE event on one target's cast leaks into the
-- next target's cast after PLAYER_TARGET_CHANGED (no START on the new unit).
local root = arg[1]
local World = assert(loadfile(root .. "/tools/tests/castbar_world.lua"))()
local world = World.New(root, "timer", { flavor = arg[2] or "Mists" })
_G.INTERRUPTED = "Interrupted"
local general = _G.MSUF_DB.general
general.castbarInterruptibleR, general.castbarInterruptibleG, general.castbarInterruptibleB = 0, 1, 0
general.castbarNonInterruptibleR, general.castbarNonInterruptibleG, general.castbarNonInterruptibleB = 1, 0, 0

local bar = world:Driver("target")
local function Color()
    local sb = bar.statusBar
    return string.format("%s,%s,%s", tostring(sb._msufLastColorR), tostring(sb._msufLastColorG), tostring(sb._msufLastColorB))
end

-- Target A: a cast that becomes uninterruptible mid-cast.
world:StartCast("target", "Shadow Bolt", 3, 11)
world:Fire(bar, "UNIT_SPELLCAST_START", "Shadow Bolt-guid", 133, 11)
print("A start           color", Color(), "isNotInterruptible", tostring(bar.isNotInterruptible))
world:Advance(0.2)
world:Fire(bar, "UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
print("A NOT_INTERRUPT   color", Color(), "isNotInterruptible", tostring(bar.isNotInterruptible))
world:Advance(0.3)

-- Tab to target B, already mid-cast with an interruptible cast (the API says
-- notInterruptible = false). No START fires for "target".
world.casting.target = nil
world:StartCast("target", "Frostbolt", 2.5, 12)
world:Fire(bar, "PLAYER_TARGET_CHANGED")
local engineState = _G.MSUF_GetCastbarEngine():GetState("target")
print("B after swap      color", Color(), "isNotInterruptible", tostring(bar.isNotInterruptible),
    "engine state.isNotInterruptible", tostring(engineState.isNotInterruptible),
    "api raw", tostring(engineState.apiNotInterruptibleRaw), "shown", tostring(bar.shown),
    "text", tostring(bar.castText.text))
print("expected B color 0,1,0 (interruptible); observed " .. Color())

assert(bar.isNotInterruptible == false and Color() == "0,1,0", "unit swap retained old interruptibility")
