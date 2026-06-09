local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets

local floor = math.floor
local VT = M.ValueTextList
local VTR = M.ValueTextRows
local KLR, KSW, WL = M.KeyLabelRows, M.KeySetFromWords, M.WordList

local UNIT_PAGES = {
    uf_player = { unit = "player", title = "MSUF Player", label = "Player" },
    uf_target = { unit = "target", title = "MSUF Target", label = "Target" },
    uf_targettarget = { unit = "targettarget", title = "MSUF Target of Target", label = "Target of Target" },
    uf_focustarget = { unit = "focustarget", title = "MSUF Focus Target", label = "Focus Target" },
    uf_focus = { unit = "focus", title = "MSUF Focus", label = "Focus" },
    uf_pet = { unit = "pet", title = "MSUF Pet", label = "Pet" },
    uf_boss = { unit = "boss", title = "MSUF Boss Frames", label = "Boss" },
}

local POWER_UNITS = KSW("player target focus targettarget focustarget pet boss")

local CASTBAR_FIELDS = {
    player = { enable = "enablePlayerCastbar", backend = "castbarPlayerBackend", providerMemory = "castbarPlayerBackendBeforeHide", time = "showPlayerCastTime", icon = "castbarPlayerShowIcon", text = "castbarPlayerShowSpellName", timeFormat = "castbarPlayerTimeFormat" },
    target = { enable = "enableTargetCastbar", backend = "castbarTargetBackend", providerMemory = "castbarTargetBackendBeforeHide", time = "showTargetCastTime", icon = "castbarTargetShowIcon", text = "castbarTargetShowSpellName", timeFormat = "castbarTargetTimeFormat" },
    focus = { enable = "enableFocusCastbar", backend = "castbarFocusBackend", providerMemory = "castbarFocusBackendBeforeHide", time = "showFocusCastTime", icon = "castbarFocusShowIcon", text = "castbarFocusShowSpellName", timeFormat = "castbarFocusTimeFormat" },
    boss = { enable = "enableBossCastbar", backend = "bossCastbarBackend", providerMemory = "bossCastbarBackendBeforeHide", time = "showBossCastTime", icon = "showBossCastIcon", text = "showBossCastName", timeFormat = "bossCastTimeFormat" },
}

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
]]

local STATUS_ANCHORS = VTR [[
TOPLEFT=Top Left
TOPRIGHT=Top Right
BOTTOMLEFT=Bottom Left
BOTTOMRIGHT=Bottom Right
CENTER=Center
TOP=Top
BOTTOM=Bottom
LEFT=Left
RIGHT=Right
]]
local STATUS_CORNER_ANCHORS = STATUS_ANCHORS
local function WithNameAnchors(rightText, leftText)
    local out = VT("NAMERIGHT", rightText, "NAMELEFT", leftText)
    for i = 1, #STATUS_ANCHORS do out[#out + 1] = STATUS_ANCHORS[i] end
    return out
end
local STATUS_LEVEL_ANCHORS = WithNameAnchors("Right to player name", "Left to player name")
local RAID_GROUP_NAME_ANCHORS = WithNameAnchors("Right to name", "Left to name")
local COMBAT_SYMBOLS = VTR [[
DEFAULT=Default
weapon_axes_crossed=Axes
weapon_bows_crossed=Bows
weapon_crossbows_crossed=Crossbows
weapon_daggers_crossed=Daggers
weapon_fishing_poles_crossed=Fishing
weapon_fist_crossed=Fist
weapon_guns_crossed=Guns
weapon_maces_crossed=Maces
weapon_polearms_crossed=Polearms
weapon_shuriken=Shuriken
weapon_staves_crossed=Staves
weapon_swords_crossed=Swords
weapon_thrown_crossed=Thorn
weapon_wands_crossed=Wands
weapon_warglaives_crossed=Warglaives
]]
local RESTED_SYMBOLS = VTR [[
DEFAULT=Default
rested_moonzzz=Moon (3 z)
rested_moonzzzz=Moon (4 z)
rested_sleep_zzzz=Sleep ZzzZ
rested_zzz_compact=Compact Zzz
rested_zzz_diag=Diagonal Zzz
rested_zzz_stack=Stacked Zzz
]]
local RESS_SYMBOLS = VTR [[
DEFAULT=Default
resurrection_ankh=Ankh
resurrection_cross=Cross
resurrection_soul=Soul
resurrection_wings=Angelic Wings
]]
local DEFAULT_SYMBOLS = VT("DEFAULT", "Default")

local function StatusIconPackValues()
    local fn = _G.MSUF_GetStatusIconPackValues
    if type(fn) == "function" then return fn(false) end
    return VTR [[
BLIZZARD=Blizzard (Default)
CLASSIC=Classic
MIDNIGHT=Midnight
GLOSSY_ORBS=Glossy Orbs
DARK_EMBOSS=Dark Emboss
GLASS_PANELS=Glass Panels
NEON_OUTLINE=Neon Outline
RING_SYMBOLS=Ring Symbols
DOTS=Dots
SHAPES=Shapes
DIAMONDS=Diamonds
SQUARES=Squares
]]
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
    StatusControl("leader", "Leader / Assist", "showLeaderIcon", true, "leaderIconSize", 14, "leaderIconAnchor", "TOPLEFT", STATUS_CORNER_ANCHORS, "leaderIconOffsetX", 0, "leaderIconOffsetY", 3, "leaderIconLayer", 7, "MSUF_RefreshLeaderIconFrames", { allowed = function(unit) return unit == "player" or unit == "target" end, iconStyle = "leaderIconStyle", defaultIconStyle = "BLIZZARD" }),
    StatusControl("raidmarker", "Raid Marker", "showRaidMarker", true, "raidMarkerSize", 18, "raidMarkerAnchor", "TOPLEFT", STATUS_CORNER_ANCHORS, "raidMarkerOffsetX", 16, "raidMarkerOffsetY", 3, "raidMarkerLayer", 7, "MSUF_RefreshRaidMarkerFrames"),
    StatusControl("level", "Level", "showLevelIndicator", true, "levelIndicatorSize", 14, "levelIndicatorAnchor", "NAMERIGHT", STATUS_LEVEL_ANCHORS, "levelIndicatorOffsetX", 0, "levelIndicatorOffsetY", 0, "levelIndicatorLayer", 7, "MSUF_RefreshLevelIndicatorFrames"),
    StatusControl("raidgroupname", "Raid Group", "showRaidGroupInName", false, "nameFontSize", 14, "raidGroupNameAnchor", "NAMERIGHT", RAID_GROUP_NAME_ANCHORS, "raidGroupNameOffsetX", 3, "raidGroupNameOffsetY", 0, "nameTextLayer", 5, "MSUF_RefreshRaidGroupNameFrames", { allowed = function(unit) return unit == "player" or unit == "target" or unit == "targettarget" or unit == "focustarget" or unit == "focus" end, inlineName = true }),
    StatusControl("eliteicon", "Elite / Rare", "showEliteIcon", true, "eliteIconSize", 20, "eliteIconAnchor", "TOPRIGHT", STATUS_CORNER_ANCHORS, "eliteIconOffsetX", 2, "eliteIconOffsetY", 2, "eliteIconLayer", 7, "MSUF_RefreshEliteIconFrames", { allowed = function(unit) return unit == "target" or unit == "focus" or unit == "targettarget" or unit == "focustarget" or unit == "boss" end }),
    StatusControl("statusText", "Dead Text", "statusTextEnabled", true, "statusTextSize", 16, "statusTextAnchor", "CENTER", STATUS_CORNER_ANCHORS, "statusTextOffsetX", 0, "statusTextOffsetY", 0, "statusTextLayer", 7, "MSUF_RequestStatusTextRefresh", { statusRuntime = true }),
    StatusControl("statusCombat", "Combat", "showCombatStateIndicator", true, "combatStateIndicatorSize", 18, "combatStateIndicatorAnchor", "TOPLEFT", STATUS_CORNER_ANCHORS, "combatStateIndicatorOffsetX", 0, "combatStateIndicatorOffsetY", 0, "combatStateIndicatorLayer", 7, "MSUF_RequestStatusCombatIndicatorRefresh", { allowed = function(unit) return unit == "player" or unit == "target" end, symbol = "combatStateIndicatorSymbol", symbols = COMBAT_SYMBOLS, statusRuntime = true }),
    StatusControl("statusResting", "Rested (player only)", "showRestingIndicator", false, "restedStateIndicatorSize", 18, "restedStateIndicatorAnchor", "TOPLEFT", STATUS_CORNER_ANCHORS, "restedStateIndicatorOffsetX", 0, "restedStateIndicatorOffsetY", 0, "restedStateIndicatorLayer", 7, "MSUF_RequestStatusRestingIndicatorRefresh", { allowed = function(unit) return unit == "player" end, symbol = "restedStateIndicatorSymbol", symbols = RESTED_SYMBOLS, statusRuntime = true }),
    StatusControl("statusIncomingRes", "Incoming Rez", "showIncomingResIndicator", true, "incomingResIndicatorSize", 18, "incomingResIndicatorAnchor", "TOPRIGHT", STATUS_CORNER_ANCHORS, "incomingResIndicatorOffsetX", 0, "incomingResIndicatorOffsetY", 0, "incomingResIndicatorLayer", 7, "MSUF_RequestStatusIncomingResIndicatorRefresh", { allowed = function(unit) return unit == "player" or unit == "target" end, symbol = "incomingResIndicatorSymbol", symbols = RESS_SYMBOLS, statusRuntime = true }),
}

local TEXT_ANCHORS = VTR [[LEFT=Left
CENTER=Center
RIGHT=Right]]
local HP_MODES = VTR [[
PERCENT=Percent
CURRENT=Current
MAX=Max
DEFICIT=Deficit
CURMAX=Current / Max
CURPERCENT=Current / Percent
CURMAXPERCENT=Current / Max / Percent
MAXPERCENT=Max / Percent
PERCENTCUR=Percent / Current
PERCENTMAX=Percent / Max
PERCENTCURMAX=Percent / Current / Max
NONE=None
]]
local POWER_MODES = VTR [[
CURRENT=Current
MAX=Max
CURMAX=Current / Max
PERCENT=Percent
CURPERCENT=Current / Percent
CURMAXPERCENT=Current / Max / Percent
NONE=None
]]
local BOSS_LAYOUT_OPTIONS = VTR [[
VERTICAL_DOWN=Vertical (top -> bottom)
VERTICAL_UP=Vertical (bottom -> top)
HORIZONTAL_RIGHT=Horizontal (left -> right)
HORIZONTAL_LEFT=Horizontal (right -> left)
]]

local BOSS_LAYOUT_VALID = KSW("VERTICAL_DOWN VERTICAL_UP HORIZONTAL_RIGHT HORIZONTAL_LEFT")

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
local PORTRAIT_RENDER = VTR [[
2D=2D portrait
CLASS=Class portrait
]]
local PORTRAIT_SHAPES = VTR [[
SQUARE=Square
CIRCLE=Circle
ROUNDED=Rounded
DIAMOND=Diamond
]]
local PORTRAIT_BORDERS = VTR [[
NONE=No border
SOLID=Solid
CLASS_COLOR=Class color
REACTION=Reaction color
CUSTOM=Custom color
]]

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
    local fn = _G[name]
    if type(fn) == "function" then pcall(fn, ...) end
end

local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    if type(CopyTable) == "function" then return CopyTable(src) end
    return M.DeepCopy(src)
end

local COPY_POWER_BAR_FIELDS = WL [[showPowerBar powerBarHeight embedPowerBarIntoHealth powerBarBorderEnabled powerBarBorderThickness powerSmoothFill powerBarDetached detachedPowerBarWidth detachedPowerBarHeight detachedPowerBarOffsetX detachedPowerBarOffsetY detachedPowerBarFrameLevelOffset detachedPowerBarTextOnBar detachedPowerBarSyncClassPower detachedPowerBarAnchorToClassPower]]
local COPY_PORTRAIT_FIELDS = WL [[portraitMode portraitRender portraitClassStyle portraitShape portraitSizeOverride portraitOffsetX portraitOffsetY portraitBorderStyle portraitBorderThickness portraitBgEnabled portraitFillBorder]]
local COPY_TEXT_FIELDS = WL [[showName showHP showPower nameTextAnchor nameOffsetX nameOffsetY nameFontSize showRaidGroupInName raidGroupNameAnchor raidGroupNameOffsetX raidGroupNameOffsetY raidGroupNameStyle hpOffsetX hpOffsetY hpFontSize hpTextMode textLeft textCenter textRight hpTextReverse hpTextSeparator powerOffsetX powerOffsetY powerFontSize powerTextMode powerTextLeft powerTextCenter powerTextRight powerTextSeparator nameTextLayer hpTextLayer powerTextLayer]]
local COPY_INDICATOR_FIELDS = WL [[showLeaderIcon leaderIconStyle leaderIconOffsetX leaderIconOffsetY leaderIconAnchor leaderIconSize leaderIconLayer showRaidMarker raidMarkerOffsetX raidMarkerOffsetY raidMarkerAnchor raidMarkerSize raidMarkerLayer showRaidGroupInName raidGroupNameAnchor raidGroupNameOffsetX raidGroupNameOffsetY raidGroupNameStyle showLevelIndicator levelIndicatorOffsetX levelIndicatorOffsetY levelIndicatorAnchor levelIndicatorSize levelIndicatorLayer showEliteIcon eliteIconSize eliteIconAnchor eliteIconOffsetX eliteIconOffsetY eliteIconLayer]]
local COPY_STATUSICON_FIELDS = WL [[statusIconsTestMode statusIconsMidnightStyle statusIconsAlpha statusTextEnabled statusTextOffsetX statusTextOffsetY statusTextAnchor statusTextSize statusTextLayer showCombatStateIndicator showRestingIndicator showIncomingResIndicator combatStateIndicatorOffsetX combatStateIndicatorOffsetY combatStateIndicatorAnchor combatStateIndicatorSize combatStateIndicatorLayer combatStateIndicatorSymbol restedStateIndicatorOffsetX restedStateIndicatorOffsetY restedStateIndicatorAnchor restedStateIndicatorSize restedStateIndicatorLayer restedStateIndicatorSymbol incomingResIndicatorOffsetX incomingResIndicatorOffsetY incomingResIndicatorAnchor incomingResIndicatorSize incomingResIndicatorLayer incomingResIndicatorSymbol]]
local COPY_FRAME_BASIC_FIELDS = WL [[enabled showName showHP showPower reverseFillBars smoothFill]]
local COPY_TRANSPARENCY_FIELDS = WL [[hpBarAlpha hpBgAlpha alphaExcludeTextPortrait rangeFadeEnabled rangeFadeAlpha rangeFadeLayerMode]]
local COPY_LOAD_CONDITION_FIELDS = WL [[loadCondHideMounted loadCondHideInVehicle loadCondHideResting loadCondHideInCombat loadCondHideOutOfCombat loadCondHideStealthed loadCondHideSolo loadCondHideInGroup loadCondHideInInstance loadCondActive]]
local COPY_LAYOUT_FIELDS = WL [[width height offsetX offsetY point relativePoint anchorFrameName anchorToUnitframe]]

local UF_COPY_CATEGORIES = {
    { key = "basics",       label = "Frame Basics",     default = true },
    { key = "text",         label = "Text",             default = true },
    { key = "portrait",     label = "Portrait",         default = true },
    { key = "power",        label = "Power Bar",        default = true },
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

local UNIT_COPY_TARGETS = VTR [[
player=Player
target=Target
targettarget=Target of Target
focustarget=Focus Target
focus=Focus
pet=Pet
boss=Boss Frames
]]

local function DefaultCopyTarget(unit)
    for i = 1, #UNIT_COPY_TARGETS do
        local value = UNIT_COPY_TARGETS[i].value
        if value ~= unit then return value end
    end
    return "target"
end

local function UnitTopLabel(unit)
    local label = ({
        player = "Player",
        target = "Target",
        targettarget = "Target of Target",
        focustarget = "Focus Target",
        focus = "Focus",
        boss = "Boss Frames",
        pet = "Pet",
    })[unit] or tostring(unit or "")
    return (M.Tr and M.Tr(label)) or label
end

local function UnitTopPillWidth(unit)
    if unit == "targettarget" then return 116 end
    if unit == "focustarget" then return 104 end
    if unit == "boss" then return 92 end
    if unit == "target" then return 62 end
    if unit == "focus" then return 58 end
    if unit == "pet" then return 46 end
    return 56
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

local function ReadPowerBarEnabled(conf, unitKey)
    if conf and conf.showPowerBar ~= nil then return conf.showPowerBar ~= false end
    local fn = _G.MSUF_ReadUnitPowerBarEnabled
    if type(fn) == "function" then return fn(unitKey) end
    local b, bk = _G.MSUF_DB and _G.MSUF_DB.bars, PB_SHOW_KEY_MAP[unitKey]
    if b and bk and b[bk] ~= nil then return b[bk] ~= false end
    return PB_SHOW_DEFAULTS[unitKey] ~= false
end

local function ReadPowerBarHeight(conf, unitKey)
    if conf and type(conf.powerBarHeight) == "number" then return conf.powerBarHeight end
    local fn = _G.MSUF_ReadUnitPowerBarHeight
    if type(fn) == "function" then return fn(unitKey) end
    local b = _G.MSUF_DB and _G.MSUF_DB.bars
    return tonumber(b and b.powerBarHeight) or 3
end

local function ReadPowerBarEmbed(conf, unitKey)
    if conf and conf.embedPowerBarIntoHealth ~= nil then return conf.embedPowerBarIntoHealth == true end
    local fn = _G.MSUF_ReadUnitPowerBarEmbed
    if type(fn) == "function" then return fn(unitKey) end
    local b = _G.MSUF_DB and _G.MSUF_DB.bars
    return b and b.embedPowerBarIntoHealth == true
end

local function ReadPowerBarBorderEnabled(conf, unitKey)
    if conf and conf.powerBarBorderEnabled ~= nil then return conf.powerBarBorderEnabled == true end
    local fn = _G.MSUF_ReadUnitPowerBarBorderEnabled
    if type(fn) == "function" then return fn(unitKey) end
    local b = _G.MSUF_DB and _G.MSUF_DB.bars
    return b and b.powerBarBorderEnabled == true
end

local function ReadPowerBarBorderThickness(conf, unitKey)
    if conf and type(conf.powerBarBorderThickness) == "number" then return conf.powerBarBorderThickness end
    local fn = _G.MSUF_ReadUnitPowerBarBorderThickness
    if type(fn) == "function" then return fn(unitKey) end
    local b = _G.MSUF_DB and _G.MSUF_DB.bars
    return tonumber(b and (b.powerBarBorderThickness or b.powerBarBorderSize)) or 1
end

local function ReadPowerSmoothFill(conf, unitKey)
    if conf and conf.powerSmoothFill ~= nil then return conf.powerSmoothFill == true end
    if unitKey == "player" then
        local b = _G.MSUF_DB and _G.MSUF_DB.bars
        return not (b and b.smoothPowerBar == false)
    end
    return false
end

local function CopyPowerBarFields(dst, src, srcKey)
    CopyFields(dst, src, COPY_POWER_BAR_FIELDS)
    dst.showPowerBar = ReadPowerBarEnabled(src, srcKey)
    dst.powerBarHeight = ReadPowerBarHeight(src, srcKey)
    dst.embedPowerBarIntoHealth = ReadPowerBarEmbed(src, srcKey)
    dst.powerBarBorderEnabled = ReadPowerBarBorderEnabled(src, srcKey)
    dst.powerBarBorderThickness = ReadPowerBarBorderThickness(src, srcKey)
    dst.powerSmoothFill = ReadPowerSmoothFill(src, srcKey)
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
    g[d.timeFormat] = g[s.timeFormat]

    local prefixByUnit = {
        player = "castbarPlayer",
        target = "castbarTarget",
        focus = "castbarFocus",
        boss = "bossCast",
    }
    local srcPrefix = prefixByUnit[src]
    local dstPrefix = prefixByUnit[dst]
    if not srcPrefix or not dstPrefix then return end
    local suffixes = {
        "IconPosition", "IconSize", "IconOffsetX", "IconOffsetY", "IconSpacing", "IconBorderStyle",
        "SpellNamePosition", "SpellNameFontSize", "TextOffsetX", "TextOffsetY", "SpellNameAlign", "SpellNameMaxWidth", "SpellNameTruncate",
        "TimePosition", "TimeFontSize", "TimeOffsetX", "TimeOffsetY",
    }
    for i = 1, #suffixes do
        g[dstPrefix .. suffixes[i]] = g[srcPrefix .. suffixes[i]]
    end
end

local function EnsureCopyDialog()
    if not StaticPopupDialogs or StaticPopupDialogs.MSUF2_COPY_TO_ALL_CONFIRM then return end
    StaticPopupDialogs.MSUF2_COPY_TO_ALL_CONFIRM = {
        text = M.Tr("Copy these settings to ALL unitframes?\n\nThis will overwrite existing settings on Player/Target/Focus/Boss/Pet/Target of Target/Focus Target."),
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function(_, data)
            if type(data) == "function" then data() end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
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
    _G.MSUF_DB = _G.MSUF_DB or {}
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
        if scopes.status then
            CopyFields(dst, src, COPY_INDICATOR_FIELDS)
            CopyFields(dst, src, COPY_STATUSICON_FIELDS)
        end
        if scopes.castbar then
            dst.showInterrupt = src.showInterrupt
            CopyCastbar(g, srcKey, dstKey)
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
        })
    end

    local function FinishCopy()
        if scopes.castbar then Call("MSUF_UpdateCastbarVisuals") end
        if scopes.status then
            Call("MSUF_RefreshAllIndicators")
            Call("MSUF_RefreshStatusIndicators")
        end
        if scopes.transparency then Call("MSUF_RefreshAllUnitAlphas") end
        Call("MSUF_UFPreview_RequestRefresh", "COPY_UNIT_SETTINGS")
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
    FinishCopy()
end

local function ToggleEditMode(unit)
    if type(_G.MSUF_BlockConfigCombatLocked) == "function" and _G.MSUF_BlockConfigCombatLocked() then return end
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
        return
    end
    local active = (_G.MSUF_IsMSUFEditModeActive and _G.MSUF_IsMSUFEditModeActive()) or _G.MSUF_UnitEditModeActive
    if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
        _G.MSUF_SetMSUFEditModeDirect(not active, CanonUnitKey(unit))
    end
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
    if type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
        pcall(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit)
    end
end

local function EnsureBossPagePreviewEvents()
    if bossPagePreviewEvents then return bossPagePreviewEvents end
    bossPagePreviewEvents = CreateFrame("Frame")
    bossPagePreviewEvents:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" and bossPagePreviewPendingCleanup then
            bossPagePreviewPendingCleanup = nil
            SyncBossPagePreview()
            if _G.MSUF2_BossUnitframePreviewActive ~= true then
                self:UnregisterAllEvents()
            end
            return
        end
        if _G.MSUF2_BossUnitframePreviewActive == true then
            SyncBossPagePreview()
        end
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
        if active and not BossPagePreviewInCombat() then SyncBossPagePreview() end
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
    if active and C_Timer and C_Timer.After then
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
    if math.abs(value - floor(value + 0.5)) < 0.001 then
        value = floor(value + 0.5)
    end
    M.SetUnitValue(unit, key, value, reason, opts)
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
    if value < 1 then return 1 end
    if value > 10 then return 10 end
    return value
end

local function StatusAllowed(unit, spec)
    return spec and (not spec.allowed or spec.allowed(unit))
end

local function StatusValues(unit)
    local values = {}
    for i = 1, #STATUS_CONTROLS do
        local spec = STATUS_CONTROLS[i]
        if StatusAllowed(unit, spec) then
            values[#values + 1] = { value = spec.value, text = spec.text }
        end
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

local function ReadStatusNumber(unit, key, default)
    local conf = GetConf(unit)
    local g = GetGeneral()
    local value = tonumber(conf[key])
    if value == nil then value = tonumber(g[key]) end
    if value == nil then value = default or 0 end
    return value
end

local function ReadStatusString(unit, key, default)
    local conf = GetConf(unit)
    local g = GetGeneral()
    local value = conf[key]
    if type(value) ~= "string" or value == "" then value = g[key] end
    if type(value) ~= "string" or value == "" then value = default end
    return value or ""
end

local function RefreshStatusRuntime(unit, spec)
    if spec and spec.refresh then Call(spec.refresh) end
    if spec and spec.statusRuntime then
        Call("MSUF_RefreshStatusIndicators")
        Call("MSUF_RequestStatusIconsRefreshForCurrent")
    end
    if spec and spec.value == "level" then
        Call("MSUF_UpdateAllFonts_Immediate")
        Call("MSUF_UpdateAllFonts")
        if unit == "boss" and _G.MSUF_BossTestMode and type(_G.MSUF_ApplyBossUnitframePreviewState) == "function" then
            _G.MSUF_ApplyBossUnitframePreviewState(true, "MSUF2_LEVEL_INDICATOR")
        end
    end
    M.RequestUnitApply(unit, "MSUF2_STATUS_INDICATOR", { preview = true, text = true })
end

local SetControlEnabled = W.SetControlEnabled

local function SeedText(unit)
    local conf = GetConf(unit)
    if type(_G.MSUF_Bars_SeedTextFromGeneral) == "function" then
        pcall(_G.MSUF_Bars_SeedTextFromGeneral, conf)
    end
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
for key, value in pairs({
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
    NewCopyScopeDefaults = NewCopyScopeDefaults,
    CopyUnitSettings = CopyUnitSettings,
    ToggleEditMode = ToggleEditMode,
    IsEditModeActive = IsEditModeActive,
    SetBossPagePreviewActive = SetBossPagePreviewActive,
    ReadBool = ReadBool,
    SetBool = SetBool,
    ReadNumber = ReadNumber,
    SetNumber = SetNumber,
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
}) do
    UnitPage[key] = value
end
UnitPage.SeedText = SeedText
UnitPage.ReadText = ReadText
UnitPage.SetText = SetText
UnitPage.NormalizePortrait = NormalizePortrait
UnitPage.SetPortraitValue = SetPortraitValue
UnitPage.NormalizeBossLayoutMode = NormalizeBossLayoutMode
UnitPage.UpdateLoadActive = UpdateLoadActive
