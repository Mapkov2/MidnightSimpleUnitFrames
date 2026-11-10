-- Verify profile strings through the real Beta 6 core graph and synchronous APIs.
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
local function Tag(w, text, client)
    local api = API(w)
    local envelope = assert(api.MSUF_TryDecodeCompactString(text))
    if envelope.msuf6 then
        assert(envelope.msuf6.auraClient == nil, "ordinary full export unexpectedly changed its wire format")
        envelope.msuf6.auraClient = client
        return assert(api.MSUF_EncodeCompactTableMSUF3(envelope))
    end
    assert(envelope.auraClient == nil, "ordinary partial export unexpectedly changed its wire format")
    envelope.auraClient = client
    return assert(api.MSUF_EncodeCompactTable(envelope))
end
local function Import(w, text, name, legacyRetail)
    local api = API(w)
    local ok, why
    if name then ok, why = api.MSUF_ImportIntoNewProfile(name, text, legacyRetail)
    else ok, why = api.MSUF_ImportFromString(text, legacyRetail) end
    assert(ok, why)
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
local initial = Tag(sender, Export(sender), source)
local decoded = assert(API(sender).MSUF_TryDecodeCompactString(initial))
assert(decoded.msuf6.auraClient == source, "missing full export client")
assert(decoded.auraClient == nil and decoded.payload[key] == nil, "legacy Wago projection changed")

for _, target in ipairs(clients) do
    if target == source then
        local same = World(target)
        assert(API(same).MSUF_ImportIntoNewProfile("Same", initial))
        assert(List(same)[sourceSpell] == true and DB(same)[key] == nil)
    else
        local receiver = World(target)
        Configure(receiver, localSpell)
        DB(receiver).player.width = 217
        Import(receiver, initial)
        assert(List(receiver)[localSpell] == true and not List(receiver)[sourceSpell], "local rules were replaced")
        assert(DB(receiver).player.width == 239, "aura projection changed frame transfer")
        Configure(receiver, editedSpell)
        receiver = Reload(receiver, target)
        assert(List(receiver)[editedSpell] == true and not List(receiver)[sourceSpell])
        local returnText = Export(receiver)
        local recovered = World(source)
        Import(recovered, returnText, "Recovered")
        assert(List(recovered)[sourceSpell] == true and not List(recovered)[editedSpell], "source rules lost on return")
        assert(DB(recovered).auras3.shared.iconSize == 37, "source visual setting lost")
        assert(DB(recovered).gf_party.ciCustomTL.spells == sourceSpell, "group corner spell lost")
        local returned = World(target)
        Import(returned, Export(recovered), "Returned")
        assert(List(returned)[editedSpell] == true and not List(returned)[sourceSpell], "target rules lost on second return")
    end
end

local other = source == "Mainline" and "Forever" or "Mainline"
local empty = World(other)
Import(empty, initial, "New client")
assert(not List(empty)[sourceSpell], "fresh target compiled foreign rules")
assert(DB(empty).auras3.shared.iconSize == 37, "portable style was lost")
Configure(empty, nil)
local returning = World(source)
Import(returning, Export(empty), "Returned source")
assert(List(returning)[sourceSpell] == true, "original aura rules did not return")
local freshActive = World(source)
Configure(freshActive, localSpell)
Import(freshActive, Export(empty))
assert(List(freshActive)[sourceSpell] == true and not List(freshActive)[localSpell],
    "customized active profile masked an incoming current-client archive")
local returnedReview = World(source)
Configure(returnedReview, localSpell)
local returnWorkbench = returnedReview.core.ProfileWorkbench
assert(returnWorkbench.CommitReview(assert(returnWorkbench.ReviewImport(Export(empty)))))
assert(H.Literal(List(returnedReview)) == H.Literal(List(freshActive)), "direct and reviewed archive return disagree")
local explicitEmpty = World(other)
Configure(explicitEmpty, localSpell)
Import(explicitEmpty, Export(returning), "Explicitly cleared")
assert(next(List(explicitEmpty)) == nil, "explicit empty list was not restored")

DB(sender).profileVariants = { version = 1, entries = { {
    name = "Aura rule", enabled = false, conditions = {},
    patch = { { path = { "auras3", "shared", "iconSize" }, value = 49 } },
} } }
DB(sender).profileVariants.entries[1].patch[2] = { path = { "player", "width" }, value = 245 }
local withVariant = Tag(sender, Export(sender), source)
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
Import(variantBack, Export(variantTarget), "Aura variants")
local returnedEntries = DB(variantBack).profileVariants.entries
assert(#returnedEntries == 2 and #returnedEntries[1].patch == 2 and returnedEntries[1].patch[1].value == 49,
    "source aura variant was lost")
assert(returnedEntries[1].enabled == true, "a variant's target-side enable change was lost")
assert(returnedEntries[2].name == "New frame variant", "restoring aura data discarded an unrelated variant")
targetEntries[1].conditions = { context = "party" }
local unchanged = H.Literal(variantBack.env.MSUF_GlobalDB)
assert(not API(variantBack).MSUF_ImportIntoNewProfile("Conflict", Export(variantTarget)), "ambiguous variant merge succeeded")
assert(H.Literal(variantBack.env.MSUF_GlobalDB) == unchanged, "variant conflict changed stored profiles")
local variantActive = World(source)
local messages = {}
variantActive.env.print = function(line) messages[#messages + 1] = line end
local activeBefore = H.Literal(variantActive.env.MSUF_GlobalDB)
assert(not API(variantActive).MSUF_ImportFromString(Export(variantTarget)), "active import accepted conflicting aura variants")
assert(H.Literal(variantActive.env.MSUF_GlobalDB) == activeBefore, "active variant conflict changed stored profiles")
assert(table.concat(messages, "\n"):find("Import failed:", 1, true), "active Stage rejection had no error message")

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
    local partial = assert(API(sender).MSUF_ExportSelectionToString(kind, { target = true }))
    Import(reviewTarget, Tag(sender, partial, source))
    assert(List(reviewTarget)[localSpell] == true and not List(reviewTarget)[sourceSpell], kind .. " replaced unit aura rules")
    assert(DB(reviewTarget).gf_party.ciCustomTL.spells == localSpell, kind .. " replaced group aura rules")
    assert(H.Literal(DB(reviewTarget)[key]) == stored, "partial import changed carried sections")
end

-- Conflicting dormant data comes from the incoming profile; local-only clients survive.
local conflict = World(source)
local incomingEnvelope = assert(API(empty).MSUF_TryDecodeCompactString(Export(empty)))
local third, fourth
for _, client in ipairs(clients) do
    if client ~= source and client ~= other then
        if not third then third = client elseif not fourth then fourth = client end
    end
end
local sourceSection = C.Copy(incomingEnvelope.msuf6.payload[key].clients[source])
local incomingSection, localSection = C.Copy(sourceSection), C.Copy(sourceSection)
incomingSection.auras3.perUnit.target.blacklist.buffs.spells = { [sourceSpell] = true }
localSection.auras3.perUnit.target.blacklist.buffs.spells = { [localSpell] = true }
incomingEnvelope.msuf6.payload[key].clients[third] = incomingSection
DB(conflict)[key] = { version = 1, clients = { [third] = localSection, [fourth] = C.Copy(localSection) } }
Import(conflict, assert(API(empty).MSUF_EncodeCompactTableMSUF3(incomingEnvelope)))
assert(H.Literal(DB(conflict)[key].clients[third]) == H.Literal(incomingSection), "local archive replaced incoming dormant client")
assert(H.Literal(DB(conflict)[key].clients[fourth]) == H.Literal(localSection), "local-only dormant client was discarded")

-- Disabling variant import keeps local dormant variants as well as active ones.
local function AuraVariant(name, size)
    return { version = 1, entries = { { name = name, enabled = false, conditions = {},
        patch = { { path = { "auras3", "shared", "iconSize" }, value = size } } } } }
end
local variantSender, variantReceiver = World(source), World(other)
DB(variantSender).profileVariants = AuraVariant("Stored source variant", 41)
Import(variantReceiver, Tag(variantSender, Export(variantSender), source))
local savedVariants = H.Literal(DB(variantReceiver)[key].clients[source].profileVariants)
DB(variantReceiver).profileVariants = AuraVariant("Active destination variant", 43)
local activeVariants = H.Literal(assert(variantReceiver.core.ProfileVariants.ValidateForProfile(
    DB(variantReceiver), DB(variantReceiver).profileVariants)))
DB(variantSender).profileVariants = AuraVariant("Incoming source variant", 51)
API(variantReceiver).MSUF_Profiles_SetImportVariants(false)
Import(variantReceiver, Tag(variantSender, Export(variantSender), source))
assert(H.Literal(DB(variantReceiver)[key].clients[source].profileVariants or {}) == savedVariants,
    "variant opt-out dropped existing foreign archive variants")
assert(H.Literal(DB(variantReceiver).profileVariants) == activeVariants, "variant opt-out changed active variants")
local variantNewTarget = World(third)
API(variantNewTarget).MSUF_Profiles_SetImportVariants(false)
Import(variantNewTarget, Export(variantReceiver))
assert(DB(variantNewTarget)[key].clients[source].profileVariants == nil, "variant opt-out imported incoming dormant variants")
local currentVariantsTarget = World(source)
DB(currentVariantsTarget).profileVariants = AuraVariant("Current-client local variant", 45)
local expectedCurrent = H.Literal(assert(currentVariantsTarget.core.ProfileVariants.ValidateForProfile(
    DB(currentVariantsTarget), DB(currentVariantsTarget).profileVariants)))
API(currentVariantsTarget).MSUF_Profiles_SetImportVariants(false)
Import(currentVariantsTarget, Export(variantReceiver))
assert(H.Literal(DB(currentVariantsTarget).profileVariants) == expectedCurrent,
    "variant opt-out imported a current-client archive variant")
local emptyCurrent = World(source)
API(emptyCurrent).MSUF_Profiles_SetImportVariants(false)
Import(emptyCurrent, Export(variantReceiver))
assert(DB(emptyCurrent).profileVariants == nil, "variant opt-out restored incoming variants into an empty current client")

local variantReview = World(third)
DB(variantReview)[key] = { version = 1, clients = { [source] = C.Copy(DB(variantReceiver)[key].clients[source]) } }
API(variantReview).MSUF_Profiles_SetImportVariants(false)
local incomingVariants = assert(API(variantReceiver).MSUF_TryDecodeCompactString(Export(variantReceiver)))
incomingVariants.msuf6.payload[key].clients[source].profileVariants = AuraVariant("Incoming dormant variant", 61)
local variantWorkbench = variantReview.core.ProfileWorkbench
assert(variantWorkbench.CommitReview(assert(variantWorkbench.ReviewImport(API(variantReceiver).MSUF_EncodeCompactTableMSUF3(incomingVariants)))))
assert(H.Literal(DB(variantReview)[key].clients[source].profileVariants) == savedVariants,
    "variant opt-out replaced local dormant variants during review")

local partialText = assert(API(sender).MSUF_ExportSelectionToString("unitframe"))
local partialTarget = World(other)
local partialBefore = H.Literal(partialTarget.env.MSUF_GlobalDB)
local partialMessages = {}
partialTarget.env.print = function(line) partialMessages[#partialMessages + 1] = line end
assert(not API(partialTarget).MSUF_ImportFromString(partialText, true), "Retail flag silently accepted a partial profile")
assert(table.concat(partialMessages):find("The Retail option applies only to full MSUF profile strings.", 1, true),
    "Retail partial rejection did not explain the full-profile requirement")
assert(H.Literal(partialTarget.env.MSUF_GlobalDB) == partialBefore, "partial Retail rejection changed profile storage")
local partialOK, partialWhy = API(partialTarget).MSUF_ImportIntoNewProfile("Rejected partial", partialText, true)
assert(not partialOK and partialWhy == "The Retail option applies only to full MSUF profile strings.")
local partialReview, reviewWhy = partialTarget.core.ProfileWorkbench.ReviewImport(partialText, true)
assert(not partialReview and reviewWhy == partialWhy, "review omitted the partial Retail rejection reason")

local bad = C.Copy(decoded)
bad.msuf6.payload[key] = { version = 1, clients = { [other] = { player = { width = 5 } } } }
local invalid = API(sender).MSUF_EncodeCompactTableMSUF3(bad)
local untouched = H.Literal(sender.env.MSUF_GlobalDB)
assert(not API(sender).MSUF_ImportFromString(invalid), "invalid aura ownership accepted")
assert(H.Literal(sender.env.MSUF_GlobalDB) == untouched, "rejected import wrote to storage")
if source == "Mainline" then
    local function Equal(a, b, message) assert(H.Literal(a) == H.Literal(b), message) end
    local function Geometry(profile)
        local out = {}
        local function Fields(prefix, value, names)
            for _, name in ipairs(names) do out[prefix .. "." .. name] = C.Copy(type(value) == "table" and value[name] or nil) end
        end
        local aura = profile.auras3 or {}
        Fields("shared", aura.shared, { "iconSize", "spacing", "iconZoom", "iconHeightPercent", "cooldownTextSize", "stackTextSize" })
        for unit, conf in pairs(aura.perUnit or {}) do
            Fields(unit, conf, { "layout", "layoutShared", "overrideLayout", "overrideSharedLayout" })
            local sharedLayout = out[unit .. ".layoutShared"]
            if sharedLayout then sharedLayout.showBuffs = nil; sharedLayout.showDebuffs = nil end
        end
        for _, rootKey in ipairs({ "customContainers", "customDisplays" }) do
            for unit, conf in pairs(aura[rootKey] and aura[rootKey].perUnit or {}) do
                for index, item in pairs(conf.items or {}) do
                    local prefix = rootKey .. "." .. unit .. "." .. index
                    Fields(prefix, item, { "layer", "strata", "frame" })
                    Fields(prefix .. ".placed", item.placed,
                        { "anchor", "x", "y", "size", "growth", "max", "perRow", "spacing", "cooldownSize", "stackSize" })
                end
            end
        end
        for _, scope in ipairs({ "gf_party", "gf_raid", "gf_mythicraid", "gf_priority" }) do
            local frame = profile[scope] or {}
            Fields(scope .. ".spellIndicators", frame.spellIndicators, { "layer", "strata", "iconZoom", "iconScale", "style" })
            for _, lane in ipairs({ "buff", "debuff", "externals" }) do
                Fields(scope .. "." .. lane, frame.auras and frame.auras[lane],
                    { "size", "spacing", "max", "perRow", "anchor", "x", "y", "growth", "iconScale", "cooldownSize", "stackSize" })
            end
        end
        return out
    end
    -- A missing aura branch must not acquire old defaults from alias repair.
    local sparse = assert(API(sender).MSUF_TryDecodeCompactString(Export(sender)))
    sparse.msuf6.auraClient = nil
    sparse.msuf6.payload.gf_party = { spellIndicators = { enabled = false, spec = "auto", specs = {} } }
    sparse.msuf6.payload.auras3.customDisplays = { shared = { items = {} }, perUnit = {
        target = { override = true, items = {
            { id = 1, enabled = false, spellIDs = sourceSpell },
            { id = 75, enabled = false, spellIDs = editedSpell },
        } },
    } }
    local sparseText = assert(API(sender).MSUF_EncodeCompactTableMSUF3(sparse))
    local sparseCanonical, sparseOther, sparseReturn = World("Mainline"), World("Forever"), World("Mainline")
    Import(sparseCanonical, sparseText)
    Import(sparseOther, sparseText, nil, true)
    Import(sparseReturn, Export(sparseOther))
    Equal(DB(sparseReturn).gf_party.auras, DB(sparseCanonical).gf_party.auras, "sparse legacy record gained default aura selections")
    assert(DB(sparseReturn).auras3.customDisplays.serial >= 75, "missing display serial ignored retained current-model IDs")
    assert(sparseReturn.core.MSUF_Auras3.MenuModel.AddCustomDisplay("target").id > 75,
        "missing display serial caused a duplicate ID after current-model return")
    for _, malformedSerial in ipairs({ "1e9999", "1e300", "nan", "-1e9999", "-4", "2.5" }) do
        sparse.msuf6.payload.auras3.customDisplays.serial = malformedSerial
        sparse.msuf6.payload.auras3.customDisplays.perUnit.target.items[3] = { id = "1e9999", enabled = false }
        local serialOther, serialReturn = World("Forever"), World("Mainline")
        Import(serialOther, assert(API(sender).MSUF_EncodeCompactTableMSUF3(sparse)), nil, true)
        Import(serialReturn, Export(serialOther))
        assert(DB(serialReturn).auras3.customDisplays.serial == 75, "malformed serial escaped finite integer repair")
        assert(serialReturn.core.MSUF_Auras3.MenuModel.AddCustomDisplay("target").id == 76,
            "malformed serial or ID corrupted the next display ID")
        assert(DB(serialReturn).auras3.customContainers.serial == nil, "display serial leaked into custom containers")
    end
    local defaultPlayerItems = DB(sparseReturn).auras3.customContainers.perUnit.player.items
    assert(defaultPlayerItems[4] and defaultPlayerItems[1] == nil, "missing player source inserted non-preset containers")

    for _, file in ipairs({ "hist_2026-05-27_msuf3_portable", "hist_2026-07-14_msuf3_raw_profile", "hist_2026-08-06_msuf3_full_schema1" }) do
        local text = C.ReadImportFixture(root, "tools/fixtures/profiles/imports/" .. file .. ".txt")
        local envelope = assert(API(sender).MSUF_TryDecodeCompactString(text))
        local profile = envelope.msuf6 and envelope.msuf6.payload or envelope.payload or envelope
        local auraKey = profile.auras3 and "auras3" or "auras2"
        local aura = profile[auraKey]
        local canonicalOriginal, flaggedOriginal = World("Mainline"), World("Mainline")
        Import(canonicalOriginal, text)
        Import(flaggedOriginal, text, nil, true)
        Equal(DB(flaggedOriginal), DB(canonicalOriginal), file .. " same-client flag changed canonical import")
        aura.perUnit.target.overrideBlacklist = true
        aura.perUnit.target.blacklist = { buffs = { spells = { [sourceSpell] = true } } }
        aura.shared.blacklist = { buffs = { spells = { [editedSpell] = true } } }
        aura.perUnit.player.overrideBlacklist = false
        aura.perUnit.focus.overrideBlacklist = nil
        aura._msufA3UnitLaneOwners_v1 = nil
        aura.shared.showWeaponEnchants = true
        aura.shared.filters = { enabled = false, buffs = { onlyMine = true }, debuffs = { nonPlayer = true } }
        aura.perUnit.focus.overrideFilters = false
        aura.perUnit.target.overrideFilters = true
        aura.perUnit.target.filters = { buffs = { enabled = false, onlyMine = false }, debuffs = { enabled = true } }
        aura.perUnit.target.overrideSharedLayout = true
        aura.perUnit.target.layoutShared = aura.perUnit.target.layoutShared or {}
        aura.perUnit.target.layoutShared.showBuffs = false
        aura.perUnit.target.layoutShared.showDebuffs = true
        aura.customContainers = { perUnit = { player = { items = {
            [1] = { name = "First player container", enabled = false, spellIDs = sourceSpell, auraType = "BUFF" },
            [2] = { name = "Second player container", enabled = true, spellIDs = editedSpell, auraType = "BUFF" },
            [4] = { enabled = false, spellIDs = sourceSpell, auraType = "BUFF" },
        } }, target = { items = { {
            name = "Preserved container", enabled = false, auraType = "DEBUFF", spellIDs = sourceSpell,
            customSpellIDs = editedSpell, prioritySpellIDs = sourceSpell .. "," .. editedSpell,
            filters = { enabled = true, onlyMine = false, hidePermanent = true },
            placed = { x = 918, size = 81, cooldownSize = 61 }, frame = { type = "glow", thickness = 27 },
        } } } } }
        aura.customDisplays = { serial = 0, shared = { items = { {
            id = 1, name = "Inherited display", enabled = true, auraType = "BUFF", spellIDs = editedSpell, onlyOwn = false,
            placed = { x = 817, size = 79 },
        } } }, perUnit = { target = { override = true, items = { {
            id = 2, name = "Owned display", enabled = false, auraType = "DEBUFF", spellIDs = sourceSpell, onlyOwn = true,
            placed = { x = 716, size = 77 },
        } } }, player = { override = false, items = {} } } }
        profile.gf_party.spellIndicators = profile.gf_party.spellIndicators or {}
        profile.gf_party.spellIndicators.enabled = true
        profile.gf_party.spellIndicators.spec = "multi"
        profile.gf_party.spellIndicators.multiSpecs = { HolyPriest = true, DisciplinePriest = false }
        profile.gf_party.spellIndicators.specs = { HolyPriest = {
            Renew = false,
            PrivateRule = { custom = true, spells = sourceSpell, onlyOwn = false, _msufCustomOnlyOwnExplicit = true, autoBlacklist = true,
                placed = { x = 615, size = 75 }, frame = { type = "glow", thickness = 29 } },
        } }
        profile.gf_party.ciSlotTL = "custom"
        profile.gf_party.ciCustomTL = { spells = editedSpell, filter = "HELPFUL", mode = "missing" }
        profile.gf_party.auras.buff.blacklist = { spells = { [sourceSpell] = true } }
        profile.gf_party.auras.enabled = false
        profile.gf_party.auras.externals.enabled = false
        profile.gf_party.auras.buff.filterToken = "Raid"
        profile.gf_party.auras.buff.blacklistCats = { SATED = true, DESERTER = false }
        profile.gf_party.auras.externals.autoBlacklistBuffs = false
        profile.gf_party.auras.blizzardTypes = { buffs = true, debuffs = false, dispels = true, externals = false, privateAuras = false }
        profile.gf_party.auras.blizzardDispelMode = "allDispellable"
        profile.gf_party.auras.debuff._filterMigV3 = nil
        profile.gf_party.auras.debuff.filterToken = nil
        profile.gf_party.auras.debuff.filterMode = "PLAYER"
        profile.gf_party.auras.debuff.spellFilter = "BLACKLIST"
        profile.gf_party.auras.debuff.spellList = { [sourceSpell] = true }
        profile.gf_raid.auras.debuff.blacklist = nil
        profile.gf_raid.auras.debuff.blacklistSpells = { [editedSpell] = true }
        local oldText = assert(API(sender).MSUF_EncodeCompactTableMSUF3(envelope))
        local canonical = World("Mainline")
        Import(canonical, oldText)

        for _, destination in ipairs({ "Forever", "Vanilla", "TBC", "Mists" }) do
            local firstHop = World(destination)
            Configure(firstHop, localSpell)
            Import(firstHop, oldText, nil, true)
            assert(List(firstHop)[localSpell] and not List(firstHop)[sourceSpell], file .. " first hop replaced " .. destination .. " rules")
            assert(DB(firstHop)[key].clients.Mainline.legacyRetail, file .. " missing " .. destination .. " archive")
        end

        local forever = World("Forever")
        Configure(forever, localSpell)
        Import(forever, oldText, nil, true)
        local archived = DB(forever)[key] and DB(forever)[key].clients.Mainline
        assert(archived and archived.legacyRetail, file .. " missing Retail archive")
        assert(H.Literal(archived[auraKey]) == H.Literal(aura), file .. " altered dormant Retail rules")
        assert(List(forever)[localSpell] and not List(forever)[sourceSpell], file .. " changed active Forever rules")
        forever = Reload(forever, "Forever")

        local retail = World("Mainline")
        local carriedExport = Export(forever)
        assert(API(forever).MSUF_TryDecodeCompactString(carriedExport).msuf6.auraClient == "Forever",
            file .. " carried archive export lost its source stamp")
        Import(retail, carriedExport, "Restored Retail")
        assert(List(retail)[sourceSpell] and not List(retail)[localSpell], file .. " lost Retail unit rules")
        assert(DB(retail).auras3.perUnit.player.blacklist.buffs.spells[editedSpell], file .. " lost inherited Retail rule")
        assert(DB(retail).gf_party.spellIndicators.enabled == true, file .. " lost Retail spell indicators")
        assert(DB(retail).gf_party.auras.buff.blacklist.spells[sourceSpell] == true, file .. " lost Retail group rules")
        assert(DB(retail).auras3.perUnit.focus.blacklist.buffs.spells[editedSpell], file .. " absent override lost inherited rule")
        assert(DB(retail).auras3.shared.showWeaponEnchants == true, file .. " lost weapon-enchant selection")
        assert(DB(retail).auras3.perUnit.focus.filters.buffs.enabled == false
            and DB(retail).auras3.perUnit.focus.filters.buffs.onlyMine == true
            and DB(retail).auras3.perUnit.focus.filters.debuffs.nonPlayer == true, file .. " lost inherited unit filters")
        assert(DB(retail).auras3.perUnit.target.filters.buffs.enabled == false
            and DB(retail).auras3.perUnit.target.filters.buffs.onlyMine == false, file .. " lost explicit per-unit filters")
        assert(DB(retail).auras3.perUnit.target.layoutShared.showBuffs == false
            and DB(retail).auras3.perUnit.target.layoutShared.showDebuffs == true, file .. " lost lane visibility selections")
        local container = DB(retail).auras3.customContainers.perUnit.target.items[1]
        assert(container.enabled == false and container.spellIDs == sourceSpell and container.customSpellIDs == editedSpell,
            file .. " lost custom container rules or explicit disabled state")
        assert(container.prioritySpellIDs == sourceSpell .. "," .. editedSpell and container.filters.onlyMine == false)
        local playerItems = DB(retail).auras3.customContainers.perUnit.player.items
        assert(playerItems[1].name == "First player container" and playerItems[2].name == "Second player container",
            file .. " shifted player custom-container indices")
        assert(playerItems[4].enabled == false and playerItems[4].spellIDs == sourceSpell,
            file .. " default migration re-enabled a disabled defensive preset")
        assert(DB(retail).auras3.customDisplays.serial >= 2, file .. " custom display sequence is below retained IDs")
        local displays = DB(retail).auras3.customDisplays.perUnit
        assert(displays.target.items[1].spellIDs == sourceSpell and displays.target.items[1].enabled == false)
        assert(displays.player.items[1].spellIDs == editedSpell and displays.focus.items[1].spellIDs == editedSpell,
            file .. " lost shared custom-display rules")
        local si = DB(retail).gf_party.spellIndicators
        assert(si.spec == "multi" and si.multiSpecs.HolyPriest == true and si.multiSpecs.DisciplinePriest == false)
        assert(si.specs.HolyPriest.Renew == false and si.specs.HolyPriest.PrivateRule.spells == sourceSpell
            and si.specs.HolyPriest.PrivateRule.onlyOwn == false and si.specs.HolyPriest.PrivateRule.autoBlacklist == true,
            file .. " lost spell indicator rules")
        assert(DB(retail).gf_party.auras.enabled == false and DB(retail).gf_party.auras.externals.enabled == false,
            file .. " legacy repair force-enabled an explicit false switch")
        assert(DB(retail).gf_raid.auras.debuff.blacklist.spells[editedSpell], file .. " lost legacy blacklistSpells fallback")
        assert(DB(retail).gf_party.auras.buff.filterToken == "Raid" and DB(retail).gf_party.auras.buff.blacklistCats.SATED == true
            and DB(retail).gf_party.auras.buff.blacklistCats.DESERTER == false, file .. " lost group filter/category selections")
        assert(DB(retail).gf_party.auras.externals.autoBlacklistBuffs == false, file .. " lost explicit auto-blacklist choice")
        assert(DB(retail).gf_party.auras.blizzardTypes.buffs == true and DB(retail).gf_party.auras.blizzardTypes.debuffs == false
            and DB(retail).gf_party.auras.blizzardTypes.privateAuras == false, file .. " lost native aura-type choices")
        assert(DB(retail).gf_party.auras.debuff.filterToken == "Player"
            and DB(retail).gf_party.auras.debuff.blacklist.spells[sourceSpell], file .. " lost legacy group filter/spell-list migration")
        assert(DB(retail).gf_party.ciSlotTL == "custom" and DB(retail).gf_party.ciCustomTL.spells == editedSpell,
            file .. " lost corner indicator rules")
        Equal(Geometry(DB(retail)), Geometry(DB(canonical)), file .. " archived return bypassed canonical geometry/font migration")
        local newDisplay = retail.core.MSUF_Auras3.MenuModel.AddCustomDisplay("target")
        assert(newDisplay.id > 2, file .. " adding a display reused an imported ID")

        local activeRetail = World("Mainline")
        Configure(activeRetail, localSpell)
        Import(activeRetail, carriedExport)
        assert(List(activeRetail)[sourceSpell] and not List(activeRetail)[localSpell], file .. " active return masked archive")

        local newForever = World("Forever")
        Import(newForever, oldText, "New legacy Retail profile", true)
        assert(DB(newForever)[key].clients.Mainline.legacyRetail, file .. " new-profile import lost Retail archive")

        local reviewForever = World("Forever")
        local review = assert(reviewForever.core.ProfileWorkbench.ReviewImport(oldText, true))
        assert(not DB(reviewForever)[key], file .. " review changed the profile before applying")
        assert(reviewForever.core.ProfileWorkbench.CommitReview(review))
        assert(DB(reviewForever)[key].clients.Mainline.legacyRetail, file .. " selective review lost Retail archive")

        local direct = World("Mainline")
        assert(API(direct).MSUF_ImportFromString(oldText, true))
        Equal(DB(direct), DB(canonical), file .. " same-client flag changed the canonical result")
    end
end
print("Beta 6 synchronous aura round trips: " .. source .. " same client and four cross-client cases passed")
if source == "Mainline" then print("Three historical Retail formats: direct, new profile, selective review and Forever reload/export/return passed") end
