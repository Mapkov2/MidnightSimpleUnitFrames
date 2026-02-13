-- ============================================================================
-- MSUF_A2_Render.lua — Auras 3.0 Orchestrator
-- Replaces the 3357-line monolith.
--
-- Responsibilities:
--   - Dirty queue + coalesced flush (OnUpdate driver)
--   - RenderUnit: collect → commit → layout (single pass)
--   - Config resolution + caching (cold path, invalidated on DB change)
--   - Private aura anchor management
--   - Edit Mode mover integration
--   - Public API surface (RefreshAll, RefreshUnit, MarkDirty, etc.)
--
-- NOT in this file: icon creation/visuals (Icons.lua), event wiring (Events.lua)
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

-- FastCall: no pcall in hot paths
local function MSUF_A2_FastCall(fn, ...)
    if fn == nil then return false end
    return true, fn(...)
end
_G.MSUF_A2_FastCall = MSUF_A2_FastCall

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

-- ────────────────────────────────────────────────────────────────
-- Hot locals
-- ────────────────────────────────────────────────────────────────
local type = type
local pairs = pairs
local CreateFrame = CreateFrame
local GetTime = GetTime
local UnitExists = UnitExists
local floor = math.floor
local max = math.max

-- Module references (late-bound)
local Collect  -- API.Collect
local Icons    -- API.Icons / API.Apply
local Store    -- API.Store (epoch only)
local Filters  -- API.Filters

-- ────────────────────────────────────────────────────────────────
-- Combat / Edit Mode state (cheap cached checks)
-- ────────────────────────────────────────────────────────────────
local _inCombat = false
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_, event)
        _inCombat = (event == "PLAYER_REGEN_DISABLED")
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
    if type(st) == "table" and st.active == true then active = true end
    if not active and rawget(_G, "MSUF_UnitEditModeActive") == true then active = true end
    if not active then
        local fn = rawget(_G, "MSUF_IsInEditMode")
        if type(fn) == "function" then
            local ok, v = MSUF_A2_FastCall(fn)
            if ok and v == true then active = true end
        end
    end

    _editModeActive = active
    return active
end

API.IsEditModeActive = IsEditModeActive

-- ────────────────────────────────────────────────────────────────
-- DB access + config cache
-- ────────────────────────────────────────────────────────────────
local MSUF_DB

-- DB defaults (copied from original Render — must stay identical for migration compat)
local A2_AURAS2_DEFAULTS = { enabled=true, showTarget=true, showFocus=true, showBoss=true, showPlayer=false }
local A2_SHARED_DEFAULTS = {
    showBuffs=true, showDebuffs=true, showTooltip=true,
    showCooldownSwipe=true, showCooldownText=true, cooldownSwipeDarkenOnLoss=false,
    showInEditMode=true, showStackCount=true,
    stackCountAnchor="TOPRIGHT", masqueEnabled=false, masqueHideBorder=false,
    layoutMode="SEPARATE", buffDebuffAnchor="STACKED", splitSpacing=0,
    highlightPrivatePlayerAuras=false, highlightOwnBuffs=false, highlightOwnDebuffs=false,
    iconSize=26, spacing=2, perRow=12, maxIcons=12,
    growth="RIGHT", rowWrap="DOWN",
    offsetX=0, offsetY=6, buffOffsetY=30,
    stackTextSize=14, cooldownTextSize=14, bossEditTogether=true,
    showPrivateAurasPlayer=true, showPrivateAurasFocus=true, showPrivateAurasBoss=true,
    privateAuraMaxPlayer=4, privateAuraMaxOther=4,
}

local A2_GROWTH_OK = {RIGHT=true,LEFT=true,UP=true,DOWN=true}
local A2_ROWWRAP_OK = {DOWN=true,UP=true}
local A2_LAYOUTMODE_OK = {SEPARATE=true,SINGLE=true}
local A2_STACKANCHOR_OK = {TOPRIGHT=true,TOPLEFT=true,BOTTOMRIGHT=true,BOTTOMLEFT=true}

local function DefaultKV(t, d) for k, v in pairs(d) do if t[k] == nil then t[k] = v end end end
local function Clamp(v, def, lo, hi) v = tonumber(v); if not v then v = def end; if lo and v < lo then v = lo end; if hi and v > hi then v = hi end; return v end

local function EnsureDB()
    local gdb = _G.MSUF_DB
    if type(gdb) ~= "table" then _G.MSUF_DB = {}; gdb = _G.MSUF_DB end
    if type(_G.EnsureDB) == "function" then MSUF_A2_FastCall(_G.EnsureDB) end
    MSUF_DB = _G.MSUF_DB
    if type(MSUF_DB) ~= "table" then return nil end

    if type(MSUF_DB.auras2) ~= "table" then MSUF_DB.auras2 = {} end
    local a2 = MSUF_DB.auras2
    DefaultKV(a2, A2_AURAS2_DEFAULTS)

    if type(a2.shared) ~= "table" then a2.shared = {} end
    local s = a2.shared
    DefaultKV(s, A2_SHARED_DEFAULTS)

    if s.maxBuffs == nil then s.maxBuffs = s.maxIcons or 12 end
    if s.maxDebuffs == nil then s.maxDebuffs = s.maxIcons or 12 end
    s.showPrivateAurasTarget = false
    s.privateAuraMaxPlayer = Clamp(s.privateAuraMaxPlayer, 4, 0, 12)
    s.privateAuraMaxOther  = Clamp(s.privateAuraMaxOther,  4, 0, 12)

    -- Filters
    Filters = API.Filters
    if Filters and Filters.EnsureSharedFilters then
        Filters.EnsureSharedFilters(a2, s)
    end

    -- Per-unit config
    if type(a2.perUnit) ~= "table" then a2.perUnit = {} end

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

local function InvalidateDB()
    _ensureReady = false
    _lastDB = nil
    _configGen = _configGen + 1
    _modulesBound = false  -- re-bind modules on next RenderUnit (picks up late-loaded modules)
    if API.DB and API.DB.InvalidateCache then API.DB.InvalidateCache() end
    if API.Colors and API.Colors.InvalidateCache then API.Colors.InvalidateCache() end
    Icons = API.Icons or API.Apply
    if Icons and Icons.BumpConfigGen then Icons.BumpConfigGen() end
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

-- ────────────────────────────────────────────────────────────────
-- Per-unit state
-- ────────────────────────────────────────────────────────────────
A2_STATE.aurasByUnit = (type(A2_STATE.aurasByUnit) == "table") and A2_STATE.aurasByUnit or {}
local AurasByUnit = A2_STATE.aurasByUnit

local _IS_BOSS = { boss1=true, boss2=true, boss3=true, boss4=true, boss5=true }

local function FindUnitFrame(unit)
    local uf = _G.MSUF_UnitFrames
    if type(uf) == "table" and uf[unit] then return uf[unit] end
    return _G["MSUF_" .. unit]
end

API.FindUnitFrame = FindUnitFrame

local function UnitEnabled(a2, unit)
    if not a2 or a2.enabled ~= true then return false end
    if unit == "player" then return a2.showPlayer == true end
    if unit == "target" then return a2.showTarget == true end
    if unit == "focus" then return a2.showFocus == true end
    if _IS_BOSS[unit] then return a2.showBoss == true end
    return false
end

-- ────────────────────────────────────────────────────────────────
-- Dirty queue + flush driver
-- ────────────────────────────────────────────────────────────────
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

local function StopFlushDriver()
    _flushNextAt = nil
    _flushDriver:SetScript("OnUpdate", nil)
    _flushDriver:Hide()
end

local function FlushDriverOnUpdate()
    local at = _flushNextAt
    if not at then StopFlushDriver(); return end
    local now = GetTime()
    A2_STATE.now = now
    if now >= at then
        _flushNextAt = nil
        if Flush then Flush() end
    end
end

local function ScheduleFlush(delay)
    if not delay or delay < 0 then delay = 0 end
    local now = GetTime()
    local at = now + delay
    if (not _flushNextAt) or at < _flushNextAt then
        _flushNextAt = at
    end
    if not _flushDriver:GetScript("OnUpdate") then
        _flushDriver:Show()
        _flushDriver:SetScript("OnUpdate", FlushDriverOnUpdate)
    end
end

-- ────────────────────────────────────────────────────────────────
-- MarkDirty (public entry point for scheduling unit updates)
-- ────────────────────────────────────────────────────────────────

local function MarkDirty(unit, delay)
    if not unit then return end

    -- Early dedupe
    if DirtyMark[unit] == DirtyGen then
        if FlushScheduled then ScheduleFlush(delay or 0) end
        return
    end

    -- Gate: skip disabled/nonexistent units (not in edit mode preview)
    local a2, shared = GetAuras2DB()
    local allowPreview = (shared and shared.showInEditMode == true and IsEditModeActive())

    if not allowPreview then
        if not UnitEnabled(a2, unit) then return end
        if UnitExists and not UnitExists(unit) then return end
    end

    DirtyAdd(unit)
    if not delay or delay < 0 then delay = 0 end
    FlushScheduled = true
    ScheduleFlush(delay)
end

-- ────────────────────────────────────────────────────────────────
-- EnsureAttached: create per-unit anchor + container frames
-- ────────────────────────────────────────────────────────────────

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

    -- Sync visibility with parent unitframe
    local ok1, _ = MSUF_A2_FastCall(frame.HookScript, frame, "OnShow", function()
        if anchor then anchor:Show() end
        if API.MarkAllDirty then API.MarkAllDirty(0) end
    end)
    local ok2, _ = MSUF_A2_FastCall(frame.HookScript, frame, "OnHide", function()
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
        -- Reusable list buffers (zero alloc on steady state)
        _buffList = {},
        _debuffList = {},
        _mergeList = {},
        -- Last rendered state for diff
        _lastBuffAids = {},
        _lastDebuffAids = {},
        _lastBuffCount = 0,
        _lastDebuffCount = 0,
        _lastEpoch = -1,
        _lastConfigGen = -1,
        _lastAnchorGen = -1,
        _lastPrivateGen = -1,
    }
    AurasByUnit[unit] = entry
    return entry
end

-- ────────────────────────────────────────────────────────────────
-- Config resolution (pre-computed per InvalidateDB, not per render)
-- ────────────────────────────────────────────────────────────────

local function ResolveUnitConfig(unit, a2, shared)
    local iconSize = shared.iconSize or 26
    local spacing = shared.spacing or 2
    local perRow = shared.perRow or 12
    local maxBuffs = shared.maxBuffs or shared.maxIcons or 12
    local maxDebuffs = shared.maxDebuffs or shared.maxIcons or 12
    local growth = shared.growth or "RIGHT"
    local rowWrap = shared.rowWrap or "DOWN"
    local layoutMode = shared.layoutMode or "SEPARATE"
    local stackCountAnchor = shared.stackCountAnchor or "TOPRIGHT"

    -- Per-unit overrides
    local pu = a2.perUnit and a2.perUnit[unit]
    if pu and pu.overrideSharedLayout == true and type(pu.layoutShared) == "table" then
        local ls = pu.layoutShared
        if type(ls.perRow) == "number" and ls.perRow >= 1 then perRow = ls.perRow end
        if type(ls.maxBuffs) == "number" then maxBuffs = ls.maxBuffs end
        if type(ls.maxDebuffs) == "number" then maxDebuffs = ls.maxDebuffs end
        if ls.growth and A2_GROWTH_OK[ls.growth] then growth = ls.growth end
        if ls.rowWrap and A2_ROWWRAP_OK[ls.rowWrap] then rowWrap = ls.rowWrap end
        if ls.layoutMode and A2_LAYOUTMODE_OK[ls.layoutMode] then layoutMode = ls.layoutMode end
        if ls.stackCountAnchor and A2_STACKANCHOR_OK[ls.stackCountAnchor] then stackCountAnchor = ls.stackCountAnchor end
    end
    if pu and pu.overrideLayout == true and type(pu.layout) == "table" then
        local lay = pu.layout
        if type(lay.iconSize) == "number" and lay.iconSize > 1 then iconSize = lay.iconSize end
        if type(lay.spacing) == "number" and lay.spacing >= 0 then spacing = lay.spacing end
    end

    return iconSize, spacing, perRow, maxBuffs, maxDebuffs, growth, rowWrap, layoutMode, stackCountAnchor
end

-- ────────────────────────────────────────────────────────────────
-- Private Auras (Blizzard-rendered)
-- ────────────────────────────────────────────────────────────────

local function PrivateAurasSupported()
    return C_UnitAuras
        and type(C_UnitAuras.AddPrivateAuraAnchor) == "function"
        and type(C_UnitAuras.RemovePrivateAuraAnchor) == "function"
end

local function PrivateClear(entry)
    if not entry then return end
    local ids = entry._privateAnchorIDs
    if type(ids) == "table" and C_UnitAuras then
        for i = 1, #ids do
            if ids[i] then MSUF_A2_FastCall(C_UnitAuras.RemovePrivateAuraAnchor, ids[i]) end
        end
    end
    entry._privateAnchorIDs = nil
    entry._privateSig = nil
    local slots = entry._privateSlots
    if type(slots) == "table" then
        for i = 1, #slots do if slots[i] then slots[i]:Hide() end end
    end
    if entry.private then entry.private:Hide() end
end

local function PrivateRebuild(entry, shared, iconSize, spacing)
    if not entry or not shared then return end
    local unit = entry.unit

    local enabled = false
    if unit == "player" then enabled = (shared.showPrivateAurasPlayer == true)
    elseif unit == "focus" then enabled = (shared.showPrivateAurasFocus == true)
    elseif _IS_BOSS[unit] then enabled = (shared.showPrivateAurasBoss == true)
    end

    if not enabled or not PrivateAurasSupported() then
        PrivateClear(entry)
        return
    end

    local maxN = (unit == "player") and (shared.privateAuraMaxPlayer or 4) or (shared.privateAuraMaxOther or 4)
    maxN = Clamp(maxN, 4, 0, 12)
    if maxN == 0 then PrivateClear(entry); return end

    -- Effective unit token (focus→player if focus IS player)
    local effectiveToken = unit
    if unit ~= "player" and UnitIsUnit and UnitIsUnit(unit, "player") then
        effectiveToken = "player"
    end

    -- Signature to avoid rebuilding when nothing changed
    local sig = unit .. "|" .. effectiveToken .. "|" .. iconSize .. "|" .. spacing .. "|" .. maxN
    if entry._privateSig == sig and type(entry._privateAnchorIDs) == "table" then
        if entry.private then entry.private:Show() end
        return
    end

    PrivateClear(entry)
    if not entry.private then return end

    local slots = entry._privateSlots or {}
    entry._privateSlots = slots
    local step = iconSize + spacing
    if step <= 0 then step = 28 end

    entry.private:Show()
    entry._privateSig = sig
    entry._privateAnchorIDs = {}
    entry.private:SetSize((maxN * step) - spacing, iconSize)

    -- Reuse args table (avoid allocation per slot)
    local args = entry._privateArgs
    if not args then
        args = {
            unitToken = effectiveToken,
            auraIndex = 1,
            parent = nil,
            showCountdownFrame = false,
            showCountdownNumbers = false,
            iconInfo = {
                iconWidth = iconSize,
                iconHeight = iconSize,
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
            slots[i] = slot
        end
        slot:ClearAllPoints()
        slot:SetPoint("BOTTOMLEFT", entry.private, "BOTTOMLEFT", (i - 1) * step, 0)
        slot:SetSize(iconSize, iconSize)
        slot:Show()

        -- Update reused args
        args.unitToken = effectiveToken
        args.auraIndex = i
        args.parent = slot
        args.showCountdownFrame = (shared.showCooldownSwipe == true)
        args.showCountdownNumbers = (shared.showCooldownText == true)
        args.iconInfo.iconWidth = iconSize
        args.iconInfo.iconHeight = iconSize
        args.iconInfo.iconAnchor.relativeTo = slot

        local ok, anchorID = MSUF_A2_FastCall(C_UnitAuras.AddPrivateAuraAnchor, args)
        if ok and anchorID then
            entry._privateAnchorIDs[#entry._privateAnchorIDs + 1] = anchorID
        end
    end
end

-- ────────────────────────────────────────────────────────────────
-- UpdateAnchor (position the aura container relative to unitframe)
-- ────────────────────────────────────────────────────────────────

-- ── File-scope helpers for UpdateAnchor (zero closure alloc) ──

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

    -- Buff/Debuff separation (buffOffsetY)
    local buffOffsetY = shared.buffOffsetY
    if lay and type(lay.buffOffsetY) == "number" then buffOffsetY = lay.buffOffsetY end
    if type(buffOffsetY) ~= "number" then buffOffsetY = iconSize + spacing + 4 end

    -- ── Per-group offsets (drag movers write to these) ──
    local buffDX   = ReadOffset(shared, lay, "buffGroupOffsetX",   0)
    local buffDY   = ReadOffset(shared, lay, "buffGroupOffsetY",   0)
    local debuffDX = ReadOffset(shared, lay, "debuffGroupOffsetX", 0)
    local debuffDY = ReadOffset(shared, lay, "debuffGroupOffsetY", 0)
    local privOffX = ReadOffset(shared, lay, "privateOffsetX",     0)
    local privOffY = ReadOffset(shared, lay, "privateOffsetY",     0)

    -- Layout mode
    local layoutMode = shared.layoutMode or "SEPARATE"
    local lsOvr = (pu and pu.overrideSharedLayout == true and type(pu.layoutShared) == "table") and pu.layoutShared or nil
    if lsOvr and lsOvr.layoutMode and A2_LAYOUTMODE_OK[lsOvr.layoutMode] then layoutMode = lsOvr.layoutMode end

    -- Edit Mode QoL: ensure min separation so movers don't overlap
    if isEditActive then
        local minSep = iconSize + spacing + 8
        if buffOffsetY < minSep then buffOffsetY = minSep end
        local hasPrivOverride = (lay and (lay.privateOffsetX ~= nil or lay.privateOffsetY ~= nil))
        if not hasPrivOverride then
            privOffY = buffOffsetY + minSep
        end
    end

    -- ── Position anchor ──
    local anchor = entry.anchor
    anchor:ClearAllPoints()
    anchor:SetPoint("BOTTOMLEFT", entry.frame, "TOPLEFT", offX, offY)

    -- ── Position containers ──
    if layoutMode == "SINGLE" and entry.mixed then
        entry.mixed:ClearAllPoints()
        entry.mixed:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
        entry.debuffs:ClearAllPoints()
        entry.debuffs:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
        entry.buffs:ClearAllPoints()
        entry.buffs:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
    else
        entry.debuffs:ClearAllPoints()
        entry.debuffs:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", debuffDX, debuffDY)

        entry.buffs:ClearAllPoints()
        entry.buffs:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", buffDX, buffOffsetY + buffDY)

        if entry.mixed then
            entry.mixed:ClearAllPoints()
            entry.mixed:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
        end
    end

    -- Private
    if entry.private then
        entry.private:ClearAllPoints()
        entry.private:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", privOffX, privOffY)
    end

    -- ── Position edit movers (mirror containers) ──
    if isEditActive then
        local step = iconSize + spacing
        local maxBuff = (shared.maxBuffs or shared.maxIcons or 12)
        local maxDebuff = (shared.maxDebuffs or shared.maxIcons or 12)
        local cols = (maxBuff < perRow) and maxBuff or perRow
        local dcols = (maxDebuff < perRow) and maxDebuff or perRow
        local headerH = 20

        MirrorMover(entry.editMoverBuff,    entry.buffs,   anchor, cols * step,  iconSize + headerH)
        MirrorMover(entry.editMoverDebuff,  entry.debuffs, anchor, dcols * step, iconSize + headerH)
        MirrorMover(entry.editMoverPrivate, entry.private, anchor, 4 * step,     iconSize + headerH)
    end
end

-- Pre-cached boss unit strings (avoid "boss"..i concatenation in loops)
local _BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }

-- Module binding flag (set once, reset only on hard reload)
local _modulesBound = false

-- ────────────────────────────────────────────────────────────────
-- RenderUnit — the core render loop (single pass, clean)
-- ────────────────────────────────────────────────────────────────

local function RenderUnit(entry)
    if not entry then return end

    -- Bind modules once
    if not _modulesBound then
        Collect = API.Collect
        Icons   = API.Icons or API.Apply
        Store   = API.Store
        Filters = API.Filters
        if Collect and Icons then _modulesBound = true end
    end

    if not Collect or not Icons then return end

    local unit = entry.unit
    local a2, shared = GetAuras2DB()
    if not a2 or not shared then return end

    -- ── Cache resolved config per configGen (eliminates ~40 table reads per aura event) ──
    local cfg = entry._cfg
    if not cfg then
        cfg = { _gen = -1 }
        entry._cfg = cfg
    end

    local gen = _configGen
    if cfg._gen ~= gen then
        cfg._gen = gen

        -- Layout config (9 values)
        cfg.iconSize, cfg.spacing, cfg.perRow, cfg.maxBuffs, cfg.maxDebuffs,
        cfg.growth, cfg.rowWrap, cfg.layoutMode, cfg.stackCountAnchor =
            ResolveUnitConfig(unit, a2, shared)

        -- Filter flags (8 values)
        if Filters and Filters.ResolveRuntimeFlags then
            cfg.tf, cfg.masterOn, cfg.onlyBossAuras, cfg.buffsOnlyMine, cfg.debuffsOnlyMine,
            cfg.buffsIncludeBoss, cfg.debuffsIncludeBoss, cfg.hidePermanentBuffs =
                Filters.ResolveRuntimeFlags(a2, shared, unit)
        else
            cfg.tf = nil
            cfg.masterOn = false
            cfg.onlyBossAuras = false
            cfg.buffsOnlyMine = false
            cfg.debuffsOnlyMine = false
            cfg.buffsIncludeBoss = false
            cfg.debuffsIncludeBoss = false
            cfg.hidePermanentBuffs = false
        end

        -- Display flags
        cfg.showBuffs = (shared.showBuffs == true)
        cfg.showDebuffs = (shared.showDebuffs == true)
        cfg.needPlayerAura = (shared.highlightOwnBuffs == true) or (shared.highlightOwnDebuffs == true)
        cfg.useSingleRow = (cfg.layoutMode == "SINGLE")
    end

    -- Local aliases for hot-path values
    local iconSize          = cfg.iconSize
    local spacing           = cfg.spacing
    local perRow            = cfg.perRow
    local maxBuffs          = cfg.maxBuffs
    local maxDebuffs        = cfg.maxDebuffs
    local growth            = cfg.growth
    local rowWrap           = cfg.rowWrap
    local stackCountAnchor  = cfg.stackCountAnchor
    local showBuffs         = cfg.showBuffs
    local showDebuffs       = cfg.showDebuffs
    local useSingleRow      = cfg.useSingleRow
    local needPlayerAura    = cfg.needPlayerAura
    local masterOn          = cfg.masterOn

    -- ── Early bail: no unit, no edit mode → nothing to render ──
    local unitExists = UnitExists and UnitExists(unit)
    local isEditActive = (not _inCombat) and IsEditModeActive() or false

    if not unitExists and not isEditActive then
        Icons.HideUnused(entry.debuffs, 1)
        Icons.HideUnused(entry.buffs, 1)
        if entry.mixed then Icons.HideUnused(entry.mixed, 1) end
        entry.anchor:Hide()
        return
    end

    -- ── Edit Mode: create movers before anchoring so UpdateAnchor can position them ──
    local EditMode = isEditActive and API.EditMode or nil
    if EditMode and EditMode.EnsureMovers then
        EditMode.EnsureMovers(entry, unit, shared, iconSize, spacing)
    end

    -- Anchor: only reposition when config changes (configGen bumped) or edit mode active
    if gen ~= entry._lastAnchorGen or isEditActive then
        UpdateAnchor(entry, shared, isEditActive)
        entry._lastAnchorGen = gen
    end
    entry.anchor:Show()

    -- Private auras: only rebuild when config changes
    if gen ~= entry._lastPrivateGen then
        PrivateRebuild(entry, shared, iconSize, spacing)
        entry._lastPrivateGen = gen
    end

    -- ── Edit Mode: show/hide movers (skip entirely in combat) ──
    if not _inCombat then
        if EditMode then
            if EditMode.ShowMovers then EditMode.ShowMovers(entry) end
        else
            local EM = API.EditMode
            if EM and EM.HideMovers then EM.HideMovers(entry) end
        end
    end

    local showTest = (shared.showInEditMode == true and isEditActive)

    if showTest then
        if entry.buffs then entry.buffs:Show() end
        if entry.debuffs then entry.debuffs:Show() end
        if entry.mixed then entry.mixed:Show() end
        if entry.private then entry.private:Show() end
        entry._msufA2_previewActive = true
    else
        entry._msufA2_previewActive = nil
    end

    -- ── Edit Mode preview (no real unit present) ──
    if showTest and not unitExists then
        if Icons.RenderPreviewIcons then
            local bc, dc = Icons.RenderPreviewIcons(entry, unit, shared, useSingleRow, maxBuffs, maxDebuffs, stackCountAnchor)
            Icons.LayoutIcons(entry.buffs, bc or 0, iconSize, spacing, perRow, growth, rowWrap)
            Icons.LayoutIcons(entry.debuffs, dc or 0, iconSize, spacing, perRow, growth, rowWrap)
        end
        if Icons.RenderPreviewPrivateIcons then
            Icons.RenderPreviewPrivateIcons(entry, unit, shared, iconSize, spacing, stackCountAnchor)
        end
        return
    end

    if not unitExists then
        Icons.HideUnused(entry.debuffs, 1)
        Icons.HideUnused(entry.buffs, 1)
        entry.anchor:Hide()
        return
    end

    -- ── Epoch diff: skip full rebuild if nothing changed ──
    local epoch = Store and Store.GetEpoch(unit) or 0

    if epoch == entry._lastEpoch and gen == entry._lastConfigGen then
        -- Nothing changed — just refresh timers and stacks
        Icons.RefreshAssignedIcons(entry, unit, shared, stackCountAnchor)
        return
    end

    entry._lastEpoch = epoch
    entry._lastConfigGen = gen

    -- ── Collect auras (single pass) ──
    local buffCount = 0
    local debuffCount = 0
    local buffsOnlyMine    = cfg.buffsOnlyMine
    local debuffsOnlyMine  = cfg.debuffsOnlyMine
    local buffsIncludeBoss = cfg.buffsIncludeBoss
    local debuffsIncludeBoss = cfg.debuffsIncludeBoss
    local onlyBossAuras    = cfg.onlyBossAuras
    local hidePermanentBuffs = cfg.hidePermanentBuffs

    if showDebuffs then
        local list
        if debuffsOnlyMine and debuffsIncludeBoss then
            list, debuffCount = Collect.GetMergedAuras(unit, "HARMFUL", maxDebuffs, false, entry._debuffList, entry._mergeList, needPlayerAura)
        else
            list, debuffCount = Collect.GetAuras(unit, "HARMFUL", maxDebuffs, debuffsOnlyMine, false, onlyBossAuras, entry._debuffList, needPlayerAura)
        end

        local container = useSingleRow and entry.mixed or entry.debuffs
        for i = 1, debuffCount do
            local aura = list[i]
            if aura then
                local icon = Icons.AcquireIcon(container, i)
                Icons.CommitIcon(icon, unit, aura, shared, false, false, masterOn, aura._msufIsPlayerAura, stackCountAnchor, gen)
            end
        end
    end

    if showBuffs then
        local list
        if buffsOnlyMine and buffsIncludeBoss then
            list, buffCount = Collect.GetMergedAuras(unit, "HELPFUL", maxBuffs, hidePermanentBuffs, entry._buffList, entry._mergeList, needPlayerAura)
        else
            list, buffCount = Collect.GetAuras(unit, "HELPFUL", maxBuffs, buffsOnlyMine, hidePermanentBuffs, onlyBossAuras, entry._buffList, needPlayerAura)
        end

        local container = useSingleRow and entry.mixed or entry.buffs
        local offset = useSingleRow and debuffCount or 0
        for i = 1, buffCount do
            local aura = list[i]
            if aura then
                local icon = Icons.AcquireIcon(container, offset + i)
                Icons.CommitIcon(icon, unit, aura, shared, true, hidePermanentBuffs, masterOn, aura._msufIsPlayerAura, stackCountAnchor, gen)
            end
        end
    end

    -- ── Layout ──
    if useSingleRow and entry.mixed then
        local total = debuffCount + buffCount
        Icons.LayoutIcons(entry.mixed, total, iconSize, spacing, perRow, growth, rowWrap)
        Icons.HideUnused(entry.mixed, total + 1)
        Icons.HideUnused(entry.debuffs, 1)
        Icons.HideUnused(entry.buffs, 1)
    else
        if showDebuffs then
            Icons.LayoutIcons(entry.debuffs, debuffCount, iconSize, spacing, perRow, growth, rowWrap)
            Icons.HideUnused(entry.debuffs, debuffCount + 1)
        else
            Icons.HideUnused(entry.debuffs, 1)
        end

        if showBuffs then
            Icons.LayoutIcons(entry.buffs, buffCount, iconSize, spacing, perRow, growth, rowWrap)
            Icons.HideUnused(entry.buffs, buffCount + 1)
        else
            Icons.HideUnused(entry.buffs, 1)
        end

        if entry.mixed then Icons.HideUnused(entry.mixed, 1) end
    end

    entry._lastBuffCount = buffCount
    entry._lastDebuffCount = debuffCount
end

-- ────────────────────────────────────────────────────────────────
-- Flush
-- ────────────────────────────────────────────────────────────────

Flush = function()
    local now = GetTime()
    A2_STATE.now = now
    _isFlushing = true
    _dirtyWhileFlushing = false
    FlushScheduled = true

    local list, count = DirtySwap()
    local a2, shared = GetAuras2DB()
    local showTest = (shared and shared.showInEditMode == true and IsEditModeActive())

    for i = 1, count do
        local unit = list[i]
        local frame = FindUnitFrame(unit)

        -- Fast path: should we render?
        local shouldRender = frame
            and (showTest or (UnitEnabled(a2, unit) and frame:IsShown() and (not UnitExists or UnitExists(unit))))

        if shouldRender then
            local e = EnsureAttached(unit)
            if e then RenderUnit(e) end
        else
            -- Hide anchor if it exists
            local entry = AurasByUnit[unit]
            if entry and entry.anchor then entry.anchor:Hide() end
        end
    end

    _isFlushing = false

    if _dirtyWhileFlushing then
        ScheduleFlush(0)
    end

    if DirtyCount == 0 then
        FlushScheduled = false
        StopFlushDriver()
    end
end

-- ────────────────────────────────────────────────────────────────
-- Public API
-- ────────────────────────────────────────────────────────────────

local function MarkAllDirty(delay)
    local DB = API.DB
    local c = DB and DB.cache
    local ue = c and c.unitEnabled
    if ue then
        if ue.player then MarkDirty("player", delay) end
        if ue.target then MarkDirty("target", delay) end
        if ue.focus then MarkDirty("focus", delay) end
        for i = 1, 5 do
            if ue[_BOSS_UNITS[i]] then MarkDirty(_BOSS_UNITS[i], delay) end
        end
    else
        MarkDirty("player", delay)
        MarkDirty("target", delay)
        MarkDirty("focus", delay)
        for i = 1, 5 do MarkDirty(_BOSS_UNITS[i], delay) end
    end
end

local function RefreshAll()
    _configGen = _configGen + 1
    if Icons and Icons.BumpConfigGen then Icons.BumpConfigGen() end

    local Store = API.Store
    if Store and Store.InvalidateUnit then
        Store.InvalidateUnit("player")
        Store.InvalidateUnit("target")
        Store.InvalidateUnit("focus")
        for i = 1, 5 do Store.InvalidateUnit(_BOSS_UNITS[i]) end
    end
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

-- ────────────────────────────────────────────────────────────────
-- ClearAllPreviews (called by Events when leaving Edit Mode)
-- ────────────────────────────────────────────────────────────────

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
            icon:Hide()
        end
    end
end

local function ClearAllPreviews()
    Icons = API.Icons or API.Apply
    if not Icons then return end

    for _, entry in pairs(AurasByUnit) do
        if entry then
            _ClearPreviewContainer(entry.buffs)
            _ClearPreviewContainer(entry.debuffs)
            _ClearPreviewContainer(entry.mixed)
        end
    end
end

API.ClearAllPreviews = ClearAllPreviews

-- Register on API
API.MarkDirty = MarkDirty
API.MarkAllDirty = MarkAllDirty
API.RefreshAll = RefreshAll
API.RefreshUnit = RefreshUnit
API.RequestUnit = function(unit, delay) MarkDirty(unit, delay) end
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

-- ────────────────────────────────────────────────────────────────
-- Init: prime DB + kick off events
-- ────────────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────
-- API bridge for Options / EditMode / Fonts
-- ────────────────────────────────────────────────────────────────
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
end

-- Deferred auto-init: if Events already loaded, Init now; otherwise Events.lua calls API.Init() at its tail
if API.Events and API.Events.Init then
    API.Init()
end
