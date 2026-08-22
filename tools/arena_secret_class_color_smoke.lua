local root = (...) or "."

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local function Secret(label)
    return { _secret = true, label = label }
end

local secretClass = Secret("class")
local secretR = Secret("r")
local secretG = Secret("g")
local secretB = Secret("b")
local classLookups = 0

_G.issecretvalue = function(value)
    return type(value) == "table" and value._secret == true
end
_G.C_ClassColor = {
    GetClassColor = function(class)
        Check(class == secretClass, "native class-color lookup did not receive the opaque arena class token")
        classLookups = classLookups + 1
        return {
            GetRGB = function()
                return secretR, secretG, secretB
            end,
        }
    end,
}
_G.RAID_CLASS_COLORS = {}
_G.UnitClass = function() return "Opponent", secretClass end
_G.UnitExists = function() return true end
_G.UnitIsPlayer = function() return Secret("isPlayer") end
_G.UnitIsDeadOrGhost = function() return false end
_G.UnitIsConnected = function() return true end
_G.UnitHealth = function() return 100 end
_G.UnitHealthMax = function() return 100 end
_G.UnitPower = function() return 100 end
_G.UnitPowerMax = function() return 100 end
_G.UnitPowerType = function() return 0, "MANA" end
_G.UnitName = function() return "Opponent" end
_G.GetTime = function() return 1 end

local UF = {
    Clamp01 = function(value, fallback)
        if type(value) ~= "number" then return fallback or 0 end
        if value < 0 then return 0 end
        if value > 1 then return 1 end
        return value
    end,
    FreshUnitState = function(frame) return frame and frame._msufUnitState end,
    IsUnitToken = function(unit) return type(unit) == "string" and unit ~= "" end,
    ReadUnitExistsCached = function() return true, true end,
    ReadDeadCached = function() return false, true end,
    ReadConnectedCached = function() return true, true end,
    ReadUnitIsPlayerCached = function() return nil, false end,
    ReadUnitClassCached = function() return "Opponent", secretClass end,
}
local MSUF = {
    UF = UF,
    Secrets = {
        IsSecret = _G.issecretvalue,
        IsNil = function(value) return value == nil end,
        SafeNumber = function(value) return type(value) == "number" and value or nil end,
    },
}

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local frame = {
    MSUFUnitKey = "arena1",
    configKey = "arena",
    MSUFSpec = {
        key = "arena",
        health = { mode = "class" },
        text = { nameClassColor = true },
        textColor = { r = 1, g = 1, b = 1, a = 0.8 },
    },
}
local bar = {
    SetStatusBarColor = function(self, r, g, b, a)
        self.color = { r, g, b, a }
    end,
}

Check(MSUF.UFBarTextCommon.ApplyHealthStatusColor(
    bar, frame, "arena1", 100, 100, nil, "UNIT_NAME_UPDATE") == true,
    "arena health bar did not use the secret native class-color path")
Check(frame._msufUnitState and frame._msufUnitState.isPlayerKnown == true
    and frame._msufUnitState.isPlayer == true,
    "arena token contract did not recover the restricted UnitIsPlayer result")
Check(bar.color and bar.color[1] == secretR and bar.color[2] == secretG and bar.color[3] == secretB,
    "arena health bar reused the cyan fallback instead of native class RGB")
Check(bar._msufStatusR == nil and bar._msufStatusG == nil and bar._msufStatusB == nil,
    "secret arena health RGB was retained in the status-color cache")

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Common.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

frame.nameText = {
    SetTextColor = function(self, r, g, b, a)
        self.color = { r, g, b, a }
    end,
}
MSUF.UFText.ApplyNameTextColor(frame, "arena1")
Check(frame.nameText.color and frame.nameText.color[1] == secretR
    and frame.nameText.color[2] == secretG and frame.nameText.color[3] == secretB,
    "arena name reused the cyan fallback instead of native class RGB")
Check(frame._msufNameTextR == nil and frame._msufNameTextG == nil and frame._msufNameTextB == nil,
    "secret arena name RGB was retained in the text-color cache")

frame.hpTextCenter = {
    SetTextColor = function(self, r, g, b, a)
        self.color = { r, g, b, a }
    end,
}
local rt = { healthColorByClass = true, healthTextAlpha = 0.8 }
MSUF.UFText.UpdateHealthTextColor(frame, rt, "arena1", 100, 100)
Check(frame.hpTextCenter.color and frame.hpTextCenter.color[1] == secretR
    and frame.hpTextCenter.color[2] == secretG and frame.hpTextCenter.color[3] == secretB,
    "arena health text reused the cyan fallback instead of native class RGB")
Check(frame._msufHealthTextR == nil and frame._msufHealthTextG == nil and frame._msufHealthTextB == nil,
    "secret arena health-text RGB was retained in the text-color cache")
Check(classLookups == 3, "unexpected number of native arena class-color lookups")

print("arena_secret_class_color_smoke: ok")
