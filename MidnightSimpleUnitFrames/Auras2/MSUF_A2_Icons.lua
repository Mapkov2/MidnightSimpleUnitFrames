-- MSUF_A2_Icons.lua

-- MSUF_A2_Icons.lua  Auras 3.0 Icon Factory + Visual Commit + Layout
-- Replaces the core of MSUF_A2_Apply.lua
-- Responsibilities:
--   1. Icon pool (AcquireIcon / HideUnused)
--   2. Visual commit (CommitIcon  texture, cooldown, stacks, border)
--   3. Grid layout (LayoutIcons)
--   4. Refresh helpers (RefreshAssignedIcons)
-- Secret-safe: uses Collect.GetDurationObject() for timers,
-- Collect.GetStackCount() for stacks, never reads secret fields.

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
-- PERF LOCALS (Auras2 runtime)
local type, tostring = type, tostring
local pairs, ipairs, next = pairs, ipairs, next
local math_max = math.max
local CreateFrame, GetTime = CreateFrame, GetTime
local C_UnitAuras = C_UnitAuras
local C_CurveUtil = C_CurveUtil
ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

API.Icons = (type(API.Icons) == "table") and API.Icons or {}
local Icons = API.Icons

-- Also register as API.Apply for backward compatibility
API.Apply = (type(API.Apply) == "table") and API.Apply or {}
local Apply = API.Apply

-- Hot locals
local GameTooltip = GameTooltip
local floor = math.floor
local max = math_max
local C_Timer = C_Timer

-- Secret value detector (Midnight/Beta)
local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue
local _hasCanaccessvalue = (type(canaccessvalue) == "function")

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
-- PERF: Direct C API refs for inlined CommitIcon path (skip wrapper function calls)
local _getDurationDirect   -- C_UnitAuras.GetAuraDuration
local _getStackCountDirect -- C_UnitAuras.GetAuraApplicationDisplayCount
local _getByAidDirect      -- C_UnitAuras.GetAuraDataByAuraInstanceID (numeric timer fallback)
local _fastPathBound = false

local function BindFastPaths()
    if _fastPathBound then return end
    if not Collect then return end
    _getDurationFast   = Collect.GetDurationObjectFast or Collect.GetDurationObject
    _getStackCountFast = Collect.GetStackCountFast or Collect.GetStackCount
    _hasExpirationFast = Collect.HasExpirationFast or Collect.HasExpiration
    -- Direct C API for inlined hot path
    local CUA = _G.C_UnitAuras
    if CUA then
        _getDurationDirect   = CUA.GetAuraDuration
        _getStackCountDirect = CUA.GetAuraApplicationDisplayCount
        _getByAidDirect      = CUA.GetAuraDataByAuraInstanceID
    end
    _fastPathBound = true
end

local function ReadAccessibleNumber(v)
    if v == nil then return nil end
    if _hasCanaccessvalue then
        if canaccessvalue(v) ~= true then return nil end
    elseif issecretvalue and issecretvalue(v) == true then
        return nil
    end
    return tonumber(v)
end

local function ApplyNumericCooldownFallback(icon, cd, unit, aid, aura, durationValue)
    if not icon or not cd or not cd.SetCooldown then return false end

    local data
    if _getByAidDirect and unit and aid then
        data = _getByAidDirect(unit, aid)
    end
    if type(data) ~= "table" then
        data = aura
    end
    if type(data) ~= "table" then return false end

    local duration = ReadAccessibleNumber(durationValue)
    if not duration then
        duration = ReadAccessibleNumber(data.duration)
    end
    local expiration = ReadAccessibleNumber(data.expirationTime)
    if not duration or not expiration or duration <= 0 or expiration <= 0 then
        return false
    end

    local remaining = expiration - GetTime()
    if remaining <= 0 then
        return false
    end

    cd:SetCooldown(expiration - duration, duration)
    icon._msufA2_durationObj = nil
    cd._msufA2_durationObj = nil
    icon._msufA2_cdNumericFallback = true
    return true
end

-- Phase 8: file-scope locals for Icons._ methods (eliminates hash-table
-- lookup per icon in tight loops).  Assigned after method definitions.
local _fast_ApplyTimer
local _fast_RefreshTimer
local _fast_ApplyStacks
local _fast_ApplyOwnHighlight
local _fast_ApplyDispelBorder
local _fast_ApplyPandemic
local _RefreshDynamicIfNeeded

--  Cached shared.* flags (resolve once per configGen, not per icon)
local _sharedFlagsGen   = -1
local _showSwipe        = false
local _showText         = true
local _swipeReverse     = false
local _showStacks       = false
local _IS_BOSS = { boss1=true, boss2=true, boss3=true, boss4=true, boss5=true }
local _wantBuffHL       = false
local _wantDebuffHL     = false
local _useBlizzardTimer = true   -- PERF C++ DELEGATION: Blizzard native countdown text (default)
local _useDispelBorders = false  -- dispel-type border coloring for debuffs
local _clickThrough     = false  -- true = all auras non-interactive (mouse pass-through)
local _showTooltip      = true   -- cached shared.showTooltip (for click-through + tooltip combo)
local _masqueEnabled    = false  -- cached shared.masqueEnabled (gates per-icon backdrop call)
local _showPandemic     = false  -- pandemic window active (any mode except OFF)
local _pandemicMode     = 0      -- 0=OFF 1=BORDER 2=PULSE 3=GLOW
local _panR, _panG, _panB = 0.0, 0.4, 1.0  -- cached pandemic color

--  Debuff dispel-type color lookup (Ã‚Â  la R41z0r / Blizzard)
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

-- Pandemic window step-curve: returns 1 when ≤30% remaining, 0 otherwise.
-- Secret-safe: EvaluateRemainingPercent + IsZero, zero value comparisons.
local _pandemicCurve
local _pandemicEvalBool  -- C_CurveUtil.EvaluateColorValueFromBoolean
do
    if C_CurveUtil and C_CurveUtil.CreateCurve
       and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then
        local ok2, curve2 = pcall(function()
            local c = C_CurveUtil.CreateCurve()
            c:SetType(Enum.LuaCurveType.Step)
            c:AddPoint(0, 1)    -- 0-30% remaining → 1 (in pandemic window)
            c:AddPoint(0.3, 0)  -- 30%+ remaining  → 0
            return c
        end)
        if ok2 and curve2 then _pandemicCurve = curve2 end
    end
    _pandemicEvalBool = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean or nil
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

local function ResolveGlobalFontKey()
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    return (g and g.fontKey) or "FRIZQT"
end

local function RefreshSharedFlags(shared, gen)
    if not shared then return end
    if _sharedFlagsGen == gen then return end
    _sharedFlagsGen = gen
    _showSwipe    = (shared and shared.showCooldownSwipe == true) or false
    _showText     = (shared and shared.showCooldownText ~= false) -- default true
    _swipeReverse = (shared and shared.cooldownSwipeDarkenOnLoss == true) or false
    _showStacks   = (shared and shared.showStackCount ~= false) -- default true
    _wantBuffHL   = (shared and shared.highlightOwnBuffs == true) or false
    _wantDebuffHL = (shared and shared.highlightOwnDebuffs == true) or false
    -- PERF C++ DELEGATION: Default to Blizzard native countdown text.
    -- Only fall back to Lua CooldownText manager if user explicitly disables it.
    _useBlizzardTimer = not (shared and shared.useBlizzardTimerText == false)
    _useDispelBorders = (shared and shared.useDebuffTypeBorders == true) or false
    _clickThrough     = (shared and shared.clickThroughAuras == true) or false
    _showTooltip      = (shared and shared.showTooltip == true) or false
    _G.MSUF_A2_ClickThrough = _clickThrough
    _G.MSUF_A2_ShowTooltip  = _showTooltip
    _masqueEnabled    = (shared and shared.masqueEnabled == true) or false
    -- Pandemic mode: "OFF"/"BORDER"/"PULSE"/"GLOW" → numeric (0/1/2/3)
    -- Migration: old boolean showPandemic=true → PULSE
    do
        local pm = shared and shared.pandemicMode
        if pm == nil and shared then pm = shared.showPandemic end -- migration
        if pm == true then pm = "PULSE" end
        if pm == "BORDER" then _pandemicMode = 1
        elseif pm == "PULSE" then _pandemicMode = 2
        elseif pm == "GLOW" then _pandemicMode = 3
        else _pandemicMode = 0
        end
        _showPandemic = (_pandemicMode > 0) and (_pandemicCurve ~= nil)
        -- Start/stop pandemic ticker based on feature state (zero idle overhead when off)
        if _showPandemic then
            if API._StartPandemicTicker then API._StartPandemicTicker() end
        else
            if API._StopPandemicTicker then API._StopPandemicTicker() end
        end
        -- Cache color
        local pr = shared and shared.pandemicR; if type(pr) == "number" then _panR = pr end
        local pg = shared and shared.pandemicG; if type(pg) == "number" then _panG = pg end
        local pb = shared and shared.pandemicB; if type(pb) == "number" then _panB = pb end
    end
end

-- Masque backdrop compatibility
-- When Masque skins are used (often non-square shapes like circles), MSUF's
-- subtle background texture can remain visible as a square "box" behind the
-- skinned icon. This can also appear intermittently due to icon reuse.
-- Fix: diff-gated show/hide of the background texture whenever Masque is
-- enabled and the icon has been registered with Masque.

local function ApplyMasqueBackdrop(icon, shared)
    local bg = icon and icon._msufBG
    if not bg then return end

    local hide = (shared and shared.masqueEnabled == true and icon.MSUF_MasqueAdded == true) or false
    if icon._msufA2_bgHidden ~= hide then
        icon._msufA2_bgHidden = hide
        if hide then
            bg:Hide()
        else
            bg:Show()
        end
    end
end

-- Text config resolution (per-icon; cached by configGen)
-- Applies stack/cooldown text sizes + offsets from shared + per-unit layout
-- Zero per-frame cost: runs only when configGen changes.

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
    local api = ns and ns.MSUF_Auras2
    if api and api.GetDB then return api.GetDB() end
    if not _G.MSUF_DB then
        local ensureDB = _G.MSUF_EnsureDB
        if type(ensureDB) == "function" then ensureDB() end
    end
    local a2 = _G.MSUF_DB and _G.MSUF_DB.auras2
    return a2, a2 and a2.shared
end

-- Color helpers (late-bound from API.Colors or fallback)

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

-- Icon Pool

-- Icons are stored on container._msufIcons[index]
-- Each icon is a Button with: .tex, .cooldown, .count, .border, .overlay

local function HideButtonStateTexture(texture)
    if not texture then return end
    if texture.SetAlpha then texture:SetAlpha(0) end
    if texture.Hide then texture:Hide() end
end

local function SuppressAuraButtonState(icon)
    if not icon then return end
    if icon.SetButtonState then icon:SetButtonState("NORMAL", false) end
    if icon.UnlockHighlight then icon:UnlockHighlight() end
    HideButtonStateTexture(icon.GetHighlightTexture and icon:GetHighlightTexture())
    HideButtonStateTexture(icon.GetPushedTexture and icon:GetPushedTexture())
    HideButtonStateTexture(icon.GetCheckedTexture and icon:GetCheckedTexture())
end

local function RestoreAuraButtonGeometry(icon, expectedSize, expectedScale)
    if not icon then return end

    expectedSize = tonumber(expectedSize) or tonumber(icon._msufA2_lastSize)
    if expectedSize and expectedSize > 0 and icon.SetSize then
        local w = icon.GetWidth and icon:GetWidth()
        local h = icon.GetHeight and icon:GetHeight()
        if w ~= expectedSize or h ~= expectedSize then
            icon._msufA2_restoringGeometry = true
            icon:SetSize(expectedSize, expectedSize)
            icon._msufA2_restoringGeometry = nil
        end
    end

    expectedScale = tonumber(expectedScale) or tonumber(icon._msufA2_baseScale)
    if expectedScale and expectedScale > 0 and icon.SetScale and icon.GetScale then
        local scale = icon:GetScale()
        if scale ~= expectedScale then
            icon:SetScale(expectedScale)
        end
    end

    SuppressAuraButtonState(icon)
end

local function RestoreAuraButtonGeometrySoon(icon, expectedSize, expectedScale)
    RestoreAuraButtonGeometry(icon, expectedSize, expectedScale)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if icon and icon._msufA2_hovering then
                RestoreAuraButtonGeometry(icon, expectedSize, expectedScale)
            end
        end)
    end
end

-- Mouse interaction state helper (safe on 12.0+)
-- 0 = normal (hover + clicks)
-- 1 = tooltip only (hover on, clicks off)
-- 2 = full click-through (hover off, clicks off)
local function ApplyMouseState(icon, wantMS)
    if not icon then return end
    if icon._msufA2_mouseState == wantMS then return end
    icon._msufA2_mouseState = wantMS

    local wantHover = (wantMS ~= 2)
    local wantClicks = (wantMS == 0)

    if icon.SetMouseMotionEnabled then
        icon:SetMouseMotionEnabled(wantHover)
    end
    if icon.SetMouseClickEnabled then
        icon:SetMouseClickEnabled(wantClicks)
    end

    -- Backward-compatible fallback for older clients/widgets without the split API.
    if (not icon.SetMouseMotionEnabled) or (not icon.SetMouseClickEnabled) then
        icon:EnableMouse(wantHover or wantClicks)
        if icon.RegisterForClicks then
            if wantClicks then
                icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            else
                icon:RegisterForClicks()
            end
        end
    end
end

-- Export for MSUF_A2_EditMode.lua (file-scope locals are invisible across files)
_G.MSUF_A2_ApplyMouseState = ApplyMouseState
_G.MSUF_A2_ResolveTextConfig = ResolveTextConfig

local function CreateIcon(container, index)
    local icon = CreateFrame("Button", nil, container)
    icon:SetSize(26, 26)
    icon._msufA2_baseScale = (icon.GetScale and icon:GetScale()) or 1

    -- Stack count overlay frame (keeps stacks above Masque/borders)
    local countFrame = CreateFrame("Frame", nil, icon)
    countFrame:SetAllPoints(icon)
    countFrame:SetFrameLevel(icon:GetFrameLevel() + 10)
    icon.countFrame = countFrame

    ApplyMouseState(icon, 0)
    SuppressAuraButtonState(icon)
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
    cd._msufA2_lastHideNumbers = true
    cd._msufA2_lastUseAuraDisplayTime = false
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
    if type(_G.MSUF_SetFontSafe) == "function" then
        _G.MSUF_SetFontSafe(count, _initFont, 14, _initFlags, ResolveGlobalFontKey())
    else
        count:SetFont(_initFont, 14, _initFlags)
    end
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

    -- Pandemic window border/glow (hidden by default)
    -- Architecture: outer frame (alpha gate via SetAlpha(secret)) × inner child (visuals + animation).
    -- Modes: BORDER (static border), PULSE (border + glow + throb), GLOW (soft glow + throb).
    do
        -- Outer: alpha gate (receives secret curve result)
        local pf = CreateFrame("Frame", nil, icon)
        pf:SetAllPoints(icon)
        pf:SetFrameLevel(icon:GetFrameLevel() + 8)
        pf:SetAlpha(0)
        -- Inner: holds textures + animation
        local inner = CreateFrame("Frame", nil, pf)
        inner:SetAllPoints(pf)
        -- Border texture (Blizzard debuff overlay, bright green)
        local pt = inner:CreateTexture(nil, "OVERLAY", nil, 7)
        pt:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
        pt:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
        pt:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
        pt:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
        pt:SetVertexColor(0.0, 0.4, 1.0, 1)
        -- Soft outer glow (color texture, larger inset)
        local pg = inner:CreateTexture(nil, "OVERLAY", nil, 6)
        pg:SetPoint("TOPLEFT", icon, "TOPLEFT", -3, 3)
        pg:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 3, -3)
        pg:SetColorTexture(0.0, 0.4, 1.0, 0.35)
        -- Alpha pulse animation on inner
        local ag = inner:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local pulse = ag:CreateAnimation("Alpha")
        pulse:SetFromAlpha(0.35)
        pulse:SetToAlpha(1.0)
        pulse:SetDuration(0.4)
        pulse:SetSmoothing("IN_OUT")
        -- Store refs for per-mode reconfiguration
        pf._border = pt
        pf._glow   = pg
        pf._anim   = ag
        pf._inner  = inner
        pf:Hide()
        icon._msufPandemic = pf
        icon._msufPanLastMode = 0  -- tracks applied mode for diff-gate
    end

    -- Background (subtle dark backdrop)
    local bg = icon:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    icon._msufBG = bg

    -- Tooltip support
    icon:SetScript("OnEnter", function(self)
        self._msufA2_hovering = true
        local expectedSize = self._msufA2_lastSize or (self.GetWidth and self:GetWidth()) or 26
        local expectedScale = (self.GetScale and self:GetScale()) or self._msufA2_baseScale or 1
        local _, shared = GetAuras2DB()
        if shared and shared.showTooltip ~= true then
            RestoreAuraButtonGeometrySoon(self, expectedSize, expectedScale)
            return
        end
        local unit = self._msufUnit
        local aid = self._msufAuraInstanceID
        if not unit or not aid then
            RestoreAuraButtonGeometrySoon(self, expectedSize, expectedScale)
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        -- Secret-safe: SetUnitAuraByAuraInstanceID handles secrets internally
        if self._msufFilter == "HARMFUL" and GameTooltip.SetUnitDebuffByAuraInstanceID then
            GameTooltip:SetUnitDebuffByAuraInstanceID(unit, aid)
        elseif GameTooltip.SetUnitBuffByAuraInstanceID then
            GameTooltip:SetUnitBuffByAuraInstanceID(unit, aid)
        elseif GameTooltip.SetUnitAuraByAuraInstanceID then
            GameTooltip:SetUnitAuraByAuraInstanceID(unit, aid, self._msufFilter or "HELPFUL")
        end
        GameTooltip:Show()
        RestoreAuraButtonGeometrySoon(self, expectedSize, expectedScale)
    end)

    icon:SetScript("OnLeave", function(self)
        self._msufA2_hovering = nil
        if GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
        RestoreAuraButtonGeometry(self)
    end)
    icon:HookScript("OnSizeChanged", function(self, width, height)
        if self._msufA2_restoringGeometry or self._msufA2_hovering ~= true then return end
        local expectedSize = tonumber(self._msufA2_lastSize)
        if expectedSize and expectedSize > 0 and (width ~= expectedSize or height ~= expectedSize) then
            RestoreAuraButtonGeometrySoon(self, expectedSize, self._msufA2_baseScale)
        end
    end)

    -- Masque integration (MSA pattern: register button, regions built in AddButton)
    EnsureBindings()
    local _, shared = GetAuras2DB()
    if Masque and Masque.IsEnabled and Masque.IsEnabled(shared) and Masque.AddButton then
        if Masque.AddButton(icon, shared) then
            icon.MSUF_MasqueAdded = true
        end
    end
    RestoreAuraButtonGeometry(icon, icon._msufA2_lastSize or icon:GetWidth(), icon._msufA2_baseScale)

    return icon
end

local ClearCooldownVisual

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
                if ClearCooldownVisual and icon.cooldown then
                    ClearCooldownVisual(icon, icon.cooldown)
                end
                icon:Hide()
                local aid = icon._msufAuraInstanceID
                if aid and map and map[aid] == icon then
                    map[aid] = nil
                end
                icon._msufAuraInstanceID = nil
                icon._msufAura = nil
                -- Bug 1 fix: Clear stale commit + texture cache so recycled
                -- icons always do a full CommitIcon on next AcquireIcon.
                -- PERF: Reuse the lastCommit table (avoid ~96B alloc on recycle).
                -- Clearing .aid forces full re-apply in CommitIcon's diff gate.
                local lc = icon._msufA2_lastCommit
                if lc then lc.aid = nil end
                icon._msufA2_lastTexAid = nil
                icon._msufA2_timerRev = nil
                icon._msufA2_dynRev = nil
                icon._msufA2_dynGen = nil
                icon._msufA2_dynAnchor = nil
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
_G.MSUF_A2_ConfigGen = _configGen
local _bindingsDone = false

function Icons.BumpConfigGen()
    _configGen = _configGen + 1
    _G.MSUF_A2_ConfigGen = _configGen
    _bindingsDone = false  -- re-bind on next commit (picks up late-loaded modules)
    _fastPathBound = false -- re-bind fast paths
    _sharedFlagsGen = -1   -- force shared flags refresh
end

-- Visual Commit (CommitIcon)
-- This is the ONLY function that touches icon visuals.
-- Called once per icon per render. Uses diff gating on
-- auraInstanceID + config generation to skip redundant work.

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

    -- PERF: Inlined ApplyMasqueBackdrop (was separate function call per icon)
    if _masqueEnabled then
        local bg = icon._msufBG
        if bg then
            local hide = (shared and shared.masqueEnabled == true and icon.MSUF_MasqueAdded == true) or false
            if icon._msufA2_bgHidden ~= hide then
                icon._msufA2_bgHidden = hide
                if hide then bg:Hide() else bg:Show() end
            end
        end
    end

    if not aura then
        local container = icon._msufA2_container or icon:GetParent()
        local aidMap = container and container._msufA2_iconByAid
        local prevAid = icon._msufAuraInstanceID
        if prevAid and aidMap and aidMap[prevAid] == icon then
            aidMap[prevAid] = nil
        end
        icon._msufAuraInstanceID = nil
        icon._msufA2_lastOwnHelpful = nil
        icon._msufA2_lastDispelAid = nil
        icon._msufA2_forceOwnBuffHighlight = nil
        icon._msufA2_dynRev = nil
        icon._msufA2_dynGen = nil
        icon._msufA2_dynAnchor = nil
        if icon._msufDispelBorder then icon._msufDispelBorder:Hide() end
        if icon._msufPandemic then icon._msufPandemic:Hide() end
        return false
    end

    local aid = aura._msufAuraInstanceID or aura.auraInstanceID
    local forceOwnBuffHighlight = (aura._msufA2_forceBossHealHighlight == true)

    --  Fast-path diff gate: same aura, same config Ã¢â€ â€™ skip all bookkeeping
    local last = icon._msufA2_lastCommit
    if last
        and last.aid == aid
        and last.gen == gen
        and last.isOwn == isOwn
        and last.forceOwnBuffHighlight == forceOwnBuffHighlight
    then
        -- Same aura, same config. Only refresh timer + stacks (values may have changed).
        -- Timer/stacks refresh only when the aura cache revision changes. The
        -- revision is our own plain value, so this avoids secret-value compares
        -- while still updating on real UNIT_AURA deltas.
        icon._msufAura = aura
        if _RefreshDynamicIfNeeded then
            _RefreshDynamicIfNeeded(icon, unit, aid, shared, stackCountAnchor, aura, gen)
        else
            _fast_RefreshTimer(icon, unit, aid, shared, aura)
            _fast_ApplyStacks(icon, unit, aid, shared, stackCountAnchor, aura)
        end
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
        icon._msufA2_lastOwnHelpful = nil
        icon._msufA2_lastDispelAid = nil
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
    last.forceOwnBuffHighlight = forceOwnBuffHighlight
    icon._msufA2_forceOwnBuffHighlight = forceOwnBuffHighlight

    -- PERF: Inline gen-check to skip function call overhead
    if icon._msufA2_textCfgGen ~= gen then
        ResolveTextConfig(icon, unit, shared, gen)
    end

    -- 1. Texture (update when aid changed)
    -- SECRET-SAFE: aura.icon CAN be a secret value in WoW 12.0.
    -- Never compare, store, or nil-check it. MSUF_SetIconTexture resolves
    -- accessible FileDataIDs to Interface\Icons paths and passes secrets through.
    if icon._msufA2_lastTexAid ~= aid then
        icon._msufA2_lastTexAid = aid
        if icon.tex then
            if type(_G.MSUF_SetIconTexture) == "function" then
                _G.MSUF_SetIconTexture(icon.tex, aura.icon, "")
            else
                icon.tex:SetTexture(aura.icon)
            end
        end
    end

    -- 2. Cooldown / Timer
    _fast_ApplyTimer(icon, unit, aid, shared, aura)

    -- 3. Stack count
    _fast_ApplyStacks(icon, unit, aid, shared, stackCountAnchor, aura)
    icon._msufA2_dynRev = aura and aura._msufA2_updateRev or nil
    icon._msufA2_dynGen = gen
    icon._msufA2_dynAnchor = stackCountAnchor or "TOPRIGHT"

    -- 4. Own-aura highlight (same effective state rarely changes across full commits)
    local ownHelpfulKey = ((isOwn and 1) or 0) * 4
        + ((isHelpful and 1) or 0) * 2
        + ((forceOwnBuffHighlight and 1) or 0)
    if icon._msufA2_lastOwnHelpful ~= ownHelpfulKey then
        icon._msufA2_lastOwnHelpful = ownHelpfulKey
        _fast_ApplyOwnHighlight(icon, isOwn, isHelpful, shared)
    end

    -- 5. Dispel-type border (Magic/Curse/Poison/Disease colored)
    if icon._msufA2_lastDispelAid ~= aid then
        icon._msufA2_lastDispelAid = aid
        _fast_ApplyDispelBorder(icon, unit, aura, isHelpful)
    end

    -- 6. Pandemic window pulsing border (secret-safe curve → Show/Hide)
    if _showPandemic then _fast_ApplyPandemic(icon) end

    -- 7. Click-through + tooltip interaction (3-state, diff-gated)
    -- 0 = normal (mouse on, no pass-through)
    -- 1 = click-through but tooltips on (mouse on, all buttons pass-through)
    -- 2 = full click-through (mouse off — no hover, no clicks)
    local wantMS = _clickThrough and (_showTooltip and 1 or 2) or 0
    ApplyMouseState(icon, wantMS)

    icon:Show()
    return true
end

-- Timer application (cooldown swipe + text)
-- Uses duration objects (secret-safe pass-through)

function ClearCooldownVisual(icon, cd)
    if not icon or not cd then return end

    -- Unregister from the cooldown text manager to prevent stale updates.
    CT = CT or (API and API.CooldownText)
    if CT and CT.UnregisterIcon then
        CT.UnregisterIcon(icon)
    end

    -- Clear swipe/timer state (works across template variants).
    if cd.Clear then cd:Clear() end
    if cd.SetCooldown then cd:SetCooldown(0, 0) end
    if cd.SetUseAuraDisplayTime then
        cd._msufA2_lastUseAuraDisplayTime = false
        cd:SetUseAuraDisplayTime(false)
    end

    -- Force-hide countdown numbers when no timer is present (prevents stale text).
    if cd.SetHideCountdownNumbers then
        cd._msufA2_lastHideNumbers = true
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
    icon._msufA2_lastCdDurationObj = nil
    icon._msufA2_lastCdAid = nil
    icon._msufA2_lastCdShown = false
    icon._msufA2_timerRev = nil

    -- Pandemic: immediately hide pulsing border when timer clears.
    local pan = icon._msufPandemic
    if pan and pan:IsShown() then pan:SetAlpha(0); pan:Hide() end
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
                if type(_G.MSUF_SetFontSafe) == "function" then
                    _G.MSUF_SetFontSafe(fs, wantFont, size, wantFlags, ResolveGlobalFontKey())
                else
                    fs:SetFont(wantFont, size, wantFlags)
                end
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

    local auraRev = aura and aura._msufA2_updateRev
    if auraRev and icon._msufA2_timerRev ~= auraRev then
        if icon._msufA2_lastHadTimer == true or cd._msufA2_durationObj ~= nil or icon._msufA2_cdNumericFallback == true then
            ClearCooldownVisual(icon, cd)
        end
        icon._msufA2_timerRev = auraRev
    end

    local hadTimer = false

    -- PERF: Inline GetDurationObjectFast — direct C API call, skip wrapper
    local obj
    local numericDuration
    if _getDurationDirect then
        obj = _getDurationDirect(unit, aid)
        if obj ~= nil and type(obj) == "number" then
            numericDuration = obj
            obj = nil
        end
    end

    local hadDurationObject = false
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
            hadDurationObject = true
        end

        icon._msufA2_durationObj = obj
        cd._msufA2_durationObj = obj
        icon._msufA2_cdNumericFallback = nil
    elseif ApplyNumericCooldownFallback(icon, cd, unit, aid, aura, numericDuration) then
        hadTimer = true
    end

    -- Pass-through: tell Blizzard CooldownFrame to render aura timer natively in C++.
    local wantAuraDisplayTime = (_useBlizzardTimer == true and hadDurationObject == true)
    if cd.SetUseAuraDisplayTime and cd._msufA2_lastUseAuraDisplayTime ~= wantAuraDisplayTime then
        cd._msufA2_lastUseAuraDisplayTime = wantAuraDisplayTime
        cd:SetUseAuraDisplayTime(wantAuraDisplayTime)
    end

    -- PERF: Diff-gate cooldown visual flags (avoid redundant C-API calls per icon).
    if cd._msufA2_lastSwipe ~= _showSwipe then
        cd._msufA2_lastSwipe = _showSwipe
        cd:SetDrawSwipe(_showSwipe)
    end
    if cd._msufA2_lastReverse ~= _swipeReverse then
        cd._msufA2_lastReverse = _swipeReverse
        cd:SetReverse(_swipeReverse)
    end
    if hadTimer then
        local wantHide = (not _showText) or (icon._msufA2_hideCDNumbers == true)
        if cd._msufA2_lastHideNumbers ~= wantHide or icon._msufA2_lastHadTimer ~= true then
            cd._msufA2_lastHideNumbers = wantHide
            cd:SetHideCountdownNumbers(wantHide)
        end
    else
        ClearCooldownVisual(icon, cd)
    end

    -- Cooldown text manager only recolors the existing Cooldown FontString.
    -- This also works in Blizzard-native timer mode: Blizzard owns the text,
    -- MSUF only applies Safe/Warning/Urgent colors from the Colors menu.
    CT = CT or API.CooldownText
    local wantText = _showText and (icon._msufA2_hideCDNumbers ~= true)
    if CT then
        if wantText and hadTimer then
            local wasRegistered = (icon._msufA2_cdMgrRegistered == true)
            if (not wasRegistered) and CT.RegisterIcon then
                CT.RegisterIcon(icon)
                wasRegistered = (icon._msufA2_cdMgrRegistered == true)
            end

            local objChanged = (icon._msufA2_lastCdDurationObj ~= obj)
            local aidChanged = (icon._msufA2_lastCdAid ~= aid)
            local textStateChanged = (icon._msufA2_lastCdWantText ~= true)
            local shownChanged = (icon._msufA2_lastCdShown ~= true)

            if wasRegistered and CT.TouchIcon and (objChanged or aidChanged or textStateChanged or shownChanged) then
                CT.TouchIcon(icon)
            end

            icon._msufA2_lastCdDurationObj = obj
            icon._msufA2_lastCdAid = aid
            icon._msufA2_lastCdWantText = true
            icon._msufA2_lastCdShown = true
        else
            icon._msufA2_lastCdWantText = false
            icon._msufA2_lastCdShown = false
            icon._msufA2_lastCdDurationObj = nil
            icon._msufA2_lastCdAid = nil
            if CT.UnregisterIcon then
                CT.UnregisterIcon(icon)
            end
        end
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

    local auraRev = aura and aura._msufA2_updateRev
    if auraRev and icon._msufA2_timerRev ~= auraRev then
        if icon._msufA2_lastHadTimer == true or cd._msufA2_durationObj ~= nil or icon._msufA2_cdNumericFallback == true then
            ClearCooldownVisual(icon, cd)
        end
        icon._msufA2_timerRev = auraRev
    end

    -- PERF: Inline GetDurationObjectFast — direct C API call, skip wrapper
    local obj
    local numericDuration
    if _getDurationDirect then
        obj = _getDurationDirect(unit, aid)
        if obj ~= nil and type(obj) == "number" then
            numericDuration = obj
            obj = nil
        end
    end

    if not obj then
        if ApplyNumericCooldownFallback(icon, cd, unit, aid, aura, numericDuration) then
            local wasTimerActive = (icon._msufA2_lastHadTimer == true)
            icon._msufA2_lastHadTimer = true

            if cd.SetUseAuraDisplayTime and cd._msufA2_lastUseAuraDisplayTime ~= false then
                cd._msufA2_lastUseAuraDisplayTime = false
                cd:SetUseAuraDisplayTime(false)
            end
            if cd._msufA2_lastSwipe ~= _showSwipe then
                cd._msufA2_lastSwipe = _showSwipe
                cd:SetDrawSwipe(_showSwipe)
            end
            if cd._msufA2_lastReverse ~= _swipeReverse then
                cd._msufA2_lastReverse = _swipeReverse
                cd:SetReverse(_swipeReverse)
            end
            local wantHide = (not _showText) or (icon._msufA2_hideCDNumbers == true)
            if cd._msufA2_lastHideNumbers ~= wantHide or not wasTimerActive then
                cd._msufA2_lastHideNumbers = wantHide
                cd:SetHideCountdownNumbers(wantHide)
            end

            if _showText and icon._msufA2_hideCDNumbers ~= true then
                CT = CT or API.CooldownText
                if CT and icon._msufA2_cdMgrRegistered ~= true and CT.RegisterIcon then
                    CT.RegisterIcon(icon)
                elseif CT and CT.TouchIcon then
                    CT.TouchIcon(icon)
                end
                icon._msufA2_lastCdDurationObj = nil
                icon._msufA2_lastCdAid = aid
                icon._msufA2_lastCdShown = true
                icon._msufA2_lastCdWantText = true
                ApplyCooldownTextStyle(icon, cd, nil)
            else
                icon._msufA2_lastCdWantText = false
                icon._msufA2_lastCdShown = false
                icon._msufA2_lastCdDurationObj = nil
                icon._msufA2_lastCdAid = nil
                CT = CT or API.CooldownText
                if CT and CT.UnregisterIcon then CT.UnregisterIcon(icon) end
            end

            if _showPandemic then _fast_ApplyPandemic(icon) end
        elseif icon._msufA2_lastHadTimer == true or cd._msufA2_durationObj ~= nil or icon._msufA2_cdNumericFallback == true then
            -- PERF: Only clear if there WAS a timer before (avoid redundant ClearCooldownVisual calls)
            ClearCooldownVisual(icon, cd)
        end
        return
    end

    -- Both swipe and text disabled: nothing visual to update (except pandemic).
    if not _showSwipe and not _showText then
        icon._msufA2_durationObj = obj
        cd._msufA2_durationObj = obj
        icon._msufA2_lastHadTimer = true
        if _showPandemic then _fast_ApplyPandemic(icon) end
        return
    end

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

    local wasTimerActive = (icon._msufA2_lastHadTimer == true)
    icon._msufA2_durationObj = obj
    cd._msufA2_durationObj = obj
    icon._msufA2_lastHadTimer = true
    icon._msufA2_cdNumericFallback = nil

    -- A prior no-duration pass calls ClearCooldownVisual(), which hides native
    -- numbers and disables aura display time. Same-aura refreshes must restore
    -- those visual flags without waiting for a full CommitIcon.
    local wantAuraDisplayTime = (_useBlizzardTimer == true)
    if cd.SetUseAuraDisplayTime and cd._msufA2_lastUseAuraDisplayTime ~= wantAuraDisplayTime then
        cd._msufA2_lastUseAuraDisplayTime = wantAuraDisplayTime
        cd:SetUseAuraDisplayTime(wantAuraDisplayTime)
    end
    if cd._msufA2_lastSwipe ~= _showSwipe then
        cd._msufA2_lastSwipe = _showSwipe
        cd:SetDrawSwipe(_showSwipe)
    end
    if cd._msufA2_lastReverse ~= _swipeReverse then
        cd._msufA2_lastReverse = _swipeReverse
        cd:SetReverse(_swipeReverse)
    end
    local wantHide = (not _showText) or (icon._msufA2_hideCDNumbers == true)
    if cd._msufA2_lastHideNumbers ~= wantHide or not wasTimerActive then
        cd._msufA2_lastHideNumbers = wantHide
        cd:SetHideCountdownNumbers(wantHide)
    end

    -- CT ticker recolors the existing Cooldown FontString in both timer modes.
    if _showText and icon._msufA2_hideCDNumbers ~= true then
        CT = CT or API.CooldownText
        local wasRegistered = (icon._msufA2_cdMgrRegistered == true)
        if CT and (not wasRegistered) and CT.RegisterIcon then
            CT.RegisterIcon(icon)
            wasRegistered = (icon._msufA2_cdMgrRegistered == true)
        end
        local objChanged = (icon._msufA2_lastCdDurationObj ~= obj)
        local aidChanged = (icon._msufA2_lastCdAid ~= aid)
        local shownChanged = (icon._msufA2_lastCdShown ~= true)
        if CT and wasRegistered and CT.TouchIcon and (objChanged or aidChanged or shownChanged) then
            CT.TouchIcon(icon)
        end
        icon._msufA2_lastCdDurationObj = obj
        icon._msufA2_lastCdAid = aid
        icon._msufA2_lastCdShown = true
        icon._msufA2_lastCdWantText = true
        ApplyCooldownTextStyle(icon, cd, nil)
    else
        icon._msufA2_lastCdWantText = false
        icon._msufA2_lastCdShown = false
        icon._msufA2_lastCdDurationObj = nil
        icon._msufA2_lastCdAid = nil
        CT = CT or API.CooldownText
        if CT and CT.UnregisterIcon then CT.UnregisterIcon(icon) end
    end

    -- Pandemic: update when duration object refreshes.
    if _showPandemic then _fast_ApplyPandemic(icon) end
end

-- Stack count display

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
                    if type(_G.MSUF_SetFontSafe) == "function" then
                        _G.MSUF_SetFontSafe(countFS, wantFont, wantSize, wantFlags, ResolveGlobalFontKey())
                    else
                        countFS:SetFont(wantFont, wantSize, wantFlags)
                    end
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
        countFS:Hide()
        return
    end

    -- PERF: Inline GetStackCountFast — direct C API call, skip wrapper
    local count = _getStackCountDirect and _getStackCountDirect(unit, aid, 2, 99)

    if count == nil then
        countFS:Hide()
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
                countFS:Hide()
                icon._msufA2_lastCountText = nil
                return
            end
            txt = tostring(count)
        elseif type(count) == "string" then
            if count == "" then
                countFS:Hide()
                icon._msufA2_lastCountText = nil
                return
            end
            txt = count
        else
            countFS:Hide()
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
    local wantR, wantG, wantB = GetStackCountRGB()
    if icon._msufA2_lastStackR ~= wantR or icon._msufA2_lastStackG ~= wantG or icon._msufA2_lastStackB ~= wantB then
        icon._msufA2_lastStackR = wantR
        icon._msufA2_lastStackG = wantG
        icon._msufA2_lastStackB = wantB
        countFS:SetTextColor(wantR, wantG, wantB)
    end

    countFS:Show()
end

-- Own-aura highlight

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
            show = _wantBuffHL or icon._msufA2_forceOwnBuffHighlight == true
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
    -- PERF: Direct call (no pcall). C API is guaranteed callable; pcall cost ~10× per icon.
    local aid = aura._msufAuraInstanceID or aura.auraInstanceID
    if aid and unit and _debuffColorCurve
       and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor then
        local color = C_UnitAuras.GetAuraDispelTypeColor(unit, aid, _debuffColorCurve)
        if color then
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

-- Pandemic window pulsing border
-- Secret-safe: uses EvaluateRemainingPercent (curve-based, no value comparisons).
-- Called from CommitIcon, _RefreshTimer, and the 100ms pandemic ticker.

function Icons._ApplyPandemic(icon)
    local pan = icon._msufPandemic
    if not pan then return end

    if not _showPandemic or not _pandemicCurve then
        if pan:IsShown() then pan:SetAlpha(0); pan:Hide() end
        icon._msufPanLastMode = 0
        return
    end

    local obj = icon._msufA2_durationObj
    if not obj then
        if pan:IsShown() then pan:SetAlpha(0); pan:Hide() end
        return
    end

    -- Mode reconfiguration (diff-gated: only when pandemicMode changes)
    local mode = _pandemicMode
    local modeColorKey = mode * 1000003 + _panR * 997 + _panG * 991 + _panB * 983
    if icon._msufPanLastMode ~= modeColorKey then
        icon._msufPanLastMode = modeColorKey
        local border = pan._border
        local glow   = pan._glow
        local anim   = pan._anim
        local inner  = pan._inner
        -- Apply cached color to textures
        if border then border:SetVertexColor(_panR, _panG, _panB, 1) end
        if glow then glow:SetColorTexture(_panR, _panG, _panB, 0.35) end
        if mode == 1 then         -- BORDER: static green border, no glow, no animation
            if border then border:Show() end
            if glow then glow:Hide() end
            if anim and anim:IsPlaying() then anim:Stop() end
            if inner then inner:SetAlpha(1) end
        elseif mode == 2 then     -- PULSE: border + glow + throb animation
            if border then border:Show() end
            if glow then glow:Show() end
            if anim and not anim:IsPlaying() then anim:Play() end
        elseif mode == 3 then     -- GLOW: soft glow only + throb animation
            if border then border:Hide() end
            if glow then glow:Show() end
            if anim and not anim:IsPlaying() then anim:Play() end
        end
    end

    -- Alpha gate: secret-safe sink. 0 × childVisuals = invisible.
    if not pan:IsShown() then pan:Show() end
    local alpha
    if _pandemicEvalBool and obj.IsZero then
        alpha = _pandemicEvalBool(obj:IsZero(), 0, obj:EvaluateRemainingPercent(_pandemicCurve))
    else
        alpha = obj:EvaluateRemainingPercent(_pandemicCurve)
    end
    pan:SetAlpha(alpha)
end

-- Phase 8: bind file-scope locals (defined above) now that methods exist.
_fast_ApplyTimer        = Icons._ApplyTimer
_fast_RefreshTimer      = Icons._RefreshTimer
_fast_ApplyStacks       = Icons._ApplyStacks
_fast_ApplyOwnHighlight = Icons._ApplyOwnHighlight
_fast_ApplyDispelBorder = Icons._ApplyDispelBorder
_fast_ApplyPandemic     = Icons._ApplyPandemic

_RefreshDynamicIfNeeded = function(icon, unit, aid, shared, stackCountAnchor, aura, gen)
    local auraRev = aura and aura._msufA2_updateRev
    local anchor = stackCountAnchor or "TOPRIGHT"
    if auraRev
        and icon._msufA2_dynRev == auraRev
        and icon._msufA2_dynGen == gen
        and icon._msufA2_dynAnchor == anchor
    then
        if _showPandemic then _fast_ApplyPandemic(icon) end
        return
    end

    _fast_RefreshTimer(icon, unit, aid, shared, aura)
    _fast_ApplyStacks(icon, unit, aid, shared, stackCountAnchor, aura)
    icon._msufA2_dynRev = auraRev
    icon._msufA2_dynGen = gen
    icon._msufA2_dynAnchor = anchor
end

-- Refresh all assigned icons (fast path: timer + stacks only)
-- Called when aura membership hasn't changed but values may have

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
                    _RefreshDynamicIfNeeded(icon, unit, aid, shared, stackCountAnchor, aura, gen)
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
                    _RefreshDynamicIfNeeded(icon, unit, aid, shared, stackCountAnchor, aura, gen)
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
                    _RefreshDynamicIfNeeded(icon, unit, aid, shared, stackCountAnchor, aura, gen)
                end
            end
        end
    end
end

-- Preview icons (Edit Mode)

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
-- Export for MSUF_A2_EditMode.lua (file-scope locals are invisible across files)
_G.MSUF_A2_PREVIEW_BUFF_TEXTURES  = _PREVIEW_BUFF_TEXTURES
_G.MSUF_A2_PREVIEW_DEBUFF_TEXTURES = _PREVIEW_DEBUFF_TEXTURES
_G.MSUF_A2_PREVIEW_BUFF_TEX_N     = _PREVIEW_BUFF_TEX_N
_G.MSUF_A2_PREVIEW_DEBUFF_TEX_N   = _PREVIEW_DEBUFF_TEX_N

-- Cooldown durations per preview slot (varying so they don't all tick together)
local _PREVIEW_CD_DURATIONS = { 12, 18, 8, 25, 15, 10, 20, 30, 6, 22, 14, 9 }
local _PREVIEW_CD_DUR_N = #_PREVIEW_CD_DURATIONS
_G.MSUF_A2_PREVIEW_CD_DURATIONS = _PREVIEW_CD_DURATIONS
_G.MSUF_A2_PREVIEW_CD_DUR_N     = _PREVIEW_CD_DUR_N

-- Pandemic window ticker (100ms)
-- Re-evaluates pandemic pulsing border for all visible icons so the glow
-- appears as soon as the aura enters the ≤30% remaining window.
-- Secret-safe: delegates to _ApplyPandemic (curve eval → Show/Hide only).

do
    local _panTickWasActive = false
    local function PandemicTick()
        local state = API.state
        local aby = state and state.aurasByUnit
        if not aby then return end

        -- Feature turned off: one cleanup pass then idle.
        if not _showPandemic then
            if _panTickWasActive then
                _panTickWasActive = false
                for _, entry in pairs(aby) do
                    if entry then
                        local pool, n, ic
                        pool = entry.debuffs and entry.debuffs._msufIcons
                        if pool then
                            n = entry.debuffs._msufA2_activeN or #pool
                            for i = 1, n do ic = pool[i]; if ic and ic._msufPandemic then ic._msufPandemic:Hide() end end
                        end
                        pool = entry.buffs and entry.buffs._msufIcons
                        if pool then
                            n = entry.buffs._msufA2_activeN or #pool
                            for i = 1, n do ic = pool[i]; if ic and ic._msufPandemic then ic._msufPandemic:Hide() end end
                        end
                    end
                end
            end
            return
        end

        _panTickWasActive = true
        local _applyPan = Icons._ApplyPandemic
        for _, entry in pairs(aby) do
            if entry then
                local pool, n, ic
                pool = entry.debuffs and entry.debuffs._msufIcons
                if pool then
                    n = entry.debuffs._msufA2_activeN or #pool
                    for i = 1, n do
                        ic = pool[i]
                        if ic and ic:IsShown() and ic._msufAuraInstanceID then _applyPan(ic) end
                    end
                end
                pool = entry.buffs and entry.buffs._msufIcons
                if pool then
                    n = entry.buffs._msufA2_activeN or #pool
                    for i = 1, n do
                        ic = pool[i]
                        if ic and ic:IsShown() and ic._msufAuraInstanceID then _applyPan(ic) end
                    end
                end
            end
        end
    end

    -- Demand-driven loop: only runs when pandemic display is active.
    -- Zero idle overhead when _showPandemic is false (default).
    local _pandemicTicker
    local function PandemicLoopStep()
        local loop = _pandemicTicker
        if not loop then return end
        PandemicTick()
        if _pandemicTicker == loop and C_Timer and C_Timer.After then
            C_Timer.After(0.10, loop.step)
        elseif _pandemicTicker == loop then
            _pandemicTicker = nil
        end
    end
    local function _StartPandemicTicker()
        if _pandemicTicker then return end
        if not (C_Timer and C_Timer.After) then return end
        local loop = {}
        loop.step = function()
            if _pandemicTicker == loop then
                PandemicLoopStep()
            end
        end
        _pandemicTicker = loop
        C_Timer.After(0.10, loop.step)
    end
    local function _StopPandemicTicker()
        if not _pandemicTicker then return end
        _pandemicTicker = nil
        -- One cleanup pass
        PandemicTick()
    end
    -- Export for RefreshSharedFlags
    API._StartPandemicTicker = _StartPandemicTicker
    API._StopPandemicTicker  = _StopPandemicTicker
    if _showPandemic then _StartPandemicTicker() end
end

-- Backward-compatible exports into API.Apply
-- (Options, CooldownText, Preview, Masque all reference API.Apply.*)

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
    _G.MSUF_A2_ConfigGen = _configGen
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
    if not shared then return end

    -- Helper: apply font family + size to a FontString
    local function ApplyFontFamily(fs, wantSize)
        if not fs or not fs.SetFont or not fs.GetFont then return end
        local curFont, curSize, curFlags = fs:GetFont()
        local newFont = fontPath or curFont
        local newFlags = fontFlags or curFlags or "OUTLINE"
        local newSize = wantSize or curSize or 14
        if newFont then
            if type(_G.MSUF_SetFontSafe) == "function" then
                _G.MSUF_SetFontSafe(fs, newFont, newSize, newFlags, ResolveGlobalFontKey())
            else
                fs:SetFont(newFont, newSize, newFlags)
            end
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
            if type(_G.MSUF_SetFontSafe) == "function" then
                _G.MSUF_SetFontSafe(countFS, wantFont, wantSize, wantFlags, ResolveGlobalFontKey())
            else
                countFS:SetFont(wantFont, wantSize, wantFlags)
            end
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

    local r, g, b = GetStackCountRGB()
    countFS:SetTextColor(r, g, b, 1)
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
