-- Standalone regression for the cached Power-bar visibility hotpath.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

_G.issecretvalue = function() return false end

local elements = {}
local percentReads = 0
local UF = {
    Elements = elements,
    RegisterElement = function(name, element) elements[name] = element end,
}
local common = {
    UF = UF,
    UnitPower = function() return 50 end,
    UnitPowerMax = function() return 100 end,
    UnitPowerType = function() return 0, "MANA" end,
    UnitPowerPercent = function()
        percentReads = percentReads + 1
        return 50
    end,
    PowerBarColor = { MANA = { r = 0, g = 0.4, b = 1 } },
    SCALE_100 = {},
    WHITE = "white",
}
local addon = { UF = UF, UFBarTextCommon = common }
local healthChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua"))
healthChunk("MidnightSimpleUnitFrames", addon)
local powerChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua"))
powerChunk("MidnightSimpleUnitFrames", addon)

local isShownCalls = 0
local bar = {
    _msufShown = true,
    _msufPowerType = 0,
    _msufPowerToken = "MANA",
    _msufPowerTypeKnown = true,
    _msufPowerTypeUnit = "target",
    IsShown = function()
        isShownCalls = isShownCalls + 1
        return true
    end,
    SetMinMaxValues = function(self, _, maximum) self.maximum = maximum end,
    SetValue = function(self, value) self.value = value end,
}
local frame = {
    unit = "target",
    targetPowerBar = bar,
    MSUFSpec = { power = { enabled = true, mode = "power" } },
}
local update = elements.Power.SelectUpdate(frame)

update(frame, "UNIT_POWER_UPDATE", "target", "MANA")
Check(percentReads == 1 and bar.value == 50, "visible cached bar did not update")
Check(isShownCalls == 0, "steady Power update called native IsShown")

bar._msufShown = false
update(frame, "UNIT_POWER_UPDATE", "target", "MANA")
Check(percentReads == 1, "cached hidden Power bar performed value work")
Check(isShownCalls == 0, "hidden Power bar called native IsShown")

bar._msufShown = nil
update(frame, "UNIT_POWER_UPDATE", "target", "MANA")
Check(percentReads == 2 and isShownCalls == 1,
    "uncached pre-Apply bar lost its native visibility fallback")

local healthBar = {
    points = {},
    clearCalls = 0,
    ClearAllPoints = function(self)
        self.clearCalls = self.clearCalls + 1
        self.points = {}
    end,
    SetPoint = function(self, ...)
        self.points[#self.points + 1] = { ... }
    end,
}
local powerBar = {
    ClearAllPoints = function(self) self.points = {} end,
    SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
    SetHeight = function(self, height) self.height = height end,
    SetSize = function(self, width, height) self.width, self.height = width, height end,
    SetStatusBarTexture = function(self, texture) self.texture = texture end,
    SetStatusBarColor = function(self, r, g, b, a) self.color = { r, g, b, a } end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
}
local layoutFrame = {
    unit = "target",
    hpBar = healthBar,
    targetPowerBar = powerBar,
    GetFrameLevel = function() return 1 end,
}

local function ApplyPower(power)
    local spec = { power = power }
    layoutFrame.MSUFSpec = spec
    elements.Power.Apply(layoutFrame, spec)
end

ApplyPower({ enabled = true, height = 7 })
Check(healthBar.points[1][1] == "TOPLEFT" and healthBar.points[1][2] == layoutFrame,
    "Health layout lost its frame TOPLEFT anchor")
Check(healthBar.points[2][1] == "BOTTOMRIGHT" and healthBar.points[2][5] == 7,
    "embedded Power height did not inset the Health bar")
local cachedClearCalls = healthBar.clearCalls
ApplyPower({ enabled = true, height = 7 })
Check(healthBar.clearCalls == cachedClearCalls, "unchanged Health inset rebuilt its anchors")

ApplyPower({ enabled = true, embed = false, height = 7 })
Check(healthBar.points[2][5] == 0, "external Power left a stale Health inset")

ApplyPower({ enabled = true, height = 7 })
ApplyPower({ enabled = true, detached = true, detachedWidth = 40, height = 7 })
Check(healthBar.points[2][5] == 0, "detached Power left a stale Health inset")

ApplyPower({ enabled = true, height = 7 })
elements.Power.Disable(layoutFrame)
Check(healthBar.points[2][5] == 0, "disabled Power left a stale Health inset")

print("Power bar visibility hotpath smoke passed (cached visibility + Health geometry)")
