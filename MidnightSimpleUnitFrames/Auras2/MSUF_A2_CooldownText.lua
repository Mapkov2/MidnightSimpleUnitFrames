-- MSUF_A2_CooldownText.lua
-- Auras 2.0 (Midnight/Beta): Secret-safe cooldown text coloring.
--
-- This implementation is tuned for maximum runtime performance:
--   * 0 protected-call wrappers
--   * No custom time formatting / no text overrides (no abbreviations)
--   * No per-icon remaining-seconds math (secret-safe by design)
--   * Discrete scheduled tick manager (no per-frame OnUpdate)
--   * Cached Cooldown FontString lookup (EnumerateRegions, no table alloc)

local addonName, ns = ...

ns = (rawget(_G, "MSUF_NS") or ns) or {}
ns.MSUF_Auras2 = ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

API.CooldownText = API.CooldownText or {}
local CT = API.CooldownText

local _G = _G
local type = _G.type
local CreateFrame = _G.CreateFrame
local CreateColor = _G.CreateColor
local GetTime = _G.GetTime
local tonumber = _G.tonumber
local strmatch = _G.string and _G.string.match
local strlower = _G.string and _G.string.lower

local C_CurveUtil = _G.C_CurveUtil
local C_Timer = _G.C_Timer

local C_Secrets = _G.C_Secrets

-- Step 6 perf: lightweight secret-value check. issecretvalue() is a single C-function call,
-- much cheaper than C_Secrets.IsSecret() which goes through namespace resolution.
-- Fallback to C_Secrets.IsSecret if issecretvalue isn't available yet (load-order defense).
local issecretvalue = _G.issecretvalue
    or (C_Secrets and type(C_Secrets.IsSecret) == "function" and C_Secrets.IsSecret)
    or nil

-- ------------------------------------------------------------
-- Secret mode detection (cached; avoids secret-value compares)
-- ------------------------------------------------------------

local _secretMode = false
local _secretNextCheck = 0
local SECRET_CHECK_INTERVAL = 0.50

local function IsSecretMode(now)
    if not C_Secrets or type(C_Secrets.ShouldAurasBeSecret) ~= "function" then
        return false
    end
    if type(now) ~= "number" then
        now = GetTime()
    end
    if now >= (_secretNextCheck or 0) then
        _secretNextCheck = now + SECRET_CHECK_INTERVAL
        -- ShouldAurasBeSecret() is cheap and avoids per-aura IsSecret checks.
        _secretMode = (C_Secrets.ShouldAurasBeSecret() == true)
    end
    return _secretMode == true
end

-- ------------------------------------------------------------
-- DB access (cheap + load-order safe)
-- ------------------------------------------------------------

local function EnsureDB()
    if API and API.EnsureDB then
        API.EnsureDB()
        return
    end
    if API and API.DB and API.DB.RebuildCache and API.GetDB then
        -- Fallback for odd load order (should be rare)
        local a2, s = API.GetDB()
        if a2 and s then
            API.DB.RebuildCache(a2, s)
        end
    end
end

local function GetGeneral()
    local db = _G and _G.MSUF_DB
    local g = db and db.general
    if type(g) ~= "table" then
        return nil
    end
    return g
end

local function ReadColor(t, defR, defG, defB, defA)
    if type(t) ~= "table" then
        return defR, defG, defB, defA
    end

    local r = t[1]; if r == nil then r = t.r end
    local g = t[2]; if g == nil then g = t.g end
    local b = t[3]; if b == nil then b = t.b end
    local a = t[4]; if a == nil then a = t.a end

    if type(r) ~= "number" then r = defR end
    if type(g) ~= "number" then g = defG end
    if type(b) ~= "number" then b = defB end
    if type(a) ~= "number" then a = defA end

    return r, g, b, a
end

-- ------------------------------------------------------------
-- Cooldown fontstring discovery (no table alloc)
-- ------------------------------------------------------------

local function MSUF_A2_GetCooldownFontString(icon, now)
    local cd = icon and icon.cooldown
    if not cd then
        return nil
    end

    local cached = cd._msufCooldownFontString
    if cached == false then
        return nil
    end
    if cached then
        return cached
    end

    -- Cooldown count text can be created lazily; retry at a low frequency.
    local retryAt = cd._msufCooldownFontStringRetryAt
    if type(retryAt) == "number" and type(now) == "number" and now < retryAt then
        return nil
    end

    if cd.EnumerateRegions then
        for region in cd:EnumerateRegions() do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                cd._msufCooldownFontString = region
                cd._msufCooldownFontStringRetryAt = nil
                return region
            end
        end
    else
        -- Rare fallback: one-time pack (only if EnumerateRegions is not available)
        local regions = { cd:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                cd._msufCooldownFontString = region
                cd._msufCooldownFontStringRetryAt = nil
                return region
            end
        end
    end

    -- Cache miss; retry later.
    cd._msufCooldownFontStringRetryAt = (type(now) == "number" and (now + 0.50)) or nil
    cd._msufCooldownFontString = false
    return nil
end

CT.GetCooldownFontString = MSUF_A2_GetCooldownFontString

if _G and type(_G.MSUF_A2_GetCooldownFontString) ~= "function" then
    _G.MSUF_A2_GetCooldownFontString = function(icon)
        return MSUF_A2_GetCooldownFontString(icon, GetTime())
    end
end

-- ------------------------------------------------------------
-- Settings cache + curve
-- ------------------------------------------------------------

local settingsDirty = true
local bucketsEnabled = true
local safeR, safeG, safeB, safeA = 1, 1, 1, 1
local normalR, normalG, normalB, normalA = 1, 1, 1, 1
local warnR, warnG, warnB, warnA = 1, 0.85, 0.2, 1
local urgR,  urgG,  urgB,  urgA  = 1, 0.45, 0.1, 1
local expR,  expG,  expB,  expA  = 1, 0.12, 0.12, 1
local curve = nil

-- Threshold cache (seconds). Used for secret-safe text parsing fallback.
local thrSafeSeconds = 60
local thrWarnSeconds = 15
local thrUrgSeconds  = 5

-- Step 6 perf: per-icon evaluation skip durations (seconds) based on color bucket.
-- Icons in stable buckets don't need EvaluateRemainingDuration every tick.
local SKIP_NORMAL = 5.0   -- >safeSeconds: color is static for a long time
local SKIP_SAFE   = 2.0   -- warnSeconds..safeSeconds: color is static for seconds

local function BuildCurve(g)
    curve = nil

    if not (C_CurveUtil and type(C_CurveUtil.CreateColorCurve) == "function") then
        return
    end
    if type(CreateColor) ~= "function" then
        return
    end

    local c = C_CurveUtil.CreateColorCurve()
    if not c then
        return
    end

    if c.SetType and _G.Enum and _G.Enum.LuaCurveType and _G.Enum.LuaCurveType.Step then
        c:SetType(_G.Enum.LuaCurveType.Step)
    end

    -- Thresholds are already clamped/ordered in Render.lua when DB is validated.
    local safeSeconds = g and g.aurasCooldownTextSafeSeconds or 60
    local warnSeconds = g and g.aurasCooldownTextWarningSeconds or 15
    local urgSeconds  = g and g.aurasCooldownTextUrgentSeconds or 5

    -- Colors (stored as plain SV numbers; no clamping here for speed)
    local safeCR, safeCG, safeCB, safeCA = ReadColor(g and g.aurasCooldownTextSafeColor, safeR, safeG, safeB, safeA)
    local warnCR, warnCG, warnCB, warnCA = ReadColor(g and g.aurasCooldownTextWarningColor, 1, 0.85, 0.2, 1)
    local urgCR,  urgCG,  urgCB,  urgCA  = ReadColor(g and g.aurasCooldownTextUrgentColor, 1, 0.45, 0.1, 1)
    local expCR,  expCG,  expCB,  expCA  = ReadColor(g and g.aurasCooldownTextExpireColor, 1, 0.12, 0.12, 1)

    local safeCol   = CreateColor(safeCR, safeCG, safeCB, safeCA)
    local warnCol   = CreateColor(warnCR, warnCG, warnCB, warnCA)
    local urgentCol = CreateColor(urgCR,  urgCG,  urgCB,  urgCA)
    local expireCol = CreateColor(expCR,  expCG,  expCB,  expCA)
    local normalCol = CreateColor(normalR, normalG, normalB, normalA)

    -- Step curve points (remaining seconds -> color)
    c:AddPoint(0, expireCol)
    c:AddPoint(0.25, urgentCol)
    c:AddPoint(urgSeconds, warnCol)
    c:AddPoint(warnSeconds, safeCol)
    c:AddPoint(safeSeconds, normalCol)

    curve = c
end

local function EnsureSettings()
    if not settingsDirty then
        return
    end

    settingsDirty = false
    EnsureDB()

    local g = GetGeneral()

    bucketsEnabled = not (g and g.aurasCooldownTextUseBuckets == false)

    -- Thresholds (used by curve + secret-safe text fallback).
    do
        local ss = g and g.aurasCooldownTextSafeSeconds or 60
        local ws = g and g.aurasCooldownTextWarningSeconds or 15
        local us = g and g.aurasCooldownTextUrgentSeconds or 5

        if type(ss) ~= "number" then ss = 60 end
        if type(ws) ~= "number" then ws = 15 end
        if type(us) ~= "number" then us = 5 end

        -- Keep ordering sane (Render.lua should already validate this; this is a cheap safety net)
        if ws > ss then ws = ss end
        if us > ws then us = ws end
        if us < 0 then us = 0 end

        thrSafeSeconds = ss
        thrWarnSeconds = ws
        thrUrgSeconds  = us
    end

    -- Base/normal color: custom font color if enabled, else white.
    if g and g.useCustomFontColor == true then
        local r = g.fontColorCustomR
        local gg = g.fontColorCustomG
        local b = g.fontColorCustomB
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            normalR, normalG, normalB = r, gg, b
            normalA = 1
        else
            normalR, normalG, normalB, normalA = 1, 1, 1, 1
        end
    else
        normalR, normalG, normalB, normalA = 1, 1, 1, 1
    end

    safeR, safeG, safeB, safeA = ReadColor(g and g.aurasCooldownTextSafeColor, normalR, normalG, normalB, normalA)

    warnR, warnG, warnB, warnA = ReadColor(g and g.aurasCooldownTextWarningColor, 1, 0.85, 0.2, 1)
    urgR,  urgG,  urgB,  urgA  = ReadColor(g and g.aurasCooldownTextUrgentColor, 1, 0.45, 0.1, 1)
    expR,  expG,  expB,  expA  = ReadColor(g and g.aurasCooldownTextExpireColor, 1, 0.12, 0.12, 1)

    if bucketsEnabled then
        BuildCurve(g)
    else
        curve = nil
    end
end

-- Public invalidation (Options -> calls this)
local function MSUF_A2_InvalidateCooldownTextCurve()
    settingsDirty = true
end

local function MSUF_A2_ForceCooldownTextRecolor()
    -- Step 6 perf: clear all per-icon skips and cached colors (bucket thresholds may have changed).
    local mgr = CT._mgr
    if mgr and mgr.count > 0 then
        for j = 1, mgr.count do
            local ic = mgr.icons[j]
            if ic then
                ic._msufA2_cdSkipUntil = nil
                ic._msufA2_cdLastR = nil
                ic._msufA2_cdLastG = nil
                ic._msufA2_cdLastB = nil
                ic._msufA2_cdLastA = nil
            end
        end
        if mgr._Schedule then
            mgr._Schedule(0)
        end
    end
end

CT.InvalidateCurve = MSUF_A2_InvalidateCooldownTextCurve
CT.ForceRecolor = MSUF_A2_ForceCooldownTextRecolor

API.InvalidateCooldownTextCurve = API.InvalidateCooldownTextCurve or MSUF_A2_InvalidateCooldownTextCurve
API.ForceCooldownTextRecolor = API.ForceCooldownTextRecolor or MSUF_A2_ForceCooldownTextRecolor

if _G and type(_G.MSUF_A2_InvalidateCooldownTextCurve) ~= "function" then
    _G.MSUF_A2_InvalidateCooldownTextCurve = function()
        return API.InvalidateCooldownTextCurve()
    end
end

if _G and type(_G.MSUF_A2_ForceCooldownTextRecolor) ~= "function" then
    _G.MSUF_A2_ForceCooldownTextRecolor = function()
        return API.ForceCooldownTextRecolor()
    end
end

-- ------------------------------------------------------------
-- Cooldown Text Manager (timer-scheduled; no per-frame OnUpdate)
--
-- Why:
--   Even with an accumulator, a Frame OnUpdate still runs every frame,
--   doing work (elapsed adds + branches) while the raid is idle.
--   This manager uses C_Timer to schedule discrete ticks only when needed.
--   Net result: near-zero idle CPU with many visible auras.
-- ------------------------------------------------------------

local function EnsureMgr()
    local mgr = CT._mgr
    if mgr then
        return mgr
    end

    mgr = {
        icons = {},
        count = 0,
        -- Discrete tick scheduling (no per-frame OnUpdate)
        timer = nil,
        timerGen = 0,
        slowInterval = 0.50, -- 2 Hz in normal mode (big idle CPU win in raids)
        fastInterval = 0.10, -- 10 Hz when a timer is in warning/urgent/expire bucket
        secretInterval = 0.20, -- 5 Hz in SecretMode (colors still animate; less CPU than 10 Hz)
        interval = 0.50,
        fastUntil = 0,
    }

    CT._mgr = mgr

    local function CancelTimer()
        local t = mgr.timer
        if t and t.Cancel then
            t:Cancel()
        end
        mgr.timer = nil
        -- Guard for C_Timer.After fallback: invalidate any already-queued callbacks.
        mgr.timerGen = (mgr.timerGen or 0) + 1
    end

    local function StopIfIdle()
        if mgr.count > 0 then
            return
        end
        CancelTimer()
    end

    local function RemoveAt(i)
        local last = mgr.count
        local icon = mgr.icons[i]
        local swap = mgr.icons[last]

        mgr.icons[i] = swap
        mgr.icons[last] = nil
        mgr.count = last - 1

        if swap then
            swap._msufA2_cdMgrIndex = i
        end
        if icon then
            icon._msufA2_cdMgrIndex = nil
            icon._msufA2_cdMgrRegistered = false
            icon._msufA2_cdLastFS = nil
            icon._msufA2_cdLastR = nil
            icon._msufA2_cdLastG = nil
            icon._msufA2_cdLastB = nil
            icon._msufA2_cdLastA = nil
            icon._msufA2_cdSkipUntil = nil
            icon._msufA2_cdLastSecret = nil
        end

        if mgr.count <= 0 then
            StopIfIdle()
        end
    end

    local function Tick()
        EnsureSettings()

        local now = GetTime()

        local secretsActive = IsSecretMode(now)

        -- If we recently saw a warning/urgent/expire bucket, keep fast ticking briefly.
        local wantFast = (now < (mgr.fastUntil or 0))

        -- Step 6 perf: lazy-resolve secret-check function once per Tick.
        -- issecretvalue may have been nil at module load due to load-order; re-check _G.
        -- If still nil → pre-12.0 client where secret values don't exist → == is safe.
        local isv = issecretvalue
        if not isv then
            isv = _G.issecretvalue
                or (C_Secrets and type(C_Secrets.IsSecret) == "function" and C_Secrets.IsSecret)
                or nil
            if isv then
                issecretvalue = isv -- cache for future ticks
            end
        end

        -- Load-order edge case: if aura secret mode is active but issecretvalue() isn't
        -- available yet, we must assume returned values could be secret and avoid any
        -- value comparisons (safety > colors until the next tick).
        local secretNoDetector = (secretsActive and not isv)

        -- Step 6 perf: per-icon secret check uses isv(r) — ONE C-call per evaluated
        -- icon instead of the original 4× C_Secrets.IsSecret(r/g/b/a).
        -- Only r is checked: if r is secret from GetRGBA(), g/b/a from the same
        -- Color object will be too. Icons in skip (NORMAL/SAFE bucket) don't reach
        -- the evaluation path at all, reducing total calls to ~5-8 per tick.
        --
        -- IMPORTANT: different Duration Objects can have different secret states
        -- (e.g. non-secret buff + secret debuff). Per-icon check is required.

        -- Iterate backwards so removals are O(1) without skipping.
        local i = mgr.count
        while i > 0 do
            local icon = mgr.icons[i]

            if not icon or not icon.cooldown or not icon.IsShown or not icon:IsShown() then
                RemoveAt(i)
            elseif icon._msufA2_hideCDNumbers ~= true then
                local cd = icon.cooldown

                local fs = cd._msufCooldownFontString
                if fs == false then
                    fs = nil
                end
                if not fs then
                    fs = MSUF_A2_GetCooldownFontString(icon, now)
                    if fs then
                        cd._msufCooldownFontString = fs
                    end
                end

                if fs then
                    -- Step 6 perf: per-icon evaluation skip.
                    -- Icons in NORMAL or SAFE buckets don't need EvaluateRemainingDuration
                    -- every tick because their color is constant until the next threshold.
                    local skipUntil = icon._msufA2_cdSkipUntil
                    if skipUntil and now < skipUntil then
                        -- Bucket hasn't changed since last eval → nothing to do.
                        -- (fs and color were already set on the last real evaluation.)
                    else
                                                -- Full evaluation path (same bucket result as before, just less frequent).
                        local r, g, b, a = safeR, safeG, safeB, safeA
                        local bucket = 3 -- safe (default)
                        local iconSecret = false
                        local didCurveEval = false

                        if bucketsEnabled and curve then
                            local obj = icon._msufA2_cdDurationObj or cd._msufA2_durationObj
                            if obj and type(obj.EvaluateRemainingDuration) == 'function' then
                                local col = obj:EvaluateRemainingDuration(curve)
                                if col then
                                    didCurveEval = true
                                    if col.GetRGBA then
                                        r, g, b, a = col:GetRGBA()
                                    elseif col.GetRGB then
                                        r, g, b = col:GetRGB()
                                        a = 1
                                    end
                                end
                            end
                        end

                        -- Secret handling:
                        -- 1) If cooldown queries are secret but we can't detect secret values yet,
                        --    treat as secret to avoid any comparisons/caching mistakes.
                        -- 2) If curve evaluation returned secret values, we still APPLY them via
                        --    SetTextColor/SetVertexColor (C-side) but we must not diff/compare them.
                        if secretsActive and secretNoDetector then
                            iconSecret = true
                        elseif isv and isv(r) then
                            iconSecret = true
                        end

                        -- If curve is missing or evaluation failed, stay on SAFE color.
                        if bucketsEnabled and (not curve or not didCurveEval) then
                            r, g, b, a = safeR, safeG, safeB, safeA
                            if secretsActive then
                                iconSecret = true
                            end
                            bucket = 3
                        end

                        -- Identify bucket by color match (non-secret only) → sets wantFast.
                        if (not iconSecret) and bucketsEnabled then
                            if r == expR and g == expG and b == expB then
                                bucket = 0
                                wantFast = true
                            elseif r == urgR and g == urgG and b == urgB then
                                bucket = 1
                                wantFast = true
                            elseif r == warnR and g == warnG and b == warnB then
                                bucket = 2
                                wantFast = true
                            elseif r == normalR and g == normalG and b == normalB then
                                bucket = 4
                            else
                                bucket = 3 -- safe (default/fallback)
                            end
                        end

                        -- In secret mode we can't diff RGBA. Tick fast enough to keep curve transitions visible.
                        if iconSecret and bucketsEnabled then
                            wantFast = true
                        end
                        -- Set per-icon skip for stable buckets.
                        -- (bucket identification is best-effort for skip/wantFast only;
                        --  if Color precision causes a mismatch, bucket defaults to 3
                        --  which gives a conservative 2s skip — safe and still beneficial.)
                        if iconSecret then
                            icon._msufA2_cdSkipUntil = nil -- secret: re-evaluate each tick
                        elseif bucket == 4 then
                            icon._msufA2_cdSkipUntil = now + SKIP_NORMAL
                        elseif bucket == 3 then
                            icon._msufA2_cdSkipUntil = now + SKIP_SAFE
                        else
                            icon._msufA2_cdSkipUntil = nil -- warn/urgent/expire: evaluate every tick
                        end

                        -- SetTextColor diff: use actual RGBA values, not integer bucket.
                        -- CreateColor/GetRGBA round-trip may not produce exact matches
                        -- with module-level cached floats, so bucket==bucket can't replace
                        -- r==lastR for SetTextColor decisions.
                        if iconSecret then
                            -- Secret RGBA: we cannot safely diff/compare, so apply every evaluation tick.
                            icon._msufA2_cdLastFS = fs
                            icon._msufA2_cdLastSecret = true
                            icon._msufA2_cdLastR = nil
                            icon._msufA2_cdLastG = nil
                            icon._msufA2_cdLastB = nil
                            icon._msufA2_cdLastA = nil

                            if fs.SetTextColor then
                                fs:SetTextColor(r, g, b, a)
                            elseif fs.SetVertexColor then
                                fs:SetVertexColor(r, g, b, a)
                            end
                        else
                            icon._msufA2_cdLastSecret = false

                            if icon._msufA2_cdLastFS ~= fs
                                or icon._msufA2_cdLastR ~= r
                                or icon._msufA2_cdLastG ~= g
                                or icon._msufA2_cdLastB ~= b
                                or icon._msufA2_cdLastA ~= a then

                                icon._msufA2_cdLastFS = fs
                                icon._msufA2_cdLastR = r
                                icon._msufA2_cdLastG = g
                                icon._msufA2_cdLastB = b
                                icon._msufA2_cdLastA = a

                                if fs.SetTextColor then
                                    fs:SetTextColor(r, g, b, a)
                                elseif fs.SetVertexColor then
                                    fs:SetVertexColor(r, g, b, a)
                                end
                            end
                        end
                        end -- skipUntil check

                end
            end

            i = i - 1
        end

        if wantFast then
            mgr.fastUntil = now + 1.50
            if secretsActive then
                mgr.interval = mgr.secretInterval or mgr.fastInterval or 0.10
            else
                mgr.interval = mgr.fastInterval or 0.10
            end
        else
            mgr.interval = mgr.slowInterval or 0.50
        end

        StopIfIdle()

        -- Reschedule next discrete tick (if still active)
        if mgr.count > 0 and mgr._Schedule then
            mgr._Schedule(mgr.interval)
        end
    end

    local function Schedule(delay)
        if mgr.count <= 0 then
            StopIfIdle()
            return
        end

        if type(delay) ~= "number" or delay < 0 then
            delay = 0
        end

        -- Replace any pending timer.
        CancelTimer()

        local timerAPI = C_Timer
        if timerAPI and type(timerAPI.NewTimer) == "function" then
            mgr.timer = timerAPI.NewTimer(delay, function()
                mgr.timer = nil
                Tick()
            end)
            return
        end

        -- Fallback (older clients): After() has no cancel; use a generation guard.
        if timerAPI and type(timerAPI.After) == "function" then
            mgr.timerGen = (mgr.timerGen or 0) + 1
            local gen = mgr.timerGen
            timerAPI.After(delay, function()
                if mgr.timerGen ~= gen then
                    return
                end
                Tick()
            end)
        end
    end

    mgr._StopIfIdle = StopIfIdle
    mgr._RemoveAt = RemoveAt
    mgr._Tick = Tick
    mgr._Schedule = Schedule

    return mgr
end

local function RegisterIcon(icon)
    if not icon or not icon.cooldown then
        return
    end

    if icon._msufA2_cdMgrRegistered == true then
        return
    end

    local mgr = EnsureMgr()

    local idx = mgr.count + 1
    mgr.count = idx
    mgr.icons[idx] = icon

    icon._msufA2_cdMgrRegistered = true
    icon._msufA2_cdMgrIndex = idx

    if mgr.count == 1 then
        if mgr._Schedule then
            mgr._Schedule(0)
        end
    end
end

local function UnregisterIcon(icon)
    if not icon or icon._msufA2_cdMgrRegistered ~= true then
        if icon then
            icon._msufA2_cdMgrIndex = nil
            icon._msufA2_cdMgrRegistered = false
        end
        return
    end

    local mgr = CT._mgr
    if not mgr or mgr.count <= 0 then
        icon._msufA2_cdMgrIndex = nil
        icon._msufA2_cdMgrRegistered = false
        return
    end

    local idx = icon._msufA2_cdMgrIndex
    if type(idx) == "number" and idx >= 1 and idx <= mgr.count then
        mgr._RemoveAt(idx)
        return
    end

    -- Fallback: rare desync (no search by default; just mark inactive)
    icon._msufA2_cdMgrIndex = nil
    icon._msufA2_cdMgrRegistered = false
end

local function UnregisterAll()
    local mgr = CT._mgr
    if not mgr then
        return
    end

    for i = 1, mgr.count do
        local icon = mgr.icons[i]
        if icon then
            icon._msufA2_cdMgrIndex = nil
            icon._msufA2_cdMgrRegistered = false
        end
        mgr.icons[i] = nil
    end

    mgr.count = 0
    if mgr.timer and mgr.timer.Cancel then
        mgr.timer:Cancel()
    end
    mgr.timer = nil
    mgr.timerGen = (mgr.timerGen or 0) + 1
end

local function TouchIcon(icon)
    -- Step 6 perf: clear per-icon evaluation skip so the next Tick() re-evaluates
    -- this icon immediately (called when a duration object is reattached).
    if icon then
        icon._msufA2_cdSkipUntil = nil
    end
    local mgr = CT._mgr
    if mgr and mgr.count > 0 then
        -- Tick ASAP (used when Options change or duration objects are reattached).
        if mgr._Schedule then
            mgr._Schedule(0)
        end
    end
end

CT.RegisterIcon = RegisterIcon
CT.UnregisterIcon = UnregisterIcon
CT.UnregisterAll = UnregisterAll
CT.TouchIcon = TouchIcon

-- Convenience alias
API.CooldownText = CT

-- ------------------------------------------------------------
-- Cold-start resync (load-order safe)
-- ------------------------------------------------------------

local function ProcessPending()
    local st = API and API.state
    local pending = st and st._msufA2_cdPending
    if type(pending) ~= "table" then
        return
    end

    for i = 1, #pending do
        local icon = pending[i]
        pending[i] = nil
        if icon and icon._msufA2_cdMgrRegistered ~= true and icon._msufA2_hideCDNumbers ~= true then
            RegisterIcon(icon)
        end
        if icon then
            icon._msufA2_cdPending = nil
        end
    end
end

local function ScanAndRegisterExisting()
    local st = API and API.state
    local byUnit = st and st.aurasByUnit
    if type(byUnit) ~= "table" then
        return
    end

    for _, entry in pairs(byUnit) do
        if type(entry) == "table" then
            local cont = entry.buffs
            if cont and type(cont._msufIcons) == "table" then
                local icons = cont._msufIcons
                for i = 1, #icons do
                    local icon = icons[i]
                    if icon
                        and icon._msufA2_cdMgrRegistered ~= true
                        and icon._msufA2_hideCDNumbers ~= true
                        and icon.IsShown and icon:IsShown()
                        and icon.cooldown
                        and (icon._msufA2_cdDurationObj ~= nil or icon.cooldown._msufA2_durationObj ~= nil)
                    then
                        RegisterIcon(icon)
                    end
                end
            end

            cont = entry.debuffs
            if cont and type(cont._msufIcons) == "table" then
                local icons = cont._msufIcons
                for i = 1, #icons do
                    local icon = icons[i]
                    if icon
                        and icon._msufA2_cdMgrRegistered ~= true
                        and icon._msufA2_hideCDNumbers ~= true
                        and icon.IsShown and icon:IsShown()
                        and icon.cooldown
                        and (icon._msufA2_cdDurationObj ~= nil or icon.cooldown._msufA2_durationObj ~= nil)
                    then
                        RegisterIcon(icon)
                    end
                end
            end

            cont = entry.mixed
            if cont and type(cont._msufIcons) == "table" then
                local icons = cont._msufIcons
                for i = 1, #icons do
                    local icon = icons[i]
                    if icon
                        and icon._msufA2_cdMgrRegistered ~= true
                        and icon._msufA2_hideCDNumbers ~= true
                        and icon.IsShown and icon:IsShown()
                        and icon.cooldown
                        and (icon._msufA2_cdDurationObj ~= nil or icon.cooldown._msufA2_durationObj ~= nil)
                    then
                        RegisterIcon(icon)
                    end
                end
            end
        end
    end
end

CT.ProcessPending = ProcessPending
CT.ScanExisting = ScanAndRegisterExisting

-- ------------------------------------------------------------
-- Combat flip recolor
--
-- In Midnight 12.0 the aura "secret mode" commonly toggles with combat state.
-- Our manager uses per-icon skip windows; without a forced refresh, a combat
-- transition could keep the previous bucket's color for up to SKIP_* seconds.
--
-- This hook is extremely cheap (fires twice per combat) and keeps colors
-- consistent with out-of-combat behavior.
-- ------------------------------------------------------------

do
    if not CT._recolorEventFrame and type(CreateFrame) == "function" then
        local f = CreateFrame("Frame")
        CT._recolorEventFrame = f

        if f.RegisterEvent then
            f:RegisterEvent("PLAYER_REGEN_DISABLED")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:RegisterEvent("PLAYER_ENTERING_WORLD")
        end

        if f.SetScript then
            f:SetScript("OnEvent", function()
                local mgr = CT._mgr
                if mgr and mgr.count and mgr.count > 0 then
                    MSUF_A2_ForceCooldownTextRecolor()
                end
            end)
        end
    end
end

-- Run now (common case: this module loads after Render/Apply)
ProcessPending()
ScanAndRegisterExisting()

-- Run once on next frame (reverse load order)
if C_Timer and type(C_Timer.After) == "function" then
    C_Timer.After(0, function()
        ProcessPending()
        ScanAndRegisterExisting()
    end)
end