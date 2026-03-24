--[[
MSUF_GF_DB.lua  v10 (perf)
GroupFrames database schema, defaults, override resolution, virtual config.

Perf (v10):
  - FONT_BRIDGE_KEYS / BARS_BRIDGE_KEYS hoisted to file scope (zero alloc per call)
  - ResolveBar/Font/Color batch-read _G.MSUF_DB once at call entry
]]

local addonName, ns = ...
ns = ns or {}

local _G    = _G
local type  = type
local pairs = pairs

local GF = ns.GF or {}
ns.GF = GF

-- ═══════════════════════════════════════════════════════════════
-- Factory Defaults
-- ═══════════════════════════════════════════════════════════════
local PARTY_DEFAULTS = {
    enabled = true, width = 120, height = 36, spacing = 2,
    growDirection = "DOWN", offsetX = -200, offsetY = 100,
    showPlayer = false, showName = true, showHP = true, showPower = true,
    powerBarHeight = 3, overrideBars = false, overrideFont = false,
    overrideColors = false, bars = {}, font = {}, colors = {},
    alphaInCombat = 1, alphaOutOfCombat = 1,
    rangeFadeEnabled = false, rangeFadeAlpha = 0.40,
}

local RAID_DEFAULTS = {
    enabled = true, width = 72, height = 30, spacing = 2,
    growDirection = "DOWN", groupGrowDirection = "RIGHT", groupSpacing = 4,
    offsetX = -300, offsetY = 100, maxColumns = 8, unitsPerColumn = 5,
    showName = true, showHP = false, showPower = false, powerBarHeight = 2,
    overrideBars = false, overrideFont = false, overrideColors = false,
    bars = {}, font = {}, colors = {},
    alphaInCombat = 1, alphaOutOfCombat = 1,
}

-- ═══════════════════════════════════════════════════════════════
-- Merge (cold path only — runs once at DB seed)
-- ═══════════════════════════════════════════════════════════════
local function ShallowMerge(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = {}
                ShallowMerge(dst[k], v)
            else
                dst[k] = v
            end
        elseif type(v) == "table" and type(dst[k]) == "table" then
            ShallowMerge(dst[k], v)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- EnsureGFDB (cold path)
-- ═══════════════════════════════════════════════════════════════
function GF.EnsureDB()
    local db = _G.MSUF_DB
    if not db then
        local fn = _G.EnsureDB
        if type(fn) == "function" then fn() end
        db = _G.MSUF_DB
    end
    if not db then return nil end
    if type(db.groupframes) ~= "table" then db.groupframes = {} end
    local gf = db.groupframes
    if gf.enabled == nil then gf.enabled = true end
    if gf.hideBlizzardFrames == nil then gf.hideBlizzardFrames = true end
    if type(gf.party) ~= "table" then gf.party = {} end
    ShallowMerge(gf.party, PARTY_DEFAULTS)
    if type(gf.raid) ~= "table" then gf.raid = {} end
    ShallowMerge(gf.raid, RAID_DEFAULTS)
    if type(gf.auras) ~= "table" then gf.auras = { enabled = false } end
    return gf
end

-- ═══════════════════════════════════════════════════════════════
-- Config Accessors
-- ═══════════════════════════════════════════════════════════════
function GF.GetPartyConf()
    local db = _G.MSUF_DB
    if not db then GF.EnsureDB(); db = _G.MSUF_DB end
    if not db then return PARTY_DEFAULTS end
    local gf = db.groupframes
    return (type(gf) == "table" and type(gf.party) == "table") and gf.party or PARTY_DEFAULTS
end

function GF.GetRaidConf()
    local db = _G.MSUF_DB
    if not db then GF.EnsureDB(); db = _G.MSUF_DB end
    if not db then return RAID_DEFAULTS end
    local gf = db.groupframes
    return (type(gf) == "table" and type(gf.raid) == "table") and gf.raid or RAID_DEFAULTS
end

function GF.IsEnabled()
    local db = _G.MSUF_DB
    if not db then return false end
    local gf = db.groupframes
    return type(gf) == "table" and (gf.enabled ~= false)
end

function GF.IsPartyEnabled()
    if not GF.IsEnabled() then return false end
    return (GF.GetPartyConf().enabled ~= false)
end

function GF.IsRaidEnabled()
    if not GF.IsEnabled() then return false end
    return (GF.GetRaidConf().enabled ~= false)
end

function GF.ShouldHideBlizzardFrames()
    local db = _G.MSUF_DB
    if not db then return false end
    local gf = db.groupframes
    return type(gf) == "table" and (gf.enabled ~= false) and (gf.hideBlizzardFrames ~= false)
end

-- ═══════════════════════════════════════════════════════════════
-- Override Resolution (single _G.MSUF_DB read per call)
-- ═══════════════════════════════════════════════════════════════
function GF.ResolveBar(gfConf, key)
    if not gfConf or not key then return nil end
    if gfConf.overrideBars then
        local ov = gfConf.bars
        if type(ov) == "table" and ov[key] ~= nil then return ov[key] end
    end
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars
    return type(bars) == "table" and bars[key] or nil
end

function GF.ResolveFont(gfConf, key)
    if not gfConf or not key then return nil end
    if gfConf.overrideFont then
        local ov = gfConf.font
        if type(ov) == "table" and ov[key] ~= nil then return ov[key] end
    end
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    return type(g) == "table" and g[key] or nil
end

function GF.ResolveColor(gfConf, key)
    if not gfConf or not key then return nil end
    if gfConf.overrideColors then
        local ov = gfConf.colors
        if type(ov) == "table" and ov[key] ~= nil then return ov[key] end
    end
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    return type(g) == "table" and g[key] or nil
end

-- ═══════════════════════════════════════════════════════════════
-- Virtual Config Builder
-- PERF: Bridge key tables hoisted to file scope (zero alloc per call)
-- ═══════════════════════════════════════════════════════════════
local _virtualPartyConf = {}
local _virtualRaidConf  = {}

-- PERF: Hoisted — no table creation in BuildVirtualConf
local FONT_BRIDGE_KEYS = {
    "boldText", "noOutline", "textBackdrop",
    "nameClassColor", "npcNameRed", "colorPowerTextByType",
    "shortenNames", "shortenNameMaxChars",
    "shortenNameClipSide", "shortenNameFrontMaskPx",
    "shortenNameShowDots",
}
local BARS_BRIDGE_KEYS = {
    "hpTextMode", "powerTextMode",
    "hpTextSeparator", "powerTextSeparator",
    "absorbTextMode", "absorbAnchorMode",
    "hpTextSpacerEnabled", "hpTextSpacerX",
    "powerTextSpacerEnabled", "powerTextSpacerX",
    "hpTextAnchor", "powerTextAnchor",
}

local function BuildVirtualConf(dst, gfConf, mode)
    for k in pairs(dst) do dst[k] = nil end
    if type(gfConf) ~= "table" then return end

    dst.width            = gfConf.width
    dst.height           = gfConf.height
    dst.showName         = gfConf.showName
    dst.showHP           = gfConf.showHP
    dst.showPower        = gfConf.showPower
    dst.alphaInCombat    = gfConf.alphaInCombat
    dst.alphaOutOfCombat = gfConf.alphaOutOfCombat
    dst.offsetX          = gfConf.offsetX
    dst.offsetY          = gfConf.offsetY
    dst.powerBarHeight   = GF.ResolveBar(gfConf, "powerBarHeight") or gfConf.powerBarHeight
    dst._isGroupFrame    = true
    dst._gfMode          = mode

    -- Bridge font overrides
    if gfConf.overrideFont and type(gfConf.font) == "table" then
        dst.fontOverride = true
        local ft = gfConf.font
        for i = 1, #FONT_BRIDGE_KEYS do
            local fk = FONT_BRIDGE_KEYS[i]
            if ft[fk] ~= nil then dst[fk] = ft[fk] end
        end
    end

    -- Bridge bars overrides
    if gfConf.overrideBars and type(gfConf.bars) == "table" then
        dst.hpPowerTextOverride = true
        local bt = gfConf.bars
        for i = 1, #BARS_BRIDGE_KEYS do
            local bk = BARS_BRIDGE_KEYS[i]
            if bt[bk] ~= nil then dst[bk] = bt[bk] end
        end
    end
end

function GF.RebuildVirtualConfigs()
    BuildVirtualConf(_virtualPartyConf, GF.GetPartyConf(), "party")
    BuildVirtualConf(_virtualRaidConf,  GF.GetRaidConf(),  "raid")
end

function GF.GetVirtualPartyConf() return _virtualPartyConf end
function GF.GetVirtualRaidConf()  return _virtualRaidConf end

_G.MSUF_GF = GF
_G.MSUF_GF_PARTY_DEFAULTS = PARTY_DEFAULTS
_G.MSUF_GF_RAID_DEFAULTS  = RAID_DEFAULTS
