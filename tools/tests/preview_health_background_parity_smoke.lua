-- preview_health_background_parity_smoke.lua <repoRoot> <flavor>
--
-- The Options previews must paint the health bar background like the live frame does for the same health: a
-- "Health gradient" background follows the health the preview shows, and "Match health" follows the bar colour the
-- preview paints. Offline twin-paint checks only ever ran the default background (a fixed tint), so a gradient that
-- stayed a fixed fallback green (group cell, no unit) or read the live unit's health (unit preview) went unseen.
--
--   1. Unit preview, player: the gradient background is the colour of the fraction the bar shows, for a readable and
--      for an unreadable current health, and the paint asks the client for no health percent.
--   2. Group preview cell: the same, for the health the cell mirrors and for the stylized sample.
--   3. Group preview cell, "Match health": the background follows the class colour the cell paints.
--
-- Plain Lua 5.1 with the repo root and a client matrix Suffix (or Forever).

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local client = assert(arg and arg[2], "flavor required (a client matrix Suffix or Forever)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil, "preview_health_background_parity_smoke boots the real TOC graph; run it with plain Lua 5.1")

local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

-- The harness answers every curve and percent API with an opaque stub; the colour checks need real numbers. A linear
-- colour curve and the native percent read of a live unit, installed before the core loads (the core captures them).
local live = { current = nil, max = 900000 }
local percentCalls = 0
local function InstallCurves(world)
    local env = world.env
    -- One distinct colour per class (the sandbox answers every class with the same stub).
    env.RAID_CLASS_COLORS = {}
    for index, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE",
        "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }) do
        env.RAID_CLASS_COLORS[class] = { r = index / 20, g = 1 - index / 20, b = 0.5 }
    end
    env.Enum = env.Enum or {}
    env.Enum.LuaCurveType = { Linear = 0, Cosine = 1, Constant = 2, Cubic = 3 }
    env.CurveConstants = { ScaleTo100 = { curve = "scale" }, ReverseTo100 = { curve = "reverse" } }
    local Color = {}
    Color.__index = Color
    function Color:GetRGB() return self.r, self.g, self.b end
    function Color:GetRGBA() return self.r, self.g, self.b, self.a end
    env.CreateColor = function(r, g, b, a) return setmetatable({ r = r, g = g, b = b, a = a or 1 }, Color) end
    local Curve = {}
    Curve.__index = Curve
    function Curve:SetType(kind) self.kind = kind end
    function Curve:GetType() return self.kind or 0 end
    function Curve:AddPoint(x, y) self.points[#self.points + 1] = { x, y } end
    function Curve:Evaluate(x)
        local p = self.points
        if x <= p[1][1] then return p[1][2] end
        for i = 2, #p do
            if x <= p[i][1] then
                local t = (x - p[i - 1][1]) / (p[i][1] - p[i - 1][1])
                local a, b = p[i - 1][2], p[i][2]
                if type(a) == "table" then
                    return env.CreateColor(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
                end
                return a + (b - a) * t
            end
        end
        return p[#p][2]
    end
    function Curve:EvaluateUnpacked(x)
        local v = self:Evaluate(x)
        if type(v) == "table" then return v.r, v.g, v.b, v.a end
        return v
    end
    env.C_CurveUtil = {
        CreateCurve = function() return setmetatable({ points = {}, kind = 0 }, Curve) end,
        CreateColorCurve = function() return setmetatable({ points = {}, kind = 0 }, Curve) end,
    }
    -- The live unit is always at full health for the percent read: a preview that asks for it shows 100%.
    env.UnitHealthPercent = function(_, _, curve)
        percentCalls = percentCalls + 1
        if curve == nil or curve == env.CurveConstants.ScaleTo100 then return 100 end
        if curve == env.CurveConstants.ReverseTo100 then return 0 end
        if type(curve) == "table" and curve.Evaluate then return curve:Evaluate(1) end
        return 1
    end
end

local mw = MenuWorld.Open(root, client, { page = "home", beforeCore = InstallCurves })
local env, core, M = mw.env, mw.core, mw.M
local Preview = core.UFPreview

local function Check(condition, message)
    if not condition then error(client .. ": " .. message, 2) end
end
local function Near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-4 end
local function Text(c) return c and string.format("%.3f/%.3f/%.3f", c[1] or -1, c[2] or -1, c[3] or -1) or "nil" end

-- The configured gradient (low, middle and high stops of the compiled spec) at a fraction, without the engine.
local function Gradient(health, fraction)
    local lo = { health.gradientLowR, health.gradientLowG, health.gradientLowB }
    local mid = { health.gradientMidR, health.gradientMidG, health.gradientMidB }
    local hi = { health.gradientHighR, health.gradientHighG, health.gradientHighB }
    local from, to, t
    if fraction <= 0.5 then from, to, t = lo, mid, fraction * 2 else from, to, t = mid, hi, (fraction - 0.5) * 2 end
    return { from[1] + (to[1] - from[1]) * t, from[2] + (to[2] - from[2]) * t, from[3] + (to[3] - from[3]) * t }
end
local function CheckColor(label, actual, expected)
    Check(actual and Near(actual[1], expected[1]) and Near(actual[2], expected[2]) and Near(actual[3], expected[3]),
        label .. ": painted " .. Text(actual) .. ", expected " .. Text(expected))
end

-- A player the client can read: it exists, has a maximum health and (when readable) a current health.
env.UnitExists = function() return true end
env.UnitHealthMax = function() return live.max end
env.UnitHealth = function() return live.current end
local general = env.MSUF_DB.general
general.barMode, general.darkMode, general.enableHealthGradient = "dark", true, true
general.barBgColorMode = "health_gradient"
core.UF.Config.RefreshSettingsCache()

-- 1. Unit preview ------------------------------------------------------------
local selected = "player"
local panel = env.CreateFrame("Frame", nil, env.UIParent)
panel._msufGetCurrentKey = function() return selected end
local box = Preview._BuildPreview(env.UIParent, panel, 900, 400)
MenuWorld.FireVisibilityScripts(box)
box:Show()
box.canvas:SetSize(600, 260)
local function UnitBackground(label)
    percentCalls = 0
    Preview.Refresh(box, "SETTINGS")
    mw:RunTimers()
    local frame = box._unitScene:Frame()
    local bar, bg = frame.hpBar, frame.hpBarBG
    Check(bar and bg and bar.maximum and bar.maximum > 0, label .. ": the unit scene has no health bar or background")
    local fraction = bar.value / bar.maximum
    CheckColor(label .. " unit gradient background", bg.vertexColor, Gradient(frame.MSUFSpec.health, fraction))
    Check(percentCalls == 0, label .. ": the unit scene asked the client for a health percent " .. percentCalls .. " times")
    return fraction
end
live.current = nil
local sampleFraction = UnitBackground("unreadable current health")
Check(sampleFraction > 0.5 and sampleFraction < 0.95, "harness: the stylized fraction is not a partial health (" .. tostring(sampleFraction) .. ")")
live.current = 450000
Check(Near(UnitBackground("readable current health"), 0.5), "the unit preview is not at the live health fraction")

-- 2. Group preview cell ------------------------------------------------------
M.gfScope = "party"
core.GF.InvalidateCompiledSpecs("party")
local gbox = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
gbox:Show()
gbox._stage:SetSize(600, 220)
local function CellBackground(label)
    gbox:Refresh("SETTINGS")
    mw:RunTimers()
    local cell = gbox._mock._cell
    Check(cell and cell.hpBar and cell.hpBarBG and cell.hpBar.maximum and cell.hpBar.maximum > 0, label .. ": the group cell has no health bar or background")
    local fraction = cell.hpBar.value / cell.hpBar.maximum
    CheckColor(label .. " group gradient background", cell.hpBarBG.vertexColor, Gradient(cell.MSUFSpec.health, fraction))
    return cell, fraction
end
live.current = 450000
local _, mirrored = CellBackground("readable current health")
Check(Near(mirrored, 0.5), "harness: the group cell does not mirror the live health (" .. tostring(mirrored) .. ")")
live.current = nil
local _, stylized = CellBackground("unreadable current health")
Check(not Near(stylized, 0.5), "harness: the group cell kept the mirrored health without a readable current value")

-- 3. "Match health" follows the colour the cell paints ----------------------------
general.barMode, general.darkMode, general.barBgColorMode = "class", false, "match_health"
core.UF.Config.RefreshSettingsCache()
core.GF.InvalidateCompiledSpecs("party")
live.current = 450000
gbox:Refresh("SETTINGS")
mw:RunTimers()
do
    local cell = gbox._mock._cell
    local fill = cell.hpBar.color
    Check(fill and cell.MSUFSpec.health.backgroundColorMode == "match_health", "harness: the cell is not in Match health mode")
    CheckColor("Match health group background", cell.hpBarBG.vertexColor, fill)
end
gbox:Hide()
box:Hide()
print("preview_health_background_parity_smoke: PASS (" .. client .. ")")
