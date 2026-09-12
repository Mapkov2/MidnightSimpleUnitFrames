--- Auras3/MSUF_Auras3_EditMode.lua
---
--- This file intentionally does not own live aura objects and does not add
--- per-aura render callbacks. It owns only edit-mode fake previews, drag
--- movement, and config refresh bridges.
---
--- Edit-mode state is visual and coldpath. Dragging writes layout offsets to
--- the Auras3 DB through the same shape that Menu_Model uses, then asks runtime
--- frames to refresh. Keep live aura payload handling inside the native runtime.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local ExportPublic = MSUF.ExportPublic

local type, tonumber, tostring, pairs = type, tonumber, tostring, pairs
local InCombatLockdown = _G.InCombatLockdown
local C_Timer = _G.C_Timer

-- SetOnUpdateMode takes an Enum.OnUpdateMode value, not a name; a string argument leaves the
-- driver disabled and silently kills the drag OnUpdate.

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
ExportPublic("MSUF_Auras3", A3)
if A3.__editModeLoaded then return end
A3.__editModeLoaded = true

A3.EditMode = (type(A3.EditMode) == "table") and A3.EditMode or {}
local EM = A3.EditMode

-- Keep the lifecycle bridge as the sole initializer. Config and layout are
-- shared by reference, while capture and preview state stay in their owners.
local modules = assert(A3.EditModeModules, "Auras3 edit-mode modules not loaded")
local config = modules.Config()
local BOSS_UNITS = config.BOSS_UNITS
local layout = modules.Layout(config)
local GetFrame = layout.GetFrame
local function IsBossScope(unit)
    return tostring(unit or ""):lower() == "boss"
end

local function ForEachBossUnit(fn)
    if type(fn) ~= "function" then return end
    for i = 1, 5 do fn("boss" .. i) end
end
local function IsEditModeActive()
    local st = rawget(_G, "MSUF_EditState")
    return (st and st.active == true) or rawget(_G, "MSUF_UnitEditModeActive") == true
end

local function EditPreviewActive()
    return IsEditModeActive() and rawget(_G, "MSUF_UnitPreviewActive") == true
end

--- Menu2's boss page keeps the out-of-menu boss frame preview alive; boss aura
--- lanes follow that flag so the page shows auras 1:1 without edit mode.
local function BossPageAuraPreviewActive()
    return rawget(_G, "MSUF2_BossPageAuraPreviewActive") == true
end

local function UnitPreviewActive(unit)
    if EditPreviewActive() then return true end
    if unit == nil then return BossPageAuraPreviewActive() end
    return (BOSS_UNITS[unit] == true or IsBossScope(unit)) and BossPageAuraPreviewActive() or false
end

--- Preview lanes must never cover Menu2. The slash menu sits at DIALOG while it
--- drives the boss page preview and only rises to FULLSCREEN_DIALOG once MSUF
--- Edit Mode is active, so the movers follow that split instead of pinning
--- FULLSCREEN in both cases. HIGH still keeps the dummy icons above the unit
--- frames, which never raise themselves past the UIParent default.
local function SyncPreviewGroupStrata(group)
    if not (group and group.SetFrameStrata) then return end
    local strata = IsEditModeActive() and "FULLSCREEN" or "HIGH"
    if group._msufA3PreviewStrata == strata then return end
    group._msufA3PreviewStrata = strata
    group:SetFrameStrata(strata)
end

local function IsConfigBlocked()
    if InCombatLockdown and InCombatLockdown() then return true end
    if _G.UnitAffectingCombat and _G.UnitAffectingCombat("player") then return true end
    if _G.MSUF_InCombat == true then return true end
    return false
end

local function RequestUnitFrameMenuPreview(reason)
    local fn = _G.MSUF_UFPreview_RequestRefresh
    if type(fn) == "function" then fn(reason or "AURAS3_EDITMODE") end
end


local drag = modules.Drag(config, layout, IsEditModeActive, IsConfigBlocked, RequestUnitFrameMenuPreview)
local PromoteRuntimeLayout = drag.PromoteRuntimeLayout
local preview = modules.Preview(config, layout, drag, IsBossScope, ForEachBossUnit,
    EditPreviewActive, UnitPreviewActive, SyncPreviewGroupStrata)
local ApplyPreviewAuraAnimation = preview.ApplyPreviewAuraAnimation
A3.EditModeModules = nil

local editRefreshSerial = 0
local function CancelQueuedEditRefresh()
    editRefreshSerial = editRefreshSerial + 1
end

local function RequestEditModeAurasRefresh(delay)
    CancelQueuedEditRefresh()
    if IsConfigBlocked() then return end
    if not UnitPreviewActive() then
        EM.HideAll()
        return
    end
    local serial = editRefreshSerial
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0, function()
            if serial ~= editRefreshSerial then return end
            if not UnitPreviewActive() then
                EM.HideAll()
                return
            end
            EM.RefreshAll()
        end)
    else
        EM.RefreshAll()
    end
end

local CoreRefreshAll = A3.RefreshAll
function A3.RefreshAll(...)
    local ret
    if type(CoreRefreshAll) == "function" then ret = CoreRefreshAll(...) end
    if IsConfigBlocked() then return ret end
    RequestEditModeAurasRefresh(0)
    return ret
end

local CoreDisableFrame = A3.DisableFrame
if type(CoreDisableFrame) == "function" then
    function A3.DisableFrame(frame, ...)
        local unit = frame and (frame.MSUFUnitKey or frame.unit)
        if unit then EM.HideUnit(unit) end
        if type(CoreDisableFrame) == "function" then return CoreDisableFrame(frame, ...) end
    end
end

local CoreRefreshUnit = A3.RefreshUnit
function A3.RefreshUnit(unit)
    if IsConfigBlocked() then
        if type(CoreRefreshUnit) == "function" then return CoreRefreshUnit(unit) end
        return false
    end
    if not unit then return end
    if IsEditModeActive() then
        if IsBossScope(unit) then
            ForEachBossUnit(function(bossUnit)
                PromoteRuntimeLayout(bossUnit, rawget(_G, "MSUF_EM2_ActiveAuraGroup"))
            end)
        else
            PromoteRuntimeLayout(unit, rawget(_G, "MSUF_EM2_ActiveAuraGroup"))
        end
    end
    local frame = GetFrame(unit)
    if frame and frame.Auras then frame.Auras.needFullUpdate = true end
    local ret = CoreRefreshUnit(unit)
    EM.RefreshUnit(unit)
    return ret
end

function A3.UpdateUnitAnchor(unit)
    if not unit then return end
    if IsConfigBlocked() then
        if type(A3._QueueDeferredAuraRuntime) == "function" then
            return A3._QueueDeferredAuraRuntime(unit, "AURAS3_UPDATE_ANCHOR")
        end
        return false
    end
    if IsBossScope(unit) then
        if IsEditModeActive() then
            ForEachBossUnit(function(bossUnit)
                PromoteRuntimeLayout(bossUnit, rawget(_G, "MSUF_EM2_ActiveAuraGroup"))
            end)
        end
        EM.RefreshUnit("boss")
        return
    end
    if IsEditModeActive() then
        PromoteRuntimeLayout(unit, rawget(_G, "MSUF_EM2_ActiveAuraGroup"))
    end
    EM.RefreshUnit(unit)
end

function A3.RefreshEditPreview(unit)
    if IsConfigBlocked() then return false end
    if not UnitPreviewActive(unit) then
        if unit then return EM.HideUnit(unit) end
        return EM.HideAll()
    end
    if unit then return EM.RefreshUnit(unit) end
    return EM.RefreshAll()
end

--- Advances only already-built Edit Mode aura dummy regions from Menu2's
--- existing preview clock.  This creates no driver of its own and is rejected
--- during combat; layout/config work remains on the normal cold refresh path.
function A3.RefreshEditPreviewAnimation(unit, elapsed)
    if IsConfigBlocked() or not EditPreviewActive() then return false end
    elapsed = tonumber(elapsed)
    if elapsed == nil then return false end
    if IsBossScope(unit) then
        local any = false
        ForEachBossUnit(function(bossUnit)
            any = A3.RefreshEditPreviewAnimation(bossUnit, elapsed) or any
        end)
        return any
    end
    local byUnit = unit and EM.groups and EM.groups[unit]
    if not byUnit then return false end
    local any = false
    for kind, group in pairs(byUnit) do
        if group and group.IsShown and group:IsShown() then
            local textCfg = group._msufA3AnimationTextConfig
            local shownIcons = tonumber(group._msufA3AnimationShownIcons) or 0
            if textCfg and shownIcons > 0 then
                ApplyPreviewAuraAnimation(group, group._msufA3AnimationKind or kind,
                    shownIcons, textCfg, elapsed)
                any = true
            end
        end
    end
    return any
end

local function OpenAuras3PositionPopup(unit, parent)
    if parent and parent._msufA3MoverKind then
        ExportPublic("MSUF_EM2_ActiveAuraGroup", parent._msufA3MoverKind)
        ExportPublic("MSUF_EM2_ActiveAuraUnit", unit)
    end
    local EM2 = _G.MSUF_EM2
    if EM2 and EM2.Popups then
        return EM2.Popups.Open("aura_" .. tostring(unit or ""), parent)
    elseif EM2 and EM2.AuraPopup then
        return EM2.AuraPopup.Open(unit, parent)
    end
end
ExportPublic("MSUF_OpenAuras3PositionPopup", OpenAuras3PositionPopup)

local function OnEditModeChanged(active)
    if active then
        RequestEditModeAurasRefresh(0.12)
    else
        CancelQueuedEditRefresh()
        EM.HideAll()
        ExportPublic("MSUF_EM2_ActiveAuraGroup", nil)
        ExportPublic("MSUF_EM2_ActiveAuraUnit", nil)
        -- Leaving edit mode must not strip the boss page's aura preview lanes.
        if BossPageAuraPreviewActive() then RequestEditModeAurasRefresh(0) end
    end
end

local function RegisterEditListener()
    if EM._registered then return end
    local reg = _G.MSUF_RegisterAnyEditModeListener
    if type(reg) == "function" then
        reg(OnEditModeChanged)
        EM._registered = true
        if IsEditModeActive() then OnEditModeChanged(true) end
    end
end

RegisterEditListener()
if not EM._registered then
    C_Timer.After(0, RegisterEditListener)
end
