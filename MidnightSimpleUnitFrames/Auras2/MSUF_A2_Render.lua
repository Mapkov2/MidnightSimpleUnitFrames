-- MSUF_A2_Render.lua — Render + Masque + CooldownText (consolidated)

-- MSUF_A2_Render.lua

-- MSUF_A2_Render.lua  Auras 3.0 Orchestrator
-- Replaces the 3357-line monolith.
-- Responsibilities:
--   - Dirty queue + coalesced flush (OnUpdate driver)
--   - RenderUnit: collect  commit  layout (single pass)
--   - Config resolution + caching (cold path, invalidated on DB change)
--   - Private aura anchor management
--   - Edit Mode mover integration
--   - Public API surface (RefreshAll, RefreshUnit, MarkDirty, etc.)
-- NOT in this file: icon creation/visuals (Icons.lua), event wiring (Events.lua)

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
-- PERF LOCALS (Auras2 runtime)
--  - Reduce global table lookups in high-frequency aura pipelines.
--  - Secret-safe: localizing function references only (no value comparisons).
local type, pairs, next = type, pairs, next
local CreateFrame, GetTime = CreateFrame, GetTime
local UnitExists = UnitExists
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local C_UnitAuras = C_UnitAuras

if ns.__MSUF_A2_CORE_LOADED then return end
ns.__MSUF_A2_CORE_LOADED = true

local API = ns.MSUF_Auras2
if type(API) ~= "table" then
    API = {}
    ns.MSUF_Auras2 = API
end
API.state = (type(API.state) == "table") and API.state or {}
API.perf  = (type(API.perf)  == "table") and API.perf  or {}

local A2_STATE = API.state

-- Hot locals
local floor = math.floor
local max = math.max
local tonumber = tonumber

-- Module references (late-bound)
local Icons        -- API.Icons / API.Apply
local Filters      -- API.Filters
local CacheModule  -- API.Cache (v4 delta cache)

-- Combat / Edit Mode state (cheap cached checks)

local _inCombat = false
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_, event)
        local entering = (event == "PLAYER_REGEN_DISABLED")
        _inCombat = entering
        if not entering then
            local fn = API._OnCombatLeave
            if fn then fn() end
        end
    end)
    if InCombatLockdown and InCombatLockdown() then _inCombat = true end
end

local _editModeActive = false
local _editModeCheckAt = 0

local function IsEditModeActive()
    if _inCombat then return false end
    local now = GetTime()
    if now < _editModeCheckAt then return _editModeActive end
    _editModeCheckAt = now + 0.10

    local active = false
    local st = rawget(_G, "MSUF_EditState")
    if st and st.active == true then active = true end
    if not active and rawget(_G, "MSUF_UnitEditModeActive") == true then active = true end
    if not active then
        local fn = rawget(_G, "MSUF_IsInEditMode")
        if type(fn) == "function" then
            -- Direct call (no FastCall overhead). fn() returns boolean.
            local v = fn()
            if v == true then active = true end
        end
    end

    _editModeActive = active
    return active
end

API.IsEditModeActive = IsEditModeActive

-- Force-set the cached edit-mode state (called by Events.OnAnyEditModeChanged
-- to avoid the 100ms stale-cache race that re-enables previews after exit).
local function ForceSetEditModeActive(active)
    _editModeActive = (active == true)
    _editModeCheckAt = GetTime() + 0.10
end
API.ForceSetEditModeActive = ForceSetEditModeActive

-- DB access + config cache

local MSUF_DB

-- DB defaults (copied from original Render  must stay identical for migration compat)
local A2_AURAS2_DEFAULTS = { enabled=true, showTarget=true, showFocus=true, showBoss=true, showPlayer=false, showParty=false, showRaid=false }
local A2_BOSS_HEAL_AURA_DEFAULTS = {
    highlightOwn = false,
    hideOthers = false,
}
local A2_SHARED_DEFAULTS = {
    showBuffs=true, showDebuffs=true, showTooltip=true,
    showCooldownSwipe=true, showCooldownText=true, cooldownSwipeDarkenOnLoss=false,
    showInEditMode=true, showStackCount=true, clickThroughAuras=false,
    stackCountAnchor="TOPRIGHT", masqueEnabled=false, masqueHideBorder=false,
    layoutMode="SEPARATE", buffDebuffAnchor="STACKED", splitSpacing=0,
    highlightPrivatePlayerAuras=false, highlightOwnBuffs=false, highlightOwnDebuffs=false,
    iconSize=26, spacing=2, perRow=12, maxIcons=12,
    growth="RIGHT", rowWrap="DOWN",
    offsetX=0, offsetY=6, buffOffsetY=30,
    stackTextSize=14, cooldownTextSize=14, bossEditTogether=true,
    privateAurasEnabled=true, showPrivateAurasPlayer=true,
    privateAuraMaxPlayer=4,
    showSated=true, satedShowAtSeconds=0,
    ignoreCats={},
    showReminders=true,
    reminders={},
    reminderThreshold=0,
    reminderOffsetX=0,
    reminderOffsetY=0,
    reminderIconSize=22,
    reminderSpacing=2,
    reminderGrowth="RIGHT",
}

local A2_GROWTH_OK = {RIGHT=true,LEFT=true,UP=true,DOWN=true}
local A2_ROWWRAP_OK = {DOWN=true,UP=true}
-- LayoutMode (SINGLE vs SEPARATE) permanently deprecated — runtime always uses separate groups.
local A2_STACKANCHOR_OK = {TOPRIGHT=true,TOPLEFT=true,BOTTOMRIGHT=true,BOTTOMLEFT=true}

-- DefaultKV + Clamp: on API._Render (avoids 200-local limit)
API._Render = API._Render or {}
API._Render.DefaultKV = function(t, d) for k, v in pairs(d) do if t[k] == nil then t[k] = v end end end
API._Render.Clamp = function(v, def, lo, hi) v = tonumber(v); if not v then v = def end; if lo and v < lo then v = lo end; if hi and v > hi then v = hi end; return v end

local function EnsureDB()
    local gdb = _G.MSUF_DB
    if type(gdb) ~= "table" then _G.MSUF_DB = {}; gdb = _G.MSUF_DB end
    if _G.EnsureDB then _G.EnsureDB() end
    MSUF_DB = _G.MSUF_DB
    if not MSUF_DB then return nil end

    if type(MSUF_DB.auras2) ~= "table" then MSUF_DB.auras2 = {} end
    local a2 = MSUF_DB.auras2
    API._Render.DefaultKV(a2, A2_AURAS2_DEFAULTS)
    if type(a2.bossHealAuras) ~= "table" then a2.bossHealAuras = {} end
    API._Render.DefaultKV(a2.bossHealAuras, A2_BOSS_HEAL_AURA_DEFAULTS)

    if type(a2.shared) ~= "table" then a2.shared = {} end
    local s = a2.shared
    API._Render.DefaultKV(s, A2_SHARED_DEFAULTS)

    -- Hard-disable legacy layoutMode behavior (SINGLE/SEPARATE logic).
    -- We keep the stored value for profile compatibility, but the runtime
    -- always uses separate Buff/Debuff containers positioned by movers.
    -- (Fixes login/reload drift caused by growth-direction anchorpoints.)
    s.layoutMode = "SEPARATE"

    if s.maxBuffs == nil then s.maxBuffs = s.maxIcons or 12 end
    if s.maxDebuffs == nil then s.maxDebuffs = s.maxIcons or 12 end
    -- Unit Frames use MSUF custom aura icons. The Blizzard native aura-container
    -- renderer is owned by Group Frames, so strip stale Unit Aura profile keys.
    s.auraRenderer = nil
    s.blizzardAuraTypes = nil
    s.blizzardIconSize = nil
    s.blizzardShowCooldownText = nil
    s.blizzardOrganizationType = nil
    s.blizzardDispelMode = nil
    s.showPrivateAurasTarget = nil
    s.privateAuraMaxTarget = nil
    s.privateAuraMaxPlayer = API._Render.Clamp(s.privateAuraMaxPlayer, 4, 0, 12)
    s.satedShowAtSeconds   = API._Render.Clamp(s.satedShowAtSeconds, 0, 0, 3600)
    -- Per-type growth: sanitize invalid values (nil = fall back to s.growth)
    if s.buffGrowth ~= nil and not A2_GROWTH_OK[s.buffGrowth] then s.buffGrowth = nil end
    if s.debuffGrowth ~= nil and not A2_GROWTH_OK[s.debuffGrowth] then s.debuffGrowth = nil end
    if s.privateGrowth ~= nil and not A2_GROWTH_OK[s.privateGrowth] then s.privateGrowth = nil end

    -- Filters
    Filters = API.Filters
    if Filters and Filters.EnsureSharedFilters then
        Filters.EnsureSharedFilters(a2, s)
    end

    -- Per-unit config
    if type(a2.perUnit) ~= "table" then a2.perUnit = {} end
    for _, pu in pairs(a2.perUnit) do
        if type(pu) == "table" then
            pu.overrideNativeAuras = nil
            pu.nativeAuras = nil
        end
    end

    -- Rebuild DB cache
    local DB = API.DB
    if DB and DB.RebuildCache then DB.RebuildCache(a2, s) end

    return a2, s
end
local _ensureReady = false
local _lastDB = nil

local function GetAuras2DB()
    local gdb = _G.MSUF_DB
    if _ensureReady and gdb == _lastDB and type(gdb) == "table" then
        local a2 = gdb.auras2
        local s = a2 and a2.shared
        if a2 and s then
            MSUF_DB = gdb
            return a2, s
        end
    end
    local a2, s = EnsureDB()
    _ensureReady = true
    _lastDB = MSUF_DB
    return a2, s
end

-- Config invalidation
local _configGen = 0
local _dbFetchGen = -1

local function InvalidateDB()
    _ensureReady = false
    _lastDB = nil
    _configGen = _configGen + 1
    _modulesBound = false  -- re-bind modules on next RenderUnit (picks up late-loaded modules)
    if API.DB and API.DB.InvalidateCache then API.DB.InvalidateCache() end
    if API.Colors and API.Colors.InvalidateCache then API.Colors.InvalidateCache() end
    Icons = API.Icons or API.Apply
    if Icons and Icons.BumpConfigGen then Icons.BumpConfigGen() end
    -- v4: Invalidate delta cache (config change affects filter results)
    local CM = API.Cache
    if CM and CM.InvalidateAll then CM.InvalidateAll() end
    -- Wipe per-entry layout caches so UpdateAnchor re-positions containers
    local aby = A2_STATE.aurasByUnit
    if aby then
        for _, entry in pairs(aby) do
            if entry then entry._msufLayoutCache = nil end
        end
    end
    -- Schedule refresh
    if API.MarkAllDirty then API.MarkAllDirty(0) end
end

API.InvalidateDB = InvalidateDB
API.EnsureDB = EnsureDB
API.GetDB = GetAuras2DB

if type(_G.MSUF_A2_InvalidateDB) ~= "function" then
    _G.MSUF_A2_InvalidateDB = function() return InvalidateDB() end
end

-- Bind EnsureDB into DB module
if API.DB and API.DB.BindEnsure then
    API.DB.BindEnsure(EnsureDB)
end

-- Per-unit state

A2_STATE.aurasByUnit = (type(A2_STATE.aurasByUnit) == "table") and A2_STATE.aurasByUnit or {}
local AurasByUnit = A2_STATE.aurasByUnit

local _IS_BOSS = { boss1=true, boss2=true, boss3=true, boss4=true, boss5=true }
local _IS_PARTY = { party1=true, party2=true, party3=true, party4=true }
local _IS_RAID = {}; for i = 1, 40 do _IS_RAID["raid" .. i] = true end
local _DIR_HASH = { LEFT=1, RIGHT=2, UP=3, DOWN=4 }

-- Phase 8: pre-computed fallback names (eliminates string concat in hot path)
local _FRAME_FALLBACK = {
    player = "MSUF_player", target = "MSUF_target", focus = "MSUF_focus",
    boss1 = "MSUF_boss1", boss2 = "MSUF_boss2", boss3 = "MSUF_boss3",
    boss4 = "MSUF_boss4", boss5 = "MSUF_boss5",
    -- Party/raid frames resolve via MSUF_UnitFrames (registered by GF_Core)
}

local function FindUnitFrame(unit)
    local uf = _G.MSUF_UnitFrames
    if type(uf) == "table" and uf[unit] then return uf[unit] end
    local key = _FRAME_FALLBACK[unit]
    return key and _G[key] or nil
end

API.FindUnitFrame = FindUnitFrame

local function UnitEnabled(a2, unit)
    if not a2 or a2.enabled ~= true then return false end
    if unit == "player" then return a2.showPlayer == true end
    if unit == "target" then return a2.showTarget == true end
    if unit == "focus" then return a2.showFocus == true end
    if _IS_BOSS[unit] then return a2.showBoss == true end
    if _IS_PARTY[unit] then return a2.showParty == true end
    if _IS_RAID[unit] then return a2.showRaid == true end
    return false
end

-- Dirty queue + flush driver

local DirtyA, DirtyB = {}, {}
local DirtyList = DirtyA
local DirtyCount = 0
local DirtyMark = {}
local DirtyGen = 1
local FlushScheduled = false
local _isFlushing = false
local _dirtyWhileFlushing = false

local function DirtyAdd(unit)
    if not unit then return end
    if DirtyMark[unit] == DirtyGen then return end
    DirtyMark[unit] = DirtyGen
    DirtyCount = DirtyCount + 1
    DirtyList[DirtyCount] = unit
    if _isFlushing then _dirtyWhileFlushing = true end
end

local function DirtySwap()
    local list, count = DirtyList, DirtyCount
    DirtyList = (DirtyList == DirtyA) and DirtyB or DirtyA
    DirtyCount = 0
    DirtyGen = DirtyGen + 1
    return list, count
end

local Flush -- forward decl

local _flushDriver = CreateFrame("Frame")
_flushDriver:Hide()
local _flushNextAt = nil
local _flushDriverActive = false   -- PERF: Boolean gate replaces GetScript() C API call

local function StopFlushDriver()
    _flushNextAt = nil
    _flushDriverActive = false
    _flushDriver:SetScript("OnUpdate", nil)
    _flushDriver:Hide()
end

local function FlushDriverOnUpdate()
    local at = _flushNextAt
    if not at then StopFlushDriver(); return end
    local now = GetTime()
    if now >= at then
        _flushNextAt = nil
        if Flush then
            Flush()
        end
    end
end

local function ScheduleFlush(delay)
    if not delay or delay < 0 then delay = 0 end

    if _flushDriverActive then
        -- Driver already running. Only update target time if new delay is sooner.
        if delay == 0 then
            _flushNextAt = 0  -- immediate (next OnUpdate)
        else
            local at = GetTime() + delay
            if not _flushNextAt or at < _flushNextAt then
                _flushNextAt = at
            end
        end
        return
    end

    -- Start driver
    _flushNextAt = (delay == 0) and 0 or (GetTime() + delay)
    _flushDriverActive = true
    _flushDriver:Show()
    _flushDriver:SetScript("OnUpdate", FlushDriverOnUpdate)
end

-- MarkDirty (public entry point for scheduling unit updates)
-- PERF: Inlined DirtyAdd + ScheduleFlush — was 3 function calls, now 0.

local function MarkDirty(unit, delay)
    if not unit then return end

    -- PERF: Single table lookup dedupe (hottest check — runs on every UNIT_AURA)
    if DirtyMark[unit] == DirtyGen then
        if delay == 0 and _flushDriverActive and _flushNextAt and _flushNextAt > 0 then
            _flushNextAt = 0
        end
        return
    end

    -- Inlined DirtyAdd
    DirtyMark[unit] = DirtyGen
    DirtyCount = DirtyCount + 1
    DirtyList[DirtyCount] = unit
    if _isFlushing then _dirtyWhileFlushing = true end

    -- Inlined ScheduleFlush
    if not delay or delay < 0 then delay = 0 end
    FlushScheduled = true
    if _flushDriverActive then
        if delay == 0 then
            _flushNextAt = 0
        else
            local at = GetTime() + delay
            if not _flushNextAt or at < _flushNextAt then
                _flushNextAt = at
            end
        end
    else
        _flushNextAt = (delay == 0) and 0 or (GetTime() + delay)
        _flushDriverActive = true
        _flushDriver:Show()
        _flushDriver:SetScript("OnUpdate", FlushDriverOnUpdate)
    end
end

-- EnsureAttached: create per-unit anchor + container frames

local function EnsureAttached(unit)
    local entry = AurasByUnit[unit]
    local frame = FindUnitFrame(unit)
    if not frame then return nil end

    if entry and entry.frame == frame and entry.anchor and entry.anchor:GetParent() then
        return entry
    end

    -- Clean up old entry
    if entry then
        if entry.anchor then entry.anchor:Hide() end
    end

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

    -- Reminder container (player-only, but create for all — hidden by default)
    local reminder = CreateFrame("Frame", nil, anchor)
    reminder:SetSize(1, 1)
    reminder:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
    reminder:Hide()

    -- Sync visibility with parent unitframe (direct calls - no FastCall overhead)
    -- PERF: Capture unit in closure (set once per EnsureAttached, never changes).
    local _hookUnit = unit
    frame:HookScript("OnShow", function()
        if anchor then anchor:Show() end
        -- Force cache re-scan for THIS unit.  Boss adds can spawn with
        -- pre-existing auras long after the initial INSTANCE_ENCOUNTER_ENGAGE_UNIT
        -- already created an empty cache entry.  Without the invalidation,
        -- FilterAndSort sees the stale empty entry and skips FullScan → 0 auras.
        local Store = API.Store
        if Store and Store.InvalidateUnit then
            Store.InvalidateUnit(_hookUnit)
        end
        -- Targeted dirty (avoids wasteful MarkAllDirty for 8 units).
        if API.MarkDirty then
            API.MarkDirty(_hookUnit, 0)
        end
    end)
    frame:HookScript("OnHide", function()
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
        reminder = reminder,
        -- Reusable list buffers (zero alloc on steady state)
        _buffList = {},
        _debuffList = {},
        -- Last rendered counts for diff
        _lastBuffCount = 0,
        _lastDebuffCount = 0,
    }
    AurasByUnit[unit] = entry
    return entry
end

-- Config resolution (pre-computed per InvalidateDB, not per render)

local function ResolveUnitConfig(unit, a2, shared)
    local iconSize = shared.iconSize or 26
    local spacing = shared.spacing or 2
    local perRow = shared.perRow or 12
    local maxBuffs = shared.maxBuffs or shared.maxIcons or 12
    local maxDebuffs = shared.maxDebuffs or shared.maxIcons or 12
    local growth = shared.growth or "RIGHT"
    local rowWrap = shared.rowWrap or "DOWN"
    local stackCountAnchor = shared.stackCountAnchor or "TOPRIGHT"
    -- Sort order (caps level — per-unit overridable via layoutShared)
    -- Falls back to shared.filters.sortOrder for backward compatibility.
    local sf = shared.filters
    local sortOrder = shared.sortOrder
    if type(sortOrder) ~= "number" then
        sortOrder = (sf and type(sf.sortOrder) == "number") and sf.sortOrder or 0
    end
    -- Per-type growth (nil = fall back to growth)
    local buffGrowth = shared.buffGrowth
    local debuffGrowth = shared.debuffGrowth
    local privateGrowth = shared.privateGrowth
    -- Per-type row wrap (nil = fall back to rowWrap)
    local buffRowWrap = shared.buffRowWrap
    local debuffRowWrap = shared.debuffRowWrap

    -- Per-unit overrides
    local pu = a2.perUnit and a2.perUnit[unit]
    if pu and pu.overrideSharedLayout == true and type(pu.layoutShared) == "table" then
        local ls = pu.layoutShared
        if type(ls.perRow) == "number" and ls.perRow >= 1 then perRow = ls.perRow end
        if type(ls.maxBuffs) == "number" then maxBuffs = ls.maxBuffs end
        if type(ls.maxDebuffs) == "number" then maxDebuffs = ls.maxDebuffs end
        if ls.growth and A2_GROWTH_OK[ls.growth] then growth = ls.growth end
        if ls.buffGrowth and A2_GROWTH_OK[ls.buffGrowth] then buffGrowth = ls.buffGrowth end
        if ls.debuffGrowth and A2_GROWTH_OK[ls.debuffGrowth] then debuffGrowth = ls.debuffGrowth end
        if ls.privateGrowth and A2_GROWTH_OK[ls.privateGrowth] then privateGrowth = ls.privateGrowth end
        if ls.rowWrap and A2_ROWWRAP_OK[ls.rowWrap] then rowWrap = ls.rowWrap end
        if ls.buffRowWrap and A2_ROWWRAP_OK[ls.buffRowWrap] then buffRowWrap = ls.buffRowWrap end
        if ls.debuffRowWrap and A2_ROWWRAP_OK[ls.debuffRowWrap] then debuffRowWrap = ls.debuffRowWrap end
        if ls.stackCountAnchor and A2_STACKANCHOR_OK[ls.stackCountAnchor] then stackCountAnchor = ls.stackCountAnchor end
        if type(ls.sortOrder) == "number" then sortOrder = ls.sortOrder end
    end
    -- Resolve per-type fallback: nil → growth
    if not buffGrowth or not A2_GROWTH_OK[buffGrowth] then buffGrowth = growth end
    if not debuffGrowth or not A2_GROWTH_OK[debuffGrowth] then debuffGrowth = growth end
    if not privateGrowth or not A2_GROWTH_OK[privateGrowth] then privateGrowth = growth end
    -- Resolve per-type rowWrap fallback: nil → rowWrap
    if not buffRowWrap or not A2_ROWWRAP_OK[buffRowWrap] then buffRowWrap = rowWrap end
    if not debuffRowWrap or not A2_ROWWRAP_OK[debuffRowWrap] then debuffRowWrap = rowWrap end

    if pu and pu.overrideLayout == true and type(pu.layout) == "table" then
        local lay = pu.layout
        if type(lay.iconSize) == "number" and lay.iconSize > 1 then iconSize = lay.iconSize end
        if type(lay.spacing) == "number" and lay.spacing >= 0 then spacing = lay.spacing end
    end

-- Group-specific sizing (Edit Mode controls)
local buffIconSize = iconSize
local debuffIconSize = iconSize
local privateIconSize = iconSize

-- Shared defaults (if present)
local bsz = shared.buffGroupIconSize
if type(bsz) == "number" and bsz > 1 then buffIconSize = bsz end
local dsz = shared.debuffGroupIconSize
if type(dsz) == "number" and dsz > 1 then debuffIconSize = dsz end
local psz = shared.privateSize
if type(psz) == "number" and psz > 1 then privateIconSize = psz end

-- Per-unit overrides (only when overrideLayout is enabled)
if pu and pu.overrideLayout == true and type(pu.layout) == "table" then
    local lay = pu.layout
    bsz = lay.buffGroupIconSize
    if type(bsz) == "number" and bsz > 1 then buffIconSize = bsz end
    dsz = lay.debuffGroupIconSize
    if type(dsz) == "number" and dsz > 1 then debuffIconSize = dsz end
    psz = lay.privateSize
    if type(psz) == "number" and psz > 1 then privateIconSize = psz end
end

    return iconSize, spacing, perRow, maxBuffs, maxDebuffs, growth, buffGrowth, debuffGrowth, privateGrowth, rowWrap, buffRowWrap, debuffRowWrap, stackCountAnchor, buffIconSize, debuffIconSize, privateIconSize, sortOrder
end

-- Private Auras (custom slot anchors)

local function PrivateAurasSupported()
    return C_UnitAuras
        and type(C_UnitAuras.AddPrivateAuraAnchor) == "function"
        and type(C_UnitAuras.RemovePrivateAuraAnchor) == "function"
end

API._Render.PrivateAurasShownForUnit = function(shared, unit)
    if not shared or shared.privateAurasEnabled ~= true then return false end
    if unit == "player" then return shared.showPrivateAurasPlayer == true end
    return false
end

API._Render.PrivateAuraMaxForUnit = function(shared, unit)
    if not shared or unit ~= "player" then return 0 end
    return API._Render.Clamp(shared.privateAuraMaxPlayer, 4, 0, 12)
end

local _pendingRemoveIDs

local function _FlushPendingRemoveIDs()
    local ids = _pendingRemoveIDs
    if not ids then return end
    _pendingRemoveIDs = nil
    local removeFn = C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor
    if not removeFn then return end
    for i = 1, #ids do
        if ids[i] then removeFn(ids[i]) end
    end
end

local function PrivateClear(entry)
    if not entry then return end
    local ids = entry._privateAnchorIDs
    if type(ids) == "table" and C_UnitAuras then
        local removeFn = C_UnitAuras.RemovePrivateAuraAnchor
        if removeFn then
            if _inCombat then
                if not _pendingRemoveIDs then _pendingRemoveIDs = {} end
                for i = 1, #ids do
                    if ids[i] then _pendingRemoveIDs[#_pendingRemoveIDs + 1] = ids[i] end
                end
            else
                for i = 1, #ids do
                    if ids[i] then removeFn(ids[i]) end
                end
            end
        end
    end
    entry._privateAnchorIDs = nil
    entry._privUnit = nil
    entry._privToken = nil
    entry._privSize = nil
    entry._privSpacing = nil
    entry._privMax = nil
    entry._privGrowth = nil
    entry._privBorderScale = nil
    entry._privNormalizeQueued = nil
    local slots = entry._privateSlots
    if type(slots) == "table" then
        for i = 1, #slots do if slots[i] then slots[i]:Hide() end end
    end
    if entry.private then entry.private:Hide() end
end

API._Render.ClearNativeAuras = function(entry)
    if not entry then return end

    local container = entry.native
    if container then
        local Native = ns and ns.MSUF_AuraNative
        if Native and type(Native.Clear) == "function" then
            Native.Clear(container)
        else
            local id = container._msufNativeAuraAnchorID
            local removeFn = C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor
            if id and type(removeFn) == "function" then
                pcall(removeFn, id)
            end
            container:Hide()
            container._msufNativeAuraAnchorID = nil
            container._msufNativeAuraSignature = nil
            container._msufNativeAuraUnit = nil
        end
    end
    entry.native = nil

    local containers = entry.nativeContainers
    if containers then
        for key, native in pairs(containers) do
            if native then
                local Native = ns and ns.MSUF_AuraNative
                if Native and type(Native.Clear) == "function" then
                    Native.Clear(native)
                else
                    local id = native._msufNativeAuraAnchorID
                    local removeFn = C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor
                    if id and type(removeFn) == "function" then
                        pcall(removeFn, id)
                    end
                    native:Hide()
                    native._msufNativeAuraAnchorID = nil
                    native._msufNativeAuraSignature = nil
                    native._msufNativeAuraUnit = nil
                end
            end
            containers[key] = nil
        end
    end
    entry.nativeContainers = nil
end

local function PrivateRelaxTexSnap(tex)
    if not tex then return end
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
end

local function NormalizePrivateSlot(slot, privateIconSize)
    if not slot then return end
    privateIconSize = math.floor((tonumber(privateIconSize) or 0) + 0.5)
    if privateIconSize < 1 then privateIconSize = 1 end

    if slot.GetWidth and slot.GetHeight then
        local sw, sh = slot:GetWidth(), slot:GetHeight()
        if sw ~= privateIconSize or sh ~= privateIconSize then
            slot:SetSize(privateIconSize, privateIconSize)
        end
    else
        slot:SetSize(privateIconSize, privateIconSize)
    end

    slot._msufPrivSize = privateIconSize

    local child = select(1, slot:GetChildren())
    if child then
        child:ClearAllPoints()
        child:SetAllPoints(slot)

        if child.Icon then
            child.Icon:ClearAllPoints()
            child.Icon:SetAllPoints(child)
            PrivateRelaxTexSnap(child.Icon)
        end
        if child.Cooldown then
            child.Cooldown:ClearAllPoints()
            child.Cooldown:SetAllPoints(child)
        end
    end
end

local function NormalizePrivateSlots(entry, privateIconSize)
    if not entry then return end
    local slots = entry._privateSlots
    if not slots then return end
    for i = 1, #slots do
        local slot = slots[i]
        if slot and slot:IsShown() then
            NormalizePrivateSlot(slot, privateIconSize)
        end
    end
end

local function QueueNormalizePrivateSlots(entry, privateIconSize)
    if not entry or entry._privNormalizeQueued then return end
    entry._privNormalizeQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if not entry then return end
            entry._privNormalizeQueued = nil
            NormalizePrivateSlots(entry, entry._privSize or privateIconSize)
        end)
    else
        entry._privNormalizeQueued = nil
        NormalizePrivateSlots(entry, privateIconSize)
    end
end

local function PrivateRebuild(entry, shared, privateIconSize, spacing, privateGrowth)
    if not entry or not shared then return end
    local unit = entry.unit

    -- 12.0.1: Private aura anchor APIs blocked in combat.
    -- Keep this to stable unit tokens where the anchor can follow unit changes.
    if not API._Render.PrivateAurasShownForUnit(shared, unit)
       or not PrivateAurasSupported()
    then
        PrivateClear(entry)
        return
    end

    -- Safety net: never call Add/RemovePrivateAuraAnchor in combat.
    if _inCombat then return end

    local maxN = API._Render.PrivateAuraMaxForUnit(shared, unit)
    if maxN == 0 then PrivateClear(entry); return end

    local effectiveToken = unit

    local borderScale = tonumber(shared.privateAuraBorderScale)
    if not borderScale or borderScale < 0 then borderScale = privateIconSize / 10 end

    -- Resolve growth direction
    privateGrowth = (privateGrowth and A2_GROWTH_OK[privateGrowth]) and privateGrowth or "RIGHT"
    local vertical = (privateGrowth == "UP" or privateGrowth == "DOWN")

    -- PERF: Zero-alloc diff check (replaces 6× string concat + comparison)
    if entry._privUnit == unit
       and entry._privToken == effectiveToken
       and entry._privSize == privateIconSize
       and entry._privSpacing == spacing
       and entry._privMax == maxN
       and entry._privGrowth == privateGrowth
       and entry._privBorderScale == borderScale
       and type(entry._privateAnchorIDs) == "table"
    then
        if entry.private then entry.private:Show() end
        NormalizePrivateSlots(entry, privateIconSize)
        return
    end

    PrivateClear(entry)
    if not entry.private then return end

    -- Store fields for next diff check
    entry._privUnit = unit
    entry._privToken = effectiveToken
    entry._privSize = privateIconSize
    entry._privSpacing = spacing
    entry._privMax = maxN
    entry._privGrowth = privateGrowth
    entry._privBorderScale = borderScale

    local slots = entry._privateSlots or {}
    entry._privateSlots = slots
    local step = privateIconSize + spacing
    if step <= 0 then step = 28 end

    entry.private:Show()
    entry._privateAnchorIDs = {}

    -- Container sizing: horizontal = wide row, vertical = tall column
    if vertical then
        entry.private:SetSize(privateIconSize, (maxN * step) - spacing)
    else
        entry.private:SetSize((maxN * step) - spacing, privateIconSize)
    end

    -- Direction + anchor (same logic as Icons.LayoutIcons)
    local anchorX, anchorY = "LEFT", "BOTTOM"
    local dx, dy = 1, 0
    if vertical then
        dx, dy = 0, 1
        if privateGrowth == "DOWN" then
            anchorY = "TOP"
            dy = -1
        end
    else
        if privateGrowth == "LEFT" then
            anchorX = "RIGHT"
            dx = -1
        end
    end
    local anchor = anchorY .. anchorX

    -- Reuse args table (avoid allocation per slot)
    local args = entry._privateArgs
    if not args then
        args = {
            unitToken = effectiveToken,
            auraIndex = 1,
            parent = nil,
            showCountdownFrame = false,
            showCountdownNumbers = false,
            -- 12.0.5 REQUIRED FIELD: isContainer
            -- Without this, AddPrivateAuraAnchor throws:
            --   bad argument #2 to '?' (Current Field: [isContainer])
            -- We use false (same as Plater) → one anchor = one aura index.
            -- isContainer=true is a future path where Blizzard manages the
            -- entire aura list within a single parent frame and (per R41z0r)
            -- displays dispel-type colors natively — but the args shape for
            -- that mode is not yet publicly documented, so we stay with
            -- the slot-per-aura model for now.
            isContainer = false,
            iconInfo = {
                iconWidth = privateIconSize,
                iconHeight = privateIconSize,
                borderScale = borderScale,
                iconAnchor = {
                    point = "CENTER", relativeTo = nil, relativePoint = "CENTER",
                    offsetX = 0, offsetY = 0,
                },
            },
        }
        entry._privateArgs = args
    end

    for i = 1, maxN do
        local slot = slots[i]
        if not slot then
            slot = CreateFrame("Frame", nil, entry.private)
            slot:SetFrameStrata("MEDIUM")
            slot:SetFrameLevel(60)
            if not slot._msufPrivSizeHook then
                slot._msufPrivSizeHook = true
                slot:HookScript("OnSizeChanged", function(self)
                    NormalizePrivateSlot(self, self._msufPrivSize or privateIconSize)
                end)
            end
            slots[i] = slot
        end
        slot:ClearAllPoints()
        local off = (i - 1) * step
        slot:SetPoint(anchor, entry.private, anchor, off * dx, off * dy)
        NormalizePrivateSlot(slot, privateIconSize)
        slot:Show()

        -- Update reused args
        args.unitToken = effectiveToken
        args.auraIndex = i
        args.parent = slot
        args.showCountdownFrame = (shared.showCooldownSwipe == true)
        args.showCountdownNumbers = (shared.showCooldownText == true)
        args.iconInfo.iconWidth = privateIconSize
        args.iconInfo.iconHeight = privateIconSize
        args.iconInfo.borderScale = borderScale
        args.iconInfo.iconAnchor.relativeTo = slot

        local ok, anchorID = true, C_UnitAuras.AddPrivateAuraAnchor(args)
        if ok and anchorID then
            entry._privateAnchorIDs[#entry._privateAnchorIDs + 1] = anchorID
        end
    end

    NormalizePrivateSlots(entry, privateIconSize)
    QueueNormalizePrivateSlots(entry, privateIconSize)
end

-- UpdateAnchor (position the aura container relative to unitframe)

-- File-scope helpers for UpdateAnchor (zero closure alloc)

local _mathFloor = math.floor

-- Read numeric offset from shared/perUnit.layout, clamped to [-2000,2000]
local function ReadOffset(shared, lay, key, def)
    local v = shared[key]
    if lay and lay[key] ~= nil then v = lay[key] end
    v = tonumber(v)
    if v == nil then return def end
    if v < -2000 then return -2000 end
    if v >  2000 then return  2000 end
    return _mathFloor(v + 0.5)
end

-- Position a mover to match its container's anchor point
local function MirrorMover(mover, container, fallbackAnchor, w, h)
    if not mover then return end
    mover:ClearAllPoints()
    if container and container:GetNumPoints() > 0 then
        local p, rel, rp, ox, oy = container:GetPoint(1)
        if p and rel and rp then
            mover:SetPoint(p, rel, rp, ox or 0, oy or 0)
        else
            mover:SetPoint("BOTTOMLEFT", fallbackAnchor, "BOTTOMLEFT", 0, 0)
        end
    else
        mover:SetPoint("BOTTOMLEFT", fallbackAnchor, "BOTTOMLEFT", 0, 0)
    end
    if w and h then mover:SetSize(w, h) end
end

local function UpdateAnchor(entry, shared, isEditActive)
    if not entry or not entry.anchor or not entry.frame or not shared then return end

    local unit = entry.unit
    local offX = shared.offsetX or 0
    local offY = shared.offsetY or 0

    -- Per-unit layout overrides
    local a2 = MSUF_DB and MSUF_DB.auras2
    local pu = a2 and a2.perUnit and a2.perUnit[unit]
    local lay = (pu and pu.overrideLayout == true and type(pu.layout) == "table") and pu.layout or nil
    local ls = (pu and pu.overrideSharedLayout == true and type(pu.layoutShared) == "table") and pu.layoutShared or nil
    local privateGrowth = shared.privateGrowth or shared.growth or "RIGHT"
    if ls and ls.privateGrowth and A2_GROWTH_OK[ls.privateGrowth] then
        privateGrowth = ls.privateGrowth
    elseif not A2_GROWTH_OK[privateGrowth] then
        privateGrowth = (shared.growth and A2_GROWTH_OK[shared.growth]) and shared.growth or "RIGHT"
    end

    if lay then
        if type(lay.offsetX) == "number" then offX = lay.offsetX end
        if type(lay.offsetY) == "number" then offY = lay.offsetY end
    end

    -- Sizing
    local iconSize = shared.iconSize or 26
    local spacing = shared.spacing or 2
    local perRow = shared.perRow or 12
    if lay then
        if type(lay.iconSize) == "number" and lay.iconSize > 1 then iconSize = lay.iconSize end
        if type(lay.spacing) == "number" and lay.spacing >= 0 then spacing = lay.spacing end
    end

-- Group-specific sizing (Edit Mode controls)
local buffIconSize = iconSize
local debuffIconSize = iconSize
local privateIconSize = iconSize

local bsz = shared.buffGroupIconSize
if type(bsz) == "number" and bsz > 1 then buffIconSize = bsz end
local dsz = shared.debuffGroupIconSize
if type(dsz) == "number" and dsz > 1 then debuffIconSize = dsz end
local psz = shared.privateSize
if type(psz) == "number" and psz > 1 then privateIconSize = psz end

if lay then
    bsz = lay.buffGroupIconSize
    if type(bsz) == "number" and bsz > 1 then buffIconSize = bsz end
    dsz = lay.debuffGroupIconSize
    if type(dsz) == "number" and dsz > 1 then debuffIconSize = dsz end
    psz = lay.privateSize
    if type(psz) == "number" and psz > 1 then privateIconSize = psz end
end

    -- Per-group offsets (drag movers write to these)
    local buffDX   = ReadOffset(shared, lay, "buffGroupOffsetX",   0)
    local buffDY   = ReadOffset(shared, lay, "buffGroupOffsetY",   0)
    local debuffDX = ReadOffset(shared, lay, "debuffGroupOffsetX", 0)
    local debuffDY = ReadOffset(shared, lay, "debuffGroupOffsetY", 0)
    local privOffX = ReadOffset(shared, lay, "privateOffsetX",     0)
    local privOffY = ReadOffset(shared, lay, "privateOffsetY",     0)
    local remOffX  = ReadOffset(shared, lay, "reminderOffsetX",    0)
    local remOffY  = ReadOffset(shared, lay, "reminderOffsetY",    0)

    -- PERF: Skip re-anchoring when target-swap refreshes request identical layout.
    -- Cache uses only non-secret DB values + frame identity.
    local layoutCache = entry._msufLayoutCache
    if not layoutCache then
        layoutCache = {}
        entry._msufLayoutCache = layoutCache
    end

    local cacheHit = (layoutCache.frame == entry.frame)
        and (layoutCache.offX == offX and layoutCache.offY == offY)
        and (layoutCache.debuffDX == debuffDX and layoutCache.debuffDY == debuffDY)
        and (layoutCache.buffDX == buffDX and layoutCache.buffDY == buffDY)
        and (layoutCache.privOffX == privOffX and layoutCache.privOffY == privOffY)
        and (layoutCache.remOffX == remOffX and layoutCache.remOffY == remOffY)

    local anchor = entry.anchor
    if not cacheHit then
        layoutCache.frame = entry.frame
        layoutCache.offX, layoutCache.offY = offX, offY
        layoutCache.debuffDX, layoutCache.debuffDY = debuffDX, debuffDY
        layoutCache.buffDX, layoutCache.buffDY = buffDX, buffDY
        layoutCache.privOffX, layoutCache.privOffY = privOffX, privOffY
        layoutCache.remOffX, layoutCache.remOffY = remOffX, remOffY

        -- Position anchor
        anchor:ClearAllPoints()
        anchor:SetPoint("BOTTOMLEFT", entry.frame, "TOPLEFT", offX, offY)

        -- Position containers (always separate groups, always driven by per-group offsets)
        entry.debuffs:ClearAllPoints()
        entry.debuffs:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", debuffDX, debuffDY)

        entry.buffs:ClearAllPoints()
        entry.buffs:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", buffDX, buffDY)

        -- Mixed container is legacy; keep hidden so it can't influence layout/anchors.
        if entry.mixed then
            entry.mixed:ClearAllPoints()
            entry.mixed:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
            entry.mixed:Hide()
        end

        -- Private
        if entry.private then
            entry.private:ClearAllPoints()
            entry.private:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", privOffX, privOffY)
        end

        -- Reminder
        if entry.reminder then
            entry.reminder:ClearAllPoints()
            entry.reminder:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", remOffX, remOffY)
        end
    end

    -- Position edit movers (mirror containers)
    if isEditActive then
        local stepB = buffIconSize + spacing
        local stepD = debuffIconSize + spacing
        local stepP = privateIconSize + spacing
        local maxBuff = (shared.maxBuffs or shared.maxIcons or 12)
        local maxDebuff = (shared.maxDebuffs or shared.maxIcons or 12)
        local cols = (maxBuff < perRow) and maxBuff or perRow
        local dcols = (maxDebuff < perRow) and maxDebuff or perRow
        local headerH = 20

        MirrorMover(entry.editMoverBuff,    entry.buffs,   anchor, cols * stepB,  buffIconSize + headerH)
        MirrorMover(entry.editMoverDebuff,  entry.debuffs, anchor, dcols * stepD, debuffIconSize + headerH)
        if API._Render.PrivateAurasShownForUnit(shared, unit) then
            local privVertical = (privateGrowth == "UP" or privateGrowth == "DOWN")
            local privMax = API._Render.PrivateAuraMaxForUnit(shared, unit)
            if privMax < 1 then privMax = 1 end
            local privW, privH
            if privVertical then
                privW = privateIconSize
                privH = (privMax * stepP) + headerH
            else
                privW = privMax * stepP
                privH = privateIconSize + headerH
            end
            MirrorMover(entry.editMoverPrivate, entry.private, anchor, privW, privH)
        end
        -- Reminder mover (player-only, created by Reminder module)
        if unit == "player" and entry.editMoverReminder and entry.reminder then
            local remIconSz = ReadOffset(shared, lay, "reminderIconSize", 22)
            if remIconSz < 10 then remIconSz = 10 end
            local remSp = ReadOffset(shared, lay, "reminderSpacing", 2)
            if remSp < 0 then remSp = 0 end
            local remGrow = (lay and type(lay.reminderGrowth) == "string" and lay.reminderGrowth)
                         or (shared and type(shared.reminderGrowth) == "string" and shared.reminderGrowth)
                         or "RIGHT"
            local remStep = remIconSz + remSp
            local remW, remH
            if remGrow == "UP" or remGrow == "DOWN" then
                remW = remIconSz
                remH = (9 * remStep) + headerH
            else
                remW = 9 * remStep
                remH = remIconSz + headerH
            end
            MirrorMover(entry.editMoverReminder, entry.reminder, anchor, remW, remH)
        end
    end
end

-- Pre-cached aura unit strings (avoid string concat in loops)
local _BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }
local _AURA_UNITS = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }

local _dirtySeen = {}

local function _ForEachDirtyUnit(includeResidualDisabled, fn)
    if type(fn) ~= "function" then return end

    local DB = API.DB
    local c = DB and DB.cache
    local ue = c and c.unitEnabled

    local seen = _dirtySeen
    for k in pairs(seen) do seen[k] = nil end

    if ue then
        for i = 1, #_AURA_UNITS do
            local unit = _AURA_UNITS[i]
            if ue[unit] == true then
                seen[unit] = true
                fn(unit)
            end
        end
    else
        for i = 1, #_AURA_UNITS do
            local unit = _AURA_UNITS[i]
            seen[unit] = true
            fn(unit)
        end
    end

    -- Disabled units can still need one cleanup render if they have attached state/icons.
    if includeResidualDisabled then
        for unit, entry in pairs(AurasByUnit) do
            if entry and not seen[unit] then
                fn(unit)
            end
        end
    end
end

local _markDirtyDelay = 0
local function _MarkDirtyEachUnit(unit)
    MarkDirty(unit, _markDirtyDelay)
end

local _storeInvalidateEachUnit = nil
local function _InvalidateStoreEachUnit(unit)
    local f = _storeInvalidateEachUnit
    if f then f(unit) end
end

-- Module binding flag (set once, reset only on hard reload)
local _modulesBound = false

-- RenderUnit  the core render loop (single pass, clean)

local function RenderUnit(entry)
    if not entry then return end

    -- Bind modules once
    if not _modulesBound then
        Icons   = API.Icons or API.Apply
        Filters = API.Filters
        CacheModule = API.Cache
        if Icons and CacheModule then _modulesBound = true end
    end

    if not Icons or not CacheModule then return end

    -- Single gen read for entire function (value cannot change mid-call)
    local gen = _configGen

    -- PERF: Cache DB fetch per configGen (avoids repeated GetAuras2DB per unit)
    local a2, shared
    if _dbFetchGen ~= gen then
        _dbFetchGen = gen
        a2, shared = GetAuras2DB()
    end

    local unit = entry.unit
    local isEditActive = (not _inCombat) and IsEditModeActive() or false

    -- Reuse DB from scan-limits path if available, otherwise fetch now
    if not a2 or not shared then
        a2, shared = GetAuras2DB()
    end
    if not a2 or not shared then return end

    -- Unit disabled via options toggle: hide all icons + anchor and bail out.
    -- Edit mode preview bypasses this so movers remain visible for positioning.
    if not UnitEnabled(a2, unit) and not isEditActive then
        Icons.HideUnused(entry.buffs, 1)
        Icons.HideUnused(entry.debuffs, 1)
        if entry.mixed then Icons.HideUnused(entry.mixed, 1) end
        PrivateClear(entry)
        API._Render.ClearNativeAuras(entry)
        if entry.anchor then entry.anchor:Hide() end
        return
    end

    -- Cache resolved config per configGen (eliminates ~40 table reads per aura event)
    local cfg = entry._cfg
    if not cfg then
        cfg = { _gen = -1 }
        entry._cfg = cfg
    end

    if cfg._gen ~= gen then
        cfg._gen = gen
        local pu = a2.perUnit and a2.perUnit[unit]

        -- Layout config
        cfg.iconSize, cfg.spacing, cfg.perRow, cfg.maxBuffs, cfg.maxDebuffs,
        cfg.growth, cfg.buffGrowth, cfg.debuffGrowth, cfg.privateGrowth, cfg.rowWrap, cfg.buffRowWrap, cfg.debuffRowWrap, cfg.stackCountAnchor,
        cfg.buffIconSize, cfg.debuffIconSize, cfg.privateIconSize, cfg.capsSortOrder =
            ResolveUnitConfig(unit, a2, shared)        -- Filter flags
        if Filters and Filters.ResolveRuntimeFlags then
            cfg.tf, cfg.masterOn,
            cfg.onlyBossAuras,
            cfg.onlyImportantBuffs, cfg.onlyImportantDebuffs,
            cfg.buffsOnlyMine, cfg.debuffsOnlyMine,
            cfg.buffsIncludeBoss, cfg.debuffsIncludeBoss,
            cfg.hidePermanentBuffs,
            cfg.sortOrder =
                Filters.ResolveRuntimeFlags(a2, shared, unit)
        else
            cfg.tf = nil
            cfg.masterOn = false
            cfg.onlyBossAuras = false
            cfg.onlyImportantBuffs = false
            cfg.onlyImportantDebuffs = false
            cfg.buffsOnlyMine = false
            cfg.debuffsOnlyMine = false
            cfg.buffsIncludeBoss = false
            cfg.debuffsIncludeBoss = false
            cfg.hidePermanentBuffs = false
            cfg.sortOrder = 0
        end
        -- Sated/Exhaustion filter (reads from shared, independent of master filter toggle)
        cfg.showSated = (shared.showSated ~= false)
        cfg.satedShowAtSeconds = (type(shared.satedShowAtSeconds) == "number") and shared.satedShowAtSeconds or 0
        -- Boss-only healer HoT behavior (global across boss1..boss5).
        cfg.bossHealHighlightOwn = false
        cfg.bossHealHideOthers = false
        if _IS_BOSS[unit] then
            local bha = a2.bossHealAuras
            if type(bha) == "table" then
                cfg.bossHealHighlightOwn = (bha.highlightOwn == true)
                cfg.bossHealHideOthers = (bha.hideOthers == true)
            end
        end
        -- Global Ignore List (reads from shared, per-unit overridable, boss excluded)
        if _IS_BOSS[unit] then
            cfg.ignoreCats = nil
        else
            local cats = shared.ignoreCats
            if pu and pu.overrideIgnore == true and type(pu.ignoreCats) == "table" then
                cats = pu.ignoreCats
            end
            cfg.ignoreCats = (cats) and cats or nil
        end
        -- Display flags
        cfg.showBuffs = (shared.showBuffs == true)
        cfg.showDebuffs = (shared.showDebuffs == true)
    end

    -- Local aliases for hot-path values
    local iconSize          = cfg.iconSize
    local buffIconSize      = cfg.buffIconSize or iconSize
    local debuffIconSize    = cfg.debuffIconSize or iconSize
    local privateIconSize   = cfg.privateIconSize or iconSize
    local spacing           = cfg.spacing
    local perRow            = cfg.perRow
    local maxBuffs          = cfg.maxBuffs
    local maxDebuffs        = cfg.maxDebuffs
    local growth            = cfg.growth
    local buffGrowth        = cfg.buffGrowth or growth
    local debuffGrowth      = cfg.debuffGrowth or growth
    local privateGrowth     = cfg.privateGrowth or growth
    local rowWrap           = cfg.rowWrap
    local buffRowWrap       = cfg.buffRowWrap or rowWrap
    local debuffRowWrap     = cfg.debuffRowWrap or rowWrap
    local stackCountAnchor  = cfg.stackCountAnchor
    local showBuffs         = cfg.showBuffs
    local showDebuffs       = cfg.showDebuffs
    local masterOn          = cfg.masterOn
    local bossHealHighlightOwn = cfg.bossHealHighlightOwn == true

    -- Early bail: no unit, no edit mode  nothing to render
    local unitExists = UnitExists and UnitExists(unit)
    -- PERF: isEditActive already computed at top of function

    if not unitExists and not isEditActive then
        Icons.HideUnused(entry.debuffs, 1)
        Icons.HideUnused(entry.buffs, 1)
        if entry.mixed then Icons.HideUnused(entry.mixed, 1) end
        API._Render.ClearNativeAuras(entry)
        entry.anchor:Hide()
        return
    end

    -- Edit Mode: create movers before anchoring so UpdateAnchor can position them
    local EditMode = isEditActive and API.EditMode or nil
    if EditMode and EditMode.EnsureMovers then
        EditMode.EnsureMovers(entry, unit, shared, iconSize, spacing)
    end
    -- Reminder mover (player-only, created by Reminder module)
    -- PERF: Zero overhead when reminders disabled — no mover creation.
    local ReminderMod = API.Reminder
    if isEditActive and unit == "player" and shared and shared.showReminders ~= false
       and ReminderMod and ReminderMod.EnsureMover then
        ReminderMod.EnsureMover(entry, unit, shared)
    end

    -- Anchor: only reposition when config changes (configGen bumped) or edit mode active
    if gen ~= entry._lastAnchorGen or isEditActive then
        UpdateAnchor(entry, shared, isEditActive)
        entry._lastAnchorGen = gen
    end
    entry.anchor:Show()

    if entry.native or entry.nativeContainers then
        API._Render.ClearNativeAuras(entry)
    end

    -- Private auras keep the dedicated AddPrivateAuraAnchor slot stack. That
    -- path is separate from the Blizzard native buff/debuff container renderer.
    PrivateRebuild(entry, shared, privateIconSize, spacing, privateGrowth)
    entry._lastPrivateGen = gen

    -- Edit Mode: show/hide movers (skip entirely in combat)
    if not _inCombat then
        if EditMode then
            if EditMode.ShowMovers then EditMode.ShowMovers(entry) end
            -- Reminder mover
            if unit == "player" and entry.editMoverReminder then
                entry.editMoverReminder:Show()
            end
        else
            local EM = API.EditMode
            if EM and EM.HideMovers then EM.HideMovers(entry) end
            if entry.editMoverReminder then entry.editMoverReminder:Hide() end
        end
    end

    local showTest = false
    do
        -- PERF: Skip preview entirely in combat (isEditActive is always false)
        if not isEditActive then
            if entry._msufA2_previewActive then
                local Preview = API.Preview
                if Preview and Preview.ClearPreviewsForEntry then
                    Preview.ClearPreviewsForEntry(entry)
                else
                    entry._msufA2_previewActive = nil
                end
                entry._msufA2_playerPreviewInit = nil
            end
        else
        local Preview = API.Preview
        local runPreview = Preview and Preview.RenderEntryPreview
        if runPreview then
            local pv = entry._previewCfg
            if not pv then
                pv = {}
                entry._previewCfg = pv
            end
            pv.maxBuffs = maxBuffs
            pv.maxDebuffs = maxDebuffs
            pv.stackCountAnchor = stackCountAnchor
            pv.buffIconSize = buffIconSize
            pv.debuffIconSize = debuffIconSize
            pv.privateIconSize = privateIconSize
            pv.spacing = spacing
            pv.perRow = perRow
            pv.buffGrowth = buffGrowth
            pv.debuffGrowth = debuffGrowth
            pv.privateGrowth = privateGrowth
            pv.buffRowWrap = buffRowWrap
            pv.debuffRowWrap = debuffRowWrap

            local pvShow, stopLive = runPreview(entry, unit, shared, isEditActive, pv)
            showTest = (pvShow == true)
            if stopLive then return end
        else
            showTest = (shared.showInEditMode == true and isEditActive)
            if not showTest and entry._msufA2_previewActive then
                entry._msufA2_previewActive = nil
                entry._msufA2_playerPreviewInit = nil
            end
        end
    end
    end

    if not unitExists then
        Icons.HideUnused(entry.debuffs, 1)
        Icons.HideUnused(entry.buffs, 1)
        API._Render.ClearNativeAuras(entry)
        entry.anchor:Hide()
        entry._unitExisted = false  -- PERF: Track for fast-path
        return
    end

    -- Collect auras via delta cache (handles both sorted and unsorted)
    -- Secret-safe: plain numeric config, never compared with secret data.

    local buffCount = 0
    local debuffCount = 0

    -- PERF: Local function references eliminate table lookups in hot loops
    local _AcquireIcon = Icons.AcquireIcon
    local _CommitIcon = Icons.CommitIcon

    -- Player in edit mode: debuffs already rendered as preview above, skip real debuff path.
    local skipDebuffs = (showTest and unit == "player")

    -- Pass sortOrder to cache (0 = unsorted fast-path, 1-6 = C++ sorted)
    cfg.sortOrder = cfg.capsSortOrder or cfg.sortOrder or 0

    local _, nB, _, nD = CacheModule.FilterAndSort(unit, cfg, entry._buffList, entry._debuffList)
    local updatedAuraIDs = CacheModule.GetUpdatedAuraIDs and CacheModule.GetUpdatedAuraIDs(unit)

    local customBuffs = showBuffs
    local customDebuffs = showDebuffs

    buffCount  = customBuffs and nB or 0
    debuffCount = (customDebuffs and not skipDebuffs) and nD or 0

    local lastBuffCount = entry._lastBuffCount or 0
    local lastDebuffCount = entry._lastDebuffCount or 0
    local countsChanged = (buffCount ~= lastBuffCount) or (debuffCount ~= lastDebuffCount)
    local commitUpdatedOnly = updatedAuraIDs and entry._lastA2CommitGen == gen and not countsChanged and not isEditActive and not showTest

    -- CommitIcon: debuffs
    -- PERF: Inlined AcquireIcon fast path — pool[i] hit skips function call.
    -- Full AcquireIcon only for pool miss (icon creation, rare after warmup).
    if debuffCount > 0 then
        local list = entry._debuffList
        local container = entry.debuffs
        local pool = container._msufIcons
        if not pool then pool = {}; container._msufIcons = pool end
        if debuffCount > (container._msufA2_activeN or 0) then container._msufA2_activeN = debuffCount end
        for i = 1, debuffCount do
            local aura = list[i]
            if aura then
                local icon = pool[i]
                if icon then
                    if not icon:IsShown() then icon:Show() end
                else
                    icon = _AcquireIcon(container, i)
                    commitUpdatedOnly = false
                end
                local doCommit = not commitUpdatedOnly
                if not doCommit then
                    local aid = aura._msufAuraInstanceID or aura.auraInstanceID
                    doCommit = updatedAuraIDs[aid] == true or not icon._msufA2_lastCommit
                end
                if doCommit then
                    _CommitIcon(icon, unit, aura, shared, false, false, masterOn, aura._msufIsPlayerAura, stackCountAnchor, gen)
                end
            end
        end
    end

    -- CommitIcon: buffs
    if buffCount > 0 then
        local list = entry._buffList
        local container = entry.buffs
        local pool = container._msufIcons
        if not pool then pool = {}; container._msufIcons = pool end
        if buffCount > (container._msufA2_activeN or 0) then container._msufA2_activeN = buffCount end
        for i = 1, buffCount do
            local aura = list[i]
            if aura then
                aura._msufA2_forceBossHealHighlight =
                    (bossHealHighlightOwn and aura._msufA2_isHealerHot == 1 and aura._msufIsPlayerAura == true) or nil
                local icon = pool[i]
                if icon then
                    if not icon:IsShown() then icon:Show() end
                else
                    icon = _AcquireIcon(container, i)
                    commitUpdatedOnly = false
                end
                local doCommit = not commitUpdatedOnly
                if not doCommit then
                    local aid = aura._msufAuraInstanceID or aura.auraInstanceID
                    doCommit = updatedAuraIDs[aid] == true or not icon._msufA2_lastCommit
                end
                if doCommit then
                    _CommitIcon(icon, unit, aura, shared, true, false, masterOn, aura._msufIsPlayerAura, stackCountAnchor, gen)
                end
            end
        end
    end

    -- Layout
    -- PERF: Local function references
    local _LayoutIcons = Icons.LayoutIcons
    local _HideUnused = Icons.HideUnused

    -- SEPARATE (only) layout path
    if skipDebuffs then
        -- Player edit mode: debuff layout already handled by preview path.
    elseif customDebuffs then
        -- Numeric stamp: eliminates 13 string allocs per type per render call.
        local debuffLayoutStamp = debuffCount * 100000007 + debuffIconSize * 10000019 + spacing * 100003 + perRow * 10007 + (_DIR_HASH[debuffGrowth] or 0) * 1009 + (_DIR_HASH[debuffRowWrap] or 0) * 101 + gen
        if entry._msufA2_lastDebuffLayoutStamp ~= debuffLayoutStamp then
            entry._msufA2_lastDebuffLayoutStamp = debuffLayoutStamp
            _LayoutIcons(entry.debuffs, debuffCount, debuffIconSize, spacing, perRow, debuffGrowth, debuffRowWrap, gen)
        end
        if debuffCount ~= lastDebuffCount then
            _HideUnused(entry.debuffs, debuffCount + 1)
        end
    else
        entry._msufA2_lastDebuffLayoutStamp = nil
        if lastDebuffCount > 0 then
            _HideUnused(entry.debuffs, 1)
        end
    end

    if customBuffs then
        local buffLayoutStamp = buffCount * 100000007 + buffIconSize * 10000019 + spacing * 100003 + perRow * 10007 + (_DIR_HASH[buffGrowth] or 0) * 1009 + (_DIR_HASH[buffRowWrap] or 0) * 101 + gen
        if entry._msufA2_lastBuffLayoutStamp ~= buffLayoutStamp then
            entry._msufA2_lastBuffLayoutStamp = buffLayoutStamp
            _LayoutIcons(entry.buffs, buffCount, buffIconSize, spacing, perRow, buffGrowth, buffRowWrap, gen)
        end
        if buffCount ~= lastBuffCount then
            _HideUnused(entry.buffs, buffCount + 1)
        end
    else
        entry._msufA2_lastBuffLayoutStamp = nil
        if lastBuffCount > 0 then
            _HideUnused(entry.buffs, 1)
        end
    end

    if entry.mixed and countsChanged then _HideUnused(entry.mixed, 1) end

    entry._lastBuffCount = buffCount
    entry._lastDebuffCount = debuffCount
    entry._lastA2CommitGen = gen

    if CacheModule.ClearChanged then
        CacheModule.ClearChanged(unit)
    end

    -- Buff Reminders: ghost icons for missing group buffs (player only).
    -- PERF: Zero overhead when disabled or non-player — no function call at all.
    if unit == "player" and shared and shared.showReminders ~= false then
        local ReminderMod = API.Reminder
        if ReminderMod and ReminderMod.Render then
            ReminderMod.Render(entry, unit, shared, buffIconSize, spacing, buffGrowth, showTest)
        end
    end
end

-- Flush

-- PERF: Budget cap for aura flush. Shared with UFCore for combined frame budget.
-- Own cap: 350μs. Shared total: 700μs (UFCore 350 + A2 350 max).
-- In practice UFCore uses 50-200μs → A2 gets 500-650μs on most frames.
-- Spiky frames (UFCore near cap): A2 gets min 150μs = enough for 1 unit.
local _A2_FLUSH_BUDGET_US = 350  -- own cap (microseconds)
local _A2_SHARED_BUDGET_US = 700 -- combined MSUF budget per frame
local _A2_MIN_BUDGET_US = 150    -- minimum budget (always process ≥1 unit)
local _debugprofilestop = debugprofilestop  -- microsecond timer (nil if unavailable)

Flush = function()
    _isFlushing = true
    _dirtyWhileFlushing = false
    FlushScheduled = true

    local list, count = DirtySwap()
    local startUs = _debugprofilestop and _debugprofilestop() or nil

    -- PERF: Shared frame budget with UFCore. Deduct UFCore's usage from our cap.
    local effectiveBudget = _A2_FLUSH_BUDGET_US
    if startUs then
        local ufcoreUsed = _G._MSUF_FrameBudgetUsed
        local ufcoreStart = _G._MSUF_FrameBudgetStart
        -- Only trust if UFCore ran recently (same frame = within ~20ms of us starting)
        if ufcoreUsed and ufcoreStart and (startUs - ufcoreStart) < 20000 then
            local remaining = _A2_SHARED_BUDGET_US - ufcoreUsed
            if remaining < _A2_MIN_BUDGET_US then remaining = _A2_MIN_BUDGET_US end
            if remaining < effectiveBudget then
                effectiveBudget = remaining
            end
        end
    end

    local budgetHit = false
    local clearAuraRescanQueued = API.Events and API.Events._ClearUnitAuraRescanQueued

    for i = 1, count do
        -- PERF: Budget check after each unit (not each aura icon).
        if startUs and i > 1 then
            local elapsed = _debugprofilestop() - startUs
            if elapsed >= effectiveBudget then
                -- Re-queue remaining units for next frame.
                for j = i, count do
                    local u = list[j]
                    if u then MarkDirty(u, 0) end
                end
                budgetHit = true
                break
            end
        end

        local unit = list[i]
        local entry = AurasByUnit[unit]

        -- Fast path: entry already attached with valid frame â†’ skip FindUnitFrame
        if entry and entry.frame then
            RenderUnit(entry)
            if clearAuraRescanQueued then clearAuraRescanQueued(unit) end
        else
            local frame = FindUnitFrame(unit)
            if not frame then
                -- No parent frame at all: just hide anchor if leftover
                if entry and entry.anchor then entry.anchor:Hide() end
                if clearAuraRescanQueued then clearAuraRescanQueued(unit) end
            else
                -- Always let RenderUnit handle both rendering AND cleanup.
                -- UnitEnabled gating lives inside RenderUnit so disabled units
                -- get their icons hidden properly.
                local e = EnsureAttached(unit)
                if e then RenderUnit(e) end
                if clearAuraRescanQueued then clearAuraRescanQueued(unit) end
            end
        end
    end

    _isFlushing = false

    if _dirtyWhileFlushing or budgetHit then
        ScheduleFlush(0)
    end

    if DirtyCount == 0 and not budgetHit then
        FlushScheduled = false
        StopFlushDriver()
    end
end

-- Public API

local function MarkAllDirty(delay)
    -- Mark enabled runtime units plus any attached disabled residual entries.
    _markDirtyDelay = delay
    _ForEachDirtyUnit(true, _MarkDirtyEachUnit)
end

-- Combat-leave guard: tear down + rebuild all private aura anchors.
-- Engine-managed private aura visuals can survive encounter cleanup if the engine
-- fails to remove stale anchor state, leaving ghost icons stuck on frames.
-- Forcing a PrivateClear → MarkAllDirty cycle on PLAYER_REGEN_ENABLED
-- guarantees a clean slate; PrivateRebuild runs on the next RenderUnit pass
-- because _lastPrivateGen was reset.
API._OnCombatLeave = function()
    _FlushPendingRemoveIDs()
    for _, entry in pairs(AurasByUnit) do
        if entry then
            PrivateClear(entry)
            entry._lastPrivateGen = nil
        end
    end
    local Store = API.Store
    if Store and Store.InvalidateUnit then
        _storeInvalidateEachUnit = Store.InvalidateUnit
        _ForEachDirtyUnit(true, _InvalidateStoreEachUnit)
        _storeInvalidateEachUnit = nil
    end
    local CM = API.Cache
    if CM and CM.InvalidateAll then CM.InvalidateAll() end
    MarkAllDirty(0)
end

local function RefreshAll()
    _configGen = _configGen + 1
    if Icons and Icons.BumpConfigGen then Icons.BumpConfigGen() end

    local Store = API.Store
    if Store and Store.InvalidateUnit then
        _storeInvalidateEachUnit = Store.InvalidateUnit
        _ForEachDirtyUnit(true, _InvalidateStoreEachUnit)
        _storeInvalidateEachUnit = nil
    end
    -- v4: Invalidate cache (forces re-filter on next render)
    local CM = API.Cache
    if CM and CM.InvalidateAll then CM.InvalidateAll() end
    MarkAllDirty(0)
end

local function RefreshUnit(unit)
    if not unit then return end
    -- Bump configGen: RefreshUnit is called when per-unit settings change
    -- (caps, layout, filters). Config-dependent gates (anchor, layout, private)
    -- must invalidate so the new values take effect.
    _configGen = _configGen + 1
    Icons = API.Icons or API.Apply
    if Icons and Icons.BumpConfigGen then Icons.BumpConfigGen() end
    local Store = API.Store
    if Store and Store.InvalidateUnit then Store.InvalidateUnit(unit) end
    -- v4: Invalidate cache for this unit (forces re-filter on next render)
    local CM = API.Cache
    if CM and CM.Invalidate then CM.Invalidate(unit) end
    MarkDirty(unit, 0)
end

local function HardDisableAll()
    StopFlushDriver()
    FlushScheduled = false
    DirtyCount = 0
    DirtyGen = DirtyGen + 1

    for _, entry in pairs(AurasByUnit) do
        if entry then
            if entry.anchor then entry.anchor:Hide() end
            PrivateClear(entry)
            Icons = API.Icons or API.Apply
            if Icons then
                Icons.HideUnused(entry.buffs, 1)
                Icons.HideUnused(entry.debuffs, 1)
                Icons.HideUnused(entry.mixed, 1)
            end
        end
    end
end

API._ClearUnitAuraContainerVisualState = function(container)
    if not container then return end

    Icons = API.Icons or API.Apply
    if Icons and Icons.HideUnused then
        Icons.HideUnused(container, 1)
    end

    local pool = container._msufIcons
    if not pool then
        container._msufA2_activeN = 0
        container._msufA2_lastLayoutN = nil
        return
    end

    local map = container._msufA2_iconByAid
    if map then
        for aid in pairs(map) do
            map[aid] = nil
        end
    end

    for i = 1, #pool do
        local icon = pool[i]
        if icon then
            icon._msufAuraInstanceID = nil
            icon._msufAura = nil
            icon._msufA2_lastTexAid = nil
            icon._msufA2_lastOwnHelpful = nil
            icon._msufA2_lastDispelAid = nil
            icon._msufA2_forceOwnBuffHighlight = nil

            local lc = icon._msufA2_lastCommit
            if lc then
                lc.aid = nil
                lc.gen = nil
                lc.isOwn = nil
                lc.forceOwnBuffHighlight = nil
            end

            if icon._msufDispelBorder then icon._msufDispelBorder:Hide() end
            if icon._msufPandemic then icon._msufPandemic:Hide() end
            if icon:IsShown() then icon:Hide() end
        end
    end

    container._msufA2_activeN = 0
    container._msufA2_lastLayoutN = nil
end

API.ClearUnitVisualState = function(unit)
    local entry = AurasByUnit and AurasByUnit[unit]
    if not entry then return end

    local clearContainer = API._ClearUnitAuraContainerVisualState
    if clearContainer then
        clearContainer(entry.buffs)
        clearContainer(entry.debuffs)
        clearContainer(entry.mixed)
    end

    entry._lastBuffCount = 0
    entry._lastDebuffCount = 0
    entry._msufA2_lastBuffLayoutStamp = nil
    entry._msufA2_lastDebuffLayoutStamp = nil

    local list = entry._buffList
    if list then
        for i = 1, (list._msufA2_n or #list) do list[i] = nil end
        list._msufA2_n = 0
    end

    list = entry._debuffList
    if list then
        for i = 1, (list._msufA2_n or #list) do list[i] = nil end
        list._msufA2_n = 0
    end
end

-- ClearAllPreviews (called by Events when leaving Edit Mode)

-- Helper: clear preview state from a single container (file-scope, no closure alloc)
local function _ClearPreviewContainer(container)
    if not container then return end
    local pool = container._msufIcons
    if not pool then return end
    for i = 1, #pool do
        local icon = pool[i]
        if icon and icon._msufA2_isPreview then
            icon._msufA2_isPreview = nil
            icon._msufA2_previewKind = nil
            icon._msufA2_previewCDCounter = nil
            icon._msufA2_lastCommit = nil
            icon._msufA2_lastTexAid = nil
            -- Hide preview CD text FontString so it doesn't bleed into real auras.
            local pvFS = icon._msufA2_previewCDText
            if pvFS then
                pvFS:Hide()
                pvFS:SetText("")
            end
            icon:Hide()
        end
    end
end

local function ClearAllPreviews()
    Icons = API.Icons or API.Apply
    if not Icons then return end

    -- Prefer Preview module's thorough cleanup (unreg from CD manager,
    -- clear duration objects, visual ID caches, preview CD FontStrings).
    local Preview = API.Preview
    local deepClean = Preview and Preview.ClearPreviewsForEntry

    for _, entry in pairs(AurasByUnit) do
        if entry then
            if deepClean then
                deepClean(entry)
            else
                _ClearPreviewContainer(entry.buffs)
                _ClearPreviewContainer(entry.debuffs)
                _ClearPreviewContainer(entry.mixed)
                _ClearPreviewContainer(entry.private)
                entry._msufA2_previewActive = nil
            end
            entry._msufA2_playerPreviewInit = nil
        end
    end

    -- Bug 2 fix: Force Masque reskin after clearing previews.
    -- Preview icons modified cooldown/texture state that Masque skins
    -- (e.g. Shadow) track internally. Without a reskin, stale overlay
    -- state causes icons to appear very dark.
    local MasqueMod = API.Masque
    if MasqueMod and MasqueMod.ForceReskin then
        MasqueMod.ForceReskin()
    end
end

API.ClearAllPreviews = ClearAllPreviews

-- Register on API
API.MarkDirty = MarkDirty
API.MarkAllDirty = MarkAllDirty
API.RefreshAll = RefreshAll
API.RefreshUnit = RefreshUnit
API.RequestUnit = MarkDirty
API.HardDisableAll = HardDisableAll
API.Flush = Flush

-- RequestApply: called by Options after any settings change (checkboxes, sliders, etc.)
-- Must bump configGen so CommitIcon diff-gate triggers a full re-apply (highlights, timers, etc.)
API.RequestApply = function()
    InvalidateDB()
end

-- Global wrappers for backward compat
_G.MSUF_Auras2_RefreshAll = function() return API.RefreshAll() end
_G.MSUF_Auras2_RefreshUnit = function(unit) return API.RefreshUnit(unit) end
_G.MSUF_A2_RequestUnit = function(unit, delay) return API.RequestUnit(unit, delay) end
_G.MSUF_A2_HardDisableAll = function() return API.HardDisableAll() end
_G.MSUF_UpdateTargetAuras = function() MarkDirty("target") end
-- Range fade propagation: returns the top-level aura anchor for a unit (or nil).
_G.MSUF_A2_GetUnitAnchor = function(unit)
    local entry = AurasByUnit[unit]
    return entry and entry.anchor or nil
end


-- Init: prime DB + kick off events

-- API bridge for Options / EditMode / Fonts

API._Render = API._Render or {}

-- UpdateUnitAnchor: immediate re-anchor for a single unit (used by EditMode drag for instant feedback)
API.UpdateUnitAnchor = function(unit)
    if not unit then return end
    local entry = AurasByUnit[unit]
    if not entry then return end
    local a2, shared = GetAuras2DB()
    if shared then UpdateAnchor(entry, shared, (not _inCombat) and IsEditModeActive() or false) end
end

API.ApplyEventRegistration = API.ApplyEventRegistration or function()
    local Ev = API.Events
    if Ev and Ev.ApplyEventRegistration then return Ev.ApplyEventRegistration() end
end

function API.Init()
    if API._renderInited then return end
    API._renderInited = true

    -- Prime DB so all caches are warm
    EnsureDB()

    -- If Events module is already loaded, initialize it
    local Ev = API.Events
    if Ev and Ev.Init then
        Ev.Init()
    end

-- IMPORTANT: On /reload, Auras2 can initialize before MSUF core has fully
-- hydrated SavedVariables (or before some modules finish their first Apply).
-- That can cause the initial anchor placement to use default offsets until
-- Edit Mode forces a re-anchor.
-- Fix: one-shot post-init invalidate on the next tick so we re-read the
-- final DB state and force UpdateAnchor to run with the correct offsets.
if not API._didPostInitInvalidate then
    API._didPostInitInvalidate = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            InvalidateDB()
        end)
    else
        InvalidateDB()
    end
end
end

-- Deferred auto-init: if Events already loaded, Init now; otherwise Events.lua calls API.Init() at its tail
if API.Events and API.Events.Init then
    API.Init()
end

-- MSUF_A2_Masque.lua

-- MSUF Auras 2.0 - Masque integration (optional)
-- Isolated here so Render remains Masque-agnostic.
-- This module intentionally keeps legacy globals used by Options (compat / no-regression).

local addonName, ns = ...

local type = type
local C_Timer = C_Timer

-- MSUF: Max-perf Auras2: replace protected calls (pcall) with direct calls.
-- NOTE: this removes error-catching; any error will propagate.
local function MSUF_A2_FastCall(fn, ...)
    return true, fn(...)
end

local API = ns and ns.MSUF_Auras2
if not API then  return end

API.Masque = API.Masque or {}
local MasqueMod = API.Masque

local _G = _G
local LibStub = _G.LibStub
local C_AddOns = _G.C_AddOns

local MSQ_LIB = nil
local MSQ_GROUP = nil
local RESKIN_QUEUED = false
local _masqueButtonCount = 0  -- Track registered button count for structural-change-only reskin

-- Load / group helpers

local function IsMasqueLoaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded("Masque") == true
    end
    if _G.IsAddOnLoaded then
        return _G.IsAddOnLoaded("Masque") == true
    end
     return false
end

local function GetMasqueLib()
    if MSQ_LIB ~= nil then  return MSQ_LIB end
    if not LibStub then MSQ_LIB = false;  return nil end
    local ok, lib = MSUF_A2_FastCall(LibStub, "Masque", true)
    if ok and lib then
        MSQ_LIB = lib
         return MSQ_LIB
    end
    MSQ_LIB = false
     return nil
end

local function EnsureMasqueGroup()
    if MSQ_GROUP then
        _G.MSUF_MasqueAuras2 = MSQ_GROUP -- legacy global for Options
         return MSQ_GROUP
    end

    if not IsMasqueLoaded() then  return nil end

    local lib = GetMasqueLib()
    if not lib then  return nil end

    local ok, group = MSUF_A2_FastCall(lib.Group, lib, "Midnight Simple Unit Frames", "Auras 2.0")
    if ok and group then
        MSQ_GROUP = group
        _G.MSUF_MasqueAuras2 = MSQ_GROUP -- legacy global for Options
         return MSQ_GROUP
    end

     return nil
end

-- Reload popup (legacy UX used by Options)

local function EnsureReloadPopup()
    if not _G.StaticPopupDialogs then  return end

    local function DoReload()
        if _G.InCombatLockdown and _G.InCombatLockdown() then
            print("|cffff5555MSUF|r: Can't reload UI in combat. Leave combat, then type /reload.")
            return
        end
        if _G.ReloadUI then _G.ReloadUI() end
    end

    local function MakeDialog(dialogKey, text, prevGlobalKey, cbGlobalKey, sharedField)
        if _G.StaticPopupDialogs[dialogKey] then return end
        _G.StaticPopupDialogs[dialogKey] = {
            text = text,
            button1 = "Reload UI",
            button2 = "Cancel",
            OnAccept = DoReload,
            OnCancel = function()
                local prev = _G[prevGlobalKey]
                local cb = _G[cbGlobalKey]
                if type(prev) == "boolean" and API.DB and API.DB.Ensure then
                    local _, shared = API.DB.Ensure()
                    if shared then shared[sharedField] = prev end
                end
                if cb and cb.SetChecked and type(prev) == "boolean" then cb:SetChecked(prev) end
                _G[cbGlobalKey] = nil
                _G[prevGlobalKey] = nil
            end,
            timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
        }
    end

    MakeDialog("MSUF_A2_RELOAD_MASQUE",
        "Masque changes require a UI reload.",
        "MSUF_A2_MASQUE_RELOAD_PREV", "MSUF_A2_MASQUE_RELOAD_CB", "masqueEnabled")

    MakeDialog("MSUF_A2_RELOAD_MASQUE_BORDER",
        "Masque border changes require a UI reload.",
        "MSUF_A2_MASQUE_BORDER_RELOAD_PREV", "MSUF_A2_MASQUE_BORDER_RELOAD_CB", "masqueHideBorder")
end

-- Ensure dialog exists early so Options can call StaticPopup_Show("MSUF_A2_RELOAD_MASQUE") directly.
EnsureReloadPopup()

-- Overlay sync + border detection (Masque-safe)

local function SyncIconOverlayLevels(icon)
    if not icon then  return end

    -- One-time sync after Masque registration: ensure MSUF overlays
    -- (countFrame, dispel border) sit above any Masque skin layers.
    local base = (icon.GetFrameLevel and icon:GetFrameLevel()) or 0
    if icon.cooldown and icon.cooldown.GetFrameLevel then
        local lvl = icon.cooldown:GetFrameLevel() or 0
        if lvl > base then base = lvl end
    end

    -- countFrame (stack count overlay)
    if icon.countFrame and icon.countFrame.SetFrameLevel then
        icon.countFrame:SetFrameLevel(base + 10)
    end
 end

local function SkinHasBorder(btn)
    -- No Border region passed to Masque (MSA pattern), so Masque never renders borders.
     return false
end

-- Regions + registration (MSA pattern: Icon/Cooldown/Count only, no Normal/Border)

local function EnsureMasqueRegions(btn)
    if not btn then  return end

    if not btn._msufMasqueRegions then
        btn._msufMasqueRegions = {}
    end

    local r = btn._msufMasqueRegions
    -- Map MSUF field names to Masque-expected keys
    -- Icon + Cooldown ONLY.  Count is managed exclusively by _ApplyStacks;
    -- passing it to Masque lets ReSkin overwrite anchor/position, breaking
    -- the user's stack-count anchor setting.
    r.Icon     = btn.tex
    r.Cooldown = btn.cooldown
    r.Count    = nil   -- explicit nil: clear stale ref from recycled buttons
    -- No Count/Normal/Border: Masque only skins icon appearance + cooldown.
 end

local _lastReskinCount = -1  -- Count at last ReSkin; -1 forces initial reskin

local function ReskinNow()
    RESKIN_QUEUED = false
    local g = MSQ_GROUP or _G.MSUF_MasqueAuras2
    if not g then  return end

    -- Skip ReSkin if button count hasn't changed since last reskin
    -- (icon textures/cooldowns don't need it, only structural adds/removes)
    if _masqueButtonCount == _lastReskinCount then  return end
    _lastReskinCount = _masqueButtonCount

    -- Masque uses ReSkin() (case varies across versions / forks)
    if g.ReSkin then
        MSUF_A2_FastCall(g.ReSkin, g)
    elseif g.Reskin then
        MSUF_A2_FastCall(g.Reskin, g)
    elseif g.ReSkinAllButtons then
        MSUF_A2_FastCall(g.ReSkinAllButtons, g)
    end
 end

local function RequestReskin()
    if RESKIN_QUEUED then  return end
    RESKIN_QUEUED = true
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, ReskinNow)
    else
        -- Fallback: run immediately
        ReskinNow()
    end
 end

local function AddButton(btn, shared)
    if not btn then  return false end
    if not (shared and shared.masqueEnabled == true) then
         return false
    end

    local g = EnsureMasqueGroup()
    if not g then  return false end

    EnsureMasqueRegions(btn)

    if btn.MSUF_MasqueAdded == true then
         return true
    end

    local ok = MSUF_A2_FastCall(g.AddButton, g, btn, btn._msufMasqueRegions)
    if ok then
        btn.MSUF_MasqueAdded = true
        _masqueButtonCount = _masqueButtonCount + 1
        -- One-time overlay sync: keep countFrame above Masque layers
        SyncIconOverlayLevels(btn)
        RequestReskin()
         return true
    end

    btn.MSUF_MasqueAdded = false
     return false
end

local function RemoveButton(btn)
    if not btn then  return end
    local g = MSQ_GROUP or _G.MSUF_MasqueAuras2
    if not g then
        btn.MSUF_MasqueAdded = false
         return
    end
    if btn.MSUF_MasqueAdded == true then
        MSUF_A2_FastCall(g.RemoveButton, g, btn)
        btn.MSUF_MasqueAdded = false
        _masqueButtonCount = _masqueButtonCount > 0 and (_masqueButtonCount - 1) or 0
        RequestReskin()
    end
 end

local function IsEnabled(shared)
    if not (shared and shared.masqueEnabled == true) then  return false end
    return EnsureMasqueGroup() ~= nil
end

local function IsReadyForToggle(cb, prevValue)
    EnsureReloadPopup()
    _G.MSUF_A2_MASQUE_RELOAD_CB = cb
    _G.MSUF_A2_MASQUE_RELOAD_PREV = prevValue
    if _G.StaticPopup_Show then
        _G.StaticPopup_Show("MSUF_A2_RELOAD_MASQUE")
    end
     return false
end

-- Public module API

MasqueMod.IsAddonLoaded = IsMasqueLoaded
MasqueMod.EnsureGroup = EnsureMasqueGroup
MasqueMod.IsEnabled = IsEnabled
MasqueMod.PrepareButton = EnsureMasqueRegions
MasqueMod.AddButton = AddButton
MasqueMod.RemoveButton = RemoveButton
MasqueMod.RequestReskin = RequestReskin
MasqueMod.ForceReskin = function()
    -- Explicit skin change: bypass count guard
    _lastReskinCount = -1
    RequestReskin()
end
MasqueMod.SyncIconOverlayLevels = SyncIconOverlayLevels
MasqueMod.SkinHasBorder = SkinHasBorder
MasqueMod.IsReadyForToggle = IsReadyForToggle

-- Legacy globals (Options expects these)

_G.MSUF_A2_IsMasqueAddonLoaded = IsMasqueLoaded
_G.MSUF_A2_EnsureMasqueGroup = function()
    EnsureReloadPopup()
    return EnsureMasqueGroup()
end
_G.MSUF_A2_RequestMasqueReskin = function()
    -- External callers (Options, skin change) bypass count guard
    _lastReskinCount = -1
    RequestReskin()
end
_G.MSUF_A2_IsMasqueReadyForToggle = IsReadyForToggle
_G.MSUF_A2_SyncIconOverlayLevels = SyncIconOverlayLevels
_G.MSUF_A2_MasqueSkinHasBorder = SkinHasBorder

-- MSUF_A2_CooldownText.lua

-- MSUF_A2_CooldownText.lua
-- Auras 2.0 (Midnight/Beta): Secret-safe cooldown text coloring.
-- This implementation is tuned for maximum runtime performance:
--   * 0 protected-call wrappers
--   * No custom time formatting / no text overrides (no abbreviations)
--   * No per-icon remaining-seconds math (secret-safe by design)
--   * Discrete scheduled tick manager (no per-frame OnUpdate)
--   * Cached Cooldown FontString lookup (EnumerateRegions, no table alloc)

local addonName, ns = ...

ns = (rawget(_G, "MSUF_NS") or ns) or {}
local type, tonumber = type, tonumber
local pairs = pairs
local CreateFrame, GetTime = CreateFrame, GetTime
local C_Timer = C_Timer
local C_Secrets = C_Secrets
local C_CurveUtil = C_CurveUtil
ns.MSUF_Auras2 = ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

API.CooldownText = API.CooldownText or {}
local CT = API.CooldownText

local _G = _G
local type = _G.type
local CreateFrame = _G.CreateFrame
local CreateColor = _G.CreateColor
local GetTime = _G.GetTime
local tonumber = _G.tonumber
local strmatch = _G.string and _G.string.match
local strlower = _G.string and _G.string.lower

local C_CurveUtil = _G.C_CurveUtil
local C_Timer = _G.C_Timer

local C_Secrets = _G.C_Secrets

-- Step 6 perf: lightweight secret-value check. issecretvalue() is a single C-function call,
-- much cheaper than C_Secrets.IsSecret() which goes through namespace resolution.
-- Fallback to C_Secrets.IsSecret if issecretvalue isn't available yet (load-order defense).
local issecretvalue = _G.issecretvalue
    or (C_Secrets and type(C_Secrets.IsSecret) == "function" and C_Secrets.IsSecret)
    or nil

-- Secret mode detection (cached; avoids secret-value compares)

local _secretMode = false
local _secretNextCheck = 0
local SECRET_CHECK_INTERVAL = 0.50

local function IsSecretMode(now)
    if not C_Secrets or type(C_Secrets.ShouldAurasBeSecret) ~= "function" then
        return false
    end
    if type(now) ~= "number" then
        now = GetTime()
    end
    if now >= (_secretNextCheck or 0) then
        _secretNextCheck = now + SECRET_CHECK_INTERVAL
        -- ShouldAurasBeSecret() is cheap and avoids per-aura IsSecret checks.
        _secretMode = (C_Secrets.ShouldAurasBeSecret() == true)
    end
    return _secretMode == true
end

-- DB access (cheap + load-order safe)

local function EnsureDB()
    local DB = API and API.DB
    if DB and DB.Ensure then DB.Ensure() end
end
local function GetGeneral()
    local db = _G.MSUF_DB
    local g = db and db.general
    if type(g) ~= "table" then
        return nil
    end
    return g
end

local function ReadColor(t, defR, defG, defB, defA)
    if type(t) ~= "table" then
        return defR, defG, defB, defA
    end

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

-- Cooldown fontstring discovery (no table alloc)

local function MSUF_A2_GetCooldownFontString(icon, now, force)
    local cd = icon and icon.cooldown
    if not cd then
        return nil
    end

    local cached = cd._msufCooldownFontString
    if cached and cached ~= false then
        return cached
    end

    -- Cooldown count text can be created lazily; retry at a low frequency.
    local retryAt = cd._msufCooldownFontStringRetryAt
    if not force and type(retryAt) == "number" and type(now) == "number" and now < retryAt then
        return nil
    end

    if cd.EnumerateRegions then
        for region in cd:EnumerateRegions() do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                cd._msufCooldownFontString = region
                cd._msufCooldownFontStringRetryAt = nil
                return region
            end
        end
    else
        -- Rare fallback: one-time pack (only if EnumerateRegions is not available)
        local regions = { cd:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                cd._msufCooldownFontString = region
                cd._msufCooldownFontStringRetryAt = nil
                return region
            end
        end
    end

    -- Cache miss; retry later.
    cd._msufCooldownFontStringRetryAt = (type(now) == "number" and (now + (force and 0.05 or 0.50))) or nil
    cd._msufCooldownFontString = false
    return nil
end

CT.GetCooldownFontString = MSUF_A2_GetCooldownFontString

if _G and type(_G.MSUF_A2_GetCooldownFontString) ~= "function" then
    _G.MSUF_A2_GetCooldownFontString = function(icon)
        return MSUF_A2_GetCooldownFontString(icon, GetTime())
    end
end

-- Settings cache + curve

local settingsDirty = true
local bucketsEnabled = true
local safeR, safeG, safeB, safeA = 1, 1, 1, 1
local normalR, normalG, normalB, normalA = 1, 1, 1, 1
local warnR, warnG, warnB, warnA = 1, 0.85, 0.2, 1
local urgR,  urgG,  urgB,  urgA  = 1, 0.55, 0.1, 1
local expR,  expG,  expB,  expA  = 1, 0.55, 0.1, 1
local curve = nil

-- Threshold cache (seconds). Used for secret-safe text parsing fallback.
local thrSafeSeconds = 60
local thrWarnSeconds = 15
local thrUrgSeconds  = 5

-- Step 6 perf: per-icon evaluation skip durations (seconds) based on color bucket.
-- Icons in stable buckets don't need EvaluateRemainingDuration every tick.
local SKIP_NORMAL = 5.0   -- >safeSeconds: color is static for a long time
local SKIP_SAFE   = 2.0   -- warnSeconds..safeSeconds: color is static for seconds

local function BuildCurve(g)
    curve = nil

    if not (C_CurveUtil and type(C_CurveUtil.CreateColorCurve) == "function") then return end
    if type(CreateColor) ~= "function" then return end

    local c = C_CurveUtil.CreateColorCurve()
    if not c then return end

    if c.SetType and _G.Enum and _G.Enum.LuaCurveType and _G.Enum.LuaCurveType.Step then
        c:SetType(_G.Enum.LuaCurveType.Step)
    end

    -- Thresholds are already clamped/ordered in Render.lua when DB is validated.
    local safeSeconds = g and g.aurasCooldownTextSafeSeconds or 60
    local warnSeconds = g and g.aurasCooldownTextWarningSeconds or 15
    local urgSeconds  = g and g.aurasCooldownTextUrgentSeconds or 5

    -- Colors (stored as plain SV numbers; no clamping here for speed)
    local safeCR, safeCG, safeCB, safeCA = ReadColor(g and g.aurasCooldownTextSafeColor, safeR, safeG, safeB, safeA)
    local warnCR, warnCG, warnCB, warnCA = ReadColor(g and g.aurasCooldownTextWarningColor, 1, 0.85, 0.2, 1)
    local urgCR,  urgCG,  urgCB,  urgCA  = ReadColor(g and g.aurasCooldownTextUrgentColor, 1, 0.55, 0.1, 1)
    -- There is no public "Expire" color in the options UI. Keep the 0s
    -- bucket aligned with Urgent so the final "1" and recycled FontStrings
    -- never flash an unexplained red color.
    local expCR,  expCG,  expCB,  expCA  = urgCR, urgCG, urgCB, urgCA

    local safeCol   = CreateColor(safeCR, safeCG, safeCB, safeCA)
    local warnCol   = CreateColor(warnCR, warnCG, warnCB, warnCA)
    local urgentCol = CreateColor(urgCR,  urgCG,  urgCB,  urgCA)
    local expireCol = CreateColor(expCR,  expCG,  expCB,  expCA)
    local normalCol = CreateColor(normalR, normalG, normalB, normalA)

    -- Step curve points (remaining seconds -> color)
    c:AddPoint(0, expireCol)
    c:AddPoint(0.25, urgentCol)
    c:AddPoint(urgSeconds, warnCol)
    c:AddPoint(warnSeconds, safeCol)
    c:AddPoint(safeSeconds, normalCol)

    curve = c
end

local function EnsureSettings()
    if not settingsDirty then return end

    settingsDirty = false
    EnsureDB()

    local g = GetGeneral()

    bucketsEnabled = not (g and g.aurasCooldownTextUseBuckets == false)

    -- Thresholds (used by curve + secret-safe text fallback).
    do
        local ss = g and g.aurasCooldownTextSafeSeconds or 60
        local ws = g and g.aurasCooldownTextWarningSeconds or 15
        local us = g and g.aurasCooldownTextUrgentSeconds or 5

        if type(ss) ~= "number" then ss = 60 end
        if type(ws) ~= "number" then ws = 15 end
        if type(us) ~= "number" then us = 5 end

        -- Keep ordering sane (Render.lua should already validate this; this is a cheap safety net)
        if ws > ss then ws = ss end
        if us > ws then us = ws end
        if us < 0 then us = 0 end

        thrSafeSeconds = ss
        thrWarnSeconds = ws
        thrUrgSeconds  = us
    end

    -- Base/normal color: custom font color if enabled, else white.
    if g and g.useCustomFontColor == true then
        local r = g.fontColorCustomR
        local gg = g.fontColorCustomG
        local b = g.fontColorCustomB
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            normalR, normalG, normalB = r, gg, b
            normalA = 1
        else
            normalR, normalG, normalB, normalA = 1, 1, 1, 1
        end
    else
        normalR, normalG, normalB, normalA = 1, 1, 1, 1
    end

    safeR, safeG, safeB, safeA = ReadColor(g and g.aurasCooldownTextSafeColor, normalR, normalG, normalB, normalA)

    warnR, warnG, warnB, warnA = ReadColor(g and g.aurasCooldownTextWarningColor, 1, 0.85, 0.2, 1)
    urgR,  urgG,  urgB,  urgA  = ReadColor(g and g.aurasCooldownTextUrgentColor, 1, 0.55, 0.1, 1)
    -- Alias the internal expire bucket to Urgent; the options surface only has
    -- Safe / Warning / Urgent and users expect the last second to use Urgent.
    expR,  expG,  expB,  expA  = urgR, urgG, urgB, urgA

    if bucketsEnabled then
        BuildCurve(g)
    else
        curve = nil
    end
end

-- Public invalidation (Options -> calls this)
local function MSUF_A2_InvalidateCooldownTextCurve()
    settingsDirty = true
end

local function MSUF_A2_ForceCooldownTextRecolor()
    -- Step 6 perf: clear all per-icon skips and cached colors (bucket thresholds may have changed).
    local mgr = CT._mgr
    if mgr and mgr.count > 0 then
        for j = 1, mgr.count do
            local ic = mgr.icons[j]
            if ic then
                ic._msufA2_cdSkipUntil = nil
                ic._msufA2_cdLastR = nil
                ic._msufA2_cdLastG = nil
                ic._msufA2_cdLastB = nil
                ic._msufA2_cdLastA = nil
            end
        end
        if mgr._Schedule then
            mgr._Schedule(0)
        end
    end
end

CT.InvalidateCurve = MSUF_A2_InvalidateCooldownTextCurve
CT.ForceRecolor = MSUF_A2_ForceCooldownTextRecolor

API.InvalidateCooldownTextCurve = API.InvalidateCooldownTextCurve or MSUF_A2_InvalidateCooldownTextCurve
API.ForceCooldownTextRecolor = API.ForceCooldownTextRecolor or MSUF_A2_ForceCooldownTextRecolor

if _G and type(_G.MSUF_A2_InvalidateCooldownTextCurve) ~= "function" then
    _G.MSUF_A2_InvalidateCooldownTextCurve = function()
        return API.InvalidateCooldownTextCurve()
    end
end

if _G and type(_G.MSUF_A2_ForceCooldownTextRecolor) ~= "function" then
    _G.MSUF_A2_ForceCooldownTextRecolor = function()
        return API.ForceCooldownTextRecolor()
    end
end

CT._ApplyCooldownTextColor = function(icon, fs, r, g, b, a, secret)
    if not icon or not fs then return end

    if secret then
        icon._msufA2_cdLastFS = fs
        icon._msufA2_cdLastR = nil
        icon._msufA2_cdLastG = nil
        icon._msufA2_cdLastB = nil
        icon._msufA2_cdLastA = nil

        if fs.SetTextColor then
            fs:SetTextColor(r, g, b, a)
        elseif fs.SetVertexColor then
            fs:SetVertexColor(r, g, b, a)
        end
        return
    end

    if icon._msufA2_cdLastFS ~= fs
        or icon._msufA2_cdLastR ~= r
        or icon._msufA2_cdLastG ~= g
        or icon._msufA2_cdLastB ~= b
        or icon._msufA2_cdLastA ~= a then

        icon._msufA2_cdLastFS = fs
        icon._msufA2_cdLastR = r
        icon._msufA2_cdLastG = g
        icon._msufA2_cdLastB = b
        icon._msufA2_cdLastA = a

        if fs.SetTextColor then
            fs:SetTextColor(r, g, b, a)
        elseif fs.SetVertexColor then
            fs:SetVertexColor(r, g, b, a)
        end
    end
end

CT.ApplyImmediateColor = function(icon, now)
    if not icon or icon._msufA2_hideCDNumbers == true then return false end
    local cd = icon.cooldown
    if not cd then return false end

    EnsureSettings()

    if type(now) ~= "number" then
        now = GetTime()
    end

    local fs = cd._msufCooldownFontString
    if fs == false then fs = nil end
    if not fs then
        fs = MSUF_A2_GetCooldownFontString(icon, now, true)
        if fs then
            cd._msufCooldownFontString = fs
        end
    end
    if not fs then return false end

    local r, g, b, a = safeR, safeG, safeB, safeA
    local iconSecret = false

    if bucketsEnabled and curve then
        local obj = icon._msufA2_cdDurationObj or cd._msufA2_durationObj
        if obj and type(obj.EvaluateRemainingDuration) == "function" then
            local col = obj:EvaluateRemainingDuration(curve)
            if col then
                if col.GetRGBA then
                    r, g, b, a = col:GetRGBA()
                elseif col.GetRGB then
                    r, g, b = col:GetRGB()
                    a = 1
                end
            end
        end

        local secretsActive = IsSecretMode(now)
        local isv = issecretvalue
        if not isv then
            isv = _G.issecretvalue
                or (C_Secrets and type(C_Secrets.IsSecret) == "function" and C_Secrets.IsSecret)
                or nil
            if isv then
                issecretvalue = isv
            end
        end
        iconSecret = (secretsActive and not isv) or (isv and isv(r)) or false
    end

    CT._ApplyCooldownTextColor(icon, fs, r, g, b, a, iconSecret)
    return true
end

-- Cooldown Text Manager (timer-scheduled; no per-frame OnUpdate)
-- Why:
--   Even with an accumulator, a Frame OnUpdate still runs every frame,
--   doing work (elapsed adds + branches) while the raid is idle.
--   This manager uses C_Timer to schedule discrete ticks only when needed.
--   Net result: near-zero idle CPU with many visible auras.

local function EnsureMgr()
    local mgr = CT._mgr
    if mgr then
        return mgr
    end

    mgr = {
        icons = {},
        count = 0,
        -- Discrete tick scheduling (no per-frame OnUpdate)
        timer = nil,
        timerGen = 0,
        slowInterval = 0.50, -- 2 Hz in normal mode (big idle CPU win in raids)
        fastInterval = 0.10, -- 10 Hz when a timer is in warning/urgent/expire bucket
        secretInterval = 0.20, -- 5 Hz in SecretMode (colors still animate; less CPU than 10 Hz)
        interval = 0.50,
        fastUntil = 0,
    }

    CT._mgr = mgr

    local function CancelTimer()
        local t = mgr.timer
        if t and t.Cancel then
            t:Cancel()
        end
        mgr.timer = nil
        -- Guard for C_Timer.After fallback: invalidate any already-queued callbacks.
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

        if swap then
            swap._msufA2_cdMgrIndex = i
        end
        if icon then
            icon._msufA2_cdMgrIndex = nil
            icon._msufA2_cdMgrRegistered = false
            icon._msufA2_cdLastFS = nil
            icon._msufA2_cdLastR = nil
            icon._msufA2_cdLastG = nil
            icon._msufA2_cdLastB = nil
            icon._msufA2_cdLastA = nil
            icon._msufA2_cdSkipUntil = nil
        end

        if mgr.count <= 0 then
            StopIfIdle()
        end
    end

    local function Tick()
        mgr._msufA2_touchPending = false
        EnsureSettings()

        local now = GetTime()

        local secretsActive = IsSecretMode(now)

        -- If we recently saw a warning/urgent/expire bucket, keep fast ticking briefly.
        local wantFast = (now < (mgr.fastUntil or 0))

        -- Step 6 perf: lazy-resolve secret-check function once per Tick.
        -- issecretvalue may have been nil at module load due to load-order; re-check _G.
        -- If still nil  pre-12.0 client where secret values don't exist  == is safe.
        local isv = issecretvalue
        if not isv then
            isv = _G.issecretvalue
                or (C_Secrets and type(C_Secrets.IsSecret) == "function" and C_Secrets.IsSecret)
                or nil
            if isv then
                issecretvalue = isv -- cache for future ticks
            end
        end

        -- Load-order edge case: if aura secret mode is active but issecretvalue() isn't
        -- available yet, we must assume returned values could be secret and avoid any
        -- value comparisons (safety > colors until the next tick).
        local secretNoDetector = (secretsActive and not isv)

        -- Step 6 perf: per-icon secret check uses isv(r) â€” ONE C-call per evaluated
        -- icon instead of the original 4Ã— C_Secrets.IsSecret(r/g/b/a).
        -- Only r is checked: if r is secret from GetRGBA(), g/b/a from the same
        -- Color object will be too. Icons in skip (NORMAL/SAFE bucket) don't reach
        -- the evaluation path at all, reducing total calls to ~5-8 per tick.
        -- IMPORTANT: different Duration Objects can have different secret states
        -- (e.g. non-secret buff + secret debuff). Per-icon check is required.

        -- Iterate backwards so removals are O(1) without skipping.
        local i = mgr.count
        while i > 0 do
            local icon = mgr.icons[i]

            if not icon or not icon.cooldown or not icon.IsShown or not icon:IsShown() then
                RemoveAt(i)
            elseif icon._msufA2_hideCDNumbers ~= true then
                local cd = icon.cooldown

                local fs = cd._msufCooldownFontString
                if fs == false then
                    fs = nil
                end
                if not fs then
                    fs = MSUF_A2_GetCooldownFontString(icon, now)
                    if fs then
                        cd._msufCooldownFontString = fs
                    end
                end

                if fs then
                    -- Step 6 perf: per-icon evaluation skip.
                    -- Icons in NORMAL or SAFE buckets don't need EvaluateRemainingDuration
                    -- every tick because their color is constant until the next threshold.
                    local skipUntil = icon._msufA2_cdSkipUntil
                    if skipUntil and now < skipUntil then
                        -- Bucket hasn't changed since last eval  nothing to do.
                        -- (fs and color were already set on the last real evaluation.)
                    else
                                                -- Full evaluation path (same bucket result as before, just less frequent).
                        local r, g, b, a = safeR, safeG, safeB, safeA
                        local bucket = 3 -- safe (default)
                        local iconSecret = false
                        local didCurveEval = false

                        if bucketsEnabled and curve then
                            local obj = icon._msufA2_cdDurationObj or cd._msufA2_durationObj
                            if obj and type(obj.EvaluateRemainingDuration) == 'function' then
                                local col = obj:EvaluateRemainingDuration(curve)
                                if col then
                                    didCurveEval = true
                                    if col.GetRGBA then
                                        r, g, b, a = col:GetRGBA()
                                    elseif col.GetRGB then
                                        r, g, b = col:GetRGB()
                                        a = 1
                                    end
                                end
                            end
                        end

                        -- Secret handling:
                        -- 1) If cooldown queries are secret but we can't detect secret values yet,
                        --    treat as secret to avoid any comparisons/caching mistakes.
                        -- 2) If curve evaluation returned secret values, we still APPLY them via
                        --    SetTextColor/SetVertexColor (C-side) but we must not diff/compare them.
                        if secretsActive and secretNoDetector then
                            iconSecret = true
                        elseif isv and isv(r) then
                            iconSecret = true
                        end

                        -- If curve is missing or evaluation failed, stay on SAFE color.
                        if bucketsEnabled and (not curve or not didCurveEval) then
                            r, g, b, a = safeR, safeG, safeB, safeA
                            if secretsActive then
                                iconSecret = true
                            end
                            bucket = 3
                        end

                        -- Identify bucket by color match (non-secret only)  sets wantFast.
                        if (not iconSecret) and bucketsEnabled then
                            if r == expR and g == expG and b == expB then
                                bucket = 0
                                wantFast = true
                            elseif r == urgR and g == urgG and b == urgB then
                                bucket = 1
                                wantFast = true
                            elseif r == warnR and g == warnG and b == warnB then
                                bucket = 2
                                wantFast = true
                            elseif r == normalR and g == normalG and b == normalB then
                                bucket = 4
                            else
                                bucket = 3 -- safe (default/fallback)
                            end
                        end

                        -- In secret mode we can't diff RGBA. Tick fast enough to keep curve transitions visible.
                        if iconSecret and bucketsEnabled then
                            wantFast = true
                        end
                        -- Set per-icon skip for stable buckets.
                        -- (bucket identification is best-effort for skip/wantFast only;
                        --  if Color precision causes a mismatch, bucket defaults to 3
                        --  which gives a conservative 2s skip â€” safe and still beneficial.)
                        if iconSecret then
                            icon._msufA2_cdSkipUntil = nil -- secret: re-evaluate each tick
                        elseif bucket == 4 then
                            icon._msufA2_cdSkipUntil = now + SKIP_NORMAL
                        elseif bucket == 3 then
                            icon._msufA2_cdSkipUntil = now + SKIP_SAFE
                        else
                            icon._msufA2_cdSkipUntil = nil -- warn/urgent/expire: evaluate every tick
                        end

                        -- SetTextColor diff: use actual RGBA values, not integer bucket.
                        -- CreateColor/GetRGBA round-trip may not produce exact matches
                        -- with module-level cached floats, so bucket==bucket can't replace
                        -- r==lastR for SetTextColor decisions.
                        CT._ApplyCooldownTextColor(icon, fs, r, g, b, a, iconSecret)
                        end -- skipUntil check

                end
            end

            i = i - 1
        end

        if wantFast then
            mgr.fastUntil = now + 1.50
            if secretsActive then
                mgr.interval = mgr.secretInterval or mgr.fastInterval or 0.10
            else
                mgr.interval = mgr.fastInterval or 0.10
            end
        else
            mgr.interval = mgr.slowInterval or 0.50
        end

        StopIfIdle()

        -- Reschedule next discrete tick (if still active)
        if mgr.count > 0 and mgr._Schedule then
            mgr._Schedule(mgr.interval)
        end
    end

    -- Stable callback: created once, reused on every Schedule call.
    -- Eliminates ~1,500 closure allocations/min from C_Timer.NewTimer.
    local _tickCallback = function()
        mgr.timer = nil
        Tick()
    end

    local function Schedule(delay)
        if mgr.count <= 0 then
            StopIfIdle()
            return
        end

        if type(delay) ~= "number" or delay < 0 then
            delay = 0
        end

        -- Replace any pending timer.
        CancelTimer()

        local timerAPI = C_Timer
        if timerAPI and type(timerAPI.NewTimer) == "function" then
            mgr.timer = timerAPI.NewTimer(delay, _tickCallback)
            return
        end

        -- Fallback (older clients): After() has no cancel; use a generation guard.
        -- This path still allocates a closure (unavoidable without Cancel support).
        if timerAPI and type(timerAPI.After) == "function" then
            mgr.timerGen = (mgr.timerGen or 0) + 1
            local gen = mgr.timerGen
            timerAPI.After(delay, function()
                if mgr.timerGen ~= gen then return end
                Tick()
            end)
        end
    end

    mgr._StopIfIdle = StopIfIdle
    mgr._RemoveAt = RemoveAt
    mgr._Tick = Tick
    mgr._Schedule = Schedule

    return mgr
end

local function RegisterIcon(icon)
    if not icon or not icon.cooldown then return end

    if icon._msufA2_cdMgrRegistered == true then return end

    local mgr = EnsureMgr()
    local now = GetTime()

    local idx = mgr.count + 1
    mgr.count = idx
    mgr.icons[idx] = icon

    icon._msufA2_cdMgrRegistered = true
    icon._msufA2_cdMgrIndex = idx
    icon._msufA2_cdSkipUntil = nil

    CT.ApplyImmediateColor(icon, now)
    mgr.fastUntil = now + 1.00

    if mgr._Schedule then
        mgr._msufA2_touchPending = false
        mgr._Schedule(0)
    end
end

local function UnregisterIcon(icon)
    if not icon or icon._msufA2_cdMgrRegistered ~= true then
        if icon then
            icon._msufA2_cdMgrIndex = nil
            icon._msufA2_cdMgrRegistered = false
        end
        return
    end

    local mgr = CT._mgr
    if not mgr or mgr.count <= 0 then
        icon._msufA2_cdMgrIndex = nil
        icon._msufA2_cdMgrRegistered = false
        return
    end

    local idx = icon._msufA2_cdMgrIndex
    if type(idx) == "number" and idx >= 1 and idx <= mgr.count then
        mgr._RemoveAt(idx)
        return
    end

    -- Fallback: rare desync (no search by default; just mark inactive)
    icon._msufA2_cdMgrIndex = nil
    icon._msufA2_cdMgrRegistered = false
end

local function UnregisterAll()
    local mgr = CT._mgr
    if not mgr then return end

    for i = 1, mgr.count do
        local icon = mgr.icons[i]
        if icon then
            icon._msufA2_cdMgrIndex = nil
            icon._msufA2_cdMgrRegistered = false
        end
        mgr.icons[i] = nil
    end

    mgr.count = 0
    if mgr.timer and mgr.timer.Cancel then
        mgr.timer:Cancel()
    end
    mgr.timer = nil
    mgr.timerGen = (mgr.timerGen or 0) + 1
end

local function TouchIcon(icon)
    -- Step 6 perf: clear per-icon evaluation skip so the next Tick() re-evaluates
    -- this icon immediately (called when a duration object is reattached).
    local now = GetTime()
    if icon then
        icon._msufA2_cdSkipUntil = nil
        CT.ApplyImmediateColor(icon, now)
    end
    local mgr = CT._mgr
    if mgr and mgr.count > 0 and mgr._Schedule then
        mgr.fastUntil = now + 1.00
        -- Coalesce repeated touches from the same render pass into one ASAP tick.
        if mgr._msufA2_touchPending ~= true then
            mgr._msufA2_touchPending = true
            mgr._Schedule(0)
        end
    end
end

CT.RegisterIcon = RegisterIcon
CT.UnregisterIcon = UnregisterIcon
CT.UnregisterAll = UnregisterAll
CT.TouchIcon = TouchIcon

-- Convenience alias
API.CooldownText = CT

-- Cold-start resync (load-order safe)

local function ProcessPending()
    local st = API and API.state
    local pending = st and st._msufA2_cdPending
    if not pending then return end

    for i = 1, #pending do
        local icon = pending[i]
        pending[i] = nil
        if icon and icon._msufA2_cdMgrRegistered ~= true and icon._msufA2_hideCDNumbers ~= true then
            RegisterIcon(icon)
        end
        if icon then
            icon._msufA2_cdPending = nil
        end
    end
end

local function ScanAndRegisterExisting()
    local st = API and API.state
    local byUnit = st and st.aurasByUnit
    if not byUnit then return end

    for _, entry in pairs(byUnit) do
        if type(entry) == "table" then
            local cont = entry.buffs
            if cont and type(cont._msufIcons) == "table" then
                local icons = cont._msufIcons
                for i = 1, #icons do
                    local icon = icons[i]
                    if icon
                        and icon._msufA2_cdMgrRegistered ~= true
                        and icon._msufA2_hideCDNumbers ~= true
                        and icon.IsShown and icon:IsShown()
                        and icon.cooldown
                        and (icon._msufA2_cdDurationObj ~= nil or icon.cooldown._msufA2_durationObj ~= nil)
                    then
                        RegisterIcon(icon)
                    end
                end
            end

            cont = entry.debuffs
            if cont and type(cont._msufIcons) == "table" then
                local icons = cont._msufIcons
                for i = 1, #icons do
                    local icon = icons[i]
                    if icon
                        and icon._msufA2_cdMgrRegistered ~= true
                        and icon._msufA2_hideCDNumbers ~= true
                        and icon.IsShown and icon:IsShown()
                        and icon.cooldown
                        and (icon._msufA2_cdDurationObj ~= nil or icon.cooldown._msufA2_durationObj ~= nil)
                    then
                        RegisterIcon(icon)
                    end
                end
            end

            cont = entry.mixed
            if cont and type(cont._msufIcons) == "table" then
                local icons = cont._msufIcons
                for i = 1, #icons do
                    local icon = icons[i]
                    if icon
                        and icon._msufA2_cdMgrRegistered ~= true
                        and icon._msufA2_hideCDNumbers ~= true
                        and icon.IsShown and icon:IsShown()
                        and icon.cooldown
                        and (icon._msufA2_cdDurationObj ~= nil or icon.cooldown._msufA2_durationObj ~= nil)
                    then
                        RegisterIcon(icon)
                    end
                end
            end
        end
    end
end

CT.ProcessPending = ProcessPending
CT.ScanExisting = ScanAndRegisterExisting

-- Combat flip recolor
-- In Midnight 12.0 the aura "secret mode" commonly toggles with combat state.
-- Our manager uses per-icon skip windows; without a forced refresh, a combat
-- transition could keep the previous bucket's color for up to SKIP_* seconds.
-- This hook is extremely cheap (fires twice per combat) and keeps colors
-- consistent with out-of-combat behavior.

do
    if not CT._recolorEventFrame and type(CreateFrame) == "function" then
        local f = CreateFrame("Frame")
        CT._recolorEventFrame = f

        if f.RegisterEvent then
            f:RegisterEvent("PLAYER_REGEN_DISABLED")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:RegisterEvent("PLAYER_ENTERING_WORLD")
        end

        if f.SetScript then
            f:SetScript("OnEvent", function()
                local mgr = CT._mgr
                if mgr and mgr.count and mgr.count > 0 then
                    MSUF_A2_ForceCooldownTextRecolor()
                end
            end)
        end
    end
end

-- Run now (common case: this module loads after Render/Apply)
ProcessPending()
ScanAndRegisterExisting()

-- Run once on next frame (reverse load order)
if C_Timer and type(C_Timer.After) == "function" then
    C_Timer.After(0, function()
        ProcessPending()
        ScanAndRegisterExisting()
    end)
end
