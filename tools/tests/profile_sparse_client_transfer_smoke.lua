-- Cross-client declared SavedVariables must match an unpruned control.
local root, source = assert(arg[1]), assert(arg[2])
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Serial(value) return assert(loadstring("return " .. H.Literal(value)))() end
local function Saved(world, flavor)
    local suffix = flavor == "Forever" and "Mainline" or flavor
    local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_" .. suffix .. ".toc", "rb"))
    local text = file:read("*a")
    file:close()
    local names = assert(text:match("## SavedVariables:%s*([^\r\n]+)"))
    local saved = {}
    for name in names:gmatch("[%w_]+") do saved[name] = rawget(world.env, name) end
    return Serial(saved)
end
local function Load(flavor, saved)
    local world = C.NewWorld(root, flavor, "Portable-Realm")
    C.Login(world, Serial(saved or {}))
    return world
end
local original, control = Load(source), Load(source)
-- Include inactive, trusted and explicit historical marker values in every transfer.
local marker = "_msufPreviewDragHintExperienced"
for _, world in ipairs({ original, control }) do
    local pool = world.env.MSUF_GlobalDB.profiles
    for i, value in ipairs({ true, false, 0, "", {}, { false, 0, "" } }) do
        local profile = C.Copy(world.env.MSUF_DB)
        profile.general[marker] = C.Copy(value)
        profile.general.markerTransferUnknown = { [0] = "zero", false, 0, "" }
        pool["Marker" .. i] = profile
    end
    pool.MarkerAbsent = C.Copy(world.env.MSUF_DB)
    pool.MarkerAbsent.general[marker] = nil
end
control.core.DefaultsSchema.Persist = function() return false end
original:FireEvent("PLAYER_LOGOUT")
control:FireEvent("PLAYER_LOGOUT")
local full, compact = Saved(control, source), Saved(original, source)
assert(compact.MSUF_GlobalDB._pre70SparseValidated == nil,
    "session safety preflight leaked into SavedVariables")
assert(full.MSUF_GlobalDB._pre70SparseValidated == nil, "disabled persistence unexpectedly recorded a sparse preflight")
-- The unpruned control suppresses Persist entirely; neither path persists
-- session approval metadata before comparing every saved value as before.
assert(full.MSUF_DB == nil and compact.MSUF_DB == nil, "terminal alias remained")
assert(full.MSUF_GlobalDB.profiles.Marker1.general[marker] == true, "marker control was pruned")
assert(compact.MSUF_GlobalDB.profiles.Marker1.general[marker] == true, "internal experience marker changed")
assert(type(compact.MSUF_GlobalDB.profiles.Marker1._msufSparseDefaultsV2) == "string", "V2 mask missing")
assert(compact.MSUF_GlobalDB.profiles.Marker1._msufDefaultsRevision == 17.5, "V2 revision missing")
assert(#H.Literal(compact) < #H.Literal(full), "declared SavedVariables did not shrink")
assert(compact.MSUF_GlobalDB.profiles.Marker2.general[marker] == false, "factory cadence was pruned")
for _, destination in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local a, b = Load(destination, full), Load(destination, compact)
    assert(H.Literal(a.env.MSUF_GlobalDB) == H.Literal(b.env.MSUF_GlobalDB),
        source .. " -> " .. destination .. ": destination opacity, stamps or other values changed")
    assert(b.env.MSUF_DB == b.env.MSUF_GlobalDB.profiles[b.env.MSUF_ActiveProfile], "destination identity changed")
    a:FireEvent("PLAYER_LOGOUT")
    b:FireEvent("PLAYER_LOGOUT")
    local returnedA, returnedB = Load(source, Saved(a, destination)), Load(source, Saved(b, destination))
    assert(H.Literal(returnedA.env.MSUF_GlobalDB) == H.Literal(returnedB.env.MSUF_GlobalDB),
        source .. " -> " .. destination .. ": declared-variable return changed")
    a, b, returnedA, returnedB = nil, nil, nil, nil
    collectgarbage("collect")
end
print("profile_sparse_client_transfer_smoke: " .. source .. " all5 destinations/returns ok")
