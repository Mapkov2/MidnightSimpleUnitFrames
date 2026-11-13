-- Real core graphs: staged import matches the synchronous API and does not
-- publish candidate data between frames. The frozen corpus pins old outcomes.
local root, flavor = assert(arg[1]):gsub("\\", "/"), assert(arg[2])
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local function World()
    local world = C.NewWorld(root, flavor, "Tester-Realm")
    C.Login(world, {})
    return world
end
local function Fixture(id)
    return C.ReadImportFixture(root, "tools/fixtures/profiles/imports/" .. id .. ".txt")
end
local sync, async = World(), World()
local begin = async.core.HostAPI.Profiles_BeginImport
assert(begin == async.env.MSUF_HostAPI.Profiles_BeginImport)
local api = sync.core.PublicGlobals

local function Prepare(job)
    local before = H.Literal(async.env.MSUF_GlobalDB)
    local db, active = async.env.MSUF_DB, async.env.MSUF_ActiveProfile
    while job.completed < job.total - 1 do
        local previous = job.completed
        local done, ok, reason, stage = job:Step()
        assert(async.env.MSUF_DB == db and async.env.MSUF_ActiveProfile == active, "preparation switched profile")
        assert(H.Literal(async.env.MSUF_GlobalDB) == before, "preparation modified stored data")
        if done then return done, ok, reason, stage end
        assert(job.completed == previous + 1, "step skipped or repeated a phase")
    end
end

local cases = {
    { "hist_2026-01-18_msuf2_preset", "Old MSUF2" },
    { "hist_2026-05-27_msuf3_portable", "Old MSUF3" },
    { "hist_2026-07-14_msuf3_raw_profile" },
    { "base_msuf4_unitselection" },
    { "synth_text_gameplay", "Old literal" },
    { "hist_2026-05-04_msuf3_corrupt", "Broken" },
}
for _, case in ipairs(cases) do
    local text, name = Fixture(case[1]), case[2]
    local job = assert(begin(text, name))
    assert(job.completed == 0 and job.phase == "decode")
    local done, ok, reason, stage = Prepare(job)
    if not done then
        assert(job.phase == "apply")
        done, ok, reason, stage = job:Step()
    end
    assert(done and job:Step() == true)
    local expected, expectedReason, expectedStage
    if name then expected, expectedReason, expectedStage = api.MSUF_ImportIntoNewProfile(name, text)
    else expected, expectedReason, expectedStage = api.MSUF_ImportFromString(text) end
    assert(ok == expected and reason == expectedReason and stage == expectedStage, case[1] .. ": return changed")
    assert(H.Literal(async.env.MSUF_GlobalDB) == H.Literal(sync.env.MSUF_GlobalDB),
        case[1] .. ": staged import persisted different settings")
    assert(async.env.MSUF_DB == async.env.MSUF_GlobalDB.profiles[async.env.MSUF_ActiveProfile])
end

-- Both public export/import paths share the session's layout opt-in.
do
    local source = World()
    local receiver = World()
    local send, receive = source.core.PublicGlobals, receiver.core.PublicGlobals
    local fixture = C.LoadSavedVariablesFixture(root, "tools/fixtures/profiles/sv/sv_retail_rev16_17.lua")
    local layout = assert(fixture.MSUF_GlobalDB.profiles.Profile01.general.blizzardEditModeSnapshot)
    assert(layout.bags and layout.bags.point)
    local sourceActive = source.env.MSUF_ActiveProfile
    source.env.MSUF_DB.general.blizzardEditModeSnapshot = C.Copy(layout)
    assert(send.MSUF_CopyProfile(sourceActive, "Stored layout"))
    local native = { arrangement = "local" }
    local applied = 0
    receive.MSUF_BlizzardEditMode_ApplyProfileSnapshot = function()
        applied = applied + 1
        native = receiver.env.MSUF_DB.general.blizzardEditModeSnapshot
    end
    receiver.env.MSUF_DB.general.blizzardEditModeSnapshot = C.Copy(layout)
    receiver.env.MSUF_DB.general.blizzardEditModeSnapshot.bags.x = 999
    local localLayout = C.Copy(receiver.env.MSUF_DB.general.blizzardEditModeSnapshot)
    assert(receive.MSUF_CopyProfile(receiver.env.MSUF_ActiveProfile, "Inactive"))

    for _, include in ipairs({ false, true }) do
        send.MSUF_Profiles_SetExportBlizzardEditMode(include)
        for _, name in ipairs({ sourceActive, "Stored layout" }) do
            local ok, text = send.MSUF_ExportExternal(name)
            assert(ok, text)
            local envelope = assert(send.MSUF_TryDecodeCompactString(text))
            for _, payload in ipairs({ envelope.payload, envelope.msuf6.payload }) do
                assert(source.core.ProfileFields.Equal(payload.general.blizzardEditModeSnapshot, include and layout or nil),
                    "external export did not honor the Blizzard layout opt-in for " .. name)
            end
        end
    end
    local text = assert(send.MSUF_ExportSelectionToString("all"))
    for _, include in ipairs({ false, true }) do
        receive.MSUF_Profiles_SetImportBlizzardEditMode(include)
        local active = receiver.env.MSUF_ActiveProfile
        for _, name in ipairs({ "Inactive", active, "New external" }) do
            local before = applied
            assert(receive.MSUF_ImportExternal(text, name))
            local stored = receiver.env.MSUF_GlobalDB.profiles[name].general.blizzardEditModeSnapshot
            local expected = include and layout or name ~= "New external" and localLayout or nil
            assert(receiver.core.ProfileFields.Equal(stored, expected), "external import ignored the layout preference")
            local wantApply = include and name == active and receiver.core.Client.SupportsBlizzardEditMode
            assert(applied == before + (wantApply and 1 or 0), "external import applied the wrong profile's layout")
            if not include then assert(native.arrangement == "local", "disabled import changed the active native layout") end
        end
    end

    -- A change to the checkbox invalidates either pending route.
    receiver.env.MSUF_DB.general.blizzardEditModeSnapshot = C.Copy(layout)
    receiver.env.MSUF_DB.general.blizzardEditModeSnapshot.bags.x = 999
    local workbench = receiver.core.ProfileWorkbench
    local pending = assert(receiver.core.HostAPI.Profiles_BeginImport(text))
    while pending.phase ~= "apply" do assert(not pending:Step()) end
    local review = assert(workbench.ReviewImport(text))
    local previousCalls = applied
    receive.MSUF_Profiles_SetImportBlizzardEditMode(false)
    assert(select(4, pending:Step()) == "stale", "staged import accepted a changed layout preference")
    assert(workbench.CommitReview(review) == false, "review accepted a changed layout preference")
    assert(receiver.env.MSUF_DB.general.blizzardEditModeSnapshot.bags.x == 999 and applied == previousCalls)

    assert(receive.MSUF_ImportFromString(text))
    assert(receiver.env.MSUF_DB.general.blizzardEditModeSnapshot.bags.x == 999 and applied == previousCalls)
    local kept = assert(receiver.core.HostAPI.Profiles_BeginImport(text))
    while kept.phase ~= "apply" do assert(not kept:Step()) end
    receiver.env.MSUF_DB.general.blizzardEditModeSnapshot.bags.x = 1000
    assert(select(2, kept:Step()))
    assert(receiver.env.MSUF_DB.general.blizzardEditModeSnapshot.bags.x == 1000 and applied == previousCalls)
    assert(workbench.CommitReview(assert(workbench.ReviewImport(text))))
    assert(receiver.env.MSUF_DB.general.blizzardEditModeSnapshot.bags.x == 1000 and applied == previousCalls)
    receiver.env.MSUF_DB.general.blizzardEditModeSnapshot.bags.x = 999

    local partial = Fixture("base_msuf4_castbar")
    for _, include in ipairs({ false, true }) do
        receive.MSUF_Profiles_SetImportBlizzardEditMode(include)
        assert(receive.MSUF_ImportFromString(partial))
        assert(workbench.CommitReview(assert(workbench.ReviewImport(partial))))
        assert(applied == previousCalls, "a castbar-only import reapplied the local Blizzard layout")
        assert(receiver.env.MSUF_DB.general.blizzardEditModeSnapshot.bags.x == 999, "partial import replaced the stored layout")
    end
    review = assert(workbench.ReviewImport(text))
    for _, row in ipairs(review.changes) do
        if row.path[1] == "general" and row.path[2] == "blizzardEditModeSnapshot" then row.selected = false end
    end
    assert(workbench.CommitReview(review))
    assert(applied == previousCalls, "an unselected layout was applied")
    assert(workbench.CommitReview(assert(workbench.ReviewImport(text))))
    assert(applied == previousCalls + (receiver.core.Client.SupportsBlizzardEditMode and 1 or 0),
        "a selected changed layout was not applied")

    receiver.env.MSUF_DB.general.blizzardEditModeSnapshot.bags.x = 999
    previousCalls = applied
    local restores = 0
    workbench.RegisterProvider("layoutFailure", {
        Capture = function() return {} end,
        Restore = function() restores = restores + 1 return restores ~= 1 end,
    })
    assert(not workbench.CommitReview(assert(workbench.ReviewImport(text))))
    assert(restores == 2 and applied == previousCalls, "provider refusal reapplied a layout the transaction never changed")
    if receiver.core.Client.SupportsBlizzardEditMode then
        -- A failure after the native write must still put the previous layout back.
        receive.MSUF_BlizzardEditMode_ApplyProfileSnapshot = function()
            applied = applied + 1
            native = C.Copy(receiver.env.MSUF_DB.general.blizzardEditModeSnapshot)
            if applied == previousCalls + 1 then error("simulated failure after applying layout") end
        end
        assert(not workbench.CommitReview(assert(workbench.ReviewImport(text))))
        assert(applied == previousCalls + 2 and native.bags.x == 999
            and receiver.env.MSUF_DB.general.blizzardEditModeSnapshot.bags.x == 999, "failed native apply did not roll back")
    end
end

local subset = Fixture("base_msuf4_unitselection")
local live = assert(begin(Fixture("base_msuf4_castbar")))
assert(not Prepare(live))
async.env.MSUF_DB.focus.width = 173
assert(select(2, live:Step()) == true)
assert(async.env.MSUF_DB.focus.width == 173, "partial import restored a stale copy of an unrelated frame")

local pending = assert(begin(subset, "Concurrent name"))
assert(not Prepare(pending))
assert(async.core.PublicGlobals.MSUF_CreateProfile("Concurrent name"))
local afterCreate = H.Literal(async.env.MSUF_GlobalDB)
local done, ok, _, stage = pending:Step()
assert(done and ok == false and stage == "exists", "did not recheck target at commit")
assert(H.Literal(async.env.MSUF_GlobalDB) == afterCreate)

pending = assert(begin(subset))
assert(not Prepare(pending))
assert(async.core.PublicGlobals.MSUF_SwitchProfile("Concurrent name"))
local switched = H.Literal(async.env.MSUF_GlobalDB)
done, ok = pending:Step()
assert(done and ok == false, "did not reject changed profile identity")
assert(H.Literal(async.env.MSUF_GlobalDB) == switched)

pending = assert(begin(subset))
assert(not Prepare(pending))
local sameProfile = async.env.MSUF_DB
assert(async.core.PublicGlobals.MSUF_ImportFromString(subset))
assert(async.env.MSUF_DB == sameProfile)
done, ok = pending:Step()
assert(done and ok == false, "same-table synchronous import did not invalidate pending work")

pending = assert(begin(subset))
assert(not Prepare(pending))
async.core.PublicGlobals.MSUF_Profiles_SetImportVariants(false)
local optionBefore = H.Literal(async.env.MSUF_GlobalDB)
done, ok = pending:Step()
assert(done and ok == false, "did not reject changed import options")
assert(H.Literal(async.env.MSUF_GlobalDB) == optionBefore)
async.core.PublicGlobals.MSUF_Profiles_SetImportVariants(true)

pending = assert(begin(subset, "Refused checkpoint"))
assert(not Prepare(pending))
local workbench = async.core.ProfileWorkbench
local checkpoint, currentDB = workbench.Checkpoint, async.env.MSUF_DB
workbench.Checkpoint = function()
    assert(pending:Step() == false, "job could re-enter its own commit")
    return false, "checkpoint refused"
end
local refusal
done, ok, refusal = pending:Step()
workbench.Checkpoint = checkpoint
assert(done and ok == false and refusal == "checkpoint refused")
assert(async.env.MSUF_DB == currentDB and not async.env.MSUF_GlobalDB.profiles["Refused checkpoint"],
    "failed checkpoint left the factory profile active or persisted")

pending = assert(begin(subset, "Combat blocked"))
assert(not Prepare(pending))
-- Signal the combat edge without running unrelated protected roster handlers.
assert(async.core.Util.InCombat("PLAYER_REGEN_DISABLED"))
local reason
done, ok, reason = pending:Step()
assert(done and ok == false and reason == "combat", "did not recheck combat before commit")
assert(not async.env.MSUF_GlobalDB.profiles["Combat blocked"])
print("profile_import_job_smoke: " .. flavor .. " historical formats, staged parity, combat and stale targets passed")
