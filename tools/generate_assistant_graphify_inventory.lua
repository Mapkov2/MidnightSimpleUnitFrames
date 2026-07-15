-- Refresh the tracked compact Graphify setting inventory from a full local
-- graph export. Run only after reviewing the live crosswalk diagnostics.

package.path = "tools/?.lua;" .. package.path

local Inventory = require("assistant_graphify_inventory")
local input = tostring(arg and arg[1] or "graphify-out/graph.json")
local output = tostring(arg and arg[2] or "tools/assistant_graphify_inventory_data.lua")
local inventory = Inventory.ParseGraph(input)
Inventory.Write(output, inventory)
print(string.format("assistant Graphify inventory refreshed: %d setting paths; source=%s (%d files) -> %s",
    inventory.recordCount, inventory.sourceSnapshot.manifestSha256,
    inventory.sourceSnapshot.fileCount, output))
