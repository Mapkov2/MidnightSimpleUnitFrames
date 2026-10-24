-- Colors, previews, feedback, fill direction and spell-name shortening.
-- Namespace utilities; public aliases belong to PublicAPI.

local _, MSUF = ...
local Castbars = MSUF.Require("MSUF", "Castbars/MSUF_CastbarUtils.lua").Castbars
local Backend = Castbars.Backend
local Config = Castbars.Config
local Driver = Castbars.Driver
local Manager = Castbars.Manager
local Frames = Castbars.Frames
local KickReady = Castbars.KickReady
local PublicAPI = Castbars.PublicAPI
local Utils = Castbars.Utils

local Publish = PublicAPI.Publish

--- Kernel Util, Runtime/MSUF_Colors.lua and the cooldown integrations load
--- before this file and resolve once here.
local FILE = "Castbars/MSUF_CastbarUtils.lua"
local Require = MSUF.Require
local SetTextIfChanged = Require("MSUF_SetTextIfChanged", FILE)
local PixelLayoutRegion = Require("MSUF_PixelLayoutRegion", FILE)
local IsCooldownAnchorEnabled = Require("MSUF_IsCooldownAnchorEnabled", FILE)
local GetEffectiveCooldownFrame = Require("MSUF_GetEffectiveCooldownFrame", FILE)
local GetUsableCooldownAnchorSize = Require("MSUF_GetUsableCooldownAnchorSize", FILE)
local GetColorRGBFromKey = Require("MSUF_GetColorRGBFromKey", FILE)
local GetColorFromKey = Require("MSUF_GetColorFromKey", FILE)
local GetInterruptFeedbackCastColor = Require("MSUF_GetInterruptFeedbackCastColor", FILE)

local type = type
local tonumber = tonumber
local tostring = tostring
local string_byte = string.byte
local string_sub = string.sub
local math_floor = math.floor
local math_abs = math.abs
local IsSecretValue = type(issecretvalue) == "function" and issecretvalue
local CurveUtil = C_CurveUtil
local EvaluateColorFromBoolean = CurveUtil and type(CurveUtil.EvaluateColorFromBoolean) == "function"
    and CurveUtil.EvaluateColorFromBoolean

local function PlainPositiveNumber(value)
    local isSecret = issecretvalue
    if type(isSecret) == "function" and isSecret(value) == true then return nil end

    value = tonumber(value)
    if type(isSecret) == "function" and isSecret(value) == true then return nil end
    if type(value) ~= "number" then return nil end
    return value > 0 and value or nil
end

local function GetInterruptFeedbackDuration()
    local general = Config.Read().general
    local duration = general and tonumber(general.castbarInterruptFeedbackDuration)
    if type(duration) ~= "number" then
        duration = tonumber(Driver.INTERRUPT_FEEDBACK_DURATION) or 0.5
    end
    if duration < 0 then return 0 end
    if duration > 5 then return 5 end
    return duration
end
Utils.GetInterruptFeedbackDuration = GetInterruptFeedbackDuration

-- The castbar preview hard sync; this file is its only provider.
do
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

    Utils.HardSyncCastbarPreview = HardSyncCastbarPreview
end

local function EnsureDBLazy()
    Config.Read()
end
Utils.EnsureDBLazy = EnsureDBLazy

--- Single owner of the castbar OnUpdate teardown. Castbar Runtime and the
--- player runtime alias this instead of carrying their own copy.
local function DisableFrameOnUpdate(frame)
    if not frame or not frame.SetScript then return end
    frame:SetScript("OnUpdate", nil)
end
Utils.Castbar_DisableFrameOnUpdate = DisableFrameOnUpdate

local function GetAnchorFrame()
    local source = Config.Source()
    local general = (source and source.general) or {}
    -- The Integrations module answers first; otherwise the client model does.
    -- The C_CooldownViewer namespace is never the signal: the shared engine
    -- exposes it on every client, while only the Mainline family ships
    -- Blizzard's Cooldown Manager (Client.HostsCooldownManager).
    local cooldownAnchorEnabled = IsCooldownAnchorEnabled(general) == true
        or (MSUF.Client.HostsCooldownManager == true and general.anchorToCooldown == true)

    if cooldownAnchorEnabled then
        local cooldown = GetEffectiveCooldownFrame("EssentialCooldownViewer") or EssentialCooldownViewer
        if GetUsableCooldownAnchorSize(cooldown) ~= nil then
            return cooldown
        end
        return UIParent
    end

    local anchorName = general.anchorName
    if anchorName and anchorName ~= "" and anchorName ~= "EssentialCooldownViewer" then
        local frame = _G[anchorName]
        if frame and frame.IsShown and frame:IsShown() then
            return frame
        end
    end

    return UIParent
end
Utils.GetAnchorFrame = GetAnchorFrame
Publish("MSUF_GetAnchorFrame", Utils.GetAnchorFrame)

-- hot path: kept whole (perf rule)
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

-- This file is the only provider; its own writes below call the local.
Utils.SetStatusBarColorIfChanged = SetStatusBarColorIfChangedImpl

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
    cache.obj = CreateColor(red, green, blue, alpha)
    return cache.obj
end

local function CanUseBooleanTintValue(value)
    if IsSecretValue and IsSecretValue(value) == true then return true, true end
    return value ~= nil, false
end

-- hot path: kept whole (perf rule)
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
        and EvaluateColorFromBoolean
    local readySecret
    if useUnavailable then
        -- Keep the classification from the validity check; checking again in
        -- the native-color branch adds work for every restricted combat value.
        useUnavailable, readySecret = CanUseBooleanTintValue(interruptReadyBool)
    end

    local red = useNonInterruptible and nonR or castR
    local green = useNonInterruptible and nonG or castG
    local blue = useNonInterruptible and nonB or castB
    local alpha = useNonInterruptible and (nonA or 1) or (castA or 1)

    local texture = statusBar.GetStatusBarTexture and statusBar:GetStatusBarTexture()
    local usedBooleanTint = false
    if texture and texture.SetVertexColorFromBoolean and CreateColor then
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
            -- Native selection creates a result ColorObject. Public booleans
            -- can reuse the immutable configured colors directly; restricted
            -- inputs must still go through Blizzard's secret-safe selector.
            if readySecret then
                local selectReadyColor = KickReady.KickReady_SelectColor or EvaluateColorFromBoolean
                activeCastColor = selectReadyColor(interruptReadyBool, castColor, unavailableColor)
            elseif type(interruptReadyBool) == "boolean" then
                activeCastColor = interruptReadyBool and castColor or unavailableColor
            else
                activeCastColor = EvaluateColorFromBoolean(interruptReadyBool, castColor, unavailableColor)
            end
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
Utils.Castbar_ApplyNonInterruptibleTint = ApplyNonInterruptibleTint

local SetTextIfChanged = Require("MSUF_SetTextIfChanged", FILE)

local function SetText(textRegion, text)
    if not (textRegion and textRegion.SetText) then return end
    SetTextIfChanged(textRegion, text or "")
end

local function ResolveReverseFill(frame, override, isChanneled)
    if override and override.reverseFill ~= nil then
        return override.reverseFill == true
    end

    local resolver = Utils.GetCastbarReverseFillForFrame
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
Utils.GetReverseFillSafe = GetReverseFillSafe

--- How the bar value moves is a cast-type property, never an anchor property.
--- Casts and empower bars count up (elapsed time) so they fill toward the far
--- edge; a channel counts down (remaining time) so the same anchor drains and
--- its moving edge travels the opposite way. Unified direction makes channels
--- fill like a cast. This mirrors TimerDirection in the runtime, so the Lua
--- fallback paths render exactly what the native 12.1 timer renders.
local function GetCastbarCountsDown(frame, isChanneled)
    if isChanneled ~= true then return false end
    if frame and frame.isEmpower == true then return false end

    local general = (Config.Read().general) or {}
    return general.castbarUnifiedDirection ~= true
end
Utils.GetCastbarCountsDown = GetCastbarCountsDown

local function GetCastbarUnitKey(frame)
    if not frame then return nil end

    local unit = frame.unit or frame.MSUF_unit or frame._msufUnit or frame.unitKey
    if type(unit) == "string" and unit ~= "" then return unit end

    local key = frame._msufBarKey or frame.barKey or frame.key
    if type(key) == "string" and key ~= "" then
        if key == "player" or key == "target" or key == "focus" then return key end
        if key == "boss" or key:sub(1, 4) == "boss" then return key end
    end

    if frame == Frames.player or frame == Frames.playerPreview then return "player" end
    if frame == Frames.target or frame == Frames.targetPreview then return "target" end
    if frame == Frames.focus or frame == Frames.focusPreview then return "focus" end

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
    local general = (Config.Read().general) or {}
    local reverseFill = general.castbarFillDirection == "RTL"

    if general.castbarOpositeDirectionTarget == true then
        local unit = GetCastbarUnitKey(frame)
        if unit == "target" then
            reverseFill = not reverseFill
        end
    end

    return reverseFill
end
Utils.GetCastbarReverseFillForFrame = GetCastbarReverseFillForFrame
Publish("MSUF_GetCastbarReverseFillForFrame", Utils.GetCastbarReverseFillForFrame)

local function GetInterruptibleCastColor(general)
    general = general or Config.Read().general or {}
    local red = tonumber(general.castbarInterruptibleR)
    local green = tonumber(general.castbarInterruptibleG)
    local blue = tonumber(general.castbarInterruptibleB)
    if red and green and blue then return red, green, blue, 1 end
end
Utils.GetInterruptibleCastColor = GetInterruptibleCastColor

local function GetNonInterruptibleCastColor(general)
    general = general or Config.Read().general or {}
    local red = tonumber(general.castbarNonInterruptibleR)
    local green = tonumber(general.castbarNonInterruptibleG)
    local blue = tonumber(general.castbarNonInterruptibleB)
    if red and green and blue then return red, green, blue, 1 end
end
Utils.GetNonInterruptibleCastColor = GetNonInterruptibleCastColor

-- The custom colours come from this file's getters, the only owner of the
-- public aliases (Runtime/MSUF_Colors.lua keeps its palette-fallback getters
-- for the menu's MSUF._colorsAPI only).
local function ResolveCastbarColors()
    local general = Config.Read().general or {}

    local castR, castG, castB = GetInterruptibleCastColor(general)
    if not (castR and castG and castB) then
        local key = general.castbarInterruptibleColor or "teal"
        castR, castG, castB = GetColorRGBFromKey(key)
        if not (castR and castG and castB) then
            local color = GetColorFromKey(key)
            if color and color.GetRGB then castR, castG, castB = color:GetRGB() end
        end
    end
    if not (castR and castG and castB) then castR, castG, castB = 0, 0.85, 0.85 end

    local nonR, nonG, nonB = GetNonInterruptibleCastColor(general)
    if not (nonR and nonG and nonB) then
        local key = general.castbarNonInterruptibleColor or "red"
        nonR, nonG, nonB = GetColorRGBFromKey(key)
        if not (nonR and nonG and nonB) then
            local color = GetColorFromKey(key)
            if color and color.GetRGB then nonR, nonG, nonB = color:GetRGB() end
        end
    end
    if not (nonR and nonG and nonB) then nonR, nonG, nonB = 0.9, 0.1, 0.1 end

    return castR, castG, castB, nonR, nonG, nonB
end
Utils.ResolveCastbarColors = ResolveCastbarColors
Publish("MSUF_ResolveCastbarColors", Utils.ResolveCastbarColors)

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

    local general = (Config.Read().general) or {}
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
Utils.PlayCastbarShake = PlayCastbarShake

local function GetInterruptUnavailableCastColor()
    local general = (Config.Read().general) or {}
    local red = tonumber(general.castbarInterruptUnavailableR)
    local green = tonumber(general.castbarInterruptUnavailableG)
    local blue = tonumber(general.castbarInterruptUnavailableB)
    if red and green and blue then return red, green, blue, 1 end
end
Utils.GetInterruptUnavailableCastColor = GetInterruptUnavailableCastColor

local function ResolveInterruptFeedbackCastColor()

    do
        local red, green, blue = GetInterruptFeedbackCastColor()
        if red and green and blue then return red, green, blue, 1 end
    end

    local general = (Config.Read().general) or {}
    local red = tonumber(general.castbarInterruptFeedbackR)
    local green = tonumber(general.castbarInterruptFeedbackG)
    local blue = tonumber(general.castbarInterruptFeedbackB)
    if red and green and blue then return red, green, blue, 1 end

    local key = general.castbarInterruptFeedbackColor or "yellow"
    red, green, blue = GetColorRGBFromKey(key)
    if red and green and blue then return red, green, blue, 1 end

    local color = GetColorFromKey(key)
    if color and color.GetRGB then
        red, green, blue = color:GetRGB()
        if red and green and blue then return red, green, blue, 1 end
    end

    return 1.0, 0.82, 0.0, 1
end
Utils.ResolveInterruptFeedbackCastColor = ResolveInterruptFeedbackCastColor
Publish("MSUF_ResolveInterruptFeedbackCastColor", Utils.ResolveInterruptFeedbackCastColor)

--- Interrupt-ready units: a castbar unit's config row (target, focus, boss for
--- boss and bossN, arena for arena and arenaN; nil for any other unit) and the
--- setting that shows the indicator on it. The one rule for the indicator
--- (MSUF_InterruptReady.lua) and the unavailable tint below.
local KICK_READY_SHOW_KEY = {
    target = "kickReadyShowTarget",
    focus = "kickReadyShowFocus",
    boss = "kickReadyShowBoss",
    arena = "kickReadyShowArena",
}

local function KickReadyUnitKey(unit)
    if type(unit) ~= "string" then return nil end
    if KICK_READY_SHOW_KEY[unit] then return unit end
    if unit:match("^boss%d+$") then return "boss" end
    if unit:match("^arena%d+$") then return "arena" end
    return nil
end

--- unit token -> its config row or false, classified once per token (the
--- indicator asks for every castbar on every cooldown event).
local KICK_READY_ROW = setmetatable({}, { __index = function(rows, unit)
    local row = KickReadyUnitKey(unit) or false
    rawset(rows, unit, row)
    return row
end })

MSUF.Castbars = MSUF.Castbars or {}
MSUF.Castbars.KickReadyUnits = { Key = KickReadyUnitKey, ShowKey = KICK_READY_SHOW_KEY, Row = KICK_READY_ROW }

local function UnitSupportsInterruptUnavailableTint(frame, general)
    local unit = frame and frame.unit
    local key = unit and KICK_READY_ROW[unit]
    if not key or general[KICK_READY_SHOW_KEY[key]] ~= true then return false end
    -- Resolve live ownership directly; no per-query closure is needed.
    local shouldUse = Backend.ShouldUseMSUFCastbar
    return type(shouldUse) ~= "function" or shouldUse(key, general) == true
end

local function ShouldUseInterruptUnavailableColor(frame)
    local general = (Config.Read().general) or {}
    if general.kickReadyStyle ~= "fill" then return false end
    return UnitSupportsInterruptUnavailableTint(frame, general)
end
Utils.Castbar_ShouldUseInterruptUnavailableColor = ShouldUseInterruptUnavailableColor

local function ResolveInterruptUnavailableCastColor()
    local general = (Config.Read().general) or {}
    local red, green, blue

    -- This file's getter (the public alias's only owner).
    red, green, blue = GetInterruptUnavailableCastColor()

    if not (red and green and blue) then
        local key = general.castbarInterruptUnavailableColor
        local color = key and GetColorFromKey(key) or nil
        if color and color.GetRGB then
            red, green, blue = color:GetRGB()
        end
    end

    if not (red and green and blue) then
        red, green, blue = 1.0, 0.494117647, 0.137254902
    end

    return red, green, blue, 1
end
Utils.ResolveInterruptUnavailableCastColor = ResolveInterruptUnavailableCastColor
Publish("MSUF_ResolveInterruptUnavailableCastColor", Utils.ResolveInterruptUnavailableCastColor)

local function GetInterruptUnavailableTintArgs(frame)
    if not ShouldUseInterruptUnavailableColor(frame) then return nil end
    if not (C_CurveUtil and type(C_CurveUtil.EvaluateColorFromBoolean) == "function") then return nil end
    if type(KickReady.KickReady_GetSpellID) == "function" and not KickReady.KickReady_GetSpellID() then return nil end

    local readyBool
    if type(KickReady.KickReady_GetReadyBoolForTint) == "function" then
        readyBool = KickReady.KickReady_GetReadyBoolForTint()
    elseif type(KickReady.KickReady_IsReady) == "function" then
        readyBool = KickReady.KickReady_IsReady()
    end
    if not CanUseBooleanTintValue(readyBool) then return nil end

    local red, green, blue, alpha = ResolveInterruptUnavailableCastColor()
    return red, green, blue, alpha or 1, readyBool, true
end
Utils.Castbar_GetInterruptUnavailableTintArgs = GetInterruptUnavailableTintArgs

local toPlainIsSecret = issecretvalue
local toPlainHuge = math.huge

--- Canonical castbar scalar unwrapper. Dragonflight+ APIs may return value
--- wrappers; convert only to plain finite numbers so callers can compare and
--- cache safely. Secret values, nan and inf all come back as nil.
---
--- This file loads before Runtime, Engine, Driver, PlayerCastbarRuntime,
--- Castbars.lua, Empower and GCD, which alias the MSUF_Castbar_PlainNumber
--- export instead of carrying a body of their own. A harness that loads one of
--- those files standalone has to load this file first.
local function PlainNumber(value)
    -- A secret is rejected before anything compares it, nil included.
    if toPlainIsSecret(value) == true or value == nil then
        return nil
    end

    -- The duration APIs normally return an ordinary number. Avoid ToPlain and
    -- the allocating tostring/tonumber round-trip on that overwhelmingly hot
    -- path while retaining the wrapper fallback below.
    if type(value) == "number"
        and value == value and value ~= toPlainHuge and value ~= -toPlainHuge then
        return value
    end

    local toPlain = ToPlain
    if type(toPlain) == "function" then
        local plain = toPlain(value)
        if plain ~= nil and toPlainIsSecret(plain) ~= true then
            local plainType = type(plain)
            if plainType == "number" then
                if plain == plain and plain ~= toPlainHuge and plain ~= -toPlainHuge then
                    return plain
                end
                return nil
            elseif plainType == "string" then
                return tonumber(plain)
            end

            -- Compatibility fallback for an unexpected ToPlain wrapper type.
            return tonumber(tostring(plain))
        end
    end

    local valueType = type(value)
    if valueType == "number" then
        if value == value and value ~= toPlainHuge and value ~= -toPlainHuge then
            return value
        end
    elseif valueType == "string" then
        return tonumber(value)
    end

    return nil
end
Utils.Castbar_PlainNumber = PlainNumber

local glowEnabledCache
local glowEnabledRevision = -1

local function IsCastbarGlowEnabled()
    local revision = Config.revision
    if glowEnabledRevision == revision and glowEnabledCache ~= nil then
        return glowEnabledCache
    end

    local general = (Config.Read().general) or nil
    glowEnabledCache = not (general and general.castbarShowGlow == false)
    glowEnabledRevision = revision
    return glowEnabledCache
end

local function ResetCastbarGlowFade(frame)
    local statusBar = frame and frame.statusBar
    if not statusBar then return end
    if statusBar._msufGlowOverlay then statusBar._msufGlowOverlay:Hide() end
    statusBar._msufGlowApplied = nil
    statusBar._msufGlowLastP = nil
end
Utils.ResetCastbarGlowFade = ResetCastbarGlowFade
Publish("MSUF_ResetCastbarGlowFade", Utils.ResetCastbarGlowFade)

-- One white overlay per castbar while the glow is on. Rounded and slanted
-- castbars build it on their cold apply and mask it with the bar's surface
-- (Castbars/MSUF_CastbarRounded.lua), so it never spills past the shape.
-- enabled: the caller's fresh read of the setting (the texture pass can run
-- before the cast-time revision that refreshes IsCastbarGlowEnabled is bumped).
local function EnsureCastbarGlowOverlay(statusBar, enabled)
    local overlay = statusBar._msufGlowOverlay
    if enabled == nil then enabled = IsCastbarGlowEnabled() end
    if overlay or not enabled then return overlay end
    overlay = PixelLayoutRegion(statusBar:CreateTexture(nil, "ARTWORK", nil, 1))
    overlay:SetColorTexture(1, 1, 1, 1)
    overlay:SetBlendMode("BLEND")
    overlay:Hide()
    statusBar._msufGlowOverlay = overlay
    return overlay
end
MSUF.Castbars.EnsureGlowOverlay = EnsureCastbarGlowOverlay

local function ApplyCastbarGlowFade(frame, remainingSeconds, totalSeconds)
    if not frame or not frame.statusBar then return end
    if (frame._msufIsPreview or frame.MSUF_testMode) and not MSUF_UnitEditModeActive then return end
    if frame.interrupted then return end

    if frame.interruptFeedbackEndTime then
        local now = (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
        if now < frame.interruptFeedbackEndTime then return end
    end

    if not IsCastbarGlowEnabled() then
        Utils.ResetCastbarGlowFade(frame)
        return
    end

    local remaining = PlainNumber(remainingSeconds)
    local total = PlainNumber(totalSeconds)
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

    -- Blend white over the native fill geometry. This is the same linear
    -- brightening as the old RGB interpolation, without overwriting native
    -- boolean-selected interruptibility/unavailable colors or reading them.
    local texture = statusBar.GetStatusBarTexture and statusBar:GetStatusBarTexture()
    if not texture then return end
    local overlay = statusBar._msufGlowOverlay
    if not overlay then
        overlay = EnsureCastbarGlowOverlay(statusBar)
        local maskGlow = MSUF.Castbars.MaskGlowOverlay
        if maskGlow then maskGlow(frame) end
    end
    if statusBar._msufGlowTexture ~= texture then
        overlay:ClearAllPoints()
        overlay:SetAllPoints(texture)
        statusBar._msufGlowTexture = texture
    end
    overlay:SetAlpha(progress)
    overlay:Show()
    statusBar._msufGlowApplied = true
end
Utils.ApplyCastbarGlowFade = ApplyCastbarGlowFade
Publish("MSUF_ApplyCastbarGlowFade", Utils.ApplyCastbarGlowFade)

local function ApplyCastbarColor(frame, reason)
    if not (frame and frame.UpdateColorForInterruptible) then return end

    local result = frame:UpdateColorForInterruptible()
    if KickReady.KickReady_RefreshFrame then KickReady.KickReady_RefreshFrame(frame, reason) end
    return result
end
Utils.CB_ApplyColor = ApplyCastbarColor

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

--- Measures a candidate string in the spell text's own font. Mirrors
--- ApproxNameWidth in MSUF_UF_Text_Layout: a hidden, never-anchored FontString
--- keeps the measurement out of the live region, so no anchoring aspect can
--- turn GetStringWidth secret on it.
local measureFS
--- Points the shared ruler at the source FontString's face. Returns it ready to
--- measure, or nil when the font cannot be resolved. Hoisted out of the
--- measuring loop so a fit pays one GetFont, not one per search step.
local function PrepareRuler(sourceFS)
    if not (sourceFS and sourceFS.GetFont) then return nil end
    local font, size, flags = sourceFS:GetFont()
    if not (font and size) then return nil end

    if not measureFS then
        local parent = UIParent
        if not (parent and parent.CreateFontString) then return nil end
        measureFS = PixelLayoutRegion(parent:CreateFontString(nil, "OVERLAY", "GameFontNormal"), true)
        if not measureFS then return nil end
        measureFS:Hide()
        if measureFS.SetWordWrap then measureFS:SetWordWrap(false) end
    end
    if measureFS._msufFont ~= font or measureFS._msufSize ~= size or measureFS._msufFlags ~= flags then
        -- SetFont reports false for a font file that cannot be loaded; measuring
        -- against the previous face would silently mis-size the budget.
        if measureFS:SetFont(font, size, flags) == false then return nil end
        measureFS._msufFont, measureFS._msufSize, measureFS._msufFlags = font, size, flags
    end
    return measureFS
end

local function RulerWidth(ruler, text)
    ruler:SetText(text)
    local width = ruler:GetStringWidth()
    if type(width) ~= "number" then return nil end
    return width
end

--- Warm companion to the cold pixel budget, called after the character cap has
--- already been applied. WoW truncates a bounded one-line FontString silently
--- and at a glyph-dependent position, which is what made a 23-character name
--- disappear under a 25-character setting (GitHub #121). Measuring the real
--- string instead cuts in Lua, always on a character boundary and always with
--- visible dots. Never reached for secret cast names - the caller returns those
--- untouched before this runs.
local function FitToBoxWidth(fs, text, fitWidth)
    local ruler = PrepareRuler(fs)
    if not ruler then return text, false end
    local full = RulerWidth(ruler, text)
    -- The overwhelmingly common case is a name that already fits: one measure,
    -- no allocation, done.
    if not full or full <= fitWidth then return text, false end

    -- Binary search the longest character prefix whose rendered width, dots
    -- included, still fits. #text is a safe upper bound: Utf8Truncate clamps to
    -- the real character count, so multi-byte names just converge a step later.
    local low, high, best = 0, #text, nil
    while low <= high do
        local mid = math_floor((low + high) / 2)
        local candidate = (Utf8Truncate(text, mid)) .. "..."
        local width = RulerWidth(ruler, candidate)
        if not width then return text, false end
        if width <= fitWidth then
            best = candidate
            low = mid + 1
        else
            high = mid - 1
        end
    end
    if best == nil then return text, false end
    return best, true
end

--- general.castbarSpellNameShortening / bossCastSpellNameShortening (saved):
--- the menu writes OFF or ON; older profiles may hold true/false or a larger
--- mode number, which counts as on. MODE_KEY_MAX bounds the field the cache
--- key packs (modes above it fold onto it: only on/off is decided).
local SPELL_NAME_SHORTENING = { OFF = 0, ON = 1, MODE_KEY_MAX = 3 }
MSUF.Castbars = MSUF.Castbars or {}
MSUF.Castbars.SpellNameShortening = SPELL_NAME_SHORTENING

local function ShorteningMode(value, fallback)
    local mode = tonumber(value)
    if mode then return mode end
    if value == true then return SPELL_NAME_SHORTENING.ON end
    if value == false then return SPELL_NAME_SHORTENING.OFF end
    return fallback
end

local function GetSpellNameShorteningConfig(frame)
    if not frame then return false end

    local general = (Config.Read().general) or nil
    if not general then return false end

    local unit = GetCastbarUnitKey(frame)
    -- This runs on every castbar text write, so resolve "is this a boss bar"
    -- once with a plain prefix compare instead of two tostring+pattern passes.
    local isBoss = unit ~= nil and string_sub(tostring(unit), 1, 4) == "boss"
    local mode = ShorteningMode(general.castbarSpellNameShortening, SPELL_NAME_SHORTENING.OFF)
    if isBoss and general.bossCastSpellNameShortening ~= nil then
        mode = ShorteningMode(general.bossCastSpellNameShortening, mode)
    end
    if mode <= SPELL_NAME_SHORTENING.OFF then return false end

    local maxLen = tonumber(general.castbarSpellNameMaxLen) or 30
    local reserved = tonumber(general.castbarSpellNameReservedSpace) or 8
    if isBoss then
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

    -- The pixel box the cold layout handed this frame is part of the verdict:
    -- an Edit Mode resize changes it without bumping the style revision, and a
    -- stale cache would replay a fit computed for the old width.
    local fitWidth = tonumber(frame._msufSpellTextFitWidth) or 0
    if fitWidth < 0 then fitWidth = 0 elseif fitWidth > 4000 then fitWidth = 4000 end
    -- Packed as a number rather than a concatenated string: that concatenation
    -- was the one allocation every text write paid before the cache could even
    -- be consulted. Every field is clamped below its factor (mode <= MODE_KEY_MAX
    -- < 4, maxLen <= 80 < 128, reserved <= 160 < 256, fitWidth <= 4000 < 4096)
    -- so no two configurations can pack to the same number. mode only ever
    -- decides on/off above, so folding larger modes onto MODE_KEY_MAX costs nothing.
    local modeKeyMax = SPELL_NAME_SHORTENING.MODE_KEY_MAX
    local modeKey = mode > modeKeyMax and modeKeyMax or mode
    local revision = tonumber(Config.textureRevision) or 1
    local cacheKey = (((revision * 4 + modeKey) * 128 + maxLen) * 256 + reserved)
        * 4096 + math_floor(fitWidth + 0.5)
    return true, maxLen, reserved, cacheKey
end
Utils.GetCastbarSpellNameShorteningConfig = GetSpellNameShorteningConfig

local function ShortenCastbarSpellName(frame, text)
    local isSecret = issecretvalue
    if type(isSecret) == "function" and isSecret(text) == true then
        -- A secret name is neither measured nor cached, but the previous plain
        -- name must go too: RefreshCastbarSpellNameText (the cold re-layout)
        -- would otherwise repaint it over the current secret one.
        if frame then
            frame._msufRawCastText = nil
            frame._msufShortCastText = nil
            frame._msufShortCastTextKey = false
        end
        return text
    end
    if text == nil then return text end

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

    -- The character cap is only half the budget - the cold layout also bounded
    -- this FontString in pixels. Fitting here, where the text is known to be a
    -- plain string, keeps the cut on a character boundary with visible dots
    -- instead of wherever the renderer silently clips (GitHub #121).
    local fitWidth = frame and tonumber(frame._msufSpellTextFitWidth)
    if fitWidth and fitWidth > 0 and frame.castText then
        out = (FitToBoxWidth(frame.castText, out, fitWidth))
    end

    if frame then
        frame._msufRawCastText = rawText
        frame._msufShortCastText = out
        frame._msufShortCastTextKey = cacheKey
    end
    return out
end
Utils.ShortenCastbarSpellName = ShortenCastbarSpellName
Publish("MSUF_ShortenCastbarSpellName", Utils.ShortenCastbarSpellName)

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

    local general = (Config.Read().general) or {}
    if general.castbarShowPushback ~= true then return nil end

    return string.format(" +%.1f", delayMS / 1000)
end

--- Cold path (one call per cast apply): the pushback delay for the suffix.
--- A client delayTimeMS wins whenever it exists. The legacy Classic tuple has
--- none, but UNIT_SPELLCAST_DELAYED moves the cast's start time forward, so the
--- delay there is the shift from the first start seen for the same castID.
--- Channels and casts carrying a Retail castBarID never use the legacy measure.
--- The identity fields are frame-local and survive the timing resets on purpose:
--- the re-read after DELAYED runs those resets before it asks for the delay.
local function ResolveCastbarPushbackMS(frame, state)
    if not state then return nil end

    local delayMS = PlainNumber(state.delayTimeMS)
    if delayMS ~= nil or not frame then return delayMS end

    if state.castType ~= "CAST" or state.castBarID ~= nil then
        frame._msufPushbackCastID = nil
        frame._msufPushbackStartMS = nil
        return nil
    end

    local castID = state.castID
    local startMS = PlainNumber(state.startTimeMS)
    if castID == nil or startMS == nil or (IsSecretValue and IsSecretValue(castID) == true) then
        frame._msufPushbackCastID = nil
        frame._msufPushbackStartMS = nil
        return nil
    end

    if castID ~= frame._msufPushbackCastID then
        frame._msufPushbackCastID = castID
        frame._msufPushbackStartMS = startMS
        return nil
    end

    local moved = startMS - frame._msufPushbackStartMS
    if moved > 0 then return moved end
    return nil
end
Utils.Castbar_ResolvePushbackMS = ResolveCastbarPushbackMS

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
Utils.RefreshCastbarSpellNameText = RefreshCastbarSpellNameText

local function ApplyCastbarTexts(frame, source, castText, timeText)
    if not frame then return end

    if source ~= nil then
        if castText == nil then castText = source.castText end
        if timeText == nil then timeText = source.timeText end
    end
    if ((IsSecretValue and IsSecretValue(castText)) or castText ~= nil) and frame.castText then
        SetText(frame.castText, ComposeCastText(frame, castText))
    end
    if timeText ~= nil and frame.timeText then SetText(frame.timeText, timeText) end
end
Utils.CB_ApplyTexts = ApplyCastbarTexts
Publish("MSUF_CB_ApplyTexts", Utils.CB_ApplyTexts)

-- hot path: kept whole (perf rule)
local function ClearEmpowerState(frame, hideFrame)
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

    local ticks = frame.empowerTicks
    if ticks then
        for index = 1, #ticks do
            local tick = ticks[index]
            if tick then
                tick:Hide()
                if tick.MSUF_glow then tick.MSUF_glow:Hide() end
                if tick.MSUF_flash then tick.MSUF_flash:Hide() end
            end
        end
    end

    local segments = frame.empowerSegments
    if segments then
        for index = 1, #segments do
            local segment = segments[index]
            if segment then segment:Hide() end
        end
    end

    -- Player-only hide policy. Shared cast/channel clears omit hideFrame.
    if hideFrame then
        frame:SetScript("OnUpdate", nil)
        Manager.UnregisterCastbar(frame)
        if frame.timeText then SetTextIfChanged(frame.timeText, "") end
        if frame.latencyBar then frame.latencyBar:Hide() end
        frame:Hide()
    end
end
Utils.ClearEmpowerState = ClearEmpowerState

-- Shared scalar timing state only. Duration ownership and stop/bridge policy
-- stay with their callers; pushback identity survives delayed re-reads.
local function ResetTimingScalars(frame)
    frame.endTime = nil
    frame._msufPlainEndTime = nil
    frame._msufPlainTotal = nil
    frame._msufRemaining = nil
    frame._msufLastTimeDecimal = nil
    frame._msufTimerAssumeCountdown = nil
    frame._msufCountsDown = nil
    frame._msufPushbackMS = nil
    frame._msufZeroCount = nil
end
Utils.ResetTimingScalars = ResetTimingScalars

local function EnsureGeneralDB()
    return Config.EnsureSource().general
end

Utils.EnsureCastbarGeneralDB = EnsureGeneralDB

local function CastTimeUnitKey(frame, unit)
    unit = tostring(unit or ""):lower()
    if frame and frame._msufIsBossCastbar then return "boss" end
    if frame and frame._msufIsArenaCastbar then return "arena" end
    if unit:match("^boss%d+$") then return "boss" end
    if unit:match("^arena%d+$") then return "arena" end
    return unit
end
Utils.CastTimeUnitKey = CastTimeUnitKey
