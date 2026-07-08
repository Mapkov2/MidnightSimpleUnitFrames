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

local function FrameMatchesFontScope(frame, scope)
    if not scope then return true end
    if not frame then return false end
    local key = frame.msufConfigKey
    if (not key) and frame.unit and MSUF and MSUF.UF and MSUF.UF.ConfigKeyForUnit then
        key = MSUF.UF.ConfigKeyForUnit(frame.unit)
    end
    return NormalizeFontScopeKey(key or frame.unit) == scope
end

local function CastbarUnitForFontScope(scope)
    if scope == "player" or scope == "target" or scope == "focus" or scope == "boss" then return scope end
    return nil
end

local CASTBAR_FONT_UNITS = { "player", "target", "focus", "boss" }

local function ApplyAllCastbarFontFollowers()
    local applyUnit = _G.MSUF_ApplyCastbarVisualsForUnit
    if type(applyUnit) == "function" then
        for i = 1, #CASTBAR_FONT_UNITS do
            applyUnit(CASTBAR_FONT_UNITS[i])
        end
        return true
    end
    if _G.MSUF_UpdateCastbarVisuals_Immediate then
        _G.MSUF_UpdateCastbarVisuals_Immediate()
        return true
    end
    if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals()
        return true
    end
    return false
end

local function ApplyScopedFontFollowers(scope)
    if scope then
        local castbarUnit = CastbarUnitForFontScope(scope)
        if castbarUnit and type(_G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
            _G.MSUF_ApplyCastbarVisualsForUnit(castbarUnit)
        elseif castbarUnit and type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
            _G.MSUF_ApplyCastbarUnitAndSync(castbarUnit)
        end
        local a3 = MSUF and MSUF.MSUF_Auras3
        if a3 and type(a3.ApplyFontsFromGlobal) == "function" then
            a3.ApplyFontsFromGlobal(scope, "FONT_RUNTIME_SCOPE")
        end
        if scope == "player" and type(_G.MSUF_ClassPower_Apply) == "function" then
            _G.MSUF_ClassPower_Apply({ fonts = true, playerHP = true })
        end
        return
    end

    ApplyAllCastbarFontFollowers()
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.ApplyFontsFromGlobal) == "function" then a3.ApplyFontsFromGlobal() end
    if _G.MSUF_ClassPower_ApplyFonts then _G.MSUF_ClassPower_ApplyFonts() end
end

--- Font changes affect many elements. Defer the UF dirty commit so global font
--- and per-frame text relayout happen once after a settings burst.
local function ScheduleApplyCommit()
    local UF = MSUF and MSUF.UF
    local commit = UF and UF.ApplyDirty
    if type(commit) ~= "function" then return end
    if _G.MSUF_ScheduleOnce then
        _G.MSUF_ScheduleOnce("UF_APPLY_COMMIT", function() commit(UF) end)
    else
        _G.C_Timer.After(0, function() commit(UF) end)
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
}
local _fontState = {}
local _MSUF_FontPathSerialByKey = {}
local _MSUF_FontPathSerialNext = 0

local function _MSUF_ComposeFontFlags(outline, monochrome)
    local flags = ""
    outline = tostring(outline or "OUTLINE"):upper()
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

local function _MSUF_ShadowMetrics(strength)
    strength = tostring(strength or "NORMAL"):upper()
    if strength == "SOFT" then return 0.55, 1, -1 end
    if strength == "DEEP" then return 1, 2, -2 end
    return 1, 1, -1
end

local function _MSUF_OutlineFromFlags(flags)
    flags = tostring(flags or ""):upper()
    if flags:find("THICKOUTLINE", 1, true) then return "THICKOUTLINE" end
    if flags:find("OUTLINE", 1, true) then return "OUTLINE" end
    return "NONE"
end

local function _MSUF_MonochromeFromFlags(flags)
    return tostring(flags or ""):upper():find("MONOCHROME", 1, true) ~= nil
end

--- Cold-start text fix, folded into the font subsystem (no standalone file).
-- On the first login after a client start the configured font may not be
-- loadable when the per-frame init layout runs, so width-dependent text anchors
-- (name maxChars clamp, inline ToT, centre/right text) get committed against the
-- wrong glyph metrics and stay off until a /reload. UpdateAllFonts is the single
-- point every font (re)apply already flows through (init, the LSM
-- LibSharedMedia_Registered callback, font option changes), so it re-runs the
-- text layout there -- but only once the configured font is genuinely applied
-- and measurable, retrying via the existing scheduler until then.
local _fontApplyFailed = false
local _fontRelayoutRetries = 0
local MSUF_FONT_RELAYOUT_MAX_RETRIES = 200   -- ~20s @ 0.1s; a missing font can't loop forever
local _measureFS

local function _ConfiguredFontReady()
    local getPath = _G.MSUF_GetFontPath
    local path = (type(getPath) == "function" and getPath()) or _fontState.path or "Fonts\\FRIZQT__.TTF"
    local resolveSafe = _G.MSUF_ResolveSafeFontPath
    if type(resolveSafe) == "function" then
        local g = _G.MSUF_DB and _G.MSUF_DB.general
        path = resolveSafe(path, 14, "", g and g.fontKey)
    end
    if type(path) ~= "string" or path == "" then return false end
    if not _measureFS then
        if not _G.UIParent then return true end
        _measureFS = _G.UIParent:CreateFontString(nil, "BACKGROUND")
        _measureFS:Hide()
    end
    local ok, applied = pcall(_measureFS.SetFont, _measureFS, path, 14, "")
    if not ok or applied == false then return false end
    -- If the requested path does not match yet, the client is still using a fallback font.
    local applied = _measureFS:GetFont()
    if not applied or tostring(applied):gsub("/", "\\"):lower() ~= tostring(path):gsub("/", "\\"):lower() then
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

local function _MSUF_FontApplied(fs, requestedPath)
    if type(fs.GetFont) ~= "function" then return true end
    local actual = fs:GetFont()
    if not actual then return true end
    local matches = _G.MSUF_FontPathMatches or _G.MSUF_FontPathEquals
    if type(matches) == "function" then
        return matches(requestedPath, actual) == true
    end
    return tostring(actual or ""):gsub("/", "\\"):lower() == tostring(requestedPath or ""):gsub("/", "\\"):lower()
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
    local applied
    local ok, result = pcall(fs.SetFont, fs, path, size, flags)
    if not ok then
        return false
    end
    applied = result
    return applied ~= false and _MSUF_FontApplied(fs, path)
end

local function _MSUF_ApplyFontCached(fs, size, setColor, cr, cg, cb, ca)
    if not fs then return end
    local S = _fontState
    size = _MSUF_NormalizeFontSize(size, 14)

    local rev = S.pathSerial * 10 + (_MSUF_FONT_FLAGS_CODE[S.flags] or 1) + size * 10000030
    if fs._msufFontRev ~= rev then
        local ok = _MSUF_SetFontChecked(fs, S.path, size, S.flags, S.fontKey)
        if not ok then
            local fallback = _G.MSUF_ResolveSafeFontPath and _G.MSUF_ResolveSafeFontPath("Fonts\\FRIZQT__.TTF", size, S.flags, "FRIZQT")
                or (_G.MSUF_ResolveFontPath and _G.MSUF_ResolveFontPath("Fonts\\FRIZQT__.TTF", size, S.flags))
                or "Fonts\\FRIZQT__.TTF"
            ok = _MSUF_SetFontChecked(fs, fallback, size, S.flags, "FRIZQT")
        end
        if ok then
            fs._msufFontRev = rev
            fs._msufShadowOn = nil
        else
            fs._msufFontRev = nil
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

    local sh = S.useShadow and 1 or 0
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
    if (not key) and f.unit and MSUF and MSUF.UF and MSUF.UF.ConfigKeyForUnit then
        key = MSUF.UF.ConfigKeyForUnit(f.unit)
    end
    if S.onlyKey and NormalizeFontScopeKey(key or f.unit) ~= S.onlyKey then return end

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
        if cNoOL ~= nil or cBold ~= nil or cMono ~= nil then
            _origFlags = S.flags
            local outline = _MSUF_OutlineFromFlags(S.flags)
            local monochrome = _MSUF_MonochromeFromFlags(S.flags)
            if cNoOL ~= nil or cBold ~= nil then
                if cNoOL then outline = "NONE"
                elseif cBold then outline = "THICKOUTLINE"
                else outline = "OUTLINE" end
            end
            if cMono ~= nil then monochrome = cMono == true end
            S.flags = _MSUF_ComposeFontFlags(outline, monochrome)
        end
        if conf.textBackdrop ~= nil then
            _origShadow = S.useShadow
            S.useShadow = conf.textBackdrop and true or false
        end
        if conf.fontShadowStrength ~= nil then
            _origShadowAlpha, _origShadowX, _origShadowY = S.shadowAlpha, S.shadowX, S.shadowY
            S.shadowAlpha, S.shadowX, S.shadowY = _MSUF_ShadowMetrics(conf.fontShadowStrength)
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
    if f.raidGroupNameText then _MSUF_ApplyFontCached(f.raidGroupNameText, nameSize, false, 0, 0, 0) end
    if f._msufToTInlineSep then _MSUF_ApplyFontCached(f._msufToTInlineSep, nameSize, false, 0, 0, 0) end
    if f._msufToTInlineText then _MSUF_ApplyFontCached(f._msufToTInlineText, nameSize, false, 0, 0, 0) end
    if f.levelText then _MSUF_ApplyFontCached(f.levelText, (conf and conf.levelIndicatorSize) or nameSize, false, 0, 0, 0) end
    if f.classificationIndicatorText then _MSUF_ApplyFontCached(f.classificationIndicatorText, (conf and conf.classificationIndicatorSize) or nameSize, true, S.fr, S.fg, S.fb, S.textAlpha) end

    local statusSize = _MSUF_NormalizeFontSize(nameSize, 14) + 2
    if f.statusIndicatorText then _MSUF_ApplyFontCached(f.statusIndicatorText, statusSize, true, S.fr, S.fg, S.fb, S.textAlpha) end
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

local function UpdateAllFonts(onlyKey)
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
    local shadowAlpha, shadowX, shadowY = _MSUF_ShadowMetrics(g.fontShadowStrength)
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
    ForEachUnitFrame(_MSUF_ApplyFontsToFrame)

    ApplyScopedFontFollowers(onlyKey)
    if not onlyKey then
        if MSUF and MSUF.MSUF_ApplyGameplayFontFromGlobal then MSUF.MSUF_ApplyGameplayFontFromGlobal() end
        if type(_G.MSCB_ApplyFontsFromMSUF) == "function" then _G.MSCB_ApplyFontsFromMSUF() end
    end
    -- Re-resolve every spec's font and re-run the text layout so width-dependent
    -- anchors recompute for the fonts now applied -- but only once the configured
    -- font is loaded + measurable. On a cold start it isn't yet, so reschedule via
    -- the existing scheduler and try again; this is what fixes the first-login
    -- misposition, driven by the font actually being ready rather than a guess.
    local ready = (not _fontApplyFailed) and _ConfiguredFontReady()
    if ready then
        _fontRelayoutRetries = 0
        local force = _G.MSUF_ForceTextLayoutForUnitKey
        if type(force) == "function" then
            ForEachUnitFrame(function(f)
                if f and FrameMatchesFontScope(f, onlyKey) then force(f.unit or f.msufConfigKey) end
            end)
        elseif MSUF and MSUF.UF then
            if MSUF.UF.UpdateRuntime then
                MSUF.UF.UpdateRuntime(onlyKey, "FONT_RUNTIME")
            elseif MSUF.UF.ForceUpdate then
                MSUF.UF.ForceUpdate(onlyKey)
            end
        end
    elseif _fontRelayoutRetries < MSUF_FONT_RELAYOUT_MAX_RETRIES then
        _fontRelayoutRetries = _fontRelayoutRetries + 1
        if _G.MSUF_ScheduleOnce then
            _G.MSUF_ScheduleOnce("UF_FONT_COLD_RELAYOUT", function() UpdateAllFonts() end)
        else
            _G.C_Timer.After(0.1, function() UpdateAllFonts() end)
        end
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

Export("MSUF_UpdateAllFonts", UpdateAllFonts, "UpdateAllFonts")

if type(_G.MSUF_UpdateCastbarVisuals) == "function" and not _G.MSUF_UpdateCastbarVisuals_Immediate then
    ExportPublic("MSUF_UpdateCastbarVisuals_Immediate", _G.MSUF_UpdateCastbarVisuals)
    ExportPublic("MSUF_UpdateCastbarVisuals", function()
        local st = _G.MSUF_ApplyCommitState
        if st then st.castbars = true end
        ScheduleApplyCommit()
    end)
end

if type(_G.MSUF_UpdateCastbarTextures) == "function" and not _G.MSUF_UpdateCastbarTextures_Immediate then
    ExportPublic("MSUF_UpdateCastbarTextures_Immediate", _G.MSUF_UpdateCastbarTextures)
    ExportPublic("MSUF_UpdateCastbarTextures", function()
        local st = _G.MSUF_ApplyCommitState
        if st then st.castbars = true end
        ScheduleApplyCommit()
    end)
end

if not _G.MSUF_UpdateAllFonts_Immediate then
    ExportPublic("MSUF_UpdateAllFonts_Immediate", _G.MSUF_UpdateAllFonts)
    ExportPublic("MSUF_UpdateAllFonts", function(onlyKey)
        local st = _G.MSUF_ApplyCommitState
        if st then
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
        end
        ScheduleApplyCommit()
    end)
    _G.UpdateAllFonts = _G.UpdateAllFonts or _G.MSUF_UpdateAllFonts
end

MSUF.Fonts.UpdateAllFonts = UpdateAllFonts

-- The per-frame init layout uses a font snapshot that can pre-date the font being
-- loadable, so kick one font apply + readiness-gated text relayout at login
-- through the same UpdateAllFonts path. Self-unregisters; the retry inside
-- UpdateAllFonts handles cold starts.
do
    local kick = CreateFrame("Frame")
    kick:RegisterEvent("PLAYER_ENTERING_WORLD")
    kick:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        UpdateAllFonts()
    end)
end
