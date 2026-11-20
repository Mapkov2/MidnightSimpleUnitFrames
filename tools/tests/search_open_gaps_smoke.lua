-- Cold discovery opens the real control without executing its action.
local root, flavor, locale = assert(arg[1]), arg[2] or "Mainline", arg[3] or "enUS"
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = World.Open(root, flavor, { page = "home", locale = locale })
local M, api = mw.M, mw.M.Search._CoreAPI
assert(mw.core.FinalizeLocale() == locale)
-- Radius two counts a swap plus a missing character consistently across scripts.
-- Alternate lengths to catch stale edges in reused edit-distance rows.
local within = M.Search._RoutingContext.SearchEditDistanceWithin
for _, case in ipairs({
    {"portrait", "portriatx", 2, true}, {"portrait", "portriatx", 1, false},
    {"separator", "seapraor", 2, true}, {"Schriftart", "Scrhiftrt", 2, true},
    {"écriture", "écirturex", 2, true}, {"abcdef", "zyxdef", 2, false},
    {"", "xy", 2, true}, {"longstring", "", 2, false}, {"ab", "ba", 0, false},
}) do
    assert(within(case[1], case[2], case[3]) == case[4], case[1] .. " vs " .. case[2])
    assert(within(case[2], case[1], case[3]) == case[4], case[2] .. " vs " .. case[1])
end
local general = M.EnsureDB().general
general.classPowerPreviewGuidesEnabled, general.classPowerPreviewAnimate = false, false
local function Ready()
    api.GetSearchRecords()
    for _ = 1, 1000 do
        if #mw.world.widgets.timers == 0 then return end
        mw:RunTimers(1000)
    end
    error("search did not settle")
end
local function Find(key, suffix)
    Ready()
    for _, row in ipairs(api.GetSearchRecords()) do
        local target = row.exactTarget or {}
        if key and target.settingKey == key or suffix and (target.controlId or ""):sub(-#suffix) == suffix then return row end
    end
end
local function Ranked(row)
    Ready()
    local wanted = row.exactTarget.controlId
    for i, result in ipairs(api.SearchPages(row.label)) do
        if i > 6 then break end
        if result.exactTarget and result.exactTarget.controlId == wanted then return true end
    end
    return false
end
if flavor == "Mainline" then
    local query = locale == "deDE" and "klsasenressouce" or "seapraor"
    local setting = locale == "deDE" and "bars.showClassPower" or "bars.classPowerTickWidth"
    Ready()
    local first = api.SearchPages(query)[1]
    assert(first and first.exactTarget and first.exactTarget.settingKey == setting, "whole-label typo: " .. query)
end
local keys = { "general.classPowerPreviewGuidesEnabled", "general.classPowerPreviewAnimate" }
for _, key in ipairs(keys) do local row=assert(Find(key), "cold setting missing: "..key); assert(Ranked(row), "cold query rank: "..key) end
for _, suffix in ipairs({ "castbar.text.color.reset", "status.text.color.reset", "spell.custom.add" }) do
    local row=assert(Find(nil, suffix), "cold action missing: "..suffix)
    assert(Ranked(row), "cold action query rank: "..suffix)
end
assert(not M.cache.classpower, "cold discovery built the preview")
for _, key in ipairs(keys) do
    local row = assert(Find(key))
    local selected = api.OpenSearchTarget(row.key, row.label, row.label, nil, row.route, row.exactTarget)
    Ready()
    assert(selected, "page did not open: " .. key)
    local record = assert(M.RuntimeControlCatalog.Get(row.exactTarget.controlId))
    assert(record.widget and record.widget:IsVisible(), "real preview control stayed hidden: " .. key)
end
for _, suffix in ipairs({ "castbar.text.color.reset", "status.text.color.reset", "spell.custom.add" }) do
    local row = assert(Find(nil, suffix))
    local selected, anchored, exact = api.OpenSearchTarget(row.key, row.label, row.label, nil, row.route, row.exactTarget)
    Ready()
    assert(selected and anchored and exact, "action route failed: " .. suffix)
    local record = assert(M.RuntimeControlCatalog.Get(row.exactTarget.controlId))
    assert(record.widget and record.widget:IsVisible(), "action target hidden: " .. suffix)
end
assert(general.classPowerPreviewGuidesEnabled == false and general.classPowerPreviewAnimate == false, "navigation changed preview preferences")
print("search_open_gaps_smoke " .. flavor .. " " .. locale .. ": cold controls and navigation passed")
