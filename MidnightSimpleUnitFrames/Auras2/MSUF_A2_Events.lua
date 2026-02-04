--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua"); -- MSUF_A2_Events.lua
-- Auras 2.0 event driver (UNIT_AURA + target/focus/boss changes + Edit Mode preview refresh).
-- Phase 2: moved out of the render module.

local addonName, ns = ...
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
local function SafePCall(fn, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "SafePCall file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:21:6");
    if type(fn) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "SafePCall file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:21:6"); return end
    local ok, _ = pcall(fn, ...)
    Perfy_Trace(Perfy_GetTime(), "Leave", "SafePCall file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:21:6"); return ok
end

local function MarkDirty(unit) Perfy_Trace(Perfy_GetTime(), "Enter", "MarkDirty file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:27:6");
    local f = API.MarkDirty
    if type(f) == "function" then
        f(unit)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MarkDirty file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:27:6"); end

local function IsEditModeActive() Perfy_Trace(Perfy_GetTime(), "Enter", "IsEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:34:6");
    local f = API.IsEditModeActive
    if type(f) == "function" then
        return Perfy_Trace_Passthrough("Leave", "IsEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:34:6", f() == true)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "IsEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:34:6"); return false
end

local function EnsureDB() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:42:6");
    local DB = API.DB
    if DB and DB.Ensure then
        return Perfy_Trace_Passthrough("Leave", "EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:42:6", DB.Ensure())
    end
    local f = API.EnsureDB
    if type(f) == "function" then
        return Perfy_Trace_Passthrough("Leave", "EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:42:6", f())
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:42:6"); return nil
end

-- Hot path: use cached unit-enabled flags (no DB work). Falls back to EnsureDB once if cache is cold.
local function _A2_UnitWantsPrivateAuras(shared, unit) Perfy_Trace(Perfy_GetTime(), "Enter", "_A2_UnitWantsPrivateAuras file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:55:6");
    if not unit or not shared then Perfy_Trace(Perfy_GetTime(), "Leave", "_A2_UnitWantsPrivateAuras file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:55:6"); return false end
    if unit == "target" then Perfy_Trace(Perfy_GetTime(), "Leave", "_A2_UnitWantsPrivateAuras file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:55:6"); return false end

    -- Private Auras require modern C_UnitAuras.AddPrivateAuraAnchor support.
    if not (C_UnitAuras and type(C_UnitAuras.AddPrivateAuraAnchor) == "function") then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_A2_UnitWantsPrivateAuras file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:55:6"); return false
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "_A2_UnitWantsPrivateAuras file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:55:6"); return false
    end

    if not show then Perfy_Trace(Perfy_GetTime(), "Leave", "_A2_UnitWantsPrivateAuras file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:55:6"); return false end

    if type(maxN) ~= "number" then maxN = 6 end
    if maxN < 0 then maxN = 0 end
    if maxN > 12 then maxN = 12 end

    return Perfy_Trace_Passthrough("Leave", "_A2_UnitWantsPrivateAuras file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:55:6", (maxN > 0))
end

-- Hot path: use cached unit-enabled flags (no DB work). Falls back to EnsureDB once if cache is cold.
-- forAuraEvent=true => ONLY consider standard aura rendering (avoid UNIT_AURA spam when only private auras are enabled).
local function ShouldProcessUnitEvent(unit, forAuraEvent) Perfy_Trace(Perfy_GetTime(), "Enter", "ShouldProcessUnitEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:91:6");
    if not unit then Perfy_Trace(Perfy_GetTime(), "Leave", "ShouldProcessUnitEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:91:6"); return false end

    local DB = API.DB
    if DB and DB.UnitEnabledCached and DB.cache and DB.cache.ready then
        if DB.UnitEnabledCached(unit) then Perfy_Trace(Perfy_GetTime(), "Leave", "ShouldProcessUnitEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:91:6"); return true end
        if (not forAuraEvent) and _A2_UnitWantsPrivateAuras(DB.cache.shared, unit) then
            Perfy_Trace(Perfy_GetTime(), "Leave", "ShouldProcessUnitEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:91:6"); return true
        end
        if DB.cache.showInEditMode and IsEditModeActive() then
            Perfy_Trace(Perfy_GetTime(), "Leave", "ShouldProcessUnitEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:91:6"); return true
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "ShouldProcessUnitEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:91:6"); return false
    end

    -- Cold start: ensure DB once, then retry cache path.
    local a2, shared = EnsureDB()
    DB = API.DB
    if DB and DB.RebuildCache then
        DB.RebuildCache(a2, shared)
    end

    if DB and DB.UnitEnabledCached and DB.cache and DB.cache.ready then
        if DB.UnitEnabledCached(unit) then Perfy_Trace(Perfy_GetTime(), "Leave", "ShouldProcessUnitEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:91:6"); return true end
        if (not forAuraEvent) and _A2_UnitWantsPrivateAuras(DB.cache.shared, unit) then
            Perfy_Trace(Perfy_GetTime(), "Leave", "ShouldProcessUnitEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:91:6"); return true
        end
        if DB.cache.showInEditMode and IsEditModeActive() then
            Perfy_Trace(Perfy_GetTime(), "Leave", "ShouldProcessUnitEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:91:6"); return true
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "ShouldProcessUnitEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:91:6"); return false
    end

    -- Fallback (should be rare): conservative deny.
    Perfy_Trace(Perfy_GetTime(), "Leave", "ShouldProcessUnitEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:91:6"); return false
end

-- Export so Render/Options can call the exact same gating without duplicating logic.
API.ShouldProcessUnitEvent = API.ShouldProcessUnitEvent or ShouldProcessUnitEvent

local function FindUnitFrame(unit) Perfy_Trace(Perfy_GetTime(), "Enter", "FindUnitFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:131:6");
    local f = API.FindUnitFrame
    if type(f) == "function" then
        return Perfy_Trace_Passthrough("Leave", "FindUnitFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:131:6", f(unit))
    end

    local uf = _G and _G.MSUF_UnitFrames
    if type(uf) == "table" and unit and uf[unit] then
        return Perfy_Trace_Passthrough("Leave", "FindUnitFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:131:6", uf[unit])
    end
    local g = _G and unit and _G["MSUF_" .. unit]
    Perfy_Trace(Perfy_GetTime(), "Leave", "FindUnitFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:131:6"); return g
end

-- ------------------------------------------------------------
-- UNIT_AURA binding (helper frames)
-- ------------------------------------------------------------
local function EnsureUnitAuraBinding(eventFrame) Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureUnitAuraBinding file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:148:6");
    if not eventFrame or eventFrame._msufA2_unitAuraBound then
        Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureUnitAuraBinding file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:148:6"); return
    end

    eventFrame._msufA2_unitAuraFrames = eventFrame._msufA2_unitAuraFrames or {}
    local frames = eventFrame._msufA2_unitAuraFrames

    local function Ensure(idx, unit1, unit2) Perfy_Trace(Perfy_GetTime(), "Enter", "Ensure file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:156:10");
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "Ensure file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:156:10"); end

    -- Keep player auras (own-aura highlighting/stack tracking), target/focus, and all bosses.
    Ensure(1, "player", "target")
    Ensure(2, "focus", "boss1")
    Ensure(3, "boss2", "boss3")
    Ensure(4, "boss4", "boss5")

    eventFrame._msufA2_unitAuraBound = true
Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureUnitAuraBinding file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:148:6"); end

-- ------------------------------------------------------------
-- Owned event registration helper
-- ------------------------------------------------------------
local function ApplyOwnedEvents(frame, desiredOwners) Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyOwnedEvents file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:193:6");
    if not frame or type(desiredOwners) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyOwnedEvents file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:193:6"); return end

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
Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyOwnedEvents file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:193:6"); end

-- ------------------------------------------------------------
-- Boss attach retry (ENGAGE_UNIT race)
-- ------------------------------------------------------------
local BossAttachRetryTicker = nil

local function StopBossRetry() Perfy_Trace(Perfy_GetTime(), "Enter", "StopBossRetry file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:225:6");
    if BossAttachRetryTicker then
        BossAttachRetryTicker:Cancel()
        BossAttachRetryTicker = nil
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "StopBossRetry file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:225:6"); end

local function StartBossAttachRetry() Perfy_Trace(Perfy_GetTime(), "Enter", "StartBossAttachRetry file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:232:6");
    StopBossRetry()

    if not C_Timer or not C_Timer.NewTicker then Perfy_Trace(Perfy_GetTime(), "Leave", "StartBossAttachRetry file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:232:6"); return end

    local tries = 0
    BossAttachRetryTicker = C_Timer.NewTicker(0.15, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:238:52");
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:238:52"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "StartBossAttachRetry file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:232:6"); end

-- ------------------------------------------------------------
-- Edit Mode preview refresh + fallback poll
-- ------------------------------------------------------------
local function MarkAllDirty() Perfy_Trace(Perfy_GetTime(), "Enter", "MarkAllDirty file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:263:6");
    MarkDirty("player")
    MarkDirty("target")
    MarkDirty("focus")
    for i = 1, 5 do MarkDirty("boss" .. i) end
Perfy_Trace(Perfy_GetTime(), "Leave", "MarkAllDirty file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:263:6"); end

local function OnAnyEditModeChanged(active) Perfy_Trace(Perfy_GetTime(), "Enter", "OnAnyEditModeChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:270:6");
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
Perfy_Trace(Perfy_GetTime(), "Leave", "OnAnyEditModeChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:270:6"); end


Events.OnAnyEditModeChanged = OnAnyEditModeChanged
API.OnAnyEditModeChanged = API.OnAnyEditModeChanged or OnAnyEditModeChanged

-- Fallback polling is ONLY active when needed: preview enabled OR currently in edit mode.
local _pollLast = nil
local _pollAcc = 0
local _polling = false

local function PollOnUpdate(_, elapsed) Perfy_Trace(Perfy_GetTime(), "Enter", "PollOnUpdate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:307:6");
    _pollAcc = _pollAcc + (elapsed or 0)
    if _pollAcc < 0.25 then Perfy_Trace(Perfy_GetTime(), "Leave", "PollOnUpdate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:307:6"); return end
    _pollAcc = 0

    local cur = IsEditModeActive()
    if _pollLast == nil then
        _pollLast = cur
        Perfy_Trace(Perfy_GetTime(), "Leave", "PollOnUpdate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:307:6"); return
    end

    if cur ~= _pollLast then
        _pollLast = cur
        OnAnyEditModeChanged(cur)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "PollOnUpdate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:307:6"); end

function Events.UpdateEditModePoll() Perfy_Trace(Perfy_GetTime(), "Enter", "Events.UpdateEditModePoll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:324:0");
    local _, shared = EnsureDB()
    local wantPreview = (shared and shared.showInEditMode == true) or false
    local cur = IsEditModeActive()
    local wantPoll = (wantPreview == true) or (cur == true)

    local ef = Events._eventFrame
    if not ef then Perfy_Trace(Perfy_GetTime(), "Leave", "Events.UpdateEditModePoll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:324:0"); return end

    if wantPoll and not _polling then
        _polling = true
        _pollAcc = 0
        _pollLast = cur
        ef:SetScript("OnUpdate", PollOnUpdate)
    elseif (not wantPoll) and _polling then
        _polling = false
        ef:SetScript("OnUpdate", nil)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "Events.UpdateEditModePoll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:324:0"); end

API.UpdateEditModePoll = API.UpdateEditModePoll or function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:344:51");
    if Events.UpdateEditModePoll then
        return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:344:51", Events.UpdateEditModePoll())
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:344:51"); end

-- ------------------------------------------------------------
-- Public API: ApplyEventRegistration + Init
-- ------------------------------------------------------------
function Events.ApplyEventRegistration() Perfy_Trace(Perfy_GetTime(), "Enter", "Events.ApplyEventRegistration file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:353:0");
    local ef = Events._eventFrame
    if not ef then Perfy_Trace(Perfy_GetTime(), "Leave", "Events.ApplyEventRegistration file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:353:0"); return end

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
        local function UnitAuraOnEvent(_, event, arg1) Perfy_Trace(Perfy_GetTime(), "Enter", "UnitAuraOnEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:370:14");
            if event ~= "UNIT_AURA" then Perfy_Trace(Perfy_GetTime(), "Leave", "UnitAuraOnEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:370:14"); return end
            if arg1 and ShouldProcessUnitEvent(arg1, true) then
                MarkDirty(arg1)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "UnitAuraOnEvent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:370:14"); end

        for i = 1, #list do
            local f = list[i]
            if f and f.SetScript then
                f:SetScript("OnEvent", UnitAuraOnEvent)
            end
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "Events.ApplyEventRegistration file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:353:0"); end

API.ApplyEventRegistration = API.ApplyEventRegistration or function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:386:59");
    if Events.ApplyEventRegistration then
        return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:386:59", Events.ApplyEventRegistration())
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:386:59"); end

function Events.Init() Perfy_Trace(Perfy_GetTime(), "Enter", "Events.Init file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:392:0");
    if Events._inited then Perfy_Trace(Perfy_GetTime(), "Leave", "Events.Init file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:392:0"); return end
    Events._inited = true

    -- Ensure we have the real DB once before registering listeners.
    EnsureDB()

    local ef = CreateFrame("Frame")
    Events._eventFrame = ef

    -- EventFrame main handler (non-UNIT_AURA)
    ef:SetScript("OnEvent", function(_, event, arg1) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:403:28");
        if event == "PLAYER_TARGET_CHANGED" then
            if ShouldProcessUnitEvent("target") then MarkDirty("target") end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:403:28"); return
        end

        if event == "PLAYER_FOCUS_CHANGED" then
            if ShouldProcessUnitEvent("focus") then MarkDirty("focus") end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:403:28"); return
        end

        if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
            for i = 1, 5 do
                local u = "boss" .. i
                if ShouldProcessUnitEvent(u) then
                    MarkDirty(u)
                end
            end
            StartBossAttachRetry()
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:403:28"); return
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:403:28"); end)

    Events.ApplyEventRegistration()

    -- Preferred path: subscribe to shared MSUF Edit Mode notifications
    if _G and type(_G.MSUF_RegisterAnyEditModeListener) == "function" then
        _G.MSUF_RegisterAnyEditModeListener(OnAnyEditModeChanged)
    else
        -- Fallback poll
        Events.UpdateEditModePoll()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "Events.Init file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:392:0"); end

-- ------------------------------------------------------------
-- Global wrappers (existing external call sites)
-- ------------------------------------------------------------
if _G and type(_G.MSUF_Auras2_ApplyEventRegistration) ~= "function" then
    _G.MSUF_Auras2_ApplyEventRegistration = function() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_Auras2_ApplyEventRegistration file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:459:44");
        return Perfy_Trace_Passthrough("Leave", "_G.MSUF_Auras2_ApplyEventRegistration file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:459:44", API.ApplyEventRegistration())
    end
end

if _G and type(_G.MSUF_Auras2_OnAnyEditModeChanged) ~= "function" then
    _G.MSUF_Auras2_OnAnyEditModeChanged = function(active) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_Auras2_OnAnyEditModeChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:465:42");
        return Perfy_Trace_Passthrough("Leave", "_G.MSUF_Auras2_OnAnyEditModeChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:465:42", API.OnAnyEditModeChanged(active))
    end
end

if _G and type(_G.MSUF_Auras2_UpdateEditModePoll) ~= "function" then
    _G.MSUF_Auras2_UpdateEditModePoll = function() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_Auras2_UpdateEditModePoll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:471:40");
        return Perfy_Trace_Passthrough("Leave", "_G.MSUF_Auras2_UpdateEditModePoll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua:471:40", API.UpdateEditModePoll())
    end
end

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_Events.lua");