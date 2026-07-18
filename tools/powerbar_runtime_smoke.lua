_G = _G or _ENV

local path = "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua"
local handle = io.open(path, "r")
if not handle then path = "UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua" else handle:close() end

local INTERP = {}
local SECRET = {}
local currentPercent = 75
local backgroundApplies, gradientApplies, gradientHides, interpolationSnaps = 0, 0, 0, 0
local externalWidths = { EssentialCooldownViewer = 222, UtilityCooldownViewer = 246 }
local externalShown, positionLocked = true, false
local externalRelativeWidths = setmetatable({}, { __mode = "k" })

local function NewRegion(parent)
    local region = { parent = parent, shown = true, points = {}, frameLevel = 1 }
    function region:GetParent() return self.parent end
    function region:SetParent(value) self.parent = value end
    function region:EnableMouse(value) self.mouseEnabled = value end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:IsShown() return self.shown end
    function region:IsVisible() return self.shown end
    function region:ClearAllPoints() self.points = {} end
    function region:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function region:SetAllPoints(value) self.allPoints = value or true end
    function region:SetSize(width, height) self.width, self.height = width, height end
    function region:SetWidth(width) self.width = width; self.setWidthCalls = (self.setWidthCalls or 0) + 1 end
    function region:SetHeight(height) self.height = height end
    function region:GetWidth() return self.width or 275 end
    function region:GetHeight() return self.height or 40 end
    function region:SetFrameLevel(level) self.frameLevel = level end
    function region:GetFrameLevel() return self.frameLevel end
    function region:SetMinMaxValues(minValue, maxValue) self.minValue, self.maxValue = minValue, maxValue end
    function region:SetValue(value, interpolation)
        self.value = value
        self.interpolation = interpolation
        self.valueCalls = (self.valueCalls or 0) + 1
    end
    function region:SetStatusBarTexture(texture) self.statusTexture = texture end
    function region:SetStatusBarColor(r, g, b, a) self.statusColor = { r, g, b, a } end
    function region:GetStatusBarColor()
        local color = self.statusColor or { 1, 1, 1, 1 }
        return color[1], color[2], color[3], color[4]
    end
    function region:SetReverseFill(value) self.reverseFill = value end
    function region:SetOrientation(value) self.orientation = value end
    function region:SetTexture(texture) self.texture = texture end
    function region:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end
    function region:SetVertexColor(r, g, b, a) self.vertexColor = { r, g, b, a } end
    function region:SetAlpha(alpha) self.alpha = alpha end
    function region:SetBlendMode(mode) self.blendMode = mode end
    function region:CreateTexture()
        local texture = NewRegion(self)
        self.textures = self.textures or {}
        self.textures[#self.textures + 1] = texture
        return texture
    end
    return region
end

local function CreateFrame(_, _, parent)
    return NewRegion(parent)
end

local registered
local UF = {
    RegisterElement = function(name, element)
        assert(name == "Power", "unexpected element registration")
        registered = element
    end,
}
local Common = {
    UF = UF,
    CreateFrame = CreateFrame,
    UnitPower = function() return 75 end,
    UnitPowerMax = function() return 100 end,
    UnitPowerType = function() return 0, "MANA" end,
    UnitPowerPercent = function() return currentPercent end,
    PowerBarColor = { MANA = { r = 0, g = 0.4, b = 1 } },
    PowerColor = function() return 0, 0.4, 1 end,
    WHITE = "white",
    SCALE_100 = {},
    POWER_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER" },
    POWER_EVENTS_FREQUENT = { "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER" },
    SetBarSmoothing = function(bar, enabled)
        bar._msufSmoothInterp = enabled and INTERP or nil
    end,
    SnapBarInterpolation = function(bar)
        interpolationSnaps = interpolationSnaps + 1
        bar._msufInterpolating = nil
    end,
    ApplyBackgrounds = function(frame, health, power)
        assert(health == false and power == true, "power background scope mismatch")
        backgroundApplies = backgroundApplies + 1
        frame.backgroundApplied = true
    end,
    ApplyBarGradient = function(frame, _, _, storeKey)
        gradientApplies = gradientApplies + 1
        frame[storeKey] = frame[storeKey] or {}
    end,
    HideBarGradient = function()
        gradientHides = gradientHides + 1
    end,
    ExternalFrameWidth = function(name, relativeTo)
        local relative = relativeTo and externalRelativeWidths[relativeTo]
        return externalShown and ((relative and relative[name]) or externalWidths[name]) or nil
    end,
    InCombatLockdown = function() return positionLocked end,
}

local MSUF = { UF = UF, UFBarTextCommon = Common }
_G.MSUF_NS = MSUF
_G.issecretvalue = function(value) return value == SECRET end

local chunk, err = loadfile(path)
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", MSUF)
local Power = assert(registered, "Power element was not registered")

local function HasEvent(events, wanted)
    for i = 1, #events do
        if events[i] == wanted then return true end
    end
    return false
end

local frame = NewRegion(nil)
frame.unit = "player"
frame.MSUFUnitKey = "player"
frame.frameLevel = 10
frame.width = 275

local power = {
    enabled = true,
    height = 6,
    embed = true,
    detached = false,
    texture = "power-fill",
    backgroundTexture = "power-bg",
    background = { r = 0.08, g = 0.09, b = 0.1, a = 0.8 },
    mode = "static",
    r = 0.1,
    g = 0.35,
    b = 0.95,
    alpha = 1,
    smooth = true,
    borderEnabled = true,
    borderThickness = 2,
    detachedOutline = 3,
    borderR = 0.2,
    borderG = 0.3,
    borderB = 0.4,
    borderA = 0.9,
    barGradient = { right = true, strength = 0.4 },
    reverse = false,
}
local spec = { power = power, texture = "fallback-fill", backgroundAlpha = 0.7 }
frame.MSUFSpec = spec

Power.Apply(frame, spec)
local bar = assert(frame.targetPowerBar, "power bar was not created")
local border = assert(bar.MSUFPowerBorderHost, "configured power border host was not created")
assert(border.shown == true, "configured power border is hidden")
assert(#bar.MSUFPowerBorderEdges == 4, "power border must use four edges")
assert(bar._msufPowerBorderThickness == 2, "power border thickness was not applied")
assert(bar.MSUFPowerBorderEdges[1].colorTexture[1] == 0.2, "power border color was not applied")
assert(backgroundApplies == 1, "compiled power background was not applied")
assert(gradientApplies == 1, "compiled power gradient was not applied")
local playerEvents = Power.GetEvents(frame, spec)
assert(HasEvent(playerEvents, "UNIT_POWER_FREQUENT"), "player power must use UNIT_POWER_FREQUENT")
assert(not HasEvent(playerEvents, "UNIT_POWER_UPDATE"), "player fast path must not duplicate UNIT_POWER_UPDATE")

currentPercent = SECRET
Power.Update(frame, "UNIT_POWER_FREQUENT", "player")
assert(bar.value == SECRET, "secret power value did not reach the StatusBar")
assert(bar.interpolation == INTERP, "secret power did not use native C-side interpolation")
assert(bar._msufPowerPercentValue == nil, "secret power leaked into a Lua comparison cache")
local valueCalls = bar.valueCalls
Power.Update(frame, "UNIT_POWER_FREQUENT", "player", "RAGE")
assert(bar.valueCalls == valueCalls, "unrelated power token reached the player bar hot path")

currentPercent = 64
Power.Update(frame, "UNIT_DISPLAYPOWER", "player")
assert(bar.value == 64 and bar.interpolation == nil, "identity/meta refresh must snap instead of animate")
assert(interpolationSnaps > 0, "non-power refresh did not finish the active interpolation")

power.smooth = false
frame.MSUFSpec = spec
Power.Apply(frame, spec)
currentPercent = SECRET
Power.Update(frame, "UNIT_POWER_FREQUENT", "player")
assert(bar.interpolation == nil, "Smooth Fill off must use immediate StatusBar updates")

power.borderEnabled = false
power.detached = false
Power.Apply(frame, spec)
assert(border.shown == false, "disabled inline power border is still shown")

power.detached = true
power.shape = "BAR"
power.detachedWidth = 320
power.detachedHeight = 9
power.detachedX = 4
power.detachedY = -7
power.detachedLevel = 6
Power.Apply(frame, spec)
assert(frame._msufPowerBarDetached == true, "detached power runtime state was not published")
assert(bar.width == 320 and bar.height == 9, "detached power dimensions were not applied")
assert(bar.frameLevel == 16, "detached power layer was not applied")
power.detachedLevel = 99
Power.Apply(frame, spec)
assert(bar.frameLevel == 40, "detached power layer was not capped at 30")
power.detachedLevel = -9
Power.Apply(frame, spec)
assert(bar.frameLevel == 10, "detached power layer was not clamped at 0")
power.detachedLevel = 6
Power.Apply(frame, spec)
assert(border.shown == true and bar._msufPowerBorderThickness == 3, "detached outline was not restored")
local centeredPoint = bar.points[1]
assert(centeredPoint and centeredPoint[1] == "TOP" and centeredPoint[2] == frame
    and centeredPoint[3] == "BOTTOM" and centeredPoint[4] == 4 and centeredPoint[5] == -7,
    "native 6.0 detached power anchor changed")

power.detachedSyncClass = false
power.detachedWidthFrameName = "EssentialCooldownViewer"
externalShown, positionLocked = true, false
externalRelativeWidths[bar] = { EssentialCooldownViewer = 222, UtilityCooldownViewer = 246 }
Power.Apply(frame, spec)
assert(bar.width == 222, "visible cooldown width source did not own detached Target width")
assert(bar._msufDetachedExternalWidths and bar._msufDetachedExternalWidths.EssentialCooldownViewer == 222,
    "visible cooldown width was not cached on its live Power bar")

local widthOnlyBackgrounds, widthOnlyGradients = backgroundApplies, gradientApplies
local widthOnlyPoints, widthOnlyHeight = #bar.points, bar.height
local widthOnlyCalls = bar.setWidthCalls or 0
externalRelativeWidths[bar].EssentialCooldownViewer = 234
assert(Power.RefreshDetachedExternalWidth(frame, "EssentialCooldownViewer") == true,
    "matching cooldown source did not enter the width-only path")
assert(bar.width == 234 and bar.height == widthOnlyHeight and #bar.points == widthOnlyPoints,
    "width-only refresh changed detached height or anchors")
assert(backgroundApplies == widthOnlyBackgrounds and gradientApplies == widthOnlyGradients,
    "width-only refresh reapplied unrelated media")
assert((bar.setWidthCalls or 0) == widthOnlyCalls + 1,
    "width-only refresh did not perform exactly one physical width write")
assert(Power.RefreshDetachedExternalWidth(frame, "UtilityCooldownViewer") == false and bar.width == 234,
    "unconfigured cooldown source reached the detached bar")
widthOnlyCalls = bar.setWidthCalls or 0
assert(Power.RefreshDetachedExternalWidth(frame, "EssentialCooldownViewer") == true
    and (bar.setWidthCalls or 0) == widthOnlyCalls,
    "unchanged external width caused a redundant SetWidth")

local focusFrame = NewRegion(nil)
local focusBar = NewRegion(focusFrame)
focusFrame.targetPowerBar = focusBar
focusFrame.width = 275
externalRelativeWidths[focusBar] = { EssentialCooldownViewer = 198 }
assert(Power.ResolveDetachedWidth(focusFrame, power) == 198,
    "differently scaled Focus width did not resolve independently")
focusBar:SetWidth(198)

externalShown = false
assert(Power.RefreshDetachedExternalWidth(frame, "EssentialCooldownViewer") == true,
    "hidden source did not enter the width-only fallback path")
assert(bar.width == 320, "hidden cooldown source did not return to the configured manual width")
assert(bar._msufDetachedExternalWidths.EssentialCooldownViewer == nil,
    "hidden OOC source retained a stale external width cache")

positionLocked = true
assert(Power.ResolveDetachedWidth(frame, power) == 320 and bar.width == 320,
    "combat preview resurrected a stale visible width after the live bar fell back OOC")
assert(Power.ResolveDetachedWidth(focusFrame, power) == 198,
    "Target combat cache overwrote the differently scaled Focus width")
positionLocked = false

power.detachedSyncClass = true
power.detachedClassWidthFrameName = "UtilityCooldownViewer"
power.detachedClassWidth = 276
externalShown = true
Power.Apply(frame, spec)
assert(bar.width == 246, "Class Resource sync did not use its own cooldown width source")
power.detachedSyncClass = false
power.detachedClassWidthFrameName = nil
power.detachedWidthFrameName = nil
externalShown = true

power.detachedAnchorMode = "LEGACY_TOPLEFT"
Power.Apply(frame, spec)
local legacyPoint = bar.points[1]
assert(legacyPoint and legacyPoint[1] == "TOPLEFT" and legacyPoint[2] == frame
    and legacyPoint[3] == "BOTTOMLEFT" and legacyPoint[4] == 4 and legacyPoint[5] == -7,
    "5.5 detached power offsets were not interpreted from the left edge")

power.shape = "ROUND"
power.orbSize = 54
Power.Apply(frame, spec)
assert(bar.width == 320 and bar.height == 9, "Round/Crystal bars must keep detached width and height")
assert(border.shown == false, "shape media must replace the square border")
assert(bar._msufDetachedShapeEdge and bar._msufDetachedShapeEdge.shown == true, "shape outline was not applied")

power.shape = "ORB"
Power.Apply(frame, spec)
assert(bar.width == 54 and bar.height == 54, "Orb size setting was not applied")
assert(gradientHides > 0, "shape bars must hide rectangular gradients")
assert(Power.RefreshDetachedExternalWidth(frame, "EssentialCooldownViewer") == false,
    "Orb entered the external width path")

power.detached = false
power.shape = "BAR"
power.borderEnabled = true
Power.Apply(frame, spec)
assert(frame._msufPowerBarDetached == nil, "inline power retained detached runtime state")
assert(bar.frameLevel == 11, "inline power did not restore its frame layer")
assert(border.shown == true, "inline border did not return after leaving a shape")

Power.Disable(frame)
assert(border.shown == false, "Power.Disable left the border visible")
assert(frame._msufPowerBarDetached == nil, "Power.Disable left detached runtime state behind")

io.write("powerbar_runtime_smoke: ok\n")
