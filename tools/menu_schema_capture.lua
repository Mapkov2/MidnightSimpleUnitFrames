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
local settingKinds = { toggle = true, checkbox = true, slider = true, dropdown = true,
    segment = true, color = true, textinput = true, editbox = true, input = true }
local declarations = setmetatable({}, { __mode = "k" })
_G.__MSUF_WatchSchema = function(M)
    watched = true
    local schema = M.ControlSchema
    local bind, custom = schema.Bind, schema.Custom
    schema.Bind = function(ctx, widget, spec)
        local result = bind(ctx, widget, spec)
        declarations[widget] = ctx and ctx.key or M.PageKeyForWidget(widget) or M.activeKey
        return result
    end
    schema.Custom = function(widget, spec)
        local result = custom(widget, spec)
        declarations[widget] = M.PageKeyForWidget(widget) or M.activeKey
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
    local function Project(public, widget)
        local spec = widget and widget._msuf2ControlSchema
        local key = public.controlId
        local row = projected[key]
        if not row then
            row = { controlId = key, pageKey = public.pageKey, kind = public.kind,
                label = public.label, classification = public.classification,
                settingKey = public.settingKey or "", controlPath = public.controlPath or "",
                actionKey = public.actionKey }
            projected[key] = row
        end
        local needsDeclaration = public.classification == "setting" or public.classification == "action"
            or settingKinds[public.kind] or public.classification == "unindexed" and public.kind == "button"
        if needsDeclaration and (not spec or (not spec.setting and not spec.ephemeralReason)) then
            row.observationIssues = row.observationIssues or {}
            row.observationIssues[not spec and "missing schema in a live build" or "missing setting/reason in a live build"] = true
        end
        if spec and needsDeclaration then
            local identity = spec.id == key or key == "schema:" .. public.pageKey .. ":" .. spec.id
            local kinds = { editbox = "textinput", input = "textinput", checkbox = "toggle" }
            if not identity or not spec.scope or not spec.applyDomain or (kinds[public.kind] or public.kind) ~= spec.kind then
                row.observationIssues = row.observationIssues or {}
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
            row.schemaId, row.schemaKind = spec.id, spec.kind
            row.scope, row.applyDomain = spec.scope, spec.applyDomain
            row.schemaSettingPath = spec.settingPath
            row.ephemeralReason = spec.ephemeralReason
            if spec.setting then
                row.setting = spec.setting
                row.settingDeclarations = row.settingDeclarations or {}
                row.settingDeclarations[Json(spec.setting)] = spec.setting
            end
            if type(spec.setting) == "table" and spec.setting.resolve then
                local path = spec.setting.resolve()
                if path then
                    assert(M.ControlSchema.Matches(spec.setting, path), "resolver outside declaration: " .. key .. ": " .. path)
                    row.resolvedPaths = row.resolvedPaths or {}
                    row.resolvedPaths[path] = true
                end
            end
            local setter = spec.set
            if type(setter) == "function" then
                local info = debug.getinfo(setter, "S")
                row.setter = info.source .. ":" .. info.linedefined
            end
        end
    end
    local function Capture()
        for _, public in ipairs(Catalog.GetRecords()) do
            local raw = assert(Catalog.Get(public.controlId))
            Project(public, raw.widget)
        end
        -- Includes declarations never registered by search (short/noisy labels,
        -- widgetless composites and deliberately hidden controls).
        for widget, page in pairs(declarations) do
            if not widget._msuf2RuntimeControlRecord then
                local spec = widget._msuf2ControlSchema
                Project({ controlId = "schema:" .. page .. ":" .. spec.id, pageKey = page,
                    kind = spec.kind, label = spec.labelKey or "", classification = spec.setting and "setting" or "unindexed" }, widget)
            end
        end
    end
    assert(watched, "schema declaration hook did not install")
    Capture()
    return Capture
end
return {
    Start = function(M, Catalog)
        local capture = __MSUF_ProjectSchema(M, Catalog)
        local get = Catalog.GetRecords
        local inside = false
        Catalog.GetRecords = function()
            local records = get()
            if not inside then
                inside = true
                capture()
                inside = false
            end
            return records
        end
    end,
    Data = function() return projected end,
    Json = Json,
    Save = function(directory, flavor)
        local file = assert(io.open(directory .. "/" .. flavor .. ".json", "wb"))
        file:write(Json(projected), "\n")
        file:close()
    end,
}
