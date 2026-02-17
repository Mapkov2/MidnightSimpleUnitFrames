-- MSUF_Castbars.lua

local addonName, ns = ...

-- P2 Fix #10: Cache MSUF_FastCall as local upvalue (avoids _G lookup on every call).
local MSUF_FastCall = MSUF_FastCall or function(...) return pcall(...) end

-- Phase 1A: Use shared _G.MSUF_EnsureDBLazy (defined in Utils, loaded earlier in TOC).
local _EnsureDBLazy = _G.MSUF_EnsureDBLazy or function()
    if not MSUF_DB and type(EnsureDB) == "function" then EnsureDB() end
end

-- Midnight/Beta: some sub-addons run in isolated environments.
-- Ensure the texture getter exists in THIS addon environment.
if type(MSUF_GetCastbarTexture) ~= "function" then
    local tostring = tostring
    local DEFAULT_TEX = "Interface\\TARGETINGFRAME\\UI-StatusBar"
    local texCache = {}

    function MSUF_GetCastbarTexture()
        local db = MSUF_DB
        local g  = db and db.general
        local castKey = g and g.castbarTexture or nil
        local barKey  = g and g.barTexture or nil

        local ck = tostring(castKey or "") .. "|" .. tostring(barKey or "")
        local hit = texCache[ck]
        if hit then return hit end

        local lsm = (ns and ns.LSM) or (LibStub and LibStub("LibSharedMedia-3.0", true))
        local tex

        if castKey and castKey ~= "" and lsm and lsm.Fetch then
            tex = lsm:Fetch("statusbar", castKey)
        end
        if (not tex or tex == "") and barKey and barKey ~= "" and lsm and lsm.Fetch then
            tex = lsm:Fetch("statusbar", barKey)
        end
        if not tex or tex == "" then
            tex = DEFAULT_TEX
        end

-- Midnight/Beta isolated environments: ensure small shared helpers exist in this addon scope.
local ROOT_G = (getfenv and getfenv(0)) or _G

if type(MSUF_SetTextIfChanged) ~= "function" then
    function MSUF_SetTextIfChanged(fs, txt)
        if not fs then return end
        -- Secret-safe: avoid comparing existing text; just set.
        fs:SetText(txt or "")
    end
end

if type(MSUF_SetPointIfChanged) ~= "function" then
    function MSUF_SetPointIfChanged(frame, point, relativeTo, relativePoint, xOfs, yOfs)
        if not frame then return end
        xOfs = xOfs or 0
        yOfs = yOfs or 0

        local snap = _G.MSUF_Snap
        if type(snap) == "function" then
            xOfs = snap(frame, xOfs)
            yOfs = snap(frame, yOfs)
        end

        if frame._msufLastPoint == point and frame._msufLastRel == relativeTo and frame._msufLastRelPoint == relativePoint
           and frame._msufLastX == xOfs and frame._msufLastY == yOfs then
            return
        end

        frame:ClearAllPoints()
        frame:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)

        frame._msufLastPoint = point
        frame._msufLastRel = relativeTo
        frame._msufLastRelPoint = relativePoint
        frame._msufLastX = xOfs
        frame._msufLastY = yOfs
    end
end

-- Export into real globals too (other modules may look there)
ROOT_G.MSUF_SetTextIfChanged = MSUF_SetTextIfChanged
ROOT_G.MSUF_SetPointIfChanged = MSUF_SetPointIfChanged
_G.MSUF_SetTextIfChanged = MSUF_SetTextIfChanged
_G.MSUF_SetPointIfChanged = MSUF_SetPointIfChanged


        texCache[ck] = tex
        return tex
    end
end


-- NOTE:
-- - EnsureDB() and MSUF_DB live in the core addon and are required here.
-- - UnitFrames table is created in MidnightSimpleUnitFrames.lua and exported as _G.MSUF_UnitFrames.
--   This file is intended to load AFTER MidnightSimpleUnitFrames.lua in the TOC.

local UnitFrames = _G.MSUF_UnitFrames

-- Fallback exports: these helpers used to live as local functions in the core file.
-- After refactoring castbars out, they must be available as globals for this module.
-- We define them here only if they are not already provided by the core (safety / load-order robustness).

if not _G.MSUF_IsCastbarEnabledForUnit then
    function _G.MSUF_IsCastbarEnabledForUnit(unit)
        -- P3 Fix #14: Fast-path when DB is already initialized (avoids function-call overhead per event).
        if not MSUF_DB then EnsureDB() end
        local g = (MSUF_DB and MSUF_DB.general) or {}

        if unit == "player" then
            return g.enablePlayerCastbar ~= false
        elseif unit == "target" then
            return g.enableTargetCastbar ~= false
        elseif unit == "focus" then
            return g.enableFocusCastbar ~= false
        end

        return true
    end
end

if not _G.MSUF_IsCastTimeEnabled then
    function _G.MSUF_IsCastTimeEnabled(frame)
        if not frame or not frame.unit then
            return true
        end
        -- P3 Fix #14: Fast-path skip.
        if not MSUF_DB then EnsureDB() end
        local g = MSUF_DB and MSUF_DB.general
        if not g then
            return true
        end

        local u = frame.unit
        if u == "player" then
            return g.showPlayerCastTime ~= false
        elseif u == "target" then
            return g.showTargetCastTime ~= false
        elseif u == "focus" then
            return g.showFocusCastTime ~= false
        end
        return true
    end
end


-- Empower stage blink helpers (used by empowered castbar stage tick flash).
-- Important: must exist even if the CastbarManager already exists (load-order / merge safety).
if not _G.MSUF_IsEmpowerStageBlinkEnabled then
    function _G.MSUF_IsEmpowerStageBlinkEnabled()
        -- P3 Fix #14: Fast-path skip.
        if not MSUF_DB and type(EnsureDB) == "function" then EnsureDB() end
        local g = MSUF_DB and MSUF_DB.general
        -- default ON (unless explicitly disabled)
        return (not g) or (g.empowerStageBlink ~= false)
    end
end

if not _G.MSUF_GetEmpowerStageBlinkTime then
    function _G.MSUF_GetEmpowerStageBlinkTime()
        -- P3 Fix #14: Fast-path skip.
        if not MSUF_DB and type(EnsureDB) == "function" then EnsureDB() end
        local g = (MSUF_DB and MSUF_DB.general) or {}
        local v = tonumber(g.empowerStageBlinkTime)
        if not v then v = 0.14 end
        if v < 0.05 then v = 0.05 end
        if v > 1.00 then v = 1.00 end
        return v
    end
end

local MSUF_GetAnchorFrame = _G.MSUF_GetAnchorFrame



-- =========================================================================
-- Phase 1-5 extractions: The following systems have been moved to separate files.
-- All functions are available via _G (set by earlier TOC files).
-- =========================================================================

-- Phase 1: Empower  Castbars/MSUF_CastbarEmpower.lua
-- Phase 3: Channel Ticks Castbars/MSUF_CastbarChannelTicks.lua
-- Phase 4: Anchors Castbars/MSUF_CastbarAnchors.lua
-- Phase 5: Player Runtime Castbars/MSUF_PlayerCastbarRuntime.lua
-- Phase 2: Previews/TestMode Castbars/MSUF_CastbarPreviews.lua

-- Local aliases for cross-file functions (all set by earlier TOC files)
local MSUF_PlayerCastbar_Cast                    = _G.MSUF_PlayerCastbar_Cast
local MSUF_PlayerCastbar_OnEvent                 = _G.MSUF_PlayerCastbar_OnEvent
local MSUF_PlayerCastbar_UpdateLatencyZone       = _G.MSUF_PlayerCastbar_UpdateLatencyZone
local MSUF_LayoutEmpowerTicks                    = _G.MSUF_LayoutEmpowerTicks
local MSUF_BlinkEmpowerTick                      = _G.MSUF_BlinkEmpowerTick
local MSUF_IsEmpowerStageBlinkEnabled            = _G.MSUF_IsEmpowerStageBlinkEnabled
local MSUF_PlayerChannelHasteMarkers_Update      = _G.MSUF_PlayerChannelHasteMarkers_Update
local MSUF_ReanchorPlayerCastBar                 = _G.MSUF_ReanchorPlayerCastBar
local MSUF_GetPlayerCastbarDesiredSize           = _G.MSUF_GetPlayerCastbarDesiredSize
local MSUF_ApplyPlayerCastbarSizeAndLayout       = _G.MSUF_ApplyPlayerCastbarSizeAndLayout
local MSUF_PositionPlayerCastbarPreview          = _G.MSUF_PositionPlayerCastbarPreview
local MSUF_PositionTargetCastbarPreview          = _G.MSUF_PositionTargetCastbarPreview
local MSUF_PositionFocusCastbarPreview           = _G.MSUF_PositionFocusCastbarPreview
local MSUF_SetupBossCastbarPreviewEditMode       = _G.MSUF_SetupBossCastbarPreviewEditMode
-- NOTE: MSUF_RegisterCastbar / MSUF_UnregisterCastbar are defined IN this file
-- (inside the bootstrap do-block below). No local alias here â€” they must write to _G.
local MSUF_CreatePlayerCastbarPreview            = _G.MSUF_CreatePlayerCastbarPreview
local MSUF_CreateTargetCastbarPreview            = _G.MSUF_CreateTargetCastbarPreview
local MSUF_CreateFocusCastbarPreview             = _G.MSUF_CreateFocusCastbarPreview

function MSUF_InitSafePlayerCastbar()
    if not MSUF_PlayerCastbar then
        local frame = CreateFrame("Frame", "MSUF_PlayerCastBar", UIParent)
        frame:SetClampedToScreen(true)
        MSUF_PlayerCastbar = frame
        frame.unit = "player"

        local height = 18
        frame:SetSize(200, height) -- Breite wird in Reanchor gesetzt

        local background = frame:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(frame)
        background:SetColorTexture(0, 0, 0, 1)
        frame.background = background

        local icon = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        icon:SetSize(height, height)
        icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
        frame.icon = icon

        local statusBar = CreateFrame("StatusBar", nil, frame)
        statusBar:SetPoint("LEFT", icon, "RIGHT", 0, 0)
        statusBar:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        -- Pixel-perfect: avoid internal -2 height padding (causes a visible 1px line when outline thickness is 0)
    statusBar:SetPoint("TOP", frame, "TOP", 0, 0)
    statusBar:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)

        local texture = MSUF_GetCastbarTexture()
        statusBar:SetStatusBarTexture(texture)
        statusBar:GetStatusBarTexture():SetHorizTile(true)
        frame.statusBar = statusBar

        local backgroundBar = frame:CreateTexture(nil, "ARTWORK")
        backgroundBar:SetPoint("TOPLEFT", statusBar, "TOPLEFT", 0, 0)
        backgroundBar:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
        local bgTex = texture
        if type(_G.MSUF_GetCastbarBackgroundTexture) == "function" then
            local t = _G.MSUF_GetCastbarBackgroundTexture()
            if t and t ~= "" then
                bgTex = t
            end
        end
        backgroundBar:SetTexture(bgTex)
        backgroundBar:SetVertexColor(0.176, 0.176, 0.176, 1)
        frame.backgroundBar = backgroundBar

        local castText = statusBar:CreateFontString(nil, "OVERLAY")
        local fontPath, fontSize, fontFlags = GameFontHighlight:GetFont()
        castText:SetFont(fontPath, fontSize, fontFlags)
        castText:SetPoint("LEFT", statusBar, "LEFT", 2, 0)
        frame.castText = castText

        EnsureDB()
        local g = MSUF_DB.general
        local timeX = g.castbarPlayerTimeOffsetX or -2
        local timeY = g.castbarPlayerTimeOffsetY or 0

        local timeText = statusBar:CreateFontString(nil, "OVERLAY")
        local latencyBar = statusBar:CreateTexture(nil, "OVERLAY")
        latencyBar:SetColorTexture(1, 0, 0, 0.25) -- rot, halbtransparent
        latencyBar:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT", 0, 0)
        latencyBar:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
        latencyBar:SetWidth(0)
        latencyBar:Hide()
        frame.latencyBar = latencyBar

        if not frame.MSUF_latencyHooked and frame.HookScript then
            frame:HookScript("OnSizeChanged", function(f)
                if f and f.latencyBar and f.MSUF_latencyLastDurSec and f.MSUF_latencyLastDurSec > 0 then
                    MSUF_PlayerCastbar_UpdateLatencyZone(f, f.MSUF_latencyLastIsChanneled, f.MSUF_latencyLastDurSec)
                end
            end)
            frame.MSUF_latencyHooked = true
        end
        timeText:SetFont(fontPath, fontSize, fontFlags)
        timeText:SetPoint("RIGHT", statusBar, "RIGHT", timeX, timeY)
        timeText:SetJustifyH("RIGHT")
        timeText:SetText("")
        frame.timeText = timeText

    if _G.MSUF_ApplyCastbarOutline then _G.MSUF_ApplyCastbarOutline(frame, true) end
        frame.empowerStageTicks = frame.empowerStageTicks or {}
        local numStages = 5      -- oder 4, je nach Taste; wir machen es erst mal generisch
        local barHeight = height -- height ist oben in der Funktion definiert

        for i = 1, numStages - 1 do
            local tick = frame.empowerStageTicks[i]
            if not tick then
                tick = statusBar:CreateTexture(nil, "OVERLAY")
                tick:SetColorTexture(1, 1, 1, 0.8) -- dÃƒÂ¼nne helle Linie
                frame.empowerStageTicks[i] = tick
            end

            tick:SetSize(3, barHeight)  -- 2 px breit, volle HÃƒÂ¶he
            tick:Hide()                 -- Standard: versteckt, nur bei Empower sichtbar
        end

        frame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP",  "player")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")

                frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player", "vehicle")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player", "vehicle")

        frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player", "vehicle")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player", "vehicle")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player", "vehicle")

        frame:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player", "vehicle")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "player", "vehicle")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "player", "vehicle")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player", "vehicle")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "vehicle")

        frame:RegisterEvent("PLAYER_ENTERING_WORLD")

        frame:SetScript("OnEvent", MSUF_PlayerCastbar_OnEvent)
        frame:Hide()
    end
        C_Timer.After(0, function()
            if not MSUF_PlayerCastbar or not MSUF_PlayerCastbar_Cast then return end
            local castName = UnitCastingInfo("player")
            local chanName = UnitChannelInfo("player")
            if not (castName or chanName) and type(UnitHasVehicleUI) == "function" and UnitHasVehicleUI("player") and type(UnitExists) == "function" and UnitExists("vehicle") then
                castName = UnitCastingInfo("vehicle")
                chanName = UnitChannelInfo("vehicle")
            end
            if castName or chanName then
                MSUF_PlayerCastbar_Cast(MSUF_PlayerCastbar)
            end
        end)
end



do
    -- Prefer existing helper, but keep a safe fallback.
    local ToPlain = MSUF_ToPlainNumber
    if type(ToPlain) ~= "function" then
        ToPlain = function(x)
            if x == nil then return nil end
            local t = type(x)
            if t == "number" then
                -- IMPORTANT: Duration/Timer APIs can return 'secret numbers' in Midnight/Beta.
                -- Converting through string strips the secret-tag so comparisons/arithmetic are safe.
                local s = tostring(x)
                return tonumber(s)
            end
            if t == "string" then
                return tonumber(x)
            end
            local s = tostring(x)
            return tonumber(s)
        end
    end

    -- Quick Win #5: Dedup wrapper for MSUF_SetCastTimeText.
    -- Avoids string.format + SetText when the displayed decimal (0.1s resolution) hasn't changed.
    -- The per-frame field `_msufLastTimeDecimal` stores floor(rem * 10) from the last update.
    local _floor = math.floor
    local function MSUF_SetCastTimeText_Dedup(frame, rem)
        if not frame or not frame.timeText then return end
        local dec = _floor((rem or 0) * 10)
        if dec == frame._msufLastTimeDecimal then return end
        frame._msufLastTimeDecimal = dec
        MSUF_SetCastTimeText(frame, rem)
    end


    _G.MSUF__castbarStyleGlobalRev = _G.MSUF__castbarStyleGlobalRev or 1
    _G.MSUF_CastbarStyleRev = _G.MSUF__castbarStyleGlobalRev
    -- P1 Fix #6: local upvalue for fast per-tick style-rev comparison (avoids _G lookup per tick).
    local _styleRevLocal = _G.MSUF__castbarStyleGlobalRev

    -- Upvalue for castTime rev (avoids _G.MSUF__castTimeGlobalRev lookup per tick).
    local _castTimeRevLocal = _G.MSUF__castTimeGlobalRev or 1

    -- PERF: Resolve time source once at load (avoids conditional per frame).
    local _Now = GetTimePreciseSec or GetTime

    -- PERF: Cache hot-path function refs as upvalues (avoids type(_G.xxx)=="function" per tick).
    local _GlowFade = _G.MSUF_ApplyCastbarGlowFade
    local _GlowReset = _G.MSUF_ResetCastbarGlowFade
    local _IsGCDEnabled = _G.MSUF_IsGCDBarEnabled
    local _GCDStop = _G.MSUF_PlayerGCDBar_Stop
    local _GCDSubOpts = _G.MSUF_GCD_GetSubOptions
    local _RefreshStyleCache = _G.MSUF_RefreshCastbarStyleCache

    -- Deferred re-cache after all files loaded (handles load-order where globals aren't set yet).
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            _GlowFade = _G.MSUF_ApplyCastbarGlowFade or _GlowFade
            _GlowReset = _G.MSUF_ResetCastbarGlowFade or _GlowReset
            _IsGCDEnabled = _G.MSUF_IsGCDBarEnabled or _IsGCDEnabled
            _GCDStop = _G.MSUF_PlayerGCDBar_Stop or _GCDStop
            _GCDSubOpts = _G.MSUF_GCD_GetSubOptions or _GCDSubOpts
            _RefreshStyleCache = _G.MSUF_RefreshCastbarStyleCache or _RefreshStyleCache
        end)
    end
    function _G.MSUF_BumpCastbarStyleRev()
        _G.MSUF__castbarStyleGlobalRev = (_G.MSUF__castbarStyleGlobalRev or 1) + 1
        _G.MSUF_CastbarStyleRev = _G.MSUF__castbarStyleGlobalRev
        _styleRevLocal = _G.MSUF__castbarStyleGlobalRev
    end
    local function MSUF_TryHookCastbarVisualsForStyleRev()
        if _G.MSUF__castbarStyleHooked then return end
        local fn = _G.MSUF_UpdateCastbarVisuals
        if type(fn) ~= "function" then return end

        _G.MSUF__castbarStyleHooked = true
        _G.MSUF_UpdateCastbarVisuals = function(...)
            _G.MSUF_BumpCastbarStyleRev()
            return fn(...)
        end
    end

    -- Try immediately and once more on the next frame (load order safety).
    MSUF_TryHookCastbarVisualsForStyleRev()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, MSUF_TryHookCastbarVisualsForStyleRev)
    end

    local function EnsureCastbarStyleCache(frame, force)
        if not frame then return end
        local refresh = _G.MSUF_RefreshCastbarStyleCache
        if type(refresh) ~= "function" then return end

        local rev = _G.MSUF__castbarStyleGlobalRev or 1
        if force or frame._msufCastbarStyleRev ~= rev then
            refresh(frame)
            frame._msufCastbarStyleRev = rev
        end
    end

    _G.MSUF__castTimeGlobalRev = _G.MSUF__castTimeGlobalRev or 1
    function _G.MSUF_BumpCastTimeRev()
        _G.MSUF__castTimeGlobalRev = (_G.MSUF__castTimeGlobalRev or 1) + 1
        _castTimeRevLocal = _G.MSUF__castTimeGlobalRev
    end

    local function RefreshCastTimeCache(frame)
        if not frame or not frame.unit then
            return true
        end

        local g = MSUF_DB and MSUF_DB.general
        if not g then
            frame._msufCastTimeEnabled = true
            return true
        end

        local u = frame.unit
        local enabled = true
        if u == "player" then
            enabled = (g.showPlayerCastTime ~= false)
        elseif u == "target" then
            enabled = (g.showTargetCastTime ~= false)
        elseif u == "focus" then
            enabled = (g.showFocusCastTime ~= false)
        end

        frame._msufCastTimeEnabled = enabled and true or false
        return frame._msufCastTimeEnabled
    end

    local function EnsureCastTimeCache(frame, force)
        if not frame or not frame.unit then
            return true
        end

        local rev = _G.MSUF__castTimeGlobalRev or 1
        if force or frame._msufCastTimeRev ~= rev or frame._msufCastTimeEnabled == nil then
            RefreshCastTimeCache(frame)
            frame._msufCastTimeRev = rev
        end
        return frame._msufCastTimeEnabled ~= false
    end

    -- Override to use the cached fast-path (same behavior; far fewer calls/DB touches).
    _G.MSUF_IsCastTimeEnabled = function(frame)
        return EnsureCastTimeCache(frame, false)
    end

    -- If visuals updater exists, bump our cast-time rev when options change.
    if _G.MSUF_UpdateCastbarVisuals and not _G.__MSUF_CastTimeRevHooked then
        _G.__MSUF_CastTimeRevHooked = true
        local orig = _G.MSUF_UpdateCastbarVisuals
        _G.MSUF_UpdateCastbarVisuals = function(...)
            _G.MSUF_BumpCastTimeRev()
            local ret = orig(...)
            if type(_G.MSUF_ReanchorPlayerCastBar) == "function" then
                _G.MSUF_ReanchorPlayerCastBar()
            end
            if _G.MSUF_ApplyCastbarOutlineToAll then
                _G.MSUF_ApplyCastbarOutlineToAll(false)
            end
            return ret
        end
    end

    -- Replace manager with a tick-gated implementation (near-zero idle, even in combat).
    local oldManager = MSUF_CastbarManager
    if oldManager then
        if oldManager.SetScript then oldManager:SetScript("OnUpdate", nil) end
        if oldManager.Hide then oldManager:Hide() end
        if oldManager.active then wipe(oldManager.active) end
    end
    local manager = CreateFrame("Frame")
    manager.active = {}
    manager:Hide()

    -- Fix 5: Cache heavy-path function as upvalue (deferred for load-order safety).
    local _HeavyUpdate = nil
    C_Timer.After(0, function()
        _HeavyUpdate = _G.MSUF_UpdateCastbarFrame
    end)

    -- Active bar count — replaces `not next(active)` hash lookups.
    local activeCount = 0

    -- Monotonic clock accumulated from engine elapsed — avoids GetTimePreciseSec in heavy path.
    local _monoClock = 0

    local function ManagerOnUpdate(self, elapsed)
        local active = self.active

        _monoClock = _monoClock + elapsed

        local frame = next(active)
        while frame do
            local nextFrame = next(active, frame)

            -- oUF-style fast path: remaining -= elapsed, inline dedup, single-flag gate.
            -- _msufFastText guarantees: timeText exists, castTime enabled, NOT gcd, NOT empower.
            local rem = frame._msufRemaining
            if frame._msufFastText and rem then
                rem = rem - elapsed
                if rem < 0 then rem = 0 end
                frame._msufRemaining = rem

                -- Fast-path completion: cast done — immediately cleanup.
                -- Eliminates ~6 wasted ticks waiting for heavy path to notice.
                if rem <= 0.001 then
                    if frame.SetSucceeded then
                        frame:SetSucceeded()
                    else
                        frame:Hide()
                    end
                    -- OnHide hook will unregister; skip to next bar.
                else
                    local dec = _floor(rem * 10)
                    if dec ~= frame._msufLastTimeDecimal then
                        frame._msufLastTimeDecimal = dec
                        frame.timeText:SetFormattedText("%.1f", rem)
                    end

                    -- Heavy path: only needed for CHANNELS (hard-stop safety + haste markers).
                    -- Non-channeled casts: fast path handles completion + time text fully.
                    -- GlowFade inlined here — avoids entering the expensive heavy path just for cosmetics.
                    if frame.MSUF_isChanneled then
                        if rem < 1.0 then
                            local cd = frame._msufHeavyIn
                            if cd then
                                cd = cd - elapsed
                            else
                                cd = 0
                            end
                            if cd <= 0 then
                                cd = frame._msufTickInterval or 0.10
                                local fn = _HeavyUpdate or _G.MSUF_UpdateCastbarFrame
                                if fn then fn(frame, elapsed, nil, _monoClock) end
                            end
                            frame._msufHeavyIn = cd
                        end
                    elseif _GlowFade then
                        -- Inline GlowFade for non-channels (uses cached total from driver).
                        local totalNum = frame._msufPlainTotal
                        if totalNum and totalNum > 0 then
                            _GlowFade(frame, rem, totalNum)
                        end
                    end
                end
            else
                -- Non-fast bars (GCD, empower, no timeText, no remaining):
                -- always need heavy path — it drives everything.
                local cd = frame._msufHeavyIn
                if cd then
                    cd = cd - elapsed
                else
                    cd = 0
                end
                if cd <= 0 then
                    cd = frame._msufTickInterval or 0.10
                    local fn = _HeavyUpdate or _G.MSUF_UpdateCastbarFrame
                    if fn then fn(frame, elapsed, nil, _monoClock) end
                end
                frame._msufHeavyIn = cd
            end

            frame = nextFrame
        end
    end

    -- OnUpdate is toggled via OnShow/OnHide — guarantees zero idle CPU.
    manager:SetScript("OnShow", function(self)
        self:SetScript("OnUpdate", ManagerOnUpdate)
    end)
    manager:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- Export as the canonical manager so existing code paths use it.
    MSUF_CastbarManager = manager

    function MSUF_RegisterCastbar(frame)
        if not frame or not frame.statusBar then return end
        if not MSUF_CastbarManager or not MSUF_CastbarManager.active then return end

        -- Empower bars drive SetValue() directly (not C-side animated), so they need ~33Hz for smooth fill.
        -- Always re-evaluate when empower state changes (a frame may switch between normal and empower).
        if frame.isEmpower then
            frame._msufTickInterval = 0.03  -- ~33Hz for smooth empower bar fill
        elseif frame._msufTickInterval == nil or frame._msufTickInterval < 0.10 then
            frame._msufTickInterval = 0.10
        end
        frame._msufHeavyIn = 0  -- fire immediately on first tick

        EnsureCastTimeCache(frame, true)

        -- Opt 5: Single-flag fast-path gate (replaces 4 field reads + 4 compares per tick).
        -- true = this bar gets the lightweight time-text fast path.
        -- GCD and empower bars are driven entirely by the heavy path.
        frame._msufFastText = (frame.timeText and frame._msufCastTimeEnabled ~= false
                               and not frame.MSUF_gcdActive and not frame.isEmpower) or false

        -- Opt 1: Init remaining from snapshot (oUF-style `remaining -= dt` per tick).
        local endT = frame._msufPlainEndTime
        if endT then
            local rem = endT - (_Now or GetTimePreciseSec)()
            frame._msufRemaining = (rem > 0) and rem or 0
        end

        -- Only add to active set if not already present.
        if not MSUF_CastbarManager.active[frame] then
            activeCount = activeCount + 1
            MSUF_CastbarManager.active[frame] = true
        end

        -- Quartz pattern: OnHide auto-unregister (eliminates IsShown() C-call from tick).
        -- Hook once per frame lifetime.
        if not frame._msufOnHideHooked then
            frame._msufOnHideHooked = true
            frame:HookScript("OnHide", function(self)
                if self._msufInUnregister then return end
                if MSUF_UnregisterCastbar then
                    MSUF_UnregisterCastbar(self)
                end
            end)
        end

        MSUF_CastbarManager:Show()
    end

    function MSUF_UnregisterCastbar(frame)
        if not frame then return end
        if not MSUF_CastbarManager or not MSUF_CastbarManager.active then return end

        -- Guard against re-entrant OnHide hook.
        frame._msufInUnregister = true

        -- Restore base color if the optional end-of-cast fade was active.
        if _GlowReset then
            _GlowReset(frame)
        end

        if MSUF_CastbarManager.active[frame] then
            MSUF_CastbarManager.active[frame] = nil
            activeCount = activeCount - 1
            if activeCount < 0 then activeCount = 0 end
        end

        frame._msufNextTick = nil
        frame._msufHeavyIn = nil
        frame._msufHardStopNext = nil
        frame._msufZeroCount = nil
        frame._msufLastTimeDecimal = nil
        frame._msufFastText = nil
        frame._msufRemaining = nil
        frame._msufCastTimeWasEnabled = nil

        frame._msufInUnregister = nil

        if activeCount == 0 then
            MSUF_CastbarManager:Hide()
        end
    end

    -- Secret-safe + cached update: time text and empower stage handling. StatusBar:SetTimerDuration animates the bar.
    -- `monoClock` = manager's monotonic elapsed accumulator (for relative timing — no C-call).
    -- `now` = wall clock — only computed when API drift correction actually needs it.
    function MSUF_UpdateCastbarFrame(frame, dt, now, monoClock)
        if not frame or not frame.statusBar then
            return
        end

        -- Inline castTime rev check (replaces EnsureCastTimeCache function call per tick).
        local castTimeEnabled = frame._msufCastTimeEnabled
        if castTimeEnabled == nil or frame._msufCastTimeRev ~= _castTimeRevLocal then
            castTimeEnabled = EnsureCastTimeCache(frame, false)
        end
        -- Only blank timeText when it transitions to disabled (not every tick).
        if frame.timeText and not castTimeEnabled and frame._msufCastTimeWasEnabled then
            MSUF_SetTextIfChanged(frame.timeText, "")
        end
        if frame._msufCastTimeWasEnabled ~= castTimeEnabled then
            frame._msufCastTimeWasEnabled = castTimeEnabled
        end

  
        -- P1 Fix #6: Inlined style-rev check (was EnsureCastbarStyleCache function call per tick).
        -- Only calls the heavy refresh when the global style rev bumps (user changed settings).
        if frame._msufCastbarStyleRev ~= _styleRevLocal then
            if _RefreshStyleCache then
                _RefreshStyleCache(frame)
            end
            frame._msufCastbarStyleRev = _styleRevLocal
        end

        -- Use monotonic clock for relative timing (hard-stop, haste markers).
        -- Only compute wall-clock `now` when API drift correction actually needs it.
        local mc = monoClock or 0

        -- GCD bar virtual cast (instant casts): driven by MSUF_CastbarGCD + CastbarManager tick.
        if frame.MSUF_gcdActive then
            if _IsGCDEnabled and not _IsGCDEnabled() then
                if _GCDStop then _GCDStop(frame) end
                return
            end

            -- Real casts/channel/empower always win.
            if frame.isEmpower then
                if _GCDStop then _GCDStop(frame, true) end
                return
            end

            -- Gate real-cast check at 4Hz (was every heavy tick = 10Hz).
            local nxtCastCheck = frame._msufGcdCastCheckNext
            if (not nxtCastCheck) or mc >= nxtCastCheck then
                frame._msufGcdCastCheckNext = mc + 0.25
                local u = frame.MSUF_gcdUnit or frame.unit or "player"
                if UnitCastingInfo(u) or UnitChannelInfo(u) then
                    if _GCDStop then _GCDStop(frame, true) end
                    return
                end
            end

            -- oUF-style elapsed accumulator — eliminates GetTimePreciseSec per tick.
            local dur = frame.MSUF_gcdDur or 0
            if dur <= 0 then
                if _GCDStop then _GCDStop(frame) end
                return
            end

            local elapsed = (frame._msufGcdElapsed or 0) + dt
            if elapsed > dur then elapsed = dur end
            frame._msufGcdElapsed = elapsed

            local rem = dur - elapsed
            if rem <= 0.001 then
                if _GCDStop then _GCDStop(frame) end
                return
            end

            -- Sub-toggles: cache per frame, refresh on rev bump.
            local showTime, showSpell
            local subRev = _castTimeRevLocal
            if frame._msufGcdSubOptsRev == subRev then
                showTime = frame._msufGcdShowTimeCached
                showSpell = frame._msufGcdShowSpellCached
            else
                showTime = true
                showSpell = true
                if _GCDSubOpts then
                    showTime, showSpell = _GCDSubOpts()
                end
                frame._msufGcdShowTimeCached = showTime
                frame._msufGcdShowSpellCached = showSpell
                frame._msufGcdSubOptsRev = subRev
            end
            frame.MSUF_gcdShowTime = showTime
            frame.MSUF_gcdShowSpell = showSpell

            -- SetMinMaxValues only once per GCD (dur is constant for the duration).
            if not frame._msufGcdMinMaxSet then
                frame._msufGcdMinMaxSet = true
                if frame.statusBar.SetMinMaxValues then
                    frame.statusBar:SetMinMaxValues(0, dur)
                end
            end
            -- 12.0: C-engine animates bar via SetTimerDuration → no per-tick SetValue.
            -- Fallback for pre-12.0 or missing API: manual SetValue.
            if not frame._msufGcdTimerDriven then
                if frame.statusBar.SetValue then
                    frame.statusBar:SetValue(elapsed)
                end
            end

            -- Dedup spell name + icon (constant during GCD).
            if frame.castText then
                if showSpell then
                    MSUF_SetTextIfChanged(frame.castText, frame.MSUF_gcdSpellName or "")
                else
                    MSUF_SetTextIfChanged(frame.castText, "")
                end
            end
            if frame.icon then
                local wantTex = (showSpell and frame.MSUF_gcdSpellIcon) or nil
                if frame._msufGcdLastIcon ~= wantTex then
                    frame._msufGcdLastIcon = wantTex
                    if frame.icon.SetTexture then
                        frame.icon:SetTexture(wantTex)
                    end
                end
            end

            if frame.timeText then
                if castTimeEnabled and showTime then
                    MSUF_SetCastTimeText_Dedup(frame, rem)
                else
                    frame._msufLastTimeDecimal = nil
                    MSUF_SetTextIfChanged(frame.timeText, "")
                end
            end

            -- Optional glow fade near completion.
            if _GlowFade then
                _GlowFade(frame, rem, dur)
            end

            return
        end


        -- Empowered casts: update value + time text and stage blink.
        -- IMPORTANT (12.0/Midnight): dt is not reliable for player empower updates (can be 0),
        -- and StatusBar:SetTimerDuration expects a DurationObject and must NOT be mixed with SetValue.
        -- Use the known-good legacy behavior: compute elapsed from wall clock each tick and
        -- drive the statusbar manually with SetValue(elapsed).
        if frame.isEmpower and frame.empowerStartTime and frame.empowerTotalWithGrace then
            -- Cache plain numbers once (first tick after empower start).
            local total = frame._msufEmpowerTotalNum
            if not total then
                total = ToPlain(frame.empowerTotalWithGrace) or 0
                if total > 0 then frame._msufEmpowerTotalNum = total end
            end
            if total <= 0 then total = 0.01 end

            -- Wall-clock driven elapsed (dt can be 0 here).
            if not now then now = (_Now or GetTimePreciseSec)() end
            local startT = frame._msufEmpowerStartNum
            if not startT then
                startT = ToPlain(frame.empowerStartTime) or now
                frame._msufEmpowerStartNum = startT
            end

            local elapsed = now - startT
            if elapsed < 0 then elapsed = 0 end
            if elapsed > total then elapsed = total end
            frame._msufEmpowerElapsed = elapsed

            -- SetMinMaxValues once per empower cast (total is constant), then drive value manually.
            if not frame._msufEmpowerMinMaxSet then
                frame._msufEmpowerMinMaxSet = true
                if frame.statusBar.SetMinMaxValues then
                    frame.statusBar:SetMinMaxValues(0, total)
                end
            end
            if frame.statusBar.SetValue then
                frame.statusBar:SetValue(elapsed)
            end

            -- Compute base once per tick (used for timeText + glowFade).
            local base = frame._msufEmpowerBaseNum
            if not base then
                base = ToPlain(frame.empowerTotalBase) or total
                if base > 0 then frame._msufEmpowerBaseNum = base end
            end
            if base <= 0 then base = total end

            if frame.timeText and castTimeEnabled then
                local rem = base - elapsed
                if rem < 0 then rem = 0 end
                MSUF_SetCastTimeText_Dedup(frame, rem)
            end

            if frame.MSUF_empowerLayoutPending and MSUF_LayoutEmpowerTicks then
                MSUF_LayoutEmpowerTicks(frame)
            end

            if frame.empowerStageEnds and frame.empowerTicks and MSUF_BlinkEmpowerTick then
                if not frame.empowerNextStage then frame.empowerNextStage = 1 end
                -- Cache stage-end plain numbers on first access.
                local stageNums = frame._msufEmpowerStageEndsNum
                while frame.empowerNextStage <= #frame.empowerStageEnds do
                    local idx = frame.empowerNextStage
                    local tEnd = stageNums and stageNums[idx]
                    if not tEnd then
                        local raw = frame.empowerStageEnds[idx]
                        if type(raw) ~= "number" then raw = ToPlain(raw) end
                        tEnd = raw
                        -- Cache for next tick.
                        if tEnd and stageNums then stageNums[idx] = tEnd end
                    end
                    if not tEnd then break end
                    if elapsed >= tEnd then
                        if MSUF_IsEmpowerStageBlinkEnabled and MSUF_IsEmpowerStageBlinkEnabled() then
                            MSUF_BlinkEmpowerTick(frame, idx)
                        end
                        frame.empowerNextStage = idx + 1
                    else
                        break
                    end
                end
            end

            -- "Glow effect": fade towards white as the empower cast approaches completion.
            if _GlowFade and base > 0 then
                local rem = base - elapsed
                if rem < 0 then rem = 0 end
                _GlowFade(frame, rem, base)
            end

            return
        end
        -- Hard-stop safety: only needed for CHANNELED casts (refresh gaps can cause false "no channel").
        -- Non-channeled casts have triple redundancy: fast-path rem<=0, OnHide hook, remNum<=0.001 safety.
        -- Uses monotonic clock (mc) for relative timing — no GetTimePreciseSec needed.
        if frame.MSUF_isChanneled then
            local nxt = frame._msufHardStopNext
            if (not nxt) or (mc >= nxt) then
                frame._msufHardStopNext = mc + 0.15

                local u = frame.unit
                if u and u ~= "" then
                    if UnitChannelInfo(u) then
                        frame._msufHardStopNoChannelSince = nil
                        frame._msufHardStopChanThresh = nil
                    else
                        local t0 = frame._msufHardStopNoChannelSince
                        if not t0 then
                            frame._msufHardStopNoChannelSince = mc
                            -- Channel refresh gaps can be as large as SpellQueueWindow; keep the hard-stop threshold above that.
                            local qms = 0
                            if GetCVar then qms = tonumber(GetCVar("SpellQueueWindow") or "0") or 0 end
                            if qms < 0 then qms = 0 end
                            local thresh = 0.45
                            local q = (qms / 1000) + 0.10
                            if q > thresh then thresh = q end
                            if thresh > 0.80 then thresh = 0.80 end
                            frame._msufHardStopChanThresh = thresh
                        else
                            local thresh = frame._msufHardStopChanThresh or 0.45
                            if (mc - t0) >= thresh then
                                if frame.SetSucceeded then frame:SetSucceeded() else frame:Hide() end
                                return
                            end
                        end
                    end
                end
            end
        end

        -- Duration-object path (modern API): we only maintain time text + safety stop.

        -- Player channel haste markers: low-cadence refresh (no per-frame OnUpdate).
        if frame.unit == "player" and frame.MSUF_isChanneled and frame.MSUF_channelHasteMarkers then
            if mc >= (frame._msufHasteMarkersNext or 0) then
                frame._msufHasteMarkersNext = mc + 0.15
                MSUF_PlayerChannelHasteMarkers_Update(frame, false)
            end
        end

        -- Lazy wall clock: only compute when the API/snapshot path actually needs it.
        if not now then now = (_Now or GetTimePreciseSec)() end

        local dObj = frame.MSUF_durationObj
        if dObj and (dObj.GetRemainingDuration or dObj.GetRemaining) then
            -- If the duration object changed, re-detect timer direction for the statusbar fallback.
            if frame._msufLastDurationObj ~= dObj then
                frame._msufLastDurationObj = dObj
                frame._msufTimerAssumeCountdown = nil
            end

            -- Fix 2: Only read the expensive API + ToPlain when remaining < 1s or no snapshot exists.
            -- When remaining > 1s, drift (max ~100ms at 10Hz) is visually imperceptible.
            local snapEndT = frame._msufPlainEndTime
            local snapRem = snapEndT and (snapEndT - now) or nil
            local needsApiRead = (not snapRem) or (snapRem < 1.0)

            local remNum
            local _fallbackSpan = nil

            if needsApiRead then
                local rem
                if dObj.GetRemainingDuration then
                    rem = dObj:GetRemainingDuration()
                else
                    rem = dObj:GetRemaining()
                end

                remNum = ToPlain(rem)

                -- Midnight/Beta: for non-interruptible casts, Remaining can be a secret value.
                -- If we can't safely coerce it, derive remaining from the animated StatusBar value instead.
                if (not remNum) and frame.statusBar and frame.MSUF_timerDriven then
                    local bar = frame.statusBar
                    local okMM, minV, maxV = pcall(bar.GetMinMaxValues, bar)
                    local okV, val = pcall(bar.GetValue, bar)
                    if okMM and okV then
                        minV = ToPlain(minV) or 0
                        maxV = ToPlain(maxV)
                        val  = ToPlain(val)

                        if maxV and val and maxV > minV then
                            local span = maxV - minV
                            _fallbackSpan = span

                            local assumeCountdown = frame._msufTimerAssumeCountdown
                            if assumeCountdown == nil then
                                local distMin = math.abs(val - minV)
                                local distMax = math.abs(maxV - val)
                                assumeCountdown = (distMax < distMin)
                                frame._msufTimerAssumeCountdown = assumeCountdown
                            end

                            if assumeCountdown then
                                remNum = val - minV
                            else
                                remNum = maxV - val
                            end

                            if remNum < 0 then remNum = 0 end
                            if remNum > span then remNum = span end
                        end
                    end
                end

                -- If we still couldn't read remaining and have no snapshot, show raw value as last resort.
                if not remNum and not snapRem then
                    if frame.timeText and castTimeEnabled and rem ~= nil then
                        local t = ""
                        local okFmt, s = pcall(string.format, "%.1f", rem)
                        if okFmt and s then
                            t = s
                        else
                            t = tostring(rem)
                        end
                        MSUF_SetTextIfChanged(frame.timeText, t)
                        frame._msufZeroCount = nil
                    end
                    return
                end
            else
                -- Remaining > 1s: use snapshot directly, no API call needed.
                remNum = snapRem
            end

            if remNum then
                if remNum < 0 then remNum = 0 end

                -- Re-snapshot only when we actually read from the API (drift correction).
                -- When using snapshot directly (>1s), no need to write back the same value.
                -- Heavy path runs at 10Hz; fast-path at 60fps for smooth time text.
                if needsApiRead then
                    frame._msufPlainEndTime = now + remNum
                    -- Sync oUF-style remaining so fast-path stays accurate after drift correction.
                    frame._msufRemaining = remNum
                end

                -- Time text is handled by the manager fast-path at 60fps via _msufPlainEndTime.
                -- No time text update needed here.

                -- "Glow effect": fade towards white as the cast approaches completion.
                if _GlowFade then
                    -- Use cached total from Cast() snapshot when available (avoids GetTotalDuration + ToPlain).
                    local totalNum = frame._msufPlainTotal
                    if not totalNum then
                        if dObj.GetTotalDuration then
                            totalNum = ToPlain(dObj:GetTotalDuration())
                        end
                    end
                    if (not totalNum) and _fallbackSpan then
                        totalNum = _fallbackSpan
                    end
                    if (not totalNum) and frame.statusBar then
                        local bar = frame.statusBar
                        local okMM, minV, maxV = pcall(bar.GetMinMaxValues, bar)
                        if okMM then
                            minV = ToPlain(minV) or 0
                            maxV = ToPlain(maxV)
                            if maxV and maxV > minV then
                                totalNum = maxV - minV
                            end
                        end
                    end
                    if totalNum and totalNum > 0 then
                        _GlowFade(frame, remNum, totalNum)
                    end
                end

                -- Safety: if events fail, stop updates after completion.
                if remNum <= 0.001 then
                    frame._msufZeroCount = (frame._msufZeroCount or 0) + 1
                    if frame._msufZeroCount >= 2 then
                        frame._msufZeroCount = nil
                        -- If STOP/CHANNEL_STOP was missed, unregistering alone can leave the bar stuck on screen.
                        -- Prefer the driver's cleanup/hide path when available.
                        if frame.SetSucceeded then
                            frame:SetSucceeded()
                        else
                            MSUF_UnregisterCastbar(frame)
                            if frame.Hide then frame:Hide() end
                        end
                    end
                else
                    frame._msufZeroCount = nil
                end
            end

            return
        end

        -- Fallback: compute from stored timestamps if available.
        if frame.endTime then
            local endT = ToPlain(frame.endTime) or 0
            local remNum = endT - now
            if remNum < 0 then remNum = 0 end

            if frame.timeText and castTimeEnabled then
                MSUF_SetCastTimeText_Dedup(frame, remNum)
            end

            -- "Glow effect": fade towards white as the cast approaches completion.
            if _GlowFade and frame.statusBar then
                local bar = frame.statusBar
                local okMM, minV, maxV = pcall(bar.GetMinMaxValues, bar)
                if okMM then
                    minV = ToPlain(minV) or 0
                    maxV = ToPlain(maxV)
                    if maxV and maxV > minV then
                        local totalNum = maxV - minV
                        if totalNum and totalNum > 0 then
                            _GlowFade(frame, remNum, totalNum)
                        end
                    end
                end
            end

            if remNum <= 0.001 then
				-- Same safety as duration-object path: hide the bar if events were missed.
				if frame.SetSucceeded then
					frame:SetSucceeded()
				else
					MSUF_UnregisterCastbar(frame)
					if frame.Hide then frame:Hide() end
				end
            end
        end
    end
end
