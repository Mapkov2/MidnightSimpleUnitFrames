-- ============================================================================
-- MSUF_ClassPower.lua — Secondary Power (ClassPower/Runes) + Alt Mana Bar
--
-- Features:
--   1. ClassPower: segmented bars for Combo Points, Holy Power, Soul Shards,
--      Arcane Charges, Chi, Essence, and DK Runes.
--   2. AltMana: extra Mana bar for dual-resource specs (Shadow Priest, etc.)
--
-- Architecture:
--   - Self-contained: own event frame, own DB defaults, own layout.
--   - Independent overlay (Unhalted approach): no HP bar reservation.
--     CP sits on top of the frame at a higher frame level.
--   - Width/Height/X/Y fully configurable via sliders in options panel.
--   - Secret-safe: raw UnitPower/UnitPowerMax (2 args, MidnightRogueBars approach),
--     nil-guarded, no arithmetic on return values.
--   - Max performance: event-driven only (zero polling), cached config,
--     pre-resolved colors, no closures/strings in hot paths.
-- ============================================================================

-- Guard: only load once.
if _G.__MSUF_ClassPower_Loaded then return end
_G.__MSUF_ClassPower_Loaded = true

-- ============================================================================
-- Perf locals (eliminate global lookups in hot paths)
-- ============================================================================
local type, tonumber, pairs, select = type, tonumber, pairs, select
local math_floor, math_max = math.floor, math.max
local CreateFrame = CreateFrame
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitPowerPercent = UnitPowerPercent
local UnitClass = UnitClass
local UnitExists = UnitExists
local GetShapeshiftFormID = GetShapeshiftFormID
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local CurveScale100 = (CurveConstants and CurveConstants.ScaleTo100) or true

-- Secret-value guard (12.0 Midnight)
local _issecretvalue = _G.issecretvalue
local function NotSecret(v)
    if _issecretvalue then return _issecretvalue(v) == false end
    return true
end

-- Spec API (12.0: C_SpecializationInfo preferred, fallback to global)
local GetSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
    or GetSpecialization

-- Player class (resolved once, never changes)
local _, PLAYER_CLASS = UnitClass("player")

-- ============================================================================
-- PowerType constants (defensive: Enum.PowerType may not exist pre-load)
-- ============================================================================
local PT = {}
do
    local E = Enum and Enum.PowerType
    PT.Mana          = (E and E.Mana)          or 0
    PT.ComboPoints   = (E and E.ComboPoints)   or 4
    PT.Runes         = (E and E.Runes)         or 5
    PT.HolyPower     = (E and E.HolyPower)     or 9
    PT.SoulShards    = (E and E.SoulShards)     or 7
    PT.ArcaneCharges = (E and E.ArcaneCharges) or 16
    PT.Chi           = (E and E.Chi)            or 12
    PT.Essence       = (E and E.Essence)        or 19
end

-- ============================================================================
-- DB Defaults (self-contained; runs on every login, no-ops if keys exist)
-- ============================================================================
local function EnsureDefaults()
    if not MSUF_DB then return end
    if not MSUF_DB.bars then MSUF_DB.bars = {} end
    local b = MSUF_DB.bars

    -- ClassPower defaults
    if b.showClassPower       == nil then b.showClassPower       = true  end
    if b.classPowerHeight     == nil then b.classPowerHeight     = 4     end
    if b.classPowerColorByType == nil then b.classPowerColorByType = true end
    if b.classPowerBgAlpha    == nil then b.classPowerBgAlpha    = 0.3   end
    if b.classPowerTickWidth  == nil then b.classPowerTickWidth  = 1     end
    if b.classPowerOutline    == nil then b.classPowerOutline    = 1     end
    if b.classPowerWidth      == nil then b.classPowerWidth      = 0     end
    if b.classPowerWidthMode  == nil then b.classPowerWidthMode  = "player" end
    if b.classPowerOffsetX    == nil then b.classPowerOffsetX    = 0     end
    if b.classPowerOffsetY    == nil then b.classPowerOffsetY    = 0     end
    if b.smoothPowerBar       == nil then b.smoothPowerBar       = false end
    if b.showChargedComboPoints == nil then b.showChargedComboPoints = true end

    -- AltMana defaults
    if b.showAltMana          == nil then b.showAltMana          = true  end
    if b.altManaHeight        == nil then b.altManaHeight        = 4     end
    if b.altManaOffsetY       == nil then b.altManaOffsetY       = -2    end
    if b.altManaColorR        == nil then b.altManaColorR        = 0.0   end
    if b.altManaColorG        == nil then b.altManaColorG        = 0.0   end
    if b.altManaColorB        == nil then b.altManaColorB        = 0.8   end
end

-- ============================================================================
-- Power-type detection (resolved per spec/form change, cached)
-- ============================================================================

-- ClassPower: returns Enum.PowerType or nil
local function GetClassPowerType()
    if PLAYER_CLASS == "DEATHKNIGHT" then
        return PT.Runes
    elseif PLAYER_CLASS == "ROGUE" then
        return PT.ComboPoints
    elseif PLAYER_CLASS == "PALADIN" then
        return PT.HolyPower
    elseif PLAYER_CLASS == "WARLOCK" then
        return PT.SoulShards
    elseif PLAYER_CLASS == "EVOKER" then
        return PT.Essence
    elseif PLAYER_CLASS == "MAGE" then
        local spec = GetSpec and GetSpec()
        if spec == 1 then return PT.ArcaneCharges end
    elseif PLAYER_CLASS == "MONK" then
        local spec = GetSpec and GetSpec()
        if spec == 3 then return PT.Chi end
    elseif PLAYER_CLASS == "DRUID" then
        local form = GetShapeshiftFormID and GetShapeshiftFormID()
        if form == 1 then return PT.ComboPoints end  -- Cat Form
    end
    return nil
end

-- AltMana: returns true if we need a mana bar (primary power != Mana)
local function NeedsAltManaBar()
    local pType = UnitPowerType("player")
    -- pType == 0 = Mana primary → no alt bar needed
    if NotSecret(pType) then
        return (pType ~= nil and pType ~= PT.Mana)
    end
    -- If it's a secret value, fall back to class/spec heuristic
    local SPECS_NEED_ALT = {
        PRIEST  = { [3] = true },           -- Shadow
        SHAMAN  = { [1] = true, [2] = true }, -- Ele, Enh
        DRUID   = { [1] = true, [2] = true, [3] = true }, -- Balance, Feral, Guardian
        PALADIN = { [3] = true },           -- Ret
        MONK    = { [3] = true },           -- WW
    }
    local specs = SPECS_NEED_ALT[PLAYER_CLASS]
    if not specs then return false end
    local si = GetSpec and GetSpec()
    return si and specs[si] or false
end

-- PowerType → token mapping (for color resolution)
local POWER_TYPE_TOKENS = {
    [PT.ComboPoints]   = "COMBO_POINTS",
    [PT.Runes]         = "RUNES",
    [PT.HolyPower]     = "HOLY_POWER",
    [PT.SoulShards]    = "SOUL_SHARDS",
    [PT.ArcaneCharges] = "ARCANE_CHARGES",
    [PT.Chi]           = "CHI",
    [PT.Essence]       = "ESSENCE",
    [PT.Mana]          = "MANA",
}

-- ============================================================================
-- Color resolution (uses MSUF's PowerBarColor override system)
-- ============================================================================
local _cachedColorR, _cachedColorG, _cachedColorB = 1, 1, 1
local _cachedColorToken = nil

local function ResolveClassPowerColor(powerType)
    local token = POWER_TYPE_TOKENS[powerType]
    if token == _cachedColorToken and _cachedColorToken then
        return _cachedColorR, _cachedColorG, _cachedColorB
    end
    _cachedColorToken = token

    -- 1. Custom class-power color override (from Colors panel)
    if MSUF_DB and MSUF_DB.general then
        local ov = MSUF_DB.general.classPowerColorOverrides
        if type(ov) == "table" and token then
            local c = ov[token]
            if type(c) == "table" then
                local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
                if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                    _cachedColorR, _cachedColorG, _cachedColorB = r, g, b
                    return r, g, b
                end
            end
        end
    end

    -- 2. MSUF power bar color override
    if _G.MSUF_GetPowerBarColor and token then
        local r, g, b = _G.MSUF_GetPowerBarColor(powerType, token)
        if type(r) == "number" then
            _cachedColorR, _cachedColorG, _cachedColorB = r, g, b
            return r, g, b
        end
    end

    -- Fallback: Blizzard PowerBarColor
    local pbc = _G.PowerBarColor
    if pbc then
        local c = (token and pbc[token]) or pbc[powerType]
        if c then
            local r = c.r or c[1]
            local g = c.g or c[2]
            local b = c.b or c[3]
            if type(r) == "number" then
                _cachedColorR, _cachedColorG, _cachedColorB = r, g, b
                return r, g, b
            end
        end
    end

    -- Hard fallback
    _cachedColorR, _cachedColorG, _cachedColorB = 1, 1, 1
    return 1, 1, 1
end

-- Public: invalidate class power color cache (called from Colors panel)
_G.MSUF_ClassPower_InvalidateColors = function()
    _cachedColorToken = nil
    _cachedChargedR = nil  -- also invalidate charged cache
    if type(_G.MSUF_ClassPower_Refresh) == "function" then
        _G.MSUF_ClassPower_Refresh()
    end
end

-- ============================================================================
-- Charged / Empowered Combo Points (Echoing Reprimand, Supercharged CP, etc.)
-- ============================================================================
-- GetUnitChargedPowerPoints("player") returns a table of 1-based indices
-- that represent which combo point slots are "charged". These are non-secret
-- in WoW 12.0 builds.
-- ============================================================================
local _chargedMap = nil   -- [index] = true, or nil if none

local function RefreshChargedPoints()
    _chargedMap = nil
    if type(GetUnitChargedPowerPoints) ~= "function" then return end

    local indices = GetUnitChargedPowerPoints("player")
    if type(indices) ~= "table" or #indices == 0 then return end

    _chargedMap = {}
    for i = 1, #indices do
        local idx = indices[i]
        if type(idx) == "number" then
            _chargedMap[idx] = true
        end
    end
end

-- Charged/empowered color resolution
local _cachedChargedR, _cachedChargedG, _cachedChargedB

local function ResolveChargedColor()
    if _cachedChargedR then
        return _cachedChargedR, _cachedChargedG, _cachedChargedB
    end

    -- 1. Custom override from Colors panel
    if MSUF_DB and MSUF_DB.general then
        local ov = MSUF_DB.general.classPowerColorOverrides
        if type(ov) == "table" then
            local c = ov["CHARGED"]
            if type(c) == "table" then
                local r, g, b = c[1] or c.r, c[2] or c.g, c[3] or c.b
                if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                    _cachedChargedR, _cachedChargedG, _cachedChargedB = r, g, b
                    return r, g, b
                end
            end
        end
    end

    -- 2. Default: MidnightRogueBars purple
    _cachedChargedR, _cachedChargedG, _cachedChargedB = 0.60, 0.20, 0.80
    return 0.60, 0.20, 0.80
end

-- ============================================================================
-- ClassPower visual: segmented bars (created lazily on player frame)
-- ============================================================================
local MAX_CLASS_POWER = 10  -- Warlock can have up to 5 shards, Rogue up to 8+ combo pts
local CP = {
    bars     = {},      -- [i] = StatusBar
    ticks    = {},      -- [i] = Texture (separator lines)
    bgTex    = nil,     -- background texture
    container = nil,    -- parent frame
    maxBars  = 0,       -- currently allocated bar count
    currentMax = 0,     -- current max power (e.g. 5 combo pts)
    powerType = nil,    -- current Enum.PowerType
    visible  = false,
    height   = 4,
}

local function CP_EnsureBars(parent, count)
    if count <= CP.maxBars then return end

    for i = CP.maxBars + 1, count do
        local bar = CreateFrame("StatusBar", nil, CP.container)
        -- Flat texture for small segments — bar textures with gradients
        -- make colors appear washed out / grayish on 4px-high bars.
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:Hide()

        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(bar)
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(0, 0, 0, 0.3)
        bar._bg = bg

        CP.bars[i] = bar
    end

    -- Tick separators (between bars)
    for i = CP.maxBars + 1, count - 1 do
        if not CP.ticks[i] then
            local tick = CP.container:CreateTexture(nil, "OVERLAY")
            tick:SetTexture("Interface\\Buttons\\WHITE8x8")
            tick:SetVertexColor(0, 0, 0, 1)
            tick:Hide()
            CP.ticks[i] = tick
        end
    end

    CP.maxBars = count
end

local function CP_Create(playerFrame)
    if CP.container then return end

    local c = CreateFrame("Frame", "MSUF_ClassPowerContainer", playerFrame)
    c:SetFrameLevel(playerFrame:GetFrameLevel() + 5)  -- above hpBar (Unhalted overlay approach)
    c:Hide()
    CP.container = c

    -- Background
    local bg = c:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetAllPoints(c)
    bg:SetVertexColor(0, 0, 0, 0.3)
    CP.bgTex = bg

    -- Pre-allocate common max (6 for DK, 5 for most others)
    CP_EnsureBars(playerFrame, 8)
end

local function CP_Layout(playerFrame, maxPower, height)
    if not CP.container or maxPower <= 0 then return end

    local h = height
    local b = MSUF_DB and MSUF_DB.bars or {}

    -- Tick width from DB (0 = no ticks)
    local tickW = tonumber(b.classPowerTickWidth) or 1
    if tickW < 0 then tickW = 0 elseif tickW > 4 then tickW = 4 end

    -- User-configurable dimensions & position.
    -- Width mode: "player" = match player frame, "cooldown" = match ECV, "custom" = DB value.
    local widthMode = b.classPowerWidthMode or "player"
    local userW

    if widthMode == "cooldown" then
        -- Match Essential Cooldown Viewer width (BetterCooldownManager).
        local ecv = _G["EssentialCooldownViewer"]
        if ecv and ecv.GetWidth then
            userW = math_floor(ecv:GetWidth() + 0.5)
        end
        if not userW or userW < 30 then
            -- Fallback to player frame if ECV not available.
            local playerConf = MSUF_DB and MSUF_DB.player
            userW = ((playerConf and tonumber(playerConf.width)) or 275) - 4
        end
    elseif widthMode == "custom" then
        userW = tonumber(b.classPowerWidth) or 0
        if userW < 30 then
            local playerConf = MSUF_DB and MSUF_DB.player
            userW = ((playerConf and tonumber(playerConf.width)) or 275) - 4
        end
    else
        -- "player" (default): deterministic from DB (Unhalted approach).
        local playerConf = MSUF_DB and MSUF_DB.player
        userW = ((playerConf and tonumber(playerConf.width)) or 275) - 4
    end

    local oX = tonumber(b.classPowerOffsetX) or 0
    local oY = tonumber(b.classPowerOffsetY) or 0

    -- Anchor to playerFrame directly.
    -- CP is an independent overlay (Unhalted approach) — no HP bar reservation.
    CP.container:ClearAllPoints()
    CP.container:SetSize(userW, h)
    CP.container:SetPoint("TOPLEFT", playerFrame, "TOPLEFT", 2 + oX, -(2 - oY))

    -- Pixel-perfect outline (BackdropTemplate, same pattern as MSUF_ApplyBarOutline).
    -- Wraps the container with a snapped black border. Thickness from DB (0 = hidden).
    local outlineThick = tonumber(b.classPowerOutline) or 1
    if outlineThick < 0 then outlineThick = 0 elseif outlineThick > 4 then outlineThick = 4 end
    local snap = _G.MSUF_Snap

    if outlineThick > 0 then
        local edge = (type(snap) == "function") and snap(CP.container, outlineThick) or outlineThick
        if not CP._outline then
            local tpl = (BackdropTemplateMixin and "BackdropTemplate") or nil
            local ol = CreateFrame("Frame", nil, CP.container, tpl)
            ol:EnableMouse(false)
            ol:SetFrameLevel(CP.container:GetFrameLevel() + 1)
            CP._outline = ol
            CP._outlineEdge = -1
        end
        if CP._outlineEdge ~= edge then
            CP._outline:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = edge })
            CP._outline:SetBackdropBorderColor(0, 0, 0, 1)
            CP._outlineEdge = edge
        end
        CP._outline:ClearAllPoints()
        CP._outline:SetPoint("TOPLEFT", CP.container, "TOPLEFT", -edge, edge)
        CP._outline:SetPoint("BOTTOMRIGHT", CP.container, "BOTTOMRIGHT", edge, -edge)
        CP._outline:Show()
    elseif CP._outline then
        CP._outline:Hide()
    end

    local frameW = userW

    -- Bar width: subtract total tick space, divide evenly.
    -- All values pixel-snapped via MSUF_Snap to avoid subpixel bleed.
    local numTicks = maxPower - 1
    local snapTickW = (tickW > 0 and type(snap) == "function") and snap(CP.container, tickW) or tickW
    local totalTickW = numTicks * snapTickW
    local totalBarSpace = frameW - totalTickW
    local barW = math_floor(totalBarSpace / maxPower)

    -- BG alpha from config
    local bgA = tonumber(b.classPowerBgAlpha) or 0.3
    CP.bgTex:SetVertexColor(0, 0, 0, bgA)

    -- Layout individual bars (pixel-snapped positions)
    local xPos = 0
    for i = 1, maxPower do
        local bar = CP.bars[i]
        if bar then
            bar:ClearAllPoints()
            -- Last bar: stretch to exactly fill remaining space (absorbs rounding remainder)
            local thisW = (i == maxPower) and (frameW - xPos) or barW
            bar:SetPoint("TOPLEFT", CP.container, "TOPLEFT", xPos, 0)
            bar:SetSize(thisW, h)
            bar._bg:SetVertexColor(0, 0, 0, bgA)
            bar:Show()
            xPos = xPos + thisW + snapTickW
        end
    end

    -- (Outline handles all 4 edges — no separate border line needed)

    -- Hide excess bars
    for i = maxPower + 1, CP.maxBars do
        if CP.bars[i] then CP.bars[i]:Hide() end
    end

    -- Tick separators (between bars, pixel-snapped)
    if snapTickW > 0 then
        local tickX = barW  -- first tick after first bar
        for i = 1, numTicks do
            local tick = CP.ticks[i]
            if tick then
                tick:ClearAllPoints()
                tick:SetPoint("TOPLEFT", CP.container, "TOPLEFT", tickX, 0)
                tick:SetSize(snapTickW, h)
                tick:Show()
            end
            tickX = tickX + snapTickW + barW
        end
    end
    -- Hide excess / all ticks when tickW == 0
    local hideFrom = (snapTickW > 0) and maxPower or 1
    for i = hideFrom, #CP.ticks do
        if CP.ticks[i] then CP.ticks[i]:Hide() end
    end

    CP.currentMax = maxPower
    CP.height = h
end

-- Secret-safe value update + per-bar coloring (charged/empowered support)
local function CP_UpdateValues(powerType, maxPower)
    if maxPower <= 0 then return end

    -- Get current power count (regular number for most class resources)
    local cur = UnitPower("player", powerType)
    if not NotSecret(cur) then
        -- Secret value: show all filled (safe default)
        for i = 1, maxPower do
            local bar = CP.bars[i]
            if bar then bar:SetValue(1) end
        end
        return
    end

    cur = tonumber(cur) or 0

    -- Resolve base color
    local colorByType = true
    if MSUF_DB and MSUF_DB.bars then
        colorByType = (MSUF_DB.bars.classPowerColorByType ~= false)
    end

    local baseR, baseG, baseB
    if colorByType then
        baseR, baseG, baseB = ResolveClassPowerColor(powerType)
    else
        baseR, baseG, baseB = 1, 1, 1
    end

    -- Charged point support (only for combo points)
    local showCharged = MSUF_DB and MSUF_DB.bars
        and (MSUF_DB.bars.showChargedComboPoints ~= false)
        and powerType == PT.ComboPoints
    local chargedR, chargedG, chargedB
    if showCharged and _chargedMap then
        chargedR, chargedG, chargedB = ResolveChargedColor()
    end

    -- Background alpha (from DB)
    local bgA = 0.3
    if MSUF_DB and MSUF_DB.bars then
        bgA = tonumber(MSUF_DB.bars.classPowerBgAlpha) or 0.3
    end

    -- Per-bar fill + color
    for i = 1, maxPower do
        local bar = CP.bars[i]
        if bar then
            local isFilled = (i <= cur)
            bar:SetValue(isFilled and 1 or 0)

            local isCharged = showCharged and _chargedMap and _chargedMap[i]

            if isCharged then
                -- Charged: empowered color (filled or dim)
                bar:SetStatusBarColor(chargedR, chargedG, chargedB, 1)
                if isFilled then
                    bar._bg:SetVertexColor(0, 0, 0, bgA)
                else
                    -- Dim charged bg (visible when empty, shows the slot is empowered)
                    local dR = chargedR * 0.45; if dR < 0.05 then dR = 0.05 end
                    local dG = chargedG * 0.45; if dG < 0.05 then dG = 0.05 end
                    local dB = chargedB * 0.45; if dB < 0.05 then dB = 0.05 end
                    bar._bg:SetVertexColor(dR, dG, dB, 1)
                end
            else
                -- Normal: base color
                bar:SetStatusBarColor(baseR, baseG, baseB, 1)
                bar._bg:SetVertexColor(0, 0, 0, bgA)
            end
        end
    end
end

-- Legacy color-only refresh (called from FullRefresh for initial setup)
local function CP_ApplyColors(powerType)
    -- Now handled inline by CP_UpdateValues; this is kept for
    -- call sites that need a color refresh without value change.
    CP_UpdateValues(powerType, CP.currentMax)
end

local function CP_RefreshTexture()
    -- Class power segments always use flat texture for crisp colors.
    -- (User's bar texture with gradients makes small 4px bars look grayish.)
    for i = 1, CP.maxBars do
        local bar = CP.bars[i]
        if bar then bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8") end
    end
end

-- ============================================================================
-- AltMana visual: single StatusBar (created lazily on player frame)
-- ============================================================================
local AM = {
    bar       = nil,
    container = nil,
    bgTex     = nil,
    visible   = false,
}

local function AM_Create(playerFrame)
    if AM.container then return end

    local c = CreateFrame("Frame", "MSUF_AltManaContainer", playerFrame)
    c:SetFrameLevel(playerFrame:GetFrameLevel() + 2)
    c:Hide()
    AM.container = c

    -- Background
    local bg = c:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetAllPoints(c)
    bg:SetVertexColor(0, 0, 0, 0.4)
    AM.bgTex = bg

    -- Border (1px black outline via backdrop)
    local border = CreateFrame("Frame", nil, c, "BackdropTemplate")
    border:SetPoint("TOPLEFT", c, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    border:SetBackdropColor(0, 0, 0, 0)
    border:SetBackdropBorderColor(0, 0, 0, 1)
    border:SetFrameLevel(c:GetFrameLevel() + 1)
    AM._border = border

    -- Status bar
    local getTexture = _G.MSUF_GetBarTexture
    local bar = CreateFrame("StatusBar", nil, c)
    bar:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    bar:SetStatusBarTexture(getTexture and getTexture() or "Interface\\Buttons\\WHITE8x8")
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    bar:SetFrameLevel(c:GetFrameLevel() + 1)
    AM.bar = bar
end

local function AM_Layout(playerFrame)
    if not AM.container then return end
    local b = MSUF_DB and MSUF_DB.bars or {}

    local h = tonumber(b.altManaHeight) or 4
    if h < 2 then h = 2 elseif h > 30 then h = 30 end
    local oY = tonumber(b.altManaOffsetY) or -2

    -- Below playerFrame, matching hpBar horizontal edges for width consistency.
    AM.container:ClearAllPoints()
    AM.container:SetPoint("TOPLEFT",  playerFrame, "BOTTOMLEFT",   2, oY)
    AM.container:SetPoint("TOPRIGHT", playerFrame, "BOTTOMRIGHT", -2, oY)
    AM.container:SetHeight(h)
end

local function AM_ApplyColor()
    if not AM.bar then return end
    local b = MSUF_DB and MSUF_DB.bars or {}
    local r = tonumber(b.altManaColorR) or 0.0
    local g = tonumber(b.altManaColorG) or 0.0
    local bl = tonumber(b.altManaColorB) or 0.8

    -- Try MSUF override for Mana color
    local mr, mg, mb = ResolveClassPowerColor(PT.Mana)
    if mr then r, g, bl = mr, mg, mb end

    AM.bar:SetStatusBarColor(r, g, bl, 1)
end

-- Secret-safe mana value update (MidnightRogueBars approach)
local function AM_UpdateValue()
    if not AM.bar then return end

    -- Raw values, 2 args only (like MidnightRogueBars).
    local cur = UnitPower("player", PT.Mana)
    local mx  = UnitPowerMax("player", PT.Mana)
    if type(cur) ~= "number" then cur = 0 end
    if type(mx)  ~= "number" then mx  = 100 end

    -- Smooth interpolation when enabled.
    local smoothOn = MSUF_DB and MSUF_DB.bars and (MSUF_DB.bars.smoothPowerBar ~= false)
    local interp = smoothOn and Enum and Enum.StatusBarInterpolation
        and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
    if interp then
        AM.bar:SetMinMaxValues(0, mx, interp)
        AM.bar:SetValue(cur, interp)
    else
        AM.bar:SetMinMaxValues(0, mx)
        AM.bar:SetValue(cur)
    end
end

local function AM_RefreshTexture()
    if not AM.bar then return end
    local getTexture = _G.MSUF_GetBarTexture
    AM.bar:SetStatusBarTexture(getTexture and getTexture() or "Interface\\Buttons\\WHITE8x8")
end

-- ============================================================================
-- Master show/hide + layout integration
-- ============================================================================

local function GetPlayerFrame()
    return _G.MSUF_player or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames.player) or nil
end

-- ============================================================================
-- Full refresh (called on spec change, form change, config change)
-- ============================================================================
local function FullRefresh()
    if not MSUF_DB then return end
    local b = MSUF_DB.bars or {}
    local playerFrame = GetPlayerFrame()
    if not playerFrame then return end

    -- Hook player frame resize → relayout bars inside the container.
    -- Container auto-stretches via dual-point anchoring, but individual
    -- bars use calculated pixel positions that need recalculating.
    if not playerFrame._msufCPSizeHooked then
        playerFrame._msufCPSizeHooked = true
        playerFrame:HookScript("OnSizeChanged", function()
            if type(_G.MSUF_ClassPower_Refresh) == "function" then
                _G.MSUF_ClassPower_Refresh()
            end
        end)
    end

    -- Hook Essential Cooldown Viewer resize (for "cooldown" width mode).
    if not CP._ecvHooked then
        local ecv = _G["EssentialCooldownViewer"]
        if ecv and ecv.HookScript then
            CP._ecvHooked = true
            ecv:HookScript("OnSizeChanged", function()
                local mode = MSUF_DB and MSUF_DB.bars and MSUF_DB.bars.classPowerWidthMode
                if mode == "cooldown" and type(_G.MSUF_ClassPower_Refresh) == "function" then
                    _G.MSUF_ClassPower_Refresh()
                end
            end)
        end
    end

    -- Edit mode: hide both
    if _G.MSUF_UnitEditModeActive == true then
        if CP.container then CP.container:Hide() end
        if AM.container then AM.container:Hide() end

        CP.visible = false
        AM.visible = false
        return
    end

    -- ---- ClassPower ----
    local cpEnabled = (b.showClassPower ~= false)
    local powerType = GetClassPowerType()
    local cpHeight = tonumber(b.classPowerHeight) or 4
    if cpHeight < 2 then cpHeight = 2 elseif cpHeight > 30 then cpHeight = 30 end

    if cpEnabled and powerType then
        CP_Create(playerFrame)

        -- Get max power
        local maxP = UnitPowerMax("player", powerType)
        if not NotSecret(maxP) or type(maxP) ~= "number" then
            -- Heuristic fallback (safe; most are 5-6)
            if powerType == PT.Runes then maxP = 6
            elseif powerType == PT.ComboPoints then maxP = 7
            else maxP = 5 end
        end
        maxP = math_floor(maxP)
        if maxP < 1 then maxP = 1 end
        if maxP > MAX_CLASS_POWER then maxP = MAX_CLASS_POWER end

        CP_EnsureBars(playerFrame, maxP)
        CP_Layout(playerFrame, maxP, cpHeight)
        CP.powerType = powerType
        RefreshChargedPoints()
        CP_UpdateValues(powerType, maxP)
        CP.container:Show()
        CP.visible = true


    else
        if CP.container then CP.container:Hide() end
        CP.visible = false
        CP.powerType = nil

    end

    -- ---- AltMana ----
    local amEnabled = (b.showAltMana ~= false)
    local needsAlt = NeedsAltManaBar()

    if amEnabled and needsAlt then
        AM_Create(playerFrame)
        AM_Layout(playerFrame)
        AM_ApplyColor()
        AM_UpdateValue()
        AM.container:Show()
        AM.visible = true
    else
        if AM.container then AM.container:Hide() end
        AM.visible = false
    end
end

-- ============================================================================
-- Event-driven updates (hot path: minimal work)
-- ============================================================================

-- ClassPower value-only update (fires on UNIT_POWER_UPDATE for player)
local function OnPowerUpdate(powerToken)
    if not CP.visible or not CP.powerType then return end

    -- Quick token filter: only react to our power type
    local expectedToken = POWER_TYPE_TOKENS[CP.powerType]
    if powerToken and expectedToken and powerToken ~= expectedToken then
        -- Also handle RUNES token name variations
        if CP.powerType ~= PT.Runes or powerToken ~= "RUNES" then
            return
        end
    end

    CP_UpdateValues(CP.powerType, CP.currentMax)
end

local function OnManaUpdate()
    if not AM.visible then return end
    AM_UpdateValue()
end

-- ============================================================================
-- Event frame (single frame handles all events)
-- ============================================================================
local eventFrame = CreateFrame("Frame")

-- Throttle for rare events (spec/form changes)
local _lastFullRefresh = 0
local FULL_REFRESH_THROTTLE = 0.15

local function ThrottledFullRefresh()
    local now = GetTime()
    if now - _lastFullRefresh < FULL_REFRESH_THROTTLE then return end
    _lastFullRefresh = now
    FullRefresh()
end

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "UNIT_POWER_UPDATE" then
        if arg1 == "player" then
            OnPowerUpdate(arg2)
            OnManaUpdate()
        end
        return
    end

    if event == "UNIT_POWER_FREQUENT" then
        if arg1 == "player" then
            OnPowerUpdate(arg2)
            OnManaUpdate()
        end
        return
    end

    if event == "UNIT_MAXPOWER" then
        if arg1 == "player" then
            -- Max power changed → full refresh (e.g. gained/lost combo point talent)
            ThrottledFullRefresh()
        end
        return
    end

    if event == "UNIT_POWER_POINT_CHARGE" then
        if arg1 == "player" then
            RefreshChargedPoints()
            -- Re-apply colors with new charged state
            if CP.visible and CP.powerType then
                CP_UpdateValues(CP.powerType, CP.currentMax)
            end
        end
        return
    end

    if event == "UNIT_DISPLAYPOWER" then
        if arg1 == "player" then
            ThrottledFullRefresh()
        end
        return
    end

    -- Rare: rebuild on spec/form/talent changes
    if event == "PLAYER_SPECIALIZATION_CHANGED"
    or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
    or event == "PLAYER_TALENT_UPDATE"
    or event == "TRAIT_CONFIG_UPDATED"
    or event == "UPDATE_SHAPESHIFT_FORM"
    then
        -- Use C_Timer for safety (some of these fire before DB is ready)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, FullRefresh)
        else
            FullRefresh()
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        EnsureDefaults()
        -- Delay to let MSUF frames initialize
        if C_Timer and C_Timer.After then
            C_Timer.After(0.3, FullRefresh)
        else
            FullRefresh()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        EnsureDefaults()
        return
    end
end)

-- Register events
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
eventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
eventFrame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
eventFrame:RegisterUnitEvent("UNIT_POWER_POINT_CHARGE", "player")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

-- ============================================================================
-- Public API (for Options, Edit Mode, and other modules)
-- ============================================================================

-- Force full refresh (call after changing DB values)
function _G.MSUF_ClassPower_Refresh()
    _cachedColorToken = nil  -- Invalidate color cache
    FullRefresh()
end

-- Refresh bar textures (call after texture change in settings)
function _G.MSUF_ClassPower_RefreshTextures()
    CP_RefreshTexture()
    AM_RefreshTexture()
end

-- Query state (for options UI display)
function _G.MSUF_ClassPower_GetState()
    return {
        classPowerVisible = CP.visible,
        classPowerType    = CP.powerType,
        classPowerMax     = CP.currentMax,
        altManaVisible    = AM.visible,
    }
end

-- Compatibility: hook bar texture change for live refresh.
-- Options panels should call MSUF_ClassPower_Refresh() after DB changes.
do
    -- Deferred hook: MSUF_TryApplyBarTextureLive is created in Options (LoadOnDemand).
    -- We post-hook it on first FullRefresh when it exists.
    local _texHooked = false
    local _origFullRefresh = FullRefresh
    FullRefresh = function()
        if not _texHooked then
            local origTex = _G.MSUF_TryApplyBarTextureLive
            if type(origTex) == "function" then
                _G.MSUF_TryApplyBarTextureLive = function(...)
                    origTex(...)
                    CP_RefreshTexture()
                    AM_RefreshTexture()
                end
                _texHooked = true
            end
        end
        _origFullRefresh()
    end
end

-- ============================================================================
-- Smooth Power Bar Mode
-- ============================================================================
-- The actual smooth bar logic lives in MSUF_UnitframeCore.lua (DIRECT_APPLY)
-- and MidnightSimpleUnitFrames.lua (_MSUF_Bars_SyncPower).
--
-- When enabled, those paths use raw UnitPower/UnitPowerMax + ExponentialEaseOut
-- on BOTH SetMinMaxValues AND SetValue — identical to MidnightRogueBars.
-- Secret-safe: nil-guarded, no arithmetic on return values.
--
-- This section only provides the public toggle API for the options panel.
-- ============================================================================
_G.MSUF_SmoothPowerBar_Apply = function()
    -- Refresh the cached flags in UFCore's DIRECT_APPLY hot path.
    if type(_G.MSUF_UFCore_RefreshSettingsCache) == "function" then
        _G.MSUF_UFCore_RefreshSettingsCache("SMOOTH_POWER")
    end
end
