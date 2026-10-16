-- Boss and Arena Layout sections: receipts captured before they moved onto the control schema.
local root, flavor = assert(arg[1]), assert(arg[2])
local Parity = assert(loadfile(root:gsub("\\", "/") .. "/tools/tests/menu_section_parity_world.lua"))()
Parity.Run({
    root = root, flavor = flavor, area = "boss_arena_layout", capture = arg[3] == "--capture",
    sections = { boss_layout = true, arena_layout = true }, units = { "boss", "arena" },
    states = function(api, unit, page)
        -- A profile from before layout modes only carries the inverted-order flag.
        api.env.MSUF_DB[unit].bossLayoutMode = nil
        api.env.MSUF_DB[unit].invertBossOrder = true
        api.Record(page, "legacy-invert")
    end,
    behavior = function(api, unit, page)
        local prefix = unit .. "_layout."
        api.Edit(page, prefix .. "spacing", -120)
        for _, mode in ipairs({ "VERTICAL_UP", "HORIZONTAL_RIGHT", "HORIZONTAL_LEFT", "VERTICAL_DOWN" }) do
            api.Edit(page, prefix .. "mode", mode)
        end
    end,
})
