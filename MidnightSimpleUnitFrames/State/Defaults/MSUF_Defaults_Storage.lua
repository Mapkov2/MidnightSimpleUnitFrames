-- V2 sparse decoder, round-trip persistence and public storage entry points.
local _, MSUF = ...
local Parts = MSUF.DefaultsSchemaParts
local ClearScratch = Parts.ClearScratch
local CountTables = Parts.CountTables
local Plain = Parts.Plain
local RestoreLegacyPersistence = Parts.RestoreLegacyPersistence
local Schema = Parts.Schema
local scratchLists = Parts.scratchLists
local scratchPath = Parts.scratchPath
local scratchRefs = Parts.scratchRefs
local sparseToken = Parts.sparseToken
local sparseV2Fields, sparseV2Owners
local sparseV3 = Parts.sparseV3
-- V2 records only fields actually removed; unlike V1 it never reconstructs an
-- absent optional field merely because its owner exists. The field pool and
-- owner order above are immutable. Future dictionary changes need a new version.
local sparseV2Marker = "_msufSparseDefaultsV2"
local sparseV2Before, sparseV2Tables, sparseV2Nibbles, sparseV2Pieces = {}, {}, {}, {}
local sparseV2Absent = {}
local sparseV2Symbols, sparseV2Bits = {}, { 1, 2, 4, 8 }
for i = 0, 15 do sparseV2Symbols[i] = ("0123456789abcdef"):sub(i + 1, i + 1) end
local sparseV2Size = 0
local sparseV2MaskSize
local function InitializeSparse()
    if sparseV2MaskSize then return end
    local data = MSUF.DefaultsStorageData
    data.Load()
    sparseV2Fields, sparseV2Owners = data.sparseV2Fields, data.sparseV2Owners
    for i = 1, #sparseV2Owners do
        local owner = sparseV2Owners[i]
        owner.offset = sparseV2Size
        sparseV2Tables[i] = false
        for j = 1, #owner.fields do sparseV2Before[sparseV2Size + j] = false end
        sparseV2Size = sparseV2Size + #owner.fields
    end
    for i = 1, #sparseV2Fields do
        local field = sparseV2Fields[i]
        field.bytes = #field[1] + #tostring(field[2]) + 4
    end
    sparseV2MaskSize = math.ceil(sparseV2Size / 4)
    for i = 1, sparseV2MaskSize do sparseV2Nibbles[i], sparseV2Pieces[i] = 0, "" end
    sparseV3.Initialize()
end

local function ResolveSparseV2Owners(profile, refs, lists)
    for i = 1, #sparseV2Owners do
        local node = profile
        local path = sparseV2Owners[i].path
        for j = 1, #path do
            if type(node) ~= "table" or lists[node] then
                node = nil
                break
            end
            if refs[node] ~= 1 then return false end
            node = node[path[j]]
        end
        if type(node) == "table" then
            if refs[node] ~= 1 then return false end
            if lists[node] then node = nil end
        else
            node = nil
        end
        sparseV2Tables[i] = node or false
    end
    return true
end

local function ReleaseSparseV2(rollback)
    sparseV3.Release(rollback)
    for i = 1, #sparseV2Owners do
        local spec, owner = sparseV2Owners[i], sparseV2Tables[i]
        for j = 1, #spec.fields do
            local slot = spec.offset + j
            local before = sparseV2Before[slot]
            if rollback and owner then
                local key = sparseV2Fields[spec.fields[j]][1]
                if before == sparseV2Absent then owner[key] = nil else owner[key] = before end
            end
            sparseV2Before[slot] = false
        end
        sparseV2Tables[i] = false
    end
end

local function SparseV2Bit(slot)
    local index = math.floor((slot - 1) / 4) + 1
    local bit = sparseV2Bits[(slot - 1) % 4 + 1]
    return math.floor(sparseV2Nibbles[index] / bit) % 2 == 1
end

local function ReadSparseV2Mask(mask)
    if type(mask) ~= "string" or #mask ~= sparseV2MaskSize then return false end
    local nonzero = false
    for i = 1, sparseV2MaskSize do
        local byte = mask:byte(i)
        local value
        if byte >= 48 and byte <= 57 then value = byte - 48
        elseif byte >= 97 and byte <= 102 then value = byte - 87
        else return false end
        sparseV2Nibbles[i] = value
        if value ~= 0 then nonzero = true end
    end
    local tail = sparseV2Size % 4
    return nonzero and (tail == 0 or sparseV2Nibbles[sparseV2MaskSize] < 2 ^ tail)
end

local function ValidateSparseV2MaskOwners()
    for i = 1, #sparseV2Owners do
        local spec = sparseV2Owners[i]
        if not sparseV2Tables[i] then
            for j = 1, #spec.fields do
                if SparseV2Bit(spec.offset + j) then return false end
            end
        end
    end
    return true
end

local function ApplySparseV2(restore)
    local count = 0
    for i = 1, #sparseV2Owners do
        local spec, owner = sparseV2Owners[i], sparseV2Tables[i]
        if owner then
            for j = 1, #spec.fields do
                if SparseV2Bit(spec.offset + j) then
                    local field = sparseV2Fields[spec.fields[j]]
                    local key, default = field[1], field[2]
                    if restore then
                        if owner[key] == nil then
                            owner[key] = default
                            count = count + 1
                        end
                    elseif owner[key] == default then
                        owner[key] = nil
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

local function RestoreSparseV2(profile, prepared)
    if profile._msufDefaultsRevision ~= sparseToken or not ReadSparseV2Mask(profile[sparseV2Marker]) then return false end
    if not prepared then
        local ok = CountTables(profile, scratchRefs, scratchPath, 0, scratchLists)
            and ResolveSparseV2Owners(profile, scratchRefs, scratchLists)
            and (profile[sparseV3.Marker] == nil or sparseV3.Resolve(profile, scratchRefs, scratchLists))
        ClearScratch()
        if not ok then return false end
    end
    -- Validate the entire mask and all referenced owners before the first write.
    if not ValidateSparseV2MaskOwners() or not sparseV3.Validate(profile) then return false end
    if profile[sparseV3.Marker] ~= nil then sparseV3.Apply(true, prepared) end
    ApplySparseV2(true)
    profile[sparseV3.Marker] = nil
    profile[sparseV2Marker] = nil
    profile._msufDefaultsRevision = 17
    return true
end

-- The second distinguishes ordinary full data from an undecodable envelope.
function Schema.RestorePersistence(profile)
    if not Plain(profile) or MSUF.Util.IsSecret(profile._msufDefaultsRevision) then return false, "rejected" end
    if Schema.IsQuarantinedProfile(profile) then return false, "rejected" end
    if not Schema.BackupNewerRevision(profile) then return false, "rejected" end
    local marker = profile[sparseV2Marker]
    local extension = profile[sparseV3.Marker]
    if MSUF.Util.IsSecret(marker) or MSUF.Util.IsSecret(extension) then return false, "rejected" end
    local revision = profile._msufDefaultsRevision
    local stale = (marker ~= nil or extension ~= nil) and (revision == nil or (type(revision) == "number" and revision < sparseToken)
        or (revision ~= sparseToken and type(marker) ~= "string" and type(extension) ~= "string"))
    if stale then
        if revision == "MSUF_SPARSE_DEFAULTS_1" and not RestoreLegacyPersistence(profile) then return false, "rejected" end
        profile[sparseV2Marker], profile[sparseV3.Marker] = nil, nil
        return true, "restored"
    elseif marker ~= nil then
        InitializeSparse()
        local restored = RestoreSparseV2(profile, false)
        ReleaseSparseV2(false)
        return restored, restored and "restored" or "rejected"
    end
    if extension ~= nil then return false, "rejected" end
    if revision == sparseToken or revision == "MSUF_SPARSE_DEFAULTS_1" then
        local restored = RestoreLegacyPersistence(profile)
        return restored, restored and "restored" or "rejected"
    end
    return false, "not-sparse"
end

local function CaptureSparseV2()
    local count, bytes = 0, 0
    for i = 1, sparseV2MaskSize do sparseV2Nibbles[i] = 0 end
    for i = 1, #sparseV2Owners do
        local spec, owner = sparseV2Owners[i], sparseV2Tables[i]
        for j = 1, #spec.fields do
            local slot, field = spec.offset + j, sparseV2Fields[spec.fields[j]]
            local value
            if owner then value = owner[field[1]] end
            if value == nil then sparseV2Before[slot] = sparseV2Absent else sparseV2Before[slot] = value end
            if not field.retain and value == field[2] then
                local index = math.floor((slot - 1) / 4) + 1
                sparseV2Nibbles[index] = sparseV2Nibbles[index] + sparseV2Bits[(slot - 1) % 4 + 1]
                count, bytes = count + 1, bytes + field.bytes
            end
        end
    end
    return count, bytes
end

local function SameSparseV2()
    for i = 1, #sparseV2Owners do
        local spec, owner = sparseV2Owners[i], sparseV2Tables[i]
        for j = 1, #spec.fields do
            local before, value = sparseV2Before[spec.offset + j]
            if before == sparseV2Absent then before = nil end
            if owner then value = owner[sparseV2Fields[spec.fields[j]][1]] end
            if type(value) ~= type(before) or value ~= before then return false end
        end
    end
    return true
end

local function PersistProfile(profile, refs, lists)
    if not Plain(profile) or profile._msufDefaultsRevision ~= 17 or profile[sparseV2Marker] ~= nil
        or profile[sparseV3.Marker] ~= nil or refs[profile] ~= 1 then return 0 end
    if not ResolveSparseV2Owners(profile, refs, lists) or not sparseV3.Resolve(profile, refs, lists) then
        ReleaseSparseV2(false)
        return 0
    end
    local legacyRemoved = CaptureSparseV2()
    local removed, bytes = sparseV3.Capture()
    -- A short/incomplete profile remains full when the fixed mask would cost more.
    if legacyRemoved == 0 or bytes <= sparseV2MaskSize + #sparseV2Marker + 32 + sparseV3.Overhead then
        ReleaseSparseV2(false)
        return 0
    end
    for i = 1, sparseV2MaskSize do sparseV2Pieces[i] = sparseV2Symbols[sparseV2Nibbles[i]] end
    local mask = table.concat(sparseV2Pieces)
    local extension = sparseV3.Mask()
    profile[sparseV2Marker], profile._msufDefaultsRevision = mask, sparseToken
    profile[sparseV3.Marker] = extension
    local elided = sparseV3.Apply(false) + ApplySparseV2(false)
    -- The real decoder's nil-only fill runs against the existing owner tables.
    -- Compare every known original field by type AND value, including nil/false/0.
    -- Only these fields and the two stamps can change; all other keys and table
    -- identities are untouched. Rollback returns the complete original profile.
    local restored = RestoreSparseV2(profile, true)
    if elided ~= removed or not restored or not SameSparseV2() or not sparseV3.Same() then
        ReleaseSparseV2(true)
        profile[sparseV2Marker], profile._msufDefaultsRevision = nil, 17
        profile[sparseV3.Marker] = nil
        return 0
    end
    local committed = sparseV3.Apply(false) + ApplySparseV2(false)
    if committed ~= removed then
        ReleaseSparseV2(true)
        profile[sparseV2Marker], profile._msufDefaultsRevision = nil, 17
        profile[sparseV3.Marker] = nil
        return 0
    end
    ReleaseSparseV2(false)
    profile[sparseV2Marker], profile._msufDefaultsRevision = mask, sparseToken
    profile[sparseV3.Marker] = extension
    return committed
end

function Schema.PreparePersistence(globalDB)
    if not Plain(globalDB) or not Plain(globalDB.profiles) then return nil end
    return globalDB.profiles
end

local sparseRefusalNotices = setmetatable({}, { __mode = "k" })

function Schema.Persist(globalDB)
    local profiles = Schema.PreparePersistence(globalDB)
    if not profiles then return false end
    if globalDB._compatSave == "armed" or globalDB._compatSave == "saved" then
        local ok, count = Schema.PersistCompat(globalDB)
        if ok then globalDB._compatSave = "saved" end
        if not ok then print(MSUF.Translate("MSUF: Compatibility save failed: a profile cannot be reconstructed. Keep 7.0 installed.")) end
        return ok, count
    end
    -- A failed safety snapshot leaves the live account full. Standalone codec
    -- callers have no account/login lifecycle and retain their pure contract.
    if globalDB == MSUF_GlobalDB and not Schema.HasRollbackBackup(globalDB, true) then
        if not sparseRefusalNotices[globalDB] then
            sparseRefusalNotices[globalDB] = true
            print(MSUF.Translate("MSUF: No complete safety copy is available. Sparse saving is disabled; your profiles stay full."))
        end
        return false
    end
    InitializeSparse()
    local count = 0
    if CountTables(globalDB, scratchRefs, scratchPath, 0, scratchLists) and scratchRefs[profiles] == 1 then
        for _, profile in pairs(profiles) do count = count + PersistProfile(profile, scratchRefs, scratchLists) end
    end
    ClearScratch()
    return true, count
end


Parts.sparseV2Bits = sparseV2Bits
Parts.sparseV2Marker = sparseV2Marker
Parts.sparseV2Symbols = sparseV2Symbols
