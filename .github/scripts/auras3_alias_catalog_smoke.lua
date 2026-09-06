-- Real generated data + native compiler contracts. No live WoW CPU claim.
local root = arg[1] or "."
local loader = assert(loadfile(root .. "/.github/scripts/auras3_test_loader.lua"))()
local function Forbidden() error("alias compilation touched the aura/event hotpath", 2) end
_G.CreateFrame, _G.pcall = Forbidden, Forbidden
_G.C_Timer = { After = Forbidden, NewTicker = Forbidden }
_G.C_Spell = { GetSpellName = Forbidden }
_G.C_UnitAuras = setmetatable({}, { __index = function() return Forbidden end })
local function SameIDs(actual, expected)
    assert(#actual == #expected, "alias count changed")
    local hash = {}
    for _, id in ipairs(actual) do assert(not hash[id], "duplicate alias"); hash[id] = true end
    for _, id in ipairs(expected) do assert(hash[id], "missing alias " .. id) end
end
local aliasFile = root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_AuraAliases.lua"
local cases = {
    {185313, {169629,169630,185313,185422,394029,394929}},
    {382514, {341532,341533,382514,386237}},
    {22812, {20655,22812,173558,182872,368364}},
    {102543, {102543,252071}},
    {1319318, {1290336,1290480,1292348,1295670,1303196,1310470,1319318}},
}
local function Load(locale)
    _G.GetLocale = function() return locale end
    local ns = {}
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_DefensiveData.lua"))("MSUF", ns)
    loader.LoadAliasCatalog(root, ns)
    return ns
end
local ns = Load("enUS")
local A3 = ns.MSUF_Auras3
for _, case in ipairs(cases) do
    A3.CompileCustomAuraAliases({[case[1]]=true})
    SameIDs(assert(A3.AuraSpellIDAliases[case[1]]), case[2])
end
A3.CompileCustomAuraAliases({[100]=true})
assert(#A3.AuraSpellIDAliases[100] == 340, "catalog truncated a group above 100 IDs")
A3.CompileCustomAuraAliases({[123]=true, [99999999]=true})
assert(A3.AuraSpellIDAliases[123] == nil and A3.AuraSpellIDAliases[99999999] == nil,
    "unknown ID guessed an alias")
local exact = {}; A3.AddAuraSpellIDAndAliases(exact, 99999999)
assert(exact[99999999], "uncatalogued IDs lost exact native selection")

-- Locale collisions are intentional: Schattentanz has an extra ID, and Charge
-- has 38 German IDs vs 340 English IDs. No union across unrelated translations.
local de = Load("deDE").MSUF_Auras3
de.CompileCustomAuraAliases({[185313]=true,[100]=true})
SameIDs(de.AuraSpellIDAliases[185313], {146636,169629,169630,185313,185422,394029,394929})
assert(#de.AuraSpellIDAliases[100] == 38)
local retained = #de.AuraAliasCatalog.common + #de.AuraAliasCatalog.localized
assert(retained < 1600000, "catalog retained an expanded Lua reverse index")

-- Instrument ONLY the desktop compiler's string searches. Cache hits and
-- negative hits must never search again, including after an identity change.
local searches = 0
local env = setmetatable({ string = setmetatable({
    find = function(...) searches = searches + 1; return string.find(...) end,
}, {__index=string}) }, {__index=_G})
setfenv(assert(loadfile(aliasFile)), env)("MSUF", ns)
local selected = {[185313]=true,[22812]=true,[123]=true}
A3.CompileCustomAuraAliases(selected)
local initial = searches
for _=1,10000 do A3.CompileCustomAuraAliases(selected) end
assert(searches == initial, "cached compilation rescanned catalog data")
assert(A3.AuraNameResolver == nil, "live resolver survived")

-- Explicit aliases whose names differ are additive and do not mutate the
-- decoded same-name group subsequently shared by another configured ID.
A3.AuraSpellIDAliases[102543] = {99999999}
A3.CompileCustomAuraAliases({[102543]=true,[252071]=true})
SameIDs(A3.AuraSpellIDAliases[102543], {102543,252071,99999999})
SameIDs(A3.AuraSpellIDAliases[252071], {102543,252071})
print("PASS alias catalog: exact enUS/deDE/hotfix data, >100 aliases, unknown IDs, static aliases, no aura APIs/events/pcall, cached hits/misses")
