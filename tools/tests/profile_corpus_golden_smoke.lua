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

local failures = Corpus.CheckClient(root, flavor)
if failures > 0 then
    error(string.format("%d of %d corpus entries differ from their golden files on %s", failures, #entries, flavor), 0)
end
print(string.format("profile_corpus_golden_smoke: ok (%s, %d entries)", flavor, #entries))
