-- ============================================================================
-- MSUF_A2_Collect.lua  Auras 3.0 — Fast-Path Helpers
--
-- Responsibilities:
--   1. Fast-path helpers: GetDurationObjectFast, GetStackCountFast,
--      HasExpirationFast (used by Icons.lua hot path, zero guard overhead)
--   2. Guarded helpers: GetDurationObject, GetStackCount, HasExpiration
--   3. Secret-safe utility exports: SecretsActive, IsBossAura, IsSV
--   4. Store table creation (real methods provided by Cache.lua)
--
-- All aura collection removed — Cache.lua handles everything via
-- delta (sortOrder==0) and C++ sorted (sortOrder!=0) paths.
-- ============================================================================

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
local type = type
local GetTime = GetTime
local C_UnitAuras = C_UnitAuras
local C_Secrets = C_Secrets
ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

if ns.__MSUF_A2_COLLECT_LOADED then return end
ns.__MSUF_A2_COLLECT_LOADED = true

API.Collect = (type(API.Collect) == "table") and API.Collect or {}
local Collect = API.Collect

-- =========================================================================
-- Hot locals
-- =========================================================================
local issecretvalue = _G and _G.issecretvalue
local canaccessvalue = _G and _G.canaccessvalue
local _hasCanaccessvalue = (type(canaccessvalue) == "function")

local _doesExpire, _getDuration, _getStackCount
local _apisBound = false

local function BindAPIs()
    if _apisBound then return end
    if not C_UnitAuras then return end
    _doesExpire    = C_UnitAuras.DoesAuraHaveExpirationTime
    _getDuration   = C_UnitAuras.GetAuraDuration
    _getStackCount = C_UnitAuras.GetAuraApplicationDisplayCount
    _apisBound = true
end

-- =========================================================================
-- Secret-safe helpers
-- =========================================================================

local function IsSV(v)
    if v == nil then return false end
    if issecretvalue then return (issecretvalue(v) == true) end
    return false
end

local _secretActive = nil
local _secretCheckAt = 0

local function SecretsActive()
    local now = GetTime()
    if _secretActive ~= nil and now < _secretCheckAt then
        return _secretActive
    end
    _secretCheckAt = now + 0.5
    local fn = C_Secrets and C_Secrets.ShouldAurasBeSecret
    _secretActive = (type(fn) == "function" and fn() == true) or false
    return _secretActive
end

local function IsBossAura(data)
    if type(data) ~= "table" then return false end
    local f = data._msufA2_bossFlag
    if f ~= nil then return (f == 1) end
    local v = data.isBossAura
    if v == nil then
        data._msufA2_bossFlag = -1
        return false
    end
    if _hasCanaccessvalue then
        if canaccessvalue(v) ~= true then data._msufA2_bossFlag = -1; return false end
    elseif issecretvalue and issecretvalue(v) == true then
        data._msufA2_bossFlag = -1
        return false
    end
    f = (v == true) and 1 or 0
    data._msufA2_bossFlag = f
    return (f == 1)
end

-- =========================================================================
-- Store table (created here; Cache.lua provides real implementations)
-- =========================================================================
API.Store = (type(API.Store) == "table") and API.Store or {}
API.Store._epochs = API.Store._epochs or {}

-- =========================================================================
-- No-op stubs (Render.lua / external addons may still reference these)
-- =========================================================================
Collect.InvalidateCache = function() end
function Collect.SetScanFlags() end
function Collect.SetScanLimits() end
function Collect.SetSortOrder() end
function Collect.SetSortReverse() end
function Collect.SetUnitSortOrder() end

-- =========================================================================
-- Stack count / Duration / Expiration (guarded)
-- =========================================================================

function Collect.GetStackCount(unit, auraInstanceID)
    if not unit or auraInstanceID == nil then return nil end
    if not _apisBound then BindAPIs() end
    if type(_getStackCount) ~= "function" then return nil end
    return _getStackCount(unit, auraInstanceID, 2, 99)
end

function Collect.GetDurationObject(unit, auraInstanceID)
    if not unit or auraInstanceID == nil then return nil end
    if not _apisBound then BindAPIs() end
    if type(_getDuration) ~= "function" then return nil end
    local obj = _getDuration(unit, auraInstanceID)
    if obj ~= nil and type(obj) ~= "number" then return obj end
    return nil
end

function Collect.HasExpiration(unit, auraInstanceID)
    if not unit or auraInstanceID == nil then return nil end
    if not _apisBound then BindAPIs() end
    if type(_doesExpire) ~= "function" then return nil end
    local v = _doesExpire(unit, auraInstanceID)
    if IsSV(v) then return nil end
    if type(v) == "boolean" then return v end
    if type(v) == "number" then return (v > 0) end
    return nil
end

-- =========================================================================
-- Fast-path (no guards — Icons.lua binds after APIs confirmed available)
-- =========================================================================

function Collect.GetDurationObjectFast(unit, aid)
    if not _getDuration then BindAPIs(); if not _getDuration then return nil end end
    local obj = _getDuration(unit, aid)
    if obj ~= nil and type(obj) ~= "number" then return obj end
    return nil
end

function Collect.GetStackCountFast(unit, aid)
    if not _getStackCount then BindAPIs(); if not _getStackCount then return nil end end
    return _getStackCount(unit, aid, 2, 99)
end

function Collect.HasExpirationFast(unit, aid)
    if not _doesExpire then BindAPIs(); if not _doesExpire then return nil end end
    local v = _doesExpire(unit, aid)
    if IsSV(v) then return nil end
    if type(v) == "boolean" then return v end
    if type(v) == "number" then return (v > 0) end
    return nil
end

-- =========================================================================
-- Exports
-- =========================================================================
Collect.SecretsActive = SecretsActive
Collect.IsBossAura = IsBossAura
Collect.IsSV = IsSV
