local _, MSUF = ...
MSUF = MSUF or {}

local Gameplay = MSUF.Gameplay or {}
MSUF.Gameplay = Gameplay

-- Shared gameplay helper bundle.
-- Provides spec caching, clamping, nudge/history helpers, and lightweight predicates used by
-- gameplay config, runtime, and preview modules. No frames should be created here.
local InCombatLockdown = InCombatLockdown
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local GetCurrentKeyBoardFocus = GetCurrentKeyBoardFocus
local tonumber = tonumber
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local UnitClass = UnitClass

local SUB_ROGUE_SPEC_ID = 261
local isSubRogue = false

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

local function MSUF_Gameplay_IsSubRogue()
    if not UnitClass then return false end
    local _, cls = UnitClass("player")
    return cls == "ROGUE" and MSUF_Gameplay_GetPlayerSpecID() == SUB_ROGUE_SPEC_ID
end

local function MSUF_Gameplay_UpdateSubRogueCache()
    isSubRogue = MSUF_Gameplay_IsSubRogue()
end

local function MSUF_Gameplay_IsSubRogueCached()
    return isSubRogue == true
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
    local ok, result = pcall(checkpoint, label or "Gameplay position", source or "gameplay:position")
    return ok and result or false
end

local function MSUF_Gameplay_BeginHistory(frame, label, source)
    local h = _G.MSUF2
    local begin = h and h.BeginHistoryTransaction
    if not (frame and type(begin) == "function") then return false end
    local ok, started = pcall(begin, label or "Gameplay position", source or "gameplay:position")
    if ok and started then
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
    local ok, result = pcall(commit)
    return ok and result or false
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

    if frame and frame._msufGameplayNudgeBorder then
        frame._msufGameplayNudgeBorder:SetShown(selected and true or false)
    end
end

local function MSUF_Gameplay_EnableKeyboardNudge(frame)
    if not frame or not frame.EnableKeyboard then return end

    if frame.SetPropagateKeyboardInput then
        if InCombatLockdown and InCombatLockdown() then return end
        frame:SetPropagateKeyboardInput(true)
    end

    frame:EnableKeyboard(true)
end

local function MSUF_Gameplay_SetupArrowNudge(frame, nudgeFn, canNudgeFn)
    if not frame or frame._msufGameplayArrowNudgeSetup then return end
    frame._msufGameplayArrowNudgeSetup = true
    frame._msufGameplayNudgeFn = nudgeFn
    frame._msufGameplayCanNudgeFn = canNudgeFn

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
    end)

    frame:SetScript("OnKeyDown", function(self, key)
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
Gameplay.IsSubRogue = MSUF_Gameplay_IsSubRogue
Gameplay.UpdateSubRogueCache = MSUF_Gameplay_UpdateSubRogueCache
Gameplay.IsSubRogueCached = MSUF_Gameplay_IsSubRogueCached
Gameplay.Clamp = _MSUF_Clamp
Gameplay.RoundInt = _MSUF_RoundInt
Gameplay.IsTextInputFocused = MSUF_Gameplay_IsTextInputFocused
Gameplay.GetNudgeStep = MSUF_Gameplay_GetNudgeStep
Gameplay.CheckpointHistory = MSUF_Gameplay_CheckpointHistory
Gameplay.BeginHistory = MSUF_Gameplay_BeginHistory
Gameplay.CommitHistory = MSUF_Gameplay_CommitHistory
Gameplay.SelectNudgeFrame = MSUF_Gameplay_SelectNudgeFrame
Gameplay.EnableKeyboardNudge = MSUF_Gameplay_EnableKeyboardNudge
Gameplay.SetupArrowNudge = MSUF_Gameplay_SetupArrowNudge
