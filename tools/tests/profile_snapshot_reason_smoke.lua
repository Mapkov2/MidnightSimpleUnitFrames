-- A profile snapshot that cannot be taken names the real problem (review
-- F17). Every failure used to read "profile exceeds snapshot limits", which
-- sent users after a size problem when a stray NaN or a value that cannot be
-- saved blocked export, copy and sync.
-- Usage: lua tools/tests/profile_snapshot_reason_smoke.lua <repoRoot>
local root = assert(arg[1], "repo root required")
local NS = {}
for _, name in ipairs({ "ProfileFields", "ProfileVariants" }) do
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/State/MSUF_" .. name .. ".lua"))("MSUF", NS)
end
local V = NS.ProfileVariants
local cyclic = { general = {} }; cyclic.general.loop = cyclic
local wide = { general = {} }
for i = 1, 140000 do wide.general["k" .. i] = i end
for _, case in ipairs({
    { "NaN", { player = { width = 0 / 0 } }, "profile contains an invalid number" },
    { "infinity", { player = { width = math.huge } }, "profile contains an invalid number" },
    { "function", { player = { callback = print } }, "profile contains a value that cannot be saved" },
    { "metatable", { player = setmetatable({}, {}) }, "profile contains a value that cannot be saved" },
    { "cycle", cyclic, "profile contains a table that refers to itself" },
    { "too many values", wide, "profile exceeds snapshot limits" },
}) do
    local copy, why = V.BaseSnapshot(case[2], true)
    assert(copy == nil, case[1] .. ": an invalid profile produced a snapshot")
    assert(why == case[3], case[1] .. ": reported '" .. tostring(why) .. "', expected '" .. case[3] .. "'")
end
assert(V.BaseSnapshot({ player = { width = 1 } }, true), "a valid profile no longer snapshots")
print("profile_snapshot_reason_smoke: OK")
