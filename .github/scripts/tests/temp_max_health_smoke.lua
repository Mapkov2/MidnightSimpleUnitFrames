_G = _G or _ENV

local path = "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_TempMaxHealth.lua"
local handle = io.open(path, "r")
if not handle then
    path = "UnitFrames/Engine/Elements/MSUF_UF_Elements_TempMaxHealth.lua"
else
    handle:close()
end

local registeredName, element
local MSUF = { UF = {} }
function MSUF.UF.RegisterElement(name, implementation)
    registeredName, element = name, implementation
end

local apiCalls = 0
_G.GetUnitTotalModifiedMaxHealthPercent = function(unit)
    apiCalls = apiCalls + 1
    assert(unit == "player", "initial seed used the wrong unit")
    return 0.25
end

local function NewTexture()
    local texture = { clearCount = 0 }
    function texture:SetColorTexture(...) self.color = { ... } end
    function texture:ClearAllPoints() self.clearCount = self.clearCount + 1 end
    function texture:SetAllPoints(anchor) self.anchor = anchor end
    return texture
end

local createdBar
_G.CreateFrame = function(frameType, _, parent)
    assert(frameType == "StatusBar" and parent, "unexpected frame creation")
    local bar = { shown = false, textureChanges = 0 }
    function bar:SetMinMaxValues(minimum, maximum)
        self.minimum, self.maximum = minimum, maximum
    end
    function bar:SetValue(value)
        self.value = value
        self.valueCalls = (self.valueCalls or 0) + 1
    end
    function bar:SetStatusBarTexture(texture)
        self.texture = texture
        self.textureChanges = self.textureChanges + 1
        self.fill = NewTexture()
    end
    function bar:GetStatusBarTexture() return self.fill end
    function bar:SetStatusBarColor(...) self.color = { ... } end
    function bar:CreateTexture() return NewTexture() end
    function bar:EnableMouse(enabled) self.mouseEnabled = enabled end
    function bar:ClearAllPoints() self.pointsCleared = true end
    function bar:SetAllPoints(anchor) self.anchor = anchor end
    function bar:SetReverseFill(reverse) self.reverse = reverse end
    function bar:SetFrameLevel(level) self.level = level end
    function bar:Show() self.shown = true end
    function bar:Hide() self.shown = false end
    createdBar = bar
    return bar
end

local chunk, err = loadfile(path)
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", MSUF)

assert(registeredName == "TempMaxHealth" and element,
    "temporary maximum-health element was not registered")

local health = { level = 10 }
function health:GetFrameLevel() return self.level end

local spec = {
    health = { reverse = false },
    tempMaxHealth = {
        enabled = true,
        test = false,
        texture = "Interface\\Test\\Loss",
        r = 0.7, g = 0.1, b = 0.1, a = 0.9,
        backgroundAlpha = 0.6,
    },
}
local frame = { hpBar = health, MSUFSpec = spec }

assert(element.IsEnabled(frame, spec) == true, "enabled element was rejected")
spec.tempMaxHealth.enabled = false
assert(element.IsEnabled(frame, spec) == false, "disabled element remained active")
spec.tempMaxHealth.enabled = true

element.Create(frame, spec)
assert(createdBar and frame.tempMaxHealthBar == createdBar
    and frame.reducedMaxHealthBar == createdBar,
    "runtime aliases were not installed")
assert(createdBar.minimum == 0 and createdBar.maximum == 1,
    "status bar did not use normalized native values")
assert(createdBar.anchor == health and createdBar.level == 10 and createdBar.reverse == true,
    "loss overlay did not mirror the health geometry")

local oldFill = createdBar:GetStatusBarTexture()
element.Apply(frame, spec)
assert(createdBar.texture == spec.tempMaxHealth.texture and createdBar.shown,
    "configured texture was not applied")
assert(createdBar:GetStatusBarTexture() ~= oldFill
    and frame.tempMaxHealthBackground.anchor == createdBar:GetStatusBarTexture(),
    "background did not follow a replaced status-bar fill texture")
assert(createdBar.color[1] == 0.7 and createdBar.color[4] == 0.9,
    "configured overlay color was not applied")
assert(frame.tempMaxHealthBackground.color[4] == 0.6,
    "configured background opacity was not applied")

local events = element.GetEvents(frame, spec)
assert(#events == 1 and events[1] == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
    "runtime event route is not minimal")

element.Update(frame, nil, "player")
assert(apiCalls == 1 and createdBar.value == 0.25,
    "cold seed did not read the native API exactly once")

local secretPayload = {}
element.Update(frame, "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", "player", secretPayload)
assert(apiCalls == 1 and createdBar.value == secretPayload,
    "event payload was not forwarded directly to the native StatusBar")

spec.health.reverse = true
element.Apply(frame, spec)
assert(createdBar.reverse == false, "reverse health direction was not mirrored")

spec.tempMaxHealth.test = true
assert(#element.GetEvents(frame, spec) == 0, "preview mode retained the live event")
element.Update(frame, nil, "player")
assert(apiCalls == 1 and createdBar.value == 0.20,
    "preview mode did not use the fixed synthetic loss")

element.Disable(frame)
assert(createdBar.value == 0 and createdBar.shown == false,
    "disable did not clear and hide the overlay")

local sourceHandle = assert(io.open(path, "r"))
local source = sourceHandle:read("*a")
sourceHandle:close()
assert(not source:find("OnUpdate", 1, true)
    and not source:find("C_Timer", 1, true)
    and not source:find("UNIT_HEALTH\"", 1, true),
    "temporary maximum-health runtime gained a polling or health-update path")

print("temp max health smoke: ok")
