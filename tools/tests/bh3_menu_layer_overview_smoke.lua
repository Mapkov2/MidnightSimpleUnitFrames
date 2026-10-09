local ROOT = assert(arg[1]):gsub("\\", "/"):gsub("/$", "") .. "/"
-- Probe: LayerOverview rows vs runtime compile for group Spell Indicators.
-- Run from repo root: lua C:\tmp\bh3\probes\C25-p1\layer_overview_probe.lua
local NS = { MSUF2 = {}, GF = {} }
NS.ExportPublic = function(name, value) _G[name] = value end
NS.MSUF2.Tr = function(s) return s end
NS.MSUF2.Format = string.format
_G.MSUF_NormalizeFrameStrata = function(v, fallback) return v or fallback end
_G.MSUF_GetGeneralDB = function() return {} end
_G.MSUF_GF_CopySpellConfig = function(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = _G.MSUF_GF_CopySpellConfig(x) end
    return o
end
-- User raised the Spell Indicators "Default" layer to 17; the preset item has no own layer
-- and no full-frame effect block (the normal state of a freshly enabled preset item).
_G.MSUF_DB = {
    general = {}, bars = {},
    gf_party = { enabled = true, spellIndicators = { enabled = true, spec = "test", layer = 17,
        specs = { test = { example = { enabled = true, custom = true, spells = "123",
            placed = { type = "icon", size = 20 } } } } } },
    auras3 = { enabled = true, showTarget = true, customContainers = { perUnit = { target = { items = {
        { id = "c1", name = "My Custom", enabled = true } } } } } },
}
NS.GF.SpellIndicators = { SpecInfo = { test = {} }, SpecDefaults = {}, TrackableAuras = {} }
assert(loadfile(ROOT .. "MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config_Indicators.lua"))("test", NS)
-- The arena PvP trinket row reads the trinket runtime (core, loaded before Options);
-- a client answer without arena units keeps its event wiring out of this probe.
NS.Client = { SupportsUnit = function() return false end }
assert(loadfile(ROOT .. "MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_ArenaTrinkets.lua"))("test", NS)
NS.Client = nil
assert(loadfile(ROOT .. "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_LayerOverview.lua"))("test", NS)
local compiled = NS.GF.CompileSpellIndicators(_G.MSUF_DB.gf_party, "party")
local item = compiled.items[1]
print("runtime item layer", item and item.layer, "runtime frame effect", item and tostring(item.frame))
for _, r in ipairs(NS.MSUF2.CollectLayerOverviewRows()) do
    if r.id == "group.party.spellIndicators.test.example.layer" then
        assert(r.layer == item.layer and r.inherited, "inherited spell layer differs from runtime")
    end
    if r.id == "group.party.spellIndicators.test.example.frame.layer" then
        assert(r.enabled == false, "absent group frame effect marked enabled")
    end
    if r.id == "auras3.target.custom.c1.frame.layer" then
        assert(r.enabled == false, "absent unit frame effect marked enabled")
    end
end
-- Round trip: press Enter on the displayed (wrong) number without editing it.
local itemRow
for _, r in ipairs(NS.MSUF2.CollectLayerOverviewRows()) do
    if r.id == "group.party.spellIndicators.test.example.layer" then itemRow = r end
end
assert(NS.MSUF2.LayerOverview.SetLayerValue(itemRow, tostring(itemRow.layer)))
local after = NS.GF.CompileSpellIndicators(_G.MSUF_DB.gf_party, "party").items[1]
print("after Enter on unchanged overview number: runtime item layer", after.layer, "expected 17 (unchanged)")

assert(after.layer == 17 and MSUF_DB.gf_party.spellIndicators.specs.test.example.layer == nil, "unchanged Enter destroyed inheritance")
print("layer overview inheritance: PASS")

-- Castbar rows follow the same client support gate as unit pages.
local supported = { player = true, target = true, arena = true }
NS.MSUF2.FilterSupportedUnitValues = function(rows)
    for i = #rows, 1, -1 do if not supported[rows[i].key] then table.remove(rows, i) end end
    return rows
end
local castbars = {}
for _, row in ipairs(NS.MSUF2.CollectLayerOverviewRows()) do
    if row.id:match("^castbar%.") then castbars[row.id] = true end
end
assert(castbars["castbar.arena.root"] and castbars["castbar.arena.icon"], "Arena castbar layers missing")
assert(not castbars["castbar.focus.root"] and not castbars["castbar.boss.root"], "unsupported castbar scopes leaked into overview")
