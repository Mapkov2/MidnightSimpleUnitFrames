-- Old SavedVariables use the existing real-graph corpus/login/codec harness.
local root, flavor = assert(arg[1]), assert(arg[2])
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function Serial(value) return assert(loadstring("return " .. H.Literal(value)))() end
local function Same(a, b, context) assert(H.Literal(a) == H.Literal(b), context) end
local function Clean(w)
    local unexpected = C.UnexpectedErrors({ world = w, flavor = flavor }, {})
    assert(#unexpected == 0, "unexpected profile error:\n" .. table.concat(unexpected, "\n"))
end
local function World(saved, character)
    local w = C.NewWorld(root, flavor, character or "Tester-Realm")
    C.Login(w, saved or {})
    Clean(w)
    return w, w.env, w.core
end
local entries, profiles = 0, 0
-- Mainline covers the complete Mainline/Forever corpus; Vanilla the Classic
-- corpus. The fast check already tests sparse transfer on all five clients.
if flavor == "Mainline" or flavor == "Vanilla" then
    for _, entry in ipairs(C.EntriesFor(root, flavor)) do
        if entry.kind == "sv" then
            local saved = C.LoadSavedVariablesFixture(root, entry.file)
            local w, env, ns = World(saved, entry.login)
            local full = Serial(env.MSUF_GlobalDB)
            local sparse = Serial(full)
            assert(ns.DefaultsSchema.Persist(sparse), entry.id .. ": sparse save refused")
            local restored = Serial(sparse)
            for name, profile in pairs(restored.profiles) do
                -- Conservative ineligible profiles remain full; that is also a
                -- valid save. Every restored or retained field must match.
                ns.DefaultsSchema.RestorePersistence(profile)
                Same(profile, full.profiles[name], entry.id .. "/" .. name .. ": sparse roundtrip changed fields")
                profiles = profiles + 1
            end
            local _, reloaded = World({ MSUF_GlobalDB = Serial(sparse) }, entry.login)
            local _, control = World({ MSUF_GlobalDB = Serial(full) }, entry.login)
            Same(reloaded.MSUF_GlobalDB.profiles, control.MSUF_GlobalDB.profiles, entry.id .. ": migrated reload changed profiles")
            assert(reloaded.MSUF_DB == reloaded.MSUF_GlobalDB.profiles[reloaded.MSUF_ActiveProfile], "reload lost active identity")
            entries = entries + 1
        end
    end
    assert(entries > 0 and profiles > 0, "old-profile corpus was empty")
end
local w, env, ns = World()
local P = ns.PublicGlobals
local original = env.MSUF_ActiveProfile
assert(P.MSUF_CreateProfile("Release A"), "create refused")
assert(P.MSUF_SwitchProfile("Release A"), "switch refused")
env.MSUF_DB.player.width = 317
assert(P.MSUF_CopyProfile("Release A", "Release B"), "copy refused")
assert(P.MSUF_SwitchProfile("Release B") and env.MSUF_DB.player.width == 317, "copy lost width")
assert(env.MSUF_DB == env.MSUF_GlobalDB.profiles["Release B"], "switch lost active identity")
assert(P.MSUF_ResetProfile("Release B"), "reset refused")
local reset = Serial(env.MSUF_DB)
assert(reset.player.width ~= 317, "reset retained custom width")
assert(P.MSUF_SwitchProfile("Release A") and env.MSUF_DB.player.width == 317, "switch lost stored state")
assert(P.MSUF_DeleteProfile("Release B") and not env.MSUF_GlobalDB.profiles["Release B"], "delete retained profile")
assert(P.MSUF_SwitchProfile(original), "return to original refused")

-- Drive the real native event listener, including the combat deferral.
local active = 1
if flavor == "Vanilla" or flavor == "TBC" then
    assert(P.MSUF_GetPlayerSpecID() == nil, "client without specs reported a specialization")
    P.MSUF_SetSpecProfile(71, "Release A")
    P.MSUF_SetSpecAutoSwitchEnabled(true)
    local listener = assert(P.MSUF_SpecProfileEventFrame)
    listener:GetScript("OnEvent")(listener, "PLAYER_SPECIALIZATION_CHANGED", "player")
    assert(env.MSUF_ActiveProfile == original, "client without specs auto-switched")
    Clean(w)
    print(string.format("profiles: %s, %d corpus entries / %d sparse roundtrips; CRUD and no-spec event passed", flavor, entries, profiles))
    return
end
if flavor == "Forever" then
    env.C_SpecializationInfo = { GetActiveSpecGroup = function() return active end }
else
    ns.Specialization.GetSpecialization = function() return active end
    ns.Specialization.GetSpecializationInfo = function(index) return index == 1 and 71 or 72 end
end
local first, second = flavor == "Forever" and 1 or 71, flavor == "Forever" and 2 or 72
P.MSUF_SetSpecProfile(first, original)
P.MSUF_SetSpecProfile(second, "Release A")
P.MSUF_SetSpecAutoSwitchEnabled(true)
local listener = assert(P.MSUF_SpecProfileEventFrame):GetScript("OnEvent")
active = 2
w.widgets:SetCombat(true)
listener(P.MSUF_SpecProfileEventFrame, "ACTIVE_TALENT_GROUP_CHANGED")
assert(env.MSUF_ActiveProfile == original, "spec changed profile in combat")
w.widgets:SetCombat(false)
local deferred = assert(P.MSUF_SpecProfileDeferFrame, "spec event queued no deferred switch")
deferred:GetScript("OnEvent")(deferred, "PLAYER_REGEN_ENABLED")
assert(env.MSUF_ActiveProfile == "Release A" and env.MSUF_DB.player.width == 317, "spec event did not switch after combat")
active = 1
listener(P.MSUF_SpecProfileEventFrame, "PLAYER_SPECIALIZATION_CHANGED", "player")
assert(env.MSUF_ActiveProfile == original, "spec event did not return to original")
Clean(w)
print(string.format("profiles: %s, %d corpus entries / %d profile sparse roundtrips; CRUD and spec events passed", flavor, entries, profiles))
