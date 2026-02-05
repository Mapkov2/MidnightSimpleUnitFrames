-- MSUF_A2_CooldownText.lua
-- Auras 2.0 cooldown text handling.
-- Phase 4: extract cooldown text manager out of Render for line-reduction + clarity.
--
-- Goals:
--  * One centralized manager (single OnUpdate) for cooldown-text coloring + optional text.
--  * Secret-safe: prefer Duration Objects / C_UnitAuras.GetAuraDurationRemaining.
--  * OmniCC is not assumed in Midnight.

local addonName, ns = ...


-- MSUF: Max-perf Auras2: replace protected calls (pcall) with direct calls.
-- NOTE: this removes error-catching; any error will propagate.
local function MSUF_A2_FastCall(fn, ...)
    return true, fn(...)
end
ns = ns or {}

ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

API.CooldownText = (type(API.CooldownText) == "table") and API.CooldownText or {}
local CT = API.CooldownText

-- ------------------------------------------------------------
-- DB helpers (avoid hard dependency on Render-local EnsureDB)
-- ------------------------------------------------------------

local function EnsureDB()
    local db = API.DB
    if db and db.Ensure then
        db.Ensure()
        return
    end
    -- Fallback (should be rare): assume core MSUF_DB exists.
end

-- ------------------------------------------------------------
-- Secret-safe numeric helpers (avoid hard dependency on core helpers)
-- ------------------------------------------------------------

local _A2_NotSecretValue = _G and _G.NotSecretValue or nil

local function MSUF_A2_NotSecretNumber(v)
    if type(v) ~= "number" then return nil end
    if _A2_NotSecretValue and not _A2_NotSecretValue(v) then
        return nil
    end
    return v
end

-- ------------------------------------------------------------
-- Locate the Blizzard cooldown countdown FontString (lazy-built)
-- ------------------------------------------------------------

function MSUF_A2_GetCooldownFontString(icon)
    local cd = icon and (icon.cooldown or icon.Cooldown)
    if not cd or type(cd.GetRegions) ~= "function" then return nil end

    -- Fast path: cached (we intentionally cache *our own* FontString, not Blizzard's).
    local cached = cd._msufCooldownFontString
    if cached and cached ~= false then
        if cached._msufA2_isCustomCooldownText then
            return cached
        end
        -- If we previously cached Blizzard's FontString, replace it with our custom one
        -- so our color can't be overwritten each frame.
    end

    -- If we previously failed, don't retry every tick.
    local now = GetTime()
    if cached == false then
        local lastTry = cd._msufCooldownFontStringLastTry or 0
        if (now - lastTry) < 0.50 then
            return nil
        end
    end
    cd._msufCooldownFontStringLastTry = now

    -- Disable Blizzard's countdown text so it can't overwrite our color each frame.
    if cd.SetHideCountdownNumbers then
        cd:SetHideCountdownNumbers(true)
    end

    -- Find Blizzard's internal FontString once (for font settings + to hard-hide duplicates).
    local r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12 = cd:GetRegions()
    local function isFS(r)
        return r and r.GetObjectType and r:GetObjectType() == "FontString"
    end
    local blizzFS =
        (isFS(r1)  and r1)  or (isFS(r2)  and r2)  or (isFS(r3)  and r3)  or (isFS(r4)  and r4)  or
        (isFS(r5)  and r5)  or (isFS(r6)  and r6)  or (isFS(r7)  and r7)  or (isFS(r8)  and r8)  or
        (isFS(r9)  and r9)  or (isFS(r10) and r10) or (isFS(r11) and r11) or (isFS(r12) and r12)

    if blizzFS and blizzFS.SetAlpha then
        blizzFS:SetAlpha(0)
    end
    cd._msufCooldownFontStringBlizzard = blizzFS

    -- Create our own countdown FontString and cache it.
    local fs = cd:CreateFontString(nil, "OVERLAY")
    if not fs then
        cd._msufCooldownFontString = false
        return nil
    end

    fs:SetPoint("CENTER", cd, "CENTER", 0, 0)
    fs._msufA2_isCustomCooldownText = true
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")

    local fontPath, fontSize, fontFlags
    if blizzFS and blizzFS.GetFont then
        fontPath, fontSize, fontFlags = blizzFS:GetFont()
    end
    if not fontPath and GameFontNormal and GameFontNormal.GetFont then
        fontPath, fontSize, fontFlags = GameFontNormal:GetFont()
    end
    if fontPath then
        fs:SetFont(fontPath, fontSize or 14, fontFlags)
    end

    local col = (MSUF_GetConfiguredFontColor and MSUF_GetConfiguredFontColor()) or nil
    if col and col.GetRGB then
        local r, g, b = col:GetRGB()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            fs:SetTextColor(r, g, b)
        end
    end

    cd._msufCooldownFontString = fs
    return fs
end

CT.GetCooldownFontString = MSUF_A2_GetCooldownFontString

-- ------------------------------------------------------------
-- Bucket colors + curve
-- ------------------------------------------------------------

local MSUF_A2_CooldownColorCurve
local MSUF_A2_CooldownTextColors
local MSUF_A2_CooldownTextThresholds
local MSUF_A2_BucketColoringEnabled
local MSUF_A2_CooldownTextMgr

-- Curve API compatibility:
-- Some clients expose Curve:AddPoint(point) instead of Curve:AddPoint(x, value).
-- We detect the required calling convention once per session.
local MSUF_A2_CurveAddMode -- nil | "xy" | "point" | "none"

local function MSUF_A2_CreateCurvePoint(x, value)
    if C_CurveUtil then
        local f = C_CurveUtil.CreateCurvePoint or C_CurveUtil.CreatePoint or C_CurveUtil.CreatePoint2D
        if type(f) == "function" then
            return f(x, value)
        end
    end
    local g = _G and (_G.CreateCurvePoint or _G.CreatePoint) or nil
    if type(g) == "function" then
        return g(x, value)
    end
    return nil
end

local function MSUF_A2_CurveAddPoint(curve, x, value)
    if not curve then return false end

    if MSUF_A2_CurveAddMode == "xy" then
        curve:AddPoint(x, value)
        return true
    elseif MSUF_A2_CurveAddMode == "point" then
        local pt = MSUF_A2_CreateCurvePoint(x, value)
        if not pt then return false end
        curve:AddPoint(pt)
        return true
    elseif MSUF_A2_CurveAddMode == "none" then
        return false
    end

    -- Detect once (pcall is fine here; curve builds only on invalidation / options changes).
    local ok = MSUF_A2_FastCall(curve.AddPoint, curve, x, value)
    if ok then
        MSUF_A2_CurveAddMode = "xy"
        return true
    end

    local pt = MSUF_A2_CreateCurvePoint(x, value)
    if pt then
        ok = MSUF_A2_FastCall(curve.AddPoint, curve, pt)
        if ok then
            MSUF_A2_CurveAddMode = "point"
            return true
        end
    end

    MSUF_A2_CurveAddMode = "none"
    return false
end

local function MSUF_A2_GetGlobalFontRGB_Fallback()
    EnsureDB()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    if g and g.useCustomFontColor == true
       and type(g.fontColorCustomR) == "number"
       and type(g.fontColorCustomG) == "number"
       and type(g.fontColorCustomB) == "number"
    then
        return g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB
    end
    return 1, 1, 1
end

-- Master toggle (global): when disabled, aura cooldown text always uses the Safe color.
local function MSUF_A2_IsCooldownTextBucketColoringEnabled()
    if MSUF_A2_BucketColoringEnabled ~= nil then
        return MSUF_A2_BucketColoringEnabled
    end
    EnsureDB()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    -- default = enabled
    MSUF_A2_BucketColoringEnabled = not (g and g.aurasCooldownTextUseBuckets == false)
    return MSUF_A2_BucketColoringEnabled
end

local function Clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function NormalizeColorTable(t, fallbackR, fallbackG, fallbackB)
    if type(t) ~= "table" then
        return { fallbackR, fallbackG, fallbackB, 1 }
    end
    local r = t[1] or t.r or fallbackR
    local g = t[2] or t.g or fallbackG
    local b = t[3] or t.b or fallbackB
    local a = t[4] or t.a or 1
    if type(r) ~= "number" then r = fallbackR end
    if type(g) ~= "number" then g = fallbackG end
    if type(b) ~= "number" then b = fallbackB end
    if type(a) ~= "number" then a = 1 end
    return { Clamp01(r), Clamp01(g), Clamp01(b), Clamp01(a) }
end

local function MSUF_A2_EnsureCooldownTextColors()
    if MSUF_A2_CooldownTextColors then
        return MSUF_A2_CooldownTextColors
    end

    EnsureDB()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil

    local normalR, normalG, normalB = MSUF_A2_GetGlobalFontRGB_Fallback()

    local safe   = NormalizeColorTable(g and g.aurasCooldownTextSafeColor,   normalR, normalG, normalB)
    local warn   = NormalizeColorTable(g and g.aurasCooldownTextWarningColor, 1, 0.82, 0)
    local urgent = NormalizeColorTable(g and g.aurasCooldownTextUrgentColor,  1, 0.1, 0.1)
    local expire = NormalizeColorTable(g and g.aurasCooldownTextExpireColor,  1, 0.1, 0.1)

    MSUF_A2_CooldownTextColors = {
        normal = { normalR, normalG, normalB, 1 },
        safe = safe,
        warning = warn,
        urgent = urgent,
        expire = expire,
    }

    return MSUF_A2_CooldownTextColors
end

local function MSUF_A2_EnsureCooldownTextThresholds()
    if MSUF_A2_CooldownTextThresholds then
        return MSUF_A2_CooldownTextThresholds
    end

    EnsureDB()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil

    local safeSec = g and g.aurasCooldownTextSafeSeconds
    local warnSec = g and g.aurasCooldownTextWarningSeconds
    local urgSec  = g and g.aurasCooldownTextUrgentSeconds

    if type(safeSec) ~= "number" then safeSec = 60 end
    if type(warnSec) ~= "number" then warnSec = 15 end
    if type(urgSec)  ~= "number" then urgSec  = 5 end

    -- Clamp + ordering guarantees (UI also enforces, but keep it robust)
    if safeSec < 0 then safeSec = 0 end
    if safeSec > 600 then safeSec = 600 end

    if warnSec < 0 then warnSec = 0 end
    if warnSec > 30 then warnSec = 30 end
    if warnSec > safeSec then warnSec = safeSec end

    if urgSec < 0 then urgSec = 0 end
    if urgSec > 15 then urgSec = 15 end
    if urgSec > warnSec then urgSec = warnSec end

    MSUF_A2_CooldownTextThresholds = {
        expireSec = 0.25, -- "about to expire"
        urgSec    = urgSec,
        warnSec   = warnSec,
        safeSec   = safeSec,
    }

    return MSUF_A2_CooldownTextThresholds
end

local function MSUF_A2_GetCooldownTextColorForRemainingSeconds(rem)
    if type(rem) ~= "number" then return nil end
    if rem <= 0 then return nil end

    local secrets = C_Secrets
    if secrets and type(secrets.IsSecret) == "function" and secrets.IsSecret(rem) == true then
        -- Do not compare/threshold secret numbers; use DurationObject + curve path instead.
        return nil
    end

    local t = MSUF_A2_EnsureCooldownTextThresholds()
    if not t then return nil end

    -- Ensure colors are built (they are table colors, not necessarily CreateColor objects).
    local c = MSUF_A2_EnsureCooldownTextColors()
    if not c then return nil end

    if rem <= (t.expireSec or 0.25) then
        return c.expire
    elseif rem <= (t.urgSec or 5) then
        return c.urgent
    elseif rem <= (t.warnSec or 15) then
        return c.warning
    elseif rem <= (t.safeSec or 60) then
        return c.safe
    else
        return c.normal
    end
end

local function MSUF_A2_EnsureCooldownColorCurve()
    -- nil = not built yet; false = unsupported (don't retry)
    if MSUF_A2_CooldownColorCurve ~= nil then
        return (MSUF_A2_CooldownColorCurve ~= false) and MSUF_A2_CooldownColorCurve or nil
    end

    local curveUtil = C_CurveUtil
    if not curveUtil then
        MSUF_A2_CooldownColorCurve = false
        return nil
    end

    local createCurve = curveUtil.CreateColorCurve or curveUtil.CreateCurve
    if type(createCurve) ~= "function" then
        MSUF_A2_CooldownColorCurve = false
        return nil
    end

    local curve = createCurve()
    if not curve then
        MSUF_A2_CooldownColorCurve = false
        return nil
    end

    -- Step curve (bucket colors)
    if curve.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
        curve:SetType(Enum.LuaCurveType.Step)
    end

    local c = MSUF_A2_EnsureCooldownTextColors()
    local t = MSUF_A2_EnsureCooldownTextThresholds()
    if (not c) or (not t) or (type(CreateColor) ~= "function") then
        MSUF_A2_CooldownColorCurve = false
        return nil
    end

    local function C4(tab)
        if not tab then return nil end
        return CreateColor(tab[1], tab[2], tab[3], tab[4] or 1)
    end

    local colExpire = C4(c.expire)  or C4(c.urgent)  or C4(c.warning) or C4(c.safe) or C4(c.normal)
    local colUrg    = C4(c.urgent)  or C4(c.warning) or C4(c.safe)    or C4(c.normal)
    local colWarn   = C4(c.warning) or C4(c.safe)    or C4(c.normal)
    local colSafe   = C4(c.safe)    or C4(c.normal)
    local colNorm   = C4(c.normal)

    if (not colExpire) or (not colUrg) or (not colWarn) or (not colSafe) or (not colNorm) then
        MSUF_A2_CooldownColorCurve = false
        return nil
    end

    local e = (t.expireSec or 0.25)
    local u = (t.urgSec or 5)
    local w = (t.warnSec or 15)
    local s = (t.safeSec or 60)

    -- Enforce monotonic X (step buckets)
    if u < e then u = e end
    if w < u then w = u end
    if s < w then s = w end

    local function AddColorPoint(x, color)
        if not curve.AddPoint then return false end

        -- Some builds: AddPoint(x, color)
        if MSUF_A2_FastCall(curve.AddPoint, curve, x, color) then
            return true
        end

        -- Some builds: AddPoint(point) where point = { x = <number>, y = <Color> }
        if MSUF_A2_FastCall(curve.AddPoint, curve, { x = x, y = color }) then
            return true
        end

        -- Some builds: AddPoint(x, r, g, b, a)
        if color and color.GetRGBA then
            local r, g, b, a = color:GetRGBA()
            if MSUF_A2_FastCall(curve.AddPoint, curve, x, r, g, b, a) then
                return true
            end
        end

        return false
    end

    if not (AddColorPoint(0, colExpire)
        and AddColorPoint(e, colUrg)
        and AddColorPoint(u, colWarn)
        and AddColorPoint(w, colSafe)
        and AddColorPoint(s, colNorm)) then
        MSUF_A2_CooldownColorCurve = false
        return nil
    end

    MSUF_A2_CooldownColorCurve = curve
    return curve
end

-- String caches for cooldown time text (reduces allocation churn on frequent updates).
local _MSUF_A2_CDTXT_DEC = {}      -- [tenthsInt] => "0.0"
local _MSUF_A2_CDTXT_SEC = {}      -- [sec] => "12"
local _MSUF_A2_CDTXT_MINSEC = {}   -- [min] => table [sec] => "m:ss"
local _MSUF_A2_CDTXT_MIN = {}      -- [min] => "12m"
local _MSUF_A2_CDTXT_HOUR = {}     -- [hour] => "2h"

-- mode: 0=empty, 1=dec (v1=tenthsInt), 2=sec (v1=sec),
--       3=minsec (v1=min, v2=sec), 4=min (v1=min), 5=hour (v1=hour)
local function MSUF_A2_FormatCooldownTimeTextFromBucket(mode, v1, v2)
    if not mode or mode == 0 then
        return ""
    end

    if mode == 1 then
        local s = _MSUF_A2_CDTXT_DEC[v1]
        if not s then
            local a = math.floor(v1 / 10)
            local b = v1 - a * 10
            s = a .. "." .. b
            _MSUF_A2_CDTXT_DEC[v1] = s
        end
        return s
    end

    if mode == 2 then
        local s = _MSUF_A2_CDTXT_SEC[v1]
        if not s then
            s = tostring(v1)
            _MSUF_A2_CDTXT_SEC[v1] = s
        end
        return s
    end

    if mode == 3 then
        local row = _MSUF_A2_CDTXT_MINSEC[v1]
        if not row then
            row = {}
            _MSUF_A2_CDTXT_MINSEC[v1] = row
        end
        local s = row[v2]
        if not s then
            if v2 < 10 then
                s = v1 .. ":0" .. v2
            else
                s = v1 .. ":" .. v2
            end
            row[v2] = s
        end
        return s
    end

    if mode == 4 then
        local s = _MSUF_A2_CDTXT_MIN[v1]
        if not s then
            s = v1 .. "m"
            _MSUF_A2_CDTXT_MIN[v1] = s
        end
        return s
    end

    if mode == 5 then
        local s = _MSUF_A2_CDTXT_HOUR[v1]
        if not s then
            s = v1 .. "h"
            _MSUF_A2_CDTXT_HOUR[v1] = s
        end
        return s
    end

    return ""
end

-- Backwards-compatible helper (kept for any external calls; uses the cached bucket formatter).
local function MSUF_A2_FormatCooldownTimeText(rem)
    rem = tonumber(rem)
    if not rem or rem <= 0 then
        return ""
    end

    if rem < 10 then
        local tenths = math.floor(rem * 10 + 0.5)
        if tenths >= 100 then
            return MSUF_A2_FormatCooldownTimeTextFromBucket(2, 10, 0)
        end
        return MSUF_A2_FormatCooldownTimeTextFromBucket(1, tenths, 0)
    end

    if rem < 60 then
        local sec = math.floor(rem + 0.5)
        return MSUF_A2_FormatCooldownTimeTextFromBucket(2, sec, 0)
    end

    if rem < 600 then
        local min = math.floor(rem / 60)
        local sec = math.floor(rem - min * 60)
        return MSUF_A2_FormatCooldownTimeTextFromBucket(3, min, sec)
    end

    if rem < 3600 then
        local min = math.floor(rem / 60 + 0.5)
        return MSUF_A2_FormatCooldownTimeTextFromBucket(4, min, 0)
    end

    local hour = math.floor(rem / 3600 + 0.5)
    return MSUF_A2_FormatCooldownTimeTextFromBucket(5, hour, 0)
end
-- ------------------------------------------------------------
-- Public controls: invalidate + recolor
-- ------------------------------------------------------------

local function MSUF_A2_InvalidateCooldownTextCurve()
    MSUF_A2_CooldownColorCurve = nil
    MSUF_A2_CooldownTextColors = nil
    MSUF_A2_CooldownTextThresholds = nil
    MSUF_A2_BucketColoringEnabled = nil
end

local function MSUF_A2_ForceCooldownTextRecolor()
    local mgr = MSUF_A2_CooldownTextMgr
    if not mgr or not mgr.active then return end

    local bucketsEnabled = MSUF_A2_IsCooldownTextBucketColoringEnabled()
    local safeCol
    if not bucketsEnabled then
        local c = MSUF_A2_EnsureCooldownTextColors()
        safeCol = c and c.safe or nil
    end

    local curve = bucketsEnabled and MSUF_A2_EnsureCooldownColorCurve() or nil

    for cooldown, ic in pairs(mgr.active) do
        if cooldown and ic and ic.IsShown and ic:IsShown() and ic._msufA2_hideCDNumbers ~= true then
            local r, g, b, a

            if not bucketsEnabled and safeCol then
                r, g, b, a = safeCol[1], safeCol[2], safeCol[3], safeCol[4]
            end

            if C_UnitAuras and type(C_UnitAuras.GetAuraDurationRemaining) == "function" then
                local unit = ic._msufUnit
                local auraID = ic._msufAuraInstanceID
                if unit and auraID and type(auraID) == "number" then
                    local rem = C_UnitAuras.GetAuraDurationRemaining(unit, auraID)
                    if type(rem) == "number" then
                        local colT = MSUF_A2_GetCooldownTextColorForRemainingSeconds(rem)
                        if colT then r, g, b, a = colT[1], colT[2], colT[3], colT[4] end
                    end
                end
            end

            if (not r) and ic._msufA2_isPreview == true then
                local ps = ic._msufA2_previewCooldownStart
                local pd = ic._msufA2_previewCooldownDur
                if type(ps) == "number" and type(pd) == "number" and pd > 0 then
                    local rem = (ps + pd) - GetTime()
                    if type(rem) == "number" then
                        local colT = MSUF_A2_GetCooldownTextColorForRemainingSeconds(rem)
                        if colT then r, g, b, a = colT[1], colT[2], colT[3], colT[4] end
                    end
                end
            end

            if (not r) and curve then
                local obj = ic._msufA2_cdDurationObj or cooldown._msufA2_durationObj
                if obj and type(obj.EvaluateRemainingDuration) == "function" then
                    local col = obj:EvaluateRemainingDuration(curve)
                    if col and col.GetRGBA then
                        r, g, b, a = col:GetRGBA()
                    end
                end
            end

            if r then
                local fs = cooldown._msufCooldownFontString
                if fs == false then fs = nil end
                if not fs then fs = MSUF_A2_GetCooldownFontString(ic) end
                if fs then cooldown._msufCooldownFontString = fs end
                if fs then
                    local aa = a
                    if type(aa) ~= "number" then aa = 1 end
                    if fs.SetTextColor then
                        fs:SetTextColor(r, g, b, aa)
                    elseif fs.SetVertexColor then
                        fs:SetVertexColor(r, g, b, aa)
                    end
                end
            end
        end
    end
end

CT.InvalidateCurve = MSUF_A2_InvalidateCooldownTextCurve
CT.ForceRecolor    = MSUF_A2_ForceCooldownTextRecolor

-- Keep old external entry points.
API.InvalidateCooldownTextCurve = API.InvalidateCooldownTextCurve or MSUF_A2_InvalidateCooldownTextCurve
API.ForceCooldownTextRecolor    = API.ForceCooldownTextRecolor    or MSUF_A2_ForceCooldownTextRecolor

if _G and type(_G.MSUF_A2_InvalidateCooldownTextCurve) ~= "function" then
    _G.MSUF_A2_InvalidateCooldownTextCurve = function() return API.InvalidateCooldownTextCurve() end
end
if _G and type(_G.MSUF_A2_ForceCooldownTextRecolor) ~= "function" then
    _G.MSUF_A2_ForceCooldownTextRecolor = function() return API.ForceCooldownTextRecolor() end
end

-- ------------------------------------------------------------
-- Cooldown Text Manager (single OnUpdate, 10 Hz)
-- ------------------------------------------------------------

MSUF_A2_CooldownTextMgr = {
    frame = nil,
    active = {}, -- [cooldownFrame] = icon
    count = 0,

    -- ticker-based driver (no per-frame OnUpdate)
    ticker = nil,
    tickerInterval = 0,
    slowInterval = 0.25,
    fastInterval = 0.10,
}

local function MSUF_A2_CooldownTextMgr_StopTicker()
    local mgr = MSUF_A2_CooldownTextMgr
    if mgr.ticker then
        mgr.ticker:Cancel()
        mgr.ticker = nil
    end
    mgr.tickerInterval = 0
end

local function MSUF_A2_CooldownTextMgr_EnsureTicker(interval)
    local mgr = MSUF_A2_CooldownTextMgr
    if mgr.count <= 0 then
        MSUF_A2_CooldownTextMgr_StopTicker()
        return
    end

    local want = interval or mgr.slowInterval or 0.25
    if mgr.ticker and mgr.tickerInterval == want then
        return
    end

    MSUF_A2_CooldownTextMgr_StopTicker()
    mgr.tickerInterval = want
    mgr.ticker = C_Timer.NewTicker(want, MSUF_A2_CooldownTextMgr_Tick)
end

local function MSUF_A2_CooldownTextMgr_ChooseNextDelay(remSeconds)
    -- Conservative: accurate enough for display, but cheap.
    if type(remSeconds) ~= "number" then return 0.50 end
    if remSeconds <= 0 then return 0.50 end
    if remSeconds < 10 then return 0.10 end
    if remSeconds < 60 then return 0.50 end
    if remSeconds < 600 then return 1.00 end
    if remSeconds < 3600 then return 5.00 end
    return 10.00
end


local function MSUF_A2_CooldownTextMgr_StopIfIdle()
    local mgr = MSUF_A2_CooldownTextMgr
    if mgr.count <= 0 then
        MSUF_A2_CooldownTextMgr_StopTicker()
        if mgr.frame then mgr.frame:Hide() end
    end
end

local function MSUF_A2_CooldownTextMgr_EnsureFrame()
    local mgr = MSUF_A2_CooldownTextMgr
    if mgr.frame then return mgr.frame end

    local f = CreateFrame("Frame", nil, UIParent)
    f:Hide()
    mgr.frame = f
    return f
end

local function MSUF_A2_ApplyCooldownTextColor(fs, col)
    if not fs or not col then return end

    local r, g, b, a
    if type(col) == "table" then
        local getRGBA = col.GetRGBA
        local getRGB  = col.GetRGB
        if type(getRGBA) == "function" then
            r, g, b, a = col:GetRGBA()
        elseif type(getRGB) == "function" then
            r, g, b = col:GetRGB()
        else
            r, g, b, a = col[1], col[2], col[3], col[4]
        end
    end

    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return
    end

    if fs._msufA2_cdColorR == r
       and fs._msufA2_cdColorG == g
       and fs._msufA2_cdColorB == b
       and fs._msufA2_cdColorA == a
    then
        return
    end

    fs._msufA2_cdColorR, fs._msufA2_cdColorG, fs._msufA2_cdColorB, fs._msufA2_cdColorA = r, g, b, a
    if a ~= nil then
        fs:SetTextColor(r, g, b, a)
    else
        fs:SetTextColor(r, g, b)
    end
end

function MSUF_A2_CooldownTextMgr_Tick()
    local mgr = MSUF_A2_CooldownTextMgr
    if mgr.count <= 0 then
        MSUF_A2_CooldownTextMgr_StopIfIdle()
        return
    end

    local now = GetTime()
    local coloringEnabled = MSUF_A2_IsCooldownTextBucketColoringEnabled()
    local c = MSUF_A2_EnsureCooldownTextColors()
    local colSafe = (c and c.safe) or (c and c.normal) or { 1, 1, 1, 1 }
    local colNormal = (c and c.normal) or colSafe
    local anyFast = false

    for cooldown, icon in pairs(mgr.active) do
        if not icon or not cooldown or icon._msufA2_cdMgrRegistered ~= true or icon:IsShown() ~= true then
            if icon then
                icon._msufA2_cdMgrRegistered = false
                icon._msufA2_cdNextUpdate = nil
                icon._msufA2_cdFast = nil
            end
            mgr.active[cooldown] = nil
            mgr.count = mgr.count - 1
        else
            -- Safety: if the icon is flagged to hide cooldown numbers, don't keep it in the manager.
            if icon._msufA2_hideCDNumbers == true then
                local fs = MSUF_A2_GetCooldownFontString(icon)
                if fs then
                    fs._msufA2_cdMode = 0
                    fs._msufA2_cdV1 = nil
                    fs._msufA2_cdV2 = nil
                    fs:SetText("")
                end
                icon._msufA2_cdMgrRegistered = false
                icon._msufA2_cdNextUpdate = nil
                icon._msufA2_cdFast = nil
                mgr.active[cooldown] = nil
                mgr.count = mgr.count - 1
            else
                local nextAt = icon._msufA2_cdNextUpdate or 0
            if now >= nextAt then
                local remSeconds

                if icon._msufA2_isPreview == true then
                    -- Preview icons: compute from the cooldown widget (safe numbers).
                    local startMS, durMS = cooldown:GetCooldownTimes()
                    if type(startMS) == "number" and type(durMS) == "number" and durMS > 0 then
                        local expiry = (startMS / 1000) + (durMS / 1000)
                        remSeconds = expiry - now
                    else
                        remSeconds = 0
                    end
                else
                    local auraInstanceID = icon._msufA2_auraInstanceID
                    local unit = icon._msufA2_unit
                    if unit and auraInstanceID then
                        remSeconds = C_UnitAuras.GetAuraDurationRemaining(unit, auraInstanceID)
                    else
                        -- Fallback for non-aura cooldowns (if any).
                        local startMS, durMS = cooldown:GetCooldownTimes()
                        if type(startMS) == "number" and type(durMS) == "number" and durMS > 0 then
                            local expiry = (startMS / 1000) + (durMS / 1000)
                            remSeconds = expiry - now
                        end
                    end
                end

                cooldown._msufLastShownNumSeconds = remSeconds

                local fs = MSUF_A2_GetCooldownFontString(icon)
                if fs then
					local delay = MSUF_A2_CooldownTextMgr_ChooseNextDelay(remSeconds) or 0.50
					local safeRem = MSUF_A2_NotSecretNumber(remSeconds)

					if safeRem and safeRem > 0 then
						remSeconds = safeRem
                        -- Only format / allocate a new string when the displayed bucket changes.
                        local mode, v1, v2
                        if remSeconds < 10 then
                            mode = 1
                            v1 = math.floor(remSeconds * 10 + 0.5) -- tenths
                        elseif remSeconds < 60 then
                            mode = 2
                            v1 = math.floor(remSeconds + 0.5)
                        elseif remSeconds < 600 then
                            mode = 3
                            v1 = math.floor(remSeconds / 60) -- minutes
                            v2 = math.floor(remSeconds - v1 * 60) -- seconds
                        elseif remSeconds < 3600 then
                            mode = 4
                            v1 = math.floor(remSeconds / 60 + 0.5) -- minutes (rounded)
                        else
                            mode = 5
                            v1 = math.floor(remSeconds / 3600 + 0.5) -- hours (rounded)
                        end

                        if fs._msufA2_cdMode ~= mode or fs._msufA2_cdV1 ~= v1 or fs._msufA2_cdV2 ~= v2 then
                            fs._msufA2_cdMode = mode
                            fs._msufA2_cdV1 = v1
                            fs._msufA2_cdV2 = v2
                            fs:SetText(MSUF_A2_FormatCooldownTimeTextFromBucket(mode, v1, v2))
                        end

                        icon._msufA2_cdFast = (remSeconds < 10)
                        if icon._msufA2_cdFast then anyFast = true end
                    else
                        -- Secret/invalid/expired: clear our text (we still may set color via duration objects).
                        if fs._msufA2_cdMode ~= 0 then
                            fs._msufA2_cdMode = 0
                            fs._msufA2_cdV1 = nil
                            fs._msufA2_cdV2 = nil
                            fs:SetText("")
                        end
                        icon._msufA2_cdFast = false
                    end


					if coloringEnabled then
						local col
						local modeNow = fs._msufA2_cdMode or 0
						if modeNow ~= 0 and safeRem and safeRem > 0 then
							col = MSUF_A2_GetCooldownTextColorForRemainingSeconds(remSeconds) or colNormal
						else
							col = colSafe
						end
						MSUF_A2_ApplyCooldownTextColor(fs, col)
					else
						-- When bucket coloring is disabled, always use the "Safe" color.
						MSUF_A2_ApplyCooldownTextColor(fs, colSafe)
					end

                    icon._msufA2_cdNextUpdate = now + delay
                else
                    -- If we can't find the FontString yet, retry later without spinning every frame.
                    icon._msufA2_cdNextUpdate = now + 0.50
                    icon._msufA2_cdFast = false
                end
            else
                if icon._msufA2_cdFast == true then anyFast = true end
            end
            end
        end
    end

    if mgr.count <= 0 then
        MSUF_A2_CooldownTextMgr_StopIfIdle()
        return
    end

    -- If any icon needs <10s updates (decimal display), go fast; otherwise stay slow.
    local want = (anyFast and mgr.fastInterval) or mgr.slowInterval
    if mgr.tickerInterval ~= want then
        MSUF_A2_CooldownTextMgr_EnsureTicker(want)
    end
end

local function MSUF_A2_CooldownTextMgr_RegisterIcon(icon)
    if not icon or not icon.cooldown then return end

    local mgr = MSUF_A2_CooldownTextMgr
    local cooldown = icon.cooldown

    if mgr.active[cooldown] ~= nil then return end

    mgr.active[cooldown] = icon
    mgr.count = mgr.count + 1

    icon._msufA2_cdMgrRegistered = true
    icon._msufA2_cdNextUpdate = 0
    icon._msufA2_cdFast = false

    MSUF_A2_CooldownTextMgr_EnsureFrame()
    MSUF_A2_CooldownTextMgr_EnsureTicker(mgr.slowInterval)
end

local function MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
    if not icon or not icon.cooldown then return end

    local mgr = MSUF_A2_CooldownTextMgr
    local cooldown = icon.cooldown

    if mgr.active[cooldown] ~= nil then
        mgr.active[cooldown] = nil
        mgr.count = mgr.count - 1
    end

    icon._msufA2_cdMgrRegistered = false
    icon._msufA2_cdNextUpdate = nil
    icon._msufA2_cdFast = nil

    local fs = MSUF_A2_GetCooldownFontString(icon)
    if fs then
        fs._msufA2_cdMode = 0
        fs._msufA2_cdV1 = nil
        fs._msufA2_cdV2 = nil
        fs:SetText("")
    end

    MSUF_A2_CooldownTextMgr_StopIfIdle()
end

CT.RegisterIcon   = MSUF_A2_CooldownTextMgr_RegisterIcon
CT.UnregisterIcon = MSUF_A2_CooldownTextMgr_UnregisterIcon

-- Convenience aliases (Render expects these names to exist as locals after it binds them)
API.CooldownText = CT