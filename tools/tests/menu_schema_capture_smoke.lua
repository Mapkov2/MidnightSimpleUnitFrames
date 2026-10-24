-- Reused preview widgets retain separate declaration evidence for each catalog ID.
local root = assert(arg[1])
local Capture = assert(loadfile(root .. '/tools/menu_schema_capture.lua'))()
local M = { activeKey = 'first', ControlSchema = {} }
function M.ControlSchema.Bind(_, widget, spec) widget._msuf2ControlSchema = spec; return widget end
function M.ControlSchema.Custom(widget, spec) widget._msuf2ControlSchema = spec; return widget end
function M.PageKeyForWidget() return M.activeKey end
__MSUF_WatchSchema(M)
local widget, records, byId = {}, {}, {}
for _, page in ipairs({ 'first', 'second' }) do
    M.activeKey = page
    local id = 'menu2.' .. page .. '.preview.zoom'
    M.ControlSchema.Custom(widget, { id = id, kind = 'slider', scope = page,
        applyDomain = 'menuState', ephemeralReason = 'Changes preview zoom only.' })
    local record = { controlId = id, pageKey = page, kind = 'slider', classification = 'ephemeral' }
    records[#records + 1], byId[id] = record, { widget = widget }
    -- Some builders rewrite the same spec table before reusing the widget.
    if page == 'first' then widget._msuf2ControlSchema.id = 'renamed.before.reuse' end
end
local undeclared = { controlId = 'menu2.third.preview.zoom', pageKey = 'third',
    kind = 'slider', classification = 'ephemeral' }
records[#records + 1], byId[undeclared.controlId] = undeclared, { widget = widget }
widget._msuf2RuntimeControlRecord = records[2]
local Catalog = {}
function Catalog.GetRecords() return records end
function Catalog.Get(id) return byId[id] end
Capture.Start(M, Catalog)
local data = Capture.Data()
for _, page in ipairs({ 'first', 'second' }) do
    local row = assert(data['menu2.' .. page .. '.preview.zoom'])
    assert(not row.observationIssues, page .. ': another page overwrote the actual declaration')
    assert(row.scope == page and row.schemaId == row.controlId, page .. ': wrong declaration captured')
end
local wrong = assert(data[undeclared.controlId])
assert(wrong.observationIssues and wrong.observationIssues['invalid schema provenance in a live build'],
    'undeclared shared-widget context was accepted')
local active = data['menu2.second.preview.zoom']
local declaration = widget._msuf2ControlSchema
active.observationIssues = nil
declaration.id = 'corrupt.current.id'
Catalog.GetRecords()
assert(active.observationIssues and active.observationIssues['invalid schema provenance in a live build'],
    'snapshot hid a current-ID mutation')
declaration.id = 'menu2.second.preview.zoom'
active.observationIssues = nil
widget._msuf2ControlSchema = nil
Catalog.GetRecords()
assert(active.observationIssues and active.observationIssues['missing schema in a live build'],
    'snapshot hid a missing current declaration')
widget._msuf2ControlSchema = declaration
active.observationIssues = nil
widget._msuf2ControlSchema.applyDomain = nil
Catalog.GetRecords()
assert(data['menu2.second.preview.zoom'].observationIssues['invalid schema provenance in a live build'],
    'snapshot hid a current-ID declaration defect')
print('PASS schema capture: declarations survive mutation; missing and defective contexts rejected')

-- A declaration snapshot must not keep a released widget alive through its setter.
local weak = setmetatable({}, { __mode = "v" })
do
    local released = {}
    weak[1] = released
    M.ControlSchema.Custom(released, { id = "released", kind = "button", scope = "first",
        applyDomain = "menuState", ephemeralReason = "Temporary fixture.",
        set = (function(owner) return function() return owner end end)(released) })
end
collectgarbage("collect")
collectgarbage("collect")
assert(not weak[1], "schema snapshots retain released widgets through callbacks")
print("PASS schema capture: released declaration widgets are collectible")

-- Dirty streaming emits only changed evidence and the final union is exact.
local function DirtyStream(streamed)
    local capture = assert(loadfile(root .. "/tools/menu_schema_capture.lua"))()
    local menu = { activeKey = "page", ControlSchema = {} }
    function menu.ControlSchema.Custom(control, spec) control._msuf2ControlSchema = spec; return control end
    function menu.PageKeyForWidget() return "page" end
    function menu.ControlSchema.Matches(setting, path)
        for _, key in ipairs(setting.keys) do if key == path then return true end end
        return false
    end
    __MSUF_WatchSchema(menu)
    local control = {}
    local public = { controlId = "width", pageKey = "page", kind = "slider", classification = "setting" }
    control._msuf2RuntimeControlRecord = public
    local catalog = { Get = function(id) if id == "width" then return { widget = control } end end,
        GetRecords = function() return { public } end }
    local directory = os.getenv("TEMP") or "/tmp"
    local temporary = os.tmpname()
    os.remove(temporary)
    local name = temporary:gsub("[^%w]", "")
    local path = directory .. "/" .. name .. ".ndjson"
    if streamed then capture.Stream(directory, name) end
    local spec = { id = "width", kind = "slider", scope = "player", applyDomain = "layout",
        setting = "player.width", settingPath = "old", ephemeralReason = "old" }
    menu.ControlSchema.Custom(control, spec)
    capture.Observe(menu, catalog)
    capture.Observe(menu, catalog)
    spec.scope = nil
    capture.Observe(menu, catalog)
    spec.scope, spec.settingPath, spec.ephemeralReason = "player", nil, nil
    capture.Observe(menu, catalog)
    local resolved = "player.width"
    spec.setting = { keys = { "player.width", "target.width" }, resolve = function() return resolved end }
    capture.Observe(menu, catalog)
    resolved = "target.width"
    capture.Observe(menu, catalog)
    control._msuf2ControlSchema = nil
    capture.Observe(menu, catalog)
    local encoded = capture.Json(capture.Data().width):gsub('"_schemaAssigned":true,', '')
    if streamed then
        capture.Save(directory, name)
        assert(next(capture.Data()) == nil and capture.Count() == 0, "saved client metadata survived")
        local file = assert(io.open(path, "rb"))
        local rows = {}
        for line in file:lines() do rows[#rows + 1] = line end
        file:close()
        os.remove(path)
        assert(#rows == 6, "unchanged capture emitted or changed evidence was dropped")
        assert(rows[#rows]:gsub('"_schemaAssigned":true,', '') == encoded, "last stream row differs from accumulated union")
    end
    return encoded
end
assert(DirtyStream(false) == DirtyStream(true), "stream and in-memory evidence differ")
print("PASS schema capture: dirty updates, nil clears, unions and client release are exact")
