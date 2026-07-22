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
local POWER_UNITS = KSW("player target focus targettarget focustarget pet boss")
local CASTBAR_FIELDS = {
    -- Castbar settings live in general DB rather than each unit DB. Keep this map as the one
    -- place where unit pages translate a unit key into the correct castbar field names.
    player = { enable = "enablePlayerCastbar", backend = "castbarPlayerBackend", providerMemory = "castbarPlayerBackendBeforeHide", time = "showPlayerCastTime", icon = "castbarPlayerShowIcon", text = "castbarPlayerShowSpellName", timeFormat = "castbarPlayerTimeFormat", w = "castbarPlayerBarWidth", h = "castbarPlayerBarHeight", match = "castbarPlayerMatchWidth" },
    target = { enable = "enableTargetCastbar", backend = "castbarTargetBackend", providerMemory = "castbarTargetBackendBeforeHide", time = "showTargetCastTime", icon = "castbarTargetShowIcon", text = "castbarTargetShowSpellName", targetName = "castbarTargetShowTargetName", timeFormat = "castbarTargetTimeFormat", w = "castbarTargetBarWidth", h = "castbarTargetBarHeight", match = "castbarTargetMatchWidth" },
    focus = { enable = "enableFocusCastbar", backend = "castbarFocusBackend", providerMemory = "castbarFocusBackendBeforeHide", time = "showFocusCastTime", icon = "castbarFocusShowIcon", text = "castbarFocusShowSpellName", targetName = "castbarFocusShowTargetName", timeFormat = "castbarFocusTimeFormat", w = "castbarFocusBarWidth", h = "castbarFocusBarHeight", match = "castbarFocusMatchWidth" },
    boss = { enable = "enableBossCastbar", backend = "bossCastbarBackend", providerMemory = "bossCastbarBackendBeforeHide", time = "showBossCastTime", icon = "showBossCastIcon", text = "showBossCastName", targetName = "showBossCastTargetName", timeFormat = "bossCastTimeFormat", w = "bossCastbarWidth", h = "bossCastbarHeight", match = "bossCastbarMatchWidth" },
}
local CASTBAR_PREFIX = { player = "castbarPlayer", target = "castbarTarget", focus = "castbarFocus", boss = "bossCast" }
local CASTBAR_COPY_SUFFIXES = WL [[IconPosition IconSize IconZoom IconOffsetX IconOffsetY IconSpacing IconBorderThickness IconBorderStyle SpellNamePosition SpellNameFontSize TextOffsetX TextOffsetY SpellNameAlign SpellNameMaxWidth SpellNameTruncate TimePosition TimeFontSize TimeOffsetX TimeOffsetY]]
local CASTBAR_TARGET_NAME_COPY_SUFFIXES = WL [[TargetNamePosition TargetNameFontSize TargetNameAlign TargetNameOffsetX TargetNameOffsetY]]
local LOAD_CONDITIONS = KLR [[
loadCondHideMounted=Mounted
loadCondHideOutOfCombat=Out of combat
loadCondHideSolo=Solo
loadCondHideInVehicle=In vehicle
loadCondHideInGroup=In group
loadCondHideInInstance=In instance
loadCondHideResting=Resting
loadCondHideInCombat=In combat
loadCondHideStealthed=Stealthed
loadCondHideInHousing=Housing
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
local RESTED_SYMBOLS = VTP "DEFAULT=Default|rested_moonzzz=Moon (3 z)|rested_moonzzzz=Moon (4 z)|rested_sleep_zzzz=Sleep ZzzZ|rested_zzz_compact=Compact Zzz|rested_zzz_diag=Diagonal Zzz|rested_zzz_stack=Stacked Zzz"
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
    StatusControl("level", "Level Text", "showLevelIndicator", true, "levelIndicatorSize", 14, "levelIndicatorAnchor", "NAMERIGHT", STATUS_LEVEL_ANCHORS, "levelIndicatorOffsetX", 0, "levelIndicatorOffsetY", 0, "levelIndicatorLayer", 7, "MSUF_RefreshIdentityTextFrames", { textIndicator = true }),
    StatusControl("raceText", "Race Text", "showRaceIndicator", false, "raceIndicatorSize", 14, "raceIndicatorAnchor", "NAMERIGHT", STATUS_LEVEL_ANCHORS, "raceIndicatorOffsetX", 0, "raceIndicatorOffsetY", 0, "raceIndicatorLayer", 7, "MSUF_RefreshIdentityTextFrames", { textIndicator = true }),
    StatusControl("classText", "Class Text", "showClassTextIndicator", false, "classTextIndicatorSize", 14, "classTextIndicatorAnchor", "NAMERIGHT", STATUS_LEVEL_ANCHORS, "classTextIndicatorOffsetX", 0, "classTextIndicatorOffsetY", 0, "classTextIndicatorLayer", 7, "MSUF_RefreshIdentityTextFrames", { textIndicator = true }),
    StatusControl("raidgroupname", "Raid Group", "showRaidGroupInName", false, "nameFontSize", 14, "raidGroupNameAnchor", "NAMERIGHT", RAID_GROUP_NAME_ANCHORS, "raidGroupNameOffsetX", 3, "raidGroupNameOffsetY", 0, "raidGroupNameLayer", 5, "MSUF_RefreshRaidGroupNameFrames", { allowed = function(unit) return unit == "player" or unit == "target" or unit == "targettarget" or unit == "focustarget" or unit == "focus" end, inlineName = true, legacyLayer = "nameTextLayer", copyProps = "show anchor x y layer", copyExtra = WL("raidGroupNameStyle") }),
    StatusControl("eliteicon", "Elite / Rare", "showEliteIcon", true, "eliteIconSize", 20, "eliteIconAnchor", "TOPRIGHT", STATUS_CORNER_ANCHORS, "eliteIconOffsetX", 2, "eliteIconOffsetY", 2, "eliteIconLayer", 7, "MSUF_RefreshEliteIconFrames", { allowed = function(unit) return unit == "target" or unit == "focus" or unit == "targettarget" or unit == "focustarget" or unit == "boss" end, iconStyle = "eliteIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "eliteIconCustomIcon" }),
    StatusControl("statusText", "Dead / Offline Text", "statusDeadTextEnabled", true, "statusTextSize", 16, "statusTextAnchor", "CENTER", STATUS_CORNER_ANCHORS, "statusTextOffsetX", 0, "statusTextOffsetY", 0, "statusTextLayer", 7, "MSUF_RequestStatusTextRefresh", { statusRuntime = true, statusTextState = "DEAD", legacyShow = "statusTextEnabled", legacyState = "showDead" }),
    StatusControl("statusGhostText", "Ghost Text", "statusGhostTextEnabled", true, "statusGhostTextSize", 16, "statusGhostTextAnchor", "CENTER", STATUS_CORNER_ANCHORS, "statusGhostTextOffsetX", 0, "statusGhostTextOffsetY", 0, "statusGhostTextLayer", 7, "MSUF_RequestStatusTextRefresh", { statusRuntime = true, statusTextState = "GHOST", legacyShow = "statusTextEnabled", legacyState = "showGhost", legacySize = "statusTextSize", legacyAnchor = "statusTextAnchor", legacyX = "statusTextOffsetX", legacyY = "statusTextOffsetY", legacyLayer = "statusTextLayer" }),
    StatusControl("statusAFKText", "AFK Text", "statusAFKTextEnabled", false, "statusAFKTextSize", 16, "statusAFKTextAnchor", "CENTER", STATUS_CORNER_ANCHORS, "statusAFKTextOffsetX", 0, "statusAFKTextOffsetY", 0, "statusAFKTextLayer", 7, "MSUF_RequestStatusTextRefresh", { statusRuntime = true, statusTextState = "AFK", legacyShow = "statusTextEnabled", legacyState = "showAFK", legacySize = "statusTextSize", legacyAnchor = "statusTextAnchor", legacyX = "statusTextOffsetX", legacyY = "statusTextOffsetY", legacyLayer = "statusTextLayer" }),
    StatusControl("statusDNDText", "DND Text", "statusDNDTextEnabled", false, "statusDNDTextSize", 16, "statusDNDTextAnchor", "CENTER", STATUS_CORNER_ANCHORS, "statusDNDTextOffsetX", 0, "statusDNDTextOffsetY", 0, "statusDNDTextLayer", 7, "MSUF_RequestStatusTextRefresh", { statusRuntime = true, statusTextState = "DND", legacyShow = "statusTextEnabled", legacyState = "showDND", legacySize = "statusTextSize", legacyAnchor = "statusTextAnchor", legacyX = "statusTextOffsetX", legacyY = "statusTextOffsetY", legacyLayer = "statusTextLayer" }),
    StatusControl("statusCombat", "Combat", "showCombatStateIndicator", true, "combatStateIndicatorSize", 18, "combatStateIndicatorAnchor", "TOPLEFT", STATUS_CORNER_ANCHORS, "combatStateIndicatorOffsetX", 0, "combatStateIndicatorOffsetY", 0, "combatStateIndicatorLayer", 7, "MSUF_RequestStatusCombatIndicatorRefresh", { allowed = function(unit) return unit == "player" or unit == "target" end, symbol = "combatStateIndicatorSymbol", symbols = COMBAT_SYMBOLS, statusRuntime = true, iconStyle = "combatStateIndicatorIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "combatStateIndicatorCustomIcon" }),
    StatusControl("statusResting", "Rested (player only)", "showRestingIndicator", false, "restedStateIndicatorSize", 18, "restedStateIndicatorAnchor", "TOPLEFT", STATUS_CORNER_ANCHORS, "restedStateIndicatorOffsetX", 0, "restedStateIndicatorOffsetY", 0, "restedStateIndicatorLayer", 7, "MSUF_RequestStatusRestingIndicatorRefresh", { allowed = function(unit) return unit == "player" end, symbol = "restedStateIndicatorSymbol", symbols = RESTED_SYMBOLS, statusRuntime = true, iconStyle = "restedStateIndicatorIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "restedStateIndicatorCustomIcon" }),
    StatusControl("statusIncomingRes", "Incoming Rez", "showIncomingResIndicator", true, "incomingResIndicatorSize", 18, "incomingResIndicatorAnchor", "TOPRIGHT", STATUS_CORNER_ANCHORS, "incomingResIndicatorOffsetX", 0, "incomingResIndicatorOffsetY", 0, "incomingResIndicatorLayer", 7, "MSUF_RequestStatusIncomingResIndicatorRefresh", { allowed = function(unit) return unit == "player" or unit == "target" end, symbol = "incomingResIndicatorSymbol", symbols = RESS_SYMBOLS, statusRuntime = true, iconStyle = "incomingResIndicatorIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "incomingResIndicatorCustomIcon" }),
    StatusControl("statusPvp", "PvP Flag (War Mode/PvP)", "showPvpIndicator", true, "pvpIndicatorSize", 18, "pvpIndicatorAnchor", "TOPRIGHT", STATUS_CORNER_ANCHORS, "pvpIndicatorOffsetX", 0, "pvpIndicatorOffsetY", 0, "pvpIndicatorLayer", 7, "MSUF_RequestStatusPvpIndicatorRefresh", { allowed = function(unit) return unit == "player" or unit == "target" or unit == "focus" or unit == "targettarget" or unit == "focustarget" end, statusRuntime = true, iconStyle = "pvpIndicatorIconStyle", defaultIconStyle = "BLIZZARD", customIcon = "pvpIndicatorCustomIcon" }),
}
local TEXT_ANCHORS = VTP "LEFT=Left|CENTER=Center|RIGHT=Right"
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
local PORTRAIT_SHAPES = VTP "SQUARE=Square|CIRCLE=Circle|ROUNDED=Rounded|DIAMOND=Diamond"
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
local COPY_POWER_BAR_FIELDS = WL [[showPowerBar powerBarHeight embedPowerBarIntoHealth powerBarBorderEnabled powerBarBorderThickness powerSmoothFill powerBarDetached detachedPowerBarShape detachedPowerOrbSize detachedPowerBarWidth detachedPowerBarHeight detachedPowerBarOffsetX detachedPowerBarOffsetY detachedPowerBarAnchorMode detachedPowerBarFrameLevelOffset detachedPowerBarTextOnBar detachedPowerBarSyncClassPower detachedPowerBarAnchorToClassPower]]
local COPY_PORTRAIT_FIELDS = WL [[portraitMode portraitRender portraitClassStyle portraitCastSpellIcon portraitShape portraitSizeOverride portraitOffsetX portraitOffsetY portraitZoom portraitBorderStyle portraitBorderThickness portraitBgEnabled portraitFillBorder]]
local COPY_TEXT_FIELDS = WL [[showName showHP showPower showPowerText nameTextAnchor nameOffsetX nameOffsetY nameFontSize showRaidGroupInName raidGroupNameAnchor raidGroupNameOffsetX raidGroupNameOffsetY raidGroupNameLayer raidGroupNameStyle hpOffsetX hpOffsetY hpFontSize hpTextMode textLeft textCenter textRight hpTextLeftHidePercentSymbol hpTextCenterHidePercentSymbol hpTextRightHidePercentSymbol hpTextLeftAbsorbIcon hpTextCenterAbsorbIcon hpTextRightAbsorbIcon hpTextReverse hpTextSeparator healthTextDecimals hpFullValueShort hpAbsorbIcon powerOffsetX powerOffsetY powerFontSize powerTextMode powerTextLeft powerTextCenter powerTextRight powerTextLeftHidePercentSymbol powerTextCenterHidePercentSymbol powerTextRightHidePercentSymbol powerTextSeparator nameTextLayer hpTextLayer powerTextLayer]]
local COPY_INDICATOR_FIELDS = M.CopyFieldsFromSpecs(STATUS_CONTROLS, "leader assist raidmarker raidgroupname eliteicon", nil, "show iconStyle customIcon x y anchor size layer symbol")
local COPY_STATUSICON_FIELDS = M.CopyFieldsFromSpecs(STATUS_CONTROLS, "level raceText classText statusText statusGhostText statusAFKText statusDNDText statusCombat statusResting statusIncomingRes statusPvp", "statusIconsTestMode statusIconsMidnightStyle statusIconsAlpha statusTextEnabled", "show iconStyle customIcon x y anchor size layer symbol")
local COPY_FRAME_BASIC_FIELDS = WL [[enabled showName showHP showPower reverseFillBars smoothFill healthColorMode]]
local COPY_TRANSPARENCY_FIELDS = WL [[hpBarAlpha powerBarAlpha hpBgAlpha powerBarBgAlpha alphaExcludeTextPortrait rangeFadeEnabled rangeFadeAlpha rangeFadeLayerMode]]
local COPY_LOAD_CONDITION_FIELDS = WL [[loadCondHideMounted loadCondHideInVehicle loadCondHideResting loadCondHideInCombat loadCondHideOutOfCombat loadCondHideStealthed loadCondHideSolo loadCondHideInGroup loadCondHideInInstance loadCondHideInHousing loadCondActive]]
local COPY_LAYOUT_FIELDS = WL [[width height offsetX offsetY point relativePoint anchorFrameName anchorToUnitframe]]
local AURA_COPY_UNITS = KSW("player target focus boss")
local AURA_COPY_FLAGS = { player = "showPlayer", target = "showTarget", focus = "showFocus", boss = "showBoss" }
local AURA_BOSS_RUNTIME_UNITS = WL("boss1 boss2 boss3 boss4 boss5")
local UF_COPY_CATEGORIES = {
    { key = "basics",       label = "Frame Basics",     default = true },
    { key = "text",         label = "Text",             default = true },
    { key = "portrait",     label = "Portrait",         default = true },
    { key = "power",        label = "Power Bar",        default = true },
    { key = "auras",        label = "Auras · All",      default = true, description = "Copies the complete Aura workspace: visibility, layout, Blizzard filters, Buff/Debuff blacklists, Custom 1-3, Dots on target, Strata, and Full-Frame effects." },
    { key = "castbar",      label = "Castbar",          default = true },
    { key = "status",       label = "Status Icons",     default = true },
    { key = "load",         label = "Load Conditions",  default = true },
    { key = "transparency", label = "Transparency",     default = true },
    { key = "layout",       label = "Size & Anchoring", default = false },
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
        db.targettarget = db.targettarget or db.tot or {}
        db.tot = db.targettarget
        return db.targettarget, key
    end
    db[key] = db[key] or {}
    return db[key], key
end
local function CopyFields(dst, src, fields)
    for i = 1, #fields do
        dst[fields[i]] = src[fields[i]]
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
}
local function ReadPowerCopyValue(conf, unitKey, spec)
    local ok, value = spec.read(conf and conf[spec.key])
    if ok then return value end
    local fn = spec.fn and _G[spec.fn]
    if type(fn) == "function" then return fn(unitKey) end
    return spec.fallback(unitKey)
end
local function CopyPowerBarFields(dst, src, srcKey)
    CopyFields(dst, src, COPY_POWER_BAR_FIELDS)
    for i = 1, #POWER_COPY_OVERRIDES do
        local spec = POWER_COPY_OVERRIDES[i]
        dst[spec.key] = ReadPowerCopyValue(src, srcKey, spec)
    end
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
    g[d.providerMemory] = remembered
    g[d.time] = g[s.time]
    g[d.icon] = g[s.icon]
    g[d.text] = g[s.text]
    if s.targetName and d.targetName then g[d.targetName] = g[s.targetName] end
    g[d.timeFormat] = g[s.timeFormat]
    g[d.w] = g[s.w]
    g[d.h] = g[s.h]
    g[d.match] = g[s.match]
    local srcPrefix = CASTBAR_PREFIX[src]
    local dstPrefix = CASTBAR_PREFIX[dst]
    if not srcPrefix or not dstPrefix then return true end
    for i = 1, #CASTBAR_COPY_SUFFIXES do
        g[dstPrefix .. CASTBAR_COPY_SUFFIXES[i]] = g[srcPrefix .. CASTBAR_COPY_SUFFIXES[i]]
    end
    if s.targetName and d.targetName then
        for i = 1, #CASTBAR_TARGET_NAME_COPY_SUFFIXES do
            g[dstPrefix .. CASTBAR_TARGET_NAME_COPY_SUFFIXES[i]] = g[srcPrefix .. CASTBAR_TARGET_NAME_COPY_SUFFIXES[i]]
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

    local function CopyScopedAuraRecord(rootKey)
        local root = auras[rootKey]
        if type(root) ~= "table" then return end
        root.perUnit = type(root.perUnit) == "table" and root.perUnit or {}
        local source = root.perUnit[src]
        root.perUnit[dst] = type(source) == "table" and DeepCopy(source) or nil
    end
    -- Custom containers are intentionally outside auras.perUnit. Copy both
    -- the native containers and the legacy per-frame migration record so no
    -- whitelist or Full-Frame configuration is silently left behind.
    CopyScopedAuraRecord("customContainers")
    CopyScopedAuraRecord("customDisplays")
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
local function CopyUnitSettings(unit, target, scopes)
    M.EnsureDB()
    ExportPublic("MSUF_DB", _G.MSUF_DB or {})
    _G.MSUF_DB.general = _G.MSUF_DB.general or {}
    local g = _G.MSUF_DB.general
    local src, srcKey = EnsureUnitDB(unit)
    if not src or not srcKey then return end
    target = (type(target) == "string") and target:lower() or DefaultCopyTarget(srcKey)
    scopes = (type(scopes) == "table") and scopes or NewCopyScopeDefaults()
    local function CopyOne(toKey)
        local dst, dstKey = EnsureUnitDB(toKey)
        if not dst or not dstKey or dstKey == srcKey then return end
        if scopes.basics then CopyFields(dst, src, COPY_FRAME_BASIC_FIELDS) end
        if scopes.text then
            CopyFields(dst, src, COPY_TEXT_FIELDS)
            dst.hpPowerTextOverride = nil
        end
        if scopes.portrait then
            CopyFields(dst, src, COPY_PORTRAIT_FIELDS)
            dst.portraitDecoOverride = nil
        end
        if scopes.power then CopyPowerBarFields(dst, src, srcKey) end
        local copiedAuras = scopes.auras and CopyAuras3UnitSettings(srcKey, dstKey) or false
        if scopes.status then
            CopyFields(dst, src, COPY_INDICATOR_FIELDS)
            CopyFields(dst, src, COPY_STATUSICON_FIELDS)
        end
        if scopes.castbar then
            dst.showInterrupt = src.showInterrupt
            if CopyCastbar(g, srcKey, dstKey) then
                Call("MSUF_UpdateCastbarWidthSourceSync", g, dstKey)
            end
        end
        if scopes.load then CopyFields(dst, src, COPY_LOAD_CONDITION_FIELDS) end
        if scopes.transparency then CopyFields(dst, src, COPY_TRANSPARENCY_FIELDS) end
        if scopes.layout then CopyFields(dst, src, COPY_LAYOUT_FIELDS) end
        M.RequestUnitApply(dstKey, "MSUF2_COPY_UNIT", {
            preview = true,
            text = scopes.text or scopes.status,
            power = scopes.power,
            alpha = scopes.transparency,
            castbar = scopes.castbar,
            auras = copiedAuras,
        })
    end
    local function FinishCopy(statusUnit)
        if scopes.status then
            Call("MSUF_RefreshAllIndicators", statusUnit, "MSUF2_COPY_UNIT_STATUS")
            Call("MSUF_RefreshStatusIndicators", statusUnit, "MSUF2_COPY_UNIT_STATUS")
        end
    end
    if target == "all" then
        ConfirmCopyToAll(function()
            for i = 1, #UNIT_COPY_TARGETS do
                local value = UNIT_COPY_TARGETS[i].value
                if value ~= srcKey then CopyOne(value) end
            end
            FinishCopy()
        end)
        return
    end
    target = CanonUnitKey(target)
    if not target or target == srcKey then return end
    CopyOne(target)
    FinishCopy(target)
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
        if active then
            _G.MSUF2_BossUnitframePreviewActive = nil
            bossPagePreviewPendingCleanup = true
        end
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
    M.SetUnitValue(unit, key, value, reason or "MSUF2_PORTRAIT", { preview = true })
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
