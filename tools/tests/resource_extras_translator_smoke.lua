-- resource_extras_translator_smoke.lua <repoRoot>
--
-- Class power resource extras saved under their former names move to the
-- current keys in the profile translator (State/MSUF_ProfileNormalize.lua),
-- once, at profile init and on import. Before wave 4 the move ran inside the
-- class power "is a helper wanted" check on every refresh
-- (ClassPower/MSUF_CP_ResourceExtras.lua), and only for the active profile;
-- the translator is now its only owner.
--
--   1. A stored profile already stamped with the current normalization
--      markers still migrates at init (the trusted fast path sees the former
--      keys), keeps the player's choices and the former Arcane look, and is
--      left alone the second time.
--   2. An import payload migrates through the untrusted path.
--   3. The rules: own former choices win, an Arcane helper that was off gains
--      no former look, a current profile is unchanged.
--   4. Every road that put a profile's bars in front of the class power code
--      reaches the translator: first login on a flat saved DB, a login over
--      stored profiles (active and inactive), a profile switch, and the
--      imports (active profile, new profile, external, unit frame kind).
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

-- The keys a profile saved under the former names does not have yet.
local CURRENT_KEYS = { "showArcaneWindow", "arcaneWindowText", "arcaneWindowTextFrom", "arcaneWindowWarnLastGCD",
    "arcaneWindowColor", "arcaneWindowSoulColor", "arcaneWindowWarnColor", "manaRegenPause", "manaGainPulse",
    "manaRegenPauseColor", "manaGainPulseColor" }
local function PlantFormer(profile)
    for _, key in ipairs(CURRENT_KEYS) do profile.bars[key] = nil end
    for key, value in pairs(Former()) do profile.bars[key] = value end
end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = Copy(item) end
    return out
end

local function PathWorld(flavor)
    local world = World.New(root, flavor)
    local env, ns = world.env, world.core
    env.InCombatLockdown = function() return false end
    env.IsInInstance = function() return false, "none" end
    env.IsInGroup = function() return false end
    local load = world.LoadFile
    function world:LoadFile(path, addon, namespace)
        if path:match("/State/MSUF_Profiles.lua$") then
            -- Keep the real storage and normalization pipeline; the frame
            -- renderers behind the runtime apply are outside this test.
            ns.ProfileRuntime.Apply = function()
                ns.ProfileVariants.ResolveCurrent()
                ns.ProfileSync.Activate(); ns.ProfileSync.RefreshEvents()
            end
        end
        return load(self, path, addon, namespace)
    end
    world:Boot()
    local failure = world:FirstFailure()
    Check(failure == nil, flavor .. ": path world load failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    return world
end

local function PathProof(flavor)
    local world = PathWorld(flavor)
    local env, ns = world.env, world.core
    local label = flavor .. " path"

    -- First login on a flat saved DB (the pre-profile layout): the DB becomes the Default profile.
    env.MSUF_DB = { general = {}, player = { width = 150 }, bars = Former() }
    env.MSUF_GlobalDB = { profiles = {}, char = {} }
    env.MSUF_InitProfiles()
    Check(env.MSUF_ActiveProfile ~= nil and env.MSUF_DB.bars ~= nil, label .. ": first login bound no profile")
    CheckCarried(env.MSUF_DB.bars, label .. " first login")
    local activeName = env.MSUF_ActiveProfile
    local factory = Copy(env.MSUF_DB)
    ns.MSUF_CreateFactoryDefaultProfile = function() return Copy(factory) end

    -- Login over stored profiles that carry former names: the active one and an inactive one.
    Check(env.MSUF_CreateProfile("Other") == true, label .. ": no second profile")
    local saved = Copy(env.MSUF_GlobalDB)
    for _, name in ipairs({ activeName, "Other" }) do PlantFormer(saved.profiles[name]) end
    env.MSUF_GlobalDB = Copy(saved)
    env.MSUF_DB, env.MSUF_ActiveProfile = nil, nil
    env.MSUF_InitProfiles()
    Check(env.MSUF_ActiveProfile == activeName, label .. ": the login changed the active profile")
    CheckCarried(env.MSUF_GlobalDB.profiles[activeName].bars, label .. " login, active profile")
    CheckCarried(env.MSUF_GlobalDB.profiles.Other.bars, label .. " login, inactive profile")
    Check(env.MSUF_DB == env.MSUF_GlobalDB.profiles[activeName], label .. ": the login did not bind the stored table")

    -- A new character over account profiles with former names.
    env.MSUF_GlobalDB = Copy(saved)
    env.MSUF_GlobalDB.char = {}
    env.MSUF_DB, env.MSUF_ActiveProfile = nil, nil
    env.MSUF_InitProfiles()
    CheckCarried(env.MSUF_DB.bars, label .. " new character login")

    -- Profile switch onto a stored profile that still carries former names.
    env.MSUF_GlobalDB = Copy(saved)
    env.MSUF_DB, env.MSUF_ActiveProfile = nil, nil
    env.MSUF_InitProfiles()
    PlantFormer(env.MSUF_GlobalDB.profiles.Other)
    Check(env.MSUF_SwitchProfile("Other") == true, label .. ": the switch failed")
    Check(env.MSUF_DB == env.MSUF_GlobalDB.profiles.Other, label .. ": the switch did not bind the profile")
    CheckCarried(env.MSUF_DB.bars, label .. " switch")

    -- Imports: a full profile and the unit frame kind, planted with former names after the export.
    local exported
    env.MSUF_EncodeCompactTableMSUF3 = function(value) exported = value; return "MSUF3:captured" end
    env.MSUF_EncodeCompactTable = env.MSUF_EncodeCompactTableMSUF3
    local source
    local decodeCompact = env.MSUF_TryDecodeCompactString
    env.MSUF_TryDecodeCompactString = function(text)
        if text == "MSUF3:captured" then return Copy(source) end
        return decodeCompact(text)
    end
    local function Payload(snapshot) return snapshot.msuf6 and snapshot.msuf6.payload or snapshot.payload end
    local function Source(kind)
        Check(env.MSUF_ExportSelectionToString(kind), label .. ": the " .. kind .. " export failed")
        source = Copy(exported)
        Check(type(Payload(source).bars) == "table", label .. ": the " .. kind .. " export carries no bars")
        PlantFormer(Payload(source))
    end

    Source("all")
    Check(env.MSUF_ImportFromString("MSUF3:captured") == true, label .. ": the full import failed")
    CheckCarried(env.MSUF_DB.bars, label .. " full import")
    Source("unitframe")
    Check(env.MSUF_ImportFromString("MSUF3:captured") == true, label .. ": the unit frame import failed")
    CheckCarried(env.MSUF_DB.bars, label .. " unit frame import")
    Source("all")
    Check(env.MSUF_ImportIntoNewProfile("Imported", "MSUF3:captured") == true, label .. ": the new profile import failed")
    CheckCarried(env.MSUF_GlobalDB.profiles.Imported.bars, label .. " new profile import")
    Source("all")
    Check(env.MSUF_ImportExternal("MSUF3:captured", "External") == true, label .. ": the external import failed")
    CheckCarried(env.MSUF_GlobalDB.profiles.External.bars, label .. " external import")
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    PathProof(flavor)
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
