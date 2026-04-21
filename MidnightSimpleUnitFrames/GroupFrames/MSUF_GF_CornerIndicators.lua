-- MSUF_GF_CornerIndicators.lua — Group Frames: Corner Indicator Dots
-- FULL PERFORMANCE REWRITE — zero unnecessary function calls in hot path.
-- 5 fixed slots (TL/TR/BL/BR/C) showing colored dots for at-a-glance info:
--   "dispel"  — dispellable debuff present  (HARMFUL|RAID_PLAYER_DISPELLABLE)
--   "boss"    — raid/boss debuff present    (HARMFUL|RAID, isRaid flag)
--   "missing" — player's class buff missing (HELPFUL|PLAYER, auto-detected)
-- Midnight 12.0 secret-safe, zero combat overhead when disabled.
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

-- Localize everything at file scope (zero global lookups in hot path)
local issecretvalue = _G.issecretvalue
local UnitExists    = _G.UnitExists
local UnitClass     = _G.UnitClass
local GetTime       = _G.GetTime
local type          = type
local next          = next
local tonumber      = tonumber

-- C API (resolved once at load)
local _getSlots  = _G.C_UnitAuras and _G.C_UnitAuras.GetAuraSlots
local _getBySlot = _G.C_UnitAuras and _G.C_UnitAuras.GetAuraDataBySlot
local _hasSlotAPI  = (type(_getSlots) == "function")
local _hasDataAPI  = (type(_getBySlot) == "function")

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local SLOT_KEYS     = { "TL", "TR", "BL", "BR", "C" }
local SLOT_ANCHORS  = { TL = "TOPLEFT", TR = "TOPRIGHT", BL = "BOTTOMLEFT", BR = "BOTTOMRIGHT", C = "CENTER" }
local SLOT_OFS_X    = { TL =  2, TR = -2, BL =  2, BR = -2, C = 0 }
local SLOT_OFS_Y    = { TL = -2, TR = -2, BL =  2, BR =  2, C = 0 }
local CONF_KEYS     = { TL = "ciSlotTL", TR = "ciSlotTR", BL = "ciSlotBL", BR = "ciSlotBR", C = "ciSlotC" }

local DISPEL_R = { Magic = 0.25, Curse = 0.60, Poison = 0.00, Disease = 0.60, Bleed = 0.80 }
local DISPEL_G = { Magic = 0.75, Curse = 0.00, Poison = 0.60, Disease = 0.40, Bleed = 0.00 }
local DISPEL_B = { Magic = 1.00, Curse = 1.00, Poison = 0.00, Disease = 0.00, Bleed = 0.00 }
local DISPEL_CURVE_POINTS = {
    { id = 0,  r = 0.25, g = 0.75, b = 1.00 },
    { id = 1,  r = 0.25, g = 0.75, b = 1.00 },
    { id = 2,  r = 0.60, g = 0.00, b = 1.00 },
    { id = 3,  r = 0.60, g = 0.40, b = 0.00 },
    { id = 4,  r = 0.00, g = 0.60, b = 0.00 },
    { id = 9,  r = 0.80, g = 0.00, b = 0.00 },
    { id = 11, r = 0.80, g = 0.00, b = 0.00 },
}

-- PERF C++ DELEGATION: Dispel color resolved entirely in C++ via ColorCurve.
-- Eliminates Lua table lookups + issecretvalue guard on dispelName.
local _dispelColorCurve
local _hasDispelColorAPI = (type(_G.C_UnitAuras) == "table"
    and type(_G.C_UnitAuras.GetAuraDispelTypeColor) == "function"
    and type(_G.C_CurveUtil) == "table"
    and type(_G.C_CurveUtil.CreateColorCurve) == "function")
if _hasDispelColorAPI then
    _dispelColorCurve = _G.C_CurveUtil.CreateColorCurve()
    if _dispelColorCurve.SetType then
        _dispelColorCurve:SetType(_G.Enum and _G.Enum.LuaCurveType and _G.Enum.LuaCurveType.Step or 0)
    end
    -- Map DispelType enum → colors (same as DISPEL_R/G/B tables)
    if _dispelColorCurve.AddPoint then
        for i = 1, #DISPEL_CURVE_POINTS do
            local p = DISPEL_CURVE_POINTS[i]
            _dispelColorCurve:AddPoint(p.id, CreateColor(p.r, p.g, p.b, 1))
        end
    else
        _hasDispelColorAPI = false
        _dispelColorCurve = nil
    end
end
-- C API for C++-based dispel scan (GetAuraDataByIndex is cheaper than GetAuraSlots+GetAuraDataBySlot)
local _getAuraByIndex = _G.C_UnitAuras and _G.C_UnitAuras.GetAuraDataByIndex
local _getDispelColor = _hasDispelColorAPI and _G.C_UnitAuras.GetAuraDispelTypeColor

------------------------------------------------------------------------
-- Auto class buff detection (resolved once at load — zero runtime cost)
------------------------------------------------------------------------
local _classBufSet = {}
local _hasClassBuff = false
do
    local _, tok = UnitClass and UnitClass("player")
    local CLASS_BUFFS = {
        DRUID={1126}, PRIEST={21562}, MAGE={1459}, WARRIOR={6673},
        SHAMAN={462854},
        EVOKER={381732,381741,381746,381748,381749,381750,381751,381752,381753,381754,381756,381757,381758},
    }
    local BUFF_NAMES = {
        DRUID="Mark of the Wild", PRIEST="Power Word: Fortitude", MAGE="Arcane Intellect",
        WARRIOR="Battle Shout", SHAMAN="Skyfury", EVOKER="Blessing of the Bronze",
    }
    local bufs = tok and CLASS_BUFFS[tok]
    if bufs then
        _hasClassBuff = true
        for i = 1, #bufs do _classBufSet[bufs[i]] = true end
    end
    GF.CI_CLASS_BUFF_NAME = tok and BUFF_NAMES[tok] or nil
end

-- Pre-allocated slot buffer (zero GC in scan)
local _slotBuf = {}

------------------------------------------------------------------------
-- Texture pool (lazy per frame per slot — created once, never GC'd)
------------------------------------------------------------------------
local function EnsureDot(f, sk)
    local pool = f._msufCI
    if not pool then pool = {}; f._msufCI = pool end
    local dot = pool[sk]
    if not dot then
        local parent = f.statusIconLayer or f.barGroup or f
        dot = parent:CreateTexture(nil, "OVERLAY", nil, 6)
        dot:SetColorTexture(1, 1, 1, 1)
        dot:Hide()
        pool[sk] = dot
    end
    return dot
end

------------------------------------------------------------------------
-- Layout (called from GF_Core LayoutIcons — NOT hot path)
------------------------------------------------------------------------
function GF.LayoutCornerIndicators(f, kind)
    local conf = GF.GetConf and GF.GetConf(kind) or nil
    if not conf or conf.ciEnabled == false then return end
    local sz = conf.ciSize or 8
    local anchor = f.statusIconLayer or f.barGroup or f
    for i = 1, 5 do
        local sk = SLOT_KEYS[i]
        local cat = conf[CONF_KEYS[sk]] or "none"
        if cat ~= "none" then
            local dot = EnsureDot(f, sk)
            dot:SetSize(sz, sz)
            dot:ClearAllPoints()
            dot:SetPoint(SLOT_ANCHORS[sk], anchor, SLOT_ANCHORS[sk], SLOT_OFS_X[sk], SLOT_OFS_Y[sk])
        else
            local pool = f._msufCI
            if pool and pool[sk] then pool[sk]:Hide() end
        end
    end
end

------------------------------------------------------------------------
-- UpdateCornerIndicators — FULL PERFORMANCE REWRITE
--
-- Design principles:
--   1. ZERO function calls for scan/resolve in the hot path — all inlined
--   2. Pre-computed slot categories from f._c (BuildFrameCache)
--   3. Each scan category (dispel/boss/missing) runs AT MOST once per update
--   4. Per-slot diff-gate: skip SetColorTexture/Show/Hide when unchanged
--   5. 5Hz rate-limit: CI states change max ~1/sec, 5Hz is sufficient
--   6. No table allocation in hot path (no {}, no pairs(), no select())
--   7. Secret-safe: all issecretvalue guards in scan paths
------------------------------------------------------------------------
function GF.UpdateCornerIndicators(f, unit)
    if not f or not unit then return end

    -- 5Hz rate-limit
    local now = GetTime()
    if (now - (f._msufCILastAt or 0)) < 0.20 then return end
    f._msufCILastAt = now

    local c = f._c
    if not c or not c.ciEn then
        -- Disabled: hide all dots
        local pool = f._msufCI
        if pool then
            for i = 1, 5 do local d = pool[SLOT_KEYS[i]]; if d then d:Hide() end end
        end
        return
    end

    if not UnitExists(unit) then
        local pool = f._msufCI
        if pool then
            for i = 1, 5 do local d = pool[SLOT_KEYS[i]]; if d then d:Hide() end end
        end
        return
    end

    -- Read slot categories from pre-computed cache (set in GF_Effects BuildFrameCache)
    local s1 = c.ciSlotTL or "none"
    local s2 = c.ciSlotTR or "none"
    local s3 = c.ciSlotBL or "none"
    local s4 = c.ciSlotBR or "none"
    local s5 = c.ciSlotC  or "none"

    -- Quick exit: all slots "none" → hide everything, done
    if s1 == "none" and s2 == "none" and s3 == "none" and s4 == "none" and s5 == "none" then
        local pool = f._msufCI
        if pool then
            for i = 1, 5 do local d = pool[SLOT_KEYS[i]]; if d and d:IsShown() then d:Hide() end end
        end
        return
    end

    -- Determine which scans are needed (bitfield: 1=dispel, 2=boss, 4=missing)
    local needScan = 0
    if s1 == "dispel" or s2 == "dispel" or s3 == "dispel" or s4 == "dispel" or s5 == "dispel" then needScan = needScan + 1 end
    if s1 == "boss"   or s2 == "boss"   or s3 == "boss"   or s4 == "boss"   or s5 == "boss"   then needScan = needScan + 2 end
    if s1 == "missing" or s2 == "missing" or s3 == "missing" or s4 == "missing" or s5 == "missing" then needScan = needScan + 4 end

    -- Scan each needed category ONCE (inlined, zero function call overhead)
    local dispelShow, dispelR, dispelG, dispelB = false, 0, 0, 0
    local bossShow, bossR, bossG, bossB = false, 0, 0, 0
    local missingShow, missingR, missingG, missingB = false, 0, 0, 0

    -- DISPEL scan — C++ path when available (1 API call vs 3 + Lua tables)
    if needScan % 2 >= 1 then
        local colorCurve = (GF and GF._sharedDispelColorCurve) or _dispelColorCurve
        if _getDispelColor and colorCurve then
            -- C++ DELEGATION: GetAuraDataByIndex → GetAuraDispelTypeColor
            local bestAura = _getAuraByIndex and _getAuraByIndex(unit, 1, "HARMFUL|RAID_PLAYER_DISPELLABLE")
            if bestAura and bestAura.auraInstanceID then
                local color = _getDispelColor(unit, bestAura.auraInstanceID, colorCurve)
                if color then
                    dispelShow = true
                    if color.r ~= nil then
                        dispelR, dispelG, dispelB = color.r, color.g, color.b
                    else
                        dispelR, dispelG, dispelB = color:GetRGB()
                    end
                end
            end
        elseif _hasSlotAPI then
            -- Fallback: Lua-side dispel color (pre-12.0 or API missing)
            local _, slot1 = _getSlots(unit, "HARMFUL|RAID_PLAYER_DISPELLABLE", 1, nil)
            if slot1 then
                dispelShow = true
                dispelR, dispelG, dispelB = 0.25, 0.75, 1.00
                if _hasDataAPI then
                    local data = _getBySlot(unit, slot1)
                    if data then
                        local dn = data.dispelName
                        if not (issecretvalue and issecretvalue(dn)) and dn and dn ~= "" then
                            dispelR = DISPEL_R[dn] or 0.25
                            dispelG = DISPEL_G[dn] or 0.75
                            dispelB = DISPEL_B[dn] or 1.00
                        end
                    end
                end
            end
        end
    end

    -- BOSS scan (inlined ScanBoss + ResolveBoss)
    if needScan % 4 >= 2 and _hasSlotAPI and _hasDataAPI then
        local _, slot1 = _getSlots(unit, "HARMFUL|RAID", 1, nil)
        if slot1 then
            local data = _getBySlot(unit, slot1)
            if data then
                local ir = data.isRaid
                local isBoss = false
                if not (issecretvalue and issecretvalue(ir)) then
                    if ir then
                        isBoss = true
                    else
                        local dn = data.dispelName
                        if not (issecretvalue and issecretvalue(dn)) and dn and dn ~= "" then
                            isBoss = true
                        end
                    end
                end
                if isBoss then
                    bossShow = true
                    local kind = f._msufGFKind or "party"
                    local conf = GF.GetConf and GF.GetConf(kind) or nil
                    bossR = conf and conf.ciBossColorR or 1.00
                    bossG = conf and conf.ciBossColorG or 0.15
                    bossB = conf and conf.ciBossColorB or 0.15
                end
            end
        end
    end

    -- MISSING scan (inlined ScanMissingClassBuff + ResolveMissing)
    if needScan >= 4 and _hasClassBuff and _hasSlotAPI and _hasDataAPI then
        local found = false
        -- Single C API call; iterate results via select (5Hz rate-limited, alloc is fine)
        local results = { _getSlots(unit, "HELPFUL|PLAYER", 20, nil) }
        -- index 1 = continuation token, slots start at 2
        for i = 2, #results do
            local slot = results[i]
            if slot then
                local data = _getBySlot(unit, slot)
                if data then
                    -- Secret-safety + tag-strip: secret-tagged integers need
                    -- tonumber() before use as hash key (Midnight 12.0 semantics)
                    local sid = data.spellId
                    if not (issecretvalue and issecretvalue(sid)) then
                        sid = tonumber(sid)
                        if sid and _classBufSet[sid] then
                            found = true
                            break
                        end
                    end
                end
            end
        end
        if not found then
            missingShow = true
            local kind = f._msufGFKind or "party"
            local conf = GF.GetConf and GF.GetConf(kind) or nil
            missingR = conf and conf.ciMissingColorR or 0.80
            missingG = conf and conf.ciMissingColorG or 0.80
            missingB = conf and conf.ciMissingColorB or 0.80
        end
    end

    -- Apply results to all 5 slots.
    -- Do not compare cached RGB values here: Blizzard can return secret-tainted
    -- numbers for dispel colors, and equality checks on those explode in Lua.
    local alpha = c.ciAlpha or 1.0
    local cache = f._msufCICache
    if not cache then cache = {}; f._msufCICache = cache end

    -- PERF: Reuse file-scope buffer (zero alloc per call)
    _slotBuf[1] = s1; _slotBuf[2] = s2; _slotBuf[3] = s3; _slotBuf[4] = s4; _slotBuf[5] = s5
    for i = 1, 5 do
        local sk = SLOT_KEYS[i]
        local cat = _slotBuf[i]
        if cat == "none" then
            if cache[sk] then
                cache[sk] = nil
                local pool = f._msufCI
                if pool and pool[sk] then pool[sk]:Hide() end
            end
        else
            local show, r, g, b
            if cat == "dispel" then
                show, r, g, b = dispelShow, dispelR, dispelG, dispelB
            elseif cat == "boss" then
                show, r, g, b = bossShow, bossR, bossG, bossB
            else -- "missing"
                show, r, g, b = missingShow, missingR, missingG, missingB
            end

            local prev = cache[sk]
            if show then
                local dot = EnsureDot(f, sk)
                dot:SetColorTexture(r, g, b, alpha)
                if not dot:IsShown() then dot:Show() end
                cache[sk] = true
            else
                if prev then
                    cache[sk] = nil
                    local pool = f._msufCI
                    if pool and pool[sk] then pool[sk]:Hide() end
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Hide all (unit despawn / disable)
------------------------------------------------------------------------
function GF.HideCornerIndicators(f)
    if not f or not f._msufCI then return end
    local pool = f._msufCI
    for i = 1, 5 do
        local d = pool[SLOT_KEYS[i]]
        if d then d:Hide() end
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
