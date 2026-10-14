-- UnitPowerType's display/color token may differ from UNIT_POWER_UPDATE's
-- canonical resource token. Exercise registered events through the real graph.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local World = dofile(root .. "/tools/tests/client_world.lua")
local world = World.New(root, flavor)
local env = world.env
env.type, env.issecretvalue = type, issecretvalue
env.Enum = setmetatable({ PowerType = {
    Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4, Runes = 5,
    RunicPower = 6, SoulShards = 7, LunarPower = 8, HolyPower = 9, Alternate = 10,
    Maelstrom = 11, Chi = 12, Insanity = 13, BurningEmbers = 14, DemonicFury = 15,
    ArcaneCharges = 16, Fury = 17, Pain = 18, Essence = 19,
} }, { __index = env.Enum })
local kind, displayToken, current, maximum = 3, "POWER_TYPE_VOID_ENERGY", 49, 100
local typeReads, valueReads = 0, 0
env.UnitPowerType = function() typeReads = typeReads + 1; return kind, displayToken end
env.UnitPower = function(_, requested)
    valueReads = valueReads + 1
    if Secrets.IsSecret(kind) or Secrets.IsSecret(displayToken) then return current end
    return (requested == nil or requested == kind) and current or 49
end
env.UnitPowerMax = function() return maximum end
env.UnitPowerPercent = function(_, requested)
    valueReads = valueReads + 1
    if Secrets.IsSecret(kind) or Secrets.IsSecret(displayToken) then return current * 100 / maximum end
    return (requested == nil or requested == kind) and current * 100 / maximum or 49
end
env.AbbreviateNumbers, env.AbbreviateLargeNumbers, env.ShortenNumber = tostring, tostring, tostring
env.BreakUpLargeNumbers = tostring
local displayColor = { r = 0.7, g = 0.2, b = 0.9 }
env.PowerBarColor = {
    MANA = { r = 0, g = 0.3, b = 1 }, RAGE = { r = 1, g = 0, b = 0 },
    ENERGY = { r = 1, g = 1, b = 0 }, POWER_TYPE_VOID_ENERGY = displayColor,
}
world:Boot()
assert(not world:FirstFailure(), "real " .. flavor .. " graph failed to load")
env.MSUF_EnsureDB(true)
local UF = world.core.UF
UF.Config.Refresh()

local function Drain()
    for _, ticker in ipairs(world.widgets.tickers) do
        if not ticker.cancelled then ticker.callback() end
    end
end

local function Event(frame, token, event)
    event = event or "UNIT_POWER_UPDATE"
    assert(frame:IsEventRegistered(event), "compiled route did not register " .. event)
    world:FireEvent(event, frame.MSUFUnitKey, token)
end

local cases = 0
for _, unit in ipairs({ "target", "focus", "boss1" }) do
  if world.core.Client.SupportsUnit(unit) then
    for _, mode in ipairs({ "PERCENT", "CURRENT", "CURMAX", "CURPERCENT" }) do
      for _, barEnabled in ipairs({ true, false }) do
        kind, displayToken, current, maximum = 3, "POWER_TYPE_VOID_ENERGY", 49, 100
        local frame = env.CreateFrame("Button", nil, env.UIParent)
        frame:SetSize(200, 40)
        frame.MSUFUnitKey, frame.unit = unit, unit
        UF.AttachFrame(frame, { scope = "unit" })
        local spec = UF.Config.GetSpec(unit)
        spec.enabled, spec.showPowerText, spec.power.enabled = true, true, barEnabled
        spec.power.mode = "power"
        spec.text.powerLeft, spec.text.powerCenter, spec.text.powerRight = "NONE", mode, "NONE"
        spec.text.healthLeft, spec.text.healthCenter, spec.text.healthRight = "NONE", "NONE", "NONE"
        spec.text.showName, spec.text.powerColorByType = false, true
        UF.ApplySpec(frame, spec, "MSUF_APPLY", { Text = true, Power = true, PowerText = true })
        local bar, text = frame.targetPowerBar, frame.powerTextCenter
        local label = flavor .. "/" .. unit .. "/" .. mode
        assert(text:GetText():find("49", 1, true), label .. ": initial sample missing")

        current, typeReads = 72, 0
        Event(frame, "ENERGY")
        if barEnabled then
            assert(bar.value == 72, label .. ": display token rejected canonical ENERGY tick")
            assert(typeReads == 0, label .. ": canonical matching tick reread metadata")
            assert(bar._msufPowerEventToken == "ENERGY", label .. ": canonical event identity missing")
            assert(bar._msufPowerToken == displayToken, label .. ": display token was overwritten")
            assert(bar._msufR == displayColor.r and bar._msufG == displayColor.g
                and bar._msufB == displayColor.b, label .. ": display color was lost")
        end
        Drain()
        assert(text:GetText():find("72", 1, true), label .. ": text froze behind bar filter")

        -- A different canonical resource still must not dirty this bar's text.
        current, valueReads = 84, 0
        Event(frame, "COMBO_POINTS")
        if barEnabled then
            assert(valueReads == 0 and frame._msufTextDirtyMask == nil,
                label .. ": foreign resource read values or queued text")
        end
        Drain()
        current = 87
        Event(frame, "FUTURE_RESOURCE")
        Drain()
        assert(text:GetText():find("87", 1, true), label .. ": unfamiliar event token was rejected")

        -- Native display-power notifications replace both cached identities;
        -- the next value tick uses the canonical token of the new resource.
        for _, identity in ipairs({ { 1, "POWER_TYPE_ENCOUNTER_RAGE", "RAGE", 65 },
            { 0, "POWER_TYPE_ENCOUNTER_MANA", "MANA", 81 } }) do
            kind, displayToken, current = identity[1], identity[2], identity[4]
            Event(frame, identity[3], "UNIT_DISPLAYPOWER")
            Event(frame, identity[3])
            Drain()
            assert(text:GetText():find(tostring(current), 1, true), label .. ": resource transition froze")
            if barEnabled then
                assert(bar._msufPowerEventToken == identity[3] and bar._msufPowerToken == displayToken,
                    label .. ": numeric and display identities were conflated")
            end
        end

        -- Missing and future numeric resources cannot establish a safe reject
        -- filter. Their updates remain live without guessing an event token.
        for _, unknown in ipairs({ false, 12345 }) do
            kind, displayToken, current = unknown or nil, "POWER_TYPE_UNKNOWN_DISPLAY", 53
            Event(frame, "ENERGY", "UNIT_DISPLAYPOWER")
            Event(frame, "ENERGY")
            Drain()
            assert(text:GetText():find("53", 1, true), label .. ": unknown resource froze")
            if barEnabled then assert(bar._msufPowerEventToken == nil, label .. ": unknown token guessed") end
            current = 67
            Event(frame, "ENERGY")
            Drain()
            assert(text:GetText():find("67", 1, true), label .. ": unknown resource stayed stale")
        end
        if flavor == "Mainline" and unit == "target" and mode == "PERCENT" and barEnabled then
            -- Plain native values isolate metadata safety from value rendering.
            local stop = Secrets.Watch(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua",
                { strict = true })
            for _, identity in ipairs({ { Secrets.New("number"), "POWER_TYPE_VOID_ENERGY" },
                { 3, Secrets.New("string") } }) do
                kind, displayToken, current = identity[1], identity[2], 59
                Event(frame, "ENERGY", "UNIT_DISPLAYPOWER")
                assert(bar._msufPowerEventToken == nil, "opaque metadata established an event filter")
                current = 71
                Event(frame, "ENERGY")
                Drain()
                assert(bar.value == 71 and text:GetText():find("71", 1, true),
                    "opaque power metadata prevented value updates: bar=" .. tostring(bar.value) .. ", text=" .. text:GetText())
            end
            local violations = stop()
            assert(#violations == 0, table.concat(violations, "\n"))
        end
        frame:UnregisterAllEvents()
        cases = cases + 1
      end
    end
  end
end
print("power_event_identity_smoke: ok (" .. flavor .. ", " .. cases .. " registered bar/text cases)")
