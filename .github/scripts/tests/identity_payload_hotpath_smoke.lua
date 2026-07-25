-- Regression coverage for the identity Health/Power -> Text payload handoff.
local root = arg and arg[1] or "."

local function Check(value, message)
    if not value then error(message or "check failed", 2) end
end

local SECRET_HP, SECRET_MAX = {}, {}
_G.issecretvalue = function(value)
    return value == SECRET_HP or value == SECRET_MAX
end
_G.CreateFrame = function() return nil end
_G.InCombatLockdown = function() return false end
local existsReads, playerReads, classReads, connectedReads, deadReads = 0, 0, 0, 0, 0
_G.UnitExists = function()
    existsReads = existsReads + 1
    return true
end
_G.UnitIsPlayer = function()
    playerReads = playerReads + 1
    return true
end
_G.UnitClass = function()
    classReads = classReads + 1
    return "Mage", "MAGE"
end
_G.UnitIsConnected = function()
    connectedReads = connectedReads + 1
    return true
end
_G.UnitIsDead = function() return false end
_G.UnitIsDeadOrGhost = function()
    deadReads = deadReads + 1
    return false
end

local scheduled = {}
_G.MSUF_ScheduleOnce = function(key, callback)
    if scheduled[key] == nil then scheduled[key] = callback end
end

local function FlushScheduled()
    local pending = scheduled
    scheduled = {}
    for _, callback in pairs(pending) do callback() end
end

local Frame = {}
Frame.__index = Frame

function Frame:SetScript(name, callback) self.scripts[name] = callback end
function Frame:HookScript(name, callback) self.hooks[name] = callback end
function Frame:IsVisible() return self.visible ~= false end
function Frame:RegisterEvent(event) self.registered[event] = true end
function Frame:RegisterUnitEvent(event, unit) self.registered[event] = unit end
function Frame:UnregisterEvent(event) self.registered[event] = nil end
function Frame:UnregisterAllEvents()
    for event in pairs(self.registered) do self.registered[event] = nil end
end

local function NewFrame(unit)
    return setmetatable({
        unit = unit,
        unitKey = unit,
        visible = true,
        scripts = {},
        hooks = {},
        registered = {},
        order = {},
    }, Frame)
end

local MSUF = { UF = { Metadata = { defaultApplyMask = { Prediction = true } } } }
_G.MSUF_NS = MSUF
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
local UF = assert(MSUF.UF)

local healthPercentReady = false
local healthCalls, powerCalls = 0, 0

local function Record(frame, label)
    Check(frame._msufDispatchActive == true, label .. " ran outside the frame dispatch")
    frame.order[#frame.order + 1] = label
end

local Health = { IsEnabled = function() return true end, GetEvents = function() return {} end }
function Health.Update(frame)
    healthCalls = healthCalls + 1
    Record(frame, "Health")
    if healthPercentReady then
        return 55, nil, true
    end
    return SECRET_HP, SECRET_MAX, false
end
UF.RegisterElement("Health", Health)

local Power = { IsEnabled = function() return true end, GetEvents = function() return {} end }
function Power.Update(frame)
    powerCalls = powerCalls + 1
    Record(frame, "Power")
    return 35, 100, 3, "ENERGY", false
end
UF.RegisterElement("Power", Power)

local NameText = { IsEnabled = function() return true end, GetEvents = function() return {} end }
function NameText.Update(frame)
    Record(frame, "NameText")
    local exists, existsKnown = UF.ReadUnitExistsCached(frame, frame.MSUFUnitKey)
    local existsAgain, existsKnownAgain = UF.ReadUnitExistsCached(frame, frame.MSUFUnitKey)
    local isPlayer, playerKnown = UF.ReadUnitIsPlayerCached(frame, frame.MSUFUnitKey)
    local isPlayerAgain, playerKnownAgain = UF.ReadUnitIsPlayerCached(frame, frame.MSUFUnitKey)
    local className, classToken = UF.ReadUnitClassCached(frame, frame.MSUFUnitKey)
    local classNameAgain, classTokenAgain = UF.ReadUnitClassCached(frame, frame.MSUFUnitKey)
    local connected, connectedKnown = UF.ReadConnectedCached(frame, frame.MSUFUnitKey)
    local connectedAgain, connectedKnownAgain = UF.ReadConnectedCached(frame, frame.MSUFUnitKey)
    local dead, deadKnown = UF.ReadDeadCached(frame, frame.MSUFUnitKey)
    local deadAgain, deadKnownAgain = UF.ReadDeadCached(frame, frame.MSUFUnitKey)
    Check(exists and existsKnown and existsAgain and existsKnownAgain,
        "dispatch existence cache changed the known result")
    Check(isPlayer and playerKnown and isPlayerAgain and playerKnownAgain,
        "dispatch player cache changed the known result")
    Check(className == "Mage" and classToken == "MAGE"
        and classNameAgain == className and classTokenAgain == classToken,
        "dispatch class cache changed the class tuple")
    Check(connected and connectedKnown and connectedAgain and connectedKnownAgain,
        "dispatch connection cache changed the known result")
    Check(not dead and deadKnown and not deadAgain and deadKnownAgain,
        "dispatch dead cache changed the known result")
end
UF.RegisterElement("NameText", NameText)

local HealthText = { IsEnabled = function() return true end, GetEvents = function() return {} end }
function HealthText.Update(frame, event, unit, hp, hpMax)
    Record(frame, "HealthText")
    frame.lastHealthPayload = { event = event, unit = unit, hp = hp, hpMax = hpMax }
end
UF.RegisterElement("HealthText", HealthText)

local PowerText = { IsEnabled = function() return true end, GetEvents = function() return {} end }
function PowerText.Update(frame, event, unit, power, powerMax, powerType, powerToken, metaChanged)
    Record(frame, "PowerText")
    frame.lastPowerPayload = {
        event = event,
        unit = unit,
        power = power,
        powerMax = powerMax,
        powerType = powerType,
        powerToken = powerToken,
        metaChanged = metaChanged,
    }
end
UF.RegisterElement("PowerText", PowerText)

local InlineToT = { IsEnabled = function() return true end, GetEvents = function() return {} end }
function InlineToT.Update(frame)
    Record(frame, "InlineToT")
end
UF.RegisterElement("InlineToT", InlineToT)

local Prediction = { IsEnabled = function() return true end, GetEvents = function() return {} end }
function Prediction.Update(frame, event, unit)
    Record(frame, "Prediction")
    frame.predictionCalls = (frame.predictionCalls or 0) + 1
    frame.lastPredictionEvent = event
    frame.lastPredictionUnit = unit
end
UF.RegisterElement("Prediction", Prediction)

local spec = { enabled = true, key = "target", unit = "target", scope = "single" }

local function Apply(frame, names)
    UF.AttachFrame(frame, { scope = "single" })
    for i = 1, #names do
        Check(UF.ApplyElementToFrame(frame, names[i], spec) == true,
            "failed to apply " .. names[i])
    end
end

local function Reset(frame)
    frame.order = {}
    frame.lastHealthPayload = nil
    frame.lastPowerPayload = nil
end

local function CheckOrder(frame, expected)
    Check(#frame.order == #expected, "identity call count changed")
    for i = 1, #expected do
        Check(frame.order[i] == expected[i],
            "identity order mismatch at " .. i .. ": " .. tostring(frame.order[i]))
    end
end

local full = NewFrame("target")
Apply(full, { "Health", "Power", "NameText", "HealthText", "PowerText", "InlineToT" })
local fullTwin = NewFrame("target")
Apply(fullTwin, { "Health", "Power", "NameText", "HealthText", "PowerText", "InlineToT" })
Check(full._msufIdentityPath == fullTwin._msufIdentityPath,
    "identical typed identity plans were not interned")
Check(full._msufIdentityBarPath == fullTwin._msufIdentityBarPath,
    "identical identity bar payload plans were not interned")
Check(type(full._msufUnitState) == "table" and full._msufIdentityDispatchState == nil,
    "identity read-through state was not prewarmed in the shared unit cache")

healthCalls, powerCalls = 0, 0
local token = full._msufDispatchToken or 0
full.PLAYER_TARGET_CHANGED(full, "PLAYER_TARGET_CHANGED")
CheckOrder(full, { "Health", "Power", "NameText", "HealthText", "PowerText", "InlineToT" })
Check(healthCalls == 1 and powerCalls == 1, "identity bars ran more than once")
Check(full.lastHealthPayload.hp == SECRET_HP and full.lastHealthPayload.hpMax == SECRET_MAX,
    "secret health payload was reread or lost before HealthText")
Check(full.lastPowerPayload.power == 35 and full.lastPowerPayload.powerMax == 100
    and full.lastPowerPayload.powerType == 3 and full.lastPowerPayload.powerToken == "ENERGY"
    and full.lastPowerPayload.metaChanged == false,
    "power payload was shifted or lost before PowerText")
Check(full._msufDispatchToken == token + 1 and full._msufDispatchActive == nil,
    "event identity did not retain exactly one dispatch boundary")
Check(existsReads == 1 and playerReads == 1 and classReads == 1
    and connectedReads == 1 and deadReads == 1,
    "one identity dispatch repeated a bound-unit API read")

-- Native percent plans seed a dispatch slot in Health. Match the normal
-- direct Health route and pass nil values so HealthText consumes that slot.
healthPercentReady = true
Reset(full)
full.PLAYER_TARGET_CHANGED(full, "PLAYER_TARGET_CHANGED")
Check(full.lastHealthPayload.hp == nil and full.lastHealthPayload.hpMax == nil,
    "percent-ready identity bypassed the dispatch-percent handoff")
Check(existsReads == 2 and playerReads == 2 and classReads == 2
    and connectedReads == 2 and deadReads == 2,
    "identity API cache survived into the next event")
healthPercentReady = false

-- RunLeanIdentity owns its own single dispatch and uses the same local payload
-- handoff as the registered target event.
Reset(full)
token = full._msufDispatchToken
Check(UF.RunLeanIdentity(full, "MSUF_UNIT_IDENTITY") == true,
    "RunLeanIdentity rejected an active identity plan")
CheckOrder(full, { "Health", "Power", "NameText", "HealthText", "PowerText", "InlineToT" })
Check(full.lastHealthPayload.hp == SECRET_HP and full.lastPowerPayload.power == 35,
    "RunLeanIdentity lost a bar payload")
Check(full._msufDispatchToken == token + 1 and full._msufDispatchActive == nil,
    "RunLeanIdentity did not retain exactly one dispatch boundary")

-- Fixed tuple positions must also hold when only one bar exists.
local powerOnly = NewFrame("target")
Apply(powerOnly, { "Power", "PowerText" })
Reset(powerOnly)
powerOnly.PLAYER_TARGET_CHANGED(powerOnly, "PLAYER_TARGET_CHANGED")
CheckOrder(powerOnly, { "Power", "PowerText" })
Check(powerOnly.lastPowerPayload.power == 35 and powerOnly.lastPowerPayload.powerType == 3,
    "power-only identity payload landed in health tuple slots")

local healthOnly = NewFrame("target")
Apply(healthOnly, { "Health", "HealthText" })
Reset(healthOnly)
healthOnly.PLAYER_TARGET_CHANGED(healthOnly, "PLAYER_TARGET_CHANGED")
CheckOrder(healthOnly, { "Health", "HealthText" })
Check(healthOnly.lastHealthPayload.hp == SECRET_HP and healthOnly.lastHealthPayload.hpMax == SECRET_MAX,
    "health-only identity payload was not forwarded")

local textOnly = NewFrame("target")
Apply(textOnly, { "PowerText" })
Reset(textOnly)
textOnly.PLAYER_TARGET_CHANGED(textOnly, "PLAYER_TARGET_CHANGED")
CheckOrder(textOnly, { "PowerText" })
Check(textOnly.lastPowerPayload.power == nil and textOnly.lastPowerPayload.powerMax == nil,
    "text-only identity did not preserve the API fallback contract")

-- Prediction owns a cached snapshot for the stable unit token. Every identity
-- lifecycle must therefore reseed it exactly once when the unit behind that
-- token changes, including coalesced dependent-unit notifications.
local function NewPredictionFrame(unit)
    local frame = NewFrame(unit)
    local predictionSpec = { enabled = true, key = unit, unit = unit, scope = "single" }
    UF.AttachFrame(frame, { scope = "single" })
    Check(UF.ApplyElementToFrame(frame, "Prediction", predictionSpec) == true,
        "failed to apply Prediction to " .. unit)
    return frame
end

local function CheckImmediateIdentity(unit, event, source)
    local frame = NewPredictionFrame(unit)
    Check(type(frame[event]) == "function", unit .. " did not register " .. event)
    frame[event](frame, event, source)
    Check(frame.predictionCalls == 1, unit .. " identity did not run Prediction exactly once")
    Check(frame.lastPredictionEvent == event and frame.lastPredictionUnit == unit,
        unit .. " identity forwarded the wrong Prediction payload")
    return frame
end

CheckImmediateIdentity("target", "PLAYER_TARGET_CHANGED")
CheckImmediateIdentity("focus", "PLAYER_FOCUS_CHANGED")
CheckImmediateIdentity("boss1", "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
local pet = CheckImmediateIdentity("pet", "UNIT_PET", "player")
Check(pet.registered.UNIT_PET == "player", "pet identity did not bind UNIT_PET to player")

local function CheckDependentIdentity(unit, parent, playerEvent)
    local frame = NewPredictionFrame(unit)
    Check(type(frame[playerEvent]) == "function" and type(frame.UNIT_TARGET) == "function",
        unit .. " did not register both dependent identity events")
    Check(frame.registered.UNIT_TARGET == parent,
        unit .. " UNIT_TARGET was not bound to its parent unit")

    frame[playerEvent](frame, playerEvent)
    frame.UNIT_TARGET(frame, "UNIT_TARGET", parent)
    Check(frame.predictionCalls == nil,
        unit .. " Prediction ran before dependent notifications were coalesced")
    FlushScheduled()
    Check(frame.predictionCalls == 1,
        unit .. " coalesced identity did not run Prediction exactly once")
    Check(frame.lastPredictionUnit == unit,
        unit .. " coalesced identity forwarded the parent instead of the dependent unit")
end

CheckDependentIdentity("targettarget", "target", "PLAYER_TARGET_CHANGED")
CheckDependentIdentity("focustarget", "focus", "PLAYER_FOCUS_CHANGED")

print("PASS identity payload hotpath: payload forwarding plus exact Prediction identity reseeds")
