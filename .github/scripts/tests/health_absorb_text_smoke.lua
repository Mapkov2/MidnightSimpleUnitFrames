-- Standalone regression for event-routed health absorb text.
local root = arg and arg[1] or "."

local function Check(value, message)
    if not value then error(message or "check failed", 2) end
end

local function HasEvent(events, expected)
    for i = 1, #events do
        if events[i] == expected then return true end
    end
    return false
end

local function NewFontString()
    return {
        shown = true,
        IsShown = function(self) return self.shown end,
        SetText = function(self, value) self.text = value end,
        SetFormattedText = function(self, pattern, ...) self.text = string.format(pattern, ...) end,
        SetTextColor = function(self, ...) self.color = { ... } end,
    }
end

local function Secret(text, zero)
    return setmetatable({ secret = true, text = text, zero = zero == true }, {
        __tostring = function(value) return value.text end,
    })
end

_G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
_G.C_StringUtil = {
    TruncateWhenZero = function(value)
        if _G.issecretvalue(value) then return value.zero and "" or value.text end
        value = tonumber(value) or 0
        return value == 0 and "" or tostring(math.floor(value))
    end,
    WrapString = function(infix, prefix, suffix)
        if infix == "" then return "" end
        return (prefix or "") .. infix .. (suffix or "")
    end,
}
_G.AbbreviateNumbers = function(value) return "SHORT:" .. tostring(value) end
_G.AbbreviateLargeNumbers = _G.AbbreviateNumbers
_G.BreakUpLargeNumbers = function(value) return "FULL:" .. tostring(value) end
_G.wipe = function(tbl)
    for key in pairs(tbl) do tbl[key] = nil end
    return tbl
end

local healthValue, healthMaxValue, absorbValue = 600, 1000, 250
local healthReads, absorbReads = 0, 0
local UF = { elements = {} }
function UF.RegisterElement(name, element) UF.elements[name] = element end

local Text = {
    UnitHealth = function() healthReads = healthReads + 1; return healthValue end,
    UnitHealthMax = function() return healthMaxValue end,
    UnitGetTotalAbsorbs = function() absorbReads = absorbReads + 1; return absorbValue end,
    UnitPower = function() return 0 end,
    UnitPowerMax = function() return 1 end,
    UnitPowerType = function() return 0 end,
    UnitHealthPercent = function() return healthValue / healthMaxValue * 100 end,
    UnitPowerPercent = function() return 0 end,
    AbbreviateNumbers = _G.AbbreviateNumbers,
    AbbreviateLargeNumbers = _G.AbbreviateLargeNumbers,
    BreakUpLargeNumbers = _G.BreakUpLargeNumbers,
    SetShownCached = function(fs, shown) if fs then fs.shown = shown == true end end,
    tonumber = tonumber,
    type = type,
    format = string.format,
    floor = math.floor,
    max = math.max,
    abs = math.abs,
    GetTime = function() return 1 end,
    ABSORB_HEALTH_MODE_BASE = {
        CURRENTABSORB = "CURRENT", FULLVALUEABSORB = "FULLVALUE", MAXABSORB = "MAX", DEFICITABSORB = "DEFICIT",
        CURMAXABSORB = "CURMAX", PERCENTABSORB = "PERCENT", CURPERCENTABSORB = "CURPERCENT",
        CURMAXPERCENTABSORB = "CURMAXPERCENT", MAXPERCENTABSORB = "MAXPERCENT",
        PERCENTCURABSORB = "PERCENTCUR", PERCENTMAXABSORB = "PERCENTMAX",
        PERCENTCURMAXABSORB = "PERCENTCURMAX", MAXCURABSORB = "MAXCUR",
        PERCENTMAXCURABSORB = "PERCENTMAXCUR",
    },
    REVERSE_HEALTH_MODE = {},
    EMPTY_EVENTS = {},
    POWER_EVENTS = {},
    POWER_EVENTS_FREQUENT = {},
}
local addon = {
    UF = UF,
    UFText = Text,
    Apply = {},
    Secrets = { UnitMissing = function() return false end },
}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua"))(
    "MidnightSimpleUnitFrames", addon)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua"))(
    "MidnightSimpleUnitFrames", addon)

local currentFS, absorbFS = NewFontString(), NewFontString()
local frame = {
    unit = "player",
    MSUFUnitKey = "player",
    hpTextLeft = currentFS,
    hpTextRight = absorbFS,
}
local spec = {
    key = "player",
    showName = false,
    showHealthText = true,
    showPowerText = false,
    text = {
        healthLeft = "CURRENT",
        healthCenter = "NONE",
        healthRight = "ABSORB",
        healthShortNumbers = true,
        powerLeft = "NONE",
        powerCenter = "NONE",
        powerRight = "NONE",
    },
}
local runtime = Text.CompileTextRuntime(frame, spec, spec.text)
Check(runtime.healthSlotCount == 2, "mixed health slot count")
Check(runtime.healthValueSlotCount == 1, "normal health slot was not isolated")
Check(runtime.healthAbsorbSlotCount == 1, "absorb slot was not isolated")

local HealthText = assert(UF.elements.HealthText, "HealthText element missing")
local events = HealthText.GetEvents(frame, spec)
Check(HasEvent(events, "UNIT_HEALTH"), "mixed text must keep UNIT_HEALTH")
Check(HasEvent(events, "UNIT_ABSORB_AMOUNT_CHANGED"), "mixed text must register the PTR absorb event")

local update = HealthText.SelectUpdate(frame, spec)
update(frame, "MSUF_TEST", "player")
Check(absorbReads == 1, "initial update must read absorbs once")
Check(currentFS.text == "SHORT:600", "current health text mismatch: " .. tostring(currentFS.text))
Check(absorbFS.text == "SHORT:250", "absorb text mismatch: " .. tostring(absorbFS.text))

healthValue = 500
local healthRoute = HealthText.SelectEventUpdate(frame, spec, "UNIT_HEALTH", update)
healthRoute(frame, "UNIT_HEALTH", "player")
Check(absorbReads == 1, "UNIT_HEALTH must not read absorbs")
Check(currentFS.text == "SHORT:500", "UNIT_HEALTH did not update the normal slot")
Check(absorbFS.text == "SHORT:250", "UNIT_HEALTH touched the absorb slot")

absorbValue = 0
local absorbRoute = HealthText.SelectEventUpdate(frame, spec, "UNIT_ABSORB_AMOUNT_CHANGED", update)
absorbRoute(frame, "UNIT_ABSORB_AMOUNT_CHANGED", "player")
Check(absorbReads == 2, "absorb event must perform exactly one absorb read")
Check(absorbFS.text == "", "zero absorb must be hidden")
Check(currentFS.text == "SHORT:500", "absorb event touched the normal health slot")

absorbValue = Secret("SECRET:375", false)
absorbRoute(frame, "UNIT_ABSORB_AMOUNT_CHANGED", "player")
Check(absorbFS.text == "SECRET:375", "PTR secret absorb path did not use TruncateWhenZero")
absorbValue = Secret("SECRET:0", true)
absorbRoute(frame, "UNIT_ABSORB_AMOUNT_CHANGED", "player")
Check(absorbFS.text == "", "PTR secret zero absorb must be hidden")

local onlyFS = NewFontString()
local onlyFrame = { unit = "party1", MSUFUnitKey = "party1", hpTextCenter = onlyFS }
local onlySpec = {
    key = "party1",
    scope = "group",
    showHealthText = true,
    text = { healthLeft = "NONE", healthCenter = "ABSORB", healthRight = "NONE" },
}
Text.CompileTextRuntime(onlyFrame, onlySpec, onlySpec.text)
events = HealthText.GetEvents(onlyFrame, onlySpec)
Check(HasEvent(events, "UNIT_ABSORB_AMOUNT_CHANGED"), "absorb-only group text lacks absorb event")
Check(HasEvent(events, "UNIT_CONNECTION"), "absorb-only group text lacks connection refresh")
Check(not HasEvent(events, "UNIT_HEALTH"), "absorb-only text must not register UNIT_HEALTH")
Check(not HasEvent(events, "UNIT_MAXHEALTH"), "absorb-only text must not register UNIT_MAXHEALTH")

healthValue, healthMaxValue, absorbValue = 600, 1000, 250
local comboFS = NewFontString()
local comboFrame = { unit = "party1", MSUFUnitKey = "party1", hpTextCenter = comboFS }
local comboSpec = {
    key = "party1",
    scope = "group",
    showHealthText = true,
    text = {
        healthLeft = "NONE", healthCenter = "CURMAXABSORB", healthRight = "NONE",
        healthDelimiter = " / ", healthShortNumbers = true,
        healthAbsorbIcon = false, healthCenterAbsorbIcon = true,
    },
}
local comboRuntime = Text.CompileTextRuntime(comboFrame, comboSpec, comboSpec.text)
Check(comboRuntime.healthValueSlotCount == 1, "combined absorb slot must stay on the health value route")
Check(comboRuntime.healthAbsorbSlotCount == 0, "combined absorb slot leaked into absorb-only route")
Check(comboRuntime.healthCombinedAbsorbSlotCount == 1 and comboRuntime.healthUsesAbsorb == true,
    "combined absorb routing flags missing")
events = HealthText.GetEvents(comboFrame, comboSpec)
Check(HasEvent(events, "UNIT_HEALTH") and HasEvent(events, "UNIT_MAXHEALTH"),
    "combined current/max absorb mode lacks health events")
Check(HasEvent(events, "UNIT_ABSORB_AMOUNT_CHANGED"), "combined mode lacks absorb event")
local readsBefore = absorbReads
local comboUpdate = HealthText.SelectUpdate(comboFrame, comboSpec)
comboUpdate(comboFrame, "MSUF_TEST", "party1")
local shield = "|TInterface\\Icons\\INV_Shield_06:0|t"
Check(absorbReads == readsBefore + 1, "combined initial refresh must read absorb exactly once")
Check(comboFS.text == "SHORT:600 / SHORT:1000 + " .. shield .. " SHORT:250",
    "combined absorb/icon text mismatch: " .. tostring(comboFS.text))
absorbValue = 0
HealthText.SelectEventUpdate(comboFrame, comboSpec, "UNIT_ABSORB_AMOUNT_CHANGED", comboUpdate)(
    comboFrame, "UNIT_ABSORB_AMOUNT_CHANGED", "party1")
Check(comboFS.text == "SHORT:600 / SHORT:1000", "combined zero absorb suffix must disappear")
absorbValue = Secret("SECRET:375", false)
HealthText.SelectEventUpdate(comboFrame, comboSpec, "UNIT_ABSORB_AMOUNT_CHANGED", comboUpdate)(
    comboFrame, "UNIT_ABSORB_AMOUNT_CHANGED", "party1")
Check(comboFS.text == "SHORT:600 / SHORT:1000 + " .. shield .. " SECRET:375",
    "combined secret absorb/icon path mismatch: " .. tostring(comboFS.text))
healthValue, healthMaxValue = Secret("SECRET_HP", false), Secret("SECRET_MAX", false)
HealthText.SelectEventUpdate(comboFrame, comboSpec, "UNIT_HEALTH", comboUpdate)(
    comboFrame, "UNIT_HEALTH", "party1", healthValue, healthMaxValue)
Check(comboFS.text == "SHORT:SECRET_HP / SHORT:SECRET_MAX + " .. shield .. " SECRET:375",
    "combined fully secret formatted path mismatch: " .. tostring(comboFS.text))
healthValue, healthMaxValue = 600, 1000

onlySpec.text.healthLeft = "MAX"
events = HealthText.GetEvents(onlyFrame, onlySpec)
Check(HasEvent(events, "UNIT_MAXHEALTH"), "mixed max/absorb group text lacks max-health event")
Check(HasEvent(events, "UNIT_CONNECTION"), "mixed max/absorb group text must retain absorb connection refresh")
Check(HasEvent(events, "UNIT_ABSORB_AMOUNT_CHANGED"), "mixed max/absorb group text lacks absorb event")

_G.MSUF_DB = {
    general = {},
    gf_party = { showHPText = true, textLeft = "ABSORB", textCenter = "NONE", textRight = "NONE", hpAbsorbIcon = true, hpTextLeftAbsorbIcon = false, hpTextCenterAbsorbIcon = true },
    gf_raid = { showHPText = true, textLeft = "NONE", textCenter = "ABSORB", textRight = "NONE" },
    gf_mythicraid = { showHPText = true, textLeft = "NONE", textCenter = "NONE", textRight = "ABSORB" },
}
local groupAddon = { UF = {} }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua"))(
    "MidnightSimpleUnitFrames", groupAddon)
local foundAbsorb = false
for i = 1, #groupAddon.GF.HEALTH_TEXT_MODES do
    foundAbsorb = foundAbsorb or groupAddon.GF.HEALTH_TEXT_MODES[i].key == "ABSORB"
end
Check(foundAbsorb, "group health mode catalogue lacks ABSORB")
Check(groupAddon.GF.FormatHealthText("ABSORB", 1, 1, " / ", false, nil, false, true, 375) == "SHORT:375",
    "group short absorb preview mismatch")
Check(groupAddon.GF.FormatHealthText("ABSORB", 1, 1, " / ", false, nil, false, false, 0) == "",
    "group zero absorb preview must be hidden")
Check(groupAddon.GF.FormatHealthText("CURMAXABSORB", 600, 1000, " / ", false, nil, false, true, 250, true)
        == "SHORT:600 / SHORT:1000 + " .. shield .. " SHORT:250",
    "group combined absorb/icon preview mismatch")
Check(groupAddon.GF.FormatHealthText("PERCENTABSORB", 600, 1000, " / ", false, nil, false, true, 0, true)
        == "60%",
    "group combined zero absorb suffix must disappear")

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Metadata.lua"))(
    "MidnightSimpleUnitFrames", groupAddon)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua"))(
    "MidnightSimpleUnitFrames", groupAddon)
local partySpec = groupAddon.GF.CompileSpec("party", nil, "party1")
local raidSpec = groupAddon.GF.CompileSpec("raid", nil, "raid1")
local mythicSpec = groupAddon.GF.CompileSpec("mythicraid", nil, "raid1")
Check(partySpec.scope == "group" and partySpec.text.healthLeft == "ABSORB", "party absorb scope did not compile")
Check(partySpec.text.healthAbsorbIcon == true, "party absorb icon scope did not compile")
Check(partySpec.text.healthLeftAbsorbIcon == false, "explicit per-slot icon off did not override legacy icon")
Check(partySpec.text.healthCenterAbsorbIcon == true and partySpec.text.healthRightAbsorbIcon == true,
    "per-slot icon fallback did not preserve the legacy scope setting")
Check(raidSpec.scope == "group" and raidSpec.text.healthCenter == "ABSORB", "raid absorb scope did not compile")
Check(mythicSpec.scope == "group" and mythicSpec.text.healthRight == "ABSORB", "mythic-raid absorb scope did not compile")

local menuAddon = { MSUF2 = {} }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_UnitSectionShared.lua"))(
    "MidnightSimpleUnitFrames", menuAddon)
local shared = menuAddon.MSUF2.UnitSectionsShared
Check(shared.HealthBaseMode("CURMAXABSORB") == "CURMAX", "combined mode did not split into its base HP value")
Check(shared.HealthModeWithAbsorb("CURMAX", true) == "CURMAXABSORB", "base HP value did not restore absorb")
Check(shared.HealthModeWithAbsorb("ABSORB", false) == "NONE", "absorb-only mode did not resolve to None")
Check(shared.HealthModeSupportsAbsorb("LEVEL") == false, "identity text must not expose absorb styling")
local filteredModes = shared.HealthBaseModeValues({
    { value = "NONE" }, { value = "CURMAX" }, { value = "ABSORB" }, { value = "CURMAXABSORB" },
})
Check(#filteredModes == 2 and filteredModes[1].value == "NONE" and filteredModes[2].value == "CURMAX",
    "progressive HP dropdown did not remove absorb duplicates")

local specs = assert(io.open(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupSpecs.lua", "r")):read("*a")
local powerModes = specs:match("TEXT_MODES%s*=%s*VTP%s*\"([^\"]+)\"")
local healthModes = specs:match("HEALTH_TEXT_MODES%s*=%s*VTP%s*\"([^\"]+)\"")
Check(powerModes and not powerModes:find("ABSORB=", 1, true), "Absorb leaked into group power modes")
Check(healthModes and healthModes:find("ABSORB=Absorb", 1, true), "Absorb missing from group health modes")
Check(healthModes and healthModes:find("CURMAXABSORB=Current / Max + Absorb", 1, true),
    "combined absorb modes missing from group health modes")

local unitPage = assert(io.open(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_Unit.lua", "r")):read("*a")
local unitText = assert(io.open(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua", "r")):read("*a")
local unitShared = assert(io.open(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_UnitSectionShared.lua", "r")):read("*a")
Check(unitPage:find("CURRENTABSORB=Current + Absorb", 1, true), "combined absorb modes missing from unit health modes")
Check(unitText:find('absorbIconKey = "hpAbsorbIcon"', 1, true), "unit shield icon control missing")
Check(unitText:find("TextSlotAccordion", 1, true) and unitText:find('"HP value"', 1, true),
    "accordion HP slot editor missing")
Check(unitShared:find('opts.label or "Text slots"', 1, true)
        and unitShared:find("function result:SetSelected", 1, true)
        and unitShared:find('"campaign_headericon_open"', 1, true)
        and unitShared:find('"campaign_headericon_closed"', 1, true),
    "shared text-slot accordion visuals or interaction missing")
Check(unitText:find('"off", "Off", "value", "+ Value", "icon"', 1, true),
    "absorb style segment missing")
Check(unitText:find('absorbIconKey = "hpTextLeftAbsorbIcon"', 1, true),
    "slot-aware unit shield style missing")

local groupBars = assert(io.open(root .. "/MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua", "r")):read("*a")
Check(groupBars:find("TextSlotAccordion", 1, true) and groupBars:find('"Power value"', 1, true),
    "accordion group slot editors missing")
Check(groupBars:find('absorbIconKey = "hpTextRightAbsorbIcon"', 1, true),
    "slot-aware group shield style missing")

print("Health absorb text smoke passed (combined modes, accordion slot UX, per-slot icon, routing, scope, zero-hide, PTR secret path)")
