-- resource_marks_smoke.lua <repoRoot>
--
-- Resource marks and threshold colours (ClassPower/MSUF_CP_ResourceMarks.lua)
-- against the client's contracts:
-- 1. A restricted power percentage never enters Lua: ColorCurve:EvaluateUnpacked
--    rejects it (AllowedWhenUntainted), UnitPowerPercent(unit, power, false,
--    curve) evaluates the curve natively and its colour reaches the bar. A
--    restricted paint leaves no state behind (the base colour keeps following
--    the bar's owner).
-- 2. Marks on class resources draw above the pips: child frames draw over their
--    parent's regions, so the marks live on an overlay above pips and outline.
-- 3. Marks follow the bar's fill axis: reverse fill measures from the far edge,
--    vertical bars from the bottom (top when reversed), the signed Balance bar
--    from its middle.
-- 4. In combat, a shapeshift that changes what the Player power bar shows
--    hides that bar's marks and threshold colours without any geometry
--    change, and restores them when the bar shows the power again.
-- 5. A host resize asks the lifecycle owner for a rebuild.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local function Check(condition, message)
    if not condition then error(message, 2) end
    return condition
end

local SecretMT = {}
for _, event in ipairs({ "__add", "__sub", "__mul", "__div", "__unm", "__lt", "__le", "__eq", "__concat", "__tostring" }) do
    SecretMT[event] = function() error("restricted value used in Lua", 2) end
end
local function Secret() return setmetatable({}, SecretMT) end
local function IsSecret(value) return getmetatable(value) == SecretMT end

local combat = false
local function Geometry() Check(not combat, "frame or region geometry changed in combat") end
local frames = {}
local M = {}
M.__index = M
local function NewObject(kind, parent)
    local object = setmetatable({ kind = kind, parent = parent, events = {}, scripts = {}, shown = kind ~= "Texture",
        level = parent and (parent.level or 1) + 1 or 1, hooks = {} }, M)
    frames[#frames + 1] = object
    return object
end
function M:SetScript(name, callback) self.scripts[name] = callback end
function M:HookScript(name, callback) self.hooks[name] = callback end
function M:RegisterEvent(event) self.events[event] = true end
function M:RegisterUnitEvent(event, ...) self.events[event] = { ... } end
function M:UnregisterEvent(event) self.events[event] = nil end
function M:UnregisterAllEvents() self.events = {} end
function M:CreateTexture(_, layer, _, sublevel) local t = NewObject("Texture", self); t.layer, t.sublevel = layer, sublevel; return t end
function M:SetAllPoints(relative) Geometry(); self.allPoints = relative end
function M:SetPoint(point, relative, relativePoint, x, y) Geometry(); self.points = self.points or {}; self.points[#self.points + 1] = { point, relative, relativePoint, x or 0, y or 0 } end
function M:ClearAllPoints() Geometry(); self.points = {} end
function M:SetWidth(value) Geometry(); self.width = value end
function M:SetHeight(value) Geometry(); self.height = value end
function M:SetFrameLevel(value) Geometry(); self.level = value end
function M:GetFrameLevel() return self.level end
function M:EnableMouse(value) self.mouse = value end
function M:GetWidth() return self.w or 200 end
function M:GetHeight() return self.h or 10 end
function M:GetOrientation() return self.orientation or "HORIZONTAL" end
function M:GetReverseFill() return self.reverse == true end
function M:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function M:Show() self.shown = true end
function M:Hide() self.shown = false end
function M:SetShown(value) self.shown = value and true or false end
function M:SetStatusBarColor(r, g, b, a) self.color = { r, g, b, a }; if self.colorHook then self.colorHook(self, r, g, b, a) end end
function M:GetStatusBarColor() return unpack(self.color or { .2, .3, .4, 1 }) end
CreateFrame = function(kind, _, parent) return NewObject(kind, parent) end
hooksecurefunc = function(object, method, callback) assert(method == "SetStatusBarColor"); object.colorHook = callback end
wipe = function(t) for k in pairs(t) do t[k] = nil end end
InCombatLockdown = function() return combat end
CreateColor = function(r, g, b, a)
    return { r, g, b, a, SetRGBA = function(self, red, green, blue, alpha) self[1], self[2], self[3], self[4] = red, green, blue, alpha end }
end
Enum = { LuaCurveType = { Step = 1 } }
local function Evaluate(points, x)
    local color = points[1][2]
    for _, point in ipairs(points) do if x >= point[1] then color = point[2] end end
    return color
end
C_CurveUtil = { CreateColorCurve = function()
    return { points = {},
        SetType = function() end,
        ClearPoints = function(self) self.points = {} end,
        AddPoint = function(self, x, color) self.points[#self.points + 1] = { x, color } end,
        EvaluateUnpacked = function(self, x)
            Check(not IsSecret(x), "ColorCurve:EvaluateUnpacked rejects restricted values from addon code")
            local color = Evaluate(self.points, x)
            return color[1], color[2], color[3], color[4]
        end,
        -- What the client does inside UnitPowerPercent with a curve.
        Native = function(self, x)
            local color = Evaluate(self.points, x)
            return { GetRGB = function() return color[1], color[2], color[3] end }
        end }
end }

local power = { value = 60, max = 100, restricted = false, type = 0, token = "MANA" }
UnitPowerType = function() return power.type, power.token end
UnitPower = function() if power.restricted then return Secret() end return power.value end
UnitPowerMax = function() return power.max end
UnitPowerPercent = function(_, _, _, curve)
    if curve then return curve:Native(power.value / power.max) end
    if power.restricted then return Secret() end
    return power.value / power.max
end

MSUF_CP_CONST = { CPK = { MODE = { SIGNED_CONTINUOUS = 12 } } }
local ns = { CPBuilders = {} }
assert(loadfile(root .. "/tools/tests/classpower_collaborators.lua"))().Install(root, ns)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_ResourceMarks.lua"))("MSUF", ns)

local player = NewObject("Frame")
local bar = NewObject("StatusBar", player)
player.targetPowerBar = bar
local container = NewObject("Frame", player)
container.level = 10
local pips = {}
for i = 1, 5 do pips[i] = NewObject("StatusBar", container); pips[i].level = 11 end
local outline = NewObject("Frame", container); outline.level = 13
local bars = {}
local requests = 0
local E = { db = { bars = bars }, NotSecret = function(v) return not IsSecret(v) end,
    GetPlayerFrame = function() return player end,
    CP = { bars = pips, container = container, visible = true, powerType = 4, powerToken = "COMBO_POINTS" },
    AM = { visible = false },
    ClassPowerUnit = function() return "player" end,
    ClassPowerEvent = function() return "UNIT_POWER_UPDATE" end,
    RequestRefresh = function() requests = requests + 1 end }
local marks = ns.CPBuilders.ResourceMarks(E)
local eventFrame
for _, object in ipairs(frames) do if object.scripts and object.scripts.OnEvent == nil and object.kind == "Frame" and not object.parent then eventFrame = object end end
local function MarkTextures(host)
    local list = {}
    for _, object in ipairs(frames) do
        if object.kind == "Texture" and object.parent and object.parent.parent == host and object.parent.marks then list[#list + 1] = object end
    end
    return list
end
local function Fire(event, unit, token)
    for _, object in ipairs(frames) do
        local handler = object.scripts.OnEvent
        if handler and object.events[event] then handler(object, event, unit, token) end
    end
end

---------------------------------------------------------------------------
-- 1. Restricted percentages.
---------------------------------------------------------------------------
bars.resourceMarks = { { target = "PLAYER", resource = "MANA", mode = "PERCENT", value = 50, width = 2,
    color = { 1, 0, 0 }, threshold = true, direction = "ABOVE" } }
marks.Refresh()
Check(bar.color[1] == 1 and bar.color[2] == 0, "plain percentage above the mark must paint the threshold colour")
power.restricted, power.value = true, 20
Fire("UNIT_POWER_FREQUENT", "player", "MANA")
Check(bar.color[1] == .2 and bar.color[2] == .3, "restricted percentage below the mark must paint the base colour natively")
power.value = 90
Fire("UNIT_POWER_FREQUENT", "player", "MANA")
Check(bar.color[1] == 1 and bar.color[2] == 0, "restricted percentage above the mark must paint the threshold colour natively")
-- The owner repaints its base colour; it is followed and the threshold stays.
bar:SetStatusBarColor(.1, .5, .9, 1)
Check(bar.color[1] == 1, "a restricted paint left the colour hook blocked")
power.value = 10
Fire("UNIT_POWER_FREQUENT", "player", "MANA")
Check(bar.color[1] == .1 and bar.color[2] == .5, "the base colour change was not captured after restricted paints")
power.restricted, power.value = false, 60

---------------------------------------------------------------------------
-- 2. Class resource marks draw above the pips and their outline.
---------------------------------------------------------------------------
bars.resourceMarks = { { target = "CLASS", mode = "PERCENT", value = 40, width = 2, color = { 1, 1, 1 } } }
marks.Refresh()
local classMarks = MarkTextures(container)
Check(#classMarks == 1 and classMarks[1].shown, "class resource mark missing")
local overlay = classMarks[1].parent
Check(overlay.level > outline.level, "class resource marks are drawn below the pips or their outline")
for _, pip in ipairs(pips) do Check(overlay.level > pip.level, "class resource marks are drawn below a pip") end
Check(overlay.mouse == false, "the mark overlay takes mouse input")

---------------------------------------------------------------------------
-- 3. Placement follows the fill axis.
---------------------------------------------------------------------------
local function Expect(texture, point, relativePoint, x, y, label)
    local anchor = Check(texture.points and texture.points[1], label .. ": unanchored mark")
    Check(anchor[1] == point and anchor[3] == relativePoint and math.abs(anchor[4] - x) < 1e-6 and math.abs(anchor[5] - y) < 1e-6,
        string.format("%s: anchored %s to %s at %.2f,%.2f", label, tostring(anchor[1]), tostring(anchor[3]), anchor[4], anchor[5]))
end
bars.resourceMarks = { { target = "PLAYER", resource = "ALL", mode = "PERCENT", value = 25, width = 3, color = { 1, 1, 1 } } }
marks.Refresh()
local playerMark = MarkTextures(bar)[1]
Expect(playerMark, "TOP", "TOPLEFT", 50, 0, "horizontal bar")
Check(playerMark.width == 3, "horizontal mark width")
bar.reverse = true; marks.Refresh()
Expect(playerMark, "TOP", "TOPRIGHT", -50, 0, "reverse-filled bar")
bar.orientation, bar.reverse = "VERTICAL", false; marks.Refresh()
Expect(playerMark, "LEFT", "BOTTOMLEFT", 0, 2.5, "vertical bar")
Check(playerMark.height == 3, "vertical mark thickness")
bar.reverse = true; marks.Refresh()
Expect(playerMark, "LEFT", "TOPLEFT", 0, -2.5, "vertical top-down bar")
bar.orientation, bar.reverse = "HORIZONTAL", false
bar.orientation = Secret(); marks.Refresh()
Check(not playerMark.shown, "a restricted orientation must not place marks")
bar.orientation = nil
bars.classPowerFillReverse = true
bars.resourceMarks = { { target = "CLASS", mode = "PERCENT", value = 40, width = 2, color = { 1, 1, 1 } } }
marks.Refresh()
Expect(classMarks[1], "TOP", "TOPRIGHT", -80, 0, "reverse-filled class resource")
bars.classPowerFillReverse = false
E.CP.renderMode = 12
bars.resourceMarks = { { target = "CLASS", mode = "PERCENT", value = 50, width = 2, color = { 1, 1, 1 } } }
marks.Refresh()
Expect(classMarks[1], "TOP", "TOPLEFT", 150, 0, "signed Balance bar (50% toward the solar end)")
E.CP.renderMode = nil

---------------------------------------------------------------------------
-- 4. Shapeshift in combat.
---------------------------------------------------------------------------
bars.resourceMarks = { { target = "PLAYER", resource = "MANA", mode = "PERCENT", value = 50, width = 2,
    color = { 0, 1, 0 }, threshold = true, direction = "ABOVE" } }
bar:SetStatusBarColor(0, 0, 1, 1)
marks.Refresh()
local manaMark = MarkTextures(bar)[1]
Check(manaMark.shown and bar.color[2] == 1, "mana mark and threshold colour missing")
combat = true
power.type, power.token = 3, "ENERGY"
marks.PowerChanged()
Check(not manaMark.shown, "the mana mark stayed on the energy bar")
Check(bar.color[3] == 1 and bar.color[2] == 0, "the mana threshold colour stayed on the energy bar")
bar:SetStatusBarColor(1, 1, 0, 1)
Check(bar.color[1] == 1 and bar.color[2] == 1, "a suspended threshold repainted the energy bar")
power.type, power.token = 0, "MANA"
marks.PowerChanged()
Check(manaMark.shown and bar.color[2] == 1 and bar.color[1] == 0, "the mana mark did not return with caster form")
Check(marks.IsPending(), "combat changes must schedule the rebuild at combat end")
combat = false
Fire("PLAYER_REGEN_ENABLED")
Check(not marks.IsPending(), "the combat-end rebuild did not run")

---------------------------------------------------------------------------
-- 5. A host resize requests a rebuild.
---------------------------------------------------------------------------
requests = 0
Check(bar.hooks.OnSizeChanged, "the power bar resize is not observed")
bar.hooks.OnSizeChanged(bar)
Check(requests == 1, "a resized power bar did not request a rebuild")
bars.resourceMarks = {}
marks.Refresh()
bar.hooks.OnSizeChanged(bar)
Check(requests == 1, "a host without marks still requests rebuilds")

print("resource_marks_smoke: OK")
