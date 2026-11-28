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
-- Cross-client aura layout: on a full import from another client the aura
-- layout follows the profile; switches, filters, lists, corner indicators and
-- model markers stay with the receiving client.
do
    local GROUPS = { "gf_party", "gf_raid", "gf_mythicraid", "gf_priority" }
    local GROUP_FIELDS = { "auras", "privateAuras", "spellIndicators", "ciCustomTL", "ciCustomTR", "ciCustomBL", "ciCustomBR",
        "ciCustomC", "ciSlotTL", "ciSlotTR", "ciSlotBL", "ciSlotBR", "ciSlotC" }
    local GROUP_OWNER = { auras = "root", privateAuras = "private", spellIndicators = "spell" }
    local SWITCHES = { "enabled", "showPlayer", "showTarget", "showFocus", "showPet", "showBoss", "showArena" }
    local POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
    local function Set(list)
        local out = {}
        for _, name in ipairs(list) do out[name] = true end
        return out
    end
    -- The keys of each owner that stay with the receiving client. Every other
    -- stored key of these owners must follow the import.
    local KEPT = {
        shared = Set({ "showBuffs", "showDebuffs", "filters", "blacklist", "hideBlizzardBuffFrame", "hideBlizzardDebuffFrame",
            "showInEditMode", "arenaEditTogether", "bossEditTogether", "showWeaponEnchants" }),
        unit = Set({ "overrideFilters", "overrideBlacklist", "filters", "blacklist" }),
        layout = {},
        layoutShared = Set({ "showBuffs", "showDebuffs" }),
        appearance = {},
        root = Set({ "enabled", "renderer", "blizzardTypes", "blizzardDispelMode", "profileModelRevision" }),
        lane = Set({ "enabled", "filterToken", "blacklist", "blacklistCats", "autoBlacklistBuffs", "trackedOnlyOwn",
            "hidePermanent", "_filterMigV3" }),
        private = Set({ "enabled" }),
        spell = Set({ "enabled", "spec", "specs", "multiSpecs", "_autoSeededSpecs", "_autoSeedVersion" }),
    }
    local CHILD = {
        shared = { appearanceIconShapes = "appearance", appearanceIconStyles = "appearance" },
        unit = { layout = "layout", layoutShared = "layoutShared" },
        root = { buff = "lane", debuff = "lane", externals = "lane" },
    }
    local EMPTY = {}
    local function Lit(value)
        if value == nil then return "nil" end
        return H.Literal(value)
    end
    local function Union(...)
        local keys = {}
        for i = 1, select("#", ...) do
            local t = select(i, ...)
            if type(t) == "table" then for k in pairs(t) do keys[k] = true end end
        end
        return keys
    end
    local function Expect(label, path, got, want, why)
        if Lit(got) ~= Lit(want) then
            error(("%s: %s %s, but is %s instead of %s"):format(label, path, why, Lit(got), Lit(want)), 0)
        end
    end
    -- Leaf by leaf. keepLocal names the leaves the receiver kept on purpose; it
    -- applies only where the receiver had the parent table (an added table
    -- arrives whole).
    local function Follow(label, path, key, got, sent, before, keepLocal, distinct)
        if type(got) == "table" and type(sent) == "table" then
            if type(before) ~= "table" then keepLocal = nil end
            for k in pairs(Union(got, sent, keepLocal and before)) do
                Follow(label, path .. "." .. tostring(k), k, got[k], sent[k], type(before) == "table" and before[k] or nil,
                    keepLocal, distinct)
            end
            return
        end
        local want, whose = sent, "the import's"
        if keepLocal and keepLocal(key) then want, whose = before, "the receiver's" end
        if Lit(got) ~= Lit(want) then
            error(("%s: %s is %s; %s value is %s (receiver had %s). Classify the key: follow it in AuraTransfer.FollowLayout"
                .. " or name it in KEPT in this test."):format(label, path, Lit(got), whose, Lit(want),
                Lit(before)), 0)
        end
        if distinct and want == sent and before ~= nil and Lit(sent) == Lit(before) then
            error(label .. ": " .. path .. " has no distinct sender value, so the case cannot tell follow from keep", 0)
        end
    end
    local function CheckOwner(label, path, kind, got, before, sent, opts)
        if type(sent) ~= "table" then return Expect(label, path, got, before, "is not in the import and must stay") end
        if type(got) ~= "table" then error(label .. ": " .. path .. " is missing", 0) end
        local keepLocal = type(before) == "table" and opts.keepLocal or nil
        before = type(before) == "table" and before or EMPTY
        for key in pairs(Union(got, before, sent)) do
            local p, child = path .. "." .. tostring(key), CHILD[kind] and CHILD[kind][key]
            if KEPT[kind][key] or (kind == "appearance" and sent[key] == nil) then
                Expect(label, p, got[key], before[key], "stays with the receiving client")
            elseif child then
                CheckOwner(label, p, child, got[key], before[key], sent[key], opts)
            else
                local beforeValue = before[key]
                Follow(label, p, key, got[key], sent[key], beforeValue, keepLocal, opts.distinct)
            end
        end
    end
    -- got/before/sent are profiles (or sections); opts.managed are the units the receiver manages.
    local function CheckProfile(label, got, before, sent, opts)
        local g, b, s = got.auras3, before.auras3, sent.auras3
        for key in pairs(Union(g, b)) do
            if key ~= "shared" and key ~= "perUnit" then
                Expect(label, "auras3." .. tostring(key), g[key], b[key], "is a switch, rule or marker and stays")
            end
        end
        CheckOwner(label, "auras3.shared", "shared", g.shared, b.shared, s.shared, opts)
        for unit in pairs(Union(g.perUnit, b.perUnit, s.perUnit)) do
            local p, own, old = "auras3.perUnit." .. unit, g.perUnit[unit], b.perUnit[unit]
            if type(s.perUnit[unit]) ~= "table" or (old == nil and not opts.managed[unit]) then
                Expect(label, p, own, old, "is a unit the import does not own")
            else
                CheckOwner(label, p, "unit", own, old, s.perUnit[unit], opts)
            end
        end
        for _, scope in ipairs(GROUPS) do
            local gs, bs, ss = got[scope] or EMPTY, before[scope] or EMPTY, sent[scope] or EMPTY
            for _, field in ipairs(GROUP_FIELDS) do
                local p, kind = scope .. "." .. field, GROUP_OWNER[field]
                if kind and type(ss.auras) == "table" then
                    CheckOwner(label, p, kind, gs[field], bs[field], ss[field], opts)
                else
                    Expect(label, p, gs[field], bs[field], "stays with the receiving client")
                end
            end
        end
    end
    local function AuraSection(profile)
        local out = { auras3 = profile.auras3 }
        for _, scope in ipairs(GROUPS) do
            local conf, fields = profile[scope], {}
            for _, field in ipairs(GROUP_FIELDS) do fields[field] = conf and conf[field] end
            out[scope] = fields
        end
        return out
    end
    local function Differences(a, b, path, out)
        if type(a) == "table" and type(b) == "table" then
            for k in pairs(Union(a, b)) do Differences(a[k], b[k], path .. "." .. tostring(k), out) end
        elseif Lit(a) ~= Lit(b) then
            out[#out + 1] = path .. " = " .. Lit(a) .. " / " .. Lit(b)
        end
        return out
    end

    -- A valid alternative for every stored string: lower-case key pattern, choices.
    local CHOICES = {
        { "anchor$", POINTS }, { "strata$", { "AUTO", "HIGH" } }, { "growthx$", { "RIGHT", "LEFT" } },
        { "growthy$", { "DOWN", "UP" } }, { "^rowwrap$", { "DOWN", "UP" } }, { "sortmethod$", { "DEFAULT", "NAME" } },
        { "durationbardisplay$", { "BAR_ONLY", "OVERLAY" } }, { "durationbarposition$", { "BOTTOM", "TOP" } },
        { "durationbardirection$", { "REMAINING", "ELAPSED" } }, { "bordermode$", { "OFF", "SYMBOL" } },
        { "stealablestyle$", { "BORDER_ICON", "BORDER" } }, { "frameeffecttype$", { "none", "border" } },
        { "^styleborderstyle$", { "SOLID", "GLOW" } }, { "^blizzardorganizationtype$", { "default", "byType" } },
        { "^blizzarddispelmode$", { "allDispellable", "playerDispellable" } }, { "^renderer$", { "NATIVE_12_1", "CUSTOM" } },
        { "^spec$", { "auto", "multi" } }, { "^filtertoken$", { "ALL", "Raid" } },
    }
    local function Choice(kind, key, current)
        local k, domain = tostring(key):lower(), nil
        if kind == "shape" then
            domain = { "RECTANGLE", "CIRCLE" }
        elseif k == "growth" then
            domain = kind == "lane" and { "RIGHTDOWN", "LEFTDOWN", "RIGHTUP", "LEFTUP" } or { "RIGHT", "LEFT" }
        elseif k == "direction" then
            domain = { "LEFT", "RIGHT" }
        else
            for _, entry in ipairs(CHOICES) do
                if k:find(entry[1]) then domain = entry[2] break end
            end
        end
        if not domain then error("no valid alternative for aura key " .. k .. " (" .. kind .. "): add one to CHOICES", 0) end
        for i, value in ipairs(domain) do
            if value == current then return domain[i % #domain + 1] end
        end
        return domain[1]
    end
    local RULE_TABLES = Set({ "filters", "blacklist", "blacklistCats", "blizzardTypes", "specs", "multiSpecs" })
    local function ChildKind(kind, key)
        if key == "appearanceIconShapes" then return "shape" end
        if kind == "root" and (key == "buff" or key == "debuff" or key == "externals") then return "lane" end
        if tostring(key):lower():find("color$") then return "color" end
        return kind
    end
    -- Give every stored value a valid value that differs from the receiver's.
    -- Rule tables only flip their switches; markers keep their meaning.
    local function Mutate(kind, own, recv, rule)
        for key, value in pairs(own) do
            local current
            if type(recv) == "table" then current = recv[key] end
            local valueType = type(value)
            if type(key) == "string" and (key:sub(1, 1) == "_" or key == "profileModelRevision") then
                -- model marker
            elseif valueType == "table" then
                Mutate(ChildKind(kind, key), value, current, rule or RULE_TABLES[key])
            elseif valueType == "boolean" then
                local base = value
                if type(current) == "boolean" then base = current end
                own[key] = not base
            elseif rule then
                -- rule values other than switches stay as they are
            elseif valueType == "number" then
                local base = type(current) == "number" and current or value
                if kind == "color" then
                    own[key] = base >= 0.5 and base - 0.25 or base + 0.25
                elseif tostring(key):lower():find("alpha", 1, true) then
                    own[key] = base == 0.5 and 0.25 or 0.5
                else
                    own[key] = base + 1
                end
            else
                own[key] = Choice(kind, key, type(current) == "string" and current or value)
            end
        end
    end
    local function NoNewErrors(label, w, count)
        -- Plain imports already raise unrelated frame errors in this harness
        -- (text runtime, class power); only aura, group or profile code counts.
        for index, caught in ipairs(C.Errors(w)) do
            local text = (tostring(caught.file) .. " " .. tostring(caught.detail)):lower()
            if index > count and (text:find("aura", 1, true) or text:find("group", 1, true) or text:find("profile", 1, true)) then
                error(label .. ": the import raised " .. tostring(caught.context) .. ": " .. tostring(caught.detail), 0)
            end
        end
    end
    local function Managed(w) return w.core.MSUF_Auras3.LaneKeySchema.MANAGED_UNITS end
    local function IsPosition(key)
        key = tostring(key):lower()
        return key:find("offset", 1, true) or key:find("anchor", 1, true) or key == "x" or key == "y"
            or key:find("position", 1, true)
    end

    -- No default profile stores the flat style keys: the sender sets all of them,
    -- the receiver some. showWeaponEnchants selects auras and stays.
    local STYLE = { iconShape = "CIRCLE", styleBorderEnabled = true, styleBorderStyle = "GLOW", styleBorderThickness = 3,
        styleBorderColor = { 1, 0, 0, 1 }, styleShadowEnabled = true, styleShadowSize = 6, styleShadowColor = { 0, 0, 1, 0.5 } }
    local function ReceiverStyle(w)
        local shared = DB(w).auras3.shared
        shared.iconShape, shared.styleBorderThickness, shared.styleShadowColor = "RECTANGLE", 2, { 0.2, 0.2, 0.2, 0.9 }
        shared.showWeaponEnchants = false
    end

    -- A: every stored layout value differs from the receiver's; the receiver has its own rules.
    local receiver = World(other)
    Configure(receiver, localSpell)
    DB(receiver).gf_party.auras.buff.blacklist.spells[localSpell] = true
    ReceiverStyle(receiver)
    local layoutSender = World(source)
    local sdb, rdb = DB(layoutSender), DB(receiver)
    for _, flag in ipairs(SWITCHES) do sdb.auras3[flag] = not rdb.auras3[flag] end
    Mutate("shared", sdb.auras3.shared, rdb.auras3.shared)
    for name, value in pairs(STYLE) do sdb.auras3.shared[name] = C.Copy(value) end
    sdb.auras3.shared.showWeaponEnchants = true
    for unit, conf in pairs(sdb.auras3.perUnit) do Mutate("unit", conf, rdb.auras3.perUnit[unit]) end
    for _, scope in ipairs(GROUPS) do
        local conf, recv = sdb[scope], rdb[scope] or EMPTY
        if type(conf) == "table" and type(conf.auras) == "table" then
            Mutate("root", conf.auras, recv.auras)
            Mutate("private", conf.privateAuras, recv.privateAuras)
            Mutate("spell", conf.spellIndicators, recv.spellIndicators)
            for _, lane in ipairs({ "buff", "debuff", "externals" }) do conf.auras[lane].blacklist.spells[sourceSpell] = true end
            conf.ciSlotTL, conf.ciSlotBR, conf.ciCustomBR = "none", "custom", { spells = sourceSpell }
        end
    end
    Configure(layoutSender, sourceSpell)
    local layoutText = Export(layoutSender)
    local sent = AuraSection(assert(API(layoutSender).MSUF_TryDecodeCompactString(layoutText)).msuf6.payload)
    local managed = Managed(receiver)
    local before, errorCount = C.Copy(rdb), #C.Errors(receiver)
    assert(API(receiver).MSUF_ImportFromString(layoutText))
    NoNewErrors("layout import", receiver, errorCount)
    local style = DB(receiver).auras3.shared
    for name, value in pairs(STYLE) do
        assert(Lit(style[name]) == Lit(value), "portable style key " .. name .. " did not follow: " .. Lit(style[name]))
    end
    assert(style.showWeaponEnchants == false, "showWeaponEnchants did not stay with the receiving client")
    CheckProfile("active layout import", DB(receiver), before, sent, { managed = managed, distinct = true })
    assert(List(receiver)[localSpell] and not List(receiver)[sourceSpell], "layout import replaced the receiver's unit rules")
    for _, scope in ipairs(GROUPS) do
        local conf = DB(receiver)[scope]
        if conf and conf.auras then
            assert(Lit(conf.auras.blizzardTypes) == Lit(before[scope].auras.blizzardTypes), scope .. " blizzardTypes changed")
            assert(conf.auras.renderer == before[scope].auras.renderer, scope .. " renderer changed")
        end
    end
    assert(Lit(DB(receiver)[key].clients[source].auras3) == Lit(sent.auras3), "carried unit section is not verbatim")
    for _, scope in ipairs(GROUPS) do
        for _, field in ipairs(GROUP_FIELDS) do
            assert(Lit(DB(receiver)[key].clients[source][scope] and DB(receiver)[key].clients[source][scope][field])
                == Lit(sent[scope][field]), "carried " .. scope .. "." .. field .. " is not verbatim")
        end
    end

    -- I: the staged job and the synchronous API stage the same profile.
    local staged = World(other)
    Configure(staged, localSpell)
    DB(staged).gf_party.auras.buff.blacklist.spells[localSpell] = true
    ReceiverStyle(staged)
    ImportJob(staged, layoutText)
    assert(Lit(DB(staged)) == Lit(DB(receiver)), "fast and synchronous layout imports differ")

    -- B: a new profile on the other client follows the layout without the sender's rules.
    ImportJob(staged, layoutText, "Layout")
    local fresh = DB(staged)
    CheckProfile("new profile", fresh, fresh, sent, { managed = managed })
    assert(not List(staged)[sourceSpell] and not fresh.gf_party.auras.buff.blacklist.spells[sourceSpell],
        "new profile compiled the sender's rules")
    assert(fresh.gf_party.ciSlotTL ~= "none" and fresh.gf_party.ciCustomBR == nil, "new profile took the sender's corner indicators")

    -- C: an unedited round trip returns the sender's aura data exactly.
    local back = World(source)
    ImportJob(back, Export(staged), "Back")
    local diff = Differences(AuraSection(DB(back)), sent, "", {})
    assert(#diff == 0, "round trip changed aura data: " .. table.concat(diff, "; "))

    -- D: a layout edit on the other client returns, a rule edit there does not.
    fresh.auras3.shared.iconSize = sent.auras3.shared.iconSize + 5
    fresh.gf_party.auras.buff.x = sent.gf_party.auras.buff.x + 5
    Configure(staged, editedSpell)
    fresh.gf_party.auras.buff.blacklist.spells[editedSpell] = true
    ImportJob(back, Export(staged), "Edited")
    assert(DB(back).auras3.shared.iconSize == sent.auras3.shared.iconSize + 5, "unit layout edit was lost on return")
    assert(DB(back).gf_party.auras.buff.x == sent.gf_party.auras.buff.x + 5, "group layout edit was lost on return")
    assert(List(back)[sourceSpell] and not List(back)[editedSpell], "unit rules of the other client came back")
    local spells = DB(back).gf_party.auras.buff.blacklist.spells
    assert(spells[sourceSpell] and not spells[editedSpell], "group rules of the other client came back")

    -- E: a section outside the current models is not followed and still imports.
    local plain = World(other)
    Configure(plain, localSpell)
    local plainBefore, plainErrors = C.Copy(AuraSection(DB(plain))), #C.Errors(plain)
    local outside = assert(API(plain).MSUF_TryDecodeCompactString(layoutText))
    outside.msuf6.payload.auras3.profileModelRevision = nil
    for _, scope in ipairs(GROUPS) do
        local conf = outside.msuf6.payload[scope]
        if conf and conf.auras then conf.auras.profileModelRevision = nil end
    end
    assert(API(plain).MSUF_ImportFromString(API(plain).MSUF_EncodeCompactTableMSUF3(outside)))
    NoNewErrors("outside-model import", plain, plainErrors)
    diff = Differences(AuraSection(DB(plain)), plainBefore, "", {})
    assert(#diff == 0, "a section outside the current models was followed: " .. table.concat(diff, "; "))

    -- F: a value of the wrong type never replaces a valid one; the copy is normalized first.
    local wrong = assert(API(plain).MSUF_TryDecodeCompactString(layoutText))
    local payload = wrong.msuf6.payload
    payload.auras3.shared.iconSize = "large"
    payload.auras3.shared.buffFrameEffectColor = 7
    payload.auras3.shared.iconZoom = 500
    payload.auras3.perUnit.target.layout.buffAnchor = 5
    payload.auras3.perUnit.target.layout.buffGroupOffsetX = "41"
    payload.auras3.perUnit.target.layout.debuffAnchor = "topright"
    payload.gf_party.auras.buff.x = "left"
    payload.gf_party.privateAuras.anchor = 3
    -- A flag the import leaves out is repaired from its layout values before it follows.
    payload.auras3.perUnit.target.overrideLayout = nil
    DB(plain).auras3.perUnit.target.overrideLayout = false
    -- Absence follows: keys the import does not carry leave the receiver too.
    assert(payload.auras3.shared.buffStrata == nil and payload.gf_party.auras.buff.behindBar == nil,
        "the absence check needs keys the import does not carry")
    DB(plain).auras3.shared.buffStrata = "HIGH"
    DB(plain).gf_party.auras.buff.behindBar = true
    local kept = C.Copy(AuraSection(DB(plain)))
    assert(API(plain).MSUF_ImportFromString(API(plain).MSUF_EncodeCompactTableMSUF3(wrong)))
    NoNewErrors("wrong-type import", plain, plainErrors)
    local shared, target = DB(plain).auras3.shared, DB(plain).auras3.perUnit.target.layout
    assert(shared.iconSize == kept.auras3.shared.iconSize, "a string replaced a stored icon size")
    assert(Lit(shared.buffFrameEffectColor) == Lit(kept.auras3.shared.buffFrameEffectColor),
        "a number replaced a stored colour")
    assert(target.buffAnchor == kept.auras3.perUnit.target.layout.buffAnchor, "a number replaced a stored anchor")
    assert(DB(plain).gf_party.auras.buff.x == kept.gf_party.auras.buff.x, "a string replaced a group offset")
    assert(DB(plain).gf_party.privateAuras.anchor == kept.gf_party.privateAuras.anchor, "a number replaced a private aura anchor")
    assert(shared.iconZoom == 200 and target.buffGroupOffsetX == 41 and target.debuffAnchor == "TOPRIGHT",
        "the followed layout was not normalized like a same-client import")
    assert(DB(plain).auras3.perUnit.target.overrideLayout == true, "a missing override flag was not repaired before it followed")
    assert(shared.buffStrata == nil, "a unit layout key the import does not carry stayed")
    assert(DB(plain).gf_party.auras.buff.behindBar == nil, "a group layout key the import does not carry stayed")
    assert(DB(plain)[key].clients[source].auras3.perUnit.target.layout.debuffAnchor == "topright",
        "following the layout changed the carried section")

    -- H: an inactive profile stores the followed layout; the active one stays.
    local activeBefore = C.Copy(AuraSection(DB(plain)))
    assert(API(plain).MSUF_CreateProfile("Inactive"))
    assert(API(plain).MSUF_ImportExternal(layoutText, "Inactive"))
    NoNewErrors("inactive import", plain, plainErrors)
    diff = Differences(AuraSection(DB(plain)), activeBefore, "", {})
    assert(#diff == 0, "inactive import changed the active profile: " .. table.concat(diff, "; "))
    local stored = plain.core.ProfileNormalize.ResolveStoredProfile(plain.env.MSUF_GlobalDB.profiles.Inactive)
    CheckProfile("inactive profile", stored, stored, sent, { managed = managed })

    -- G: the workbench review follows the layout too; preserved positions stay local.
    local reviewed = World(other)
    Configure(reviewed, localSpell)
    local reviewBefore, reviewErrors = C.Copy(DB(reviewed)), #C.Errors(reviewed)
    local bench = reviewed.core.ProfileWorkbench
    local positions = assert(bench.ReviewImport(layoutText))
    bench.Preserve(positions, "positions", true)
    assert(bench.CommitReview(positions))
    CheckProfile("review keeping positions", DB(reviewed), reviewBefore, sent, { managed = managed, keepLocal = IsPosition })
    local full = assert(bench.ReviewImport(layoutText))
    assert(bench.CommitReview(full))
    NoNewErrors("review import", reviewed, reviewErrors)
    CheckProfile("review", DB(reviewed), reviewBefore, sent, { managed = managed })
end
print("profile_aura_roundtrip_smoke: " .. source .. " same client and four cross-client round trips passed")
