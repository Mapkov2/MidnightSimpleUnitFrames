-- power_foreign_token_text_skip_smoke.lua
-- UNIT_POWER_* names the resource that changed. A power bar rejects a tick for
-- a resource it does not display (COMBO_POINTS on an energy bar) and flags that
-- in its sixth return. The compiled Power -> PowerText route then skips the
-- text: the text shows the bar's resource, so the tick cannot change it, and
-- running it re-read the power and re-formatted the same string natively (one
-- Perfy capture: 117 of 1,054 player UNIT_POWER_FREQUENT ticks).
-- This smoke proves, on the shipped sources:
--   * every token-rejection site in the power element returns the flag,
--   * the flag is the only thing that suppresses the text (a hidden bar, a
--     missing bar and a matching token still reach the text),
--   * both the unit and the target route variants honor it.
-- Run with Lua 5.1 and the repo root as arg 1.
local root = assert(arg[1], "repo root required"):gsub("\\", "/")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()
local POWER = "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua"
local CORE = "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua"
local power = Slice.Read(root .. "/" .. POWER)
local core = Slice.Read(root .. "/" .. CORE)

-- Every site that compares the event token must flag its rejection.
local _, checks = power:gsub("bar%._msufPowerEventToken ~= eventPowerToken", "")
local _, flagged = power:gsub(
    "CachedDisplayPowerIdentityIsCurrent%(bar, unit, eventPowerToken%) then return nil, nil, nil, nil, nil, true end", "")
Check(checks == 5, "expected 5 power token checks, found " .. checks)
Check(flagged == checks, "every power token check must return the foreign flag (" .. flagged .. "/" .. checks .. ")")

-- The bar paths, with their collaborators stubbed. Only the event-token
-- rejection and the normal value path of the CURRENT route are exercised.
local identityCurrent = true
local absoluteCalls = 0
local function Identity() return identityCurrent end
local function UpdateAbsolute()
    absoluteCalls = absoluteCalls + 1
    return 42, nil, 3, "ENERGY"
end
local function NoOp() end

local PATHS = {
    "UpdatePercentPath", "UpdateAbsolutePath", "UpdateCurrentPath",
    "UpdateCurrentPercentPath", "UpdateGroupPercentPathLean",
}
local function CompilePath(name)
    local body = Slice.Function(power, "local function " .. name, POWER)
    local chunk = "local CachedDisplayPowerIdentityIsCurrent, UpdateAbsolute, SetColor, SnapBarInterpolation = ...\n"
        .. body .. "\nreturn " .. name
    return assert(loadstring(chunk, name))(Identity, UpdateAbsolute, NoOp, NoOp)
end

local function EnergyFrame(shown)
    return {
        MSUFUnitKey = "player",
        targetPowerBar = {
            _msufShown = shown,
            _msufPowerTypeKnown = true,
            _msufPowerToken = "ENERGY",
            _msufPowerEventToken = "ENERGY",
        },
    }
end

for i = 1, #PATHS do
    local name = PATHS[i]
    local fn = CompilePath(name)
    local results = { fn(EnergyFrame(true), "UNIT_POWER_FREQUENT", "player", "COMBO_POINTS") }
    Check(results[6] == true and results[1] == nil,
        name .. ": a foreign token must return the foreign flag in slot 6")
    -- A hidden bar returns before the token check: no flag, the text still runs.
    local hidden = { fn(EnergyFrame(false), "UNIT_POWER_FREQUENT", "player", "COMBO_POINTS") }
    Check(hidden[6] == nil, name .. ": a hidden bar must not flag the tick as foreign")
end

-- The CURRENT route still paints and returns its value for its own token, and
-- for a foreign token while Class Resources changed the displayed identity.
local current = CompilePath("UpdateCurrentPath")
local own = { current(EnergyFrame(true), "UNIT_POWER_FREQUENT", "player", "ENERGY") }
Check(own[1] == 42 and own[6] == nil and absoluteCalls == 1, "own token must paint and return the value")
identityCurrent = false
local changed = { current(EnergyFrame(true), "UNIT_POWER_FREQUENT", "player", "COMBO_POINTS") }
Check(changed[1] == 42 and changed[6] == nil and absoluteCalls == 2,
    "a foreign token during a displayed-identity change must still paint")
identityCurrent = true

-- The compiled route: the flag, and only the flag, suppresses the text.
local routeBody = Slice.Function(core, "local function BuildPowerRoute", CORE)
local BuildPowerRoute = assert(loadstring(routeBody .. "\nreturn BuildPowerRoute", "BuildPowerRoute"))()

local barResult
local function Bar() return unpack(barResult, 1, 6) end
local textCalls, textPower
local function Text(_, _, unit, value)
    textCalls = textCalls + 1
    textPower = value
    return unit
end

local frame = { MSUFUnitKey = "player" }
local CASES = {
    { "own token", { 42, nil, 3, "ENERGY", false }, 1, 42 },
    { "foreign token", { nil, nil, nil, nil, nil, true }, 0, nil },
    { "hidden or missing bar", {}, 1, nil },
}
for _, target in ipairs({ false, "target" }) do
    local route = BuildPowerRoute(Bar, Text, nil, nil, false, target or nil)
    for c = 1, #CASES do
        local case = CASES[c]
        barResult = case[2]
        textCalls, textPower = 0, "unset"
        route(frame, "UNIT_POWER_FREQUENT", "player", "ENERGY")
        local label = (target and "target route: " or "unit route: ") .. case[1]
        Check(textCalls == case[3], label .. " text calls " .. textCalls .. " ~= " .. case[3])
        if case[3] == 1 then Check(textPower == case[4], label .. " passed the wrong power value") end
    end
    -- A frame without a bar keeps its text-only update.
    local textOnly = BuildPowerRoute(nil, Text, nil, nil, false, target or nil)
    textCalls = 0
    textOnly(frame, "UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
    Check(textCalls == 1, "a text-only route must keep updating")
end

print("power_foreign_token_text_skip_smoke: ok")

-- 2026-10-14, Lua 5.1 x86, actual registered CURRENT bar/text route:
-- matching ENERGY stays at 235021 VM instructions/1000 notifications;
-- rejected COMBO_POINTS moves 78008 -> 82008 (+4/event, production 6.501's
-- exact delta). Matching native work stays at 1000 value reads, foreign at
-- zero; both paths stay at 0.055 KB. No extra instruction headroom is added.
for _, flavor in ipairs({ "Mainline", "Vanilla" }) do
    local world = dofile(root .. "/tools/tests/client_world.lua").New(root, flavor)
    local env = world.env
    env.Enum = setmetatable({ PowerType = { Mana = 0, Rage = 1, Energy = 3, ComboPoints = 4 } }, { __index = env.Enum })
    local reads, typeReads = 0, 0
    env.UnitPowerType = function() typeReads = typeReads + 1 return 3, "ENERGY" end
    env.UnitPower = function() reads = reads + 1 return 50 end
    env.UnitPowerMax = function() reads = reads + 1 return 100 end
    env.UnitPowerPercent = function() reads = reads + 1 return 50 end
    world:Boot()
    assert(not world:FirstFailure())
    env.MSUF_EnsureDB(true)
    local UF = world.core.UF
    UF.Config.Refresh()
    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame:SetSize(200, 40)
    frame.MSUFUnitKey, frame.unit = "target", "target"
    UF.AttachFrame(frame, { scope = "unit" })
    local spec = UF.Config.GetSpec("target")
    spec.enabled, spec.showPowerText, spec.power.enabled = true, true, true
    spec.power.mode = "power"
    spec.text.powerLeft, spec.text.powerCenter, spec.text.powerRight = "NONE", "CURRENT", "NONE"
    spec.text.healthLeft, spec.text.healthCenter, spec.text.healthRight = "NONE", "NONE", "NONE"
    spec.text.showName = false
    UF.ApplySpec(frame, spec, "MSUF_APPLY", { Text = true, Power = true, PowerText = true })
    assert(frame:IsEventRegistered("UNIT_POWER_UPDATE"), "power event was not registered")
    local handler = assert(frame:GetScript("OnEvent"))
    local function Drain()
        for _, ticker in ipairs(world.widgets.tickers) do
            if not ticker.cancelled then ticker.callback() end
        end
    end
    local natives = {}
    for _, name in ipairs({"UnitPowerType", "UnitPower", "UnitPowerMax", "UnitPowerPercent", "UnitExists", "GetTime"}) do
        if type(env[name]) == "function" then natives[env[name]] = true end
    end
    for _, name in ipairs({"SetValue", "SetMinMaxValues", "SetText", "SetFormattedText", "SetTextColor",
        "SetStatusBarColor", "IsShown", "IsVisible", "Show", "Hide"}) do
        natives[world.widgets.Methods[name]] = true
    end
    for _, token in ipairs({"ENERGY", "COMBO_POINTS"}) do
        for _ = 1, 100 do handler(frame, "UNIT_POWER_UPDATE", "target", token) end
        Drain()
        local ticks, kb = 0, math.huge
        for _ = 1, 2 do
            collectgarbage("collect")
            collectgarbage("stop")
            local count = 0
            local before = collectgarbage("count")
            debug.sethook(function() count = count + 1 end, "", 1)
            for _ = 1, 1000 do handler(frame, "UNIT_POWER_UPDATE", "target", token) end
            debug.sethook()
            ticks = math.max(ticks, count)
            kb = math.min(kb, collectgarbage("count") - before)
            collectgarbage("restart")
            Drain()
        end
        reads, typeReads = 0, 0
        local nativeCalls = 0
        debug.sethook(function()
            if natives[debug.getinfo(2, "f").func] then nativeCalls = nativeCalls + 1 end
        end, "c")
        for _ = 1, 1000 do handler(frame, "UNIT_POWER_UPDATE", "target", token) end
        debug.sethook()
        local expectedTicks = token == "ENERGY" and 235021 or 82008
        local expectedNative = token == "ENERGY" and 1000 or 0
        assert(ticks <= expectedTicks, flavor .. ": " .. token .. " exceeded measured VM budget: " .. ticks)
        assert(kb <= 0.1, flavor .. ": power event allocated " .. kb .. " KB")
        assert(nativeCalls == expectedNative and reads == expectedNative and typeReads == 0,
            flavor .. ": power event added native or metadata reads")
        print(string.format("power_event_budget: ok (%s %s: %d instructions, %.3f KB, %d native calls)",
            flavor, token, ticks, kb, nativeCalls))
    end
end
