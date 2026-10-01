-- Saving a variant recording keeps what the user meant (review F24).
-- * A field of the entry the recording did not touch stays, even when its
--   value happens to equal the base at that moment.
-- * A change under a key no field path can name is reported, not dropped
--   silently.
-- * Lazy default fills run before the recording base is taken, so a module
--   completing its settings during the recording records nothing.
-- Usage: lua tools/tests/profile_variant_save_smoke.lua <repoRoot>
local root = assert(arg[1], "repo root required")
local prints = {}
print = function(text) prints[#prints + 1] = tostring(text) end
local NS = {}
function InCombatLockdown() return false end
function CreateFrame() return { SetScript = function() end, RegisterEvent = function() end, UnregisterAllEvents = function() end } end
function IsInInstance() return false, "none" end
function IsInGroup() return false end
function MSUF_GetPlayerSpecID() return 63 end
for _, name in ipairs({ "ProfileFields", "ProfileVariants", "ProfileSync", "ProfileVariantEditor" }) do
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_" .. name .. ".lua"))("MSUF", NS)
end
local V = NS.ProfileVariants
NS.ProfileRuntime = { Apply = function() end }
local function Fields(entry)
    local out = {}
    for _, field in ipairs(entry.patch) do out[table.concat(field.path, ".")] = field.value end
    return out
end
-- A lazy filler the way modules complete their settings on first use.
local function LazyFill() if MSUF_DB.gameplay.filledLater == nil then MSUF_DB.gameplay.filledLater = 18 end end
NS.ProfileIOEnsureCompleteProfileDB = LazyFill

local db = { general = {}, gameplay = {}, player = { width = 150, height = 30, native = { [0] = 7 } },
    profileVariants = { version = 1, entries = { { name = "Raid", conditions = { context = "raid" }, patch = {
        { path = { "player", "width" }, value = 150 },
    } } } } }
MSUF_DB, MSUF_ActiveProfile = db, "A"
MSUF_GlobalDB = { profiles = { A = db }, global = {} }

assert(V.BeginRecording("Raid"))
db.player.height = 40          -- a real edit
db.player.native[0] = 9         -- a key no field path can name
LazyFill()                      -- a module page opened during the recording
assert(V.SaveRecording())
local saved = Fields(V.Find(db, "Raid"))
assert(saved["player.height"] == 40, "the edit was not recorded")
assert(saved["player.width"] == 150, "an untouched field equal to the base was dropped")
assert(saved["gameplay.filledLater"] == nil, "a lazy default fill became a variant field")
local reported = false
for _, line in ipairs(prints) do if line:find("could not be stored", 1, true) then reported = true end end
assert(reported, "an edit the variant cannot store was dropped silently")
assert(db.player.height == 30 and db.player.native[0] == 7, "saving changed the base")

-- Setting a field back to its base value still removes it.
assert(V.BeginRecording("Raid"))
db.player.height = 30
assert(V.SaveRecording())
saved = Fields(V.Find(db, "Raid"))
assert(saved["player.height"] == nil and saved["player.width"] == 150, "returning a value to its base did not remove only that field")
io.write("profile_variant_save_smoke: OK\n")
