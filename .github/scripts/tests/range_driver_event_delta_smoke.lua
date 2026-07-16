-- Standalone regression for incremental RangeFade driver event registration.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local UNIT_EVENTS = {
    "UNIT_IN_RANGE_UPDATE", "UNIT_PHASE", "UNIT_CTR_OPTIONS", "UNIT_OTHER_PARTY_CHANGED",
    "UNIT_CONNECTION",
}
local SPELL_UPDATE_EVENTS = {
    "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED",
}
local ACTIVE_EVENTS = {
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING",
}
for i = 1, #SPELL_UPDATE_EVENTS do
    ACTIVE_EVENTS[#ACTIVE_EVENTS + 1] = SPELL_UPDATE_EVENTS[i]
end

local operations = {}
local driver
local secondaryUnitDriver
local secretValue
local spellRangeByUnit = {}
local unitRangeByUnit = {}
local movingUnits = {}

local function Record(operation, event, units)
    operations[#operations + 1] = {
        operation = operation,
        event = event,
        units = units,
    }
end

local function ResetOperations()
    for i = #operations, 1, -1 do operations[i] = nil end
end

local function OperationCount(event, operation)
    local count = 0
    for i = 1, #operations do
        local entry = operations[i]
        if (event == nil or entry.event == event)
            and (operation == nil or entry.operation == operation) then
            count = count + 1
        end
    end
    return count
end

local function AssertNoOperations(events, message)
    for i = 1, #events do
        Equal(OperationCount(events[i]), 0, message .. " " .. events[i])
    end
end

local function AssertUnitFilter(event, expected)
    local registration = driver.registered[event]
    Check(registration and registration.kind == "unit", event .. " is not unit-filtered")
    Equal(#registration.units, #expected, event .. " unit count")
    for i = 1, #expected do
        Equal(registration.units[i], expected[i], event .. " unit " .. tostring(i))
    end
end

local DriverMethods = {}

function DriverMethods:SetScript(script, callback)
    self.scripts[script] = callback
end

function DriverMethods:RegisterEvent(event)
    Record("register", event)
    self.registered[event] = { kind = "plain" }
end

function DriverMethods:RegisterUnitEvent(event, ...)
    local units = { ... }
    Check(#units <= 4, event .. " registered more than four unit filters")
    Record("register-unit", event, units)
    self.registered[event] = { kind = "unit", units = units }
end

function DriverMethods:UnregisterEvent(event)
    Record("unregister", event)
    self.registered[event] = nil
end

function DriverMethods:UnregisterAllEvents()
    Record("unregister-all")
    for event in pairs(self.registered) do self.registered[event] = nil end
end

_G.CreateFrame = function()
    local created = setmetatable({ scripts = {}, registered = {} }, { __index = DriverMethods })
    if not driver then
        driver = created
    else
        secondaryUnitDriver = created
    end
    return created
end

_G.C_Timer = { After = function() end }
_G.UnitCanAssist = function(_, unit) return not tostring(unit):match("^boss%d+$") end
_G.UnitCanAttack = function(_, unit) return tostring(unit):match("^boss%d+$") ~= nil end
_G.UnitIsDeadOrGhost = function() return false end
_G.UnitInRange = function(unit)
    local result = unitRangeByUnit[unit]
    if result == nil then result = true end
    return result, true
end
_G.UnitClass = function() return "Mage", "MAGE" end
_G.InCombatLockdown = function() return false end
_G.CheckInteractDistance = function() return true end
_G.GetUnitSpeed = function(unit) return movingUnits[unit] and 7 or 0 end
_G.GetTime = function() return 1 end
_G.issecretvalue = function(value) return value == secretValue end
_G.IsPlayerSpell = function() return true end
_G.Enum = { SpellBookSpellBank = { Player = 1 } }
_G.C_SpellBook = {
    IsSpellKnownOrInSpellBook = function() return true end,
}
_G.C_Spell = {
    IsSpellInRange = function(_, unit)
        local result = spellRangeByUnit[unit]
        if result == nil then return true end
        return result
    end,
    EnableSpellRangeCheck = function() end,
    GetSpellIDForSpellIdentifier = function(value) return tonumber(value) end,
    GetOverrideSpell = function(spellID) return spellID end,
}

local captured
local MSUF = {
    UF = {
        frames = {},
        UnitExistsSafe = function() return true end,
        ApplyRangeModifier = function(frame, multiplier)
            frame.appliedRangeMultiplier = multiplier
            return true
        end,
        RegisterElement = function(name, element)
            if name == "RangeFade" then captured = element end
        end,
    },
}
_G.MSUF_NS = MSUF

local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Range/MSUF_UF_RangeFade.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)
local RangeFade = assert(captured, "RangeFade element was not registered")

local function NewUnitFrame(unit)
    local frame = {
        unit = unit,
        visible = true,
        hooks = {},
    }
    function frame:HookScript(script, callback) self.hooks[script] = callback end
    function frame:IsVisible() return self.visible == true end
    MSUF.UF.frames[unit] = frame
    return frame
end

local function ApplyRange(frame)
    RangeFade.Apply(frame, { range = { active = true, alpha = 0.4 } })
end

local function SetVisible(frame, visible)
    frame.visible = visible == true
    local script = visible and "OnShow" or "OnHide"
    local callback = assert(frame.hooks[script], script .. " hook missing for " .. frame.unit)
    callback(frame)
end

local focus = NewUnitFrame("focus")
local target = NewUnitFrame("target")
local pet = NewUnitFrame("pet")
local boss1 = NewUnitFrame("boss1")
ApplyRange(focus)
ApplyRange(target)
ApplyRange(pet)
ApplyRange(boss1)

Check(driver ~= nil, "range driver was not created")
for i = 1, #ACTIVE_EVENTS do
    Check(driver.registered[ACTIVE_EVENTS[i]] ~= nil, "missing active event " .. ACTIVE_EVENTS[i])
end
Check(driver.registered.PLAYER_TARGET_CHANGED ~= nil, "missing target event")
Check(driver.registered.PLAYER_FOCUS_CHANGED ~= nil, "missing focus event")
Check(driver.registered.UNIT_PET ~= nil, "missing pet event")
Check(driver.registered.INSTANCE_ENCOUNTER_ENGAGE_UNIT ~= nil, "missing boss event")
Check(driver.registered.SPELL_RANGE_CHECK_UPDATE ~= nil, "missing target spell event")
for i = 1, #UNIT_EVENTS do
    AssertUnitFilter(UNIT_EVENTS[i], { "target", "focus", "pet", "boss1" })
end

-- Once an idle poll has settled, player movement must re-arm the fallback for
-- friendly target aliases whose range event can arrive under a group token.
unitRangeByUnit.target = false
movingUnits.player = true
driver.scripts.OnEvent(driver, "PLAYER_STARTED_MOVING")
Equal(target.appliedRangeMultiplier, 0.4,
    "movement start did not refresh a stale friendly target range")
unitRangeByUnit.target = true
movingUnits.player = nil
driver.scripts.OnEvent(driver, "PLAYER_STOPPED_MOVING")
Equal(target.appliedRangeMultiplier, 1,
    "movement stop did not settle friendly target range")

-- Hiding target changes its unit filter and target-specific plain events only.
ResetOperations()
SetVisible(target, false)
Equal(OperationCount(nil, "unregister-all"), 0, "target hide used full event reset")
for i = 1, #UNIT_EVENTS do
    Equal(OperationCount(UNIT_EVENTS[i], "unregister"), 1, "target hide unit-event unregister")
    Equal(OperationCount(UNIT_EVENTS[i], "register-unit"), 1, "target hide unit-event register")
    AssertUnitFilter(UNIT_EVENTS[i], { "focus", "pet", "boss1" })
end
Equal(OperationCount("PLAYER_TARGET_CHANGED", "unregister"), 1, "target hide target-event unregister")
Equal(OperationCount("SPELL_RANGE_CHECK_UPDATE", "unregister"), 1, "target hide spell-event unregister")
AssertNoOperations(ACTIVE_EVENTS, "target hide touched active event")
AssertNoOperations({ "PLAYER_FOCUS_CHANGED", "UNIT_PET", "INSTANCE_ENCOUNTER_ENGAGE_UNIT" },
    "target hide touched unrelated event")

-- Showing target restores only the same changed subscriptions.
ResetOperations()
SetVisible(target, true)
Equal(OperationCount(nil, "unregister-all"), 0, "target show used full event reset")
for i = 1, #UNIT_EVENTS do
    Equal(OperationCount(UNIT_EVENTS[i], "unregister"), 1, "target show unit-event unregister")
    Equal(OperationCount(UNIT_EVENTS[i], "register-unit"), 1, "target show unit-event register")
    AssertUnitFilter(UNIT_EVENTS[i], { "target", "focus", "pet", "boss1" })
end
Equal(OperationCount("PLAYER_TARGET_CHANGED", "register"), 1, "target show target-event register")
Equal(OperationCount("SPELL_RANGE_CHECK_UPDATE", "register"), 1, "target show spell-event register")
AssertNoOperations(ACTIVE_EVENTS, "target show touched active event")
AssertNoOperations({ "PLAYER_FOCUS_CHANGED", "UNIT_PET", "INSTANCE_ENCOUNTER_ENGAGE_UNIT" },
    "target show touched unrelated event")

-- A redundant visibility callback must not touch any event registration.
ResetOperations()
SetVisible(target, true)
Equal(#operations, 0, "unchanged driver masks touched event registration")

-- targettarget keeps PLAYER_TARGET_CHANGED and UNIT_TARGET alive when target hides.
local targettarget = NewUnitFrame("targettarget")
ApplyRange(targettarget)
Check(driver.registered.UNIT_TARGET ~= nil, "missing targettarget UNIT_TARGET registration")
ResetOperations()
SetVisible(target, false)
Equal(OperationCount("PLAYER_TARGET_CHANGED"), 0, "targettarget dependency churned target event")
Equal(OperationCount("UNIT_TARGET"), 0, "unchanged target-unit filter was rebuilt")
Equal(OperationCount("SPELL_RANGE_CHECK_UPDATE", "unregister"), 1,
    "target hide with targettarget did not remove target spell event")

-- Boss2-5 exceed one RegisterUnitEvent block. They must spill into one second
-- four-unit driver, and a secret event payload must still refresh that block.
local boss2 = NewUnitFrame("boss2")
local boss3 = NewUnitFrame("boss3")
local boss4 = NewUnitFrame("boss4")
local boss5 = NewUnitFrame("boss5")
ApplyRange(boss2)
ApplyRange(boss3)
ApplyRange(boss4)
ApplyRange(boss5)
Check(secondaryUnitDriver ~= nil, "boss unit filters did not create a second driver block")
for i = 1, #UNIT_EVENTS do
    local registration = secondaryUnitDriver.registered[UNIT_EVENTS[i]]
    Check(registration and registration.kind == "unit", UNIT_EVENTS[i] .. " missing second unit block")
    Check(#registration.units <= 4, UNIT_EVENTS[i] .. " second unit block exceeded filter limit")
end

spellRangeByUnit.boss1 = false
spellRangeByUnit.boss5 = false
secretValue = {}
driver.scripts.OnEvent(driver, "UNIT_IN_RANGE_UPDATE", secretValue, secretValue)
Equal(boss1.appliedRangeMultiplier, 0.4,
    "secret UNIT_IN_RANGE_UPDATE did not refresh boss1 range fade")
secondaryUnitDriver.scripts.OnEvent(secondaryUnitDriver, "UNIT_IN_RANGE_UPDATE", secretValue, secretValue)
Equal(boss5.appliedRangeMultiplier, 0.4,
    "secret UNIT_IN_RANGE_UPDATE did not refresh boss range fade")
secretValue = nil

-- The final active frame still performs the intentional full shutdown.
SetVisible(targettarget, false)
SetVisible(pet, false)
SetVisible(boss1, false)
SetVisible(boss2, false)
SetVisible(boss3, false)
SetVisible(boss4, false)
SetVisible(boss5, false)
ResetOperations()
SetVisible(focus, false)
Equal(OperationCount(nil, "unregister-all"), 2, "last active frame did not fully unregister both drivers")
Check(next(driver.registered) == nil, "driver retained events after full shutdown")
Check(next(secondaryUnitDriver.registered) == nil, "secondary driver retained events after full shutdown")

print("PASS range driver event deltas: exact masks, bounded unit blocks, secret boss refresh, full shutdown")
