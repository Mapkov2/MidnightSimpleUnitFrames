-- Search navigation for profile editors is independent of mutation eligibility.
local _, MSUF = ...
local M = MSUF.MSUF2
local H = {}
M.ProfileSearch = H
local serial, targets, tokens = 0, {}, setmetatable({}, { __mode = "k" })
local selectors, selectedNames = {}, {}
local lastDB, lastSchema, lastGroups, lastProfile, lastRecording
local definitions = {
    variant = {
        { "variant.condition.context", "Where", "dropdown" },
        { "variant.condition.dark", "Dark Mode condition", "dropdown" },
        { "variant.condition.hotkey", "Activation", "dropdown" },
        { "variant.enabled", "Enable variant", "toggle" },
        { "variant.conditions.save", "Save conditions", "button" },
        { "variant.delete", "Delete variant", "button" },
        { "variant.values.edit", "Edit variant values", "button", "idle" },
        { "variant.activate", "Use hotkey variant", "button", "idle" },
        { "variant.values.save", "Save variant values", "button", "editing" },
        { "variant.values.cancel", "Cancel variant editing", "button", "editing" },
        { "variant.field.select", "Overridden settings", "dropdown" },
        { "variant.field.remove", "Return setting to base", "button" },
    },
    sync = {
        { "sync.group.save", "Save sync group", "button" },
        { "sync.group.delete", "Delete sync group", "button" },
        { "sync.flush", "Synchronize changes now", "button" },
        { "sync.initialize", "Copy shared modules now", "button" },
        { "sync.field.search", "Find a setting to exclude", "editbox" },
        { "sync.field.select", "Setting", "dropdown" },
        { "sync.field.exclude", "Exclude this setting", "button" },
        { "sync.exclusion.select", "Excluded settings", "dropdown" },
        { "sync.exclusion.remove", "Remove exclusion", "button" },
    },
}
local fixed = {
    ["variant.select"] = true, ["variant.name"] = true, ["variant.create"] = true,
    ["sync.group.select"] = true, ["sync.group.name"] = true, ["sync.group.create"] = true,
    profileExportVariants = true, profileImportVariants = true,
}
local function Context()
    local db = _G.MSUF_DB
    local global = _G.MSUF_GlobalDB and _G.MSUF_GlobalDB.global
    return db, db and db.profileVariants, global and global.profileSyncGroups,
        _G.MSUF_ActiveProfile or "Default", MSUF.ProfileVariants and MSUF.ProfileVariants.RecordingName()
end
local function Entries(scope)
    local db, schema, groups = Context()
    return scope == "variant" and (schema and schema.entries or {}) or groups or {}, db
end
local function Current(target)
    local entries, db = Entries(target.scope)
    if db ~= target.db or (_G.MSUF_ActiveProfile or "Default") ~= target.profile then return false end
    for _, entry in ipairs(entries) do
        if entry == target.entry and entry.name == target.name then return true end
    end
    return false
end
local function Token(scope, entry)
    local existing = tokens[entry]
    local id = existing and existing.name == entry.name and existing.id
    if not id then
        serial = serial + 1
        id = tostring(serial)
        tokens[entry] = { id = id, name = entry.name }
    end
    targets[id] = { scope = scope, entry = entry, name = entry.name,
        db = _G.MSUF_DB, profile = _G.MSUF_ActiveProfile or "Default" }
    return id
end
local function ID(path, token)
    return M.ControlMeta("profiles", "advanced", path, "ephemeral").controlId
        .. (token and (".s" .. token) or "")
end
-- Runs from the search query path (RefreshProviderContexts), so it never
-- rebuilds the Profiles page on screen: that blanked it on the first keystroke.
-- Tokens stay bound to their entry tables (weak keys) and Current() checks the
-- profile, so a built page keeps matching the rows Collect produces; a cached
-- page that is not on screen is rebuilt on its next visit.
function H.ContextChanged()
    local db, schema, groups, profile, recording = Context()
    if db == lastDB and schema == lastSchema and groups == lastGroups and profile == lastProfile
        and recording == lastRecording then return false end
    lastDB, lastSchema, lastGroups, lastProfile, lastRecording = db, schema, groups, profile, recording
    targets = {}
    local onScreen = M.activeKey == "profiles" and M.frame and M.frame.IsShown and M.frame:IsShown()
    if M.cache and M.cache.profiles and not onScreen then M.InvalidatePage("profiles") end
    return true
end
function H.RegisterSelector(scope, selectEntry)
    selectors[scope] = selectEntry
end
function H.Selecting(scope, name)
    selectedNames[scope] = name
end
function H.Meta(path, meta)
    meta.searchIndexed = true
    if fixed[path] then return meta end
    local scope = path:match("^sync%.") and "sync" or "variant"
    local entries = Entries(scope)
    for _, entry in ipairs(entries) do
        if entry.name == selectedNames[scope] then
            local token = Token(scope, entry)
            meta.controlId = ID(path, token)
            meta.searchPrepareKind, meta.searchPrepareValue = "profileEditor", token
            meta.prepareExactSearchTarget = function(_, target)
                local bound = targets[token]
                return target.prepareKind == "profileEditor" and target.prepareValue == token
                    and bound ~= nil and Current(bound) and selectedNames[bound.scope] == bound.name
            end
            return meta
        end
    end
    return meta
end
function H.Prepare(target)
    local bound = targets[target.prepareValue]
    if not bound or not Current(bound) or not selectors[bound.scope] then return false end
    if selectedNames[bound.scope] ~= bound.name then
        selectors[bound.scope](bound.name)
        selectedNames[bound.scope] = bound.name
        M.InvalidatePage("profiles")
    end
    return true
end
function H.Refresh()
    M.InvalidateSearchProvider("profile-editors")
end
function H.Collect()
    targets = {}
    local out = {}
    -- Always-visible editor controls are available even before the page is built.
    for _, spec in ipairs({
        {"profiles_variants", "variant.select", "Variant", "dropdown"},
        {"profiles_variants", "variant.name", "New variant name", "textinput"},
        {"profiles_variants", "variant.create", "Create variant", "button"},
        {"profiles_sync", "sync.group.select", "Sync group", "dropdown"},
        {"profiles_sync", "sync.group.name", "New sync group name", "textinput"},
        {"profiles_sync", "sync.group.create", "Create sync group", "button"},
        {"profiles_variant_transport", "profileExportVariants", "Export profile variants", "toggle"},
        {"profiles_variant_transport", "profileImportVariants", "Import profile variants", "toggle"},
    }) do
        out[#out + 1] = {pageKey="profiles",sectionId=spec[1],
            controlId=M.ControlMeta("profiles",spec[1],spec[2],"ephemeral").controlId,
            label=M.Tr(spec[3]),kind=spec[4],keywords="profile variants profilvariante profile sync profilsynchronisierung"}
    end
    local editing = MSUF.ProfileVariants.IsRecording()
    local specRows, profileNames = M.GetProfileSpecializations(), _G.MSUF_GetAllProfiles()
    local function Add(scope, entry, token, path, label, kind)
        local section = scope == "variant" and "profiles_variants" or "profiles_sync"
        if #out >= 4000 then return false end -- Existing search-provider row contract.
        out[#out + 1] = { pageKey = "profiles", label = M.Tr(label), kind = kind == "editbox" and "textinput" or kind,
            controlId = ID(path, token), sectionId = section,
            prepareKind = "profileEditor", prepareValue = token,
            keywords = { entry.name, scope == "variant" and "profile variants profilvariante profilvariante variante" or
                "profile sync profile synchronization profilsynchronisierung profil synchronisieren" },
            help = entry.name, profileSearchToken = token }
        return true
    end
    for _, scope in ipairs({ "variant", "sync" }) do
        local entries = Entries(scope)
        for _, entry in ipairs(entries) do
            local token = Token(scope, entry)
            for _, spec in ipairs(definitions[scope]) do
                if spec[4] == nil or (spec[4] == "editing") == editing then
                    if not Add(scope, entry, token, spec[1], spec[2], spec[3]) then return out end
                end
            end
            if scope == "variant" then
                for i, spec in ipairs(specRows) do
                    if not Add(scope, entry, token, "variant.spec." .. i, spec.name, "toggle") then return out end
                end
            else
                for i, name in ipairs(profileNames) do
                    if not Add(scope, entry, token, "sync.member." .. i, name, "toggle") then return out end
                end
                for _, module in ipairs(MSUF.ProfileSync.Modules) do
                    if not Add(scope, entry, token, "sync.module." .. module,
                        (MSUF.ProfileSync.Labels and MSUF.ProfileSync.Labels[module]) or module, "toggle") then return out end
                end
            end
        end
    end
    return out
end
-- Search availability predicate: (pageKey, settingKey, record); the record is
-- nil when only a page's availability is asked.
function H.Available(_, _, row)
    if type(row) ~= "table" then return true end
    local token = row.providerRow and row.providerRow.profileSearchToken
        or row.exactTarget and row.exactTarget.prepareKind == "profileEditor" and row.exactTarget.prepareValue
    if not token then return true end
    return targets[token] ~= nil and Current(targets[token])
end
-- The canonical Retail host can load these pages with an older search API.
-- Selected-entry rows need both contracts; legacy hosts keep normal page controls.
if type(M.RegisterSearchAvailability) == "function" then
    M.RegisterSearchProvider("profile-editors", H.Collect, H.ContextChanged)
    M.RegisterSearchAvailability("profile-editors", H.Available)
end
