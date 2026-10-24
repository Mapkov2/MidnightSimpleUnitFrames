local MSUF = select(2, ...)
MSUF = MSUF or {}
local SELF = "Shell/Menu2/Pages/MSUF_Menu2_Unit.lua"
local Preview = MSUF.Require("MSUF", SELF).UF.Preview
local previewKind = type(Preview)
assert(previewKind == "table",
  "MSUF: missing required dependency 'UF.Preview' required by Shell/Menu2/Pages/MSUF_Menu2_Unit.lua")
local validateKind = type(Preview.Validate)
assert(validateKind == "function",
  "MSUF: missing required dependency 'UF.Preview.Validate' required by Shell/Menu2/Pages/MSUF_Menu2_Unit.lua")
Preview.Validate(SELF)
local SetArenaPage = Preview.SetArenaPage
local SetBossPage = Preview.SetBossPage
local previewState = Preview.State

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
-- Core functions this page calls by their global names: required here at
-- load, called through _G so a hook installed on one later still applies.
M.RequireGlobals("Shell/Menu2/Pages/MSUF_Menu2_Unit.lua", {
    "MSUF_SetMSUFEditModeDirect",
    "MSUF_ApplyBossUnitframePreviewState",
    "MSUF_ApplyArenaUnitframePreviewState",
})
local C_Timer = M.MenuTimer or C_Timer

-- Menu2 Unit page definitions.
-- Declares per-unit page metadata, value lists, copy categories, and shared control constants.
-- Concrete section rendering is split into UnitSections/UnitText/UnitFrameVisuals.
local W = M.Widgets
local floor = math.floor
local VT = M.ValueTextList
local VTR = M.ValueTextRows
local VTP = M.ValueTextPairs
local KLR, KSW, WL = M.KeyLabelRows, M.KeySetFromWords, M.WordList
local NAV_SUBPAGE_LABELS = M.navSubpageLabels or {}
local UNIT_PAGES = { uf_player = { unit = "player", title = "MSUF Player", label = NAV_SUBPAGE_LABELS.uf_player or "Player" },
    uf_target = { unit = "target", title = "MSUF Target", label = NAV_SUBPAGE_LABELS.uf_target or "Target" },
    uf_targettarget = { unit = "targettarget", title = "MSUF Target of Target", label = NAV_SUBPAGE_LABELS.uf_targettarget or "Target of Target" },
    uf_focustarget = { unit = "focustarget", title = "MSUF Focus Target", label = NAV_SUBPAGE_LABELS.uf_focustarget or "Focus Target" },
    uf_focus = { unit = "focus", title = "MSUF Focus", label = NAV_SUBPAGE_LABELS.uf_focus or "Focus" },
    uf_pet = { unit = "pet", title = "MSUF Pet", label = NAV_SUBPAGE_LABELS.uf_pet or "Pet" },
    uf_pettarget = { unit = "pettarget", title = "MSUF Pet Target", label = NAV_SUBPAGE_LABELS.uf_pettarget or "Pet Target" },
    uf_boss = { unit = "boss", title = "MSUF Boss Frames", label = NAV_SUBPAGE_LABELS.uf_boss or "Boss" },
    uf_arena = { unit = "arena", title = "MSUF Arena Frames", label = NAV_SUBPAGE_LABELS.uf_arena or "Arena" } }
-- WoW Forever runs this Mainline page without arena units, and the Classic
-- clients lack some units too (Classic Era: focus, boss and arena; TBC: boss).
-- There the pages, aura copy partners and copy targets of every unit
-- MSUF.Client.SupportsUnit rejects are dropped. Midnight keeps every unit.
local IS_CLASSIC_FAMILY = MSUF.Client ~= nil and MSUF.Client.Family == "Classic"
local DROP_UNSUPPORTED_UNITS = MSUF.Client ~= nil and (MSUF.Client.IsForever == true or IS_CLASSIC_FAMILY)
    and type(MSUF.Client.SupportsUnit) == "function"
--- Load-time only. Takes a { value = unit } list and returns the kept rows, or
--- a table keyed by unit (or holding { unit = ... } pages) and prunes it in place.
local function DropUnsupportedUnits(units)
    if not DROP_UNSUPPORTED_UNITS then return units end
    local supportsUnit = MSUF.Client.SupportsUnit
    if units[1] ~= nil then
        local kept = {}
        for i = 1, #units do
            if supportsUnit(units[i].value) then kept[#kept + 1] = units[i] end
        end
        return kept
    end
    for key, entry in pairs(units) do
        if not supportsUnit(type(entry) == "table" and entry.unit or key) then units[key] = nil end
    end
    return units
end
UNIT_PAGES = DropUnsupportedUnits(UNIT_PAGES)
local CanDetachUnitPowerBar = MSUF.Require("MSUF_CanDetachUnitPowerBar", SELF)
-- Built in a function: a loop here would keep its control variables as
-- main-chunk locals (the chunk has a local budget).
local POWER_UNITS = (function()
    local units = {}
    for _, page in pairs(UNIT_PAGES) do
        if CanDetachUnitPowerBar(page.unit) then
            units[page.unit] = true
        end
    end
    return units
end)()
--- Appends lead .. prefix .. suffix for every prefix and suffix, in order.
local function AppendCombinedFields(list, lead, prefixes, suffixes)
    for _, prefix in ipairs(prefixes) do
        for _, suffix in ipairs(suffixes) do list[#list + 1] = lead .. prefix .. suffix end
    end
    return list
end
-- Castbar settings live in general DB rather than each unit DB. Keep this map as the one
-- place where unit pages translate a unit key into the correct castbar field names.
-- Player, Target and Focus castbars share one key pattern ("castbarTargetBarWidth"), Boss
-- and Arena another ("bossCastbarWidth"); $U is the capitalized unit, $u the unit key.
-- The Player castbar has no target-name key.
local CASTBAR_FIELDS = (function()
    local patterns = {
        { units = "player target focus", stylePrefix = "castbar$U", enable = "enable$UCastbar",
            backend = "castbar$UBackend", providerMemory = "castbar$UBackendBeforeHide", time = "show$UCastTime",
            icon = "castbar$UShowIcon", text = "castbar$UShowSpellName", targetName = "castbar$UShowTargetName",
            timeFormat = "castbar$UTimeFormat", w = "castbar$UBarWidth", h = "castbar$UBarHeight",
            match = "castbar$UMatchWidth", detached = "castbar$UDetached", offsetX = "castbar$UOffsetX",
            offsetY = "castbar$UOffsetY" },
        { units = "boss arena", stylePrefix = "$uCast", enable = "enable$UCastbar", backend = "$uCastbarBackend",
            providerMemory = "$uCastbarBackendBeforeHide", time = "show$UCastTime", icon = "show$UCastIcon",
            text = "show$UCastName", targetName = "show$UCastTargetName", timeFormat = "$uCastTimeFormat",
            w = "$uCastbarWidth", h = "$uCastbarHeight", match = "$uCastbarMatchWidth",
            detached = "$uCastbarDetached", offsetX = "$uCastbarOffsetX", offsetY = "$uCastbarOffsetY" },
    }
    local fields = {}
    for _, pattern in ipairs(patterns) do
        for _, unit in ipairs(WL(pattern.units)) do
            local capitalized = unit:sub(1, 1):upper() .. unit:sub(2)
            local entry = {}
            for field, template in pairs(pattern) do
                if field ~= "units" then entry[field] = template:gsub("%$U", capitalized):gsub("%$u", unit) end
            end
            if unit == "player" then entry.targetName = nil end
            fields[unit] = entry
        end
    end
    return fields
end)()
local CASTBAR_COPY_SUFFIXES = WL [[IconPosition IconSize IconZoom IconOffsetX IconOffsetY IconSpacing IconBorderThickness IconBorderStyle IconShape IconFrameLevelOffset SpellNamePosition SpellNameFontSize TextOffsetX TextOffsetY SpellNameMaxWidth SpellNameTruncate TimePosition TimeFontSize TimeOffsetX TimeOffsetY FrameLevelOffset SpellNameColorR SpellNameColorG SpellNameColorB TimeColorR TimeColorG TimeColorB]]
--- OffsetX/OffsetY mean two different things depending on the detach state: anchored
--- to the unit frame they are a relative gap and safe to copy, detached they are an
--- absolute UIParent position (see MSUF_CastbarAnchors) and copying them would stack
--- both castbars on the same screen spot. Only the relative case travels.
local CASTBAR_TARGET_NAME_COPY_SUFFIXES = WL [[TargetNamePosition TargetNameFontSize TargetNameAlign TargetNameOffsetX TargetNameOffsetY TargetNameColorR TargetNameColorG TargetNameColorB]]
local LOAD_CONDITIONS = KLR [[
loadCondHideInHousing=Housing
loadCondHideInCombat=In combat
loadCondHideInGroup=In group
loadCondHideInInstance=In instance
loadCondHideInVehicle=In vehicle
loadCondHideMounted=Mounted
loadCondHideNoTarget=No target
loadCondHideOutOfCombat=Out of combat
loadCondHideOutOfCombatNoTarget=Out of combat and no target
loadCondHideResting=Resting
loadCondHideSolo=Solo
loadCondHideStealthed=Stealthed
]]
local STATUS_ANCHORS = VTP "TOPLEFT=Top Left|TOPRIGHT=Top Right|BOTTOMLEFT=Bottom Left|BOTTOMRIGHT=Bottom Right|CENTER=Center|TOP=Top|BOTTOM=Bottom|LEFT=Left|RIGHT=Right"
local STATUS_CORNER_ANCHORS = STATUS_ANCHORS
local function WithNameAnchors(rightText, leftText)
    local out = VT("NAMERIGHT", rightText, "NAMELEFT", leftText)
    for i = 1, #STATUS_ANCHORS do out[#out + 1] = STATUS_ANCHORS[i] end
    return out
end
local STATUS_LEVEL_ANCHORS = WithNameAnchors("Right to name", "Left to name")
local RAID_GROUP_NAME_ANCHORS = WithNameAnchors("Right to name", "Left to name")
local COMBAT_SYMBOLS = VTP "DEFAULT=Default|weapon_axes_crossed=Axes|weapon_bows_crossed=Bows|weapon_crossbows_crossed=Crossbows|weapon_daggers_crossed=Daggers|weapon_fishing_poles_crossed=Fishing|weapon_fist_crossed=Fist|weapon_guns_crossed=Guns|weapon_maces_crossed=Maces|weapon_polearms_crossed=Polearms|weapon_shuriken=Shuriken|weapon_staves_crossed=Staves|weapon_swords_crossed=Swords|weapon_thrown_crossed=Thorn|weapon_wands_crossed=Wands|weapon_warglaives_crossed=Warglaives"
local RESTED_SYMBOLS = VTP "DEFAULT=Default|rested_blizzard_animated=Blizzard animated Zzz|rested_moonzzz=Moon (3 z)|rested_moonzzzz=Moon (4 z)|rested_sleep_zzzz=Sleep ZzzZ|rested_zzz_compact=Compact Zzz|rested_zzz_diag=Diagonal Zzz|rested_zzz_stack=Stacked Zzz"
local RESS_SYMBOLS = VTP "DEFAULT=Default|resurrection_ankh=Ankh|resurrection_cross=Cross|resurrection_soul=Soul|resurrection_wings=Angelic Wings"
local DEFAULT_SYMBOLS = VT("DEFAULT", "Default")
local UnitPage = M.UnitPage or {}
M.UnitPage = UnitPage
-- The icon pack list is rebuilt on every status refresh: resolve its provider once.
local packValuesFn
function UnitPage.StatusIconPackValues()
    packValuesFn = packValuesFn or MSUF.Require("MSUF_GetStatusIconPackValues", SELF)
    return packValuesFn(false)
end
local function StatusControl(value, text, show, defaultShow, prefix, defaultSize, defaultAnchor, anchors, defaultX, defaultY, defaultLayer, refresh, extra)
    local spec = {
        value = value, text = text, show = show, defaultShow = defaultShow,
        size = prefix .. "Size", defaultSize = defaultSize, anchor = prefix .. "Anchor", defaultAnchor = defaultAnchor, anchors = anchors,
        x = prefix .. "OffsetX", defaultX = defaultX, y = prefix .. "OffsetY", defaultY = defaultY,
        layer = prefix .. "Layer", defaultLayer = defaultLayer,
        refresh = refresh,
    }
    if extra then for k, v in pairs(extra) do spec[k] = v end end
    return spec
end
local STATUS_CONTROLS = {
    StatusControl("leader", "Leader Icon", "showLeaderIcon", true, "leaderIcon", 14, "TOPLEFT", STATUS_CORNER_ANCHORS, 0, 3, 7,
        "MSUF_RefreshLeaderIconFrames",
        { allowed = function(unit) return unit == "player" or unit == "target" end, iconStyle = "leaderIconStyle", defaultIconStyle = "BLIZZARD",
        customIcon = "leaderIconCustomIcon" }),
    StatusControl("assist", "Assist Icon", "showLeaderIcon", true, "leaderIcon", 14, "TOPLEFT", STATUS_CORNER_ANCHORS, 0, 3, 7,
        "MSUF_RefreshLeaderIconFrames",
        { allowed = function(unit) return unit == "player" or unit == "target" end, iconStyle = "assistIconStyle", defaultIconStyle = "BLIZZARD",
        customIcon = "assistIconCustomIcon" }),
    StatusControl("raidmarker", "Raid Marker", "showRaidMarker", true, "raidMarker", 18, "TOPLEFT", STATUS_CORNER_ANCHORS, 16, 3, 7,
        "MSUF_RefreshRaidMarkerFrames", { iconStyle = "raidMarkerIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "raidMarkerCustomIcon" }),
    StatusControl("level", "Level Text", "showLevelIndicator", true, "levelIndicator", 14, "NAMERIGHT", STATUS_LEVEL_ANCHORS, 0, 0, 7,
        "MSUF_RefreshIdentityTextFrames",
        { textIndicator = true, colorPrefix = "levelIndicator" }),
    StatusControl("bossNumber", "Boss Number", "showBossNumberIndicator", false, "bossNumberIndicator", 14, "TOPLEFT", STATUS_CORNER_ANCHORS, 4, -4, 7,
        "MSUF_RefreshStatusIndicators", { allowed = function(unit) return unit == "boss" end, textIndicator = true, colorPrefix = "bossNumberIndicator" }),
    StatusControl("raceText", "Race Text", "showRaceIndicator", false, "raceIndicator", 14, "NAMERIGHT", STATUS_LEVEL_ANCHORS, 0, 0, 7,
        "MSUF_RefreshIdentityTextFrames",
        { textIndicator = true, colorPrefix = "raceIndicator" }),
    StatusControl("classText", "Class Text", "showClassTextIndicator", false, "classTextIndicator", 14, "NAMERIGHT", STATUS_LEVEL_ANCHORS, 0, 0, 7,
        "MSUF_RefreshIdentityTextFrames",
        { textIndicator = true, colorPrefix = "classTextIndicator" }),
    StatusControl("raidgroupname", "Raid Group", "showRaidGroupInName", false, "raidGroupName", 14, "NAMERIGHT", RAID_GROUP_NAME_ANCHORS, 3, 0, 5,
        "MSUF_RefreshRaidGroupNameFrames",
        { allowed = function(unit) return unit == "player" or unit == "target" or unit == "targettarget" or unit == "focustarget" or unit == "pettarget"
        or unit == "focus" end, inlineName = true, legacyLayer = "nameTextLayer", colorPrefix = "raidGroupName", copyProps = "show size anchor x y layer",
        copyExtra = WL("raidGroupNameStyle") }),
    StatusControl("eliteicon", "Elite / Rare", "showEliteIcon", true, "eliteIcon", 20, "TOPRIGHT", STATUS_CORNER_ANCHORS, 2, 2, 7,
        "MSUF_RefreshEliteIconFrames",
        { allowed = function(unit) return unit == "target" or unit == "focus" or unit == "targettarget" or unit == "focustarget" or unit == "pettarget"
        or unit == "boss" end, iconStyle = "eliteIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "eliteIconCustomIcon" }),
    StatusControl("statusText", "Dead / Offline Text", "statusDeadTextEnabled", true, "statusText", 16, "CENTER", STATUS_CORNER_ANCHORS, 0, 0, 7,
        "MSUF_RequestStatusTextRefresh",
        { statusRuntime = true, statusTextState = "DEAD", colorPrefix = "statusText", legacyShow = "statusTextEnabled", legacyState = "showDead" }),
    StatusControl("statusGhostText", "Ghost Text", "statusGhostTextEnabled", true, "statusGhostText", 16, "CENTER", STATUS_CORNER_ANCHORS, 0, 0, 7,
        "MSUF_RequestStatusTextRefresh",
        { statusRuntime = true, statusTextState = "GHOST", colorPrefix = "statusGhostText", legacyShow = "statusTextEnabled", legacyState = "showGhost",
        legacySize = "statusTextSize", legacyAnchor = "statusTextAnchor", legacyX = "statusTextOffsetX", legacyY = "statusTextOffsetY",
        legacyLayer = "statusTextLayer" }),
    StatusControl("statusAFKText", "AFK Text", "statusAFKTextEnabled", false, "statusAFKText", 16, "CENTER", STATUS_CORNER_ANCHORS, 0, 0, 7,
        "MSUF_RequestStatusTextRefresh",
        { statusRuntime = true, statusTextState = "AFK", colorPrefix = "statusAFKText", legacyShow = "statusTextEnabled", legacyState = "showAFK",
        legacySize = "statusTextSize", legacyAnchor = "statusTextAnchor", legacyX = "statusTextOffsetX", legacyY = "statusTextOffsetY",
        legacyLayer = "statusTextLayer" }),
    StatusControl("statusAFKTimer", "AFK Timer", "statusAFKTimerEnabled", false, "statusAFKTimer", 12, "CENTER", STATUS_CORNER_ANCHORS, 0, -14, 7,
        "MSUF_RequestStatusTextRefresh",
        { statusRuntime = true, statusTextState = "AFKTIMER", colorPrefix = "statusAFKTimer" }),
    StatusControl("statusDNDText", "DND Text", "statusDNDTextEnabled", false, "statusDNDText", 16, "CENTER", STATUS_CORNER_ANCHORS, 0, 0, 7,
        "MSUF_RequestStatusTextRefresh",
        { statusRuntime = true, statusTextState = "DND", colorPrefix = "statusDNDText", legacyShow = "statusTextEnabled", legacyState = "showDND",
        legacySize = "statusTextSize", legacyAnchor = "statusTextAnchor", legacyX = "statusTextOffsetX", legacyY = "statusTextOffsetY",
        legacyLayer = "statusTextLayer" }),
    StatusControl("statusCombat", "Combat", "showCombatStateIndicator", true, "combatStateIndicator", 18, "TOPLEFT", STATUS_CORNER_ANCHORS, 0, 0, 7,
        "MSUF_RequestStatusCombatIndicatorRefresh",
        { allowed = function(unit) return unit == "player" or unit == "target" end, symbol = "combatStateIndicatorSymbol", symbols = COMBAT_SYMBOLS,
        statusRuntime = true, iconStyle = "combatStateIndicatorIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "combatStateIndicatorCustomIcon" }),
    StatusControl("statusResting", "Rested (player only)", "showRestingIndicator", true, "restedStateIndicator", 39, "TOPLEFT", STATUS_CORNER_ANCHORS, -40,
        50, 25, "MSUF_RequestStatusRestingIndicatorRefresh",
        { allowed = function(unit) return unit == "player" end, symbol = "restedStateIndicatorSymbol", symbols = RESTED_SYMBOLS, statusRuntime = true,
        iconStyle = "restedStateIndicatorIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "restedStateIndicatorCustomIcon" }),
    StatusControl("statusIncomingRes", "Incoming Rez", "showIncomingResIndicator", true, "incomingResIndicator", 18, "TOPRIGHT", STATUS_CORNER_ANCHORS, 0, 0,
        7, "MSUF_RequestStatusIncomingResIndicatorRefresh",
        { allowed = function(unit) return unit == "player" or unit == "target" end, symbol = "incomingResIndicatorSymbol", symbols = RESS_SYMBOLS,
        statusRuntime = true, iconStyle = "incomingResIndicatorIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "incomingResIndicatorCustomIcon" }),
    StatusControl("stance", "Stance", "showStanceIndicator", false, "stanceIndicator", 12, "TOP", STATUS_LEVEL_ANCHORS, 0, -2, 7,
        "MSUF_RequestStatusIconsRefreshForCurrent",
        { allowed = function(unit) return unit == "player" end, statusRuntime = true, textIndicator = true, colorPrefix = "stanceIndicator" }),
    StatusControl("statusPvp", "PvP Flag (War Mode/PvP)", "showPvpIndicator", true, "pvpIndicator", 18, "TOPRIGHT", STATUS_CORNER_ANCHORS, 0, 0, 7,
        "MSUF_RequestStatusPvpIndicatorRefresh",
        { allowed = function(unit) return unit == "player" or unit == "target" or unit == "focus" or unit == "targettarget" or unit == "focustarget"
        or unit == "pettarget" end, statusRuntime = true, iconStyle = "pvpIndicatorIconStyle", defaultIconStyle = "BLIZZARD",
        customIcon = "pvpIndicatorCustomIcon" }),
}
-- Hunter pet happiness exists again on WoW Forever, Classic Era and TBC, which
-- all load this page. Midnight and Mists have none, so the control is only
-- added where the client supports it.
if MSUF.Client ~= nil and MSUF.Client.SupportsPetHappiness == true then
    STATUS_CONTROLS[#STATUS_CONTROLS + 1] = StatusControl("statusPetHappiness", "Pet Happiness", "showPetHappinessIndicator", true, "petHappinessIndicator",
        24, "RIGHT", STATUS_CORNER_ANCHORS, -7, -4, 7, "MSUF_RequestPetHappinessIndicatorRefresh",
        { allowed = function(unit) return unit == "pet" end, statusRuntime = true })
end
if MSUF.Client ~= nil and MSUF.Client.IsClassic == true then
    STATUS_CONTROLS[#STATUS_CONTROLS + 1] = StatusControl("statusPetXP", "Pet XP Bar", "showPetXPBar", true, "petXPBar", 8, "BOTTOM", STATUS_CORNER_ANCHORS,
        0, -5, 7, "MSUF_RequestPetXPBarRefresh",
        { allowed = function(unit) return unit == "pet" end, statusRuntime = true, width = "petXPBarWidth", defaultWidth = 80 })
end
-- The threat percentage text exists on WoW Forever, Classic Era and TBC, which
-- all load this page; Midnight and Mists have none. statusTextState gives it the
-- status text color shortcut without the name-font size fallback of textIndicator.
if MSUF.Client ~= nil and MSUF.Client.SupportsThreatText == true then
    STATUS_CONTROLS[#STATUS_CONTROLS + 1] = StatusControl("statusThreat", "Threat %", "showThreatIndicator", true, "threatIndicator", 11, "BOTTOMLEFT",
        STATUS_CORNER_ANCHORS, 6, 2, 7, "MSUF_RequestThreatIndicatorRefresh",
        { allowed = function(unit) return unit == "target" or unit == "focus" or unit == "boss" end, statusRuntime = true, statusTextState = "THREAT",
        colorPrefix = "threatIndicator" })
end
-- LEFT/CENTER/RIGHT were legacy 5.77 tokens for the top row. Profiles migrate
-- those values to TOPLEFT/TOP/TOPRIGHT; FRAME* keeps the new middle row
-- unambiguous even when an old profile is imported later.
local TEXT_ANCHORS = VTP "TOPLEFT=Top Left|TOP=Top Center|TOPRIGHT=Top Right|FRAMELEFT=Left|FRAMECENTER=Center|FRAMERIGHT=Right"
local HP_MODES = VTP "ABSORB=Absorb|CURRENTABSORB=Current + Absorb|FULLVALUEABSORB=Full Value + Absorb|MAXABSORB=Max + Absorb|DEFICITABSORB=Deficit + Absorb|CURMAXABSORB=Current / Max + Absorb|PERCENTABSORB=Percent + Absorb|CURPERCENTABSORB=Current / Percent + Absorb|CURMAXPERCENTABSORB=Current / Max / Percent + Absorb|MAXPERCENTABSORB=Max / Percent + Absorb|PERCENTCURABSORB=Percent / Current + Absorb|PERCENTMAXABSORB=Percent / Max + Absorb|PERCENTCURMAXABSORB=Percent / Current / Max + Absorb|PERCENT=Percent|CURRENT=Current|FULLVALUE=Full Value|MAX=Max|DEFICIT=Deficit|CURMAX=Current / Max|CURPERCENT=Current / Percent|CURMAXPERCENT=Current / Max / Percent|MAXPERCENT=Max / Percent|PERCENTCUR=Percent / Current|PERCENTMAX=Percent / Max|PERCENTCURMAX=Percent / Current / Max|NONE=None"
local POWER_MODES = VTP "CURRENT=Current|MAX=Max|CURMAX=Current / Max|PERCENT=Percent|CURPERCENT=Current / Percent|CURMAXPERCENT=Current / Max / Percent|NONE=None"
local BOSS_LAYOUT_OPTIONS = VTP "VERTICAL_DOWN=Vertical (top -> bottom)|VERTICAL_UP=Vertical (bottom -> top)|HORIZONTAL_RIGHT=Horizontal (left -> right)|HORIZONTAL_LEFT=Horizontal (right -> left)"
local BOSS_LAYOUT_VALID = KSW("VERTICAL_DOWN VERTICAL_UP HORIZONTAL_RIGHT HORIZONTAL_LEFT")
local PortableControlToken = M.PortableControlToken
local function UnitControlMeta(ctx, semanticPath, classification)
    local pageKey = PortableControlToken(ctx and ctx.key or M.activeKey, "uf_unknown")
    local path = PortableControlToken(semanticPath, "control")
    local identity = "unit." .. path
    local meta = {
        controlId = "menu2." .. pageKey .. ".unit." .. path,
        pageKey = pageKey,
        identityKey = identity,
        controlPath = identity:gsub("%.", "/"),
        classification = classification or "setting",
    }
    -- Unit controls execute against the page/runtime scope. The semantic role
    -- is a stable control identity, not a globally resolvable Search action.
    return meta
end
local function UnitSettingMeta(ctx, semanticPath, unit, key)
    local meta = UnitControlMeta(ctx, semanticPath, "setting")
    unit, key = tostring(unit or ""), tostring(key or "")
    if unit ~= "" and key ~= "" then meta.settingKey = unit .. "." .. key end
    return meta
end
local function RegisterUnitControl(widget, ctx, semanticPath, label, kind, classification, extra)
    if not widget then return widget end
    local meta = UnitControlMeta(ctx, semanticPath, classification)
    meta.label, meta.kind = label, kind
    if type(extra) == "table" then
        for key, value in pairs(extra) do meta[key] = value end
    end
    if type(M.RegisterSearchWidget) == "function" then M.RegisterSearchWidget(widget, meta) end
    return widget
end
local SEPARATORS = VTR [[
=space
-=-
/=/
\=\
|=|
<=<
>=>
~=~
:=:
]]
local PORTRAIT_RENDER = VTP "2D=2D portrait|CLASS=Class portrait"
local PORTRAIT_SHAPES = VTP "SQUARE=Square|CIRCLE=Circle|ROUNDED=Rounded|DIAMOND=Diamond|BLIZZARD=Blizzard ring"
local PORTRAIT_BORDERS = VTP "NONE=No border|SOLID=Solid|CLASS_COLOR=Class color|REACTION=Reaction color|CUSTOM=Custom color"
local function GetConf(unit)
    return M.GetUnitDB(unit)
end
local function GetGeneral()
    return M.GetGeneralDB()
end
function UnitPage.GetBars()
    local db = M.EnsureDB()
    db.bars = db.bars or {}
    return db.bars
end

local DeepCopy = M.DeepCopy
local COPY_POWER_BAR_FIELDS = WL [[showPowerBar powerBarHeight embedPowerBarIntoHealth powerBarBorderEnabled powerBarBorderThickness powerBarBorderColorR powerBarBorderColorG powerBarBorderColorB powerSmoothFill powerChunkedFill powerBarDetached detachedPowerBarShape detachedPowerOrbSize detachedPowerBarWidth detachedPowerBarHeight detachedPowerBarOffsetX detachedPowerBarOffsetY detachedPowerBarAnchorMode detachedPowerBarFrameLevelOffset detachedPowerBarTextOnBar detachedPowerBarSyncClassPower detachedPowerBarAnchorToClassPower powerBarTexture powerBarBgTexture]]
--- Must cover every per-unit portrait key the engine reads (CompileUnitPortrait in
--- MSUF_UF_Config.lua) and the Visuals page binds. Border/background COLORS are
--- intentionally absent: those live in MSUF_DB.general and are shared by all units.
--- unit_copy_semantics_smoke extracts the bound keys from the Visuals page source and
--- fails when a new portrait control is missing here.
local COPY_PORTRAIT_FIELDS = WL [[portraitMode portraitRender portraitClassStyle portraitCastSpellIcon portraitClickable portraitBlizzardElite portraitBlizzardCorner portraitBlizzardDirection portraitBlizzardStandaloneRing portraitShape portraitSizeMode portraitSizeOverride portraitWidth portraitHeight portraitOffsetX portraitOffsetY portraitZoom portraitPanX portraitPanY portraitPlacement portraitDetachedPoint portraitDetachedTo portraitOverlayAlign portraitLevelOffset portraitAlpha portraitBorderStyle portraitEdgeSoftness portraitBorderArt portraitBorderDirection portraitBorderThickness portraitBgEnabled portraitFillBorder portraitDecoOverride portraitFlip portraitInnerShadow portraitDragonArtwork portraitDragonScale portraitDragonX portraitDragonY portraitDragonFlip portraitDragonInInstances portraitDragonLayer portraitDragonLevel]]
local COPY_TEXT_FIELDS = WL [[
    nameTextMouseover hpTextMouseover powerTextMouseover
    nameTextMouseoverFadeIn nameTextMouseoverFadeOut hpTextMouseoverFadeIn hpTextMouseoverFadeOut powerTextMouseoverFadeIn powerTextMouseoverFadeOut
    showName showHP showPower showPowerText nameTextAnchor nameOffsetX nameOffsetY nameFontSize
    showRaidGroupInName raidGroupNameAnchor raidGroupNameOffsetX raidGroupNameOffsetY raidGroupNameLayer raidGroupNameStyle
    hpOffsetX hpOffsetY hpFontSize hpTextMode textLeft textCenter textRight
    hpTextLeftHidePercentSymbol hpTextCenterHidePercentSymbol hpTextRightHidePercentSymbol
    hpTextLeftAbsorbIcon hpTextCenterAbsorbIcon hpTextRightAbsorbIcon
    hpTextReverse hpTextSeparator healthTextDecimals hpFullValueShort hpAbsorbIcon
    powerOffsetX powerOffsetY powerFontSize powerTextMode powerTextLeft powerTextCenter powerTextRight
    powerTextLeftHidePercentSymbol powerTextCenterHidePercentSymbol powerTextRightHidePercentSymbol powerTextSeparator
    nameTextLayer hpTextLayer powerTextLayer
    hpTextLeftOffsetX hpTextLeftOffsetY hpTextCenterOffsetX hpTextCenterOffsetY hpTextRightOffsetX hpTextRightOffsetY
    powerTextLeftOffsetX powerTextLeftOffsetY powerTextCenterOffsetX powerTextCenterOffsetY powerTextRightOffsetX powerTextRightOffsetY
    hpPowerTextOverride
    fontOverride fontKey boldText noOutline textBackdrop fontMonochrome fontSlug fontOutline
    fontShadowStrength fontShadowOpacity fontShadowDistance fontTextAlpha fontBaselineOffset
    useGlobalFontColor fontR fontG fontB nameColorMode nameColorR nameColorG nameColorB nameClassColor npcNameRed nameNpcClassColor
    colorPowerTextByType colorHealthTextByHealth
    nameShortenEnabled nameClipSide nameMaxChars nameNoEllipsis
    shortenNames shortenNameClipSide shortenNameMaxChars shortenNameShowDots
    hpTextLeftFontSize hpTextCenterFontSize hpTextRightFontSize
    powerTextLeftFontSize powerTextCenterFontSize powerTextRightFontSize
    directTextLayout
    --- Legacy twins of the modern keys above. MSUF_UF_Config reads them as fallbacks
    --- ("conf.hpOffsetX or conf.hpTextOffsetX", and healthTextDecimals is even OR-ed
    --- with hpTextDecimals), and MSUF_Defaults/MSUF_Profiles refill a missing modern
    --- key from its twin on every load. Copying only the modern half therefore leaves
    --- the destination's stale twin to win the fallback chain, or to resurrect the old
    --- value after a reload -- the copy looks like it silently reverted.
    nameAnchor nameTextOffsetX nameTextOffsetY hpTextOffsetX hpTextOffsetY
    powerTextOffsetX powerTextOffsetY hpTextDecimals textLayer fontSize
]]
--- With directTextLayout on, these keys ARE the text layout: MSUF_UF_Config resolves
--- every name/health/power slot from direct<Slot>Point/RelativePoint/OffsetX/OffsetY
--- and takes the name color from directNameColor. Skipping them left the destination
--- on its own placement, so a Text copy appeared to do nothing at all.
--- Mirrors DIRECT_TEXT_LAYOUTS in UnitFrames/Engine/MSUF_UF_Config.lua.
AppendCombinedFields(COPY_TEXT_FIELDS, "direct", WL [[Name HealthLeft HealthCenter HealthRight PowerLeft PowerCenter PowerRight]],
    WL [[Point RelativePoint OffsetX OffsetY Color]])
local COPY_INDICATOR_FIELDS = M.CopyFieldsFromSpecs(STATUS_CONTROLS, "leader assist raidmarker raidgroupname eliteicon", nil,
    "show iconStyle customIcon x y anchor size layer symbol")
local COPY_STATUSICON_FIELDS = M.CopyFieldsFromSpecs(STATUS_CONTROLS, "level raceText classText statusText statusGhostText statusAFKText statusAFKTimer statusDNDText statusCombat statusResting statusIncomingRes statusPvp statusPetHappiness statusThreat stance", "stateIconsTestMode statusIconsTestMode stateIconsAlpha statusIconsAlpha statusTextEnabled levelIndicatorDifficultyColor levelIndicatorForeverBadge threatIndicatorColorCurve threatIndicatorBackground", "show iconStyle customIcon x y anchor size layer symbol")
--- Most fields below "healthColorMode" are the per-unit Bars override scope (gated by
--- hlOverride, see MSUF_Menu2_Bindings BARS_SCOPE_KEYS). UnitFrame Dispel Overlay/Symbol
--- are the deliberate exception: they are copied with Frame settings but stay owned by
--- the source/destination units regardless of the Bars override. powerSmoothFill is
--- owned by the Power Bar category, hpPowerTextOverride by Text.
local COPY_FRAME_BASIC_FIELDS = WL [[
    enabled showName showHP showPower reverseFillBars verticalFillBars smoothFill chunkedFill healthColorMode frameBarShape slantedBarDirection
    hlOverride barTexture barBackgroundTexture barBgTexture
    barOutlineThickness barOutlineLayer barOutlineStrata barOutlineTexture barOutlineColorR barOutlineColorG barOutlineColorB barOutlineColorA
    highlightBorderThickness hlAggroSize aggroOutlineMode dispelOutlineMode purgeOutlineMode dispelBorderTrigger dispelBorderShowOn
    unitDispelOverlayEnabled unitDispelOverlayStyle unitDispelOverlayOnHealth unitDispelOverlayAlpha unitDispelOverlayTrigger
    unitDispelSymbolEnabled unitDispelSymbolStyle unitDispelSymbolMode unitDispelSymbolTrigger
    unitDispelSymbolSize unitDispelSymbolSpacing unitDispelSymbolGrowth unitDispelSymbolAnchor
    unitDispelSymbolX unitDispelSymbolY unitDispelSymbolAlpha unitDispelSymbolLayer unitDispelSymbolStrata
    hlPrioEnabled hlPrioOrder
    enableAbsorbBar absorbTextMode absorbAnchorMode absorbBarHeight absorbBarOffsetY absorbBarOpacity
    healAbsorbEnabled healAbsorbAnchorMode healAbsorbBarHeight healAbsorbBarOffsetY healAbsorbBarOpacity
    healPredEnabled healPredAllHealers healPredAnchorMode healPredictionBarHeight healPredictionBarOffsetY healPredictionBarOpacity healPredictionBarTexture
    overAbsorbOverlay fullHealthAbsorbStripe
    enableGradient enablePowerGradient gradientStrength gradientDirection
    powerGradientStrength aggroMode tempMaxHealthEnabled tempMaxHealthTexture tempMaxHealthOpacity
    tempMaxHealthBackgroundOpacity tempMaxHealthColorR tempMaxHealthColorG tempMaxHealthColorB
    gradientDirRight gradientDirLeft gradientDirUp gradientDirDown
    gradientOverride gradientOverrideVersion gradientOverrideKeys
    healthBarGradientColorR healthBarGradientColorG healthBarGradientColorB
    powerBarGradientColorR powerBarGradientColorG powerBarGradientColorB
]]
local COPY_TRANSPARENCY_FIELDS = WL [[hpBarAlpha powerBarAlpha hpBgAlpha powerBarBgAlpha alphaExcludeTextPortrait alphaExcludePredictionBars oocFadeEnabled oocFadeAlpha rangeFadeEnabled rangeFadeAlpha rangeFadeLayerMode]]
-- Keep this as a WL literal (even though the shared prefix list is empty) so
-- unit_copy_coverage_smoke.lua can audit the dynamically-prefixed suffix set.
local COPY_TEXLAYER_FIELDS = WL [[]]
AppendCombinedFields(COPY_TEXLAYER_FIELDS, "", { "texLayer", "texLayer2", "texLayer3" },
    WL [[Enabled SourceMode Atlas Texture CustomTexturePath Alpha FollowFrameAlpha Strata Level AnchorTarget Anchor OffsetX OffsetY ResponsiveSize SizeMode EdgeAttach Width Height ColorMode ColorTreatment ColorR ColorG ColorB GradientEnabled Gradient2R Gradient2G Gradient2B GradientDirRight GradientDirLeft GradientDirUp GradientDirDown BlendMode MirrorH MirrorV CropMode EdgeSoftness Visibility RoundedClip
        TargetOnly HealthCondition HealthThreshold HealthLowAlphaEnabled HealthLowAlpha HealthAboveMode]])
local COPY_LOAD_CONDITION_FIELDS = WL [[loadCondHideInHousing loadCondHideInCombat loadCondHideInGroup loadCondHideInInstance loadCondHideInVehicle loadCondHideMounted loadCondHideNoTarget loadCondHideOutOfCombat loadCondHideOutOfCombatNoTarget loadCondHideResting loadCondHideSolo loadCondHideStealthed loadCondShowWhenInjured loadCondActive]]
--- Size only. Placement (offsetX/offsetY, point/relativePoint, anchorFrameName and
--- anchorToUnitframe) must never travel through Copy To: two unit frames sharing a
--- placement land exactly on top of each other, and the covered one is then
--- unreachable for dragging. Frames are positioned in MSUF Edit Mode, not by copying.
--- Boss layout also describes the boss1-boss5 container rather than one unit frame,
--- so it has no semantic equivalent on Player/Target/Focus and must never be cleared
--- when a normal unit's frame size is copied to Boss.
local COPY_LAYOUT_FIELDS = WL [[width height]]
local AURA_COPY_UNITS = DropUnsupportedUnits(KSW("player pet target focus boss arena"))
local AURA_COPY_FLAGS = { player = "showPlayer", pet = "showPet", target = "showTarget", focus = "showFocus", boss = "showBoss", arena = "showArena" }
local AURA_BOSS_RUNTIME_UNITS = WL("boss1 boss2 boss3 boss4 boss5")
-- TBC and Mists field five arena opponents, Classic Era and WoW Forever none,
-- Midnight three (MSUF.Client.MaxArenaOpponents, published as MSUF_MAX_ARENA_FRAMES).
local ARENA_SLOTS = tonumber(MSUF.Client and MSUF.Client.MaxArenaOpponents)
    or (IS_CLASSIC_FAMILY and tonumber(MSUF_MAX_ARENA_FRAMES)) or 3
local AURA_ARENA_RUNTIME_UNITS = (function()
    local units = WL("arena1 arena2 arena3")
    for arenaIndex = 4, ARENA_SLOTS do units[#units + 1] = "arena" .. arenaIndex end
    return units
end)()
local UF_COPY_CATEGORIES = {
    { key = "basics",       label = "Basics",     default = true, description = "Copies the frame toggle, fill direction and health coloring, plus this unit's Bars overrides: bar textures, outline, highlight priority, gradient, absorb and heal prediction." },
    { key = "text",         label = "Text",             default = true, description = "Copies every text slot with its content, size and position, plus this unit's font overrides: font, outline, shadow, text color and name shortening." },
    { key = "portrait",     label = "Portrait",         default = true },
    { key = "power",        label = "Power Bar",        default = true },
    { key = "auras",        label = "Aura Options",     default = true, description = "Copies this UnitFrame's Aura visibility, layout, filters, blacklists, Custom Aura setup and tracked spells. Aura Style and the global Appearance theme remain unchanged." },
    { key = "aurastyle",    label = "Aura Style",       default = true, description = "Copies this UnitFrame's Buff, Debuff, Custom Aura, Player Defensive and Dots on Target presentation, including text, swipe, icon zoom, duration bars, Pandemic and Full-Frame effects. Aura Options and the global Appearance theme remain unchanged." },
    { key = "castbar",      label = "Castbar",          default = true },
    { key = "status",       label = "Status Icons",     default = true },
    { key = "load",         label = "Visibility",  default = true },
    { key = "transparency", label = "Transparency",     default = true },
    { key = "texlayer",     label = "Texture Layer",    default = true },
    { key = "layout",       label = "Frame Size",       default = false,
        description = "Copies the frame width and height only. Position and anchoring never travel with a copy; place frames in MSUF Edit Mode." },
}
local function NewCopyScopeDefaults()
    local t = {}
    for i = 1, #UF_COPY_CATEGORIES do
        local cat = UF_COPY_CATEGORIES[i]
        t[cat.key] = cat.default ~= false
    end
    return t
end
local UNIT_COPY_TARGETS = DropUnsupportedUnits(VTP "player=Player|target=Target|targettarget=Target of Target|focustarget=Focus Target|focus=Focus|pet=Pet|pettarget=Pet Target|boss=Boss Frames|arena=Arena Frames")
local UNIT_LABELS = { player = "Player", target = "Target", targettarget = "Target of Target", focustarget = "Focus Target", focus = "Focus", pet = "Pet",
    pettarget = "Pet Target", boss = "Boss Frames", arena = "Arena Frames" }
local UNIT_PILL_WIDTHS = { targettarget = 116, focustarget = 104, boss = 92, arena = 92, target = 62, focus = 58, pet = 46, pettarget = 104 }
local function DefaultCopyTarget(unit)
    for i = 1, #UNIT_COPY_TARGETS do
        local value = UNIT_COPY_TARGETS[i].value
        if value ~= unit then return value end
    end
    return "target"
end
local function UnitTopLabel(unit)
    local label = UNIT_LABELS[unit] or tostring(unit or "")
    return (M.Tr and M.Tr(label)) or label
end
function UnitPage.UnitTopPillWidth(unit)
    return UNIT_PILL_WIDTHS[unit] or 56
end
local UNIT_KEY_SET = KSW("player target targettarget focustarget focus pet pettarget boss arena")
local function CanonUnitKey(key)
    if type(key) ~= "string" then return key end
    key = key:lower()
    if key == "tot" or key == "targetoftarget" or key == "target_of_target" then return "targettarget" end
    if key == "focus_target" or key == "focustargettarget" then return "focustarget" end
    if key:match("^boss") then return "boss" end
    if key:match("^arena") then return "arena" end
    return key
end
-- Older profiles stored these units' tables under other names; the first one found moves over.
local UNIT_DB_ALIASES = { targettarget = WL "tot targetoftarget target_of_target", focustarget = WL "focus_target focustargettarget" }
local function EnsureUnitDB(key)
    local db = M.EnsureDB()
    key = CanonUnitKey(key)
    if not UNIT_KEY_SET[key] then return nil, nil end
    local aliases = UNIT_DB_ALIASES[key]
    if aliases then
        if type(db[key]) ~= "table" then
            local found
            for i = 1, #aliases do
                if not found and type(db[aliases[i]]) == "table" then found = db[aliases[i]] end
            end
            db[key] = found or {}
        end
        for i = 1, #aliases do db[aliases[i]] = nil end
        return db[key], key
    end
    db[key] = db[key] or {}
    return db[key], key
end
local function CopyFields(dst, src, fields)
    for i = 1, #fields do
        local key = fields[i]
        local value = src[key]
        --- Table-valued scope keys (highlight priority order, gradient key sets) must be
        --- cloned: a shallow assign would alias both unit configs onto one table, so a
        --- later edit on either unit would silently change the other.
        if type(value) == "table" then value = DeepCopy(value) end
        dst[key] = value
    end
end
local PB_SHOW_KEY_MAP = {
    player = "showPlayerPowerBar",
    target = "showTargetPowerBar",
    focus = "showFocusPowerBar",
    boss = "showBossPowerBar",
    arena = "showArenaPowerBar",
}
local PB_SHOW_DEFAULTS = {
    player = true,
    target = true,
    focus = true,
    targettarget = false,
    focustarget = false,
    pet = true,
    pettarget = false,
    boss = true,
    arena = true,
}
local function ConfBool(value) if value ~= nil then return true, value ~= false end end
local function ConfTrue(value) if value ~= nil then return true, value == true end end
local function ConfNumber(value) if type(value) == "number" then return true, value end end
local function BarsDB()
    return M.EnsureDB().bars
end
local POWER_COPY_OVERRIDES = {
    { key = "showPowerBar", fn = "MSUF_ReadUnitPowerBarEnabled", read = ConfBool, fallback = function(unitKey)
        local b, bk = BarsDB(), PB_SHOW_KEY_MAP[unitKey]
        if b and bk and b[bk] ~= nil then return b[bk] ~= false end
        return PB_SHOW_DEFAULTS[unitKey] ~= false
    end },
    { key = "powerBarHeight", fn = "MSUF_ReadUnitPowerBarHeight", read = ConfNumber, fallback = function()
        local b = BarsDB()
        return tonumber(b and b.powerBarHeight) or 3
    end },
    { key = "embedPowerBarIntoHealth", fn = "MSUF_ReadUnitPowerBarEmbed", read = ConfTrue, fallback = function()
        local b = BarsDB()
        return b and b.embedPowerBarIntoHealth == true
    end },
    { key = "powerBarBorderEnabled", fn = "MSUF_ReadUnitPowerBarBorderEnabled", read = ConfTrue, fallback = function()
        local b = BarsDB()
        return b and b.powerBarBorderEnabled == true
    end },
    { key = "powerBarBorderThickness", fn = "MSUF_ReadUnitPowerBarBorderThickness", read = ConfNumber, fallback = function()
        local b = BarsDB()
        return tonumber(b and (b.powerBarBorderThickness or b.powerBarBorderSize)) or 1
    end },
    { key = "powerSmoothFill", read = ConfTrue, fallback = function(unitKey)
        if unitKey ~= "player" then return false end
        local b = BarsDB()
        return b and b.smoothPowerBar == true or false
    end },
    { key = "powerChunkedFill", read = ConfTrue, fallback = function(unitKey)
        if unitKey ~= "player" then return false end
        local b = BarsDB()
        return b and b.chunkedPowerBar == true or false
    end },
}
local function ReadPowerCopyValue(conf, unitKey, spec)
    local fn = spec.fn and MSUF.Optional(spec.fn)
    if type(fn) == "function" then return fn(unitKey) end
    local ok, value = spec.read(conf and conf[spec.key])
    if ok then return value end
    return spec.fallback(unitKey)
end
local function CopyPowerBarFields(dst, src, srcKey, dstKey)
    CopyFields(dst, src, COPY_POWER_BAR_FIELDS)
    for i = 1, #POWER_COPY_OVERRIDES do
        local spec = POWER_COPY_OVERRIDES[i]
        dst[spec.key] = ReadPowerCopyValue(src, srcKey, spec)
    end
    if dstKey == "player" then
        local bars = BarsDB()
        if bars then
            local thickness = tonumber(dst.powerBarBorderThickness) or 1
            bars.detachedPowerBarOutline = dst.powerBarBorderEnabled == true and thickness or 0
        end
    end
end
-- Plain castbar keys by CASTBAR_FIELDS name; the Player castbar has no targetName, which is skipped.
local CASTBAR_COPY_FIELDS = WL "time icon text targetName timeFormat w h match"
local function CopyCastbarValue(g, sourceKey, destinationKey)
    if not sourceKey or not destinationKey then return end
    local value = g[sourceKey]
    --- General defaults normally hydrate every castbar key. Still, an older or
    --- partially migrated profile can omit one; absence must not erase a valid
    --- destination value during a copy.
    if value ~= nil then g[destinationKey] = value end
end
local function CopyCastbar(g, src, dst)
    src, dst = CanonUnitKey(src), CanonUnitKey(dst)
    local s, d = CASTBAR_FIELDS[src], CASTBAR_FIELDS[dst]
    if not s or not d then return end
    local backend = MSUF.Require("MSUF_NormalizeCastbarBackendForUnit", SELF)(dst, g[s.backend]) or g[s.backend]
    if backend == nil then backend = (g[s.enable] == false) and ((dst == "player") and "BLIZZARD" or "HIDE") or "MSUF" end
    if backend == "BLIZZARD" and dst ~= "player" then backend = "HIDE" end
    local remembered = g[s.providerMemory]
    if remembered == "BLIZZARD" and dst ~= "player" then remembered = "MSUF" end
    g[d.enable] = (backend == "MSUF")
    g[d.backend] = backend
    if remembered ~= nil then g[d.providerMemory] = remembered end
    for i = 1, #CASTBAR_COPY_FIELDS do
        local field = CASTBAR_COPY_FIELDS[i]
        CopyCastbarValue(g, s[field], d[field])
    end
    local srcPrefix = s.stylePrefix
    local dstPrefix = d.stylePrefix
    if not srcPrefix or not dstPrefix then return true end
    for i = 1, #CASTBAR_COPY_SUFFIXES do
        local suffix = CASTBAR_COPY_SUFFIXES[i]
        CopyCastbarValue(g, srcPrefix .. suffix, dstPrefix .. suffix)
    end
    --- Only meaningful while both castbars hang off their own unit frame. A detached
    --- source stores an absolute screen position, and a detached destination would
    --- reinterpret the copied gap as one, so leave the destination where it is.
    if g[s.detached] ~= true and g[d.detached] ~= true then
        CopyCastbarValue(g, s.offsetX, d.offsetX)
        CopyCastbarValue(g, s.offsetY, d.offsetY)
    end
    if s.targetName and d.targetName then
        for i = 1, #CASTBAR_TARGET_NAME_COPY_SUFFIXES do
            local suffix = CASTBAR_TARGET_NAME_COPY_SUFFIXES[i]
            CopyCastbarValue(g, srcPrefix .. suffix, dstPrefix .. suffix)
        end
    end
    return true
end
local function AuraRuntimeSource(unit)
    unit = CanonUnitKey(unit)
    if unit == "boss" then return "boss1" end
    if unit == "arena" then return "arena1" end
    return unit
end
local function ForEachAuraRuntimeTarget(unit, callback)
    unit = CanonUnitKey(unit)
    if unit == "boss" then
        for i = 1, #AURA_BOSS_RUNTIME_UNITS do callback(AURA_BOSS_RUNTIME_UNITS[i]) end
        return
    end
    if unit == "arena" then
        for i = 1, #AURA_ARENA_RUNTIME_UNITS do callback(AURA_ARENA_RUNTIME_UNITS[i]) end
        return
    end
    callback(unit)
end
local function ApplyAuras3Unit(unit)
    local apply = M.ApplyService or MSUF.Require("MSUF_Menu2_ApplyService", SELF)
    return apply.RequestAuras(unit, "MSUF2_COPY_UNIT_AURAS")
end
local AURA_COPY_DEFAULTS = { enabled = true, showPlayer = false, showPet = true, showTarget = true, showFocus = true,
    showBoss = true, showArena = true }
local function EnsureAuras3CopyDB()
    local a3 = MSUF and MSUF.MSUF_Auras3
    local model = a3 and a3.MenuModel
    local auras
    if model and type(model.EnsureDB) == "function" then
        auras = model.EnsureDB()
    elseif a3 and type(a3.EnsureDB) == "function" then
        auras = a3.EnsureDB()
    else
        local db = M.EnsureDB()
        if type(db) ~= "table" then return nil end
        if type(db.auras3) ~= "table" then db.auras3 = {} end
        auras = db.auras3
    end
    if type(auras) ~= "table" then return nil end
    for key, default in pairs(AURA_COPY_DEFAULTS) do
        if auras[key] == nil then auras[key] = default end
    end
    if type(auras.perUnit) ~= "table" then auras.perUnit = {} end
    return auras
end
local function CopyAuras3UnitSettings(src, dst)
    src, dst = CanonUnitKey(src), CanonUnitKey(dst)
    if not AURA_COPY_UNITS[src] or not AURA_COPY_UNITS[dst] then return false end
    local auras = EnsureAuras3CopyDB()
    if type(auras) ~= "table" then return false end

    local a3 = MSUF and MSUF.MSUF_Auras3
    local model = a3 and a3.MenuModel
    local destinationStyle = model and type(model.CaptureUnitStyle) == "function"
        and model.CaptureUnitStyle(dst) or nil
    -- Materialize the source's frame-owned lists before copying. This also
    -- completes the one-time legacy Shared whitelist migration when needed.
    if model and type(model.CustomContainers) == "function" then model.CustomContainers(src, true) end

    local srcFlag, dstFlag = AURA_COPY_FLAGS[src], AURA_COPY_FLAGS[dst]
    if srcFlag and dstFlag then
        local enabled = auras[srcFlag] == true
        if enabled then auras.enabled = true end
        auras[dstFlag] = enabled and true or false
    end

    local sourceConfig = auras.perUnit[AuraRuntimeSource(src)]
    ForEachAuraRuntimeTarget(dst, function(runtimeUnit)
        auras.perUnit[runtimeUnit] = type(sourceConfig) == "table" and DeepCopy(sourceConfig) or nil
    end)

    local function CopyScopedAuraRecord(rootKey, preserveIncompatibleSpecial)
        local root = auras[rootKey]
        if type(root) ~= "table" then return end
        root.perUnit = type(root.perUnit) == "table" and root.perUnit or {}
        local destinationSpecial
        if preserveIncompatibleSpecial and model and type(model.CustomContainer) == "function"
            and ((src == "player") ~= (dst == "player"))
        then
            destinationSpecial = DeepCopy(model.CustomContainer(dst, 4, true))
        end
        local source = root.perUnit[src]
        root.perUnit[dst] = type(source) == "table" and DeepCopy(source) or nil
        if destinationSpecial then
            root.perUnit[dst] = type(root.perUnit[dst]) == "table" and root.perUnit[dst] or { items = {} }
            root.perUnit[dst].items = type(root.perUnit[dst].items) == "table" and root.perUnit[dst].items or {}
            root.perUnit[dst].items[4] = destinationSpecial
        end
    end
    -- Custom containers are intentionally outside auras.perUnit. Copy both
    -- the native containers and the legacy per-frame migration record so no
    -- whitelist or Full-Frame configuration is silently left behind.
    CopyScopedAuraRecord("customContainers", true)
    CopyScopedAuraRecord("customDisplays")
    if model and type(model.CustomContainer) == "function" then model.CustomContainer(dst, 4, true) end
    if destinationStyle and type(model.ApplyUnitStyleSnapshot) == "function" then
        model.ApplyUnitStyleSnapshot(dst, destinationStyle)
    end
    ApplyAuras3Unit(dst)
    return true
end
local function CopyAuras3UnitStyle(src, dst)
    src, dst = CanonUnitKey(src), CanonUnitKey(dst)
    if not AURA_COPY_UNITS[src] or not AURA_COPY_UNITS[dst] then return false end
    local a3 = MSUF and MSUF.MSUF_Auras3
    local model = a3 and a3.MenuModel
    if not (model and type(model.CopyUnitStyle) == "function") then return false end
    if model.CopyUnitStyle(src, dst) ~= true then return false end
    ApplyAuras3Unit(dst)
    return true
end
local function ConfirmCopyToAll(callback)
    if type(callback) ~= "function" then return end
    M.ShowPrompt("MSUF2_COPY_TO_ALL_CONFIRM", {
        text = M.Tr("Copy these settings to ALL unitframes?\n\nThis will overwrite existing settings on Player/Target/Focus/Boss/Pet/Target of Target/Focus Target/Arena/Pet Target."),
        onAccept = callback,
    })
end
local AURA_COPY_SCOPE_KEYS = { auras = true, aurastyle = true }
local function SelectedCopyScopeState(scopes)
    local anySelected, nonAuraSelected, nonCastbarSelected = false, false, false
    for i = 1, #UF_COPY_CATEGORIES do
        local key = UF_COPY_CATEGORIES[i].key
        if scopes[key] == true then
            anySelected = true
            if not AURA_COPY_SCOPE_KEYS[key] then
                nonAuraSelected = true
                if key ~= "castbar" then nonCastbarSelected = true end
            end
        end
    end
    return anySelected, nonAuraSelected, nonCastbarSelected
end
local function CompleteUnitCopy(callback, applied, result)
    if type(callback) == "function" then callback(applied == true, result) end
    return applied == true, result
end
function UnitPage.CopyUnitSettings(unit, target, scopes, onComplete, allConfirmed)
    local profileDB = M.EnsureDB()
    profileDB.general = profileDB.general or {}
    local g = profileDB.general
    local src, srcKey = EnsureUnitDB(unit)
    if not src or not srcKey then
        return CompleteUnitCopy(onComplete, false, { reason = "invalid_source", source = unit, destination = target })
    end
    target = (type(target) == "string") and target:lower() or DefaultCopyTarget(srcKey)
    scopes = (type(scopes) == "table") and scopes or NewCopyScopeDefaults()
    local anySelected, nonAuraSelected, nonCastbarSelected = SelectedCopyScopeState(scopes)
    if not anySelected then
        return CompleteUnitCopy(onComplete, false, {
            reason = "no_categories", source = srcKey, destination = target,
            anySelected = false, nonAuraSelected = false,
        })
    end
    local function CopyOne(toKey)
        local dst, dstKey = EnsureUnitDB(toKey)
        local result = {
            source = srcKey,
            destination = dstKey or toKey,
            anySelected = anySelected,
            nonAuraSelected = nonAuraSelected,
            auraOptionsRequested = scopes.auras == true,
            auraStyleRequested = scopes.aurastyle == true,
            castbarRequested = scopes.castbar == true,
        }
        if not dst or not dstKey then
            result.reason = "invalid_destination"
            return false, result
        end
        if dstKey == srcKey then
            result.reason = "same_destination"
            return false, result
        end
        result.castbarSupported = CASTBAR_FIELDS[srcKey] ~= nil and CASTBAR_FIELDS[dstKey] ~= nil
        result.castbarSkipped = result.castbarRequested and not result.castbarSupported
        if scopes.basics then CopyFields(dst, src, COPY_FRAME_BASIC_FIELDS) end
        --- The override gate flags travel with their values on purpose. Clearing them
        --- here would leave the destination showing the copied values on the frame while
        --- the Global pages still report the shared ones for that scope.
        if scopes.text then CopyFields(dst, src, COPY_TEXT_FIELDS) end
        if scopes.portrait then CopyFields(dst, src, COPY_PORTRAIT_FIELDS) end
        if scopes.power then CopyPowerBarFields(dst, src, srcKey, dstKey) end
        local copiedAuraOptions = scopes.auras and CopyAuras3UnitSettings(srcKey, dstKey) or false
        local copiedAuraStyle = scopes.aurastyle and CopyAuras3UnitStyle(srcKey, dstKey) or false
        local copiedAuras = copiedAuraOptions or copiedAuraStyle
        result.auraOptionsApplied = copiedAuraOptions == true
        result.auraStyleApplied = copiedAuraStyle == true
        result.auraSupported = AURA_COPY_UNITS[srcKey] == true and AURA_COPY_UNITS[dstKey] == true
        result.auraSkipped = (result.auraOptionsRequested and not result.auraOptionsApplied)
            or (result.auraStyleRequested and not result.auraStyleApplied)
        local copiedAny = nonCastbarSelected
            or (result.castbarRequested and result.castbarSupported)
            or copiedAuras
        if not copiedAny then
            if result.castbarSkipped then
                result.reason = "unsupported_castbar_scope"
            else
                result.reason = result.auraSupported and "aura_copy_unavailable" or "unsupported_aura_scope"
            end
            return false, result
        end
        if scopes.status then
            CopyFields(dst, src, COPY_INDICATOR_FIELDS)
            CopyFields(dst, src, COPY_STATUSICON_FIELDS)
        end
        if result.castbarRequested and result.castbarSupported then
            dst.showInterrupt = src.showInterrupt
            dst.showInterruptSource = src.showInterruptSource
            MSUF.Castbars.Config.Invalidate()
            if CopyCastbar(g, srcKey, dstKey) then
                result.castbarApplied = true
                MSUF.Castbars.Config.Invalidate()
                MSUF.Require("MSUF_UpdateCastbarWidthSourceSync", SELF)(g, dstKey)
            end
        end
        if scopes.load then CopyFields(dst, src, COPY_LOAD_CONDITION_FIELDS) end
        if scopes.transparency then CopyFields(dst, src, COPY_TRANSPARENCY_FIELDS) end
        if scopes.texlayer then CopyFields(dst, src, COPY_TEXLAYER_FIELDS) end
        if scopes.layout then CopyFields(dst, src, COPY_LAYOUT_FIELDS) end
        M.RequestUnitDomains(dstKey, "MSUF2_COPY_UNIT", {
            preview = true,
            text = scopes.text or scopes.status,
            power = scopes.power,
            alpha = scopes.transparency,
            castbar = result.castbarApplied == true,
            auras = copiedAuras,
            --- Text carries this unit's font override scope, which needs the font runtime
            --- rebuilt for the destination rather than a plain layout pass.
            fonts = scopes.text,
        })
        result.applied = true
        return true, result
    end
    local function FinishCopy(statusUnit)
        if scopes.status then
            MSUF.Require("MSUF_RefreshStatusIndicators", SELF)(statusUnit, "MSUF2_COPY_UNIT_STATUS")
        end
    end
    if target == "all" then
        local function CopyAll()
            local summary = {
                source = srcKey, destination = "all", anySelected = anySelected,
                nonAuraSelected = nonAuraSelected, targets = {}, appliedTargets = 0,
                auraOptionsRequested = scopes.auras == true,
                auraStyleRequested = scopes.aurastyle == true,
                castbarRequested = scopes.castbar == true,
            }
            for i = 1, #UNIT_COPY_TARGETS do
                local value = UNIT_COPY_TARGETS[i].value
                if value ~= srcKey then
                    local applied, result = CopyOne(value)
                    summary.targets[value] = result
                    if applied then summary.appliedTargets = summary.appliedTargets + 1 end
                    if result and result.auraSkipped then summary.auraSkipped = true end
                    if result and result.castbarSkipped then summary.castbarSkipped = true end
                end
            end
            if summary.appliedTargets > 0 then FinishCopy() end
            summary.applied = summary.appliedTargets > 0
            if not summary.applied then
                if summary.castbarRequested and summary.castbarSkipped then
                    summary.reason = "unsupported_castbar_scope"
                else
                    summary.reason = (summary.auraOptionsRequested or summary.auraStyleRequested)
                        and "unsupported_aura_scope" or "nothing_copied"
                end
            end
            return CompleteUnitCopy(onComplete, summary.applied, summary)
        end
        if allConfirmed == true then return CopyAll() end
        ConfirmCopyToAll(CopyAll)
        return nil, { pending = true, source = srcKey, destination = "all" }
    end
    target = CanonUnitKey(target)
    if not target or target == srcKey then
        return CompleteUnitCopy(onComplete, false, {
            reason = target == srcKey and "same_destination" or "invalid_destination",
            source = srcKey, destination = target,
        })
    end
    local applied, result = CopyOne(target)
    if applied then FinishCopy(target) end
    return CompleteUnitCopy(onComplete, applied, result)
end
function UnitPage.ToggleEditMode(unit)
    if M.BlockCombatAction() then return end
    if InCombatLockdown and InCombatLockdown() then
        M.ShowConfigCombatLockMessage()
        return
    end
    local active = previewState.editMode == true
    MSUF.Require("MSUF_SetMSUFEditModeDirect", SELF)(not active, CanonUnitKey(unit))
end
function UnitPage.IsEditModeActive()
    return previewState.editMode == true
end
local function PagePreviewInCombat()
    return (InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player"))
end
--- The engine's live frame reader, bound the same way every other Menu2
--- file binds it (PagePreviews, UnitPreview_Castbar, UnitPreview_Runtime).
local CoreFrame = MSUF.UF.GetFrame
local function ArenaPreviewFramesVisible()
    local sawFrame = false
    for i = 1, ARENA_SLOTS do
        local unit = "arena" .. i
        local frame = CoreFrame(unit) or _G["MSUF_" .. unit]
        if frame then
            sawFrame = true
            if frame.IsShown and not frame:IsShown() then return false end
        end
    end
    return sawFrame
end
--- Boss and Arena page preview coordinators, one state table each, working
--- against the preview globals/entry points the engine exports. While the page is
--- open the engine shows its preview frames (stateKey is the page flag in the
--- preview state, unitKey the unit flag); combat clears them at once and remembers
--- the out-of-combat rebuild. `events` and `pendingCleanup` are the page's own event
--- frame and rebuild flag, `sync` its shared sync closure.
local function PagePreviewClear(page)
    if not page.clearResolved then
        page.clearResolved = true
        page.clearFn = MSUF.Optional(page.clear)
    end
    local clear = page.clearFn
    return type(clear) == "function" and clear() == true
end
local function SyncPagePreview(page)
    local active = (previewState[page.stateKey] == true)
    if PagePreviewInCombat() then
        local cleared = PagePreviewClear(page)
        page.setPage(nil)
        if active or cleared then page.pendingCleanup = true end
        return
    end
    local apply = page.applyFn or MSUF.Require(page.apply, SELF)
    page.applyFn = apply
    apply(active, active and page.reasonOn or page.reasonOff)
end
local function NewPagePreview(page)
    page.sync = function() SyncPagePreview(page) end
    return page
end
local BOSS_PAGE = NewPagePreview({
    stateKey = "bossPage", unitKey = "boss", setPage = SetBossPage, framesVisible = M.BossPreviewFramesVisible,
    clear = "MSUF_ClearBossUnitframePreviewForCombat", apply = "MSUF_ApplyBossUnitframePreviewState",
    reasonOn = "MSUF2_BOSS_PAGE", reasonOff = "MSUF2_BOSS_PAGE_OFF",
})
local ARENA_PAGE = NewPagePreview({
    stateKey = "arenaPage", unitKey = "arena", setPage = SetArenaPage, framesVisible = ArenaPreviewFramesVisible,
    clear = "MSUF_ClearArenaUnitframePreviewForCombat", apply = "MSUF_ApplyArenaUnitframePreviewState",
    reasonOn = "MSUF2_ARENA_PAGE", reasonOff = "MSUF2_ARENA_PAGE_OFF",
})
local function EnsurePagePreviewEvents(page)
    if page.events then return page.events end
    local events = CreateFrame("Frame")
    page.events = events
    events:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            -- Another Menu2 coordinator may already have cleared the global
            -- flag. Always run the frame handoff and remember the OOC rebuild.
            PagePreviewClear(page)
            page.setPage(nil)
            page.pendingCleanup = true
            return
        end
        if event == "PLAYER_REGEN_ENABLED" and page.pendingCleanup then
            page.pendingCleanup = nil
            SyncPagePreview(page)
            if previewState[page.stateKey] ~= true then self:UnregisterAllEvents() end
            return
        end
        if previewState[page.stateKey] == true then SyncPagePreview(page) end
    end)
    return events
end
local function SetPagePreviewActive(page, active)
    active = active and true or false
    if active and PagePreviewInCombat() then
        PagePreviewClear(page)
        page.setPage(nil)
        page.pendingCleanup = nil
        if page.events then page.events:UnregisterAllEvents() end
        return
    end
    local current = previewState[page.stateKey] == true
    if current == active then
        if active and not PagePreviewInCombat() and not page.framesVisible() then SyncPagePreview(page) end
        if not active and previewState[page.unitKey] == true and not PagePreviewInCombat() then SyncPagePreview(page) end
        return
    end
    page.setPage(active or nil)
    local events = EnsurePagePreviewEvents(page)
    if active then
        page.pendingCleanup = nil
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    elseif PagePreviewInCombat() then
        page.pendingCleanup = true
        events:UnregisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    else
        page.pendingCleanup = nil
        events:UnregisterAllEvents()
    end
    SyncPagePreview(page)
    if active then
        C_Timer.After(0, page.sync)
        C_Timer.After(0.12, page.sync)
    end
end
local function SetBossPagePreviewActive(active) return SetPagePreviewActive(BOSS_PAGE, active) end
local function SetArenaPagePreviewActive(active) return SetPagePreviewActive(ARENA_PAGE, active) end
function UnitPage.ReadBool(unit, key, default)
    local conf = GetConf(unit)
    local value = conf[key]
    if value == nil then return default and true or false end
    return value and true or false
end
function UnitPage.SetBool(unit, key, value, reason, opts)
    M.SetUnitValue(unit, key, value and true or false, reason, opts)
end
function UnitPage.ReadNumber(unit, key, default)
    local conf = GetConf(unit)
    local value = tonumber(conf[key])
    if value == nil then value = default or 0 end
    return value
end
function UnitPage.SetNumber(unit, key, value, reason, opts)
    value = tonumber(value)
    if value == nil then return end
    if math.abs(value - floor(value + 0.5)) < 0.001 then value = floor(value + 0.5) end
    M.SetUnitValue(unit, key, value, reason, opts)
end
function UnitPage.IsPlayerPowerManagedByClassResources(unit)
    if unit ~= "player" then return false end
    local conf = GetConf("player")
    if not (conf and conf.powerBarDetached == true) then return false end
    return conf.detachedPowerBarAnchorToClassPower == true
end
function UnitPage.SetString(unit, key, value, reason, opts)
    M.SetUnitValue(unit, key, tostring(value or ""), reason, opts)
end
function UnitPage.ReadGeneralBool(key, default)
    local g = GetGeneral()
    local value = g[key]
    if value == nil then return default and true or false end
    return value and true or false
end
function UnitPage.SetGeneralBool(key, value, reason, opts)
    M.SetGeneralValue(key, value and true or false, reason, opts)
end
function UnitPage.ClampStatusLayer(value, default)
    value = tonumber(value) or default or 7
    value = floor(value + 0.5)
    if value < 0 then return 0 end
    if value > 30 then return 30 end
    return value
end
local function StatusAllowed(unit, spec)
    return spec and (not spec.allowed or spec.allowed(unit))
end
function UnitPage.StatusValues(unit)
    local values = {}
    for i = 1, #STATUS_CONTROLS do
        local spec = STATUS_CONTROLS[i]
        if StatusAllowed(unit, spec) then values[#values + 1] = { value = spec.value, text = spec.text } end
    end
    return values
end
local function FindStatusSpec(unit, value)
    for i = 1, #STATUS_CONTROLS do
        local spec = STATUS_CONTROLS[i]
        if spec.value == value and StatusAllowed(unit, spec) then return spec end
    end
    for i = 1, #STATUS_CONTROLS do
        local spec = STATUS_CONTROLS[i]
        if StatusAllowed(unit, spec) then return spec end
    end
    return nil
end
function UnitPage.CurrentStatusSpec(unit)
    M.unitStatusSelection = M.unitStatusSelection or {}
    local spec = FindStatusSpec(unit, M.unitStatusSelection[unit])
    if spec then M.unitStatusSelection[unit] = spec.value end
    return spec
end
function UnitPage.ReadStatusBool(unit, key, default)
    local conf = GetConf(unit)
    local g = GetGeneral()
    local value = conf[key]
    if value == nil then value = g[key] end
    if value == nil then return default and true or false end
    return value and true or false
end
function UnitPage.ReadStatusNumber(unit, key, default, legacyKey)
    local conf = GetConf(unit)
    local g = GetGeneral()
    local value = tonumber(conf[key])
    if value == nil and legacyKey then value = tonumber(conf[legacyKey]) end
    if value == nil then value = tonumber(g[key]) end
    if value == nil and legacyKey then value = tonumber(g[legacyKey]) end
    if value == nil then value = default or 0 end
    return value
end
function UnitPage.ReadStatusString(unit, key, default, legacyKey)
    local conf = GetConf(unit)
    local g = GetGeneral()
    local value = conf[key]
    if (type(value) ~= "string" or value == "") and legacyKey then value = conf[legacyKey] end
    if type(value) ~= "string" or value == "" then value = g[key] end
    if (type(value) ~= "string" or value == "") and legacyKey then value = g[legacyKey] end
    if type(value) ~= "string" or value == "" then value = default end
    return value or ""
end
-- Core refresh entry points by global name, resolved on first use: this runs on every
-- status setting change, a slider drag included.
local StatusRuntimeFns = {}
function UnitPage.RefreshStatusRuntime(unit, spec)
    local runtimeRefreshed = false
    if spec and spec.refresh then
        local refresh = StatusRuntimeFns[spec.refresh] or MSUF.Require(spec.refresh, SELF)
        StatusRuntimeFns[spec.refresh] = refresh
        runtimeRefreshed = true, refresh(unit, "MSUF2_STATUS_INDICATOR")
    end
    if spec and spec.statusRuntime and not runtimeRefreshed then
        local indicators = StatusRuntimeFns.MSUF_RefreshStatusIndicators or MSUF.Require("MSUF_RefreshStatusIndicators", SELF)
        StatusRuntimeFns.MSUF_RefreshStatusIndicators = indicators
        indicators(unit, "MSUF2_STATUS_INDICATOR")
    end
    if spec and spec.value == "level" then
        if unit == "boss" and previewState.boss == true then
            local preview = StatusRuntimeFns.MSUF_ApplyBossUnitframePreviewState or MSUF.Require("MSUF_ApplyBossUnitframePreviewState", SELF)
            StatusRuntimeFns.MSUF_ApplyBossUnitframePreviewState = preview
            preview(true, "MSUF2_LEVEL_INDICATOR")
        end
    end
    M.RequestUnitDomains(unit, "MSUF2_STATUS_INDICATOR", { preview = true, text = true, fonts = spec and spec.value == "level" })
end
-- Text keys are read with a general fallback (ReadText), so no seeding step
-- writes the general values into the unit config (SeedText is the plain config).
function UnitPage.ReadText(unit, key, default)
    local conf = GetConf(unit)
    if conf[key] ~= nil then return conf[key] end
    local g = GetGeneral()
    if g[key] ~= nil then return g[key] end
    return default
end
function UnitPage.SetText(unit, key, value, reason)
    local conf = GetConf(unit)
    if conf[key] == value then return end
    conf[key] = value
    conf.hpPowerTextOverride = nil
    M.RequestUnitDomains(unit, reason or "MSUF2_TEXT", { text = true, preview = true })
end
function UnitPage.NormalizePortrait(unit)
    local conf = GetConf(unit)
    local value = conf.portraitMode or "OFF"
    if value ~= "LEFT" and value ~= "RIGHT" then value = "OFF" end
    return value
end
function UnitPage.SetPortraitValue(unit, key, value, reason)
    local mask = { preview = true }
    if unit == "player" then
        local a3 = MSUF and MSUF.MSUF_Auras3
        local model = a3 and a3.MenuModel
        local defensive = model and type(model.CustomContainer) == "function"
            and model.CustomContainer("player", 4, false)
        if defensive and defensive.portraitIcon == true then mask.auras = true end
    end
    M.SetUnitValue(unit, key, value, reason or "MSUF2_PORTRAIT", mask)
end
function UnitPage.NormalizeBossLayoutMode(value, legacyInvert)
    if type(value) == "string" and BOSS_LAYOUT_VALID[value] then return value end
    if legacyInvert == true then return "VERTICAL_UP" end
    return "VERTICAL_DOWN"
end
function UnitPage.UpdateLoadActive(unit)
    local conf = GetConf(unit)
    local active = conf.loadCondShowWhenInjured == true
    for i = 1, #LOAD_CONDITIONS do
        if conf[LOAD_CONDITIONS[i].key] == true then
            active = true
            break
        end
    end
    conf.loadCondActive = active or nil
end
-- Status icon helpers the unit and group status pages share.
--- Every icon asset the status preview entries offer (the first entry's
--- list first, no repeats), or the single "Use default icon" row.
local assetValuesFn
function UnitPage.StatusIconAssetValues(entries)
    if type(entries) ~= "table" then
        return { { value = "", text = "Use default icon" } }
    end
    assetValuesFn = assetValuesFn or MSUF.Require("MSUF_GetStatusIconAssetValues", SELF)
    local valuesFn = assetValuesFn
    local out, used = {}, {}
    for i = 1, #entries do
        local entry = entries[i]
        local values = valuesFn(entry[1], entry[2], i == 1, true)
        for j = 1, #(values or {}) do
            local item = values[j]
            local value = item and item.value
            if type(value) == "string" and not used[value] then
                used[value] = true
                out[#out + 1] = item
            end
        end
    end
    if #out == 0 then out[1] = { value = "", text = "Use default icon" } end
    return out
end

--- The five-slot icon preview strip of a status card, at (16, y) inside the
--- card: dark holders with a centred 22 px texture each.
function UnitPage.CreateStatusIconStrip(card, y, width)
    local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", SELF)
    local iconPreviewStrip = PixelLayoutRegion(CreateFrame("Frame", nil, card))
    iconPreviewStrip:SetPoint("TOPLEFT", card, "TOPLEFT", 16, y)
    iconPreviewStrip:SetSize(width, 24)
    local holders = {}
    for i = 1, 5 do
        local holder = PixelLayoutRegion(CreateFrame("Frame", nil, iconPreviewStrip))
        holder:SetSize(24, 24)
        holder:SetPoint("LEFT", iconPreviewStrip, "LEFT", (i - 1) * 28, 0)
        holder.bg = PixelLayoutRegion(holder:CreateTexture(nil, "BACKGROUND"))
        holder.bg:SetAllPoints()
        holder.bg:SetColorTexture(0.020, 0.026, 0.052, 0.70)
        holder.tex = PixelLayoutRegion(holder:CreateTexture(nil, "ARTWORK"))
        holder.tex:SetPoint("CENTER", holder, "CENTER", 0, 0)
        holder.tex:SetSize(22, 22)
        holders[i] = holder
    end
    return iconPreviewStrip, holders
end
M.Assign(UnitPage, {
    SectionFields = {
        portrait = table.concat(COPY_PORTRAIT_FIELDS, " "),
        power_bar = table.concat(COPY_POWER_BAR_FIELDS, " "),
        text = table.concat(COPY_TEXT_FIELDS, " "),
        transparency = table.concat(COPY_TRANSPARENCY_FIELDS, " "),
        load_conditions = table.concat(COPY_LOAD_CONDITION_FIELDS, " "),
        texture_layer = table.concat(COPY_TEXLAYER_FIELDS, " "),
    },
    UNIT_PAGES = UNIT_PAGES,
    POWER_UNITS = POWER_UNITS,
    CASTBAR_FIELDS = CASTBAR_FIELDS,
    LOAD_CONDITIONS = LOAD_CONDITIONS,
    STATUS_ANCHORS = STATUS_ANCHORS,
    DEFAULT_SYMBOLS = DEFAULT_SYMBOLS,
    STATUS_CONTROLS = STATUS_CONTROLS,
    TEXT_ANCHORS = TEXT_ANCHORS,
    HP_MODES = HP_MODES,
    POWER_MODES = POWER_MODES,
    BOSS_LAYOUT_OPTIONS = BOSS_LAYOUT_OPTIONS,
    SEPARATORS = SEPARATORS,
    PORTRAIT_RENDER = PORTRAIT_RENDER,
    PORTRAIT_SHAPES = PORTRAIT_SHAPES,
    PORTRAIT_BORDERS = PORTRAIT_BORDERS,
    UNIT_COPY_TARGETS = UNIT_COPY_TARGETS,
    UF_COPY_CATEGORIES = UF_COPY_CATEGORIES,
    GetConf = GetConf,
    GetGeneral = GetGeneral,
    DeepCopy = DeepCopy,
    DefaultCopyTarget = DefaultCopyTarget,
    UnitTopLabel = UnitTopLabel,
    -- The raw key of UnitTopLabel, for widgets that translate their own label.
    UnitTopLabelKey = function(unit) return UNIT_LABELS[unit] or tostring(unit or "") end,
    ControlMeta = UnitControlMeta,
    SettingMeta = UnitSettingMeta,
    -- Call sites keep Retail's disposition and reason arguments; nothing reads them.
    ReviewedMeta = UnitControlMeta,
    RegisterControl = RegisterUnitControl,
    NewCopyScopeDefaults = NewCopyScopeDefaults,
    ConfirmCopyToAll = ConfirmCopyToAll,
    SetBossPagePreviewActive = SetBossPagePreviewActive,
    SetArenaPagePreviewActive = SetArenaPagePreviewActive,
    StatusAllowed = StatusAllowed,
    FindStatusSpec = FindStatusSpec,
    SetControlEnabled = W.SetControlEnabled,
    SeedText = GetConf,
})
