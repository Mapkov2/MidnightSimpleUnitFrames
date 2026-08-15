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

local type, tostring, tonumber, pairs, pcall = type, tostring, tonumber, pairs, pcall

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local function Export(key, fn, aliasKey, forceAlias)
    if MSUF then MSUF[key] = fn end
    ExportPublic(key, fn)
    if aliasKey then
        if forceAlias then
            ExportPublic(aliasKey, fn)
        else
            ExportPublic(aliasKey, _G[aliasKey] or fn)
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
    local UF = MSUF and MSUF.UF
    local frames = UF and UF.frames
    if type(frames) ~= "table" then return end
    for _, frame in pairs(frames) do
        if frame then fn(frame) end
    end
end

local function NormalizeFontScopeKey(key)
    if key == nil then return nil end
    key = tostring(key)
    if key == "" then return nil end
    if key == "tot" or key == "targetoftarget" then return "targettarget" end
    if key == "focus_target" or key == "focustargettarget" then return "focustarget" end
    if _G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(key) then return "boss" end
    return key
end

local function CastbarUnitForFontScope(scope)
    if scope == "player" or scope == "target" or scope == "focus" or scope == "boss" then return scope end
    return nil
end

local CASTBAR_FONT_UNITS = { "player", "target", "focus", "boss" }
local UNITFRAME_FONT_ELEMENTS = {
    "Text", "NameText", "HealthText", "PowerText", "InlineToT", "StatusIndicators",
}

local function ApplyAllCastbarFontFollowers()
    local updateVisuals = _G.MSUF_UpdateCastbarVisuals_Immediate or _G.MSUF_UpdateCastbarVisuals
    if type(updateVisuals) == "function" then
        updateVisuals()
        return true
    end

    local applyUnit = _G.MSUF_ApplyCastbarVisualsForUnit
    if type(applyUnit) == "function" then
        for i = 1, #CASTBAR_FONT_UNITS do
            applyUnit(CASTBAR_FONT_UNITS[i])
        end
        return true
    end
    return false
end

local function ApplyScopedFontFollowers(scope, skipCastbars, skipClassPower, skipAuras)
    if scope then
        local castbarUnit = CastbarUnitForFontScope(scope)
        if skipCastbars ~= true and castbarUnit and type(_G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
            _G.MSUF_ApplyCastbarVisualsForUnit(castbarUnit)
        elseif skipCastbars ~= true and castbarUnit and type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
            _G.MSUF_ApplyCastbarUnitAndSync(castbarUnit)
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

    if skipCastbars ~= true then ApplyAllCastbarFontFollowers() end
    local a3 = MSUF and MSUF.MSUF_Auras3
    if skipAuras ~= true and a3 and type(a3.ApplyFontsFromGlobal) == "function" then a3.ApplyFontsFromGlobal() end
    if skipClassPower ~= true and _G.MSUF_ClassPower_ApplyFonts then _G.MSUF_ClassPower_ApplyFonts() end
end

--- Font changes affect many elements. Defer the UF dirty commit so global font
--- and per-frame text relayout happen once after a settings burst.
local function ApplyDirtyCommit()
    local UF = MSUF and MSUF.UF
    local commit = UF and UF.ApplyDirty
    if type(commit) == "function" then commit(UF) end
end

local function ScheduleApplyCommit()
    local UF = MSUF and MSUF.UF
    local commit = UF and UF.ApplyDirty
    if type(commit) ~= "function" then return end
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("UF_APPLY_COMMIT", ApplyDirtyCommit)
    else
        _G.C_Timer.After(0, ApplyDirtyCommit)
    end
end

--- Changes preserved from main:
--- 1. Numeric hash replaces string concat stamps (cheaper comparison)
--- 2. Inner closures hoisted to file-level (no re-creation per call)
--- 3. 3-stamp-layer collapsed to 2 (global + per-key)

local _MSUF_FONT_FLAGS_CODE = {
    [""] = 0,
    OUTLINE = 1,
    THICKOUTLINE = 2,
    MONOCHROME = 3,
    ["OUTLINE,MONOCHROME"] = 4,
    ["THICKOUTLINE,MONOCHROME"] = 5,
    SLUG = 6,
    ["OUTLINE,SLUG"] = 7,
}
local _fontState = {}
local _MSUF_FontPathSerialByKey = {}
local _MSUF_FontPathSerialNext = 0

local function _MSUF_ComposeFontFlags(outline, monochrome, slug)
    local flags = ""
    outline = tostring(outline or "OUTLINE"):upper()
    if slug == true then
        return (outline == "NONE" or outline == "") and "SLUG" or "OUTLINE,SLUG"
    end
    if outline == "THICKOUTLINE" then
        flags = "THICKOUTLINE"
    elseif outline ~= "NONE" and outline ~= "" then
        flags = "OUTLINE"
    end
    if monochrome == true then
        flags = flags ~= "" and (flags .. ",MONOCHROME") or "MONOCHROME"
    end
    return flags
end

local function _MSUF_ClampTextAlpha(value)
    value = tonumber(value) or 1
    if value < 0.7 then return 0.7 end
    if value > 1 then return 1 end
    return value
end

local _MSUF_ShadowMetrics = _G.MSUF_ResolveFontShadowMetrics

--- Bound once at load like _MSUF_ShadowMetrics: Kernel/MSUF_Libs.lua publishes
--- these before any Runtime file and never rebinds them. The per-FontString
--- fanout below runs hot enough that repeated _G lookups are worth removing.
local _MSUF_MatchesApplication = _G.MSUF_FontApplicationMatches
local _MSUF_PathMatchesFn = _G.MSUF_FontPathMatches or _G.MSUF_FontPathEquals
local _MSUF_ClearFSCachesFn = _G.MSUF_ClearFontStringApplyCaches
local _MSUF_ApplyFontScaleMode = _G.MSUF_ApplyFontScaleAnimationMode

local function _MSUF_OutlineFromFlags(flags)
    flags = tostring(flags or ""):upper()
    if flags:find("THICKOUTLINE", 1, true) then return "THICKOUTLINE" end
    if flags:find("OUTLINE", 1, true) then return "OUTLINE" end
    return "NONE"
end

local function _MSUF_MonochromeFromFlags(flags)
    return tostring(flags or ""):upper():find("MONOCHROME", 1, true) ~= nil
end

local function _MSUF_SlugFromFlags(flags)
    return tostring(flags or ""):upper():find("SLUG", 1, true) ~= nil
end

--- Cold-start font coordinator. Path/size readback may become exact before the
--- selected face's glyph metrics are active, so the first fanout is always
--- provisional. Unready retries touch one hidden FontString; a delayed epoch
--- transition performs one forced final fanout and then leaves no timer active.
local _fontApplyFailed = false
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
local MSUF_FONT_SETTLE_DELAYS = { 1.0, 0.5, 1.0, 2.0, 4.0, 8.0 }
local _measureFS
local UpdateAllFonts
local _MSUF_ScheduleFontProbe
local _MSUF_RunFontProbe
local _fontRecoveryCombatFrame
local _fontUpdateDepth = 0
local _fontFailureRecoveryPending = false

_G.MSUF_FontApplyEpoch = tonumber(_G.MSUF_FontApplyEpoch) or 0
--- Local mirror of MSUF_FontApplyEpoch for the per-FontString hot compare.
--- Only _MSUF_BumpFontApplyEpoch advances the epoch, so the mirror re-syncs on
--- every bump; external code reads the global but never writes it.
local _fontApplyEpoch = _G.MSUF_FontApplyEpoch

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
    elseif _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, RecoverLateFontString)
    else
        _fontFailureRecoveryPending = false
    end
end

ExportPublic("MSUF_OnFontApplyFailed", function()
    if _fontSettle.active or _fontSettle.timedOutTuple == _fontSettle.tuple then return end
    if _fontUpdateDepth == 0 then
        _MSUF_ScheduleLateFontRecovery()
    else
        _fontSettle.lateFailureDuringFanout = true
    end
end)

local function _MSUF_BumpFontApplyEpoch()
    local epoch = (tonumber(_G.MSUF_FontApplyEpoch) or 0) + 1
    ExportPublic("MSUF_FontApplyEpoch", epoch)
    _fontApplyEpoch = epoch
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
    path = path or _fontSettle.path or _fontState.path or "Fonts\\FRIZQT__.TTF"
    if type(path) ~= "string" or path == "" then return false end
    if not _measureFS then
        if not _G.UIParent then return true end
        _measureFS = _G.UIParent:CreateFontString(nil, "BACKGROUND")
        _measureFS:Hide()
    end
    local ok, applied = pcall(_measureFS.SetFont, _measureFS, path, 14, "")
    if not ok or applied == false then return false end
    -- If path or size do not match yet, the client is still publishing
    -- provisional/fallback font metrics.
    local matches = _G.MSUF_FontApplicationMatches
    if type(matches) == "function" then
        if not matches(_measureFS, path, 14) then return false end
    else
        local actualPath, actualSize = _measureFS:GetFont()
        if not actualPath
            or tostring(actualPath):gsub("/", "\\"):lower() ~= tostring(path):gsub("/", "\\"):lower()
            or math.abs((tonumber(actualSize) or 0) - 14) > 0.01
        then
            return false
        end
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

local function _MSUF_FontApplied(fs, requestedPath, requestedSize)
    local matchesApplication = _MSUF_MatchesApplication
    if type(matchesApplication) == "function" then
        return matchesApplication(fs, requestedPath, requestedSize) == true
    end
    if type(fs.GetFont) ~= "function" then return true end
    local actual, actualSize = fs:GetFont()
    if not actual then return false end
    local matches = _MSUF_PathMatchesFn
    local pathMatches
    if type(matches) == "function" then
        pathMatches = matches(requestedPath, actual) == true
    else
        pathMatches = tostring(actual or ""):gsub("/", "\\"):lower() == tostring(requestedPath or ""):gsub("/", "\\"):lower()
    end
    actualSize, requestedSize = tonumber(actualSize), tonumber(requestedSize)
    return pathMatches and actualSize ~= nil and requestedSize ~= nil and math.abs(actualSize - requestedSize) <= 0.01
end

local function _MSUF_ClearFontApplyCaches(fs)
    local clear = _MSUF_ClearFSCachesFn
    if type(clear) == "function" then clear(fs) end
    if fs then
        fs._msufFontRev = nil
        fs._msufFontEpoch = nil
    end
end

local function _MSUF_NormalizeFontSize(size, fallback)
    size = tonumber(size)
    if size == nil or size <= 0 then
        size = tonumber(fallback) or 14
    end
    if size < 6 then
        return 6
    elseif size > 128 then
        return 128
    end
    return size
end

local function _MSUF_SetFontChecked(fs, path, size, flags, fontKey)
    if not (fs and type(fs.SetFont) == "function" and type(path) == "string" and path ~= "") then
        return false
    end
    size = _MSUF_NormalizeFontSize(size, 14)
    flags = flags or ""
    if type(_MSUF_ApplyFontScaleMode) == "function" then _MSUF_ApplyFontScaleMode(fs, flags) end
    local applied
    local ok, result = pcall(fs.SetFont, fs, path, size, flags)
    if not ok then
        _MSUF_ClearFontApplyCaches(fs)
        return false, false
    end
    applied = result
    if applied ~= false and _MSUF_FontApplied(fs, path, size) then
        return true, false
    end
    _MSUF_ClearFontApplyCaches(fs)
    return false, applied ~= false
end

local function _MSUF_ApplyFontCached(fs, size, setColor, cr, cg, cb, ca)
    if not fs then return end
    local S = _fontState
    size = _MSUF_NormalizeFontSize(size, 14)

    local rev = S.pathSerial * 10 + (_MSUF_FONT_FLAGS_CODE[S.flags] or 1) + size * 10000030
    local epoch = _fontApplyEpoch
    if fs._msufFontRev ~= rev or fs._msufFontEpoch ~= epoch then
        if fs._msufFontEpoch ~= epoch then _MSUF_ClearFontApplyCaches(fs) end
        local ok, retryableMismatch = _MSUF_SetFontChecked(fs, S.path, size, S.flags, S.fontKey)
        if not ok and not retryableMismatch then
            local fallback = _G.MSUF_ResolveSafeFontPath and _G.MSUF_ResolveSafeFontPath("Fonts\\FRIZQT__.TTF", size, S.flags, "FRIZQT")
                or (_G.MSUF_ResolveFontPath and _G.MSUF_ResolveFontPath("Fonts\\FRIZQT__.TTF", size, S.flags))
                or "Fonts\\FRIZQT__.TTF"
            -- Display-only fallback. It may keep text readable, but it must
            -- never earn the configured font's revision.
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
        ca = _MSUF_ClampTextAlpha(ca)
        local crev = cr * 1000000000 + cg * 1000000 + cb * 1000 + ca
        if fs._msufColorRev ~= crev then
            fs:SetTextColor(cr, cg, cb, ca)
            fs._msufColorRev = crev
        end
    end

    local sh = S.useShadow and not _MSUF_SlugFromFlags(S.flags) and 1 or 0
    local sx = sh == 1 and (tonumber(S.shadowX) or 1) or 0
    local sy = sh == 1 and (tonumber(S.shadowY) or -1) or 0
    local sa = sh == 1 and (tonumber(S.shadowAlpha) or 1) or 0
    if fs._msufShadowOn ~= sh or fs._msufShadowX ~= sx or fs._msufShadowY ~= sy or fs._msufShadowA ~= sa then
        if sh == 1 then
            fs:SetShadowColor(0, 0, 0, sa)
            fs:SetShadowOffset(sx, sy)
        else
            fs:SetShadowOffset(0, 0)
        end
        fs._msufShadowOn = sh
        fs._msufShadowX = sx
        fs._msufShadowY = sy
        fs._msufShadowA = sa
    end
end

local function _MSUF_ApplyFontsToFrame(f)
    if not f then return end
    local S = _fontState
    local key = f.msufConfigKey
    local unit = f.MSUFUnitKey or f.unit
    if (not key) and unit and MSUF and MSUF.UF and MSUF.UF.ConfigKeyForUnit then
        key = MSUF.UF.ConfigKeyForUnit(unit)
    end
    if S.onlyKey and NormalizeFontScopeKey(key or unit) ~= S.onlyKey then return end

    local conf
    if key and _G.MSUF_DB then conf = _G.MSUF_DB[key] end
    local nameSize  = (conf and conf.nameFontSize)  or S.globalNameSize
    local hpSize    = (conf and conf.hpFontSize)    or S.globalHPSize
    local powerSize = (conf and conf.powerFontSize) or S.globalPowSize

    local _origFlags, _origShadow, _origShadowAlpha, _origShadowX, _origShadowY, _origTextAlpha, _origCPT
    if conf and conf.fontOverride then
        local cNoOL = conf.noOutline
        local cBold = conf.boldText
        local cMono = conf.fontMonochrome
        local cSlug = conf.fontSlug
        if cNoOL ~= nil or cBold ~= nil or cMono ~= nil or cSlug ~= nil then
            _origFlags = S.flags
            local outline = _MSUF_OutlineFromFlags(S.flags)
            local monochrome = _MSUF_MonochromeFromFlags(S.flags)
            local slug = _MSUF_SlugFromFlags(S.flags)
            if cNoOL ~= nil or cBold ~= nil then
                if cNoOL then outline = "NONE"
                elseif cBold then outline = "THICKOUTLINE"
                else outline = "OUTLINE" end
            end
            if cMono ~= nil then monochrome = cMono == true end
            if cSlug ~= nil then slug = cSlug == true end
            if slug then monochrome = false end
            S.flags = _MSUF_ComposeFontFlags(outline, monochrome, slug)
        end
        if conf.textBackdrop ~= nil then
            _origShadow = S.useShadow
            S.useShadow = conf.textBackdrop and true or false
        end
        if conf.fontShadowOpacity ~= nil or conf.fontShadowDistance ~= nil or conf.fontShadowStrength ~= nil then
            _origShadowAlpha, _origShadowX, _origShadowY = S.shadowAlpha, S.shadowX, S.shadowY
            S.shadowAlpha, S.shadowX, S.shadowY = _MSUF_ShadowMetrics(conf.fontShadowOpacity,
                conf.fontShadowDistance, conf.fontShadowStrength, S.shadowAlpha, S.shadowX)
        end
        if conf.fontTextAlpha ~= nil then
            _origTextAlpha = S.textAlpha
            S.textAlpha = _MSUF_ClampTextAlpha(conf.fontTextAlpha)
        end
        if conf.colorPowerTextByType ~= nil then
            _origCPT = S.colorPowerByType
            S.colorPowerByType = conf.colorPowerTextByType and true or false
        end
    end

    if f.nameText then _MSUF_ApplyFontCached(f.nameText, nameSize, false, 0, 0, 0) end
    -- NAMELEFT/NAMERIGHT status text anchors to this invisible auto-width twin,
    -- so every font fanout must keep its glyph metrics identical to nameText.
    if f._msufNameAnchorText then _MSUF_ApplyFontCached(f._msufNameAnchorText, nameSize, false, 0, 0, 0) end
    if f.raidGroupNameText then _MSUF_ApplyFontCached(f.raidGroupNameText, nameSize, false, 0, 0, 0) end
    if f._msufToTInlineSep then _MSUF_ApplyFontCached(f._msufToTInlineSep, nameSize, false, 0, 0, 0) end
    if f._msufToTInlineText then _MSUF_ApplyFontCached(f._msufToTInlineText, nameSize, false, 0, 0, 0) end
    if f.levelText then _MSUF_ApplyFontCached(f.levelText, (conf and conf.levelIndicatorSize) or nameSize, false, 0, 0, 0) end
    if f.classificationIndicatorText then _MSUF_ApplyFontCached(f.classificationIndicatorText, (conf and conf.classificationIndicatorSize) or nameSize, true, S.fr, S.fg, S.fb, S.textAlpha) end

    local statusSize = _MSUF_NormalizeFontSize(nameSize, 14) + 2
    -- Status text owns its color in the Status element, which resolves the
    -- optional per-state override before falling back to this same font color.
    -- Writing it here too would win the last write after any font change and
    -- silently drop a configured Dead/Ghost/AFK/DND color, so size only.
    if f.statusIndicatorText then _MSUF_ApplyFontCached(f.statusIndicatorText, statusSize, false, 0, 0, 0) end
    if f.statusIndicatorOverlayText then _MSUF_ApplyFontCached(f.statusIndicatorOverlayText, statusSize, true, S.fr, S.fg, S.fb, S.textAlpha) end

    if f.nameText and S.UpdateNameColor then S.UpdateNameColor(f) end
    if f.hpTextLeft then _MSUF_ApplyFontCached(f.hpTextLeft, hpSize, true, S.fr, S.fg, S.fb, S.textAlpha) end
    if f.hpTextCenter then _MSUF_ApplyFontCached(f.hpTextCenter, hpSize, true, S.fr, S.fg, S.fb, S.textAlpha) end
    if f.hpText then _MSUF_ApplyFontCached(f.hpText, hpSize, true, S.fr, S.fg, S.fb, S.textAlpha) end
    if f.hpTextPct then _MSUF_ApplyFontCached(f.hpTextPct, hpSize, true, S.fr, S.fg, S.fb, S.textAlpha) end

    local pwSetColor = not S.colorPowerByType
    local pCr, pCg, pCb = pwSetColor and S.fr or 0, pwSetColor and S.fg or 0, pwSetColor and S.fb or 0
    if f.powerTextLeft then _MSUF_ApplyFontCached(f.powerTextLeft, powerSize, pwSetColor, pCr, pCg, pCb, S.textAlpha) end
    if f.powerTextCenter then _MSUF_ApplyFontCached(f.powerTextCenter, powerSize, pwSetColor, pCr, pCg, pCb, S.textAlpha) end
    if f.powerTextPct then _MSUF_ApplyFontCached(f.powerTextPct, powerSize, pwSetColor, pCr, pCg, pCb, S.textAlpha) end
    if f.powerText then _MSUF_ApplyFontCached(f.powerText, powerSize, pwSetColor, pCr, pCg, pCb, S.textAlpha) end

    if _origFlags then S.flags = _origFlags end
    if _origShadow ~= nil then S.useShadow = _origShadow end
    if _origShadowAlpha ~= nil then S.shadowAlpha, S.shadowX, S.shadowY = _origShadowAlpha, _origShadowX, _origShadowY end
    if _origTextAlpha ~= nil then S.textAlpha = _origTextAlpha end
    if _origCPT ~= nil then S.colorPowerByType = _origCPT end
end

UpdateAllFonts = function(onlyKey, skipUnitFrames, skipCastbars, skipClassPower, skipAuras)
    _fontUpdateDepth = _fontUpdateDepth + 1
    local castbars = MSUF and MSUF.Castbars
    local getFontPath = castbars and castbars._GetFontPath or _G.MSUF_GetFontPath
    local getFontFlags = castbars and castbars._GetFontFlags or _G.MSUF_GetFontFlags
    local path = type(getFontPath) == "function" and getFontPath() or "Fonts\\FRIZQT__.TTF"
    local flags = type(getFontFlags) == "function" and getFontFlags() or ""

    EnsureDBSafe()
    local db = _G.MSUF_DB
    local g = (db and db.general) or {}
    local resolveSafe = _G.MSUF_ResolveSafeFontPath
    if type(resolveSafe) == "function" then
        path = resolveSafe(path, 14, flags, g.fontKey)
    end
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

    local baseSize       = _MSUF_NormalizeFontSize(g.fontSize, 14)
    local globalNameSize = _MSUF_NormalizeFontSize(g.nameFontSize, baseSize)
    local globalHPSize   = _MSUF_NormalizeFontSize(g.hpFontSize, baseSize)
    local globalPowSize  = _MSUF_NormalizeFontSize(g.powerFontSize, baseSize)
    local useShadow      = not (g and g.textBackdrop == false)
    local shadowAlpha, shadowX, shadowY = _MSUF_ShadowMetrics(g.fontShadowOpacity,
        g.fontShadowDistance, g.fontShadowStrength)
    local textAlpha = _MSUF_ClampTextAlpha(g.fontTextAlpha)
    local colorPowerByType = (g.colorPowerTextByType == true)

    onlyKey = NormalizeFontScopeKey(onlyKey)

    local pathKey = tostring(path) .. "|" .. tostring(flags) .. "|" .. tostring(fr) .. "|" .. tostring(fg) .. "|" .. tostring(fb)
    if _G.MSUF_FontPathKey ~= pathKey then
        ExportPublic("MSUF_FontPathKey", pathKey)
        ExportPublic("MSUF_FontPathSerial", (_G.MSUF_FontPathSerial or 0) + 1)
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
    _fontState.shadowAlpha = shadowAlpha
    _fontState.shadowX = shadowX
    _fontState.shadowY = shadowY
    _fontState.textAlpha = textAlpha
    _fontState.colorPowerByType = colorPowerByType
    _fontState.onlyKey = onlyKey
    _fontState.UpdateNameColor = nil

    _fontApplyFailed = false
    local fontFailureSerialBefore = tonumber(_G.MSUF_FontApplyFailureSerial) or 0
    local unitFramesApplied = false
    if skipUnitFrames ~= true then
        local UF = MSUF and MSUF.UF
        if UF and type(UF.RefreshElements) == "function" then
            unitFramesApplied = UF.RefreshElements(onlyKey, UNITFRAME_FONT_ELEMENTS, "FONT_RUNTIME") ~= false
        elseif type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
            _G.MSUF_ForceTextLayoutForUnitKey(onlyKey)
            unitFramesApplied = true
        end
        if not unitFramesApplied then ForEachUnitFrame(_MSUF_ApplyFontsToFrame) end
    end

    -- Group name FontStrings are the source for Auras3 name-color overlays.
    -- Refresh them before Auras3 copies their font during the final fanout.
    if not onlyKey then
        local gf = MSUF and MSUF.GF
        if gf and type(gf.RefreshFonts) == "function" then gf.RefreshFonts() end
    end
    ApplyScopedFontFollowers(onlyKey, skipCastbars, skipClassPower, skipAuras)
    if not onlyKey then
        if MSUF and MSUF.MSUF_ApplyGameplayFontFromGlobal then MSUF.MSUF_ApplyGameplayFontFromGlobal() end
        if type(_G.MSCB_ApplyFontsFromMSUF) == "function" then _G.MSCB_ApplyFontsFromMSUF() end
    end
    if not onlyKey then
        if type(_G.MSUF_FocusKick_ApplyTimeTextFont) == "function" then
            _G.MSUF_FocusKick_ApplyTimeTextFont()
        end
    end
    if (tonumber(_G.MSUF_FontApplyFailureSerial) or 0) ~= fontFailureSerialBefore then
        _fontApplyFailed = true
    end
    if _fontSettle.active and not _fontSettle.committing then
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
    _fontUpdateDepth = _fontUpdateDepth - 1
    if _fontUpdateDepth == 0 and _fontSettle.lateFailureDuringFanout then
        _fontSettle.lateFailureDuringFanout = nil
        _MSUF_ScheduleLateFontRecovery()
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
            return
        end
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
    _fontSettle.pending = true
    local key = "UF_FONT_COLD_RELAYOUT_" .. tostring(generation)
    if _G.MSUF_ScheduleDelayOnce then
        _G.MSUF_ScheduleDelayOnce(key, delay, RunCapturedFontProbe)
    elseif _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(delay, RunCapturedFontProbe)
    elseif _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce(key, RunCapturedFontProbe)
    else
        _fontSettle.pending = false
        _fontSettle.active = false
    end
end

ExportPublic("MSUF_RequestFontRecovery", function()
    _fontSettle.forceNext = true
    if _MSUF_FontCombatLocked() then
        _MSUF_DeferFontRecoveryAfterCombat(true)
        return false
    end
    return UpdateAllFonts()
end)

Export("MSUF_UpdateAllFonts", UpdateAllFonts, "UpdateAllFonts")

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
    _G.UpdateAllFonts = _G.UpdateAllFonts or _G.MSUF_UpdateAllFonts
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
