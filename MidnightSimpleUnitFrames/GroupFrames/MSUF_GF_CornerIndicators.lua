-- MSUF_GF_CornerIndicators.lua — Group Frames: Corner Indicator Dots
-- FULL PERFORMANCE REWRITE — zero unnecessary function calls in hot path.
-- 5 fixed slots (TL/TR/BL/BR/C) showing colored dots for at-a-glance info:
--   "dispel"  — dispellable debuff present  (HARMFUL|RAID_PLAYER_DISPELLABLE)
--                  → C++ ColorCurve, fully secret-safe
--   "aggro"   — unit has aggro/threat       (reads f._msufGFAggroLevel cache)
--                  → secret-safe (cache populated by GF UpdateAggro)
--   "custom"  — user-defined spell ID list  (scan with secret guard)
--                  → user controls filter (HELPFUL|PLAYER best, others limited)
-- Midnight 12.0 secret-safe, zero combat overhead when disabled.
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

-- Localize everything at file scope (zero global lookups in hot path)
local issecretvalue = _G.issecretvalue
local UnitExists    = _G.UnitExists
local GetTime       = _G.GetTime
local type          = type
local tonumber      = tonumber
local strmatch      = string.match
local strgmatch     = string.gmatch

-- C API (resolved once at load)
local _getSlots       = _G.C_UnitAuras and _G.C_UnitAuras.GetAuraSlots
local _getBySlot      = _G.C_UnitAuras and _G.C_UnitAuras.GetAuraDataBySlot
local _getAuraByIndex = _G.C_UnitAuras and _G.C_UnitAuras.GetAuraDataByIndex
local _hasSlotAPI = (type(_getSlots) == "function")
local _hasDataAPI = (type(_getBySlot) == "function")

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local SLOT_KEYS    = { "TL", "TR", "BL", "BR", "C" }
local SLOT_ANCHORS = { TL = "TOPLEFT", TR = "TOPRIGHT", BL = "BOTTOMLEFT", BR = "BOTTOMRIGHT", C = "CENTER" }
local SLOT_OFS_X   = { TL =  2, TR = -2, BL =  2, BR = -2, C = 0 }
local SLOT_OFS_Y   = { TL = -2, TR = -2, BL =  2, BR =  2, C = 0 }

------------------------------------------------------------------------
-- Dispel: C++ ColorCurve (secret-safe, zero Lua arithmetic)
------------------------------------------------------------------------
local DISPEL_CURVE_POINTS = {
    { id = 0,  r = 0.25, g = 0.75, b = 1.00 },
    { id = 1,  r = 0.25, g = 0.75, b = 1.00 },
    { id = 2,  r = 0.60, g = 0.00, b = 1.00 },
    { id = 3,  r = 0.60, g = 0.40, b = 0.00 },
    { id = 4,  r = 0.00, g = 0.60, b = 0.00 },
    { id = 9,  r = 0.80, g = 0.00, b = 0.00 },
    { id = 11, r = 0.80, g = 0.00, b = 0.00 },
}

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
local _getDispelColor = _hasDispelColorAPI and _G.C_UnitAuras.GetAuraDispelTypeColor

-- Fallback Lua-side dispel colors (used only if ColorCurve API missing)
local DISPEL_R = { Magic = 0.25, Curse = 0.60, Poison = 0.00, Disease = 0.60, Bleed = 0.80 }
local DISPEL_G = { Magic = 0.75, Curse = 0.00, Poison = 0.60, Disease = 0.40, Bleed = 0.00 }
local DISPEL_B = { Magic = 1.00, Curse = 1.00, Poison = 0.00, Disease = 0.00, Bleed = 0.00 }

------------------------------------------------------------------------
-- Custom spell list parsing — lazy, cached per slot config
-- Stored as comma/space-separated string; parsed to set on first use.
-- Cache invalidated when raw string changes (cc._setStamp ~= cc.spells).
------------------------------------------------------------------------
local function _ParseSpellList(cc)
    if cc._setStamp == cc.spells then return cc._set end
    local set = {}
    local raw = cc.spells
    if type(raw) == "string" and raw ~= "" then
        for sid in strgmatch(raw, "(%d+)") do
            local n = tonumber(sid)
            if n and n > 0 then set[n] = true end
        end
    end
    cc._set = set
    cc._setStamp = raw
    cc._empty = (next(set) == nil) and true or nil
    return set
end

------------------------------------------------------------------------
-- Pre-allocated buffers (zero alloc in hot path)
------------------------------------------------------------------------
local _slotBuf = {}      -- categories per slot (5 entries)
local _scanBuf = {}      -- filter → set of present spell IDs (cleared per call)
local _scanSlotBuf = {}  -- token capture for GetAuraSlots variadic returns
local function _CaptureSlots(...)
    local n = select("#", ...)
    for i = 1, n do _scanSlotBuf[i] = (select(i, ...)) end
    _scanSlotBuf[n + 1] = nil
    return _scanSlotBuf, n
end

------------------------------------------------------------------------
-- Scan a unit with the given filter for matching spell IDs.
-- Returns a set { [spellId]=true } of all PLAIN-tagged matching spell IDs
-- whose IDs are in the wantedSet. Per-call cached by filter (zero re-scan
-- when multiple slots share a filter).
-- SECRET-SAFE: skips secret-tagged spellId entries silently.
------------------------------------------------------------------------
local function _ScanFilterForUnit(unit, filter, wantedSet)
    if not (_hasSlotAPI and _hasDataAPI and unit and filter and wantedSet) then return nil end
    -- Per-call cache lookup: same filter already enumerated → reuse the
    -- presence-set (covers all spellIds seen, not just `wanted`). This is
    -- safe because _scanBuf is wiped at the start of every UpdateCornerIndicators.
    local cached = _scanBuf[filter]
    if cached == nil then
        local present = {}
        local results, n = _CaptureSlots(_getSlots(unit, filter, 40, nil))
        -- index 1 = continuation token, slots start at 2
        for i = 2, n do
            local slot = results[i]
            if slot then
                local data = _getBySlot(unit, slot)
                if data then
                    local sid = data.spellId
                    -- Secret guard: skip secret-tagged (other players' casts in 12.0)
                    if sid ~= nil and not (issecretvalue and issecretvalue(sid)) then
                        sid = tonumber(sid)
                        if sid and sid > 0 then present[sid] = true end
                    end
                end
            end
        end
        _scanBuf[filter] = present
        cached = present
    end
    -- Quick existence test against wantedSet
    for sid in pairs(wantedSet) do
        if cached[sid] then return true end
    end
    return false
end

------------------------------------------------------------------------
-- Dot pool (lazy per frame per slot — created once, never GC'd)
------------------------------------------------------------------------
local function EnsureDot(f, sk)
    local pool = f._msufCI
    if not pool then pool = {}; f._msufCI = pool end
    local parent = f.statusIconLayer or f.barGroup or f
    local d = pool[sk]
    if d and d.GetParent and d:GetParent() ~= parent then
        d:Hide()
        d = nil
    end
    if not d then
        d = parent:CreateTexture(nil, "OVERLAY", nil, 6)
        pool[sk] = d
    elseif d.SetDrawLayer then
        d:SetDrawLayer("OVERLAY", 6)
    end

    local c = f._c
    local sz = (c and c.ciSize) or 8
    d:SetSize(sz, sz)
    d:ClearAllPoints()
    d:SetPoint(SLOT_ANCHORS[sk], parent, SLOT_ANCHORS[sk], SLOT_OFS_X[sk], SLOT_OFS_Y[sk])
    return d
end

------------------------------------------------------------------------
-- Public: layout (size + position) — called from GF render path
------------------------------------------------------------------------
function GF.LayoutCornerIndicators(f, kind)
    if not f then return end
    local conf = GF.GetConf and GF.GetConf(kind or f._msufGFKind or "party")
    local pool = f._msufCI
    if not conf or conf.ciEnabled == false then
        if pool then for i = 1, 5 do local d = pool[SLOT_KEYS[i]]; if d then d:Hide() end end end
        return
    end
    local c = f._c
    local sz = tonumber((c and c.ciSize) or conf.ciSize) or 8
    if sz < 4 then sz = 4 elseif sz > 24 then sz = 24 end
    if not pool then return end
    local parent = f.statusIconLayer or f.barGroup or f
    for i = 1, 5 do
        local sk = SLOT_KEYS[i]
        local d = pool[sk]
        if d then
            if d.GetParent and d:GetParent() ~= parent then
                d:Hide()
                d = parent:CreateTexture(nil, "OVERLAY", nil, 6)
                pool[sk] = d
            elseif d.SetDrawLayer then
                d:SetDrawLayer("OVERLAY", 6)
            end
            d:SetSize(sz, sz)
            d:ClearAllPoints()
            d:SetPoint(SLOT_ANCHORS[sk], parent, SLOT_ANCHORS[sk], SLOT_OFS_X[sk], SLOT_OFS_Y[sk])
        end
    end
end

------------------------------------------------------------------------
-- Per-slot resolution helpers (return show, r, g, b for the slot category)
------------------------------------------------------------------------
local function _ResolveDispel(f, unit)
    if f and f._msufGFDispelKnown then
        local aid = f._msufGFDispelAuraID
        if not aid and not f._msufGFDispelType then return false end
        local color = f._msufGFDispelColorObj
        if color then
            if color.r ~= nil then
                return true, color.r, color.g, color.b
            else
                local r, g, b = color:GetRGB()
                return true, r, g, b
            end
        end
        local dn = f._msufGFDispelType
        return true, DISPEL_R[dn] or 0.25, DISPEL_G[dn] or 0.75, DISPEL_B[dn] or 1.00
    end

    local colorCurve = (GF and GF._sharedDispelColorCurve) or _dispelColorCurve
    if _getDispelColor and colorCurve and _getAuraByIndex then
        local bestAura = _getAuraByIndex(unit, 1, "HARMFUL|RAID_PLAYER_DISPELLABLE")
        if bestAura and bestAura.auraInstanceID then
            local color = _getDispelColor(unit, bestAura.auraInstanceID, colorCurve)
            if color then
                if color.r ~= nil then
                    return true, color.r, color.g, color.b
                else
                    local r, g, b = color:GetRGB()
                    return true, r, g, b
                end
            end
        end
        return false
    end
    -- Fallback: Lua-side dispel color
    if _hasSlotAPI then
        local _, slot1 = _getSlots(unit, "HARMFUL|RAID_PLAYER_DISPELLABLE", 1, nil)
        if slot1 then
            local r, g, b = 0.25, 0.75, 1.00
            if _hasDataAPI then
                local data = _getBySlot(unit, slot1)
                if data then
                    local dn = data.dispelName
                    if not (issecretvalue and issecretvalue(dn)) and dn and dn ~= "" then
                        r = DISPEL_R[dn] or 0.25
                        g = DISPEL_G[dn] or 0.75
                        b = DISPEL_B[dn] or 1.00
                    end
                end
            end
            return true, r, g, b
        end
    end
    return false
end

local function _ResolveAggro(f, conf)
    local lvl = f._msufGFAggroLevel
    if not (lvl and lvl >= 1) then return false end
    -- Default: orange (matches highlight aggro border default)
    local r = conf and conf.ciAggroColorR or 1.00
    local g = conf and conf.ciAggroColorG or 0.55
    local b = conf and conf.ciAggroColorB or 0.00
    return true, r, g, b
end

local function _ResolveCustom(unit, cc)
    if type(cc) ~= "table" then return false end
    local set = _ParseSpellList(cc)
    if cc._empty then return false end
    local filter = cc.filter or "HELPFUL|PLAYER"
    local present = _ScanFilterForUnit(unit, filter, set)
    local mode = cc.mode or "present"
    local show
    if mode == "missing" then
        show = (present == false)
    else
        show = (present == true)
    end
    if not show then return false end
    local r = cc.r or 0.40
    local g = cc.g or 1.00
    local b = cc.b or 0.40
    return true, r, g, b
end

------------------------------------------------------------------------
-- Main update — called from GF event/render dispatch (5Hz rate-limited)
------------------------------------------------------------------------
function GF.UpdateCornerIndicators(f, unit)
    if not f or not unit then return end

    -- 5Hz rate-limit
    local now = GetTime()
    if (now - (f._msufCILastAt or 0)) < 0.20 then return end
    f._msufCILastAt = now

    local c = f._c
    if not c or not c.ciEn then
        local pool = f._msufCI
        if pool then for i = 1, 5 do local d = pool[SLOT_KEYS[i]]; if d then d:Hide() end end end
        f._msufCIHasVisible = nil
        return
    end

    if not UnitExists(unit) then
        local pool = f._msufCI
        if pool then for i = 1, 5 do local d = pool[SLOT_KEYS[i]]; if d then d:Hide() end end end
        f._msufCIHasVisible = nil
        return
    end

    local s1 = c.ciSlotTL or "none"
    local s2 = c.ciSlotTR or "none"
    local s3 = c.ciSlotBL or "none"
    local s4 = c.ciSlotBR or "none"
    local s5 = c.ciSlotC  or "none"

    -- Quick exit: all slots "none"
    if s1 == "none" and s2 == "none" and s3 == "none" and s4 == "none" and s5 == "none" then
        local pool = f._msufCI
        if pool then for i = 1, 5 do local d = pool[SLOT_KEYS[i]]; if d and d:IsShown() then d:Hide() end end end
        f._msufCIHasVisible = nil
        return
    end

    -- Wipe per-call scan cache (custom slots may share filters → dedupe)
    for k in pairs(_scanBuf) do _scanBuf[k] = nil end

    -- Resolve once: dispel + aggro (shared across slots)
    local nativeDispels = c.nativeBlizzardDispels == true
    local allowDispel = c.ciDispel == true
    local allowCustom = c.ciCustom == true
    local needDispel = allowDispel and not nativeDispels
        and (s1 == "dispel" or s2 == "dispel" or s3 == "dispel" or s4 == "dispel" or s5 == "dispel")
    local needAggro  = (s1 == "aggro"  or s2 == "aggro"  or s3 == "aggro"  or s4 == "aggro"  or s5 == "aggro")

    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf and GF.GetConf(kind) or nil

    local dispelShow, dispelR, dispelG, dispelB = false, 0, 0, 0
    if needDispel then
        local ok, r, g, b = _ResolveDispel(f, unit)
        if ok then dispelShow, dispelR, dispelG, dispelB = true, r, g, b end
    end

    local aggroShow, aggroR, aggroG, aggroB = false, 0, 0, 0
    if needAggro then
        local ok, r, g, b = _ResolveAggro(f, conf)
        if ok then aggroShow, aggroR, aggroG, aggroB = true, r, g, b end
    end

    -- Per-slot resolution + apply
    local alpha = c.ciAlpha or 1.0
    local cache = f._msufCICache
    if not cache then cache = {}; f._msufCICache = cache end

    _slotBuf[1] = s1; _slotBuf[2] = s2; _slotBuf[3] = s3; _slotBuf[4] = s4; _slotBuf[5] = s5
    local anyVisible
    for i = 1, 5 do
        local sk = SLOT_KEYS[i]
        local cat = _slotBuf[i]
        local show, r, g, b = false, 0, 0, 0

        if cat == "dispel" and allowDispel then
            show, r, g, b = dispelShow, dispelR, dispelG, dispelB
        elseif cat == "aggro" then
            show, r, g, b = aggroShow, aggroR, aggroG, aggroB
        elseif cat == "custom" and allowCustom then
            -- Per-slot custom config: read directly from conf (5Hz limit makes
            -- this safe perf-wise; avoids needing to extend BuildFrameCache).
            local cc = conf and conf["ciCustom" .. sk]
            if type(cc) == "table" then
                local ok, cr, cg, cb = _ResolveCustom(unit, cc)
                if ok then show, r, g, b = true, cr, cg, cb end
            end
        end
        -- Unknown categories (legacy "boss"/"missing" or typos) → silently hidden

        local prev = cache[sk]
        if show then
            local dot = EnsureDot(f, sk)
            dot:SetColorTexture(r, g, b, alpha)
            if not dot:IsShown() then dot:Show() end
            cache[sk] = true
            anyVisible = true
        else
            if prev then
                cache[sk] = nil
                local pool = f._msufCI
                if pool and pool[sk] then pool[sk]:Hide() end
            end
        end
    end
    f._msufCIHasVisible = anyVisible or nil
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
    f._msufCIHasVisible = nil
end

------------------------------------------------------------------------
-- Expose for Options UI + Preview
------------------------------------------------------------------------
GF.CI_SLOT_KEYS = SLOT_KEYS
GF.CI_CATEGORIES = {
    { key = "none",   label = "None"          },
    { key = "dispel", label = "Dispellable"   },
    { key = "aggro",  label = "Aggro/Threat"  },
    { key = "custom", label = "Custom Spell"  },
}

-- Filter choices for custom slot (exposed for Menu2)
GF.CI_CUSTOM_FILTERS = {
    { key = "HELPFUL|PLAYER", label = "Buff (cast by me)",   secretSafe = true  },
    { key = "HELPFUL",        label = "Buff (any caster)",   secretSafe = false },
    { key = "HARMFUL|PLAYER", label = "Debuff (cast by me)", secretSafe = true  },
    { key = "HARMFUL",        label = "Debuff (any caster)", secretSafe = false },
}

-- Custom mode choices
GF.CI_CUSTOM_MODES = {
    { key = "present", label = "Show when present" },
    { key = "missing", label = "Show when missing" },
}
