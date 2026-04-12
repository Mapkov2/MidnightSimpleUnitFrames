-- MSUF_GF_Auras.lua — Group Frames: 3-Group Aura Display (Buffs / Debuffs / Externals)
-- Replaces Phase 4 flat system. Each group has independent anchor, growth, icon pool.
-- GetAuraSlots + GetAuraDataBySlot scan (EQoL proven pattern).
-- Externals use BIG_DEFENSIVE filter; buff scan excludes externals IDs to prevent dupes.
-- Midnight 12.0 secret-safe, zero combat overhead, zero-alloc icon pools.
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local issecretvalue = _G.issecretvalue
local C_UnitAuras   = _G.C_UnitAuras
local CreateFrame   = _G.CreateFrame
local UnitExists    = _G.UnitExists
local GetTime       = _G.GetTime
local select        = select
local pairs         = pairs
local type          = type
local tonumber      = tonumber
local math_min      = math.min
local math_max      = math.max
local math_ceil     = math.ceil
local math_floor    = math.floor
local GameTooltip   = _G.GameTooltip

------------------------------------------------------------------------
-- Class-based dispel detection (set once at load)
------------------------------------------------------------------------
local _DISPEL_CLASSES = {
    PRIEST=true, PALADIN=true, SHAMAN=true, MONK=true,
    DRUID=true, MAGE=true, EVOKER=true,
}
local _playerCanDispel = false
do
    local _, cls
    if UnitClass then _, cls = UnitClass("player") end
    _playerCanDispel = (cls and _DISPEL_CLASSES[cls]) or false
end
GF._playerCanDispel = _playerCanDispel

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
-- 2-Tier Filter Engine (via MSUF_GF_AuraFilter.lua)
-- Tier 1: Blizzard API tokens (GetAuraSlots filter string)
-- Tier 2: Declassified spell blacklist (categorized, user-toggleable)
------------------------------------------------------------------------
local _AF  -- deferred AuraFilter reference (resolved at first use)
local function AF()
    if _AF then return _AF end
    _AF = GF.AuraFilter or (_G.MSUF_GF_AuraFilter)
    return _AF
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
    -- Centered: icons grow outward from center along primary axis
    CENTER_H  = { px = 1, py = 0, sx = 0, sy = -1, centered = true },
    CENTER_V  = { px = 0, py = -1, sx = 1, sy = 0, centered = true },
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
-- Pre-computed keys (eliminate string concat in hot path)
------------------------------------------------------------------------
local POOL_KEYS = {
    buff      = "_msufAuraPool_buff",
    debuff    = "_msufAuraPool_debuff",
    externals = "_msufAuraPool_externals",
}
local CONT_KEYS = {
    buff      = "_msufAuraCont_buff",
    debuff    = "_msufAuraCont_debuff",
    externals = "_msufAuraCont_externals",
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
        if icon.cooldown then icon.cooldown:Clear(); if icon.cooldown.SetDrawBling then icon.cooldown:SetDrawBling(false) end end
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

    -- Tooltip: hover only, clicks pass through to unit frame beneath
    if icon.SetMouseMotionEnabled then
        icon:SetMouseMotionEnabled(true)
        icon:SetMouseClickEnabled(false)
    else
        icon:EnableMouse(true)
    end
    icon:SetScript("OnEnter", function(self)
        local unit = self._msufUnit
        local aid  = self._msufAuraID
        if not unit or not aid then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        if GameTooltip.SetUnitAuraByAuraInstanceID then
            GameTooltip:SetUnitAuraByAuraInstanceID(unit, aid, self._msufFilter or "HELPFUL")
        end
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)

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
    -- Prevent end-of-cooldown bling/flash (common source of unwanted blinking)
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    icon.cooldown = cd
    -- Guard: GF icons must never carry A2 own-highlight overlays
    icon._msufOwnGlow = false  -- sentinel: _ApplyOwnHighlight exits on falsy

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
    local poolKey = POOL_KEYS[groupKey]
    f[poolKey] = f[poolKey] or {}
    local pool = f[poolKey]
    -- PERF: Skip loop when pool already matches (count/size/parent unchanged)
    if pool._msufPoolOK and pool._msufPoolN == count
       and pool._msufPoolSz == size and pool._msufPoolP == parent then
        return pool
    end
    pool._msufPoolN  = count
    pool._msufPoolSz = size
    pool._msufPoolP  = parent
    pool._msufPoolOK = true
    local pLvl = parent.GetFrameLevel and (parent:GetFrameLevel() + 2) or nil
    local masqueAdd = GF.Masque and GF.Masque.AddButton
    for i = 1, count do
        if not pool[i] then
            pool[i] = AcquireAuraIcon(parent, size) or CreateAuraIcon(parent, size)
            pool[i]._msufGFOwner = f
            if masqueAdd then masqueAdd(pool[i]) end
        end
        local ic = pool[i]
        if ic._msufCachedSz ~= size then
            ic._msufCachedSz = size
            ic:SetSize(size, size)
        end
        if ic:GetParent() ~= parent then ic:SetParent(parent) end
        if pLvl and ic._msufCachedFLvl ~= pLvl then
            ic._msufCachedFLvl = pLvl
            ic:SetFrameLevel(pLvl)
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
    local cKey = CONT_KEYS[groupKey]
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
        if not ic._msufBorderBlack then
            ic._msufBorderBlack = true
            ic:SetBackdropBorderColor(0, 0, 0, 1)
        end
        return
    end
    ic._msufBorderBlack = nil -- clear diff-gate flag (non-black border)
    -- Plain dispelName lookup (non-secret only)
    if not (issecretvalue and issecretvalue(dispelName)) and dispelName ~= nil then
        local c = DISPEL_COLORS[dispelName]
        if c then ic:SetBackdropBorderColor(c[1], c[2], c[3], 1); return end
    end
    -- Default red for unknown/secret debuffs
    ic:SetBackdropBorderColor(0.8, 0, 0, 1)
end

------------------------------------------------------------------------
-- Cached global font resolution (same pattern as A2_Icons.ResolveGlobalFont)
------------------------------------------------------------------------
local _gfCdFontPath, _gfCdFontFlags
local function ResolveGlobalFont()
    if _gfCdFontPath then return _gfCdFontPath, _gfCdFontFlags end
    local gfs = _G.MSUF_GetGlobalFontSettings
    if type(gfs) == "function" then
        local p, fl = gfs()
        if type(p) == "string" then _gfCdFontPath = p end
        if type(fl) == "string" then _gfCdFontFlags = fl end
    end
    if not _gfCdFontPath then
        _gfCdFontPath = GF.ResolveFontPath and GF.ResolveFontPath() or "Fonts\\FRIZQT__.TTF"
        _gfCdFontFlags = GF.ResolveFontFlags and GF.ResolveFontFlags() or "OUTLINE"
    end
    return _gfCdFontPath, _gfCdFontFlags
end

--- Invalidate cached font (called by font options changes)
function GF.InvalidateCdFont()
    _gfCdFontPath = nil
    _gfCdFontFlags = nil
end

------------------------------------------------------------------------
-- Apply cooldown text font (A2 proven pattern: diff-gated, global font,
-- configurable size, lazy FontString discovery via CT module)
------------------------------------------------------------------------
local function ApplyCooldownFont(ic, gcfg)
    local cd = ic and ic.cooldown
    if not cd then return end
    local showCd = gcfg and gcfg.showCooldown ~= false
    cd:SetHideCountdownNumbers(not showCd)
    if not showCd then return end

    -- Discover FontString (A2 pattern: use CT module if available, else EnumerateRegions)
    local fs = cd._msufCooldownFontString
    if fs == false then fs = nil end
    if not fs then
        local A2 = ns.MSUF_Auras2
        local CT = A2 and A2.CooldownText
        local getfs = CT and CT.GetCooldownFontString
        if type(getfs) == "function" then
            fs = getfs(ic, GetTime())
        end
        if not fs and cd.EnumerateRegions then
            for region in cd:EnumerateRegions() do
                if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                    fs = region; break
                end
            end
        end
        if fs then cd._msufCooldownFontString = fs end
    end
    if not fs then return end

    local size = gcfg.cooldownSize or 8
    local gFont, gFlags = ResolveGlobalFont()
    local wantFlags = gcfg.cooldownOutline or gFlags or "OUTLINE"

    -- Diff-gate: skip redundant SetFont (same pattern as A2_Icons line 938)
    if cd._msufGFCdTextSize ~= size or cd._msufGFCdFontPath ~= gFont then
        if gFont and fs.SetFont then
            fs:SetFont(gFont, size, wantFlags)
        end
        cd._msufGFCdTextSize = size
        cd._msufGFCdFontPath = gFont
    end
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
-- Tier 2 filter: decoded spellId blacklist check
-- Uses AuraFilter.DecodeSpellId + AuraFilter.IsBlacklisted
-- Secret spellIds (decoded=0) pass through — only declassified spells
-- can be filtered. This is correct for 12.0.
------------------------------------------------------------------------
-- (All logic lives in MSUF_GF_AuraFilter.lua — nothing to define here)

------------------------------------------------------------------------
-- Scan + render one aura group
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Dynamic content scale (auto-shrink icons in large raids)
-- P1: GetNumGroupMembers cached for 1s — avoids C API call per render.
-- In a 20-man raid, saves 20 C calls/s → 0 C calls/s steady-state.
-- Invalidated automatically by 1s timeout (group size changes are rare;
-- 1s delay before scale adjusts is imperceptible).
------------------------------------------------------------------------
local GetNumGroupMembers = _G.GetNumGroupMembers
local _cachedGroupSize   = 0
local _groupSizeCacheAt  = 0

local function GetCachedGroupSize()
    local now = GetTime()
    if (now - _groupSizeCacheAt) < 1.0 then return _cachedGroupSize end
    _groupSizeCacheAt = now
    _cachedGroupSize = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    return _cachedGroupSize
end

--- Invalidate cache (called by event handlers on GROUP_ROSTER_UPDATE)
function GF.InvalidateGroupSizeCache()
    _groupSizeCacheAt = 0
end

local function GetDynamicScale(conf)
    if not conf or not conf.auras or not conf.auras.dynamicScale then return 1 end
    local n = GetCachedGroupSize()
    if n <= 15 then return 1 end
    if n <= 25 then return 0.85 end
    return 0.70
end

--- Preview variant: uses configured capacity instead of live group size
local function GetPreviewDynamicScale(conf, kind)
    if not conf or not conf.auras or not conf.auras.dynamicScale then return 1 end
    local n = GF.GetPositionCount and GF.GetPositionCount(kind) or 0
    if n <= 15 then return 1 end
    if n <= 25 then return 0.85 end
    return 0.70
end

------------------------------------------------------------------------
-- Main render: one aura group
------------------------------------------------------------------------
local function RenderGroup(f, unit, groupKey, gcfg, filter, isHarmful, parent, dedupIDs, scale)
    if not gcfg or gcfg.enabled == false then
        HidePool(f[POOL_KEYS[groupKey]], 1)
        return 0, nil
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
    local isCentered = gv.centered
    local container = EnsureContainer(f, groupKey)

    -- ── Behind-Bar Mode ─────────────────────────────────────────────
    -- Icons sit BETWEEN barGroup bg and health StatusBar foreground.
    -- Where HP is present → health bar covers icons.
    -- Where HP is missing → icons visible through healthBg tint (alpha ~0.85).
    --
    -- Z-Order:  barGroup bg (N, BG) → icons (N) → healthBg (N+1, BG) → HP fill (N+1, ART)
    -- Icons at barGroup level: above barGroup bg, below healthBg+health fill.
    -- ─────────────────────────────────────────────────────────────────
    local behindBar = gcfg.behindBar and f.health
    local wantParent, wantLvl
    if behindBar then
        wantParent = f.barGroup or f
        wantLvl = wantParent:GetFrameLevel()
    else
        wantParent = parent
        wantLvl = parent:GetFrameLevel() + (gcfg.layer or 5)
    end

    -- Re-parent container if mode changed (diff-gated)
    if container:GetParent() ~= wantParent then
        container:SetParent(wantParent)
        container._msufAnchor = nil
        -- Force pool rebuild (icon parents + frame levels need updating)
        local pool = f[POOL_KEYS[groupKey]]
        if pool then pool._msufPoolOK = nil end
    end

    -- Behind-bar alpha (percentage in DB: 30-100 → 0.30-1.00)
    local wantAlpha = behindBar and ((gcfg.behindBarAlpha or 85) / 100) or 1
    if container._msufCachedAlpha ~= wantAlpha then
        container._msufCachedAlpha = wantAlpha
        container:SetAlpha(wantAlpha)
    end

    -- Diff-gate container position
    local cx = gcfg.x or 0
    local cy = gcfg.y or 0
    local effAnchor = isCentered and "CENTER" or anchor
    local anchorTarget = behindBar and (f.health or wantParent) or wantParent
    if container._msufAnchor ~= effAnchor or container._msufAnchorX ~= cx
       or container._msufAnchorY ~= cy or container._msufAnchorParent ~= anchorTarget then
        container._msufAnchor = effAnchor
        container._msufAnchorX = cx
        container._msufAnchorY = cy
        container._msufAnchorParent = anchorTarget
        container:ClearAllPoints()
        container:SetPoint(effAnchor, anchorTarget, effAnchor, cx, cy)
        container:SetSize(1, 1)
    end
    if container._msufCachedLvl ~= wantLvl then
        container._msufCachedLvl = wantLvl
        container:SetFrameLevel(wantLvl)
    end
    container:Show()

    local pool = EnsurePool(f, groupKey, maxIcons, iconSize, container)

    -- ── Behind-bar icon level fix ────────────────────────────────────
    -- EnsurePool sets icons to container+2 (normal mode: above status icons).
    -- Behind-bar: icons MUST stay at container level (= barGroup level)
    -- so health StatusBar (barGroup+1) renders ON TOP of them.
    -- ─────────────────────────────────────────────────────────────────
    if behindBar then
        for pi = 1, maxIcons do
            local ic = pool[pi]
            if ic and ic._msufCachedFLvl ~= wantLvl then
                ic._msufCachedFLvl = wantLvl
                ic:SetFrameLevel(wantLvl)
            end
        end
    end
    -- Harmful: scan extra slots for merged dispel detection (dispellables sort first)
    local queryLimit = isHarmful and math_max(maxIcons + 1, 12) or (maxIcons + 1)
    local slots, slotCount = QuerySlots(unit, filter, queryLimit)
    local shown = 0
    local isBuff = (groupKey == "buff")
    local isExt  = (groupKey == "externals")
    local showCd = (gcfg.showCooldown ~= false)
    local showStk = (gcfg.showStacks ~= false)
    local step = iconSize + spacing
    local topDispel = nil

    -- Pre-resolve Tier 2 blacklist hash (zero-alloc cached)
    local af = AF()
    local blHash = af and af.BuildBlacklistHash(gcfg) or nil

    for i = 2, slotCount do
        if shown >= maxIcons and (not isHarmful or topDispel) then break end
        local aura = C_UnitAuras.GetAuraDataBySlot(unit, slots[i])
        if aura then
            local aid = aura.auraInstanceID
            if (isBuff and aid and _externalsIDs[aid])
               or (dedupIDs and aid and dedupIDs[aid]) then
                -- skip (claimed by externals or SpellIndicators)
            else
                -- Merged dispel: check during harmful scan (BEFORE spell filter — dispel ignores blacklist)
                if isHarmful and not topDispel then
                    local dn = aura.dispelName
                    if not (issecretvalue and issecretvalue(dn)) and dn ~= nil and dn ~= "" then
                        topDispel = dn
                    else
                        local ir = aura.isRaid
                        if not (issecretvalue and issecretvalue(ir)) and ir then
                            topDispel = "Bleed"
                        end
                    end
                end

                -- Tier 2: Declassified spell blacklist (skip AFTER dispel check)
                local _skip = false
                if blHash and af then
                    local sid = af.DecodeSpellId(aura)
                    if af.IsBlacklisted(sid, blHash) then
                        _skip = true
                    end
                end

                if _skip then
                    -- filtered — dispel was already checked above
                elseif shown >= maxIcons then
                    -- Past icon limit — only scanning for dispel
                else
                    shown = shown + 1
                    local ic = pool[shown]
                    if ic then
                        local prevAid = ic._msufAuraID
                        if prevAid == aid then
                            -- ══ SAME AURA ══ cheap refresh (cooldown sweep + stacks)
                            if showCd then ApplyCooldown(ic, unit, aid, true) end
                            if showStk then ApplyStacks(ic, unit, aid, aura.applications, true, gcfg) end
                        else
                            -- ══ DIFFERENT AURA OR FIRST SHOW ══
                            ic._msufAuraID = aid
                            ic._msufUnit   = unit
                            ic._msufFilter = filter
                            ic._msufBorderBlack = nil

                            ic.texture:SetTexture(aura.icon or "")
                            if not ic.texture:IsShown() then ic.texture:Show() end

                            ApplyCooldown(ic, unit, aid, showCd)
                            local cd = ic.cooldown
                            if cd then
                                local wantHide = not showCd
                                if ic._msufCdHidden ~= wantHide then
                                    ic._msufCdHidden = wantHide
                                    cd:SetHideCountdownNumbers(wantHide)
                                end
                            end
                            ApplyCooldownFont(ic, gcfg)
                            ApplyStacks(ic, unit, aid, aura.applications, showStk, gcfg)

                            if isHarmful then
                                ApplyDispelBorder(ic, unit, aid, aura.dispelName, true, showDisp)
                            elseif not ic._msufBorderBlack then
                                ic._msufBorderBlack = true
                                ic:SetBackdropBorderColor(0, 0, 0, 1)
                            end

                            -- Position: deferred for centered growth, immediate otherwise
                            if not isCentered and ic._msufPosIdx ~= shown then
                                ic._msufPosIdx = shown
                                ic:ClearAllPoints()
                                local col = (shown - 1) % perRow
                                local row = math_floor((shown - 1) / perRow)
                                local ox = col * step * gv.px + row * step * gv.sx
                                local oy = col * step * gv.py + row * step * gv.sy
                                ic:SetPoint(anchor, container, anchor, ox, oy)
                            end

                            if not ic:IsShown() then ic:Show() end
                        end

                        if isExt and aid then
                            _externalsIDs[aid] = true
                        end
                    end
                end -- shown >= maxIcons
            end
        end
    end

    -- Centered growth: reposition only when shown count changes (diff-gated)
    if isCentered and shown > 0 then
        local prevCenterN = container._msufCenterN
        if prevCenterN ~= shown then
            container._msufCenterN = shown
            local isH = (gv.px ~= 0)  -- horizontal primary axis
            local totalPrimary = shown * iconSize + (shown - 1) * spacing
            local halfOfs = totalPrimary * 0.5
            for idx = 1, shown do
                local ic = pool[idx]
                if ic then
                    ic._msufPosIdx = nil
                    ic:ClearAllPoints()
                    local col = idx - 1
                    if isH then
                        local ox = col * step - halfOfs
                        ic:SetPoint("CENTER", container, "CENTER", ox + iconSize * 0.5, 0)
                    else
                        local oy = -(col * step - halfOfs)
                        ic:SetPoint("CENTER", container, "CENTER", 0, oy - iconSize * 0.5)
                    end
                end
            end
        end
    elseif isCentered then
        container._msufCenterN = 0
    end

    -- Clear diff-gate flags on hidden icons
    for j = shown + 1, #pool do
        local ic = pool[j]
        if ic then
            if ic:IsShown() then ic:Hide() end
            ic._msufPosIdx = nil
            ic._msufBorderBlack = nil
            ic._msufAuraID = nil
            ic._msufUnit = nil
            ic._msufFilter = nil
        end
    end
    return shown, topDispel
end

------------------------------------------------------------------------
-- Main entry: UpdateFrameAuras (orchestrator for 3 groups)
------------------------------------------------------------------------
function GF.UpdateFrameAuras(f, unit)
    if not f or not unit then return end

    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    local auras = conf and conf.auras

    if not auras or auras.enabled == false then
        if not f._msufGFAurasHidden then
            f._msufGFAurasHidden = true
            HidePool(f[POOL_KEYS.buff], 1)
            HidePool(f[POOL_KEYS.debuff], 1)
            HidePool(f[POOL_KEYS.externals], 1)
        end
        return
    end
    f._msufGFAurasHidden = nil

    if not UnitExists(unit) then
        HidePool(f[POOL_KEYS.buff], 1)
        HidePool(f[POOL_KEYS.debuff], 1)
        HidePool(f[POOL_KEYS.externals], 1)
        return
    end
    if not C_UnitAuras or not C_UnitAuras.GetAuraSlots or not C_UnitAuras.GetAuraDataBySlot then return end

    local parent = f.statusIconLayer or f.barGroup or f
    local scale = GetDynamicScale(conf)
    local anyShown = false

    -- 1) Externals
    local extCfg = auras.externals
    if extCfg and extCfg.enabled then
        for k in pairs(_externalsIDs) do _externalsIDs[k] = nil end
        local afr = AF()
        local extFilter = afr and afr.EXTERNALS_TOKEN or "HELPFUL|BIG_DEFENSIVE"
        local n = RenderGroup(f, unit, "externals", extCfg, extFilter, false, parent, nil, scale)
        if n > 0 then anyShown = true end
    elseif not f._msufGFExtHidden then
        f._msufGFExtHidden = true
        HidePool(f[POOL_KEYS.externals], 1)
    end
    if extCfg and extCfg.enabled then f._msufGFExtHidden = nil end

    -- 2) Debuffs + merged dispel
    local debCfg = auras.debuff
    local mergedDispel
    local debOn = debCfg and debCfg.enabled ~= false
    local dispelNeeded = _playerCanDispel and conf.dispelEnabled ~= false

    if debOn then
        local afr = AF()
        local debFilter = afr and afr.ResolveDebuffFilter(debCfg.filterToken) or "HARMFUL"
        local n, md = RenderGroup(f, unit, "debuff", debCfg, debFilter, true, parent, nil, scale)
        mergedDispel = md
        if n > 0 then anyShown = true end
        f._msufGFDebHidden = nil
    else
        if not f._msufGFDebHidden then
            f._msufGFDebHidden = true
            HidePool(f[POOL_KEYS.debuff], 1)
        end
        -- Lightweight dispel scan ONLY when class can dispel AND dispel enabled
        if dispelNeeded then
            local slots, sc = QuerySlots(unit, "HARMFUL", 12)
            for i = 2, sc do
                local aura = C_UnitAuras.GetAuraDataBySlot(unit, slots[i])
                if aura then
                    local dn = aura.dispelName
                    if not (issecretvalue and issecretvalue(dn)) and dn ~= nil and dn ~= "" then
                        mergedDispel = dn; break
                    end
                    local ir = aura.isRaid
                    if not (issecretvalue and issecretvalue(ir)) and ir then
                        mergedDispel = "Bleed"; break
                    end
                end
            end
        end
    end
    f._msufGFMergedDispel = mergedDispel

    -- 3) Buffs
    local buffCfg = auras.buff
    if buffCfg and buffCfg.enabled ~= false then
        local afr = AF()
        local buffFilter = afr and afr.ResolveBuffFilter(buffCfg.filterToken) or "HELPFUL|RAID"
        local n = RenderGroup(f, unit, "buff", buffCfg, buffFilter, false, parent, f._msufSIDedupIDs, scale)
        if n > 0 then anyShown = true end
        f._msufGFBufHidden = nil
    elseif not f._msufGFBufHidden then
        f._msufGFBufHidden = true
        HidePool(f[POOL_KEYS.buff], 1)
    end

    -- Build displayed aura ID hash set (only when icons are shown)
    if anyShown then
        local disp = f._msufDisplayedAuraIDs
        if not disp then disp = {}; f._msufDisplayedAuraIDs = disp end
        for k in pairs(disp) do disp[k] = nil end
        local pool = f._msufAuraPool_buff
        if pool then for ii = 1, #pool do local ic = pool[ii]
            if ic and ic:IsShown() and ic._msufAuraID then disp[ic._msufAuraID] = ic end
        end end
        pool = f._msufAuraPool_debuff
        if pool then for ii = 1, #pool do local ic = pool[ii]
            if ic and ic:IsShown() and ic._msufAuraID then disp[ic._msufAuraID] = ic end
        end end
        pool = f._msufAuraPool_externals
        if pool then for ii = 1, #pool do local ic = pool[ii]
            if ic and ic:IsShown() and ic._msufAuraID then disp[ic._msufAuraID] = ic end
        end end
    else
        -- No icons shown — clear hash set
        local disp = f._msufDisplayedAuraIDs
        if disp then for k in pairs(disp) do disp[k] = nil end end
    end
end

------------------------------------------------------------------------
-- Direct icon refresh (skip full UpdateFrameAuras for update-only events)
-- Called by dispatchAura when only cooldown/stacks changed on displayed icons.
-- Cost: ~16µs (2 C-API calls) vs 130µs (31 C-API calls) for full pipeline.
------------------------------------------------------------------------
function GF.RefreshAuraIcon(icon, unit, aid)
    if not icon or not unit or not aid then return end
    ApplyCooldown(icon, unit, aid, true)
    ApplyStacks(icon, unit, aid, nil, true, nil)
end

------------------------------------------------------------------------
-- Hide all aura groups (for unit change / hide)
------------------------------------------------------------------------
function GF.HideFrameAuras(f)
    HidePool(f[POOL_KEYS.buff], 1)
    HidePool(f[POOL_KEYS.debuff], 1)
    HidePool(f[POOL_KEYS.externals], 1)
    for _, cKey in pairs(CONT_KEYS) do
        local c = f[cKey]
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

    -- Apply behind-bar or normal parent/level to a container (shared by preview + live)
    local function ApplyContainerMode(container, f, gcfg, normalParent)
        local behindBar = gcfg.behindBar and f.health
        local wantParent = behindBar and (f.barGroup or f) or normalParent
        if container:GetParent() ~= wantParent then
            container:SetParent(wantParent)
        end
        local wantLvl
        if behindBar then
            wantLvl = (f.barGroup or f):GetFrameLevel()
        else
            wantLvl = normalParent:GetFrameLevel() + (gcfg.layer or 5)
        end
        if container._msufCachedLvl ~= wantLvl then
            container._msufCachedLvl = wantLvl
            container:SetFrameLevel(wantLvl)
        end
        local wantAlpha = behindBar and ((gcfg.behindBarAlpha or 85) / 100) or 1
        if container._msufCachedAlpha ~= wantAlpha then
            container._msufCachedAlpha = wantAlpha
            container:SetAlpha(wantAlpha)
        end
        -- Behind-bar anchors to health area
        return behindBar and (f.health or wantParent) or normalParent
    end

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
        -- Apply dynamic scale based on configured capacity (mirrors live GetDynamicScale)
        local dynScale = GetPreviewDynamicScale(conf, kind)

        -- Buffs
        local buffCfg = auras.buff
        if buffCfg and buffCfg.enabled ~= false then
            local rawSize = buffCfg.size or 20
            local size = rawSize
            if dynScale ~= 1 then size = math_max(8, math_floor(rawSize * dynScale + 0.5)) end
            local anchor = buffCfg.anchor or "BOTTOMLEFT"
            local growth = buffCfg.growth or "RIGHTDOWN"
            local spacing = buffCfg.spacing or 1
            local perRow = buffCfg.perRow or 4
            local maxShow = math_min(#MOCK_BUFFS, buffCfg.max or 6)
            local gv = GetGrowthVectors(growth)
            local container = EnsureContainer(f, "buff")
            local anchorTarget = ApplyContainerMode(container, f, buffCfg, parent)
            container:ClearAllPoints()
            container:SetPoint(anchor, anchorTarget, anchor, buffCfg.x or 0, buffCfg.y or 0)
            container:SetSize(1, 1)
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
            local rawSize = debCfg.size or 20
            local size = rawSize
            if dynScale ~= 1 then size = math_max(8, math_floor(rawSize * dynScale + 0.5)) end
            local anchor = debCfg.anchor or "TOPLEFT"
            local growth = debCfg.growth or "RIGHTDOWN"
            local spacing = debCfg.spacing or 1
            local perRow = debCfg.perRow or 3
            local maxShow = math_min(#MOCK_DEBUFFS, debCfg.max or 6)
            local gv = GetGrowthVectors(growth)
            local container = EnsureContainer(f, "debuff")
            local anchorTarget = ApplyContainerMode(container, f, debCfg, parent)
            container:ClearAllPoints()
            container:SetPoint(anchor, anchorTarget, anchor, debCfg.x or 0, debCfg.y or 0)
            container:SetSize(1, 1)
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
            local rawSize = extCfg.size or 28
            local size = rawSize
            if dynScale ~= 1 then size = math_max(8, math_floor(rawSize * dynScale + 0.5)) end
            local anchor = extCfg.anchor or "CENTER"
            local growth = extCfg.growth or "RIGHTDOWN"
            local spacing = extCfg.spacing or 1
            local perRow = extCfg.perRow or 3
            local maxShow = math_min(#MOCK_EXTERNALS, extCfg.max or 2)
            local gv = GetGrowthVectors(growth)
            local container = EnsureContainer(f, "externals")
            local anchorTarget = ApplyContainerMode(container, f, extCfg, parent)
            container:ClearAllPoints()
            container:SetPoint(anchor, anchorTarget, anchor, extCfg.x or 0, extCfg.y or 0)
            container:SetSize(1, 1)
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
GF.GetPreviewDynamicScale = GetPreviewDynamicScale
_G.MSUF_GF_UpdateFrameAuras = GF.UpdateFrameAuras
