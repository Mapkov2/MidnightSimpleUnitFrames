-- probe_a2_player_channel_kick.lua <repoRoot> [flavor]
-- A kicked channel ends with UNIT_SPELLCAST_CHANNEL_STOP carrying interruptedBy
-- (Blizzard CastingBarMixin:OnEvent: complete = interruptedBy == nil). The
-- target driver shows interrupt feedback for it; the player castbar does not.
local root = arg[1]
local World = assert(loadfile(root .. "/tools/tests/castbar_world.lua"))()
local world = World.New(root, "timer", { flavor = arg[2] or "Mists" })
_G.INTERRUPTED = "Interrupted"
_G.MSUF_SetTextIfChanged = function(fs, text) if fs then fs.text = text end end
_G.GetNetStats = function() return 0, 0, 40, 40 end
_G.MSUF_DB.player = {}

-- 1. The target driver (reference behaviour of the same repo).
local bar = world:Driver("target")
world:StartChannel("target", "Mind Flay", 3, 31)
world:Fire(bar, "UNIT_SPELLCAST_CHANNEL_START", "MF-guid", 15407, 31)
world:Advance(0.5)
world.channeling.target = nil
world:Fire(bar, "UNIT_SPELLCAST_CHANNEL_STOP", "MF-guid", 15407, "Creature-0-1-2-3-4-5", 31)
print("target driver after kicked CHANNEL_STOP: text=" .. tostring(bar.castText.text)
    .. " interrupted=" .. tostring(bar.interrupted) .. " shown=" .. tostring(bar.shown))

-- 2. The player castbar, real runtime file.
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_PlayerCastbarRuntime.lua"))(
    "MidnightSimpleUnitFrames", world.ns)
_G.MSUF_IsCastbarEnabledForUnit = function() return true end
local player = world.NewWidget("StatusBar", "MSUF_PlayerProbeCastBar")
player.unit = "player"
player.statusBar = world.NewWidget("StatusBar")
player.castText = world.NewWidget("FontString")
player.timeText = world.NewWidget("FontString")
local OnEvent = _G.MSUF_PlayerCastbar_OnEvent

world:StartChannel("player", "Mind Flay", 3, 41)
OnEvent(player, "UNIT_SPELLCAST_CHANNEL_START", "player", "PMF-guid", 15407, 41)
print("player after CHANNEL_START: text=" .. tostring(player.castText.text) .. " shown=" .. tostring(player.shown)
    .. " castActive=" .. tostring(player.MSUF_castActive))
world:Advance(0.5)
-- The mob kicks the player's channel: CHANNEL_STOP(unit, castGUID, spellID, interruptedBy, castBarID).
world.channeling.player = nil
OnEvent(player, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "PMF-guid", 15407, "Creature-0-1-2-3-4-5", 41)
world:Advance(0.05)
print("player after kicked CHANNEL_STOP (+0.05 s): text=" .. tostring(player.castText.text)
    .. " shown=" .. tostring(player.shown) .. " interruptFeedbackEndTime=" .. tostring(player.interruptFeedbackEndTime))
print("expected: player shows 'Interrupted' like the target driver; observed above")

assert(player.castText.text == "Interrupted", "player kicked channel lost interrupt feedback")

-- The active empower branch must resolve the local feedback helper too.
player.isEmpower = true
player.castText.text = "Fire Breath"
OnEvent(player, "UNIT_SPELLCAST_INTERRUPTED", "player", "empower-guid", 357208, nil, 42)
assert(player.castText.text == "Interrupted" and player.interruptFeedbackEndTime,
    "active empowered cast lost interruption feedback")
