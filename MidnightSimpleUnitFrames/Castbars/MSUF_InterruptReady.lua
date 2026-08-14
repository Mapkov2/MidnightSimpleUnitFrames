--- Castbars/MSUF_InterruptReady.lua
--- Optional interrupt-readiness indicator for target, focus, and boss castbars.
---
--- This module answers two questions: "is my interrupt cooldown ready?" and
--- "how should the indicator look for the current cast's interruptibility?" It
--- must not decide castbar ownership or spellcast state; it decorates frames
--- that the castbar drivers already own.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local SpellAPI = _G.C_Spell
local TimerAPI = _G.C_Timer
local CurveAPI = _G.C_CurveUtil
local EvaluateColorValueFromBoolean = CurveAPI and CurveAPI.EvaluateColorValueFromBoolean
local EvaluateColorFromBoolean = CurveAPI and CurveAPI.EvaluateColorFromBoolean

local INTERRUPT_SPELLS = {
    DEATHKNIGHT = { DEFAULT = 47528 },
    DEMONHUNTER = { DEFAULT = 183752 },
    DRUID = { DEFAULT = 106839, BALANCE = 78675 },
    EVOKER = { DEFAULT = 351338 },
    HUNTER = { DEFAULT = 147362, SURVIVAL = 187707 },
    MAGE = { DEFAULT = 2139 },
    MONK = { DEFAULT = 116705 },
    PALADIN = { DEFAULT = 96231 },
    PRIEST = { DEFAULT = 15487 },
    ROGUE = { DEFAULT = 1766 },
    SHAMAN = { DEFAULT = 57994 },
    WARLOCK = { DEFAULT = 19647, DEMONOLOGY = 119914 },
    WARRIOR = { DEFAULT = 6552 },
}

local SPECIALIZATION_KEYS = {
    [102] = "BALANCE",
    [255] = "SURVIVAL",
    [266] = "DEMONOLOGY",
}

local state = {}
local cooldownTimerGeneration = 0
local cooldownTimerEndTime
local cooldownWakeFrame
local cooldownWakeArmed = false
local eventFrame
local cooldownEventRegistered = false
local activeIndicatorFrames = {}
local activeIndicatorFrameCount = 0
local fillActiveFrames = {}
local fillActiveFrameCount = 0
local refreshActiveFrames = {}
local UpdateCooldownEventRegistration
local UpdateLifecycleEventRegistration
local ClearCooldownWake
local HandleCooldownWakeDone
local cooldownSnapshot
local cooldownSnapshotSpellID
local cooldownSnapshotFrameStamp
local cooldownSnapshotKnown = false

local function InvalidateCooldownSnapshot()
    cooldownSnapshot = nil
    cooldownSnapshotSpellID = nil
    cooldownSnapshotFrameStamp = nil
    cooldownSnapshotKnown = false
end

local function GeneralDB()
    if type(_G.MSUF_EnsureDB) == "function" then
        _G.MSUF_EnsureDB()
    elseif type(EnsureDB) == "function" then
        EnsureDB()
    end

    return (_G.MSUF_DB and _G.MSUF_DB.general) or {}
end

local plainIsSecret = _G.issecretvalue or function(_) return false end
local plainHuge = math.huge

local function HasKnownValue(value)
    if plainIsSecret(value) == true then
        return true
    end

    return value ~= nil
end

local function PlainNumber(value)
    if plainIsSecret(value) == true then
        local toPlain = _G.ToPlain
        if type(toPlain) ~= "function" then return nil end
        value = toPlain(value)
        if plainIsSecret(value) == true then return nil end
    end

    if value == nil then
        return nil
    end

    -- PERF fast path: a plain finite number needs no tostring/tonumber
    -- round-trip (that round-trip only exists to redact secrets and to map
    -- nan/inf to nil, which the guards below preserve exactly).
    if type(value) == "number"
        and value == value and value ~= plainHuge and value ~= -plainHuge then
        return value
    end

    local valueType = type(value)
    if valueType == "number" then
        if value == value and value ~= plainHuge and value ~= -plainHuge then
            return value
        end
        return nil
    elseif valueType == "string" then
        return tonumber(value)
    end

    return nil
end

local function Now()
    return (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
end

--- Resolve the player's current interrupt spell once per class/spec change.
--- Some classes swap interrupt IDs by specialization, so cache both class/spec
--- metadata with the selected spell.
local function ResolveInterruptSpellID()
    local previousSpellID = state.spellID
    local classToken
    if UnitClass then
        local _, token = UnitClass("player")
        classToken = token
    end
    state.classToken = classToken

    local classSpells = classToken and INTERRUPT_SPELLS[classToken]
    local spellID = classSpells and classSpells.DEFAULT

    if classSpells and GetSpecialization and GetSpecializationInfo then
        local specID = select(1, GetSpecializationInfo(GetSpecialization()))
        local specKey = SPECIALIZATION_KEYS[specID]

        if specKey and classSpells[specKey] then
            spellID = classSpells[specKey]
        end

        state.specID = specID
    end

    if previousSpellID and previousSpellID ~= spellID then
        state.previousSpellID = previousSpellID
    end
    if previousSpellID ~= spellID then
        InvalidateCooldownSnapshot()
    end
    state.spellID = spellID
    return spellID
end

--- Unrelated spell and GCD events cannot change the dedicated interrupt
--- cooldown because InterruptCooldown explicitly ignores the GCD. Nil-ID
--- broadcasts remain relevant, as do current and previous override IDs.
local function NeedsInterruptCooldownUpdate(spellID, baseSpellID)
    if spellID == nil then return true end

    local interruptSpellID = state.spellID or ResolveInterruptSpellID()
    if spellID == interruptSpellID or baseSpellID == interruptSpellID then
        return true
    end

    local previousSpellID = state.previousSpellID
    return previousSpellID ~= nil
        and (spellID == previousSpellID or baseSpellID == previousSpellID)
end

local function InterruptCooldown()
    local spellID = state.spellID or ResolveInterruptSpellID()
    if not (spellID and SpellAPI and SpellAPI.GetSpellCooldownDuration) then
        return nil
    end

    -- GetSpellCooldownDuration creates a LuaDurationObject. Share it only
    -- inside the current rendered frame; relevant cooldown/spec/world events
    -- invalidate before their refresh. This removes cast/color refresh-burst
    -- allocation without depending on undocumented cross-event object lifetime.
    local frameStamp = _G.GetTime and _G.GetTime()
    if frameStamp ~= nil
        and cooldownSnapshotKnown == true
        and cooldownSnapshotFrameStamp == frameStamp
        and cooldownSnapshotSpellID == spellID
    then
        return cooldownSnapshot
    end

    local cooldown = SpellAPI.GetSpellCooldownDuration(spellID, true)
    if frameStamp ~= nil then
        cooldownSnapshot = cooldown
        cooldownSnapshotSpellID = spellID
        cooldownSnapshotFrameStamp = frameStamp
        cooldownSnapshotKnown = true
    end
    return cooldown
end

local function CooldownRemaining(cooldown)
    if not cooldown then
        return nil
    end

    local remaining
    if cooldown.GetRemainingDuration then
        remaining = cooldown:GetRemainingDuration()
    elseif cooldown.GetRemaining then
        remaining = cooldown:GetRemaining()
    end

    return PlainNumber(remaining)
end

local function CooldownReadyValue(cooldown, remaining)
    if remaining ~= nil then
        return remaining <= 0.05
    end

    if cooldown and cooldown.IsZero then
        local ready = cooldown:IsZero()
        if HasKnownValue(ready) then
            return ready
        end
    end

    return nil
end

local function InterruptStatus(cooldown, cooldownResolved)
    if cooldownResolved ~= true then
        cooldown = InterruptCooldown()
    end
    local remaining = CooldownRemaining(cooldown)
    local ready = CooldownReadyValue(cooldown, remaining)

    if not HasKnownValue(ready) then
        ready = false
    end

    return ready, remaining, cooldown
end

local function ResolveStatus(status)
    if type(status) == "table" then
        if not status.resolved then
            if status.cooldownResolved ~= true then
                status.cooldown = InterruptCooldown()
                status.cooldownResolved = true
            end
            status.ready, status.remaining = InterruptStatus(status.cooldown, true)
            status.resolved = true
        end

        return status.ready
    end

    local ready = InterruptStatus()
    return ready
end

local function InterruptReady()
    local ready = InterruptStatus()
    return ready
end

local function InterruptReadyBoolForTint()
    local cooldown = InterruptCooldown()
    if cooldown and cooldown.IsZero then
        return cooldown:IsZero()
    end

    return InterruptReady()
end

local function ColorFromDB(general, key, defaultR, defaultG, defaultB)
    local color = general[key]
    if type(color) == "table" then
        defaultR = tonumber(color[1] or color["1"]) or defaultR
        defaultG = tonumber(color[2] or color["2"]) or defaultG
        defaultB = tonumber(color[3] or color["3"]) or defaultB
    end

    return defaultR, defaultG, defaultB, 1
end

--- Color objects are cached because indicator refreshes can happen from both
--- spellcast events and cooldown timers.
local function ReadyColors(general)
    general = general or GeneralDB()

    local readyR, readyG, readyB, readyA = ColorFromDB(general, "kickReadyColor", 0, 1, 0)
    local notReadyR, notReadyG, notReadyB, notReadyA = ColorFromDB(general, "kickNotReadyColor", 1, 0, 0)

    if state.readyR == readyR
        and state.readyG == readyG
        and state.readyB == readyB
        and state.readyA == readyA
        and state.notReadyR == notReadyR
        and state.notReadyG == notReadyG
        and state.notReadyB == notReadyB
        and state.notReadyA == notReadyA
        and state.readyColor
        and state.notReadyColor
    then
        return state.readyColor, state.notReadyColor
    end

    state.readyR, state.readyG, state.readyB, state.readyA = readyR, readyG, readyB, readyA
    state.notReadyR, state.notReadyG, state.notReadyB, state.notReadyA = notReadyR, notReadyG, notReadyB, notReadyA

    if _G.CreateColor then
        state.readyColor = _G.CreateColor(readyR, readyG, readyB, readyA)
        state.notReadyColor = _G.CreateColor(notReadyR, notReadyG, notReadyB, notReadyA)
        return state.readyColor, state.notReadyColor
    end

    state.readyColor = {
        GetRGBA = function()
            return readyR, readyG, readyB, readyA
        end,
    }
    state.notReadyColor = {
        GetRGBA = function()
            return notReadyR, notReadyG, notReadyB, notReadyA
        end,
    }

    return state.readyColor, state.notReadyColor
end

local function ColorForReady(isReady, general)
    local readyColor, notReadyColor = ReadyColors(general)
    if plainIsSecret(isReady) == true then
        if EvaluateColorFromBoolean then
            return EvaluateColorFromBoolean(isReady, readyColor, notReadyColor)
        end
        return notReadyColor
    end

    return isReady == true and readyColor or notReadyColor
end

local function RGBAForReady(isReady, general)
    general = general or GeneralDB()
    if isReady == true then
        return ColorFromDB(general, "kickReadyColor", 0, 1, 0)
    end
    return ColorFromDB(general, "kickNotReadyColor", 1, 0, 0)
end

local function ShouldShow(general, unit)
    if unit == "target" then
        return general.kickReadyShowTarget == true
    end

    if unit == "focus" then
        return general.kickReadyShowFocus == true or general.enableFocusKickIcon == true
    end

    if unit == "boss" or (type(unit) == "string" and unit:match("^boss%d+$")) then
        return general.kickReadyShowBoss == true
    end

    return false
end

local function CastbarFeatureActive(general, unit, key)
    local shouldUse = _G.MSUF_ShouldUseMSUFCastbar
    if type(shouldUse) == "function" then return shouldUse(unit, general) == true end
    return general[key] ~= false
end

local function FeatureEnabled(general)
    general = general or GeneralDB()
    local target = general.kickReadyShowTarget == true and CastbarFeatureActive(general, "target", "enableTargetCastbar")
    local focus = (general.kickReadyShowFocus == true or general.enableFocusKickIcon == true)
        and CastbarFeatureActive(general, "focus", "enableFocusCastbar")
    local boss = general.kickReadyShowBoss == true and CastbarFeatureActive(general, "boss", "enableBossCastbar")
    return target or focus or boss
end

local function UnitSupportsFillStyle(general, unit)
    if unit == "target" then
        return general.kickReadyShowTarget == true
    end

    if unit == "focus" then
        return general.kickReadyShowFocus == true
    end

    if unit == "boss" or (type(unit) == "string" and unit:match("^boss%d+$")) then
        return general.kickReadyShowBoss == true
    end

    return false
end

local function IndicatorStyle(general)
    if general.kickReadyStyle == "fill" then
        return "fill"
    end

    return (general.kickReadyStyle == "border") and "border" or "box"
end

local function EnsureBox(frame)
    local box = frame.kickReadyBox
    if box then
        return box
    end

    box = CreateFrame("Frame", nil, frame)
    box.fill = box:CreateTexture(nil, "OVERLAY")
    box.fill:SetAllPoints()
    box.fill:SetTexture("Interface\\Buttons\\WHITE8x8")
    box:Hide()

    frame.kickReadyBox = box
    return box
end

local function ApplyBoxLayout(frame, general)
    general = general or GeneralDB()
    local box = EnsureBox(frame)
    local castbarHeight = frame.statusBar and frame.statusBar:GetHeight() or frame:GetHeight() or 16
    local boxSize = general.kickReadyAutoSize == false and tonumber(general.kickReadySize) or castbarHeight

    boxSize = math.max(8, math.min(boxSize or 16, 80))

    local anchor = general.kickReadyAnchor or "RIGHT"
    local offsetX = tonumber(general.kickReadyOffsetX) or 4
    local offsetY = tonumber(general.kickReadyOffsetY) or 0
    local relativePoint = anchor == "RIGHT" and "LEFT"
        or anchor == "LEFT" and "RIGHT"
        or anchor == "TOP" and "BOTTOM"
        or anchor == "BOTTOM" and "TOP"
        or anchor

    box:SetSize(boxSize, boxSize)
    box:ClearAllPoints()
    box:SetPoint(relativePoint, frame.statusBar or frame, anchor, offsetX, offsetY)
    return box
end

local function OutlineTextures(frame)
    local outline = frame and frame._msufOutline
    return outline and outline.top, outline and outline.bottom, outline and outline.left, outline and outline.right
end

local function TintOutline(frame, red, green, blue, alpha)
    local tintRounded = _G.MSUF_RoundedCastbar_TintOutline
    if type(tintRounded) == "function" and tintRounded(frame, red, green, blue, alpha) then
        frame._kickReadyBorderTinted = true
        return
    end

    local host = frame and (frame._msufOutlineHost or (frame._msufOutline and frame._msufOutline._host))
    if host and host.SetBackdropBorderColor and host.IsShown and host:IsShown() then
        host:SetBackdropBorderColor(red, green, blue, alpha)
        frame._kickReadyBorderTinted = true
        return
    end

    -- Compatibility with frames created by an older in-session implementation.
    local top, bottom, left, right = OutlineTextures(frame)
    if not top then
        return
    end

    top:SetVertexColor(red, green, blue, alpha)
    bottom:SetVertexColor(red, green, blue, alpha)
    left:SetVertexColor(red, green, blue, alpha)
    right:SetVertexColor(red, green, blue, alpha)
    frame._kickReadyBorderTinted = true
end

local function RestoreOutline(frame)
    if not (frame and frame._kickReadyBorderTinted) then
        return
    end

    frame._kickReadyBorderTinted = nil

    if type(_G.MSUF_ApplyCastbarOutline) == "function" then
        _G.MSUF_ApplyCastbarOutline(frame, true)
    end
end

--- Raw interruptibility can be nil, false, true, or a wrapped/secret value
--- depending on which castbar path produced the state. Preserve "known false"
--- instead of collapsing it with "unknown".
local function ResolveRawNotInterruptible(frame, castState)
    if castState then
        local rawValue = castState.apiNotInterruptibleRaw
        if HasKnownValue(rawValue) then
            return rawValue
        end
    end

    if frame then
        local rawValue = frame._msufApiNotInterruptibleRaw
        if HasKnownValue(rawValue) then
            return rawValue
        end

        return frame.MSUF_apiNotInterruptibleRaw
    end

    return nil
end

local function NotInterruptibleColor()
    if not state.notInterruptibleColor and _G.CreateColor then
        state.notInterruptibleColor = _G.CreateColor(0.6, 0.6, 0.6, 1)
    end

    return state.notInterruptibleColor
end

local function MarkActiveIndicatorFrame(frame)
    if not frame or activeIndicatorFrames[frame] then return end
    activeIndicatorFrames[frame] = true
    activeIndicatorFrameCount = activeIndicatorFrameCount + 1
    if UpdateCooldownEventRegistration then
        UpdateCooldownEventRegistration()
    end
end

local function MarkInactiveIndicatorFrame(frame)
    if not frame or not activeIndicatorFrames[frame] then return end
    activeIndicatorFrames[frame] = nil
    activeIndicatorFrameCount = activeIndicatorFrameCount - 1
    if activeIndicatorFrameCount < 0 then activeIndicatorFrameCount = 0 end
    if UpdateCooldownEventRegistration then
        UpdateCooldownEventRegistration()
    end
end

local function MarkActiveFillFrame(frame)
    if not frame or fillActiveFrames[frame] then return end
    fillActiveFrames[frame] = true
    fillActiveFrameCount = fillActiveFrameCount + 1
    if UpdateCooldownEventRegistration then
        UpdateCooldownEventRegistration()
    end
end

local function MarkInactiveFillFrame(frame)
    if not frame or not fillActiveFrames[frame] then return end
    fillActiveFrames[frame] = nil
    fillActiveFrameCount = fillActiveFrameCount - 1
    if fillActiveFrameCount < 0 then fillActiveFrameCount = 0 end
    if UpdateCooldownEventRegistration then
        UpdateCooldownEventRegistration()
    end
end

local function EvaluateIndicatorRGBA(isReady, rawNotInterruptible, general)
    local readySecret = plainIsSecret(isReady) == true
    local red, green, blue, alpha
    if readySecret then
        general = general or GeneralDB()
        local readyR, readyG, readyB, readyA = ColorFromDB(general, "kickReadyColor", 0, 1, 0)
        local notReadyR, notReadyG, notReadyB = ColorFromDB(general, "kickNotReadyColor", 1, 0, 0)

        if EvaluateColorValueFromBoolean then
            red = EvaluateColorValueFromBoolean(isReady, readyR, notReadyR)
            green = EvaluateColorValueFromBoolean(isReady, readyG, notReadyG)
            blue = EvaluateColorValueFromBoolean(isReady, readyB, notReadyB)
            alpha = readyA
        elseif EvaluateColorFromBoolean then
            local color = ColorForReady(isReady, general)
            if color and color.GetRGBA then
                red, green, blue, alpha = color:GetRGBA()
            end
        end

        if not HasKnownValue(red) then
            red, green, blue, alpha = notReadyR, notReadyG, notReadyB, 1
        end
    else
        red, green, blue, alpha = RGBAForReady(isReady == true, general)
    end

    local rawSecret = plainIsSecret(rawNotInterruptible) == true
    local cacheable = not readySecret and not rawSecret

    if not rawSecret and rawNotInterruptible == true then
        return 0.6, 0.6, 0.6, 1, cacheable
    end

    if (rawSecret or (rawNotInterruptible ~= nil and rawNotInterruptible ~= false))
        and EvaluateColorValueFromBoolean
    then
        return EvaluateColorValueFromBoolean(rawNotInterruptible, 0.6, red),
            EvaluateColorValueFromBoolean(rawNotInterruptible, 0.6, green),
            EvaluateColorValueFromBoolean(rawNotInterruptible, 0.6, blue),
            alpha,
            false
    end

    -- Compatibility fallback for clients exposing only the older color-object
    -- evaluator. Current Midnight clients take the allocation-free scalar path.
    if (rawSecret or (rawNotInterruptible ~= nil and rawNotInterruptible ~= false))
        and EvaluateColorFromBoolean
    then
        local color = EvaluateColorFromBoolean(rawNotInterruptible, NotInterruptibleColor(), ColorForReady(isReady, general))
        if color and color.GetRGBA then
            red, green, blue, alpha = color:GetRGBA()
            return red, green, blue, alpha, false
        end
    end

    return red, green, blue, alpha, cacheable
end

local function RawInterruptibleKey(value)
    if plainIsSecret(value) == true then
        return nil
    end
    if value == nil then
        return ""
    end
    if value == true then
        return "1"
    end
    if value == false then
        return "0"
    end
    return tostring(value)
end

local function HideIndicatorVisual(frame)
    if not frame then
        return
    end

    frame._msufKickReadyVisualKey = nil

    if frame.kickReadyBox then
        frame.kickReadyBox:Hide()
        frame.kickReadyBox._kickReadyShown = nil
    end

    RestoreOutline(frame)
end

local function HideIndicator(frame)
    MarkInactiveIndicatorFrame(frame)
    MarkInactiveFillFrame(frame)
    HideIndicatorVisual(frame)
end

--- Per-frame decorator entry. It never starts or stops casts; it only shows,
--- hides, or recolors the indicator on frames that are already active.
local function RefreshFrame(frame, castState, status, general, updateFillColor)
    if not frame then
        return
    end

    if not frame.statusBar then
        HideIndicator(frame)
        return
    end

    general = general or GeneralDB()

    local castStateTable = type(castState) == "table" and castState or nil
    local active = frame.MSUF_castActive or (castStateTable and castStateTable.active)
    local style = IndicatorStyle(general)

    if style == "fill" then
        MarkInactiveIndicatorFrame(frame)
        HideIndicatorVisual(frame)

        if not UnitSupportsFillStyle(general, frame.unit) or not active then
            MarkInactiveFillFrame(frame)
            return
        end

        if frame.isNotInterruptible == true
            or frame.MSUF_kickInterruptibleConfirmed == false
            or (castStateTable and castStateTable.isNotInterruptible == true)
        then
            MarkInactiveFillFrame(frame)
            return
        end

        MarkActiveFillFrame(frame)
        if updateFillColor == true and frame.UpdateColorForInterruptible then
            frame:UpdateColorForInterruptible()
        end
        return
    end

    MarkInactiveFillFrame(frame)
    if not ShouldShow(general, frame.unit) or not active then
        HideIndicator(frame)
        return
    end

    if frame.isNotInterruptible == true
        or frame.MSUF_kickInterruptibleConfirmed == false
        or (castStateTable and castStateTable.isNotInterruptible == true)
    then
        HideIndicator(frame)
        return
    end

    MarkActiveIndicatorFrame(frame)

    local isReady = ResolveStatus(status)
    local rawNotInterruptible = ResolveRawNotInterruptible(frame, castStateTable)
    local red, green, blue, alpha, cacheable = EvaluateIndicatorRGBA(isReady, rawNotInterruptible, general)
    local rawKey = cacheable and RawInterruptibleKey(rawNotInterruptible) or nil
    local visualKey
    if rawKey ~= nil then
        visualKey = style .. "|"
            .. (isReady == true and "1" or "0") .. "|"
            .. rawKey .. "|"
            .. tostring(red) .. "|"
            .. tostring(green) .. "|"
            .. tostring(blue) .. "|"
            .. tostring(alpha)
        if frame._msufKickReadyVisualKey == visualKey then
            return
        end
    end

    if style == "border" then
        if frame.kickReadyBox then
            frame.kickReadyBox:Hide()
            frame.kickReadyBox._kickReadyShown = nil
        end

        TintOutline(frame, red, green, blue, alpha)
        frame._msufKickReadyVisualKey = visualKey
        return
    end

    RestoreOutline(frame)

    local box = ApplyBoxLayout(frame, general)
    box.fill:SetVertexColor(red, green, blue, alpha)

    if HasKnownValue(rawNotInterruptible) and box.SetAlphaFromBoolean then
        box:SetAlphaFromBoolean(rawNotInterruptible, 0, 1)
    else
        box:SetAlpha(1)
    end

    box:Show()
    box._kickReadyShown = true
    frame._msufKickReadyVisualKey = visualKey
end

--- PERF: RefreshAll/RefreshActive/KickReady_RefreshFrame run per cooldown or
--- castbar event; a fresh status table per call is steady combat garbage. The
--- shared scratch is safe because the status never escapes these calls and the
--- three entry points never nest into each other.
local scratchStatus = {}
local function AcquireScratchStatus()
    scratchStatus.resolved = nil
    scratchStatus.ready = nil
    scratchStatus.remaining = nil
    scratchStatus.cooldown = nil
    scratchStatus.cooldownResolved = nil
    return scratchStatus
end

local function StatusCooldown(status)
    if status.cooldownResolved ~= true then
        status.cooldown = InterruptCooldown()
        status.cooldownResolved = true
    end
    return status.cooldown
end

local function ResolveFillStatus(status)
    if status.resolved or fillActiveFrameCount <= 0 then
        return
    end

    local cooldown = StatusCooldown(status)
    status.remaining = CooldownRemaining(cooldown)
    status.ready = CooldownReadyValue(cooldown, status.remaining)
    status.resolved = HasKnownValue(status.ready)
end

local function RecordDisplayedReady(status)
    if status.resolved ~= true then
        return
    end

    if HasKnownValue(status.ready) and plainIsSecret(status.ready) ~= true then
        state.cooldownDisplayReady = status.ready == true
    elseif status.remaining ~= nil then
        state.cooldownDisplayReady = status.remaining <= 0.05
    end
end

local function RefreshAll(updateFillColor)
    local status = AcquireScratchStatus()
    local general = GeneralDB()

    -- Keep this traversal direct. RefreshAll is event-driven and a capturing
    -- callback here produced one short-lived closure on every refresh.
    RefreshFrame(_G.MSUF_TargetCastbar or _G.MSUF_TargetCastBar
        or ((_G.TargetCastBar and _G.TargetCastBar._msufCastbarDriver == true) and _G.TargetCastBar),
        nil, status, general, updateFillColor)
    RefreshFrame(_G.MSUF_FocusCastbar or _G.MSUF_FocusCastBar
        or ((_G.FocusCastBar and _G.FocusCastBar._msufCastbarDriver == true) and _G.FocusCastBar),
        nil, status, general, updateFillColor)

    local bossCastbars = _G.MSUF_BossCastbars
    if type(bossCastbars) == "table" then
        for index = 1, #bossCastbars do
            RefreshFrame(bossCastbars[index], nil, status, general, updateFillColor)
        end
    end

    ResolveFillStatus(status)
    RecordDisplayedReady(status)

    return status.remaining, status.resolved == true, status.cooldown, status.cooldownResolved == true
end

local function QueueActiveRefreshFrame(frame)
    if not frame or frame._msufKickReadyQueuedRefresh == true then
        return
    end
    frame._msufKickReadyQueuedRefresh = true
    refreshActiveFrames[#refreshActiveFrames + 1] = frame
end

local function QueueActiveRefreshFrames(frames)
    for frame in pairs(frames) do
        QueueActiveRefreshFrame(frame)
    end
end

local function RefreshActive(updateFillColor, seededReady, seededRemaining, seededCooldown, seededCooldownResolved)
    local status = AcquireScratchStatus()
    if seededCooldownResolved == true then
        status.cooldown = seededCooldown
        status.cooldownResolved = true
    end
    if HasKnownValue(seededReady) then
        status.ready = seededReady
        status.remaining = seededRemaining
        status.resolved = true
    end
    local general = GeneralDB()

    QueueActiveRefreshFrames(activeIndicatorFrames)
    QueueActiveRefreshFrames(fillActiveFrames)

    for index = 1, #refreshActiveFrames do
        local frame = refreshActiveFrames[index]
        refreshActiveFrames[index] = nil
        if frame then
            frame._msufKickReadyQueuedRefresh = nil
            RefreshFrame(frame, nil, status, general, updateFillColor)
        end
    end

    ResolveFillStatus(status)
    RecordDisplayedReady(status)

    return status.remaining, status.resolved == true, status.cooldown, status.cooldownResolved == true
end

local function RefreshExternalReadyConsumers()
    local refreshFocusKick = _G.MSUF_FocusKick_RefreshReadyColor
    if type(refreshFocusKick) == "function" then
        refreshFocusKick()
    end
end

local function EnsureCooldownWakeFrame()
    if cooldownWakeFrame == false then
        return nil
    end
    if cooldownWakeFrame then
        return cooldownWakeFrame
    end

    local frame = _G.CreateFrame("Cooldown", nil, eventFrame or _G.UIParent)
    if not (frame and frame.SetCooldownFromDurationObject and frame.SetScript) then
        cooldownWakeFrame = false
        return nil
    end

    if frame.SetSize then frame:SetSize(1, 1) end
    if frame.SetAlpha then frame:SetAlpha(0) end
    if frame.SetDrawSwipe then frame:SetDrawSwipe(false) end
    if frame.SetDrawEdge then frame:SetDrawEdge(false) end
    if frame.SetDrawBling then frame:SetDrawBling(false) end
    if frame.SetHideCountdownNumbers then frame:SetHideCountdownNumbers(true) end
    frame:SetScript("OnCooldownDone", function()
        if HandleCooldownWakeDone then
            HandleCooldownWakeDone()
        end
    end)
    if frame.Show then frame:Show() end

    cooldownWakeFrame = frame
    return frame
end

ClearCooldownWake = function()
    cooldownWakeArmed = false
    cooldownTimerGeneration = cooldownTimerGeneration + 1
    cooldownTimerEndTime = nil
    if cooldownWakeFrame and cooldownWakeFrame ~= false and cooldownWakeFrame.Clear then
        cooldownWakeFrame:Clear()
    end
end

--- Arm one native C-side cooldown completion callback from the secret-safe
--- Duration object. Numeric one-shot timing is retained only as a degraded
--- fallback for clients without SetCooldownFromDurationObject; neither path
--- polls or installs a Lua OnUpdate.
local function ScheduleCooldownRefresh(remaining, remainingResolved, cooldown, cooldownResolved)
    if activeIndicatorFrameCount <= 0 and fillActiveFrameCount <= 0 then
        ClearCooldownWake()
        return false
    end

    if cooldownResolved ~= true then
        cooldown = InterruptCooldown()
        cooldownResolved = true
    end

    if cooldown then
        local wakeFrame = EnsureCooldownWakeFrame()
        if wakeFrame then
            cooldownTimerGeneration = cooldownTimerGeneration + 1
            cooldownTimerEndTime = nil
            cooldownWakeArmed = true
            wakeFrame:SetCooldownFromDurationObject(cooldown, true)
            return true
        end
    end

    if cooldownTimerEndTime then
        if remaining and remaining > 0.05 then
            local delay = math.min(remaining + 0.05, 90)
            local fireAt = Now() + delay
            local drift = fireAt - cooldownTimerEndTime
            if drift < 0 then
                drift = -drift
            end

            if drift <= 0.10 then
                return
            end
        end
        cooldownTimerGeneration = cooldownTimerGeneration + 1
    end

    cooldownTimerEndTime = nil

    if remaining == nil and not remainingResolved then
        remaining = CooldownRemaining(cooldown)
    end

    if not (remaining and remaining > 0.05 and TimerAPI and TimerAPI.After) then
        return false
    end

    cooldownTimerGeneration = cooldownTimerGeneration + 1
    local generation = cooldownTimerGeneration
    local delay = math.min(remaining + 0.05, 90)
    cooldownTimerEndTime = Now() + delay

    TimerAPI.After(delay, function()
        if generation == cooldownTimerGeneration then
            cooldownTimerEndTime = nil
            local remaining, resolved, nextCooldown, nextCooldownResolved = RefreshAll(true)
            RefreshExternalReadyConsumers()
            if resolved then
                ScheduleCooldownRefresh(remaining, true, nextCooldown, nextCooldownResolved)
            end
        end
    end)
    return true
end

HandleCooldownWakeDone = function()
    if not cooldownWakeArmed then
        return
    end
    cooldownWakeArmed = false

    if activeIndicatorFrameCount <= 0 and fillActiveFrameCount <= 0 then
        return
    end

    InvalidateCooldownSnapshot()
    local cooldown = InterruptCooldown()
    local remaining = CooldownRemaining(cooldown)
    local ready = CooldownReadyValue(cooldown, remaining)
    RefreshActive(true, ready, remaining, cooldown, true)
    RefreshExternalReadyConsumers()
end

local function KickReady_Init()
    if not FeatureEnabled() then return nil end
    ResolveInterruptSpellID()
    return state.spellID
end

local function KickReady_IsReady()
    if not FeatureEnabled() then return nil end
    local ready = InterruptStatus()
    return ready
end

local function KickReady_GetSpellID()
    if not FeatureEnabled() then return nil end
    return state.spellID or ResolveInterruptSpellID()
end

local function KickReady_GetReadyBoolForTint()
    return InterruptReadyBoolForTint()
end

local function KickReady_EvaluateColor(ready)
    return ColorForReady(ready)
end

local function KickReady_EvaluateRGBA(ready, rawNotInterruptible)
    local red, green, blue, alpha = EvaluateIndicatorRGBA(ready, rawNotInterruptible)
    return red, green, blue, alpha
end

local function KickReady_ApplyLayout(frame)
    local general = GeneralDB()
    if IndicatorStyle(general) == "fill" then
        HideIndicatorVisual(frame)
        return
    end

    if frame and ShouldShow(general, frame.unit) then
        ApplyBoxLayout(frame, general)
    end
end

local function KickReady_RefreshFrame(frame, castState)
    local status = AcquireScratchStatus()
    RefreshFrame(frame, castState, status)
    ResolveFillStatus(status)
    if status.cooldownResolved == true then
        ScheduleCooldownRefresh(status.remaining, true, status.cooldown, true)
    end
end

local function KickReady_RefreshAll()
    local enabled = FeatureEnabled()
    if UpdateLifecycleEventRegistration then UpdateLifecycleEventRegistration(enabled) end
    if not enabled then
        ClearCooldownWake()
        InvalidateCooldownSnapshot()
        local remaining, resolved = RefreshAll(false)
        if UpdateCooldownEventRegistration then UpdateCooldownEventRegistration() end
        return remaining, resolved
    end
    ResolveInterruptSpellID()
    local remaining, resolved, cooldown, cooldownResolved = RefreshAll(true)
    if resolved then
        ScheduleCooldownRefresh(remaining, true, cooldown, cooldownResolved)
    end
    if UpdateCooldownEventRegistration then
        UpdateCooldownEventRegistration()
    end
    return remaining, resolved
end

local function CooldownEventAlreadyDisplayed()
    -- GetSpellCooldownDuration returns a fresh Duration object. Reuse this
    -- event's object for both readable-remaining and secret IsZero paths.
    local cooldown = InterruptCooldown()
    local remaining = CooldownRemaining(cooldown)
    local ready = CooldownReadyValue(cooldown, remaining)
    if not HasKnownValue(ready) then
        return false, nil, nil, cooldown, true
    end

    -- Secret readiness cannot be compared or cached in Lua. It still travels
    -- directly to the C-side color selectors in RefreshActive.
    if plainIsSecret(ready) == true then
        return false, ready, remaining, cooldown, true
    end

    if state.cooldownDisplayReady ~= ready then
        -- Record the ready state we are about to display before running the
        -- refresh. RefreshActive/RefreshAll only resolve a status when some
        -- indicator actually paints; without this write the stored state goes
        -- stale whenever no cast is active.
        state.cooldownDisplayReady = ready
        return false, ready, remaining, cooldown, true
    end

    return true, ready, remaining, cooldown, true
end

ExportPublic("MSUF_KickReady_Init", KickReady_Init)
ExportPublic("MSUF_KickReady_IsReady", KickReady_IsReady)
ExportPublic("MSUF_KickReady_GetSpellID", KickReady_GetSpellID)
ExportPublic("MSUF_KickReady_GetReadyBoolForTint", KickReady_GetReadyBoolForTint)
ExportPublic("MSUF_KickReady_EvaluateColor", KickReady_EvaluateColor)
ExportPublic("MSUF_KickReady_EvaluateRGBA", KickReady_EvaluateRGBA)
ExportPublic("MSUF_KickReady_ApplyLayout", KickReady_ApplyLayout)
ExportPublic("MSUF_KickReady_RefreshFrame", KickReady_RefreshFrame)
ExportPublic("MSUF_KickReady_RefreshAll", KickReady_RefreshAll)

UpdateCooldownEventRegistration = function()
    if not eventFrame then
        return
    end

    local shouldRegister = activeIndicatorFrameCount > 0 or fillActiveFrameCount > 0
    if shouldRegister and not cooldownEventRegistered then
        eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        cooldownEventRegistered = true
    elseif not shouldRegister and cooldownEventRegistered then
        eventFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        cooldownEventRegistered = false
    end
    if not shouldRegister and ClearCooldownWake then
        ClearCooldownWake()
    end
end

eventFrame = CreateFrame("Frame", "MSUF_InterruptReady_EventFrame")
eventFrame:SetScript("OnEvent", function(_, event, spellID, baseSpellID)
    if event ~= "SPELL_UPDATE_COOLDOWN" then
        InvalidateCooldownSnapshot()
        ResolveInterruptSpellID()
    else
        if not NeedsInterruptCooldownUpdate(spellID, baseSpellID) then
            return
        end

        -- SPELL_UPDATE_COOLDOWN can repeat in one rendered frame. Filter and
        -- dedupe before requesting a fresh Duration object.
        local now = _G.GetTime and _G.GetTime()
        if now ~= nil and state.cooldownRefreshFrameStamp == now then
            return
        end
        state.cooldownRefreshFrameStamp = now
        InvalidateCooldownSnapshot()

        local alreadyDisplayed, ready, remaining, cooldown, cooldownResolved = CooldownEventAlreadyDisplayed()
        if alreadyDisplayed then
            ScheduleCooldownRefresh(remaining, true, cooldown, cooldownResolved)
            UpdateCooldownEventRegistration()
            return
        end

        local resolved, nextCooldown, nextCooldownResolved
        remaining, resolved, nextCooldown, nextCooldownResolved = RefreshActive(
            true,
            ready,
            remaining,
            cooldown,
            cooldownResolved
        )
        RefreshExternalReadyConsumers()
        if resolved then
            ScheduleCooldownRefresh(remaining, true, nextCooldown, nextCooldownResolved)
        end
        UpdateCooldownEventRegistration()
        return
    end

    local remaining, resolved, cooldown, cooldownResolved = RefreshAll(true)
    RefreshExternalReadyConsumers()
    if resolved then
        ScheduleCooldownRefresh(remaining, true, cooldown, cooldownResolved)
    end
    UpdateCooldownEventRegistration()
end)

UpdateLifecycleEventRegistration = function(enabled)
    if eventFrame.UnregisterAllEvents then
        eventFrame:UnregisterAllEvents()
    else
        eventFrame:UnregisterEvent("PLAYER_LOGIN")
        eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        eventFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    end
    cooldownEventRegistered = false
    if enabled ~= true then
        if ClearCooldownWake then ClearCooldownWake() end
        return false
    end
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    UpdateCooldownEventRegistration()
    return true
end
UpdateLifecycleEventRegistration(FeatureEnabled())
