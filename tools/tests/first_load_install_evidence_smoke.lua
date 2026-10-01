-- first_load_install_evidence_smoke.lua <repoRoot>
--
-- State/MSUF_FirstLoad.lua classifies the install from the raw SavedVariables
-- before anything normalizes them. Character profile bindings live in
-- MSUF_GlobalDB.char (State/MSUF_Profiles.lua); the evidence read
-- MSUF_GlobalDB.chars, a key nothing writes, so an install that only kept its
-- bindings never reported "saved_profile_bindings" (quality finding C4.7).
-- Plain Lua 5.1, repo root as arg 1.
local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

local function Classify(globalDB, profileDB)
    MSUF_GlobalDB, MSUF_DB = globalDB, profileDB
    local namespace = { Client = { IsClassic = true }, Compat = {}, Public = {} }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_FirstLoad.lua"))("MidnightSimpleUnitFrames", namespace)
    return MSUF_GlobalDB.global.firstLoad6
end

local state = Classify({ char = { ["Tester - Realm"] = { activeProfile = "Main" } } }, nil)
assert(state.installKind == "upgrade", "saved bindings were not read as an upgrade")
assert(state.installReason == "saved_profile_bindings",
    "an install with only profile bindings reported " .. tostring(state.installReason))

state = Classify({ chars = { ["Tester - Realm"] = { activeProfile = "Main" } } }, nil)
assert(state.installReason == "saved_variables_present", "the retired chars key still counts as bindings")

state = Classify(nil, nil)
assert(state.installKind == "fresh" and state.installReason == "no_saved_variables", "a clean install was misread")

state = Classify({ profiles = { Main = { _msufProfileSchema = 600, general = {} } } }, nil)
assert(state.installReason == "saved_profiles_schema", "saved profiles were misread: " .. tostring(state.installReason))
print("first_load_install_evidence_smoke: OK")
