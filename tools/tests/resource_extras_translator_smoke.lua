-- resource_extras_translator_smoke.lua <repoRoot>
--
-- Class power resource extras saved under their former names move to the
-- current keys in the profile translator (State/MSUF_ProfileNormalize.lua),
-- once, at profile init and on import. Before wave 4 the move ran inside the
-- class power "is a helper wanted" check on every refresh
-- (ClassPower/MSUF_CP_ResourceExtras.lua), and only for the active profile.
--
--   1. A stored profile already stamped with the current normalization
--      markers still migrates at init (the trusted fast path sees the former
--      keys), keeps the player's choices and the former Arcane look, and is
--      left alone the second time.
--   2. An import payload migrates through the untrusted path.
--   3. The rules match the class power copy: own former choices win, an Arcane
--      helper that was off gains no former look, a current profile is unchanged.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local FORMER_KEYS = { "showArcaneSoul", "arcaneSoulDisplay", "arcaneSoulCountdownWindow", "arcaneSoulBeforeColor",
    "arcaneSoulActiveColor", "arcaneSoulLastColor", "manaFiveSecondRule", "manaRegenTicks", "manaFiveSecondColor",
    "manaTickColor" }

local function Former()
    return { showArcaneSoul = true, arcaneSoulBeforeColor = { .1, .1, .1 }, arcaneSoulActiveColor = { .2, .2, .2 },
        arcaneSoulLastColor = { .3, .3, .3 }, manaFiveSecondRule = true, manaRegenTicks = false,
        manaFiveSecondColor = { .4, .4, .4 }, manaTickColor = { .5, .5, .5 }, arcaneSoulGCDSeconds = 1.5 }
end

local function CheckCarried(b, label)
    Check(b.showArcaneWindow == true and b.arcaneWindowText == "both" and b.arcaneWindowTextFrom == 6
        and b.arcaneWindowWarnLastGCD == true, label .. ": the former Arcane helper's look was not kept")
    Check(b.arcaneWindowColor[1] == .1 and b.arcaneWindowSoulColor[1] == .2 and b.arcaneWindowWarnColor[1] == .3,
        label .. ": the former Arcane colours were not carried")
    Check(b.manaRegenPause == true and b.manaGainPulse == false and b.manaRegenPauseColor[1] == .4
        and b.manaGainPulseColor[1] == .5, label .. ": the former mana settings were not carried")
    for _, key in ipairs(FORMER_KEYS) do Check(b[key] == nil, label .. ": the former key " .. key .. " stayed") end
    Check(b.arcaneSoulGCDSeconds == 1.5, label .. ": a former key without a current one was removed")
end

for _, flavor in ipairs({ "Mainline", "Vanilla", "Mists" }) do
    local world = World.New(root, flavor)
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local N = assert(world.core.ProfileNormalize, flavor .. ": no MSUF.ProfileNormalize")

    -- 1. stored profiles, trusted fast path.
    local stored = { general = {}, bars = {} }
    N.TranslateProfilesToCurrent({ Stored = stored }, "init")
    Check(stored._msufProfileSchema == N.CURRENT_PROFILE_SCHEMA and stored._msufProfileNormalizationRevision ~= nil,
        flavor .. ": the first pass did not stamp the profile")
    local formerBars = Former()
    for key, value in pairs(formerBars) do stored.bars[key] = value end
    Check(N.TranslateProfilesToCurrent({ Stored = stored }, "init") == true,
        flavor .. ": a stamped profile with former resource extras reads as current")
    CheckCarried(stored.bars, flavor .. " init")
    local window = stored.bars.arcaneWindowTextFrom
    Check(N.TranslateProfilesToCurrent({ Stored = stored }, "init") == false and stored.bars.arcaneWindowTextFrom == window,
        flavor .. ": a migrated profile was changed again")

    -- 2. an import payload.
    local payload = { general = {}, bars = Former() }
    N.TranslateProfileToCurrent(payload, { source = "import" })
    CheckCarried(payload.bars, flavor .. " import")

    -- 3. the rules.
    local chosen = { showArcaneSoul = true, arcaneSoulDisplay = "SECONDS", arcaneSoulCountdownWindow = 0 }
    N.CarryFormerResourceExtras(chosen)
    Check(chosen.arcaneWindowText == "seconds" and chosen.arcaneWindowTextFrom == 0,
        flavor .. ": the player's own former choices were replaced")
    local off = { showArcaneSoul = false, arcaneSoulDisplay = "GCD" }
    N.CarryFormerResourceExtras(off)
    Check(off.showArcaneWindow == false and off.arcaneWindowText == "gcds" and off.arcaneWindowTextFrom == nil
        and off.arcaneWindowWarnLastGCD == nil, flavor .. ": a former helper that was off gained the former look")
    local current = { showArcaneWindow = true, arcaneWindowText = "gcds" }
    Check(N.CarryFormerResourceExtras(current) == false and current.arcaneWindowText == "gcds"
        and current.arcaneWindowWarnLastGCD == nil, flavor .. ": a current profile was changed")
    print("resource_extras_translator_smoke: ok (" .. flavor .. ")")
end
