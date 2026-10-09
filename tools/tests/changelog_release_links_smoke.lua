-- changelog_release_links_smoke.lua <repoRoot> <flavor>
--
-- The current release's notes (CHANGELOG.md, generated into
-- MSUF_ChangelogFull.lua, entries[1]) on one client's real core and Options
-- graph with the menu open:
--   * every bullet outside the "Bug Fixes - ..." and "Performance" sections
--     declares its route policy: an exact menu link, or
--     `<!-- msuf-menu-link: none -->` (generated as linkless = true) when no
--     menu control owns it;
--   * every link opens and highlights its control through the real link
--     opener the See New Features page and the dashboard call
--     (M.OpenChangelogMenuLink: exact control, section, setting key, prepare
--     contract), except on the clients ABSENT names for that control. An
--     absence that resolves fails, so the table stays true; no control may be
--     absent everywhere;
--   * a link that opens also passes the release packager's static contract
--     (.github/scripts/assert-classic-changelog-links.ps1) against the search
--     index this client loads: the row exists, the section matches, the setting
--     key matches the row or one of its published prepare contracts.
-- Plain Lua 5.1, repo root as arg 1, flavor as arg 2.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local CLIENTS = { "Mainline", "Forever", "Vanilla", "TBC", "Mists" }

-- Controls a client does not build, keyed "pageKey controlId" or
-- "pageKey controlId prepareValue". Facts about the menu, not about one release.
local ABSENT = {
    -- Arena Frames: Midnight (arena1-3), TBC and Mists (arena1-5).
    ["uf_arena menu2.uf_arena.unit.basics.enabled"] = { Vanilla = true, Forever = true },
    ["uf_arena menu2.uf_arena.unit.castbar.feature.msuf2_castbar_icon"] = { Vanilla = true, Forever = true },
    -- Threat % and Pet Happiness: MSUF.Client.SupportsThreatText / SupportsPetHappiness
    -- (Classic Era, TBC and WoW Forever).
    ["uf_target menu2.uf_target.unit.status.selected.enabled statusThreat"] = { Mainline = true, Mists = true },
    ["uf_pet menu2.uf_pet.unit.status.selected.enabled statusPetHappiness"] = { Mainline = true, Mists = true },
    -- Gray tagged mobs: MSUF.Client.SupportsTapDenied (every client but Midnight).
    ["opt_colors menu2.opt.colors.advanced.npc.tap.denied.gray"] = { Mainline = true },
    -- WoW Forever only: character name parts, the Swing Timers page, group buff coverage.
    ["opt_fonts menu2.opt.fonts.global.name.shortening.character.name.parts"] =
        { Mainline = true, Vanilla = true, TBC = true, Mists = true },
    ["swingtimers menu2.swingtimers.swing.enabled"] = { Mainline = true, Vanilla = true, TBC = true, Mists = true },
    ["swingtimers menu2.swingtimers.swing.main.offhand.lane"] = { Mainline = true, Vanilla = true, TBC = true, Mists = true },
    ["gf_layout menu2.gf_layout.group.field.buffcoverageenabled party"] =
        { Mainline = true, Vanilla = true, TBC = true, Mists = true },
    -- Midnight resource helpers (the Resource Extras page's client lists).
    ["classpower menu2.classpower.advanced.resource.extras.show.ignore.pain"] =
        { Forever = true, Vanilla = true, TBC = true, Mists = true },
    ["classpower menu2.classpower.advanced.resource.extras.arcane.window.text"] =
        { Forever = true, Vanilla = true, TBC = true, Mists = true },
    -- Aura tooltip caster names: the native Mainline tooltip option.
    ["opt_misc menu2.opt.misc.global.setting.tooltip.show.aura.caster.names"] = { Vanilla = true, TBC = true, Mists = true },
    -- GCD bar: WoW Forever arms it only while its spell data has the GCD spell
    -- (M.CastbarGCDBarSupported); the harness supplies the Duration API everywhere.
    ["opt_castbar menu2.opt.castbar.global.gcd.gcd.bar.detached"] = { Forever = true },
    -- Focus Kick: Classic Era has no focus unit.
    ["opt_castbar menu2.opt.castbar.global.focus.kick.focus.kick.show.castbar"] = { Vanilla = true },
    -- Allied boss frames: the "boss" frame scope (clients with boss units).
    ["gf_layout menu2.gf_layout.group.field.friendlybossenabled party"] = { Vanilla = true, TBC = true },
}

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = flavor .. ": " .. message end
    return condition
end

for key, clients in pairs(ABSENT) do
    local present = 0
    for i = 1, #CLIENTS do
        if not clients[CLIENTS[i]] then present = present + 1 end
    end
    Check(present > 0, "ABSENT names every client for " .. key .. "; such a control cannot be linked")
end

-- The GCD Bar section needs C_Spell.GetSpellCooldownDuration, which the shared
-- stubs leave out (as in search_client_dead_rows_smoke).
local mw = MenuWorld.Open(root, flavor, { locale = "enUS", beforeCore = function(world)
    local spell = world.env.C_Spell
    world.env.C_Spell = setmetatable({ GetSpellCooldownDuration = function() return nil end }, { __index = spell })
end })
local M, env = mw.M, mw.env
env.InCombatLockdown = function() return false end
env.UnitAffectingCombat = function() return false end

-- The search index this client loads, parsed like the release packager does.
local INDEX = {}
do
    local blob = assert(M.Search and M.Search.StaticIndexBlob, "no static search index loaded")
    for line in blob:gmatch("[^\n]+") do
        local fields, start = {}, 1
        for _ = 1, 11 do
            local tab = line:find("\t", start, true)
            if not tab then break end
            fields[#fields + 1] = line:sub(start, tab - 1)
            start = tab + 1
        end
        if #fields == 11 and fields[8]:sub(1, 3) == "id\031" then
            INDEX[fields[8]] = { setting = fields[4], section = fields[9], kinds = fields[10], contracts = fields[11] }
        end
    end
end

local function Identity(pageKey, controlId)
    local encoded = controlId:gsub("%%", "%%25"):gsub("\031", "%%1F"):gsub("%.", "%%2E")
    return "id\031" .. pageKey .. "\031" .. encoded
end

local function StaticProblem(link)
    local row = INDEX[Identity(link.pageKey, link.controlId)]
    if not row then return "no row in this client's search index" end
    if row.section ~= link.sectionId then return "section " .. link.sectionId .. " ~= row " .. row.section end
    if row.setting ~= "" and row.setting ~= link.settingKey then return "setting " .. link.settingKey .. " ~= row " .. row.setting end
    local kind = link.prepareKind or ""
    if row.setting == "" and kind == "" then return "dynamic control without a prepare contract" end
    if kind ~= "" then
        if not ("," .. row.kinds .. ","):find("," .. kind .. ",", 1, true) then return "prepare kind " .. kind .. " not published" end
        local contract = kind .. "=" .. tostring(link.prepareValue) .. "=" .. link.settingKey
        if not ("|" .. row.contracts .. "|"):find("|" .. contract .. "|", 1, true) then return "contract " .. contract .. " not published" end
    end
end

local data = env.MSUF_FullChangelog
local entry = type(data) == "table" and type(data.entries) == "table" and data.entries[1]
if Check(type(entry) == "table" and type(entry.sections) == "table", "MSUF_FullChangelog has no current release entry") then
    local linked, linkless, opened, absent = 0, 0, 0, 0
    for _, section in ipairs(entry.sections) do
        local title = tostring(section.title or "")
        local exempt = title:find("^Bug Fixes") or title:find("^Fixes") or title == "Performance"
        for _, bullet in ipairs(section.bullets or {}) do
            local text = type(bullet) == "table" and tostring(bullet.text) or tostring(bullet)
            local link = type(bullet) == "table" and type(bullet.link) == "table" and bullet.link or nil
            if link then
                linked = linked + 1
                local key = link.pageKey .. " " .. link.controlId
                local clients = ABSENT[key .. " " .. tostring(link.prepareValue or "")] or ABSENT[key]
                local missing = clients and clients[flavor]
                local ok = M.OpenChangelogMenuLink(link) == true
                mw:RunTimers()
                if missing then
                    absent = absent + 1
                    Check(not ok, "ABSENT says this client lacks " .. key .. ", but the link opened it (drop the client)")
                elseif Check(ok, title .. ": the link did not open its control: " .. key .. " (" .. text:sub(1, 60) .. ")") then
                    opened = opened + 1
                    local problem = StaticProblem(link)
                    Check(problem == nil, title .. ": " .. key .. " breaks the packager's static contract: " .. tostring(problem))
                end
            elseif type(bullet) == "table" and bullet.linkless == true then
                linkless = linkless + 1
            else
                Check(exempt, title .. ": the bullet declares no route policy (add a msuf-menu-link or"
                    .. " msuf-menu-link: none): " .. text:sub(1, 80))
            end
        end
    end
    Check(linked > 0, "the current release has no linked bullet; the check would prove nothing")
    if #failures == 0 then
        print(("changelog_release_links_smoke: ok (%s, %s: %d links, %d opened, %d absent on this client, %d without a menu control)")
            :format(flavor, tostring(entry.version), linked, opened, absent, linkless))
    end
end

if #failures > 0 then
    error("changelog_release_links_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
