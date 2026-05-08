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
local canaccessvalue = _G.canaccessvalue
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
local C_Timer       = _G.C_Timer
local C_CurveUtil   = _G.C_CurveUtil
local C_Secrets     = _G.C_Secrets
local CreateColor   = _G.CreateColor
local _hasCanaccessvalue = (type(canaccessvalue) == "function")
local _QUESTION_MARK_ICON = 136243
local _PADLOCK_ICON = 134400
local _GF_RegisterCooldownTextIcon
local _GF_UnregisterCooldownTextIcon
local _GF_TouchCooldownTextIcon

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
local _getSlots, _getBySlot, _getByIndex, _getByAuraInstanceID, _getDuration, _getStackCount, _apisBound

local function BindAPIs()
    if _apisBound then return end
    _apisBound = true
    if C_UnitAuras then
        _getSlots      = C_UnitAuras.GetAuraSlots
        _getBySlot     = C_UnitAuras.GetAuraDataBySlot
        _getByIndex    = C_UnitAuras.GetAuraDataByIndex
        _getByAuraInstanceID = C_UnitAuras.GetAuraDataByAuraInstanceID
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
    if not _apisBound then BindAPIs() end
    if not _getSlots then return _slotBuf, 0 end
    if maxCount then
        return CaptureSlots(_getSlots(unit, filter, maxCount))
    end
    return CaptureSlots(_getSlots(unit, filter))
end

------------------------------------------------------------------------
-- 2-Tier Filter Engine (via MSUF_GF_AuraFilter.lua)
-- Tier 1: Blizzard API tokens (GetAuraSlots filter string)
-- Tier 2: Declassified spell blacklist (categorized, user-toggleable)
------------------------------------------------------------------------

-- Shared empty-config sentinel (4.22 Beta hotfix).
-- Was: `local buffCfg = auras.buff or {}` -- 3 sites in UpdateFrameAuras
-- allocated a fresh empty table per call when the config branch was nil.
-- We point all three to ONE frozen empty table. Read-only access only
-- (the value flows into `cfg.enabled`, `cfg.max`, `cfg.filterToken`).
-- Zero allocations on the cold-config branch.
local _EMPTY_AURA_CFG = {}

local _AF  -- deferred AuraFilter reference (resolved at first use)
local function AF()
    if _AF then return _AF end
    _AF = GF.AuraFilter or (_G.MSUF_GF_AuraFilter)
    return _AF
end

local function DecodeAuraIconFileID(icon)
    if _hasCanaccessvalue then
        if canaccessvalue(icon) ~= true then return 0 end
    elseif issecretvalue and issecretvalue(icon) == true then
        return 0
    end
    return tonumber(icon) or 0
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
-- Dispel type border colors — C-side ColorCurve (secret-safe)
-- GetAuraDispelTypeColor works on secret auras — no dispelName read needed.
-- IsAuraFilteredOutByInstanceID with RAID_PLAYER_DISPELLABLE checks dispellability.
------------------------------------------------------------------------
local _dispelColorCurve
local _getDispelColor
local _isFilteredOut

------------------------------------------------------------------------
-- Shared dispel color curve — reads per-type colors from Colors panel DB.
-- Evaluated via C_UnitAuras.GetAuraDispelTypeColor(unit, aid, curve) →
-- returns a Color object whose RGBA can be applied to textures via
-- tex:SetVertexColor(color:GetRGBA()) in a secret-safe varargs passthrough.
--
-- The curve MUST cover every dispel enum the API can return — Magic,
-- Curse, Poison, Disease, Bleed AND Enrage (9). Without a point for an
-- enum, GetAuraDispelTypeColor returns nil and callers fall back to the
-- static 0.25/0.75/1.00 neutral palette, which is indistinguishable from
-- the "only single color works" bug users saw in Beta 4/5.
------------------------------------------------------------------------
local function _ReadDBColor(gen, typeName, dr, dg, db)
    if not gen then return dr, dg, db end
    local r = gen["dispelType" .. typeName .. "R"]
    if type(r) ~= "number" then return dr, dg, db end
    local g = gen["dispelType" .. typeName .. "G"]
    local b = gen["dispelType" .. typeName .. "B"]
    return r, g or dg, b or db
end

local function _GetReadableDispelName(dispelName)
    if dispelName == nil then return nil end
    if issecretvalue and issecretvalue(dispelName) then return nil end
    if type(dispelName) ~= "string" or dispelName == "" or dispelName == "None" then
        return nil
    end
    return dispelName
end

-- Grid2-compatible dispel type ids for GetAuraDispelTypeColor():
-- None=0, Magic=1, Curse=2, Disease=3, Poison=4, Enrage=9, Bleed=11.
-- Using the hardcoded ids is more reliable than Enum.DispelType here.
local _DISPEL_CURVE_POINTS = {
    { id = 0,  typeName = nil,       defR = 0.25, defG = 0.75, defB = 1.00 },
    { id = 1,  typeName = "Magic",   defR = 0.25, defG = 0.75, defB = 1.00 },
    { id = 2,  typeName = "Curse",   defR = 0.60, defG = 0.00, defB = 1.00 },
    { id = 3,  typeName = "Disease", defR = 0.60, defG = 0.40, defB = 0.00 },
    { id = 4,  typeName = "Poison",  defR = 0.00, defG = 0.60, defB = 0.00 },
    { id = 9,  typeName = "Bleed",   defR = 0.80, defG = 0.00, defB = 0.00 },
    { id = 11, typeName = "Bleed",   defR = 0.80, defG = 0.00, defB = 0.00 },
}

local function _BuildDispelColorCurve()
    local CUA = _G.C_UnitAuras
    local CCU = _G.C_CurveUtil
    if not (CUA and type(CUA.GetAuraDispelTypeColor) == "function"
            and CCU and type(CCU.CreateColorCurve) == "function") then
        return nil
    end

    local curve = CCU.CreateColorCurve()
    if curve.SetType then
        curve:SetType(_G.Enum and _G.Enum.LuaCurveType and _G.Enum.LuaCurveType.Step or 0)
    end
    if not curve.AddPoint then return curve end

    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    local C   = _G.CreateColor

    for i = 1, #_DISPEL_CURVE_POINTS do
        local p = _DISPEL_CURVE_POINTS[i]
        local r, g, b = p.defR, p.defG, p.defB
        if p.typeName then
            r, g, b = _ReadDBColor(gen, p.typeName, r, g, b)
        end
        curve:AddPoint(p.id, C(r, g, b, 1))
    end
    return curve
end

do
    local CUA = _G.C_UnitAuras
    _dispelColorCurve = _BuildDispelColorCurve()
    if CUA and type(CUA.GetAuraDispelTypeColor) == "function" then
        _getDispelColor = CUA.GetAuraDispelTypeColor
    end
    if CUA and type(CUA.IsAuraFilteredOutByInstanceID) == "function" then
        _isFilteredOut = CUA.IsAuraFilteredOutByInstanceID
    end
end
local _DISPEL_FILTER = "HARMFUL|RAID_PLAYER_DISPELLABLE"

-- Export shared ColorCurve + rebuild entry for Options live-apply.
GF._sharedDispelColorCurve = _dispelColorCurve
GF.RebuildDispelColorCurve = function()
    local new = _BuildDispelColorCurve()
    if not new then return GF._sharedDispelColorCurve end
    _dispelColorCurve          = new
    _getDispelColor            = (_G.C_UnitAuras or {}).GetAuraDispelTypeColor
    GF._sharedDispelColorCurve = new
    return new
end

-- Legacy fallback colors (used only when C-side API unavailable)
local DISPEL_COLORS = {
    Magic   = { 0.25, 0.75, 1.00 },
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
-- Bounded high enough to absorb a full custom raid-aura header rebuild.
local _ICON_RECYCLE_MAX = 2048

local function IconUsesMasque(icon)
    local M = GF.Masque
    return M and M.IconUsesMasque and M.IconUsesMasque(icon) == true
end

local function SyncAuraIconGeometry(icon, size)
    if not icon then return false end
    local changed = (icon._msufCachedSz ~= size)
    if changed then
        icon._msufCachedSz = size
        icon:SetSize(size, size)
    end

    local masqueActive
    local M = GF.Masque
    if M and M.SyncIconGeometry then
        masqueActive = M.SyncIconGeometry(icon, size) == true
    else
        masqueActive = IconUsesMasque(icon)
    end

    -- Masque owns the Icon region geometry once a skin is active. For the
    -- native skin we keep every child hard-anchored to the aura frame so a
    -- size slider cannot resize only the backdrop/cooldown "box".
    if icon.texture and not masqueActive then
        icon.texture:ClearAllPoints()
        icon.texture:SetAllPoints(icon)
    end
    if icon.cooldown then
        icon.cooldown:ClearAllPoints()
        icon.cooldown:SetAllPoints(icon)
    end
    local overlay = icon._msufOverlay or (icon.count and icon.count.GetParent and icon.count:GetParent())
    if overlay and overlay ~= icon then
        icon._msufOverlay = overlay
        overlay:ClearAllPoints()
        overlay:SetAllPoints(icon)
        if overlay.SetFrameLevel then
            local base = icon.cooldown and icon.cooldown.GetFrameLevel and icon.cooldown:GetFrameLevel()
            overlay:SetFrameLevel((base or (icon:GetFrameLevel() or 0)) + 5)
        end
    end
    return changed
end

local function AcquireAuraIcon(parent, size)
    if _iconRecyclerN > 0 then
        local icon = _iconRecycler[_iconRecyclerN]
        _iconRecycler[_iconRecyclerN] = nil
        _iconRecyclerN = _iconRecyclerN - 1
        icon:SetParent(parent)
        SyncAuraIconGeometry(icon, size)
        icon:SetBackdropBorderColor(0, 0, 0, 1)
        if icon.texture then icon.texture:SetTexCoord(0, 1, 0, 1); icon.texture:SetDesaturated(false) end
        if _GF_UnregisterCooldownTextIcon then _GF_UnregisterCooldownTextIcon(icon) end
        icon._msufGF_cdDurationObj = nil
        if icon.cooldown then icon.cooldown._msufGF_cdDurationObj = nil; icon.cooldown:Clear(); if icon.cooldown.SetDrawBling then icon.cooldown:SetDrawBling(false) end end
        if icon.count then icon.count:SetText(""); icon.count:Hide() end
        -- Defensive: ensure tracking fields are clean (Recycle clears them, but
        -- belt-and-braces in case future code paths feed the recycler differently).
        icon._msufAuraID       = nil
        icon._msufBorderBlack  = nil
        icon._msufPosIdx       = nil
        icon._msufPosStep      = nil
        icon._msufPosPR        = nil
        icon._msufPosAnchor    = nil
        icon._msufPosGrowth    = nil
        icon._msufAuraGroupKey = nil
        return icon
    end
    return nil
end

-- Memory-leak Fix3: aggressively reset icon state on recycle.
-- Without this, a recycled icon carries stale tracking fields (auraID,
-- unit, owner, position cache) which would cause RenderGroup's "same
-- aura" fast-path to skip a fresh setup when the icon lands on a
-- different frame. We also break the strong-ref to the prior owner
-- so the recycled icon doesn't keep an old retired frame alive.
local function RecycleAuraIcon(icon)
    if not icon then return false end
    icon:Hide()
    icon:ClearAllPoints()
    if _GF_UnregisterCooldownTextIcon then _GF_UnregisterCooldownTextIcon(icon) end
    icon._msufGF_cdDurationObj = nil
    if icon.cooldown then icon.cooldown._msufGF_cdDurationObj = nil end
    -- Clear tracking fields so a future Acquire onto a different frame
    -- takes the full-setup branch in RenderGroup.
    icon._msufAuraID       = nil
    icon._msufUnit         = nil
    icon._msufFilter       = nil
    icon._msufBorderBlack  = nil
    icon._msufPosIdx       = nil
    icon._msufPosStep      = nil
    icon._msufPosPR        = nil
    icon._msufPosAnchor    = nil
    icon._msufPosGrowth    = nil
    icon._msufCdHidden     = nil
    icon._msufCachedSz     = nil
    icon._msufAuraGroupKey = nil
    -- Drop owner ref so the prior frame can be GC'd (most important: when
    -- a Header retire calls GF.RecycleFramePools, the icon→frame strong-ref
    -- via _msufGFOwner would otherwise pin the retired frame in memory.)
    icon._msufGFOwner      = nil
    if _iconRecyclerN >= _ICON_RECYCLE_MAX then return true end
    -- Optional: if the icon had a Masque skin, the Acquire path doesn't
    -- re-skin (skin sticks to the frame). Leaving Masque state alone is
    -- correct: same library handles re-anchor on next AddButton call.
    _iconRecyclerN = _iconRecyclerN + 1
    _iconRecycler[_iconRecyclerN] = icon
    return true
end

------------------------------------------------------------------------
-- GF.RecycleFramePools(f)
-- Called from RetireHeader: empty all aura-icon pools owned by `f`
-- and feed reusable icons into the global recycler. If the recycler is full,
-- icons are still detached from frame-local Lua tables to avoid stale refs.
-- The next SetupHeader can then reuse retained icons instead of creating
-- a fresh set after every zone-triggered header rebuild.
------------------------------------------------------------------------
function GF.RecycleFramePools(f)
    if not f then return end
    for _, poolKey in pairs(POOL_KEYS) do
        local pool = f[poolKey]
        if type(pool) == "table" then
            for i = 1, #pool do
                local ic = pool[i]
                if ic then
                    RecycleAuraIcon(ic)
                    pool[i] = nil
                end
            end
            -- Reset pool meta-cache so EnsurePool re-populates correctly on next setup
            pool._msufPoolOK = nil
            pool._msufPoolN  = nil
            pool._msufPoolSz = nil
            pool._msufPoolP  = nil
            f[poolKey] = nil
        end
    end
    if GF.ClearFrameAuraCache then GF.ClearFrameAuraCache(f) end
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
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetReverse(false)
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
    icon._msufOverlay = overlay

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
    local anySizeChanged = false
    for i = 1, count do
        if not pool[i] then
            pool[i] = AcquireAuraIcon(parent, size) or CreateAuraIcon(parent, size)
            pool[i]._msufGFOwner = f
            if masqueAdd then masqueAdd(pool[i]) end
        end
        local ic = pool[i]
        ic._msufGFOwner = f
        ic._msufAuraGroupKey = groupKey
        if SyncAuraIconGeometry(ic, size) then
            anySizeChanged = true
            ic._msufPosStep = nil
            ic._msufPosAnchor = nil
            ic._msufPosGrowth = nil
        end
        if ic:GetParent() ~= parent then ic:SetParent(parent) end
        if pLvl and ic._msufCachedFLvl ~= pLvl then
            ic._msufCachedFLvl = pLvl
            ic:SetFrameLevel(pLvl)
        end
    end
    if anySizeChanged and GF.Masque and GF.Masque.ForceReskin then
        GF.Masque.ForceReskin()
    end
    return pool
end

local function HidePool(pool, startIdx)
    if not pool then return end
    for i = startIdx, #pool do
        local ic = pool[i]
        if ic then
            if _GF_UnregisterCooldownTextIcon then _GF_UnregisterCooldownTextIcon(ic) end
            ic._msufGF_cdDurationObj = nil
            if ic.cooldown then ic.cooldown._msufGF_cdDurationObj = nil end
            ic:Hide()
            -- Invalidate diff-cache so the next render takes the full-setup
            -- branch in RenderGroup (which ends with ic:Show()) instead of
            -- the cheap "same aura" refresh path that assumes visibility.
            -- Fixes: toggle Buffs/Debuffs off → on leaves icons hidden when
            -- the same auras are still present (MotW, Fortitude, etc.).
            -- Mirrors the end-of-render cleanup in RenderGroup.
            ic._msufAuraID = nil
            ic._msufPosIdx = nil
            ic._msufPosStep = nil
            ic._msufPosPR = nil
            ic._msufPosAnchor = nil
            ic._msufPosGrowth = nil
            ic._msufBorderBlack = nil
            ic._msufAuraGroupCfg = nil
            ic._msufAuraFrameScale = nil
        end
    end
    pool._msufShown = (startIdx and startIdx > 1) and (startIdx - 1) or 0
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
local function PositionIcon(ic, anchor, container, idx, perRow, size, spacing, gv, totalCount)
    ic:ClearAllPoints()
    local step = size + spacing
    if gv and gv.centered then
        local count = math_max(1, totalCount or 1)
        local col = idx - 1
        local totalPrimary = count * size + (count - 1) * spacing
        local halfOfs = totalPrimary * 0.5
        if gv.px ~= 0 then
            local ox = col * step - halfOfs + size * 0.5
            ic:SetPoint("CENTER", container, "CENTER", ox, 0)
        else
            local oy = -(col * step - halfOfs) - size * 0.5
            ic:SetPoint("CENTER", container, "CENTER", 0, oy)
        end
        return
    end
    local col = (idx - 1) % perRow
    local row = math_floor((idx - 1) / perRow)
    local ox = col * step * gv.px + row * step * gv.sx
    local oy = col * step * gv.py + row * step * gv.sy
    ic:SetPoint(anchor, container, anchor, ox, oy)
end

------------------------------------------------------------------------
-- Apply cooldown (SetCooldownFromDurationObject — only secret-safe path)
--
-- Midnight 12.0 detail: the cooldown swipe will NOT animate for an aura
-- on a non-self unit unless we also tell the CooldownFrame to use the
-- native aura display time. Without SetUseAuraDisplayTime(true), the
-- swirl renders as a static frame because the secret-tagged duration
-- object alone doesn't drive C-side progress on its own.
--
-- Diff-gated via _msufGFCdAuraTime so we only hit the C method on real
-- transitions (most aura updates re-enter ApplyCooldown but keep the
-- same on/off state). Cheap when state is steady.
------------------------------------------------------------------------
local function ApplyCooldown(ic, unit, auraInstanceID, showCooldown, showText)
    local cd = ic.cooldown
    if not cd then return end
    if not showCooldown then
        ic._msufGF_cdDurationObj = nil
        cd._msufGF_cdDurationObj = nil
        if _GF_UnregisterCooldownTextIcon then _GF_UnregisterCooldownTextIcon(ic) end
        if cd._msufGFCdAuraTime ~= false and cd.SetUseAuraDisplayTime then
            cd._msufGFCdAuraTime = false
            cd:SetUseAuraDisplayTime(false)
        end
        cd:Clear()
        return
    end
    if not _apisBound then BindAPIs() end
    if not _getDuration or not auraInstanceID then
        ic._msufGF_cdDurationObj = nil
        cd._msufGF_cdDurationObj = nil
        if _GF_UnregisterCooldownTextIcon then _GF_UnregisterCooldownTextIcon(ic) end
        if cd._msufGFCdAuraTime ~= false and cd.SetUseAuraDisplayTime then
            cd._msufGFCdAuraTime = false
            cd:SetUseAuraDisplayTime(false)
        end
        cd:Clear()
        return
    end
    local obj = _getDuration(unit, auraInstanceID)
    if obj ~= nil then
        local fn = cd.SetCooldownFromDurationObject
        if fn then
            fn(cd, obj)
            ic._msufGF_cdDurationObj = obj
            cd._msufGF_cdDurationObj = obj
            cd._msufCooldownFontStringDirty = true
            if showText and _GF_TouchCooldownTextIcon then _GF_TouchCooldownTextIcon(ic) end
            if cd._msufGFCdAuraTime ~= true and cd.SetUseAuraDisplayTime then
                cd._msufGFCdAuraTime = true
                cd:SetUseAuraDisplayTime(true)
            end
            return
        end
    end
    if cd._msufGFCdAuraTime ~= false and cd.SetUseAuraDisplayTime then
        cd._msufGFCdAuraTime = false
        cd:SetUseAuraDisplayTime(false)
    end
    ic._msufGF_cdDurationObj = nil
    cd._msufGF_cdDurationObj = nil
    if _GF_UnregisterCooldownTextIcon then _GF_UnregisterCooldownTextIcon(ic) end
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
-- Uses C-side GetAuraDispelTypeColor (secret-safe, works on all auras).
-- Falls back to dispelName for legacy compat when C-side API unavailable.
------------------------------------------------------------------------
local function ApplyDispelBorder(ic, unit, auraInstanceID, dispelName, isHarmful, showDispel)
    if not isHarmful or not showDispel then
        if not ic._msufBorderBlack then
            ic._msufBorderBlack = true
            ic:SetBackdropBorderColor(0, 0, 0, 1)
        end
        return
    end
    ic._msufBorderBlack = nil
    -- C-side dispel color (secret-safe, works on all debuffs)
    if _getDispelColor and _dispelColorCurve and auraInstanceID then
        local color = _getDispelColor(unit, auraInstanceID, _dispelColorCurve)
        if color then
            local r, g, b
            if color.GetRGB then r, g, b = color:GetRGB()
            elseif color.r then r, g, b = color.r, color.g, color.b end
            if r then ic:SetBackdropBorderColor(r, g, b, 1); return end
        end
    end
    -- Legacy fallback: plain dispelName (non-secret only)
    if not (issecretvalue and issecretvalue(dispelName)) and dispelName ~= nil then
        local c = DISPEL_COLORS[dispelName]
        if c then ic:SetBackdropBorderColor(c[1], c[2], c[3], 1); return end
    end
    -- Default red for unknown debuffs
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

local function WantsCooldownText(gcfg)
    -- GF uses showCooldown as the runtime key. Legacy showCooldownText values
    -- are ignored here so stale saved vars cannot suppress Blizzard's timer.
    return not (gcfg and gcfg.showCooldown == false)
end

local function WantsCooldownSwipe(gcfg)
    return not (gcfg and gcfg.showCooldownSwipe == false)
end

local function IsCooldownFontString(region)
    return region and region.GetObjectType and region:GetObjectType() == "FontString"
end

local function CacheCooldownFontString(cd, fs)
    cd._msufCooldownFontString = fs
    return fs
end

local function FindCooldownFontStringInRegions(...)
    for i = 1, select("#", ...) do
        local region = select(i, ...)
        if IsCooldownFontString(region) then return region end
    end
    return nil
end

local function ResolveCooldownFontString(cd, forceLookup)
    if not cd then return nil end

    local fs = cd.Text
    if IsCooldownFontString(fs) then return CacheCooldownFontString(cd, fs) end

    fs = cd.text
    if IsCooldownFontString(fs) then return CacheCooldownFontString(cd, fs) end

    local cached = cd._msufCooldownFontString
    if not forceLookup and cached and cached ~= false then return cached end

    if cd.GetRegions then
        fs = FindCooldownFontStringInRegions(cd:GetRegions())
        if fs then return CacheCooldownFontString(cd, fs) end
    end

    if cd.EnumerateRegions then
        for region in cd:EnumerateRegions() do
            if IsCooldownFontString(region) then return CacheCooldownFontString(cd, region) end
        end
    end

    cd._msufCooldownFontString = false
    return nil
end

------------------------------------------------------------------------
-- Cooldown text base color — module-level cache, mirrors ResolveGlobalFont
-- pattern. Invalidated by GF.InvalidateCdColor() from RefreshFonts and
-- RefreshColors hooks (covers font-color change + profile-swap-via-PushVisualUpdates).
-- Cached values: r, g, b, a. The "1" alpha is constant and cached too so
-- callers never have to special-case it.
------------------------------------------------------------------------
local _gfCdColR, _gfCdColG, _gfCdColB, _gfCdColA
local function ResolveCooldownBaseColor()
    local r = _gfCdColR
    if r then return r, _gfCdColG, _gfCdColB, _gfCdColA end
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    if g and g.useCustomFontColor == true then
        local cr = g.fontColorCustomR
        local cg = g.fontColorCustomG
        local cb = g.fontColorCustomB
        if type(cr) == "number" and type(cg) == "number" and type(cb) == "number" then
            _gfCdColR, _gfCdColG, _gfCdColB, _gfCdColA = cr, cg, cb, 1
            return cr, cg, cb, 1
        end
    end
    _gfCdColR, _gfCdColG, _gfCdColB, _gfCdColA = 1, 1, 1, 1
    return 1, 1, 1, 1
end

--- Invalidate cached cooldown text color (called by font/color options changes
--- via GF.RefreshFonts and GF.RefreshColors).
function GF.InvalidateCdColor()
    _gfCdColR = nil
    _gfCdColG = nil
    _gfCdColB = nil
    _gfCdColA = nil
    if GF.InvalidateCooldownTextColors then GF.InvalidateCooldownTextColors() end
end

-- Native Blizzard cooldown text coloring for GF aura timers.
-- Uses GF-scoped bucket/threshold settings and the shared aura timer colors.
-- Blizzard still owns the timer text; MSUF
-- only recolors its FontString. Runtime is a scheduled timer manager,
-- not OnUpdate, and remaining time is evaluated via DurationObject curves
-- so secret aura values are never read or compared directly.
------------------------------------------------------------------------
local _gfCdTextSettingsDirty = true
local _gfCdTextBucketsEnabled = true
local _gfCdCurve
local _gfCdSafeR, _gfCdSafeG, _gfCdSafeB, _gfCdSafeA = 1, 1, 1, 1
local _gfCdWarnR, _gfCdWarnG, _gfCdWarnB, _gfCdWarnA = 1, 0.85, 0.2, 1
local _gfCdUrgR,  _gfCdUrgG,  _gfCdUrgB,  _gfCdUrgA  = 1, 0.55, 0.1, 1
local _gfCdExpR,  _gfCdExpG,  _gfCdExpB,  _gfCdExpA  = 1, 0.12, 0.12, 1
local _gfCdNormR, _gfCdNormG, _gfCdNormB, _gfCdNormA = 1, 1, 1, 1
local _gfCdSecretMode, _gfCdSecretNextCheck = false, 0
local _gfIsSecretValue = _G.issecretvalue
    or (C_Secrets and type(C_Secrets.IsSecret) == "function" and C_Secrets.IsSecret)
    or nil

local function ReadColor(t, defR, defG, defB, defA)
    if type(t) ~= "table" then return defR, defG, defB, defA end
    local r = t[1]; if r == nil then r = t.r end
    local g = t[2]; if g == nil then g = t.g end
    local b = t[3]; if b == nil then b = t.b end
    local a = t[4]; if a == nil then a = t.a end
    if type(r) ~= "number" then r = defR end
    if type(g) ~= "number" then g = defG end
    if type(b) ~= "number" then b = defB end
    if type(a) ~= "number" then a = defA end
    return r, g, b, a
end

local function ResolveStackTextColor()
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    return ReadColor(g and g.aurasStackCountColor, 1, 1, 1, 1)
end

local function IsGFSecretMode(now)
    if not (C_Secrets and type(C_Secrets.ShouldAurasBeSecret) == "function") then return false end
    if type(now) ~= "number" then now = GetTime() end
    if now >= (_gfCdSecretNextCheck or 0) then
        _gfCdSecretNextCheck = now + 0.50
        _gfCdSecretMode = (C_Secrets.ShouldAurasBeSecret() == true)
    end
    return _gfCdSecretMode == true
end

local function BuildGFCooldownTextCurve(g)
    _gfCdCurve = nil
    if not (C_CurveUtil and type(C_CurveUtil.CreateColorCurve) == "function"
            and type(CreateColor) == "function") then
        return
    end

    local c = C_CurveUtil.CreateColorCurve()
    if not c then return end
    if c.SetType and _G.Enum and _G.Enum.LuaCurveType and _G.Enum.LuaCurveType.Step then
        c:SetType(_G.Enum.LuaCurveType.Step)
    end

    local safeSeconds = (g and type(g.gfAurasCooldownTextSafeSeconds) == "number") and g.gfAurasCooldownTextSafeSeconds or 60
    local warnSeconds = (g and type(g.gfAurasCooldownTextWarningSeconds) == "number") and g.gfAurasCooldownTextWarningSeconds or 15
    local urgSeconds  = (g and type(g.gfAurasCooldownTextUrgentSeconds) == "number") and g.gfAurasCooldownTextUrgentSeconds or 5
    if warnSeconds > safeSeconds then warnSeconds = safeSeconds end
    if urgSeconds > warnSeconds then urgSeconds = warnSeconds end
    if urgSeconds < 0 then urgSeconds = 0 end

    c:AddPoint(0, CreateColor(_gfCdExpR, _gfCdExpG, _gfCdExpB, _gfCdExpA))
    c:AddPoint(0.25, CreateColor(_gfCdUrgR, _gfCdUrgG, _gfCdUrgB, _gfCdUrgA))
    c:AddPoint(urgSeconds, CreateColor(_gfCdWarnR, _gfCdWarnG, _gfCdWarnB, _gfCdWarnA))
    c:AddPoint(warnSeconds, CreateColor(_gfCdSafeR, _gfCdSafeG, _gfCdSafeB, _gfCdSafeA))
    c:AddPoint(safeSeconds, CreateColor(_gfCdNormR, _gfCdNormG, _gfCdNormB, _gfCdNormA))
    _gfCdCurve = c
end

local function EnsureGFCooldownTextColorSettings()
    if not _gfCdTextSettingsDirty then return end
    _gfCdTextSettingsDirty = false

    local g = _G.MSUF_DB and _G.MSUF_DB.general
    _gfCdTextBucketsEnabled = not (g and g.gfAurasCooldownTextUseBuckets == false)
    _gfCdNormR, _gfCdNormG, _gfCdNormB, _gfCdNormA = ResolveCooldownBaseColor()
    _gfCdSafeR, _gfCdSafeG, _gfCdSafeB, _gfCdSafeA = ReadColor(g and g.aurasCooldownTextSafeColor, _gfCdNormR, _gfCdNormG, _gfCdNormB, _gfCdNormA)
    _gfCdWarnR, _gfCdWarnG, _gfCdWarnB, _gfCdWarnA = ReadColor(g and g.aurasCooldownTextWarningColor, 1, 0.85, 0.2, 1)
    _gfCdUrgR,  _gfCdUrgG,  _gfCdUrgB,  _gfCdUrgA  = ReadColor(g and g.aurasCooldownTextUrgentColor, 1, 0.55, 0.1, 1)
    _gfCdExpR,  _gfCdExpG,  _gfCdExpB,  _gfCdExpA  = ReadColor(g and g.aurasCooldownTextExpireColor, 1, 0.12, 0.12, 1)

    if _gfCdTextBucketsEnabled then
        BuildGFCooldownTextCurve(g)
    else
        _gfCdCurve = nil
    end
end

local function ApplyGFCooldownTextColor(icon, fs, r, g, b, a, secret)
    if not fs then return end
    if secret then
        icon._msufGF_cdLastFS = fs
        icon._msufGF_cdLastR = nil
        icon._msufGF_cdLastG = nil
        icon._msufGF_cdLastB = nil
        icon._msufGF_cdLastA = nil
        if fs.SetTextColor then fs:SetTextColor(r, g, b, a)
        elseif fs.SetVertexColor then fs:SetVertexColor(r, g, b, a) end
        return
    end
    if icon._msufGF_cdLastFS ~= fs
        or icon._msufGF_cdLastR ~= r or icon._msufGF_cdLastG ~= g
        or icon._msufGF_cdLastB ~= b or icon._msufGF_cdLastA ~= a
    then
        icon._msufGF_cdLastFS = fs
        icon._msufGF_cdLastR = r
        icon._msufGF_cdLastG = g
        icon._msufGF_cdLastB = b
        icon._msufGF_cdLastA = a
        if fs.SetTextColor then fs:SetTextColor(r, g, b, a)
        elseif fs.SetVertexColor then fs:SetVertexColor(r, g, b, a) end
    end
end

local _gfCdTextMgr
local function EnsureGFCooldownTextMgr()
    if _gfCdTextMgr then return _gfCdTextMgr end
    local mgr = {
        icons = {},
        count = 0,
        timer = nil,
        timerGen = 0,
        interval = 0.50,
        slowInterval = 0.50,
        fastInterval = 0.10,
        secretInterval = 0.20,
        maxIdleInterval = 5.00,
        fastUntil = 0,
    }
    _gfCdTextMgr = mgr

    local function CancelTimer()
        if mgr.timer and mgr.timer.Cancel then mgr.timer:Cancel() end
        mgr.timer = nil
        mgr.touchScheduled = false
        mgr.timerGen = (mgr.timerGen or 0) + 1
    end

    local function StopIfIdle()
        if mgr.count > 0 then return end
        CancelTimer()
    end

    local function RemoveAt(i)
        local last = mgr.count
        local icon = mgr.icons[i]
        local swap = mgr.icons[last]
        mgr.icons[i] = swap
        mgr.icons[last] = nil
        mgr.count = last - 1
        if swap then swap._msufGF_cdMgrIndex = i end
        if icon then
            icon._msufGF_cdMgrIndex = nil
            icon._msufGF_cdMgrRegistered = false
            icon._msufGF_cdSkipUntil = nil
            icon._msufGF_cdLastFS = nil
            icon._msufGF_cdLastR = nil
            icon._msufGF_cdLastG = nil
            icon._msufGF_cdLastB = nil
            icon._msufGF_cdLastA = nil
        end
        if mgr.count <= 0 then StopIfIdle() end
    end

    local function Tick()
        mgr.touchScheduled = false
        EnsureGFCooldownTextColorSettings()
        local now = GetTime()
        local secretsActive = IsGFSecretMode(now)
        local wantFast = now < (mgr.fastUntil or 0)
        local nextDue
        local isv = _gfIsSecretValue
        if not isv then
            isv = _G.issecretvalue or (C_Secrets and type(C_Secrets.IsSecret) == "function" and C_Secrets.IsSecret) or nil
            if isv then _gfIsSecretValue = isv end
        end
        local secretNoDetector = (secretsActive and not isv)

        local i = mgr.count
        while i > 0 do
            local icon = mgr.icons[i]
            local cd = icon and icon.cooldown
            if not icon or not cd or not icon.IsShown or not icon:IsShown()
               or icon._msufCdHidden == true or not _gfCdTextBucketsEnabled then
                RemoveAt(i)
            else
                local fs = ResolveCooldownFontString(cd)
                local obj = icon._msufGF_cdDurationObj or cd._msufGF_cdDurationObj
                if fs and obj then
                    local skipUntil = icon._msufGF_cdSkipUntil
                    if skipUntil and now < skipUntil then
                        if not nextDue or skipUntil < nextDue then nextDue = skipUntil end
                    else
                        local r, g, b, a = _gfCdSafeR, _gfCdSafeG, _gfCdSafeB, _gfCdSafeA
                        local bucket = 3
                        local iconSecret = false
                        local didCurveEval = false

                        if _gfCdCurve and type(obj.EvaluateRemainingDuration) == "function" then
                            local col = obj:EvaluateRemainingDuration(_gfCdCurve)
                            if col then
                                didCurveEval = true
                                if col.GetRGBA then r, g, b, a = col:GetRGBA()
                                elseif col.GetRGB then r, g, b = col:GetRGB(); a = 1 end
                            end
                        end
                        if secretsActive and secretNoDetector then
                            iconSecret = true
                        elseif isv and isv(r) then
                            iconSecret = true
                        end
                        if not didCurveEval then
                            r, g, b, a = _gfCdSafeR, _gfCdSafeG, _gfCdSafeB, _gfCdSafeA
                            iconSecret = secretsActive or iconSecret
                        end

                        if not iconSecret then
                            if r == _gfCdExpR and g == _gfCdExpG and b == _gfCdExpB then
                                bucket = 0; wantFast = true
                            elseif r == _gfCdUrgR and g == _gfCdUrgG and b == _gfCdUrgB then
                                bucket = 1; wantFast = true
                            elseif r == _gfCdWarnR and g == _gfCdWarnG and b == _gfCdWarnB then
                                bucket = 2; wantFast = true
                            elseif r == _gfCdNormR and g == _gfCdNormG and b == _gfCdNormB then
                                bucket = 4
                            end
                        else
                            wantFast = true
                        end

                        if iconSecret then
                            icon._msufGF_cdSkipUntil = nil
                        elseif bucket == 4 then
                            icon._msufGF_cdSkipUntil = now + 5.0
                            if not nextDue or icon._msufGF_cdSkipUntil < nextDue then nextDue = icon._msufGF_cdSkipUntil end
                        elseif bucket == 3 then
                            icon._msufGF_cdSkipUntil = now + 2.0
                            if not nextDue or icon._msufGF_cdSkipUntil < nextDue then nextDue = icon._msufGF_cdSkipUntil end
                        else
                            icon._msufGF_cdSkipUntil = nil
                        end
                        ApplyGFCooldownTextColor(icon, fs, r, g, b, a, iconSecret)
                    end
                end
            end
            i = i - 1
        end

        if wantFast then
            mgr.fastUntil = now + 1.50
            mgr.interval = secretsActive and (mgr.secretInterval or 0.20) or (mgr.fastInterval or 0.10)
        elseif nextDue and nextDue > now then
            local delay = nextDue - now
            local maxIdle = mgr.maxIdleInterval or 5.0
            if delay < 0.05 then delay = 0.05 elseif delay > maxIdle then delay = maxIdle end
            mgr.interval = delay
        else
            mgr.interval = mgr.slowInterval or 0.50
        end
        StopIfIdle()
        if mgr.count > 0 and mgr._Schedule then mgr._Schedule(mgr.interval) end
    end

    local tickCallback = function()
        mgr.timer = nil
        Tick()
    end

    local function Schedule(delay)
        if mgr.count <= 0 then StopIfIdle(); return end
        if type(delay) ~= "number" or delay < 0 then delay = 0 end
        CancelTimer()
        mgr.touchScheduled = delay <= 0
        if C_Timer and type(C_Timer.NewTimer) == "function" then
            mgr.timer = C_Timer.NewTimer(delay, tickCallback)
        elseif C_Timer and type(C_Timer.After) == "function" then
            mgr.timerGen = (mgr.timerGen or 0) + 1
            local gen = mgr.timerGen
            C_Timer.After(delay, function()
                if mgr.timerGen ~= gen then return end
                mgr.touchScheduled = false
                Tick()
            end)
        end
    end

    mgr._RemoveAt = RemoveAt
    mgr._Schedule = Schedule
    return mgr
end

_GF_RegisterCooldownTextIcon = function(icon)
    if not icon or not icon.cooldown or icon._msufGF_cdMgrRegistered == true then return end
    EnsureGFCooldownTextColorSettings()
    if not _gfCdTextBucketsEnabled then return end
    local mgr = EnsureGFCooldownTextMgr()
    local idx = mgr.count + 1
    mgr.count = idx
    mgr.icons[idx] = icon
    icon._msufGF_cdMgrRegistered = true
    icon._msufGF_cdMgrIndex = idx
    if mgr.count == 1 and mgr._Schedule then mgr._Schedule(0) end
end

_GF_UnregisterCooldownTextIcon = function(icon)
    if not icon then return end
    if icon._msufGF_cdMgrRegistered ~= true then
        icon._msufGF_cdMgrIndex = nil
        return
    end
    local mgr = _gfCdTextMgr
    local idx = icon._msufGF_cdMgrIndex
    if mgr and type(idx) == "number" and idx >= 1 and idx <= mgr.count and mgr._RemoveAt then
        mgr._RemoveAt(idx)
    else
        icon._msufGF_cdMgrRegistered = false
        icon._msufGF_cdMgrIndex = nil
    end
end

_GF_TouchCooldownTextIcon = function(icon)
    if not icon then return end
    icon._msufGF_cdSkipUntil = nil
    if icon._msufGF_cdMgrRegistered == true then
        local mgr = _gfCdTextMgr
        if mgr and mgr.count > 0 and mgr._Schedule and not mgr.touchScheduled then
            mgr._Schedule(0)
        end
    end
end

local function ApplyGFCooldownTextColorMode(icon, fs)
    EnsureGFCooldownTextColorSettings()
    if _gfCdTextBucketsEnabled and icon and icon._msufGF_cdDurationObj then
        _GF_RegisterCooldownTextIcon(icon)
        _GF_TouchCooldownTextIcon(icon)
        return true
    end
    _GF_UnregisterCooldownTextIcon(icon)
    ApplyGFCooldownTextColor(icon, fs, _gfCdSafeR, _gfCdSafeG, _gfCdSafeB, _gfCdSafeA, false)
    return true
end

function GF.InvalidateCooldownTextColors()
    _gfCdTextSettingsDirty = true
end

function GF.ForceCooldownTextRecolor()
    _gfCdTextSettingsDirty = true
    local mgr = _gfCdTextMgr
    if mgr and mgr.count and mgr.count > 0 then
        for i = 1, mgr.count do
            local icon = mgr.icons[i]
            if icon then
                icon._msufGF_cdSkipUntil = nil
                icon._msufGF_cdLastFS = nil
                icon._msufGF_cdLastR = nil
                icon._msufGF_cdLastG = nil
                icon._msufGF_cdLastB = nil
                icon._msufGF_cdLastA = nil
            end
        end
        if mgr._Schedule then mgr._Schedule(0) end
    end
end

function GF.ForceAuraTextColorRefresh()
    if GF.ForceCooldownTextRecolor then GF.ForceCooldownTextRecolor() end
    if GF.RequestAuraRefresh then
        GF.RequestAuraRefresh()
    elseif GF.MarkAllDirty then
        GF.MarkAllDirty(GF.DIRTY_ALL or 0x3F)
    end
    if GF.RefreshPreviewHandles then GF.RefreshPreviewHandles() end
end

_G.MSUF_GF_InvalidateCooldownTextCurve = GF.InvalidateCooldownTextColors
_G.MSUF_GF_ForceCooldownTextRecolor = GF.ForceCooldownTextRecolor
_G.MSUF_GF_ForceAuraTextColorRefresh = GF.ForceAuraTextColorRefresh

do
    local f = CreateFrame("Frame")
    if f and f.RegisterEvent then
        f:RegisterEvent("PLAYER_REGEN_DISABLED")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:SetScript("OnEvent", function()
            if _gfCdTextMgr and _gfCdTextMgr.count and _gfCdTextMgr.count > 0 then
                GF.ForceCooldownTextRecolor()
            end
        end)
    end
end

-- ApplyCooldownVisualStyle(cd, reverse, drawSwipe)
-- `reverse` is the cooldownSwipeDarkenOnLoss bool. Caller pre-resolves it
-- once per render (RenderGroup) or per-icon-event (RefreshAuraIcon) from
-- f._c.cdReverse — eliminates GF.GetConf from this hot path.
-- Diff-gates remain per-icon (correctness — required for live-apply).
local function ApplyCooldownVisualStyle(cd, reverse, drawSwipe)
    if not cd then return end
    drawSwipe = drawSwipe ~= false

    if cd._msufGFDrawEdge ~= false then
        cd._msufGFDrawEdge = false
        cd:SetDrawEdge(false)
    end
    if cd.SetDrawBling and cd._msufGFDrawBling ~= false then
        cd._msufGFDrawBling = false
        cd:SetDrawBling(false)
    end
    if cd._msufGFReverse ~= reverse then
        cd._msufGFReverse = reverse
        cd:SetReverse(reverse)
    end
    if cd._msufGFDrawSwipe ~= drawSwipe then
        cd._msufGFDrawSwipe = drawSwipe
        cd:SetDrawSwipe(drawSwipe)
    end
end

------------------------------------------------------------------------
-- Apply cooldown text font (diff-gated, global font, lazy FontString discovery)
------------------------------------------------------------------------
local ScaleFrameValue

-- ApplyCooldownFont(ic, gcfg, gFont, wantFlags, baseR, baseG, baseB, baseA, frameScale)
-- Caller (RenderGroup) pre-resolves the four style values once per render
-- group — eliminates per-icon ResolveGlobalFont + ResolveCooldownBaseColor
-- calls. Per-icon diff-gates remain for live-apply correctness.
local function ApplyCooldownFont(ic, gcfg, gFont, wantFlags, baseR, baseG, baseB, baseA, frameScale, isRetry)
    local cd = ic and ic.cooldown
    if not cd then return end
    local showCd = WantsCooldownText(gcfg)
    local wantHide = not showCd
    ic._msufCdHidden = wantHide
    cd:SetHideCountdownNumbers(wantHide)
    if not showCd then
        if _GF_UnregisterCooldownTextIcon then _GF_UnregisterCooldownTextIcon(ic) end
        return
    end

    local forceLookup = cd._msufCooldownFontStringDirty == true or isRetry == true
    cd._msufCooldownFontStringDirty = nil
    local fs = ResolveCooldownFontString(cd, forceLookup)
    if not fs then
        if not isRetry and not cd._msufGFCdFontRetryQueued then
            local timer = _G.C_Timer
            if timer and timer.After then
                cd._msufGFCdFontRetryQueued = true
                local retryIcon = ic
                local retryCd = cd
                local retryGroup = ic._msufAuraGroupKey
                timer.After(0, function()
                    retryCd._msufGFCdFontRetryQueued = nil
                    if retryIcon and retryIcon.cooldown == retryCd
                       and retryIcon._msufAuraGroupKey == retryGroup then
                        retryCd._msufCooldownFontStringDirty = true
                        ApplyCooldownFont(retryIcon, gcfg, gFont, wantFlags, baseR, baseG, baseB, baseA, frameScale, true)
                    end
                end)
            end
        end
        return
    end

    cd._msufGFCdFontRetryQueued = nil
    local fsChanged = cd._msufGFCdStyledFS ~= fs
    if fsChanged then cd._msufGFCdStyledFS = fs end

    local size = ScaleFrameValue((gcfg and gcfg.cooldownSize) or 8, frameScale or 1, 6)

    -- Diff-gate: skip redundant SetFont (same pattern as A2_Icons line 938)
    if fsChanged or cd._msufGFCdTextSize ~= size or cd._msufGFCdFontPath ~= gFont
       or cd._msufGFCdFontFlags ~= wantFlags then
        if gFont and fs.SetFont then
            fs:SetFont(gFont, size, wantFlags)
        end
        cd._msufGFCdTextSize = size
        cd._msufGFCdFontPath = gFont
        cd._msufGFCdFontFlags = wantFlags
    end

    -- Anchor + offset (live-apply via diff-gate on anchor+x+y)
    local anchor = (gcfg and gcfg.cooldownAnchor) or "CENTER"
    local ox = ScaleFrameValue((gcfg and gcfg.cooldownOffsetX) or 0, frameScale or 1)
    local oy = ScaleFrameValue((gcfg and gcfg.cooldownOffsetY) or 0, frameScale or 1)
    if fsChanged or cd._msufGFCdAnchor ~= anchor or cd._msufGFCdOX ~= ox or cd._msufGFCdOY ~= oy then
        cd._msufGFCdAnchor = anchor
        cd._msufGFCdOX = ox
        cd._msufGFCdOY = oy
        fs:ClearAllPoints()
        fs:SetPoint(anchor, cd, anchor, ox, oy)
    end

    if ApplyGFCooldownTextColorMode(ic, fs) then return end

    if fsChanged or cd._msufGFCdColorR ~= baseR or cd._msufGFCdColorG ~= baseG
        or cd._msufGFCdColorB ~= baseB or cd._msufGFCdColorA ~= baseA
    then
        cd._msufGFCdColorR = baseR
        cd._msufGFCdColorG = baseG
        cd._msufGFCdColorB = baseB
        cd._msufGFCdColorA = baseA
        if fs.SetTextColor then
            fs:SetTextColor(baseR, baseG, baseB, baseA)
        elseif fs.SetVertexColor then
            fs:SetVertexColor(baseR, baseG, baseB, baseA)
        end
    end
end

------------------------------------------------------------------------
-- Apply stack count layout (font size, anchor, offset)
-- Diff-gated per icon for live-apply.
-- Caller (RenderGroup) pre-resolves gFont + wantFlags once per render group.
------------------------------------------------------------------------
local function ApplyStackLayout(ic, gcfg, gFont, wantFlags, frameScale)
    local fs = ic and ic.count
    if not fs then return end

    local size = ScaleFrameValue(gcfg.stackSize or 10, frameScale or 1, 6)
    local anchor = gcfg.stackAnchor or "BOTTOMRIGHT"
    local ox = ScaleFrameValue(gcfg.stackOffsetX or -1, frameScale or 1)
    local oy = ScaleFrameValue(gcfg.stackOffsetY or 1, frameScale or 1)

    if ic._msufGFStkSize ~= size or ic._msufGFStkFont ~= gFont then
        if gFont and fs.SetFont then
            fs:SetFont(gFont, size, wantFlags)
        end
        ic._msufGFStkSize = size
        ic._msufGFStkFont = gFont
    end

    if ic._msufGFStkAnchor ~= anchor or ic._msufGFStkOX ~= ox or ic._msufGFStkOY ~= oy then
        ic._msufGFStkAnchor = anchor
        ic._msufGFStkOX = ox
        ic._msufGFStkOY = oy
        fs:ClearAllPoints()
        fs:SetPoint(anchor, ic, anchor, ox, oy)
    end

    local sr, sg, sb, sa = ResolveStackTextColor()
    if ic._msufGFStkColorR ~= sr or ic._msufGFStkColorG ~= sg
        or ic._msufGFStkColorB ~= sb or ic._msufGFStkColorA ~= sa then
        ic._msufGFStkColorR = sr
        ic._msufGFStkColorG = sg
        ic._msufGFStkColorB = sb
        ic._msufGFStkColorA = sa
        fs:SetTextColor(sr, sg, sb, sa)
    end
end

------------------------------------------------------------------------
-- Resolve group config from DB
------------------------------------------------------------------------
local function GetGroupCfg(kind, groupKey)
    local conf = GF.GetConf and GF.GetConf(kind)
    local auras = conf and conf.auras
    if not auras then return nil end
    return auras[groupKey]
end

------------------------------------------------------------------------
-- Externals exclusion set (reused per frame update)
------------------------------------------------------------------------
local _externalsIDs = {}

------------------------------------------------------------------------
-- EQoL-style frame-local aura cache
-- Stores C_UnitAuras auraData by auraInstanceID and applies UNIT_AURA
-- deltas in Lua, so add/remove events do not need fresh GetAuraSlots scans.
------------------------------------------------------------------------
local AURA_KIND_HELPFUL  = 1
local AURA_KIND_HARMFUL  = 2
local AURA_KIND_EXTERNAL = 4
local AURA_KIND_DISPEL   = 8

local function HasAuraKind(flags, flag)
    return flags and flags % (flag * 2) >= flag
end

local function AddAuraKind(flags, flag)
    flags = flags or 0
    if HasAuraKind(flags, flag) then return flags end
    return flags + flag
end

local function NewAuraCache()
    return { auras = {}, order = {}, indexById = {} }
end

local function EnsureFrameAuraCache(f)
    local st = f._msufGFAuraCache
    if not st then
        st = {
            buff = NewAuraCache(),
            debuff = NewAuraCache(),
            externals = NewAuraCache(),
            flagsById = {},
        }
        f._msufGFAuraCache = st
    end
    return st
end

local function ResetAuraCache(cache)
    if not cache then return end
    for k in pairs(cache.auras) do cache.auras[k] = nil end
    for k in pairs(cache.indexById) do cache.indexById[k] = nil end
    for i = 1, #cache.order do cache.order[i] = nil end
    cache._orderDirty = nil
end

local function ClearFrameAuraCache(f)
    local st = f and f._msufGFAuraCache
    if not st then return end
    ResetAuraCache(st.buff)
    ResetAuraCache(st.debuff)
    ResetAuraCache(st.externals)
    for k in pairs(st.flagsById) do st.flagsById[k] = nil end
    st.unit = nil
    st.sig = nil
    st.ready = nil
end
GF.ClearFrameAuraCache = ClearFrameAuraCache

local function AuraCacheAddOrder(cache, auraInstanceID)
    local idx = cache.indexById[auraInstanceID]
    if idx then return idx, false end
    idx = #cache.order + 1
    cache.order[idx] = auraInstanceID
    cache.indexById[auraInstanceID] = idx
    return idx, true
end

local function AuraCachePut(cache, aura)
    local auraInstanceID = aura and aura.auraInstanceID
    if not auraInstanceID then return nil, false end
    cache.auras[auraInstanceID] = aura
    return AuraCacheAddOrder(cache, auraInstanceID)
end

local function AuraCacheRemove(cache, auraInstanceID)
    if not (cache and auraInstanceID) then return nil end
    local idx = cache.indexById[auraInstanceID]
    if cache.auras[auraInstanceID] ~= nil then
        cache.auras[auraInstanceID] = nil
    end
    if idx then
        cache.indexById[auraInstanceID] = nil
        cache._orderDirty = true
    end
    return idx
end

local function CompactAuraCache(cache)
    if not (cache and cache._orderDirty) then return end
    local order, indexById, auras = cache.order, cache.indexById, cache.auras
    for k in pairs(indexById) do indexById[k] = nil end
    local write = 1
    for read = 1, #order do
        local auraInstanceID = order[read]
        if auraInstanceID and auras[auraInstanceID] and not indexById[auraInstanceID] then
            order[write] = auraInstanceID
            indexById[auraInstanceID] = write
            write = write + 1
        end
    end
    for i = write, #order do order[i] = nil end
    cache._orderDirty = nil
end

local function AuraCacheVisibleIndex(cache, auraInstanceID, maxIcons, includeSpare)
    local idx = cache and cache.indexById and cache.indexById[auraInstanceID]
    if not idx then return false end
    local limit = (tonumber(maxIcons) or 0) + (includeSpare and 1 or 0)
    return limit <= 0 or idx <= limit
end

local function AuraMatchesFilter(unit, aura, filter)
    local auraInstanceID = aura and aura.auraInstanceID
    if not (unit and auraInstanceID and filter) then return false end
    if _isFilteredOut then
        return _isFilteredOut(unit, auraInstanceID, filter) == false
    end
    if type(filter) == "string" then
        if filter:find("HELPFUL", 1, true) then return aura.isHelpful == true end
        if filter:find("HARMFUL", 1, true) then return aura.isHarmful == true end
    end
    return false
end

local function ScanAuraCache(unit, cache, filter, queryLimit)
    ResetAuraCache(cache)
    if not (unit and cache and filter) then return end
    local slots, slotCount = QuerySlots(unit, filter, queryLimit)
    for i = 2, slotCount do
        local aura = _getBySlot(unit, slots[i])
        if aura and aura.auraInstanceID then
            AuraCachePut(cache, aura)
        end
    end
end

local _fullScanSeen = {}
local function ScanAuraCacheSeen(unit, cache, filter, queryLimit, seen)
    ResetAuraCache(cache)
    if not (unit and cache and filter) then return end
    local slots, slotCount = QuerySlots(unit, filter, queryLimit)
    for i = 2, slotCount do
        local aura = _getBySlot(unit, slots[i])
        local aid = aura and aura.auraInstanceID
        if aid and not seen[aid] then
            seen[aid] = true
            AuraCachePut(cache, aura)
        end
    end
end

local function AuraQueryLimit(maxIcons)
    local n = tonumber(maxIcons) or 0
    if n < 1 then return nil end
    return n + 1
end

local function BuildAuraCacheSig(buffFilter, debuffFilter, externalFilter, buffMax, debuffMax, externalMax, wantBuff, wantDebuff, wantExternals, wantDispel)
    return tostring(buffFilter) .. "\001" .. tostring(debuffFilter) .. "\001" .. tostring(externalFilter) .. "\001"
        .. tostring(buffMax) .. "\001" .. tostring(debuffMax) .. "\001" .. tostring(externalMax) .. "\001"
        .. tostring(wantBuff) .. "\001" .. tostring(wantDebuff) .. "\001" .. tostring(wantExternals) .. "\001" .. tostring(wantDispel)
end

local function GetAuraKindFlags(unit, aura, buffFilter, debuffFilter, externalFilter, wantBuff, wantDebuff, wantExternals, wantDispel)
    if not (unit and aura and aura.auraInstanceID) then return nil end
    local flags
    if wantBuff and AuraMatchesFilter(unit, aura, buffFilter) then
        flags = AddAuraKind(flags, AURA_KIND_HELPFUL)
    end
    if wantDebuff and AuraMatchesFilter(unit, aura, debuffFilter) then
        flags = AddAuraKind(flags, AURA_KIND_HARMFUL)
    end
    if wantExternals and AuraMatchesFilter(unit, aura, externalFilter) then
        flags = AddAuraKind(flags, AURA_KIND_EXTERNAL)
    end
    if wantDispel and AuraMatchesFilter(unit, aura, _DISPEL_FILTER) then
        flags = AddAuraKind(flags, AURA_KIND_DISPEL)
    end
    return flags
end

local function CacheAuraWithFlags(st, aura, flags)
    local auraInstanceID = aura and aura.auraInstanceID
    if not (st and auraInstanceID) then return end

    if HasAuraKind(flags, AURA_KIND_HELPFUL) then
        AuraCachePut(st.buff, aura)
    else
        AuraCacheRemove(st.buff, auraInstanceID)
    end

    if HasAuraKind(flags, AURA_KIND_HARMFUL) then
        AuraCachePut(st.debuff, aura)
    else
        AuraCacheRemove(st.debuff, auraInstanceID)
    end

    if HasAuraKind(flags, AURA_KIND_EXTERNAL) then
        AuraCachePut(st.externals, aura)
    else
        AuraCacheRemove(st.externals, auraInstanceID)
    end

    st.flagsById[auraInstanceID] = flags or nil
end

local function TouchFromFlags(st, auraInstanceID, flags, buffMax, debuffMax, externalMax, includeSpare)
    local touchBuff, touchDebuff, touchExt, touchDispel
    if HasAuraKind(flags, AURA_KIND_HELPFUL) and AuraCacheVisibleIndex(st.buff, auraInstanceID, buffMax, includeSpare) then
        touchBuff = true
    end
    if (HasAuraKind(flags, AURA_KIND_HARMFUL) or HasAuraKind(flags, AURA_KIND_DISPEL))
        and AuraCacheVisibleIndex(st.debuff, auraInstanceID, debuffMax, includeSpare) then
        touchDebuff = HasAuraKind(flags, AURA_KIND_HARMFUL) or nil
        touchDispel = HasAuraKind(flags, AURA_KIND_DISPEL) or nil
    elseif HasAuraKind(flags, AURA_KIND_DISPEL) then
        touchDispel = true
    end
    if HasAuraKind(flags, AURA_KIND_EXTERNAL) and AuraCacheVisibleIndex(st.externals, auraInstanceID, externalMax, includeSpare) then
        touchExt = true
        touchBuff = true
    end
    return touchBuff, touchDebuff, touchExt, touchDispel
end

local function MergeTouches(a, b, c, d, aa, bb, cc, dd)
    return a or aa, b or bb, c or cc, d or dd
end

local function FullScanFrameAuraCache(f, unit, sig, buffFilter, debuffFilter, externalFilter, buffMax, debuffMax, externalMax, wantBuff, wantDebuff, wantExternals, wantDispel)
    local st = EnsureFrameAuraCache(f)
    ResetAuraCache(st.buff)
    ResetAuraCache(st.debuff)
    ResetAuraCache(st.externals)
    for k in pairs(st.flagsById) do st.flagsById[k] = nil end
    for k in pairs(_fullScanSeen) do _fullScanSeen[k] = nil end

    if wantExternals then
        ScanAuraCacheSeen(unit, st.externals, externalFilter, AuraQueryLimit(externalMax), _fullScanSeen)
    end
    if wantDebuff then
        ScanAuraCache(unit, st.debuff, debuffFilter or "HARMFUL", AuraQueryLimit(debuffMax))
    end
    if wantBuff then
        ScanAuraCacheSeen(unit, st.buff, buffFilter, AuraQueryLimit(buffMax), _fullScanSeen)
    end
    for k in pairs(_fullScanSeen) do _fullScanSeen[k] = nil end

    if wantDispel and _getByIndex then
        local aura = _getByIndex(unit, 1, _DISPEL_FILTER)
        local aid = aura and aura.auraInstanceID
        if aid then
            st.flagsById[aid] = AddAuraKind(st.flagsById[aid], AURA_KIND_DISPEL)
        end
    end

    for aid, aura in pairs(st.buff.auras) do
        st.flagsById[aid] = AddAuraKind(st.flagsById[aid], AURA_KIND_HELPFUL)
    end
    for aid, aura in pairs(st.debuff.auras) do
        local flags = st.flagsById[aid] or 0
        if wantDebuff then
            flags = AddAuraKind(flags, AURA_KIND_HARMFUL)
        end
        if wantDispel and AuraMatchesFilter(unit, aura, _DISPEL_FILTER) then
            flags = AddAuraKind(flags, AURA_KIND_DISPEL)
        end
        st.flagsById[aid] = flags ~= 0 and flags or nil
    end
    for aid in pairs(st.externals.auras) do
        st.flagsById[aid] = AddAuraKind(st.flagsById[aid], AURA_KIND_EXTERNAL)
    end

    st.unit = unit
    st.sig = sig
    st.ready = true
    return st
end

local function UpdateFrameAuraCacheDelta(f, unit, updateInfo, buffFilter, debuffFilter, externalFilter, buffMax, debuffMax, externalMax, wantBuff, wantDebuff, wantExternals, wantDispel)
    local st = f and f._msufGFAuraCache
    if not (st and st.ready and updateInfo) then return nil end
    if not _apisBound then BindAPIs() end

    local touchBuff, touchDebuff, touchExt, touchDispel
    local flagsById = st.flagsById

    local removed = updateInfo.removedAuraInstanceIDs
    if removed then
        for i = 1, #removed do
            local aid = removed[i]
            local oldFlags = flagsById[aid]
            if oldFlags ~= nil then
                local tb, td, te, tp = TouchFromFlags(st, aid, oldFlags, buffMax, debuffMax, externalMax, true)
                touchBuff, touchDebuff, touchExt, touchDispel = MergeTouches(touchBuff, touchDebuff, touchExt, touchDispel, tb, td, te, tp)
                AuraCacheRemove(st.buff, aid)
                AuraCacheRemove(st.debuff, aid)
                AuraCacheRemove(st.externals, aid)
                flagsById[aid] = nil
            end
        end
    end

    local added = updateInfo.addedAuras
    if added then
        for i = 1, #added do
            local aura = added[i]
            local aid = aura and aura.auraInstanceID
            if aid then
                local flags = GetAuraKindFlags(unit, aura, buffFilter, debuffFilter, externalFilter, wantBuff, wantDebuff, wantExternals, wantDispel)
                CacheAuraWithFlags(st, aura, flags)
                local tb, td, te, tp = TouchFromFlags(st, aid, flags, buffMax, debuffMax, externalMax, false)
                touchBuff, touchDebuff, touchExt, touchDispel = MergeTouches(touchBuff, touchDebuff, touchExt, touchDispel, tb, td, te, tp)
            end
        end
    end

    local updated = updateInfo.updatedAuraInstanceIDs
    if updated and _getByAuraInstanceID then
        for i = 1, #updated do
            local aid = updated[i]
            if aid then
                local oldFlags = flagsById[aid]
                if oldFlags then
                    local tb, td, te, tp = TouchFromFlags(st, aid, oldFlags, buffMax, debuffMax, externalMax, false)
                    touchBuff, touchDebuff, touchExt, touchDispel = MergeTouches(touchBuff, touchDebuff, touchExt, touchDispel, tb, td, te, tp)

                    local aura = _getByAuraInstanceID(unit, aid)
                    if aura then
                        local flags = GetAuraKindFlags(unit, aura, buffFilter, debuffFilter, externalFilter, wantBuff, wantDebuff, wantExternals, wantDispel)
                        CacheAuraWithFlags(st, aura, flags)
                        tb, td, te, tp = TouchFromFlags(st, aid, flags, buffMax, debuffMax, externalMax, false)
                        touchBuff, touchDebuff, touchExt, touchDispel = MergeTouches(touchBuff, touchDebuff, touchExt, touchDispel, tb, td, te, tp)
                    else
                        AuraCacheRemove(st.buff, aid)
                        AuraCacheRemove(st.debuff, aid)
                        AuraCacheRemove(st.externals, aid)
                        flagsById[aid] = nil
                    end
                end
            end
        end
    end

    return st, touchBuff, touchDebuff, touchExt, touchDispel
end

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

local function GetDefaultPreviewCount(kind)
    if kind == "mythicraid" then return 20 end
    if kind == "raid" then return 30 end
    return 5
end

local function GetPreviewReferenceCount(kind)
    local previewN = GF.GetPreviewAuraCount and GF.GetPreviewAuraCount(kind) or 0
    if previewN and previewN > 0 then return previewN end

    local isRaidLike = (kind == "raid" or kind == "mythicraid")
    if isRaidLike then
        local inRaid = _G.IsInRaid and _G.IsInRaid()
        local liveKind = (GF.GetLiveRaidKind and GF.GetLiveRaidKind()) or "raid"
        if inRaid and liveKind == kind then
            local liveN = (GetNumGroupMembers and GetNumGroupMembers()) or 0
            if liveN > 0 then return liveN end
        end
        return GetDefaultPreviewCount(kind)
    end

    if _G.IsInGroup and _G.IsInGroup() and not (_G.IsInRaid and _G.IsInRaid()) then
        local liveN = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        if liveN > 0 then return liveN end
    end
    return GetDefaultPreviewCount(kind)
end

--- Preview variant: uses the same visible/live group size that the user is editing.
local function GetPreviewDynamicScale(conf, kind)
    if not conf or not conf.auras or not conf.auras.dynamicScale then return 1 end
    local n = GetPreviewReferenceCount(kind)
    if n <= 15 then return 1 end
    if n <= 25 then return 0.85 end
    return 0.70
end

local function GetFrameScale(kind, conf)
    local s = conf and conf._resolvedFrameScale
    if s and s > 0 then return s end
    if GF.GetFrameScale then
        s = GF.GetFrameScale(kind)
        if s and s > 0 then return s end
    end
    return 1
end

ScaleFrameValue = function(value, scale, minValue)
    value = tonumber(value) or 0
    scale = tonumber(scale) or 1
    local v
    if scale == 1 then
        v = value
    elseif GF.ScaleValue then
        v = GF.ScaleValue(value, scale, minValue)
    else
        local scaled = value * scale
        if scaled >= 0 then
            v = math_floor(scaled + 0.5)
        else
            v = -math_floor((-scaled) + 0.5)
        end
        if minValue ~= nil and v < minValue then v = minValue end
    end
    if minValue ~= nil and v < minValue then v = minValue end
    return v
end

local function GetNativeAuraAPI()
    return ns and ns.MSUF_AuraNative
end

function GF.EnsureBlizzardAuraTypes(conf)
    if not conf then return nil end
    conf.auras = conf.auras or {}
    local Native = GetNativeAuraAPI()
    if Native then
        conf.auras.blizzardTypes = Native.EnsureTypes(conf.auras.blizzardTypes, true)
    else
        if type(conf.auras.blizzardTypes) ~= "table" then
            conf.auras.blizzardTypes = {
                buffs = true,
                debuffs = true,
                dispels = true,
                externals = true,
                privateAuras = true,
            }
        end
    end
    return conf.auras.blizzardTypes
end

function GF.GetAuraRendererMode(conf)
    local auras = conf and conf.auras
    if not auras then return "CUSTOM" end
    if auras.renderer == nil then return "BLIZZARD" end
    local Native = GetNativeAuraAPI()
    if Native then
        return Native.NormalizeRenderer(auras.renderer)
    end
    if auras.renderer == "CUSTOM" then return "CUSTOM" end
    return "BLIZZARD"
end

function GF.IsAuraRendererBlizzard(conf)
    return GF.GetAuraRendererMode(conf) == "BLIZZARD"
end

function GF.IsAuraRendererCustom(conf)
    return GF.GetAuraRendererMode(conf) == "CUSTOM"
end

function GF.IsAuraRendererMixed(conf)
    return false
end

function GF.IsBlizzardAuraTypeEnabled(conf, key)
    if not GF.IsAuraRendererBlizzard(conf) then return false end
    local auras = conf and conf.auras
    if not auras or auras.enabled == false then return false end
    if key == "dispels" and conf and conf.dispelEnabled == false then return false end
    local types = GF.EnsureBlizzardAuraTypes(conf)
    local Native = GetNativeAuraAPI()
    if Native and Native.Supported and not Native.Supported() then return false end

    if key == "privateAuras" then
        local pa = conf.privateAuras
        if pa and pa.enabled == false then return false end
    end
    if Native and Native.TypeEnabled then
        return Native.TypeEnabled(types, key, true)
    end
    return type(types) ~= "table" or types[key] ~= false
end

function GF.GetBlizzardAuraIconSize(conf, scale, frameScale)
    local auras = conf and conf.auras
    local raw = auras and tonumber(auras.blizzardIconSize)
    if not raw then
        local buffCfg = auras and auras.buff
        local debCfg = auras and auras.debuff
        local extCfg = auras and auras.externals
        local paCfg = conf and conf.privateAuras
        raw = (buffCfg and buffCfg.size) or (debCfg and debCfg.size) or (extCfg and extCfg.size) or (paCfg and paCfg.size) or 20
    end
    return ScaleFrameValue(raw, (scale or 1) * (frameScale or 1), 8)
end

local function ClearOneBlizzardAuraContainer(container)
    local Native = GetNativeAuraAPI()
    if Native and container then
        return Native.Clear(container) ~= false
    elseif container then
        local id = container._msufNativeAuraAnchorID
        local removeFn = _G.C_UnitAuras and _G.C_UnitAuras.RemovePrivateAuraAnchor
        if id and type(removeFn) == "function" then
            local ok, err = pcall(removeFn, id)
            if not ok then
                container._msufNativeAuraLastError = err
                return false
            end
        elseif id then
            container._msufNativeAuraLastError = "RemovePrivateAuraAnchor unavailable"
            return false
        end
        container:Hide()
        container._msufNativeAuraAnchorID = nil
        container._msufNativeAuraSignature = nil
        container._msufNativeAuraUnit = nil
        return true
    end
    return true
end

function GF.ClearBlizzardAuraContainer(f)
    if not f then return end
    if ClearOneBlizzardAuraContainer(f._msufGFNativeAuras) then
        f._msufGFNativeAuras = nil
    end
    local containers = f._msufGFNativeAuraContainers
    if containers then
        local allCleared = true
        for _, container in pairs(containers) do
            if not ClearOneBlizzardAuraContainer(container) then
                allCleared = false
            end
        end
        if allCleared then
            f._msufGFNativeAuraContainers = nil
        end
    end
    if f._msufGFNativeAuraRoot then f._msufGFNativeAuraRoot:Hide() end
end

local function NativeBlizzardAuraContainerReady(f, unit)
    local container = f and f._msufGFNativeAuras
    if not (container and container._msufNativeAuraAnchorID and container._msufNativeAuraSignature) then return false end
    local Native = GetNativeAuraAPI()
    local effectiveUnit = Native and Native.ResolveUnitToken and Native.ResolveUnitToken(unit) or unit
    return container._msufNativeAuraUnit == effectiveUnit
end

local function EnsureBlizzardAuraContainer(f, parent)
    if not f then return nil end
    local container = f._msufGFNativeAuras
    if not container then
        container = CreateFrame("Frame", nil, parent or f)
        container:EnableMouse(false)
        if container.SetMouseClickEnabled then container:SetMouseClickEnabled(false) end
        f._msufGFNativeAuras = container
    elseif parent and container.GetParent and container:GetParent() ~= parent then
        container:SetParent(parent)
    end
    return container
end

function GF.UpdateBlizzardAuraContainer(f, unit, conf, scale, frameScale, updateInfo)
    local Native = GetNativeAuraAPI()
    local auras = conf and conf.auras
    if not (Native and f and unit and auras and auras.enabled ~= false and GF.IsAuraRendererBlizzard(conf)) then
        GF.ClearBlizzardAuraContainer(f)
        return nil
    end
    if Native.Supported and not Native.Supported() then
        GF.ClearBlizzardAuraContainer(f)
        return nil
    end

    local types = GF.EnsureBlizzardAuraTypes(conf)
    local buffCfg = auras.buff or _EMPTY_AURA_CFG
    local debCfg = auras.debuff or _EMPTY_AURA_CFG
    local extCfg = auras.externals or _EMPTY_AURA_CFG
    local paCfg = conf.privateAuras or _EMPTY_AURA_CFG

    local renderBuffs = Native.TypeEnabled(types, "buffs", true)
    local renderDebuffs = Native.TypeEnabled(types, "debuffs", true)
    local renderDispels = Native.TypeEnabled(types, "dispels", true) and conf.dispelEnabled ~= false
    local renderExt = Native.TypeEnabled(types, "externals", true)
    local renderPrivate = Native.TypeEnabled(types, "privateAuras", true) and paCfg.enabled ~= false

    if not (renderBuffs or renderDebuffs or renderDispels or renderExt or renderPrivate) then
        GF.ClearBlizzardAuraContainer(f)
        return nil
    end

    -- Legacy cleanup: older builds used one native container per category.
    -- EQoL's performant path uses exactly one Blizzard container per unit frame.
    if f._msufGFNativeAuraContainers then
        for _, container in pairs(f._msufGFNativeAuraContainers) do
            ClearOneBlizzardAuraContainer(container)
        end
        f._msufGFNativeAuraContainers = nil
    end

    local kind = f._msufGFKind or "party"
    local groupType = (kind == "party") and 4 or 5
    local levelParent = f.statusIconLayer or f.barGroup or f
    local powerUsedHeight = (GF.GetEffectivePowerHeight and GF.GetEffectivePowerHeight(kind, unit, f._msufGFPreviewRole, conf))
        or ((GF.GetScaledPowerHeight and GF.GetScaledPowerHeight(kind)) or (conf.powerHeight or 0))
    if f._msufGFNativeAuraRoot then f._msufGFNativeAuraRoot:Hide() end
    local parent = f.statusIconLayer or f.barGroup or f
    local container = EnsureBlizzardAuraContainer(f, parent)
    if not container then return nil end

    local iconSize = GF.GetBlizzardAuraIconSize(conf, scale, frameScale)
    local bigDefensiveSize = renderExt and ScaleFrameValue(extCfg.size or iconSize, (scale or 1) * (frameScale or 1), 8) or iconSize
    -- Native Blizzard containers are intentionally not user-positioned.
    -- Blizzard owns the exact anchor and final placement; MSUF only supplies
    -- the native renderer settings such as aura types, counts and sizes.
    local iconAnchor = nil
    local iconOffsetX = 0
    local iconOffsetY = 0
    if renderPrivate and GF.ClearPrivateAuras then
        GF.ClearPrivateAuras(f)
    end
    local maxDebuffs = renderDebuffs and (tonumber(debCfg.max) or 6) or 0
    if renderPrivate then
        local privateMax = tonumber(paCfg.max) or 4
        if privateMax > maxDebuffs then maxDebuffs = privateMax end
    end
    local showDebuffs = renderDebuffs or renderPrivate
    local cfg = {
        showBuffs = renderBuffs,
        showDebuffs = showDebuffs,
        showDispels = renderDispels,
        showBigDefensive = renderExt,
        privateAuras = renderPrivate,
        maxBuffs = renderBuffs and (tonumber(buffCfg.max) or 6) or 0,
        maxDebuffs = maxDebuffs,
        maxDispelDebuffs = renderDispels and 3 or 0,
        iconSize = iconSize,
        bigDefensiveSize = bigDefensiveSize,
        showDispelOverlay = renderDispels,
        organizationType = auras.blizzardOrganizationType or auras.blizzardOrganization or "default",
        dispelMode = auras.blizzardDispelMode or "allDispellable",
        showCountdownFrame = true,
        showCountdownNumbers = auras.blizzardShowCooldownText ~= false,
        groupType = groupType,
        displayLargerRoleSpecificDebuffs = debCfg.displayLargerRoleSpecificDebuffs ~= false,
        powerBarUsedHeight = tonumber(powerUsedHeight) or 0,
        iconAnchor = iconAnchor,
        iconOffsetX = iconOffsetX,
        iconOffsetY = iconOffsetY,
    }

    local effectiveUnit = Native.ResolveUnitToken and Native.ResolveUnitToken(unit) or unit
    local desiredSig = Native.Signature and Native.Signature(effectiveUnit, cfg)
    local ready = container._msufNativeAuraAnchorID
        and container._msufNativeAuraUnit == effectiveUnit
        and (not desiredSig or container._msufNativeAuraSignature == desiredSig)
    if ready then
        if Native.ApplyFrameStrata then
            Native.ApplyFrameStrata(container, parent, levelParent)
        end
        container:Show()
        return {
            buffs = renderBuffs,
            debuffs = renderDebuffs,
            dispels = renderDispels,
            externals = renderExt,
            privateAuras = renderPrivate,
        }
    end

    local applied = Native.Apply(container, unit, cfg, parent, levelParent)

    return {
        buffs = applied and renderBuffs,
        debuffs = applied and renderDebuffs,
        dispels = applied and renderDispels,
        externals = applied and renderExt,
        privateAuras = applied and renderPrivate,
    }
end

------------------------------------------------------------------------
-- Main render: one aura group
------------------------------------------------------------------------
local function RenderGroup(f, unit, groupKey, gcfg, filter, isHarmful, parent, dedupIDs, scale, frameScale, sourceCache)
    if not gcfg or gcfg.enabled == false then
        HidePool(f[POOL_KEYS[groupKey]], 1)
        return 0, nil
    end

    local maxIcons = gcfg.max or 6
    local totalScale = (scale or 1) * (frameScale or 1)
    local iconSize = ScaleFrameValue(gcfg.size or 20, totalScale, 8)
    local anchor   = gcfg.anchor or "BOTTOMLEFT"
    local growth   = gcfg.growth or "RIGHTDOWN"
    local spacing  = ScaleFrameValue(gcfg.spacing or 1, frameScale or 1, 0)
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
        -- health - 1: above replacement-bg (on barGroup), below health fill
        wantLvl = f.health:GetFrameLevel() - 1
    else
        wantParent = parent
        wantLvl = (GF.GetFrameLayerLevel and GF.GetFrameLayerLevel(f, gcfg.layer, 5))
            or (parent:GetFrameLevel() + (gcfg.layer or 5))
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
    local cx = ScaleFrameValue(gcfg.x or 0, frameScale or 1)
    local cy = ScaleFrameValue(gcfg.y or 0, frameScale or 1)
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
    -- Full fallback only asks for visible icons + one spare. Dispel state uses
    -- the direct RAID_PLAYER_DISPELLABLE query, so debuffs no longer need the
    -- old fixed 12-slot scan.
    local slots, slotCount
    local order, aurasById, orderCount
    if sourceCache then
        CompactAuraCache(sourceCache)
        order = sourceCache.order
        aurasById = sourceCache.auras
        orderCount = #order
    else
        local queryLimit = maxIcons + 1
        slots, slotCount = QuerySlots(unit, filter, queryLimit)
    end
    local shown = 0
    local isBuff = (groupKey == "buff")
    local isExt  = (groupKey == "externals")
    local showCdText = WantsCooldownText(gcfg)
    local showCdSwipe = WantsCooldownSwipe(gcfg)
    local showCdVisual = showCdText or showCdSwipe
    local showStk = (gcfg.showStacks ~= false)
    local step = iconSize + spacing
    local topDispel = nil
    local topDispelColor = nil

    -- Pre-resolve Tier 2 blacklist hash (zero-alloc cached)
    local af = AF()
    local blHash = af and af.BuildBlacklistHash(gcfg) or nil

    -- ── Pre-resolve per-render-group style values (Fix A) ─────────────
    -- Hoisted out of the per-icon loop. Identical for all icons in this
    -- render. Per-icon helpers receive these as parameters and keep their
    -- own diff-gates for live-apply correctness.
    -- _styleReverse: cooldown swipe direction (cooldownSwipeDarkenOnLoss)
    --   sourced from f._c.cdReverse which BuildFrameCache populates from conf.
    --   Live-apply: Options toggle calls GF.RefreshVisuals → ApplyVisuals →
    --   BuildFrameCache → c.cdReverse refreshed.
    -- _styleGFont/_styleGFlags: ResolveGlobalFont (module-cached, invalidated
    --   by GF.InvalidateCdFont on font change).
    -- _styleBaseR/G/B/A: ResolveCooldownBaseColor (module-cached, invalidated
    --   by GF.InvalidateCdColor on color/font-color change).
    -- These do NOT cache numeric data (HP, stacks, durations) — only style.
    local _ownerC = f._c
    local _styleReverse  = _ownerC and _ownerC.cdReverse or false
    local _styleGFont, _styleGFlags = ResolveGlobalFont()
    local _styleBaseR, _styleBaseG, _styleBaseB, _styleBaseA = ResolveCooldownBaseColor()
    local _styleCdFlags  = gcfg.cooldownOutline or _styleGFlags or "OUTLINE"
    local _styleStkFlags = gcfg.stackOutline    or _styleGFlags or "OUTLINE"

    local startIndex = sourceCache and 1 or 2
    local endIndex = sourceCache and orderCount or slotCount
    for i = startIndex, endIndex do
        if shown >= maxIcons and (not isHarmful or topDispel) then break end
        local aura = sourceCache and aurasById[order[i]] or _getBySlot(unit, slots[i])
        if aura then
            local aid = aura.auraInstanceID
            if (isBuff and aid and _externalsIDs[aid])
               or (dedupIDs and aid and dedupIDs[aid]) then
                -- skip (claimed by externals or SpellIndicators)
            else
                -- Merged dispel: C-side check (secret-safe, BEFORE spell filter)
                if isHarmful and not topDispel and aid then
                    local dn = _GetReadableDispelName(aura.dispelName)
                    if _isFilteredOut then
                        local filtered = _isFilteredOut(unit, aid, _DISPEL_FILTER)
                        if filtered == false then
                            -- Prefer the real dispel school when the aura exposes it.
                            topDispel = dn or "DISPELLABLE"
                            f._msufGFDispelAuraID = aid
                            if _getDispelColor and _dispelColorCurve then
                                topDispelColor = _getDispelColor(unit, aid, _dispelColorCurve)
                            end
                        end
                    else
                        -- Legacy fallback: plain dispelName
                        if dn then
                            topDispel = dn
                            f._msufGFDispelAuraID = aid
                            if _getDispelColor and _dispelColorCurve then
                                topDispelColor = _getDispelColor(unit, aid, _dispelColorCurve)
                            end
                        end
                    end
                end

                -- Tier 2: Declassified spell blacklist (skip AFTER dispel check)
                local _skip = false
                if blHash and af then
                    local sid = af.DecodeSpellId(aura)
                    if af.IsBlacklisted(sid, blHash, aura) then
                        _skip = true
                    end
                end
                -- Skip auras with placeholder icons. Decode only accessible values so Lua
                -- never compares a secret-tagged icon against constants.
                if not _skip then
                    local iconFileID = DecodeAuraIconFileID(aura.icon)
                    if iconFileID == _QUESTION_MARK_ICON or iconFileID == _PADLOCK_ICON then
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
                        ic._msufAuraGroupCfg = gcfg
                        ic._msufAuraFrameScale = frameScale
                        ApplyCooldownVisualStyle(ic.cooldown, _styleReverse, showCdSwipe)
                        local prevAid = ic._msufAuraID
                        if prevAid == aid then
                            -- ══ SAME AURA ══ cheap refresh (cooldown sweep + stacks + layout)
                            ApplyCooldown(ic, unit, aid, showCdVisual, showCdText)
                            local cd = ic.cooldown
                            if cd then
                                local wantHide = not showCdText
                                if ic._msufCdHidden ~= wantHide then
                                    ic._msufCdHidden = wantHide
                                    cd:SetHideCountdownNumbers(wantHide)
                                end
                            end
                            ApplyCooldownFont(ic, gcfg, _styleGFont, _styleCdFlags, _styleBaseR, _styleBaseG, _styleBaseB, _styleBaseA, frameScale)
                            ApplyStackLayout(ic, gcfg, _styleGFont, _styleStkFlags, frameScale)
                            ApplyStacks(ic, unit, aid, aura.applications, showStk, gcfg)
                            if isHarmful then
                                ApplyDispelBorder(ic, unit, aid, aura.dispelName, true, showDisp)
                            elseif not ic._msufBorderBlack then
                                ic._msufBorderBlack = true
                                ic:SetBackdropBorderColor(0, 0, 0, 1)
                            end
                        else
                            -- ══ DIFFERENT AURA OR FIRST SHOW ══
                            ic._msufAuraID = aid
                            ic._msufUnit   = unit
                            ic._msufFilter = filter
                            ic._msufBorderBlack = nil

                            ic.texture:SetTexture(aura.icon or "")
                            if not ic.texture:IsShown() then ic.texture:Show() end

                            ApplyCooldown(ic, unit, aid, showCdVisual, showCdText)
                            local cd = ic.cooldown
                            if cd then
                                local wantHide = not showCdText
                                if ic._msufCdHidden ~= wantHide then
                                    ic._msufCdHidden = wantHide
                                    cd:SetHideCountdownNumbers(wantHide)
                                end
                            end
                            ApplyCooldownFont(ic, gcfg, _styleGFont, _styleCdFlags, _styleBaseR, _styleBaseG, _styleBaseB, _styleBaseA, frameScale)
                            ApplyStackLayout(ic, gcfg, _styleGFont, _styleStkFlags, frameScale)
                            ApplyStacks(ic, unit, aid, aura.applications, showStk, gcfg)

                            if isHarmful then
                                ApplyDispelBorder(ic, unit, aid, aura.dispelName, true, showDisp)
                            elseif not ic._msufBorderBlack then
                                ic._msufBorderBlack = true
                                ic:SetBackdropBorderColor(0, 0, 0, 1)
                            end

                        end

                        -- Position: deferred for centered growth, immediate otherwise.
                        -- Same-aura refreshes must re-enter this gate so size,
                        -- growth and anchor sliders apply without waiting for an
                        -- aura add/remove event.
                        if not isCentered and (ic._msufPosIdx ~= shown or ic._msufPosStep ~= step
                            or ic._msufPosPR ~= perRow or ic._msufPosAnchor ~= anchor
                            or ic._msufPosGrowth ~= growth)
                        then
                            ic._msufPosIdx = shown
                            ic._msufPosStep = step
                            ic._msufPosPR = perRow
                            ic._msufPosAnchor = anchor
                            ic._msufPosGrowth = growth
                            ic:ClearAllPoints()
                            local col = (shown - 1) % perRow
                            local row = math_floor((shown - 1) / perRow)
                            local ox = col * step * gv.px + row * step * gv.sx
                            local oy = col * step * gv.py + row * step * gv.sy
                            ic:SetPoint(anchor, container, anchor, ox, oy)
                        end

                        if not ic:IsShown() then ic:Show() end

                        if isExt and aid then
                            _externalsIDs[aid] = true
                        end
                    end
                end -- shown >= maxIcons
            end
        end
    end

    -- Centered growth: reposition when shown count OR step (size+spacing) changes
    if isCentered and shown > 0 then
        local prevCenterN = container._msufCenterN
        local prevCenterStep = container._msufCenterStep
        local prevCenterGrowth = container._msufCenterGrowth
        if prevCenterN ~= shown or prevCenterStep ~= step or prevCenterGrowth ~= growth then
            container._msufCenterN = shown
            container._msufCenterStep = step
            container._msufCenterGrowth = growth
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
        container._msufCenterStep = nil
        container._msufCenterGrowth = nil
    end

    -- Clear diff-gate flags on hidden icons
    local prevShown = pool._msufShown or #pool
    if prevShown < shown then prevShown = shown end
    for j = shown + 1, prevShown do
        local ic = pool[j]
        if ic then
            if _GF_UnregisterCooldownTextIcon then _GF_UnregisterCooldownTextIcon(ic) end
            ic._msufGF_cdDurationObj = nil
            if ic.cooldown then ic.cooldown._msufGF_cdDurationObj = nil end
            if ic:IsShown() then ic:Hide() end
            ic._msufPosIdx = nil
            ic._msufPosStep = nil
            ic._msufPosPR = nil
            ic._msufPosAnchor = nil
            ic._msufPosGrowth = nil
            ic._msufBorderBlack = nil
            ic._msufAuraID = nil
            ic._msufUnit = nil
            ic._msufFilter = nil
            ic._msufAuraGroupCfg = nil
            ic._msufAuraFrameScale = nil
        end
    end
    pool._msufShown = shown
    return shown, topDispel, topDispelColor
end

local function FillDisplayedExternalIDs(f, dst)
    for k in pairs(dst) do dst[k] = nil end
    local pool = f and f._msufAuraPool_externals
    if not pool then return end
    local shown = pool._msufShown or #pool
    for i = 1, shown do
        local ic = pool[i]
        if ic and ic:IsShown() and ic._msufAuraID then
            dst[ic._msufAuraID] = true
        end
    end
end

local function RefreshDisplayedAuraIDMap(f)
    if not f then return false end
    local disp = f._msufDisplayedAuraIDs
    if not disp then
        disp = {}
        f._msufDisplayedAuraIDs = disp
    else
        for k in pairs(disp) do disp[k] = nil end
    end

    local anyShown = false
    local function addPool(pool)
        if not pool then return end
        local shown = pool._msufShown or #pool
        for i = 1, shown do
            local ic = pool[i]
            if ic and ic:IsShown() and ic._msufAuraID then
                disp[ic._msufAuraID] = ic
                anyShown = true
            end
        end
    end

    addPool(f._msufAuraPool_buff)
    addPool(f._msufAuraPool_debuff)
    addPool(f._msufAuraPool_externals)
    return anyShown
end

------------------------------------------------------------------------
-- Main entry: UpdateFrameAuras (orchestrator for 3 groups)
------------------------------------------------------------------------
local function UpdateFrameAuras_SlotScanLegacy(f, unit, updateInfo)
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
        GF.ClearBlizzardAuraContainer(f)
        if GF.ClearPrivateAuras then GF.ClearPrivateAuras(f) end
        f._msufGFDispelAuraID = nil
        f._msufGFDispelColorObj = nil
        f._msufGFDispelColorRev = nil
        return
    end
    f._msufGFAurasHidden = nil

    if not UnitExists(unit) then
        HidePool(f[POOL_KEYS.buff], 1)
        HidePool(f[POOL_KEYS.debuff], 1)
        HidePool(f[POOL_KEYS.externals], 1)
        GF.ClearBlizzardAuraContainer(f)
        if GF.ClearPrivateAuras then GF.ClearPrivateAuras(f) end
        f._msufGFDispelAuraID = nil
        f._msufGFDispelColorObj = nil
        f._msufGFDispelColorRev = nil
        return
    end
    local parent = f.statusIconLayer or f.barGroup or f
    local scale = GetDynamicScale(conf)
    local frameScale = GetFrameScale(kind, conf)
    local anyShown = false
    local c = f._c
    local nativeBuffs, nativeDebuffs, nativeDispels, nativeExt, nativePrivate
    if c then
        nativeBuffs = c.nativeBlizzardBuffs
        nativeDebuffs = c.nativeBlizzardDebuffs
        nativeDispels = c.nativeBlizzardDispels
        nativeExt = c.nativeBlizzardExt
        nativePrivate = c.nativeBlizzardPrivate
    else
        local nativeEnabled = GF.IsBlizzardAuraTypeEnabled
        nativeBuffs = nativeEnabled and nativeEnabled(conf, "buffs")
        nativeDebuffs = nativeEnabled and nativeEnabled(conf, "debuffs")
        nativeDispels = nativeEnabled and nativeEnabled(conf, "dispels")
        nativeExt = nativeEnabled and nativeEnabled(conf, "externals")
        nativePrivate = nativeEnabled and nativeEnabled(conf, "privateAuras")
    end
    local buffCfg = auras.buff or _EMPTY_AURA_CFG
    local debCfg = auras.debuff or _EMPTY_AURA_CFG
    local extCfg = auras.externals or _EMPTY_AURA_CFG
    local nativeRendered = nativeBuffs
        or nativeDebuffs
        or nativeDispels
        or nativeExt
        or nativePrivate
    -- EQoL-style fast path: UNIT_AURA deltas do not need to re-register an
    -- already applied Blizzard container. Full/options refreshes still rebuild.
    if not (updateInfo and not updateInfo.isFullUpdate and nativeRendered and NativeBlizzardAuraContainerReady(f, unit)) then
        GF.UpdateBlizzardAuraContainer(f, unit, conf, scale, frameScale, updateInfo)
    end

    if c and c.nativeBlizzardAuraOnly then
        if not f._msufGFExtHidden then
            HidePool(f[POOL_KEYS.externals], 1)
            f._msufGFExtHidden = true
        end
        if not f._msufGFDebHidden then
            HidePool(f[POOL_KEYS.debuff], 1)
            f._msufGFDebHidden = true
        end
        if not f._msufGFBufHidden then
            HidePool(f[POOL_KEYS.buff], 1)
            f._msufGFBufHidden = true
        end
        f._msufGFMergedDispel = nil
        f._msufGFDispelAuraID = nil
        f._msufGFDispelColorObj = nil
        f._msufGFDispelColorRev = nil
        local disp = f._msufDisplayedAuraIDs
        if disp then for k in pairs(disp) do disp[k] = nil end end
        return
    end

    if not _apisBound then BindAPIs() end
    if not _getSlots or not _getBySlot then return end

    -- 1) Externals
    local extCfg = auras.externals
    if nativeExt then
        if not f._msufGFExtHidden then
            f._msufGFExtHidden = true
            HidePool(f[POOL_KEYS.externals], 1)
        end
    elseif extCfg and extCfg.enabled ~= false then
        for k in pairs(_externalsIDs) do _externalsIDs[k] = nil end
        local afr = AF()
        local extFilter = afr and afr.EXTERNALS_TOKEN or "HELPFUL|BIG_DEFENSIVE"
        local n = RenderGroup(f, unit, "externals", extCfg, extFilter, false, parent, nil, scale, frameScale)
        if n > 0 then anyShown = true end
        f._msufGFExtHidden = nil
    elseif not f._msufGFExtHidden then
        f._msufGFExtHidden = true
        HidePool(f[POOL_KEYS.externals], 1)
    end

    -- 2) Debuffs + merged dispel
    local debCfg = auras.debuff
    local mergedDispel
    local mergedDispelColor
    -- Clear the tracked dispel aura up front so each refresh resolves the current live aura.
    -- This mirrors EQoL's approach of treating the dispel aura id as frame-local volatile state.
    f._msufGFDispelAuraID = nil
    f._msufGFDispelColorObj = nil
    f._msufGFDispelColorRev = nil
    local debOn = debCfg and debCfg.enabled ~= false and not nativeDebuffs
    local dispelNeeded = _playerCanDispel and conf.dispelEnabled ~= false and not nativeDispels

    if nativeDebuffs then
        if not f._msufGFDebHidden then
            f._msufGFDebHidden = true
            HidePool(f[POOL_KEYS.debuff], 1)
        end
    elseif debOn then
        local afr = AF()
        local debFilter = afr and afr.ResolveDebuffFilter(debCfg.filterToken) or "HARMFUL"
        local n, md, mdColor = RenderGroup(f, unit, "debuff", debCfg, debFilter, true, parent, nil, scale, frameScale)
        if not nativeDispels then
            mergedDispel = md
            mergedDispelColor = mdColor
        end
        if n > 0 then anyShown = true end
        f._msufGFDebHidden = nil
    else
        if not f._msufGFDebHidden then
            f._msufGFDebHidden = true
            HidePool(f[POOL_KEYS.debuff], 1)
        end
        -- Lightweight dispel scan ONLY when class can dispel AND dispel enabled
        -- Uses C-side RAID_PLAYER_DISPELLABLE filter (secret-safe)
        if dispelNeeded then
            if _getByIndex then
                local aura = _getByIndex(unit, 1, _DISPEL_FILTER)
                if aura and aura.auraInstanceID then
                    mergedDispel = _GetReadableDispelName(aura.dispelName) or "DISPELLABLE"
                    f._msufGFDispelAuraID = aura.auraInstanceID
                    if _getDispelColor and _dispelColorCurve then
                        mergedDispelColor = _getDispelColor(unit, aura.auraInstanceID, _dispelColorCurve)
                    end
                end
            elseif _isFilteredOut then
                local slots, sc = QuerySlots(unit, _DISPEL_FILTER, 4)
                if sc >= 2 then
                    local aura = _getBySlot(unit, slots[2])
                    if aura and aura.auraInstanceID then
                        mergedDispel = _GetReadableDispelName(aura.dispelName) or "DISPELLABLE"
                        f._msufGFDispelAuraID = aura.auraInstanceID
                        if _getDispelColor and _dispelColorCurve then
                            mergedDispelColor = _getDispelColor(unit, aura.auraInstanceID, _dispelColorCurve)
                        end
                    end
                end
            else
                local slots, sc = QuerySlots(unit, "HARMFUL", 12)
                for i = 2, sc do
                    local aura = _getBySlot(unit, slots[i])
                    if aura then
                        local dn = _GetReadableDispelName(aura.dispelName)
                        if dn then
                            mergedDispel = dn
                            f._msufGFDispelAuraID = aura.auraInstanceID
                            if _getDispelColor and _dispelColorCurve then
                                mergedDispelColor = _getDispelColor(unit, aura.auraInstanceID, _dispelColorCurve)
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    f._msufGFMergedDispel = mergedDispel
    f._msufGFDispelColorObj = mergedDispelColor
    f._msufGFDispelColorRev = mergedDispelColor and (_G.MSUF_ColorStyleRevision or 0) or nil

    -- 3) Buffs
    local buffCfg = auras.buff
    if nativeBuffs then
        if not f._msufGFBufHidden then
            f._msufGFBufHidden = true
            HidePool(f[POOL_KEYS.buff], 1)
        end
    elseif buffCfg and buffCfg.enabled ~= false then
        local afr = AF()
        local buffFilter = afr and afr.ResolveBuffFilter(buffCfg.filterToken) or "HELPFUL|RAID"
        local n = RenderGroup(f, unit, "buff", buffCfg, buffFilter, false, parent, f._msufSIDedupIDs, scale, frameScale)
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
-- EQoL-style cache-backed orchestrator.
-- Full updates rebuild the cache from C_UnitAuras.GetAuraSlots; deltas mutate
-- the frame-local cache by auraInstanceID and render only touched groups.
------------------------------------------------------------------------
function GF.UpdateFrameAuras(f, unit, updateInfo)
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
        GF.ClearBlizzardAuraContainer(f)
        if GF.ClearPrivateAuras then GF.ClearPrivateAuras(f) end
        ClearFrameAuraCache(f)
        f._msufGFDispelAuraID = nil
        f._msufGFDispelColorObj = nil
        f._msufGFDispelColorRev = nil
        RefreshDisplayedAuraIDMap(f)
        return
    end
    f._msufGFAurasHidden = nil

    if not UnitExists(unit) then
        HidePool(f[POOL_KEYS.buff], 1)
        HidePool(f[POOL_KEYS.debuff], 1)
        HidePool(f[POOL_KEYS.externals], 1)
        GF.ClearBlizzardAuraContainer(f)
        if GF.ClearPrivateAuras then GF.ClearPrivateAuras(f) end
        ClearFrameAuraCache(f)
        f._msufGFDispelAuraID = nil
        f._msufGFDispelColorObj = nil
        f._msufGFDispelColorRev = nil
        RefreshDisplayedAuraIDMap(f)
        return
    end

    if not _apisBound then BindAPIs() end
    if not _getSlots or not _getBySlot then
        return UpdateFrameAuras_SlotScanLegacy(f, unit, updateInfo)
    end

    local parent = f.statusIconLayer or f.barGroup or f
    local scale = GetDynamicScale(conf)
    local frameScale = GetFrameScale(kind, conf)
    local c = f._c
    local nativeBuffs, nativeDebuffs, nativeDispels, nativeExt, nativePrivate
    if c then
        nativeBuffs = c.nativeBlizzardBuffs
        nativeDebuffs = c.nativeBlizzardDebuffs
        nativeDispels = c.nativeBlizzardDispels
        nativeExt = c.nativeBlizzardExt
        nativePrivate = c.nativeBlizzardPrivate
    else
        local nativeEnabled = GF.IsBlizzardAuraTypeEnabled
        nativeBuffs = nativeEnabled and nativeEnabled(conf, "buffs")
        nativeDebuffs = nativeEnabled and nativeEnabled(conf, "debuffs")
        nativeDispels = nativeEnabled and nativeEnabled(conf, "dispels")
        nativeExt = nativeEnabled and nativeEnabled(conf, "externals")
        nativePrivate = nativeEnabled and nativeEnabled(conf, "privateAuras")
    end
    local buffCfg = auras.buff or _EMPTY_AURA_CFG
    local debCfg = auras.debuff or _EMPTY_AURA_CFG
    local extCfg = auras.externals or _EMPTY_AURA_CFG
    local nativeRendered = nativeBuffs
        or nativeDebuffs
        or nativeDispels
        or nativeExt
        or nativePrivate

    if not (updateInfo and not updateInfo.isFullUpdate and nativeRendered and NativeBlizzardAuraContainerReady(f, unit)) then
        GF.UpdateBlizzardAuraContainer(f, unit, conf, scale, frameScale, updateInfo)
    end

    if c and c.nativeBlizzardAuraOnly then
        if not f._msufGFExtHidden then HidePool(f[POOL_KEYS.externals], 1); f._msufGFExtHidden = true end
        if not f._msufGFDebHidden then HidePool(f[POOL_KEYS.debuff], 1); f._msufGFDebHidden = true end
        if not f._msufGFBufHidden then HidePool(f[POOL_KEYS.buff], 1); f._msufGFBufHidden = true end
        f._msufGFMergedDispel = nil
        f._msufGFDispelAuraID = nil
        f._msufGFDispelColorObj = nil
        f._msufGFDispelColorRev = nil
        ClearFrameAuraCache(f)
        RefreshDisplayedAuraIDMap(f)
        return
    end

    local extOn = extCfg and extCfg.enabled ~= false and not nativeExt
    local debOn = debCfg and debCfg.enabled ~= false and not nativeDebuffs
    local buffOn = buffCfg and buffCfg.enabled ~= false and not nativeBuffs
    local dispelNeeded = _playerCanDispel and conf.dispelEnabled ~= false and not nativeDispels

    -- PERF (4.22 Beta hotfix): cache settings-stable filter/max resolutions
    -- on the frame settings cache `c`. Was: 3× ResolveDebuff/Buff function
    -- calls + EXTERNALS_TOKEN read + 3× tonumber per UpdateFrameAuras call,
    -- reading from auras.X.filterToken / auras.X.max which only change on
    -- options updates. Invalidated together with c.auraCacheSig when
    -- BuildFrameCache rebuilds settings cache (c.auraResolved = nil).
    local resolved = c and c.auraResolved
    local extFilter, debFilter, buffFilter, extMax, debMax, buffMax
    if resolved then
        extFilter = resolved.extFilter
        debFilter = resolved.debFilter
        buffFilter = resolved.buffFilter
        extMax = resolved.extMax
        debMax = resolved.debMax
        buffMax = resolved.buffMax
    else
        local afr = AF()
        extFilter = afr and afr.EXTERNALS_TOKEN or "HELPFUL|BIG_DEFENSIVE"
        debFilter = afr and afr.ResolveDebuffFilter(debCfg.filterToken) or "HARMFUL"
        buffFilter = afr and afr.ResolveBuffFilter(buffCfg.filterToken) or "HELPFUL|RAID"
        extMax = tonumber(extCfg.max) or 6
        debMax = tonumber(debCfg.max) or 6
        buffMax = tonumber(buffCfg.max) or 6
        if c then
            c.auraResolved = {
                extFilter = extFilter, debFilter = debFilter, buffFilter = buffFilter,
                extMax = extMax, debMax = debMax, buffMax = buffMax,
            }
        end
    end

    local sig = c and c.auraCacheSig
    if not sig then
        sig = BuildAuraCacheSig(buffFilter, debFilter, extFilter, buffMax, debMax, extMax, buffOn, debOn, extOn, dispelNeeded)
        if c then c.auraCacheSig = sig end
    end

    local st = f._msufGFAuraCache
    local useDelta = updateInfo and not updateInfo.isFullUpdate
        and st and st.ready and st.unit == unit and st.sig == sig

    local touchBuff, touchDebuff, touchExt, touchDispel
    if useDelta then
        st, touchBuff, touchDebuff, touchExt, touchDispel = UpdateFrameAuraCacheDelta(
            f, unit, updateInfo,
            buffFilter, debFilter, extFilter,
            buffMax, debMax, extMax,
            buffOn, debOn, extOn, dispelNeeded
        )
    else
        st = FullScanFrameAuraCache(
            f, unit, sig,
            buffFilter, debFilter, extFilter,
            buffMax, debMax, extMax,
            buffOn, debOn, extOn, dispelNeeded
        )
        touchBuff = buffOn
        touchDebuff = debOn
        touchExt = extOn
        touchDispel = dispelNeeded
    end

    if nativeExt then
        if not f._msufGFExtHidden then
            f._msufGFExtHidden = true
            HidePool(f[POOL_KEYS.externals], 1)
        end
    elseif extOn then
        if touchExt then
            for k in pairs(_externalsIDs) do _externalsIDs[k] = nil end
            RenderGroup(f, unit, "externals", extCfg, extFilter, false, parent, nil, scale, frameScale, st and st.externals)
        else
            FillDisplayedExternalIDs(f, _externalsIDs)
        end
        f._msufGFExtHidden = nil
    elseif not f._msufGFExtHidden then
        f._msufGFExtHidden = true
        HidePool(f[POOL_KEYS.externals], 1)
        for k in pairs(_externalsIDs) do _externalsIDs[k] = nil end
    else
        for k in pairs(_externalsIDs) do _externalsIDs[k] = nil end
    end

    if nativeDebuffs then
        if not f._msufGFDebHidden then
            f._msufGFDebHidden = true
            HidePool(f[POOL_KEYS.debuff], 1)
        end
    elseif debOn then
        if touchDebuff or touchDispel then
            f._msufGFDispelAuraID = nil
            f._msufGFDispelColorObj = nil
            f._msufGFDispelColorRev = nil
            local _, md, mdColor = RenderGroup(f, unit, "debuff", debCfg, debFilter, true, parent, nil, scale, frameScale, st and st.debuff)
            if not nativeDispels then
                if touchDispel and dispelNeeded and not md then
                    if _getByIndex then
                        local aura = _getByIndex(unit, 1, _DISPEL_FILTER)
                        if aura and aura.auraInstanceID then
                            md = _GetReadableDispelName(aura.dispelName) or "DISPELLABLE"
                            f._msufGFDispelAuraID = aura.auraInstanceID
                            if _getDispelColor and _dispelColorCurve then
                                mdColor = _getDispelColor(unit, aura.auraInstanceID, _dispelColorCurve)
                            end
                        end
                    elseif _isFilteredOut then
                        local slots, sc = QuerySlots(unit, _DISPEL_FILTER, 4)
                        if sc >= 2 then
                            local aura = _getBySlot(unit, slots[2])
                            if aura and aura.auraInstanceID then
                                md = _GetReadableDispelName(aura.dispelName) or "DISPELLABLE"
                                f._msufGFDispelAuraID = aura.auraInstanceID
                                if _getDispelColor and _dispelColorCurve then
                                    mdColor = _getDispelColor(unit, aura.auraInstanceID, _dispelColorCurve)
                                end
                            end
                        end
                    end
                end
                f._msufGFMergedDispel = md
                f._msufGFDispelColorObj = mdColor
                f._msufGFDispelColorRev = mdColor and (_G.MSUF_ColorStyleRevision or 0) or nil
            end
        end
        f._msufGFDebHidden = nil
    else
        if not f._msufGFDebHidden then
            f._msufGFDebHidden = true
            HidePool(f[POOL_KEYS.debuff], 1)
        end
        if dispelNeeded and (not useDelta or touchDispel) then
            local mergedDispel, mergedDispelColor
            f._msufGFDispelAuraID = nil
            f._msufGFDispelColorObj = nil
            f._msufGFDispelColorRev = nil
            if _getByIndex then
                local aura = _getByIndex(unit, 1, _DISPEL_FILTER)
                if aura and aura.auraInstanceID then
                    mergedDispel = _GetReadableDispelName(aura.dispelName) or "DISPELLABLE"
                    f._msufGFDispelAuraID = aura.auraInstanceID
                    if _getDispelColor and _dispelColorCurve then
                        mergedDispelColor = _getDispelColor(unit, aura.auraInstanceID, _dispelColorCurve)
                    end
                end
            elseif _isFilteredOut then
                local slots, sc = QuerySlots(unit, _DISPEL_FILTER, 4)
                if sc >= 2 then
                    local aura = _getBySlot(unit, slots[2])
                    if aura and aura.auraInstanceID then
                        mergedDispel = _GetReadableDispelName(aura.dispelName) or "DISPELLABLE"
                        f._msufGFDispelAuraID = aura.auraInstanceID
                        if _getDispelColor and _dispelColorCurve then
                            mergedDispelColor = _getDispelColor(unit, aura.auraInstanceID, _dispelColorCurve)
                        end
                    end
                end
            end
            f._msufGFMergedDispel = mergedDispel
            f._msufGFDispelColorObj = mergedDispelColor
            f._msufGFDispelColorRev = mergedDispelColor and (_G.MSUF_ColorStyleRevision or 0) or nil
        elseif not dispelNeeded then
            f._msufGFMergedDispel = nil
            f._msufGFDispelAuraID = nil
            f._msufGFDispelColorObj = nil
            f._msufGFDispelColorRev = nil
        end
    end

    if nativeBuffs then
        if not f._msufGFBufHidden then
            f._msufGFBufHidden = true
            HidePool(f[POOL_KEYS.buff], 1)
        end
    elseif buffOn then
        if touchBuff or touchExt then
            if not touchExt then FillDisplayedExternalIDs(f, _externalsIDs) end
            RenderGroup(f, unit, "buff", buffCfg, buffFilter, false, parent, f._msufSIDedupIDs, scale, frameScale, st and st.buff)
        end
        f._msufGFBufHidden = nil
    elseif not f._msufGFBufHidden then
        f._msufGFBufHidden = true
        HidePool(f[POOL_KEYS.buff], 1)
    end

    RefreshDisplayedAuraIDMap(f)
end

------------------------------------------------------------------------
-- Coalesced options refresh for GF aura groups only.
-- Used by aura sliders to avoid a full unit-frame UpdateAll on every drag
-- tick while still applying icon size/layout changes live next frame.
------------------------------------------------------------------------
local _auraOptionsRefreshQueued = false

local function _DoAuraOptionsRefresh()
    _auraOptionsRefreshQueued = false

    if GF.ForEachFrame then
        GF.ForEachFrame(function(f)
            if f and GF.BuildFrameCache then GF.BuildFrameCache(f) end
            if f and f.unit and GF.RegisterUnitEvents then GF.RegisterUnitEvents(f, f.unit) end
            if f and f.unit and UnitExists(f.unit) then
                GF.UpdateFrameAuras(f, f.unit)
                local c = f._c
                if c and c.paEn and GF.ApplyPrivateAuras then
                    GF.ApplyPrivateAuras(f, f.unit)
                elseif GF.ClearPrivateAuras then
                    GF.ClearPrivateAuras(f)
                end
            elseif f then
                GF.HideFrameAuras(f)
            end
        end)
    elseif GF.frames then
        for f in pairs(GF.frames) do
            if f and GF.BuildFrameCache then GF.BuildFrameCache(f) end
            if f and f.unit and GF.RegisterUnitEvents then GF.RegisterUnitEvents(f, f.unit) end
            if f and f.unit and UnitExists(f.unit) then
                GF.UpdateFrameAuras(f, f.unit)
                local c = f._c
                if c and c.paEn and GF.ApplyPrivateAuras then
                    GF.ApplyPrivateAuras(f, f.unit)
                elseif GF.ClearPrivateAuras then
                    GF.ClearPrivateAuras(f)
                end
            elseif f then
                GF.HideFrameAuras(f)
            end
        end
    end

    if GF._previewFrames then
        for kind, list in pairs(GF._previewFrames) do
            for i = 1, #list do
                local f = list[i]
                if f and f._msufGFPreviewActive and GF.PreviewFrameAuras then
                    GF.PreviewFrameAuras(f, kind, i)
                end
                if f and f._msufGFPreviewActive and GF.PreviewPrivateAuras then
                    GF.PreviewPrivateAuras(f, kind)
                end
            end
        end
    end

    if GF.RefreshPreviewBox then GF.RefreshPreviewBox() end
    if GF.RefreshPreviewHandles then GF.RefreshPreviewHandles() end
end

function GF.RequestAuraRefresh()
    if _auraOptionsRefreshQueued then return end
    _auraOptionsRefreshQueued = true
    local sched = _G.MSUF_ScheduleOnce
    if type(sched) == "function" then
        sched("GF_AURA_OPTIONS_REFRESH", _DoAuraOptionsRefresh)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, _DoAuraOptionsRefresh)
    else
        _DoAuraOptionsRefresh()
    end
end

------------------------------------------------------------------------
-- Direct icon refresh (skip full UpdateFrameAuras for update-only events)
-- Called by dispatchAura when only cooldown/stacks changed on displayed icons.
-- Cost: ~16µs (2 C-API calls) vs 130µs (31 C-API calls) for full pipeline.
------------------------------------------------------------------------
function GF.RefreshAuraIcon(icon, unit, aid)
    if not icon or not unit or not aid then return false end
    if not _apisBound then BindAPIs() end
    if _getByAuraInstanceID and not _getByAuraInstanceID(unit, aid) then
        return false
    end

    local owner = icon._msufGFOwner
    local gcfg
    local frameScale = 1
    if owner then
        -- Read pre-cached reverse flag from BuildFrameCache (Fix B).
        -- Avoids GF.GetConf in this hot path (called per updated aura per UNIT_AURA event).
        local oc = owner._c
        local reverse = (oc and oc.cdReverse) or false
        gcfg = icon._msufAuraGroupCfg
        frameScale = icon._msufAuraFrameScale or frameScale
        if not gcfg then
            local groupKey = icon._msufAuraGroupKey
            local kind = owner._msufGFKind or "party"
            local conf = GF.GetConf and GF.GetConf(kind)
            frameScale = GetFrameScale(kind, conf)
            if groupKey then
                gcfg = GetGroupCfg(kind, groupKey)
            end
        end
        ApplyCooldownVisualStyle(icon.cooldown, reverse, WantsCooldownSwipe(gcfg))
    end
    local showCdText = WantsCooldownText(gcfg)
    local showCdSwipe = WantsCooldownSwipe(gcfg)
    ApplyCooldown(icon, unit, aid, showCdText or showCdSwipe, showCdText)
    if gcfg then
        local gFont, gFlags = ResolveGlobalFont()
        local baseR, baseG, baseB, baseA = ResolveCooldownBaseColor()
        ApplyCooldownFont(icon, gcfg, gFont, gcfg.cooldownOutline or gFlags or "OUTLINE", baseR, baseG, baseB, baseA, frameScale)
        ApplyStackLayout(icon, gcfg, gFont, gcfg.stackOutline or gFlags or "OUTLINE", frameScale)
        ApplyStacks(icon, unit, aid, nil, gcfg.showStacks ~= false, gcfg)
    else
        local gFont, gFlags = ResolveGlobalFont()
        local baseR, baseG, baseB, baseA = ResolveCooldownBaseColor()
        ApplyCooldownFont(icon, nil, gFont, gFlags or "OUTLINE", baseR, baseG, baseB, baseA, frameScale)
        ApplyStacks(icon, unit, aid, nil, true, nil)
    end
    return true
end

------------------------------------------------------------------------
-- Hide all aura groups (for unit change / hide)
------------------------------------------------------------------------
function GF.HideFrameAuras(f)
    GF.ClearBlizzardAuraContainer(f)
    if GF.ClearPrivateAuras then GF.ClearPrivateAuras(f) end
    HidePool(f[POOL_KEYS.buff], 1)
    HidePool(f[POOL_KEYS.debuff], 1)
    HidePool(f[POOL_KEYS.externals], 1)
    ClearFrameAuraCache(f)
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
            wantLvl = f.health:GetFrameLevel() - 1
        else
            wantLvl = (GF.GetFrameLayerLevel and GF.GetFrameLayerLevel(f, gcfg.layer, 5))
                or (normalParent:GetFrameLevel() + (gcfg.layer or 5))
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
        -- Apply dynamic scale based on the same visible/live count the user is editing.
        local dynScale = GetPreviewDynamicScale(conf, kind)
        local frameScale = GetFrameScale(kind, conf)
        local nativeBuffs = GF.IsBlizzardAuraTypeEnabled and GF.IsBlizzardAuraTypeEnabled(conf, "buffs")
        local nativeDebuffs = GF.IsBlizzardAuraTypeEnabled and GF.IsBlizzardAuraTypeEnabled(conf, "debuffs")
        local nativeExt = GF.IsBlizzardAuraTypeEnabled and GF.IsBlizzardAuraTypeEnabled(conf, "externals")

        -- Buffs
        local buffCfg = auras.buff
        if buffCfg and buffCfg.enabled ~= false and not nativeBuffs then
            local rawSize = buffCfg.size or 20
            local size = ScaleFrameValue(rawSize, dynScale * frameScale, 8)
            local anchor = buffCfg.anchor or "BOTTOMLEFT"
            local growth = buffCfg.growth or "RIGHTDOWN"
            local spacing = ScaleFrameValue(buffCfg.spacing or 1, frameScale, 0)
            local perRow = buffCfg.perRow or 4
            local maxShow = math_min(#MOCK_BUFFS, buffCfg.max or 6)
            local gv = GetGrowthVectors(growth)
            local effAnchor = gv.centered and "CENTER" or anchor
            local container = EnsureContainer(f, "buff")
            local anchorTarget = ApplyContainerMode(container, f, buffCfg, parent)
            container:ClearAllPoints()
            container:SetPoint(effAnchor, anchorTarget, effAnchor,
                ScaleFrameValue(buffCfg.x or 0, frameScale),
                ScaleFrameValue(buffCfg.y or 0, frameScale))
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
                    PositionIcon(ic, anchor, container, i, perRow, size, spacing, gv, maxShow)
                    ic:Show()
                end
            end
            HidePool(pool, maxShow + 1)
        else
            HidePool(f._msufAuraPool_buff, 1)
        end

        -- Debuffs
        local debCfg = auras.debuff
        if debCfg and debCfg.enabled ~= false and not nativeDebuffs then
            local rawSize = debCfg.size or 20
            local size = ScaleFrameValue(rawSize, dynScale * frameScale, 8)
            local anchor = debCfg.anchor or "TOPLEFT"
            local growth = debCfg.growth or "RIGHTDOWN"
            local spacing = ScaleFrameValue(debCfg.spacing or 1, frameScale, 0)
            local perRow = debCfg.perRow or 3
            local maxShow = math_min(#MOCK_DEBUFFS, debCfg.max or 6)
            local gv = GetGrowthVectors(growth)
            local effAnchor = gv.centered and "CENTER" or anchor
            local container = EnsureContainer(f, "debuff")
            local anchorTarget = ApplyContainerMode(container, f, debCfg, parent)
            container:ClearAllPoints()
            container:SetPoint(effAnchor, anchorTarget, effAnchor,
                ScaleFrameValue(debCfg.x or 0, frameScale),
                ScaleFrameValue(debCfg.y or 0, frameScale))
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
                    PositionIcon(ic, anchor, container, i, perRow, size, spacing, gv, maxShow)
                    ic:Show()
                end
            end
            HidePool(pool, maxShow + 1)
        else
            HidePool(f._msufAuraPool_debuff, 1)
        end

        -- Externals
        local extCfg = auras.externals
        if extCfg and extCfg.enabled ~= false and index == 1 and not nativeExt then
            local rawSize = extCfg.size or 28
            local size = ScaleFrameValue(rawSize, dynScale * frameScale, 8)
            local anchor = extCfg.anchor or "CENTER"
            local growth = extCfg.growth or "RIGHTDOWN"
            local spacing = ScaleFrameValue(extCfg.spacing or 1, frameScale, 0)
            local perRow = extCfg.perRow or 3
            local maxShow = math_min(#MOCK_EXTERNALS, extCfg.max or 2)
            local gv = GetGrowthVectors(growth)
            local effAnchor = gv.centered and "CENTER" or anchor
            local container = EnsureContainer(f, "externals")
            local anchorTarget = ApplyContainerMode(container, f, extCfg, parent)
            container:ClearAllPoints()
            container:SetPoint(effAnchor, anchorTarget, effAnchor,
                ScaleFrameValue(extCfg.x or 0, frameScale),
                ScaleFrameValue(extCfg.y or 0, frameScale))
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
                    PositionIcon(ic, anchor, container, i, perRow, size, spacing, gv, maxShow)
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
GF.GetAuraDynamicScale = GetDynamicScale
_G.MSUF_GF_UpdateFrameAuras = GF.UpdateFrameAuras
