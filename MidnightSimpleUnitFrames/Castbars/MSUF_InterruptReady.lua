local SpellAPI = _G.C_Spell
local TimerAPI = _G.C_Timer

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
local cooldownTimer
local cooldownTimerGeneration = 0
local cooldownTimerEndTime

local function GeneralDB()
    if type(_G.MSUF_EnsureDB) == "function" then
        _G.MSUF_EnsureDB()
    elseif type(EnsureDB) == "function" then
        EnsureDB()
    end

    return (_G.MSUF_DB and _G.MSUF_DB.general) or {}
end

local function PlainNumber(value)
    if value == nil then
        return nil
    end

    local toPlain = _G.ToPlain
    if type(toPlain) == "function" then
        local plain = tonumber(tostring(toPlain(value)))
        if plain ~= nil then
            return plain
        end
    end

    local valueType = type(value)
    if valueType == "number" or valueType == "string" then
        return tonumber(tostring(value))
    end

    return nil
end

local function Now()
    return (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
end

local function ResolveInterruptSpellID()
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

    state.spellID = spellID
    return spellID
end

local function InterruptCooldown()
    local spellID = state.spellID or ResolveInterruptSpellID()
    if not (spellID and SpellAPI and SpellAPI.GetSpellCooldownDuration) then
        return nil
    end

    return SpellAPI.GetSpellCooldownDuration(spellID)
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

local function InterruptStatus()
    local remaining = CooldownRemaining(InterruptCooldown())
    if remaining == nil then
        return false, nil
    end

    return remaining <= 0.05, remaining
end

local function ResolveStatus(status)
    if type(status) == "table" then
        if not status.resolved then
            status.ready, status.remaining = InterruptStatus()
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

local function InterruptRemaining()
    return CooldownRemaining(InterruptCooldown())
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
    return isReady and readyColor or notReadyColor
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

local function IndicatorStyle(general)
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

local function HasKnownValue(value)
    local isSecretValue = _G.issecretvalue
    if type(isSecretValue) == "function" and isSecretValue(value) == true then
        return true
    end

    return value ~= nil
end

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

local function EvaluateIndicatorRGBA(isReady, rawNotInterruptible, general)
    local color = ColorForReady(isReady, general)

    if HasKnownValue(rawNotInterruptible)
        and _G.CreateColor
        and _G.C_CurveUtil
        and _G.C_CurveUtil.EvaluateColorFromBoolean
    then
        color = _G.C_CurveUtil.EvaluateColorFromBoolean(rawNotInterruptible, NotInterruptibleColor(), color)
    end

    if color and color.GetRGBA then
        return color:GetRGBA()
    end

    return isReady and 0 or 1, isReady and 1 or 0, 0, 1
end

local function HideIndicator(frame)
    if not frame then
        return
    end

    if frame.kickReadyBox then
        frame.kickReadyBox:Hide()
        frame.kickReadyBox._kickReadyShown = nil
    end

    RestoreOutline(frame)
end

local function RefreshFrame(frame, castState, status, general)
    if not (frame and frame.statusBar) then
        return
    end

    general = general or GeneralDB()
    if not ShouldShow(general, frame.unit) or not (frame.MSUF_castActive or (castState and castState.active)) then
        HideIndicator(frame)
        return
    end

    if frame.isNotInterruptible == true
        or frame.MSUF_kickInterruptibleConfirmed == false
        or (castState and castState.isNotInterruptible == true)
    then
        HideIndicator(frame)
        return
    end

    local isReady = ResolveStatus(status)
    local rawNotInterruptible = ResolveRawNotInterruptible(frame, castState)
    local red, green, blue, alpha = EvaluateIndicatorRGBA(isReady, rawNotInterruptible, general)

    if IndicatorStyle(general) == "border" then
        if frame.kickReadyBox then
            frame.kickReadyBox:Hide()
            frame.kickReadyBox._kickReadyShown = nil
        end

        TintOutline(frame, red, green, blue, alpha)
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
end

local function ForEachCastbar(callback)
    callback(_G.MSUF_TargetCastbar or _G.TargetCastBar)
    callback(_G.MSUF_FocusCastbar or _G.FocusCastBar)

    local bossCastbars = _G.MSUF_BossCastbars
    if type(bossCastbars) == "table" then
        for index = 1, #bossCastbars do
            callback(bossCastbars[index])
        end
    end
end

local function RefreshAll()
    local status = {}
    local general = GeneralDB()

    ForEachCastbar(function(frame)
        RefreshFrame(frame, nil, status, general)
    end)

    return status.remaining, status.resolved == true
end

local function ScheduleCooldownRefresh(remaining, remainingResolved)
    if cooldownTimer and cooldownTimer.Cancel then
        if remaining and remaining > 0.05 and cooldownTimerEndTime and TimerAPI and TimerAPI.NewTimer then
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

        cooldownTimer:Cancel()
    end

    cooldownTimer = nil
    cooldownTimerEndTime = nil

    if remaining == nil and not remainingResolved then
        remaining = InterruptRemaining()
    end

    if not (remaining and remaining > 0.05 and TimerAPI and TimerAPI.NewTimer) then
        return
    end

    cooldownTimerGeneration = cooldownTimerGeneration + 1
    local generation = cooldownTimerGeneration
    local delay = math.min(remaining + 0.05, 90)
    cooldownTimerEndTime = Now() + delay

    cooldownTimer = TimerAPI.NewTimer(delay, function()
        if generation == cooldownTimerGeneration then
            cooldownTimer = nil
            cooldownTimerEndTime = nil
            local remaining, resolved = RefreshAll()
            if resolved then
                ScheduleCooldownRefresh(remaining, true)
            end
        end
    end)
end

function _G.MSUF_KickReady_Init()
    ResolveInterruptSpellID()
    return state.spellID
end

function _G.MSUF_KickReady_IsReady()
    local ready, remaining = InterruptStatus()
    ScheduleCooldownRefresh(remaining, true)
    return ready
end

function _G.MSUF_KickReady_EvaluateColor(ready)
    return ColorForReady(ready)
end

function _G.MSUF_KickReady_ApplyLayout(frame)
    local general = GeneralDB()
    if frame and ShouldShow(general, frame.unit) then
        ApplyBoxLayout(frame, general)
    end
end

function _G.MSUF_KickReady_RefreshFrame(frame, castState)
    local status = {}
    RefreshFrame(frame, castState, status)
    if status.resolved then
        ScheduleCooldownRefresh(status.remaining, true)
    end
end

local eventFrame = CreateFrame("Frame", "MSUF_InterruptReady_EventFrame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:SetScript("OnEvent", function()
    ResolveInterruptSpellID()
    local remaining, resolved = RefreshAll()
    if resolved then
        ScheduleCooldownRefresh(remaining, true)
    end
end)
