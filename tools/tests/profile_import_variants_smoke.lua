-- Variant import switch and new-profile rollback (review F22, F23).
-- * With variant import off, a string is never rejected for the variants it
--   leaves behind, and the kept local variants are checked against the
--   imported settings: a mismatch is reported, the variants stay stored.
-- * A new-profile import whose switch fails removes the created profile from
--   Suite as well ("delete" after "create").
-- Usage: lua tools/tests/profile_import_variants_smoke.lua <repoRoot> [flavor]
local root, flavor = assert(arg[1], "repo root required"), arg[2] or "Vanilla"
local w = assert(loadfile(root .. "/tools/tests/client_world.lua"))().New(root, flavor)
local env, ns = w.env, w.core
env.InCombatLockdown = function() return false end
env.IsInInstance = function() return false, "none" end
env.IsInGroup = function() return false end
local load = w.LoadFile
function w:LoadFile(path, addon, namespace)
    if path:match("/State/MSUF_Profiles.lua$") then
        ns.ProfileRuntime.Apply = function()
            ns.ProfileVariants.ResolveCurrent()
            ns.ProfileSync.Activate(); ns.ProfileSync.RefreshEvents()
        end
    end
    return load(self, path, addon, namespace)
end
w:Boot()
local failure = w:FirstFailure(); assert(not failure, failure and failure.message)
local V, F = ns.ProfileVariants, ns.ProfileFields
local function Copy(value) return (F.CopySnapshot(value)) end
env.MSUF_DB = { general = {}, player = { width = 150 } }
env.MSUF_GlobalDB = { profiles = {}, char = {} }
env.MSUF_InitProfiles()
local db = env.MSUF_DB
local exported
env.MSUF_EncodeCompactTableMSUF3 = function(value) exported = value; return "MSUF3:captured" end
env.MSUF_EncodeCompactTable = env.MSUF_EncodeCompactTableMSUF3
assert(env.MSUF_ExportSelectionToString("all"), "full export failed")
local base = Copy(exported)
local source
env.MSUF_TryDecodeCompactString = function(str) if str == "MSUF3:captured" then return Copy(source) end end
local function Payload(value) return value.msuf6 and value.msuf6.payload or value.payload end
local function Printed(pattern)
    for i = #w.prints, 1, -1 do if w.prints[i]:find(pattern, 1, true) then return true end end
    return false
end

-- F22a: invalid variants in a string are ignored while variant import is off.
source = Copy(base)
Payload(source).profileVariants = { version = 2, entries = {} }
env.MSUF_Profiles_SetImportVariants(true)
local ok, why = env.MSUF_ImportFromString("MSUF3:captured")
assert(not ok and why == "invalid profile variants", "variant import on must still validate the variants: " .. tostring(why))
env.MSUF_Profiles_SetImportVariants(false)
ok, why = env.MSUF_ImportFromString("MSUF3:captured")
assert(ok, "variant import off rejected a string for variants it does not import: " .. tostring(why))

-- F22b: kept local variants that no longer fit the imported settings are
-- reported once and stay stored unchanged.
assert(V.Replace(db, { version = 1, entries = { { name = "Local", patch = { { path = { "player", "width" }, value = 250 } } } } }))
local before = #w.prints
source = Copy(base)
Payload(source).player.width = "wide"
ok, why = env.MSUF_ImportFromString("MSUF3:captured")
assert(ok, "import with kept variants failed: " .. tostring(why))
assert(Printed("do not match the imported settings"), "a kept variant that no longer fits was not reported")
local kept = V.Find(env.MSUF_DB, "Local")
assert(kept and kept.patch[1].value == 250, "kept local variants were changed or dropped")
-- A kept variant that still fits stays quiet.
local quiet = #w.prints
source = Copy(base)
ok, why = env.MSUF_ImportFromString("MSUF3:captured")
assert(ok, "second import failed: " .. tostring(why))
for i = quiet + 1, #w.prints do
    assert(not w.prints[i]:find("do not match the imported settings", 1, true), "a fitting kept variant was reported")
end
assert(before < quiet)

-- F23: a new profile created for an import that cannot switch to it is
-- removed again, also from Suite.
local lifecycle = {}
env.MSUFSuite = { OnMSUFProfileLifecycle = function(kind, a) lifecycle[#lifecycle + 1] = kind .. ":" .. tostring(a); return true end }
local factory = Copy(env.MSUF_DB)
ns.MSUF_CreateFactoryDefaultProfile = function() return Copy(factory) end
local realSwitch = env.MSUF_SwitchProfile
env.MSUF_SwitchProfile = function(name)
    if name == "Rollback" then return false, "switch refused by the smoke" end
    return realSwitch(name)
end
source = Copy(base)
local created, reason, stage = env.MSUF_ImportIntoNewProfile("Rollback", "MSUF3:captured")
env.MSUF_SwitchProfile = realSwitch
assert(not created and stage == "switch", "the refused switch was not reported: " .. tostring(reason) .. "/" .. tostring(stage))
assert(env.MSUF_GlobalDB.profiles.Rollback == nil, "the rolled-back profile is still stored")
local sawCreate, sawDelete = false, false
for _, entry in ipairs(lifecycle) do
    if entry == "create:Rollback" then sawCreate = true end
    if entry == "delete:Rollback" and sawCreate then sawDelete = true end
end
assert(sawCreate, "Suite never heard about the created profile")
assert(sawDelete, "Suite kept the rolled-back profile (no delete after create)")
print("profile_import_variants_smoke: OK (" .. flavor .. ")")
