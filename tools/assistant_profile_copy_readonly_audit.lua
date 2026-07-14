_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing after dashboard smoke")
local Registry = assert(A.Registry, "Assistant registry missing")

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do out[clone(key, seen)] = clone(item, seen) end
    return out
end

local function equal(a, b, seen)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for key, value in pairs(a) do
        if not equal(value, b[key], seen) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

local function snapshotSettings()
    local out = {}
    for _, setting in ipairs(Registry:AllSettings() or {}) do
        if setting and setting.key and type(setting.get) == "function" then
            local ok, value = pcall(setting.get)
            if ok then out[setting.key] = clone(value) end
        end
    end
    return out
end

local function snapshotProfileState()
    local globalDB = rawget(_G, "MSUF_GlobalDB")
    local profiles = clone(globalDB and globalDB.profiles)
    -- Assistant conversation history is expected to change on every Submit;
    -- it is not profile-copy state and must not mask actual profile mutations.
    for _, profile in pairs(profiles or {}) do
        if type(profile) == "table" then profile.assistant = nil end
    end
    return {
        profiles = profiles,
        char = clone(globalDB and globalDB.char),
        activeProfile = rawget(_G, "MSUF_ActiveProfile"),
    }
end

local function clearConversationState()
    A.pendingConfirmation = nil
    A.pendingChoices = nil
    A.pendingCandidates = nil
    A.pendingResults = nil
    A.pendingSelectedResult = nil
    A.pendingFlow = nil
    local ctx = A.GetContext and A.GetContext() or nil
    if type(ctx) == "table" then
        ctx.pendingConfirmation = nil
        ctx.pendingChoices = nil
        ctx.pendingResults = nil
        ctx.pendingSelectedResult = nil
        ctx.pendingFlow = nil
    end
end

local function assertProfileCopyQuestion(prompt)
    clearConversationState()
    local beforeSettings = snapshotSettings()
    local beforeProfiles = snapshotProfileState()
    local result = assert(A.Submit(prompt), prompt .. ": missing result")
    local afterSettings = snapshotSettings()
    local afterProfiles = snapshotProfileState()

    assert(equal(beforeSettings, afterSettings), prompt .. ": profile-copy question changed a registered setting")
    assert(equal(beforeProfiles, afterProfiles), prompt .. ": profile-copy question changed profile state")
    local status = tostring(result.status or result.result or "")
    assert(status == "info", prompt .. ": expected read-only info status, got " .. status .. ": " .. tostring(result.text))

    local output = tostring(result.text or "")
    assert(output:find("Profile copy help", 1, true), prompt .. ": missing precise Profile copy help: " .. output)
    assert(output:find("destination profile name", 1, true), prompt .. ": missing destination explanation: " .. output)
    assert(not output:find("MSUF option help", 1, true), prompt .. ": fell back to generic option help: " .. output)
    assert(not output:find("I found these MSUF matches", 1, true), prompt .. ": fell back to unrelated search results: " .. output)
end

local profileCopyQuestions = {
    "how to copy profile",
    "can I copy a profile?",
    "how do I copy my profile?",
    "wie kann ich ein profil kopieren?",
    "kann ich ein profil kopieren?",
    "wie kopiere ich mein profil nach Raid Backup?",
}

for i = 1, #profileCopyQuestions do assertProfileCopyQuestion(profileCopyQuestions[i]) end
print("assistant_profile_copy_readonly_audit: ok cases=" .. tostring(#profileCopyQuestions))
