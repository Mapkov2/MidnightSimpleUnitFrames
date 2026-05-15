-- MSUF_GF_EM2.lua — GF Edit Mode + Popup (consolidated)

-- MSUF_GF_EM2.lua

-- MSUF_GF_EM2.lua — Edit Mode 2 integration for Group Frames
-- Refactor: Group Frames now behave like normal EM2 unitframes.
-- Stored offsetX/offsetY = GRID CENTER everywhere.
-- EM2 drags a real container frame, and preview buttons are parented to it,
-- so live mouse drag and final landing position are identical.
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local EM2 = _G.MSUF_EM2
if not EM2 or not EM2.Registry then return end

local Reg = EM2.Registry
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
local GetTime = GetTime
local type = type
local ipairs = ipairs
local math_max = math.max
local math_floor = math.floor

------------------------------------------------------------------------
-- Real config
------------------------------------------------------------------------
local function GetPartyConf()
    local db = _G.MSUF_DB; return db and db.gf_party
end
local function GetRaidConf()
    local db = _G.MSUF_DB; return db and db.gf_raid
end
local function GetMythicRaidConf()
    local db = _G.MSUF_DB; return db and db.gf_mythicraid
end
local function PartyEnabled()
    local c = GetPartyConf(); return c and c.enabled == true
end
local function RaidEnabled()
    local c = GetRaidConf(); return c and c.enabled == true
end
local function MythicRaidEnabled()
    local c = GetMythicRaidConf(); return c and c.enabled == true
end

local function IsRaidLikeKind(kind)
    return kind == "raid" or kind == "mythicraid"
end

local KIND_TO_KEY = {
    party = "gf_party",
    raid = "gf_raid",
    mythicraid = "gf_mythicraid",
}
local KEY_TO_KIND = {
    gf_party = "party",
    gf_raid = "raid",
    gf_mythicraid = "mythicraid",
}

local function NormalizeKind(kind)
    if kind == "party" or kind == "raid" or kind == "mythicraid" then return kind end
    return KEY_TO_KIND[kind]
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local _containers = {}
local _em2Active = false
local _previewShownByEM2 = true
local _activePreviewKind = nil
local HideHeaders

local function GetDefaultCenter(kind)
    return IsRaidLikeKind(kind) and -500 or -400, 0
end

local function GetRequestedPreviewCount(kind)
    if kind == "mythicraid" then return 20 end
    if kind == "raid" then return 30 end
    return 5
end

local function GetSelectedPreviewKind()
    local gf = ns.GF
    local panel = _G.MSUF_GFOptionsPanel
    if panel and panel.IsShown and panel:IsShown() then
        local optionsKind = NormalizeKind(gf and gf._optionsActiveKind)
        if optionsKind then return optionsKind end
        local explicitKind = NormalizeKind(_activePreviewKind)
        if explicitKind then return explicitKind end
    end

    local stateKey = EM2.State and EM2.State.GetUnitKey and EM2.State.GetUnitKey()
    return NormalizeKind(stateKey)
end

local function ShouldShowPreviewKind(kind)
    local selected = GetSelectedPreviewKind()
    return selected == nil or selected == kind
end

local function RefreshGFPositionUI(kind)
    local gf = ns.GF
    if gf and gf._RequestOptionsResync then gf._RequestOptionsResync() end
    if type(_G.MSUF_EM2_SyncGFPopups) == "function" then
        _G.MSUF_EM2_SyncGFPopups()
    end
    if EM2.HUD and EM2.HUD.RefreshUnitSelector then EM2.HUD.RefreshUnitSelector() end
end

local function GetPreviewCount(kind)
    local gf = ns.GF
    local frames = gf and gf._previewFrames and gf._previewFrames[kind]
    if frames then
        local n = 0
        for i = 1, #frames do
            local f = frames[i]
            if f and f:IsShown() then n = n + 1 end
        end
        if n > 0 then return n end
    end
    return GetRequestedPreviewCount(kind)
end

------------------------------------------------------------------------
-- Container: real draggable frame for EM2
------------------------------------------------------------------------
local function EnsureContainer(kind)
    if _containers[kind] then return _containers[kind] end
    local f = CreateFrame("Frame", "MSUF_GF_Container_" .. kind, UIParent)
    f:SetSize(120, 40)
    f:SetPoint("CENTER", UIParent, "CENTER", GetDefaultCenter(kind))
    f:SetClampedToScreen(true)
    f:Hide()
    f.msufConfigKey = "gf_" .. kind
    f._msufIsGroupFrame = true
    f._msufGFKind = kind
    _containers[kind] = f
    return f
end

local function IsPreviewActive(kind)
    local gf = ns.GF
    return _em2Active
        and _previewShownByEM2
        and gf
        and gf._previewActive
        and gf._previewActive[kind] == true
end

local function SyncContainer(kind)
    local gf = ns.GF; if not gf then return end
    local conf = gf.GetConf(kind); if not conf then return end
    local container = EnsureContainer(kind)

    if not _em2Active or not IsPreviewActive(kind) then
        container:Hide()
        return nil
    end

    -- IMPORTANT:
    -- The live SecureGroupHeader is positioned from the full configured
    -- grid footprint (GF.GetPositionCount), not from the smaller visible
    -- dummy-preview count.  Using the dummy count makes Edit Mode drift away
    -- from the real group frames, especially raid/mythic layouts where the
    -- preview may show 10/20/30 units while the real header reserves the
    -- configured columns.
    local count = (gf.GetPositionCount and gf.GetPositionCount(kind)) or GetPreviewCount(kind)
    local _, _, totalW, totalH = gf.GetGridMetrics(kind, count)
    local cx = conf.offsetX
    local cy = conf.offsetY
    if cx == nil or cy == nil then
        cx, cy = GetDefaultCenter(kind)
    end

    container:SetSize(math_max(totalW, 1), math_max(totalH, 1))
    container:ClearAllPoints()
    local anchorFrame = (gf.ResolveAnchorFrame and gf.ResolveAnchorFrame(kind)) or UIParent
    local anchorPoint = conf.anchorPoint or conf.point or "CENTER"
    -- Stored GF offsets are GRID_CENTER_V1 values.  Keep the container center
    -- on the same configured anchor reference the live header resolves from.
    container:SetPoint("CENTER", anchorFrame, anchorPoint, cx, cy)
    container:Show()
    return container
end

local function SyncAllContainers()
    SyncContainer("party")
    SyncContainer("raid")
    SyncContainer("mythicraid")
end

local function SyncMoversSoon(delay)
    C_Timer.After(delay or 0, function()
        if not _em2Active then return end
        SyncAllContainers()
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    end)
end

local function OpenPreviewPopup(kind, anchor)
    if not _em2Active then return end
    local key = KIND_TO_KEY[kind]
    if not key then return end
    if EM2.State then EM2.State.SetUnitKey(key) end
    if _G.MSUF_GF_EM2_SetPreviewNudgeTarget then _G.MSUF_GF_EM2_SetPreviewNudgeTarget(kind, anchor) end
    if EM2.HUD and EM2.HUD.RefreshUnitSelector then EM2.HUD.RefreshUnitSelector() end
    if EM2.Popups and EM2.Popups.Open then
        EM2.Popups.Open(key, anchor)
    elseif _G.MSUF_EM2_ShowGFPopup then
        _G.MSUF_EM2_ShowGFPopup(kind)
    end
end

local function NudgePreviewKind(kind, dx, dy)
    kind = NormalizeKind(kind)
    local key = KIND_TO_KEY[kind]
    if not key then return false end
    if not (_em2Active and _previewShownByEM2 and IsPreviewActive(kind)) then return false end
    if InCombatLockdown and InCombatLockdown() then return true end

    local gf = ns.GF; if not gf then return false end
    local conf = gf.GetConf and gf.GetConf(kind)
    if not conf then return false end

    local defX, defY = GetDefaultCenter(kind)
    if _G.MSUF_EM_UndoBeforeChange then
        _G.MSUF_EM_UndoBeforeChange("unit", key, true)
    end

    conf.offsetX = math_floor(((tonumber(conf.offsetX) or defX) + (dx or 0)) + 0.5)
    conf.offsetY = math_floor(((tonumber(conf.offsetY) or defY) + (dy or 0)) + 0.5)

    SyncContainer(kind)
    if gf.RefreshPreviewLayout then
        gf.RefreshPreviewLayout(kind)
    end
    HideHeaders()
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    RefreshGFPositionUI(kind)
    return true
end

function _G.MSUF_GF_EM2_NudgePreview(kind, dx, dy)
    return NudgePreviewKind(kind, dx, dy)
end

function _G.MSUF_GF_EM2_SetPreviewNudgeTarget(kind, source)
    local key = KIND_TO_KEY[kind]
    if not key then return end
    if EM2.State then EM2.State.SetUnitKey(key) end
    if not _G.MSUF_EM2_SetPreviewNudgeTarget then return end

    _G.MSUF_EM2_SetPreviewNudgeTarget({
        frame = EnsureContainer(kind),
        sourceFrame = source,
        IsActive = function()
            return _em2Active and _previewShownByEM2 and IsPreviewActive(kind)
        end,
        Nudge = function(_, dx, dy)
            NudgePreviewKind(kind, dx, dy)
        end,
    })
end

local function BeginPreviewDrag(kind)
    if not _em2Active then return false end
    if InCombatLockdown and InCombatLockdown() then return false end

    local key = KIND_TO_KEY[kind]
    local cfg = key and Reg.Get(key)
    if not key or not cfg then return false end
    if _G.MSUF_GF_EM2_SetPreviewNudgeTarget then _G.MSUF_GF_EM2_SetPreviewNudgeTarget(kind) end

    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    local mover = EM2.Movers and EM2.Movers.Get and EM2.Movers.Get(key)
    if not mover or not EM2.Ticker then return false end

    mover._dragging = true
    if mover._coordFS then mover._coordFS:Show() end
    if _G.MSUF_EM_UndoBeforeChange then
        _G.MSUF_EM_UndoBeforeChange("unit", key)
    end
    EM2.Ticker.BeginDrag(mover, key, cfg)
    return true
end

local function EndPreviewDrag(kind, source)
    local key = KIND_TO_KEY[kind]
    local mover = key and EM2.Movers and EM2.Movers.Get and EM2.Movers.Get(key)
    if mover then
        mover._dragging = false
        if mover._coordFS then mover._coordFS:Hide() end
    end
    if EM2.Snap and EM2.Snap.HideGuides then EM2.Snap.HideGuides() end
    if EM2.Ticker then EM2.Ticker.EndDrag() end
    if mover and mover.UpdateLabelVisibility then mover:UpdateLabelVisibility() end
    if source then
        source._msufGFEM2Dragging = nil
        source._msufGFEM2LastDragEnd = GetTime and GetTime() or 0
    end
end

local function WirePreviewMouse(kind)
    local gf = ns.GF; if not gf then return end
    local frames = gf._previewFrames and gf._previewFrames[kind]
    if not frames then return end
    for i = 1, #frames do
        local f = frames[i]
        if f and not f._msufGFEM2MouseWired then
            f._msufGFEM2MouseWired = true
            f._msufGFEM2Kind = kind
            if f.RegisterForClicks then f:RegisterForClicks("LeftButtonUp") end
            if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
            if f.EnableMouse then f:EnableMouse(true) end
            f:SetScript("OnDragStart", function(self)
                if BeginPreviewDrag(self._msufGFEM2Kind or kind) then
                    self._msufGFEM2Dragging = true
                end
            end)
            f:SetScript("OnDragStop", function(self)
                if self._msufGFEM2Dragging then
                    EndPreviewDrag(self._msufGFEM2Kind or kind, self)
                end
            end)
            f:SetScript("OnClick", function(self, button)
                if button ~= "LeftButton" then return end
                if self._msufGFEM2Dragging then return end
                local now = GetTime and GetTime() or 0
                if self._msufGFEM2LastDragEnd and (now - self._msufGFEM2LastDragEnd) < 0.12 then return end
                OpenPreviewPopup(self._msufGFEM2Kind or kind, self)
            end)
        elseif f then
            f._msufGFEM2Kind = kind
            if f.EnableMouse then f:EnableMouse(true) end
        end
    end
end

------------------------------------------------------------------------
-- Header hiding
------------------------------------------------------------------------
function HideHeaders()
    if InCombatLockdown() then return end
    local gf = ns.GF; if not gf or not gf.headers then return end
    if gf.headers.party then gf.headers.party:Hide() end
    if type(gf.HideRaidHeaders) == "function" then gf.HideRaidHeaders(true)
    elseif gf.headers.raid then gf.headers.raid:Hide() end
end

------------------------------------------------------------------------
-- Preview handling
------------------------------------------------------------------------
local function DisablePreviewMouse(disabled)
    local gf = ns.GF; if not gf then return end
    for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
        local frames = gf._previewFrames and gf._previewFrames[kind]
        if frames then
            for i = 1, #frames do
                local f = frames[i]
                if f and f.EnableMouse then
                    f:EnableMouse((disabled and f._msufGFEM2MouseWired) or not disabled)
                end
            end
        end
    end
end

local function ShowPreviewOnly()
    local gf = ns.GF; if not gf then return end
    _previewShownByEM2 = true
    local selectedKind = GetSelectedPreviewKind()

    if PartyEnabled() and ShouldShowPreviewKind("party") then
        gf.SetPreviewAnchor("party", EnsureContainer("party"))
        gf.ShowPreview("party", GetRequestedPreviewCount("party"))
        WirePreviewMouse("party")
    else
        gf.SetPreviewAnchor("party", nil)
        gf.HidePreview("party")
    end
    if RaidEnabled() and ShouldShowPreviewKind("raid") then
        gf.SetPreviewAnchor("raid", EnsureContainer("raid"))
        gf.ShowPreview("raid", GetRequestedPreviewCount("raid"))
        WirePreviewMouse("raid")
    else
        gf.SetPreviewAnchor("raid", nil)
        gf.HidePreview("raid")
    end
    if MythicRaidEnabled() and ShouldShowPreviewKind("mythicraid") then
        gf.SetPreviewAnchor("mythicraid", EnsureContainer("mythicraid"))
        gf.ShowPreview("mythicraid", GetRequestedPreviewCount("mythicraid"))
        WirePreviewMouse("mythicraid")
    else
        gf.SetPreviewAnchor("mythicraid", nil)
        gf.HidePreview("mythicraid")
    end

    DisablePreviewMouse(true)
    SyncAllContainers()
    gf.RefreshPreviewLayout("party")
    gf.RefreshPreviewLayout("raid")
    gf.RefreshPreviewLayout("mythicraid")
    HideHeaders()
    if selectedKind and _G.MSUF_GF_EM2_SetPreviewNudgeTarget then
        _G.MSUF_GF_EM2_SetPreviewNudgeTarget(selectedKind)
    end
    SyncMoversSoon(0)
    SyncMoversSoon(0.05)
end

function _G.MSUF_GF_EM2_SetActivePreviewKind(kind)
    _activePreviewKind = NormalizeKind(kind)
    if _em2Active and _previewShownByEM2 then
        ShowPreviewOnly()
    end
end

local function HidePreviewOnly()
    local gf = ns.GF; if not gf then return end
    _previewShownByEM2 = false

    DisablePreviewMouse(false)
    gf.SetPreviewAnchor("party", nil)
    gf.SetPreviewAnchor("raid", nil)
    gf.SetPreviewAnchor("mythicraid", nil)
    gf.HidePreview("party")
    gf.HidePreview("raid")
    gf.HidePreview("mythicraid")
    SyncAllContainers()
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
end

local function EnterEditMode()
    if _em2Active then return end
    local gf = ns.GF
    if gf and gf._em2UpdateGroupVisibilityWrapper then
        gf.UpdateGroupVisibility = gf._em2UpdateGroupVisibilityWrapper
        _G.MSUF_GF_UpdateGroupVisibility = gf.UpdateGroupVisibility
    end
    _em2Active = true
    SyncAllContainers()
    HideHeaders()
    ShowPreviewOnly()
    SyncMoversSoon(0.1)
end

local function ExitEditMode()
    if not _em2Active then return end
    local gf = ns.GF; if not gf then return end
    -- Kill state FIRST so pending C_Timer callbacks from RebuildAll
    -- see _em2Active=false and skip their ShowPreviewOnly() branch.
    _em2Active = false
    _previewShownByEM2 = false
    if gf._origUpdateGroupVisibility then
        gf.UpdateGroupVisibility = gf._origUpdateGroupVisibility
        _G.MSUF_GF_UpdateGroupVisibility = gf.UpdateGroupVisibility
    end

    -- Hide preview frames
    DisablePreviewMouse(false)
    gf.SetPreviewAnchor("party", nil)
    gf.SetPreviewAnchor("raid", nil)
    gf.SetPreviewAnchor("mythicraid", nil)
    gf.HidePreview("party")
    gf.HidePreview("raid")
    gf.HidePreview("mythicraid")

    -- Hide EM2 containers
    if _containers.party then _containers.party:Hide() end
    if _containers.raid  then _containers.raid:Hide()  end
    if _containers.mythicraid then _containers.mythicraid:Hide() end

    -- Close GF popups
    if _G.MSUF_EM2_HideGFPopup then
        _G.MSUF_EM2_HideGFPopup("party")
        _G.MSUF_EM2_HideGFPopup("raid")
        _G.MSUF_EM2_HideGFPopup("mythicraid")
    end

    -- Restore real headers
    if not InCombatLockdown() then
        if type(gf.SyncHeaderPosition) == "function" then
            gf.SyncHeaderPosition("party")
            gf.SyncHeaderPosition("raid")
            gf.SyncHeaderPosition("mythicraid")
        end
        local fn = gf._origUpdateGroupVisibility or gf.UpdateGroupVisibility
        if type(fn) == "function" then fn() end
    end

    -- Deferred safety net: force-hide any lingering preview frames
    -- and re-trigger real header visibility (catches stale C_Timer races)
    C_Timer.After(0.15, function()
        if _em2Active then return end -- re-entered edit mode already
        -- Belt-and-suspenders: kill preview frames
        for _, kind in ipairs({ "party", "raid", "mythicraid" }) do
            local frames = gf._previewFrames and gf._previewFrames[kind]
            if frames then
                for i = 1, #frames do
                    if frames[i] and frames[i]:IsShown() then frames[i]:Hide() end
                end
            end
            gf._previewActive[kind] = nil
        end
        -- Ensure real headers are visible
        if not InCombatLockdown() then
            local fn = gf._origUpdateGroupVisibility or gf.UpdateGroupVisibility
            if type(fn) == "function" then fn() end
        end
    end)
end

------------------------------------------------------------------------
-- Post-Drag hook
------------------------------------------------------------------------
local function HookPostDrag()
    if type(_G.ApplySettingsForKey) ~= "function" then return end
    hooksecurefunc("ApplySettingsForKey", function(key)
        local keyToKind = {
            gf_party = "party",
            gf_raid = "raid",
            gf_mythicraid = "mythicraid",
        }
        local kind = keyToKind[key]
        if not kind then return end
        local gf = ns.GF; if not gf then return end

        if type(gf.SyncHeaderPosition) == "function" and not InCombatLockdown() then
            gf.SyncHeaderPosition(kind)
        end

        if _em2Active then
            SyncContainer(kind)
            if _previewShownByEM2 then
                gf.RefreshPreviewLayout(kind)
                HideHeaders()
            end
            RefreshGFPositionUI(kind)
        end
    end)
end

------------------------------------------------------------------------
-- Registration
------------------------------------------------------------------------
local function RegisterGF()
    local gf = ns.GF; if not gf then return end

    Reg.Register({
        key       = "gf_party",
        label     = "Group: Party",
        order     = 70,
        popupType = "gf_party",
        canResize = false,
        canNudge  = true,
        getFrame  = function()
            return SyncContainer("party")
        end,
        getConf   = function() local gf = ns.GF; return gf and gf.GetConf("party") or GetPartyConf() end,
        isEnabled = PartyEnabled,
        onEnter   = function() EnterEditMode() end,
        onExit    = function() ExitEditMode() end,
    })

    Reg.Register({
        key       = "gf_raid",
        label     = "Group: Raid",
        order     = 71,
        popupType = "gf_raid",
        canResize = false,
        canNudge  = true,
        getFrame  = function()
            return SyncContainer("raid")
        end,
        getConf   = function() local gf = ns.GF; return gf and gf.GetConf("raid") or GetRaidConf() end,
        isEnabled = RaidEnabled,
        onEnter   = function() EnterEditMode() end,
        onExit    = function() ExitEditMode() end,
    })

    Reg.Register({
        key       = "gf_mythicraid",
        label     = "Group: Mythic Raid",
        order     = 72,
        popupType = "gf_mythicraid",
        canResize = false,
        canNudge  = true,
        getFrame  = function()
            return SyncContainer("mythicraid")
        end,
        getConf   = function() local gf = ns.GF; return gf and gf.GetConf("mythicraid") or GetMythicRaidConf() end,
        isEnabled = MythicRaidEnabled,
        onEnter   = function() EnterEditMode() end,
        onExit    = function() ExitEditMode() end,
    })

    HookPostDrag()

    if EM2.State and EM2.State.IsActive and EM2.State.IsActive() then
        EnterEditMode()
        if EM2.Movers and EM2.Movers.Show then EM2.Movers.Show() end
        SyncMoversSoon(0)
        SyncMoversSoon(0.1)
    end
end

------------------------------------------------------------------------
-- Hook EM2 enter/exit
------------------------------------------------------------------------
do
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_LOGIN")
    ef:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        C_Timer.After(0.1, function()
            RegisterGF()

            -- Primary hook: EM2 State listener (covers HUD Exit, CancelAll, combat exit)
            if _G.MSUF_RegisterAnyEditModeListener then
                _G.MSUF_RegisterAnyEditModeListener(function(active)
                    if active then
                        EnterEditMode()
                        C_Timer.After(0.15, function()
                            if not _em2Active then return end
                            HideHeaders()
                            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
                        end)
                    else
                        ExitEditMode()
                    end
                end)
            end

            -- Legacy fallback: MSUF_SetMSUFEditModeDirect (slash menu, old code paths)
            if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
                hooksecurefunc("MSUF_SetMSUFEditModeDirect", function(active)
                    if active then
                        EnterEditMode()
                        C_Timer.After(0.15, function()
                            if not _em2Active then return end
                            HideHeaders()
                            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
                        end)
                    else
                        ExitEditMode()
                    end
                end)
            end
        end)
    end)
end

------------------------------------------------------------------------
-- HUD "GF" toggle
------------------------------------------------------------------------
do
    C_Timer.After(0.5, function()
        local HUD = EM2.HUD; if not HUD then return end
        local origShow = HUD.Show
        if type(origShow) ~= "function" then return end
        local gfBtn
        HUD.Show = function(...)
            origShow(...)
            if not gfBtn then
                local hf = _G["MSUF_EM2_HUD"]; if not hf then return end
                local slot = _G["MSUF_EM2_HUD_PreviewAddonSlot"]
                local FONT = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
                gfBtn = CreateFrame("Button", nil, slot or hf); gfBtn:SetSize(38, 32)
                gfBtn:CreateTexture(nil, "HIGHLIGHT"):SetAllPoints()
                local lbl = gfBtn:CreateFontString(nil, "OVERLAY")
                lbl:SetFont(FONT, 12, ""); lbl:SetShadowOffset(1, -1)
                lbl:SetPoint("CENTER"); lbl:SetText("GF"); gfBtn._label = lbl
                local dot = gfBtn:CreateTexture(nil, "OVERLAY")
                dot:SetSize(30, 2); dot:SetPoint("BOTTOM", gfBtn, "BOTTOM", 0, 2)
                dot:SetColorTexture(0.38, 0.65, 1.00, 0.90); dot:Hide(); gfBtn._dot = dot
                if slot then
                    gfBtn:SetAllPoints(slot)
                else
                    gfBtn:SetPoint("LEFT", hf, "CENTER", -198, 0)
                end

                local function Vis()
                    if _previewShownByEM2 then
                        gfBtn._label:SetTextColor(0.38, 0.65, 1.00, 1); gfBtn._dot:Show()
                    else
                        gfBtn._label:SetTextColor(0.40, 0.42, 0.50, 0.85); gfBtn._dot:Hide()
                    end
                end

                gfBtn:SetScript("OnClick", function()
                    if _previewShownByEM2 then HidePreviewOnly() else ShowPreviewOnly() end
                    Vis()
                    C_Timer.After(0.05, function()
                        SyncAllContainers()
                        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
                    end)
                end)
                gfBtn:SetScript("OnEnter", function(self)
                    if GameTooltip and not GameTooltip:IsForbidden() then
                        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -6)
                        GameTooltip:SetText("Toggle Group Frames preview", 1, 1, 1, 1, true)
                        GameTooltip:Show()
                    end
                end)
                gfBtn:SetScript("OnLeave", function()
                    if GameTooltip and not GameTooltip:IsForbidden() then GameTooltip:Hide() end
                end)
            end
            if gfBtn then
                if _previewShownByEM2 then gfBtn._label:SetTextColor(0.38, 0.65, 1, 1); gfBtn._dot:Show()
                else gfBtn._label:SetTextColor(0.40, 0.42, 0.50, 0.85); gfBtn._dot:Hide() end
            end
        end
    end)
end

------------------------------------------------------------------------
-- Hooks: runtime/options changes
------------------------------------------------------------------------
do
    C_Timer.After(0.2, function()
        local gf = ns.GF; if not gf then return end

        local origRV = gf.RefreshVisuals
        if type(origRV) == "function" then
            gf.RefreshVisuals = function(...)
                origRV(...)
                if _em2Active and _previewShownByEM2 then
                    SyncAllContainers()
                    gf.RefreshPreviewLayout("party")
                    gf.RefreshPreviewLayout("raid")
                    gf.RefreshPreviewLayout("mythicraid")
                    HideHeaders()
                end
            end
            _G.MSUF_GF_RefreshVisuals = gf.RefreshVisuals
        end

        local origRB = gf.RebuildAll
        if type(origRB) == "function" then
            gf.RebuildAll = function(...)
                origRB(...)
                if _em2Active then
                    C_Timer.After(0.1, function()
                        if not _em2Active then return end
                        SyncAllContainers()
                        if _previewShownByEM2 then
                            ShowPreviewOnly()
                        end
                        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
                    end)
                end
            end
            _G.MSUF_GF_RebuildAll = gf.RebuildAll
        end

        local origUGV = gf.UpdateGroupVisibility
        if type(origUGV) == "function" then
            gf._origUpdateGroupVisibility = origUGV
            gf._em2UpdateGroupVisibilityWrapper = function(...)
                if _em2Active then return end
                origUGV(...)
            end
            _G.MSUF_GF_UpdateGroupVisibility = origUGV
        end
    end)
end

------------------------------------------------------------------------
_G.MSUF_GF_EM2_ShowPreview = ShowPreviewOnly
_G.MSUF_GF_EM2_HidePreview = HidePreviewOnly

-- MSUF_GF_EM2_Popup.lua

-- MSUF_GF_EM2_Popup.lua — Edit Mode popup for GroupFrames  v2
-- Full text settings (Name, HP Text 3-slot, Power) in Edit Mode.
-- Midnight 12.0 secret-safe, zero combat overhead.
local _, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 or not EM2.PopupFactory then return end
local F = EM2.PopupFactory
local floor = math.floor
local max, min = math.max, math.min
local type = type

local GF
local function GetGF() if not GF then GF = ns.GF end; return GF end

local function San(v, d)
    v = tonumber(v) or d or 0
    if v ~= v or v > 2000 or v < -2000 then v = d or 0 end
    return floor(v + 0.5)
end

local _popups = {} -- [mode] = popup

------------------------------------------------------------------------
-- Shared dropdown items (built once, reused across party/raid popups)
------------------------------------------------------------------------
local _textModeItems
local function GetTextModeItems()
    if _textModeItems then return _textModeItems end
    local gf = GetGF()
    local modes = gf and gf.HEALTH_TEXT_MODES
    if not modes then return {} end
    _textModeItems = {}
    for i = 1, #modes do
        _textModeItems[i] = { key = modes[i].key, label = modes[i].label }
    end
    return _textModeItems
end

local _delimItems
local function GetDelimItems()
    if _delimItems then return _delimItems end
    local gf = GetGF()
    local opts = gf and gf.DELIMITER_OPTIONS
    if not opts then return {} end
    _delimItems = {}
    for i = 1, #opts do
        _delimItems[i] = { key = opts[i].key, label = opts[i].label }
    end
    return _delimItems
end

local ANCH = { { "LEFT", "Left" }, { "RIGHT", "Right" }, { "CENTER", "Center" } }

------------------------------------------------------------------------
-- Build popup for a mode ("party" or "raid")
------------------------------------------------------------------------
local function BuildGFPopup(mode)
    local gf = GetGF(); if not gf then return nil end
    local isRaid = (mode == "raid" or mode == "mythicraid")
    local title = (mode == "mythicraid") and "Mythic Raid Frames" or (isRaid and "Raid Frames" or "Party Frames")
    local popup  = F.Panel("MSUF_EM2_GFPopup_" .. mode, 380, isRaid and 640 or 600,
                           title)

    local function Conf() return gf.GetConf(mode) end
    local function V(key) return gf.Val(mode, key) end

    -- ── Apply: read all widgets → write to conf → rebuild ──
    local function Apply()
        if InCombatLockdown and InCombatLockdown() then return end
        local conf = Conf(); if not conf then return end
        if _G.MSUF_EM_UndoBeforeChange then
            _G.MSUF_EM_UndoBeforeChange("gf", mode)
        end

        -- Position & Size
        conf.offsetX = San(popup.xBox and tonumber(popup.xBox:GetText()), conf.offsetX or 0)
        conf.offsetY = San(popup.yBox and tonumber(popup.yBox:GetText()), conf.offsetY or 0)
        local w = popup.wBox and tonumber(popup.wBox:GetText())
        if w then conf.width = floor(max(40, min(400, w)) + 0.5) end
        local h = popup.hBox and tonumber(popup.hBox:GetText())
        if h then conf.height = floor(max(16, min(200, h)) + 0.5) end

        -- Layout
        local sp = popup.spacingBox and tonumber(popup.spacingBox:GetText())
        if sp then conf.spacing = floor(max(0, min(40, sp)) + 0.5) end
        local pbh = popup.pbhBox and tonumber(popup.pbhBox:GetText())
        if pbh then conf.powerHeight = floor(max(0, min(30, pbh)) + 0.5) end
        if isRaid then
            local upc = popup.upcBox and tonumber(popup.upcBox:GetText())
            if upc then conf.unitsPerColumn = floor(max(1, min(40, upc)) + 0.5) end
            local mc = popup.mcBox and tonumber(popup.mcBox:GetText())
            if mc then conf.maxColumns = floor(max(1, min(8, mc)) + 0.5) end
            if popup.preserveRaidGroupsCB then
                conf.preserveRaidGroups = popup.preserveRaidGroupsCB:GetChecked() and true or false
            end
        end

        -- Name
        if popup.nameShowCB then conf.showName = popup.nameShowCB:GetChecked() and true or false end
        conf.nameOffsetX = San(popup.nameXBox and tonumber(popup.nameXBox:GetText()), 0)
        conf.nameOffsetY = San(popup.nameYBox and tonumber(popup.nameYBox:GetText()), 0)
        if popup.nameSizeBox then
            local sz = tonumber(popup.nameSizeBox:GetText())
            if sz then conf.nameFontSize = floor(max(6, min(24, sz)) + 0.5) end
        end
        if popup._nameAnchorVal then conf.nameAnchor = popup._nameAnchorVal end

        -- HP Text (3-slot)
        if popup._hpLeftVal   then conf.textLeft      = popup._hpLeftVal end
        if popup._hpCenterVal then conf.textCenter     = popup._hpCenterVal end
        if popup._hpRightVal  then conf.textRight      = popup._hpRightVal end
        if popup._hpDelimVal  then conf.textDelimiter  = popup._hpDelimVal end
        if popup.hpReverseCB  then conf.hpTextReverse  = popup.hpReverseCB:GetChecked() and true or false end
        if popup.hpSizeBox then
            local sz = tonumber(popup.hpSizeBox:GetText())
            if sz then conf.hpFontSize = floor(max(6, min(24, sz)) + 0.5) end
        end
        conf.hpOffsetX = San(popup.hpXBox and tonumber(popup.hpXBox:GetText()), 0)
        conf.hpOffsetY = San(popup.hpYBox and tonumber(popup.hpYBox:GetText()), 0)

        -- Power
        if popup.powerShowCB then
            local v = popup.powerShowCB:GetChecked() and true or false
            if gf.SetPowerTextEnabled then gf.SetPowerTextEnabled(mode, v) else conf.showPower = v; conf.showPowerText = v end
        end
        if popup._powLeftVal   then conf.powerTextLeft      = popup._powLeftVal end
        if popup._powCenterVal then conf.powerTextCenter    = popup._powCenterVal end
        if popup._powRightVal  then conf.powerTextRight     = popup._powRightVal end
        if popup._powDelimVal  then conf.powerTextDelimiter = popup._powDelimVal end
        if popup.powerSizeBox then
            local sz = tonumber(popup.powerSizeBox:GetText())
            if sz then conf.powerFontSize = floor(max(6, min(24, sz)) + 0.5) end
        end
        conf.powerOffsetX = San(popup.powXBox and tonumber(popup.powXBox:GetText()), 0)
        conf.powerOffsetY = San(popup.powYBox and tonumber(popup.powYBox:GetText()), 0)

        -- Rebuild + immediate Edit Mode preview sync.  UnitFrame popups apply
        -- directly to the live frame; GF needs the same direct path for its
        -- preview container or X/Y fields appear stale until a later rebuild.
        gf.RebuildAll()
        if _em2Active then
            if _previewShownByEM2 and ShouldShowPreviewKind(mode) then
                gf.SetPreviewAnchor(mode, EnsureContainer(mode))
                gf.ShowPreview(mode, GetRequestedPreviewCount(mode))
                WirePreviewMouse(mode)
            end
            SyncContainer(mode)
            if gf.RefreshPreviewLayout then gf.RefreshPreviewLayout(mode) end
            if _previewShownByEM2 then HideHeaders()
            elseif gf.SyncHeaderPosition and not InCombatLockdown() then gf.SyncHeaderPosition(mode) end
            if _G.MSUF_GF_EM2_SetPreviewNudgeTarget then _G.MSUF_GF_EM2_SetPreviewNudgeTarget(mode) end
        elseif gf.SyncHeaderPosition and not InCombatLockdown() then
            gf.SyncHeaderPosition(mode)
        end

        if gf.MarkAllDirty then gf.MarkAllDirty(gf.DIRTY_ALL or 0x3F)
        elseif gf.RefreshVisuals then gf.RefreshVisuals() end
        if gf._RequestOptionsResync then gf._RequestOptionsResync() end
        C_Timer.After(0.05, function()
            if popup and popup.IsShown and popup:IsShown() and popup.Sync then popup.Sync() end
            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        end)
    end

    -- ── Sync: read conf → write to all widgets ──
    local function Sync()
        local conf = Conf(); if not conf then return end
        local function S(b, v) if b and b.SetText then b:SetText(tostring(v or 0)) end end
        local function SC(c, v) if c and c.SetChecked then c:SetChecked(v and true or false) end end

        -- Position & Size
        S(popup.xBox, San(conf.offsetX, 0))
        S(popup.yBox, San(conf.offsetY, 0))
        S(popup.wBox, conf.width  or (isRaid and 80 or 120))
        S(popup.hBox, conf.height or (isRaid and 32 or 40))

        -- Layout
        S(popup.spacingBox, conf.spacing or 1)
        S(popup.pbhBox, conf.powerHeight or (isRaid and 4 or 6))
        if isRaid then
            S(popup.upcBox, conf.unitsPerColumn or 5)
            S(popup.mcBox,  conf.maxColumns or 8)
            SC(popup.preserveRaidGroupsCB, conf.preserveRaidGroups == true)
        end

        -- Name
        SC(popup.nameShowCB, V("showName") ~= false)
        S(popup.nameXBox, conf.nameOffsetX or 0)
        S(popup.nameYBox, conf.nameOffsetY or 0)
        S(popup.nameSizeBox, conf.nameFontSize or (isRaid and 10 or 12))
        popup._nameAnchorVal = conf.nameAnchor or "LEFT"
        if popup.nameAnchorDrop then popup.nameAnchorDrop:SetValue(popup._nameAnchorVal) end

        -- HP Text (3-slot)
        popup._hpLeftVal   = V("textLeft")      or "NONE"
        popup._hpCenterVal = V("textCenter")     or "NONE"
        popup._hpRightVal  = V("textRight")      or "NONE"
        popup._hpDelimVal  = V("textDelimiter")  or " / "
        if popup.hpLeftSel   then popup.hpLeftSel:SetValue(popup._hpLeftVal) end
        if popup.hpCenterSel then popup.hpCenterSel:SetValue(popup._hpCenterVal) end
        if popup.hpRightSel  then popup.hpRightSel:SetValue(popup._hpRightVal) end
        if popup.hpDelimSel  then popup.hpDelimSel:SetValue(popup._hpDelimVal) end
        SC(popup.hpReverseCB, V("hpTextReverse"))
        S(popup.hpSizeBox, conf.hpFontSize or (isRaid and 9 or 10))
        S(popup.hpXBox, conf.hpOffsetX or 0)
        S(popup.hpYBox, conf.hpOffsetY or 0)

        -- Power
        SC(popup.powerShowCB, (gf.IsPowerTextEnabled and gf.IsPowerTextEnabled(mode, conf)) or false)
        popup._powLeftVal   = V("powerTextLeft")      or "NONE"
        popup._powCenterVal = V("powerTextCenter")    or "NONE"
        popup._powRightVal  = V("powerTextRight")     or "NONE"
        popup._powDelimVal  = V("powerTextDelimiter") or " / "
        if popup.powLeftSel   then popup.powLeftSel:SetValue(popup._powLeftVal) end
        if popup.powCenterSel then popup.powCenterSel:SetValue(popup._powCenterVal) end
        if popup.powRightSel  then popup.powRightSel:SetValue(popup._powRightVal) end
        if popup.powDelimSel  then popup.powDelimSel:SetValue(popup._powDelimVal) end
        S(popup.powerSizeBox, conf.powerFontSize or 9)
        S(popup.powXBox, conf.powerOffsetX or 0)
        S(popup.powYBox, conf.powerOffsetY or 0)

        -- Dependent rows gray-out
        if popup.nameShowCB  and popup.nameShowCB.UpdateDependents  then popup.nameShowCB:UpdateDependents() end
        if popup.powerShowCB and popup.powerShowCB.UpdateDependents then popup.powerShowCB:UpdateDependents() end
    end

    popup.Sync  = Sync
    popup.Apply = Apply

    -- ════════════════════════════════════════════════════════════════════
    -- Build UI
    -- ════════════════════════════════════════════════════════════════════
    local top = popup._contentTop

    -- ── Card 1: Position & Size ──
    local fC, fB = F.Card(popup, top, "Position & Size", -2, true)
    local fXY = F.PairRow(popup, fB, fC, { label1="X:", label2="Y:", key1="xBox", key2="yBox", onChanged=Apply })
    F.PairRow(popup, fB, fC, { label1="W:", label2="H:", key1="wBox", key2="hBox",
        anchorTo=fXY, onChanged=Apply })
    fC:RecalcHeight()

    -- ── Card 2: Layout ──
    local lC, lB = F.Card(popup, fC, "Layout", -6, true)
    local lSP = F.PairRow(popup, lB, lC, { label1="Spacing:", label2="PBar H:",
        key1="spacingBox", key2="pbhBox", onChanged=Apply })
    if isRaid then
        local lRaid = F.PairRow(popup, lB, lC, { label1="Units/Col:", label2="Max Cols:",
            key1="upcBox", key2="mcBox", anchorTo=lSP, onChanged=Apply })
        F.CheckRow(popup, lB, lC, { label="Preserve raid groups",
            cbKey="preserveRaidGroupsCB", anchorTo=lRaid, onChanged=function() Apply() end })
    end
    lC:RecalcHeight()

    -- ── Card 3: Name ──
    local nC, nB = F.Card(popup, lC, "Name", -6, true)
    local nShow = F.CheckRow(popup, nB, nC, { label="Show Name", cbKey="nameShowCB",
        onChanged=function() Apply() end })
    local nXY = F.PairRow(popup, nB, nC, { label1="X:", label2="Y:",
        key1="nameXBox", key2="nameYBox", anchorTo=nShow, onChanged=Apply })
    local nSA = F.SizeAnchorRow(popup, nB, nC, { sizeKey="nameSizeBox",
        anchorKey="nameAnchorDrop", stateKey="_nameAnchorVal",
        options=ANCH, anchorTo=nXY, onChanged=Apply })
    nC:RecalcHeight()
    popup.nameShowCB:SetDependentRows(nXY, nSA)

    -- ── Card 4: HP Text (3-slot) ──
    local hC, hB = F.Card(popup, nC, "HP Text", -6, false)
    local hLeft = F.SelectRow(popup, hB, hC, { label="Left:",
        selectKey="hpLeftSel", stateKey="_hpLeftVal",
        items=GetTextModeItems, width=140, menuWidth=160, onChanged=Apply })
    local hCenter = F.SelectRow(popup, hB, hC, { label="Center:",
        selectKey="hpCenterSel", stateKey="_hpCenterVal",
        items=GetTextModeItems, width=140, menuWidth=160, anchorTo=hLeft, onChanged=Apply })
    local hRight = F.SelectRow(popup, hB, hC, { label="Right:",
        selectKey="hpRightSel", stateKey="_hpRightVal",
        items=GetTextModeItems, width=140, menuWidth=160, anchorTo=hCenter, onChanged=Apply })
    local hDelim = F.SelectRow(popup, hB, hC, { label="Delimiter:",
        selectKey="hpDelimSel", stateKey="_hpDelimVal",
        items=GetDelimItems, width=100, menuWidth=120, anchorTo=hRight, onChanged=Apply })
    local hRev = F.CheckRow(popup, hB, hC, { label="Reverse Order", cbKey="hpReverseCB",
        anchorTo=hDelim, onChanged=function() Apply() end })
    local hSize = F.SingleRow(popup, hB, hC, { label="Font Size:", boxKey="hpSizeBox",
        anchorTo=hRev, onChanged=Apply })
    F.PairRow(popup, hB, hC, { label1="X:", label2="Y:",
        key1="hpXBox", key2="hpYBox", anchorTo=hSize, onChanged=Apply })
    hC:RecalcHeight()

    -- ── Card 5: Power ──
    local pC, pB = F.Card(popup, hC, "Power", -6, false)
    local pShow = F.CheckRow(popup, pB, pC, { label="Show Power Text", cbKey="powerShowCB",
        onChanged=function() Apply() end })
    local pLeft = F.SelectRow(popup, pB, pC, { label="Left:",
        selectKey="powLeftSel", stateKey="_powLeftVal",
        items=GetTextModeItems, width=140, menuWidth=160, anchorTo=pShow, onChanged=Apply })
    local pCenter = F.SelectRow(popup, pB, pC, { label="Center:",
        selectKey="powCenterSel", stateKey="_powCenterVal",
        items=GetTextModeItems, width=140, menuWidth=160, anchorTo=pLeft, onChanged=Apply })
    local pRight = F.SelectRow(popup, pB, pC, { label="Right:",
        selectKey="powRightSel", stateKey="_powRightVal",
        items=GetTextModeItems, width=140, menuWidth=160, anchorTo=pCenter, onChanged=Apply })
    local pDelim = F.SelectRow(popup, pB, pC, { label="Delimiter:",
        selectKey="powDelimSel", stateKey="_powDelimVal",
        items=GetDelimItems, width=100, menuWidth=120, anchorTo=pRight, onChanged=Apply })
    local pSize = F.SingleRow(popup, pB, pC, { label="Font Size:", boxKey="powerSizeBox",
        anchorTo=pDelim, onChanged=Apply })
    local pXY = F.PairRow(popup, pB, pC, { label1="X:", label2="Y:",
        key1="powXBox", key2="powYBox", anchorTo=pSize, onChanged=Apply })
    pC:RecalcHeight()
    popup.powerShowCB:SetDependentRows(pLeft, pCenter, pRight, pDelim, pSize, pXY)

    -- ── Scroll recalc ──
    popup._allCards = { fC, lC, nC, hC, pC }
    popup._recalcScroll = function()
        C_Timer.After(0, function()
            local t = popup._scrollChild and popup._scrollChild:GetTop()
            local last = pC
            local b = last and last.GetBottom and last:GetBottom()
            if t and b then popup:UpdateScrollHeight(t - b + 30)
            else popup:UpdateScrollHeight(800) end
        end)
    end

    popup:Hide()
    return popup
end

------------------------------------------------------------------------
-- Show / Hide / IsOpen (global exports for Popups.lua routing)
------------------------------------------------------------------------
local function ShowGFPopup(mode)
    if not _popups[mode] then _popups[mode] = BuildGFPopup(mode) end
    local popup = _popups[mode]; if not popup then return end
    if _G.MSUF_GF_EM2_SetPreviewNudgeTarget then
        _G.MSUF_GF_EM2_SetPreviewNudgeTarget(mode)
    end
    popup.Sync(); popup:Show()
end

local function HideGFPopup(mode)
    if _popups[mode] then _popups[mode]:Hide() end
end

_G.MSUF_EM2_ShowGFPopup = ShowGFPopup
_G.MSUF_EM2_HideGFPopup = HideGFPopup
_G.MSUF_EM2_SyncGFPopups = function()
    for _, popup in pairs(_popups) do
        if popup and popup.IsShown and popup:IsShown() and popup.Sync then
            popup.Sync()
        end
    end
end
_G.MSUF_EM2_GFPopupIsOpen = function()
    return (_popups.party and _popups.party:IsShown())
        or (_popups.raid and _popups.raid:IsShown())
        or (_popups.mythicraid and _popups.mythicraid:IsShown()) or false
end
