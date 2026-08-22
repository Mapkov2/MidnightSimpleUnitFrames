local root = assert(arg[1], "repository root argument missing")

local callbacks = {}
local namespace = {
    UF = {
        RegisterVisualRefreshCallback = function(key, callback)
            callbacks[key] = callback
            return true
        end,
    },
}
namespace.ExportPublic = function(name, value)
    _G[name] = value
    namespace[name] = value
    return value
end

_G.hooksecurefunc = function(name, callback)
    local original = assert(_G[name], "missing hook target: " .. tostring(name))
    _G[name] = function(...)
        local results = { original(...) }
        callback(...)
        return unpack(results)
    end
end

local fillTexture = {}
local spark = {
    shown = false,
    width = 0,
    height = 0,
}
function spark:SetTexture(texture) self.texture = texture end
function spark:SetTexCoord(...) self.texCoord = { ... } end
function spark:SetDesaturated(value) self.desaturated = value end
function spark:SetVertexColor(...) self.vertexColor = { ... } end
function spark:SetBlendMode(value) self.blendMode = value end
function spark:SetShown(value) self.shown = value end
function spark:SetSize(width, height) self.width, self.height = width, height end
function spark:GetWidth() return self.width end
function spark:GetHeight() return self.height end
function spark:ClearAllPoints() self.point = nil end
function spark:SetPoint(...) self.point = { ... } end

local statusBar = { height = 2, reverse = false }
function statusBar:GetHeight() return self.height end
function statusBar:GetStatusBarTexture() return fillTexture end
function statusBar:GetReverseFill() return self.reverse end

local frame = { height = 6, statusBar = statusBar, spark = spark }
function frame:GetHeight() return self.height end

local general = {
    castbarShowSpark = true,
    castbarSparkOverflow = true,
}
_G.MSUF_DB = { general = general }
_G.MSUF_TargetCastbar = frame
_G.MSUF_BossCastbars = { frame }
_G.MSUF_ArenaCastbars = { frame }
_G.MSUF_MAX_BOSS_FRAMES = 1
_G.MSUF_MAX_ARENA_FRAMES = 1

-- Shared implementations intentionally reproduce the unsafe geometry. The
-- Classic hooks must leave the public result corrected after they return.
_G.MSUF_GetCastbarOutlineInset = function() return 6 end
_G.MSUF_ApplyCastbarSparkVisual = function(target)
    target.spark:SetSize(16, target:GetHeight() * 2.1)
end
_G.MSUF_RefreshCastbarFrame = function(target)
    target.spark:SetSize(16, target:GetHeight() * 2.1)
end
_G.MSUF_ApplyCastbarVisualsForUnit = function(unit)
    assert(unit == "target" or unit == "boss1" or unit == "arena1", "unexpected visual unit")
    _G.MSUF_RefreshCastbarFrame(frame, unit, general)
    -- Mirrors the shared Core local spark pass which runs after RefreshFrame.
    frame.spark:SetSize(16, frame:GetHeight() * 2.1)
    return "shared-result"
end
_G.MSUF_UpdateCastbarVisuals = function(unit)
    if unit then return _G.MSUF_ApplyCastbarVisualsForUnit(unit) end
end
_G.MSUF_UpdateCastbarVisuals_Immediate = _G.MSUF_UpdateCastbarVisuals
_G.MSUF_ApplyAllCastbarsAndSync = function()
    return _G.MSUF_ApplyCastbarVisualsForUnit("target")
end

local compatPath = root .. "/MidnightSimpleUnitFrames/Game/Classic/Castbars/MSUF_CastbarVisualCompat.lua"
assert(loadfile(compatPath))("MidnightSimpleUnitFrames", namespace)

local inset = assert(_G.MSUF_ClassicCastbar_GetOutlineInset)(frame, general)
assert(inset == 2, "6px Classic castbar did not retain a 2px drawable inner surface")

_G.MSUF_ClassicCastbar_ApplySparkVisual(frame, general)
assert(spark.texture == "Interface\\CastingBar\\UI-CastingBar-Spark",
    "Classic castbar did not use Blizzard's Classic spark texture")
assert(spark.texCoord[1] == 0 and spark.texCoord[2] == 1
    and spark.texCoord[3] == 0 and spark.texCoord[4] == 1,
    "Classic spark retained the Retail atlas crop")
assert(spark.shown == true and spark.width == 16 and math.abs(spark.height - 4.2) < 0.001,
    "overflow spark was not sized from the 2px inner statusbar")
assert(spark.point and spark.point[3] == "RIGHT", "normal fill spark lost the moving right edge")

statusBar.reverse = true
_G.MSUF_ClassicCastbar_ApplySparkVisual(frame, general)
assert(spark.point and spark.point[3] == "LEFT", "reverse fill spark lost the moving left edge")

general.castbarSparkOverflow = false
_G.MSUF_ClassicCastbar_ApplySparkVisual(frame, general)
assert(spark.height == 2, "non-overflow spark did not match the inner statusbar height")

general.castbarSparkOverflow = true
local result = _G.MSUF_ApplyCastbarVisualsForUnit("target", true, general)
assert(result == "shared-result", "Classic post-hook changed the shared return value")
assert(math.abs(spark.height - 4.2) < 0.001,
    "Classic post-hook did not correct the shared outer-frame spark size")

assert(type(callbacks.Castbars) == "function", "Classic visual callback did not replace the shared closure")
callbacks.Castbars("target")
assert(math.abs(spark.height - 4.2) < 0.001,
    "visual callback bypassed the final Classic spark geometry")

spark.height = 12.6
callbacks.Castbars("boss1")
assert(math.abs(spark.height - 4.2) < 0.001,
    "boss table castbar bypassed the final Classic spark geometry")
spark.height = 12.6
callbacks.Castbars("arena1")
assert(math.abs(spark.height - 4.2) < 0.001,
    "arena table castbar bypassed the final Classic spark geometry")

general.castbarShowSpark = false
_G.MSUF_ClassicCastbar_ApplySparkVisual(frame, general)
assert(spark.shown == false, "disabled Classic spark remained visible")

for _, tocName in ipairs({ "Vanilla", "Mists", "TBC" }) do
    local tocPath = root .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_" .. tocName .. ".toc"
    local file = assert(io.open(tocPath, "rb"))
    local source = file:read("*a")
    file:close()
    local rounded = assert(source:find("Castbars\\MSUF_CastbarRounded.lua", 1, true),
        tocName .. " castbar rounded entry missing")
    local compat = assert(source:find("Game\\Classic\\Castbars\\MSUF_CastbarVisualCompat.lua", 1, true),
        tocName .. " Classic castbar compatibility entry missing")
    assert(rounded < compat, tocName .. " loaded Classic castbar compatibility before shared visuals")
end

local mainlineFile = assert(io.open(
    root .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc", "rb"))
local mainlineSource = mainlineFile:read("*a")
mainlineFile:close()
assert(not mainlineSource:find("MSUF_CastbarVisualCompat.lua", 1, true),
    "Classic castbar compatibility leaked into the Retail-identical Mainline TOC")

print("classic castbar visual compat smoke passed")
