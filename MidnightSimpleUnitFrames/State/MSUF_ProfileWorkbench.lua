-- Explicit, cold-path profile tools. No timer or gameplay listener belongs here.
local _, MSUF = ...
local W, Fields = {}, MSUF.ProfileFields
MSUF.ProfileWorkbench = W
local providers = {}
local MAX_POINTS, MAX_BYTES = 12, 8 * 1024 * 1024
local MAX_ID = 9007199254740990
local function Whole(value, maximum)
    return type(value) == "number" and value >= 0 and value <= maximum and value == math.floor(value)
end
local function Database()
    return MSUF.History.EnsureDB()
end
local function Storage()
    Database()
    local global = MSUF_GlobalDB
    global.global = global.global or {}
    local saved = global.global.profileWorkbench
    if type(saved) ~= "table" or saved.version ~= 1 then
        saved = { version = 1, points = {}, serial = 0 }
        global.global.profileWorkbench = saved
    end
    if type(saved.points) ~= "table" then saved.points = {} end
    for i = #saved.points, 1, -1 do
        local point = saved.points[i]
        if i > MAX_POINTS or type(point) ~= "table" or not Whole(point.id, MAX_ID) or point.id < 1
            or type(point.profile) ~= "string" or type(point.label) ~= "string"
            or type(point.snapshot) ~= "table" or type(point.snapshot.core) ~= "table" then
            table.remove(saved.points, i)
        else
            if not Whole(point.bytes, MAX_BYTES) then point.bytes = MAX_BYTES end
            if not Whole(point.time, 9999999999) then point.time = nil end
        end
    end
    if not Whole(saved.serial, MAX_ID) then saved.serial = 0 end
    for _, point in ipairs(saved.points) do saved.serial = math.max(saved.serial, point.id) end
    if saved.serial >= MAX_ID then
        for i = #saved.points, 1, -1 do saved.points[i].id = #saved.points - i + 1 end
        saved.serial = #saved.points
    end
    return saved
end
function W.CanEdit()
    if MSUF.Public.IsConfigCombatLocked() then return false, "Settings cannot be changed in combat." end
    if not MSUF.ProfileVariants.CanMutateProfile() then return false, "Finish editing the variant first." end
    return true
end
local function RegisterHistoryProvider(id, provider)
    if provider.Capture and provider.Restore and not provider.historyRegistered then
        local ownership = provider.OwnsSnapshot and { roots = provider.OwnsRoots, covers = provider.OwnsSnapshot,
            aliases = provider.HistoryAliases, merge = provider.MergeRoots }
        provider.historyRegistered = MSUF.History.RegisterHistoryProvider("workbench:" .. id,
            provider.Capture, provider.Restore, ownership)
        provider.historyOwnership = ownership ~= nil
    end
end
function W.RegisterProvider(id, provider)
    if type(id) ~= "string" or type(provider) ~= "table" then return false end
    providers[id] = provider
    -- A saved guided-tour point can restore before the Workbench is opened.
    RegisterHistoryProvider(id, provider)
    return true
end
function W.HistoryOwnsRoots(id)
    local provider = providers[id]
    return provider ~= nil and provider.historyRegistered == true and provider.historyOwnership == true
end
local function Invoke(id, method, value, roots)
    local provider = providers[id]
    if not provider or type(provider[method]) ~= "function" then return false, "Profile provider unavailable." end
    local state = { label = "profile workbench " .. id .. " " .. method }
    local ok, result, why = MSUF.RunIntegrationCall(state, provider[method], value, roots)
    if not ok or result == false or result == nil then return false, why or "Profile provider failed." end
    return result
end
function W.Snapshot()
    local db = Database()
    local extra, owned = {}, nil
    for id, provider in pairs(providers) do
        if provider.Capture then
            local value, reason = Invoke(id, "Capture")
            if value == false then return nil, reason end
            extra[id] = value
            RegisterHistoryProvider(id, provider)
            local roots, valid = MSUF.HistoryProviders.CoveredRoots("workbench:" .. id, value)
            if not valid then return nil, "Profile provider failed." end
            for root in pairs(roots or {}) do owned = owned or {} owned[root] = true end
        end
    end
    local core, why = MSUF.ProfileVariants.BaseSnapshot(db, true, owned)
    if not core then return nil, why end
    for _, provider in pairs(providers) do
        if not provider.OwnsSnapshot then
            for root in pairs(provider.OwnsRoots or {}) do core[root] = nil end
        end
    end
    local budget = { maxBytes = MAX_BYTES, count = 0, limit = 131072, maxDepth = 32 }
    local copy, valid = Fields.CopySnapshot({ core = core, providers = extra }, budget)
    if not valid then return nil, "Restore point exceeds the storage limit." end
    local bytes = (budget.bytes or 0) + (budget.count or 0) * 64
    if bytes > MAX_BYTES then return nil, "Restore point exceeds the storage limit." end
    return copy, nil, bytes
end
local function ProfileName()
    return Fields.ProfileName(Database())
end
function W.Checkpoint(label, automatic)
    local ok, why = W.CanEdit()
    if not ok then return false, why end
    local snapshot, reason, bytes = W.Snapshot()
    if not snapshot then return false, reason end
    local saved = Storage()
    saved.serial = (tonumber(saved.serial) or 0) + 1
    local point = { id = saved.serial, profile = ProfileName(), label = tostring(label or "Restore point"):sub(1, 96),
        automatic = automatic == true, snapshot = snapshot, bytes = bytes, time = GetServerTime() }
    table.insert(saved.points, 1, point)
    local total = 0
    for i = #saved.points, MAX_POINTS + 1, -1 do table.remove(saved.points, i) end
    for i = 1, #saved.points do total = total + (saved.points[i].bytes or MAX_BYTES) end
    while total > MAX_BYTES and #saved.points > 1 do
        total = total - (saved.points[#saved.points].bytes or MAX_BYTES)
        table.remove(saved.points)
    end
    return true, point.id
end
function W.Points()
    local result = {}
    for _, point in ipairs(Storage().points) do
        if point.profile == ProfileName() then result[#result + 1] = point end
    end
    return result
end
function W.DeletePoint(id)
    local ok, why = W.CanEdit()
    if not ok then return false, why end
    for i, point in ipairs(Storage().points) do
        if point.id == id and point.profile == ProfileName() then
            table.remove(Storage().points, i)
            return true
        end
    end
    return false
end
local RestoreProviders
function W.Rollback(snapshot)
    local restored, why = RestoreProviders(snapshot)
    if not restored then return false, why end
    local candidate = Fields.CopySnapshot(snapshot.core)
    Fields.StripExternal(candidate)
    return MSUF.ProfileImportReview.Commit(candidate)
end
RestoreProviders = function(snapshot)
    local prepared, owned = {}, nil
    for id, value in pairs(snapshot.providers or {}) do
        local roots, valid = MSUF.HistoryProviders.CoveredRoots("workbench:" .. id, value)
        if not valid then return false, "Profile provider failed." end
        for root in pairs(roots or {}) do
            local provider = providers[id]
            if snapshot.core[root] ~= nil and provider.MergeRoots then
                local projection, projectionOK = MSUF.HistoryProviders.CopyRoots(snapshot.core, roots)
                if not projectionOK then return false, "Profile provider failed." end
                local merged, why = Invoke(id, "MergeRoots", Fields.CopySnapshot(value), projection)
                if not merged then return false, why end
                value = merged
            end
            if snapshot.core[root] == nil or provider.MergeRoots then
                owned = owned or {}
                owned[root] = true
            end
        end
        prepared[id] = value
    end
    for id, value in pairs(prepared) do
        local ok, why = Invoke(id, "Restore", Fields.CopySnapshot(value))
        if not ok then return false, why end
    end
    return Fields.RestoreExternal(Database(), snapshot.core, owned)
end
function W.ApplySnapshot(snapshot, label)
    local ok, why = W.CanEdit()
    if not ok then return false, why end
    local before, reason = W.Snapshot()
    if not before then return false, reason end
    local candidate, valid = Fields.CopySnapshot(snapshot)
    if not valid or type(candidate.core) ~= "table" then return false, "Invalid restore point." end
    -- Saved versions can outlive a profile schema. Repair a private core
    -- before the checkpoint or any provider restore touches live settings.
    local staged, normalized, normalizeWhy = MSUF.RunIntegrationCall({ label = "profile restore normalization" },
        MSUF.ProfileImportReview.PrepareSnapshot, candidate.core)
    if not staged or not normalized then return false, normalizeWhy or "Invalid restore point." end
    local checkpoint, checkpointWhy = W.Checkpoint(label or "Before profile change", true)
    if not checkpoint then return false, checkpointWhy end
    local prepared = MSUF.History.PrepareHistoryChange(label, "profile-workbench")
    local completed, failure, rollback = false, nil, true
    local function Apply()
        local restored, restoreWhy = RestoreProviders(candidate)
        if not restored then failure = restoreWhy return end
        completed, failure = MSUF.ProfileImportReview.Commit(normalized)
    end
    local function Finish(success)
        if success and completed then return end
        rollback = RestoreProviders(before)
        Fields.StripExternal(before.core)
        rollback = MSUF.ProfileImportReview.Commit(before.core) and rollback
    end
    local committed = MSUF.RunLabeledStep("profile restore transaction", Apply, Finish)
    if not committed or not completed then
        return false, rollback and failure or "Profile provider rollback failed. Use the saved restore point."
    end
    MSUF.History.CommitPreparedHistory(prepared)
    return true
end
function W.Restore(id)
    for _, point in ipairs(W.Points()) do
        if point.id == id then return W.ApplySnapshot(point.snapshot, "Before restoring a version") end
    end
    return false, "Restore point unavailable."
end
local function AppendSpecial(changes, before, after, key, provider)
    if Fields.Equal(before, after) then return end
    changes[#changes + 1] = { path = { key }, value = Fields.CopySnapshot(after), before = Fields.CopySnapshot(before),
        remove = after == nil, selected = true, provider = provider, special = not provider }
end
local function ProviderChanges(changes, before, after, path)
    if Fields.Equal(before, after) then return true end
    if #changes >= 8192 or #path > 24 then return false end
    if type(before) == "table" and type(after) == "table" then
        local keys = {}
        for key in pairs(before) do keys[key] = true end
        for key in pairs(after) do keys[key] = true end
        for key in pairs(keys) do
            path[#path + 1] = key
            if not ProviderChanges(changes, before[key], after[key], path) then return false end
            path[#path] = nil
        end
    else
        changes[#changes + 1] = { path = Fields.CopySnapshot(path), value = Fields.CopySnapshot(after),
            before = Fields.CopySnapshot(before), selected = true, provider = true }
    end
    return true
end
function W.ReviewSnapshot(after, label)
    local before, why = W.Snapshot()
    if not before then return nil, why end
    local changes, reason, skipped = Fields.Diff(before.core, after.core, 8192)
    if not changes or skipped ~= 0 then return nil, reason or "Some changes cannot be reviewed safely." end
    for _, change in ipairs(changes) do
        change.before = Fields.CopySnapshot(Fields.Read(before.core, change.path))
        change.selected = true
    end
    AppendSpecial(changes, before.core.profileVariants, after.core.profileVariants, "profileVariants")
    for id, value in pairs(after.providers or {}) do
        if not ProviderChanges(changes, before.providers[id], value, { id }) then
            return nil, "Some changes cannot be reviewed safely."
        end
    end
    return { before = before, after = after, changes = changes, label = label, profile = ProfileName() }
end
function W.ReviewImport(text)
    local before, why = W.Snapshot()
    if not before then return nil, why end
    for id, provider in pairs(providers) do
        if provider.AcceptsImport and provider.AcceptsImport(text) then
            local incoming, reason = Invoke(id, "PrepareImport", text)
            if not incoming then return nil, reason end
            local candidate = before.core
            if incoming.coreText then
                candidate, reason = MSUF.ProfileImportReview.Prepare(incoming.coreText, before.core)
                if not candidate then return nil, reason end
            end
            candidate.suiteModules = incoming.modules or before.core.suiteModules
            before.providers[id] = incoming.provider or before.providers[id]
            return W.ReviewSnapshot({ core = candidate, providers = before.providers }, "Before importing settings")
        end
    end
    local candidate, reason = MSUF.ProfileImportReview.Prepare(text, before.core)
    if not candidate then return nil, reason end
    candidate.suiteModules = before.core.suiteModules
    return W.ReviewSnapshot({ core = candidate, providers = before.providers }, "Before importing settings")
end
function W.CommitReview(review)
    if not review or review.profile ~= ProfileName() then return false, "The active profile changed. Review again." end
    local current, why = W.Snapshot()
    if not current then return false, why end
    if not Fields.Equal(current, review.before) then return false, "Settings changed. Review again before applying." end
    local nextSnapshot = Fields.CopySnapshot(review.before)
    for _, change in ipairs(review.changes) do
        if change.selected then
            local value = Fields.CopySnapshot(change.value)
            if change.provider then
                local target = nextSnapshot.providers
                for i = 1, #change.path - 1 do
                    target[change.path[i]] = target[change.path[i]] or {}
                    target = target[change.path[i]]
                end
                target[change.path[#change.path]] = value
            elseif change.special then nextSnapshot.core[change.path[1]] = value
            else Fields.Write(nextSnapshot.core, change.path, value) end
        end
    end
    return W.ApplySnapshot(nextSnapshot, review.label)
end
function W.Preserve(review, kind, preserve)
    for _, change in ipairs(review.changes) do
        local key = tostring(change.path[#change.path]):lower()
        local matches = kind == "fonts" and (key:find("font", 1, true) or key:find("textsize", 1, true))
            or kind == "positions" and (key:find("offset", 1, true) or key:find("anchor", 1, true)
                or key == "x" or key == "y" or key:find("position", 1, true))
        if matches then change.selected = not preserve end
    end
end
function W.InspectProviders()
    local rows = {}
    for id, provider in pairs(providers) do
        if provider.Inspect then
            local result = Invoke(id, "Inspect")
            if type(result) == "table" then
                for _, row in ipairs(result) do rows[#rows + 1] = row end
            end
        end
    end
    return rows
end
