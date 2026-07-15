_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing after dashboard smoke")
local Registry = assert(A.Registry, "Assistant registry missing")

local cases = {
    { input = "change the grow direction of player buffs", key = "auras3.player.buff.growth", visibility = "auras3.player.buff.visible", count = 6, label = "Player Buff Growth" },
    { input = "can you help me to change player buff grow direction", key = "auras3.player.buff.growth", visibility = "auras3.player.buff.visible", count = 6, label = "Player Buff Growth" },
    { input = "could you help me adjust target debuff growth direction", key = "auras3.target.debuff.growth", visibility = "auras3.target.debuff.visible", count = 6, label = "Target Debuff Growth" },
    { input = "help me to configure focus buff growth direction", key = "auras3.focus.buff.growth", visibility = "auras3.focus.buff.visible", count = 6, label = "Focus Buff Growth" },
    { input = "help me adjust boss debuff grow direction", key = "auras3.boss.debuff.growth", visibility = "auras3.boss.debuff.visible", count = 6, label = "Boss Debuff Growth" },
    { input = "help me change party buff grow direction", key = "gf_party.auras.buff.growth", visibility = "gf_party.auras.buff.enabled", count = 6, label = "Party Buff Growth" },
    { input = "help me configure raid debuff growth direction", key = "gf_raid.auras.debuff.growth", visibility = "gf_raid.auras.debuff.enabled", count = 6, label = "Raid Debuff Growth" },
    { input = "help me to adjust mythic raid buff growth direction", key = "gf_mythicraid.auras.buff.growth", visibility = "gf_mythicraid.auras.buff.enabled", count = 6, label = "Mythic Raid Buff Growth" },
    { input = "could you help me configure mythic raid debuff grow direction", key = "gf_mythicraid.auras.debuff.growth", visibility = "gf_mythicraid.auras.debuff.enabled", count = 6, label = "Mythic Raid Debuff Growth" },
    { input = "make player buffs grow differently", key = "auras3.player.buff.growth", visibility = "auras3.player.buff.visible", count = 6, label = "Player Buff Growth" },
    { input = "change target debuff growth", key = "auras3.target.debuff.growth", visibility = "auras3.target.debuff.visible", count = 6, label = "Target Debuff Growth" },
    { input = "I want to change how raid buffs grow", key = "gf_raid.auras.buff.growth", visibility = "gf_raid.auras.buff.enabled", count = 6, label = "Raid Buff Growth" },
    { input = "change how player buffs grow", key = "auras3.player.buff.growth", visibility = "auras3.player.buff.visible", count = 6, label = "Player Buff Growth" },
}

local function assertChoices(label, choices, expectedKey, expectedCount)
    assert(type(choices) == "table" and #choices == expectedCount,
        label .. ": expected " .. tostring(expectedCount) .. " direction choices, got " .. tostring(type(choices) == "table" and #choices or nil))
    for i = 1, #choices do
        local setting = choices[i] and choices[i].setting
        assert(setting and setting.key == expectedKey,
            label .. ": choice " .. tostring(i) .. " lost the requested frame/lane scope")
        assert(choices[i].value ~= nil, label .. ": choice " .. tostring(i) .. " has no enum value")
    end
end

for i = 1, #cases do
    local case = cases[i]
    if A.Knowledge and type(A.Knowledge.MarkDirty) == "function" then A.Knowledge.MarkDirty() end
    A.StartNewTask()

    local parsed = A.Parse(case.input)
    assert(parsed and parsed.kind == "ambiguous", case.input .. ": direct parser did not request a direction")
    assertChoices(case.input .. " parse", parsed.choices, case.key, case.count)

    local growth = assert(Registry:GetSetting(case.key), case.key .. " setting missing")
    local visibility = assert(Registry:GetSetting(case.visibility), case.visibility .. " setting missing")
    local growthBefore = growth.get()
    local visibilityBefore = visibility.get()

    local result = A.Submit(case.input)
    assert((result.status or result.result) == "ambiguous",
        case.input .. ": expected ambiguous choices, got " .. tostring(result.status or result.result) .. "; " .. tostring(result.text))
    assert(tostring(result.text):find(case.label, 1, true), case.input .. ": response lost the exact growth control label")
    assertChoices(case.input .. " submit", A.pendingChoices, case.key, case.count)
    assert(growth.get() == growthBefore, case.input .. ": changed growth before the user selected a direction")
    assert(visibility.get() == visibilityBefore, case.input .. ": incorrectly toggled lane visibility")

    local selectedValue = A.pendingChoices[2].value
    local selected = A.Submit("2")
    assert((selected.status or selected.result) == "applied", case.input .. ": numbered direction choice was not applied")
    assert(growth.get() == selectedValue, case.input .. ": numbered choice changed the wrong setting/value")

    growth.set(growthBefore)
    visibility.set(visibilityBefore)
end

-- A complete exact control plus a closed enum value is still a mutation when
-- ordinary speech omits the connector ("set X RIGHTUP"). The exact-match
-- proof must not be rejected by the general read-only guard.
A.StartNewTask()
local noConnectorGrowth = assert(Registry:GetSetting("auras3.target.debuff.growth"))
local noConnectorBefore = noConnectorGrowth.get()
local noConnector = A.Submit("set target debuff growth RIGHTUP")
assert((noConnector.status or noConnector.result) == "applied", "connector-less exact Aura growth did not apply")
assert(noConnectorGrowth.get() == "RIGHTUP", "connector-less exact Aura growth selected the wrong value")
noConnectorGrowth.set(noConnectorBefore)

-- One sentence that names multiple lanes or scopes must never be partially
-- executed by a single-control shortcut.
local compoundKeys = {
    "auras3.player.buff.growth", "auras3.player.debuff.growth",
    "auras3.target.buff.growth", "auras3.target.debuff.growth",
}
local compoundBefore = {}
for i = 1, #compoundKeys do compoundBefore[i] = assert(Registry:GetSetting(compoundKeys[i])).get() end

for _, case in ipairs({
    { input = "set player buffs and debuffs growth to left", contains = { "Player Buff Growth", "Player Debuff Growth" } },
    { input = "change player buffs and debuffs growth direction", contains = { "Player Buff Growth", "Player Debuff Growth" } },
    { input = "make target buffs grow left and player buffs grow right", contains = { "more than one frame scope", "Player", "Target" } },
    { input = "change target aura growth direction", contains = { "Target Buff Growth", "Target Debuff Growth" } },
}) do
    A.StartNewTask()
    local result = A.Submit(case.input)
    assert((result.status or result.result) == "ambiguous", case.input .. ": compound request did not clarify")
    for i = 1, #case.contains do
        assert(tostring(result.text):find(case.contains[i], 1, true), case.input .. ": missing clarification text " .. case.contains[i])
    end
    assert(not A.pendingChoices or #A.pendingChoices == 0, case.input .. ": compound request exposed one lane's value choices")
    for i = 1, #compoundKeys do
        assert(Registry:GetSetting(compoundKeys[i]).get() == compoundBefore[i], case.input .. ": partially changed " .. compoundKeys[i])
    end
end

-- Read-only wording owns the exact scoped setting and must not fall back to a
-- generic Aura article or an unrelated Group Growth setting.
for _, case in ipairs({
    { input = "what is target buff growth direction?", label = "Target Buff Growth", extra = "Current value:" },
    { input = "why do player debuffs grow down?", label = "Player Debuff Growth", extra = "Current value:" },
    { input = "where is focus buff growth direction", label = "Focus Buff Growth", extra = "lives on Focus" },
}) do
    A.StartNewTask()
    local result = A.Submit(case.input)
    assert((result.status or result.result) == "info", case.input .. ": read-only growth request was not informational")
    assert(tostring(result.text):find(case.label, 1, true), case.input .. ": lost the exact scoped growth label")
    assert(tostring(result.text):find(case.extra, 1, true), case.input .. ": missing exact read-only detail")
    assert(not tostring(result.text):find("Best place to start: Aura Style", 1, true), case.input .. ": fell back to generic Aura Style guidance")
    for i = 1, #compoundKeys do
        assert(Registry:GetSetting(compoundKeys[i]).get() == compoundBefore[i], case.input .. ": read-only request changed " .. compoundKeys[i])
    end
end

A.StartNewTask()
local explicit = A.Submit("make target debuffs grow up")
assert((explicit.status or explicit.result) == "applied", "explicit Aura growth direction regressed")
assert(Registry:GetSetting("auras3.target.debuff.growth").get() == "UP", "explicit Aura growth changed the wrong control")

A.StartNewTask()
local explicitDown = A.Submit("set target debuff growth direction down")
assert((explicitDown.status or explicitDown.result) == "applied", "explicit Down Aura growth direction regressed")
assert(Registry:GetSetting("auras3.target.debuff.growth").get() == "DOWN", "Down Aura growth selected a diagonal layout")

A.StartNewTask()
local sizeBefore = Registry:GetSetting("auras3.player.buff.size").get()
local growthBefore = Registry:GetSetting("auras3.player.buff.growth").get()
local size = A.Submit("make player buffs bigger")
assert((size.status or size.result) == "applied", "Aura icon-size request no longer applies")
assert(Registry:GetSetting("auras3.player.buff.size").get() ~= sizeBefore, "Aura icon-size request did not change icon size")
assert(Registry:GetSetting("auras3.player.buff.growth").get() == growthBefore, "Aura icon-size request was reinterpreted as growth")

-- Retired private-aura profile fields must never fall through to the ordinary
-- Buff/Debuff geometry pair just because the request also says "aura size".
A.StartNewTask()
local partyBuffSize = assert(Registry:GetSetting("gf_party.auras.buff.size"))
local partyDebuffSize = assert(Registry:GetSetting("gf_party.auras.debuff.size"))
local partyBuffSizeBefore, partyDebuffSizeBefore = partyBuffSize.get(), partyDebuffSize.get()
local privateParsed = assert(A.Parse("set party private aura size to 20"))
assert(privateParsed.kind ~= "changes", "private-aura wording produced an executable ordinary-Aura plan")
local privateResult = assert(A.Submit("set party private aura size to 20"))
assert((privateResult.status or privateResult.result) == "info",
    "private-aura wording did not fail closed: " .. tostring(privateResult.text))
assert(partyBuffSize.get() == partyBuffSizeBefore and partyDebuffSize.get() == partyDebuffSizeBefore,
    "private-aura wording changed an ordinary Party Aura size")

io.write("assistant_open_ended_aura_growth_regression: ok (" .. tostring(#cases) .. " open-ended prompts)\n")
