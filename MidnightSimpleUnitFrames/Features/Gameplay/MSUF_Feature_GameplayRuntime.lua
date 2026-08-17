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
local UnitExists    = UnitExists
local UnitCanAttack = UnitCanAttack
local GetTime             = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local string_format       = string.format
local GetCVar    = GetCVar
local GetCVarBool = GetCVarBool
local math_min     = math.min
local math_max     = math.max
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
        if ApplyGameplayNow then ApplyGameplayNow() end
        _applyPending = false
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

local function ApplyFontToCounter()
    if not timerText and not stateText then return end
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
        or g.enablePlayerTotems == true) or false
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
