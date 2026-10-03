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

---------------------------------------------------------------------------
-- 6. Class resource threshold colours on the power hot path (a Classic Rogue
--    Energy tick reaches every pip through AcceptPowerToken). Native calls per
--    event: the class resource is read once for all pips (reader + maximum, or
--    one percent), the pips past the current maximum are skipped, and a pip
--    whose colour stays is not written. Before: every allocated pip read the
--    resource, evaluated its curve and wrote its colour, 8 x 4 = 32 calls.
---------------------------------------------------------------------------
do
    local natives = 0
    local createCurve = C_CurveUtil.CreateColorCurve
    C_CurveUtil.CreateColorCurve = function()
        local curve = createCurve()
        local evaluate = curve.EvaluateUnpacked
        curve.EvaluateUnpacked = function(...) natives = natives + 1 return evaluate(...) end
        return curve
    end
    local combo = { value = 4, max = 5, restricted = false }
    local unitPowerMax, unitPowerPercent = UnitPowerMax, UnitPowerPercent
    UnitPowerMax = function(unit, powerType)
        natives = natives + 1
        if powerType == 4 then return combo.max end
        return unitPowerMax(unit, powerType)
    end
    UnitPowerPercent = function(unit, powerType, unmodified, curve)
        natives = natives + 1
        if powerType ~= 4 then return unitPowerPercent(unit, powerType, unmodified, curve) end
        if curve then return curve:Native(combo.value / combo.max) end
        if combo.restricted then return Secret() end
        return combo.value / combo.max
    end
    local setColor = M.SetStatusBarColor
    local pipWrites = {}
    M.SetStatusBarColor = function(self, ...)
        if self.pip then
            natives = natives + 1
            pipWrites[self.pip] = (pipWrites[self.pip] or 0) + 1
        end
        return setColor(self, ...)
    end
    local function Pips()
        local list = {}
        for i = 1, 8 do
            local pip = NewObject("StatusBar", container)
            pip.level, pip.pip, pip.color = 11, i, { 0.1 * i, 0.2, 0.3, 1 }
            list[i] = pip
        end
        return list
    end
    local function Tick(event, token)
        natives = 0
        for key in pairs(pipWrites) do pipWrites[key] = nil end
        Fire(event or "UNIT_POWER_FREQUENT", "player", token or "ENERGY")
        return natives
    end
    local function IsRed(pip) return pip.color[1] == 1 and pip.color[2] == 0 and pip.color[3] == 0 end
    local function IsBase(pip) return math.abs(pip.color[1] - 0.1 * pip.pip) < 1e-9 and pip.color[2] == 0.2 end
    local rule = { target = "CLASS", mode = "PERCENT", value = 60, width = 2, color = { 1, 0, 0 },
        threshold = true, direction = "ABOVE", mark = false }

    -- A client-owned class resource (a reader exists): plain values.
    local pips = Pips()
    E.CP.bars, E.CP.currentMax = pips, 5
    E.ClassPowerReader = function() natives = natives + 1 return combo.value end
    E.ClassPowerEvent = function() return "UNIT_POWER_FREQUENT" end
    E.AcceptPowerToken = function(_, token) return token == "ENERGY" end
    bars.resourceMarks = { rule }
    marks.Refresh()
    for i = 1, 5 do Check(IsRed(pips[i]), "combo points above the mark must paint pip " .. i .. " red") end
    local cost = Tick()
    Check(cost <= 2, "an Energy tick that changes no pip costs " .. cost .. " native calls, budget 2 (one read)")
    combo.value = 2
    cost = Tick()
    Check(cost <= 2 + 5, "a threshold change costs " .. cost .. " native calls, budget 7 (one read, five pips)")
    for i = 1, 5 do Check(IsBase(pips[i]), "pip " .. i .. " did not return to its own base colour") end
    Check(not pipWrites[6] and not pipWrites[7] and not pipWrites[8], "a pip past the current maximum was painted")
    -- The maximum grows in combat (the rebuild waits): the next tick paints the new pips.
    E.CP.currentMax = 7
    Tick()
    Check(IsBase(pips[6]) and IsBase(pips[7]) and not pipWrites[8], "the pips a grown maximum shows were not painted")
    -- The owner repaints a pip over the threshold colour: it is painted again.
    combo.value = 4
    Tick()
    pips[3]:SetStatusBarColor(0.9, 0.9, 0.9, 1)
    Check(IsRed(pips[3]), "an owner write over a threshold pip was not repainted")
    cost = Tick()
    Check(cost <= 2, "the tick after an owner write costs " .. cost .. " native calls, budget 2")
    -- A target change repaints with one read too.
    cost = Tick("PLAYER_TARGET_CHANGED")
    Check(cost <= 2, "a target change costs " .. cost .. " native calls, budget 2")

    -- Without a reader (Midnight): one percent read for all pips; a restricted
    -- percent needs the native curve evaluation of each shown pip.
    pips = Pips()
    E.CP.bars, E.CP.currentMax = pips, 5
    E.ClassPowerReader = nil
    combo.value, combo.restricted = 4, false
    marks.Refresh()
    cost = Tick()
    Check(cost <= 1, "a plain class percent tick costs " .. cost .. " native calls, budget 1")
    combo.restricted = true
    combo.value = 2
    cost = Tick()
    Check(cost <= 1 + 2 * 5, "a restricted class percent tick costs " .. cost .. " native calls, budget 11")
    for i = 1, 5 do Check(IsBase(pips[i]), "restricted: pip " .. i .. " did not return to its base colour") end
    Check(not pipWrites[6], "restricted: a pip past the current maximum was painted")
    combo.restricted = false

    M.SetStatusBarColor = setColor
    UnitPowerMax, UnitPowerPercent = unitPowerMax, unitPowerPercent
    C_CurveUtil.CreateColorCurve = createCurve
    E.ClassPowerReader, E.AcceptPowerToken = nil, nil
    bars.resourceMarks = {}
    marks.Refresh()
end

print("resource_marks_smoke: OK")
