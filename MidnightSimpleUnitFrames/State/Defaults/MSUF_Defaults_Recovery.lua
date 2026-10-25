-- Profile quarantine, immutable backup histories and account rollback recovery.
local _, MSUF = ...
local Parts = MSUF.DefaultsSchemaParts
local ClearScratch = Parts.ClearScratch
local CountTables = Parts.CountTables
local Plain = Parts.Plain
local Schema = Parts.Schema
local entries = Parts.entries
local scratchLists = Parts.scratchLists
local scratchPath = Parts.scratchPath
local scratchRefs = Parts.scratchRefs
local sparseToken = Parts.sparseToken
local sparseV2Marker = Parts.sparseV2Marker
local sparseV3 = Parts.sparseV3
-- Capture stored newer data at the shared decoder entry, before either the
-- profile translator or the defaults normalizer can change it. Private copies
-- have no stored owner and must not overwrite the account's original backup.
local function CopyNewerProfile(value, seen)
    if MSUF.Util.IsSecret(value) or type(value) ~= "table" then return value end
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[CopyNewerProfile(key, seen)] = CopyNewerProfile(child, seen)
    end
    return copy
end

do
    local rejected, working = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
    local function Literal(value, path)
        if MSUF.Util.IsSecret(value) then return nil end
        local kind = type(value)
        if kind == "string" then return string.format("%q", value) end
        if kind == "boolean" then return tostring(value) end
        if kind == "number" and value == value and value ~= math.huge and value ~= -math.huge then
            return string.format("%.17g", value)
        end
        if not Plain(value) or path[value] then return nil end
        path[value] = true
        local keys, parts = {}, {}
        for key in pairs(value) do
            if MSUF.Util.IsSecret(key) or (type(key) ~= "string" and type(key) ~= "number") then return nil end
            keys[#keys + 1] = key
        end
        table.sort(keys, function(a, b)
            if type(a) ~= type(b) then return type(a) < type(b) end
            return a < b
        end)
        for _, key in ipairs(keys) do
            local name, child = Literal(key, path), Literal(value[key], path)
            if not name or not child then return nil end
            parts[#parts + 1] = "[" .. name .. "]=" .. child
        end
        path[value] = nil
        return "{" .. table.concat(parts, ",") .. "}"
    end
    local function ContentHash(text)
        local a, b = 5381, 0
        for i = 1, #text do
            local byte = text:byte(i)
            a = (a * 33 + byte) % 4294967296
            b = (b * 65599 + byte) % 4294967296
        end
        return string.format("%08x%08x", a, b)
    end
    local recoveryLimit = 2 * 1024 * 1024
    local recoveryFields = { "_newerRevisionBackups", "_rejectedProfileBackups" }
    local function IndexedHistory(bucket)
        if type(bucket.entries) ~= "table" or type(bucket.order) ~= "table" then return false end
        local indexed = {}
        for _, key in ipairs(bucket.order) do
            if indexed[key] or type(bucket.entries[key]) ~= "table" then return false end
            indexed[key] = true
        end
        for key in pairs(bucket.entries) do if not indexed[key] then return false end end
        return true
    end
    local function Ordinal(value)
        if MSUF.Util.IsSecret(value) or type(value) ~= "number" then return 0 end
        if value ~= value or value < 0 or value == math.huge then return 0 end
        return value
    end
    local function RecoveryRows(store)
        local rows = {}
        local function Add(owner, name, field, archived)
            if type(owner) ~= "table" then return end
            local bucket = owner[name]
            if bucket == nil then return end
            if type(bucket) ~= "table" or not IndexedHistory(bucket) then
                rows[#rows + 1] = { owner = owner, name = name, bucket = bucket, field = field, archived = archived,
                    legacy = true, key = "legacy:" .. field .. ":" .. tostring(name),
                    entry = { data = type(bucket) == "table" and bucket.data or bucket } }
                return
            end
            for index, key in ipairs(bucket.order) do
                rows[#rows + 1] = { owner = owner, name = name, bucket = bucket, key = key,
                    entry = bucket.entries[key], field = field, archived = archived, index = index }
            end
        end
        for _, field in ipairs(recoveryFields) do
            if type(store[field]) == "table" then
                for name in pairs(store[field]) do Add(store[field], name, field) end
            else Add(store, field, field) end
        end
        local archive = store._profileRecoveryArchive
        if type(archive) == "table" then
            for field, saved in pairs(archive) do
                if type(saved) == "table" then
                    for id in pairs(saved) do Add(saved, id, tostring(field), true) end
                else Add(archive, field, tostring(field), true) end
            end
        else Add(store, "_profileRecoveryArchive", "archive", true) end
        table.sort(rows, function(a, b)
            local x, y = Ordinal(a.entry.sequence), Ordinal(b.entry.sequence)
            if x ~= y then return x < y end
            local ai = type(a.bucket) == "table" and Ordinal(a.bucket.identity) or 0
            local bi = type(b.bucket) == "table" and Ordinal(b.bucket.identity) or 0
            if ai ~= bi then return ai < bi end
            if a.bucket == b.bucket then return (a.index or 0) < (b.index or 0) end
            return a.field .. tostring(a.name) .. tostring(a.key) < b.field .. tostring(b.name) .. tostring(b.key)
        end)
        return rows
    end
    local function RecoveryBytes(store)
        local view = {}
        for _, field in ipairs(recoveryFields) do view[field] = store[field] end
        view._profileRecoveryArchive = store._profileRecoveryArchive
        local literal = Literal(view, {})
        return literal and #literal or math.huge
    end
    local function RemoveRecovery(row)
        local bucket = row.bucket
        if row.legacy then row.owner[row.name] = nil return end
        bucket.entries[row.key] = nil
        for i = #bucket.order, 1, -1 do
            if bucket.order[i] == row.key then table.remove(bucket.order, i) end
        end
        local latest = bucket.entries[bucket.order[#bucket.order]]
        if latest then bucket.revision, bucket.data = latest.revision, latest.data
        else row.owner[row.name] = nil end
    end
    local function BoundRecovery(store)
        local rows = RecoveryRows(store)
        local bytes = RecoveryBytes(store)
        for _, row in ipairs(rows) do
            if bytes <= recoveryLimit then break end
            RemoveRecovery(row)
            bytes = RecoveryBytes(store)
        end
        -- Empty archived identities must not accumulate after their last eviction.
        local function RemoveEmpty(owner)
            for name, bucket in pairs(type(owner) == "table" and owner or {}) do
                if type(bucket) == "table" and type(bucket.entries) == "table" and next(bucket.entries) == nil then owner[name] = nil end
            end
        end
        for _, field in ipairs(recoveryFields) do RemoveEmpty(store[field]) end
        local archive = store._profileRecoveryArchive
        if type(archive) == "table" then
            for field, owner in pairs(archive) do
                RemoveEmpty(owner)
                if type(owner) == "table" and next(owner) == nil then archive[field] = nil end
            end
            if next(archive) == nil then store._profileRecoveryArchive = nil end
        end
        return RecoveryBytes(store)
    end
    local function Insert(bucket, profile, revision, store)
        local literal = Literal(profile, {})
        if not literal or #literal * 2 + 1024 > recoveryLimit then return false end
        local hash = ContentHash(literal)
        local base = tostring(bucket.identity) .. ":" .. tostring(revision) .. ":" .. hash
        local key, collision = base, 0
        while bucket.entries[key] do
            if Literal(bucket.entries[key].data, {}) == literal then return false, key end
            collision = collision + 1
            key = base .. ":" .. collision
        end
        local entry = { revision = revision, hash = hash, data = CopyNewerProfile(profile, {}) }
        store._profileRecoverySequence = Ordinal(store._profileRecoverySequence) + 1
        entry.sequence = store._profileRecoverySequence
        bucket.entries[key] = entry
        bucket.order[#bucket.order + 1] = key
        if #bucket.order > 3 then bucket.entries[table.remove(bucket.order, 1)] = nil end
        -- Compatibility view of the latest snapshot; immutable entries own the data.
        bucket.revision, bucket.data = entry.revision, entry.data
        return true, key
    end
    local function Identity(store, name)
        local ids = store._profileRecoveryIDs
        if type(ids) ~= "table" then
            ids = {}
            store._profileRecoveryIDs = ids
        end
        if ids[name] == nil then
            store._profileRecoveryIdentity = (tonumber(store._profileRecoveryIdentity) or 0) + 1
            ids[name] = store._profileRecoveryIdentity
        end
        return ids[name]
    end
    local function RecoveryBucket(store, field, name)
        local backups = store[field]
        if type(backups) ~= "table" then
            backups = {}
            store[field] = backups
        end
        local bucket = backups[name]
        if type(bucket) ~= "table" or type(bucket.entries) ~= "table" or type(bucket.order) ~= "table" or bucket.identity == nil then
            local legacy = bucket
            bucket = { identity = Identity(store, name), entries = {}, order = {} }
            backups[name] = bucket
            if type(legacy) == "table" and type(legacy.data) == "table" then Insert(bucket, legacy.data, legacy.revision, store) end
        end
        return bucket
    end
    local function Save(store, field, name, profile)
        local bucket = RecoveryBucket(store, field, name)
        local saved, key = Insert(bucket, profile, profile._msufDefaultsRevision, store)
        BoundRecovery(store)
        return saved, store[field][name] == bucket and IndexedHistory(bucket) and key ~= nil and bucket.entries[key] ~= nil
    end
    local refusedNotices = setmetatable({}, { __mode = "k" })
    local function SaveNamed(store, field, name, profile, notice)
        local saved, retained = Save(store, field, name, profile)
        if notice and retained and saved then
            print("|cffffd700MSUF:|r " .. string.format(MSUF.Translate(
                "Profile '%s' uses a newer MSUF revision (%s). An untouched backup was saved."),
                name, tostring(profile._msufDefaultsRevision)))
        elseif notice and not retained and not refusedNotices[profile] then
            refusedNotices[profile] = true
            print("|cffffd700MSUF:|r " .. string.format(MSUF.Translate(
                "Profile '%s' could not be backed up. Its original is unchanged; this temporary session copy will not be saved."), name))
        end
        return retained
    end
    local function SaveOwned(profile, field, notice)
        local store = MSUF_GlobalDB
        if type(store) ~= "table" then return true end
        local found, retained = false, true
        if type(store.profiles) == "table" then
            for name, stored in pairs(store.profiles) do
                if stored == profile then
                    if not SaveNamed(store, field, name, profile, notice) then retained = false end
                    found = true
                end
            end
        end
        if found then return retained end
        -- Startup may normalize a copy before adding its selected saved source.
        local legacy = MSUF.FirstLoad6.GetLegacyProfileDB()
        local charKey = MSUF.Require("MSUF_GetCharKey", "State/Defaults/MSUF_Defaults_Schema.lua")()
        local name, source = MSUF.ResolveStartupProfile(store, legacy, charKey)
        if not Plain(source) or MSUF.Util.IsSecret(source._msufDefaultsRevision) then return true end
        if field == "_rejectedProfileBackups" and Literal(source, {}) ~= Literal(profile, {}) then return true end
        local revision = tonumber(source._msufDefaultsRevision)
        if field == "_newerRevisionBackups" and (not revision or revision <= 17 or revision == sparseToken) then return true end
        return SaveNamed(store, field, name, source, notice)
    end
    function Schema.BackupNewerRevision(profile)
        local revision = tonumber(profile._msufDefaultsRevision)
        if revision and revision > 17 and revision ~= sparseToken then return SaveOwned(profile, "_newerRevisionBackups", true) end
        return true
    end
    function Schema.IsQuarantinedProfile(profile)
        if MSUF.Util.IsSecret(profile) then return false end
        return rejected[profile] ~= nil or working[profile] == true
    end
    function Schema.ReleaseQuarantinedProfile(profile)
        rejected[profile], working[profile] = nil, nil
    end
    local function FillWorking(copy, defaults)
        for key, value in pairs(defaults) do
            local current = copy[key]
            if MSUF.Util.IsSecret(current) then
                copy[key] = nil
                current = nil
            end
            if type(value) == "table" then
                if not Plain(current) then copy[key] = {} end
                FillWorking(copy[key], value)
            elseif current == nil then copy[key] = value end
        end
    end
    function Schema.QuarantineProfile(profile)
        if not Plain(profile) then return Schema.BuildRecoveryDefaults() end
        if working[profile] then return profile end
        if rejected[profile] then return rejected[profile] end
        SaveOwned(profile, "_rejectedProfileBackups", false)
        local copy = CopyNewerProfile(profile, {})
        local defaults = Schema.BuildRecoveryDefaults()
        FillWorking(copy, defaults)
        copy[sparseV2Marker], copy[sparseV3.Marker] = nil, nil
        copy._msufDefaultsRevision = defaults._msufDefaultsRevision
        rejected[profile], working[copy] = copy, true
        return copy
    end
    local function Archive(store, field, name)
        local backups = store[field]
        local bucket = type(backups) == "table" and backups[name]
        if type(bucket) ~= "table" then return end
        bucket = RecoveryBucket(store, field, name)
        local archive = store._profileRecoveryArchive
        if type(archive) ~= "table" then
            archive = {}
            store._profileRecoveryArchive = archive
        end
        if type(archive[field]) ~= "table" then archive[field] = {} end
        archive[field][bucket.identity] = bucket
        backups[name] = nil
    end
    function Schema.RenameProfileRecovery(source, target)
        local store = MSUF_GlobalDB
        if type(store) ~= "table" then return end
        for _, field in ipairs({ "_newerRevisionBackups", "_rejectedProfileBackups" }) do
            local backups = store[field]
            if type(backups) == "table" then
                if target then
                    Archive(store, field, target)
                    backups[target], backups[source] = backups[source], nil
                else Archive(store, field, source) end
            end
        end
        BoundRecovery(store)
        local ids = store._profileRecoveryIDs
        if type(ids) == "table" then
            if target then ids[target] = ids[source] end
            ids[source] = nil
        end
    end
    function Schema.ListProfileRecovery()
        local store = MSUF_GlobalDB
        if type(store) ~= "table" then return {}, 2, recoveryLimit end
        local rows = RecoveryRows(store)
        return rows, RecoveryBytes(store), recoveryLimit
    end
    function Schema.ExportProfileRecovery(key)
        local rows = Schema.ListProfileRecovery()
        for _, row in ipairs(rows) do
            if row.key == key then return "return " .. Literal(row.entry.data, {}) end
        end
    end
    function Schema.PurgeProfileRecovery(key)
        local rows, count = Schema.ListProfileRecovery(), 0
        for _, row in ipairs(rows) do
            if key == "all" or row.key == key then RemoveRecovery(row) count = count + 1 end
        end
        if type(MSUF_GlobalDB) == "table" then BoundRecovery(MSUF_GlobalDB) end
        return count
    end
    function Schema.RegisterRecoveryCommands()
        local commands = MSUF.SlashCommands
        if commands.Get("recovery") then return end
        commands.Register({ name = "recovery", group = "profiles", help = "Profiles",
            usage = "/msuf recovery list | export <key> | purge <key|all>",
            run = function(rest)
                local action, key = (rest or ""):match("^(%S+)%s*(.-)%s*$")
                if action == "list" then
                    local rows, bytes, limit = Schema.ListProfileRecovery()
                    print(string.format("MSUF recovery: %d/%d bytes", bytes, limit))
                    for _, row in ipairs(rows) do
                        print(string.format("%s %s %s", row.field, tostring(row.name), tostring(row.key or "legacy")))
                    end
                elseif action == "export" and key ~= "" then
                    local text = Schema.ExportProfileRecovery(key)
                    if not text or MSUF.Util.InCombat() then return false end
                    if not MSUF.Require("MSUF_EnsureOptionsLoaded", "State/Defaults/MSUF_Defaults_Recovery.lua")("recovery") then return false end
                    MSUF.Require("MSUF_ShowCopyLink", "State/Defaults/MSUF_Defaults_Recovery.lua")("Profiles", text)
                elseif action == "purge" and key ~= "" then
                    print("MSUF recovery: " .. Schema.PurgeProfileRecovery(key))
                else print("/msuf recovery list | export <key> | purge <key|all>") end
            end,
        })
    end
    function Schema.BoundProfileRecovery(store)
        return BoundRecovery(store)
    end
    -- Restore is explicit and does not bind or normalize the recovered bytes.
    function Schema.RestoreProfileBackup(name, key, kind)
        local store = MSUF_GlobalDB
        if type(store) ~= "table" or type(store.profiles) ~= "table" then return nil, "no profile store" end
        local field = kind == "rejected" and "_rejectedProfileBackups" or "_newerRevisionBackups"
        local backups = store[field]
        local bucket = type(backups) == "table" and backups[name]
        local entry
        if type(bucket) == "table" then
            bucket = RecoveryBucket(store, field, name)
            entry = bucket.entries[key or bucket.order[#bucket.order]]
        end
        if type(entry) ~= "table" then
            local archive = store._profileRecoveryArchive
            archive = type(archive) == "table" and archive[field]
            for _, saved in pairs(type(archive) == "table" and archive or {}) do
                if type(saved.entries) == "table" and saved.entries[key] then entry = saved.entries[key] end
            end
        end
        if type(entry) ~= "table" then return nil, "unknown profile backup" end
        local copy = CopyNewerProfile(entry.data, {})
        store.profiles[name] = copy
        return copy
    end
end

-- The first return retains the historical changed/restored boolean contract.
-- Cold account recovery. One immutable snapshot, outside the compacted pool;
-- never a per-profile history or a copy on each logout.
do
    local blockedStore
    local sparseValidation = setmetatable({}, { __mode = "k" })
    local snapshotLimit = 8 * 1024 * 1024

    local function SnapshotCost(value, remaining)
        local kind = type(value)
        if kind == "string" then return #value * 4 + 2 end
        if kind ~= "table" then return 32 end
        local cost = 2
        for key, child in pairs(value) do
            cost = cost + SnapshotCost(key, remaining - cost) + 4
            if cost > remaining then return cost end
            cost = cost + SnapshotCost(child, remaining - cost)
            if cost > remaining then return cost end
        end
        return cost
    end

    local function Safe(value)
        local safe = CountTables(value, scratchRefs, scratchPath, 0, scratchLists)
        ClearScratch()
        return safe
    end

    local function CopySafe(value, bounded)
        if not Safe(value) then return nil end
        local cost = bounded and SnapshotCost(value, snapshotLimit)
        if cost and cost > snapshotLimit then return nil end
        return CopyNewerProfile(value, {}), cost
    end

    local function IsFull(profile)
        return Plain(profile) and Safe(profile) and profile._msufDefaultsRevision == 17
            and profile[sparseV2Marker] == nil and profile[sparseV3.Marker] == nil
            and Schema.IsCurrentProfile(profile)
    end

    local function ValidSnapshotUnit(owner)
        return Plain(owner) and type(owner.width) == "number" and owner.width > 0
            and type(owner.height) == "number" and owner.height > 0
    end

    local function ValidSnapshotProfile(profile)
        if not Plain(profile) or not Plain(profile.general) or type(profile.general.fontKey) ~= "string"
            or profile.general.fontKey == "" or not ValidSnapshotUnit(profile.player)
            or not ValidSnapshotUnit(profile.target) then return false end
        if profile[sparseV2Marker] ~= nil or profile[sparseV3.Marker] ~= nil
            or profile._msufDefaultsRevision == sparseToken or profile._msufDefaultsRevision == "MSUF_SPARSE_DEFAULTS_1" then return false end
        for key in pairs(Schema.Values.UnitFrames) do
            local owner = profile[key]
            if MSUF.Util.IsSecret(owner) or (owner ~= nil and not Plain(owner)) then return false end
        end
        return not MSUF.Util.IsSecret(profile.bars) and (profile.bars == nil or Plain(profile.bars))
    end

    local function ValidSnapshot(backup, knownCost)
        if not Plain(backup) or (not knownCost and not Safe(backup)) then return false end
        local cost = knownCost or SnapshotCost(backup, snapshotLimit)
        if cost > snapshotLimit then return false end
        if backup.version ~= 1 or not Plain(backup.profiles) or next(backup.profiles) == nil or not Plain(backup.char)
            or (backup.source ~= "full" and backup.source ~= "reconstructed") then return false end
        for name, profile in pairs(backup.profiles) do
            if type(name) ~= "string" or name == "" or not ValidSnapshotProfile(profile) then return false end
        end
        for name, binding in pairs(backup.char) do
            if type(name) ~= "string" or name == "" or not Plain(binding)
                or (binding.activeProfile ~= nil and type(binding.activeProfile) ~= "string") then return false end
        end
        return backup.legacy == nil or ValidSnapshotProfile(backup.legacy), cost
    end

    -- The payload is immutable. Persist only scalar validation facts; never
    -- serialize table identities or scan the profile tree on ordinary reload.
    local function StampKey(backup, stamp)
        return table.concat({ "1", stamp.bytes, stamp.profile, backup.source, tostring(backup.legacy ~= nil) }, ":")
    end

    local function Readable(...)
        for i = 1, select("#", ...) do
            if MSUF.Util.IsSecret(select(i, ...)) then return false end
        end
        return true
    end

    local function HasStamp(backup)
        if not Plain(backup) then return false end
        local stamp = backup.validation
        if not Plain(stamp) then return false end
        if not Readable(stamp.generator, stamp.bytes, stamp.profile, stamp.key, backup.version, backup.source, backup.legacy) then return false end
        if stamp.generator ~= 1 or type(stamp.bytes) ~= "number" or stamp.bytes ~= stamp.bytes
            or stamp.bytes <= 0 or stamp.bytes > snapshotLimit or type(stamp.profile) ~= "string"
            or stamp.profile == "" or type(stamp.key) ~= "string" or backup.version ~= 1
            or (backup.source ~= "full" and backup.source ~= "reconstructed")
            or not Plain(backup.profiles) or not Plain(backup.char) then return false end
        local profile = backup.profiles[stamp.profile]
        if not Plain(profile) or not Plain(profile.general) or not Plain(profile.player) or not Plain(profile.target) then return false end
        if not Readable(profile.general.fontKey, profile.player.width, profile.player.height,
            profile.target.width, profile.target.height, profile._msufDefaultsRevision,
            profile[sparseV2Marker], profile[sparseV3.Marker]) then return false end
        return ValidSnapshotProfile(profile) and stamp.key == StampKey(backup, stamp)
    end

    local function ValidateAndStamp(backup, knownCost)
        local valid, cost = ValidSnapshot(backup, knownCost)
        if not valid then return false end
        if not HasStamp(backup) then
            local stamp = { generator = 1, bytes = cost, profile = next(backup.profiles) }
            stamp.key = StampKey(backup, stamp)
            local overhead = SnapshotCost("validation", snapshotLimit) + 4 + SnapshotCost(stamp, snapshotLimit)
            if cost + overhead > snapshotLimit then return false end
            backup.validation = stamp
        end
        return true
    end

    function Schema.HasRollbackBackup(store, beforeSparse)
        if not Plain(store) then return false end
        local backup = store._pre70ProfileBackup
        if beforeSparse then
            -- Disk stamps keep login cheap; only this session's full content
            -- preflight can authorize removing defaults at logout or reload.
            if not Plain(backup) then return false end
            local valid = sparseValidation[backup]
            if valid == nil then
                valid = ValidateAndStamp(backup)
                sparseValidation[backup] = valid
            end
            return valid
        end
        return HasStamp(backup) or ValidateAndStamp(backup)
    end

    function Schema.CaptureRollbackBackup(store, legacy)
        if not Plain(store) then return false end
        if store._pre70ProfileBackup ~= nil then return Schema.HasRollbackBackup(store) end
        if store == blockedStore then return false end
        local profiles = store.profiles
        if not Plain(profiles) or next(profiles) == nil then
            if not Plain(legacy) then return false end
            profiles = { Default = legacy }
        end
        local snapshot, cost = CopySafe({ profiles = profiles, char = Plain(store.char) and store.char or {}, legacy = legacy }, true)
        if not snapshot then
            blockedStore = store
            return false
        end
        local source = "full"
        for _, profile in pairs(snapshot.profiles) do
            if not Plain(profile) then blockedStore = store return false end
            if profile[sparseV2Marker] ~= nil or profile[sparseV3.Marker] ~= nil
                or profile._msufDefaultsRevision == sparseToken or profile._msufDefaultsRevision == "MSUF_SPARSE_DEFAULTS_1" then
                local _, status = Schema.RestorePersistence(profile)
                if status == "rejected" then blockedStore = store return false end
                source = "reconstructed"
            end
        end
        if Plain(snapshot.legacy) and (snapshot.legacy[sparseV2Marker] ~= nil or snapshot.legacy[sparseV3.Marker] ~= nil
            or snapshot.legacy._msufDefaultsRevision == sparseToken
            or snapshot.legacy._msufDefaultsRevision == "MSUF_SPARSE_DEFAULTS_1") then
            local _, status = Schema.RestorePersistence(snapshot.legacy)
            if status == "rejected" then blockedStore = store return false end
            source = "reconstructed"
        end
        snapshot.version, snapshot.source = 1, source
        -- CopySafe already checked the full source tree. Only reconstruction
        -- changes its payload; avoid a second full walk for a fresh full copy.
        if source == "reconstructed" then cost = nil
        else cost = cost + SnapshotCost("version", snapshotLimit) + 36
            + SnapshotCost("source", snapshotLimit) + 4 + SnapshotCost(source, snapshotLimit) end
        if not ValidateAndStamp(snapshot, cost) then blockedStore = store return false end
        store._pre70ProfileBackup = snapshot
        return true
    end

    -- Inspect the on-disk envelope before login has decoded or migrated it.
    function Schema.BeginRollbackSession(store, legacy)
        if not Plain(store) then return end
        store._pre70SparseValidated = nil
        Schema.RegisterRecoveryCommands()
        Schema.BoundProfileRecovery(store)
        if store._compatSave == "saved" then
            local full = Plain(store.profiles) and next(store.profiles) ~= nil
            if full then
                for _, profile in pairs(store.profiles) do
                    if not IsFull(profile) then full = false break end
                end
            end
            if full then store._compatSave = nil else store._compatSave = "armed" end
        end
        Schema.CaptureRollbackBackup(store, legacy)
    end

    function Schema.RestoreRollbackBackup(store)
        if not Plain(store) or not ValidateAndStamp(store._pre70ProfileBackup) then return false end
        local restored = CopySafe(store._pre70ProfileBackup, true)
        if not restored then return false end
        store.profiles, store.char = restored.profiles, restored.char
        store._compatSave = "armed"
        return true, restored.legacy
    end

    function Schema.PersistCompat(store)
        local profiles = Schema.PreparePersistence(store)
        if not profiles then return false end
        for _, profile in pairs(profiles) do
            if not IsFull(profile) then
                -- Preflight detached data: an unknown envelope must never be
                -- stamped as revision 17 or silently presented as downgrade safe.
                local candidate = CopySafe(profile)
                if not Plain(candidate) then return false end
                local _, status = Schema.RestorePersistence(candidate)
                if status == "rejected" or (tonumber(candidate._msufDefaultsRevision) or 0) > 17 then return false end
                MSUF.Require("MSUF_NormalizeProfileDefaults", "State/Defaults/MSUF_Defaults_Schema.lua")(candidate, false, true)
                if not IsFull(candidate) then return false end
            end
        end
        for _, profile in pairs(profiles) do
            if not IsFull(profile) then
                Schema.RestorePersistence(profile)
                MSUF.Require("MSUF_NormalizeProfileDefaults", "State/Defaults/MSUF_Defaults_Schema.lua")(profile, false, true)
            end
        end
        return true, 0
    end

    function Schema.SetCompatSave(store, enabled)
        if not Plain(store) then return false end
        store._compatSave = enabled and "armed" or nil
        return true
    end
end



-- Complete forward bindings once; gameplay closures keep direct local calls.
Parts.Bind2()
MSUF.DefaultsSchemaParts = nil
