--- Castbars/MSUF_CastbarGCD.lua - GCD bar (instant casts) on the Player castbar.
---
--- 12.1 rebuild of the 5.x GCD bar. Everything time-driven runs C-side:
--- UNIT_SPELLCAST_SUCCEEDED (player/vehicle only) resolves the active global
--- cooldown as a native duration object (C_Spell.GetSpellCooldownDuration on
--- the GCD dummy spell 61304) and binds it to the player castbar through the
--- shared castbar Runtime (StatusBar timer + DurationTextBinding). No OnUpdate
--- tick exists anywhere in this module; fill and time text advance in C, and
--- teardown is one C_Timer armed from the plain remaining time. When the
--- cooldown values are secret, a coarse ticker polls SpellCooldownInfo.isActive
--- instead - that field is NeverSecret in the 12.1 API contract.
---
--- Unlike 5.x this is haste-correct: the duration object describes the real
--- scaled GCD, so no base-GCD approximation and no GetHaste() taint hazard.
---
--- The event is unregistered while the feature is disabled - true zero cost.
---
--- DB keys (MSUF_DB.general, seeded in State/MSUF_Defaults.lua):
---   showGCDBar       - master toggle
---   showGCDBarTime   - remaining-time text on the GCD bar
---   showGCDBarSpell  - spell name + icon on the GCD bar

local _, ns = ...
ns = ns or _G.MSUF_NS or {}

local _G = _G
local CreateFrame = CreateFrame
local C_Timer = C_Timer

--- The classic "Global Cooldown" dummy spell: querying its cooldown yields the
--- player's current GCD window.
local GCD_SPELL_ID = 61304

--- Safety cap for the secret-cooldown poll fallback (0.1s cadence). The GCD
--- never exceeds 1.5s; anything past this is a stuck state we force-clear.
local POLL_INTERVAL = 0.1
local POLL_MAX_TICKS = 25

-- ============================================================
-- Settings
-- ============================================================
local function GeneralDB()
    local db = _G.MSUF_DB
    return db and db.general or nil
end

local function IsGCDBarEnabled()
    local g = GeneralDB()
    return g ~= nil and g.showGCDBar == true
end

-- ============================================================
-- Static spell metadata cache (name/icon for instants, skip set)
-- ============================================================
--- Once a spellID is known to never produce a GCD bar (hard-cast or off-GCD)
--- it can not change mid-session: one table lookup replaces every API call.
local spellSkip = {}
local spellNames = {}
local spellIcons = {}

local function PlainNumber(value)
    local plain = _G.MSUF_CastbarRuntime_PlainNumber
    if type(plain) == "function" then return plain(value) end
    if type(value) == "number" then return value end
    return nil
end

--- Resolves and caches name/icon for an instant spell. Returns nil for
--- hard-casts (and records them in the skip set).
local function ResolveInstantSpell(spellID)
    local name = spellNames[spellID]
    if name ~= nil then return name end

    local spellAPI = _G.C_Spell
    local getInfo = spellAPI and spellAPI.GetSpellInfo
    if type(getInfo) ~= "function" then return nil end

    local info = getInfo(spellID)
    if not info then return nil end

    -- Static spell data; plain on 12.1. An unreadable castTime is not cached:
    -- do not show, do not poison the skip set.
    local castTime = PlainNumber(info.castTime)
    if castTime == nil then return nil end
    if castTime > 0 then
        spellSkip[spellID] = true
        return nil
    end

    name = info.name or ""
    spellNames[spellID] = name
    spellIcons[spellID] = info.iconID
    return name
end

-- ============================================================
-- Bar lifecycle
-- ============================================================
local function CancelFinishTimers(frame)
    local timer = frame._msufGCDTimer
    if timer then
        frame._msufGCDTimer = nil
        if timer.Cancel then timer:Cancel() end
    end
    local ticker = frame._msufGCDTicker
    if ticker then
        frame._msufGCDTicker = nil
        if ticker.Cancel then ticker:Cancel() end
    end
end

--- A real cast/channel/empower owns the bar; the GCD bar must never touch the
--- frame while any of these is active.
local function BarOwnedByRealCast(frame)
    return frame.MSUF_castActive == true
        or frame._msufActiveCastUnit ~= nil
        or frame.isEmpower == true
end

local function FinishGCDBar(frame)
    if not frame then return end
    -- Cancel before the active check: a stray ticker must never survive an
    -- already-cleared GCD state.
    CancelFinishTimers(frame)
    if frame._msufGCDActive ~= true then return end
    frame._msufGCDActive = nil

    -- A real cast took over: its apply path already rebound timer, text and
    -- color. Only drop GCD ownership.
    if BarOwnedByRealCast(frame) then return end

    local runtime = _G.MSUF_CastbarRuntime
    if runtime then
        runtime:DisableNativeTimeText(frame)
        runtime:ClearTimer(frame.statusBar)
    end

    -- An edit-mode test cast that started mid-GCD owns the visuals now; only
    -- the native bindings above needed to be released.
    if frame.MSUF_testMode == true then return end

    local applyTexts = _G.MSUF_CB_ApplyTexts
    if type(applyTexts) == "function" then
        applyTexts(frame, nil, "", "")
    else
        if frame.castText then frame.castText:SetText("") end
        if frame.timeText then frame.timeText:SetText("") end
    end

    frame:Hide()
end

--- Poll fallback for secret cooldown values: SpellCooldownInfo.isActive is
--- NeverSecret, so this stays legal when startTime/duration are not.
local function GCDStillActive()
    local spellAPI = _G.C_Spell
    local getCooldown = spellAPI and spellAPI.GetSpellCooldown
    if type(getCooldown) ~= "function" then return false end
    local cooldown = getCooldown(GCD_SPELL_ID)
    return cooldown ~= nil and cooldown.isActive == true
end

--- Persistent finish callbacks: exactly one player castbar exists and
--- CancelFinishTimers guarantees at most one pending timer/ticker, so the
--- per-GCD closure allocation of the 5.x version is not needed.
local pollTicks = 0

local function OnFinishTimer()
    local frame = _G.MSUF_PlayerCastbar
    if not frame then return end
    frame._msufGCDTimer = nil
    FinishGCDBar(frame)
end

local function OnPollTicker()
    local frame = _G.MSUF_PlayerCastbar
    if not frame then return end
    pollTicks = pollTicks + 1
    if frame._msufGCDActive ~= true
        or pollTicks >= POLL_MAX_TICKS
        or not GCDStillActive()
    then
        FinishGCDBar(frame)
    end
end

local function ArmFinish(frame, durationObj)
    CancelFinishTimers(frame)

    -- Preferred: one exact timer from the plain remaining time.
    local getRemaining = durationObj.GetRemainingDuration or durationObj.GetRemaining
    local remaining
    if type(getRemaining) == "function" then
        -- Secret GCD durations return secret values; PlainNumber rejects them
        -- into the bounded NeverSecret poll ticker below.
        remaining = PlainNumber(getRemaining(durationObj))
    end

    if remaining and remaining > 0 then
        frame._msufGCDTimer = C_Timer.NewTimer(remaining + 0.03, OnFinishTimer)
        return
    end

    -- Secret cooldown: coarse NeverSecret poll, hard-capped.
    pollTicks = 0
    frame._msufGCDTicker = C_Timer.NewTicker(POLL_INTERVAL, OnPollTicker)
end

local function StartGCDBar(frame, spellID, durationObj)
    local runtime = _G.MSUF_CastbarRuntime
    local statusBar = frame.statusBar
    if not (runtime and statusBar) then return end

    --- One mutable duration container per frame (shared with the cast path);
    --- Assign copies the GCD window into it without allocating.
    local stable = runtime:RetainDuration(frame, durationObj)

    local reverseFill = false
    local getReverse = _G.MSUF_GetReverseFillSafe
    if type(getReverse) == "function" then
        reverseFill = getReverse(frame, false) == true
    end

    -- C-side fill or nothing: without a working SetTimerDuration there is no
    -- zero-cost way to animate the GCD, and this module never installs an
    -- OnUpdate tick.
    if not runtime:ApplyTimer(statusBar, stable, reverseFill, false, true) then
        return
    end

    frame._msufGCDActive = true
    frame.interrupted = nil

    local g = GeneralDB()
    local showTime = g == nil or g.showGCDBarTime ~= false
    local showSpell = g == nil or g.showGCDBarSpell ~= false
    local applyTexts = _G.MSUF_CB_ApplyTexts

    local castText = ""
    if showSpell then
        castText = spellNames[spellID] or ""
        local iconID = spellIcons[spellID]
        if frame.icon and iconID then
            frame.icon:SetTexture(iconID)
        end
    end
    if type(applyTexts) == "function" then
        applyTexts(frame, nil, castText, nil)
    elseif frame.castText then
        frame.castText:SetText(castText)
    end

    if showTime and frame.timeText then
        runtime:BindNativeTimeText(frame, stable, "CURRENT")
    else
        runtime:DisableNativeTimeText(frame)
        if type(applyTexts) == "function" then
            applyTexts(frame, nil, nil, "")
        elseif frame.timeText then
            frame.timeText:SetText("")
        end
    end

    local updateColor = _G.MSUF_PlayerCastbar_UpdateColorForInterruptible
    if type(updateColor) == "function" then
        updateColor(frame)
    end

    if frame.latencyBar then
        frame.latencyBar:Hide()
    end

    frame:Show()
    ArmFinish(frame, stable)
end

-- ============================================================
-- Driver: UNIT_SPELLCAST_SUCCEEDED -> GCD bar
-- ============================================================
local driver = CreateFrame("Frame", "MSUF_GCDBarDriver")
local succeededRegistered = false

local function SyncRegistration()
    local want = IsGCDBarEnabled()
    if want == succeededRegistered then return end
    succeededRegistered = want
    if want then
        driver:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "vehicle")
    else
        driver:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
end

local function OnSucceeded(spellID)
    -- Guard against stale registration after a profile switch: read the live
    -- setting and self-heal the event registration.
    if not IsGCDBarEnabled() then
        SyncRegistration()
        return
    end

    if not spellID or spellSkip[spellID] then return end

    local frame = _G.MSUF_PlayerCastbar
    if frame then
        if BarOwnedByRealCast(frame) then return end
        if frame.MSUF_testMode then return end
        -- Interrupt feedback is a deliberate visual hold; let it play out.
        if frame.interrupted then return end
    end

    if ResolveInstantSpell(spellID) == nil then return end

    -- Instant cast confirmed. If no GCD is active at this synchronous event
    -- the spell is off-GCD (GCD-triggering instants always leave isActive
    -- true here) - cache that verdict.
    if not GCDStillActive() then
        spellSkip[spellID] = true
        return
    end

    local isCastbarEnabled = _G.MSUF_IsCastbarEnabledForUnit
    if type(isCastbarEnabled) == "function" and not isCastbarEnabled("player") then
        return
    end

    if not frame then
        local init = _G.MSUF_InitSafePlayerCastbar
        if type(init) ~= "function" then return end
        init()
        frame = _G.MSUF_PlayerCastbar
        if not frame then return end
    end

    local spellAPI = _G.C_Spell
    local getDuration = spellAPI and spellAPI.GetSpellCooldownDuration
    if type(getDuration) ~= "function" then return end
    local durationObj = getDuration(GCD_SPELL_ID)
    if not durationObj then return end

    StartGCDBar(frame, spellID, durationObj)
end

driver:SetScript("OnEvent", function(_, event, _, _, spellID)
    if event == "PLAYER_ENTERING_WORLD" then
        SyncRegistration()
        return
    end
    OnSucceeded(spellID)
end)
--- Kept registered permanently: fires once per loading screen and re-syncs the
--- SUCCEEDED registration after login-time profile binding.
driver:RegisterEvent("PLAYER_ENTERING_WORLD")

-- ============================================================
-- Public API (menu + castbar apply pipeline)
-- ============================================================
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

ExportPublic("MSUF_IsGCDBarEnabled", IsGCDBarEnabled)
ExportPublic("MSUF_GCDBar_SyncRegistration", SyncRegistration)

ExportPublic("MSUF_SetGCDBarEnabled", function(enabled)
    local g = GeneralDB()
    if g then
        g.showGCDBar = (enabled == true)
    end
    SyncRegistration()
    if not enabled then
        FinishGCDBar(_G.MSUF_PlayerCastbar)
    end
end)
