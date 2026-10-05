-- copy_to_section_completeness_smoke.lua <repoRoot> <flavor>
--
-- A Copy To category copies everything its section configures, so the target
-- behaves like the source afterwards.
--
--   1. Group Frames, "Font Override" (MSUF_Menu2_Group.lua GF_COPY_CATEGORIES):
--      the list held the outline and colour keys only, so a copy left the text
--      opacity, rendering mode (sharp/slug), baseline offset and the text
--      shadow switch and metrics of the target as they were. After copying
--      Party's font override to Raid, every group font resolver
--      (GroupFrames/MSUF_GroupFrames_DB_Text.lua) answers Raid like Party.
--   2. Unit frames, "Texture Layer" (MSUF_Menu2_Unit.lua COPY_TEXLAYER_FIELDS):
--      the suffix list left out the visibility rules ("Current target only",
--      the health condition and threshold, the low-health opacity and the
--      above-threshold colour), so a copied layer showed under the target's
--      old rules. Every per-slot key the runtime reads (BuildSlotKeys in
--      UnitFrames/Effects/MSUF_UF_TextureLayer.lua) now arrives on the target
--      for all three layers.
--
-- Boots the real core and Options graph (menu_core_world.lua) and calls the
-- real copy functions. Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("copy_to_section_completeness_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local mw = MenuWorld.Open(root, flavor, { page = "home" })
local M, env, core = mw.M, mw.env, mw.core
local db = env.MSUF_DB

---------------------------------------------------------------------------
-- 1. Group Font Override
---------------------------------------------------------------------------
local GF = Check(core.GF, "group frame runtime missing")
local copyGroup = Check(M.GroupPage and M.GroupPage.CopyGroupSettings, "group Copy To missing")
local party, raid = db.gf_party, db.gf_raid
-- Everything the Fonts page writes into a group font override scope.
local SOURCE = {
    fontOverride = true, fontOutline = "NONE", fontMonochrome = true, fontSlug = false,
    fontTextAlpha = 0.7, fontBaselineOffset = 2, textBackdrop = false,
    fontShadowOpacity = 0.5, fontShadowDistance = 2,
    useGlobalFontColor = false, fontR = 0.2, fontG = 0.4, fontB = 0.6,
}
local TARGET = {
    fontOverride = true, fontOutline = "OUTLINE", fontMonochrome = false, fontSlug = false,
    fontTextAlpha = 1, fontBaselineOffset = 0, textBackdrop = true,
    fontShadowOpacity = 1, fontShadowDistance = 1,
    useGlobalFontColor = true, fontR = 1, fontG = 1, fontB = 1,
}
for key, value in pairs(SOURCE) do party[key] = value end
for key, value in pairs(TARGET) do raid[key] = value end
local raidWidth = raid.width
local function Resolved(kind)
    local shadowOn, shadowAlpha, shadowX, shadowY = GF.ResolveFontShadow(kind)
    local r, g, b = GF.ResolveFontColor(kind)
    return {
        flags = GF.ResolveFontFlags(kind), alpha = GF.ResolveFontTextAlpha(kind),
        baseline = GF.ResolveFontBaselineOffset(kind),
        shadow = table.concat({ tostring(shadowOn), tostring(shadowAlpha), tostring(shadowX), tostring(shadowY) }, " "),
        color = table.concat({ tostring(r), tostring(g), tostring(b) }, " "),
    }
end
local want = Resolved("party")
local before = Resolved("raid")
for field, value in pairs(want) do
    Check(before[field] ~= value, "precondition: Raid already resolves the same " .. field .. " as Party")
end
Check(copyGroup("party", "raid", { font = true }), "the Font Override copy did not run")
mw:RunTimers()
local got = Resolved("raid")
for field, value in pairs(want) do
    Check(got[field] == value, "after Copy To, Raid font " .. field .. " is " .. tostring(got[field])
        .. ", Party's is " .. tostring(value))
end
Check(raid.width == raidWidth, "the Font Override copy changed the Raid width")

---------------------------------------------------------------------------
-- 2. Unit Texture Layer
---------------------------------------------------------------------------
local copyUnit = Check(M.UnitPage and M.UnitPage.CopyUnitSettings, "unit Copy To missing")
-- The runtime's per-slot key universe, read from its key builder.
local handle = assert(io.open(root .. "/MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_TextureLayer.lua", "rb"))
local runtime = handle:read("*a"):gsub("\r\n", "\n")
handle:close()
local builder = Check(runtime:match("local function BuildSlotKeys%(prefix%)(.-)\nend"), "BuildSlotKeys not found")
local suffixes = {}
for name, suffix in builder:gmatch('(%w+) = prefix %.%. "(%w+)"') do
    Check(name == suffix, "slot key " .. name .. " is stored as " .. suffix)
    suffixes[#suffixes + 1] = suffix
end
Check(#suffixes >= 40, "only " .. #suffixes .. " texture layer keys parsed")
-- Rule values that differ from the target's; every other key gets a marker.
local RULES = { TargetOnly = true, HealthCondition = "BELOW", HealthThreshold = 0.8,
    HealthLowAlphaEnabled = true, HealthLowAlpha = 0.4, HealthAboveMode = "CLASS" }
local player, target = db.player, db.target
for slot, prefix in ipairs({ "texLayer", "texLayer2", "texLayer3" }) do
    for _, suffix in ipairs(suffixes) do
        local value = RULES[suffix]
        if value == nil then value = "copy-marker-" .. slot .. "-" .. suffix end
        player[prefix .. suffix] = value
        target[prefix .. suffix] = nil
    end
end
local applied = copyUnit("player", "target", { texlayer = true }, nil, true)
Check(applied, "the Texture Layer copy did not run")
-- The copy writes synchronously; the queued unit-frame apply it requests is
-- outside this contract (the offline runtime cannot draw the target frame).
local missing = {}
for _, prefix in ipairs({ "texLayer", "texLayer2", "texLayer3" }) do
    for _, suffix in ipairs(suffixes) do
        local key = prefix .. suffix
        if target[key] ~= player[key] then missing[#missing + 1] = key end
    end
end
table.sort(missing)
Check(#missing == 0, "Copy To left texture layer settings of Target behind: " .. table.concat(missing, ", "))

print("copy_to_section_completeness_smoke " .. flavor .. ": OK (group font override, "
    .. #suffixes .. " texture layer keys x3)")
