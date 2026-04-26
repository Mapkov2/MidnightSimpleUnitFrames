-- MSUF_EliteIcon.lua
-- Adds a per-unit elite / rare / rare-elite icon overlay to MSUF unit frames.
-- Follows the same patterns as leaderIcon / raidMarkerIcon.
--
-- DB keys (per-unit, stored in MSUF_DB[unitKey]):
--   showEliteIcon        boolean  default true
--   eliteIconSize        number   default 20
--   eliteIconAnchor      string   "TOPLEFT"|"TOPRIGHT"|"BOTTOMLEFT"|"BOTTOMRIGHT"  default "TOPRIGHT"
--   eliteIconOffsetX     number   default 2
--   eliteIconOffsetY     number   default 2
--
-- Supported units: target, focus, targettarget, boss
-- DB defaults live in Foundation/MSUF_Defaults.lua (canonical location).
-- Frame creation lives in MidnightSimpleUnitFrames.lua (main build loop).
-- Options live in Options/MSUF_Options_Player.lua (eliteicon indicator spec entry).

local addonName, ns = ...
ns = ns or _G.MSUF_NS or {}
_G.MSUF_NS = ns
ns.Icons = ns.Icons or {}

-- ─── atlas names ─────────────────────────────────────────────────────────────
local ATLAS_GOLD   = "nameplates-icon-elite-gold"    -- elite / worldboss
local ATLAS_SILVER = "nameplates-icon-elite-silver"  -- rare / rareelite

-- Units that can show the elite icon (player/pet are never elite NPCs).
-- Exposed via ns so MidnightSimpleUnitFrames.lua can reference it without
-- an addon-global that may collide with other addons.
local VALID_UNITS = { target = true, focus = true, targettarget = true, boss = true }
ns.MSUF_EliteValidUnits = VALID_UNITS

local floor = math.floor

-- ─── Classification → atlas (nil = hide) ─────────────────────────────────────
local function GetEliteAtlas(unit)
    local cls = UnitClassification and UnitClassification(unit)
    if not cls then return nil end
    if cls == "worldboss" or cls == "elite" then
        return ATLAS_GOLD
    elseif cls == "rareelite" or cls == "rare" then
        return ATLAS_SILVER
    end
    return nil
end

-- ─── Apply layout with stamp/diff gating ─────────────────────────────────────
-- Called from MSUF_ApplyEliteIconLayout (settings panel refresh) and from
-- UpdateEliteIcon whenever the icon needs to be shown.
-- Uses the same ns.Icons._layout helpers as leaderIcon / raidMarkerIcon.
local function ApplyLayout(f)
    local icon = f.eliteIcon
    if not icon then return end

    local g, key, conf = ns.Icons._layout.GetConf(f)
    if not conf or not VALID_UNITS[key] then return end

    local size   = floor(math.max(8, math.min(64,
        (ns.Util and ns.Util.Num and ns.Util.Num(conf, g, "eliteIconSize", 20)) or 20)) + 0.5)
    local ox     = (ns.Util and ns.Util.Num and ns.Util.Num(conf, g, "eliteIconOffsetX", 2)) or 2
    local oy     = (ns.Util and ns.Util.Num and ns.Util.Num(conf, g, "eliteIconOffsetY", 2)) or 2
    local anchor = (ns.Util and ns.Util.Val and ns.Util.Val(conf, g, "eliteIconAnchor", "TOPRIGHT")) or "TOPRIGHT"

    -- Stamp gate: skip ClearAllPoints/SetPoint/SetSize when nothing changed.
    if ns.Cache and ns.Cache.StampChanged and
       not ns.Cache.StampChanged(f, "EliteIconLayout", size, ox, oy, anchor, (key or "")) then
        return
    end
    f._msufEliteIconLayoutStamp = 1

    local point, relPoint = ns.Icons._layout.Resolve(anchor, false)
    ns.Icons._layout.Apply(icon, f, size, point, relPoint, ox, oy)
end

-- ─── Update visibility + atlas for a single frame ────────────────────────────
-- Called from MSUF_UnitframeCore.lua indicator path (mirrors leaderIcon / raidMarkerIcon).
-- Gates SetAtlas via a per-frame cache to avoid redundant calls every update.
local function UpdateEliteIcon(f)
    local icon = f.eliteIcon
    if not icon then return end

    local g, key, conf = ns.Icons._layout.GetConf(f)
    if not conf or not VALID_UNITS[key] then icon:Hide(); return end

    if conf.showEliteIcon == false then icon:Hide(); return end

    local unit = f.unit
    if not unit or not UnitExists(unit) then icon:Hide(); return end

    local atlas = GetEliteAtlas(unit)
    if not atlas then icon:Hide(); return end

    -- SetAtlas only when the atlas value actually changes.
    if f._msufEliteIconAtlas ~= atlas then
        f._msufEliteIconAtlas = atlas
        icon:SetAtlas(atlas)  -- SetAtlas without useAtlasSize; we control size via ApplyLayout.
    end

    ApplyLayout(f)
    icon:Show()
end

-- ─── Public API ───────────────────────────────────────────────────────────────

-- Called from settings-change refresh path (equivalent to MSUF_ApplyLeaderIconLayout).
function MSUF_ApplyEliteIconLayout(f)
    if not (f and f.eliteIcon) then return end
    ApplyLayout(f)
    UpdateEliteIcon(f)
end
_G.MSUF_ApplyEliteIconLayout = MSUF_ApplyEliteIconLayout

-- Called from MSUF_UnitframeCore.lua indicator update path.
function MSUF_UpdateEliteIcon(f)
    UpdateEliteIcon(f)
end
_G.MSUF_UpdateEliteIcon = MSUF_UpdateEliteIcon
-- Note: MSUF_RefreshEliteIconFrames is defined in Options/MSUF_Options_Player.lua
-- alongside MSUF_RefreshLeaderIconFrames / MSUF_RefreshRaidMarkerFrames, using
-- the same MSUF_GetUnitFrameToken / MSUF_RefreshFrames helpers.