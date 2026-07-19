local root = "MidnightSimpleUnitFrames/"

local function read(path)
    local file, err = io.open(path, "rb")
    assert(file, err)
    local text = file:read("*a")
    file:close()
    return text
end

local function contains(text, needle)
    return text:find(needle, 1, true) ~= nil
end

_G.MSUF_DB = { general = {} }
_G.MSUF_EnsureDB = function() return _G.MSUF_DB end
_G.InCombatLockdown = function() return false end

local visualRefreshes = 0
local targetColorRefreshes = 0
_G.MSUF_UpdateCastbarVisuals = function() visualRefreshes = visualRefreshes + 1 end
_G.MSUF_RefreshAllCastTargetTextColors = function()
    targetColorRefreshes = targetColorRefreshes + 1
end
_G.C_Timer = {
    After = function(_, callback) callback() end,
}

local namespace = {
    Public = {},
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}
_G.MSUF = namespace

assert(loadfile(root .. "Runtime/MSUF_Colors.lua"))("MidnightSimpleUnitFrames", namespace)

local api = assert(namespace._colorsAPI)
local r, g, b, custom = api.GetCastbarTargetNameColor()
assert(r == 1 and g == 1 and b == 1 and custom == false,
    "unset cast-target color must preserve the legacy class-color fallback")

api.SetCastbarTargetNameColor(0.2, 0.4, 0.6)
r, g, b, custom = api.GetCastbarTargetNameColor()
assert(r == 0.2 and g == 0.4 and b == 0.6 and custom == true,
    "custom cast-target color did not round-trip")
assert(_G.MSUF_DB.general.castbarTargetNameR == 0.2
    and _G.MSUF_DB.general.castbarTargetNameG == 0.4
    and _G.MSUF_DB.general.castbarTargetNameB == 0.6,
    "custom cast-target color was not persisted")
assert(visualRefreshes == 1 and targetColorRefreshes == 1,
    "custom cast-target color did not refresh live castbars")

local classColorCalls = 0
_G.C_ClassColor = {
    GetClassColor = function(token)
        classColorCalls = classColorCalls + 1
        assert(token == "MAGE")
        return { GetRGB = function() return 0.25, 0.5, 0.75 end }
    end,
}
assert(loadfile(root .. "Castbars/MSUF_CastbarDriver.lua"))("MidnightSimpleUnitFrames", namespace)
local applyCastTargetTextColor = assert(_G.MSUF_ApplyCastTargetTextColor)
_G.MSUF_RefreshAllCastTargetTextColors = function()
    targetColorRefreshes = targetColorRefreshes + 1
end

local applied
local appliedCalls = 0
local frame = {
    castTargetText = {
        SetTextColor = function(_, red, green, blue)
            appliedCalls = appliedCalls + 1
            applied = { red, green, blue }
        end,
    },
}
applyCastTargetTextColor(frame, "MAGE")
assert(applied[1] == 0.2 and applied[2] == 0.4 and applied[3] == 0.6,
    "custom cast-target color did not override the target class color")

api.ResetCastbarTargetNameColor()
r, g, b, custom = api.GetCastbarTargetNameColor()
assert(r == 1 and g == 1 and b == 1 and custom == false,
    "reset cast-target color did not restore the class-color fallback")
applyCastTargetTextColor(frame, "MAGE")
assert(applied[1] == 0.25 and applied[2] == 0.5 and applied[3] == 0.75,
    "legacy target class color was not restored after reset")
applyCastTargetTextColor(frame, "MAGE")
assert(classColorCalls == 2,
    "secret target class must be resolved directly by the safe C API on each refresh")
assert(appliedCalls == 3,
    "secret target class color was cached or compared in Lua")
api.SetCastbarTargetNameColor(0.2, 0.4, 0.6)
applyCastTargetTextColor(frame, "MAGE")
assert(appliedCalls == 4 and applied[1] == 0.2 and applied[2] == 0.4 and applied[3] == 0.6,
    "class-color forwarding left the plain custom-color cache stale")
assert(visualRefreshes == 3 and targetColorRefreshes == 3,
    "cast-target color changes did not refresh live castbars")

api.ResetCastbarTargetNameColor()
local secretComparisons = 0
local secretComponentMT = {
    __eq = function()
        secretComparisons = secretComparisons + 1
        error("secret RGB comparison")
    end,
}
_G.C_ClassColor.GetClassColor = function()
    return {
        GetRGB = function()
            return setmetatable({}, secretComponentMT),
                setmetatable({}, secretComponentMT),
                setmetatable({}, secretComponentMT)
        end,
    }
end
local secretApplyStart = appliedCalls
applyCastTargetTextColor(frame, "MAGE")
applyCastTargetTextColor(frame, "MAGE")
assert(appliedCalls == secretApplyStart + 2 and secretComparisons == 0,
    "secret class RGB values entered a Lua comparison cache")

local castbarDriver = read(root .. "Castbars/MSUF_CastbarDriver.lua")
assert(contains(castbarDriver, "C_ClassColor_GetClassColor(classFilename)"),
    "cast-target class color no longer uses the secret-safe C API")
assert(contains(castbarDriver, "fs:SetTextColor(classColor:GetRGB())")
    and not contains(castbarDriver, "local red, green, blue = classColor:GetRGB()"),
    "secret class RGB values are still retained before the native setter")
assert(not contains(castbarDriver, "RAID_CLASS_COLORS[classFilename]")
    and not contains(castbarDriver, "castTargetClassColors[classFilename]"),
    "secret target class is still used as a Lua table key")

local unitPreview = read(root .. "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua")
local castbarPage = read(root .. "Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua")
local unitCastbarPreview = read(root .. "Castbars/MSUF_CastbarPreviews.lua")
local bossCastbarPreview = read(root .. "Castbars/MSUF_BossCastbars_Preview.lua")
assert(contains(unitPreview, "MSUF_GetCastbarTargetNameColor")
    and not contains(unitPreview, "mock.cast.target:SetTextColor(1, 0.82, 0.20, 1)"),
    "Unit Frame castbar preview still ignores the configured cast-target color")
assert(contains(castbarPage, "CastbarShowTargetName(unit, g)")
    and contains(castbarPage, "MSUF_GetCastbarTargetNameColor"),
    "Global Castbar preview does not show and color enabled cast-target text")
assert(contains(unitCastbarPreview, "MSUF_ApplyCastTargetTextColor(frame)"),
    "Target/Focus Edit Mode previews do not apply the cast-target color")
assert(contains(bossCastbarPreview, "MSUF_ApplyCastTargetTextColor(preview)"),
    "Boss Edit Mode preview does not apply the cast-target color")

print("castbar target name color smoke: ok")
