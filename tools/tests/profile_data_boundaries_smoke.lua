-- Real State lifecycle regression: defaults, migration, activation and imports.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local mode = arg[3] or "all"
local Corpus = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local function World(saved)
    local world = Corpus.NewWorld(root, flavor, "Tester-Realm")
    Corpus.Login(world, saved or {})
    return world, world.env, world.core
end
local function Run(name, fn)
    if mode == "all" or mode == name then
        fn()
        print("profile_data_boundaries_smoke: " .. flavor .. " " .. name .. " ok")
    end
end
local function Literal(value)
    if type(value) == "table" then
        local parts = {}
        for _, key in ipairs(Corpus.SortedKeys(value)) do parts[#parts + 1] = "[" .. Literal(key) .. "]=" .. Literal(value[key]) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    if type(value) == "string" then return string.format("%q", value) end
    return tostring(value)
end
local function Legacy(env)
    local profile = Corpus.Copy(env.MSUF_DB)
    profile._msufStateSchema = nil
    for _, unit in ipairs({ "player", "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena" }) do
        for key in pairs(profile[unit]) do if key:match("^portraitDragon") then profile[unit][key] = nil end end
    end
    for key in pairs(profile.general) do if key:match("^gcdBar") then profile.general[key] = nil end end
    profile.general.kickReadyTimeMarker = nil
    for key in pairs(profile.arena) do if key:match("^trinket") then profile.arena[key] = nil end end
    for key in pairs(profile.pet) do
        if key:match("^petHappinessIndicator") or key == "showPetHappinessIndicator" then profile.pet[key] = nil end
    end
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do profile[key].auras.buff.trackedStrata = nil end
    return profile
end
Run("seed", function()
    local _, env, ns = World()
    local old = Legacy(env)
    local portraitBefore = {}
    ns.PortraitDetails.Compile(portraitBefore, old.player)
    local previous = env.MSUF_DB
    env.MSUF_DB = old
    local arenaBefore = { ns.ArenaTrinkets.Layout() }
    local arenaShownBefore = ns.ArenaTrinkets.Shown()
    env.MSUF_DB = previous
    env.MSUF_GlobalDB.profiles.Old = old
    assert(env.MSUF_SwitchProfile("Old"))
    assert(old.player.portraitDragonScale == 100, "rev-17 fast path skipped portrait defaults")
    assert(old.general.gcdBarWidth == 180 and old.general.kickReadyTimeMarker == false, "rev-17 castbar defaults missing")
    assert(old.arena.trinketSize == 20 and old.arena.trinketLayer == 10, "rev-17 arena defaults missing")
    assert(old.gf_party.auras.buff.trackedStrata == "AUTO", "stored trackedStrata missing")
    assert(old._msufStateSchema == 700 and old._msufProfileSchema == 600, "migration/wire schema stamps missing")
    local portraitAfter = {}
    ns.PortraitDetails.Compile(portraitAfter, old.player)
    assert(Literal(portraitBefore) == Literal(portraitAfter), "portrait runtime fallback changed after seeding")
    assert(Literal(arenaBefore) == Literal({ ns.ArenaTrinkets.Layout() }) and arenaShownBefore == ns.ArenaTrinkets.Shown(),
        "arena runtime fallback changed after seeding")
    if flavor == "Forever" or flavor == "Vanilla" or flavor == "TBC" then
        assert(old.pet.showPetHappinessIndicator == true and old.pet.petHappinessIndicatorOffsetX == -7, "pet defaults missing")
    else
        assert(old.pet.showPetHappinessIndicator == nil, "unsupported happiness was seeded")
    end
    local explicit = Legacy(env)
    explicit.player.portraitDragonScale, explicit.player.portraitDragonInInstances = 0, false
    explicit.general.gcdBarWidth, explicit.general.gcdBarCombatOnly = 0, false
    explicit.arena.trinketLayer, explicit.arena.showTrinket = 0, false
    explicit.pet.showPetHappinessIndicator, explicit.pet.petHappinessIndicatorOffsetX = false, 0
    explicit.gf_party.auras.buff.trackedStrata = "LOW"
    env.MSUF_GlobalDB.profiles.Explicit = explicit
    assert(env.MSUF_SwitchProfile("Explicit"))
    assert(explicit.player.portraitDragonScale == 0 and explicit.player.portraitDragonInInstances == false)
    assert(explicit.general.gcdBarWidth == 0 and explicit.general.gcdBarCombatOnly == false)
    assert(explicit.arena.trinketLayer == 0 and explicit.arena.showTrinket == false)
    assert(explicit.pet.showPetHappinessIndicator == false and explicit.pet.petHappinessIndicatorOffsetX == 0)
    assert(explicit.gf_party.auras.buff.trackedStrata == "LOW")
end)
Run("fresh", function()
    local _, env = World()
    assert(env.MSUF_DB.general._msufFactoryProfileApplied == true, "stamp prevented factory seeding")
    assert(env.MSUF_DB._msufStateSchema == 700, "fresh profile has no completed ledger")
    assert(env.MSUF_CreateProfile("Created"))
    assert(env.MSUF_GlobalDB.profiles.Created.general._msufFactoryProfileApplied == true)
    assert(env.MSUF_ResetProfile("Created"))
    assert(env.MSUF_GlobalDB.profiles.Created._msufStateSchema == 700)
    assert(env.MSUF_ResetProfile())
    assert(env.MSUF_DB.general._msufFactoryProfileApplied == true and env.MSUF_DB._msufStateSchema == 700)
end)
Run("aliases", function()
    local _, env = World()
    local old = Corpus.Copy(env.MSUF_DB)
    old._msufStateSchema, old._msufProfileNormalizationRevision = nil, nil
    old.targettarget = nil
    old.tot = { width = 333, height = 44, enabled = false }
    local _, loaded = World({ MSUF_GlobalDB = { profiles = { Default = old },
        char = { ["Tester-Realm"] = { activeProfile = "Default" } } } })
    assert(loaded.MSUF_DB.targettarget.width == 333 and loaded.MSUF_DB.targettarget.height == 44,
        "cold migration seeded canonical owner before preserving tot alias")
    assert(loaded.MSUF_DB.targettarget.enabled == false)
end)
Run("sparse", function()
    local _, env, ns = World()
    local sparse = { general = { fontKey = "FRIZQT" }, player = { width = 100, height = 30 }, target = { width = 100, height = 30 } }
    env.MSUF_NormalizeProfileDefaults(sparse, true)
    assert(sparse.gf_party.auras.buff.trackedStrata == "AUTO", "ledger stamped before group owners existed")
    local inherited = Legacy(env)
    inherited.gf_party.auras.buff.trackedFrameStrata = "HIGH"
    inherited.gf_raid.spellIndicators.strata = "DIALOG"
    env.MSUF_NormalizeProfileDefaults(inherited, false, true)
    assert(inherited.gf_party.auras.buff.trackedStrata == "HIGH", "trackedFrameStrata runtime fallback lost")
    assert(inherited.gf_raid.auras.buff.trackedStrata == "DIALOG", "spellIndicators strata runtime fallback lost")
    local malformed = Legacy(env)
    malformed.gf_party.spellIndicators = 4
    env.MSUF_NormalizeProfileDefaults(malformed, true)
    assert(malformed.gf_party.auras.buff.trackedStrata == "AUTO", "malformed spell indicator fallback was not repaired")
    local crossClient = Legacy(env)
    crossClient._msufStateSchema = 700
    ns.ProfileMigrations.Apply(crossClient)
    if ns.Client.SupportsPetHappiness then
        assert(crossClient.pet.showPetHappinessIndicator == true, "schema-700 cross-client profile skipped happiness")
    end
end)
Run("boundaries", function()
    local _, env, ns = World()
    local old = Legacy(env)
    old.general.barTexture, old.general.castbarTexture = "Midnight Smooth", "MSUF Flat"
    old.gf_party.tooltipMode, old.gf_party.tooltipModifier = "ALWAYS", "SHIFT"
    env.MSUF_GlobalDB.profiles.Old = old
    assert(env.MSUF_SwitchProfile("Old"))
    assert(old.general.barTexture == "MSUF Smooth" and old.general.castbarTexture == "Solid", "switch left old media names")
    assert(old.gf_party.tooltipMode == nil and old.gf_party.tooltipModifier == nil, "tooltip not stripped")
    old.gf_party.tooltipMode = "ONE_SHOT_SENTINEL"
    env.MSUF_EnsureDB(true)
    assert(old.gf_party.tooltipMode == "ONE_SHOT_SENTINEL", "tooltip stripping ran twice")
    local untouched = Legacy(env)
    untouched.gf_party.tooltipMode = "INACTIVE_SENTINEL"
    env.MSUF_GlobalDB.profiles.Untouched = untouched
    env.MSUF_EnsureDB(true)
    assert(untouched.gf_party.tooltipMode == "INACTIVE_SENTINEL", "EnsureDB walked inactive profiles")
    assert(env.MSUF_CopyProfile("Untouched", "Copy"))
    assert(env.MSUF_GlobalDB.profiles.Copy.gf_party.tooltipMode == nil, "copy did not migrate")
    -- Original late-LSM probe: activating an old profile before bundled registration.
    ns.LSM = { Register = function() end }
    env.MSUF_BUNDLED_FONTS_REGISTERED = false
    env.MSUF_UpdateAllBarTextures = function() end
    env.MSUF_ApplyCastbarVisualsForUnit = function() end
    local callbacks = {}
    env.C_Timer.After = function(_, callback) callbacks[#callbacks + 1] = callback end
    env.MSUF_RegisterBundledMediaWithLSM()
    for _, callback in ipairs(callbacks) do callback() end
    assert(old.general.barTexture == "MSUF Smooth" and old.general.castbarTexture == "Solid", "late LSM regressed")
end)
Run("import", function()
    local _, env = World()
    local normalize = env.MSUF_NormalizeProfileDefaults
    local heavyIndex, heavy
    for index = 1, 60 do
        local name, value = debug.getupvalue(normalize, index)
        if not name then break end
        if name == "MSUF_EnsureDB_Heavy" then
            heavyIndex, heavy = index, value
            break
        end
    end
    assert(heavyIndex, "heavy pass not observable")
    local calls = 0
    debug.setupvalue(normalize, heavyIndex, function(profile)
        if profile.general and profile.general.boundaryProbe == true then calls = calls + 1 end
        return heavy(profile)
    end)
    local payload = Legacy(env)
    payload.general.boundaryProbe = true
    payload.general.barTexture, payload.general.castbarTexture = "Midnight Smooth", "MSUF Flat"
    payload._msufStateSchema = 700 -- Untrusted metadata cannot skip repairs.
    local text = Literal({ addon = "MSUF", fmt = 2, schema = 600, kind = "all", payload = payload })
    for _, path in ipairs({ "active", "new", "externalActive", "externalStored" }) do
        calls = 0
        local ok, why
        if path == "active" then ok, why = env.MSUF_ImportFromString(text)
        elseif path == "new" then ok, why = env.MSUF_ImportIntoNewProfile("Imported", text)
        else ok, why = env.MSUF_ImportExternal(text, path == "externalActive" and env.MSUF_ActiveProfile or "Stored") end
        assert(ok, path .. " import failed: " .. tostring(why))
        assert(calls == 1, path .. " normalized imported profile " .. calls .. " times")
        local target = path == "externalStored" and env.MSUF_GlobalDB.profiles.Stored or env.MSUF_DB
        assert(target.general.barTexture == "MSUF Smooth" and target.general.castbarTexture == "Solid", path .. " skipped media migration")
        assert(target.gf_party.auras.buff.trackedStrata == "AUTO", path .. " skipped trackedStrata")
    end
end)
Run("beta", function()
    local _, env = World()
    local text = Corpus.ReadImportFixture(root, "tools/fixtures/profiles/imports/hist_2026-08-06_msuf3_full_schema1.txt")
    local ok, why = env.MSUF_ImportIntoNewProfile("Beta", text)
    assert(ok, "valid beta profile refused: " .. tostring(why))
    assert(env.MSUF_DB._msufStateSchema == 700 and env.MSUF_DB._msufProfileSchema == 600)
    local before = Literal(env.MSUF_GlobalDB)
    for _, bad in ipairs({ {}, { general = {} }, { general = "bad", player = {} }, { player = { enabled = true } } }) do
        local malformed = Literal({ addon = "MSUF", fmt = 2, schema = 1, kind = "all", payload = {},
            msuf6 = { schema = 1, kind = "all", payload = bad } })
        assert(env.MSUF_ImportIntoNewProfile("Invalid", malformed) == false, "invalid beta data admitted")
        assert(Literal(env.MSUF_GlobalDB) == before, "invalid beta input mutated profile store")
    end
end)
