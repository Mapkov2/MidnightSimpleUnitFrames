-- MSUF_A2_CooldownText.lua
-- Auras 2.0 cooldown text handling.
-- Phase 4: extract cooldown text manager out of Render for line-reduction + clarity.
--
-- Goals:
--  * One centralized manager (single OnUpdate) for cooldown-text coloring + optional text.
--  * Secret-safe: prefer Duration Objects / C_UnitAuras.GetAuraDurationRemaining.
--  * OmniCC is not assumed in Midnight.

local addonName, ns = ...
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
-- Locate the Blizzard cooldown countdown FontString (lazy-built)
-- ------------------------------------------------------------

function MSUF_A2_GetCooldownFontString(icon)
    local cd = icon and icon.cooldown
    if not cd or not cd.GetRegions then return nil end

    local cached = cd._msufCooldownFontString
    if cached and cached ~= false then
        return cached
    end

    -- If we previously failed to find the fontstring, retry occasionally because
    -- Blizzard may build the countdown text lazily.
    local now = (GetTime and GetTime()) or 0
    if cached == false then
        local last = cd._msufCooldownFontStringLastTry or 0
        if (now - last) < 0.5 then
            return nil
        end
    end
    cd._msufCooldownFontStringLastTry = now

    local regions = { cd:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        if r and r.GetObjectType and r:GetObjectType() == "FontString" then
            cd._msufCooldownFontString = r
            return r
        end
    end

    cd._msufCooldownFontString = false
    return nil
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
    local ok = pcall(curve.AddPoint, curve, x, value)
    if ok then
        MSUF_A2_CurveAddMode = "xy"
        return true
    end

    local pt = MSUF_A2_CreateCurvePoint(x, value)
    if pt then
        ok = pcall(curve.AddPoint, curve, pt)
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

    if rem <= (t.expireSec or 0.25) then
        return (MSUF_A2_CooldownTextColors and MSUF_A2_CooldownTextColors.expire) or nil
    elseif rem <= (t.urgSec or 5) then
        return (MSUF_A2_CooldownTextColors and MSUF_A2_CooldownTextColors.urgent) or nil
    elseif rem <= (t.warnSec or 15) then
        return (MSUF_A2_CooldownTextColors and MSUF_A2_CooldownTextColors.warning) or nil
    elseif rem <= (t.safeSec or 60) then
        return (MSUF_A2_CooldownTextColors and MSUF_A2_CooldownTextColors.safe) or nil
    else
        return (MSUF_A2_CooldownTextColors and MSUF_A2_CooldownTextColors.normal) or nil
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
        if pcall(curve.AddPoint, curve, x, color) then
            return true
        end

        -- Some builds: AddPoint(point) where point = { x = <number>, y = <Color> }
        if pcall(curve.AddPoint, curve, { x = x, y = color }) then
            return true
        end

        -- Some builds: AddPoint(x, r, g, b, a)
        if color and color.GetRGBA then
            local r, g, b, a = color:GetRGBA()
            if pcall(curve.AddPoint, curve, x, r, g, b, a) then
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

local function MSUF_A2_FormatCooldownTimeText(rem)
    rem = tonumber(rem)
    if not rem or rem <= 0 then return "" end

    if rem < 10 then
        local v = math.floor(rem * 10 + 0.5) / 10
        local s = tostring(v)
        if not string.find(s, "%.", 1, true) then
            s = s .. ".0"
        end
        return s
    elseif rem < 60 then
        return tostring(math.floor(rem + 0.5))
    end

    if rem < 600 then
        local m = math.floor(rem / 60)
        local s = math.floor(rem - (m * 60))
        if s < 0 then s = 0 end
        if s < 10 then
            return tostring(m) .. ":0" .. tostring(s)
        end
        return tostring(m) .. ":" .. tostring(s)
    end

    if rem < 3600 then
        local m = math.floor(rem / 60 + 0.5)
        return tostring(m) .. "m"
    end

    local h = math.floor(rem / 3600 + 0.5)
    return tostring(h) .. "h"
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
    acc = 0,
}

local function MSUF_A2_CooldownTextMgr_StopIfIdle()
    if MSUF_A2_CooldownTextMgr.count > 0 then return end
    MSUF_A2_CooldownTextMgr.count = 0
    local f = MSUF_A2_CooldownTextMgr.frame
    if f then
        f:SetScript("OnUpdate", nil)
        f:Hide()
    end
end

local function MSUF_A2_CooldownTextMgr_EnsureFrame()
    local f = MSUF_A2_CooldownTextMgr.frame
    if f then return f end
    f = CreateFrame("Frame")
    f:Hide()
    MSUF_A2_CooldownTextMgr.frame = f
    return f
end

local function MSUF_A2_CooldownTextMgr_OnUpdate(_, elapsed)
    local mgr = MSUF_A2_CooldownTextMgr
    mgr.acc = mgr.acc + (elapsed or 0)
    if mgr.acc < 0.10 then return end -- 10 Hz
    mgr.acc = 0

    local bucketsEnabled = MSUF_A2_IsCooldownTextBucketColoringEnabled()
    local c = MSUF_A2_EnsureCooldownTextColors()
    local safeCol = c and c.safe or nil
    local normalCol = c and c.normal or nil

    local curve = bucketsEnabled and MSUF_A2_EnsureCooldownColorCurve() or nil

    local secrets = C_Secrets
    local isSecret = (secrets and type(secrets.IsSecret) == "function") and secrets.IsSecret or nil

    local removed = 0
    for cooldown, ic in pairs(mgr.active) do
        if (not cooldown) or (not ic) or (not ic.IsShown) or (ic.IsShown and not ic:IsShown()) then
            mgr.active[cooldown] = nil
            removed = removed + 1
        elseif ic._msufA2_hideCDNumbers ~= true then
            local r, g, b, a
            local remSeconds
            local didCurveColor = false

            -- Base color: safe when disabled; normal when enabled (long durations stay default).
            if not bucketsEnabled then
                if safeCol then r, g, b, a = safeCol[1], safeCol[2], safeCol[3], safeCol[4] end
            else
                if normalCol then r, g, b, a = normalCol[1], normalCol[2], normalCol[3], normalCol[4] end
            end

            -- Secret-safe bucket color (preferred): DurationObject + curve evaluation.
            if bucketsEnabled and curve then
                local obj = ic._msufA2_cdDurationObj or (cooldown and cooldown._msufA2_durationObj)
                if obj and type(obj.EvaluateRemainingDuration) == "function" then
                    local col = obj:EvaluateRemainingDuration(curve)
                    if col and col.GetRGBA then
                        r, g, b, a = col:GetRGBA()
                        didCurveColor = true
                    elseif col and col.GetRGB then
                        r, g, b = col:GetRGB()
                        a = 1
                        didCurveColor = true
                    end
                end
            end

            -- Remaining seconds (for optional live text + non-secret bucket fallback).
            if C_UnitAuras and type(C_UnitAuras.GetAuraDurationRemaining) == "function" then
                local unit = ic._msufUnit
                local auraID = ic._msufAuraInstanceID
                if unit and auraID and type(auraID) == "number" then
                    local rem = C_UnitAuras.GetAuraDurationRemaining(unit, auraID)
                    if type(rem) == "number" then
                        remSeconds = rem

                        if bucketsEnabled and (not didCurveColor) and (not (isSecret and isSecret(rem))) then
                            local colT = MSUF_A2_GetCooldownTextColorForRemainingSeconds(rem)
                            if colT then r, g, b, a = colT[1], colT[2], colT[3], colT[4] end
                        end
                    end
                end
            end

            -- Edit Mode preview: synthetic cooldown timing (always plain numbers).
            if ic._msufA2_isPreview == true then
                local ps = ic._msufA2_previewCooldownStart
                local pd = ic._msufA2_previewCooldownDur
                if type(ps) == "number" and type(pd) == "number" and pd > 0 then
                    local rem = (ps + pd) - GetTime()
                    if type(rem) == "number" then
                        remSeconds = rem
                        if bucketsEnabled and (not didCurveColor) then
                            local colT = MSUF_A2_GetCooldownTextColorForRemainingSeconds(rem)
                            if colT then r, g, b, a = colT[1], colT[2], colT[3], colT[4] end
                        end
                    end
                end
            end

            -- Cache cooldown fontstring once (Blizzard may create it lazily)
            local fs = cooldown and cooldown._msufCooldownFontString
            if fs == false then fs = nil end
            if not fs then
                fs = MSUF_A2_GetCooldownFontString(ic)
            end
            if fs and cooldown then
                cooldown._msufCooldownFontString = fs
            end

            if fs then
                -- Optional live text (OmniCC-independent) when we have a plain number.
                if remSeconds ~= nil and fs.SetText and (not (isSecret and isSecret(remSeconds))) then
                    local t = MSUF_A2_FormatCooldownTimeText(remSeconds)
                    if fs._msufA2_lastText ~= t then
                        fs._msufA2_lastText = t
                        fs:SetText(t)
                    end
                end

                if r then
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

    if removed > 0 then
        mgr.count = mgr.count - removed
        if mgr.count < 0 then mgr.count = 0 end
        MSUF_A2_CooldownTextMgr_StopIfIdle()
    end
end

local function MSUF_A2_CooldownTextMgr_RegisterIcon(icon)
    local cd = icon and icon.cooldown
    if not cd then return end

    if MSUF_A2_CooldownTextMgr.active[cd] then
        return
    end

    MSUF_A2_CooldownTextMgr.active[cd] = icon
    MSUF_A2_CooldownTextMgr.count = MSUF_A2_CooldownTextMgr.count + 1
    icon._msufA2_cdMgrRegistered = true

    local f = MSUF_A2_CooldownTextMgr_EnsureFrame()
    if MSUF_A2_CooldownTextMgr.count ~= 1 then
        return
    end

    MSUF_A2_CooldownTextMgr.acc = 0
    f:Show()
    f:SetScript("OnUpdate", MSUF_A2_CooldownTextMgr_OnUpdate)
end

local function MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
    local cd = icon and icon.cooldown
    if not cd then return end
    if not MSUF_A2_CooldownTextMgr.active[cd] then
        icon._msufA2_cdMgrRegistered = false
        return
    end
    MSUF_A2_CooldownTextMgr.active[cd] = nil
    MSUF_A2_CooldownTextMgr.count = MSUF_A2_CooldownTextMgr.count - 1
    if MSUF_A2_CooldownTextMgr.count < 0 then MSUF_A2_CooldownTextMgr.count = 0 end
    icon._msufA2_cdMgrRegistered = false
    MSUF_A2_CooldownTextMgr_StopIfIdle()
end

CT.RegisterIcon   = MSUF_A2_CooldownTextMgr_RegisterIcon
CT.UnregisterIcon = MSUF_A2_CooldownTextMgr_UnregisterIcon

-- Convenience aliases (Render expects these names to exist as locals after it binds them)
API.CooldownText = CT



-- ------------------------------------------------------------
-- Compatibility helpers expected by some refactor entrypoints
-- ------------------------------------------------------------

local function MSUF_A2_CooldownTextMgr_UnregisterAll()
    local mgr = MSUF_A2_CooldownTextMgr
    if not mgr or not mgr.active then return end
    for cd, ic in pairs(mgr.active) do
        if ic then ic._msufA2_cdMgrRegistered = false end
        mgr.active[cd] = nil
    end
    mgr.count = 0
    mgr.acc = 0
    local f = mgr.frame
    if f then
        f:SetScript('OnUpdate', nil)
        f:Hide()
    end
end

-- TouchIcon: force the manager to run on the next OnUpdate tick (cheap nudge)
local function MSUF_A2_CooldownTextMgr_TouchIcon(icon)
    local mgr = MSUF_A2_CooldownTextMgr
    if not mgr or mgr.count <= 0 then return end
    mgr.acc = 0.10
end

CT.UnregisterAll = MSUF_A2_CooldownTextMgr_UnregisterAll
CT.TouchIcon = MSUF_A2_CooldownTextMgr_TouchIcon

-- Cold-start resync (load-order safe)
-- If Render.lua applies cooldowns before this file loads, RegisterIcon calls are skipped.
-- We fix that by (a) consuming a small pending list, and (b) scanning existing pooled icons once.
-- This runs only at load / next tick, so it has effectively zero steady-state cost.
-- ------------------------------------------------------------

local function CT_ProcessPending()
    local st = API and API.state
    local pending = st and st._msufA2_cdPending
    if type(pending) ~= "table" then
        return
    end
    for i = 1, #pending do
        local icon = pending[i]
        if icon then
            pending[i] = nil
            if icon._msufA2_cdMgrRegistered ~= true and icon._msufA2_hideCDNumbers ~= true then
                MSUF_A2_CooldownTextMgr_RegisterIcon(icon)
            end
            icon._msufA2_cdPending = nil
        end
    end
end

local function CT_ScanAndRegisterExisting()
    local st = API and API.state
    local byUnit = st and st.aurasByUnit
    if type(byUnit) ~= "table" then
        return
    end

    for _, entry in pairs(byUnit) do
        if type(entry) == "table" then
            local c1 = entry.buffs
            local c2 = entry.debuffs
            local c3 = entry.mixed
            local cList = { c1, c2, c3 }
            for ci = 1, 3 do
                local cont = cList[ci]
                local icons = cont and cont._msufIcons
                if type(icons) == "table" then
                    for i = 1, #icons do
                        local icon = icons[i]
                        if icon
                            and icon._msufA2_cdMgrRegistered ~= true
                            and icon._msufA2_hideCDNumbers ~= true
                            and icon:IsShown()
                            and icon.cooldown
                            and (icon._msufA2_cdDurationObj ~= nil or icon.cooldown._msufA2_durationObj ~= nil)
                        then
                            MSUF_A2_CooldownTextMgr_RegisterIcon(icon)
                        end
                    end
                end
            end
        end
    end
end

CT.ProcessPending = CT_ProcessPending
CT.ScanExisting   = CT_ScanAndRegisterExisting

-- Run immediately (for the common case where this module loads after Render.lua).
CT_ProcessPending()
CT_ScanAndRegisterExisting()

-- Run once on next frame (for the reverse load order: this file loads before Render.lua).
if C_Timer and type(C_Timer.After) == "function" then
    C_Timer.After(0, function()
        CT_ProcessPending()
        CT_ScanAndRegisterExisting()
    end)
end
