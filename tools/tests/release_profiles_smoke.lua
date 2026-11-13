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
    local w = C.NewWorld(root, flavor, character or "Tester-Realm", function(world)
        -- A solo client's native roster count is a number. H1 correctly keeps
        -- applying after an isolated frame failure, so the scale timer now
        -- reaches this provider too; the generic unknown-global stub is invalid.
        world.env.GetNumSubgroupMembers = function() return 0 end
    end)
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

do
    local api, active = P, original
    local W = ns.ProfileWorkbench
    assert(W.Checkpoint("Unrelated version"))
    assert(api.MSUF_CreateProfile("Raid setup"))
    assert(api.MSUF_SwitchProfile("Raid setup"))
    local ok, id = W.Checkpoint("Before raid")
    assert(ok and W.Points()[1].id == id)
    -- Released builds deleted the profile table and kept its Workbench row.
    local disk = Serial(env.MSUF_GlobalDB)
    disk.profiles["Raid setup"] = nil
    disk.char["Tester-Realm"].activeProfile = active
    local upgraded, _, upgradedNS = World({ MSUF_GlobalDB = disk })
    local upgradedAPI, upgradedW = upgraded.core.PublicGlobals, upgradedNS.ProfileWorkbench
    assert(upgradedW.Points()[1].label == "Unrelated version", "upgrade lost a valid owner's restore point")
    assert(upgradedAPI.MSUF_CreateProfile("Raid setup") and upgradedAPI.MSUF_SwitchProfile("Raid setup"))
    assert(#upgradedW.Points() == 0 and not upgradedW.Restore(id), "fresh profile inherited a deleted legacy profile's settings")
    local lifecycle = ns.SuiteLink.NotifyProfileLifecycle
    ns.SuiteLink.NotifyProfileLifecycle = function() return false, "profile-exists" end
    assert(not api.MSUF_RenameProfile("Raid setup", "Refused rename"))
    ns.SuiteLink.NotifyProfileLifecycle = lifecycle
    assert(W.Points()[1].id == id, "refused rename moved the owner's restore points")
    local staleDestination = Serial(W.Points()[1])
    staleDestination.profile, staleDestination.id = "Progress", id + 5000
    table.insert(env.MSUF_GlobalDB.global.profileWorkbench.points, staleDestination)
    assert(api.MSUF_RenameProfile("Raid setup", "Progress"))
    assert(#W.Points() == 1 and W.Points()[1].id == id and W.Restore(id), "rename lost or mixed the profile's restore points")
    assert(api.MSUF_CreateProfile("Raid setup") and api.MSUF_SwitchProfile("Raid setup"))
    assert(#W.Points() == 0 and not W.Restore(id), "fresh profile inherited another profile's restore point")
    assert(api.MSUF_SwitchProfile("Progress"))
    local after = assert(W.Snapshot())
    after.core.player.width = after.core.player.width + 17
    local draft = assert(W.ReviewSnapshot(after, "Before replacement"))
    local sameSettings = C.Copy(env.MSUF_DB)
    assert(api.MSUF_DeleteProfile("Progress") and api.MSUF_CreateProfile("Progress") and api.MSUF_SwitchProfile("Progress"))
    for key in pairs(env.MSUF_DB) do env.MSUF_DB[key] = nil end
    for key, value in pairs(sameSettings) do env.MSUF_DB[key] = value end
    assert(not W.CommitReview(draft), "review applied to a replacement profile with identical settings")
    assert(#W.Points() == 0 and not W.Restore(id), "reusing a deleted profile name adopted its restore points")
    assert(api.MSUF_SwitchProfile(active) and W.Points()[1].label == "Unrelated version", "another profile's points changed")
    local saved = env.MSUF_GlobalDB.global.profileWorkbench
    local template = Serial(W.Points()[1])
    local function AddOrphan(name)
        local point = Serial(template)
        saved.serial = saved.serial + 1
        point.id, point.profile = saved.serial, name
        table.insert(saved.points, point)
        return point.id
    end
    local function HasPoint(name)
        for _, point in ipairs(saved.points) do if point.profile == name then return true end end
        return false
    end
    -- Observe at publication: lazy cleanup on opening Workbench is too late.
    ns.SuiteLink.NotifyProfileLifecycle = function(kind, source, destination)
        if kind == "create" or kind == "copy" then
            assert(not HasPoint(destination or source), "new profile became visible with stale restore points")
        end
        return true
    end
    AddOrphan("Fresh create")
    assert(api.MSUF_CreateProfile("Fresh create"))
    AddOrphan("Fresh copy")
    assert(api.MSUF_CopyProfile(active, "Fresh copy"))
    ns.SuiteLink.NotifyProfileLifecycle = lifecycle
    assert(api.MSUF_SwitchProfile("Fresh copy") and #W.Points() == 0, "copy adopted another owner's points")
    local resetOK, resetID = W.Checkpoint("Before reset")
    assert(resetOK and api.MSUF_ResetProfile("Fresh copy"))
    assert(W.Points()[2].id == resetID, "reset lost the existing owner's restore point")
    assert(not api.MSUF_CreateProfile("Fresh copy") and W.Points()[2].id == resetID,
        "refused create cleared the existing owner's restore point")
    assert(api.MSUF_SwitchProfile(active))
    local orphanID = AddOrphan("Removed profile")
    assert(not W.Restore(orphanID) and not HasPoint("Removed profile"), "legacy orphan survived storage validation")
    local empty = Serial(env.MSUF_GlobalDB)
    empty.profiles, empty.char = {}, {}
    template.profile = "Default"
    empty.global.profileWorkbench.points = { template }
    local _, _, rebuiltNS = World({ MSUF_GlobalDB = empty })
    assert(#rebuiltNS.ProfileWorkbench.Points() == 0, "startup Default adopted a deleted owner's restore point")
end

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
