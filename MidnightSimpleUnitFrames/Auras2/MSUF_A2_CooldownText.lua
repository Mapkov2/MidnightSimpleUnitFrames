-- MSUF_A2_CooldownText.lua
-- Auras 2.0 (Midnight/Beta): Secret-safe cooldown text coloring.
--
-- This implementation is tuned for maximum runtime performance:
--   * 0 protected-call wrappers
--   * No custom time formatting / no text overrides (no abbreviations)
--   * No per-icon remaining-seconds math (secret-safe by design)
--   * Single OnUpdate manager (10 Hz) with numeric icon list
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

local C_CurveUtil = _G.C_CurveUtil
local C_Timer = _G.C_Timer

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
local curve = nil

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
    -- Force an immediate manager tick.
    local mgr = CT._mgr
    if mgr and mgr.count > 0 then
        mgr.acc = 0.10
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
-- Cooldown Text Manager (single OnUpdate, 10 Hz)
-- ------------------------------------------------------------

local function EnsureMgr()
    local mgr = CT._mgr
    if mgr then
        return mgr
    end

    mgr = {
        frame = nil,
        icons = {},
        count = 0,
        acc = 0,
    }

    CT._mgr = mgr

    local f = CreateFrame("Frame")
    f:Hide()
    mgr.frame = f

    local function StopIfIdle()
        if mgr.count > 0 then
            return
        end
        mgr.acc = 0
        f:SetScript("OnUpdate", nil)
        f:Hide()
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
        end

        if mgr.count <= 0 then
            StopIfIdle()
        end
    end

    local function OnUpdate(_, elapsed)
        mgr.acc = mgr.acc + (elapsed or 0)
        if mgr.acc < 0.10 then
            return
        end
        mgr.acc = 0

        EnsureSettings()

        local now = GetTime()

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
                    local r, g, b, a = safeR, safeG, safeB, safeA

                    if bucketsEnabled and curve then
                        local obj = icon._msufA2_cdDurationObj or cd._msufA2_durationObj
                        if obj and type(obj.EvaluateRemainingDuration) == "function" then
                            local col = obj:EvaluateRemainingDuration(curve)
                            if col then
                                if col.GetRGBA then
                                    r, g, b, a = col:GetRGBA()
                                elseif col.GetRGB then
                                    r, g, b = col:GetRGB()
                                    a = 1
                                end
                            end
                        end
                    end

                    if fs.SetTextColor then
                        fs:SetTextColor(r, g, b, a)
                    elseif fs.SetVertexColor then
                        fs:SetVertexColor(r, g, b, a)
                    end
                end
            end

            i = i - 1
        end

        StopIfIdle()
    end

    mgr._StopIfIdle = StopIfIdle
    mgr._RemoveAt = RemoveAt
    mgr._OnUpdate = OnUpdate

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
        mgr.acc = 0
        mgr.frame:Show()
        mgr.frame:SetScript("OnUpdate", mgr._OnUpdate)
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
    mgr.acc = 0

    local f = mgr.frame
    if f then
        f:SetScript("OnUpdate", nil)
        f:Hide()
    end
end

local function TouchIcon(_)
    local mgr = CT._mgr
    if mgr and mgr.count > 0 then
        mgr.acc = 0.10
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
