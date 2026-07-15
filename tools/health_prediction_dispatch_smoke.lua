_G = _G or _ENV

local MSUF = { UF = { Metadata = { runtimeUpdateOwners = { Prediction = true } } } }
_G.MSUF_NS = MSUF
_G.UnitExists = function() return true end
_G.issecretvalue = function() return false end
_G.InCombatLockdown = function() return false end

assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Core.lua"))(
  "MidnightSimpleUnitFrames",
  MSUF
)

local UF = MSUF.UF
local percentMode = false
local order = {}
local predictionHP, predictionMax, textHP, textMax
local events = { "UNIT_HEALTH" }

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
  Update = function(_, _, _, hp, maxHP)
    order[#order + 1] = "prediction"
    predictionHP, predictionMax = hp, maxHP
  end,
})
UF.RegisterElement("HealthText", {
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

print("health prediction dispatch smoke: ok")
