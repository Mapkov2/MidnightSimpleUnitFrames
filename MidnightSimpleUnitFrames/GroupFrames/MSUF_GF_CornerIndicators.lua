-- MSUF_GF_CornerIndicators.lua — Group Frames: Corner Indicator Dots
-- 5 fixed slots (TL/TR/BL/BR/C) showing colored dots for at-a-glance info:
--   "dispel"  — dispellable debuff present  (HARMFUL|RAID_PLAYER_DISPELLABLE)
--   "boss"    — raid/boss debuff present    (HARMFUL|RAID, isRaid flag)
--   "missing" — player's class buff missing (HELPFUL|PLAYER, auto-detected)
-- All three categories are fully automatic — zero configuration needed.
-- Midnight 12.0 secret-safe, zero combat overhead when disabled.
local _, ns = ...
ns = ns or (_G and _G.MSUF_NS) or {}
if _G then _G.MSUF_NS = ns end

local GF = ns.GF
if not GF then return end

local issecretvalue = _G.issecretvalue
local C_UnitAuras   = _G.C_UnitAuras
local UnitExists    = _G.UnitExists
local UnitClass     = _G.UnitClass
local pairs         = pairs
local type          = type
local select        = select

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local SLOT_KEYS = { "TL", "TR", "BL", "BR", "C" }

local SLOT_ANCHORS = {
    TL = "TOPLEFT",
    TR = "TOPRIGHT",
    BL = "BOTTOMLEFT",
    BR = "BOTTOMRIGHT",
    C  = "CENTER",
}

local SLOT_OFS = {
    TL = {  2, -2 },
    TR = { -2, -2 },
    BL = {  2,  2 },
    BR = { -2,  2 },
    C  = {  0,  0 },
}

local DISPEL_COLORS = {
    Magic   = { 0.25, 0.75, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Poison  = { 0.00, 0.60, 0.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Bleed   = { 0.80, 0.00, 0.00 },
}

local BOSS_COLOR    = { 1.00, 0.15, 0.15 }
local MISSING_COLOR = { 0.80, 0.80, 0.80 }

------------------------------------------------------------------------
-- Auto class buff detection (resolved once at load)
------------------------------------------------------------------------
local CLASS_BUFFS = {
    DRUID   = { 1126 },
    PRIEST  = { 21562 },
    MAGE    = { 1459 },
    WARRIOR = { 6673 },
    SHAMAN  = { 462854 },
    EVOKER  = { 381732, 381741, 381746, 381748, 381749, 381750,
                381751, 381752, 381753, 381754, 381756, 381757, 381758 },
}

local BUFF_NAMES = {
    DRUID   = "Mark of the Wild",
    PRIEST  = "Power Word: Fortitude",
    MAGE    = "Arcane Intellect",
    WARRIOR = "Battle Shout",
    SHAMAN  = "Skyfury",
    EVOKER  = "Blessing of the Bronze",
}

local _playerClassToken
do
    if UnitClass then _, _playerClassToken = UnitClass("player") end
end

local _playerClassBuff = _playerClassToken and CLASS_BUFFS[_playerClassToken] or nil
local _classBufSet = {}
if _playerClassBuff then
    for _, sid in pairs(_playerClassBuff) do _classBufSet[sid] = true end
end

------------------------------------------------------------------------
-- DB helpers
------------------------------------------------------------------------
local function GetConf(kind)
    return GF.GetConf and GF.GetConf(kind) or nil
end

local function SlotCat(conf, slotKey)
    if not conf then return "none" end
    return conf["ciSlot" .. slotKey] or "none"
end

------------------------------------------------------------------------
-- Texture pool (lazy per frame per slot)
------------------------------------------------------------------------
local function EnsureDot(f, slotKey)
    local pool = f._msufCI
    if not pool then pool = {}; f._msufCI = pool end
    local dot = pool[slotKey]
    if not dot then
        local parent = f.statusIconLayer or f.barGroup or f
        dot = parent:CreateTexture(nil, "OVERLAY", nil, 6)
        dot:SetColorTexture(1, 1, 1, 1)
        dot:Hide()
        pool[slotKey] = dot
    end
    return dot
end

------------------------------------------------------------------------
-- Layout (called from GF_Core LayoutIcons + OnSizeChanged)
------------------------------------------------------------------------
function GF.LayoutCornerIndicators(f, kind)
    local conf = GetConf(kind)
    if not conf or conf.ciEnabled == false then return end
    local sz = conf.ciSize or 8
    local anchor = f.statusIconLayer or f.barGroup or f
    for _, sk in pairs(SLOT_KEYS) do
        local cat = SlotCat(conf, sk)
        if cat ~= "none" then
            local dot = EnsureDot(f, sk)
            dot:SetSize(sz, sz)
            dot:ClearAllPoints()
            local ofs = SLOT_OFS[sk]
            dot:SetPoint(SLOT_ANCHORS[sk], anchor, SLOT_ANCHORS[sk], ofs[1], ofs[2])
        else
            local pool = f._msufCI
            if pool and pool[sk] then pool[sk]:Hide() end
        end
    end
end

------------------------------------------------------------------------
-- Scan helpers (Midnight secret-safe)
------------------------------------------------------------------------
local _getSlots  = C_UnitAuras and C_UnitAuras.GetAuraSlots
local _getBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot

local function ScanDispel(unit)
    if type(_getSlots) ~= "function" then return false, nil end
    local _, slot1 = _getSlots(unit, "HARMFUL|RAID_PLAYER_DISPELLABLE", 1, nil)
    if not slot1 then return false, nil end
    if type(_getBySlot) ~= "function" then return true, nil end
    local data = _getBySlot(unit, slot1)
    if not data then return true, nil end
    local dn = data.dispelName
    if issecretvalue and issecretvalue(dn) then return true, nil end
    if dn and dn ~= "" then return true, dn end
    return true, "Bleed"
end

local function ScanBoss(unit)
    if type(_getSlots) ~= "function" then return false end
    local _, slot1 = _getSlots(unit, "HARMFUL|RAID", 1, nil)
    if not slot1 then return false end
    if type(_getBySlot) ~= "function" then return false end
    local data = _getBySlot(unit, slot1)
    if not data then return false end
    local ir = data.isRaid
    if issecretvalue and issecretvalue(ir) then return false end
    if ir then return true end
    local dn = data.dispelName
    if issecretvalue and issecretvalue(dn) then return false end
    return dn and dn ~= ""
end

-- Pre-allocated slot buffer (zero GC)
local _slotBuf = {}
local function CaptureSlots(...)
    local n = select("#", ...)
    for i = 1, n do _slotBuf[i] = select(i, ...) end
    for i = n + 1, #_slotBuf do _slotBuf[i] = nil end
    return n
end

local function ScanMissingClassBuff(unit)
    if not _playerClassBuff then return false end
    if type(_getSlots) ~= "function" then return false end
    if type(_getBySlot) ~= "function" then return false end
    local n = CaptureSlots(_getSlots(unit, "HELPFUL|PLAYER", 20, nil))
    -- index 1 = continuation token, slots start at 2
    for i = 2, n do
        local slot = _slotBuf[i]
        if slot then
            local data = _getBySlot(unit, slot)
            if data then
                local sid = data.spellId
                -- HELPFUL|PLAYER should be plain, but guard for defense-in-depth
                if not (issecretvalue and issecretvalue(sid)) and _classBufSet[sid] then
                    return false  -- found → NOT missing
                end
            end
        end
    end
    return true  -- not found → missing
end

------------------------------------------------------------------------
-- Category resolvers: returns (shouldShow, r, g, b)
------------------------------------------------------------------------
local function ResolveDispel(unit, conf)
    local hasDispel, dispelType = ScanDispel(unit)
    if not hasDispel then return false, 0, 0, 0 end
    local c = dispelType and DISPEL_COLORS[dispelType]
    if c then return true, c[1], c[2], c[3] end
    return true, 0.25, 0.75, 1.00
end

local function ResolveBoss(unit, conf)
    if not ScanBoss(unit) then return false, 0, 0, 0 end
    return true,
        conf.ciBossColorR or BOSS_COLOR[1],
        conf.ciBossColorG or BOSS_COLOR[2],
        conf.ciBossColorB or BOSS_COLOR[3]
end

local function ResolveMissing(unit, conf)
    if not _playerClassBuff then return false, 0, 0, 0 end
    if not ScanMissingClassBuff(unit) then return false, 0, 0, 0 end
    return true,
        conf.ciMissingColorR or MISSING_COLOR[1],
        conf.ciMissingColorG or MISSING_COLOR[2],
        conf.ciMissingColorB or MISSING_COLOR[3]
end

------------------------------------------------------------------------
-- Main update (called from dispatchAura in Effects.lua)
------------------------------------------------------------------------
function GF.UpdateCornerIndicators(f, unit)
    if not f or not unit then return end
    local kind = f._msufGFKind or "party"
    local conf = GetConf(kind)
    if not conf or conf.ciEnabled == false then
        if f._msufCI then
            for _, sk in pairs(SLOT_KEYS) do
                local dot = f._msufCI[sk]
                if dot then dot:Hide() end
            end
        end
        return
    end

    if not UnitExists(unit) then
        if f._msufCI then
            for _, sk in pairs(SLOT_KEYS) do
                local dot = f._msufCI[sk]
                if dot then dot:Hide() end
            end
        end
        return
    end

    local alpha = conf.ciAlpha or 1.0

    -- Each category scanned at most once per update
    local _dispelDone, _bossDone, _missingDone = false, false, false
    local _dispelShow, _dispelR, _dispelG, _dispelB
    local _bossShow,   _bossR,   _bossG,   _bossB
    local _missingShow, _missingR, _missingG, _missingB

    for _, sk in pairs(SLOT_KEYS) do
        local cat = SlotCat(conf, sk)
        if cat == "none" then
            local pool = f._msufCI
            if pool and pool[sk] then pool[sk]:Hide() end
        else
            local show, r, g, b = false, 0, 0, 0

            if cat == "dispel" then
                if not _dispelDone then
                    _dispelDone = true
                    _dispelShow, _dispelR, _dispelG, _dispelB = ResolveDispel(unit, conf)
                end
                show, r, g, b = _dispelShow, _dispelR, _dispelG, _dispelB
            elseif cat == "boss" then
                if not _bossDone then
                    _bossDone = true
                    _bossShow, _bossR, _bossG, _bossB = ResolveBoss(unit, conf)
                end
                show, r, g, b = _bossShow, _bossR, _bossG, _bossB
            elseif cat == "missing" then
                if not _missingDone then
                    _missingDone = true
                    _missingShow, _missingR, _missingG, _missingB = ResolveMissing(unit, conf)
                end
                show, r, g, b = _missingShow, _missingR, _missingG, _missingB
            end

            if show then
                local dot = EnsureDot(f, sk)
                dot:SetColorTexture(r, g, b, alpha)
                if not dot:IsShown() then dot:Show() end
            else
                local pool = f._msufCI
                if pool and pool[sk] then pool[sk]:Hide() end
            end
        end
    end
end

------------------------------------------------------------------------
-- Hide all (unit despawn / disable)
------------------------------------------------------------------------
function GF.HideCornerIndicators(f)
    if not f or not f._msufCI then return end
    for _, sk in pairs(SLOT_KEYS) do
        local dot = f._msufCI[sk]
        if dot then dot:Hide() end
    end
end

------------------------------------------------------------------------
-- Expose for Options UI + Preview
------------------------------------------------------------------------
GF.CI_SLOT_KEYS = SLOT_KEYS
GF.CI_CATEGORIES = {
    { key = "none",    label = "None"               },
    { key = "dispel",  label = "Dispellable"         },
    { key = "boss",    label = "Boss Debuff"         },
    { key = "missing", label = "Missing Class Buff"  },
}
GF.CI_CLASS_BUFF_NAME = _playerClassToken and BUFF_NAMES[_playerClassToken] or nil
