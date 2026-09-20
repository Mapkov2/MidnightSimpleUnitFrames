-- Generates the compact, pre-normalized Menu2 search index that ships with the core
-- addon (Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex_Data.lua).
--
-- Why this exists: search records were only ever created by RegisterSearchWidget while
-- a page was being built, so a setting on a page the player never opened could not be
-- found at all. Baking the inventory gives complete coverage without constructing a
-- single frame and without normalizing any text at runtime.
--
-- Three sources are merged, in this order of authority:
--   1. RuntimeControlCatalog after the real crosswalk harness builds every page. This
--      is the only source that contains the lazily-built unit-page sections.
--   2. The finite Aura workspace state matrix (a Custom container's Setup, the Ordering
--      tool, a group lane's Style...), rebuilt page by page under the same client facts.
--      Those controls only exist while their view is selected, so the default build
--      never sees them.
--   3. The committed Assistant control schemas, but only for a control 1 or 2 proved
--      this client builds (a schema supplies the label a runtime record lacks) or for a
--      page the harness could not build. A schema was collected for one client at one
--      point in time and the Classic one is older than its pages, so a schema control
--      that never appeared under this client's facts is one the client does not show.
--
-- Determinism: rows are sorted by their encoded identity, so regenerating without a
-- content change produces a byte-identical file and -Check can gate drift.
--
-- Client facts: the crosswalk harness only installs the shared WoW stubs, which have
-- no MSUF.Client and no 12.1 spell API. Every control behind a client gate therefore
-- stayed unbuilt, its row fell back to the Assistant schema and lost the runtime
-- exactSectionId. This generator installs the facts first, then lets the product's own
-- Game/Shared/Initialize.lua derive the client model from them, so nothing is faked
-- beyond the client identity itself (project global, interface, TOC metadata).
--
-- Flavors: --flavor reads the Menu2 XML manifests from that flavor's Options TOC
-- instead of assuming the Mainline list, so the Classic index is generated from the
-- files the Classic clients actually load. Every Classic flavor shares one index file,
-- so a Classic run is the union over the Classic flavors in the client matrix.
--
--   lua .github/scripts/search_static_index_project.lua            -> writes the Mainline file
--   lua .github/scripts/search_static_index_project.lua --stdout   -> prints it instead
--   lua .github/scripts/search_static_index_project.lua --flavor Vanilla   -> Classic file
-- The harness can only build one client per process, so each client runs in a child of
-- this script with --rows-only; that flag is internal and prints rows, not a file.
_G = _G or _ENV
loadstring = loadstring or load
unpack = unpack or table.unpack

local MAINLINE_OUTPUT_PATH = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex_Data.lua"
local CLASSIC_OUTPUT_PATH = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_StaticIndex_Data_Classic.lua"
local CLIENT_MATRIX_PATH = "tools/classic-client-matrix.tsv"
local CLIENT_INIT_PATH = "MidnightSimpleUnitFrames/Game/Shared/Initialize.lua"
local ASSISTANT_ROOT = "MidnightSimpleUnitFrames_Assistant"
local SCHEMA_FILE_PATTERN = "MSUF_AssistantControlSchema_Data[^/]*%.lua$"
local HARNESS_PATH = "tools/assistant_v1_catalog_crosswalk.lua"
-- The crosswalk continues into Graphify-backed release gates that need an ignored
-- local build artifact. Everything this generator needs is already in place by then.
local HARNESS_CUT = "\nlocal function HasExecutableSettingContract"
-- The harness honors a caller-supplied Menu2 manifest list, which is how a flavor
-- other than Mainline is built. Pinned here so a harness that loses the hook fails
-- loudly instead of quietly producing a Mainline index under a Classic flavor name.
local HARNESS_MANIFEST_HOOK = 'local MENU_XML = rawget(_G, "__MSUF_MENU2_XML_MANIFEST") or {'
-- The harness records every page that failed to build; only those pages may fall back
-- to the Assistant schema, so the list has to be in scope where the harness is cut.
local HARNESS_FAILURES_LOCAL = "local pageBuildFailures = {}"
-- Child runs print their rows and this terminator, so a child that died halfway can
-- never be mistaken for a complete, shorter index.
local ROWS_ONLY_FLAG = "--rows-only"
local ROWS_TERMINATOR = "-- end of flavor rows"
-- Collected rows carry where they came from in a leading field that never reaches the
-- shipped file; it only decides which client's answer survives a shared identity. A
-- higher rank wins: the default build knows a control's collapsible section, a workspace
-- view proves the control exists without one, the schema proves nothing about this client.
local ORIGIN_RUNTIME = "runtime"
local ORIGIN_STATE = "state"
local ORIGIN_SCHEMA = "schema"
local ORIGIN_RANK = { [ORIGIN_RUNTIME] = 3, [ORIGIN_STATE] = 2, [ORIGIN_SCHEMA] = 1 }

-- Only these classifications are things a player can change or run. "ephemeral" and
-- "navigation" controls are menu plumbing and normally stay out of the index. A
-- reviewed exact-target contract is the narrow exception: release highlights need
-- its stable control ID to open a selector-owned subcategory without making that
-- selector executable through ordinary Assistant label matching.
local INDEXED_CLASSIFICATIONS = { setting = true, action = true }
local SOURCE_SHA256 = tostring(os.getenv("MSUF_SEARCH_SOURCE_SHA256") or "")
if not SOURCE_SHA256:match("^[A-F0-9][A-F0-9]+$") or #SOURCE_SHA256 ~= 64 then
    error("MSUF_SEARCH_SOURCE_SHA256 must be a 64-character uppercase SHA256")
end

-- Path segments that carry no search meaning and only make hints noisy.
local HINT_NOISE = {
    ["unit-workspace"] = true, ["group-workspace"] = true, ["workspace"] = true,
    ["lane"] = true, ["root"] = true, ["page"] = true, ["section"] = true,
}

local function Fail(message)
    io.stderr:write("search_static_index_project: " .. tostring(message) .. "\n")
    os.exit(1)
end

local function Read(path)
    local handle, err = io.open(path, "rb")
    if not handle then Fail(path .. ": " .. tostring(err)) end
    local text = handle:read("*a") or ""
    handle:close()
    return text
end

local function Trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ArgumentValue(name)
    local pattern = "^" .. name:gsub("%p", "%%%0") .. "=(.*)$"
    local list = arg or {}
    for index = 1, #list do
        if list[index] == name then return list[index + 1] end
        local inline = tostring(list[index]):match(pattern)
        if inline then return inline end
    end
    return nil
end

-- tools/classic-client-matrix.tsv is the single list of supported clients. Its
-- Suffix, Interfaces, ClientToken, ProjectGlobal and IsClassic columns carry every
-- client fact this generator needs; nothing here hard-codes a flavor.
local function LoadClientMatrix()
    local header, rows, order = nil, {}, {}
    for line in Read(CLIENT_MATRIX_PATH):gmatch("[^\r\n]+") do
        local fields = {}
        for field in (line .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = Trim(field) end
        if not header then
            header = fields
        elseif Trim(fields[1] or "") ~= "" then
            local row = {}
            for index = 1, #header do row[header[index]] = fields[index] or "" end
            rows[row.Suffix] = row
            order[#order + 1] = row.Suffix
        end
    end
    if not header or #order == 0 then Fail(CLIENT_MATRIX_PATH .. ": no client rows") end
    for _, required in ipairs({ "Suffix", "Interfaces", "ClientToken", "ProjectGlobal", "IsClassic" }) do
        local present = false
        for _, name in ipairs(header) do if name == required then present = true end end
        if not present then Fail(CLIENT_MATRIX_PATH .. ": missing column " .. required) end
    end
    return rows, order
end

local ROWS_ONLY = false
for _, value in ipairs(arg or {}) do
    if value == ROWS_ONLY_FLAG then ROWS_ONLY = true end
end

local MATRIX_ROWS, MATRIX_ORDER = LoadClientMatrix()

-- WoW Forever is not a matrix row: it shares the Mainline TOCs and is placed by
-- Blizzard's own Camelot marker, never by a project ID or a TOC suffix. The Mainline
-- row already records its interface, the only entry below the six-digit Midnight
-- range, so the build target is derived from the matrix instead of being invented.
-- Its capability answers differ from Midnight's (tap denied, pet happiness,
-- surnames, no arena, no empowered casts), and it reads the same index file, so a
-- Mainline index that leaves it out loses rows for a shipping client.
local FOREVER_TARGET = "Forever"
local function TargetRow(target)
    if target == FOREVER_TARGET then
        for _, suffix in ipairs(MATRIX_ORDER) do
            local row = MATRIX_ROWS[suffix]
            if row.IsClassic ~= "true" then
                for value in tostring(row.Interfaces):gmatch("%d+") do
                    if tonumber(value) < 100000 then return row, tonumber(value), true end
                end
                Fail(CLIENT_MATRIX_PATH .. ": the " .. suffix
                    .. " row records no WoW Forever interface number")
            end
        end
        Fail(CLIENT_MATRIX_PATH .. ": no Mainline-family row to place WoW Forever on")
    end
    local row = MATRIX_ROWS[target]
    if not row then return nil end
    return row, tonumber(tostring(row.Interfaces):match("%d+")), false
end

local FLAVOR = ArgumentValue("--flavor") or MATRIX_ORDER[1]
local FLAVOR_ROW = TargetRow(FLAVOR)
if not FLAVOR_ROW then
    Fail("unknown flavor '" .. tostring(FLAVOR) .. "'; " .. CLIENT_MATRIX_PATH
        .. " lists " .. table.concat(MATRIX_ORDER, ", ") .. " and " .. FOREVER_TARGET
        .. " shares the Mainline row")
end
local IS_CLASSIC_FLAVOR = FLAVOR_ROW.IsClassic == "true"
local OUTPUT_PATH = IS_CLASSIC_FLAVOR and CLASSIC_OUTPUT_PATH or MAINLINE_OUTPUT_PATH
-- Every client that loads one index file contributes to it: the three Classic flavors
-- share the Classic file, Midnight and WoW Forever share the Mainline file. Dropping a
-- row a sibling client builds would make that control unfindable there.
local BUILD_FLAVORS = {}
for _, suffix in ipairs(MATRIX_ORDER) do
    if (MATRIX_ROWS[suffix].IsClassic == "true") == IS_CLASSIC_FLAVOR then
        BUILD_FLAVORS[#BUILD_FLAVORS + 1] = suffix
    end
end
if not IS_CLASSIC_FLAVOR then BUILD_FLAVORS[#BUILD_FLAVORS + 1] = FOREVER_TARGET end

local ADDON_TOC_PATTERN = {
    MidnightSimpleUnitFrames = "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_%s.toc",
    MidnightSimpleUnitFrames_Options =
        "MidnightSimpleUnitFrames_Options/MidnightSimpleUnitFrames_Options_%s.toc",
    MidnightSimpleUnitFrames_Assistant =
        "MidnightSimpleUnitFrames_Assistant/MidnightSimpleUnitFrames_Assistant_%s.toc",
}

-- A TOC may repeat a field with different load conditions (the Mainline "## Version"
-- pair). A desktop harness has no game type to select with, so the first line wins and
-- the condition suffix is left in place: Initialize.lua cuts it the same way in game.
local function TOCMetadata(path)
    local fields = {}
    for line in Read(path):gmatch("[^\r\n]+") do
        local field, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
        if field and fields[field] == nil then fields[field] = value end
    end
    return fields
end

-- The Menu2 load list is a property of the flavor's Options TOC, not of this script.
-- Mainline and the Classic flavors list different manifests (Classic swaps in the
-- _Classic pages and the Classic index file), and the TOC is the only place that
-- records which.
local function Menu2Manifests(suffix)
    local tocPath = ADDON_TOC_PATTERN.MidnightSimpleUnitFrames_Options:format(suffix)
    local manifests = {}
    for line in Read(tocPath):gmatch("[^\r\n]+") do
        local entry = Trim(line)
        if entry ~= "" and entry:sub(1, 1) ~= "#" then
            entry = entry:gsub("\\", "/")
            if entry:lower():match("^shell/menu2/.+%.xml$") then manifests[#manifests + 1] = entry end
        end
    end
    if #manifests == 0 then Fail(tocPath .. ": lists no Shell/Menu2 XML manifest") end
    return manifests
end

-- The Assistant control schema is per flavor too (the Classic runtime XML loads its own
-- smaller file), resolved through the flavor's Assistant TOC.
local function ControlSchemaPath(suffix)
    local tocPath = ADDON_TOC_PATTERN.MidnightSimpleUnitFrames_Assistant:format(suffix)
    for line in Read(tocPath):gmatch("[^\r\n]+") do
        local entry = Trim(line):gsub("\\", "/")
        if entry ~= "" and entry:sub(1, 1) ~= "#" and entry:lower():match("%.xml$") then
            local xmlPath = ASSISTANT_ROOT .. "/" .. entry
            local xmlDir = xmlPath:match("^(.*)/[^/]+$") or ASSISTANT_ROOT
            for file in Read(xmlPath):gmatch('<Script%s+file="([^"]+)"') do
                local relative = file:gsub("\\", "/")
                if relative:match(SCHEMA_FILE_PATTERN) then return xmlDir .. "/" .. relative end
            end
        end
    end
    Fail(tocPath .. ": no manifest under it loads a control schema data file")
end

-- A schema only ever describes a control this client's runtime built (see Collect), so
-- a Classic run cannot inherit a Mainline-only control from the Mainline schema, which
-- is where the hand-kept Classic index picked up its rows for controls no Classic page
-- builds. Every committed schema may therefore name such a control; the flavor's own
-- schema answers first. Some controls register without a label (the unit Range Fade
-- opacity slider) and only a schema carries one, and the Classic schema predates the
-- Classic arena page.
local function ControlSchemaPaths(suffix)
    local paths, seen = {}, {}
    local function Add(path)
        if not seen[path] then seen[path] = true; paths[#paths + 1] = path end
    end
    Add(ControlSchemaPath(suffix))
    for _, other in ipairs(MATRIX_ORDER) do Add(ControlSchemaPath(other)) end
    return paths
end

local PANDEMIC_APPLIER_PATH = "MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_Appearance.lua"

local function NormalizePath(path)
    local parts = {}
    for part in tostring(path):gsub("\\", "/"):gmatch("[^/]+") do
        if part == ".." then
            parts[#parts] = nil
        elseif part ~= "." then
            parts[#parts + 1] = part
        end
    end
    return table.concat(parts, "/")
end

--- Every Lua path one flavor's core addon loads, from its TOC and through every XML
--- manifest it includes. Runtime capabilities that a menu section probes for exist on a
--- client exactly when the file publishing them is in this set.
local function CoreLoadGraph(suffix)
    local loaded = {}
    local function Walk(path)
        if path:lower():match("%.xml$") then
            local directory = path:match("^(.*)/[^/]+$") or ""
            for element, file in Read(path):gmatch('<(%a+)%s+file="([^"]+)"') do
                if element == "Script" or element == "Include" then Walk(NormalizePath(directory .. "/" .. file)) end
            end
        elseif path:lower():match("%.lua$") then
            loaded[path] = true
        end
    end
    local tocPath = ADDON_TOC_PATTERN.MidnightSimpleUnitFrames:format(suffix)
    for line in Read(tocPath):gmatch("[^\r\n]+") do
        local entry = Trim(line)
        if entry ~= "" and entry:sub(1, 1) ~= "#" then Walk(NormalizePath("MidnightSimpleUnitFrames/" .. entry)) end
    end
    if not loaded[CLIENT_INIT_PATH] then Fail(tocPath .. ": the load graph does not reach " .. CLIENT_INIT_PATH) end
    return loaded
end

-- Interface numbers are MMmmpp: 120100 -> 12.1.0, 11509 -> 1.15.9.
local function InterfaceVersionString(interface)
    return string.format("%d.%d.%d", math.floor(interface / 10000),
        math.floor(interface / 100) % 100, interface % 100)
end

--- Publishes one flavor's client identity and the capability probes the gated Menu2
--- controls make, then runs the product's own client initializer over them. Called
--- before any Menu2 file loads.
local function InstallClientFacts(target)
    local row, interface, isForever = TargetRow(target)
    if not row then Fail("client matrix has no row for " .. tostring(target)) end
    if not interface then Fail(target .. ": the client matrix records no interface number") end
    local suffix = row.Suffix
    -- The harness requires the same stubs; loading them here first only moves that
    -- step earlier, so the client model exists before any Menu2 file is read.
    package.path = ".github/scripts/?.lua;tools/?.lua;tools/AssistantTraining/?.lua;" .. package.path
    require("wow_stubs")
    -- Project globals are only ever compared for equality, so distinct identities are
    -- enough and no Blizzard project number is invented here.
    for index, name in ipairs(MATRIX_ORDER) do
        local projectGlobal = MATRIX_ROWS[name].ProjectGlobal
        if projectGlobal ~= "" then _G[projectGlobal] = index end
    end
    if row.ProjectGlobal == "" then Fail(suffix .. ": the client matrix records no ProjectGlobal") end
    _G.WOW_PROJECT_ID = _G[row.ProjectGlobal]

    local versionString = InterfaceVersionString(interface)
    _G.GetBuildInfo = function()
        return versionString, tostring(interface), "Jan 1 2026", interface
    end

    -- WoW Forever is placed only by Blizzard's Camelot marker on GameEvent, exactly as
    -- Game/Shared/Initialize.lua documents; nothing else about it is guessed here.
    if isForever then
        _G.GameEvent = _G.GameEvent or {}
        _G.GameEvent.RegisterCamelotEvents = _G.GameEvent.RegisterCamelotEvents or function() end
    elseif type(_G.GameEvent) == "table" then
        _G.GameEvent.RegisterCamelotEvents = nil
    end

    local metadata = {}
    for addonName, pattern in pairs(ADDON_TOC_PATTERN) do metadata[addonName] = TOCMetadata(pattern:format(suffix)) end
    _G.GetAddOnMetadata = function(addonName, field)
        local fields = metadata[addonName]
        return fields and fields[field] or nil
    end
    _G.C_AddOns = _G.C_AddOns or {}
    _G.C_AddOns.GetAddOnMetadata = function(addonName, field) return _G.GetAddOnMetadata(addonName, field) end
    -- The X-MSUF-Client tag is the authoritative Classic placement route and has to
    -- agree with the project global above, or Initialize.lua would report a mismatch.
    local tag = Trim(metadata.MidnightSimpleUnitFrames["X-MSUF-Client"] or "")
    if tag:lower() ~= row.ClientToken:lower() then
        Fail(suffix .. ": core TOC X-MSUF-Client '" .. tag .. "' does not match the matrix ClientToken '"
            .. row.ClientToken .. "'")
    end

    -- Capability probes the Menu2 pages make while building. The GCD Bar section is
    -- offered only when the client can drive the bar C-side, which
    -- MSUF_Menu2_GlobalCastbars.lua probes as C_Spell.GetSpellCooldownDuration plus
    -- StatusBar:SetTimerDuration; the permissive region stub already answers the
    -- widget half. Both arrived with the 12.1 Mainline client, which is why the
    -- shipped Classic index carries no GCD rows.
    if row.IsClassic ~= "true" then
        local spellAPI = _G.C_Spell or {}
        _G.C_Spell = spellAPI
        spellAPI.GetSpellCooldownDuration = spellAPI.GetSpellCooldownDuration or function() return 0 end
    else
        _G.C_Spell = nil
    end

    local namespace = _G.MSUF_NS
    if type(namespace) ~= "table" then Fail("WoW stubs did not create MSUF_NS") end
    -- The Custom workspace offers Pandemic Warning & Style only where the Aura backend
    -- publishes its Pandemic applier. That applier ships in the 12.1 native aura runtime,
    -- which only some flavors load, so this flavor's own core load graph decides it.
    local auraBackend = type(namespace.MSUF_Auras3) == "table" and namespace.MSUF_Auras3 or {}
    namespace.MSUF_Auras3 = auraBackend
    auraBackend.ApplyPandemicVisual = CoreLoadGraph(suffix)[PANDEMIC_APPLIER_PATH] and function() end or nil

    namespace.Client = nil
    local chunk, err = loadfile(CLIENT_INIT_PATH)
    if not chunk then Fail(CLIENT_INIT_PATH .. ": " .. tostring(err)) end
    local ok, result = pcall(chunk, "MidnightSimpleUnitFrames", namespace)
    if not ok then Fail(CLIENT_INIT_PATH .. ": " .. tostring(result)) end
    local client = namespace.Client
    if type(client) ~= "table" then Fail(CLIENT_INIT_PATH .. ": published no MSUF.Client") end
    if client.Flavor ~= suffix or client.IsForever ~= isForever then
        Fail(target .. ": the client model placed this build as " .. tostring(client.Flavor)
            .. (client.IsForever and " (WoW Forever)" or ""))
    end
    return client
end

local function Titleize(segment)
    segment = tostring(segment or ""):gsub("[-_]", " ")
    return (segment:gsub("(%a)([%w]*)", function(first, rest) return first:upper() .. rest end))
end

-- "auras/unit-workspace/lane/buff/filters/hide-permanent" -> "Buff > Filters"
local function HintFromControlPath(controlPath, pageKey)
    local segments = {}
    for segment in tostring(controlPath or ""):gmatch("[^/]+") do
        segments[#segments + 1] = segment
    end
    -- The last segment is the control itself, and the page is shown separately.
    table.remove(segments)
    local kept = {}
    for i = 1, #segments do
        local segment = segments[i]
        if not HINT_NOISE[segment] and segment ~= pageKey then kept[#kept + 1] = segment end
    end
    while #kept > 2 do table.remove(kept, 1) end
    for i = 1, #kept do kept[i] = Titleize(kept[i]) end
    return table.concat(kept, " > ")
end

local function LoadSchemaRecords(schemaPath)
    local MSUF = { Assistant = {} }
    local chunk, err = loadfile(schemaPath)
    if not chunk then Fail(schemaPath .. ": " .. tostring(err)) end
    local ok, result = pcall(chunk, "MidnightSimpleUnitFrames_Assistant", MSUF)
    if not ok then Fail(schemaPath .. ": " .. tostring(result)) end
    local data = MSUF.Assistant.ControlSchemaData
    if type(data) ~= "table" or type(data.records) ~= "table" or type(data.columns) ~= "table" then
        Fail("control schema data did not expose records/columns")
    end
    local col = {}
    for index, name in ipairs(data.columns) do col[name] = index end
    for _, required in ipairs({ "controlId", "pageKey", "controlPath", "classification", "kind",
        "settingKey", "actionKey", "label" }) do
        if not col[required] then Fail("control schema is missing column " .. required) end
    end
    local out = {}
    for _, record in ipairs(data.records) do
        out[#out + 1] = {
            controlId = record[col.controlId],
            pageKey = record[col.pageKey],
            label = record[col.label],
            kind = record[col.kind],
            settingKey = record[col.settingKey],
            actionKey = record[col.actionKey],
            controlPath = record[col.controlPath],
            classification = record[col.classification],
        }
    end
    return out
end

--- Exact runtime control IDs are the preferred identity: they are the catalog's
--- stable semantic route and survive localization or repeated display labels.
--- Older/unreviewed records retain deterministic fallbacks, ordered from the
--- strongest route metadata to display geometry. The separators are never emitted
--- by catalog IDs/paths and remain inside one TSV field.
local function SearchIdentityComponent(value)
    local text = tostring(value or "")
    text = text:gsub("%%", "%%25")
    text = text:gsub("\031", "%%1F")
    text = text:gsub("%.", "%%2E")
    return text
end

local function CatalogSearchIdentity(kind, pageKey, ...)
    local parts = { kind, SearchIdentityComponent(pageKey) }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = SearchIdentityComponent(select(i, ...))
    end
    return table.concat(parts, "\031")
end

local function SearchRouteIdentity(record, pageKey, labelNorm, kind, hint)
    local controlId = tostring(record.controlId or "")
    if controlId ~= "" then
        return CatalogSearchIdentity("id", pageKey, controlId)
    end
    local controlPath = tostring(record.controlPath or "")
    if controlPath ~= "" then
        return CatalogSearchIdentity("path", pageKey, controlPath)
    end
    local settingKey = tostring(record.settingKey or "")
    if settingKey ~= "" then
        return CatalogSearchIdentity("setting", pageKey, settingKey)
    end
    local actionKey = tostring(record.actionKey or "")
    if actionKey ~= "" then
        return CatalogSearchIdentity("action", pageKey, actionKey, labelNorm, hint)
    end
    return CatalogSearchIdentity("display", pageKey, kind, labelNorm, hint)
end

local function RuntimeExactContract(Catalog, record)
    if not (Catalog and type(Catalog.Get) == "function" and type(record) == "table") then return "", "", "" end
    local raw = Catalog.Get(tostring(record.controlId or ""))
    local widget = raw and raw.widget
    if not widget then return "", "", "" end

    local sectionId = ""
    local node = widget
    while node do
        local entry = node._msuf2CollapsibleEntry
        local stateKey = entry and tostring(entry.stateKey or "") or ""
        local pageKey, id = stateKey:match("^([^:]+):(.+)$")
        if pageKey == tostring(record.pageKey or "") and id and id ~= "" then
            sectionId = id
            break
        end
        node = node.GetParent and node:GetParent() or nil
    end

    local kinds = {}
    for kind, enabled in pairs(widget._msuf2ExactTargetKinds or {}) do
        if enabled == true and type(kind) == "string" and kind ~= "" then kinds[#kinds + 1] = kind end
    end
    table.sort(kinds)

    local contracts = {}
    for kind, values in pairs(widget._msuf2ExactTargetContracts or {}) do
        if type(kind) == "string" and kind ~= "" and type(values) == "table" then
            for value, settingKey in pairs(values) do
                value, settingKey = tostring(value or ""), settingKey == true and "*" or tostring(settingKey or "")
                if value ~= "" and settingKey ~= "" then
                    if widget._msuf2ExactTargetKinds == nil
                        or widget._msuf2ExactTargetKinds[kind] ~= true
                        or type(widget._msuf2PrepareExactSearchTarget) ~= "function"
                        or type(Catalog.ResolveExactTarget) ~= "function"
                    then
                        Fail("exact target contract has no matching runtime preparation hook: "
                            .. tostring(record.controlId) .. " " .. kind .. "=" .. value)
                    end
                    local _, resolvedWidget, resolveSource = Catalog.ResolveExactTarget(
                        tostring(record.pageKey or ""), {
                        controlId = tostring(record.controlId or ""),
                        pageKey = tostring(record.pageKey or ""),
                        prepareKind = kind,
                        prepareValue = value,
                        settingKey = settingKey ~= "*" and settingKey or "",
                    })
                    if resolvedWidget ~= widget or resolveSource ~= "control_id" then
                        Fail("exact target contract did not activate its declared subcategory: "
                            .. tostring(record.controlId) .. " " .. kind .. "=" .. value
                            .. " (" .. tostring(resolveSource) .. ")")
                    end
                    contracts[#contracts + 1] = kind .. "=" .. value .. "=" .. settingKey
                end
            end
        end
    end
    table.sort(contracts)
    return sectionId, table.concat(kinds, ","), table.concat(contracts, "|")
end

-- The finite Aura workspace views: the matrix the Assistant control schema is collected
-- over (four unit frames x every container tool, three group scopes x every lane tool,
-- the global Appearance products and their two compatibility landings). A Custom
-- container is also visited as a Debuff container where its Filters and Ordering tools
-- branch on the aura type.
local WORKSPACE_UNIT_PAGES = {
    { unit = "player", page = "uf_player" },
    { unit = "target", page = "uf_target" },
    { unit = "focus", page = "uf_focus" },
    { unit = "boss", page = "uf_boss" },
}
local WORKSPACE_LANE_TOOLS = { "layout", "behavior", "filters", "blacklist", "style" }
local WORKSPACE_CUSTOM_TOOLS = { "setup", "layout", "behavior", "filters", "whitelist", "style" }
local WORKSPACE_AURA_TYPE_TOOLS = { "filters", "behavior" }
local WORKSPACE_INDEX4_TOOLS = {
    player = { "setup", "layout", "behavior", "filters", "defensives", "style" },
    other = { "setup", "layout", "behavior", "filters", "dots", "style" },
}
local WORKSPACE_EXTERNALS_TOOLS = { "layout", "behavior", "style" }
local WORKSPACE_GROUP_SCOPES = { "party", "raid", "mythicraid" }
local WORKSPACE_APPEARANCE_PRODUCTS = { "buff", "debuff", "playerDefensives", "targetDots" }
local WORKSPACE_COMPAT_PAGES = { "auras3_buffs", "auras3_debuffs" }

local function EnsureTable(owner, key)
    local value = owner[key]
    if type(value) ~= "table" then value = {}; owner[key] = value end
    return value
end

--- Rebuilds one page in whatever view the menu state now selects. Menu2 slices hidden
--- lazy sections through construction timers, and a unit page reaches them two ways
--- (inline sections through UnitPage.BuildSectionLazy, registered sections through
--- spec.lazy). Both are forced eager for the rebuild, or the page would come back
--- without every lazily built section.
local function RebuildPage(M, pageKey)
    local timer, menuTimer = _G.C_Timer, M.MenuTimer
    local after = timer and timer.After
    local menuAfter, menuNewTimer = menuTimer and menuTimer.After, menuTimer and menuTimer.NewTimer
    local function RunNow(_, callback) if type(callback) == "function" then callback() end end
    if timer then timer.After = RunNow end
    if menuTimer then
        menuTimer.After = RunNow
        menuTimer.NewTimer = function(_, callback)
            RunNow(nil, callback)
            return { Cancel = function() end }
        end
    end
    local unitPage = type(M.UnitPage) == "table" and M.UnitPage or nil
    local lazyBuilder = unitPage and unitPage.BuildSectionLazy
    local registry = unitPage and type(unitPage._sectionRegistry) == "table" and unitPage._sectionRegistry or {}
    local specLazy = {}
    if unitPage then unitPage.BuildSectionLazy = nil end
    for index = 1, #registry do
        local spec = registry[index]
        if type(spec) == "table" then specLazy[index] = spec.lazy; spec.lazy = false end
    end
    M.InvalidatePage(pageKey)
    local ok, result = pcall(M.BuildPageEntry, pageKey, true)
    for index = 1, #registry do
        local spec = registry[index]
        if type(spec) == "table" then spec.lazy = specLazy[index] end
    end
    if unitPage then unitPage.BuildSectionLazy = lazyBuilder end
    if timer then timer.After = after end
    if menuTimer then menuTimer.After, menuTimer.NewTimer = menuAfter, menuNewTimer end
    if not ok or result == nil then
        Fail("the " .. pageKey .. " workspace view did not build: " .. tostring(result))
    end
end

--- Selects every finite workspace view this client has, rebuilds the owning page and
--- calls capture() after each build. A page the client does not register (Classic Era
--- has no focus frame) has no views to visit.
local function VisitWorkspaceStates(M, capture)
    local namespace = _G.MSUF_NS
    local model = type(namespace) == "table" and type(namespace.MSUF_Auras3) == "table"
        and namespace.MSUF_Auras3.MenuModel or nil
    if type(model) ~= "table" or type(model.CustomContainer) ~= "function" then
        Fail("the Auras3 MenuModel did not load, so the workspace views cannot be built")
    end
    if type(M.InvalidatePage) ~= "function" or type(M.BuildPageEntry) ~= "function" then
        Fail("the Menu2 page lifecycle API did not load")
    end
    local pages, visited = M.pages or {}, 0
    local function Visit(pageKey)
        RebuildPage(M, pageKey)
        capture()
        visited = visited + 1
    end
    local function UnitView(unit, page, container, tool)
        EnsureTable(M, "unitAuraTabSelection")[unit] = container
        EnsureTable(EnsureTable(M, "unitAuraToolSelection"), unit)[container] = tool
        Visit(page)
    end
    local function SetCustomAuraType(unit, index, auraType)
        local item = model.CustomContainer(unit, index, true)
        if type(item) ~= "table" then Fail("no Custom " .. index .. " Aura container for " .. unit) end
        item.auraType = auraType
    end
    for _, row in ipairs(WORKSPACE_UNIT_PAGES) do
        if pages[row.page] then
            for _, lane in ipairs({ "buff", "debuff" }) do
                for _, tool in ipairs(WORKSPACE_LANE_TOOLS) do UnitView(row.unit, row.page, lane, tool) end
            end
            for index = 1, 3 do
                local container = "custom" .. index
                SetCustomAuraType(row.unit, index, "BUFF")
                for _, tool in ipairs(WORKSPACE_CUSTOM_TOOLS) do UnitView(row.unit, row.page, container, tool) end
                SetCustomAuraType(row.unit, index, "DEBUFF")
                for _, tool in ipairs(WORKSPACE_AURA_TYPE_TOOLS) do UnitView(row.unit, row.page, container, tool) end
                SetCustomAuraType(row.unit, index, "BUFF")
            end
            for _, tool in ipairs(WORKSPACE_INDEX4_TOOLS[row.unit] or WORKSPACE_INDEX4_TOOLS.other) do
                UnitView(row.unit, row.page, "custom4", tool)
            end
            UnitView(row.unit, row.page, "buff", "layout")
        end
    end
    for _, scope in ipairs(WORKSPACE_GROUP_SCOPES) do
        M.gfScope = scope
        if pages.gf_layout then Visit("gf_layout") end
        if pages.gf_auras then
            local function GroupView(lane, tool)
                EnsureTable(M, "gfAuraLaneSelection")[scope] = lane
                EnsureTable(EnsureTable(M, "gfAuraToolSelection"), scope)[lane] = tool
                Visit("gf_auras")
            end
            for _, lane in ipairs({ "buff", "debuff" }) do
                for _, tool in ipairs(WORKSPACE_LANE_TOOLS) do GroupView(lane, tool) end
            end
            for _, tool in ipairs(WORKSPACE_EXTERNALS_TOOLS) do GroupView("externals", tool) end
        end
    end
    for _, product in ipairs(WORKSPACE_APPEARANCE_PRODUCTS) do
        -- The Mainline Aura page keeps the selected product in auraAppearanceContainer,
        -- the Classic one (MSUF_Menu2_Auras_Classic.lua) in auraSharedStyleContainer.
        M.auraAppearanceContainer, M.auraSharedStyleContainer = product, product
        if product == "buff" or product == "debuff" then M.auraStyleGFLane = product end
        if pages.auras3_styling then Visit("auras3_styling") end
        for _, page in ipairs(WORKSPACE_COMPAT_PAGES) do
            if pages[page] and (product == "buff" or product == "debuff") then Visit(page) end
        end
    end
    return visited
end

--- Called from inside the crosswalk harness, where every page has been built with the
--- real product builders and the real search text utilities are loaded. Returns this
--- flavor's encoded rows; the caller merges and writes them.
local function Collect(M, Catalog, schemaPaths, buildFailures)
    local Normalize = M.Search and M.Search.Text and M.Search.Text.NormalizeSearchText
    if type(Normalize) ~= "function" then Fail("NormalizeSearchText did not load") end

    -- Where a record came from decides which client wins a shared row below: only the
    -- runtime catalog knows the collapsible section a control actually sits in, so a
    -- client that builds the page beats one that only inherits the schema fallback.
    local sources, origin, built = {}, {}, {}
    local function BuiltKey(record)
        return tostring(record.pageKey or "") .. "\031" .. tostring(record.controlId or "")
    end
    for _, record in ipairs(Catalog.GetRecords()) do
        record.exactSectionId, record.exactTargetKinds, record.exactTargetContracts = RuntimeExactContract(Catalog, record)
        sources[#sources + 1] = record
        origin[record] = ORIGIN_RUNTIME
        built[BuiltKey(record)] = true
    end
    -- A workspace view's controls carry no exact section: one identity serves every
    -- Custom container, so the collapsible that holds it differs per view, and search
    -- routes these rows by the query instead (exactly as it did for the schema rows).
    local views = VisitWorkspaceStates(M, function()
        for _, record in ipairs(Catalog.GetRecords()) do
            local key = BuiltKey(record)
            if not built[key] then
                built[key] = true
                sources[#sources + 1] = record
                origin[record] = ORIGIN_STATE
            end
        end
    end)
    -- A schema record is used only for a control this client actually builds: one the
    -- runtime registered (the schema may still supply the label a runtime record lacks),
    -- or, from the flavor's own schema, one on a page that could not be built here at all.
    -- Every other page was built in its default view and in every workspace view under
    -- this client's facts, so a schema control that never appeared is one the client does
    -- not show (Classic has no GCD bar and no Empowered casts; the Classic Aura page
    -- builds no lane Full-Frame effect).
    local unbuiltPages, schemaUsed, schemaDropped = {}, 0, 0
    for _, failure in ipairs(buildFailures or {}) do unbuiltPages[tostring(failure.key or "")] = true end
    for index, schemaPath in ipairs(schemaPaths) do
        local own = index == 1
        for _, record in ipairs(LoadSchemaRecords(schemaPath)) do
            if built[BuiltKey(record)] or (own and unbuiltPages[tostring(record.pageKey or "")]) then
                sources[#sources + 1] = record
                origin[record] = ORIGIN_SCHEMA
                if own then schemaUsed = schemaUsed + 1 end
            elseif own then
                schemaDropped = schemaDropped + 1
            end
        end
    end
    for _, failure in ipairs(buildFailures or {}) do
        io.stderr:write(string.format("search static index: page %s did not build (%s); its schema rows stand in\n",
            tostring(failure.key), tostring(failure.error)))
    end
    io.stderr:write(string.format("search static index: %d workspace views built; %d schema records name built "
        .. "controls, %d name controls this client does not build\n", views, schemaUsed, schemaDropped))

    local rows, seen = {}, {}
    for _, record in ipairs(sources) do
        local hasExactTarget = tostring(record.exactTargetKinds or "") ~= ""
            and tostring(record.exactTargetContracts or "") ~= ""
        if INDEXED_CLASSIFICATIONS[tostring(record.classification or "")] or hasExactTarget then
            local pageKey = tostring(record.pageKey or "")
            local label = tostring(record.label or "")
            if pageKey ~= "" and pageKey ~= "search" and label ~= "" then
                local controlPath = tostring(record.controlPath or "")
                local settingKey = tostring(record.settingKey or "")
                local actionKey = tostring(record.actionKey or "")
                local kind = tostring(record.kind or "control")
                local hint = HintFromControlPath(controlPath, pageKey)
                local labelNorm = Normalize(label)
                if labelNorm ~= "" then
                    local identity = SearchRouteIdentity(record, pageKey, labelNorm, kind, hint)
                    if not seen[identity] then
                        seen[identity] = true
                        rows[#rows + 1] = {
                            origin[record], pageKey, label, kind, settingKey, actionKey, hint,
                            labelNorm, identity,
                            tostring(record.exactSectionId or ""), tostring(record.exactTargetKinds or ""),
                            tostring(record.exactTargetContracts or ""),
                            Normalize(table.concat({
                                label, hint, controlPath, pageKey, kind, settingKey, actionKey,
                            }, " ")),
                        }
                    end
                end
            end
        end
    end

    local lines = {}
    for index = 1, #rows do
        local row = rows[index]
        for field = 1, #row do
            if row[field]:find("[\t\n\r]") then
                Fail("field " .. field .. " of '" .. row[3] .. "' contains a separator character")
            end
        end
        lines[index] = table.concat(row, "\t")
    end
    return lines
end

--- One sorted, de-duplicated file out of one or more client runs. Each collected line
--- carries its origin in field 1 and its search identity in field 9. Clients that share
--- an index file can answer the same identity differently: a client that builds a
--- control only in a workspace view knows no collapsible section for it, a client that
--- could not build a page only has the Assistant schema, and WoW Forever's pet frame
--- adds a pet-happiness exact target Midnight has no subcategory for. The higher origin
--- rank therefore wins, two rows of one rank are resolved in matrix order, and every
--- unresolved disagreement is named on stderr instead of being silent. Sorting the
--- encoded lines is the field order of the first eleven columns: the separator is lower
--- than every character a field may contain.
-- Shared selector widgets expose different choices on each client. Preserve the
-- union of their proven runtime contracts when all other row fields agree.
local function MergeSelectorContracts(first, second)
    local a, b = {}, {}
    for field in (first .. "\t"):gmatch("(.-)\t") do a[#a + 1] = field end
    for field in (second .. "\t"):gmatch("(.-)\t") do b[#b + 1] = field end
    if #a ~= 12 or #b ~= 12 then return nil end
    for i = 1, 12 do
        if i ~= 10 and i ~= 11 and a[i] ~= b[i] then return nil end
    end
    for _, column in ipairs({ 10, 11 }) do
        local separator = column == 10 and "," or "|"
        local values, seen = {}, {}
        for _, source in ipairs({ a[column], b[column] }) do
            for value in source:gmatch("[^" .. separator .. "]+") do
                if not seen[value] then seen[value] = true; values[#values + 1] = value end
            end
        end
        table.sort(values)
        a[column] = table.concat(values, separator)
    end
    return table.concat(a, "\t")
end

local function Render(lines)
    local byIdentity, order, conflicts = {}, {}, 0
    for _, line in ipairs(lines) do
        local origin, rest = line:match("^([^\t]*)\t(.*)$")
        if not ORIGIN_RANK[origin] then
            Fail("row carries no origin: " .. line:sub(1, 120))
        end
        local identity = select(8, rest:match("^(.-)\t(.-)\t(.-)\t(.-)\t(.-)\t(.-)\t(.-)\t(.-)\t"))
        if not identity then Fail("row is not a 12-field record: " .. line:sub(1, 120)) end
        local previous = byIdentity[identity]
        if previous == nil then
            byIdentity[identity] = { origin = origin, line = rest }
            order[#order + 1] = identity
        elseif previous.line ~= rest then
            if ORIGIN_RANK[origin] > ORIGIN_RANK[previous.origin] then
                byIdentity[identity] = { origin = origin, line = rest }
            elseif previous.origin == origin then
                local merged = MergeSelectorContracts(previous.line, rest)
                if merged then
                    previous.line = merged
                else
                    conflicts = conflicts + 1
                    local page, label = rest:match("^([^\t]*)\t([^\t]*)\t")
                    io.stderr:write(string.format(
                        "search static index: clients disagree about %s / %s; keeping the first client's row\n",
                        tostring(page), tostring(label)))
                end
            end
        end
    end
    if conflicts > 0 then
        io.stderr:write(string.format("search static index: %d identity conflicts resolved in matrix order\n",
            conflicts))
    end
    local unique = {}
    for _, identity in ipairs(order) do unique[#unique + 1] = byIdentity[identity].line end
    table.sort(unique)
    local blob = table.concat(unique, "\n")
    if blob:find("]==]", 1, true) then Fail("blob would terminate its own long string") end

    return #unique, table.concat({
        "-- Generated by .github/scripts/search_static_index_project.lua. Do not edit by hand.\n",
        "--\n",
        "-- Complete Menu2 control inventory for search. One string constant, so login\n",
        "-- pays only the parse of a literal; it is split into records the first time a\n",
        "-- player actually uses search (see MSUF_Menu2_Search_StaticIndex.lua).\n",
        "-- Columns: pageKey, label, kind, settingKey, actionKey, hint, labelNorm, searchIdentity, exactSectionId, exactTargetKinds, exactTargetContracts, haystack\n",
        "local _, MSUF = ...\n",
        "MSUF = MSUF or _G.MSUF_NS or {}\n",
        "local M = MSUF.MSUF2 or {}\n",
        "MSUF.MSUF2 = M\n",
        "local Search = M.Search or {}\n",
        "M.Search = Search\n",
        "Search.StaticIndexSourceSha256 = \"" .. SOURCE_SHA256 .. "\"\n",
        "Search.StaticIndexRecordCount = " .. tostring(#unique) .. "\n",
        "Search.StaticIndexBlob = [==[\n",
        blob,
        "\n]==]\n",
    })
end

--- Builds one flavor in this process. The crosswalk harness registers pages and
--- catalog records into process-wide state, so it can only run once; a file that
--- covers several flavors is assembled from one child process per flavor below.
local function BuildFlavor(target)
    -- WoW Forever reads the Mainline TOCs, so every manifest follows the matrix row,
    -- not the build target name.
    local suffix = (TargetRow(target)).Suffix
    local schemaPaths = ControlSchemaPaths(suffix)
    local collected
    _G.__MSUF_EmitSearchStaticIndex = function(M, Catalog, buildFailures)
        collected = Collect(M, Catalog, schemaPaths, buildFailures)
    end
    local client = InstallClientFacts(target)
    _G.__MSUF_MENU2_XML_MANIFEST = Menu2Manifests(suffix)

    local harness = Read(HARNESS_PATH)
    -- The appearance hook is a direct TOC Lua entry before the XML manifests.
    -- Load it into the same namespace before tokens, just as Options does in game.
    local hookAt = harness:find(HARNESS_MANIFEST_HOOK, 1, true)
    if hookAt then
        harness = harness:sub(1, hookAt - 1)
            .. 'assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme_Forever.lua"))("MidnightSimpleUnitFrames", MSUF)\n'
            .. harness:sub(hookAt)
    end
    local cut = harness:find(HARNESS_CUT, 1, true)
    if not cut then Fail(HARNESS_PATH .. ": bootstrap boundary marker moved") end
    if not harness:find(HARNESS_MANIFEST_HOOK, 1, true) then
        Fail(HARNESS_PATH .. ": the Menu2 manifest hook moved; the flavor list is no longer honored")
    end
    local failuresAt = harness:find(HARNESS_FAILURES_LOCAL, 1, true)
    if not failuresAt or failuresAt > cut then
        Fail(HARNESS_PATH .. ": the page build failure list moved; unbuilt pages could no longer be told apart")
    end
    local chunk, err = loadstring(
        harness:sub(1, cut) .. "\n__MSUF_EmitSearchStaticIndex(M, Catalog, pageBuildFailures)\n", "@" .. HARNESS_PATH)
    if not chunk then Fail(HARNESS_PATH .. ": " .. tostring(err)) end
    local ok, result = pcall(chunk)
    if not ok then Fail("harness failed for " .. target .. ": " .. tostring(result)) end
    if type(collected) ~= "table" then Fail("harness produced no rows for " .. target) end
    io.stderr:write(string.format("search static index: %s (%s, interface %s) built %d rows\n",
        target, client.Family, tostring(client.Interface), #collected))
    return collected
end

--- Runs this script again for one flavor and reads its rows back. The child prints a
--- terminator, so a child that died mid-run can never be mistaken for a short index.
local function BuildFlavorInChild(suffix)
    local interpreter, script = arg[-1], arg[0]
    if type(interpreter) ~= "string" or type(script) ~= "string" then
        Fail("cannot re-invoke this script: the interpreter or script path is unknown")
    end
    local command = string.format('"%s" "%s" --flavor %s %s', interpreter, script, suffix, ROWS_ONLY_FLAG)
    if package.config:sub(1, 1) == "\\" then command = '"' .. command .. '"' end
    local pipe, err = io.popen(command, "r")
    if not pipe then Fail("could not start the " .. suffix .. " child run: " .. tostring(err)) end
    local lines, terminated = {}, false
    for line in pipe:lines() do
        line = line:gsub("\r$", "")
        if line == ROWS_TERMINATOR then
            terminated = true
        elseif line ~= "" then
            lines[#lines + 1] = line
        end
    end
    pipe:close()
    if not terminated then
        Fail("the " .. suffix .. " child run did not finish; rerun it directly to see its error")
    end
    return lines
end

local rows = {}
if ROWS_ONLY then
    io.write(table.concat(BuildFlavor(FLAVOR), "\n"), "\n", ROWS_TERMINATOR, "\n")
    return
end
for _, target in ipairs(BUILD_FLAVORS) do
    for _, line in ipairs(BuildFlavorInChild(target)) do rows[#rows + 1] = line end
end

local count, text = Render(rows)
local toStdout = false
for i = 1, #(arg or {}) do
    if arg[i] == "--stdout" then toStdout = true end
end
if toStdout then
    io.write(text)
else
    local handle, err = io.open(OUTPUT_PATH, "wb")
    if not handle then Fail(OUTPUT_PATH .. ": " .. tostring(err)) end
    handle:write(text)
    handle:close()
end
io.stderr:write(string.format("search static index: %d records from %s, %.0f KB -> %s\n",
    count, table.concat(BUILD_FLAVORS, "+"), #text / 1024, toStdout and "stdout" or OUTPUT_PATH))
