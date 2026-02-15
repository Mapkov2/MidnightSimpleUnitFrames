-- MSUF Castbar LoD: GCD bar (instant casts)
-- Shows a short "GCD castbar" on the Player castbar for instant spells that trigger the global cooldown.

local _G = _G
local C_Spell = C_Spell

local GetTimePreciseSec = GetTimePreciseSec
local GetTime = GetTime
local GetHaste = GetHaste
local GetSpellBaseCooldown = GetSpellBaseCooldown
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local CreateFrame = CreateFrame

-- ============================================================
-- DB / toggles
-- ============================================================
-- DB keys:
--   MSUF_DB.general.showGCDBar        (default: true)
--   MSUF_DB.general.showGCDBarTime    (default: true)
--   MSUF_DB.general.showGCDBarSpell   (default: true)
local _gcdDefaultsSet = false
local function EnsureGCDDBDefault()
    if _gcdDefaultsSet then return end
    local db = _G.MSUF_DB
    if not db then return end
    local g = db.general
    if not g then return end

    if g.showGCDBar == nil then g.showGCDBar = true end
    if g.showGCDBarTime == nil then g.showGCDBarTime = true end
    if g.showGCDBarSpell == nil then g.showGCDBarSpell = true end
    _gcdDefaultsSet = true
end

function _G.MSUF_IsGCDBarEnabled()
    EnsureGCDDBDefault()
    local db = _G.MSUF_DB
    local g = db and db.general
    if not g then return true end
    return (g.showGCDBar ~= false)
end

function _G.MSUF_GCD_GetSubOptions()
    EnsureGCDDBDefault()
    local db = _G.MSUF_DB
    local g = db and db.general
    if not g then
        return true, true
    end
    return (g.showGCDBarTime ~= false), (g.showGCDBarSpell ~= false)
end

function _G.MSUF_SetGCDBarEnabled(enabled)
    EnsureGCDDBDefault()
    local db = _G.MSUF_DB
    local g = db and db.general
    if g then
        g.showGCDBar = (enabled and true or false)
    end

    -- True zero-cost: unregister the event so OnSucceeded never fires when disabled.
    local drv = _G.MSUF_GCDBarDriver
    if drv then
        if enabled then
            drv:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "vehicle")
        else
            drv:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        end
    end

    if not enabled then
        local f = _G.MSUF_PlayerCastBar or _G.MSUF_PlayerCastbar
        if f and type(_G.MSUF_PlayerGCDBar_Stop) == "function" then
            _G.MSUF_PlayerGCDBar_Stop(f)
        end
    end
end

-- Ensure defaults exist as soon as the LoD loads.
EnsureGCDDBDefault()

-- ============================================================
-- Helpers
-- ============================================================
-- PERF: Resolve time source once.
local _GCDNow = GetTimePreciseSec or GetTime
local function Now()
    return _GCDNow()
end

-- PERF FIX #5: Cache spellIDs that are known to be hard-casts (castTime > 0) or have no GCD.
-- Once a spellID is identified as non-instant or no-GCD, it will never change mid-session,
-- so we can skip 3 API calls (GetSpellInfo + GetSpellBaseCooldown + GetHaste) entirely.
local _gcdSkipCache = {}  -- spellID -> true for spells that will never produce a GCD bar

-- Returns: durationSec, spellName, spellIcon
function _G.MSUF_GCD_GetDurationForSpellID(spellID)
    if not spellID then return nil end

    -- Fast path: cached non-GCD spell (hard-cast or no-GCD)
    if _gcdSkipCache[spellID] then return nil end

    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end

    local info = C_Spell.GetSpellInfo(spellID)
    if not info then return nil end

    -- Only true instant spells.
    local castTime = info.castTime
    if castTime and castTime > 0 then
        _gcdSkipCache[spellID] = true  -- cache: this spell is a hard-cast
        return nil
    end

    -- 2nd return value is base GCD (ms) for that spell. If 0/nil -> no GCD triggered.
    local _, gcdMS = GetSpellBaseCooldown(spellID)
    if not gcdMS or gcdMS <= 0 then
        _gcdSkipCache[spellID] = true  -- cache: this spell has no GCD
        return nil
    end

    local baseGCD = gcdMS / 1000

    local hastePct = (GetHaste and GetHaste()) or 0
    local haste = 1 + (hastePct / 100)
    local scaled = baseGCD / haste

    -- Frogski-style minimum clamps (keeps GCD readable at high haste).
    local minGCD
    if baseGCD > 1.49 then
        minGCD = 0.75
    else
        minGCD = 1.0
    end
    if scaled < minGCD then
        scaled = minGCD
    end
    if scaled <= 0 then
        return nil
    end

    return scaled, info.name, info.iconID
end

-- ============================================================
-- Runtime: start/stop using CastbarManager tick (no per-frame OnUpdate)
-- ============================================================
function _G.MSUF_PlayerGCDBar_Start(frame, unitToken, durationSec, spellName, spellIcon)
    if not frame or not durationSec or durationSec <= 0 then return end

    if type(_G.MSUF_IsGCDBarEnabled) == "function" and not _G.MSUF_IsGCDBarEnabled() then
        return
    end

    -- Respect player castbar enable state (if the core exposes it).
    if type(_G.MSUF_IsCastbarEnabledForUnit) == "function" then
        if not _G.MSUF_IsCastbarEnabledForUnit("player") then
            return
        end
    end

    -- Real cast/channel/empower always wins.
    if frame.isEmpower then return end
    local unit = unitToken or "player"
    if UnitCastingInfo(unit) or UnitChannelInfo(unit) then
        return
    end

    local showTime, showSpell = true, true
    if type(_G.MSUF_GCD_GetSubOptions) == "function" then
        showTime, showSpell = _G.MSUF_GCD_GetSubOptions()
    end

    frame.MSUF_gcdActive = true
    frame.MSUF_gcdStart = Now()
    frame.MSUF_gcdDur = durationSec
    frame.MSUF_gcdUnit = unit
    frame.MSUF_gcdShowTime = showTime
    frame.MSUF_gcdShowSpell = showSpell
    frame.MSUF_gcdSpellName = spellName
    frame.MSUF_gcdSpellIcon = spellIcon
    frame._msufGcdElapsed = 0  -- oUF-style accumulator — eliminates wall clock per tick

    -- Make the bar feel smooth: temporarily run the manager at ~60fps and update this frame at the same cadence.
    -- Save/restore so we don't permanently change the player's castbar cadence.
    -- 12.0 optimization: SetTimerDuration lets C-engine animate the bar → heavy path only needs ~20Hz for time-text.
    if frame.MSUF_gcdPrevTick == nil then
        frame.MSUF_gcdPrevTick = frame._msufTickInterval
    end
    frame._msufTickInterval = 0.05  -- ~20Hz: time-text + GlowFade (was 0.016/60Hz when SetValue drove bar)
    frame._msufHeavyIn = 0


    -- Clear any legacy OnUpdate (older builds used per-frame OnUpdate).
    if frame.SetScript then
        frame:SetScript("OnUpdate", nil)
    end

    if frame.latencyBar and frame.latencyBar.Hide then
        frame.latencyBar:Hide()
    end

    if frame.statusBar and frame.statusBar.SetMinMaxValues then
        frame.statusBar:SetMinMaxValues(0, durationSec)
    end
    -- 12.0: C-engine animates bar fill via SetTimerDuration — eliminates SetValue per tick.
    if frame.statusBar and frame.statusBar.SetTimerDuration then
        frame.statusBar:SetTimerDuration(durationSec)
        frame._msufGcdTimerDriven = true
    elseif frame.statusBar and frame.statusBar.SetValue then
        frame.statusBar:SetValue(0)
        frame._msufGcdTimerDriven = false
        -- Fallback: need higher tick rate for manual SetValue.
        frame._msufTickInterval = 0.016
    end

    if frame.Show then frame:Show() end

    -- Register with CastbarManager so MSUF_UpdateCastbarFrame() can drive the bar.
    if type(_G.MSUF_EnsureCastbarManager) == "function" then
        _G.MSUF_EnsureCastbarManager()
    end

    -- Ensure the manager runs at the higher cadence while the GCD bar is active.
    local m = _G.MSUF_CastbarManager
    if m then
        m._msufHasGCD = true
    end
    if type(_G.MSUF_RegisterCastbar) == "function" then
        _G.MSUF_RegisterCastbar(frame)
    end
end

function _G.MSUF_PlayerGCDBar_Stop(frame, keepVisible)
    if not frame or not frame.MSUF_gcdActive then return end

    frame.MSUF_gcdActive = nil
    frame.MSUF_gcdStart = nil
    frame.MSUF_gcdDur = nil
    frame.MSUF_gcdUnit = nil
    frame._msufGcdElapsed = nil

    frame.MSUF_gcdShowTime = nil
    frame.MSUF_gcdShowSpell = nil
    frame.MSUF_gcdSpellName = nil
    frame.MSUF_gcdSpellIcon = nil

    -- Clear per-GCD dedup caches.
    frame._msufGcdMinMaxSet = nil
    frame._msufGcdLastIcon = nil
    frame._msufGcdCastCheckNext = nil
    frame._msufGcdSubOptsRev = nil
    frame._msufGcdShowTimeCached = nil
    frame._msufGcdShowSpellCached = nil
    frame._msufGcdTimerDriven = nil

    if frame.MSUF_gcdPrevTick ~= nil then
        frame._msufTickInterval = frame.MSUF_gcdPrevTick
        frame.MSUF_gcdPrevTick = nil
    else
        frame._msufTickInterval = nil
    end

    -- Unregister; the normal cast/channel/empower paths will re-register as needed.
    if type(_G.MSUF_UnregisterCastbar) == "function" then
        _G.MSUF_UnregisterCastbar(frame)
    end

    local m = _G.MSUF_CastbarManager
    if m and m._msufHasGCD then
        m._msufHasGCD = nil
    end

    if frame.MSUF_testMode then
        keepVisible = true
    end

    if not keepVisible then
        if frame.Hide then frame:Hide() end
    end
end

-- ============================================================
-- Driver: listen for UNIT_SPELLCAST_SUCCEEDED and start the bar
-- ============================================================
local function GetPlayerBar()
    return _G.MSUF_PlayerCastBar or _G.MSUF_PlayerCastbar
end

local function EnsurePlayerBarExists()
    local bar = GetPlayerBar()
    if bar then return bar end
    if type(_G.MSUF_InitSafePlayerCastbar) == "function" then
        _G.MSUF_InitSafePlayerCastbar()
        bar = GetPlayerBar()
    end
    return bar
end

local function OnSucceeded(_, _, unitTarget, _, spellID)
    if unitTarget ~= "player" and unitTarget ~= "vehicle" then
        return
    end

    -- Cheapest exit: GCD bar disabled.
    -- Should never fire (event unregistered), but guard defensively for race with toggle.
    if type(_G.MSUF_IsGCDBarEnabled) == "function" and not _G.MSUF_IsGCDBarEnabled() then
        return
    end

    -- PERF FIX #5: SpellID cache check (zero-cost table lookup) before any API calls.
    if not spellID or (_gcdSkipCache[spellID]) then
        return
    end

    -- Real cast/channel always wins -- check BEFORE expensive DB lookups.
    if UnitCastingInfo(unitTarget) or UnitChannelInfo(unitTarget) then
        return
    end

    -- If the user disabled the player castbar, don't force-create/show anything.
    if type(_G.MSUF_IsCastbarEnabledForUnit) == "function" then
        if not _G.MSUF_IsCastbarEnabledForUnit("player") then
            return
        end
    end

    local bar = EnsurePlayerBarExists()
    if not bar then return end
    if bar.isEmpower then return end
    if bar.MSUF_testMode then return end

    local dur, name, icon = _G.MSUF_GCD_GetDurationForSpellID(spellID)
    if not dur then return end

    if type(_G.MSUF_PlayerGCDBar_Start) == "function" then
        _G.MSUF_PlayerGCDBar_Start(bar, unitTarget, dur, name, icon)
    end
end

local driver = CreateFrame("Frame", "MSUF_GCDBarDriver")
-- Always register initially (DB might not be loaded yet → defaults to enabled).
-- A deferred sync below will unregister if the saved setting is off.
driver:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "vehicle")
driver:SetScript("OnEvent", OnSucceeded)

-- Deferred cold-state sync: once DB is available, unregister event if GCD bar was saved as disabled.
-- Uses PLAYER_ENTERING_WORLD (fires once per login/reload, after SavedVariables are loaded).
local function SyncGCDRegistration(self, event)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:SetScript("OnEvent", OnSucceeded)  -- restore to GCD handler only
    if _G.MSUF_IsGCDBarEnabled and not _G.MSUF_IsGCDBarEnabled() then
        self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
end
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
-- Temporarily multiplex OnEvent to handle both PLAYER_ENTERING_WORLD and UNIT_SPELLCAST_SUCCEEDED.
driver:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        SyncGCDRegistration(self, event)
    else
        OnSucceeded(self, event, ...)
    end
end)
