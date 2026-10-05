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

print("copy_to_section_completeness_smoke " .. flavor .. ": OK (group font override)")
