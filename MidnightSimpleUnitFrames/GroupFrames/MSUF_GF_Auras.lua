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
local _getSlots, _getBySlot, _getByIndex, _getDuration, _getStackCount, _apisBound

local function BindAPIs()
    if _apisBound then return end
    _apisBound = true
    if C_UnitAuras then
        _getSlots      = C_UnitAuras.GetAuraSlots
        _getBySlot     = C_UnitAuras.GetAuraDataBySlot
        _getByIndex    = C_UnitAuras.GetAuraDataByIndex
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
local _ICON_RECYCLE_MAX = 32

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

    -- Masque owns the Icon region geometry once a skin is active. For the
    -- native skin we keep every child hard-anchored to the aura frame so a
    -- size slider cannot resize only the backdrop/cooldown "box".
    if icon.texture and not IconUsesMasque(icon) then
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
    if not icon or _iconRecyclerN >= _ICON_RECYCLE_MAX then return false end
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
-- and feed the global recycler. Stops at the recycler's hard cap (32)
-- — surplus icons remain on the retired frame and get GC'd along with
-- the frame. This single function is the only path that consumes the
-- recycler in the hot rebuild cycle (zone change → frames retired →
-- next SetupHeader pulls icons from the pool instead of CreateFrame'ing).
------------------------------------------------------------------------
function GF.RecycleFramePools(f)
    if not f then return end
    for _, poolKey in pairs(POOL_KEYS) do
        local pool = f[poolKey]
        if type(pool) == "table" then
            for i = 1, #pool do
                local ic = pool[i]
                if ic then
                    if not RecycleAuraIcon(ic) then break end -- recycler full → stop
                    pool[i] = nil
                end
            end
            -- Reset pool meta-cache so EnsurePool re-populates correctly on next setup
            pool._msufPoolOK = nil
            pool._msufPoolN  = nil
            pool._msufPoolSz = nil
            pool._msufPoolP  = nil
        end
    end
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
        end
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
local function ApplyCooldown(ic, unit, auraInstanceID, showCd)
    local cd = ic.cooldown
    if not cd then return end
    if not showCd then
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
            if _GF_TouchCooldownTextIcon then _GF_TouchCooldownTextIcon(ic) end
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

------------------------------------------------------------------------
-- Native Blizzard cooldown text coloring for GF aura timers.
-- Uses the same global Auras cooldown color settings as Auras2, but is
-- fully local to Group Frames: Blizzard still owns the timer text, MSUF
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

    local safeSeconds = (g and type(g.aurasCooldownTextSafeSeconds) == "number") and g.aurasCooldownTextSafeSeconds or 60
    local warnSeconds = (g and type(g.aurasCooldownTextWarningSeconds) == "number") and g.aurasCooldownTextWarningSeconds or 15
    local urgSeconds  = (g and type(g.aurasCooldownTextUrgentSeconds) == "number") and g.aurasCooldownTextUrgentSeconds or 5
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
    _gfCdTextBucketsEnabled = not (g and g.aurasCooldownTextUseBuckets == false)
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
        fastUntil = 0,
    }
    _gfCdTextMgr = mgr

    local function CancelTimer()
        if mgr.timer and mgr.timer.Cancel then mgr.timer:Cancel() end
        mgr.timer = nil
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
        EnsureGFCooldownTextColorSettings()
        local now = GetTime()
        local secretsActive = IsGFSecretMode(now)
        local wantFast = now < (mgr.fastUntil or 0)
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
                    if not (skipUntil and now < skipUntil) then
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
                        elseif bucket == 3 then
                            icon._msufGF_cdSkipUntil = now + 2.0
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
        if C_Timer and type(C_Timer.NewTimer) == "function" then
            mgr.timer = C_Timer.NewTimer(delay, tickCallback)
        elseif C_Timer and type(C_Timer.After) == "function" then
            mgr.timerGen = (mgr.timerGen or 0) + 1
            local gen = mgr.timerGen
            C_Timer.After(delay, function()
                if mgr.timerGen ~= gen then return end
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
        if mgr and mgr.count > 0 and mgr._Schedule then mgr._Schedule(0) end
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

-- ApplyCooldownVisualStyle(cd, reverse)
-- `reverse` is the cooldownSwipeDarkenOnLoss bool. Caller pre-resolves it
-- once per render (RenderGroup) or per-icon-event (RefreshAuraIcon) from
-- f._c.cdReverse — eliminates GF.GetConf from this hot path.
-- Diff-gates remain per-icon (correctness — required for live-apply).
local function ApplyCooldownVisualStyle(cd, reverse)
    if not cd then return end

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
end

------------------------------------------------------------------------
-- Apply cooldown text font (diff-gated, global font, lazy FontString discovery)
------------------------------------------------------------------------
-- ApplyCooldownFont(ic, gcfg, gFont, wantFlags, baseR, baseG, baseB, baseA)
-- Caller (RenderGroup) pre-resolves the four style values once per render
-- group — eliminates per-icon ResolveGlobalFont + ResolveCooldownBaseColor
-- calls. Per-icon diff-gates remain for live-apply correctness.
local function ApplyCooldownFont(ic, gcfg, gFont, wantFlags, baseR, baseG, baseB, baseA, isRetry)
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
                        ApplyCooldownFont(retryIcon, gcfg, gFont, wantFlags, baseR, baseG, baseB, baseA, true)
                    end
                end)
            end
        end
        return
    end

    cd._msufGFCdFontRetryQueued = nil
    local fsChanged = cd._msufGFCdStyledFS ~= fs
    if fsChanged then cd._msufGFCdStyledFS = fs end

    local size = (gcfg and gcfg.cooldownSize) or 8

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
    local ox = (gcfg and gcfg.cooldownOffsetX) or 0
    local oy = (gcfg and gcfg.cooldownOffsetY) or 0
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
local function ApplyStackLayout(ic, gcfg, gFont, wantFlags)
    local fs = ic and ic.count
    if not fs then return end

    local size = gcfg.stackSize or 10
    local anchor = gcfg.stackAnchor or "BOTTOMRIGHT"
    local ox = gcfg.stackOffsetX or -1
    local oy = gcfg.stackOffsetY or 1

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
        -- health - 1: above replacement-bg (on barGroup), below health fill
        wantLvl = f.health:GetFrameLevel() - 1
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
    local showCd = WantsCooldownText(gcfg)
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

    for i = 2, slotCount do
        if shown >= maxIcons and (not isHarmful or topDispel) then break end
        local aura = _getBySlot(unit, slots[i])
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
                        ApplyCooldownVisualStyle(ic.cooldown, _styleReverse)
                        local prevAid = ic._msufAuraID
                        if prevAid == aid then
                            -- ══ SAME AURA ══ cheap refresh (cooldown sweep + stacks + layout)
                            ApplyCooldown(ic, unit, aid, showCd)
                            local cd = ic.cooldown
                            if cd then
                                local wantHide = not showCd
                                if ic._msufCdHidden ~= wantHide then
                                    ic._msufCdHidden = wantHide
                                    cd:SetHideCountdownNumbers(wantHide)
                                end
                            end
                            ApplyCooldownFont(ic, gcfg, _styleGFont, _styleCdFlags, _styleBaseR, _styleBaseG, _styleBaseB, _styleBaseA)
                            ApplyStackLayout(ic, gcfg, _styleGFont, _styleStkFlags)
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

                            ApplyCooldown(ic, unit, aid, showCd)
                            local cd = ic.cooldown
                            if cd then
                                local wantHide = not showCd
                                if ic._msufCdHidden ~= wantHide then
                                    ic._msufCdHidden = wantHide
                                    cd:SetHideCountdownNumbers(wantHide)
                                end
                            end
                            ApplyCooldownFont(ic, gcfg, _styleGFont, _styleCdFlags, _styleBaseR, _styleBaseG, _styleBaseB, _styleBaseA)
                            ApplyStackLayout(ic, gcfg, _styleGFont, _styleStkFlags)
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
    for j = shown + 1, #pool do
        local ic = pool[j]
        if ic then
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
        end
    end
    return shown, topDispel, topDispelColor
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
        f._msufGFDispelAuraID = nil
        f._msufGFDispelColorObj = nil
        f._msufGFDispelColorRev = nil
        return
    end
    if not _apisBound then BindAPIs() end
    if not _getSlots or not _getBySlot then return end

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
    local mergedDispelColor
    -- Clear the tracked dispel aura up front so each refresh resolves the current live aura.
    -- This mirrors EQoL's approach of treating the dispel aura id as frame-local volatile state.
    f._msufGFDispelAuraID = nil
    f._msufGFDispelColorObj = nil
    f._msufGFDispelColorRev = nil
    local debOn = debCfg and debCfg.enabled ~= false
    local dispelNeeded = _playerCanDispel and conf.dispelEnabled ~= false

    if debOn then
        local afr = AF()
        local debFilter = afr and afr.ResolveDebuffFilter(debCfg.filterToken) or "HARMFUL"
        local n, md, mdColor = RenderGroup(f, unit, "debuff", debCfg, debFilter, true, parent, nil, scale)
        mergedDispel = md
        mergedDispelColor = mdColor
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
            if f and f.unit and UnitExists(f.unit) then
                GF.UpdateFrameAuras(f, f.unit)
            elseif f then
                GF.HideFrameAuras(f)
            end
        end)
    elseif GF.frames then
        for f in pairs(GF.frames) do
            if f and GF.BuildFrameCache then GF.BuildFrameCache(f) end
            if f and f.unit and UnitExists(f.unit) then
                GF.UpdateFrameAuras(f, f.unit)
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
    if not icon or not unit or not aid then return end
    local owner = icon._msufGFOwner
    local gcfg
    if owner then
        -- Read pre-cached reverse flag from BuildFrameCache (Fix B).
        -- Avoids GF.GetConf in this hot path (called per updated aura per UNIT_AURA event).
        local oc = owner._c
        local reverse = (oc and oc.cdReverse) or false
        ApplyCooldownVisualStyle(icon.cooldown, reverse)
        local groupKey = icon._msufAuraGroupKey
        if groupKey then
            gcfg = GetGroupCfg(owner._msufGFKind or "party", groupKey)
        end
    end
    local showCd = WantsCooldownText(gcfg)
    ApplyCooldown(icon, unit, aid, showCd)
    if gcfg then
        local gFont, gFlags = ResolveGlobalFont()
        local baseR, baseG, baseB, baseA = ResolveCooldownBaseColor()
        ApplyCooldownFont(icon, gcfg, gFont, gcfg.cooldownOutline or gFlags or "OUTLINE", baseR, baseG, baseB, baseA)
        ApplyStackLayout(icon, gcfg, gFont, gcfg.stackOutline or gFlags or "OUTLINE")
        ApplyStacks(icon, unit, aid, nil, gcfg.showStacks ~= false, gcfg)
    else
        local gFont, gFlags = ResolveGlobalFont()
        local baseR, baseG, baseB, baseA = ResolveCooldownBaseColor()
        ApplyCooldownFont(icon, nil, gFont, gFlags or "OUTLINE", baseR, baseG, baseB, baseA)
        ApplyStacks(icon, unit, aid, nil, true, nil)
    end
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
            wantLvl = f.health:GetFrameLevel() - 1
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
