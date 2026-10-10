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
--   * a link into a selectable view (Bars scope, Texture Layer slot and card,
--     group status indicator, corner slot) also opens from another view: the
--     route selects the view the link names;
--   * both renderers draw every linked bullet as a link, not only Highlights:
--     See New Features shows one link button per linked bullet of the release,
--     the dashboard card one per linked bullet of its compact entries, and
--     clicking a linked change bullet on the page opens its control.
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
    ["uf_arena menu2.uf_arena.unit.trinket.show"] = { Vanilla = true, Forever = true },
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
    ["gf_layout menu2.gf_layout.group.field.buffcoverageglow party"] =
        { Mainline = true, Vanilla = true, TBC = true, Mists = true },
    ["gf_layout menu2.gf_layout.group.field.buffcoveragecombat party"] =
        { Mainline = true, Vanilla = true, TBC = true, Mists = true },
    -- Midnight resource helpers (the Resource Extras page's client lists).
    ["classpower menu2.classpower.advanced.resource.extras.show.ignore.pain"] =
        { Forever = true, Vanilla = true, TBC = true, Mists = true },
    ["classpower menu2.classpower.advanced.resource.extras.arcane.window.text"] =
        { Forever = true, Vanilla = true, TBC = true, Mists = true },
    ["classpower menu2.classpower.advanced.behavior.sweeping"] =
        { Forever = true, Vanilla = true, TBC = true, Mists = true },
    ["uf_boss menu2.uf_boss.unit.boss_target_highlight.style"] = { Vanilla = true, TBC = true },
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
    -- Native visibility includes hidden ancestors. The shared widget fixture
    -- checks only the widget itself, masking warm Colors category navigation.
    world.widgets.Methods.IsVisible = function(frame)
        while frame do
            if frame.IsShown and not frame:IsShown() then return false end
            frame = frame.GetParent and frame:GetParent()
        end
        return true
    end
end })
local M, env = mw.M, mw.env
env.InCombatLockdown = function() return false end
env.UnitAffectingCombat = function() return false end

-- Both bundled views show stable release history, including the last Retail
-- releases before Classic 6.50. Keep the current release visible on beta builds.
for _, data in ipairs({ env.MSUF_Changelog, env.MSUF_FullChangelog }) do
    local versions = {}
    for i, release in ipairs(data.entries) do
        Check(not versions[release.version], "duplicate historical release " .. release.version)
        versions[release.version] = i
        Check(i == 1 or release.version:match("^%d[%d%.]*$"), "prerelease in visible history: " .. release.version)
        if release.version == "6.20" then Check(release.date == "2026-09-11", "6.20 release date changed") end
        if release.version == "6.21" then Check(release.date == "2026-09-22", "6.21 release date changed") end
    end
    if data == env.MSUF_FullChangelog then
        Check(versions["6.20"] and versions["6.21"] and versions["6.21"] < versions["6.20"],
            "stable 6.21 and 6.20 patch notes missing or out of order")
    end
end
local fullEntries = env.MSUF_FullChangelog.entries
Check(fullEntries[#fullEntries].version == "6.02", "full history floor changed")

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
        local contracts = "|" .. row.contracts .. "|"
        local wildcard = "|" .. kind .. "=" .. tostring(link.prepareValue) .. "=*|"
        if not contracts:find("|" .. contract .. "|", 1, true)
            and not (row.setting == link.settingKey and contracts:find(wildcard, 1, true)) then
            return "contract " .. contract .. " not published"
        end
    end
end

-- Resource links must select their owning workspace, even when another resource
-- was selected. A successful exact-control lookup alone also accepts hidden views.
local RESOURCE_VIEWS = {
    classpower_display = "class", classpower_behavior = "class", classpower_visuals = "class", classpower_visibility = "class",
    classpower_detached_power = "power", classpower_resource_marks = "extras",
    classpower_resource_extras = "extras", classpower_resource_pain = "extras", classpower_resource_arcane = "extras",
}
local RESOURCE_EFFECTS = { classpower_resource_marks = "marks", classpower_resource_extras = "cost",
    classpower_resource_pain = "pain", classpower_resource_arcane = "arcane" }
local resourceLinks, resourceOpens = 0, 0
for _, release in ipairs(env.MSUF_FullChangelog.entries) do
    for _, section in ipairs(release.sections or {}) do
        for _, bullet in ipairs(section.bullets or {}) do
            local link = type(bullet) == "table" and bullet.link
            if link and link.pageKey == "classpower" then
                resourceLinks = resourceLinks + 1
                local expected = RESOURCE_VIEWS[link.sectionId]
                Check(expected ~= nil, "resource section needs a workspace expectation: " .. link.sectionId)
                Check(link.prepareKind == "classPowerWorkspace" and link.prepareValue == expected,
                    "resource link omits its workspace contract: " .. link.controlId)
                local clients = ABSENT[link.pageKey .. " " .. link.controlId]
                if expected and not (clients and clients[flavor]) then
                    for _, source in ipairs({ "cold", "class", "power", "hp", "mana", "extras" }) do
                        if source == "cold" then M.InvalidatePage("classpower") end
                        M.ClassPowerWorkspace.Select(source == "cold" and "hp" or source)
                        M.ResourceExtrasPreview.Select("marks")
                        local ok = M.OpenChangelogMenuLink(link)
                        mw:RunTimers()
                        resourceOpens = resourceOpens + 1
                        local ui = M.ClassPowerWorkspace.current
                        local prefix = release.version .. " " .. link.controlId .. " from " .. source .. ": "
                        Check(ok, prefix .. "link did not open")
                        Check(ui and ui.selected == expected and ui.selector:GetValue() == expected,
                            prefix .. "wrong resource selected")
                        local body = M.cache.classpower and M.cache.classpower.sections[link.sectionId]
                        local accordion = body and body._msuf2CollapsibleEntry
                        Check(accordion and accordion.open and accordion.outer:IsShown(), prefix .. "target section hidden/collapsed")
                        if ui then
                            for kind, entries in pairs(ui.entries) do
                                for _, item in ipairs(entries) do
                                    Check(item.outer:IsShown() == (kind == expected), prefix .. "wrong workspace visibility")
                                end
                            end
                            for _, button in ipairs(ui.selector.buttons) do
                                Check(button._msuf2Active == (button._msuf2Value == expected), prefix .. "wrong selector highlight")
                            end
                        end
                        local effect = RESOURCE_EFFECTS[link.sectionId]
                        if effect then Check(M.ResourceExtrasPreview.Selection() == effect, prefix .. "wrong helper preview") end
                        local problem = StaticProblem(link)
                        Check(problem == nil, prefix .. tostring(problem))
                    end
                end
            elseif link and link.sectionId == "colors_resource_extras" then
                for _, source in ipairs({ "unit", "group", "cast", "auras" }) do
                    M.SelectPage("opt_colors")
                    M.ColorsSetPainterCategory(source)
                    Check(M.OpenChangelogMenuLink(link), "resource color link did not open from " .. source)
                    mw:RunTimers()
                    Check(M.colorsPainterCategory == "resources", "resource color link kept category " .. source)
                end
            end
        end
    end
end
Check(resourceLinks > 0 and resourceOpens > 0, "resource link regression exercised no controls")

local restoredLinks = 0
for _, release in ipairs(fullEntries) do
    if release.version == "6.20" or release.version == "6.21" then
        for _, section in ipairs(release.sections) do
            for _, bullet in ipairs(section.bullets) do
                local link = type(bullet) == "table" and bullet.link
                if link then
                    restoredLinks = restoredLinks + 1
                    local key = link.pageKey .. " " .. link.controlId
                    local clients = ABSENT[key .. " " .. tostring(link.prepareValue or "")] or ABSENT[key]
                    local missing = clients and clients[flavor]
                    local opened = M.OpenChangelogMenuLink(link)
                    mw:RunTimers()
                    Check(opened == not missing, "restored " .. release.version .. " link availability: " .. key)
                    if not missing then
                        local problem = StaticProblem(link)
                        Check(problem == nil, "restored " .. release.version .. " exact contract: " .. key .. " " .. tostring(problem))
                    end
                end
            end
        end
    end
end
Check(restoredLinks == 7, "restored 6.20/6.21 link coverage changed")

--- Link buttons (T.StyleFeatureLink marks them) the page builds, in build order.
local function LinkButtons(pageKey, open)
    local first = #mw.world.widgets.frames + 1
    open()
    mw:RunTimers()
    local wrapper = M.cache[pageKey] and M.cache[pageKey].wrapper
    local out = {}
    if not Check(wrapper ~= nil and M.activeKey == pageKey, "the " .. pageKey .. " page did not open") then return out end
    local frames = mw.world.widgets.frames
    for i = first, #frames do
        local frame, node = frames[i], frames[i]
        while node and node ~= wrapper do node = node.GetParent and node:GetParent() or nil end
        if node and frame._msuf2ChangelogLinkOutline then out[#out + 1] = frame end
    end
    return out
end

local data = env.MSUF_FullChangelog
local entry = type(data) == "table" and type(data.entries) == "table" and data.entries[1]
if Check(type(entry) == "table" and type(entry.sections) == "table", "MSUF_FullChangelog has no current release entry") then
    local linked, linkless, opened, absent = 0, 0, 0, 0
    local order = {}
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
                order[#order + 1] = { link = link, title = title, missing = missing }
                local ok = M.OpenChangelogMenuLink(link) == true
                mw:RunTimers()
                if missing then
                    absent = absent + 1
                    Check(not ok, "ABSENT says this client lacks " .. key .. ", but the link opened it (drop the client)")
                elseif Check(ok, title .. ": the link did not open its control: " .. key .. " (" .. text:sub(1, 60) .. ")") then
                    opened = opened + 1
                    local problem = StaticProblem(link)
                    Check(problem == nil, title .. ": " .. key .. " breaks its exact static contract: " .. tostring(problem))
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

    -- From another view: each view link must select the view it names.
    local OTHER_VIEW = {
        barsScope = function() env.MSUF_DB.general.hpPowerTextSelectedKey = "gf_party" end,
        unitTextureLayer = function(unit) M.unitTexLayerSlot[unit], M.unitTexLayerTab[unit] = 2, "rules" end,
        groupStatus = function()
            M.SetMenuStateValue("gfScope", "raid")
            M.SetMenuStateValue("gfStatusIconSelection", "roleIcon")
        end,
        groupCornerSlot = function()
            M.SetMenuStateValue("gfScope", "raid")
            M.SetMenuStateValue("gfCornerSlotSelection", "BR")
        end,
    }
    local switched = 0
    for _, item in ipairs(order) do
        local perturb = OTHER_VIEW[item.link.prepareKind or ""]
        if perturb and not item.missing then
            M.unitTexLayerSlot, M.unitTexLayerTab = M.unitTexLayerSlot or {}, M.unitTexLayerTab or {}
            perturb((item.link.pageKey:gsub("^uf_", "")))
            local ok = M.OpenChangelogMenuLink(item.link) == true
            mw:RunTimers()
            switched = switched + 1
            Check(ok, ("%s: the %s link did not open from another view: %s"):format(item.title,
                item.link.prepareKind, item.link.controlId))
        end
    end

    -- See New Features: one link button per linked bullet, in bullet order.
    local pageButtons = LinkButtons("changelog", function() return M.OpenSeeNewFeatures() end)
    Check(#pageButtons == linked, ("See New Features draws %d link buttons for %d linked bullets of %s")
        :format(#pageButtons, linked, tostring(entry.version)))
    if #pageButtons == linked then
        -- Click the last linked change bullet this client builds.
        for i = #order, 1, -1 do
            local item = order[i]
            if item.title ~= "Highlights" and not item.missing then
                local onClick = pageButtons[i]:GetScript("OnClick")
                if Check(onClick ~= nil, "the link button of a change bullet has no click handler") then
                    onClick(pageButtons[i], "LeftButton")
                    mw:RunTimers()
                    Check(M.activeKey == item.link.pageKey, ("clicking the %s link landed on %s, not %s")
                        :format(item.title, tostring(M.activeKey), item.link.pageKey))
                end
                break
            end
        end
    end

    -- Dashboard card: one link button per linked bullet of its compact entries.
    local compact, expected = env.MSUF_Changelog, 0
    for e = 1, math.min(4, #(compact and compact.entries or {})) do
        for _, section in ipairs(compact.entries[e].sections or {}) do
            for _, bullet in ipairs(section.bullets or {}) do
                if type(bullet) == "table" and type(bullet.link) == "table" then expected = expected + 1 end
            end
        end
    end
    mw.core.FirstLoad6:Complete("fixture")
    M.dashboardChangelogOpen = true
    M.InvalidatePage("home")
    local homeButtons = LinkButtons("home", function() return M.SelectPage("home") end)
    Check(expected >= linked and #homeButtons == expected, ("the dashboard card draws %d link buttons for %d linked bullets")
        :format(#homeButtons, expected))
    if #failures == 0 then
        print(("changelog_release_links_smoke: ok (%s, %s: %d links, %d opened, %d absent on this client, %d without a menu control;"
            .. " %d from another view; %d page and %d dashboard link buttons; %d historical resource links/%d resource opens)")
            :format(flavor, tostring(entry.version), linked, opened, absent, linkless, switched, #pageButtons, #homeButtons,
                resourceLinks, resourceOpens))
    end
end

if #failures > 0 then
    error("changelog_release_links_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
