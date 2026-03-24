--[[
MSUF_GF_Effects.lua
Aggro border + dispel glow for GroupFrame members.

Aggro: orange border when player has aggro on a party/raid unit's target.
       Uses UNIT_THREAT_SITUATION_UPDATE, secret-safe.

Dispel: colored border glow when a party/raid member has a dispellable debuff.
        Uses UNIT_AURA, checks debuffType vs player's dispel capabilities.

Both effects use the same border-overlay approach as main MSUF unitframes.
Zero overhead when GF is disabled or no party/raid exists.
]]

local addonName, ns = ...
ns = ns or {}

local _G               = _G
local type             = type
local pairs            = pairs
local CreateFrame      = CreateFrame
local UnitExists       = UnitExists
local UnitThreatSituation = UnitThreatSituation
local issecretvalue    = _G.issecretvalue

local GF = ns.GF or {}
ns.GF = GF

-- ═══════════════════════════════════════════════════════════════
-- Dispel type → border color
-- ═══════════════════════════════════════════════════════════════
local DISPEL_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
}

-- Aggro color
local AGGRO_COLOR = { 1.00, 0.40, 0.00, 0.90 }

-- ═══════════════════════════════════════════════════════════════
-- Border Overlay (created once per frame, reused)
-- ═══════════════════════════════════════════════════════════════
local function EnsureBorder(f)
    if f._msufGFBorder then return f._msufGFBorder end

    local brd = CreateFrame("Frame", nil, f, "BackdropTemplate")
    brd:SetAllPoints(f)
    brd:SetFrameLevel(f:GetFrameLevel() + 10)
    brd:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    brd:SetBackdropBorderColor(1, 1, 1, 0)
    brd:Hide()

    f._msufGFBorder = brd
    return brd
end

local function ShowBorder(f, r, g, b, a)
    local brd = EnsureBorder(f)
    brd:SetBackdropBorderColor(r, g, b, a or 0.90)
    brd:Show()
end

local function HideBorder(f)
    if f._msufGFBorder then
        f._msufGFBorder:Hide()
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Aggro Check (secret-safe)
-- ═══════════════════════════════════════════════════════════════
local function CheckAggro(f)
    if not f or not f.unit then return false end
    if not UnitExists(f.unit) then return false end
    if not UnitThreatSituation then return false end

    local status = UnitThreatSituation(f.unit)
    if status == nil then return false end
    if issecretvalue and issecretvalue(status) then
        return f._msufGFAggroLast or false
    end
    local hasAggro = (status >= 2)
    f._msufGFAggroLast = hasAggro
    return hasAggro
end

-- ═══════════════════════════════════════════════════════════════
-- Dispel Check
-- ═══════════════════════════════════════════════════════════════
local function CheckDispellable(f)
    if not f or not f.unit then return nil end
    if not UnitExists(f.unit) then return nil end

    local AuraUtil = _G.AuraUtil
    if not AuraUtil or not AuraUtil.ForEachAura then
        -- Fallback for pre-DF API
        local i = 1
        while true do
            local name, _, _, debuffType = UnitDebuff(f.unit, i, "RAID")
            if not name then break end
            if debuffType and DISPEL_COLORS[debuffType] then
                return debuffType
            end
            i = i + 1
        end
        return nil
    end

    -- Midnight 12.0 AuraUtil path
    local found = nil
    AuraUtil.ForEachAura(f.unit, "HARMFUL|RAID", nil, function(aura)
        if aura and aura.dispelName and DISPEL_COLORS[aura.dispelName] then
            found = aura.dispelName
            return true  -- stop iteration
        end
    end)
    return found
end

-- ═══════════════════════════════════════════════════════════════
-- Update single frame (called per event)
-- ═══════════════════════════════════════════════════════════════
local function UpdateFrameEffects(f)
    if not f or not f:IsShown() then return end
    if f._msufGFPreviewActive then return end  -- skip preview frames

    -- Priority: Dispel > Aggro
    local dispelType = CheckDispellable(f)
    if dispelType then
        local c = DISPEL_COLORS[dispelType]
        if c then
            ShowBorder(f, c[1], c[2], c[3], 0.85)
            f._msufGFEffectState = "dispel"
            return
        end
    end

    local hasAggro = CheckAggro(f)
    if hasAggro then
        ShowBorder(f, AGGRO_COLOR[1], AGGRO_COLOR[2], AGGRO_COLOR[3], AGGRO_COLOR[4])
        f._msufGFEffectState = "aggro"
        return
    end

    -- No effect active
    if f._msufGFEffectState then
        f._msufGFEffectState = nil
        HideBorder(f)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Refresh all visible GF frames
-- ═══════════════════════════════════════════════════════════════
local function RefreshAllEffects()
    local partyFrames = GF.GetPartyFrames and GF.GetPartyFrames()
    if partyFrames then
        for i = 1, 4 do
            local f = partyFrames[i]
            if f and f:IsShown() then
                UpdateFrameEffects(f)
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Event Handler
-- ═══════════════════════════════════════════════════════════════
local _effectFrame = nil
local _effectsActive = false

local function OnEvent(_, event, arg1)
    if not GF.IsEnabled or not GF.IsEnabled() then return end

    if event == "UNIT_THREAT_SITUATION_UPDATE" then
        -- Only process party units
        if not arg1 then return end
        local prefix = arg1:sub(1, 5)
        if prefix ~= "party" and prefix ~= "raid " then return end

        local partyFrames = GF.GetPartyFrames and GF.GetPartyFrames()
        if partyFrames then
            for i = 1, 4 do
                local f = partyFrames[i]
                if f and f.unit == arg1 and f:IsShown() then
                    UpdateFrameEffects(f)
                    return
                end
            end
        end
        return
    end

    if event == "UNIT_AURA" then
        if not arg1 then return end
        local prefix = arg1:sub(1, 5)
        if prefix ~= "party" and prefix ~= "raid " then return end

        local partyFrames = GF.GetPartyFrames and GF.GetPartyFrames()
        if partyFrames then
            for i = 1, 4 do
                local f = partyFrames[i]
                if f and f.unit == arg1 and f:IsShown() then
                    UpdateFrameEffects(f)
                    return
                end
            end
        end
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        RefreshAllEffects()
        return
    end
end

local function RegisterEffectEvents()
    if _effectsActive then return end
    if not _effectFrame then
        _effectFrame = CreateFrame("Frame")
        _effectFrame:SetScript("OnEvent", OnEvent)
    end
    _effectFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    _effectFrame:RegisterEvent("UNIT_AURA")
    _effectFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    _effectsActive = true
end

local function UnregisterEffectEvents()
    if not _effectsActive or not _effectFrame then return end
    _effectFrame:UnregisterAllEvents()
    _effectsActive = false
end

-- ═══════════════════════════════════════════════════════════════
-- Bootstrap
-- ═══════════════════════════════════════════════════════════════
do
    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_ENTERING_WORLD")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if not GF.IsEnabled or not GF.IsEnabled() then return end
        RegisterEffectEvents()
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- Exports
-- ═══════════════════════════════════════════════════════════════
GF.UpdateFrameEffects  = UpdateFrameEffects
GF.RefreshAllEffects   = RefreshAllEffects
_G.MSUF_GF_RefreshAllEffects = RefreshAllEffects
