-- PvP Trinket section: receipts captured before it moved onto the control schema.
local root, flavor = assert(arg[1]), assert(arg[2])
local Parity = assert(loadfile(root:gsub("\\", "/") .. "/tools/tests/menu_section_parity_world.lua"))()
Parity.Run({
    root = root, flavor = flavor, area = "pvp_trinket", capture = arg[3] == "--capture",
    sections = { pvp_trinket = true }, units = { "arena" },
    edits = {
        { "trinket.show", false }, { "trinket.show", true }, { "trinket.size", 31 }, { "trinket.layer", 12 },
        { "trinket.anchor", "LEFT" }, { "trinket.offset_x", 5 }, { "trinket.offset_y", -7 },
    },
    states = function(api, unit, page)
        api.env.MSUF_DB[unit].showTrinket = false
        api.Record(page, "disabled")
        api.env.MSUF_DB[unit].showTrinket = true
    end,
})
