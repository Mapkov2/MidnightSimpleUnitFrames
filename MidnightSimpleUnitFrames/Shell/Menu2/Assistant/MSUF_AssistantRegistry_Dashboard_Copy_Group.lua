-- Assistant Dashboard group copy-scope selector helpers.
-- Loaded before MSUF_AssistantRegistry_Dashboard_Copy.lua; consumed by the shared copy selector builder.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.DashboardRegistry = A.DashboardRegistry or {}

local CopyCategoryFallbacks = A.DashboardRegistry.CopyCategoryFallbacks or {}
local GROUP_COPY_CATEGORY_FALLBACK = CopyCategoryFallbacks.group or {}

function A.DashboardRegistry.BuildGroupCopySelectorContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local Menu = ctx.M or M
    local NormalizeKey = ctx.NormalizeKey
    local OpenMenuPage = ctx.OpenMenuPage
    local SelectorBool = ctx.SelectorBool

    if type(Menu) ~= "table" then return nil end
    if type(NormalizeKey) ~= "function" or type(OpenMenuPage) ~= "function" then return nil end
    if type(SelectorBool) ~= "function" then return nil end

    local function DisplayCategoryLabel(label, key)
        if A and type(A.DisplayEnumLabel) == "function" then return A.DisplayEnumLabel(label, key) end
        if label ~= nil and tostring(label) ~= "" and tostring(label) ~= tostring(key or "") then return tostring(label) end
        local parser = A and A.Parser
        if parser and type(parser.ValueDisplay) == "function" then
            return parser.ValueDisplay({ type = "enum" }, key)
        end
        key = tostring(key or "")
        if key == "" then return "category" end
        key = key:gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
        return key:gsub("^%l", string.upper)
    end

    local function GroupCopyCategories()
        local cats = Menu.GroupPage and type(Menu.GroupPage.GF_COPY_CATEGORIES) == "table" and Menu.GroupPage.GF_COPY_CATEGORIES or nil
        if cats and #cats > 0 then return cats end
        return GROUP_COPY_CATEGORY_FALLBACK
    end

    local function EnsureGroupCopyScopes()
        Menu.gfCopyScopes = type(Menu.gfCopyScopes) == "table" and Menu.gfCopyScopes or {}
        local cats = GroupCopyCategories()
        for i = 1, #cats do
            local key = cats[i] and cats[i].key
            if type(key) == "string" and Menu.gfCopyScopes[key] == nil then Menu.gfCopyScopes[key] = true end
        end
        return Menu.gfCopyScopes, cats
    end

    local function ResolveGroupCopyCategory(category)
        local needle = NormalizeKey(category)
        if needle == "" then return nil end
        local cats = GroupCopyCategories()
        for i = 1, #cats do
            local cat = cats[i]
            local key = cat and cat.key
            local label = cat and cat.label
            if key and (needle == NormalizeKey(key) or needle == NormalizeKey(label)) then return key, label or key end
            local aliases = cat and cat.aliases
            for j = 1, #(aliases or {}) do
                if needle == NormalizeKey(aliases[j]) then return key, label or key end
            end
        end
        return nil
    end

    local function SetGroupCopyScopeSelector(args)
        local scopes, cats = EnsureGroupCopyScopes()
        local command = NormalizeKey(args and args.command)
        local function refresh()
            OpenMenuPage("gf_layout")
            if type(Menu.Refresh) == "function" then Menu.Refresh() end
        end
        if command == "all" or command == "selectall" then
            for i = 1, #cats do
                scopes[cats[i].key] = true
            end
            refresh()
            return true, "Selected all group copy categories."
        end
        if command == "none" or command == "clear" or command == "selectnone" then
            for i = 1, #cats do scopes[cats[i].key] = false end
            refresh()
            return true, "Cleared all group copy categories."
        end
        if command == "only" then
            local wanted = args and args.categories
            if type(wanted) ~= "table" or #wanted == 0 then return false, "Which group copy categories do you want me to use?" end
            for i = 1, #cats do scopes[cats[i].key] = false end
            local labels = {}
            for i = 1, #wanted do
                local key, label = ResolveGroupCopyCategory(wanted[i])
                if key then
                    scopes[key] = true
                    labels[#labels + 1] = DisplayCategoryLabel(label, key)
                end
            end
            if #labels == 0 then return false, "Which group copy categories from this list do you want me to use?" end
            refresh()
            return true, "Selected only group copy categories: " .. table.concat(labels, ", ") .. "."
        end
        local key, label = ResolveGroupCopyCategory(args and args.category)
        if not key then return false, "Which group copy category do you want me to use?" end
        scopes[key] = SelectorBool(args and args.value)
        refresh()
        return true, "Set group copy category " .. DisplayCategoryLabel(label, key) .. " " .. (scopes[key] and "on" or "off") .. "."
    end

    return {
        SetGroupCopyScopeSelector = SetGroupCopyScopeSelector,
    }
end
