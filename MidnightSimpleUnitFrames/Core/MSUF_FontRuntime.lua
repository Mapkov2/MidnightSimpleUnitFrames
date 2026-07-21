-- Core/MSUF_FontRuntime.lua
-- Runtime font refresh and deferred castbar/font apply wrappers.
-- Extracted from MidnightSimpleUnitFrames.lua; keep exported globals stable.

local addonName, ns = ...
ns = ns or _G.MSUF_NS or {}
_G.MSUF_NS = ns
ns.Fonts = ns.Fonts or {}

local type, tostring, tonumber, pcall, pairs = type, tostring, tonumber, pcall, pairs

local function Export(key, fn, aliasKey, forceAlias)
    if ns then ns[key] = fn end
    _G[key] = fn
    if aliasKey then
        if forceAlias then
            _G[aliasKey] = fn
        else
            _G[aliasKey] = _G[aliasKey] or fn
        end
    end
    return fn
end

local function EnsureDBSafe()
    if not _G.MSUF_DB and type(_G.MSUF_EnsureDB) == "function" then
        (_G.MSUF_EnsureDB)()
    end
end

local function ForEachUnitFrame(fn)
    local forEach = _G.MSUF_ForEachUnitFrame
    if type(forEach) == "function" then
        return forEach(fn)
    end
    local frames = _G.MSUF_UnitFrames
    if type(frames) ~= "table" then return end
    for _, frame in pairs(frames) do
        if frame then fn(frame) end
    end
end

local function ScheduleApplyCommit()
    local schedule = _G.MSUF_ScheduleApplyCommit
    if type(schedule) == "function" then
        schedule()
        return
    end
    local commit = _G.MSUF_CommitApplyDirty
    if type(commit) ~= "function" then return end
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("UF_APPLY_COMMIT", commit)
    elseif _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, commit)
    else
        commit()
    end
end

-- Changes preserved from main:
-- 1. Numeric hash replaces string concat stamps (cheaper comparison)
-- 2. Inner closures hoisted to file-level (no re-creation per call)
-- 3. 3-stamp-layer collapsed to 2 (global + per-key)

local _MSUF_FONT_FLAGS_CODE = { [""] = 0, OUTLINE = 1, THICKOUTLINE = 2 }
local _fontState = {}
local _MSUF_FontPathSerialByKey = {}
local _MSUF_FontPathSerialNext = 0

-- Cold-start font coordinator. WoW can publish the requested path/size before
-- the selected face's glyph metrics are actually active. The first fanout is
-- therefore provisional; a delayed probe advances the epoch and performs one
-- forced settle fanout. Unready retries touch only the hidden probe FontString.
local _fontApplyFailed = false
local _fontApplyFailureSerial = tonumber(_G.MSUF_FontApplyFailureSerial) or 0
local _fontSettle = {
    tuple = nil,
    path = nil,
    generation = 0,
    attempt = 0,
    pending = false,
    active = false,
    forceNext = false,
    committing = false,
}
-- The mandatory first settle intentionally waits one second. Path/size
-- readback can be false-ready for several frames on a real cold client; other
-- production addons use the same one-second post-login font settle window.
local MSUF_FONT_SETTLE_DELAYS = { 1.0, 0.5, 1.0, 2.0, 4.0, 8.0 }
local _measureFS
local UpdateAllFonts
local _MSUF_ScheduleFontProbe
local _MSUF_RunFontProbe
local _fontRecoveryCombatFrame
local _fontUpdateDepth = 0
local _fontFailureRecoveryPending = false

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
        if _fontUpdateDepth == 0
            and not _fontSettle.active
            and _fontSettle.timedOutTuple ~= _fontSettle.tuple
            and type(_G.MSUF_RequestFontRecovery) == "function"
        then
            _G.MSUF_RequestFontRecovery("LATE_FONTSTRING_FAILURE")
        end
    end
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("FONT_APPLY_FAILURE_RECOVERY", RecoverLateFontString)
    elseif _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, RecoverLateFontString)
    else
        _fontFailureRecoveryPending = false
    end
end

local function _MSUF_FontCombatLocked()
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true
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
            local runRequest = _fontSettle.deferredRequest
            local runProbe = _fontSettle.deferredProbe
            _fontSettle.deferredRequest = nil
            _fontSettle.deferredProbe = nil
            if runRequest and type(_G.MSUF_RequestFontRecovery) == "function" then
                _G.MSUF_RequestFontRecovery("PLAYER_REGEN_ENABLED")
            elseif runProbe and type(_MSUF_RunFontProbe) == "function" then
                _MSUF_RunFontProbe()
            end
        end)
        _fontRecoveryCombatFrame = frame
    end
    if _fontRecoveryCombatFrame then
        _fontRecoveryCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end

_G.MSUF_FontApplyFailureSerial = _fontApplyFailureSerial
_G.MSUF_FontApplyEpoch = tonumber(_G.MSUF_FontApplyEpoch) or 0

function _G.MSUF_MarkFontApplyFailed()
    _fontApplyFailureSerial = _fontApplyFailureSerial + 1
    _G.MSUF_FontApplyFailureSerial = _fontApplyFailureSerial
    if not _fontSettle.active and _fontSettle.timedOutTuple ~= _fontSettle.tuple then
        if _fontUpdateDepth == 0 then
            _MSUF_ScheduleLateFontRecovery()
        else
            _fontSettle.lateFailureDuringFanout = true
        end
    end
    return _fontApplyFailureSerial
end

local function _MSUF_BumpFontApplyEpoch()
    local epoch = (tonumber(_G.MSUF_FontApplyEpoch) or 0) + 1
    _G.MSUF_FontApplyEpoch = epoch
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
    _fontSettle.pendingGeneration = nil
    _fontSettle.active = true
    _fontSettle.timedOutTuple = nil
    _MSUF_BumpFontApplyEpoch()
    return true
end

local function _ConfiguredFontReady(path)
    path = path or _fontSettle.path or _fontState.path or "Fonts\\FRIZQT__.TTF"
    if type(path) ~= "string" or path == "" then return false end
    if not _measureFS then
        if not _G.UIParent then return true end
        _measureFS = _G.UIParent:CreateFontString(nil, "BACKGROUND")
        _measureFS:Hide()
    end
    local ok, accepted = pcall(_measureFS.SetFont, _measureFS, path, 14, "")
    if not ok or accepted == false then return false end
    local readOK, applied, appliedSize = pcall(_measureFS.GetFont, _measureFS)
    if not readOK or not applied
        or tostring(applied):gsub("/", "\\"):lower() ~= tostring(path):gsub("/", "\\"):lower()
        or math.abs((tonumber(appliedSize) or 0) - 14) > 0.01
    then
        return false
    end
    _measureFS:SetText("ABCabcgjpqy0123")
    local w = _measureFS:GetStringWidth()
    return type(w) == "number" and w > 0
end

local function _MSUF_GetFontPathSerial(path)
    local key = tostring(path or "")
    local serial = _MSUF_FontPathSerialByKey[key]
    if not serial then
        _MSUF_FontPathSerialNext = _MSUF_FontPathSerialNext + 1
        serial = _MSUF_FontPathSerialNext
        _MSUF_FontPathSerialByKey[key] = serial
    end
    return serial
end

local function _MSUF_FontPathMatches(expected, actual)
    local matches = _G.MSUF_FontPathMatches or _G.MSUF_FontPathEquals
    if type(matches) == "function" then
        return matches(expected, actual) == true
    end
    return tostring(actual or ""):gsub("/", "\\"):lower() == tostring(expected or ""):gsub("/", "\\"):lower()
end

local function _MSUF_FontApplied(fs, expectedPath, expectedSize)
    if type(fs.GetFont) ~= "function" then return true end
    local ok, actualPath, actualSize = pcall(fs.GetFont, fs)
    if not ok or not actualPath or not _MSUF_FontPathMatches(expectedPath, actualPath) then
        return false
    end
    actualSize, expectedSize = tonumber(actualSize), tonumber(expectedSize)
    return actualSize ~= nil and expectedSize ~= nil and math.abs(actualSize - expectedSize) <= 0.01
end

local function _MSUF_ClearFontApplyCaches(fs)
    if not fs then return end
    fs._msufFontRev = nil
    fs._msufFontEpoch = nil
    fs._msufSafeFontPath = nil
    fs._msufSafeFontSize = nil
    fs._msufSafeFontFlags = nil
    fs._msufSafeFontEpoch = nil
    fs._msufSafeFontRequestPath = nil
    fs._msufSafeFontRequestSize = nil
    fs._msufSafeFontRequestFlags = nil
    fs._msufSafeFontRequestEpoch = nil
    fs._msufSafeFontAppliedPath = nil
    fs._msufSafeFontSource = nil
end

-- A cold client can accept SetFont before the live FontString publishes the
-- requested path/metrics. Only verified path + size may earn _msufFontRev;
-- otherwise clear both cache layers and let the bounded cold retry try again.
local function _MSUF_SetFontChecked(fs, path, size, flags, fontKey)
    local expectedSize = tonumber(size) or 12
    if expectedSize <= 0 then expectedSize = 12 end

    local safeSet = _G.MSUF_SetFontSafe
    if type(safeSet) == "function" then
        local ok, appliedPath, source = safeSet(fs, path, size, flags, fontKey)
        if ok ~= true then
            _MSUF_ClearFontApplyCaches(fs)
            return false, false
        end
        appliedPath = appliedPath or path
        -- A helper-level fallback keeps text readable, but it must not settle
        -- the configured-path revision or that font can never be retried.
        if source ~= "fallback"
            and _MSUF_FontPathMatches(path, appliedPath)
            and _MSUF_FontApplied(fs, appliedPath, expectedSize)
        then
            return true, false
        end
        _MSUF_ClearFontApplyCaches(fs)
        return false, true
    end

    local ok, applied = pcall(fs.SetFont, fs, path, expectedSize, flags)
    if not ok or applied == false then
        _MSUF_ClearFontApplyCaches(fs)
        return false, false
    end
    if _MSUF_FontApplied(fs, path, expectedSize) then
        return true, false
    end
    _MSUF_ClearFontApplyCaches(fs)
    return false, true
end

local function _MSUF_ApplyFontCached(fs, size, setColor, cr, cg, cb)
    if not fs then return end
    local S = _fontState
    size = tonumber(size) or 14

    local rev = S.pathSerial * 10 + (_MSUF_FONT_FLAGS_CODE[S.flags] or 1) + size * 10000030
    local epoch = tonumber(_G.MSUF_FontApplyEpoch) or 0
    if fs._msufFontRev ~= rev or fs._msufFontEpoch ~= epoch then
        if fs._msufFontEpoch ~= epoch then
            -- Also defeats older/external SafeSet implementations whose tuple
            -- cache predates MSUF's epoch contract.
            _MSUF_ClearFontApplyCaches(fs)
        end
        local ok, retryableMismatch = _MSUF_SetFontChecked(fs, S.path, size, S.flags, S.fontKey)
        if not ok and not retryableMismatch then
            local fallback = _G.MSUF_ResolveFontPath and _G.MSUF_ResolveFontPath("Fonts\\FRIZQT__.TTF", size, S.flags) or "Fonts\\FRIZQT__.TTF"
            -- Display-only fallback: never stamp the configured-path revision
            -- for a different font or the configured font cannot recover.
            _MSUF_SetFontChecked(fs, fallback, size, S.flags, "FRIZQT")
        end
        if ok then
            fs._msufFontRev = rev
            fs._msufFontEpoch = epoch
            fs._msufShadowOn = nil
        else
            fs._msufFontRev = nil
            fs._msufFontEpoch = nil
            _fontApplyFailed = true
        end
    end

    if setColor then
        cr, cg, cb = tonumber(cr) or 1, tonumber(cg) or 1, tonumber(cb) or 1
        local crev = cr * 1000000 + cg * 1000 + cb
        if fs._msufColorRev ~= crev then
            fs:SetTextColor(cr, cg, cb, 1)
            fs._msufColorRev = crev
        end
    end

    local sh = S.useShadow and 1 or 0
    if fs._msufShadowOn ~= sh then
        if sh == 1 then
            fs:SetShadowColor(0, 0, 0, 1)
            fs:SetShadowOffset(1, -1)
        else
            fs:SetShadowOffset(0, 0)
        end
        fs._msufShadowOn = sh
    end
end

local function _MSUF_ApplyFontsToFrame(f)
    if not f then return end
    local S = _fontState
    local key = f.msufConfigKey
    if (not key) and f.unit and type(_G.MSUF_GetConfigKeyForUnit) == "function" then
        key = _G.MSUF_GetConfigKeyForUnit(f.unit)
    end
    if S.onlyKey and key ~= S.onlyKey then return end

    local conf
    if key and _G.MSUF_DB then conf = _G.MSUF_DB[key] end
    local nameSize  = (conf and conf.nameFontSize)  or S.globalNameSize
    local hpSize    = (conf and conf.hpFontSize)    or S.globalHPSize
    local powerSize = (conf and conf.powerFontSize) or S.globalPowSize

    local _origFlags, _origShadow, _origCPT
    if conf and conf.fontOverride then
        local cNoOL = conf.noOutline
        local cBold = conf.boldText
        if cNoOL ~= nil or cBold ~= nil then
            _origFlags = S.flags
            if cNoOL then S.flags = ""
            elseif cBold then S.flags = "THICKOUTLINE"
            else S.flags = "OUTLINE" end
        end
        if conf.textBackdrop ~= nil then
            _origShadow = S.useShadow
            S.useShadow = conf.textBackdrop and true or false
        end
        if conf.colorPowerTextByType ~= nil then
            _origCPT = S.colorPowerByType
            S.colorPowerByType = conf.colorPowerTextByType and true or false
        end
    end

    if f.nameText then _MSUF_ApplyFontCached(f.nameText, nameSize, false, 0, 0, 0) end
    if f.raidGroupNameText then _MSUF_ApplyFontCached(f.raidGroupNameText, nameSize, false, 0, 0, 0) end
    if f._msufToTInlineSep then _MSUF_ApplyFontCached(f._msufToTInlineSep, nameSize, false, 0, 0, 0) end
    if f._msufToTInlineText then _MSUF_ApplyFontCached(f._msufToTInlineText, nameSize, false, 0, 0, 0) end
    if f.levelText then _MSUF_ApplyFontCached(f.levelText, (conf and conf.levelIndicatorSize) or nameSize, false, 0, 0, 0) end
    if f.classificationIndicatorText then _MSUF_ApplyFontCached(f.classificationIndicatorText, (conf and conf.classificationIndicatorSize) or nameSize, true, S.fr, S.fg, S.fb) end

    local statusSize = (tonumber(nameSize) or 14) + 2
    if f.statusIndicatorText then _MSUF_ApplyFontCached(f.statusIndicatorText, statusSize, true, S.fr, S.fg, S.fb) end
    if f.statusIndicatorOverlayText then _MSUF_ApplyFontCached(f.statusIndicatorOverlayText, statusSize, true, S.fr, S.fg, S.fb) end

    if f.nameText and S.UpdateNameColor then S.UpdateNameColor(f) end
    if f.hpTextLeft then _MSUF_ApplyFontCached(f.hpTextLeft, hpSize, true, S.fr, S.fg, S.fb) end
    if f.hpTextCenter then _MSUF_ApplyFontCached(f.hpTextCenter, hpSize, true, S.fr, S.fg, S.fb) end
    if f.hpText then _MSUF_ApplyFontCached(f.hpText, hpSize, true, S.fr, S.fg, S.fb) end
    if f.hpTextPct then _MSUF_ApplyFontCached(f.hpTextPct, hpSize, true, S.fr, S.fg, S.fb) end

    local pwSetColor = not S.colorPowerByType
    local pCr, pCg, pCb = pwSetColor and S.fr or 0, pwSetColor and S.fg or 0, pwSetColor and S.fb or 0
    if f.powerTextLeft then _MSUF_ApplyFontCached(f.powerTextLeft, powerSize, pwSetColor, pCr, pCg, pCb) end
    if f.powerTextCenter then _MSUF_ApplyFontCached(f.powerTextCenter, powerSize, pwSetColor, pCr, pCg, pCb) end
    if f.powerTextPct then _MSUF_ApplyFontCached(f.powerTextPct, powerSize, pwSetColor, pCr, pCg, pCb) end
    if f.powerText then _MSUF_ApplyFontCached(f.powerText, powerSize, pwSetColor, pCr, pCg, pCb) end

    if _origFlags then S.flags = _origFlags end
    if _origShadow ~= nil then S.useShadow = _origShadow end
    if _origCPT ~= nil then S.colorPowerByType = _origCPT end
end

UpdateAllFonts = function(onlyKey)
    _fontUpdateDepth = _fontUpdateDepth + 1
    local castbars = ns and ns.Castbars
    local getFontPath = castbars and castbars._GetFontPath or _G.MSUF_GetFontPath
    local getFontFlags = castbars and castbars._GetFontFlags or _G.MSUF_GetFontFlags
    local path = type(getFontPath) == "function" and getFontPath() or "Fonts\\FRIZQT__.TTF"
    local flags = type(getFontFlags) == "function" and getFontFlags() or ""

    EnsureDBSafe()
    local db = _G.MSUF_DB
    local g = (db and db.general) or {}
    local forceGeneration = _fontSettle.forceNext == true
    _fontSettle.forceNext = false
    local newFontGeneration = _MSUF_BeginFontGeneration(path, flags, g.fontKey, forceGeneration)
    if newFontGeneration then
        -- Prewarm only; never accept this first sample as final readiness.
        _ConfiguredFontReady(path)
    end
    local getColor = (ns and ns.MSUF_GetConfiguredFontColor) or _G.MSUF_GetConfiguredFontColor
    local fr, fg, fb = 1, 1, 1
    if type(getColor) == "function" then
        fr, fg, fb = getColor()
    end
    fr, fg, fb = tonumber(fr) or 1, tonumber(fg) or 1, tonumber(fb) or 1

    local baseSize       = g.fontSize or 14
    local globalNameSize = g.nameFontSize  or baseSize
    local globalHPSize   = g.hpFontSize    or baseSize
    local globalPowSize  = g.powerFontSize or baseSize
    local useShadow      = g.textBackdrop and true or false
    local colorPowerByType = (g.colorPowerTextByType == true)

    if onlyKey == "tot" or onlyKey == "targetoftarget" then onlyKey = "targettarget" end
    if onlyKey == "focus_target" or onlyKey == "focustargettarget" then onlyKey = "focustarget" end
    if _G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(onlyKey) then onlyKey = "boss" end

    local pathKey = tostring(path) .. "|" .. tostring(flags) .. "|" .. tostring(fr) .. "|" .. tostring(fg) .. "|" .. tostring(fb)
    if _G.MSUF_FontPathKey ~= pathKey then
        _G.MSUF_FontPathKey = pathKey
        _G.MSUF_FontPathSerial = (_G.MSUF_FontPathSerial or 0) + 1
    end

    _fontState.path = path
    _fontState.flags = flags
    _fontState.pathSerial = _MSUF_GetFontPathSerial(path)
    _fontState.fontKey = g.fontKey
    _fontState.fr = fr
    _fontState.fg = fg
    _fontState.fb = fb
    _fontState.globalNameSize = globalNameSize
    _fontState.globalHPSize = globalHPSize
    _fontState.globalPowSize = globalPowSize
    _fontState.useShadow = useShadow
    _fontState.colorPowerByType = colorPowerByType
    _fontState.onlyKey = onlyKey
    _fontState.UpdateNameColor = _G.MSUF_UpdateNameColor

    _fontApplyFailed = false
    local failureSerialBefore = _fontApplyFailureSerial
    ForEachUnitFrame(_MSUF_ApplyFontsToFrame)

    if _G.MSUF_UpdateCastbarVisuals_Immediate then
        _G.MSUF_UpdateCastbarVisuals_Immediate()
    elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals()
    end
    if ns and ns.MSUF_ApplyGameplayFontFromGlobal then ns.MSUF_ApplyGameplayFontFromGlobal() end
    if type(_G.MSCB_ApplyFontsFromMSUF) == "function" then _G.MSCB_ApplyFontsFromMSUF() end
    if _G.MSUF_Auras2_ApplyFontsFromGlobal then _G.MSUF_Auras2_ApplyFontsFromGlobal() end
    if _G.MSUF_ClassPower_ApplyFonts then _G.MSUF_ClassPower_ApplyFonts() end
    if ns and ns.MSUF_ToTInline_RequestRefresh then ns.MSUF_ToTInline_RequestRefresh("FONTS") end
    if type(_G.MSUF_FocusKick_ApplyTimeTextFont) == "function" then
        _G.MSUF_FocusKick_ApplyTimeTextFont()
    end
    local gf = (ns and ns.GF) or (_G.MSUF_NS and _G.MSUF_NS.GF)
    if _fontSettle.committing and gf and type(gf.RefreshVisuals) == "function" then
        if type(gf.InvalidateCdFont) == "function" then gf.InvalidateCdFont() end
        gf.RefreshVisuals()
    elseif gf and type(gf.RefreshFonts) == "function" then
        -- Initial/menu pass: base text only. The single settle commit uses the
        -- full path once so existing GF aura/spell FontStrings also re-enter
        -- their epoch gates without doubling the expensive full refresh.
        gf.RefreshFonts()
    end

    if _fontApplyFailureSerial ~= failureSerialBefore then
        _fontApplyFailed = true
    end
    if _fontSettle.active and not _fontSettle.committing then
        _MSUF_ScheduleFontProbe()
    end

    if _G.MSUF_BossTestMode and _G.MSUF_UnitEditModeActive and not _G.MSUF_InCombat then
        local frames = _G.MSUF_UnitFrames or {}
        local max = _G.MSUF_MAX_BOSS_FRAMES or 5
        for i = 1, max do
            local bf = frames["boss" .. i]
            if bf and bf.isBoss and _G.MSUF_QueueUnitframeUpdate then
                _G.MSUF_QueueUnitframeUpdate(bf, true)
            end
        end
    end
    _fontUpdateDepth = _fontUpdateDepth - 1
    if _fontUpdateDepth == 0 and _fontSettle.lateFailureDuringFanout then
        _fontSettle.lateFailureDuringFanout = nil
        _MSUF_ScheduleLateFontRecovery()
    end
end

local function _MSUF_ForceSettledTextLayout()
    local forceFrame = _G.MSUF_ForceTextLayoutForFrame
    local forceKey = _G.MSUF_ForceTextLayoutForUnitKey
    if type(forceFrame) ~= "function" and type(forceKey) ~= "function" then return end
    local seenKeys = type(forceFrame) ~= "function" and {} or nil
    ForEachUnitFrame(function(f)
        if not f then return end
        if type(forceFrame) == "function" then
            forceFrame(f)
        else
            local key = f.msufConfigKey or f.unit
            local normalize = _G.MSUF_NormalizeTextLayoutUnitKey
            if type(normalize) == "function" then key = normalize(key) end
            key = key or "player"
            if not seenKeys[key] then
                seenKeys[key] = true
                forceKey(key)
            end
        end
    end)
end

_MSUF_RunFontProbe = function(expectedGeneration)
    if expectedGeneration and expectedGeneration ~= _fontSettle.generation then return end
    _fontSettle.pending = false
    _fontSettle.pendingGeneration = nil
    if not _fontSettle.active then return end
    if _MSUF_FontCombatLocked() then
        _MSUF_DeferFontRecoveryAfterCombat(false)
        return
    end

    local generation = _fontSettle.generation
    _fontSettle.attempt = _fontSettle.attempt + 1
    local ready = _ConfiguredFontReady(_fontSettle.path)
    if ready then
        -- The first accepted tuple was provisional. Advancing the epoch makes
        -- every participating cache issue one real SetFont on this settle pass.
        _MSUF_BumpFontApplyEpoch()
        local invalidate = _G.MSUF_InvalidateFontMetricCaches
        if type(invalidate) == "function" then
            invalidate()
        else
            _G.MSUF_NameWidthAvgCache = nil
        end

        _fontSettle.committing = true
        UpdateAllFonts()
        _fontSettle.committing = false

        if generation ~= _fontSettle.generation then
            _MSUF_ScheduleFontProbe()
            return
        end
        if not _fontApplyFailed then
            _fontSettle.active = false
            _fontSettle.attempt = 0
            _MSUF_ForceSettledTextLayout()
            return
        end
    end

    if generation == _fontSettle.generation
        and _fontSettle.active
        and _fontSettle.attempt < #MSUF_FONT_SETTLE_DELAYS
    then
        _MSUF_ScheduleFontProbe()
    else
        -- The readable fallback from the initial fanout remains in place.
        -- A later profile/path change or matching LSM registration starts a
        -- fresh generation with a fresh retry budget.
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
    _fontSettle.pending = true
    _fontSettle.pendingGeneration = generation
    local key = "UF_FONT_COLD_RELAYOUT_" .. tostring(generation)
    if _G.MSUF_ScheduleDelayOnce then
        _G.MSUF_ScheduleDelayOnce(key, delay, RunCapturedFontProbe)
    elseif _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(delay, RunCapturedFontProbe)
    elseif _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce(key, RunCapturedFontProbe)
    else
        _fontSettle.pending = false
        _fontSettle.active = false
    end
end

function _G.MSUF_RequestFontRecovery()
    _fontSettle.forceNext = true
    if _MSUF_FontCombatLocked() then
        _MSUF_DeferFontRecoveryAfterCombat(true)
        return false
    end
    return UpdateAllFonts()
end

Export("MSUF_UpdateAllFonts", UpdateAllFonts, "UpdateAllFonts")

if type(_G.MSUF_UpdateCastbarVisuals) == "function" and not _G.MSUF_UpdateCastbarVisuals_Immediate then
    _G.MSUF_UpdateCastbarVisuals_Immediate = _G.MSUF_UpdateCastbarVisuals
    _G.MSUF_UpdateCastbarVisuals = function()
        local st = _G.MSUF_ApplyCommitState
        if st then st.castbars = true end
        ScheduleApplyCommit()
    end
end

if type(_G.MSUF_UpdateCastbarTextures) == "function" and not _G.MSUF_UpdateCastbarTextures_Immediate then
    _G.MSUF_UpdateCastbarTextures_Immediate = _G.MSUF_UpdateCastbarTextures
    _G.MSUF_UpdateCastbarTextures = function()
        local st = _G.MSUF_ApplyCommitState
        if st then st.castbars = true end
        ScheduleApplyCommit()
    end
end

if not _G.MSUF_UpdateAllFonts_Immediate then
    _G.MSUF_UpdateAllFonts_Immediate = _G.MSUF_UpdateAllFonts
    _G.MSUF_UpdateAllFonts = function(onlyKey)
        local st = _G.MSUF_ApplyCommitState
        if st then
            st.fonts = true
            if onlyKey then
                if st.fontKey == nil then
                    st.fontKey = onlyKey
                elseif st.fontKey == false then
                    -- already a full refresh queued
                elseif st.fontKey ~= onlyKey then
                    st.fontKey = false
                end
            else
                st.fontKey = false
            end
        end
        ScheduleApplyCommit()
    end
    _G.UpdateAllFonts = _G.UpdateAllFonts or _G.MSUF_UpdateAllFonts
end

ns.Fonts.UpdateAllFonts = UpdateAllFonts

do
    local kick = CreateFrame("Frame")
    kick:RegisterEvent("PLAYER_ENTERING_WORLD")
    kick:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        _G.MSUF_RequestFontRecovery("PLAYER_ENTERING_WORLD")
    end)
end
