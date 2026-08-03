--- Classic Era ClassPower provider.
--- Era combo points are target-owned and no later class resources exist.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local K = _G.MSUF_CP_CONST or {}
local CPK = K.CPK or {}
local MODE = CPK.MODE or {}
local PT = K.PT or {}
local NativeUnitPower = _G.UnitPower
local GetComboPoints = _G.GetComboPoints

local Provider = { Flavor = "Vanilla" }

function Provider.UnitPower(unit, powerType, unmodified)
    if powerType == PT.ComboPoints and type(GetComboPoints) == "function" then
        return GetComboPoints("player", "target") or 0
    end
    return NativeUnitPower(unit, powerType, unmodified)
end

function Provider.Resolve(env)
    if env.playerClass == "ROGUE" then
        return true, PT.ComboPoints, MODE.SEGMENTED, false
    end
    if env.playerClass == "DRUID" and env.primaryPower == PT.Energy then
        return true, PT.ComboPoints, MODE.SEGMENTED, false
    end
    return true, nil, MODE.NONE, false
end

function Provider.UseFrequentPower(powerType)
    if powerType == PT.ComboPoints then return true end
    return nil
end

function Provider.NeedsTargetChanged(powerType)
    return powerType == PT.ComboPoints
end

function Provider.AcceptPowerToken(powerType, powerToken, expectedToken, playerClass)
    if powerType ~= PT.ComboPoints then return powerToken == expectedToken end
    return powerToken == "COMBO_POINTS"
        or ((playerClass == "ROGUE" or playerClass == "DRUID") and powerToken == "ENERGY")
end

local _, playerClass = _G.UnitClass("player")
if playerClass == "ROGUE" or playerClass == "DRUID" then
    Provider.BlizzardFrames = {
        {
            name = "ComboFrame",
            restore = function(frame)
                local update = _G.ComboFrame_UpdateMax or _G.ComboFrame_Update
                if type(update) == "function" then update(frame) end
            end,
        },
    }
else
    Provider.BlizzardFrames = {}
end

MSUF.CPClient = Provider
