local _, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

-- Gameplay feature runtime.
-- Coordinates optional gameplay overlays such as combat timer, crosshair, totem/statue
-- helpers. Config writes are scheduled through the gameplay apply queue so UI updates coalesce
-- instead of rebuilding several feature frames per setting edit.
local CreateFrame   = CreateFrame
local UIParent      = UIParent
local C_Spell       = C_Spell
local C_SpellBook   = C_SpellBook
local C_CooldownViewer = C_CooldownViewer
local C_NamePlate = C_NamePlate
local C_StringUtil = C_StringUtil
local hooksecurefunc = hooksecurefunc
local UnitExists    = UnitExists
local UnitCanAttack = UnitCanAttack
local GetTime             = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local string_format       = string.format
local GetCVar    = GetCVar
local GetCVarBool = GetCVarBool
local math_min     = math.min
local math_max     = math.max
local math_floor   = math.floor
local IsAltKeyDown  = IsAltKeyDown
local tonumber            = tonumber

local GameplayHelpers = MSUF.Gameplay or {}
local GetPlayerSpecID = GameplayHelpers.GetPlayerSpecID
local Clamp, RoundInt = GameplayHelpers.Clamp or _G._MSUF_Clamp, GameplayHelpers.RoundInt or _G._MSUF_RoundInt
local CheckpointHistory, BeginHistory, CommitHistory = GameplayHelpers.CheckpointHistory, GameplayHelpers.BeginHistory, GameplayHelpers.CommitHistory
local SelectNudgeFrame, SetupArrowNudge = GameplayHelpers.SelectNudgeFrame, GameplayHelpers.SetupArrowNudge
local RefreshKeyboardNudge, ReleaseKeyboardNudge = GameplayHelpers.RefreshKeyboardNudge, GameplayHelpers.ReleaseKeyboardNudge

local ScheduleOnce = _G.MSUF_ScheduleOnce
local EventBus_Register = _G.MSUF_EventBus_Register
local EventBus_Unregister = _G.MSUF_EventBus_Unregister
local RegisterModule = MSUF.MSUF_RegisterModule
local ApplyGameplayNow
local SyncGameplaySpecEvents
local ApplyApexItDevAura
local ApplyApexRangeCounter
local ApplyApexRangeCounterStyle

local function BusRegister(...)
    if type(EventBus_Register) == "function" then EventBus_Register(...) end
end

local function BusUnregister(...)
    if type(EventBus_Unregister) == "function" then EventBus_Unregister(...) end
end

local function RefreshGameplayKeyboardNudge(frame)
    if not frame then return end
    if type(RefreshKeyboardNudge) == "function" then
        RefreshKeyboardNudge(frame)
    elseif frame._msufGameplayUpdateKeyboardNudge then
        frame:_msufGameplayUpdateKeyboardNudge()
    end
end

local function ReleaseGameplayKeyboardNudge(frame)
    if not frame then return end
    if type(ReleaseKeyboardNudge) == "function" then
        ReleaseKeyboardNudge(frame)
    elseif frame._msufGameplayReleaseKeyboardNudge then
        frame:_msufGameplayReleaseKeyboardNudge()
    end
end

do
    local _applyPending = false

    local function _DoGameplayApply()
        -- Release the coalescing guard before applying. If any feature throws, a later
        -- settings change must still be able to schedule a fresh apply.
        _applyPending = false
        if ApplyGameplayNow then ApplyGameplayNow() end
    end

    function MSUF.MSUF_RequestGameplayApply()
        -- Multiple Menu2 controls can change in one frame. Coalesce them into a single apply
        -- so feature frames and event registrations are rebuilt once.
        if _applyPending then return end
        _applyPending = true

        if type(ScheduleOnce) == "function" then
            ScheduleOnce("MSUF_GAMEPLAY_APPLY", _DoGameplayApply)
        else
            C_Timer.After(0, _DoGameplayApply)
        end
    end
end

local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local GetCameraZoom = GetCameraZoom

local GameplayDefaults = MSUF.MSUF_EnsureGameplayDefaults
local GetGameplayDB = MSUF.MSUF_GetGameplayDBFast
local GetGameplayFont = MSUF.MSUF_GetGameplayFontSettings
local NormalizeRGB = MSUF.MSUF_NormalizeRGB
local MSUF_GetCombatStateColors = MSUF.MSUF_GetCombatStateColors

local ApplyCombatStateDynamicColor

local function GlobalFontTextAlpha()
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    local a = tonumber(g and g.fontTextAlpha) or 1
    if a < 0.7 then return 0.7 end
    if a > 1 then return 1 end
    return a
end

local function GlobalFontShadowMetrics()
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    return _G.MSUF_ResolveFontShadowMetrics(g and g.fontShadowOpacity,
        g and g.fontShadowDistance, g and g.fontShadowStrength)
end

local function SetTextShadow(fs, enabled)
    if not fs then return end
    if enabled then
        local a, x, y = GlobalFontShadowMetrics()
        fs:SetShadowOffset(x, y)
        fs:SetShadowColor(0, 0, 0, a)
    else
        fs:SetShadowOffset(0, 0)
    end
end

local function SetAltDragMouse(frame, enabled, locked, clickThrough)
    if not frame then return end
    -- Click-through helpers should only catch the mouse while explicitly draggable. Alt-gated
    -- mouse enablement keeps gameplay overlays from eating normal clicks.
    if frame._msufDragging then
        frame:EnableMouse(true)
    elseif not enabled or locked then
        frame:EnableMouse(false)
    elseif clickThrough ~= false then
        frame:EnableMouse((IsAltKeyDown and IsAltKeyDown()) and true or false)
    else
        frame:EnableMouse(true)
    end
end

local function EnsureAltDragWatcher(key, frame, enabledKey, lockKey, clickThroughKey, enabled)
    local f = MSUF[key]
    if not f then
        f = CreateFrame("Frame")
        MSUF[key] = f
        f:SetScript("OnEvent", function()
            local gd = GetGameplayDB()
            SetAltDragMouse(frame, gd and gd[enabledKey], gd and gd[lockKey], gd and gd[clickThroughKey])
        end)
    end
    f:UnregisterAllEvents()
    if enabled == true then f:RegisterEvent("MODIFIER_STATE_CHANGED") end
end

local function SyncGameplayPanel(method)
    local panel = _G.MSUF_GameplayPanel
    local fn = panel and panel[method]
    if fn then fn(panel) end
    -- Menu2 replaced the legacy gameplay panel, so mover drags/nudges must repaint the visible
    -- X/Y offset sliders through the Menu2 sync path (same one Edit Mode position drags use).
    local m2 = _G.MSUF2
    if m2 and type(m2.RefreshVisibleSliders) == "function" then m2.RefreshVisibleSliders("GAMEPLAY_MOVER_POSITION_CHANGED") end
end

local function StoreCenteredOffset(frame, db, xKey, yKey, anchor, roundValues)
    local x, y = frame:GetCenter()
    if not (x and y) then return end

    -- GetCenter reports each region in its own effective-scale space. Anchoring to a scaled
    -- unit frame therefore needs both centers converted through screen pixels into the moving
    -- frame's space (the space SetPoint offsets are applied in), or the stored offsets drift
    -- and the next re-anchor jumps the frame.
    local frameScale = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
    if not frameScale or frameScale <= 0 then frameScale = 1 end

    local ax, ay = UIParent:GetCenter()
    local anchorScale = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or frameScale
    if anchor and anchor.GetCenter then
        local tx, ty = anchor:GetCenter()
        if tx and ty then
            ax, ay = tx, ty
            anchorScale = (anchor.GetEffectiveScale and anchor:GetEffectiveScale()) or anchorScale
        end
    end
    if not (ax and ay) then return end
    if not anchorScale or anchorScale <= 0 then anchorScale = frameScale end

    local dx = ((x * frameScale) - (ax * anchorScale)) / frameScale
    local dy = ((y * frameScale) - (ay * anchorScale)) / frameScale
    if roundValues ~= false then
        dx, dy = RoundInt(dx), RoundInt(dy)
    end
    db[xKey], db[yKey] = dx, dy
end

local function BeginGameplayDrag(frame, label, source)
    SelectNudgeFrame(frame, true)
    BeginHistory(frame, label, source)
    frame._msufDragging = true
    frame:StartMoving()
end

local function CanAltDrag(g, lockKey, clickThroughKey)
    if g[lockKey] then return false end
    return g[clickThroughKey] == false or not IsAltKeyDown or IsAltKeyDown()
end

local function CreateMovableGameplayFrame(name, width, height)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(width, height)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    return frame
end

local combatFrame
local timerText
local stateFrame
local stateText
local CombatStateOnEvent
local apexItFrame
local apexItText
local apexItStackText
local apexItLabelSensor
local apexItStackSensor
local shadowTechHighlightSensorsByFrame = {}
local apexItEventFrame
local apexItPreviewActive = false
local apexItConsumed = false
local apexDeathstalkerKnown = false
local apexRangeCounterFrame
local apexRangeCounterHeader
local apexRangeCounterText
local apexRangeCounterEventFrame
local apexRangeCounterTimer
local apexRangeCounterTimerGeneration = 0
local apexRangeCounterScanPending = false
local apexRangeCounterPreviewActive = false
local apexRangeCounterUnits = {}
local apexRangeState = {
    snapshotValid = false,
    inRangeEnemyCount = 0,
    sensorActionApplied = false,
    secretTechniqueReadyByFrame = {},
}
local crosshairFrame
local crosshairEventFrame
local crosshairZoomHooksInstalled = false

local RequestCrosshairRangeRefresh
local function ResolveCrosshairRangeSpellID(g)
    if not g then return 0 end

    -- Resolution is ordered from most explicit to broad fallback so per-spec/per-class helper
    -- settings do not override a user-selected spell ID.
    local spellID = tonumber(g.crosshairRangeSpellID) or 0
    if spellID > 0 then return spellID end

    spellID = tonumber(g.meleeRangeSpellID) or 0
    if spellID > 0 then return spellID end

    if g.meleeSpellPerSpec and type(g.nameplateMeleeSpellIDBySpec) == "table" then
        local specID = GetPlayerSpecID()
        if specID then
            spellID = tonumber(g.nameplateMeleeSpellIDBySpec[specID]) or 0
            if spellID > 0 then return spellID end
        end
    end

    if g.meleeSpellPerClass and type(g.nameplateMeleeSpellIDByClass) == "table" and UnitClass then
        local _, class = UnitClass("player")
        if class then
            spellID = tonumber(g.nameplateMeleeSpellIDByClass[class]) or 0
            if spellID > 0 then return spellID end
        end
    end

    spellID = tonumber(g.nameplateMeleeSpellID) or 0
    if spellID > 0 then return spellID end

    return (MSUF_DB and type(MSUF_DB.general) == "table" and tonumber(MSUF_DB.general.meleeRangeSpellID)) or 0
end

local function SyncCrosshairRangeCache(g)
    if not crosshairFrame then return end

    crosshairFrame._msufCrosshairEnabled = (g and g.enableCombatCrosshair) and true or false

    local spellID = ResolveCrosshairRangeSpellID(g)
    crosshairFrame._msufRangeSpellID = spellID

    crosshairFrame._msufUseRangeColor = (g and g.enableCombatCrosshairMeleeRangeColor) and (spellID > 0) or false

    crosshairFrame._msufInRangeR, crosshairFrame._msufInRangeG, crosshairFrame._msufInRangeB =
        NormalizeRGB(g and g.crosshairInRangeColor, 0, 1, 0)
    crosshairFrame._msufOutRangeR, crosshairFrame._msufOutRangeG, crosshairFrame._msufOutRangeB =
        NormalizeRGB(g and g.crosshairOutRangeColor, 1, 0, 0)
end

local combatStartTime = nil
local lastTimerText = ""
local lastTimerMinute
local lastTimerSecond
local combatTimerLoop

local function SetCombatTimerText(text)
    if text ~= lastTimerText then
        lastTimerText = text
        lastTimerMinute = nil
        lastTimerSecond = nil
        timerText:SetText(text)
    end
end

local function SetCombatTimerValue(minutes, seconds)
    if lastTimerText == false and minutes == lastTimerMinute and seconds == lastTimerSecond then
        return
    end
    lastTimerText = false
    lastTimerMinute = minutes
    lastTimerSecond = seconds
    timerText:SetFormattedText("%d:%02d", minutes, seconds)
end

local function SetCombatTimerShown(shown)
    if combatFrame then combatFrame:SetShown(shown) end
end

local function TickCombatTimer()
    if not timerText then return end

    local gNow = GetGameplayDB()
    if not gNow or not gNow.enableCombatTimer then
        SetCombatTimerText("")
        SetCombatTimerShown(false)
        combatStartTime = nil
        return
    end

    local inCombat = (UnitAffectingCombat and UnitAffectingCombat("player")) or (_G.MSUF_InCombat == true)

    if not inCombat then
        SetCombatTimerShown(not gNow.lockCombatTimer)
        SetCombatTimerText(gNow.lockCombatTimer and "" or "0:00")
        combatStartTime = nil
        return
    end

    SetCombatTimerShown(true)
    local now = GetTime()
    combatStartTime = combatStartTime or now
    local elapsedCombat = math_max(now - combatStartTime, 0)
    SetCombatTimerValue(math.floor(elapsedCombat / 60), math.floor(elapsedCombat % 60))
end

local function _StartCombatTimerTick()
    if combatTimerLoop then return end

    -- Retail provides one cancellable ticker for this exact repeating job.
    -- It avoids allocating a fresh After timer every second and lets combat
    -- end cancel the pending callback immediately.
    if C_Timer.NewTicker then
        combatTimerLoop = C_Timer.NewTicker(1.0, TickCombatTimer)
        MSUF._MSUF_CombatTimerLoopActive = combatTimerLoop
        return
    end

    -- Compatibility fallback for clients/harnesses without NewTicker.
    local loop = {}
    loop.step = function()
        if combatTimerLoop ~= loop or MSUF._MSUF_CombatTimerLoopActive ~= loop then return end
        TickCombatTimer()
        if combatTimerLoop == loop and MSUF._MSUF_CombatTimerLoopActive == loop then
            C_Timer.After(1.0, loop.step)
        end
    end
    combatTimerLoop = loop
    MSUF._MSUF_CombatTimerLoopActive = loop
    C_Timer.After(1.0, loop.step)
end

local function _StopCombatTimerTick()
    local loop = combatTimerLoop
    combatTimerLoop = nil
    MSUF._MSUF_CombatTimerLoopActive = nil
    if loop and loop.Cancel then
        loop:Cancel()
    end
end

local function SetCombatStateClickThrough(active)
    if not stateFrame then return end

    if active then
        stateFrame._msufClickThroughActive = true
        stateFrame:EnableMouse(false)
        stateFrame:Show()
        return
    end

    stateFrame._msufClickThroughActive = nil
    local g = GetGameplayDB()
    if g and not g.lockCombatState and stateText and stateText:IsShown() then
        stateFrame:EnableMouse(true)
        stateFrame:Show()
    else
        stateFrame:EnableMouse(false)
        if not stateText or not stateText:IsShown() then
            stateFrame:Hide()
        end
    end
end

local function TextOrDefault(text, fallback)
    if type(text) ~= "string" or text == "" then return fallback end
    return text
end

local function ShowCombatStateText(state, text, r, g, b, clickThrough)
    stateText._msufLastState = state
    stateText:SetTextColor(r, g, b, GlobalFontTextAlpha())
    stateText:SetText(text)
    if clickThrough then
        SetCombatStateClickThrough(true)
    else
        stateFrame:Show()
        stateFrame:EnableMouse(true)
    end
    stateText:Show()
end

local function ClearCombatStateText()
    if stateText then
        stateText:SetText("")
        stateText:Hide()
    end
end

local combatStateClearTimer

local function CombatStateClearTimerFired()
    combatStateClearTimer = nil
    local g = GetGameplayDB()
    if stateText and g and g.enableCombatStateText then
        ClearCombatStateText()
        SetCombatStateClickThrough(false)
        if not g.lockCombatState then
            -- Unlocked text stays visible as the movable handle; without this the handle
            -- vanishes after every combat transition until the next menu apply.
            local er, eg, eb = MSUF_GetCombatStateColors(g)
            ShowCombatStateText("enter", TextOrDefault(g.combatStateEnterText, "+Combat"), er, eg, eb, false)
        end
    end
end

local function CancelCombatStateClear()
    local timer = combatStateClearTimer
    combatStateClearTimer = nil
    if timer and timer.Cancel then timer:Cancel() end
end

local function ScheduleCombatStateClear(duration)
    CancelCombatStateClear()
    if C_Timer.NewTimer then
        combatStateClearTimer = C_Timer.NewTimer(duration, CombatStateClearTimerFired)
    else
        C_Timer.After(duration, CombatStateClearTimerFired)
    end
end

local GAMEPLAY_FALLBACK_FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function GameplayFontApplied(fs, path, size, flags)
    if type(fs.GetFont) ~= "function" then return true end
    local actual, actualSize, actualFlags = fs:GetFont()
    if not actual then return true end
    if actualSize and actualSize ~= size then return false end
    if (actualFlags or "") ~= (flags or "") then return false end
    if actual == path then return true end
    local matches = _G.MSUF_FontPathMatches or _G.MSUF_FontPathEquals
    if type(matches) == "function" then return matches(path, actual) == true end
    return tostring(actual or ""):gsub("/", "\\"):lower() == tostring(path or ""):gsub("/", "\\"):lower()
end

local function ApplyGameplayFont(fs, path, size, flags)
    if not (fs and fs.SetFont) then return false end
    path = path or GAMEPLAY_FALLBACK_FONT
    size = tonumber(size) or 12
    if size <= 0 then size = 12 end
    if size < 6 then size = 6 elseif size > 128 then size = 128 end
    flags = flags or "OUTLINE"
    local ok = pcall(fs.SetFont, fs, path, size, flags)
    if ok and GameplayFontApplied(fs, path, size, flags) then
        return true
    end
    if path ~= GAMEPLAY_FALLBACK_FONT then
        ok = pcall(fs.SetFont, fs, GAMEPLAY_FALLBACK_FONT, size, flags)
        return ok == true
    end
    return false
end

local function ApplyApexTextStyle(fontString, isStackText)
    if not fontString then return end
    local gdb = GetGameplayDB()
    local path, flags, _, _, _, _, useShadow = GetGameplayFont("state")
    local apexFontSize = tonumber(gdb and gdb.apexItFontSize) or 32
    local fontSize = isStackText
        and math_min(24, math_max(12, apexFontSize * 0.65))
        or apexFontSize
    ApplyGameplayFont(fontString, path, fontSize, flags or "OUTLINE")
    if isStackText then
        fontString:SetTextColor(1, 1, 1, GlobalFontTextAlpha())
    else
        fontString:SetTextColor(1, 0.82, 0.08, GlobalFontTextAlpha())
    end
    SetTextShadow(fontString, useShadow ~= false)
end

local function ApplyFontToCounter()
    if not timerText and not stateText and not apexItText and not apexItStackText
        and not apexRangeCounterHeader and not apexRangeCounterText then return end
    if timerText then
        local path, flags, r, g, b, size, useShadow = GetGameplayFont("timer")
        ApplyGameplayFont(timerText, path, size or 20, flags or "OUTLINE")
        local gdb = GetGameplayDB()
        local tr, tg, tb = NormalizeRGB(gdb and gdb.combatTimerColor, r or 1, g or 1, b or 1)
        timerText:SetTextColor(tr, tg, tb, GlobalFontTextAlpha())
        SetTextShadow(timerText, useShadow)
    end

    if stateText then
        local path, flags, r, g, b, size, useShadow = GetGameplayFont("state")
        ApplyGameplayFont(stateText, path, (size or 24), flags or "OUTLINE")
        stateText:SetTextColor(r or 1, g or 1, b or 1, GlobalFontTextAlpha())
        SetTextShadow(stateText, useShadow)
        ApplyCombatStateDynamicColor()
    end

    if apexItText or apexItStackText then
        ApplyApexTextStyle(apexItText, false)
        ApplyApexTextStyle(apexItStackText, true)
    end
    if (apexRangeCounterHeader or apexRangeCounterText) and ApplyApexRangeCounterStyle then
        ApplyApexRangeCounterStyle()
    end
end

local DARKEST_NIGHT_TALENT_SPELL_ID = 457058
local DARKEST_NIGHT_AURA_SPELL_ID = 457280
local ANCIENT_ARTS_AURA_SPELL_ID = 1269163
local SHADOW_TECHNIQUES_AURA_SPELL_ID = 196911
local EVISCERATE_SPELL_ID = 196819
local SUBTLETY_ROGUE_SPEC_ID = 261
local APEX_MIN_SHADOW_TECHNIQUES_STACKS = 5
local APEX_ROLE_DARKEST = "darkestNight"
local APEX_ROLE_ANCIENT = "ancientArts"
local APEX_ROLE_SHADOW_TECHNIQUES = "shadowTechniques"
local APEX_VIEWER_NAMES = { "EssentialCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local apexRoleByCooldownID = {}
local apexRoleByViewerFrame = {}
local apexActiveByViewerFrame = {}
local apexHookedViewerFrames = {}
local apexHookedViewers = {}
local apexDriverRefreshBusy = false
local RefreshApexItCooldownDrivers

local function IsSubtletyRogue()
    return type(GetPlayerSpecID) == "function" and GetPlayerSpecID() == SUBTLETY_ROGUE_SPEC_ID
end

local function EnsureApexItFrame()
    -- Reuse and repair a partially-created named frame. This matters for developer
    -- reload paths: the named frame can survive while this file's local FontString
    -- references are rebuilt.
    apexItFrame = apexItFrame or _G.MSUF_ApexItDevAuraFrame
    local createdFrame = not apexItFrame
    if createdFrame then
        apexItFrame = CreateFrame("Frame", "MSUF_ApexItDevAuraFrame", UIParent)
    end
    apexItFrame:SetSize(360, 80)
    apexItFrame:SetFrameStrata("DIALOG")
    if createdFrame then apexItFrame:Hide() end

    apexItText = apexItText or apexItFrame._msufApexItText or _G.MSUF_ApexItDevAuraText
    if not apexItText then
        apexItText = apexItFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        apexItFrame._msufApexItText = apexItText
        apexItText:SetPoint("BOTTOM", apexItFrame, "CENTER", 0, 2)
    else
        apexItFrame._msufApexItText = apexItText
    end

    apexItStackText = apexItStackText or apexItFrame._msufApexItStackText or _G.MSUF_ApexItDevAuraStackText
    if not apexItStackText then
        apexItStackText = apexItFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        apexItFrame._msufApexItStackText = apexItStackText
        apexItStackText:SetPoint("TOP", apexItText, "BOTTOM", 0, -2)
    else
        apexItFrame._msufApexItStackText = apexItStackText
    end
    return apexItFrame
end

local function CooldownInfoContainsSpell(cooldownInfo, spellID)
    if not cooldownInfo then return false end
    if cooldownInfo.spellID == spellID
        or cooldownInfo.overrideSpellID == spellID
        or cooldownInfo.overrideTooltipSpellID == spellID
        or cooldownInfo.linkedSpellID == spellID then
        return true
    end
    local linkedSpellIDs = cooldownInfo.linkedSpellIDs
    if type(linkedSpellIDs) == "table" then
        for i = 1, #linkedSpellIDs do
            if linkedSpellIDs[i] == spellID then return true end
        end
    end
    return false
end

local function ResolveApexViewerFrameRole(frame)
    if not (frame and type(frame.GetCooldownID) == "function") then return nil end
    local cooldownID = frame:GetCooldownID()
    if not cooldownID then return nil end

    local cachedRole = apexRoleByCooldownID[cooldownID]
    if cachedRole ~= nil then return cachedRole or nil end

    -- Cooldown metadata is static, non-secret data. Resolve each cooldown ID once;
    -- combat callbacks then use only this cached role and Blizzard's active boolean.
    local cooldownInfo
    if C_CooldownViewer and type(C_CooldownViewer.GetCooldownViewerCooldownInfo) == "function" then
        cooldownInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
    end
    if not cooldownInfo and type(frame.GetCooldownInfo) == "function" then cooldownInfo = frame:GetCooldownInfo() end

    local role
    if CooldownInfoContainsSpell(cooldownInfo, 280719) then
        role = "secretTechnique"
    elseif CooldownInfoContainsSpell(cooldownInfo, DARKEST_NIGHT_AURA_SPELL_ID) then
        role = APEX_ROLE_DARKEST
    elseif CooldownInfoContainsSpell(cooldownInfo, ANCIENT_ARTS_AURA_SPELL_ID) then
        role = APEX_ROLE_ANCIENT
    elseif CooldownInfoContainsSpell(cooldownInfo, SHADOW_TECHNIQUES_AURA_SPELL_ID) then
        role = APEX_ROLE_SHADOW_TECHNIQUES
    end
    apexRoleByCooldownID[cooldownID] = role or false
    return role
end

local function ApexRoleIsActive(role)
    for frame, frameRole in pairs(apexRoleByViewerFrame) do
        if frameRole == role and apexActiveByViewerFrame[frame] == true then return true end
    end
    return false
end

apexRangeState.SecretTechniqueIsReady = function()
    for frame, frameRole in pairs(apexRoleByViewerFrame) do
        if frameRole == "secretTechnique"
            and apexRangeState.secretTechniqueReadyByFrame[frame] == true then
            return true
        end
    end
    return false
end

apexRangeState.HasSecretTechniqueCooldownDriver = function()
    for frame, frameRole in pairs(apexRoleByViewerFrame) do
        if frameRole == "secretTechnique" and frame then return true end
    end
    return false
end

apexRangeState.EnsureSecretTechniqueWindowCurve = function()
    if apexRangeState.secretTechniqueWindowCurve then return apexRangeState.secretTechniqueWindowCurve end
    local curveUtil = _G.C_CurveUtil
    if not (curveUtil and type(curveUtil.CreateCurve) == "function") then return nil end

    local curve = curveUtil.CreateCurve()
    if not (curve and type(curve.AddPoint) == "function") then return nil end
    if type(curve.SetType) == "function" then
        local curveTypes = _G.Enum and _G.Enum.LuaCurveType
        curve:SetType(curveTypes and curveTypes.Step or 1)
    end
    -- The native duration owns the protected remaining time. This public step
    -- curve only turns it into an alpha sink: visible through five seconds,
    -- fully transparent above that threshold. Addon Lua never compares or
    -- stores the cooldown value/result.
    curve:AddPoint(0, 1)
    curve:AddPoint(5.001, 0)
    apexRangeState.secretTechniqueWindowCurve = curve
    return curve
end

apexRangeState.EnsureSecretTechniqueOutsideWindowCurve = function()
    if apexRangeState.secretTechniqueOutsideWindowCurve then
        return apexRangeState.secretTechniqueOutsideWindowCurve
    end
    local curveUtil = _G.C_CurveUtil
    if not (curveUtil and type(curveUtil.CreateCurve) == "function") then return nil end

    local curve = curveUtil.CreateCurve()
    if not (curve and type(curve.AddPoint) == "function") then return nil end
    if type(curve.SetType) == "function" then
        local curveTypes = _G.Enum and _G.Enum.LuaCurveType
        curve:SetType(curveTypes and curveTypes.Step or 1)
    end
    -- Complement of the SECTECH window. The cooldown duration remains native:
    -- addon Lua never branches on the protected remaining-time value.
    curve:AddPoint(0, 0)
    curve:AddPoint(5.001, 1)
    apexRangeState.secretTechniqueOutsideWindowCurve = curve
    return curve
end

apexRangeState.CanUseSecretTechniqueNativeWindow = function()
    return apexRangeState.HasSecretTechniqueCooldownDriver()
        and C_Spell and type(C_Spell.GetSpellCooldownDuration) == "function"
        and apexRangeState.EnsureSecretTechniqueWindowCurve() ~= nil
        and apexRangeState.EnsureSecretTechniqueOutsideWindowCurve() ~= nil
end

apexRangeState.RefreshChargedComboPointState = function()
    local hasCharged = false
    local getCharged = _G.GetUnitChargedPowerPoints
    if type(getCharged) == "function" then
        local ok, result = pcall(function()
            local indices = getCharged("player")
            local issecretvalue = _G.issecretvalue
            local canaccesstable = _G.canaccesstable
            if indices == nil
                or (type(issecretvalue) == "function" and issecretvalue(indices) == true)
                or type(indices) ~= "table"
                or (type(canaccesstable) == "function" and canaccesstable(indices) == false) then
                return false
            end

            for i = 1, #indices do
                local chargedIndex = indices[i]
                if not (type(issecretvalue) == "function" and issecretvalue(chargedIndex) == true)
                    and type(chargedIndex) == "number"
                    and chargedIndex >= 1 then
                    return true
                end
            end
            return false
        end)
        if ok and result == true then hasCharged = true end
    end

    local changed = apexRangeState.hasChargedComboPoint ~= hasCharged
    apexRangeState.hasChargedComboPoint = hasCharged
    return changed
end

apexRangeState.RefreshMultiTargetActionAlphas = function()
    if not apexItFrame or apexRangeState.sensorAction ~= "multiTarget" then return false end
    local function SetSensorAlpha(sensor, alpha)
        if sensor and type(sensor.SetAlpha) == "function" then sensor:SetAlpha(alpha) end
    end

    if apexRangeState.secretTechniqueCastPending == true then
        SetSensorAlpha(apexRangeState.secTechLabelSensor, 0)
        SetSensorAlpha(apexRangeState.secTechStackSensor, 0)
        SetSensorAlpha(apexRangeState.blackPowderLabelSensor, 0)
        SetSensorAlpha(apexRangeState.blackPowderStackSensor, 0)
        return false
    end

    if apexRangeState.CanUseSecretTechniqueNativeWindow() then
        local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, 280719, true)
        if ok and duration and type(duration.EvaluateRemainingDuration) == "function" then
            local secOK, secAlpha = pcall(duration.EvaluateRemainingDuration,
                duration, apexRangeState.secretTechniqueWindowCurve)
            local bpOK, bpAlpha = pcall(duration.EvaluateRemainingDuration,
                duration, apexRangeState.secretTechniqueOutsideWindowCurve)
            local issecretvalue = _G.issecretvalue
            local secUsable = secOK and ((type(issecretvalue) == "function"
                and issecretvalue(secAlpha) == true) or type(secAlpha) == "number")
            local bpUsable = bpOK and ((type(issecretvalue) == "function"
                and issecretvalue(bpAlpha) == true) or type(bpAlpha) == "number")
            if secUsable and bpUsable then
                -- Both values go straight from Blizzard's Duration object into
                -- native alpha sinks. The complementary curves choose SECTECH
                -- inside five seconds and BLACK POWDER outside that window.
                SetSensorAlpha(apexRangeState.secTechLabelSensor, secAlpha)
                SetSensorAlpha(apexRangeState.secTechStackSensor, secAlpha)
                SetSensorAlpha(apexRangeState.blackPowderLabelSensor, bpAlpha)
                SetSensorAlpha(apexRangeState.blackPowderStackSensor, bpAlpha)
                return true
            end
        end
    end

    -- Degraded clients retain deterministic exact-ready behavior. Black Powder
    -- is the fallback only when a Supercharger-marked point is actually known.
    local secretReady = apexRangeState.SecretTechniqueIsReady()
    local secAlpha = secretReady and 1 or 0
    local bpAlpha = not secretReady
        and apexRangeState.hasChargedComboPoint == true and 1 or 0
    SetSensorAlpha(apexRangeState.secTechLabelSensor, secAlpha)
    SetSensorAlpha(apexRangeState.secTechStackSensor, secAlpha)
    SetSensorAlpha(apexRangeState.blackPowderLabelSensor, bpAlpha)
    SetSensorAlpha(apexRangeState.blackPowderStackSensor, bpAlpha)
    return false
end

apexRangeState.UpdateSecretTechniqueReadyFromFrame = function(frame)
    if apexRoleByViewerFrame[frame] ~= "secretTechnique"
        or type(frame.IsOnCooldown) ~= "function" then return false end
    local inCombat = type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true
    if inCombat then return false end

    local ok, onCooldown = pcall(frame.IsOnCooldown, frame)
    local issecretvalue = _G.issecretvalue
    if not ok
        or (type(issecretvalue) == "function" and issecretvalue(onCooldown) == true)
        or type(onCooldown) ~= "boolean" then return false end

    local ready = onCooldown == false
    if apexRangeState.secretTechniqueReadyByFrame[frame] == ready then return false end
    apexRangeState.secretTechniqueReadyByFrame[frame] = ready
    return true
end

apexRangeState.SetSecretTechniqueReady = function(frame, ready)
    if apexRoleByViewerFrame[frame] ~= "secretTechnique" then return false end
    ready = ready == true
    if apexRangeState.secretTechniqueReadyByFrame[frame] == ready then return false end
    apexRangeState.secretTechniqueReadyByFrame[frame] = ready
    return true
end

apexRangeState.SetAllSecretTechniqueReady = function(ready)
    local changed = false
    for frame, frameRole in pairs(apexRoleByViewerFrame) do
        if frameRole == "secretTechnique"
            and apexRangeState.SetSecretTechniqueReady(frame, ready) then changed = true end
    end
    return changed
end

apexRangeState.OnSecretTechniqueCooldownDataChanged = function(frame)
    local changed = apexRangeState.UpdateSecretTechniqueReadyFromFrame(frame)
    if apexRangeState.secretTechniqueCastPending then
        apexRangeState.secretTechniqueCastPending = false
        changed = true
    end
    if changed and apexRangeState.RefreshApexItDevAura then
        apexRangeState.RefreshApexItDevAura()
    elseif apexRangeState.RefreshMultiTargetActionAlphas then
        apexRangeState.RefreshMultiTargetActionAlphas()
    end
end

apexRangeState.OnSecretTechniqueCooldownDone = function(frame)
    local changed = apexRangeState.SetSecretTechniqueReady(frame, true)
    if apexRangeState.secretTechniqueCastPending then
        apexRangeState.secretTechniqueCastPending = false
        changed = true
    end
    if (changed or apexRangeState.sensorAction == "multiTarget")
        and apexRangeState.RefreshApexItDevAura then apexRangeState.RefreshApexItDevAura() end
end

local function IsPlainSpellID(spellID, expectedSpellID)
    local issecretvalue = _G.issecretvalue
    if type(issecretvalue) == "function" and issecretvalue(spellID) == true then return false end
    return type(spellID) == "number" and spellID == expectedSpellID
end

local function RefreshApexDeathstalkerKnown()
    local known = false
    local isKnown = C_SpellBook and C_SpellBook.IsSpellKnown
    if type(isKnown) == "function" then
        local ok, result = pcall(isKnown, DARKEST_NIGHT_TALENT_SPELL_ID)
        local issecretvalue = _G.issecretvalue
        if ok and not (type(issecretvalue) == "function" and issecretvalue(result) == true) then
            known = result == true
        end
    end
    apexDeathstalkerKnown = known
end

local function IsDeathstalkerActive()
    -- Fail closed here: a stale CooldownViewer entry for Darkest Night must not
    -- turn this Deathstalker-only helper into a Trickster rule.
    return apexDeathstalkerKnown
end

local function CreateApexStackThresholdFormatter(visibleFormat)
    if not (C_StringUtil and type(C_StringUtil.CreateNumericRuleFormatter) == "function") then return nil end
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    formatter:SetBreakpoints({
        { threshold = 0, format = "" },
        { threshold = APEX_MIN_SHADOW_TECHNIQUES_STACKS, format = visibleFormat },
    })
    return formatter
end

local function ShadowTechniquesHighlightTarget(frame)
    if frame and type(frame.GetAlertTargetFrame) == "function" then
        local ok, target = pcall(frame.GetAlertTargetFrame, frame)
        if ok and target then return target end
    end
    return frame
end

local function ShadowTechniquesHighlightVisual(g, target)
    local width, height
    if target and type(target.GetSize) == "function" then
        local ok, w, h = pcall(target.GetSize, target)
        if ok then width, height = tonumber(w), tonumber(h) end
    end
    width = math_max(1, width or 36)
    height = math_max(1, height or 36)
    local scale = math_max(75, math_min(175, tonumber(g and g.shadowTechniquesGlowScale) or 100)) / 100
    local edge = math_max(3, math_min(24, math_min(width, height) * 0.17 * scale))
    local color = g and g.shadowTechniquesGlowColor
    local r = math_max(0, math_min(1, tonumber(color and color[1]) or 0.69))
    local green = math_max(0, math_min(1, tonumber(color and color[2]) or 0.50))
    local b = math_max(0, math_min(1, tonumber(color and color[3]) or 0.88))
    local alpha = math_max(10, math_min(100, tonumber(g and g.shadowTechniquesGlowStrength) or 80)) / 100
    local signature = string_format("%.2f:%.2f:%.2f:%d:%d:%d:%d",
        width, height, edge, math_floor(r * 255 + 0.5), math_floor(green * 255 + 0.5),
        math_floor(b * 255 + 0.5), math_floor(alpha * 100 + 0.5))
    return {
        width = width,
        height = height,
        edge = edge,
        r = r,
        g = green,
        b = b,
        a = alpha,
        signature = signature,
    }
end

local function InitializeShadowTechniquesHighlightButton(button, visual)
    button:ClearAllPoints()
    button:SetAllPoints(button:GetParent())
    if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
    if button.EnableMouse then button:EnableMouse(false) end

    local BorderStyles = MSUF.BorderStyles or _G.MSUF_BorderStyles
    local texture = BorderStyles and BorderStyles.Resolve and BorderStyles.Resolve("GLOW")
    if not (texture and BorderStyles.Create and BorderStyles.Apply and button.SetApplicationBar) then return end

    -- Application counts are secret in combat. AuraContainer therefore owns a
    -- hidden StatusBar whose value is clamped to 0..5. Its C-side fill edge
    -- moves the glow host into this clipping gate only at five applications;
    -- addon Lua never reads or compares the protected stack count.
    local gate = CreateFrame("Frame", nil, button)
    if not gate.SetClipsChildren then return end
    local gateWidth = visual.width + visual.edge
    local gateHeight = visual.height + visual.edge
    gate:SetSize(gateWidth, gateHeight)
    gate:SetPoint("CENTER", button, "CENTER", 0, 0)
    gate:SetClipsChildren(true)

    local travel = math_max(gateWidth, gateHeight) + visual.edge + 2
    local applicationBar = CreateFrame("StatusBar", nil, button)
    applicationBar:SetSize(travel * APEX_MIN_SHADOW_TECHNIQUES_STACKS, 1)
    applicationBar:SetPoint("LEFT", gate, "CENTER", -travel * APEX_MIN_SHADOW_TECHNIQUES_STACKS, 0)
    applicationBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    applicationBar:SetMinMaxValues(0, APEX_MIN_SHADOW_TECHNIQUES_STACKS)
    applicationBar:SetValue(0)
    applicationBar:SetAlpha(0)
    if applicationBar.EnableMouse then applicationBar:EnableMouse(false) end

    local fill = applicationBar:GetStatusBarTexture()
    local host = CreateFrame("Frame", nil, gate)
    host:SetSize(visual.width, visual.height)
    host:SetPoint("CENTER", fill, "RIGHT", 0, 0)
    local pieces = BorderStyles.Create(host, "OVERLAY", 7, texture)
    BorderStyles.Apply(pieces, host, visual.edge, visual.width, visual.height,
        visual.r, visual.g, visual.b, visual.a)

    -- Bind last: AuraContainer seals the inbound StatusBar and its descendants
    -- immediately. Every visual mutation above must remain initialization-only.
    button:SetApplicationBar(applicationBar, {
        maxApplications = APEX_MIN_SHADOW_TECHNIQUES_STACKS,
    })
end

local function EnsureShadowTechniquesHighlightSensor(frame)
    local A3 = _G.MSUF_Auras3
    local createSensor = A3 and A3.CreateClassPowerAuraSensor
    local target = ShadowTechniquesHighlightTarget(frame)
    if type(createSensor) ~= "function" or not target then return nil end

    local g = GetGameplayDB()
    local visual = ShadowTechniquesHighlightVisual(g, target)
    local current = shadowTechHighlightSensorsByFrame[frame]
    if current and current.signature == visual.signature then return current.sensor end

    local generation = (current and current.generation or 0) + 1
    local sensor = createSensor(target, "msuf_shadow_techniques_stack_highlight_" .. tostring(generation), {
        [SHADOW_TECHNIQUES_AURA_SPELL_ID] = true,
    }, function(button)
        InitializeShadowTechniquesHighlightButton(button, visual)
    end)
    if not sensor then return nil end

    sensor:ClearAllPoints()
    sensor:SetAllPoints(target)
    if current and current.sensor then
        if type(current.sensor.SetEnabled) == "function" then current.sensor:SetEnabled(false) end
        current.sensor:SetShown(false)
    end
    shadowTechHighlightSensorsByFrame[frame] = {
        sensor = sensor,
        signature = visual.signature,
        generation = generation,
    }
    return sensor
end

local function SetShadowTechniquesHighlightSensorsActive(active)
    active = active == true
    for frame, entry in pairs(shadowTechHighlightSensorsByFrame) do
        local sensor = entry and entry.sensor
        local shown = active and apexRoleByViewerFrame[frame] == APEX_ROLE_SHADOW_TECHNIQUES
        if sensor then
            if type(sensor.SetEnabled) == "function" then sensor:SetEnabled(shown) end
            sensor:SetShown(shown)
        end
    end
end

local function InitializeApexStackSensorButton(button, isStackText, formatter)
    button:ClearAllPoints()
    button:SetAllPoints(button:GetParent())
    if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
    if button.EnableMouse then button:EnableMouse(false) end

    local fontTemplate = isStackText and "GameFontNormalLarge" or "GameFontNormalHuge"
    local fontString = button:CreateFontString(nil, "OVERLAY", fontTemplate)
    if isStackText then
        fontString:SetPoint("TOP", button, "CENTER", 0, -2)
    else
        fontString:SetPoint("BOTTOM", button, "CENTER", 0, 2)
    end

    -- Finish every addon-owned visual mutation before AuraContainer seals the
    -- inbound FontString and takes ownership of its secret Text/Shown aspects.
    ApplyApexTextStyle(fontString, isStackText)
    button:SetApplicationCount(fontString, { formatter = formatter })
end

local function EnsureApexStackThresholdSensors()
    local A3 = _G.MSUF_Auras3
    local createSensor = A3 and A3.CreateClassPowerAuraSensor
    if type(createSensor) ~= "function" or not apexItFrame then return false end

    if not apexItLabelSensor then
        local formatter = CreateApexStackThresholdFormatter("APEX IT")
        if formatter then
            apexItLabelSensor = createSensor(apexItFrame, "msuf_apex_it_label",
                { [SHADOW_TECHNIQUES_AURA_SPELL_ID] = true }, function(button)
                    InitializeApexStackSensorButton(button, false, formatter)
                end)
        end
    end

    if not apexRangeState.secTechLabelSensor then
        local formatter = CreateApexStackThresholdFormatter("APEX SECTECH")
        if formatter then
            apexRangeState.secTechLabelSensor = createSensor(apexItFrame, "msuf_apex_sectech_label",
                { [SHADOW_TECHNIQUES_AURA_SPELL_ID] = true }, function(button)
                    InitializeApexStackSensorButton(button, false, formatter)
                end)
        end
    end

    if not apexRangeState.blackPowderLabelSensor then
        local formatter = CreateApexStackThresholdFormatter("APEX BLACK POWDER")
        if formatter then
            apexRangeState.blackPowderLabelSensor = createSensor(apexItFrame,
                "msuf_apex_black_powder_label",
                { [SHADOW_TECHNIQUES_AURA_SPELL_ID] = true }, function(button)
                    InitializeApexStackSensorButton(button, false, formatter)
                end)
        end
    end

    if not apexItStackSensor then
        local formatter = CreateApexStackThresholdFormatter("%d")
        if formatter then
            apexItStackSensor = createSensor(apexItFrame, "msuf_apex_it_stacks",
                { [SHADOW_TECHNIQUES_AURA_SPELL_ID] = true }, function(button)
                    InitializeApexStackSensorButton(button, true, formatter)
                end)
        end
    end

    if not apexRangeState.secTechStackSensor then
        local formatter = CreateApexStackThresholdFormatter("%d")
        if formatter then
            apexRangeState.secTechStackSensor = createSensor(apexItFrame,
                "msuf_apex_sectech_stacks",
                { [SHADOW_TECHNIQUES_AURA_SPELL_ID] = true }, function(button)
                    InitializeApexStackSensorButton(button, true, formatter)
                end)
        end
    end

    if not apexRangeState.blackPowderStackSensor then
        local formatter = CreateApexStackThresholdFormatter("%d")
        if formatter then
            apexRangeState.blackPowderStackSensor = createSensor(apexItFrame,
                "msuf_apex_black_powder_stacks",
                { [SHADOW_TECHNIQUES_AURA_SPELL_ID] = true }, function(button)
                    InitializeApexStackSensorButton(button, true, formatter)
                end)
        end
    end

    local function AnchorSensor(sensor)
        if sensor then
            sensor:ClearAllPoints()
            sensor:SetAllPoints(apexItFrame)
        end
    end
    AnchorSensor(apexItLabelSensor)
    AnchorSensor(apexRangeState.secTechLabelSensor)
    AnchorSensor(apexRangeState.blackPowderLabelSensor)
    AnchorSensor(apexItStackSensor)
    AnchorSensor(apexRangeState.secTechStackSensor)
    AnchorSensor(apexRangeState.blackPowderStackSensor)
    apexRangeState.sensorActionApplied = false
    return apexItLabelSensor ~= nil
        and apexRangeState.secTechLabelSensor ~= nil
        and apexRangeState.blackPowderLabelSensor ~= nil
        and apexItStackSensor ~= nil
        and apexRangeState.secTechStackSensor ~= nil
        and apexRangeState.blackPowderStackSensor ~= nil
end

local function SetApexStackThresholdSensorAction(action)
    local blackPowderEligible = apexRangeState.hasChargedComboPoint == true
    if action ~= "multiTarget" and apexRangeState.CancelMultiTargetRefreshTimer then
        apexRangeState.CancelMultiTargetRefreshTimer()
    end
    if apexRangeState.sensorActionApplied and apexRangeState.sensorAction == action
        and (action ~= "multiTarget"
            or apexRangeState.blackPowderEligibleApplied == blackPowderEligible) then return end
    apexRangeState.sensorAction = action
    apexRangeState.sensorActionApplied = true
    apexRangeState.blackPowderEligibleApplied = blackPowderEligible
    local function SetSensorState(sensor, active)
        if sensor then
            if type(sensor.SetEnabled) == "function" then sensor:SetEnabled(active) end
            sensor:SetShown(active)
            if type(sensor.SetAlpha) == "function" then sensor:SetAlpha(1) end
        end
    end

    -- Switching target bands must be visually atomic. Clear every native label
    -- first so Darkest Night can never leave APEX IT exposed while the 4+
    -- Secret Technique route is being activated (or vice versa).
    SetSensorState(apexItLabelSensor, false)
    SetSensorState(apexRangeState.secTechLabelSensor, false)
    SetSensorState(apexRangeState.blackPowderLabelSensor, false)
    SetSensorState(apexItStackSensor, false)
    SetSensorState(apexRangeState.secTechStackSensor, false)
    SetSensorState(apexRangeState.blackPowderStackSensor, false)

    if action == "multiTarget" then
        SetSensorState(apexRangeState.secTechLabelSensor, true)
        SetSensorState(apexRangeState.secTechStackSensor, true)
        SetSensorState(apexRangeState.blackPowderLabelSensor, blackPowderEligible)
        SetSensorState(apexRangeState.blackPowderStackSensor, blackPowderEligible)
        apexRangeState.RefreshMultiTargetActionAlphas()
    elseif action == "eviscerate" then
        SetSensorState(apexItLabelSensor, true)
        SetSensorState(apexItStackSensor, true)
    end
end

apexRangeState.InvalidateActionSnapshot = function()
    apexRangeState.snapshotValid = false
    apexRangeState.inRangeEnemyCount = 0
    SetApexStackThresholdSensorAction(nil)
    if apexItFrame then
        apexItFrame:SetAlpha(1)
        apexItFrame:Hide()
    end
end

apexRangeState.CommonRuleEligible = function(g)
    return g and g.enableApexItDevAura == true
        and IsSubtletyRogue()
        and IsDeathstalkerActive()
        and ApexRoleIsActive(APEX_ROLE_SHADOW_TECHNIQUES)
        and not ApexRoleIsActive(APEX_ROLE_ANCIENT)
end

apexRangeState.EviscerateRuleEligible = function(g)
    return apexRangeState.CommonRuleEligible(g)
        and not apexItConsumed
        and ApexRoleIsActive(APEX_ROLE_DARKEST)
end

apexRangeState.MultiTargetRuleEligible = function(g)
    return apexRangeState.CommonRuleEligible(g)
        and apexRangeState.secretTechniqueCastPending ~= true
        and (apexRangeState.CanUseSecretTechniqueNativeWindow()
            or apexRangeState.SecretTechniqueIsReady()
            or apexRangeState.hasChargedComboPoint == true)
end

apexRangeState.BaseRuleEligible = function(g)
    return apexRangeState.EviscerateRuleEligible(g)
        or apexRangeState.MultiTargetRuleEligible(g)
end

local function RefreshApexItDevAura()
    local g = GetGameplayDB()
    if apexItPreviewActive then
        SetApexStackThresholdSensorAction(nil)
        local frame = EnsureApexItFrame()
        frame:SetAlpha(1)
        if apexItText then apexItText:Show() end
        if apexItStackText then
            apexItStackText:SetText(tostring(APEX_MIN_SHADOW_TECHNIQUES_STACKS))
            apexItStackText:Show()
        end
        frame:Show()
        return
    end
    if apexItText then apexItText:Hide() end
    if apexItStackText then apexItStackText:Hide() end
    if not (apexItFrame and g and g.enableApexItDevAura == true and IsSubtletyRogue()) then
        SetApexStackThresholdSensorAction(nil)
        if apexItFrame then apexItFrame:Hide() end
        return
    end

    local baseEligible = apexRangeState.BaseRuleEligible(g)
    local targetDetectionEnabled = g.enableApexNameplateRangeDetection ~= false
    local action
    if baseEligible then
        if not targetDetectionEnabled and apexRangeState.EviscerateRuleEligible(g) then
            -- The expensive target-count driver is optional. Without it we cannot
            -- distinguish 1-3 from 4+ targets. Keep only the deterministic Darkest
            -- Night single-target fallback; never reinterpret a ready multi-target
            -- Secret Technique route as APEX IT.
            action = "eviscerate"
        elseif apexRangeState.snapshotValid then
            if apexRangeState.inRangeEnemyCount >= 4
                and apexRangeState.MultiTargetRuleEligible(g) then
                action = "multiTarget"
            elseif apexRangeState.inRangeEnemyCount >= 1
                and apexRangeState.inRangeEnemyCount <= 3
                and apexRangeState.EviscerateRuleEligible(g) then
                action = "eviscerate"
            end
        end
    end
    SetApexStackThresholdSensorAction(action)
    if apexItFrame then apexItFrame:SetAlpha(1) end
    if action == "multiTarget" then
        apexRangeState.RefreshMultiTargetActionAlphas()
        if apexRangeState.ArmMultiTargetRefreshTimer then
            apexRangeState.ArmMultiTargetRefreshTimer()
        end
    end
    apexItFrame:SetShown(action ~= nil)

    if targetDetectionEnabled and apexRangeState.CommonRuleEligible(g)
        and not apexRangeState.snapshotValid and apexRangeState.RequestScan then
        apexRangeState.RequestScan()
    elseif not targetDetectionEnabled
        or (not apexRangeState.CommonRuleEligible(g)
            and not (g.enableApexRangeCounter == true and IsSubtletyRogue())) then
        -- Never reuse a target count from an earlier actionable APEX window.
        apexRangeState.snapshotValid = false
        apexRangeState.inRangeEnemyCount = 0
    end
end
apexRangeState.RefreshApexItDevAura = RefreshApexItDevAura

local function OnApexViewerActiveStateChanged(frame)
    local role = apexRoleByViewerFrame[frame]
    if not role then return end
    apexActiveByViewerFrame[frame] = type(frame.IsActive) == "function" and frame:IsActive() == true or false
    if role == APEX_ROLE_DARKEST and not ApexRoleIsActive(APEX_ROLE_DARKEST) then
        apexItConsumed = false
    end
    if role == "secretTechnique" then
        apexRangeState.UpdateSecretTechniqueReadyFromFrame(frame)
    end
    RefreshApexItDevAura()
end

RefreshApexItCooldownDrivers = function()
    if apexDriverRefreshBusy then return end
    apexDriverRefreshBusy = true
    local g = GetGameplayDB()

    for frame in pairs(apexRoleByViewerFrame) do apexRoleByViewerFrame[frame] = nil end
    for frame in pairs(apexActiveByViewerFrame) do apexActiveByViewerFrame[frame] = nil end

    for i = 1, #APEX_VIEWER_NAMES do
        local viewer = _G[APEX_VIEWER_NAMES[i]]
        if viewer and type(viewer.GetItemFrames) == "function" then
            if not apexHookedViewers[viewer] and type(hooksecurefunc) == "function" and type(viewer.RefreshData) == "function" then
                apexHookedViewers[viewer] = true
                hooksecurefunc(viewer, "RefreshData", RefreshApexItCooldownDrivers)
            end

            local itemFrames = viewer:GetItemFrames()
            for j = 1, #itemFrames do
                local itemFrame = itemFrames[j]
                local role = ResolveApexViewerFrameRole(itemFrame)
                if role then
                    apexRoleByViewerFrame[itemFrame] = role
                    apexActiveByViewerFrame[itemFrame] = type(itemFrame.IsActive) == "function" and itemFrame:IsActive() == true or false
                    if not apexHookedViewerFrames[itemFrame] and type(hooksecurefunc) == "function" then
                        apexHookedViewerFrames[itemFrame] = true
                        if type(itemFrame.OnActiveStateChanged) == "function" then
                            hooksecurefunc(itemFrame, "OnActiveStateChanged", OnApexViewerActiveStateChanged)
                        end
                        if role == "secretTechnique" then
                            if type(itemFrame.RefreshData) == "function" then
                                hooksecurefunc(itemFrame, "RefreshData", apexRangeState.OnSecretTechniqueCooldownDataChanged)
                            end
                            if type(itemFrame.RefreshCooldownOnly) == "function" then
                                hooksecurefunc(itemFrame, "RefreshCooldownOnly", apexRangeState.OnSecretTechniqueCooldownDataChanged)
                            end
                            if type(itemFrame.OnCooldownDone) == "function" then
                                hooksecurefunc(itemFrame, "OnCooldownDone", apexRangeState.OnSecretTechniqueCooldownDone)
                            end
                            local cooldownFrame = type(itemFrame.GetCooldownFrame) == "function"
                                and itemFrame:GetCooldownFrame() or nil
                            if cooldownFrame and type(cooldownFrame.HookScript) == "function" then
                                cooldownFrame:HookScript("OnCooldownDone", function()
                                    apexRangeState.OnSecretTechniqueCooldownDone(itemFrame)
                                end)
                            end
                        end
                    end
                    if role == "secretTechnique" then
                        apexRangeState.UpdateSecretTechniqueReadyFromFrame(itemFrame)
                    end
                    if role == APEX_ROLE_SHADOW_TECHNIQUES
                        and g and g.enableShadowTechniquesStackHighlight == true
                        and IsSubtletyRogue() then
                        EnsureShadowTechniquesHighlightSensor(itemFrame)
                    end
                end
            end
        end
    end

    for frame in pairs(apexRangeState.secretTechniqueReadyByFrame) do
        if apexRoleByViewerFrame[frame] ~= "secretTechnique" then
            apexRangeState.secretTechniqueReadyByFrame[frame] = nil
        end
    end

    if not ApexRoleIsActive(APEX_ROLE_DARKEST) then
        apexItConsumed = false
    end
    SetShadowTechniquesHighlightSensorsActive(g
        and g.enableShadowTechniquesStackHighlight == true
        and IsSubtletyRogue())
    apexDriverRefreshBusy = false
    RefreshApexItDevAura()
end

local function EnsureApexItEventFrame()
    if apexItEventFrame then return apexItEventFrame end

    apexItEventFrame = CreateFrame("Frame")
    apexItEventFrame:SetScript("OnEvent", function(_, event, arg1, _, spellID)
        if event == "UNIT_POWER_POINT_CHARGE" then
            if arg1 == "player" and apexRangeState.RefreshChargedComboPointState() then
                RefreshApexItDevAura()
            end
            return
        end
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if IsPlainSpellID(spellID, EVISCERATE_SPELL_ID) then
                if ApexRoleIsActive(APEX_ROLE_DARKEST) then
                    apexItConsumed = true
                    apexRangeState.snapshotValid = false
                    RefreshApexItDevAura()
                end
            elseif IsPlainSpellID(spellID, 280719) then
                -- Consume immediately even if Blizzard publishes the new
                -- cooldown duration one event later. The hooked native
                -- RefreshCooldownOnly/RefreshData path clears this latch.
                apexRangeState.secretTechniqueCastPending = true
                apexRangeState.SetAllSecretTechniqueReady(false)
                apexRangeState.snapshotValid = false
                RefreshApexItDevAura()
            end
            return
        end
        if event == "ADDON_LOADED"
            and arg1 ~= "Blizzard_CooldownViewer"
            and arg1 ~= "Blizzard_AuraContainer" then return end
        if ApplyApexItDevAura then ApplyApexItDevAura(GetGameplayDB()) end
        if ApplyApexRangeCounter then ApplyApexRangeCounter(GetGameplayDB()) end
    end)
    return apexItEventFrame
end

ApplyApexItDevAura = function(g)
    local apexEnabled = g and g.enableApexItDevAura == true
    local shadowHighlightEnabled = g and g.enableShadowTechniquesStackHighlight == true
    local enabled = apexEnabled or shadowHighlightEnabled
    if not enabled and not apexItPreviewActive then
        apexItConsumed = false
        apexDeathstalkerKnown = false
        if apexItEventFrame then apexItEventFrame:UnregisterAllEvents() end
        SetApexStackThresholdSensorAction(nil)
        SetShadowTechniquesHighlightSensorsActive(false)
        if apexItFrame then apexItFrame:Hide() end
        return
    end

    g = g or GetGameplayDB() or {}
    local frame
    if apexEnabled or apexItPreviewActive then
        frame = EnsureApexItFrame()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", tonumber(g.apexItOffsetX) or 0, tonumber(g.apexItOffsetY) or 140)
    elseif apexItFrame then
        apexItFrame:Hide()
    end
    local subtletyEnabled = enabled and IsSubtletyRogue()
    if subtletyEnabled and apexEnabled then
        RefreshApexDeathstalkerKnown()
        if apexEnabled then EnsureApexStackThresholdSensors() end
    else
        apexDeathstalkerKnown = false
    end
    local deathstalkerEnabled = subtletyEnabled and IsDeathstalkerActive()
    if deathstalkerEnabled and apexEnabled then
        apexRangeState.RefreshChargedComboPointState()
    else
        apexRangeState.hasChargedComboPoint = false
    end
    if apexEnabled or apexItPreviewActive then
        ApplyFontToCounter()
        -- Text is assigned only after ApplyFontToCounter. WoW rejects SetText on a
        -- FontString that has no FontObject/font yet.
        apexItText:SetText("APEX IT")
    end

    local events = EnsureApexItEventFrame()
    events:UnregisterAllEvents()
    if enabled then
        events:RegisterEvent("ADDON_LOADED")
        events:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    end
    if subtletyEnabled and apexEnabled then
        events:RegisterEvent("PLAYER_TALENT_UPDATE")
        events:RegisterEvent("TRAIT_CONFIG_UPDATED")
        events:RegisterEvent("SPELLS_CHANGED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    if deathstalkerEnabled and apexEnabled then
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        events:RegisterUnitEvent("UNIT_POWER_POINT_CHARGE", "player")
    end
    if not (deathstalkerEnabled and not apexItPreviewActive) then
        SetApexStackThresholdSensorAction(nil)
    end
    SetShadowTechniquesHighlightSensorsActive(shadowHighlightEnabled and subtletyEnabled)
    if subtletyEnabled then
        RefreshApexItCooldownDrivers()
    end
    RefreshApexItDevAura()
end

function MSUF.MSUF_Gameplay_ApexIt_SetPreview(enabled)
    apexItPreviewActive = enabled == true
    ApplyApexItDevAura(GetGameplayDB())
    return apexItPreviewActive
end

function MSUF.MSUF_Gameplay_ApexIt_TogglePreview()
    return MSUF.MSUF_Gameplay_ApexIt_SetPreview(not apexItPreviewActive)
end

function MSUF.MSUF_Gameplay_ApexIt_IsPreviewActive()
    return apexItPreviewActive
end

-- Full nameplate scans stay bounded because they query every visible hostile.
-- The lightweight BP/SECTECH alpha gate below runs separately, so the action
-- can react much faster without multiplying those per-nameplate range calls.
local APEX_RANGE_COUNTER_INTERVAL = 0.10

local function IsApexRangeCounterUnit(unit)
    return type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil
end

local function ClearApexRangeCounterUnits()
    for unit in pairs(apexRangeCounterUnits) do apexRangeCounterUnits[unit] = nil end
    apexRangeState.snapshotValid = false
    apexRangeState.inRangeEnemyCount = 0
end

local function CancelApexRangeCounterTimer()
    apexRangeCounterTimerGeneration = apexRangeCounterTimerGeneration + 1
    local timer = apexRangeCounterTimer
    apexRangeCounterTimer = nil
    if timer and timer.Cancel then timer:Cancel() end
end

apexRangeState.DiagnosticActive = function(g)
    return g and g.enableApexNameplateRangeDetection ~= false
        and g.enableApexRangeCounter == true
        and apexRangeCounterPreviewActive ~= true
        and IsSubtletyRogue()
end

local function ApexRangeCounterRuntimeActive()
    local g = GetGameplayDB()
    return g and g.enableApexNameplateRangeDetection ~= false
        -- Keep the current target snapshot warm throughout the shared APEX
        -- window. Readiness/Darkest Night decide the action, not whether target
        -- monitoring is allowed to run; coupling those states caused SECTECH
        -- to wait for a fresh scan after becoming relevant.
        and (apexRangeState.DiagnosticActive(g) or apexRangeState.CommonRuleEligible(g))
end

apexRangeState.CancelMultiTargetRefreshTimer = function()
    apexRangeState.multiTargetRefreshTimerGeneration =
        (apexRangeState.multiTargetRefreshTimerGeneration or 0) + 1
    local timer = apexRangeState.multiTargetRefreshTimer
    apexRangeState.multiTargetRefreshTimer = nil
    if timer and timer.Cancel then timer:Cancel() end
end

apexRangeState.MultiTargetRefreshRuntimeActive = function()
    return apexRangeState.sensorAction == "multiTarget"
        and ApexRangeCounterRuntimeActive()
        and apexRangeState.CanUseSecretTechniqueNativeWindow()
end

apexRangeState.ArmMultiTargetRefreshTimer = function()
    apexRangeState.CancelMultiTargetRefreshTimer()
    if not apexRangeState.MultiTargetRefreshRuntimeActive() then return end
    local generation = apexRangeState.multiTargetRefreshTimerGeneration
    local function OnTimer()
        if generation ~= apexRangeState.multiTargetRefreshTimerGeneration then return end
        apexRangeState.multiTargetRefreshTimer = nil
        if not apexRangeState.MultiTargetRefreshRuntimeActive() then return end
        apexRangeState.RefreshMultiTargetActionAlphas()
        apexRangeState.ArmMultiTargetRefreshTimer()
    end
    if C_Timer and type(C_Timer.NewTimer) == "function" then
        apexRangeState.multiTargetRefreshTimer = C_Timer.NewTimer(0.05, OnTimer)
    elseif C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0.05, OnTimer)
    end
end

ApplyApexRangeCounterStyle = function()
    if not (apexRangeCounterHeader and apexRangeCounterText) then return end
    local g = GetGameplayDB() or {}
    local path, flags, _, _, _, _, useShadow = GetGameplayFont("state")
    local size = math_max(10, math_min(36, tonumber(g.apexRangeCounterFontSize) or 18))
    ApplyGameplayFont(apexRangeCounterHeader, path, math_max(9, math_floor(size * 0.72)), flags or "OUTLINE")
    ApplyGameplayFont(apexRangeCounterText, path, size, flags or "OUTLINE")
    apexRangeCounterHeader:SetTextColor(1, 0.82, 0.08, GlobalFontTextAlpha())
    apexRangeCounterText:SetTextColor(1, 1, 1, GlobalFontTextAlpha())
    SetTextShadow(apexRangeCounterHeader, useShadow ~= false)
    SetTextShadow(apexRangeCounterText, useShadow ~= false)
end

local function EnsureApexRangeCounterFrame()
    apexRangeCounterFrame = apexRangeCounterFrame or _G.MSUF_ApexRangeCounterFrame
    local createdFrame = not apexRangeCounterFrame
    if createdFrame then
        apexRangeCounterFrame = CreateFrame("Frame", "MSUF_ApexRangeCounterFrame", UIParent)
    end
    apexRangeCounterFrame:SetSize(620, 52)
    apexRangeCounterFrame:SetFrameStrata("DIALOG")
    if createdFrame then apexRangeCounterFrame:Hide() end

    apexRangeCounterHeader = apexRangeCounterHeader or apexRangeCounterFrame._msufHeader
    if not apexRangeCounterHeader then
        apexRangeCounterHeader = apexRangeCounterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        apexRangeCounterFrame._msufHeader = apexRangeCounterHeader
        apexRangeCounterHeader:SetPoint("BOTTOM", apexRangeCounterFrame, "CENTER", 0, 3)
    end

    apexRangeCounterText = apexRangeCounterText or apexRangeCounterFrame._msufText
    if not apexRangeCounterText then
        apexRangeCounterText = apexRangeCounterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        apexRangeCounterFrame._msufText = apexRangeCounterText
        apexRangeCounterText:SetPoint("TOP", apexRangeCounterFrame, "CENTER", 0, -1)
    end

    ApplyApexRangeCounterStyle()
    apexRangeCounterHeader:SetText("NAMEPLATE RANGE - EVISCERATE 196819")
    return apexRangeCounterFrame
end

local function SetApexRangeCounterValues(plates, enemies, inRange, outOfRange, invalid)
    if not apexRangeCounterText then return end
    apexRangeCounterText:SetText(string_format(
        "PLATES %d   ENEMIES %d   IN %d   OUT %d   NIL %d",
        plates or 0, enemies or 0, inRange or 0, outOfRange or 0, invalid or 0))
end

local function SeedApexRangeCounterUnits()
    ClearApexRangeCounterUnits()
    if not (C_NamePlate and type(C_NamePlate.GetNamePlates) == "function") then return end
    local ok, nameplates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(nameplates) ~= "table" then return end
    for _, nameplate in pairs(nameplates) do
        local unitOK, unit = pcall(function()
            local getUnit = nameplate and nameplate.GetUnit
            if type(getUnit) == "function" then return getUnit(nameplate) end
        end)
        if unitOK and IsApexRangeCounterUnit(unit) then
            apexRangeCounterUnits[unit] = true
        end
    end
end

local ArmApexRangeCounterTimer
local function RunApexRangeCounterScan()
    apexRangeCounterScanPending = false
    if not ApexRangeCounterRuntimeActive() then
        CancelApexRangeCounterTimer()
        return
    end

    local g = GetGameplayDB()
    local diagnosticActive = apexRangeState.DiagnosticActive(g)
    local frame = diagnosticActive and EnsureApexRangeCounterFrame() or nil
    local previousSnapshotValid = apexRangeState.snapshotValid
    local previousInRangeEnemyCount = apexRangeState.inRangeEnemyCount
    local plates, enemies, inRange, invalid = 0, 0, 0, 0
    local issecretvalue = _G.issecretvalue
    local hasRangeAPI = C_Spell and type(C_Spell.IsSpellInRange) == "function"

    for unit in pairs(apexRangeCounterUnits) do
        local existsOK, exists = pcall(UnitExists, unit)
        local existsSecret = type(issecretvalue) == "function" and issecretvalue(exists) == true
        if not existsOK or existsSecret or exists ~= true then
            apexRangeCounterUnits[unit] = nil
        else
            plates = plates + 1
            local attackOK, canAttack = pcall(UnitCanAttack, "player", unit)
            local deadOK, isDead = pcall(UnitIsDeadOrGhost, unit)
            local attackSecret = type(issecretvalue) == "function" and issecretvalue(canAttack) == true
            local deadSecret = type(issecretvalue) == "function" and issecretvalue(isDead) == true
            if attackOK and deadOK and not attackSecret and not deadSecret
                and canAttack == true and isDead ~= true then
                enemies = enemies + 1
                local rangeOK, result
                if hasRangeAPI then
                    rangeOK, result = pcall(C_Spell.IsSpellInRange, EVISCERATE_SPELL_ID, unit)
                end
                local rangeSecret = type(issecretvalue) == "function" and issecretvalue(result) == true
                if not rangeOK or rangeSecret or result == nil then
                    invalid = invalid + 1
                elseif result == true or result == 1 then
                    inRange = inRange + 1
                end
            end
        end
    end

    local outOfRange = math_max(0, enemies - inRange - invalid)
    apexRangeState.snapshotValid = true
    apexRangeState.inRangeEnemyCount = inRange
    if diagnosticActive then
        SetApexRangeCounterValues(plates, enemies, inRange, outOfRange, invalid)
        frame:Show()
    end
    if not previousSnapshotValid or previousInRangeEnemyCount ~= inRange then
        RefreshApexItDevAura()
    elseif apexRangeState.sensorAction == "multiTarget" then
        -- Keep event/scan refreshes authoritative as well; the separate 0.05 s
        -- wake-up only shortens the protected five-second cooldown transition.
        apexRangeState.RefreshMultiTargetActionAlphas()
    end
    ArmApexRangeCounterTimer()
end

ArmApexRangeCounterTimer = function()
    CancelApexRangeCounterTimer()
    if not ApexRangeCounterRuntimeActive() or next(apexRangeCounterUnits) == nil then return end
    local generation = apexRangeCounterTimerGeneration
    local function OnTimer()
        if generation ~= apexRangeCounterTimerGeneration then return end
        apexRangeCounterTimer = nil
        RunApexRangeCounterScan()
    end
    if C_Timer and type(C_Timer.NewTimer) == "function" then
        apexRangeCounterTimer = C_Timer.NewTimer(APEX_RANGE_COUNTER_INTERVAL, OnTimer)
    elseif C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(APEX_RANGE_COUNTER_INTERVAL, OnTimer)
    end
end

apexRangeState.RequestScan = function()
    if not ApexRangeCounterRuntimeActive() then return end
    CancelApexRangeCounterTimer()
    if apexRangeCounterScanPending then return end
    apexRangeCounterScanPending = true
    local function Flush()
        apexRangeCounterScanPending = false
        RunApexRangeCounterScan()
    end
    if type(ScheduleOnce) == "function" then
        ScheduleOnce("MSUF_APEX_RANGE_COUNTER_SCAN", Flush)
    elseif C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, Flush)
    else
        Flush()
    end
end

local function EnsureApexRangeCounterEventFrame()
    if apexRangeCounterEventFrame then return apexRangeCounterEventFrame end
    apexRangeCounterEventFrame = CreateFrame("Frame")
    apexRangeCounterEventFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "NAME_PLATE_UNIT_ADDED" then
            if IsApexRangeCounterUnit(unit) then apexRangeCounterUnits[unit] = true end
            apexRangeState.InvalidateActionSnapshot()
            apexRangeState.RequestScan()
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            if IsApexRangeCounterUnit(unit) then apexRangeCounterUnits[unit] = nil end
            apexRangeState.InvalidateActionSnapshot()
            apexRangeState.RequestScan()
        elseif event == "PLAYER_ENTERING_WORLD" then
            SeedApexRangeCounterUnits()
            apexRangeState.InvalidateActionSnapshot()
            apexRangeState.RequestScan()
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            if ApplyApexRangeCounter then ApplyApexRangeCounter(GetGameplayDB()) end
        elseif event == "SPELL_RANGE_CHECK_UPDATE" or event == "ACTION_RANGE_CHECK_UPDATE" then
            -- Blizzard emits these when the current target crosses a native
            -- spell/action range boundary. Coalesce an immediate full snapshot;
            -- other nameplates remain covered by the bounded fallback cadence.
            apexRangeState.RequestScan()
        else
            apexRangeState.InvalidateActionSnapshot()
            apexRangeState.RequestScan()
        end
    end)
    return apexRangeCounterEventFrame
end

ApplyApexRangeCounter = function(g)
    g = g or GetGameplayDB() or {}
    local subtlety = IsSubtletyRogue()
    local targetDetectionEnabled = g.enableApexNameplateRangeDetection ~= false
    local diagnosticEnabled = targetDetectionEnabled and g.enableApexRangeCounter == true and subtlety
    local apexRangeEnabled = targetDetectionEnabled and g.enableApexItDevAura == true
        and subtlety and IsDeathstalkerActive()
    local wantFrame = diagnosticEnabled or apexRangeCounterPreviewActive
    local wantRoster = (diagnosticEnabled and not apexRangeCounterPreviewActive) or apexRangeEnabled
    local events = EnsureApexRangeCounterEventFrame()
    events:UnregisterAllEvents()
    CancelApexRangeCounterTimer()
    apexRangeCounterScanPending = false

    if not wantFrame and not wantRoster then
        ClearApexRangeCounterUnits()
        if apexRangeCounterFrame then apexRangeCounterFrame:Hide() end
        return
    end

    local frame
    if wantFrame then
        frame = EnsureApexRangeCounterFrame()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER",
            tonumber(g.apexRangeCounterOffsetX) or 0,
            tonumber(g.apexRangeCounterOffsetY) or 70)
        ApplyApexRangeCounterStyle()
    elseif apexRangeCounterFrame then
        apexRangeCounterFrame:Hide()
    end

    if apexRangeCounterPreviewActive then
        SetApexRangeCounterValues(6, 5, 4, 1, 0)
        frame:Show()
    end

    if wantRoster then
        events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("SPELLS_CHANGED")
        events:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")
        events:RegisterEvent("ACTION_RANGE_CHECK_UPDATE")
        SeedApexRangeCounterUnits()
        if ApexRangeCounterRuntimeActive() then
            RunApexRangeCounterScan()
        else
            RefreshApexItDevAura()
        end
    else
        ClearApexRangeCounterUnits()
    end
end

function MSUF.MSUF_Gameplay_ApexRangeCounter_SetPreview(enabled)
    apexRangeCounterPreviewActive = enabled == true
    ApplyApexRangeCounter(GetGameplayDB())
    return apexRangeCounterPreviewActive
end

function MSUF.MSUF_Gameplay_ApexRangeCounter_TogglePreview()
    return MSUF.MSUF_Gameplay_ApexRangeCounter_SetPreview(not apexRangeCounterPreviewActive)
end

function MSUF.MSUF_Gameplay_ApexRangeCounter_IsPreviewActive()
    return apexRangeCounterPreviewActive
end

local EnsureCombatStateText

ApplyCombatStateDynamicColor = function()
    if not stateText then EnsureCombatStateText() end

    if not stateText then return end
    local g = GetGameplayDB()
    local er, eg, eb, lr, lg, lb = MSUF_GetCombatStateColors(g)

    local st = stateText._msufLastState
    if st == "leave" then
        stateText:SetTextColor(lr, lg, lb, GlobalFontTextAlpha())
    else
        stateText:SetTextColor(er, eg, eb, GlobalFontTextAlpha())
    end
end

CombatStateOnEvent = function(event)
    local g = GetGameplayDB()
    if not g or not g.enableCombatStateText then
        CancelCombatStateClear()
        ReleaseGameplayKeyboardNudge(stateFrame)
        ClearCombatStateText()
        SetCombatStateClickThrough(false)
        return
    end

    local wantState = (g.enableCombatStateText == true)
    local duration = math_max(g.combatStateDuration or 1.5, 0.1)

    if event == "PLAYER_REGEN_DISABLED" then
        ReleaseGameplayKeyboardNudge(stateFrame)
        if not wantState then
            ClearCombatStateText()
            SetCombatStateClickThrough(false)
            return
        end
        if not stateText then EnsureCombatStateText() end
        local er, eg, eb = MSUF_GetCombatStateColors(g)
        ShowCombatStateText("enter", TextOrDefault(g.combatStateEnterText, "+Combat"), er, eg, eb, true)
        ScheduleCombatStateClear(duration)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not wantState then
            ClearCombatStateText()
            SetCombatStateClickThrough(false)
            return
        end
        if not stateText then EnsureCombatStateText() end
        local _er, _eg, _eb, lr, lg, lb = MSUF_GetCombatStateColors(g)
        ShowCombatStateText("leave", TextOrDefault(g.combatStateLeaveText, "-Combat"), lr, lg, lb, true)
        RefreshGameplayKeyboardNudge(stateFrame)
        ScheduleCombatStateClear(duration)
    end
end

EnsureCombatStateText = function()
    if stateText then return end

    local g = GetGameplayDB()

    if not stateFrame then
        stateFrame = CreateMovableGameplayFrame("MSUF_CombatStateFrame", 220, 60)
        local startX, startY = tonumber(g.combatStateOffsetX) or 0, tonumber(g.combatStateOffsetY) or 80
        stateFrame:SetPoint("CENTER", UIParent, "CENTER", startX, startY)
        stateFrame._msufAppliedPositionX = startX
        stateFrame._msufAppliedPositionY = startY
        SetupArrowNudge(stateFrame,
            function(self, dx, dy)
                local db = GameplayDefaults()
                if db.lockCombatState then return false end
                db.combatStateOffsetX = RoundInt((tonumber(db.combatStateOffsetX) or 0) + (dx or 0))
                db.combatStateOffsetY = RoundInt((tonumber(db.combatStateOffsetY) or 80) + (dy or 0))
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "CENTER", db.combatStateOffsetX, db.combatStateOffsetY)
                self._msufAppliedPositionX = db.combatStateOffsetX
                self._msufAppliedPositionY = db.combatStateOffsetY
                SyncGameplayPanel("MSUF_SyncCombatStateOffsetSliders")
                CheckpointHistory("Combat enter/leave position", "gameplay:combatState:position")
                return true
            end,
            function(self)
                local gd = GameplayDefaults()
                return gd.enableCombatStateText and not gd.lockCombatState and self.IsShown and self:IsShown()
            end)

        stateFrame:SetScript("OnDragStart", function(self)
            local gd = GameplayDefaults()
            if gd.lockCombatState then return end
            BeginGameplayDrag(self, "Combat enter/leave position", "gameplay:combatState:position")
        end)

        stateFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            self._msufDragging = nil

            local db = GameplayDefaults()
            StoreCenteredOffset(self, db, "combatStateOffsetX", "combatStateOffsetY")
            -- Re-anchor to the stored (rounded) offsets and sync the applied cache, otherwise the
            -- next ApplyCombatStatePosition sees stale values and snaps the frame back.
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", tonumber(db.combatStateOffsetX) or 0, tonumber(db.combatStateOffsetY) or 80)
            self._msufAppliedPositionX = tonumber(db.combatStateOffsetX) or 0
            self._msufAppliedPositionY = tonumber(db.combatStateOffsetY) or 80

            SyncGameplayPanel("MSUF_SyncCombatStateOffsetSliders")
            SelectNudgeFrame(self, true)
            CommitHistory(self)
        end)
    end

    stateText = stateFrame:CreateFontString("MSUF_CombatStateText", "OVERLAY")
    stateText:SetPoint("CENTER")

    local path, flags, r, gCol, bCol, size, useShadow = GetGameplayFont("state")
    ApplyGameplayFont(stateText, path, (size or 24), flags or "OUTLINE")
    local _er, _eg, _eb, lr, lg, lb = MSUF_GetCombatStateColors(g)
    stateText._msufLastState = "leave"
    stateText:SetTextColor(lr, lg, lb, GlobalFontTextAlpha())
    SetTextShadow(stateText, useShadow)

    ClearCombatStateText()
end

local function ApplyCombatStatePosition(g)
    if not stateFrame or stateFrame._msufDragging then return end
    g = g or GameplayDefaults()
    local x, y = tonumber(g.combatStateOffsetX) or 0, tonumber(g.combatStateOffsetY) or 80
    if stateFrame._msufAppliedPositionX == x and stateFrame._msufAppliedPositionY == y then return end
    stateFrame:ClearAllPoints()
    stateFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    stateFrame._msufAppliedPositionX = x
    stateFrame._msufAppliedPositionY = y
end

local function MSUF_ShouldCrosshairFollowCamera()
    if not GetCVar then return false end
    if (tonumber(GetCVar("findYourselfMode") or "0") or 0) > 0 then return true end

    if GetCVarBool and (
        GetCVarBool("findYourselfModeAll")
        or GetCVarBool("findYourselfModeAlways")
        or GetCVarBool("findYourselfModeCombat")
        or GetCVarBool("nameplateShowSelf")
        or GetCVarBool("nameplateShowAll")) then
        return true
    end

    local personal = _G.NamePlatePersonalFrame
    return personal and personal.IsShown and personal:IsShown() or false
end

local function AnchorCombatCrosshair()
    if not crosshairFrame then return end

    local parent   = UIParent
    local anchorTo = UIParent
    local offsetY  = -20

    if MSUF_ShouldCrosshairFollowCamera() then
        local personal = _G.NamePlatePersonalFrame
        if personal then
            parent   = personal
            anchorTo = personal.UnitFrame or personal

            local zoom = GetCameraZoom and GetCameraZoom() or 0
            local maxFactor = tonumber(GetCVar and GetCVar("cameraDistanceMaxZoomFactor") or "1") or 1
            local maxDist = 15 * maxFactor

            local close = maxDist > 0 and (1 - math_min(zoom / maxDist, 1)) or 0
            local base = (personal:GetHeight() or 0) * 0.6
            offsetY = -(base + base * 0.6 * close)
        end
    end

    if crosshairFrame._msufAnchorParent ~= parent
        or crosshairFrame._msufAnchorTo ~= anchorTo
        or crosshairFrame._msufAnchorOffsetX ~= 0
        or crosshairFrame._msufAnchorOffsetY ~= offsetY then

        crosshairFrame._msufAnchorParent = parent
        crosshairFrame._msufAnchorTo = anchorTo
        crosshairFrame._msufAnchorOffsetX = 0
        crosshairFrame._msufAnchorOffsetY = offsetY

        crosshairFrame:ClearAllPoints()
        crosshairFrame:SetParent(parent)
        crosshairFrame:SetPoint("CENTER", anchorTo, "CENTER", 0, offsetY)
    end
end

local UpdateCrosshairRangeColor

local function ScheduleCombatCrosshairAnchor()
    if not crosshairFrame or crosshairFrame._msufAnchorPending then return end
    crosshairFrame._msufAnchorPending = true
    C_Timer.After(0, function()
        if crosshairFrame then crosshairFrame._msufAnchorPending = nil end
        AnchorCombatCrosshair()
    end)
end

local function InstallCombatCrosshairZoomHooks()
    if crosshairZoomHooksInstalled or type(_G.hooksecurefunc) ~= "function" then return end
    crosshairZoomHooksInstalled = true
    local function CameraZoomChanged()
        local g = GetGameplayDB()
        if g and g.enableCombatCrosshair == true and MSUF_ShouldCrosshairFollowCamera() then
            ScheduleCombatCrosshairAnchor()
        end
    end
    for _, name in ipairs({ "CameraZoomIn", "CameraZoomOut" }) do
        if type(_G[name]) == "function" then _G.hooksecurefunc(name, CameraZoomChanged) end
    end
end

local function EnsureCombatCrosshair()
    local g = GameplayDefaults()
    InstallCombatCrosshairZoomHooks()

    if not crosshairFrame then
        crosshairFrame = CreateFrame("Frame", "MSUF_CombatCrosshairFrame", UIParent)
        crosshairFrame:SetSize(40, 40)
        AnchorCombatCrosshair()
        crosshairFrame:SetFrameStrata("BACKGROUND")
        crosshairFrame:SetClampedToScreen(true)
        crosshairFrame:EnableMouse(false)

        local horiz = crosshairFrame:CreateTexture(nil, "ARTWORK")
        horiz:SetPoint("CENTER")

        local vert = crosshairFrame:CreateTexture(nil, "ARTWORK")
        vert:SetPoint("CENTER")

        crosshairFrame.horiz = horiz
        crosshairFrame.vert  = vert

        crosshairFrame:Hide()

        if not crosshairEventFrame then
            crosshairEventFrame = CreateFrame("Frame", "MSUF_CombatCrosshairEventFrame", UIParent)
            crosshairEventFrame:UnregisterAllEvents()

            local function MSUF_CombatCrosshair_OnEvent(_, event, ...)
                local arg1 = ...
                local g2 = GetGameplayDB()
                if not g2.enableCombatCrosshair then
                    crosshairFrame:Hide()
                    return
                end

                if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
                    crosshairFrame:SetShown(event == "PLAYER_REGEN_DISABLED")
                    RequestCrosshairRangeRefresh()
                elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" then
                    AnchorCombatCrosshair()
                    crosshairFrame:SetShown((UnitAffectingCombat and UnitAffectingCombat("player")) or (_G.MSUF_InCombat == true))
                    RequestCrosshairRangeRefresh()
                elseif (event == "NAME_PLATE_UNIT_REMOVED" and arg1 == "player") or event == "DISPLAY_SIZE_CHANGED" then
                    AnchorCombatCrosshair()
                elseif event == "SPELL_RANGE_CHECK_UPDATE" then
                    RequestCrosshairRangeRefresh()
                elseif event == "CVAR_UPDATE" and (arg1 == "nameplateShowSelf" or arg1 == "cameraDistanceMaxZoomFactor") then
                    ScheduleCombatCrosshairAnchor()
                end
            end

            crosshairEventFrame:SetScript("OnEvent", MSUF_CombatCrosshair_OnEvent)
        end
    end

    local thickness = Clamp(g.crosshairThickness or 2, 1, 10)
    local size = Clamp(g.crosshairSize or 40, 20, 80)

    if crosshairFrame and crosshairFrame._msufLastSize ~= size then
        crosshairFrame._msufLastSize = size
        crosshairFrame:SetSize(size, size)
    end

    if crosshairFrame.horiz and crosshairFrame.vert then
        if crosshairFrame._msufLastThickness ~= thickness or crosshairFrame._msufLastSizeForLines ~= size then
            crosshairFrame._msufLastThickness = thickness
            crosshairFrame._msufLastSizeForLines = size
            crosshairFrame.horiz:SetSize(size, thickness)
            crosshairFrame.vert:SetSize(thickness, size)
        end

        SyncCrosshairRangeCache(g)
        UpdateCrosshairRangeColor()

        RequestCrosshairRangeRefresh()
    end

    return crosshairFrame
end

local function ApplyLockState()
    local g = GameplayDefaults()
    if combatFrame then
        SetAltDragMouse(combatFrame, g.enableCombatTimer, g.lockCombatTimer, g.combatTimerClickThrough)
        RefreshGameplayKeyboardNudge(combatFrame)
    end

    if stateFrame then
        if stateFrame._msufClickThroughActive then
            stateFrame:EnableMouse(false)
        elseif g.lockCombatState then
            stateFrame:EnableMouse(false)
        elseif stateText and stateText:IsShown() then
            stateFrame:EnableMouse(true)
        else
            stateFrame:EnableMouse(false)
        end
        RefreshGameplayKeyboardNudge(stateFrame)
    end
end

local function ValidateCombatTimerAnchor(v)
    if v == "player" or v == "target" or v == "focus" then
        return v
    end
    return "none"
end

local function GetCombatTimerAnchorFrame(g)
    local key = ValidateCombatTimerAnchor(g and g.combatTimerAnchor)
    if key == "none" then
        return UIParent
    end
    local uf = MSUF and MSUF.UF
    local frame = uf and type(uf.GetFrame) == "function" and uf.GetFrame(key) or nil
    local list = uf and uf.frames
    return frame or (list and list[key]) or (_G and _G["MSUF_" .. key]) or UIParent
end

local function ApplyCombatTimerAnchor(g)
    if not combatFrame then return end

    if combatFrame._msufDragging then return end

    g = g or GameplayDefaults()
    local anchor = GetCombatTimerAnchorFrame(g)
    local x, y = tonumber(g.combatOffsetX) or 0, tonumber(g.combatOffsetY) or 0

    if combatFrame._msufAppliedAnchor ~= anchor
        or combatFrame._msufAppliedPositionX ~= x
        or combatFrame._msufAppliedPositionY ~= y
    then
        combatFrame:ClearAllPoints()
        combatFrame:SetPoint("CENTER", anchor, "CENTER", x, y)
        combatFrame._msufAppliedAnchor = anchor
        combatFrame._msufAppliedPositionX = x
        combatFrame._msufAppliedPositionY = y
    end

    local want = ValidateCombatTimerAnchor(g.combatTimerAnchor)
    if want ~= "none" and anchor == UIParent then
        if not combatFrame._msufAnchorRetryPending then
            combatFrame._msufAnchorRetryPending = true
            C_Timer.After(0.2, function()
                if combatFrame then
                    combatFrame._msufAnchorRetryPending = nil
                    ApplyCombatTimerAnchor()
                end
            end)
        end
    end
end

MSUF.MSUF_ApplyGameplayFontFromGlobal = ApplyFontToCounter

local function CreateCombatTimerFrame()
    if combatFrame then
        return combatFrame
    end

    local g = GameplayDefaults()

    combatFrame = CreateMovableGameplayFrame("MSUF_CombatTimerFrame", 220, 60)
    ApplyCombatTimerAnchor(g)
    SetupArrowNudge(combatFrame,
        function(self, dx, dy)
            local db = GameplayDefaults()
            if db.lockCombatTimer then return false end
            db.combatOffsetX = Clamp(RoundInt((tonumber(db.combatOffsetX) or 0) + (dx or 0)), -800, 800)
            db.combatOffsetY = Clamp(RoundInt((tonumber(db.combatOffsetY) or 0) + (dy or 0)), -800, 800)
            ApplyCombatTimerAnchor(db)
            TickCombatTimer()
            SyncGameplayPanel("MSUF_SyncCombatTimerOffsetSliders")
            ApplyLockState()
            CheckpointHistory("Combat timer position", "gameplay:combatTimer:position")
            return true
        end,
        function(self)
            local gd = GameplayDefaults()
            return gd.enableCombatTimer and not gd.lockCombatTimer and self.IsShown and self:IsShown()
        end)

    combatFrame:SetScript("OnDragStart", function(self)
        local gd = GameplayDefaults()
        if CanAltDrag(gd, "lockCombatTimer", "combatTimerClickThrough") then
            BeginGameplayDrag(self, "Combat timer position", "gameplay:combatTimer:position")
        end
    end)

    combatFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self._msufDragging = nil

        local db = GameplayDefaults()
        local anchorFrame = GetCombatTimerAnchorFrame(db)
        StoreCenteredOffset(self, db, "combatOffsetX", "combatOffsetY", anchorFrame)
        -- Re-anchor to the stored offsets and sync the applied cache so the next apply does not
        -- re-anchor (and visibly jump) from stale cached values.
        self:ClearAllPoints()
        self:SetPoint("CENTER", anchorFrame, "CENTER", tonumber(db.combatOffsetX) or 0, tonumber(db.combatOffsetY) or 0)
        self._msufAppliedAnchor = anchorFrame
        self._msufAppliedPositionX = tonumber(db.combatOffsetX) or 0
        self._msufAppliedPositionY = tonumber(db.combatOffsetY) or 0

        SyncGameplayPanel("MSUF_SyncCombatTimerOffsetSliders")

        SelectNudgeFrame(self, true)
        ApplyLockState()
        CommitHistory(self)
    end)

    timerText = combatFrame:CreateFontString(nil, "OVERLAY")
    timerText:SetPoint("CENTER")

    ApplyFontToCounter()
    timerText:SetText("")

    ApplyLockState()

    EnsureAltDragWatcher("_MSUF_CombatTimerModifierFrame", combatFrame, "enableCombatTimer", "lockCombatTimer", "combatTimerClickThrough", true)

    return combatFrame
end

local MSUF_LastEnabledMeleeRangeSpellID = 0
local MSUF_LastEnabledMeleeRangeSpellID_Override = 0

local function GetOverrideSpellID(spellID)
    if not (C_Spell and C_Spell.GetOverrideSpell) then
        return 0
    end
    local overrideID = C_Spell.GetOverrideSpell(spellID)
    if type(overrideID) == "number" and overrideID > 0 and overrideID ~= spellID then
        return overrideID
    end
    return 0
end

local function SetEnabledMeleeRangeCheck(spellID)
    if not (C_Spell and C_Spell.EnableSpellRangeCheck) then return end

    spellID = tonumber(spellID) or 0
    local overrideID = 0
    if spellID > 0 then
        overrideID = GetOverrideSpellID(spellID)
    end

    if spellID == MSUF_LastEnabledMeleeRangeSpellID and overrideID == MSUF_LastEnabledMeleeRangeSpellID_Override then return end

    if MSUF_LastEnabledMeleeRangeSpellID_Override > 0 then C_Spell.EnableSpellRangeCheck(MSUF_LastEnabledMeleeRangeSpellID_Override, false) end
    if MSUF_LastEnabledMeleeRangeSpellID > 0 then C_Spell.EnableSpellRangeCheck(MSUF_LastEnabledMeleeRangeSpellID, false) end

    MSUF_LastEnabledMeleeRangeSpellID = spellID
    MSUF_LastEnabledMeleeRangeSpellID_Override = overrideID

    if spellID > 0 then C_Spell.EnableSpellRangeCheck(spellID, true) end
    if overrideID > 0 then C_Spell.EnableSpellRangeCheck(overrideID, true) end
end

local function IsUnitInMeleeRange(unit, spellID)
    spellID = tonumber(spellID) or 0
    if spellID <= 0 then
        return false
    end
    if not (C_Spell and C_Spell.IsSpellInRange) then
        return false
    end

    local overrideID = GetOverrideSpellID(spellID)
    if overrideID and overrideID > 0 then
        local okOverride = C_Spell.IsSpellInRange(overrideID, unit)
        if okOverride == true or okOverride == 1 then
            return true
        end
    end

    local ok = C_Spell.IsSpellInRange(spellID, unit)
    return ok == true or ok == 1
end

local function CrosshairHasValidTarget()
    return UnitExists and UnitExists("target")
        and UnitCanAttack and UnitCanAttack("player", "target")
        and UnitIsDeadOrGhost and (not UnitIsDeadOrGhost("target"))
end

local function DisableCrosshairRangeCheck()
    if not crosshairFrame then return end
    local lastEnabled = crosshairFrame._msufRangeCheckEnabledSpellID or 0
    if lastEnabled > 0 then
        SetEnabledMeleeRangeCheck(0)
        crosshairFrame._msufRangeCheckEnabledSpellID = 0
    end
end

local function RunCrosshairRangeRefresh()
    MSUF._MSUF_CrosshairRangeRefreshPending = nil

    if not crosshairFrame or not crosshairFrame.IsShown or (not crosshairFrame:IsShown()) then
        DisableCrosshairRangeCheck()
        return
    end

    UpdateCrosshairRangeColor()
end

RequestCrosshairRangeRefresh = function()
    if MSUF._MSUF_CrosshairRangeRefreshPending then return end
    if not crosshairFrame or not crosshairFrame:IsShown() then
        DisableCrosshairRangeCheck()
        return
    end
    MSUF._MSUF_CrosshairRangeRefreshPending = true
    C_Timer.After(0, RunCrosshairRangeRefresh)
end

UpdateCrosshairRangeColor = function()
    local f = crosshairFrame
    if not f or not f.horiz or not f.vert or not f._msufCrosshairEnabled then return end

    local spellID = f._msufRangeSpellID or 0
    local checkingRange = f._msufUseRangeColor and spellID > 0 and CrosshairHasValidTarget()
    local desiredInRange
    if checkingRange then
        local lastEnabled = f._msufRangeCheckEnabledSpellID or 0
        if lastEnabled ~= spellID then
            SetEnabledMeleeRangeCheck(spellID)
            f._msufRangeCheckEnabledSpellID = spellID
        end
        desiredInRange = IsUnitInMeleeRange("target", spellID)
    else
        DisableCrosshairRangeCheck()
    end

    local desiredMode = checkingRange and spellID or 0
    local lastMode = f._msufLastRangeMode
    local lastInRange = f._msufLastInRange

    if desiredMode ~= lastMode or (checkingRange and desiredInRange ~= lastInRange) then
        local r, g, b = f._msufInRangeR or 0, f._msufInRangeG or 1, f._msufInRangeB or 0
        if checkingRange and desiredInRange == false then
            r, g, b = f._msufOutRangeR or 1, f._msufOutRangeG or 0, f._msufOutRangeB or 0
        end
        f.horiz:SetColorTexture(r, g, b, 0.9)
        f.vert:SetColorTexture(r, g, b, 0.9)

        f._msufLastRangeMode = desiredMode
        f._msufLastInRange = checkingRange and desiredInRange or nil
    end
end

local function ApplyCombatStateText(g)
    local wantState = (g.enableCombatStateText == true)

    if wantState then
        EnsureCombatStateText()
    end

    if wantState then
        BusRegister("PLAYER_REGEN_DISABLED", "MSUF_COMBAT_STATE", CombatStateOnEvent)
        BusRegister("PLAYER_REGEN_ENABLED", "MSUF_COMBAT_STATE", CombatStateOnEvent)
    else
        BusUnregister("PLAYER_REGEN_DISABLED", "MSUF_COMBAT_STATE")
        BusUnregister("PLAYER_REGEN_ENABLED", "MSUF_COMBAT_STATE")
    end

    if wantState then
        SetCombatStateClickThrough(false)
        ApplyCombatStatePosition(g)

        if not g.lockCombatState and stateText then
            local er, eg, eb = MSUF_GetCombatStateColors(g)
            ShowCombatStateText("enter", TextOrDefault(g.combatStateEnterText, "+Combat"), er, eg, eb, false)
        elseif stateText then
            ClearCombatStateText()
            stateFrame:Hide()
        end
    else
        CancelCombatStateClear()
        ClearCombatStateText()
        SetCombatStateClickThrough(false)
    end
end

local function ApplyCombatCrosshair(g)

    if g.enableCombatCrosshair then
        local frame = EnsureCombatCrosshair()
        SyncCrosshairRangeCache(g)
        crosshairEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        crosshairEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        crosshairEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        crosshairEventFrame:RegisterEvent("PLAYER_LOGIN")
        BusRegister("PLAYER_TARGET_CHANGED", "MSUF_CROSSHAIR", RequestCrosshairRangeRefresh)
        if crosshairFrame._msufUseRangeColor then
            crosshairEventFrame:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")
        else
            crosshairEventFrame:UnregisterEvent("SPELL_RANGE_CHECK_UPDATE")
        end
        crosshairEventFrame:RegisterEvent("CVAR_UPDATE")
        crosshairEventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")

        frame:SetShown((UnitAffectingCombat and UnitAffectingCombat("player")) or (_G.MSUF_InCombat == true))
        RequestCrosshairRangeRefresh()
    else
        if crosshairEventFrame then
            crosshairEventFrame:UnregisterAllEvents()
        end
        BusUnregister("PLAYER_TARGET_CHANGED", "MSUF_CROSSHAIR")

        DisableCrosshairRangeCheck()

        if crosshairFrame then
            crosshairFrame:Hide()
        end
    end
end

local function ApplyCombatTimer(g)
    if g.enableCombatTimer and not combatFrame then
        CreateCombatTimerFrame()
    end

    ApplyFontToCounter()
    ApplyLockState()
    if combatFrame then
        ApplyCombatTimerAnchor(g)
        combatFrame:SetShown(g.enableCombatTimer)
        EnsureAltDragWatcher("_MSUF_CombatTimerModifierFrame", combatFrame, "enableCombatTimer", "lockCombatTimer", "combatTimerClickThrough", g.enableCombatTimer == true)
    end
end

local function MSUF_CombatTimer_OnRegenDisabled()
    local gd = GetGameplayDB()
    if not gd or not gd.enableCombatTimer then return end
    ReleaseGameplayKeyboardNudge(combatFrame)
    combatStartTime = GetTime()
    lastTimerText = ""
    TickCombatTimer()
    ApplyLockState()
    _StartCombatTimerTick()
end

local function MSUF_CombatTimer_OnRegenEnabled()
    local gd = GetGameplayDB()
    if not gd or not gd.enableCombatTimer then return end
    _StopCombatTimerTick()
    combatStartTime = nil
    lastTimerText = ""
    TickCombatTimer()
end

local function MSUF_CombatTimer_OnEnteringWorld()
    local gd = GetGameplayDB()
    if not gd or not gd.enableCombatTimer then return end
    lastTimerText = ""
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        ReleaseGameplayKeyboardNudge(combatFrame)
        if not combatStartTime then
            combatStartTime = GetTime()
        end
        TickCombatTimer()
        _StartCombatTimerTick()
    else
        _StopCombatTimerTick()
        combatStartTime = nil
    end
    ApplyLockState()
    TickCombatTimer()
end

local function UnregisterGameplayEventBus(timer, state)
    if timer then
        BusUnregister("PLAYER_REGEN_DISABLED", "MSUF_COMBAT_TIMER")
        BusUnregister("PLAYER_REGEN_ENABLED", "MSUF_COMBAT_TIMER")
        BusUnregister("PLAYER_ENTERING_WORLD", "MSUF_COMBAT_TIMER")
    end
    if state then
        BusUnregister("PLAYER_REGEN_DISABLED", "MSUF_COMBAT_STATE")
        BusUnregister("PLAYER_REGEN_ENABLED", "MSUF_COMBAT_STATE")
    end
end

ApplyGameplayNow = function()
    local g = GameplayDefaults()

    ApplyCombatTimer(g)
    ApplyCombatStateText(g)
    ApplyCombatCrosshair(g)
    ApplyApexItDevAura(g)
    ApplyApexRangeCounter(g)
    local applyTotems = MSUF.MSUF_Gameplay_PlayerTotems_Apply
    if applyTotems then applyTotems(g) end

    UnregisterGameplayEventBus(true, false)
    _StopCombatTimerTick()

    if g.enableCombatTimer then
        BusRegister("PLAYER_REGEN_DISABLED", "MSUF_COMBAT_TIMER", MSUF_CombatTimer_OnRegenDisabled)
        BusRegister("PLAYER_REGEN_ENABLED", "MSUF_COMBAT_TIMER", MSUF_CombatTimer_OnRegenEnabled)
        BusRegister("PLAYER_ENTERING_WORLD", "MSUF_COMBAT_TIMER", MSUF_CombatTimer_OnEnteringWorld)

        if UnitAffectingCombat and UnitAffectingCombat("player") then
            if not combatStartTime then
                combatStartTime = GetTime()
            end
            lastTimerText = ""
            TickCombatTimer()
            _StartCombatTimerTick()
        else
            -- Out of combat the tick never runs on its own, so enabling or unlocking the timer
            -- from the menu would leave it invisible; the tick paints the movable 0:00 placeholder.
            TickCombatTimer()
        end
    else
        combatStartTime = nil
        lastTimerText = ""
    end
    if SyncGameplaySpecEvents then SyncGameplaySpecEvents(g) end
    local gameplay = MSUF.Gameplay
    if gameplay and type(gameplay.SyncNudgeEvents) == "function" then gameplay.SyncNudgeEvents() end
end

MSUF.MSUF_ApplyGameplayVisuals = ApplyGameplayNow

MSUF.MSUF_GameplayShared = MSUF.MSUF_GameplayShared or {}
do
    local S = MSUF.MSUF_GameplayShared
    S.EnsureGameplayDefaults = GameplayDefaults
    S.GetPlayerSpecID = GetPlayerSpecID
    S.Clamp = Clamp
    S.RoundInt = RoundInt
    S.SetupArrowNudge = SetupArrowNudge
    S.BeginHistory = BeginHistory
    S.CommitHistory = CommitHistory
    S.CheckpointHistory = CheckpointHistory
    S.SelectNudgeFrame = SelectNudgeFrame
end

do
    local meleeCache = {}
    MSUF.MSUF_GetCombatTimerFrame = function() return combatFrame end
    MSUF.MSUF_Gameplay_ApplyFontToCounter = ApplyFontToCounter
    MSUF.MSUF_Gameplay_ApplyLockState = ApplyLockState
    MSUF.MSUF_Gameplay_ApplyCombatTimerAnchorFn = ApplyCombatTimerAnchor
    MSUF.MSUF_Gameplay_ApplyCombatStatePosition = ApplyCombatStatePosition
    MSUF.MSUF_Gameplay_TickCombatTimer = TickCombatTimer
    MSUF.MSUF_GetCombatTimerAnchorFrame = GetCombatTimerAnchorFrame
    MSUF.MSUF_SetEnabledMeleeRangeCheck = SetEnabledMeleeRangeCheck
    MSUF.MSUF_BuildMeleeSpellCache = function() end
    MSUF.MSUF_GetMeleeSpellCache = function() return meleeCache end
end

do
    local _specChangeFrame = CreateFrame("Frame")
    _specChangeFrame:SetScript("OnEvent", function()
        if MSUF.MSUF_RequestGameplayApply then MSUF.MSUF_RequestGameplayApply() end
    end)
    SyncGameplaySpecEvents = function(g)
        g = g or GetGameplayDB()
        local wanted = g and (g.enableCombatTimer == true
            or g.enableCombatStateText == true
            or g.enableCombatCrosshair == true
            or g.enableApexItDevAura == true
            or g.enableApexRangeCounter == true
            or g.enableShadowTechniquesStackHighlight == true
            or g.enablePlayerTotems == true)
        _specChangeFrame:UnregisterAllEvents()
        if wanted then _specChangeFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED") end
        return wanted == true
    end
end

do
    local didApply = false

    local function AutoApplyOnce()
        if didApply then return end
        didApply = true

        if type(MSUF.MSUF_RequestGameplayApply) == "function" then
            ExportPublic("MSUF_RequestGameplayApply", MSUF.MSUF_RequestGameplayApply)
        end
        if type(GameplayDefaults) == "function" then GameplayDefaults() end
        if MSUF.MSUF_RequestGameplayApply then MSUF.MSUF_RequestGameplayApply() end
    end

    C_Timer.After(0, AutoApplyOnce)

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function()
        AutoApplyOnce()
        f:UnregisterAllEvents()
        f:SetScript("OnEvent", nil)
    end)
end

local function StopGameplayModule()
    _StopCombatTimerTick()
    UnregisterGameplayEventBus(true, true)
    apexItPreviewActive = false
    ApplyApexItDevAura({})
    apexRangeCounterPreviewActive = false
    ApplyApexRangeCounter({})
    if SyncGameplaySpecEvents then SyncGameplaySpecEvents({}) end
    local modifierFrame = MSUF._MSUF_CombatTimerModifierFrame
    if modifierFrame then modifierFrame:UnregisterAllEvents() end
    local gameplay = MSUF.Gameplay
    if gameplay and type(gameplay.SyncNudgeEvents) == "function" then gameplay.SyncNudgeEvents() end
end

local function IsGameplayModuleEnabled()
    local g = GetGameplayDB()
    return g and (g.enableCombatTimer == true
        or g.enableCombatStateText == true
        or g.enableCombatCrosshair == true
        or g.enableApexItDevAura == true
        or g.enableApexRangeCounter == true
        or g.enableShadowTechniquesStackHighlight == true
        or g.enablePlayerTotems == true
        or apexItPreviewActive
        or apexRangeCounterPreviewActive) or false
end

local reg = RegisterModule or _G.MSUF_RegisterModule
if type(reg) == "function" then
    reg("Gameplay", {
        order = 50,
        IsEnabled = IsGameplayModuleEnabled,
        Init = GameplayDefaults,
        Enable = MSUF.MSUF_RequestGameplayApply,
        Disable = StopGameplayModule,
        RefreshSettings = MSUF.MSUF_RequestGameplayApply,
        Shutdown = StopGameplayModule,
    })
end
