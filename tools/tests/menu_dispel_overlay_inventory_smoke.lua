-- Dispel Overlay section: receipts captured before it moved onto the control schema.
local root, flavor = assert(arg[1]), assert(arg[2])
local Parity = assert(loadfile(root:gsub("\\", "/") .. "/tools/tests/menu_section_parity_world.lua"))()
Parity.Run({
    root = root, flavor = flavor, area = "dispel_overlay", capture = arg[3] == "--capture",
    sections = { unit_dispel_overlay = true }, units = { "player", "target", "focus", "boss", "arena" },
    edits = {
        { "dispel.overlay.enabled", true }, { "dispel.overlay.unitdispeloverlaytrigger", "BY_ME" },
        { "dispel.overlay.unitdispeloverlaystyle", "TOP" }, { "dispel.overlay.unitdispeloverlayonhealth", false },
        { "dispel.overlay.unitdispeloverlayalpha", 0.5 }, { "dispel.overlay.preview", true },
        { "dispel.overlay.preview", false }, { "dispel.overlay.enabled", false },
    },
    states = function(api, unit, page)
        for _, enabled in ipairs({ true, false }) do
            api.env.MSUF_DB[unit].unitDispelOverlayEnabled = enabled
            api.Record(page, "enabled:" .. tostring(enabled))
        end
    end,
})
