-- Cold discovery opens the real control without executing its action.
local root, flavor, locale = assert(arg[1]), arg[2] or "Mainline", arg[3] or "enUS"
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = World.Open(root, flavor, { page = "home", locale = locale })
local M, api = mw.M, mw.M.Search._CoreAPI
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
