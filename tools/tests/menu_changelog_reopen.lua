local root = assert(arg[1])
local mw = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))().Open(root, arg[2] or "Mainline", { page = "home" })
local M = mw.M
assert(M.OpenSeeNewFeatures())
mw:RunTimers()
local frames, entry = mw:Frames(), M.cache.changelog
local counts = {}
for i = 1, 3 do
    M.SelectPage("home")
    assert(M.OpenSeeNewFeatures())
    mw:RunTimers()
    counts[i] = mw:Frames() - frames
end
print("changelog reopen frames: " .. table.concat(counts, ","))
assert(mw:Frames() == frames and M.cache.changelog == entry, "unchanged changelog rebuilt its frame tree")
