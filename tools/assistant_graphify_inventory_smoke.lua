package.path = "tools/?.lua;" .. package.path

local Inventory = require("assistant_graphify_inventory")
local tracked = Inventory.Load("tools/assistant_graphify_inventory_data.lua")
assert(tracked.recordCount == 1651, "reviewed Graphify setting-inventory count drifted")

local paths, tiers, evidence = Inventory.ToCrosswalkMaps(tracked)
assert(#paths == tracked.recordCount, "Graphify inventory map lost paths")
assert(tiers["bars._msuf2Width"] == nil and evidence["bars._msuf2Width"] == nil,
    "Graphify inventory retained the removed Group Bars width projection")

local same, sameError = Inventory.Compare(tracked, tracked)
assert(same == true and sameError == nil, "identical Graphify inventories did not compare equal")

local changedRecords = {}
for i = 1, #tracked.records do
    local row = tracked.records[i]
    changedRecords[i] = { row[1], row[2], row[3], row[4] }
end
changedRecords[1][4] = "L999999"
local changed = {
    schemaVersion = tracked.schemaVersion,
    recordCount = tracked.recordCount,
    records = changedRecords,
}
local current, drift = Inventory.Compare(tracked, changed)
assert(current == false and tostring(drift):find("source location changed", 1, true),
    "Graphify inventory comparison accepted changed source evidence")

print(string.format("assistant_graphify_inventory_smoke: ok records=%d exact_drift_detection=1",
    tracked.recordCount))
