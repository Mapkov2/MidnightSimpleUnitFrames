--[[
MSUF_GF_Effects.lua  v10i
GroupFrames visual effects: aggro border, dispel glow, range fade,
dead/offline/ghost/AFK/DND status overlays.

Reads from:
  - MSUF_DB.general.statusIndicators (showDead/Ghost/AFK/DND)
  - MSUF_DB.groupframes.party.rangeFadeEnabled / rangeFadeAlpha

Secret-safe:
  - UnitThreatSituation  → issecretvalue guard
  - UnitInRange           → issecretvalue guard on both returns
  - UnitIsAFK / UnitIsDND → issecretvalue guard
  - All other UnitIs* calls return regular booleans

Perf:
  - Zero string alloc in combat hot path (pre-built state keys)
  - Hoisted ForEachAura callback (zero closure alloc)
  - Byte-compare unit filter
  - Cached _gfEnabled flag
  - Diff-gated border + alpha + status text
]]

local addonName, ns = ...
ns = ns or {}

local _G               = _G
local type             = type
local CreateFrame      = CreateFrame
local UnitExists       = UnitExists
local UnitThreatSituation = UnitThreatSituation
local UnitInRange      = _G.UnitInRange
local UnitIsConnected  = _G.UnitIsConnected
local UnitIsDead       = _G.UnitIsDead
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitIsGhost      = _G.UnitIsGhost
local UnitIsAFK        = _G.UnitIsAFK
local UnitIsDND        = _G.UnitIsDND
local issecretvalue    = _G.issecretvalue
local string_byte      = string.byte

local GF = ns.GF or {}
ns.GF = GF

-- ═══════════════════════════════════════════════════════════════
-- Constants
-- ═══════════════════════════════════════════════════════════════
local DISPEL_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
}
local AGGRO_R, AGGRO_G, AGGRO_B, AGGRO_A = 1.00, 0.40, 0.00, 0.90

local DISPEL_STATE_KEYS = {
    Magic = "dispel_Magic", Curse = "dispel_Curse",
    Disease = "dispel_Disease", Poison = "dispel_Poison",
}

local BYTE_P = 112  -- 'p'
local BORDER_BACKDROP = { edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 }

-- Range fade defaults
local RANGE_FADE_ALPHA = 0.40
local RANGE_FADE_NORMAL = 1.0

-- ═══════════════════════════════════════════════════════════════
-- Cached AuraUtil
-- ═══════════════════════════════════════════════════════════════
local _AuraUtil, _AuraUtilResolved = nil, false
local function GetAuraUtil()
    if _AuraUtilResolved then return _AuraUtil end
    _AuraUtilResolved = true
    local au = _G.AuraUtil
    if au and type(au.ForEachAura) == "function" then _AuraUtil = au end
    return _AuraUtil
end

-- ═══════════════════════════════════════════════════════════════
-- Border (created once, diff-gated)
-- ═══════════════════════════════════════════════════════════════
local function EnsureBorder(f)
    if f._msufGFBorder then return f._msufGFBorder end
    local brd = CreateFrame("Frame", nil, f, "BackdropTemplate")
    brd:SetAllPoints(f)
    brd:SetFrameLevel(f:GetFrameLevel() + 10)
    brd:SetBackdrop(BORDER_BACKDROP)
    brd:SetBackdropBorderColor(1, 1, 1, 0)
    brd:Hide()
    f._msufGFBorder = brd
    return brd
end

local function SetBorderState(f, state, r, g, b, a)
    if f._msufGFEffectState == state then return end
    f._msufGFEffectState = state
    if not state then
        if f._msufGFBorder then f._msufGFBorder:Hide() end
        return
    end
    local brd = EnsureBorder(f)
    brd:SetBackdropBorderColor(r, g, b, a or 0.90)
    brd:Show()
end

-- ═══════════════════════════════════════════════════════════════
-- Status Text Overlay (DEAD / OFFLINE / GHOST / AFK / DND)
-- ═══════════════════════════════════════════════════════════════
local function EnsureStatusText(f)
    if f._msufGFStatusText then return f._msufGFStatusText end
    local textFrame = f.textFrame or f
    local fs = textFrame:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    fs:SetPoint("CENTER", f, "CENTER", 0, 0)
    fs:SetTextColor(0.9, 0.1, 0.1, 1)
    fs:SetJustifyH("CENTER")
    fs:Hide()
    f._msufGFStatusText = fs
    return fs
end

local function SetStatusText(f, text)
    if f._msufGFStatusLast == text then return end
    f._msufGFStatusLast = text
    if not text or text == "" then
        if f._msufGFStatusText then f._msufGFStatusText:Hide() end
        return
    end
    local fs = EnsureStatusText(f)
    fs:SetText(text)
    fs:Show()
end

-- ═══════════════════════════════════════════════════════════════
-- Range Fade (secret-safe)
-- ═══════════════════════════════════════════════════════════════
local function CheckInRange(f)
    if not f.unit then return true end
    if not UnitExists(f.unit) then return true end
    if not UnitInRange then return true end

    local inR, checked = UnitInRange(f.unit)
    if issecretvalue and (issecretvalue(inR) or issecretvalue(checked)) then
        return true  -- secret → treat as in-range (safe default)
    end
    if checked then return inR and true or false end
    return true  -- not checked → treat as in-range
end

local function ApplyRangeFade(f)
    if f._msufGFPreviewActive then return end

    -- Check if range fade is enabled for GF
    local conf = GF.GetPartyConf()
    if not conf or conf.rangeFadeEnabled ~= true then
        -- Range fade off → ensure full alpha
        if f._msufGFRangeFaded then
            f._msufGFRangeFaded = nil
            f:SetAlpha(RANGE_FADE_NORMAL)
        end
        return
    end

    local inRange = CheckInRange(f)
    if inRange then
        if f._msufGFRangeFaded then
            f._msufGFRangeFaded = nil
            f:SetAlpha(RANGE_FADE_NORMAL)
        end
    else
        if not f._msufGFRangeFaded then
            f._msufGFRangeFaded = true
            local alpha = conf.rangeFadeAlpha
            if type(alpha) ~= "number" then alpha = RANGE_FADE_ALPHA end
            f:SetAlpha(alpha)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Status Check (dead/offline/ghost/AFK/DND)
-- ═══════════════════════════════════════════════════════════════
local function UpdateStatus(f)
    if f._msufGFPreviewActive then return end
    if not f.unit or not UnitExists(f.unit) then
        SetStatusText(f, nil)
        return
    end

    -- Read status indicator config from main DB
    local db = _G.MSUF_DB
    local si = db and db.general and db.general.statusIndicators
    if type(si) ~= "table" then
        SetStatusText(f, nil)
        return
    end

    -- Offline (highest priority)
    if si.showDead and UnitIsConnected then
        local conn = UnitIsConnected(f.unit)
        if conn == false then
            SetStatusText(f, "OFFLINE")
            return
        end
    end

    -- Ghost
    if si.showGhost and UnitIsGhost and UnitIsGhost(f.unit) then
        SetStatusText(f, "GHOST")
        return
    end

    -- Dead
    if si.showDead then
        local dead = false
        if UnitIsDead and UnitIsDead(f.unit) then
            dead = true
        elseif UnitIsDeadOrGhost and UnitIsDeadOrGhost(f.unit) then
            dead = true
        end
        if dead and not (UnitIsGhost and UnitIsGhost(f.unit)) then
            SetStatusText(f, "DEAD")
            return
        end
    end

    -- AFK (secret-safe)
    if si.showAFK and UnitIsAFK then
        local afk = UnitIsAFK(f.unit)
        if issecretvalue and issecretvalue(afk) then afk = nil end
        if afk then
            SetStatusText(f, "AFK")
            return
        end
    end

    -- DND (secret-safe)
    if si.showDND and UnitIsDND then
        local dnd = UnitIsDND(f.unit)
        if issecretvalue and issecretvalue(dnd) then dnd = nil end
        if dnd then
            SetStatusText(f, "DND")
            return
        end
    end

    SetStatusText(f, nil)
end

-- ═══════════════════════════════════════════════════════════════
-- Aggro Check (secret-safe)
-- ═══════════════════════════════════════════════════════════════
local function CheckAggro(f)
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
-- Dispel Check (zero-alloc)
-- ═══════════════════════════════════════════════════════════════
local _dispelResult = nil
local function _ForEachAuraCallback(aura)
    if aura and aura.dispelName and DISPEL_COLORS[aura.dispelName] then
        _dispelResult = aura.dispelName
        return true
    end
end

local function CheckDispellable(f)
    local au = GetAuraUtil()
    if au then
        _dispelResult = nil
        au.ForEachAura(f.unit, "HARMFUL|RAID", nil, _ForEachAuraCallback)
        return _dispelResult
    end
    local UnitDebuff = _G.UnitDebuff
    if not UnitDebuff then return nil end
    local i = 1
    while true do
        local name, _, _, debuffType = UnitDebuff(f.unit, i, "RAID")
        if not name then return nil end
        if debuffType and DISPEL_COLORS[debuffType] then return debuffType end
        i = i + 1
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Update single frame (all effects)
-- ═══════════════════════════════════════════════════════════════
local function UpdateFrameEffects(f)
    if f._msufGFPreviewActive then return end

    -- Range fade
    ApplyRangeFade(f)

    -- Status overlay (dead/offline/ghost/AFK/DND)
    UpdateStatus(f)

    -- Border: Dispel > Aggro
    if UnitExists(f.unit) then
        local dispelType = CheckDispellable(f)
        if dispelType then
            local c = DISPEL_COLORS[dispelType]
            SetBorderState(f, DISPEL_STATE_KEYS[dispelType], c[1], c[2], c[3], 0.85)
            return
        end
        if CheckAggro(f) then
            SetBorderState(f, "aggro", AGGRO_R, AGGRO_G, AGGRO_B, AGGRO_A)
            return
        end
    end
    SetBorderState(f, nil)
end

-- ═══════════════════════════════════════════════════════════════
-- State (shared by ticker + event handler)
-- ═══════════════════════════════════════════════════════════════
local _effectFrame = nil
local _effectsActive = false
local _gfEnabled = false
local _partyFramesDirect = nil

-- ═══════════════════════════════════════════════════════════════
-- Lightweight Ticker for Range Fade + Status Overlays
--
-- Runs at 1.0s interval. Only active when GF frames are visible.
-- No event registration that could interfere with main RangeFade.
-- ═══════════════════════════════════════════════════════════════
local _tickerFrame = nil
local _tickerAcc = 0
local TICKER_INTERVAL = 1.0

local function TickerOnUpdate(_, elapsed)
    _tickerAcc = _tickerAcc + elapsed
    if _tickerAcc < TICKER_INTERVAL then return end
    _tickerAcc = 0

    if not _gfEnabled or not _partyFramesDirect then return end
    for i = 1, 4 do
        local f = _partyFramesDirect[i]
        if f and f:IsShown() and not f._msufGFPreviewActive then
            ApplyRangeFade(f)
            UpdateStatus(f)
        end
    end
end

local function StartTicker()
    if _tickerFrame then return end
    _tickerFrame = CreateFrame("Frame")
    _tickerFrame:SetScript("OnUpdate", TickerOnUpdate)
    _tickerAcc = 0
end

local function StopTicker()
    if _tickerFrame then
        _tickerFrame:SetScript("OnUpdate", nil)
        _tickerFrame = nil
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Event Handler
-- ═══════════════════════════════════════════════════════════════

local function OnEvent(_, event, arg1, arg2)
    if not _gfEnabled then return end

    if event == "GROUP_ROSTER_UPDATE" then
        _gfEnabled = GF.IsEnabled()
        _partyFramesDirect = GF.GetPartyFrames and GF.GetPartyFrames()
        local anyVisible = false
        if _partyFramesDirect then
            for i = 1, 4 do
                local f = _partyFramesDirect[i]
                if f and f:IsShown() then
                    UpdateFrameEffects(f)
                    anyVisible = true
                end
            end
        end
        -- Start/stop range+status ticker based on visibility
        if anyVisible and _gfEnabled then
            StartTicker()
        else
            StopTicker()
        end
        return
    end

    if not arg1 then return end
    local b1 = string_byte(arg1, 1)
    if b1 ~= BYTE_P and b1 ~= 114 then return end -- 'p' or 'r'

    -- UNIT_AURA filter
    if event == "UNIT_AURA" and arg2 and type(arg2) == "table" then
        if arg2.isFullUpdate ~= true and not arg2.addedAuras
            and not arg2.updatedAuraInstanceIDs and not arg2.removedAuraInstanceIDs then
            return
        end
    end

    if not _partyFramesDirect then return end
    for i = 1, 4 do
        local f = _partyFramesDirect[i]
        if f and f.unit == arg1 and f:IsShown() then
            UpdateFrameEffects(f)
            return
        end
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
    _gfEnabled = GF.IsEnabled()
    _partyFramesDirect = GF.GetPartyFrames and GF.GetPartyFrames()
end

-- ═══════════════════════════════════════════════════════════════
-- Bootstrap
-- ═══════════════════════════════════════════════════════════════
do
    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_ENTERING_WORLD")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if not GF.IsEnabled() then return end
        RegisterEffectEvents()
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- Exports
-- ═══════════════════════════════════════════════════════════════
GF.UpdateFrameEffects   = UpdateFrameEffects
GF.RegisterEffectEvents = RegisterEffectEvents
GF.StartEffectTicker    = StartTicker
GF.StopEffectTicker     = StopTicker
GF.RefreshAllEffects = function()
    if not _partyFramesDirect then return end
    local anyVisible = false
    for i = 1, 4 do
        local f = _partyFramesDirect[i]
        if f and f:IsShown() then
            UpdateFrameEffects(f)
            anyVisible = true
        end
    end
    if anyVisible and _gfEnabled then StartTicker() else StopTicker() end
end
_G.MSUF_GF_RefreshAllEffects = GF.RefreshAllEffects
