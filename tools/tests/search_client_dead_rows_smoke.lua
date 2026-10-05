-- search_client_dead_rows_smoke.lua <repoRoot> [flavor]
--
-- One static search index file serves several clients, so it carries rows for
-- controls only some of them build. Every row the search offers on a client
-- must name a control that client's page builds: opening any other row lands
-- on a page without it. Covered here for the Castbar and Colors pages, whose
-- client-only controls are the Interrupt Ready unit toggles and Focus Kick
-- (unit scopes), Empowered Casts (MSUF.Client.HasEmpoweredCasts), the tagged-mob
-- colors (MSUF.Client.SupportsTapDenied) and the resource extra colors (the
-- Resource Extras page's client lists).
--
-- Boots one client's real core and Options graph with the menu open
-- (menu_core_world.lua), builds each page hidden with every lazy section
-- drained, as the index generator does, and resolves every offered static row
-- through the real RuntimeControlCatalog.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = flavor .. ": " .. message end
    return condition
end

local PAGES = { "opt_castbar", "opt_colors" }

-- The GCD Bar section needs C_Spell.GetSpellCooldownDuration, which the shared
-- stubs leave out; every client running the Mainline index has it (12.x API).
-- The page and the search ask the same capability probe, so supplying it on
-- every client keeps the check honest either way.
local mw = MenuWorld.Open(root, flavor, { locale = "enUS", beforeCore = function(world)
    local spell = world.env.C_Spell
    world.env.C_Spell = setmetatable({ GetSpellCooldownDuration = function() return nil end }, { __index = spell })
end })
local M, env = mw.M, mw.env
env.InCombatLockdown = function() return false end
env.UnitAffectingCombat = function() return false end

local offered = {}
for _, page in ipairs(PAGES) do offered[page] = {} end
for _, rec in ipairs(M.Search._CoreAPI.GetSearchRecords()) do
    local list = rec.static and rec.exactTarget and offered[rec.key]
    if list then list[#list + 1] = rec end
end

local checked = 0
for _, page in ipairs(PAGES) do
    Check(#offered[page] > 20, page .. ": only " .. #offered[page] .. " static rows offered; the check would prove nothing")
    Check(M.BuildPageEntry(page, true) ~= nil, page .. " did not build")
    mw:RunTimers(20000)
    for _, rec in ipairs(offered[page]) do
        local exact = rec.exactTarget
        local _, widget = M.RuntimeControlCatalog.ResolveExactTarget(page, exact)
        if not widget and exact.settingKey then
            _, widget = M.RuntimeControlCatalog.FindBySettingKey(exact.settingKey, page, exact)
        end
        Check(widget ~= nil, ("%s offers '%s' (%s) but its page builds no such control"):format(page,
            tostring(rec.label), tostring(exact.settingKey or exact.actionKey or exact.controlId)))
        checked = checked + 1
    end
end

if #failures > 0 then
    error("search_client_dead_rows_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("search_client_dead_rows_smoke: ok (" .. flavor .. "; " .. checked
    .. " offered Castbar and Colors rows name controls their page builds)")
