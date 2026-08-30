-- Assistant workflow navigation helpers.
-- Loaded before MSUF_AssistantRegistry_Workflows.lua; the main workflow module passes menu APIs in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.Workflow = A.Workflow or {}

function A.Workflow.InstallNavigationHelpers(ctx)
    ctx = type(ctx) == "table" and ctx or {}
    local Menu = ctx.M or M

    local function CanonicalPage(page)
        page = tostring(page or "")
        if page == "" then return nil end
        if type(A.ResolveCanonicalMenuRoute) == "function" then
            local canonical = A.ResolveCanonicalMenuRoute(page)
            if type(canonical) == "string" and canonical ~= "" then return canonical end
            return nil
        end
        if type(A.ResolveRegisteredMenuPage) == "function" then
            local canonical = A.ResolveRegisteredMenuPage(page)
            if type(canonical) == "string" and canonical ~= "" then return canonical end
            return nil
        end
        if type(A.IsKnownPageKey) == "function" and not A.IsKnownPageKey(page) then return nil end
        return page
    end

    function A.Workflow.PushNavigationPage(page)
        page = CanonicalPage(page)
        if not page then return end
        A.Workflow.navStack = type(A.Workflow.navStack) == "table" and A.Workflow.navStack or {}
        local stack = A.Workflow.navStack
        if stack[#stack] ~= page then stack[#stack + 1] = page end
        while #stack > 20 do table.remove(stack, 1) end
    end

    function A.Workflow.GoBackPage()
        local stack = type(A.Workflow.navStack) == "table" and A.Workflow.navStack or nil
        local page
        while stack and #stack > 0 and not page do page = CanonicalPage(table.remove(stack)) end
        if page then
            local opened = false
            if Menu and type(Menu.Open) == "function" then
                local accepted = Menu.Open(page) ~= false
                opened = accepted and Menu.activeKey == page
            end
            if not opened and Menu and type(Menu.SelectPage) == "function" then
                local accepted = Menu.SelectPage(page) ~= false
                opened = accepted and Menu.activeKey == page
            end
            if opened then return true, "Opened previous page." end
        end
        if Menu and type(Menu.GoBackPage) == "function" then return Menu.GoBackPage() end
        return false, "Open the MSUF menu first so I can go back."
    end

    function A.Workflow.GoForwardPage()
        if Menu and type(Menu.GoForwardPage) == "function" then return Menu.GoForwardPage() end
        return false, "Open the MSUF menu first so I can go forward."
    end

    return true
end
