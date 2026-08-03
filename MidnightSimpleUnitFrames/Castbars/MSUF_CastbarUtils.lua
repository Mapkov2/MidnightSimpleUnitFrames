--- Castbars/MSUF_CastbarUtils.lua
--- Utility exports for castbar colors, preview sync, interrupt tinting,
--- shake/glow feedback, reverse fill, and spell-name shortening.
---
--- Many modules call these globals directly. Keep this file as a compatibility
--- surface; new code should prefer clearer helpers in Runtime/Style/Visuals and
--- leave these exports stable unless a migration is planned.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local C_Timer = _G.C_Timer
local type = type
local tonumber = tonumber
local tostring = tostring
local string_byte = string.byte
local string_sub = string.sub
local math_floor = math.floor
local math_abs = math.abs

local function PlainPositiveNumber(value)
    local isSecret = _G.issecretvalue
    if type(isSecret) == "function" and isSecret(value) == true then return nil end

    value = tonumber(value)
    if type(isSecret) == "function" and isSecret(value) == true then return nil end
    if type(value) ~= "number" then return nil end
    return value > 0 and value or nil
end

local function GetInterruptFeedbackDuration()
    local general = _G.MSUF_DB and _G.MSUF_DB.general
    local duration = general and tonumber(general.castbarInterruptFeedbackDuration)
    if type(duration) ~= "number" then
        duration = tonumber(_G.MSUF_INTERRUPT_FEEDBACK_DURATION) or 0.5
    end
    if duration < 0 then return 0 end
    if duration > 5 then return 5 end
    return duration
end
ExportPublic("MSUF_GetInterruptFeedbackDuration", GetInterruptFeedbackDuration)

if type(_G.MSUF_HardSyncCastbarPreview) ~= "function" then
    local function HardSyncCastbarPreview(preview, source)
        if not preview or not source then return end

        if source.GetScale and preview.SetScale then
            local scale = PlainPositiveNumber(source:GetScale())
            if scale then preview:SetScale(scale) end
        end

        if preview.statusBar and preview.statusBar.SetSize then
            if source.statusBar and source.statusBar.GetSize then
                local width, height = source.statusBar:GetSize()
                width = PlainPositiveNumber(width)
                height = PlainPositiveNumber(height)
                if width and height then preview.statusBar:SetSize(width, height) end
            elseif preview.GetSize then
                local width, height = preview:GetSize()
                width = PlainPositiveNumber(width)
                height = PlainPositiveNumber(height)
                if width and height then preview.statusBar:SetSize(width, height) end
            end
        end

        if preview.icon and preview.icon.SetSize and source.icon and source.icon.GetSize then
            local width, height = source.icon:GetSize()
            width = PlainPositiveNumber(width)
            height = PlainPositiveNumber(height)
            if width and height then preview.icon:SetSize(width, height) end
        end

        if preview.latencyBar
            and preview.latencyBar.SetWidth
            and source.latencyBar
            and source.latencyBar.GetWidth then
            local width = PlainPositiveNumber(source.latencyBar:GetWidth())
            if width then preview.latencyBar:SetWidth(width) end
        end
    end

    ExportPublic("MSUF_HardSyncCastbarPreview", HardSyncCastbarPreview)
end

local function EnsureDBLazy()
    if not _G.MSUF_DB and type(_G.EnsureDB) == "function" then
        _G.EnsureDB()
    end
end
ExportPublic("MSUF_EnsureDBLazy", EnsureDBLazy)

local function GetAnchorFrame()
    EnsureDBLazy()
    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    local isCooldownAnchorEnabled = _G.MSUF_IsCooldownAnchorEnabled
    local cooldownAnchorEnabled = type(isCooldownAnchorEnabled) == "function"
        and isCooldownAnchorEnabled(general) == true
        or general.anchorToCooldown == true

    if cooldownAnchorEnabled then
        local getCooldown = _G.MSUF_GetEffectiveCooldownFrame
        local cooldown = (type(getCooldown) == "function" and getCooldown("EssentialCooldownViewer"))
            or _G.EssentialCooldownViewer
        if cooldown and cooldown.IsShown and cooldown:IsShown() then
            return cooldown
        end
        return _G.UIParent
    end

    local anchorName = general.anchorName
    if anchorName and anchorName ~= "" and anchorName ~= "EssentialCooldownViewer" then
        local frame = _G[anchorName]
        if frame and frame.IsShown and frame:IsShown() then
            return frame
        end
    end

    return _G.UIParent
end
ExportPublic("MSUF_GetAnchorFrame", GetAnchorFrame)

local function SetStatusBarColorIfChangedImpl(statusBar, red, green, blue, alpha)
    if not (statusBar and statusBar.SetStatusBarColor) then return end

    alpha = alpha or 1
    local lastR, lastG, lastB, lastA =
        statusBar._msufLastColorR,
        statusBar._msufLastColorG,
        statusBar._msufLastColorB,
        statusBar._msufLastColorA

    if (lastR == red and lastG == green and lastB == blue and lastA == alpha)
        or (
            statusBar._msufLastR == red
            and statusBar._msufLastG == green
            and statusBar._msufLastB == blue
            and statusBar._msufLastA == alpha
        ) then
        return
    end

    statusBar._msufLastColorR = red
    statusBar._msufLastColorG = green
    statusBar._msufLastColorB = blue
    statusBar._msufLastColorA = alpha
    statusBar._msufLastR = red
    statusBar._msufLastG = green
    statusBar._msufLastB = blue
    statusBar._msufLastA = alpha
    statusBar:SetStatusBarColor(red, green, blue, alpha)
end

if type(_G.MSUF_SetStatusBarColorIfChanged) ~= "function" then
    ExportPublic("MSUF_SetStatusBarColorIfChanged", SetStatusBarColorIfChangedImpl)
end

-- Castbar colors are global settings, so all target/focus/boss bars can share
-- the same three ColorObjects. Keep only one object per semantic color and
-- replace it solely when that global color actually changes.
local interruptibleColorCache = { r = nil, g = nil, b = nil, a = nil, obj = nil }
local nonInterruptibleColorCache = { r = nil, g = nil, b = nil, a = nil, obj = nil }
local interruptUnavailableColorCache = { r = nil, g = nil, b = nil, a = nil, obj = nil }

local function CachedColor(cache, red, green, blue, alpha)
    if cache.r == red and cache.g == green and cache.b == blue and cache.a == alpha and cache.obj then
        return cache.obj
    end
    cache.r, cache.g, cache.b, cache.a = red, green, blue, alpha
    cache.obj = _G.CreateColor(red, green, blue, alpha)
    return cache.obj
end

local function CanUseBooleanTintValue(value)
    local isSecret = _G.issecretvalue
    if type(isSecret) == "function" and isSecret(value) == true then return true end
    return value ~= nil
end

local function ApplyNonInterruptibleTint(
    frame,
    apiNotInterruptibleRaw,
    nonR,
    nonG,
    nonB,
    nonA,
    castR,
    castG,
    castB,
    castA,
    forceNotInterruptible,
    unavailableR,
    unavailableG,
    unavailableB,
    unavailableA,
    interruptReadyBool,
    useUnavailableColor
)
    local statusBar = frame and frame.statusBar
    if not statusBar then return false end

    local useNonInterruptible = forceNotInterruptible == true
    local useUnavailable = useUnavailableColor == true
        and unavailableR ~= nil
        and unavailableG ~= nil
        and unavailableB ~= nil
        and CanUseBooleanTintValue(interruptReadyBool)
        and _G.C_CurveUtil
        and type(_G.C_CurveUtil.EvaluateColorFromBoolean) == "function"

    local red = useNonInterruptible and nonR or castR
    local green = useNonInterruptible and nonG or castG
    local blue = useNonInterruptible and nonB or castB
    local alpha = useNonInterruptible and (nonA or 1) or (castA or 1)

    local texture = statusBar.GetStatusBarTexture and statusBar:GetStatusBarTexture()
    local usedBooleanTint = false
    if texture and texture.SetVertexColorFromBoolean and _G.CreateColor then
        local nonColor = CachedColor(nonInterruptibleColorCache, nonR, nonG, nonB, nonA or 1)
        local castColor = CachedColor(interruptibleColorCache, castR, castG, castB, castA or 1)
        local activeCastColor = castColor
        if useUnavailable then
            local unavailableColor = CachedColor(
                interruptUnavailableColorCache,
                unavailableR,
                unavailableG,
                unavailableB,
                unavailableA or 1
            )
            activeCastColor = _G.C_CurveUtil.EvaluateColorFromBoolean(interruptReadyBool, castColor, unavailableColor)
        end

        local boolValue = apiNotInterruptibleRaw
        if not CanUseBooleanTintValue(boolValue) then
            boolValue = useNonInterruptible == true
        end
        texture:SetVertexColorFromBoolean(boolValue, nonColor, activeCastColor)
        usedBooleanTint = true
    end

    if not usedBooleanTint then
        SetStatusBarColorIfChangedImpl(statusBar, red, green, blue, alpha)
    elseif useUnavailable then
        statusBar._msufLastColorR = nil
        statusBar._msufLastColorG = nil
        statusBar._msufLastColorB = nil
        statusBar._msufLastColorA = nil
        statusBar._msufLastR = nil
        statusBar._msufLastG = nil
        statusBar._msufLastB = nil
        statusBar._msufLastA = nil
    else
        statusBar._msufLastColorR = red
        statusBar._msufLastColorG = green
        statusBar._msufLastColorB = blue
        statusBar._msufLastColorA = alpha
        statusBar._msufLastR = red
        statusBar._msufLastG = green
        statusBar._msufLastB = blue
        statusBar._msufLastA = alpha
    end

    if not statusBar._msufGlowSkipBase and not useUnavailable then
        local baseR, baseG, baseB, baseA =
            statusBar._msufGlowBaseR,
            statusBar._msufGlowBaseG,
            statusBar._msufGlowBaseB,
            statusBar._msufGlowBaseA
        if baseR ~= red or baseG ~= green or baseB ~= blue or baseA ~= alpha then
            statusBar._msufGlowBaseR = red
            statusBar._msufGlowBaseG = green
            statusBar._msufGlowBaseB = blue
            statusBar._msufGlowBaseA = alpha
            statusBar._msufGlowLastP = nil
        end
    end

    return usedBooleanTint
end
ExportPublic("MSUF_Castbar_ApplyNonInterruptibleTint", ApplyNonInterruptibleTint)

local SetTextIfChanged = _G.MSUF_SetTextIfChanged

local function SetText(textRegion, text)
    if not (textRegion and textRegion.SetText) then return end
    if SetTextIfChanged then
        SetTextIfChanged(textRegion, text or "")
    else
        textRegion:SetText(text or "")
    end
end

if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
        SetTextIfChanged = _G.MSUF_SetTextIfChanged or SetTextIfChanged
    end)
end

local function ResolveReverseFill(frame, override, isChanneled)
    if override and override.reverseFill ~= nil then
        return override.reverseFill == true
    end

    local resolver = _G.MSUF_GetCastbarReverseFillForFrame
    if type(resolver) == "function" then
        local reverseFill = resolver(frame, isChanneled and true or false)
        if reverseFill ~= nil then
            return reverseFill == true
        end
    end

    return false
end

local function GetReverseFillSafe(frame, isChanneled)
    return ResolveReverseFill(frame, nil, isChanneled)
end
ExportPublic("MSUF_GetReverseFillSafe", GetReverseFillSafe)

--- How the bar value moves is a cast-type property, never an anchor property.
--- Casts and empower bars count up (elapsed time) so they fill toward the far
--- edge; a channel counts down (remaining time) so the same anchor drains and
--- its moving edge travels the opposite way. Unified direction makes channels
--- fill like a cast. This mirrors TimerDirection in the runtime, so the Lua
--- fallback paths render exactly what the native 12.1 timer renders.
local function GetCastbarCountsDown(frame, isChanneled)
    if isChanneled ~= true then return false end
    if frame and frame.isEmpower == true then return false end

    EnsureDBLazy()
    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    return general.castbarUnifiedDirection ~= true
end
ExportPublic("MSUF_GetCastbarCountsDown", GetCastbarCountsDown)

local function GetCastbarUnitKey(frame)
    if not frame then return nil end

    local unit = frame.unit or frame.MSUF_unit or frame._msufUnit or frame.unitKey
    if type(unit) == "string" and unit ~= "" then return unit end

    local key = frame._msufBarKey or frame.barKey or frame.key
    if type(key) == "string" and key ~= "" then
        if key == "player" or key == "target" or key == "focus" then return key end
        if key == "boss" or key:sub(1, 4) == "boss" then return key end
    end

    if frame == _G.MSUF_PlayerCastbar or frame == _G.MSUF_PlayerCastbarPreview then return "player" end
    if frame == _G.MSUF_TargetCastbar or frame == _G.MSUF_TargetCastbarPreview then return "target" end
    if frame == _G.MSUF_FocusCastbar or frame == _G.MSUF_FocusCastbarPreview then return "focus" end

    local name = frame.GetName and frame:GetName() or nil
    if type(name) == "string" then
        if name:find("Target", 1, true) then return "target" end
        if name:find("Focus", 1, true) then return "focus" end
        if name:find("Player", 1, true) then return "player" end
        if name:find("boss", 1, true) or name:find("Boss", 1, true) then return "boss" end
    end

    return nil
end

--- The fill anchor comes only from the configured castbar direction (plus the
--- target override). Casts and empower bars both count up; channels keep this
--- same anchor and reverse their value direction when unified fill is off.
local function GetCastbarReverseFillForFrame(frame, _)
    EnsureDBLazy()
    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    local reverseFill = general.castbarFillDirection == "RTL"

    if general.castbarOpositeDirectionTarget == true then
        local unit = GetCastbarUnitKey(frame)
        if unit == "target" then
            reverseFill = not reverseFill
        end
    end

    return reverseFill
end
ExportPublic("MSUF_GetCastbarReverseFillForFrame", GetCastbarReverseFillForFrame)

local function ResolveCastbarColors()
    EnsureDBLazy()
    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}

    local castR, castG, castB
    if type(_G.MSUF_GetInterruptibleCastColor) == "function" then
        castR, castG, castB = _G.MSUF_GetInterruptibleCastColor()
    end
    if not (castR and castG and castB) then
        local key = general.castbarInterruptibleColor or "teal"
        local getRGB = _G.MSUF_GetColorRGBFromKey
        if type(getRGB) == "function" then castR, castG, castB = getRGB(key) end
        if not (castR and castG and castB) then
            local color = type(_G.MSUF_GetColorFromKey) == "function" and _G.MSUF_GetColorFromKey(key) or nil
            if color and color.GetRGB then castR, castG, castB = color:GetRGB() end
        end
    end
    if not (castR and castG and castB) then castR, castG, castB = 0, 0.85, 0.85 end

    local nonR, nonG, nonB
    if type(_G.MSUF_GetNonInterruptibleCastColor) == "function" then
        nonR, nonG, nonB = _G.MSUF_GetNonInterruptibleCastColor()
    end
    if not (nonR and nonG and nonB) then
        local key = general.castbarNonInterruptibleColor or "red"
        local getRGB = _G.MSUF_GetColorRGBFromKey
        if type(getRGB) == "function" then nonR, nonG, nonB = getRGB(key) end
        if not (nonR and nonG and nonB) then
            local color = type(_G.MSUF_GetColorFromKey) == "function" and _G.MSUF_GetColorFromKey(key) or nil
            if color and color.GetRGB then nonR, nonG, nonB = color:GetRGB() end
        end
    end
    if not (nonR and nonG and nonB) then nonR, nonG, nonB = 0.9, 0.1, 0.1 end

    return castR, castG, castB, nonR, nonG, nonB
end
ExportPublic("MSUF_ResolveCastbarColors", ResolveCastbarColors)

local function EnsureShakeGroup(frame)
    if not frame or frame.MSUF_ShakeGroup then return end

    local group = frame:CreateAnimationGroup("MSUF_ShakeGroup")
    group:SetLooping("NONE")

    local first = group:CreateAnimation("Translation")
    first:SetOffset(4, 0)
    first:SetDuration(0.05)
    first:SetOrder(1)

    local second = group:CreateAnimation("Translation")
    second:SetOffset(-8, 0)
    second:SetDuration(0.10)
    second:SetOrder(2)

    local third = group:CreateAnimation("Translation")
    third:SetOffset(4, 0)
    third:SetDuration(0.05)
    third:SetOrder(3)

    frame.MSUF_ShakeGroup = group
    frame.MSUF_ShakeA1 = first
    frame.MSUF_ShakeA2 = second
    frame.MSUF_ShakeA3 = third
end

local function PlayCastbarShake(frame)
    if not frame then return end

    EnsureDBLazy()
    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    if general.castbarInterruptShake == false then return end

    local strength = tonumber(general.castbarShakeStrength) or 8
    if strength < 0 then strength = 0 end
    if strength > 30 then strength = 30 end
    if strength <= 0 then return end

    local half = strength / 2
    EnsureShakeGroup(frame)
    if frame.MSUF_ShakeA1 and frame.MSUF_ShakeA1.SetOffset then frame.MSUF_ShakeA1:SetOffset(half, 0) end
    if frame.MSUF_ShakeA2 and frame.MSUF_ShakeA2.SetOffset then frame.MSUF_ShakeA2:SetOffset(-strength, 0) end
    if frame.MSUF_ShakeA3 and frame.MSUF_ShakeA3.SetOffset then frame.MSUF_ShakeA3:SetOffset(half, 0) end
    if frame.MSUF_ShakeGroup then
        frame.MSUF_ShakeGroup:Stop()
        frame.MSUF_ShakeGroup:Play()
    end
end
ExportPublic("MSUF_PlayCastbarShake", PlayCastbarShake)

local function GetInterruptibleCastColor()
    EnsureDBLazy()
    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    local red = tonumber(general.castbarInterruptibleR)
    local green = tonumber(general.castbarInterruptibleG)
    local blue = tonumber(general.castbarInterruptibleB)
    if red and green and blue then return red, green, blue, 1 end
end
ExportPublic("MSUF_GetInterruptibleCastColor", GetInterruptibleCastColor)

local function GetNonInterruptibleCastColor()
    EnsureDBLazy()
    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    local red = tonumber(general.castbarNonInterruptibleR)
    local green = tonumber(general.castbarNonInterruptibleG)
    local blue = tonumber(general.castbarNonInterruptibleB)
    if red and green and blue then return red, green, blue, 1 end
end
ExportPublic("MSUF_GetNonInterruptibleCastColor", GetNonInterruptibleCastColor)

local function GetInterruptUnavailableCastColor()
    EnsureDBLazy()
    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    local red = tonumber(general.castbarInterruptUnavailableR)
    local green = tonumber(general.castbarInterruptUnavailableG)
    local blue = tonumber(general.castbarInterruptUnavailableB)
    if red and green and blue then return red, green, blue, 1 end
end
ExportPublic("MSUF_GetInterruptUnavailableCastColor", GetInterruptUnavailableCastColor)

local function ResolveInterruptFeedbackCastColor()
    EnsureDBLazy()

    local getter = _G.MSUF_GetInterruptFeedbackCastColor
    if type(getter) == "function" then
        local red, green, blue = getter()
        if red and green and blue then return red, green, blue, 1 end
    end

    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    local red = tonumber(general.castbarInterruptFeedbackR)
    local green = tonumber(general.castbarInterruptFeedbackG)
    local blue = tonumber(general.castbarInterruptFeedbackB)
    if red and green and blue then return red, green, blue, 1 end

    local key = general.castbarInterruptFeedbackColor or "yellow"
    local getRGB = _G.MSUF_GetColorRGBFromKey
    if type(getRGB) == "function" then
        red, green, blue = getRGB(key)
        if red and green and blue then return red, green, blue, 1 end
    end

    local color = type(_G.MSUF_GetColorFromKey) == "function" and _G.MSUF_GetColorFromKey(key) or nil
    if color and color.GetRGB then
        red, green, blue = color:GetRGB()
        if red and green and blue then return red, green, blue, 1 end
    end

    return 1.0, 0.82, 0.0, 1
end
ExportPublic("MSUF_ResolveInterruptFeedbackCastColor", ResolveInterruptFeedbackCastColor)

local function UnitSupportsInterruptUnavailableTint(frame, general)
    local unit = frame and frame.unit
    if type(unit) ~= "string" then return false end

    local shouldUse = _G.MSUF_ShouldUseMSUFCastbar
    local function owns(which)
        if type(shouldUse) == "function" then
            return shouldUse(which, general) == true
        end
        return true
    end

    if unit == "target" then return general.kickReadyShowTarget == true and owns("target") end
    if unit == "focus" then return general.kickReadyShowFocus == true and owns("focus") end
    if unit:sub(1, 4) == "boss" then return general.kickReadyShowBoss == true and owns("boss") end
    return false
end

local function ShouldUseInterruptUnavailableColor(frame)
    EnsureDBLazy()
    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    if general.kickReadyStyle ~= "fill" then return false end
    return UnitSupportsInterruptUnavailableTint(frame, general)
end
ExportPublic("MSUF_Castbar_ShouldUseInterruptUnavailableColor", ShouldUseInterruptUnavailableColor)

local function ResolveInterruptUnavailableCastColor()
    EnsureDBLazy()
    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    local red, green, blue

    if type(_G.MSUF_GetInterruptUnavailableCastColor) == "function" then
        red, green, blue = _G.MSUF_GetInterruptUnavailableCastColor()
    end

    if not (red and green and blue) then
        local key = general.castbarInterruptUnavailableColor
        local color = key and type(_G.MSUF_GetColorFromKey) == "function" and _G.MSUF_GetColorFromKey(key) or nil
        if color and color.GetRGB then
            red, green, blue = color:GetRGB()
        end
    end

    if not (red and green and blue) then
        red, green, blue = 1.0, 0.494117647, 0.137254902
    end

    return red, green, blue, 1
end
ExportPublic("MSUF_ResolveInterruptUnavailableCastColor", ResolveInterruptUnavailableCastColor)

local function GetInterruptUnavailableTintArgs(frame)
    if not ShouldUseInterruptUnavailableColor(frame) then return nil end
    if not (_G.C_CurveUtil and type(_G.C_CurveUtil.EvaluateColorFromBoolean) == "function") then return nil end
    if type(_G.MSUF_KickReady_GetSpellID) == "function" and not _G.MSUF_KickReady_GetSpellID() then return nil end

    local readyBool
    if type(_G.MSUF_KickReady_GetReadyBoolForTint) == "function" then
        readyBool = _G.MSUF_KickReady_GetReadyBoolForTint()
    elseif type(_G.MSUF_KickReady_IsReady) == "function" then
        readyBool = _G.MSUF_KickReady_IsReady()
    end
    if not CanUseBooleanTintValue(readyBool) then return nil end

    local red, green, blue, alpha = ResolveInterruptUnavailableCastColor()
    return red, green, blue, alpha or 1, readyBool, true
end
ExportPublic("MSUF_Castbar_GetInterruptUnavailableTintArgs", GetInterruptUnavailableTintArgs)

local toPlainIsSecret = _G.issecretvalue or function(_) return false end
local toPlainHuge = math.huge

local function ToPlainNumber(value)
    -- PERF fast path: a plain finite number needs no tostring/tonumber
    -- round-trip (that round-trip only exists to redact secrets and to map
    -- nan/inf to nil, which the guards below preserve exactly).
    if type(value) == "number" then
        if toPlainIsSecret(value) ~= true
            and value == value and value ~= toPlainHuge and value ~= -toPlainHuge then
            return value
        end
        return tonumber(tostring(value))
    end
    local fn = _G.MSUF_ToPlainNumber
    if type(fn) == "function" then
        local plain = fn(value)
        if type(plain) == "number" then return tonumber(tostring(plain)) end
        return plain
    end
    local valueType = type(value)
    if valueType == "number" or valueType == "string" then return tonumber(tostring(value)) end
    return nil
end

local glowEnabledCache
local glowEnabledRevision = -1

local function IsCastbarGlowEnabled()
    local revision = _G.MSUF__castTimeGlobalRev or 1
    if glowEnabledRevision == revision and glowEnabledCache ~= nil then
        return glowEnabledCache
    end

    EnsureDBLazy()
    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    glowEnabledCache = not (general and general.castbarShowGlow == false)
    glowEnabledRevision = revision
    return glowEnabledCache
end

local function ResetCastbarGlowFade(frame)
    if not frame or not frame.statusBar then return end

    local statusBar = frame.statusBar
    if not statusBar._msufGlowApplied then return end

    local red, green, blue, alpha =
        statusBar._msufGlowBaseR,
        statusBar._msufGlowBaseG,
        statusBar._msufGlowBaseB,
        statusBar._msufGlowBaseA

    if type(red) ~= "number" or type(green) ~= "number" or type(blue) ~= "number" then
        statusBar._msufGlowApplied = nil
        statusBar._msufGlowLastP = nil
        return
    end

    if alpha == nil then alpha = 1 end
    statusBar._msufGlowSkipBase = true
    if type(_G.MSUF_SetStatusBarColorIfChanged) == "function" then
        _G.MSUF_SetStatusBarColorIfChanged(statusBar, red, green, blue, alpha)
    else
        statusBar:SetStatusBarColor(red, green, blue, alpha)
    end
    statusBar._msufGlowSkipBase = nil
    statusBar._msufGlowApplied = nil
    statusBar._msufGlowLastP = nil
end
ExportPublic("MSUF_ResetCastbarGlowFade", ResetCastbarGlowFade)

local function ApplyCastbarGlowFade(frame, remainingSeconds, totalSeconds)
    if not frame or not frame.statusBar then return end
    if (frame._msufIsPreview or frame.MSUF_testMode) and not _G.MSUF_UnitEditModeActive then return end
    if frame.interrupted then return end

    if frame.interruptFeedbackEndTime then
        local now = (_G.GetTimePreciseSec and _G.GetTimePreciseSec()) or _G.GetTime()
        if now < frame.interruptFeedbackEndTime then return end
    end

    if not IsCastbarGlowEnabled() then
        _G.MSUF_ResetCastbarGlowFade(frame)
        return
    end

    local remaining = ToPlainNumber(remainingSeconds)
    local total = ToPlainNumber(totalSeconds)
    if type(remaining) ~= "number" or type(total) ~= "number" or total <= 0 then return end
    if remaining < 0 then remaining = 0 end
    if remaining > total then remaining = total end

    local progress = 1 - (remaining / total)
    if progress < 0 then progress = 0 elseif progress > 1 then progress = 1 end
    progress = progress * progress

    local statusBar = frame.statusBar
    local lastProgress = statusBar._msufGlowLastP
    if type(lastProgress) == "number" and math_abs(progress - lastProgress) < 0.02 then return end
    statusBar._msufGlowLastP = progress

    local baseR, baseG, baseB, baseA =
        statusBar._msufGlowBaseR,
        statusBar._msufGlowBaseG,
        statusBar._msufGlowBaseB,
        statusBar._msufGlowBaseA
    if type(baseR) ~= "number" or type(baseG) ~= "number" or type(baseB) ~= "number" then
        if statusBar.GetStatusBarColor then
            baseR, baseG, baseB, baseA = statusBar:GetStatusBarColor()
            statusBar._msufGlowBaseR = baseR
            statusBar._msufGlowBaseG = baseG
            statusBar._msufGlowBaseB = baseB
            statusBar._msufGlowBaseA = baseA
        end
    end
    if type(baseR) ~= "number" or type(baseG) ~= "number" or type(baseB) ~= "number" then return end
    if baseA == nil then baseA = 1 end

    local red = baseR + (1 - baseR) * progress
    local green = baseG + (1 - baseG) * progress
    local blue = baseB + (1 - baseB) * progress

    statusBar._msufGlowSkipBase = true
    if type(_G.MSUF_SetStatusBarColorIfChanged) == "function" then
        _G.MSUF_SetStatusBarColorIfChanged(statusBar, red, green, blue, baseA)
    else
        statusBar:SetStatusBarColor(red, green, blue, baseA)
    end
    statusBar._msufGlowSkipBase = nil
    statusBar._msufGlowApplied = true
end
ExportPublic("MSUF_ApplyCastbarGlowFade", ApplyCastbarGlowFade)

local function ApplyCastbarColor(frame, reason)
    if not (frame and frame.UpdateColorForInterruptible) then return end

    local result = frame:UpdateColorForInterruptible()
    if _G.MSUF_KickReady_RefreshFrame then _G.MSUF_KickReady_RefreshFrame(frame, reason) end
    return result
end
ExportPublic("MSUF_CB_ApplyColor", ApplyCastbarColor)

local function Utf8Truncate(text, maxChars)
    if not text or text == "" then return text, false end

    maxChars = tonumber(maxChars) or 0
    if maxChars <= 0 then return "", text ~= "" end

    local index, last, count = 1, #text, 0
    while index <= last and count < maxChars do
        local byte = string_byte(text, index)
        if not byte then break end
        if byte < 128 then
            index = index + 1
        elseif byte < 224 then
            index = index + 2
        elseif byte < 240 then
            index = index + 3
        else
            index = index + 4
        end
        count = count + 1
    end

    if index > last then return text, false end
    return string_sub(text, 1, index - 1), true
end

local function GetSpellNameShorteningConfig(frame)
    if not frame then return false end

    EnsureDBLazy()
    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    if not general then return false end

    local unit = GetCastbarUnitKey(frame)
    local modeValue = general.castbarSpellNameShortening
    local mode = tonumber(modeValue) or (modeValue == true and 1 or 0)
    if unit and tostring(unit):match("^boss") and general.bossCastSpellNameShortening ~= nil then
        local bossMode = general.bossCastSpellNameShortening
        mode = tonumber(bossMode) or (bossMode == true and 1 or bossMode == false and 0 or mode)
    end
    if mode <= 0 then return false end

    local maxLen = tonumber(general.castbarSpellNameMaxLen) or 30
    local reserved = tonumber(general.castbarSpellNameReservedSpace) or 8
    if unit and tostring(unit):match("^boss") then
        local bossMax = tonumber(general.bossCastSpellNameMaxLen or general.bossCastSpellNameMaxChars or general.bossSpellNameMaxLen)
        local bossReserved = tonumber(
            general.bossCastSpellNameReservedSpace
                or general.bossCastSpellNameReserved
                or general.bossSpellNameReservedSpace
        )
        if bossMax and bossMax > 0 then maxLen = bossMax end
        if bossReserved and bossReserved >= 0 then reserved = bossReserved end
    end

    maxLen = math_floor((tonumber(maxLen) or 30) + 0.5)
    if maxLen < 1 then maxLen = 1 elseif maxLen > 80 then maxLen = 80 end
    reserved = math_floor((tonumber(reserved) or 0) + 0.5)
    if reserved < 0 then reserved = 0 elseif reserved > 160 then reserved = 160 end

    local cacheKey = (_G.MSUF_CastbarStyleRevision or 1) .. ":" .. mode .. ":" .. maxLen .. ":" .. reserved
    return true, maxLen, reserved, cacheKey
end
ExportPublic("MSUF_GetCastbarSpellNameShorteningConfig", GetSpellNameShorteningConfig)

local function ShortenCastbarSpellName(frame, text)
    if text == nil then return text end

    local isSecret = _G.issecretvalue
    if type(isSecret) == "function" and isSecret(text) == true then return text end

    local valueType = type(text)
    if valueType ~= "string" and valueType ~= "number" and valueType ~= "boolean" then return text end

    local rawText = tostring(text or "")
    if rawText == "" then
        if frame then
            frame._msufRawCastText = rawText
            frame._msufShortCastText = rawText
            frame._msufShortCastTextKey = false
        end
        return rawText
    end

    local enabled, maxLen, _, cacheKey = GetSpellNameShorteningConfig(frame)
    if not enabled then
        if frame then
            frame._msufRawCastText = rawText
            frame._msufShortCastText = rawText
            frame._msufShortCastTextKey = false
        end
        return rawText
    end

    if frame
        and frame._msufRawCastText == rawText
        and frame._msufShortCastTextKey == cacheKey
        and frame._msufShortCastText ~= nil then
        return frame._msufShortCastText
    end

    local truncated, wasTruncated = Utf8Truncate(rawText, maxLen)
    local out = wasTruncated and (truncated .. "...") or rawText
    if frame then
        frame._msufRawCastText = rawText
        frame._msufShortCastText = out
        frame._msufShortCastTextKey = cacheKey
    end
    return out
end
ExportPublic("MSUF_ShortenCastbarSpellName", ShortenCastbarSpellName)

--- Pushback suffix ("+0.4"). delayTimeMs is NeverSecret in 12.x and is captured
--- once per cast into frame._msufPushbackMS, so this costs one field read per
--- text write. It is deliberately applied *after* shortening: the suffix must
--- survive truncation, and folding it into the shortener would also poison that
--- function's raw/short text cache. The active-cast guard keeps it off the
--- interrupt and failure labels, which reuse the same writer.
local function PushbackSuffix(frame)
    if not frame or frame.MSUF_castActive ~= true or frame.interrupted then return nil end

    local delayMS = frame._msufPushbackMS
    if type(delayMS) ~= "number" or delayMS <= 0 then return nil end

    EnsureDBLazy()
    local general = (_G.MSUF_DB and _G.MSUF_DB.general) or {}
    if general.castbarShowPushback ~= true then return nil end

    return string.format(" +%.1f", delayMS / 1000)
end

local function ComposeCastText(frame, text)
    local out = ShortenCastbarSpellName(frame, text)
    if type(out) ~= "string" then return out end

    local suffix = PushbackSuffix(frame)
    if suffix then return out .. suffix end
    return out
end

local function RefreshCastbarSpellNameText(frame)
    if not (frame and frame.castText) then return end

    local rawText = frame._msufRawCastText
    if rawText == nil then return end
    SetText(frame.castText, ComposeCastText(frame, rawText))
end
ExportPublic("MSUF_RefreshCastbarSpellNameText", RefreshCastbarSpellNameText)

local function ApplyCastbarTexts(frame, source, castText, timeText)
    if not frame then return end

    if source ~= nil then
        if castText == nil then castText = source.castText end
        if timeText == nil then timeText = source.timeText end
    end
    if castText ~= nil and frame.castText then SetText(frame.castText, ComposeCastText(frame, castText)) end
    if timeText ~= nil and frame.timeText then SetText(frame.timeText, timeText) end
end
ExportPublic("MSUF_CB_ApplyTexts", ApplyCastbarTexts)

local function ClearEmpowerState(frame)
    if not frame then return end

    frame.isEmpower = nil
    frame.empowerStartTime = nil
    frame.empowerStageEnds = nil
    frame.empowerTotalBase = nil
    frame.empowerTotalWithGrace = nil
    frame.empowerNextStage = nil
    frame.MSUF_empowerLayoutPending = nil
    frame.MSUF_wantsEmpower = nil
    frame.MSUF_empowerRetryCount = nil
    frame.MSUF_empowerRetryActive = nil
    frame._msufEmpowerTotalNum = nil
    frame._msufEmpowerStartNum = nil
    frame._msufEmpowerBaseNum = nil
    frame._msufEmpowerStageEndsNum = nil
    frame._msufEmpowerMinMaxSet = nil
    frame._msufEmpowerElapsed = nil
    frame._msufEmpowerTimerDriven = nil

    if frame.empowerTicks then
        for index = 1, #frame.empowerTicks do
            local tick = frame.empowerTicks[index]
            if tick then
                tick:Hide()
                if tick.MSUF_glow then tick.MSUF_glow:Hide() end
                if tick.MSUF_flash then tick.MSUF_flash:Hide() end
            end
        end
    end

    if frame.empowerSegments then
        for index = 1, #frame.empowerSegments do
            local segment = frame.empowerSegments[index]
            if segment then segment:Hide() end
        end
    end
end
ExportPublic("MSUF_ClearEmpowerState", ClearEmpowerState)
