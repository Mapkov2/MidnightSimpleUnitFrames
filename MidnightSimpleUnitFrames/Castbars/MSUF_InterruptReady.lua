--- Castbars/MSUF_InterruptReady.lua
--- Optional interrupt-readiness indicator for target, focus, and boss castbars.
---
--- This module answers two questions: "is any of my interrupts ready?" and
--- "how should the indicator look for the current cast's interruptibility?" It
--- must not decide castbar ownership or spellcast state; it decorates frames
--- that the castbar drivers already own.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic

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

-- Spell-book membership handles spec and talent changes without spec shims.
local SECONDARY_INTERRUPT_SPELLS = { PALADIN = 31935, WARRIOR = 386071 }

local SPECIALIZATION_KEYS = {
    [102] = "BALANCE",
    [255] = "SURVIVAL",
    [266] = "DEMONOLOGY",
}

local state = {}
local slots = { {}, {} }
local slotCount = 0
local spellSetGeneration = 0
local spellBookEventRegistered = false
local cooldownWakeUnsupported = false
local cooldownTimerGeneration = 0
local cooldownTimerEndTime
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
local statusSnapshotFrameStamp
local statusSnapshotGeneration
local statusSnapshotReady
local statusSnapshotRemaining
local statusSnapshotCooldown
local statusSnapshotKnown = false

local function InvalidateCooldownSnapshot()
    for index = 1, #slots do
        local slot = slots[index]
        slot.snapshot = nil
        slot.snapshotFrameStamp = nil
        slot.snapshotKnown = false
    end
    statusSnapshotFrameStamp = nil
    statusSnapshotGeneration = nil
    statusSnapshotReady = nil
    statusSnapshotRemaining = nil
    statusSnapshotCooldown = nil
    statusSnapshotKnown = false
end

local function GeneralDB()
    if type(_G.MSUF_EnsureDB) == "function" then
        _G.MSUF_EnsureDB()
    elseif type(EnsureDB) == "function" then
        EnsureDB()
    end

    return (_G.MSUF_DB and _G.MSUF_DB.general) or {}
end

local plainIsSecret = _G.issecretvalue
local plainHuge = math.huge

local function HasKnownValue(value)
    if plainIsSecret(value) == true then
        return true
    end

    return value ~= nil
end

local function PlainNumber(value)
    -- A secret has no plain reading here: the client exposes no unwrap helper
    -- (there is no ToPlain in the 12.1 API), so secrets report "unknown" and
    -- the callers fall back to their own defaults.
    if plainIsSecret(value) == true then return nil end

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

-- Modern specialization APIs work even with deprecation shims disabled.
local function ActiveSpecID()
    local specInfo = _G.C_SpecializationInfo
    local getSpecialization = (specInfo and specInfo.GetSpecialization) or _G.GetSpecialization
    local getSpecializationInfo = (specInfo and specInfo.GetSpecializationInfo) or _G.GetSpecializationInfo
    if type(getSpecialization) ~= "function" or type(getSpecializationInfo) ~= "function" then
        return nil
    end

    local specIndex = getSpecialization()
    if specIndex == nil then return nil end

    return (select(1, getSpecializationInfo(specIndex)))
end

local function SecondaryInterruptSpellID(classToken)
    local spellID = classToken and SECONDARY_INTERRUPT_SPELLS[classToken]
    local spellBook = _G.C_SpellBook
    local isKnown = spellBook and spellBook.IsSpellKnownOrInSpellBook
    if spellID and type(isKnown) == "function" and isKnown(spellID) == true then
        return spellID
    end
end

local function ClassHasSecondaryCandidate()
    local classToken = state.classToken
    if classToken == nil and UnitClass then
        local _, token = UnitClass("player")
        classToken = token
    end

    return (classToken and SECONDARY_INTERRUPT_SPELLS[classToken]) ~= nil
end

-- Resolve spells only on lifecycle/settings changes. Spell-book membership
-- admits Avenger's Shield and the talented Disrupting Shout independently.
local function ResolveInterruptSpellID()
    local previousSpellID = state.spellID
    local previousSecondarySpellID = state.secondarySpellID
    local classToken
    if UnitClass then
        local _, token = UnitClass("player")
        classToken = token
    end
    state.classToken = classToken

    local classSpells = classToken and INTERRUPT_SPELLS[classToken]
    local spellID = classSpells and classSpells.DEFAULT

    local specID = ActiveSpecID()
    if specID ~= nil then
        local specKey = SPECIALIZATION_KEYS[specID]
        if classSpells and specKey and classSpells[specKey] then
            spellID = classSpells[specKey]
        end
        state.specID = specID
    end

    local secondarySpellID = spellID and SecondaryInterruptSpellID(classToken)

    if previousSpellID and previousSpellID ~= spellID then
        state.previousSpellID = previousSpellID
    end
    if previousSecondarySpellID and previousSecondarySpellID ~= secondarySpellID then
        state.previousSecondarySpellID = previousSecondarySpellID
    end

    if previousSpellID ~= spellID or previousSecondarySpellID ~= secondarySpellID then
        spellSetGeneration = spellSetGeneration + 1
        InvalidateCooldownSnapshot()
        if ClearCooldownWake then ClearCooldownWake() end
    end

    state.spellID = spellID
    state.secondarySpellID = secondarySpellID
    slots[1].spellID, slots[2].spellID = spellID, secondarySpellID
    slotCount = secondarySpellID and 2 or (spellID and 1 or 0)
    if eventFrame and not spellBookEventRegistered and ClassHasSecondaryCandidate() then
        eventFrame:RegisterEvent("SPELLS_CHANGED")
        spellBookEventRegistered = true
    end

    return spellID
end

-- Either slot (including base/previous IDs) can change the union.
local function NeedsInterruptCooldownUpdate(spellID, baseSpellID)
    if spellID == nil then return true end

    if state.spellID == nil then ResolveInterruptSpellID() end

    for index = 1, slotCount do
        local slotSpellID = slots[index].spellID
        if spellID == slotSpellID or baseSpellID == slotSpellID then
            return true
        end
    end

    local previousSpellID = state.previousSpellID
    if previousSpellID ~= nil
        and (spellID == previousSpellID or baseSpellID == previousSpellID)
    then
        return true
    end

    local previousSecondarySpellID = state.previousSecondarySpellID
    return previousSecondarySpellID ~= nil
        and (spellID == previousSecondarySpellID or baseSpellID == previousSecondarySpellID)
end

-- Share each Duration only within this rendered frame. Relevant events must
-- invalidate before reading, including multiple resets within the same frame.
local function SlotCooldown(slot)
    local spellID = slot.spellID
    if not (spellID and SpellAPI and SpellAPI.GetSpellCooldownDuration) then
        return nil
    end
    local frameStamp = _G.GetTime and _G.GetTime()
    if frameStamp ~= nil
        and slot.snapshotKnown == true
        and slot.snapshotFrameStamp == frameStamp
    then
        return slot.snapshot
    end
    local cooldown = SpellAPI.GetSpellCooldownDuration(spellID, true)
    if frameStamp ~= nil then
        slot.snapshot = cooldown
        slot.snapshotFrameStamp = frameStamp
        slot.snapshotKnown = true
    end
    return cooldown
end

local function InterruptCooldown()
    if state.spellID == nil then ResolveInterruptSpellID() end
    if slotCount < 1 then return nil end

    return SlotCooldown(slots[1])
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

-- A plain ready slot settles the union. If both booleans are restricted,
-- return one here and compose both at the native color sink below.
local function CombinedStatus(seedCooldown, seedResolved)
    if state.spellID == nil then ResolveInterruptSpellID() end

    local plainReady = false
    local secretReady
    local hasSecret = false
    local soonestRemaining
    local primaryCooldown

    for index = 1, slotCount do
        local cooldown
        if index == 1 and seedResolved == true then
            cooldown = seedCooldown
        else
            cooldown = SlotCooldown(slots[index])
        end

        if index == 1 then
            primaryCooldown = cooldown
        end

        local remaining = CooldownRemaining(cooldown)
        local ready = CooldownReadyValue(cooldown, remaining)

        if plainIsSecret(ready) == true then
            if not hasSecret then
                hasSecret = true
                secretReady = ready
            end
        elseif ready == true then
            plainReady = true
        end

        if remaining ~= nil and (soonestRemaining == nil or remaining < soonestRemaining) then
            soonestRemaining = remaining
        end
    end

    if plainReady == true then
        return true, soonestRemaining, primaryCooldown
    end

    if hasSecret then
        return secretReady, soonestRemaining, primaryCooldown
    end

    return false, soonestRemaining, primaryCooldown
end

local function InterruptStatus(cooldown, cooldownResolved)
    local useSnapshot = cooldownResolved ~= true
    local frameStamp = useSnapshot and _G.GetTime and _G.GetTime() or nil
    if frameStamp ~= nil
        and statusSnapshotKnown == true
        and statusSnapshotFrameStamp == frameStamp
        and statusSnapshotGeneration == spellSetGeneration
    then
        return statusSnapshotReady, statusSnapshotRemaining, statusSnapshotCooldown
    end

    local ready, remaining, primaryCooldown = CombinedStatus(cooldown, cooldownResolved)

    if not HasKnownValue(ready) then
        ready = false
    end
    if frameStamp ~= nil and plainIsSecret(ready) ~= true then
        statusSnapshotFrameStamp = frameStamp
        statusSnapshotGeneration = spellSetGeneration
        statusSnapshotReady = ready
        statusSnapshotRemaining = remaining
        statusSnapshotCooldown = primaryCooldown
        statusSnapshotKnown = true
    end

    return ready, remaining, primaryCooldown
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

local function InterruptReadyBoolForTint()
    local ready = InterruptStatus()
    return ready
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

local function SecondaryReadyForColor()
    if slotCount < 2 then return false end
    local cooldown = SlotCooldown(slots[2])
    return CooldownReadyValue(cooldown, CooldownRemaining(cooldown))
end

local function SelectReadyColor(isReady, readyColor, notReadyColor)
    if plainIsSecret(isReady) ~= true then
        return isReady == true and readyColor or notReadyColor
    end
    if not EvaluateColorFromBoolean then return notReadyColor end
    local secondary = SecondaryReadyForColor()
    if plainIsSecret(secondary) == true then
        -- Nested native selection implements OR without branching on either
        -- restricted boolean (live CurveUtilDocumentation.lua).
        notReadyColor = EvaluateColorFromBoolean(secondary, readyColor, notReadyColor)
    end
    return EvaluateColorFromBoolean(isReady, readyColor, notReadyColor)
end
ExportPublic("MSUF_KickReady_SelectColor", SelectReadyColor)

local function ColorForReady(isReady, general)
    local readyColor, notReadyColor = ReadyColors(general)
    return SelectReadyColor(isReady, readyColor, notReadyColor)
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

    box = CreateFrame("Frame", nil, frame._msufHealthVisualRoot or frame)
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
            local secondary = SecondaryReadyForColor()
            if plainIsSecret(secondary) == true then
                notReadyR = EvaluateColorValueFromBoolean(secondary, readyR, notReadyR)
                notReadyG = EvaluateColorValueFromBoolean(secondary, readyG, notReadyG)
                notReadyB = EvaluateColorValueFromBoolean(secondary, readyB, notReadyB)
            end
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
        frame._msufKickReadyVisualKey = frame._kickReadyBorderTinted and visualKey or nil
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
    status.ready, status.remaining = InterruptStatus(cooldown, true)
    status.resolved = HasKnownValue(status.ready)
end

local function RecordDisplayedReady(status)
    if status.resolved ~= true then
        return
    end

    if HasKnownValue(status.ready) and plainIsSecret(status.ready) ~= true then
        state.cooldownDisplayReady = status.ready == true
    else
        -- A readable cooldown from one slot says nothing about the other
        -- slot's secret readiness or the color selected by the native sink.
        state.cooldownDisplayReady = nil
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

-- One native completion callback per slot; no polling or Lua OnUpdate.
local function EnsureCooldownWakeFrame(slot)
    if cooldownWakeUnsupported then
        return nil
    end
    if slot.wakeFrame then
        return slot.wakeFrame
    end

    local frame = _G.CreateFrame("Cooldown", nil, eventFrame or _G.UIParent)
    if not (frame and frame.SetCooldownFromDurationObject and frame.SetScript) then
        cooldownWakeUnsupported = true
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
            HandleCooldownWakeDone(slot)
        end
    end)
    if frame.Show then frame:Show() end

    slot.wakeFrame = frame
    return frame
end

ClearCooldownWake = function()
    cooldownTimerGeneration = cooldownTimerGeneration + 1
    cooldownTimerEndTime = nil
    for index = 1, #slots do
        local slot = slots[index]
        slot.wakeArmed = false
        slot.wakeEndTime = nil
        local wakeFrame = slot.wakeFrame
        if wakeFrame and wakeFrame.Clear then
            wakeFrame:Clear()
        end
    end
end

local function ScheduleCooldownRefresh(remaining, remainingResolved, cooldown, cooldownResolved)
    if activeIndicatorFrameCount <= 0 and fillActiveFrameCount <= 0 then
        ClearCooldownWake()
        return false
    end

    if cooldownResolved ~= true then
        cooldown = InterruptCooldown()
        cooldownResolved = true
    end
    local armed = false
    for index = 1, slotCount do
        local slot = slots[index]
        local slotCooldown = (index == 1) and cooldown or SlotCooldown(slot)
        if slotCooldown then
            local slotRemaining = CooldownRemaining(slotCooldown)
            -- Keep wakes through the final 50 ms: visual readiness has a
            -- tolerance, but native completion fires only at actual zero.
            local slotRunning = slotRemaining == nil or slotRemaining > 0
            local wakeFrame = slotRunning and EnsureCooldownWakeFrame(slot) or nil
            if wakeFrame then
                if not armed then
                    cooldownTimerGeneration = cooldownTimerGeneration + 1
                    cooldownTimerEndTime = nil
                    armed = true
                end
                -- GetEndTime's default is real time, including mod-rate.
                -- Compare exact public deadlines, never object/event identity
                -- or a tolerance that could swallow a reset. Secrets rebind.
                local endTime
                if slotRemaining ~= nil and slotCooldown.GetEndTime then
                    endTime = PlainNumber(slotCooldown:GetEndTime())
                end
                if not slot.wakeArmed or endTime == nil or slot.wakeEndTime ~= endTime then
                    slot.wakeEndTime = endTime
                    slot.wakeArmed = true
                    wakeFrame:SetCooldownFromDurationObject(slotCooldown, true)
                end
            elseif not slotRunning then
                slot.wakeArmed = false
                local existingFrame = slot.wakeFrame
                if existingFrame and existingFrame.Clear then
                    existingFrame:Clear()
                end
            end
        end
    end

    if armed then
        return true
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

HandleCooldownWakeDone = function(slot)
    if not (slot and slot.wakeArmed) then
        return
    end
    slot.wakeArmed = false

    if activeIndicatorFrameCount <= 0 and fillActiveFrameCount <= 0 then
        return
    end

    InvalidateCooldownSnapshot()
    local ready, remaining, cooldown = CombinedStatus()
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
    -- One frame's paint cannot certify the readiness displayed by all frames.
    state.cooldownDisplayReady = nil
    if status.cooldownResolved == true then
        ScheduleCooldownRefresh(status.remaining, true, status.cooldown, true)
    end
end

-- The outline owner only needs a new paint after replacing its edges. Keep
-- this independent of shared scratch status and cooldown wake scheduling.
local function KickReady_RefreshOutline(frame)
    if not (frame and frame._kickReadyBorderTinted) then return end
    frame._msufKickReadyVisualKey = nil
    RefreshFrame(frame)
    state.cooldownDisplayReady = nil
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
    local ready, remaining, cooldown = InterruptStatus()
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
ExportPublic("MSUF_KickReady_RefreshOutline", KickReady_RefreshOutline)
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
        local previousGeneration = spellSetGeneration
        InvalidateCooldownSnapshot()
        ResolveInterruptSpellID()
        if previousGeneration == spellSetGeneration and event == "SPELLS_CHANGED" then
            return
        end
    else
        if not NeedsInterruptCooldownUpdate(spellID, baseSpellID) then
            return
        end

        -- Starts and resets (including the SAME spell) can share a frame.
        -- Invalidate first; only the resulting display state may be deduped.
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
        eventFrame:UnregisterEvent("SPELLS_CHANGED")
        eventFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    end
    cooldownEventRegistered = false
    spellBookEventRegistered = false
    if enabled ~= true then
        if ClearCooldownWake then ClearCooldownWake() end
        return false
    end
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    if ClassHasSecondaryCandidate() then
        eventFrame:RegisterEvent("SPELLS_CHANGED")
        spellBookEventRegistered = true
    end
    UpdateCooldownEventRegistration()
    return true
end
UpdateLifecycleEventRegistration(FeatureEnabled())
