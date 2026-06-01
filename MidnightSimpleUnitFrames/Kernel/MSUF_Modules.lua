--- MSUF_Modules.lua
--- Lightweight module registry + lifecycle manager for Midnight Simple Unit Frames.
--- Over the course of the development this amounted to all sorts of stuff that has nothing to do with its intentional idea of managing modules and addons for MSUF.

local addonName, MSUF = ...
MSUF = MSUF or {}

local _G = _G

--- Registry (array for stable order + map for quick lookup)
MSUF.MSUF_Modules = MSUF.MSUF_Modules or {}
MSUF.MSUF_ModulesByKey = MSUF.MSUF_ModulesByKey or {}

--- Internal flags
MSUF.__MSUF_ModulesInitialized = MSUF.__MSUF_ModulesInitialized or false
MSUF.__MSUF_ModulesApplied = MSUF.__MSUF_ModulesApplied or false

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    return true, fn(...)
end

local function SortModulesIfNeeded()
    --- Only sort once, unless a late registration happens after init.
    if MSUF.__MSUF_ModulesSorted then return end
    MSUF.__MSUF_ModulesSorted = true

    table.sort(MSUF.MSUF_Modules, function(a, b)
        local ao = tonumber(a and a.order) or 100
        local bo = tonumber(b and b.order) or 100
        if ao ~= bo then return ao < bo end
        local ak = tostring(a and a.key or "")
        local bk = tostring(b and b.key or "")
        return ak < bk
    end)
end

--- Public: Register a module.
--- key: unique string
--- module: table with optional fields:
--- order (number), Init(), Enable(), Disable(), IsEnabled(),
--- RefreshSettings(self, source), Shutdown(self, reason)
function MSUF.MSUF_RegisterModule(key, module)
    if type(key) ~= "string" or key == "" then return end
    if type(module) ~= "table" then module = {} end

    module.key = key

    --- Replace existing module entry if re-registered (keeps array position stable if possible)
    local existing = MSUF.MSUF_ModulesByKey[key]
    if existing and existing ~= module then
        --- swap in place
        for i = 1, #MSUF.MSUF_Modules do
            if MSUF.MSUF_Modules[i] == existing then
                MSUF.MSUF_Modules[i] = module
                break
            end
        end
    elseif not existing then
        table.insert(MSUF.MSUF_Modules, module)
    end

    MSUF.MSUF_ModulesByKey[key] = module

    --- Late registration after sort/init: re-sort once.
    MSUF.__MSUF_ModulesSorted = false

    --- If core already initialized modules, init this one immediately.
    if MSUF.__MSUF_ModulesInitialized and not module.__msufInited then
        SortModulesIfNeeded()
        module.__msufInited = true
        SafeCall(module.Init, module)
    end

    --- If core already applied desired states, apply this module immediately too.
    if MSUF.__MSUF_ModulesApplied then
        SortModulesIfNeeded()
        MSUF.MSUF_ApplyModules() --- will handle idempotently
    end
end

--- Alias (short)
MSUF.RegisterModule = MSUF.MSUF_RegisterModule

local function GetDesiredEnabled(module)
    --- Modules may provide IsEnabled() which returns the desired state.
    if type(module.IsEnabled) == "function" then
        local ok, val = SafeCall(module.IsEnabled, module)
        if ok then return not not val end
    end

    --- Fallback: if the module sets module.enabled = true/false, respect it.
    if module.enabled ~= nil then
        return not not module.enabled
    end

    --- Default: enabled (but a module without Enable/Disable does nothing anyway).
    return true
end

--- Public: Init all registered modules (Init only, no Enable/Disable).
function MSUF.MSUF_InitModules()
    SortModulesIfNeeded()

    for i = 1, #MSUF.MSUF_Modules do
        local m = MSUF.MSUF_Modules[i]
        if m and not m.__msufInited then
            m.__msufInited = true
            SafeCall(m.Init, m)
        end
    end

    MSUF.__MSUF_ModulesInitialized = true
end

--- Public: Apply desired enabled/disabled states to all modules.
function MSUF.MSUF_ApplyModules()
    SortModulesIfNeeded()

    for i = 1, #MSUF.MSUF_Modules do
        local m = MSUF.MSUF_Modules[i]
        if m then
            local desired = GetDesiredEnabled(m)
            --- Phase 4: debug toggle override
            if m.__msufDebugOff then desired = false end
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

    MSUF.__MSUF_ModulesApplied = true
    --- Notify RoundedUF module (replaces former hooksecurefunc).
    if _G.MSUF_RoundedUF_Active == true then
        local fnR = _G.MSUF_RoundedUF_OnModulesApplied; if fnR then fnR() end
    end
end

--- Convenience: one-shot at startup.
function MSUF.MSUF_Modules_InitAndApply()
    MSUF.MSUF_InitModules()
    MSUF.MSUF_ApplyModules()
end

--- Phase 4: RefreshSettings - broadcast settings change to all enabled modules.
--- Called on: Options apply, profile switch, font/texture change.
--- Each module's RefreshSettings receives the module table as self.
function MSUF.MSUF_RefreshModuleSettings(source)
    SortModulesIfNeeded()
    for i = 1, #MSUF.MSUF_Modules do
        local m = MSUF.MSUF_Modules[i]
        if m and m.__msufEnabled and not m.__msufDebugOff then
            local fn = m.RefreshSettings
            if type(fn) == "function" then
                SafeCall(fn, m, source)
            end
        end
    end
end

--- Phase 4: Shutdown - cleanup all modules (profile switch, addon unload).
--- Calls Shutdown on every module that has one, regardless of enabled state.
function MSUF.MSUF_ShutdownModules(reason)
    SortModulesIfNeeded()
    for i = 1, #MSUF.MSUF_Modules do
        local m = MSUF.MSUF_Modules[i]
        if m then
            local fn = m.Shutdown
            if type(fn) == "function" then
                SafeCall(fn, m, reason)
            end
            m.__msufEnabled = false
        end
    end
    MSUF.__MSUF_ModulesApplied = false
end

--- Phase 4: GetModule - quick lookup by key.
function MSUF.MSUF_GetModule(key)
    return MSUF.MSUF_ModulesByKey[key]
end

--- Phase 4: Debug toggle - disable/enable a single module at runtime.
--- Usage: /msuf debug toggle <key>
--- Returns new state (true = enabled, false = disabled).
function MSUF.MSUF_ToggleModule(key)
    if type(key) ~= "string" then return nil end
    local m = MSUF.MSUF_ModulesByKey[key]
    if not m then return nil end

    if m.__msufDebugOff then
        --- Re-enable
        m.__msufDebugOff = nil
        if m.__msufEnabled and type(m.Enable) == "function" then
            SafeCall(m.Enable, m)
        end
        if m.__msufEnabled and type(m.RefreshSettings) == "function" then
            SafeCall(m.RefreshSettings, m, "debug_toggle")
        end
        return true
    else
        --- Disable
        m.__msufDebugOff = true
        if m.__msufEnabled and type(m.Disable) == "function" then
            SafeCall(m.Disable, m)
        end
        return false
    end
end

--- Phase 4: List all registered module keys (for debug/slash commands).
function MSUF.MSUF_ListModules()
    SortModulesIfNeeded()
    local out = {}
    for i = 1, #MSUF.MSUF_Modules do
        local m = MSUF.MSUF_Modules[i]
        if m and m.key then
            out[#out + 1] = m.key .. (m.__msufEnabled and " [ON]" or " [OFF]") .. (m.__msufDebugOff and " (debug-off)" or "")
        end
    end
    return out
end

--- Optional globals (useful for debugging / slash commands / external modules)
_G.MSUF_RegisterModule = MSUF.MSUF_RegisterModule
_G.MSUF_InitModules = MSUF.MSUF_InitModules
_G.MSUF_ApplyModules = MSUF.MSUF_ApplyModules
_G.MSUF_Modules_InitAndApply = MSUF.MSUF_Modules_InitAndApply
_G.MSUF_RefreshModuleSettings = MSUF.MSUF_RefreshModuleSettings
_G.MSUF_ShutdownModules = MSUF.MSUF_ShutdownModules
_G.MSUF_GetModule = MSUF.MSUF_GetModule
_G.MSUF_ToggleModule = MSUF.MSUF_ToggleModule
_G.MSUF_ListModules = MSUF.MSUF_ListModules
