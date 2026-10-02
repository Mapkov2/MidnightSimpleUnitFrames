-- Edit Mode hides the live aura element while its preview groups show, and it
-- rewires only the lane containers' mouse input (MSUF_Auras3_EditMode_Drag.lua).
--
-- A native AuraButton is sealed once initializeFrame returns: the frame provider
-- applies its access restrictions right after that callback
-- (Blizzard_AuraContainerFrameProviders.lua), the AuraButton intrinsic forbids
-- untrusted scripts and AlwaysPropagateInput (Blizzard_AuraButton.xml), and the
-- client then refuses SetScript and HookScript on it ("blocked by secret
-- aspects"). The button stub below is that strict: any input or script write on
-- a sealed button raises, so the old per-button rewiring fails here as it
-- failed in game. A container stays writable, but only while it is not
-- forbidden, the UI is not locked down and CanBeAccessedInContext says so.
local root = assert(arg[1], "repository root argument missing")
local locked = false
local timers = {}
local listener

_G.InCombatLockdown = function() return locked end
_G.issecretvalue = function(value) return type(value) == "table" and value._secret == true end
_G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
_G.CreateFrame = function()
    listener = { events = {} }
    function listener:SetScript(_, callback) self.callback = callback end
    function listener:RegisterEvent(event) self.events[event] = true end
    function listener:UnregisterEvent(event) if self.events then self.events[event] = nil end end
    return listener
end

local function NewMouseFrame(sealed)
    local frame = { mouse = true, click = false, motion = true, propagate = false, writes = 0, hooks = {},
        sealed = sealed == true, access = true }
    local function Write(self, name)
        if self.sealed then error(name .. "(): blocked by secret aspects", 3) end
        assert(not self:IsForbidden() and not locked, "forbidden " .. name)
        assert(self.access == true, "access-restricted " .. name)
        self.writes = self.writes + 1
    end
    function frame:IsForbidden() return self.forbidden == true end
    function frame:CanBeAccessedInContext() return self.access end
    function frame:IsMouseEnabled() return self.mouse end
    function frame:IsMouseClickEnabled() return self.click end
    function frame:IsMouseMotionEnabled() return self.motion end
    function frame:GetPropagateMouseClicks() return self.propagate end
    function frame:EnableMouse(value) Write(self, "EnableMouse"); self.mouse = value end
    function frame:SetMouseClickEnabled(value) Write(self, "SetMouseClickEnabled"); self.click = value end
    function frame:SetMouseMotionEnabled(value) Write(self, "SetMouseMotionEnabled"); self.motion = value end
    function frame:SetPropagateMouseClicks(value)
        if self.sealed and value == true then error("SetPropagateMouseClicks(): AlwaysPropagateInput is forbidden", 2) end
        Write(self, "SetPropagateMouseClicks")
        self.propagate = value
    end
    function frame:SetScript(name) Write(self, "SetScript " .. tostring(name)) end
    function frame:HookScript(name, handler) Write(self, "HookScript " .. tostring(name)); self.hooks[name] = handler end
    return frame
end

-- A native lane container: one fixed slot, then its flow group's buttons.
local slotButton = NewMouseFrame(true)
local flowButton = NewMouseFrame(true)
slotButton._msufA3LaneKind, flowButton._msufA3LaneKind = "buff", "buff"
local container = NewMouseFrame(false)
container._msufA3NativeLane = "buffs"
container._msufA3NativeLaneConfig = { unit = "boss1" }
container._msufA3ManagedGroupKey = "msuf_buff"
container._msufA3FixedButtonCount = 1
container.createdButtons = 2
container[1] = slotButton
function container:GetAuraFrameCount() return 1 end
function container:GetAuraFrame() return slotButton end
function container:GetAuraGroupFrameCount() return 1 end
function container:GetAuraGroupFrame() return flowButton end
local element = { Buffs = container, alpha = 1, _msufA3Config = { lanes = { buffs = { showTooltip = true } } } }
function element:GetAlpha() return self.alpha end
function element:SetAlpha(value) self.alpha = value end
local unitFrame = { Auras = element }

local editActive = true
local forwarded = {}
local group = {}
function group:GetScript(name) return function(_, button) forwarded[#forwarded + 1] = name .. ":" .. button end end
local namespace = { MSUF_Auras3 = { EditMode = { groups = { boss1 = { buff = group } } } } }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_EditMode_Drag.lua"))("MidnightSimpleUnitFrames", namespace)
local drag = namespace.MSUF_Auras3.EditModeModules.Drag(
    {}, { GetFrame = function(unit) assert(unit == "boss1"); return unitFrame end },
    function() return editActive end, function() return false end, function() end)

local function ButtonsUntouched(label)
    for _, button in ipairs({ slotButton, flowButton }) do
        assert(button.writes == 0 and next(button.hooks) == nil,
            label .. ": Edit Mode rewired a sealed native AuraButton")
        assert(button.click == false and button.motion == true and button.propagate == false,
            label .. ": a sealed native AuraButton lost its initializeFrame input")
    end
end

-- Hide: the element goes transparent and the container forwards clicks to the
-- preview group and through to the unit frame below; the buttons keep their own
-- click-through input.
drag.SetRuntimeAuraHidden("boss1", true)
assert(element.alpha == 0, "the live aura element stayed visible in Edit Mode")
assert(container.mouse == true and container.click == true and container.motion == false
    and container.propagate == true, "the container did not forward Edit Mode clicks")
assert(container.hooks.OnMouseDown and container.hooks.OnMouseUp, "the container forward hooks are missing")
ButtonsUntouched("hide")
container.hooks.OnMouseDown(container, "LeftButton")
container.hooks.OnMouseUp(container, "LeftButton")
assert(forwarded[1] == "OnMouseDown:LeftButton" and forwarded[2] == "OnMouseUp:LeftButton",
    "a container click did not reach the preview group")
-- A refresh hides again: the hooks are installed once.
local hookWrites = container.writes
drag.SetRuntimeAuraHidden("boss1", true)
assert(container.writes - hookWrites <= 4, "a repeated hide hooked the container again")

-- Restore puts the container's own input back and leaves the buttons alone.
drag.SetRuntimeAuraHidden("boss1", false)
assert(element.alpha == 1 and element._msufA3EditModeAlpha == nil, "leaving Edit Mode kept the element hidden")
assert(container.mouse == true and container.click == false and container.motion == true
    and container.propagate == false, "leaving Edit Mode did not restore the container input")
ButtonsUntouched("restore")

-- A forbidden container cannot be restored now: the restore waits for an event.
drag.SetRuntimeAuraHidden("boss1", true)
container.forbidden = true
drag.SetRuntimeAuraHidden("boss1", false)
assert(element.alpha == 1 and element._msufA3EditModeAlpha == 1 and listener.events.PLAYER_ALIVE,
    "a forbidden container's restore was not queued")
assert(#timers >= 1)
timers[#timers]()
assert(element._msufA3EditModeAlpha == 1, "the retry must wait without polling")
container.forbidden = false
listener.callback(listener, "PLAYER_ALIVE")
assert(container.click == false and container.motion == true and container.propagate == false,
    "the queued restore did not restore the container")
assert(element._msufA3EditModeAlpha == nil and not listener.events.PLAYER_ALIVE)

-- An access-restricted container (a false or secret CanBeAccessedInContext)
-- is never written, and its restore is queued the same way.
container.access = { _secret = true }
local writes = container.writes
drag.SetRuntimeAuraHidden("boss1", true)
assert(container.writes == writes and container.click == false, "Edit Mode wrote an access-restricted container")
container.access = true
drag.SetRuntimeAuraHidden("boss1", true)
container.access = false
drag.SetRuntimeAuraHidden("boss1", false)
assert(element._msufA3EditModeAlpha == 1, "an access-restricted container's restore was not queued")
container.access = true
listener.callback(listener, "PLAYER_ALIVE")
assert(container.click == false and element._msufA3EditModeAlpha == nil, "the queued restore did not run")

-- Lockdown: nothing is written until combat ends.
drag.SetRuntimeAuraHidden("boss1", true)
locked = true
drag.SetRuntimeAuraHidden("boss1", false)
assert(element.alpha == 0 and element._msufA3EditModeAlpha == 1)
locked = false
listener.callback(listener, "PLAYER_REGEN_ENABLED")
assert(element.alpha == 1 and element._msufA3EditModeAlpha == nil)
assert(container.click == false and container.motion == true)
ButtonsUntouched("lockdown")

print("classic aura edit forbidden mouse smoke: OK")
