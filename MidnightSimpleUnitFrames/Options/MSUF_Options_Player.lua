--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua"); local addonName, ns = ...
ns = ns or {}

-- Ensure the Castbars LoD addon is loaded before calling castbar functions.
local function MSUF_EnsureCastbars() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EnsureCastbars file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:5:6");
    if type(_G.MSUF_EnsureAddonLoaded) == "function" then
        _G.MSUF_EnsureAddonLoaded("MidnightSimpleUnitFrames_Castbars")
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EnsureCastbars file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:5:6"); return
    end
    local loader = (_G.C_AddOns and _G.C_AddOns.LoadAddOn) or _G.LoadAddOn
    if type(loader) == "function" then
        pcall(loader, "MidnightSimpleUnitFrames_Castbars")
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EnsureCastbars file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:5:6"); end


-- Early tab guard helper
-- Some OnShow handlers call IsFramesTab() before the tab API is constructed.
-- In this build, the controls are only created for the Frames UI anyway, so this must be safe.
local function IsFramesTab() Perfy_Trace(Perfy_GetTime(), "Enter", "IsFramesTab file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:20:6");
    Perfy_Trace(Perfy_GetTime(), "Leave", "IsFramesTab file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:20:6"); return true
end

-- Numeric editbox helper: ensures the number is visible even when set programmatically.
local function MSUF_SetNumericEditBoxValue(edit, v) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetNumericEditBoxValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:25:6");
    if not edit then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetNumericEditBoxValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:25:6"); return end
    if edit.HasFocus and edit:HasFocus() then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetNumericEditBoxValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:25:6"); return end

    local n = tonumber(v) or 0
    n = math.floor(n + 0.5)

    -- Force a readable font + color in our dark UI.
    if edit.SetFontObject then
        edit:SetFontObject(GameFontHighlightSmall)
    end
    if edit.SetTextColor then
        edit:SetTextColor(1, 1, 1, 1)
    end

    if edit.SetNumber then
        edit:SetNumber(n)
    else
        edit:SetText(tostring(n))
    end

    if edit.SetCursorPosition then
        edit:SetCursorPosition(0)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetNumericEditBoxValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:25:6"); end


-- Mockup Unitframe Layout (reusable)
-- Left:  Frame Basics + Frame Size
-- Right: Name / HP / Power (X stepper, Y stepper, Size slider)
--
-- IMPORTANT: This module is designed to work in two modes depending on the core:
--  1) Player-only reflector mode (older core): only shows/applies when currentKey == "player".
--  2) Multi-unit mode (newer core): can be shown for any unit key; handlers write to MSUF_DB[currentKey].

local MSUF_PositionLeaderMiniHeaders

-- Shared label helper for the Leader Icon anchor dropdown.
-- Must be file-scope so both CreatePanel() and ApplyFromDB() can use it.
local function MSUF_LeaderAnchorText(v) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_LeaderAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:64:6");
    if v == "TOPLEFT" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_LeaderAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:64:6"); return "Top left" end
    if v == "TOPRIGHT" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_LeaderAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:64:6"); return "Top right" end
    if v == "BOTTOMLEFT" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_LeaderAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:64:6"); return "Bottom left" end
    if v == "BOTTOMRIGHT" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_LeaderAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:64:6"); return "Bottom right" end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_LeaderAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:64:6"); return "Top left"
end


-- Raid marker anchor text helper (used by dropdown + ApplySettingsForKey)
local function MSUF_RaidMarkerAnchorText(v) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_RaidMarkerAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:74:6");
    if v == "CENTER" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RaidMarkerAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:74:6"); return "Center" end
    if v == "TOPRIGHT" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RaidMarkerAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:74:6"); return "Top right" end
    if v == "BOTTOMLEFT" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RaidMarkerAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:74:6"); return "Bottom left" end
    if v == "BOTTOMRIGHT" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RaidMarkerAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:74:6"); return "Bottom right" end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RaidMarkerAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:74:6"); return "Top left"
end

local function MSUF_LevelAnchorText(v) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_LevelAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:82:6");
    if v == "TOPLEFT" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_LevelAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:82:6"); return "Top left" end
    if v == "TOPRIGHT" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_LevelAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:82:6"); return "Top right" end
    if v == "BOTTOMLEFT" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_LevelAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:82:6"); return "Bottom left" end
    if v == "BOTTOMRIGHT" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_LevelAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:82:6"); return "Bottom right" end
    if v == "NAMELEFT" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_LevelAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:82:6"); return "Left to player name" end
    if v == "NAMERIGHT" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_LevelAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:82:6"); return "Right to player name" end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_LevelAnchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:82:6"); return "Right to player name"
end

-- ---------------------------------------------------------------------------
-- Status icon symbol textures (Classic vs Midnight)
-- These are used by the Status icon "symbol" dropdowns (Combat/Rested/Incoming Rez).
-- We store the chosen symbol key per-unit, but the "style" (classic vs midnight) is global.
-- ---------------------------------------------------------------------------

local function MSUF_GetStatusIconStyleUseMidnight() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetStatusIconStyleUseMidnight file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:98:6");
    if type(_G.EnsureDB) == "function" then
        _G.EnsureDB()
    end
    local db = _G.MSUF_DB
    local g = (type(db) == "table") and db.general or nil
    if type(g) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetStatusIconStyleUseMidnight file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:98:6"); return false end
    return Perfy_Trace_Passthrough("Leave", "MSUF_GetStatusIconStyleUseMidnight file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:98:6", (g.statusIconsUseMidnightStyle == true))
end

-- Returns a texture path for a given symbol key.
-- Symbol keys are grouped by prefix:
--   weapon_*  -> Media/Symbols/Combat  (128_clean)
--   rested_*  -> Media/Symbols/Rested  (64)
local function MSUF_StatusIcon_GetSymbolTexture(symbolKey) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_StatusIcon_GetSymbolTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:112:6");
    if type(symbolKey) ~= "string" or symbolKey == "" or symbolKey == "DEFAULT" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StatusIcon_GetSymbolTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:112:6"); return nil
    end

    local useMidnight = MSUF_GetStatusIconStyleUseMidnight()

    local folder = "Combat"
    local suffix = useMidnight and "_midnight_128_clean.tga" or "_classic_128_clean.tga"

    -- Rested icons use a different folder + size/suffix convention.
    if string.find(symbolKey, "^rested_") then
        folder = "Rested"
        suffix = useMidnight and "_midnight_64.tga" or "_classic_64.tga"
    end

-- Resurrection icons use a different folder + size/suffix convention.
if string.find(symbolKey, "^resurrection_") then
    folder = "Ress"
    suffix = useMidnight and "_midnight_64.tga" or "_classic_64.tga"
end


    return Perfy_Trace_Passthrough("Leave", "MSUF_StatusIcon_GetSymbolTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:112:6", "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Symbols\\" .. folder .. "\\" .. symbolKey .. suffix)
end


local _MSUF_STATUSICON_SYMBOLS = {
    { "Default",    "DEFAULT",                    nil },

    -- Weapon icons (short names, as requested)
    { "Axes",       "weapon_axes_crossed",        "weapon_axes_crossed" },
    { "Bows",       "weapon_bows_crossed",        "weapon_bows_crossed" },
    { "Crossbows",  "weapon_crossbows_crossed",   "weapon_crossbows_crossed" },
    { "Daggers",    "weapon_daggers_crossed",     "weapon_daggers_crossed" },
    { "Fishing",    "weapon_fishing_poles_crossed","weapon_fishing_poles_crossed" },
    { "Fist",       "weapon_fist_crossed",        "weapon_fist_crossed" },
    { "Guns",       "weapon_guns_crossed",        "weapon_guns_crossed" },
    { "Maces",      "weapon_maces_crossed",       "weapon_maces_crossed" },
    { "Polearms",   "weapon_polearms_crossed",    "weapon_polearms_crossed" },
    { "Shuriken",   "weapon_shuriken",            "weapon_shuriken" },
    { "Staves",     "weapon_staves_crossed",      "weapon_staves_crossed" },
    { "Swords",     "weapon_swords_crossed",      "weapon_swords_crossed" },
    -- (User wording) "Thorn" = Thrown weapons
    { "Thorn",      "weapon_thrown_crossed",      "weapon_thrown_crossed" },
    { "Wands",      "weapon_wands_crossed",       "weapon_wands_crossed" },
    { "Warglaives", "weapon_warglaives_crossed",  "weapon_warglaives_crossed" },
}


-- Rested icon symbol set (player only)
-- Files live in: Media/Symbols/Rested/
-- Pattern: rested_<name>_{classic|midnight}_64.tga
local _MSUF_STATUSICON_RESTED_SYMBOLS = {
    { "Default",     "DEFAULT" },

    { "Moon Zzz",    "rested_moonzzz"  },
    { "Moon Zzzz",   "rested_moonzzzz" },
    { "Compact",     "rested_zzz_compact" },
    { "Diag",        "rested_zzz_diag" },
    { "Stack",       "rested_zzz_stack" },
}



-- Resurrection icon symbol set (Incoming Rez)
-- Files live in: Media/Symbols/Ress/
-- Pattern: resurrection_<name>_{classic|midnight}_64.tga
local _MSUF_STATUSICON_RESS_SYMBOLS = {
    { "Default", "DEFAULT" },
    { "Ankh",    "resurrection_ankh"  },
    { "Cross",   "resurrection_cross" },
    { "Soul",    "resurrection_soul"  },
    { "Wings",   "resurrection_wings" },
}

local function _MSUF_FindStatusIconLabel(symbolKey) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_FindStatusIconLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:188:6");
    if symbolKey == nil or symbolKey == "DEFAULT" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_FindStatusIconLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:188:6"); return "Default"
    end

    for i = 1, #_MSUF_STATUSICON_SYMBOLS do
        local row = _MSUF_STATUSICON_SYMBOLS[i]
        if row and row[2] == symbolKey then
            return Perfy_Trace_Passthrough("Leave", "_MSUF_FindStatusIconLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:188:6", row[1])
        end
    end

    for i = 1, #_MSUF_STATUSICON_RESTED_SYMBOLS do
        local row = _MSUF_STATUSICON_RESTED_SYMBOLS[i]
        if row and row[2] == symbolKey then
            return Perfy_Trace_Passthrough("Leave", "_MSUF_FindStatusIconLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:188:6", row[1])
        end
    end


    for i = 1, #_MSUF_STATUSICON_RESS_SYMBOLS do
        local row = _MSUF_STATUSICON_RESS_SYMBOLS[i]
        if row and row[2] == symbolKey then
            return Perfy_Trace_Passthrough("Leave", "_MSUF_FindStatusIconLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:188:6", row[1])
        end
    end

    return Perfy_Trace_Passthrough("Leave", "_MSUF_FindStatusIconLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:188:6", tostring(symbolKey))
end

local function MSUF_StatusIcon_SymbolText(v) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_StatusIcon_SymbolText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:218:6");
    return Perfy_Trace_Passthrough("Leave", "MSUF_StatusIcon_SymbolText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:218:6", _MSUF_FindStatusIconLabel(v))
end

local function MSUF_StatusIcon_GetSymbolChoices() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_StatusIcon_GetSymbolChoices file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:222:6");
    local t = {}
    for i = 1, #_MSUF_STATUSICON_SYMBOLS do
        local row = _MSUF_STATUSICON_SYMBOLS[i]
        if row then t[#t+1] = { row[1], row[2] } end
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StatusIcon_GetSymbolChoices file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:222:6"); return t
end

local function MSUF_StatusIcon_GetRestedSymbolChoices() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_StatusIcon_GetRestedSymbolChoices file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:231:6");
    local t = {}
    for i = 1, #_MSUF_STATUSICON_RESTED_SYMBOLS do
        local row = _MSUF_STATUSICON_RESTED_SYMBOLS[i]
        if row then t[#t+1] = { row[1], row[2] } end
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StatusIcon_GetRestedSymbolChoices file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:231:6"); return t
end

local function MSUF_StatusIcon_GetRessSymbolChoices() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_StatusIcon_GetRessSymbolChoices file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:240:6");
    local t = {}
    for i = 1, #_MSUF_STATUSICON_RESS_SYMBOLS do
        local row = _MSUF_STATUSICON_RESS_SYMBOLS[i]
        if row then t[#t+1] = { row[1], row[2] } end
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StatusIcon_GetRessSymbolChoices file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:240:6"); return t
end


local function MSUF_StatusIcon_GetSymbolTexture(symbolKey) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_StatusIcon_GetSymbolTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:250:6");
    if type(symbolKey) ~= "string" or symbolKey == "" or symbolKey == "DEFAULT" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StatusIcon_GetSymbolTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:250:6"); return nil
    end
    local useMidnight = MSUF_GetStatusIconStyleUseMidnight()
    local suffix = useMidnight and "_midnight_128_clean.tga" or "_classic_128_clean.tga"
    -- NOTE: These are addon-bundled .tga files.
    -- Folder must match your actual media folder structure.
    return Perfy_Trace_Passthrough("Leave", "MSUF_StatusIcon_GetSymbolTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:250:6", "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Symbols\\Combat\\" .. symbolKey .. suffix)
end


-- Shared indicator specs for Options_Player (used by ApplyFromDB layout + InstallHandlers)
local _MSUF_INDICATOR_SPECS = {
    leader = {
        id = "leader",
        order = 1,
        allowed = function(key) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:267:18"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:267:18", (key == "player" or key == "target")) end,

        showCB = "playerLeaderIconCB", showField = "showLeaderIcon", showDefault = true,

        ui = {
            cbName = "MSUF_PlayerLeaderIconCB",
            cbText = "Show leader/assist icon",
            xName = "MSUF_PlayerLeaderIconOffsetX",
            yName = "MSUF_PlayerLeaderIconOffsetY",
            anchorName = "MSUF_PlayerLeaderIconAnchorDropdown",
            anchorW = 70,
            sizeName = "MSUF_PlayerLeaderIconSizeEdit",
        },


        xStepper = "playerLeaderOffsetXStepper", xField = "leaderIconOffsetX", xDefault = 0,
        yStepper = "playerLeaderOffsetYStepper", yField = "leaderIconOffsetY", yDefault = 3,

        anchorDrop = "playerLeaderAnchorDrop", anchorLabel = "playerLeaderAnchorLabel",
        anchorField = "leaderIconAnchor", anchorDefault = "TOPLEFT",
        anchorText = function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:287:21"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:287:21", MSUF_LeaderAnchorText(v)) end,
        anchorChoices = {
            { MSUF_LeaderAnchorText("TOPLEFT"), "TOPLEFT" },
            { MSUF_LeaderAnchorText("TOPRIGHT"), "TOPRIGHT" },
            { MSUF_LeaderAnchorText("BOTTOMLEFT"), "BOTTOMLEFT" },
            { MSUF_LeaderAnchorText("BOTTOMRIGHT"), "BOTTOMRIGHT" },
        },


        sizeEdit = "playerLeaderSizeEdit", sizeLabel = "playerLeaderSizeLabel",
        sizeField = "leaderIconSize", sizeDefault = 14,

        divider = "playerLeaderGroupDivider",
        resetBtn = "playerLeaderResetBtn",

        refreshFnName = "MSUF_RefreshLeaderIconFrames",
    },

    raidmarker = {
        id = "raidmarker",
        order = 2,
        allowed = function(_) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:308:18"); Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:308:18"); return true end,

        showCB = "playerRaidMarkerCB", showField = "showRaidMarker", showDefault = true,

        ui = {
            cbName = "MSUF_PlayerRaidMarkerCB",
            cbText = "Show raid marker icon",
            xName = "MSUF_PlayerRaidMarkerOffsetX",
            yName = "MSUF_PlayerRaidMarkerOffsetY",
            anchorName = "MSUF_PlayerRaidMarkerAnchorDropdown",
            anchorW = 70,
            sizeName = "MSUF_PlayerRaidMarkerSizeEdit",
        },


        xStepper = "playerRaidMarkerOffsetXStepper", xField = "raidMarkerOffsetX", xDefault = 16,
        yStepper = "playerRaidMarkerOffsetYStepper", yField = "raidMarkerOffsetY", yDefault = 3,

        anchorDrop = "playerRaidMarkerAnchorDrop", anchorLabel = "playerRaidMarkerAnchorLabel",
        anchorField = "raidMarkerAnchor", anchorDefault = "TOPLEFT",
        anchorText = function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:328:21"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:328:21", MSUF_RaidMarkerAnchorText(v)) end,
        anchorChoices = {
            { MSUF_RaidMarkerAnchorText("TOPLEFT"), "TOPLEFT" },
            { MSUF_RaidMarkerAnchorText("TOPRIGHT"), "TOPRIGHT" },
            { MSUF_RaidMarkerAnchorText("BOTTOMLEFT"), "BOTTOMLEFT" },
            { MSUF_RaidMarkerAnchorText("BOTTOMRIGHT"), "BOTTOMRIGHT" },
            { MSUF_RaidMarkerAnchorText("CENTER"), "CENTER" },
        },


        sizeEdit = "playerRaidMarkerSizeEdit", sizeLabel = "playerRaidMarkerSizeLabel",
        sizeField = "raidMarkerSize", sizeDefault = 18,

        divider = "playerRaidMarkerGroupDivider",
        resetBtn = "playerRaidMarkerResetBtn",

        refreshFnName = "MSUF_RefreshRaidMarkerFrames",
    },

    level = {
        id = "level",
        order = 3,
        allowed = function(_) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:350:18"); Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:350:18"); return true end,

        showCB = "playerLevelIndicatorCB", showField = "showLevelIndicator", showDefault = true,

        ui = {
            cbName = "MSUF_PlayerLevelIndicatorCB",
            cbText = "Show level",
            xName = "MSUF_PlayerLevelOffsetX",
            yName = "MSUF_PlayerLevelOffsetY",
            anchorName = "MSUF_PlayerLevelAnchorDropdown",
            anchorW = 70,
            sizeName = "MSUF_PlayerLevelSizeEdit",
        },


        xStepper = "playerLevelOffsetXStepper", xField = "levelIndicatorOffsetX", xDefault = 0,
        yStepper = "playerLevelOffsetYStepper", yField = "levelIndicatorOffsetY", yDefault = 0,

        anchorDrop = "playerLevelAnchorDrop", anchorLabel = "playerLevelAnchorLabel",
        anchorField = "levelIndicatorAnchor", anchorDefault = "NAMERIGHT",
        anchorText = function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:370:21"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:370:21", MSUF_LevelAnchorText(v)) end,
        anchorChoices = {
            { MSUF_LevelAnchorText("NAMERIGHT"), "NAMERIGHT" },
            { MSUF_LevelAnchorText("NAMELEFT"), "NAMELEFT" },
            { MSUF_LevelAnchorText("TOPLEFT"), "TOPLEFT" },
            { MSUF_LevelAnchorText("TOPRIGHT"), "TOPRIGHT" },
            { MSUF_LevelAnchorText("BOTTOMLEFT"), "BOTTOMLEFT" },
            { MSUF_LevelAnchorText("BOTTOMRIGHT"), "BOTTOMRIGHT" },
        },


        -- Level: eigene Größe (per-unit). Nil => folgt Name-Fontgröße (Fallback in Apply/Runtime).
        sizeEdit  = "playerLevelSizeEdit",
        sizeLabel = "playerLevelSizeLabel",
        sizeField = "levelIndicatorSize",
        sizeDefault = 14,

        divider = "playerLevelGroupDivider",
        resetBtn = "playerLevelResetBtn",

        refreshFnName = "MSUF_RefreshLevelIndicatorFrames",
    },
}

-- ============================================================
-- Step 4B: ApplyFromDB refactor helpers (spec-driven apply)
-- ============================================================

local MSUF_INDICATOR_ORDER = { "leader", "raidmarker", "level" }

local function MSUF_ReadBool(conf, g, field, defaultVal) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ReadBool file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:400:6");
    local v = conf and conf[field]
    if v == nil and g then v = g[field] end
    if v == nil then v = defaultVal end
    return Perfy_Trace_Passthrough("Leave", "MSUF_ReadBool file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:400:6", (v ~= false))
end

local function MSUF_ReadNumber(conf, g, field, defaultVal) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ReadNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:407:6");
    local v = conf and conf[field]
    if type(v) ~= "number" then v = nil end
    if v == nil and g then
        local gv = g[field]
        if type(gv) == "number" then v = gv end
    end
    if v == nil then v = defaultVal end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ReadNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:407:6"); return v
end

local function MSUF_ReadString(conf, g, field, defaultVal) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ReadString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:418:6");
    local v = conf and conf[field]
    if type(v) ~= "string" then v = nil end
    if v == nil and g then
        local gv = g[field]
        if type(gv) == "string" then v = gv end
    end
    if v == nil then v = defaultVal end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ReadString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:418:6"); return v
end


-- ============================================================
-- Step 4C: Portrait + Alpha + BossSpacing in Specs/Loops
-- ============================================================

local MSUF_PORTRAIT_OPTIONS = {
    { value = "OFF",      text = "Portrait Off" },
    { value = "2D_LEFT",  text = "2D Portrait Left" },
    { value = "2D_RIGHT", text = "2D Portrait Right" },
    { value = "3D_LEFT",  text = "3D Portrait Left" },
    { value = "3D_RIGHT", text = "3D Portrait Right" },
}

-- Target-of-Target inline-in-Target separator dropdown (token stored in MSUF_DB.targettarget.totInlineSeparator).
-- UI shows the raw token; runtime renders it with spaces around it (legacy: " | ").
local MSUF_TOTINLINE_SEP_OPTIONS = {
    { value = ".",   text = "."   },
    { value = "-",   text = "-"   },
    { value = "/",   text = "/"   },
    { value = "\\",  text = "\\"  },
    { value = "|",   text = "|"   },
    { value = "<<<", text = "<<<" },
    { value = ">>>", text = ">>>" },
    -- optional extras (UTF-8 is fine in Lua sources)
    { value = "•",   text = "•"   },
    { value = "—",   text = "—"   },
    { value = "·",   text = "·"   },
    { value = ">",   text = ">"   },
    { value = "<",   text = "<"   },
}

-- Fast validation for ToT-inline separator tokens (keeps dropdown checked-state stable
-- even if profiles/imports contain unknown values).
local MSUF_TOTINLINE_SEP_LOOKUP = {}
do
    for i = 1, #MSUF_TOTINLINE_SEP_OPTIONS do
        local v = MSUF_TOTINLINE_SEP_OPTIONS[i] and MSUF_TOTINLINE_SEP_OPTIONS[i].value
        if type(v) == "string" and v ~= "" then
            MSUF_TOTINLINE_SEP_LOOKUP[v] = true
        end
    end
end

local function MSUF_ToTInlineSepTokenText(v) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ToTInlineSepTokenText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:472:6");
    if type(v) ~= "string" or v == "" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ToTInlineSepTokenText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:472:6"); return "|" end
    if not MSUF_TOTINLINE_SEP_LOOKUP[v] then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ToTInlineSepTokenText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:472:6"); return "|" end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ToTInlineSepTokenText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:472:6"); return v
end

local function MSUF_PortraitModeText(mode) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_PortraitModeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:478:6");
    if mode == "2D_LEFT" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_PortraitModeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:478:6"); return "2D Portrait Left" end
    if mode == "2D_RIGHT" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_PortraitModeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:478:6"); return "2D Portrait Right" end
    if mode == "3D_LEFT" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_PortraitModeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:478:6"); return "3D Portrait Left" end
    if mode == "3D_RIGHT" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_PortraitModeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:478:6"); return "3D Portrait Right" end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_PortraitModeText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:478:6"); return "Portrait Off"
end

local function MSUF_GetPortraitDropdownValue(conf) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetPortraitDropdownValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:486:6");
    if not conf then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetPortraitDropdownValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:486:6"); return "OFF" end
    local pm = conf.portraitMode or "OFF"
    if pm ~= "LEFT" and pm ~= "RIGHT" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetPortraitDropdownValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:486:6"); return "OFF"
    end

    local render = conf.portraitRender
    if render == "3D" then
        return Perfy_Trace_Passthrough("Leave", "MSUF_GetPortraitDropdownValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:486:6", (pm == "LEFT") and "3D_LEFT" or "3D_RIGHT")
    end

    -- Default to 2D for legacy profiles (portraitRender nil/unknown)
    return Perfy_Trace_Passthrough("Leave", "MSUF_GetPortraitDropdownValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:486:6", (pm == "LEFT") and "2D_LEFT" or "2D_RIGHT")
end

local function MSUF_ApplyPortraitChoice(conf, choice) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ApplyPortraitChoice file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:502:6");
    if not conf then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyPortraitChoice file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:502:6"); return end

    if choice == "OFF" then
        conf.portraitMode = "OFF"
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyPortraitChoice file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:502:6"); return
    end

    if choice == "2D_LEFT" then
        conf.portraitMode = "LEFT"
        conf.portraitRender = "2D"
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyPortraitChoice file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:502:6"); return
    end
    if choice == "2D_RIGHT" then
        conf.portraitMode = "RIGHT"
        conf.portraitRender = "2D"
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyPortraitChoice file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:502:6"); return
    end

    if choice == "3D_LEFT" then
        conf.portraitMode = "LEFT"
        conf.portraitRender = "3D"
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyPortraitChoice file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:502:6"); return
    end
    if choice == "3D_RIGHT" then
        conf.portraitMode = "RIGHT"
        conf.portraitRender = "3D"
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyPortraitChoice file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:502:6"); return
    end

    -- Fallback
    conf.portraitMode = "OFF"
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyPortraitChoice file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:502:6"); end

local function MSUF_BindPortraitDropdown(panel, fieldName, IsFramesTabFn, EnsureKeyDBFn, ApplyFn) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_BindPortraitDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:536:6");
    local dd = panel and panel[fieldName]
    if not dd or not UIDropDownMenu_Initialize then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BindPortraitDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:536:6"); return end

    local function OnClick(btn, arg1) Perfy_Trace(Perfy_GetTime(), "Enter", "OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:540:10");
        if IsFramesTabFn and not IsFramesTabFn() then Perfy_Trace(Perfy_GetTime(), "Leave", "OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:540:10"); return end
        local conf = EnsureKeyDBFn and EnsureKeyDBFn()
        if not conf then Perfy_Trace(Perfy_GetTime(), "Leave", "OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:540:10"); return end

        local choice = (btn and btn.value) or arg1 or "OFF"

        MSUF_ApplyPortraitChoice(conf, choice)

        -- Sync dropdown UI based on current frame config (not global state)
        local cur = MSUF_GetPortraitDropdownValue(conf)
        if UIDropDownMenu_SetSelectedValue then
            UIDropDownMenu_SetSelectedValue(dd, cur)
        end
        if UIDropDownMenu_SetText then
            UIDropDownMenu_SetText(dd, MSUF_PortraitModeText(cur))
        end

        if ApplyFn then ApplyFn() end

        -- Hard-sync portrait visuals immediately. Some core paths skip portrait updates
        -- when portraitMode is OFF, so we must explicitly hide the 3D model if it was
        -- previously visible.
        local getKey = panel and panel._msufGetCurrentKey
        local key = (type(getKey) == "function") and getKey() or nil
        local sync = _G and _G.MSUF_3DPortraits_SyncUnit
        if key and type(sync) == "function" then
            pcall(sync, key)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:540:10"); end

    UIDropDownMenu_Initialize(dd, function(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:571:34");
        if not level or level ~= 1 then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:571:34"); return end
        for _, opt in ipairs(MSUF_PORTRAIT_OPTIONS or {}) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = opt.text
            info.value = opt.value
            info.func  = OnClick
            info.arg1  = opt.value
            info.checked = function() Perfy_Trace(Perfy_GetTime(), "Enter", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:579:27");
                local conf = EnsureKeyDBFn and EnsureKeyDBFn()
                local cur = MSUF_GetPortraitDropdownValue(conf)
                return Perfy_Trace_Passthrough("Leave", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:579:27", (cur == opt.value))
            end
            UIDropDownMenu_AddButton(info, level)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:571:34"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BindPortraitDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:536:6"); end

local function MSUF_BindDropdown(panel, fieldName, confKey, options, textFn, IsFramesTabFn, EnsureKeyDBFn, ApplyFn) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_BindDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:589:6");
    local dd = panel and panel[fieldName]
    if not dd or not UIDropDownMenu_Initialize then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BindDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:589:6"); return end

    local function OnClick(btn, arg1) Perfy_Trace(Perfy_GetTime(), "Enter", "OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:593:10");
        if IsFramesTabFn and not IsFramesTabFn() then Perfy_Trace(Perfy_GetTime(), "Leave", "OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:593:10"); return end
        local conf = EnsureKeyDBFn and EnsureKeyDBFn()
        if not conf then Perfy_Trace(Perfy_GetTime(), "Leave", "OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:593:10"); return end

        local value = (btn and btn.value) or arg1 or (options and options[1] and options[1].value) or "OFF"
        conf[confKey] = value

        if UIDropDownMenu_SetSelectedValue then
            UIDropDownMenu_SetSelectedValue(dd, value)
        end
        if UIDropDownMenu_SetText and textFn then
            UIDropDownMenu_SetText(dd, textFn(value))
        end

        if ApplyFn then ApplyFn() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "OnClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:593:10"); end

    UIDropDownMenu_Initialize(dd, function(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:611:34");
        if not level or level ~= 1 then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:611:34"); return end
        for _, opt in ipairs(options or {}) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = opt.text
            info.value = opt.value
            info.func  = OnClick
            info.arg1  = opt.value
            -- safe checked function, don’t rely on btn.text being non-nil
            info.checked = function() Perfy_Trace(Perfy_GetTime(), "Enter", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:620:27");
                local conf = EnsureKeyDBFn and EnsureKeyDBFn()
                local v = conf and conf[confKey]
                return Perfy_Trace_Passthrough("Leave", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:620:27", (v == opt.value))
            end
            UIDropDownMenu_AddButton(info, level)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:611:34"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BindDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:589:6"); end

local MSUF_ALPHA_SLIDER_SPECS = {
    { field = "playerAlphaInCombatSlider",  isInCombat = true,  otherField = "playerAlphaOutCombatSlider" },
    { field = "playerAlphaOutCombatSlider", isInCombat = false, otherField = "playerAlphaInCombatSlider" },
}
local function MSUF_ApplyCheck(panel, widgetKey, show, checked) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ApplyCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:634:6");
    if not panel or not widgetKey then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:634:6"); return end
    local w = panel[widgetKey]
    if not w then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:634:6"); return end
    if w.SetShown then w:SetShown(show and true or false) end
    if show and w.SetChecked then w:SetChecked(checked and true or false) end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:634:6"); end

local function MSUF_ApplyDropdown(panel, widgetKey, show, value, textLabel) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ApplyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:642:6");
    if not panel or not widgetKey then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:642:6"); return end
    local d = panel[widgetKey]
    if not d then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:642:6"); return end
    if d.SetShown then d:SetShown(show and true or false) end
    if show then
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(d, value) end
        if UIDropDownMenu_SetText and textLabel then UIDropDownMenu_SetText(d, textLabel) end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:642:6"); end

local function MSUF_GetShowWithFallback(storedValue, fallbackValue) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetShowWithFallback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:653:6");
    if storedValue == nil then
        return Perfy_Trace_Passthrough("Leave", "MSUF_GetShowWithFallback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:653:6", (fallbackValue ~= false))
    end
    return Perfy_Trace_Passthrough("Leave", "MSUF_GetShowWithFallback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:653:6", (storedValue ~= false))
end

local MSUF_BASIC_CB_SPECS = {
    { w = "playerEnableFrameCB", eval = function(conf) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:661:40"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:661:40", (conf.enabled ~= false)) end },
    { w = "playerShowNameCB",    eval = function(conf) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:662:40"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:662:40", (conf.showName ~= false)) end },
    { w = "playerShowHPCB",      eval = function(conf) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:663:40"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:663:40", (conf.showHP ~= false)) end },
    { w = "playerShowPowerCB",   eval = function(conf) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:664:40"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:664:40", (conf.showPower ~= false)) end },
    { w = "playerReverseFillBarsCB", eval = function(conf) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:665:44"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:665:44", (conf.reverseFillBars == true)) end },
}

local MSUF_CASTBAR_FRAME_TOGGLE_SPECS = {
    { key = "player", enableW = "playerCastbarEnableCB", enableK = "enablePlayerCastbar", timeW = "playerCastbarTimeCB", timeK = "showPlayerCastTime", interruptW = "playerCastbarInterruptCB" },
    { key = "target", enableW = "targetCastbarEnableCB", enableK = "enableTargetCastbar", timeW = "targetCastbarTimeCB", timeK = "showTargetCastTime", interruptW = "targetCastbarInterruptCB" },
    { key = "focus",  enableW = "focusCastbarEnableCB",  enableK = "enableFocusCastbar",  timeW = "focusCastbarTimeCB",  timeK = "showFocusCastTime",  interruptW = "focusCastbarInterruptCB" },
    { key = "boss",   enableW = "bossCastbarEnableCB",   enableK = "enableBossCastbar",   timeW = "bossCastbarTimeCB",   timeK = "showBossCastTime",   interruptW = "bossCastbarInterruptCB" },
}

local MSUF_CASTBAR_TEXTICON_SPECS = {
    { key = "player", iconW = "playerCastbarShowIconCB", iconK = "castbarPlayerShowIcon", textW = "playerCastbarShowTextCB", textK = "castbarPlayerShowSpellName", textDirect = false },
    { key = "target", iconW = "targetCastbarShowIconCB", iconK = "castbarTargetShowIcon", textW = "targetCastbarShowTextCB", textK = "castbarTargetShowSpellName", textDirect = false },
    { key = "focus",  iconW = "focusCastbarShowIconCB",  iconK = "castbarFocusShowIcon",  textW = "focusCastbarShowTextCB",  textK = "castbarFocusShowSpellName",  textDirect = false },
    { key = "boss",   iconW = "bossCastbarShowIconCB",   iconK = "showBossCastIcon",      textW = "bossCastbarShowTextCB",   textK = "showBossCastName",           textDirect = true },
}

-- Copy-to-all confirmation dialog helper (used by Copy To dropdowns).
-- UI-safe: uses a standard StaticPopup YES/NO confirmation.
local function MSUF_EnsureCopyToAllDialog() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EnsureCopyToAllDialog file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:684:6");
    if not StaticPopupDialogs then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EnsureCopyToAllDialog file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:684:6"); return end
    if StaticPopupDialogs["MSUF_COPY_TO_ALL_CONFIRM"] then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EnsureCopyToAllDialog file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:684:6"); return end

    StaticPopupDialogs["MSUF_COPY_TO_ALL_CONFIRM"] = {
        text = "Copy these settings to ALL unitframes?\n\nThis will overwrite existing settings on Player/Target/Focus/Boss/Pet/Target of Target.",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function(self, data) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:692:19");
            if type(data) == "function" then
                data()
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:692:19"); end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EnsureCopyToAllDialog file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:684:6"); end

local function MSUF_ConfirmCopyToAll(callback) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ConfirmCopyToAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:704:6");
    if type(callback) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ConfirmCopyToAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:704:6"); return end
    MSUF_EnsureCopyToAllDialog()
    if StaticPopup_Show then
        StaticPopup_Show("MSUF_COPY_TO_ALL_CONFIRM", nil, nil, callback)
    else
        callback()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ConfirmCopyToAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:704:6"); end

_G.MSUF_ConfirmCopyToAll = MSUF_ConfirmCopyToAll


-- ============================================================
-- Copy Engine (deduplicated)
-- ============================================================
-- This used to be implemented as large per-unit inline blocks.
-- Keep it centralized so future fields/behavior changes are one edit.

local MSUF_COPY_BASIC_FIELDS = {
    "enabled",
    "showName",
    "showHP",
    "showPower",
    "reverseFillBars",
    "portraitMode",
    "portraitRender",
    "alphaInCombat",
    "alphaOutOfCombat",
    "alphaSync",

    -- Layered alpha (keep text+portrait visible)
    "alphaExcludeTextPortrait",
    "alphaLayerMode", -- stored as 0/1 or "foreground"/"background"
    "alphaFGInCombat",
    "alphaFGOutOfCombat",
    "alphaBGInCombat",
    "alphaBGOutOfCombat",
}

local MSUF_COPY_INDICATOR_FIELDS = {
    "showLeaderIcon",
    "leaderIconOffsetX",
    "leaderIconOffsetY",
    "leaderIconAnchor",
    "leaderIconSize",

    "showRaidMarker",
    "raidMarkerOffsetX",
    "raidMarkerOffsetY",
    "raidMarkerAnchor",
    "raidMarkerSize",

    "showLevelIndicator",
    "levelIndicatorOffsetX",
    "levelIndicatorOffsetY",
    "levelIndicatorAnchor",
    "levelIndicatorSize",
}

MSUF_COPY_STATUSICON_FIELDS = {
    -- Status Indicators / Icons (per-unitframe)
    "statusIconsTestMode",
    "statusIconsMidnightStyle",
    "statusIconsAlpha",

    "showCombatStateIndicator",
    "showRestingIndicator",
    "showIncomingResIndicator",

    "combatStateIndicatorOffsetX",
    "combatStateIndicatorOffsetY",
    "combatStateIndicatorAnchor",
    "combatStateIndicatorSize",
    "combatStateIndicatorSymbol",

    "restedStateIndicatorOffsetX",
    "restedStateIndicatorOffsetY",
    "restedStateIndicatorAnchor",
    "restedStateIndicatorSize",
    "restedStateIndicatorSymbol",

    "incomingResIndicatorOffsetX",
    "incomingResIndicatorOffsetY",
    "incomingResIndicatorAnchor",
    "incomingResIndicatorSize",
    "incomingResIndicatorSymbol",
}


local function MSUF_CanonUnitKey(k) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CanonUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:794:6");
    if not k then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CanonUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:794:6"); return nil end
    if type(k) ~= "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CanonUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:794:6"); return k end
    k = k:lower()
    if k:match("^boss") then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CanonUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:794:6"); return "boss" end
    if k == "tot" or k == "targetoftarget" or k == "target_of_target" or k == "targettarget" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CanonUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:794:6"); return "targettarget"
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CanonUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:794:6"); return k
end

local function MSUF_EnsureDB_IfPossible(api) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EnsureDB_IfPossible file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:805:6");
    -- EnsureDB is typically provided by core (global). Fall back to api.EnsureDB if available.
    if type(_G.EnsureDB) == "function" then
        _G.EnsureDB()
    elseif type(_G.MSUF_EnsureDB) == "function" then
        _G.MSUF_EnsureDB()
    elseif api and type(api.EnsureDB) == "function" then
        api.EnsureDB()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EnsureDB_IfPossible file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:805:6"); end

local function MSUF_EnsureUnitDB(key) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EnsureUnitDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:816:6");
    MSUF_DB = MSUF_DB or {}
    local k = MSUF_CanonUnitKey(key)
    if not k then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EnsureUnitDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:816:6"); return nil, nil end

    if k == "targettarget" then
        -- keep alias in sync for older builds
        MSUF_DB.targettarget = MSUF_DB.targettarget or MSUF_DB.tot or {}
        MSUF_DB.tot = MSUF_DB.targettarget
        return Perfy_Trace_Passthrough("Leave", "MSUF_EnsureUnitDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:816:6", MSUF_DB.targettarget, "targettarget")
    end

    MSUF_DB[k] = MSUF_DB[k] or {}
    return Perfy_Trace_Passthrough("Leave", "MSUF_EnsureUnitDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:816:6", MSUF_DB[k], k)
end

local function MSUF_CopyFieldList(dst, src, fields) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CopyFieldList file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:832:6");
    if not dst or not src or not fields then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CopyFieldList file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:832:6"); return end
    for i = 1, #fields do
        local f = fields[i]
        dst[f] = src[f]
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CopyFieldList file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:832:6"); end

local function MSUF_GetCastbarKeysForUnit(unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetCastbarKeysForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:840:6");
    unitKey = MSUF_CanonUnitKey(unitKey)
    if unitKey == "player" then
        return Perfy_Trace_Passthrough("Leave", "MSUF_GetCastbarKeysForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:840:6", { enable = "enablePlayerCastbar", time = "showPlayerCastTime", icon = "castbarPlayerShowIcon", name = "castbarPlayerShowSpellName" })
    elseif unitKey == "target" then
        return Perfy_Trace_Passthrough("Leave", "MSUF_GetCastbarKeysForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:840:6", { enable = "enableTargetCastbar", time = "showTargetCastTime", icon = "castbarTargetShowIcon", name = "castbarTargetShowSpellName" })
    elseif unitKey == "focus" then
        return Perfy_Trace_Passthrough("Leave", "MSUF_GetCastbarKeysForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:840:6", { enable = "enableFocusCastbar", time = "showFocusCastTime", icon = "castbarFocusShowIcon", name = "castbarFocusShowSpellName" })
    elseif unitKey == "boss" then
        return Perfy_Trace_Passthrough("Leave", "MSUF_GetCastbarKeysForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:840:6", { enable = "enableBossCastbar", time = "showBossCastTime", icon = "showBossCastIcon", name = "showBossCastName" })
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetCastbarKeysForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:840:6"); return nil
end

local function MSUF_CopyCastbarSettings(g, srcUnit, dstUnit) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CopyCastbarSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:854:6");
    if not g then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CopyCastbarSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:854:6"); return end
    srcUnit = MSUF_CanonUnitKey(srcUnit)
    dstUnit = MSUF_CanonUnitKey(dstUnit)

    local srcKeys = MSUF_GetCastbarKeysForUnit(srcUnit)
    local dstKeys = MSUF_GetCastbarKeysForUnit(dstUnit)
    if not srcKeys or not dstKeys then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CopyCastbarSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:854:6"); return end

    g[dstKeys.enable] = g[srcKeys.enable]
    g[dstKeys.time]   = g[srcKeys.time]
    g[dstKeys.icon]   = g[srcKeys.icon]
    g[dstKeys.name]   = g[srcKeys.name]
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CopyCastbarSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:854:6"); end

local function MSUF_CopyUnitSettings(srcKey, destKey, api) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CopyUnitSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:869:6");
    api = api or nil

    MSUF_EnsureDB_IfPossible(api)
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}

    srcKey = MSUF_CanonUnitKey(srcKey) or "player"
    destKey = (type(destKey) == "string") and destKey or "target"
    destKey = destKey:lower()

    local g = MSUF_DB.general

    local src, srcCanon = MSUF_EnsureUnitDB(srcKey)
    if not src or not srcCanon then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CopyUnitSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:869:6"); return end

    local function CopyOne(toKey) Perfy_Trace(Perfy_GetTime(), "Enter", "CopyOne file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:885:10");
        local dst, dstCanon = MSUF_EnsureUnitDB(toKey)
        if not dst or not dstCanon then Perfy_Trace(Perfy_GetTime(), "Leave", "CopyOne file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:885:10"); return end
        if dstCanon == srcCanon then Perfy_Trace(Perfy_GetTime(), "Leave", "CopyOne file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:885:10"); return end

        MSUF_CopyFieldList(dst, src, MSUF_COPY_BASIC_FIELDS)
        MSUF_CopyFieldList(dst, src, MSUF_COPY_INDICATOR_FIELDS)
        MSUF_CopyFieldList(dst, src, MSUF_COPY_STATUSICON_FIELDS)

        -- Per-unit castbar interrupt toggle
        dst.showInterrupt = src.showInterrupt

        -- Copy matching castbar settings in general DB (player/target/focus/boss)
        MSUF_CopyCastbarSettings(g, srcCanon, dstCanon)

        if api and api.ApplySettingsForKey then
            api.ApplySettingsForKey(dstCanon)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "CopyOne file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:885:10"); end

    if destKey == "all" then
        if _G.MSUF_ConfirmCopyToAll then
            _G.MSUF_ConfirmCopyToAll(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:907:37");
                local keys = { "player", "target", "focus", "boss", "pet", "targettarget" }
                for i = 1, #keys do
                    local k = keys[i]
                    if k ~= srcCanon then
                        CopyOne(k)
                    end
                end

                if _G.MSUF_UpdateCastbarVisuals then
                    _G.MSUF_UpdateCastbarVisuals()
                end
                if _G.MSUF_RefreshAllIndicators then
                    _G.MSUF_RefreshAllIndicators()
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:907:37"); end)
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CopyUnitSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:869:6"); return
    end

    CopyOne(destKey)

    if _G.MSUF_UpdateCastbarVisuals then
        _G.MSUF_UpdateCastbarVisuals()
    end
    if _G.MSUF_RefreshAllIndicators then
        _G.MSUF_RefreshAllIndicators()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CopyUnitSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:869:6"); end

local function MSUF_BindAllCopyButtons(panel) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_BindAllCopyButtons file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:937:6");
    if not panel then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BindAllCopyButtons file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:937:6"); return end

    local function Bind(btn, srcKey, destVar, defaultDest) Perfy_Trace(Perfy_GetTime(), "Enter", "Bind file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:940:10");
        if not btn or btn._msufCopyBound then Perfy_Trace(Perfy_GetTime(), "Leave", "Bind file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:940:10"); return end
        btn._msufCopyBound = true

        btn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:944:33");
            local isFramesTab = (panel._msufIsFramesTab and panel._msufIsFramesTab()) or (type(IsFramesTab) == "function" and IsFramesTab()) or true
            if not isFramesTab then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:944:33"); return end

            local api = panel._msufAPI
            local destKey = (destVar and panel[destVar]) or defaultDest
            MSUF_CopyUnitSettings(srcKey, destKey, api)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:944:33"); end)
    Perfy_Trace(Perfy_GetTime(), "Leave", "Bind file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:940:10"); end

    Bind(panel.playerCopyToButton, "player", "_msufCopyDestKey", "target")
    Bind(panel.targetCopyToButton, "target", "_msufCopyDestKey_target", "player")
    Bind(panel.focusCopyToButton,  "focus",  "_msufCopyDestKey_focus",  "target")
    Bind(panel.bossCopyToButton,   "boss",   "_msufCopyDestKey_boss",   "target")
    Bind(panel.petCopyToButton,    "pet",    "_msufCopyDestKey_pet",    "target")
    Bind(panel.totCopyToButton,    "targettarget", "_msufCopyDestKey_tot", "player")
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BindAllCopyButtons file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:937:6"); end


local function CreateGroupBox(parent, title, x, y, w, h, texWhite, texWhite2) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateGroupBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:963:6");
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(w, h)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    box:SetBackdrop({
        bgFile = texWhite or "Interface\\Buttons\\WHITE8X8",
        edgeFile = texWhite2 or "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    box:SetBackdropColor(0, 0, 0, 0.25)
    box:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)

    local titleText = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleText:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -6)
    titleText:SetText(title or "")

    local divider = box:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -22)
    divider:SetPoint("TOPRIGHT", box, "TOPRIGHT", -8, -22)
    divider:SetHeight(1)
    divider:SetColorTexture(1, 1, 1, 0.08)

    box._msufTitleText = titleText
    box._msufDivider = divider
    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateGroupBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:963:6"); return box
end

-- Expand the clickable area of a Blizzard UIDropDownMenu so the whole dropdown "box" is clickable,
-- not just the small arrow button. We do this by expanding the Button hit-rect to the dropdown size.
local function MSUF_ExpandDropdownClickArea(dropdown) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ExpandDropdownClickArea file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:994:6");
    if not dropdown or dropdown._msufClickAreaExpanded then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ExpandDropdownClickArea file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:994:6"); return end
    dropdown._msufClickAreaExpanded = true

    local function Apply() Perfy_Trace(Perfy_GetTime(), "Enter", "Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:998:10");
        local name = dropdown.GetName and dropdown:GetName()
        local btn = dropdown.Button or (name and _G[name .. "Button"])
        if not btn or not btn.SetHitRectInsets then Perfy_Trace(Perfy_GetTime(), "Leave", "Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:998:10"); return end

        local dw = tonumber(dropdown:GetWidth()) or 0
        local dh = tonumber(dropdown:GetHeight()) or 0
        local bw = tonumber(btn:GetWidth()) or 0
        local bh = tonumber(btn:GetHeight()) or 0

        local fallbackW = tonumber(dropdown._msufDropWidth) or 0
        if dw <= 1 and fallbackW > 1 then dw = fallbackW end

        -- Defer until we have real sizes (happens after layout/scale is applied).
        if dw <= 1 or dh <= 1 or bw <= 1 or bh <= 1 then
            if _G.C_Timer and type(_G.C_Timer.After) == "function" then
                _G.C_Timer.After(0, Apply)
            end
            Perfy_Trace(Perfy_GetTime(), "Leave", "Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:998:10"); return
        end

        local extendLeft = math.max(0, dw - bw)
        local extendTop  = math.max(0, (dh - bh) / 2)

        -- Negative insets expand the hit rect.
        btn:SetHitRectInsets(-extendLeft - 2, -2, -extendTop - 2, -extendTop - 2)
    Perfy_Trace(Perfy_GetTime(), "Leave", "Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:998:10"); end

    if dropdown.HookScript then
        dropdown:HookScript("OnShow", Apply)
        dropdown:HookScript("OnSizeChanged", Apply)
    end

    local name = dropdown.GetName and dropdown:GetName()
    local btn = dropdown.Button or (name and _G[name .. "Button"])
    if btn and btn.HookScript then
        btn:HookScript("OnSizeChanged", Apply)
    end

    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, Apply)
    else
        Apply()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ExpandDropdownClickArea file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:994:6"); end

local function CreateCheck(parent, name, label, x, y) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1044:6");
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if cb.Text then
        cb.Text:SetText(label)
    else
        local t = _G[name .. "Text"]
        if t then t:SetText(label) end
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1044:6"); return cb
end

local function ResizeStepper(stepper, width, editWidth) Perfy_Trace(Perfy_GetTime(), "Enter", "ResizeStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1056:6");
    if not stepper or not width then Perfy_Trace(Perfy_GetTime(), "Leave", "ResizeStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1056:6"); return end
    stepper:SetWidth(width)
    if stepper.editBox and editWidth then
        stepper.editBox:SetWidth(editWidth)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "ResizeStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1056:6"); end

-- Restyle a CreateAxisStepper() control to match the requested "no box" look:
-- Only +/- buttons are visible, with the axis label above.
local function RestyleStepperButtonsNoBox(stepper) Perfy_Trace(Perfy_GetTime(), "Enter", "RestyleStepperButtonsNoBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1066:6");
    if not stepper then Perfy_Trace(Perfy_GetTime(), "Leave", "RestyleStepperButtonsNoBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1066:6"); return end
    local eb = stepper.editBox
    local minus = stepper.minusButton
    local plus  = stepper.plusButton

    -- Hide the numeric box entirely (user requested no boxes).
    if eb then
        eb:Hide()
        eb:SetAlpha(0)
        eb:EnableMouse(false)
        eb:ClearAllPoints()
        -- Park it off-screen so it can't affect layout/anchoring.
        eb:SetPoint("TOPLEFT", stepper, "TOPLEFT", -2000, 0)
        eb:SetWidth(1)
    end

    -- Place buttons centered under the label.
    if minus then
        minus:ClearAllPoints()
        minus:SetPoint("LEFT", stepper, "LEFT", 0, 0)
    end
    if plus then
        plus:ClearAllPoints()
        plus:SetPoint("LEFT", (minus or stepper), "RIGHT", 2, 0)
    end

    -- Make the overall control compact.
    local w = 46
    if minus and minus.GetWidth then w = (minus:GetWidth() or 22) + (plus and (plus:GetWidth() or 22) or 0) + 2 end
    stepper:SetWidth(w)
Perfy_Trace(Perfy_GetTime(), "Leave", "RestyleStepperButtonsNoBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1066:6"); end


local function ClampNumber(v, minVal, maxVal) Perfy_Trace(Perfy_GetTime(), "Enter", "ClampNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1100:6");
    v = tonumber(v) or 0
    if minVal and v < minVal then v = minVal end
    if maxVal and v > maxVal then v = maxVal end
    Perfy_Trace(Perfy_GetTime(), "Leave", "ClampNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1100:6"); return v
end

local function FormatSliderValue(slider, value) Perfy_Trace(Perfy_GetTime(), "Enter", "FormatSliderValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1107:6");
    local step = (slider and slider.step) or (slider and slider.GetValueStep and slider:GetValueStep()) or 1
    if step and step >= 1 then
        return Perfy_Trace_Passthrough("Leave", "FormatSliderValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1107:6", tostring(math.floor((value or 0) + 0.5)))
    end
    -- keep it simple (2 decimals)
    local precision = 2
    return Perfy_Trace_Passthrough("Leave", "FormatSliderValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1107:6", string.format("%." .. precision .. "f", tonumber(value) or 0))
end

local function ForceSliderEditBox(slider) Perfy_Trace(Perfy_GetTime(), "Enter", "ForceSliderEditBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1117:6");
    if not slider or not slider.editBox then Perfy_Trace(Perfy_GetTime(), "Leave", "ForceSliderEditBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1117:6"); return end
    if slider.editBox:HasFocus() then Perfy_Trace(Perfy_GetTime(), "Leave", "ForceSliderEditBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1117:6"); return end
    local v = slider.GetValue and slider:GetValue() or 0
    slider.editBox:SetText(FormatSliderValue(slider, v))
Perfy_Trace(Perfy_GetTime(), "Leave", "ForceSliderEditBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1117:6"); end

-- Stepper modifier support (requested):
-- default = 1px, Shift = 5px, Ctrl = 10px
-- Alt = grid step (matches Edit Mode)
-- (Alt > Ctrl > Shift priority)
local function MSUF_GetCurrentGridStep() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetCurrentGridStep file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1128:6");
    local MIN, MAX = 8, 64
    local step

    local slider = _G and _G["MSUF_EditModeGridSlider"]
    if slider and slider.GetValue then
        step = slider:GetValue()
    elseif MSUF_DB and MSUF_DB.general and type(MSUF_DB.general.editModeGridStep) == "number" then
        step = MSUF_DB.general.editModeGridStep
    else
        step = 20
    end

    step = tonumber(step) or 20
    if step < MIN then step = MIN end
    if step > MAX then step = MAX end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetCurrentGridStep file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1128:6"); return step
end

local function MSUF_GetModifierStep(baseStep) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetModifierStep file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1147:6");
    baseStep = tonumber(baseStep) or 1

    -- Alt: grid step
    if IsAltKeyDown and IsAltKeyDown() then
        return Perfy_Trace_Passthrough("Leave", "MSUF_GetModifierStep file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1147:6", MSUF_GetCurrentGridStep())
    end

    local mult = 1
    if IsControlKeyDown and IsControlKeyDown() then
        mult = 10
    elseif IsShiftKeyDown and IsShiftKeyDown() then
        mult = 5
    end
    return Perfy_Trace_Passthrough("Leave", "MSUF_GetModifierStep file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1147:6", baseStep * mult)
end

-- One-time session tip popup for stepper modifiers (Options menu)
local function MSUF_ShowStepperTipOnce(stepper) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ShowStepperTipOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1165:6");
    if _G.MSUF_OptionsStepperTipShown then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ShowStepperTipOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1165:6"); return end
    _G.MSUF_OptionsStepperTipShown = true

    local parent = (stepper and stepper.GetParent and stepper:GetParent()) or UIParent
    if not parent then parent = UIParent end

    local f = parent._msufStepperTipFrame
    if not f then
        f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        f:SetSize(430, 22)
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        f:SetBackdropColor(0, 0, 0, 0.45)
        f:SetBackdropBorderColor(1, 1, 1, 0.12)

        local t = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        t:SetPoint("CENTER", f, "CENTER", 0, 0)
        t:SetText("Tip: Hold SHIFT (5) / CTRL (10) / ALT (grid step) for bigger steps.")
        f.text = t

        f:Hide()
        parent._msufStepperTipFrame = f
    end

    f:ClearAllPoints()
    f:SetPoint("BOTTOM", parent, "BOTTOM", 0, 8)

    local lvl = (parent.GetFrameLevel and parent:GetFrameLevel()) or 0
    if f.SetFrameLevel then f:SetFrameLevel(lvl + 50) end

    f:Show()
    if C_Timer and C_Timer.After then
        C_Timer.After(6, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1202:25");
            if f and f.Hide then f:Hide() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1202:25"); end)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ShowStepperTipOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1165:6"); end

local function MSUF_ApplyModifierStepper(stepper) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ApplyModifierStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1208:6");
    if not stepper or not stepper.minusButton or not stepper.plusButton then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyModifierStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1208:6"); return end

    stepper.minusButton:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1211:45");
        MSUF_ShowStepperTipOnce(stepper)
        local delta = MSUF_GetModifierStep(stepper.step or 1)
        stepper:SetValue((stepper:GetValue() or 0) - delta, true)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1211:45"); end)

    stepper.plusButton:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1217:44");
        MSUF_ShowStepperTipOnce(stepper)
        local delta = MSUF_GetModifierStep(stepper.step or 1)
        stepper:SetValue((stepper:GetValue() or 0) + delta, true)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1217:44"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyModifierStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1208:6"); end

-- BUILD
function ns.MSUF_Options_Player_Build(panel, frameGroup, helpers) Perfy_Trace(Perfy_GetTime(), "Enter", "ns.MSUF_Options_Player_Build file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1225:0");
    if not panel or not frameGroup or not helpers then Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_Options_Player_Build file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1225:0"); return end

    local CreateAxisStepper = helpers.CreateAxisStepper
    local CreateLabeledSlider = helpers.CreateLabeledSlider
    local texWhite = helpers.texWhite
    local texWhite2 = helpers.texWhite2
    -- Layout constants (GOOD layout)
    local leftX, topY = 8, -110
    local leftW = 250
    local gap = 16
    local rightX = leftX + leftW + gap
    local rightW = 410

    -- Make slider track/line more visible (especially on dark MSUF panels)
    local function MSUF_EnhanceSliderTrack(slider) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EnhanceSliderTrack file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1240:10");
        if not slider or slider._msufTrackEnhanced then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EnhanceSliderTrack file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1240:10"); return end

        -- Create a higher-contrast "rail" behind the slider bar
        local rail = slider:CreateTexture(nil, "BACKGROUND")
        rail:SetPoint("LEFT", slider, "LEFT", 2, 0)
        rail:SetPoint("RIGHT", slider, "RIGHT", -2, 0)
        rail:SetHeight(10)
        rail:SetColorTexture(0, 0, 0, 0.85)

        -- Add a brighter center line to improve readability
        local line = slider:CreateTexture(nil, "BORDER")
        line:SetPoint("LEFT", rail, "LEFT", 0, 0)
        line:SetPoint("RIGHT", rail, "RIGHT", 0, 0)
        line:SetHeight(3)
        line:SetColorTexture(1, 1, 1, 0.65)

        -- Subtle border around the rail (helps against dark backgrounds)
        local bTop = slider:CreateTexture(nil, "BORDER")
        bTop:SetPoint("TOPLEFT", rail, "TOPLEFT", -1, 1)
        bTop:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 1, 1)
        bTop:SetHeight(1)
        bTop:SetColorTexture(1, 1, 1, 0.18)

        local bBot = slider:CreateTexture(nil, "BORDER")
        bBot:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", -1, -1)
        bBot:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", 1, -1)
        bBot:SetHeight(1)
        bBot:SetColorTexture(1, 1, 1, 0.18)

        -- Larger thumb for easier grabbing
        local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
        if thumb and thumb.SetSize then
            thumb:SetSize(18, 18)
        end

        slider._msufTrackEnhanced = true
        slider._msufTrackRail = rail
        slider._msufTrackLine = line
        slider._msufTrackBorderTop = bTop
        slider._msufTrackBorderBot = bBot
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EnhanceSliderTrack file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1240:10"); end



    -- Animated "fill" for alpha sliders (visualizes current alpha as a shrinking/growing bar).
    -- Designed to look like Blizzard slider fill (UI-SliderBar-Fill) and animate from filled->empty smoothly.
    function MSUF_EnableAnimatedAlphaFill(slider) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EnableAnimatedAlphaFill file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1287:4");
        if not slider or slider._msufAlphaFillEnabled then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EnableAnimatedAlphaFill file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1287:4"); return end

        -- Ensure we have the enhanced rail to anchor into
        if not slider._msufTrackRail then
            if MSUF_EnhanceSliderTrack then MSUF_EnhanceSliderTrack(slider) end
        end

        local rail = slider._msufTrackRail
        if not rail then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EnableAnimatedAlphaFill file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1287:4"); return end

        local insetX, insetY = 2, 2

        local fill = slider:CreateTexture(nil, "ARTWORK")
        fill:SetTexture("Interface\\Buttons\\UI-SliderBar-Fill")
        if fill.SetHorizTile then fill:SetHorizTile(true) end
        fill:SetPoint("TOPLEFT", rail, "TOPLEFT", insetX, -insetY)
        fill:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", insetX, insetY)
        fill:SetWidth(1)
        fill:SetAlpha(0.90)

        slider._msufAlphaFill = fill
        slider._msufAlphaFillInsetX = insetX
        slider._msufAlphaFillInsetY = insetY
        slider._msufAlphaFillCur = nil
        slider._msufAlphaFillTarget = nil
        slider._msufAlphaFillEnabled = true

        -- Dedicated animation driver so we don't stomp any existing OnUpdate on the slider
        local anim = CreateFrame("Frame", nil, slider)
        anim:Hide()
        slider._msufAlphaFillAnim = anim

        local function GetMaxValue() Perfy_Trace(Perfy_GetTime(), "Enter", "GetMaxValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1320:14");
            if slider.maxVal then return Perfy_Trace_Passthrough("Leave", "GetMaxValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1320:14", slider.maxVal) end
            if slider.GetMinMaxValues then
                local _, mx = slider:GetMinMaxValues()
                Perfy_Trace(Perfy_GetTime(), "Leave", "GetMaxValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1320:14"); return mx
            end
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetMaxValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1320:14"); return 1
        end

        local function Clamp01(x) Perfy_Trace(Perfy_GetTime(), "Enter", "Clamp01 file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1329:14");
            if x < 0 then Perfy_Trace(Perfy_GetTime(), "Leave", "Clamp01 file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1329:14"); return 0 end
            if x > 1 then Perfy_Trace(Perfy_GetTime(), "Leave", "Clamp01 file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1329:14"); return 1 end
            Perfy_Trace(Perfy_GetTime(), "Leave", "Clamp01 file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1329:14"); return x
        end

        local function GetUsableWidth() Perfy_Trace(Perfy_GetTime(), "Enter", "GetUsableWidth file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1335:14");
            local w = rail.GetWidth and rail:GetWidth() or 0
            if not w or w <= 0 then
                w = slider.GetWidth and slider:GetWidth() or 0
            end
            w = (w or 0) - (insetX * 2)
            if w < 1 then w = 1 end
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetUsableWidth file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1335:14"); return w
        end

        local function ApplyFrac(frac) Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyFrac file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1345:14");
            frac = Clamp01(frac or 0)
            local w = GetUsableWidth()
            fill:SetWidth(w * frac)
        Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyFrac file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1345:14"); end

        local function SetTarget(frac, instant) Perfy_Trace(Perfy_GetTime(), "Enter", "SetTarget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1351:14");
            frac = Clamp01(frac or 0)

            if slider._msufAlphaFillCur == nil then
                slider._msufAlphaFillCur = frac
                slider._msufAlphaFillTarget = frac
                ApplyFrac(frac)
                Perfy_Trace(Perfy_GetTime(), "Leave", "SetTarget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1351:14"); return
            end

            slider._msufAlphaFillTarget = frac

            if instant then
                slider._msufAlphaFillCur = frac
                ApplyFrac(frac)
                anim:Hide()
                Perfy_Trace(Perfy_GetTime(), "Leave", "SetTarget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1351:14"); return
            end

            -- Start anim
            slider._msufAlphaFillStart = slider._msufAlphaFillCur
            slider._msufAlphaFillStartTime = GetTime()
            slider._msufAlphaFillDur = 0.14
            anim:Show()
        Perfy_Trace(Perfy_GetTime(), "Leave", "SetTarget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1351:14"); end

        anim:SetScript("OnUpdate", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1377:35");
            local t0 = slider._msufAlphaFillStartTime
            local dur = slider._msufAlphaFillDur or 0.14
            if not t0 then self:Hide(); Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1377:35"); return end

            local p = (GetTime() - t0) / dur
            if p >= 1 then
                slider._msufAlphaFillCur = slider._msufAlphaFillTarget
                ApplyFrac(slider._msufAlphaFillCur)
                self:Hide()
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1377:35"); return
            end

            -- easeOutQuad
            local e = 1 - (1 - p) * (1 - p)
            local a = slider._msufAlphaFillStart or 0
            local b = slider._msufAlphaFillTarget or a
            local cur = a + (b - a) * e
            slider._msufAlphaFillCur = cur
            ApplyFrac(cur)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1377:35"); end)

        local function UpdateFromValue(value, instant) Perfy_Trace(Perfy_GetTime(), "Enter", "UpdateFromValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1399:14");
            local mx = GetMaxValue()
            if not mx or mx <= 0 then mx = 1 end
            local frac = (value or 0) / mx
            SetTarget(frac, instant)
        Perfy_Trace(Perfy_GetTime(), "Leave", "UpdateFromValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1399:14"); end

        -- Dragging should feel snappy (no laggy animation while moving the thumb)
        slider:HookScript("OnMouseDown", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1407:41"); slider._msufAlphaFillDragging = true Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1407:41"); end)
        slider:HookScript("OnMouseUp", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1408:39");
            slider._msufAlphaFillDragging = false
            if slider.GetValue then
                UpdateFromValue(slider:GetValue(), true)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1408:39"); end)

        slider:HookScript("OnValueChanged", function(_, value) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1415:44");
            UpdateFromValue(value, slider._msufAlphaFillDragging)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1415:44"); end)

        -- Size changes / first layout pass
        slider:HookScript("OnSizeChanged", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1420:43");
            if slider.GetValue then
                UpdateFromValue(slider:GetValue(), true)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1420:43"); end)

        -- Initial sync next tick (rail width is 0 at creation time sometimes)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1428:29");
                if slider and slider.GetValue then
                    UpdateFromValue(slider:GetValue(), true)
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1428:29"); end)
        else
            if slider.GetValue then UpdateFromValue(slider:GetValue(), true) end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EnableAnimatedAlphaFill file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1287:4"); end

    -- Slightly taller: accommodates the per-unit reverse-fill toggle above the portrait dropdown.
    local basicsH = 202
    -- Slightly taller so the new Alpha dropdown + sliders never clip
    local sizeH = 245
    local bossExtraH = 60
    local sizeBossH = sizeH + bossExtraH

    -- Left: Frame Basics
    local basicsBox = CreateGroupBox(frameGroup, "Frame Basics", leftX, topY, leftW, basicsH, texWhite, texWhite2)
    basicsBox:Hide()
    panel.playerBasicsBox = basicsBox

    -- Enable/Disable + Display toggles (spec-driven; keep widget names)
    local BASIC_TOGGLES = {
        { field = "playerEnableFrameCB", name = "MSUF_UF_EnableFrameCB", label = "Enable this frame", x = 12, y = -34 },
        { field = "playerShowNameCB",    name = "MSUF_UF_ShowNameCB",   label = "Show name",         x = 12, y = -58 },
        { field = "playerShowHPCB",      name = "MSUF_UF_ShowHPCB",     label = "Show HP text",      x = 12, y = -82 },
        { field = "playerShowPowerCB",   name = "MSUF_UF_ShowPowerCB",  label = "Show power text",   x = 12, y = -106 },
        { field = "playerReverseFillBarsCB", name = "MSUF_UF_ReverseFillBarsCB", label = "Reverse fill (HP/Power)", x = 12, y = -130 },
    }
    for _, s in ipairs(BASIC_TOGGLES) do
        panel[s.field] = CreateCheck(basicsBox, s.name, s.label, s.x, s.y)
    end

    -- Portrait dropdown under display toggles.

    local dd = CreateFrame("Frame", "MSUF_UF_PortraitDropDown", basicsBox, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", basicsBox, "TOPLEFT", -6, -162)
    dd:Show() -- portrait dropdown (all unitframes)
    panel.playerPortraitDropDown = dd

    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(dd, 170)
    end
    
    dd._msufDropWidth = 170
    MSUF_ExpandDropdownClickArea(dd)

    -- Left: Unit Alpha
    local sizeBox = CreateGroupBox(frameGroup, "Unit Alpha", leftX, topY - basicsH - 12, leftW, sizeH, texWhite, texWhite2)
    sizeBox:Hide()
    panel.playerSizeBox = sizeBox

    -- Store base/boss heights for dynamic boss-only extension
    panel._msufBasicsH = basicsH
    panel._msufSizeBaseH = sizeH
    panel._msufSizeBossH = sizeBossH

    -- Unit Alpha controls (in/out of combat)

    -- Top-right toggle: sync both sliders
    local alphaSyncCB = CreateFrame("CheckButton", "MSUF_UF_AlphaSyncCB", sizeBox, "UICheckButtonTemplate")
    alphaSyncCB:SetPoint("TOPRIGHT", sizeBox, "TOPRIGHT", -12, -6)
    if alphaSyncCB.Text then
        alphaSyncCB.Text:SetText("Sync both")
        alphaSyncCB.Text:ClearAllPoints()
        alphaSyncCB.Text:SetPoint("RIGHT", alphaSyncCB, "LEFT", -4, 0)
        alphaSyncCB.Text:SetJustifyH("RIGHT")
    end
    panel.playerAlphaSyncCB = alphaSyncCB


    -- New: Exclude Text/Portrait from Unit Alpha + choose alpha target layer (background/foreground)
    local alphaExcludeCB = CreateFrame("CheckButton", "MSUF_UF_AlphaExcludeTextPortraitCB", sizeBox, "UICheckButtonTemplate")
    alphaExcludeCB:SetPoint("TOPLEFT", sizeBox, "TOPLEFT", 12, -25)
    if alphaExcludeCB.Text then
        alphaExcludeCB.Text:SetText("Keep text + portrait visible")
    end
    panel.playerAlphaExcludeTextPortraitCB = alphaExcludeCB

    local alphaLayerLabel = sizeBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    alphaLayerLabel:SetPoint("TOPLEFT", sizeBox, "TOPLEFT", 12, -58)
    alphaLayerLabel:SetText("Alpha sliders affect")

    local alphaLayerDD = CreateFrame("Frame", "MSUF_UF_AlphaLayerDropDown", sizeBox, "UIDropDownMenuTemplate")
    alphaLayerDD:SetPoint("TOPLEFT", sizeBox, "TOPLEFT", -6, -70)
    alphaLayerDD:Show()
    panel.playerAlphaLayerDropDown = alphaLayerDD
    if UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(alphaLayerDD, 170)
    end
    alphaLayerDD._msufDropWidth = 170
    if MSUF_ExpandDropdownClickArea then
        MSUF_ExpandDropdownClickArea(alphaLayerDD)
    end

    local function FinalizeCompactSlider(slider, width, opts) Perfy_Trace(Perfy_GetTime(), "Enter", "FinalizeCompactSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1524:10");
        if not slider then Perfy_Trace(Perfy_GetTime(), "Leave", "FinalizeCompactSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1524:10"); return end
        slider:SetWidth(width or (leftW - 24))
        if slider.editBox then slider.editBox:Hide() end
        if slider.minusButton then slider.minusButton:Hide() end
        if slider.plusButton then slider.plusButton:Hide() end
        if MSUF_EnhanceSliderTrack then
            MSUF_EnhanceSliderTrack(slider)
        end
        if opts and opts.animatedFill and MSUF_EnableAnimatedAlphaFill then
            MSUF_EnableAnimatedAlphaFill(slider)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "FinalizeCompactSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1524:10"); end

local function FinalizeDashboardAlphaSlider(slider, width) Perfy_Trace(Perfy_GetTime(), "Enter", "FinalizeDashboardAlphaSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1538:6");
    if not slider then Perfy_Trace(Perfy_GetTime(), "Leave", "FinalizeDashboardAlphaSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1538:6"); return end

    -- Make it easier to grab.
    slider:SetWidth(width or (leftW - 24))

    if MSUF_EnhanceSliderTrack then
        MSUF_EnhanceSliderTrack(slider)
    end

    -- Stepper row (editbox +/-) like the Dashboard sliders.
    local eb = slider.editBox
    local minus = slider.minusButton
    local plus  = slider.plusButton

    if eb then
        eb:Show()
        eb:ClearAllPoints()
        eb:SetPoint("TOP", slider, "BOTTOM", 0, -12)
        eb:SetWidth(40)
    end
    if minus then
        minus:Show()
        minus:ClearAllPoints()
        minus:SetPoint("RIGHT", (eb or slider), "LEFT", -4, 0)
    end
    if plus then
        plus:Show()
        plus:ClearAllPoints()
        plus:SetPoint("LEFT", (eb or slider), "RIGHT", 4, 0)
    end

    local name = slider.GetName and slider:GetName()
    local low  = name and _G[name .. "Low"]
    local high = name and _G[name .. "High"]
    if low then
        low:ClearAllPoints()
        low:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
    end
    if high then
        high:ClearAllPoints()
        high:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
    end
    if slider.SetHitRectInsets then
        slider:SetHitRectInsets(-6, -6, -14, -14)
    end

    -- Ensure the thumb is visible immediately.
    local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
    if thumb then
        if thumb.SetAlpha then thumb:SetAlpha(1) end
        if thumb.Show then thumb:Show() end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "FinalizeDashboardAlphaSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1538:6"); end

    -- Push sliders down a bit so the dropdown never overlaps/clips them
    local ALPHA_SPECS = {
        { field = "playerAlphaInCombatSlider",  name = "MSUF_UF_AlphaInCombatSlider",  label = "Alpha in combat",      y = -118 },
        { field = "playerAlphaOutCombatSlider", name = "MSUF_UF_AlphaOutCombatSlider", label = "Alpha out of combat", y = -178 },
    }
    for _, s in ipairs(ALPHA_SPECS) do
        panel[s.field] = CreateLabeledSlider(s.name, s.label, sizeBox, 0.00, 1.00, 0.05, 12, s.y)
        FinalizeDashboardAlphaSlider(panel[s.field], (leftW - 24))
    end


    -- Right: Castbar group (Castbar + Indicator)
    -- Keep this compact for ALL unit pages. Status Icons get their own box (player/target only).
    local _msufTextBaseH = 390
    panel._msufTextBaseH = _msufTextBaseH
    local textGroup = CreateGroupBox(frameGroup, "Castbar", rightX, topY, rightW, _msufTextBaseH, texWhite, texWhite2)
    textGroup:Hide()
    panel.playerTextLayoutGroup = textGroup
    panel._msufTextGroup = textGroup

    -- Separate Status Icons box (player/target only; shown/hidden by LayoutIndicatorTemplate)
    local _msufStatusBoxH = 300
    panel._msufStatusBoxH = _msufStatusBoxH
    local statusBox = CreateGroupBox(frameGroup, "Status icons", rightX, topY - _msufTextBaseH - 12, rightW, _msufStatusBoxH, texWhite, texWhite2)
    statusBox:Hide()
    panel._msufStatusIconsGroup = statusBox



-- ToT-only utility: show Target-of-Target name inline in the Target frame name line.
panel.totShowInTargetCB = CreateCheck(textGroup, "MSUF_ToTInlineInTargetCB", "Show ToT text in Target frame", 12, -32)
panel.totShowInTargetCB:Hide()

-- Separator dropdown (no title) directly under the toggle.
local totSepDD = CreateFrame("Frame", "MSUF_ToTInlineSeparatorDropDown", textGroup, "UIDropDownMenuTemplate")
-- Anchor to the toggle (not the box) so any future/reflowed layout changes can't "strand" the dropdown.
-- UIDropDownMenuTemplate is left-shifted vs. CheckButtons, hence the -18 X offset.
if panel.totShowInTargetCB then
    totSepDD:SetPoint("TOPLEFT", panel.totShowInTargetCB, "BOTTOMLEFT", -18, -6)
    if totSepDD.SetFrameLevel and panel.totShowInTargetCB.GetFrameLevel then
        totSepDD:SetFrameLevel((panel.totShowInTargetCB:GetFrameLevel() or 0) + 2)
    end
else
    totSepDD:SetPoint("TOPLEFT", textGroup, "TOPLEFT", -6, -52)
end
totSepDD:Hide()
panel.totInlineSeparatorDD = totSepDD
if UIDropDownMenu_SetWidth then
    UIDropDownMenu_SetWidth(totSepDD, 170)
end
totSepDD._msufDropWidth = 170
if MSUF_ExpandDropdownClickArea then
    MSUF_ExpandDropdownClickArea(totSepDD)
end


    

    -- Player-only: Player castbar toggles live in the Frames tab -> Text box.

    -- Castbar toggles (Player/Target/Focus/Boss) live in the Frames tab -> Castbar box.
    -- These overlap each other and are shown/hidden based on the selected unitframe tab.
    local CASTBAR_UI_SPECS = {
        { key = "player", cap = "Player", enableText = "Enable player castbar", timeText = "Show player cast time", defaultVisible = true },
        { key = "target", cap = "Target", enableText = "Enable target castbar", timeText = "Show target cast time" },
        { key = "focus",  cap = "Focus",  enableText = "Enable focus castbar",  timeText = "Show focus cast time"  },
        { key = "boss",   cap = "Boss",   enableText = "Enable boss castbars", timeText = "Show boss cast time"   },
    }

    for _, spec in ipairs(CASTBAR_UI_SPECS) do
        local key, cap = spec.key, spec.cap

        panel[key .. "CastbarEnableCB"] = CreateCheck(textGroup, "MSUF_" .. cap .. "CastbarEnableCB", spec.enableText, 12, -34)
        panel[key .. "CastbarShowIconCB"] = CreateCheck(textGroup, "MSUF_" .. cap .. "CastbarShowIconCB", "Icon", 230, -34)
        panel[key .. "CastbarShowTextCB"] = CreateCheck(textGroup, "MSUF_" .. cap .. "CastbarShowTextCB", "Text", 300, -34)
        panel[key .. "CastbarTimeCB"]   = CreateCheck(textGroup, "MSUF_" .. cap .. "CastbarTimeCB",   spec.timeText, 12, -58)
        panel[key .. "CastbarInterruptCB"] = CreateCheck(textGroup, "MSUF_" .. cap .. "CastbarInterruptCB", "Show interrupt", 12, -82)

        if not spec.defaultVisible then
            if panel[key .. "CastbarEnableCB"] then panel[key .. "CastbarEnableCB"]:Hide() end
            if panel[key .. "CastbarShowIconCB"] then panel[key .. "CastbarShowIconCB"]:Hide() end
            if panel[key .. "CastbarShowTextCB"] then panel[key .. "CastbarShowTextCB"]:Hide() end
            if panel[key .. "CastbarTimeCB"] then panel[key .. "CastbarTimeCB"]:Hide() end
            if panel[key .. "CastbarInterruptCB"] then panel[key .. "CastbarInterruptCB"]:Hide() end
        end
    end





		---------------------------------------------------------------------
		-- Indicator (Leader / Raid Marker / Level) — spec-driven build
		-- All layout for other unit tabs is handled by LayoutIndicatorTemplate().
		---------------------------------------------------------------------

		-- Section title (anchored to first divider in LayoutIndicatorTemplate)
		if not panel.playerLeaderIndicatorHeader then
			panel.playerLeaderIndicatorHeader = textGroup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		end
		panel.playerLeaderIndicatorHeader:SetText("Indicator")
		panel.playerLeaderIndicatorHeader:Hide()

		-- Shared layout constants for the indicator template
		local IND_COL_X          = 175
		local IND_BASE_TOGGLE_Y  = -163
		local IND_BASE_CTRL_Y    = -178
		local IND_ROW_STEP       = -64  -- Y offsets are negative: going "down" means more negative.
		local IND_DIVIDER_OFFSET = 23

		panel._msufIndicatorLayout = panel._msufIndicatorLayout or {}
		panel._msufIndicatorLayout.colX          = IND_COL_X
		panel._msufIndicatorLayout.leaderToggleY = IND_BASE_TOGGLE_Y
		panel._msufIndicatorLayout.leaderCtrlY   = IND_BASE_CTRL_Y
		panel._msufIndicatorLayout.rowStep       = IND_ROW_STEP
		panel._msufIndicatorLayout.dividerOffset = IND_DIVIDER_OFFSET

		-- Boss-only: spacing slider (shown only on boss pages by LayoutIndicatorTemplate)
		local bossSpacingY = (IND_BASE_CTRL_Y + (2 * IND_ROW_STEP)) - 42
		panel.playerBossSpacingSlider = panel.playerBossSpacingSlider or CreateLabeledSlider("MSUF_UF_BossSpacingSlider", "Boss spacing", textGroup, -200, 0, 1, 12, bossSpacingY)
		FinalizeCompactSlider(panel.playerBossSpacingSlider, (rightW - 24))
		panel.playerBossSpacingSlider:Hide()

		-- Status icons (player/target only; lives in its own box)
		local statusBox = panel._msufStatusIconsGroup
		local STATUS_BASE_TOGGLE_Y = -34
		local STATUS_BASE_CTRL_Y   = -49
		local STATUS_ROW_STEP      = -64

		panel.statusIconsHeader = panel.statusIconsHeader or (statusBox and statusBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
		if panel.statusIconsHeader then
			panel.statusIconsHeader:SetText("Status icons")
			panel.statusIconsHeader:Hide()
		end

		panel.statusCombatIconCB = panel.statusCombatIconCB or CreateCheck(statusBox or textGroup, "MSUF_StatusCombatIconCB", "Combat", 12, STATUS_BASE_TOGGLE_Y + (0 * STATUS_ROW_STEP))
		panel.statusRestingIconCB = panel.statusRestingIconCB or CreateCheck(statusBox or textGroup, "MSUF_StatusRestingIconCB", "Rested (player only)", 12, STATUS_BASE_TOGGLE_Y + (1 * STATUS_ROW_STEP))
		panel.statusIncomingResIconCB = panel.statusIncomingResIconCB or CreateCheck(statusBox or textGroup, "MSUF_StatusIncomingResIconCB", "Incoming Rez", 12, STATUS_BASE_TOGGLE_Y + (2 * STATUS_ROW_STEP))

		panel.statusIconsTestModeCB = panel.statusIconsTestModeCB or CreateCheck(statusBox or textGroup, "MSUF_StatusIconsTestModeCB", "Test mode", 12, STATUS_BASE_TOGGLE_Y + (3 * STATUS_ROW_STEP) + 10)

		panel.statusIconsStyleCB = panel.statusIconsStyleCB or CreateCheck(statusBox or textGroup, "MSUF_StatusIconsStyleCB", "Use Midnight style icons", 12, STATUS_BASE_TOGGLE_Y + (3 * STATUS_ROW_STEP) - 12)
		if panel.statusIconsStyleCB then panel.statusIconsStyleCB:Hide() end

		if panel.statusCombatIconCB then panel.statusCombatIconCB:Hide() end
		if panel.statusRestingIconCB then panel.statusRestingIconCB:Hide() end
		if panel.statusIncomingResIconCB then panel.statusIncomingResIconCB:Hide() end
		if panel.statusIconsTestModeCB then panel.statusIconsTestModeCB:Hide() end
		if panel.statusIconsStyleCB then panel.statusIconsStyleCB:Hide() end

-- Safety: older refactors called this; now it's not needed (layout is already relative).
		MSUF_PositionLeaderMiniHeaders = MSUF_PositionLeaderMiniHeaders or function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1744:69"); Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1744:69"); end

		local function _MSUF_GetCheckboxIcon(cb) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_GetCheckboxIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1746:8");
			if not cb then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_GetCheckboxIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1746:8"); return nil end
			return Perfy_Trace_Passthrough("Leave", "_MSUF_GetCheckboxIcon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1746:8", cb.Check or (cb.GetName and _G[cb:GetName() .. "Check"]) or nil)
		end

		local function _MSUF_CreateResetButton(field, cb, parentOverride) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_CreateResetButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1751:8");
			if panel[field] then
				panel[field]:Hide()
				panel[field]:ClearAllPoints()
			else
				panel[field] = CreateFrame("Button", nil, parentOverride or textGroup, "UIPanelButtonTemplate")
				panel[field]:SetSize(20, 20)
				panel[field]:SetText("R")

				local fs = panel[field].GetFontString and panel[field]:GetFontString()
				if fs then
					fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
					fs:ClearAllPoints()
					fs:SetPoint("CENTER", panel[field], "CENTER", 0, 0)
				end

				panel[field]:SetScript("OnEnter", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1767:38");
					if not GameTooltip then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1767:38"); return end
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText("Resets current indicator", 1, 1, 1)
					GameTooltip:AddLine("Resets X/Y, Anchor and Size back to defaults.", 0.85, 0.85, 0.85, true)
					GameTooltip:Show()
				Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1767:38"); end)
				panel[field]:SetScript("OnLeave", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1774:38");
					if GameTooltip then GameTooltip:Hide() end
				Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1774:38"); end)
			end

			local chk = _MSUF_GetCheckboxIcon(cb)
			if chk then
				panel[field]:SetPoint("TOP", chk, "BOTTOM", 0, -2)
			elseif cb then
				panel[field]:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 2, 2)
			else
				panel[field]:SetPoint("TOPLEFT", textGroup, "TOPLEFT", 12, IND_BASE_CTRL_Y + 2)
			end

			panel[field]:Hide()
			return Perfy_Trace_Passthrough("Leave", "_MSUF_CreateResetButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1751:8", panel[field])
		end

		local function _MSUF_MakeDivider(field, parentOverride) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_MakeDivider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1792:8");
			if panel[field] then
				panel[field]:Hide()
				return Perfy_Trace_Passthrough("Leave", "_MSUF_MakeDivider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1792:8", panel[field])
			end
			local tex = (parentOverride or textGroup):CreateTexture(nil, "ARTWORK")
			tex:SetHeight(1)
			tex:SetColorTexture(1, 1, 1, 0.08)
			tex:Hide()
			panel[field] = tex
			Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_MakeDivider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1792:8"); return tex
		end

		local function _MSUF_MakeDrop(field, globalName, width, parentOverride) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_MakeDrop file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1805:8");
			if panel[field] then
				panel[field]:Hide()
				return Perfy_Trace_Passthrough("Leave", "_MSUF_MakeDrop file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1805:8", panel[field])
			end
			local dd = CreateFrame("Frame", globalName, parentOverride or textGroup, "UIDropDownMenuTemplate")
			if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(dd, width) end
			dd._msufDropWidth = width
			if MSUF_ExpandDropdownClickArea then MSUF_ExpandDropdownClickArea(dd) end
			dd:SetScale(0.80)
			dd:Hide()
			panel[field] = dd
			Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_MakeDrop file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1805:8"); return dd
		end

		local function _MSUF_MakeLabel(field, text, parentOverride) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_MakeLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1820:8");
			if panel[field] then
				panel[field]:SetText(text)
				panel[field]:Hide()
				return Perfy_Trace_Passthrough("Leave", "_MSUF_MakeLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1820:8", panel[field])
			end
			local fs = (parentOverride or textGroup):CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			fs:SetText(text)
			fs:Hide()
			panel[field] = fs
			Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_MakeLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1820:8"); return fs
		end

		local function _MSUF_MakeSizeEdit(field, globalName, parentOverride) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_MakeSizeEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1833:8");
			if panel[field] then
				panel[field]:Hide()
				return Perfy_Trace_Passthrough("Leave", "_MSUF_MakeSizeEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1833:8", panel[field])
			end
			local eb = CreateFrame("EditBox", globalName, parentOverride or textGroup, "InputBoxTemplate")
			eb:SetAutoFocus(false)
			eb:SetSize(46, 18)
			eb:SetNumeric(true)
			eb:SetMaxLetters(3)
			local font = eb.GetFont and eb:GetFont()
			if font then
				eb:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
			else
				eb:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
			end
			eb:Hide()
			panel[field] = eb
			Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_MakeSizeEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1833:8"); return eb
		end

		local function _MSUF_LayoutIndicatorRow(cb, stepperX, stepperY, anchorDrop, anchorLabel, sizeEdit, sizeLabel, iconDrop, iconLabel, colX, ctrlY) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_LayoutIndicatorRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1854:8");
			-- X stepper is anchored to container; everything else is relative to it
			if stepperX then
				stepperX:ClearAllPoints()
				local anchorParent = (stepperX and stepperX.GetParent and stepperX:GetParent()) or textGroup
					stepperX:SetPoint("TOPLEFT", anchorParent, "TOPLEFT", colX, ctrlY)
				ResizeStepper(stepperX, 46, 1)
				RestyleStepperButtonsNoBox(stepperX)
				if MSUF_ApplyModifierStepper then MSUF_ApplyModifierStepper(stepperX, 1) end
				if stepperX.label then
					stepperX.label:Show()
					stepperX.label:ClearAllPoints()
					stepperX.label:SetPoint("BOTTOM", stepperX, "TOP", 0, 6)
				end
				stepperX:Hide()
			end

			if stepperY and stepperX then
				stepperY:ClearAllPoints()
				stepperY:SetPoint("LEFT", stepperX, "RIGHT", 6, 0)
				ResizeStepper(stepperY, 46, 1)
				RestyleStepperButtonsNoBox(stepperY)
				if MSUF_ApplyModifierStepper then MSUF_ApplyModifierStepper(stepperY, 1) end
				if stepperY.label then
					stepperY.label:Show()
					stepperY.label:ClearAllPoints()
					stepperY.label:SetPoint("BOTTOM", stepperY, "TOP", 0, 6)
				end
				stepperY:Hide()
			end

			if anchorDrop and stepperY then
				anchorDrop:ClearAllPoints()
				anchorDrop:SetPoint("LEFT", stepperY, "RIGHT", 1, 0)
				if anchorLabel then
					anchorLabel:ClearAllPoints()
					anchorLabel:SetPoint("BOTTOM", anchorDrop, "TOP", 0, 6)
					anchorLabel:Hide()
				end
				anchorDrop:Hide()
			end

			if sizeEdit and anchorDrop then
				sizeEdit:ClearAllPoints()
				sizeEdit:SetPoint("LEFT", anchorDrop, "RIGHT", 1, 2)
				if sizeLabel then
					sizeLabel:ClearAllPoints()
					sizeLabel:SetPoint("BOTTOM", sizeEdit, "TOP", 0, 6)
					sizeLabel:Hide()
				end
				sizeEdit:Hide()
			end

			if iconDrop and sizeEdit then
				iconDrop:ClearAllPoints()
				iconDrop:SetPoint("LEFT", sizeEdit, "RIGHT", 1, -2)
				if iconLabel then
					iconLabel:ClearAllPoints()
					iconLabel:SetPoint("BOTTOM", iconDrop, "TOP", 0, 6)
					iconLabel:Hide()
				end
				iconDrop:Hide()
			end


			if cb then cb:Hide() end
		Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_LayoutIndicatorRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1854:8"); end

		
		---------------------------------------------------------------------
		-- Indicator rows (Leader / Raid Marker / Level) — spec-driven
		---------------------------------------------------------------------
		local function _MSUF_BuildIndicatorRow(spec, idx) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_BuildIndicatorRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1926:8");
			if not spec then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BuildIndicatorRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1926:8"); return end
			local ui = spec.ui or {}

			-- Divider texture (positioned in LayoutIndicatorTemplate)
			if spec.divider then
				_MSUF_MakeDivider(spec.divider)
			end

			-- Toggle
			if spec.showCB and not panel[spec.showCB] then
				local fallbackName = "MSUF_" .. (spec.showCB:gsub("^%l", string.upper))
				panel[spec.showCB] = CreateCheck(textGroup, ui.cbName or fallbackName, ui.cbText or "Enable", 12,
					(IND_BASE_TOGGLE_Y + ((idx - 1) * IND_ROW_STEP)))
			end
			if spec.showCB and panel[spec.showCB] then
				panel[spec.showCB]:Hide()
			end

			-- Reset button
			if spec.resetBtn and spec.showCB then
				_MSUF_CreateResetButton(spec.resetBtn, panel[spec.showCB])
			end

			-- X/Y steppers
			if spec.xStepper and not panel[spec.xStepper] then
				panel[spec.xStepper] = CreateAxisStepper(ui.xName or ("MSUF_" .. spec.xStepper), "X", textGroup,
					spec.xDefault or 0, 0, -200, 200, 1)
			end
			if spec.yStepper and not panel[spec.yStepper] then
				panel[spec.yStepper] = CreateAxisStepper(ui.yName or ("MSUF_" .. spec.yStepper), "Y", textGroup,
					spec.yDefault or 0, 0, -200, 200, 1)
			end

			-- Anchor dropdown + label
			if spec.anchorDrop and spec.anchorLabel then
				panel[spec.anchorDrop]  = _MSUF_MakeDrop(spec.anchorDrop, ui.anchorName or ("MSUF_" .. spec.anchorDrop), ui.anchorW or 70)
				panel[spec.anchorLabel] = _MSUF_MakeLabel(spec.anchorLabel, "Anchor")
			end

			-- Size edit + label
			if spec.sizeEdit and spec.sizeLabel then
				panel[spec.sizeEdit]  = _MSUF_MakeSizeEdit(spec.sizeEdit, ui.sizeName or ("MSUF_" .. spec.sizeEdit))
				panel[spec.sizeLabel] = _MSUF_MakeLabel(spec.sizeLabel, "Size")
			end

			-- Relative layout: only X stepper is absolute, everything else follows.
			_MSUF_LayoutIndicatorRow(
				spec.showCB and panel[spec.showCB] or nil,
				spec.xStepper and panel[spec.xStepper] or nil,
				spec.yStepper and panel[spec.yStepper] or nil,
				spec.anchorDrop and panel[spec.anchorDrop] or nil,
				spec.anchorLabel and panel[spec.anchorLabel] or nil,
				spec.sizeEdit and panel[spec.sizeEdit] or nil,
				spec.sizeLabel and panel[spec.sizeLabel] or nil,
				nil,
				nil,
				IND_COL_X,
				IND_BASE_CTRL_Y + ((idx - 1) * IND_ROW_STEP)
			)
		Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BuildIndicatorRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1926:8"); end

		for idx, id in ipairs({ "leader", "raidmarker", "level" }) do
			_MSUF_BuildIndicatorRow(_MSUF_INDICATOR_SPECS and _MSUF_INDICATOR_SPECS[id], idx)
		end


		---------------------------------------------------------------------
		-- Status Icons rows (Combat / Rested / Incoming Rez) — spec-driven
		---------------------------------------------------------------------
		local STATUS_ROW_SPECS = {
			{
				rowIndex = 0,
				parent = panel._msufStatusIconsGroup,
				cbField = "statusCombatIconCB",
				cbName  = "MSUF_StatusCombatIconCB",
				cbText  = "Combat",
				divider = "statusCombatGroupDivider",
				resetBtn = "statusCombatResetBtn",
				xField = "statusCombatOffsetXStepper", xName = "MSUF_StatusCombatOffsetX",
				yField = "statusCombatOffsetYStepper", yName = "MSUF_StatusCombatOffsetY",
				anchorDrop = "statusCombatAnchorDrop", anchorName = "MSUF_StatusCombatAnchorDropdown", anchorLabel = "statusCombatAnchorLabel",
				sizeEdit = "statusCombatSizeEdit", sizeName = "MSUF_StatusCombatSizeEdit", sizeLabel = "statusCombatSizeLabel",
				iconDrop = "statusCombatSymbolDrop", iconName = "MSUF_StatusCombatSymbolDropdown", iconW = 92, iconLabel = "statusCombatSymbolLabel",
			},
			{
				rowIndex = 1,
				parent = panel._msufStatusIconsGroup,
				cbField = "statusRestingIconCB",
				cbName  = "MSUF_StatusRestingIconCB",
				cbText  = "Rested (player only)",
				divider = "statusRestingGroupDivider",
				resetBtn = "statusRestingResetBtn",
				xField = "statusRestingOffsetXStepper", xName = "MSUF_StatusRestingOffsetX",
				yField = "statusRestingOffsetYStepper", yName = "MSUF_StatusRestingOffsetY",
				anchorDrop = "statusRestingAnchorDrop", anchorName = "MSUF_StatusRestingAnchorDropdown", anchorLabel = "statusRestingAnchorLabel",
				sizeEdit = "statusRestingSizeEdit", sizeName = "MSUF_StatusRestingSizeEdit", sizeLabel = "statusRestingSizeLabel",
				iconDrop = "statusRestingSymbolDrop", iconName = "MSUF_StatusRestingSymbolDropdown", iconW = 92, iconLabel = "statusRestingSymbolLabel",
			},
			{
				rowIndex = 2,
				parent = panel._msufStatusIconsGroup,
				cbField = "statusIncomingResIconCB",
				cbName  = "MSUF_StatusIncomingResIconCB",
				cbText  = "Incoming Rez",
				divider = "statusIncomingResGroupDivider",
				resetBtn = "statusIncomingResResetBtn",
				xField = "statusIncomingResOffsetXStepper", xName = "MSUF_StatusIncomingResOffsetX",
				yField = "statusIncomingResOffsetYStepper", yName = "MSUF_StatusIncomingResOffsetY",
				anchorDrop = "statusIncomingResAnchorDrop", anchorName = "MSUF_StatusIncomingResAnchorDropdown", anchorLabel = "statusIncomingResAnchorLabel",
				sizeEdit = "statusIncomingResSizeEdit", sizeName = "MSUF_StatusIncomingResSizeEdit", sizeLabel = "statusIncomingResSizeLabel",
				iconDrop = "statusIncomingResSymbolDrop", iconName = "MSUF_StatusIncomingResSymbolDropdown", iconW = 92, iconLabel = "statusIncomingResSymbolLabel",
			},
		}

		local function _MSUF_BuildStatusRow(s) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_BuildStatusRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2041:8");
			local parent = s.parent or textGroup

			if s.divider then
				_MSUF_MakeDivider(s.divider, parent)
			end

			-- Toggle (usually already created above)
			if not panel[s.cbField] then
				panel[s.cbField] = CreateCheck(parent, s.cbName, s.cbText, 12, STATUS_BASE_TOGGLE_Y + (s.rowIndex * STATUS_ROW_STEP))
			end
			if panel[s.cbField] then panel[s.cbField]:Hide() end

			-- Reset button
			_MSUF_CreateResetButton(s.resetBtn, panel[s.cbField], parent)

			-- X/Y steppers
			if not panel[s.xField] then
				panel[s.xField] = CreateAxisStepper(s.xName, "X", parent, 0, 0, -200, 200, 1)
			end
			if not panel[s.yField] then
				panel[s.yField] = CreateAxisStepper(s.yName, "Y", parent, 0, 0, -200, 200, 1)
			end

			-- Anchor dropdown + label
			panel[s.anchorDrop]  = panel[s.anchorDrop]  or _MSUF_MakeDrop(s.anchorDrop, s.anchorName, 70, parent)
			panel[s.anchorLabel] = panel[s.anchorLabel] or _MSUF_MakeLabel(s.anchorLabel, "Anchor", parent)

			-- Size edit + label
			panel[s.sizeEdit]  = panel[s.sizeEdit]  or _MSUF_MakeSizeEdit(s.sizeEdit, s.sizeName, parent)
			panel[s.sizeLabel] = panel[s.sizeLabel] or _MSUF_MakeLabel(s.sizeLabel, "Size", parent)

			-- Icon dropdown + label
			panel[s.iconDrop]  = panel[s.iconDrop]  or _MSUF_MakeDrop(s.iconDrop, s.iconName, s.iconW or 92, parent)
			panel[s.iconLabel] = panel[s.iconLabel] or _MSUF_MakeLabel(s.iconLabel, "Icon", parent)

			-- Relative layout: only X stepper is absolute, everything else follows.
			_MSUF_LayoutIndicatorRow(
				panel[s.cbField],
				panel[s.xField],
				panel[s.yField],
				panel[s.anchorDrop],
				panel[s.anchorLabel],
				panel[s.sizeEdit],
				panel[s.sizeLabel],
				panel[s.iconDrop],
				panel[s.iconLabel],
				IND_COL_X,
				STATUS_BASE_CTRL_Y + (s.rowIndex * STATUS_ROW_STEP)
			)
		Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BuildStatusRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2041:8"); end

		for i = 1, #STATUS_ROW_SPECS do
			_MSUF_BuildStatusRow(STATUS_ROW_SPECS[i])
		end

		local function _MSUF_BuildCopyUI(spec) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_BuildCopyUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2097:8");
        local prefix    = spec.prefix
        local destVar   = spec.destVar
        local default   = spec.defaultDest
        local items     = spec.items or {}
        local hintText  = spec.hintText or "Copies compatible settings."
        local dropName  = spec.dropName

        local labelKey  = prefix .. "CopyToLabel"
        local dropKey   = prefix .. "CopyToDrop"
        local btnKey    = prefix .. "CopyToButton"
        local hintKey   = prefix .. "CopyToHint"

        if not panel[labelKey] then
            panel[labelKey] = (parentOverride or textGroup):CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            panel[labelKey]:SetText("Copy to")
            panel[labelKey]:Hide()
        end

        if not panel[dropKey] then
            panel[dropKey] = CreateFrame("Frame", dropName, textGroup, "UIDropDownMenuTemplate")
            if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(panel[dropKey], 150) end
            panel[dropKey]._msufDropWidth = 150
            if MSUF_ExpandDropdownClickArea then MSUF_ExpandDropdownClickArea(panel[dropKey]) end
            panel[dropKey]:SetScale(0.86)
            panel[dropKey]:Hide()

            panel[destVar] = panel[destVar] or default

            local function Init(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "Init file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2126:18");
                if not level then Perfy_Trace(Perfy_GetTime(), "Leave", "Init file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2126:18"); return end

                local function AddItem(text, value) Perfy_Trace(Perfy_GetTime(), "Enter", "AddItem file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2129:22");
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = text
                    info.value = value
                    info.func = function(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2133:32");
                        local v = (btn and btn.value) or value or default
                        panel[destVar] = v
                        self.selectedValue = v
                        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(self, v) end
                        local label = (_G._MSUF_CopyDestLabel and _G._MSUF_CopyDestLabel(v)) or tostring(v)
                        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(self, label) end
                        if CloseDropDownMenus then CloseDropDownMenus() end
                    Perfy_Trace(Perfy_GetTime(), "Leave", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2133:32"); end
                    info.checked = function() Perfy_Trace(Perfy_GetTime(), "Enter", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2142:35");
                        return Perfy_Trace_Passthrough("Leave", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2142:35", (panel[destVar] == value))
                    end
                    UIDropDownMenu_AddButton(info, level)
                Perfy_Trace(Perfy_GetTime(), "Leave", "AddItem file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2129:22"); end

                for i = 1, #items do
                    local it = items[i]
                    AddItem(it[1], it[2])
                end

                local sep = UIDropDownMenu_CreateInfo()
                sep.text = " "
                sep.isTitle = true
                sep.notCheckable = true
                UIDropDownMenu_AddButton(sep, level)
                AddItem("All", "all")
            Perfy_Trace(Perfy_GetTime(), "Leave", "Init file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2126:18"); end

            UIDropDownMenu_Initialize(panel[dropKey], Init)

            if not panel[dropKey]._msufCopySyncHooked and panel[dropKey].HookScript then
                panel[dropKey]._msufCopySyncHooked = true
                panel[dropKey]:HookScript("OnShow", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2165:52");
                    local k = panel[destVar] or default
                    if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(self, k) end
                    local label = (_G._MSUF_CopyDestLabel and _G._MSUF_CopyDestLabel(k)) or tostring(k)
                    if UIDropDownMenu_SetText then UIDropDownMenu_SetText(self, label) end
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2165:52"); end)
            end
        end

        if not panel[btnKey] then
            panel[btnKey] = CreateFrame("Button", nil, parentOverride or textGroup, "UIPanelButtonTemplate")
            panel[btnKey]:SetSize(64, 20)
            panel[btnKey]:SetText("Copy")
            panel[btnKey]:Hide()
        end

        if not panel[hintKey] then
            panel[hintKey] = textGroup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            panel[hintKey]:SetText(hintText)
            panel[hintKey]:Hide()
        end

        -- Single, stable anchor for all copy UIs (above the Edit Mode button, avoids indicator overlap)
        panel[dropKey]:ClearAllPoints()
        panel[dropKey]:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 52, 96)

        panel[labelKey]:ClearAllPoints()
        panel[labelKey]:SetPoint("LEFT", panel[dropKey], "LEFT", -40, 2)

        panel[btnKey]:ClearAllPoints()
        panel[btnKey]:SetPoint("LEFT", panel[dropKey], "RIGHT", -14, 2)

        panel[hintKey]:ClearAllPoints()
        panel[hintKey]:SetPoint("TOPLEFT", panel[dropKey], "BOTTOMLEFT", -32, -2)
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BuildCopyUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2097:8"); end

    local _MSUF_COPY_UI_SPECS = {
        {
            prefix = "player",
            dropName = "MSUF_PlayerCopyToDropdown",
            destVar = "_msufCopyDestKey",
            defaultDest = "target",
            hintText = "",
            items = {
                { "Target", "target" },
                { "Focus", "focus" },
                { "Boss frames", "boss" },
                { "Pet", "pet" },
                { "Target of Target", "targettarget" },
            },
        },
        {
            prefix = "target",
            dropName = "MSUF_TargetCopyToDropdown",
            destVar = "_msufCopyDestKey_target",
            defaultDest = "player",
            hintText = "",
            items = {
                { "Player", "player" },
                { "Focus", "focus" },
                { "Boss frames", "boss" },
                { "Pet", "pet" },
                { "Target of Target", "targettarget" },
            },
        },
        {
            prefix = "focus",
            dropName = "MSUF_FocusCopyToDropdown",
            destVar = "_msufCopyDestKey_focus",
            defaultDest = "target",
            hintText = "",
            items = {
                { "Player", "player" },
                { "Target", "target" },
                { "Boss frames", "boss" },
                { "Pet", "pet" },
                { "Target of Target", "targettarget" },
            },
        },
        {
            prefix = "boss",
            dropName = "MSUF_BossCopyToDropdown",
            destVar = "_msufCopyDestKey_boss",
            defaultDest = "target",
            hintText = "",
            items = {
                { "Player", "player" },
                { "Target", "target" },
                { "Focus", "focus" },
                { "Pet", "pet" },
                { "Target of Target", "targettarget" },
            },
        },
        {
            prefix = "tot",
            dropName = "MSUF_ToTCopyToDropdown",
            destVar = "_msufCopyDestKey_tot",
            defaultDest = "player",
            hintText = "",
            items = {
                { "Player", "player" },
                { "Target", "target" },
                { "Focus", "focus" },
                { "Boss frames", "boss" },
                { "Pet", "pet" },
            },
        },
        {
            prefix = "pet",
            dropName = "MSUF_PetCopyToDropdown",
            destVar = "_msufCopyDestKey_pet",
            defaultDest = "target",
            hintText = "",
            items = {
                { "Player", "player" },
                { "Target", "target" },
                { "Target of Target", "targettarget" },
                { "Focus", "focus" },
                { "Boss frames", "boss" },
            },
        },
    }

    for i = 1, #_MSUF_COPY_UI_SPECS do
        _MSUF_BuildCopyUI(_MSUF_COPY_UI_SPECS[i])
    end

    if false and not panel.petEditModeButton then
        panel.petEditModeButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        panel.petEditModeButton:SetSize(220, 28)
        panel.petEditModeButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 20)
        panel.petEditModeButton:SetText("Edit Mode")
        panel.petEditModeButton:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2297:53");
            local fn = _G and _G.MSUF_SetMSUFEditModeDirect
            if type(fn) == "function" then
                local active = _G.MSUF_UnitEditModeActive and true or false
                local cur = _G.MSUF_CurrentEditUnitKey
                if active and cur == "pet" then
                    fn(false)
                else
                    fn(true, "pet")
                end
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2297:53"); end)
        panel.petEditModeButton:Hide()
    end

    Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_Options_Player_Build file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:1225:0"); end


-- APPLY FROM DB (called from Options Core)


-- Reuse the Player indicator block layout as a template for other unitframe pages.
-- Leader/Assist is only shown on Player + Target; Raid Marker + Level are available for all.
function ns.MSUF_Options_Player_LayoutIndicatorTemplate(panel, currentKey) Perfy_Trace(Perfy_GetTime(), "Enter", "ns.MSUF_Options_Player_LayoutIndicatorTemplate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2320:0");
    if not panel or not panel._msufIndicatorLayout then Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_Options_Player_LayoutIndicatorTemplate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2320:0"); return end

    local l = panel._msufIndicatorLayout
    local container = panel._msufTextGroup or panel.playerTextLayoutGroup or panel
    if not container then Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_Options_Player_LayoutIndicatorTemplate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2320:0"); return end

    local isFramesTab = true
    if type(panel._msufIsFramesTab) == "function" then
        isFramesTab = panel._msufIsFramesTab()
    end

    local function SetShownByName(name, show) Perfy_Trace(Perfy_GetTime(), "Enter", "SetShownByName file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2332:10");
        if not name then Perfy_Trace(Perfy_GetTime(), "Leave", "SetShownByName file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2332:10"); return end
        local w = panel[name]
        if w then w:SetShown(show) end
    Perfy_Trace(Perfy_GetTime(), "Leave", "SetShownByName file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2332:10"); end

    -- If we're not on the Frames tab, hard-hide the whole indicator template to avoid stray UI.
    if not isFramesTab then
        if panel._msufStatusIconsGroup then panel._msufStatusIconsGroup:Hide() end
        if panel.playerLeaderIndicatorHeader then panel.playerLeaderIndicatorHeader:Hide() end
        for _, spec in pairs(_MSUF_INDICATOR_SPECS) do
            SetShownByName(spec.showCB, false)
            SetShownByName(spec.xStepper, false)
            SetShownByName(spec.yStepper, false)
            SetShownByName(spec.anchorDrop, false)
            SetShownByName(spec.anchorLabel, false)
            SetShownByName(spec.sizeEdit, false)
            SetShownByName(spec.sizeLabel, false)
            SetShownByName(spec.divider, false)
            SetShownByName(spec.resetBtn, false)
        end
        if panel.playerBossSpacingSlider then panel.playerBossSpacingSlider:Hide() end
        -- Status icons (and Step-1 Combat row controls) must also be hard-hidden outside Frames tab
        if panel.statusIconsHeader then panel.statusIconsHeader:Hide() end
        if panel.statusCombatIconCB then panel.statusCombatIconCB:Hide() end
        if panel.statusRestingIconCB then panel.statusRestingIconCB:Hide() end
        if panel.statusIncomingResIconCB then panel.statusIncomingResIconCB:Hide() end
        if panel.statusIconsTestModeCB then panel.statusIconsTestModeCB:Hide() end
        if panel.statusIconsStyleCB then panel.statusIconsStyleCB:Hide() end
        SetShownByName("statusCombatGroupDivider", false)
        SetShownByName("statusCombatResetBtn", false)
        SetShownByName("statusCombatOffsetXStepper", false)
        SetShownByName("statusCombatOffsetYStepper", false)
        SetShownByName("statusCombatAnchorDrop", false)
        SetShownByName("statusCombatAnchorLabel", false)
        SetShownByName("statusCombatSizeEdit", false)
        SetShownByName("statusCombatSizeLabel", false)
        -- Step 2: Rested row controls must also be hard-hidden outside Frames tab
        SetShownByName("statusRestingGroupDivider", false)
        SetShownByName("statusRestingResetBtn", false)
        SetShownByName("statusRestingOffsetXStepper", false)
        SetShownByName("statusRestingOffsetYStepper", false)
        SetShownByName("statusRestingAnchorDrop", false)
        SetShownByName("statusRestingAnchorLabel", false)
        SetShownByName("statusRestingSizeEdit", false)
        SetShownByName("statusRestingSizeLabel", false)
        Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_Options_Player_LayoutIndicatorTemplate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2320:0"); return
    end

    -- Header: keep it present for all frames pages.
    if panel.playerLeaderIndicatorHeader then
        panel.playerLeaderIndicatorHeader:Show()
        panel.playerLeaderIndicatorHeader:SetJustifyH("LEFT")
    end

    local baseToggleY = l.leaderToggleY or -163
    local baseCtrlY   = l.leaderCtrlY   or -178
    local step        = l.rowStep       or -64
    local dividerOffset = l.dividerOffset or 23

    -- Pet tab has no Castbar section in this panel; move Indicator up to occupy that space.
    -- This aligns the first indicator row roughly where other tabs place the Castbar controls.
    if currentKey == "pet" then
        baseToggleY = -34
        baseCtrlY   = -49
    end


    local function PlaceToggle(cb, y) Perfy_Trace(Perfy_GetTime(), "Enter", "PlaceToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2400:10");
        if not cb then Perfy_Trace(Perfy_GetTime(), "Leave", "PlaceToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2400:10"); return end
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", container, "TOPLEFT", 12, y)
    Perfy_Trace(Perfy_GetTime(), "Leave", "PlaceToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2400:10"); end

    local function PlaceXStepper(stepper, y) Perfy_Trace(Perfy_GetTime(), "Enter", "PlaceXStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2406:10");
        if not stepper then Perfy_Trace(Perfy_GetTime(), "Leave", "PlaceXStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2406:10"); return end
        stepper:ClearAllPoints()
        stepper:SetPoint("TOPLEFT", container, "TOPLEFT", l.colX or 175, y)
    Perfy_Trace(Perfy_GetTime(), "Leave", "PlaceXStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2406:10"); end

    local function PlaceDivider(tex, toggleY) Perfy_Trace(Perfy_GetTime(), "Enter", "PlaceDivider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2412:10");
        if not tex then Perfy_Trace(Perfy_GetTime(), "Leave", "PlaceDivider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2412:10"); return end
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", container, "TOPLEFT", 15, toggleY + dividerOffset)
        tex:SetPoint("TOPRIGHT", container, "TOPRIGHT", -15, toggleY + dividerOffset)
    Perfy_Trace(Perfy_GetTime(), "Leave", "PlaceDivider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2412:10"); end

    local row = 0
    local firstDivider = nil

    for _, id in ipairs({ "leader", "raidmarker", "level" }) do
        local spec = _MSUF_INDICATOR_SPECS[id]
        if spec then
            local show = (spec.allowed and spec.allowed(currentKey)) and true or false

            SetShownByName(spec.showCB, show)
            SetShownByName(spec.xStepper, show)
            SetShownByName(spec.yStepper, show)
            SetShownByName(spec.anchorDrop, show)
            SetShownByName(spec.anchorLabel, show)
            SetShownByName(spec.sizeEdit, show)
            SetShownByName(spec.sizeLabel, show)
            SetShownByName(spec.divider, show)
            SetShownByName(spec.resetBtn, show)

            if show then
                local toggleY = baseToggleY + (row * step)
                local ctrlY   = baseCtrlY + (row * step)

                PlaceToggle(panel[spec.showCB], toggleY)
                PlaceXStepper(panel[spec.xStepper], ctrlY)
                PlaceDivider(panel[spec.divider], toggleY)

                if not firstDivider and spec.divider and panel[spec.divider] then
                    firstDivider = panel[spec.divider]
                end

                row = row + 1
            end
        end
    end

    if panel.playerLeaderIndicatorHeader and firstDivider then
        panel.playerLeaderIndicatorHeader:ClearAllPoints()
        panel.playerLeaderIndicatorHeader:SetPoint("LEFT", firstDivider, "LEFT", 0, 0)
    end



    -- Status icons live in their own box (player/target only).
    local statusBox = panel._msufStatusIconsGroup
    local showStatusIcons = (currentKey == "player" or currentKey == "target") and true or false
    if statusBox then
        statusBox:SetShown(showStatusIcons)
    end

    -- Hard-hide all status icon widgets when not needed (prevents stray UI).
    if not showStatusIcons then
        if panel.statusIconsHeader then panel.statusIconsHeader:Hide() end
        if panel.statusCombatIconCB then panel.statusCombatIconCB:Hide() end
        if panel.statusRestingIconCB then panel.statusRestingIconCB:Hide() end
        if panel.statusIncomingResIconCB then panel.statusIncomingResIconCB:Hide() end
        if panel.statusIconsTestModeCB then panel.statusIconsTestModeCB:Hide() end
        if panel.statusIconsStyleCB then panel.statusIconsStyleCB:Hide() end
        SetShownByName("statusCombatGroupDivider", false)
        SetShownByName("statusCombatResetBtn", false)
        SetShownByName("statusCombatOffsetXStepper", false)
        SetShownByName("statusCombatOffsetYStepper", false)
        SetShownByName("statusCombatAnchorDrop", false)
        SetShownByName("statusCombatAnchorLabel", false)
        SetShownByName("statusCombatSizeEdit", false)
        SetShownByName("statusCombatSizeLabel", false)
        SetShownByName("statusCombatSymbolDrop", false)
        SetShownByName("statusCombatSymbolLabel", false)

        SetShownByName("statusRestingGroupDivider", false)
        SetShownByName("statusRestingResetBtn", false)
        SetShownByName("statusRestingOffsetXStepper", false)
        SetShownByName("statusRestingOffsetYStepper", false)
        SetShownByName("statusRestingAnchorDrop", false)
        SetShownByName("statusRestingAnchorLabel", false)
        SetShownByName("statusRestingSizeEdit", false)
        SetShownByName("statusRestingSizeLabel", false)
        SetShownByName("statusRestingSymbolDrop", false)
        SetShownByName("statusRestingSymbolLabel", false)

        SetShownByName("statusIncomingResGroupDivider", false)
        SetShownByName("statusIncomingResResetBtn", false)
        SetShownByName("statusIncomingResOffsetXStepper", false)
        SetShownByName("statusIncomingResOffsetYStepper", false)
        SetShownByName("statusIncomingResAnchorDrop", false)
        SetShownByName("statusIncomingResAnchorLabel", false)
        SetShownByName("statusIncomingResSizeEdit", false)
        SetShownByName("statusIncomingResSizeLabel", false)
        SetShownByName("statusIncomingResSymbolDrop", false)
        SetShownByName("statusIncomingResSymbolLabel", false)
    else
        -- Within Status box: fixed layout (independent from Indicator rows)
        local baseToggleY = -34
        local baseCtrlY   = -49
        local step        = -64
        local dividerOffset = l.dividerOffset or 23

        local function PlaceToggleIn(box, cb, y) Perfy_Trace(Perfy_GetTime(), "Enter", "PlaceToggleIn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2515:14");
            if not cb then Perfy_Trace(Perfy_GetTime(), "Leave", "PlaceToggleIn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2515:14"); return end
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", box, "TOPLEFT", 12, y)
        Perfy_Trace(Perfy_GetTime(), "Leave", "PlaceToggleIn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2515:14"); end

        local function PlaceXStepperIn(box, stepper, y) Perfy_Trace(Perfy_GetTime(), "Enter", "PlaceXStepperIn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2521:14");
            if not stepper then Perfy_Trace(Perfy_GetTime(), "Leave", "PlaceXStepperIn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2521:14"); return end
            stepper:ClearAllPoints()
            stepper:SetPoint("TOPLEFT", box, "TOPLEFT", l.colX or 175, y)
        Perfy_Trace(Perfy_GetTime(), "Leave", "PlaceXStepperIn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2521:14"); end

        local function PlaceDividerIn(box, tex, toggleY) Perfy_Trace(Perfy_GetTime(), "Enter", "PlaceDividerIn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2527:14");
            if not tex then Perfy_Trace(Perfy_GetTime(), "Leave", "PlaceDividerIn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2527:14"); return end
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", box, "TOPLEFT", 15, toggleY + dividerOffset)
            tex:SetPoint("TOPRIGHT", box, "TOPRIGHT", -15, toggleY + dividerOffset)
        Perfy_Trace(Perfy_GetTime(), "Leave", "PlaceDividerIn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2527:14"); end

        if panel.statusIconsHeader then
            panel.statusIconsHeader:Hide() -- box title already says "Status icons"
        end

        -- Combat row
        if panel.statusCombatIconCB then panel.statusCombatIconCB:Show() end
        SetShownByName("statusCombatGroupDivider", true)
        SetShownByName("statusCombatResetBtn", true)
        SetShownByName("statusCombatOffsetXStepper", true)
        SetShownByName("statusCombatOffsetYStepper", true)
        SetShownByName("statusCombatAnchorDrop", true)
        SetShownByName("statusCombatAnchorLabel", true)
        SetShownByName("statusCombatSizeEdit", true)
        SetShownByName("statusCombatSizeLabel", true)
        SetShownByName("statusCombatSymbolDrop", true)
        SetShownByName("statusCombatSymbolLabel", true)

        PlaceToggleIn(statusBox, panel.statusCombatIconCB, baseToggleY + (0 * step))
        PlaceXStepperIn(statusBox, panel.statusCombatOffsetXStepper, baseCtrlY + (0 * step))
        PlaceDividerIn(statusBox, panel.statusCombatGroupDivider, baseToggleY + (0 * step))

        -- Rested row (player only)
        local showResting = (currentKey == "player") and true or false
        if panel.statusRestingIconCB then panel.statusRestingIconCB:SetShown(showResting) end
        SetShownByName("statusRestingGroupDivider", showResting)
        SetShownByName("statusRestingResetBtn", showResting)
        SetShownByName("statusRestingOffsetXStepper", showResting)
        SetShownByName("statusRestingOffsetYStepper", showResting)
        SetShownByName("statusRestingAnchorDrop", showResting)
        SetShownByName("statusRestingAnchorLabel", showResting)
        SetShownByName("statusRestingSizeEdit", showResting)
        SetShownByName("statusRestingSizeLabel", showResting)
        SetShownByName("statusRestingSymbolDrop", showResting)
        SetShownByName("statusRestingSymbolLabel", showResting)

        if showResting then
            PlaceToggleIn(statusBox, panel.statusRestingIconCB, baseToggleY + (1 * step))
            PlaceXStepperIn(statusBox, panel.statusRestingOffsetXStepper, baseCtrlY + (1 * step))
            PlaceDividerIn(statusBox, panel.statusRestingGroupDivider, baseToggleY + (1 * step))
        end

        -- Incoming Rez row
        if panel.statusIncomingResIconCB then panel.statusIncomingResIconCB:Show() end
        SetShownByName("statusIncomingResGroupDivider", true)
        SetShownByName("statusIncomingResResetBtn", true)
        SetShownByName("statusIncomingResOffsetXStepper", true)
        SetShownByName("statusIncomingResOffsetYStepper", true)
        SetShownByName("statusIncomingResAnchorDrop", true)
        SetShownByName("statusIncomingResAnchorLabel", true)
        SetShownByName("statusIncomingResSizeEdit", true)
        SetShownByName("statusIncomingResSizeLabel", true)
        SetShownByName("statusIncomingResSymbolDrop", true)
        SetShownByName("statusIncomingResSymbolLabel", true)

        PlaceToggleIn(statusBox, panel.statusIncomingResIconCB, baseToggleY + (2 * step))
        PlaceXStepperIn(statusBox, panel.statusIncomingResOffsetXStepper, baseCtrlY + (2 * step))
        PlaceDividerIn(statusBox, panel.statusIncomingResGroupDivider, baseToggleY + (2 * step))

        -- Remaining status toggles (Test mode / Style)
        if panel.statusIconsTestModeCB then
            panel.statusIconsTestModeCB:Show()
            PlaceToggleIn(statusBox, panel.statusIconsTestModeCB, baseToggleY + (3 * step) + 10)
        end
        if panel.statusIconsStyleCB then
            panel.statusIconsStyleCB:Show()
            panel.statusIconsStyleCB:ClearAllPoints()
            panel.statusIconsStyleCB:SetPoint("TOPLEFT", statusBox, "TOPLEFT", 220, baseToggleY + (3 * step) + 10)
        end

        -- Icon pickers are currently layout-only storage (Step 4.6)
        local function HideIconPicker(label, drop) Perfy_Trace(Perfy_GetTime(), "Enter", "HideIconPicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2604:14");
            if label then label:Hide() end
            if drop  then drop:Hide() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "HideIconPicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2604:14"); end

        local function PlaceIconPickerAt(label, drop, titleText, rel, xOff) Perfy_Trace(Perfy_GetTime(), "Enter", "PlaceIconPickerAt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2609:14");
            if not (label and drop and rel) then Perfy_Trace(Perfy_GetTime(), "Leave", "PlaceIconPickerAt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2609:14"); return end
            label:SetText(titleText)
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 2 + (xOff or 0), -8)  -- moved up ~10px and slightly left
            label:Show()

            drop:ClearAllPoints()
            drop:SetPoint("TOPLEFT", label, "BOTTOMLEFT", -12, -4)
            drop:Show()
        Perfy_Trace(Perfy_GetTime(), "Leave", "PlaceIconPickerAt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2609:14"); end

        local baseRel = panel.statusIconsTestModeCB
        if baseRel then
            PlaceIconPickerAt(panel.statusCombatSymbolLabel, panel.statusCombatSymbolDrop, "Combat", baseRel, 0)
            PlaceIconPickerAt(panel.statusIncomingResSymbolLabel, panel.statusIncomingResSymbolDrop, "Rez", baseRel, 125)
            if showResting then
                PlaceIconPickerAt(panel.statusRestingSymbolLabel, panel.statusRestingSymbolDrop, "Rested", baseRel, 250)
            else
                HideIconPicker(panel.statusRestingSymbolLabel, panel.statusRestingSymbolDrop)
            end
        else
            HideIconPicker(panel.statusCombatSymbolLabel, panel.statusCombatSymbolDrop)
            HideIconPicker(panel.statusIncomingResSymbolLabel, panel.statusIncomingResSymbolDrop)
            HideIconPicker(panel.statusRestingSymbolLabel, panel.statusRestingSymbolDrop)
        end
    end

local isBossKey = false
    if type(currentKey) == "string" then
        if currentKey == "boss" or currentKey:match("^boss") then
            isBossKey = true
        end
    end

    if panel.playerBossSpacingSlider then
        local show = isBossKey and true or false
        panel.playerBossSpacingSlider:SetShown(show)
        if panel.playerBossSpacingSlider.editBox then panel.playerBossSpacingSlider.editBox:SetShown(show) end
        if panel.playerBossSpacingSlider.minusButton then panel.playerBossSpacingSlider.minusButton:SetShown(show) end
        if panel.playerBossSpacingSlider.plusButton then panel.playerBossSpacingSlider.plusButton:SetShown(show) end

        local n = panel.playerBossSpacingSlider.GetName and panel.playerBossSpacingSlider:GetName()
        if n then
            local low  = _G[n .. "Low"]
            local high = _G[n .. "High"]
            local text = _G[n .. "Text"]
            if low  then low:SetShown(show) end
            if high then high:SetShown(show) end
            if text then text:SetShown(show) end
        end

        if show then
            local ctrlY = baseCtrlY + (row * step)
            panel.playerBossSpacingSlider:ClearAllPoints()
            panel.playerBossSpacingSlider:SetPoint("TOPLEFT", container, "TOPLEFT", 12, ctrlY)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_Options_Player_LayoutIndicatorTemplate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2320:0"); end

function ns.MSUF_Options_Player_ApplyFromDB(panel, currentKey, conf, g, GetOffsetValue) Perfy_Trace(Perfy_GetTime(), "Enter", "ns.MSUF_Options_Player_ApplyFromDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2669:0");
    if not panel or not currentKey then Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_Options_Player_ApplyFromDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2669:0"); return end

    -- Be robust when the core passes nil conf/g (e.g. first time opening a unit tab).
    EnsureDB()
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}
    g = MSUF_DB.general

    local key = currentKey
    if key == "tot" or key == "targetoftarget" then key = "targettarget" end
    MSUF_DB[key] = MSUF_DB[key] or conf or {}
    conf = MSUF_DB[key]
    currentKey = key
    panel._msufLastApplyKey = currentKey

    -- If the core is still in player-only mode, it will only show this UI for player.
    -- We still keep ApplyFromDB working for any key (multi-unit core).

    -- Basics

    -- Unit Alpha: make the left box title reflect the selected unit (Player/Target/Focus/etc.).
    if panel.playerSizeBox and panel.playerSizeBox._msufTitleText then
        local k = currentKey
        if k == "tot" or k == "targetoftarget" then k = "targettarget" end
        local titleMap = {
            player = "Player Alpha",
            target = "Target Alpha",
            focus = "Focus Alpha",
            pet = "Pet Alpha",
            boss = "Boss Alpha",
            targettarget = "Target of Target Alpha",
        }
        panel.playerSizeBox._msufTitleText:SetText(titleMap[k] or "Unit Alpha")
    end
    for _, s in ipairs(MSUF_BASIC_CB_SPECS) do
        local w = panel[s.w]
        if w and w.SetChecked then
            w:SetChecked((s.eval and s.eval(conf)) and true or false)
        end
    end

    -- Player-only: Player castbar toggles (Frames tab -> Text box)
    local isPlayerKey = (currentKey == "player")
    local isTargetKey = (currentKey == "target")
    local isFocusKey  = (currentKey == "focus")
    local isBossKey   = (currentKey == "boss")
    local isToTKey    = (currentKey == "targettarget" or currentKey == "tot" or currentKey == "targetoftarget")
    local isPetKey    = (currentKey == "pet")
    local isFramesTab = (panel._msufIsFramesTab and panel._msufIsFramesTab()) or true

    -- ToT-only: inline ToT text in Target name line toggle lives in the right "Castbar" box.
    if panel.totShowInTargetCB then
        panel.totShowInTargetCB:SetShown(isToTKey and isFramesTab)
        if isToTKey and isFramesTab then
            panel.totShowInTargetCB:SetChecked(conf.showToTInTargetName == true)
        end
        -- Separator dropdown directly under the toggle.
        if panel.totInlineSeparatorDD then
            local show = (isToTKey and isFramesTab)
            panel.totInlineSeparatorDD:SetShown(show)
            if show then
                -- Keep anchoring stable even if other reflow/layout code touches the parent group.
                if panel.totShowInTargetCB then
                    panel.totInlineSeparatorDD:ClearAllPoints()
                    panel.totInlineSeparatorDD:SetPoint("TOPLEFT", panel.totShowInTargetCB, "BOTTOMLEFT", -18, -6)
                    if panel.totInlineSeparatorDD.SetFrameLevel and panel.totShowInTargetCB.GetFrameLevel then
                        panel.totInlineSeparatorDD:SetFrameLevel((panel.totShowInTargetCB:GetFrameLevel() or 0) + 2)
                    end
                end

                local token = MSUF_ReadString(conf, g, "totInlineSeparator", "|")
                token = MSUF_ToTInlineSepTokenText(token)
                if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(panel.totInlineSeparatorDD, token) end
                if UIDropDownMenu_SetText then UIDropDownMenu_SetText(panel.totInlineSeparatorDD, token) end

                -- Grey/disable when inline is off (safe UX, avoids accidental confusion).
                local enabled = (conf.showToTInTargetName == true)
                if UIDropDownMenu_EnableDropDown and UIDropDownMenu_DisableDropDown then
                    if enabled then UIDropDownMenu_EnableDropDown(panel.totInlineSeparatorDD) else UIDropDownMenu_DisableDropDown(panel.totInlineSeparatorDD) end
                elseif panel.totInlineSeparatorDD.Button then
                    if enabled and panel.totInlineSeparatorDD.Button.Enable then panel.totInlineSeparatorDD.Button:Enable() end
                    if (not enabled) and panel.totInlineSeparatorDD.Button.Disable then panel.totInlineSeparatorDD.Button:Disable() end
                end
            end
        end

    -- Title: Target of Target uses "Inline Text" (it is not a castbar).
    -- Pet uses this box for indicator settings, so we hide the "Castbar" title there.
    if panel.playerTextLayoutGroup and panel.playerTextLayoutGroup._msufTitleText then
        local t = panel.playerTextLayoutGroup._msufTitleText
        if isFramesTab and isPetKey then
            t:SetText("")
            t:Hide()
        elseif isToTKey and isFramesTab then
            t:SetText("Inline Text")
            t:Show()
        else
            t:SetText("Castbar")
            t:Show()
        end
    end

    end


    -- Copy-to UI visibility (refactored)
    local function _MSUF_SetCopyVisible(prefix, destVar, defaultDest, active) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_SetCopyVisible file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2776:10");
        local labelKey = prefix .. "CopyToLabel"
        local dropKey  = prefix .. "CopyToDrop"
        local btnKey   = prefix .. "CopyToButton"
        local hintKey  = prefix .. "CopyToHint"

        if panel[labelKey] then panel[labelKey]:SetShown(active) end
        if panel[btnKey] then panel[btnKey]:SetShown(active) end
        if panel[hintKey] then panel[hintKey]:SetShown(active) end

        local drop = panel[dropKey]
        if drop then
            drop:SetShown(active)
            if active then
                local k = panel[destVar] or defaultDest
                panel[destVar] = k
                if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(drop, k) end
                local label = (_G._MSUF_CopyDestLabel and _G._MSUF_CopyDestLabel(k)) or tostring(k)
                if UIDropDownMenu_SetText then UIDropDownMenu_SetText(drop, label) end
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetCopyVisible file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2776:10"); end

    _MSUF_SetCopyVisible("player", "_msufCopyDestKey",        "target", isPlayerKey and isFramesTab)
    _MSUF_SetCopyVisible("target", "_msufCopyDestKey_target", "player", isTargetKey and isFramesTab)
    _MSUF_SetCopyVisible("focus",  "_msufCopyDestKey_focus",  "target", isFocusKey  and isFramesTab)
    _MSUF_SetCopyVisible("boss",   "_msufCopyDestKey_boss",   "target", isBossKey   and isFramesTab)
    _MSUF_SetCopyVisible("pet",    "_msufCopyDestKey_pet",    "target", isPetKey    and isFramesTab)
    _MSUF_SetCopyVisible("tot",    "_msufCopyDestKey_tot",    "player", isToTKey    and isFramesTab)

-- Castbar toggles (Enable / Time / Interrupt) per unit (Frames tab) [spec-driven]
    for _, spec in ipairs(MSUF_CASTBAR_FRAME_TOGGLE_SPECS) do
        local show = (isFramesTab and currentKey == spec.key)
        MSUF_ApplyCheck(panel, spec.enableW, show, (g[spec.enableK] ~= false))
        MSUF_ApplyCheck(panel, spec.timeW, show, (g[spec.timeK] ~= false))
        MSUF_ApplyCheck(panel, spec.interruptW, show, (conf.showInterrupt ~= false))
    end

-- Indicators (spec-driven)
    for _, id in ipairs(MSUF_INDICATOR_ORDER) do
        local spec = _MSUF_INDICATOR_SPECS[id]
        if spec then
            -- Checkbox
            if spec.showCB and spec.showField and panel[spec.showCB] and panel[spec.showCB].SetChecked then
                panel[spec.showCB]:SetChecked(MSUF_ReadBool(conf, g, spec.showField, spec.showDefault) and true or false)
            end

            -- X/Y offsets
            if spec.xStepper and spec.xField and panel[spec.xStepper] and panel[spec.xStepper].SetValue then
                panel[spec.xStepper]:SetValue(MSUF_ReadNumber(conf, g, spec.xField, spec.xDefault), false)
            end
            if spec.yStepper and spec.yField and panel[spec.yStepper] and panel[spec.yStepper].SetValue then
                panel[spec.yStepper]:SetValue(MSUF_ReadNumber(conf, g, spec.yField, spec.yDefault), false)
            end

            -- Anchor dropdown
            if spec.anchorDrop and spec.anchorField and panel[spec.anchorDrop] then
                local v = MSUF_ReadString(conf, g, spec.anchorField, spec.anchorDefault)
                if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(panel[spec.anchorDrop], v) end
                if UIDropDownMenu_SetText and spec.anchorText then UIDropDownMenu_SetText(panel[spec.anchorDrop], spec.anchorText(v)) end
            end

            -- Optional size editbox
            if spec.sizeEdit and spec.sizeField and panel[spec.sizeEdit] then
                MSUF_SetNumericEditBoxValue(panel[spec.sizeEdit], MSUF_ReadNumber(conf, g, spec.sizeField, spec.sizeDefault))
            end
        end
    end

-- Reflow the indicator block rows depending on which unitframe tab we are on.
if ns and ns.MSUF_Options_Player_LayoutIndicatorTemplate then
    ns.MSUF_Options_Player_LayoutIndicatorTemplate(panel, currentKey)
end


    
-- Castbar icon/text toggles (per-unit overrides with global fallback) [spec-driven]
    for _, spec in ipairs(MSUF_CASTBAR_TEXTICON_SPECS) do
        local show = (isFramesTab and currentKey == spec.key)

        local iconChecked = MSUF_GetShowWithFallback(g[spec.iconK], g.castbarShowIcon)
        local textChecked
        if spec.textDirect then
            textChecked = (g[spec.textK] ~= false)
        else
            textChecked = MSUF_GetShowWithFallback(g[spec.textK], g.castbarShowSpellName)
        end

        MSUF_ApplyCheck(panel, spec.iconW, show, iconChecked)
        MSUF_ApplyCheck(panel, spec.textW, show, textChecked)
    end


-- Portrait dropdown (all unitframes) [spec-driven]
    if panel.playerPortraitDropDown and UIDropDownMenu_SetSelectedValue and UIDropDownMenu_SetText then
        panel.playerPortraitDropDown:Show()

        local mode = MSUF_GetPortraitDropdownValue(conf)
        UIDropDownMenu_SetSelectedValue(panel.playerPortraitDropDown, mode)
        UIDropDownMenu_SetText(panel.playerPortraitDropDown, MSUF_PortraitModeText(mode))
    end



    -- Unit Alpha (in/out of combat) [spec-driven]
    local excludeTP = (conf.alphaExcludeTextPortrait == true)
    if panel.playerAlphaExcludeTextPortraitCB then
        panel.playerAlphaExcludeTextPortraitCB:SetChecked(excludeTP and true or false)
    end

    local layerMode = MSUF_Alpha_NormalizeMode(conf.alphaLayerMode)

    if panel.playerAlphaLayerDropDown and UIDropDownMenu_SetSelectedValue and UIDropDownMenu_SetText then
        panel.playerAlphaLayerDropDown:Show()
        UIDropDownMenu_SetSelectedValue(panel.playerAlphaLayerDropDown, layerMode)
        UIDropDownMenu_SetText(panel.playerAlphaLayerDropDown, (layerMode == "background") and "Background" or "Foreground")

        -- Hard fallback: some dropdown skins won"t display the label unless we also set the FontString.
        local _ddText = (_G and _G["MSUF_UF_AlphaLayerDropDownText"]) or (panel.playerAlphaLayerDropDown and panel.playerAlphaLayerDropDown.Text)
        if _ddText and _ddText.SetText then
            _ddText:SetText((layerMode == "background") and "Background" or "Foreground")
        end

        -- Disable dropdown unless layered alpha is enabled, so users don't pick a mode that does nothing.
        local btn = (_G and _G["MSUF_UF_AlphaLayerDropDownButton"]) or (panel.playerAlphaLayerDropDown and panel.playerAlphaLayerDropDown.Button)
        if btn and btn.Enable and btn.Disable then
            if excludeTP then btn:Enable() else btn:Disable() end
        end
        if panel.playerAlphaLayerDropDown.Text and panel.playerAlphaLayerDropDown.Text.SetTextColor then
            if excludeTP then
                panel.playerAlphaLayerDropDown.Text:SetTextColor(1, 1, 1)
            else
                panel.playerAlphaLayerDropDown.Text:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    end

    if panel.playerAlphaSyncCB then
        panel.playerAlphaSyncCB:SetChecked((conf.alphaSync == true) and true or false)
    end

    local aIn, aOut = MSUF_Alpha_ReadPair(conf, layerMode)
    MSUF_AlphaUI_SetSlider(panel.playerAlphaInCombatSlider, aIn)
    MSUF_AlphaUI_SetSlider(panel.playerAlphaOutCombatSlider, aOut)

-- Boss-only extension: grow the right-side box for boss-only controls (Boss spacing lives under Indicator now).
    local isBoss = (currentKey == "boss")
    if panel.playerSizeBox and panel._msufSizeBaseH then
        panel.playerSizeBox:SetHeight(panel._msufSizeBaseH)
    end
    if panel.playerTextLayoutGroup and panel._msufTextBaseH then
        panel.playerTextLayoutGroup:SetHeight(panel._msufTextBaseH)
    end

    -- Status icons box (player/target only)
    if panel._msufStatusIconsGroup and panel._msufStatusBoxH then
        panel._msufStatusIconsGroup:SetHeight(panel._msufStatusBoxH)
        panel._msufStatusIconsGroup:SetShown((currentKey == "player" or currentKey == "target") and true or false)
    end


    -- Frame size

    -- Boss Spacing (boss only) [spec-driven]
    if panel.playerBossSpacingSlider then
        local show = (currentKey == "boss")
        if panel.playerBossSpacingSlider.SetShown then
            panel.playerBossSpacingSlider:SetShown(show)
        else
            if show then panel.playerBossSpacingSlider:Show() else panel.playerBossSpacingSlider:Hide() end
        end
        if show then
            panel.playerBossSpacingSlider.MSUF_SkipCallback = true
            panel.playerBossSpacingSlider:SetValue(conf.spacing or -36)
            panel.playerBossSpacingSlider.MSUF_SkipCallback = false
            ForceSliderEditBox(panel.playerBossSpacingSlider)
        end
    end

    -- Copy settings button (Player menu)
    MSUF_BindAllCopyButtons(panel)

    -- Copy settings button (Target menu)
    -- (bound by MSUF_BindAllCopyButtons)

    -- Copy settings button (Focus menu)
    -- (bound by MSUF_BindAllCopyButtons)

    -- Copy settings button (Target of Target menu)
    -- (bound by MSUF_BindAllCopyButtons)


    -- Text positioning controls removed (Text group is a placeholder only).


    -- Keep mini headers aligned with the "Indicator" title line after layout has settled.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2973:25");
            MSUF_PositionLeaderMiniHeaders(panel)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2973:25"); end)
    else
        MSUF_PositionLeaderMiniHeaders(panel)
    end

Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_Options_Player_ApplyFromDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2669:0"); end

-- INSTALL HANDLERS (called from Options Core)
function ns.MSUF_Options_Player_InstallHandlers(panel, api) Perfy_Trace(Perfy_GetTime(), "Enter", "ns.MSUF_Options_Player_InstallHandlers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2983:0");
    if not panel or not api then Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_Options_Player_InstallHandlers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2983:0"); return end

    local function IsFramesTab() Perfy_Trace(Perfy_GetTime(), "Enter", "IsFramesTab file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2986:10");
        return Perfy_Trace_Passthrough("Leave", "IsFramesTab file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2986:10", (api.getTabKey and api.getTabKey() == "frames"))
    end

    local function CurrentKey() Perfy_Trace(Perfy_GetTime(), "Enter", "CurrentKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2990:10");
        return Perfy_Trace_Passthrough("Leave", "CurrentKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2990:10", (api.getKey and api.getKey()) or "player")
    end

    -- Make current unit key available to CreatePanel callbacks (dropdowns / edits).
    panel._msufGetCurrentKey = CurrentKey

    panel._msufIsFramesTab = IsFramesTab

    -- Expose API for lightweight UI callbacks (e.g. Copy dropdown)
    panel._msufAPI = api

    local function ApplyCurrent() Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyCurrent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3002:10");
        if api.ApplySettingsForKey then
            api.ApplySettingsForKey(CurrentKey())
        end
Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyCurrent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3002:10"); end

local function ApplyLayoutCurrent(reason) Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyLayoutCurrent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3008:6");
    local key = CurrentKey()
    local fn = _G and _G.MSUF_UFCore_RequestLayoutForUnit
    if type(fn) == "function" then
        local urgent = (key == "target" or key == "targettarget" or key == "focus")
        pcall(fn, key, reason or "OPTIONS_LAYOUT", urgent)
        Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyLayoutCurrent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3008:6"); return
    end
    ApplyCurrent()
Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyLayoutCurrent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3008:6"); end

    local function EnsureKeyDB() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureKeyDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3019:10");
        if api.EnsureDB then api.EnsureDB() end
        local key = (CurrentKey and CurrentKey()) or "player"
        if key == "tot" then key = "targettarget" end -- back-compat / alias safety
        if panel then panel._msufLastApplyKey = key end
        MSUF_DB[key] = MSUF_DB[key] or {}
        return Perfy_Trace_Passthrough("Leave", "EnsureKeyDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3019:10", MSUF_DB[key])
    end

    -- Indicator reset binding (shared helper for Leader / Raid Marker / Level)
    local function MSUF_ApplyStepper(stepper, v) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ApplyStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3029:10");
        if not stepper then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3029:10"); return end
        stepper:SetValue(v, false)
        if stepper.editBox and (not stepper.editBox:HasFocus()) then
            stepper.editBox:SetText(tostring(v))
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3029:10"); end

    local function MSUF_ApplyDropdown(drop, value, textFunc) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ApplyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3037:10");
        if not drop then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3037:10"); return end
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(drop, value) end
        if UIDropDownMenu_SetText and textFunc then UIDropDownMenu_SetText(drop, textFunc(value)) end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3037:10"); end
    -- Indicator row specs (shared)
    local INDICATOR_SPECS = _MSUF_INDICATOR_SPECS

local function MSUF_CanonIndicatorKey() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CanonIndicatorKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3045:6");
    local key = (CurrentKey and CurrentKey()) or "player"
    if key == "tot" then key = "targettarget" end
    if type(key) == "string" and key:match("^boss") then key = "boss" end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CanonIndicatorKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3045:6"); return key
end

local function MSUF_GetIndicatorConfAndGeneral() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetIndicatorConfAndGeneral file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3052:6");
    EnsureDB()
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    local key = MSUF_CanonIndicatorKey()
    MSUF_DB[key] = MSUF_DB[key] or {}
    local conf = MSUF_DB[key]
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetIndicatorConfAndGeneral file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3052:6"); return conf, g, key
end

-- Use shared MSUF_ReadBool / MSUF_ReadNumber / MSUF_ReadString helpers (file-scope)

local function MSUF_CallIndicatorRefresh(spec) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CallIndicatorRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3066:6");
    if not spec then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CallIndicatorRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3066:6"); return end

    -- Some indicator systems still have dedicated refresh helpers (e.g. leader/assist icon rebuild).
    local fnName = spec.refreshFnName
    if fnName then
        local fn = _G and _G[fnName]
        if type(fn) == "function" then
            pcall(fn)
        end
    end

    -- Always request a layout pass so size/anchor changes apply without forcing full updates.
    ApplyLayoutCurrent("INDICATOR")
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CallIndicatorRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3066:6"); end

local function MSUF_ApplyIndicatorUI(spec) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ApplyIndicatorUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3082:6");
    if not spec then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyIndicatorUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3082:6"); return end
    if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyIndicatorUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3082:6"); return end

    local conf, g, key = MSUF_GetIndicatorConfAndGeneral()
    if spec.allowed and (not spec.allowed(key)) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyIndicatorUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3082:6"); return end

    if spec.showCB and panel[spec.showCB] and spec.showField then
        panel[spec.showCB]:SetChecked(MSUF_ReadBool(conf, g, spec.showField, spec.showDefault))
    end
    if spec.xStepper and panel[spec.xStepper] and spec.xField then
        MSUF_ApplyStepper(panel[spec.xStepper], MSUF_ReadNumber(conf, g, spec.xField, spec.xDefault))
    end
    if spec.yStepper and panel[spec.yStepper] and spec.yField then
        MSUF_ApplyStepper(panel[spec.yStepper], MSUF_ReadNumber(conf, g, spec.yField, spec.yDefault))
    end
    if spec.anchorDrop and panel[spec.anchorDrop] and spec.anchorField then
        local a = MSUF_ReadString(conf, g, spec.anchorField, spec.anchorDefault)
        MSUF_ApplyDropdown(panel[spec.anchorDrop], a, spec.anchorText)
    end

    if spec.iconDrop and panel[spec.iconDrop] and spec.iconField then
        local v = MSUF_ReadString(conf, g, spec.iconField, spec.iconDefault)
        MSUF_ApplyDropdown(panel[spec.iconDrop], v, spec.iconText)
    end
    if spec.sizeEdit and panel[spec.sizeEdit] and spec.sizeField then
        local v = conf and conf[spec.sizeField]
        if type(v) ~= "number" and g then v = g[spec.sizeField] end
        if type(v) ~= "number" and spec.id == "level" then
            -- Wenn kein eigener Wert gesetzt ist: zeige effektive Name-Fontgröße als Default.
            v = MSUF_ReadNumber(conf, g, "nameFontSize", 14)
        end
        v = tonumber(v) or spec.sizeDefault or 14
        v = math.floor(v + 0.5)
        if v < 8 then v = 8 end
        if v > 64 then v = 64 end
        MSUF_SetNumericEditBoxValue(panel[spec.sizeEdit], v)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyIndicatorUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3082:6"); end

local function MSUF_ResetIndicatorRow(rowId) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ResetIndicatorRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3122:6");
    if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResetIndicatorRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3122:6"); return end
    if not rowId then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResetIndicatorRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3122:6"); return end

    local spec = INDICATOR_SPECS[rowId]
    if not spec then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResetIndicatorRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3122:6"); return end

    local conf, _, key = MSUF_GetIndicatorConfAndGeneral()
    if spec.allowed and (not spec.allowed(key)) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResetIndicatorRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3122:6"); return end

    if spec.xField then conf[spec.xField] = nil end
    if spec.yField then conf[spec.yField] = nil end
    if spec.anchorField then conf[spec.anchorField] = nil end
    if spec.iconField then conf[spec.iconField] = nil end
    if spec.sizeField then conf[spec.sizeField] = nil end

    MSUF_ApplyIndicatorUI(spec)

    ApplyLayoutCurrent("INDICATOR_RESET")
    MSUF_CallIndicatorRefresh(spec)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResetIndicatorRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3122:6"); end

    local function MSUF_BindIndicatorResetButton(btn, rowId) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_BindIndicatorResetButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3144:10");
        if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BindIndicatorResetButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3144:10"); return end
        btn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3146:33");
            MSUF_ResetIndicatorRow(rowId)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3146:33"); end)
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BindIndicatorResetButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3144:10"); end

    for _, rowId in ipairs(MSUF_INDICATOR_ORDER) do
        local spec = INDICATOR_SPECS[rowId]
        if spec and spec.resetBtn then
            MSUF_BindIndicatorResetButton(panel[spec.resetBtn], rowId)
        end
    end

-- Bind all indicator-row controls from a single spec table
local function MSUF_BindIndicatorRow(spec) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_BindIndicatorRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3159:6");
    if not spec then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BindIndicatorRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3159:6"); return end

    local function AllowedNow() Perfy_Trace(Perfy_GetTime(), "Enter", "AllowedNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3162:10");
        local _, _, key = MSUF_GetIndicatorConfAndGeneral()
        if spec.allowed and (not spec.allowed(key)) then Perfy_Trace(Perfy_GetTime(), "Leave", "AllowedNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3162:10"); return false end
        Perfy_Trace(Perfy_GetTime(), "Leave", "AllowedNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3162:10"); return true
    end

    local function Refresh() Perfy_Trace(Perfy_GetTime(), "Enter", "Refresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3168:10");
        MSUF_CallIndicatorRefresh(spec)
    Perfy_Trace(Perfy_GetTime(), "Leave", "Refresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3168:10"); end

    -- Checkbox
    if spec.showCB and panel[spec.showCB] and spec.showField then
        local cb = panel[spec.showCB]
        cb:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3175:32");
            if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3175:32"); return end
            if not AllowedNow() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3175:32"); return end

            local conf, _, key = MSUF_GetIndicatorConfAndGeneral()
            conf[spec.showField] = self:GetChecked() and true or false

            Refresh()
            -- Best-effort: immediately refresh current unitframe if present (coalesced)
            local uf = _G and (_G.MSUF_UnitFrames or _G.UnitFrames)
            local fr = (uf and key) and uf[key] or nil
            if fr and type(_G.MSUF_RequestUnitframeUpdate) == "function" then
                _G.MSUF_RequestUnitframeUpdate(fr, true, true, "IndicatorToggle")
            elseif fr and type(_G.UpdateSimpleUnitFrame) == "function" then
                _G.UpdateSimpleUnitFrame(fr)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3175:32"); end)
        cb:HookScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3192:32"); MSUF_ApplyIndicatorUI(spec) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3192:32"); end)
    end

    -- Steppers (offsets)
    local function BindStepper(stepperName, fieldName, defaultVal) Perfy_Trace(Perfy_GetTime(), "Enter", "BindStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3196:10");
        if not stepperName or not fieldName then Perfy_Trace(Perfy_GetTime(), "Leave", "BindStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3196:10"); return end
        local st = panel[stepperName]
        if not st then Perfy_Trace(Perfy_GetTime(), "Leave", "BindStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3196:10"); return end

        st.onValueChanged = function(_, v) Perfy_Trace(Perfy_GetTime(), "Enter", "st.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3201:28");
            if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "st.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3201:28"); return end
            if not AllowedNow() then Perfy_Trace(Perfy_GetTime(), "Leave", "st.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3201:28"); return end
            local conf = MSUF_GetIndicatorConfAndGeneral()
            conf[fieldName] = tonumber(v) or (defaultVal or 0)
            Refresh()
        Perfy_Trace(Perfy_GetTime(), "Leave", "st.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3201:28"); end

        st:SetScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3209:31"); MSUF_ApplyIndicatorUI(spec) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3209:31"); end)
    Perfy_Trace(Perfy_GetTime(), "Leave", "BindStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3196:10"); end

    BindStepper(spec.xStepper, spec.xField, spec.xDefault)
    BindStepper(spec.yStepper, spec.yField, spec.yDefault)

    
    -- Dropdown (anchor)
    if spec.anchorDrop and panel[spec.anchorDrop] and spec.anchorField and UIDropDownMenu_Initialize then
        local drop = panel[spec.anchorDrop]

        UIDropDownMenu_Initialize(drop, function(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3220:40");
            if not level or level ~= 1 then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3220:40"); return end
            if not AllowedNow() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3220:40"); return end

            local function GetCurrent() Perfy_Trace(Perfy_GetTime(), "Enter", "GetCurrent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3224:18");
                local conf, g = MSUF_GetIndicatorConfAndGeneral()
                return Perfy_Trace_Passthrough("Leave", "GetCurrent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3224:18", MSUF_ReadString(conf, g, spec.anchorField, spec.anchorDefault))
            end

            local function IsChecked(v) Perfy_Trace(Perfy_GetTime(), "Enter", "IsChecked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3229:18");
                return Perfy_Trace_Passthrough("Leave", "IsChecked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3229:18", (GetCurrent() == v))
            end

            local function OnSelect(btn, value, textLabel) Perfy_Trace(Perfy_GetTime(), "Enter", "OnSelect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3233:18");
                if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "OnSelect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3233:18"); return end

                local conf2, _, key2 = MSUF_GetIndicatorConfAndGeneral()
                if spec.allowed and (not spec.allowed(key2)) then Perfy_Trace(Perfy_GetTime(), "Leave", "OnSelect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3233:18"); return end

                local v = (btn and btn.value) or value or spec.anchorDefault
                conf2[spec.anchorField] = v

                if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(drop, v) end
                if UIDropDownMenu_SetText then
                    -- Prefer spec.anchorText() for consistent labels, but fall back to the item label.
                    local label = (spec.anchorText and spec.anchorText(v)) or textLabel or tostring(v)
                    UIDropDownMenu_SetText(drop, label)
                end

                if CloseDropDownMenus then CloseDropDownMenus() end

                -- Live-apply
                Refresh()
            Perfy_Trace(Perfy_GetTime(), "Leave", "OnSelect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3233:18"); end

            for _, pair in ipairs(spec.anchorChoices or {}) do
                local textLabel, value = pair[1], pair[2]
                local info = UIDropDownMenu_CreateInfo()
                info.text  = textLabel
                info.value = value
                info.func  = function(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3260:29"); OnSelect(btn, value, textLabel) Perfy_Trace(Perfy_GetTime(), "Leave", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3260:29"); end
                info.checked = function() Perfy_Trace(Perfy_GetTime(), "Enter", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3261:31"); return Perfy_Trace_Passthrough("Leave", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3261:31", IsChecked(value)) end
                info.isNotRadio = false
                UIDropDownMenu_AddButton(info, level)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3220:40"); end)

        drop:SetScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3267:33"); MSUF_ApplyIndicatorUI(spec) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3267:33"); end)
    end


    -- Dropdown (icon symbol - dummy, wired for DB storage)
    if spec.iconDrop and panel[spec.iconDrop] and spec.iconField and UIDropDownMenu_Initialize then
        local drop2 = panel[spec.iconDrop]

        UIDropDownMenu_Initialize(drop2, function(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3275:41");
            if not level or level ~= 1 then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3275:41"); return end
            if not AllowedNow() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3275:41"); return end

            local function GetCurrent() Perfy_Trace(Perfy_GetTime(), "Enter", "GetCurrent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3279:18");
                local conf3, g3 = MSUF_GetIndicatorConfAndGeneral()
                return Perfy_Trace_Passthrough("Leave", "GetCurrent file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3279:18", MSUF_ReadString(conf3, g3, spec.iconField, spec.iconDefault))
            end

            local function IsChecked(v) Perfy_Trace(Perfy_GetTime(), "Enter", "IsChecked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3284:18");
                return Perfy_Trace_Passthrough("Leave", "IsChecked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3284:18", (GetCurrent() == v))
            end

            local function OnSelect(btn, value, textLabel) Perfy_Trace(Perfy_GetTime(), "Enter", "OnSelect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3288:18");
                if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "OnSelect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3288:18"); return end

                local conf4, _, key4 = MSUF_GetIndicatorConfAndGeneral()
                if spec.allowed and (not spec.allowed(key4)) then Perfy_Trace(Perfy_GetTime(), "Leave", "OnSelect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3288:18"); return end

                local v = (btn and btn.value) or value or spec.iconDefault
                conf4[spec.iconField] = v

                if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(drop2, v) end
                if UIDropDownMenu_SetText then
                    local label = (spec.iconText and spec.iconText(v)) or textLabel or tostring(v)
                    UIDropDownMenu_SetText(drop2, label)
                end

                if CloseDropDownMenus then CloseDropDownMenus() end
                Refresh()
            Perfy_Trace(Perfy_GetTime(), "Leave", "OnSelect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3288:18"); end

            local _choices = spec.iconChoices
            if type(_choices) == "function" then
                _choices = _choices()
            end

            for _, pair in ipairs(_choices or {}) do
                local textLabel, value = pair[1], pair[2]
                local info = UIDropDownMenu_CreateInfo()
                info.text  = textLabel
                info.value = value

                -- Optional icon preview (used by Status icon symbols)
                local tex = (type(MSUF_StatusIcon_GetSymbolTexture) == "function") and MSUF_StatusIcon_GetSymbolTexture(value) or nil
                if tex then
                    info.icon = tex
                    info.iconInfo = {
                        tCoordLeft = 0, tCoordRight = 1,
                        tCoordTop = 0, tCoordBottom = 1,
                        tSizeX = 16, tSizeY = 16,
                        tFitDropDownSizeX = true,
                    }
                end

                info.func  = function(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3330:29"); OnSelect(btn, value, textLabel) Perfy_Trace(Perfy_GetTime(), "Leave", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3330:29"); end
                info.checked = function() Perfy_Trace(Perfy_GetTime(), "Enter", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3331:31"); return Perfy_Trace_Passthrough("Leave", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3331:31", IsChecked(value)) end
                info.isNotRadio = false
                UIDropDownMenu_AddButton(info, level)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3275:41"); end)

        drop2:SetScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3337:34"); MSUF_ApplyIndicatorUI(spec) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3337:34"); end)
    end



    -- Numeric edit box (size)
    if spec.sizeEdit and panel[spec.sizeEdit] and spec.sizeField then
        local edit = panel[spec.sizeEdit]

        local function ApplySize() Perfy_Trace(Perfy_GetTime(), "Enter", "ApplySize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3346:14");
            if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "ApplySize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3346:14"); return end
            if not AllowedNow() then Perfy_Trace(Perfy_GetTime(), "Leave", "ApplySize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3346:14"); return end

            local conf, g = MSUF_GetIndicatorConfAndGeneral()

            local v = tonumber(edit:GetText())
            if not v then
                v = MSUF_ReadNumber(conf, g, spec.sizeField, spec.sizeDefault or 14)
            end

            v = math.floor((tonumber(v) or (spec.sizeDefault or 14)) + 0.5)
            if v < 8 then v = 8 end
            if v > 64 then v = 64 end

            conf[spec.sizeField] = v
            MSUF_SetNumericEditBoxValue(edit, v)


            -- Level size changes need a font refresh (otherwise it looks like the size box "does nothing").
            if spec.id == "level" then
                if type(_G.MSUF_UpdateAllFonts_Immediate) == "function" then
                    _G.MSUF_UpdateAllFonts_Immediate()
                elseif type(_G.MSUF_UpdateAllFonts) == "function" then
                    _G.MSUF_UpdateAllFonts()
                elseif type(_G.UpdateAllFonts) == "function" then
                    _G.UpdateAllFonts()
                end

                -- Also poke the current unitframe to ensure immediate visual sync.
                local _, _, _key = MSUF_GetIndicatorConfAndGeneral()
                local uf = _G and (_G.MSUF_UnitFrames or _G.UnitFrames)
                local fr = (uf and _key) and uf[_key] or nil
                if fr and type(_G.MSUF_RequestUnitframeUpdate) == "function" then
                    _G.MSUF_RequestUnitframeUpdate(fr, true, true, "LevelIndicatorSize")
                elseif fr and type(_G.UpdateSimpleUnitFrame) == "function" then
                    pcall(_G.UpdateSimpleUnitFrame, fr, true)
                end
            end
            Refresh()
        Perfy_Trace(Perfy_GetTime(), "Leave", "ApplySize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3346:14"); end

        edit:SetScript("OnEnterPressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3388:41"); ApplySize(); self:ClearFocus() Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3388:41"); end)
        edit:SetScript("OnEditFocusLost", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3389:42"); ApplySize() Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3389:42"); end)
        edit:SetScript("OnTextChanged", function(self, userInput) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3390:40");
            if not userInput then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3390:40"); return end
            self._msufIndSizeSeq = (self._msufIndSizeSeq or 0) + 1
            local seq = self._msufIndSizeSeq
            if C_Timer and C_Timer.After then
                C_Timer.After(0.25, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3395:36");
                    if self._msufIndSizeSeq == seq and self:HasFocus() then
                        ApplySize()
                    end
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3395:36"); end)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3390:40"); end)
        edit:HookScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3402:34"); MSUF_ApplyIndicatorUI(spec) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3402:34"); end)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BindIndicatorRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3159:6"); end

for _, rowId in ipairs(MSUF_INDICATOR_ORDER) do
    MSUF_BindIndicatorRow(INDICATOR_SPECS[rowId])
end


-- Status icons (Step 1): Combat row uses indicator-style controls (player/target)
_G.MSUF_RequestStatusCombatIndicatorRefresh = _G.MSUF_RequestStatusCombatIndicatorRefresh or function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3412:93");
    ApplyLayoutCurrent("STATUSICON_COMBAT")

    local _, _, key = MSUF_GetIndicatorConfAndGeneral()
    if not (key == "player" or key == "target") then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3412:93"); return end

    local uf = _G and (_G.MSUF_UnitFrames or _G.UnitFrames)
    local fr = (uf and key) and uf[key] or nil
    if fr and type(_G.MSUF_RequestUnitframeUpdate) == "function" then
        _G.MSUF_RequestUnitframeUpdate(fr, true, true, "StatusCombatIndicator")
    elseif fr and type(_G.UpdateSimpleUnitFrame) == "function" then
        pcall(_G.UpdateSimpleUnitFrame, fr, true)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3412:93"); end

local function MSUF_BuildStatusCombatSpec() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_BuildStatusCombatSpec file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3427:6");
    local spec = {}
    spec.id = "status_combat"
    spec.order = 100
    spec.allowed = function(key) Perfy_Trace(Perfy_GetTime(), "Enter", "spec.allowed file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3431:19"); return Perfy_Trace_Passthrough("Leave", "spec.allowed file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3431:19", (key == "player" or key == "target")) end

    spec.showCB = "statusCombatIconCB"
    spec.showField = "showCombatStateIndicator"
    spec.showDefault = true

    spec.xStepper = "statusCombatOffsetXStepper"
    spec.xField = "combatStateIndicatorOffsetX"
    spec.xDefault = 0

    spec.yStepper = "statusCombatOffsetYStepper"
    spec.yField = "combatStateIndicatorOffsetY"
    spec.yDefault = 0

    spec.anchorDrop = "statusCombatAnchorDrop"
    spec.anchorLabel = "statusCombatAnchorLabel"
    spec.anchorField = "combatStateIndicatorAnchor"
    spec.anchorDefault = "TOPLEFT"
    spec.anchorText = function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "spec.anchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3449:22"); return Perfy_Trace_Passthrough("Leave", "spec.anchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3449:22", MSUF_LeaderAnchorText(v)) end
    spec.anchorChoices = {
        { MSUF_LeaderAnchorText("TOPLEFT"), "TOPLEFT" },
        { MSUF_LeaderAnchorText("TOPRIGHT"), "TOPRIGHT" },
        { MSUF_LeaderAnchorText("BOTTOMLEFT"), "BOTTOMLEFT" },
        { MSUF_LeaderAnchorText("BOTTOMRIGHT"), "BOTTOMRIGHT" },
    }

    spec.sizeEdit = "statusCombatSizeEdit"
    spec.sizeLabel = "statusCombatSizeLabel"
    spec.sizeField = "combatStateIndicatorSize"
    spec.sizeDefault = 18

    spec.iconDrop = "statusCombatSymbolDrop"
    spec.iconLabel = "statusCombatSymbolLabel"
    spec.iconField = "combatStateIndicatorSymbol"
    spec.iconDefault = "DEFAULT"
    spec.iconText = MSUF_StatusIcon_SymbolText
    spec.iconChoices = MSUF_StatusIcon_GetSymbolChoices

    spec.divider = "statusCombatGroupDivider"
    spec.resetBtn = "statusCombatResetBtn"
    spec.refreshFnName = "MSUF_RequestStatusCombatIndicatorRefresh"
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BuildStatusCombatSpec file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3427:6"); return spec
end

local STATUSICON_COMBAT_SPEC = MSUF_BuildStatusCombatSpec()

MSUF_BindIndicatorRow(STATUSICON_COMBAT_SPEC)

-- Reset button: X/Y/Anchor/Size back to global defaults
if panel.statusCombatResetBtn then
    panel.statusCombatResetBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3481:52");
        if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3481:52"); return end
        local conf, _, key = MSUF_GetIndicatorConfAndGeneral()
        if not (key == "player" or key == "target") then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3481:52"); return end

        conf.combatStateIndicatorOffsetX = nil
        conf.combatStateIndicatorOffsetY = nil
        conf.combatStateIndicatorAnchor  = nil
        conf.combatStateIndicatorSize    = nil

        MSUF_ApplyIndicatorUI(STATUSICON_COMBAT_SPEC)
        MSUF_CallIndicatorRefresh(STATUSICON_COMBAT_SPEC)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3481:52"); end)
end

-- Status icons (Step 2): Rested row uses indicator-style controls (player only)
_G.MSUF_RequestStatusRestingIndicatorRefresh = _G.MSUF_RequestStatusRestingIndicatorRefresh or function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3497:95");
    ApplyLayoutCurrent("STATUSICON_RESTED")

    local _, _, key = MSUF_GetIndicatorConfAndGeneral()
    if key ~= "player" then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3497:95"); return end

    local uf = _G and (_G.MSUF_UnitFrames or _G.UnitFrames)
    local fr = (uf and "player") and uf["player"] or nil
    if fr and type(_G.MSUF_RequestUnitframeUpdate) == "function" then
        _G.MSUF_RequestUnitframeUpdate(fr, true, true, "StatusRestingIndicator")
    elseif fr and type(_G.UpdateSimpleUnitFrame) == "function" then
        pcall(_G.UpdateSimpleUnitFrame, fr, true)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3497:95"); end

local function MSUF_BuildStatusRestedSpec() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_BuildStatusRestedSpec file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3512:6");
    local spec = {}
    spec.id = "status_rested"
    spec.order = 110
    spec.allowed = function(key) Perfy_Trace(Perfy_GetTime(), "Enter", "spec.allowed file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3516:19"); return Perfy_Trace_Passthrough("Leave", "spec.allowed file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3516:19", (key == "player")) end -- player only

    spec.showCB = "statusRestingIconCB"
    spec.showField = "showRestingIndicator"
    spec.showDefault = false

    spec.xStepper = "statusRestingOffsetXStepper"
    spec.xField = "restedStateIndicatorOffsetX"
    spec.xDefault = 0

    spec.yStepper = "statusRestingOffsetYStepper"
    spec.yField = "restedStateIndicatorOffsetY"
    spec.yDefault = 0

    spec.anchorDrop = "statusRestingAnchorDrop"
    spec.anchorLabel = "statusRestingAnchorLabel"
    spec.anchorField = "restedStateIndicatorAnchor"
    spec.anchorDefault = "TOPLEFT"
    spec.anchorText = function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "spec.anchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3534:22"); return Perfy_Trace_Passthrough("Leave", "spec.anchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3534:22", MSUF_LeaderAnchorText(v)) end
    spec.anchorChoices = {
        { MSUF_LeaderAnchorText("TOPLEFT"), "TOPLEFT" },
        { MSUF_LeaderAnchorText("TOPRIGHT"), "TOPRIGHT" },
        { MSUF_LeaderAnchorText("BOTTOMLEFT"), "BOTTOMLEFT" },
        { MSUF_LeaderAnchorText("BOTTOMRIGHT"), "BOTTOMRIGHT" },
    }

    spec.sizeEdit = "statusRestingSizeEdit"
    spec.sizeLabel = "statusRestingSizeLabel"
    spec.sizeField = "restedStateIndicatorSize"
    spec.sizeDefault = 18

    spec.iconDrop = "statusRestingSymbolDrop"
    spec.iconLabel = "statusRestingSymbolLabel"
    spec.iconField = "restedStateIndicatorSymbol"
    spec.iconDefault = "DEFAULT"
    spec.iconText = MSUF_StatusIcon_SymbolText
    spec.iconChoices = MSUF_StatusIcon_GetRestedSymbolChoices

    spec.divider = "statusRestingGroupDivider"
    spec.resetBtn = "statusRestingResetBtn"
    spec.refreshFnName = "MSUF_RequestStatusRestingIndicatorRefresh"
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BuildStatusRestedSpec file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3512:6"); return spec
end

local STATUSICON_RESTING_SPEC = MSUF_BuildStatusRestedSpec()

MSUF_BindIndicatorRow(STATUSICON_RESTING_SPEC)

-- Reset button: X/Y/Anchor/Size back to global defaults
if panel.statusRestingResetBtn then
    panel.statusRestingResetBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3566:53");
        if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3566:53"); return end
        local conf, _, key = MSUF_GetIndicatorConfAndGeneral()
        if key ~= "player" then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3566:53"); return end

        conf.restedStateIndicatorOffsetX = nil
        conf.restedStateIndicatorOffsetY = nil
        conf.restedStateIndicatorAnchor  = nil
        conf.restedStateIndicatorSize    = nil

        conf.restedStateIndicatorSymbol  = nil
        MSUF_ApplyIndicatorUI(STATUSICON_RESTING_SPEC)
        MSUF_CallIndicatorRefresh(STATUSICON_RESTING_SPEC)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3566:53"); end)
end

-- Status icons (Step 3): Incoming Rez row uses indicator-style controls (player/target)
_G.MSUF_RequestStatusIncomingResIndicatorRefresh = _G.MSUF_RequestStatusIncomingResIndicatorRefresh or function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3583:103");
    ApplyLayoutCurrent("STATUSICON_INCOMINGRES")

    local _, _, key = MSUF_GetIndicatorConfAndGeneral()
    if not (key == "player" or key == "target") then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3583:103"); return end

    local uf = _G and (_G.MSUF_UnitFrames or _G.UnitFrames)
    local fr = (uf and key) and uf[key] or nil
    if fr and type(_G.MSUF_RequestUnitframeUpdate) == "function" then
        _G.MSUF_RequestUnitframeUpdate(fr, true, true, "StatusIncomingResIndicator")
    elseif fr and type(_G.UpdateSimpleUnitFrame) == "function" then
        pcall(_G.UpdateSimpleUnitFrame, fr, true)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3583:103"); end

local function MSUF_BuildStatusIncomingResSpec() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_BuildStatusIncomingResSpec file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3598:6");
    local spec = {}
    spec.id = "status_incoming_res"
    spec.order = 120
    spec.allowed = function(key) Perfy_Trace(Perfy_GetTime(), "Enter", "spec.allowed file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3602:19"); return Perfy_Trace_Passthrough("Leave", "spec.allowed file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3602:19", (key == "player" or key == "target")) end

    spec.showCB = "statusIncomingResIconCB"
    spec.showField = "showIncomingResIndicator"
    spec.showDefault = true

    spec.xStepper = "statusIncomingResOffsetXStepper"
    spec.xField = "incomingResIndicatorOffsetX"
    spec.xDefault = 0

    spec.yStepper = "statusIncomingResOffsetYStepper"
    spec.yField = "incomingResIndicatorOffsetY"
    spec.yDefault = 0

    spec.anchorDrop = "statusIncomingResAnchorDrop"
    spec.anchorLabel = "statusIncomingResAnchorLabel"
    spec.anchorField = "incomingResIndicatorAnchor"
    spec.anchorDefault = "TOPLEFT"
    spec.anchorText = function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "spec.anchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3620:22"); return Perfy_Trace_Passthrough("Leave", "spec.anchorText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3620:22", MSUF_LeaderAnchorText(v)) end
    spec.anchorChoices = {
        { MSUF_LeaderAnchorText("TOPLEFT"), "TOPLEFT" },
        { MSUF_LeaderAnchorText("TOPRIGHT"), "TOPRIGHT" },
        { MSUF_LeaderAnchorText("BOTTOMLEFT"), "BOTTOMLEFT" },
        { MSUF_LeaderAnchorText("BOTTOMRIGHT"), "BOTTOMRIGHT" },
    }

    spec.sizeEdit = "statusIncomingResSizeEdit"
    spec.sizeLabel = "statusIncomingResSizeLabel"
    spec.sizeField = "incomingResIndicatorSize"
    spec.sizeDefault = 18

    spec.iconDrop = "statusIncomingResSymbolDrop"
    spec.iconLabel = "statusIncomingResSymbolLabel"
    spec.iconField = "incomingResIndicatorSymbol"
    spec.iconDefault = "DEFAULT"
    spec.iconText = MSUF_StatusIcon_SymbolText
    spec.iconChoices = MSUF_StatusIcon_GetRessSymbolChoices

    spec.divider = "statusIncomingResGroupDivider"
    spec.resetBtn = "statusIncomingResResetBtn"
    spec.refreshFnName = "MSUF_RequestStatusIncomingResIndicatorRefresh"
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BuildStatusIncomingResSpec file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3598:6"); return spec
end

local STATUSICON_INCOMINGRES_SPEC = MSUF_BuildStatusIncomingResSpec()

MSUF_BindIndicatorRow(STATUSICON_INCOMINGRES_SPEC)

-- Reset button: X/Y/Anchor/Size back to global defaults
if panel.statusIncomingResResetBtn then
    panel.statusIncomingResResetBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3652:57");
        if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3652:57"); return end
        local conf, _, key = MSUF_GetIndicatorConfAndGeneral()
        if not (key == "player" or key == "target") then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3652:57"); return end

        conf.incomingResIndicatorOffsetX = nil
        conf.incomingResIndicatorOffsetY = nil
        conf.incomingResIndicatorAnchor  = nil
        conf.incomingResIndicatorSize    = nil

        MSUF_ApplyIndicatorUI(STATUSICON_INCOMINGRES_SPEC)
        MSUF_CallIndicatorRefresh(STATUSICON_INCOMINGRES_SPEC)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3652:57"); end)
end

-- Status icons (Combat / Rested / Incoming Rez) per-unit overrides
local function MSUF_ApplyStatusIconsUI() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ApplyStatusIconsUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3668:6");
    if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyStatusIconsUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3668:6"); return end
    local conf, g, key = MSUF_GetIndicatorConfAndGeneral()
    if not (key == "player" or key == "target") then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyStatusIconsUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3668:6"); return end

    -- Combat row uses indicator-style controls (Step 1)
    if STATUSICON_COMBAT_SPEC then
        MSUF_ApplyIndicatorUI(STATUSICON_COMBAT_SPEC)
    elseif panel.statusCombatIconCB then
        panel.statusCombatIconCB:SetChecked(MSUF_ReadBool(conf, g, "showCombatStateIndicator", true))
    end
    -- Rested row uses indicator-style controls (Step 2, player only)
    if STATUSICON_RESTING_SPEC then
        MSUF_ApplyIndicatorUI(STATUSICON_RESTING_SPEC)
    elseif panel.statusRestingIconCB then
        panel.statusRestingIconCB:SetChecked(MSUF_ReadBool(conf, g, "showRestingIndicator", true))
    end

    if STATUSICON_INCOMINGRES_SPEC then
        MSUF_ApplyIndicatorUI(STATUSICON_INCOMINGRES_SPEC)
    elseif panel.statusIncomingResIconCB then
        panel.statusIncomingResIconCB:SetChecked(MSUF_ReadBool(conf, g, "showIncomingResIndicator", true))
    end
    if panel.statusIconsTestModeCB then
        panel.statusIconsTestModeCB:SetChecked((type(g) == "table" and g.stateIconsTestMode == true) or false)
    end

    if panel.statusIconsStyleCB then
        panel.statusIconsStyleCB:SetChecked(MSUF_GetStatusIconStyleUseMidnight())
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyStatusIconsUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3668:6"); end

local function MSUF_RequestStatusIconRefresh(key) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_RequestStatusIconRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3700:6");
    ApplyLayoutCurrent("STATUSICON_TOGGLE")
    local uf = _G and (_G.MSUF_UnitFrames or _G.UnitFrames)
    local fr = (uf and key) and uf[key] or nil
    if fr and type(_G.MSUF_RequestUnitframeUpdate) == "function" then
        _G.MSUF_RequestUnitframeUpdate(fr, true, true, "StatusIconToggle")
    elseif fr and type(_G.UpdateSimpleUnitFrame) == "function" then
        _G.UpdateSimpleUnitFrame(fr)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RequestStatusIconRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3700:6"); end

local function MSUF_BindStatusIconToggle(cb, field, allowedKey) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_BindStatusIconToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3711:6");
    if not cb then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BindStatusIconToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3711:6"); return end

    -- Store on the widget itself so we can't accidentally capture the wrong key if this gets
    -- rebound/reused by future refactors.
    cb._msufStatusField = field
    cb._msufStatusAllowedKey = allowedKey

    cb:SetScript("OnClick", function(self, button) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3719:28");
        if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3719:28"); return end
        local conf, _, key = MSUF_GetIndicatorConfAndGeneral()
        local fieldName = self._msufStatusField
        local allowKey  = self._msufStatusAllowedKey

        if allowKey and key ~= allowKey then
            -- For player-only toggles (Rested), ignore clicks on other tabs.
            MSUF_ApplyStatusIconsUI()
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3719:28"); return
        end

        if type(fieldName) ~= "string" or fieldName == "" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3719:28"); return
        end

        if button == "RightButton" then
            conf[fieldName] = nil -- reset to global
        else
            conf[fieldName] = self:GetChecked() and true or false
        end

        MSUF_ApplyStatusIconsUI()
        MSUF_RequestStatusIconRefresh(key)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3719:28"); end)

    cb:HookScript("OnShow", MSUF_ApplyStatusIconsUI)
    cb:HookScript("OnEnter", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3746:29");
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Status icon")
            GameTooltip:AddLine("Left-click: set this frame override", 1, 1, 1)
            GameTooltip:AddLine("Right-click: reset to global setting", 1, 1, 1)
            GameTooltip:Show()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3746:29"); end)
    cb:HookScript("OnLeave", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3755:29"); if GameTooltip then GameTooltip:Hide() end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3755:29"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BindStatusIconToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3711:6"); end

-- Combat row is bound via MSUF_BindIndicatorRow(STATUSICON_COMBAT_SPEC) (Step 1)
-- MSUF_BindStatusIconToggle(panel.statusCombatIconCB, "showCombatStateIndicator", nil)
-- Rested row is bound via MSUF_BindIndicatorRow(STATUSICON_RESTING_SPEC) (Step 2)
-- MSUF_BindStatusIconToggle(panel.statusRestingIconCB, "showRestingIndicator", "player")
-- Incoming Rez row is bound via MSUF_BindIndicatorRow(STATUSICON_INCOMINGRES_SPEC) (Step 3)

-- Shared test mode toggle (sync between Player/Target pages + Edit Mode preview checkbox)
if panel.statusIconsTestModeCB then
    panel.statusIconsTestModeCB:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3766:53");
        if type(_G.MSUF_SetStatusIconsTestMode) == "function" then
            _G.MSUF_SetStatusIconsTestMode(self:GetChecked() and true or false, "OPTIONS")
        else
            EnsureDB()
            MSUF_DB.general = MSUF_DB.general or {}
            MSUF_DB.general.stateIconsTestMode = self:GetChecked() and true or false
        end

        MSUF_ApplyStatusIconsUI()

        -- Force-refresh both frames so previews update immediately.
        for _, k in ipairs({ "player", "target" }) do
            MSUF_RequestStatusIconRefresh(k)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3766:53"); end)

    panel.statusIconsTestModeCB:HookScript("OnShow", MSUF_ApplyStatusIconsUI)
    panel.statusIconsTestModeCB:HookScript("OnEnter", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3784:54");
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Status icons test mode")
            GameTooltip:AddLine("Shows enabled status icons even if the real state is not active.", 1, 1, 1)
            GameTooltip:AddLine("Useful for positioning/offset testing.", 1, 1, 1)
            GameTooltip:Show()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3784:54"); end)
    panel.statusIconsTestModeCB:HookScript("OnLeave", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3793:54"); if GameTooltip then GameTooltip:Hide() end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3793:54"); end)
end

-- Ensure setter exists (some patches call this as a global helper).
if type(_G.MSUF_SetStatusIconStyleUseMidnight) ~= "function" then
    function _G.MSUF_SetStatusIconStyleUseMidnight(useMidnight) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_SetStatusIconStyleUseMidnight file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3798:4");
        if type(_G.EnsureDB) == "function" then
            _G.EnsureDB()
        end
        local db = _G.MSUF_DB
        if type(db) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SetStatusIconStyleUseMidnight file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3798:4"); return end
        if type(db.general) ~= "table" then db.general = {} end
        db.general.statusIconsUseMidnightStyle = (useMidnight == true)

        -- Refresh player/target so icons update immediately.
        if type(_G.MSUF_UnitFrames) == "table" and type(_G.UpdateSimpleUnitFrame) == "function" then
            for _, k in ipairs({ "player", "target" }) do
                local fr = _G.MSUF_UnitFrames[k]
                if fr then
                    pcall(_G.UpdateSimpleUnitFrame, fr, true)
                end
            end
        end

        if type(_G.MSUF_RequestStatusIconsRefreshForCurrent) == "function" then
            pcall(_G.MSUF_RequestStatusIconsRefreshForCurrent)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SetStatusIconStyleUseMidnight file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3798:4"); end
end

-- Local alias for convenience (older code calls without _G prefix)
MSUF_SetStatusIconStyleUseMidnight = _G.MSUF_SetStatusIconStyleUseMidnight

-- Global icon style toggle (Classic vs Midnight) affects the symbol dropdown icon previews.
if panel.statusIconsStyleCB then
    panel.statusIconsStyleCB:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3828:50");
        local useMidnight = self:GetChecked() and true or false
        MSUF_SetStatusIconStyleUseMidnight(useMidnight)

        -- Re-apply UI so dropdown texts sync (and the checkbox stays consistent on both pages).
        MSUF_ApplyStatusIconsUI()

        -- Refresh both frames so any live symbol render (when implemented) will update immediately.
        for _, k in ipairs({ "player", "target" }) do
            MSUF_RequestStatusIconRefresh(k)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3828:50"); end)
end



-- Allow other UI locations (Edit Mode checkbox) to request a live refresh of this section.
_G.MSUF_RefreshStatusIconsOptionsUI = MSUF_ApplyStatusIconsUI

-- ToT inline-in-Target toggle (stored under MSUF_DB.targettarget)
if panel.totShowInTargetCB then
    panel.totShowInTargetCB:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3849:49");
        EnsureDB()
        EnsureKeyDB()
        MSUF_DB.targettarget = MSUF_DB.targettarget or {}
        MSUF_DB.targettarget.showToTInTargetName = self:GetChecked() and true or false
        ApplyLayoutCurrent("TOTINLINE_TOGGLE")
        if type(_G.MSUF_UpdateTargetToTInlineNow) == "function" then
            _G.MSUF_UpdateTargetToTInlineNow()
        end

        -- Keep separator dropdown greyed/active in sync with the toggle.
        if panel.totInlineSeparatorDD then
            local enabled = (MSUF_DB and MSUF_DB.targettarget and MSUF_DB.targettarget.showToTInTargetName == true)
            if UIDropDownMenu_EnableDropDown and UIDropDownMenu_DisableDropDown then
                if enabled then UIDropDownMenu_EnableDropDown(panel.totInlineSeparatorDD) else UIDropDownMenu_DisableDropDown(panel.totInlineSeparatorDD) end
            elseif panel.totInlineSeparatorDD.Button then
                if enabled and panel.totInlineSeparatorDD.Button.Enable then panel.totInlineSeparatorDD.Button:Enable() end
                if (not enabled) and panel.totInlineSeparatorDD.Button.Disable then panel.totInlineSeparatorDD.Button:Disable() end
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3849:49"); end)
end

-- ToT-inline separator dropdown (target-only).
if panel.totInlineSeparatorDD and UIDropDownMenu_Initialize then
    local drop = panel.totInlineSeparatorDD

    local function EnsureToTConf() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureToTConf file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3876:10");
        EnsureDB()
        if not MSUF_DB then Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureToTConf file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3876:10"); return nil end
        if type(MSUF_DB.targettarget) ~= "table" then MSUF_DB.targettarget = {} end
        -- Migration fallback: some older builds may have stored the value under target.
        if MSUF_DB.targettarget.totInlineSeparator == nil and type(MSUF_DB.target) == "table" and type(MSUF_DB.target.totInlineSeparator) == "string" then
            MSUF_DB.targettarget.totInlineSeparator = MSUF_DB.target.totInlineSeparator
        end
        MSUF_DB.targettarget.totInlineSeparator = MSUF_ToTInlineSepTokenText(MSUF_DB.targettarget.totInlineSeparator)
        return Perfy_Trace_Passthrough("Leave", "EnsureToTConf file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3876:10", MSUF_DB.targettarget)
    end

    local function OnSelect(btn, arg1) Perfy_Trace(Perfy_GetTime(), "Enter", "OnSelect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3888:10");
        local conf = EnsureToTConf()
        if not conf then Perfy_Trace(Perfy_GetTime(), "Leave", "OnSelect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3888:10"); return end
        local value = (btn and btn.value) or arg1 or "|"
        value = MSUF_ToTInlineSepTokenText(value)
        conf.totInlineSeparator = value

        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(drop, value) end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(drop, value) end
        if CloseDropDownMenus then CloseDropDownMenus() end

        -- Targeted live refresh (coalesced entry point if available).
        if type(_G.MSUF_ToTInline_RequestRefresh) == "function" then
            _G.MSUF_ToTInline_RequestRefresh("TOTINLINE_SEP")
        elseif type(_G.MSUF_UpdateTargetToTInlineNow) == "function" then
            _G.MSUF_UpdateTargetToTInlineNow()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "OnSelect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3888:10"); end

    UIDropDownMenu_Initialize(drop, function(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3907:36");
        if not level or level ~= 1 then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3907:36"); return end
        local conf = EnsureToTConf()
        local cur = conf and conf.totInlineSeparator

        for _, opt in ipairs(MSUF_TOTINLINE_SEP_OPTIONS) do
            local v = opt.value
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.value = v
            info.arg1 = v
            info.func = OnSelect
            info.checked = function() Perfy_Trace(Perfy_GetTime(), "Enter", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3919:27"); return Perfy_Trace_Passthrough("Leave", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3919:27", (cur == v)) end
            UIDropDownMenu_AddButton(info, level)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3907:36"); end)
end


    -- Checkboxes
    local function HookCheck(cb, field) Perfy_Trace(Perfy_GetTime(), "Enter", "HookCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3927:10");
        if not cb then Perfy_Trace(Perfy_GetTime(), "Leave", "HookCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3927:10"); return end
        cb:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3929:32");
            if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3929:32"); return end
            local conf = EnsureKeyDB()
            conf[field] = self:GetChecked() and true or false
            ApplyCurrent()
            if type(_G.MSUF_SyncUnitPositionPopup) == "function" then
                _G.MSUF_SyncUnitPositionPopup(CurrentKey(), conf)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3929:32"); end)
    Perfy_Trace(Perfy_GetTime(), "Leave", "HookCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3927:10"); end

    local _basicChecks = {
        {"playerEnableFrameCB", "enabled"},
        {"playerShowNameCB",    "showName"},
        {"playerShowHPCB",      "showHP"},
        {"playerShowPowerCB",   "showPower"},
        {"playerReverseFillBarsCB", "reverseFillBars"},
    }
    for i = 1, #_basicChecks do
        local wKey, field = _basicChecks[i][1], _basicChecks[i][2]
        HookCheck(panel[wKey], field)
    end


    
-- Castbar toggles (Enable / Time / Interrupt / Icon / Text)
local function _MSUF_SetCastTimeTextVisible(bar, show) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_SetCastTimeTextVisible file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3955:6");
    if not bar or not bar.timeText then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetCastTimeTextVisible file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3955:6"); return end
    if show then
        bar.timeText:Show()
        bar.timeText:SetAlpha(1)
    else
        bar.timeText:SetText("")
        bar.timeText:Show()
        bar.timeText:SetAlpha(0)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetCastTimeTextVisible file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3955:6"); end

local function _MSUF_ClearInterruptFeedback(bar) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_ClearInterruptFeedback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3967:6");
    if not bar or not bar.interruptFeedbackEndTime then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_ClearInterruptFeedback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3967:6"); return end
    bar.interruptFeedbackEndTime = nil
    if bar.castText then bar.castText:SetText("") end
    if bar.timeText then bar.timeText:SetText("") end
    bar:Hide()
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_ClearInterruptFeedback file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3967:6"); end

local function _MSUF_ClearInterruptFeedback_Boss() Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_ClearInterruptFeedback_Boss file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3975:6");
    local frames = _G.MSUF_BossCastbars
    if not frames then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_ClearInterruptFeedback_Boss file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3975:6"); return end
    for i = 1, #frames do
        local b = frames[i]
        if b and b.interruptFeedbackEndTime then
            b.interruptFeedbackEndTime = nil
            if b.castText then b.castText:SetText("") end
            if b.timeText then b.timeText:SetText("") end
            b:Hide()
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_ClearInterruptFeedback_Boss file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3975:6"); end

local function _MSUF_ForceRefreshCastbarIfCasting(bar, unitToken) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_ForceRefreshCastbarIfCasting file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3989:6");
    if not bar or not bar.Cast then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_ForceRefreshCastbarIfCasting file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3989:6"); return end
    local casting = (UnitCastingInfo and UnitCastingInfo(unitToken)) or (UnitChannelInfo and UnitChannelInfo(unitToken))
    if casting then
        pcall(bar.Cast, bar)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_ForceRefreshCastbarIfCasting file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:3989:6"); end

local CASTBAR_HANDLER_SPECS = {
    player = {
        requireKey = nil, -- keep legacy behavior (no CurrentKey check)
        enableW = "playerCastbarEnableCB", enableK = "enablePlayerCastbar",
        timeW   = "playerCastbarTimeCB",   timeK   = "showPlayerCastTime",
        interruptW = "playerCastbarInterruptCB",
        iconW = "playerCastbarShowIconCB", iconK = "castbarPlayerShowIcon",
        textW = "playerCastbarShowTextCB", textK = "castbarPlayerShowSpellName",
        bar = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4005:14"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4005:14", _G.MSUF_PlayerCastbar) end,
        reanchor = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4006:19"); if _G.MSUF_ReanchorPlayerCastBar then _G.MSUF_ReanchorPlayerCastBar() end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4006:19"); end,
        preview  = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4007:19"); if _G.MSUF_PositionPlayerCastbarPreview then _G.MSUF_PositionPlayerCastbarPreview() end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4007:19"); end,
    },
    target = {
        requireKey = "target",
        enableW = "targetCastbarEnableCB", enableK = "enableTargetCastbar",
        timeW   = "targetCastbarTimeCB",   timeK   = "showTargetCastTime",
        interruptW = "targetCastbarInterruptCB",
        iconW = "targetCastbarShowIconCB", iconK = "castbarTargetShowIcon",
        textW = "targetCastbarShowTextCB", textK = "castbarTargetShowSpellName",
        bar = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4016:14"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4016:14", _G.MSUF_TargetCastbar) end,
        reanchor = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4017:19"); if _G.MSUF_ReanchorTargetCastBar then _G.MSUF_ReanchorTargetCastBar() end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4017:19"); end,
        preview  = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4018:19"); if _G.MSUF_PositionTargetCastbarPreview then _G.MSUF_PositionTargetCastbarPreview() end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4018:19"); end,
        forceRefreshUnit = "target",
    },
    focus = {
        requireKey = "focus",
        enableW = "focusCastbarEnableCB", enableK = "enableFocusCastbar",
        timeW   = "focusCastbarTimeCB",   timeK   = "showFocusCastTime",
        interruptW = "focusCastbarInterruptCB",
        iconW = "focusCastbarShowIconCB", iconK = "castbarFocusShowIcon",
        textW = "focusCastbarShowTextCB", textK = "castbarFocusShowSpellName",
        bar = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4028:14"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4028:14", _G.MSUF_FocusCastbar) end,
        reanchor = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4029:19"); if _G.MSUF_ReanchorFocusCastBar then _G.MSUF_ReanchorFocusCastBar() end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4029:19"); end,
        preview  = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4030:19"); if _G.MSUF_PositionFocusCastbarPreview then _G.MSUF_PositionFocusCastbarPreview() end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4030:19"); end,
        forceRefreshUnit = "focus",
    },
    boss = {
        requireKey = "boss",
        enableW = "bossCastbarEnableCB", enableK = "enableBossCastbar",
        timeW   = "bossCastbarTimeCB",   timeK   = "showBossCastTime",
        interruptW = "bossCastbarInterruptCB",
        iconW = "bossCastbarShowIconCB", iconK = "showBossCastIcon",
        textW = "bossCastbarShowTextCB", textK = "showBossCastName",
        bar = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4040:14"); Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4040:14"); return nil end,
        reanchor = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4041:19"); Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4041:19"); end,
        preview  = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4042:19"); Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4042:19"); end,
    },
}


local function _MSUF_BindCastbarGeneralToggle(spec, widgetKey, dbKey, onBoss, onNormal) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_BindCastbarGeneralToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4047:6");
    local w = panel[widgetKey]
    if not w then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BindCastbarGeneralToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4047:6"); return end
    w:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4050:27");
        if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4050:27"); return end
        if spec.requireKey and CurrentKey() ~= spec.requireKey then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4050:27"); return end
        MSUF_EnsureDB_IfPossible(api)
        MSUF_DB = MSUF_DB or {}
        MSUF_DB.general = MSUF_DB.general or {}
        local g = MSUF_DB.general
        g[dbKey] = self:GetChecked() and true or false
        if spec.requireKey == "boss" then
            if onBoss then onBoss(spec, g) end
        else
            if onNormal then onNormal(spec, g) end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4050:27"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BindCastbarGeneralToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4047:6"); end

local function _MSUF_BossRefreshCastbarLayout() Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_BossRefreshCastbarLayout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4066:6");
    if type(_G.MSUF_RefreshBossCastbarLayout) == "function" then _G.MSUF_RefreshBossCastbarLayout() end
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BossRefreshCastbarLayout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4066:6"); end

local function _MSUF_BossApplyTimeAndLayout() Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_BossApplyTimeAndLayout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4070:6");
    if type(_G.MSUF_ApplyBossCastbarTimeSetting) == "function" then _G.MSUF_ApplyBossCastbarTimeSetting() end
    _MSUF_BossRefreshCastbarLayout()
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BossApplyTimeAndLayout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4070:6"); end

local function _MSUF_NonBossVisualRefresh(spec) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_NonBossVisualRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4075:6");
    if _G.MSUF_UpdateCastbarVisuals then _G.MSUF_UpdateCastbarVisuals() end
    spec.reanchor()
    spec.preview()
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_NonBossVisualRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4075:6"); end

local function _MSUF_NonBossTimeRefresh(spec, g) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_NonBossTimeRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4081:6");
    _MSUF_SetCastTimeTextVisible(spec.bar(), g[spec.timeK] ~= false)
    spec.reanchor()
    spec.preview()
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_NonBossTimeRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4081:6"); end


local function _MSUF_BindCastbarEnable(spec) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_BindCastbarEnable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4088:6");
    local w = panel[spec.enableW]
    if not w then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BindCastbarEnable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4088:6"); return end
    w:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4091:27");
        MSUF_EnsureCastbars()
        if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4091:27"); return end
        if spec.requireKey and CurrentKey() ~= spec.requireKey then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4091:27"); return end
        if api.EnsureDB then api.EnsureDB() end
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general[spec.enableK] = self:GetChecked() and true or false

        -- Boss castbars have a dedicated enable pipeline.
        if spec.requireKey == "boss" then
            if type(_G.MSUF_SetBossCastbarsEnabled) == "function" then
                _G.MSUF_SetBossCastbarsEnabled(MSUF_DB.general.enableBossCastbar ~= false)
            elseif type(_G.MSUF_ApplyBossCastbarsEnabled) == "function" then
                _G.MSUF_ApplyBossCastbarsEnabled()
            end
            if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then _G.MSUF_UpdateBossCastbarPreview() end
            if type(_G.MSUF_RefreshBossCastbarLayout) == "function" then _G.MSUF_RefreshBossCastbarLayout() end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4091:27"); return
        end

        spec.reanchor()
        spec.preview()

        -- If enabled while unit is already casting/channeling, force-refresh the bar immediately.
        if spec.forceRefreshUnit and MSUF_DB.general[spec.enableK] ~= false then
            _MSUF_ForceRefreshCastbarIfCasting(spec.bar(), spec.forceRefreshUnit)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4091:27"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BindCastbarEnable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4088:6"); end

local function _MSUF_BindCastbarInterrupt(spec) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_BindCastbarInterrupt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4121:6");
    local w = panel[spec.interruptW]
    if not w then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BindCastbarInterrupt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4121:6"); return end
    w:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4124:27");
        if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4124:27"); return end
        if spec.requireKey and CurrentKey() ~= spec.requireKey then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4124:27"); return end
        local conf = EnsureKeyDB()
        conf.showInterrupt = self:GetChecked() and true or false

        -- If disabled while interrupt feedback is showing, hide immediately.
        if conf.showInterrupt == false then
            if spec.requireKey == "boss" then
                _MSUF_ClearInterruptFeedback_Boss()
            else
                _MSUF_ClearInterruptFeedback(spec.bar())
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4124:27"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BindCastbarInterrupt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4121:6"); end

for _, spec in pairs(CASTBAR_HANDLER_SPECS) do
    _MSUF_BindCastbarEnable(spec)
    _MSUF_BindCastbarInterrupt(spec)

    _MSUF_BindCastbarGeneralToggle(spec, spec.iconW, spec.iconK, _MSUF_BossRefreshCastbarLayout, _MSUF_NonBossVisualRefresh)
    _MSUF_BindCastbarGeneralToggle(spec, spec.textW, spec.textK, _MSUF_BossRefreshCastbarLayout, _MSUF_NonBossVisualRefresh)
    _MSUF_BindCastbarGeneralToggle(spec, spec.timeW, spec.timeK, _MSUF_BossApplyTimeAndLayout, _MSUF_NonBossTimeRefresh)
end

-- Indicator live refresh (spec-driven)
-- Keep this lean: Options-time refresh only, and we rely on core layout helpers when present.
local MSUF_ALL_UF_TOKENS = { "player","target","focus","pet","tot","targettarget","boss1","boss2","boss3","boss4","boss5" }

local function MSUF_GetUnitFrameToken(unitToken) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetUnitFrameToken file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4154:6");
    local uf = _G.MSUF_UnitFrames or _G.UnitFrames
    if uf and uf[unitToken] then return Perfy_Trace_Passthrough("Leave", "MSUF_GetUnitFrameToken file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4154:6", uf[unitToken]) end
    -- Some builds only store ToT under one key; try common aliases
    if unitToken == "tot" and uf and uf.targettarget then return Perfy_Trace_Passthrough("Leave", "MSUF_GetUnitFrameToken file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4154:6", uf.targettarget) end
    if unitToken == "targettarget" and uf and uf.tot then return Perfy_Trace_Passthrough("Leave", "MSUF_GetUnitFrameToken file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4154:6", uf.tot) end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetUnitFrameToken file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4154:6"); return nil
end

local function MSUF_RefreshFrames(unitList, applyLayoutFnName) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_RefreshFrames file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4163:6");
    local update = _G.UpdateSimpleUnitFrame
    local applyLayout = applyLayoutFnName and _G[applyLayoutFnName] or nil

    for i = 1, #unitList do
        local f = MSUF_GetUnitFrameToken(unitList[i])
        if f then
            if update then pcall(update, f) end
            if applyLayout then pcall(applyLayout, f) end
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RefreshFrames file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4163:6"); end

-- Leader icon offsets + size/anchor live refresh (player + target)
MSUF_RefreshLeaderIconFrames = function() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_RefreshLeaderIconFrames file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4177:31");
    MSUF_RefreshFrames({ "player", "target" }, "MSUF_ApplyLeaderIconLayout")
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RefreshLeaderIconFrames file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4177:31"); end

-- Raid marker offset/anchor/size (per-unit): live update
MSUF_RefreshRaidMarkerFrames = function() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_RefreshRaidMarkerFrames file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4182:31");
    MSUF_RefreshFrames(MSUF_ALL_UF_TOKENS, "MSUF_ApplyRaidMarkerLayout")
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RefreshRaidMarkerFrames file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4182:31"); end

-- Level indicator offset/anchor (per-unit): live update
MSUF_RefreshLevelIndicatorFrames = function() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_RefreshLevelIndicatorFrames file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4187:35");
    MSUF_RefreshFrames(MSUF_ALL_UF_TOKENS, "MSUF_ApplyLevelIndicatorLayout")
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RefreshLevelIndicatorFrames file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4187:35"); end





    -- Portrait dropdown (all unitframes) [spec-driven]
    MSUF_BindPortraitDropdown(panel, "playerPortraitDropDown", IsFramesTab, EnsureKeyDB, ApplyCurrent)



-- Unit Alpha + Boss spacing sliders [spec-driven]

-- Alpha slider target routing:
-- Legacy keys: alphaInCombat / alphaOutOfCombat
-- Layered keys (when alphaExcludeTextPortrait == true):
--   Foreground: alphaFGInCombat / alphaFGOutOfCombat
--   Background: alphaBGInCombat / alphaBGOutOfCombat
local function MSUF_Alpha_NormalizeMode(mode) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_Alpha_NormalizeMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4207:6");
    -- IMPORTANT: Some DB sanitizers keep only numbers/bools.
    -- Accept both the legacy string modes and a compact numeric/bool encoding.
    --   background: true / 1 / "background"
    --   foreground: false / 0 / "foreground" (default)
    if mode == true or mode == 1 or mode == "background" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Alpha_NormalizeMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4207:6"); return "background"
    end
    if mode == false or mode == 0 or mode == "foreground" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Alpha_NormalizeMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4207:6"); return "foreground"
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Alpha_NormalizeMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4207:6"); return "foreground"
end

local function MSUF_Alpha_GetKeysForMode(conf, mode) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_Alpha_GetKeysForMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4221:6");
    mode = MSUF_Alpha_NormalizeMode(mode)
    local layered = (conf and conf.alphaExcludeTextPortrait == true)
    if layered then
        if mode == "background" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Alpha_GetKeysForMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4221:6"); return "alphaBGInCombat", "alphaBGOutOfCombat"
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Alpha_GetKeysForMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4221:6"); return "alphaFGInCombat", "alphaFGOutOfCombat"
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Alpha_GetKeysForMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4221:6"); return "alphaInCombat", "alphaOutOfCombat"
end

local function MSUF_Alpha_ReadPair(conf, mode) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_Alpha_ReadPair file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4233:6");
    if not conf then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Alpha_ReadPair file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4233:6"); return 1, 1 end
    mode = MSUF_Alpha_NormalizeMode(mode)

    local aInLegacy  = tonumber(conf.alphaInCombat) or 1
    local aOutLegacy = tonumber(conf.alphaOutOfCombat) or 1

    local aIn, aOut = aInLegacy, aOutLegacy
    if conf.alphaExcludeTextPortrait == true then
        if mode == "background" then
            aIn  = tonumber(conf.alphaBGInCombat) or aInLegacy
            aOut = tonumber(conf.alphaBGOutOfCombat) or aOutLegacy
        else
            aIn  = tonumber(conf.alphaFGInCombat) or aInLegacy
            aOut = tonumber(conf.alphaFGOutOfCombat) or aOutLegacy
        end
    end

    if conf.alphaSync == true then
        aOut = aIn
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Alpha_ReadPair file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4233:6"); return aIn, aOut
end

local function MSUF_Alpha_WritePair(conf, mode, aIn, aOut) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_Alpha_WritePair file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4257:6");
    if not conf then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Alpha_WritePair file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4257:6"); return end
    mode = MSUF_Alpha_NormalizeMode(mode)
    local kIn, kOut = MSUF_Alpha_GetKeysForMode(conf, mode)
    conf[kIn] = aIn
    conf[kOut] = aOut
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Alpha_WritePair file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4257:6"); end

local function MSUF_AlphaUI_SetSlider(slider, v) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_AlphaUI_SetSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4265:6");
    if slider and slider.SetValue then
        slider.MSUF_SkipCallback = true
        slider:SetValue(v)
        slider.MSUF_SkipCallback = false
        if slider.editBox then ForceSliderEditBox(slider) end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_AlphaUI_SetSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4265:6"); end

local function MSUF_AlphaUI_RefreshSliders() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_AlphaUI_RefreshSliders file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4274:6");
    if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_AlphaUI_RefreshSliders file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4274:6"); return end
    local conf = EnsureKeyDB()
    local mode = MSUF_Alpha_NormalizeMode(conf.alphaLayerMode)
    local aIn, aOut = MSUF_Alpha_ReadPair(conf, mode)
    MSUF_AlphaUI_SetSlider(panel.playerAlphaInCombatSlider, aIn)
    MSUF_AlphaUI_SetSlider(panel.playerAlphaOutCombatSlider, aOut)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_AlphaUI_RefreshSliders file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4274:6"); end

local function ApplyAlphaOnly() Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyAlphaOnly file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4283:6");
    local fn = (_G and _G.MSUF_RefreshAllUnitAlphas) or MSUF_RefreshAllUnitAlphas
    if type(fn) == "function" then pcall(fn) end
Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyAlphaOnly file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4283:6"); end

-- Alpha sync checkbox
if panel.playerAlphaSyncCB then
    panel.playerAlphaSyncCB:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4290:49");
        if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4290:49"); return end
        local conf = EnsureKeyDB()
        conf.alphaSync = self:GetChecked() and true or false

        local mode = MSUF_Alpha_NormalizeMode(conf.alphaLayerMode)
        local aIn, aOut = MSUF_Alpha_ReadPair(conf, mode)

        if conf.alphaSync == true then
            aOut = aIn
            MSUF_Alpha_WritePair(conf, mode, aIn, aOut)
        end

        MSUF_AlphaUI_RefreshSliders()
        ApplyAlphaOnly()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4290:49"); end)
end

-- Alpha: keep text/portrait visible (layered alpha enable)
if panel.playerAlphaExcludeTextPortraitCB then
    panel.playerAlphaExcludeTextPortraitCB:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4310:64");
        if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4310:64"); return end
        local conf = EnsureKeyDB()
        local on = self:GetChecked() and true or false
        conf.alphaExcludeTextPortrait = on
        -- Default to foreground in layered mode.
        if on and (conf.alphaLayerMode == nil) then
            -- Store as number to survive DB sanitizers.
            conf.alphaLayerMode = 0
        end

        -- Toggle dropdown enabled state immediately
        local dd = panel.playerAlphaLayerDropDown
        if dd then
            local btn = (_G and _G["MSUF_UF_AlphaLayerDropDownButton"]) or (dd and dd.Button)
            if btn and btn.Enable and btn.Disable then
                if on then btn:Enable() else btn:Disable() end
            end
            if dd.Text and dd.Text.SetTextColor then
                if on then dd.Text:SetTextColor(1, 1, 1) else dd.Text:SetTextColor(0.5, 0.5, 0.5) end
            end
        end

        MSUF_AlphaUI_RefreshSliders()
        ApplyAlphaOnly()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4310:64"); end)
end

-- Alpha layer dropdown
if panel.playerAlphaLayerDropDown and UIDropDownMenu_Initialize then
    UIDropDownMenu_Initialize(panel.playerAlphaLayerDropDown, function(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4340:62");
        if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4340:62"); return end
        local conf = EnsureKeyDB()
        local excludeOn = (conf.alphaExcludeTextPortrait == true)

        -- Ensure the dropdown shows the current DB value immediately (even after /reload).
        local _curMode = MSUF_Alpha_NormalizeMode(conf.alphaLayerMode)
        if UIDropDownMenu_SetSelectedValue then
            UIDropDownMenu_SetSelectedValue(panel.playerAlphaLayerDropDown, _curMode)
        end
        if UIDropDownMenu_SetText then
            UIDropDownMenu_SetText(panel.playerAlphaLayerDropDown, (_curMode == "background") and "Background" or "Foreground")
        end
        local _ddText = (_G and _G["MSUF_UF_AlphaLayerDropDownText"]) or (panel.playerAlphaLayerDropDown and panel.playerAlphaLayerDropDown.Text)
        if _ddText and _ddText.SetText then
            _ddText:SetText((_curMode == "background") and "Background" or "Foreground")
        end

        local function AddItem(value, text) Perfy_Trace(Perfy_GetTime(), "Enter", "AddItem file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4358:14");
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.checked = function() Perfy_Trace(Perfy_GetTime(), "Enter", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4362:27");
                return Perfy_Trace_Passthrough("Leave", "info.checked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4362:27", MSUF_Alpha_NormalizeMode(conf.alphaLayerMode) == value)
            end
            info.disabled = (excludeOn ~= true)
            info.func = function() Perfy_Trace(Perfy_GetTime(), "Enter", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4366:24");
                if not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4366:24"); return end
                local c = EnsureKeyDB()
                -- Store as number to survive DB sanitizers.
                c.alphaLayerMode = (value == "background") and 1 or 0
                UIDropDownMenu_SetSelectedValue(panel.playerAlphaLayerDropDown, value)
                UIDropDownMenu_SetText(panel.playerAlphaLayerDropDown, text)
                CloseDropDownMenus()
                MSUF_AlphaUI_RefreshSliders()
                ApplyAlphaOnly()
            Perfy_Trace(Perfy_GetTime(), "Leave", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4366:24"); end
            UIDropDownMenu_AddButton(info, level)
        Perfy_Trace(Perfy_GetTime(), "Leave", "AddItem file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4358:14"); end

        AddItem("foreground", "Foreground")
        AddItem("background", "Background")
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4340:62"); end)
end

local function BindAlphaSlider(spec) Perfy_Trace(Perfy_GetTime(), "Enter", "BindAlphaSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4385:6");
    local s = panel[spec.field]
    if not s then Perfy_Trace(Perfy_GetTime(), "Leave", "BindAlphaSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4385:6"); return end
    s.onValueChanged = function(self, value) Perfy_Trace(Perfy_GetTime(), "Enter", "s.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4388:23");
        if self.MSUF_SkipCallback or not IsFramesTab() then Perfy_Trace(Perfy_GetTime(), "Leave", "s.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4388:23"); return end
        local conf = EnsureKeyDB()
        local mode = MSUF_Alpha_NormalizeMode(conf.alphaLayerMode)

        local v = tonumber(value) or 1
        if v < 0 then v = 0 elseif v > 1 then v = 1 end

        local aIn, aOut = MSUF_Alpha_ReadPair(conf, mode)

        if spec.isInCombat then
            aIn = v
        else
            aOut = v
        end

        if conf.alphaSync == true then
            aOut = aIn
            local other = panel[spec.otherField]
            MSUF_AlphaUI_SetSlider(other, aOut)
        end

        MSUF_Alpha_WritePair(conf, mode, aIn, aOut)
        ApplyAlphaOnly()
    Perfy_Trace(Perfy_GetTime(), "Leave", "s.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4388:23"); end
    if s.HookScript then s:HookScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4413:48"); ForceSliderEditBox(s) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4413:48"); end) end
Perfy_Trace(Perfy_GetTime(), "Leave", "BindAlphaSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4385:6"); end

for _, spec in ipairs(MSUF_ALPHA_SLIDER_SPECS) do
    BindAlphaSlider(spec)
end

-- Boss spacing slider (boss key only)
local bs = panel.playerBossSpacingSlider
if bs then
    bs.onValueChanged = function(self, value) Perfy_Trace(Perfy_GetTime(), "Enter", "bs.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4423:24");
        if not IsFramesTab() or CurrentKey() ~= "boss" then Perfy_Trace(Perfy_GetTime(), "Leave", "bs.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4423:24"); return end
        local conf = EnsureKeyDB()
        conf.spacing = math.floor((tonumber(value) or 0) + 0.5)
        ApplyCurrent()
    Perfy_Trace(Perfy_GetTime(), "Leave", "bs.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4423:24"); end
    if bs.HookScript then bs:HookScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4429:50"); ForceSliderEditBox(bs) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:4429:50"); end) end
end

-- Copy settings button (Player menu)
    MSUF_BindAllCopyButtons(panel)


    -- Text positioning controls removed (Text group is a placeholder only).

Perfy_Trace(Perfy_GetTime(), "Leave", "ns.MSUF_Options_Player_InstallHandlers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua:2983:0"); end

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Player.lua");