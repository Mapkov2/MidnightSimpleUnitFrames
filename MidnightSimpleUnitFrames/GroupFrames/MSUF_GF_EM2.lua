-- MSUF_GF_EM2.lua — Edit Mode 2 integration for Group Frames
--
-- Refactor: Group Frames now behave like normal EM2 unitframes.
-- Stored offsetX/offsetY = GRID CENTER everywhere.
-- EM2 drags a real container frame, and preview buttons are parented to it,
-- so live mouse drag and final landing position are identical.
local _, ns = ...
ns = ns or (_G and _G.MSUF_NS) or {}
if _G then _G.MSUF_NS = ns end

local EM2 = _G.MSUF_EM2
if not EM2 or not EM2.Registry then return end

local Reg = EM2.Registry
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
local type = type
local ipairs = ipairs
local math_max = math.max

------------------------------------------------------------------------
-- Real config
------------------------------------------------------------------------
local function GetPartyConf()
    local db = _G.MSUF_DB; return db and db.gf_party
end
local function GetRaidConf()
    local db = _G.MSUF_DB; return db and db.gf_raid
end
local function PartyEnabled()
    local c = GetPartyConf(); return c and c.enabled == true
end
local function RaidEnabled()
    local c = GetRaidConf(); return c and c.enabled == true
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local _containers = {}
local _em2Active = false
local _previewShownByEM2 = true

local function GetDefaultCenter(kind)
    return (kind == "raid") and -500 or -400, 0
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
    return (kind == "raid") and 10 or 4
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

local function SyncContainer(kind)
    local gf = ns.GF; if not gf then return end
    local conf = gf.GetConf(kind); if not conf then return end
    local container = EnsureContainer(kind)

    if not _em2Active then
        container:Hide()
        return
    end

    local count = GetPreviewCount(kind)
    local _, _, totalW, totalH = gf.GetGridMetrics(kind, count)
    local cx = conf.offsetX
    local cy = conf.offsetY
    if cx == nil or cy == nil then
        cx, cy = GetDefaultCenter(kind)
    end

    container:SetSize(math_max(totalW, 1), math_max(totalH, 1))
    container:ClearAllPoints()
    container:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
    container:Show()
end

local function SyncAllContainers()
    SyncContainer("party")
    SyncContainer("raid")
end

------------------------------------------------------------------------
-- Header hiding
------------------------------------------------------------------------
local function HideHeaders()
    if InCombatLockdown() then return end
    local gf = ns.GF; if not gf or not gf.headers then return end
    if gf.headers.party then gf.headers.party:Hide() end
    if gf.headers.raid  then gf.headers.raid:Hide()  end
end

------------------------------------------------------------------------
-- Preview handling
------------------------------------------------------------------------
local function DisablePreviewMouse(disabled)
    local gf = ns.GF; if not gf then return end
    for _, kind in ipairs({ "party", "raid" }) do
        local frames = gf._previewFrames and gf._previewFrames[kind]
        if frames then
            for i = 1, #frames do
                local f = frames[i]
                if f and f.EnableMouse then f:EnableMouse(not disabled) end
            end
        end
    end
end

local function ShowPreviewOnly()
    local gf = ns.GF; if not gf then return end
    _previewShownByEM2 = true

    if PartyEnabled() then
        gf.SetPreviewAnchor("party", EnsureContainer("party"))
        gf.ShowPreview("party", 4)
    end
    if RaidEnabled() then
        gf.SetPreviewAnchor("raid", EnsureContainer("raid"))
        gf.ShowPreview("raid", 10)
    end

    DisablePreviewMouse(true)
    SyncAllContainers()
    gf.RefreshPreviewLayout("party")
    gf.RefreshPreviewLayout("raid")
    HideHeaders()
end

local function HidePreviewOnly()
    local gf = ns.GF; if not gf then return end
    _previewShownByEM2 = false

    DisablePreviewMouse(false)
    gf.SetPreviewAnchor("party", nil)
    gf.SetPreviewAnchor("raid", nil)
    gf.HidePreview("party")
    gf.HidePreview("raid")
end

local function EnterEditMode()
    _em2Active = true
    SyncAllContainers()
    HideHeaders()
    ShowPreviewOnly()
end

local function ExitEditMode()
    local gf = ns.GF; if not gf then return end
    HidePreviewOnly()
    _em2Active = false
    if _containers.party then _containers.party:Hide() end
    if _containers.raid  then _containers.raid:Hide()  end
    if not InCombatLockdown() then
        if type(gf.SyncHeaderPosition) == "function" then
            gf.SyncHeaderPosition("party")
            gf.SyncHeaderPosition("raid")
        end
        local fn = gf.UpdateGroupVisibility
        if type(fn) == "function" then fn() end
    end
end

------------------------------------------------------------------------
-- Post-Drag hook
------------------------------------------------------------------------
local function HookPostDrag()
    if type(_G.ApplySettingsForKey) ~= "function" then return end
    hooksecurefunc("ApplySettingsForKey", function(key)
        if key ~= "gf_party" and key ~= "gf_raid" then return end
        local kind = (key == "gf_raid") and "raid" or "party"
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
            SyncContainer("party")
            return EnsureContainer("party")
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
            SyncContainer("raid")
            return EnsureContainer("raid")
        end,
        getConf   = function() local gf = ns.GF; return gf and gf.GetConf("raid") or GetRaidConf() end,
        isEnabled = RaidEnabled,
        onEnter   = function() EnterEditMode() end,
        onExit    = function() ExitEditMode() end,
    })

    HookPostDrag()
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
            if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
                hooksecurefunc("MSUF_SetMSUFEditModeDirect", function(active)
                    if active then
                        EnterEditMode()
                        C_Timer.After(0.15, function()
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
                local FONT = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
                gfBtn = CreateFrame("Button", nil, hf); gfBtn:SetSize(38, 32)
                gfBtn:CreateTexture(nil, "HIGHLIGHT"):SetAllPoints()
                local lbl = gfBtn:CreateFontString(nil, "OVERLAY")
                lbl:SetFont(FONT, 12, ""); lbl:SetShadowOffset(1, -1)
                lbl:SetPoint("CENTER"); lbl:SetText("GF"); gfBtn._label = lbl
                local dot = gfBtn:CreateTexture(nil, "OVERLAY")
                dot:SetSize(30, 2); dot:SetPoint("BOTTOM", gfBtn, "BOTTOM", 0, 2)
                dot:SetColorTexture(0.38, 0.65, 1.00, 0.90); dot:Hide(); gfBtn._dot = dot
                gfBtn:SetPoint("RIGHT", hf, "RIGHT", -10, 0)

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
                if _em2Active then
                    SyncAllContainers()
                    if _previewShownByEM2 then
                        gf.RefreshPreviewLayout("party")
                        gf.RefreshPreviewLayout("raid")
                        HideHeaders()
                    end
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
            gf.UpdateGroupVisibility = function(...)
                if _previewShownByEM2 then return end
                origUGV(...)
            end
            _G.MSUF_GF_UpdateGroupVisibility = gf.UpdateGroupVisibility
        end
    end)
end

------------------------------------------------------------------------
_G.MSUF_GF_EM2_ShowPreview = ShowPreviewOnly
_G.MSUF_GF_EM2_HidePreview = HidePreviewOnly
