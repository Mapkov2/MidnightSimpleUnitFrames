local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Dashboard assistant action domain.
-- Depends on MSUF_AssistantRegistry_Dashboard.lua for workflow helpers.
local ctx = A.DashboardRegistry and A.DashboardRegistry.Actions
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
A = ctx.A or A
M = ctx.M or M

if not (Registry and type(Registry.RegisterAction) == "function") then return end
local RegisterNavigationActions = A.DashboardRegistry and A.DashboardRegistry.RegisterNavigationActions

local function StageFactoryReset()
    if not (M and type(M.StageFactoryReset) == "function") then
        return false, "Open the Dashboard first so I can stage the factory reset."
    end
    if M.StageFactoryReset() then
        return true, "Done. Factory reset is ready. Reload UI to rebuild clean defaults."
    end
    return false, "Open the Dashboard first so I can stage the factory reset."
end

A.Workflow = A.Workflow or {}
A.Workflow.StageFactoryReset = StageFactoryReset

if type(RegisterNavigationActions) == "function" then
    RegisterNavigationActions(ctx)
end

Registry:RegisterAction({
    key = "factory_reset_all",
    label = "Factory Reset All",
    type = "reset",
    combatSafe = false,
    confirmRequired = true,
    run = function()
        return A.Workflow.StageFactoryReset()
    end,
})

local DASHBOARD_ACTIONS = {
    { "dashboard.globalUiScale.apply", "Apply Global UI Scale", false },
    { "dashboard.globalUiScale.revertPending", "Revert Pending Global UI Scale", true },
    { "dashboard.globalUiScale.disable", "Disable Global UI Scale", false },
    { "dashboard.msufFrameScale.apply", "Apply MSUF Frame Scale", false },
    { "dashboard.msufFrameScale.revertPending", "Revert Pending MSUF Frame Scale", true },
    { "dashboard.menuScale.apply", "Apply MSUF Menu Scale", false },
    { "dashboard.menuScale.revertPending", "Revert Pending MSUF Menu Scale", true },
}
for i = 1, #DASHBOARD_ACTIONS do
    local spec = DASHBOARD_ACTIONS[i]
    Registry:RegisterAction({
        key = spec[1],
        label = spec[2],
        type = "dashboard",
        page = "home",
        combatSafe = spec[3] == true,
        confirmRequired = false,
        run = function()
            if not (M and type(M.RunDashboardDirectAction) == "function") then
                return false, "Open the Dashboard first so I can run that scale action."
            end
            return M.RunDashboardDirectAction(spec[1])
        end,
    })
end

Registry:RegisterAction({
    key = "menu_search_query",
    label = "Run Menu Search",
    type = "navigation",
    combatSafe = false,
    confirmRequired = false,
    run = function(args)
        local query = args and (args.query or args.value or args.text)
        if type(query) ~= "string" or query == "" then
            return false, "What should I search for in the MSUF menu?"
        end
        local bridge = M and M.SearchBridge
        if not (bridge and type(bridge.RunSearchQuery) == "function") then
            return false, "Open the MSUF menu first so I can run that search."
        end
        return bridge.RunSearchQuery(query)
    end,
})

local FIRST_LOAD_ACTIONS = {
    { "personalize", "Start First-Load Guided Setup" },
    { "import_profile", "Open First-Load Profile Import" },
    { "use_defaults", "Keep First-Load Defaults" },
    { "whats_new", "Open First-Load Changelog" },
    { "not_now", "Defer First-Load Setup" },
    { "full_settings", "Open Full Settings from First Load" },
}
for i = 1, #FIRST_LOAD_ACTIONS do
    local suffix, label = FIRST_LOAD_ACTIONS[i][1], FIRST_LOAD_ACTIONS[i][2]
    Registry:RegisterAction({
        key = "first_load." .. suffix,
        label = label,
        type = "onboarding",
        page = "home",
        combatSafe = false,
        confirmRequired = false,
        run = function()
            if not (M and type(M.ExecuteFirstLoadDashboardAction) == "function") then
                return false, "The first-load Dashboard is not available in this menu build."
            end
            return M.ExecuteFirstLoadDashboardAction(suffix)
        end,
    })
end
