--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua"); -- MSUF_A2_CooldownText.lua
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
local function MSUF_A2_FastCall(fn, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_FastCall file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:15:6");
    return Perfy_Trace_Passthrough("Leave", "MSUF_A2_FastCall file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:15:6", true, fn(...))
end
ns = ns or {}

ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

API.CooldownText = (type(API.CooldownText) == "table") and API.CooldownText or {}
local CT = API.CooldownText

-- ------------------------------------------------------------
-- DB helpers (avoid hard dependency on Render-local EnsureDB)
-- ------------------------------------------------------------

local function EnsureDB() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:30:6");
    local db = API.DB
    if db and db.Ensure then
        db.Ensure()
        Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:30:6"); return
    end
    -- Fallback (should be rare): assume core MSUF_DB exists.
Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:30:6"); end

-- ------------------------------------------------------------
-- Locate the Blizzard cooldown countdown FontString (lazy-built)
-- ------------------------------------------------------------

function MSUF_A2_GetCooldownFontString(icon) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_GetCooldownFontString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:43:0");
    local cd = icon and icon.cooldown
    if not cd or not cd.GetRegions then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetCooldownFontString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:43:0"); return nil end

    local cached = cd._msufCooldownFontString
    if cached and cached ~= false then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetCooldownFontString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:43:0"); return cached
    end

    -- If we previously failed to find the fontstring, retry occasionally because
    -- Blizzard may build the countdown text lazily.
    local now = (GetTime and GetTime()) or 0
    if cached == false then
        local last = cd._msufCooldownFontStringLastTry or 0
        if (now - last) < 0.5 then
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetCooldownFontString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:43:0"); return nil
        end
    end
    cd._msufCooldownFontStringLastTry = now

    local regions = { cd:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        if r and r.GetObjectType and r:GetObjectType() == "FontString" then
            cd._msufCooldownFontString = r
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetCooldownFontString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:43:0"); return r
        end
    end

    cd._msufCooldownFontString = false
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetCooldownFontString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:43:0"); return nil
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

local function MSUF_A2_CreateCurvePoint(x, value) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_CreateCurvePoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:93:6");
    if C_CurveUtil then
        local f = C_CurveUtil.CreateCurvePoint or C_CurveUtil.CreatePoint or C_CurveUtil.CreatePoint2D
        if type(f) == "function" then
            return Perfy_Trace_Passthrough("Leave", "MSUF_A2_CreateCurvePoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:93:6", f(x, value))
        end
    end
    local g = _G and (_G.CreateCurvePoint or _G.CreatePoint) or nil
    if type(g) == "function" then
        return Perfy_Trace_Passthrough("Leave", "MSUF_A2_CreateCurvePoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:93:6", g(x, value))
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CreateCurvePoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:93:6"); return nil
end

local function MSUF_A2_CurveAddPoint(curve, x, value) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_CurveAddPoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:107:6");
    if not curve then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CurveAddPoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:107:6"); return false end

    if MSUF_A2_CurveAddMode == "xy" then
        curve:AddPoint(x, value)
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CurveAddPoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:107:6"); return true
    elseif MSUF_A2_CurveAddMode == "point" then
        local pt = MSUF_A2_CreateCurvePoint(x, value)
        if not pt then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CurveAddPoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:107:6"); return false end
        curve:AddPoint(pt)
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CurveAddPoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:107:6"); return true
    elseif MSUF_A2_CurveAddMode == "none" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CurveAddPoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:107:6"); return false
    end

    -- Detect once (pcall is fine here; curve builds only on invalidation / options changes).
    local ok = MSUF_A2_FastCall(curve.AddPoint, curve, x, value)
    if ok then
        MSUF_A2_CurveAddMode = "xy"
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CurveAddPoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:107:6"); return true
    end

    local pt = MSUF_A2_CreateCurvePoint(x, value)
    if pt then
        ok = MSUF_A2_FastCall(curve.AddPoint, curve, pt)
        if ok then
            MSUF_A2_CurveAddMode = "point"
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CurveAddPoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:107:6"); return true
        end
    end

    MSUF_A2_CurveAddMode = "none"
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CurveAddPoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:107:6"); return false
end

local function MSUF_A2_GetGlobalFontRGB_Fallback() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_GetGlobalFontRGB_Fallback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:142:6");
    EnsureDB()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    if g and g.useCustomFontColor == true
       and type(g.fontColorCustomR) == "number"
       and type(g.fontColorCustomG) == "number"
       and type(g.fontColorCustomB) == "number"
    then
        return Perfy_Trace_Passthrough("Leave", "MSUF_A2_GetGlobalFontRGB_Fallback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:142:6", g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetGlobalFontRGB_Fallback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:142:6"); return 1, 1, 1
end

-- Master toggle (global): when disabled, aura cooldown text always uses the Safe color.
local function MSUF_A2_IsCooldownTextBucketColoringEnabled() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_IsCooldownTextBucketColoringEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:156:6");
    if MSUF_A2_BucketColoringEnabled ~= nil then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_IsCooldownTextBucketColoringEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:156:6"); return MSUF_A2_BucketColoringEnabled
    end
    EnsureDB()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    -- default = enabled
    MSUF_A2_BucketColoringEnabled = not (g and g.aurasCooldownTextUseBuckets == false)
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_IsCooldownTextBucketColoringEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:156:6"); return MSUF_A2_BucketColoringEnabled
end

local function Clamp01(v) Perfy_Trace(Perfy_GetTime(), "Enter", "Clamp01 file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:167:6");
    if v < 0 then Perfy_Trace(Perfy_GetTime(), "Leave", "Clamp01 file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:167:6"); return 0 end
    if v > 1 then Perfy_Trace(Perfy_GetTime(), "Leave", "Clamp01 file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:167:6"); return 1 end
    Perfy_Trace(Perfy_GetTime(), "Leave", "Clamp01 file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:167:6"); return v
end

local function NormalizeColorTable(t, fallbackR, fallbackG, fallbackB) Perfy_Trace(Perfy_GetTime(), "Enter", "NormalizeColorTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:173:6");
    if type(t) ~= "table" then
        return Perfy_Trace_Passthrough("Leave", "NormalizeColorTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:173:6", { fallbackR, fallbackG, fallbackB, 1 })
    end
    local r = t[1] or t.r or fallbackR
    local g = t[2] or t.g or fallbackG
    local b = t[3] or t.b or fallbackB
    local a = t[4] or t.a or 1
    if type(r) ~= "number" then r = fallbackR end
    if type(g) ~= "number" then g = fallbackG end
    if type(b) ~= "number" then b = fallbackB end
    if type(a) ~= "number" then a = 1 end
    return Perfy_Trace_Passthrough("Leave", "NormalizeColorTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:173:6", { Clamp01(r), Clamp01(g), Clamp01(b), Clamp01(a) })
end

local function MSUF_A2_EnsureCooldownTextColors() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_EnsureCooldownTextColors file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:188:6");
    if MSUF_A2_CooldownTextColors then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_EnsureCooldownTextColors file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:188:6"); return MSUF_A2_CooldownTextColors
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

    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_EnsureCooldownTextColors file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:188:6"); return MSUF_A2_CooldownTextColors
end

local function MSUF_A2_EnsureCooldownTextThresholds() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_EnsureCooldownTextThresholds file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:214:6");
    if MSUF_A2_CooldownTextThresholds then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_EnsureCooldownTextThresholds file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:214:6"); return MSUF_A2_CooldownTextThresholds
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

    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_EnsureCooldownTextThresholds file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:214:6"); return MSUF_A2_CooldownTextThresholds
end

local function MSUF_A2_GetCooldownTextColorForRemainingSeconds(rem) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_GetCooldownTextColorForRemainingSeconds file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:252:6");
    if type(rem) ~= "number" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetCooldownTextColorForRemainingSeconds file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:252:6"); return nil end
    if rem <= 0 then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetCooldownTextColorForRemainingSeconds file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:252:6"); return nil end

    local secrets = C_Secrets
    if secrets and type(secrets.IsSecret) == "function" and secrets.IsSecret(rem) == true then
        -- Do not compare/threshold secret numbers; use DurationObject + curve path instead.
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetCooldownTextColorForRemainingSeconds file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:252:6"); return nil
    end

    local t = MSUF_A2_EnsureCooldownTextThresholds()
    if not t then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetCooldownTextColorForRemainingSeconds file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:252:6"); return nil end

    if rem <= (t.expireSec or 0.25) then
        return Perfy_Trace_Passthrough("Leave", "MSUF_A2_GetCooldownTextColorForRemainingSeconds file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:252:6", (MSUF_A2_CooldownTextColors and MSUF_A2_CooldownTextColors.expire) or nil)
    elseif rem <= (t.urgSec or 5) then
        return Perfy_Trace_Passthrough("Leave", "MSUF_A2_GetCooldownTextColorForRemainingSeconds file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:252:6", (MSUF_A2_CooldownTextColors and MSUF_A2_CooldownTextColors.urgent) or nil)
    elseif rem <= (t.warnSec or 15) then
        return Perfy_Trace_Passthrough("Leave", "MSUF_A2_GetCooldownTextColorForRemainingSeconds file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:252:6", (MSUF_A2_CooldownTextColors and MSUF_A2_CooldownTextColors.warning) or nil)
    elseif rem <= (t.safeSec or 60) then
        return Perfy_Trace_Passthrough("Leave", "MSUF_A2_GetCooldownTextColorForRemainingSeconds file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:252:6", (MSUF_A2_CooldownTextColors and MSUF_A2_CooldownTextColors.safe) or nil)
    else
        return Perfy_Trace_Passthrough("Leave", "MSUF_A2_GetCooldownTextColorForRemainingSeconds file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:252:6", (MSUF_A2_CooldownTextColors and MSUF_A2_CooldownTextColors.normal) or nil)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetCooldownTextColorForRemainingSeconds file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:252:6"); end

local function MSUF_A2_EnsureCooldownColorCurve() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_EnsureCooldownColorCurve file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:278:6");
    -- nil = not built yet; false = unsupported (don't retry)
    if MSUF_A2_CooldownColorCurve ~= nil then
        return Perfy_Trace_Passthrough("Leave", "MSUF_A2_EnsureCooldownColorCurve file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:278:6", (MSUF_A2_CooldownColorCurve ~= false) and MSUF_A2_CooldownColorCurve or nil)
    end

    local curveUtil = C_CurveUtil
    if not curveUtil then
        MSUF_A2_CooldownColorCurve = false
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_EnsureCooldownColorCurve file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:278:6"); return nil
    end

    local createCurve = curveUtil.CreateColorCurve or curveUtil.CreateCurve
    if type(createCurve) ~= "function" then
        MSUF_A2_CooldownColorCurve = false
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_EnsureCooldownColorCurve file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:278:6"); return nil
    end

    local curve = createCurve()
    if not curve then
        MSUF_A2_CooldownColorCurve = false
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_EnsureCooldownColorCurve file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:278:6"); return nil
    end

    -- Step curve (bucket colors)
    if curve.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
        curve:SetType(Enum.LuaCurveType.Step)
    end

    local c = MSUF_A2_EnsureCooldownTextColors()
    local t = MSUF_A2_EnsureCooldownTextThresholds()
    if (not c) or (not t) or (type(CreateColor) ~= "function") then
        MSUF_A2_CooldownColorCurve = false
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_EnsureCooldownColorCurve file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:278:6"); return nil
    end

    local function C4(tab) Perfy_Trace(Perfy_GetTime(), "Enter", "C4 file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:314:10");
        if not tab then Perfy_Trace(Perfy_GetTime(), "Leave", "C4 file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:314:10"); return nil end
        return Perfy_Trace_Passthrough("Leave", "C4 file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:314:10", CreateColor(tab[1], tab[2], tab[3], tab[4] or 1))
    end

    local colExpire = C4(c.expire)  or C4(c.urgent)  or C4(c.warning) or C4(c.safe) or C4(c.normal)
    local colUrg    = C4(c.urgent)  or C4(c.warning) or C4(c.safe)    or C4(c.normal)
    local colWarn   = C4(c.warning) or C4(c.safe)    or C4(c.normal)
    local colSafe   = C4(c.safe)    or C4(c.normal)
    local colNorm   = C4(c.normal)

    if (not colExpire) or (not colUrg) or (not colWarn) or (not colSafe) or (not colNorm) then
        MSUF_A2_CooldownColorCurve = false
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_EnsureCooldownColorCurve file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:278:6"); return nil
    end

    local e = (t.expireSec or 0.25)
    local u = (t.urgSec or 5)
    local w = (t.warnSec or 15)
    local s = (t.safeSec or 60)

    -- Enforce monotonic X (step buckets)
    if u < e then u = e end
    if w < u then w = u end
    if s < w then s = w end

    local function AddColorPoint(x, color) Perfy_Trace(Perfy_GetTime(), "Enter", "AddColorPoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:340:10");
        if not curve.AddPoint then Perfy_Trace(Perfy_GetTime(), "Leave", "AddColorPoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:340:10"); return false end

        -- Some builds: AddPoint(x, color)
        if MSUF_A2_FastCall(curve.AddPoint, curve, x, color) then
            Perfy_Trace(Perfy_GetTime(), "Leave", "AddColorPoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:340:10"); return true
        end

        -- Some builds: AddPoint(point) where point = { x = <number>, y = <Color> }
        if MSUF_A2_FastCall(curve.AddPoint, curve, { x = x, y = color }) then
            Perfy_Trace(Perfy_GetTime(), "Leave", "AddColorPoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:340:10"); return true
        end

        -- Some builds: AddPoint(x, r, g, b, a)
        if color and color.GetRGBA then
            local r, g, b, a = color:GetRGBA()
            if MSUF_A2_FastCall(curve.AddPoint, curve, x, r, g, b, a) then
                Perfy_Trace(Perfy_GetTime(), "Leave", "AddColorPoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:340:10"); return true
            end
        end

        Perfy_Trace(Perfy_GetTime(), "Leave", "AddColorPoint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:340:10"); return false
    end

    if not (AddColorPoint(0, colExpire)
        and AddColorPoint(e, colUrg)
        and AddColorPoint(u, colWarn)
        and AddColorPoint(w, colSafe)
        and AddColorPoint(s, colNorm)) then
        MSUF_A2_CooldownColorCurve = false
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_EnsureCooldownColorCurve file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:278:6"); return nil
    end

    MSUF_A2_CooldownColorCurve = curve
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_EnsureCooldownColorCurve file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:278:6"); return curve
end

local function MSUF_A2_FormatCooldownTimeText(rem) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_FormatCooldownTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:377:6");
    rem = tonumber(rem)
    if not rem or rem <= 0 then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_FormatCooldownTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:377:6"); return "" end

    if rem < 10 then
        local v = math.floor(rem * 10 + 0.5) / 10
        local s = tostring(v)
        if not string.find(s, "%.", 1, true) then
            s = s .. ".0"
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_FormatCooldownTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:377:6"); return s
    elseif rem < 60 then
        return Perfy_Trace_Passthrough("Leave", "MSUF_A2_FormatCooldownTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:377:6", tostring(math.floor(rem + 0.5)))
    end

    if rem < 600 then
        local m = math.floor(rem / 60)
        local s = math.floor(rem - (m * 60))
        if s < 0 then s = 0 end
        if s < 10 then
            return Perfy_Trace_Passthrough("Leave", "MSUF_A2_FormatCooldownTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:377:6", tostring(m) .. ":0" .. tostring(s))
        end
        return Perfy_Trace_Passthrough("Leave", "MSUF_A2_FormatCooldownTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:377:6", tostring(m) .. ":" .. tostring(s))
    end

    if rem < 3600 then
        local m = math.floor(rem / 60 + 0.5)
        return Perfy_Trace_Passthrough("Leave", "MSUF_A2_FormatCooldownTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:377:6", tostring(m) .. "m")
    end

    local h = math.floor(rem / 3600 + 0.5)
    return Perfy_Trace_Passthrough("Leave", "MSUF_A2_FormatCooldownTimeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:377:6", tostring(h) .. "h")
end

-- ------------------------------------------------------------
-- Public controls: invalidate + recolor
-- ------------------------------------------------------------

local function MSUF_A2_InvalidateCooldownTextCurve() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_InvalidateCooldownTextCurve file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:415:6");
    MSUF_A2_CooldownColorCurve = nil
    MSUF_A2_CooldownTextColors = nil
    MSUF_A2_CooldownTextThresholds = nil
    MSUF_A2_BucketColoringEnabled = nil
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_InvalidateCooldownTextCurve file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:415:6"); end

local function MSUF_A2_ForceCooldownTextRecolor() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_ForceCooldownTextRecolor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:422:6");
    local mgr = MSUF_A2_CooldownTextMgr
    if not mgr or not mgr.active then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_ForceCooldownTextRecolor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:422:6"); return end

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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_ForceCooldownTextRecolor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:422:6"); end

CT.InvalidateCurve = MSUF_A2_InvalidateCooldownTextCurve
CT.ForceRecolor    = MSUF_A2_ForceCooldownTextRecolor

-- Keep old external entry points.
API.InvalidateCooldownTextCurve = API.InvalidateCooldownTextCurve or MSUF_A2_InvalidateCooldownTextCurve
API.ForceCooldownTextRecolor    = API.ForceCooldownTextRecolor    or MSUF_A2_ForceCooldownTextRecolor

if _G and type(_G.MSUF_A2_InvalidateCooldownTextCurve) ~= "function" then
    _G.MSUF_A2_InvalidateCooldownTextCurve = function() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_A2_InvalidateCooldownTextCurve file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:504:45"); return Perfy_Trace_Passthrough("Leave", "_G.MSUF_A2_InvalidateCooldownTextCurve file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:504:45", API.InvalidateCooldownTextCurve()) end
end
if _G and type(_G.MSUF_A2_ForceCooldownTextRecolor) ~= "function" then
    _G.MSUF_A2_ForceCooldownTextRecolor = function() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_A2_ForceCooldownTextRecolor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:507:42"); return Perfy_Trace_Passthrough("Leave", "_G.MSUF_A2_ForceCooldownTextRecolor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:507:42", API.ForceCooldownTextRecolor()) end
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

local function MSUF_A2_CooldownTextMgr_StopIfIdle() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_CooldownTextMgr_StopIfIdle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:521:6");
    if MSUF_A2_CooldownTextMgr.count > 0 then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CooldownTextMgr_StopIfIdle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:521:6"); return end
    MSUF_A2_CooldownTextMgr.count = 0
    local f = MSUF_A2_CooldownTextMgr.frame
    if f then
        f:SetScript("OnUpdate", nil)
        f:Hide()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CooldownTextMgr_StopIfIdle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:521:6"); end

local function MSUF_A2_CooldownTextMgr_EnsureFrame() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_CooldownTextMgr_EnsureFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:531:6");
    local f = MSUF_A2_CooldownTextMgr.frame
    if f then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CooldownTextMgr_EnsureFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:531:6"); return f end
    f = CreateFrame("Frame")
    f:Hide()
    MSUF_A2_CooldownTextMgr.frame = f
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CooldownTextMgr_EnsureFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:531:6"); return f
end

local function MSUF_A2_CooldownTextMgr_OnUpdate(_, elapsed) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_CooldownTextMgr_OnUpdate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:540:6");
    local mgr = MSUF_A2_CooldownTextMgr
    mgr.acc = mgr.acc + (elapsed or 0)
    if mgr.acc < 0.10 then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CooldownTextMgr_OnUpdate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:540:6"); return end -- 10 Hz
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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CooldownTextMgr_OnUpdate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:540:6"); end

local function MSUF_A2_CooldownTextMgr_RegisterIcon(icon) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_CooldownTextMgr_RegisterIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:662:6");
    local cd = icon and icon.cooldown
    if not cd then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CooldownTextMgr_RegisterIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:662:6"); return end

    if MSUF_A2_CooldownTextMgr.active[cd] then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CooldownTextMgr_RegisterIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:662:6"); return
    end

    MSUF_A2_CooldownTextMgr.active[cd] = icon
    MSUF_A2_CooldownTextMgr.count = MSUF_A2_CooldownTextMgr.count + 1
    icon._msufA2_cdMgrRegistered = true

    local f = MSUF_A2_CooldownTextMgr_EnsureFrame()
    if MSUF_A2_CooldownTextMgr.count ~= 1 then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CooldownTextMgr_RegisterIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:662:6"); return
    end

    MSUF_A2_CooldownTextMgr.acc = 0
    f:Show()
    f:SetScript("OnUpdate", MSUF_A2_CooldownTextMgr_OnUpdate)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CooldownTextMgr_RegisterIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:662:6"); end

local function MSUF_A2_CooldownTextMgr_UnregisterIcon(icon) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_CooldownTextMgr_UnregisterIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:684:6");
    local cd = icon and icon.cooldown
    if not cd then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CooldownTextMgr_UnregisterIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:684:6"); return end
    if not MSUF_A2_CooldownTextMgr.active[cd] then
        icon._msufA2_cdMgrRegistered = false
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CooldownTextMgr_UnregisterIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:684:6"); return
    end
    MSUF_A2_CooldownTextMgr.active[cd] = nil
    MSUF_A2_CooldownTextMgr.count = MSUF_A2_CooldownTextMgr.count - 1
    if MSUF_A2_CooldownTextMgr.count < 0 then MSUF_A2_CooldownTextMgr.count = 0 end
    icon._msufA2_cdMgrRegistered = false
    MSUF_A2_CooldownTextMgr_StopIfIdle()
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CooldownTextMgr_UnregisterIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua:684:6"); end

CT.RegisterIcon   = MSUF_A2_CooldownTextMgr_RegisterIcon
CT.UnregisterIcon = MSUF_A2_CooldownTextMgr_UnregisterIcon

-- Convenience aliases (Render expects these names to exist as locals after it binds them)
API.CooldownText = CT


Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Auras2/MSUF_A2_CooldownText.lua");