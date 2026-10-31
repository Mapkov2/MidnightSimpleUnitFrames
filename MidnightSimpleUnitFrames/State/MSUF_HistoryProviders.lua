local _, MSUF = ...
local Providers, registry, aliases = {}, {}, {}
MSUF.HistoryProviders = Providers
local Copy = MSUF.Util.DeepCopy
local function IsFunction(value) return type(value) == "function" end
local function Assign(key, provider)
    local previous = registry[key]
    for _, alias in ipairs(previous and previous.aliases or {}) do aliases[alias] = nil end
    registry[key] = provider
    for _, alias in ipairs(provider and provider.aliases or {}) do aliases[alias] = key end
end
function Providers.Register(key, capture, restore, metadata)
    if type(key) ~= "string" or key == "" or not IsFunction(capture) or not IsFunction(restore)
        or (aliases[key] and aliases[key] ~= key) then return false end
    local provider = { capture = capture, restore = restore }
    if metadata then
        if type(metadata) ~= "table" or getmetatable(metadata) ~= nil then return false end
        local roots, names = metadata.roots, metadata.aliases
        if roots ~= nil and (type(roots) ~= "table" or getmetatable(roots) ~= nil) then return false end
        if names ~= nil and (type(names) ~= "table" or getmetatable(names) ~= nil) then return false end
        if not IsFunction(metadata.covers) or (metadata.merge ~= nil and not IsFunction(metadata.merge)) then return false end
        provider.roots, provider.aliases = {}, {}
        provider.covers, provider.merge = metadata.covers, metadata.merge
        for root, claimed in pairs(roots or {}) do
            if claimed ~= false then
                if type(root) ~= "string" or claimed ~= true or not MSUF.ProfileFields.IsExternal(root) then return false end
                provider.roots[root] = true
            end
        end
        for index, alias in ipairs(names or {}) do
            if type(alias) ~= "string" or alias == "" or alias == key or registry[alias]
                or (aliases[alias] and aliases[alias] ~= key) then return false end
            provider.aliases[index] = alias
        end
        for index in pairs(names or {}) do
            if type(index) ~= "number" or index < 1 or index > #provider.aliases or index ~= math.floor(index) then return false end
        end
        for other, owner in pairs(registry) do
            if other ~= key then
                for root in pairs(provider.roots) do
                    if owner.roots and owner.roots[root] then return false end
                end
            end
        end
    end
    local previous = registry[key]
    Assign(key, provider)
    return true, previous
end
function Providers.RestoreRegistration(key, previous) Assign(key, previous) end
function Providers.Unregister(key) Assign(key, nil) end
function Providers.CoveredRoots(key, value)
    local provider = registry[key]
    if not provider or not provider.roots or not provider.covers then return nil, true end
    local ok, covered, why = MSUF.RunIntegrationCall({ label = "history provider ownership " .. key }, provider.covers, value)
    if not ok or covered == nil then return nil, false, why end
    return covered == true and provider.roots or nil, true
end
function Providers.CaptureOne(key, copy)
    local provider = registry[key]
    if not provider then return nil, false end
    local ok, value = MSUF.RunIntegrationCall({ label = "history provider capture " .. key }, provider.capture)
    if not ok or value == false then return nil, false end
    if copy == false then return value, true end
    local copied, valid = MSUF.ProfileFields.CopySnapshot(value)
    return copied, valid
end
function Providers.Capture(copy)
    local snapshot, owned = {}, nil
    for key in pairs(registry) do
        local value, valid = Providers.CaptureOne(key, copy)
        if not valid then return nil end
        local roots, covered = Providers.CoveredRoots(key, value)
        if not covered then return nil end
        for root in pairs(roots or {}) do
            owned = owned or {}
            owned[root] = key
        end
        snapshot[key] = value
    end
    return snapshot, owned
end
-- A callback receives only private copies of its declared synthetic roots.
function Providers.CopyRoots(profile, roots)
    local projection = {}
    for root in pairs(roots) do projection[root] = profile[root] end
    return MSUF.ProfileFields.CopySnapshot(projection)
end
-- Select one registered owner for each saved payload. Old duplicate Suite
-- points prefer their richer Options alias; new points write only the key.
-- Root data introduced by an older sparse history entry is reconciled by
-- that owner, never silently hidden by the cursor's newer full payload.
function Providers.Prepare(snapshot)
    local values, selected, owned, bindings = snapshot.externalProviders, {}, nil, {}
    if values == nil then values = {} elseif type(values) ~= "table" then return nil end
    for savedKey in pairs(values) do
        local key = registry[savedKey] and savedKey or aliases[savedKey]
        if not key then return nil end
        if selected[key] == nil then
            local provider, value = registry[key], values[key]
            for _, alias in ipairs(provider.aliases or {}) do
                if values[alias] ~= nil then value = values[alias] break end
            end
            selected[key], bindings[key] = value, provider
        end
    end
    for key, value in pairs(selected) do
        local roots, valid = Providers.CoveredRoots(key, value)
        if not valid then return nil end
        local profile, recorded = snapshot.profileDB, snapshot._msuf2HistoryOwners
        if recorded ~= nil and type(recorded) ~= "table" then return nil end
        for root in pairs(roots or {}) do
            if recorded and recorded[root] == key and profile and profile[root] ~= nil then
                local merge = registry[key].merge
                if not merge then return nil end
                local copied, copiedOK = MSUF.ProfileFields.CopySnapshot(value)
                if not copiedOK then return nil end
                local projection, projectionOK = Providers.CopyRoots(profile, roots)
                if not projectionOK then return nil end
                local ok, merged = MSUF.RunIntegrationCall({ label = "history provider root merge " .. key }, merge, copied, projection)
                if not ok or not merged then return nil end
                selected[key] = merged
                roots, valid = Providers.CoveredRoots(key, merged)
                if not valid or not roots then return nil end
                break
            end
        end
        if roots then
            owned = owned or {}
            for root in pairs(roots) do owned[root] = key end
        end
    end
    return { values = selected, roots = owned, providers = bindings }
end
function Providers.Restore(snapshot, reason, source, restoreAll, plan)
    plan = plan or Providers.Prepare(snapshot)
    if not plan then return false end
    local restored = true
    for key, value in pairs(plan.values) do
        local provider = plan.providers[key]
        local ok, result = false, false
        if provider and registry[key] == provider then
            ok, result = MSUF.RunIntegrationCall({ label = "history provider restore " .. key },
                provider.restore, Copy(value), reason, source)
        end
        if not ok or result == false then
            restored = false
            if not restoreAll then return false end
        end
    end
    return restored
end
-- Capture the live state, not the cursor already staged by Undo/Redo. Both
-- attempts cross the callback boundary, so a provider cannot leak restore flags.
function Providers.Transaction(snapshot, reason, source, capture, restore)
    local ok, before = MSUF.RunIntegrationCall({ label = "history restore capture" }, capture)
    if not ok or type(before) ~= "table" then return false, "history_snapshot_failed" end
    local applied, result = MSUF.RunIntegrationCall({ label = "history restore" }, restore, snapshot, reason, source)
    if applied and result ~= false then return true end
    local rolledBack, restored = MSUF.RunIntegrationCall({ label = "history rollback" }, restore,
        before, reason, source, true)
    local why = rolledBack and restored ~= false and "history_restore_failed" or "history_rollback_failed"
    local message = why == "history_restore_failed" and "The settings could not be restored; the history entry was kept."
        or "The previous settings could not be restored; the history entry was kept."
    MSUF.RunIntegrationCall({ label = "history failure report" }, MSUF.ReportError, "history restore", MSUF.Translate(message))
    return false, why
end
