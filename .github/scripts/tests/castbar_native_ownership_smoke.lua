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

-- Another addon may publish an AceAddon controller under these generic names
-- instead of a frame. MSUF must neither adopt nor hide such foreign objects.
local foreignTarget = { hideCount = 0 }
function foreignTarget:Hide() self.hideCount = self.hideCount + 1 end
local foreignFocus = { hideCount = 0, alphaCount = 0 }
function foreignFocus:Hide() self.hideCount = self.hideCount + 1 end
function foreignFocus:SetAlpha() self.alphaCount = self.alphaCount + 1 end
_G.TargetCastBar = foreignTarget
_G.FocusCastBar = foreignFocus
_G.MSUF_Castbars_ForceHideAll()
assert(foreignTarget.hideCount == 0 and foreignFocus.hideCount == 0,
    "castbar bridge crossed ownership into foreign generic globals")

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

-- Range alpha and UnitFrame disable bridges must apply only to MSUF-owned
-- legacy globals. PlayerCastBars exposes its controller as _G.FocusCastBar.
local registeredElements = {}
ns.UF.frames = {
    focus = {
        MSUFUnitKey = "focus",
        _msufAlphaRangeActive = true,
        _msufAlphaRangeHealthLayer = false,
    },
}
ns.UF.elementOrder = {}
ns.UF.RegisterElement = function(name, element)
    registeredElements[name] = element
end
ns.UFVisuals = {
    Clamp01 = function(value, fallback)
        value = tonumber(value)
        if value == nil then return fallback end
        if value < 0 then return 0 end
        if value > 1 then return 1 end
        return value
    end,
    SetFrameAlpha = function(frame, alpha) frame.alpha = alpha end,
    SetAlphaCached = function(object, alpha)
        object:SetAlpha(alpha)
    end,
}

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Alpha.lua"))("MSUF", ns)
assert(_G.MSUF_UF_ApplyCastbarRangeAlpha("focus", 0.5, true) == false,
    "range alpha adopted a foreign FocusCastBar controller")
assert(foreignFocus.alphaCount == 0, "range alpha mutated a foreign FocusCastBar controller")

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Bridges.lua"))("MSUF", ns)
assert(registeredElements.Castbars, "UnitFrame castbar bridge did not register")
registeredElements.Castbars.Disable({ MSUFUnitKey = "focus" })
assert(foreignFocus.hideCount == 0, "UnitFrame disable hid a foreign FocusCastBar controller")

-- Exact Edit Mode regression: Target applies successfully and the following
-- Focus reanchor ignores PlayerCastBars' non-frame _G.FocusCastBar controller.
local function NewOwnedCastbar()
    local frame = { width = 0, height = 0 }
    function frame:ClearAllPoints() end
    function frame:SetPoint() end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    return frame
end

_G.UIParent = {}
_G.EnsureDB = function() end
_G.MSUF_DB.general.enableTargetCastbar = true
_G.MSUF_DB.general.enableFocusCastbar = true
_G.MSUF_DB.general.castbarTargetDetached = true
_G.MSUF_DB.general.castbarFocusDetached = true
_G.MSUF_DB.general.castbarTargetBarWidth = 175
_G.MSUF_DB.general.castbarTargetBarHeight = 18
_G.MSUF_DB.general.castbarFocusBarWidth = 175
_G.MSUF_DB.general.castbarFocusBarHeight = 18
_G.MSUF_TargetCastbar = NewOwnedCastbar()
_G.MSUF_TargetCastBar = nil
_G.MSUF_FocusCastbar = nil
_G.MSUF_FocusCastBar = nil

assert(loadfile("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarAnchors.lua"))("MSUF", ns)
local targetOK, targetError = pcall(_G.MSUF_ReanchorTargetCastBar)
local focusOK, focusError = pcall(_G.MSUF_ReanchorFocusCastBar)
assert(targetOK, "Edit Mode target reanchor failed: " .. tostring(targetError))
assert(focusOK, "foreign FocusCastBar crashed Edit Mode reanchor: " .. tostring(focusError))
assert(_G.MSUF_TargetCastbar.width == 175 and _G.MSUF_TargetCastbar.height == 18,
    "foreign FocusCastBar prevented the Target castbar apply")
assert(foreignFocus.hideCount == 0 and foreignFocus.alphaCount == 0,
    "Edit Mode reanchor mutated the foreign FocusCastBar controller")

print("castbar native ownership smoke: ok")
