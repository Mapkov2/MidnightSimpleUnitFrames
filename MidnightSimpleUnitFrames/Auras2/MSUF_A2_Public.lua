-- MSUF_A2_Public.lua
-- Public Auras 2.0 namespace + lightweight init coordinator.
-- Load-order safe: Public/Events/Render can load in any order, so Init can be called multiple times.

local addonName, ns = ...
ns = ns or {}

ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

API.state = (type(API.state) == "table") and API.state or {}
API.perf  = (type(API.perf)  == "table") and API.perf  or {}

function API.Init()
    -- Prime DB cache once so UNIT_AURA hot-path never does migrations/default work.
    -- Load-order safety: DB.Ensure() can legitimately return nil early (EnsureDB not bound yet).
    -- Only mark __dbInited once we actually have valid pointers.
    if not API.__dbInited then
        local DB = API.DB
        if DB and DB.Ensure then
            local a2, shared = DB.Ensure()
            if type(a2) == "table" and type(shared) == "table" then
                API.__dbInited = true
            end
        end
    end

    -- Bind + register events (UNIT_AURA helper frames, target/focus/boss changes, edit mode preview refresh)
    if not API.__eventsInited then
        local Ev = API.Events
        if Ev and Ev.Init then
            API.__eventsInited = true
            Ev.Init()
        end
    end
end
