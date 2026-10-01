-- Variants and sync cover every profile root (review F8): the WoW Forever
-- swing timers (MSUF_DB.swingTimers) and the root value "Shorten unit names"
-- (MSUF_DB.shortenNames) were missing, so saving a recording silently lost
-- those edits and sync never carried them.
-- Usage: lua tools/tests/profile_fields_roots_smoke.lua <repoRoot>
local root = assert(arg[1], "repo root required")
local NS = {}
function InCombatLockdown() return false end
function CreateFrame() return { SetScript = function() end, RegisterEvent = function() end, UnregisterAllEvents = function() end } end
function IsInInstance() return false, "none" end
function IsInGroup() return false end
function MSUF_GetPlayerSpecID() return 63 end
for _, name in ipairs({ "ProfileFields", "ProfileVariants", "ProfileSync", "ProfileVariantEditor" }) do
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_" .. name .. ".lua"))("MSUF", NS)
end
local V, S = NS.ProfileVariants, NS.ProfileSync
NS.ProfileRuntime = { Apply = function() if not V.IsRecording() then V.Resolve(MSUF_DB, { location = "solo", spec = 63, dark = false }) end end }

-- Recording keeps both kinds of edits.
local function Profile(width, shorten)
    return { general = {}, shortenNames = shorten, swingTimers = { main = { width = width } }, player = { width = 150 } }
end
local a, b = Profile(200, false), Profile(200, false)
a.profileVariants = { version = 1, entries = { { name = "Raid", conditions = { context = "raid" }, patch = {} } } }
MSUF_GlobalDB = { profiles = { A = a, B = b }, global = {} }
MSUF_ActiveProfile, MSUF_DB = "A", a
assert(V.BeginRecording("Raid"))
a.shortenNames = true
a.swingTimers.main.width = 240
assert(V.SaveRecording())
local entry = V.Find(a, "Raid")
local seen = {}
for _, field in ipairs(entry.patch) do seen[table.concat(field.path, ".")] = field.value end
assert(seen.shortenNames == true, "a recording lost the Shorten unit names edit")
assert(seen["swingTimers.main.width"] == 240, "a recording lost the swing timer edit")
assert(a.shortenNames == false and a.swingTimers.main.width == 200, "saving the recording changed the base")
-- The overlay applies and restores a root value.
V.Resolve(a, { location = "raid", spec = 63, dark = false })
assert(a.shortenNames == true and a.swingTimers.main.width == 240, "the overlay did not apply both fields")
V.Restore()
assert(a.shortenNames == false and a.swingTimers.main.width == 200, "restore did not bring the base back")

-- Sync carries both, swing timers with the gameplay module. (Fields a
-- variant owns never sync, so these two profiles carry no variants.)
local c, d = Profile(200, false), Profile(200, false)
MSUF_GlobalDB = { profiles = { C = c, D = d }, global = {} }
MSUF_ActiveProfile, MSUF_DB = "C", c
assert(S.Replace({ { name = "G", members = { C = true, D = true }, modules = { unitframes = true, gameplay = true } } }))
c.shortenNames = true
c.swingTimers.main.width = 260
assert(S.Flush())
assert(d.shortenNames == true, "sync did not carry Shorten unit names")
assert(d.swingTimers.main.width == 260, "sync did not carry the swing timers")
assert(S.Owner({ "swingTimers", "main", "width" }) == "gameplay", "swing timers are not owned by the gameplay module")
print("profile_fields_roots_smoke: OK")
