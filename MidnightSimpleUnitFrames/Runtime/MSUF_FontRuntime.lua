--- Runtime/MSUF_FontRuntime.lua
--- Runtime font refresh and deferred castbar/font apply wrappers.
--- Shared font application runtime helpers with stable exported globals.
---
--- FontRegistry resolves font keys and catalogues. This file applies the active
--- font/color/shadow settings to existing frames and schedules layout refreshes
--- when font metrics become available after login.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Fonts = MSUF.Fonts or {}

local type, tostring, tonumber, pairs = type, tostring, tonumber, pairs
local _G = _G

local ExportPublic = MSUF.ExportPublic

local EnsureDBSafe = MSUF.Util.EnsureDBSafe

--- REQUIRED: Kernel/MSUF_Util.lua is listed unconditionally in the TOC well
--- ahead of this file and is the only writer of the boss-token helper.
local GetBossIndexFromToken = MSUF.Require("MSUF_GetBossIndexFromToken", "Runtime/MSUF_FontRuntime.lua")

local function NormalizeFontScopeKey(key)
    if key == nil then return nil end
    key = tostring(key)
    if key == "" then return nil end
    if key == "tot" or key == "targetoftarget" then return "targettarget" end
    if key == "focus_target" or key == "focustargettarget" then return "focustarget" end
    if GetBossIndexFromToken(key) then return "boss" end
    return key
end

local function CastbarUnitForFontScope(scope)
    if scope == "player" or scope == "target" or scope == "focus" or scope == "boss" then return scope end
    return nil
end

local UNITFRAME_FONT_ELEMENTS = {
    "Text", "NameText", "HealthText", "PowerText", "InlineToT", "StatusIndicators",
}

local function ApplyScopedFontFollowers(scope, skipCastbars, skipClassPower, skipAuras)
    if scope then
        local castbarUnit = CastbarUnitForFontScope(scope)
        if skipCastbars ~= true and castbarUnit then
            _G.MSUF_ApplyCastbarVisualsForUnit(castbarUnit)
        end
        local a3 = MSUF and MSUF.MSUF_Auras3
        if skipAuras ~= true and a3 and type(a3.ApplyFontsFromGlobal) == "function" then
            a3.ApplyFontsFromGlobal(scope, "FONT_RUNTIME_SCOPE")
        end
        if skipClassPower ~= true and scope == "player" and type(_G.MSUF_ClassPower_Apply) == "function" then
            _G.MSUF_ClassPower_Apply({ fonts = true, playerHP = true })
        end
        return
    end

    if skipCastbars ~= true then _G.MSUF_UpdateCastbarVisuals_Immediate() end
    local a3 = MSUF and MSUF.MSUF_Auras3
    if skipAuras ~= true and a3 and type(a3.ApplyFontsFromGlobal) == "function" then a3.ApplyFontsFromGlobal() end
    if skipClassPower ~= true and _G.MSUF_ClassPower_ApplyFonts then _G.MSUF_ClassPower_ApplyFonts() end
end

--- Font changes affect many elements. Defer the UF dirty commit so global font
--- and per-frame text relayout happen once after a settings burst.

local ScheduleApplyCommit = _G.MSUF_UF_ScheduleApplyCommit

local _MSUF_MatchesApplication = MSUF.Require("MSUF_FontApplicationMatches", "Runtime/MSUF_FontRuntime.lua")
local _MSUF_SetFontCheckedFn = MSUF.Require("MSUF_SetFontChecked", "Runtime/MSUF_FontRuntime.lua")

--- Cold-start font coordinator. Path/size readback may become exact before the
--- selected face's glyph metrics are active, so the first fanout is always
--- provisional. Unready retries touch one hidden FontString; a delayed epoch
--- transition performs one forced final fanout and then leaves no timer active.
local _fontSettle = {
    tuple = nil,
    path = nil,
    generation = 0,
    attempt = 0,
    pending = false,
    active = false,
    forceNext = false,
}
local MSUF_FONT_SETTLE_DELAYS = { 1.0, 0.5, 1.0, 2.0, 4.0, 8.0 }
local _measureFS
local UpdateAllFonts
local _MSUF_ScheduleFontProbe
local _MSUF_RunFontProbe
local _fontRecoveryCombatFrame
local _fontFailureRecoveryPending = false

_G.MSUF_FontApplyEpoch = tonumber(_G.MSUF_FontApplyEpoch) or 0
local function _MSUF_FontCombatLocked()
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true
end

local function _MSUF_ScheduleLateFontRecovery()
    if _fontSettle.active
        or _fontSettle.timedOutTuple == _fontSettle.tuple
        or _fontFailureRecoveryPending
    then
        return
    end
    _fontFailureRecoveryPending = true
    local function RecoverLateFontString()
        _fontFailureRecoveryPending = false
        if not _fontSettle.active
            and _fontSettle.timedOutTuple ~= _fontSettle.tuple
            and type(_G.MSUF_RequestFontRecovery) == "function"
        then
            _G.MSUF_RequestFontRecovery("LATE_FONTSTRING_FAILURE")
        end
    end
    _G.MSUF_ScheduleOnce("FONT_APPLY_FAILURE_RECOVERY", RecoverLateFontString)
end

ExportPublic("MSUF_OnFontApplyFailed", function()
    if _fontSettle.active or _fontSettle.timedOutTuple == _fontSettle.tuple then return end
    _MSUF_ScheduleLateFontRecovery()
end)

local function _MSUF_BumpFontApplyEpoch()
    local epoch = (tonumber(_G.MSUF_FontApplyEpoch) or 0) + 1
    ExportPublic("MSUF_FontApplyEpoch", epoch)
    return epoch
end

local function _MSUF_FontTuple(path, flags, fontKey)
    return tostring(path or ""):gsub("/", "\\"):lower()
        .. "\001" .. tostring(flags or "")
        .. "\001" .. tostring(fontKey or "")
end

local function _MSUF_BeginFontGeneration(path, flags, fontKey, force)
    local tuple = _MSUF_FontTuple(path, flags, fontKey)
    if not force and _fontSettle.tuple == tuple then return false end
    _fontSettle.tuple = tuple
    _fontSettle.path = path
    _fontSettle.generation = _fontSettle.generation + 1
    _fontSettle.attempt = 0
    _fontSettle.pending = false
    _fontSettle.active = true
    _fontSettle.timedOutTuple = nil
    _MSUF_BumpFontApplyEpoch()
    return true
end

local function _MSUF_DeferFontRecoveryAfterCombat(requested)
    if requested then
        _fontSettle.deferredRequest = true
        _fontSettle.deferredProbe = nil
    elseif not _fontSettle.deferredRequest then
        _fontSettle.deferredProbe = true
    end
    if not _fontRecoveryCombatFrame and type(_G.CreateFrame) == "function" then
        local frame = _G.CreateFrame("Frame")
        frame:SetScript("OnEvent", function(self, event)
            if event ~= "PLAYER_REGEN_ENABLED" then return end
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            local runRequest, runProbe = _fontSettle.deferredRequest, _fontSettle.deferredProbe
            _fontSettle.deferredRequest, _fontSettle.deferredProbe = nil, nil
            if runRequest and type(_G.MSUF_RequestFontRecovery) == "function" then
                _G.MSUF_RequestFontRecovery("PLAYER_REGEN_ENABLED")
            elseif runProbe and type(_MSUF_RunFontProbe) == "function" then
                _MSUF_RunFontProbe()
            end
        end)
        _fontRecoveryCombatFrame = frame
    end
    if _fontRecoveryCombatFrame then _fontRecoveryCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED") end
end

local function _ConfiguredFontReady(path)
    path = path or _fontSettle.path
    if type(path) ~= "string" or path == "" then return false end
    if not _measureFS then
        if not _G.UIParent then return true end
        _measureFS = _G.UIParent:CreateFontString(nil, "BACKGROUND")
        _measureFS:Hide()
    end
    if not _MSUF_SetFontCheckedFn(_measureFS, path, 14, "") then return false end
    -- If path or size do not match yet, the client is still publishing
    -- provisional/fallback font metrics.
    if not _MSUF_MatchesApplication(_measureFS, path, 14) then return false end
    _measureFS:SetText("ABCabcgjpqy0123")
    local w = _measureFS:GetStringWidth()
    return type(w) == "number" and w > 0
end

UpdateAllFonts = function(onlyKey, skipUnitFrames, skipCastbars, skipClassPower, skipAuras)
    EnsureDBSafe()
    local g = _G.MSUF_DB.general
    local flags = _G.MSUF_GetFontFlags()
    local path = _G.MSUF_ResolveFontPath(_G.MSUF_GetFontPath(), 14, flags, g.fontKey)
    local forceGeneration = _fontSettle.forceNext == true
    _fontSettle.forceNext = false
    local newFontGeneration = _MSUF_BeginFontGeneration(path, flags, g.fontKey, forceGeneration)
    if newFontGeneration then
        -- Prewarm only; the delayed generation probe must confirm readiness.
        _ConfiguredFontReady(path)
    end
    local getColor = (MSUF and MSUF.MSUF_GetConfiguredFontColor) or _G.MSUF_GetConfiguredFontColor
    local fr, fg, fb = 1, 1, 1
    if type(getColor) == "function" then
        fr, fg, fb = getColor()
    end
    fr, fg, fb = tonumber(fr) or 1, tonumber(fg) or 1, tonumber(fb) or 1

    onlyKey = NormalizeFontScopeKey(onlyKey)

    local pathKey = tostring(path) .. "|" .. tostring(flags) .. "|" .. tostring(fr) .. "|" .. tostring(fg) .. "|" .. tostring(fb)
    if _G.MSUF_FontPathKey ~= pathKey then
        ExportPublic("MSUF_FontPathKey", pathKey)
        ExportPublic("MSUF_FontPathSerial", (_G.MSUF_FontPathSerial or 0) + 1)
    end

    if skipUnitFrames ~= true then
        MSUF.UF.RefreshElements(onlyKey, UNITFRAME_FONT_ELEMENTS, "FONT_RUNTIME")
    end

    -- Group name FontStrings are the source for Auras3 name-color overlays.
    -- Refresh them before Auras3 copies their font during the final fanout.
    if not onlyKey then
        local gf = MSUF and MSUF.GF
        if gf and type(gf.RefreshFonts) == "function" then gf.RefreshFonts() end
    end
    ApplyScopedFontFollowers(onlyKey, skipCastbars, skipClassPower, skipAuras)
    --- Registered font followers outside the unit-frame engine, looked up per
    --- full refresh on purpose: MSCB_ApplyFontsFromMSUF belongs to a separate
    --- companion addon that may load later or not at all, and
    --- MSUF_FocusKick_ApplyTimeTextFont is exported by
    --- Castbars/MSUF_FocusKickIcon.lua, which loads after this file.
    if not onlyKey then
        if MSUF and MSUF.MSUF_ApplyGameplayFontFromGlobal then MSUF.MSUF_ApplyGameplayFontFromGlobal() end
        if type(_G.MSCB_ApplyFontsFromMSUF) == "function" then _G.MSCB_ApplyFontsFromMSUF() end
    end
    if not onlyKey then
        if type(_G.MSUF_FocusKick_ApplyTimeTextFont) == "function" then
            _G.MSUF_FocusKick_ApplyTimeTextFont()
        end
    end
    if _fontSettle.active then
        _MSUF_ScheduleFontProbe()
    end

    if _G.MSUF_BossTestMode and _G.MSUF_UnitEditModeActive and not _G.MSUF_InCombat then
        local frames = (MSUF and MSUF.UF and MSUF.UF.frames) or {}
        local max = _G.MSUF_MAX_BOSS_FRAMES or 5
        for i = 1, max do
            local bf = frames["boss" .. i]
            if bf and bf.isBoss and bf.ForceUpdate then
                bf:ForceUpdate("FONT_RUNTIME")
            end
        end
    end

end

_MSUF_RunFontProbe = function(expectedGeneration)
    if expectedGeneration and expectedGeneration ~= _fontSettle.generation then return end
    _fontSettle.pending = false
    if not _fontSettle.active then return end
    if _MSUF_FontCombatLocked() then
        _MSUF_DeferFontRecoveryAfterCombat(false)
        return
    end

    local generation = _fontSettle.generation
    _fontSettle.attempt = _fontSettle.attempt + 1
    if _ConfiguredFontReady(_fontSettle.path) then
        _MSUF_BumpFontApplyEpoch()
        _fontSettle.active = false
        UpdateAllFonts()

        if generation ~= _fontSettle.generation then
            _MSUF_ScheduleFontProbe()
            return
        end
        _fontSettle.attempt = 0
        return
    end

    if generation == _fontSettle.generation
        and _fontSettle.active
        and _fontSettle.attempt < #MSUF_FONT_SETTLE_DELAYS
    then
        _MSUF_ScheduleFontProbe()
    else
        _fontSettle.active = false
        _fontSettle.timedOutTuple = _fontSettle.tuple
    end
end

_MSUF_ScheduleFontProbe = function()
    if _fontSettle.pending or not _fontSettle.active then return end
    local delay = MSUF_FONT_SETTLE_DELAYS[_fontSettle.attempt + 1]
    if not delay then
        _fontSettle.active = false
        _fontSettle.timedOutTuple = _fontSettle.tuple
        return
    end
    local generation = _fontSettle.generation
    local function RunCapturedFontProbe()
        if generation ~= _fontSettle.generation then return end
        _MSUF_RunFontProbe(generation)
    end
    _G.C_Timer.After(delay, RunCapturedFontProbe)
    _fontSettle.pending = true
end

ExportPublic("MSUF_RequestFontRecovery", function()
    _fontSettle.forceNext = true
    if _MSUF_FontCombatLocked() then
        _MSUF_DeferFontRecoveryAfterCombat(true)
        return false
    end
    return UpdateAllFonts()
end)

MSUF.MSUF_UpdateAllFonts = UpdateAllFonts
ExportPublic("MSUF_UpdateAllFonts", UpdateAllFonts)

if not _G.MSUF_UpdateAllFonts_Immediate then
    ExportPublic("MSUF_UpdateAllFonts_Immediate", _G.MSUF_UpdateAllFonts)
    ExportPublic("MSUF_UpdateAllFonts", function(onlyKey)
        local st = _G.MSUF_ApplyCommitState
        if not st then
            if _MSUF_FontCombatLocked() then
                _fontSettle.forceNext = true
                _MSUF_DeferFontRecoveryAfterCombat(true)
                return false
            end
            return UpdateAllFonts(onlyKey)
        end
        st.fonts = true
        if onlyKey then
            if st.fontKey == nil then
                st.fontKey = onlyKey
            elseif st.fontKey == false then
                --- already a full refresh queued
            elseif st.fontKey ~= onlyKey then
                st.fontKey = false
            end
        else
            st.fontKey = false
        end
        ScheduleApplyCommit()
    end)
end

MSUF.Fonts.UpdateAllFonts = UpdateAllFonts
--- Namespaced mirror of the _G export above; new internal callers should use
--- this instead of the global.
MSUF.Fonts.RequestRecovery = _G.MSUF_RequestFontRecovery

-- The per-frame init layout uses a font snapshot that can pre-date the font being
-- loadable, so kick one font apply + readiness-gated text relayout at login
-- through the same UpdateAllFonts path. Self-unregisters; the retry inside
-- UpdateAllFonts handles cold starts.
do
    local kick = CreateFrame("Frame")
    kick:RegisterEvent("PLAYER_ENTERING_WORLD")
    kick:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        _G.MSUF_RequestFontRecovery("PLAYER_ENTERING_WORLD")
    end)
end
