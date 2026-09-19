--- Game/Classic/ClassPower/MSUF_CP_ClassicRouting.lua
--- Classic routing for the shared class resource controller.
---
--- Vanilla, TBC and Mists run the Retail-named controller
--- (ClassPower/MSUF_CP_Controller.lua). It reads one provider seam at load:
--- GetClassPowerType, a Client table with NeedsTargetChanged, UnitPower,
--- UnitPowerDisplayMod, AcceptPowerToken and comboTargetEvent. WoW Forever's
--- provider fills that seam itself. A Classic flavor provider (MSUF.CPClient,
--- Game/<Flavor>/ClassPower.lua) keeps its Resolve(env) contract instead, which
--- the Blizzard frame compat layer and the provider smokes read, so this file
--- builds the seam from it and leaves the provider table untouched. Only the
--- Classic TOCs load it, after the flavor provider and before the controller.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local provider = assert(MSUF.CPClient, "Classic ClassPower provider must load first")
local K = _G.MSUF_CP_CONST or {}
local PT = K.PT or {}
local NotSecret = MSUF.Secrets.NotSecret
local type, assert = type, assert
local UnitPowerType = UnitPowerType
local UnitHasVehicleUI = UnitHasVehicleUI
local C_SpellBook = C_SpellBook
local GetSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
    or GetSpecialization
local PLAYER_CLASS = select(2, UnitClass("player"))

local Routing = {
    --- The provider owns combo point reads (target-owned, or the vehicle's on
    --- Mists) and, on Mists, the Burning Ember display modifier.
    UnitPower = provider.UnitPower,
    UnitPowerDisplayMod = provider.UnitPowerDisplayMod,
    --- The controller reads the target-change rule through a Client table.
    Client = provider,
    --- COMBO_TARGET_CHANGED is bound wherever the client supports it: the
    --- controller's Classic event binder asks MSUF.Client.SupportsEvent.
    comboTargetEvent = true,
}

--- The structural signature resolves on every UNIT_DISPLAYPOWER and
--- structural event, so one env table is refreshed in place and the spell
--- check is a single closure instead of per-call allocations.
local resolveEnv = {}

local function IsPlayerSpell(spellID)
    local known = C_SpellBook and (C_SpellBook.IsSpellKnown or C_SpellBook.IsSpellKnownOrInSpellBook)
    return type(known) == "function" and known(spellID) == true
end

function Routing.GetClassPowerType()
    local clientProvider = MSUF.CPClient
    assert(type(clientProvider.Resolve) == "function", "Missing Classic ClassPower provider")
    local spec = GetSpec and GetSpec()
    local primaryPower = UnitPowerType("player")
    local inVehicle = UnitHasVehicleUI and UnitHasVehicleUI("player") or false
    local vehicleHasCombo = false
    if inVehicle then
        if PlayerVehicleHasComboPoints then
            vehicleHasCombo = PlayerVehicleHasComboPoints() == true
        elseif UnitPowerType then
            vehicleHasCombo = UnitPowerType("vehicle") == PT.ComboPoints
        end
    end
    resolveEnv.playerClass = PLAYER_CLASS
    resolveEnv.spec = spec
    resolveEnv.primaryPower = NotSecret(primaryPower) and primaryPower or nil
    resolveEnv.formID = GetShapeshiftFormID and GetShapeshiftFormID() or nil
    resolveEnv.inVehicle = inVehicle
    resolveEnv.vehicleHasCombo = vehicleHasCombo
    resolveEnv.isPlayerSpell = IsPlayerSpell
    local handled, powerType, renderMode, isAuraPower = clientProvider.Resolve(resolveEnv)
    assert(handled, "Classic ClassPower provider did not handle its client")
    return powerType, renderMode, isAuraPower
end

--- The shared core passes three arguments; the provider rule also takes the
--- class (a target-owned combo point change can arrive with the Energy token).
function Routing.AcceptPowerToken(powerType, powerToken, expectedToken)
    local clientProvider = MSUF.CPClient
    if clientProvider and type(clientProvider.AcceptPowerToken) == "function" then
        return clientProvider.AcceptPowerToken(powerType, powerToken, expectedToken, PLAYER_CLASS) == true
    end
    return false
end

MSUF.CPClassicRouting = Routing
