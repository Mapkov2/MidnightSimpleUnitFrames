-- Verify profile strings through the real core graph and staged API.
local root, source = assert(arg[1]):gsub("\\", "/"), assert(arg[2])
local C = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
local H = assert(loadfile(root .. "/tools/tests/profile_state_harness.lua"))()
local clients = { "Mainline", "Forever", "Vanilla", "TBC", "Mists" }
local key = "_msufAuraClients"
local function World(client, saved)
    local w = C.NewWorld(root, client, "Portable-Realm")
    C.Login(w, saved or {})
    return w
end
local function API(w) return w.core.PublicGlobals end
local function DB(w) return w.env.MSUF_DB end
local function List(w)
    local blacklist = DB(w).auras3.perUnit.target.blacklist
    local buffs = blacklist and blacklist.buffs
    return buffs and buffs.spells or {}
end
local function Configure(w, id)
    local target = DB(w).auras3.perUnit.target
    target.overrideBlacklist = true
    target.blacklist = { spells = {}, buffs = { spells = id and { [id] = true } or {} }, debuffs = { spells = {} } }
end
local function Export(w) return assert(API(w).MSUF_ExportSelectionToString("all")) end
local function ImportJob(w, text, name, legacyRetail)
    local job = assert(w.core.HostAPI.Profiles_BeginImport(text, name, legacyRetail))
    local before = H.Literal(w.env.MSUF_GlobalDB)
    while job.completed < job.total - 1 do
        local done, ok, why = job:Step()
        assert(not done, tostring(ok) .. " " .. tostring(why))
        assert(H.Literal(w.env.MSUF_GlobalDB) == before, "preparation changed SavedVariables")
    end
    local done, ok, why = job:Step()
    assert(done and ok, why)
end
local function Reload(w, client)
    w:FireEvent("PLAYER_LOGOUT")
    local saved = { MSUF_GlobalDB = w.env.MSUF_GlobalDB, MSUF_DB = w.env.MSUF_DB }
    return World(client, assert(loadstring("return " .. H.Literal(saved)))())
end

local sender = World(source)
local sourceSpell, localSpell, editedSpell = "299991", "299992", "299993"
Configure(sender, sourceSpell)
DB(sender).auras3.shared.iconSize = 37
DB(sender).player.width = 239
DB(sender).gf_party.ciSlotTL = "custom"
DB(sender).gf_party.ciCustomTL = { spells = sourceSpell }
local initial = Export(sender)
local decoded = assert(API(sender).MSUF_TryDecodeCompactString(initial))
assert(decoded.msuf6.auraClient == source, "missing full export client")
assert(decoded.auraClient == nil and decoded.payload[key] == nil, "legacy Wago projection changed")

for _, target in ipairs(clients) do
    if target == source then
        local same = World(target)
        assert(API(same).MSUF_ImportIntoNewProfile("Same", initial))
        assert(List(same)[sourceSpell] == true and DB(same)[key] == nil)
    else
        local sync, fast = World(target), World(target)
        for _, w in ipairs({ sync, fast }) do
            Configure(w, localSpell)
            DB(w).player.width = 217
        end
        assert(API(sync).MSUF_ImportFromString(initial))
        ImportJob(fast, initial)
        assert(H.Literal(DB(sync)) == H.Literal(DB(fast)), "fast and synchronous differ for " .. target)
        assert(List(fast)[localSpell] == true and not List(fast)[sourceSpell], "local rules were replaced")
        assert(DB(fast).player.width == 239, "aura projection changed frame transfer")
        Configure(fast, editedSpell)
        fast = Reload(fast, target)
        assert(List(fast)[editedSpell] == true and not List(fast)[sourceSpell])
        local returnText = Export(fast)
        local recovered = World(source)
        ImportJob(recovered, returnText, "Recovered")
        assert(List(recovered)[sourceSpell] == true and not List(recovered)[editedSpell], "source rules lost on return")
        assert(DB(recovered).auras3.shared.iconSize == 37, "source visual setting lost")
        assert(DB(recovered).gf_party.ciCustomTL.spells == sourceSpell, "group corner spell lost")
        local returned = World(target)
        ImportJob(returned, Export(recovered), "Returned")
        assert(List(returned)[editedSpell] == true and not List(returned)[sourceSpell], "target rules lost on second return")
    end
end

local other = source == "Mainline" and "Forever" or "Mainline"
local empty = World(other)
ImportJob(empty, initial, "New client")
assert(not List(empty)[sourceSpell], "fresh target compiled foreign rules")
assert(DB(empty).auras3.shared.iconSize == 37, "portable style was lost")
Configure(empty, nil)
local returning = World(source)
ImportJob(returning, Export(empty), "Returned source")
assert(List(returning)[sourceSpell] == true, "original aura rules did not return")
local freshActive = World(source)
ImportJob(freshActive, Export(empty))
assert(List(freshActive)[sourceSpell] == true, "existing factory profile masked a recovered client section")
local explicitEmpty = World(other)
Configure(explicitEmpty, localSpell)
ImportJob(explicitEmpty, Export(returning), "Explicitly cleared")
assert(next(List(explicitEmpty)) == nil, "explicit empty list was not restored")

DB(sender).profileVariants = { version = 1, entries = { {
    name = "Aura rule", enabled = false, conditions = {},
    patch = { { path = { "auras3", "shared", "iconSize" }, value = 49 } },
} } }
DB(sender).profileVariants.entries[1].patch[2] = { path = { "player", "width" }, value = 245 }
local withVariant = Export(sender)
local variantTarget = World(other)
assert(API(variantTarget).MSUF_ImportFromString(withVariant))
local targetEntries = DB(variantTarget).profileVariants.entries
assert(#targetEntries == 1 and #targetEntries[1].patch == 1 and targetEntries[1].patch[1].path[1] == "player",
    "foreign aura field stayed active or regular field was lost")
targetEntries[1].enabled = true
targetEntries[2] = {
    name = "New frame variant", enabled = false, conditions = {},
    patch = { { path = { "target", "width" }, value = 123 } },
}
local variantBack = World(source)
ImportJob(variantBack, Export(variantTarget), "Aura variants")
local returnedEntries = DB(variantBack).profileVariants.entries
assert(#returnedEntries == 2 and #returnedEntries[1].patch == 2 and returnedEntries[1].patch[1].value == 49,
    "source aura variant was lost")
assert(returnedEntries[1].enabled == true, "a variant's target-side enable change was lost")
assert(returnedEntries[2].name == "New frame variant", "restoring aura data discarded an unrelated variant")
-- A carried variant must honor "Import profile variants" on the intermediate
-- client, including when the same local section already carries a different variant.
if source == "Mainline" then
    local receiving = World("Vanilla")
    local incoming = Export(variantTarget)
    API(receiving).MSUF_Profiles_SetImportVariants(false)
    ImportJob(receiving, incoming, "Exclude variants")
    local round = World(source)
    assert(API(round).MSUF_ImportIntoNewProfile("Excluded", Export(receiving)))
    assert(not DB(round).profileVariants or #DB(round).profileVariants.entries == 0,
        "a carried variant excluded on import returned on its original client")

    API(receiving).MSUF_Profiles_SetImportVariants(true)
    ImportJob(receiving, incoming, "Include first")
    local kept = DB(receiving)[key].clients[source].profileVariants
    kept.entries[1].name = "Kept local rule"
    API(receiving).MSUF_Profiles_SetImportVariants(false)
    ImportJob(receiving, withVariant)
    assert(H.Literal(DB(receiving)[key].clients[source].profileVariants) == H.Literal(kept),
        "import with variants excluded replaced an existing dormant variant")
end
targetEntries[1].conditions = { context = "party" }
local unchanged = H.Literal(variantBack.env.MSUF_GlobalDB)
assert(not API(variantBack).MSUF_ImportIntoNewProfile("Conflict", Export(variantTarget)), "ambiguous variant merge succeeded")
assert(H.Literal(variantBack.env.MSUF_GlobalDB) == unchanged, "variant conflict changed stored profiles")

local external = World(other)
Configure(external, localSpell)
assert(API(external).MSUF_CreateProfile("Inactive"))
assert(API(external).MSUF_ImportExternal(initial, "Inactive"))
assert(List(external)[localSpell] == true and DB(external)[key] == nil, "inactive external import changed the active profile")
API(external).MSUF_SwitchProfile("Inactive")
assert(DB(external)[key].clients[source] and not List(external)[sourceSpell], "inactive profile lost the carried aura section")

local reviewTarget = World(other)
Configure(reviewTarget, localSpell)
local workbench = reviewTarget.core.ProfileWorkbench
local review = assert(workbench.ReviewImport(initial))
local clientRow
for _, row in ipairs(review.changes) do
    if row.auraClient == source then clientRow = row end
end
assert(clientRow and clientRow.selected, "review did not offer the carried section")
assert(workbench.CommitReview(review))
assert(DB(reviewTarget)[key].clients[source] and List(reviewTarget)[localSpell])
local stored = H.Literal(DB(reviewTarget)[key])
local legacy = API(reviewTarget).MSUF_TryDecodeCompactString(Export(reviewTarget))
legacy.msuf6.auraClient = nil
legacy.msuf6.payload[key] = nil
local oldText = API(reviewTarget).MSUF_EncodeCompactTableMSUF3(legacy)
assert(API(reviewTarget).MSUF_ImportFromString(oldText))
assert(H.Literal(DB(reviewTarget)[key]) == stored, "untagged import discarded carried data")
local unitOnly = API(reviewTarget).MSUF_ExportSelectionToString("unitframe")
assert(API(reviewTarget).MSUF_TryDecodeCompactString(unitOnly).payload[key] == nil, "partial export included dormant data")
Configure(reviewTarget, localSpell)
DB(reviewTarget).gf_party.ciSlotTL = "custom"
DB(reviewTarget).gf_party.ciCustomTL = { spells = localSpell }
for _, kind in ipairs({ "unitframe", "unitselection", "groupframe" }) do
    ImportJob(reviewTarget, assert(API(sender).MSUF_ExportSelectionToString(kind, { target = true })))
    assert(List(reviewTarget)[localSpell] == true and not List(reviewTarget)[sourceSpell], kind .. " replaced unit aura rules")
    assert(DB(reviewTarget).gf_party.ciCustomTL.spells == localSpell, kind .. " replaced group aura rules")
    assert(H.Literal(DB(reviewTarget)[key]) == stored, "partial import changed carried sections")
end

local editing = World(other)
local job = assert(editing.core.HostAPI.Profiles_BeginImport(initial))
while job.phase ~= "apply" do assert(not job:Step()) end
Configure(editing, editedSpell)
local done, ok, reason = job:Step()
assert(done and ok, reason)
assert(List(editing)[editedSpell] == true, "fast import staged a stale local aura selection")

local bad = C.Copy(decoded)
bad.msuf6.payload[key] = { version = 1, clients = { [other] = { player = { width = 5 } } } }
local invalid = API(sender).MSUF_EncodeCompactTableMSUF3(bad)
local untouched = H.Literal(sender.env.MSUF_GlobalDB)
assert(not API(sender).MSUF_ImportFromString(invalid), "invalid aura ownership accepted")
assert(H.Literal(sender.env.MSUF_GlobalDB) == untouched, "rejected import wrote to storage")
if source == "Mainline" then
    for _, file in ipairs({ "hist_2026-05-27_msuf3_portable", "hist_2026-07-14_msuf3_raw_profile", "hist_2026-08-06_msuf3_full_schema1" }) do
        local text = C.ReadImportFixture(root, "tools/fixtures/profiles/imports/" .. file .. ".txt")
        local envelope = assert(API(sender).MSUF_TryDecodeCompactString(text))
        local profile = envelope.msuf6 and envelope.msuf6.payload or envelope.payload or envelope
        local auraKey = profile.auras3 and "auras3" or "auras2"
        local aura = profile[auraKey]
        aura.perUnit.target.overrideBlacklist = true
        aura.perUnit.target.blacklist = { buffs = { spells = { [sourceSpell] = true } } }
        aura.shared.blacklist = { buffs = { spells = { [editedSpell] = true } } }
        aura.perUnit.player.overrideBlacklist = false
        profile.gf_party.spellIndicators = profile.gf_party.spellIndicators or {}
        profile.gf_party.spellIndicators.enabled = true
        profile.gf_party.auras.buff.blacklist = { spells = { [sourceSpell] = true } }
        local oldText = assert(API(sender).MSUF_EncodeCompactTableMSUF3(envelope))

        local forever = World("Forever")
        Configure(forever, localSpell)
        ImportJob(forever, oldText, nil, true)
        local archived = DB(forever)[key] and DB(forever)[key].clients.Mainline
        assert(archived and archived.legacyRetail, file .. " missing Retail archive")
        assert(H.Literal(archived[auraKey]) == H.Literal(aura), file .. " altered dormant Retail rules")
        assert(List(forever)[localSpell] and not List(forever)[sourceSpell], file .. " changed active Forever rules")
        forever = Reload(forever, "Forever")

        local retail = World("Mainline")
        ImportJob(retail, Export(forever), "Restored Retail")
        assert(List(retail)[sourceSpell] and not List(retail)[localSpell], file .. " lost Retail unit rules")
        assert(DB(retail).auras3.perUnit.player.blacklist.buffs.spells[editedSpell], file .. " lost inherited Retail rule")
        assert(DB(retail).gf_party.spellIndicators.enabled == true, file .. " lost Retail spell indicators")
        assert(DB(retail).gf_party.auras.buff.blacklist.spells[sourceSpell] == true, file .. " lost Retail group rules")

        local direct = World("Mainline")
        assert(API(direct).MSUF_ImportFromString(oldText, true))
        assert(H.Literal(List(direct)) == H.Literal(List(retail)), file .. " changed Retail rules on the direct import")
    end
end
print("profile_aura_roundtrip_smoke: " .. source .. " same client and four cross-client round trips passed")
