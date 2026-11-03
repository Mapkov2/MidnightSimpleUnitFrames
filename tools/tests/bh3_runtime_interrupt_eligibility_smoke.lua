-- interrupt_ready_consumer_smoke.lua <repoRoot>
--
-- MSUF.KickReady, the interrupt-ready engine's consumer API (handed to the
-- MSUF Suite's nameplates by MSUF_HostAPI.GetKickReady()). With every MSUF
-- castbar indicator off, a registered consumer keeps the engine running; an
-- active one keeps the cooldown event and the native wake frames armed and is
-- told about every readiness change, a moved cooldown end, and a wake. MSUF's
-- own readiness exports keep their castbar-gated answers. Notifications run
-- after the engine's own state is settled.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")

local REBUKE, AVENGERS_SHIELD = 96231, 31935
local classToken, knownSpells, petSpells, usable, power, reads = "PRIEST", {}, {}, true, false, 0
local frameStamp = 100
local commandOverride, overrideReads, specID = 119898, 0, 66
local events = {}
local eventHandler
local wakeFrames, wakeSets = {}, 0

_G.MSUF_DB = {
    general = {
        kickReadyShowTarget = false, kickReadyShowFocus = false,
        kickReadyShowBoss = false, kickReadyShowArena = false,
        enableFocusKickIcon = false, kickReadyStyle = "border",
    },
}
_G.MSUF_EnsureDB = function() end
_G.UnitClass = function() return classToken, classToken end
_G.C_SpecializationInfo = {
    GetSpecialization = function() return 2 end,
    GetSpecializationInfo = function() return specID end,
}
_G.Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 } }
_G.C_SpellBook = { IsSpellKnown = function(spellID, bank)
    reads = reads + 1
    return (bank == 1 and petSpells or knownSpells)[spellID] == true
end }
_G.GetTime = function() return frameStamp end
_G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
_G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
_G.C_CurveUtil = {
    EvaluateColorFromBoolean = function(value, ifTrue, ifFalse) return value.value and ifTrue or ifFalse end,
    EvaluateColorValueFromBoolean = function(value, ifTrue, ifFalse) return value.value and ifTrue or ifFalse end,
}
-- The castbar utilities schedule their own next-frame refresh at load.
_G.C_Timer = { After = function() end }

-- One cooldown object per interrupt; remaining is a number or a secret.
local function Cooldown(remaining, endTime)
    local cooldown = { remaining = remaining, endTime = endTime }
    function cooldown.GetRemainingDuration() return cooldown.remaining end
    function cooldown.IsZero() return cooldown.zero end
    function cooldown.GetEndTime() return cooldown.endTime end
    return cooldown
end
local cooldowns = { [REBUKE] = Cooldown(5, 105), [AVENGERS_SHIELD] = Cooldown(8, 108) }
_G.C_Spell = {
    GetOverrideSpell = function(spellID)
        assert(spellID == 119898, "only Command Demon should be resolved")
        overrideReads = overrideReads + 1
        return commandOverride
    end,
    GetSpellCooldownDuration = function(spellID, ignoreGCD)
        assert(ignoreGCD == true)
        return cooldowns[spellID] or Cooldown(0, 0)
    end,
}

_G.CreateFrame = function(frameType)
    if frameType == "Cooldown" then
        local wake = { Show = function() end, SetSize = function() end, SetAlpha = function() end,
            SetDrawSwipe = function() end, SetDrawEdge = function() end, SetDrawBling = function() end,
            SetHideCountdownNumbers = function() end, Clear = function() end }
        function wake.SetCooldownFromDurationObject() wakeSets = wakeSets + 1 end
        function wake.SetScript(_, script, callback)
            if script == "OnCooldownDone" then wake.done = callback end
        end
        wakeFrames[#wakeFrames + 1] = wake
        return wake
    end
    return {
        RegisterEvent = function(_, event) events[event] = true end,
        UnregisterEvent = function(_, event) events[event] = nil end,
        UnregisterAllEvents = function() for event in pairs(events) do events[event] = nil end end,
        SetScript = function(_, script, callback) if script == "OnEvent" then eventHandler = callback end end,
    }
end

-- ExportPublic as Kernel/MSUF_Bootstrap.lua: the global and MSUF.Public.
local ns = { Public = {}, Client = { IsForever = arg[2] == "Forever", IsMists = arg[2] == "Mists", IsVanilla = arg[2] == "Vanilla", IsTBC = arg[2] == "TBC" } }
ns.Client.IsClassic = ns.Client.IsVanilla or ns.Client.IsTBC or ns.Client.IsMists
ns.ExportPublic = function(name, value)
    _G[name] = value
    ns.Public[(name:gsub("^MSUF_", ""))] = value
    return value
end
for key, value in pairs({
    Scheduler = { ScheduleAfter = function() error("native wakes must not fall back to the scheduler") end },
    Util = { InCombat = function() return false end },
}) do ns[key] = value end
-- Castbars/MSUF_Castbars_Core.lua (not loaded here) owns the castbar texture.
ns.Public.GetCastbarTexture = function() return "Interface\\MSUF\\Lucent" end
local reports = {}
_G.geterrorhandler = function() return function(message) reports[#reports + 1] = message end end
_G.MSUF_ApplyCastbarOutline = function() end
-- The real boundary: consumer callbacks run through MSUF.RunHostAPIStep.
for _, file in ipairs({ "Kernel/MSUF_Boundary.lua", "Runtime/MSUF_HostAPI.lua", "Castbars/MSUF_CastbarUtils.lua",
    "Castbars/MSUF_InterruptReady.lua" }) do
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. file))("MidnightSimpleUnitFrames", ns)
end
_G.C_Timer.After = function() error("native wakes must not fall back to a Lua timer") end


_G.C_Spell.IsSpellUsable = function() return usable, power end
local K = ns.KickReady
K.Register("audit", function() end)
_G.MSUF_DB.general.kickReadyShowNameplates = true
_G.MSUF_KickReady_RefreshAll()
assert(K.SlotCount() == 0, "unlearned Silence appears ready")
assert(events.SPELLS_CHANGED, "learned spell events are not subscribed")
knownSpells[15487] = true; eventHandler(nil, "SPELLS_CHANGED")
assert(K.SlotCount() == 1, "learned Silence missing")
knownSpells[15487] = nil; eventHandler(nil, "SPELLS_CHANGED")
assert(K.SlotCount() == 0, "removed talent retained")
local before = reads
for i = 1, 1000 do K.SlotCount() end
assert(reads == before, "absent interrupt rescans spellbook in steady state")
classToken, specID = "WARLOCK", 267; _G.MSUF_KickReady_RefreshAll()
assert(events.UNIT_PET, "pet replacement lifecycle missing")
knownSpells[19647] = true; eventHandler(nil, "SPELLS_CHANGED")
assert(K.SlotCount() == 0, "player knowledge admits absent pet spell")
petSpells[19647] = true; eventHandler(nil, "UNIT_PET", "player")
assert(K.SlotCount() == 1, "current pet Spell Lock missing")
petSpells[19647] = nil; eventHandler(nil, "UNIT_PET", "player")
assert(K.SlotCount() == 0, "dismissed pet retained")
-- Grimoire of Sacrifice grants a player override, not a pet-book spell.
-- The exact known override is authoritative even if the spellbook lists an
-- inactive variant; an empty pet book alone must never admit an interrupt.
local SACRIFICE_LOCK, PET_LOCK = 132409, 19647
local retail = not ns.Client.IsClassic and not ns.Client.IsForever
knownSpells[119898] = true
cooldowns[SACRIFICE_LOCK] = Cooldown(0, 0)
cooldowns[PET_LOCK] = Cooldown(0, 0)
commandOverride = SACRIFICE_LOCK
-- Pet removal may precede the override change; SPELLS_CHANGED must recover.
eventHandler(nil, "SPELLS_CHANGED")
if retail then
    assert(K.SlotCount() == 1, "sacrificed Felhunter's player Spell Lock is missing")
    assert(K.Cooldown(1) == cooldowns[SACRIFICE_LOCK], "sacrifice uses the pet cooldown")
    local function CheckColor(red, green, message)
        local r, g, b = K.RGBA(false)
        assert(r == red and g == green and b == 0, message)
    end
    K.SetActive("audit", true)
    CheckColor(0, 1, "ready sacrifice interrupt is not green")
    local bookBefore, overrideBefore = reads, overrideReads
    for i = 1, 1000 do K.SlotCount(); K.RGBA(false) end
    assert(reads == bookBefore and overrideReads == overrideBefore, "warm paints re-resolve the interrupt")
    frameStamp = frameStamp + 1
    cooldowns[SACRIFICE_LOCK].remaining, cooldowns[SACRIFICE_LOCK].endTime = 24, frameStamp + 24
    eventHandler(nil, "SPELL_UPDATE_COOLDOWN", SACRIFICE_LOCK, 119898)
    CheckColor(1, 0, "sacrifice cooldown did not turn red")
    assert(wakeSets > 0 and wakeFrames[1].done, "sacrifice cooldown wake missing")
    frameStamp = frameStamp + 24
    cooldowns[SACRIFICE_LOCK].remaining = 0
    wakeFrames[1].done()
    CheckColor(0, 1, "sacrifice cooldown wake did not return to green")
    commandOverride = 132411 -- a non-interrupt demon ability
    knownSpells[SACRIFICE_LOCK] = true -- stale/book membership cannot override current Command Demon
    eventHandler(nil, "UNIT_PET", "target")
    assert(K.SlotCount() == 1, "another unit's pet change affected the player's interrupt")
    eventHandler(nil, "SPELLS_CHANGED")
    assert(K.SlotCount() == 0, "a different sacrificed demon admitted Spell Lock")
    commandOverride, petSpells[PET_LOCK] = 119910, true
    eventHandler(nil, "UNIT_PET", "player")
    assert(K.SlotCount() == 1 and K.Cooldown(1) == cooldowns[PET_LOCK], "resummoned Felhunter kept sacrifice cooldown")
    commandOverride, petSpells[PET_LOCK] = 119898, nil
    eventHandler(nil, "UNIT_PET", "player")
    assert(K.SlotCount() == 0, "dismissed Felhunter retained sacrifice interrupt")
    specID, commandOverride = 265, SACRIFICE_LOCK
    eventHandler(nil, "PLAYER_SPECIALIZATION_CHANGED", "player")
    assert(K.SlotCount() == 1, "Affliction sacrifice interrupt missing")
    commandOverride = { secret = true }
    eventHandler(nil, "SPELLS_CHANGED")
    assert(K.SlotCount() == 0, "unreadable override admitted an interrupt")
    local getOverride = _G.C_Spell.GetOverrideSpell
    _G.C_Spell.GetOverrideSpell = nil
    eventHandler(nil, "SPELLS_CHANGED")
    assert(K.SlotCount() == 1, "learned sacrifice spell fallback missing without override API")
    knownSpells[SACRIFICE_LOCK] = nil
    _G.C_SpellBook.IsSpellKnownOrInSpellBook = function() return true end
    eventHandler(nil, "SPELLS_CHANGED")
    assert(K.SlotCount() == 0, "fallback admitted an unlearned spellbook entry")
    _G.C_Spell.GetOverrideSpell = getOverride
    _G.C_SpellBook.IsSpellKnownOrInSpellBook = nil
    K.SetActive("audit", false)
else
    assert(K.SlotCount() == 0 and overrideReads == 0, "Retail sacrifice resolution leaked onto another client")
end
commandOverride = 119898
classToken = "DRUID"; knownSpells[16979], knownSpells[106839] = true, true
_G.C_SpecializationInfo.GetSpecializationInfo = function() return 103 end
usable, power = false, false; _G.MSUF_KickReady_RefreshAll()
assert(K.SlotCount() == 0, "out-of-form interrupt admitted")
assert(events.UPDATE_SHAPESHIFT_FORM, "form lifecycle missing")
usable = true; eventHandler(nil, "UPDATE_SHAPESHIFT_FORM")
assert(K.SlotCount() == 1, "available form interrupt missing")
usable, power = false, true; eventHandler(nil, "UPDATE_SHAPESHIFT_FORM")
assert(K.SlotCount() == 1, "low resource incorrectly removed learned interrupt")
print("PASS interrupt eligibility " .. tostring(arg[2] or "Mainline") .. "; steady-state spellbook reads=0")
