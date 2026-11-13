-- Project declarations from real page builds, sharing the search generator's
-- client bootstrap and finite workspace traversal. No product metadata is inferred.
local function Read(path)
    local file = assert(io.open(path, "rb"))
    local value = file:read("*a")
    file:close()
    return (value:gsub("\r\n", "\n"))
end
local function Json(value)
    if type(value) == "string" then
        return '"' .. value:gsub('[%z\1-\31\\"]', function(char)
            return string.format("\\u%04x", string.byte(char))
        end) .. '"'
    end
    if type(value) == "boolean" or type(value) == "number" then return tostring(value) end
    if type(value) ~= "table" then return "null" end
    if #value > 0 then
        local out = {}
        for _, item in ipairs(value) do out[#out + 1] = Json(item) end
        return "[" .. table.concat(out, ",") .. "]"
    end
    local fields = {}
    for key in pairs(value) do fields[#fields + 1] = key end
    table.sort(fields)
    local out = {}
    for _, key in ipairs(fields) do out[#out + 1] = Json(key) .. ":" .. Json(value[key]) end
    return "{" .. table.concat(out, ",") .. "}"
end
local projected = {}
local watched = false
local stream, dirty
local initialObservation = false
local settingFingerprints = {}
local function Null() end
local function Plain(value)
    if type(value) == "function" then return Null end
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = Plain(item) end
    return out
end
local function Setter(spec, widget, record)
    local setter = spec.set
    if type(setter) ~= "function" then
        if spec._setter then return spec._setter end
        local command = widget and widget._msuf2CommandAction
        setter = command and command.set
        if type(setter) ~= "function" then
            record = record or (widget and widget._msuf2RuntimeControlRecord)
            setter = record and record.command and record.command.set
        end
    end
    if type(setter) ~= "function" then return nil end
    local info = debug.getinfo(setter, "S")
    return info.source .. ":" .. info.linedefined
end
local function Changed(row, key, value)
    if row[key] ~= value then row[key] = value; if stream then dirty[row.controlId] = true end end
end
local function Flush()
    if not stream or not next(dirty) then return end
    for key in pairs(dirty) do stream:write(Json(projected[key]), "\n") end
    dirty = {}
    stream:flush()
    -- Rows contain only serializable evidence; no widget/callback graph survives.
    -- Incremental collection bounds transient page data without a full heap walk per record read.
    collectgarbage("step", 512)
end

local settingKinds = { toggle = true, checkbox = true, slider = true, dropdown = true,
    segment = true, color = true, textinput = true, editbox = true, input = true }
local declarations = setmetatable({}, { __mode = "k" })
local declaredSchemas = setmetatable({}, { __mode = "k" })
-- Decorative rows repeat across selectors (one class name per drag row, for
-- example). Their widgets can be collected before the next inventory pass.
-- Keep only data, retain every distinct label/scope pair, and use one pair
-- as the deterministic representative expected by existing evidence readers.
local presentation = {}
local pendingPresentation = {}
local candidates, candidateByWidget, candidateWidgets = {}, setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "v" })
local nextCandidate = 0
local function IsPresentation(spec)
    return spec and spec.applyDomain == "presentation" and (spec.kind == "font" or spec.kind == "text")
        and not (spec.setting or spec.set or spec.settingPath or spec.ephemeralReason)
end
local function QueuePresentation(widget, spec, page)
    -- A generic font can become a catalog control or be redeclared as a preview
    -- while the same build is still in progress. Only its last declaration at
    -- the observation boundary counts.
    local old = candidateByWidget[widget]
    if old then candidates[old], candidateWidgets[old], candidateByWidget[widget] = nil, nil, nil end
    if not page or not IsPresentation(spec) or widget._msuf2RuntimeControlRecord then return end
    nextCandidate = nextCandidate + 1
    candidateWidgets[nextCandidate], candidateByWidget[widget] = widget, nextCandidate
    candidates[nextCandidate] = { page = page, id = spec.id, kind = spec.kind, scope = spec.scope,
        labelKey = Plain(spec.labelKey), applyDomain = spec.applyDomain }
end
local function ObservePresentation(widget, spec, page)
    if not page or not IsPresentation(spec) then return false end
    local snapshot = widget and declaredSchemas[widget] and declaredSchemas[widget][spec.id]
    if snapshot and snapshot._presentationPage == page and type(spec.labelKey) ~= "table"
        and snapshot.kind == spec.kind and snapshot.scope == spec.scope and snapshot.labelKey == spec.labelKey then
        return true
    end
    local id = "schema:" .. page .. ":" .. spec.id
    local group = presentation[id]
    if not group then
        group = { id = spec.id, page = page, variants = {}, count = 0 }
        presentation[id] = group
    end
    local label = spec.labelKey or ""
    local variant = { kind = spec.kind, scope = spec.scope, label = label }
    local encoded = Json(variant)
    if not group.variants[encoded] then
        -- Stub values sometimes stand in for unavailable localized labels.
        -- Preserve their JSON form, and prefer an observed real label for display.
        variant.label = Plain(label)
        group.variants[encoded] = variant
        group.count = group.count + 1
        local rank = type(label) == "string" and label ~= "" and 0 or 1
        if not group.bestKey or rank < group.rank or (rank == group.rank and encoded < group.bestKey) then
            group.bestKey, group.rank = encoded, rank
        end
        pendingPresentation[id] = group
    end
    if snapshot then snapshot._presentationPage = page end
    return true
end
local function PublishPresentation()
    -- Surviving widgets were inspected with their final catalog/preview state
    -- just above this boundary. A collected widget cannot be inspected now.
    for index, candidate in pairs(candidates) do
        if not candidateWidgets[index] then ObservePresentation(nil, candidate, candidate.page) end
    end
    candidates, candidateByWidget, candidateWidgets = {}, setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "v" })
    nextCandidate = 0
    for key, group in pairs(pendingPresentation) do
        local best = group.variants[group.bestKey]
        local row = projected[key] or { controlId = key, pageKey = group.page, classification = "unindexed",
            settingKey = "", controlPath = "", schemaId = group.id, applyDomain = "presentation" }
        row.kind, row.schemaKind, row.label, row.scope = best.kind, best.kind, best.label, best.scope
        if group.count > 1 then row.presentationVariants = group.variants end
        projected[key] = row
        if stream then dirty[key] = true end
    end
    pendingPresentation = {}
end
local function Remember(widget, spec)
    local variants = declaredSchemas[widget]
    if not variants then variants = {}; declaredSchemas[widget] = variants end
    local snapshot = {}
    if initialObservation then
        -- The finite initial-page inventory observes declarations once, after
        -- every default page has built. Preserve its original weak-key lifetime.
        for key, value in pairs(spec) do snapshot[key] = value end
        snapshot._setter = Setter(spec, widget)
        variants[spec.id] = snapshot
        return
    end
    for _, key in ipairs({ "id", "kind", "scope", "applyDomain", "settingPath", "ephemeralReason", "labelKey" }) do
        snapshot[key] = spec[key]
    end
    snapshot.setting, snapshot._setter = Plain(spec.setting), Setter(spec, widget)
    if type(spec.setting) == "table" and type(spec.setting.resolve) == "function" then
        snapshot._resolvedPath = spec.setting.resolve()
    end
    variants[spec.id] = snapshot
end
_G.__MSUF_WatchSchema = function(M)
    watched = true
    local schema = M.ControlSchema
    local bind, custom = schema.Bind, schema.Custom
    schema.Bind = function(ctx, widget, spec)
        local result = bind(ctx, widget, spec)
        Remember(widget, widget._msuf2ControlSchema)
        declarations[widget] = ctx and ctx.key or M.PageKeyForWidget(widget) or M.activeKey
        QueuePresentation(widget, widget._msuf2ControlSchema, declarations[widget])
        return result
    end
    schema.Custom = function(widget, spec)
        local result = custom(widget, spec)
        Remember(widget, widget._msuf2ControlSchema)
        declarations[widget] = M.PageKeyForWidget(widget) or M.activeKey
        QueuePresentation(widget, widget._msuf2ControlSchema, declarations[widget])
        return result
    end
end
_G.__MSUF_ProjectSchema = function(M, Catalog)
    -- Generation checks the family contract on a real control without invoking
    -- its getter/setter or changing its binding metadata. The temporary anchor
    -- reproduces the former fixed-gf_party mismatch for another family member.
    local pets = Catalog.Get("menu2.gf_layout.group.field.petsenabled")
    if pets then
        local previous = pets.settingKey
        pets.settingKey = "gf_party.petsEnabled"
        local _, widget = Catalog.ResolveExactTarget("gf_layout", {
            controlId = pets.controlId, settingKey = "gf_raid.petsEnabled" })
        local _, invalid = Catalog.ResolveExactTarget("gf_layout", {
            controlId = pets.controlId, settingKey = "gf_raid.unrelatedSetting" })
        pets.settingKey = previous
        assert(widget == pets.widget and not invalid, "group key family exact-target contract failed")
    end
    local function Project(public, widget, record)
        local key = public.controlId
        -- A shared preview moves between page records. Read the declaration
        -- actually made for this ID; an undeclared context still fails below.
        local variants = widget and declaredSchemas[widget]
        local current = widget and widget._msuf2ControlSchema
        local matches = current and (current.id == key or key == "schema:" .. public.pageKey .. ":" .. current.id)
        local active = widget and widget._msuf2RuntimeControlRecord
        local spec
        if matches or active and active.controlId == key then spec = current
        else spec = variants and variants[key] or current end
        if matches then Remember(widget, current) end
        local row = projected[key]
        if not row then
            row = { controlId = key, pageKey = public.pageKey, kind = public.kind,
                label = public.label, classification = public.classification,
                settingKey = public.settingKey or "", controlPath = public.controlPath or "",
                actionKey = public.actionKey }
            projected[key] = row
            if stream then dirty[key] = true end
        end
        local needsDeclaration = public.classification == "setting" or public.classification == "action"
            or settingKinds[public.kind] or public.classification == "unindexed" and public.kind == "button"
        if needsDeclaration and (not spec or (not spec.setting and not spec.ephemeralReason)) then
            row.observationIssues = row.observationIssues or {}
            local issue = not spec and "missing schema in a live build" or "missing setting/reason in a live build"
            if not row.observationIssues[issue] and stream then dirty[key] = true end
            row.observationIssues[issue] = true
        end
        if spec and needsDeclaration then
            local identity = spec.id == key or key == "schema:" .. public.pageKey .. ":" .. spec.id
            local kinds = { editbox = "textinput", input = "textinput", checkbox = "toggle" }
            if not identity or not spec.scope or not spec.applyDomain or (kinds[public.kind] or public.kind) ~= spec.kind then
                row.observationIssues = row.observationIssues or {}
                if not row.observationIssues["invalid schema provenance in a live build"] and stream then dirty[key] = true end
                row.observationIssues["invalid schema provenance in a live build"] = true
            end
            local setting = spec.setting
            for _, path in ipairs(type(setting) == "string" and { setting } or type(setting) == "table" and setting.keys or {}) do
                local owner, field = path:match("^auras3%.perUnit%.[^.]+%.(layout[^.]*)%.(.+)$")
                if owner then
                    local namespace = M.ControlSchema.AuraLaneSchema()
                    assert((owner == "layoutShared" and namespace.SHARED_LAYOUT_KEYS or namespace.LAYOUT_KEYS)[field],
                        "unknown physical aura layout field: " .. path)
                end
            end
        end
        if spec then
            if stream then row._schemaAssigned = true end
            Changed(row, "schemaId", spec.id)
            Changed(row, "schemaKind", spec.kind)
            Changed(row, "scope", spec.scope)
            Changed(row, "applyDomain", spec.applyDomain)
            Changed(row, "schemaSettingPath", spec.settingPath)
            Changed(row, "ephemeralReason", spec.ephemeralReason)
            if spec.setting then
                local encoded = Json(spec.setting)
                if settingFingerprints[key] ~= encoded then
                    row.setting = Plain(spec.setting)
                    settingFingerprints[key] = encoded
                    if stream then dirty[key] = true end
                end
                row.settingDeclarations = row.settingDeclarations or {}
                if not row.settingDeclarations[encoded] then
                    row.settingDeclarations[encoded] = row.setting
                    if stream then dirty[key] = true end
                end
            end
            if type(spec.setting) == "table" and (spec.setting.resolve or spec._resolvedPath) then
                local path = spec._resolvedPath
                if spec.setting.resolve ~= Null and spec.setting.resolve then path = spec.setting.resolve() end
                if path then
                    assert(M.ControlSchema.Matches(spec.setting, path), "resolver outside declaration: " .. key .. ": " .. path)
                    row.resolvedPaths = row.resolvedPaths or {}
                    if not row.resolvedPaths[path] and stream then dirty[key] = true end
                    row.resolvedPaths[path] = true
                end
            end
            local setter = Setter(spec, widget, record)
            if setter then Changed(row, "setter", setter) end
        end
    end
    local function Capture(records)
        local previousPage
        for _, public in ipairs(records or Catalog.GetRecords()) do
            if previousPage and previousPage ~= public.pageKey then Flush() end
            previousPage = public.pageKey
            local raw = assert(Catalog.Get(public.controlId))
            Project(public, raw.widget, raw)
        end
        -- Includes declarations never registered by search (short/noisy labels,
        -- widgetless composites and deliberately hidden controls).
        for widget, page in pairs(declarations) do
            if not widget._msuf2RuntimeControlRecord then
                local spec = widget._msuf2ControlSchema
                if not ObservePresentation(widget, spec, page) then
                    Project({ controlId = "schema:" .. page .. ":" .. spec.id, pageKey = page,
                        kind = spec.kind, label = spec.labelKey or "", classification = spec.setting and "setting" or "unindexed" }, widget)
                end
            end
        end
        PublishPresentation()
        Flush()
    end
    assert(watched, "schema declaration hook did not install")
    Capture()
    return Capture
end
return {
    InitialObservation = function() initialObservation = true end,
    Stream = function(directory, flavor)
        assert(not stream, "schema stream already open")
        stream = assert(io.open(directory .. "/" .. flavor .. ".ndjson", "wb"))
        dirty = {}
    end,
    Observe = function(M, Catalog)
        __MSUF_ProjectSchema(M, Catalog)
    end,
    Start = function(M, Catalog)
        local capture = __MSUF_ProjectSchema(M, Catalog)
        local get = Catalog.GetRecords
        local inside = false
        Catalog.GetRecords = function()
            local records = get()
            if not inside then
                inside = true
                capture(records)
                inside = false
            end
            return records
        end
    end,
    Data = function() return projected end,
    Count = function()
        local count = 0
        for _ in pairs(projected) do count = count + 1 end
        return count
    end,
    Json = Json,
    Save = function(directory, flavor)
        if stream then
            Flush()
            stream:close()
            stream, dirty = nil, nil
            projected, settingFingerprints, presentation, pendingPresentation = {}, {}, {}, {}
            declarations, declaredSchemas = nil, nil
            collectgarbage("collect")
            return
        end
        local file = assert(io.open(directory .. "/" .. flavor .. ".json", "wb"))
        file:write(Json(projected), "\n")
        file:close()
    end,
}
