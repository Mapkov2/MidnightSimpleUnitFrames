local root = assert(arg[1], "repository root argument missing")
local locked = false
local timers = {}
local listener

_G.InCombatLockdown = function() return locked end
_G.issecretvalue = function() return false end
_G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
_G.CreateFrame = function()
    listener = { events = {} }
    function listener:SetScript(_, callback) self.callback = callback end
    function listener:RegisterEvent(event) self.events[event] = true end
    function listener:UnregisterEvent(event) self.events[event] = nil end
    return listener
end

local function NewMouseFrame()
    local frame = { mouse = true, click = false, motion = true, propagate = false, writes = 0 }
    function frame:IsForbidden() return self.forbidden == true end
    function frame:IsMouseEnabled() return self.mouse end
    function frame:IsMouseClickEnabled() return self.click end
    function frame:IsMouseMotionEnabled() return self.motion end
    function frame:GetPropagateMouseClicks() return self.propagate end
    function frame:EnableMouse(value)
        assert(not self:IsForbidden() and not locked, "forbidden EnableMouse")
        self.writes = self.writes + 1
        self.mouse = value
    end
    function frame:SetMouseClickEnabled(value)
        assert(not self:IsForbidden() and not locked, "forbidden SetMouseClickEnabled")
        self.writes = self.writes + 1
        self.click = value
    end
    function frame:SetMouseMotionEnabled(value)
        assert(not self:IsForbidden() and not locked, "forbidden SetMouseMotionEnabled")
        self.writes = self.writes + 1
        self.motion = value
    end
    function frame:SetPropagateMouseClicks(value)
        assert(not self:IsForbidden() and not locked, "forbidden SetPropagateMouseClicks")
        self.writes = self.writes + 1
        self.propagate = value
    end
    function frame:HookScript() assert(not self:IsForbidden() and not locked) end
    return frame
end

local button = NewMouseFrame()
button._msufA3LaneKind = "buff"
local container = NewMouseFrame()
container._msufA3NativeLane = "buffs"
container._msufA3NativeLaneConfig = { unit = "boss1" }
function container:GetAuraFrameCount() return 1 end
function container:GetAuraFrame() return button end
local element = { Buffs = container, alpha = 1, _msufA3Config = { lanes = { buffs = { showTooltip = true } } } }
function element:GetAlpha() return self.alpha end
function element:SetAlpha(value) self.alpha = value end
local unitFrame = { Auras = element }

local namespace = { MSUF_Auras3 = { EditMode = { groups = {} } } }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_EditMode_Drag.lua"))("MidnightSimpleUnitFrames", namespace)
local drag = namespace.MSUF_Auras3.EditModeModules.Drag(
    {}, { GetFrame = function(unit) assert(unit == "boss1"); return unitFrame end },
    function() return false end, function() return false end, function() end)

drag.SetRuntimeAuraHidden("boss1", true)
assert(element.alpha == 0 and button.click == true and button.motion == false)
button.forbidden = true
local writes = button.writes
drag.SetRuntimeAuraHidden("boss1", false)
assert(button.writes == writes and element.alpha == 1)
assert(element._msufA3EditModeAlpha == 1 and listener.events.PLAYER_ALIVE)
assert(#timers == 1)
timers[1]()
assert(#timers == 1 and element._msufA3EditModeAlpha == 1, "retry must wait without polling")
button.forbidden = false
listener.callback(listener, "PLAYER_ALIVE")
assert(button.click == false and button.motion == true and button.propagate == false)
assert(element._msufA3EditModeAlpha == nil and not listener.events.PLAYER_ALIVE)

button = NewMouseFrame()
button._msufA3LaneKind = "buff"
button.forbidden = true
drag.SetRuntimeAuraHidden("boss1", true)
drag.SetRuntimeAuraHidden("boss1", false)
assert(button.writes == 0 and element._msufA3EditModeAlpha == nil)

button.forbidden = false
drag.SetRuntimeAuraHidden("boss1", true)
locked = true
drag.SetRuntimeAuraHidden("boss1", false)
assert(element.alpha == 0 and element._msufA3EditModeAlpha == 1)
locked = false
listener.callback(listener, "PLAYER_REGEN_ENABLED")
assert(element.alpha == 1 and element._msufA3EditModeAlpha == nil)
assert(button.click == false and button.motion == true)

print("classic aura edit forbidden mouse smoke: OK")
