--- Mists Classic ClassPower provider.
--- Contracts follow Blizzard_UnitFrame/{Cata,Mists} and ElvUI's Mists oUF
--- classpower/eclipse elements.  This module is loaded only by the Mists TOC.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local K = _G.MSUF_CP_CONST or {}
local CPK = K.CPK or {}
local MODE = CPK.MODE or {}
local PT = K.PT or {}
local NativeUnitPower = _G.UnitPower
local GetComboPoints = _G.GetComboPoints

local Provider = {
    Flavor = "Mists",
}

--- MoP combo points are target-owned. Blizzard/oUF use GetComboPoints rather
--- than the modern player UnitPower contract.
function Provider.UnitPower(unit, powerType, unmodified)
    if powerType == PT.ComboPoints and type(GetComboPoints) == "function" then
        return GetComboPoints(unit == "vehicle" and "vehicle" or "player", "target") or 0
    end
    return NativeUnitPower(unit, powerType, unmodified)
end

function Provider.Resolve(env)
    local class = env.playerClass
    local spec = env.spec

    if env.inVehicle then
        local vehiclePower = type(_G.UnitPowerType) == "function" and _G.UnitPowerType("vehicle") or nil
        if env.vehicleHasCombo or vehiclePower == PT.ComboPoints then
            return true, PT.ComboPoints, MODE.SEGMENTED, false
        end
        return true, nil, MODE.NONE, false
    end

    if class == "DEATHKNIGHT" then
        return true, PT.Runes, MODE.RUNE_CD, false
    elseif class == "ROGUE" then
        return true, PT.ComboPoints, MODE.SEGMENTED, false
    elseif class == "PALADIN" then
        return true, PT.HolyPower, MODE.SEGMENTED, false
    elseif class == "WARLOCK" then
        if spec == 2 then return true, PT.DemonicFury, MODE.CONTINUOUS, false end
        if spec == 3 then return true, PT.BurningEmbers, MODE.FRACTIONAL, false end
        if spec == 1 and env.isPlayerSpell(74434) then
            return true, PT.SoulShards, MODE.SEGMENTED, false
        end
        return true, nil, MODE.NONE, false
    elseif class == "MAGE" then
        if spec == 1 then
            return true, "MISTS_ARCANE_CHARGES", MODE.AURA_SEGMENTED, true
        end
        return true, nil, MODE.NONE, false
    elseif class == "MONK" then
        return true, PT.Chi, MODE.SEGMENTED, false
    elseif class == "PRIEST" then
        if spec == 3 then return true, PT.ShadowOrbs, MODE.SEGMENTED, false end
        return true, nil, MODE.NONE, false
    elseif class == "DRUID" then
        if env.primaryPower == PT.Energy then
            return true, PT.ComboPoints, MODE.SEGMENTED, false
        end
        local form = env.formID
        local moonkin = _G.MOONKIN_FORM
        if spec == 1 and (form == nil or (moonkin ~= nil and form == moonkin)) then
            return true, PT.Balance, MODE.SIGNED_CONTINUOUS, false
        end
        return true, nil, MODE.NONE, false
    end

    --- Retail-only class resource trackers must never become active on MoP.
    return true, nil, MODE.NONE, false
end

function Provider.UseFrequentPower(powerType, mode)
    if powerType == PT.HolyPower then return false end
    if powerType == PT.ComboPoints or powerType == PT.SoulShards
        or powerType == PT.Chi or powerType == PT.ShadowOrbs
        or powerType == PT.DemonicFury or powerType == PT.BurningEmbers
        or powerType == PT.Balance then
        return true
    end
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

local function RestoreCombo(frame)
    local update = _G.ComboFrame_UpdateMax or _G.ComboFrame_Update
    if type(update) == "function" then update(frame) end
end

local function RestoreShown(frame, method)
    local fn = frame and frame[method]
    if type(fn) == "function" then fn(frame) end
end

local _, playerClass = _G.UnitClass("player")
if playerClass == "ROGUE" or playerClass == "DRUID" then
    Provider.BlizzardFrames = {
        { name = "ComboFrame", restore = RestoreCombo },
    }
    if playerClass == "DRUID" then
        Provider.BlizzardFrames[#Provider.BlizzardFrames + 1] = {
            name = "EclipseBarFrame",
            restore = function(frame) RestoreShown(frame, "UpdateShown") end,
        }
    end
elseif playerClass == "DEATHKNIGHT" then
    Provider.BlizzardFrames = {
        { name = "RuneFrame", restore = function(frame) frame:Show() end },
    }
elseif playerClass == "PALADIN" then
    Provider.BlizzardFrames = {
        { name = "PaladinPowerBar", restore = function(frame) frame:Show(); RestoreShown(frame, "Update") end },
    }
elseif playerClass == "WARLOCK" then
    Provider.BlizzardFrames = {
        { name = "WarlockPowerFrame", restore = function(frame) RestoreShown(frame, "SetUpCurrentPower") end },
    }
elseif playerClass == "MONK" then
    Provider.BlizzardFrames = {
        { name = "MonkHarmonyBar", restore = function(frame) frame:Show(); RestoreShown(frame, "Update") end },
    }
elseif playerClass == "PRIEST" then
    Provider.BlizzardFrames = {
        { name = "PriestBarFrame", restore = function(frame) RestoreShown(frame, "CheckAndShow") end },
    }
else
    Provider.BlizzardFrames = {}
end

MSUF.CPClient = Provider
