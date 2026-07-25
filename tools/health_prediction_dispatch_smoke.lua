_G = _G or _ENV

local MSUF = { UF = { Metadata = { runtimeUpdateOwners = { Prediction = true } } } }
_G.MSUF_NS = MSUF
_G.UnitExists = function() return true end
_G.issecretvalue = function() return false end
_G.InCombatLockdown = function() return false end

assert(loadfile("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Core.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)

local UF = MSUF.UF
local percentMode = false
local order = {}
local predictionHP, predictionMax, textHP, textMax
local events = { "UNIT_HEALTH" }
local function UpdatePrediction(_, _, _, hp, maxHP)
  order[#order + 1] = "prediction"
  predictionHP, predictionMax = hp, maxHP
end

UF.RegisterElement("Health", {
  GetEvents = function() return events end,
  Update = function()
    order[#order + 1] = "health"
    if percentMode then return 73, 100, true end
    return 80, 100, false
  end,
})
UF.RegisterElement("Prediction", {
  GetEvents = function() return events end,
  Update = UpdatePrediction,
  HealthVisualGateUpdates = { [UpdatePrediction] = true },
})
UF.RegisterElement("HealthText", {
  IsEnabled = function(_, spec) return not spec or spec.showHealthText ~= false end,
  GetEvents = function() return events end,
  Update = function(_, _, _, hp, maxHP)
    order[#order + 1] = "text"
    textHP, textMax = hp, maxHP
  end,
})

local frame = { unitEvents = {}, genericEvents = {} }
function frame:SetScript(kind, script) self[kind] = script end
function frame:IsVisible() return true end
function frame:UnregisterAllEvents() self.unitEvents, self.genericEvents = {}, {} end
function frame:RegisterUnitEvent(event, unit) self.unitEvents[event] = unit end
function frame:RegisterEvent(event) self.genericEvents[event] = true end

UF.ApplySpec(frame, { unit = "party1", key = "party1", scope = "group", enabled = true })
frame._msufPredictionHealthVisualActive = true
frame.OnEvent(frame, "UNIT_HEALTH", "party1")
assert(table.concat(order, "|") == "health|prediction|text", "unexpected dispatch order: " .. table.concat(order, "|"))
assert(predictionHP == 80 and predictionMax == 100)
assert(textHP == 80 and textMax == 100)

percentMode = true
order = {}
frame.OnEvent(frame, "UNIT_HEALTH", "party1")
assert(table.concat(order, "|") == "health|prediction|text", "unexpected percent dispatch order: " .. table.concat(order, "|"))
assert(predictionHP == nil and predictionMax == nil,
  "percent health must not seed prediction with non-absolute values")
assert(textHP == nil and textMax == nil,
  "percent health must retain the secret text fastpath")

frame._msufPredictionHealthVisualActive = nil
order = {}
predictionHP, predictionMax = false, false
frame.OnEvent(frame, "UNIT_HEALTH", "party1")
assert(table.concat(order, "|") == "health|text",
  "inactive health visual still called Prediction: " .. table.concat(order, "|"))
assert(predictionHP == false and predictionMax == false,
  "inactive health visual mutated Prediction payload")

local frameMethods = frame
local function NewGroupFrame()
  return setmetatable({ unitEvents = {}, genericEvents = {} }, { __index = frameMethods })
end

-- Party, Raid, and Mythic Raid must all compile the bar-only no-absorb
-- archetype: one Health updater call, no generic dispatch and no Prediction
-- follower until absorb data explicitly opens the gate.
local groupKinds = {
  { kind = "party", unit = "party1" },
  { kind = "raid", unit = "raid1" },
  { kind = "mythicraid", unit = "raid2" },
}
for i = 1, #groupKinds do
  local entry = groupKinds[i]
  local lean = NewGroupFrame()
  UF.ApplySpec(lean, {
    unit = entry.unit,
    key = entry.unit,
    scope = "group",
    groupKind = entry.kind,
    enabled = true,
    showHealthText = false,
  })
  lean._msufDispatchToken = 200 + i
  order = {}
  lean.OnEvent(lean, "UNIT_HEALTH", entry.unit)
  assert(table.concat(order, "|") == "health",
    entry.kind .. " no-absorb route retained a follower: " .. table.concat(order, "|"))
  assert(lean._msufDispatchToken == 200 + i and lean._msufDispatchActive == nil,
    entry.kind .. " bar-only health re-entered generic dispatch")

  lean._msufPredictionHealthVisualActive = true
  order = {}
  lean.OnEvent(lean, "UNIT_HEALTH", entry.unit)
  assert(table.concat(order, "|") == "health|prediction",
    entry.kind .. " active absorb route lost Prediction: " .. table.concat(order, "|"))
end

print("health prediction dispatch smoke: ok")
