local _, MSUF = ...
MSUF = MSUF or {}

local Gameplay = MSUF.Gameplay or {}
MSUF.Gameplay = Gameplay

-- Shared gameplay helper bundle.
-- Provides spec lookup, clamping, nudge/history helpers, and lightweight predicates used by
-- gameplay config, runtime, and preview modules. It only creates a shared nudge event guard.
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UnitAffectingCombat = UnitAffectingCombat
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local GetCurrentKeyBoardFocus = GetCurrentKeyBoardFocus
local tonumber = tonumber
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo

local function MSUF_Gameplay_GetPlayerSpecID()
    -- Spec lookup can be nil during early login/reload. Callers use the cached helper when
    -- they need stable behavior between spec-update events.
    if not GetSpecialization then return nil end
    local specIndex = GetSpecialization()
    if not specIndex or specIndex <= 0 then return nil end
    if not GetSpecializationInfo then return nil end
    local specID = GetSpecializationInfo(specIndex)
    if not specID or specID <= 0 then return nil end
    return specID
end

local _MSUF_Clamp = _G._MSUF_Clamp
if not _MSUF_Clamp then
    _MSUF_Clamp = function(v, mn, mx)
        v = tonumber(v)
        if not v then
            return mn
        end
        if v < mn then
            return mn
        end
        if v > mx then
            return mx
        end
        return v
    end
    _G._MSUF_Clamp = _MSUF_Clamp
end

local _MSUF_RoundInt = _G._MSUF_RoundInt
if not _MSUF_RoundInt then
    _MSUF_RoundInt = function(v)
        v = tonumber(v)
        if not v then
            return 0
        end
        if v >= 0 then
            return math.floor(v + 0.5)
        end
        return math.ceil(v - 0.5)
    end
    _G._MSUF_RoundInt = _MSUF_RoundInt
end

local gameplayNudgeSelection
local gameplayNudgeFrames = setmetatable({}, { __mode = "k" })
local gameplayNudgeEventFrame

local function MSUF_Gameplay_IsTextInputFocused()
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    return focus and focus.IsObjectType and focus:IsObjectType("EditBox")
end

local function MSUF_Gameplay_GetNudgeStep()
    if IsControlKeyDown and IsControlKeyDown() then return 10 end
    if IsShiftKeyDown and IsShiftKeyDown() then return 5 end
    return 1
end

local function MSUF_Gameplay_CheckpointHistory(label, source)
    local h = _G.MSUF2
    local checkpoint = h and h.CheckpointHistory
    if type(checkpoint) ~= "function" then return false end
    return checkpoint(label or "Gameplay position", source or "gameplay:position") or false
end

local function MSUF_Gameplay_BeginHistory(frame, label, source)
    local h = _G.MSUF2
    local begin = h and h.BeginHistoryTransaction
    if not (frame and type(begin) == "function") then return false end
    if begin(label or "Gameplay position", source or "gameplay:position") then
        frame._msufGameplayHistoryTransaction = true
        return true
    end
    return false
end

local function MSUF_Gameplay_CommitHistory(frame)
    if not (frame and frame._msufGameplayHistoryTransaction) then return false end
    frame._msufGameplayHistoryTransaction = nil
    local h = _G.MSUF2
    local commit = h and h.CommitHistoryTransaction
    if type(commit) ~= "function" then return false end
    return commit() or false
end

local function MSUF_Gameplay_SelectNudgeFrame(frame, selected)
    if selected and gameplayNudgeSelection and gameplayNudgeSelection ~= frame then
        MSUF_Gameplay_SelectNudgeFrame(gameplayNudgeSelection, false)
    end

    if selected then
        gameplayNudgeSelection = frame
    elseif gameplayNudgeSelection == frame then
        gameplayNudgeSelection = nil
    end

    if frame then
        if frame._msufGameplayNudgeBorder then
            frame._msufGameplayNudgeBorder:SetShown(selected and true or false)
        end
        if frame._msufGameplayUpdateKeyboardNudge then
            frame:_msufGameplayUpdateKeyboardNudge()
        end
    end
    if type(Gameplay.SyncNudgeEvents) == "function" then Gameplay.SyncNudgeEvents() end
end

local function MSUF_Gameplay_IsCombatInputLocked()
    return ((InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player"))
        or (_G.MSUF_InCombat == true)) and true or false
end

local function MSUF_Gameplay_SetKeyboardNudgeEnabled(frame, enabled)
    if not frame or not frame.EnableKeyboard then return end

    if enabled then
        if frame.SetPropagateKeyboardInput then
            frame:SetPropagateKeyboardInput(true)
        end
        frame:EnableKeyboard(true)
        return
    end

    if frame.SetPropagateKeyboardInput and not (InCombatLockdown and InCombatLockdown()) then
        frame:SetPropagateKeyboardInput(true)
    end
    frame:EnableKeyboard(false)
end

local function MSUF_Gameplay_ShouldEnableKeyboardNudge(frame)
    if not frame or gameplayNudgeSelection ~= frame then return false end
    if MSUF_Gameplay_IsCombatInputLocked() then return false end
    if frame.IsShown and not frame:IsShown() then return false end

    local can = frame._msufGameplayCanNudgeFn
    if type(can) == "function" and not can(frame) then return false end
    return true
end

local function MSUF_Gameplay_RefreshKeyboardNudge(frame)
    MSUF_Gameplay_SetKeyboardNudgeEnabled(frame, MSUF_Gameplay_ShouldEnableKeyboardNudge(frame))
end

local function MSUF_Gameplay_ReleaseKeyboardNudge(frame)
    if frame and gameplayNudgeSelection == frame then
        gameplayNudgeSelection = nil
    end
    if frame and frame._msufGameplayNudgeBorder then
        frame._msufGameplayNudgeBorder:Hide()
    end
    MSUF_Gameplay_SetKeyboardNudgeEnabled(frame, false)
end

local function MSUF_Gameplay_SyncNudgeEvents()
    local wanted = false
    for frame in pairs(gameplayNudgeFrames) do
        local can = frame and frame._msufGameplayCanNudgeFn
        if type(can) == "function" and can(frame) then
            wanted = true
            break
        end
    end
    if not wanted then
        if gameplayNudgeEventFrame then gameplayNudgeEventFrame:UnregisterAllEvents() end
        return false
    end
    if not gameplayNudgeEventFrame then
        if not CreateFrame then return false end
        gameplayNudgeEventFrame = CreateFrame("Frame")
        gameplayNudgeEventFrame:SetScript("OnEvent", function()
            local locked = MSUF_Gameplay_IsCombatInputLocked()
            for frame in pairs(gameplayNudgeFrames) do
                if locked then
                    MSUF_Gameplay_ReleaseKeyboardNudge(frame)
                else
                    MSUF_Gameplay_RefreshKeyboardNudge(frame)
                end
            end
        end)
    end
    gameplayNudgeEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    gameplayNudgeEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    gameplayNudgeEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    return true
end

local function MSUF_Gameplay_EnableKeyboardNudge(frame)
    MSUF_Gameplay_RefreshKeyboardNudge(frame)
end

local function MSUF_Gameplay_SetupArrowNudge(frame, nudgeFn, canNudgeFn)
    if not frame or frame._msufGameplayArrowNudgeSetup then return end
    frame._msufGameplayArrowNudgeSetup = true
    frame._msufGameplayNudgeFn = nudgeFn
    frame._msufGameplayCanNudgeFn = canNudgeFn
    frame._msufGameplayUpdateKeyboardNudge = MSUF_Gameplay_RefreshKeyboardNudge
    frame._msufGameplayReleaseKeyboardNudge = MSUF_Gameplay_ReleaseKeyboardNudge
    gameplayNudgeFrames[frame] = true
    MSUF_Gameplay_SyncNudgeEvents()

    MSUF_Gameplay_EnableKeyboardNudge(frame)

    local border = frame:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", frame, "TOPLEFT", -3, 3)
    border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 3, -3)
    border:SetColorTexture(0.27, 0.53, 0.80, 0.40)
    border:Hide()
    frame._msufGameplayNudgeBorder = border

    frame:HookScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local can = self._msufGameplayCanNudgeFn
        if type(can) == "function" and not can(self) then return end
        MSUF_Gameplay_SelectNudgeFrame(self, true)
    end)

    frame:HookScript("OnHide", function(self)
        MSUF_Gameplay_SelectNudgeFrame(self, false)
        MSUF_Gameplay_ReleaseKeyboardNudge(self)
    end)

    frame:SetScript("OnKeyDown", function(self, key)
        if MSUF_Gameplay_IsCombatInputLocked() then
            MSUF_Gameplay_ReleaseKeyboardNudge(self)
            return
        end

        local dx, dy = 0, 0
        if key == "LEFT" then
            dx = -1
        elseif key == "RIGHT" then
            dx = 1
        elseif key == "UP" then
            dy = 1
        elseif key == "DOWN" then
            dy = -1
        else
            return
        end

        local can = self._msufGameplayCanNudgeFn
        if gameplayNudgeSelection ~= self or MSUF_Gameplay_IsTextInputFocused() or (type(can) == "function" and not can(self)) then
            MSUF_Gameplay_RefreshKeyboardNudge(self)
            return
        end

        local step = MSUF_Gameplay_GetNudgeStep()
        local fn = self._msufGameplayNudgeFn
        if type(fn) == "function" then
            fn(self, dx * step, dy * step)
        end
    end)
end

Gameplay.GetPlayerSpecID = MSUF_Gameplay_GetPlayerSpecID
MSUF.MSUF_GetPlayerSpecID = MSUF_Gameplay_GetPlayerSpecID
Gameplay.Clamp = _MSUF_Clamp
Gameplay.RoundInt = _MSUF_RoundInt
Gameplay.IsTextInputFocused = MSUF_Gameplay_IsTextInputFocused
Gameplay.GetNudgeStep = MSUF_Gameplay_GetNudgeStep
Gameplay.CheckpointHistory = MSUF_Gameplay_CheckpointHistory
Gameplay.BeginHistory = MSUF_Gameplay_BeginHistory
Gameplay.CommitHistory = MSUF_Gameplay_CommitHistory
Gameplay.SelectNudgeFrame = MSUF_Gameplay_SelectNudgeFrame
Gameplay.EnableKeyboardNudge = MSUF_Gameplay_EnableKeyboardNudge
Gameplay.RefreshKeyboardNudge = MSUF_Gameplay_RefreshKeyboardNudge
Gameplay.ReleaseKeyboardNudge = MSUF_Gameplay_ReleaseKeyboardNudge
Gameplay.SetupArrowNudge = MSUF_Gameplay_SetupArrowNudge
Gameplay.SyncNudgeEvents = MSUF_Gameplay_SyncNudgeEvents
