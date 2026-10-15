-- SavedVariables settle before migration and binding. Login consumers run only
-- after that cold boundary, in the explicit order below.
local addonName, MSUF = ...
local Lifecycle = { Bound = false }
MSUF.Lifecycle = Lifecycle
local startup

local phases = {
    settle = {
        function() MSUF.FirstLoad6.SettleSavedVariables(true) end,
    },
    migrate = {
        function()
            MSUF.ClearRetiredProfilerData()
            local cleared = MSUF.ClearRetiredAssistantData()
            startup = MSUF.ProfileBinding.Migrate(MSUF.FirstLoad6.GetLegacyProfileDB(), cleared)
        end,
    },
    bind = {
        function() MSUF.Require("MSUF_InitProfiles", "Kernel/MSUF_Lifecycle.lua")(startup) end,
    },
}

local loginOrder = {
    { "variants", function() MSUF.ProfileVariants.ResolveCurrent() end },
    { "profile_sync", function()
        MSUF.ProfileSync.Activate()
        MSUF.ProfileSync.RefreshEvents()
    end },
    { "number_format", function() MSUF.NumberFormat.Refresh() end },
}

local function RunPhase(phase)
    Lifecycle.Phase = phase
    local steps = phases[phase]
    for i = 1, #steps do steps[i]() end
end

local bus = MSUF.EventBus
bus:Register("ADDON_LOADED", "MSUF_LIFECYCLE_BIND", function(_, loadedName)
    if loadedName ~= addonName then return end
    bus:Unregister("ADDON_LOADED", "MSUF_LIFECYCLE_BIND")
    RunPhase("settle")
    RunPhase("migrate")
    RunPhase("bind")
    startup = nil
    Lifecycle.Bound = true
    Lifecycle.Phase = "ready"
end)
-- Separate bus subscribers preserve native error isolation between login
-- steps. Their registration still comes from this one ordered list.
for i = 1, #loginOrder do
    local step = loginOrder[i]
    bus:Register("PLAYER_LOGIN", "MSUF_LIFECYCLE_" .. step[1], function()
        assert(Lifecycle.Bound, "MSUF: PLAYER_LOGIN before SavedVariables binding")
        Lifecycle.Phase = step[1]
        step[2]()
    end, nil, true)
end
bus:Register("PLAYER_LOGIN", "MSUF_LIFECYCLE_RUNNING", function()
    Lifecycle.Phase = "running"
end, nil, true)

-- The profile stays public through logout restoration and synchronization.
-- Separate native handlers preserve error isolation, including the final clear.
local logoutOrder = {
    function()
        MSUF.ProfileVariants.Restore()
        MSUF.ProfileVariants.CancelRecording(false, true)
    end,
    function() MSUF.ProfileSync.Flush() end,
    function()
        MSUF.DefaultsSchema.Persist(MSUF_GlobalDB)
        _G.MSUF_DB = nil
    end,
}
-- WoW guarantees no last-running PLAYER_LOGOUT handler. These frames register as late as the
-- lifecycle can, so every handler registered earlier (core, Options, the Suite) still reads the
-- bound MSUF_DB. An addon that registers PLAYER_LOGOUT after these frames and reads MSUF_DB sees
-- nil; no known consumer does. Accepted so the SavedVariables file stores the profile only once.
local function RegisterLateLogout()
    for i = 1, #logoutOrder do
        local step = logoutOrder[i]
        local frame = CreateFrame("Frame")
        frame:Hide()
        frame:RegisterEvent("PLAYER_LOGOUT")
        frame:SetScript("OnEvent", step)
    end
end
-- Other addons and lazy State drivers finish their login work first. No shared
-- bus subscriber clears the alias ahead of those native logout handlers.
bus:Register("PLAYER_LOGIN", "MSUF_LIFECYCLE_LOGOUT", function()
    C_Timer.After(0, RegisterLateLogout)
end, nil, true)
