-- Headless proof that the real shared Unit-preview catalog enumerator moves all
-- interactive preview roles to the currently attached unit page.

local function Pick(source, names)
    local values, n = {}, 0
    for name in tostring(names or ""):gmatch("%S+") do
        n = n + 1
        values[n] = source and source[name]
    end
    return table.unpack(values, 1, n)
end
local function AssignNamedValues(target, names, ...)
    local values, n = { ... }, 0
    for name in tostring(names or ""):gmatch("%S+") do
        n = n + 1
        target[name] = values[n]
    end
end

local registrations = {}
local M = {
    activeKey = "uf_player",
    Pick = Pick,
    AssignNamedValues = AssignNamedValues,
    Fallbacks = {
        Noop = function() end,
        One = function() return 1 end,
    },
}
M.UnitPage = {
    RegisterControl = function(widget, ctx, path, label, kind, classification, extra)
        registrations[#registrations + 1] = {
            widget = widget,
            pageKey = ctx and ctx.key,
            path = path,
            label = label,
            kind = kind,
            classification = classification,
            navigationKey = extra and extra.navigationKey,
        }
        if type(M.RegisterRuntimeControl) == "function" then
            local pageKey = tostring(ctx and ctx.key or "uf_unknown")
            local semantic = tostring(path or "control"):lower():gsub("[^%w_]+", "."):gsub("^%.*", ""):gsub("%.*$", ""):gsub("%.+", ".")
            local identity = "unit." .. semantic
            M.RegisterRuntimeControl(widget, {
                controlId = "menu2." .. pageKey .. ".unit." .. semantic,
                pageKey = pageKey,
                kind = kind,
                label = label,
                identityKey = identity,
                controlPath = identity:gsub("%.", "/"),
                classification = classification,
                ephemeral = classification == "ephemeral" or nil,
                navigationKey = extra and extra.navigationKey,
            }, "unit-preview-rebind-smoke")
        end
        return widget
    end,
}
local MSUF = {
    LOCALE = "enUS",
    L = {},
    MSUF2 = M,
    UFPreview = { Model = { UnitPreviewText = {} } },
    UFPreviewCore = {},
    UFPreviewCastbar = {},
    UFPreviewStatus = {},
    UFPreviewAuras = {},
    UFPreviewRuntime = {},
    UFPreviewZoomPan = {},
    ExportPublic = function(_, value) return value end,
}

local catalogChunk, catalogError = loadfile("Shell/Menu2/MSUF_Menu2_ControlCatalog.lua")
assert(catalogChunk, catalogError)
catalogChunk("MidnightSimpleUnitFrames", MSUF)

local chunk, err = loadfile("Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua")
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", MSUF)
assert(type(MSUF.UFPreview.RegisterRuntimeControlsForPage) == "function", "runtime catalog rebind API missing")

local function Widget(key, label)
    local widget = { key = key, _key = key, _label = label or key }
    widget.fs = { GetText = function() return label or key end }
    return widget
end
local function Read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end
local function UniquePush(out, seen, value)
    if value and value ~= "" and not seen[value] then seen[value] = true; out[#out + 1] = value end
end
local viewSource = Read("Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua")
local auraSource = Read("Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Auras.lua")
local specsSource = Read("Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Specs.lua")
local handleKeys, handleSeen = {}, {}
for key in viewSource:gmatch('MakeHandle%s*%(%s*box%s*,%s*"([^"]+)"') do UniquePush(handleKeys, handleSeen, key) end
for key in auraSource:gmatch('makeHandle%s*%(%s*box%s*,%s*"([^"]+)"') do
    if key ~= "auraCustom" then UniquePush(handleKeys, handleSeen, key) end
end
if auraSource:find('"auraCustom" .. tostring(index)', 1, true) then
    for index = 1, 3 do UniquePush(handleKeys, handleSeen, "auraCustom" .. tostring(index)) end
end
local statusBlock = specsSource:match("specs%.StatusPreview%s*=%s*StatusRows%s*%[%[(.-)%]%]") or ""
for key in statusBlock:gmatch("[\r\n]%s*([^|\r\n]+)|") do UniquePush(handleKeys, handleSeen, key) end
local layerKeys, layerSeen = {}, {}
local layerBlock = specsSource:match("specs%.PreviewLayers%s*=%s*LayerRows%s*%[%[(.-)%]%]") or ""
for key in layerBlock:gmatch("[\r\n]%s*([^|\r\n]+)|") do UniquePush(layerKeys, layerSeen, key) end
assert(#handleKeys >= 30, "Unit preview handle source inventory unexpectedly small")
assert(#layerKeys >= 10, "Unit preview layer source inventory unexpectedly small")

local layerButtons = {}
for i = 1, #layerKeys do layerButtons[i] = Widget(layerKeys[i], layerKeys[i]) end
local handles = {}
for i = 1, #handleKeys do
    handles[i] = Widget(handleKeys[i], handleKeys[i])
    handles[i]._fields = { section = (handleKeys[i] == "classPower" or handleKeys[i] == "classPowerText") and "classPower" or "text" }
    handles[i]._msuf2SettingsGear = Widget(handleKeys[i] .. "Gear")
end
local box = {
    zoomBar = Widget("zoomBar"),
    zoomOutButton = Widget("zoomOut"),
    zoomFitButton = Widget("zoomFit"),
    zoomOneButton = Widget("zoomOne"),
    zoomInButton = Widget("zoomIn"),
    zoomHelpButton = Widget("zoomHelp"),
    _msuf2PreviewControlsHint = { _close = Widget("hintClose") },
    canvas = Widget("canvas"),
    animateCombatButton = Widget("animate"),
    layerButtons = layerButtons,
    handles = handles,
    _msuf2PinButton = Widget("pin"),
}

local function AuditPage(pageKey)
    registrations = {}
    local count = MSUF.UFPreview.RegisterRuntimeControlsForPage(box, pageKey)
    local expected = 9 + #layerKeys + (#handleKeys * 2) + 1
    assert(count == expected, "unexpected interactive Unit preview count: " .. tostring(count) .. " expected " .. tostring(expected))
    assert(#registrations == count, "registration return count drift")
    local seen = {}
    for i = 1, #registrations do
        local record = registrations[i]
        assert(record.pageKey == pageKey, "stale Unit preview page ownership")
        assert(type(record.path) == "string" and record.path:match("^preview%."), "invalid semantic path")
        assert(not seen[record.path], "duplicate semantic path: " .. record.path)
        seen[record.path] = true
    end
    assert(seen["preview.zoom.surface"] and seen["preview.zoom.in"], "zoom controls missing")
    assert(seen["preview.hint.dismiss"] and seen["preview.canvas"] and seen["preview.pin.toggle"], "preview chrome missing")
    for i = 1, #layerKeys do assert(seen["preview.layer." .. layerKeys[i]], "layer control missing: " .. layerKeys[i]) end
    for i = 1, #handleKeys do
        assert(seen["preview.handle." .. handleKeys[i]], "handle missing: " .. handleKeys[i])
        assert(seen["preview.handle." .. handleKeys[i] .. ".open_settings"], "handle gear missing: " .. handleKeys[i])
    end
    for i = 1, #registrations do
        local record = registrations[i]
        if record.path == "preview.handle.name.open_settings" then
            assert(record.classification == "navigation" and record.navigationKey == pageKey,
                "handle gear navigation context is stale")
        elseif record.path == "preview.handle.classPower.open_settings" or record.path == "preview.handle.classPowerText.open_settings" then
            assert(record.classification == "navigation" and record.navigationKey == "classpower",
                "Class Resources handle gear has the wrong navigation target")
        end
    end
end

AuditPage("uf_player")
AuditPage("uf_target")
local coverage = M.GetRuntimeControlCoverageReport()
assert(coverage.collisions == 0 and coverage.byClassification.unknown == 0 and coverage.unstableIds == 0,
    "real runtime catalog rejected the shared Unit preview inventory")
local targetCount, stalePlayerCount = 0, 0
for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
    if record.pageKey == "uf_target" then targetCount = targetCount + 1 end
    if record.pageKey == "uf_player" then stalePlayerCount = stalePlayerCount + 1 end
end
assert(targetCount == #registrations and stalePlayerCount == 0,
    "real runtime catalog retained stale shared-preview ownership")
print(string.format("unit preview runtime-control rebind smoke: ok; controls=%d handles=%d layers=%d pages=2 collisions=0 stale_owners=0",
    10 + #layerKeys + (#handleKeys * 2), #handleKeys, #layerKeys))
