-- Late default fills never overwrite another sync member (review F9), and a
-- first edit of an unset key reaches every member (quality finding C4.2).
-- Modules fill their missing defaults lazily, the first time they read their
-- settings. The sync baseline is taken after those ensures ran on the active
-- profile, so a fill is part of the baseline and never travels. Every change
-- after the baseline is an edit; an earlier rule treated any nil-to-value
-- change as a fill, so a first edit of an unset key never replaced a member's
-- own value.
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
local b = { player = { width = 100, newKey = "custom", unsetKey = "memberOwn" }, gameplay = { combatTimerSize = 30 } }
local c = { player = { width = 100 }, gameplay = {} }
MSUF_GlobalDB = { profiles = { A = a, B = b, C = c }, global = {} }
MSUF_ActiveProfile, MSUF_DB = "A", a
-- The lazy ensures as the real modules publish them (module tables, no globals).
local ensures = {}
NS.MSUF_EnsureDB = function() ensures.defaults = (ensures.defaults or 0) + 1 end
NS.MSUF_EnsureGameplayDefaults = function()
    ensures.gameplay = (ensures.gameplay or 0) + 1
    if MSUF_DB.gameplay.combatTimerSize == nil then MSUF_DB.gameplay.combatTimerSize = 18 end
end
NS.GF = { EnsureDB = function()
    ensures.groups = (ensures.groups or 0) + 1
    if MSUF_DB.player.newKey == nil then MSUF_DB.player.newKey = "default" end
end }
NS.MSUF_Auras3 = { EnsureDB = function() ensures.auras = (ensures.auras or 0) + 1 end }
assert(S.Replace({ { name = "All", members = { A = true, B = true, C = true }, modules = { unitframes = true, gameplay = true } } }))
assert(ensures.defaults == 1 and ensures.gameplay == 1 and ensures.groups == 1 and ensures.auras == 1,
    "the lazy default ensures did not run before the baseline was taken")
assert(a.player.newKey == "default" and a.gameplay.combatTimerSize == 18, "the ensures did not fill the active profile")
-- A real edit after the baseline.
a.player.width = 250
assert(S.Flush())
assert(b.player.newKey == "custom", "a late default fill replaced a member's own value")
assert(b.gameplay.combatTimerSize == 30, "a late gameplay fill replaced a member's own value")
assert(c.player.newKey == nil and c.gameplay.combatTimerSize == nil, "a fill absorbed by the baseline still travelled")
assert(b.player.width == 250 and c.player.width == 250, "a real edit stopped syncing")
-- C4.2: the first edit of a key the source never had reaches every member,
-- also one that holds its own value.
a.player.unsetKey = "edited"
assert(S.Flush())
assert(b.player.unsetKey == "edited", "a first edit of an unset key did not replace a member's own value")
assert(c.player.unsetKey == "edited", "a first edit of an unset key did not reach a member's gap")
-- A value the source already had at the baseline still overwrites members.
a.player.newKey = "changed"
assert(S.Flush())
assert(b.player.newKey == "changed", "an edit of an existing setting no longer reaches the members")
-- A table the source newly inserts is an edit: its leaves replace members' values.
b.player.inserted = { x = 1 }
a.player.inserted = { x = 5 }
assert(S.Flush())
assert(b.player.inserted.x == 5, "a newly inserted table stopped syncing over members")
-- Without sync groups no ensure runs on activation (no cost for everyone else).
ensures = {}
assert(S.Replace({}))
MSUF_ActiveProfile, MSUF_DB = "B", b
S.Activate()
assert(next(ensures) == nil, "activation ran the lazy ensures without any sync group")
print("profile_sync_late_fill_smoke: OK")
