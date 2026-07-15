local root = arg and arg[1] or "."
local path = root .. "/MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_GameplayRuntime.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

local function Has(fragment, message)
    assert(source:find(fragment, 1, true), message)
end

Has("local crosshairZoomHooksInstalled = false", "zoom hook ownership guard is missing")
Has("local function InstallCombatCrosshairZoomHooks()", "zoom hook installer is missing")
Has('for _, name in ipairs({ "CameraZoomIn", "CameraZoomOut" }) do', "camera zoom APIs are not both observed")
Has("_G.hooksecurefunc(name, CameraZoomChanged)", "camera zoom observation is not secure-hook based")
Has("g.enableCombatCrosshair == true and MSUF_ShouldCrosshairFollowCamera()", "zoom hook lacks disabled/follow-camera gate")
Has("ScheduleCombatCrosshairAnchor()", "zoom hook does not coalesce anchor work")
Has('event == "CVAR_UPDATE" and (arg1 == "nameplateShowSelf" or arg1 == "cameraDistanceMaxZoomFactor")',
    "camera-distance CVar changes do not refresh the anchor")
Has("InstallCombatCrosshairZoomHooks()", "crosshair creation does not install zoom hooks")

local crosshairStart = assert(source:find("local function EnsureCombatCrosshair()", 1, true))
local crosshairEnd = assert(source:find("local function ApplyCombatStateText", crosshairStart, true))
local crosshairRuntime = source:sub(crosshairStart, crosshairEnd - 1)
assert(not crosshairRuntime:find('SetScript("OnUpdate"', 1, true), "crosshair zoom tracking added an OnUpdate loop")

print("PASS combat crosshair zoom contract: event-driven hooks, CVar repair, no OnUpdate")
