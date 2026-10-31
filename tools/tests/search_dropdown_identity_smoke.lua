-- A dropdown value refresh must preserve its authored search identity while
-- function-valued choice providers follow the current editor state.
local root, flavor, locale = assert(arg[1]), arg[2] or "Mainline", arg[3] or "enUS"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "uf_player", locale = locale })
local M, api = mw.M, mw.M.Search._CoreAPI
local function Ready()
    api.GetSearchRecords()
    for _ = 1, 1000 do
        if #mw.world.widgets.timers == 0 then return end
        mw:RunTimers(1000)
    end
    error("search did not settle")
end
Ready()
assert(api.OpenSearchTarget("uf_player", "player status icons"))
Ready()
local id = "menu2.uf_player.unit.status.selected.iconstyle"
local catalog = assert(M.RuntimeControlCatalog.Get(id))
local widget, label = catalog.widget, "Visual style for this indicator"
assert(catalog.label == label, "selected value replaced the control catalog label")
local meta = assert(widget._msuf2SearchMeta)
local controlId, identityKey, help, keywords = meta.controlId, meta.identityKey, meta.help, meta.keywords
local choice = "SearchFirstChoice"
local function Values()
    return { { value = "TEST", text = "Stable selected label" }, { value = "OTHER", text = choice } }
end
widget:SetValues(Values)
local function Row()
    Ready()
    for _, row in ipairs(api.GetSearchRecords()) do
        if M.Search.StaticIndex.TargetField(row, "controlId") == id then return row end
    end
    error("dropdown lost its exact record")
end
widget:SetValue("TEST")
assert(Row().haystack:find("searchfirstchoice", 1, true), "initial choices were not indexed")
choice = "SearchSecondChoice"
widget:SetValue("TEST")
local row = Row()
assert(row.label == M.Tr(label), "selected choice renamed the live search result")
meta = assert(widget._msuf2SearchMeta)
assert(row.haystack:find("searchsecondchoice", 1, true), "dynamic choices stayed stale when the value was unchanged")
assert(not row.haystack:find("searchfirstchoice", 1, true), "obsolete choice survived re-registration")
assert(M.RuntimeControlCatalog.Get(id).label == label, "visible choice renamed the authored search label")
assert(meta.controlId == controlId and meta.identityKey == identityKey and meta.help == help and meta.keywords == keywords,
    "SetValues discarded authored navigation/help metadata")
print("search_dropdown_identity_smoke " .. flavor .. " " .. locale .. ": stable name, exact identity, fresh choices")
