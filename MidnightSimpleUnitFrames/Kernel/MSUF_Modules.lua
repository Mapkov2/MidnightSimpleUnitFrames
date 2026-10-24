--- MSUF_Modules.lua
--- Lightweight module registry + enable/disable pass for Midnight Simple Unit Frames.
---
--- Modules register Enable/Disable/IsEnabled hooks here. The registry owns
--- ordering, late registration and the idempotent enable/disable pass
--- (MSUF_ApplyModules), which State/MSUF_Profiles.lua runs after every profile
--- apply and menu actions run after ownership changes. There is no Init phase:
--- a module that needs login work wires it at file load (see
--- Features/Versioning). Individual modules still own their runtime behavior.

local addonName, MSUF = ...
MSUF = MSUF or {}

--- Registry (array for stable order + map for quick lookup)
MSUF.MSUF_Modules = MSUF.MSUF_Modules or {}
MSUF.MSUF_ModulesByKey = MSUF.MSUF_ModulesByKey or {}

--- Internal flag: set once MSUF_ApplyModules has run, so late registrations
--- apply themselves immediately.
MSUF.__MSUF_ModulesApplied = MSUF.__MSUF_ModulesApplied or false

local function SortModulesIfNeeded()
    --- Only sort once, unless a late registration happens after the first apply.
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
--- order (number), Enable(), Disable(), IsEnabled()
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

    --- Late registration after sort/apply: re-sort once.
    MSUF.__MSUF_ModulesSorted = false

    --- If core already applied desired states, apply this module immediately too.
    if MSUF.__MSUF_ModulesApplied then
        SortModulesIfNeeded()
        MSUF.MSUF_ApplyModules() --- will handle idempotently
    end
end

local function GetDesiredEnabled(module)
    --- Modules may provide IsEnabled() which returns the desired state.
    if type(module.IsEnabled) == "function" then
        return not not module:IsEnabled()
    end

    --- Fallback: if the module sets module.enabled = true/false, respect it.
    if module.enabled ~= nil then
        return not not module.enabled
    end

    --- Default: enabled (but a module without Enable/Disable does nothing anyway).
    return true
end

--- Query and transition share the Kernel boundary. Commit state only after
--- the transition returns; the caller clears the in-progress marker on errors.
local RunModuleStep = MSUF.RunHostAPIStep
local function ApplyModule(m)
    local desired = GetDesiredEnabled(m)
    if desired == not not m.__msufEnabled then return end
    local fn = desired and m.Enable or m.Disable
    if type(fn) == "function" then fn(m) end
    m.__msufEnabled = desired
end

--- Public: Apply desired enabled/disabled states to all modules.
--- Apply is idempotent: it only calls Enable/Disable when the desired state
--- differs from the current module state.
function MSUF.MSUF_ApplyModules()
    SortModulesIfNeeded()

    for i = 1, #MSUF.MSUF_Modules do
        local m = MSUF.MSUF_Modules[i]
        if m and m.__msufSwitchTo == nil then
            -- Guard the query too: it may re-enter Apply or raise.
            m.__msufSwitchTo = true
            RunModuleStep("module " .. m.key, ApplyModule, m)
            m.__msufSwitchTo = nil
        end
    end

    MSUF.__MSUF_ModulesApplied = true
    --- Notify the rounded unit-frame module (replaces former hooksecurefunc).
    --- UnitFrames/Effects/MSUF_UF_RoundedFrames.lua exports the callback while
    --- rounded frames are active; it re-applies masks after a profile apply.
    if MSUF.PublicGlobals.MSUF_RoundedUF_Active == true then
        local fnR = MSUF.PublicGlobals.MSUF_RoundedUF_OnModulesApplied
        if fnR then fnR() end
    end
end

local ExportPublic = MSUF.ExportPublic

ExportPublic("MSUF_RegisterModule", MSUF.MSUF_RegisterModule)
ExportPublic("MSUF_ApplyModules", MSUF.MSUF_ApplyModules)
