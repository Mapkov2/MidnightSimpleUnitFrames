-- Unit Visibility (load conditions) section: receipts captured before it moved onto the control schema.
local root, flavor = assert(arg[1]), assert(arg[2])
local Parity = assert(loadfile(root:gsub("\\", "/") .. "/tools/tests/menu_section_parity_world.lua"))()
Parity.Run({
    root = root, flavor = flavor, area = "unit_visibility", capture = arg[3] == "--capture",
    sections = { load_conditions = true },
    behavior = function(api, _, page)
        for _, spec in ipairs(api.M.UnitPage.LOAD_CONDITIONS) do
            api.Edit(page, "load_condition." .. spec.key, true)
        end
        api.Edit(page, "load_condition.loadcondshowwheninjured", true)
        api.Edit(page, "load_condition.loadcondshowwheninjured", false)
        api.Edit(page, "load_condition." .. api.M.UnitPage.LOAD_CONDITIONS[1].key, false)
    end,
})
