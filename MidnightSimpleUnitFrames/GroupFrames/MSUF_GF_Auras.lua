-- MSUF_GF_Auras.lua — Group Frames: 3-Group Aura Display (Buffs / Debuffs / Externals)
-- Replaces Phase 4 flat system. Each group has independent anchor, growth, icon pool.
-- GetAuraSlots + GetAuraDataBySlot scan (EQoL proven pattern).
-- Externals use BIG_DEFENSIVE filter; buff scan excludes externals IDs to prevent dupes.
-- Midnight 12.0 secret-safe, zero combat overhead, zero-alloc icon pools.
local _, ns = ...
ns = ns or (_G and _G.MSUF_NS) or {}
if _G then _G.MSUF_NS = ns end

local GF = ns.GF
if not GF then return end

local issecretvalue = _G.issecretvalue
local C_UnitAuras   = _G.C_UnitAuras
local CreateFrame   = _G.CreateFrame
local UnitExists    = _G.UnitExists
local select        = select
local pairs         = pairs
local type          = type
local math_min      = math.min
local math_max      = math.max
local math_ceil     = math.ceil
local math_floor    = math.floor

------------------------------------------------------------------------
-- C API bindings (deferred to first use)
------------------------------------------------------------------------
local _getDuration, _getStackCount, _apisBound

local function BindAPIs()
    if _apisBound then return end
    _apisBound = true
    if C_UnitAuras then
        _getDuration   = C_UnitAuras.GetAuraDuration
        _getStackCount = C_UnitAuras.GetAuraApplicationDisplayCount
    end
end

------------------------------------------------------------------------
-- Aura slot capture buffer (pre-allocated, zero GC)
------------------------------------------------------------------------
local _slotBuf = {}
local _slotCount = 0

local function CaptureSlots(...)
    local count = select("#", ...)
    for i = 1, count do _slotBuf[i] = select(i, ...) end
    for i = count + 1, _slotCount do _slotBuf[i] = nil end
    _slotCount = count
    return _slotBuf, count
end

local function QuerySlots(unit, filter, maxCount)
    if not (C_UnitAuras and C_UnitAuras.GetAuraSlots) then return _slotBuf, 0 end
    if maxCount then
        return CaptureSlots(C_UnitAuras.GetAuraSlots(unit, filter, maxCount))
    end
    return CaptureSlots(C_UnitAuras.GetAuraSlots(unit, filter))
end

------------------------------------------------------------------------
-- Filter strings
------------------------------------------------------------------------
local FILTERS = {
    HELPFUL_RAID_PLAYER       = "HELPFUL|INCLUDE_NAME_PLATE_ONLY|RAID|PLAYER",
    HELPFUL_RAID_COMBAT       = "HELPFUL|INCLUDE_NAME_PLATE_ONLY|RAID_IN_COMBAT|PLAYER",
    HELPFUL_ALL_PLAYER        = "HELPFUL|INCLUDE_NAME_PLATE_ONLY|PLAYER",
    HARMFUL                   = "HARMFUL|INCLUDE_NAME_PLATE_ONLY",
    BIG_DEFENSIVE             = "HELPFUL|BIG_DEFENSIVE",
}

local function ResolveBuffFilter(filterMode)
    if filterMode == "RAID_IN_COMBAT" then return FILTERS.HELPFUL_RAID_COMBAT end
    if filterMode == "ALL_PLAYER" then return FILTERS.HELPFUL_ALL_PLAYER end
    return FILTERS.HELPFUL_RAID_PLAYER
end

------------------------------------------------------------------------
-- Growth decomposition: "LEFTUP" → xMul=-1, yMul=1, primary=X, etc.
------------------------------------------------------------------------
local GROWTH_TABLE = {
    RIGHTDOWN = { px =  1, py =  0, sx =  0, sy = -1 },
    RIGHTUP   = { px =  1, py =  0, sx =  0, sy =  1 },
    LEFTDOWN  = { px = -1, py =  0, sx =  0, sy = -1 },
    LEFTUP    = { px = -1, py =  0, sx =  0, sy =  1 },
    DOWNRIGHT = { px =  0, py = -1, sx =  1, sy =  0 },
    DOWNLEFT  = { px =  0, py = -1, sx = -1, sy =  0 },
    UPRIGHT   = { px =  0, py =  1, sx =  1, sy =  0 },
    UPLEFT    = { px =  0, py =  1, sx = -1, sy =  0 },
}

local function GetGrowthVectors(growth)
    return GROWTH_TABLE[growth] or GROWTH_TABLE.RIGHTDOWN
end

------------------------------------------------------------------------
-- Dispel type border colors
------------------------------------------------------------------------
local DISPEL_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
}

------------------------------------------------------------------------
-- Icon creation (global recycler pool — avoids CreateFrame in steady-state)
------------------------------------------------------------------------
local _iconRecycler = {}
local _iconRecyclerN = 0
local _ICON_RECYCLE_MAX = 32

local function AcquireAuraIcon(parent, size)
    if _iconRecyclerN > 0 then
        local icon = _iconRecycler[_iconRecyclerN]
        _iconRecycler[_iconRecyclerN] = nil
        _iconRecyclerN = _iconRecyclerN - 1
        icon:SetParent(parent)
        icon:SetSize(size, size)
        icon:SetBackdropBorderColor(0, 0, 0, 1)
        if icon.texture then icon.texture:SetTexCoord(0, 1, 0, 1); icon.texture:SetDesaturated(false) end
        if icon.cooldown then icon.cooldown:Clear() end
        if icon.count then icon.count:SetText(""); icon.count:Hide() end
        return icon
    end
    return nil
end

local function RecycleAuraIcon(icon)
    if not icon or _iconRecyclerN >= _ICON_RECYCLE_MAX then return false end
    icon:Hide()
    icon:ClearAllPoints()
    _iconRecyclerN = _iconRecyclerN + 1
    _iconRecycler[_iconRecyclerN] = icon
    return true
end

local function CreateAuraIcon(parent, size)
    local icon = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    icon:SetSize(size, size)
    icon:EnableMouse(false)

    -- Icon texture — NO SetTexCoord (EQoL pattern: secret icons render via C-side)
    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(icon)
    icon.texture = tex

    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetDrawEdge(true)
    cd:SetDrawSwipe(true)
    cd:SetReverse(true)
    cd:SetHideCountdownNumbers(true)
    icon.cooldown = cd

    -- Overlay above cooldown for count (EQoL pattern: prevents CD frame hiding count)
    local overlay = CreateFrame("Frame", nil, icon)
    overlay:SetAllPoints(icon)
    overlay:SetFrameStrata(cd:GetFrameStrata())
    overlay:SetFrameLevel(cd:GetFrameLevel() + 5)

    local count = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -1, 1)
    count:SetDrawLayer("OVERLAY", 2)
    count:SetJustifyH("RIGHT")
    count:SetTextColor(1, 1, 1, 1)
    count:SetText("")
    count:Hide()
    icon.count = count

    icon:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    icon:SetBackdropColor(0, 0, 0, 0)
    icon:SetBackdropBorderColor(0, 0, 0, 1)
    icon:Hide()
    return icon
end

local function EnsurePool(f, groupKey, count, size, parent)
    local poolKey = "_msufAuraPool_" .. groupKey
    f[poolKey] = f[poolKey] or {}
    local pool = f[poolKey]
    for i = 1, count do
        if not pool[i] then
            pool[i] = AcquireAuraIcon(parent, size) or CreateAuraIcon(parent, size)
        end
        local ic = pool[i]
        ic:SetSize(size, size)
        if ic:GetParent() ~= parent then ic:SetParent(parent) end
        if parent.GetFrameLevel then
            ic:SetFrameLevel(parent:GetFrameLevel() + 2)
        end
    end
    return pool
end

local function HidePool(pool, startIdx)
    if not pool then return end
    for i = startIdx, #pool do
        if pool[i] then pool[i]:Hide() end
    end
end

------------------------------------------------------------------------
-- Container creation (one per group per frame, lazy)
------------------------------------------------------------------------
local function EnsureContainer(f, groupKey)
    local cKey = "_msufAuraCont_" .. groupKey
    local cont = f[cKey]
    if not cont then
        local parent = f.statusIconLayer or f.barGroup or f
        cont = CreateFrame("Frame", nil, parent)
        cont:EnableMouse(false)
        f[cKey] = cont
    end
    return cont
end

------------------------------------------------------------------------
-- Position an icon within its group container
------------------------------------------------------------------------
local function PositionIcon(ic, anchor, container, idx, perRow, size, spacing, gv)
    ic:ClearAllPoints()
    local col = (idx - 1) % perRow
    local row = math_floor((idx - 1) / perRow)
    local step = size + spacing
    local ox = col * step * gv.px + row * step * gv.sx
    local oy = col * step * gv.py + row * step * gv.sy
    ic:SetPoint(anchor, container, anchor, ox, oy)
end

------------------------------------------------------------------------
-- Apply cooldown (SetCooldownFromDurationObject — only secret-safe path)
------------------------------------------------------------------------
local function ApplyCooldown(ic, unit, auraInstanceID, showCd)
    local cd = ic.cooldown
    if not cd then return end
    if not showCd then cd:Clear(); return end
    if not _apisBound then BindAPIs() end
    if not _getDuration or not auraInstanceID then cd:Clear(); return end
    local obj = _getDuration(unit, auraInstanceID)
    if obj ~= nil then
        local fn = cd.SetCooldownFromDurationObject
        if fn then fn(cd, obj); return end
    end
    cd:Clear()
end

------------------------------------------------------------------------
-- Apply stack count (secret-safe)
------------------------------------------------------------------------
local function ApplyStacks(ic, unit, auraInstanceID, applications, showStacks, cfg)
    local fs = ic.count
    if not fs then return end
    if not showStacks then fs:SetText(""); fs:Hide(); return end

    -- EQoL pattern: use GetAuraApplicationDisplayCount for display (handles secrets C-side)
    if not _apisBound then BindAPIs() end
    if _getStackCount and auraInstanceID then
        local display = _getStackCount(unit, auraInstanceID, 2, 99)
        if display ~= nil then
            -- SetText accepts secret values natively (C-side renders)
            fs:SetText(display)
            fs:Show()
            return
        end
    end

    -- Fallback: direct applications field
    if applications ~= nil then
        if issecretvalue and issecretvalue(applications) then
            fs:SetText("?"); fs:Show(); return
        end
        local n = tonumber(applications)
        if n and n >= 2 then fs:SetText(n); fs:Show(); return end
    end

    fs:SetText(""); fs:Hide()
end

------------------------------------------------------------------------
-- Apply dispel-type border (debuffs only)
------------------------------------------------------------------------
local function ApplyDispelBorder(ic, unit, auraInstanceID, dispelName, isHarmful, showDispel)
    if not isHarmful or not showDispel then
        ic:SetBackdropBorderColor(0, 0, 0, 1); return
    end
    -- Plain dispelName lookup (non-secret only)
    if dispelName ~= nil and not (issecretvalue and issecretvalue(dispelName)) then
        local c = DISPEL_COLORS[dispelName]
        if c then ic:SetBackdropBorderColor(c[1], c[2], c[3], 1); return end
    end
    -- Default red for unknown/secret debuffs
    ic:SetBackdropBorderColor(0.8, 0, 0, 1)
end

------------------------------------------------------------------------
-- Apply cooldown text config (anchor/offset/size/outline)
------------------------------------------------------------------------
local function ConfigureCooldownText(cd, showCd)
    if not cd then return end
    cd:SetHideCountdownNumbers(not showCd)
end

------------------------------------------------------------------------
-- Resolve group config from DB
------------------------------------------------------------------------
local function GetGroupCfg(kind, groupKey)
    local conf = GF.GetConf(kind)
    local auras = conf.auras
    if not auras then return nil end
    return auras[groupKey]
end

------------------------------------------------------------------------
-- Externals exclusion set (reused per frame update)
------------------------------------------------------------------------
local _externalsIDs = {}

------------------------------------------------------------------------
-- Scan + render one aura group
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Dynamic content scale (auto-shrink icons in large raids)
------------------------------------------------------------------------
local GetNumGroupMembers = _G.GetNumGroupMembers

local function GetDynamicScale(conf)
    if not conf or not conf.auras or not conf.auras.dynamicScale then return 1 end
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if n <= 15 then return 1 end
    if n <= 25 then return 0.85 end
    return 0.70
end

------------------------------------------------------------------------
-- Main render: one aura group
------------------------------------------------------------------------
local function RenderGroup(f, unit, groupKey, gcfg, filter, isHarmful, parent, dedupIDs, scale)
    if not gcfg or gcfg.enabled == false then
        HidePool(f["_msufAuraPool_" .. groupKey], 1)
        return 0
    end

    local maxIcons = gcfg.max or 6
    local iconSize = gcfg.size or 20
    if scale and scale ~= 1 then
        iconSize = math_max(8, math_floor(iconSize * scale + 0.5))
    end
    local anchor   = gcfg.anchor or "BOTTOMLEFT"
    local growth   = gcfg.growth or "RIGHTDOWN"
    local spacing  = gcfg.spacing or 1
    local perRow   = gcfg.perRow or maxIcons
    local showDisp = gcfg.showDispelBorder ~= false

    local gv = GetGrowthVectors(growth)
    local container = EnsureContainer(f, groupKey)
    container:ClearAllPoints()
    container:SetPoint(anchor, parent, anchor, gcfg.x or 0, gcfg.y or 0)
    container:SetSize(1, 1) -- auto-sized by icon positions
    local wantLvl = parent:GetFrameLevel() + (gcfg.layer or 5)
    if container._msufCachedLvl ~= wantLvl then
        container._msufCachedLvl = wantLvl
        container:SetFrameLevel(wantLvl)
    end
    container:Show()

    local pool = EnsurePool(f, groupKey, maxIcons, iconSize, container)
    local slots, slotCount = QuerySlots(unit, filter, maxIcons + 1) -- +1 for continuation token
    local shown = 0

    for i = 2, slotCount do
        if shown >= maxIcons then break end
        local aura = C_UnitAuras.GetAuraDataBySlot(unit, slots[i])
        if aura then
            local aid = aura.auraInstanceID -- always non-secret
            -- Skip if claimed by externals or tracked by SpellIndicators
            if (groupKey == "buff" and aid and _externalsIDs[aid])
               or (dedupIDs and aid and dedupIDs[aid]) then
                -- skip
            else
                shown = shown + 1
                local ic = pool[shown]
                if ic then
                    -- aura.icon may be secret; SetTexture C-side accepts it natively
                    ic.texture:SetTexture(aura.icon or "")
                    ic.texture:Show()
                    ApplyCooldown(ic, unit, aid, gcfg.showCooldown ~= false)
                    ConfigureCooldownText(ic.cooldown, gcfg.showCooldown ~= false)
                    ApplyStacks(ic, unit, aid, aura.applications, gcfg.showStacks ~= false, gcfg)
                    if isHarmful then
                        ApplyDispelBorder(ic, unit, aid, aura.dispelName, true, showDisp)
                    else
                        ic:SetBackdropBorderColor(0, 0, 0, 1)
                    end
                    PositionIcon(ic, anchor, container, shown, perRow, iconSize, spacing, gv)
                    ic:Show()
                    -- Track externals IDs for buff dedup (auraInstanceID is always non-secret)
                    if groupKey == "externals" and aid then
                        _externalsIDs[aid] = true
                    end
                end
            end
        end
    end

    HidePool(pool, shown + 1)
    return shown
end

------------------------------------------------------------------------
-- Main entry: UpdateFrameAuras (orchestrator for 3 groups)
------------------------------------------------------------------------
function GF.UpdateFrameAuras(f, unit)
    if not f or not unit then return end
    if not UnitExists(unit) then
        HidePool(f._msufAuraPool_buff, 1)
        HidePool(f._msufAuraPool_debuff, 1)
        HidePool(f._msufAuraPool_externals, 1)
        return
    end
    if not C_UnitAuras or not C_UnitAuras.GetAuraSlots or not C_UnitAuras.GetAuraDataBySlot then
        return
    end

    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    local auras = conf.auras

    if not auras or auras.enabled == false then
        HidePool(f._msufAuraPool_buff, 1)
        HidePool(f._msufAuraPool_debuff, 1)
        HidePool(f._msufAuraPool_externals, 1)
        return
    end

    local parent = f.statusIconLayer or f.barGroup or f
    local scale = GetDynamicScale(conf)

    -- Clear externals exclusion set
    for k in pairs(_externalsIDs) do _externalsIDs[k] = nil end

    -- 1) Externals first (so we can exclude from buffs)
    local extCfg = auras.externals
    if extCfg and extCfg.enabled then
        RenderGroup(f, unit, "externals", extCfg, FILTERS.BIG_DEFENSIVE, false, parent, nil, scale)
    else
        HidePool(f._msufAuraPool_externals, 1)
    end

    -- 2) Debuffs
    local debCfg = auras.debuff
    RenderGroup(f, unit, "debuff", debCfg, FILTERS.HARMFUL, true, parent, nil, scale)

    -- 3) Buffs (excludes externals IDs + SI-tracked IDs)
    local buffCfg = auras.buff
    local buffFilter = ResolveBuffFilter(buffCfg and buffCfg.filterMode)
    RenderGroup(f, unit, "buff", buffCfg, buffFilter, false, parent, f._msufSIDedupIDs, scale)
end

------------------------------------------------------------------------
-- Hide all aura groups (for unit change / hide)
------------------------------------------------------------------------
function GF.HideFrameAuras(f)
    HidePool(f._msufAuraPool_buff, 1)
    HidePool(f._msufAuraPool_debuff, 1)
    HidePool(f._msufAuraPool_externals, 1)
    local contKeys = { "_msufAuraCont_buff", "_msufAuraCont_debuff", "_msufAuraCont_externals" }
    for i = 1, 3 do
        local c = f[contKeys[i]]
        if c then c:Hide() end
    end
end

------------------------------------------------------------------------
-- Preview: mock aura icons (no real unit, static textures)
------------------------------------------------------------------------
do
    -- Well-known buff/debuff/external textures for preview
    local MOCK_BUFFS = { 136078, 135932, 135987 }     -- MotW, AI, Fortitude
    local MOCK_DEBUFFS = { 136157, 136182 }           -- Curse, Disease
    local MOCK_EXTERNALS = { 135936, 572025 }         -- Pain Supp, Ironbark
    local MOCK_DISPELS = { nil, "Magic", "Curse" }

    function GF.PreviewFrameAuras(f, kind, index)
        if not f then return end
        local conf = GF.GetConf(kind)
        local auras = conf and conf.auras
        if not auras or auras.enabled == false then
            HidePool(f._msufAuraPool_buff, 1)
            HidePool(f._msufAuraPool_debuff, 1)
            HidePool(f._msufAuraPool_externals, 1)
            return
        end

        local parent = f.statusIconLayer or f.barGroup or f

        -- Buffs
        local buffCfg = auras.buff
        if buffCfg and buffCfg.enabled ~= false then
            local size = buffCfg.size or 20
            local anchor = buffCfg.anchor or "BOTTOMLEFT"
            local growth = buffCfg.growth or "RIGHTDOWN"
            local spacing = buffCfg.spacing or 1
            local perRow = buffCfg.perRow or 4
            local maxShow = math_min(#MOCK_BUFFS, buffCfg.max or 6)
            local gv = GetGrowthVectors(growth)
            local container = EnsureContainer(f, "buff")
            container:ClearAllPoints()
            container:SetPoint(anchor, parent, anchor, buffCfg.x or 0, buffCfg.y or 0)
            container:SetSize(1, 1)
            do local wl = parent:GetFrameLevel() + (buffCfg.layer or 5)
                if container._msufCachedLvl ~= wl then container._msufCachedLvl = wl; container:SetFrameLevel(wl) end
            end
            container:Show()
            local pool = EnsurePool(f, "buff", maxShow, size, container)
            for i = 1, maxShow do
                local ic = pool[i]
                if ic then
                    ic.texture:SetTexture(MOCK_BUFFS[i])
                    ic.texture:Show()
                    if ic.cooldown then ic.cooldown:Clear() end
                    if ic.count then ic.count:SetText(""); ic.count:Hide() end
                    ic:SetBackdropBorderColor(0, 0, 0, 1)
                    PositionIcon(ic, anchor, container, i, perRow, size, spacing, gv)
                    ic:Show()
                end
            end
            HidePool(pool, maxShow + 1)
        else
            HidePool(f._msufAuraPool_buff, 1)
        end

        -- Debuffs
        local debCfg = auras.debuff
        if debCfg and debCfg.enabled ~= false then
            local size = debCfg.size or 20
            local anchor = debCfg.anchor or "TOPLEFT"
            local growth = debCfg.growth or "RIGHTDOWN"
            local spacing = debCfg.spacing or 1
            local perRow = debCfg.perRow or 3
            local maxShow = math_min(#MOCK_DEBUFFS, debCfg.max or 6)
            local gv = GetGrowthVectors(growth)
            local container = EnsureContainer(f, "debuff")
            container:ClearAllPoints()
            container:SetPoint(anchor, parent, anchor, debCfg.x or 0, debCfg.y or 0)
            container:SetSize(1, 1)
            do local wl = parent:GetFrameLevel() + (debCfg.layer or 6)
                if container._msufCachedLvl ~= wl then container._msufCachedLvl = wl; container:SetFrameLevel(wl) end
            end
            container:Show()
            local pool = EnsurePool(f, "debuff", maxShow, size, container)
            for i = 1, maxShow do
                local ic = pool[i]
                if ic then
                    ic.texture:SetTexture(MOCK_DEBUFFS[i])
                    ic.texture:Show()
                    if ic.cooldown then ic.cooldown:Clear() end
                    if ic.count then ic.count:SetText(""); ic.count:Hide() end
                    local disp = MOCK_DISPELS[i]
                    local showDisp = debCfg.showDispelBorder ~= false
                    if disp and showDisp then
                        local dc = DISPEL_COLORS[disp]
                        if dc then ic:SetBackdropBorderColor(dc[1], dc[2], dc[3], 1)
                        else ic:SetBackdropBorderColor(0.8, 0, 0, 1) end
                    else
                        ic:SetBackdropBorderColor(0.8, 0, 0, 1)
                    end
                    PositionIcon(ic, anchor, container, i, perRow, size, spacing, gv)
                    ic:Show()
                end
            end
            HidePool(pool, maxShow + 1)
        else
            HidePool(f._msufAuraPool_debuff, 1)
        end

        -- Externals
        local extCfg = auras.externals
        if extCfg and extCfg.enabled and index == 1 then
            local size = extCfg.size or 28
            local anchor = extCfg.anchor or "CENTER"
            local growth = extCfg.growth or "RIGHTDOWN"
            local spacing = extCfg.spacing or 1
            local perRow = extCfg.perRow or 3
            local maxShow = math_min(#MOCK_EXTERNALS, extCfg.max or 2)
            local gv = GetGrowthVectors(growth)
            local container = EnsureContainer(f, "externals")
            container:ClearAllPoints()
            container:SetPoint(anchor, parent, anchor, extCfg.x or 0, extCfg.y or 0)
            container:SetSize(1, 1)
            do local wl = parent:GetFrameLevel() + (extCfg.layer or 7)
                if container._msufCachedLvl ~= wl then container._msufCachedLvl = wl; container:SetFrameLevel(wl) end
            end
            container:Show()
            local pool = EnsurePool(f, "externals", maxShow, size, container)
            for i = 1, maxShow do
                local ic = pool[i]
                if ic then
                    ic.texture:SetTexture(MOCK_EXTERNALS[i])
                    ic.texture:Show()
                    if ic.cooldown then ic.cooldown:Clear() end
                    if ic.count then ic.count:SetText(""); ic.count:Hide() end
                    ic:SetBackdropBorderColor(0, 0, 0, 1)
                    PositionIcon(ic, anchor, container, i, perRow, size, spacing, gv)
                    ic:Show()
                end
            end
            HidePool(pool, maxShow + 1)
        else
            HidePool(f._msufAuraPool_externals, 1)
        end
    end
end

------------------------------------------------------------------------
GF.GetDynamicScale = GetDynamicScale
_G.MSUF_GF_UpdateFrameAuras = GF.UpdateFrameAuras
