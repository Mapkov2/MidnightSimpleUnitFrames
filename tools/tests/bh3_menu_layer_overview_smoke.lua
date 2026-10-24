local ROOT = assert(arg[1]):gsub("\\", "/"):gsub("/$", "") .. "/"
-- Probe: LayerOverview rows vs runtime compile for group Spell Indicators.
-- Run from repo root: lua C:\tmp\bh3\probes\C25-p1\layer_overview_probe.lua
local NS = { MSUF2 = {}, GF = {} }
-- The real Kernel namespace API (Bootstrap, Require); each file loads through LoadShipped, which defers the
-- providers this probe does not load (a deferred one raises if the probe uses it).
local REPO = ROOT:gsub("/$", "")
local RequireFixture = assert(loadfile(ROOT .. "tools/tests/require_fixture.lua"))()
RequireFixture.InstallKernel(REPO, NS)
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
RequireFixture.LoadShipped(REPO, "MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config_Indicators.lua", NS)
-- The arena PvP trinket row reads the trinket runtime (core, loaded before Options);
-- a client answer without arena units keeps its event wiring out of this probe.
NS.Client = { SupportsUnit = function() return false end }
RequireFixture.LoadShipped(REPO, "MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_ArenaTrinkets.lua", NS)
NS.Client = nil
RequireFixture.LoadShipped(REPO, "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_LayerOverview.lua", NS)
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

-- Group Aura lanes render only in the CUSTOM renderer: an edit made here must
-- show, and a no-op Enter on an unchanged number must not switch the renderer.
local laneKey = "gf_party"
local function GroupLaneRow(id, strata)
    local rows = strata and NS.MSUF2.CollectFrameStrataRows() or NS.MSUF2.CollectLayerOverviewRows()
    for _, r in ipairs(rows) do
        if r.id == id then return r end
    end
end
MSUF_DB[laneKey].auras = { renderer = "NATIVE_12_1", buff = { layer = 5 } }
local layerRow = assert(GroupLaneRow("group.party.auras.buff.layer"), "group aura lane layer row missing")
NS.MSUF2.LayerOverview.SetLayerValue(layerRow, tostring(layerRow.layer))
assert(MSUF_DB[laneKey].auras.renderer == "NATIVE_12_1", "an unchanged Enter switched the aura renderer")
assert(NS.MSUF2.LayerOverview.SetLayerValue(layerRow, "12"))
assert(MSUF_DB[laneKey].auras.buff.layer == 12 and MSUF_DB[laneKey].auras.renderer == "CUSTOM",
    "a group aura layer edit left the renderer inactive")
MSUF_DB[laneKey].auras.renderer = "NATIVE_12_1"
local strataRow = assert(GroupLaneRow("group.party.auras.debuff.strata", true), "group aura lane strata row missing")
assert(NS.MSUF2.LayerOverview.SetStrataValue(strataRow, "HIGH"))
assert(MSUF_DB[laneKey].auras.debuff.strata == "HIGH" and MSUF_DB[laneKey].auras.renderer == "CUSTOM",
    "a group aura strata edit left the renderer inactive")
print("layer overview group aura activation: PASS")

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
