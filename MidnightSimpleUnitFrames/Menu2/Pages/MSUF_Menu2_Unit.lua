local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme

local floor = math.floor

local UNIT_PAGES = {
    uf_player = { unit = "player", title = "MSUF Player", label = "Player" },
    uf_target = { unit = "target", title = "MSUF Target", label = "Target" },
    uf_targettarget = { unit = "targettarget", title = "MSUF Target of Target", label = "Target of Target" },
    uf_focus = { unit = "focus", title = "MSUF Focus", label = "Focus" },
    uf_pet = { unit = "pet", title = "MSUF Pet", label = "Pet" },
    uf_boss = { unit = "boss", title = "MSUF Boss Frames", label = "Boss" },
}

local POWER_UNITS = {
    player = true,
    target = true,
    focus = true,
    boss = true,
}

local CASTBAR_FIELDS = {
    player = { enable = "enablePlayerCastbar", time = "showPlayerCastTime", icon = "castbarPlayerShowIcon", text = "castbarPlayerShowSpellName" },
    target = { enable = "enableTargetCastbar", time = "showTargetCastTime", icon = "castbarTargetShowIcon", text = "castbarTargetShowSpellName" },
    focus = { enable = "enableFocusCastbar", time = "showFocusCastTime", icon = "castbarFocusShowIcon", text = "castbarFocusShowSpellName" },
    boss = { enable = "enableBossCastbar", time = "showBossCastTime", icon = "showBossCastIcon", text = "showBossCastName" },
}

local LOAD_CONDITIONS = {
    { key = "loadCondHideMounted", label = "Mounted" },
    { key = "loadCondHideOutOfCombat", label = "Out of combat" },
    { key = "loadCondHideSolo", label = "Solo" },
    { key = "loadCondHideInVehicle", label = "In vehicle" },
    { key = "loadCondHideInGroup", label = "In group" },
    { key = "loadCondHideInInstance", label = "In instance" },
    { key = "loadCondHideResting", label = "Resting" },
    { key = "loadCondHideInCombat", label = "In combat" },
    { key = "loadCondHideStealthed", label = "Stealthed" },
}

local STATUS_ANCHORS = {
    { value = "TOPLEFT", text = "Top Left" },
    { value = "TOPRIGHT", text = "Top Right" },
    { value = "BOTTOMLEFT", text = "Bottom Left" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
    { value = "CENTER", text = "Center" },
    { value = "TOP", text = "Top" },
    { value = "BOTTOM", text = "Bottom" },
    { value = "LEFT", text = "Left" },
    { value = "RIGHT", text = "Right" },
}

local STATUS_CORNER_ANCHORS = {
    { value = "TOPLEFT", text = "Top Left" },
    { value = "TOPRIGHT", text = "Top Right" },
    { value = "BOTTOMLEFT", text = "Bottom Left" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
    { value = "CENTER", text = "Center" },
}

local STATUS_LEVEL_ANCHORS = {
    { value = "NAMERIGHT", text = "Right to player name" },
    { value = "NAMELEFT", text = "Left to player name" },
    { value = "TOPLEFT", text = "Top Left" },
    { value = "TOPRIGHT", text = "Top Right" },
    { value = "BOTTOMLEFT", text = "Bottom Left" },
    { value = "BOTTOMRIGHT", text = "Bottom Right" },
}

local COMBAT_SYMBOLS = {
    { value = "DEFAULT", text = "Default" },
    { value = "weapon_axes_crossed", text = "Axes" },
    { value = "weapon_bows_crossed", text = "Bows" },
    { value = "weapon_crossbows_crossed", text = "Crossbows" },
    { value = "weapon_daggers_crossed", text = "Daggers" },
    { value = "weapon_fishing_poles_crossed", text = "Fishing" },
    { value = "weapon_fist_crossed", text = "Fist" },
    { value = "weapon_guns_crossed", text = "Guns" },
    { value = "weapon_maces_crossed", text = "Maces" },
    { value = "weapon_polearms_crossed", text = "Polearms" },
    { value = "weapon_shuriken", text = "Shuriken" },
    { value = "weapon_staves_crossed", text = "Staves" },
    { value = "weapon_swords_crossed", text = "Swords" },
    { value = "weapon_thrown_crossed", text = "Thorn" },
    { value = "weapon_wands_crossed", text = "Wands" },
    { value = "weapon_warglaives_crossed", text = "Warglaives" },
}

local RESTED_SYMBOLS = {
    { value = "DEFAULT", text = "Default" },
    { value = "rested_moonzzz", text = "Moon (3 z)" },
    { value = "rested_moonzzzz", text = "Moon (4 z)" },
    { value = "rested_zzz_compact", text = "Compact Zzz" },
    { value = "rested_zzz_diag", text = "Diagonal Zzz" },
    { value = "rested_zzz_stack", text = "Stacked Zzz" },
}

local RESS_SYMBOLS = {
    { value = "DEFAULT", text = "Default" },
    { value = "resurrection_ankh", text = "Ankh" },
    { value = "resurrection_cross", text = "Cross" },
    { value = "resurrection_soul", text = "Soul" },
    { value = "resurrection_wings", text = "Angelic Wings" },
}

local DEFAULT_SYMBOLS = {
    { value = "DEFAULT", text = "Default" },
}

local STATUS_CONTROLS = {
    {
        value = "leader", text = "Leader / Assist",
        allowed = function(unit) return unit == "player" or unit == "target" end,
        show = "showLeaderIcon", defaultShow = true,
        size = "leaderIconSize", defaultSize = 14,
        anchor = "leaderIconAnchor", defaultAnchor = "TOPLEFT", anchors = STATUS_CORNER_ANCHORS,
        x = "leaderIconOffsetX", defaultX = 0,
        y = "leaderIconOffsetY", defaultY = 3,
        layer = "leaderIconLayer", defaultLayer = 7,
        refresh = "MSUF_RefreshLeaderIconFrames",
    },
    {
        value = "raidmarker", text = "Raid Marker",
        show = "showRaidMarker", defaultShow = true,
        size = "raidMarkerSize", defaultSize = 18,
        anchor = "raidMarkerAnchor", defaultAnchor = "TOPLEFT", anchors = STATUS_CORNER_ANCHORS,
        x = "raidMarkerOffsetX", defaultX = 16,
        y = "raidMarkerOffsetY", defaultY = 3,
        layer = "raidMarkerLayer", defaultLayer = 7,
        refresh = "MSUF_RefreshRaidMarkerFrames",
    },
    {
        value = "level", text = "Level",
        show = "showLevelIndicator", defaultShow = true,
        size = "levelIndicatorSize", defaultSize = 14,
        anchor = "levelIndicatorAnchor", defaultAnchor = "NAMERIGHT", anchors = STATUS_LEVEL_ANCHORS,
        x = "levelIndicatorOffsetX", defaultX = 0,
        y = "levelIndicatorOffsetY", defaultY = 0,
        layer = "levelIndicatorLayer", defaultLayer = 7,
        refresh = "MSUF_RefreshLevelIndicatorFrames",
    },
    {
        value = "eliteicon", text = "Elite / Rare",
        allowed = function(unit) return unit == "target" or unit == "focus" or unit == "targettarget" or unit == "boss" end,
        show = "showEliteIcon", defaultShow = true,
        size = "eliteIconSize", defaultSize = 20,
        anchor = "eliteIconAnchor", defaultAnchor = "TOPRIGHT", anchors = STATUS_CORNER_ANCHORS,
        x = "eliteIconOffsetX", defaultX = 2,
        y = "eliteIconOffsetY", defaultY = 2,
        layer = "eliteIconLayer", defaultLayer = 7,
        refresh = "MSUF_RefreshEliteIconFrames",
    },
    {
        value = "statusText", text = "Dead Text",
        show = "statusTextEnabled", defaultShow = true,
        size = "statusTextSize", defaultSize = 16,
        anchor = "statusTextAnchor", defaultAnchor = "CENTER", anchors = STATUS_CORNER_ANCHORS,
        x = "statusTextOffsetX", defaultX = 0,
        y = "statusTextOffsetY", defaultY = 0,
        layer = "statusTextLayer", defaultLayer = 7,
        refresh = "MSUF_RequestStatusTextRefresh",
        statusRuntime = true,
    },
    {
        value = "statusCombat", text = "Combat",
        allowed = function(unit) return unit == "player" or unit == "target" end,
        show = "showCombatStateIndicator", defaultShow = true,
        size = "combatStateIndicatorSize", defaultSize = 18,
        anchor = "combatStateIndicatorAnchor", defaultAnchor = "TOPLEFT", anchors = STATUS_CORNER_ANCHORS,
        x = "combatStateIndicatorOffsetX", defaultX = 0,
        y = "combatStateIndicatorOffsetY", defaultY = 0,
        layer = "combatStateIndicatorLayer", defaultLayer = 7,
        symbol = "combatStateIndicatorSymbol", symbols = COMBAT_SYMBOLS,
        refresh = "MSUF_RequestStatusCombatIndicatorRefresh",
        statusRuntime = true,
    },
    {
        value = "statusResting", text = "Rested (player only)",
        allowed = function(unit) return unit == "player" end,
        show = "showRestingIndicator", defaultShow = false,
        size = "restedStateIndicatorSize", defaultSize = 18,
        anchor = "restedStateIndicatorAnchor", defaultAnchor = "TOPLEFT", anchors = STATUS_CORNER_ANCHORS,
        x = "restedStateIndicatorOffsetX", defaultX = 0,
        y = "restedStateIndicatorOffsetY", defaultY = 0,
        layer = "restedStateIndicatorLayer", defaultLayer = 7,
        symbol = "restedStateIndicatorSymbol", symbols = RESTED_SYMBOLS,
        refresh = "MSUF_RequestStatusRestingIndicatorRefresh",
        statusRuntime = true,
    },
    {
        value = "statusIncomingRes", text = "Incoming Rez",
        allowed = function(unit) return unit == "player" or unit == "target" end,
        show = "showIncomingResIndicator", defaultShow = true,
        size = "incomingResIndicatorSize", defaultSize = 18,
        anchor = "incomingResIndicatorAnchor", defaultAnchor = "TOPRIGHT", anchors = STATUS_CORNER_ANCHORS,
        x = "incomingResIndicatorOffsetX", defaultX = 0,
        y = "incomingResIndicatorOffsetY", defaultY = 0,
        layer = "incomingResIndicatorLayer", defaultLayer = 7,
        symbol = "incomingResIndicatorSymbol", symbols = RESS_SYMBOLS,
        refresh = "MSUF_RequestStatusIncomingResIndicatorRefresh",
        statusRuntime = true,
    },
}

local TEXT_ANCHORS = {
    { value = "LEFT", text = "Left" },
    { value = "CENTER", text = "Center" },
    { value = "RIGHT", text = "Right" },
}

local HP_MODES = {
    { value = "PERCENT", text = "Percent" },
    { value = "CURRENT", text = "Current" },
    { value = "MAX", text = "Max" },
    { value = "DEFICIT", text = "Deficit" },
    { value = "CURMAX", text = "Current / Max" },
    { value = "CURPERCENT", text = "Current / Percent" },
    { value = "CURMAXPERCENT", text = "Current / Max / Percent" },
    { value = "MAXPERCENT", text = "Max / Percent" },
    { value = "PERCENTCUR", text = "Percent / Current" },
    { value = "PERCENTMAX", text = "Percent / Max" },
    { value = "PERCENTCURMAX", text = "Percent / Current / Max" },
    { value = "NONE", text = "None" },
}

local POWER_MODES = {
    { value = "CURRENT", text = "Current" },
    { value = "MAX", text = "Max" },
    { value = "CURMAX", text = "Current / Max" },
    { value = "PERCENT", text = "Percent" },
    { value = "CURPERCENT", text = "Current / Percent" },
    { value = "CURMAXPERCENT", text = "Current / Max / Percent" },
    { value = "NONE", text = "None" },
}

local BOSS_LAYOUT_OPTIONS = {
    { value = "VERTICAL_DOWN", text = "Vertical (top -> bottom)" },
    { value = "VERTICAL_UP", text = "Vertical (bottom -> top)" },
    { value = "HORIZONTAL_RIGHT", text = "Horizontal (left -> right)" },
    { value = "HORIZONTAL_LEFT", text = "Horizontal (right -> left)" },
}

local BOSS_LAYOUT_VALID = {
    VERTICAL_DOWN = true,
    VERTICAL_UP = true,
    HORIZONTAL_RIGHT = true,
    HORIZONTAL_LEFT = true,
}

local SEPARATORS = {
    { value = "", text = "space" },
    { value = "-", text = "-" },
    { value = "/", text = "/" },
    { value = "\\", text = "\\" },
    { value = "|", text = "|" },
    { value = "<", text = "<" },
    { value = ">", text = ">" },
    { value = "~", text = "~" },
    { value = ":", text = ":" },
}

local PORTRAIT_RENDER = {
    { value = "2D", text = "2D portrait" },
    { value = "CLASS", text = "Class portrait" },
}

local PORTRAIT_SHAPES = {
    { value = "SQUARE", text = "Square" },
    { value = "CIRCLE", text = "Circle" },
    { value = "ROUNDED", text = "Rounded" },
    { value = "DIAMOND", text = "Diamond" },
}

local PORTRAIT_BORDERS = {
    { value = "NONE", text = "No border" },
    { value = "SOLID", text = "Solid" },
    { value = "CLASS_COLOR", text = "Class color" },
    { value = "REACTION", text = "Reaction color" },
    { value = "CUSTOM", text = "Custom color" },
}

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
    local dst = {}
    for k, v in pairs(src) do dst[k] = DeepCopy(v) end
    return dst
end

local UNIT_COPY_TARGETS = {
    { value = "player", text = "Player" },
    { value = "target", text = "Target" },
    { value = "targettarget", text = "Target of Target" },
    { value = "focus", text = "Focus" },
    { value = "pet", text = "Pet" },
    { value = "boss", text = "Boss Frames" },
}

local function DefaultCopyTarget(unit)
    for i = 1, #UNIT_COPY_TARGETS do
        local value = UNIT_COPY_TARGETS[i].value
        if value ~= unit then return value end
    end
    return "target"
end

local function UnitTopLabel(unit)
    return ({
        player = "Player",
        target = "Target",
        targettarget = "Target of Target",
        focus = "Focus",
        boss = "Boss Frames",
        pet = "Pet",
    })[unit] or tostring(unit or "")
end

local function UnitTopPillWidth(unit)
    if unit == "targettarget" then return 116 end
    if unit == "boss" then return 92 end
    if unit == "target" then return 62 end
    if unit == "focus" then return 58 end
    if unit == "pet" then return 46 end
    return 56
end

local function CopyUnitSettings(unit, target)
    if target == "all" then
        for i = 1, #UNIT_COPY_TARGETS do
            local value = UNIT_COPY_TARGETS[i].value
            if value ~= unit then CopyUnitSettings(unit, value) end
        end
        return
    end
    if not target or target == unit then return end
    local sourceConf = GetConf(unit)
    local targetConf = GetConf(target)
    for k in pairs(targetConf) do targetConf[k] = nil end
    local copyConf = DeepCopy(sourceConf)
    for k, v in pairs(copyConf) do targetConf[k] = v end
    M.RequestUnitApply(target, "MSUF2_COPY_UNIT", { preview = true, text = true, power = true, alpha = true, castbar = true })
end

local function ToggleEditMode()
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end
    local active = (_G.MSUF_IsMSUFEditModeActive and _G.MSUF_IsMSUFEditModeActive()) or _G.MSUF_UnitEditModeActive
    if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
        _G.MSUF_SetMSUFEditModeDirect(not active)
    end
end

local function IsEditModeActive()
    return ((_G.MSUF_IsMSUFEditModeActive and _G.MSUF_IsMSUFEditModeActive()) or _G.MSUF_UnitEditModeActive) and true or false
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

local function ReadString(unit, key, default)
    local conf = GetConf(unit)
    local value = conf[key]
    if type(value) ~= "string" or value == "" then value = default end
    return value or ""
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
    end
    M.RequestUnitApply(unit, "MSUF2_STATUS_INDICATOR", { preview = true, text = true })
end

local function SetControlEnabled(control, enabled)
    W.SetControlEnabled(control, enabled)
end

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
    if M.SetUnitValue(unit, key, value, reason or "MSUF2_PORTRAIT", { preview = true }) then
        Call("MSUF_Portraits_SyncUnit", unit)
        Call("MSUF_PortraitDecoration_SyncUnit", unit)
        Call("MSUF_PortraitDecoration_RefreshAll")
    end
end

local function NormalizeAlphaMode(value)
    if value == 1 or value == "background" then return "background" end
    if value == 2 or value == "health" then return "health" end
    return "foreground"
end

local function AlphaModeValue(mode)
    if mode == "background" then return 1 end
    if mode == "health" then return 2 end
    return 0
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
UnitPage.UNIT_PAGES = UNIT_PAGES
UnitPage.POWER_UNITS = POWER_UNITS
UnitPage.CASTBAR_FIELDS = CASTBAR_FIELDS
UnitPage.LOAD_CONDITIONS = LOAD_CONDITIONS
UnitPage.STATUS_ANCHORS = STATUS_ANCHORS
UnitPage.STATUS_CORNER_ANCHORS = STATUS_CORNER_ANCHORS
UnitPage.STATUS_LEVEL_ANCHORS = STATUS_LEVEL_ANCHORS
UnitPage.COMBAT_SYMBOLS = COMBAT_SYMBOLS
UnitPage.RESTED_SYMBOLS = RESTED_SYMBOLS
UnitPage.RESS_SYMBOLS = RESS_SYMBOLS
UnitPage.DEFAULT_SYMBOLS = DEFAULT_SYMBOLS
UnitPage.STATUS_CONTROLS = STATUS_CONTROLS
UnitPage.TEXT_ANCHORS = TEXT_ANCHORS
UnitPage.HP_MODES = HP_MODES
UnitPage.POWER_MODES = POWER_MODES
UnitPage.BOSS_LAYOUT_OPTIONS = BOSS_LAYOUT_OPTIONS
UnitPage.BOSS_LAYOUT_VALID = BOSS_LAYOUT_VALID
UnitPage.SEPARATORS = SEPARATORS
UnitPage.PORTRAIT_RENDER = PORTRAIT_RENDER
UnitPage.PORTRAIT_SHAPES = PORTRAIT_SHAPES
UnitPage.PORTRAIT_BORDERS = PORTRAIT_BORDERS
UnitPage.UNIT_COPY_TARGETS = UNIT_COPY_TARGETS
UnitPage.GetConf = GetConf
UnitPage.GetGeneral = GetGeneral
UnitPage.GetBars = GetBars
UnitPage.Call = Call
UnitPage.DeepCopy = DeepCopy
UnitPage.DefaultCopyTarget = DefaultCopyTarget
UnitPage.UnitTopLabel = UnitTopLabel
UnitPage.UnitTopPillWidth = UnitTopPillWidth
UnitPage.CopyUnitSettings = CopyUnitSettings
UnitPage.ToggleEditMode = ToggleEditMode
UnitPage.IsEditModeActive = IsEditModeActive
UnitPage.ReadBool = ReadBool
UnitPage.SetBool = SetBool
UnitPage.ReadNumber = ReadNumber
UnitPage.SetNumber = SetNumber
UnitPage.ReadString = ReadString
UnitPage.SetString = SetString
UnitPage.ReadGeneralBool = ReadGeneralBool
UnitPage.SetGeneralBool = SetGeneralBool
UnitPage.ClampStatusLayer = ClampStatusLayer
UnitPage.StatusAllowed = StatusAllowed
UnitPage.StatusValues = StatusValues
UnitPage.FindStatusSpec = FindStatusSpec
UnitPage.CurrentStatusSpec = CurrentStatusSpec
UnitPage.ReadStatusBool = ReadStatusBool
UnitPage.ReadStatusNumber = ReadStatusNumber
UnitPage.ReadStatusString = ReadStatusString
UnitPage.RefreshStatusRuntime = RefreshStatusRuntime
UnitPage.SetControlEnabled = SetControlEnabled
UnitPage.SeedText = SeedText
UnitPage.ReadText = ReadText
UnitPage.SetText = SetText
UnitPage.NormalizePortrait = NormalizePortrait
UnitPage.SetPortraitValue = SetPortraitValue
UnitPage.NormalizeAlphaMode = NormalizeAlphaMode
UnitPage.AlphaModeValue = AlphaModeValue
UnitPage.NormalizeBossLayoutMode = NormalizeBossLayoutMode
UnitPage.UpdateLoadActive = UpdateLoadActive