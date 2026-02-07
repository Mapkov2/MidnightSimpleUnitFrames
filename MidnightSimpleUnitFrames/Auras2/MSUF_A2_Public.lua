-- Public Auras 2.0 namespace + lightweight init coordinator.
-- Phase 1+2: DB caching + Events driver live in their own modules.
local addonName, ns = ...
ns = ns or {}
ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2
API.state = (type(API.state) == "table") and API.state or {}
API.perf  = (type(API.perf)  == "table") and API.perf  or {}
-- Idempotent init entrypoint.
-- IMPORTANT: Load order in the .toc is Render -> Events.
-- Render may call Init() before Events exists, so Init must be able to run again later.
function API.Init()
    -- Prime DB cache once so UNIT_AURA hot-path never does migrations/default work.
    if not API.__dbInited then
        API.__dbInited = true
        local DB = API.DB
        if DB and DB.Ensure then
            DB.Ensure()
        end
    end

    -- Bind + register events once Events is available.
    if not API.__eventsInited then
        local Ev = API.Events
        if Ev and Ev.Init then
            Ev.Init()
            API.__eventsInited = true
        end
    end
end
