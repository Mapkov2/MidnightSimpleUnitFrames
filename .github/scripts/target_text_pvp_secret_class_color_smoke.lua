local function AssertSame(actual, expected, message)
    assert(actual == expected, message)
end

local secretClass = {}
local secretR, secretG, secretB = {}, {}, {}
local classToken = secretClass
local nativeLookups = 0

_G = _G or _ENV
_G.issecretvalue = function(value)
    return value == secretClass or value == secretR or value == secretG or value == secretB
end
_G.C_ClassColor = {
    GetClassColor = function(value)
        nativeLookups = nativeLookups + 1
        AssertSame(value, secretClass, "native class-color lookup did not receive the opaque target class token")
        return {
            GetRGB = function()
                return secretR, secretG, secretB
            end,
        }
    end,
}

local isPlayer = true
local UF = {
    FreshUnitState = function()
        return nil
    end,
    ReadUnitIsPlayerCached = function()
        return isPlayer, true
    end,
    ReadUnitClassCached = function()
        return "Mage", classToken
    end,
}

local classColors = {
    MAGE = { r = 0.25, g = 0.50, b = 0.75 },
}
local C = {
    UF = UF,
    type = type,
    tonumber = tonumber,
    format = string.format,
    abs = math.abs,
    floor = math.floor,
    max = math.max,
    RAID_CLASS_COLORS = classColors,
    ClassColorForToken = function(token)
        if _G.issecretvalue(token) then
            error("opaque target class token reached the Lua class-color table path")
        end
        local color = classColors[token]
        if color then return color.r, color.g, color.b end
    end,
    ClassColor = function()
        return 0.12, 0.62, 0.95
    end,
}

local MSUF = {
    UFBarTextCommon = C,
    Secrets = {},
}

local chunk = assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Common.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)
local Text = assert(MSUF.UFText)

local function NewFontString()
    return {
        SetTextColor = function(self, r, g, b, a)
            self.r, self.g, self.b, self.a = r, g, b, a
        end,
    }
end

local nameText = NewFontString()
local frame = {
    MSUFUnitKey = "target",
    MSUFSpec = {
        textColor = { r = 1, g = 1, b = 1, a = 0.80 },
        text = { nameClassColor = true },
    },
    nameText = nameText,
}

Text.ApplyNameTextColor(frame, "target")
AssertSame(nameText.r, secretR, "PvP target name did not receive native secret red")
AssertSame(nameText.g, secretG, "PvP target name did not receive native secret green")
AssertSame(nameText.b, secretB, "PvP target name did not receive native secret blue")
AssertSame(nameText.a, 0.80, "PvP target name alpha changed")
assert(frame._msufNameTextR == nil and frame._msufNameTextG == nil and frame._msufNameTextB == nil,
    "PvP target name cached secret RGB values")

local healthText = NewFontString()
local runtime = {
    healthColorByClass = true,
    healthTextAlpha = 0.70,
    healthSlots = { { fs = healthText } },
    healthSlotCount = 1,
}
Text.UpdateHealthTextColor(frame, runtime, "target")
AssertSame(healthText.r, secretR, "PvP target HP text did not receive native secret red")
AssertSame(healthText.g, secretG, "PvP target HP text did not receive native secret green")
AssertSame(healthText.b, secretB, "PvP target HP text did not receive native secret blue")
AssertSame(healthText.a, 0.70, "PvP target HP text alpha changed")
assert(frame._msufHealthTextR == nil and frame._msufHealthTextG == nil and frame._msufHealthTextB == nil,
    "PvP target HP text cached secret RGB values")
AssertSame(nativeLookups, 2, "unexpected number of native target class-color lookups")

classToken = "MAGE"
Text.ApplyNameTextColor(frame, "target")
AssertSame(nameText.r, 0.25, "plain target class red changed")
AssertSame(nameText.g, 0.50, "plain target class green changed")
AssertSame(nameText.b, 0.75, "plain target class blue changed")
Text.UpdateHealthTextColor(frame, runtime, "target")
AssertSame(healthText.r, 0.25, "plain target HP class red changed")
AssertSame(healthText.g, 0.50, "plain target HP class green changed")
AssertSame(healthText.b, 0.75, "plain target HP class blue changed")
AssertSame(nativeLookups, 2, "plain target class color used the native secret path")

io.write("target_text_pvp_secret_class_color_smoke: ok\n")
