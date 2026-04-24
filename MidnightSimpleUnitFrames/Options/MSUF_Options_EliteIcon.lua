-- MSUF_Options_EliteIcon.lua
-- Options panel for the Elite / Rare icon overlay.
-- Plugs into the existing MSUF_Options_Player.lua per-unit indicator pattern.
--
-- Add this file to MidnightSimpleUnitFrames.toc AFTER Options\MSUF_Options_Player.lua:
--   Options\MSUF_Options_EliteIcon.lua

local addonName, ns = ...
ns = ns or _G.MSUF_NS or {}
_G.MSUF_NS = ns

-- Units shown in the scope dropdown (same pool as raidMarker / leaderIcon)
local UNIT_KEYS  = { "target", "focus", "targettarget", "boss" }
local UNIT_LABELS = {
    target       = "Target",
    focus        = "Focus",
    targettarget = "Target of Target",
    boss         = "Boss",
}

local ANCHOR_CHOICES = {
    { "Top Right",    "TOPRIGHT"    },
    { "Top Left",     "TOPLEFT"     },
    { "Bottom Right", "BOTTOMRIGHT" },
    { "Bottom Left",  "BOTTOMLEFT"  },
}

-- ─── helpers (mirrors MSUF_Options_Player.lua patterns) ───────────────────────
local function GetDB(key)
    local db = _G.MSUF_DB
    if not db then return {} end
    db[key] = db[key] or {}
    return db[key]
end

local function Refresh()
    if type(_G.MSUF_RefreshEliteIconFrames) == "function" then
        _G.MSUF_RefreshEliteIconFrames()
    end
end

-- ─── Build the options block ──────────────────────────────────────────────────
-- This function is called by MSUF_Options_Player when it builds the
-- "Indicators" section, or you can call it standalone to create a dedicated
-- panel. It expects a parent frame that already has a vertical layout helper
-- (MSUF_AppendRow / MSUF_MakeLabel / MSUF_MakeCheckbox / etc.).
--
-- If MSUF exposes MSUF_Options_BuildIndicatorBlock (the generic builder used
-- for raidMarker/leaderIcon), we reuse that; otherwise we build manually.

local function BuildEliteIconBlock(parent, unitKey)
    -- Reuse the generic indicator builder if it exists (MSUF internal helper)
    local builder = _G.MSUF_Options_BuildIndicatorBlock
    if type(builder) == "function" then
        builder(parent, {
            id          = "eliteicon",
            order       = 10,  -- after raidMarker
            allowed     = function(key) return GetDB(key) ~= nil end,
            showCB      = "eliteIconCB",
            showField   = "showEliteIcon",
            showDefault = true,
            ui = {
                cbName     = "MSUF_EliteIconCB_" .. unitKey,
                cbText     = "Show elite / rare icon",
                xName      = "MSUF_EliteIconOffsetX_" .. unitKey,
                yName      = "MSUF_EliteIconOffsetY_" .. unitKey,
                anchorName = "MSUF_EliteIconAnchorDrop_" .. unitKey,
                anchorW    = 80,
                sizeName   = "MSUF_EliteIconSize_" .. unitKey,
            },
            xStepper     = "eliteIconOffsetXStepper_" .. unitKey,
            xField       = "eliteIconOffsetX",
            xDefault     = 2,
            yStepper     = "eliteIconOffsetYStepper_" .. unitKey,
            yField       = "eliteIconOffsetY",
            yDefault     = 2,
            anchorDrop   = "eliteIconAnchorDrop_" .. unitKey,
            anchorLabel  = "eliteIconAnchorLabel_" .. unitKey,
            anchorField  = "eliteIconAnchor",
            anchorDefault = "TOPRIGHT",
            anchorText   = function(v)
                for _, pair in ipairs(ANCHOR_CHOICES) do
                    if pair[2] == v then return pair[1] end
                end
                return v
            end,
            anchorChoices = ANCHOR_CHOICES,
            sizeEdit     = "eliteIconSizeEdit_" .. unitKey,
            sizeLabel    = "eliteIconSizeLabel_" .. unitKey,
            sizeField    = "eliteIconSize",
            sizeDefault  = 20,
            divider      = "eliteIconDivider_" .. unitKey,
            resetBtn     = "eliteIconResetBtn_" .. unitKey,
            refreshFnName = "MSUF_RefreshEliteIconFrames",
        }, unitKey)
        return
    end

    -- ── Fallback: manual widget creation ──────────────────────────────────────
    -- Uses the same MSUF widget helpers (MSUF_MakeCheckbox, MSUF_MakeStepper,
    -- MSUF_MakeDropdown, MSUF_MakeLabel) that Options_Player uses.
    local MakeCB      = _G.MSUF_MakeCheckbox
    local MakeStepper = _G.MSUF_MakeStepper
    local MakeDrop    = _G.MSUF_MakeDropdown
    local MakeLabel   = _G.MSUF_MakeLabel
    local MakeDiv     = _G.MSUF_MakeDivider
    local AppendRow   = _G.MSUF_AppendRow

    if not (MakeCB and AppendRow) then return end  -- options widgets not loaded yet

    local conf = GetDB(unitKey)

    -- Divider
    if MakeDiv then AppendRow(parent, MakeDiv(parent)) end

    -- Enable checkbox
    local cb = MakeCB(parent, "MSUF_EliteIconCB_" .. unitKey, "Show elite / rare icon",
        function() return conf.showEliteIcon ~= false end,
        function(val)
            conf.showEliteIcon = val
            Refresh()
        end)
    AppendRow(parent, cb)

    -- Size
    if MakeLabel and MakeStepper then
        local sizeLabel = MakeLabel(parent, "Size:")
        local sizeStep  = MakeStepper(parent, "MSUF_EliteIconSize_" .. unitKey,
            function() return conf.eliteIconSize or 20 end,
            function(val)
                conf.eliteIconSize = math.max(8, math.min(64, val))
                Refresh()
            end, 1, 8, 64)
        AppendRow(parent, sizeLabel, sizeStep)
    end

    -- Anchor dropdown
    if MakeDrop then
        local anchorLabel = MakeLabel and MakeLabel(parent, "Anchor:")
        local anchorDrop  = MakeDrop(parent, "MSUF_EliteIconAnchorDrop_" .. unitKey,
            ANCHOR_CHOICES,
            function() return conf.eliteIconAnchor or "TOPRIGHT" end,
            function(val)
                conf.eliteIconAnchor = val
                Refresh()
            end, 80)
        if anchorLabel then AppendRow(parent, anchorLabel, anchorDrop)
        else AppendRow(parent, anchorDrop) end
    end

    -- X offset
    if MakeStepper then
        local xLabel = MakeLabel and MakeLabel(parent, "Offset X:")
        local xStep  = MakeStepper(parent, "MSUF_EliteIconOffsetX_" .. unitKey,
            function() return conf.eliteIconOffsetX or 2 end,
            function(val)
                conf.eliteIconOffsetX = val
                Refresh()
            end, 1, -200, 200)
        if xLabel then AppendRow(parent, xLabel, xStep)
        else AppendRow(parent, xStep) end
    end

    -- Y offset
    if MakeStepper then
        local yLabel = MakeLabel and MakeLabel(parent, "Offset Y:")
        local yStep  = MakeStepper(parent, "MSUF_EliteIconOffsetY_" .. unitKey,
            function() return conf.eliteIconOffsetY or 2 end,
            function(val)
                conf.eliteIconOffsetY = val
                Refresh()
            end, 1, -200, 200)
        if yLabel then AppendRow(parent, yLabel, yStep)
        else AppendRow(parent, yStep) end
    end
end

-- Export so MSUF_Options_Player can call it when building the indicators section
ns.Options = ns.Options or {}
ns.Options.BuildEliteIconBlock = BuildEliteIconBlock
_G.MSUF_Options_BuildEliteIconBlock = BuildEliteIconBlock

-- ─── DB keys that need to be preserved/reset via the Player options reset list ─
-- Add these keys to the MSUF_PLAYER_RESET_KEYS table in MSUF_Options_Player.lua:
--   "showEliteIcon", "eliteIconSize", "eliteIconAnchor",
--   "eliteIconOffsetX", "eliteIconOffsetY"