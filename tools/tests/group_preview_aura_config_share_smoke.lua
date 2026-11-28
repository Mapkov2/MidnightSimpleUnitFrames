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
h:RunDeferred()

h.core.ExportPublic("MSUF2_GFPagePreviewActive", true)
Check(GF.ShowPreview("raid", 20, { immediate = true }) ~= false, "the raid preview did not open")
h:RunDeferred()
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
    -- Force a cold answer with a temporary independent base identity. The
    -- Auras3-owned weak cache is deliberately absent from every group spec.
    local row = frames[7]
    local savedBase, savedConfig = row._msufGFSpecBase, row._msufA3NativeGroupConfig
    row._msufGFSpecBase, row._msufA3NativeGroupConfig = {}, nil
    local perRow = A3.ResolveAuraPreviewConfig(row, row.MSUFUnitKey)
    row._msufGFSpecBase, row._msufA3NativeGroupConfig = savedBase, savedConfig
    Check(type(perRow) == "table" and perRow ~= shared, "fixture premise: the per-row resolve should compile its own table")
    Same(shared.lanes, perRow.lanes, "lanes", 0)
    Same(shared.spellIndicators, perRow.spellIndicators, "spellIndicators", 0)
    -- The menu uses the cold runtime resolver for each row's final position and zoom.
    -- Keep this contract observable independently of the emulator's native pixel rounding.
    local previewLane = assert(shared.lanes.buff)
    local oldSolve, oldMetrics = A3.ResolveOutlineLaneOffset, A3.OutlineLaneMetrics
    local oldZoom = row._msufBorderPreviewZoom
    local sampleSlot = { visual = "icon", anchor = "TOPLEFT", x = 0, y = 4, size = 17,
        icon = "Interface\\Icons\\INV_Misc_QuestionMark", iconShape = "RECTANGLE" }
    local positions = 0
    A3.ResolveOutlineLaneOffset = function(owner, lane, x, y, zoom)
        if lane == sampleSlot then return x - 0.25, y + 0.5, true end
        if lane ~= previewLane then return x, y, false end
        Check(owner == row and zoom == 4, "aura resolver received another row or zoom")
        Check(x == lane.x and y == lane.y, "preview replaced the configured offsets")
        positions = positions + 1
        return x + 0.25, y - 0.25, true
    end
    A3.OutlineLaneMetrics = function(owner, lane, zoom)
        if lane == sampleSlot then return 16, 18, 0, 0, 16, 18 end
        if lane == previewLane then
            Check(owner == row and zoom == 4, "icon metrics received another row or zoom")
            return 19, 21, 0, 2, 61, 21
        end
    end
    row._msufBorderPreviewZoom = 4
    GF.PreviewFrameAuras(row, "raid", 7, nil, row._msufGFSpecBase)
    local host = row._msufGFFrameAuraPreviewHosts.buff
    local _, parent, _, x, y = host:GetPoint(1)
    Check(positions == 1 and parent == row and x == previewLane.x + 0.25 and y == previewLane.y - 0.25,
        "group preview ignored the corrected aura origin")
    Check(host:GetWidth() == 61 and host:GetHeight() == 21, "group preview lost the projected footprint")
    local icons = 0
    for _, icon in ipairs(row._msufGFFrameAuraPreviews) do
        if icon:IsShown() and icon._sceneAuraLayoutHost == host then
            Check(icon:GetWidth() == 19 and icon:GetHeight() == 21, "preview art did not use projected size")
            icons = icons + 1
        end
    end
    Check(icons > 0, "no projected raid aura samples")
    GF.PreviewFrameAuras(row, "raid", 7, nil, row._msufGFSpecBase)
    Check(positions == 1, "unchanged preview reapplied the pixel resolver")
    -- The options inserter rewrites this same slot table on each settings refresh.
    local sampleOwner = env.CreateFrame("Frame", nil, row)
    for _, value in ipairs({ 0, 3 }) do
        sampleSlot.x = value
        local visual = GF.PreviewSpellSample(row, sampleOwner, sampleSlot)
        local _, rel, _, sx, sy = visual:GetPoint(1)
        Check(rel == row and sx == value - 0.25 and sy == 4.5, "spell sample reused a stale corrected anchor")
        Check(visual:GetWidth() == 16 and visual:GetHeight() == 18, "spell sample ignored its pixel size")
    end
    A3.ResolveOutlineLaneOffset, A3.OutlineLaneMetrics = oldSolve, oldMetrics
    row._msufBorderPreviewZoom = oldZoom
end

-- Live frames are untouched: a real raid never reaches the preview resolver.
GF.HidePreview("raid")
h.core.ExportPublic("MSUF2_GFPagePreviewActive", nil)
h:SetRaid(20)
h:Event("GROUP_ROSTER_UPDATE")
h:RunDeferred()
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
