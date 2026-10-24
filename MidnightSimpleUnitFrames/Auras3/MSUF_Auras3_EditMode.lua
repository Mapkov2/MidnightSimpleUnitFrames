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
local ExportPublic = MSUF.ExportPublic
local PublicGlobals = MSUF.PublicGlobals
local Optional = MSUF.Optional
local EditState = Optional("MSUF_EditState")
local MAX_ARENA_FRAMES = tonumber(MSUF.Client.MaxArenaOpponents) or 3

local type, tonumber, tostring, pairs = type, tonumber, tostring, pairs
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer

-- SetOnUpdateMode takes an Enum.OnUpdateMode value, not a name; a string argument leaves the
-- driver disabled and silently kills the drag OnUpdate.

local A3 = MSUF.MSUF_Auras3
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
local ARENA_UNITS = config.ARENA_UNITS
local layout = modules.Layout(config)
local GetFrame = layout.GetFrame
local function IsBossScope(unit)
    return tostring(unit or ""):lower() == "boss"
end

local function ForEachBossUnit(fn)
    if type(fn) ~= "function" then return end
    for i = 1, 5 do fn("boss" .. i) end
end
local function IsArenaScope(unit)
    return tostring(unit or ""):lower() == "arena"
end

local function ForEachArenaUnit(fn)
    if type(fn) ~= "function" then return end
    for i = 1, MAX_ARENA_FRAMES do fn("arena" .. i) end
end

local function IsEditModeActive()
    return (EditState and EditState.active == true) or MSUF_UnitEditModeActive == true
end

local function EditPreviewActive()
    return IsEditModeActive() and PublicGlobals.MSUF_UnitPreviewActive == true
end

--- Menu2's boss page keeps the out-of-menu boss frame preview alive; boss aura
--- lanes follow that flag so the page shows auras 1:1 without edit mode.
local function BossPageAuraPreviewActive()
    return PublicGlobals.MSUF2_BossPageAuraPreviewActive == true
end

--- Menu2's arena page mirrors the boss-page flag for its own preview lane.
local function ArenaPageAuraPreviewActive()
    return PublicGlobals.MSUF2_ArenaPageAuraPreviewActive == true
end

local function UnitPreviewActive(unit)
    if EditPreviewActive() then return true end
    if unit == nil then return BossPageAuraPreviewActive() or ArenaPageAuraPreviewActive() end
    if (ARENA_UNITS[unit] == true or IsArenaScope(unit)) and ArenaPageAuraPreviewActive() then
        return true
    end
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
    if UnitAffectingCombat and UnitAffectingCombat("player") then return true end
    return false
end

-- The unit preview (Options, load on demand) publishes and clears this refresh
-- through ExportPublic; the Public mirror read keeps the drag flush call-free.
local PublicAPI = MSUF.Public
local function RequestUnitFrameMenuPreview(reason)
    local fn = PublicAPI.UFPreview_RequestRefresh
    if type(fn) == "function" then fn(reason or "AURAS3_EDITMODE") end
end


local drag = modules.Drag(config, layout, IsEditModeActive, IsConfigBlocked, RequestUnitFrameMenuPreview)
-- Aura groups already own capture, lane writes, history and release. Bind
-- those real lifecycle methods; applyDrag uses the group's hosted callback.
local function BeginAuraStrategy(group)
    if drag.BeginAuraGroupDrag(group) then return group end
end
local function FinishAuraStrategy(group)
    return drag.EndAuraGroupDrag(group, "LeftButton", true)
end
MSUF.EditModeKinds.Bind("aura", BeginAuraStrategy, nil, FinishAuraStrategy)
MSUF.EditModeKinds.aura.history = function(_, key, cfg)
    return "aura", cfg.historyKey or cfg._msufA3Unit or key:sub(6)
end
MSUF.EditModeKinds.aura.openPopup = function(_, key, group)
    if group and group._msufA3Unit then return drag.OpenAuraGroupPopup(group) end
    return MSUF.EditModeController.Popups.Open(key, group)
end
local PromoteRuntimeLayout = drag.PromoteRuntimeLayout
local function PromoteActiveLayout(unit)
    PromoteRuntimeLayout(unit, PublicGlobals.MSUF_EM2_ActiveAuraGroup)
end
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
        -- Inline scope dispatch: the aura drag flush refreshes units through here.
        if IsBossScope(unit) then
            ForEachBossUnit(PromoteActiveLayout)
        elseif IsArenaScope(unit) then
            ForEachArenaUnit(PromoteActiveLayout)
        else
            PromoteRuntimeLayout(unit, PublicGlobals.MSUF_EM2_ActiveAuraGroup)
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
        return A3._QueueDeferredAuraRuntime(unit, "AURAS3_UPDATE_ANCHOR")
    end
    if IsBossScope(unit) then
        if IsEditModeActive() then ForEachBossUnit(PromoteActiveLayout) end
        EM.RefreshUnit("boss")
        return
    end
    if IsArenaScope(unit) then
        if IsEditModeActive() then ForEachArenaUnit(PromoteActiveLayout) end
        EM.RefreshUnit("arena")
        return
    end
    if IsEditModeActive() then
        PromoteRuntimeLayout(unit, PublicGlobals.MSUF_EM2_ActiveAuraGroup)
    end
    EM.RefreshUnit(unit)
end

function A3.RefreshEditPreview(unit)
    if not UnitPreviewActive(unit) then
        if unit then return EM.HideUnit(unit) end
        return EM.HideAll()
    end
    if IsConfigBlocked() then return false end
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
    if IsArenaScope(unit) then
        local any = false
        ForEachArenaUnit(function(arenaUnit)
            any = A3.RefreshEditPreviewAnimation(arenaUnit, elapsed) or any
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
    local EM2 = MSUF.EditModeController
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
        -- Leaving edit mode must not strip the boss or arena page's aura preview lanes.
        if BossPageAuraPreviewActive() or ArenaPageAuraPreviewActive() then RequestEditModeAurasRefresh(0) end
    end
end

-- Edit Mode State loads before Auras3 on every client.
MSUF.Require("MSUF_RegisterAnyEditModeListener", "Auras3/MSUF_Auras3_EditMode.lua")(OnEditModeChanged)
if IsEditModeActive() then OnEditModeChanged(true) end
