--- Auras3/MSUF_Auras3_CooldownText.lua
--- Shared cooldown text color manager for Auras3 and GroupFrame custom aura icons.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local type, select = type, select
local tonumber = tonumber
local C_Timer, GetTime, CreateFrame = _G.C_Timer, _G.GetTime, _G.CreateFrame
local C_CurveUtil, CreateColor = _G.C_CurveUtil, _G.CreateColor
local STANDARD_TEXT_FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local issecretvalue = _G.issecretvalue
    or (_G.C_Secrets and type(_G.C_Secrets.IsSecret) == "function" and _G.C_Secrets.IsSecret)
    or nil

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end

local CT = A3.CooldownText
if type(CT) ~= "table" then
    CT = {}
    A3.CooldownText = CT
end

MSUF.AuraCore = MSUF.AuraCore or _G.MSUF_AuraCore or {}
_G.MSUF_AuraCore = MSUF.AuraCore
MSUF.AuraCore.CooldownText = CT

local scopes = {
    unit = { dirty = true },
    group = { dirty = true },
}

local function ReadColor(t, defR, defG, defB, defA)
    if type(t) ~= "table" then return defR, defG, defB, defA end
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

local function ResolveBaseColor()
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    if g and g.useCustomFontColor == true
        and type(g.fontColorCustomR) == "number"
        and type(g.fontColorCustomG) == "number"
        and type(g.fontColorCustomB) == "number"
    then
        return g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB, 1
    end
    return 1, 1, 1, 1
end

local function ReadThreshold(g, scope, key, fallback)
    local prefix = scope == "group" and "gfAurasCooldownText" or "aurasCooldownText"
    local v = g and g[prefix .. key]
    if type(v) == "number" then return v end
    v = g and g["aurasCooldownText" .. key]
    if type(v) == "number" then return v end
    return fallback
end

local function BuildCurve(st, g, scope)
    st.curve = nil
    if not (C_CurveUtil and type(C_CurveUtil.CreateColorCurve) == "function"
        and type(CreateColor) == "function")
    then
        return
    end

    local curve = C_CurveUtil.CreateColorCurve()
    if not curve then return end
    if curve.SetType and _G.Enum and _G.Enum.LuaCurveType and _G.Enum.LuaCurveType.Step then
        curve:SetType(_G.Enum.LuaCurveType.Step)
    end

    local safeSeconds = ReadThreshold(g, scope, "SafeSeconds", 60)
    local warnSeconds = ReadThreshold(g, scope, "WarningSeconds", 15)
    local urgentSeconds = ReadThreshold(g, scope, "UrgentSeconds", 5)
    if warnSeconds > safeSeconds then warnSeconds = safeSeconds end
    if urgentSeconds > warnSeconds then urgentSeconds = warnSeconds end
    if urgentSeconds < 0 then urgentSeconds = 0 end

    curve:AddPoint(0, CreateColor(st.expR, st.expG, st.expB, st.expA))
    curve:AddPoint(0.25, CreateColor(st.urgR, st.urgG, st.urgB, st.urgA))
    curve:AddPoint(urgentSeconds, CreateColor(st.warnR, st.warnG, st.warnB, st.warnA))
    curve:AddPoint(warnSeconds, CreateColor(st.safeR, st.safeG, st.safeB, st.safeA))
    curve:AddPoint(safeSeconds, CreateColor(st.normR, st.normG, st.normB, st.normA))
    st.curve = curve
end

local function EnsureSettings(scope)
    scope = scope == "group" and "group" or "unit"
    local st = scopes[scope]
    if not st then
        st = { dirty = true }
        scopes[scope] = st
    end
    if not st.dirty then return st end
    st.dirty = false

    local g = _G.MSUF_DB and _G.MSUF_DB.general
    if scope == "group" then
        st.enabled = not (g and g.gfAurasCooldownTextUseBuckets == false)
    else
        st.enabled = not (g and g.aurasCooldownTextUseBuckets == false)
    end

    st.normR, st.normG, st.normB, st.normA = ResolveBaseColor()
    st.safeR, st.safeG, st.safeB, st.safeA = ReadColor(g and g.aurasCooldownTextSafeColor, st.normR, st.normG, st.normB, st.normA)
    st.warnR, st.warnG, st.warnB, st.warnA = ReadColor(g and g.aurasCooldownTextWarningColor, 1, 0.85, 0.20, 1)
    st.urgR, st.urgG, st.urgB, st.urgA = ReadColor(g and g.aurasCooldownTextUrgentColor, 1, 0.55, 0.10, 1)
    st.expR, st.expG, st.expB, st.expA = ReadColor(g and g.aurasCooldownTextExpireColor, 1, 0.12, 0.12, 1)

    if st.enabled then
        BuildCurve(st, g, scope)
    else
        st.curve = nil
    end
    return st
end

local function IsCooldownFontString(region)
    return region and region.GetObjectType and region:GetObjectType() == "FontString"
end

local function CacheCooldownFontString(cd, fs)
    cd._msufA3CooldownFontString = fs
    return fs
end

local function FindCooldownFontStringInRegions(...)
    for i = 1, select("#", ...) do
        local region = select(i, ...)
        if IsCooldownFontString(region) then return region end
    end
    return nil
end

local function ResolveCooldownFontString(cd, forceLookup)
    if not cd then return nil end
    local fs = cd.Text
    if IsCooldownFontString(fs) then return CacheCooldownFontString(cd, fs) end
    fs = cd.text
    if IsCooldownFontString(fs) then return CacheCooldownFontString(cd, fs) end
    local cached = cd._msufA3CooldownFontString
    if not forceLookup and cached and cached ~= false then return cached end
    if cd.GetRegions then
        fs = FindCooldownFontStringInRegions(cd:GetRegions())
        if fs then return CacheCooldownFontString(cd, fs) end
    end
    if cd.EnumerateRegions then
        for region in cd:EnumerateRegions() do
            if IsCooldownFontString(region) then return CacheCooldownFontString(cd, region) end
        end
    end
    cd._msufA3CooldownFontString = false
    return nil
end

local TEXT_ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function ClampSize(size)
    size = tonumber(size) or 10
    if size < 6 then size = 6 elseif size > 32 then size = 32 end
    return size
end

function CT.ApplyButtonStyle(button, size, anchor)
    local cd = button and (button.Cooldown or button.cooldown)
    local fs = ResolveCooldownFontString(cd, true)
    if not fs then return false end
    size = ClampSize(size)
    anchor = TEXT_ANCHORS[anchor] and anchor or "CENTER"
    if fs._msufA3CdFontSize ~= size then
        if type(_G.MSUF_SetFontSafe) == "function" then
            _G.MSUF_SetFontSafe(fs, STANDARD_TEXT_FONT, size, "OUTLINE")
        elseif fs.SetFont then
            fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
        end
        fs._msufA3CdFontSize = size
    end
    if fs._msufA3CdAnchor ~= anchor then
        fs:ClearAllPoints()
        if anchor == "TOPLEFT" then
            fs:SetPoint("TOPLEFT", cd, "TOPLEFT", 1, -1)
        elseif anchor == "TOP" then
            fs:SetPoint("TOP", cd, "TOP", 0, -1)
        elseif anchor == "TOPRIGHT" then
            fs:SetPoint("TOPRIGHT", cd, "TOPRIGHT", -1, -1)
        elseif anchor == "LEFT" then
            fs:SetPoint("LEFT", cd, "LEFT", 1, 0)
        elseif anchor == "RIGHT" then
            fs:SetPoint("RIGHT", cd, "RIGHT", -1, 0)
        elseif anchor == "BOTTOMLEFT" then
            fs:SetPoint("BOTTOMLEFT", cd, "BOTTOMLEFT", 1, 0)
        elseif anchor == "BOTTOM" then
            fs:SetPoint("BOTTOM", cd, "BOTTOM", 0, 0)
        elseif anchor == "BOTTOMRIGHT" then
            fs:SetPoint("BOTTOMRIGHT", cd, "BOTTOMRIGHT", -1, 0)
        else
            fs:SetPoint("CENTER", cd, "CENTER", 0, 0)
        end
        fs._msufA3CdAnchor = anchor
    end
    return true
end

local secretMode, secretNextCheck = false, 0
local function IsSecretMode(now)
    local secrets = _G.C_Secrets
    if not (secrets and type(secrets.ShouldAurasBeSecret) == "function") then return false end
    if type(now) ~= "number" then now = GetTime and GetTime() or 0 end
    if now >= (secretNextCheck or 0) then
        secretNextCheck = now + 0.50
        secretMode = secrets.ShouldAurasBeSecret() == true
    end
    return secretMode == true
end

local function IsSecretValue(value)
    local fn = issecretvalue
    if type(fn) ~= "function" then
        local secrets = _G.C_Secrets
        fn = _G.issecretvalue
            or (secrets and type(secrets.IsSecret) == "function" and secrets.IsSecret)
            or nil
        if type(fn) ~= "function" then return false end
        issecretvalue = fn
    end
    return fn(value) == true
end

local function ApplyColor(button, fs, r, g, b, a, force)
    if not fs then return end
    -- These color components can be secret numbers in Midnight/Beta. Pass them
    -- straight to Blizzard widgets; do not store or compare them in addon Lua.
    button._msufA3CdLastFS = fs
    button._msufA3CdLastR = nil
    button._msufA3CdLastG = nil
    button._msufA3CdLastB = nil
    button._msufA3CdLastA = nil
    if fs.SetTextColor then fs:SetTextColor(r, g, b, a)
    elseif fs.SetVertexColor then fs:SetVertexColor(r, g, b, a) end
end

local manager
local function EnsureManager()
    if manager then return manager end
    manager = {
        buttons = {},
        count = 0,
        fastUntil = 0,
        fastInterval = 0.10,
        secretInterval = 0.20,
        slowInterval = 0.50,
        maxIdleInterval = 5.0,
    }

    local function CancelTimer()
        if manager.timer and manager.timer.Cancel then manager.timer:Cancel() end
        manager.timer = nil
        manager.timerGen = (manager.timerGen or 0) + 1
    end

    local function RemoveAt(index)
        local button = manager.buttons[index]
        local last = manager.buttons[manager.count]
        manager.buttons[index] = last
        manager.buttons[manager.count] = nil
        if last and last ~= button then last._msufA3CdMgrIndex = index end
        manager.count = manager.count - 1
        if button then
            button._msufA3CdMgrRegistered = false
            button._msufA3CdMgrIndex = nil
            button._msufA3CdSkipUntil = nil
            button._msufA3CdDurationObj = nil
            button._msufA3CdScope = nil
            button._msufA3CdLastFS = nil
            button._msufA3CdLastR = nil
            button._msufA3CdLastG = nil
            button._msufA3CdLastB = nil
            button._msufA3CdLastA = nil
        end
        if manager.count <= 0 then CancelTimer() end
    end

    local function Tick()
        manager.touchScheduled = false
        local now = GetTime and GetTime() or 0
        local secretsActive = IsSecretMode(now)
        local wantFast = now < (manager.fastUntil or 0)
        local nextDue
        local secretNoDetector = secretsActive and not issecretvalue

        local i = manager.count
        while i > 0 do
            local button = manager.buttons[i]
            local cd = button and (button.Cooldown or button.cooldown)
            local st = button and EnsureSettings(button._msufA3CdScope)
            if not button or not cd or not button.IsShown or not button:IsShown() or not st or not st.enabled then
                RemoveAt(i)
            else
                local fs = ResolveCooldownFontString(cd)
                local obj = button._msufA3CdDurationObj
                if fs and obj then
                    local skipUntil = button._msufA3CdSkipUntil
                    if skipUntil and now < skipUntil then
                        if not nextDue or skipUntil < nextDue then nextDue = skipUntil end
                    else
                        local r, g, b, a = st.safeR, st.safeG, st.safeB, st.safeA
                        local bucket, secret, evaluated = 3, false, false
                        if st.curve and type(obj.EvaluateRemainingDuration) == "function" then
                            local col = obj:EvaluateRemainingDuration(st.curve)
                            if col then
                                evaluated = true
                                if col.GetRGBA then r, g, b, a = col:GetRGBA()
                                elseif col.GetRGB then r, g, b = col:GetRGB(); a = 1 end
                            end
                        end
                        if secretsActive and secretNoDetector then
                            secret = true
                        elseif IsSecretValue(r) or IsSecretValue(g) or IsSecretValue(b) or IsSecretValue(a) then
                            secret = true
                        end
                        if not evaluated then
                            r, g, b, a = st.safeR, st.safeG, st.safeB, st.safeA
                            secret = secretsActive or secret
                        end
                        if not secret then
                            if r == st.expR and g == st.expG and b == st.expB then
                                bucket = 0; wantFast = true
                            elseif r == st.urgR and g == st.urgG and b == st.urgB then
                                bucket = 1; wantFast = true
                            elseif r == st.warnR and g == st.warnG and b == st.warnB then
                                bucket = 2; wantFast = true
                            elseif r == st.normR and g == st.normG and b == st.normB then
                                bucket = 4
                            end
                        else
                            wantFast = true
                        end
                        if secret then
                            button._msufA3CdSkipUntil = nil
                        elseif bucket == 4 then
                            button._msufA3CdSkipUntil = now + 5.0
                            if not nextDue or button._msufA3CdSkipUntil < nextDue then nextDue = button._msufA3CdSkipUntil end
                        elseif bucket == 3 then
                            button._msufA3CdSkipUntil = now + 2.0
                            if not nextDue or button._msufA3CdSkipUntil < nextDue then nextDue = button._msufA3CdSkipUntil end
                        else
                            button._msufA3CdSkipUntil = nil
                        end
                        ApplyColor(button, fs, r, g, b, a, secret)
                    end
                end
            end
            i = i - 1
        end

        if manager.count <= 0 then CancelTimer(); return end
        local delay
        if wantFast then
            manager.fastUntil = now + 1.50
            delay = secretsActive and manager.secretInterval or manager.fastInterval
        elseif nextDue and nextDue > now then
            delay = nextDue - now
            if delay < 0.05 then delay = 0.05 elseif delay > manager.maxIdleInterval then delay = manager.maxIdleInterval end
        else
            delay = manager.slowInterval
        end
        manager.Schedule(delay)
    end

    function manager.Schedule(delay)
        if manager.count <= 0 then CancelTimer(); return end
        if type(delay) ~= "number" or delay < 0 then delay = 0 end
        CancelTimer()
        manager.touchScheduled = delay <= 0
        if C_Timer and type(C_Timer.NewTimer) == "function" then
            manager.timer = C_Timer.NewTimer(delay, function()
                manager.timer = nil
                Tick()
            end)
        elseif C_Timer and type(C_Timer.After) == "function" then
            local gen = manager.timerGen
            C_Timer.After(delay, function()
                if manager.timerGen ~= gen then return end
                Tick()
            end)
        end
    end

    manager.RemoveAt = RemoveAt
    return manager
end

function CT.RegisterButton(button, durationObject, scope)
    if not button or not durationObject then return end
    local cd = button.Cooldown or button.cooldown
    if not cd then return end
    scope = scope == "group" and "group" or "unit"
    local st = EnsureSettings(scope)
    button._msufA3CdDurationObj = durationObject
    button._msufA3CdScope = scope
    button._msufA3CdSkipUntil = nil
    if button._msufA3CdTextSize or button._msufA3CdTextAnchor then
        CT.ApplyButtonStyle(button, button._msufA3CdTextSize, button._msufA3CdTextAnchor)
    end
    if not (st and st.enabled) then
        CT.UnregisterButton(button)
        local fs = ResolveCooldownFontString(cd)
        if fs and st then ApplyColor(button, fs, st.normR, st.normG, st.normB, st.normA, true) end
        return
    end
    local manager = EnsureManager()
    if button._msufA3CdMgrRegistered == true then
        if manager.Schedule and not manager.touchScheduled then manager.Schedule(0) end
        return
    end
    local index = manager.count + 1
    manager.count = index
    manager.buttons[index] = button
    button._msufA3CdMgrRegistered = true
    button._msufA3CdMgrIndex = index
    manager.Schedule(0)
end

function CT.TouchButton(button)
    if not button then return end
    button._msufA3CdSkipUntil = nil
    local manager = manager
    if button._msufA3CdMgrRegistered == true and manager and manager.count > 0 and manager.Schedule and not manager.touchScheduled then
        manager.Schedule(0)
    end
end

function CT.UnregisterButton(button)
    if not button then return end
    if button._msufA3CdMgrRegistered ~= true then
        button._msufA3CdMgrIndex = nil
        button._msufA3CdDurationObj = nil
        button._msufA3CdScope = nil
        return
    end
    local manager = manager
    local index = button._msufA3CdMgrIndex
    if manager and type(index) == "number" and index >= 1 and index <= manager.count and manager.RemoveAt then
        manager.RemoveAt(index)
    else
        button._msufA3CdMgrRegistered = false
        button._msufA3CdMgrIndex = nil
        button._msufA3CdDurationObj = nil
        button._msufA3CdScope = nil
    end
end

function CT.Invalidate(scope)
    if scope == "group" then
        scopes.group.dirty = true
    elseif scope == "unit" then
        scopes.unit.dirty = true
    else
        scopes.unit.dirty = true
        scopes.group.dirty = true
    end
end

function CT.ForceRecolor(scope)
    CT.Invalidate(scope)
    local manager = manager
    if not (manager and manager.count and manager.count > 0) then return end
    for i = 1, manager.count do
        local button = manager.buttons[i]
        if button and (not scope or button._msufA3CdScope == scope) then
            button._msufA3CdSkipUntil = nil
            button._msufA3CdLastFS = nil
            button._msufA3CdLastR = nil
            button._msufA3CdLastG = nil
            button._msufA3CdLastB = nil
            button._msufA3CdLastA = nil
        end
    end
    if manager.Schedule then manager.Schedule(0) end
end

_G.MSUF_A3_InvalidateCooldownTextCurve = function() return CT.Invalidate("unit") end
_G.MSUF_A3_ForceCooldownTextRecolor = function() return CT.ForceRecolor("unit") end

if CreateFrame then
    local f = CreateFrame("Frame")
    if f and f.RegisterEvent then
        f:RegisterEvent("PLAYER_REGEN_DISABLED")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:SetScript("OnEvent", function()
            if manager and manager.count and manager.count > 0 then CT.ForceRecolor() end
        end)
    end
end
