-- MSUF_A2_Render.lua
-- Auras 2.0 runtime core (moved from MidnightSimpleUnitFrames_Auras.lua)
-- NOTE: Phase-0 split: logic moved verbatim to enable incremental modularization without regressions.

local addonName, ns = ...
ns = ns or {}
if ns.__MSUF_A2_CORE_LOADED then return end
ns.__MSUF_A2_CORE_LOADED = true

-- Auras 2.0 public API
--  * Options/UI talks to runtime ONLY via ns.MSUF_Auras2
--  * Globals are kept as thin wrappers for backwards compatibility (MSUF_* prefixed only)
local API = ns.MSUF_Auras2
if type(API) ~= "table" then
    API = {}
    ns.MSUF_Auras2 = API
end
API.state = (type(API.state) == "table") and API.state or {}
API.perf  = (type(API.perf)  == "table") and API.perf  or {}


local MSUF_DB

local MSUF_A2_DB_READY = false
local MSUF_A2_DB_LAST = nil

local function MSUF_A2_InvalidateDB()
    MSUF_A2_DB_READY = false
    MSUF_A2_DB_LAST = nil

    -- Options often call InvalidateDB() after toggles. Ensure Edit Mode preview icons never linger.
    if API and API.ClearAllPreviews then
        API.ClearAllPreviews()
    end

    if API and API.DB and API.DB.InvalidateCache then
        API.DB.InvalidateCache()
    end
    if API and API.Colors and API.Colors.InvalidateCache then
        API.Colors.InvalidateCache()
    end
end


API.InvalidateDB = MSUF_A2_InvalidateDB
if _G and type(_G.MSUF_A2_InvalidateDB) ~= "function" then
    _G.MSUF_A2_InvalidateDB = function() return API.InvalidateDB() end
end



-- ------------------------------------------------------------
-- (Phase 5) Fast local bindings for highlight/border/stack colors
-- (implemented in Auras2/MSUF_A2_Colors.lua; keep fallbacks to avoid hard regressions)
-- ------------------------------------------------------------
local MSUF_A2_GetOwnBuffHighlightRGB = _G and _G.MSUF_A2_GetOwnBuffHighlightRGB or nil
local MSUF_A2_GetOwnDebuffHighlightRGB = _G and _G.MSUF_A2_GetOwnDebuffHighlightRGB or nil
local MSUF_A2_GetStackCountRGB = _G and _G.MSUF_A2_GetStackCountRGB or nil
local MSUF_A2_GetDispelBorderRGB = _G and _G.MSUF_A2_GetDispelBorderRGB or nil
local MSUF_A2_GetPrivatePlayerHighlightRGB = _G and _G.MSUF_A2_GetPrivatePlayerHighlightRGB or nil

if type(MSUF_A2_GetOwnBuffHighlightRGB) ~= "function" then
    MSUF_A2_GetOwnBuffHighlightRGB = function() return 1.0, 0.85, 0.2 end
end
if type(MSUF_A2_GetOwnDebuffHighlightRGB) ~= "function" then
    MSUF_A2_GetOwnDebuffHighlightRGB = function() return 1.0, 0.3, 0.3 end
end
if type(MSUF_A2_GetStackCountRGB) ~= "function" then
    MSUF_A2_GetStackCountRGB = function() return 1.0, 1.0, 1.0 end
end
if type(MSUF_A2_GetDispelBorderRGB) ~= "function" then
    MSUF_A2_GetDispelBorderRGB = function() return 0.2, 0.6, 1.0 end
end
if type(MSUF_A2_GetPrivatePlayerHighlightRGB) ~= "function" then
    MSUF_A2_GetPrivatePlayerHighlightRGB = function() return 0.75, 0.2, 1.0 end
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

-- Patch 1 helpers (Auras2): per-unit layout + numeric resolve
local function MSUF_A2_GetPerUnit(unitKey)
    local pu = MSUF_DB and MSUF_DB.auras2 and MSUF_DB.auras2.perUnit
    return (pu and unitKey) and pu[unitKey] or nil
end

local function MSUF_A2_GetPerUnitLayout(unitKey)
    local u = MSUF_A2_GetPerUnit(unitKey)
    return (u and u.overrideLayout == true and type(u.layout) == "table") and u.layout or nil
end

local function MSUF_A2_GetPerUnitSharedLayout(unitKey)
    local u = MSUF_A2_GetPerUnit(unitKey)
    return (u and u.overrideSharedLayout == true and type(u.layoutShared) == "table") and u.layoutShared or nil
end

local function MSUF_A2_ResolveNumber(unitKey, shared, key, def, minV, maxV, roundInt)
    local v = (shared and key) and shared[key] or nil
    local ul = MSUF_A2_GetPerUnitLayout(unitKey)
    if ul and ul[key] ~= nil then v = ul[key] end
    v = tonumber(v); if v == nil then v = def end
    if minV ~= nil and v < minV then v = minV end
    if maxV ~= nil and v > maxV then v = maxV end
    if roundInt then v = math.floor(v + 0.5) end
    return v
end

-- Patch 4 helpers (Auras2): spec-driven defaults + filter normalization (defined once; no per-call closures)
local function A2_EnsureTable(parent, key)
    local t = parent[key]
    if type(t) ~= "table" then t = {}; parent[key] = t end
    return t
end

local function A2_Default(t, key, val) if t[key] == nil then t[key] = val end end

local function A2_ApplyDefaultsKV(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then t[k] = v end
    end
end

local function A2_ClampNumber(v, def, minV, maxV, roundInt)
    if type(v) ~= "number" then v = tonumber(v) end
    if v == nil then v = def end
    if minV ~= nil and v < minV then v = minV end
    if maxV ~= nil and v > maxV then v = maxV end
    if roundInt then v = math.floor(v + 0.5) end
    return v
end

local function A2_Enum(t, key, def, okSet)
    local v = t[key]
    if v == nil or (okSet and not okSet[v]) then t[key] = def; return def end
    return v
end

local function A2_OptionalNumber(t, key)
    local v = t[key]
    if v ~= nil and type(v) ~= "number" then v = tonumber(v); t[key] = v end
    if t[key] ~= nil and type(t[key]) ~= "number" then t[key] = nil end
    return t[key]
end

local A2_GROWTH_OK = {RIGHT=true,LEFT=true,UP=true,DOWN=true}
local A2_ROWWRAP_OK = {DOWN=true,UP=true}
local A2_LAYOUTMODE_OK = {SEPARATE=true,SINGLE=true}
local A2_STACKANCHOR_OK = {TOPRIGHT=true,TOPLEFT=true,BOTTOMRIGHT=true,BOTTOMLEFT=true}
local A2_SPLITANCHOR_OK = {
    STACKED=true,
    TOP_BOTTOM_BUFFS=true,TOP_BOTTOM_DEBUFFS=true,
    TOP_RIGHT_BUFFS=true,TOP_RIGHT_DEBUFFS=true,
    BOTTOM_RIGHT_BUFFS=true,BOTTOM_RIGHT_DEBUFFS=true,
    BOTTOM_LEFT_BUFFS=true,BOTTOM_LEFT_DEBUFFS=true,
    TOP_LEFT_BUFFS=true,TOP_LEFT_DEBUFFS=true,
}

local A2_AURAS2_DEFAULTS = { enabled=true, showTarget=true, showFocus=true, showBoss=true, showPlayer=false }

-- Shared defaults: values only. Fields that need migration or nil default are handled explicitly in EnsureDB.
local A2_SHARED_DEFAULTS = {
    showBuffs=true, showDebuffs=true, showTooltip=true,
    showCooldownSwipe=true, showCooldownText=true, cooldownSwipeDarkenOnLoss=false,
    showInEditMode=true, showStackCount=true,
    stackCountAnchor="TOPRIGHT", masqueEnabled=false,
    layoutMode="SEPARATE", buffDebuffAnchor="STACKED", splitSpacing=0,
    highlightPrivatePlayerAuras=false, highlightOwnBuffs=false, highlightOwnDebuffs=false,
    iconSize=26, spacing=2, perRow=12, maxIcons=12,
    growth="RIGHT", rowWrap="DOWN",
    offsetX=0, offsetY=6, buffOffsetY=30,
    stackTextSize=14, cooldownTextSize=14, bossEditTogether=true,
    showPrivateAurasPlayer=true, showPrivateAurasFocus=true, showPrivateAurasBoss=true,
    privateAuraMaxPlayer=6, privateAuraMaxOther=6,
}

local function A2_NormalizeCooldownBuckets(g)
    A2_Default(g, "aurasCooldownTextUseBuckets", true)
    g.aurasCooldownTextSafeSeconds = A2_ClampNumber(g.aurasCooldownTextSafeSeconds, 60, 0, nil)
    g.aurasCooldownTextWarningSeconds = A2_ClampNumber(g.aurasCooldownTextWarningSeconds, 15, 0, 30)
    g.aurasCooldownTextUrgentSeconds  = A2_ClampNumber(g.aurasCooldownTextUrgentSeconds,  5, 0, 15)
    local safe = g.aurasCooldownTextSafeSeconds
    local warn = g.aurasCooldownTextWarningSeconds; if warn > safe then warn = safe end
    local urg  = g.aurasCooldownTextUrgentSeconds;  if urg  > warn then urg  = warn end
    g.aurasCooldownTextWarningSeconds = warn
    g.aurasCooldownTextUrgentSeconds  = urg
end

local A2_DISPEL_KEYS = { "dispelMagic", "dispelCurse", "dispelDisease", "dispelPoison", "dispelEnrage" }

local function MSUF_A2_NormalizeFilters(f, sharedSettings, migrateFlagKey)
    if type(f) ~= "table" then return end
    A2_Default(f, "enabled", true)
    f.buffs = (type(f.buffs) == "table") and f.buffs or {}
    f.debuffs = (type(f.debuffs) == "table") and f.debuffs or {}
    local b, d = f.buffs, f.debuffs

    if migrateFlagKey and not f[migrateFlagKey] and type(sharedSettings) == "table" then
        if f.hidePermanent == nil then f.hidePermanent = (sharedSettings.hidePermanent == true) end
        if b.onlyMine == nil then b.onlyMine = (sharedSettings.onlyMyBuffs == true) end
        if d.onlyMine == nil then d.onlyMine = (sharedSettings.onlyMyDebuffs == true) end
        f[migrateFlagKey] = true
    end

    A2_Default(f, "hidePermanent", false)

    A2_Default(b, "onlyMine", false); A2_Default(b, "includeBoss", false)

    A2_Default(d, "onlyMine", false); A2_Default(d, "includeBoss", false); A2_Default(d, "includeDispellable", false)
    if d.dispellableOnly == true then d.includeDispellable = true; d.dispellableOnly = false end

    A2_Default(f, "onlyBossAuras", false)

    for i = 1, #A2_DISPEL_KEYS do
        local k = A2_DISPEL_KEYS[i]
        if d[k] == nil then d[k] = false end
    end
end

local function MSUF_A2_EnsurePerUnitConfig(pu, unitKey, sharedSettings)
    if type(pu[unitKey]) ~= "table" then pu[unitKey] = {} end
    local u = pu[unitKey]

    A2_Default(u, "overrideFilters", false)
    A2_Default(u, "overrideLayout", false)
    A2_Default(u, "overrideSharedLayout", false)

    if type(u.layout) ~= "table" then u.layout = {} end
    local lay = u.layout
    if type(lay.offsetX) ~= "number" then lay.offsetX = 0 end
    if type(lay.offsetY) ~= "number" then lay.offsetY = 0 end
    if lay.width ~= nil and type(lay.width) ~= "number" then lay.width = nil end
    if lay.height ~= nil and type(lay.height) ~= "number" then lay.height = nil end
    -- Optional: independent Buff/Debuff offsets + icon size (used by Edit Mode tabs).
    A2_OptionalNumber(lay, "buffGroupOffsetX");   if lay.buffGroupOffsetX ~= nil then lay.buffGroupOffsetX = A2_ClampNumber(lay.buffGroupOffsetX, 0, -2000, 2000, true) end
    A2_OptionalNumber(lay, "buffGroupOffsetY");   if lay.buffGroupOffsetY ~= nil then lay.buffGroupOffsetY = A2_ClampNumber(lay.buffGroupOffsetY, 0, -2000, 2000, true) end
    A2_OptionalNumber(lay, "debuffGroupOffsetX"); if lay.debuffGroupOffsetX ~= nil then lay.debuffGroupOffsetX = A2_ClampNumber(lay.debuffGroupOffsetX, 0, -2000, 2000, true) end
    A2_OptionalNumber(lay, "debuffGroupOffsetY"); if lay.debuffGroupOffsetY ~= nil then lay.debuffGroupOffsetY = A2_ClampNumber(lay.debuffGroupOffsetY, 0, -2000, 2000, true) end
    A2_OptionalNumber(lay, "buffGroupIconSize");  if lay.buffGroupIconSize ~= nil then lay.buffGroupIconSize = A2_ClampNumber(lay.buffGroupIconSize, 0, 10, 80, true) end
    A2_OptionalNumber(lay, "debuffGroupIconSize");if lay.debuffGroupIconSize ~= nil then lay.debuffGroupIconSize = A2_ClampNumber(lay.debuffGroupIconSize, 0, 10, 80, true) end

    if type(u.layoutShared) ~= "table" then u.layoutShared = {} end
    local ls = u.layoutShared
    A2_OptionalNumber(ls, "maxBuffs"); A2_OptionalNumber(ls, "maxDebuffs"); A2_OptionalNumber(ls, "perRow")
    if A2_OptionalNumber(ls, "splitSpacing") ~= nil then ls.splitSpacing = A2_ClampNumber(ls.splitSpacing, 0, 0, 80, true) end
    if ls.growth ~= nil and not A2_GROWTH_OK[ls.growth] then ls.growth = nil end
    if ls.rowWrap ~= nil and not A2_ROWWRAP_OK[ls.rowWrap] then ls.rowWrap = nil end
    if ls.layoutMode ~= nil and not A2_LAYOUTMODE_OK[ls.layoutMode] then ls.layoutMode = nil end
    if ls.buffDebuffAnchor ~= nil and not A2_SPLITANCHOR_OK[ls.buffDebuffAnchor] then ls.buffDebuffAnchor = nil end
    if ls.stackCountAnchor ~= nil and not A2_STACKANCHOR_OK[ls.stackCountAnchor] then ls.stackCountAnchor = nil end

    -- Player: production-ready defaults (Stage D). Only applies once and only if user hasn't configured Player.
    if unitKey == "player" and u._msufA2_playerDefaults_stageD_v1 == nil then
        u._msufA2_playerDefaults_stageD_v1 = true

        if u.overrideSharedLayout == false then
            local hasAny =
                (ls.maxBuffs ~= nil) or (ls.maxDebuffs ~= nil) or (ls.perRow ~= nil) or (ls.splitSpacing ~= nil)
                or (ls.growth ~= nil) or (ls.rowWrap ~= nil) or (ls.layoutMode ~= nil) or (ls.buffDebuffAnchor ~= nil)
                or (ls.stackCountAnchor ~= nil)
            if not hasAny then u.overrideSharedLayout = true end
        end

        if ls.perRow == nil then ls.perRow = 10 end
        if ls.maxBuffs == nil then ls.maxBuffs = 12 end
        if ls.maxDebuffs == nil then ls.maxDebuffs = 8 end
        if ls.splitSpacing == nil then ls.splitSpacing = 0 end
        if ls.growth == nil then ls.growth = "RIGHT" end
        if ls.rowWrap == nil then ls.rowWrap = "UP" end
        if ls.layoutMode == nil then ls.layoutMode = "SEPARATE" end
        if ls.buffDebuffAnchor == nil then ls.buffDebuffAnchor = "STACKED" end
        if ls.stackCountAnchor == nil then ls.stackCountAnchor = "BOTTOMRIGHT" end

        if u.overrideLayout == false then
            local hasPos = (lay.width ~= nil) or (lay.height ~= nil) or (lay.offsetX ~= 0) or (lay.offsetY ~= 0)
            if not hasPos then u.overrideLayout = true; lay.offsetX = 0; lay.offsetY = 8 end
        end
    end

    if type(u.filters) ~= "table" then u.filters = {} end
    MSUF_A2_NormalizeFilters(u.filters, sharedSettings, "_msufA2_filtersMigrated_v2")
    return u.filters
end

local function EnsureDB()
    -- Fast-path: if we already ensured this SavedVariables table this session, return pointers.
    local gdb = _G and _G.MSUF_DB or nil
    if MSUF_A2_DB_READY and gdb == MSUF_A2_DB_LAST and type(gdb) == "table" then
        local a2fast = gdb.auras2
        local sfast = (type(a2fast) == "table") and a2fast.shared or nil
        if type(a2fast) == "table" and type(sfast) == "table" then
            MSUF_DB = gdb
            return a2fast, sfast
        end
    end

    if type(_G.MSUF_DB) ~= "table" then _G.MSUF_DB = {} end
    if type(_G.EnsureDB) == "function" then pcall(_G.EnsureDB) end

    MSUF_DB = _G.MSUF_DB
    if type(MSUF_DB) ~= "table" then return nil end

    local g = A2_EnsureTable(MSUF_DB, "general")
    A2_NormalizeCooldownBuckets(g)

    local a2 = A2_EnsureTable(MSUF_DB, "auras2")
    A2_ApplyDefaultsKV(a2, A2_AURAS2_DEFAULTS)

    local s = A2_EnsureTable(a2, "shared")
    A2_ApplyDefaultsKV(s, A2_SHARED_DEFAULTS)

    -- Legacy: fill maxBuffs/maxDebuffs from maxIcons when unset.
    if s.maxBuffs == nil then s.maxBuffs = s.maxIcons or 12 end
    if s.maxDebuffs == nil then s.maxDebuffs = s.maxIcons or 12 end

    -- Migration: older builds used highlightPrivatePlayerAuras.
    if s.highlightPrivateAuras == nil then s.highlightPrivateAuras = (s.highlightPrivatePlayerAuras == true) end

    -- Target private auras removed (force off regardless of old DB)
    s.showPrivateAurasTarget = false

    -- Clamp + validate (match existing slider caps)
    s.splitSpacing = A2_ClampNumber(s.splitSpacing, 0, 0, 80, true)
    s.privateAuraMaxPlayer = A2_ClampNumber(s.privateAuraMaxPlayer, 6, 0, 12, true)
    s.privateAuraMaxOther  = A2_ClampNumber(s.privateAuraMaxOther,  6, 0, 12, true)

    A2_Enum(s, "growth", "RIGHT", A2_GROWTH_OK)
    A2_Enum(s, "rowWrap", "DOWN", A2_ROWWRAP_OK)
    A2_Enum(s, "layoutMode", "SEPARATE", A2_LAYOUTMODE_OK)
    A2_Enum(s, "buffDebuffAnchor", "STACKED", A2_SPLITANCHOR_OK)
    A2_Enum(s, "stackCountAnchor", "TOPRIGHT", A2_STACKANCHOR_OK)

    A2_Default(s, "_msufA2_migrated_v11f", true)

    -- Shared filter config: migrate older storage from perUnit.target.filters if needed.
    if type(s.filters) ~= "table" then
        local migrated = (type(a2.perUnit) == "table" and type(a2.perUnit.target) == "table") and a2.perUnit.target.filters or nil
        s.filters = (type(migrated) == "table") and migrated or {}
        if migrated then s.filters._msufA2_sharedFiltersMigratedFromTarget = true end
    end

    a2.perUnit = (type(a2.perUnit) == "table") and a2.perUnit or {}
    local pu = a2.perUnit

    local sf = s.filters
    if type(sf) ~= "table" then sf = {}; s.filters = sf end
    MSUF_A2_NormalizeFilters(sf, s, "_msufA2_sharedFiltersMigrated_v1")

    -- Compatibility: some Options builds still toggle shared.hidePermanent directly.
    -- Mirror that value into shared.filters.hidePermanent so the runtime filter respects the UI.
    if s.hidePermanent ~= nil and sf.hidePermanent ~= s.hidePermanent then
        sf.hidePermanent = (s.hidePermanent == true)
    end

    -- Keep legacy shared flags synced (derived from shared.filters)
    s.onlyMyBuffs = (sf.buffs and sf.buffs.onlyMine == true) or false
    s.onlyMyDebuffs = (sf.debuffs and sf.debuffs.onlyMine == true) or false
    s.hidePermanent = (sf.hidePermanent == true)

    MSUF_A2_EnsurePerUnitConfig(pu, "player", s)
    MSUF_A2_EnsurePerUnitConfig(pu, "target", s)
    MSUF_A2_EnsurePerUnitConfig(pu, "focus", s)
    for i = 1, 5 do MSUF_A2_EnsurePerUnitConfig(pu, "boss" .. i, s) end

    MSUF_A2_DB_LAST = MSUF_DB
    MSUF_A2_DB_READY = true
    if API and API.DB and API.DB.RebuildCache then
        API.DB.RebuildCache(a2, s)
    end
    return a2, s
end

-- Phase 1: bind EnsureDB into the DB module so Events can prime/cache without calling into render locals.
if API and API.DB and API.DB.BindEnsure then
    API.DB.BindEnsure(EnsureDB)
end


-- (Phase 5) Auras2 highlight/border/stack colors moved to Auras2/MSUF_A2_Colors.lua

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


local MSUF_A2_GetCooldownFontString


local function MSUF_A2_GetEffectiveCooldownTextOffsets(unitKey, shared)
    local offX, offY = nil, nil
    local enabled = false

    -- shared defaults (optional)
    if shared then
        if shared.cooldownTextOffsetX ~= nil then offX = shared.cooldownTextOffsetX; enabled = true end
        if shared.cooldownTextOffsetY ~= nil then offY = shared.cooldownTextOffsetY; enabled = true end
    end

    -- per-unit override (optional)
    if MSUF_DB and MSUF_DB.auras2 and MSUF_DB.auras2.perUnit and unitKey then
        local u = MSUF_DB.auras2.perUnit[unitKey]
        if u and u.overrideLayout == true and type(u.layout) == "table" then
            if u.layout.cooldownTextOffsetX ~= nil then offX = u.layout.cooldownTextOffsetX; enabled = true end
            if u.layout.cooldownTextOffsetY ~= nil then offY = u.layout.cooldownTextOffsetY; enabled = true end
        end
    end

    -- 0-regression: if user never set any offsets, don't touch anchors.
    if not enabled then
        return 0, 0, false
    end

    offX = tonumber(offX) or 0
    offY = tonumber(offY) or 0
    offX = math.max(-2000, math.min(2000, offX))
    offY = math.max(-2000, math.min(2000, offY))
    return offX, offY, true
end

local function MSUF_A2_ApplyCooldownTextOffsets(icon, unitKey, shared)
    local fs = MSUF_A2_GetCooldownFontString and MSUF_A2_GetCooldownFontString(icon) or nil
    if not fs then return end

    local offX, offY, enabled = MSUF_A2_GetEffectiveCooldownTextOffsets(unitKey, shared)
    if not enabled then
        return
    end

    -- Only re-anchor when the requested offsets actually change.
    if fs._msufA2_cdOffApplied ~= true or fs._msufA2_cdOffX ~= offX or fs._msufA2_cdOffY ~= offY then
        fs._msufA2_cdOffApplied = true
        fs._msufA2_cdOffX = offX
        fs._msufA2_cdOffY = offY

        if fs.ClearAllPoints then fs:ClearAllPoints() end
        if fs.SetPoint then fs:SetPoint("CENTER", icon, "CENTER", offX, offY) end
    end
end




local function MSUF_A2_GetEffectiveStackTextOffsets(unitKey, shared)
    local offX, offY = nil, nil
    local enabled = false

    if shared then
        if shared.stackTextOffsetX ~= nil then offX = shared.stackTextOffsetX; enabled = true end
        if shared.stackTextOffsetY ~= nil then offY = shared.stackTextOffsetY; enabled = true end
    end

    if MSUF_DB and MSUF_DB.auras2 and MSUF_DB.auras2.perUnit and unitKey then
        local u = MSUF_DB.auras2.perUnit[unitKey]
        if u and u.overrideLayout == true and type(u.layout) == "table" then
            if u.layout.stackTextOffsetX ~= nil then offX = u.layout.stackTextOffsetX; enabled = true end
            if u.layout.stackTextOffsetY ~= nil then offY = u.layout.stackTextOffsetY; enabled = true end
        end
    end

    -- 0-regression: if user never set any offsets, don't touch anchors.
    if not enabled then
        return 0, 0, false
    end

    offX = tonumber(offX) or 0
    offY = tonumber(offY) or 0
    offX = math.max(-2000, math.min(2000, offX))
    offY = math.max(-2000, math.min(2000, offY))
    return offX, offY, true
end

local function MSUF_A2_ApplyStackTextOffsets(icon, unitKey, shared, stackAnchorOverride)
    if not icon or not icon.count then return end

    local offX, offY, enabled = MSUF_A2_GetEffectiveStackTextOffsets(unitKey, shared)
    if not enabled then
        return
    end

    local stackAnchor = stackAnchorOverride or (shared and shared.stackCountAnchor) or "TOPRIGHT"

    local point, relPoint, xBase, yBase, justify
    if stackAnchor == "TOPLEFT" then
        point, relPoint, xBase, yBase, justify = "TOPLEFT", "TOPLEFT", -4, 7, "LEFT"
    elseif stackAnchor == "BOTTOMLEFT" then
        point, relPoint, xBase, yBase, justify = "BOTTOMLEFT", "BOTTOMLEFT", -4, -7, "LEFT"
    elseif stackAnchor == "BOTTOMRIGHT" then
        point, relPoint, xBase, yBase, justify = "BOTTOMRIGHT", "BOTTOMRIGHT", 4, -7, "RIGHT"
    else
        point, relPoint, xBase, yBase, justify = "TOPRIGHT", "TOPRIGHT", 4, 7, "RIGHT"
    end

    local fs = icon.count
    if fs._msufA2_stackOffApplied ~= true
        or fs._msufA2_stackOffX ~= offX
        or fs._msufA2_stackOffY ~= offY
        or fs._msufA2_stackOffAnchor ~= stackAnchor
    then
        fs._msufA2_stackOffApplied = true
        fs._msufA2_stackOffX = offX
        fs._msufA2_stackOffY = offY
        fs._msufA2_stackOffAnchor = stackAnchor

        fs:ClearAllPoints()
        fs:SetPoint(point, icon, relPoint, xBase + offX, yBase + offY)
        if fs.SetJustifyH and justify then fs:SetJustifyH(justify) end
    end
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

-- ------------------------------------------------------------
-- Cooldown text (fontstring scan + coloring + optional text) is handled by:
--   Auras2/MSUF_A2_CooldownText.lua
-- We only localize the public entry points here to keep existing call sites.
-- ------------------------------------------------------------

MSUF_A2_GetCooldownFontString = (_G and _G.MSUF_A2_GetCooldownFontString) or ((API and API.CooldownText) and API.CooldownText.GetCooldownFontString)

local function MSUF_A2_CooldownTextMgr_RegisterIcon(icon)
    local CT = API and API.CooldownText
    local f = CT and CT.RegisterIcon
    if f then
        return f(icon)
    end
end

local function MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
    local CT = API and API.CooldownText
    local f = CT and CT.UnregisterIcon
    if f then
        return f(icon)
    end
end

-- (Phase 5) Dispel border colors moved to Auras2/MSUF_A2_Colors.lua

local function GetAuras2DB()
    local DB = API and API.DB
    if DB and DB.GetCached then
        local a2, shared = DB.GetCached()
        if a2 and shared then
            return a2, shared
        end
    end

    local a2, shared = EnsureDB()
    if DB and DB.RebuildCache then
        DB.RebuildCache(a2, shared)
    end
    return a2, shared
end


local AurasByUnit

-- ------------------------------------------------------------
-- Masque (optional)
-- ------------------------------------------------------------
local Masque = API.Masque
local Masque_IsEnabled = Masque and Masque.IsEnabled
local Masque_AddButton = Masque and Masque.AddButton
local Masque_RemoveButton = Masque and Masque.RemoveButton
local Masque_RequestReskin = Masque and Masque.RequestReskin
local Masque_SyncIconOverlayLevels = Masque and Masque.SyncIconOverlayLevels
local Masque_SkinHasBorder = Masque and Masque.SkinHasBorder
local Masque_PrepareButton = Masque and Masque.PrepareButton

-- ------------------------------------------------------------
-- Icon factory
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- Icon borders / highlights (Masque-safe)
-- ------------------------------------------------------------
-- Overlay level syncing and border-detection are handled by MSUF_A2_Masque.lua


local function CreateBorder(frame)
    local border = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    border:SetAllPoints()
    border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    border:SetBackdropBorderColor(0, 0, 0, 1)
    frame._msufBorder = border

    -- Keep our overlay levels consistent from creation onward.
    if Masque_SyncIconOverlayLevels then Masque_SyncIconOverlayLevels(frame) end
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

-- Cached preview definitions (no per-render table allocations)
local MSUF_A2_PREVIEW_BUFF_DEFS = {
    -- Recognizable buffs (variety helps spacing/rows). Some show timers, some are permanent.
    { tex = "Interface\\Icons\\Spell_Holy_WordFortitude",        spellId = 21562, isHelpful = true,  previewKind = "Buff preview",  cdDur = 300, cdElapsed = 245 },
    { tex = "Interface\\Icons\\Spell_Holy_ArcaneIntellect",      spellId = 1459,  isHelpful = true,  previewKind = "Buff preview",  cdDur = 120, cdElapsed = 50  },
    { tex = "Interface\\Icons\\Spell_Nature_Rejuvenation",       spellId = 774,   isHelpful = true,  previewKind = "Buff preview",  cdDur = 18,  cdElapsed = 6   },
    { tex = "Interface\\Icons\\Spell_Holy_MagicalSentry",        spellId = 0,     isHelpful = true,  previewKind = "Buff preview",  permanent = true            },
    { tex = "Interface\\Icons\\Ability_Mage_TimeWarp",           spellId = 80353, isHelpful = true,  previewKind = "Buff preview",  cdDur = 40,  cdElapsed = 12  },
    { tex = "Interface\\Icons\\Spell_Nature_LightningShield",    spellId = 324,   isHelpful = true,  previewKind = "Buff preview",  cdDur = 90,  cdElapsed = 30  },
}



local MSUF_A2_PREVIEW_DEBUFF_DEFS = {
    -- Recognizable debuffs (variety helps spacing/rows). Some show timers, some are permanent.
    { tex = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",       spellId = 589,   isHelpful = false, previewKind = "Debuff preview", cdDur = 20,  cdElapsed = 7   },
    { tex = "Interface\\Icons\\Spell_Shadow_AbominationExplosion", spellId = 172,   isHelpful = false, previewKind = "Debuff preview", cdDur = 14,  cdElapsed = 2   },
    { tex = "Interface\\Icons\\Ability_Rogue_Rupture",             spellId = 1943,  isHelpful = false, previewKind = "Debuff preview", cdDur = 24,  cdElapsed = 11  },
    { tex = "Interface\\Icons\\Spell_Shadow_CurseOfTounges",       spellId = 1714,  isHelpful = false, previewKind = "Debuff preview", cdDur = 30,  cdElapsed = 18  },
    { tex = "Interface\\Icons\\Spell_Nature_Slow",                 spellId = 0,     isHelpful = false, previewKind = "Debuff preview", permanent = true            },
    { tex = "Interface\\Icons\\Spell_Shadow_VampiricAura",         spellId = 34914, isHelpful = false, previewKind = "Debuff preview", cdDur = 60,  cdElapsed = 35  },
}

-- Private Aura preview icons (Edit Mode only; does not affect Blizzard private aura anchors)
local MSUF_A2_PREVIEW_PRIVATE_DEFS = {
    -- Private aura preview icons (Edit Mode only; does not affect Blizzard private aura anchors)
    { tex = "Interface\\Icons\\Ability_Creature_Cursed_03",     spellId = 0,     isHelpful = true,  previewKind = "Private preview", isPrivate = true, cdDur = 12,  cdElapsed = 3  },
    { tex = "Interface\\Icons\\Spell_Shadow_AntiMagicShell",    spellId = 48707, isHelpful = true,  previewKind = "Private preview", isPrivate = true, cdDur = 25,  cdElapsed = 10 },
    { tex = "Interface\\Icons\\Spell_Arcane_Arcane01",          spellId = 0,     isHelpful = true,  previewKind = "Private preview", isPrivate = true, permanent = true           },
    { tex = "Interface\\Icons\\Spell_Fire_Fireball02",          spellId = 133,   isHelpful = true,  previewKind = "Private preview", isPrivate = true, cdDur = 45,  cdElapsed = 20 },
    { tex = "Interface\\Icons\\INV_Misc_QuestionMark",          spellId = 0,     isHelpful = true,  previewKind = "Private preview", isPrivate = true, cdDur = 90,  cdElapsed = 60 },
}



local function MSUF_A2_PreviewUnitLabel(unit)
    if unit == "player" then return "Player" end
    if unit == "target" then return "Target" end
    if unit == "focus" then return "Focus" end
    if type(unit) == "string" then
        local n = unit:match("^boss(%d+)$")
        if n then return "Boss " .. n end
    end
    return tostring(unit or "Unit")
end

local function AcquireIcon(container, index)
    container._msufIcons = container._msufIcons or {}
    local icon = container._msufIcons[index]
    if icon then
        -- Sync Masque state for pooled/reused buttons (no per-icon DB fetch)
        local st = API and API.state
        local stamp = st and st._msufA2_masqueStamp or 0
        if icon._msufA2_masqueStamp ~= stamp then
            local wantMasque = st and st._msufA2_masqueWant
            if wantMasque and Masque_AddButton then
                local shared = st and st._msufA2_masqueShared
                if shared then Masque_AddButton(icon, shared) end
            elseif (not wantMasque) and Masque_RemoveButton then
                Masque_RemoveButton(icon)
            end
            icon._msufA2_masqueStamp = stamp
        end
        -- Preview label safety: never let preview text stick on reused icons.
        if icon._msufA2_previewLabel then
            icon._msufA2_previewLabel:Hide()
        end
        icon._msufA2_previewLabelText = nil

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
    if Masque_PrepareButton then Masque_PrepareButton(icon) end

    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.Cooldown = icon.cooldown
    if icon.cooldown.SetDrawEdge then icon.cooldown:SetDrawEdge(false) end
    if icon.cooldown.SetDrawSwipe then icon.cooldown:SetDrawSwipe(true) end
    if icon.cooldown.SetDrawBling then icon.cooldown:SetDrawBling(false) end
    if icon.cooldown.SetHideCountdownNumbers then icon.cooldown:SetHideCountdownNumbers(false) end
    if icon.cooldown.SetHideCountdownNumbers then icon.cooldown:SetHideCountdownNumbers(false) end

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
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, aid)
                -- Secret-safe: don't compare auraData to nil; use type() gating.
                if type(auraData) ~= "table" then
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


-- Preview label (Edit Mode only). Created once and toggled on/off per icon render.
icon._msufA2_previewLabel = icon._msufCountFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
-- Label should always identify the bar without obscuring icons.
-- Anchor it slightly above the first icon, left-aligned (matches "Private" bar readability).
icon._msufA2_previewLabel:SetPoint("BOTTOMLEFT", icon, "TOPLEFT", 2, 6)
icon._msufA2_previewLabel:SetWordWrap(false)
icon._msufA2_previewLabel:SetNonSpaceWrap(false)
icon._msufA2_previewLabel:SetJustifyH("LEFT")
icon._msufA2_previewLabel:SetJustifyV("MIDDLE")
icon._msufA2_previewLabel:SetTextColor(1, 1, 1, 0.95)
icon._msufA2_previewLabel:SetShadowColor(0, 0, 0, 1)
icon._msufA2_previewLabel:SetShadowOffset(1, -1)
icon._msufA2_previewLabel:Hide()

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


-- Private aura marker (player-only): small lock in the top-left corner.
-- We keep this lightweight and purely visual (no glow libs / no combat-unsafe calls).
icon._msufPrivateMark = icon:CreateTexture(nil, "OVERLAY")
icon._msufPrivateMark:SetTexture("Interface\\Buttons\\UI-GroupLoot-LockIcon")
icon._msufPrivateMark:SetSize(12, 12)
icon._msufPrivateMark:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
icon._msufPrivateMark:SetAlpha(0.9)
icon._msufPrivateMark:Hide()

    -- Register with Masque if enabled (RenderUnit caches the state)
    do
        local st = API and API.state
        if st and st._msufA2_masqueWant and Masque_AddButton then
            local shared = st._msufA2_masqueShared
            if shared then
                Masque_AddButton(icon, shared)
            end
        end
        icon._msufA2_masqueStamp = (st and st._msufA2_masqueStamp) or 0
    end

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
            MSUF_A2_ApplyStackTextOffsets(icon, unit, shared, stackAnchor)
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

-- Layout a container's icon grid.
-- IMPORTANT: This is called once per container (mixed, buffs, debuffs).
-- If buffs/debuffs have different icon sizes, call this with the desired iconSize for that container.
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

	    -- Defensive defaults / normalization.
	    -- (All inputs should be numeric except growth/rowWrap, but older stamps or bad calls can leak strings.)
	    iconSize = tonumber(iconSize) or 20
	    if iconSize < 1 then iconSize = 20 end
	
	    spacing = tonumber(spacing) or 2
	    if spacing < 0 then spacing = 0 end
	
	    perRow = tonumber(perRow) or 1
	    perRow = math.floor(perRow)
	    if perRow < 1 then perRow = 1 end
	    if perRow > 40 then perRow = 40 end
	
	    if growth ~= "LEFT" and growth ~= "RIGHT" and growth ~= "UP" and growth ~= "DOWN" then
	        growth = "RIGHT"
	    end
	
	    -- keep old behavior if missing/invalid.
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
            local needReskin = false

            for i = oldCount + 1, count do
                local icon = AcquireIcon(container, i)
                icon:SetSize(iconSize, iconSize)
                if icon.MSUF_MasqueAdded and icon._msufA2_masqueSized ~= iconSize then
                    icon._msufA2_masqueSized = iconSize
                    needReskin = true
                end

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

            if needReskin then
                if Masque_RequestReskin then Masque_RequestReskin() end
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
    local needReskin = false

    for i = 1, count do
        local icon = AcquireIcon(container, i)
        -- Only run when layout inputs changed, so always set size + anchors here.
        icon:SetSize(iconSize, iconSize)
        if icon.MSUF_MasqueAdded and icon._msufA2_masqueSized ~= iconSize then
            icon._msufA2_masqueSized = iconSize
            needReskin = true
        end

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

    if needReskin then
        if Masque_RequestReskin then Masque_RequestReskin() end
    end

    HideUnused(container, count + 1)
    return math.ceil(count / perRow)
end

-- ------------------------------------------------------------
-- Per-unit attachment
-- ------------------------------------------------------------

AurasByUnit = {}

-- Expose internal state for split modules (Preview/CooldownText)
API.state = (type(API.state) == "table") and API.state or {}
API.state.aurasByUnit = AurasByUnit

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
    -- MSUF-only Edit Mode:
    -- Blizzard Edit Mode is intentionally ignored (Blizzard lifecycle currently unreliable on reload/zone transitions).
    -- 1) Preferred state object (MSUF_EditState) introduced by MSUF_EditMode.lua
    local st = rawget(_G, "MSUF_EditState")
    if type(st) == "table" and st.active == true then
        return true
    end

    -- 2) Legacy global boolean used by older patches
    if rawget(_G, "MSUF_UnitEditModeActive") == true then
        return true
    end

    -- 3) Exported helper from MSUF_EditMode.lua (now MSUF-only)
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

    if unit == "player" then return a2.showPlayer end

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

-- Forward declarations for Private Aura anchor helpers (Blizzard-rendered private aura icons)
local MSUF_A2_PrivateAuras_Clear
local MSUF_A2_PrivateAuras_RebuildIfNeeded

local function EnsureAttached(unit)
    local entry = AurasByUnit[unit]
    local frame = FindUnitFrame(unit)
    if not frame then
        return nil
    end

    if entry and entry.frame == frame and entry.anchor and entry.anchor:GetParent() then
        return entry
    end-- If we are re-attaching (frame changed), make sure old private anchors are removed and old anchor is hidden.
if entry then
    if MSUF_A2_PrivateAuras_Clear then
        MSUF_A2_PrivateAuras_Clear(entry)
    end
    if entry.anchor then
        entry.anchor:Hide()
    end
end



    -- Create anchor (parented to UIParent but anchored to the unitframe so it follows MSUF edit moves)
    local anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetSize(1, 1)
    anchor:SetFrameStrata("MEDIUM")
    anchor:SetFrameLevel(50)

    local debuffs = CreateFrame("Frame", nil, anchor)
    debuffs:SetSize(1, 1)
    debuffs:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)

    local buffs = CreateFrame("Frame", nil, anchor)
    buffs:SetSize(1, 1)
    buffs:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 30)
local mixed = CreateFrame("Frame", nil, anchor)
mixed:SetSize(1, 1)
mixed:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
local private = CreateFrame("Frame", nil, anchor)
private:SetSize(1, 1)
private:SetPoint("BOTTOMLEFT", buffs, "TOPLEFT", 0, 0)
private:Hide()


    -- Sync show/hide with the unitframe
    SafeCall(frame.HookScript, frame, "OnShow", function()
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
        private = private,
    }
    AurasByUnit[unit] = entry
    return entry
end

-- Forward declarations for Auras 2\.0 Edit Mode helpers
local MSUF_A2_GetEffectiveSizing
local MSUF_A2_ComputeDefaultEditBoxSize
local MSUF_A2_GetEffectiveLayout


-- ---------------------------------------------------------
-- Private Auras (Blizzard-rendered) via C_UnitAuras.AddPrivateAuraAnchor
--  * No spell tracking lists required.
--  * We only provide anchor "slots" and let Blizzard render icon + countdown.
--  * Supports Player / Target / Focus / Boss units (boss1..bossN).
-- ---------------------------------------------------------

local function MSUF_A2_PrivateAuras_Supported()
    return (C_UnitAuras
        and type(C_UnitAuras.AddPrivateAuraAnchor) == "function"
        and type(C_UnitAuras.RemovePrivateAuraAnchor) == "function") and true or false
end

-- Private aura data is intentionally not exposed to addons; Blizzard renders the icons.
-- Some private-aura payloads appear to be delivered only for the canonical "player"
-- unit token (not aliases like "focus" even if focus == player). To keep MSUF behavior
-- intuitive, we map focus/target -> "player" when they point at the player.
local function MSUF_A2_PrivateAuras_GetEffectiveUnitToken(unit)
    if type(unit) ~= "string" then return unit end

    if unit ~= "player" and type(UnitIsUnit) == "function" then
        -- If the current unit token is the player (e.g. focus self), bind anchors to "player".
        if UnitIsUnit(unit, "player") then
            return "player"
        end
    end

    return unit
end


MSUF_A2_PrivateAuras_Clear = function(entry)
    if not entry then return end

    local ids = entry._msufA2_privateAnchorIDs
    if type(ids) == "table" and C_UnitAuras and type(C_UnitAuras.RemovePrivateAuraAnchor) == "function" then
        for i = 1, #ids do
            local id = ids[i]
            if id then
                C_UnitAuras.RemovePrivateAuraAnchor(id)
            end
        end
    end
    entry._msufA2_privateAnchorIDs = nil
    entry._msufA2_privateCfgSig = nil
    entry._msufA2_privateCfgUnit = nil
    entry._msufA2_privateCfgEffToken = nil
    entry._msufA2_privateCfgIconSize = nil
    entry._msufA2_privateCfgSpacing = nil
    entry._msufA2_privateCfgMaxN = nil
    entry._msufA2_privateCfgShowFrame = nil
    entry._msufA2_privateCfgShowNums = nil
    entry._msufA2_privateCfgHighlight = nil
    entry._msufA2_privateCfgLayoutMode = nil

    local slots = entry._msufA2_privateSlots
    if type(slots) == "table" then
        for i = 1, #slots do
            if slots[i] then slots[i]:Hide() end
        end
    end
    if entry.private then entry.private:Hide() end
end

local function MSUF_A2_PrivateAuras_EnsureSlots(entry, maxN)
    if not entry or not entry.private or maxN <= 0 then return nil end

    local slots = entry._msufA2_privateSlots
    if type(slots) ~= "table" then
        slots = {}
        entry._msufA2_privateSlots = slots
    end

    for i = 1, maxN do
        if not slots[i] then
            local slot = CreateFrame("Frame", nil, entry.private, "BackdropTemplate")
            slot:SetSize(1, 1)
            slot:SetFrameStrata("MEDIUM")
            slot:SetFrameLevel(60)

            slot:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            slot:SetBackdropBorderColor(0, 0, 0, 0)

            -- Corner marker (shown only when highlight is enabled).
            local mark = slot:CreateTexture(nil, "OVERLAY")
            mark:SetTexture("Interface\\Buttons\\UI-Quickslot2")
            mark:SetTexCoord(0.0, 0.25, 0.0, 0.25)
            mark:SetPoint("TOPLEFT", slot, "TOPLEFT", -2, 2)
            mark:SetSize(14, 14)
            mark:SetAlpha(0.9)
            mark:Hide()
            slot._msufPrivateMark = mark

            slots[i] = slot
        end
    end

    for i = maxN + 1, #slots do
        if slots[i] then slots[i]:Hide() end
    end

    return slots
end

MSUF_A2_PrivateAuras_RebuildIfNeeded = function(entry, shared, iconSize, spacing, layoutMode)
    if not entry or not shared then return end

    local unit = entry.unit
    if type(unit) ~= "string" then
        MSUF_A2_PrivateAuras_Clear(entry)
        return
    end

    -- Per-unit enable toggles (shared layout feature).
    local enabled = false
    if unit == "player" then
        enabled = (shared.showPrivateAurasPlayer == true)
    elseif unit == "target" then
        enabled = false -- Target private auras removed
    elseif unit == "focus" then
        enabled = (shared.showPrivateAurasFocus == true)
    elseif unit:match("^boss%d$") then
        enabled = (shared.showPrivateAurasBoss == true)
    else
        enabled = false
    end

    if not enabled then
        MSUF_A2_PrivateAuras_Clear(entry)
        return
    end

    if not MSUF_A2_PrivateAuras_Supported() then
        MSUF_A2_PrivateAuras_Clear(entry)
        return
    end

    local maxN
    if unit == "player" then
        maxN = shared.privateAuraMaxPlayer or 6
    else
        maxN = shared.privateAuraMaxOther or 6
    end
    if type(maxN) ~= "number" then maxN = 6 end
    if maxN < 0 then maxN = 0 end
    if maxN > 12 then maxN = 12 end
    if maxN == 0 then
        MSUF_A2_PrivateAuras_Clear(entry)
        return
    end

    local showCountdownFrame = (shared.showCooldownSwipe == true)
    local showCountdownNumbers = (shared.showCooldownText == true)

    local highlight = (shared.highlightPrivateAuras == true)

    local effectiveToken = MSUF_A2_PrivateAuras_GetEffectiveUnitToken(unit)

        local lm = layoutMode or ""
    if entry._msufA2_privateCfgUnit == unit
        and entry._msufA2_privateCfgEffToken == effectiveToken
        and entry._msufA2_privateCfgIconSize == iconSize
        and entry._msufA2_privateCfgSpacing == spacing
        and entry._msufA2_privateCfgMaxN == maxN
        and entry._msufA2_privateCfgShowFrame == (showCountdownFrame == true)
        and entry._msufA2_privateCfgShowNums == (showCountdownNumbers == true)
        and entry._msufA2_privateCfgHighlight == (highlight == true)
        and entry._msufA2_privateCfgLayoutMode == lm
        and type(entry._msufA2_privateAnchorIDs) == "table"
    then
        if entry.private then entry.private:Show() end
        local slots = entry._msufA2_privateSlots
        if type(slots) == "table" then
            for i = 1, maxN do if slots[i] then slots[i]:Show() end end
        end
        return
    end

    MSUF_A2_PrivateAuras_Clear(entry)

    if not entry.private then return end
    local slots = MSUF_A2_PrivateAuras_EnsureSlots(entry, maxN)
    if not slots then return end

    local step = (iconSize + spacing)
    if type(step) ~= "number" or step <= 0 then step = 28 end

    entry.private:Show()
    entry._msufA2_privateCfgSig = nil -- legacy field (no longer used)
    entry._msufA2_privateCfgUnit = unit
    entry._msufA2_privateCfgEffToken = effectiveToken
    entry._msufA2_privateCfgIconSize = iconSize
    entry._msufA2_privateCfgSpacing = spacing
    entry._msufA2_privateCfgMaxN = maxN
    entry._msufA2_privateCfgShowFrame = (showCountdownFrame == true)
    entry._msufA2_privateCfgShowNums = (showCountdownNumbers == true)
    entry._msufA2_privateCfgHighlight = (highlight == true)
    entry._msufA2_privateCfgLayoutMode = lm
    entry._msufA2_privateAnchorIDs = {}

    -- Size the container so it has a meaningful clickable/drag area in Edit Mode.
    entry.private:SetSize((maxN * step) - spacing, iconSize)

    for i = 1, maxN do
        local slot = slots[i]
        slot:ClearAllPoints()
        slot:SetPoint("BOTTOMLEFT", entry.private, "BOTTOMLEFT", (i - 1) * step, 0)
        slot:SetSize(iconSize, iconSize)

        if highlight then
            slot:SetBackdropBorderColor(0.80, 0.30, 1.00, 1.0) -- purple
            if slot._msufPrivateMark then slot._msufPrivateMark:Show() end
        else
            slot:SetBackdropBorderColor(0, 0, 0, 0)
            if slot._msufPrivateMark then slot._msufPrivateMark:Hide() end
        end

        slot:Show()

        local args = {
            unitToken = effectiveToken,
            auraIndex = i,
            parent = slot,
            showCountdownFrame = showCountdownFrame,
            showCountdownNumbers = showCountdownNumbers,
            iconInfo = {
                iconWidth = iconSize,
                iconHeight = iconSize,
                iconAnchor = {
                    point = "CENTER",
                    relativeTo = slot,
                    relativePoint = "CENTER",
                    offsetX = 0,
                    offsetY = 0,
                },
            },
        }

        local anchorID = C_UnitAuras.AddPrivateAuraAnchor(args)
        if anchorID then
            table.insert(entry._msufA2_privateAnchorIDs, anchorID)
        end
    end

end

local A2_SPLIT_ANCHOR_MAP = {
    TOP_BOTTOM_BUFFS   = { buffs = "ABOVE", debuffs = "BELOW" },
    TOP_BOTTOM_DEBUFFS = { buffs = "BELOW", debuffs = "ABOVE" },
    TOP_RIGHT_BUFFS    = { buffs = "ABOVE", debuffs = "RIGHT" },
    TOP_RIGHT_DEBUFFS  = { buffs = "RIGHT", debuffs = "ABOVE" },
    BOTTOM_RIGHT_BUFFS   = { buffs = "BELOW", debuffs = "RIGHT" },
    BOTTOM_RIGHT_DEBUFFS = { buffs = "RIGHT", debuffs = "BELOW" },
    BOTTOM_LEFT_BUFFS    = { buffs = "BELOW", debuffs = "LEFT" },
    BOTTOM_LEFT_DEBUFFS  = { buffs = "LEFT", debuffs = "BELOW" },
    TOP_LEFT_BUFFS   = { buffs = "ABOVE", debuffs = "LEFT" },
    TOP_LEFT_DEBUFFS = { buffs = "LEFT", debuffs = "ABOVE" },
}

local function A2_AnchorStacked(entry, by, buffDX, buffDY, debuffDX, debuffDY)
    local bdx = (type(buffDX) == "number") and buffDX or 0
    local bdy = (type(buffDY) == "number") and buffDY or 0
    local ddx = (type(debuffDX) == "number") and debuffDX or 0
    local ddy = (type(debuffDY) == "number") and debuffDY or 0
    local sepY = (type(by) == "number") and by or 0

    entry.debuffs:ClearAllPoints()
    entry.debuffs:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", ddx, ddy)

    entry.buffs:ClearAllPoints()
    entry.buffs:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", bdx, sepY + bdy)

    if entry.mixed then
        entry.mixed:ClearAllPoints()
        entry.mixed:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)
    end
end

local function UpdateAnchor(entry, shared, offX, offY, boxW, boxH, layoutModeOverride, buffDebuffAnchorOverride, splitSpacingOverride, isEditMode)
    if not entry or not entry.anchor or not entry.frame or not shared then return end

    local unitKey = entry.unit
    local iconSize, spacing, perRow, buffOffsetY = MSUF_A2_GetEffectiveSizing(unitKey, shared)


    -- If callers forget to pass isEditMode, default to the real Edit Mode state.
    -- This prevents preview/mover anchors from oscillating between edit/non-edit paths.
    if isEditMode == nil then
        isEditMode = (IsEditModeActive and IsEditModeActive()) and true or false
    end
    local x = (offX ~= nil) and offX or (shared.offsetX or 0)
    local y = (offY ~= nil) and offY or (shared.offsetY or 0)

    -- Independent Buff/Debuff offsets + icon size (per-unit overrides via Edit Mode popup)
    local buffIconSize = MSUF_A2_ResolveNumber(unitKey, shared, "buffGroupIconSize", iconSize, 10, 80, true)
    local debuffIconSize = MSUF_A2_ResolveNumber(unitKey, shared, "debuffGroupIconSize", iconSize, 10, 80, true)
    local buffDX = MSUF_A2_ResolveNumber(unitKey, shared, "buffGroupOffsetX", 0, -2000, 2000, true)
    local buffDY = MSUF_A2_ResolveNumber(unitKey, shared, "buffGroupOffsetY", 0, -2000, 2000, true)
    local debuffDX = MSUF_A2_ResolveNumber(unitKey, shared, "debuffGroupOffsetX", 0, -2000, 2000, true)
    local debuffDY = MSUF_A2_ResolveNumber(unitKey, shared, "debuffGroupOffsetY", 0, -2000, 2000, true)

    -- Edit Mode QoL: Prevent Buff/Debuff/Private previews from stacking while positioning.
    -- This ONLY affects Edit Mode visuals; DB values remain unchanged until the user drags a mover.
    if isEditMode then
        local maxSize = iconSize
        if type(buffIconSize) == "number" and buffIconSize > maxSize then maxSize = buffIconSize end
        if type(debuffIconSize) == "number" and debuffIconSize > maxSize then maxSize = debuffIconSize end
        local minSep = maxSize + spacing + 8

do
    local fn = _G.MSUF_A2_GetMinStackedSeparationForEditMode
    if type(fn) == "function" then
        local ok, v = pcall(fn, unitKey)
        if ok and type(v) == "number" and v > 0 then
            minSep = v
        end
    end
end
        if type(buffOffsetY) ~= "number" then
            buffOffsetY = minSep
        elseif buffOffsetY < minSep then
            buffOffsetY = minSep
        end
    end


    entry.anchor:ClearAllPoints()
    entry.anchor:SetPoint("BOTTOMLEFT", entry.frame, "TOPLEFT", x, y)

    -- Private Auras (Blizzard anchors) are offset independently from buff/debuff containers.
    local privOffX = MSUF_A2_ResolveNumber(unitKey, shared, "privateOffsetX", 0, -2000, 2000, true)
    local privOffY = MSUF_A2_ResolveNumber(unitKey, shared, "privateOffsetY", 0, -2000, 2000, true)
    -- If Private offsets were never customized, keep Private above Buffs in Edit Mode
    -- so the three mover bars are easier to grab separately.
    do
        local ul_tmp = MSUF_A2_GetPerUnitLayout(unitKey)
        local hasPriv = (ul_tmp and (ul_tmp.privateOffsetX ~= nil or ul_tmp.privateOffsetY ~= nil)) and true or false
        if isEditMode and (not hasPriv) then
            local maxSize = iconSize
            if type(buffIconSize) == "number" and buffIconSize > maxSize then maxSize = buffIconSize end
            if type(debuffIconSize) == "number" and debuffIconSize > maxSize then maxSize = debuffIconSize end
            local minSep = maxSize + spacing + 8

do
    local fn = _G.MSUF_A2_GetMinStackedSeparationForEditMode
    if type(fn) == "function" then
        local ok, v = pcall(fn, unitKey)
        if ok and type(v) == "number" and v > 0 then
            minSep = v
        end
    end
end
            privOffY = (buffOffsetY or minSep) + minSep
        end
    end
    if entry.private then
        entry.private:ClearAllPoints()
        entry.private:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", privOffX, privOffY)
    end

    local mode = layoutModeOverride or (shared.layoutMode or "SEPARATE")
    if mode == "SINGLE" and entry.mixed then
        if entry.private then
            entry.private:ClearAllPoints()
            entry.private:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", privOffX, privOffY)
        end

        entry.mixed:ClearAllPoints()
        entry.mixed:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)

        entry.debuffs:ClearAllPoints()
        entry.debuffs:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)

        entry.buffs:ClearAllPoints()
        entry.buffs:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)
    else
        local splitSpacing = tonumber(splitSpacingOverride)
        if splitSpacing == nil then
            splitSpacing = MSUF_A2_ResolveNumber(unitKey, shared, "splitSpacing", 0, 0, 80, false)
        else
            if splitSpacing < 0 then splitSpacing = 0 end
            if splitSpacing > 80 then splitSpacing = 80 end
        end

        local function Place(container, pos, dx, dy, size)
            container:ClearAllPoints()

            local s = (type(size) == "number") and size or iconSize
            local ox = (type(dx) == "number") and dx or 0
            local oy = (type(dy) == "number") and dy or 0

            if pos == "ABOVE" then
                container:SetPoint("BOTTOMLEFT", entry.frame, "TOPLEFT", x + ox, y + splitSpacing + oy)
            elseif pos == "BELOW" then
                container:SetPoint("BOTTOMLEFT", entry.frame, "BOTTOMLEFT", x + ox, y - s - splitSpacing + oy)
            elseif pos == "RIGHT" then
                container:SetPoint("BOTTOMLEFT", entry.frame, "RIGHT", x + splitSpacing + ox, y - (s * 0.5) + oy)
            elseif pos == "LEFT" then
                container:SetPoint("BOTTOMLEFT", entry.frame, "LEFT", x - s - splitSpacing + ox, y - (s * 0.5) + oy)
            else
                container:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", ox, oy)
            end
        end

        local anchorMode = buffDebuffAnchorOverride or (shared.buffDebuffAnchor or "STACKED")
        local map = (anchorMode and A2_SPLIT_ANCHOR_MAP[anchorMode]) or nil
        if anchorMode == "STACKED" or anchorMode == nil or not map then
            A2_AnchorStacked(entry, buffOffsetY, buffDX, buffDY, debuffDX, debuffDY)
        else
            Place(entry.buffs, map.buffs, buffDX, buffDY, buffIconSize)
            Place(entry.debuffs, map.debuffs, debuffDX, debuffDY, debuffIconSize)
        end

        if entry.mixed then
            entry.mixed:ClearAllPoints()
            entry.mixed:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)
        end
    end

    -- Split Edit Movers: position + size follow their respective containers (Buffs / Debuffs / Private).
    local function SetMover(mover, rel, w, h, ox, oy)
        if not mover then return end
        mover:ClearAllPoints()
        if rel then
            mover:SetPoint("BOTTOMLEFT", rel, "BOTTOMLEFT", ox or 0, oy or 0)
        else
            mover:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", ox or 0, oy or 0)
        end
        if w and h then mover:SetSize(w, h) end
    end

    -- Use effective per-row sizing so the click/drag area is predictable even if there are currently no auras.
    local bw = (perRow * buffIconSize) + (math.max(0, perRow - 1) * spacing)
    local bh = math.max(buffIconSize, 24)
    local dw = (perRow * debuffIconSize) + (math.max(0, perRow - 1) * spacing)
    local dh = math.max(debuffIconSize, 24)

    -- Private size can differ (shared/privateSize or per-unit override).
    local privSize = iconSize
    if shared and type(shared.privateSize) == "number" then
        privSize = shared.privateSize
    end
    local ul = MSUF_A2_GetPerUnitLayout(unitKey)
    if ul and type(ul.privateSize) == "number" then
        privSize = ul.privateSize
    end
    privSize = tonumber(privSize) or iconSize
    if privSize < 10 then privSize = 10 end
    if privSize > 80 then privSize = 80 end
    local pw = (perRow * privSize) + (math.max(0, perRow - 1) * spacing)
    local ph = math.max(privSize, 24)


-- IMPORTANT: Buff/Debuff movers must NOT be anchored to their containers while dragging.
-- Mirror the container anchor points instead (same visual position, independent mover frame).
local function MirrorMoverToContainer(mover, container, w, h)
    if not mover then return end
    mover:ClearAllPoints()
    if container and container.GetPoint then
        local p, rel, rp, ox, oy = container:GetPoint(1)
        if p and rel and rp then
            mover:SetPoint(p, rel, rp, ox or 0, oy or 0)
        else
            mover:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)
        end
    else
        mover:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)
    end
    if w and h then mover:SetSize(w, h) end
end

MirrorMoverToContainer(entry.editMoverBuff, entry.buffs, bw, bh)
MirrorMoverToContainer(entry.editMoverDebuff, entry.debuffs, dw, dh)
SetMover(entry.editMoverPrivate, nil, pw, ph, privOffX, privOffY)
end

-- ---------------------------------------------------------
-- Edit Mode: Aura anchor mover (Target first)
-- ---------------------------------------------------------
MSUF_A2_GetEffectiveSizing = function(unitKey, shared)
    local iconSize = (shared and shared.iconSize) or 26
    local spacing  = (shared and shared.spacing) or 2
    local perRow   = (shared and shared.perRow) or 12
    local buffOffsetY = (shared and shared.buffOffsetY)

    -- Optional: independent group icon sizes (used for stacked-row separation default and split layout).
    local buffSize = (shared and shared.buffGroupIconSize) or nil
    local debuffSize = (shared and shared.debuffGroupIconSize) or nil

    local us = MSUF_A2_GetPerUnitSharedLayout(unitKey)
    if us and type(us.perRow) == "number" and us.perRow >= 1 then
        perRow = us.perRow
    end

    local ul = MSUF_A2_GetPerUnitLayout(unitKey)
    if ul then
        local v = ul.iconSize;           if type(v) == "number" and v > 1  then iconSize = v end
        v = ul.spacing;                  if type(v) == "number" and v >= 0 then spacing  = v end
        v = ul.perRow;                   if type(v) == "number" and v >= 1 then perRow   = v end
        v = ul.buffOffsetY;              if type(v) == "number"             then buffOffsetY = v end

        v = ul.buffGroupIconSize;        if type(v) == "number" and v > 1  then buffSize = v end
        v = ul.debuffGroupIconSize;      if type(v) == "number" and v > 1  then debuffSize = v end
    end

    if type(buffSize) == "number" then
        if buffSize < 10 then buffSize = 10 elseif buffSize > 80 then buffSize = 80 end
    else
        buffSize = nil
    end
    if type(debuffSize) == "number" then
        if debuffSize < 10 then debuffSize = 10 elseif debuffSize > 80 then debuffSize = 80 end
    else
        debuffSize = nil
    end

    if buffOffsetY == nil then
        local maxSize = iconSize
        if type(buffSize) == "number" and buffSize > maxSize then maxSize = buffSize end
        if type(debuffSize) == "number" and debuffSize > maxSize then maxSize = debuffSize end
        buffOffsetY = maxSize + spacing + 4
    end

    return iconSize, spacing, perRow, buffOffsetY
end

MSUF_A2_ComputeDefaultEditBoxSize = function(unitKey, shared)
    local iconSize, spacing, perRow, buffOffsetY = MSUF_A2_GetEffectiveSizing(unitKey, shared)

    local buffSize = MSUF_A2_ResolveNumber(unitKey, shared, "buffGroupIconSize", iconSize, 10, 80, true)
    local debuffSize = MSUF_A2_ResolveNumber(unitKey, shared, "debuffGroupIconSize", iconSize, 10, 80, true)
    local maxSize = math.max(iconSize or 0, buffSize or 0, debuffSize or 0)

    local w = (perRow * maxSize) + (math.max(0, perRow - 1) * spacing)
    local h = math.max(debuffSize, buffOffsetY + buffSize)
    return w, h
end

MSUF_A2_GetEffectiveLayout = function(unitKey, shared)
    local x = (shared and shared.offsetX) or 0
    local y = (shared and shared.offsetY) or 0

    local boxW, boxH
    local ul = MSUF_A2_GetPerUnitLayout(unitKey)
    if ul then
        if type(ul.offsetX) == "number" then x = ul.offsetX end
        if type(ul.offsetY) == "number" then y = ul.offsetY end
        if type(ul.width)  == "number" and ul.width  > 1 then boxW = ul.width end
        if type(ul.height) == "number" and ul.height > 1 then boxH = ul.height end
    end

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

local function MSUF_A2_SetEditMoversVisible(entry, show)
    if not entry then return end
    if entry.editMoverBuff then if show then entry.editMoverBuff:Show() else entry.editMoverBuff:Hide() end end
    if entry.editMoverDebuff then if show then entry.editMoverDebuff:Show() else entry.editMoverDebuff:Hide() end end
    if entry.editMoverPrivate then if show then entry.editMoverPrivate:Show() else entry.editMoverPrivate:Hide() end end
end

local function MSUF_A2_AnyEditMover(entry)
    return (entry and (entry.editMoverBuff or entry.editMoverDebuff or entry.editMoverPrivate)) and true or false
end

local function MSUF_A2_HideEditMovers(entry)
    MSUF_A2_SetEditMoversVisible(entry, false)
end

local A2_MOVER_KEYS = {
    buff   = { "buffGroupOffsetX",   "buffGroupOffsetY"   },
    buffs  = { "buffGroupOffsetX",   "buffGroupOffsetY"   },
    debuff = { "debuffGroupOffsetX", "debuffGroupOffsetY" },
    debuffs= { "debuffGroupOffsetX", "debuffGroupOffsetY" },
    private= { "privateOffsetX",     "privateOffsetY"     },
}

local function MSUF_A2_GetMoverKeyPair(kind)
    local k = (type(kind) == "string") and kind or "private"
    -- kind is always an internal constant ("buff"/"debuff"/"private"), but accept plural/safe fallbacks.
    if k == "BUFF" or k == "Buff" then k = "buff" end
    if k == "DEBUFF" or k == "Debuff" then k = "debuff" end
    if k == "PRIVATE" or k == "Private" then k = "private" end
    local pair = A2_MOVER_KEYS[k] or A2_MOVER_KEYS.private
    return pair[1], pair[2]
end

local function MSUF_A2_GetMoverStartOffsets(unitKey, shared, kind)
    local kx, ky = MSUF_A2_GetMoverKeyPair(kind)
    return MSUF_A2_ResolveNumber(unitKey, shared, kx, 0, -2000, 2000, true),
           MSUF_A2_ResolveNumber(unitKey, shared, ky, 0, -2000, 2000, true)
end

local function MSUF_A2_WriteMoverOffsets(a2, unitKey, kind, newX, newY)
    if not (a2 and unitKey and kind) then return end
    a2.perUnit = (type(a2.perUnit) == "table") and a2.perUnit or {}
    local perUnit = a2.perUnit

    local u = perUnit[unitKey]
    if type(u) ~= "table" then
        u = {}
        perUnit[unitKey] = u
    end

    u.overrideLayout = true
    u.layout = (type(u.layout) == "table") and u.layout or {}
    local ul = u.layout

    local kx, ky = MSUF_A2_GetMoverKeyPair(kind)
    ul[kx] = newX
    ul[ky] = newY
end

local function MSUF_A2_EnsureGroupEditMover(entry, unitKey, kind, labelText)
    if not entry or not unitKey or not kind then return end

    local field
    if kind == "buff" then field = "editMoverBuff"
    elseif kind == "debuff" then field = "editMoverDebuff"
    else field = "editMoverPrivate" end

    if entry[field] then return end

    local moverName = "MSUF_Auras2_" .. (tostring(unitKey):gsub("%W", "")) .. "EditMover_" .. tostring(kind)
    local mover = CreateFrame("Frame", moverName, UIParent, "BackdropTemplate")
    mover:SetFrameStrata("DIALOG")
    mover:SetFrameLevel(500)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(true)


    -- QoL: make the mover easy to grab even if preview labels sit slightly above the icon row.
    if mover.SetHitRectInsets then
        mover:SetHitRectInsets(-2, -2, -22, -2)
    end

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

    -- Header bar + label (like Private Auras mover): easier to read and easier to click/drag without obscuring icons
    local headerH = 18
    local header = CreateFrame("Frame", nil, mover, "BackdropTemplate")
    header:SetPoint("TOPLEFT", mover, "TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", mover, "TOPRIGHT", -2, -2)
    header:SetHeight(headerH)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })

    -- Subtle per-kind tint (Edit Mode only, no gameplay impact)
    local hr, hg, hb = 0.20, 0.65, 1.00
    if kind == "buff" then
        hr, hg, hb = 0.18, 0.80, 0.30
    elseif kind == "debuff" then
        hr, hg, hb = 0.90, 0.20, 0.20
    elseif kind == "private" then
        hr, hg, hb = 0.20, 0.65, 1.00
    end
    header:SetBackdropColor(hr, hg, hb, 0.22)
    mover._msufHeader = header

    -- Drag QoL: the header bar must never block dragging; route mouse events to the mover.
    header:EnableMouse(true)
    header:SetScript("OnMouseDown", function(h, btn)
        local p = h and h.GetParent and h:GetParent()
        local fn = p and p.GetScript and p:GetScript("OnMouseDown")
        if fn then fn(p, btn) end
    end)
    header:SetScript("OnMouseUp", function(h, btn)
        local p = h and h.GetParent and h:GetParent()
        local fn = p and p.GetScript and p:GetScript("OnMouseUp")
        if fn then fn(p, btn) end
    end)


    local headerIcon = header:CreateTexture(nil, "OVERLAY")
    headerIcon:SetSize(14, 14)
    headerIcon:SetPoint("LEFT", header, "LEFT", 6, 0)
    if kind == "buff" then
        headerIcon:SetTexture("Interface\\Icons\\Spell_Holy_WordFortitude")
    elseif kind == "debuff" then
        headerIcon:SetTexture("Interface\\Icons\\Spell_Shadow_ShadowWordPain")
    else
        headerIcon:SetTexture("Interface\\Icons\\Ability_Creature_Cursed_03")
    end
    headerIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    mover._msufHeaderIcon = headerIcon

    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", headerIcon, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    label:SetJustifyH("LEFT")
    label:SetText(labelText or (tostring(unitKey) .. " Auras"))
    label:SetTextColor(0.95, 0.95, 0.95, 0.92)
    mover._msufLabel = label

    mover:Hide()

    mover._msufAuraEntry = entry
    mover._msufAuraUnitKey = unitKey
    mover._msufA2MoverKind = kind

    local function IsAnyPopupOpen()
        local st = rawget(_G, "MSUF_EditState")
        if not (st and st.popupOpen) then
            return false
        end

        -- Auras2 special-case: allow dragging the Aura movers while the Auras2 Position Popup is open.
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
        if InCombatLockdown() then return end

        EnsureDB()
        local a2 = MSUF_DB and MSUF_DB.auras2
        if type(a2) ~= "table" then return end
        local shared = a2.shared
        if type(shared) ~= "table" then return end

        local key = self._msufAuraUnitKey
        local moverKind = self._msufA2MoverKind or "buff"

        local startX = self._msufDragStartOffsetX or 0
        local startY = self._msufDragStartOffsetY or 0

        local newX = math.floor(startX + dx + 0.5)
        local newY = math.floor(startY + dy + 0.5)

        -- Clamp to the same range as the popup steppers to avoid accidental far-off positions.
        if newX < -2000 then newX = -2000 end
        if newX >  2000 then newX =  2000 end
        if newY < -2000 then newY = -2000 end
        if newY >  2000 then newY =  2000 end

        -- Edit Mode safety: keep Buffs and Debuffs from collapsing into the same space while dragging.
        -- We only clamp in STACKED + SEPARATE mode; this preserves full freedom for other layouts.
        local function _ClampStackedSep(unitK, kind, x, y)
            if kind ~= "buff" and kind ~= "debuff" then return x, y end
            if not shared then return x, y end
            local mode = shared.layoutMode or "SEPARATE"
            if mode == "SINGLE" then return x, y end
            local anchorMode = shared.buffDebuffAnchor or "STACKED"
            if anchorMode ~= "STACKED" then return x, y end

            -- Compute the minimum separation based on the largest icon size in use.
            local iconSize, spacing, _, buffOffsetY = MSUF_A2_GetEffectiveSizing(unitK, shared)
            local buffIconSize = MSUF_A2_ResolveNumber(unitK, shared, "buffGroupIconSize", iconSize, 10, 80, true)
            local debuffIconSize = MSUF_A2_ResolveNumber(unitK, shared, "debuffGroupIconSize", iconSize, 10, 80, true)

            local maxSize = tonumber(iconSize) or 26
            if type(buffIconSize) == "number" and buffIconSize > maxSize then maxSize = buffIconSize end
            if type(debuffIconSize) == "number" and debuffIconSize > maxSize then maxSize = debuffIconSize end
            local minSep = maxSize + (tonumber(spacing) or 2) + 8

            if type(buffOffsetY) ~= "number" or buffOffsetY < minSep then
                buffOffsetY = minSep
            end

            local buffDY = MSUF_A2_ResolveNumber(unitK, shared, "buffGroupOffsetY", 0, -2000, 2000, true)
            local debuffDY = MSUF_A2_ResolveNumber(unitK, shared, "debuffGroupOffsetY", 0, -2000, 2000, true)

            if kind == "buff" then
                -- Buffs sit above Debuffs in STACKED mode: ensure (buffOffsetY + buffDY) - debuffDY >= minSep
                local sep = buffOffsetY + y - debuffDY
                if sep < minSep then
                    y = debuffDY + (minSep - buffOffsetY)
                end
            else
                -- Debuffs sit below Buffs: ensure (buffOffsetY + buffDY) - debuffDY >= minSep  => debuffDY <= buffOffsetY + buffDY - minSep
                local sep = buffOffsetY + buffDY - y
                if sep < minSep then
                    y = buffOffsetY + buffDY - minSep
                end
            end

            -- Re-clamp to the supported offset range.
            if y < -2000 then y = -2000 end
            if y >  2000 then y =  2000 end
            return x, y
        end

        newX, newY = _ClampStackedSep(key, moverKind, newX, newY)


-- Prefer the EditMode clamp (multi-row aware). Fallback: keep local clamp above.
do
    local fn = _G.MSUF_A2_ClampGroupOffsetsForEditMode
    if type(fn) == "function" then
        local ok, cx, cy = pcall(fn, key, moverKind, newX, newY)
        if ok then
            if type(cx) == "number" then newX = cx end
            if type(cy) == "number" then newY = cy end
        end
    end
end

        local function ApplyToUnit(unitK)
            MSUF_A2_WriteMoverOffsets(a2, unitK, moverKind, newX, newY)

            local e = AurasByUnit and AurasByUnit[unitK]
			if e and e.anchor then
				local ox, oy, bw, bh = MSUF_A2_GetEffectiveLayout(unitK, shared)
				-- Keep drag refresh consistent with any Edit Mode preview override (e.g. split preview when saved mode is SINGLE).
				local lm = e._msufA2_editLayoutMode
				local bd = e._msufA2_editBuffDebuffAnchor
				local ss = e._msufA2_editSplitSpacing
				UpdateAnchor(e, shared, ox, oy, bw, bh, lm, bd, ss, (IsEditModeActive and IsEditModeActive()) and true or false)
			end
        end

        if shared.bossEditTogether == true and type(key) == "string" and key:match("^boss%d+$") then
            for i = 1, 5 do
                ApplyToUnit("boss" .. i)
            end
        else
            ApplyToUnit(key)
        end

        if type(_G.MSUF_SyncAuras2PositionPopup) == "function" then
            _G.MSUF_SyncAuras2PositionPopup(key)
        end
    end

    mover:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        if InCombatLockdown() then return end
        if IsAnyPopupOpen() then return end

        EnsureDB()
        local a2 = MSUF_DB and MSUF_DB.auras2
        if type(a2) ~= "table" then return end
        local shared = a2.shared
        if type(shared) ~= "table" then return end

        local key = self._msufAuraUnitKey
        local moverKind = self._msufA2MoverKind or "buff"

        local startX, startY = MSUF_A2_GetMoverStartOffsets(key, shared, moverKind)

        self._msufDragStartOffsetX = startX
        self._msufDragStartOffsetY = startY

        local x, y = GetCursorScaled()
        self._msufDragStartCursorX = x
        self._msufDragStartCursorY = y
        self._msufDragMoved = false

        if not self._msufMoverOnUpdate then
            self._msufMoverOnUpdate = function(me)
                local cx, cy = GetCursorScaled()
                local dx = cx - (me._msufDragStartCursorX or cx)
                local dy = cy - (me._msufDragStartCursorY or cy)
                if not me._msufDragMoved then
                    if (dx * dx + dy * dy) >= 9 then -- 3px threshold
                        me._msufDragMoved = true
                    else
                        return
                    end
                end
                ApplyDragDelta(me, dx, dy)
            end
        end
        self:SetScript("OnUpdate", self._msufMoverOnUpdate)
    end)

    mover:SetScript("OnMouseUp", function(self, button)
        if self:GetScript("OnUpdate") then
            self:SetScript("OnUpdate", nil)
            if self._msufDragMoved then
                self._msufDragMoved = false
                return
            end
        end

        local key = self._msufAuraUnitKey
        if type(_G.MSUF_OpenAuras2PositionPopup) == "function" then
            _G.MSUF_OpenAuras2PositionPopup(key, self)
        end
    end)

    entry[field] = mover
end

-- Convenience wrappers (kept for readability)
local function MSUF_A2_EnsureUnitEditMovers(entry, unitKey, baseLabel)
    if not entry or not unitKey then return end
    MSUF_A2_EnsureGroupEditMover(entry, unitKey, "buff",    (baseLabel or unitKey) .. " Buffs")
    MSUF_A2_EnsureGroupEditMover(entry, unitKey, "debuff",  (baseLabel or unitKey) .. " Debuffs")
    MSUF_A2_EnsureGroupEditMover(entry, unitKey, "private", (baseLabel or unitKey) .. " Private")
end

local function MSUF_A2_EnsureTargetEditMovers(entry)
    if not entry or entry.unit ~= "target" then return end
    return MSUF_A2_EnsureUnitEditMovers(entry, "target", "Target")
end

local function MSUF_A2_EnsureFocusEditMovers(entry)
    if not entry or entry.unit ~= "focus" then return end
    return MSUF_A2_EnsureUnitEditMovers(entry, "focus", "Focus")
end

local function MSUF_A2_EnsureBossEditMovers(entry)
    if not entry or type(entry.unit) ~= "string" then return end
    local u = entry.unit
    local n = u:match("^boss(%d+)$")
    if not n then return end
    return MSUF_A2_EnsureUnitEditMovers(entry, u, "Boss " .. n)
end

local function MSUF_A2_EnsurePlayerEditMovers(entry)
    if not entry or entry.unit ~= "player" then return end
    return MSUF_A2_EnsureUnitEditMovers(entry, "player", "Player")
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

local function MSUF_A2_IsDispellableAura(unit, aura)
    -- DISABLED: dispellable-aura feature removed per user request.
    -- Keep stub for compatibility, but never call UnitAuras dispel APIs (preview auras have no real instance).
    return false
end

-- Private aura detection
-- (spellID-based, cached). Player-only feature.
-- Note: Blizzard's private aura system intentionally hides most aura data from addons.
-- AuraIsPrivate lets us *detect* that the spell is part of that system so we can visually mark it.
local MSUF_A2__PrivateSpellCache = {}
local function MSUF_A2_IsPrivateAuraSpellID(spellID)
    if not spellID then return false end
    if not (C_UnitAuras and type(C_UnitAuras.AuraIsPrivate) == "function") then
        return false
    end

    local cached = MSUF_A2__PrivateSpellCache[spellID]
    if cached ~= nil then
        return cached == true
    end

    local ok, isPriv = pcall(C_UnitAuras.AuraIsPrivate, spellID)
    local v = (ok and isPriv == true) or false
    MSUF_A2__PrivateSpellCache[spellID] = v
    return v
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
-- eff = { includeDispellable=false, ... }
local function SetDispelBorder(icon, unit, aura, isHelpful, shared, allowHighlights, isOwn)
    if not icon or not icon._msufBorder then return end

    -- Shared config can be passed in by the caller (fast-path).
    if not shared then
        local _, s = GetAuras2DB()
        shared = s
    end

    local masqueOn = (Masque_IsEnabled and Masque_IsEnabled(shared)) and true or false

    -- Keep MSUF overlays above Masque regions (Masque can re-apply framelevels on skin changes).
    if masqueOn and icon.MSUF_MasqueAdded and Masque_SyncIconOverlayLevels then
        Masque_SyncIconOverlayLevels(icon)
    end

    local auraInstanceID = aura and (aura._msufAuraInstanceID or aura.auraInstanceID)

    local function ShowBorder(r, g, b, a)
        icon._msufBorder:Show()
        icon._msufBorder:SetBackdropBorderColor(r or 0, g or 0, b or 0, a or 1)
    end

    local function HideBaseBorder()
        -- If the active Masque skin provides its own border region, hide our default border.
        -- Otherwise, show the classic 1px black border.
        if masqueOn and Masque_SkinHasBorder and Masque_SkinHasBorder(icon) then
            if icon._msufBorder then icon._msufBorder:Hide() end
        else
            ShowBorder(0, 0, 0, 1)
        end
    end

    -- Preview-private always wins.
    if aura and aura._msufA2_previewIsPrivate == true then
        local pr, pg, pb = MSUF_A2_GetPrivatePlayerHighlightRGB()
        ShowBorder(pr, pg, pb, 1)
        if icon._msufPrivateMark then icon._msufPrivateMark:Show() end
        return
    end

    if icon._msufOwnGlow then icon._msufOwnGlow:Hide() end
    if icon._msufPrivateMark then icon._msufPrivateMark:Hide() end

    -- Player private aura highlight
    if unit == "player" and shared and shared.highlightPrivateAuras == true and aura then
        local sidStr = MSUF_A2_AuraFieldToString(aura, "spellId") or MSUF_A2_AuraFieldToString(aura, "spellID")
        local sid = sidStr and tonumber(sidStr) or nil
        if sid and MSUF_A2_IsPrivateAuraSpellID(sid) then
            local pr, pg, pb = MSUF_A2_GetPrivatePlayerHighlightRGB()
            ShowBorder(pr, pg, pb, 1)
            if icon._msufPrivateMark then icon._msufPrivateMark:Show() end
            return
        end
    end

    -- Own aura highlight
    if isOwn and shared then
        if isHelpful and shared.highlightOwnBuffs == true then
            local r, g, b = MSUF_A2_GetOwnBuffHighlightRGB()
            ShowBorder(r, g, b, 1)
            if icon._msufOwnGlow then
                icon._msufOwnGlow:SetVertexColor(r, g, b, 1)
                icon._msufOwnGlow:Show()
            end
            return
        elseif (not isHelpful) and shared.highlightOwnDebuffs == true then
            local r, g, b = MSUF_A2_GetOwnDebuffHighlightRGB()
            ShowBorder(r, g, b, 1)
            if icon._msufOwnGlow then
                icon._msufOwnGlow:SetVertexColor(r, g, b, 1)
                icon._msufOwnGlow:Show()
            end
            return
        end
    end

    if allowHighlights ~= true then
        HideBaseBorder()
        return
    end

    -- Buffs: no special border highlight overrides.
    if isHelpful then
        HideBaseBorder()
        return
    end

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



-- Cooldown clearing needs a stricter signal than MSUF_A2_AuraHasExpiration():
-- That helper intentionally treats "unknown" as non-expiring for the Hide-Permanent filter.
-- For cooldown timers, "unknown" must NOT clear, or debuff countdowns can "drop out" on boss/focus.
-- This returns TRUE only when the API explicitly reports a ZERO duration / no-expiration state.
local function MSUF_A2_AuraIsKnownPermanent(unit, aura)
    if not aura then return false end

    local auraInstanceID = aura._msufAuraInstanceID or aura.auraInstanceID
    if not auraInstanceID then
        return false
    end

    -- 1) Explicit API helper (if it reliably reports "no expiration").
    if C_UnitAuras and type(C_UnitAuras.DoesAuraHaveExpirationTime) == "function" then
        local ok, v = pcall(C_UnitAuras.DoesAuraHaveExpirationTime, unit, auraInstanceID)
        if ok then
            local okS, s = pcall(tostring, v)
            if okS and type(s) == "string" then
                if MSUF_A2_StringIsTrue(s) then
                    return false
                end
                local okB1, b1 = pcall(string.byte, s, 1)
                if okB1 and b1 then
                    -- "0"
                    if b1 == 48 then
                        return true
                    end
                    -- "f" / "F" (false)
                    if b1 == 102 or b1 == 70 then
                        return true
                    end
                end
            end
        end
    end

    -- 2) Zero-duration signals via base duration / duration.
    local function TryGetSpellID()
        local raw = nil
        local okRaw = pcall(function()
            raw = aura.spellId or aura.spellID or aura.spellid
        end)
        if not okRaw or raw == nil then
            if C_UnitAuras and type(C_UnitAuras.GetAuraDataByAuraInstanceID) == "function" then
                local okData, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, auraInstanceID)
                if okData and type(data) == "table" then
                    pcall(function()
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

    if C_UnitAuras and type(C_UnitAuras.GetAuraBaseDuration) == "function" then
        local spellID = TryGetSpellID()
        if spellID then
            local okBD, bd = pcall(C_UnitAuras.GetAuraBaseDuration, unit, auraInstanceID, spellID)
            if okBD and bd ~= nil then
                local okS, s = pcall(tostring, bd)
                if okS and MSUF_A2_StringIsZeroNumber(s) then
                    return true
                end
                return false
            end
        end
    end

    if C_UnitAuras and type(C_UnitAuras.GetAuraDuration) == "function" then
        local okD, d = pcall(C_UnitAuras.GetAuraDuration, unit, auraInstanceID)
        if okD and d ~= nil then
            local okS, s = pcall(tostring, d)
            if okS and MSUF_A2_StringIsZeroNumber(s) then
                return true
            end
            return false
        end
    end

    return false
end

-- Cooldown helper (secret-safe): use Duration Objects only (no legacy Remaining* APIs).
local function MSUF_A2_TrySetCooldownFromAura(icon, unit, aura, wantCountdownText)
    if not icon or not icon.cooldown or not aura then return false end

    local auraInstanceID = aura._msufAuraInstanceID or aura.auraInstanceID

    -- Prefer duration objects ONLY (no arithmetic/numeric fallbacks).
    local function TryApplyDurationObject(obj)
        if obj == nil then return false end

        -- Newer APIs
        if type(icon.cooldown.SetCooldownFromDurationObject) == "function" then
            icon.cooldown:SetCooldownFromDurationObject(obj)
            return true
        end
        if type(icon.cooldown.SetTimerDuration) == "function" then
            icon.cooldown:SetTimerDuration(obj)
            return true
        end

        return false
    end


    if C_UnitAuras and type(C_UnitAuras.GetAuraDuration) == "function" then
        local obj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
        if TryApplyDurationObject(obj) then
            -- Cache the Duration Object for the shared manager (no remaining-time arithmetic).
            icon._msufA2_cdDurationObj = obj
            icon.cooldown._msufA2_durationObj = obj

            -- Register this icon for centralized cooldown text color updates.
            -- (Only when countdown numbers are enabled; otherwise skip the manager entirely.)
            if wantCountdownText ~= false then
                MSUF_A2_CooldownTextMgr_RegisterIcon(icon)
            elseif icon._msufA2_cdMgrRegistered == true then
                MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
            end
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

-- Patch 3: make per-icon apply logic more maintainable (no feature regression)
local function MSUF_A2_ApplyIconTextSizing(icon, unit, shared)
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
    if cdFS then
        if icon._msufA2_lastCooldownTextSize ~= cooldownSize then
            local ok = MSUF_A2_ApplyFont(cdFS, fontPath, cooldownSize, fontFlags, useShadow)
            if ok then
                icon._msufA2_lastCooldownTextSize = cooldownSize
            end
        end
        MSUF_A2_ApplyCooldownTextOffsets(icon, unit, shared)
    end
end

local function MSUF_A2_ApplyIconStacks(icon, unit, shared, stackAnchorOverride, forcedDisp, forceHideCooldownNumbers)
    if shared and shared.showStackCount == false then
        if icon.cooldown and icon.cooldown.SetHideCountdownNumbers then
            if icon.cooldown.SetHideCountdownNumbers then icon.cooldown:SetHideCountdownNumbers(false) end
        end
        if icon.count then
            icon.count:SetText("")
            icon.count:Hide()
        end
        icon._msufA2_stackWasShown, icon._msufA2_lastStackDisp = false, nil

        if icon._msufA2_hideCDNumbers == true then
            icon._msufA2_hideCDNumbers = false
            if icon._msufA2_cdMgrRegistered == true then
                MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
            end
        end

        return false
    end

    local stackAnchor = stackAnchorOverride or (shared and shared.stackCountAnchor) or "TOPRIGHT"
    MSUF_A2_ApplyStackCountAnchorStyle(icon, stackAnchor)

    local disp = forcedDisp
    if disp == nil and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount and icon._msufAuraInstanceID then
        disp = C_UnitAuras.GetAuraApplicationDisplayCount(unit, icon._msufAuraInstanceID, 2, 99)
    end

    MSUF_A2_ApplyStackTextOffsets(icon, unit, shared, stackAnchor)

    if disp ~= nil then
        local wantHideNums = (forceHideCooldownNumbers == true)
        if icon._msufA2_hideCDNumbers ~= wantHideNums then
            icon._msufA2_hideCDNumbers = wantHideNums
            if icon.cooldown and icon.cooldown.SetHideCountdownNumbers then
                if icon.cooldown.SetHideCountdownNumbers then icon.cooldown:SetHideCountdownNumbers(wantHideNums) end
            end
            if wantHideNums and icon._msufA2_cdMgrRegistered == true then
                MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
            end
        end

        if icon.count then
            local sr, sg, sb = MSUF_A2_GetStackCountRGB()
            icon.count:SetTextColor(sr, sg, sb, 1)
            icon.count:SetText(tostring(disp))
            icon.count:Show()
        end

        icon._msufA2_stackWasShown, icon._msufA2_lastStackDisp = true, nil
        return true
    end

    if icon._msufA2_stackWasShown == true and InCombatLockdown and InCombatLockdown() then
        return true
    end

if icon._msufA2_hideCDNumbers == true and forceHideCooldownNumbers ~= true then
    icon._msufA2_hideCDNumbers = false
    if icon.cooldown and icon.cooldown.SetHideCountdownNumbers then
        if icon.cooldown.SetHideCountdownNumbers then icon.cooldown:SetHideCountdownNumbers(false) end
    end
end

    if icon.count then
        icon.count:SetText("")
        icon.count:Hide()
    end
    icon._msufA2_stackWasShown, icon._msufA2_lastStackDisp = false, nil
    return false
end

local function MSUF_A2_EffectiveHidePermanent(shared, hidePermanentOverride)
    if hidePermanentOverride ~= nil then
        return (hidePermanentOverride == true)
    end
    -- Prefer the legacy/shared flag first because some UIs still write shared.hidePermanent.
    if shared and shared.hidePermanent ~= nil then
        return (shared.hidePermanent == true)
    end
    local sf = shared and shared.filters
    if sf and sf.hidePermanent ~= nil then
        return (sf.hidePermanent == true)
    end
    return false
end

local function MSUF_A2_ApplyIconCooldown(icon, unit, aura, shared, previewDef)
    if not icon.cooldown then return false end
    icon.cooldown:Show()

    local wantText = not (shared and shared.showCooldownText == false)

    if icon.cooldown.SetHideCountdownNumbers then
        if icon.cooldown.SetHideCountdownNumbers then icon.cooldown:SetHideCountdownNumbers(not wantText) end
    end
    if not wantText and icon._msufA2_cdMgrRegistered == true then
        MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
    end

    local swipeWanted = (shared and shared.showCooldownSwipe and true) or false
    if icon._msufA2_lastSwipeWanted ~= swipeWanted then
        icon._msufA2_lastSwipeWanted = swipeWanted
        if icon.cooldown.SetDrawSwipe then icon.cooldown:SetDrawSwipe(swipeWanted) end
    end

    local reverseWanted = (shared and shared.cooldownSwipeDarkenOnLoss == true) or false
    if icon._msufA2_lastReverseWanted ~= reverseWanted then
        icon._msufA2_lastReverseWanted = reverseWanted
        if icon.cooldown.SetReverse then
            if icon.cooldown.SetReverse then icon.cooldown:SetReverse(reverseWanted) end
        end
    end

    if previewDef ~= nil then
        icon._msufA2_cdDurationObj = nil
        icon.cooldown._msufA2_durationObj = nil
        icon._msufA2_lastCooldownAuraInstanceID = nil
        icon._msufA2_lastHadTimer = nil

        local hadTimer = false
        local isPermanent = (previewDef.permanent == true) or (previewDef.noTimer == true)

        if isPermanent then
            pcall(icon.cooldown.Clear, icon.cooldown)
            pcall(icon.cooldown.SetCooldown, icon.cooldown, 0, 0)
            icon._msufA2_previewCooldownStart = nil
            icon._msufA2_previewCooldownDur = nil
        else
            -- Allow per-preview timing variety (so previews can show both permanent + timed auras).
            local pd = tonumber(previewDef.cdDur or previewDef.cooldownDur or previewDef.duration) or 25
            if pd < 1 then pd = 1 end
            if pd > 36000 then pd = 36000 end

            local elapsed = nil
            if previewDef.cdElapsed ~= nil then
                elapsed = tonumber(previewDef.cdElapsed)
            elseif previewDef.elapsed ~= nil then
                elapsed = tonumber(previewDef.elapsed)
            elseif previewDef.cdRemaining ~= nil then
                local rem = tonumber(previewDef.cdRemaining)
                if rem ~= nil then elapsed = pd - rem end
            end
            if elapsed == nil then elapsed = 10 end
            if elapsed < 0 then elapsed = 0 end
            if elapsed > pd then elapsed = pd * 0.5 end

            local ps = GetTime() - elapsed
            if icon.cooldown.SetCooldown then icon.cooldown:SetCooldown(ps, pd) end
            icon._msufA2_previewCooldownStart = ps
            icon._msufA2_previewCooldownDur = pd
            hadTimer = true
        end

        MSUF_A2_ApplyCooldownTextOffsets(icon, unit, shared)

        if wantText and icon._msufA2_hideCDNumbers ~= true and hadTimer then
            MSUF_A2_CooldownTextMgr_RegisterIcon(icon)
        elseif icon._msufA2_cdMgrRegistered == true then
            MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
        end

        return hadTimer
    end

    local prevAuraID = icon._msufA2_lastCooldownAuraInstanceID
    local prevHadTimer = (icon._msufA2_lastHadTimer == true)

    icon._msufA2_lastCooldownAuraInstanceID = icon._msufAuraInstanceID
    local hadTimer = MSUF_A2_TrySetCooldownFromAura(icon, unit, aura, wantText)
    icon._msufA2_lastHadTimer = hadTimer

    if not hadTimer then
        local sameAura = (prevAuraID ~= nil and prevAuraID == icon._msufAuraInstanceID)
        if MSUF_A2_AuraIsKnownPermanent(unit, aura) or (not sameAura) or (sameAura and not prevHadTimer) then
            pcall(icon.cooldown.Clear, icon.cooldown)
            pcall(icon.cooldown.SetCooldown, icon.cooldown, 0, 0)
        end
    end

    return hadTimer
end

local function MSUF_A2_ApplyIconTooltip(icon, shared)
    local wantTip = (shared and shared.showTooltip == true)

    -- IMPORTANT (Edit Mode QoL): Aura icons must never block dragging the split preview bars.
    -- In Edit Mode, the movers are the interaction surface; icons should be purely visual.
    -- (Tooltips can be re-enabled simply by leaving Edit Mode.)
    if IsEditModeActive and IsEditModeActive() then
        wantTip = false
    end

    icon:EnableMouse((wantTip and true) or false)
end

local function ApplyAuraToIcon(icon, unit, aura, shared, isHelpful, hidePermanentOverride, allowHighlights, isOwn, stackAnchorOverride)
    if not icon or not aura then return end

    icon._msufUnit = unit
    -- Clear preview tooltip metadata (icons are recycled)
    local wasPreview = (icon._msufA2_isPreview == true)
    icon._msufA2_isPreview = nil
    icon._msufA2_previewKind = nil
    if wasPreview then
        -- If preview modified this icon, force a full visual refresh even if auraInstanceID matches prior cache.
        icon._msufA2_lastVisualAuraInstanceID = nil
    end

    icon._msufAuraInstanceID = aura._msufAuraInstanceID or aura.auraInstanceID
    icon._msufSpellId = aura.spellId

    local newFilter = isHelpful and "HELPFUL" or "HARMFUL"
    if icon._msufFilter ~= newFilter then
        icon._msufFilter = newFilter
    end

    -- Texture updates must be secret-safe: only touch when bound auraInstanceID changes.
    local auraInstanceID = icon._msufAuraInstanceID
    if auraInstanceID ~= nil and icon._msufA2_lastVisualAuraInstanceID ~= auraInstanceID then
        icon._msufA2_lastVisualAuraInstanceID = auraInstanceID
        local newTex = aura.icon
        if newTex ~= nil and icon.tex then
            icon.tex:SetTexture(newTex)
        end
    end

    -- Font sizes + per-unit offsets (stack + cooldown text)
    MSUF_A2_ApplyIconTextSizing(icon, unit, shared)

    -- Stacks (may affect countdown number hiding policy)
    MSUF_A2_ApplyIconStacks(icon, unit, shared, stackAnchorOverride)

    -- Hide permanent auras (secret-safe)
    if MSUF_A2_EffectiveHidePermanent(shared, hidePermanentOverride) then
        local hasExpiration = MSUF_A2_AuraHasExpiration(unit, aura)
        if not hasExpiration then
            -- Ensure this icon is not kept alive by the cooldown text manager.
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

    -- Cooldown (secret-safe)
    MSUF_A2_ApplyIconCooldown(icon, unit, aura, shared)

    -- Dispel/Highlight border (secret-safe)
    SetDispelBorder(icon, unit, aura, isHelpful, shared, allowHighlights, isOwn)

    -- Tooltip: scripts are assigned once per icon; we only toggle mouse.
    MSUF_A2_ApplyIconTooltip(icon, shared)

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
    iconSize, buffIconSize, debuffIconSize, spacing, perRow, maxBuffs, maxDebuffs, growth, rowWrap, stackCountAnchor,
    tf, masterOn, onlyBossAuras, showExtraDispellable, finalShowBuffs, finalShowDebuffs)

    local h = 146959

    h = MSUF_A2__HashStep(h, unit)
    h = MSUF_A2__HashStep(h, layoutMode)
    h = MSUF_A2__HashStep(h, buffDebuffAnchor)
    h = MSUF_A2__HashStep(h, growth)
    h = MSUF_A2__HashStep(h, rowWrap)
    h = MSUF_A2__HashStep(h, stackCountAnchor)

    h = MSUF_A2__HashStep(h, iconSize)
    h = MSUF_A2__HashStep(h, buffIconSize)
    h = MSUF_A2__HashStep(h, debuffIconSize)
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
        h = MSUF_A2__HashStep(h, shared.cooldownSwipeDarkenOnLoss)
        h = MSUF_A2__HashStep(h, shared.showTooltip)
        h = MSUF_A2__HashStep(h, shared.highlightOwnBuffs)
        h = MSUF_A2__HashStep(h, shared.highlightOwnDebuffs)
h = MSUF_A2__HashStep(h, shared.hidePermanent)
        h = MSUF_A2__HashStep(h, shared.onlyMyBuffs)
        h = MSUF_A2__HashStep(h, shared.onlyMyDebuffs)
    end

    return h
end

local function MSUF_A2_RefreshAssignedIcons(entry, unit, shared, masterOn, stackCountAnchor, hidePermanentBuffs)
    if not entry or not unit or not shared then return end
    if not C_UnitAuras or type(C_UnitAuras.GetAuraDataByAuraInstanceID) ~= "function" then return end

    local wantOwnHighlights = (shared.highlightOwnBuffs == true) or (shared.highlightOwnDebuffs == true)
    local wantOwnBuff = (shared.highlightOwnBuffs == true) and (shared.showBuffs == true)
    local wantOwnDebuff = (shared.highlightOwnDebuffs == true) and (shared.showDebuffs == true)

    local ownBuffSet, ownDebuffSet = nil, nil
    if wantOwnHighlights and unit ~= "player" then
        if wantOwnBuff then
            ownBuffSet = MSUF_A2_GetPlayerAuraIdSet(unit, "HELPFUL")
        end
        if wantOwnDebuff then
            ownDebuffSet = MSUF_A2_GetPlayerAuraIdSet(unit, "HARMFUL")
        end
    end

    local function IsOwn(isHelpful, aid)
        if not aid then return false end
        local okK, k = pcall(tostring, aid)
        if not okK or not k then return false end
        local set = isHelpful and ownBuffSet or ownDebuffSet
        return (set and set[k]) == true
    end

    -- Re-apply visuals for currently assigned icons without rebuilding lists / changing layout.
    -- This is used for fast refreshes (aura visuals only), so keep it light and avoid allocations.
    local useSingleRow = (entry.mixed ~= nil) and (entry.mixed:IsShown() or false)
    local mixedCount = entry._msufA2_lastMixedCount or 0
    local debuffCount = entry._msufA2_lastDebuffCount or 0
    local buffCount = entry._msufA2_lastBuffCount or 0

    local function RefreshContainer(container, count)
        if not container or count <= 0 then return end
        for idx = 1, count do
            local icon = container.icons and container.icons[idx]
            if icon and icon._msufAuraInstanceID then
                local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, icon._msufAuraInstanceID)
                if aura then
                    local isHelpful = (icon._msufFilter == "HELPFUL")
                    local isOwn = IsOwn(isHelpful, aura and (aura._msufAuraInstanceID or aura.auraInstanceID))
                    -- "Hide permanent" is BUFF-only (HELPFUL). Debuffs must never be hidden by this toggle.
                    local hidePerm = (isHelpful and hidePermanentBuffs == true) and true or false
                    ApplyAuraToIcon(icon, unit, aura, shared, isHelpful, hidePerm, masterOn, isOwn, stackCountAnchor)
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



local MSUF_A2_RENDER_BUDGET = 18

-- ------------------------------------------------------------
-- Auras 2.0 Render helpers (Patch 2): consolidate buff/debuff flow
--  * Reduces duplicate code in RenderUnit()
--  * Avoids per-render table churn where possible
--  * Keeps "hide permanent" BUFF-only behavior consistent (also in fast refresh)
-- ------------------------------------------------------------

local MSUF_A2_EMPTY = {}

local function MSUF_A2_DebuffTypeAllowed(tf, anyDispel, aura)
    if anyDispel ~= true or not tf or not tf.debuffs then return true end
    local d = tf.debuffs

    -- When debuff-type filtering is enabled, "unknown" types are treated as NOT allowed.
    local dtype = MSUF_A2_AuraFieldToString(aura, "dispelName") or MSUF_A2_AuraFieldToString(aura, "dispelType")
    if dtype == nil then
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

local function MSUF_A2_BuildMergedAuraList(entry, unit, filter, baseShow, onlyMine, includeBoss, wantExtra, extraKind)
    if not unit then return MSUF_A2_EMPTY end
    if not baseShow and not wantExtra then
        return MSUF_A2_EMPTY
    end

    local needAll = (wantExtra == true) or (baseShow == true and (onlyMine ~= true or includeBoss == true))
    local allList = nil
    if needAll then
        allList = GetAuraList(unit, filter, false)
    end

    local baseList = MSUF_A2_EMPTY
    if baseShow == true then
        if onlyMine == true then
            if includeBoss == true then
                local mine = GetAuraList(unit, filter, true)
                baseList = MSUF_A2_MergeBossAuras(mine, allList or GetAuraList(unit, filter, false))
            else
                baseList = GetAuraList(unit, filter, true)
            end
        else
            baseList = allList or GetAuraList(unit, filter, false)
        end
    end

    if wantExtra ~= true then
        return baseList
    end

    local all = allList or GetAuraList(unit, filter, false)
    local scratchKey = (filter == "HELPFUL") and "_msufA2_extraScratchBuffs" or "_msufA2_extraScratchDebuffs"
    local scratch = entry[scratchKey]
    if type(scratch) ~= "table" then
        scratch = {}
        entry[scratchKey] = scratch
    end
    wipe(scratch)

    if type(all) == "table" then
        if extraKind == "dispellable" then
            for i = 1, #all do
                local aura = all[i]
                if aura and MSUF_A2_IsDispellableAura(unit, aura) then
                    scratch[#scratch + 1] = aura
                end
            end
        end
    end

    -- Merge into a stable, dedicated list (do not return the scratch table directly).
    return MSUF_A2_MergeAuraLists(scratch, baseList)
end

local function MSUF_A2_RenderFromListBudgeted(ctx, list, startI, cap, isHelpful, hidePermanent)
    if not ctx or not list then return false end

    local entry = ctx.entry
    local unit = ctx.unit
    local shared = ctx.shared
    local st = ctx.st

    local useSingleRow = ctx.useSingleRow == true
    local onlyBossAuras = ctx.onlyBossAuras == true

    local tf = ctx.tf
    local debuffFilterOn = (ctx.anyDispel == true and tf and tf.debuffs) and true or false

    local budget = (type(ctx.budget) == "number") and ctx.budget or 0
    local count = isHelpful and (ctx.buffCount or 0) or (ctx.debuffCount or 0)

    for i = startI, #list do
        if count >= cap then break end
        local aura = list[i]
        if aura then
            if onlyBossAuras and not MSUF_A2_AuraFieldIsTrue(aura, "isBossAura") then
                -- skip
            elseif (not isHelpful) and debuffFilterOn and not MSUF_A2_DebuffTypeAllowed(tf, ctx.anyDispel, aura) then
                -- skip
            else
                if budget <= 0 then
                    ctx.budgetExhausted = true
                    ctx.budget = budget

                    if isHelpful then
                        ctx.buffCount = count
                    else
                        ctx.debuffCount = count
                    end

                    if st then
                        st.pending = true
                        if isHelpful then
                            st.iBuff = i
                            -- Skip debuffs on resume (they were already processed this tick).
                            local dl = ctx.debuffsLen
                            if type(dl) == "number" and dl > 0 then
                                st.iDebuff = dl + 1
                            else
                                st.iDebuff = st.iDebuff or 1
                            end
                        else
                            st.iDebuff = i
                            st.iBuff = 1
                        end
                        st.debuffCount = ctx.debuffCount or 0
                        st.buffCount = ctx.buffCount or 0
                        st.mixedCount = ctx.mixedCount or 0
                    end

                    if type(ctx.ScheduleBudgetContinuation) == "function" then
                        ctx.ScheduleBudgetContinuation(ctx)
                    end
                    return true
                end

                budget = budget - 1

                local container = useSingleRow and entry.mixed or (isHelpful and entry.buffs or entry.debuffs)
                local iconIndex = useSingleRow and ((ctx.mixedCount or 0) + 1) or (count + 1)
                local icon = AcquireIcon(container, iconIndex)

                local isOwn = false
                local ownSet = isHelpful and ctx.ownBuffSet or ctx.ownDebuffSet
                if ownSet then
                    local aid = aura and (aura._msufAuraInstanceID or aura.auraInstanceID)
                    local okK, k = pcall(tostring, aid)
                    if okK and k and ownSet[k] then
                        isOwn = true
                    end
                end

                if ApplyAuraToIcon(icon, unit, aura, shared, isHelpful, hidePermanent, ctx.masterOn == true, isOwn, ctx.stackCountAnchor) then
                    count = count + 1
                    if useSingleRow then
                        ctx.mixedCount = (ctx.mixedCount or 0) + 1
                    end
                end
            end
        end
    end

    if isHelpful then
        ctx.buffCount = count
    else
        ctx.debuffCount = count
    end
    ctx.budget = budget
    return false
end


-- ---------------------------------------------------------------------------
-- Patch 5: RenderUnit cleanup helpers (preview + budget continuation)
--  - Moves preview rendering and budget continuation scheduling out of RenderUnit
--    to reduce per-render closure allocations and improve maintainability.
-- ---------------------------------------------------------------------------

local function MSUF_A2_ScheduleBudgetContinuation(ctx)
    if not ctx then return end
    local entry = ctx.entry
    local renderFunc = ctx.renderFunc
    if not entry or type(renderFunc) ~= "function" then return end
    if entry._msufA2_budgetScheduled then return end
    entry._msufA2_budgetScheduled = true

    C_Timer.After(0, function()
        entry._msufA2_budgetScheduled = false
        local s = entry._msufA2_budgetState
        if not s or s.pending ~= true then return end
        entry._msufA2_budgetResume = true
        renderFunc(entry)
        entry._msufA2_budgetResume = false
    end)
end

local function MSUF_A2_ApplyPreviewIcon(icon, tex, spellId, opts, unit, shared, stackCountAnchor, previewLabelText)
    if not icon then return end

    icon._msufUnit = unit
    icon._msufAuraInstanceID = nil
    icon._msufA2_lastCooldownAuraInstanceID = nil
    icon._msufA2_lastHadTimer = nil
    icon._msufA2_lastVisualAuraInstanceID = nil
    icon._msufSpellId = spellId
    icon._msufFilter = (opts and opts.isHelpful) and "HELPFUL" or "HARMFUL"

    -- Mark as preview so tooltips can describe the fake aura type
    icon._msufA2_isPreview = true
    icon._msufA2_previewKind = (opts and opts.previewKind) or nil
    icon._msufA2_previewLabelText = previewLabelText

    if icon.tex then
        icon.tex:SetTexture(tex)
    end

    -- Apply per-unit text sizes in preview too (stacks + cooldown text).
    MSUF_A2_ApplyIconTextSizing(icon, unit, shared)

    -- Cooldown setup (preview uses synthetic timers, but still shares swipe/text settings + manager).
    if icon.cooldown then
        MSUF_A2_ApplyIconCooldown(icon, unit, nil, shared, opts)
    end

    -- Stack preview (optional). Keep preview cycling fields used by the preview ticker.
    local forcedDisp, forceHideNums = nil, false
    if opts and opts.stackText then
        local curN = tonumber(opts.stackText) or 2
        forcedDisp = curN
        forceHideNums = true

        local maxN = tonumber(opts.stackText)
        if type(maxN) == "number" then
            if maxN < 5 then maxN = 5 end
            icon._msufA2_previewStackMax = maxN
        else
            icon._msufA2_previewStackMax = nil
        end
        icon._msufA2_previewStackCur = icon._msufA2_previewStackCur or curN
    else
        icon._msufA2_previewStackCur = nil
        icon._msufA2_previewStackMax = nil
    end

    -- For preview: apply cooldown first, then stacks can optionally hide countdown numbers (stack demo).
    MSUF_A2_ApplyIconStacks(icon, unit, shared, stackCountAnchor, forcedDisp, forceHideNums)


-- Preview label text (only in Edit Mode previews)
if icon._msufA2_previewLabel then
    local t = previewLabelText
    if (not t or t == "") and opts and opts.previewLabel then
        t = opts.previewLabel
    end
    if t and t ~= "" then
        icon._msufA2_previewLabel:SetText(t)
        icon._msufA2_previewLabel:SetWidth(icon:GetWidth() or 26)
        icon._msufA2_previewLabel:Show()
    else
        icon._msufA2_previewLabel:Hide()
    end
end

    -- Highlights + borders share the live pipeline (preview injects simple override flags).
    local pa = icon._msufA2_previewAura
    if type(pa) ~= "table" then
        pa = {}
        icon._msufA2_previewAura = pa
    end
    pa._msufAuraInstanceID = nil
    pa.auraInstanceID = nil
    pa.spellId = spellId
    pa._msufA2_previewDispellable = false -- dispellable feature removed
    pa._msufA2_previewIsPrivate = (opts and ((opts.isPrivate == true) or (opts.previewKind == "private"))) and true or false

    SetDispelBorder(icon, unit, pa, (icon._msufFilter == "HELPFUL"), shared, true, (opts and (opts.isOwn or opts.own)))
    -- IMPORTANT (Edit Mode QoL): Preview icons must never block dragging the mover bars.
    -- The mover is the interaction surface; preview icons are purely visual.
    icon:EnableMouse(false)

    icon:Show()
end

local function MSUF_A2_RenderPreviewIcons(entry, unit, shared, useSingleRow, buffCap, debuffCap, stackCountAnchor)
    if not entry then return 0, 0 end

    local buffDefs = MSUF_A2_PREVIEW_BUFF_DEFS
    local debuffDefs = MSUF_A2_PREVIEW_DEBUFF_DEFS

    local uLabel = MSUF_A2_PreviewUnitLabel(unit)
    local buffLabel = uLabel .. " Buff"
    local debuffLabel = uLabel .. " Debuff"

    local debuffCount = tonumber(debuffCap) or 0
    if debuffCount < 0 then debuffCount = 0 end
    if debuffCount > 80 then debuffCount = 80 end

    local buffCount = tonumber(buffCap) or 0
    if buffCount < 0 then buffCount = 0 end
    if buffCount > 80 then buffCount = 80 end

    local nDeb = (debuffDefs and #debuffDefs) or 0
    local nBuf = (buffDefs and #buffDefs) or 0
    if nDeb < 1 then nDeb = 1 end
    if nBuf < 1 then nBuf = 1 end

    -- Debuffs first
    for i = 1, debuffCount do
        local def = debuffDefs[((i - 1) % nDeb) + 1]
        local icon = AcquireIcon(useSingleRow and entry.mixed or entry.debuffs, i)
        -- Only label the first icon (avoids text spam when showing many icons).
        local label = (i == 1) and debuffLabel or nil
        MSUF_A2_ApplyPreviewIcon(icon, def.tex, def.spellId, def, unit, shared, stackCountAnchor, label)
    end

    -- Buffs next (append in mixed mode)
    for i = 1, buffCount do
        local def = buffDefs[((i - 1) % nBuf) + 1]
        local idx = useSingleRow and (debuffCount + i) or i
        local icon = AcquireIcon(useSingleRow and entry.mixed or entry.buffs, idx)
        local label = (i == 1) and buffLabel or nil
        MSUF_A2_ApplyPreviewIcon(icon, def.tex, def.spellId, def, unit, shared, stackCountAnchor, label)
    end

    if useSingleRow then
        HideUnused(entry.mixed, (debuffCount + buffCount) + 1)
    else
        HideUnused(entry.debuffs, debuffCount + 1)
        HideUnused(entry.buffs, buffCount + 1)
    end

    return buffCount, debuffCount
end


local function MSUF_A2_RenderPreviewPrivateIcons(entry, unit, shared, privIconSize, spacing, stackCountAnchor)
    if not entry or not entry.private then return 0 end
    -- Target private auras are disabled in MSUF (kept for future-proofing); do not render preview there.
    if unit == "target" then
        HideUnused(entry.private, 1)
        return 0
    end

    local defs = MSUF_A2_PREVIEW_PRIVATE_DEFS
    local uLabel = MSUF_A2_PreviewUnitLabel(unit)

    local maxN = 0
    if type(shared) == "table" then
        local cap = (unit == "player") and shared.privateAuraMaxPlayer or shared.privateAuraMaxOther
        if type(cap) == "number" and cap >= 0 then
            maxN = math.floor(cap)
        end
    end
    if maxN < 0 then maxN = 0 end
    if maxN > 80 then maxN = 80 end

    if type(privIconSize) ~= "number" or privIconSize <= 0 then privIconSize = 26 end
    if type(spacing) ~= "number" then spacing = 2 end

    local nDefs = (defs and #defs) or 0
    if nDefs < 1 then nDefs = 1 end

    local count = maxN
    local prev
    for i = 1, count do
        local def = defs[((i - 1) % nDefs) + 1]
        local icon = AcquireIcon(entry.private, i)
        icon:SetSize(privIconSize, privIconSize)
        icon:ClearAllPoints()
        if not prev then
            icon:SetPoint("BOTTOMLEFT", entry.private, "BOTTOMLEFT", 0, 0)
        else
            icon:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
        end
        prev = icon

        local label = (i == 1) and (uLabel .. " Private") or nil
        MSUF_A2_ApplyPreviewIcon(icon, def.tex, def.spellId, def, unit, shared, stackCountAnchor, label)
    end
    HideUnused(entry.private, count + 1)
    return count
end

local function RenderUnit(entry)
    local rawSig, layoutSig
    local a2, shared = GetAuras2DB()
    -- Cache Masque state for this render pass (used by AcquireIcon without extra DB lookups)
    do
        local st = API and API.state
        if st then
            st._msufA2_masqueShared = shared
            local wantMasque = (Masque_IsEnabled and Masque_IsEnabled(shared)) and true or false
            if st._msufA2_masqueWant ~= wantMasque then
                st._msufA2_masqueWant = wantMasque
                st._msufA2_masqueStamp = (st._msufA2_masqueStamp or 0) + 1
            elseif st._msufA2_masqueStamp == nil then
                st._msufA2_masqueStamp = 0
            end
        end
    end

    if not a2 or not shared or not entry then return end

    local unit = entry.unit
    local wantPreview = (shared.showInEditMode == true) and IsEditModeActive()

    local unitEnabled = UnitEnabled(unit)
    local unitExists = UnitExists and UnitExists(unit)
    local frame = entry.frame or FindUnitFrame(unit)

    -- Preview is ONLY allowed when there is no live unit (or the unit is disabled/hidden).
    -- This prevents preview icons from blocking real auras.
    local showTest = (wantPreview == true) and ((not unitExists) or (not unitEnabled) or (not frame) or (not frame:IsShown()))

    -- Additional Edit Mode quality-of-life:
    -- If the unit exists but has *no* auras at all, allow preview icons so users can position
    -- and see styling without needing to go fish for a buff/debuff.
    if (not showTest) and (wantPreview == true) and unitExists and unitEnabled and frame and frame:IsShown() then
        local hasAny = false
        if C_UnitAuras and type(C_UnitAuras.GetAuraSlots) == "function" then
            local slots = C_UnitAuras.GetAuraSlots(unit, "HELPFUL", 1)
            if type(slots) == "table" and slots[1] then
                hasAny = true
            else
                local slots2 = C_UnitAuras.GetAuraSlots(unit, "HARMFUL", 1)
                if type(slots2) == "table" and slots2[1] then
                    hasAny = true
                end
            end
        end
        if not hasAny then
            showTest = true
        end
    end

    -- In Edit Mode preview, still allow positioning even if this unit's auras are disabled.
    -- Outside preview, respect the unit enable toggle.
    if (not unitEnabled) and (not showTest) then
        if MSUF_A2_PrivateAuras_Clear then MSUF_A2_PrivateAuras_Clear(entry) end
        if entry.anchor then entry.anchor:Hide() end
        MSUF_A2_HideEditMovers(entry)
        return
    end

    if not unitExists and not showTest then
        if MSUF_A2_PrivateAuras_Clear then MSUF_A2_PrivateAuras_Clear(entry) end
        if entry.anchor then entry.anchor:Hide() end
        MSUF_A2_HideEditMovers(entry)
        return
    end

    if (not showTest) and (not frame or not frame:IsShown()) then
        if MSUF_A2_PrivateAuras_Clear then MSUF_A2_PrivateAuras_Clear(entry) end
        if entry.anchor then entry.anchor:Hide() end
        MSUF_A2_HideEditMovers(entry)
        return
    end

    entry = EnsureAttached(unit)
    if not entry or not entry.anchor then return end

    if (not showTest) and entry._msufA2_previewActive == true then
        -- We are about to render real auras; ensure old preview icons are fully cleared first.
        if API and API.ClearPreviewsForEntry then API.ClearPreviewsForEntry(entry) end
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

    if wantPreview then
        if unit == "player" then
            if MSUF_A2_EnsurePlayerEditMovers then MSUF_A2_EnsurePlayerEditMovers(entry) end
        elseif unit == "target" then
            MSUF_A2_EnsureTargetEditMovers(entry)
        elseif unit == "focus" then
            if MSUF_A2_EnsureFocusEditMovers then MSUF_A2_EnsureFocusEditMovers(entry) end
        elseif type(unit) == "string" and unit:match("^boss%d+$") then
            if MSUF_A2_EnsureBossEditMovers then MSUF_A2_EnsureBossEditMovers(entry) end
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

    local isEditModeActive = IsEditModeActive()
    -- In Edit Mode preview (showTest), force a split anchor layout so buff/debuff movers don't collapse
    -- when the saved layout mode is SINGLE.
    local effectiveLayoutMode = layoutMode
    if wantPreview and showTest and layoutMode == "SINGLE" then
        effectiveLayoutMode = "SEPARATE"
    end

    -- Cache for mover-driven refreshes (dragging needs the same override).
    entry._msufA2_editLayoutMode = effectiveLayoutMode
    entry._msufA2_editBuffDebuffAnchor = buffDebuffAnchor
    entry._msufA2_editSplitSpacing = splitSpacing

    UpdateAnchor(entry, shared, offX, offY, boxW, boxH, effectiveLayoutMode, buffDebuffAnchor, splitSpacing, isEditModeActive)
    -- Edit mover visibility: show when Edit Mode is active and Auras2 are enabled.
    -- We keep the mover always created but only visible in Edit Mode.
    if MSUF_A2_AnyEditMover(entry) then
        MSUF_A2_SetEditMoversVisible(entry, isEditModeActive)
    end
    if showTest then
        -- Preview/edit-mode safety: containers are entry.buffs/entry.debuffs/entry.mixed (not *Container)
        entry.anchor:Show()
        if entry.buffs then entry.buffs:Show() end
        if entry.debuffs then entry.debuffs:Show() end
        if entry.mixed then entry.mixed:Show() end
        if entry.private then entry.private:Show() end
    end
    entry.anchor:Show()

    local iconSize, spacing, perRow = MSUF_A2_GetEffectiveSizing(unit, shared)

    -- Independent group icon sizes (Buffs vs Debuffs). Used for SEPARATE layout and signature caching.
    local buffIconSize = MSUF_A2_ResolveNumber(unit, shared, "buffGroupIconSize", iconSize, 10, 80, true)
    local debuffIconSize = MSUF_A2_ResolveNumber(unit, shared, "debuffGroupIconSize", iconSize, 10, 80, true)



-- Private Auras (Blizzard-rendered) anchored to this unitframe.
-- Supports independent icon size via shared/privateSize + per-unit layout override (Edit Mode popup).
local privIconSize = iconSize
if shared and type(shared.privateSize) == "number" then
    privIconSize = shared.privateSize
end
if uconf and uconf.overrideLayout == true and type(uconf.layout) == "table" and type(uconf.layout.privateSize) == "number" then
    privIconSize = uconf.layout.privateSize
end
if type(privIconSize) ~= "number" then privIconSize = iconSize end
if privIconSize < 10 then privIconSize = 10 end
if privIconSize > 80 then privIconSize = 80 end
if MSUF_A2_PrivateAuras_RebuildIfNeeded then
    -- Use the effective layout mode so Edit Mode preview stays split even if the saved mode is SINGLE.
    MSUF_A2_PrivateAuras_RebuildIfNeeded(entry, shared, privIconSize, spacing, effectiveLayoutMode or layoutMode)
end


    -- Separate caps (nice-to-have). Keep legacy maxIcons as fallback.
    local maxDebuffs = (caps and type(caps.maxDebuffs) == "number") and caps.maxDebuffs or shared.maxDebuffs or shared.maxIcons or 12
    local maxBuffs = (caps and type(caps.maxBuffs) == "number") and caps.maxBuffs or shared.maxBuffs or shared.maxIcons or 12

    -- Internal caps used by render loops (legacy variable names expected below).
    local debuffCap = maxDebuffs
    local buffCap = maxBuffs


    local growth = (caps and caps.growth ~= nil) and caps.growth or shared.growth or "RIGHT"
    local rowWrap = (caps and caps.rowWrap ~= nil) and caps.rowWrap or shared.rowWrap or "DOWN"
    local stackCountAnchor = (caps and caps.stackCountAnchor ~= nil) and caps.stackCountAnchor or shared.stackCountAnchor or "TOPRIGHT"

    local useSingleRow = (effectiveLayoutMode == "SINGLE")
    local mixedCount = 0

    local debuffCount = 0
    local buffCount = 0

    local finalShowDebuffs = (shared.showDebuffs == true)
    local finalShowBuffs = (shared.showBuffs == true)
    -- Filter source of truth:
    -- Use shared.filters by default; use per-unit filters only when overrideFilters is enabled for this unit.
    local tf = shared and shared.filters
    do
        local unitKey = unit
        local pu = a2 and a2.perUnit
        if pu and unitKey and pu[unitKey] and pu[unitKey].overrideFilters == true then
            local puf = pu[unitKey].filters
            if puf ~= nil then
                tf = puf
            end
        end
    end

    -- Advanced filter master toggle (when off: behave like legacy toggles only)
    local masterOn = (tf and tf.enabled == true) and true or false
    local onlyBossAuras = (masterOn and tf and tf.onlyBossAuras == true) and true or false

    -- Additive "extras" (advanced filters only)
    local showExtraDispellable = (masterOn and tf and tf.debuffs and tf.debuffs.includeDispellable == true) or false

    local baseShowDebuffs = (shared.showDebuffs == true)
    local baseShowBuffs = (shared.showBuffs == true)

    local wantDebuffs = baseShowDebuffs or showExtraDispellable
    local wantBuffs = baseShowBuffs

    finalShowDebuffs = (wantDebuffs == true)
    finalShowBuffs = (wantBuffs == true)

    -- Effective filter flags (prefer per-unit filter values when present; otherwise fall back to legacy shared toggles)
    local buffsOnlyMine, debuffsOnlyMine = false, false
    local buffsIncludeBoss, debuffsIncludeBoss = false, false
    local hidePermanentBuffs = false

    if masterOn and tf then
        local b = tf.buffs
        local d = tf.debuffs

        if b and b.onlyMine ~= nil then
            buffsOnlyMine = (b.onlyMine == true)
        else
            buffsOnlyMine = (shared.onlyMyBuffs == true)
        end

        if d and d.onlyMine ~= nil then
            debuffsOnlyMine = (d.onlyMine == true)
        else
            debuffsOnlyMine = (shared.onlyMyDebuffs == true)
        end

        buffsIncludeBoss = (b and b.includeBoss == true) or false
        debuffsIncludeBoss = (d and d.includeBoss == true) or false

        if tf.hidePermanent ~= nil then
            hidePermanentBuffs = (tf.hidePermanent == true)
        else
            hidePermanentBuffs = (shared.hidePermanent == true)
        end
    else
        buffsOnlyMine = (shared.onlyMyBuffs == true)
        debuffsOnlyMine = (shared.onlyMyDebuffs == true)
        hidePermanentBuffs = (shared.hidePermanent == true)
    end

    local anyDispel = false
    if masterOn and tf and tf.debuffs then
        local d = tf.debuffs
        anyDispel = (d.dispelMagic == true) or (d.dispelCurse == true) or (d.dispelDisease == true) or (d.dispelPoison == true) or (d.dispelEnrage == true)
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
            st.debuffsLen = nil
            st.buffsLen = nil
        else
            -- Resume from where we left off (counts already applied last tick).
            if st then st.pending = false end
            debuffCount = st.debuffCount or debuffCount
            buffCount = st.buffCount or buffCount
            mixedCount = st.mixedCount or mixedCount
        end

        local budgetExhausted = false

        -- If raw auraInstanceID sets + layout/filter signature are unchanged, avoid expensive list building.
        if not resumeBudget then
            rawSig = MSUF_A2_ComputeRawAuraSig(unit)
            layoutSig = MSUF_A2_ComputeLayoutSig(unit, shared, caps, layoutMode, buffDebuffAnchor, splitSpacing,
                iconSize, buffIconSize, debuffIconSize, spacing, perRow, maxBuffs, maxDebuffs, growth, rowWrap, stackCountAnchor,
                tf, masterOn, onlyBossAuras, showExtraDispellable, finalShowBuffs, finalShowDebuffs)

            if rawSig and layoutSig
               and entry._msufA2_lastRawSig == rawSig
               and entry._msufA2_lastLayoutSig == layoutSig
               and entry._msufA2_lastQuickOK == true
               and type(entry._msufA2_lastBuffCount) == 'number'
               and type(entry._msufA2_lastDebuffCount) == 'number'
            then
                MSUF_A2_RefreshAssignedIcons(entry, unit, shared, masterOn, stackCountAnchor, hidePermanentBuffs)
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
        local ctx = entry._msufA2_renderCtx
        if type(ctx) ~= "table" then ctx = {}; entry._msufA2_renderCtx = ctx end

        local buckets = ctx._buckets
        if type(buckets) ~= "table" then
            buckets = {
                { filter="HARMFUL", kind="dispellable", helpful=false, listKey="debuffs", iKey="iDebuff", lenKey="debuffsLen" },
                { filter="HELPFUL", helpful=true, listKey="buffs", iKey="iBuff", lenKey="buffsLen" },
            }
            ctx._buckets = buckets
        end

        buckets[1].want, buckets[1].base, buckets[1].only, buckets[1].boss, buckets[1].extra, buckets[1].cap, buckets[1].hidePerm =
            wantDebuffs, baseShowDebuffs, debuffsOnlyMine, debuffsIncludeBoss, showExtraDispellable, debuffCap, false
        buckets[2].want, buckets[2].base, buckets[2].only, buckets[2].boss, buckets[2].extra, buckets[2].cap, buckets[2].hidePerm =
            wantBuffs, baseShowBuffs, buffsOnlyMine, buffsIncludeBoss, false, buffCap, (hidePermanentBuffs == true)

        ctx.entry, ctx.unit, ctx.shared, ctx.st, ctx.tf, ctx.anyDispel, ctx.useSingleRow, ctx.onlyBossAuras, ctx.masterOn, ctx.stackCountAnchor, ctx.ownBuffSet, ctx.ownDebuffSet =
            entry, unit, shared, st, tf, anyDispel, (useSingleRow == true), (onlyBossAuras == true), (masterOn == true), stackCountAnchor, ownBuffSet, ownDebuffSet
        ctx.budget, ctx.budgetExhausted, ctx.ScheduleBudgetContinuation, ctx.renderFunc =
            budget, false, MSUF_A2_ScheduleBudgetContinuation, RenderUnit
        ctx.mixedCount, ctx.debuffCount, ctx.buffCount = mixedCount, debuffCount, buffCount

        for bi = 1, 2 do
            local b = buckets[bi]
            if b.want then
                local list, startI = MSUF_A2_EMPTY, 1
                if resumeBudget and st and st[b.listKey] then
                    list = st[b.listKey]
                    startI = (type(st[b.iKey]) == "number") and st[b.iKey] or 1
                else
                    list = MSUF_A2_BuildMergedAuraList(entry, unit, b.filter, b.base, b.only, b.boss, b.extra, b.kind)
                    if st then st[b.listKey] = list end
                end

                local len = (list and #list) or 0
                if st then st[b.lenKey] = len end
                if not b.helpful then ctx.debuffsLen = len end

                MSUF_A2_RenderFromListBudgeted(ctx, list, startI, b.cap, b.helpful, b.hidePerm)
                if ctx.budgetExhausted then break end
            else
                if st then st[b.lenKey] = 0 end
                if bi == 1 then ctx.debuffsLen = 0 end
            end
        end

        budget, budgetExhausted = ctx.budget or budget, (ctx.budgetExhausted == true)
        mixedCount, debuffCount, buffCount = ctx.mixedCount or mixedCount, ctx.debuffCount or debuffCount, ctx.buffCount or buffCount
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
            if entry.private then HideUnused(entry.private, 1); entry.private:Hide() end
            debuffCount = 0
            buffCount = 0
        else
            -- Force both rows visible in preview so users can position/see styling even if they toggled rows off.
            finalShowBuffs = true
            finalShowDebuffs = true

            buffCount, debuffCount = MSUF_A2_RenderPreviewIcons(entry, unit, shared, useSingleRow, buffCap, debuffCap, stackCountAnchor)
            if entry.private then entry.private:Show() end
            MSUF_A2_RenderPreviewPrivateIcons(entry, unit, shared, privIconSize, spacing, stackCountAnchor)
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
            LayoutIcons(entry.debuffs, debuffCount, debuffIconSize, spacing, perRow, growth, rowWrap)
            HideUnused(entry.debuffs, debuffCount + 1)
        else
            HideUnused(entry.debuffs, 1)
        end

        if finalShowBuffs then
            LayoutIcons(entry.buffs, buffCount, buffIconSize, spacing, perRow, growth, rowWrap)
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
    if type(API.perf) ~= "table" then
        API.perf = {
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
    return API.perf
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
    if unit == "player" then return a2.showPlayer == true end
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
            if entry then MSUF_A2_HideEditMovers(entry) end
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
                    if entry then MSUF_A2_HideEditMovers(entry) end

                -- Visibility gate: if the unitframe isn't shown, do zero work (anchor is hidden by OnHide)
                elseif not frame:IsShown() then
                    if entry and entry.anchor then entry.anchor:Hide() end
                    if entry then MSUF_A2_HideEditMovers(entry) end

                else
                    -- Unit existence gate
                    local unitExists = UnitExists and UnitExists(unit)
                    if not unitExists then
                        if entry and entry.anchor then entry.anchor:Hide() end
                        if entry then MSUF_A2_HideEditMovers(entry) end
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



-- Public refresh (used by options)
local function MSUF_A2_RefreshAll()
    -- Settings can change derived cache flags (enabled/showInEditMode/unit enabled).
    -- Rebuild the cache once per user-triggered refresh (NOT in UNIT_AURA hot-path).
    if API and API.DB and API.DB.RebuildCache then
        local a2, s = EnsureDB()
        API.DB.RebuildCache(a2, s)
    end
    local Units = API and API.Units
    if Units and Units.ForEachAll then
        Units.ForEachAll(MarkDirty)
    else
        MarkDirty("player")
        MarkDirty("target")
        MarkDirty("focus")
        for i = 1, 5 do
            MarkDirty("boss" .. i)
        end
    end
    if API and API.UpdatePreviewStackTicker then API.UpdatePreviewStackTicker() end
end



-- Bind aura cooldown/stack texts to the global font pipeline (called from UpdateAllFonts).
local function MSUF_A2_ApplyFontsFromGlobal()
    local _, shared = GetAuras2DB()
    if type(AurasByUnit) ~= "table" then return end

    if type(MSUF_GetGlobalFontSettings) ~= "function" then return end
    local fontPath, fontFlags, _, _, _, _, useShadow = MSUF_GetGlobalFontSettings()

    -- If the user changed the global font color, rebuild the cooldown color curve's "normal" point.
if API and API.InvalidateCooldownTextCurve then
    API.InvalidateCooldownTextCurve()
elseif _G and type(_G.MSUF_A2_InvalidateCooldownTextCurve) == "function" then
    _G.MSUF_A2_InvalidateCooldownTextCurve()
end

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
local function MSUF_A2_RefreshUnit(unit)
    if not unit then return end
    if API and API.DB and API.DB.RebuildCache then
        local a2, s = EnsureDB()
        API.DB.RebuildCache(a2, s)
    end
    MarkDirty(unit)
    if API and API.UpdatePreviewStackTicker then API.UpdatePreviewStackTicker() end
end

-- Public API (reddit-clean)
API.RefreshAll = MSUF_A2_RefreshAll
API.RefreshUnit = MSUF_A2_RefreshUnit
API.ApplyFontsFromGlobal = MSUF_A2_ApplyFontsFromGlobal

if _G and type(_G.MSUF_Auras2_RefreshAll) ~= "function" then
    _G.MSUF_Auras2_RefreshAll = function() return API.RefreshAll() end
end
if _G and type(_G.MSUF_Auras2_RefreshUnit) ~= "function" then
    _G.MSUF_Auras2_RefreshUnit = function(unit) return API.RefreshUnit(unit) end
end
if _G and type(_G.MSUF_Auras2_ApplyFontsFromGlobal) ~= "function" then
    _G.MSUF_Auras2_ApplyFontsFromGlobal = function() return API.ApplyFontsFromGlobal() end
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

-- ------------------------------------------------------------
-- Event driver moved to Auras2\MSUF_A2_Events.lua (Phase 2)
--  * UNIT_AURA helper frames
--  * target/focus/boss change handling
--  * Edit Mode preview refresh + lightweight poll fallback
-- ------------------------------------------------------------


-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- Auras 2.0 split: public bridge for Options module
--  - Logic lives in this file (core)
--  - Options UI lives in MSUF_Options_Auras.lua
-- This table provides a small, stable API so the Options module never depends
-- on file-scope locals defined above.
-- ------------------------------------------------------------
do
    ns = ns or {}
    local API = ns.MSUF_Auras2
    if type(API) ~= "table" then
        API = {}
        ns.MSUF_Auras2 = API
    end
    API.state = (type(API.state) == "table") and API.state or {}
    API.perf  = (type(API.perf)  == "table") and API.perf  or {}

    -- Accessors (used by Options)
    API.GetDB = API.GetDB or GetAuras2DB
    API.EnsureDB = API.EnsureDB or EnsureDB
    API.IsEditModeActive = API.IsEditModeActive or IsEditModeActive
    API.MarkDirty = API.MarkDirty or MarkDirty
    API.Flush = API.Flush or Flush
    API.FindUnitFrame = API.FindUnitFrame or FindUnitFrame

    -- Runtime triggers (used by Options / Fonts / EditMode)
    API.RefreshAll = API.RefreshAll or MSUF_A2_RefreshAll
    API.RefreshUnit = API.RefreshUnit or MSUF_A2_RefreshUnit
API.ApplyFontsFromGlobal = API.ApplyFontsFromGlobal or MSUF_A2_ApplyFontsFromGlobal

-- Internal render helpers for split modules (Preview tickers, etc.)
API._Render = (type(API._Render) == "table") and API._Render or {}
API._Render.ApplyStackCountAnchorStyle = MSUF_A2_ApplyStackCountAnchorStyle
API._Render.ApplyStackTextOffsets = MSUF_A2_ApplyStackTextOffsets
API._Render.ApplyCooldownTextOffsets = MSUF_A2_ApplyCooldownTextOffsets

    local Ev = API.Events
    API.ApplyEventRegistration = API.ApplyEventRegistration or (Ev and Ev.ApplyEventRegistration) or API.ApplyEventRegistration
    API.OnAnyEditModeChanged = API.OnAnyEditModeChanged or (Ev and Ev.OnAnyEditModeChanged) or API.OnAnyEditModeChanged
    API.UpdateEditModePoll = API.UpdateEditModePoll or (Ev and Ev.UpdateEditModePoll) or API.UpdateEditModePoll

    -- Cooldown text helpers
    API.InvalidateCooldownTextCurve = API.InvalidateCooldownTextCurve or MSUF_A2_InvalidateCooldownTextCurve
    API.ForceCooldownTextRecolor = API.ForceCooldownTextRecolor or MSUF_A2_ForceCooldownTextRecolor
    API.InvalidateDB = API.InvalidateDB or MSUF_A2_InvalidateDB

    -- Masque helpers (Options needs these for the toggle + reload popup)
    API.EnsureMasqueGroup = API.EnsureMasqueGroup or _G.MSUF_A2_EnsureMasqueGroup
    API.IsMasqueAddonLoaded = API.IsMasqueAddonLoaded or _G.MSUF_A2_IsMasqueAddonLoaded
    API.IsMasqueReadyForToggle = API.IsMasqueReadyForToggle or _G.MSUF_A2_IsMasqueReadyForToggle
    API.RequestMasqueReskin = API.RequestMasqueReskin or _G.MSUF_A2_RequestMasqueReskin
end


-- Phase 2: init DB cache + event driver now that core exports exist.
if API and API.Init then
    API.Init()
end


-- Private Aura preview toggle helper (shared highlight flag).
-- Used by Edit Mode popup to stay in sync with the Options menu toggle.
if _G and type(_G.MSUF_SetPrivateAuraPreviewEnabled) ~= "function" then
    _G.MSUF_SetPrivateAuraPreviewEnabled = function(enabled)
        if MSUF_DB and MSUF_DB.auras2 and MSUF_DB.auras2.shared then
            MSUF_DB.auras2.shared.highlightPrivateAuras = (enabled and true) or false
        end
        if _G and type(_G.MSUF_Auras2_RefreshAll) == "function" then
            _G.MSUF_Auras2_RefreshAll()
        end
    end
end
