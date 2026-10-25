-- profile_corpus_golden_smoke.lua <repo root> <flavor>
--
-- The old-profile regression corpus on one client (tools/fixtures/profiles):
-- every corpus entry that lists the client loads through the real State
-- pipeline (SavedVariables, ADDON_LOADED, PLAYER_LOGIN, profile binds, a
-- fresh install, profile strings of every historical codec) and must give the
-- effective settings its golden file records, with every export -> import
-- round trip reproducing the profile. The check itself is
-- tools/profile_corpus_golden.lua; on a failure it prints the first differing
-- paths of each entry.
--
-- Regenerate the golden files only for a deliberate, reviewed behaviour
-- change: lua tools/profile_corpus_golden.lua <repo root> all --write
--
-- Plain Lua 5.1.

local root = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "flavor required (a matrix client or Forever)")

local Corpus = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local entries = Corpus.EntriesFor(root, flavor)
assert(#entries > 0, "the corpus has no entry for " .. flavor)

-- Exercise the real registry and Boundary report path, then the corpus driver.
-- A successfully caught/reported module exception must still fail the entry.
local injected = Corpus.RunEntry(root, entries[1], flavor)
local attempts = 0
injected.world.core.MSUF_RegisterModule("corpus-injected-fault", {
    order = -1000, Enable = function() attempts = attempts + 1; error("injected-real-module-error") end,
})
injected.world.core.MSUF_ApplyModules()
assert(attempts > 0, "injected module transition did not run")
local runEntry = Corpus.RunEntry
Corpus.RunEntry = function() return injected end
print("Expected corpus rejection of injected module on " .. flavor .. ":")
local rejected = Corpus.CheckClient(root, flavor, { entry = entries[1].id })
Corpus.RunEntry = runEntry
assert(rejected == 1, "corpus accepted a real Boundary-reported module error")
local found = false
for _, message in ipairs(Corpus.UnexpectedErrors(injected, {})) do
    if message:find("module corpus-injected-fault", 1, true)
        and message:find("injected-real-module-error", 1, true) then found = true end
end
assert(found, "corpus lost the module label or the reported error")

local failures = Corpus.CheckClient(root, flavor)
if failures > 0 then
    error(string.format("%d of %d corpus entries differ from their golden files on %s", failures, #entries, flavor), 0)
end
print(string.format("profile_corpus_golden_smoke: ok (%s, %d entries)", flavor, #entries))
