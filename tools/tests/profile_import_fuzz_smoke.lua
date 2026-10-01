-- Profile import fuzz (review F1). A type-mutated full profile string is
-- either rejected cleanly or applied safely: an import never raises, never
-- leaves a half-written profile behind, and the saved state boots again.
-- Paths: import into the active profile, into a new profile, and the external
-- (Wago) import into a stored profile followed by a switch to it. The commit
-- swaps in a candidate that already ran the complete normalization, so a
-- normalizer that raises leaves every stored profile exactly as it was.
-- Usage: lua tools/tests/profile_import_fuzz_smoke.lua <repoRoot> <flavor>
local root, flavor = assert(arg[1], "repo root required"), arg[2] or "Vanilla"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function NewWorld()
    local w = World.New(root, flavor)
    local env, ns = w.env, w.core
    env.InCombatLockdown = function() return false end
    env.IsInInstance = function() return false, "none" end
    env.IsInGroup = function() return false end
    local load = w.LoadFile
    function w:LoadFile(path, addon, namespace)
        if path:match("/State/MSUF_Profiles.lua$") then
            -- Keep the real storage and normalization pipeline; the frame
            -- renderers behind the runtime apply are outside this test.
            ns.ProfileRuntime.Apply = function()
                ns.ProfileVariants.ResolveCurrent()
                ns.ProfileSync.Activate(); ns.ProfileSync.RefreshEvents()
            end
        end
        return load(self, path, addon, namespace)
    end
    w:Boot()
    local failure = w:FirstFailure()
    assert(not failure, failure and (failure.file .. ": " .. failure.message))
    return w
end

local function Copy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}; seen[v] = out
    for k, x in pairs(v) do out[Copy(k, seen)] = Copy(x, seen) end
    return out
end
-- _resolvedFrameScale is the group-frame scale cache: the group-frame code
-- writes it into the live scope whenever it reads frame metrics, the
-- position repair of any profile included. It is not profile data.
local CACHE_KEYS = { _resolvedFrameScale = true }
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not CACHE_KEYS[k] and not Equal(v, b[k]) then return false end end
    for k in pairs(b) do if not CACHE_KEYS[k] and a[k] == nil then return false end end
    return true
end
local function SortedStringKeys(t)
    local keys = {}
    for k in pairs(t) do if type(k) == "string" then keys[#keys + 1] = k end end
    table.sort(keys)
    return keys
end

local w = NewWorld()
local env, ns = w.env, w.core
env.MSUF_DB = { general = {}, player = { width = 150 } }
env.MSUF_GlobalDB = { profiles = {}, char = {} }
env.MSUF_InitProfiles()
local exported
env.MSUF_EncodeCompactTableMSUF3 = function(value) exported = value; return "MSUF3:captured" end
env.MSUF_EncodeCompactTable = env.MSUF_EncodeCompactTableMSUF3
assert(env.MSUF_ExportSelectionToString("all"), "full export failed")
local base = Copy(exported)
local source
-- Only the fuzz string decodes to the mutated payload; every other compact
-- string (the factory profile a new profile starts from) keeps its decoder.
local decodeCompact = env.MSUF_TryDecodeCompactString
env.MSUF_TryDecodeCompactString = function(str)
    if str == "MSUF3:captured" then return Copy(source) end
    return decodeCompact(str)
end
local function Payload(snapshot) return snapshot.msuf6 and snapshot.msuf6.payload or snapshot.payload end
-- The harness has no native CBOR decoder for the embedded factory string, so
-- a new profile starts from a copy of the clean, normalized active profile.
local factory = Copy(env.MSUF_DB)
ns.MSUF_CreateFactoryDefaultProfile = function() return Copy(factory) end
local savedGlobal = Copy(env.MSUF_GlobalDB)
local savedActive = env.MSUF_ActiveProfile

-- Mutations: every table up to three levels deep becomes a number and a
-- string (a root also a boolean); every root scalar and a fixed sample of the
-- second-level scalars become a table.
local mutations = {}
local function Add(label, path, value, crossPaths)
    mutations[#mutations + 1] = { label = label, path = path, value = value, cross = crossPaths }
end
local scalarIndex = 0
local function Walk(tbl, path, depth)
    for _, key in ipairs(SortedStringKeys(tbl)) do
        local value = tbl[key]
        local p = path == "" and key or (path .. "." .. key)
        if type(value) == "table" then
            for _, bad in ipairs(depth == 1 and { 1, "x", true } or { 1, "x" }) do
                Add(p .. "=" .. tostring(bad), p, bad, (#mutations % 5) == 0)
            end
            if depth < 3 then Walk(value, p, depth + 1) end
        elseif depth == 1 then
            Add(p .. "={}", p, "__table", true)
        elseif depth == 2 then
            scalarIndex = scalarIndex + 1
            if scalarIndex % 47 == 0 then Add(p .. "={}", p, "__table", false) end
        end
    end
end
Walk(Payload(base), "", 1)
-- Regression cases from the review and the scalar sweep.
Add("auras3=1 (review F1)", "auras3", 1, true)
Add("general.statusIndicators=1 (review F1)", "general.statusIndicators", 1, true)
Add("player.castbar=x (review F1)", "player.castbar", "x", true)
Add("general.fontColor={}", "general.fontColor", "__table", true)
local perUnit = Payload(base).auras3 and Payload(base).auras3.perUnit
if type(perUnit) == "table" then
    local units = SortedStringKeys(perUnit)
    if units[1] then Add("auras3.perUnit." .. units[1] .. "=1", "auras3.perUnit." .. units[1], 1, true) end
end
assert(#mutations >= 100, "fuzz needs at least 100 type mutations, got " .. #mutations)

local function SetPath(t, path, value)
    local parts = {}
    for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
    for i = 1, #parts - 1 do
        t = t[parts[i]]
        if type(t) ~= "table" then return false end
    end
    if value == "__table" then value = {} end
    t[parts[#parts]] = value
    return true
end

local failures = {}
local function Fail(label, message) failures[#failures + 1] = label .. ": " .. tostring(message) end

local function Restore()
    env.MSUF_GlobalDB = Copy(savedGlobal)
    env.MSUF_DB, env.MSUF_ActiveProfile = nil, nil
    env.MSUF_InitProfiles()
    assert(env.MSUF_ActiveProfile == savedActive, "restore lost the active profile")
end

local function NormalizedShape(profile)
    if type(profile) ~= "table" then return "profile is not a table" end
    for _, key in ipairs({ "general", "classColors", "npcColors", "bars", "gameplay", "player", "target",
        "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena", "auras3" }) do
        if type(profile[key]) ~= "table" then return key .. " is " .. type(profile[key]) end
    end
    if type(profile.auras3.perUnit) == "table" then
        for unit, owner in pairs(profile.auras3.perUnit) do
            if type(owner) ~= "table" then return "auras3.perUnit." .. tostring(unit) .. " is " .. type(owner) end
        end
    end
    if type(profile.general.statusIndicators) ~= "table" then return "general.statusIndicators is not a table" end
    if type(profile.player.castbar) ~= "table" then return "player.castbar is not a table" end
    if type(profile.general.fontColor) ~= "string" then return "general.fontColor is not a string" end
    if tonumber(profile._msufProfileSchema) ~= 600 then return "profile lost its schema stamp" end
    return nil
end

-- The next login boots the saved account state in a second world.
local login = NewWorld()
local function NextLogin(label)
    login.env.MSUF_GlobalDB = Copy(env.MSUF_GlobalDB)
    login.env.MSUF_DB, login.env.MSUF_ActiveProfile = nil, nil
    local ok, err = pcall(login.env.MSUF_InitProfiles)
    if ok then ok, err = pcall(login.env.MSUF_EnsureDB, true) end
    if ok then ok, err = pcall(login.env.MSUF_GF_EnsureDB) end
    if ok then ok, err = pcall(login.core.MSUF_Auras3.EnsureDB) end
    if not ok then Fail(label, "next login raised: " .. tostring(err)) end
end

QUIET = true
local accepted, rejected, appliedBy = 0, 0, { active = 0, new = 0, external = 0 }
local function Run(m, mode)
    source = Copy(base)
    if not SetPath(Payload(source), m.path, m.value) then return end
    local before = Copy(env.MSUF_GlobalDB)
    local ok, result, why
    if mode == "new" then
        ok, result, why = pcall(env.MSUF_ImportIntoNewProfile, "FuzzNew", "MSUF3:captured")
    elseif mode == "external" then
        ok, result, why = pcall(env.MSUF_ImportExternal, "MSUF3:captured", "FuzzExternal")
        if ok and result then ok, result, why = pcall(env.MSUF_SwitchProfile, "FuzzExternal") end
    else
        ok, result, why = pcall(env.MSUF_ImportFromString, "MSUF3:captured")
    end
    local label = mode .. " " .. m.label
    if not ok then
        Fail(label, "raised: " .. tostring(result))
    elseif result == false then
        rejected = rejected + 1
        if type(why) ~= "string" or why == "" then Fail(label, "rejection without a reason") end
        if not Equal(before, env.MSUF_GlobalDB) then Fail(label, "rejected import changed saved profiles") end
    else
        accepted = accepted + 1
        appliedBy[mode] = appliedBy[mode] + 1
        local shape = NormalizedShape(env.MSUF_GlobalDB.profiles[env.MSUF_ActiveProfile])
        if shape then Fail(label, "applied profile is not normalized: " .. shape) end
        if env.MSUF_GlobalDB.profiles[env.MSUF_ActiveProfile] ~= env.MSUF_DB then
            Fail(label, "active profile table was replaced")
        end
        NextLogin(label)
    end
    Restore()
end

for _, m in ipairs(mutations) do
    Run(m, "active")
    if m.cross then
        Run(m, "new")
        Run(m, "external")
    end
end

-- Transaction boundary: a normalizer that raises must leave every stored
-- profile, the active binding and the profile list exactly as they were.
do
    local repair = ns.GF.RepairGroupDB
    ns.GF.RepairGroupDB = function() error("normalizer failure injected by the smoke") end
    for _, mode in ipairs({ "active", "new", "external" }) do
        source = Copy(base)
        local before = Copy(env.MSUF_GlobalDB)
        local beforeActive = env.MSUF_ActiveProfile
        local ok
        if mode == "new" then
            ok = pcall(env.MSUF_ImportIntoNewProfile, "TxNew", "MSUF3:captured")
        elseif mode == "external" then
            ok = pcall(env.MSUF_ImportExternal, "MSUF3:captured", "TxExternal")
        else
            ok = pcall(env.MSUF_ImportFromString, "MSUF3:captured")
        end
        if ok then Fail("transaction " .. mode, "the injected normalizer failure did not surface") end
        if not Equal(before, env.MSUF_GlobalDB) then
            Fail("transaction " .. mode, "a failed normalization changed saved profiles")
        end
        if env.MSUF_ActiveProfile ~= beforeActive then
            Fail("transaction " .. mode, "a failed normalization switched the active profile")
        end
    end
    ns.GF.RepairGroupDB = repair
    Restore()
end

for _, mode in ipairs({ "active", "new", "external" }) do
    if appliedBy[mode] == 0 then Fail(mode, "no import of this kind was applied; the path went untested") end
end
if #failures > 0 then
    for i = 1, math.min(#failures, 25) do print("FAIL " .. failures[i]) end
    error(string.format("profile_import_fuzz_smoke (%s): %d failure(s) over %d mutations", flavor, #failures, #mutations))
end
print(string.format("profile_import_fuzz_smoke: OK (%s, %d mutations, %d imports applied, %d rejected cleanly)",
    flavor, #mutations, accepted, rejected))
