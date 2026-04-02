--[[
MSUF_GF_EditMode.lua
Edit Mode 2 integration for GroupFrames.

Key fix (v6): getConf() returns the ACTUAL DB config table
(GF.GetPartyConf / GF.GetRaidConf) so Ticker writes offsetX/offsetY
directly to MSUF_DB.groupframes.party — not a transient virtual table.

Post-drag: hooks ApplySettingsForKey to call GF.Relayout() + SyncContainer.
Container frame covers the bounding box of all visible party frames.
]]

local addonName, ns = ...
ns = ns or {}

local _G   = _G
local type = type
local CreateFrame      = CreateFrame
local hooksecurefunc   = hooksecurefunc
local math_max         = math.max

local GF = ns.GF or {}
ns.GF = GF

-- ═══════════════════════════════════════════════════════════════
-- Container Frame for Party Mover
-- ═══════════════════════════════════════════════════════════════
local _partyContainer = nil

local function EnsurePartyContainer()
    if _partyContainer then return _partyContainer end
    local f = CreateFrame("Frame", "MSUF_GF_PartyContainer", UIParent)
    f:SetSize(120, 36)
    f:SetPoint("CENTER", UIParent, "CENTER", -200, 100)
    f:SetClampedToScreen(true)
    f:Hide()
    f.msufConfigKey = "gf_party"
    f._msufIsGroupFrame = true
    f._msufGFMode = "party"
    f._msufGFContainerMover = true
    _partyContainer = f
    return f
end

local function SyncPartyContainer()
    local gf = ns.GF or _G.MSUF_GF
    if not gf then return end
    local container = EnsurePartyContainer()
    local conf = gf.GetPartyConf()
    if not conf then return end

    local w   = conf.width or 120
    local h   = conf.height or 36
    local sp  = conf.spacing or 2
    local dir = conf.growDirection or "DOWN"
    local ax  = conf.offsetX or -200
    local ay  = conf.offsetY or 100

    local count = 0
    local partyFrames = gf.GetPartyFrames()
    if partyFrames then
        for i = 1, 4 do
            if partyFrames[i] and partyFrames[i]:IsShown() then
                count = count + 1
            end
        end
    end
    if count < 1 then count = 4 end

    local totalW, totalH
    if dir == "DOWN" or dir == "UP" then
        totalW = w
        totalH = count * h + math_max(0, count - 1) * sp
    else
        totalW = count * w + math_max(0, count - 1) * sp
        totalH = h
    end

    container:SetSize(totalW, totalH)
    container:ClearAllPoints()

    if dir == "DOWN" then
        container:SetPoint("CENTER", UIParent, "CENTER",
            ax, ay - (count - 1) * (h + sp) / 2)
    elseif dir == "UP" then
        container:SetPoint("CENTER", UIParent, "CENTER",
            ax, ay + (count - 1) * (h + sp) / 2)
    elseif dir == "RIGHT" then
        container:SetPoint("CENTER", UIParent, "CENTER",
            ax + (count - 1) * (w + sp) / 2, ay)
    elseif dir == "LEFT" then
        container:SetPoint("CENTER", UIParent, "CENTER",
            ax - (count - 1) * (w + sp) / 2, ay)
    end
    container:Show()
end

GF._SyncPartyContainer = SyncPartyContainer

-- ═══════════════════════════════════════════════════════════════
-- Post-Drag Hook
--
-- Ticker calls ApplySettingsForKey(key) after drag ends.
-- Hook it to handle GF keys → relayout + sync container.
-- ═══════════════════════════════════════════════════════════════
local function HookPostDrag()
    local orig = _G.ApplySettingsForKey
    if type(orig) ~= "function" then return end

    hooksecurefunc("ApplySettingsForKey", function(key)
        if key == "gf_party" or key == "gf_raid" then
            local gf = ns.GF or _G.MSUF_GF
            if gf and type(gf.Relayout) == "function" then
                gf.Relayout()
            end
            SyncPartyContainer()
            -- Sync popup if open
            if type(_G.MSUF_EM2_ShowGFPopup) == "function" then
                -- Just sync, don't re-show
                local pType = (key == "gf_raid") and "raid" or "party"
                -- The popup's Sync is called by Ticker already for UnitPopup
                -- but not for GF. Manually sync.
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- Deferred EM2 Registration
-- ═══════════════════════════════════════════════════════════════
do
    local function RegisterGFMovers()
        local EM2 = _G.MSUF_EM2
        if not EM2 or not EM2.Registry or not EM2.Registry.Register then return end
        local gf = ns.GF or _G.MSUF_GF
        if not gf then return end

        -- CRITICAL: getConf returns the ACTUAL DB config table,
        -- NOT the virtual config. Ticker writes offsetX/offsetY here.
        EM2.Registry.Register({
            key       = "gf_party",
            label     = "Group Frames (Party)",
            order     = 200,
            popupType = "gf_party",
            getFrame = function()
                SyncPartyContainer()
                return EnsurePartyContainer()
            end,
            getConf = function()
                -- Return the actual persistent DB table
                return gf.GetPartyConf()
            end,
            isEnabled = function()
                return gf.IsPartyEnabled()
            end,
            canResize = true,
            canNudge  = true,
            onEnter = function()
                if gf.IsPartyEnabled() and type(gf.Refresh) == "function" then
                    gf.Refresh()
                    SyncPartyContainer()
                end
            end,
            onExit = function()
                if _partyContainer then _partyContainer:Hide() end
                if type(gf.Refresh) == "function" then gf.Refresh() end
            end,
        })

        EM2.Registry.Register({
            key       = "gf_raid",
            label     = "Group Frames (Raid)",
            order     = 201,
            popupType = "gf_raid",
            getFrame = function()
                return gf.GetRaidHeader()
            end,
            getConf = function()
                return gf.GetRaidConf()
            end,
            isEnabled = function()
                return gf.IsRaidEnabled()
            end,
            canResize = true,
            canNudge  = true,
            onEnter = function() gf.RebuildVirtualConfigs() end,
            onExit = function()
                if type(gf.Refresh) == "function" then gf.Refresh() end
            end,
        })

        -- Hook drag finalization for GF keys
        HookPostDrag()
    end

    local regFrame = CreateFrame("Frame")
    regFrame:RegisterEvent("PLAYER_LOGIN")
    regFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        RegisterGFMovers()
    end)
end
