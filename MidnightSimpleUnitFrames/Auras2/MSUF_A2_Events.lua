-- MSUF_A2_Events.lua
-- Auras 2.0 event driver (UNIT_AURA + target/focus/boss changes + Edit Mode preview refresh).
-- Phase 2: moved out of the render module.

local addonName, ns = ...


-- MSUF: Max-perf Auras2: replace protected calls (pcall) with direct calls.
-- NOTE: this removes error-catching; any error will propagate.
local function MSUF_A2_FastCall(fn, ...)
    return true, fn(...)
end
ns = (rawget(_G, "MSUF_NS") or ns) or {}
ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

API.Events = (type(API.Events) == "table") and API.Events or {}
local Events = API.Events

local _G = _G
local CreateFrame = CreateFrame
local C_Timer = C_Timer

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------
local function SafePCall(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, _ = MSUF_A2_FastCall(fn, ...)
    return ok
end

-- Strict coalescing for UNIT_AURA bursts:
--  * Never render "per event".
--  * Batch same-frame (and small multi-event bursts) into a single render.
--
-- Route through API.RequestUnit(delay) when available so the render module can
-- coalesce aggressively while still allowing non-aura events (target/focus swap)
-- to request immediate refresh.
local function MarkDirty(unit, delay)
    if not unit then return end

    local req = API.RequestUnit
    if type(req) == "function" then
        -- Default delay for UNIT_AURA should be small but non-zero.
        -- (0 would still be next-frame, but 0.01 collapses most burst patterns.)
        if delay == nil then delay = 0.01 end
        req(unit, delay)
        return
    end

    local f = API.MarkDirty
    if type(f) == "function" then
        f(unit, delay)
    end
end

local function IsEditModeActive()
    -- Prefer exported Auras2 helper, but provide a robust local fallback so we never need polling
    -- just to detect MSUF Edit Mode transitions.
    local f = API.IsEditModeActive
    if type(f) == "function" then
        return f() == true
    end

    -- MSUF-only Edit Mode (Blizzard Edit Mode intentionally ignored here).
    local st = rawget(_G, "MSUF_EditState")
    if type(st) == "table" and st.active == true then
        return true
    end

    -- Legacy global boolean used by older patches
    if rawget(_G, "MSUF_UnitEditModeActive") == true then
        return true
    end

    -- Exported helper from MSUF_EditMode.lua
    local g = rawget(_G, "MSUF_IsInEditMode")
    if type(g) == "function" then
        local ok, v = MSUF_A2_FastCall(g)
        if ok and v == true then
            return true
        end
    end

    -- Compatibility hook name from older experiments (last resort)
    local h = rawget(_G, "MSUF_IsMSUFEditModeActive")
    if type(h) == "function" then
        local ok, v = MSUF_A2_FastCall(h)
        if ok and v == true then
            return true
        end
    end

    return false
end

local function EnsureDB()
    local DB = API.DB
    if DB and DB.Ensure then
        return DB.Ensure()
    end
    local f = API.EnsureDB
    if type(f) == "function" then
        return f()
    end
    return nil
end

-- Hot path: use cached unit-enabled flags (no DB work). Falls back to EnsureDB once if cache is cold.
-- forAuraEvent=true => ONLY consider standard aura rendering (avoid UNIT_AURA spam when only private auras are enabled).
local function ShouldProcessUnitEvent(unit, forAuraEvent)
    if not unit then return false end

    local DB = API.DB
    if DB and DB.UnitEnabledCached and DB.cache and DB.cache.ready then
        -- MSUF Edit Mode preview should always stay responsive (no polling).
        if DB.cache.showInEditMode and IsEditModeActive() then
            return true
        end

        -- Non-UNIT_AURA events: allow when the unit's Auras2 is enabled.
        if not forAuraEvent then
            return DB.UnitEnabledCached(unit) == true
        end

        -- UNIT_AURA events are extremely spammy. Only process them when we actually render standard auras.
        if DB.UnitEnabledCached(unit) ~= true then
            return false
        end

        local shared = DB.cache.shared
        if not shared then return false end

        if shared.showBuffs == true then
            local n = shared.maxBuffs
            if type(n) ~= "number" then n = 0 end
            if n > 0 then return true end
        end
        if shared.showDebuffs == true then
            local n = shared.maxDebuffs
            if type(n) ~= "number" then n = 0 end
            if n > 0 then return true end
        end

        return false
    end

    -- Cold start: ensure DB once, then retry cache path.
    local a2, shared = EnsureDB()
    DB = API.DB
    if DB and DB.RebuildCache then
        DB.RebuildCache(a2, shared)
    end

    if DB and DB.UnitEnabledCached and DB.cache and DB.cache.ready then
        if DB.cache.showInEditMode and IsEditModeActive() then
            return true
        end

        if not forAuraEvent then
            return DB.UnitEnabledCached(unit) == true
        end

        if DB.UnitEnabledCached(unit) ~= true then
            return false
        end

        shared = DB.cache.shared
        if not shared then return false end

        if shared.showBuffs == true then
            local n = shared.maxBuffs
            if type(n) ~= "number" then n = 0 end
            if n > 0 then return true end
        end
        if shared.showDebuffs == true then
            local n = shared.maxDebuffs
            if type(n) ~= "number" then n = 0 end
            if n > 0 then return true end
        end

        return false
    end

    -- Fallback (should be rare): conservative deny.
    return false
end

-- Export so Render/Options can call the exact same gating without duplicating logic.
API.ShouldProcessUnitEvent = API.ShouldProcessUnitEvent or ShouldProcessUnitEvent

local function FindUnitFrame(unit)
    local f = API.FindUnitFrame
    if type(f) == "function" then
        return f(unit)
    end

    local uf = _G and _G.MSUF_UnitFrames
    if type(uf) == "table" and unit and uf[unit] then
        return uf[unit]
    end
    local g = _G and unit and _G["MSUF_" .. unit]
    return g
end

-- ------------------------------------------------------------
-- UNIT_AURA binding (helper frames)
-- ------------------------------------------------------------
local function EnsureUnitAuraBinding(eventFrame)
    if not eventFrame then
        return
    end

    local DB = API and API.DB
    local c = DB and DB.cache
    local ue = c and c.unitEnabled

    -- Bootstrap: if cache isn't ready yet (load-order / cold start),
    -- keep PLAYER_LOGIN/PLAYER_ENTERING_WORLD registered so we can finalize
    -- proper UNIT_AURA bindings once DB pointers are ready.
    if not (c and c.ready == true) then
        ApplyOwnedEvents(eventFrame, {
            PLAYER_LOGIN = "Core",
            PLAYER_ENTERING_WORLD = "Core",
        })
        return
    end

    if not ue then
        return
    end

    eventFrame._msufA2_unitAuraFrames = eventFrame._msufA2_unitAuraFrames or {}
    local frames = eventFrame._msufA2_unitAuraFrames

    -- Reuse a temp list to avoid allocations.
    local units = eventFrame._msufA2_unitAuraUnitsTemp
    if not units then
        units = {}
        eventFrame._msufA2_unitAuraUnitsTemp = units
    else
        for i = #units, 1, -1 do
            units[i] = nil
        end
    end

    local n = 0
    if ue.player == true then n = n + 1; units[n] = "player" end
    if ue.target == true then n = n + 1; units[n] = "target" end
    if ue.focus == true then n = n + 1; units[n] = "focus" end
    if ue.boss1 == true then n = n + 1; units[n] = "boss1" end
    if ue.boss2 == true then n = n + 1; units[n] = "boss2" end
    if ue.boss3 == true then n = n + 1; units[n] = "boss3" end
    if ue.boss4 == true then n = n + 1; units[n] = "boss4" end
    if ue.boss5 == true then n = n + 1; units[n] = "boss5" end

    local idx = 1
    local i = 1
    while i <= n do
        local unit1 = units[i]
        local unit2 = units[i + 1]

        local f = frames[idx]
        if not f then
            f = CreateFrame("Frame")
            frames[idx] = f
        end

        if f.IsEventRegistered and f:IsEventRegistered("UNIT_AURA") then
            f:UnregisterEvent("UNIT_AURA")
        elseif f.UnregisterEvent then
            f:UnregisterEvent("UNIT_AURA")
        end

        local regUnit = f.RegisterUnitEvent
        if type(regUnit) == "function" then
            if unit2 then
                regUnit(f, "UNIT_AURA", unit1, unit2)
            else
                regUnit(f, "UNIT_AURA", unit1)
            end
        elseif f.RegisterEvent then
            -- Fallback: register generic UNIT_AURA and filter in handler.
            f:RegisterEvent("UNIT_AURA")
        end

        f._msufA2_unitAuraUnits = f._msufA2_unitAuraUnits or {}
        f._msufA2_unitAuraUnits[1], f._msufA2_unitAuraUnits[2] = unit1, unit2

        idx = idx + 1
        i = i + 2
    end

    -- Unused frames: fully unhook.
    for j = idx, #frames do
        local f = frames[j]
        if f then
            if f.IsEventRegistered and f:IsEventRegistered("UNIT_AURA") then
                f:UnregisterEvent("UNIT_AURA")
            elseif f.UnregisterEvent then
                f:UnregisterEvent("UNIT_AURA")
            end
            if f.SetScript then
                f:SetScript("OnEvent", nil)
            end
            if f._msufA2_unitAuraUnits then
                f._msufA2_unitAuraUnits[1], f._msufA2_unitAuraUnits[2] = nil, nil
            end
        end
    end

    eventFrame._msufA2_unitAuraBound = (n > 0)
end

-- ------------------------------------------------------------
-- Owned event registration helper
-- ------------------------------------------------------------
local function ApplyOwnedEvents(frame, desiredOwners)
    if not frame or type(desiredOwners) ~= "table" then return end

    frame._msufA2_eventOwner = frame._msufA2_eventOwner or {}
    local owned = frame._msufA2_eventOwner

    -- Register desired
    for event, owner in pairs(desiredOwners) do
        if owned[event] ~= owner then
            owned[event] = owner
            if frame.RegisterEvent then
                frame:RegisterEvent(event)
            end
        end
    end

    -- Unregister events no longer desired (only those we own).
    -- Important: avoid mutating the owner-table while iterating with pairs().
    local tmp = frame._msufA2_eventOwnerRemoveTemp
    if not tmp then
        tmp = {}
        frame._msufA2_eventOwnerRemoveTemp = tmp
    else
        for i = #tmp, 1, -1 do tmp[i] = nil end
    end

    local n = 0
    for event, owner in pairs(owned) do
        if owner and desiredOwners[event] == nil then
            n = n + 1
            tmp[n] = event
        end
    end

    if frame.UnregisterEvent then
        for i = 1, n do
            local event = tmp[i]
            owned[event] = nil
            frame:UnregisterEvent(event)
            tmp[i] = nil
        end
    else
        for i = 1, n do
            local event = tmp[i]
            owned[event] = nil
            tmp[i] = nil
        end
    end
end

-- ------------------------------------------------------------
-- Boss attach retry (ENGAGE_UNIT race)
-- ------------------------------------------------------------
local BossAttachRetryTicker = nil

local function StopBossRetry()
    if BossAttachRetryTicker then
        BossAttachRetryTicker:Cancel()
        BossAttachRetryTicker = nil
    end
end

local function StartBossAttachRetry()
    StopBossRetry()

    if not C_Timer or not C_Timer.NewTicker then return end

    local tries = 0
    BossAttachRetryTicker = C_Timer.NewTicker(0.15, function()
        tries = tries + 1

        local anyPending = false
        for i = 1, 5 do
            local u = "boss" .. i
            if ShouldProcessUnitEvent(u) then
                local f = FindUnitFrame(u)
                if f and f.IsShown and f:IsShown() and UnitExists and UnitExists(u) then
                    MarkDirty(u)
                else
                    anyPending = true
                end
            end
        end

        if (not anyPending) or tries >= 10 then
            StopBossRetry()
        end
    end)
end

-- ------------------------------------------------------------
-- Edit Mode preview refresh + fallback poll
-- ------------------------------------------------------------
local function MarkAllDirty()
    MarkDirty("player")
    MarkDirty("target")
    MarkDirty("focus")
    for i = 1, 5 do MarkDirty("boss" .. i) end
end

local function OnAnyEditModeChanged(active)
    local _, shared = EnsureDB()

    local wantPreview = (shared and shared.showInEditMode == true) or false

    -- Clear previews when leaving Edit Mode OR when previews are disabled.
    -- This prevents preview icons from lingering and blocking real aura updates.
    if (active == false) or (wantPreview ~= true) then
        if API.ClearAllPreviews then
            API.ClearAllPreviews()
        end
    end

    MarkAllDirty()

    -- Keep preview tickers in sync with both DB toggles and Edit Mode lifecycle.
    if API.UpdatePreviewStackTicker then
        API.UpdatePreviewStackTicker()
    end
    if API.UpdatePreviewCooldownTicker then
        API.UpdatePreviewCooldownTicker()
    end

    if Events.UpdateEditModePoll then
        Events.UpdateEditModePoll()
    end
end


Events.OnAnyEditModeChanged = OnAnyEditModeChanged
API.OnAnyEditModeChanged = API.OnAnyEditModeChanged or OnAnyEditModeChanged

-- Preferred: event-driven notifications from MSUF Edit Mode.
-- Goal: 0 Poll CPU in idle (preview still snaps instantly on enter/exit).
Events._anyEditModeHooked = Events._anyEditModeHooked or false
Events._anyEditModeHookAttempted = Events._anyEditModeHookAttempted or false
Events._pollFallbackAllowed = Events._pollFallbackAllowed or false

local function _A2_DebugPollForced()
    if rawget(_G, "MSUF_A2_DEBUG_POLL") == true then
        return true
    end
    local db = rawget(_G, "MSUF_DB")
    if type(db) == "table" and type(db.general) == "table" and db.general.debugAuras2Poll == true then
        return true
    end
    return false
end

local function TryHookAnyEditModeListener()
    if Events._anyEditModeHooked then return true end

    local reg = rawget(_G, "MSUF_RegisterAnyEditModeListener")
    if type(reg) ~= "function" then
        return false
    end

    reg(OnAnyEditModeChanged)
    Events._anyEditModeHooked = true

    -- Ensure we are cold-idle immediately.
    if Events.UpdateEditModePoll then
        Events.UpdateEditModePoll()
    end

    return true
end

local function ScheduleAnyEditModeHookRetry()
    if Events._anyEditModeHooked or Events._anyEditModeHookAttempted then return end
    Events._anyEditModeHookAttempted = true

    if not (C_Timer and C_Timer.After) then
        -- No timers available: allow poll fallback so preview can still work.
        Events._pollFallbackAllowed = true
        if Events.UpdateEditModePoll then
            Events.UpdateEditModePoll()
        end
        return
    end

    local tries = 0
    local function step()
        if Events._anyEditModeHooked then return end

        if TryHookAnyEditModeListener() then
            -- Sync once after hooking (covers rare "Auras2 loads before EditMode" order,
            -- or /reload while Edit Mode is already active).
            OnAnyEditModeChanged(IsEditModeActive())
            return
        end

        tries = tries + 1
        if tries == 1 then
            C_Timer.After(0.5, step)
        elseif tries == 2 then
            C_Timer.After(2.0, step)
        elseif tries == 3 then
            C_Timer.After(5.0, step)
        else
            -- Give up: enable poll fallback as last resort.
            Events._pollFallbackAllowed = true
            if Events.UpdateEditModePoll then
                Events.UpdateEditModePoll()
            end
        end
    end

    C_Timer.After(0, step)
end

-- ------------------------------------------------------------
-- Poll fallback (last resort)
-- ------------------------------------------------------------
local _pollLast = nil
local _pollAcc = 0
local _polling = false

local function PollOnUpdate(_, elapsed)
    _pollAcc = _pollAcc + (elapsed or 0)
    if _pollAcc < 0.25 then return end
    _pollAcc = 0

    local cur = IsEditModeActive()
    if _pollLast == nil then
        _pollLast = cur
        return
    end

    if cur ~= _pollLast then
        _pollLast = cur
        OnAnyEditModeChanged(cur)
    end
end

function Events.UpdateEditModePoll()
    local ef = Events._eventFrame
    if not ef then return end

    local debugPoll = _A2_DebugPollForced()

    -- Cold idle: if we are hooked into MSUF Edit Mode notifications, never poll.
    if Events._anyEditModeHooked and (not debugPoll) then
        if _polling then
            _polling = false
            ef:SetScript("OnUpdate", nil)
        end
        return
    end

    -- If we're not hooked yet, keep cold-idle while we retry the hook.
    if (not Events._anyEditModeHooked) and (not debugPoll) and (not Events._pollFallbackAllowed) then
        if _polling then
            _polling = false
            ef:SetScript("OnUpdate", nil)
        end
        ScheduleAnyEditModeHookRetry()
        return
    end

    -- Poll fallback enabled (or debug forces polling).
    local a2, shared = EnsureDB()

    if not debugPoll then
        local DB = API and API.DB
        if (not a2) or (a2.enabled ~= true) or (not DB) or (not DB.AnyUnitEnabledCached) or (DB.AnyUnitEnabledCached() ~= true) then
            if _polling then
                _polling = false
                ef:SetScript("OnUpdate", nil)
            end
            return
        end
    end

    local wantPreview = (shared and shared.showInEditMode == true) or false
    local cur = IsEditModeActive()
    local wantPoll = debugPoll or (wantPreview == true) or (cur == true)

    if wantPoll and not _polling then
        _polling = true
        _pollAcc = 0
        _pollLast = cur
        ef:SetScript("OnUpdate", PollOnUpdate)
    elseif (not wantPoll) and _polling then
        _polling = false
        ef:SetScript("OnUpdate", nil)
    end
end

API.UpdateEditModePoll = API.UpdateEditModePoll or function()
    if Events.UpdateEditModePoll then
        return Events.UpdateEditModePoll()
    end
end
-- ------------------------------------------------------------
-- Public API: ApplyEventRegistration + Init
-- ------------------------------------------------------------
function Events.ApplyEventRegistration()
    local ef = Events._eventFrame
    if not ef then return end

    EnsureDB()

    local DB = API and API.DB
    local c = DB and DB.cache
    local ue = c and c.unitEnabled

-- Cold-start bootstrap:
-- If DB/cache is not ready yet (load-order), keep only LOGIN/ENTERING_WORLD registered.
-- This guarantees we get a chance to re-run ApplyEventRegistration once EnsureDB becomes available,
-- instead of unregistering everything and waiting for manual RefreshAll/EditMode.
if not (c and c.ready == true) then
    ApplyOwnedEvents(ef, {
        PLAYER_LOGIN = "Core",
        PLAYER_ENTERING_WORLD = "Core",
    })

    -- Ensure UNIT_AURA helper frames are not running while we don't know which units are enabled.
    local list = ef._msufA2_unitAuraFrames
    if type(list) == "table" then
        for i = 1, #list do
            local f = list[i]
            if f then
                if f.IsEventRegistered and f:IsEventRegistered("UNIT_AURA") then
                    f:UnregisterEvent("UNIT_AURA")
                elseif f.UnregisterEvent then
                    f:UnregisterEvent("UNIT_AURA")
                end
                if f.SetScript then
                    f:SetScript("OnEvent", nil)
                end
            end
        end
    end
    ef._msufA2_unitAuraBound = false
    StopBossRetry()

    -- Avoid polling unless explicitly enabled elsewhere.
    if _polling then
        _polling = false
        ef:SetScript("OnUpdate", nil)
    end

    return
end

    local want = false
    if c and c.ready == true and c.enabled == true and ue then
        if DB.AnyUnitEnabledCached then
            want = (DB.AnyUnitEnabledCached() == true)
        else
            want = (ue.player == true) or (ue.target == true) or (ue.focus == true)
                or (ue.boss1 == true) or (ue.boss2 == true) or (ue.boss3 == true)
                or (ue.boss4 == true) or (ue.boss5 == true)
        end
    end

    if not want then
        -- No enabled units: unregister everything (OFF = ~0 overhead)
        ApplyOwnedEvents(ef, {})

        local list = ef._msufA2_unitAuraFrames
        if type(list) == "table" then
            for i = 1, #list do
                local f = list[i]
                if f then
                    if f.IsEventRegistered and f:IsEventRegistered("UNIT_AURA") then
                        f:UnregisterEvent("UNIT_AURA")
                    elseif f.UnregisterEvent then
                        f:UnregisterEvent("UNIT_AURA")
                    end
                    if f.SetScript then
                        f:SetScript("OnEvent", nil)
                    end
                end
            end
        end

        ef._msufA2_unitAuraBound = false

        StopBossRetry()

        if _polling then
            _polling = false
            ef:SetScript("OnUpdate", nil)
        end

        -- Ensure preview tickers + cooldown-text manager are stopped
        if API and API.UpdatePreviewStackTicker then API.UpdatePreviewStackTicker() end
        if API and API.UpdatePreviewCooldownTicker then API.UpdatePreviewCooldownTicker() end
        local CT = API and API.CooldownText
        if CT and CT.UnregisterAll then
            CT.UnregisterAll()
        end

        -- Kill any pending flush + hide visuals (Render module)
        if API and API.HardDisableAll then
            API.HardDisableAll()
        end

        return
    end

    -- Bind UNIT_AURA for only the enabled units
    EnsureUnitAuraBinding(ef)

    -- Build desired core events based on enabled units
    local needTarget = (ue and ue.target == true) or false
    local needFocus  = (ue and ue.focus  == true) or false
    local needBoss   = (ue and ((ue.boss1 == true) or (ue.boss2 == true) or (ue.boss3 == true) or (ue.boss4 == true) or (ue.boss5 == true))) or false

    local desired = {
        PLAYER_LOGIN = "Core",
        PLAYER_ENTERING_WORLD = "Core",
    }

    if needTarget then
        desired.PLAYER_TARGET_CHANGED = "Core"
        desired.UNIT_TARGETABLE_CHANGED = "Core"
    end
    if needFocus then
        desired.PLAYER_FOCUS_CHANGED = "Core"
        desired.UNIT_TARGETABLE_CHANGED = "Core"
    end
    if needBoss then
        desired.INSTANCE_ENCOUNTER_ENGAGE_UNIT = "Core"
    end

    ApplyOwnedEvents(ef, desired)

    -- Apply UNIT_AURA handler only on frames that are actually registered
    local list = ef._msufA2_unitAuraFrames
    if type(list) == "table" then
        local handler = ef._msufA2_unitAuraOnEvent
        if not handler then
            handler = function(self, event, unit, updateInfo)
                if event ~= "UNIT_AURA" then return end

                local units = self._msufA2_unitAuraUnits
                if units then
                    local u1, u2 = units[1], units[2]
                    if unit ~= u1 and unit ~= u2 then
                        return
                    end
                end

                -- No-op skip: some clients can fire UNIT_AURA with an empty updateInfo.
                -- Avoid waking Render/Store when nothing actually changed.
                if type(updateInfo) == "table" then
                    local full = updateInfo.isFullUpdate
                    if full ~= true then
                        local a = updateInfo.addedAuras
                        local r = updateInfo.removedAuraInstanceIDs
                        local u = updateInfo.updatedAuraInstanceIDs
                        local na = (type(a) == "table" and #a) or 0
                        local nr = (type(r) == "table" and #r) or 0
                        local nu = (type(u) == "table" and #u) or 0
                        if na == 0 and nr == 0 and nu == 0 then
                            return
                        end
                    end
                end


                if unit and ShouldProcessUnitEvent(unit, true) then
                    -- Feed delta info into the Aura Store (secret-safe; avoids full rescan per burst).
                    local Store = API and API.Store
                    local onAura = Store and Store.OnUnitAura
                    if type(onAura) == "function" then
                        onAura(unit, updateInfo)
                    end

                    -- MarkDirty expects a numeric delay (or nil). Never pass updateInfo (table).
                    MarkDirty(unit)
                end
            end
            ef._msufA2_unitAuraOnEvent = handler
        end

        for i = 1, #list do
            local f = list[i]
            if f and f.SetScript then
                if f.IsEventRegistered and f:IsEventRegistered("UNIT_AURA") then
                    f:SetScript("OnEvent", handler)
                else
                    f:SetScript("OnEvent", nil)
                end
            end
        end
    end

    -- Boss attach retry only when boss units are enabled
    if needBoss then
        StartBossAttachRetry()
    else
        StopBossRetry()
    end
end

API.ApplyEventRegistration = API.ApplyEventRegistration or function()
    if Events.ApplyEventRegistration then
        return Events.ApplyEventRegistration()
    end
end

function Events.Init()
    if Events._inited then return end
    Events._inited = true

    -- Ensure we have the real DB once before registering listeners.
    EnsureDB()

    local ef = CreateFrame("Frame")
    Events._eventFrame = ef

    -- EventFrame main handler (non-UNIT_AURA)
    ef:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_TARGET_CHANGED" then
            -- Target swap should feel instant: request next-frame render (0 delay)
            local Store = API and API.Store
            if Store and Store.InvalidateUnit then Store.InvalidateUnit("target") end
            if ShouldProcessUnitEvent("target") then MarkDirty("target", 0) end
            return
        end

        if event == "PLAYER_FOCUS_CHANGED" then
            local Store = API and API.Store
            if Store and Store.InvalidateUnit then Store.InvalidateUnit("focus") end
            if ShouldProcessUnitEvent("focus") then MarkDirty("focus", 0) end
            return
        end

        if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
            local Store = API and API.Store
            if Store and Store.InvalidateUnit then
                for i = 1, 5 do Store.InvalidateUnit("boss" .. i) end
            end
            for i = 1, 5 do
                local u = "boss" .. i
                if ShouldProcessUnitEvent(u) then
                    MarkDirty(u, 0)
                end
            end
            StartBossAttachRetry()
            return
        end

        if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            EnsureDB() -- prime + cache

            -- Ensure event registration is aligned now that EnsureDB is definitely bound and cache is ready.
            -- Fixes a rare load-order case where Events.Init ran before Render bound EnsureDB, which
            -- could leave UNIT_AURA bindings (especially for player) disabled until a manual RefreshAll.
            if Events.ApplyEventRegistration then
                Events.ApplyEventRegistration()
            end

            local Store = API and API.Store
            if Store and Store.InvalidateUnit then
                Store.InvalidateUnit("player")
                Store.InvalidateUnit("target")
                Store.InvalidateUnit("focus")
                for i = 1, 5 do Store.InvalidateUnit("boss" .. i) end
            end

            if ShouldProcessUnitEvent("player") then MarkDirty("player", 0) end
            if ShouldProcessUnitEvent("target") then MarkDirty("target", 0) end
            if ShouldProcessUnitEvent("focus") then MarkDirty("focus") end
            for i = 1, 5 do
                local u = "boss" .. i
                if ShouldProcessUnitEvent(u) then
                    MarkDirty(u)
                end
            end

            if Events.UpdateEditModePoll then
                Events.UpdateEditModePoll()
            end
        end
    end)

    Events.ApplyEventRegistration()

    -- Preferred path: hook into MSUF Edit Mode enter/exit notifications (no polling).
    if not TryHookAnyEditModeListener() then
        -- Load-order safety: Auras2 can init before MSUF_EditMode.lua has created the broadcaster.
        -- Retry via timers; poll fallback is only enabled if hooks are not possible.
        ScheduleAnyEditModeHookRetry()
    else
        -- Sync once (covers rare /reload while Edit Mode already active).
        OnAnyEditModeChanged(IsEditModeActive())
    end
end

-- ------------------------------------------------------------
-- Global wrappers (existing external call sites)
-- ------------------------------------------------------------
if _G and type(_G.MSUF_Auras2_ApplyEventRegistration) ~= "function" then
    _G.MSUF_Auras2_ApplyEventRegistration = function()
        return API.ApplyEventRegistration()
    end
end

if _G and type(_G.MSUF_Auras2_OnAnyEditModeChanged) ~= "function" then
    _G.MSUF_Auras2_OnAnyEditModeChanged = function(active)
        return API.OnAnyEditModeChanged(active)
    end
end

if _G and type(_G.MSUF_Auras2_UpdateEditModePoll) ~= "function" then
    _G.MSUF_Auras2_UpdateEditModePoll = function()
        return API.UpdateEditModePoll()
    end
end

-- Load-order safety:
-- Render.lua calls API.Init() at load time, but depending on .toc order this Events module
-- can load AFTER Render. In that case, events would never register unless something else
-- calls Init again (e.g., opening Options or entering Edit Mode). Ensure we always
-- (re)run Init once this module is present.
if API and API.Init then
    API.Init()
end
