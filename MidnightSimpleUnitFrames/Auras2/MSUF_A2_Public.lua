-- MSUF_A2_Public.lua
-- Public Auras 2.0 namespace + lightweight init coordinator.
-- Load-order safe: Public/Events/Render can load in any order, so Init can be called multiple times.

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
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

function API.RequestApply()
    if API.__applyPending then return end
    API.__applyPending = true

    local function _do()
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

    if C_Timer and C_Timer.After then
        C_Timer.After(0, _do)
    else
        _do()
    end
end

-- Legacy/global entrypoint (optional)
if type(_G) == "table" and type(_G.MSUF_Auras2_RequestApply) ~= "function" then
    _G.MSUF_Auras2_RequestApply = function() return API.RequestApply() end
end


-- ------------------------------------------------------------
-- A2 Perfy bridge (opt-in, zero cost when disabled)
-- Usage:
--   /run MSUF_A2_PerfyEnable()        -- coarse spans (Flush/RenderUnit/etc.)
--   /run MSUF_A2_PerfyEnable(true)    -- deep spans/events (per-icon, store deltas)
--   /run MSUF_A2_PerfyDisable()
-- ------------------------------------------------------------
do
    if rawget(_G, "MSUF_A2_PerfyEnable") == nil then
        local function _clear()
            _G.MSUF_A2_PerfyEnter = nil
            _G.MSUF_A2_PerfyLeave = nil
            _G.MSUF_A2_PerfyEvent = nil
        end

        local function _bind()
            if rawget(_G, "MSUF_A2_PERFY_ENABLED") ~= true then
                _clear()
                return
            end

            local trace = rawget(_G, "Perfy_Trace")
            local gett  = rawget(_G, "Perfy_GetTime") or rawget(_G, "GetTimePreciseSec")
            if type(trace) ~= "function" or type(gett) ~= "function" then
                _clear()
                return
            end

            -- NOTE: Analyzer expects the standard event names "Enter"/"Leave" to reconstruct stacks.
            -- We deliberately generate synthetic spans only for Auras2 so traces remain small and focused.
            _G.MSUF_A2_PerfyEnter = function(name, extra)
                trace(gett(), "Enter", name, extra)
            end
            _G.MSUF_A2_PerfyLeave = function(name, extra)
                trace(gett(), "Leave", name, extra)
            end
            -- Deep marker events (do not participate in stack accounting; useful for correlation only)
            _G.MSUF_A2_PerfyEvent = function(name, extra)
                if rawget(_G, "MSUF_A2_PERFY_DEEP") == true then
                    trace(gett(), "OnEvent", name, extra)
                end
            end
        end

        function _G.MSUF_A2_PerfyEnable(deep)
            _G.MSUF_A2_PERFY_ENABLED = true
            _G.MSUF_A2_PERFY_DEEP = (deep == true)
            _bind()
        end

        function _G.MSUF_A2_PerfyDisable()
            _G.MSUF_A2_PERFY_ENABLED = false
            _G.MSUF_A2_PERFY_DEEP = false
            _bind()
        end

        function _G.MSUF_A2_PerfyBind()
            _bind()
        end

        -- Respect any pre-set global flags (e.g. user toggled via /run before reload)
        _G.MSUF_A2_PERFY_ENABLED = (rawget(_G, "MSUF_A2_PERFY_ENABLED") == true)
        _G.MSUF_A2_PERFY_DEEP = (rawget(_G, "MSUF_A2_PERFY_DEEP") == true)
        _bind()
    end
end

