local addonName, addonNS = ...
local ns = (_G.MSUF_NS) or addonNS or {}
_G.MSUF_NS = ns

ns.L = ns.L or (_G.MSUF_L) or {}
local L = ns.L
if not getmetatable(L) then
    setmetatable(L, { __index = function(_, k) return k end })
end
local isEn = (ns and ns.LOCALE) == "enUS"
local function TR(v)
    if type(v) ~= "string" then return v end
    if isEn then return v end
    return L[v] or v
end

local floor, max, min = math.floor, math.max, math.min
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"
local MEDIA_BASE = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Symbols\\"

--------------------------------------------------------------------
-- Castbar LoD loader
--------------------------------------------------------------------
local function EnsureCastbars()
    if _G.MSUF_EnsureAddonLoaded then
        _G.MSUF_EnsureAddonLoaded("MidnightSimpleUnitFrames_Castbars")
        return
    end
    local loader = (_G.C_AddOns and _G.C_AddOns.LoadAddOn) or _G.LoadAddOn
    if type(loader) == "function" then pcall(loader, "MidnightSimpleUnitFrames_Castbars") end
end

--------------------------------------------------------------------
-- Search helper
--------------------------------------------------------------------
if _G.MSUF_Search_RegisterRoots then
    _G.MSUF_Search_RegisterRoots(
        { "player","target","targettarget","focus","pet","boss" },
        { "MSUF_FramesMenuScrollChild" }, "Frames")
end

--------------------------------------------------------------------
-- Numeric editbox helper
--------------------------------------------------------------------
local function SetNumericEB(edit, v)
    if not edit then return end
    if edit.HasFocus and edit:HasFocus() then return end
    local n = floor((tonumber(v) or 0) + 0.5)
    if edit.SetFontObject then edit:SetFontObject(GameFontHighlightSmall) end
    if edit.SetTextColor then edit:SetTextColor(1, 1, 1, 1) end
    if edit.SetNumber then edit:SetNumber(n) else edit:SetText(tostring(n)) end
    if edit.SetCursorPosition then edit:SetCursorPosition(0) end
end

--------------------------------------------------------------------
-- Anchor text helpers (shared by indicators + status icons)
--------------------------------------------------------------------
local ANCHOR_LABELS = {
    TOPLEFT = "Top left", TOPRIGHT = "Top right",
    BOTTOMLEFT = "Bottom left", BOTTOMRIGHT = "Bottom right",
    CENTER = "Center",
    NAMELEFT = "Left to player name", NAMERIGHT = "Right to player name",
}
local function AnchorText(v) return ANCHOR_LABELS[v] or "Top left" end

local function LevelAnchorText(v) return ANCHOR_LABELS[v] or "Right to player name" end

--------------------------------------------------------------------
-- Status icon symbol data
--------------------------------------------------------------------
local function GetStatusIconStyleMidnight()
    if _G.EnsureDB then _G.EnsureDB() end
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    return g and (g.statusIconsUseMidnightStyle == true)
end

local function StatusSymbolTexture(symbolKey)
    if type(symbolKey) ~= "string" or symbolKey == "" or symbolKey == "DEFAULT" then return nil end
    local mid = GetStatusIconStyleMidnight()
    local folder, suffix = "Combat", mid and "_midnight_128_clean.tga" or "_classic_128_clean.tga"
    if symbolKey:find("^rested_") then
        folder, suffix = "Rested", mid and "_midnight_64.tga" or "_classic_64.tga"
    elseif symbolKey:find("^resurrection_") then
        folder, suffix = "Ress", mid and "_midnight_64.tga" or "_classic_64.tga"
    end
    return MEDIA_BASE .. folder .. "\\" .. symbolKey .. suffix
end

local COMBAT_SYMBOLS = {
    { "Default","DEFAULT" },
    { "Axes","weapon_axes_crossed" },{ "Bows","weapon_bows_crossed" },
    { "Crossbows","weapon_crossbows_crossed" },{ "Daggers","weapon_daggers_crossed" },
    { "Fishing","weapon_fishing_poles_crossed" },{ "Fist","weapon_fist_crossed" },
    { "Guns","weapon_guns_crossed" },{ "Maces","weapon_maces_crossed" },
    { "Polearms","weapon_polearms_crossed" },{ "Shuriken","weapon_shuriken" },
    { "Staves","weapon_staves_crossed" },{ "Swords","weapon_swords_crossed" },
    { "Thorn","weapon_thrown_crossed" },{ "Wands","weapon_wands_crossed" },
    { "Warglaives","weapon_warglaives_crossed" },
}
local RESTED_SYMBOLS = {
    { "Default","DEFAULT" },
    { "Moon (3 z)","rested_moonzzz" },{ "Moon (4 z)","rested_moonzzzz" },
    { "Compact Zzz","rested_zzz_compact" },{ "Diagonal Zzz","rested_zzz_diag" },
    { "Stacked Zzz","rested_zzz_stack" },
}
local RESS_SYMBOLS = {
    { "Default","DEFAULT" },
    { "Ankh","resurrection_ankh" },{ "Cross","resurrection_cross" },
    { "Soul","resurrection_soul" },{ "Angelic Wings","resurrection_wings" },
}
local function FindSymbolLabel(key)
    if not key or key == "DEFAULT" then return "Default" end
    for _, tbl in ipairs({ COMBAT_SYMBOLS, RESTED_SYMBOLS, RESS_SYMBOLS }) do
        for i = 1, #tbl do
            if tbl[i][2] == key then return tbl[i][1] end
        end
    end
    return tostring(key)
end
local function SymbolChoices(tbl)
    local t = {}
    for i = 1, #tbl do t[i] = { tbl[i][1], tbl[i][2] } end
    return t
end

--------------------------------------------------------------------
-- DB read helpers
--------------------------------------------------------------------
local function ReadBool(conf, g, field, def)
    local v = conf and conf[field]
    if v == nil and g then v = g[field] end
    if v == nil then v = def end
    return (v ~= false)
end
local function ReadNum(conf, g, field, def)
    local v = conf and conf[field]
    if type(v) ~= "number" then v = nil end
    if v == nil and g then local gv = g[field]; if type(gv) == "number" then v = gv end end
    return v or def or 0
end
local function ReadStr(conf, g, field, def)
    local v = conf and conf[field]
    if type(v) ~= "string" then v = nil end
    if v == nil and g then local gv = g[field]; if type(gv) == "string" then v = gv end end
    return v or def or ""
end
local function ClampLayerValue(v, def)
    v = tonumber(v) or def or 7
    v = floor(v + 0.5)
    if v < 1 then return 1 end
    if v > 10 then return 10 end
    return v
end

--------------------------------------------------------------------
-- Indicator specs (Leader / RaidMarker / Level / Elite-Rare icon)
--------------------------------------------------------------------
local FOUR_ANCHORS = { "TOPLEFT","TOPRIGHT","BOTTOMLEFT","BOTTOMRIGHT" }
local function MakeAnchorChoices(list, textFn)
    local t = {}
    for i = 1, #list do t[i] = { textFn(list[i]), list[i] } end
    return t
end

local INDICATOR_SPECS = {
    leader = {
        id = "leader", order = 1,
        allowed = function(k) return k == "player" or k == "target" end,
        showCB = "playerLeaderIconCB", showField = "showLeaderIcon", showDefault = true,
        xStepper = "playerLeaderOffsetXStepper", xField = "leaderIconOffsetX", xDefault = 0,
        yStepper = "playerLeaderOffsetYStepper", yField = "leaderIconOffsetY", yDefault = 3,
        anchorDrop = "playerLeaderAnchorDrop", anchorField = "leaderIconAnchor", anchorDefault = "TOPLEFT",
        anchorText = AnchorText, anchorChoices = MakeAnchorChoices(FOUR_ANCHORS, AnchorText),
        sizeEdit = "playerLeaderSizeEdit", sizeField = "leaderIconSize", sizeDefault = 14,
        layerSlider = "playerLeaderLayerSlider", layerField = "leaderIconLayer", layerDefault = 7,
        divider = "playerLeaderGroupDivider", resetBtn = "playerLeaderResetBtn",
        refreshFnName = "MSUF_RefreshLeaderIconFrames",
    },
    raidmarker = {
        id = "raidmarker", order = 2,
        allowed = function() return true end,
        showCB = "playerRaidMarkerCB", showField = "showRaidMarker", showDefault = true,
        xStepper = "playerRaidMarkerOffsetXStepper", xField = "raidMarkerOffsetX", xDefault = 16,
        yStepper = "playerRaidMarkerOffsetYStepper", yField = "raidMarkerOffsetY", yDefault = 3,
        anchorDrop = "playerRaidMarkerAnchorDrop", anchorField = "raidMarkerAnchor", anchorDefault = "TOPLEFT",
        anchorText = AnchorText,
        anchorChoices = MakeAnchorChoices({ "TOPLEFT","TOPRIGHT","BOTTOMLEFT","BOTTOMRIGHT","CENTER" }, AnchorText),
        sizeEdit = "playerRaidMarkerSizeEdit", sizeField = "raidMarkerSize", sizeDefault = 18,
        layerSlider = "playerRaidMarkerLayerSlider", layerField = "raidMarkerLayer", layerDefault = 7,
        divider = "playerRaidMarkerGroupDivider", resetBtn = "playerRaidMarkerResetBtn",
        refreshFnName = "MSUF_RefreshRaidMarkerFrames",
    },
    level = {
        id = "level", order = 3,
        allowed = function() return true end,
        showCB = "playerLevelIndicatorCB", showField = "showLevelIndicator", showDefault = true,
        xStepper = "playerLevelOffsetXStepper", xField = "levelIndicatorOffsetX", xDefault = 0,
        yStepper = "playerLevelOffsetYStepper", yField = "levelIndicatorOffsetY", yDefault = 0,
        anchorDrop = "playerLevelAnchorDrop", anchorField = "levelIndicatorAnchor", anchorDefault = "NAMERIGHT",
        anchorText = LevelAnchorText,
        anchorChoices = MakeAnchorChoices({ "NAMERIGHT","NAMELEFT","TOPLEFT","TOPRIGHT","BOTTOMLEFT","BOTTOMRIGHT" }, LevelAnchorText),
        sizeEdit = "playerLevelSizeEdit", sizeField = "levelIndicatorSize", sizeDefault = 14,
        layerSlider = "playerLevelLayerSlider", layerField = "levelIndicatorLayer", layerDefault = 7,
        divider = "playerLevelGroupDivider", resetBtn = "playerLevelResetBtn",
        refreshFnName = "MSUF_RefreshLevelIndicatorFrames",
    },
    eliteicon = {
        id = "eliteicon", order = 4,
        allowed = function(k) return k == "target" or k == "focus" or k == "targettarget" or k == "boss" end,
        showCB = "playerEliteIconCB", showField = "showEliteIcon", showDefault = true,
        xStepper = "playerEliteIconOffsetXStepper", xField = "eliteIconOffsetX", xDefault = 2,
        yStepper = "playerEliteIconOffsetYStepper", yField = "eliteIconOffsetY", yDefault = 2,
        anchorDrop = "playerEliteIconAnchorDrop", anchorField = "eliteIconAnchor", anchorDefault = "TOPRIGHT",
        anchorText = AnchorText, anchorChoices = MakeAnchorChoices(FOUR_ANCHORS, AnchorText),
        sizeEdit = "playerEliteIconSizeEdit", sizeField = "eliteIconSize", sizeDefault = 20,
        layerSlider = "playerEliteIconLayerSlider", layerField = "eliteIconLayer", layerDefault = 7,
        divider = "playerEliteIconGroupDivider", resetBtn = "playerEliteIconResetBtn",
        refreshFnName = "MSUF_RefreshEliteIconFrames",
    },
}
local INDICATOR_ORDER = { "leader", "raidmarker", "level", "eliteicon" }

--------------------------------------------------------------------
-- Status icon specs (Combat / Rested / IncomingRes) — data-driven
--------------------------------------------------------------------
local STATUS_ICON_DEFS = {
    {
        prefix = "statusCombat", cbText = "Combat", rowIndex = 0,
        allowed = function(k) return k == "player" or k == "target" end,
        showField = "showCombatStateIndicator", showDefault = true,
        xField = "combatStateIndicatorOffsetX", yField = "combatStateIndicatorOffsetY",
        anchorField = "combatStateIndicatorAnchor", sizeField = "combatStateIndicatorSize", sizeDefault = 18,
        layerField = "combatStateIndicatorLayer", layerDefault = 7,
        symbolField = "combatStateIndicatorSymbol", symbolChoices = function() return SymbolChoices(COMBAT_SYMBOLS) end,
        refreshGlobal = "MSUF_RequestStatusCombatIndicatorRefresh",
        pickerTitle = "Combat icon",
    },
    {
        prefix = "statusResting", cbText = "Rested (player only)", rowIndex = 1,
        allowed = function(k) return k == "player" end,
        showField = "showRestingIndicator", showDefault = false,
        xField = "restedStateIndicatorOffsetX", yField = "restedStateIndicatorOffsetY",
        anchorField = "restedStateIndicatorAnchor", sizeField = "restedStateIndicatorSize", sizeDefault = 18,
        layerField = "restedStateIndicatorLayer", layerDefault = 7,
        symbolField = "restedStateIndicatorSymbol", symbolChoices = function() return SymbolChoices(RESTED_SYMBOLS) end,
        refreshGlobal = "MSUF_RequestStatusRestingIndicatorRefresh",
        pickerTitle = "Rested icon",
    },
    {
        prefix = "statusIncomingRes", cbText = "Incoming Rez", rowIndex = 2,
        allowed = function(k) return k == "player" or k == "target" end,
        showField = "showIncomingResIndicator", showDefault = true,
        xField = "incomingResIndicatorOffsetX", yField = "incomingResIndicatorOffsetY",
        anchorField = "incomingResIndicatorAnchor", sizeField = "incomingResIndicatorSize", sizeDefault = 18,
        layerField = "incomingResIndicatorLayer", layerDefault = 7,
        symbolField = "incomingResIndicatorSymbol", symbolChoices = function() return SymbolChoices(RESS_SYMBOLS) end,
        refreshGlobal = "MSUF_RequestStatusIncomingResIndicatorRefresh",
        pickerTitle = "Rez icon",
    },
}

-- Status icon widget field suffixes for bulk show/hide
local STATUS_WIDGET_SUFFIXES = {
    "IconCB","GroupDivider","ResetBtn","OffsetXStepper","OffsetYStepper",
    "AnchorDrop","AnchorLabel","SizeEdit","SizeLabel","LayerSlider","SymbolDrop","SymbolLabel",
}

--------------------------------------------------------------------
-- Portrait options
--------------------------------------------------------------------
local PORTRAIT_OPTIONS = {
    { value = "OFF", text = "Portrait Off" },
    { value = "LEFT", text = "Portrait Left" },
    { value = "RIGHT", text = "Portrait Right" },
}
local function PortraitText(m)
    if m == "LEFT" then return "Portrait Left" end
    if m == "RIGHT" then return "Portrait Right" end
    return "Portrait Off"
end
local function GetPortraitVal(conf)
    if not conf then return "OFF" end
    local pm = conf.portraitMode or "OFF"
    return (pm == "LEFT" or pm == "RIGHT") and pm or "OFF"
end

--------------------------------------------------------------------
-- Boss layout mode (vertical/horizontal ordering of boss1..8)
--------------------------------------------------------------------
local BOSS_LAYOUT_OPTIONS = {
    { value = "VERTICAL_DOWN",    text = "Vertical (top -> bottom)" },
    { value = "VERTICAL_UP",      text = "Vertical (bottom -> top)" },
    { value = "HORIZONTAL_RIGHT", text = "Horizontal (left -> right)" },
    { value = "HORIZONTAL_LEFT",  text = "Horizontal (right -> left)" },
}
local BOSS_LAYOUT_VALID = {
    VERTICAL_DOWN    = true,
    VERTICAL_UP      = true,
    HORIZONTAL_RIGHT = true,
    HORIZONTAL_LEFT  = true,
}
local function BossLayoutMode_Text(m)
    if m == "VERTICAL_UP"      then return "Vertical (bottom -> top)" end
    if m == "HORIZONTAL_RIGHT" then return "Horizontal (left -> right)" end
    if m == "HORIZONTAL_LEFT"  then return "Horizontal (right -> left)" end
    return "Vertical (top -> bottom)"
end
-- Normalize: accept new string values; fall back to legacy invertBossOrder; default VERTICAL_DOWN.
local function BossLayoutMode_Normalize(v, legacyInvert)
    if type(v) == "string" and BOSS_LAYOUT_VALID[v] then return v end
    if legacyInvert == true then return "VERTICAL_UP" end
    return "VERTICAL_DOWN"
end

--------------------------------------------------------------------
-- ToT inline separator
--------------------------------------------------------------------
local TOTSEP_OPTIONS = {
    { ".", "." },{ "-", "-" },{ "/", "/" },{ "\\", "\\" },{ "|", "|" },
    { "<<<", "<<<" },{ ">>>", ">>>" },{ "||", "||" },{ "", "" },
    { "--", "--" },{ ">", ">" },{ "<", "<" },
}
local TOTSEP_VALID = {}
for i = 1, #TOTSEP_OPTIONS do
    local v = TOTSEP_OPTIONS[i][1]
    if v ~= "" then TOTSEP_VALID[v] = true end
end
local function ToTSepText(v)
    if type(v) ~= "string" or v == "" or not TOTSEP_VALID[v] then return "|" end
    return v
end

--------------------------------------------------------------------
-- Alpha helpers (forward-declared, filled in InstallHandlers)
--------------------------------------------------------------------
local Alpha_NormalizeMode, Alpha_GetKeys, Alpha_ReadPair, Alpha_WritePair
local AlphaUI_SetSlider, AlphaUI_RefreshSliders

--------------------------------------------------------------------
-- Castbar spec tables
--------------------------------------------------------------------
local CASTBAR_TOGGLE_SPECS = {
    { key = "player", enableW = "playerCastbarEnableCB", enableK = "enablePlayerCastbar", timeW = "playerCastbarTimeCB", timeK = "showPlayerCastTime", interruptW = "playerCastbarInterruptCB" },
    { key = "target", enableW = "targetCastbarEnableCB", enableK = "enableTargetCastbar", timeW = "targetCastbarTimeCB", timeK = "showTargetCastTime", interruptW = "targetCastbarInterruptCB" },
    { key = "focus",  enableW = "focusCastbarEnableCB",  enableK = "enableFocusCastbar",  timeW = "focusCastbarTimeCB",  timeK = "showFocusCastTime",  interruptW = "focusCastbarInterruptCB" },
    { key = "boss",   enableW = "bossCastbarEnableCB",   enableK = "enableBossCastbar",   timeW = "bossCastbarTimeCB",   timeK = "showBossCastTime",   interruptW = "bossCastbarInterruptCB" },
}
local CASTBAR_TEXTICON_SPECS = {
    { key = "player", iconW = "playerCastbarShowIconCB", iconK = "castbarPlayerShowIcon", textW = "playerCastbarShowTextCB", textK = "castbarPlayerShowSpellName", textDirect = false },
    { key = "target", iconW = "targetCastbarShowIconCB", iconK = "castbarTargetShowIcon", textW = "targetCastbarShowTextCB", textK = "castbarTargetShowSpellName", textDirect = false },
    { key = "focus",  iconW = "focusCastbarShowIconCB",  iconK = "castbarFocusShowIcon",  textW = "focusCastbarShowTextCB",  textK = "castbarFocusShowSpellName",  textDirect = false },
    { key = "boss",   iconW = "bossCastbarShowIconCB",   iconK = "showBossCastIcon",      textW = "bossCastbarShowTextCB",   textK = "showBossCastName",           textDirect = true },
}

--------------------------------------------------------------------
-- Copy engine
--------------------------------------------------------------------
local COPY_BASIC_FIELDS = {
    "enabled","showName","showHP","showPower","reverseFillBars","smoothFill","powerSmoothFill","portraitMode",
    "alphaInCombat","alphaOutOfCombat","alphaSync",
    "alphaExcludeTextPortrait","alphaLayerMode",
    "alphaFGInCombat","alphaFGOutOfCombat","alphaBGInCombat","alphaBGOutOfCombat",
    "loadCondHideMounted","loadCondHideInVehicle","loadCondHideResting",
    "loadCondHideInCombat","loadCondHideOutOfCombat","loadCondHideStealthed",
    "loadCondHideSolo","loadCondHideInGroup","loadCondHideInInstance","loadCondActive",
}
local COPY_INDICATOR_FIELDS = {
    "showLeaderIcon","leaderIconOffsetX","leaderIconOffsetY","leaderIconAnchor","leaderIconSize","leaderIconLayer",
    "showRaidMarker","raidMarkerOffsetX","raidMarkerOffsetY","raidMarkerAnchor","raidMarkerSize","raidMarkerLayer",
    "showLevelIndicator","levelIndicatorOffsetX","levelIndicatorOffsetY","levelIndicatorAnchor","levelIndicatorSize","levelIndicatorLayer",
    "showEliteIcon","eliteIconSize","eliteIconAnchor","eliteIconOffsetX","eliteIconOffsetY","eliteIconLayer",
}
MSUF_COPY_STATUSICON_FIELDS = {
    "statusIconsTestMode","statusIconsMidnightStyle","statusIconsAlpha",
    "showCombatStateIndicator","showRestingIndicator","showIncomingResIndicator",
    "combatStateIndicatorOffsetX","combatStateIndicatorOffsetY","combatStateIndicatorAnchor",
    "combatStateIndicatorSize","combatStateIndicatorLayer","combatStateIndicatorSymbol",
    "restedStateIndicatorOffsetX","restedStateIndicatorOffsetY","restedStateIndicatorAnchor",
    "restedStateIndicatorSize","restedStateIndicatorLayer","restedStateIndicatorSymbol",
    "incomingResIndicatorOffsetX","incomingResIndicatorOffsetY","incomingResIndicatorAnchor",
    "incomingResIndicatorSize","incomingResIndicatorLayer","incomingResIndicatorSymbol",
}

local function CanonKey(k)
    if not k or type(k) ~= "string" then return k end
    k = k:lower()
    if k:match("^boss") then return "boss" end
    if k == "tot" or k == "targetoftarget" or k == "target_of_target" then return "targettarget" end
    return k
end

local function EnsureDB()
    if _G.EnsureDB then _G.EnsureDB()
    elseif _G.MSUF_EnsureDB then _G.MSUF_EnsureDB()
    end
end

local function EnsureUnitDB(key)
    MSUF_DB = MSUF_DB or {}
    local k = CanonKey(key)
    if not k then return nil, nil end
    if k == "targettarget" then
        MSUF_DB.targettarget = MSUF_DB.targettarget or MSUF_DB.tot or {}
        MSUF_DB.tot = MSUF_DB.targettarget
        return MSUF_DB.targettarget, k
    end
    MSUF_DB[k] = MSUF_DB[k] or {}
    return MSUF_DB[k], k
end

local function CopyFields(dst, src, fields)
    for i = 1, #fields do dst[fields[i]] = src[fields[i]] end
end

local function ReadPowerSmoothFill(conf, unitKey)
    if conf and conf.powerSmoothFill ~= nil then return conf.powerSmoothFill == true end
    if unitKey == "player" then
        local b = MSUF_DB and MSUF_DB.bars
        return not (b and b.smoothPowerBar == false)
    end
    return false
end

local CASTBAR_KEY_MAP = {
    player = { enable = "enablePlayerCastbar", time = "showPlayerCastTime", icon = "castbarPlayerShowIcon", name = "castbarPlayerShowSpellName" },
    target = { enable = "enableTargetCastbar", time = "showTargetCastTime", icon = "castbarTargetShowIcon", name = "castbarTargetShowSpellName" },
    focus  = { enable = "enableFocusCastbar",  time = "showFocusCastTime",  icon = "castbarFocusShowIcon",  name = "castbarFocusShowSpellName" },
    boss   = { enable = "enableBossCastbar",   time = "showBossCastTime",   icon = "showBossCastIcon",      name = "showBossCastName" },
}

local function CopyCastbar(g, src, dst)
    src, dst = CanonKey(src), CanonKey(dst)
    local s, d = CASTBAR_KEY_MAP[src], CASTBAR_KEY_MAP[dst]
    if not s or not d then return end
    g[d.enable] = g[s.enable]; g[d.time] = g[s.time]
    g[d.icon] = g[s.icon]; g[d.name] = g[s.name]
end

--------------------------------------------------------------------
-- Copy-To-All dialog
--------------------------------------------------------------------
local function EnsureCopyDialog()
    if not StaticPopupDialogs or StaticPopupDialogs["MSUF_COPY_TO_ALL_CONFIRM"] then return end
    StaticPopupDialogs["MSUF_COPY_TO_ALL_CONFIRM"] = {
        text = "Copy these settings to ALL unitframes?\n\nThis will overwrite existing settings on Player/Target/Focus/Boss/Pet/Target of Target.",
        button1 = YES or "Yes", button2 = NO or "No",
        OnAccept = function(_, data) if type(data) == "function" then data() end end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end
local function ConfirmCopyToAll(cb)
    if type(cb) ~= "function" then return end
    EnsureCopyDialog()
    if StaticPopup_Show then StaticPopup_Show("MSUF_COPY_TO_ALL_CONFIRM", nil, nil, cb) else cb() end
end
_G.MSUF_ConfirmCopyToAll = ConfirmCopyToAll

local function CopyUnitSettings(srcKey, destKey, api)
    EnsureDB()
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    srcKey = CanonKey(srcKey) or "player"
    destKey = type(destKey) == "string" and destKey:lower() or "target"
    local src, srcC = EnsureUnitDB(srcKey)
    if not src or not srcC then return end

    local function CopyOne(toKey)
        local dst, dstC = EnsureUnitDB(toKey)
        if not dst or not dstC or dstC == srcC then return end
        CopyFields(dst, src, COPY_BASIC_FIELDS)
        dst.powerSmoothFill = ReadPowerSmoothFill(src, srcC)
        CopyFields(dst, src, COPY_INDICATOR_FIELDS)
        CopyFields(dst, src, MSUF_COPY_STATUSICON_FIELDS)
        dst.showInterrupt = src.showInterrupt
        CopyCastbar(g, srcC, dstC)
        if api and api.ApplySettingsForKey then api.ApplySettingsForKey(dstC) end
    end

    if destKey == "all" then
        ConfirmCopyToAll(function()
            for _, k in ipairs({ "player","target","focus","boss","pet","targettarget" }) do
                if k ~= srcC then CopyOne(k) end
            end
            if _G.MSUF_UpdateCastbarVisuals then _G.MSUF_UpdateCastbarVisuals() end
            if _G.MSUF_RefreshAllIndicators then _G.MSUF_RefreshAllIndicators() end
        end)
        return
    end
    CopyOne(destKey)
    if _G.MSUF_UpdateCastbarVisuals then _G.MSUF_UpdateCastbarVisuals() end
    if _G.MSUF_RefreshAllIndicators then _G.MSUF_RefreshAllIndicators() end
end

--------------------------------------------------------------------
-- Widget creation helpers
--------------------------------------------------------------------
local function MkCheck(parent, name, label, x, y, maxW)
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local t = cb.Text or _G[name .. "Text"]
    if t then t:SetText(label) end
    if maxW and _G.MSUF_ClampCheckboxText then _G.MSUF_ClampCheckboxText(cb, maxW) end
    return cb
end

local function CBLabelLeft(cb, text)
    if not cb or not cb.Text then return end
    if text then cb.Text:SetText(TR(text)) end
    cb.Text:ClearAllPoints()
    cb.Text:SetPoint("RIGHT", cb, "LEFT", -4, 0)
    cb.Text:SetJustifyH("RIGHT")
end

local function CBLabelRight(cb, text)
    if not cb or not cb.Text then return end
    if text then cb.Text:SetText(TR(text)) end
    cb.Text:ClearAllPoints()
    cb.Text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.Text:SetJustifyH("LEFT")
end

local function MkGroupBox(parent, title, x, y, w, h)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(w, h)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    box:SetBackdropColor(0, 0, 0, 0.25)
    box:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)
    local tt = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tt:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -6)
    tt:SetText(title or "")
    local div = box:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -22)
    div:SetPoint("TOPRIGHT", box, "TOPRIGHT", -8, -22)
    div:SetHeight(1); div:SetColorTexture(1, 1, 1, 0.08)
    box._msufTitleText = tt; box._msufDivider = div
    return box
end

local function MkCollapsible(parent, title, w, expandedH, defaultOpen)
    local box = MkGroupBox(parent, title, 0, 0, w, defaultOpen and expandedH or 28)
    box:ClearAllPoints()
    box._msufExpandedH = expandedH
    box._msufCollapsedH = 28
    box._msufCollapsed = not defaultOpen

    local hdr = CreateFrame("Button", nil, box)
    hdr:SetHeight(24)
    hdr:SetPoint("TOPLEFT", 0, 0); hdr:SetPoint("TOPRIGHT", 0, 0)
    local chev = hdr:CreateTexture(nil, "OVERLAY")
    chev:SetSize(12, 12); chev:SetPoint("LEFT", hdr, "LEFT", 12, 0)
    chev:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    MSUF_ApplyCollapseVisual(chev, nil, defaultOpen)
    if box._msufTitleText then
        box._msufTitleText:ClearAllPoints()
        box._msufTitleText:SetPoint("LEFT", chev, "RIGHT", 6, 0)
    end
    local hint = hdr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("RIGHT", hdr, "RIGHT", -12, 0)
    hint:SetText(defaultOpen and "" or TR("click to expand"))
    hint:SetTextColor(0.45, 0.52, 0.65)
    if box._msufDivider then
        box._msufDivider:ClearAllPoints()
        box._msufDivider:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -28)
        box._msufDivider:SetPoint("TOPRIGHT", box, "TOPRIGHT", -8, -28)
    end
    local body = CreateFrame("Frame", nil, box)
    body:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -28)
    body:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    body:SetShown(defaultOpen)
    box._msufBody = body

    local function ApplyState()
        local open = not box._msufCollapsed
        body:SetShown(open)
        box:SetHeight(open and box._msufExpandedH or box._msufCollapsedH)
        MSUF_ApplyCollapseVisual(chev, hint, open)
        if type(box._msufOnCollapsedChanged) == "function" then pcall(box._msufOnCollapsedChanged, box, box._msufCollapsed) end
    end
    hdr:SetScript("OnClick", function() box._msufCollapsed = not box._msufCollapsed; ApplyState() end)
    hdr:SetScript("OnEnter", function() end)
    do local hl = hdr:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.03) end
    box._msufApplyCollapseState = ApplyState
    ApplyState()
    return box, body
end

local function ExpandDropdownClick(dd)
    if not dd or dd._msufClickAreaExpanded then return end
    dd._msufClickAreaExpanded = true
    local function Apply()
        local name = dd.GetName and dd:GetName()
        local btn = dd.Button or (name and _G[name .. "Button"])
        if not btn or not btn.SetHitRectInsets then return end
        local dw = tonumber(dd:GetWidth()) or 0
        local dh = tonumber(dd:GetHeight()) or 0
        local bw = tonumber(btn:GetWidth()) or 0
        local bh = tonumber(btn:GetHeight()) or 0
        if dw <= 1 and dd._msufDropWidth then dw = dd._msufDropWidth end
        if dw <= 1 or dh <= 1 or bw <= 1 or bh <= 1 then
            if C_Timer and C_Timer.After then C_Timer.After(0, Apply) end
            return
        end
        btn:SetHitRectInsets(-max(0, dw - bw) - 2, -2, -max(0, (dh - bh) / 2) - 2, -max(0, (dh - bh) / 2) - 2)
    end
    if dd.HookScript then dd:HookScript("OnShow", Apply); dd:HookScript("OnSizeChanged", Apply) end
    local name = dd.GetName and dd:GetName()
    local btn = dd.Button or (name and _G[name .. "Button"])
    if btn and btn.HookScript then btn:HookScript("OnSizeChanged", Apply) end
    if C_Timer and C_Timer.After then C_Timer.After(0, Apply) else Apply() end
end

local function MkStyledDD(name, parent, width)
    local dd = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown(name, parent)
        or CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate"))
    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(dd, width) end
    dd._msufDropWidth = width
    ExpandDropdownClick(dd)
    return dd
end

local function RestyleStepper(stepper)
    if not stepper then return end
    local eb, minus, plus = stepper.editBox, stepper.minusButton, stepper.plusButton
    if eb then eb:Hide(); eb:SetAlpha(0); eb:EnableMouse(false); eb:ClearAllPoints(); eb:SetPoint("TOPLEFT", stepper, "TOPLEFT", -2000, 0); eb:SetWidth(1) end
    if minus then minus:ClearAllPoints(); minus:SetPoint("LEFT", stepper, "LEFT", 0, 0) end
    if plus then plus:ClearAllPoints(); plus:SetPoint("LEFT", minus or stepper, "RIGHT", 2, 0) end
    local w = 46
    if minus and minus.GetWidth then w = (minus:GetWidth() or 22) + (plus and (plus:GetWidth() or 22) or 0) + 2 end
    stepper:SetWidth(w)
end

--------------------------------------------------------------------
-- Stepper modifier support
--------------------------------------------------------------------
local function GetGridStep()
    local step
    local s = _G["MSUF_EditModeGridSlider"]
    if s and s.GetValue then step = s:GetValue()
    elseif MSUF_DB and MSUF_DB.general and type(MSUF_DB.general.editModeGridStep) == "number" then step = MSUF_DB.general.editModeGridStep
    else step = 20 end
    step = tonumber(step) or 20
    return max(8, min(64, step))
end
local function ModStep(base)
    base = tonumber(base) or 1
    if IsAltKeyDown and IsAltKeyDown() then return GetGridStep() end
    local m = 1
    if IsControlKeyDown and IsControlKeyDown() then m = 10
    elseif IsShiftKeyDown and IsShiftKeyDown() then m = 5 end
    return base * m
end
local function ApplyModStepper(stepper)
    if not stepper or not stepper.minusButton or not stepper.plusButton then return end
    stepper.minusButton:SetScript("OnClick", function()
        stepper:SetValue((stepper:GetValue() or 0) - ModStep(stepper.step or 1), true)
    end)
    stepper.plusButton:SetScript("OnClick", function()
        stepper:SetValue((stepper:GetValue() or 0) + ModStep(stepper.step or 1), true)
    end)
end

--------------------------------------------------------------------
-- Slider helpers
--------------------------------------------------------------------
local function FormatSliderVal(slider, v)
    local step = (slider and slider.step) or (slider and slider.GetValueStep and slider:GetValueStep()) or 1
    if step and step >= 1 then return tostring(floor((v or 0) + 0.5)) end
    return string.format("%.2f", tonumber(v) or 0)
end
local function ForceSliderEB(slider)
    if not slider or not slider.editBox then return end
    if slider.editBox:HasFocus() then return end
    slider.editBox:SetText(FormatSliderVal(slider, slider.GetValue and slider:GetValue() or 0))
end

local function EnhanceSliderTrack(slider)
    if not slider or slider._msufTrackEnhanced then return end
    slider._msufTrackEnhanced = true
    local rail = slider:CreateTexture(nil, "BACKGROUND")
    rail:SetPoint("LEFT", slider, "LEFT", 2, 0); rail:SetPoint("RIGHT", slider, "RIGHT", -2, 0)
    rail:SetHeight(10); rail:SetColorTexture(0, 0, 0, 0.85)
    local line = slider:CreateTexture(nil, "BORDER")
    line:SetPoint("LEFT", rail, "LEFT", 0, 0); line:SetPoint("RIGHT", rail, "RIGHT", 0, 0)
    line:SetHeight(3); line:SetColorTexture(1, 1, 1, 0.65)
    for _, edge in ipairs({"TOP","BOTTOM"}) do
        local b = slider:CreateTexture(nil, "BORDER")
        b:SetPoint(edge.."LEFT", rail, edge.."LEFT", -1, edge == "TOP" and 1 or -1)
        b:SetPoint(edge.."RIGHT", rail, edge.."RIGHT", 1, edge == "TOP" and 1 or -1)
        b:SetHeight(1); b:SetColorTexture(1, 1, 1, 0.18)
    end
    local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
    if thumb and thumb.SetSize then thumb:SetSize(18, 18) end
    slider._msufTrackRail = rail; slider._msufTrackLine = line
end

local function EnableAnimatedFill(slider)
    if not slider or slider._msufAlphaFillEnabled then return end
    if not slider._msufTrackRail then EnhanceSliderTrack(slider) end
    local rail = slider._msufTrackRail
    if not rail then return end
    local inX = 2
    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetTexture("Interface\\Buttons\\UI-SliderBar-Fill")
    if fill.SetHorizTile then fill:SetHorizTile(true) end
    fill:SetPoint("TOPLEFT", rail, "TOPLEFT", inX, -2)
    fill:SetPoint("BOTTOMLEFT", rail, "BOTTOMLEFT", inX, 2)
    fill:SetWidth(1); fill:SetAlpha(0.90)
    slider._msufAlphaFill = fill
    slider._msufAlphaFillEnabled = true
    local anim = CreateFrame("Frame", nil, slider); anim:Hide()
    local function GetMax()
        if slider.maxVal then return slider.maxVal end
        if slider.GetMinMaxValues then local _, mx = slider:GetMinMaxValues(); return mx end
        return 1
    end
    local function Clamp01(x) return x < 0 and 0 or x > 1 and 1 or x end
    local function UsableW()
        local w = (rail.GetWidth and rail:GetWidth() or 0) - inX * 2
        return w < 1 and 1 or w
    end
    local function ApplyFrac(f) fill:SetWidth(UsableW() * Clamp01(f or 0)) end
    local function SetTarget(frac, instant)
        frac = Clamp01(frac or 0)
        if slider._msufAlphaFillCur == nil then
            slider._msufAlphaFillCur = frac
            slider._msufAlphaFillTarget = frac
            ApplyFrac(frac); return
        end
        slider._msufAlphaFillTarget = frac
        if instant then slider._msufAlphaFillCur = frac; ApplyFrac(frac); anim:Hide(); return end
        slider._msufAlphaFillStart = slider._msufAlphaFillCur
        slider._msufAlphaFillStartTime = GetTime()
        slider._msufAlphaFillDur = 0.14; anim:Show()
    end
    anim:SetScript("OnUpdate", function(self)
        local t0 = slider._msufAlphaFillStartTime
        if not t0 then self:Hide(); return end
        local p = (GetTime() - t0) / (slider._msufAlphaFillDur or 0.14)
        if p >= 1 then
            slider._msufAlphaFillCur = slider._msufAlphaFillTarget
            ApplyFrac(slider._msufAlphaFillCur); self:Hide(); return
        end
        local e = 1 - (1 - p) * (1 - p)
        slider._msufAlphaFillCur = (slider._msufAlphaFillStart or 0) + ((slider._msufAlphaFillTarget or 0) - (slider._msufAlphaFillStart or 0)) * e
        ApplyFrac(slider._msufAlphaFillCur)
    end)
    local function Update(v, instant)
        local mx = GetMax(); if not mx or mx <= 0 then mx = 1 end
        SetTarget((v or 0) / mx, instant)
    end
    slider:HookScript("OnMouseDown", function() slider._msufAlphaFillDragging = true end)
    slider:HookScript("OnMouseUp", function() slider._msufAlphaFillDragging = false; if slider.GetValue then Update(slider:GetValue(), true) end end)
    slider:HookScript("OnValueChanged", function(_, v) Update(v, slider._msufAlphaFillDragging) end)
    slider:HookScript("OnSizeChanged", function() if slider.GetValue then Update(slider:GetValue(), true) end end)
    if C_Timer and C_Timer.After then C_Timer.After(0, function() if slider and slider.GetValue then Update(slider:GetValue(), true) end end)
    else if slider.GetValue then Update(slider:GetValue(), true) end end
end

--------------------------------------------------------------------
-- BUILD
--------------------------------------------------------------------
function ns.MSUF_Options_Player_Build(panel, frameGroup, helpers)
    if not panel or not frameGroup or not helpers then return end
    local CreateAxisStepper = helpers.CreateAxisStepper
    local CreateLabeledSlider = helpers.CreateLabeledSlider
    local texWhite, texWhite2 = helpers.texWhite, helpers.texWhite2
    local leftX, topY = 8, -110
    local leftW, gap, rightW = 320, 8, 328
    local fullW = leftW + gap + rightW - 8
    local sectionGap = 8

    local function FinalizeCompactSlider(s, w)
        if not s then return end
        s:SetWidth(w or (leftW - 24))
        if s.editBox then s.editBox:Hide() end
        if s.minusButton then s.minusButton:Hide() end
        if s.plusButton then s.plusButton:Hide() end
        EnhanceSliderTrack(s)
    end

    local function FinalizeDashboard(s, w)
        if not s then return end
        s:SetWidth(w or ((fullW * 0.5) - 40))
        EnhanceSliderTrack(s)
        local eb, minus, plus = s.editBox, s.minusButton, s.plusButton
        if eb then eb:Show(); eb:ClearAllPoints(); eb:SetPoint("TOP", s, "BOTTOM", 0, -12); eb:SetWidth(40) end
        if minus then minus:Show(); minus:ClearAllPoints(); minus:SetPoint("RIGHT", eb or s, "LEFT", -4, 0) end
        if plus then plus:Show(); plus:ClearAllPoints(); plus:SetPoint("LEFT", eb or s, "RIGHT", 4, 0) end
        local n = s.GetName and s:GetName()
        if n then
            local low, high = _G[n.."Low"], _G[n.."High"]
            if low then low:ClearAllPoints(); low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -2) end
            if high then high:ClearAllPoints(); high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -2) end
        end
        if s.SetHitRectInsets then s:SetHitRectInsets(-6, -6, -14, -14) end
        local thumb = s.GetThumbTexture and s:GetThumbTexture()
        if thumb then if thumb.SetAlpha then thumb:SetAlpha(1) end; if thumb.Show then thumb:Show() end end
    end

    -- Collapsible sections
    local basicsH, castbarBoxH, loadCondH, sizeH = 132, 132, 124, 200
    local textBaseH, statusBoxH, bossLayoutH = 136, 188, 152
    panel._msufTextBaseH = textBaseH; panel._msufStatusBoxH = statusBoxH

    local basicsBox, basicsBody = MkCollapsible(frameGroup, "Frame Basics", fullW, basicsH, true)
    basicsBox:Hide(); panel.playerBasicsBox = basicsBox; panel.playerBasicsBody = basicsBody; panel._msufBasicsH = basicsH

    -- Power Bar section
    local powerBarBox, powerBarBody = MkCollapsible(frameGroup, "Power Bar", fullW, 160, false)
    powerBarBox:Hide(); panel.playerPowerBarBox = powerBarBox; panel.playerPowerBarBody = powerBarBody
    do
        local pbShowCB = MkCheck(powerBarBody, "MSUF_UF_PowerBarShowCB", "Show power bar", 12, -6)
        panel.playerPowerBarShowCB = pbShowCB

        local pbHeightSlider = CreateFrame("Slider", "MSUF_UF_PowerBarHeightSlider", powerBarBody, "OptionsSliderTemplate")
        pbHeightSlider:SetPoint("TOPLEFT", powerBarBody, "TOPLEFT", 14, -44)
        pbHeightSlider:SetMinMaxValues(1, 20); pbHeightSlider:SetValueStep(1); pbHeightSlider:SetObeyStepOnDrag(true)
        pbHeightSlider:SetWidth(200)
        local pbhText = _G["MSUF_UF_PowerBarHeightSliderText"]; if pbhText then pbhText:SetText("Height") end
        local pbhLow = _G["MSUF_UF_PowerBarHeightSliderLow"]; if pbhLow then pbhLow:SetText("1") end
        local pbhHigh = _G["MSUF_UF_PowerBarHeightSliderHigh"]; if pbhHigh then pbhHigh:SetText("20") end
        panel.playerPowerBarHeightSlider = pbHeightSlider

        local pbEmbedCB = MkCheck(powerBarBody, "MSUF_UF_PowerBarEmbedCB", "Embed into health bar", 12, -80)
        panel.playerPowerBarEmbedCB = pbEmbedCB

        local pbBorderCB = MkCheck(powerBarBody, "MSUF_UF_PowerBarBorderCB", "Power bar border", 300, -6)
        panel.playerPowerBarBorderCB = pbBorderCB

        local pbBorderSlider = CreateFrame("Slider", "MSUF_UF_PowerBarBorderSlider", powerBarBody, "OptionsSliderTemplate")
        pbBorderSlider:SetPoint("TOPLEFT", powerBarBody, "TOPLEFT", 300, -44)
        pbBorderSlider:SetMinMaxValues(0, 6); pbBorderSlider:SetValueStep(1); pbBorderSlider:SetObeyStepOnDrag(true)
        pbBorderSlider:SetWidth(200)
        local pbbText = _G["MSUF_UF_PowerBarBorderSliderText"]; if pbbText then pbbText:SetText("Border thickness") end
        local pbbLow = _G["MSUF_UF_PowerBarBorderSliderLow"]; if pbbLow then pbbLow:SetText("0") end
        local pbbHigh = _G["MSUF_UF_PowerBarBorderSliderHigh"]; if pbbHigh then pbbHigh:SetText("6") end
        panel.playerPowerBarBorderSlider = pbBorderSlider

        local pbSmoothCB = MkCheck(powerBarBody, "MSUF_UF_PowerBarSmoothCB", "Smooth Fill", 300, -80)
        panel.playerPowerBarSmoothCB = pbSmoothCB
    end

    local castbarBox, castbarBody = MkCollapsible(frameGroup, "Castbar", fullW, castbarBoxH, false)
    castbarBox:Hide(); panel.playerCastbarBox = castbarBox; panel.playerCastbarBody = castbarBody

    local textGroup, textBody = MkCollapsible(frameGroup, "Indicators", fullW, textBaseH, false)
    textGroup:Hide(); panel.playerTextLayoutGroup = textGroup; panel.playerTextLayoutBody = textBody; panel._msufTextGroup = textBody

    local statusBox, statusBody = MkCollapsible(frameGroup, "Status icons", fullW, statusBoxH, false)
    statusBox:Hide(); panel._msufStatusIconsGroup = statusBox; panel._msufStatusIconsBody = statusBody

    local bossLayoutBox, bossLayoutBody = MkCollapsible(frameGroup, "Boss Layout", fullW, bossLayoutH, false)
    bossLayoutBox:Hide(); panel.playerBossLayoutBox = bossLayoutBox; panel.playerBossLayoutBody = bossLayoutBody; panel._msufBossLayoutH = bossLayoutH

    local loadCondBox, loadCondBody = MkCollapsible(frameGroup, "Load Conditions", fullW, loadCondH, false)
    loadCondBox:Hide(); panel.playerLoadCondBox = loadCondBox; panel.playerLoadCondBody = loadCondBody; panel._msufLoadCondH = loadCondH

    local sizeBox, sizeBody = MkCollapsible(frameGroup, "Transparency", fullW, sizeH, false)
    sizeBox:Hide(); panel.playerSizeBox = sizeBox; panel.playerSizeBody = sizeBody; panel._msufSizeBaseH = sizeH; panel._msufSizeBossH = sizeH

    local anchorGroup, anchorBody = MkCollapsible(frameGroup, "Anchoring", fullW, 128, false)
    anchorGroup:Hide(); panel.unitAnchorGroup = anchorGroup; panel.unitAnchorBody = anchorBody

    -- Basic toggles
    local BASIC_TOGGLES = {
        { "playerEnableFrameCB", "MSUF_UF_EnableFrameCB", "Enable", 0, 0 },
        { "playerShowNameCB", "MSUF_UF_ShowNameCB", "Show name", 12, -34 },
        { "playerShowHPCB", "MSUF_UF_ShowHPCB", "Show HP text", 164, -34 },
        { "playerShowPowerCB", "MSUF_UF_ShowPowerCB", "Show power text", 12, -58 },
        { "playerReverseFillBarsCB", "MSUF_UF_ReverseFillBarsCB", "Reverse fill", 164, -58 },
        { "playerSmoothFillCB", "MSUF_UF_SmoothFillCB", "Smooth Health Fill", 320, -58 },
    }
    for _, s in ipairs(BASIC_TOGGLES) do
        panel[s[1]] = MkCheck(basicsBody, s[2], s[3], s[4], s[5] + 28)
    end
    -- Enable checkbox: right-aligned, label-left
    if panel.playerEnableFrameCB then
        panel.playerEnableFrameCB:ClearAllPoints()
        panel.playerEnableFrameCB:SetPoint("TOPRIGHT", basicsBody, "TOPRIGHT", -12, -6)
        CBLabelLeft(panel.playerEnableFrameCB, "Enable")
    end

    -- Portrait dropdown
    local portraitLabel = basicsBody:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    portraitLabel:SetPoint("TOPLEFT", basicsBody, "TOPLEFT", 12, -60)
    portraitLabel:SetText(TR("Portrait"))
    panel.playerPortraitLabel = portraitLabel
    local pdd = MkStyledDD("MSUF_UF_PortraitDropDown", basicsBody, 190)
    pdd:SetPoint("TOPLEFT", basicsBody, "TOPLEFT", -6, -72); pdd:Show()
    panel.playerPortraitDropDown = pdd

    -- Load Conditions (3-column grid)
    local LC_SPECS = {
        { "playerLoadCondMountedCB","loadCondHideMounted","Mounted",12,-14 },
        { "playerLoadCondOutCombatCB","loadCondHideOutOfCombat","Out of combat",240,-14 },
        { "playerLoadCondSoloCB","loadCondHideSolo","Solo",458,-14 },
        { "playerLoadCondVehicleCB","loadCondHideInVehicle","In vehicle",12,-38 },
        { "playerLoadCondInGroupCB","loadCondHideInGroup","In group",240,-38 },
        { "playerLoadCondInInstanceCB","loadCondHideInInstance","In instance",458,-38 },
        { "playerLoadCondRestingCB","loadCondHideResting","Resting",12,-62 },
        { "playerLoadCondInCombatCB","loadCondHideInCombat","In combat",240,-62 },
        { "playerLoadCondStealthedCB","loadCondHideStealthed","Stealthed",458,-62 },
    }
    panel._msufLoadCondSpecs = LC_SPECS
    for _, s in ipairs(LC_SPECS) do
        panel[s[1]] = MkCheck(loadCondBody, "MSUF_UF_"..s[1], s[3], s[4], s[5])
        if _G.MSUF_ClampCheckboxText then _G.MSUF_ClampCheckboxText(panel[s[1]], 170) end
    end

    -- Transparency controls
    local alphaSyncCB = CreateFrame("CheckButton", "MSUF_UF_AlphaSyncCB", sizeBody, "UICheckButtonTemplate")
    alphaSyncCB:SetPoint("TOPLEFT", sizeBody, "TOPLEFT", 12, -12)
    if alphaSyncCB.Text then alphaSyncCB.Text:SetText(TR("Sync both")) end
    panel.playerAlphaSyncCB = alphaSyncCB

    local alphaExcludeCB = CreateFrame("CheckButton", "MSUF_UF_AlphaExcludeTextPortraitCB", sizeBody, "UICheckButtonTemplate")
    alphaExcludeCB:SetPoint("TOPLEFT", sizeBody, "TOPLEFT", 304, -12)
    CBLabelLeft(alphaExcludeCB, "Keep text + portrait visible")
    if _G.MSUF_ClampCheckboxText then _G.MSUF_ClampCheckboxText(alphaExcludeCB, 220) end
    panel.playerAlphaExcludeTextPortraitCB = alphaExcludeCB

    sizeBody:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"):SetPoint("TOPLEFT", sizeBody, "TOPLEFT", 12, -44)
    -- (label text set implicitly via fontstring above, but we need to set text)
    do local lbl = sizeBody:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", sizeBody, "TOPLEFT", 12, -44); lbl:SetText(TR("Sliders affect"))
    end

    local alphaLayerDD = MkStyledDD("MSUF_UF_AlphaLayerDropDown", sizeBody, 160)
    alphaLayerDD:SetPoint("TOPLEFT", sizeBody, "TOPLEFT", -6, -56); alphaLayerDD:Show()
    panel.playerAlphaLayerDropDown = alphaLayerDD

    for _, s in ipairs({
        { "playerAlphaInCombatSlider","MSUF_UF_AlphaInCombatSlider","Alpha in combat",12,-98 },
        { "playerAlphaOutCombatSlider","MSUF_UF_AlphaOutCombatSlider","Alpha out of combat",334,-98 },
    }) do
        panel[s[1]] = CreateLabeledSlider(s[2], s[3], sizeBody, 0.00, 1.00, 0.05, s[4], s[5])
        FinalizeDashboard(panel[s[1]], 236)
    end

    -- ToT inline toggle + separator
    panel.totShowInTargetCB = MkCheck(castbarBody, "MSUF_ToTInlineInTargetCB", "Show ToT text in target frame", 12, -6)
    if _G.MSUF_ClampCheckboxText then _G.MSUF_ClampCheckboxText(panel.totShowInTargetCB, 230) end
    panel.totShowInTargetCB:Hide()

    local totSepDD = MkStyledDD("MSUF_ToTInlineSeparatorDropDown", castbarBody, 156)
    if panel.totShowInTargetCB then
        totSepDD:SetPoint("TOPLEFT", panel.totShowInTargetCB, "BOTTOMLEFT", -18, -8)
        if totSepDD.SetFrameLevel and panel.totShowInTargetCB.GetFrameLevel then
            totSepDD:SetFrameLevel((panel.totShowInTargetCB:GetFrameLevel() or 0) + 2)
        end
    else totSepDD:SetPoint("TOPLEFT", castbarBody, "TOPLEFT", -6, -30) end
    totSepDD:Hide(); panel.totInlineSeparatorDD = totSepDD

    -- Castbar toggles per unit
    for _, spec in ipairs({
        { key = "player", cap = "Player", et = "Enable player castbar", tt = "Show player cast time", vis = true },
        { key = "target", cap = "Target", et = "Enable target castbar", tt = "Show target cast time" },
        { key = "focus", cap = "Focus", et = "Enable focus castbar", tt = "Show focus cast time" },
        { key = "boss", cap = "Boss", et = "Enable boss castbars", tt = "Show boss cast time" },
    }) do
        panel[spec.key.."CastbarEnableCB"] = MkCheck(castbarBody, "MSUF_"..spec.cap.."CastbarEnableCB", spec.et, 12, -6)
        panel[spec.key.."CastbarShowIconCB"] = MkCheck(castbarBody, "MSUF_"..spec.cap.."CastbarShowIconCB", "Icon", 214, -6)
        panel[spec.key.."CastbarShowTextCB"] = MkCheck(castbarBody, "MSUF_"..spec.cap.."CastbarShowTextCB", "Text", 276, -6)
        panel[spec.key.."CastbarTimeCB"] = MkCheck(castbarBody, "MSUF_"..spec.cap.."CastbarTimeCB", spec.tt, 12, -30)
        panel[spec.key.."CastbarInterruptCB"] = MkCheck(castbarBody, "MSUF_"..spec.cap.."CastbarInterruptCB", "Show interrupt", 12, -54)
        if not spec.vis then
            for _, sfx in ipairs({"CastbarEnableCB","CastbarShowIconCB","CastbarShowTextCB","CastbarTimeCB","CastbarInterruptCB"}) do
                local w = panel[spec.key..sfx]; if w then w:Hide() end
            end
        end
    end

    -- Indicator layout constants
    local IND_COL_X, IND_BASE_TOGGLE_Y, IND_BASE_CTRL_Y, IND_ROW_STEP = 300, -6, -8, -30
    panel._msufIndicatorLayout = { colX = IND_COL_X, leaderToggleY = IND_BASE_TOGGLE_Y, leaderCtrlY = IND_BASE_CTRL_Y, rowStep = IND_ROW_STEP, dividerOffset = 0 }

    -- Boss-only controls
    panel.playerBossSpacingSlider = CreateLabeledSlider("MSUF_UF_BossSpacingSlider", "Boss spacing", bossLayoutBody, -400, 0, 1, 12, -14)
    FinalizeCompactSlider(panel.playerBossSpacingSlider, fullW - 24)
    panel.playerBossSpacingSlider:Hide()

    -- Layout mode dropdown (replaces the old "Invert boss order" checkbox).
    -- Four orderings: vertical down/up, horizontal left->right / right->left.
    panel.playerBossLayoutModeLabel = bossLayoutBody:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.playerBossLayoutModeLabel:SetJustifyH("LEFT")
    panel.playerBossLayoutModeLabel:SetText(TR("Boss frame layout"))
    panel.playerBossLayoutModeLabel:Hide()

    panel.playerBossLayoutModeDD = MkStyledDD("MSUF_UF_BossLayoutModeDropDown", bossLayoutBody, 220)
    panel.playerBossLayoutModeDD:Hide()

    -- Target highlight moved 10px lower to make room for the dropdown (label + DD = 2 rows).
    panel.playerBossTargetHLCB = MkCheck(bossLayoutBody, "MSUF_UF_BossTargetHLCB", "Highlight targeted boss frame", 12, -96); panel.playerBossTargetHLCB:Hide()

    -- Per-unit anchoring controls
    do
        if not panel.unitAnchorToLabel then
            panel.unitAnchorToLabel = anchorBody:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            panel.unitAnchorToLabel:SetJustifyH("LEFT")
        end
        panel.unitAnchorToLabel:SetText(TR("Anchor unit to")); panel.unitAnchorToLabel:Hide()

        if not panel.unitAnchorToDD then
            panel.unitAnchorToDD = MkStyledDD("MSUF_UnitAnchorToDropDown", anchorBody, 180)
        end
        panel.unitAnchorToDD:Hide()

        if not panel.unitCustomAnchorLabel then
            panel.unitCustomAnchorLabel = anchorBody:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            panel.unitCustomAnchorLabel:SetJustifyH("LEFT")
        end
        panel.unitCustomAnchorLabel:SetText(TR("Custom anchor target (mouse picker)")); panel.unitCustomAnchorLabel:Hide()

        if not panel.unitCustomAnchorPickButton then
            local b = CreateFrame("Button", nil, anchorBody, "UIPanelButtonTemplate")
            b:SetSize(170, 22); b:SetText(TR("Pick frame (CTRL+Click)"))
            panel.unitCustomAnchorPickButton = b
        end
        panel.unitCustomAnchorPickButton:Hide()

        if not panel.unitCustomAnchorClearButton then
            local b = CreateFrame("Button", nil, anchorBody, "UIPanelButtonTemplate")
            b:SetSize(56, 22); b:SetText(TR("Clear"))
            panel.unitCustomAnchorClearButton = b
        end
        panel.unitCustomAnchorClearButton:Hide()

        if not panel.unitCustomAnchorValueText then
            local fs = anchorBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetJustifyH("LEFT"); fs:SetTextColor(0.85, 0.85, 0.85)
            panel.unitCustomAnchorValueText = fs
        end
        panel.unitCustomAnchorValueText:Hide()

        if not panel.unitGlobalAnchorWarn then
            panel.unitGlobalAnchorWarn = anchorBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            panel.unitGlobalAnchorWarn:SetJustifyH("LEFT"); panel.unitGlobalAnchorWarn:SetTextColor(1, 0.82, 0.2)
        end
        panel.unitGlobalAnchorWarn:SetText(""); panel.unitGlobalAnchorWarn:Hide()
    end

    -- Status icon checkboxes
    local STATUS_BASE_Y, STATUS_STEP = -6, -30
    panel.statusCombatIconCB = MkCheck(statusBody, "MSUF_StatusCombatIconCB", "Combat", 12, STATUS_BASE_Y)
    panel.statusRestingIconCB = MkCheck(statusBody, "MSUF_StatusRestingIconCB", "Rested (player only)", 12, STATUS_BASE_Y + STATUS_STEP)
    panel.statusIncomingResIconCB = MkCheck(statusBody, "MSUF_StatusIncomingResIconCB", "Incoming Rez", 12, STATUS_BASE_Y + 2*STATUS_STEP)
    panel.statusIconsTestModeCB = MkCheck(statusBody, "MSUF_StatusIconsTestModeCB", "Test mode", 12, STATUS_BASE_Y + 3*STATUS_STEP + 10)
    panel.statusIconsStyleCB = MkCheck(statusBody, "MSUF_StatusIconsStyleCB", "Use Midnight style icons", 12, STATUS_BASE_Y + 3*STATUS_STEP - 12)
    for _, w in ipairs({ panel.statusCombatIconCB, panel.statusRestingIconCB, panel.statusIncomingResIconCB, panel.statusIconsTestModeCB, panel.statusIconsStyleCB }) do
        if w then w:Hide() end
    end

    -- Helper factories for indicator/status rows
    local function MkDivider(field, par)
        if panel[field] then panel[field]:Hide(); return panel[field] end
        local tex = (par or textBody):CreateTexture(nil, "ARTWORK"); tex:SetHeight(1); tex:SetColorTexture(1, 1, 1, 0.08); tex:Hide()
        panel[field] = tex; return tex
    end
    local function MkDrop(field, gname, w, par)
        if panel[field] then panel[field]:Hide(); return panel[field] end
        local dd = MkStyledDD(gname, par or textBody, w); dd:SetScale(0.80); dd:Hide()
        panel[field] = dd; return dd
    end
    local function MkLabel(field, text, par)
        if panel[field] then panel[field]:SetText(text); panel[field]:Hide(); return panel[field] end
        local fs = (par or textBody):CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); fs:SetText(text); fs:Hide()
        panel[field] = fs; return fs
    end
    local function MkSizeEdit(field, gname, par)
        if panel[field] then panel[field]:Hide(); return panel[field] end
        local eb = CreateFrame("EditBox", gname, par or textBody, "InputBoxTemplate")
        eb:SetAutoFocus(false); eb:SetSize(46, 18); eb:SetNumeric(true); eb:SetMaxLetters(3)
        eb:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE"); eb:Hide()
        panel[field] = eb; return eb
    end
    local function MkLayerSlider(field, gname, par)
        if panel[field] then panel[field]:Hide(); return panel[field] end
        local sl = CreateFrame("Slider", gname, par or textBody, "OptionsSliderTemplate")
        sl:SetMinMaxValues(1, 10); sl:SetValueStep(1); sl:SetObeyStepOnDrag(true); sl:SetWidth(56)
        EnhanceSliderTrack(sl)
        local low, high, text = _G[gname.."Low"], _G[gname.."High"], _G[gname.."Text"]
        if low then low:SetText(""); low:Hide() end
        if high then high:SetText(""); high:Hide() end
        if text then text:SetText(""); text:Hide() end
        local val = sl:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        val:SetPoint("LEFT", sl, "RIGHT", 3, 0); val:SetText("L7")
        sl._msufValueText = val
        sl._msufSetLayerText = function(self, v)
            if self._msufValueText then self._msufValueText:SetText("L" .. tostring(ClampLayerValue(v, 7))) end
        end
        sl.MSUF_SetValueSilent = function(self, v)
            self._msufLayerSilent = true
            local n = ClampLayerValue(v, 7)
            self:SetValue(n)
            self:_msufSetLayerText(n)
            self._msufLayerSilent = nil
        end
        sl:SetScript("OnValueChanged", function(self, v)
            local n = ClampLayerValue(v, 7)
            self:_msufSetLayerText(n)
            if self._msufLayerSilent then return end
            if type(self.onValueChanged) == "function" then self.onValueChanged(self, n) end
        end)
        sl:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TR("Icon layer / strata"), 1, 1, 1)
            GameTooltip:AddLine(TR("1 = behind, 10 = on top."), 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        sl:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        if sl.SetHitRectInsets then sl:SetHitRectInsets(-4, -22, -8, -8) end
        sl:Hide(); panel[field] = sl; return sl
    end
    local function MkResetBtn(field, cb, par)
        if not panel[field] then
            local btn = CreateFrame("Button", nil, par or textBody, "UIPanelButtonTemplate")
            btn:SetSize(20, 20); btn:SetText(TR("R"))
            local fs = btn.GetFontString and btn:GetFontString()
            if fs then fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE"); fs:ClearAllPoints(); fs:SetPoint("CENTER") end
            btn:SetScript("OnEnter", function(self)
                if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(TR("Resets current indicator"), 1, 1, 1)
                    GameTooltip:AddLine("Resets X/Y, Anchor, Size and Layer back to defaults.", 0.85, 0.85, 0.85, true); GameTooltip:Show() end
            end)
            btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            panel[field] = btn
        end
        panel[field]:Hide()
        return panel[field]
    end

    local function LayoutRow(cb, sx, sy, ad, al, se, sl, ls, id, il, colX, ctrlY)
        if sx then sx:ClearAllPoints(); sx:SetPoint("TOPLEFT", sx:GetParent(), "TOPLEFT", colX, ctrlY)
            sx:SetWidth(46); RestyleStepper(sx); ApplyModStepper(sx); if sx.label then sx.label:Hide() end; sx:Hide() end
        if sy and sx then sy:ClearAllPoints(); sy:SetPoint("LEFT", sx, "RIGHT", 6, 0)
            sy:SetWidth(46); RestyleStepper(sy); ApplyModStepper(sy); if sy.label then sy.label:Hide() end; sy:Hide() end
        if ad and sy then ad:ClearAllPoints(); ad:SetPoint("LEFT", sy, "RIGHT", 1, 0)
            if al then al:ClearAllPoints(); al:SetPoint("BOTTOM", ad, "TOP", 0, 6); al:Hide() end; ad:Hide() end
        if se and ad then se:ClearAllPoints(); se:SetPoint("LEFT", ad, "RIGHT", 1, 2)
            if sl then sl:ClearAllPoints(); sl:SetPoint("BOTTOM", se, "TOP", 0, 6); sl:Hide() end; se:Hide() end
        if ls and se then ls:ClearAllPoints(); ls:SetPoint("LEFT", se, "RIGHT", 8, -1); ls:Hide() end
        local tail = ls or se
        if id and tail then id:ClearAllPoints(); id:SetPoint("LEFT", tail, "RIGHT", 1, -2)
            if il then il:ClearAllPoints(); il:SetPoint("BOTTOM", id, "TOP", 0, 6); il:Hide() end; id:Hide() end
        if cb then cb:Hide() end
    end

    -- Build indicator rows
    for idx, id in ipairs(INDICATOR_ORDER) do
        local spec = INDICATOR_SPECS[id]; if not spec then break end
        MkDivider(spec.divider)
        if not panel[spec.showCB] then
            panel[spec.showCB] = MkCheck(textBody, "MSUF_"..spec.showCB:gsub("^%l", string.upper), spec.showCB:find("Leader") and "Show leader/assist icon" or spec.showCB:find("RaidMarker") and "Show raid marker icon" or spec.showCB:find("Elite") and "Show elite / rare icon" or "Show level", 12, IND_BASE_TOGGLE_Y + (idx - 1) * IND_ROW_STEP)
        end
        panel[spec.showCB]:Hide()
        MkResetBtn(spec.resetBtn, panel[spec.showCB])
        if not panel[spec.xStepper] then panel[spec.xStepper] = CreateAxisStepper("MSUF_"..spec.xStepper, "X", textBody, spec.xDefault, 0, -200, 200, 1) end
        if not panel[spec.yStepper] then panel[spec.yStepper] = CreateAxisStepper("MSUF_"..spec.yStepper, "Y", textBody, spec.yDefault, 0, -200, 200, 1) end
        panel[spec.anchorDrop] = MkDrop(spec.anchorDrop, "MSUF_"..spec.anchorDrop, 70)
        MkLabel(spec.anchorDrop:gsub("Drop$","Label"), "Anchor")
        panel[spec.sizeEdit] = MkSizeEdit(spec.sizeEdit, "MSUF_"..spec.sizeEdit)
        MkLabel(spec.sizeEdit:gsub("Edit$","Label"), "Size")
        if spec.layerSlider then panel[spec.layerSlider] = MkLayerSlider(spec.layerSlider, "MSUF_"..spec.layerSlider) end
        -- Store anchorLabel/sizeLabel keys for later
        spec.anchorLabel = spec.anchorDrop:gsub("Drop$","Label")
        spec.sizeLabel = spec.sizeEdit:gsub("Edit$","Label")
        LayoutRow(panel[spec.showCB], panel[spec.xStepper], panel[spec.yStepper],
            panel[spec.anchorDrop], panel[spec.anchorLabel], panel[spec.sizeEdit], panel[spec.sizeLabel], panel[spec.layerSlider],
            nil, nil, IND_COL_X, IND_BASE_CTRL_Y + (idx - 1) * IND_ROW_STEP)
    end

    -- Build status icon rows
    for _, def in ipairs(STATUS_ICON_DEFS) do
        local p = def.prefix
        MkDivider(p.."GroupDivider", statusBody)
        MkResetBtn(p.."ResetBtn", panel[p.."IconCB"], statusBody)
        if not panel[p.."OffsetXStepper"] then panel[p.."OffsetXStepper"] = CreateAxisStepper("MSUF_"..p.."OffsetX", "X", statusBody, 0, 0, -200, 200, 1) end
        if not panel[p.."OffsetYStepper"] then panel[p.."OffsetYStepper"] = CreateAxisStepper("MSUF_"..p.."OffsetY", "Y", statusBody, 0, 0, -200, 200, 1) end
        panel[p.."AnchorDrop"] = MkDrop(p.."AnchorDrop", "MSUF_"..p.."AnchorDropdown", 70, statusBody)
        MkLabel(p.."AnchorLabel", "Anchor", statusBody)
        panel[p.."SizeEdit"] = MkSizeEdit(p.."SizeEdit", "MSUF_"..p.."SizeEdit", statusBody)
        MkLabel(p.."SizeLabel", "Size", statusBody)
        panel[p.."LayerSlider"] = MkLayerSlider(p.."LayerSlider", "MSUF_"..p.."LayerSlider", statusBody)
        panel[p.."SymbolDrop"] = MkDrop(p.."SymbolDrop", "MSUF_"..p.."SymbolDropdown", 128, statusBody)
        MkLabel(p.."SymbolLabel", "Icon", statusBody)
        LayoutRow(panel[p.."IconCB"], panel[p.."OffsetXStepper"], panel[p.."OffsetYStepper"],
            panel[p.."AnchorDrop"], panel[p.."AnchorLabel"], panel[p.."SizeEdit"], panel[p.."SizeLabel"], panel[p.."LayerSlider"],
            panel[p.."SymbolDrop"], panel[p.."SymbolLabel"], IND_COL_X, STATUS_BASE_Y - 2 + def.rowIndex * STATUS_STEP)
    end

    -- Copy-To UI (all 6 units)
    if not _G._MSUF_CopyDestLabel then
        _G._MSUF_CopyDestLabel = function(k)
            return ({ player="Player", target="Target", focus="Focus", boss="Boss frames",
                      pet="Pet", targettarget="Target of Target", all="All" })[k] or tostring(k)
        end
    end
    local COPY_UI_DEFS = {
        { "player","MSUF_PlayerCopyToDropdown","_msufCopyDestKey","target",
          { {"Target","target"},{"Focus","focus"},{"Boss frames","boss"},{"Pet","pet"},{"Target of Target","targettarget"} } },
        { "target","MSUF_TargetCopyToDropdown","_msufCopyDestKey_target","player",
          { {"Player","player"},{"Focus","focus"},{"Boss frames","boss"},{"Pet","pet"},{"Target of Target","targettarget"} } },
        { "focus","MSUF_FocusCopyToDropdown","_msufCopyDestKey_focus","target",
          { {"Player","player"},{"Target","target"},{"Boss frames","boss"},{"Pet","pet"},{"Target of Target","targettarget"} } },
        { "boss","MSUF_BossCopyToDropdown","_msufCopyDestKey_boss","target",
          { {"Player","player"},{"Target","target"},{"Focus","focus"},{"Pet","pet"},{"Target of Target","targettarget"} } },
        { "tot","MSUF_ToTCopyToDropdown","_msufCopyDestKey_tot","player",
          { {"Player","player"},{"Target","target"},{"Focus","focus"},{"Boss frames","boss"},{"Pet","pet"} } },
        { "pet","MSUF_PetCopyToDropdown","_msufCopyDestKey_pet","target",
          { {"Player","player"},{"Target","target"},{"Target of Target","targettarget"},{"Focus","focus"},{"Boss frames","boss"} } },
    }
    for _, def in ipairs(COPY_UI_DEFS) do
        local prefix, dropName, destVar, defaultDest, items = def[1], def[2], def[3], def[4], def[5]
        local lk, dk, bk, hk = prefix.."CopyToLabel", prefix.."CopyToDrop", prefix.."CopyToButton", prefix.."CopyToHint"
        if not panel[lk] then
            panel[lk] = textGroup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            panel[lk]:SetText(TR("Copy to")); panel[lk]:Hide()
        end
        if not panel[dk] then
            local dd = MkStyledDD(dropName, textGroup, 150); dd:SetScale(0.86); dd:Hide()
            panel[dk] = dd; panel[destVar] = panel[destVar] or defaultDest
            UIDropDownMenu_Initialize(dd, function(self, level)
                if not level then return end
                for i = 1, #items do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text, info.value = items[i][1], items[i][2]
                    info.func = function(btn)
                        local v = (btn and btn.value) or defaultDest
                        panel[destVar] = v; self.selectedValue = v
                        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(self, v) end
                        local label = (_G._MSUF_CopyDestLabel and _G._MSUF_CopyDestLabel(v)) or tostring(v)
                        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(self, label) end
                        if CloseDropDownMenus then CloseDropDownMenus() end
                    end
                    info.checked = function() return panel[destVar] == items[i][2] end
                    UIDropDownMenu_AddButton(info, level)
                end
                local sep = UIDropDownMenu_CreateInfo(); sep.text = " "; sep.isTitle = true; sep.notCheckable = true
                UIDropDownMenu_AddButton(sep, level)
                local ainfo = UIDropDownMenu_CreateInfo(); ainfo.text = "All"; ainfo.value = "all"
                ainfo.func = function(btn) panel[destVar] = "all"
                    if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(self, "all") end
                    if UIDropDownMenu_SetText then UIDropDownMenu_SetText(self, "All") end
                    if CloseDropDownMenus then CloseDropDownMenus() end
                end
                ainfo.checked = function() return panel[destVar] == "all" end
                UIDropDownMenu_AddButton(ainfo, level)
            end)
            if dd.HookScript then dd:HookScript("OnShow", function(self)
                local k = panel[destVar] or defaultDest
                if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(self, k) end
                local label = (_G._MSUF_CopyDestLabel and _G._MSUF_CopyDestLabel(k)) or tostring(k)
                if UIDropDownMenu_SetText then UIDropDownMenu_SetText(self, label) end
            end) end
        end
        if not panel[bk] then
            local btn = CreateFrame("Button", nil, textGroup, "UIPanelButtonTemplate")
            btn:SetSize(64, 20); btn:SetText(TR("Copy")); btn:Hide()
            btn._msufNoSlashSkin = true
            if _G.MSUF_SkinMidnightActionButton then _G.MSUF_SkinMidnightActionButton(btn) end
            panel[bk] = btn
        end
        if not panel[hk] then
            panel[hk] = textGroup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); panel[hk]:SetText(""); panel[hk]:Hide()
        end
        -- Position relative to bottom anchor
        local anchorBox = panel._msufBottomAnchor or panel.unitAnchorGroup or panel.playerSizeBox
        if anchorBox then
            panel[dk]:ClearAllPoints(); panel[dk]:SetPoint("TOPLEFT", anchorBox, "BOTTOMLEFT", 44, -16)
            panel[lk]:ClearAllPoints(); panel[lk]:SetPoint("LEFT", panel[dk], "LEFT", -40, 2)
            panel[bk]:ClearAllPoints(); panel[bk]:SetPoint("LEFT", panel[dk], "RIGHT", -14, 2)
            panel[hk]:ClearAllPoints(); panel[hk]:SetPoint("TOPLEFT", panel[dk], "BOTTOMLEFT", -32, -2)
        end
    end

    -- Relayout system
    do
        local function RelayoutCopy(anchor)
            for _, def in ipairs(COPY_UI_DEFS) do
                local prefix = def[1]
                local dk, lk, bk, hk = prefix.."CopyToDrop", prefix.."CopyToLabel", prefix.."CopyToButton", prefix.."CopyToHint"
                if panel[dk] and anchor then
                    panel[dk]:ClearAllPoints(); panel[dk]:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 44, -16)
                end
                if panel[lk] and panel[dk] then panel[lk]:ClearAllPoints(); panel[lk]:SetPoint("LEFT", panel[dk], "LEFT", -40, 2) end
                if panel[bk] and panel[dk] then panel[bk]:ClearAllPoints(); panel[bk]:SetPoint("LEFT", panel[dk], "RIGHT", -14, 2) end
                if panel[hk] and panel[dk] then panel[hk]:ClearAllPoints(); panel[hk]:SetPoint("TOPLEFT", panel[dk], "BOTTOMLEFT", -32, -2) end
            end
        end

        local function Relayout(activeKey)
            local k = CanonKey(activeKey) or "player"
            local showCB = (k == "player" or k == "target" or k == "focus" or k == "boss" or k == "targettarget")
            local showSt = (k == "player" or k == "target")
            local showBL = (k == "boss")
            local showAnch = (k == "player" or k == "target" or k == "focus" or k == "boss" or k == "pet" or k == "targettarget")

            if basicsBox then basicsBox:ClearAllPoints(); basicsBox:SetPoint("TOPLEFT", frameGroup, "TOPLEFT", leftX, topY); basicsBox:SetWidth(fullW) end
            local prev = basicsBox
            local function Chain(box, show)
                if not box then return end
                box:ClearAllPoints(); box:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -sectionGap); box:SetWidth(fullW); box:SetShown(show)
                if show then prev = box end
            end
            local showPB = (k == "player" or k == "target" or k == "focus" or k == "boss")
            Chain(powerBarBox, showPB)
            Chain(castbarBox, showCB)
            Chain(textGroup, true)
            Chain(statusBox, showSt)
            Chain(bossLayoutBox, showBL)
            Chain(loadCondBox, true)
            Chain(sizeBox, true)
            Chain(anchorGroup, showAnch)
            panel._msufBottomAnchor = prev
            RelayoutCopy(prev)
            if panel._msufFramesScrollUpdate then panel._msufFramesScrollUpdate() end
        end
        panel._msufRelayoutUnitBoxes = Relayout
        for _, box in ipairs({ basicsBox, powerBarBox, castbarBox, textGroup, statusBox, loadCondBox, sizeBox, bossLayoutBox, anchorGroup }) do
            if box then box._msufOnCollapsedChanged = function() Relayout(panel._msufLastApplyKey or "player") end end
        end
        Relayout("player")
    end

    -- Bind copy buttons
    local function BindCopy(btn, src, destVar, def)
        if not btn or btn._msufCopyBound then return end
        btn._msufCopyBound = true
        btn:SetScript("OnClick", function()
            CopyUnitSettings(src, panel[destVar] or def, panel._msufAPI)
        end)
    end
    panel._msufBindCopyButtons = function()
        BindCopy(panel.playerCopyToButton, "player", "_msufCopyDestKey", "target")
        BindCopy(panel.targetCopyToButton, "target", "_msufCopyDestKey_target", "player")
        BindCopy(panel.focusCopyToButton, "focus", "_msufCopyDestKey_focus", "target")
        BindCopy(panel.bossCopyToButton, "boss", "_msufCopyDestKey_boss", "target")
        BindCopy(panel.petCopyToButton, "pet", "_msufCopyDestKey_pet", "target")
        BindCopy(panel.totCopyToButton, "targettarget", "_msufCopyDestKey_tot", "player")
    end
end

--------------------------------------------------------------------
-- LAYOUT INDICATOR TEMPLATE
--------------------------------------------------------------------
function ns.MSUF_Options_Player_LayoutIndicatorTemplate(panel, currentKey)
    if not panel or not panel._msufIndicatorLayout then return end
    local l = panel._msufIndicatorLayout
    local container = panel._msufTextGroup or panel.playerTextLayoutGroup or panel
    local isFrames = true
    if type(panel._msufIsFramesTab) == "function" then isFrames = panel._msufIsFramesTab() end

    local function SW(name, show)
        local w = name and panel[name]; if w then w:SetShown(show) end
    end

    -- Hide everything if not on Frames tab
    if not isFrames then
        if panel._msufStatusIconsGroup then panel._msufStatusIconsGroup:Hide() end
        for _, spec in pairs(INDICATOR_SPECS) do
            for _, f in ipairs({ spec.showCB, spec.xStepper, spec.yStepper, spec.anchorDrop, spec.anchorLabel, spec.sizeEdit, spec.sizeLabel, spec.layerSlider, spec.divider, spec.resetBtn }) do
                SW(f, false)
            end
        end
        for _, def in ipairs(STATUS_ICON_DEFS) do
            for _, sfx in ipairs(STATUS_WIDGET_SUFFIXES) do SW(def.prefix..sfx, false) end
        end
        for _, w in ipairs({ "statusIconsTestModeCB","statusIconsStyleCB","statusIconsHeader" }) do SW(w, false) end
        if panel.playerBossSpacingSlider then panel.playerBossSpacingSlider:Hide() end
        if panel.playerBossLayoutModeLabel then panel.playerBossLayoutModeLabel:Hide() end
        if panel.playerBossLayoutModeDD then panel.playerBossLayoutModeDD:Hide() end
        if panel.playerBossTargetHLCB then panel.playerBossTargetHLCB:Hide() end
        if panel.playerBossLayoutBox then panel.playerBossLayoutBox:Hide() end
        for _, w in ipairs({ "unitAnchorToLabel","unitAnchorToDD","unitCustomAnchorLabel","unitCustomAnchorPickButton","unitCustomAnchorClearButton","unitCustomAnchorValueText","unitGlobalAnchorWarn" }) do
            SW(w, false)
        end
        return
    end

    local baseToggleY = l.leaderToggleY or -34
    local baseCtrlY = l.leaderCtrlY or -36
    local step = l.rowStep or -30
    local colX = l.colX or 420

    -- Indicator rows
    local row = 0
    for _, id in ipairs(INDICATOR_ORDER) do
        local spec = INDICATOR_SPECS[id]
        if spec then
            local show = spec.allowed(currentKey) and true or false
            for _, f in ipairs({ spec.showCB, spec.xStepper, spec.yStepper, spec.anchorDrop, spec.sizeEdit, spec.layerSlider, spec.resetBtn }) do SW(f, show) end
            SW(spec.anchorLabel, false); SW(spec.sizeLabel, false); SW(spec.divider, false)
            if show then
                local cb = panel[spec.showCB]
                if cb then cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", container, "TOPLEFT", 12, baseToggleY + row * step) end
                local sx = panel[spec.xStepper]
                if sx then sx:ClearAllPoints(); sx:SetPoint("TOPLEFT", container, "TOPLEFT", colX, baseCtrlY + row * step) end
                local reset = panel[spec.resetBtn]
                if reset then
                    reset:ClearAllPoints()
                    local tail = panel[spec.layerSlider] or panel[spec.sizeEdit]
                    if tail then reset:SetPoint("LEFT", tail, "RIGHT", 24, 0) else local ad = panel[spec.anchorDrop]; if ad then reset:SetPoint("LEFT", ad, "RIGHT", 6, 0) end end
                    reset:Show()
                end
                row = row + 1
            end
        end
    end

    -- The target tab can show four indicator rows at once
    -- (leader/assist + raid marker + level + elite/rare). The old fixed
    -- 3-row height caused the last row to overlap the next collapsible box.
    if panel.playerTextLayoutGroup and panel._msufTextBaseH then
        local extraRows = math.max(0, row - 3)
        local extraTot = (currentKey == "targettarget") and 28 or 0
        local neededH = panel._msufTextBaseH + extraTot + extraRows * math.abs(step)
        panel.playerTextLayoutGroup._msufExpandedH = neededH
        if not panel.playerTextLayoutGroup._msufCollapsed then
            panel.playerTextLayoutGroup:SetHeight(neededH)
        end
    end

    -- Anchoring
    local showAnch = (currentKey == "player" or currentKey == "target" or currentKey == "targettarget" or currentKey == "focus" or currentKey == "pet" or currentKey == "boss")
    for _, w in ipairs({ "unitAnchorGroup","unitAnchorToLabel","unitAnchorToDD","unitCustomAnchorLabel","unitCustomAnchorPickButton","unitCustomAnchorClearButton","unitCustomAnchorValueText" }) do
        SW(w, showAnch)
    end
    SW("unitGlobalAnchorWarn", false)
    if showAnch and panel.unitAnchorGroup then
        local g = panel.unitAnchorBody or panel.unitAnchorGroup
        if panel.unitAnchorToLabel then panel.unitAnchorToLabel:ClearAllPoints(); panel.unitAnchorToLabel:SetPoint("TOPLEFT", g, "TOPLEFT", 10, -14) end
        if panel.unitAnchorToDD then
            panel.unitAnchorToDD:ClearAllPoints(); panel.unitAnchorToDD:SetPoint("TOPLEFT", g, "TOPLEFT", 86, -6)
            if panel.unitAnchorToDD.SetFrameLevel and panel.unitAnchorGroup.GetFrameLevel then
                panel.unitAnchorToDD:SetFrameLevel((panel.unitAnchorGroup:GetFrameLevel() or 0) + 2) end
        end
        if panel.unitCustomAnchorLabel then panel.unitCustomAnchorLabel:ClearAllPoints(); panel.unitCustomAnchorLabel:SetPoint("TOPLEFT", g, "TOPLEFT", 10, -44) end
        if panel.unitCustomAnchorPickButton then panel.unitCustomAnchorPickButton:ClearAllPoints(); panel.unitCustomAnchorPickButton:SetPoint("TOPLEFT", g, "TOPLEFT", 10, -66) end
        if panel.unitCustomAnchorClearButton then panel.unitCustomAnchorClearButton:ClearAllPoints(); panel.unitCustomAnchorClearButton:SetPoint("LEFT", panel.unitCustomAnchorPickButton, "RIGHT", 8, 0) end
        if panel.unitCustomAnchorValueText then
            panel.unitCustomAnchorValueText:ClearAllPoints()
            panel.unitCustomAnchorValueText:SetPoint("LEFT", panel.unitCustomAnchorClearButton, "RIGHT", 12, 0)
            panel.unitCustomAnchorValueText:SetPoint("RIGHT", g, "RIGHT", -10, 0)
            panel.unitCustomAnchorValueText:SetJustifyH("LEFT")
        end
    end

    -- Status icons
    local showStatus = (currentKey == "player" or currentKey == "target")
    if panel._msufStatusIconsGroup then panel._msufStatusIconsGroup:SetShown(showStatus) end
    if not showStatus then
        for _, def in ipairs(STATUS_ICON_DEFS) do
            for _, sfx in ipairs(STATUS_WIDGET_SUFFIXES) do SW(def.prefix..sfx, false) end
        end
        for _, w in ipairs({ "statusIconsTestModeCB","statusIconsStyleCB","statusIconsHeader" }) do SW(w, false) end
    else
        SW("statusIconsHeader", false)
        local sBase, sStep = -34, -30
        for _, def in ipairs(STATUS_ICON_DEFS) do
            local show = def.allowed(currentKey)
            local p = def.prefix
            SW(p.."GroupDivider", false); SW(p.."AnchorLabel", false); SW(p.."SizeLabel", false); SW(p.."SymbolLabel", false)
            for _, sfx in ipairs({ "IconCB","ResetBtn","OffsetXStepper","OffsetYStepper","AnchorDrop","SizeEdit","LayerSlider","SymbolDrop" }) do SW(p..sfx, show) end
            if show then
                local cb = panel[p.."IconCB"]
                if cb then cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", panel._msufStatusIconsGroup, "TOPLEFT", 12, sBase + def.rowIndex * sStep) end
                local sx = panel[p.."OffsetXStepper"]
                if sx then sx:ClearAllPoints(); sx:SetPoint("TOPLEFT", panel._msufStatusIconsGroup, "TOPLEFT", colX, sBase - 2 + def.rowIndex * sStep) end
                local reset = panel[p.."ResetBtn"]
                if reset then
                    reset:ClearAllPoints()
                    local tail = panel[p.."LayerSlider"] or panel[p.."SizeEdit"]
                    if tail then reset:SetPoint("LEFT", tail, "RIGHT", 24, 0) end
                    reset:Show()
                end
            end
        end
        -- Symbol pickers below the rows
        local baseRel = panel.statusIncomingResIconCB or panel.statusCombatIconCB
        if baseRel then
            local pickerDefs = {}
            for _, def in ipairs(STATUS_ICON_DEFS) do
                pickerDefs[#pickerDefs + 1] = { label = panel[def.prefix.."SymbolLabel"], drop = panel[def.prefix.."SymbolDrop"], title = def.pickerTitle, show = def.allowed(currentKey) }
            end
            local xOff = 0
            for _, pd in ipairs(pickerDefs) do
                if pd.show and pd.label and pd.drop then
                    pd.label:SetText(pd.title); pd.label:ClearAllPoints()
                    pd.label:SetPoint("TOPLEFT", baseRel, "BOTTOMLEFT", 2 + xOff, -8); pd.label:Show()
                    pd.drop:ClearAllPoints(); pd.drop:SetPoint("TOPLEFT", pd.label, "BOTTOMLEFT", -12, -4); pd.drop:Show()
                    xOff = xOff + 138
                else
                    if pd.label then pd.label:Hide() end
                    if pd.drop then pd.drop:Hide() end
                end
            end
            local toggleAnchor = pickerDefs[#pickerDefs] and pickerDefs[#pickerDefs].drop
            if panel.statusIconsTestModeCB then
                panel.statusIconsTestModeCB:Show(); panel.statusIconsTestModeCB:ClearAllPoints()
                if toggleAnchor then panel.statusIconsTestModeCB:SetPoint("LEFT", toggleAnchor, "RIGHT", 12, -2)
                else panel.statusIconsTestModeCB:SetPoint("TOPLEFT", panel._msufStatusIconsGroup, "TOPLEFT", 520, -132) end
                CBLabelRight(panel.statusIconsTestModeCB, "Test mode")
            end
            if panel.statusIconsStyleCB then
                panel.statusIconsStyleCB:Show(); panel.statusIconsStyleCB:ClearAllPoints()
                if panel.statusIconsTestModeCB and panel.statusIconsTestModeCB:IsShown() then
                    local a = (panel.statusIconsTestModeCB.Text and panel.statusIconsTestModeCB.Text:IsShown()) and panel.statusIconsTestModeCB.Text or panel.statusIconsTestModeCB
                    panel.statusIconsStyleCB:SetPoint("LEFT", a, "RIGHT", 14, 0)
                elseif toggleAnchor then panel.statusIconsStyleCB:SetPoint("LEFT", toggleAnchor, "RIGHT", 112, -2) end
                CBLabelRight(panel.statusIconsStyleCB, "Midnight style")
            end
        end
    end

    -- Boss layout box
    local isBoss = (currentKey == "boss")
    if panel.playerBossLayoutBox then panel.playerBossLayoutBox:SetShown(isBoss) end
    local bossBody = panel.playerBossLayoutBody or panel.playerBossLayoutBox
    if panel.playerBossSpacingSlider then
        panel.playerBossSpacingSlider:SetShown(isBoss)
        if isBoss and bossBody then panel.playerBossSpacingSlider:ClearAllPoints(); panel.playerBossSpacingSlider:SetPoint("TOPLEFT", bossBody, "TOPLEFT", 12, -14) end
        if isBoss then
            if panel.playerBossSpacingSlider.editBox then panel.playerBossSpacingSlider.editBox:SetShown(isBoss) end
            if panel.playerBossSpacingSlider.minusButton then panel.playerBossSpacingSlider.minusButton:SetShown(isBoss) end
            if panel.playerBossSpacingSlider.plusButton then panel.playerBossSpacingSlider.plusButton:SetShown(isBoss) end
            local n = panel.playerBossSpacingSlider.GetName and panel.playerBossSpacingSlider:GetName()
            if n then for _, sfx in ipairs({"Low","High","Text"}) do local w = _G[n..sfx]; if w then w:SetShown(isBoss) end end end
        end
    end
    if panel.playerBossLayoutModeLabel then
        panel.playerBossLayoutModeLabel:SetShown(isBoss)
        if isBoss and bossBody then
            panel.playerBossLayoutModeLabel:ClearAllPoints()
            panel.playerBossLayoutModeLabel:SetPoint("TOPLEFT", bossBody, "TOPLEFT", 14, -50)
        end
    end
    if panel.playerBossLayoutModeDD then
        panel.playerBossLayoutModeDD:SetShown(isBoss)
        if isBoss and bossBody then
            panel.playerBossLayoutModeDD:ClearAllPoints()
            panel.playerBossLayoutModeDD:SetPoint("TOPLEFT", bossBody, "TOPLEFT", -6, -64)
        end
    end
    if panel.playerBossTargetHLCB then panel.playerBossTargetHLCB:SetShown(isBoss)
        if isBoss and bossBody then panel.playerBossTargetHLCB:ClearAllPoints(); panel.playerBossTargetHLCB:SetPoint("TOPLEFT", bossBody, "TOPLEFT", 12, -96) end end

    if panel._msufFramesScrollUpdate then panel._msufFramesScrollUpdate() end
end

--------------------------------------------------------------------
-- APPLY FROM DB
--------------------------------------------------------------------
function ns.MSUF_Options_Player_ApplyFromDB(panel, currentKey, conf, g, GetOffsetValue)
    if not panel or not currentKey then return end
    EnsureDB()
    MSUF_DB = MSUF_DB or {}; MSUF_DB.general = MSUF_DB.general or {}
    g = MSUF_DB.general
    local key = CanonKey(currentKey) or currentKey
    MSUF_DB[key] = MSUF_DB[key] or conf or {}
    conf = MSUF_DB[key]; currentKey = key
    panel._msufLastApplyKey = currentKey

    local isPlayer = (key == "player"); local isTarget = (key == "target")
    local isFocus = (key == "focus"); local isBoss = (key == "boss")
    local isToT = (key == "targettarget"); local isPet = (key == "pet")
    local isFrames = (panel._msufIsFramesTab and panel._msufIsFramesTab()) or true

    -- Basics box height
    if panel.playerBasicsBox then
        panel.playerBasicsBox._msufExpandedH = panel._msufBasicsH or 132
        if not panel.playerBasicsBox._msufCollapsed then panel.playerBasicsBox:SetHeight(panel._msufBasicsH or 132) end
    end
    if panel.playerCastbarBox then
        panel.playerCastbarBox._msufExpandedH = 132
        if not panel.playerCastbarBox._msufCollapsed then panel.playerCastbarBox:SetHeight(132) end
    end
    if panel.playerSizeBox and panel.playerSizeBox._msufTitleText then panel.playerSizeBox._msufTitleText:SetText("Transparency") end

    -- Basic checkboxes
    local BASIC_EVALS = {
        { "playerEnableFrameCB", function(c) return c.enabled ~= false end },
        { "playerShowNameCB", function(c) return c.showName ~= false end },
        { "playerShowHPCB", function(c) return c.showHP ~= false end },
        { "playerShowPowerCB", function(c) return c.showPower ~= false end },
        { "playerReverseFillBarsCB", function(c) return c.reverseFillBars == true end },
        { "playerSmoothFillCB", function(c) return c.smoothFill ~= false end },
    }
    for _, s in ipairs(BASIC_EVALS) do
        local w = panel[s[1]]; if w and w.SetChecked then w:SetChecked(s[2](conf)) end
    end

    -- Power Bar sync
    do
        MSUF_DB.bars = MSUF_DB.bars or {}
        local b = MSUF_DB.bars
        local showKey = isPlayer and "showPlayerPowerBar" or isTarget and "showTargetPowerBar"
            or isFocus and "showFocusPowerBar" or isBoss and "showBossPowerBar" or nil
        local showPB = (isPlayer or isTarget or isFocus or isBoss)
        if panel.playerPowerBarBox then panel.playerPowerBarBox:SetShown(showPB and isFrames) end
        if panel.playerPowerBarShowCB and showKey then
            panel.playerPowerBarShowCB:SetChecked(b[showKey] ~= false)
        end
        if panel.playerPowerBarHeightSlider then
            local h = tonumber(b.powerBarHeight) or 6; if h < 1 then h = 1 elseif h > 20 then h = 20 end
            panel.playerPowerBarHeightSlider:SetValue(h)
        end
        if panel.playerPowerBarEmbedCB then panel.playerPowerBarEmbedCB:SetChecked(b.embedPowerBarIntoHealth == true) end
        if panel.playerPowerBarBorderCB then panel.playerPowerBarBorderCB:SetChecked(b.powerBarBorderEnabled == true) end
        if panel.playerPowerBarBorderSlider then
            local t = tonumber(b.powerBarBorderThickness) or 1; if t < 0 then t = 0 elseif t > 6 then t = 6 end
            panel.playerPowerBarBorderSlider:SetValue(t)
        end
        if panel.playerPowerBarSmoothCB then
            panel.playerPowerBarSmoothCB:SetChecked(ReadPowerSmoothFill(conf, key))
        end
    end

    -- ToT inline
    if panel.totShowInTargetCB then
        panel.totShowInTargetCB:SetShown(isToT and isFrames)
        if isToT and isFrames then panel.totShowInTargetCB:SetChecked(conf.showToTInTargetName == true) end
        if panel.playerCastbarBody and panel.totShowInTargetCB:GetParent() ~= panel.playerCastbarBody then
            panel.totShowInTargetCB:SetParent(panel.playerCastbarBody)
        end
        if panel.playerCastbarBody then
            panel.totShowInTargetCB:ClearAllPoints()
            panel.totShowInTargetCB:SetPoint("TOPLEFT", panel.playerCastbarBody, "TOPLEFT", 12, -6)
        end
    end
    if panel.totInlineSeparatorDD then
        local show = isToT and isFrames
        panel.totInlineSeparatorDD:SetShown(show)
        if panel.playerCastbarBody and panel.totInlineSeparatorDD:GetParent() ~= panel.playerCastbarBody then
            panel.totInlineSeparatorDD:SetParent(panel.playerCastbarBody)
        end
        if show then
            if panel.totShowInTargetCB then
                panel.totInlineSeparatorDD:ClearAllPoints()
                panel.totInlineSeparatorDD:SetPoint("TOPLEFT", panel.totShowInTargetCB, "BOTTOMLEFT", -18, -6)
            end
            local token = ToTSepText(ReadStr(conf, g, "totInlineSeparator", "|"))
            if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(panel.totInlineSeparatorDD, token) end
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(panel.totInlineSeparatorDD, token) end
            local enabled = (conf.showToTInTargetName == true)
            if UIDropDownMenu_EnableDropDown and UIDropDownMenu_DisableDropDown then
                if enabled then UIDropDownMenu_EnableDropDown(panel.totInlineSeparatorDD) else UIDropDownMenu_DisableDropDown(panel.totInlineSeparatorDD) end
            elseif panel.totInlineSeparatorDD.Button then
                if enabled and panel.totInlineSeparatorDD.Button.Enable then panel.totInlineSeparatorDD.Button:Enable() end
                if not enabled and panel.totInlineSeparatorDD.Button.Disable then panel.totInlineSeparatorDD.Button:Disable() end
            end
        end
    end

    -- Anchoring
    local showAnch = isFrames and (isPlayer or isTarget or isFocus or isBoss or isPet or isToT)
    if panel.unitAnchorToDD then panel.unitAnchorToDD:SetShown(showAnch) end
    if showAnch then
        local v = conf.anchorToUnitframe
        if v ~= "player" and v ~= "target" and v ~= "focus" and v ~= "pet" and v ~= "targettarget" then v = "GLOBAL" end
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(panel.unitAnchorToDD, v) end
        if UIDropDownMenu_SetText then
            local txt = ({ player = "Player frame", target = "Target frame", focus = "Focus frame", pet = "Pet frame", targettarget = "Target of Target frame" })[v] or "Free (global anchor)"
            UIDropDownMenu_SetText(panel.unitAnchorToDD, txt)
        end
        if panel.unitCustomAnchorValueText then
            local an = (type(conf.anchorFrameName) == "string" and conf.anchorFrameName) or ""
            panel.unitCustomAnchorValueText:SetText(TR("Current custom anchor: ") .. (an ~= "" and an or "none"))
        end
    end

    -- Indicators title
    if panel.playerTextLayoutGroup and panel.playerTextLayoutGroup._msufTitleText then
        panel.playerTextLayoutGroup._msufTitleText:SetText(TR("Indicators")); panel.playerTextLayoutGroup._msufTitleText:Show()
    end

    -- Load conditions
    local lcSpecs = panel._msufLoadCondSpecs
    if lcSpecs then
        for _, s in ipairs(lcSpecs) do
            local cb = panel[s[1]]; if cb and cb.SetChecked then cb:SetChecked(conf[s[2]] == true) end
        end
    end
    local lcR = _G.MSUF_LoadCond_RecomputeActive; if type(lcR) == "function" then lcR(conf) end
    if panel.playerLoadCondBox and panel.playerLoadCondBox._msufTitleText then panel.playerLoadCondBox._msufTitleText:SetText("Load Conditions") end

    -- Alpha
    local excludeTP = (conf.alphaExcludeTextPortrait == true)
    if panel.playerAlphaExcludeTextPortraitCB then panel.playerAlphaExcludeTextPortraitCB:SetChecked(excludeTP) end
    if Alpha_NormalizeMode then
        local layerMode = Alpha_NormalizeMode(conf.alphaLayerMode)
        if panel.playerAlphaLayerDropDown and UIDropDownMenu_SetSelectedValue and UIDropDownMenu_SetText then
            panel.playerAlphaLayerDropDown:Show()
            UIDropDownMenu_SetSelectedValue(panel.playerAlphaLayerDropDown, layerMode)
            UIDropDownMenu_SetText(panel.playerAlphaLayerDropDown, layerMode == "background" and "Background" or "Foreground")
            local btn = (_G["MSUF_UF_AlphaLayerDropDownButton"]) or (panel.playerAlphaLayerDropDown and panel.playerAlphaLayerDropDown.Button)
            if btn then if excludeTP then if btn.Enable then btn:Enable() end else if btn.Disable then btn:Disable() end end end
            if panel.playerAlphaLayerDropDown.Text and panel.playerAlphaLayerDropDown.Text.SetTextColor then
                panel.playerAlphaLayerDropDown.Text:SetTextColor(excludeTP and 1 or 0.5, excludeTP and 1 or 0.5, excludeTP and 1 or 0.5)
            end
        end
        if panel.playerAlphaSyncCB then panel.playerAlphaSyncCB:SetChecked(conf.alphaSync == true) end
        local aIn, aOut = Alpha_ReadPair(conf, Alpha_NormalizeMode(conf.alphaLayerMode))
        if AlphaUI_SetSlider then AlphaUI_SetSlider(panel.playerAlphaInCombatSlider, aIn); AlphaUI_SetSlider(panel.playerAlphaOutCombatSlider, aOut) end
    end

    -- Boss
    if panel.playerBossSpacingSlider then
        panel.playerBossSpacingSlider:SetShown(isBoss)
        if isBoss then
            panel.playerBossSpacingSlider.MSUF_SkipCallback = true
            panel.playerBossSpacingSlider:SetValue(conf.spacing or -36)
            panel.playerBossSpacingSlider.MSUF_SkipCallback = false
            ForceSliderEB(panel.playerBossSpacingSlider)
        end
    end
    if panel.playerBossLayoutModeLabel then panel.playerBossLayoutModeLabel:SetShown(isBoss) end
    if panel.playerBossLayoutModeDD and UIDropDownMenu_SetSelectedValue and UIDropDownMenu_SetText then
        panel.playerBossLayoutModeDD:SetShown(isBoss)
        if isBoss then
            local mode = BossLayoutMode_Normalize(conf.bossLayoutMode, conf.invertBossOrder)
            UIDropDownMenu_SetSelectedValue(panel.playerBossLayoutModeDD, mode)
            UIDropDownMenu_SetText(panel.playerBossLayoutModeDD, BossLayoutMode_Text(mode))
        end
    end
    if panel.playerBossTargetHLCB then panel.playerBossTargetHLCB:SetShown(isBoss); if isBoss then panel.playerBossTargetHLCB:SetChecked(g.bossTargetHighlightEnabled ~= false) end end

    -- Portrait
    if panel.playerPortraitDropDown and UIDropDownMenu_SetSelectedValue and UIDropDownMenu_SetText then
        panel.playerPortraitDropDown:Show()
        local mode = GetPortraitVal(conf)
        UIDropDownMenu_SetSelectedValue(panel.playerPortraitDropDown, mode)
        UIDropDownMenu_SetText(panel.playerPortraitDropDown, PortraitText(mode))
    end

    -- Castbar toggles
    local function ApplyCheck(wk, show, checked)
        local w = panel[wk]; if not w then return end
        w:SetShown(show); if show and w.SetChecked then w:SetChecked(checked) end
    end
    for _, spec in ipairs(CASTBAR_TOGGLE_SPECS) do
        local show = isFrames and currentKey == spec.key
        ApplyCheck(spec.enableW, show, g[spec.enableK] ~= false)
        ApplyCheck(spec.timeW, show, g[spec.timeK] ~= false)
        ApplyCheck(spec.interruptW, show, conf.showInterrupt ~= false)
    end
    local function GetShowFallback(stored, fallback) if stored == nil then return fallback ~= false end; return stored ~= false end
    for _, spec in ipairs(CASTBAR_TEXTICON_SPECS) do
        local show = isFrames and currentKey == spec.key
        ApplyCheck(spec.iconW, show, GetShowFallback(g[spec.iconK], g.castbarShowIcon))
        local tc; if spec.textDirect then tc = g[spec.textK] ~= false else tc = GetShowFallback(g[spec.textK], g.castbarShowSpellName) end
        ApplyCheck(spec.textW, show, tc)
    end
    -- Castbar box
    if panel.playerCastbarBox then
        panel.playerCastbarBox:SetShown(isFrames and (isPlayer or isTarget or isFocus or isBoss or isToT))
        if panel.playerCastbarBox._msufTitleText then
            panel.playerCastbarBox._msufTitleText:SetText(TR(isToT and "Inline Text" or "Castbar"))
        end
    end
    -- Reposition castbar checkboxes
    for _, k in ipairs({ "player","target","focus","boss" }) do
        local en = panel[k.."CastbarEnableCB"]; if en and en:IsShown() then en:ClearAllPoints(); en:SetPoint("TOPLEFT", panel.playerCastbarBody or panel.playerCastbarBox, "TOPLEFT", 12, -6) end
        local tm = panel[k.."CastbarTimeCB"]; if tm and tm:IsShown() then tm:ClearAllPoints(); tm:SetPoint("TOPLEFT", panel.playerCastbarBody or panel.playerCastbarBox, "TOPLEFT", 12, -30) end
        local ic = panel[k.."CastbarInterruptCB"]; if ic and ic:IsShown() then ic:ClearAllPoints(); ic:SetPoint("TOPLEFT", panel.playerCastbarBody or panel.playerCastbarBox, "TOPLEFT", 12, -54) end
        local ico = panel[k.."CastbarShowIconCB"]; if ico and ico:IsShown() then ico:ClearAllPoints(); ico:SetPoint("TOPRIGHT", panel.playerCastbarBody or panel.playerCastbarBox, "TOPRIGHT", -112, -6); CBLabelLeft(ico, "Icon") end
        local txt = panel[k.."CastbarShowTextCB"]; if txt and txt:IsShown() then txt:ClearAllPoints(); txt:SetPoint("TOPRIGHT", panel.playerCastbarBody or panel.playerCastbarBox, "TOPRIGHT", -36, -6); CBLabelLeft(txt, "Text") end
    end

    -- Indicators
    for _, id in ipairs(INDICATOR_ORDER) do
        local spec = INDICATOR_SPECS[id]; if not spec then break end
        if spec.showCB and spec.showField and panel[spec.showCB] then panel[spec.showCB]:SetChecked(ReadBool(conf, g, spec.showField, spec.showDefault)) end
        if spec.xStepper and panel[spec.xStepper] and panel[spec.xStepper].SetValue then panel[spec.xStepper]:SetValue(ReadNum(conf, g, spec.xField, spec.xDefault), false) end
        if spec.yStepper and panel[spec.yStepper] and panel[spec.yStepper].SetValue then panel[spec.yStepper]:SetValue(ReadNum(conf, g, spec.yField, spec.yDefault), false) end
        if spec.anchorDrop and panel[spec.anchorDrop] then
            local v = ReadStr(conf, g, spec.anchorField, spec.anchorDefault)
            if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(panel[spec.anchorDrop], v) end
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(panel[spec.anchorDrop], spec.anchorText(v)) end
        end
        if spec.sizeEdit and panel[spec.sizeEdit] then SetNumericEB(panel[spec.sizeEdit], ReadNum(conf, g, spec.sizeField, spec.sizeDefault)) end
        if spec.layerSlider and panel[spec.layerSlider] and panel[spec.layerSlider].MSUF_SetValueSilent then
            panel[spec.layerSlider]:MSUF_SetValueSilent(ReadNum(conf, g, spec.layerField, spec.layerDefault or 7))
        end
    end

    -- Text group height
    if panel.playerTextLayoutGroup and panel._msufTextBaseH then
        local h = panel._msufTextBaseH + (isToT and 28 or 0)
        panel.playerTextLayoutGroup._msufExpandedH = h
        if not panel.playerTextLayoutGroup._msufCollapsed then panel.playerTextLayoutGroup:SetHeight(h) end
    end
    -- Status box height
    if panel._msufStatusIconsGroup and panel._msufStatusBoxH then
        panel._msufStatusIconsGroup._msufExpandedH = panel._msufStatusBoxH
        if not panel._msufStatusIconsGroup._msufCollapsed then panel._msufStatusIconsGroup:SetHeight(panel._msufStatusBoxH) end
        panel._msufStatusIconsGroup:SetShown(isPlayer or isTarget)
    end
    if panel.playerSizeBox and panel._msufSizeBaseH and not panel.playerSizeBox._msufCollapsed then
        panel.playerSizeBox:SetHeight(panel._msufSizeBaseH)
    end

    -- Layout reflow
    if ns.MSUF_Options_Player_LayoutIndicatorTemplate then ns.MSUF_Options_Player_LayoutIndicatorTemplate(panel, currentKey) end

    -- Copy visibility
    local function SetCopyVis(prefix, destVar, def, active)
        for _, sfx in ipairs({ "CopyToLabel","CopyToButton","CopyToHint" }) do
            local w = panel[prefix..sfx]; if w then w:SetShown(active) end
        end
        local drop = panel[prefix.."CopyToDrop"]
        if drop then
            drop:SetShown(active)
            if active then
                local k = panel[destVar] or def; panel[destVar] = k
                if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(drop, k) end
                local label = (_G._MSUF_CopyDestLabel and _G._MSUF_CopyDestLabel(k)) or tostring(k)
                if UIDropDownMenu_SetText then UIDropDownMenu_SetText(drop, label) end
            end
        end
    end
    SetCopyVis("player","_msufCopyDestKey","target",isPlayer and isFrames)
    SetCopyVis("target","_msufCopyDestKey_target","player",isTarget and isFrames)
    SetCopyVis("focus","_msufCopyDestKey_focus","target",isFocus and isFrames)
    SetCopyVis("boss","_msufCopyDestKey_boss","target",isBoss and isFrames)
    SetCopyVis("pet","_msufCopyDestKey_pet","target",isPet and isFrames)
    SetCopyVis("tot","_msufCopyDestKey_tot","player",isToT and isFrames)

    if panel._msufRelayoutUnitBoxes then panel._msufRelayoutUnitBoxes(currentKey) end
    if panel._msufBindCopyButtons then panel._msufBindCopyButtons() end
end

--------------------------------------------------------------------
-- INSTALL HANDLERS
--------------------------------------------------------------------
function ns.MSUF_Options_Player_InstallHandlers(panel, api)
    if not panel or not api then return end

    local function IsFramesTab()
        if not api.getTabKey then return true end
        local k = api.getTabKey()
        return (k == nil) or (k == "frames") or (k == "player") or (k == "unitframes")
    end
    local function CurrentKey() return (api.getKey and api.getKey()) or "player" end
    panel._msufGetCurrentKey = CurrentKey
    panel._msufIsFramesTab = IsFramesTab
    panel._msufAPI = api

    local function ApplyCurrent() if api.ApplySettingsForKey then api.ApplySettingsForKey(CurrentKey()) end end
    local function ApplyLayout(reason)
        local key = CurrentKey()
        local fn = _G.MSUF_UFCore_RequestLayoutForUnit
        if type(fn) == "function" then pcall(fn, key, reason or "OPTIONS_LAYOUT", key == "target" or key == "targettarget" or key == "focus") end
        ApplyCurrent()
    end
    local function EnsureKeyDB()
        if api.EnsureDB then api.EnsureDB() end
        local key = CanonKey(CurrentKey()) or "player"
        panel._msufLastApplyKey = key; MSUF_DB[key] = MSUF_DB[key] or {}
        return MSUF_DB[key]
    end
    local function GetConfAndG()
        EnsureDB(); MSUF_DB = MSUF_DB or {}; MSUF_DB.general = MSUF_DB.general or {}
        local key = CanonKey(CurrentKey()) or "player"
        MSUF_DB[key] = MSUF_DB[key] or {}
        return MSUF_DB[key], MSUF_DB.general, key
    end

    -- Alpha system
    Alpha_NormalizeMode = function(mode)
        if mode == true or mode == 1 or mode == "background" then return "background" end
        return "foreground"
    end
    Alpha_GetKeys = function(conf, mode)
        mode = Alpha_NormalizeMode(mode)
        if conf and conf.alphaExcludeTextPortrait == true then
            if mode == "background" then return "alphaBGInCombat","alphaBGOutOfCombat" end
            return "alphaFGInCombat","alphaFGOutOfCombat"
        end
        return "alphaInCombat","alphaOutOfCombat"
    end
    Alpha_ReadPair = function(conf, mode)
        if not conf then return 1, 1 end
        mode = Alpha_NormalizeMode(mode)
        local aIn = tonumber(conf.alphaInCombat) or 1
        local aOut = tonumber(conf.alphaOutOfCombat) or 1
        if conf.alphaExcludeTextPortrait == true then
            if mode == "background" then
                aIn = tonumber(conf.alphaBGInCombat) or aIn; aOut = tonumber(conf.alphaBGOutOfCombat) or aOut
            else
                aIn = tonumber(conf.alphaFGInCombat) or aIn; aOut = tonumber(conf.alphaFGOutOfCombat) or aOut
            end
        end
        if conf.alphaSync == true then aOut = aIn end
        return aIn, aOut
    end
    Alpha_WritePair = function(conf, mode, aIn, aOut)
        if not conf then return end
        local kIn, kOut = Alpha_GetKeys(conf, mode); conf[kIn] = aIn; conf[kOut] = aOut
    end
    AlphaUI_SetSlider = function(s, v)
        if s and s.SetValue then s.MSUF_SkipCallback = true; s:SetValue(v); s.MSUF_SkipCallback = false; if s.editBox then ForceSliderEB(s) end end
    end
    AlphaUI_RefreshSliders = function()
        if not IsFramesTab() then return end
        local conf = EnsureKeyDB()
        local mode = Alpha_NormalizeMode(conf.alphaLayerMode)
        local aIn, aOut = Alpha_ReadPair(conf, mode)
        AlphaUI_SetSlider(panel.playerAlphaInCombatSlider, aIn)
        AlphaUI_SetSlider(panel.playerAlphaOutCombatSlider, aOut)
    end
    local function ApplyAlpha()
        local fn = _G.MSUF_RefreshAllUnitAlphas; if type(fn) == "function" then pcall(fn) end
    end

    -- Basic checkboxes
    for _, pair in ipairs({ {"playerEnableFrameCB","enabled"},{"playerShowNameCB","showName"},{"playerShowHPCB","showHP"},{"playerShowPowerCB","showPower"},{"playerReverseFillBarsCB","reverseFillBars"},{"playerSmoothFillCB","smoothFill"} }) do
        local w = panel[pair[1]]; if w then
            w:SetScript("OnClick", function(self) if not IsFramesTab() then return end
                local c = EnsureKeyDB(); c[pair[2]] = self:GetChecked() and true or false; ApplyCurrent()
                if _G.MSUF_SyncUnitPositionPopup then _G.MSUF_SyncUnitPositionPopup(CurrentKey(), c) end end)
        end
    end

    -- Power Bar controls
    do
        local PB_KEY_MAP = { player = "showPlayerPowerBar", target = "showTargetPowerBar",
            focus = "showFocusPowerBar", boss = "showBossPowerBar" }
        local function PBApply()
            if _G.MSUF_ApplyPowerBarEmbedLayout_All then _G.MSUF_ApplyPowerBarEmbedLayout_All() end
            if _G.MSUF_ApplyPowerBarBorder_All then _G.MSUF_ApplyPowerBarBorder_All() end
            ApplyCurrent()
        end
        local function PBBars() EnsureDB(); MSUF_DB.bars = MSUF_DB.bars or {}; return MSUF_DB.bars end
        if panel.playerPowerBarShowCB then
            panel.playerPowerBarShowCB:SetScript("OnClick", function(self)
                local k = CanonKey(CurrentKey()); local bk = PB_KEY_MAP[k]; if not bk then return end
                PBBars()[bk] = self:GetChecked() and true or false; PBApply()
            end)
        end
        if panel.playerPowerBarHeightSlider then
            panel.playerPowerBarHeightSlider:SetScript("OnValueChanged", function(self, v)
                v = math.floor(v + 0.5); PBBars().powerBarHeight = v; PBApply()
            end)
        end
        if panel.playerPowerBarEmbedCB then
            panel.playerPowerBarEmbedCB:SetScript("OnClick", function(self)
                PBBars().embedPowerBarIntoHealth = self:GetChecked() and true or false; PBApply()
            end)
        end
        if panel.playerPowerBarBorderCB then
            panel.playerPowerBarBorderCB:SetScript("OnClick", function(self)
                PBBars().powerBarBorderEnabled = self:GetChecked() and true or false; PBApply()
            end)
        end
        if panel.playerPowerBarBorderSlider then
            panel.playerPowerBarBorderSlider:SetScript("OnValueChanged", function(self, v)
                v = math.floor(v + 0.5); PBBars().powerBarBorderThickness = v; PBApply()
            end)
        end
        if panel.playerPowerBarSmoothCB then
            panel.playerPowerBarSmoothCB:SetScript("OnClick", function(self)
                local k = CanonKey(CurrentKey()); if not (k == "player" or k == "target" or k == "focus" or k == "boss") then return end
                EnsureKeyDB().powerSmoothFill = self:GetChecked() and true or false
                PBApply()
            end)
        end
    end

    -- Portrait dropdown
    if panel.playerPortraitDropDown and UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(panel.playerPortraitDropDown, function(_, level)
            if not level or level ~= 1 then return end
            for _, opt in ipairs(PORTRAIT_OPTIONS) do
                local info = UIDropDownMenu_CreateInfo()
                info.text, info.value = opt.text, opt.value
                info.func = function(btn)
                    if not IsFramesTab() then return end
                    local c = EnsureKeyDB(); local choice = (btn and btn.value) or "OFF"
                    c.portraitMode = (choice == "LEFT" or choice == "RIGHT") and choice or "OFF"
                    local cur = GetPortraitVal(c)
                    if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(panel.playerPortraitDropDown, cur) end
                    if UIDropDownMenu_SetText then UIDropDownMenu_SetText(panel.playerPortraitDropDown, PortraitText(cur)) end
                    ApplyCurrent()
                    local sync = _G.MSUF_3DPortraits_SyncUnit
                    if type(sync) == "function" then pcall(sync, CurrentKey()) end
                end
                info.checked = function() return GetPortraitVal(EnsureKeyDB()) == opt.value end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
    end

    -- Alpha controls
    if panel.playerAlphaSyncCB then panel.playerAlphaSyncCB:SetScript("OnClick", function(self)
        if not IsFramesTab() then return end
        local c = EnsureKeyDB(); c.alphaSync = self:GetChecked() and true or false
        local mode = Alpha_NormalizeMode(c.alphaLayerMode)
        local aIn, aOut = Alpha_ReadPair(c, mode)
        if c.alphaSync then aOut = aIn; Alpha_WritePair(c, mode, aIn, aOut) end
        AlphaUI_RefreshSliders(); ApplyAlpha()
    end) end

    if panel.playerAlphaExcludeTextPortraitCB then panel.playerAlphaExcludeTextPortraitCB:SetScript("OnClick", function(self)
        if not IsFramesTab() then return end
        local c = EnsureKeyDB(); local on = self:GetChecked() and true or false; c.alphaExcludeTextPortrait = on
        if on and c.alphaLayerMode == nil then c.alphaLayerMode = 0 end
        local dd = panel.playerAlphaLayerDropDown
        if dd then
            local btn = (_G["MSUF_UF_AlphaLayerDropDownButton"]) or (dd and dd.Button)
            if btn then if on then if btn.Enable then btn:Enable() end else if btn.Disable then btn:Disable() end end end
            if dd.Text and dd.Text.SetTextColor then dd.Text:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5) end
        end
        AlphaUI_RefreshSliders(); ApplyAlpha()
    end) end

    if panel.playerAlphaLayerDropDown and UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(panel.playerAlphaLayerDropDown, function(_, level)
            if not IsFramesTab() then return end
            local c = EnsureKeyDB()
            local cur = Alpha_NormalizeMode(c.alphaLayerMode)
            UIDropDownMenu_SetSelectedValue(panel.playerAlphaLayerDropDown, cur)
            UIDropDownMenu_SetText(panel.playerAlphaLayerDropDown, cur == "background" and "Background" or "Foreground")
            for _, pair in ipairs({ {"foreground","Foreground"},{"background","Background"} }) do
                local info = UIDropDownMenu_CreateInfo()
                info.text, info.value = pair[2], pair[1]
                info.checked = function() return Alpha_NormalizeMode(EnsureKeyDB().alphaLayerMode) == pair[1] end
                info.disabled = (c.alphaExcludeTextPortrait ~= true)
                info.func = function()
                    if not IsFramesTab() then return end
                    local c2 = EnsureKeyDB(); c2.alphaLayerMode = pair[1] == "background" and 1 or 0
                    UIDropDownMenu_SetSelectedValue(panel.playerAlphaLayerDropDown, pair[1])
                    UIDropDownMenu_SetText(panel.playerAlphaLayerDropDown, pair[2])
                    if CloseDropDownMenus then CloseDropDownMenus() end
                    AlphaUI_RefreshSliders(); ApplyAlpha()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
    end

    local ALPHA_SPECS = {
        { field = "playerAlphaInCombatSlider", isInCombat = true, other = "playerAlphaOutCombatSlider" },
        { field = "playerAlphaOutCombatSlider", isInCombat = false, other = "playerAlphaInCombatSlider" },
    }
    for _, spec in ipairs(ALPHA_SPECS) do
        local s = panel[spec.field]; if not s then break end
        s.onValueChanged = function(self, value)
            if self.MSUF_SkipCallback or not IsFramesTab() then return end
            local c = EnsureKeyDB(); local mode = Alpha_NormalizeMode(c.alphaLayerMode)
            local v = tonumber(value) or 1; v = max(0, min(1, v))
            local aIn, aOut = Alpha_ReadPair(c, mode)
            if spec.isInCombat then aIn = v else aOut = v end
            if c.alphaSync then aOut = aIn; AlphaUI_SetSlider(panel[spec.other], aOut) end
            Alpha_WritePair(c, mode, aIn, aOut); ApplyAlpha()
        end
        if s.HookScript then s:HookScript("OnShow", function() ForceSliderEB(s) end) end
    end

    -- Boss controls
    local bs = panel.playerBossSpacingSlider
    if bs then
        bs.onValueChanged = function(self, value)
            if not IsFramesTab() or CurrentKey() ~= "boss" then return end
            EnsureKeyDB().spacing = floor((tonumber(value) or 0) + 0.5); ApplyCurrent()
        end
        if bs.HookScript then bs:HookScript("OnShow", function() ForceSliderEB(bs) end) end
    end
    if panel.playerBossLayoutModeDD and UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(panel.playerBossLayoutModeDD, function(_, level)
            if not IsFramesTab() or CurrentKey() ~= "boss" then return end
            local c = EnsureKeyDB()
            local cur = BossLayoutMode_Normalize(c.bossLayoutMode, c.invertBossOrder)
            UIDropDownMenu_SetSelectedValue(panel.playerBossLayoutModeDD, cur)
            UIDropDownMenu_SetText(panel.playerBossLayoutModeDD, BossLayoutMode_Text(cur))
            for i = 1, #BOSS_LAYOUT_OPTIONS do
                local opt = BOSS_LAYOUT_OPTIONS[i]
                local info = UIDropDownMenu_CreateInfo()
                info.text, info.value = TR(opt.text), opt.value
                info.checked = (cur == opt.value)
                info.func = function()
                    if not IsFramesTab() or CurrentKey() ~= "boss" then return end
                    local c2 = EnsureKeyDB()
                    c2.bossLayoutMode = opt.value
                    -- Keep legacy field roughly in sync for any third-party code that may still read it.
                    c2.invertBossOrder = (opt.value == "VERTICAL_UP")
                    UIDropDownMenu_SetSelectedValue(panel.playerBossLayoutModeDD, opt.value)
                    UIDropDownMenu_SetText(panel.playerBossLayoutModeDD, BossLayoutMode_Text(opt.value))
                    if CloseDropDownMenus then CloseDropDownMenus() end
                    ApplyCurrent()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
    end
    if panel.playerBossTargetHLCB then panel.playerBossTargetHLCB:SetScript("OnClick", function(self)
        EnsureDB(); MSUF_DB.general = MSUF_DB.general or {}
        local on = self:GetChecked() and true or false
        MSUF_DB.general.bossTargetHighlightEnabled = on; MSUF_DB.general.bossTargetOutlineMode = on and 1 or 0
        if _G.MSUF_UFCore_RefreshSettingsCache then _G.MSUF_UFCore_RefreshSettingsCache("BOSS_TARGET_HL") end
        if _G.MSUF_UpdateBossTargetHighlight then _G.MSUF_UpdateBossTargetHighlight() end
    end) end

    -- Indicator binding (shared for both indicator rows and status icon rows)
    local function BindIndicatorRow(spec)
        if not spec then return end
        local function AllowedNow() local _, _, k = GetConfAndG(); return not spec.allowed or spec.allowed(k) end
        local function Refresh()
            -- ONLY call the dedicated layout helper (lightweight: reposition icon).
            -- Do NOT call ApplyLayout/ApplyCurrent here — the caller does that once.
            if spec.refreshFnName then local fn = _G[spec.refreshFnName]; if type(fn) == "function" then pcall(fn) end end
        end
        local function ApplyUI()
            if not IsFramesTab() then return end
            local conf2, g2, k2 = GetConfAndG()
            if spec.allowed and not spec.allowed(k2) then return end
            if spec.showCB and panel[spec.showCB] then panel[spec.showCB]:SetChecked(ReadBool(conf2, g2, spec.showField, spec.showDefault)) end
            if spec.xStepper and panel[spec.xStepper] then panel[spec.xStepper]:SetValue(ReadNum(conf2, g2, spec.xField, spec.xDefault), false) end
            if spec.yStepper and panel[spec.yStepper] then panel[spec.yStepper]:SetValue(ReadNum(conf2, g2, spec.yField, spec.yDefault), false) end
            if spec.anchorDrop and panel[spec.anchorDrop] then
                local a = ReadStr(conf2, g2, spec.anchorField, spec.anchorDefault)
                if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(panel[spec.anchorDrop], a) end
                if UIDropDownMenu_SetText and spec.anchorText then UIDropDownMenu_SetText(panel[spec.anchorDrop], spec.anchorText(a)) end
            end
            if spec.iconDrop and panel[spec.iconDrop] and spec.iconField then
                local v = ReadStr(conf2, g2, spec.iconField, spec.iconDefault)
                if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(panel[spec.iconDrop], v) end
                if UIDropDownMenu_SetText and spec.iconText then UIDropDownMenu_SetText(panel[spec.iconDrop], spec.iconText(v)) end
            end
            if spec.sizeEdit and panel[spec.sizeEdit] and spec.sizeField then
                local v = conf2[spec.sizeField]
                if type(v) ~= "number" and g2 then v = g2[spec.sizeField] end
                if type(v) ~= "number" and spec.id == "level" then v = ReadNum(conf2, g2, "nameFontSize", 14) end
                v = max(8, min(64, floor((tonumber(v) or spec.sizeDefault or 14) + 0.5)))
                SetNumericEB(panel[spec.sizeEdit], v)
            end
            if spec.layerSlider and panel[spec.layerSlider] and panel[spec.layerSlider].MSUF_SetValueSilent then
                panel[spec.layerSlider]:MSUF_SetValueSilent(ReadNum(conf2, g2, spec.layerField, spec.layerDefault or 7))
            end
        end

        -- Checkbox
        if spec.showCB and panel[spec.showCB] then
            panel[spec.showCB]:SetScript("OnClick", function(self)
                if not IsFramesTab() or not AllowedNow() then return end
                local c, _, k = GetConfAndG(); c[spec.showField] = self:GetChecked() and true or false
                Refresh()       -- lightweight layout helper only
                ApplyCurrent()  -- single coalesced apply
            end)
            panel[spec.showCB]:HookScript("OnShow", function() ApplyUI() end)
        end
        -- Steppers
        for _, pair in ipairs({ {spec.xStepper, spec.xField, spec.xDefault}, {spec.yStepper, spec.yField, spec.yDefault} }) do
            local st = panel[pair[1]]; if st then
                st.onValueChanged = function(_, v) if not IsFramesTab() or not AllowedNow() then return end; GetConfAndG()[pair[2]] = tonumber(v) or pair[3]; Refresh(); ApplyCurrent() end
                st:SetScript("OnShow", function() ApplyUI() end)
            end
        end
        -- Layer slider (draw order: 1-10, higher = above)
        if spec.layerSlider and panel[spec.layerSlider] and spec.layerField then
            local lsl = panel[spec.layerSlider]
            lsl.onValueChanged = function(_, v)
                if not IsFramesTab() or not AllowedNow() then return end
                GetConfAndG()[spec.layerField] = ClampLayerValue(v, spec.layerDefault or 7)
                Refresh(); ApplyCurrent()
            end
            lsl:SetScript("OnShow", function() ApplyUI() end)
        end
        -- Anchor dropdown
        if spec.anchorDrop and panel[spec.anchorDrop] and UIDropDownMenu_Initialize then
            local drop = panel[spec.anchorDrop]
            UIDropDownMenu_Initialize(drop, function(_, level)
                if not level or level ~= 1 or not AllowedNow() then return end
                for _, pair in ipairs(spec.anchorChoices or {}) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text, info.value = pair[1], pair[2]
                    info.func = function(btn)
                        if not IsFramesTab() then return end
                        local c2 = GetConfAndG(); c2[spec.anchorField] = (btn and btn.value) or spec.anchorDefault
                        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(drop, c2[spec.anchorField]) end
                        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(drop, spec.anchorText(c2[spec.anchorField])) end
                        if CloseDropDownMenus then CloseDropDownMenus() end; Refresh(); ApplyCurrent()
                    end
                    info.checked = function() return ReadStr(GetConfAndG(), nil, spec.anchorField, spec.anchorDefault) == pair[2] end
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
            drop:SetScript("OnShow", function() ApplyUI() end)
        end
        -- Icon dropdown
        if spec.iconDrop and panel[spec.iconDrop] and spec.iconField and UIDropDownMenu_Initialize then
            local drop2 = panel[spec.iconDrop]
            UIDropDownMenu_Initialize(drop2, function(_, level)
                if not level or level ~= 1 or not AllowedNow() then return end
                local choices = spec.iconChoices; if type(choices) == "function" then choices = choices() end
                for _, pair in ipairs(choices or {}) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text, info.value = pair[1], pair[2]
                    info.func = function(btn)
                        if not IsFramesTab() then return end
                        local c3 = GetConfAndG(); c3[spec.iconField] = (btn and btn.value) or spec.iconDefault
                        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(drop2, c3[spec.iconField]) end
                        if UIDropDownMenu_SetText and spec.iconText then UIDropDownMenu_SetText(drop2, spec.iconText(c3[spec.iconField])) end
                        if CloseDropDownMenus then CloseDropDownMenus() end; Refresh(); ApplyCurrent()
                    end
                    info.checked = function() return ReadStr(GetConfAndG(), nil, spec.iconField, spec.iconDefault) == pair[2] end
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
            drop2:SetScript("OnShow", function() ApplyUI() end)
        end
        -- Size edit
        if spec.sizeEdit and panel[spec.sizeEdit] and spec.sizeField then
            local edit = panel[spec.sizeEdit]
            local function DoSize()
                if not IsFramesTab() or not AllowedNow() then return end
                local c, g2 = GetConfAndG()
                local v = tonumber(edit:GetText()) or ReadNum(c, g2, spec.sizeField, spec.sizeDefault or 14)
                v = max(8, min(64, floor(v + 0.5))); c[spec.sizeField] = v; SetNumericEB(edit, v)
                if spec.id == "level" then
                    local fn = _G.MSUF_UpdateAllFonts_Immediate or _G.MSUF_UpdateAllFonts or _G.UpdateAllFonts
                    if type(fn) == "function" then fn() end
                end
                Refresh(); ApplyCurrent()
            end
            edit:SetScript("OnEnterPressed", function(self) DoSize(); self:ClearFocus() end)
            edit:SetScript("OnEditFocusLost", DoSize)
            edit:SetScript("OnTextChanged", function(self, user)
                if not user then return end
                self._msufSeq = (self._msufSeq or 0) + 1; local seq = self._msufSeq
                if C_Timer and C_Timer.After then C_Timer.After(0.25, function() if self._msufSeq == seq and self:HasFocus() then DoSize() end end) end
            end)
            edit:HookScript("OnShow", function() ApplyUI() end)
        end
        -- Reset button
        if spec.resetBtn and panel[spec.resetBtn] then
            panel[spec.resetBtn]:SetScript("OnClick", function()
                if not IsFramesTab() then return end
                local c, _, k = GetConfAndG()
                if spec.allowed and not spec.allowed(k) then return end
                for _, f in ipairs({ spec.xField, spec.yField, spec.anchorField, spec.sizeField, spec.layerField, spec.iconField, spec.symbolField }) do
                    if f then c[f] = nil end
                end
                ApplyUI(); Refresh(); ApplyCurrent()
            end)
        end
    end

    -- Bind all indicator rows
    for _, id in ipairs(INDICATOR_ORDER) do BindIndicatorRow(INDICATOR_SPECS[id]) end

    -- Build and bind status icon specs
    for _, def in ipairs(STATUS_ICON_DEFS) do
        local spec = {
            id = "status_"..def.prefix, allowed = def.allowed,
            showCB = def.prefix.."IconCB", showField = def.showField, showDefault = def.showDefault,
            xStepper = def.prefix.."OffsetXStepper", xField = def.xField, xDefault = 0,
            yStepper = def.prefix.."OffsetYStepper", yField = def.yField, yDefault = 0,
            anchorDrop = def.prefix.."AnchorDrop", anchorField = def.anchorField, anchorDefault = "TOPLEFT",
            anchorText = AnchorText, anchorChoices = MakeAnchorChoices(FOUR_ANCHORS, AnchorText),
            sizeEdit = def.prefix.."SizeEdit", sizeField = def.sizeField, sizeDefault = def.sizeDefault,
            layerSlider = def.prefix.."LayerSlider", layerField = def.layerField, layerDefault = def.layerDefault or 7,
            iconDrop = def.prefix.."SymbolDrop", iconField = def.symbolField, iconDefault = "DEFAULT",
            iconText = FindSymbolLabel, iconChoices = def.symbolChoices,
            resetBtn = def.prefix.."ResetBtn",
            refreshFnName = def.refreshGlobal,
        }
        -- Register global refresh function. Status icon sliders are global-ish and can
        -- affect both player and target, so refresh those two frames directly in addition
        -- to the normal coalesced apply for the currently open unit.
        _G[def.refreshGlobal] = _G[def.refreshGlobal] or function()
            local uf = _G.MSUF_UnitFrames or _G.UnitFrames
            local fn = _G.MSUF_UpdateStatusIndicatorForFrame
            if type(fn) == "function" and uf then
                local fp = uf.player
                local ft = uf.target
                if fp then fp._msufStatusIconsConf = nil; fn(fp) end
                if ft then ft._msufStatusIconsConf = nil; fn(ft) end
            end
            ApplyCurrent()
        end
        BindIndicatorRow(spec)
    end

    -- Status icons test mode + style toggles
    local function ApplyStatusUI()
        if not IsFramesTab() then return end
        local conf2, g2, k2 = GetConfAndG()
        if not (k2 == "player" or k2 == "target") then return end
        if panel.statusIconsTestModeCB then panel.statusIconsTestModeCB:SetChecked(g2.stateIconsTestMode == true) end
        if panel.statusIconsStyleCB then panel.statusIconsStyleCB:SetChecked(GetStatusIconStyleMidnight()) end
    end
    _G.MSUF_RefreshStatusIconsOptionsUI = ApplyStatusUI

    if panel.statusIconsTestModeCB then
        panel.statusIconsTestModeCB:SetScript("OnClick", function(self)
            if _G.MSUF_SetStatusIconsTestMode then _G.MSUF_SetStatusIconsTestMode(self:GetChecked() and true or false, "OPTIONS")
            else EnsureDB(); MSUF_DB.general.stateIconsTestMode = self:GetChecked() and true or false end
            ApplyStatusUI()
            ApplyCurrent()  -- single coalesced apply for both player+target
        end)
        panel.statusIconsTestModeCB:HookScript("OnShow", ApplyStatusUI)
    end

    if type(_G.MSUF_SetStatusIconStyleUseMidnight) ~= "function" then
        function _G.MSUF_SetStatusIconStyleUseMidnight(useMidnight)
            EnsureDB(); MSUF_DB.general = MSUF_DB.general or {}
            MSUF_DB.general.statusIconsUseMidnightStyle = (useMidnight == true)
            -- Caller is responsible for triggering apply (ApplyCurrent or equivalent).
            -- No direct frame updates here to avoid bypassing coalescing.
            if type(_G.MSUF_RequestStatusIconsRefreshForCurrent) == "function" then pcall(_G.MSUF_RequestStatusIconsRefreshForCurrent) end
        end
    end

    if panel.statusIconsStyleCB then panel.statusIconsStyleCB:SetScript("OnClick", function(self)
        _G.MSUF_SetStatusIconStyleUseMidnight(self:GetChecked() and true or false)
        ApplyStatusUI()
        ApplyCurrent()  -- single coalesced apply
    end) end

    -- Castbar handlers
    local CASTBAR_HANDLERS = {
        player = { enableW = "playerCastbarEnableCB", enableK = "enablePlayerCastbar", timeW = "playerCastbarTimeCB", timeK = "showPlayerCastTime", interruptW = "playerCastbarInterruptCB",
            iconW = "playerCastbarShowIconCB", iconK = "castbarPlayerShowIcon", textW = "playerCastbarShowTextCB", textK = "castbarPlayerShowSpellName",
            bar = function() return _G.MSUF_PlayerCastbar end, reanchor = function() if _G.MSUF_ReanchorPlayerCastBar then _G.MSUF_ReanchorPlayerCastBar() end end,
            preview = function() if _G.MSUF_PositionPlayerCastbarPreview then _G.MSUF_PositionPlayerCastbarPreview() end end },
        target = { requireKey = "target", enableW = "targetCastbarEnableCB", enableK = "enableTargetCastbar", timeW = "targetCastbarTimeCB", timeK = "showTargetCastTime", interruptW = "targetCastbarInterruptCB",
            iconW = "targetCastbarShowIconCB", iconK = "castbarTargetShowIcon", textW = "targetCastbarShowTextCB", textK = "castbarTargetShowSpellName",
            bar = function() return _G.MSUF_TargetCastbar end, reanchor = function() if _G.MSUF_ReanchorTargetCastBar then _G.MSUF_ReanchorTargetCastBar() end end,
            preview = function() if _G.MSUF_PositionTargetCastbarPreview then _G.MSUF_PositionTargetCastbarPreview() end end, forceRefreshUnit = "target" },
        focus = { requireKey = "focus", enableW = "focusCastbarEnableCB", enableK = "enableFocusCastbar", timeW = "focusCastbarTimeCB", timeK = "showFocusCastTime", interruptW = "focusCastbarInterruptCB",
            iconW = "focusCastbarShowIconCB", iconK = "castbarFocusShowIcon", textW = "focusCastbarShowTextCB", textK = "castbarFocusShowSpellName",
            bar = function() return _G.MSUF_FocusCastbar end, reanchor = function() if _G.MSUF_ReanchorFocusCastBar then _G.MSUF_ReanchorFocusCastBar() end end,
            preview = function() if _G.MSUF_PositionFocusCastbarPreview then _G.MSUF_PositionFocusCastbarPreview() end end, forceRefreshUnit = "focus" },
        boss = { requireKey = "boss", enableW = "bossCastbarEnableCB", enableK = "enableBossCastbar", timeW = "bossCastbarTimeCB", timeK = "showBossCastTime", interruptW = "bossCastbarInterruptCB",
            iconW = "bossCastbarShowIconCB", iconK = "showBossCastIcon", textW = "bossCastbarShowTextCB", textK = "showBossCastName",
            bar = function() return nil end, reanchor = function() end, preview = function() end },
    }
    for _, spec in pairs(CASTBAR_HANDLERS) do
        -- Enable toggle
        local ew = panel[spec.enableW]; if ew then
            ew:SetScript("OnClick", function(self)
                EnsureCastbars(); if not IsFramesTab() then return end
                if spec.requireKey and CurrentKey() ~= spec.requireKey then return end
                if api.EnsureDB then api.EnsureDB() end; MSUF_DB.general[spec.enableK] = self:GetChecked() and true or false
                if spec.requireKey == "boss" then
                    if _G.MSUF_SetBossCastbarsEnabled then _G.MSUF_SetBossCastbarsEnabled(MSUF_DB.general.enableBossCastbar ~= false) end
                    if _G.MSUF_RefreshBossCastbarLayout then _G.MSUF_RefreshBossCastbarLayout() end; return
                end
                spec.reanchor(); spec.preview()
                if spec.forceRefreshUnit and MSUF_DB.general[spec.enableK] ~= false then
                    local bar = spec.bar(); if bar and bar.Cast then
                        local casting = (UnitCastingInfo and UnitCastingInfo(spec.forceRefreshUnit)) or (UnitChannelInfo and UnitChannelInfo(spec.forceRefreshUnit))
                        if casting then pcall(bar.Cast, bar) end
                    end
                end
            end)
        end
        -- Interrupt
        local iw = panel[spec.interruptW]; if iw then
            iw:SetScript("OnClick", function(self)
                if not IsFramesTab() then return end
                if spec.requireKey and CurrentKey() ~= spec.requireKey then return end
                EnsureKeyDB().showInterrupt = self:GetChecked() and true or false
            end)
        end
        -- General toggles (icon, text, time)
        for _, pair in ipairs({ {spec.iconW, spec.iconK}, {spec.textW, spec.textK}, {spec.timeW, spec.timeK} }) do
            local w = panel[pair[1]]; if w then
                w:SetScript("OnClick", function(self)
                    if not IsFramesTab() then return end
                    if spec.requireKey and CurrentKey() ~= spec.requireKey then return end
                    EnsureDB(); MSUF_DB.general[pair[2]] = self:GetChecked() and true or false
                    if spec.requireKey == "boss" then if _G.MSUF_RefreshBossCastbarLayout then _G.MSUF_RefreshBossCastbarLayout() end
                    else if _G.MSUF_UpdateCastbarVisuals then _G.MSUF_UpdateCastbarVisuals() end; spec.reanchor(); spec.preview() end
                end)
            end
        end
    end

    -- Live refresh globals
    local ALL_UF = { "player","target","focus","pet","tot","targettarget","boss1","boss2","boss3","boss4","boss5" }
    -- Lightweight refresh: only calls the per-frame layout helper (e.g. ApplyLeaderIconLayout).
    -- Does NOT call UpdateSimpleUnitFrame — that goes through the coalesced dirty-frame system.
    local function RefreshFrames(list, applyFn)
        local uf = _G.MSUF_UnitFrames or _G.UnitFrames; local apply = applyFn and _G[applyFn]
        if not apply then return end
        for i = 1, #list do
            local f = uf and (uf[list[i]] or (list[i] == "tot" and uf.targettarget) or (list[i] == "targettarget" and uf.tot))
            if f then pcall(apply, f) end
        end
    end
    MSUF_RefreshLeaderIconFrames = function() RefreshFrames({ "player","target" }, "MSUF_ApplyLeaderIconLayout") end
    MSUF_RefreshRaidMarkerFrames = function() RefreshFrames(ALL_UF, "MSUF_ApplyRaidMarkerLayout") end
    MSUF_RefreshLevelIndicatorFrames = function() RefreshFrames(ALL_UF, "MSUF_ApplyLevelIndicatorLayout") end
    MSUF_RefreshEliteIconFrames = function() RefreshFrames({ "target", "focus", "targettarget", "boss1", "boss2", "boss3", "boss4", "boss5" }, "MSUF_ApplyEliteIconLayout") end

    -- Load Conditions
    do
        local lcSpecs = panel._msufLoadCondSpecs; if lcSpecs then
            local allCBs = {}
            for _, s in ipairs(lcSpecs) do
                local cb = panel[s[1]]; if cb then
                    allCBs[#allCBs + 1] = cb
                    cb:SetScript("OnClick", function(self)
                        if not IsFramesTab() then return end
                        if InCombatLockdown and InCombatLockdown() then self:SetChecked(not self:GetChecked()); return end
                        local c = EnsureKeyDB(); c[s[2]] = self:GetChecked() and true or false
                        local r = _G.MSUF_LoadCond_RecomputeActive; if type(r) == "function" then r(c) end
                        local lr = _G.MSUF_LoadCond_RefreshAll; if type(lr) == "function" then lr() end
                    end)
                end
            end
            local lcF = CreateFrame("Frame")
            lcF:RegisterEvent("PLAYER_REGEN_DISABLED"); lcF:RegisterEvent("PLAYER_REGEN_ENABLED")
            lcF:SetScript("OnEvent", function(_, ev)
                local en = (ev == "PLAYER_REGEN_ENABLED")
                for i = 1, #allCBs do local cb = allCBs[i]; if en then if cb.Enable then cb:Enable() end else if cb.Disable then cb:Disable() end end end
            end)
            if InCombatLockdown and InCombatLockdown() then
                for i = 1, #allCBs do if allCBs[i].Disable then allCBs[i]:Disable() end end
            end
        end
    end

    -- ToT inline toggle + separator
    if panel.totShowInTargetCB then panel.totShowInTargetCB:SetScript("OnClick", function(self)
        EnsureDB(); EnsureKeyDB(); MSUF_DB.targettarget = MSUF_DB.targettarget or {}
        MSUF_DB.targettarget.showToTInTargetName = self:GetChecked() and true or false
        ApplyLayout("TOTINLINE_TOGGLE")
        if _G.MSUF_UpdateTargetToTInlineNow then _G.MSUF_UpdateTargetToTInlineNow() end
        if panel.totInlineSeparatorDD then
            local en = MSUF_DB.targettarget.showToTInTargetName == true
            if UIDropDownMenu_EnableDropDown and UIDropDownMenu_DisableDropDown then
                if en then UIDropDownMenu_EnableDropDown(panel.totInlineSeparatorDD) else UIDropDownMenu_DisableDropDown(panel.totInlineSeparatorDD) end
            end
        end
    end) end

    if panel.totInlineSeparatorDD and UIDropDownMenu_Initialize then
        local drop = panel.totInlineSeparatorDD
        UIDropDownMenu_Initialize(drop, function(_, level)
            if not level or level ~= 1 then return end
            EnsureDB(); MSUF_DB.targettarget = MSUF_DB.targettarget or {}
            local cur = ToTSepText(MSUF_DB.targettarget.totInlineSeparator)
            for _, opt in ipairs(TOTSEP_OPTIONS) do
                local info = UIDropDownMenu_CreateInfo()
                info.text, info.value = opt[2], opt[1]
                info.func = function(btn)
                    local v = ToTSepText((btn and btn.value) or "|")
                    MSUF_DB.targettarget.totInlineSeparator = v
                    if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(drop, v) end
                    if UIDropDownMenu_SetText then UIDropDownMenu_SetText(drop, v) end
                    if CloseDropDownMenus then CloseDropDownMenus() end
                    if _G.MSUF_ToTInline_RequestRefresh then _G.MSUF_ToTInline_RequestRefresh("TOTINLINE_SEP")
                    elseif _G.MSUF_UpdateTargetToTInlineNow then _G.MSUF_UpdateTargetToTInlineNow() end
                end
                info.checked = function() return cur == opt[1] end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
    end

    -- Per-unit anchor dropdown
    local ANCHOR_CHOICES = {
        {"Free (global anchor)","GLOBAL"},{"Player frame","player"},{"Target frame","target"},
        {"Target of Target frame","targettarget"},{"Focus frame","focus"},{"Pet frame","pet"},
    }
    local function AnchorTextFor(v)
        return ({ player = "Player frame", target = "Target frame", focus = "Focus frame", pet = "Pet frame", targettarget = "Target of Target frame" })[v] or "Free (global anchor)"
    end
    local function AnchorVal(c) local v = c and c.anchorToUnitframe; if v == "player" or v == "target" or v == "focus" or v == "pet" or v == "targettarget" then return v end; return "GLOBAL" end
    local function AnchorKey() local k = CanonKey(CurrentKey()); return (k == "player" or k == "target" or k == "targettarget" or k == "focus" or k == "pet" or k == "boss") and k or nil end

    local function RefreshAnchorWidgets()
        if not panel.unitAnchorToDD or not IsFramesTab() or not AnchorKey() then return end
        local c = EnsureKeyDB(); local v = AnchorVal(c)
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(panel.unitAnchorToDD, v) end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(panel.unitAnchorToDD, AnchorTextFor(v)) end
        if panel.unitCustomAnchorValueText then
            local an = (type(c.anchorFrameName) == "string" and c.anchorFrameName) or ""
            panel.unitCustomAnchorValueText:SetText(TR("Current custom anchor: ") .. (an ~= "" and an or "none"))
        end
    end

    if panel.unitAnchorToDD and UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(panel.unitAnchorToDD, function(_, level)
            if not level or level ~= 1 or not IsFramesTab() or not AnchorKey() then return end
            local c = EnsureKeyDB(); local cur = AnchorVal(c); local curKey = AnchorKey()
            for _, pair in ipairs(ANCHOR_CHOICES) do
                if pair[2] == "GLOBAL" or pair[2] ~= curKey then
                    local info = UIDropDownMenu_CreateInfo()
                    info.text, info.value = pair[1], pair[2]
                    info.func = function()
                        if not IsFramesTab() then return end
                        EnsureKeyDB().anchorToUnitframe = pair[2]
                        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(panel.unitAnchorToDD, pair[2]) end
                        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(panel.unitAnchorToDD, pair[1]) end
                        if CloseDropDownMenus then CloseDropDownMenus() end; ApplyCurrent()
                    end
                    info.checked = function() return cur == pair[2] end
                    UIDropDownMenu_AddButton(info, level)
                end
            end
        end)
        panel.unitAnchorToDD:HookScript("OnShow", RefreshAnchorWidgets)
    end

    if panel.unitCustomAnchorPickButton and not panel._msufAnchorPickHooked then
        panel._msufAnchorPickHooked = true
        panel.unitCustomAnchorPickButton:SetScript("OnClick", function()
            if not IsFramesTab() or not AnchorKey() then return end
            local ov = type(_G.MSUF_EnsureAnchorPicker) == "function" and _G.MSUF_EnsureAnchorPicker()
            if not ov then return end
            ov._onPick = function(frameName)
                if not IsFramesTab() or not AnchorKey() then return end
                local c = EnsureKeyDB(); c.anchorFrameName = frameName; c.anchorToUnitframe = "GLOBAL"
                ApplyCurrent(); RefreshAnchorWidgets()
            end
            ov:Show()
        end)
    end
    if panel.unitCustomAnchorClearButton and not panel._msufAnchorClearHooked then
        panel._msufAnchorClearHooked = true
        panel.unitCustomAnchorClearButton:SetScript("OnClick", function()
            if not IsFramesTab() or not AnchorKey() then return end
            EnsureKeyDB().anchorFrameName = nil; ApplyCurrent(); RefreshAnchorWidgets()
        end)
    end

    -- Copy buttons
    if panel._msufBindCopyButtons then panel._msufBindCopyButtons() end
end
