-- Exact Graphify setting-inventory parser and tracked-snapshot contract.
-- The full graph stays a disposable analysis artifact; release/schema gates
-- consume the compact snapshot generated from it without weakening any path,
-- tier, or source-evidence checks.

local M = {
    schemaVersion = 2,
    sourceSnapshotSchemaVersion = 1,
    sourceSnapshotManifestFormat = "msuf-addon-source-sha256-v1",
    sourceSnapshotAlgorithm = "SHA256",
    sourceSnapshotSidecarName = ".msuf-assistant-source-snapshot.json",
}

local VALID_TIERS = {
    core_read_write = true,
    core_reference_only = true,
    assistant_only = true,
    unclassified = true,
}

local function Read(path)
    local file, err = io.open(path, "rb")
    assert(file, err)
    local text = file:read("*a") or ""
    file:close()
    return text
end

local function JsonUnescape(text)
    return tostring(text or "")
        :gsub("\\/", "/")
        :gsub("\\b", "\b")
        :gsub("\\f", "\f")
        :gsub("\\n", "\n")
        :gsub("\\r", "\r")
        :gsub("\\t", "\t")
        :gsub('\\"', '"')
        :gsub("\\\\", "\\")
end

local function JsonField(object, key)
    local encoded = object:match('"' .. key .. '"%s*:%s*"([^"\\]*)"')
    return encoded and JsonUnescape(encoded) or nil
end

local function JsonNumberField(object, key)
    local encoded = object:match('"' .. key .. '"%s*:%s*(%d+)')
    return encoded and tonumber(encoded) or nil
end

local function ValidateSourceSnapshot(snapshot, label)
    label = tostring(label or "Graphify source snapshot")
    assert(type(snapshot) == "table", label .. " is missing")
    assert(snapshot.schemaVersion == M.sourceSnapshotSchemaVersion,
        label .. " schema version is unsupported: " .. tostring(snapshot.schemaVersion))
    assert(snapshot.manifestFormat == M.sourceSnapshotManifestFormat,
        label .. " manifest format is unsupported: " .. tostring(snapshot.manifestFormat))
    assert(snapshot.algorithm == M.sourceSnapshotAlgorithm,
        label .. " algorithm is unsupported: " .. tostring(snapshot.algorithm))
    local fingerprint = tostring(snapshot.manifestSha256 or "")
    assert(#fingerprint == 64 and fingerprint:match("^[0-9A-F]+$") ~= nil,
        label .. " has an invalid manifest SHA256")
    local fileCount = tonumber(snapshot.fileCount)
    assert(fileCount and fileCount > 0 and fileCount == math.floor(fileCount),
        label .. " has an invalid file count")
    return snapshot
end

local function SourceSnapshotPathForGraph(path)
    local directory = tostring(path or ""):match("^(.*[/\\])[^/\\]+$") or ""
    return directory .. M.sourceSnapshotSidecarName
end

local function LoadSourceSnapshot(path)
    local text = Read(path)
    return ValidateSourceSnapshot({
        schemaVersion = JsonNumberField(text, "schemaVersion"),
        manifestFormat = JsonField(text, "manifestFormat"),
        algorithm = JsonField(text, "algorithm"),
        manifestSha256 = JsonField(text, "manifestSha256"),
        fileCount = JsonNumberField(text, "fileCount"),
    }, path)
end

local function EachJsonArrayObject(json, field, callback)
    local _, cursor = json:find('"' .. field .. '"%s*:%s*%[')
    assert(cursor, "Graphify JSON array missing: " .. field)
    cursor = cursor + 1
    local depth, objectStart, quoted, escaped = 0, nil, false, false
    for i = cursor, #json do
        local char = json:sub(i, i)
        if quoted then
            if escaped then escaped = false
            elseif char == "\\" then escaped = true
            elseif char == '"' then quoted = false end
        elseif char == '"' then
            quoted = true
        elseif char == "{" then
            depth = depth + 1
            if depth == 1 then objectStart = i end
        elseif char == "}" then
            depth = depth - 1
            if depth == 0 and objectStart then
                callback(json:sub(objectStart, i))
                objectStart = nil
            end
        elseif char == "]" and depth == 0 then
            return
        end
    end
    error("unterminated Graphify JSON array: " .. field)
end

local function Validate(inventory, label)
    label = tostring(label or "Graphify setting inventory")
    assert(type(inventory) == "table", label .. " returned no contract")
    assert(inventory.schemaVersion == M.schemaVersion,
        label .. " schema version is unsupported: " .. tostring(inventory.schemaVersion))
    ValidateSourceSnapshot(inventory.sourceSnapshot, label .. " source snapshot")
    assert(type(inventory.records) == "table", label .. " has no records")
    assert(tonumber(inventory.recordCount) == #inventory.records,
        label .. " record count is inconsistent")
    assert(#inventory.records > 0, label .. " is empty")

    local previous
    for i = 1, #inventory.records do
        local row = inventory.records[i]
        assert(type(row) == "table", label .. " record " .. i .. " is invalid")
        local path, tier = tostring(row[1] or ""), tostring(row[2] or "")
        local sourceFile, sourceLocation = tostring(row[3] or ""), tostring(row[4] or "")
        assert(path ~= "", label .. " record " .. i .. " has no setting path")
        assert(VALID_TIERS[tier], label .. " record " .. i .. " has invalid tier " .. tier)
        assert(sourceFile ~= "" and sourceLocation ~= "",
            label .. " record " .. i .. " has incomplete source evidence for " .. path)
        assert(not previous or previous < path,
            label .. " paths must be unique and strictly sorted at " .. path)
        previous = path
    end
    return inventory
end

function M.ParseGraph(path)
    local sourceSnapshot = LoadSourceSnapshot(SourceSnapshotPathForGraph(path))
    local graphText = Read(path)
    local graphPathById, rowByPath = {}, {}

    EachJsonArrayObject(graphText, "nodes", function(object)
        if JsonField(object, "kind") ~= "setting" then return end
        local settingPath, id = JsonField(object, "setting_path"), JsonField(object, "id")
        if settingPath and settingPath ~= "" and id and id ~= "" then
            graphPathById[id] = settingPath
            rowByPath[settingPath] = rowByPath[settingPath] or {
                settingPath,
                "unclassified",
                JsonField(object, "source_file") or "",
                JsonField(object, "source_location") or "",
            }
        end
    end)

    local coreReadWrite, coreReference, assistantEvidence = {}, {}, {}
    EachJsonArrayObject(graphText, "links", function(object)
        local relation = JsonField(object, "relation")
        if relation ~= "reads_setting" and relation ~= "writes_setting"
            and relation ~= "references_setting" and relation ~= "registers_setting"
        then
            return
        end
        local settingPath = graphPathById[JsonField(object, "target")]
            or graphPathById[JsonField(object, "source")]
        if not settingPath then return end
        local sourceFile = tostring(JsonField(object, "source_file") or ""):gsub("\\", "/")
        local isAssistant = sourceFile:find("^MidnightSimpleUnitFrames_Assistant/") ~= nil
        local isCore = sourceFile:find("^MidnightSimpleUnitFrames/") ~= nil and not isAssistant
        if isCore and (relation == "reads_setting" or relation == "writes_setting") then
            coreReadWrite[settingPath] = true
        elseif isCore and relation == "references_setting" then
            coreReference[settingPath] = true
        elseif isAssistant then
            assistantEvidence[settingPath] = true
        end
    end)

    local records = {}
    for _, row in pairs(rowByPath) do
        local settingPath = row[1]
        if coreReadWrite[settingPath] then row[2] = "core_read_write"
        elseif coreReference[settingPath] then row[2] = "core_reference_only"
        elseif assistantEvidence[settingPath] then row[2] = "assistant_only" end
        records[#records + 1] = row
    end
    table.sort(records, function(left, right) return left[1] < right[1] end)
    return Validate({
        schemaVersion = M.schemaVersion,
        sourceSnapshot = sourceSnapshot,
        recordCount = #records,
        records = records,
    }, path)
end

M.SourceSnapshotPathForGraph = SourceSnapshotPathForGraph
M.LoadSourceSnapshot = LoadSourceSnapshot

function M.Load(path)
    local chunk, err = loadfile(path)
    assert(chunk, tostring(path) .. ": " .. tostring(err))
    local ok, inventory = pcall(chunk)
    assert(ok, tostring(path) .. ": " .. tostring(inventory))
    return Validate(inventory, path)
end

function M.Compare(expected, actual)
    Validate(expected, "expected Graphify inventory")
    Validate(actual, "actual Graphify inventory")
    local snapshotFields = {
        { "schemaVersion", "schema version" },
        { "manifestFormat", "manifest format" },
        { "algorithm", "algorithm" },
        { "manifestSha256", "manifest SHA256" },
        { "fileCount", "file count" },
    }
    for i = 1, #snapshotFields do
        local key, description = snapshotFields[i][1], snapshotFields[i][2]
        if expected.sourceSnapshot[key] ~= actual.sourceSnapshot[key] then
            return false, string.format("source snapshot %s changed: tracked=%s live=%s",
                description, tostring(expected.sourceSnapshot[key]), tostring(actual.sourceSnapshot[key]))
        end
    end
    if #expected.records ~= #actual.records then
        return false, string.format("record count changed: tracked=%d live=%d",
            #expected.records, #actual.records)
    end
    local fields = { "path", "tier", "source file", "source location" }
    for i = 1, #expected.records do
        for field = 1, 4 do
            if expected.records[i][field] ~= actual.records[i][field] then
                return false, string.format("record %d %s changed: tracked=%s live=%s", i,
                    fields[field], tostring(expected.records[i][field]), tostring(actual.records[i][field]))
            end
        end
    end
    return true
end

local function Quote(value)
    return string.format("%q", tostring(value or ""))
end

function M.Write(path, inventory)
    Validate(inventory, "generated Graphify inventory")
    local file, err = io.open(path, "wb")
    assert(file, err)
    file:write("-- Generated by tools/generate_assistant_graphify_inventory.lua. Do not edit by hand.\n")
    file:write("return {\n")
    file:write("    schemaVersion = ", tostring(M.schemaVersion), ",\n")
    file:write("    sourceSnapshot = {\n")
    file:write("        schemaVersion = ", tostring(inventory.sourceSnapshot.schemaVersion), ",\n")
    file:write("        manifestFormat = ", Quote(inventory.sourceSnapshot.manifestFormat), ",\n")
    file:write("        algorithm = ", Quote(inventory.sourceSnapshot.algorithm), ",\n")
    file:write("        manifestSha256 = ", Quote(inventory.sourceSnapshot.manifestSha256), ",\n")
    file:write("        fileCount = ", tostring(inventory.sourceSnapshot.fileCount), ",\n")
    file:write("    },\n")
    file:write("    recordCount = ", tostring(#inventory.records), ",\n")
    file:write("    records = {\n")
    for i = 1, #inventory.records do
        local row = inventory.records[i]
        file:write("        { ", Quote(row[1]), ", ", Quote(row[2]), ", ",
            Quote(row[3]), ", ", Quote(row[4]), " },\n")
    end
    file:write("    },\n}\n")
    file:close()
end

function M.ToCrosswalkMaps(inventory)
    Validate(inventory, "Graphify crosswalk inventory")
    local paths, tierByPath, evidenceByPath = {}, {}, {}
    for i = 1, #inventory.records do
        local row = inventory.records[i]
        paths[i] = row[1]
        tierByPath[row[1]] = row[2]
        evidenceByPath[row[1]] = {
            sourceFile = row[3],
            sourceLocation = row[4],
        }
    end
    return paths, tierByPath, evidenceByPath
end

return M
