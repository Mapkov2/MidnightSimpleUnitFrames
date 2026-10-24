-- Preview cadence remains independent of V2 storage; internal markers stay explicit.
return function(root, flavor, C, H)
    local key = "_msufPreviewDragHintExperienced"
    local function Serial(value) return assert(loadstring("return " .. H.Literal(value)))() end
    local function World(saved)
        local w = C.NewWorld(root, flavor, "Marker-Realm")
        C.Login(w, Serial(saved or {}))
        return w
    end
    local w = World()
    local ns, env = w.core, w.env
    local factory = Serial(env.MSUF_DB)
    assert(factory.general[key] == false, "factory teaching cadence changed")
    assert(env.MSUF_CreateProfile("Marker Created"), "profile creation failed")
    assert(env.MSUF_GlobalDB.profiles["Marker Created"].general[key] == false, "created marker changed")
    assert(env.MSUF_ResetProfile("Marker Created"), "profile reset failed")
    assert(env.MSUF_GlobalDB.profiles["Marker Created"].general[key] == false, "reset marker changed")

    -- Neither direct menu fill nor either migration route may fill this marker early.
    local direct = { general = {} }
    ns.DefaultsSchema.FillMenuDefaults(direct)
    assert(direct.general[key] == nil, "menu fill materialized the marker early")
    for _, current in ipairs({ false, true }) do
        local profile = Serial(factory)
        profile.general[key] = nil
        profile._msufStateSchema = current and ns.ProfileMigrations.Schema or nil
        ns.ProfileMigrations.Apply(profile)
        assert(profile.general[key] == nil, "migration materialized the marker early")
        ns.ProfileNormalize.TranslateProfilesToCurrent({ Inactive = profile })
        assert(profile.general[key] == true, "all-profile normalizer did not reconstruct the marker")
    end

    -- Execute the actual menu reader and acknowledgement without creating visuals.
    local path = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua"
    local helpers = assert(loadfile(path))
    setfenv(helpers, env)("MidnightSimpleUnitFrames_Options", ns)
    local preview = ns.MSUF2.PreviewHelpers
    env.MSUF_DB.general[key] = false
    local first, second = {}, {}
    assert(preview.ShouldShowPreviewHandleTooltip(first), "new-profile first hint missing")
    assert(not preview.ShouldShowPreviewHandleTooltip(first), "new-profile hint repeated on one owner")
    assert(preview.ShouldShowPreviewHandleTooltip(second), "new-profile per-owner hint missing")
    preview.NotePreviewElementMoved()
    assert(env.MSUF_DB.general[key] == true, "preview acknowledgement did not persist experience")
    preview._previewHandleTooltipSessionShown = nil
    assert(preview.ShouldShowPreviewHandleTooltip({}), "experienced first hint missing")
    assert(not preview.ShouldShowPreviewHandleTooltip({}), "experienced hint cadence changed")

    local pool = { profiles = {} }
    local values = { true, false, 0, "", {}, { false, 0, "" } }
    for i, value in ipairs(values) do
        pool.profiles[i] = { general = { [key] = Serial(value), unknown = { [0] = "zero", false, 0, "" } } }
    end
    pool.profiles.Absent = { general = {} }
    local before = Serial(pool)
    local ok, removed = ns.DefaultsSchema.Persist(pool)
    assert(ok and removed == 0, "short unstamped profiles entered V2 persistence")
    assert(H.Literal(pool) == H.Literal(before), "internal marker or partial profile changed")
    for i = 1, #values do
        assert(H.Literal(pool.profiles[i]) == H.Literal(before.profiles[i]), "explicit marker value changed")
    end
    assert(next(pool.profiles.Absent.general) == nil, "absence materialized during persistence")
    assert(pool.profiles[1].general.unknown[0] == "zero", "unknown marker sibling changed")

    -- Reject the new field's secrets and owner traps before pruning any profile.
    local secret, readSecret = {}, ns.Util.IsSecret
    ns.Util.IsSecret = function(value) return value == secret end
    local invalid = { profiles = { A = { general = { [key] = true } }, B = { general = { [key] = secret } } } }
    local valid, count = ns.DefaultsSchema.Persist(invalid)
    assert(valid and count == 0, "secret marker entered sparse persistence")
    assert(invalid.profiles.A.general[key] == true, "secret marker partly pruned the pool")
    ns.Util.IsSecret = readSecret
    for _, profileTrap in ipairs({ false, true }) do
        local trap = setmetatable({}, { __index = function() error("owner metatable read") end })
        invalid.profiles.B = profileTrap and trap or { general = trap }
        local valid, count = ns.DefaultsSchema.Persist(invalid)
        assert(valid and count == 0, "owner metatable entered sparse persistence")
        assert(invalid.profiles.A.general[key] == true, "owner rejection partly pruned the pool")
    end

    -- Internal underscore paths are deliberately outside the variant format.
    local original = H.Literal(env.MSUF_DB)
    local accepted, why = ns.ProfileVariants.Replace(env.MSUF_DB, { version = 1, entries = {
        { name = "Rejected", patch = { { path = { "general", key }, value = false } } },
    } })
    assert(not accepted and why == "invalid setting path", "internal marker became a variant setting")
    assert(H.Literal(env.MSUF_DB) == original, "rejected marker variant changed the profile")

    -- Actual terminal ordering with a supported menu variant and independent marker bases.
    for _, case in ipairs({ { false, true }, { true, false }, { "absent", true } }) do
        local runtime = World()
        local profile = runtime.env.MSUF_DB
        profile.general[key] = case[1] ~= "absent" and case[1] or nil
        if case[1] == false then profile.general[key] = false end
        profile.general.showGameMenuButton = not case[2]
        assert(runtime.core.ProfileVariants.Replace(profile, { version = 1, entries = {
            { name = "Menu", patch = { { path = { "general", "showGameMenuButton" }, value = case[2] } } },
        } }))
        assert(profile.general.showGameMenuButton == case[2], "supported variant overlay did not materialize")
        local expected = runtime.core.ProfileVariants.BaseSnapshot(profile)
        local full = Serial(runtime.env.MSUF_GlobalDB)
        full.profiles[runtime.env.MSUF_ActiveProfile] = expected
        runtime:FireEvent("PLAYER_LOGOUT")
        assert(rawget(runtime.env, "MSUF_DB") == nil, "terminal alias survived")
        assert(profile.general[key] == expected.general[key], "variant restoration changed the internal marker")
        local a = World({ MSUF_GlobalDB = full })
        local b = World({ MSUF_GlobalDB = Serial(runtime.env.MSUF_GlobalDB) })
        assert(H.Literal(a.env.MSUF_GlobalDB) == H.Literal(b.env.MSUF_GlobalDB), "variant reload changed the full pool")
        assert(b.env.MSUF_DB == b.env.MSUF_GlobalDB.profiles[b.env.MSUF_ActiveProfile], "variant reload identity changed")
    end

    print("profile_sparse_preview_marker: " .. flavor .. " functional factory/migration/cadence/variant/secret/reload ok")
    -- Keep the original performance contract, after the parent smoke's functional checks.
    return function()
    local measured = { profiles = { Default = { general = {} } } }
    local general = measured.profiles.Default.general
    for _ = 1, 100 do general[key] = true; ns.DefaultsSchema.Persist(measured) end
    local minimum = math.huge
    for _ = 1, 2 do
        collectgarbage("collect"); collectgarbage("stop")
        local start = collectgarbage("count")
        for _ = 1, 100 do general[key] = true; ns.DefaultsSchema.Persist(measured) end
        local bytes = (collectgarbage("count") - start) * 1024
        collectgarbage("restart")
        minimum = math.min(minimum, bytes)
    end
    assert(minimum == 0, "new marker persistence allocates " .. minimum .. " bytes")
    print("profile_sparse_preview_marker: " .. flavor .. " warm allocation 0")
    end
end
