-- group_preview_aura_config_share_smoke.lua <repoRoot> <flavor>
--
-- Every group preview row carries its own PatchFrameSpec copy of one compiled
-- base spec. Resolving the aura preview config against that row spec missed the
-- runtime's per-spec shared cache, so a 20-row raid preview compiled 20 configs
-- (80 lane compiles plus the spell-indicator slots), one per row, for the same
-- answer. A 2026-10-05 Retail trace measured it as the largest preview-only
-- cost inside ApplyPreviewData. The preview now resolves against the base spec
-- while the row still mirrors it (MSUF_UF_Group_Preview.lua
-- PreviewAuraConfigSpec), the path RefreshPreviewAuras already took.
-- This smoke pins, on the real load graph (SecureGroupHeader emulator):
--   1. Mainline family: every row of one build resolves to one shared config
--      table, and that config's lanes and spell-indicator slots equal the
--      per-row compile field for field (what the painters read);
--   2. Classic family: rows keep resolving per row (no proxy is created);
--   3. live raid frames never take the preview path.
-- Plain Lua 5.1, repo root as arg 1, flavor as arg 2.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")

local function Check(condition, message)
    if not condition then error("group_preview_aura_config_share_smoke " .. flavor .. ": " .. message, 2) end
end

local h = Harness.New(root, flavor, { beforeBoot = function(harness) harness.env.MAX_BOSS_FRAMES = 5 end })
local GF, env = h.GF, h.env
local A3 = h.core.MSUF_Auras3
local classic = h.core.Client and h.core.Client.IsClassic == true
GF.EnsureDB()
local raid = GF.GetConf("raid")
raid.enabled = true
-- Spell indicators on, for the first spec that ships trackable auras.
local siModule = GF.SpellIndicators or (A3 and A3.SpellIndicators)
local trackable = siModule and siModule.TrackableAuras
local specKey
if type(trackable) == "table" then
    local keys = {}
    for key, list in pairs(trackable) do
        if type(list) == "table" and #list > 0 then keys[#keys + 1] = tostring(key) end
    end
    table.sort(keys)
    specKey = keys[1]
end
raid.spellIndicators = raid.spellIndicators or {}
raid.spellIndicators.enabled = true
raid.spellIndicators.spec = specKey or "auto"
if GF.InvalidateConfCache then GF.InvalidateConfCache() end
if GF.InvalidateCompiledSpecs then GF.InvalidateCompiledSpecs() end
GF.RefreshHeaderLayout()
h:RunTimers()

env.MSUF2_GFPagePreviewActive = true
Check(GF.ShowPreview("raid", 20, { immediate = true }) ~= false, "the raid preview did not open")
h:RunTimers()
local frames = GF._previewFrames.raid or {}
Check(#frames == 20, "the raid preview built " .. #frames .. " rows, expected 20")

-- Field-for-field equality over what the painters read (scalars and nested tables).
local function Same(a, b, path, depth)
    if type(a) ~= "table" or type(b) ~= "table" then
        Check(a == b or (type(a) == "function" and type(b) == "function"),
            "shared and per-row config differ at " .. path .. ": " .. tostring(a) .. " vs " .. tostring(b))
        return
    end
    if depth > 6 then return end
    for k, v in pairs(a) do Same(v, b[k], path .. "." .. tostring(k), depth + 1) end
    for k in pairs(b) do
        if a[k] == nil then Check(false, "shared config lacks " .. path .. "." .. tostring(k)) end
    end
end

if classic then
    for i = 1, #frames do
        Check(frames[i]._msufA3AuraPreviewConfigProxy == nil, "Classic row " .. i .. " resolved through a shared proxy")
    end
else
    local shared
    for i = 1, #frames do
        local proxy = frames[i]._msufA3AuraPreviewConfigProxy
        Check(proxy ~= nil, "row " .. i .. " still resolved its aura config per row")
        local cfg = proxy._msufA3NativeGroupConfig
        Check(type(cfg) == "table", "row " .. i .. " has no shared aura config")
        shared = shared or cfg
        Check(cfg == shared, "row " .. i .. " compiled its own aura config")
    end
    Check(type(shared.lanes) == "table" and type(shared.spellIndicators) == "table",
        "the shared config carries no lanes or spell-indicator slots")
    -- The per-row answer the preview used to paint from: compile row 7 from its
    -- own spec with every cache out of the way (a row spec copied after its base
    -- gained the shared cache table holds the same table reference).
    local row = frames[7]
    local rowSpec = row.MSUFSpec
    local savedCache, savedConfig = rowSpec._msufA3NativeGroupConfigCache, row._msufA3NativeGroupConfig
    rowSpec._msufA3NativeGroupConfigCache, row._msufA3NativeGroupConfig = nil, nil
    local perRow = A3.ResolveAuraPreviewConfig(row, row.MSUFUnitKey)
    rowSpec._msufA3NativeGroupConfigCache, row._msufA3NativeGroupConfig = savedCache, savedConfig
    Check(type(perRow) == "table" and perRow ~= shared, "fixture premise: the per-row resolve should compile its own table")
    Same(shared.lanes, perRow.lanes, "lanes", 0)
    Same(shared.spellIndicators, perRow.spellIndicators, "spellIndicators", 0)
end

-- Live frames are untouched: a real raid never reaches the preview resolver.
GF.HidePreview("raid")
env.MSUF2_GFPagePreviewActive = nil
h:SetRaid(20)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local live = 0
GF.ForEachHeader("raid", function(header)
    for _, child in ipairs(h:Children(header)) do
        if child.attributes.unit then
            live = live + 1
            Check(child._msufA3AuraPreviewConfigProxy == nil, "live raid child took the preview aura path")
        end
    end
end)
Check(live == 20, "the live raid built " .. live .. " frames, expected 20")
Check(#h.violations == 0, "protected write in lockdown:\n" .. tostring(h.violations[1]))

print(string.format("group_preview_aura_config_share_smoke: ok (%s: %s)", flavor,
    classic and "per-row resolve kept" or "20 rows share one aura config"))
