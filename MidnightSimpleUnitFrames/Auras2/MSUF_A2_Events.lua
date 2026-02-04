-- MSUF_A2_Events.lua
-- Auras 2.0 event driver (UNIT_AURA + target/focus/boss changes + Edit Mode preview refresh).
-- Phase 2: moved out of the render module.

local addonName, ns = ...


-- MSUF: Max-perf Auras2: replace protected calls (pcall) with direct calls.
-- NOTE: this removes error-catching; any error will propagate.
local function MSUF_A2_FastCall(fn, ...)
    return true, fn(...)
end
ns = ns or {}

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

local function MarkDirty(unit)
    local f = API.MarkDirty
    if type(f) == "function" then
        f(unit)
    end
end

local function IsEditModeActive()
    local f = API.IsEditModeActive
    if type(f) == "function" then
        return f() == true
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
local function _A2_UnitWantsPrivateAuras(shared, unit)
    if not unit or not shared then return false end
    if unit == "target" then return false end

    -- Private Auras require modern C_UnitAuras.AddPrivateAuraAnchor support.
    if not (C_UnitAuras and type(C_UnitAuras.AddPrivateAuraAnchor) == "function") then
        return false
    end

    local show = false
    local maxN = nil

    if unit == "player" then
        show = (shared.showPrivateAurasPlayer == true)
        maxN = shared.privateAuraMaxPlayer
    elseif unit == "focus" then
        show = (shared.showPrivateAurasFocus == true)
        maxN = shared.privateAuraMaxOther
    elseif unit and unit:match("^boss%d$") then
        show = (shared.showPrivateAurasBoss == true)
        maxN = shared.privateAuraMaxOther
    else
        return false
    end

    if not show then return false end

    if type(maxN) ~= "number" then maxN = 6 end
    if maxN < 0 then maxN = 0 end
    if maxN > 12 then maxN = 12 end

    return (maxN > 0)
end

-- Hot path: use cached unit-enabled flags (no DB work). Falls back to EnsureDB once if cache is cold.
-- forAuraEvent=true => ONLY consider standard aura rendering (avoid UNIT_AURA spam when only private auras are enabled).
local function ShouldProcessUnitEvent(unit, forAuraEvent)
    if not unit then return false end

    local DB = API.DB
    if DB and DB.UnitEnabledCached and DB.cache and DB.cache.ready then
        if DB.UnitEnabledCached(unit) then return true end
        if (not forAuraEvent) and _A2_UnitWantsPrivateAuras(DB.cache.shared, unit) then
            return true
        end
        if DB.cache.showInEditMode and IsEditModeActive() then
            return true
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
        if DB.UnitEnabledCached(unit) then return true end
        if (not forAuraEvent) and _A2_UnitWantsPrivateAuras(DB.cache.shared, unit) then
            return true
        end
        if DB.cache.showInEditMode and IsEditModeActive() then
            return true
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
    if not eventFrame or eventFrame._msufA2_unitAuraBound then
        return
    end

    eventFrame._msufA2_unitAuraFrames = eventFrame._msufA2_unitAuraFrames or {}
    local frames = eventFrame._msufA2_unitAuraFrames

    local function Ensure(idx, unit1, unit2)
        local f = frames[idx]
        if not f then
            f = CreateFrame("Frame")
            frames[idx] = f
        end

        -- Re-register cleanly
        if f.IsEventRegistered and f:IsEventRegistered("UNIT_AURA") then
            SafePCall(f.UnregisterEvent, f, "UNIT_AURA")
        end

        local regUnit = f.RegisterUnitEvent
        if type(regUnit) == "function" then
            if unit2 then
                regUnit(f, "UNIT_AURA", unit1, unit2)
            else
                regUnit(f, "UNIT_AURA", unit1)
            end
        end

        f._msufA2_unitAuraUnits = f._msufA2_unitAuraUnits or {}
        f._msufA2_unitAuraUnits[1], f._msufA2_unitAuraUnits[2] = unit1, unit2
    end

    -- Keep player auras (own-aura highlighting/stack tracking), target/focus, and all bosses.
    Ensure(1, "player", "target")
    Ensure(2, "focus", "boss1")
    Ensure(3, "boss2", "boss3")
    Ensure(4, "boss4", "boss5")

    eventFrame._msufA2_unitAuraBound = true
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
                SafePCall(frame.RegisterEvent, frame, event)
            end
        end
    end

    -- Unregister events no longer desired (only those we own)
    for event, owner in pairs(owned) do
        if owner and desiredOwners[event] == nil then
            owned[event] = nil
            if frame.UnregisterEvent then
                SafePCall(frame.UnregisterEvent, frame, event)
            end
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


-- Fallback polling (LAST RESORT): must never run permanently in idle.
--
-- NOTE: When MSUF_RegisterAnyEditModeListener() is available, we rely on that and keep this polling OFF.
-- Polling only exists as a compatibility fallback for older builds / missed lifecycle events.
local _pollLast = nil
local _pollAcc = 0
local _polling = false

local function _A2_DebugPollEnabled()
    local gdb = _G and rawget(_G, "MSUF_DB")
    if gdb and gdb.general and gdb.general.debugAuras2Poll == true then return true end
    if _G and rawget(_G, "MSUF_A2_DEBUG_POLL") == true then return true end
    return false
end

local function _A2_HasEditModeListener()
    if Events._hasEditModeListener ~= nil then
        return (Events._hasEditModeListener == true)
    end
    return (_G and type(_G.MSUF_RegisterAnyEditModeListener) == "function") or false
end

local function _A2_DirtyListNotEmpty()
    local f = API and API.DirtyListNotEmpty
    if type(f) == "function" then
        local ok, v = MSUF_A2_FastCall(f)
        return ok and v == true
    end
    local g = _G and rawget(_G, "MSUF_A2_DirtyListNotEmpty")
    if type(g) == "function" then
        local ok, v = MSUF_A2_FastCall(g)
        return ok and v == true
    end
    return false
end

local function _A2_TestmodeEnabled()
    local p = API and API.Preview
    if p and type(p.IsTestModeActive) == "function" then
        local ok, v = MSUF_A2_FastCall(p.IsTestModeActive, p)
        return ok and v == true
    end
    return false
end

local function _A2_ShouldPollNow()
    local cur = IsEditModeActive()

    if _A2_DebugPollEnabled() then
        return true, cur
    end

    -- If we have a proper listener, polling is unnecessary and should stay off.
    if _A2_HasEditModeListener() then
        return false, cur
    end

    -- Minimal-safe fallback rules (only when really needed):
    -- - dirty render work pending
    -- - preview/testmode toggle enabled (showInEditMode)
    -- - Edit Mode active
    -- - explicit debug fallback (handled above)
    if cur == true then
        return true, cur
    end

    if _A2_DirtyListNotEmpty() then
        return true, cur
    end

    if _A2_TestmodeEnabled() then
        return true, cur
    end

    local _, shared = EnsureDB()
    if shared and shared.showInEditMode == true then
        return true, cur
    end

    return false, cur
end

local function _A2_StopPoll()
    local ef = Events._eventFrame
    _polling = false
    _pollAcc = 0
    if ef and ef.SetScript then
        ef:SetScript("OnUpdate", nil)
    end
end

local function PollOnUpdate(_, elapsed)
    _pollAcc = _pollAcc + (elapsed or 0)
    if _pollAcc < 0.25 then return end
    _pollAcc = 0

    local wantPoll, cur = _A2_ShouldPollNow()
    if not wantPoll then
        _A2_StopPoll()
        return
    end

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

    -- If listener exists (normal case), force-disable the poll unless explicitly debugging.
    if _A2_HasEditModeListener() and not _A2_DebugPollEnabled() then
        if _polling then
            _A2_StopPoll()
        end
        return
    end

    local wantPoll, cur = _A2_ShouldPollNow()

    if wantPoll and not _polling then
        _polling = true
        _pollAcc = 0
        _pollLast = cur
        ef:SetScript("OnUpdate", PollOnUpdate)
    elseif (not wantPoll) and _polling then
        _A2_StopPoll()
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

    EnsureUnitAuraBinding(ef)

    ApplyOwnedEvents(ef, {
        PLAYER_LOGIN = "Core",
        PLAYER_ENTERING_WORLD = "Core",
        PLAYER_TARGET_CHANGED = "Core",
        PLAYER_FOCUS_CHANGED = "Core",
        INSTANCE_ENCOUNTER_ENGAGE_UNIT = "Core",
    })

    -- Bind UNIT_AURA scripts for helper frames
    local list = ef._msufA2_unitAuraFrames
    if type(list) == "table" then
        local function UnitAuraOnEvent(_, event, arg1)
            if event ~= "UNIT_AURA" then return end
            if arg1 and ShouldProcessUnitEvent(arg1, true) then
                MarkDirty(arg1)
            end
        end

        for i = 1, #list do
            local f = list[i]
            if f and f.SetScript then
                f:SetScript("OnEvent", UnitAuraOnEvent)
            end
        end
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
            if ShouldProcessUnitEvent("target") then MarkDirty("target") end
            return
        end

        if event == "PLAYER_FOCUS_CHANGED" then
            if ShouldProcessUnitEvent("focus") then MarkDirty("focus") end
            return
        end

        if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
            for i = 1, 5 do
                local u = "boss" .. i
                if ShouldProcessUnitEvent(u) then
                    MarkDirty(u)
                end
            end
            StartBossAttachRetry()
            return
        end

        if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            EnsureDB() -- prime + cache

            if ShouldProcessUnitEvent("player") then MarkDirty("player") end
            if ShouldProcessUnitEvent("target") then MarkDirty("target") end
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

    -- Preferred path: subscribe to shared MSUF Edit Mode notifications
    if _G and type(_G.MSUF_RegisterAnyEditModeListener) == "function" then
        Events._hasEditModeListener = true
        _G.MSUF_RegisterAnyEditModeListener(OnAnyEditModeChanged)
    else
        Events._hasEditModeListener = false
        -- Fallback poll
        Events.UpdateEditModePoll()
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
