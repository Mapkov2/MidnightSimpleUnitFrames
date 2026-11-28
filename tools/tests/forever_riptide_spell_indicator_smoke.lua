local root = assert(arg[1]):gsub("/$", "")
local Harness = assert(loadfile(root .. "/tools/tests/group_header_world.lua"))()
local h = Harness.New(root, "Forever", { beforeBoot = function(world) world.env.MAX_BOSS_FRAMES = 5 end })
local spec = "ClassicShaman"
local SI = h.GF.SpellIndicators
assert(SI.SpellIDs[spec].Riptide == 408521)
assert(SI.AltSpellIDs[spec][1239242] == "Riptide")
assert(SI.AltSpellIDs[spec][1239243] == "Riptide")
assert(SI.SpecDefaults[spec].Riptide and SI.SpecDefaults[spec].AncestralFortitude)
local runtime = h.core.MSUF_Auras3.SpellIndicators
for _, scope in ipairs({ "party", "raid" }) do
    local db = { spellIndicators = { enabled = true, spec = spec, specs = { [spec] = { Riptide = { enabled = true } } } } }
    local compiled = h.GF.CompileSpellIndicators(db, scope)
    local found
    for _, item in ipairs(compiled.items) do
        if item.auraName == "Riptide" then
            local slots = runtime.CompileSlots(scope .. "1", { enabled = true, items = { item } })
            local slot = assert(slots.slots[1])
            local ids = assert(slot.candidateFilters.includeSpellIDs)
            assert(ids[408521] and ids[1239242] and ids[1239243], "native slot must recognize every Forever rank")
            assert(slot.nativeFilter:find("HELPFUL", 1, true), "Riptide uses a native helpful aura slot")
            found = true
        end
    end
    assert(found, "Riptide missing on " .. scope)
end
print("forever_riptide_spell_indicator_smoke: passed")
