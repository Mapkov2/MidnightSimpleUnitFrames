-- ============================================================================
-- MSUF_A2_Icons.lua  Auras 3.0 Icon Factory + Visual Commit + Layout
-- Replaces the core of MSUF_A2_Apply.lua
--
-- Responsibilities:
--   1. Icon pool (AcquireIcon / HideUnused)
--   2. Visual commit (CommitIcon  texture, cooldown, stacks, border)
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

-- Secret value detector (Midnight/Beta)
local issecretvalue = _G and _G.issecretvalue

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

--  Fast-path Collect helpers (skip guard checks in hot path) 
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

-- Phase 8: file-scope locals for Icons._ methods (eliminates hash-table
-- lookup per icon in tight loops).  Assigned after method definitions.
local _fast_ApplyTimer
local _fast_RefreshTimer
local _fast_ApplyStacks
local _fast_ApplyOwnHighlight
local _fast_ApplyDispelBorder

--  Cached shared.* flags (resolve once per configGen, not per icon) 
local _sharedFlagsGen   = -1
local _showSwipe        = false
local _showText         = true
local _swipeReverse     = false
local _showStacks       = false
local _IS_BOSS = { boss1=true, boss2=true, boss3=true, boss4=true, boss5=true }
local _wantBuffHL       = false
local _wantDebuffHL     = false
local _useBlizzardTimer = false  -- true = Blizzard C++ pass-through for countdown text
local _useDispelBorders = false  -- dispel-type border coloring for debuffs

--  Debuff dispel-type color lookup (  la R41z0r / Blizzard) 
-- Maps dispel index  Blizzard color object; used for both manual
-- fallback and the C_CurveUtil-based GetAuraDispelTypeColor() API.
local _debuffColorByIndex = {
    [1] = _G.DEBUFF_TYPE_MAGIC_COLOR,
    [2] = _G.DEBUFF_TYPE_CURSE_COLOR,
    [3] = _G.DEBUFF_TYPE_DISEASE_COLOR,
    [4] = _G.DEBUFF_TYPE_POISON_COLOR,
    [5] = _G.DEBUFF_TYPE_BLEED_COLOR,
    [0] = _G.DEBUFF_TYPE_NONE_COLOR,
}
local _dispelNameToIndex = {
    Magic   = 1,
    Curse   = 2,
    Disease = 3,
    Poison  = 4,
    Bleed   = 5,
    None    = 0,
}

-- Build a step-curve for C_UnitAuras.GetAuraDispelTypeColor() (secret-safe).
-- This mirrors R41z0r's approach: one-time init, reused every commit.
local _debuffColorCurve
do
    local ok, curve = pcall(function()
        if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return nil end
        if not Enum or not Enum.LuaCurveType or not Enum.LuaCurveType.Step then return nil end
        local c = C_CurveUtil.CreateColorCurve()
        c:SetType(Enum.LuaCurveType.Step)
        for idx, col in pairs(_debuffColorByIndex) do
            if col then c:AddPoint(idx, col) end
        end
        return c
    end)
    _debuffColorCurve = ok and curve or nil
end

-- Manual fallback: dispelName string  r, g, b
local function GetDebuffColorFromName(name)
    local idx = _dispelNameToIndex[name] or 0
    local col = _debuffColorByIndex[idx] or _debuffColorByIndex[0]
    if not col then return 1, 0, 0 end
    if col.GetRGBA then return col:GetRGBA() end
    if col.GetRGB  then return col:GetRGB()  end
    if col.r       then return col.r, col.g, col.b end
    return col[1] or 1, col[2] or 0, col[3] or 0
end

-- Cached global MSUF font family (resolved once, updated by ApplyFontsFromGlobal)
local _globalFontPath   = nil   -- nil = not yet resolved
local _globalFontFlags  = "OUTLINE"

-- Resolve the global MSUF font (lazy; caches after first call)
local function ResolveGlobalFont()
    if _globalFontPath then return _globalFontPath, _globalFontFlags end
    local gfs = _G.MSUF_GetGlobalFontSettings
    if type(gfs) == "function" then
        local p, fl = gfs()
        if type(p) == "string" then _globalFontPath = p end
        if type(fl) == "string" then _globalFontFlags = fl end
    end
    return _globalFontPath, _globalFontFlags
end

local function RefreshSharedFlags(shared, gen)
    if type(shared) ~= "table" then return end
    if _sharedFlagsGen == gen then return end
    _sharedFlagsGen = gen
    _showSwipe    = (shared and shared.showCooldownSwipe == true) or false
    _showText     = (shared and shared.showCooldownText ~= false) -- default true
    _swipeReverse = (shared and shared.cooldownSwipeDarkenOnLoss == true) or false
    _showStacks   = (shared and shared.showStackCount ~= false) -- default true
    _wantBuffHL   = (shared and shared.highlightOwnBuffs == true) or false
    _wantDebuffHL = (shared and shared.highlightOwnDebuffs == true) or false
    _useBlizzardTimer = (shared and shared.useBlizzardTimerText == true) or false
    _useDispelBorders = (shared and shared.useDebuffTypeBorders == true) or false
end

-- --
-- Text config resolution (per-icon; cached by configGen)
-- Applies stack/cooldown text sizes + offsets from shared + per-unit layout
-- Zero per-frame cost: runs only when configGen changes.
-- --

local function ResolveTextConfig(icon, unit, shared, gen)
    if not icon then return end
    if icon._msufA2_textCfgGen == gen then return end
    icon._msufA2_textCfgGen = gen

    local stackSize = (shared and shared.stackTextSize) or 14
    local cdSize = (shared and shared.cooldownTextSize) or 14

    local stackOffX = (shared and shared.stackTextOffsetX)
    if type(stackOffX) ~= "number" then stackOffX = -1 end
    local stackOffY = (shared and shared.stackTextOffsetY)
    if type(stackOffY) ~= "number" then stackOffY = 1 end
    local cdOffX = (shared and shared.cooldownTextOffsetX) or 0
    local cdOffY = (shared and shared.cooldownTextOffsetY) or 0

    -- Per-unit overrides (a2.perUnit[unit].layout)
    local a2 = nil
    local DB = API and API.DB
    local cache = DB and DB.cache
    if cache and cache.ready and type(cache.a2) == "table" then
        a2 = cache.a2
    else
        -- Fallback for early load-order: query via API.GetDB if present
        local getdb = API and API.GetDB
        if type(getdb) == "function" then
            local aa, ss = getdb()
            if type(aa) == "table" then a2 = aa end
            if not shared and type(ss) == "table" then shared = ss end
        end
    end

    local pu = a2 and a2.perUnit and unit and a2.perUnit[unit]
    if pu and pu.overrideLayout == true and type(pu.layout) == "table" then
        local lay = pu.layout
        if type(lay.stackTextSize) == "number" then stackSize = lay.stackTextSize end
        if type(lay.cooldownTextSize) == "number" then cdSize = lay.cooldownTextSize end

        if type(lay.stackTextOffsetX) == "number" then stackOffX = lay.stackTextOffsetX end
        if type(lay.stackTextOffsetY) == "number" then stackOffY = lay.stackTextOffsetY end
        if type(lay.cooldownTextOffsetX) == "number" then cdOffX = lay.cooldownTextOffsetX end
        if type(lay.cooldownTextOffsetY) == "number" then cdOffY = lay.cooldownTextOffsetY end
    end

    if type(stackSize) ~= "number" or stackSize <= 0 then stackSize = 14 end
    if type(cdSize) ~= "number" or cdSize <= 0 then cdSize = 14 end
    if type(stackOffX) ~= "number" then stackOffX = 0 end
    if type(stackOffY) ~= "number" then stackOffY = 0 end
    if type(cdOffX) ~= "number" then cdOffX = 0 end
    if type(cdOffY) ~= "number" then cdOffY = 0 end

    icon._msufA2_stackTextSize = stackSize
    icon._msufA2_cooldownTextSize = cdSize
    icon._msufA2_stackTextOffsetX = stackOffX
    icon._msufA2_stackTextOffsetY = stackOffY
    icon._msufA2_cooldownTextOffsetX = cdOffX
    icon._msufA2_cooldownTextOffsetY = cdOffY
end


-- DB access
local function GetAuras2DB()
    if API.GetDB then return API.GetDB() end
    if API.EnsureDB then return API.EnsureDB() end
    return nil, nil
end

-- --
-- Color helpers (late-bound from API.Colors or fallback)
-- --

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

-- --
-- Icon Pool
-- --

-- Icons are stored on container._msufIcons[index]
-- Each icon is a Button with: .tex, .cooldown, .count, .border, .overlay

local function CreateIcon(container, index)
    local icon = CreateFrame("Button", nil, container)
    icon:SetSize(26, 26)
-- Stack count overlay frame (keeps stacks above Masque/borders)
local countFrame = CreateFrame("Frame", nil, icon)
countFrame:SetAllPoints(icon)
countFrame:SetFrameLevel(icon:GetFrameLevel() + 10)
icon.countFrame = countFrame

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
    local count = (icon.countFrame or icon):CreateFontString(nil, "OVERLAY")
    -- Use global MSUF font when available, fallback to default
    local _initFont, _initFlags = "Fonts\\FRIZQT__.TTF", "OUTLINE"
    local _gfs = _G.MSUF_GetGlobalFontSettings
    if type(_gfs) == "function" then
        local p, fl = _gfs()
        if type(p) == "string" then _initFont = p end
        if type(fl) == "string" then _initFlags = fl end
    end
    count:SetFont(_initFont, 14, _initFlags)
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

    -- Dispel-type colored border overlay (hidden by default)
    -- Uses Blizzard's standard debuff overlay texture, colored per dispel type.
    local dispelBdr = icon:CreateTexture(nil, "OVERLAY", nil, 1)
    dispelBdr:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
    dispelBdr:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    dispelBdr:SetAllPoints(icon)
    dispelBdr:Hide()
    icon._msufDispelBorder = dispelBdr

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
        -- PERF: Skip Show() if already visible (IsShown() is cheaper than Show())
        if not icon:IsShown() then
            icon:Show()
        end
        return icon
    end

    icon = CreateIcon(container, index)
    pool[index] = icon

    -- Keep an icon map on the container for fast delta lookups
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
    local highWater = container._msufA2_activeN or 0
    
    -- PERF: Early exit if nothing to hide (fromIndex > active count)
    -- This skips the loop entirely when all icons are already in use
    if fromIndex > highWater then
        -- Still update active count for caller's bookkeeping
        container._msufA2_activeN = fromIndex - 1
        return
    end
    
    -- PERF: Early exit if activeN already matches (no change)
    if highWater == fromIndex - 1 then return end

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

-- Config generation counter: MUST be declared before LayoutIcons and BumpConfigGen
-- so Lua 5.1 captures it as a proper upvalue (not a global nil reference).
local _configGen = 0
local _bindingsDone = false

function Icons.BumpConfigGen()
    _configGen = _configGen + 1
    _bindingsDone = false  -- re-bind on next commit (picks up late-loaded modules)
    _fastPathBound = false -- re-bind fast paths
    _sharedFlagsGen = -1   -- force shared flags refresh
end

-- --
-- Layout Engine
-- --

function Icons.LayoutIcons(container, count, iconSize, spacing, perRow, growth, rowWrap, configGen)
    if not container or count <= 0 then return end

    --  Layout diff gate 
    -- If count and configGen match last call, positions are identical. Skip.
    -- configGen covers iconSize, spacing, perRow, growth, rowWrap (all settings).
    local gen = configGen or _configGen
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

    -- PERF: Cache container-level layout params to skip per-icon checks
    local lastSize = container._msufA2_lastIconSize
    local sizeChanged = (lastSize ~= iconSize)
    if sizeChanged then container._msufA2_lastIconSize = iconSize end

    for i = 1, count do
        local icon = pool[i]
        if icon then
            local idx = i - 1
            local col = idx % perRow
            local row = (idx - col) / perRow  -- integer division (faster than floor)
            local x = col * step * dx
            local y = row * step * dy

            -- PERF: Skip SetPoint if position unchanged
            if icon._msufA2_lastX ~= x or icon._msufA2_lastY ~= y or icon._msufA2_lastAnchor ~= anchor then
                icon._msufA2_lastX = x
                icon._msufA2_lastY = y
                icon._msufA2_lastAnchor = anchor
                icon:ClearAllPoints()
                icon:SetPoint(anchor, container, anchor, x, y)
            end
            
            -- PERF: Skip SetSize if unchanged
            if sizeChanged or icon._msufA2_lastSize ~= iconSize then
                icon._msufA2_lastSize = iconSize
                icon:SetSize(iconSize, iconSize)
            end
        end
    end
end

-- --
-- Visual Commit (CommitIcon)
-- 
-- This is the ONLY function that touches icon visuals.
-- Called once per icon per render. Uses diff gating on
-- auraInstanceID + config generation to skip redundant work.
-- --




function Icons.CommitIcon(icon, unit, aura, shared, isHelpful, hidePermanent, masterOn, isOwn, stackCountAnchor, configGen)
    if not icon then return false end
    if not _bindingsDone then
        EnsureBindings()
        BindFastPaths()
        _bindingsDone = true
    end

    local gen = configGen or _configGen
    -- PERF: Inline gen-check to skip function call overhead (most calls hit this fast-path)
    if _sharedFlagsGen ~= gen then
        RefreshSharedFlags(shared, gen)
    end

    if not aura then
        local container = icon._msufA2_container or icon:GetParent()
        local aidMap = container and container._msufA2_iconByAid
        local prevAid = icon._msufAuraInstanceID
        if prevAid and aidMap and aidMap[prevAid] == icon then
            aidMap[prevAid] = nil
        end
        icon._msufAuraInstanceID = nil
        if icon._msufDispelBorder then icon._msufDispelBorder:Hide() end
        return false
    end

    local aid = aura._msufAuraInstanceID or aura.auraInstanceID

    --  Fast-path diff gate: same aura, same config †’ skip all bookkeeping 
    local last = icon._msufA2_lastCommit
    if last
        and last.aid == aid
        and last.gen == gen
        and last.isOwn == isOwn
    then
        -- Same aura, same config. Only refresh timer + stacks (values may have changed).
        -- PERF: Pass aura object to use pre-cached duration/stack values
        _fast_RefreshTimer(icon, unit, aid, shared, aura)
        _fast_ApplyStacks(icon, unit, aid, shared, stackCountAnchor, aura)
        return true
    end

    --  Full apply: update all bookkeeping + visuals 
    icon._msufUnit = unit
    icon._msufFilter = isHelpful and "HELPFUL" or "HARMFUL"

    -- Clear preview state if recycled (only when actually preview)
    if icon._msufA2_isPreview then
        icon._msufA2_isPreview = nil
        icon._msufA2_previewKind = nil
        local lbl = icon._msufA2_previewLabel
        if lbl and lbl.Hide then lbl:Hide() end
        -- Hide private aura preview overlays
        if icon._msufPrivateBorder then icon._msufPrivateBorder:Hide() end
        if icon._msufPrivateLock then icon._msufPrivateLock:Hide() end
        if icon._msufDispelBorder then icon._msufDispelBorder:Hide() end
        last = nil
        icon._msufA2_lastCommit = nil
    end

    local container = icon._msufA2_container or icon:GetParent()
    local aidMap = container and container._msufA2_iconByAid

    local prevAid = icon._msufAuraInstanceID
    if prevAid and prevAid ~= aid and aidMap and aidMap[prevAid] == icon then
        aidMap[prevAid] = nil
    end
    icon._msufAuraInstanceID = aid
    icon._msufAura = aura  -- PERF: Store aura ref for cached duration/stacks
    if aid and aidMap then aidMap[aid] = icon end

    if not last then
        last = {}
        icon._msufA2_lastCommit = last
    end
    last.aid = aid
    last.gen = gen
    last.isOwn = isOwn

    -- PERF: Inline gen-check to skip function call overhead
    if icon._msufA2_textCfgGen ~= gen then
        ResolveTextConfig(icon, unit, shared, gen)
    end

    -- 1. Texture (only when aid changed)
    if icon._msufA2_lastTexAid ~= aid then
        icon._msufA2_lastTexAid = aid
        local tex = aura.icon
        if tex ~= nil and icon.tex then
            icon.tex:SetTexture(tex)
        end
    end

    -- 2. Cooldown / Timer
    _fast_ApplyTimer(icon, unit, aid, shared, aura)

    -- 3. Stack count
    _fast_ApplyStacks(icon, unit, aid, shared, stackCountAnchor, aura)

    -- 4. Own-aura highlight
    _fast_ApplyOwnHighlight(icon, isOwn, isHelpful, shared)

    -- 5. Dispel-type border (Magic/Curse/Poison/Disease colored)
    _fast_ApplyDispelBorder(icon, unit, aura, isHelpful)

    -- 6. Masque sync
    if Masque and icon.MSUF_MasqueAdded and Masque.SyncIconOverlayLevels then
        Masque.SyncIconOverlayLevels(icon)
    end

    icon:Show()
    return true
end

-- --
-- Timer application (cooldown swipe + text)
-- Uses duration objects (secret-safe pass-through)
-- --


local function ClearCooldownVisual(icon, cd)
    if not icon or not cd then return end

    -- Unregister from the cooldown text manager to prevent stale updates.
    CT = CT or (API and API.CooldownText)
    if CT and CT.UnregisterIcon then
        CT.UnregisterIcon(icon)
    end

    -- Clear swipe/timer state (works across template variants).
    if cd.Clear then cd:Clear() end
    if cd.SetCooldown then cd:SetCooldown(0, 0) end
    if cd.SetUseAuraDisplayTime then cd:SetUseAuraDisplayTime(false) end

    -- Force-hide countdown numbers when no timer is present (prevents stale text).
    if cd.SetHideCountdownNumbers then
        cd:SetHideCountdownNumbers(true)
    end

    -- If we already discovered the cooldown fontstring, clear its text.
    local fs = cd._msufCooldownFontString
    if fs and fs ~= false and fs.SetText then
        fs:SetText("")
    end

    icon._msufA2_durationObj = nil
    cd._msufA2_durationObj = nil
    icon._msufA2_lastHadTimer = false
end

local function ApplyCooldownTextStyle(icon, cd, now, force)
    if not icon or not cd then return end
    if icon._msufA2_hideCDNumbers == true then return end
    if not force and _showText ~= true then return end

    local size = icon._msufA2_cooldownTextSize or 14
    local offX = icon._msufA2_cooldownTextOffsetX or 0
    local offY = icon._msufA2_cooldownTextOffsetY or 0

    local fs = cd._msufCooldownFontString
    if fs == false then fs = nil end

    -- Only discover the cooldown fontstring when needed (rare) to keep hot paths cheap.
    if not fs then
        if type(now) ~= "number" then
            now = GetTime()
        end
        CT = CT or (API and API.CooldownText)
        local getfs = CT and CT.GetCooldownFontString
        if type(getfs) == "function" then
            fs = getfs(icon, now)
        end
    end

    if not fs then return end
    cd._msufCooldownFontString = fs

    -- Resolve global font family (cached, cheap)
    local gFont, gFlags = ResolveGlobalFont()

    -- Apply font family + size (diff-gated on both size AND font path)
    if fs.GetFont and fs.SetFont then
        local curFont, curSize, curFlags = fs:GetFont()
        local wantFont = gFont or curFont
        local wantFlags = gFlags or curFlags or "OUTLINE"
        if cd._msufA2_cdTextSize ~= size or cd._msufA2_cdFontPath ~= wantFont then
            if wantFont then
                fs:SetFont(wantFont, size, wantFlags)
            end
            cd._msufA2_cdTextSize = size
            cd._msufA2_cdFontPath = wantFont
        end
    end

    -- Apply offsets (only when changed)
    if cd._msufA2_cdTextOffX ~= offX or cd._msufA2_cdTextOffY ~= offY then
        cd._msufA2_cdTextOffX = offX
        cd._msufA2_cdTextOffY = offY
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", cd, "CENTER", offX, offY)
    end
end

-- PERF: aura parameter for pre-cached duration object (ZERO C API calls!)
function Icons._ApplyTimer(icon, unit, aid, shared, aura)
    local cd = icon.cooldown
    if not cd then return end

    local hadTimer = false

    -- PERF: Use pre-cached duration object instead of C API call
    local obj = aura and aura._msufDurationObj
    if not obj and _getDurationFast then
        -- Fallback if no cached value
        obj = _getDurationFast(unit, aid)
    end
    
    if obj then
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
            hadTimer = true
        end

        icon._msufA2_durationObj = obj
        cd._msufA2_durationObj = obj
    end

    -- Pass-through: tell Blizzard CooldownFrame to render aura timer natively in C++.
    if _useBlizzardTimer and cd.SetUseAuraDisplayTime then
        cd:SetUseAuraDisplayTime(hadTimer)
    end

    -- Apply shared visual flags.
    cd:SetDrawSwipe(_showSwipe)
    cd:SetReverse(_swipeReverse)
    if hadTimer then
        cd:SetHideCountdownNumbers(not _showText)
    else
        ClearCooldownVisual(icon, cd)
    end

    -- Cooldown text manager: skip entirely in pass-through (Blizzard C++ renders text).
    if not _useBlizzardTimer then
        CT = CT or API.CooldownText
        local wantText = _showText and (icon._msufA2_hideCDNumbers ~= true)
        if CT then
            if wantText and hadTimer then
                if CT.RegisterIcon then CT.RegisterIcon(icon) end
                if CT.TouchIcon then CT.TouchIcon(icon) end
            elseif CT.UnregisterIcon then
                CT.UnregisterIcon(icon)
            end
        end
    else
        -- Pass-through: ensure CT is not tracking this icon.
        CT = CT or API.CooldownText
        if CT and CT.UnregisterIcon then CT.UnregisterIcon(icon) end
    end

    -- Apply cooldown text font size + offsets (styles Blizzard native text too).
    if hadTimer and _showText == true and icon._msufA2_hideCDNumbers ~= true then
        ApplyCooldownTextStyle(icon, cd, nil)
    end

    icon._msufA2_lastHadTimer = hadTimer
end

-- Fast-path timer refresh (same auraInstanceID, possible reapply)
-- PERF: Uses pre-cached duration object from aura (ZERO C API calls!)
function Icons._RefreshTimer(icon, unit, aid, shared, aura)
    local cd = icon.cooldown
    if not cd then return end

    -- PERF: Use pre-cached duration object instead of C API call
    local obj = aura and aura._msufDurationObj
    if not obj and _getDurationFast then
        -- Fallback if no cached value
        obj = _getDurationFast(unit, aid)
    end
    
    if not obj then
        if icon._msufA2_lastHadTimer == true or cd._msufA2_durationObj ~= nil then
            ClearCooldownVisual(icon, cd)
        end
        return
    end

    -- Both swipe and text disabled: nothing to update.
    if not _showSwipe and not _showText then return end

    -- Refresh duration on the CooldownFrame (needed for both swipe and text).
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

    -- CT ticker: only when NOT pass-through AND text is enabled.
    -- Pass-through: Blizzard C++ auto-updates countdown from SetUseAuraDisplayTime.
    -- Text disabled: no reason to touch CT at all.
    if not _useBlizzardTimer and _showText then
        CT = CT or API.CooldownText
        if CT and CT.TouchIcon then CT.TouchIcon(icon) end
    end
end

-- --
-- Stack count display
-- --

-- Cached stack count color (invalidated by BumpConfigGen)
local _stackR, _stackG, _stackB, _stackColorGen = 1, 1, 1, -1

-- PERF: aura parameter for pre-cached stack count (ZERO C API calls!)
function Icons._ApplyStacks(icon, unit, aid, shared, stackCountAnchor, aura)
    local countFS = icon.count
    if not countFS then return end

    -- Phase 8: ResolveTextConfig already called by all callers (CommitIcon / RefreshAssignedIcons).



    -- Apply stack font family + size (gen-guarded: skip GetFont C-API on hot path)
    if icon._msufA2_stackFontGen ~= _configGen then
        icon._msufA2_stackFontGen = _configGen
        local wantSize = icon._msufA2_stackTextSize or 14
        if countFS.GetFont and countFS.SetFont then
            local gFont, gFlags = ResolveGlobalFont()
            local curFont, curSize, curFlags = countFS:GetFont()
            local wantFont = gFont or curFont
            local wantFlags = gFlags or curFlags or "OUTLINE"
            if icon._msufA2_lastStackFontSize ~= wantSize or icon._msufA2_lastStackFontPath ~= wantFont then
                if wantFont then
                    countFS:SetFont(wantFont, wantSize, wantFlags)
                end
                icon._msufA2_lastStackFontSize = wantSize
                icon._msufA2_lastStackFontPath = wantFont
            end
        end
    end

    -- Anchor style (justify) + offsets
    local anchor = stackCountAnchor or "TOPRIGHT"
    if icon._msufA2_lastStackJustifyAnchor ~= anchor then
        icon._msufA2_lastStackJustifyAnchor = anchor

        if anchor == "TOPLEFT" or anchor == "BOTTOMLEFT" then
            countFS:SetJustifyH("LEFT")
        else
            countFS:SetJustifyH("RIGHT")
        end
        if anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT" then
            countFS:SetJustifyV("BOTTOM")
        else
            countFS:SetJustifyV("TOP")
        end
    end

    local offX = icon._msufA2_stackTextOffsetX or 0
    local offY = icon._msufA2_stackTextOffsetY or 0
    if icon._msufA2_lastStackPointAnchor ~= anchor
        or icon._msufA2_lastStackPointX ~= offX
        or icon._msufA2_lastStackPointY ~= offY
    then
        icon._msufA2_lastStackPointAnchor = anchor
        icon._msufA2_lastStackPointX = offX
        icon._msufA2_lastStackPointY = offY

        countFS:ClearAllPoints()
        if anchor == "TOPLEFT" then
            countFS:SetPoint("TOPLEFT", icon, "TOPLEFT", offX, offY)
        elseif anchor == "BOTTOMLEFT" then
            countFS:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", offX, offY)
        elseif anchor == "BOTTOMRIGHT" then
            countFS:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", offX, offY)
        else
            countFS:SetPoint("TOPRIGHT", icon, "TOPRIGHT", offX, offY)
        end
    end

    -- Shared flags cache determines if stack display is enabled.
    if not _showStacks then
        if countFS.IsShown and countFS:IsShown() then countFS:Hide() end
        return
    end

    -- PERF: Use pre-cached stack count instead of C API call
    local count = aura and aura._msufStackCount
    if count == nil and _getStackCountFast then
        -- Fallback if no cached value
        count = _getStackCountFast(unit, aid)
    end
    
    if count == nil then
        if countFS.IsShown and countFS:IsShown() then countFS:Hide() end
        icon._msufA2_lastCountText = nil
        return
    end

    -- Midnight/Secret-mode: stack display values can be secret.
    -- PASS-THROUGH to FontStrings is allowed; avoid comparisons/arithmetic.
    if issecretvalue and issecretvalue(count) == true then
        countFS:SetText(count)
        icon._msufA2_lastCountText = nil
    else
        local txt
        if type(count) == "number" then
            if count <= 1 then
                if countFS.IsShown and countFS:IsShown() then countFS:Hide() end
                icon._msufA2_lastCountText = nil
                return
            end
            txt = tostring(count)
        elseif type(count) == "string" then
            if count == "" then
                if countFS.IsShown and countFS:IsShown() then countFS:Hide() end
                icon._msufA2_lastCountText = nil
                return
            end
            txt = count
        else
            if countFS.IsShown and countFS:IsShown() then countFS:Hide() end
            icon._msufA2_lastCountText = nil
            return
        end

        if icon._msufA2_lastCountText ~= txt then
            icon._msufA2_lastCountText = txt
            countFS:SetText(txt)
        end
    end

    -- At this point we have a visible stack display (count already set).
    -- Diff-gate SetTextColor to avoid redundant C-API calls on hot path.
    local wantR, wantG, wantB = 1, 1, 1
    if shared and shared.ownStackCountColor == true and icon._msufA2_lastCommit and icon._msufA2_lastCommit.isOwn == true then
        wantR, wantG, wantB = GetStackCountRGB()
    end
    if icon._msufA2_lastStackR ~= wantR or icon._msufA2_lastStackG ~= wantG or icon._msufA2_lastStackB ~= wantB then
        icon._msufA2_lastStackR = wantR
        icon._msufA2_lastStackG = wantG
        icon._msufA2_lastStackB = wantB
        countFS:SetTextColor(wantR, wantG, wantB)
    end

    if not countFS.IsShown or not countFS:IsShown() then
        countFS:Show()
    end
end


-- --
-- Own-aura highlight
-- --

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

--  Dispel-type border (Magic/Curse/Poison/Disease/Bleed colored) 
-- Purely cosmetic classification border for debuffs that have an actual
-- dispel school (Magic/Curse/Disease/Poison/Bleed).  Non-dispellable
-- debuffs (dispelName == nil / "" / "None") are left without a border.
-- This is independent of the bar-outline dispel highlight (Bars menu)
-- which tracks whether the *player* can actively dispel on that unit.
--
-- Color resolution:
--   1. Try C_UnitAuras.GetAuraDispelTypeColor() with step-curve (secret-safe)
--   2. Fallback to manual dispelName  DEBUFF_TYPE_*_COLOR lookup
function Icons._ApplyDispelBorder(icon, unit, aura, isHelpful)
    local bdr = icon._msufDispelBorder
    if not bdr then return end

    -- Only show on harmful auras when the feature is enabled
    if isHelpful or not _useDispelBorders or not aura then
        bdr:Hide()
        return
    end

    -- Gate: only debuffs with a *real* dispel school get a border.
    -- dispelName may be a secret value on private auras in that case
    -- we allow the API path below to resolve the color (it's secret-safe).
    local dName = aura.dispelName
    local isSecret = issecretvalue and dName ~= nil and issecretvalue(dName)
    if not isSecret then
        if not dName or dName == "" or dName == "None" then
            bdr:Hide()
            return
        end
    end

    local r, g, b = 1, 0.25, 0.25  -- default debuff red
    local usedApi = false

    -- Primary: C_UnitAuras.GetAuraDispelTypeColor (secret-safe, works for private auras)
    local aid = aura._msufAuraInstanceID or aura.auraInstanceID
    if aid and unit and _debuffColorCurve
       and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor then
        local ok, color = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, aid, _debuffColorCurve)
        if ok and color then
            usedApi = true
            if color.GetRGBA then
                r, g, b = color:GetRGBA()
            elseif color.r then
                r, g, b = color.r, color.g, color.b
            end
        end
    end

    -- Fallback: manual dispelName lookup (only reached for non-secret values)
    if not usedApi then
        if isSecret then
            -- Secret dispelName but API unavailable can't determine type safely
            bdr:Hide()
            return
        end
        local fr, fg, fb = GetDebuffColorFromName(dName)
        if fr then r, g, b = fr, fg, fb end
    end

    bdr:SetVertexColor(r, g, b, 1)
    bdr:Show()
end

-- Phase 8: bind file-scope locals (defined above) now that methods exist.
_fast_ApplyTimer        = Icons._ApplyTimer
_fast_RefreshTimer      = Icons._RefreshTimer
_fast_ApplyStacks       = Icons._ApplyStacks
_fast_ApplyOwnHighlight = Icons._ApplyOwnHighlight
_fast_ApplyDispelBorder = Icons._ApplyDispelBorder

-- --
-- Refresh all assigned icons (fast path: timer + stacks only)
-- Called when aura membership hasn't changed but values may have
-- --

function Icons.RefreshAssignedIcons(entry, unit, shared, stackCountAnchor)
    if not entry then return end
    if not _bindingsDone then
        EnsureBindings()
        BindFastPaths()
        _bindingsDone = true
    end

    -- PERF: Inline gen-check to skip function call overhead
    if _sharedFlagsGen ~= _configGen then
        RefreshSharedFlags(shared, _configGen)
    end

    -- Inline container refresh (no closure allocation)
    -- Use activeN for bounded iteration (avoids walking dead pool entries)
    local pool, activeN, icon, aid
    local gen = _configGen  -- Cache for inner loop

    pool = entry.buffs and entry.buffs._msufIcons
    if pool then
        activeN = entry.buffs._msufA2_activeN or #pool
        for i = 1, activeN do
            icon = pool[i]
            if icon and icon:IsShown() then
                aid = icon._msufAuraInstanceID
                if aid then
                    -- PERF: Inline gen-check for ResolveTextConfig
                    if icon._msufA2_textCfgGen ~= gen then
                        ResolveTextConfig(icon, unit, shared, gen)
                    end
                    -- PERF: Use stored aura ref for cached duration/stacks
                    local aura = icon._msufAura
                    _fast_RefreshTimer(icon, unit, aid, shared, aura)
                    _fast_ApplyStacks(icon, unit, aid, shared, stackCountAnchor, aura)
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
                    -- PERF: Inline gen-check
                    if icon._msufA2_textCfgGen ~= gen then
                        ResolveTextConfig(icon, unit, shared, gen)
                    end
                    local aura = icon._msufAura
                    _fast_RefreshTimer(icon, unit, aid, shared, aura)
                    _fast_ApplyStacks(icon, unit, aid, shared, stackCountAnchor, aura)
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
                    -- PERF: Inline gen-check
                    if icon._msufA2_textCfgGen ~= gen then
                        ResolveTextConfig(icon, unit, shared, gen)
                    end
                    local aura = icon._msufAura
                    _fast_RefreshTimer(icon, unit, aid, shared, aura)
                    _fast_ApplyStacks(icon, unit, aid, shared, stackCountAnchor, aura)
                end
            end
        end
    end
end

-- --
-- Preview icons (Edit Mode)
-- --

-- Sample textures for varied preview icons (common WoW spell icons)
local _PREVIEW_BUFF_TEXTURES = {
    136116,  -- generic buff (INV_Misc_QuestionMark)
    135932,  -- Arcane Intellect
    135987,  -- Power Word: Fortitude
    136085,  -- Mark of the Wild
    135915,  -- Blessing of Kings
    132333,  -- Renew
    136075,  -- Rejuvenation
    135981,  -- Prayer of Mending
    136076,  -- Regrowth
    135964,  -- Shield
    136048,  -- Heroism / Bloodlust
    132316,  -- Beacon of Light
}
local _PREVIEW_DEBUFF_TEXTURES = {
    136118,  -- generic debuff
    136139,  -- Shadow Word: Pain
    136197,  -- Corruption
    135817,  -- Agony
    132851,  -- Flame Shock
    135813,  -- Moonfire
    136188,  -- Curse of Tongues
    136186,  -- Slow
    135975,  -- Polymorph
    132337,  -- Frost Nova
    136093,  -- Rend
    136170,  -- Deep Wounds
}
local _PREVIEW_BUFF_TEX_N = #_PREVIEW_BUFF_TEXTURES
local _PREVIEW_DEBUFF_TEX_N = #_PREVIEW_DEBUFF_TEXTURES

-- Cooldown durations per preview slot (varying so they don't all tick together)
local _PREVIEW_CD_DURATIONS = { 12, 18, 8, 25, 15, 10, 20, 30, 6, 22, 14, 9 }
local _PREVIEW_CD_DUR_N = #_PREVIEW_CD_DURATIONS

function Icons.RenderPreviewIcons(entry, unit, shared, useSingleRow, buffCap, debuffCap, stackCountAnchor)
    -- Delegate to existing preview system if available
    local fn = API._Render and API._Render.RenderPreviewIcons
    if type(fn) == "function" then
        return fn(entry, unit, shared, useSingleRow, buffCap, debuffCap, stackCountAnchor)
    end

    local buffCount = 0
    local debuffCount = 0
    local gen = _configGen
    local showStacks = (shared and shared.showStackCount ~= false)
    local now = GetTime()

    -- Apply full text config + cooldown to a preview icon
    local function SetupPreviewIcon(icon, idx, kind)
        icon._msufA2_isPreview = true
        icon._msufA2_previewKind = kind
        icon._msufUnit = unit

        -- Varied texture
        if icon.tex then
            if kind == "buff" then
                icon.tex:SetTexture(_PREVIEW_BUFF_TEXTURES[((idx - 1) % _PREVIEW_BUFF_TEX_N) + 1])
            else
                icon.tex:SetTexture(_PREVIEW_DEBUFF_TEXTURES[((idx - 1) % _PREVIEW_DEBUFF_TEX_N) + 1])
            end
        end

        icon:Show()

        -- Invalidate + resolve text config
        icon._msufA2_textCfgGen = nil
        ResolveTextConfig(icon, unit, shared, gen)

        -- Stack text
        icon._msufA2_lastStackFontSize = nil
        icon._msufA2_lastStackFontPath = nil
        icon._msufA2_lastStackPointAnchor = nil
        icon._msufA2_lastStackPointX = nil
        icon._msufA2_lastStackPointY = nil
        icon._msufA2_lastStackJustifyAnchor = nil
        Apply.ApplyStackTextOffsets(icon, unit, shared, stackCountAnchor)

        if icon.count then
            if showStacks then
                local n = icon._msufA2_previewStackT or (((idx - 1) % 9) + 1)
                icon._msufA2_previewStackT = icon._msufA2_previewStackT or n
                icon.count:SetText(n)
                icon.count:Show()
            else
                icon.count:Hide()
            end
        end

        -- Cooldown swipe + countdown text
        local cd = icon.cooldown
        if cd then
            cd._msufA2_cdTextSize = nil
            cd._msufA2_cdFontPath = nil
            cd._msufA2_cdTextOffX = nil
            cd._msufA2_cdTextOffY = nil

            local dur = _PREVIEW_CD_DURATIONS[((idx - 1) % _PREVIEW_CD_DUR_N) + 1]
            -- Stagger start times so icons show different remaining times
            local elapsed = (idx * 2.7) % dur
            local startTime = now - elapsed

            if cd.SetHideCountdownNumbers then
                cd:SetHideCountdownNumbers(false)
            end
            if cd.SetCooldown then
                cd:SetCooldown(startTime, dur)
            end

            Apply.ApplyCooldownTextOffsets(icon, unit, shared)
        end
    end

    -- Buffs: show up to buffCap preview icons
    if entry.buffs and buffCap > 0 then
        for i = 1, buffCap do
            local icon = Icons.AcquireIcon(entry.buffs, i)
            if icon then
                SetupPreviewIcon(icon, i, "buff")
                buffCount = buffCount + 1
            end
        end
        Icons.HideUnused(entry.buffs, buffCount + 1)
    end

    -- Debuffs: show up to debuffCap preview icons
    if entry.debuffs and debuffCap > 0 then
        for i = 1, debuffCap do
            local icon = Icons.AcquireIcon(entry.debuffs, i)
            if icon then
                SetupPreviewIcon(icon, i, "debuff")
                debuffCount = debuffCount + 1
            end
        end
        Icons.HideUnused(entry.debuffs, debuffCount + 1)
    end

    entry._msufA2_previewActive = true
    return buffCount, debuffCount
end

function Icons.RenderPreviewPrivateIcons(entry, unit, shared, privIconSize, spacing, stackCountAnchor)
    -- Delegate to existing preview system
    local fn = API._Render and API._Render.RenderPreviewPrivateIcons
    if type(fn) == "function" then
        return fn(entry, unit, shared, privIconSize, spacing, stackCountAnchor)
    end

    -- Always show private aura previews in Edit Mode (no enabled-gate needed 
    -- this function is only called from the preview path). Use configured max
    -- counts so the user sees exactly how many slots they have allocated.
    local container = entry.private
    if not container then return end

    local maxN = 4
    if unit == "player" then
        maxN = (shared and shared.privateAuraMaxPlayer) or 4
    else
        maxN = (shared and shared.privateAuraMaxOther) or 4
    end
    if maxN <= 0 then maxN = 4 end -- always show at least a few in preview

    local gen = _configGen
    local now = GetTime()
    local showStacks = (shared and shared.showStackCount ~= false)
    local privCount = 0

    -- Sample private-aura-ish textures (shield/lock/eye themed)
    local privTex = { 136177, 134400, 135894, 136116, 135987, 136085,
                      132333, 135932, 136075, 135981, 136048, 132316 }
    local privTexN = #privTex

    for i = 1, maxN do
        local icon = Icons.AcquireIcon(container, i)
        if icon then
            icon._msufA2_isPreview = true
            icon._msufA2_previewKind = "private"
            icon._msufUnit = unit

            -- Aura texture (varied)
            if icon.tex then
                icon.tex:SetTexture(privTex[((i - 1) % privTexN) + 1])
            end
            icon:SetSize(privIconSize, privIconSize)

            --  Purple border to mark as "private aura" 
            if not icon._msufPrivateBorder then
                local border = icon:CreateTexture(nil, "OVERLAY", nil, 2)
                border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
                border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
                border:SetColorTexture(0.6, 0.2, 0.9, 0.0) -- start transparent
                icon._msufPrivateBorder = border
            end
            icon._msufPrivateBorder:SetColorTexture(0.6, 0.2, 0.9, 0.55)
            icon._msufPrivateBorder:Show()

            -- Small lock icon overlay (bottom-left corner)
            if not icon._msufPrivateLock then
                local lock = icon:CreateTexture(nil, "OVERLAY", nil, 3)
                lock:SetSize(math_max(10, privIconSize * 0.35), math_max(10, privIconSize * 0.35))
                lock:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 1, 1)
                lock:SetTexture(134400) -- padlock
                lock:SetDesaturated(false)
                icon._msufPrivateLock = lock
            end
            icon._msufPrivateLock:SetSize(math_max(10, privIconSize * 0.35), math_max(10, privIconSize * 0.35))
            icon._msufPrivateLock:Show()

            icon:Show()

            -- Position: horizontal row
            icon:ClearAllPoints()
            if i == 1 then
                icon:SetPoint("LEFT", container, "LEFT", 0, 0)
            else
                local prev = container._msufIcons and container._msufIcons[i - 1]
                if prev then
                    icon:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
                end
            end

            -- Text config
            icon._msufA2_textCfgGen = nil
            ResolveTextConfig(icon, unit, shared, gen)

            -- Stack text
            icon._msufA2_lastStackFontSize = nil
            icon._msufA2_lastStackFontPath = nil
            icon._msufA2_lastStackPointAnchor = nil
            Apply.ApplyStackTextOffsets(icon, unit, shared, stackCountAnchor)

            if icon.count then
                if showStacks then
                    local n = icon._msufA2_previewStackT or (((i - 1) % 5) + 1)
                    icon._msufA2_previewStackT = icon._msufA2_previewStackT or n
                    icon.count:SetText(n)
                    icon.count:Show()
                else
                    icon.count:Hide()
                end
            end

            -- Cooldown swipe + countdown text
            local cd = icon.cooldown
            if cd then
                cd._msufA2_cdTextSize = nil
                cd._msufA2_cdFontPath = nil
                cd._msufA2_cdTextOffX = nil
                cd._msufA2_cdTextOffY = nil

                local dur = _PREVIEW_CD_DURATIONS[((i - 1) % _PREVIEW_CD_DUR_N) + 1]
                local elapsed = (i * 3.1) % dur

                if cd.SetHideCountdownNumbers then
                    cd:SetHideCountdownNumbers(false)
                end
                if cd.SetCooldown then
                    cd:SetCooldown(now - elapsed, dur)
                end
                Apply.ApplyCooldownTextOffsets(icon, unit, shared)
            end

            privCount = privCount + 1
        end
    end
    Icons.HideUnused(container, privCount + 1)

    -- Size the container to wrap its children
    local step = privIconSize + spacing
    if step <= 0 then step = privIconSize + 2 end
    container:SetSize(math_max(1, (privCount * step) - spacing), math_max(1, privIconSize))
    container:Show()
end

-- --
-- Backward-compatible exports into API.Apply
-- (Options, CooldownText, Preview, Masque all reference API.Apply.*)
-- --

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
    -- Bump configGen so ResolveTextConfig cache is invalidated and new
    -- font values from shared.stackTextSize / cooldownTextSize take effect.
    _configGen = _configGen + 1
    _sharedFlagsGen = -1

    -- Resolve global MSUF font family (path + flags) and flush the file-scope cache
    -- so ApplyCooldownTextStyle / _ApplyStacks pick up the new font immediately.
    _globalFontPath = nil
    _globalFontFlags = "OUTLINE"
    local fontPath, fontFlags
    local getFontSettings = _G.MSUF_GetGlobalFontSettings
    if type(getFontSettings) == "function" then
        fontPath, fontFlags = getFontSettings()
    end
    if type(fontPath) ~= "string" then fontPath = nil end
    if type(fontFlags) ~= "string" then fontFlags = "OUTLINE" end
    -- Update file-scope cache
    _globalFontPath = fontPath
    _globalFontFlags = fontFlags

    -- Iterate all active icons and re-apply text settings + font family
    local state = API.state
    local aby = state and state.aurasByUnit
    if not aby then return end

    local a2, shared = GetAuras2DB()
    if type(shared) ~= "table" then return end

    -- Helper: apply font family + size to a FontString
    local function ApplyFontFamily(fs, wantSize)
        if not fs or not fs.SetFont or not fs.GetFont then return end
        local curFont, curSize, curFlags = fs:GetFont()
        local newFont = fontPath or curFont
        local newFlags = fontFlags or curFlags or "OUTLINE"
        local newSize = wantSize or curSize or 14
        if newFont then
            fs:SetFont(newFont, newSize, newFlags)
        end
    end

    -- Helper: refresh font on all icons in a container
    local function RefreshContainerFonts(container, unit, sca)
        if not container or not container._msufIcons then return end
        local pool = container._msufIcons
        local activeN = container._msufA2_activeN or #pool
        for i = 1, activeN do
            local icon = pool[i]
            if icon and icon:IsShown() then
                -- Resolve text config (sizes, offsets) for this configGen
                ResolveTextConfig(icon, unit, shared, _configGen)

                -- Apply font family to stack count text
                if icon.count then
                    ApplyFontFamily(icon.count, icon._msufA2_stackTextSize)
                end

                -- Apply font family to cooldown text
                local cd = icon.cooldown
                if cd then
                    -- Use the cached fontstring from CooldownText module
                    local cdFS = cd._msufCooldownFontString
                    if cdFS == false then cdFS = nil end
                    -- Fallback: try to discover via EnumerateRegions
                    if not cdFS and cd.EnumerateRegions then
                        for region in cd:EnumerateRegions() do
                            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                                cdFS = region
                                cd._msufCooldownFontString = region
                                break
                            end
                        end
                    end
                    if cdFS and cdFS.SetFont then
                        ApplyFontFamily(cdFS, icon._msufA2_cooldownTextSize)
                    end
                end
            end
        end
    end

    for _, entry in pairs(aby) do
        if entry then
            local unit = entry.unit
            local stackCountAnchor = shared.stackCountAnchor

            -- Respect per-unit stack anchor overrides
            local pu = a2 and a2.perUnit and unit and a2.perUnit[unit]
            if pu and pu.overrideSharedLayout == true and type(pu.layoutShared) == "table" then
                local v = pu.layoutShared.stackCountAnchor
                if type(v) == "string" then
                    stackCountAnchor = v
                end
            end

            -- Standard refresh (timer + stacks positioning)
            Icons.RefreshAssignedIcons(entry, unit, shared, stackCountAnchor)

            -- Font family refresh (the part that was missing)
            if fontPath then
                RefreshContainerFonts(entry.buffs, unit, stackCountAnchor)
                RefreshContainerFonts(entry.debuffs, unit, stackCountAnchor)
                RefreshContainerFonts(entry.mixed, unit, stackCountAnchor)
                RefreshContainerFonts(entry.private, unit, stackCountAnchor)
            end

            -- Also refresh preview icons (they lack _msufAuraInstanceID so
            -- RefreshAssignedIcons skips them)
            if entry._msufA2_previewActive then
                local gen = _configGen
                local function RefreshPreviewFonts(ctr)
                    if not ctr or not ctr._msufIcons then return end
                    for _, icon in ipairs(ctr._msufIcons) do
                        if icon and icon:IsShown() and icon._msufA2_isPreview then
                            ResolveTextConfig(icon, unit, shared, gen)
                            -- Stack count font
                            if icon.count and fontPath then
                                ApplyFontFamily(icon.count, icon._msufA2_stackTextSize)
                            end
                            -- Cooldown text font
                            if fontPath then
                                local cd = icon.cooldown
                                if cd then
                                    local cdFS = cd._msufCooldownFontString
                                    if cdFS == false then cdFS = nil end
                                    if not cdFS and cd.EnumerateRegions then
                                        for region in cd:EnumerateRegions() do
                                            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                                                cdFS = region
                                                cd._msufCooldownFontString = region
                                                break
                                            end
                                        end
                                    end
                                    if cdFS and cdFS.SetFont then
                                        ApplyFontFamily(cdFS, icon._msufA2_cooldownTextSize)
                                    end
                                end
                            end
                        end
                    end
                end
                RefreshPreviewFonts(entry.buffs)
                RefreshPreviewFonts(entry.debuffs)
                RefreshPreviewFonts(entry.private)
            end
        end
    end
end

-- Text offset stubs (Edit Mode references)

function Apply.ApplyStackCountAnchorStyle(icon, stackCountAnchor)
    local countFS = icon and icon.count
    if not countFS then return end

    local anchor = stackCountAnchor or "TOPRIGHT"
    -- Always apply (Preview-only; force-invalidate)
    icon._msufA2_lastStackJustifyAnchor = anchor

    if anchor == "TOPLEFT" or anchor == "BOTTOMLEFT" then
        countFS:SetJustifyH("LEFT")
    else
        countFS:SetJustifyH("RIGHT")
    end
    if anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT" then
        countFS:SetJustifyV("BOTTOM")
    else
        countFS:SetJustifyV("TOP")
    end
end

function Apply.ApplyStackTextOffsets(icon, unit, shared, stackCountAnchor)
    local countFS = icon and icon.count
    if not countFS then return end

    -- Force-invalidate text config cache so ResolveTextConfig re-reads DB.
    -- This function is Preview-only (ticker + RenderPreviewIcons), so the
    -- unconditional invalidation has zero cost on live aura hot paths.
    icon._msufA2_textCfgGen = nil
    ResolveTextConfig(icon, unit, shared, _configGen)

    -- Font family + size (always re-apply: Preview-only)
    local wantSize = icon._msufA2_stackTextSize or 14
    if countFS.GetFont and countFS.SetFont then
        local gFont, gFlags = ResolveGlobalFont()
        local curFont, _, curFlags = countFS:GetFont()
        local wantFont = gFont or curFont
        local wantFlags = gFlags or curFlags or "OUTLINE"
        if wantFont then
            countFS:SetFont(wantFont, wantSize, wantFlags)
        end
    end
    icon._msufA2_lastStackFontSize = wantSize

    -- Anchor style + offsets (always re-apply: clear diff cache)
    local anchor = stackCountAnchor or "TOPRIGHT"
    icon._msufA2_lastStackJustifyAnchor = nil
    Apply.ApplyStackCountAnchorStyle(icon, anchor)

    local offX = icon._msufA2_stackTextOffsetX or 0
    local offY = icon._msufA2_stackTextOffsetY or 0
    icon._msufA2_lastStackPointAnchor = nil
    icon._msufA2_lastStackPointX = nil
    icon._msufA2_lastStackPointY = nil

    countFS:ClearAllPoints()
    if anchor == "TOPLEFT" then
        countFS:SetPoint("TOPLEFT", icon, "TOPLEFT", offX, offY)
    elseif anchor == "BOTTOMLEFT" then
        countFS:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", offX, offY)
    elseif anchor == "BOTTOMRIGHT" then
        countFS:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", offX, offY)
    else
        countFS:SetPoint("TOPRIGHT", icon, "TOPRIGHT", offX, offY)
    end
end

function Apply.ApplyCooldownTextOffsets(icon, unit, shared)
    local cd = icon and icon.cooldown
    if not cd then return end

    -- Force-invalidate text config cache (Preview-only function).
    icon._msufA2_textCfgGen = nil
    ResolveTextConfig(icon, unit, shared, _configGen)

    -- Force-invalidate cooldown diff caches so new values always apply
    cd._msufA2_cdTextSize = nil
    cd._msufA2_cdFontPath = nil
    cd._msufA2_cdTextOffX = nil
    cd._msufA2_cdTextOffY = nil

    -- Ensure fontstring is discovered (safe: uses cached retry logic in cooldown module)
    CT = CT or API.CooldownText
    local getfs = CT and CT.GetCooldownFontString
    if type(getfs) ~= "function" then return end

    local now = GetTime()
    ApplyCooldownTextStyle(icon, cd, now, true)
end

API.ApplyFontsFromGlobal = Apply.ApplyFontsFromGlobal

-- Global wrapper (referenced by MidnightSimpleUnitFrames.lua)
if type(_G.MSUF_Auras2_ApplyFontsFromGlobal) ~= "function" then
    _G.MSUF_Auras2_ApplyFontsFromGlobal = function() return Apply.ApplyFontsFromGlobal() end
end
