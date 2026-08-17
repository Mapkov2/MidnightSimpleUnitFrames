local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer

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
local UNIT_PAGES = { uf_player = { unit = "player", title = "MSUF Player", label = NAV_SUBPAGE_LABELS.uf_player or "Player" }, uf_target = { unit = "target", title = "MSUF Target", label = NAV_SUBPAGE_LABELS.uf_target or "Target" }, uf_targettarget = { unit = "targettarget", title = "MSUF Target of Target", label = NAV_SUBPAGE_LABELS.uf_targettarget or "Target of Target" }, uf_focustarget = { unit = "focustarget", title = "MSUF Focus Target", label = NAV_SUBPAGE_LABELS.uf_focustarget or "Focus Target" }, uf_focus = { unit = "focus", title = "MSUF Focus", label = NAV_SUBPAGE_LABELS.uf_focus or "Focus" }, uf_pet = { unit = "pet", title = "MSUF Pet", label = NAV_SUBPAGE_LABELS.uf_pet or "Pet" }, uf_boss = { unit = "boss", title = "MSUF Boss Frames", label = NAV_SUBPAGE_LABELS.uf_boss or "Boss" } }
local POWER_UNITS = {}
local CanDetachUnitPowerBar = _G.MSUF_CanDetachUnitPowerBar
for _, page in pairs(UNIT_PAGES) do
    if type(CanDetachUnitPowerBar) ~= "function" or CanDetachUnitPowerBar(page.unit) then
        POWER_UNITS[page.unit] = true
    end
end
local CASTBAR_FIELDS = {
    -- Castbar settings live in general DB rather than each unit DB. Keep this map as the one
    -- place where unit pages translate a unit key into the correct castbar field names.
    player = {
        stylePrefix = "castbarPlayer", enable = "enablePlayerCastbar", backend = "castbarPlayerBackend",
        providerMemory = "castbarPlayerBackendBeforeHide", time = "showPlayerCastTime",
        icon = "castbarPlayerShowIcon", text = "castbarPlayerShowSpellName",
        timeFormat = "castbarPlayerTimeFormat", w = "castbarPlayerBarWidth", h = "castbarPlayerBarHeight",
        match = "castbarPlayerMatchWidth", detached = "castbarPlayerDetached",
        offsetX = "castbarPlayerOffsetX", offsetY = "castbarPlayerOffsetY",
    },
    target = {
        stylePrefix = "castbarTarget", enable = "enableTargetCastbar", backend = "castbarTargetBackend",
        providerMemory = "castbarTargetBackendBeforeHide", time = "showTargetCastTime",
        icon = "castbarTargetShowIcon", text = "castbarTargetShowSpellName",
        targetName = "castbarTargetShowTargetName", timeFormat = "castbarTargetTimeFormat",
        w = "castbarTargetBarWidth", h = "castbarTargetBarHeight", match = "castbarTargetMatchWidth",
        detached = "castbarTargetDetached", offsetX = "castbarTargetOffsetX", offsetY = "castbarTargetOffsetY",
    },
    focus = {
        stylePrefix = "castbarFocus", enable = "enableFocusCastbar", backend = "castbarFocusBackend",
        providerMemory = "castbarFocusBackendBeforeHide", time = "showFocusCastTime",
        icon = "castbarFocusShowIcon", text = "castbarFocusShowSpellName",
        targetName = "castbarFocusShowTargetName", timeFormat = "castbarFocusTimeFormat",
        w = "castbarFocusBarWidth", h = "castbarFocusBarHeight", match = "castbarFocusMatchWidth",
        detached = "castbarFocusDetached", offsetX = "castbarFocusOffsetX", offsetY = "castbarFocusOffsetY",
    },
    boss = {
        stylePrefix = "bossCast", enable = "enableBossCastbar", backend = "bossCastbarBackend",
        providerMemory = "bossCastbarBackendBeforeHide", time = "showBossCastTime",
        icon = "showBossCastIcon", text = "showBossCastName", targetName = "showBossCastTargetName",
        timeFormat = "bossCastTimeFormat", w = "bossCastbarWidth", h = "bossCastbarHeight",
        match = "bossCastbarMatchWidth", detached = "bossCastbarDetached",
        offsetX = "bossCastbarOffsetX", offsetY = "bossCastbarOffsetY",
    },
}
local CASTBAR_COPY_SUFFIXES = WL [[IconPosition IconSize IconZoom IconOffsetX IconOffsetY IconSpacing IconBorderThickness IconBorderStyle IconFrameLevelOffset SpellNamePosition SpellNameFontSize TextOffsetX TextOffsetY SpellNameMaxWidth SpellNameTruncate TimePosition TimeFontSize TimeOffsetX TimeOffsetY FrameLevelOffset SpellNameColorR SpellNameColorG SpellNameColorB TimeColorR TimeColorG TimeColorB]]
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
local function StatusIconPackValues()
    local fn = _G.MSUF_GetStatusIconPackValues
    if type(fn) == "function" then return fn(false) end
    return VTP "BLIZZARD=Blizzard (Default)|CLASSIC=Classic|MIDNIGHT=Midnight|UXPRO=UX Pro|GLOSSY_ORBS=Glossy Orbs|DARK_EMBOSS=Dark Emboss|GLASS_PANELS=Glass Panels|NEON_OUTLINE=Neon Outline|RING_SYMBOLS=Ring Symbols|DOTS=Dots|SHAPES=Shapes|DIAMONDS=Diamonds|SQUARES=Squares"
end
local function StatusControl(value, text, show, defaultShow, size, defaultSize, anchor, defaultAnchor, anchors, x, defaultX, y, defaultY, layer, defaultLayer, refresh, extra)
    local spec = {
        value = value, text = text, show = show, defaultShow = defaultShow,
        size = size, defaultSize = defaultSize, anchor = anchor, defaultAnchor = defaultAnchor, anchors = anchors,
        x = x, defaultX = defaultX, y = y, defaultY = defaultY, layer = layer, defaultLayer = defaultLayer,
        refresh = refresh,
    }
    if extra then for k, v in pairs(extra) do spec[k] = v end end
    return spec
end
local STATUS_CONTROLS = {
    StatusControl("leader", "Leader Icon", "showLeaderIcon", true, "leaderIconSize", 14, "leaderIconAnchor", "TOPLEFT", STATUS_CORNER_ANCHORS, "leaderIconOffsetX", 0, "leaderIconOffsetY", 3, "leaderIconLayer", 7, "MSUF_RefreshLeaderIconFrames", { allowed = function(unit) return unit == "player" or unit == "target" end, iconStyle = "leaderIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "leaderIconCustomIcon" }),
    StatusControl("assist", "Assist Icon", "showLeaderIcon", true, "leaderIconSize", 14, "leaderIconAnchor", "TOPLEFT", STATUS_CORNER_ANCHORS, "leaderIconOffsetX", 0, "leaderIconOffsetY", 3, "leaderIconLayer", 7, "MSUF_RefreshLeaderIconFrames", { allowed = function(unit) return unit == "player" or unit == "target" end, iconStyle = "assistIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "assistIconCustomIcon" }),
    StatusControl("raidmarker", "Raid Marker", "showRaidMarker", true, "raidMarkerSize", 18, "raidMarkerAnchor", "TOPLEFT", STATUS_CORNER_ANCHORS, "raidMarkerOffsetX", 16, "raidMarkerOffsetY", 3, "raidMarkerLayer", 7, "MSUF_RefreshRaidMarkerFrames", { iconStyle = "raidMarkerIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "raidMarkerCustomIcon" }),
    StatusControl("level", "Level Text", "showLevelIndicator", true, "levelIndicatorSize", 14, "levelIndicatorAnchor", "NAMERIGHT", STATUS_LEVEL_ANCHORS, "levelIndicatorOffsetX", 0, "levelIndicatorOffsetY", 0, "levelIndicatorLayer", 7, "MSUF_RefreshIdentityTextFrames", { textIndicator = true, colorPrefix = "levelIndicator" }),
    StatusControl("bossNumber", "Boss Number", "showBossNumberIndicator", false, "bossNumberIndicatorSize", 14, "bossNumberIndicatorAnchor", "TOPLEFT", STATUS_CORNER_ANCHORS, "bossNumberIndicatorOffsetX", 4, "bossNumberIndicatorOffsetY", -4, "bossNumberIndicatorLayer", 7, "MSUF_RefreshStatusIndicators", { allowed = function(unit) return unit == "boss" end, textIndicator = true, colorPrefix = "bossNumberIndicator" }),
    StatusControl("raceText", "Race Text", "showRaceIndicator", false, "raceIndicatorSize", 14, "raceIndicatorAnchor", "NAMERIGHT", STATUS_LEVEL_ANCHORS, "raceIndicatorOffsetX", 0, "raceIndicatorOffsetY", 0, "raceIndicatorLayer", 7, "MSUF_RefreshIdentityTextFrames", { textIndicator = true, colorPrefix = "raceIndicator" }),
    StatusControl("classText", "Class Text", "showClassTextIndicator", false, "classTextIndicatorSize", 14, "classTextIndicatorAnchor", "NAMERIGHT", STATUS_LEVEL_ANCHORS, "classTextIndicatorOffsetX", 0, "classTextIndicatorOffsetY", 0, "classTextIndicatorLayer", 7, "MSUF_RefreshIdentityTextFrames", { textIndicator = true, colorPrefix = "classTextIndicator" }),
    StatusControl("raidgroupname", "Raid Group", "showRaidGroupInName", false, "nameFontSize", 14, "raidGroupNameAnchor", "NAMERIGHT", RAID_GROUP_NAME_ANCHORS, "raidGroupNameOffsetX", 3, "raidGroupNameOffsetY", 0, "raidGroupNameLayer", 5, "MSUF_RefreshRaidGroupNameFrames", { allowed = function(unit) return unit == "player" or unit == "target" or unit == "targettarget" or unit == "focustarget" or unit == "focus" end, inlineName = true, legacyLayer = "nameTextLayer", colorPrefix = "raidGroupName", copyProps = "show anchor x y layer", copyExtra = WL("raidGroupNameStyle") }),
    StatusControl("eliteicon", "Elite / Rare", "showEliteIcon", true, "eliteIconSize", 20, "eliteIconAnchor", "TOPRIGHT", STATUS_CORNER_ANCHORS, "eliteIconOffsetX", 2, "eliteIconOffsetY", 2, "eliteIconLayer", 7, "MSUF_RefreshEliteIconFrames", { allowed = function(unit) return unit == "target" or unit == "focus" or unit == "targettarget" or unit == "focustarget" or unit == "boss" end, iconStyle = "eliteIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "eliteIconCustomIcon" }),
    StatusControl("statusText", "Dead / Offline Text", "statusDeadTextEnabled", true, "statusTextSize", 16, "statusTextAnchor", "CENTER", STATUS_CORNER_ANCHORS, "statusTextOffsetX", 0, "statusTextOffsetY", 0, "statusTextLayer", 7, "MSUF_RequestStatusTextRefresh", { statusRuntime = true, statusTextState = "DEAD", colorPrefix = "statusText", legacyShow = "statusTextEnabled", legacyState = "showDead" }),
    StatusControl("statusGhostText", "Ghost Text", "statusGhostTextEnabled", true, "statusGhostTextSize", 16, "statusGhostTextAnchor", "CENTER", STATUS_CORNER_ANCHORS, "statusGhostTextOffsetX", 0, "statusGhostTextOffsetY", 0, "statusGhostTextLayer", 7, "MSUF_RequestStatusTextRefresh", { statusRuntime = true, statusTextState = "GHOST", colorPrefix = "statusGhostText", legacyShow = "statusTextEnabled", legacyState = "showGhost", legacySize = "statusTextSize", legacyAnchor = "statusTextAnchor", legacyX = "statusTextOffsetX", legacyY = "statusTextOffsetY", legacyLayer = "statusTextLayer" }),
    StatusControl("statusAFKText", "AFK Text", "statusAFKTextEnabled", false, "statusAFKTextSize", 16, "statusAFKTextAnchor", "CENTER", STATUS_CORNER_ANCHORS, "statusAFKTextOffsetX", 0, "statusAFKTextOffsetY", 0, "statusAFKTextLayer", 7, "MSUF_RequestStatusTextRefresh", { statusRuntime = true, statusTextState = "AFK", colorPrefix = "statusAFKText", legacyShow = "statusTextEnabled", legacyState = "showAFK", legacySize = "statusTextSize", legacyAnchor = "statusTextAnchor", legacyX = "statusTextOffsetX", legacyY = "statusTextOffsetY", legacyLayer = "statusTextLayer" }),
    StatusControl("statusAFKTimer", "AFK Timer", "statusAFKTimerEnabled", false, "statusAFKTimerSize", 12, "statusAFKTimerAnchor", "CENTER", STATUS_CORNER_ANCHORS, "statusAFKTimerOffsetX", 0, "statusAFKTimerOffsetY", -14, "statusAFKTimerLayer", 7, "MSUF_RequestStatusTextRefresh", { statusRuntime = true, statusTextState = "AFKTIMER", colorPrefix = "statusAFKTimer" }),
    StatusControl("statusDNDText", "DND Text", "statusDNDTextEnabled", false, "statusDNDTextSize", 16, "statusDNDTextAnchor", "CENTER", STATUS_CORNER_ANCHORS, "statusDNDTextOffsetX", 0, "statusDNDTextOffsetY", 0, "statusDNDTextLayer", 7, "MSUF_RequestStatusTextRefresh", { statusRuntime = true, statusTextState = "DND", colorPrefix = "statusDNDText", legacyShow = "statusTextEnabled", legacyState = "showDND", legacySize = "statusTextSize", legacyAnchor = "statusTextAnchor", legacyX = "statusTextOffsetX", legacyY = "statusTextOffsetY", legacyLayer = "statusTextLayer" }),
    StatusControl("statusCombat", "Combat", "showCombatStateIndicator", true, "combatStateIndicatorSize", 18, "combatStateIndicatorAnchor", "TOPLEFT", STATUS_CORNER_ANCHORS, "combatStateIndicatorOffsetX", 0, "combatStateIndicatorOffsetY", 0, "combatStateIndicatorLayer", 7, "MSUF_RequestStatusCombatIndicatorRefresh", { allowed = function(unit) return unit == "player" or unit == "target" end, symbol = "combatStateIndicatorSymbol", symbols = COMBAT_SYMBOLS, statusRuntime = true, iconStyle = "combatStateIndicatorIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "combatStateIndicatorCustomIcon" }),
    StatusControl("statusResting", "Rested (player only)", "showRestingIndicator", true, "restedStateIndicatorSize", 39, "restedStateIndicatorAnchor", "TOPLEFT", STATUS_CORNER_ANCHORS, "restedStateIndicatorOffsetX", -40, "restedStateIndicatorOffsetY", 50, "restedStateIndicatorLayer", 25, "MSUF_RequestStatusRestingIndicatorRefresh", { allowed = function(unit) return unit == "player" end, symbol = "restedStateIndicatorSymbol", symbols = RESTED_SYMBOLS, statusRuntime = true, iconStyle = "restedStateIndicatorIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "restedStateIndicatorCustomIcon" }),
    StatusControl("statusIncomingRes", "Incoming Rez", "showIncomingResIndicator", true, "incomingResIndicatorSize", 18, "incomingResIndicatorAnchor", "TOPRIGHT", STATUS_CORNER_ANCHORS, "incomingResIndicatorOffsetX", 0, "incomingResIndicatorOffsetY", 0, "incomingResIndicatorLayer", 7, "MSUF_RequestStatusIncomingResIndicatorRefresh", { allowed = function(unit) return unit == "player" or unit == "target" end, symbol = "incomingResIndicatorSymbol", symbols = RESS_SYMBOLS, statusRuntime = true, iconStyle = "incomingResIndicatorIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "incomingResIndicatorCustomIcon" }),
    StatusControl("stance", "Stance", "showStanceIndicator", false, "stanceIndicatorSize", 12, "stanceIndicatorAnchor", "TOP", STATUS_LEVEL_ANCHORS, "stanceIndicatorOffsetX", 0, "stanceIndicatorOffsetY", -2, "stanceIndicatorLayer", 7, "MSUF_RequestStatusIconsRefreshForCurrent", { allowed = function(unit) return unit == "player" end, statusRuntime = true, textIndicator = true, colorPrefix = "stanceIndicator" }),
    StatusControl("statusPvp", "PvP Flag (War Mode/PvP)", "showPvpIndicator", true, "pvpIndicatorSize", 18, "pvpIndicatorAnchor", "TOPRIGHT", STATUS_CORNER_ANCHORS, "pvpIndicatorOffsetX", 0, "pvpIndicatorOffsetY", 0, "pvpIndicatorLayer", 7, "MSUF_RequestStatusPvpIndicatorRefresh", { allowed = function(unit) return unit == "player" or unit == "target" or unit == "focus" or unit == "targettarget" or unit == "focustarget" end, statusRuntime = true, iconStyle = "pvpIndicatorIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "pvpIndicatorCustomIcon" }),
}
-- LEFT/CENTER/RIGHT were legacy 5.77 tokens for the top row. Profiles migrate
-- those values to TOPLEFT/TOP/TOPRIGHT; FRAME* keeps the new middle row
-- unambiguous even when an old profile is imported later.
local TEXT_ANCHORS = VTP "TOPLEFT=Top Left|TOP=Top Center|TOPRIGHT=Top Right|FRAMELEFT=Left|FRAMECENTER=Center|FRAMERIGHT=Right"
local HP_MODES = VTP "ABSORB=Absorb|CURRENTABSORB=Current + Absorb|FULLVALUEABSORB=Full Value + Absorb|MAXABSORB=Max + Absorb|DEFICITABSORB=Deficit + Absorb|CURMAXABSORB=Current / Max + Absorb|PERCENTABSORB=Percent + Absorb|CURPERCENTABSORB=Current / Percent + Absorb|CURMAXPERCENTABSORB=Current / Max / Percent + Absorb|MAXPERCENTABSORB=Max / Percent + Absorb|PERCENTCURABSORB=Percent / Current + Absorb|PERCENTMAXABSORB=Percent / Max + Absorb|PERCENTCURMAXABSORB=Percent / Current / Max + Absorb|PERCENT=Percent|CURRENT=Current|FULLVALUE=Full Value|MAX=Max|DEFICIT=Deficit|CURMAX=Current / Max|CURPERCENT=Current / Percent|CURMAXPERCENT=Current / Max / Percent|MAXPERCENT=Max / Percent|PERCENTCUR=Percent / Current|PERCENTMAX=Percent / Max|PERCENTCURMAX=Percent / Current / Max|NONE=None"
local POWER_MODES = VTP "CURRENT=Current|MAX=Max|CURMAX=Current / Max|PERCENT=Percent|CURPERCENT=Current / Percent|CURMAXPERCENT=Current / Max / Percent|NONE=None"
local BOSS_LAYOUT_OPTIONS = VTP "VERTICAL_DOWN=Vertical (top -> bottom)|VERTICAL_UP=Vertical (bottom -> top)|HORIZONTAL_RIGHT=Horizontal (left -> right)|HORIZONTAL_LEFT=Horizontal (right -> left)"
local BOSS_LAYOUT_VALID = KSW("VERTICAL_DOWN VERTICAL_UP HORIZONTAL_RIGHT HORIZONTAL_LEFT")
local function PortableControlToken(value, fallback)
    local token = tostring(value or ""):lower():gsub("[^%w_]+", "."):gsub("^%.*", ""):gsub("%.*$", ""):gsub("%.+", ".")
    return token ~= "" and token or (fallback or "control")
end
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
    -- is a stable control identity, not a globally resolvable Assistant action.
    return meta
end
local function UnitSettingMeta(ctx, semanticPath, unit, key)
    local meta = UnitControlMeta(ctx, semanticPath, "setting")
    unit, key = tostring(unit or ""), tostring(key or "")
    if unit ~= "" and key ~= "" then meta.settingKey = unit .. "." .. key end
    return meta
end
local function UnitReviewedMeta(ctx, semanticPath, classification, disposition, reason)
    local meta = UnitControlMeta(ctx, semanticPath, classification)
    meta.assistantDisposition = disposition
    meta.assistantDispositionReason = reason
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
local function GetBars()
    local db = M.EnsureDB()
    db.bars = db.bars or {}
    return db.bars
end
local function Call(name, ...)
    local apply = M.ApplyService
    if apply and type(apply.CallGlobal) == "function" then return apply.CallGlobal(name, ...) end
    local fn = _G[name]
    if type(fn) == "function" then fn(...); return true end
    return false
end
local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    if type(CopyTable) == "function" then return CopyTable(src) end
    return M.DeepCopy(src)
end
local COPY_POWER_BAR_FIELDS = WL [[showPowerBar powerBarHeight embedPowerBarIntoHealth powerBarBorderEnabled powerBarBorderThickness powerSmoothFill powerChunkedFill powerBarDetached detachedPowerBarShape detachedPowerOrbSize detachedPowerBarWidth detachedPowerBarHeight detachedPowerBarOffsetX detachedPowerBarOffsetY detachedPowerBarAnchorMode detachedPowerBarFrameLevelOffset detachedPowerBarTextOnBar detachedPowerBarSyncClassPower detachedPowerBarAnchorToClassPower powerBarTexture powerBarBgTexture]]
--- Must cover every per-unit portrait key the engine reads (CompileUnitPortrait in
--- MSUF_UF_Config.lua) and the Visuals page binds. Border/background COLORS are
--- intentionally absent: those live in MSUF_DB.general and are shared by all units.
--- unit_copy_semantics_smoke extracts the bound keys from the Visuals page source and
--- fails when a new portrait control is missing here.
local COPY_PORTRAIT_FIELDS = WL [[portraitMode portraitRender portraitClassStyle portraitCastSpellIcon portraitShape portraitSizeMode portraitSizeOverride portraitWidth portraitHeight portraitOffsetX portraitOffsetY portraitZoom portraitPanX portraitPanY portraitPlacement portraitDetachedPoint portraitDetachedTo portraitOverlayAlign portraitLevelOffset portraitAlpha portraitBorderStyle portraitEdgeSoftness portraitBorderArt portraitBorderDirection portraitBorderThickness portraitBgEnabled portraitFillBorder portraitDecoOverride]]
local COPY_TEXT_FIELDS = WL [[
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
for _, slot in ipairs(WL [[Name HealthLeft HealthCenter HealthRight PowerLeft PowerCenter PowerRight]]) do
    for _, suffix in ipairs(WL [[Point RelativePoint OffsetX OffsetY Color]]) do
        COPY_TEXT_FIELDS[#COPY_TEXT_FIELDS + 1] = "direct" .. slot .. suffix
    end
end
local COPY_INDICATOR_FIELDS = M.CopyFieldsFromSpecs(STATUS_CONTROLS, "leader assist raidmarker raidgroupname eliteicon", nil, "show iconStyle customIcon x y anchor size layer symbol")
local COPY_STATUSICON_FIELDS = M.CopyFieldsFromSpecs(STATUS_CONTROLS, "level raceText classText statusText statusGhostText statusAFKText statusAFKTimer statusDNDText statusCombat statusResting statusIncomingRes statusPvp stance", "statusIconsTestMode statusIconsMidnightStyle statusIconsAlpha statusTextEnabled", "show iconStyle customIcon x y anchor size layer symbol")
--- Most fields below "healthColorMode" are the per-unit Bars override scope (gated by
--- hlOverride, see MSUF_Menu2_Bindings BARS_SCOPE_KEYS). UnitFrame Dispel Overlay/Symbol
--- are the deliberate exception: they are copied with Frame settings but stay owned by
--- the source/destination units regardless of the Bars override. powerSmoothFill is
--- owned by the Power Bar category, hpPowerTextOverride by Text.
local COPY_FRAME_BASIC_FIELDS = WL [[
    enabled showName showHP showPower reverseFillBars verticalFillBars smoothFill chunkedFill healthColorMode
    hlOverride barTexture barBackgroundTexture barBgTexture
    barOutlineThickness barOutlineLayer barOutlineStrata barOutlineTexture barOutlineColorR barOutlineColorG barOutlineColorB barOutlineColorA
    highlightBorderThickness hlAggroSize aggroOutlineMode dispelOutlineMode purgeOutlineMode dispelBorderTrigger
    unitDispelOverlayEnabled unitDispelOverlayStyle unitDispelOverlayOnHealth unitDispelOverlayAlpha unitDispelOverlayTrigger
    unitDispelSymbolEnabled unitDispelSymbolStyle unitDispelSymbolMode unitDispelSymbolTrigger
    unitDispelSymbolSize unitDispelSymbolSpacing unitDispelSymbolGrowth unitDispelSymbolAnchor
    unitDispelSymbolX unitDispelSymbolY unitDispelSymbolAlpha unitDispelSymbolLayer unitDispelSymbolStrata
    hlPrioEnabled hlPrioOrder
    enableAbsorbBar absorbTextMode absorbAnchorMode absorbBarHeight absorbBarOffsetY absorbBarOpacity
    healAbsorbEnabled healAbsorbAnchorMode healAbsorbBarHeight healAbsorbBarOffsetY healAbsorbBarOpacity
    healPredEnabled healPredAnchorMode healPredictionBarHeight healPredictionBarOffsetY healPredictionBarOpacity healPredictionBarTexture
    overAbsorbOverlay fullHealthAbsorbStripe
    enableGradient enablePowerGradient gradientStrength gradientDirection
    gradientDirRight gradientDirLeft gradientDirUp gradientDirDown
    gradientOverride gradientOverrideVersion gradientOverrideKeys
    healthBarGradientColorR healthBarGradientColorG healthBarGradientColorB
    powerBarGradientColorR powerBarGradientColorG powerBarGradientColorB
]]
local COPY_TRANSPARENCY_FIELDS = WL [[hpBarAlpha powerBarAlpha hpBgAlpha powerBarBgAlpha alphaExcludeTextPortrait oocFadeEnabled oocFadeAlpha rangeFadeEnabled rangeFadeAlpha rangeFadeLayerMode]]
-- Keep this as a WL literal (even though the shared prefix list is empty) so
-- unit_copy_coverage_smoke.lua can audit the dynamically-prefixed suffix set.
local COPY_TEXLAYER_FIELDS = WL [[]]
for _, texP in ipairs({ "texLayer", "texLayer2", "texLayer3" }) do
    for _, texBase in ipairs(WL [[Enabled Texture CustomTexturePath Alpha FollowFrameAlpha Strata Level AnchorTarget Anchor OffsetX OffsetY Width Height ColorMode ColorTreatment ColorR ColorG ColorB GradientEnabled Gradient2R Gradient2G Gradient2B GradientDirRight GradientDirLeft GradientDirUp GradientDirDown BlendMode MirrorH MirrorV CropMode EdgeSoftness Visibility RoundedClip]]) do
        COPY_TEXLAYER_FIELDS[#COPY_TEXLAYER_FIELDS + 1] = texP .. texBase
    end
end
local COPY_LOAD_CONDITION_FIELDS = WL [[loadCondHideInHousing loadCondHideInCombat loadCondHideInGroup loadCondHideInInstance loadCondHideInVehicle loadCondHideMounted loadCondHideNoTarget loadCondHideOutOfCombat loadCondHideOutOfCombatNoTarget loadCondHideResting loadCondHideSolo loadCondHideStealthed loadCondActive]]
--- Size only. Placement (offsetX/offsetY, point/relativePoint, anchorFrameName and
--- anchorToUnitframe) must never travel through Copy To: two unit frames sharing a
--- placement land exactly on top of each other, and the covered one is then
--- unreachable for dragging. Frames are positioned in MSUF Edit Mode, not by copying.
--- Boss layout also describes the boss1-boss5 container rather than one unit frame,
--- so it has no semantic equivalent on Player/Target/Focus and must never be cleared
--- when a normal unit's frame size is copied to Boss.
local COPY_LAYOUT_FIELDS = WL [[width height]]
local AURA_COPY_UNITS = KSW("player target focus boss")
local AURA_COPY_FLAGS = { player = "showPlayer", target = "showTarget", focus = "showFocus", boss = "showBoss" }
local AURA_BOSS_RUNTIME_UNITS = WL("boss1 boss2 boss3 boss4 boss5")
local UF_COPY_CATEGORIES = {
    { key = "basics",       label = "Frame Basics",     default = true, description = "Copies the frame toggle, fill direction and health coloring, plus this unit's Bars overrides: bar textures, outline, highlight priority, gradient, absorb and heal prediction." },
    { key = "text",         label = "Text",             default = true, description = "Copies every text slot with its content, size and position, plus this unit's font overrides: font, outline, shadow, text color and name shortening." },
    { key = "portrait",     label = "Portrait",         default = true },
    { key = "power",        label = "Power Bar",        default = true },
    { key = "auras",        label = "Aura Options",     default = true, description = "Copies this UnitFrame's Aura visibility, layout, filters, blacklists, Custom Aura setup and tracked spells. Aura Style and the global Appearance theme remain unchanged." },
    { key = "aurastyle",    label = "Aura Style",       default = true, description = "Copies this UnitFrame's Buff, Debuff, Custom Aura, Player Defensive and Dots on Target presentation, including text, swipe, icon zoom, duration bars, Pandemic and Full-Frame effects. Aura Options and the global Appearance theme remain unchanged." },
    { key = "castbar",      label = "Castbar",          default = true },
    { key = "status",       label = "Status Icons",     default = true },
    { key = "load",         label = "Load Conditions",  default = true },
    { key = "transparency", label = "Transparency",     default = true },
    { key = "texlayer",     label = "Texture Layer",    default = true },
    { key = "layout",       label = "Frame Size",       default = false, description = "Copies the frame width and height only. Position and anchoring never travel with a copy; place frames in MSUF Edit Mode." },
}
local function NewCopyScopeDefaults()
    local t = {}
    for i = 1, #UF_COPY_CATEGORIES do
        local cat = UF_COPY_CATEGORIES[i]
        t[cat.key] = cat.default ~= false
    end
    return t
end
local UNIT_COPY_TARGETS = VTP "player=Player|target=Target|targettarget=Target of Target|focustarget=Focus Target|focus=Focus|pet=Pet|boss=Boss Frames"
local UNIT_LABELS = { player = "Player", target = "Target", targettarget = "Target of Target", focustarget = "Focus Target", focus = "Focus", pet = "Pet", boss = "Boss Frames" }
local UNIT_PILL_WIDTHS = { targettarget = 116, focustarget = 104, boss = 92, target = 62, focus = 58, pet = 46 }
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
local function UnitTopPillWidth(unit)
    return UNIT_PILL_WIDTHS[unit] or 56
end
local UNIT_KEY_SET = KSW("player target targettarget focustarget focus pet boss")
local function CanonUnitKey(key)
    if type(key) ~= "string" then return key end
    key = key:lower()
    if key == "tot" or key == "targetoftarget" or key == "target_of_target" then return "targettarget" end
    if key == "focus_target" or key == "focustargettarget" then return "focustarget" end
    if key:match("^boss") then return "boss" end
    return key
end
local function EnsureUnitDB(key)
    local db = M.EnsureDB()
    key = CanonUnitKey(key)
    if not UNIT_KEY_SET[key] then return nil, nil end
    if key == "targettarget" then
        if type(db.targettarget) ~= "table" then
            db.targettarget = type(db.tot) == "table" and db.tot
                or type(db.targetoftarget) == "table" and db.targetoftarget
                or type(db.target_of_target) == "table" and db.target_of_target
                or {}
        end
        db.tot = nil
        db.targetoftarget = nil
        db.target_of_target = nil
        return db.targettarget, key
    end
    if key == "focustarget" then
        if type(db.focustarget) ~= "table" then
            db.focustarget = type(db.focus_target) == "table" and db.focus_target
                or type(db.focustargettarget) == "table" and db.focustargettarget
                or {}
        end
        db.focus_target = nil
        db.focustargettarget = nil
        return db.focustarget, key
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
}
local PB_SHOW_DEFAULTS = {
    player = true,
    target = true,
    focus = true,
    targettarget = false,
    focustarget = false,
    pet = true,
    boss = true,
}
local function ConfBool(value) if value ~= nil then return true, value ~= false end end
local function ConfTrue(value) if value ~= nil then return true, value == true end end
local function ConfNumber(value) if type(value) == "number" then return true, value end end
local function BarsDB()
    return _G.MSUF_DB and _G.MSUF_DB.bars
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
    local fn = spec.fn and _G[spec.fn]
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
    local normalize = _G.MSUF_NormalizeCastbarBackendForUnit
    local backend = (type(normalize) == "function") and normalize(dst, g[s.backend]) or g[s.backend]
    if backend == nil then backend = (g[s.enable] == false) and ((dst == "player") and "BLIZZARD" or "HIDE") or "MSUF" end
    if backend == "BLIZZARD" and dst ~= "player" then backend = "HIDE" end
    local remembered = g[s.providerMemory]
    if remembered == "BLIZZARD" and dst ~= "player" then remembered = "MSUF" end
    g[d.enable] = (backend == "MSUF")
    g[d.backend] = backend
    if remembered ~= nil then g[d.providerMemory] = remembered end
    CopyCastbarValue(g, s.time, d.time)
    CopyCastbarValue(g, s.icon, d.icon)
    CopyCastbarValue(g, s.text, d.text)
    if s.targetName and d.targetName then CopyCastbarValue(g, s.targetName, d.targetName) end
    CopyCastbarValue(g, s.timeFormat, d.timeFormat)
    CopyCastbarValue(g, s.w, d.w)
    CopyCastbarValue(g, s.h, d.h)
    CopyCastbarValue(g, s.match, d.match)
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
    return unit == "boss" and "boss1" or unit
end
local function ForEachAuraRuntimeTarget(unit, callback)
    unit = CanonUnitKey(unit)
    if unit == "boss" then
        for i = 1, #AURA_BOSS_RUNTIME_UNITS do callback(AURA_BOSS_RUNTIME_UNITS[i]) end
        return
    end
    callback(unit)
end
local function ApplyAuras3Unit(unit)
    local apply = M.ApplyService or _G.MSUF_Menu2_ApplyService
    if apply and type(apply.RequestAuras) == "function" then
        return apply.RequestAuras(unit, "MSUF2_COPY_UNIT_AURAS")
    end
    local a3 = MSUF and MSUF.MSUF_Auras3
    local model = a3 and a3.MenuModel
    if model and type(model.Apply) == "function" then
        model.Apply(unit, "MSUF2_COPY_UNIT_AURAS")
        return true
    end
    if a3 and type(a3.RequestScope) == "function" then
        a3.RequestScope(unit, "MSUF2_COPY_UNIT_AURAS")
        return true
    end
    if a3 and type(a3.RefreshUnit) == "function" then
        a3.RefreshUnit(unit)
        return true
    end
    if a3 and type(a3.RequestUnit) == "function" then
        a3.RequestUnit(unit)
        return true
    end
    if a3 and type(a3.RequestApply) == "function" then
        a3.RequestApply(unit, "MSUF2_COPY_UNIT_AURAS")
        return true
    end
    return false
end
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
    if auras.enabled == nil then auras.enabled = true end
    if auras.showPlayer == nil then auras.showPlayer = false end
    if auras.showTarget == nil then auras.showTarget = true end
    if auras.showFocus == nil then auras.showFocus = true end
    if auras.showBoss == nil then auras.showBoss = true end
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
        if type(sourceConfig) == "table" then
            auras.perUnit[runtimeUnit] = DeepCopy(sourceConfig)
        else
            auras.perUnit[runtimeUnit] = nil
        end
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
local function EnsureCopyDialog()
    M.InstallStaticPopup("MSUF2_COPY_TO_ALL_CONFIRM", {
        text = M.Tr("Copy these settings to ALL unitframes?\n\nThis will overwrite existing settings on Player/Target/Focus/Boss/Pet/Target of Target/Focus Target."),
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function(_, data)
            if type(data) == "function" then data() end
        end,
    })
end
local function ConfirmCopyToAll(callback)
    if type(callback) ~= "function" then return end
    local legacy = _G.MSUF_ConfirmCopyToAll
    if type(legacy) == "function" then
        legacy(callback)
        return
    end
    EnsureCopyDialog()
    if StaticPopup_Show then
        StaticPopup_Show("MSUF2_COPY_TO_ALL_CONFIRM", nil, nil, callback)
    else
        callback()
    end
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
local function CopyUnitSettings(unit, target, scopes, onComplete, allConfirmed)
    M.EnsureDB()
    ExportPublic("MSUF_DB", _G.MSUF_DB or {})
    _G.MSUF_DB.general = _G.MSUF_DB.general or {}
    local g = _G.MSUF_DB.general
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
        if not dst or not dstKey then result.reason = "invalid_destination"; return false, result end
        if dstKey == srcKey then result.reason = "same_destination"; return false, result end
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
            if CopyCastbar(g, srcKey, dstKey) then
                result.castbarApplied = true
                Call("MSUF_UpdateCastbarWidthSourceSync", g, dstKey)
            end
        end
        if scopes.load then CopyFields(dst, src, COPY_LOAD_CONDITION_FIELDS) end
        if scopes.transparency then CopyFields(dst, src, COPY_TRANSPARENCY_FIELDS) end
        if scopes.texlayer then CopyFields(dst, src, COPY_TEXLAYER_FIELDS) end
        if scopes.layout then CopyFields(dst, src, COPY_LAYOUT_FIELDS) end
        M.RequestUnitApply(dstKey, "MSUF2_COPY_UNIT", {
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
            Call("MSUF_RefreshAllIndicators", statusUnit, "MSUF2_COPY_UNIT_STATUS")
            Call("MSUF_RefreshStatusIndicators", statusUnit, "MSUF2_COPY_UNIT_STATUS")
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
local function ToggleEditMode(unit)
    if type(_G.MSUF_BlockConfigCombatLocked) == "function" and _G.MSUF_BlockConfigCombatLocked() then return end
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
        return
    end
    local active = (_G.MSUF_IsMSUFEditModeActive and _G.MSUF_IsMSUFEditModeActive()) or _G.MSUF_UnitEditModeActive
    if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then _G.MSUF_SetMSUFEditModeDirect(not active, CanonUnitKey(unit)) end
end
local function IsEditModeActive()
    return ((_G.MSUF_IsMSUFEditModeActive and _G.MSUF_IsMSUFEditModeActive()) or _G.MSUF_UnitEditModeActive) and true or false
end
local bossPagePreviewEvents
local bossPagePreviewPendingCleanup
local function BossPagePreviewInCombat()
    return (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
end
local function ClearBossPagePreviewForCombat()
    local clear = _G.MSUF_ClearBossUnitframePreviewForCombat
    return type(clear) == "function" and clear() == true
end
local function CoreFrame(unit)
    local uf = MSUF and MSUF.UF
    if uf and type(uf.GetFrame) == "function" then
        local frame = uf.GetFrame(unit)
        if frame then return frame end
    end
    local frames = uf and uf.frames
    return unit and frames and frames[unit] or nil
end
local function BossPreviewFramesVisible()
    local sawFrame = false
    for i = 1, 5 do
        local unit = "boss" .. i
        local frame = CoreFrame(unit) or _G["MSUF_" .. unit]
        if frame then
            sawFrame = true
            if frame.IsShown and not frame:IsShown() then return false end
        end
    end
    return sawFrame
end
local function SyncBossPagePreview()
    local active = (_G.MSUF2_BossUnitframePreviewActive == true)
    if BossPagePreviewInCombat() then
        local cleared = ClearBossPagePreviewForCombat()
        _G.MSUF2_BossUnitframePreviewActive = nil
        if active or cleared then bossPagePreviewPendingCleanup = true end
        return
    end
    if not BossPagePreviewInCombat() and type(_G.MSUF_ApplyBossUnitframePreviewState) == "function" then
        _G.MSUF_ApplyBossUnitframePreviewState(active, active and "MSUF2_BOSS_PAGE" or "MSUF2_BOSS_PAGE_OFF")
        return
    end
    if type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then _G.MSUF_SyncBossUnitframePreviewWithUnitEdit() end
end
local function EnsureBossPagePreviewEvents()
    if bossPagePreviewEvents then return bossPagePreviewEvents end
    bossPagePreviewEvents = CreateFrame("Frame")
    bossPagePreviewEvents:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            -- Another Menu2 coordinator may already have cleared the global
            -- flag. Always run the frame handoff and remember the OOC rebuild.
            ClearBossPagePreviewForCombat()
            _G.MSUF2_BossUnitframePreviewActive = nil
            bossPagePreviewPendingCleanup = true
            return
        end
        if event == "PLAYER_REGEN_ENABLED" and bossPagePreviewPendingCleanup then
            bossPagePreviewPendingCleanup = nil
            SyncBossPagePreview()
            if _G.MSUF2_BossUnitframePreviewActive ~= true then self:UnregisterAllEvents() end
            return
        end
        if _G.MSUF2_BossUnitframePreviewActive == true then SyncBossPagePreview() end
    end)
    return bossPagePreviewEvents
end
local function SetBossPagePreviewActive(active)
    active = active and true or false
    if active and BossPagePreviewInCombat() then
        ClearBossPagePreviewForCombat()
        _G.MSUF2_BossUnitframePreviewActive = nil
        bossPagePreviewPendingCleanup = nil
        if bossPagePreviewEvents then bossPagePreviewEvents:UnregisterAllEvents() end
        return
    end
    local current = _G.MSUF2_BossUnitframePreviewActive == true
    if current == active then
        if active and not BossPagePreviewInCombat() and not BossPreviewFramesVisible() then SyncBossPagePreview() end
        if not active and _G.MSUF_BossTestMode == true and not BossPagePreviewInCombat() then SyncBossPagePreview() end
        return
    end
    _G.MSUF2_BossUnitframePreviewActive = active or nil
    local events = EnsureBossPagePreviewEvents()
    if active then
        bossPagePreviewPendingCleanup = nil
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    elseif BossPagePreviewInCombat() then
        bossPagePreviewPendingCleanup = true
        events:UnregisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    else
        bossPagePreviewPendingCleanup = nil
        events:UnregisterAllEvents()
    end
    SyncBossPagePreview()
    if active then
        C_Timer.After(0, SyncBossPagePreview)
        C_Timer.After(0.12, SyncBossPagePreview)
    end
end
local function ReadBool(unit, key, default)
    local conf = GetConf(unit)
    local value = conf[key]
    if value == nil then return default and true or false end
    return value and true or false
end
local function SetBool(unit, key, value, reason, opts)
    M.SetUnitValue(unit, key, value and true or false, reason, opts)
end
local function ReadNumber(unit, key, default)
    local conf = GetConf(unit)
    local value = tonumber(conf[key])
    if value == nil then value = default or 0 end
    return value
end
local function SetNumber(unit, key, value, reason, opts)
    value = tonumber(value)
    if value == nil then return end
    if math.abs(value - floor(value + 0.5)) < 0.001 then value = floor(value + 0.5) end
    M.SetUnitValue(unit, key, value, reason, opts)
end
local function IsPlayerPowerManagedByClassResources(unit)
    if unit ~= "player" then return false end
    local conf = GetConf("player")
    if not (conf and conf.powerBarDetached == true) then return false end
    return conf.detachedPowerBarAnchorToClassPower == true
end
local function SetString(unit, key, value, reason, opts)
    M.SetUnitValue(unit, key, tostring(value or ""), reason, opts)
end
local function ReadGeneralBool(key, default)
    local g = GetGeneral()
    local value = g[key]
    if value == nil then return default and true or false end
    return value and true or false
end
local function SetGeneralBool(key, value, reason, opts)
    M.SetGeneralValue(key, value and true or false, reason, opts)
end
local function ClampStatusLayer(value, default)
    value = tonumber(value) or default or 7
    value = floor(value + 0.5)
    if value < 0 then return 0 end
    if value > 30 then return 30 end
    return value
end
local function StatusAllowed(unit, spec)
    return spec and (not spec.allowed or spec.allowed(unit))
end
local function StatusValues(unit)
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
local function CurrentStatusSpec(unit)
    M.unitStatusSelection = M.unitStatusSelection or {}
    local spec = FindStatusSpec(unit, M.unitStatusSelection[unit])
    if spec then M.unitStatusSelection[unit] = spec.value end
    return spec
end
local function ReadStatusBool(unit, key, default)
    local conf = GetConf(unit)
    local g = GetGeneral()
    local value = conf[key]
    if value == nil then value = g[key] end
    if value == nil then return default and true or false end
    return value and true or false
end
local function ReadStatusNumber(unit, key, default, legacyKey)
    local conf = GetConf(unit)
    local g = GetGeneral()
    local value = tonumber(conf[key])
    if value == nil and legacyKey then value = tonumber(conf[legacyKey]) end
    if value == nil then value = tonumber(g[key]) end
    if value == nil and legacyKey then value = tonumber(g[legacyKey]) end
    if value == nil then value = default or 0 end
    return value
end
local function ReadStatusString(unit, key, default, legacyKey)
    local conf = GetConf(unit)
    local g = GetGeneral()
    local value = conf[key]
    if (type(value) ~= "string" or value == "") and legacyKey then value = conf[legacyKey] end
    if type(value) ~= "string" or value == "" then value = g[key] end
    if (type(value) ~= "string" or value == "") and legacyKey then value = g[legacyKey] end
    if type(value) ~= "string" or value == "" then value = default end
    return value or ""
end
local function RefreshStatusRuntime(unit, spec)
    local runtimeRefreshed = false
    if spec and spec.refresh then
        runtimeRefreshed = Call(spec.refresh, unit, "MSUF2_STATUS_INDICATOR")
    end
    if spec and spec.statusRuntime and not runtimeRefreshed then
        Call("MSUF_RefreshStatusIndicators", unit, "MSUF2_STATUS_INDICATOR")
    end
    if spec and spec.value == "level" then
        if unit == "boss" and _G.MSUF_BossTestMode and type(_G.MSUF_ApplyBossUnitframePreviewState) == "function" then _G.MSUF_ApplyBossUnitframePreviewState(true, "MSUF2_LEVEL_INDICATOR") end
    end
    M.RequestUnitApply(unit, "MSUF2_STATUS_INDICATOR", { preview = true, text = true, fonts = spec and spec.value == "level" })
end
local SetControlEnabled = W.SetControlEnabled
local function SeedText(unit)
    local conf = GetConf(unit)
    if type(_G.MSUF_Bars_SeedTextFromGeneral) == "function" then _G.MSUF_Bars_SeedTextFromGeneral(conf) end
    return conf
end
local function ReadText(unit, key, default)
    local conf = SeedText(unit)
    if conf[key] ~= nil then return conf[key] end
    local g = GetGeneral()
    if g[key] ~= nil then return g[key] end
    return default
end
local function SetText(unit, key, value, reason)
    local conf = SeedText(unit)
    if conf[key] == value then return end
    conf[key] = value
    conf.hpPowerTextOverride = nil
    M.RequestUnitApply(unit, reason or "MSUF2_TEXT", { text = true, preview = true })
end
local function NormalizePortrait(unit)
    local conf = GetConf(unit)
    local value = conf.portraitMode or "OFF"
    if value ~= "LEFT" and value ~= "RIGHT" then value = "OFF" end
    return value
end
local function SetPortraitValue(unit, key, value, reason)
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
local function NormalizeBossLayoutMode(value, legacyInvert)
    if type(value) == "string" and BOSS_LAYOUT_VALID[value] then return value end
    if legacyInvert == true then return "VERTICAL_UP" end
    return "VERTICAL_DOWN"
end
local function UpdateLoadActive(unit)
    local conf = GetConf(unit)
    local active = false
    for i = 1, #LOAD_CONDITIONS do
        if conf[LOAD_CONDITIONS[i].key] == true then
            active = true
            break
        end
    end
    conf.loadCondActive = active or nil
end
local UnitPage = M.UnitPage or {}
M.UnitPage = UnitPage
M.Assign(UnitPage, {
    UNIT_PAGES = UNIT_PAGES,
    POWER_UNITS = POWER_UNITS,
    CASTBAR_FIELDS = CASTBAR_FIELDS,
    LOAD_CONDITIONS = LOAD_CONDITIONS,
    STATUS_ANCHORS = STATUS_ANCHORS,
    DEFAULT_SYMBOLS = DEFAULT_SYMBOLS,
    StatusIconPackValues = StatusIconPackValues,
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
    GetBars = GetBars,
    Call = Call,
    DeepCopy = DeepCopy,
    DefaultCopyTarget = DefaultCopyTarget,
    UnitTopLabel = UnitTopLabel,
    UnitTopPillWidth = UnitTopPillWidth,
    ControlMeta = UnitControlMeta,
    SettingMeta = UnitSettingMeta,
    ReviewedMeta = UnitReviewedMeta,
    RegisterControl = RegisterUnitControl,
    NewCopyScopeDefaults = NewCopyScopeDefaults,
    ConfirmCopyToAll = ConfirmCopyToAll,
    CopyUnitSettings = CopyUnitSettings,
    ToggleEditMode = ToggleEditMode,
    IsEditModeActive = IsEditModeActive,
    SetBossPagePreviewActive = SetBossPagePreviewActive,
    ReadBool = ReadBool,
    SetBool = SetBool,
    ReadNumber = ReadNumber,
    SetNumber = SetNumber,
    IsPlayerPowerManagedByClassResources = IsPlayerPowerManagedByClassResources,
    SetString = SetString,
    ReadGeneralBool = ReadGeneralBool,
    SetGeneralBool = SetGeneralBool,
    ClampStatusLayer = ClampStatusLayer,
    StatusAllowed = StatusAllowed,
    StatusValues = StatusValues,
    FindStatusSpec = FindStatusSpec,
    CurrentStatusSpec = CurrentStatusSpec,
    ReadStatusBool = ReadStatusBool,
    ReadStatusNumber = ReadStatusNumber,
    ReadStatusString = ReadStatusString,
    RefreshStatusRuntime = RefreshStatusRuntime,
    SetControlEnabled = SetControlEnabled,
    SeedText = SeedText,
    ReadText = ReadText,
    SetText = SetText,
    NormalizePortrait = NormalizePortrait,
    SetPortraitValue = SetPortraitValue,
    NormalizeBossLayoutMode = NormalizeBossLayoutMode,
    UpdateLoadActive = UpdateLoadActive,
})
