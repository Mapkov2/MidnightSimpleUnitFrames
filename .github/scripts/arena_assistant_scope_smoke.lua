-- Pins the hand-written Assistant Arena scope and castbar parity contracts.
-- Run from the repository root: lua .github/scripts/arena_assistant_scope_smoke.lua

local function Read(path)
    local handle = assert(io.open(path, "rb"), "missing file: " .. path)
    local source = handle:read("*a")
    handle:close()
    return (source:gsub("\r\n", "\n"))
end

local function Slice(source, startMarker, endMarker)
    local first = assert(source:find(startMarker, 1, true), "missing start marker: " .. startMarker)
    local last = assert(source:find(endMarker, first + #startMarker, true), "missing end marker: " .. endMarker)
    return source:sub(first, last - 1)
end

local function Contains(source, needle)
    return source:find(needle, 1, true) ~= nil
end

local function AssertContains(source, needle, message)
    assert(Contains(source, needle), message .. ": " .. needle)
end

local function ContainsValue(values, wanted)
    for index = 1, #(values or {}) do
        if values[index] == wanted then return true end
    end
    return false
end

local namespace = { MSUF2 = {}, Assistant = {} }
assert(loadfile("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantParser_Core_Data.lua"))(
    "MidnightSimpleUnitFrames_Assistant", namespace
)
assert(loadfile("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantParser_Core.lua"))(
    "MidnightSimpleUnitFrames_Assistant", namespace
)

local parserCore = assert(namespace.Assistant.Parser)
local arenaUnits = parserCore.DetectUnits(parserCore.Normalize("set arena width to 180"))
assert(#arenaUnits == 1 and arenaUnits[1] == "arena",
    "central DetectUnits did not resolve the explicit Arena scope")
local allUnits = parserCore.DetectUnits(parserCore.Normalize("set all unitframes width to 180"))
assert(ContainsValue(allUnits, "arena"),
    "central DetectUnits omitted Arena from all unitframes")
local arenaPage, arenaPageLabel = parserCore.PageForText(parserCore.Normalize("open arena frames"))
assert(arenaPage == "uf_arena" and arenaPageLabel == "Arena",
    "central page routing did not resolve Arena Frames")

local parserSource = Read("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantParser.lua")
AssertContains(parserSource, 'units = { "player", "target", "focus", "boss", "arena" }',
    "all-castbar width mode omitted Arena")
local parserArenaKeys = {
    "general.arenaCastbarMatchWidth",
    "general.arenaCastIconSize", "general.arenaCastIconPosition",
    "general.arenaCastIconOffsetX", "general.arenaCastIconOffsetY",
    "general.arenaCastIconSpacing", "general.arenaCastIconBorderStyle",
    "general.arenaCastSpellNamePosition", "general.arenaCastTextOffsetX",
    "general.arenaCastTextOffsetY", "general.arenaCastSpellNameFontSize",
    "general.arenaCastSpellNameMaxWidth", "general.arenaCastSpellNameTruncate",
    "general.arenaCastTimeFormat", "general.arenaCastTimePosition",
    "general.arenaCastTimeOffsetX", "general.arenaCastTimeOffsetY",
    "general.arenaCastTimeFontSize",
    "general.showArenaCastTime", "general.showArenaCastIcon", "general.showArenaCastName",
    "general.arenaCastbarWidth", "general.arenaCastbarHeight",
    "general.arenaCastbarOffsetX", "general.arenaCastbarOffsetY",
    "general.enableArenaCastbar",
}
for index = 1, #parserArenaKeys do
    AssertContains(parserSource, parserArenaKeys[index],
        "hand-written parser omitted an Arena castbar key")
end

local registrySource = Read("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantParser_Registry.lua")
local registryScopeBlock = Slice(registrySource,
    "local POWER_UNIT_ORDER", "local function ParseGlobalFontFamilyShortcut")
AssertContains(registryScopeBlock,
    'local POWER_UNIT_ORDER = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss", "arena" }',
    "power unit order omitted Arena")
AssertContains(registryScopeBlock,
    'local CASTBAR_INTERRUPT_UNITS = { "player", "target", "focus", "boss", "arena" }',
    "castbar interrupt unit order omitted Arena")

local fontScopeBlock = Slice(registrySource,
    "local FONT_RENDERING_UNIT_SCOPES", "local FONT_RENDERING_GROUP_SCOPES")
AssertContains(fontScopeBlock, 'arena = "arena"',
    "font-rendering unit scopes omitted Arena")

local backendBlock = Slice(registrySource,
    "local CASTBAR_BACKEND_UNITS", "function P.ParseCastbarPositionRegistryShortcut")
AssertContains(backendBlock,
    'local CASTBAR_BACKEND_UNITS = { "player", "target", "focus", "boss", "arena" }',
    "castbar backend unit order omitted Arena")
AssertContains(backendBlock, 'arena = "general.enableArenaCastbar"',
    "castbar backend enable map omitted Arena")
AssertContains(backendBlock, "Target, Focus, Boss, and Arena cast bars can use MSUF or be hidden.",
    "castbar backend help omitted Arena")

local positionBlock = Slice(registrySource,
    "function P.ParseCastbarPositionRegistryShortcut", "function P.ParsePowerBarGradientRegistryShortcut")
AssertContains(positionBlock, 'arena = "arenaCast"',
    "castbar fixed-position prefix map omitted Arena")
AssertContains(positionBlock, 'units = { "player", "target", "focus", "boss", "arena" }',
    "castbar fixed-position all/fallback scopes omitted Arena")

assert(loadfile("MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantSettingGraph_Data.lua"))(
    "MidnightSimpleUnitFrames_Assistant", namespace
)
local graphData = assert(namespace.Assistant.SettingGraphData)
assert(ContainsValue(graphData.unitScopes, "arena"),
    "setting graph unit scopes omitted Arena")
assert(ContainsValue(graphData.auraScopes, "arena"),
    "setting graph aura scopes omitted Arena")
local inheritanceById = {}
for index = 1, #(graphData.scopedInheritanceRules or {}) do
    local rule = graphData.scopedInheritanceRules[index]
    inheritanceById[rule.id] = rule
end
assert(ContainsValue(assert(inheritanceById["font-scope-inheritance"]).scopes, "arena"),
    "setting graph font inheritance omitted Arena")
assert(ContainsValue(assert(inheritanceById["bar-scope-inheritance"]).scopes, "arena"),
    "setting graph bar inheritance omitted Arena")

print("arena_assistant_scope_smoke: ok")
