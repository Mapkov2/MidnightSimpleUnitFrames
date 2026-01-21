-- MidnightSimpleUnitFrames_Auras.lua
-- Auras 2.0: standalone menu, shared config (Target/Focus/Boss1-5)
-- One file containing Options Menu of Auras and the whole logicgate for it. In the long term should be its on LoD part of MSUF (Will be a LoD)

local addonName, ns = ...
ns = ns or {}

local MSUF_DB

local MSUF_A2_DB_READY = false
local MSUF_A2_DB_LAST = nil

local function MSUF_A2_InvalidateDB()
    MSUF_A2_DB_READY = false
    MSUF_A2_DB_LAST = nil
end

if _G and type(_G.MSUF_A2_InvalidateDB) ~= "function" then
    _G.MSUF_A2_InvalidateDB = MSUF_A2_InvalidateDB
end


local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil
end

local function MSUF_SafeNumber(v)
    local ok, s = pcall(tostring, v)
    if not ok then return nil end
    local n = tonumber(s)
    return n
end

local function EnsureDB()
    -- Fast-path: if we already ensured this SavedVariables table this session,
    -- just return pointers without re-running migrations/default normalization.
    local gdb = _G and _G.MSUF_DB or nil
    if MSUF_A2_DB_READY and gdb == MSUF_A2_DB_LAST and type(gdb) == "table" then
        local a2fast = gdb.auras2
        local sfast = (type(a2fast) == "table") and a2fast.shared or nil
        if type(a2fast) == "table" and type(sfast) == "table" then
            MSUF_DB = gdb
            return a2fast, sfast
        end
    end

    -- Ensure a SavedVariables table exists (load-order safe)
    if type(_G.MSUF_DB) ~= "table" then
        _G.MSUF_DB = {}
    end

    -- Prefer the project-wide EnsureDB if present
    if type(_G.EnsureDB) == "function" then
        pcall(_G.EnsureDB)
    end

    MSUF_DB = _G.MSUF_DB
    if type(MSUF_DB) ~= "table" then
        return nil
    end


    -- Global (General) defaults used by Auras 2.0 cooldown text
    MSUF_DB.general = (type(MSUF_DB.general) == 'table') and MSUF_DB.general or {}
    local g = MSUF_DB.general
    if g.aurasCooldownTextUseBuckets == nil then g.aurasCooldownTextUseBuckets = true end

    -- Breakpoints (seconds) for aura cooldown text bucket coloring.
    -- Safe: upper window for applying Safe/Warning/Urgent colors (above this uses normal font color).
    -- Warning: when remaining seconds are <= Warning, switch to Warning color.
    -- Urgent: when remaining seconds are <= Urgent, switch to Urgent color.
    if type(g.aurasCooldownTextSafeSeconds) ~= 'number' then g.aurasCooldownTextSafeSeconds = 60 end
    if type(g.aurasCooldownTextWarningSeconds) ~= 'number' then g.aurasCooldownTextWarningSeconds = 15 end
    if type(g.aurasCooldownTextUrgentSeconds) ~= 'number' then g.aurasCooldownTextUrgentSeconds = 5 end
    -- Hard caps for UI sliders (Step 2): Warning max 30s, Urgent max 15s
    if g.aurasCooldownTextWarningSeconds > 30 then g.aurasCooldownTextWarningSeconds = 30 end
    if g.aurasCooldownTextUrgentSeconds  > 15 then g.aurasCooldownTextUrgentSeconds  = 15 end

    -- Clamp ordering: Safe >= Warning >= Urgent >= 0
    if g.aurasCooldownTextSafeSeconds < 0 then g.aurasCooldownTextSafeSeconds = 0 end
    if g.aurasCooldownTextWarningSeconds < 0 then g.aurasCooldownTextWarningSeconds = 0 end
    if g.aurasCooldownTextUrgentSeconds < 0 then g.aurasCooldownTextUrgentSeconds = 0 end
    if g.aurasCooldownTextUrgentSeconds > g.aurasCooldownTextWarningSeconds then
        g.aurasCooldownTextUrgentSeconds = g.aurasCooldownTextWarningSeconds
    end
    if g.aurasCooldownTextWarningSeconds > g.aurasCooldownTextSafeSeconds then
        g.aurasCooldownTextWarningSeconds = g.aurasCooldownTextSafeSeconds
        if g.aurasCooldownTextUrgentSeconds > g.aurasCooldownTextWarningSeconds then
            g.aurasCooldownTextUrgentSeconds = g.aurasCooldownTextWarningSeconds
        end
    end

    -- Create / normalize Auras2 defaults (also duplicated in MSUF_Defaults.lua, but kept here for safety)
    MSUF_DB.auras2 = (type(MSUF_DB.auras2) == "table") and MSUF_DB.auras2 or {}
    local a2 = MSUF_DB.auras2

    if a2.enabled == nil then a2.enabled = true end
    if a2.showTarget == nil then a2.showTarget = true end
    if a2.showFocus == nil then a2.showFocus = true end
    if a2.showBoss  == nil then a2.showBoss  = true end

    a2.shared = (type(a2.shared) == "table") and a2.shared or {}
    local s = a2.shared
    if s.showBuffs == nil then s.showBuffs = true end
    if s.showDebuffs == nil then s.showDebuffs = true end
    if s.onlyMyBuffs == nil then s.onlyMyBuffs = false end
    if s.onlyMyDebuffs == nil then s.onlyMyDebuffs = false end
    if s.hidePermanent == nil then s.hidePermanent = false end
    if s.showTooltip == nil then s.showTooltip = true end
    if s.showCooldownSwipe == nil then s.showCooldownSwipe = true end
    if s.showInEditMode == nil then s.showInEditMode = true end
    if s.showStackCount == nil then s.showStackCount = true end
    if s.stackCountAnchor == nil then s.stackCountAnchor = "TOPRIGHT" end
    if s.masqueEnabled == nil then s.masqueEnabled = false end
    if s.layoutMode == nil then s.layoutMode = "SEPARATE" end

    -- Buff/Debuff anchor mode for "Separate rows".
    -- "STACKED" preserves legacy behavior (both groups above the frame, buffs above debuffs).
    -- Split modes place one group on one side of the unitframe and the other group on another side.
    if s.buffDebuffAnchor == nil then s.buffDebuffAnchor = "STACKED" end

    -- Spacing used by split-anchor modes (how far the buff/debuff blocks are pushed away from the unitframe).
    -- 0 preserves existing behavior.
    if s.splitSpacing == nil then s.splitSpacing = 0 end
    if type(s.splitSpacing) ~= "number" then s.splitSpacing = 0 end
    if s.splitSpacing < 0 then s.splitSpacing = 0 end
    if s.splitSpacing > 80 then s.splitSpacing = 80 end

    -- Visual highlights (border coloring)
    -- These are independent of the filter master switch: they never hide auras, they only change border color.
    if s.highlightStealableBuffs == nil then s.highlightStealableBuffs = true end
    if s.highlightDispellableDebuffs == nil then s.highlightDispellableDebuffs = true end

    -- Highlight your own auras (border coloring). Independent of filters.
    if s.highlightOwnBuffs == nil then s.highlightOwnBuffs = false end
    if s.highlightOwnDebuffs == nil then s.highlightOwnDebuffs = false end

    if s.iconSize == nil then s.iconSize = 26 end
    if s.spacing == nil then s.spacing = 2 end
    if s.perRow == nil then s.perRow = 12 end
    if s.maxIcons == nil then s.maxIcons = 12 end
    if s.maxBuffs == nil then s.maxBuffs = s.maxIcons or 12 end
    if s.maxDebuffs == nil then s.maxDebuffs = s.maxIcons or 12 end
    if s.growth == nil then s.growth = "RIGHT" end -- RIGHT/LEFT/UP/DOWN
    if s.growth ~= "RIGHT" and s.growth ~= "LEFT" and s.growth ~= "UP" and s.growth ~= "DOWN" then
        s.growth = "RIGHT"
    end

    -- Validate buff/debuff anchor mode
    if s.buffDebuffAnchor ~= "STACKED"
        and s.buffDebuffAnchor ~= "TOP_BOTTOM_BUFFS"
        and s.buffDebuffAnchor ~= "TOP_BOTTOM_DEBUFFS"
        and s.buffDebuffAnchor ~= "TOP_RIGHT_BUFFS"
        and s.buffDebuffAnchor ~= "TOP_RIGHT_DEBUFFS"
        and s.buffDebuffAnchor ~= "BOTTOM_RIGHT_BUFFS"
        and s.buffDebuffAnchor ~= "BOTTOM_RIGHT_DEBUFFS"
        and s.buffDebuffAnchor ~= "BOTTOM_LEFT_BUFFS"
        and s.buffDebuffAnchor ~= "BOTTOM_LEFT_DEBUFFS"
        and s.buffDebuffAnchor ~= "TOP_LEFT_BUFFS"
        and s.buffDebuffAnchor ~= "TOP_LEFT_DEBUFFS"
    then
        s.buffDebuffAnchor = "STACKED"
    end

    -- Row wrap direction when using horizontal growth (LEFT/RIGHT) and icons exceed "perRow".
    -- DOWN (default): second row appears below the first.
    -- UP: second row appears above the first.
    if s.rowWrap == nil then s.rowWrap = "DOWN" end
    if s.rowWrap ~= "DOWN" and s.rowWrap ~= "UP" then
        s.rowWrap = "DOWN"
    end

    if s.offsetX == nil then s.offsetX = 0 end
    if s.offsetY == nil then s.offsetY = 6 end
    if s.buffOffsetY == nil then s.buffOffsetY = 30 end

    if s.stackTextSize == nil then s.stackTextSize = 14 end
    if s.cooldownTextSize == nil then s.cooldownTextSize = 14 end
    if s.bossEditTogether == nil then s.bossEditTogether = true end

-- Shared filter config (source of truth for filtering). Units can optionally override these.
-- Migration: older builds stored the filter config under perUnit.target.filters.
if type(s.filters) ~= "table" then
    if type(a2.perUnit) == "table" and type(a2.perUnit.target) == "table" and type(a2.perUnit.target.filters) == "table" then
        s.filters = a2.perUnit.target.filters
        s.filters._msufA2_sharedFiltersMigratedFromTarget = true
    else
        s.filters = {}
    end
end

    -- Mark that Auras2 defaults have been initialized at least once.
    if s._msufA2_migrated_v11f == nil then
        s._msufA2_migrated_v11f = true
    end

    -- Per-unit filter DB (Target first; future-ready for Focus/Boss). UI will write here.
    a2.perUnit = (type(a2.perUnit) == "table") and a2.perUnit or {}
    local pu = a2.perUnit

    -- Normalize filter tables (shared + per-unit) without overwriting user choices.
    -- Note: We also keep legacy migrations here so old DBs remain compatible.
    local A2_DISPEL_KEYS = { "dispelMagic", "dispelCurse", "dispelDisease", "dispelPoison", "dispelEnrage" }

    local function NormalizeFilters(f, sharedSettings, migrateFlagKey)
        if type(f) ~= "table" then return end

        if f.enabled == nil then f.enabled = true end
        if type(f.buffs) ~= "table" then f.buffs = {} end
        if type(f.debuffs) ~= "table" then f.debuffs = {} end

        local b, d = f.buffs, f.debuffs

        -- One-time migration from old shared flags (kept for backward compatibility).
        -- Important: never overwrite an existing user choice; only fill missing fields.
        if migrateFlagKey and not f[migrateFlagKey] and type(sharedSettings) == "table" then
            if f.hidePermanent == nil then f.hidePermanent = (sharedSettings.hidePermanent == true) end
            if b.onlyMine == nil then b.onlyMine = (sharedSettings.onlyMyBuffs == true) end
            if d.onlyMine == nil then d.onlyMine = (sharedSettings.onlyMyDebuffs == true) end
            f[migrateFlagKey] = true
        end

        -- Defaults (do not assume UI exists yet)
        if f.hidePermanent == nil then f.hidePermanent = false end

        if b.onlyMine == nil then b.onlyMine = false end
        if b.includeBoss == nil then b.includeBoss = false end
        if b.includeStealable == nil then b.includeStealable = false end
        -- Legacy: migrate old "Only stealable" into additive mode
        if b.stealableOnly == true then b.includeStealable = true; b.stealableOnly = false end

        if d.onlyMine == nil then d.onlyMine = false end
        if d.includeBoss == nil then d.includeBoss = false end
        if d.includeDispellable == nil then d.includeDispellable = false end
        -- Legacy: migrate old "Only dispellable" into additive mode
        if d.dispellableOnly == true then d.includeDispellable = true; d.dispellableOnly = false end

        if f.onlyBossAuras == nil then f.onlyBossAuras = false end

        -- Debuff-type filtering (optional): if ANY type is selected, debuffs are limited to selected types.
        for i = 1, #A2_DISPEL_KEYS do
            local k = A2_DISPEL_KEYS[i]
            if d[k] == nil then d[k] = false end
        end
    end

    local function EnsurePerUnitFilters(unitKey)
        if type(pu[unitKey]) ~= "table" then pu[unitKey] = {} end
        local u = pu[unitKey]

        if u.overrideFilters == nil then u.overrideFilters = false end

        -- Edit Mode layout override (position + box size)
        if u.overrideLayout == nil then u.overrideLayout = false end
        if type(u.layout) ~= "table" then u.layout = {} end
        do
            local lay = u.layout
            if type(lay.offsetX) ~= "number" then lay.offsetX = 0 end
            if type(lay.offsetY) ~= "number" then lay.offsetY = 0 end
            -- Width/Height are optional (only used for Edit Mode box / popup), keep nil unless user sets them.
            if lay.width ~= nil and type(lay.width) ~= "number" then lay.width = nil end
            if lay.height ~= nil and type(lay.height) ~= "number" then lay.height = nil end
        end


        -- Shared caps overrides (Max Buffs/Debuffs, Icons per row)
        if u.overrideSharedLayout == nil then u.overrideSharedLayout = false end
        if type(u.layoutShared) ~= "table" then u.layoutShared = {} end
        do
            local ls = u.layoutShared
            if ls.maxBuffs ~= nil and type(ls.maxBuffs) ~= "number" then ls.maxBuffs = nil end
            if ls.maxDebuffs ~= nil and type(ls.maxDebuffs) ~= "number" then ls.maxDebuffs = nil end
            if ls.perRow ~= nil and type(ls.perRow) ~= "number" then ls.perRow = nil end
            if ls.splitSpacing ~= nil and type(ls.splitSpacing) ~= "number" then ls.splitSpacing = nil end
            if type(ls.splitSpacing) == "number" then
                if ls.splitSpacing < 0 then ls.splitSpacing = 0 end
                if ls.splitSpacing > 80 then ls.splitSpacing = 80 end
            end

            -- New shared-layout dropdown overrides (string values)
            -- Keep nil when invalid; runtime will fall back to shared.
            if ls.growth ~= nil and (ls.growth ~= "RIGHT" and ls.growth ~= "LEFT" and ls.growth ~= "UP" and ls.growth ~= "DOWN") then ls.growth = nil end
            if ls.rowWrap ~= nil and (ls.rowWrap ~= "DOWN" and ls.rowWrap ~= "UP") then ls.rowWrap = nil end
            if ls.layoutMode ~= nil and (ls.layoutMode ~= "SEPARATE" and ls.layoutMode ~= "SINGLE") then ls.layoutMode = nil end
            if ls.buffDebuffAnchor ~= nil and (
                ls.buffDebuffAnchor ~= "STACKED"
                and ls.buffDebuffAnchor ~= "TOP_BOTTOM_BUFFS"
                and ls.buffDebuffAnchor ~= "TOP_BOTTOM_DEBUFFS"
                and ls.buffDebuffAnchor ~= "TOP_RIGHT_BUFFS"
                and ls.buffDebuffAnchor ~= "TOP_RIGHT_DEBUFFS"
                and ls.buffDebuffAnchor ~= "BOTTOM_RIGHT_BUFFS"
                and ls.buffDebuffAnchor ~= "BOTTOM_RIGHT_DEBUFFS"
                and ls.buffDebuffAnchor ~= "BOTTOM_LEFT_BUFFS"
                and ls.buffDebuffAnchor ~= "BOTTOM_LEFT_DEBUFFS"
                and ls.buffDebuffAnchor ~= "TOP_LEFT_BUFFS"
                and ls.buffDebuffAnchor ~= "TOP_LEFT_DEBUFFS"
            ) then
                ls.buffDebuffAnchor = nil
            end
            if ls.stackCountAnchor ~= nil and (ls.stackCountAnchor ~= "TOPRIGHT" and ls.stackCountAnchor ~= "TOPLEFT" and ls.stackCountAnchor ~= "BOTTOMRIGHT" and ls.stackCountAnchor ~= "BOTTOMLEFT") then ls.stackCountAnchor = nil end
        end

        if type(u.filters) ~= "table" then u.filters = {} end
        NormalizeFilters(u.filters, s, "_msufA2_filtersMigrated_v2")
        return u.filters
    end

    -- Ensure shared filters exist and are normalized (do not overwrite user choices).
    local sf = s.filters
    if type(sf) ~= "table" then sf = {}; s.filters = sf end
    NormalizeFilters(sf, s, "_msufA2_sharedFiltersMigrated_v1")

    -- Keep legacy shared flags synced for backward compatibility (safe; derived from shared.filters).
    s.onlyMyBuffs = (sf.buffs and sf.buffs.onlyMine == true) or false
    s.onlyMyDebuffs = (sf.debuffs and sf.debuffs.onlyMine == true) or false
    s.hidePermanent = (sf.hidePermanent == true)

    -- Ensure per-unit filter tables exist now (Player/Target/Focus/Boss1-5).
    EnsurePerUnitFilters("player")
    EnsurePerUnitFilters("target")
    EnsurePerUnitFilters("focus")
    for i = 1, 5 do
        EnsurePerUnitFilters("boss" .. i)
    end

    -- Mark DB as ensured for fast-path in hot paths.

    MSUF_A2_DB_LAST = MSUF_DB

    MSUF_A2_DB_READY = true


    return a2, s
end


-- ------------------------------------------------------------
-- Auras 2.0 colors (secret-safe)
-- Stored under MSUF_DB.general so the Colors menu can manage them.
-- ------------------------------------------------------------
local function MSUF_A2_GetOwnBuffHighlightRGB()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    local t = g and g.aurasOwnBuffHighlightColor or nil
    if type(t) == "table" then
        local r = t[1] or t.r
        local gg = t[2] or t.g
        local b = t[3] or t.b
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b
        end
    end
    return 1.0, 0.85, 0.2 -- legacy gold
end

local function MSUF_A2_GetOwnDebuffHighlightRGB()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    local t = g and g.aurasOwnDebuffHighlightColor or nil
    if type(t) == "table" then
        local r = t[1] or t.r
        local gg = t[2] or t.g
        local b = t[3] or t.b
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b
        end
    end
    return 1.0, 0.85, 0.2 -- legacy gold
end

local function MSUF_A2_GetStackCountRGB()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    local t = g and g.aurasStackCountColor or nil
    if type(t) == "table" then
        local r = t[1] or t.r
        local gg = t[2] or t.g
        local b = t[3] or t.b
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b
        end
    end
    return 1, 1, 1 -- white
end

local function MSUF_A2_GetEffectiveTextSizes(unitKey, shared)
    local stackSize = (shared and shared.stackTextSize) or 14
    local cooldownSize = (shared and shared.cooldownTextSize) or 14

    if MSUF_DB and MSUF_DB.auras2 and MSUF_DB.auras2.perUnit and unitKey then
        local u = MSUF_DB.auras2.perUnit[unitKey]
        if u and u.overrideLayout == true and type(u.layout) == 'table' then
            if type(u.layout.stackTextSize) == 'number' and u.layout.stackTextSize > 0 then
                stackSize = u.layout.stackTextSize
            end
            if type(u.layout.cooldownTextSize) == 'number' and u.layout.cooldownTextSize > 0 then
                cooldownSize = u.layout.cooldownTextSize
            end
        end
    end

    stackSize = tonumber(stackSize) or 14
    cooldownSize = tonumber(cooldownSize) or 14
    stackSize = math.max(6, math.min(40, stackSize))
    cooldownSize = math.max(6, math.min(40, cooldownSize))
    return stackSize, cooldownSize
end

local function MSUF_A2_SetFontSize(fs, size)
    if not fs or not fs.SetFont then return false end

    size = tonumber(size)
    if not size or size <= 0 then return false end

    -- Prefer the resolved font file from GetFont(); if missing (FontObject-only),
    -- fall back to the FontObject's GetFont().
    local font, _, flags = nil, nil, nil
    if fs.GetFont then
        font, _, flags = fs:GetFont()
    end
    if not font and fs.GetFontObject then
        local fo = fs:GetFontObject()
        if fo and fo.GetFont then
            font, _, flags = fo:GetFont()
        end
    end

    if not font then
        return false
    end

    local ok = pcall(fs.SetFont, fs, font, size, flags)
    return ok == true
end


-- Apply the MSUF global font (face/outline/shadow) to a FontString, using the provided size.
-- NOTE: Size is still driven by Auras (shared/per-unit). This only binds font face + flags + shadow.
local function MSUF_A2_ApplyFont(fs, fontPath, size, flags, useShadow)
    if not fs or not fs.SetFont then return false end

    size = tonumber(size)
    if not size or size <= 0 then return false end

    if not fontPath or fontPath == "" then
        -- Fallback: keep current font file if global isn't resolved yet.
        if fs.GetFont then
            local curFont, _, curFlags = fs:GetFont()
            if curFont and curFont ~= "" then
                fontPath = curFont
                if not flags or flags == "" then
                    flags = curFlags
                end
            end
        end
        if not fontPath or fontPath == "" then
            fontPath = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        end
    end

    local stamp = tostring(fontPath) .. "|" .. tostring(size) .. "|" .. tostring(flags or "")
    if fs._msufA2_fontStamp ~= stamp then
        local ok = pcall(fs.SetFont, fs, fontPath, size, flags)
        if ok then
            fs._msufA2_fontStamp = stamp
        end
    end

    local wantShadow = (useShadow == true)
    local shadowStamp = wantShadow and 1 or 0
    if fs._msufA2_shadowStamp ~= shadowStamp then
        if wantShadow then
            if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
            if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
        else
            if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
        end
        fs._msufA2_shadowStamp = shadowStamp
    end

    return true
end

local function MSUF_A2_GetCooldownFontString(icon)
    local cd = icon and icon.cooldown
    if not cd or not cd.GetRegions then return nil end

    local cached = cd._msufCooldownFontString
    if cached and cached ~= false then
        return cached
    end

    -- If we previously failed to find the fontstring, retry occasionally because
    -- Blizzard may build the countdown text lazily.
    local now = (GetTime and GetTime()) or 0
    if cached == false then
        local last = cd._msufCooldownFontStringLastTry or 0
        if (now - last) < 0.5 then
            return nil
        end
    end
    cd._msufCooldownFontStringLastTry = now

    local regions = { cd:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        if r and r.GetObjectType and r:GetObjectType() == 'FontString' then
            cd._msufCooldownFontString = r
            return r
        end
    end

    cd._msufCooldownFontString = false
    return nil
end

-- ------------------------------------------------------------
-- Auras 2.0 Cooldown Text Manager (single OnUpdate)
--
-- Purpose:
--  * Centralize any cooldown-text work (coloring / future bucketing) into ONE OnUpdate.
--  * Use Duration Objects + EvaluateRemainingDuration(ColorCurve) (secret-safe).
--
-- NOTE:
--  This does NOT compute remaining seconds itself (no expiration arithmetic). It only evaluates
--  a Duration Object against a step curve and applies the resulting color.
-- ------------------------------------------------------------

local MSUF_A2_CooldownColorCurve

-- Called from Colors menu when Safe/Warning/Urgent swatches change.
-- Keep global to avoid module coupling.
function _G.MSUF_A2_InvalidateCooldownTextCurve()
    MSUF_A2_CooldownColorCurve = nil
    MSUF_A2_CooldownTextColors = nil
end

-- Force an immediate recolor pass (used by Colors menu so preview reacts instantly).
function _G.MSUF_A2_ForceCooldownTextRecolor()
    local mgr = MSUF_A2_CooldownTextMgr
    if not mgr or not mgr.active then return end

    local bucketsEnabled = MSUF_A2_IsCooldownTextBucketColoringEnabled()
    local safeCol
    if not bucketsEnabled then
        local c = MSUF_A2_EnsureCooldownTextColors()
        safeCol = c and c.safe or nil
    end

    local curve = bucketsEnabled and MSUF_A2_EnsureCooldownColorCurve() or nil
    for cooldown, ic in pairs(mgr.active) do
        if cooldown and ic and ic.IsShown and ic:IsShown() and ic._msufA2_hideCDNumbers ~= true then
            local r, g, b, a

            if not bucketsEnabled and safeCol then
                r, g, b, a = safeCol[1], safeCol[2], safeCol[3], safeCol[4]
            end

            if C_UnitAuras and type(C_UnitAuras.GetAuraDurationRemaining) == 'function' then
                local unit = ic._msufUnit
                local auraID = ic._msufAuraInstanceID
                if unit and auraID then
                    local okRem, rem = pcall(C_UnitAuras.GetAuraDurationRemaining, unit, auraID)
                    if okRem and type(rem) == 'number' then
                        local colT = MSUF_A2_GetCooldownTextColorForRemainingSeconds(rem)
                        if colT then r, g, b, a = colT[1], colT[2], colT[3], colT[4] end
                    end
                end
            end

            if (not r) and ic._msufA2_isPreview == true then
                local ps = ic._msufA2_previewCooldownStart
                local pd = ic._msufA2_previewCooldownDur
                if type(ps) == 'number' and type(pd) == 'number' and pd > 0 then
                    local rem = (ps + pd) - GetTime()
                    if type(rem) == 'number' then
                        local colT = MSUF_A2_GetCooldownTextColorForRemainingSeconds(rem)
                        if colT then r, g, b, a = colT[1], colT[2], colT[3], colT[4] end
                    end
                end
            end

            if (not r) and curve then
                local obj = ic._msufA2_cdDurationObj or cooldown._msufA2_durationObj
                if obj and type(obj.EvaluateRemainingDuration) == 'function' then
                    local okCol, col = pcall(obj.EvaluateRemainingDuration, obj, curve)
                    if okCol and col and col.GetRGBA then
                        r, g, b, a = col:GetRGBA()
                    end
                end
            end

            if r then
                local fs = cooldown._msufCooldownFontString
                if fs == false then fs = nil end
                if not fs then fs = MSUF_A2_GetCooldownFontString(ic) end
                if fs then cooldown._msufCooldownFontString = fs end
                if fs then
                    local aa = a
                    if type(aa) ~= 'number' then aa = 1 end
                    if fs.SetTextColor then
                        fs:SetTextColor(r, g, b, aa)
                    elseif fs.SetVertexColor then
                        fs:SetVertexColor(r, g, b, aa)
                    end
                end
            end
        end
    end
end

local MSUF_A2_CooldownTextMgr = {
    frame = nil,
    active = {}, -- [cooldownFrame] = icon
    count = 0,
    acc = 0,
}

local function MSUF_A2_GetGlobalFontRGB_Fallback()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or nil
    if g and g.useCustomFontColor == true
       and type(g.fontColorCustomR) == "number"
       and type(g.fontColorCustomG) == "number"
       and type(g.fontColorCustomB) == "number"
    then
        return g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB
    end
    return 1, 1, 1
end

-- Master toggle (global): when disabled, aura cooldown text always uses the Safe color.
local function MSUF_A2_IsCooldownTextBucketColoringEnabled()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or nil
    -- default = enabled
    return not (g and g.aurasCooldownTextUseBuckets == false)
end

-- Cached cooldown text bucket colors (safe/warning/urgent/expire).
-- Invalidation is wired to _G.MSUF_A2_InvalidateCooldownTextCurve() to keep menu changes live.
local MSUF_A2_CooldownTextColors

local function MSUF_A2_EnsureCooldownTextColors()
    if MSUF_A2_CooldownTextColors then
        return MSUF_A2_CooldownTextColors
    end

    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or nil

    local normalR, normalG, normalB = MSUF_A2_GetGlobalFontRGB_Fallback()

    -- Optional user overrides (all non-secret).
    local safeR, safeG, safeB = normalR, normalG, normalB
    if g and type(g.aurasCooldownTextSafeColor) == "table" then
        local t = g.aurasCooldownTextSafeColor
        if type(t[1]) == "number" and type(t[2]) == "number" and type(t[3]) == "number" then
            safeR, safeG, safeB = t[1], t[2], t[3]
        end
    end
    local warnR, warnG, warnB = 1.00, 0.85, 0.20
    if g and type(g.aurasCooldownTextWarningColor) == "table" then
        local t = g.aurasCooldownTextWarningColor
        local r = t[1] or t.r
        local gg = t[2] or t.g
        local b = t[3] or t.b
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            warnR, warnG, warnB = r, gg, b
        end
    end

    local urgR, urgG, urgB = 1.00, 0.55, 0.10
    if g and type(g.aurasCooldownTextUrgentColor) == "table" then
        local t = g.aurasCooldownTextUrgentColor
        if type(t[1]) == "number" and type(t[2]) == "number" and type(t[3]) == "number" then
            urgR, urgG, urgB = t[1], t[2], t[3]
        end
    end

    -- Expire color is intentionally hard red (matches the UI example).
    MSUF_A2_CooldownTextColors = {
        -- Normal (uncolored) fallback for long durations (when Safe window is exceeded).
        normal  = { normalR, normalG, normalB, 1 },
        expire  = { 1.00, 0.10, 0.10, 1 },
        urgent  = { urgR,  urgG,  urgB,  1 },
        warning = { warnR, warnG, warnB, 1 },
        safe    = { safeR, safeG, safeB, 1 },
    }

    return MSUF_A2_CooldownTextColors
end

local function MSUF_A2_GetCooldownTextColorForRemainingSeconds(rem)
    if type(rem) ~= 'number' then return nil end
    local c = MSUF_A2_EnsureCooldownTextColors()
    if not c then return nil end

    -- Feature toggle: always Safe when disabled.
    if not MSUF_A2_IsCooldownTextBucketColoringEnabled() then
        return c.safe
    end

    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local safeSec = (g and type(g.aurasCooldownTextSafeSeconds) == 'number') and g.aurasCooldownTextSafeSeconds or 60
    local warnSec = (g and type(g.aurasCooldownTextWarningSeconds) == 'number') and g.aurasCooldownTextWarningSeconds or 15
    local urgSec  = (g and type(g.aurasCooldownTextUrgentSeconds)  == 'number') and g.aurasCooldownTextUrgentSeconds  or 5

    -- Clamp ordering defensively (menu setters already enforce this).
    if safeSec < 0 then safeSec = 0 end
    if warnSec < 0 then warnSec = 0 end
    if urgSec  < 0 then urgSec  = 0 end
    if urgSec > warnSec then urgSec = warnSec end
    if warnSec > safeSec then warnSec = safeSec; if urgSec > warnSec then urgSec = warnSec end end

    -- Buckets:
    --  • <=0: Expire (hard red)
    --  • <=Urgent: Urgent color
    --  • <=Warning: Warning color
    --  • <=Safe: Safe color
    --  • >Safe: Normal font color (keeps long buffs clean / less noisy)
    if rem <= 0 then
        return c.expire
    elseif rem <= urgSec then
        return c.urgent
    elseif rem <= warnSec then
        return c.warning
    elseif rem <= safeSec then
        return c.safe
    end
    return c.normal
end

local function MSUF_A2_EnsureCooldownColorCurve()
    if MSUF_A2_CooldownColorCurve then
        return MSUF_A2_CooldownColorCurve
    end

    -- Feature toggle: when disabled, skip curve evaluation entirely (Safe color is applied directly).
    if not MSUF_A2_IsCooldownTextBucketColoringEnabled() then
        return nil
    end

    if not C_CurveUtil or type(C_CurveUtil.CreateColorCurve) ~= "function" then
        return nil
    end
    if type(CreateColor) ~= "function" then
        return nil
    end

    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or nil

    local normalR, normalG, normalB = MSUF_A2_GetGlobalFontRGB_Fallback()

    -- Optional user overrides (all non-secret).
    local safeR, safeG, safeB = normalR, normalG, normalB
    if g and type(g.aurasCooldownTextSafeColor) == "table" then
        local t = g.aurasCooldownTextSafeColor
        if type(t[1]) == "number" and type(t[2]) == "number" and type(t[3]) == "number" then
            safeR, safeG, safeB = t[1], t[2], t[3]
        end
    end
    local warnR, warnG, warnB = 1.00, 0.85, 0.20
    if g and type(g.aurasCooldownTextWarningColor) == "table" then
        local t = g.aurasCooldownTextWarningColor
        local r = t[1] or t.r
        local gg = t[2] or t.g
        local b = t[3] or t.b
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            warnR, warnG, warnB = r, gg, b
        end
    end

    local urgR, urgG, urgB = 1.00, 0.55, 0.10
    if g and type(g.aurasCooldownTextUrgentColor) == "table" then
        local t = g.aurasCooldownTextUrgentColor
        if type(t[1]) == "number" and type(t[2]) == "number" and type(t[3]) == "number" then
            urgR, urgG, urgB = t[1], t[2], t[3]
        end
    end

    -- Step curve with unique colors per bucket.
    local curve = C_CurveUtil.CreateColorCurve()
    if curve.SetType then
        curve:SetType(Enum.LuaCurveType.Step)
    end

    local cExpire  = CreateColor(1.00, 0.10, 0.10, 1)
    local cSeconds = CreateColor(urgR,  urgG,  urgB,  1) -- Urgent
    local cShort   = CreateColor(warnR, warnG, warnB, 1) -- Warning
    local cNormal  = CreateColor(safeR, safeG, safeB, 1) -- Safe (or Global font)

    -- Step curves return the *previous* point's color between points.
    -- To get intuitive buckets in seconds:
    --   Expire:  <= 0
    --   Urgent:  0 < rem <= 5
    --   Warning: 5 < rem <= 15
    --   Safe:    rem > 15
    -- we use small epsilons so the boundaries land in the intended bucket.
    curve:AddPoint(0.00,  cExpire)
    curve:AddPoint(0.01,  cSeconds) -- Urgent
    curve:AddPoint(5.01,  cShort)   -- Warning
    curve:AddPoint(15.01, cNormal)  -- Safe
    curve:AddPoint(59.00, cNormal)  -- clamp / long durations
    MSUF_A2_CooldownColorCurve = curve
    return curve
end

local function MSUF_A2_CooldownTextMgr_StopIfIdle()
    if MSUF_A2_CooldownTextMgr.count > 0 then return end
    MSUF_A2_CooldownTextMgr.count = 0
    local f = MSUF_A2_CooldownTextMgr.frame
    if f then
        f:SetScript("OnUpdate", nil)
        f:Hide()
    end
end

local function MSUF_A2_CooldownTextMgr_EnsureFrame()
    local f = MSUF_A2_CooldownTextMgr.frame
    if f then return f end
    f = CreateFrame("Frame")
    f:Hide()
    MSUF_A2_CooldownTextMgr.frame = f
    return f
end

local function MSUF_A2_CooldownTextMgr_RegisterIcon(icon)
    local cd = icon and icon.cooldown
    if not cd then return end

    -- Avoid double-register
    if MSUF_A2_CooldownTextMgr.active[cd] then
        return
    end

    MSUF_A2_CooldownTextMgr.active[cd] = icon
    MSUF_A2_CooldownTextMgr.count = MSUF_A2_CooldownTextMgr.count + 1
    icon._msufA2_cdMgrRegistered = true

    local f = MSUF_A2_CooldownTextMgr_EnsureFrame()
    if MSUF_A2_CooldownTextMgr.count ~= 1 then
        return
    end

    MSUF_A2_CooldownTextMgr.acc = 0
    f:Show()
    f:SetScript('OnUpdate', function(_, elapsed)
        local mgr = MSUF_A2_CooldownTextMgr
        mgr.acc = mgr.acc + (elapsed or 0)
        if mgr.acc < 0.10 then return end -- 10 Hz
        mgr.acc = 0

        -- Feature toggle: when disabled, always apply the Safe color.
        local bucketsEnabled = MSUF_A2_IsCooldownTextBucketColoringEnabled()
        local safeCol
        if not bucketsEnabled then
            local c = MSUF_A2_EnsureCooldownTextColors()
            safeCol = c and c.safe or nil
        end

        -- Build (or reuse) the curve. If unavailable, we still clean up stale entries.
        local curve = bucketsEnabled and MSUF_A2_EnsureCooldownColorCurve() or nil

        local removed = 0
        for cooldown, ic in pairs(mgr.active) do
            if (not cooldown) or (not ic) or (not ic.IsShown) or (ic.IsShown and not ic:IsShown()) then
                mgr.active[cooldown] = nil
                removed = removed + 1
            elseif ic._msufA2_hideCDNumbers ~= true then
                local r, g, b, a

                if not bucketsEnabled and safeCol then
                    r, g, b, a = safeCol[1], safeCol[2], safeCol[3], safeCol[4]
                end

                -- Prefer a real remaining-seconds API (non-secret) so bucketing is deterministic and options apply correctly.
                if C_UnitAuras and type(C_UnitAuras.GetAuraDurationRemaining) == "function" then
                    local unit = ic._msufUnit
                    local auraID = ic._msufAuraInstanceID
                    if unit and auraID then
                        local okRem, rem = pcall(C_UnitAuras.GetAuraDurationRemaining, unit, auraID)
                        if okRem and type(rem) == "number" then
                            local colT = MSUF_A2_GetCooldownTextColorForRemainingSeconds(rem)
                            if colT then
                                r, g, b, a = colT[1], colT[2], colT[3], colT[4]
                            end
                        end
                    end

                -- Preview in Edit Mode: use our synthetic cooldown timing so users can see real bucket colors.
                if (not r) and ic._msufA2_isPreview == true then
                    local ps = ic._msufA2_previewCooldownStart
                    local pd = ic._msufA2_previewCooldownDur
                    if type(ps) == 'number' and type(pd) == 'number' and pd > 0 then
                        local rem = (ps + pd) - GetTime()
                        if type(rem) == 'number' then
                            local colT = MSUF_A2_GetCooldownTextColorForRemainingSeconds(rem)
                            if colT then
                                r, g, b, a = colT[1], colT[2], colT[3], colT[4]
                            end
                        end
                    end
                end

                end

                -- Fallback: Duration Object evaluation (kept for clients without GetAuraDurationRemaining).
                if (not r) and curve then
                    local obj = ic._msufA2_cdDurationObj or (cooldown and cooldown._msufA2_durationObj)
                    if obj and type(obj.EvaluateRemainingDuration) == 'function' then
                        local okCol, col = pcall(obj.EvaluateRemainingDuration, obj, curve)
                        if okCol and col and col.GetRGBA then
                            r, g, b, a = col:GetRGBA()
                        end
                    end
                end

                if r then
                    -- Cache the cooldown fontstring once (Blizzard may create it lazily)
                    local fs = cooldown and cooldown._msufCooldownFontString
                    if fs == false then fs = nil end
                    if not fs then
                        fs = MSUF_A2_GetCooldownFontString(ic)
                    end
                    if fs and cooldown then
                        cooldown._msufCooldownFontString = fs
                    end

                    if fs then
                        local aa = a
                        if type(aa) ~= 'number' then aa = 1 end
                        if fs.SetTextColor then
                            fs:SetTextColor(r, g, b, aa)
                        elseif fs.SetVertexColor then
                            fs:SetVertexColor(r, g, b, aa)
                        end
                    end
                end
            end
        end

        if removed > 0 then
            mgr.count = mgr.count - removed
            if mgr.count < 0 then mgr.count = 0 end
            MSUF_A2_CooldownTextMgr_StopIfIdle()
        end
    end)
end

local function MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
    local cd = icon and icon.cooldown
    if not cd then return end
    if not MSUF_A2_CooldownTextMgr.active[cd] then
        icon._msufA2_cdMgrRegistered = false
        return
    end
    MSUF_A2_CooldownTextMgr.active[cd] = nil
    MSUF_A2_CooldownTextMgr.count = MSUF_A2_CooldownTextMgr.count - 1
    if MSUF_A2_CooldownTextMgr.count < 0 then MSUF_A2_CooldownTextMgr.count = 0 end
    icon._msufA2_cdMgrRegistered = false
    MSUF_A2_CooldownTextMgr_StopIfIdle()
end

local function MSUF_A2_GetDispelBorderRGB()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    local t = g and g.aurasDispelBorderColor or nil
    if type(t) == "table" then
        local r = t[1] or t.r
        local gg = t[2] or t.g
        local b = t[3] or t.b
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b
        end
    end
    return 0.2, 0.6, 1.0 -- bright blue
end

local function MSUF_A2_GetStealableBorderRGB()
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    local t = g and g.aurasStealableBorderColor or nil
    if type(t) == "table" then
        local r = t[1] or t.r
        local gg = t[2] or t.g
        local b = t[3] or t.b
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b
        end
    end
    return 0.0, 0.75, 1.0 -- cyan
end

local function GetAuras2DB()

    return EnsureDB()
end


local AurasByUnit

-- ------------------------------------------------------------
-- Masque (optional)
-- ------------------------------------------------------------
local MSUF_MasqueAuras2

local function MSUF_A2_IsMasqueAddonLoaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("Masque") == true
    end
    if type(IsAddOnLoaded) == "function" then
        return IsAddOnLoaded("Masque") == true
    end
    return false
end

local function MSUF_A2_EnsureMasqueGroup()
    if MSUF_MasqueAuras2 then return true end
    if not MSUF_A2_IsMasqueAddonLoaded() then return false end
    local msq = (LibStub and LibStub("Masque", true)) or nil
    if not msq then return false end
    MSUF_MasqueAuras2 = msq:Group("Midnight Simple Unit Frames", "Auras 2.0")
    return MSUF_MasqueAuras2 ~= nil
end

-- Masque toggle requires a ReloadUI to fully rebuild icon regions in a predictable way.
-- (Masque can skin existing buttons, but reusing pooled regions without reload can look inconsistent.)
if _G and not _G.MSUF_A2_MASQUE_RELOAD_POPUP_READY then
    _G.MSUF_A2_MASQUE_RELOAD_POPUP_READY = true

    StaticPopupDialogs["MSUF_A2_RELOAD_MASQUE"] = StaticPopupDialogs["MSUF_A2_RELOAD_MASQUE"] or {
        text = "Masque skinning change requires a UI reload to apply cleanly.\n\n WARNING: Stealable/Dispellable/Buff/Debuff Highlights may not work properly with some Masque skins.",
        button1 = RELOADUI,
        button2 = CANCEL,
        OnAccept = function()
            ReloadUI()
        end,
        OnCancel = function()
            -- Revert the toggle if the user cancels.
            local _, shared = GetAuras2DB()
            if shared then
                shared.masqueEnabled = (_G.MSUF_A2_MASQUE_RELOAD_PREV == true) and true or false
            end
            if _G.MSUF_A2_MASQUE_RELOAD_CB and _G.MSUF_A2_MASQUE_RELOAD_CB.SetChecked then
                _G.MSUF_A2_MASQUE_RELOAD_CB:SetChecked((_G.MSUF_A2_MASQUE_RELOAD_PREV == true) and true or false)
                if _G.MSUF_A2_MASQUE_RELOAD_CB._msufSync then
                    _G.MSUF_A2_MASQUE_RELOAD_CB._msufSync()
                end
            end
            if type(_G.MSUF_Auras2_RefreshAll) == "function" then
                _G.MSUF_Auras2_RefreshAll()
            end
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }
end


local function MSUF_A2_IsMasqueEnabled(shared)
    if not MSUF_A2_EnsureMasqueGroup() then return false end
    if shared and shared.masqueEnabled == true then return true end
    return false
end

local function MSUF_A2_MasqueAddButton(btn, shared)
    if not btn or btn.MSUF_MasqueAdded then return end
    if not MSUF_A2_IsMasqueEnabled(shared) then return end

    local regions = {
        Icon     = btn.Icon or btn.tex,
        Cooldown = btn.Cooldown or btn.cooldown,
        Border   = btn.Border or btn.border,
        Normal   = btn.Normal or (btn.GetNormalTexture and btn:GetNormalTexture()) or nil,
        Count    = btn.Count or btn.count,
    }

    local ok = pcall(MSUF_MasqueAuras2.AddButton, MSUF_MasqueAuras2, btn, regions)
    if ok then
        btn.MSUF_MasqueAdded = true
    end
end

local function MSUF_A2_MasqueRemoveButton(btn)
    if not btn or not btn.MSUF_MasqueAdded or not MSUF_MasqueAuras2 then return end
    pcall(MSUF_MasqueAuras2.RemoveButton, MSUF_MasqueAuras2, btn)
    btn.MSUF_MasqueAdded = nil
end

-- ------------------------------------------------------------
-- Icon factory
-- ------------------------------------------------------------

local function CreateBorder(frame)
    local border = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    border:SetAllPoints()
    border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    border:SetBackdropBorderColor(0, 0, 0, 1)
    frame._msufBorder = border
end


-- ------------------------------------------------------------
-- Step 7 perf (cumulative): shared tooltip handlers + cached preview defs + cooldown set gating
-- ------------------------------------------------------------

-- One-time tooltip handlers (assigned once per icon). We only toggle EnableMouse per update.
local function MSUF_A2_IconOnEnter(self)
    if not self then return end
    -- DB guard (tooltip should never error if called early)
    if not MSUF_DB or not MSUF_DB.auras2 or not MSUF_DB.auras2.shared then
        EnsureDB()
    end
    if not MSUF_DB or not MSUF_DB.auras2 or not MSUF_DB.auras2.shared then return end
    local shared = MSUF_DB.auras2.shared
    if shared.showTooltip ~= true then return end

    -- Preview tooltip (fake auras shown in Edit Mode)
    if self._msufA2_isPreview then
        if GameTooltip then
			local owner = self._msufTooltipOwner or self
			-- Tooltip should never error even if called from a stale/early frame
			if not owner then return end
			GameTooltip:SetOwner(owner, "ANCHOR_NONE")
			GameTooltip:ClearAllPoints()
			GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 12, 0)
            GameTooltip:SetText("Auras 2.0 Preview", 1, 1, 1)
            local kind = self._msufA2_previewKind
            if kind and kind ~= "" then
                GameTooltip:AddLine(kind, 0.9, 0.9, 0.9, true)
            end
            local cat = (self._msufFilter == "HELPFUL") and "Buff" or "Debuff"
            GameTooltip:AddLine("Category: " .. cat, 0.7, 0.7, 0.7, true)
            if self._msufSpellId then
                GameTooltip:AddLine("SpellID: " .. tostring(self._msufSpellId), 0.7, 0.7, 0.7, true)
            end
            GameTooltip:Show()
        end
        return
    end

	if not GameTooltip then return end
	local owner = self._msufTooltipOwner or self
	if not owner then return end
	GameTooltip:SetOwner(owner, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 12, 0)
    local ok = false
    if GameTooltip.SetUnitAuraByAuraInstanceID and self._msufUnit and self._msufAuraInstanceID then
        GameTooltip:SetUnitAuraByAuraInstanceID(self._msufUnit, self._msufAuraInstanceID)
        ok = true
    elseif self._msufSpellId and GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(self._msufSpellId)
        ok = true
    end
    if not ok then
        GameTooltip:SetText("Aura")
    end
    GameTooltip:Show()
end

local function MSUF_A2_IconOnLeave(self)
    if GameTooltip then GameTooltip:Hide() end
end

-- Cached preview definitions (no per-render table allocations)
local MSUF_A2_PREVIEW_BUFF_DEFS = {
    { tex = "Interface\\Icons\\Spell_Arcane_ArcaneTorrent", spellId = 28730, isHelpful = true, stealable = true, previewKind = "Stealable / purgeable buff (border)" },
    { tex = "Interface\\Icons\\Ability_Rogue_SliceDice", spellId = 5171, isHelpful = true, stackText = "2", previewKind = "Stacked buff (shows stack count)" },
    { tex = "Interface\\Icons\\Spell_Holy_BlessingOfStrength", spellId = 6673, isHelpful = true, isOwn = true, previewKind = "Own buff (highlight)" },
    { tex = "Interface\\Icons\\Spell_Nature_Rejuvenation", spellId = 774, isHelpful = true, previewKind = "Normal buff" },
    { tex = "Interface\\Icons\\Spell_Holy_DevotionAura", spellId = 465, isHelpful = true, permanent = true, previewKind = "Permanent buff (no duration)" },
}

local MSUF_A2_PREVIEW_DEBUFF_DEFS = {
    { tex = "Interface\\Icons\\Spell_Frost_FrostNova", spellId = 122, isHelpful = false, dispellable = true, previewKind = "Dispellable debuff (border)" },
    { tex = "Interface\\Icons\\Ability_Warrior_Sunder", spellId = 7386, isHelpful = false, stackText = "12", previewKind = "Stacked debuff (shows stack count)" },
    { tex = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy", spellId = 49016, isHelpful = false, isOwn = true, previewKind = "Own debuff (highlight)" },
    { tex = "Interface\\Icons\\Spell_Shadow_ShadowWordPain", spellId = 589, isHelpful = false, previewKind = "Normal debuff" },
    { tex = "Interface\\Icons\\Spell_Shadow_Curse", spellId = 702, isHelpful = false, permanent = true, previewKind = "Permanent debuff (no duration)" },
}

local function AcquireIcon(container, index)
    container._msufIcons = container._msufIcons or {}
    local icon = container._msufIcons[index]
    if icon then
        -- Ensure Masque state is synced even for pooled/reused buttons
        local _, shared = GetAuras2DB()
        if MSUF_A2_IsMasqueEnabled(shared) then
            MSUF_A2_MasqueAddButton(icon, shared)
        else
            MSUF_A2_MasqueRemoveButton(icon)
        end
        return icon
    end

    icon = CreateFrame("Button", nil, container, BackdropTemplateMixin and "BackdropTemplate" or nil)
    icon:SetSize(26, 26)
    icon:EnableMouse(true)

    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()
    icon.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Masque expects these canonical fields on a Button
    icon.Icon = icon.tex

    -- Provide a Normal texture region for Masque skins (even if we don't use it)
    icon._msufMasqueNormal = icon:CreateTexture(nil, "BACKGROUND")
    icon._msufMasqueNormal:SetAllPoints()
    icon._msufMasqueNormal:SetTexture(nil)
    SafeCall(icon.SetNormalTexture, icon, icon._msufMasqueNormal)
    icon.Normal = (icon.GetNormalTexture and icon:GetNormalTexture()) or icon._msufMasqueNormal

    -- Provide a Border texture region for Masque skins
    icon._msufMasqueBorder = icon:CreateTexture(nil, "OVERLAY")
    icon._msufMasqueBorder:SetAllPoints()
    icon._msufMasqueBorder:SetTexture(nil)
    icon.Border = icon._msufMasqueBorder


    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.Cooldown = icon.cooldown
    SafeCall(icon.cooldown.SetDrawEdge, icon.cooldown, false)
    SafeCall(icon.cooldown.SetDrawSwipe, icon.cooldown, true)
    SafeCall(icon.cooldown.SetDrawBling, icon.cooldown, false)
    SafeCall(icon.cooldown.SetHideCountdownNumbers, icon.cooldown, false)
    SafeCall(icon.cooldown.SetHideCountdownNumbers, icon.cooldown, false)

    -- Auras2: Expiration accuracy/stuck-at-0 fix (secret-safe)
    -- Some clients do not fire UNIT_AURA exactly at natural expiration, which can leave an icon visible at 0.
    -- We hook the Cooldown widget's OnCooldownDone and revalidate auraInstanceID, then request a coalesced refresh.
    if icon.cooldown and not icon.cooldown._msufA2_doneHooked then
        icon.cooldown._msufA2_doneHooked = true
        icon.cooldown._msufA2_parentIcon = icon
        icon.cooldown:SetScript("OnCooldownDone", function(cd)
            local ic = cd and cd._msufA2_parentIcon
            if not ic then return end
            if ic._msufA2_isPreview then return end
            local unit = ic._msufUnit
            local aid = ic._msufAuraInstanceID
            if not unit or not aid then return end

            if C_UnitAuras and type(C_UnitAuras.GetAuraDataByAuraInstanceID) == "function" then
                local ok, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, aid)
                -- Secret-safe: don't compare auraData to nil; use type() gating.
                if ok and type(auraData) ~= "table" then
                    -- Aura is gone: immediately hide this recycled icon and force a refresh so layout closes gaps.
                    if ic._msufA2_cdMgrRegistered == true then
                        MSUF_A2_CooldownTextMgr_UnregisterIcon(ic)
                    end
                    ic._msufA2_cdDurationObj = nil
                    if ic.cooldown then
                        ic.cooldown._msufA2_durationObj = nil
                    end
                    ic:Hide()
                    if _G and type(_G.MSUF_Auras2_RefreshUnit) == "function" then
                        _G.MSUF_Auras2_RefreshUnit(unit)
                    elseif _G and type(_G.MSUF_Auras2_RefreshAll) == "function" then
                        _G.MSUF_Auras2_RefreshAll()
                    end
                end
            end
        end)
    end

    -- Count must render ABOVE the cooldown swipe.
    -- A Cooldown widget is a child frame and can cover parent fontstrings due to framelevel.
    -- So we create a dedicated count frame with a higher framelevel than the cooldown.
    icon._msufCountFrame = CreateFrame("Frame", nil, icon)
    icon._msufCountFrame:SetAllPoints()
    do
        local baseLevel = (icon.cooldown and icon.cooldown.GetFrameLevel and icon.cooldown:GetFrameLevel()) or icon:GetFrameLevel() or 1
        icon._msufCountFrame:SetFrameLevel(baseLevel + 5)
    end

    icon.count = icon._msufCountFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    icon.Count = icon.count
    icon.count:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 4, 7) -- slightly more right
    icon.count:SetJustifyH("RIGHT")

    -- Bind stack count to global font settings (face/outline/shadow). Size follows Auras layout (shared/per-unit).
    do
        local fontPath, fontFlags, _, _, _, _, useShadow
        if type(MSUF_GetGlobalFontSettings) == "function" then
            fontPath, fontFlags, _, _, _, _, useShadow = MSUF_GetGlobalFontSettings()
        end
        local _, shared = GetAuras2DB()
        local stackSize = (shared and shared.stackTextSize) or 14
        if icon.count and fontPath then
            MSUF_A2_ApplyFont(icon.count, fontPath, stackSize, fontFlags, useShadow)
            icon._msufA2_lastStackTextSize = stackSize
        end
    end


    CreateBorder(icon)

    -- Strong highlight glow (used for "Highlight own buffs/debuffs")
    icon._msufOwnGlow = icon:CreateTexture(nil, "OVERLAY")
    icon._msufOwnGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    icon._msufOwnGlow:SetBlendMode("ADD")
    icon._msufOwnGlow:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon._msufOwnGlow:SetSize(42, 42)
    icon._msufOwnGlow:SetAlpha(0.95)
    icon._msufOwnGlow:Hide()

    -- Register with Masque if enabled
    MSUF_A2_MasqueAddButton(icon, select(2, GetAuras2DB()))

    -- Step 7 perf: assign tooltip scripts once (no per-update SetScript churn)
    if not icon._msufA2_scriptsHooked then
        icon._msufA2_scriptsHooked = true
        icon:SetScript("OnEnter", MSUF_A2_IconOnEnter)
        icon:SetScript("OnLeave", MSUF_A2_IconOnLeave)
        icon:EnableMouse(false)
    end

    icon:Hide()
    container._msufIcons[index] = icon
    return icon
end

-- Shared helper: apply the stack-count anchor styling to an icon's count fontstring.
-- Safe to call repeatedly; it re-anchors only when the anchor setting changes.
local function MSUF_A2_ApplyStackCountAnchorStyle(icon, stackAnchor)
    if not icon or not icon.count then return end

    stackAnchor = stackAnchor or "TOPRIGHT"
    if (not icon._msufCountStyledA2) or (icon._msufA2_lastStackAnchor ~= stackAnchor) then
        icon._msufCountStyledA2 = true
        icon._msufA2_lastStackAnchor = stackAnchor

        local point, relPoint, xOff, yOff, justify
        if stackAnchor == "TOPLEFT" then
            point, relPoint, xOff, yOff, justify = "TOPLEFT", "TOPLEFT", -4, 7, "LEFT"
        elseif stackAnchor == "BOTTOMLEFT" then
            point, relPoint, xOff, yOff, justify = "BOTTOMLEFT", "BOTTOMLEFT", -4, -7, "LEFT"
        elseif stackAnchor == "BOTTOMRIGHT" then
            point, relPoint, xOff, yOff, justify = "BOTTOMRIGHT", "BOTTOMRIGHT", 4, -7, "RIGHT"
        else
            point, relPoint, xOff, yOff, justify = "TOPRIGHT", "TOPRIGHT", 4, 7, "RIGHT"
        end

        icon.count:ClearAllPoints()
        icon.count:SetPoint(point, icon, relPoint, xOff, yOff)
        icon.count:SetJustifyH(justify)
        icon.count:SetTextColor(1, 1, 1, 1)

        -- Shadow is driven by the global font pipeline.
        local useShadow = false
        if type(MSUF_GetGlobalFontSettings) == "function" then
            local _, _, _, _, _, _, sh = MSUF_GetGlobalFontSettings()
            useShadow = (sh == true)
        end
        if useShadow then
            icon.count:SetShadowColor(0, 0, 0, 1)
            icon.count:SetShadowOffset(1, -1)
        else
            icon.count:SetShadowOffset(0, 0)
        end
    end
end

local function HideUnused(container, fromIndex)
    if not container or not container._msufIcons then return end
    for i = fromIndex, #container._msufIcons do
        local icon = container._msufIcons[i]
        if icon then
            -- If this icon is registered with the cooldown text manager, unregister to avoid holding refs.
            if icon._msufA2_cdMgrRegistered == true then
                MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
            end
            icon:Hide()
        end
    end
end

local function LayoutIcons(container, count, iconSize, spacing, perRow, growth, rowWrap)
    if count <= 0 then
        -- Layout stamp reset so next show does a full reflow
        if container then
            container._msufA2_layoutIconSize = nil
            container._msufA2_layoutSpacing = nil
            container._msufA2_layoutPerRow = nil
            container._msufA2_layoutGrowth = nil
            container._msufA2_layoutRowWrap = nil
            container._msufA2_layoutCount = 0
        end
        HideUnused(container, 1)
        return 0
    end

    -- Defensive default: keep old behavior if missing/invalid.
    if rowWrap ~= "UP" and rowWrap ~= "DOWN" then
        rowWrap = "DOWN"
    end

    if not container then
        return 0
    end

    -- avoid a full reflow (ClearAllPoints/SetPoint/SetSize) when layout inputs are unchanged.
    -- In addition, if ONLY the icon count changed, we do a delta-layout:
    --  • count increased: anchor only the newly-used indices
    --  • count decreased: just hide extras (existing points remain valid)
    local oldCount = container._msufA2_layoutCount or 0

    local sameParams = (
        container._msufA2_layoutIconSize == iconSize
        and container._msufA2_layoutSpacing == spacing
        and container._msufA2_layoutPerRow == perRow
        and container._msufA2_layoutGrowth == growth
        and container._msufA2_layoutRowWrap == rowWrap
    )

    if sameParams then
        if oldCount == count then
            -- Nothing changed: ensure the icons exist (no layout work)
            for i = 1, count do
                AcquireIcon(container, i)
            end
            HideUnused(container, count + 1)
            return math.ceil(count / perRow)
        end

        -- Count changed but layout inputs are identical.
        if count > oldCount then
            local stepX = (iconSize + spacing)
            local stepY = (iconSize + spacing)
            local vertical = (growth == "UP" or growth == "DOWN")

            for i = oldCount + 1, count do
                local icon = AcquireIcon(container, i)
                icon:SetSize(iconSize, iconSize)

                local row, col
                if vertical then
                    -- Vertical growth: fill a column first, then wrap into the next column.
                    col = math.floor((i - 1) / perRow)
                    row = (i - 1) % perRow
                else
                    -- Horizontal growth: fill a row first, then wrap into the next row.
                    row = math.floor((i - 1) / perRow)
                    col = (i - 1) % perRow
                end

                local x = stepX * col
                if (not vertical) and growth == "LEFT" then
                    x = -x
                end

                local y
                if vertical then
                    y = stepY * row
                    if growth == "DOWN" then
                        y = -y
                    end
                else
                    if rowWrap == "UP" then
                        y = stepY * row
                    else
                        y = -stepY * row
                    end
                end

                icon:ClearAllPoints()
                icon:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", x, y)
            end
        else
            -- Count shrank: keep existing anchors; just ensure base indices exist.
            for i = 1, count do
                AcquireIcon(container, i)
            end
        end

        container._msufA2_layoutCount = count
        HideUnused(container, count + 1)
        return math.ceil(count / perRow)
    end

    -- Full reflow (layout inputs changed)
    container._msufA2_layoutIconSize = iconSize
    container._msufA2_layoutSpacing = spacing
    container._msufA2_layoutPerRow = perRow
    container._msufA2_layoutGrowth = growth
    container._msufA2_layoutRowWrap = rowWrap
    container._msufA2_layoutCount = count

    local stepX = (iconSize + spacing)
    local stepY = (iconSize + spacing)

    local vertical = (growth == "UP" or growth == "DOWN")

    for i = 1, count do
        local icon = AcquireIcon(container, i)
        -- Only run when layout inputs changed, so always set size + anchors here.
        icon:SetSize(iconSize, iconSize)

        local row, col
        if vertical then
            -- Vertical growth: fill a column first, then wrap into the next column.
            col = math.floor((i - 1) / perRow)
            row = (i - 1) % perRow
        else
            -- Horizontal growth: fill a row first, then wrap into the next row.
            row = math.floor((i - 1) / perRow)
            col = (i - 1) % perRow
        end

        local x = stepX * col
        if (not vertical) and growth == "LEFT" then
            x = -x
        end

        local y
        if vertical then
            y = stepY * row
            if growth == "DOWN" then
                y = -y
            end
        else
            if rowWrap == "UP" then
                y = stepY * row
            else
                y = -stepY * row
            end
        end

        icon:ClearAllPoints()
        icon:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", x, y)
    end

    HideUnused(container, count + 1)
    return math.ceil(count / perRow)
end

-- ------------------------------------------------------------
-- Per-unit attachment
-- ------------------------------------------------------------

AurasByUnit = {}

-- Step 6 perf (cumulative): recycle Dirty tables to reduce GC churn during frequent MarkDirty() calls.
local DirtyPool = {}
local function AcquireDirtyTable()
    local t = DirtyPool[#DirtyPool]
    if t then
        DirtyPool[#DirtyPool] = nil
        return t
    end
    return {}
end
local function ReleaseDirtyTable(t)
    if not t then return end
    wipe(t)
    DirtyPool[#DirtyPool + 1] = t
end

local Dirty = AcquireDirtyTable()
local FlushScheduled = false

local function IsEditModeActive()
    -- We need to treat BOTH Blizzard Edit Mode and MSUF Edit Mode as "edit mode" for previews.
    -- Blizzard Edit Mode:
    if _G.EditModeManagerFrame and _G.EditModeManagerFrame.IsEditModeActive and _G.EditModeManagerFrame:IsEditModeActive() then
        return true
    end

    -- MSUF Edit Mode (preferred / stable signals):
    -- 1) New state object (MSUF_EditState) introduced by MSUF_EditMode.lua
    local st = rawget(_G, "MSUF_EditState")
    if type(st) == "table" and st.active == true then
        return true
    end

    -- 2) Legacy global booleans used by older patches
    if rawget(_G, "MSUF_UnitEditModeActive") == true then
        return true
    end

    -- 3) Exported helper from MSUF_EditMode.lua (exists in current project files)
    local f = rawget(_G, "MSUF_IsInEditMode")
    if type(f) == "function" then
        local ok, v = pcall(f)
        if ok and v == true then
            return true
        end
    end

    -- 4) Compatibility hook name from older experiments (keep as last resort)
    local g = rawget(_G, "MSUF_IsMSUFEditModeActive")
    if type(g) == "function" then
        local ok, v = pcall(g)
        if ok and v == true then
            return true
        end
    end

    return false
end

local function UnitEnabled(unit)
    local a2, _ = GetAuras2DB()
    if not a2 or not a2.enabled then return false end

    if unit == "target" then return a2.showTarget end
    if unit == "focus" then return a2.showFocus end
    if unit and unit:match("^boss%d$") then return a2.showBoss end
    return false
end

local function FindUnitFrame(unit)
    local uf = _G.MSUF_UnitFrames
    if type(uf) == "table" and uf[unit] then
        return uf[unit]
    end
    local g = _G["MSUF_" .. unit]
    if g then return g end
    return nil
end

local function EnsureAttached(unit)
    local entry = AurasByUnit[unit]
    local frame = FindUnitFrame(unit)
    if not frame then
        return nil
    end

    if entry and entry.frame == frame and entry.anchor and entry.anchor:GetParent() then
        return entry
    end

    -- Create anchor (parented to UIParent but anchored to the unitframe so it follows MSUF edit moves)
    local anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetSize(1, 1)
    -- IMPORTANT (showstopper fix): ensure the aura anchor renders ABOVE the unitframe.
    -- Some boss frames (boss3+) can end up with higher frame levels than earlier bosses, which would
    -- cause the UIParent-parented aura anchor to sit *behind* the later boss frames (looks like "no auras").
    -- We therefore match the unitframe's strata and set a safe level offset above it.
    do
        local p = (frame and frame.textFrame) or frame
        local strata = (p and p.GetFrameStrata and p:GetFrameStrata()) or "MEDIUM"
        local lvl = (p and p.GetFrameLevel and p:GetFrameLevel()) or 0
        lvl = tonumber(lvl) or 0
        anchor:SetFrameStrata(strata)
        anchor:SetFrameLevel(lvl + 50)
    end

    local debuffs = CreateFrame("Frame", nil, anchor)
    debuffs:SetSize(1, 1)
    debuffs:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)

    local buffs = CreateFrame("Frame", nil, anchor)
    buffs:SetSize(1, 1)
    buffs:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 30)
    local mixed = CreateFrame("Frame", nil, anchor)
    mixed:SetSize(1, 1)
    mixed:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)

    -- Keep child containers at/above the anchor level so icons are never hidden behind later boss frames.
    do
        local strata = (anchor and anchor.GetFrameStrata and anchor:GetFrameStrata()) or "MEDIUM"
        local base = (anchor and anchor.GetFrameLevel and anchor:GetFrameLevel()) or 0
        base = tonumber(base) or 0
        if debuffs and debuffs.SetFrameStrata then debuffs:SetFrameStrata(strata) end
        if buffs and buffs.SetFrameStrata then buffs:SetFrameStrata(strata) end
        if mixed and mixed.SetFrameStrata then mixed:SetFrameStrata(strata) end
        if debuffs and debuffs.SetFrameLevel then debuffs:SetFrameLevel(base + 1) end
        if buffs and buffs.SetFrameLevel then buffs:SetFrameLevel(base + 1) end
        if mixed and mixed.SetFrameLevel then mixed:SetFrameLevel(base + 1) end
    end

    -- Sync show/hide with the unitframe
    SafeCall(frame.HookScript, frame, "OnShow", function()
        -- Re-sync strata/levels in case the unitframe was rebuilt or its level changed (can happen for bosses).
        if anchor then
            local p = (frame and frame.textFrame) or frame
            local strata = (p and p.GetFrameStrata and p:GetFrameStrata()) or "MEDIUM"
            local lvl = (p and p.GetFrameLevel and p:GetFrameLevel()) or 0
            lvl = tonumber(lvl) or 0
            if anchor.SetFrameStrata then anchor:SetFrameStrata(strata) end
            if anchor.SetFrameLevel then anchor:SetFrameLevel(lvl + 50) end
            local base = (anchor.GetFrameLevel and anchor:GetFrameLevel()) or (lvl + 50)
            base = tonumber(base) or 0
            if debuffs and debuffs.SetFrameStrata then debuffs:SetFrameStrata(strata) end
            if buffs and buffs.SetFrameStrata then buffs:SetFrameStrata(strata) end
            if mixed and mixed.SetFrameStrata then mixed:SetFrameStrata(strata) end
            if debuffs and debuffs.SetFrameLevel then debuffs:SetFrameLevel(base + 1) end
            if buffs and buffs.SetFrameLevel then buffs:SetFrameLevel(base + 1) end
            if mixed and mixed.SetFrameLevel then mixed:SetFrameLevel(base + 1) end
        end

        if anchor then anchor:Show() end
        -- Don't rely on child OnShow scripts (they may already be "shown" while parent is hidden).
        -- Just request a real refresh through the normal coalesced pipeline.
        if type(_G.MSUF_Auras2_RefreshAll) == "function" then
            _G.MSUF_Auras2_RefreshAll()
        end
    end)
    SafeCall(frame.HookScript, frame, "OnHide", function()
        if anchor then anchor:Hide() end
    end)

    entry = {
        unit = unit,
        frame = frame,
        anchor = anchor,
        debuffs = debuffs,
        buffs = buffs,
        mixed = mixed,
    }
    AurasByUnit[unit] = entry
    return entry
end

-- Forward declarations for Auras 2.0 Edit Mode helpers
local MSUF_A2_GetEffectiveSizing
local MSUF_A2_ComputeDefaultEditBoxSize
local MSUF_A2_GetEffectiveLayout

local function UpdateAnchor(entry, shared, offX, offY, boxW, boxH, layoutModeOverride, buffDebuffAnchorOverride, splitSpacingOverride)
    local unitKey = entry and entry.unit
    local iconSize, spacing, perRow, buffOffsetY = MSUF_A2_GetEffectiveSizing(unitKey, shared)
    if not entry or not entry.anchor or not entry.frame or not shared then return end

    local x = offX
    if x == nil then x = shared.offsetX or 0 end
    local y = offY
    if y == nil then y = shared.offsetY or 0 end

    entry.anchor:ClearAllPoints()
    entry.anchor:SetPoint("BOTTOMLEFT", entry.frame, "TOPLEFT", x, y)

    -- Edit-mode mover overlay (Target only for now)
    if entry.editMover then
        entry.editMover:ClearAllPoints()
        entry.editMover:SetPoint("BOTTOMLEFT", entry.frame, "TOPLEFT", x, y)
        if boxW and boxH then
            entry.editMover:SetSize(boxW, boxH)
        end
    end

    local mode = layoutModeOverride or (shared.layoutMode or "SEPARATE")

    -- Mixed single-row layout: use one shared container (entry.mixed)
    if mode == "SINGLE" and entry.mixed then
        entry.mixed:ClearAllPoints()
        entry.mixed:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)

        -- Keep legacy containers positioned but they will be hidden/unused in render.
        entry.debuffs:ClearAllPoints()
        entry.debuffs:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)

        entry.buffs:ClearAllPoints()
        entry.buffs:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)
        return
    end

    -- Extra spacing used only for split-anchor modes (how far the blocks are pushed away from the unitframe).
    -- Default 0 preserves existing behavior.
    local splitSpacing = splitSpacingOverride
    if type(splitSpacing) ~= "number" then splitSpacing = shared.splitSpacing end
    if type(splitSpacing) ~= "number" then splitSpacing = 0 end
    if splitSpacing < 0 then splitSpacing = 0 end
    if splitSpacing > 80 then splitSpacing = 80 end

    local function AnchorToFrame(container, relPoint, dx, dy)
        container:ClearAllPoints()
        container:SetPoint("BOTTOMLEFT", entry.frame, relPoint, dx, dy)
    end

    local function AnchorAbove(container)
        AnchorToFrame(container, "TOPLEFT", x, y + splitSpacing)
    end

    local function AnchorBelow(container)
        AnchorToFrame(container, "BOTTOMLEFT", x, y - iconSize - splitSpacing)
    end

    local function AnchorRightCentered(container)
        -- Container uses BOTTOMLEFT. To center a single row on the unitframe's RIGHT edge,
        -- offset down by half an icon so the row midpoint matches the frame edge midpoint.
        AnchorToFrame(container, "RIGHT", x + splitSpacing, y - (iconSize * 0.5))
    end

    local function AnchorLeftCentered(container)
        -- Move left by one icon width so the first icon sits fully outside the frame.
        AnchorToFrame(container, "LEFT", x - iconSize - splitSpacing, y - (iconSize * 0.5))
    end

    local anchorMode = buffDebuffAnchorOverride or (shared.buffDebuffAnchor or "STACKED")

    -- Default: fixed Razor-ish spacing (buffs above debuffs) within the shared anchor (legacy behavior)
    local by = buffOffsetY

    if anchorMode == "STACKED" or anchorMode == nil then
        entry.debuffs:ClearAllPoints()
        entry.debuffs:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)

        entry.buffs:ClearAllPoints()
        entry.buffs:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, by)

        if entry.mixed then
            entry.mixed:ClearAllPoints()
            entry.mixed:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)
        end
        return
    end

    -- Split anchors (Blizzard-like around the unitframe)
    entry.debuffs:ClearAllPoints()
    entry.buffs:ClearAllPoints()

    if anchorMode == "TOP_BOTTOM_BUFFS" then
        AnchorAbove(entry.buffs)
        AnchorBelow(entry.debuffs)
    elseif anchorMode == "TOP_BOTTOM_DEBUFFS" then
        AnchorAbove(entry.debuffs)
        AnchorBelow(entry.buffs)
    elseif anchorMode == "TOP_RIGHT_BUFFS" then
        AnchorAbove(entry.buffs)
        AnchorRightCentered(entry.debuffs)
    elseif anchorMode == "TOP_RIGHT_DEBUFFS" then
        AnchorAbove(entry.debuffs)
        AnchorRightCentered(entry.buffs)
    elseif anchorMode == "BOTTOM_RIGHT_BUFFS" then
        AnchorBelow(entry.buffs)
        AnchorRightCentered(entry.debuffs)
    elseif anchorMode == "BOTTOM_RIGHT_DEBUFFS" then
        AnchorBelow(entry.debuffs)
        AnchorRightCentered(entry.buffs)
    elseif anchorMode == "BOTTOM_LEFT_BUFFS" then
        AnchorBelow(entry.buffs)
        AnchorLeftCentered(entry.debuffs)
    elseif anchorMode == "BOTTOM_LEFT_DEBUFFS" then
        AnchorBelow(entry.debuffs)
        AnchorLeftCentered(entry.buffs)
    elseif anchorMode == "TOP_LEFT_BUFFS" then
        AnchorAbove(entry.buffs)
        AnchorLeftCentered(entry.debuffs)
    elseif anchorMode == "TOP_LEFT_DEBUFFS" then
        AnchorAbove(entry.debuffs)
        AnchorLeftCentered(entry.buffs)
    else
        -- Unknown value -> fallback
        entry.debuffs:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)
        entry.buffs:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, by)
    end

    if entry.mixed then
        entry.mixed:ClearAllPoints()
        entry.mixed:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)
    end

end

-- ---------------------------------------------------------
-- Edit Mode: Aura anchor mover (Target first)
-- ---------------------------------------------------------
MSUF_A2_GetEffectiveSizing = function(unitKey, shared)
    local iconSize = (shared and shared.iconSize) or 26
    local spacing  = (shared and shared.spacing) or 2
    local perRow   = (shared and shared.perRow) or 12
    local buffOffsetY = (shared and shared.buffOffsetY)

    -- Per-unit cap overrides (menu-level): Icons per row
    if MSUF_DB and MSUF_DB.auras2 and MSUF_DB.auras2.perUnit and unitKey then
        local u2 = MSUF_DB.auras2.perUnit[unitKey]
        if u2 and u2.overrideSharedLayout == true and type(u2.layoutShared) == 'table' then
            if type(u2.layoutShared.perRow) == 'number' and u2.layoutShared.perRow >= 1 then
                perRow = u2.layoutShared.perRow
            end
        end
    end

    -- Per-unit layout overrides (Edit Mode popup)
    if MSUF_DB and MSUF_DB.auras2 and MSUF_DB.auras2.perUnit and unitKey then
        local u = MSUF_DB.auras2.perUnit[unitKey]
        if u and u.overrideLayout == true and type(u.layout) == 'table' then
            if type(u.layout.iconSize) == 'number' and u.layout.iconSize > 1 then
                iconSize = u.layout.iconSize
            end
            if type(u.layout.spacing) == 'number' and u.layout.spacing >= 0 then
                spacing = u.layout.spacing
            end
            if type(u.layout.perRow) == 'number' and u.layout.perRow >= 1 then
                perRow = u.layout.perRow
            end
            if type(u.layout.buffOffsetY) == 'number' then
                buffOffsetY = u.layout.buffOffsetY
            end
        end
    end

    -- Fallback row gap (buffs above debuffs)
    if buffOffsetY == nil then
        buffOffsetY = iconSize + spacing + 4
    end

    return iconSize, spacing, perRow, buffOffsetY
end

MSUF_A2_ComputeDefaultEditBoxSize = function(unitKey, shared)
    local iconSize, spacing, perRow, buffOffsetY = MSUF_A2_GetEffectiveSizing(unitKey, shared)

    local w = (perRow * iconSize) + (math.max(0, perRow - 1) * spacing)
    local h = math.max(iconSize, buffOffsetY + iconSize)
    return w, h
end

MSUF_A2_GetEffectiveLayout = function(unitKey, shared)
    local x = (shared and shared.offsetX) or 0
    local y = (shared and shared.offsetY) or 0

    local boxW, boxH
    if MSUF_DB and MSUF_DB.auras2 and MSUF_DB.auras2.perUnit then
        local u = MSUF_DB.auras2.perUnit[unitKey]
        if u and u.overrideLayout == true and type(u.layout) == "table" then
            if type(u.layout.offsetX) == "number" then x = u.layout.offsetX end
            if type(u.layout.offsetY) == "number" then y = u.layout.offsetY end
            if type(u.layout.width) == "number" and u.layout.width > 1 then boxW = u.layout.width end
            if type(u.layout.height) == "number" and u.layout.height > 1 then boxH = u.layout.height end
        end
    end

    -- Default edit box size (used for the Edit Mode mover)
    local defW, defH = MSUF_A2_ComputeDefaultEditBoxSize(unitKey, shared)
    if type(boxW) ~= "number" then boxW = defW end
    if type(boxH) ~= "number" then boxH = defH end

    return x, y, boxW, boxH
end


-- ------------------------------------------------------------
-- Auras2 Edit Mode mover (Target / Focus / Boss)
-- ------------------------------------------------------------
-- NOTE:
--  * RenderUnit() is the source of truth for showing/hiding the mover (Edit Mode preview only).
--  * The mover exists only to drag the per-unit Aura anchor offsets without opening Blizzard Edit Mode.

local function MSUF_A2_EnsureEditMover(entry, unitKey, labelText)
    if not entry or not unitKey then return end
    if entry.editMover then return end

    local moverName = "MSUF_Auras2_" .. (tostring(unitKey):gsub("%W", "")) .. "EditMover"
    local mover = CreateFrame("Frame", moverName, UIParent, "BackdropTemplate")
    mover:SetFrameStrata("DIALOG")
    mover:SetFrameLevel(500)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(true)

    mover:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    mover:SetBackdropColor(0.20, 0.65, 1.00, 0.12)
    mover:SetBackdropBorderColor(0.20, 0.65, 1.00, 0.55)

    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", mover, "TOPLEFT", 6, -4)
    label:SetText(labelText or (tostring(unitKey) .. " Auras"))
    label:SetTextColor(0.95, 0.95, 0.95, 0.85)
    mover._msufLabel = label

    mover:Hide()

    mover._msufAuraEntry = entry
    mover._msufAuraUnitKey = unitKey

    local function IsAnyPopupOpen()
        local st = rawget(_G, "MSUF_EditState")
        if not (st and st.popupOpen) then
            return false
        end

        -- Auras2 special-case: allow dragging the Aura mover while the Auras2 Position Popup is open.
        -- Otherwise you must close the popup to move the auras, which feels broken.
        local ap = _G.MSUF_Auras2PositionPopup
        if ap and ap.IsShown and ap:IsShown() then
            return false
        end

        return true
    end

    local function GetCursorScaled()
        local scale = (UIParent and UIParent.GetEffectiveScale) and UIParent:GetEffectiveScale() or 1
        local cx, cy = GetCursorPosition()
        return cx / scale, cy / scale
    end

    local function ApplyDragDelta(self, dx, dy)
        if InCombatLockdown and InCombatLockdown() then return end

        local key = self._msufAuraUnitKey or unitKey
        EnsureDB()

        local a2 = (MSUF_DB and MSUF_DB.auras2) or nil
        if not a2 then return end
        a2.shared = (type(a2.shared) == "table") and a2.shared or {}
        a2.perUnit = (type(a2.perUnit) == "table") and a2.perUnit or {}

        local shared = a2.shared or {}
        local isBoss = (type(key) == "string" and key:match("^boss%d+$")) and true or false
        local bossTogether = (isBoss and (shared.bossEditTogether ~= false)) and true or false

        local startX = (type(self._msufDragStartOffsetX) == "number") and self._msufDragStartOffsetX or 0
        local startY = (type(self._msufDragStartOffsetY) == "number") and self._msufDragStartOffsetY or 0
        local newX = math.floor(startX + dx + 0.5)
        local newY = math.floor(startY + dy + 0.5)

        local function ApplyToUnit(k)
            local u = a2.perUnit[k]
            if type(u) ~= "table" then
                u = {}
                a2.perUnit[k] = u
            end
            if u.overrideLayout ~= true then u.overrideLayout = true end
            if type(u.layout) ~= "table" then u.layout = {} end
            u.layout.offsetX = newX
            u.layout.offsetY = newY
        end

        if bossTogether then
            for i = 1, 5 do
                ApplyToUnit("boss" .. i)
            end
            -- Live update all boss anchors while dragging (so they move together)
            for i = 1, 5 do
                local k = "boss" .. i
                local e = AurasByUnit and AurasByUnit[k]
                if e then
                    local x, y, boxW, boxH = MSUF_A2_GetEffectiveLayout(k, shared)
                    UpdateAnchor(e, shared, x, y, boxW, boxH)
                end
            end
        else
            ApplyToUnit(key)
            local e = self._msufAuraEntry
            if e then
                local x, y, boxW, boxH = MSUF_A2_GetEffectiveLayout(key, shared)
                UpdateAnchor(e, shared, x, y, boxW, boxH)
            end
        end

        -- Live sync popup fields (throttled)
        if _G.MSUF_SyncAuras2PositionPopup then
            local now = GetTime and GetTime() or 0
            if not self._msufLastPopupSync or (now - self._msufLastPopupSync) > 0.05 then
                self._msufLastPopupSync = now
                _G.MSUF_SyncAuras2PositionPopup(key)
            end
        end
    end

    mover:SetScript("OnMouseDown", function(self, button)
        if not IsEditModeActive() then return end
        if button ~= "LeftButton" then return end
        if IsAnyPopupOpen() then return end
        if InCombatLockdown and InCombatLockdown() then return end

        EnsureDB()
        local a2 = (MSUF_DB and MSUF_DB.auras2) or nil
        if not a2 then return end
        local shared = a2.shared or {}

        local key = self._msufAuraUnitKey or unitKey
        local x, y = MSUF_A2_GetEffectiveLayout(key, shared)

        self._msufDragDown = true
        self._msufDragMoved = false
        self._msufDragStartX, self._msufDragStartY = GetCursorScaled()
        self._msufDragStartOffsetX = x
        self._msufDragStartOffsetY = y

        self:SetScript("OnUpdate", function(me)
            if not me._msufDragDown then return end
            local cx, cy = GetCursorScaled()
            local dx = cx - (me._msufDragStartX or cx)
            local dy = cy - (me._msufDragStartY or cy)

            if not me._msufDragMoved then
                if (dx * dx + dy * dy) >= 9 then -- 3px threshold
                    me._msufDragMoved = true
                else
                    return
                end
            end

            ApplyDragDelta(me, dx, dy)
        end)
    end)

    mover:SetScript("OnMouseUp", function(self, button)
        if not IsEditModeActive() then return end

        local key = self._msufAuraUnitKey or unitKey

        if button == "LeftButton" then
            local moved = (self._msufDragMoved == true)
            self._msufDragDown = false
            self:SetScript("OnUpdate", nil)

            if not moved and _G.MSUF_OpenAuras2PositionPopup then
                _G.MSUF_OpenAuras2PositionPopup(key, self)
            end
            return
        end

        if button == "RightButton" and _G.MSUF_OpenAuras2PositionPopup then
            _G.MSUF_OpenAuras2PositionPopup(key, self)
        end
    end)

    entry.editMover = mover
end

-- Convenience wrappers (kept for readability)
local function MSUF_A2_EnsureTargetEditMover(entry)
    if not entry or entry.unit ~= "target" then return end
    return MSUF_A2_EnsureEditMover(entry, "target", "Target Auras")
end

local function MSUF_A2_EnsureFocusEditMover(entry)
    if not entry or entry.unit ~= "focus" then return end
    return MSUF_A2_EnsureEditMover(entry, "focus", "Focus Auras")
end

local function MSUF_A2_EnsureBossEditMover(entry)
    if not entry or type(entry.unit) ~= "string" then return end
    local u = entry.unit
    local n = u:match("^boss(%d+)$")
    if not n then return end
    return MSUF_A2_EnsureEditMover(entry, u, "Boss " .. n .. " Auras")
end

-- ------------------------------------------------------------
-- Aura data + update
-- ------------------------------------------------------------
-- ------------------------------------------------------------

local function GetAuraList(unit, filter, onlyPlayer)
    -- filter: "HELPFUL" or "HARMFUL"
    -- onlyPlayer: try to request player-only ids via filter flag, but fall back safely.
    --
    -- PERF: Avoid per-aura pcall/SafeCall in the inner loop. We guard the list fetch with pcall,
    -- then guard the entire data-build loop with a single pcall.
    if not unit or not C_UnitAuras then
        return {}
    end

    local getIDs  = C_UnitAuras.GetUnitAuraInstanceIDs
    local getData = C_UnitAuras.GetAuraDataByAuraInstanceID
    if type(getIDs) ~= "function" or type(getData) ~= "function" then
        return {}
    end

    local ids

    if onlyPlayer then
        local ok, res = pcall(getIDs, unit, filter .. "|PLAYER")
        if ok and type(res) == "table" then
            ids = res
        else
            ok, res = pcall(getIDs, unit, filter)
            if ok and type(res) == "table" then
                ids = res
            end
        end
    else
        local ok, res = pcall(getIDs, unit, filter)
        if ok and type(res) == "table" then
            ids = res
        end
    end

    if type(ids) ~= "table" then
        return {}
    end

    local out = {}

    local okLoop = pcall(function()
        for i = 1, #ids do
            local id = ids[i]
            local data = getData(unit, id)
            if type(data) == "table" then
                data._msufAuraInstanceID = id
                out[#out+1] = data
            end
        end
    end)

    if not okLoop then
        return {}
    end

    return out
end


-- Build a set of auraInstanceIDs for a unit that belong to the player (or player pet),
-- using filter flags only. This is robust in combat and avoids reading aura fields.
local function MSUF_A2_GetPlayerAuraIdSet(unit, filter)
    if not unit or not C_UnitAuras or type(C_UnitAuras.GetUnitAuraInstanceIDs) ~= "function" then
        return nil
    end

    local ids = SafeCall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, filter .. "|PLAYER")
    if type(ids) ~= "table" then
        return nil
    end

    local set = {}
    for i = 1, #ids do
        local okK, k = pcall(tostring, ids[i])
        if okK and k then
            set[k] = true
        end
    end
    return set
end

-- NOTE: In Midnight/Beta, many aura fields can be "secret values".
-- Helpers below must stay secret-safe (no boolean-tests on aura fields; convert via tostring + compare).
local function MSUF_A2_StringIsTrue(s)
    -- Secret-safe truthy check (avoid direct string comparisons).
    if s == nil then return false end

    local ok1, b1 = pcall(string.byte, s, 1)
    if not ok1 or b1 == nil then return false end

    -- "1"
    if b1 == 49 then
        local ok5, b5 = pcall(string.byte, s, 2)
        if ok5 and b5 == nil then return true end
        return true -- tolerate "1..." defensively
    end

    -- "true" / "True"
    if b1 ~= 116 and b1 ~= 84 then return false end
    local ok2, b2 = pcall(string.byte, s, 2)
    local ok3, b3 = pcall(string.byte, s, 3)
    local ok4, b4 = pcall(string.byte, s, 4)
    if not ok2 or not ok3 or not ok4 then return false end
    if b2 == nil or b3 == nil or b4 == nil then return false end

    local is_r = (b2 == 114) or (b2 == 82)
    local is_u = (b3 == 117) or (b3 == 85)
    local is_e = (b4 == 101) or (b4 == 69)
    if not (is_r and is_u and is_e) then return false end

    -- Strict-ish: require no 5th character when possible.
    local ok5, b5 = pcall(string.byte, s, 5)
    if ok5 and b5 ~= nil then
        -- allow "true" with suffixes (defensive); but still treat as true
        return true
    end
    return true
end


-- Secret-safe ASCII-lower hash for short tokens (avoids string equality on potential secret values).
-- We use this for sourceUnit and dispel type checks.
local function MSUF_A2_HashAsciiLower(s)
    if type(s) ~= "string" then return 0 end
    local h = 5381
    -- token strings are tiny; cap loop to avoid worst-case costs on weird inputs
    for i = 1, 32 do
        local okB, b = pcall(string.byte, s, i)
        if not okB or b == nil then break end
        -- A-Z -> a-z (ASCII)
        if b >= 65 and b <= 90 then
            b = b + 32
        end
        h = (h * 33 + b) % 2147483647
    end
    return h
end

local MSUF_A2_HASH_PLAYER  = MSUF_A2_HashAsciiLower("player")
local MSUF_A2_HASH_PET     = MSUF_A2_HashAsciiLower("pet")
local MSUF_A2_HASH_VEHICLE = MSUF_A2_HashAsciiLower("vehicle")

local MSUF_A2_HASH_MAGIC   = MSUF_A2_HashAsciiLower("magic")
local MSUF_A2_HASH_CURSE   = MSUF_A2_HashAsciiLower("curse")
local MSUF_A2_HASH_DISEASE = MSUF_A2_HashAsciiLower("disease")
local MSUF_A2_HASH_POISON  = MSUF_A2_HashAsciiLower("poison")
local MSUF_A2_HASH_ENRAGE  = MSUF_A2_HashAsciiLower("enrage")

-- Secret-safe check for numeric "0" / "0.0" / "0.00" strings.
-- Used for "Hide permanent buffs": we ONLY hide when an API explicitly reports a 0 duration.
local function MSUF_A2_StringIsZeroNumber(s)
    if s == nil then return false end
    local okTrim, t = pcall(function()
        -- trim spaces without pattern magic
        local x = s
        x = x:gsub("^%s+", "")
        x = x:gsub("%s+$", "")
        return x
    end)
    if not okTrim or type(t) ~= "string" then return false end

    -- Match: 0, 0.0, 0.00, 00.000 etc
    local okM, m = pcall(string.match, t, "^0+%.?0*$")
    return (okM and m ~= nil) or false
end

local function MSUF_A2_AuraFieldToString(aura, field)
    local ok, v = pcall(function()
        return aura and aura[field]
    end)
    if not ok then return nil end
    if v == nil then return nil end

    local okS, s = pcall(tostring, v)
    if not okS or type(s) ~= "string" then return nil end

    -- Secret-safe empty-string check: string.byte(s,1) returns nil if empty.
    local okB, b1 = pcall(string.byte, s, 1)
    if not okB or b1 == nil then return nil end

    return s
end

local function MSUF_A2_AuraFieldIsTrue(aura, field)
    local s = MSUF_A2_AuraFieldToString(aura, field)
    if not s then return false end
    return MSUF_A2_StringIsTrue(s)
end

local function MSUF_A2_IsBossAura(aura)
    -- isBossAura is often a boolean, but treat it as string to stay secret-safe.
    local s = MSUF_A2_AuraFieldToString(aura, "isBossAura")
    if not s then return false end
    return MSUF_A2_StringIsTrue(s)
end

local function MSUF_A2_MergeBossAuras(playerList, fullList)
    -- Return a list that contains all player auras, plus any boss auras from fullList.
    -- Dedupe by auraInstanceID (stringified).
    if type(playerList) ~= "table" then playerList = {} end
    if type(fullList) ~= "table" then fullList = {} end

    local out = {}
    local seen = {}

    for i = 1, #playerList do
        local aura = playerList[i]
        out[#out+1] = aura
        local aid
        local ok, v = pcall(function()
            return aura and (aura._msufAuraInstanceID or aura.auraInstanceID)
        end)
        if ok then aid = v end
        if type(aid) ~= "nil" then
            local okS, k = pcall(tostring, aid)
            if okS and k then seen[k] = true end
        end
    end

    for i = 1, #fullList do
        local aura = fullList[i]
        if aura and MSUF_A2_IsBossAura(aura) then
            local aid
            local ok, v = pcall(function()
                return aura and (aura._msufAuraInstanceID or aura.auraInstanceID)
            end)
            if ok then aid = v end

            local skip = false
            if type(aid) ~= "nil" then
                local okS, k = pcall(tostring, aid)
                if okS and k and seen[k] then
                    skip = true
                elseif okS and k then
                    seen[k] = true
                end
            end

            if not skip then
                out[#out+1] = aura
            end
        end
    end

    return out
end


-- Additive "extras" helpers (secret-safe; API-only for dispellable checks)
local function MSUF_A2_IsStealableAura(aura)
    if not aura then return false end
    return MSUF_A2_AuraFieldIsTrue(aura, "isStealable")
        or MSUF_A2_AuraFieldIsTrue(aura, "isPurgeable")
        or MSUF_A2_AuraFieldIsTrue(aura, "canStealOrPurge")
end

local function MSUF_A2_IsDispellableAura(unit, aura)
    if not (unit and aura) then return false end
    local auraInstanceID = aura._msufAuraInstanceID or aura.auraInstanceID
    if not (C_UnitAuras and type(C_UnitAuras.GetAuraDispelTypeColor) == "function") then
        return false
    end

    local ok, c1, c2, c3 = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, auraInstanceID, 0)
    if not ok then
        return false
    end
    if type(c1) == "table" then
        return true
    end
    if type(c1) == "number" and type(c2) == "number" and type(c3) == "number" then
        return true
    end
    return false
end

-- Merge two aura lists, keeping primary order first, and de-duping by auraInstanceID.
local function MSUF_A2_MergeAuraLists(primary, secondary)
    if type(primary) ~= "table" then primary = {} end
    if type(secondary) ~= "table" then secondary = {} end

    local out = {}
    local seen = {}

    local function AddList(list)
        for i = 1, #list do
            local aura = list[i]
            if aura then
                local aid
                local ok, v = pcall(function()
                    return aura and (aura._msufAuraInstanceID or aura.auraInstanceID)
                end)
                if ok then aid = v end

                local skip = false
                if type(aid) ~= "nil" then
                    local okS, k = pcall(tostring, aid)
                    if okS and k and seen[k] then
                        skip = true
                    elseif okS and k then
                        seen[k] = true
                    end
                end

                if not skip then
                    out[#out+1] = aura
                end
            end
        end
    end

    AddList(primary)
    AddList(secondary)
    return out
end

-- Advanced filter evaluation (Target-only for now):
-- eff = { includeStealable=false, includeDispellable=false, ... }
local function SetDispelBorder(icon, unit, aura, isHelpful, shared, allowHighlights, isOwn)
    if not icon or not icon._msufBorder then return end

    -- Shared config can be passed in by the caller (fast-path).
    if not shared then
        local _, s = GetAuras2DB()
        shared = s
    end

    local masqueOn = (shared and shared.masqueEnabled == true and MSUF_MasqueAuras2) and true or false

    local auraInstanceID = aura and (aura._msufAuraInstanceID or aura.auraInstanceID)

    local function ShowBorder(r, g, b, a)
        icon._msufBorder:Show()
        icon._msufBorder:SetBackdropBorderColor(r or 0, g or 0, b or 0, a or 1)
    end

    local function HideBaseBorder()
        if masqueOn then
            icon._msufBorder:Hide()
        else
            ShowBorder(0, 0, 0, 1)
        end
    end

    -- Always reset glow each update.
    if icon._msufOwnGlow then icon._msufOwnGlow:Hide() end

    -- Own-aura highlight is independent of filtering.
    if isOwn and shared then
        if isHelpful and (shared.highlightOwnBuffs == true) then
            local r, g, b = MSUF_A2_GetOwnBuffHighlightRGB()
            ShowBorder(r, g, b, 1)
            if icon._msufOwnGlow then
                icon._msufOwnGlow:SetVertexColor(r, g, b, 1)
                icon._msufOwnGlow:Show()
            end
            return
        elseif (not isHelpful) and (shared.highlightOwnDebuffs == true) then
            local r, g, b = MSUF_A2_GetOwnDebuffHighlightRGB()
            ShowBorder(r, g, b, 1)
            if icon._msufOwnGlow then
                icon._msufOwnGlow:SetVertexColor(r, g, b, 1)
                icon._msufOwnGlow:Show()
            end
            return
        end
    end

    -- If filters are disabled, advanced highlights should not apply.
    if allowHighlights ~= true then
        HideBaseBorder()
        return
    end

    -- Buffs: optionally highlight stealable/purgeable buffs.
    if isHelpful then
        if shared and shared.highlightStealableBuffs == true then
            local stealable = false
            do
                -- Prefer fresh API data by auraInstanceID (more consistent across units in Midnight).
                local aid = auraInstanceID
                local data
                if unit and aid and C_UnitAuras and type(C_UnitAuras.GetAuraDataByAuraInstanceID) == "function" then
                    local okD, d = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, aid)
                    if okD and type(d) == "table" then
                        data = d
                    end
                end

                local a = data or aura
                if a then
                    stealable = MSUF_A2_AuraFieldIsTrue(a, 'isStealable')
                        or MSUF_A2_AuraFieldIsTrue(a, 'isPurgeable')
                        or MSUF_A2_AuraFieldIsTrue(a, 'canStealOrPurge')
                end
            end

            if stealable then
                local r, g, b = MSUF_A2_GetStealableBorderRGB()
                ShowBorder(r, g, b, 1)
                return
            end
        end

        HideBaseBorder()
        return
    end

    -- Debuffs: only highlight dispellable debuffs if the toggle is on.
    if not (shared and shared.highlightDispellableDebuffs == true) then
        HideBaseBorder()
        return
    end

    -- Prefer the UnitAuras API (no aura-table reads / no secret comparisons).
    if unit and C_UnitAuras and type(C_UnitAuras.GetAuraDispelTypeColor) == 'function' then
        local ok, c1, c2, c3 = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, auraInstanceID, 0)
        if ok then
            local rr, gg, bb
            if type(c1) == 'table' then
                if type(c1.GetRGB) == 'function' then
                    local okRGB, r1, g1, b1 = pcall(c1.GetRGB, c1)
                    if okRGB then rr, gg, bb = r1, g1, b1 end
                else
                    rr = c1.r or c1[1]
                    gg = c1.g or c1[2]
                    bb = c1.b or c1[3]
                end
            elseif type(c1) == 'number' and type(c2) == 'number' and type(c3) == 'number' then
                rr, gg, bb = c1, c2, c3
            end

            if rr and gg and bb then
                local cr, cg, cb = MSUF_A2_GetDispelBorderRGB()
                ShowBorder(cr, cg, cb, 1)
                return
            end
        end
    end

    -- If we can't query via UnitAuras, keep border hidden/black.
    HideBaseBorder()
end


local function MSUF_A2_AuraHasExpiration(unit, aura)
    -- IMPORTANT:
    -- Under Midnight/Beta, aura.duration / aura.expirationTime can be secret (and/or appear as 0).
    -- We MUST avoid any boolean/arithmetic tests on those fields.
    --
    -- Goal for "Hide permanent buffs":
    -- Only hide when we can safely determine the aura truly has NO expiration time.
    -- If we are unsure (API unavailable / pcall fails), we default to "has expiration" so timed buffs
    -- are never accidentally hidden.
    if not aura then return true end

    local auraInstanceID = aura._msufAuraInstanceID or aura.auraInstanceID
    if not auraInstanceID then
        -- No ID => cannot ask UnitAuras helpers. Assume expiring to avoid accidental hides.
        return true
    end

    -- 1) Best signal: explicit API helper.
    if C_UnitAuras and type(C_UnitAuras.DoesAuraHaveExpirationTime) == "function" then
        local ok, v = pcall(C_UnitAuras.DoesAuraHaveExpirationTime, unit, auraInstanceID)
        if ok then
            -- Never return v directly (it may be a secret boolean). Convert to a safe string first.
            local okS, s = pcall(tostring, v)
            if okS and s then
                if MSUF_A2_StringIsTrue(s) then
                    return true
                end

                -- Treat "0"/"false"/nil as false in a secret-safe way
                local okB1, b1 = pcall(string.byte, s, 1)
                if okB1 and b1 then
                    -- "0"
                    if b1 == 48 then
                        return false
                    end
                    -- "f" / "F" (false)
                    if b1 == 102 or b1 == 70 then
                        return false
                    end
                end
            end
        end
    end

    -- NOTE:
    -- We intentionally DO NOT treat a Duration Object as proof of expiration time.
    -- In combat (especially on focus/boss), the API can return a non-nil duration object even for
    -- permanent buffs, which would cause "Hide permanent buffs" to fail.
    -- We rely on DoesAuraHaveExpirationTime / explicit duration==0 signals below.

    -- 2) "Hide permanent buffs" should be STRICT: only hide when an API explicitly reports duration == 0.
    -- This avoids hiding timed buffs that may report as "unknown" under secret values (especially in combat).
    local function TryGetSpellID()
        local raw = nil
        local okRaw = pcall(function()
            raw = aura.spellId or aura.spellID or aura.spellid
        end)
        if not okRaw or raw == nil then
            -- Fallback: ask UnitAuras for full data (API-only, secret-safe access path)
            if C_UnitAuras and type(C_UnitAuras.GetAuraDataByAuraInstanceID) == "function" then
                local okData, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, auraInstanceID)
                if okData and type(data) == "table" then
                    local ok2 = pcall(function()
                        raw = data.spellId or data.spellID or data.spellid
                    end)
                end
            end
        end
        if raw == nil then return nil end
        local okS, s = pcall(tostring, raw)
        if not okS or type(s) ~= "string" then return nil end
        local okN, n = pcall(tonumber, s)
        if not okN then return nil end
        return n
    end

    -- Prefer base duration when possible.
    if C_UnitAuras and type(C_UnitAuras.GetAuraBaseDuration) == "function" then
        local spellID = TryGetSpellID()
        if spellID then
            local okBD, bd = pcall(C_UnitAuras.GetAuraBaseDuration, unit, auraInstanceID, spellID)
            if okBD and bd ~= nil then
                local okS, s = pcall(tostring, bd)
                if okS and MSUF_A2_StringIsZeroNumber(s) then
                    return false
                end
                return true
            end
        end
    end

    -- Fallback: direct duration query (some builds may not support GetAuraBaseDuration).
    if C_UnitAuras and type(C_UnitAuras.GetAuraDuration) == "function" then
        local okD, d = pcall(C_UnitAuras.GetAuraDuration, unit, auraInstanceID)
        if okD and d ~= nil then
            local okS, s = pcall(tostring, d)
            if okS and MSUF_A2_StringIsZeroNumber(s) then
                return false
            end
            return true
        end
    end

    -- 3) Unknown => treat as NON-expiring.
    -- The user's expectation for "Hide permanent buffs" is that it should also hide buffs that don't provide
    -- duration info (nil/unknown) on certain units in combat (focus/boss). Timed buffs are protected above
    -- by the Duration Object check.
    return false
end

-- Cooldown helper (secret-safe): use Duration Objects only (no legacy Remaining* APIs).
local function MSUF_A2_TrySetCooldownFromAura(icon, unit, aura)
    if not icon or not icon.cooldown or not aura then return false end

    local auraInstanceID = aura._msufAuraInstanceID or aura.auraInstanceID

    -- Prefer duration objects ONLY (no arithmetic/numeric fallbacks).
    local function TryApplyDurationObject(obj)
        if obj == nil then return false end

        -- Newer APIs
        if type(icon.cooldown.SetCooldownFromDurationObject) == "function" then
            local ok = pcall(icon.cooldown.SetCooldownFromDurationObject, icon.cooldown, obj)
            if ok then return true end
        end
        if type(icon.cooldown.SetTimerDuration) == "function" then
            local ok = pcall(icon.cooldown.SetTimerDuration, icon.cooldown, obj)
            if ok then return true end
        end

        return false
    end


    if C_UnitAuras and type(C_UnitAuras.GetAuraDuration) == "function" then
        local okGet, obj = pcall(C_UnitAuras.GetAuraDuration, unit, auraInstanceID)
        if okGet and TryApplyDurationObject(obj) then
            -- Cache the Duration Object for the shared manager (no remaining-time arithmetic).
            icon._msufA2_cdDurationObj = obj
            icon.cooldown._msufA2_durationObj = obj

            -- Register this icon for centralized cooldown text color updates.
            MSUF_A2_CooldownTextMgr_RegisterIcon(icon)
            return true
        end
    end

    -- Clear cached state + unregister if we can't apply a timer.
    icon._msufA2_cdDurationObj = nil
    if icon.cooldown then
        icon.cooldown._msufA2_durationObj = nil
    end
    if icon._msufA2_cdMgrRegistered == true then
        MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
    end
    return false
end

local function ApplyAuraToIcon(icon, unit, aura, shared, isHelpful, hidePermanentOverride, allowHighlights, isOwn, stackAnchorOverride)
    if not icon or not aura then return end

    icon._msufUnit = unit
    -- Clear preview tooltip metadata (icons are recycled)
    icon._msufA2_isPreview = nil
    icon._msufA2_previewKind = nil
    icon._msufAuraInstanceID = aura._msufAuraInstanceID or aura.auraInstanceID
    icon._msufSpellId = aura.spellId
    local newFilter = isHelpful and "HELPFUL" or "HARMFUL"
    if icon._msufFilter ~= newFilter then
        icon._msufFilter = newFilter
    end
    -- Texture updates must be secret-safe: texture handles can be "secret" and cannot be compared.
    -- We only touch the texture when the auraInstanceID bound to this icon changes.
    local auraInstanceID = icon._msufAuraInstanceID
    if auraInstanceID ~= nil and icon._msufA2_lastVisualAuraInstanceID ~= auraInstanceID then
        icon._msufA2_lastVisualAuraInstanceID = auraInstanceID
        local newTex = aura.icon
        if newTex ~= nil and icon.tex then
            icon.tex:SetTexture(newTex)
        end
    end
    -- Stacks (secret-safe, API-only):
    -- Use C_UnitAuras.GetAuraApplicationDisplayCount to get a pre-formatted display string (e.g. "2", "99+").
    -- We DO NOT read aura.applications/stacks and we DO NOT do numeric comparisons (secret-safe).
    local stackShown = false

    -- Live-apply text sizes from per-unit popup (stacks + cooldown text). Font face/outline/shadow follow global font settings.
    do
        local stackSize, cooldownSize = MSUF_A2_GetEffectiveTextSizes(unit, shared)

        local fontPath, fontFlags, _, _, _, _, useShadow
        if type(MSUF_GetGlobalFontSettings) == "function" then
            fontPath, fontFlags, _, _, _, _, useShadow = MSUF_GetGlobalFontSettings()
        end

        if icon.count and icon._msufA2_lastStackTextSize ~= stackSize then
            local ok = MSUF_A2_ApplyFont(icon.count, fontPath, stackSize, fontFlags, useShadow)
            if ok then
                icon._msufA2_lastStackTextSize = stackSize
            end
        end

        local cdFS = MSUF_A2_GetCooldownFontString(icon)
        if cdFS and icon._msufA2_lastCooldownTextSize ~= cooldownSize then
            local ok = MSUF_A2_ApplyFont(cdFS, fontPath, cooldownSize, fontFlags, useShadow)
            if ok then
                icon._msufA2_lastCooldownTextSize = cooldownSize
            end
        end
    end

    local showStacks = not (shared and shared.showStackCount == false)
    if showStacks then
		do
			-- Ensure strong stack styling (anchor configurable)
			local stackAnchor = stackAnchorOverride or (shared and shared.stackCountAnchor) or "TOPRIGHT"
			MSUF_A2_ApplyStackCountAnchorStyle(icon, stackAnchor)

            -- Stack count MUST be refreshed on every UNIT_AURA light update.
            -- Root cause of "stuck stacks": relying only on a single return value wrapper (SafeCall)
            -- for GetAuraApplicationDisplayCount can yield a non-updating/incorrect value on some clients.
            -- Fix: capture multiple returns (pcall) + provide a deterministic numeric fallback via aura.applications.
            local disp = nil



            -- Combat-safe stack sourcing:
            -- 1) Use aura.applications (numeric) as the source of truth when available.
            -- 2) Also capture the API display text (may be formatted) without numeric coercion.
            --    Never rely on string comparisons for gating in combat.
            local nApps = MSUF_SafeNumber(aura and aura.applications)
            local wantStack = (nApps ~= nil and nApps >= 2) or false

            local apiText = nil
            if C_UnitAuras and type(C_UnitAuras.GetAuraApplicationDisplayCount) == "function" and icon._msufAuraInstanceID then
                -- (unit, auraInstanceID, minDisplayCount, maxDisplayCount)
                local ok, r1, r2 = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, icon._msufAuraInstanceID, 2, 99)
                if ok then
                    if r1 ~= nil then
                        apiText = r1
                    elseif r2 ~= nil then
                        apiText = r2
                    end
                end
            end

            -- Decide what to display.
            -- If we know the aura is stacked (nApps>=2), prefer the API display text if present, else use nApps.
            -- If we don't know (nApps nil), we may still display the API text, but we do NOT toggle cooldown numbers.
            if wantStack then
                if apiText ~= nil then
                    disp = tostring(apiText)
                else
                    if nApps and nApps > 99 then
                        disp = "99+"
                    else
                        disp = tostring(nApps)
                    end
                end
            else
                if nApps == nil and apiText ~= nil then
                    disp = tostring(apiText)
                end
            end


            if disp ~= nil then
                stackShown = true

                -- Keep Blizzard cooldown numbers visible even when stacks are shown (stacks are anchored top-right).
                -- Stack availability can fluctuate in combat; hiding countdown numbers would make the timer appear to "drop out".
                if icon._msufA2_hideCDNumbers ~= false then
                    icon._msufA2_hideCDNumbers = false
                    if icon.cooldown and icon.cooldown.SetHideCountdownNumbers then
                        SafeCall(icon.cooldown.SetHideCountdownNumbers, icon.cooldown, false)
                    end
                end

                if icon.count then
                    -- Secret-safe: do NOT compare cached display strings; just set text when we have any display.
                    local newDisp = tostring(disp)
                    local sr, sg, sb = MSUF_A2_GetStackCountRGB()
                    icon.count:SetTextColor(sr, sg, sb, 1)
                    icon.count:SetText(newDisp)
                    icon.count:Show()
                    icon._msufA2_stackWasShown = true
                    -- Do not cache/compare newDisp (may become secret in Midnight/Beta).
                    icon._msufA2_lastStackDisp = nil
                end

            else

                -- In combat, aura stack data can be restricted/unstable for some units.
                -- If we previously showed stacks and do not have a numeric "applications" value, do not force-clear.
                local keep = false
                if InCombatLockdown and InCombatLockdown() and icon._msufA2_stackWasShown and (nApps == nil) then
                    keep = true
                end

                if not keep then
                    -- Restore countdown numbers only when needed.
                    if icon.cooldown and icon.cooldown.SetHideCountdownNumbers then
                        if icon._msufA2_hideCDNumbers ~= false then
                            icon._msufA2_hideCDNumbers = false
                            SafeCall(icon.cooldown.SetHideCountdownNumbers, icon.cooldown, false)
                        end
                    end
                    if icon.count then
                        -- Secret-safe: always clear/hide when no stacks.
                        icon.count:SetText("")
                        icon.count:Hide()
                        icon._msufA2_stackWasShown = false
                        icon._msufA2_lastStackDisp = nil
                    end
                end
            end
        end
    else
        if icon.cooldown and icon.cooldown.SetHideCountdownNumbers then
            SafeCall(icon.cooldown.SetHideCountdownNumbers, icon.cooldown, false)
        end
        if icon.count then
            icon.count:SetText("")
            icon.count:Hide()
        end
    end


    -- Hide-permanent is based on expiration (not on whether swipe is enabled).
    -- IMPORTANT: this is part of the per-unit filter set (overrideable). We pass it explicitly from the
    -- effective filter table. If not provided, fall back to shared.filters (and then legacy shared flag).
    local hidePermanent
    if hidePermanentOverride ~= nil then
        hidePermanent = (hidePermanentOverride == true)
    else
        local sf = shared and shared.filters
        if sf and sf.hidePermanent ~= nil then
            hidePermanent = (sf.hidePermanent == true)
        else
            hidePermanent = (shared and shared.hidePermanent == true) or false
        end
    end
    -- Hide permanent auras (secret-safe):
    -- Only compute "has expiration" when the option is enabled, and early-out before doing any cooldown/text work.
    if hidePermanent then
        local hasExpiration = MSUF_A2_AuraHasExpiration(unit, aura)
        if not hasExpiration then
            -- Safety: ensure this icon is not kept alive by the cooldown text manager.
            icon._msufA2_cdDurationObj = nil
            if icon.cooldown then
                icon.cooldown._msufA2_durationObj = nil
            end
            if icon._msufA2_cdMgrRegistered == true then
                MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
            end
            icon:Hide()
            return false
        end
    end
    -- Cooldown (secret-safe):
    -- Step 7 perf: Only re-apply cooldown data when the auraInstanceID changes (icons are recycled).
    -- This avoids SetCooldownFromDurationObject/SetTimerDuration churn during frequent UNIT_AURA bursts.
    local hadTimer = false
    local swipeWanted = (shared and shared.showCooldownSwipe and true) or false

    if icon.cooldown then
        SafeCall(icon.cooldown.Show, icon.cooldown)

        -- Always show Blizzard cooldown countdown numbers (stacks are drawn separately).
        if icon.cooldown.SetHideCountdownNumbers then
            SafeCall(icon.cooldown.SetHideCountdownNumbers, icon.cooldown, false)
        end

        if icon._msufA2_lastSwipeWanted ~= swipeWanted then
            icon._msufA2_lastSwipeWanted = swipeWanted
            SafeCall(icon.cooldown.SetDrawSwipe, icon.cooldown, swipeWanted)
        end

        -- Accuracy fix (secret-safe): always re-apply the Duration Object when we render.
        -- AuraInstanceIDs can stay stable across refreshes, but the expiration changes. Gating on auraInstanceID
        -- can therefore leave the Cooldown timer stale (stuck/incorrect). We do no time arithmetic or compares.
        local prevAuraID = icon._msufA2_lastCooldownAuraInstanceID
        local prevHadTimer = (icon._msufA2_lastHadTimer == true)

        icon._msufA2_lastCooldownAuraInstanceID = icon._msufAuraInstanceID
        hadTimer = MSUF_A2_TrySetCooldownFromAura(icon, unit, aura)
        icon._msufA2_lastHadTimer = hadTimer

        if not hadTimer then
            -- If we fail to fetch/apply a Duration Object for a timed aura, do NOT clear the cooldown immediately.
            -- This avoids the visible countdown text "dropping out" for a few frames when aura data is restricted/late.
            -- We only hard-clear when the aura is known to be non-expiring, or when this icon was recycled to a new aura
            -- and we never successfully applied a timer for it (to prevent stale timers from previous icons).
            local hasExpiration = MSUF_A2_AuraHasExpiration(unit, aura)
            local sameAura = (prevAuraID ~= nil and prevAuraID == icon._msufAuraInstanceID)

            local shouldClear = false
            if hasExpiration == false then
                shouldClear = true
            elseif (not prevHadTimer) and (not sameAura) then
                -- Freshly recycled icon with no successfully applied timer yet
                shouldClear = true
            end

            if shouldClear then
                pcall(icon.cooldown.Clear, icon.cooldown)
                pcall(icon.cooldown.SetCooldown, icon.cooldown, 0, 0)
                icon._msufA2_previewCooldownStart = nil
                icon._msufA2_previewCooldownDur = nil
            end
        end
    end

    -- Dispel border (secret-safe): just apply once.
    SetDispelBorder(icon, unit, aura, isHelpful, shared, allowHighlights, isOwn)
    -- Tooltip: scripts are assigned once per icon; we only toggle mouse.
    local wantTip = (shared and shared.showTooltip == true)
    icon:EnableMouse((wantTip and true) or false)

    icon:Show()
    return true
end

-- Goal:
--  * Avoid rebuilding/merging large aura lists on UNIT_AURA bursts when nothing about the unit's
--    auraInstanceID sets changed.
--  * Keep this secret-safe: we only hash auraInstanceIDs and config values; no expiration arithmetic.
--
-- If signatures match, we run a *visual-only* refresh over already-assigned icons.
-- ------------------------------------------------------------

local function MSUF_A2__HashStep(h, v)
    if v == nil then v = 0 end
    if type(v) == 'boolean' then v = v and 1 or 0 end
    if type(v) == 'string' then
        v = MSUF_A2_HashAsciiLower and (MSUF_A2_HashAsciiLower(v) or 0) or 0
    end
    if type(v) ~= 'number' then v = 0 end
    -- 31-bit modular hash (stable, cheap)
    local m = 2147483647
    h = (h * 33 + (v % m)) % m
    return h
end

local function MSUF_A2_ComputeRawAuraSig(unit)
    if not unit or not C_UnitAuras or type(C_UnitAuras.GetAuraInstanceIDs) ~= 'function' then
        return nil
    end

    local okH, helpful = pcall(C_UnitAuras.GetAuraInstanceIDs, unit, 'HELPFUL')
    local okD, harmful = pcall(C_UnitAuras.GetAuraInstanceIDs, unit, 'HARMFUL')
    if not okH or type(helpful) ~= 'table' then helpful = nil end
    if not okD or type(harmful) ~= 'table' then harmful = nil end

    local h = 5381
    local hc = 0
    local dc = 0

    if helpful then
        hc = #helpful
        for i = 1, hc do
            h = MSUF_A2__HashStep(h, helpful[i])
        end
    end

    -- delimiter so helpful+harmful order can't collide
    h = MSUF_A2__HashStep(h, 777)

    if harmful then
        dc = #harmful
        for i = 1, dc do
            h = MSUF_A2__HashStep(h, harmful[i])
        end
    end

    h = MSUF_A2__HashStep(h, hc)
    h = MSUF_A2__HashStep(h, dc)
    return h
end

local function MSUF_A2_ComputeLayoutSig(unit, shared, caps, layoutMode, buffDebuffAnchor, splitSpacing,
    iconSize, spacing, perRow, maxBuffs, maxDebuffs, growth, rowWrap, stackCountAnchor,
    tf, masterOn, onlyBossAuras, showExtraStealable, showExtraDispellable, finalShowBuffs, finalShowDebuffs)

    local h = 146959

    h = MSUF_A2__HashStep(h, unit)
    h = MSUF_A2__HashStep(h, layoutMode)
    h = MSUF_A2__HashStep(h, buffDebuffAnchor)
    h = MSUF_A2__HashStep(h, growth)
    h = MSUF_A2__HashStep(h, rowWrap)
    h = MSUF_A2__HashStep(h, stackCountAnchor)

    h = MSUF_A2__HashStep(h, iconSize)
    h = MSUF_A2__HashStep(h, spacing)
    h = MSUF_A2__HashStep(h, perRow)

    h = MSUF_A2__HashStep(h, splitSpacing)
    h = MSUF_A2__HashStep(h, maxBuffs)
    h = MSUF_A2__HashStep(h, maxDebuffs)

    h = MSUF_A2__HashStep(h, finalShowBuffs)
    h = MSUF_A2__HashStep(h, finalShowDebuffs)

    -- master filters + important filter toggles
    h = MSUF_A2__HashStep(h, masterOn)
    h = MSUF_A2__HashStep(h, onlyBossAuras)
    h = MSUF_A2__HashStep(h, showExtraStealable)
    h = MSUF_A2__HashStep(h, showExtraDispellable)

    if tf and type(tf) == 'table' then
        h = MSUF_A2__HashStep(h, tf.enabled)
        h = MSUF_A2__HashStep(h, tf.hidePermanent)
        h = MSUF_A2__HashStep(h, tf.onlyBossAuras)

        local b = tf.buffs
        local d = tf.debuffs
        if type(b) == 'table' then
            h = MSUF_A2__HashStep(h, b.onlyMine)
            h = MSUF_A2__HashStep(h, b.includeBoss)
            h = MSUF_A2__HashStep(h, b.includeStealable)
        end
        if type(d) == 'table' then
            h = MSUF_A2__HashStep(h, d.onlyMine)
            h = MSUF_A2__HashStep(h, d.includeBoss)
            h = MSUF_A2__HashStep(h, d.includeDispellable)
            h = MSUF_A2__HashStep(h, d.dispelMagic)
            h = MSUF_A2__HashStep(h, d.dispelCurse)
            h = MSUF_A2__HashStep(h, d.dispelDisease)
            h = MSUF_A2__HashStep(h, d.dispelPoison)
            h = MSUF_A2__HashStep(h, d.dispelEnrage)
        end
    end

    -- Visual toggles that affect per-icon work
    if shared and type(shared) == 'table' then
        h = MSUF_A2__HashStep(h, shared.showCooldownSwipe)
        h = MSUF_A2__HashStep(h, shared.showTooltip)
        h = MSUF_A2__HashStep(h, shared.highlightOwnBuffs)
        h = MSUF_A2__HashStep(h, shared.highlightOwnDebuffs)
        h = MSUF_A2__HashStep(h, shared.highlightStealableBuffs)
        h = MSUF_A2__HashStep(h, shared.highlightDispellableDebuffs)
        h = MSUF_A2__HashStep(h, shared.hidePermanent)
        h = MSUF_A2__HashStep(h, shared.onlyMyBuffs)
        h = MSUF_A2__HashStep(h, shared.onlyMyDebuffs)
    end

    return h
end

local function MSUF_A2_RefreshAssignedIcons(entry, unit, shared, GetEffFn, masterOn, stackCountAnchor)
    if not entry or not unit or not shared then return end
    if not C_UnitAuras or type(C_UnitAuras.GetAuraDataByAuraInstanceID) ~= 'function' then return end

    local wantOwnBuff = (shared.highlightOwnBuffs == true)
    local wantOwnDebuff = (shared.highlightOwnDebuffs == true)
    local ownBuffSet, ownDebuffSet

    local function IsOwn(isHelpful, auraInstanceID)
        if not auraInstanceID then return false end
        local okK, k = pcall(tostring, auraInstanceID)
        if not okK or not k then return false end

        if isHelpful then
            if not wantOwnBuff then return false end
            if not ownBuffSet then ownBuffSet = MSUF_A2_GetPlayerAuraIdSet(unit, 'HELPFUL') end
            return ownBuffSet and ownBuffSet[k] and true or false
        else
            if not wantOwnDebuff then return false end
            if not ownDebuffSet then ownDebuffSet = MSUF_A2_GetPlayerAuraIdSet(unit, 'HARMFUL') end
            return ownDebuffSet and ownDebuffSet[k] and true or false
        end
    end

    local useSingleRow = (entry._msufA2_lastUseSingleRow == true)
    local buffCount = entry._msufA2_lastBuffCount or 0
    local debuffCount = entry._msufA2_lastDebuffCount or 0
    local mixedCount = entry._msufA2_lastMixedCount or 0

    local function RefreshContainer(container, count)
        if not container or not container._msufIcons or count <= 0 then return end
        local icons = container._msufIcons
        for i = 1, count do
            local ic = icons[i]
            if ic and ic.IsShown and ic:IsShown() then
                local aid = ic._msufAuraInstanceID
                if aid then
                    local okA, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, aid)
                    if okA and type(aura) == 'table' then
                        -- Preserve the filter category this icon was assigned under.
                        local isHelpful = (ic._msufFilter == 'HELPFUL')
                        local eff = GetEffFn and GetEffFn(isHelpful) or nil
                        local hidePerm = (eff and eff.hidePermanent) and true or false
                        local isOwn = IsOwn(isHelpful, aid)
                        ApplyAuraToIcon(ic, unit, aura, shared, isHelpful, hidePerm, masterOn, isOwn, stackCountAnchor)
                    end
                end
            end
        end
    end

    if useSingleRow then
        RefreshContainer(entry.mixed, mixedCount)
    else
        RefreshContainer(entry.debuffs, debuffCount)
        RefreshContainer(entry.buffs, buffCount)
    end
end


-- ------------------------------------------------------------
-- Auras 2.0 Preview safety: ensure preview icons never block real auras
-- ------------------------------------------------------------
local function MSUF_A2_ClearPreviewIconsInContainer(container)
    if not container or not container._msufIcons then return end
    local icons = container._msufIcons
    for i = 1, #icons do
        local icon = icons[i]
        if icon and icon._msufA2_isPreview == true then
            -- Unregister from cooldown text manager (prevents orphan updates)
            if icon._msufA2_cdMgrRegistered == true and type(MSUF_A2_CooldownTextMgr_UnregisterIcon) == "function" then
                MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
            end

            -- Clear any preview timing state
            icon._msufA2_previewCooldownStart = nil
            icon._msufA2_previewCooldownDur = nil
            icon._msufA2_previewStackCur = nil
            icon._msufA2_previewStackMax = nil

            -- Clear cooldown widget state (best-effort)
            if icon.cooldown then
                icon.cooldown._msufA2_durationObj = nil
                pcall(icon.cooldown.Clear, icon.cooldown)
                pcall(icon.cooldown.SetCooldown, icon.cooldown, 0, 0)
            end

            -- Clear visual + identity state
            icon._msufA2_isPreview = nil
            icon._msufA2_previewKind = nil
            icon._msufAuraInstanceID = nil
            icon._msufSpellId = nil
            icon._msufA2_lastVisualAuraInstanceID = nil

            if icon.count then
                icon.count:SetText("")
                icon.count:Hide()
            end
            if icon._msufOwnGlow then icon._msufOwnGlow:Hide() end

            icon:Hide()
        end
    end
end

local function MSUF_A2_ClearPreviewsForEntry(entry)
    if not entry then return end
    MSUF_A2_ClearPreviewIconsInContainer(entry.debuffs)
    MSUF_A2_ClearPreviewIconsInContainer(entry.buffs)
    MSUF_A2_ClearPreviewIconsInContainer(entry.mixed)
    entry._msufA2_previewActive = nil
end

local function MSUF_A2_ClearAllPreviews()
    for _, entry in pairs(AurasByUnit) do
        if entry and entry._msufA2_previewActive == true then
            MSUF_A2_ClearPreviewsForEntry(entry)
        end
    end
end

-- Export (used by options / edit-mode transitions)
_G.MSUF_Auras2_ClearAllPreviews = MSUF_A2_ClearAllPreviews

local MSUF_A2_RENDER_BUDGET = 18

local function RenderUnit(entry)
    local rawSig, layoutSig
    local a2, shared = GetAuras2DB()
    if not a2 or not shared or not entry then return end

    local unit = entry.unit
    local wantPreview = (shared.showInEditMode == true) and IsEditModeActive()

    local unitEnabled = UnitEnabled(unit)
    local unitExists = UnitExists and UnitExists(unit)
    local frame = entry.frame or FindUnitFrame(unit)

    -- Preview is ONLY allowed when there is no live unit (or the unit is disabled/hidden).
    -- This prevents preview icons from blocking real auras.
    local showTest = (wantPreview == true) and ((not unitExists) or (not unitEnabled) or (not frame) or (not frame:IsShown()))

    -- In Edit Mode preview, still allow positioning even if this unit's auras are disabled.
    -- Outside preview, respect the unit enable toggle.
    if (not unitEnabled) and (not showTest) then
        if entry.anchor then entry.anchor:Hide() end
        if entry.editMover then entry.editMover:Hide() end
        return
    end

    if not unitExists and not showTest then
        if entry.anchor then entry.anchor:Hide() end
        if entry.editMover then entry.editMover:Hide() end
        return
    end

    if (not showTest) and (not frame or not frame:IsShown()) then
        if entry.anchor then entry.anchor:Hide() end
        if entry.editMover then entry.editMover:Hide() end
        return
    end

    entry = EnsureAttached(unit)
    if not entry or not entry.anchor then return end

    if (not showTest) and entry._msufA2_previewActive == true then
        -- We are about to render real auras; ensure old preview icons are fully cleared first.
        MSUF_A2_ClearPreviewsForEntry(entry)
    end


    -- Keep anchors updated (unitframe may have moved). Also drive Edit Mode mover for Target.
    local offX = shared.offsetX or 0
    local offY = shared.offsetY or 0
    local boxW, boxH = nil, nil

    local pu = a2.perUnit
    local uconf = pu and pu[unit]
    if uconf and uconf.overrideLayout and type(uconf.layout) == "table" then
        if type(uconf.layout.offsetX) == "number" then offX = uconf.layout.offsetX end
        if type(uconf.layout.offsetY) == "number" then offY = uconf.layout.offsetY end
        if type(uconf.layout.width) == "number" then boxW = uconf.layout.width end
        if type(uconf.layout.height) == "number" then boxH = uconf.layout.height end
    end

    if showTest then
        if unit == "target" then
            MSUF_A2_EnsureTargetEditMover(entry)
        elseif unit == "focus" then
            if MSUF_A2_EnsureFocusEditMover then MSUF_A2_EnsureFocusEditMover(entry) end
        elseif type(unit) == "string" and unit:match("^boss%d+$") then
            if MSUF_A2_EnsureBossEditMover then MSUF_A2_EnsureBossEditMover(entry) end
        end

        if entry.editMover then
            local defW, defH = MSUF_A2_ComputeDefaultEditBoxSize(unit, shared)
            if type(boxW) ~= "number" or boxW <= 0 then boxW = defW end
            if type(boxH) ~= "number" or boxH <= 0 then boxH = defH end
        end
    end

        -- Shared caps overrides (Max Buffs/Debuffs, Icons per row + layout dropdowns)
    local caps = nil
    if uconf and uconf.overrideSharedLayout == true and type(uconf.layoutShared) == "table" then
        caps = uconf.layoutShared
    end

    local layoutMode = (caps and caps.layoutMode ~= nil) and caps.layoutMode or shared.layoutMode or "SEPARATE"
    local buffDebuffAnchor = (caps and caps.buffDebuffAnchor ~= nil) and caps.buffDebuffAnchor or shared.buffDebuffAnchor or "STACKED"
    local splitSpacing = (caps and type(caps.splitSpacing) == "number") and caps.splitSpacing or shared.splitSpacing or 0

    UpdateAnchor(entry, shared, offX, offY, boxW, boxH, layoutMode, buffDebuffAnchor, splitSpacing)
    -- Edit mover visibility: show when Edit Mode is active and Auras2 are enabled.
    -- We keep the mover always created but only visible in Edit Mode.
    if entry.editMover then
        if IsEditModeActive() and UnitEnabled(unit) then
            entry.editMover:Show()
        else
            entry.editMover:Hide()
        end
    end
    if showTest then
        -- Preview/edit-mode safety: containers are entry.buffs/entry.debuffs/entry.mixed (not *Container)
        entry.anchor:Show()
        if entry.buffs then entry.buffs:Show() end
        if entry.debuffs then entry.debuffs:Show() end
        if entry.mixed then entry.mixed:Show() end
    end
    entry.anchor:Show()

    local iconSize, spacing, perRow = MSUF_A2_GetEffectiveSizing(unit, shared)

    -- Separate caps (nice-to-have). Keep legacy maxIcons as fallback.
    local maxDebuffs = (caps and type(caps.maxDebuffs) == "number") and caps.maxDebuffs or shared.maxDebuffs or shared.maxIcons or 12
    local maxBuffs = (caps and type(caps.maxBuffs) == "number") and caps.maxBuffs or shared.maxBuffs or shared.maxIcons or 12

    -- Internal caps used by render loops (legacy variable names expected below).
    local debuffCap = maxDebuffs
    local buffCap = maxBuffs


    local growth = (caps and caps.growth ~= nil) and caps.growth or shared.growth or "RIGHT"
    local rowWrap = (caps and caps.rowWrap ~= nil) and caps.rowWrap or shared.rowWrap or "DOWN"
    local stackCountAnchor = (caps and caps.stackCountAnchor ~= nil) and caps.stackCountAnchor or shared.stackCountAnchor or "TOPRIGHT"

    local useSingleRow = (layoutMode == "SINGLE")
    local mixedCount = 0

    local debuffCount = 0
    local buffCount = 0

    local finalShowDebuffs = (shared.showDebuffs == true)
    local finalShowBuffs = (shared.showBuffs == true)
-- Filter source of truth:
-- Use shared.filters by default; use per-unit filters only when overrideFilters is enabled for this unit.
local tf
local filtersDisabled = false
do
    local unitKey = unit
    local sf = shared and shared.filters
    tf = sf
    if a2 and a2.perUnit and unitKey and a2.perUnit[unitKey] and a2.perUnit[unitKey].overrideFilters == true then
        tf = a2.perUnit[unitKey].filters or sf
    end
    if tf and tf.enabled == false then
        filtersDisabled = true -- master off: show everything (no filtering / no highlight)
    end
end

    local function GetEff(isHelpful)
        if filtersDisabled then
            return {
                onlyMine = false,
                includeBoss = false,
                includeStealable = false,
                includeDispellable = false,
                hidePermanent = false,
            }
        end
        if tf then
            if isHelpful then
                return {
                    onlyMine = (tf.buffs and tf.buffs.onlyMine) == true,
                    includeBoss = (tf.buffs and tf.buffs.includeBoss) == true,
                    includeStealable = (tf.buffs and tf.buffs.includeStealable) == true,
                    includeDispellable = false,
                    hidePermanent = (tf.hidePermanent == true),
                }
            else
                return {
                    onlyMine = (tf.debuffs and tf.debuffs.onlyMine) == true,
                    includeBoss = (tf.debuffs and tf.debuffs.includeBoss) == true,
                    includeStealable = false,
                    includeDispellable = (tf.debuffs and tf.debuffs.includeDispellable) == true,
                    hidePermanent = (tf.hidePermanent == true),
                }
            end
        end

        -- Shared fallback (no advanced filters)
        if isHelpful then
            return {
                onlyMine = (shared.onlyMyBuffs == true),
                includeBoss = false,
                includeStealable = false,
                includeDispellable = false,
                hidePermanent = (shared.hidePermanent == true),
            }
        else
            return {
                onlyMine = (shared.onlyMyDebuffs == true),
                includeBoss = false,
                includeStealable = false,
                includeDispellable = false,
                hidePermanent = (shared.hidePermanent == true),
            }
        end
    end

    if unitExists and not showTest then
        -- Real auras are skipped while Preview-in-Edit-Mode is active so preview always wins.
        local budget = MSUF_A2_RENDER_BUDGET
        local st = entry._msufA2_budgetState
        local resumeBudget = (entry._msufA2_budgetResume == true) and st and (st.pending == true) and (st.unit == unit)

        if not resumeBudget then
            -- New render invalidates any pending continuation so we always reflect the latest unit state.
            entry._msufA2_budgetResume = false
            if st and st.pending then
                st.pending = false
            end
            entry._msufA2_budgetStamp = (entry._msufA2_budgetStamp or 0) + 1
            st = st or {}
            entry._msufA2_budgetState = st
            st.stamp = entry._msufA2_budgetStamp
            st.unit = unit
            st.pending = false
            st.iDebuff = 1
            st.iBuff = 1
            st.debuffCount = 0
            st.buffCount = 0
            st.mixedCount = 0
            st.debuffs = nil
            st.buffs = nil
        else
            -- Resume from where we left off (counts already applied last tick).
            if st then st.pending = false end
            debuffCount = st.debuffCount or debuffCount
            buffCount = st.buffCount or buffCount
            mixedCount = st.mixedCount or mixedCount
        end

        local budgetExhausted = false
        local function ScheduleBudgetContinuation()
            if entry._msufA2_budgetScheduled then return end
            entry._msufA2_budgetScheduled = true
            C_Timer.After(0, function()
                entry._msufA2_budgetScheduled = false
                local s = entry._msufA2_budgetState
                if not s or s.pending ~= true then return end
                entry._msufA2_budgetResume = true
                RenderUnit(entry)
                entry._msufA2_budgetResume = false
            end)
        end

        -- Additive extras: when enabled (and master filters are on), always include stealable buffs and/or dispellable debuffs
        -- in addition to the normal "Display" lists, without overriding them.
        local masterOn = (tf and tf.enabled == true) and true or false

        local onlyBossAuras = (masterOn and tf and tf.onlyBossAuras == true) and true or false

        local anyDispel = false
        if masterOn and tf and tf.debuffs then
            local d = tf.debuffs
            anyDispel = (d.dispelMagic or d.dispelCurse or d.dispelDisease or d.dispelPoison or d.dispelEnrage) and true or false
        end

        local function DebuffTypeAllowed(aura)
            if not anyDispel then return true end
            local d = tf and tf.debuffs
            if not d then return true end

            local dtype = MSUF_A2_AuraFieldToString(aura, 'dispelName') or MSUF_A2_AuraFieldToString(aura, 'dispelType')
            if dtype == nil then
                -- When debuff-type filtering is enabled, "unknown" types are treated as not allowed.
                return false
            end

            -- IMPORTANT (Midnight): avoid string equality on potential secret values.
            local h = MSUF_A2_HashAsciiLower(dtype)

            -- Some effects can report an empty token; treat that as "Enrage".
            if h == 0 or h == MSUF_A2_HASH_ENRAGE then
                return d.dispelEnrage == true
            end
            if h == MSUF_A2_HASH_MAGIC then return d.dispelMagic == true end
            if h == MSUF_A2_HASH_CURSE then return d.dispelCurse == true end
            if h == MSUF_A2_HASH_DISEASE then return d.dispelDisease == true end
            if h == MSUF_A2_HASH_POISON then return d.dispelPoison == true end
            return false
        end

        local baseShowDebuffs = (shared.showDebuffs == true)
        local baseShowBuffs = (shared.showBuffs == true)

        local showExtraStealable = (masterOn and tf.buffs and tf.buffs.includeStealable == true) and true or false
        local showExtraDispellable = (masterOn and tf.debuffs and tf.debuffs.includeDispellable == true) and true or false

        local wantDebuffs = baseShowDebuffs or showExtraDispellable
        local wantBuffs = baseShowBuffs or showExtraStealable

        finalShowDebuffs = (wantDebuffs == true)
        finalShowBuffs = (wantBuffs == true)


        -- If raw auraInstanceID sets + layout/filter signature are unchanged, avoid expensive list building.
        if not resumeBudget then
            rawSig = MSUF_A2_ComputeRawAuraSig(unit)
            layoutSig = MSUF_A2_ComputeLayoutSig(unit, shared, caps, layoutMode, buffDebuffAnchor, splitSpacing,
                iconSize, spacing, perRow, maxBuffs, maxDebuffs, growth, rowWrap, stackCountAnchor,
                tf, masterOn, onlyBossAuras, showExtraStealable, showExtraDispellable, finalShowBuffs, finalShowDebuffs)

            if rawSig and layoutSig
               and entry._msufA2_lastRawSig == rawSig
               and entry._msufA2_lastLayoutSig == layoutSig
               and entry._msufA2_lastQuickOK == true
               and type(entry._msufA2_lastBuffCount) == 'number'
               and type(entry._msufA2_lastDebuffCount) == 'number'
            then
                MSUF_A2_RefreshAssignedIcons(entry, unit, shared, GetEff, masterOn, stackCountAnchor)
                return
            end
        end

        -- Own-aura highlight uses API-only player-only instance ID sets so it works in combat too.
        -- (No reliance on aura-table fields that may be missing/secret.)
        local ownBuffSet, ownDebuffSet
        if unitExists then
            if (shared.highlightOwnBuffs == true) and finalShowBuffs then
                ownBuffSet = MSUF_A2_GetPlayerAuraIdSet(unit, "HELPFUL")
            end
            if (shared.highlightOwnDebuffs == true) and finalShowDebuffs then
                ownDebuffSet = MSUF_A2_GetPlayerAuraIdSet(unit, "HARMFUL")
            end
        end

        if wantDebuffs then
            local eff = GetEff(false)

            local baseDebuffs = {}
            if baseShowDebuffs then
                if eff.onlyMine then
                    if eff.includeBoss then
                        local mine = GetAuraList(unit, "HARMFUL", true)
                        local all = GetAuraList(unit, "HARMFUL", false)
                        baseDebuffs = MSUF_A2_MergeBossAuras(mine, all)
                    else
                        baseDebuffs = GetAuraList(unit, "HARMFUL", true)
                    end
                else
                    baseDebuffs = GetAuraList(unit, "HARMFUL", false)
                end
            end

            local extraDebuffs = {}
            if showExtraDispellable then
                local all = GetAuraList(unit, "HARMFUL", false)
                for i = 1, #all do
                    local aura = all[i]
                    if aura and MSUF_A2_IsDispellableAura(unit, aura) then
                        extraDebuffs[#extraDebuffs+1] = aura
                    end
                end
            end

            local debuffs
            local startDebuffI = 1
            if resumeBudget and st and st.debuffs then
                debuffs = st.debuffs
                startDebuffI = (type(st.iDebuff) == 'number' and st.iDebuff) or 1
            else
                debuffs = MSUF_A2_MergeAuraLists(extraDebuffs, baseDebuffs)
                if st then st.debuffs = debuffs end
                startDebuffI = 1
            end
            if st then st.debuffsLen = (debuffs and #debuffs) or 0 end
            for i = startDebuffI, #debuffs do
                if debuffCount >= debuffCap then break end
                local aura = debuffs[i]
                if aura then
                    if onlyBossAuras and not MSUF_A2_AuraFieldIsTrue(aura, 'isBossAura') then
                        -- skip
                    elseif not DebuffTypeAllowed(aura) then
                        -- skip
                    else
                        if budget <= 0 then
                            budgetExhausted = true
                            if st then
                                st.pending = true
                                st.iDebuff = i
                                st.iBuff = 1
                                st.debuffCount = debuffCount
                                st.buffCount = buffCount
                                st.mixedCount = mixedCount
                            end
                            ScheduleBudgetContinuation()
                            break
                        end
                        budget = budget - 1
                        local icon = AcquireIcon(useSingleRow and entry.mixed or entry.debuffs, (useSingleRow and (mixedCount + 1) or (debuffCount + 1)))
                        local isOwn = false
                        if ownDebuffSet then
                            local aid = aura and (aura._msufAuraInstanceID or aura.auraInstanceID)
                            local okK, k = pcall(tostring, aid)
                            if okK and k and ownDebuffSet[k] then
                                isOwn = true
                            end
                        end
						-- "Hide permanent" is intended to apply to BUFFS only (HELPFUL). Debuffs should never be hidden
						-- by this toggle, otherwise it can erase important dispels/CC icons.
						if ApplyAuraToIcon(icon, unit, aura, shared, false, false, masterOn, isOwn, stackCountAnchor) then
                            debuffCount = debuffCount + 1
                            if useSingleRow then mixedCount = mixedCount + 1 end
                        end
                    end
                end
            end
        end

        if wantBuffs and not budgetExhausted then
            local eff = GetEff(true)

            local baseBuffs = {}
            if baseShowBuffs then
                if eff.onlyMine then
                    if eff.includeBoss then
                        local mine = GetAuraList(unit, "HELPFUL", true)
                        local all = GetAuraList(unit, "HELPFUL", false)
                        baseBuffs = MSUF_A2_MergeBossAuras(mine, all)
                    else
                        baseBuffs = GetAuraList(unit, "HELPFUL", true)
                    end
                else
                    baseBuffs = GetAuraList(unit, "HELPFUL", false)
                end
            end

            local extraBuffs = {}
            if showExtraStealable then
                local all = GetAuraList(unit, "HELPFUL", false)
                for i = 1, #all do
                    local aura = all[i]
                    if aura and MSUF_A2_IsStealableAura(aura) then
                        extraBuffs[#extraBuffs+1] = aura
                    end
                end
            end

            local buffs
            local startBuffI = 1
            if resumeBudget and st and st.buffs then
                buffs = st.buffs
                startBuffI = (type(st.iBuff) == 'number' and st.iBuff) or 1
            else
                buffs = MSUF_A2_MergeAuraLists(extraBuffs, baseBuffs)
                if st then st.buffs = buffs end
                startBuffI = 1
            end
            if st then st.buffsLen = (buffs and #buffs) or 0 end
            for i = startBuffI, #buffs do
                if buffCount >= buffCap then break end
                local aura = buffs[i]
                if aura then
                    if onlyBossAuras and not MSUF_A2_AuraFieldIsTrue(aura, 'isBossAura') then
                        -- skip
                    else
                        if budget <= 0 then
                            budgetExhausted = true
                            if st then
                                st.pending = true
                                st.iBuff = i
                                -- Ensure resume does not re-run debuffs when we are continuing in buffs.
                                if type(st.debuffsLen) == 'number' and st.debuffsLen > 0 then
                                    st.iDebuff = st.debuffsLen + 1
                                else
                                    st.iDebuff = st.iDebuff or 1
                                end
                                st.debuffCount = debuffCount
                                st.buffCount = buffCount
                                st.mixedCount = mixedCount
                            end
                            ScheduleBudgetContinuation()
                            break
                        end
                        budget = budget - 1
                        local icon = AcquireIcon(useSingleRow and entry.mixed or entry.buffs, (useSingleRow and (mixedCount + 1) or (buffCount + 1)))
                        local isOwn = false
                        if ownBuffSet then
                            local aid = aura and (aura._msufAuraInstanceID or aura.auraInstanceID)
                            local okK, k = pcall(tostring, aid)
                            if okK and k and ownBuffSet[k] then
                                isOwn = true
                            end
                        end
						if ApplyAuraToIcon(icon, unit, aura, shared, true, eff.hidePermanent, masterOn, isOwn, stackCountAnchor) then
                            buffCount = buffCount + 1
                            if useSingleRow then mixedCount = mixedCount + 1 end
                        end
                    end
                end
            end
        end

        if st and not budgetExhausted and st.pending ~= true then
            st.debuffs = nil
            st.buffs = nil
            st.debuffsLen = nil
            st.buffsLen = nil
            st.iDebuff = 1
            st.iBuff = 1
            st.debuffCount = debuffCount
            st.buffCount = buffCount
            st.mixedCount = mixedCount
        end
    else
        -- Preview in Edit Mode (no unit)
        if not showTest then
            -- No unit and preview disabled: hide everything.
            HideUnused(entry.debuffs, 1)
            HideUnused(entry.buffs, 1)
            debuffCount = 0
            buffCount = 0
        else
            -- Force both rows visible in preview so users can position/see styling even if they toggled rows off.
            finalShowBuffs = true
            finalShowDebuffs = true

            local function ApplyPreviewIcon(icon, tex, spellId, opts)
                if not icon then return end
                icon._msufUnit = unit
                icon._msufAuraInstanceID = nil
                icon._msufA2_lastCooldownAuraInstanceID = nil
                icon._msufA2_lastHadTimer = nil
                icon._msufSpellId = spellId
                icon._msufFilter = (opts and opts.isHelpful) and "HELPFUL" or "HARMFUL"


                -- Mark as preview so tooltips can describe the fake aura type
                icon._msufA2_isPreview = true
                icon._msufA2_previewKind = (opts and opts.previewKind) or nil
                icon.tex:SetTexture(tex)

                -- Reset visuals
                if icon._msufOwnGlow then icon._msufOwnGlow:Hide() end
                if icon._msufBorder then icon._msufBorder:SetBackdropBorderColor(0, 0, 0, 1) end

                -- Cooldown setup (always apply a cooldown object; swipe visibility follows setting)
                if icon.cooldown then
                    SafeCall(icon.cooldown.Show, icon.cooldown)
                    SafeCall(icon.cooldown.SetDrawSwipe, icon.cooldown, (shared.showCooldownSwipe and true) or false)
                    SafeCall(icon.cooldown.SetHideCountdownNumbers, icon.cooldown, false)
                    if opts and opts.permanent then
                        pcall(icon.cooldown.Clear, icon.cooldown)
                        pcall(icon.cooldown.SetCooldown, icon.cooldown, 0, 0)
                        -- No synthetic timing for permanent preview auras
                        icon._msufA2_previewCooldownStart = nil
                        icon._msufA2_previewCooldownDur = nil
                    else
                        -- Show an obvious, readable timer in preview
                        local ps = GetTime() - 10
                        local pd = 25
                        SafeCall(icon.cooldown.SetCooldown, icon.cooldown, ps, pd)
                        -- Store synthetic timing so the CooldownTextMgr can color preview numbers (no auraInstanceID in preview).
                        icon._msufA2_previewCooldownStart = ps
                        icon._msufA2_previewCooldownDur = pd
                    end

-- Apply per-unit text sizes in preview too (stacks + cooldown text). Font face/outline/shadow follow global font settings.
do
    local stackSize, cooldownSize = MSUF_A2_GetEffectiveTextSizes(unit, shared)

    local fontPath, fontFlags, _, _, _, _, useShadow
    if type(MSUF_GetGlobalFontSettings) == "function" then
        fontPath, fontFlags, _, _, _, _, useShadow = MSUF_GetGlobalFontSettings()
    end

    if icon.count and icon._msufA2_lastStackTextSize ~= stackSize then
        local ok = MSUF_A2_ApplyFont(icon.count, fontPath, stackSize, fontFlags, useShadow)
        if ok then
            icon._msufA2_lastStackTextSize = stackSize
        end
    end
    local cdFS = MSUF_A2_GetCooldownFontString(icon)
    if cdFS and icon._msufA2_lastCooldownTextSize ~= cooldownSize then
        local ok = MSUF_A2_ApplyFont(cdFS, fontPath, cooldownSize, fontFlags, useShadow)
        if ok then
            icon._msufA2_lastCooldownTextSize = cooldownSize
        end
    end
end

                end

                -- Register preview icons with the cooldown text manager so timer colors are visible in preview mode.
                if icon.cooldown and icon._msufA2_isPreview == true then
                    -- Manager itself will skip if numbers are hidden (e.g. stack preview icon).
                    MSUF_A2_CooldownTextMgr_RegisterIcon(icon)
                end

                -- Stack count preview
                local showStacks = not (shared and shared.showStackCount == false)
                if showStacks and opts and opts.stackText and icon.count then
                    -- Keep preview stack anchor in sync with the live setting (shared/per-unit).
                    MSUF_A2_ApplyStackCountAnchorStyle(icon, stackCountAnchor)
                    local sr, sg, sb = MSUF_A2_GetStackCountRGB()
                    icon.count:SetTextColor(sr, sg, sb, 1)
                    -- Preview stacks are demo values (not real unit data). Store numeric state so we can light-refresh without rebuild.
                    local curN = tonumber(opts.stackText) or 2
                    local maxN = tonumber(opts.stackText)
                    if type(maxN) == "number" then
                        if maxN < 5 then maxN = 5 end
                        icon._msufA2_previewStackMax = maxN
                    else
                        icon._msufA2_previewStackMax = nil
                    end
                    icon._msufA2_previewStackCur = icon._msufA2_previewStackCur or curN
                    icon.count:SetText(tostring(icon._msufA2_previewStackCur))
                    icon.count:Show()
                    if icon.cooldown and icon.cooldown.SetHideCountdownNumbers then
                        SafeCall(icon.cooldown.SetHideCountdownNumbers, icon.cooldown, true)
                    end
                else
                    icon._msufA2_previewStackCur = nil
                    icon._msufA2_previewStackMax = nil
                    if icon.count then
                        icon.count:SetText("")
                        icon.count:Hide()
                    end
                    if icon.cooldown and icon.cooldown.SetHideCountdownNumbers then
                        SafeCall(icon.cooldown.SetHideCountdownNumbers, icon.cooldown, false)
                    end
                end

                -- Highlights (respond to toggles so preview reflects your current settings)
                if opts and opts.isOwn then
                    if opts.isHelpful and shared and shared.highlightOwnBuffs == true then
                        local r, g, b = MSUF_A2_GetOwnBuffHighlightRGB()
                        if icon._msufBorder then icon._msufBorder:SetBackdropBorderColor(r, g, b, 1) end
                        if icon._msufOwnGlow then
                            icon._msufOwnGlow:SetVertexColor(r, g, b, 1)
                            icon._msufOwnGlow:Show()
                        end
                    elseif (not opts.isHelpful) and shared and shared.highlightOwnDebuffs == true then
                        local r, g, b = MSUF_A2_GetOwnDebuffHighlightRGB()
                        if icon._msufBorder then icon._msufBorder:SetBackdropBorderColor(r, g, b, 1) end
                        if icon._msufOwnGlow then
                            icon._msufOwnGlow:SetVertexColor(r, g, b, 1)
                            icon._msufOwnGlow:Show()
                        end
                    end
                end

                if opts and opts.isHelpful and opts.stealable and shared and shared.highlightStealableBuffs == true then
                    local r, g, b = MSUF_A2_GetStealableBorderRGB()
                    if icon._msufBorder then icon._msufBorder:SetBackdropBorderColor(r, g, b, 1) end
                end

                if opts and (not opts.isHelpful) and opts.dispellable and shared and shared.highlightDispellableDebuffs == true then
                    local r, g, b = MSUF_A2_GetDispelBorderRGB()
                    if icon._msufBorder then icon._msufBorder:SetBackdropBorderColor(r, g, b, 1) end
                end

                -- Tooltip: scripts are assigned once per icon; we only toggle mouse.
                icon:EnableMouse((shared and shared.showTooltip and true) or false)


                icon:Show()
            end

            -- Build a small, representative set (prioritize border/stack examples so they show even when Max Buffs/Debuffs is low)
            local buffDefs = MSUF_A2_PREVIEW_BUFF_DEFS

            local debuffDefs = MSUF_A2_PREVIEW_DEBUFF_DEFS

            -- Debuffs
            debuffCount = math.min(#debuffDefs, debuffCap)
            for i = 1, debuffCount do
                local def = debuffDefs[i]
                local icon = AcquireIcon(useSingleRow and entry.mixed or entry.debuffs, i)
                ApplyPreviewIcon(icon, def.tex, def.spellId, def)
            end
            if not useSingleRow then HideUnused(entry.debuffs, debuffCount + 1) end

            -- Buffs
            buffCount = math.min(#buffDefs, buffCap)
            for i = 1, buffCount do
                local def = buffDefs[i]
                local icon = AcquireIcon(useSingleRow and entry.mixed or entry.buffs, (useSingleRow and (debuffCount + i) or i))
                ApplyPreviewIcon(icon, def.tex, def.spellId, def)
            end
            if not useSingleRow then HideUnused(entry.buffs, buffCount + 1) end
        end
    end

    -- Track whether preview icons are currently active for this unit (used to hard-clear on transition)
    if showTest then
        entry._msufA2_previewActive = true
    else
        entry._msufA2_previewActive = nil
    end

    -- Layout
    if useSingleRow and entry.mixed then
        local total = 0
        if finalShowDebuffs then total = total + debuffCount end
        if finalShowBuffs then total = total + buffCount end
        if showTest then
            -- In preview mode, we already populated sequential indices: debuffs [1..debuffCount], buffs [debuffCount+1..debuffCount+buffCount]
            total = (finalShowDebuffs and debuffCount or 0) + (finalShowBuffs and buffCount or 0)
        else
            total = mixedCount
        end

        if (finalShowDebuffs or finalShowBuffs) then
            LayoutIcons(entry.mixed, total, iconSize, spacing, perRow, growth, rowWrap)
            HideUnused(entry.mixed, total + 1)
        else
            HideUnused(entry.mixed, 1)
        end

        HideUnused(entry.debuffs, 1)
        HideUnused(entry.buffs, 1)
    else
        if finalShowDebuffs then
            LayoutIcons(entry.debuffs, debuffCount, iconSize, spacing, perRow, growth, rowWrap)
            HideUnused(entry.debuffs, debuffCount + 1)
        else
            HideUnused(entry.debuffs, 1)
        end

        if finalShowBuffs then
            LayoutIcons(entry.buffs, buffCount, iconSize, spacing, perRow, growth, rowWrap)
            HideUnused(entry.buffs, buffCount + 1)
        else
            HideUnused(entry.buffs, 1)
        end

        if entry.mixed then
            HideUnused(entry.mixed, 1)
        end
    end

    -- Commit render signatures + counts for the fast-path.
    -- Only commit for real units (never preview).
    if (not showTest) and unitExists then
        if rawSig and layoutSig then
            entry._msufA2_lastRawSig = rawSig
            entry._msufA2_lastLayoutSig = layoutSig
        end
        entry._msufA2_lastUseSingleRow = (useSingleRow and true) or false
        entry._msufA2_lastBuffCount = buffCount or 0
        entry._msufA2_lastDebuffCount = debuffCount or 0
        entry._msufA2_lastMixedCount = mixedCount or 0
        local st2 = entry._msufA2_budgetState
        entry._msufA2_lastQuickOK = (not (st2 and st2.pending == true)) and true or false
    end
end

-- Performance tracking for Auras2 rendering
local _A2_PERF = nil
local _A2_PERF_ENABLED = false
local _A2_PERF_NEXTCHECK = 0
local _A2_GetTime = _G and _G.GetTime
local _A2_debugprofilestop = _G and _G.debugprofilestop

-- Minimum time between full renders per unit (helps target-swap bursts).
-- Keep small enough to feel instant, but large enough to collapse multi-event storms into one render.
-- NOTE: Budget continuation renders (render budget resume) bypass this gate by design.
local MSUF_A2_MIN_RENDER_INTERVAL = 0.05

local function _A2_PerfEnsureTable()
    if not _G then return nil end
    if type(_G.MSUF_Auras2_Perf) ~= "table" then
        _G.MSUF_Auras2_Perf = {
            marks = 0,
            flushes = 0,
            marksSinceFlush = 0,
            lastFlushMs = 0,
            lastFlushUnits = 0,
            maxFlushMs = 0,
            maxFlushUnits = 0,
            maxMarksSinceFlush = 0,
        }
    end
    return _G.MSUF_Auras2_Perf
end

local function _A2_PerfEnabled()
    if not _A2_GetTime then return false end
    local now = _A2_GetTime()
    if now < _A2_PERF_NEXTCHECK then
        return _A2_PERF_ENABLED
    end

    _A2_PERF_NEXTCHECK = now + 1.0

    local enabled = false
    local profEnabled = (ns and ns.MSUF_ProfileEnabled)
    if type(profEnabled) == "function" and profEnabled() then
        enabled = true
    else
        local gdb = _G and _G.MSUF_DB
        if gdb and gdb.general and gdb.general.debugAuras2Perf == true then
            enabled = true
        end
    end

    _A2_PERF_ENABLED = enabled
    if enabled then
        _A2_PERF = _A2_PerfEnsureTable()
    else
        _A2_PERF = nil
    end

    return enabled
end


local function _A2_UnitEnabledFast(a2, unit)
    if not a2 or a2.enabled ~= true then return false end
    if unit == "target" then return a2.showTarget == true end
    if unit == "focus" then return a2.showFocus == true end
    if unit and unit:match("^boss%d$") then return a2.showBoss == true end
    return false
end

local function Flush()
    local doPerf = _A2_PerfEnabled()
    local perf = _A2_PERF
    local t0 = (doPerf and _A2_debugprofilestop and _A2_debugprofilestop()) or nil
    local unitsUpdated = 0

    local nextRenderDelay = nil
    local nowT = (_A2_GetTime and _A2_GetTime()) or (GetTime and GetTime()) or 0

    FlushScheduled = false
    local toUpdate = Dirty
    Dirty = AcquireDirtyTable()

    -- perf/peaks: hard-gate work when not relevant.
    -- Never render when the unitframe isn't visible (unless Edit Mode preview is active).
    local a2, shared = GetAuras2DB()
    local showTest = (shared and shared.showInEditMode and IsEditModeActive and IsEditModeActive()) and true or false

    for unit, _ in pairs(toUpdate) do
        local entry = AurasByUnit[unit]
        local frame = (entry and entry.frame) or FindUnitFrame(unit)

        if not frame then
            -- Unitframe not available: ensure anchors stay hidden.
            if entry and entry.anchor then entry.anchor:Hide() end
            if entry and entry.editMover then entry.editMover:Hide() end
        else
            if showTest then
                -- Preview mode: allow positioning even if unit is disabled or doesn't exist.
                local e = EnsureAttached(unit)
                if e then
                    RenderUnit(e)
                    unitsUpdated = unitsUpdated + 1
                end
            else
                -- Master/unit enable gate
                if not _A2_UnitEnabledFast(a2, unit) then
                    if entry and entry.anchor then entry.anchor:Hide() end
                    if entry and entry.editMover then entry.editMover:Hide() end

                -- Visibility gate: if the unitframe isn't shown, do zero work (anchor is hidden by OnHide)
                elseif not frame:IsShown() then
                    if entry and entry.anchor then entry.anchor:Hide() end
                    if entry and entry.editMover then entry.editMover:Hide() end

                else
                    -- Unit existence gate
                    local unitExists = UnitExists and UnitExists(unit)
                    if not unitExists then
                        if entry and entry.anchor then entry.anchor:Hide() end
                        if entry and entry.editMover then entry.editMover:Hide() end
                    else                        -- collapse multi-event storms by limiting full render frequency per unit.
                        -- Keep prior visuals; defer only the expensive RenderUnit call.
                        local doRender = true
                        if MSUF_A2_MIN_RENDER_INTERVAL and MSUF_A2_MIN_RENDER_INTERVAL > 0 then
                            local last = entry and entry._msufA2_lastRenderAt
                            if type(last) == 'number' then
                                local dt = nowT - last
                                if dt >= 0 and dt < MSUF_A2_MIN_RENDER_INTERVAL then
                                    local remaining = MSUF_A2_MIN_RENDER_INTERVAL - dt
                                    Dirty[unit] = true
                                    if remaining < 0 then remaining = 0 end
                                    if (not nextRenderDelay) or remaining < nextRenderDelay then
                                        nextRenderDelay = remaining
                                    end
                                    doRender = false
                                end
                            end
                        end

                        if doRender then
                            local e = EnsureAttached(unit)
                            if e then
                                e._msufA2_lastRenderAt = nowT
                                RenderUnit(e)
                                unitsUpdated = unitsUpdated + 1
                            end
                        end
                    end
                end
            end
        end
    end

    ReleaseDirtyTable(toUpdate)

    -- Schedule a deferred flush if we intentionally deferred expensive renders due to burst gating.
    if nextRenderDelay ~= nil and (not FlushScheduled) then
        FlushScheduled = true
        if nextRenderDelay < 0 then nextRenderDelay = 0 end
        C_Timer.After(nextRenderDelay, Flush)
    end

    -- Preview stack-count light refresh ticker must start/stop reliably when Edit Mode preview is shown.
    -- Do this here (coalesced flush point) so entering Edit Mode starts the ticker even if no options refresh
    -- function was invoked, while still keeping the ticker preview-only (no gameplay cost).
    if _G and _G.MSUF_Auras2_UpdatePreviewStackTicker then
        _G.MSUF_Auras2_UpdatePreviewStackTicker()
    end

    if doPerf and perf then
        local dt = (t0 and _A2_debugprofilestop and (_A2_debugprofilestop() - t0)) or 0

        perf.flushes = (perf.flushes or 0) + 1
        perf.lastFlushMs = dt
        perf.lastFlushUnits = unitsUpdated

        if dt > (perf.maxFlushMs or 0) then perf.maxFlushMs = dt end
        if unitsUpdated > (perf.maxFlushUnits or 0) then perf.maxFlushUnits = unitsUpdated end

        if (perf.marksSinceFlush or 0) > (perf.maxMarksSinceFlush or 0) then
            perf.maxMarksSinceFlush = perf.marksSinceFlush
        end
        perf.marksSinceFlush = 0
    end
end

local function MarkDirty(unit)
    Dirty[unit] = true

    -- Perf counters (debug-only). Keep this extremely light.
    if _A2_PerfEnabled() and _A2_PERF then
        local perf = _A2_PERF
        perf.marks = (perf.marks or 0) + 1
        perf.marksSinceFlush = (perf.marksSinceFlush or 0) + 1
        if (perf.marksSinceFlush or 0) > (perf.maxMarksSinceFlush or 0) then
            perf.maxMarksSinceFlush = perf.marksSinceFlush
        end
    end

    if FlushScheduled then return end
    FlushScheduled = true
    C_Timer.After(0, Flush)
end


-- ------------------------------------------------------------
-- Auras 2.0 Preview: light stack-count refresh (Edit Mode preview only)
-- ------------------------------------------------------------
local MSUF_A2_PreviewStackTicker

local function MSUF_A2_IsEditModeActive_Safe()
    if type(IsEditModeActive) == "function" then
        return IsEditModeActive()
    end
    if C_EditMode and C_EditMode.IsEditModeActive then
        return C_EditMode.IsEditModeActive()
    end
    if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive then
        return EditModeManagerFrame:IsEditModeActive()
    end
    return false
end

local function MSUF_A2_ShouldRunPreviewStackTicker()
    local a2, shared = GetAuras2DB()
    if not a2 or not shared then return false end
    if a2.enabled ~= true then return false end
    if shared.showInEditMode ~= true then return false end
    if shared.showStackCount == false then return false end
    if not MSUF_A2_IsEditModeActive_Safe() then return false end
    return true
end

local function MSUF_A2_PreviewStackLightRefresh()
    if not MSUF_A2_ShouldRunPreviewStackTicker() then
        if MSUF_A2_PreviewStackTicker then
            MSUF_A2_PreviewStackTicker:Cancel()
            MSUF_A2_PreviewStackTicker = nil
        end
        return
    end

    local a2, shared = GetAuras2DB()
    local pu = a2 and a2.perUnit

    for _, entry in pairs(AurasByUnit) do
        local function RefreshContainer(container)
            if not container or not container._msufIcons then return end
            for i = 1, #container._msufIcons do
                local icon = container._msufIcons[i]
                if icon and icon:IsShown() and icon._msufA2_isPreview == true and icon.count and icon._msufA2_previewStackCur then
                    -- Keep preview stack anchor live when the dropdown changes.
                    do
                        local unitKey = icon._msufUnit
                        local caps = nil
                        local uconf = (pu and unitKey and pu[unitKey]) or nil
                        if uconf and uconf.overrideSharedLayout == true and type(uconf.layoutShared) == "table" then
                            caps = uconf.layoutShared
                        end
                        local stackAnchor = (caps and caps.stackCountAnchor ~= nil) and caps.stackCountAnchor or (shared and shared.stackCountAnchor) or "TOPRIGHT"
                        MSUF_A2_ApplyStackCountAnchorStyle(icon, stackAnchor)
                    end

                    local maxN = icon._msufA2_previewStackMax
                    local curN = icon._msufA2_previewStackCur
                    local nextN = curN + 1

                    if type(maxN) == "number" then
                        if nextN > maxN then nextN = 1 end
                    else
                        if nextN > 5 then nextN = 1 end
                    end

                    icon._msufA2_previewStackCur = nextN
                    icon.count:SetText(tostring(nextN))
                    icon.count:Show()
                end
            end
        end

        RefreshContainer(entry.mixed)
        RefreshContainer(entry.debuffs)
        RefreshContainer(entry.buffs)
    end
end

local function MSUF_A2_UpdatePreviewStackTicker()
    local want = MSUF_A2_ShouldRunPreviewStackTicker()
    if want then
        if not MSUF_A2_PreviewStackTicker and C_Timer and C_Timer.NewTicker then
            MSUF_A2_PreviewStackTicker = C_Timer.NewTicker(0.4, MSUF_A2_PreviewStackLightRefresh)
        end
    else
        if MSUF_A2_PreviewStackTicker then
            MSUF_A2_PreviewStackTicker:Cancel()
            MSUF_A2_PreviewStackTicker = nil
        end
    end
end

_G.MSUF_Auras2_UpdatePreviewStackTicker = MSUF_A2_UpdatePreviewStackTicker

-- Public refresh (used by options)
function _G.MSUF_Auras2_RefreshAll()
    MarkDirty("target")
    MarkDirty("focus")
    for i = 1, 5 do
        MarkDirty("boss" .. i)
    end
    MSUF_A2_UpdatePreviewStackTicker()
end



-- Bind aura cooldown/stack texts to the global font pipeline (called from UpdateAllFonts).
function _G.MSUF_Auras2_ApplyFontsFromGlobal()
    local _, shared = GetAuras2DB()
    if type(AurasByUnit) ~= "table" then return end

    if type(MSUF_GetGlobalFontSettings) ~= "function" then return end
    local fontPath, fontFlags, _, _, _, _, useShadow = MSUF_GetGlobalFontSettings()

    -- If the user changed the global font color, rebuild the cooldown color curve's "normal" point.
    MSUF_A2_CooldownColorCurve = nil

    for unitKey, entry in pairs(AurasByUnit) do
        if entry then
            for _, container in ipairs({ entry.buffs, entry.debuffs, entry.mixed }) do
                if container and container._msufIcons then
                    local stackSize, cooldownSize = MSUF_A2_GetEffectiveTextSizes(unitKey, shared)
                    for i = 1, #container._msufIcons do
                        local icon = container._msufIcons[i]
                        if icon then
                            if icon.count then
                                local ok = MSUF_A2_ApplyFont(icon.count, fontPath, stackSize, fontFlags, useShadow)
                                if ok then
                                    icon._msufA2_lastStackTextSize = stackSize
                                end
                            end

                            if icon.cooldown then
                                -- Force a rescan of the countdown FontString on demand (built lazily by Blizzard)
                                icon.cooldown._msufCooldownFontString = nil
                                icon.cooldown._msufCooldownFontStringLastTry = 0
                            end
                            local cdFS = MSUF_A2_GetCooldownFontString(icon)
                            if cdFS then
                                local ok = MSUF_A2_ApplyFont(cdFS, fontPath, cooldownSize, fontFlags, useShadow)
                                if ok then
                                    icon._msufA2_lastCooldownTextSize = cooldownSize
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Public refresh (unit) (used by Edit Mode popups / targeted updates)
function _G.MSUF_Auras2_RefreshUnit(unit)
    if not unit then return end
    MarkDirty(unit)
    MSUF_A2_UpdatePreviewStackTicker()
end

-- Compatibility: core calls this during unitframe creation
function _G.MSUF_UpdateTargetAuras(frame)
    -- Frame arg is ignored (we look it up), but keep it for compatibility
    MarkDirty("target")
end

-- ------------------------------------------------------------
-- Events
-- ------------------------------------------------------------

-- oUF-style discipline: centralize event registration and track ownership.
-- This prevents "unknown event" unregister spam, and makes future per-feature event toggles safe.
local function MSUF_A2_ApplyOwnedEvents(frame, desiredOwners)
    if not frame or type(desiredOwners) ~= "table" then return end

    local reg = frame._msufA2_events
    if type(reg) ~= "table" then
        reg = {}
        frame._msufA2_events = reg
    end

    local isReg = frame.IsEventRegistered

    -- Unregister events no longer desired.
    for ev, _ in pairs(reg) do
        if not desiredOwners[ev] then
            if isReg and frame:IsEventRegistered(ev) then
                pcall(frame.UnregisterEvent, frame, ev)
            end
            reg[ev] = nil
        end
    end

    -- Register desired events and enforce deterministic owner.
    for ev, ownerKey in pairs(desiredOwners) do
        local have = reg[ev]
        if have ~= ownerKey then
            -- If already registered with a different owner, rebind deterministically.
            if have and isReg and frame:IsEventRegistered(ev) then
                pcall(frame.UnregisterEvent, frame, ev)
            end
            if (not isReg) or (not frame:IsEventRegistered(ev)) then
                pcall(frame.RegisterEvent, frame, ev)
            end
            reg[ev] = ownerKey
        else
            -- Ensure it is actually registered (external code may have unregistered it).
            if isReg and (not frame:IsEventRegistered(ev)) then
                pcall(frame.RegisterEvent, frame, ev)
            end
        end
    end
end

local function MSUF_A2_EnsureUnitAuraBinding(frame)
    if not frame or frame._msufA2_unitAuraBound == true then return end

    -- IMPORTANT: RegisterUnitEvent does NOT reliably "add" units across multiple calls on all clients.
    -- Register once with all units so Focus/Boss updates never get dropped.
    local regUnit = frame.RegisterUnitEvent
    if type(regUnit) ~= "function" then return end

    local units = { "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
    local unpackUnits = (unpack or table.unpack)
    SafeCall(regUnit, frame, "UNIT_AURA", unpackUnits(units))
    frame._msufA2_unitAuraBound = true
end

local EventFrame = CreateFrame("Frame")

local function MSUF_A2_ApplyEventRegistration()
    MSUF_A2_EnsureUnitAuraBinding(EventFrame)
    MSUF_A2_ApplyOwnedEvents(EventFrame, {
        PLAYER_LOGIN = "Core",
        PLAYER_ENTERING_WORLD = "Core",
        PLAYER_TARGET_CHANGED = "Core",
        PLAYER_FOCUS_CHANGED = "Core",
        INSTANCE_ENCOUNTER_ENGAGE_UNIT = "Core",
    })
end

-- Export for debugging / external triggers (safe no-op if called early).
_G.MSUF_Auras2_ApplyEventRegistration = MSUF_A2_ApplyEventRegistration

-- Apply once at load.
MSUF_A2_ApplyEventRegistration()


-- Step 9: Event coalescing + unit gating.
-- We already coalesce renders via MarkDirty + C_Timer.After(0, Flush).
-- Additionally, avoid scheduling work for units that are disabled (outside Edit Mode preview),
-- while still keeping options-driven RefreshAll() able to hide/show everything.
local function MSUF_A2_ShouldProcessUnitEvent(unit)
    if not unit then return false end
    local a2, shared = GetAuras2DB()
    if not a2 or not shared then return false end

    -- If unit auras are enabled, always process.
    if UnitEnabled(unit) then return true end

    -- In Edit Mode preview, still process so the user can position even when disabled.
    if shared.showInEditMode and IsEditModeActive() then
        return true
    end

    return false
end

EventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_AURA" then
        if arg1 and MSUF_A2_ShouldProcessUnitEvent(arg1) then
            MarkDirty(arg1)
        end
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        if MSUF_A2_ShouldProcessUnitEvent("target") then
            MarkDirty("target")
        end
        return
    end

    if event == "PLAYER_FOCUS_CHANGED" then
        if MSUF_A2_ShouldProcessUnitEvent("focus") then
            MarkDirty("focus")
        end
        return
    end

    if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        for i = 1, 5 do
            local u = "boss" .. i
            if MSUF_A2_ShouldProcessUnitEvent(u) then
                MarkDirty(u)
            end
        end
        return
    end

    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        -- Prime Auras2 DB once (keeps UNIT_AURA hot-path free of migrations/default work).
        EnsureDB() -- prime Auras2 DB
        -- Attach everything that already exists, then do a first render (coalesced).
        if MSUF_A2_ShouldProcessUnitEvent("target") then MarkDirty("target") end
        if MSUF_A2_ShouldProcessUnitEvent("focus") then MarkDirty("focus") end
        for i = 1, 5 do
            local u = "boss" .. i
            if MSUF_A2_ShouldProcessUnitEvent(u) then
                MarkDirty(u)
            end
        end
    end


-- Edit Mode preview refresh:
-- Prefer direct notifications from MSUF Edit Mode to avoid polling.
-- If the listener API is missing (older EditMode file), we fall back to a light poll
-- that is ONLY active while previews are enabled or while Edit Mode is currently active.
do
    local function MSUF_A2_EditModeRefresh(active)
        local _, shared = GetAuras2DB()
        local wantPreview = shared and (shared.showInEditMode == true) or false

        -- Always refresh on Edit Mode transitions (and on the Preview toggle), so previews
        -- can never linger and block real auras.
        if wantPreview ~= true then
            MSUF_A2_ClearAllPreviews()
        end

        MarkDirty("target")
        MarkDirty("focus")
        for i = 1, 5 do
            MarkDirty("boss" .. i)
        end
        MSUF_A2_UpdatePreviewStackTicker()
    end

    -- Export for debugging / external triggers
    _G.MSUF_Auras2_OnAnyEditModeChanged = MSUF_A2_EditModeRefresh

    -- Preferred path: subscribe to the shared MSUF Edit Mode notifications
    if type(_G.MSUF_RegisterAnyEditModeListener) == "function" then
        _G.MSUF_RegisterAnyEditModeListener(MSUF_A2_EditModeRefresh)
    else
        -- Fallback: light poll (gated so it does not prevent full idle when previews are off)
        local _last = nil
        local _acc = 0
        local _polling = false

        local function PollOnUpdate(_, elapsed)
            _acc = _acc + (elapsed or 0)
            if _acc < 0.25 then return end
            _acc = 0

            local cur = IsEditModeActive()
            if _last == nil then
                _last = cur
                return
            end

            if cur ~= _last then
                _last = cur
                MSUF_A2_EditModeRefresh(cur)
            end
        end

        local function UpdatePoll()
            local _, shared = GetAuras2DB()
            local wantPreview = shared and (shared.showInEditMode == true) or false
            local cur = IsEditModeActive()

            -- Poll only while needed: preview enabled OR currently in edit mode (to detect leaving).
            local wantPoll = (wantPreview == true) or (cur == true)

            if wantPoll and not _polling then
                _polling = true
                _acc = 0
                _last = cur
                EventFrame:SetScript("OnUpdate", PollOnUpdate)
            elseif (not wantPoll) and _polling then
                _polling = false
                EventFrame:SetScript("OnUpdate", nil)
            end
        end

        _G.MSUF_Auras2_UpdateEditModePoll = UpdatePoll

        -- Seed once (login/world) and whenever edit mode toggles through the poll itself
        UpdatePoll()
    end
end


end)

-- ------------------------------------------------------------
-- Standalone Settings panel (like Colors / Gameplay)
-- ------------------------------------------------------------

local function CreateTitle(panel, text)
    local t = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    t:SetText(text)
    return t
end

local function CreateSubText(panel, anchor, text)
    local t = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    t:SetText(text)
    t:SetWidth(660)
    t:SetJustifyH("LEFT")
    return t
end

local function MakeBox(parent, w, h)
    local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(w, h)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0, 0, 0, 0.35)
    f:SetBackdropBorderColor(1, 1, 1, 0.08)
    return f
end

-- ------------------------------------------------------------
-- Checkbox styling (match the rest of MSUF menus)
-- ------------------------------------------------------------

local function MSUF_ApplyMenuCheckboxStyle(cb)
    if not cb or cb.__MSUF_menuStyled then return end
    cb.__MSUF_menuStyled = true

    -- IMPORTANT:
    -- Do NOT make the whole row clickable via huge HitRectInsets here.
    -- In Auras 2.0 we have two columns; wide HitRects overlap and "steal" clicks.
    -- Instead, keep the button hit-rect tight and add a dedicated label-click button.
    cb:SetHitRectInsets(0, 0, 0, 0)

    -- Normalize button + label placement (match other MSUF menus)
    -- Match the footprint used across other MSUF menus (slightly larger than default).
    cb:SetSize(22, 22)
    if cb.text then
        cb.text:ClearAllPoints()
        cb.text:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        cb.text:SetJustifyH("LEFT")
    end

    -- Nuke Blizzard template textures (UICheckButtonTemplate varies across builds,
    -- so do it defensively by hiding all texture regions first).
    do
        local r = { cb:GetRegions() }
        for i = 1, #r do
            local region = r[i]
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                region:SetTexture(nil)
                region:Hide()
            end
        end
        local function Kill(tex)
            if tex then
                tex:SetTexture(nil)
                tex:Hide()
            end
        end
        Kill(cb:GetNormalTexture())
        Kill(cb:GetPushedTexture())
        Kill(cb:GetHighlightTexture())
        Kill(cb:GetDisabledTexture())
        Kill(cb:GetDisabledCheckedTexture())
        Kill(cb:GetCheckedTexture())
    end

    -- Visual size (small dark superellipse box + white tick)
    local VIS = 18

    -- Base: dark fill with rounded corners (superellipse mask)
    -- Use OVERLAY so the checkbox can never end up behind box backdrops/borders.
    local base = cb:CreateTexture(nil, "OVERLAY", nil, 0)
    base:EnableMouse(false)
    base:SetPoint("CENTER", cb, "CENTER", 0, 0)
    base:SetSize(VIS, VIS)
    base:SetTexture("Interface\\Buttons\\WHITE8x8")
    base:SetVertexColor(0.03, 0.03, 0.03, 0.95)

    local mask = cb:CreateMaskTexture()
    mask:SetTexture("Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\superellipse.png")
    mask:SetAllPoints(base)
    base:AddMaskTexture(mask)

    -- Subtle rim / outline
    local rim = cb:CreateTexture(nil, "OVERLAY", nil, 1)
    rim:EnableMouse(false)
    rim:SetPoint("CENTER", base, "CENTER", 0, 0)
    rim:SetSize(VIS, VIS)
    rim:SetTexture("Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\msuf_check_superellipse_hole.png")
    rim:SetVertexColor(1, 1, 1, 0.28)

    -- Tick
    local tick = cb:CreateTexture(nil, "OVERLAY", nil, 2)
    tick:EnableMouse(false)
    tick:SetPoint("CENTER", base, "CENTER", 0, 0)
    tick:SetSize(16, 16)
    tick:SetTexture("Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\msuf_check_tick_bold.png")
    tick:SetVertexColor(1, 1, 1, 1)

    cb._msufBase = base
    cb._msufRim  = rim
    cb._msufTick = tick

    local function Sync()
        local checked = cb:GetChecked() and true or false
        tick:SetShown(checked)

        if cb:IsEnabled() then
            base:SetAlpha(1.0)
            rim:SetAlpha(1.0)
            tick:SetAlpha(1.0)

            if checked then
                rim:SetVertexColor(1, 1, 1, 0.26)
            else
                rim:SetVertexColor(1, 1, 1, 0.20)
            end
        else
            base:SetAlpha(0.55)
            rim:SetAlpha(0.55)
            tick:SetAlpha(0.55)
        end
    end

    cb._msufSync = Sync
    cb:HookScript("OnClick", Sync)
    cb:HookScript("OnShow", Sync)
    cb:HookScript("OnEnable", Sync)
    cb:HookScript("OnDisable", Sync)

    -- Hover: brighten rim slightly
    cb:HookScript("OnEnter", function()
        if rim then rim:SetVertexColor(1, 1, 1, 0.34) end
    end)
    cb:HookScript("OnLeave", function()
        Sync()
    end)

    -- Make label clickable WITHOUT overlapping other columns.
    if cb.text and not cb._msufLabelButton then
        -- Put the label-click button on the panel (NOT the checkbox) so it remains clickable
        -- even if the label extends outside the 20x20 checkbox bounds.
        local lb = CreateFrame("Button", nil, cb:GetParent())
        cb._msufLabelButton = lb
        lb:SetFrameLevel(cb:GetFrameLevel() + 2)
        lb:SetPoint("TOPLEFT", cb.text, "TOPLEFT", -2, 2)
        lb:SetPoint("BOTTOMRIGHT", cb.text, "BOTTOMRIGHT", 2, -2)

        lb:SetScript("OnClick", function()
            if cb.Click then cb:Click() end
        end)

        -- Forward tooltip + hover
        lb:SetScript("OnEnter", function()
            if cb._msufRim then cb._msufRim:SetVertexColor(1, 1, 1, 0.34) end
            local onEnter = cb:GetScript("OnEnter")
            if onEnter then onEnter(cb) end
        end)
        lb:SetScript("OnLeave", function()
            if cb._msufSync then cb._msufSync() end
            local onLeave = cb:GetScript("OnLeave")
            if onLeave then onLeave(cb) end
        end)
    end

    Sync()
end


local function CreateCheckbox(parent, label, x, y, getter, setter, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    -- Prevent any box/backdrop overlays from swallowing clicks on first open.
    cb:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)
    cb.text:SetText(label)
    MSUF_ApplyMenuCheckboxStyle(cb)

    cb:SetScript("OnClick", function(self)
        local v = self:GetChecked() and true or false
        setter(v)
        _G.MSUF_Auras2_RefreshAll()

        if self._msufSync then self._msufSync() end
    end)

    cb:SetScript("OnShow", function(self)
        local v = getter()
        self:SetChecked(v and true or false)

        if self._msufSync then self._msufSync() end
    end)

    if tooltip then
        cb:SetScript("OnEnter", function(self)
            if not GameTooltip then return end

            -- Anchor tooltip consistently to the right of the hovered widget.
            -- Note: SetOwner signature can vary across clients, so we use a safe fallback.
            local owner = self
            if self._msufLabelButton and self._msufLabelButton.IsMouseOver and self._msufLabelButton:IsMouseOver() then
                owner = self._msufLabelButton
            end

            local ok = pcall(GameTooltip.SetOwner, GameTooltip, owner, "ANCHOR_NONE")
            if not ok then
                pcall(GameTooltip.SetOwner, GameTooltip, owner)
            end
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 12, 0)

            GameTooltip:SetText(label)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end

    return cb
end

-- IMPORTANT: Slider frame names must be globally unique.
-- Using a per-parent counter causes name collisions (and sliders "teleport" between boxes)
-- because OptionsSliderTemplate relies on globally-named regions (<Name>Text/Low/High).
local MSUF_Auras2_SliderGlobalCount = 0

local function CreateSlider(parent, label, minV, maxV, step, x, y, getter, setter)
    MSUF_Auras2_SliderGlobalCount = MSUF_Auras2_SliderGlobalCount + 1
    local sliderName = "MSUF_Auras2Slider_" .. tostring(MSUF_Auras2_SliderGlobalCount)

    local s = CreateFrame("Slider", sliderName, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:SetWidth(320)

    local txt = _G[sliderName .. "Text"] or s.Text
    if txt then txt:SetText(label) end
    local low = _G[sliderName .. "Low"] or s.Low
    if low then low:SetText(tostring(minV)) end
    local high = _G[sliderName .. "High"] or s.High
    if high then high:SetText(tostring(maxV)) end

    s:SetScript("OnValueChanged", function(self, value)
        -- Snap/clamp defensively. Some clients can deliver fractional values even with SetValueStep/ObeyStepOnDrag.
        local snapped = value
        if step and step > 0 then
            snapped = math.floor((snapped / step) + 0.5) * step
        end
        if snapped < minV then snapped = minV end
        if snapped > maxV then snapped = maxV end

        -- If we changed the value, push it back into the slider so the thumb matches the stored setting.
        if snapped ~= value then
            self:SetValue(snapped)
            return
        end

        setter(snapped)

        -- Default behavior: refresh all Auras 2.0 units (coalesced).
        -- Some sliders (Auras 2.0 caps) perform their own targeted refresh
        -- via their setters; those can opt out by setting __MSUF_skipAutoRefresh.
        if not self.__MSUF_skipAutoRefresh then
            if type(_G.MSUF_Auras2_RefreshAll) == "function" then
                _G.MSUF_Auras2_RefreshAll()
            end
        end
    end)

    s:SetScript("OnShow", function(self)
        self:SetValue(getter() or minV)
    end)

    return s
end

-- Compact slider variant used in the Auras 2.0 box.
-- Defaults to ~50% width to keep the layout clean.
local function CreateAuras2CompactSlider(parent, label, minV, maxV, step, x, y, width, getter, setter)
    local s = CreateSlider(parent, label, minV, maxV, step, x, y, getter, setter)
    if width and width > 0 then
        s:SetWidth(width)
    else
        -- Base template sliders are 320 in this file.
        s:SetWidth(160)
    end
    return s
end

-- Attach a compact numeric input to a slider.
-- For Auras 2.0, we keep the entry box centered UNDER the slider so it reads cleanly
-- in the two-column "Display" section.
local function AttachSliderValueBox(slider, minV, maxV, step, getter)
    if not slider or slider.__MSUF_hasValueBox then return end
    slider.__MSUF_hasValueBox = true

    local eb = CreateFrame("EditBox", nil, slider, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(3)
    eb:SetJustifyH("CENTER")
    eb:SetSize(44, 20)
    -- Center the numeric entry under the slider for cleaner two-column layouts.
    -- (Keeps Low/High labels visible on the left/right.)
    eb:SetPoint("TOP", slider, "BOTTOM", 0, -6)
    eb:SetText(tostring(slider:GetValue() or (getter and getter()) or minV))

    local function ClampRound(v)
        v = tonumber(v) or 0
        if step and step > 0 then
            v = math.floor((v / step) + 0.5) * step
        end
        if v < minV then v = minV end
        if v > maxV then v = maxV end
        return v
    end

    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local v = ClampRound(self:GetText())
        slider:SetValue(v) -- triggers the slider's OnValueChanged (setter + refresh)
        self:SetText(tostring(v))
        self:HighlightText(0, 0)
    end)

    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        local v = slider:GetValue() or (getter and getter()) or minV
        self:SetText(tostring(ClampRound(v)))
        self:HighlightText(0, 0)
    end)

    eb:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)

    eb:SetScript("OnEditFocusLost", function(self)
        local v = slider:GetValue() or (getter and getter()) or minV
        self:SetText(tostring(ClampRound(v)))
        self:HighlightText(0, 0)
    end)

    -- Keep the box in sync when the slider changes.
    slider:HookScript("OnValueChanged", function(self, value)
        if not eb:HasFocus() then
            value = ClampRound(value)
            eb:SetText(tostring(value))
        end
    end)

    slider.__MSUF_valueBox = eb
    return eb
end

-- Auras 2.0 style: small slider with a centered [-][value][+] control UNDER the bar.
-- This matches the "Outline thickness" style used elsewhere in MSUF.
-- Style helper used for the compact "Auras 2.0" layout controls.
-- Keeps the layout row looking clean (no stray min/max numbers, left-aligned titles, etc).
local function MSUF_StyleAuras2CompactSlider(s, opts)
    if not s then return end
    opts = opts or {}

    -- Hide the default Low/High range labels for a cleaner look.
    if opts.hideMinMax then
        local n = s:GetName()
        local low = (n and _G[n .. "Low"]) or s.Low
        local high = (n and _G[n .. "High"]) or s.High
        if low then low:SetText(""); low:Hide() end
        if high then high:SetText(""); high:Hide() end
    end

    -- Left-align the title (OptionsSliderTemplate defaults to centered).
    if opts.leftTitle then
        local n = s:GetName()
        local title = (n and _G[n .. "Text"]) or s.Text
        if title then
            title:ClearAllPoints()
            title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 4)
            title:SetJustifyH("LEFT")
        end
    end
end

-- Dropdown UX fix:
--  • Ensure dropdown frame width matches visual width
--  • Anchor the dropdown list directly under the control (prevents detached menus)
--  • Use single-choice (radio) selections so it reads like a real dropdown (not a toggle list)
local function MSUF_FixUIDropDown(dd, width)
    if not dd then return end

    -- Width: keep the template visuals intact (don't manually widen the parent frame).
    if width then
        -- UIDropDownMenu_SetWidth handles the internal regions (Text/Left/Middle/Right) correctly.
        UIDropDownMenu_SetWidth(dd, width)
    end

    -- Anchor: keep the list directly under the control.
    if type(UIDropDownMenu_SetAnchor) == "function" then
        UIDropDownMenu_SetAnchor(dd, 16, 0, "TOPLEFT", dd, "BOTTOMLEFT")
    end

    -- UX: make the whole dropdown area clickable WITHOUT changing visuals.
    -- Don't resize/reattach the template button (that can "split" the art).
    -- Instead, expand the arrow button's hit-rect to the left to cover the full dropdown width.
    local btn = dd.Button or (dd.GetName and dd:GetName() and _G[dd:GetName() .. "Button"]) or nil
    if btn and btn.SetHitRectInsets then
        local w = (dd.GetWidth and dd:GetWidth()) or nil
        if (not w or w <= 0) and width then
            -- UIDropDownMenuTemplate adds some padding beyond the requested width.
            w = width + 40
        end
        local bw = (btn.GetWidth and btn:GetWidth()) or 24
        local extend = 0
        if w and bw and w > bw then
            extend = w - bw
        end
        btn:SetHitRectInsets(-extend, 0, 0, 0)
    end
end

local function CreateDropdown(parent, label, x, y, getter, setter)
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y + 4)
    -- Keep this compact so it doesn't dominate the Auras 2.0 layout row.
    MSUF_FixUIDropDown(dd, 130)

    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 4)
    title:SetText(label)

    local function OnClick(self)
        setter(self.value)
        UIDropDownMenu_SetSelectedValue(dd, self.value)
        CloseDropDownMenus()
        _G.MSUF_Auras2_RefreshAll()
    end

	UIDropDownMenu_Initialize(dd, function()
	    local function AddItem(text, value)
	        local info = UIDropDownMenu_CreateInfo()
	        info.text = text
	        info.value = value
	        info.func = OnClick
	        info.keepShownOnClick = false
	        info.checked = function()
	            return (getter() == value)
	        end
	        -- radio style (default): no isNotRadio
	        UIDropDownMenu_AddButton(info)
	    end
	    AddItem("Grow Right", "RIGHT")
	    AddItem("Grow Left", "LEFT")
	    AddItem("Vertical Up", "UP")
	    AddItem("Vertical Down", "DOWN")
	end)

    dd:SetScript("OnShow", function()
        local v = getter() or "RIGHT"
        UIDropDownMenu_SetSelectedValue(dd, v)
        local txt = "Grow Right"
        if v == "LEFT" then
            txt = "Grow Left"
        elseif v == "UP" then
            txt = "Vertical Up"
        elseif v == "DOWN" then
            txt = "Vertical Down"
        end
        UIDropDownMenu_SetText(dd, txt)
    end)

    return dd
end

local function CreateLayoutDropdown(parent, x, y, getter, setter)
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y + 4)
    -- Keep Layout dropdown the same visual width as Growth.
    MSUF_FixUIDropDown(dd, 130)

    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 4)
    title:SetText("Layout")

    local function OnClick(self)
        setter(self.value)
        UIDropDownMenu_SetSelectedValue(dd, self.value)
        CloseDropDownMenus()
        _G.MSUF_Auras2_RefreshAll()

        -- Keep dependent UI (Buff/Debuff Anchor) in sync immediately.
        if parent and parent._msufA2_OnLayoutModeChanged then
            pcall(parent._msufA2_OnLayoutModeChanged)
        end
    end

    UIDropDownMenu_Initialize(dd, function()
	    local function AddItem(text, value)
	        local info = UIDropDownMenu_CreateInfo()
	        info.text = text
	        info.value = value
	        info.func = OnClick
	        info.keepShownOnClick = false
	        info.checked = function()
	            return (getter() == value)
	        end
	        UIDropDownMenu_AddButton(info)
	    end
	    AddItem("Separate rows", "SEPARATE")
	    AddItem("Single row (Mixed)", "SINGLE")
    end)

	dd:SetScript("OnShow", function()
	    local v = getter() or "SEPARATE"
	    UIDropDownMenu_SetSelectedValue(dd, v)
	    if v == "SINGLE" then
	        UIDropDownMenu_SetText(dd, "Single row (Mixed)")
	    else
	        UIDropDownMenu_SetText(dd, "Separate rows")
	    end

	    if parent and parent._msufA2_OnLayoutModeChanged then
	        pcall(parent._msufA2_OnLayoutModeChanged)
	    end
	end)

    return dd
end

local function CreateBuffDebuffAnchorDropdown(parent, x, y, getter, setter, layoutGetter)
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y + 4)
    MSUF_FixUIDropDown(dd, 180)

    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 4)
    title:SetText("Buff/Debuff Anchor")
    dd._msufTitle = title

    local function IsSeparateRows()
        if type(layoutGetter) == "function" then
            return (layoutGetter() or "SEPARATE") ~= "SINGLE"
        end
        return true
    end

    local function ApplyEnabledState()
        local ok = IsSeparateRows()
        if ok then
            if UIDropDownMenu_EnableDropDown then UIDropDownMenu_EnableDropDown(dd) end
            if dd._msufTitle then dd._msufTitle:SetTextColor(1, 1, 1) end
        else
            if UIDropDownMenu_DisableDropDown then UIDropDownMenu_DisableDropDown(dd) end
            if dd._msufTitle then dd._msufTitle:SetTextColor(0.5, 0.5, 0.5) end
        end
    end
    dd._msufApplyEnabledState = ApplyEnabledState

    local function ShowTooltip(self)
	-- Anchor the tooltip to the full dropdown (not the tiny arrow button),
	-- so it appears aligned over the whole control.
	if not GameTooltip then return end
	local anchor = dd
	if not anchor then return end
	GameTooltip:SetOwner(anchor, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint("BOTTOM", anchor, "TOP", 0, 8)
        GameTooltip:SetText("Buff/Debuff Anchor", 1, 1, 1)
        GameTooltip:AddLine("Controls how Buffs and Debuffs are placed around the unitframe.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Requires Layout: Separate rows.", 1, 0.82, 0, true)
        GameTooltip:AddLine("In 'Single row (Mixed)', buffs and debuffs share one row, so split anchoring is unavailable.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end

    local function HideTooltip()
        if GameTooltip then GameTooltip:Hide() end
    end

    dd:SetScript("OnEnter", ShowTooltip)
    dd:SetScript("OnLeave", HideTooltip)
    if dd.Button then
        dd.Button:SetScript("OnEnter", ShowTooltip)
        dd.Button:SetScript("OnLeave", HideTooltip)
    end

    local function OnClick(self)
        if not IsSeparateRows() then return end
        setter(self.value)
        UIDropDownMenu_SetSelectedValue(dd, self.value)
        CloseDropDownMenus()
        _G.MSUF_Auras2_RefreshAll()
    end

    UIDropDownMenu_Initialize(dd, function()
        local function AddItem(text, value)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.func = OnClick
            info.keepShownOnClick = false
            info.checked = function()
                return (getter() == value)
            end
            UIDropDownMenu_AddButton(info)
        end

        AddItem("Stacked (Legacy)", "STACKED")
        AddItem("Buffs Top / Debuffs Bottom", "TOP_BOTTOM_BUFFS")
        AddItem("Debuffs Top / Buffs Bottom", "TOP_BOTTOM_DEBUFFS")

        AddItem("Buffs Top / Debuffs Right", "TOP_RIGHT_BUFFS")
        AddItem("Debuffs Top / Buffs Right", "TOP_RIGHT_DEBUFFS")

        AddItem("Buffs Bottom / Debuffs Right", "BOTTOM_RIGHT_BUFFS")
        AddItem("Debuffs Bottom / Buffs Right", "BOTTOM_RIGHT_DEBUFFS")

        AddItem("Buffs Bottom / Debuffs Left", "BOTTOM_LEFT_BUFFS")
        AddItem("Debuffs Bottom / Buffs Left", "BOTTOM_LEFT_DEBUFFS")

        AddItem("Buffs Top / Debuffs Left", "TOP_LEFT_BUFFS")
        AddItem("Debuffs Top / Buffs Left", "TOP_LEFT_DEBUFFS")
    end)

    dd:SetScript("OnShow", function()
        local v = getter() or "STACKED"
        UIDropDownMenu_SetSelectedValue(dd, v)

        local txt = "Stacked (Legacy)"
        if v == "TOP_BOTTOM_BUFFS" then
            txt = "Buffs Top / Debuffs Bottom"
        elseif v == "TOP_BOTTOM_DEBUFFS" then
            txt = "Debuffs Top / Buffs Bottom"
        elseif v == "TOP_RIGHT_BUFFS" then
            txt = "Buffs Top / Debuffs Right"
        elseif v == "TOP_RIGHT_DEBUFFS" then
            txt = "Debuffs Top / Buffs Right"
        elseif v == "BOTTOM_RIGHT_BUFFS" then
            txt = "Buffs Bottom / Debuffs Right"
        elseif v == "BOTTOM_RIGHT_DEBUFFS" then
            txt = "Debuffs Bottom / Buffs Right"
        elseif v == "BOTTOM_LEFT_BUFFS" then
            txt = "Buffs Bottom / Debuffs Left"
        elseif v == "BOTTOM_LEFT_DEBUFFS" then
            txt = "Debuffs Bottom / Buffs Left"
        elseif v == "TOP_LEFT_BUFFS" then
            txt = "Buffs Top / Debuffs Left"
        elseif v == "TOP_LEFT_DEBUFFS" then
            txt = "Debuffs Top / Buffs Left"
        end
        UIDropDownMenu_SetText(dd, txt)

        ApplyEnabledState()
    end)

    return dd
end

local function CreateRowWrapDropdown(parent, x, y, getter, setter)
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y + 4)
    MSUF_FixUIDropDown(dd, 130)

    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 4)
    title:SetText("Wrap rows")

    local function OnClick(self)
        setter(self.value)
        UIDropDownMenu_SetSelectedValue(dd, self.value)
        CloseDropDownMenus()
        _G.MSUF_Auras2_RefreshAll()
    end

    UIDropDownMenu_Initialize(dd, function()
        local function AddItem(text, value)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.func = OnClick
            info.keepShownOnClick = false
            info.checked = function()
                return (getter() == value)
            end
            UIDropDownMenu_AddButton(info)
        end
        AddItem("2nd row down", "DOWN")
        AddItem("2nd row up", "UP")
    end)

    dd:SetScript("OnShow", function()
        local v = getter() or "DOWN"
        UIDropDownMenu_SetSelectedValue(dd, v)
        if v == "UP" then
            UIDropDownMenu_SetText(dd, "2nd row up")
        else
            UIDropDownMenu_SetText(dd, "2nd row down")
        end
    end)

    return dd
end

local function CreateStackAnchorDropdown(parent, x, y, getter, setter)
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y + 4)
    MSUF_FixUIDropDown(dd, 130)

    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 4)
    title:SetText("Stack Anchor")

    local function OnClick(self)
        setter(self.value)
        UIDropDownMenu_SetSelectedValue(dd, self.value)
        CloseDropDownMenus()
        if type(_G.MSUF_Auras2_RefreshAll) == "function" then _G.MSUF_Auras2_RefreshAll() end
    end

    UIDropDownMenu_Initialize(dd, function()
        local function AddItem(text, value)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.func = OnClick
            info.keepShownOnClick = false
            info.checked = function()
                return (getter() == value)
            end
            UIDropDownMenu_AddButton(info)
        end
        AddItem("Top Left", "TOPLEFT")
        AddItem("Top Right", "TOPRIGHT")
        AddItem("Bottom Left", "BOTTOMLEFT")
        AddItem("Bottom Right", "BOTTOMRIGHT")
    end)

    dd:SetScript("OnShow", function()
        local v = getter() or "TOPRIGHT"
        UIDropDownMenu_SetSelectedValue(dd, v)
        if v == "TOPLEFT" then
            UIDropDownMenu_SetText(dd, "Top Left")
        elseif v == "BOTTOMLEFT" then
            UIDropDownMenu_SetText(dd, "Bottom Left")
        elseif v == "BOTTOMRIGHT" then
            UIDropDownMenu_SetText(dd, "Bottom Right")
        else
            UIDropDownMenu_SetText(dd, "Top Right")
        end
    end)

    return dd
end


function ns.MSUF_RegisterAurasOptions_Full(parentCategory)
    if _G.MSUF_AurasPanel and _G.MSUF_AurasPanel.__MSUF_AurasBuilt then
        return _G.MSUF_AurasCategory
    end

    local panel = _G.MSUF_AurasPanel
    if not panel then
        panel = CreateFrame("Frame", "MSUF_AurasPanel", UIParent)
        panel.name = "Auras 2.0"
        _G.MSUF_AurasPanel = panel
        _G.MSUF_AurasOptionsPanel = panel
    end

    panel.__MSUF_AurasBuilt = true

    local title = CreateTitle(panel, "Midnight Simple Unit Frames - Auras 2.0")
    CreateSubText(panel, title, "Auras 2.0: Target / Focus / Boss 1-5.\nDefaults show ALL buffs & debuffs. This menu controls a shared layout for these units.")

	-- Top-right convenience button: enter/exit MSUF Edit Mode (MSUF frames only; no Blizzard frame taint).
	local editBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	editBtn:SetSize(140, 22)
	editBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -18)
	-- Keep it reliably above the scroll canvas in the new Blizzard Settings UI.
	if editBtn.SetFrameLevel and panel.GetFrameLevel then
		editBtn:SetFrameLevel((panel:GetFrameLevel() or 0) + 50)
	end
	editBtn:SetText("MSUF Edit Mode")

	local function MSUF_Auras2_IsEditModeActive()
		if type(_G.MSUF_IsMSUFEditModeActive) == "function" then
			return _G.MSUF_IsMSUFEditModeActive() and true or false
		end
		-- MSUF_EditMode.lua uses this as the shared/global active flag.
		return (_G.MSUF_UnitEditModeActive and true or false)
	end

	local function RefreshEditBtnText()
		if MSUF_Auras2_IsEditModeActive() then
			editBtn:SetText("Exit MSUF Edit Mode")
		else
			editBtn:SetText("MSUF Edit Mode")
		end
	end

	editBtn:SetScript("OnShow", RefreshEditBtnText)
	editBtn:SetScript("OnClick", function()
		if InCombatLockdown and InCombatLockdown() then
			if UIErrorsFrame and UIErrorsFrame.AddMessage then
				UIErrorsFrame:AddMessage("MSUF: Can't toggle Edit Mode in combat.", 1, 0.2, 0.2)
			end
			return
		end
		local isActive = MSUF_Auras2_IsEditModeActive()
		if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
			_G.MSUF_SetMSUFEditModeDirect(not isActive)
			-- State may flip on the next tick; update label after.
			if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
				C_Timer.After(0, RefreshEditBtnText)
			else
				RefreshEditBtnText()
			end
		else
			RefreshEditBtnText()
		end
	end)

	editBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(dd, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", dd, "TOPRIGHT", 12, 0)
		GameTooltip:SetText("MSUF Edit Mode", 1, 1, 1)
		GameTooltip:AddLine("Toggle MSUF Edit Mode (only affects Midnight Simple Unit Frames).", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	editBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -80)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -36, 16)

    local content = CreateFrame("Frame", nil, scroll)
    -- Size is corrected dynamically once controls are laid out (prevents dead scroll space).
    content:SetSize(780, 900)
    scroll:SetScrollChild(content)

    -- IMPORTANT:
    -- In the new Blizzard Settings canvas, this panel often receives its final size *after* the
    -- first OnShow / category selection. Legacy UIPanelScrollFrameTemplate can end up with a
    -- zero-sized scroll area on the first open, so you see only the title/subtext and have to
    -- click away/back to trigger a layout pass.
    --
    -- We hook OnSizeChanged and perform a one-shot refresh once the panel has a real size.
    -- This is the most reliable fix for the "must click twice" problem.
    panel.__msufAuras2_LastSizedW = panel.__msufAuras2_LastSizedW or 0
    panel.__msufAuras2_LastSizedH = panel.__msufAuras2_LastSizedH or 0

    -- The new Blizzard Settings canvas sometimes fails to fully layout/update legacy scroll frames
    -- and control OnShow scripts on the very first open. Users then have to click away/back.
    -- We provide a single, shared refresh path that Settings can call on selection.

    -- Layout (Step 3+): wide main box, Timer Colors box, Advanced box below
    local leftTop = MakeBox(content, 720, 460)
    leftTop:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

    -- Timer / cooldown text color controls live here (breakpoints are added in later steps).
    local timerBox = MakeBox(content, 720, 200)
    timerBox:SetPoint("TOPLEFT", leftTop, "BOTTOMLEFT", 0, -14)

    local advBox = MakeBox(content, 720, 460)
    advBox:SetPoint("TOPLEFT", timerBox, "BOTTOMLEFT", 0, -14)
    -- Movement controls are handled via MSUF Edit Mode now (no placeholder section here).

    -- Prevent dead scroll space: keep the scroll child height tight to the last section.
    local function MSUF_Auras2_UpdateContentHeight()
        if not (content and advBox and content.GetTop and advBox.GetBottom) then return end
        local top = content:GetTop()
        local bottom = advBox:GetBottom()
        if not top or not bottom then return end

        -- Add a small bottom padding so the last box doesn't stick to the edge.
        local h = (top - bottom) + 24
        if h < 10 then h = 10 end

        if content.__msufAuras2_lastAutoH ~= h then
            content.__msufAuras2_lastAutoH = h
            content:SetHeight(h)
        end
    end

    -- (kept as a local so we can call it from refresh paths below)
-- Helpers (Filters override only)
local advGate = {} -- checkboxes gated by 'Enable filters'
local ddEditFilters, cbOverrideFilters, cbOverrideCaps

local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    if type(CopyTable) == "function" then
        return CopyTable(src)
    end
    local dst = {}
    for k, v in pairs(src) do
        dst[k] = DeepCopy(v)
    end
    return dst
end

local function GetEditingKey()
    local k = panel.__msufAuras2_FilterEditKey
    if type(k) ~= "string" then k = "shared" end
    return k
end

local function GetEditingFilters()
    local a2 = select(1, GetAuras2DB())
    if not a2 or not a2.shared or type(a2.shared.filters) ~= "table" then return nil end

    local sf = a2.shared.filters
    local key = GetEditingKey()
    if key == "shared" then
        return sf
    end

    local u = a2.perUnit and a2.perUnit[key]
    if u and u.overrideFilters == true and type(u.filters) == "table" then
        return u.filters
    end
    return sf
end

-- ------------------------------------------------------------
-- Options UI helpers (reduce getter/setter boilerplate)
-- ------------------------------------------------------------
local function A2_DB()
    return select(1, GetAuras2DB())
end

local function A2_Settings()
    local _, s = GetAuras2DB()
    return s
end

local function A2_FilterBuffs()
    local f = GetEditingFilters()
    return f and f.buffs
end

local function A2_FilterDebuffs()
    local f = GetEditingFilters()
    return f and f.debuffs
end

-- Create a checkbox that reads/writes a boolean field path from a table returned by getTbl().
-- Supports one or two keys:   t[k1]  or  t[k1][k2].
local function CreateBoolCheckboxPath(parent, label, x, y, getTbl, k1, k2, tooltip, postSet)
    local function getter()
        local t = getTbl and getTbl()
        if not t then return nil end
        if k2 then
            t = t[k1]
            return t and t[k2]
        end
        return t[k1]
    end

    local function setter(v)
        local t = getTbl and getTbl()
        if not t then return end
        local b = (v == true)
        if k2 then
            t = t[k1]
            if t then t[k2] = b end
        else
            t[k1] = b
        end
        if postSet then postSet(b) end
    end

    return CreateCheckbox(parent, label, x, y, getter, setter, tooltip)
end

-- Unit toggles: MSUF-style on/off buttons (avoid checkbox ticks for the compact Units row)
local function CreateBoolToggleButtonPath(parent, label, x, y, width, height, getTbl, k1, k2, tooltip, postSet)
    local function getter()
        local t = getTbl and getTbl()
        if not t then return nil end
        if k2 then
            t = t[k1]
            return t and t[k2]
        end
        return t[k1]
    end

    local function setter(v)
        local t = getTbl and getTbl()
        if not t then return end
        local b = (v == true)
        if k2 then
            t = t[k1]
            if t then t[k2] = b end
        else
            t[k1] = b
        end
        if postSet then postSet(b) end
    end

    -- Rebuilt from scratch (no UIPanelButtonTemplate / no shared skinning).
    -- This avoids rare Settings/CvarLayout repaint issues where template FontStrings
    -- can appear invisible until the first hover.
    local btn = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn:SetSize(width or 110, height or 22)
    btn:EnableMouse(true)

    -- Background
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.06, 0.85)
    btn._msufBg = bg

    -- Border (match our simple 1px style)
    local border = CreateFrame("Frame", nil, btn, BackdropTemplateMixin and "BackdropTemplate" or nil)
    border:SetAllPoints()
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    border:SetBackdropBorderColor(0, 0, 0, 1)
    btn._msufBorder = border

    -- Highlight overlay
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    btn._msufHL = hl

    -- Label (we own the FontString entirely)
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    fs:SetText(label or "")
    fs:SetAlpha(1)
    btn._msufLabel = fs
    btn._msufLabelText = label or ""

    local function ApplyVisual()
        local on = getter() and true or false
        btn.__msufOn = on

        -- Ensure label always repaints (some settings layouts don't redraw until hover).
        if btn._msufLabel then
            btn._msufLabel:Show()
            btn._msufLabel:SetAlpha(1)
            btn._msufLabel:SetText(btn._msufLabelText or "")
            if btn._msufLabel.SetDrawLayer then
                btn._msufLabel:SetDrawLayer("OVERLAY", 7)
            end
            if btn._msufLabel.SetTextColor then
                if on then
                    btn._msufLabel:SetTextColor(0.2, 1, 0.2)
                else
                    btn._msufLabel:SetTextColor(1, 0.2, 0.2)
                end
            end
        end

        if btn._msufBg and btn._msufBg.SetColorTexture then
            if on then
                btn._msufBg:SetColorTexture(0.10, 0.10, 0.10, 0.92)
            else
                btn._msufBg:SetColorTexture(0.06, 0.06, 0.06, 0.85)
            end
        end

        btn:SetAlpha(1)
    end

    btn:SetScript("OnClick", function()
        setter(not (getter() and true or false))
        if type(_G.MSUF_Auras2_RefreshAll) == "function" then
            _G.MSUF_Auras2_RefreshAll()
        end
        ApplyVisual()
    end)

    btn:SetScript("OnMouseDown", function(self)
        if self._msufBg and self._msufBg.SetColorTexture then
            self._msufBg:SetColorTexture(1, 1, 1, 0.08)
        end
    end)

    btn:SetScript("OnMouseUp", function()
        ApplyVisual()
    end)

    btn:SetScript("OnShow", function()
        -- Defer one tick to survive Settings layout reflows.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, ApplyVisual)
        else
            ApplyVisual()
        end
    end)

    btn:SetScript("OnHide", function(self)
        -- Reset hover/press visuals so we never get "stuck" when switching menus.
        self:SetButtonState("NORMAL")
        if self._msufBg and self._msufBg.SetColorTexture then
            self._msufBg:SetColorTexture(0.06, 0.06, 0.06, 0.85)
        end
        if self._msufLabel then
            self._msufLabel:Show()
            self._msufLabel:SetAlpha(1)
            self._msufLabel:SetText(self._msufLabelText or "")
        end
    end)

    if tooltip then
        btn:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            local owner = self
            local ok = pcall(GameTooltip.SetOwner, GameTooltip, owner, "ANCHOR_NONE")
            if not ok then pcall(GameTooltip.SetOwner, GameTooltip, owner) end
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 12, 0)
            GameTooltip:SetText(label)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end

    return btn
end


local function BuildBoolPathCheckboxes(parent, entries, out)
    -- Schema helper for simple on/off checkboxes that map to a DB table path.
    -- entry = { label, x, y, getTbl, k1, k2, tooltip, refKey, postSet }
    for i = 1, #entries do
        local e = entries[i]
        local cb = CreateBoolCheckboxPath(parent, e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[9])
        if out and e[8] then
            out[e[8]] = cb
        end
    end
end

local function GetOverrideForEditing()
    local key = GetEditingKey()
    if key == "shared" then return false end
    local a2 = select(1, GetAuras2DB())
    if not a2 or not a2.perUnit or not a2.perUnit[key] then return false end
    return (a2.perUnit[key].overrideFilters == true)
end

local function SetOverrideForEditing(v)
    local key = GetEditingKey()
    if key == "shared" then return end

    local a2 = select(1, GetAuras2DB())
    if not a2 then return end
    a2.perUnit = (type(a2.perUnit) == "table") and a2.perUnit or {}

    if type(a2.perUnit[key]) ~= "table" then a2.perUnit[key] = {} end
    local u = a2.perUnit[key]
    if u.overrideFilters == nil then u.overrideFilters = false end

    if v == true then
        u.overrideFilters = true
        local sf = a2.shared and a2.shared.filters
        if type(u.filters) ~= "table" or u.filters == sf then
            u.filters = DeepCopy(sf or {})
        end
    else
        u.overrideFilters = false
    end

    -- Refresh UI state (checkbox enabled/disabled + values)
    C_Timer.After(0, function()
        if panel and panel.OnRefresh then panel.OnRefresh() end
    end)
end

local function GetOverrideCapsForEditing()
    local key = GetEditingKey()
    if key == "shared" then return false end
    local a2 = select(1, GetAuras2DB())
    if not a2 or not a2.perUnit or not a2.perUnit[key] then return false end
    return (a2.perUnit[key].overrideSharedLayout == true)
end



    local function A2_IsAuras2UnitKey(unitKey)
        if unitKey == "target" or unitKey == "focus" then return true end
        if type(unitKey) == "string" and unitKey:match("^boss%d+$") then return true end
        return false
    end

    -- Shared caps override helper (shared vs per-unit layoutShared)
    local function A2_GetCapsValue(unitKey, key, fallback)
        local a2, shared = GetAuras2DB()
        if not a2 or not shared then return fallback end

        if unitKey and unitKey ~= "shared" then
            local pu = a2.perUnit
            local u = pu and pu[unitKey]
            if u and u.overrideSharedLayout == true and type(u.layoutShared) == "table" then
                local v = u.layoutShared[key]
                if v ~= nil then
                    return v
                end
            end
        end

        local v = shared[key]
        if v ~= nil then
            return v
        end
        return fallback
    end

    local function A2_SetCapsValue(unitKey, key, value)
        local a2, shared = GetAuras2DB()
        if not a2 or not shared then return end

        local wrotePerUnit = false
        if unitKey and unitKey ~= "shared" then
            local pu = a2.perUnit
            local u = pu and pu[unitKey]
            if u and u.overrideSharedLayout == true then
                if type(u.layoutShared) ~= "table" then u.layoutShared = {} end
                u.layoutShared[key] = value
                wrotePerUnit = true
            end
        end

        if not wrotePerUnit then
            shared[key] = value
        end

        if wrotePerUnit and A2_IsAuras2UnitKey(unitKey) and type(_G.MSUF_Auras2_RefreshUnit) == "function" then
            _G.MSUF_Auras2_RefreshUnit(unitKey)
        elseif type(_G.MSUF_Auras2_RefreshAll) == "function" then
            _G.MSUF_Auras2_RefreshAll()
        end
    end
local function SetOverrideCapsForEditing(v)
    local key = GetEditingKey()
    if key == "shared" then return end

    local a2, shared = GetAuras2DB()
    if not a2 or not shared then return end
    a2.perUnit = (type(a2.perUnit) == "table") and a2.perUnit or {}

    if type(a2.perUnit[key]) ~= "table" then a2.perUnit[key] = {} end
    local u = a2.perUnit[key]
    if u.overrideSharedLayout == nil then u.overrideSharedLayout = false end

    if v == true then
        u.overrideSharedLayout = true
        if type(u.layoutShared) ~= "table" then u.layoutShared = {} end
        local ls = u.layoutShared
        -- Seed from Shared if missing so the UI reflects current values immediately.
        if ls.maxBuffs == nil then ls.maxBuffs = shared.maxBuffs end
        if ls.maxDebuffs == nil then ls.maxDebuffs = shared.maxDebuffs end
        if ls.perRow == nil then ls.perRow = shared.perRow end
        if ls.layoutMode == nil then ls.layoutMode = shared.layoutMode end
        if ls.growth == nil then ls.growth = shared.growth end
        if ls.rowWrap == nil then ls.rowWrap = shared.rowWrap end
        if ls.buffDebuffAnchor == nil then ls.buffDebuffAnchor = shared.buffDebuffAnchor end
        if ls.splitSpacing == nil then ls.splitSpacing = shared.splitSpacing end
        if ls.stackCountAnchor == nil then ls.stackCountAnchor = shared.stackCountAnchor end
    else
        u.overrideSharedLayout = false
    end

    if type(_G.MSUF_Auras2_RefreshAll) == "function" then
        _G.MSUF_Auras2_RefreshAll()
    end

    C_Timer.After(0, function()
        if panel and panel.OnRefresh then panel.OnRefresh() end
    end)
end


local function SyncLegacySharedFromSharedFilters()
    -- Keep legacy/shared fields in sync for backward compatibility.
    local a2, s = GetAuras2DB()
    if not (a2 and s and a2.shared and a2.shared.filters) then return end
    local f = a2.shared.filters
    if f.buffs and f.buffs.onlyMine ~= nil then s.onlyMyBuffs = (f.buffs.onlyMine == true) end
    if f.debuffs and f.debuffs.onlyMine ~= nil then s.onlyMyDebuffs = (f.debuffs.onlyMine == true) end
    if f.hidePermanent ~= nil then s.hidePermanent = (f.hidePermanent == true) end
end

local function SetCheckboxEnabled(cb, enabled)
    if not cb then return end
    cb:SetEnabled(enabled and true or false)
    if cb.text then
        if enabled then
            cb.text:SetTextColor(1, 1, 1)
        else
            cb.text:SetTextColor(0.5, 0.5, 0.5)
        end
    end
end

local function UpdateAdvancedEnabled()
    local f = GetEditingFilters()
    local master = (f and f.enabled == true) and true or false

    for i = 1, #advGate do
        SetCheckboxEnabled(advGate[i], master)
    end

    -- Override toggle is only meaningful for non-shared editing keys.
    local key = GetEditingKey()
    if cbOverrideFilters then
        SetCheckboxEnabled(cbOverrideFilters, key ~= "shared")
    end

    if cbOverrideCaps then
        SetCheckboxEnabled(cbOverrideCaps, key ~= "shared")
    end
end

-- ------------------------------------------------------------
    -- LEFT TOP: Auras 2.0 (minimal UX restructure)
    -- ------------------------------------------------------------
    local h1 = leftTop:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h1:SetPoint("TOPLEFT", leftTop, "TOPLEFT", 12, -10)
    h1:SetText("Auras 2.0")

    -- Master toggles (top cluster)
    CreateBoolCheckboxPath(leftTop, "Enable Auras 2.0", 12, -34, A2_DB, "enabled", nil,
        "Master toggle. When off, no auras are shown for Target/Focus/Boss.")

    -- Filters (master): gates all filter logic (Only-mine/Hide-permanent + Advanced)
    local cbEnableFilters = CreateBoolCheckboxPath(leftTop, "Enable filters", 200, -34, GetEditingFilters, "enabled", nil,
        "Master for all filtering for the selected profile (Shared or a per-unit override). When off, no filtering/highlight is applied.")

    -- Masque skinning (optional)
    -- NOTE: Keep the toggle UI state synced even if Masque loads after MSUF.
    local RefreshMasqueToggleState -- forward-declared so scripts can call it
    local cbMasque = CreateCheckbox(leftTop, "Enable Masque skinning", 200, -58,
        function() local _, s = GetAuras2DB(); return s and s.masqueEnabled end,
        function(v)
            local _, s = GetAuras2DB()
            if s then s.masqueEnabled = (v == true) end
        end,
        "Skins Auras 2.0 icons with Masque (if installed).\n\nWarning: Highlight borders (stealable/dispellable/own) may look odd with some Masque skins.")

    local cbMasqueDefaultTip = cbMasque.tooltipText

    local function MSUF_A2_IsMasqueReadyForToggle()
        -- If the group already exists, we're definitely good.
        if MSUF_MasqueAuras2 then return true end
        -- If the addon isn't loaded, don't offer the toggle.
        if not MSUF_A2_IsMasqueAddonLoaded() then return false end
        -- If the library isn't registered yet, treat as not ready (but this should be rare).
        local msq = (LibStub and LibStub("Masque", true)) or _G.Masque
        return msq ~= nil
    end

    RefreshMasqueToggleState = function()
        local _, s = GetAuras2DB()
        local ready = MSUF_A2_IsMasqueReadyForToggle()

        -- Always reflect the DB state visually (even if disabled), so it doesn't look "stuck".
        cbMasque:SetChecked((s and s.masqueEnabled) and true or false)
        SetCheckboxEnabled(cbMasque, ready)

        -- Our checkbox uses a custom tick overlay; programmatic SetChecked() does not
        -- automatically refresh that overlay, so sync it explicitly.
        if cbMasque._msufSync then cbMasque._msufSync() end

        if not ready then
            cbMasque.tooltipText = "Masque is not loaded/ready. Enable/load the Masque addon, then /reload."
        else
            cbMasque.tooltipText = cbMasqueDefaultTip
        end
    end

    -- Force reload on toggle, and revert if cancelled
    cbMasque:SetScript("OnClick", function(self)
        local _, shared = GetAuras2DB()
        if not shared then return end

        -- If Masque isn't loaded, keep it disabled and unchecked.
        if not MSUF_A2_EnsureMasqueGroup() then
            shared.masqueEnabled = false
            self:SetChecked(false)
            RefreshMasqueToggleState()
            return
        end

        local old = (shared.masqueEnabled == true) and true or false
        local new = self:GetChecked() and true or false
        shared.masqueEnabled = new

        -- Keep the custom tick overlay in sync even if other code adjusts the checked state.
        if self._msufSync then self._msufSync() end

        if type(_G.MSUF_Auras2_RefreshAll) == "function" then
            _G.MSUF_Auras2_RefreshAll()
        end

        _G.MSUF_A2_MASQUE_RELOAD_PREV = old
        _G.MSUF_A2_MASQUE_RELOAD_CB = self
        StaticPopup_Show("MSUF_A2_RELOAD_MASQUE")
    end)

    cbMasque:SetScript("OnShow", function(self)
        RefreshMasqueToggleState()
    end)


-- Filter editing (Shared/Unit) + override toggle (filters only)
do
    local editLbl = leftTop:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    editLbl:SetPoint("TOPLEFT", leftTop, "TOPLEFT", 380, -36)
    editLbl:SetText("Edit filters:")

    ddEditFilters = CreateFrame("Frame", "MSUF_Auras2_EditFiltersDropDown", leftTop, "UIDropDownMenuTemplate")
    ddEditFilters:SetPoint("TOPLEFT", leftTop, "TOPLEFT", 452, -42)
    MSUF_FixUIDropDown(ddEditFilters, 160)

    local labelForKey = {
        shared = "Shared",
        player = "Player",
        target = "Target",
        focus = "Focus",
        boss1 = "Boss 1",
        boss2 = "Boss 2",
        boss3 = "Boss 3",
        boss4 = "Boss 4",
        boss5 = "Boss 5",
    }

    local function ApplyKey(key)
        panel.__msufAuras2_FilterEditKey = key
        if ddEditFilters and labelForKey then
            UIDropDownMenu_SetText(ddEditFilters, labelForKey[key] or "Shared")
        end
        if panel and panel.OnRefresh then panel.OnRefresh() end
    end

    UIDropDownMenu_Initialize(ddEditFilters, function(self, level)
        local function Add(text, key)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.func = function() ApplyKey(key); CloseDropDownMenus() end
            info.checked = function() return GetEditingKey() == key end
	            info.keepShownOnClick = false
	            -- radio style (default): no isNotRadio
            UIDropDownMenu_AddButton(info, level)
        end
        Add("Shared", "shared")
        Add("Player", "player")
        Add("Target", "target")
        Add("Focus", "focus")
        Add("Boss 1", "boss1")
        Add("Boss 2", "boss2")
        Add("Boss 3", "boss3")
        Add("Boss 4", "boss4")
        Add("Boss 5", "boss5")
    end)

    ddEditFilters:SetScript("OnShow", function(self)
        local key = GetEditingKey()
        UIDropDownMenu_SetText(self, labelForKey[key] or "Shared")
    end)

    cbOverrideFilters = CreateCheckbox(leftTop, "Override shared filters", 380, -70,
        function() return GetOverrideForEditing() end,
        function(v) SetOverrideForEditing(v) end,
        "When off, this unit uses Shared filter settings. When on, it uses its own copy of the filters.")


    cbOverrideCaps = CreateCheckbox(leftTop, "Override shared caps", 380, -92,
        function() return GetOverrideCapsForEditing() end,
        function(v) SetOverrideCapsForEditing(v) end,
        "When off, this unit uses Shared caps (Max Buffs/Debuffs, Icons per row). When on, it uses its own caps.")
    -- Overrides: global summary + reset (good UX)
    -- Layout goals:
    --  • Checkbox + Reset sit on the SAME row (no overlap with dropdown)
    --  • Status sits under the checkbox (short + readable)
    --  • Status stays "short": shows up to 2 units, then "+N"
    local overrideKeys = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }

    -- Reset button aligned to the right edge of the box, same row as the checkbox
    local btnResetOverrides = CreateFrame("Button", nil, leftTop, "UIPanelButtonTemplate")
    btnResetOverrides:SetSize(92, 18)
    btnResetOverrides:SetPoint("TOPRIGHT", leftTop, "TOPRIGHT", -24, -70)
    btnResetOverrides:SetText("Reset")

    -- Status row under checkbox
    local overrideRow = CreateFrame("Frame", nil, leftTop)
    overrideRow:SetPoint("TOPLEFT", cbOverrideCaps, "BOTTOMLEFT", 24, -4)
    overrideRow:SetSize(360, 18)

    local overrideInfo = overrideRow:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    overrideInfo:SetPoint("TOPLEFT", overrideRow, "TOPLEFT", 0, -1)
    overrideInfo:SetWidth(340)
    overrideInfo:SetJustifyH("LEFT")
    local function BuildOverrideSummary(active)
        local n = #active
        if n == 0 then
            return "|cff9aa0a6No overrides active.|r"
        end
        if n <= 2 then
            return "|cffffffffOverrides:|r " .. table.concat(active, ", ")
        end
        -- Keep it short: show first two, then "+N"
        return ("|cffffffffOverrides:|r %s, %s |cff9aa0a6+%d|r"):format(active[1], active[2], (n - 2))
    end

    local function UpdateOverrideSummary()
        local a2 = select(1, GetAuras2DB())
        local active = {}
        if a2 and type(a2.perUnit) == "table" then
            for i = 1, #overrideKeys do
                local k = overrideKeys[i]
                local u = a2.perUnit[k]
                if u and (u.overrideFilters == true or u.overrideSharedLayout == true) then
                    active[#active + 1] = (labelForKey[k] or k)
                end
            end
        end

        overrideInfo:SetText(BuildOverrideSummary(active))

        if #active == 0 then
            overrideInfo:SetFontObject(GameFontDisableSmall)
            btnResetOverrides:Disable()
            btnResetOverrides:SetAlpha(0.45)
        else
            overrideInfo:SetFontObject(GameFontHighlightSmall)
            btnResetOverrides:Enable()
            btnResetOverrides:SetAlpha(1)
        end
    end

    overrideRow:SetScript("OnShow", UpdateOverrideSummary)
    btnResetOverrides:SetScript("OnShow", UpdateOverrideSummary)

    btnResetOverrides:SetScript("OnClick", function()
        local a2 = select(1, GetAuras2DB())
        if not a2 then return end
        a2.perUnit = (type(a2.perUnit) == "table") and a2.perUnit or {}
        for i = 1, #overrideKeys do
            local k = overrideKeys[i]
            local u = a2.perUnit[k]
            if type(u) == "table" then
                u.overrideFilters = false
                u.filters = nil -- revert to Shared
                u.overrideSharedLayout = false
                u.layoutShared = nil -- revert to Shared
            end
        end

        if type(_G.MSUF_Auras2_RefreshAll) == "function" then
            _G.MSUF_Auras2_RefreshAll()
        end

        C_Timer.After(0, function()
            if panel and panel.OnRefresh then panel.OnRefresh() end
        end)
    end)

    btnResetOverrides:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(dd, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", dd, "TOPRIGHT", 12, 0)
        GameTooltip:SetText("Reset overrides", 1, 1, 1)
        GameTooltip:AddLine("Turns off Override shared filters and caps for all units and reverts them to Shared.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btnResetOverrides:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

    CreateCheckbox(leftTop, "Preview in Edit Mode", 12, -58,
        function() local _, s = GetAuras2DB(); return s and s.showInEditMode end,
        function(v)
            local _, s = GetAuras2DB()
            if s then
                s.showInEditMode = (v == true)
            end
            if type(_G.MSUF_Auras2_UpdateEditModePoll) == "function" then
                _G.MSUF_Auras2_UpdateEditModePoll()
            end
            if type(_G.MSUF_Auras2_OnAnyEditModeChanged) == "function" then
                _G.MSUF_Auras2_OnAnyEditModeChanged(IsEditModeActive())
            end
        end,

        "When enabled, placeholder auras can be shown while MSUF Edit Mode is active.")

    do
        local _oldClick = cbEnableFilters:GetScript("OnClick")
        cbEnableFilters:SetScript("OnClick", function(self)
            if _oldClick then _oldClick(self) end
            UpdateAdvancedEnabled()
        end)

        local _oldShow = cbEnableFilters:GetScript("OnShow")
        cbEnableFilters:SetScript("OnShow", function(self)
            if _oldShow then _oldShow(self) end
            UpdateAdvancedEnabled()
        end)
    end

    -- Units
    local h2 = leftTop:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h2:SetPoint("TOPLEFT", leftTop, "TOPLEFT", 12, -92)
    h2:SetText("Units")
    -- Compact unit toggles: use MSUF on/off buttons (no checkbox tick coloring).
    CreateBoolToggleButtonPath(leftTop, "Target", 12, -120, 110, 22, A2_DB, "showTarget")
    CreateBoolToggleButtonPath(leftTop, "Focus", 140, -120, 110, 22, A2_DB, "showFocus")
    CreateBoolToggleButtonPath(leftTop, "Boss 1-5", 260, -120, 110, 22, A2_DB, "showBoss")

    -- Display (two-column layout)
    local h3 = leftTop:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h3:SetPoint("TOPLEFT", leftTop, "TOPLEFT", 12, -156)
    h3:SetText("Display")

    local TIP_SHOW_STACK = 'Shows stack/application counts (e.g. "2") on aura icons. Disable to hide stack numbers.'
    local TIP_HIDE_PERMANENT = 'Hides buffs with no duration. Debuffs are never hidden by this option.\n\nNote: Target/Focus APIs may still show permanent buffs during combat due to API limitations.'
    local TIP_ADV_INFO = 'Use "Enable filters" in the Auras 2.0 box as the master switch.\n\nInclude toggles are additive (they never hide your normal auras).\nHighlight toggles only change border colors.\n\nDebuff types: if you select ANY type, debuffs are limited to the selected types.'


    BuildBoolPathCheckboxes(leftTop, {
        { "Show Buffs", 12, -180, A2_Settings, "showBuffs" },
        { "Show Debuffs", 200, -180, A2_Settings, "showDebuffs" },

        { "Highlight own buffs", 12, -228, A2_Settings, "highlightOwnBuffs", nil,
            "Highlights your own buffs with a border color (visual only; does not filter)." },
        { "Highlight own debuffs", 200, -228, A2_Settings, "highlightOwnDebuffs", nil,
            "Highlights your own debuffs with a border color (visual only; does not filter)." },

        { "Show cooldown swipe", 12, -252, A2_Settings, "showCooldownSwipe" },
        { "Show stack count", 200, -276, A2_Settings, "showStackCount", nil, TIP_SHOW_STACK },
        { "Show tooltip", 12, -276, A2_Settings, "showTooltip" },
    })

    -- Only-mine + permanent filters are stored per-unit (Target first), but we also sync shared fields for now.
    BuildBoolPathCheckboxes(leftTop, {
        { "Only my buffs", 12, -204, A2_FilterBuffs, "onlyMine", nil, nil, nil, SyncLegacySharedFromSharedFilters },
        { "Only my debuffs", 200, -204, A2_FilterDebuffs, "onlyMine", nil, nil, nil, SyncLegacySharedFromSharedFilters },
        { "Hide permanent buffs", 200, -252, GetEditingFilters, "hidePermanent", nil, TIP_HIDE_PERMANENT, nil, SyncLegacySharedFromSharedFilters },
    })

    -- Caps (live here in the Auras 2.0 box) + numeric entry boxes
    local function MakeCapsNumberGS(key, default, legacyKey)
        local function get()
            local a2, shared = GetAuras2DB()
            if not shared then return default end

            local v
            local editKey = GetEditingKey()
            if editKey ~= "shared" and a2 and a2.perUnit then
                local u = a2.perUnit[editKey]
                if u and u.overrideSharedLayout == true and type(u.layoutShared) == "table" then
                    v = u.layoutShared[key]
                end
            end

            if v == nil then v = shared[key] end
            if v == nil and legacyKey then v = shared[legacyKey] end
            if v == nil then v = default end
            return v
        end

        local function set(v)
            -- Idempotent: avoid double-apply (OnEnterPressed -> ClearFocus -> OnEditFocusLost)
            -- and avoid spurious refreshes when the slider initializes.
            local cur = get()
            if type(cur) == "number" and cur == v then
                return
            end

            -- Use the shared/per-unit caps writer (overrideSharedCaps aware) so we also
            -- get the correct targeted refresh behavior.
            local editKey = GetEditingKey()
            A2_SetCapsValue(editKey, key, v)
        end

        return get, set
    end

    local GetMaxBuffs, SetMaxBuffs = MakeCapsNumberGS("maxBuffs", 12, "maxIcons")
    local GetMaxDebuffs, SetMaxDebuffs = MakeCapsNumberGS("maxDebuffs", 12, "maxIcons")
    local GetPerRow, SetPerRow = MakeCapsNumberGS("perRow", 12)
    local GetSplitSpacing, SetSplitSpacingRaw = MakeCapsNumberGS("splitSpacing", 0)
    local function SetSplitSpacing(v)
        local key = GetEditingKey()
        local mode = A2_GetCapsValue(key, "layoutMode", "SEPARATE")
        if mode == "SINGLE" then return end
        SetSplitSpacingRaw(v)
    end

	-- Dropdown column layout (Auras 2.0 Display): align with the "Show Debuffs" row and keep
	-- everything safely to the right so it never overlaps the 2-column checkbox area.
	local A2_DD_X = 500
	local A2_DD_Y0 = -180 -- aligns with "Show Debuffs"
	local A2_DD_STEP = 24

    -- Caps: restore Max Buffs / Max Debuffs controls (0 = unlimited)
    -- Caps: moved slightly down so the sliders breathe under the tooltip/stack toggles.
    local maxBuffsSlider = CreateAuras2CompactSlider(leftTop, "Max Buffs", 0, 40, 1, 12, -336, nil, GetMaxBuffs, SetMaxBuffs)
    -- Caps sliders manage refresh via A2_SetCapsValue (targeted/coalesced). Avoid double refresh.
    maxBuffsSlider.__MSUF_skipAutoRefresh = true
    MSUF_StyleAuras2CompactSlider(maxBuffsSlider, { leftTitle = true })
    AttachSliderValueBox(maxBuffsSlider, 0, 40, 1, GetMaxBuffs)

    local maxDebuffsSlider = CreateAuras2CompactSlider(leftTop, "Max Debuffs", 0, 40, 1, 200, -336, nil, GetMaxDebuffs, SetMaxDebuffs)
    maxDebuffsSlider.__MSUF_skipAutoRefresh = true
    MSUF_StyleAuras2CompactSlider(maxDebuffsSlider, { leftTitle = true })
    AttachSliderValueBox(maxDebuffsSlider, 0, 40, 1, GetMaxDebuffs)

    -- Split-anchor spacing: when buff/debuff blocks are anchored around the unitframe, this controls
    -- how far they are pushed away from the frame edges.
    local splitSpacingSlider = CreateAuras2CompactSlider(leftTop, "Block spacing", 0, 40, 1, 200, -414, nil, GetSplitSpacing, SetSplitSpacing)
    splitSpacingSlider.__MSUF_skipAutoRefresh = true
    MSUF_StyleAuras2CompactSlider(splitSpacingSlider, { leftTitle = true })
    AttachSliderValueBox(splitSpacingSlider, 0, 40, 1, GetSplitSpacing)

    -- Disable Block spacing when Layout is Single row (Mixed) (it has no effect there).
    local function A2_IsSeparateRowsNow()
        local key = GetEditingKey()
        return (A2_GetCapsValue(key, "layoutMode", "SEPARATE") ~= "SINGLE")
    end

    local function A2_ApplySplitSpacingEnabledState()
        if not splitSpacingSlider then return end
        local ok = A2_IsSeparateRowsNow()
        if ok then
            splitSpacingSlider:Enable()
        else
            splitSpacingSlider:Disable()
        end
        local n = splitSpacingSlider:GetName()
        local title = (n and _G[n .. "Text"]) or splitSpacingSlider.Text
        if title then
            if ok then title:SetTextColor(1, 1, 1) else title:SetTextColor(0.5, 0.5, 0.5) end
        end
        if splitSpacingSlider.__MSUF_valueBox then
            if ok then
                splitSpacingSlider.__MSUF_valueBox:Enable()
                splitSpacingSlider.__MSUF_valueBox:SetAlpha(1)
            else
                splitSpacingSlider.__MSUF_valueBox:Disable()
                splitSpacingSlider.__MSUF_valueBox:SetAlpha(0.6)
            end
        end
    end
    leftTop._msufA2_ApplySplitSpacingEnabledState = A2_ApplySplitSpacingEnabledState
    A2_ApplySplitSpacingEnabledState()

    local function ShowSplitSpacingTooltip()
        if not GameTooltip then return end
        GameTooltip:SetOwner(splitSpacingSlider, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", splitSpacingSlider, "TOPRIGHT", 12, 0)
        GameTooltip:SetText("Block spacing", 1, 1, 1)
        GameTooltip:AddLine("Controls how far Buff and Debuff blocks are pushed away from the unitframe when using split anchors.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Requires Layout: Separate rows.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end
    local function HideAnyTooltip() if GameTooltip then GameTooltip:Hide() end end
    splitSpacingSlider:SetScript("OnEnter", ShowSplitSpacingTooltip)
    splitSpacingSlider:SetScript("OnLeave", HideAnyTooltip)
    if splitSpacingSlider.__MSUF_valueBox then
        splitSpacingSlider.__MSUF_valueBox:SetScript("OnEnter", ShowSplitSpacingTooltip)
        splitSpacingSlider.__MSUF_valueBox:SetScript("OnLeave", HideAnyTooltip)
    end


    -- Layout row (cleaner): Icons-per-row on the left, Growth dropdown aligned on the right.
    local perRowSlider = CreateAuras2CompactSlider(leftTop, "Icons per row", 4, 20, 1, 12, -414, nil, GetPerRow, SetPerRow)
    perRowSlider.__MSUF_skipAutoRefresh = true
    MSUF_StyleAuras2CompactSlider(perRowSlider, { leftTitle = true })
    AttachSliderValueBox(perRowSlider, 4, 20, 1, GetPerRow)

    -- Grow direction (right column)
    CreateDropdown(leftTop, "Growth", A2_DD_X, A2_DD_Y0 - (A2_DD_STEP * 9) - 8,
        function() local key = GetEditingKey(); return A2_GetCapsValue(key, "growth", "RIGHT") end,
        function(v) local key = GetEditingKey(); A2_SetCapsValue(key, "growth", v) end)

	-- Layout mode / layout helpers (right column)

	-- Row wrap direction for per-row limits (when icons exceed "Icons per row").
	-- This controls whether the 2nd row spawns below (default) or above the first row.
	CreateRowWrapDropdown(leftTop, A2_DD_X, A2_DD_Y0,
        function() local key = GetEditingKey(); return A2_GetCapsValue(key, "rowWrap", "DOWN") end,
        function(v) local key = GetEditingKey(); A2_SetCapsValue(key, "rowWrap", v) end)

    local layoutDD = CreateLayoutDropdown(leftTop, A2_DD_X, A2_DD_Y0 - A2_DD_STEP,
        function() local key = GetEditingKey(); return A2_GetCapsValue(key, "layoutMode", "SEPARATE") end,
        function(v) local key = GetEditingKey(); A2_SetCapsValue(key, "layoutMode", v) end)

	-- Stack Anchor dropdown (right column)
	CreateStackAnchorDropdown(leftTop, A2_DD_X, A2_DD_Y0 - (A2_DD_STEP * 3) - 8,
        function() local key = GetEditingKey(); return A2_GetCapsValue(key, "stackCountAnchor", "TOPRIGHT") end,
        function(v) local key = GetEditingKey(); A2_SetCapsValue(key, "stackCountAnchor", v) end)

    -- Buff/Debuff placement around the unitframe (Blizzard-like)
    local buffDebuffAnchorDD = CreateBuffDebuffAnchorDropdown(leftTop, A2_DD_X, A2_DD_Y0 - (A2_DD_STEP * 5) - 12,
        function() local key = GetEditingKey(); return A2_GetCapsValue(key, "buffDebuffAnchor", "STACKED") end,
        function(v) local key = GetEditingKey(); A2_SetCapsValue(key, "buffDebuffAnchor", v) end,
        function() local key = GetEditingKey(); return A2_GetCapsValue(key, "layoutMode", "SEPARATE") end)

    -- Allow the Layout dropdown to notify dependent widgets immediately.
    leftTop._msufA2_OnLayoutModeChanged = function()
        if buffDebuffAnchorDD and buffDebuffAnchorDD._msufApplyEnabledState then
            pcall(buffDebuffAnchorDD._msufApplyEnabledState)
        end

        if leftTop._msufA2_ApplySplitSpacingEnabledState then
            pcall(leftTop._msufA2_ApplySplitSpacingEnabledState)
        end
    end



    -- ------------------------------------------------------------
    -- TIMER COLORS (middle): global master toggle
    -- ------------------------------------------------------------
    do
        local tTitle = timerBox:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
        tTitle:SetPoint('TOPLEFT', timerBox, 'TOPLEFT', 12, -10)
        tTitle:SetText('Timer colors')

        local function GetGeneral()
            EnsureDB()
            return (MSUF_DB and MSUF_DB.general) or nil
        end

        

        CreateBoolCheckboxPath(timerBox, 'Color aura timers by remaining time', 12, -34, GetGeneral, 'aurasCooldownTextUseBuckets', nil,
            'When enabled, aura cooldown text uses Safe / Warning / Urgent colors based on remaining time.\nWhen disabled, aura cooldown text always uses the Safe color.',
            function()
                if timerBox and timerBox._msufApplyTimerColorsEnabledState then
                    pcall(timerBox._msufApplyTimerColorsEnabledState)
                end
                if _G.MSUF_A2_InvalidateCooldownTextCurve then _G.MSUF_A2_InvalidateCooldownTextCurve() end
                if _G.MSUF_A2_ForceCooldownTextRecolor then _G.MSUF_A2_ForceCooldownTextRecolor() end
            end)


        -- Breakpoint sliders (seconds).
        -- These are global (General) settings because cooldown text styling is global.

        local function GetSafe()
            local g = GetGeneral()
            return (g and g.aurasCooldownTextSafeSeconds) or 60
        end
        local function GetWarn()
            local g = GetGeneral()
            local v = (g and g.aurasCooldownTextWarningSeconds) or 15
            if type(v) ~= 'number' then v = 15 end
            if v > 30 then v = 30 end
            return v
        end
        local function GetUrg()
            local g = GetGeneral()
            local v = (g and g.aurasCooldownTextUrgentSeconds) or 5
            if type(v) ~= 'number' then v = 5 end
            if v > 15 then v = 15 end
            return v
        end

        local function SetSafe(v)
            local g = GetGeneral(); if not g then return end
            g.aurasCooldownTextSafeSeconds = v
            if type(g.aurasCooldownTextWarningSeconds) ~= 'number' then g.aurasCooldownTextWarningSeconds = 15 end
            if type(g.aurasCooldownTextUrgentSeconds)  ~= 'number' then g.aurasCooldownTextUrgentSeconds  = 5 end
            if g.aurasCooldownTextWarningSeconds > v then g.aurasCooldownTextWarningSeconds = v end
            if g.aurasCooldownTextUrgentSeconds > g.aurasCooldownTextWarningSeconds then g.aurasCooldownTextUrgentSeconds = g.aurasCooldownTextWarningSeconds end
            if _G.MSUF_A2_InvalidateCooldownTextCurve then _G.MSUF_A2_InvalidateCooldownTextCurve() end
            if _G.MSUF_A2_ForceCooldownTextRecolor then _G.MSUF_A2_ForceCooldownTextRecolor() end
        end

        local function SetWarn(v)
            local g = GetGeneral(); if not g then return end
            if type(g.aurasCooldownTextSafeSeconds) ~= 'number' then g.aurasCooldownTextSafeSeconds = 60 end
            if v > g.aurasCooldownTextSafeSeconds then v = g.aurasCooldownTextSafeSeconds end
            if v > 30 then v = 30 end
            g.aurasCooldownTextWarningSeconds = v
            if type(g.aurasCooldownTextUrgentSeconds) ~= 'number' then g.aurasCooldownTextUrgentSeconds = 5 end
            if g.aurasCooldownTextUrgentSeconds > v then g.aurasCooldownTextUrgentSeconds = v end
            if _G.MSUF_A2_InvalidateCooldownTextCurve then _G.MSUF_A2_InvalidateCooldownTextCurve() end
            if _G.MSUF_A2_ForceCooldownTextRecolor then _G.MSUF_A2_ForceCooldownTextRecolor() end
        end

        local function SetUrg(v)
            local g = GetGeneral(); if not g then return end
            if type(g.aurasCooldownTextWarningSeconds) ~= 'number' then g.aurasCooldownTextWarningSeconds = 15 end
            if v > g.aurasCooldownTextWarningSeconds then v = g.aurasCooldownTextWarningSeconds end
            if v > 15 then v = 15 end
            g.aurasCooldownTextUrgentSeconds = v
            if _G.MSUF_A2_InvalidateCooldownTextCurve then _G.MSUF_A2_InvalidateCooldownTextCurve() end
            if _G.MSUF_A2_ForceCooldownTextRecolor then _G.MSUF_A2_ForceCooldownTextRecolor() end
        end

        local safeSlider = CreateAuras2CompactSlider(timerBox, 'Safe (seconds)', 0, 600, 1, 12, -72, 220, GetSafe, SetSafe)
        MSUF_StyleAuras2CompactSlider(safeSlider, { hideMinMax = true, leftTitle = true })
        AttachSliderValueBox(safeSlider, 0, 600, 1, GetSafe)

        local warnSlider = CreateAuras2CompactSlider(timerBox, 'Warning (<=)', 0, 30, 1, 260, -72, 200, GetWarn, SetWarn)
        MSUF_StyleAuras2CompactSlider(warnSlider, { hideMinMax = true, leftTitle = true })
        AttachSliderValueBox(warnSlider, 0, 30, 1, GetWarn)

        local urgSlider = CreateAuras2CompactSlider(timerBox, 'Urgent (<=)', 0, 15, 1, 486, -72, 200, GetUrg, SetUrg)
        MSUF_StyleAuras2CompactSlider(urgSlider, { hideMinMax = true, leftTitle = true })
        AttachSliderValueBox(urgSlider, 0, 15, 1, GetUrg)

        -- Enable-state: when bucket coloring is OFF, only Safe remains configurable (Step 3).
        local function ApplyTimerEnabledState()
            local g = GetGeneral()
            local enabled = not (g and g.aurasCooldownTextUseBuckets == false)

            local function SetWidgetEnabled(sl, on)
                if not sl then return end
                if on then
                    if sl.Show then sl:Show() end
                    sl:Enable(); sl:SetAlpha(1)
                    if sl.__MSUF_valueBox then
                        sl.__MSUF_valueBox:Show(); sl.__MSUF_valueBox:Enable(); sl.__MSUF_valueBox:SetAlpha(1)
                    end
                else
                    -- Step 3: when bucket coloring is OFF, only Safe remains configurable.
                    -- Hide the extra sliders entirely to keep the section clean.
                    sl:Disable(); sl:SetAlpha(0.35)
                    if sl.Hide then sl:Hide() end
                    if sl.__MSUF_valueBox then
                        sl.__MSUF_valueBox:Disable(); sl.__MSUF_valueBox:SetAlpha(0.35)
                        if sl.__MSUF_valueBox.Hide then sl.__MSUF_valueBox:Hide() end
                    end
                end
            end

            SetWidgetEnabled(warnSlider, enabled)
            SetWidgetEnabled(urgSlider, enabled)
        end

        timerBox._msufApplyTimerColorsEnabledState = ApplyTimerEnabledState
        ApplyTimerEnabledState()

    end

    -- ------------------------------------------------------------
    -- ADVANCED (below): Include / Highlight / Dispel-type filters
    -- ------------------------------------------------------------
    local rTitle = advBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rTitle:SetPoint("TOPLEFT", advBox, "TOPLEFT", 12, -10)
    rTitle:SetText("Advanced")

    local incH = advBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    incH:SetPoint("TOPLEFT", advBox, "TOPLEFT", 12, -34)
    incH:SetText("Include")
    do
        local refs = {}

        BuildBoolPathCheckboxes(advBox, {
            { "Include boss buffs", 12, -58, A2_FilterBuffs, "includeBoss", nil, nil, "cbBossBuffs" },
            { "Include boss debuffs", 12, -86, A2_FilterDebuffs, "includeBoss", nil, nil, "cbBossDebuffs" },

            { "Always include stealable buffs", 12, -114, A2_FilterBuffs, "includeStealable", nil,
                "Additive: this will NOT hide your normal buffs.", "cbStealable" },

            { "Always include dispellable debuffs", 12, -142, A2_FilterDebuffs, "includeDispellable", nil,
                "Additive: this will NOT hide your normal debuffs.", "cbDispellable" },

            { "Only show boss auras", 380, -58, GetEditingFilters, "onlyBossAuras", nil,
                "Hard filter: when enabled (and filters are enabled), only auras flagged as boss auras will be shown.", "cbOnlyBoss" },
        }, refs)

        -- Highlight is stored in Shared settings (visual-only).
        local hlH = advBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        hlH:SetPoint("TOPLEFT", advBox, "TOPLEFT", 12, -170)
        hlH:SetText("Highlight")

        BuildBoolPathCheckboxes(advBox, {
            { "Highlight stealable buffs", 12, -194, A2_Settings, "highlightStealableBuffs", nil,
                "Highlights stealable buffs (visual only; does not filter).", "cbHLSteal" },
            { "Highlight dispellable debuffs", 12, -222, A2_Settings, "highlightDispellableDebuffs", nil,
                "Highlights dispellable debuffs (visual only; does not filter).", "cbHLDispel" },
        }, refs)

        local function Track(keys)
            for i = 1, #keys do
                local cb = refs[keys[i]]
                if cb then advGate[#advGate + 1] = cb end
            end
        end

        Track({ "cbBossBuffs", "cbBossDebuffs", "cbStealable", "cbDispellable", "cbOnlyBoss", "cbHLSteal", "cbHLDispel" })

        local dtH = advBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        dtH:SetPoint("TOPLEFT", advBox, "TOPLEFT", 12, -270)
        dtH:SetText("Debuff types")

        BuildBoolPathCheckboxes(advBox, {
            { "Magic", 12, -294, A2_FilterDebuffs, "dispelMagic", nil, nil, "cbMagic" },
            { "Curse", 140, -294, A2_FilterDebuffs, "dispelCurse", nil, nil, "cbCurse" },
            { "Disease", 268, -294, A2_FilterDebuffs, "dispelDisease", nil, nil, "cbDisease" },
            { "Poison", 396, -294, A2_FilterDebuffs, "dispelPoison", nil, nil, "cbPoison" },
            { "Enrage", 524, -294, A2_FilterDebuffs, "dispelEnrage", nil, nil, "cbEnrage" },
        }, refs)

        Track({ "cbMagic", "cbCurse", "cbDisease", "cbPoison", "cbEnrage" })
    end

    UpdateAdvancedEnabled()

    -- Ensure checkbox state stays consistent after /reload or early panel opens
    local function MSUF_Auras2_RefreshOptionsControls()
        if not content then return end
        -- We cannot rely on individual control OnShow scripts because many widgets are created "shown"
        -- while the parent panel is hidden; they won't get another OnShow when the panel is first opened.
        -- Force-run their OnShow scripts once on panel open so checkboxes/sliders/dropdowns reflect DB instantly.
        local stack = { content }
        while #stack > 0 do
            local f = stack[#stack]
            stack[#stack] = nil
            if f and f.GetScript then
                local fn = f:GetScript("OnShow")
                if type(fn) == "function" then
                    pcall(fn, f)
                end
            end
            if f and f.GetChildren then
                local kids = { f:GetChildren() }
                for i = 1, #kids do
                    stack[#stack + 1] = kids[i]
                end
            end
        end
    end

    local function ForcePanelRefresh()
        -- Ensure DB exists before getters run
        EnsureDB()

        -- Tighten the scroll child to the actual content to avoid empty scroll space.
        pcall(MSUF_Auras2_UpdateContentHeight)

        -- Some Settings/canvas states fail to update legacy scrollframes on the first open.
        -- Force an update so the scroll child rect/layout is computed immediately.
        if scroll and scroll.UpdateScrollChildRect then
            pcall(scroll.UpdateScrollChildRect, scroll)
        end
        if _G.UIPanelScrollFrame_Update and scroll then
            pcall(_G.UIPanelScrollFrame_Update, scroll)
        end

        -- Now sync widgets to DB (checkboxes/sliders/dropdowns)
        MSUF_Auras2_RefreshOptionsControls()
        UpdateAdvancedEnabled()
    end

    -- Settings sometimes calls OnRefresh (old InterfaceOptions style) when a category is selected.
    -- Provide it so the panel refreshes even when OnShow does not re-fire.
    panel.OnRefresh = function()
        if cbMasque and RefreshMasqueToggleState then RefreshMasqueToggleState() end
        -- Defer to next tick so Settings has time to size/layout the canvas.
        C_Timer.After(0, function()
            if panel and panel:IsShown() then
                ForcePanelRefresh()
                -- One more short defer catches the first-open layout pass edge-case.
                C_Timer.After(0.05, function()
                    if panel and panel:IsShown() then
                        ForcePanelRefresh()
                    end
                end)
            end
        end)
    end
    panel.refresh = panel.OnRefresh

    -- Critical: Fix the "must click twice" issue by reacting to the first real size/layout pass.
    -- When the category is first selected, the panel may be shown with a 0x0 (or tiny) size,
    -- so the legacy UIPanelScrollFrame doesn't render. As soon as Settings assigns the final
    -- size, OnSizeChanged fires and we can force-refresh the scrollframe + widgets.
    if not panel.__msufAuras2_SizeHooked then
        panel.__msufAuras2_SizeHooked = true
        panel:HookScript("OnSizeChanged", function(self, w, h)
            if not (self and self.IsShown and self:IsShown()) then return end
            w = tonumber(w) or 0
            h = tonumber(h) or 0
            if w < 200 or h < 200 then return end

            local lw = tonumber(self.__msufAuras2_LastSizedW) or 0
            local lh = tonumber(self.__msufAuras2_LastSizedH) or 0
            if lw == w and lh == h then return end
            self.__msufAuras2_LastSizedW = w
            self.__msufAuras2_LastSizedH = h

            C_Timer.After(0, function()
                if self and self.IsShown and self:IsShown() then
                    ForcePanelRefresh()
                end
            end)
        end)
    end

    panel:HookScript("OnShow", function()
        if panel.OnRefresh then
            panel.OnRefresh()
        else
            ForcePanelRefresh()
        end
    end)

    local rInfo = advBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    rInfo:SetPoint("TOPLEFT", advBox, "TOPLEFT", 12, -330)
    rInfo:SetWidth(690)
    rInfo:SetJustifyH("LEFT")
    rInfo:SetText(TIP_ADV_INFO)
    -- Register in Settings / Interface Options.
    -- NOTE: Slash-menu-only mode must NOT register any Blizzard settings / interface options categories.
    if not (_G and _G.MSUF_SLASHMENU_ONLY) then
        if parentCategory and Settings and Settings.RegisterCanvasLayoutSubcategory then
            local sub = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
            if sub then
                ns.MSUF_AurasCategory = sub
                _G.MSUF_AurasCategory = sub
            end
        end
    end

    return ns.MSUF_AurasCategory
end

function ns.MSUF_RegisterAurasOptions(parentCategory)
    if _G and _G.MSUF_SLASHMENU_ONLY then
        -- Slash-menu-only: build the panel for mirroring, but do NOT register it in Blizzard Settings.
        if type(ns.MSUF_RegisterAurasOptions_Full) == "function" then
            return ns.MSUF_RegisterAurasOptions_Full(nil)
        end
        return
    end
    -- Lazy wrapper (mirrors Colors/GamePlay pattern)
    if ns.__MSUF_AurasBuilt then
        return ns.MSUF_AurasCategory
    end
    ns.__MSUF_AurasBuilt = true
    return ns.MSUF_RegisterAurasOptions_Full(parentCategory)
end
