-- MSUF_A2_Public.lua
-- Public Auras 2.0 namespace + lightweight init coordinator.
-- Phase 1+2: DB caching + Events driver live in their own modules.

local addonName, ns = ...
ns = ns or {}

ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

API.state = (type(API.state) == "table") and API.state or {}
API.perf  = (type(API.perf)  == "table") and API.perf  or {}

-- Idempotent init entrypoint. Render calls this once it has exported runtime hooks.
function API.Init()
    if API.__inited then return end
    API.__inited = true

    -- Prime DB cache once so UNIT_AURA hot-path never does migrations/default work.
    local DB = API.DB
    if DB and DB.Ensure then
        DB.Ensure()
    end

    -- Bind + register events (UNIT_AURA helper frames, target/focus/boss changes, edit mode preview refresh)
    local Ev = API.Events
    if Ev and Ev.Init then
        Ev.Init()
    end
end

