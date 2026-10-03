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
assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Shared/ClassPower/MSUF_CP_TargetCombo.lua"))(addonName, namespace)
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
--- PlayerFrameBottomManagedFrameTemplate (isManagedFrame, layoutParent). They
--- are not protected, but their OnShow/OnHide run layoutParent:Layout(), which
--- re-anchors the secure PetFrame, so a Show() or Hide() from addon code runs
--- that layout tainted, in combat or out of it. MSUF conceals them (alpha 0,
--- mouse off) and never shows or hides them; Blizzard keeps doing that, and
--- the release gives the alpha and the mouse back. Their fade-in (showAnim,
--- which ends in SetAlpha(1)) is stopped while MSUF owns the bar.
combat = false
function UnitClass() return "Death Knight", "DEATHKNIGHT" end

local runeOnShow
local addonToggles, blizzard = 0, false
local fadeIn = { scripts = {}, stops = 0 }
function fadeIn:HookScript(script, callback) self.scripts[script] = callback end
function fadeIn:GetParent() return RuneFrame end
function fadeIn:Stop() self.stops = self.stops + 1; self.playing = false end
function fadeIn:Play()
    self.playing = true
    if self.scripts.OnPlay then self.scripts.OnPlay(self) end
end
function fadeIn:Finish()
    self.playing = false
    RuneFrame.alpha = 1 -- Blizzard's OnFinished: self:GetParent():SetAlpha(1.0)
    if self.scripts.OnFinished then self.scripts.OnFinished(self) end
end
RuneFrame = {
    shown = true,
    alpha = 1,
    mouse = true,
    isManagedFrame = true,
    layoutParent = {},
    showAnim = fadeIn,
    HookScript = function(_, script, callback)
        assert(script == "OnShow", "unexpected RuneFrame script hook")
        runeOnShow = callback
    end,
    IsProtected = function() return false end,
    IsShown = function(self) return self.shown end,
    SetAlpha = function(self, alpha) self.alpha = alpha end,
    GetAlpha = function(self) return self.alpha end,
    IsMouseEnabled = function(self) return self.mouse end,
    EnableMouse = function(self, on) self.mouse = on and true or false end,
    Hide = function(self)
        if not blizzard then addonToggles = addonToggles + 1 end
        self.shown = false
    end,
    Show = function(self)
        if not blizzard then addonToggles = addonToggles + 1 end
        local wasShown = self.shown
        self.shown = true
        if not wasShown and runeOnShow then runeOnShow(self) end
    end,
}
--- Blizzard's own code shows and hides the bar (spec changes, CheckAndShow).
local function Blizzard(method, ...)
    blizzard = true
    RuneFrame[method](RuneFrame, ...)
    blizzard = false
end

assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Mists/ClassPower.lua"))(addonName, namespace)

for _, inCombat in ipairs({ false, true }) do
    local when = inCombat and "in combat" or "out of combat"
    combat = inCombat
    deferredDriver.event = nil
    assert(setter(true) == true, "suppression did not find RuneFrame")
    assert(RuneFrame.shown == true and RuneFrame.alpha == 0 and RuneFrame.mouse == false,
        "managed RuneFrame was not concealed " .. when)
    assert(addonToggles == 0, "MSUF showed or hid the managed RuneFrame " .. when)
    assert(deferredDriver.event == nil, "the managed RuneFrame concealment was deferred " .. when)

    -- Blizzard hides and shows it again while MSUF owns it.
    Blizzard("Hide")
    RuneFrame.alpha = 1
    Blizzard("Show")
    assert(RuneFrame.shown == true and RuneFrame.alpha == 0, "a Blizzard re-show escaped the concealment " .. when)
    -- Its fade-in is stopped, and a finish that ran anyway re-conceals.
    RuneFrame.alpha = 0
    fadeIn.stops = 0
    fadeIn:Play()
    assert(fadeIn.stops == 1 and not fadeIn.playing and RuneFrame.alpha == 0, "the fade-in ran on a concealed bar " .. when)
    fadeIn:Finish()
    assert(RuneFrame.alpha == 0, "the fade-in's finish revealed the concealed bar " .. when)

    setter(false)
    assert(RuneFrame.shown == true and RuneFrame.alpha == 1 and RuneFrame.mouse == true,
        "the release did not give RuneFrame its alpha and mouse back " .. when)
    assert(addonToggles == 0, "the release showed or hid the managed RuneFrame " .. when)
    fadeIn.stops = 0
    fadeIn:Play()
    assert(fadeIn.stops == 0 and fadeIn.playing, "the fade-in was stopped after the release " .. when)
    fadeIn.playing = false
end
combat = false

--- Record-once: a second conceal (setter plus Blizzard OnShow) keeps the
--- original alpha, not the concealed 0.
RuneFrame.alpha = 0.5
setter(true)
Blizzard("Hide")
Blizzard("Show")
setter(true)
setter(false)
assert(RuneFrame.alpha == 0.5 and addonToggles == 0, "a repeated conceal overwrote the recorded RuneFrame alpha")

--- A bar concealed mid fade-in (alpha 0) is not released invisible.
RuneFrame.alpha = 0
setter(true)
setter(false)
assert(RuneFrame.alpha == 1, "RuneFrame concealed at alpha 0 was released invisible")

--- A bar without mouse stays without mouse.
RuneFrame.mouse = false
setter(true)
setter(false)
assert(RuneFrame.mouse == false and addonToggles == 0, "the release turned the mouse on for a bar that had none")

print("classic class-resource ownership smoke passed")
