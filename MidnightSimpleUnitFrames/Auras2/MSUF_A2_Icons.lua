-- ============================================================================
-- MSUF_A2_Icons.lua — Auras 3.0 Icon Factory + Visual Commit + Layout
-- Replaces the core of MSUF_A2_Apply.lua
--
-- Responsibilities:
--   1. Icon pool (AcquireIcon / HideUnused)
--   2. Visual commit (CommitIcon — texture, cooldown, stacks, border)
--   3. Grid layout (LayoutIcons)
--   4. Refresh helpers (RefreshAssignedIcons)
--
-- Secret-safe: uses Collect.GetDurationObject() for timers,
-- Collect.GetStackCount() for stacks, never reads secret fields.
-- ============================================================================

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
-- =========================================================================
-- PERF LOCALS (Auras2 runtime)
--  - Reduce global table lookups in high-frequency aura pipelines.
--  - Secret-safe: localizing function references only (no value comparisons).
-- =========================================================================
local type, tostring, tonumber, select = type, tostring, tonumber, select
local pairs, ipairs, next = pairs, ipairs, next
local math_min, math_max, math_floor = math.min, math.max, math.floor
local string_format, string_match, string_sub = string.format, string.match, string.sub
local CreateFrame, GetTime = CreateFrame, GetTime
local UnitExists = UnitExists
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local C_UnitAuras = C_UnitAuras
local C_Secrets = C_Secrets
local C_CurveUtil = C_CurveUtil

ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

API.Icons = (type(API.Icons) == "table") and API.Icons or {}
local Icons = API.Icons

-- Also register as API.Apply for backward compatibility
API.Apply = (type(API.Apply) == "table") and API.Apply or {}
local Apply = API.Apply

-- Hot locals
local type = type
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local floor = math.floor
local max = math.max

local function FastCall(fn, ...)
    if fn == nil then return false end
    return true, fn(...)
end

-- Lazy-bound references
local Collect   -- bound on first use
local Colors    -- API.Colors
local Masque    -- API.Masque
local CT        -- API.CooldownText (cooldown text manager)

local function EnsureBindings()
    if not Collect then Collect = API.Collect end
    if not Colors then Colors = API.Colors end
    if not Masque then Masque = API.Masque end
    if not CT then CT = API.CooldownText end
end

-- ── Fast-path Collect helpers (skip guard checks in hot path) ──
local _getDurationFast   -- Collect.GetDurationObjectFast (bound on first use)
local _getStackCountFast -- Collect.GetStackCountFast
local _hasExpirationFast -- Collect.HasExpirationFast
local _fastPathBound = false

local function BindFastPaths()
    if _fastPathBound then return end
    if not Collect then return end
    _getDurationFast   = Collect.GetDurationObjectFast or Collect.GetDurationObject
    _getStackCountFast = Collect.GetStackCountFast or Collect.GetStackCount
    _hasExpirationFast = Collect.HasExpirationFast or Collect.HasExpiration
    _fastPathBound = true
end

-- ── Cached shared.* flags (resolve once per configGen, not per icon) ──
local _sharedFlagsGen   = -1
local _showSwipe        = false
local _showText         = true
local _swipeReverse     = false
local _showStacks       = false
local _wantBuffHL       = false
local _wantDebuffHL     = false

local function RefreshSharedFlags(shared, gen)
    if _sharedFlagsGen == gen then return end
    _sharedFlagsGen = gen
    _showSwipe    = (shared and shared.showCooldownSwipe == true) or false
    _showText     = (shared and shared.showCooldownText ~= false) -- default true
    _swipeReverse = (shared and shared.cooldownSwipeDarkenOnLoss == true) or false
    _showStacks   = (shared and shared.showStackCount == true) or false
    _wantBuffHL   = (shared and shared.highlightOwnBuffs == true) or false
    _wantDebuffHL = (shared and shared.highlightOwnDebuffs == true) or false
end

-- DB access
local function GetAuras2DB()
    if API.GetDB then return API.GetDB() end
    if API.EnsureDB then return API.EnsureDB() end
    return nil, nil
end

-- ────────────────────────────────────────────────────────────────
-- Color helpers (late-bound from API.Colors or fallback)
-- ────────────────────────────────────────────────────────────────

local function GetOwnBuffHighlightRGB()
    local f = _G.MSUF_A2_GetOwnBuffHighlightRGB
    if type(f) == "function" then return f() end
    return 1.0, 0.85, 0.2
end

local function GetOwnDebuffHighlightRGB()
    local f = _G.MSUF_A2_GetOwnDebuffHighlightRGB
    if type(f) == "function" then return f() end
    return 1.0, 0.3, 0.3
end

local function GetStackCountRGB()
    local f = _G.MSUF_A2_GetStackCountRGB
    if type(f) == "function" then return f() end
    return 1.0, 1.0, 1.0
end

-- ────────────────────────────────────────────────────────────────
-- Icon Pool
-- ────────────────────────────────────────────────────────────────

-- Icons are stored on container._msufIcons[index]
-- Each icon is a Button with: .tex, .cooldown, .count, .border, .overlay

local function CreateIcon(container, index)
    local icon = CreateFrame("Button", nil, container)
    icon:SetSize(26, 26)
    icon:EnableMouse(true)
    icon:RegisterForClicks("RightButtonUp")
    icon._msufA2_container = container

    -- Texture
    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon.tex = tex

    -- Cooldown
    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetReverse(false)
    cd:SetSwipeColor(0, 0, 0, 0.65)
    cd:SetHideCountdownNumbers(true)
    icon.cooldown = cd

    -- Stack count text
    local count = icon:CreateFontString(nil, "OVERLAY")
    count:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    count:SetJustifyH("RIGHT")
    count:SetTextColor(GetStackCountRGB())
    icon.count = count

    -- Own-aura highlight glow (hidden by default)
    local glow = icon:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", 2, -2)
    glow:SetColorTexture(1, 1, 1, 0.3)
    glow:Hide()
    icon._msufOwnGlow = glow

    -- Background (subtle dark backdrop)
    local bg = icon:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    icon._msufBG = bg

    -- Tooltip support
    icon:SetScript("OnEnter", function(self)
        local _, shared = GetAuras2DB()
        if shared and shared.showTooltip ~= true then return end
        local unit = self._msufUnit
        local aid = self._msufAuraInstanceID
        if not unit or not aid then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        -- Secret-safe: SetUnitAuraByAuraInstanceID handles secrets internally
        if GameTooltip.SetUnitAuraByAuraInstanceID then
            GameTooltip:SetUnitAuraByAuraInstanceID(unit, aid, self._msufFilter or "HELPFUL")
        end
        GameTooltip:Show()
    end)

    icon:SetScript("OnLeave", function()
        if GameTooltip:IsOwned(icon) then
            GameTooltip:Hide()
        end
    end)

    -- Masque integration
    EnsureBindings()
    if Masque and Masque.PrepareButton then
        Masque.PrepareButton(icon)
    end
    local _, shared = GetAuras2DB()
    if Masque and Masque.IsEnabled and Masque.IsEnabled(shared) and Masque.AddButton then
        Masque.AddButton(icon)
        icon.MSUF_MasqueAdded = true
    end

    return icon
end

function Icons.AcquireIcon(container, index)
    if not container then return nil end

    local pool = container._msufIcons
    if not pool then
        pool = {}
        container._msufIcons = pool
    end

    -- Track high water mark for HideUnused bounded iteration
    local activeN = container._msufA2_activeN or 0
    if index > activeN then container._msufA2_activeN = index end

    local icon = pool[index]
    if icon then
        icon:Show()
        return icon
    end

    icon = CreateIcon(container, index)
    pool[index] = icon

    -- Keep an AID→icon map on the container for fast delta lookups
    if not container._msufA2_iconByAid then
        container._msufA2_iconByAid = {}
    end

    icon:Show()
    return icon
end

function Icons.HideUnused(container, fromIndex)
    if not container then return end
    local pool = container._msufIcons
    if not pool then return end

    -- Bound iteration to the last known active count (high water mark).
    local highWater = container._msufA2_activeN or #pool
    if fromIndex > highWater then return end -- nothing to hide

    local map = container._msufA2_iconByAid
    for i = fromIndex, highWater do
        local icon = pool[i]
        if icon then
            if icon:IsShown() then
                icon:Hide()
                local aid = icon._msufAuraInstanceID
                if aid and map and map[aid] == icon then
                    map[aid] = nil
                end
                icon._msufAuraInstanceID = nil
            end
        end
    end

    -- Update active count (the caller just committed fromIndex-1 icons)
    container._msufA2_activeN = fromIndex - 1

    -- Invalidate layout cache when count shrinks (forces re-layout on next grow)
    if container._msufA2_lastLayoutN and fromIndex - 1 < container._msufA2_lastLayoutN then
        container._msufA2_lastLayoutN = nil
    end
end

-- ────────────────────────────────────────────────────────────────
-- Layout Engine
-- ────────────────────────────────────────────────────────────────

function Icons.LayoutIcons(container, count, iconSize, spacing, perRow, growth, rowWrap)
    if not container or count <= 0 then return end

    -- ── Layout diff gate ──
    -- If count and configGen match last call, positions are identical. Skip.
    -- configGen covers iconSize, spacing, perRow, growth, rowWrap (all settings).
    local gen = _configGen
    if count == container._msufA2_lastLayoutN and gen == container._msufA2_lastLayoutGen then
        return
    end
    container._msufA2_lastLayoutN = count
    container._msufA2_lastLayoutGen = gen

    iconSize = iconSize or 26
    spacing = spacing or 2
    perRow = perRow or 12
    if perRow < 1 then perRow = 1 end

    local step = iconSize + spacing

    -- Direction multipliers
    local dx, dy = 1, -1  -- growth RIGHT, wrap DOWN
    local anchorX, anchorY = "LEFT", "BOTTOM"

    if growth == "LEFT" then
        dx = -1
        anchorX = "RIGHT"
    end
    if rowWrap == "UP" then
        dy = 1
    end

    -- Precompute anchor string ONCE (not per icon)
    local anchor = anchorY .. anchorX

    local pool = container._msufIcons
    if not pool then return end

    for i = 1, count do
        local icon = pool[i]
        if icon then
            local idx = i - 1
            local col = idx % perRow
            local row = (idx - col) / perRow  -- integer division (faster than floor)

            icon:ClearAllPoints()
            icon:SetSize(iconSize, iconSize)
            icon:SetPoint(anchor, container, anchor, col * step * dx, row * step * dy)
        end
    end
end

-- ────────────────────────────────────────────────────────────────
-- Visual Commit (CommitIcon)
-- 
-- This is the ONLY function that touches icon visuals.
-- Called once per icon per render. Uses diff gating on
-- auraInstanceID + config generation to skip redundant work.
-- ────────────────────────────────────────────────────────────────

local _configGen = 0  -- bumped by InvalidateDB

function Icons.BumpConfigGen()
    _configGen = _configGen + 1
    _bindingsDone = false  -- re-bind on next commit (picks up late-loaded modules)
    _fastPathBound = false -- re-bind fast paths
    _sharedFlagsGen = -1   -- force shared flags refresh
end

local _bindingsDone = false

function Icons.CommitIcon(icon, unit, aura, shared, isHelpful, hidePermanent, masterOn, isOwn, stackCountAnchor, configGen)
    if not icon then return false end
    if not _bindingsDone then
        EnsureBindings()
        BindFastPaths()
        _bindingsDone = true
    end

    local gen = configGen or _configGen
    RefreshSharedFlags(shared, gen)

    icon._msufUnit = unit
    icon._msufFilter = isHelpful and "HELPFUL" or "HARMFUL"

    -- Clear preview state if recycled (only when actually preview)
    if icon._msufA2_isPreview then
        icon._msufA2_isPreview = nil
        icon._msufA2_previewKind = nil
        local lbl = icon._msufA2_previewLabel
        if lbl and lbl.Hide then lbl:Hide() end
        icon._msufA2_lastCommit = nil
    end

    local container = icon._msufA2_container or icon:GetParent()
    local aidMap = container and container._msufA2_iconByAid

    local prevAid = icon._msufAuraInstanceID
    if not aura then
        if prevAid and aidMap and aidMap[prevAid] == icon then
            aidMap[prevAid] = nil
        end
        icon._msufAuraInstanceID = nil
        return false
    end

    local aid = aura._msufAuraInstanceID or aura.auraInstanceID
    if prevAid and prevAid ~= aid and aidMap and aidMap[prevAid] == icon then
        aidMap[prevAid] = nil
    end
    icon._msufAuraInstanceID = aid
    if aid and aidMap then aidMap[aid] = icon end

    -- ── Diff gate ──
    local gen = configGen or _configGen
    local last = icon._msufA2_lastCommit

    if last
        and last.aid == aid
        and last.gen == gen
        and last.isOwn == isOwn
    then
        -- Fast path: same aura, same config. Just refresh cooldown timer.
        Icons._RefreshTimer(icon, unit, aid, shared)
        return true
    end

    -- ── Full apply ──
    if not last then
        last = {}
        icon._msufA2_lastCommit = last
    end
    last.aid = aid
    last.gen = gen
    last.isOwn = isOwn

    -- 1. Texture (only when aid changed)
    if icon._msufA2_lastTexAid ~= aid then
        icon._msufA2_lastTexAid = aid
        local tex = aura.icon
        if tex ~= nil and icon.tex then
            icon.tex:SetTexture(tex)
        end
    end

    -- 2. Cooldown / Timer
    Icons._ApplyTimer(icon, unit, aid, shared)

    -- 3. Stack count
    Icons._ApplyStacks(icon, unit, aid, shared, stackCountAnchor)

    -- 4. Own-aura highlight
    Icons._ApplyOwnHighlight(icon, isOwn, isHelpful, shared)

    -- 5. Masque sync
    if Masque and icon.MSUF_MasqueAdded and Masque.SyncIconOverlayLevels then
        Masque.SyncIconOverlayLevels(icon)
    end

    icon:Show()
    return true
end

-- ────────────────────────────────────────────────────────────────
-- Timer application (cooldown swipe + text)
-- Uses duration objects (secret-safe pass-through)
-- ────────────────────────────────────────────────────────────────

function Icons._ApplyTimer(icon, unit, aid, shared)
    local cd = icon.cooldown
    if not cd then return end

    -- Use cached shared flags (refreshed per configGen in CommitIcon/RefreshAssignedIcons)
    cd:SetDrawSwipe(_showSwipe)
    cd:SetReverse(_swipeReverse)
    cd:SetHideCountdownNumbers(not _showText)

    local hadTimer = false

    -- Get duration object (secret-safe) — fast path skips 3 guards
    local obj = _getDurationFast and _getDurationFast(unit, aid)
    if obj then
        -- Cache method reference on cd frame to avoid type() check per call
        local cdSetFn = cd._msufA2_cdSetFn
        if cdSetFn == nil then
            if type(cd.SetCooldownFromDurationObject) == "function" then
                cdSetFn = cd.SetCooldownFromDurationObject
            elseif type(cd.SetTimerDuration) == "function" then
                cdSetFn = cd.SetTimerDuration
            else
                cdSetFn = false  -- sentinel: no method available
            end
            cd._msufA2_cdSetFn = cdSetFn
        end

        if cdSetFn then
            cdSetFn(cd, obj)
            hadTimer = true
        end

        icon._msufA2_durationObj = obj
        cd._msufA2_durationObj = obj

        if cd._msufCooldownFontString == false then
            cd._msufCooldownFontString = nil
            cd._msufCooldownFontStringRetryAt = nil
        end
    end

    if not hadTimer then
        local hasExp = _hasExpirationFast and _hasExpirationFast(unit, aid)
        if hasExp == false then
            if cd.Clear then cd:Clear() end
            if cd.SetCooldown then cd:SetCooldown(0, 0) end
            icon._msufA2_durationObj = nil
            cd._msufA2_durationObj = nil
        end
    end

    -- Cooldown text manager integration (CT already bound by CommitIcon)
    CT = CT or API.CooldownText
    local wantText = _showText and (icon._msufA2_hideCDNumbers ~= true)
    if CT then
        if wantText and hadTimer then
            if CT.RegisterIcon then CT.RegisterIcon(icon) end
            if CT.TouchIcon then CT.TouchIcon(icon) end
        elseif icon._msufA2_cdMgrRegistered and CT.UnregisterIcon then
            CT.UnregisterIcon(icon)
        end
    end

    icon._msufA2_lastHadTimer = hadTimer
end

-- Fast-path timer refresh (same auraInstanceID, possible reapply)
function Icons._RefreshTimer(icon, unit, aid, shared)
    local cd = icon.cooldown
    if not cd then return end

    -- Use cached shared flags (no shared table reads)
    if not _showSwipe and not _showText then return end

    local obj = _getDurationFast and _getDurationFast(unit, aid)
    if obj then
        -- Use cached method ref (set by _ApplyTimer)
        local cdSetFn = cd._msufA2_cdSetFn
        if cdSetFn == nil then
            if type(cd.SetCooldownFromDurationObject) == "function" then
                cdSetFn = cd.SetCooldownFromDurationObject
            elseif type(cd.SetTimerDuration) == "function" then
                cdSetFn = cd.SetTimerDuration
            else
                cdSetFn = false
            end
            cd._msufA2_cdSetFn = cdSetFn
        end

        if cdSetFn then
            cdSetFn(cd, obj)
        end

        icon._msufA2_durationObj = obj
        cd._msufA2_durationObj = obj
        icon._msufA2_lastHadTimer = true

        if cd._msufCooldownFontString == false then
            cd._msufCooldownFontString = nil
            cd._msufCooldownFontStringRetryAt = nil
        end

        CT = CT or API.CooldownText
        if CT and CT.TouchIcon then CT.TouchIcon(icon) end
    end
end

-- ────────────────────────────────────────────────────────────────
-- Stack count display
-- ────────────────────────────────────────────────────────────────

-- Cached stack count color (invalidated by BumpConfigGen)
local _stackR, _stackG, _stackB, _stackColorGen = 1, 1, 1, -1

function Icons._ApplyStacks(icon, unit, aid, shared, stackCountAnchor)
    local countFS = icon.count
    if not countFS then return end

    -- Use cached shared flag (no shared table read)
    if not _showStacks then
        if icon._msufA2_lastStackText then
            countFS:SetText("")
            countFS:Hide()
            icon._msufA2_lastStackText = nil
        end
        return
    end

    local stacks = _getStackCountFast and _getStackCountFast(unit, aid)
    if type(stacks) == "number" and stacks >= 2 then
        -- Only SetText when value changed
        if icon._msufA2_lastStackText ~= stacks then
            countFS:SetText(stacks)
            icon._msufA2_lastStackText = stacks
        end
        countFS:Show()
    else
        if icon._msufA2_lastStackText then
            countFS:SetText("")
            icon._msufA2_lastStackText = nil
        end
        countFS:Hide()
        return
    end

    -- Anchor: only reposition when anchor setting changed
    local anchor = stackCountAnchor or "TOPRIGHT"
    if icon._msufA2_lastStackAnchor ~= anchor then
        icon._msufA2_lastStackAnchor = anchor
        countFS:ClearAllPoints()
        if anchor == "TOPLEFT" then
            countFS:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
            countFS:SetJustifyH("LEFT")
        elseif anchor == "BOTTOMLEFT" then
            countFS:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 1, 1)
            countFS:SetJustifyH("LEFT")
        elseif anchor == "BOTTOMRIGHT" then
            countFS:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
            countFS:SetJustifyH("RIGHT")
        else
            countFS:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -1, -1)
            countFS:SetJustifyH("RIGHT")
        end
    end

    -- Color: cache to avoid _G lookup per icon
    local gen = _configGen
    if _stackColorGen ~= gen then
        _stackR, _stackG, _stackB = GetStackCountRGB()
        _stackColorGen = gen
    end
    countFS:SetTextColor(_stackR, _stackG, _stackB)
end

-- ────────────────────────────────────────────────────────────────
-- Own-aura highlight
-- ────────────────────────────────────────────────────────────────

-- Cached highlight colors (invalidated by configGen change)
local _hlBuffR, _hlBuffG, _hlBuffB = 1.0, 0.85, 0.2
local _hlDebR, _hlDebG, _hlDebB = 1.0, 0.3, 0.3
local _hlColorGen = -1

function Icons._ApplyOwnHighlight(icon, isOwn, isHelpful, shared)
    local glow = icon._msufOwnGlow
    if not glow then return end

    -- Use cached shared flags (no shared table reads)
    local show = false
    if isOwn then
        if isHelpful then
            show = _wantBuffHL
        else
            show = _wantDebuffHL
        end
    end

    if show then
        -- Refresh cached colors when config changes
        local gen = _configGen
        if _hlColorGen ~= gen then
            _hlBuffR, _hlBuffG, _hlBuffB = GetOwnBuffHighlightRGB()
            _hlDebR, _hlDebG, _hlDebB = GetOwnDebuffHighlightRGB()
            _hlColorGen = gen
        end

        if isHelpful then
            glow:SetColorTexture(_hlBuffR, _hlBuffG, _hlBuffB, 0.3)
        else
            glow:SetColorTexture(_hlDebR, _hlDebG, _hlDebB, 0.3)
        end
        glow:Show()
    else
        glow:Hide()
    end
end

-- ────────────────────────────────────────────────────────────────
-- Refresh all assigned icons (fast path: timer + stacks only)
-- Called when aura membership hasn't changed but values may have
-- ────────────────────────────────────────────────────────────────

function Icons.RefreshAssignedIcons(entry, unit, shared, stackCountAnchor)
    if not entry then return end
    if not _bindingsDone then
        EnsureBindings()
        BindFastPaths()
        _bindingsDone = true
    end

    -- Ensure cached shared flags are current
    RefreshSharedFlags(shared, _configGen)

    -- Inline container refresh (no closure allocation)
    -- Use activeN for bounded iteration (avoids walking dead pool entries)
    local pool, activeN, icon, aid

    pool = entry.buffs and entry.buffs._msufIcons
    if pool then
        activeN = entry.buffs._msufA2_activeN or #pool
        for i = 1, activeN do
            icon = pool[i]
            if icon and icon:IsShown() then
                aid = icon._msufAuraInstanceID
                if aid then
                    Icons._RefreshTimer(icon, unit, aid, shared)
                    Icons._ApplyStacks(icon, unit, aid, shared, stackCountAnchor)
                end
            end
        end
    end

    pool = entry.debuffs and entry.debuffs._msufIcons
    if pool then
        activeN = entry.debuffs._msufA2_activeN or #pool
        for i = 1, activeN do
            icon = pool[i]
            if icon and icon:IsShown() then
                aid = icon._msufAuraInstanceID
                if aid then
                    Icons._RefreshTimer(icon, unit, aid, shared)
                    Icons._ApplyStacks(icon, unit, aid, shared, stackCountAnchor)
                end
            end
        end
    end

    pool = entry.mixed and entry.mixed._msufIcons
    if pool then
        activeN = entry.mixed._msufA2_activeN or #pool
        for i = 1, activeN do
            icon = pool[i]
            if icon and icon:IsShown() then
                aid = icon._msufAuraInstanceID
                if aid then
                    Icons._RefreshTimer(icon, unit, aid, shared)
                    Icons._ApplyStacks(icon, unit, aid, shared, stackCountAnchor)
                end
            end
        end
    end
end

-- ────────────────────────────────────────────────────────────────
-- Preview icons (Edit Mode)
-- ────────────────────────────────────────────────────────────────

function Icons.RenderPreviewIcons(entry, unit, shared, useSingleRow, buffCap, debuffCap, stackCountAnchor)
    -- Delegate to existing preview system if available
    local fn = API._Render and API._Render.RenderPreviewIcons
    if type(fn) == "function" then
        return fn(entry, unit, shared, useSingleRow, buffCap, debuffCap, stackCountAnchor)
    end

    -- Minimal fallback: show placeholder icons
    local buffCount = 0
    local debuffCount = 0

    if entry.buffs and buffCap > 0 then
        for i = 1, math.min(3, buffCap) do
            local icon = Icons.AcquireIcon(entry.buffs, i)
            if icon then
                icon._msufA2_isPreview = true
                icon._msufA2_previewKind = "buff"
                if icon.tex then icon.tex:SetTexture(136116) end -- generic buff texture
                icon:Show()
                buffCount = buffCount + 1
            end
        end
        Icons.HideUnused(entry.buffs, buffCount + 1)
    end

    if entry.debuffs and debuffCap > 0 then
        for i = 1, math.min(3, debuffCap) do
            local icon = Icons.AcquireIcon(entry.debuffs, i)
            if icon then
                icon._msufA2_isPreview = true
                icon._msufA2_previewKind = "debuff"
                if icon.tex then icon.tex:SetTexture(136118) end -- generic debuff texture
                icon:Show()
                debuffCount = debuffCount + 1
            end
        end
        Icons.HideUnused(entry.debuffs, debuffCount + 1)
    end

    return buffCount, debuffCount
end

function Icons.RenderPreviewPrivateIcons(entry, unit, shared, privIconSize, spacing, stackCountAnchor)
    -- Delegate to existing preview system
    local fn = API._Render and API._Render.RenderPreviewPrivateIcons
    if type(fn) == "function" then
        return fn(entry, unit, shared, privIconSize, spacing, stackCountAnchor)
    end
end

-- ────────────────────────────────────────────────────────────────
-- Backward-compatible exports into API.Apply
-- (Options, CooldownText, Preview, Masque all reference API.Apply.*)
-- ────────────────────────────────────────────────────────────────

Apply.AcquireIcon = Icons.AcquireIcon
Apply.HideUnused = Icons.HideUnused
Apply.LayoutIcons = Icons.LayoutIcons
Apply.CommitIcon = Icons.CommitIcon
Apply.RefreshAssignedIcons = function(entry, unit, shared, masterOn, stackCountAnchor, hidePermanentBuffs)
    return Icons.RefreshAssignedIcons(entry, unit, shared, stackCountAnchor)
end
Apply.RefreshAssignedIconsDelta = function(entry, unit, shared, masterOn, stackCountAnchor, hidePermanentBuffs, upd, updN)
    return Icons.RefreshAssignedIcons(entry, unit, shared, stackCountAnchor)
end
Apply.RenderPreviewIcons = Icons.RenderPreviewIcons
Apply.RenderPreviewPrivateIcons = Icons.RenderPreviewPrivateIcons

-- Stubs for Apply helpers referenced by Render
Apply.ApplyAuraToIcon = function(icon, unit, aura, shared, isHelpful, hidePermanent, masterOn, isOwn, stackCountAnchor)
    return Icons.CommitIcon(icon, unit, aura, shared, isHelpful, hidePermanent, masterOn, isOwn, stackCountAnchor)
end

-- Font application helpers (referenced by Options/Fonts)
function Apply.ApplyFontsFromGlobal()
    -- Iterate all icons and re-apply font sizes
    local state = API.state
    local aby = state and state.aurasByUnit
    if not aby then return end
    for _, entry in pairs(aby) do
        if entry then
            Icons.RefreshAssignedIcons(entry, entry.unit, nil, nil)
        end
    end
end

-- Text offset stubs (Edit Mode references)
Apply.ApplyCooldownTextOffsets = Apply.ApplyCooldownTextOffsets or function() end
Apply.ApplyStackTextOffsets = Apply.ApplyStackTextOffsets or function() end
Apply.ApplyStackCountAnchorStyle = Apply.ApplyStackCountAnchorStyle or function() end

API.ApplyFontsFromGlobal = Apply.ApplyFontsFromGlobal

-- Global wrapper (referenced by MidnightSimpleUnitFrames.lua)
if type(_G.MSUF_Auras2_ApplyFontsFromGlobal) ~= "function" then
    _G.MSUF_Auras2_ApplyFontsFromGlobal = function() return Apply.ApplyFontsFromGlobal() end
end
