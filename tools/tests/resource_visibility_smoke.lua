-- Separate alpha gates, native secret curves, parent restoration and hidden
-- Player power updates. No live WoW behavior is simulated by the assertions.
local root = assert(arg[1])
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
Secrets.Install()
local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()
local barsPath = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua"
local resolver = Slice.Function(Slice.Read(barsPath), "local function ResolveDisplayedPowerIdentity", barsPath)
local ResolvePower
local frames, listeners = {}, {}
local combat, affecting, power, maximum, health = false, false, 50, 100, 50
local powerPaints, textPaints = 0, 0
local powerType, powerTypeReads, powerReads, percentReads = 3, 0, 0, 0
local function Frame(parent)
    local f = { parent = parent, alpha = 1, shown = true, scale = 1, events = {}, scripts = {} }
    function f:GetParent() return self.parent end
    function f:SetParent(value) assert(not combat and not affecting, "parent changed in combat"); self.parent = value end
    function f:GetScale() return self.scale end
    function f:SetScale(value) self.scale = value end
    function f:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
    function f:SetAlpha(value) self.alpha = value end
    function f:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function f:SetAllPoints() end
    function f:EnableMouse() end
    function f:RegisterEvent(event) self.events[event] = true end
    function f:RegisterUnitEvent(event, unit) assert(unit == "player"); self.events[event] = true end
    function f:UnregisterAllEvents() self.events = {} end
    function f:SetScript(event, fn) assert(event ~= "OnUpdate", "visibility added polling"); self.scripts[event] = fn end
    frames[#frames + 1] = f
    return f
end
UIParent = Frame()
local hider, player = Frame(UIParent), Frame(UIParent)
local visual = Frame(player)
player._msufHealthVisualRoot = visual
player.MSUFUnitKey = "player"
player.MSUFSpec = { enabled = true, power = { enabled = true, detached = true } }
function CreateFrame(_, _, parent) return Frame(parent) end
function InCombatLockdown() return combat end
function UnitAffectingCombat() return affecting end
function UnitPowerType() powerTypeReads = powerTypeReads + 1; return powerType end
function UnitPower() powerReads = powerReads + 1; return power end
function UnitPowerMax() return maximum end
function UnitHealth() return health end
function UnitHealthMax() return maximum end
local ns = { UFBarTextCommon = { ResolveDisplayedPowerIdentity = ResolvePower },
    UF = { GetPetBattleFrameHider = function() return hider end, elements = {
    Power = { Update = function(_, _, _, token)
        powerPaints = powerPaints + 1
        return power, maximum, 3, token, false
    end },
    PowerText = { Update = function() textPaints = textPaints + 1 end },
} } }
ns.ExportPublic = function(name, value) _G[name] = value end
-- This section tests only ResourceVisibility with its injected Power painters;
-- the real controller/UF lifecycle is exercised in the per-client section below.
assert(loadfile(root .. "/tools/tests/classpower_collaborators.lua"))().Install(root, ns, false)
ResolvePower = assert(loadstring("local MSUF, POWER_TYPE_MANA = ..., 0\n" .. resolver
    .. "\nreturn ResolveDisplayedPowerIdentity"))(ns)
ns.UFBarTextCommon.ResolveDisplayedPowerIdentity = ResolvePower
MSUF_DB = { bars = {} }
MSUF_PixelLayoutRegion = function(region) return region end
assert(loadfile(root .. "/tools/tests/require_fixture.lua"))().Install(root, ns)
function MSUF_RegisterAnyEditModeListener(fn) listeners[#listeners + 1] = fn end
local path = root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Visibility.lua"
assert(loadfile(path))("MSUF", ns)
local stopWatch = Secrets.Watch(path, { strict = true })
local V, b = ns.ResourceVisibility, MSUF_DB.bars
local function Fire(event, unit, token)
    for _, f in ipairs(frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, unit, token) end
    end
end
local function Events()
    local count = 0
    for _, f in ipairs(frames) do for _ in pairs(f.events) do count = count + 1 end end
    return count
end
local function Edit(active)
    MSUF_UnitEditModeActive = active
    for _, fn in ipairs(listeners) do fn(active) end
end
local hp, mana, class, extra = Frame(visual), Frame(visual), Frame(visual), Frame(player)
local count = #frames
V.Bind(hp, visual, b, "playerHPBar", "health")
assert(#frames == count and Events() == 0, "disabled defaults created an event owner")
b.playerHPBarHideOOC = true
V.Bind(hp, visual, b, "playerHPBar", "health")
assert(hp.alpha == 0 and player.alpha == 1, "health rule changed the Player frame")
affecting = true -- PLAYER_REGEN_DISABLED precedes lockdown.
Fire("PLAYER_REGEN_DISABLED")
assert(hp.alpha == 1, "combat entry did not reveal Health")
affecting = false
Fire("PLAYER_REGEN_ENABLED")
assert(hp.alpha == 0, "combat exit did not hide Health")
Edit(true)
assert(hp.alpha == 1, "Edit Mode did not bypass auto-hide")
Edit(false)
assert(hp.alpha == 0, "Edit Mode exit did not restore auto-hide")
b.playerHPBarHideOOC = false
b.playerHPBarHideWhenFull = true
V.Bind(hp, visual, b, "playerHPBar", "health")
health = 100; Fire("UNIT_HEALTH", "player")
assert(hp.alpha == 0)
health = 99; Fire("UNIT_HEALTH", "player")
assert(hp.alpha == 1)
b.altManaHideWhenEmpty = true
V.Bind(mana, visual, b, "altMana", "mana")
power = 0; Fire("UNIT_POWER_UPDATE", "player", "MANA")
assert(mana.alpha == 0 and hp.alpha == 1, "resource rules leaked into another resource")
power = 1; Fire("UNIT_POWER_UPDATE", "player", "MANA")
assert(mana.alpha == 1)
-- The fallback must never compare restricted values.
power, maximum, health = Secrets.New("number"), Secrets.New("number"), Secrets.New("number")
Fire("UNIT_POWER_UPDATE", "player", "MANA")
Fire("UNIT_HEALTH", "player")
assert(hp.alpha == 1 and mana.alpha == 1, "restricted fallback invented a full/empty result")
-- A native curve's secret alpha goes straight to the native setter.
local alpha = Secrets.New("number")
Enum = { LuaCurveType = { Step = 1 } }
C_CurveUtil = { CreateCurve = function()
    return { points = {}, SetType = function(self, kind) assert(kind == Enum.LuaCurveType.Step) end,
        AddPoint = function(self, x, y) self.points[#self.points + 1] = { x, y } end,
        Evaluate = function(self, value)
            local result = self.points[1][2]
            for _, point in ipairs(self.points) do
                if value >= point[1] then result = point[2] end
            end
            return result
        end }
end }
function UnitHealthPercent(_, _, curve) assert(curve); return alpha end
function UnitPowerPercent(_, _, _, curve) assert(curve); return alpha end
Fire("UNIT_HEALTH", "player")
assert(rawequal(hp.alpha, alpha), "health curve result was interpreted in Lua")
Fire("UNIT_POWER_UPDATE", "player", "MANA")
assert(rawequal(mana.alpha, alpha), "power curve result was interpreted in Lua")
UnitHealthPercent, UnitPowerPercent = nil, nil
power, maximum, health = 50, 100, 50
b.classPowerIndependentVisibility = true
class.alpha = .4
V.Bind(class, visual, b, "classPower", "class")
assert(class.parent == hider and class.alpha == .4, "Class Resource alpha ownership was replaced")
visual.scale = .8
V.Bind(class, visual, b, "classPower", "class")
assert(class.scale == .8, "independent resource lost its owner's scale")
visual.scale = .6
V.Bind(class, visual, b, "classPower", "class")
assert(class.scale == .6, "scale changes stopped at the independent parent")
visual.scale = 1
player.shown = false
assert(class:IsVisible(), "independent resource still follows hidden Player")
assert(not hp:IsVisible(), "default Health visibility was detached")
b.classPowerIndependentVisibility = false
V.Bind(class, visual, b, "classPower", "class")
assert(class.parent == visual and not class:IsVisible(), "return to inherited visibility failed")
b.playerHPBarIndependentVisibility = true
combat, affecting = true, true
V.Bind(hp, visual, b, "playerHPBar", "health")
assert(hp.parent == visual, "protected hierarchy changed during combat")
combat, affecting = false, false
Fire("PLAYER_REGEN_ENABLED")
assert(hp.parent == hider and hp:IsVisible(), "pending parent was not applied after combat")
b.resourceExtraHideOOC = true
b.resourceExtraIndependentVisibility = true
V.BindExtra(extra, player, b)
assert(extra.parent == hider and extra.alpha == 0 and player.alpha == 1)
Fire("PLAYER_REGEN_DISABLED")
assert(extra.alpha == 1 and extra:IsVisible())
V.ClearExtras()
assert(extra.parent == player and extra.alpha == 1, "extras did not restore their host")
player.targetPowerBar, player.powerBarBG = Frame(visual), Frame(visual)
player.MSUFPowerTextLayer = Frame(visual)
local border, trail1, trail2 = Frame(visual), Frame(visual), Frame(visual)
player.targetPowerBar.MSUFPowerBorderHost = border
player.powerLossTrail = { _msufLossTrailPool = { trail1, trail2 } }
b.playerPowerIndependentVisibility = true
b.playerPowerHideOOC = true
V.ConfigurePower(player)
local host = assert(player._msufPowerVisibilityHost)
assert(host.parent == hider and host.alpha == 0)
for _, region in ipairs({ player.targetPowerBar, player.powerBarBG, player.MSUFPowerTextLayer, border, trail1, trail2 }) do
    assert(region.parent == host, "power sibling escaped the visibility gate")
end
Fire("UNIT_POWER_UPDATE", "player", "ENERGY")
assert(powerPaints == 1 and textPaints == 1, "hidden Player stopped detached power/text updates")
Fire("UNIT_HEALTH", "player")
assert(powerPaints == 1, "health events repainted unrelated Player power")
player.shown = true
Fire("UNIT_POWER_UPDATE", "player", "ENERGY")
assert(powerPaints == 1, "visible Player power was painted twice")
-- Use the real bar/text resolver: normal Energy/Rage needs its current type,
-- while explicit Mana and class-resource hand-offs override that same input.
b.playerPowerHideOOC = false
V.Unbind(hp); V.Unbind(mana)
local nativePercent = function(unit, kind, unmodified, curve)
    assert(unit == "player" and kind == powerType and unmodified == true)
    percentReads = percentReads + 1
    return curve:Evaluate(power / maximum)
end
for _, native in ipairs({ false, true }) do
    UnitPowerPercent = native and nativePercent or nil
    for _, kind in ipairs({ 3, 1 }) do
        powerType = kind
        for _, rule in ipairs({ { true, false }, { false, true }, { true, true } }) do
            b.playerPowerHideWhenFull, b.playerPowerHideWhenEmpty = rule[1], rule[2]
            power, maximum = 50, 100
            V.ConfigurePower(player)
            for _, value in ipairs({ 100, 99, 0, 1, 50 }) do
                power = value
                local typesBefore, powersBefore, percentsBefore = powerTypeReads, powerReads, percentReads
                Fire("UNIT_POWER_UPDATE", "player", kind == 3 and "ENERGY" or "RAGE")
                local hidden = (rule[1] and value == 100) or (rule[2] and value == 0)
                assert(host.alpha == (hidden and 0 or 1), "Player Power full/empty transition failed")
                assert(powerTypeReads - typesBefore == 1, "visibility repeated its native power-type query")
                assert(powerReads - powersBefore == (native and 0 or 1), "visibility raw-value query budget changed")
                assert(percentReads - percentsBefore == (native and 1 or 0), "visibility native curve query budget changed")
            end
            maximum = 50
            Fire("UNIT_MAXPOWER", "player")
            assert(host.alpha == (rule[1] and 0 or 1), "power maximum change missed full-state visibility")
            Edit(true)
            assert(host.alpha == 1, "Edit Mode did not reveal full Player Power")
            Edit(false)
            assert(host.alpha == (rule[1] and 0 or 1), "Edit Mode exit lost Player Power auto-hide")
        end
    end
end
UnitPowerPercent = nil
powerType, power, maximum = 3, 100, 100
b.playerPowerHideWhenFull, b.playerPowerHideWhenEmpty = true, false
V.ConfigurePower(player)
assert(host.alpha == 0, "configure did not hide already-full Player Power")
powerType, power = 1, 0
b.playerPowerHideWhenFull, b.playerPowerHideWhenEmpty = false, true
Fire("UNIT_DISPLAYPOWER", "player")
V.ConfigurePower(player)
assert(host.alpha == 0, "configure did not hide already-empty Player Power")
for index = 1, 3 do
    ns.ClassPowerOwnership:SetDisplay(index == 1, index == 2, index == 3)
    local savedPower = UnitPower
    UnitPower = function(_, kind) assert(kind == 0, "auto-hide ignored displayed Mana ownership"); return power end
    Fire("UNIT_POWER_UPDATE", "player", "MANA")
    assert(host.alpha == 0, "empty displayed Mana remained visible")
    power = 1; Fire("UNIT_POWER_UPDATE", "player", "MANA")
    assert(host.alpha == 1, "displayed Mana did not return after gaining power")
    UnitPower, power = savedPower, 0
    ns.ClassPowerOwnership:SetDisplay(false, false, false)
end
powerType, power = 3, Secrets.New("number")
Fire("UNIT_POWER_UPDATE", "player", "ENERGY")
assert(host.alpha == 1, "restricted Player Power fallback invented an empty result")
UnitPowerPercent = function(_, kind, _, curve) assert(kind == 3 and curve); return alpha end
Fire("UNIT_POWER_UPDATE", "player", "ENERGY")
assert(rawequal(host.alpha, alpha), "Player Power interpreted a native secret alpha")
UnitPowerPercent, power = nil, 50
player._msufPowerEbonMight = true
Fire("UNIT_POWER_UPDATE", "player", "ENERGY")
assert(host.alpha == 1, "power rules hid the Ebon Might duration carrier")
player._msufPowerEbonMight = nil
player.MSUFSpec.power.detached = false
V.ConfigurePower(player)
assert(player.targetPowerBar.parent == visual and player.MSUFPowerTextLayer.parent == visual,
    "inline power retained detached visibility ownership")
Fire("UNIT_POWER_UPDATE", "player", "ENERGY")
assert(powerPaints == 1, "resource visibility updated embedded Power")
V.Unbind(hp); V.Unbind(mana); V.Unbind(class)
assert(Events() == 0, "disabled resources kept event subscriptions")
local violations = stopWatch()
assert(#violations == 0, table.concat(violations, "\n"))

-- The real per-client controllers must bind Class Resource, Health and Mana
-- independently, including when Class Resource itself is switched off.
MSUF_RegisterAnyEditModeListener, C_CurveUtil = nil, nil
local World = assert(loadfile(root .. "/tools/tests/classpower_world.lua"))()
local sharedPath = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Shared.lua"
local shared = Slice.Read(sharedPath)
local function SharedFunction(name)
    local source = Slice.Function(shared, "local function " .. name, sharedPath)
    return assert(loadstring(source .. "\nreturn " .. name))()
end
for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists" }) do
    local t = World.Start(root, flavor, "ROGUE", 1, World.PT.ENERGY, {
        classPowerIndependentVisibility = true,
        playerHPBarEnabled = true, playerHPBarIndependentVisibility = true,
        playerHPBarHideWhenFull = true,
        showAltMana = true, altManaIndependentVisibility = true, altManaHideWhenEmpty = true,
    }, { beforeLoad = function()
        UnitAffectingCombat = function() return false end
        MSUF_UF_NormalizePlayerHPShape = SharedFunction("NormalizePlayerHPShape")
        MSUF_UF_ShapeOutlineAlpha = SharedFunction("ShapeOutlineAlpha")
    end })
    assert(t.CP.container:GetParent() == UIParent, flavor .. ": Class Resource still inherits Player visibility")
    local hpFrame = assert(MSUF_ClassPowerPlayerHealthBar)
    local manaFrame = assert(MSUF_AltManaContainer)
    assert(hpFrame:GetParent() == UIParent and manaFrame:GetParent() == UIParent,
        flavor .. ": controller did not bind independent Health/Mana")
    t.S.health = t.S.healthMax
    for _, frame in ipairs(t.env.frames) do
        if frame.events.UNIT_HEALTH and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, "UNIT_HEALTH", "player") end
    end
    assert(hpFrame.alpha == 0 and manaFrame.alpha == 1, flavor .. ": Health auto-hide leaked into Mana")
    MSUF_DB.bars.showClassPower = false
    t.ns.PublicGlobals.MSUF_ClassPower_Refresh() -- a namespace-only export of this client's world, not a global
    assert(hpFrame.shown and manaFrame.shown, flavor .. ": disabling Class Resource disabled independent resources")
    t.module.Disable()
end
print("resource_visibility_smoke: OK")
