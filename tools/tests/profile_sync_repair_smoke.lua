-- Profile sync fails open (review F2). Saved sync groups that no longer
-- validate are repaired instead of blocking every flush: invalid groups,
-- members, modules and exclusions are dropped, a profile that no longer exists
-- leaves its groups, a module two groups claim for one profile stays with the
-- first group, and the editor can always replace the groups. Archiving a
-- pre-6.0 profile at login removes it from the groups as well.
-- Usage: lua tools/tests/profile_sync_repair_smoke.lua <repoRoot>
local root = assert(arg[1], "repo root required")
local prints = {}
print = function(...) local parts = {} for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end prints[#prints + 1] = table.concat(parts, " ") end
local function Printed(text)
    for _, line in ipairs(prints) do if line:find(text, 1, true) then return true end end
    return false
end
local NS = {}
function InCombatLockdown() return false end
function CreateFrame() return { SetScript = function() end, RegisterEvent = function() end, UnregisterAllEvents = function() end } end
for _, name in ipairs({ "ProfileFields", "ProfileVariants", "ProfileSync" }) do
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_" .. name .. ".lua"))("MSUF", NS)
end
local S = NS.ProfileSync

-- (1) The review's dead lock: a stale member plus a rename put one profile
-- into two groups for the same module.
MSUF_GlobalDB = { profiles = { A = { player = { width = 1 } }, C = { player = { width = 3 } }, Z = { player = { width = 9 } } }, global = {} }
MSUF_ActiveProfile, MSUF_DB = "A", MSUF_GlobalDB.profiles.A
assert(S.Replace({
    { name = "G1", members = { A = true }, modules = { unitframes = true } },
    { name = "G2", members = { C = true, Z = true }, modules = { unitframes = true } },
}))
MSUF_GlobalDB.profiles.Z = nil
S.RenameOrDelete("A", "Z")
MSUF_GlobalDB.profiles.Z, MSUF_GlobalDB.profiles.A = MSUF_GlobalDB.profiles.A, nil
MSUF_ActiveProfile = "Z"
assert(S.Flush(), "a repairable saved group blocked the flush")
local groups = S.GetGroups()
assert(groups[1].members.Z and not groups[2].members.Z, "the first group keeps the doubly claimed profile")
assert(groups[2].members.C, "the repair dropped a valid member")
assert(Printed("invalid entries"), "the repair was not reported")
local reports = #prints
assert(S.Flush() and #prints == reports, "the repair was reported more than once")
assert(S.Replace({}), "an empty group list could not replace the saved groups")
assert(S.Replace({ { name = "G1", members = { Z = true }, modules = { unitframes = true } } }), "valid groups were refused")

-- (2) Garbage in every field: only the valid parts survive and still sync.
MSUF_GlobalDB.profiles.B = { player = { width = 5 } }
MSUF_GlobalDB.global.profileSyncGroups = {
    { name = "Keep", members = { Z = true, B = true, Gone = true, [7] = true, Bad = "yes" },
      modules = { unitframes = true, nonsense = true, ["suite:extra"] = true },
      exclude = { { "player", "height" }, { "nonsense" }, "x" } },
    "not a group",
    { name = "", members = {}, modules = {} },
    { name = "Keep", members = { B = true }, modules = { colors = true } },
    { name = "NoModules", members = { B = true } },
    extra = true,
}
MSUF_DB = MSUF_GlobalDB.profiles.Z
S.Activate(true)
MSUF_DB.player.width = 444
assert(S.Flush(), "garbage in saved groups blocked the flush")
assert(MSUF_GlobalDB.profiles.B.player.width == 444, "the valid part of a repaired group stopped syncing")
groups = S.GetGroups()
assert(#groups == 1 and groups[1].name == "Keep", "invalid groups survived the repair")
local keep = groups[1]
assert(keep.members.Z and keep.members.B and not keep.members.Gone and not keep.members.Bad, "member repair is wrong")
assert(keep.modules.unitframes and keep.modules["suite:extra"] and not keep.modules.nonsense, "module repair is wrong")
assert(#keep.exclude == 1 and keep.exclude[1][2] == "height", "exclusion repair is wrong")
assert(S.Validate(groups), "the repaired groups do not validate")

-- (2b) A flush that cannot run is reported in the menu language, reason
-- included (review F28: the reason used to be printed in English).
NS.Translate = function(text) return "<" .. text .. ">" end
MSUF_DB.player.width = 0 / 0
prints = {}
assert(S.Replace({ { name = "Keep", members = { Z = true, B = true }, modules = { unitframes = true } } }),
    "a failed flush locked the sync editor")
assert(Printed("<Profile sync skipped (<profile contains an invalid number>).>"), "the skipped flush was not reported translated")
NS.Translate, MSUF_DB.player.width = nil, 444

-- (3) Login archiving removes the archived profile from every sync group.
MSUF_GlobalDB = {
    profiles = {
        Default = { _msufProfileSchema = 600, general = {} },
        Legacy = { general = { fontKey = "X" } },
    },
    char = {},
    global = { profileSyncGroups = { { name = "G", members = { Default = true, Legacy = true }, modules = { colors = true } } } },
}
MSUF_DB = MSUF_GlobalDB.profiles.Default
time = os.time
local ns = { ExportPublic = function(n, v) _G[n] = v end, GetAddonVersion = function() return "6.5" end, Client = {} }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_FirstLoad.lua"))("MidnightSimpleUnitFrames", ns)
assert(MSUF_GlobalDB.profiles.Legacy == nil, "the pre-6.0 profile was not archived")
local members = MSUF_GlobalDB.global.profileSyncGroups[1].members
assert(members.Default and not members.Legacy, "an archived profile stayed a sync member")
io.write("profile_sync_repair_smoke: OK\n")
