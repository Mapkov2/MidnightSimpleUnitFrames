-- Cold search and warm exact routing use the player's actual mana-helper toggles.
local root, flavor, locale = assert(arg[1]), arg[2] or "Forever", arg[3] or "enUS"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home", locale = locale, beforeOptions = function(world)
    -- The shared generic stub is a callable table; the client exports a native function.
    world.env.C_DurationUtil = { CreateDuration = function() return { SetTimeFromStart = function() end } end }
end })
local M, api, checked = mw.M, mw.M.Search._CoreAPI, 0
local supported = flavor == "Forever" or flavor == "Vanilla" or flavor == "TBC"
local targets = {
    { "mana per 5 seconds", "bars.manaRegenPause" },
    { "mana per five seconds", "bars.manaRegenPause" },
    { "mana per 5", "bars.manaRegenPause" },
    { "MP5", "bars.manaRegenPause" },
    { "five second rule", "bars.manaRegenPause" },
    { "five-second rule", "bars.manaRegenPause" },
    { "5 second rule", "bars.manaRegenPause" },
    { "fsr", "bars.manaRegenPause" },
    { "Fünf-Sekunden-Regel", "bars.manaRegenPause" },
    { "Fünfsekundenregel", "bars.manaRegenPause" },
    { "mana pro 5 sekunden", "bars.manaRegenPause" },
    { "mana pro fünf sekunden", "bars.manaRegenPause" },
    { "mana alle 5 sekunden", "bars.manaRegenPause" },
    { "mana return pulse", "bars.manaGainPulse" },
    { "mana tick", "bars.manaRegenStyle" },
    { "mana regen tick", "bars.manaRegenStyle" },
    { "mana tick style", "bars.manaRegenStyle" },
    { "mana per 5 seconds style", "bars.manaRegenStyle" },
    { "mana tick width", "bars.manaRegenSparkWidth" },
    { "mana tick glow", "bars.manaRegenSparkAlpha" },
    { "mana tick breite", "bars.manaRegenSparkWidth" },
    { "mana tick leuchten", "bars.manaRegenSparkAlpha" },
    { "manaregeneration tick", "bars.manaGainPulse" },
}
local function Ready()
    for _ = 1, 1000 do
        -- Lazy accordion bindings can dirty the sliced index during timer drain.
        local records = api.GetSearchRecords()
        if #records > 0 and #mw.world.widgets.timers == 0 then return end
        mw:RunTimers(1000)
    end
    error("search index did not become ready")
end
local function Check(ok, message) checked = checked + 1 assert(ok, message) end
Ready()
for pass = 1, 2 do
    Ready()
    for _, target in ipairs(targets) do
        local rows = api.SearchPages(target[1])
        local found, rank
        for i, row in ipairs(rows) do
            if row.exactTarget and row.exactTarget.settingKey == target[2] then found, rank = row, i break end
        end
        Check((found ~= nil) == supported, flavor .. ": query support mismatch " .. target[1])
        if found then
            Check(rank == 1, "mana toggle must rank first: " .. target[1] .. " at " .. rank)
            if pass == 1 then Check(not M.cache.classpower, "cold search built the resource page") end
        end
    end
    if supported then
        local row = api.SearchPages("mana per five seconds")[1]
        local opened, anchor, exact = api.OpenSearchTarget(row.key, "mana per five seconds", row.label, nil, row.route, row.exactTarget)
        Ready()
        Check(opened and anchor and exact, "five-second rule exact navigation failed")
        local record, widget = M.RuntimeControlCatalog.ResolveExactTarget(row.key, row.exactTarget)
        Check(record and widget and record.settingKey == "bars.manaRegenPause", "search opened the wrong mana toggle")
    end
end
print("mana_regen_search_smoke " .. flavor .. " " .. locale .. ": " .. checked .. " checks passed")
