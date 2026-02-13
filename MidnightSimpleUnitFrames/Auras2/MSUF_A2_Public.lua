-- MSUF_A2_Public.lua
-- Public Auras 2.0 namespace + lightweight init coordinator.
-- Load-order safe: Public/Events/Render can load in any order, so Init can be called multiple times.

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
-- =========================================================================
-- PERF LOCALS (Auras2 runtime)
--  - Reduce global table lookups in high-frequency aura pipelines.
--  - Secret-safe: localizing function references only (no value comparisons).
-- =========================================================================
local type, tostring, tonumber, select = type, tostring, tonumber, select
local pairs, ipairs, next = pairs, ipairs, next
local math_min, math_max, math_floor = math.min, math.max, math.floor
local string_format, string_match, string_sub = string.format, string.match, string.sub
local CreateFrame, GetTime = CreateFrame, GetTime
local UnitExists = UnitExists
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local C_UnitAuras = C_UnitAuras
local C_Secrets = C_Secrets
local C_CurveUtil = C_CurveUtil

ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

API.state = (type(API.state) == "table") and API.state or {}
API.perf  = (type(API.perf)  == "table") and API.perf  or {}

function API.Init()
    -- Prime DB cache once so UNIT_AURA hot-path never does migrations/default work.
    -- Load-order safety: DB.Ensure() can legitimately return nil early (EnsureDB not bound yet).
    -- Only mark __dbInited once we actually have valid pointers.
    local a2_ok, a2_ptr
    if not API.__dbInited then
        local DB = API.DB
        if DB and DB.Ensure then
            local a2, shared = DB.Ensure()
            if type(a2) == "table" and type(shared) == "table" then
                API.__dbInited = true
                a2_ok, a2_ptr = true, a2
            end
        end
    else
        local DB = API.DB
        local c = DB and DB.cache
        if c and c.ready and c.a2 then
            a2_ok, a2_ptr = true, c.a2
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

    -- Load-order edge case fix:
    -- Events.Init can run before Render has bound EnsureDB, causing ApplyEventRegistration() to
    -- disable all UNIT_AURA bindings. Once DB pointers are valid, re-apply event registration once
    -- and prime the Player unit so player auras don't "wake up" only after Edit Mode toggles.
    if a2_ok and API.__eventsInited and not API.__eventRegPrimed then
        local Ev = API.Events
        local apply = Ev and Ev.ApplyEventRegistration
        if type(apply) == "function" then
            API.__eventRegPrimed = true
            apply()

            -- Prime initial player render only when player unit is enabled.
            if a2_ptr and a2_ptr.enabled == true and a2_ptr.showPlayer == true then
                local req = API.RequestUnit or API.MarkDirty
                if type(req) == "function" then
                    req("player", 0)
                end
            end
        end
    end
end

-- ------------------------------------------------------------
-- Public API: coalesced apply (used by Options toggles)
-- Ensures Auras2 is initialized and a full refresh is requested next frame.
-- ------------------------------------------------------------
API.__applyPending = (API.__applyPending == true)

-- File-scope apply function (avoid closure allocation per RequestApply call)
local function _DoApply()
    API.__applyPending = false

    if API.Init then
        API.Init()
    end

    local r = API.RefreshAll
    if type(r) == "function" then
        r()
    elseif type(_G) == "table" and type(_G.MSUF_Auras2_RefreshAll) == "function" then
        _G.MSUF_Auras2_RefreshAll()
    end
end

function API.RequestApply()
    if API.__applyPending then return end
    API.__applyPending = true

    if C_Timer and C_Timer.After then
        C_Timer.After(0, _DoApply)
    else
        _DoApply()
    end
end

-- Legacy/global entrypoint (optional)
if type(_G) == "table" then
    _G.MSUF_Auras2_RequestApply = function() return API.RequestApply() end
end
