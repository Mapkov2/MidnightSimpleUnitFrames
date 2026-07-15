local castEvents = {
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
    "PLAYER_ENTERING_WORLD",
}

local function newFrame(unit, isPet)
    local frame = {
        unit = unit,
        events = {},
        scripts = {},
        shown = false,
        unregisterAllCount = 0,
        hookCount = 0,
    }

    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:RegisterUnitEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents()
        self.unregisterAllCount = self.unregisterAllCount + 1
        self.events = {}
    end
    function frame:SetScript(kind, callback) self.scripts[kind] = callback end
    function frame:HookScript(kind, callback)
        self.hookCount = self.hookCount + 1
        self.scripts["Hook" .. kind] = callback
    end
    function frame:Show()
        self.shown = true
        local callback = self.scripts.HookOnShow
        if callback then callback(self) end
    end
    function frame:Hide() self.shown = false end
    function frame:SetUnit(nextUnit, showTradeSkills, showShield)
        self.unit = nextUnit
        self.showTradeSkills = showTradeSkills
        self.showShield = showShield
        for index = 1, #castEvents do self.events[castEvents[index]] = nil end
        if nextUnit then
            for index = 1, #castEvents do self.events[castEvents[index]] = true end
        end
    end

    frame:SetUnit(unit, false, false)
    if isPet then frame:RegisterEvent("UNIT_PET") end
    return frame
end

local createdFrames = {}
_G.CreateFrame = function()
    local frame = newFrame(nil, false)
    createdFrames[#createdFrames + 1] = frame
    return frame
end

_G.C_Timer = { After = function(_, callback) callback() end }
local inCombat = false
_G.InCombatLockdown = function() return inCombat end

local ns = {
    UF = {},
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

_G.MSUF_DB = {
    general = {
        castbarPlayerBackend = "MSUF",
        enablePlayerCastbar = true,
        castbarTargetBackend = "MSUF",
        enableTargetCastbar = true,
        castbarFocusBackend = "MSUF",
        enableFocusCastbar = true,
        bossCastbarBackend = "MSUF",
        enableBossCastbar = true,
    },
}

_G.PlayerCastingBarFrame = newFrame("player", false)
_G.CastingBarFrame = _G.PlayerCastingBarFrame
_G.PetCastingBarFrame = newFrame("pet", true)

assert(loadfile("MidnightSimpleUnitFrames/Castbars/MSUF_Castbars_Backend.lua"))("MSUF", ns)

do
    local general = { enablePlayerCastbar = false }
    assert(ns.MSUF_CastbarBackend.Resolve("player", general) == "BLIZZARD")
    assert(general.castbarPlayerBackend == nil, "pure backend resolution mutated profile state")
    assert(ns.MSUF_CastbarBackend.Get("player", general) == "BLIZZARD")
    assert(general.castbarPlayerBackend == "BLIZZARD", "compatibility Get did not repair profile state")
end

assert(loadfile("MidnightSimpleUnitFrames/Castbars/MSUF_Castbars_Bridge.lua"))("MSUF", ns)
local bridgeEvents = assert(createdFrames[1])

assert(_G.MSUF_ApplyBlizzardCastbarOwnership() == true)
assert(_G.PlayerCastingBarFrame.unit == "player", "player castbar lost its valid unit token")
assert(next(_G.PlayerCastingBarFrame.events) == nil, "suppressed player retained native event work")
assert(_G.PetCastingBarFrame.events.UNIT_PET == true
    and _G.PetCastingBarFrame.events.PLAYER_ENTERING_WORLD == true,
    "player ownership mutated Blizzard's independent pet event lifecycle")
assert(_G.PlayerCastingBarFrame.unregisterAllCount == 1 and _G.PetCastingBarFrame.unregisterAllCount == 0,
    "player ownership detached the wrong native castbar")
assert(_G.PlayerCastingBarFrame.hookCount == 1 and _G.PetCastingBarFrame.hookCount == 0,
    "player ownership installed a guard on the pet castbar")

-- Regression: the player backend must never manage PetCastingBarFrame. Doing
-- so can race Blizzard's PLAYER_ENTERING_WORLD dispatch and reach
-- UnitChannelInfo(nil) from PetCastingBarMixin:OnEvent.
_G.PetCastingBarFrame:Show()
assert(_G.PetCastingBarFrame.shown == true, "player ownership suppressed the pet castbar")

_G.MSUF_ApplyBlizzardCastbarOwnership()
assert(_G.PlayerCastingBarFrame.unit == "player", "idempotent suppression changed ownership")
assert(_G.PlayerCastingBarFrame.unregisterAllCount == 1 and _G.PetCastingBarFrame.unregisterAllCount == 0,
    "idempotent suppression repeated event detachment")
assert(_G.PlayerCastingBarFrame.hookCount == 1 and _G.PetCastingBarFrame.hookCount == 0,
    "idempotent suppression installed another show guard")

_G.MSUF_SetCastbarBackend("player", "BLIZZARD")
_G.MSUF_Castbars_OnSettingsChanged("test_blizzard")
assert(_G.PlayerCastingBarFrame.unit == "player", "player castbar was not restored")
assert(_G.PetCastingBarFrame.unit == "pet", "pet castbar was not restored")
assert(_G.PlayerCastingBarFrame.events.PLAYER_ENTERING_WORLD == true,
    "Blizzard-owned player cast events were not restored")
assert(_G.PetCastingBarFrame.events.UNIT_PET == true
    and _G.PetCastingBarFrame.events.PLAYER_ENTERING_WORLD == true,
    "player restore mutated Blizzard's pet events")
_G.PetCastingBarFrame:Show()
assert(_G.PetCastingBarFrame.shown == true, "player show guard hid a Blizzard-owned pet bar")

_G.MSUF_SetCastbarBackend("player", "HIDE")
_G.MSUF_Castbars_OnSettingsChanged("test_hide")
assert(bridgeEvents.events.PLAYER_LOGIN and bridgeEvents.events.PLAYER_ENTERING_WORLD
    and bridgeEvents.events.ADDON_LOADED, "HIDE backend lost late native suppression coverage")

_G.MSUF_SetCastbarBackend("player", "BLIZZARD")
inCombat = true
_G.MSUF_Castbars_OnSettingsChanged("test_combat_restore")
assert(_G.PlayerCastingBarFrame.events.PLAYER_ENTERING_WORLD == nil,
    "combat restore mutated native registration")
assert(bridgeEvents.events.PLAYER_REGEN_ENABLED, "combat restore did not queue ownership work")
inCombat = false
assert(bridgeEvents.scripts.OnEvent)
bridgeEvents.scripts.OnEvent(bridgeEvents, "PLAYER_REGEN_ENABLED")
assert(_G.PlayerCastingBarFrame.unit == "player", "queued native ownership did not restore after combat")

_G.MSUF_SetCastbarBackend("player", "MSUF")
_G.MSUF_Castbars_OnSettingsChanged("test_late_player")
local latePlayer = newFrame("player", false)
_G.PlayerCastingBarFrame = latePlayer
_G.CastingBarFrame = latePlayer
bridgeEvents.scripts.OnEvent(bridgeEvents, "ADDON_LOADED", "Blizzard_CastingBarFrame")
assert(latePlayer.unit == "player" and next(latePlayer.events) == nil,
    "late-created player castbar escaped suppression")
assert(_G.PetCastingBarFrame.events.UNIT_PET == true
    and _G.PetCastingBarFrame.events.PLAYER_ENTERING_WORLD == true
    and _G.PetCastingBarFrame.unregisterAllCount == 0,
    "late player suppression crossed into pet ownership")

print("castbar native ownership smoke: ok")
