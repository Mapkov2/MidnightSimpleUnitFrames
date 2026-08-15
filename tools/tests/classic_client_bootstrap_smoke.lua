local flavor = assert(arg[1], "client flavor required")
local repo = assert(arg[2], "repo root required")

WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_CLASSIC = 2
WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
WOW_PROJECT_MISTS_CLASSIC = 19

local specs = {
    Mainline = { project = WOW_PROJECT_MAINLINE, interface = 120100, classic = false },
    Vanilla = { project = WOW_PROJECT_CLASSIC, interface = 11509, classic = true },
    Mists = { project = WOW_PROJECT_MISTS_CLASSIC, interface = 50504, classic = true },
    TBC = { project = WOW_PROJECT_BURNING_CRUSADE_CLASSIC, interface = 20506, classic = true },
}
local spec = assert(specs[flavor], "unknown flavor: " .. tostring(flavor))
WOW_PROJECT_ID = spec.project

C_AddOns = {
    GetAddOnMetadata = function(_, key)
        if key == "X-MSUF-Client" and spec.classic then return flavor end
        return nil
    end,
}
local originalAddOns = C_AddOns
local originalMetadata = C_AddOns.GetAddOnMetadata
C_Spell = nil
C_SpellBook = nil
function GetBuildInfo()
    return "test", "test", "test", spec.interface
end

local addonName = "MidnightSimpleUnitFrames"
local namespace = {}
local clientChunk = assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Shared/Initialize.lua"))
clientChunk(addonName, namespace)
if spec.classic then
    local classicChunk = assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Classic/Initialize.lua"))
    classicChunk(addonName, namespace)
end

assert(MSUF == namespace, "client bootstrap did not publish MSUF")
assert(namespace.Client.Flavor == flavor, "wrong flavor")
assert(namespace.Client.IsClassic == spec.classic, "wrong Classic flag")
assert(namespace.Client.IsVanilla == (flavor == "Vanilla"), "wrong Vanilla flag")
assert(namespace.Client.IsEra == (flavor == "Vanilla"), "wrong Era flag")
assert(namespace.Client.IsMists == (flavor == "Mists"), "wrong Mists flag")
assert(namespace.Client.IsTBC == (flavor == "TBC"), "wrong TBC flag")
assert(namespace.Client.IsRetail == (flavor == "Mainline"), "wrong Retail flag")
assert(namespace.Client.SupportsPetHappiness == (flavor == "Vanilla" or flavor == "TBC"),
    "wrong Pet Happiness capability")
assert(namespace.Client.Interface == spec.interface, "wrong interface")
assert(namespace.Client.SupportsEvent("PLAYER_ENTERING_WORLD") == true, "known event was rejected")
assert(namespace.Client.SupportsEvent("UNIT_POWER_POINT_CHARGE") == (not spec.classic), "point-charge event capability mismatch")
assert(namespace.Client.SupportsEvent("WAR_MODE_STATUS_UPDATE") == (not spec.classic), "war-mode event capability mismatch")
assert(C_AddOns == originalAddOns and C_AddOns.GetAddOnMetadata == originalMetadata,
    "client bootstrap replaced or rewrote Blizzard C_AddOns")
assert(C_AddOns.IsAddOnLoaded == nil and C_AddOns.LoadAddOn == nil,
    "client bootstrap added fields to Blizzard C_AddOns")
assert(C_Spell == nil and C_SpellBook == nil,
    "client bootstrap created Blizzard C_Spell/C_SpellBook namespaces")
if spec.classic then
    assert(type(namespace.Compat.AddOns) == "table"
        and namespace.Compat.AddOns.GetAddOnMetadata == originalMetadata,
        "Classic local AddOns compatibility adapter missing")
    assert(type(namespace.Compat.Spell) == "table" and type(namespace.Compat.Spell.GetSpellName) == "function",
        "Classic local spell compatibility adapter missing")
    assert(type(namespace.Compat.SpellBook) == "table",
        "Classic local spellbook compatibility adapter missing")
else
    assert(namespace.Compat.AddOns == nil and namespace.Compat.Spell == nil and namespace.Compat.SpellBook == nil,
        "Mainline loaded Classic compatibility adapters")
end

local bootstrapChunk = assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Bootstrap.lua"))
bootstrapChunk(addonName, namespace)
assert(MSUF == namespace and MSUF_NS == namespace, "kernel replaced client namespace")
assert(namespace.Compat.Client == namespace.Client, "client compat bridge was lost")
assert(namespace.Core.BootstrapLoaded == true, "kernel bootstrap did not finish")

-- A Classic interface is intentionally below 120100 but must not arm the
-- Retail-only old-client popup or create its fallback event frame.
function CreateFrame()
    error("client version warning created a frame for " .. flavor)
end
local warningChunk = assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Game/Classic/Features/MSUF_ClientVersionWarning.lua"))
warningChunk(addonName, namespace)
assert(namespace.ClientVersionWarning.IsLegacyClient() == false, "Classic was classified as legacy Retail")

print("client bootstrap smoke passed: " .. flavor)
