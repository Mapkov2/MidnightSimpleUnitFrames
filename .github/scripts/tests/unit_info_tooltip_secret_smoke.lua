local path = "MidnightSimpleUnitFrames/Runtime/MSUF_ChatAndTooltips.lua"
local handle = io.open(path, "r")
if not handle then
    path = "Runtime/MSUF_ChatAndTooltips.lua"
else
    handle:close()
end

local secret = setmetatable({}, {
    __concat = function() error("secret value was concatenated", 2) end,
    __eq = function() error("secret value was compared", 2) end,
    __tostring = function() error("secret value was stringified", 2) end,
})

issecretvalue = function(value)
    return rawequal(value, secret)
end

SlashCmdList = {}
UIParent = {}
C_Timer = { After = function(_, callback) if callback then callback() end end }
MSUF_DB = {
    general = {
        unitTooltipProvider = "MSUF",
        unitTooltipAnchor = "FIXED",
        unitTooltipMode = "ALWAYS",
        unitTooltipModifier = "ALT",
    },
}

local assigned = {}
local fontStringCount = 0
local function Noop() end
local function NewFontString()
    fontStringCount = fontStringCount + 1
    local key = ({ "name", "line2", "line3", "line4", "line5" })[fontStringCount]
    return {
        SetPoint = Noop,
        SetJustifyH = Noop,
        SetTextColor = Noop,
        SetText = function(_, value) assigned[key] = value end,
    }
end

local infoFrame
CreateFrame = function()
    infoFrame = {
        SetSize = Noop,
        SetPoint = Noop,
        ClearAllPoints = Noop,
        SetFrameStrata = Noop,
        SetClampedToScreen = Noop,
        EnableMouse = Noop,
        SetBackdrop = Noop,
        SetBackdropColor = Noop,
        Hide = function(self) self.shown = false end,
        Show = function(self) self.shown = true end,
        CreateFontString = function() return NewFontString() end,
    }
    return infoFrame
end

UnitExists = function() return true end
UnitName = function() return secret end
UnitLevel = function() return secret end
UnitIsPlayer = function() return true end
UnitRace = function() return secret end
UnitClass = function() return secret, secret end
UnitFactionGroup = function() return secret end
UnitIsPVP = function() return secret end
UnitIsAFK = function() return secret end
UnitIsDND = function() return secret end
UnitClassification = function() return secret end
UnitCreatureType = function() return secret end
UnitSex = function() return secret end
GetZoneText = function() return secret end
GetSubZoneText = function() return secret end

local MSUF = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

assert(loadfile(path))("MidnightSimpleUnitFrames", MSUF)
assert(type(MSUF_ShowUnitInfoTooltip) == "function", "unit-info tooltip export missing")

local ok, err = pcall(MSUF_ShowUnitInfoTooltip, "target", "Target")
assert(ok, "secret unit identity reached an unsafe tooltip operation: " .. tostring(err))
assert(infoFrame and infoFrame.shown == true, "secret identity tooltip was not shown")
assert(rawequal(assigned.name, secret), "secret name was not passed directly to the font string")
assert(assigned.line2 == "", "secret level/race/class leaked into line 2")
assert(assigned.line3 == "", "secret class leaked into line 3")
assert(assigned.line4 == "", "secret faction/PvP state leaked into line 4")
assert(assigned.line5 == "", "secret location leaked into line 5")

print("unit_info_tooltip_secret_smoke: ok")
