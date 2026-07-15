package.path = "tools/?.lua;" .. package.path

local Inventory = require("assistant_graphify_inventory")
local tracked = Inventory.Load("tools/assistant_graphify_inventory_data.lua")
assert(tracked.recordCount == 1700, "reviewed Graphify setting-inventory count drifted")
assert(tracked.schemaVersion == 2, "Graphify inventory source-snapshot contract is not current")
assert(tracked.sourceSnapshot.schemaVersion == 1
        and tracked.sourceSnapshot.manifestFormat == "msuf-addon-source-sha256-v1"
        and tracked.sourceSnapshot.algorithm == "SHA256"
        and #tracked.sourceSnapshot.manifestSha256 == 64
        and tracked.sourceSnapshot.fileCount > 0,
    "Graphify inventory has incomplete source-snapshot metadata")

local paths, tiers, evidence = Inventory.ToCrosswalkMaps(tracked)
assert(#paths == tracked.recordCount, "Graphify inventory map lost paths")
assert(tiers["bars._msuf2Width"] == nil and evidence["bars._msuf2Width"] == nil,
    "Graphify inventory retained the removed Group Bars width projection")

local same, sameError = Inventory.Compare(tracked, tracked)
assert(same == true and sameError == nil, "identical Graphify inventories did not compare equal")

local function CopySourceSnapshot(snapshot)
    return {
        schemaVersion = snapshot.schemaVersion,
        manifestFormat = snapshot.manifestFormat,
        algorithm = snapshot.algorithm,
        manifestSha256 = snapshot.manifestSha256,
        fileCount = snapshot.fileCount,
    }
end

local changedSnapshot = CopySourceSnapshot(tracked.sourceSnapshot)
local first = changedSnapshot.manifestSha256:sub(1, 1)
changedSnapshot.manifestSha256 = (first == "A" and "B" or "A")
    .. changedSnapshot.manifestSha256:sub(2)
local sourceChanged = {
    schemaVersion = tracked.schemaVersion,
    sourceSnapshot = changedSnapshot,
    recordCount = tracked.recordCount,
    records = tracked.records,
}
local sourceCurrent, sourceDrift = Inventory.Compare(tracked, sourceChanged)
assert(sourceCurrent == false and tostring(sourceDrift):find("source snapshot manifest SHA256 changed", 1, true),
    "Graphify inventory comparison accepted source-manifest drift")

local changedRecords = {}
for i = 1, #tracked.records do
    local row = tracked.records[i]
    changedRecords[i] = { row[1], row[2], row[3], row[4] }
end
changedRecords[1][4] = "L999999"
local changed = {
    schemaVersion = tracked.schemaVersion,
    sourceSnapshot = CopySourceSnapshot(tracked.sourceSnapshot),
    recordCount = tracked.recordCount,
    records = changedRecords,
}
local current, drift = Inventory.Compare(tracked, changed)
assert(current == false and tostring(drift):find("source location changed", 1, true),
    "Graphify inventory comparison accepted changed source evidence")

print(string.format("assistant_graphify_inventory_smoke: ok records=%d source_and_record_drift_detection=1",
    tracked.recordCount))
