-- Real integration adapters and profile apply, with every external addon absent.
local repo = assert(arg[1])
local flavor = assert(arg[2])
WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_ID = flavor == "Mainline" and 1 or 42
C_AddOns = { GetAddOnMetadata = function(_, key)
    if key == "X-MSUF-Client" then return flavor end
end }
Enum = flavor == "Mainline" and { EditModeSystem = { Minimap = 1 } } or nil
C_EditMode = nil
local ns = {}
local function load(path)
    assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. path))("MidnightSimpleUnitFrames", ns)
end
load("Game/Shared/Initialize.lua")
ns.ExportPublic = function(name, value) _G[name] = value end
MSUF_DB = { general = {} }
MSUF_GetGeneralDB = function() return MSUF_DB.general end
MSUF_EM2 = {}
MSUF_EditModeAPI = { RegisterElement = function() error("external mover registered without addon") end }
InCombatLockdown = function() return false end
CreateFrame = function()
    return { RegisterEvent = function() end, SetScript = function() end }
end
load("Shell/EditMode/MSUF_EditMode_ExternalProvider.lua")
for _, name in ipairs({ "Grid2", "Details", "Dominos", "Danders", "Blizzard" }) do
    load("Shell/EditMode/MSUF_EditMode_" .. name .. ".lua")
end
if flavor == "Mainline" then
    load("Integrations/MSUF_Integration_EllesmereUnlock.lua")
    assert(MSUF_EllesmereEditMode_IsAvailable() == false)
    assert(MSUF_EllesmereEditMode_SetEnabled(false) == false)
    assert(MSUF_DB.general.ellesmereEditModeIntegration == false)
else
    assert(MSUF_EllesmereEditMode_SetEnabled == nil)
    assert(MSUF_BlizzardEditMode_SetEnabled == nil)
end
for _, name in ipairs({ "Grid2", "Details", "Dominos", "Danders" }) do
    assert(_G["MSUF_" .. name .. "EditMode_IsAvailable"]() == false)
    _G["MSUF_" .. name .. "EditMode_SetEnabled"](false)
    assert(MSUF_DB.general[name:lower() .. "EditModeIntegration"] == false)
end
-- Explicit unrelated runtime services; integration exports above are never stubbed.
local calls = {}
for name in ([[MSUF_ApplyMsufScale MSUF_TargetSoundDriver_ApplySetting MSUF_NSRTNicknames_ApplySetting
MSUF_GF_InvalidateConfCache MSUF_UFCore_NotifyConfigChanged MSUF_ApplyModules MSUF_GF_RebuildAll
MSUF_ClassPower_Apply MSUF_ApplyPowerBarEmbedLayout_All MSUF_Castbars_OnSettingsChanged
MSUF_ApplyAllCastbarsAndSync MSUF_UpdateAllFonts_Immediate MSUF_UpdateCastbarVisuals_Immediate
MSUF_ApplyCastbarVisualsForUnit]]):gmatch("%S+") do
    local key = name
    _G[key] = function() calls[key] = true end
end
ns.UF = { DisableBlizzardFrames = function() end, RefreshElements = function() end }
ns.GF = { RefreshFonts = function() end, RefreshColors = function() end, RefreshVisuals = function() end }
ns.NumberFormat = { Refresh = function() end }
load("State/MSUF_ProfileRuntime.lua")
load("Kernel/MSUF_RuntimeContracts.lua")
ns.ProfileRuntime.Apply("NO_EXTERNAL_ADDONS", false)
assert(calls.MSUF_UpdateAllFonts_Immediate, "profile apply aborted before final font pass")
-- A broken required MSUF adapter must still surface, instead of being silently skipped.
local setter = MSUF_Grid2EditMode_SetEnabled
MSUF_Grid2EditMode_SetEnabled = nil
local ok, err = pcall(load, "Kernel/MSUF_RuntimeContracts.lua")
assert(not ok and tostring(err):find("MSUF_Grid2EditMode_SetEnabled", 1, true))
MSUF_Grid2EditMode_SetEnabled = function() error("INTEGRATION_FAILURE_MARKER") end
ok, err = pcall(ns.ProfileRuntime.Apply, "BROKEN_ADAPTER", false)
assert(not ok and tostring(err):find("INTEGRATION_FAILURE_MARKER", 1, true))
MSUF_Grid2EditMode_SetEnabled = setter
print("PASS " .. flavor .. ": optional addons absent, real adapters and profile apply, errors propagate")
