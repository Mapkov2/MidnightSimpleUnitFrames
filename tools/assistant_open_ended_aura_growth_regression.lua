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
    { input = "make player buffs grow differently", key = "auras3.player.buff.growth", visibility = "auras3.player.buff.visible", count = 6, label = "Player Buff Growth" },
    { input = "change target debuff growth", key = "auras3.target.debuff.growth", visibility = "auras3.target.debuff.visible", count = 6, label = "Target Debuff Growth" },
    { input = "I want to change how raid buffs grow", key = "gf_raid.auras.buff.growth", visibility = "gf_raid.auras.buff.enabled", count = 4, label = "Raid Buff Growth" },
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

io.write("assistant_open_ended_aura_growth_regression: ok (" .. tostring(#cases) .. " open-ended prompts)\n")
