--[[
MSUF_BlizzKill.lua
Blizzard Frame Kill System + Compat Anchors + HideDefaultFrames.

Tracks killed frames for re-assertion on PLAYER_ENTERING_WORLD
(loading screens, flight, zone transitions).
Combat-deferred RegisterStateDriver via lazy PLAYER_REGEN_ENABLED.
Zero per-frame overhead: no OnUpdate, no polling.

Extracted from MidnightSimpleUnitFrames.lua for maintainability.
]]

local _, ns = ...
ns = ns or {}

local CreateFrame = CreateFrame
local RegisterStateDriver = RegisterStateDriver
local C_Timer = C_Timer

local _msufKilledFrames = {}           -- { [frame] = allowInEditMode }
local _msufDeferredCount = 0           -- count of entries in deferred set (avoids next() check)
local _msufKillProtectedDeferred = {}  -- { [frame] = true }
local _msufKillGuardFrame              -- persistent event frame (created once)
local _msufRegenListening = false      -- true when guard is listening to PLAYER_REGEN_ENABLED

local _MSUF_ReassertKilledFrames       -- forward decl
local _MSUF_FlushDeferred              -- forward decl

local function _MSUF_ApplyStateDriverHide(frame)
    if not (frame and RegisterStateDriver) then return false end
    if _G.MSUF_InCombat then
        if not _msufKillProtectedDeferred[frame] then
            _msufKillProtectedDeferred[frame] = true
            _msufDeferredCount = _msufDeferredCount + 1
        end
        if not _msufRegenListening and _msufKillGuardFrame then
            _msufKillGuardFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            _msufRegenListening = true
        end
        return false
    end
    RegisterStateDriver(frame, "visibility", "hide")
    frame.MSUF_StateDriverHidden = true
    if _msufKillProtectedDeferred[frame] then
        _msufKillProtectedDeferred[frame] = nil
        _msufDeferredCount = _msufDeferredCount - 1
    end
    return true
end

local function _MSUF_SafeDisableMouse(frame)
    if not frame or not frame.EnableMouse then return end
    if (frame.IsForbidden and frame:IsForbidden()) or (frame.IsProtected and frame:IsProtected()) then return end
    frame:EnableMouse(false)
end
_G.MSUF_SafeDisableMouse = _MSUF_SafeDisableMouse

local function _MSUF_KillOnShow(f)
    local allowInEditMode = _msufKilledFrames[f]
    if allowInEditMode and MSUF_IsInEditMode and MSUF_IsInEditMode() then return end

    local inCombat = _G.MSUF_InCombat

    if inCombat then
        if f.MSUF_KillCombatApplied then return end
        f.MSUF_KillCombatApplied = true

        if f.MSUF_KillIsProtected then
            if f.SetAlpha then
                f:SetAlpha(0)
            end

            if not f.MSUF_KillDeferred then
                f.MSUF_KillDeferred = true
                if not _msufKillProtectedDeferred[f] then
                    _msufKillProtectedDeferred[f] = true
                    _msufDeferredCount = _msufDeferredCount + 1
                end
            end

            if not _msufRegenListening and _msufKillGuardFrame then
                _msufKillGuardFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                _msufRegenListening = true
            end
            return
        end

        if f.Hide then
            f:Hide()
        end
        return
    end

    f.MSUF_KillCombatApplied = nil
    f.MSUF_KillDeferred = nil
    if f.Hide then
        f:Hide()
    end
end

local function KillFrame(frame, allowInEditMode)
    if not frame then return end

    _msufKilledFrames[frame] = allowInEditMode or false

    if frame.UnregisterAllEvents then
        frame:UnregisterAllEvents()
    end
    frame:Hide()

    local isProtected = frame.IsProtected and frame:IsProtected()
    frame.MSUF_KillIsProtected = isProtected and true or false
    if isProtected then
        if not frame.MSUF_StateDriverHidden then
            _MSUF_ApplyStateDriverHide(frame)
        end
        if frame.HookScript and not frame.MSUF_KillOnShowHooked then
            frame.MSUF_KillOnShowHooked = true
            frame:HookScript("OnShow", _MSUF_KillOnShow)
        end
    else
        if frame.SetScript then
            frame:SetScript("OnShow", _MSUF_KillOnShow)
        end
    end

    _MSUF_SafeDisableMouse(frame)
end
_G.MSUF_KillFrame = KillFrame

_MSUF_ReassertKilledFrames = function()
    if not MSUF_DB then return end
    local g = MSUF_DB.general
    if not g or g.disableBlizzardUnitFrames == false then return end

    local inCombat = _G.MSUF_InCombat

    for frame, allowInEditMode in pairs(_msufKilledFrames) do
        if frame.UnregisterAllEvents then
            frame:UnregisterAllEvents()
        end

        local isProtected = frame.IsProtected and frame:IsProtected()
        if isProtected then
            if not frame.MSUF_StateDriverHidden then
                _MSUF_ApplyStateDriverHide(frame)
            elseif not inCombat then
                RegisterStateDriver(frame, "visibility", "hide")
            end
            if not inCombat and frame.GetAlpha and frame:GetAlpha() ~= 1 then
                frame:SetAlpha(1)
            end
        else
            if frame.IsShown and frame:IsShown() then
                if not (allowInEditMode and MSUF_IsInEditMode and MSUF_IsInEditMode()) then
                    frame:Hide()
                end
            end
        end
        _MSUF_SafeDisableMouse(frame)
    end
end

_MSUF_FlushDeferred = function()
    if _msufDeferredCount <= 0 then return end
    for frame in pairs(_msufKillProtectedDeferred) do
        _MSUF_ApplyStateDriverHide(frame)
        if frame.GetAlpha and frame:GetAlpha() ~= 1 then
            frame:SetAlpha(1)
        end
        if frame.IsShown and frame:IsShown() then
            frame:Hide()
        end
    end
end

-- Pre-allocated callback for deferred detached power bar re-layout.
local function _MSUF_DeferredPBRelayout()
    local uf = _G.MSUF_UnitFrames
    if not uf then return end
    for _, fr in pairs(uf) do
        if fr and fr._msufStampCache then
            fr._msufStampCache["PBEmbedLayout"] = nil
        end
    end
    if _G.MSUF_ApplyPowerBarEmbedLayout_All then
        _G.MSUF_ApplyPowerBarEmbedLayout_All()
    end
end

local function _MSUF_KillGuard_PEW_Callback()
    _MSUF_ReassertKilledFrames()
    if _G.MSUF_ApplyCompatAnchor_PlayerFrame then
        _G.MSUF_ApplyCompatAnchor_PlayerFrame()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.40, _MSUF_DeferredPBRelayout)
    end
end

local function _MSUF_KillGuard_OnEvent(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, _MSUF_KillGuard_PEW_Callback)
        else
            _MSUF_KillGuard_PEW_Callback()
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        _MSUF_FlushDeferred()
        if _G.MSUF_ApplyCompatAnchor_PlayerFrame then
            _G.MSUF_ApplyCompatAnchor_PlayerFrame()
        end
        if _msufDeferredCount <= 0 and _msufKillGuardFrame then
            _msufKillGuardFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            _msufRegenListening = false
        end
        return
    end
end

local function _MSUF_EnsureKillGuard()
    if _msufKillGuardFrame then return end
    _msufKillGuardFrame = CreateFrame("Frame")
    _msufKillGuardFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _msufKillGuardFrame:SetScript("OnEvent", _MSUF_KillGuard_OnEvent)
end

-- Compat anchor: keep Blizzard PlayerFrame alive but invisible + anchored to MSUF.
local function MSUF_GetMSUFPlayerFrame()
    if _G.MSUF_player then return _G.MSUF_player end
    local list = _G.MSUF_UnitFrames
    if list and list.player then return list.player end
    return nil
end

local MSUF_CompatAnchorEventFrame
local MSUF_CompatAnchorPending
local function MSUF_ApplyCompatAnchor_PlayerFrame()
    if not PlayerFrame then return end
    if not MSUF_DB or not MSUF_DB.general then return end
    local g = MSUF_DB.general
    if g.disableBlizzardUnitFrames == false then return end
    if g.hardKillBlizzardPlayerFrame == true then
        PlayerFrame.MSUF_CompatAnchorActive = nil
        return
    end
    PlayerFrame.MSUF_CompatAnchorActive = true
    if PlayerFrame.SetAlpha then PlayerFrame:SetAlpha(0) end
    if PlayerFrame.Show then PlayerFrame:Show() end
    if _G.MSUF_InCombat then
        MSUF_CompatAnchorPending = true
        if not MSUF_CompatAnchorEventFrame then
            MSUF_CompatAnchorEventFrame = CreateFrame("Frame")
            MSUF_CompatAnchorEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            MSUF_CompatAnchorEventFrame:SetScript("OnEvent", function()
                if MSUF_CompatAnchorPending then
                    MSUF_CompatAnchorPending = nil
                    MSUF_ApplyCompatAnchor_PlayerFrame()
                end
            end)
        end
        return
    end
    local anchor = MSUF_GetMSUFPlayerFrame()
    if anchor and PlayerFrame.ClearAllPoints and PlayerFrame.SetPoint then
        PlayerFrame:ClearAllPoints()
        PlayerFrame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    end
    if PlayerFrame.SetScale then PlayerFrame:SetScale(0.05) end
    if PlayerFrame.SetFrameStrata then PlayerFrame:SetFrameStrata("BACKGROUND") end
    if PlayerFrame.SetFrameLevel then PlayerFrame:SetFrameLevel(0) end
    if PlayerFrame.HookScript and not PlayerFrame.MSUF_CompatAnchorHooked then
        PlayerFrame.MSUF_CompatAnchorHooked = true
        PlayerFrame:HookScript("OnShow", function()
            if not PlayerFrame or not PlayerFrame.MSUF_CompatAnchorActive then return end
            if PlayerFrame.SetAlpha then PlayerFrame:SetAlpha(0) end
            if _G.MSUF_InCombat then
                MSUF_CompatAnchorPending = true
                return
            end
            local a = MSUF_GetMSUFPlayerFrame()
            if a and PlayerFrame.ClearAllPoints and PlayerFrame.SetPoint then
                PlayerFrame:ClearAllPoints()
                PlayerFrame:SetPoint("CENTER", a, "CENTER", 0, 0)
            end
        end)
    end
end
_G.MSUF_ApplyCompatAnchor_PlayerFrame = MSUF_ApplyCompatAnchor_PlayerFrame

local function HideDefaultFrames()
    if not MSUF_DB then
        local fn = _G.EnsureDB
        if type(fn) == "function" then fn() end
    end
    local g = (MSUF_DB and MSUF_DB.general) or {}
    if g.disableBlizzardUnitFrames == false then
        return
    end
    if g.hardKillBlizzardPlayerFrame == true then
        KillFrame(PlayerFrame)
    else
        MSUF_ApplyCompatAnchor_PlayerFrame()
    end
    KillFrame(TargetFrameToT)
    KillFrame(PetFrame)
    KillFrame(TargetFrame)
    KillFrame(FocusFrame)
    for i = 1, 5 do
        local bossFrame = _G["Boss"..i.."TargetFrame"]
        KillFrame(bossFrame)
    end
    if BossTargetFrameContainer then
        KillFrame(BossTargetFrameContainer)
        if BossTargetFrameContainer.Selection then
            local sel = BossTargetFrameContainer.Selection
            if sel.UnregisterAllEvents then
                sel:UnregisterAllEvents()
            end
            _MSUF_SafeDisableMouse(sel)
            sel:Hide()
            if sel.SetScript then
                sel:SetScript("OnShow", function(f) f:Hide() end)
                sel:SetScript("OnEnter", nil)
                sel:SetScript("OnLeave", nil)
            end
        end
    end
    _MSUF_EnsureKillGuard()
end
_G.MSUF_HideDefaultFrames = HideDefaultFrames
