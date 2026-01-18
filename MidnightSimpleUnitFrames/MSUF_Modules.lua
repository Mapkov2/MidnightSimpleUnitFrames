-- MSUF_Modules.lua
-- Lightweight module registry + lifecycle manager for Midnight Simple Unit Frames.
-- Over the course of the development this amounted to all sorts of stuff that has nothing to do with its intentional idea of managing modules and addons for MSUF. 

local addonName, ns = ...
ns = ns or {}

local _G = _G

-- Registry (array for stable order + map for quick lookup)
ns.MSUF_Modules = ns.MSUF_Modules or {}
ns.MSUF_ModulesByKey = ns.MSUF_ModulesByKey or {}

-- Internal flags
ns.__MSUF_ModulesInitialized = ns.__MSUF_ModulesInitialized or false
ns.__MSUF_ModulesApplied = ns.__MSUF_ModulesApplied or false

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    -- Prefer the project's fast-call helper if present (login-time only, but keeps consistency)
    if _G and type(_G.MSUF_FastCall) == "function" then
        return _G.MSUF_FastCall(fn, ...)
    end
    return pcall(fn, ...)
end

local function SortModulesIfNeeded()
    -- Only sort once, unless a late registration happens after init.
    if ns.__MSUF_ModulesSorted then return end
    ns.__MSUF_ModulesSorted = true

    table.sort(ns.MSUF_Modules, function(a, b)
        local ao = tonumber(a and a.order) or 100
        local bo = tonumber(b and b.order) or 100
        if ao ~= bo then return ao < bo end
        local ak = tostring(a and a.key or "")
        local bk = tostring(b and b.key or "")
        return ak < bk
    end)
end

-- Public: Register a module.
-- key: unique string
-- module: table with optional fields:
--   order (number), Init(), Enable(), Disable(), IsEnabled()
function ns.MSUF_RegisterModule(key, module)
    if type(key) ~= "string" or key == "" then return end
    if type(module) ~= "table" then module = {} end

    module.key = key

    -- Replace existing module entry if re-registered (keeps array position stable if possible)
    local existing = ns.MSUF_ModulesByKey[key]
    if existing and existing ~= module then
        -- swap in place
        for i = 1, #ns.MSUF_Modules do
            if ns.MSUF_Modules[i] == existing then
                ns.MSUF_Modules[i] = module
                break
            end
        end
    elseif not existing then
        table.insert(ns.MSUF_Modules, module)
    end

    ns.MSUF_ModulesByKey[key] = module

    -- Late registration after sort/init: re-sort once.
    ns.__MSUF_ModulesSorted = false

    -- If core already initialized modules, init this one immediately.
    if ns.__MSUF_ModulesInitialized and not module.__msufInited then
        SortModulesIfNeeded()
        module.__msufInited = true
        SafeCall(module.Init, module)
    end

    -- If core already applied desired states, apply this module immediately too.
    if ns.__MSUF_ModulesApplied then
        SortModulesIfNeeded()
        ns.MSUF_ApplyModules() -- will handle idempotently
    end
end

-- Alias (short)
ns.RegisterModule = ns.MSUF_RegisterModule

local function GetDesiredEnabled(module)
    -- Modules may provide IsEnabled() which returns the desired state.
    if type(module.IsEnabled) == "function" then
        local ok, val = SafeCall(module.IsEnabled, module)
        if ok then return not not val end
    end

    -- Fallback: if the module sets module.enabled = true/false, respect it.
    if module.enabled ~= nil then
        return not not module.enabled
    end

    -- Default: enabled (but a module without Enable/Disable does nothing anyway).
    return true
end

-- Public: Init all registered modules (Init only, no Enable/Disable).
function ns.MSUF_InitModules()
    SortModulesIfNeeded()

    for i = 1, #ns.MSUF_Modules do
        local m = ns.MSUF_Modules[i]
        if m and not m.__msufInited then
            m.__msufInited = true
            SafeCall(m.Init, m)
        end
    end

    ns.__MSUF_ModulesInitialized = true
end

-- Public: Apply desired enabled/disabled states to all modules.
function ns.MSUF_ApplyModules()
    SortModulesIfNeeded()

    for i = 1, #ns.MSUF_Modules do
        local m = ns.MSUF_Modules[i]
        if m then
            local desired = GetDesiredEnabled(m)
            local current = not not m.__msufEnabled

            if desired and not current then
                m.__msufEnabled = true
                SafeCall(m.Enable, m)
            elseif (not desired) and current then
                m.__msufEnabled = false
                SafeCall(m.Disable, m)
            end
        end
    end

    ns.__MSUF_ModulesApplied = true
end

-- Convenience: one-shot at startup.
function ns.MSUF_Modules_InitAndApply()
    ns.MSUF_InitModules()
    ns.MSUF_ApplyModules()
end

-- Optional globals (useful for debugging / slash commands / external modules)
_G.MSUF_RegisterModule = ns.MSUF_RegisterModule
_G.MSUF_InitModules = ns.MSUF_InitModules
_G.MSUF_ApplyModules = ns.MSUF_ApplyModules
_G.MSUF_Modules_InitAndApply = ns.MSUF_Modules_InitAndApply
