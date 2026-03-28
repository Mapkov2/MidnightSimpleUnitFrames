-- MSUF_GF_EM2_Popup.lua — Edit Mode popup for GroupFrames
-- Follows MSUF_EM2_Popup_Unit.lua pattern. Uses PopupFactory.
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

local function BuildGFPopup(mode)
    local gf = GetGF(); if not gf then return nil end
    local isRaid = (mode == "raid")
    local popup  = F.Panel("MSUF_EM2_GFPopup_" .. mode, 380, isRaid and 440 or 340,
                           isRaid and "Raid Frames" or "Party Frames")

    local function Conf() return gf.GetConf(mode) end

    local function Apply()
        if InCombatLockdown and InCombatLockdown() then return end
        local conf = Conf(); if not conf then return end
        if type(_G.MSUF_EM_UndoBeforeChange) == "function" then
            _G.MSUF_EM_UndoBeforeChange("gf", mode)
        end
        conf.offsetX = San(popup.xBox and tonumber(popup.xBox:GetText()), conf.offsetX or 0)
        conf.offsetY = San(popup.yBox and tonumber(popup.yBox:GetText()), conf.offsetY or 0)
        local w = popup.wBox and tonumber(popup.wBox:GetText())
        if w then conf.width = floor(max(40, min(400, w)) + 0.5) end
        local h = popup.hBox and tonumber(popup.hBox:GetText())
        if h then conf.height = floor(max(16, min(200, h)) + 0.5) end
        local sp = popup.spacingBox and tonumber(popup.spacingBox:GetText())
        if sp then conf.spacing = floor(max(0, min(40, sp)) + 0.5) end
        local pbh = popup.pbhBox and tonumber(popup.pbhBox:GetText())
        if pbh then conf.powerHeight = floor(max(0, min(30, pbh)) + 0.5) end
        if popup.nameShowCB  then conf.showName  = popup.nameShowCB:GetChecked()  and true or false end
        if popup.hpShowCB    then conf.showHP    = popup.hpShowCB:GetChecked()    and true or false end
        if popup.powerShowCB then conf.showPower = popup.powerShowCB:GetChecked() and true or false end
        if isRaid then
            local upc = popup.upcBox and tonumber(popup.upcBox:GetText())
            if upc then conf.unitsPerColumn = floor(max(1, min(40, upc)) + 0.5) end
            local mc = popup.mcBox and tonumber(popup.mcBox:GetText())
            if mc then conf.maxColumns = floor(max(1, min(8, mc)) + 0.5) end
        end
        gf.RebuildAll()
        C_Timer.After(0.1, function()
            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        end)
    end

    local function Sync()
        local conf = Conf(); if not conf then return end
        local function S(b, v) if b and b.SetText then b:SetText(tostring(v or 0)) end end
        local function SC(c, v) if c and c.SetChecked then c:SetChecked(v and true or false) end end
        S(popup.xBox, San(conf.offsetX, 0))
        S(popup.yBox, San(conf.offsetY, 0))
        S(popup.wBox, conf.width or (isRaid and 80 or 120))
        S(popup.hBox, conf.height or (isRaid and 32 or 40))
        S(popup.spacingBox, conf.spacing or 1)
        S(popup.pbhBox, conf.powerHeight or 6)
        SC(popup.nameShowCB, conf.showName ~= false)
        SC(popup.hpShowCB, conf.showHP)
        SC(popup.powerShowCB, conf.showPower)
        if isRaid then
            S(popup.upcBox, conf.unitsPerColumn or 5)
            S(popup.mcBox, conf.maxColumns or 8)
        end
    end

    popup.Sync  = Sync
    popup.Apply = Apply

    -- ── Build UI ─────────────────────────────────────────
    local top = popup._contentTop

    local fC, fB = F.Card(popup, top, "Position & Size", -2, true)
    F.PairRow(popup, fB, fC, { label1="X:", label2="Y:", key1="xBox", key2="yBox", onChanged=Apply })
    F.PairRow(popup, fB, fC, { label1="W:", label2="H:", key1="wBox", key2="hBox",
        anchorTo = popup.xBox:GetParent(), onChanged=Apply })
    fC:RecalcHeight()

    local lC, lB = F.Card(popup, fC, "Layout", -6, true)
    F.PairRow(popup, lB, lC, { label1="Spacing:", label2="PBar H:",
        key1="spacingBox", key2="pbhBox", onChanged=Apply })
    F.CheckRow(popup, lB, lC, { label="Show Name", cbKey="nameShowCB",
        anchorTo=popup.spacingBox:GetParent(), onChanged=function() Apply() end })
    F.CheckRow(popup, lB, lC, { label="Show HP Text", cbKey="hpShowCB",
        anchorTo=popup.nameShowCB:GetParent(), onChanged=function() Apply() end })
    F.CheckRow(popup, lB, lC, { label="Show Power Text", cbKey="powerShowCB",
        anchorTo=popup.hpShowCB:GetParent(), onChanged=function() Apply() end })
    lC:RecalcHeight()

    if isRaid then
        local rC, rB = F.Card(popup, lC, "Raid Grid", -6, true)
        F.PairRow(popup, rB, rC, { label1="Units/Col:", label2="Max Cols:",
            key1="upcBox", key2="mcBox", onChanged=Apply })
        rC:RecalcHeight()
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
    popup.Sync(); popup:Show()
end

local function HideGFPopup(mode)
    if _popups[mode] then _popups[mode]:Hide() end
end

_G.MSUF_EM2_ShowGFPopup = ShowGFPopup
_G.MSUF_EM2_HideGFPopup = HideGFPopup
_G.MSUF_EM2_GFPopupIsOpen = function()
    return (_popups.party and _popups.party:IsShown())
        or (_popups.raid and _popups.raid:IsShown()) or false
end
