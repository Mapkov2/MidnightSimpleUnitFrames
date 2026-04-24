-- MSUF_EliteIcon.lua
-- Adds a per-unit elite / rare / rare-elite icon overlay to MSUF unit frames.
-- Follows the same patterns as leaderIcon / raidMarkerIcon / kickReady.
--
-- DB keys (per-unit, stored in MSUF_DB[unitKey]):
--   showEliteIcon        boolean  default true
--   eliteIconSize        number   default 20
--   eliteIconAnchor      string   "TOPLEFT"|"TOPRIGHT"|"BOTTOMLEFT"|"BOTTOMRIGHT"  default "TOPRIGHT"
--   eliteIconOffsetX     number   default 2
--   eliteIconOffsetY     number   default 2
--
-- Supported units: target, focus, targettarget, boss
-- (player/pet are never elite NPCs so skipped by default; can be extended trivially)

local addonName, ns = ...
ns = ns or _G.MSUF_NS or {}
_G.MSUF_NS = ns

-- ─── atlas names (from interface/targetingframe/nameplates sheet) ────────────
local ATLAS_GOLD   = "nameplates-icon-elite-gold"    -- elite / worldboss
local ATLAS_SILVER = "nameplates-icon-elite-silver"  -- rare / rareelite

-- Classification → atlas mapping (nil = hide the icon)
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

-- ─── layout helper (mirrors ns.Icons._layout.Apply) ─────────────────────────
local ANCHOR_MAP = {
    TOPLEFT     = { point = "LEFT",  relPoint = "TOPLEFT"     },
    TOPRIGHT    = { point = "RIGHT", relPoint = "TOPRIGHT"    },
    BOTTOMLEFT  = { point = "LEFT",  relPoint = "BOTTOMLEFT"  },
    BOTTOMRIGHT = { point = "RIGHT", relPoint = "BOTTOMRIGHT" },
}

local function ResolveAnchor(anchor)
    return ANCHOR_MAP[anchor] or ANCHOR_MAP["TOPRIGHT"]
end

-- ─── DB helpers ──────────────────────────────────────────────────────────────
local VALID_UNITS = { target = true, focus = true, targettarget = true, boss = true }
_G.VALID_UNITS = VALID_UNITS

local function GetConf(f)
    local db = _G.MSUF_DB
    if not db then return nil, nil end
    local key = f.msufConfigKey or f.unitKey or f.unit
    -- boss1..boss5 → "boss"
    if type(key) == "string" and key:sub(1, 4) == "boss" and key ~= "boss" then
        key = "boss"
    end
    if not VALID_UNITS[key] then return nil, nil end
    return db[key] or {}, key
end

local function GetBool(conf, field, default)
    local v = conf and conf[field]
    if v == nil then return default end
    return v
end

local function GetNum(conf, field, default)
    local v = conf and conf[field]
    if type(v) == "number" then return v end
    return default
end

local function GetStr(conf, field, default)
    local v = conf and conf[field]
    if type(v) == "string" and v ~= "" then return v end
    return default
end

-- ─── apply layout (called once on frame creation and on settings change) ─────
local floor = math.floor

local function ApplyLayout(f)
    local icon = f.eliteIcon
    if not icon then return end

    local conf, key = GetConf(f)
    if not conf then icon:Hide(); return end

    local size   = floor(math.max(8, math.min(64, GetNum(conf, "eliteIconSize", 20))) + 0.5)
    local ox     = GetNum(conf, "eliteIconOffsetX", 2)
    local oy     = GetNum(conf, "eliteIconOffsetY", 2)
    local anchor = GetStr(conf, "eliteIconAnchor", "TOPRIGHT")

    local a      = ResolveAnchor(anchor)
    icon:SetSize(size, size)
    icon:ClearAllPoints()
    icon:SetPoint(a.point, f, a.relPoint, ox, oy)
end

-- ─── update visibility + atlas for a single frame ────────────────────────────
local function UpdateEliteIcon(f)
    local icon = f.eliteIcon
    if not icon then return end

    local conf, key = GetConf(f)
    if not conf then icon:Hide(); return end

    if not GetBool(conf, "showEliteIcon", true) then
        icon:Hide(); return
    end

    local unit = f.unit
    if not unit or not UnitExists(unit) then
        icon:Hide(); return
    end

    local atlas = GetEliteAtlas(unit)
    if not atlas then
        icon:Hide(); return
    end

    -- SetAtlas without useAtlasSize so we control size ourselves
    icon:SetAtlas(atlas)
    ApplyLayout(f)  -- re-apply in case something moved
    icon:Show()
end

-- ─── public API ──────────────────────────────────────────────────────────────

-- Called by MSUF_RefreshEliteIconFrames from the options panel
function MSUF_ApplyEliteIconLayout(f)
    if not (f and f.eliteIcon) then return end
    ApplyLayout(f)
    UpdateEliteIcon(f)
end
_G.MSUF_ApplyEliteIconLayout = MSUF_ApplyEliteIconLayout

-- Called from the main update path (mirrors how leaderIcon / raidMarkerIcon are driven)
function MSUF_UpdateEliteIcon(f)
    UpdateEliteIcon(f)
end
_G.MSUF_UpdateEliteIcon = MSUF_UpdateEliteIcon

-- Refresh all MSUF frames (called after settings change in the options panel)
function MSUF_RefreshEliteIconFrames()
    if not ns or not ns.UF or not ns.UF.AllFrames then return end
    for _, f in pairs(ns.UF.AllFrames) do
        MSUF_ApplyEliteIconLayout(f)
    end
end
_G.MSUF_RefreshEliteIconFrames = MSUF_RefreshEliteIconFrames

-- ─── DB defaults (called by MSUF_EnsureDB_Heavy) ─────────────────────────────
-- You need to add a call to MSUF_EliteIcon_EnsureDefaults() inside
-- MSUF_EnsureDB_Heavy() in Foundation/MSUF_Defaults.lua, or call it from
-- PLAYER_LOGIN after EnsureDB() runs. See integration notes below.
function MSUF_EliteIcon_EnsureDefaults()
    local db = _G.MSUF_DB
    if not db then return end
    for _, key in ipairs({ "target", "focus", "targettarget", "boss" }) do
        db[key] = db[key] or {}
        local u = db[key]
        if u.showEliteIcon    == nil then u.showEliteIcon    = true         end
        if u.eliteIconSize    == nil then u.eliteIconSize    = 20           end
        if u.eliteIconAnchor  == nil then u.eliteIconAnchor  = "TOPRIGHT"   end
        if u.eliteIconOffsetX == nil then u.eliteIconOffsetX = 2            end
        if u.eliteIconOffsetY == nil then u.eliteIconOffsetY = 2            end
    end
end
_G.MSUF_EliteIcon_EnsureDefaults = MSUF_EliteIcon_EnsureDefaults

-- ─── hook into MSUF once it is ready ─────────────────────────────────────────
-- We listen for MSUF_FRAME_CREATED (fired by MidnightSimpleUnitFrames.lua for
-- every new unitframe) and UNIT_TARGET / PLAYER_TARGET_CHANGED / etc. to keep
-- the icon in sync with the currently targeted unit's classification.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Seed DB defaults after EnsureDB has already run
        if type(MSUF_EliteIcon_EnsureDefaults) == "function" then
            MSUF_EliteIcon_EnsureDefaults()
        end

        -- Hook MSUF_FRAME_CREATED so we can add eliteIcon to each new frame
        -- MSUF fires this custom callback from ns.UF.Register / BuildFrame
        if ns and ns.EventBus and ns.EventBus.On then
            ns.EventBus.On("MSUF_FRAME_CREATED", function(f)
                -- Only attach to units that can be elite/rare
                local unit = f and f.unit
                if not unit then return end
                local key = f.msufConfigKey or f.unitKey or unit
                if type(key) == "string" and key:sub(1, 4) == "boss" then key = "boss" end
                if not VALID_UNITS[key] then return end

                -- Create the icon texture on the frame (mirrors the defs table in main)
                if not f.eliteIcon then
                    local tex = f:CreateTexture(nil, "OVERLAY", nil, 8)
                    tex:SetSize(20, 20)
                    tex:Hide()
                    f.eliteIcon = tex
                end

                ApplyLayout(f)
            end)
        end

        -- Listen to events that change what the target IS (classification changes)
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
        self:RegisterEvent("PLAYER_FOCUS_CHANGED")
        self:RegisterEvent("UNIT_CLASSIFICATION_CHANGED")
        self:RegisterEvent("GROUP_ROSTER_UPDATE")

    elseif event == "PLAYER_TARGET_CHANGED" then
        if ns and ns.UF and ns.UF.AllFrames then
            for _, f in pairs(ns.UF.AllFrames) do
                local u = f and f.unit
                if u == "target" or u == "targettarget" then
                    UpdateEliteIcon(f)
                end
            end
        end

    elseif event == "PLAYER_FOCUS_CHANGED" then
        if ns and ns.UF and ns.UF.AllFrames then
            for _, f in pairs(ns.UF.AllFrames) do
                if f and f.unit == "focus" then
                    UpdateEliteIcon(f)
                end
            end
        end

    elseif event == "UNIT_CLASSIFICATION_CHANGED" then
        local unit = ...
        if ns and ns.UF and ns.UF.AllFrames then
            for _, f in pairs(ns.UF.AllFrames) do
                if f and f.unit == unit then
                    UpdateEliteIcon(f)
                end
            end
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Boss frames may change
        if ns and ns.UF and ns.UF.AllFrames then
            for _, f in pairs(ns.UF.AllFrames) do
                local key = f and (f.msufConfigKey or f.unitKey or f.unit)
                if type(key) == "string" and key:sub(1, 4) == "boss" then
                    UpdateEliteIcon(f)
                end
            end
        end
    end
end)