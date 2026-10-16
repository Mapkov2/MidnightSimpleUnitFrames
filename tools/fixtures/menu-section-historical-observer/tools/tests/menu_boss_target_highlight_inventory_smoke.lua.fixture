-- Boss target highlight section: receipts captured before it moved onto the control schema.
local root, flavor = assert(arg[1]), assert(arg[2])
local Parity = assert(loadfile(root:gsub("\\", "/") .. "/tools/tests/menu_section_parity_world.lua"))()
local P = "boss_target_highlight."
Parity.Run({
    root = root, flavor = flavor, area = "boss_target_highlight", capture = arg[3] == "--capture",
    sections = { boss_target_highlight = true }, units = { "boss" },
    edits = {
        { P .. "style", "ARROW" }, { P .. "style", "OFF" }, { P .. "style", "BORDER_ARROW" },
        { P .. "bosstargetindicatoranchor", "TOP" }, { P .. "bosstargetindicatordirection", "UP" },
        { P .. "bosstargetindicatorsize", 40 }, { P .. "bosstargetindicatoroffsetx", -10 },
        { P .. "bosstargetindicatoroffsety", 12 }, { P .. "bosstargetindicatorlayout", "BOTH_IN" },
        { P .. "multiple_only", true }, { P .. "multiple_only", false },
    },
})
