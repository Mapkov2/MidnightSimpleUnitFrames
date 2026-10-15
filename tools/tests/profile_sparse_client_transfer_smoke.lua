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
control.core.DefaultsSchema.Persist = function() return false end
original:FireEvent("PLAYER_LOGOUT")
control:FireEvent("PLAYER_LOGOUT")
local full, compact = Saved(control, source), Saved(original, source)
assert(full.MSUF_DB == nil and compact.MSUF_DB == nil, "terminal alias remained")
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
