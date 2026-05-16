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
    if not _G.MSUF_DB and type(_G.EnsureDB) == "function" then
        _G.EnsureDB()
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
    local ok, actual = pcall(fs.GetFont, fs)
    if not ok or not actual then return true end
    local matches = _G.MSUF_FontPathMatches or _G.MSUF_FontPathEquals
    if type(matches) == "function" then
        return matches(requestedPath, actual) == true
    end
    return tostring(actual or ""):gsub("/", "\\"):lower() == tostring(requestedPath or ""):gsub("/", "\\"):lower()
end

local function _MSUF_SetFontChecked(fs, path, size, flags, fontKey)
    local safeSet = _G.MSUF_SetFontSafe
    if type(safeSet) == "function" then
        local ok = safeSet(fs, path, size, flags, fontKey)
        return ok == true
    end

    local ok, applied = pcall(fs.SetFont, fs, path, size, flags)
    return ok and applied ~= false and _MSUF_FontApplied(fs, path)
end

local function _MSUF_ApplyFontCached(fs, size, setColor, cr, cg, cb)
    if not fs then return end
    local S = _fontState
    size = tonumber(size) or 14

    local rev = S.pathSerial * 10 + (_MSUF_FONT_FLAGS_CODE[S.flags] or 1) + size * 10000030
    if fs._msufFontRev ~= rev then
        local ok = _MSUF_SetFontChecked(fs, S.path, size, S.flags, S.fontKey)
        if not ok then
            local fallback = _G.MSUF_ResolveFontPath and _G.MSUF_ResolveFontPath("Fonts\\FRIZQT__.TTF", size, S.flags) or "Fonts\\FRIZQT__.TTF"
            ok = _MSUF_SetFontChecked(fs, fallback, size, S.flags, "FRIZQT")
        end
        if ok then
            fs._msufFontRev = rev
            fs._msufShadowOn = nil
        else
            fs._msufFontRev = nil
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

local function UpdateAllFonts(onlyKey)
    local castbars = ns and ns.Castbars
    local getFontPath = castbars and castbars._GetFontPath or _G.MSUF_GetFontPath
    local getFontFlags = castbars and castbars._GetFontFlags or _G.MSUF_GetFontFlags
    local path = type(getFontPath) == "function" and getFontPath() or "Fonts\\FRIZQT__.TTF"
    local flags = type(getFontFlags) == "function" and getFontFlags() or ""

    EnsureDBSafe()
    local db = _G.MSUF_DB
    local g = (db and db.general) or {}
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
    _G.UpdateAllFonts = _G.MSUF_UpdateAllFonts
end

ns.Fonts.UpdateAllFonts = UpdateAllFonts
