_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing")
local Registry = assert(A.Registry, "Assistant registry missing")

local function fresh()
    if type(A.StartNewTask) == "function" then A.StartNewTask() end
end

local function setting(key)
    return assert(Registry:GetSetting(key), "missing setting " .. tostring(key))
end

local function read(s)
    local ok, value = pcall(s.get)
    assert(ok, "could not read " .. tostring(s.key))
    return value
end

local function writeBaseline(s, value)
    assert(pcall(s.set, value), "could not seed " .. tostring(s.key))
end

local function exactSet(key, baseline, spokenValue, expected)
    fresh()
    local s = setting(key)
    writeBaseline(s, baseline)
    local result = assert(A.Submit("set " .. tostring(s.label) .. " to " .. tostring(spokenValue)))
    local status = result.status or result.result
    local tx = A.lastAssistantTransactionError or {}
    assert(status == "applied" or status == "unchanged",
        tostring(s.label) .. " did not apply: " .. tostring(result.text)
            .. " [" .. tostring(tx.phase) .. "/" .. tostring(tx.target) .. ": " .. tostring(tx.error) .. "]")
    assert(read(s) == expected,
        tostring(s.label) .. " expected " .. tostring(expected) .. ", got " .. tostring(read(s)))
end

local function exactMissingValue(key, baseline)
    fresh()
    local s = setting(key)
    writeBaseline(s, baseline)
    local before = read(s)
    local result = assert(A.Submit("change " .. tostring(s.label)))
    assert((result.status or result.result) == "ambiguous",
        tostring(s.label) .. " did not ask for a value: " .. tostring(result.text))
    assert(read(s) == before, tostring(s.label) .. " changed without a supplied value")
    assert(tostring(result.text or ""):find(tostring(s.label), 1, true),
        tostring(s.label) .. " prompt did not name the exact control")
end

exactSet("general.focusKickIconWidth", 40, "16", 16)
exactSet("player.detachedPowerBarFrameLevelOffset", 6, "0", 0)
exactSet("player.powerSmoothFill", true, "off", false)
exactSet("auras3.player.buff.stackTextSize", 12, "18", 18)
exactSet("menu.aurasUXMode", "basic", "advanced", "advanced")
do
    local s = setting("player.combatStateIndicatorSymbol")
    local parsed = A.Parser.ValueForRegistrySetting(s,
        A.Parser.Normalize("set " .. tostring(s.label) .. " to weapon_axes_crossed"),
        "set " .. tostring(s.label) .. " to weapon_axes_crossed")
    assert(parsed == "weapon_axes_crossed", "symbol parser returned " .. tostring(parsed))
end
exactSet("player.combatStateIndicatorSymbol", "DEFAULT", "weapon_axes_crossed", "weapon_axes_crossed")
exactSet("player.leaderIconStyle", "CLASSIC", "DOTS", "DOTS")
exactSet("player.raidMarkerIconStyle", "CLASSIC", "default", "BLIZZARD")
exactSet("gf_party.readyCheckIconStyle", "CLASSIC", "default", "DEFAULT")
exactSet("gf_party.leaderIconStyle", "CLASSIC", "default", "DEFAULT")

do
    fresh()
    local s = setting("general.focusKickIconWidth")
    writeBaseline(s, 40)
    local result = assert(A.Submit("set " .. tostring(s.label) .. " 17"))
    assert((result.status or result.result) == "applied", "connector-less exact slider command did not apply")
    assert(read(s) == 17, "connector-less exact slider command used the wrong control/value")
end

do
    fresh()
    local s = setting("player.leaderIconStyle")
    writeBaseline(s, "CLASSIC")
    local result = assert(A.Submit("set " .. tostring(s.label) .. " to UXPRO"))
    assert((result.status or result.result) == "applied", "UX Pro pack did not apply")
    assert(tostring(result.text or ""):find("UX Pro", 1, true), "pack response exposed a machine-style value")
end

do
    fresh()
    local s = setting("player.leaderIconStyle")
    local original = _G.MSUF_GetStatusIconPackValues
    _G.MSUF_GetStatusIconPackValues = function()
        return { { value = "LATE_PACK", text = "Late Registered Pack" } }
    end
    local result = assert(A.Submit("set " .. tostring(s.label) .. " to late registered pack"))
    assert((result.status or result.result) == "applied", "late runtime pack did not apply: " .. tostring(result.text))
    assert(read(s) == "LATE_PACK", "late runtime pack was not canonicalized")
    _G.MSUF_GetStatusIconPackValues = original
    if type(A.Parser.RefreshRegistrySettingValues) == "function" then A.Parser.RefreshRegistrySettingValues(s) end
end

exactMissingValue("gf_party.scaleAt10", 100)
exactMissingValue("focustarget.loadCondHideInGroup", false)

do
    fresh()
    local s = setting("player.raidMarkerIconStyle")
    writeBaseline(s, "CLASSIC")
    local result = assert(A.Submit("set " .. tostring(s.label) .. " to BANANA_TEST"))
    assert((result.status or result.result) == "ambiguous", "invalid fixed choice did not ask")
    assert(read(s) == "CLASSIC", "invalid fixed choice mutated the setting")
    assert(tostring(result.text or ""):find("available", 1, true), "invalid fixed choice did not offer valid values")
end

do
    fresh()
    local s = setting("player.anchorFrameName")
    writeBaseline(s, "UIParent")
    local first = assert(A.Submit("change " .. tostring(s.label)))
    assert((first.status or first.result) == "ambiguous", "free string did not ask for a value")
    local help = assert(A.Submit("what options do I have"))
    assert((help.status or help.result) == "ambiguous", "uncertainty reply did not guide")
    assert(read(s) == "UIParent", "uncertainty reply was stored as literal text")
    local cancel = assert(A.Submit("maybe later"))
    assert((cancel.status or cancel.result) == "info", "maybe later did not cancel cleanly")
    assert(read(s) == "UIParent", "cancel reply changed free string")
end

io.write("assistant_exact_setting_control_contract: ok\n")
