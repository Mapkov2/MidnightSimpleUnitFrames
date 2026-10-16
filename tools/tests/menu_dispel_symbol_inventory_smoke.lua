-- Dispel Symbol section: receipts captured before it moved onto the control schema.
local root, flavor = assert(arg[1]), assert(arg[2])
local Parity = assert(loadfile(root:gsub("\\", "/") .. "/tools/tests/menu_section_parity_world.lua"))()
Parity.Run({
    root = root, flavor = flavor, area = "dispel_symbol", capture = arg[3] == "--capture",
    sections = { unit_dispel_symbol = true }, units = { "player", "target", "focus", "boss", "arena" },
    virtual = function(record) return record.controlId:find("dispel_symbol_offset", 1, true) ~= nil end,
    edits = {
        { "dispel.symbol.enabled", true }, { "dispel.symbol.unitdispelsymbolstyle", "MSUF_LETTERS" },
        { "dispel.symbol.unitdispelsymbolmode", "TOP" }, { "dispel.symbol.unitdispelsymboltrigger", "BY_RAID" },
        { "dispel.symbol.unitdispelsymbolsize", 19 }, { "dispel.symbol.unitdispelsymbolalpha", 0.5 },
        { "dispel.symbol.unitdispelsymbolanchor", "LEFT" }, { "dispel.symbol.unitdispelsymbolgrowth", "UP" },
        { "dispel.symbol.unitdispelsymbolspacing", 0 }, { "dispel.symbol.unitdispelsymbollayer", 3 },
        { "dispel.symbol.unitdispelsymbolstrata", "HIGH" }, { "dispel.symbol.preview", true },
        { "dispel.symbol.preview", false }, { "dispel.symbol.enabled", false },
    },
    states = function(api, unit, page)
        local M, conf = api.M, api.env.MSUF_DB[unit]
        for _, enabled in ipairs({ false, true }) do
            conf.unitDispelSymbolEnabled = enabled
            for _, mode in ipairs({ "TOP", "ALL" }) do
                conf.unitDispelSymbolMode = mode
                api.Record(page, tostring(enabled) .. ":" .. mode)
            end
        end
        M.formContentMaxWidth = 420
        M.InvalidatePage(page)
        api.Check(api.mw:Select(page), "narrow select")
        api.Record(page, "narrow")
        M.formContentMaxWidth = nil
        M.InvalidatePage(page)
        api.Check(api.mw:Select(page), "wide select")
    end,
})
