-- Assistant Dashboard copy-scope selector helpers.
-- Loaded before MSUF_AssistantRegistry_Dashboard.lua; the main dashboard registry passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.DashboardRegistry = A.DashboardRegistry or {}

local CopyCategoryFallbacks = A.DashboardRegistry.CopyCategoryFallbacks or {}
local UNIT_COPY_CATEGORY_FALLBACK = CopyCategoryFallbacks.unit or {}

function A.DashboardRegistry.BuildCopySelectors(ctx)
    if type(ctx) ~= "table" then return {} end

    local Menu = ctx.M or M
    local NormalizeKey = ctx.NormalizeKey
    local ResolveUnitKey = ctx.ResolveUnitKey
    local OpenMenuPage = ctx.OpenMenuPage
    local SelectorBool = ctx.SelectorBool
    local UNIT_PAGE_KEYS = ctx.UNIT_PAGE_KEYS or {}

    if type(Menu) ~= "table" then return {} end
    if type(NormalizeKey) ~= "function" or type(ResolveUnitKey) ~= "function" then return {} end
    if type(OpenMenuPage) ~= "function" or type(SelectorBool) ~= "function" then return {} end

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

    local function UnitCopyCategories()
        local cats = Menu.UnitPage and type(Menu.UnitPage.UF_COPY_CATEGORIES) == "table" and Menu.UnitPage.UF_COPY_CATEGORIES or nil
        if cats and #cats > 0 then return cats end
        return UNIT_COPY_CATEGORY_FALLBACK
    end

    local function EnsureUnitCopyScopes()
        Menu.unitCopyScopes = type(Menu.unitCopyScopes) == "table" and Menu.unitCopyScopes or {}
        local cats = UnitCopyCategories()
        for i = 1, #cats do
            local cat = cats[i]
            local key = cat and cat.key
            if type(key) == "string" and Menu.unitCopyScopes[key] == nil then
                local defaultValue = cat.default
                if defaultValue == nil then
                    for j = 1, #UNIT_COPY_CATEGORY_FALLBACK do
                        if UNIT_COPY_CATEGORY_FALLBACK[j].key == key then
                            defaultValue = UNIT_COPY_CATEGORY_FALLBACK[j].default
                            break
                        end
                    end
                end
                Menu.unitCopyScopes[key] = defaultValue ~= false
            end
        end
        return Menu.unitCopyScopes, cats
    end

    local function UnitCopyFallbackSpec(key)
        for i = 1, #UNIT_COPY_CATEGORY_FALLBACK do
            local spec = UNIT_COPY_CATEGORY_FALLBACK[i]
            if spec.key == key then return spec end
        end
        return nil
    end

    local function ResolveUnitCopyCategory(category)
        local needle = NormalizeKey(category)
        if needle == "" then return nil end
        local cats = UnitCopyCategories()
        for i = 1, #cats do
            local cat = cats[i]
            local key = cat and cat.key
            local fallback = UnitCopyFallbackSpec(key)
            local label = cat and cat.label or fallback and fallback.label
            if key and (needle == NormalizeKey(key) or needle == NormalizeKey(label)) then return key, label or key end
            local aliases = cat and cat.aliases or fallback and fallback.aliases
            for j = 1, #(aliases or {}) do
                if needle == NormalizeKey(aliases[j]) then return key, label or key end
            end
        end
        return nil
    end

    local function CurrentUnitPage()
        local page = Menu.activeKey
        if type(page) ~= "string" then return nil end
        for unit, key in pairs(UNIT_PAGE_KEYS) do
            if key == page then return unit end
        end
        return nil
    end

    local function SetUnitCopyScopeSelector(args)
        local scopes, cats = EnsureUnitCopyScopes()
        local unit = ResolveUnitKey(args and args.unit) or CurrentUnitPage() or "player"
        local command = NormalizeKey(args and args.command)
        local function refresh()
            OpenMenuPage(UNIT_PAGE_KEYS[unit] or "uf_player")
            if type(Menu.Refresh) == "function" then Menu.Refresh() end
        end
        if command == "all" or command == "selectall" then
            for i = 1, #cats do scopes[cats[i].key] = true end
            refresh()
            return true, "Selected all unit copy categories."
        end
        if command == "none" or command == "clear" or command == "selectnone" then
            for i = 1, #cats do scopes[cats[i].key] = false end
            refresh()
            return true, "Cleared all unit copy categories."
        end
        if command == "only" then
            local wanted = args and args.categories
            if type(wanted) ~= "table" or #wanted == 0 then return false, "Which unit copy categories do you want me to use?" end
            for i = 1, #cats do scopes[cats[i].key] = false end
            local labels = {}
            for i = 1, #wanted do
                local key, label = ResolveUnitCopyCategory(wanted[i])
                if key then
                    scopes[key] = true
                    labels[#labels + 1] = DisplayCategoryLabel(label, key)
                end
            end
            if #labels == 0 then return false, "Which unit copy categories from this list do you want me to use?" end
            refresh()
            return true, "Selected only unit copy categories: " .. table.concat(labels, ", ") .. "."
        end
        local key, label = ResolveUnitCopyCategory(args and args.category)
        if not key then return false, "Which unit copy category do you want me to use?" end
        scopes[key] = SelectorBool(args and args.value)
        refresh()
        return true, "Set unit copy category " .. DisplayCategoryLabel(label, key) .. " " .. (scopes[key] and "on" or "off") .. "."
    end

    local BuildGroupCopySelectorContext = A.DashboardRegistry and A.DashboardRegistry.BuildGroupCopySelectorContext
    local GroupCopySelectors = type(BuildGroupCopySelectorContext) == "function" and BuildGroupCopySelectorContext({
        M = Menu,
        NormalizeKey = NormalizeKey,
        OpenMenuPage = OpenMenuPage,
        SelectorBool = SelectorBool,
    }) or nil
    if type(GroupCopySelectors) ~= "table" then return {} end

    return {
        SetUnitCopyScopeSelector = SetUnitCopyScopeSelector,
        SetGroupCopyScopeSelector = GroupCopySelectors.SetGroupCopyScopeSelector,
    }
end
