--- Target-owned combo points, shared by every client that has them.
---
--- Classic Era, TBC and Mists read combo points from GetComboPoints(unit,
--- "target") instead of the modern player-owned UnitPower contract, and so does
--- WoW Forever: Blizzard loads none of the Retail class resource bars for its
--- camelot game type and keeps only the target-owned ComboFrame. Those four
--- clients therefore share one power reader, one target-change rule, one
--- power-token rule and one ComboFrame restore. Only the routing around them
--- differs, and that stays in each client's own MSUF.CPClient provider
--- (Game/<Flavor>/ClassPower.lua, Game/Forever/ClassPower.lua).
---
--- Midnight shares the Mainline manifest with Forever and therefore loads this
--- file. It only defines functions: nothing runs until a provider asks for a
--- part, and Midnight has no provider.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local K = _G.MSUF_CP_CONST or {}
local CPK = K.CPK or {}
local MODE = CPK.MODE or {}
local PT = K.PT or {}
local NativeUnitPower = _G.UnitPower
local GetComboPoints = _G.GetComboPoints
local type = type

local TargetCombo = {}
MSUF.CPTargetCombo = TargetCombo

--- One power reader per provider. The returned SetComboUnit exists for Mists,
--- where a vehicle owns the points while the vehicle route is active; every
--- other client stays on the player and never calls it.
function TargetCombo.NewPowerReader()
    local comboUnit = "player"

    local function UnitPower(unit, powerType, unmodified)
        if powerType == PT.ComboPoints and type(GetComboPoints) == "function" then
            return GetComboPoints(comboUnit, "target") or 0
        end
        return NativeUnitPower(unit, powerType, unmodified)
    end

    local function SetComboUnit(unit)
        comboUnit = unit or "player"
    end

    return UnitPower, SetComboUnit
end

--- The points belong to the target, so they change without a power event.
function TargetCombo.NeedsTargetChanged(powerType)
    return powerType == PT.ComboPoints
end

--- Combo points follow the client's frequent power event.
function TargetCombo.UseFrequentPower(powerType)
    if powerType == PT.ComboPoints then return true end
    return nil
end

--- A target-owned combo point change can arrive with the Energy token, so for
--- combo points the expected-token test is replaced.
function TargetCombo.AcceptPowerToken(powerType, powerToken, expectedToken, playerClass)
    if powerType ~= PT.ComboPoints then return powerToken == expectedToken end
    return powerToken == "COMBO_POINTS"
        or ((playerClass == "ROGUE" or playerClass == "DRUID") and powerToken == "ENERGY")
end

--- The shared ClassPower core passes three arguments, so a controller that
--- knows the class itself binds it once here instead of per event.
function TargetCombo.NewPowerTokenTest(playerClass)
    local AcceptPowerToken = TargetCombo.AcceptPowerToken
    return function(powerType, powerToken, expectedToken)
        return AcceptPowerToken(powerType, powerToken, expectedToken, playerClass)
    end
end

--- Blizzard's own combo point display, for the compat layer that suppresses
--- and restores the client's resource frames.
local function RestoreComboFrame(frame)
    local update = _G.ComboFrame_UpdateMax or _G.ComboFrame_Update
    if type(update) == "function" then update(frame) end
end

--- Only Rogues and Druids ever see a ComboFrame.
function TargetCombo.ComboFrameDefinition(playerClass)
    if playerClass ~= "ROGUE" and playerClass ~= "DRUID" then return nil end
    return { name = "ComboFrame", restore = RestoreComboFrame }
end

--- The whole provider for a client whose only class resource is target-owned
--- combo points: Rogues always, Druids while Cat Form's Energy is the primary
--- power. Classic Era and TBC differ in nothing but their flavor name.
function TargetCombo.NewComboOnlyProvider(flavor, playerClass)
    local Provider = { Flavor = flavor }

    Provider.UnitPower = TargetCombo.NewPowerReader()
    Provider.UseFrequentPower = TargetCombo.UseFrequentPower
    Provider.NeedsTargetChanged = TargetCombo.NeedsTargetChanged
    Provider.AcceptPowerToken = TargetCombo.AcceptPowerToken

    function Provider.Resolve(env)
        if env.playerClass == "ROGUE" then
            return true, PT.ComboPoints, MODE.SEGMENTED, false
        end
        if env.playerClass == "DRUID" and env.primaryPower == PT.Energy then
            return true, PT.ComboPoints, MODE.SEGMENTED, false
        end
        return true, nil, MODE.NONE, false
    end

    local comboFrame = TargetCombo.ComboFrameDefinition(playerClass)
    Provider.BlizzardFrames = comboFrame and { comboFrame } or {}
    return Provider
end
