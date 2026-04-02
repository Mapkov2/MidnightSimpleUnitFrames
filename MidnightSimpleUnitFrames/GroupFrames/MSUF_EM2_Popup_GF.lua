-- ============================================================================
-- MSUF_EM2_Popup_GF.lua — Edit Mode popup for GroupFrames
-- Follows MSUF_EM2_Popup_Unit.lua pattern exactly.
-- Controls: Position (X/Y), Size (W/H), Spacing, Power Bar Height,
--           Show toggles (Name/HP/Power), Grow Direction.
-- ============================================================================
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 or not EM2.PopupFactory then return end
local F = EM2.PopupFactory
local floor = math.floor
local max, min = math.max, math.min

local GF
local function GetGF()
    if not GF then GF = ns.GF or _G.MSUF_GF end
    return GF
end

local function San(v, d)
    v = tonumber(v) or d or 0
    if v ~= v or v > 2000 or v < -2000 then v = d or 0 end
    return floor(v + 0.5)
end

local pf    -- party popup
local pf_r  -- raid popup

-- ═══════════════════════════════════════════════════════════════
-- Build a GF popup for a given mode ("party" | "raid")
-- ═══════════════════════════════════════════════════════════════
local function BuildGFPopup(mode)
    local gf = GetGF()
    if not gf then return nil end

    local isRaid = (mode == "raid")
    local title  = isRaid and "Raid Frames" or "Party Frames"
    local popup  = F.Panel("MSUF_EM2_GFPopup_" .. mode, 380, isRaid and 440 or 380, title)

    local function Conf()
        return isRaid and gf.GetRaidConf() or gf.GetPartyConf()
    end

    local function Apply()
        if InCombatLockdown and InCombatLockdown() then return end
        if not popup then return end
        local conf = Conf()
        if not conf then return end

        if type(_G.MSUF_EM_UndoBeforeChange) == "function" then
            _G.MSUF_EM_UndoBeforeChange("gf", mode)
        end

        conf.offsetX = San(popup.xBox and tonumber(popup.xBox:GetText()), 0)
        conf.offsetY = San(popup.yBox and tonumber(popup.yBox:GetText()), 0)

        local w = popup.wBox and tonumber(popup.wBox:GetText())
        if w then conf.width = floor(max(30, min(400, w)) + 0.5) end
        local h = popup.hBox and tonumber(popup.hBox:GetText())
        if h then conf.height = floor(max(8, min(200, h)) + 0.5) end

        local sp = popup.spacingBox and tonumber(popup.spacingBox:GetText())
        if sp then conf.spacing = floor(max(0, min(40, sp)) + 0.5) end

        local pbh = popup.pbhBox and tonumber(popup.pbhBox:GetText())
        if pbh then conf.powerBarHeight = floor(max(0, min(30, pbh)) + 0.5) end

        if popup.nameShowCB then
            conf.showName = popup.nameShowCB:GetChecked() and true or false
        end
        if popup.hpShowCB then
            conf.showHP = popup.hpShowCB:GetChecked() and true or false
        end
        if popup.powerShowCB then
            conf.showPower = popup.powerShowCB:GetChecked() and true or false
        end

        -- Grow direction from dropdown value
        if popup._growDirVal then
            conf.growDirection = popup._growDirVal
        end

        -- Raid-specific
        if isRaid then
            local upc = popup.upcBox and tonumber(popup.upcBox:GetText())
            if upc then conf.unitsPerColumn = floor(max(1, min(40, upc)) + 0.5) end
            local mc = popup.mcBox and tonumber(popup.mcBox:GetText())
            if mc then conf.maxColumns = floor(max(1, min(8, mc)) + 0.5) end
            local gs = popup.gsBox and tonumber(popup.gsBox:GetText())
            if gs then conf.groupSpacing = floor(max(0, min(40, gs)) + 0.5) end
        end

        -- Apply changes
        if type(gf.Refresh) == "function" then gf.Refresh() end
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    end

    local function Sync()
        if not popup then return end
        local conf = Conf()
        if not conf then return end

        local function S(b, v)
            if b and b.SetText then b:SetText(tostring(v or 0)) end
        end
        local function SC(c, v)
            if c and c.SetChecked then c:SetChecked(v and true or false) end
        end

        S(popup.xBox, San(conf.offsetX, 0))
        S(popup.yBox, San(conf.offsetY, 0))
        S(popup.wBox, conf.width or (isRaid and 72 or 120))
        S(popup.hBox, conf.height or (isRaid and 30 or 36))
        S(popup.spacingBox, conf.spacing or 2)
        S(popup.pbhBox, conf.powerBarHeight or (isRaid and 2 or 3))
        SC(popup.nameShowCB, conf.showName ~= false)
        SC(popup.hpShowCB, conf.showHP ~= false)
        SC(popup.powerShowCB, conf.showPower ~= false)
        popup._growDirVal = conf.growDirection or "DOWN"

        if isRaid then
            S(popup.upcBox, conf.unitsPerColumn or 5)
            S(popup.mcBox, conf.maxColumns or 8)
            S(popup.gsBox, conf.groupSpacing or 4)
        end
    end

    popup.Sync = Sync
    popup.Apply = Apply

    -- ── Build UI ─────────────────────────────────────────
    local top = popup._contentTop

    -- Position & Size card
    local fC, fB = F.Card(popup, top, "Position & Size", -2, true)
    F.PairRow(popup, fB, fC, {
        label1 = "X:", label2 = "Y:",
        key1 = "xBox", key2 = "yBox",
        onChanged = Apply,
    })
    local fWH = F.PairRow(popup, fB, fC, {
        label1 = "W:", label2 = "H:",
        key1 = "wBox", key2 = "hBox",
        anchorTo = popup.xBox:GetParent(),
        onChanged = Apply,
    })
    fC:RecalcHeight()

    -- Layout card
    local lC, lB = F.Card(popup, fC, "Layout", -6, true)
    F.PairRow(popup, lB, lC, {
        label1 = "Spacing:", label2 = "PBar H:",
        key1 = "spacingBox", key2 = "pbhBox",
        onChanged = Apply,
    })

    -- Show toggles
    F.CheckRow(popup, lB, lC, {
        label = "Show Name",
        cbKey = "nameShowCB",
        anchorTo = popup.spacingBox:GetParent(),
        onChanged = function() Apply() end,
    })
    F.CheckRow(popup, lB, lC, {
        label = "Show HP Text",
        cbKey = "hpShowCB",
        anchorTo = popup.nameShowCB:GetParent(),
        onChanged = function() Apply() end,
    })
    F.CheckRow(popup, lB, lC, {
        label = "Show Power Bar",
        cbKey = "powerShowCB",
        anchorTo = popup.hpShowCB:GetParent(),
        onChanged = function() Apply() end,
    })
    lC:RecalcHeight()

    -- Raid-specific card
    if isRaid then
        local rC, rB = F.Card(popup, lC, "Raid Grid", -6, true)
        F.PairRow(popup, rB, rC, {
            label1 = "Units/Col:", label2 = "Max Cols:",
            key1 = "upcBox", key2 = "mcBox",
            onChanged = Apply,
        })
        F.PairRow(popup, rB, rC, {
            label1 = "Group Gap:", label2 = "",
            key1 = "gsBox", key2 = nil,
            anchorTo = popup.upcBox:GetParent(),
            onChanged = Apply,
        })
        rC:RecalcHeight()
    end

    popup:Hide()
    return popup
end

-- ═══════════════════════════════════════════════════════════════
-- Registration: called by EM2 when element popup is requested
-- ═══════════════════════════════════════════════════════════════
local function ShowGFPopup(mode)
    local popup
    if mode == "raid" then
        if not pf_r then pf_r = BuildGFPopup("raid") end
        popup = pf_r
    else
        if not pf then pf = BuildGFPopup("party") end
        popup = pf
    end
    if not popup then return end
    popup.Sync()
    popup:Show()
end

local function HideGFPopup(mode)
    if mode == "raid" and pf_r then pf_r:Hide() end
    if mode == "party" and pf then pf:Hide() end
end

-- ═══════════════════════════════════════════════════════════════
-- Export for EM2 popup dispatcher
-- ═══════════════════════════════════════════════════════════════
_G.MSUF_EM2_ShowGFPopup = ShowGFPopup
_G.MSUF_EM2_HideGFPopup = HideGFPopup
_G.MSUF_EM2_GFPopupIsOpen = function()
    return (pf and pf:IsShown()) or (pf_r and pf_r:IsShown()) or false
end
