-- The real unit-frame graph owns visibility, geometry and the compiled power routes.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = dofile(root .. "/tools/tests/menu_core_world.lua")
local current, maximum, hasResource = 0, 100, false
local presenceReads, valueReads = 0, 0
local secret, displayType, displayToken = {}, 0, "MANA"
local function TestUnit(unit) return unit == "target" or unit == "targettarget" end
local mw = MenuWorld.Open(root, flavor, { page = "uf_target", beforeCore = function(world)
    MenuWorld.InstallNativeUnitInputs(world)
    local env = world.env
    local powerType, power, maxPower = env.UnitPowerType, env.UnitPower, env.UnitPowerMax
    local issecretvalue = env.issecretvalue
    env.issecretvalue = function(value)
        return rawequal(value, secret) or (issecretvalue and issecretvalue(value)) or false
    end
    env.UnitExists = TestUnit
    env.UnitPowerType = function(unit)
        if TestUnit(unit) then return displayType, displayToken end
        return powerType(unit)
    end
    env.UnitHasPowerType = function(unit, resource)
        if not TestUnit(unit) then return false end
        assert(resource == displayType, "presence read used the wrong resource")
        presenceReads = presenceReads + 1
        return hasResource
    end
    env.UnitPower = function(unit, resource)
        if not TestUnit(unit) then return power(unit, resource) end
        valueReads = valueReads + 1
        return current
    end
    env.UnitPowerMax = function(unit, resource)
        if not TestUnit(unit) then return maxPower(unit, resource) end
        return maximum
    end
    env.UnitPowerPercent = nil
    if arg[3] then
        local load = world.LoadFile
        function world:LoadFile(path, addon, ns)
            if path:match("MSUF_UF_Elements_Power%.lua$") then path = arg[3] .. path:sub(#root + 1) end
            return load(self, path, addon, ns)
        end
    end
end })
local env, UF = mw.env, mw.core.UF
local target = env.MSUF_DB.target
target.enabled, target.showPowerBar, target.showPowerText = true, true, true
target.embedPowerBarIntoHealth, target.powerBarDetached, target.powerBarHeight = true, false, 5
target.powerBarBorderEnabled, target.powerBarBorderThickness = true, 1
target.powerTextLeft, target.powerTextCenter, target.powerTextRight = "NONE", "NONE", "CURRENT"

local frame = env.CreateFrame("Button", nil, env.UIParent)
frame:SetSize(160, 40)
frame.unit, frame.MSUFUnitKey = "target", "target"
UF.AttachFrame(frame, { scope = "single" })
UF.frames.target = frame
local function Apply()
    assert(UF.ApplySpec(frame, UF.Config.RefreshUnit("target"), "MSUF_POWER_LAYOUT"))
end
local function CheckVisibility(shown)
    assert(frame.targetPowerBar:IsShown() == shown, "power fill visibility")
    assert(frame.powerBarBG:IsShown() == shown, "power background visibility")
    assert(frame.MSUFPowerTextLayer:IsShown() == shown, "power text visibility")
end
local function Fire(event, unit, token)
    mw.world:FireEvent(event, unit, token)
end

Apply()
CheckVisibility(true)
assert(presenceReads == 0 and frame.hpBar._msufHealthPowerInset == 5, "default profile tested resources")
target.powerHideMissingResource = true
Apply()
CheckVisibility(false)
assert(frame.hpBar._msufHealthPowerInset == 0, "embedded row left a gap")
assert(frame.targetPowerBar.MSUFPowerBorderHost:GetAlpha() == 0, "power border still visible")
maximum, displayToken = secret, secret
Fire("UNIT_DISPLAYPOWER", "target")
CheckVisibility(false)
maximum, displayToken = 100, "MANA"
local beforePresence, beforeValue = presenceReads, valueReads
for _ = 1, 25 do Fire("UNIT_POWER_UPDATE", "target", "MANA") end
assert(presenceReads == beforePresence and valueReads == beforeValue, "hidden row read a power value")

hasResource = true
Fire("UNIT_MAXPOWER", "target", "MANA")
CheckVisibility(true)
assert(frame.hpBar._msufHealthPowerInset == 5, "embedded row did not rejoin health")
assert(frame.targetPowerBar:GetValue() == 0, "empty mana was not reseeded")
assert(frame.powerTextRight:GetText() == "0", "CURRENT-only text did not reseed on maximum change")
assert(frame.targetPowerBar.MSUFPowerBorderHost:GetAlpha() == 1, "power border did not return")
beforePresence, beforeValue = presenceReads, valueReads
for _ = 1, 25 do Fire("UNIT_POWER_UPDATE", "target", "MANA") end
assert(presenceReads == beforePresence and valueReads > beforeValue, "visible value route checked resource presence")

hasResource = false
mw.world.widgets:SetCombat(true)
Fire("UNIT_DISPLAYPOWER", "target", "MANA")
CheckVisibility(false)
assert(frame.hpBar._msufHealthPowerInset == 5, "geometry changed under combat lockdown")
mw.world.widgets:SetCombat(false)
Fire("PLAYER_REGEN_ENABLED")
assert(frame.hpBar._msufHealthPowerInset == 0, "deferred layout did not release the row")

local function SwitchTarget(present, powerType, token, value, expectedInset)
    hasResource, displayType, displayToken, current = present, powerType, token, value
    local before = presenceReads
    Fire("PLAYER_TARGET_CHANGED")
    CheckVisibility(present)
    local point, relative, relativePoint, _, inset = frame.hpBar:GetPoint(2)
    assert(point == "BOTTOMRIGHT" and relative == frame and relativePoint == "BOTTOMRIGHT" and inset == expectedInset,
        "target change did not set the actual health bar anchor")
    assert(presenceReads == before + 1, "target change checked resource presence more than once")
    if present then assert(frame.targetPowerBar:GetValue() == value, "target change displayed the previous target's power") end
end
SwitchTarget(true, 0, "MANA", 0, 5)
SwitchTarget(false, 0, "MANA", 0, 0)
SwitchTarget(true, 1, "RAGE", 27, 5)
hasResource, maximum = nil, 0
Fire("UNIT_MAXPOWER", "target", "RAGE")
CheckVisibility(false)
hasResource, maximum = true, 100
Fire("UNIT_MAXPOWER", "target", "RAGE")
CheckVisibility(true)
target.powerBarDetached = true
Apply()
hasResource = false
Fire("PLAYER_TARGET_CHANGED")
CheckVisibility(false)
assert(frame.hpBar._msufHealthPowerInset == 0, "detached power altered health layout")
target.powerHideMissingResource = false
Apply()
CheckVisibility(true)
for _, section in pairs(mw.M.cache.uf_target.sections) do
    local entry = section._msuf2CollapsibleEntry
    if entry then entry.SetOpenImmediate(true) end
end
mw:RunTimers()
local function PowerToggle(unit, suffix)
    local id = "menu2.uf_" .. unit .. ".unit.power." .. suffix
    for _, widget in ipairs(mw.world.widgets.frames) do
        local command = widget._msuf2CommandAction
        if command and command.controlId == id then return widget end
    end
    error("missing toggle " .. id)
end
local function CheckToggleSpacing(unit)
    local detach = PowerToggle(unit, "detached")
    local hide = PowerToggle(unit, "powerhidemissingresource")
    local _, card, _, _, detachY = detach:GetPoint(1)
    local _, hideCard, _, _, hideY = hide:GetPoint(1)
    assert(card == hideCard and detachY - hideY >= 28, "resource visibility toggle overlaps Detach from frame for " .. unit)
    assert(card:GetHeight() + hideY >= hide:GetHeight() + 8, "resource visibility toggle clips the card bottom for " .. unit)
    return hide
end
local control = CheckToggleSpacing("target")
control:Click("LeftButton")
assert(target.powerHideMissingResource == true, "menu toggle did not store the per-unit option")
assert(env.MSUF_DB.focus.powerHideMissingResource ~= true, "menu toggle changed a different unit scope")
mw:RunTimers()
CheckVisibility(false)

local preview = mw.core.PreviewAnimation
preview.enabled = true
assert(preview.ApplyUnitFrame(frame, 1, "target"))
CheckVisibility(true)
preview.SetEnabled(false)
CheckVisibility(false)

local dependent = env.MSUF_DB.targettarget
dependent.enabled, dependent.showPowerBar, dependent.powerHideMissingResource = true, true, true
local child = env.CreateFrame("Button", nil, env.UIParent)
child:SetSize(100, 30)
child.unit, child.MSUFUnitKey = "targettarget", "targettarget"
UF.AttachFrame(child, { scope = "single" })
UF.frames.targettarget = child
assert(UF.ApplySpec(child, UF.Config.RefreshUnit("targettarget"), "MSUF_POWER_LAYOUT"))
assert(not child.targetPowerBar:IsShown(), "dependent target without power displayed a bar")
hasResource = true
assert(UF.RunLeanIdentity(child, "MSUF_DEPENDENT_TARGET_POLL"))
assert(child.targetPowerBar:IsShown(), "existing dependent-unit sample did not notice the new resource")
print(flavor .. ": Unit Frames missing resource visibility, power routes and combat layout passed")
