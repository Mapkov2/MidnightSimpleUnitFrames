-- The old-profile regression corpus: one row per entry. Provenance and the
-- reason for each entry are in tools/fixtures/profiles/README.md.
--
--   id       golden file name (golden/<id>.golden)
--   kind     "sv": a SavedVariables fixture (sv/<id>.lua) loaded at login;
--            "factory": an empty SavedVariables (fresh install), then new,
--            reset and imported profiles
--   clients  the clients that load it: a SavedVariables file belongs to its
--            client family; profile strings travel to every client
--   login    the character that logs in (the one the saved MSUF_DB belongs to)
--   imports  factory only: profile strings imported into new profiles
local RETAIL = { "Mainline", "Forever" }
local CLASSIC = { "Vanilla", "TBC", "Mists" }
local EVERY = { "Mainline", "Forever", "Vanilla", "TBC", "Mists" }

local IMPORTS = {}
for _, id in ipairs({
    "hist_2026-01-18_msuf2_preset",
    "hist_2026-05-04_msuf3_corrupt",
    "hist_2026-05-27_msuf3_portable",
    "hist_2026-07-14_msuf3_raw_profile",
    "hist_2026-08-06_msuf3_full_schema1",
    "hist_2026-08-15_classic_factory",
    "base_factory",
    "base_forever_factory",
    "base_modern_dark",
    "base_msuf4_unitframe",
    "base_msuf4_castbar",
    "base_msuf4_colors",
    "base_msuf4_gameplay",
    "base_msuf4_groupframe",
    "base_msuf4_unitselection",
    "synth_msuf2_printsafe_castbar",
    "synth_msuf3_uncompressed_colors",
    "synth_text_gameplay",
    "synth_msuf3_pre6_profile",
}) do
    IMPORTS[#IMPORTS + 1] = { id = id, file = "tools/fixtures/profiles/imports/" .. id .. ".txt" }
end

return {
    -- First: the SavedVariables entries take a fresh install's values from it.
    { id = "factory", kind = "factory", clients = EVERY, imports = IMPORTS },
    { id = "sv_retail_rev16_17", kind = "sv", file = "tools/fixtures/profiles/sv/sv_retail_rev16_17.lua",
        clients = RETAIL, login = "Char16-Realm03" },
    { id = "sv_ptr_rev13", kind = "sv", file = "tools/fixtures/profiles/sv/sv_ptr_rev13.lua",
        clients = RETAIL, login = "Char01-Realm01" },
    { id = "sv_ptr_rev6", kind = "sv", file = "tools/fixtures/profiles/sv/sv_ptr_rev6.lua",
        clients = RETAIL, login = "Char01-Realm01" },
    { id = "sv_xptr_rev15", kind = "sv", file = "tools/fixtures/profiles/sv/sv_xptr_rev15.lua",
        clients = RETAIL, login = "Char01-Realm01" },
    { id = "sv_pre6_feb", kind = "sv", file = "tools/fixtures/profiles/sv/sv_pre6_feb.lua",
        clients = RETAIL, login = "Char01-Realm01" },
    { id = "sv_pre6_mar", kind = "sv", file = "tools/fixtures/profiles/sv/sv_pre6_mar.lua",
        clients = RETAIL, login = "Char10-Realm01" },
    { id = "sv_forever_beta_rev17", kind = "sv", file = "tools/fixtures/profiles/sv/sv_forever_beta_rev17.lua",
        clients = { "Forever", "Mainline" }, login = "Char01-Realm01" },
    { id = "sv_mists_rev15", kind = "sv", file = "tools/fixtures/profiles/sv/sv_mists_rev15.lua",
        clients = CLASSIC, login = "Char01-Realm01" },
    { id = "sv_era_rev15", kind = "sv", file = "tools/fixtures/profiles/sv/sv_era_rev15.lua",
        clients = CLASSIC, login = "Char03-Realm01" },
    { id = "sv_tbcptr_rev14", kind = "sv", file = "tools/fixtures/profiles/sv/sv_tbcptr_rev14.lua",
        clients = CLASSIC, login = "Char01-Realm01" },
    { id = "sv_anniversary_rev17", kind = "sv", file = "tools/fixtures/profiles/sv/sv_anniversary_rev17.lua",
        clients = CLASSIC, login = "Char01-Realm01" },
}
