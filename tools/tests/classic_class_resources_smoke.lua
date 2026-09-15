local repo = assert(arg[1], "repo root required")

WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 2
WOW_PROJECT_MISTS_CLASSIC = 5
WOW_PROJECT_ID = WOW_PROJECT_BURNING_CRUSADE_CLASSIC

C_AddOns = {
    GetAddOnMetadata = function(_, key)
        return key == "X-MSUF-Client" and "TBC" or nil
    end,
}
function GetBuildInfo() return "test", "test", "test", 20506 end
function UnitClass() return "Rogue", "ROGUE" end
function UnitPower() return 0 end
function GetComboPoints() return 0 end

local combat = false
function InCombatLockdown() return combat end
local deferredDriver
function CreateFrame()
    deferredDriver = {
        SetScript = function(self, _, handler) self.handler = handler end,
        RegisterEvent = function(self, event) self.event = event end,
        UnregisterEvent = function(self, event) if self.event == event then self.event = nil end end,
    }
    return deferredDriver
end

local hookCount = 0
local onShow
ComboFrame = {
    shown = true,
    HookScript = function(_, script, callback)
        assert(script == "OnShow", "unexpected script hook")
        hookCount = hookCount + 1
        onShow = callback
    end,
    IsShown = function(self) return self.shown end,
    IsProtected = function() return true end,
    Hide = function(self) self.shown = false end,
    Show = function(self)
        self.shown = true
        if onShow then onShow(self) end
    end,
}

local updateCount = 0
function ComboFrame_UpdateMax(frame)
    updateCount = updateCount + 1
    frame:Show()
end

local addonName = "MidnightSimpleUnitFrames"
local namespace = {}
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Shared/Initialize.lua"))(addonName, namespace)
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Classic/BlizzardFrames.lua"))(addonName, namespace)
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Constants.lua"))(addonName, namespace)
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/TBC/ClassPower.lua"))(addonName, namespace)

local setter = assert(namespace.Compat.SetBlizzardClassResourcesSuppressed)
assert(setter(true) == true, "suppression did not find ComboFrame")
assert(ComboFrame.shown == false, "visible ComboFrame was not hidden")
assert(hookCount == 1, "ComboFrame OnShow hook count mismatch")

ComboFrame:Show()
assert(ComboFrame.shown == false, "Blizzard re-show escaped suppression")

setter(true)
assert(hookCount == 1, "suppression installed a duplicate hook")

setter(false)
assert(updateCount == 1, "Blizzard restore path did not refresh ComboFrame")
assert(ComboFrame.shown == true, "Blizzard restore result was suppressed")

setter(false)
assert(updateCount == 1, "unchanged restore state refreshed ComboFrame again")

combat = true
setter(true)
assert(ComboFrame.shown == true, "protected ComboFrame was changed in combat")
assert(deferredDriver and deferredDriver.event == "PLAYER_REGEN_ENABLED",
    "protected ComboFrame suppression was not deferred")
setter(false)
assert(ComboFrame.shown == true, "protected ComboFrame restore was changed in combat")
combat = false
deferredDriver.handler(deferredDriver, "PLAYER_REGEN_ENABLED")
assert(updateCount == 2 and ComboFrame.shown == true,
    "deferred ComboFrame restore did not reconcile after combat")

--- Mists: RuneFrame and the other class bars inherit
--- PlayerFrameBottomManagedFrameTemplate. They are not protected, but their
--- OnShow/OnHide run layoutParent:Layout(), which re-anchors the secure PetFrame,
--- so addon code must not Show/Hide them in combat.
combat = false
function UnitClass() return "Death Knight", "DEATHKNIGHT" end

local runeOnShow
local runeCombatToggles = 0
RuneFrame = {
    shown = true,
    alpha = 1,
    layoutParent = {},
    HookScript = function(_, script, callback)
        assert(script == "OnShow", "unexpected RuneFrame script hook")
        runeOnShow = callback
    end,
    IsProtected = function() return false end,
    IsShown = function(self) return self.shown end,
    SetAlpha = function(self, alpha) self.alpha = alpha end,
    GetAlpha = function(self) return self.alpha end,
    Hide = function(self)
        if combat then runeCombatToggles = runeCombatToggles + 1 end
        self.shown = false
    end,
    Show = function(self)
        if combat then runeCombatToggles = runeCombatToggles + 1 end
        self.shown = true
        if runeOnShow then runeOnShow(self) end
    end,
}

assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Mists/ClassPower.lua"))(addonName, namespace)

assert(setter(true) == true, "suppression did not find RuneFrame")
assert(RuneFrame.shown == false, "visible RuneFrame was not hidden out of combat")

combat = true
RuneFrame:Show()
assert(RuneFrame.shown == true and RuneFrame.alpha == 0 and runeCombatToggles == 1,
    "managed RuneFrame was hidden from addon code in combat instead of muted")
assert(deferredDriver.event == "PLAYER_REGEN_ENABLED",
    "managed RuneFrame suppression was not deferred")

combat = false
deferredDriver.handler(deferredDriver, "PLAYER_REGEN_ENABLED")
assert(RuneFrame.shown == false and RuneFrame.alpha == 1,
    "deferred RuneFrame suppression did not reconcile after combat")

combat = true
setter(false)
assert(RuneFrame.shown == false and runeCombatToggles == 1,
    "managed RuneFrame restore toggled visibility in combat")
combat = false
deferredDriver.handler(deferredDriver, "PLAYER_REGEN_ENABLED")
assert(RuneFrame.shown == true, "deferred RuneFrame restore did not reconcile after combat")

combat = true
setter(true)
assert(RuneFrame.shown == true and RuneFrame.alpha == 0 and runeCombatToggles == 1,
    "in-combat RuneFrame suppression was not alpha-only")
setter(false)
assert(RuneFrame.shown == true and RuneFrame.alpha == 1 and runeCombatToggles == 1,
    "in-combat RuneFrame restore did not unmute")
combat = false
deferredDriver.handler(deferredDriver, "PLAYER_REGEN_ENABLED")
assert(RuneFrame.shown == true and RuneFrame.alpha == 1,
    "RuneFrame did not stay visible after the in-combat suppress/restore round trip")

--- Record-once: a second mute in the same combat (setter plus Blizzard OnShow)
--- must keep the original alpha, not the muted 0.
RuneFrame.alpha = 0.5
combat = true
setter(true)
RuneFrame:Show()
setter(true)
assert(RuneFrame.alpha == 0 and runeCombatToggles == 2,
    "repeated in-combat RuneFrame suppression was not alpha-only")
combat = false
deferredDriver.handler(deferredDriver, "PLAYER_REGEN_ENABLED")
assert(RuneFrame.shown == false and RuneFrame.alpha == 0.5,
    "repeated in-combat mute overwrote the recorded RuneFrame alpha")

--- A frame muted mid fade-in (alpha 0) must not be restored invisible.
setter(false)
assert(RuneFrame.shown == true and RuneFrame.alpha == 0.5, "RuneFrame restore after record-once phase failed")
RuneFrame.alpha = 0
combat = true
setter(true)
setter(false)
assert(RuneFrame.alpha == 1, "RuneFrame muted at alpha 0 was restored invisible")
combat = false
deferredDriver.handler(deferredDriver, "PLAYER_REGEN_ENABLED")
assert(RuneFrame.shown == true and RuneFrame.alpha == 1,
    "RuneFrame muted at alpha 0 did not settle visible after combat")

print("classic class-resource ownership smoke passed")
