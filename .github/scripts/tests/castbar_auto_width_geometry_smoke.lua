local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function Near(actual, expected, message)
    if math.abs((actual or 0) - expected) > 0.000001 then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

_G.UIParent = {}
_G.MSUF_DB = {
    general = {
        castbarTargetMatchWidth = "unitframe",
        castbarTargetBarHeight = 18,
    },
}
_G.EnsureDB = function() end
_G.MSUF_ShouldUseMSUFCastbar = function() return true end
_G.MSUF_InCombat = false
_G.InCombatLockdown = function() return false end
_G.UnitAffectingCombat = function() return false end
_G.C_Timer = { After = function() end }
_G.CreateFrame = function()
    return {
        RegisterEvent = function() end,
        UnregisterAllEvents = function() end,
        SetScript = function() end,
    }
end

local health = {
    GetWidth = function() return 280 end,
    GetEffectiveScale = function() return 0.75 end,
    GetScaledRect = function() return 100, 0, 210, 20 end,
    HookScript = function() end,
}
local unitframe = {
    unit = "target",
    MSUFUnitKey = "target",
    hpBar = health,
    _msufBorderRuntimeNormal = true,
    _msufBorderRuntimeNormalThickness = 1,
    GetWidth = function() return 280 end,
    GetHeight = function() return 36 end,
    GetEffectiveScale = function() return 0.75 end,
    GetScaledRect = function() return 100, 0, 210, 27 end,
    HookScript = function() end,
}
local namespace = {
    UF = {
        frames = { target = unitframe },
        GetFrame = function(unit) return unit == "target" and unitframe or nil end,
    },
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}
_G.MSUF_NS = namespace

local chunk, loadError = loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarAnchors.lua")
Check(chunk ~= nil, loadError)
chunk("MidnightSimpleUnitFrames", namespace)

local castbar = {
    width = 0,
    height = 0,
    GetEffectiveScale = function() return 1 end,
    SetWidth = function(self, value) self.width = value end,
    SetHeight = function(self, value) self.height = value end,
}
local general = _G.MSUF_DB.general

Check(_G.MSUF_GetCastbarUnitframeWidthSource("target") == health,
    "Auto Width did not select the visible health geometry")
local offsetX = _G.MSUF_GetCastbarAutoAnchorOffsetX(general, "target", castbar)
local width, height, preserveWidth = _G.MSUF_GetCastbarDesiredSize("target", general, castbar, 240, 18)
Near(offsetX, -0.75, "normal outside border was not included in the left edge")
Near(width, 211.5, "normal outside border was not included in Auto Width")
Check(preserveWidth == true, "Auto Width lost its exact-width marker")
Near(100 + offsetX + width, 310.75, "Auto Width right edge does not match the unitframe")

_G.MSUF_Snap = function(_, value) return math.floor(value) end
_G.MSUF_ApplyPlayerCastbarSizeAndLayout(castbar, general, width, height, preserveWidth)
Near(castbar.width, 211.5, "Auto Width was rounded a second time")

unitframe._msufBorderRuntimeNormal = nil
unitframe._msufBorderRuntimeNormalThickness = nil
unitframe.MSUFSpec = { border = { enabled = false, thickness = 0 } }
offsetX = _G.MSUF_GetCastbarAutoAnchorOffsetX(general, "target", castbar)
width = _G.MSUF_GetCastbarDesiredSize("target", general, castbar, 240, 18)
Near(offsetX, 0, "border-off Auto Width retained a border offset")
Near(width, 210, "border-off Auto Width retained border width")

general.castbarTargetMatchWidth = nil
general.castbarTargetBarWidth = 211.5
Check(_G.MSUF_GetCastbarAutoAnchorOffsetX(general, "target", castbar) == 0,
    "manual width received an automatic anchor correction")
local manualWidth, manualHeight, manualPreserve = _G.MSUF_GetCastbarDesiredSize(
    "target", general, castbar, 240, 18)
Check(manualPreserve == false, "manual width was marked exact-source width")
_G.MSUF_ApplyPlayerCastbarSizeAndLayout(castbar, general, manualWidth, manualHeight, manualPreserve)
Check(castbar.width == 211, "manual width no longer uses the existing snap behavior")

print("castbar auto width geometry smoke: ok")
