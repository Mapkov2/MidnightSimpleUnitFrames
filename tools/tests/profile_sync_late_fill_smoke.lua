-- Late default fills never overwrite another sync member (review F9). The
-- baseline is taken when a profile becomes active, before modules fill their
-- missing defaults lazily; such a fill appears as a new value in the source.
-- It may fill a member's gap but must never replace a value the member has.
-- Usage: lua tools/tests/profile_sync_late_fill_smoke.lua <repoRoot>
local root = assert(arg[1], "repo root required")
local NS = {}
function InCombatLockdown() return false end
function CreateFrame() return { SetScript = function() end, RegisterEvent = function() end, UnregisterAllEvents = function() end } end
for _, name in ipairs({ "ProfileFields", "ProfileVariants", "ProfileSync" }) do
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_" .. name .. ".lua"))("MSUF", NS)
end
local S = NS.ProfileSync
local a = { player = { width = 100 }, gameplay = {} }
local b = { player = { width = 100, newKey = "custom" }, gameplay = { combatTimerSize = 30 } }
local c = { player = { width = 100 }, gameplay = {} }
MSUF_GlobalDB = { profiles = { A = a, B = b, C = c }, global = {} }
MSUF_ActiveProfile, MSUF_DB = "A", a
assert(S.Replace({ { name = "All", members = { A = true, B = true, C = true }, modules = { unitframes = true, gameplay = true } } }))
-- Lazy fills after the baseline, then one real edit.
a.player.newKey = "default"
a.gameplay.combatTimerSize = 18
a.player.width = 250
assert(S.Flush())
assert(b.player.newKey == "custom", "a late default fill replaced a member's own value")
assert(b.gameplay.combatTimerSize == 30, "a late gameplay fill replaced a member's own value")
assert(c.player.newKey == "default" and c.gameplay.combatTimerSize == 18, "a late fill no longer fills a member's gap")
assert(b.player.width == 250 and c.player.width == 250, "a real edit stopped syncing")
-- A value the source already had at the baseline still overwrites members.
a.player.newKey = "changed"
assert(S.Flush())
assert(b.player.newKey == "changed", "an edit of an existing setting no longer reaches the members")
-- A table the source newly inserts is an edit: its leaves replace members' values.
b.player.inserted = { x = 1 }
a.player.inserted = { x = 5 }
assert(S.Flush())
assert(b.player.inserted.x == 5, "a newly inserted table stopped syncing over members")
print("profile_sync_late_fill_smoke: OK")
