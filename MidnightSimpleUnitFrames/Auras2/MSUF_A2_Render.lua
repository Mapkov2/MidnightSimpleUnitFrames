-- MSUF_A2_Render.lua - Auras2 render orchestration

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
-- NOT in this file: icon creation/visuals (Core.lua), event wiring (Events.lua),
-- Masque integration (Masque.lua), or cooldown text management (CooldownText.lua).

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}

ns.MSUF_A2_L_RELOAD_COMBAT = "|cffff5555MSUF|r: Can't reload UI in combat. Leave combat, then type /reload."
ns.MSUF_A2_L_RELOAD_UI = "Reload UI"
ns.MSUF_A2_L_CANCEL = "Cancel"

ns.MSUF_A2_RefreshLocaleText = function()
    if type(ns.Translate) == "function" then
        ns.MSUF_A2_L_RELOAD_COMBAT = ns.Translate("|cffff5555MSUF|r: Can't reload UI in combat. Leave combat, then type /reload.")
        ns.MSUF_A2_L_RELOAD_UI = ns.Translate("Reload UI")
        ns.MSUF_A2_L_CANCEL = ns.Translate("Cancel")
    end
end

ns.MSUF_A2_RefreshLocaleText()
if type(ns.RegisterLocaleCallback) == "function" then
    ns.RegisterLocaleCallback("MSUF_A2_Render", ns.MSUF_A2_RefreshLocaleText)
end

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
    if _inCombat or _G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()) then return false end
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
-- LayoutMode (SINGLE vs SEPARATE) permanently deprecated â€” runtime always uses separate groups.
local A2_STACKANCHOR_OK = {TOPRIGHT=true,TOPLEFT=true,BOTTOMRIGHT=true,BOTTOMLEFT=true}

-- DefaultKV + Clamp: on API._Render (avoids 200-local limit)
API._Render = API._Render or {}
API._Render.DefaultKV = function(t, d) for k, v in pairs(d) do if t[k] == nil then t[k] = v end end end
API._Render.Clamp = function(v, def, lo, hi) v = tonumber(v); if not v then v = def end; if lo and v < lo then v = lo end; if hi and v > hi then v = hi end; return v end

local function EnsureDB()
    local gdb = _G.MSUF_DB
    if type(gdb) ~= "table" then _G.MSUF_DB = {}; gdb = _G.MSUF_DB end
    local ensureDB = _G.MSUF_EnsureDB
    if ensureDB then ensureDB() end
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

    -- Rebuild the cheap DB snapshot immediately so event registrations follow
    -- the current enabled state. Without this, old UNIT_AURA helper frames can
    -- keep firing after the master Auras2 toggle was disabled.
    local a2 = GetAuras2DB()
    local DB = API.DB
    local anyEnabled = false
    if type(a2) == "table" and a2.enabled == true and DB then
        if DB.AnyUnitEnabledCached then
            anyEnabled = (DB.AnyUnitEnabledCached() == true)
        else
            local c = DB.cache
            local ue = c and c.unitEnabled
            if ue then
                for _, enabled in pairs(ue) do
                    if enabled == true then
                        anyEnabled = true
                        break
                    end
                end
            end
        end
    end

    local applyEvents = API.ApplyEventRegistration
    if type(applyEvents) == "function" then applyEvents() end

    -- Wipe per-entry layout caches so UpdateAnchor re-positions containers
    local aby = A2_STATE.aurasByUnit
    if aby then
        for _, entry in pairs(aby) do
            if entry then entry._msufLayoutCache = nil end
        end
    end
    if not anyEnabled then
        local hardDisable = API.HardDisableAll
        if type(hardDisable) == "function" then hardDisable() end
        return
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

local function FlushDriverOnUpdate(_, elapsed)
    local at = _flushNextAt
    if not at then StopFlushDriver(); return end
    at = at - (elapsed or 0)
    if at <= 0 then
        _flushNextAt = nil
        if Flush then
            Flush()
        end
    else
        _flushNextAt = at
    end
end

local function ScheduleFlush(delay)
    if not delay or delay < 0 then delay = 0 end

    if _flushDriverActive then
        -- Driver already running. Only update target time if new delay is sooner.
        if delay == 0 then
            _flushNextAt = 0  -- immediate (next OnUpdate)
        else
            local at = delay
            if not _flushNextAt or at < _flushNextAt then
                _flushNextAt = at
            end
        end
        return
    end

    -- Start driver
    _flushNextAt = delay
    _flushDriverActive = true
    _flushDriver:Show()
    _flushDriver:SetScript("OnUpdate", FlushDriverOnUpdate)
end

-- MarkDirty (public entry point for scheduling unit updates)
-- PERF: Inlined DirtyAdd + ScheduleFlush â€” was 3 function calls, now 0.

local function MarkDirty(unit, delay)
    if not unit then return end

    -- PERF: Single table lookup dedupe (hottest check â€” runs on every UNIT_AURA)
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
            local at = delay
            if not _flushNextAt or at < _flushNextAt then
                _flushNextAt = at
            end
        end
    else
        _flushNextAt = delay
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

    -- Reminder container (player-only, but create for all â€” hidden by default)
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
        -- FilterAndSort sees the stale empty entry and skips FullScan â†’ 0 auras.
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
    -- Sort order (caps level â€” per-unit overridable via layoutShared)
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
    -- Resolve per-type fallback: nil â†’ growth
    if not buffGrowth or not A2_GROWTH_OK[buffGrowth] then buffGrowth = growth end
    if not debuffGrowth or not A2_GROWTH_OK[debuffGrowth] then debuffGrowth = growth end
    if not privateGrowth or not A2_GROWTH_OK[privateGrowth] then privateGrowth = growth end
    -- Resolve per-type rowWrap fallback: nil â†’ rowWrap
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

API._Render.HasPrivateAuraState = function(entry, checkSlots)
    if not entry then return false end
    if entry._msufA2PrivateStateActive == true then return true end
    if type(entry._privateAnchorIDs) == "table" then return true end
    if entry._privUnit or entry._privToken or entry._privSize or entry._privMax then return true end
    if entry._privNormalizeQueued then return true end
    if entry.private and entry.private.IsShown and entry.private:IsShown() then return true end
    if checkSlots then
        local slots = entry._privateSlots
        if type(slots) == "table" then
            for i = 1, #slots do
                local slot = slots[i]
                if slot and slot.IsShown and slot:IsShown() then return true end
            end
        end
    end
    return false
end

local function PrivateClear(entry)
    if not entry then return end
    if not API._Render.HasPrivateAuraState(entry, true) then return end
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
    entry._msufA2PrivateStateActive = nil
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
        if API._Render.HasPrivateAuraState(entry, false) then PrivateClear(entry) end
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

    -- PERF: Zero-alloc diff check (replaces 6Ã— string concat + comparison)
    if entry._privUnit == unit
       and entry._privToken == effectiveToken
       and entry._privSize == privateIconSize
       and entry._privSpacing == spacing
       and entry._privMax == maxN
       and entry._privGrowth == privateGrowth
       and entry._privBorderScale == borderScale
       and type(entry._privateAnchorIDs) == "table"
    then
        entry._msufA2PrivateStateActive = true
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
    entry._msufA2PrivateStateActive = true

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
            -- We use false (same as Plater) â†’ one anchor = one aura index.
            -- isContainer=true is a future path where Blizzard manages the
            -- entire aura list within a single parent frame and (per R41z0r)
            -- displays dispel-type colors natively â€” but the args shape for
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

    local Native = ns and ns.MSUF_AuraNative
    local ensureDispelOverlay = Native and Native.EnsurePrivateAuraDispelOverlay
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
        if ensureDispelOverlay then
            ensureDispelOverlay(slot)
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

        local ok, anchorID = pcall(C_UnitAuras.AddPrivateAuraAnchor, args)
        if ok and anchorID then
            entry._privateAnchorIDs[#entry._privateAnchorIDs + 1] = anchorID
        elseif not ok then
            entry._privateLastError = anchorID
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

API._RenderCommitAuraList = function(container, list, count, unit, shared, isHelpful, masterOn, bossHealHighlightOwn, stackCountAnchor, gen, updatedAuraIDs, commitUpdatedOnly, acquireIcon, commitIcon)
    if count <= 0 then return commitUpdatedOnly end

    local pool = container._msufIcons
    if not pool then
        pool = {}
        container._msufIcons = pool
    end
    if count > (container._msufA2_activeN or 0) then
        container._msufA2_activeN = count
    end

    for i = 1, count do
        local aura = list[i]
        if aura then
            if isHelpful then
                aura._msufA2_forceBossHealHighlight =
                    (bossHealHighlightOwn and aura._msufA2_isHealerHot == 1 and aura._msufIsPlayerAura == true) or nil
            end

            local icon = pool[i]
            if icon then
                if not icon:IsShown() then icon:Show() end
            else
                icon = acquireIcon(container, i)
                commitUpdatedOnly = false
            end

            local doCommit = not commitUpdatedOnly
            if not doCommit then
                local aid = aura._msufAuraInstanceID or aura.auraInstanceID
                doCommit = updatedAuraIDs[aid] == true or not icon._msufA2_lastCommit
            end
            if doCommit then
                commitIcon(icon, unit, aura, shared, isHelpful, false, masterOn, aura._msufIsPlayerAura, stackCountAnchor, gen)
            end
        end
    end

    return commitUpdatedOnly
end

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
    local isEditActive = (not _inCombat and _G.MSUF_InCombat ~= true) and IsEditModeActive() or false

    -- Reuse DB from scan-limits path if available, otherwise fetch now
    if not a2 or not shared then
        a2, shared = GetAuras2DB()
    end
    if not a2 or not shared then return end

    -- Unit disabled via options toggle: hide all icons + anchor and bail out.
    -- Edit mode preview bypasses this so movers remain visible for positioning.
    if not UnitEnabled(a2, unit) and not isEditActive then
        if entry._msufA2DisabledClean == true then return end
        Icons.HideUnused(entry.buffs, 1)
        Icons.HideUnused(entry.debuffs, 1)
        if entry.mixed then Icons.HideUnused(entry.mixed, 1) end
        if API._Render.HasPrivateAuraState(entry, false) then PrivateClear(entry) end
        API._Render.ClearNativeAuras(entry)
        if entry.anchor then entry.anchor:Hide() end
        entry._msufA2DisabledClean = true
        return
    end
    entry._msufA2DisabledClean = nil

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
            cfg.debuffsIncludeDispellable,
            cfg.debuffDispelMagic, cfg.debuffDispelCurse, cfg.debuffDispelPoison, cfg.debuffDispelDisease,
            cfg.sortOrder,
            cfg.buffsIncludeStealable =
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
            cfg.buffsIncludeStealable = false
            cfg.debuffsIncludeBoss = false
            cfg.hidePermanentBuffs = false
            cfg.debuffsIncludeDispellable = false
            cfg.debuffDispelMagic = false
            cfg.debuffDispelCurse = false
            cfg.debuffDispelPoison = false
            cfg.debuffDispelDisease = false
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
        -- Global Ignore List (shared for boss frames, per-unit overridable elsewhere)
        local cats = shared.ignoreCats
        if pu and pu.overrideIgnore == true and type(pu.ignoreCats) == "table" then
            cats = pu.ignoreCats
        end
        cfg.ignoreCats = (cats) and cats or nil
        -- Display flags
        cfg.showBuffs = (shared.showBuffs == true)
        cfg.showDebuffs = (shared.showDebuffs == true)
        cfg.privateAurasShown = (unit == "player")
            and (shared.privateAurasEnabled == true)
            and (shared.showPrivateAurasPlayer == true)

        -- Migration/edge guard: old builds may have left private anchor state
        -- on an entry before this hot-path gate existed. Detect it only when
        -- config changes, never on every aura render.
        if cfg.privateAurasShown ~= true and entry._msufA2PrivateStateActive ~= true then
            if entry._privateAnchorIDs ~= nil
               or entry._privUnit ~= nil
               or entry._privToken ~= nil
               or entry._privSize ~= nil
               or entry._privMax ~= nil
               or entry._privNormalizeQueued == true
            then
                entry._msufA2PrivateStateActive = true
            end
        end
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
    -- PERF: Zero overhead when reminders disabled â€” no mover creation.
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
    -- Only player can use this path; once anchors are built they are engine
    -- managed, so normal combat aura renders should not re-enter the rebuild.
    local privateActive = entry._msufA2PrivateStateActive == true
    if cfg.privateAurasShown == true then
        if entry._lastPrivateGen ~= gen or not privateActive then
            if not _inCombat then
                PrivateRebuild(entry, shared, privateIconSize, spacing, privateGrowth)
                entry._lastPrivateGen = gen
            end
        end
    elseif privateActive then
        if not _inCombat then
            PrivateClear(entry)
            entry._lastPrivateGen = nil
        end
    end

    -- Edit Mode: show/hide movers (skip entirely in combat)
    if not _inCombat and _G.MSUF_InCombat ~= true then
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
    local maxBuffsNum = tonumber(maxBuffs) or 12
    local maxDebuffsNum = tonumber(maxDebuffs) or 12
    if maxBuffsNum < 0 then maxBuffsNum = 0 end
    if maxDebuffsNum < 0 then maxDebuffsNum = 0 end
    cfg._maxBuffs = maxBuffsNum
    cfg._maxDebuffs = maxDebuffsNum
    local customBuffs = (showBuffs == true) and maxBuffsNum > 0
    local customDebuffs = (showDebuffs == true) and not skipDebuffs and maxDebuffsNum > 0
    cfg._wantBuffs = customBuffs
    cfg._wantDebuffs = customDebuffs

    local _, nB, _, nD = CacheModule.FilterAndSort(unit, cfg, entry._buffList, entry._debuffList)
    local updatedAuraIDs = CacheModule.GetUpdatedAuraIDs and CacheModule.GetUpdatedAuraIDs(unit)

    buffCount  = customBuffs and nB or 0
    debuffCount = customDebuffs and nD or 0

    local lastBuffCount = entry._lastBuffCount or 0
    local lastDebuffCount = entry._lastDebuffCount or 0
    local countsChanged = (buffCount ~= lastBuffCount) or (debuffCount ~= lastDebuffCount)
    local commitUpdatedOnly = updatedAuraIDs and entry._lastA2CommitGen == gen and not countsChanged and not isEditActive and not showTest

    -- CommitIcon: debuffs, then buffs. Helper keeps the pool fast path shared.
    -- PERF: pool[i] hit still skips the full AcquireIcon path.
    if debuffCount > 0 then
        commitUpdatedOnly = API._RenderCommitAuraList(entry.debuffs, entry._debuffList, debuffCount, unit, shared, false, masterOn, false, stackCountAnchor, gen, updatedAuraIDs, commitUpdatedOnly, _AcquireIcon, _CommitIcon)
    end

    if buffCount > 0 then
        commitUpdatedOnly = API._RenderCommitAuraList(entry.buffs, entry._buffList, buffCount, unit, shared, true, masterOn, bossHealHighlightOwn, stackCountAnchor, gen, updatedAuraIDs, commitUpdatedOnly, _AcquireIcon, _CommitIcon)
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
        local debuffLayoutStamp = debuffCount * 100000007 + debuffIconSize * 10000019 + spacing * 100003 + perRow * 10007 + (_DIR_HASH[debuffGrowth] or 0) * 1009 + (_DIR_HASH[debuffRowWrap] or 0) * 101
        if entry._msufA2_lastDebuffLayoutStamp ~= debuffLayoutStamp then
            entry._msufA2_lastDebuffLayoutStamp = debuffLayoutStamp
            _LayoutIcons(entry.debuffs, debuffCount, debuffIconSize, spacing, perRow, debuffGrowth, debuffRowWrap, debuffLayoutStamp)
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
        local buffLayoutStamp = buffCount * 100000007 + buffIconSize * 10000019 + spacing * 100003 + perRow * 10007 + (_DIR_HASH[buffGrowth] or 0) * 1009 + (_DIR_HASH[buffRowWrap] or 0) * 101
        if entry._msufA2_lastBuffLayoutStamp ~= buffLayoutStamp then
            entry._msufA2_lastBuffLayoutStamp = buffLayoutStamp
            _LayoutIcons(entry.buffs, buffCount, buffIconSize, spacing, perRow, buffGrowth, buffRowWrap, buffLayoutStamp)
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
    -- PERF: Zero overhead when disabled or non-player â€” no function call at all.
    if unit == "player" and shared and shared.showReminders ~= false then
        local ReminderMod = API.Reminder
        if ReminderMod and ReminderMod.Render then
            ReminderMod.Render(entry, unit, shared, buffIconSize, spacing, buffGrowth, showTest)
        end
    end
end

-- Flush

-- PERF: Budget cap for aura flush. Shared with UFCore for combined frame budget.
-- Own cap: 350Î¼s. Shared total: 700Î¼s (UFCore 350 + A2 350 max).
-- In practice UFCore uses 50-200Î¼s â†’ A2 gets 500-650Î¼s on most frames.
-- Spiky frames (UFCore near cap): A2 gets min 150Î¼s = enough for 1 unit.
local _A2_FLUSH_BUDGET_US = 350  -- own cap (microseconds)
local _A2_SHARED_BUDGET_US = 700 -- combined MSUF budget per frame
local _A2_MIN_BUDGET_US = 150    -- minimum budget (always process â‰¥1 unit)
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

        -- Fast path: entry already attached with valid frame Ã¢â€ â€™ skip FindUnitFrame
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

-- Combat-leave guard: tear down private aura anchors only when there is private
-- state to clear. Engine-managed private aura visuals can survive encounter
-- cleanup, but a broad aura redraw on every PLAYER_REGEN_ENABLED is wasteful
-- when no private anchors were active.
API._OnCombatLeave = function()
    _FlushPendingRemoveIDs()

    local Store = API.Store
    local CM = API.Cache
    local needsCacheAll = false
    for unit, entry in pairs(AurasByUnit) do
        if API._Render.HasPrivateAuraState(entry, true) then
            PrivateClear(entry)
            entry._lastPrivateGen = nil
            if Store and Store.InvalidateUnit then Store.InvalidateUnit(unit) end
            if CM and CM.Invalidate then
                CM.Invalidate(unit)
            else
                needsCacheAll = true
            end
            MarkDirty(unit, 0)
        end
    end

    if needsCacheAll and CM and CM.InvalidateAll then CM.InvalidateAll() end
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
            if API._Render.HasPrivateAuraState(entry, false) then PrivateClear(entry) end
            Icons = API.Icons or API.Apply
            if Icons then
                Icons.HideUnused(entry.buffs, 1)
                Icons.HideUnused(entry.debuffs, 1)
                Icons.HideUnused(entry.mixed, 1)
            end
            entry._msufA2DisabledClean = true
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
    if shared then UpdateAnchor(entry, shared, (not _inCombat and _G.MSUF_InCombat ~= true) and IsEditModeActive() or false) end
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
