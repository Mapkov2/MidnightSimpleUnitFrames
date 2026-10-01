local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
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
local IS_FOREVER = ns.Client ~= nil and ns.Client.IsForever == true

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

local activeFrame, detachedFrame, detachedPreview, idleDuration, gcdBarSupported
local RefreshDetached, RegisterDetachedMover, FinishGCDBar

local function IsGCDBarEnabled()
    local g = GeneralDB()
    return g ~= nil and g.showGCDBar == true
end

--- WoW Forever runs Classic Era spell data, and its client DB (build
--- 1.60.1.69876) has no row for the dummy spell. GetSpellCooldown then answers
--- nil, every instant would be skip-cached and the bar could never show, so
--- Forever arms the bar only while the client knows the spell (the answer is
--- kept for the session). Every other client keeps the unconditional path.
local function GCDBarSupported()
    if not IS_FOREVER then return true end
    if gcdBarSupported == nil then
        local spellAPI = _G.C_Spell
        local doesSpellExist = spellAPI and spellAPI.DoesSpellExist
        gcdBarSupported = type(doesSpellExist) == "function" and doesSpellExist(GCD_SPELL_ID) == true
    end
    return gcdBarSupported
end

--- PLAYER_REGEN_DISABLED is delivered before InCombatLockdown() turns true, so
--- the combat-entry refresh also reads UnitAffectingCombat("player").
local function PlayerInCombat()
    return InCombatLockdown() or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player")) == true
end

--- A client that cannot fill the bar (no Duration API, or Forever without the
--- GCD spell) never shows the separate bar or its mover, even when an
--- imported profile asks for it.
local function DetachedWanted()
    local g = GeneralDB()
    local spellAPI = _G.C_Spell
    return g ~= nil and g.gcdBarDetached == true and GCDBarSupported()
        and type(spellAPI) == "table" and type(spellAPI.GetSpellCooldownDuration) == "function"
end
local function DetachedVisible()
    local g = GeneralDB()
    return DetachedWanted() and ((detachedPreview and not InCombatLockdown())
        or (IsGCDBarEnabled() and (not g.gcdBarCombatOnly or PlayerInCombat())))
end
local function EnsureDetached()
    if not detachedFrame then
        local frame = PixelLayoutRegion(CreateFrame("Frame", "MSUF_DetachedGCDBar", UIParent))
        frame.unit, frame._msufDetachedGCD = "player", true
        frame:SetFrameStrata("MEDIUM")
        frame:EnableMouse(false)
        local bar = PixelLayoutRegion(CreateFrame("StatusBar", nil, frame))
        bar:SetAllPoints(frame)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetStatusBarColor(.2, .75, 1, 1)
        bar:SetMinMaxValues(0, 1)
        frame.statusBar = bar
        local background = PixelLayoutRegion(bar:CreateTexture(nil, "BACKGROUND"))
        background:SetAllPoints(bar)
        background:SetColorTexture(.05, .05, .05, .8)
        frame.castText = PixelLayoutRegion(bar:CreateFontString(nil, "OVERLAY"))
        frame.castText:SetPoint("LEFT", bar, "LEFT", 3, 0)
        frame.timeText = PixelLayoutRegion(bar:CreateFontString(nil, "OVERLAY"))
        frame.timeText:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
        frame.icon = PixelLayoutRegion(bar:CreateTexture(nil, "ARTWORK"))
        frame.icon:SetPoint("RIGHT", bar, "LEFT", -2, 0)
        frame.icon:SetTexCoord(.07, .93, .07, .93)
        frame:Hide()
        detachedFrame = frame
    end
    return detachedFrame
end
--- Geometry, opacity and fonts follow the settings, not the GCD: only the
--- settings, profile and Edit Mode paths pass layout = true.
local function LayoutDetached(frame, g)
    local height = math.max(4, math.min(50, tonumber(g.gcdBarHeight) or 12))
    frame:SetSize(math.max(40, math.min(600, tonumber(g.gcdBarWidth) or 180)), height)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", tonumber(g.gcdBarX) or 0, tonumber(g.gcdBarY) or -180)
    frame:SetAlpha((tonumber(g.gcdBarOpacity) or 100) / 100)
    frame.icon:SetSize(height, height)
    -- The castbars' configured font; the size follows the bar height.
    local font = (type(_G.MSUF_GetFontPath) == "function" and _G.MSUF_GetFontPath()) or _G.STANDARD_TEXT_FONT
    local flags = (type(_G.MSUF_GetFontFlags) == "function" and _G.MSUF_GetFontFlags()) or "OUTLINE"
    local size = math.min(12, math.max(8, height - 2))
    frame.castText:SetFont(font, size, flags)
    frame.timeText:SetFont(font, size, flags)
    frame._msufIdleState = nil
    frame._msufLaidOut = true
end
--- A finished GCD leaves the bar bound to its expired duration (ClearTimer
--- only drops the runtime's bookkeeping), which keeps the fill at its end.
--- Rebind an empty duration so the idle background shows an empty bar.
local function BindIdleDuration(statusBar)
    if not idleDuration then
        local durationUtil = _G.C_DurationUtil
        if not (durationUtil and durationUtil.CreateDuration) then return end
        idleDuration = durationUtil.CreateDuration()
    end
    if not statusBar.SetTimerDuration then return end
    idleDuration:Reset()
    statusBar:SetTimerDuration(idleDuration)
end
RefreshDetached = function(layout)
    local g = GeneralDB()
    if not g then return end
    if not DetachedWanted() then if detachedFrame then detachedFrame:Hide() end; return end
    local frame = EnsureDetached()
    if layout == true or not frame._msufLaidOut then LayoutDetached(frame, g) end
    local active = frame._msufGCDActive == true
    local iconShown = g.showGCDBarSpell ~= false and (active or detachedPreview == true)
    if frame.icon:IsShown() ~= iconShown then frame.icon:SetShown(iconShown) end
    if active then
        frame._msufIdleState = nil
    else
        -- Idle texts and the preview sample are written once per state.
        local idleState = "idle"
        if detachedPreview then
            idleState = (g.showGCDBarSpell ~= false and "spell" or "") .. (g.showGCDBarTime ~= false and "+time" or "")
        end
        if frame._msufIdleState ~= idleState then
            frame._msufIdleState = idleState
            frame.statusBar:SetValue(detachedPreview and .65 or 0)
            frame.castText:SetText(detachedPreview and g.showGCDBarSpell ~= false and "GCD" or "")
            frame.timeText:SetText(detachedPreview and g.showGCDBarTime ~= false and "0.8" or "")
            if detachedPreview then frame.icon:SetTexture(136243) end
        end
    end
    local shown = DetachedVisible() and (active or detachedPreview or g.gcdBarIdle == true) and true or false
    if frame:IsShown() ~= shown then frame:SetShown(shown) end
end
-- The shared edit bridge owns dragging, nudging and history. Keep dimensions in
-- the captured state so its popup controls also participate in undo/discard.
local function DetachedPosition()
    local g = GeneralDB() or {}
    return { x = g.gcdBarX or 0, y = g.gcdBarY or -180,
        width = g.gcdBarWidth or 180, height = g.gcdBarHeight or 12 }
end
local function SetDetachedPosition(position)
    local g = GeneralDB()
    if not g or InCombatLockdown() then return false end
    g.gcdBarX, g.gcdBarY = position.x, position.y
    if position.width then g.gcdBarWidth = position.width end
    if position.height then g.gcdBarHeight = position.height end
    RefreshDetached(true)
    return true
end
local function Text(label) return ns.Translate and ns.Translate(label) or label end
local function DimensionControl(id, label, key, default, min, max)
    return { id = id, label = Text(label), kind = "number", min = min, max = max, step = 1,
        get = function() local g = GeneralDB(); return g and g[key] or default end,
        set = function(value)
            local g = GeneralDB()
            if not g or InCombatLockdown() then return false end
            g[key] = math.max(min, math.min(max, value))
            RefreshDetached(true)
            return true
        end }
end
RegisterDetachedMover = function()
    local api = _G.MSUF_EditModeAPI
    if not api or not api.RegisterElement or not DetachedWanted() or detachedFrame and detachedFrame._moverRegistered then return end
    EnsureDetached()
    detachedFrame._moverRegistered = api.RegisterElement("MSUF.GCD", {
        id = "bar", label = Text("GCD Bar"), group = Text("Castbars"), order = 115,
        getFrame = function() return detachedFrame end,
        -- Placement stays editable while the master toggle or combat-only rule
        -- keeps the real bar hidden; entering Edit Mode never enables gameplay.
        isEnabled = DetachedWanted,
        getPosition = DetachedPosition, setPosition = SetDetachedPosition,
        captureState = DetachedPosition, restoreState = SetDetachedPosition,
        resetPosition = function() return SetDetachedPosition({ x = 0, y = -180, width = 180, height = 12 }) end,
        extraControls = {
            DimensionControl("width", "Width", "gcdBarWidth", 180, 40, 600),
            DimensionControl("height", "Height", "gcdBarHeight", 12, 4, 50),
        },
        onSessionChanged = function(enabled)
            if enabled and activeFrame then FinishGCDBar(activeFrame) end
            detachedPreview = enabled
            RefreshDetached(true)
        end,
    }) == true
end

-- ============================================================
-- Static spell metadata cache (name/icon for instants, skip set)
-- ============================================================
--- Once a spellID is known to never produce a GCD bar (hard-cast or off-GCD)
--- it can not change mid-session: one table lookup replaces every API call.
local spellSkip = {}
local spellNames = {}
local spellIcons = {}

-- MSUF_CastbarUtils.lua loads first and owns the shared scalar unwrapper.
local PlainNumber = _G.MSUF_Castbar_PlainNumber

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

FinishGCDBar = function(frame)
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
    if frame._msufDetachedGCD then BindIdleDuration(frame.statusBar) end

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

    if frame._msufDetachedGCD then RefreshDetached() else frame:Hide() end
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
    local frame = activeFrame
    if not frame then return end
    frame._msufGCDTimer = nil
    FinishGCDBar(frame)
end

local function OnPollTicker()
    local frame = activeFrame
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
    if activeFrame and activeFrame ~= frame then FinishGCDBar(activeFrame) end
    activeFrame = frame
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
    if not frame._msufDetachedGCD and type(updateColor) == "function" then
        updateColor(frame)
    end

    if frame.latencyBar then
        frame.latencyBar:Hide()
    end

    if frame._msufDetachedGCD then RefreshDetached() else frame:Show() end
    ArmFinish(frame, stable)
end

-- ============================================================
-- Driver: UNIT_SPELLCAST_SUCCEEDED -> GCD bar
-- ============================================================
local driver = PixelLayoutRegion(CreateFrame("Frame", "MSUF_GCDBarDriver"))
local succeededRegistered = false

local function SyncRegistration()
    RefreshDetached(true)
    RegisterDetachedMover()
    local api = _G.MSUF_EditModeAPI
    if detachedFrame and detachedFrame._moverRegistered and api and api.RefreshElement then
        api.RefreshElement("MSUF.GCD", "bar")
    end
    local want = IsGCDBarEnabled() and GCDBarSupported()
    local g = GeneralDB()
    if want and DetachedWanted() and g.gcdBarCombatOnly then
        driver:RegisterEvent("PLAYER_REGEN_DISABLED")
        driver:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        driver:UnregisterEvent("PLAYER_REGEN_DISABLED")
        driver:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
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

    spellID = PlainNumber(spellID)
    if not spellID or spellSkip[spellID] then return end

    local detached = DetachedWanted()
    if detached and (detachedPreview or not DetachedVisible()) then return end
    local frame = detached and EnsureDetached() or _G.MSUF_PlayerCastbar
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
    if not detached and type(isCastbarEnabled) == "function" and not isCastbarEnabled("player") then
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
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then RefreshDetached(); return end
    OnSucceeded(spellID)
end)
--- Kept registered permanently: fires once per loading screen and re-syncs the
--- SUCCEEDED registration after login-time profile binding.
driver:RegisterEvent("PLAYER_ENTERING_WORLD")

-- ============================================================
-- Public API (menu + castbar apply pipeline)
-- ============================================================
local ExportPublic = ns.ExportPublic

ExportPublic("MSUF_IsGCDBarEnabled", IsGCDBarEnabled)
ExportPublic("MSUF_GCDBar_IsSupported", GCDBarSupported)
ExportPublic("MSUF_GCDBar_SyncRegistration", SyncRegistration)
ExportPublic("MSUF_GCDBar_RefreshLayout", function()
    if activeFrame then FinishGCDBar(activeFrame) end
    SyncRegistration()
end)

ExportPublic("MSUF_SetGCDBarEnabled", function(enabled)
    local g = GeneralDB()
    if g then
        g.showGCDBar = (enabled == true)
    end
    SyncRegistration()
    if not enabled then
        FinishGCDBar(activeFrame)
        RefreshDetached()
    end
end)
