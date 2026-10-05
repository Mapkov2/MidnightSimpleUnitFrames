-- aura_custom_workspace_translate_once_smoke.lua <repoRoot> <flavor>
--
-- The Custom Aura workspace (MSUF_Menu2_Auras_CustomWorkspace.lua) translates
-- each text once. Its theme font strings translate whatever SetText gets
-- (T.Font), so composed status lines (M.Format output), spell names, the
-- "Name (#id)" entries and the "#1" ranks have to go through
-- T.SetTranslatedText; otherwise every non-English session logs them as
-- missing keys (M.GetLocaleCoverage, /msuf locale) and a spell name that is a
-- locale key would be shown mistranslated. menu_pages_translate_once_smoke
-- builds every page in its default state, which never opens these tools with
-- entries in their lists, so this smoke builds them directly:
--   Defensive Buffs (player, Custom 4): the custom list and the Setup source line,
--   Dots on target (target, Custom 4): the DoT list and the Setup source line,
--   Custom 1 (target): the Whitelist rows and the Setup count line.
--
-- Under deDE every translation carries a marker byte, so translating marked
-- text again is a second lookup; a "#<n>" rank must not be looked up at all.
-- Each shown text is checked too: it is the translated text, painted once.
--
-- Boots the real core and Options graph (menu_core_world.lua).
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("aura_custom_workspace_translate_once_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local MARK = "\030"
local WORKSPACE = "MSUF_Menu2_Auras_CustomWorkspace.lua"
local recording, doubles, ranks = false, {}, {}
local function WorkspaceLine()
    for level = 3, 40 do
        local info = debug.getinfo(level, "Sl")
        if not info then break end
        if info.source:find(WORKSPACE, 1, true) then return WORKSPACE .. ":" .. tostring(info.currentline) end
    end
end
local mw = MenuWorld.Open(root, flavor, { page = "home", locale = "deDE", beforeOptions = function(world)
    Check(world.core.FinalizeLocale() == "deDE", "the deDE pack was not selected")
    for key, value in pairs(world.env.MSUF_L) do
        if type(key) == "string" and type(value) == "string" then rawset(world.env.MSUF_L, key, MARK .. value) end
    end
    -- The Options files keep the translator they find at load.
    local Translate = world.core.Translate
    world.core.Translate = function(text, ...)
        if recording and type(text) == "string" then
            local site = WorkspaceLine()
            if site and text:find(MARK, 1, true) then doubles[site] = doubles[site] or text:gsub(MARK, "~") end
            if site and text:find("^#%d+$") then ranks[site] = text end
        end
        return Translate(text, ...)
    end
end })
local M, env, core = mw.M, mw.env, mw.core
local Model = Check(core.MSUF_Auras3 and core.MSUF_Auras3.MenuModel, "aura menu model missing")

-- Borrow a real page context for the tools (they build into any page builder).
local pageCtx
local miscSpec = M.pages.opt_misc
local miscBuild = miscSpec.build
miscSpec.build = function(ctx, ...)
    pageCtx = pageCtx or ctx
    return miscBuild(ctx, ...)
end
Check(mw:Select("opt_misc"), "Miscellaneous page did not open")
miscSpec.build = miscBuild
Check(pageCtx, "no page context was captured")

-- Two custom IDs per list: the spell names do not resolve offline, so each
-- entry reads "<translated Spell> (#id)", a translated, composed text.
for _, scope in ipairs({ { "player", 4 }, { "target", 4 }, { "target", 1 } }) do
    Check(Model.AddCustomContainerSpell(scope[1], scope[2], "424242", true), "custom ID was not added to "
        .. scope[1] .. " " .. scope[2])
    Check(Model.AddCustomContainerSpell(scope[1], scope[2], "434343", true), "second custom ID was not added")
end

local shown = {}
local frames = mw.world.widgets.frames
local before = #frames
recording = true
for _, tool in ipairs({ { "player", 4, "defensives" }, { "player", 4, "setup" }, { "target", 4, "dots" },
    { "target", 4, "setup" }, { "target", 1, "whitelist" }, { "target", 1, "setup" } }) do
    M.BuildAuras3CompactCustomWorkspace(pageCtx, M.Widgets.PageBuilder(pageCtx), tool[1], tool[2], tool[3])
end
mw:RunTimers()
recording = false
for i = before + 1, #frames do
    for _, region in ipairs(frames[i].regions or {}) do
        local text = region.GetText and region:GetText()
        if type(text) == "string" and text ~= "" then shown[#shown + 1] = text end
    end
end

local list = {}
for site, text in pairs(doubles) do list[#list + 1] = site .. "  " .. text end
table.sort(list)
Check(#list == 0, #list .. " workspace sites translated text again:\n  " .. table.concat(list, "\n  "))
list = {}
for site, text in pairs(ranks) do list[#list + 1] = site .. "  " .. text end
table.sort(list)
Check(#list == 0, "list ranks were looked up as locale keys:\n  " .. table.concat(list, "\n  "))

-- What the lists and status lines show is the translated text (marked once).
local function Shown(pattern)
    for _, text in ipairs(shown) do
        if text:find(pattern) then return text end
    end
end
local entry = Check(Shown("%(#424242%)$"), "no list row shows the custom entry")
Check(entry:sub(1, 1) == MARK and not entry:find(MARK, 2, true), "list row text is not translated once: " .. entry)
Check(Shown("^#1$") and Shown("^#2$"), "the list ranks are not shown as #1 and #2")
for _, key in ipairs({ "Source: player buffs · %d / %d predefined enabled · %d custom · passive talent procs included",
    "Source: this UnitFrame · Ownership: only mine · Harmful DoTs only · %d selected",
    "%d whitelisted spells · style remains live in Menu Preview and Edit Mode." }) do
    local translated = Check(env.MSUF_L[key], "precondition: deDE has no entry for " .. key)
    -- The translated format as a pattern: literal text, any number for %d.
    local pattern = "^" .. translated:gsub("%%d", "NUMBERSLOT"):gsub("%p", "%%%0"):gsub("NUMBERSLOT", "%%d+") .. "$"
    local text = Check(Shown(pattern), "status line missing: " .. key)
    Check(not text:find(MARK, 2, true), "status line is translated twice: " .. text)
end

print("aura_custom_workspace_translate_once_smoke " .. flavor .. ": OK (" .. #shown .. " texts)")
