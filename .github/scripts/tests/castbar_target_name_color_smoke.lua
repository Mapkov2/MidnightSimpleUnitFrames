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

_G.C_ClassColor = {
    GetClassColor = function(token)
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
local frame = {
    castTargetText = {
        SetTextColor = function(_, red, green, blue)
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
assert(visualRefreshes == 2 and targetColorRefreshes == 2,
    "reset cast-target color did not refresh live castbars")

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
