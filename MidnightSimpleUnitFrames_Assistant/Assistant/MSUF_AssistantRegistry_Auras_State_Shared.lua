-- Assistant Auras shared saved-state helper registry.
-- Loaded before MSUF_AssistantRegistry_Auras_State.lua; the main auras registry reads this helper.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value) _G[name] = value; return value end

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildSharedStateHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local AuraModel = ctx.AuraModel
    local EnsureAuraFallbackDB = ctx.EnsureAuraFallbackDB
    local ApplyAura = ctx.ApplyAura
    local MSUFRef = ctx.MSUF or MSUF

    if type(AuraModel) ~= "function" or type(EnsureAuraFallbackDB) ~= "function" then return nil end

    local function SharedDB()
        local Model = AuraModel()
        local shared
        if Model and type(Model.EnsureDB) == "function" then
            local _, modelShared = Model.EnsureDB()
            shared = modelShared
        else
            ExportPublic("MSUF_DB", type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {})
            _G.MSUF_DB.auras3 = type(_G.MSUF_DB.auras3) == "table" and _G.MSUF_DB.auras3 or {}
            _G.MSUF_DB.auras3.shared = type(_G.MSUF_DB.auras3.shared) == "table" and _G.MSUF_DB.auras3.shared or {}
            shared = _G.MSUF_DB.auras3.shared
        end
        return shared
    end

    local function AuraSharedString(key, defaultValue, allowed)
        local shared = SharedDB()
        local value = type(shared) == "table" and shared[key] or nil
        if allowed and allowed[value] then return value end
        return defaultValue
    end

    local function SetAuraSharedString(key, value, defaultValue, allowed)
        local shared = SharedDB()
        if type(shared) == "table" then shared[key] = allowed and allowed[value] and value or defaultValue end
    end

    local function AuraSharedTable(key)
        local shared = SharedDB()
        if type(shared) ~= "table" then return {} end
        shared[key] = type(shared[key]) == "table" and shared[key] or {}
        return shared[key]
    end

    local function ApplyAuraReminders(reason)
        local api = MSUFRef and MSUFRef.MSUF_Auras3
        local reminder = api and api.Reminder
        if reminder and type(reminder.MarkDirty) == "function" then reminder.MarkDirty() end
        if type(ApplyAura) == "function" then ApplyAura("shared", reason or "MSUF_ASSISTANT_AURA_REMINDERS") end
    end

    return {
        AuraSharedString = AuraSharedString,
        SetAuraSharedString = SetAuraSharedString,
        AuraSharedTable = AuraSharedTable,
        ApplyAuraReminders = ApplyAuraReminders,
    }
end
