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
    if not control then return end
    enabled = enabled and true or false
    if control.EnableMouse then control:EnableMouse(enabled) end
    if control.SetEnabled then control:SetEnabled(enabled) end
    if control.SetAlpha then control:SetAlpha(enabled and 1 or 0.45) end
    if control._msuf2Title and control._msuf2Title.SetTextColor then
        local c = enabled and T.colors.text or T.colors.dim
        control._msuf2Title:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
    if control.editBox then
        if control.editBox.EnableMouse then control.editBox:EnableMouse(enabled) end
        if control.editBox.SetAlpha then control.editBox:SetAlpha(enabled and 1 or 0.45) end
    end
    if control._msuf2StepButtons then
        for i = 1, #control._msuf2StepButtons do
            local btn = control._msuf2StepButtons[i]
            if btn.SetEnabled then btn:SetEnabled(enabled) end
            if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.45) end
        end
    end
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

local function BuildPreview(ctx, builder, unit)
    local sec = builder:CollapsibleSection("preview", "Hide Preview", 352, true)
    if not ns.MSUF_Options_CreateUnitPreviewBox then
        W.Text(sec, "The shared unit preview module is not loaded.", 14, -42, ctx.width - 28, T.colors.muted)
        return
    end

    local panel = CreateFrame("Frame", nil, sec)
    panel._msufLastApplyKey = unit
    panel._msufGetCurrentKey = function() return unit end
    panel._msufIsFramesTab = function() return true end
    panel._msufAPI = {
        ApplySettingsForKey = function(key)
            key = key or unit
            if type(_G.ApplySettingsForKey) == "function" then
                _G.ApplySettingsForKey(key)
            else
                Call("MSUF_ApplySettingsForKey_Immediate", key)
            end
        end,
    }
    panel._msufOpenUnitSection = function() end

    local box = ns.MSUF_Options_CreateUnitPreviewBox(sec, panel, ctx.width - 28, 300)
    box:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, -38)
    box:Show()
    panel.unitPreviewBox = box

    local function RefreshThisPreview(reason)
        panel._msufLastApplyKey = unit
        local preview = ns.UFPreview
        if type(preview) == "table" then
            preview.active = box
            if type(preview.Refresh) == "function" and box:IsShown() then
                preview.Refresh(box, reason or "MSUF2_UNIT_PAGE")
                return
            end
            if type(preview.RequestRefresh) == "function" then
                preview.RequestRefresh(reason or "MSUF2_UNIT_PAGE")
                return
            end
        end
        Call("MSUF_UFPreview_RequestRefresh", reason or "MSUF2_UNIT_PAGE")
    end

    if box.HookScript then
        box:HookScript("OnShow", function()
            RefreshThisPreview("MSUF2_UNIT_PAGE_SHOW")
        end)
    end
    RefreshThisPreview("MSUF2_UNIT_PAGE_BUILD")
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if box and box:IsShown() then RefreshThisPreview("MSUF2_UNIT_PAGE_DEFERRED") end
        end)
    end

    M.AddRefresher(ctx, function()
        if box:IsShown() then RefreshThisPreview("MSUF2_UNIT_PAGE") end
    end)
end

local function BuildTopActions(ctx, builder, unit, label)
    local sec = CreateFrame("Frame", nil, builder.parent)
    sec:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", builder.x, builder.y)
    sec:SetSize(builder.width, 30)
    builder.y = builder.y - 38
    if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(builder.y) + 28) end

    local line = sec:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", sec, "BOTTOMLEFT", 4, 1)
    line:SetPoint("BOTTOMRIGHT", sec, "BOTTOMRIGHT", -4, 1)
    line:SetHeight(1)
    line:SetColorTexture(0.22, 0.42, 0.70, 0.42)

    local function ApplyTopButtonVisual(btn, hover)
        local c = T.colors
        local bg = btn._msuf2TopActive and c.pillActive or (hover and c.pillHover or c.pillBaseSolid)
        local br = btn._msuf2TopActive and c.pillEdgeActive or (hover and c.pillEdgeHover or c.pillEdgeButton)
        local tx = btn._msuf2TopActive and c.pillTextActive or c.pillText
        local mul = hover and 1.06 or 1
        if btn._msuf2Fill then btn._msuf2Fill:SetVertexColor(math.min(bg[1] * mul, 1), math.min(bg[2] * mul, 1), math.min(bg[3] * mul, 1), bg[4] or 1) end
        if btn._msuf2Edge then btn._msuf2Edge:SetVertexColor(math.min(br[1] * mul, 1), math.min(br[2] * mul, 1), math.min(br[3] * mul, 1), br[4] or 1) end
        if btn._msuf2Label then btn._msuf2Label:SetTextColor(tx[1], tx[2], tx[3], tx[4] or 1) end
    end

    local function MakeTopButton(parent, text, width, active)
        local btn = T.Button(parent, text, width, 24)
        btn._msuf2TopActive = active and true or false
        if btn._msuf2Label then
            btn._msuf2Label:ClearAllPoints()
            btn._msuf2Label:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn._msuf2Label:SetJustifyH("CENTER")
            if btn._msuf2Label.SetShadowColor then btn._msuf2Label:SetShadowColor(0, 0, 0, 0.55) end
            if btn._msuf2Label.SetShadowOffset then btn._msuf2Label:SetShadowOffset(1, -1) end
        end
        btn.SetActive = function(self, nextActive)
            self._msuf2TopActive = nextActive and true or false
            ApplyTopButtonVisual(self)
        end
        btn:SetScript("OnEnter", function(self) ApplyTopButtonVisual(self, true) end)
        btn:SetScript("OnLeave", function(self) ApplyTopButtonVisual(self) end)
        ApplyTopButtonVisual(btn)
        return btn
    end

    local editing = T.Font(sec, "GameFontNormalSmall", "Editing:", { 0.72, 0.82, 1.00, 1 })
    editing:SetPoint("LEFT", sec, "LEFT", 8, 2)

    local unitPill = MakeTopButton(sec, UnitTopLabel(unit), UnitTopPillWidth(unit), true)
    unitPill:SetPoint("LEFT", editing, "RIGHT", 8, 2)
    unitPill:EnableMouse(false)

    local copy = MakeTopButton(sec, "Copy To", 86, false)
    copy:SetPoint("RIGHT", sec, "RIGHT", -8, 2)

    local edit = MakeTopButton(sec, "MSUF Edit Mode", 128, false)
    edit:SetPoint("RIGHT", copy, "LEFT", -8, 0)

    local function RefreshEditButton()
        local active = IsEditModeActive()
        edit:SetText(active and "Exit Edit Mode" or "MSUF Edit Mode")
        edit:SetActive(active)
    end

    edit:SetScript("OnClick", function()
        ToggleEditMode()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, RefreshEditButton)
        else
            RefreshEditButton()
        end
    end)
    M.AddRefresher(ctx, RefreshEditButton)
    RefreshEditButton()

    copy:SetScript("OnClick", function()
        if W.OpenDropdownList then
            local items = {}
            for i = 1, #UNIT_COPY_TARGETS do
                local item = UNIT_COPY_TARGETS[i]
                if item.value ~= unit then items[#items + 1] = item end
            end
            items[#items + 1] = { value = "all", text = "All unit frames" }
            W.OpenDropdownList(copy, items, function(value)
                M.unitCopyTarget = value
                CopyUnitSettings(unit, value)
            end, M.unitCopyTarget or DefaultCopyTarget(unit))
            return
        end

        local target = M.unitCopyTarget or DefaultCopyTarget(unit)
        if target == unit then target = DefaultCopyTarget(unit) end
        CopyUnitSettings(unit, target)
    end)
end

local function BuildBasics(ctx, builder, unit, label)
    local sec = builder:CollapsibleSection("frame_basics", "Frame Basics", 116, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local gap = 24
    local colW = math.floor((sectionW - 28 - (gap * 2)) / 3)
    if colW < 136 then colW = 136 end
    local x1 = 14
    local x2 = x1 + colW + gap
    local x3 = x2 + colW + gap
    local labelW = math.max(104, colW - 34)
    local row1 = -42
    local row2 = -74

    local enabled = W.ToggleAt(sec, "Enable frame", x1, row1, labelW)
    M.BindToggle(ctx, enabled,
        function() return ReadBool(unit, "enabled", true) end,
        function(v) SetBool(unit, "enabled", v, "MSUF2_ENABLED", { preview = true }) end)

    local showName = W.ToggleAt(sec, "Show name", x2, row1, labelW)
    M.BindToggle(ctx, showName,
        function() return ReadBool(unit, "showName", true) end,
        function(v) SetBool(unit, "showName", v, "MSUF2_SHOW_NAME", { text = true, preview = true }) end)

    local showHP = W.ToggleAt(sec, "Show health text", x3, row1, labelW)
    M.BindToggle(ctx, showHP,
        function() return ReadBool(unit, "showHP", true) end,
        function(v) SetBool(unit, "showHP", v, "MSUF2_SHOW_HP", { text = true, preview = true }) end)

    local showPower = W.ToggleAt(sec, "Show power text", x1, row2, labelW)
    M.BindToggle(ctx, showPower,
        function() return ReadBool(unit, "showPower", unit ~= "pet" and unit ~= "targettarget") end,
        function(v) SetBool(unit, "showPower", v, "MSUF2_SHOW_POWER", { text = true, preview = true }) end)

    local reverse = W.ToggleAt(sec, "Reverse fill direction", x2, row2, labelW)
    M.BindToggle(ctx, reverse,
        function() return ReadBool(unit, "reverseFillBars", false) end,
        function(v) SetBool(unit, "reverseFillBars", v, "MSUF2_REVERSE_FILL", { preview = true }) end)

    local smooth = W.ToggleAt(sec, "Smooth fill", x3, row2, labelW)
    M.BindToggle(ctx, smooth,
        function() return ReadBool(unit, "smoothFill", true) end,
        function(v) SetBool(unit, "smoothFill", v, "MSUF2_SMOOTH_FILL", { preview = true }) end)
end

local function BuildLayout(ctx, builder, unit)
    local sec = builder:CollapsibleSection("anchoring", "Anchoring", 128, false)
    local anchorChoices = {
        { value = "GLOBAL", text = "Global anchor" },
        { value = "player", text = "Player frame" },
        { value = "target", text = "Target frame" },
        { value = "targettarget", text = "Target of Target frame" },
        { value = "focus", text = "Focus frame" },
        { value = "pet", text = "Pet frame" },
    }
    local function AnchorValues()
        local values = {}
        local conf = GetConf(unit)
        local custom = (type(conf.anchorFrameName) == "string" and conf.anchorFrameName) or ""
        if custom ~= "" then
            local text = custom
            if #text > 24 then text = text:sub(1, 21) .. "..." end
            values[#values + 1] = { value = "__CUSTOM", text = "Custom: " .. text }
        end
        for i = 1, #anchorChoices do
            local item = anchorChoices[i]
            if item.value == "GLOBAL" or item.value ~= unit then
                values[#values + 1] = item
            end
        end
        return values
    end
    local function AnchorValue()
        local conf = GetConf(unit)
        if type(conf.anchorFrameName) == "string" and conf.anchorFrameName ~= "" then return "__CUSTOM" end
        local v = conf.anchorToUnitframe
        if v == "player" or v == "target" or v == "targettarget" or v == "focus" or v == "pet" then return v end
        return "GLOBAL"
    end
    local function ApplyAnchorChange()
        M.RequestUnitApply(unit, "MSUF2_ANCHORING", { preview = true })
    end

    local anchorTo = W.Dropdown(sec, "Anchor unit to", AnchorValues, 180)
    anchorTo._msuf2Title:ClearAllPoints()
    anchorTo._msuf2Title:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, -12)
    anchorTo:ClearAllPoints()
    anchorTo:SetPoint("TOPLEFT", sec, "TOPLEFT", 110, -30)
    anchorTo:SetSize(180, 22)
    M.BindDropdown(ctx, anchorTo,
        AnchorValue,
        function(v)
            if v == "__CUSTOM" then return end
            local conf = GetConf(unit)
            conf.anchorToUnitframe = v or "GLOBAL"
            conf.anchorFrameName = nil
            ApplyAnchorChange()
        end)

    local customLabel = T.Font(sec, "GameFontNormalSmall", "Custom anchor target (mouse picker)", T.colors.text)
    customLabel:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, -62)

    local pick = T.Button(sec, "Pick frame (CTRL+Click)", 170, 22)
    pick:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, -88)
    pick:SetScript("OnClick", function()
        local ensure = _G.MSUF_EnsureAnchorPicker
        local overlay = type(ensure) == "function" and ensure()
        if not overlay then return end
        overlay._onPick = function(frameName)
            local conf = GetConf(unit)
            conf.anchorFrameName = frameName
            conf.anchorToUnitframe = "GLOBAL"
            ApplyAnchorChange()
            if M.InvalidatePage then M.InvalidatePage(ctx.key) end
            if M.SelectPage then M.SelectPage(ctx.key) end
        end
        overlay:Show()
    end)

    local clear = T.Button(sec, "Clear", 58, 22)
    clear:SetPoint("LEFT", pick, "RIGHT", 8, 0)
    clear:SetScript("OnClick", function()
        local conf = GetConf(unit)
        conf.anchorFrameName = nil
        ApplyAnchorChange()
        if M.InvalidatePage then M.InvalidatePage(ctx.key) end
        if M.SelectPage then M.SelectPage(ctx.key) end
    end)

    local current = T.Font(sec, "GameFontHighlightSmall", "", T.colors.text)
    current:SetPoint("LEFT", clear, "RIGHT", 14, 0)
    current:SetPoint("RIGHT", sec, "RIGHT", -14, 0)
    current:SetJustifyH("LEFT")

    M.AddRefresher(ctx, function()
        local conf = GetConf(unit)
        local custom = (type(conf.anchorFrameName) == "string" and conf.anchorFrameName) or ""
        current:SetText("Current custom anchor: " .. (custom ~= "" and custom or "none"))
        if anchorTo.SetValue then anchorTo:SetValue(AnchorValue()) end
    end)
end

local function BuildText(ctx, builder, unit)
    local sec = builder:CollapsibleSection("text", "Text", 1120, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 20
    local rightX = math.max(360, floor(sectionW * 0.50) + 4)
    local colW = math.max(260, sectionW - rightX - 20)
    local sliderW = math.min(300, math.max(220, colW - 82))
    local dropdownW = math.min(260, math.max(190, colW - 30))
    local smallDropdownW = math.min(160, math.max(110, colW - 140))
    local RefreshTextControlState

    W.Text(sec, "Font, outline and color are controlled globally in |cffffd200Global Style > Fonts|r.", 14, -38, sectionW - 190, T.colors.muted)
    W.Text(sec, "Tip: positions can also be dragged in |cffffd200Edit Mode|r - changes sync live both ways.", 14, -58, sectionW - 190, T.colors.dim)
    local scope = T.Font(sec, "GameFontDisableSmall", "Editing " .. UnitTopLabel(unit), T.colors.dim)
    scope:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -16, -38)
    scope:SetJustifyH("RIGHT")
    scope:SetWidth(170)
    sec._msuf2CursorY = -80

    local function PlaceToggle(control, x, y, labelWidth)
        if not control then return end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y)
        if control._msuf2Label and labelWidth then control._msuf2Label:SetWidth(labelWidth) end
    end

    local function PlaceDropdown(control, x, y, width)
        if not control then return end
        width = width or dropdownW
        if control._msuf2Title then
            control._msuf2Title:ClearAllPoints()
            control._msuf2Title:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y)
            control._msuf2Title:SetWidth(width)
        end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y - 22)
        control:SetSize(width, 22)
    end

    local function PlaceSlider(control, x, y, width)
        if not control then return end
        width = width or sliderW
        if control._msuf2Title then
            control._msuf2Title:ClearAllPoints()
            control._msuf2Title:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y)
            control._msuf2Title:SetWidth(width)
            control._msuf2Title:SetJustifyH("CENTER")
        end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y - 22)
        if control._msuf2SetLayoutWidth then
            control:_msuf2SetLayoutWidth(width)
        else
            control:SetSize(width, 16)
            if control._msuf2UpdateFill then control:_msuf2UpdateFill() end
        end
    end

    local function SectionLabel(text, x, y)
        local fs = T.Font(sec, "GameFontNormalSmall", text, T.colors.text)
        fs:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y)
        return fs
    end

    local function Divider(x, y, width)
        local line = sec:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.55)
        line:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y)
        line:SetSize(width or sliderW, 1)
        return line
    end

    SectionLabel("Name", leftX, -102)
    SectionLabel("Power Text", leftX, -412)
    SectionLabel("HP Text", rightX, -102)
    Divider(leftX, -386, sliderW + 88)
    Divider(rightX, -526, sliderW + 88)
    SectionLabel("Text Layers", rightX, -560)
    Divider(rightX, -790, sliderW + 88)
    SectionLabel("Text Spacing", rightX, -824)
    local spacingHint = W.Text(sec, "Optional split spacing for two-part HP or Power patterns.", rightX, -846, sliderW + 88, T.colors.dim)
    if spacingHint and spacingHint.SetWordWrap then spacingHint:SetWordWrap(true) end

    local showNameText = W.ToggleAt(sec, "Show Name", leftX, -128, colW - 60)
    M.BindToggle(ctx, showNameText,
        function() return ReadBool(unit, "showName", true) end,
        function(v)
            SetBool(unit, "showName", v, "MSUF2_SHOW_NAME_TEXT", { text = true, preview = true })
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    local showHPText = W.ToggleAt(sec, "Show HP Text", rightX, -128, colW - 60)
    M.BindToggle(ctx, showHPText,
        function() return ReadBool(unit, "showHP", true) end,
        function(v)
            SetBool(unit, "showHP", v, "MSUF2_SHOW_HP_TEXT", { text = true, preview = true })
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    local showPowerText = W.ToggleAt(sec, "Show Power Text", leftX, -438, colW - 60)
    M.BindToggle(ctx, showPowerText,
        function() return ReadBool(unit, "showPower", unit ~= "pet" and unit ~= "targettarget") end,
        function(v)
            SetBool(unit, "showPower", v, "MSUF2_SHOW_POWER_TEXT", { text = true, preview = true })
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    local nameAnchor = W.Dropdown(sec, "Name anchor", TEXT_ANCHORS, 210)
    PlaceDropdown(nameAnchor, leftX, -168, smallDropdownW)
    M.BindDropdown(ctx, nameAnchor,
        function() return ReadText(unit, "nameTextAnchor", "LEFT") end,
        function(v) SetText(unit, "nameTextAnchor", v or "LEFT", "MSUF2_NAME_ANCHOR") end)

    local nameSize = W.Slider(sec, "Name size", 6, 32, 1, 260)
    PlaceSlider(nameSize, leftX, -224, sliderW)
    M.BindSlider(ctx, nameSize,
        function() return ReadNumber(unit, "nameFontSize", 12) end,
        function(v) SetNumber(unit, "nameFontSize", v, "MSUF2_NAME_SIZE", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

    local nameX = W.Slider(sec, "Name X", -300, 300, 1, 260)
    PlaceSlider(nameX, leftX, -282, sliderW)
    M.BindSlider(ctx, nameX,
        function() return ReadNumber(unit, "nameOffsetX", 4) end,
        function(v) SetNumber(unit, "nameOffsetX", v, "MSUF2_NAME_X", { text = true, preview = true }) end)

    local nameY = W.Slider(sec, "Name Y", -300, 300, 1, 260)
    PlaceSlider(nameY, leftX, -340, sliderW)
    M.BindSlider(ctx, nameY,
        function() return ReadNumber(unit, "nameOffsetY", -4) end,
        function(v) SetNumber(unit, "nameOffsetY", v, "MSUF2_NAME_Y", { text = true, preview = true }) end)

    local hpMode = W.Dropdown(sec, "Health pattern", HP_MODES, 260)
    PlaceDropdown(hpMode, rightX, -168, dropdownW)
    M.BindDropdown(ctx, hpMode,
        function() return ReadText(unit, "hpTextMode", "CURPERCENT") end,
        function(v) SetText(unit, "hpTextMode", v or "CURPERCENT", "MSUF2_HP_MODE") end)

    local hpAnchor = W.Dropdown(sec, "Health anchor", TEXT_ANCHORS, 210)
    PlaceDropdown(hpAnchor, rightX, -220, smallDropdownW)
    M.BindDropdown(ctx, hpAnchor,
        function() return ReadText(unit, "hpTextAnchor", "RIGHT") end,
        function(v) SetText(unit, "hpTextAnchor", v or "RIGHT", "MSUF2_HP_ANCHOR") end)

    local hpSep = W.Dropdown(sec, "Health delimiter", SEPARATORS, 160)
    PlaceDropdown(hpSep, rightX, -272, smallDropdownW)
    M.BindDropdown(ctx, hpSep,
        function() return ReadText(unit, "hpTextSeparator", "") end,
        function(v) SetText(unit, "hpTextSeparator", v or "", "MSUF2_HP_SEPARATOR") end)

    local hpReverse = W.ToggleAt(sec, "Reverse HP text order", rightX, -326, colW - 60)
    M.BindToggle(ctx, hpReverse,
        function() return ReadText(unit, "hpTextReverse", false) == true end,
        function(v) SetText(unit, "hpTextReverse", v and true or false, "MSUF2_HP_REVERSE") end)

    local hpSize = W.Slider(sec, "Health text size", 6, 32, 1, 260)
    PlaceSlider(hpSize, rightX, -366, sliderW)
    M.BindSlider(ctx, hpSize,
        function() return ReadNumber(unit, "hpFontSize", 12) end,
        function(v) SetNumber(unit, "hpFontSize", v, "MSUF2_HP_SIZE", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

    local hpX = W.Slider(sec, "Health X", -300, 300, 1, 260)
    PlaceSlider(hpX, rightX, -424, sliderW)
    M.BindSlider(ctx, hpX,
        function() return ReadNumber(unit, "hpOffsetX", -4) end,
        function(v) SetNumber(unit, "hpOffsetX", v, "MSUF2_HP_X", { text = true, preview = true }) end)

    local hpY = W.Slider(sec, "Health Y", -300, 300, 1, 260)
    PlaceSlider(hpY, rightX, -482, sliderW)
    M.BindSlider(ctx, hpY,
        function() return ReadNumber(unit, "hpOffsetY", -4) end,
        function(v) SetNumber(unit, "hpOffsetY", v, "MSUF2_HP_Y", { text = true, preview = true }) end)

    local pMode = W.Dropdown(sec, "Power pattern", POWER_MODES, 260)
    PlaceDropdown(pMode, leftX, -478, dropdownW)
    M.BindDropdown(ctx, pMode,
        function() return ReadText(unit, "powerTextMode", "CURPERCENT") end,
        function(v) SetText(unit, "powerTextMode", v or "CURPERCENT", "MSUF2_POWER_TEXT_MODE") end)

    local pAnchor = W.Dropdown(sec, "Power anchor", TEXT_ANCHORS, 210)
    PlaceDropdown(pAnchor, leftX, -530, smallDropdownW)
    M.BindDropdown(ctx, pAnchor,
        function() return ReadText(unit, "powerTextAnchor", "RIGHT") end,
        function(v) SetText(unit, "powerTextAnchor", v or "RIGHT", "MSUF2_POWER_TEXT_ANCHOR") end)

    local pSep = W.Dropdown(sec, "Power delimiter", SEPARATORS, 160)
    PlaceDropdown(pSep, leftX, -582, smallDropdownW)
    M.BindDropdown(ctx, pSep,
        function() return ReadText(unit, "powerTextSeparator", ReadText(unit, "hpTextSeparator", "")) end,
        function(v) SetText(unit, "powerTextSeparator", v or "", "MSUF2_POWER_TEXT_SEPARATOR") end)

    local pSize = W.Slider(sec, "Power text size", 6, 32, 1, 260)
    PlaceSlider(pSize, leftX, -638, sliderW)
    M.BindSlider(ctx, pSize,
        function() return ReadNumber(unit, "powerFontSize", 12) end,
        function(v) SetNumber(unit, "powerFontSize", v, "MSUF2_POWER_TEXT_SIZE", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

    local pX = W.Slider(sec, "Power X", -300, 300, 1, 260)
    PlaceSlider(pX, leftX, -696, sliderW)
    M.BindSlider(ctx, pX,
        function() return ReadNumber(unit, "powerOffsetX", -4) end,
        function(v) SetNumber(unit, "powerOffsetX", v, "MSUF2_POWER_X", { text = true, preview = true }) end)

    local pY = W.Slider(sec, "Power Y", -300, 300, 1, 260)
    PlaceSlider(pY, leftX, -754, sliderW)
    M.BindSlider(ctx, pY,
        function() return ReadNumber(unit, "powerOffsetY", 4) end,
        function(v) SetNumber(unit, "powerOffsetY", v, "MSUF2_POWER_Y", { text = true, preview = true }) end)

    local nameLayer = W.Slider(sec, "Name layer", 0, 30, 1, 260)
    PlaceSlider(nameLayer, rightX, -600, sliderW)
    M.BindSlider(ctx, nameLayer,
        function() return ReadNumber(unit, "nameTextLayer", 5) end,
        function(v) SetNumber(unit, "nameTextLayer", v, "MSUF2_NAME_TEXT_LAYER", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

    local hpLayer = W.Slider(sec, "HP layer", 0, 30, 1, 260)
    PlaceSlider(hpLayer, rightX, -658, sliderW)
    M.BindSlider(ctx, hpLayer,
        function() return ReadNumber(unit, "hpTextLayer", 5) end,
        function(v) SetNumber(unit, "hpTextLayer", v, "MSUF2_HP_TEXT_LAYER", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

    local powerLayer = W.Slider(sec, "Power layer", 0, 30, 1, 260)
    PlaceSlider(powerLayer, rightX, -716, sliderW)
    M.BindSlider(ctx, powerLayer,
        function() return ReadNumber(unit, "powerTextLayer", 2) end,
        function(v) SetNumber(unit, "powerTextLayer", v, "MSUF2_POWER_TEXT_LAYER", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

    local hpSpacer = W.ToggleAt(sec, "HP spacer", rightX, -878, colW - 60)
    M.BindToggle(ctx, hpSpacer,
        function() return ReadText(unit, "hpTextSpacerEnabled", false) == true end,
        function(v)
            SetText(unit, "hpTextSpacerEnabled", v and true or false, "MSUF2_HP_TEXT_SPACER")
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    local hpSpacerX = W.Slider(sec, "HP spacer X", 0, 1000, 1, 260)
    PlaceSlider(hpSpacerX, rightX, -920, sliderW)
    M.BindSlider(ctx, hpSpacerX,
        function() return tonumber(ReadText(unit, "hpTextSpacerX", 140)) or 140 end,
        function(v) SetText(unit, "hpTextSpacerX", floor((tonumber(v) or 140) + 0.5), "MSUF2_HP_TEXT_SPACER_X") end)

    local powerSpacer = W.ToggleAt(sec, "Power spacer", rightX, -984, colW - 60)
    M.BindToggle(ctx, powerSpacer,
        function() return ReadText(unit, "powerTextSpacerEnabled", false) == true end,
        function(v)
            SetText(unit, "powerTextSpacerEnabled", v and true or false, "MSUF2_POWER_TEXT_SPACER")
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    local powerSpacerX = W.Slider(sec, "Power spacer X", 0, 1000, 1, 260)
    PlaceSlider(powerSpacerX, rightX, -1026, sliderW)
    M.BindSlider(ctx, powerSpacerX,
        function() return tonumber(ReadText(unit, "powerTextSpacerX", 140)) or 140 end,
        function(v) SetText(unit, "powerTextSpacerX", floor((tonumber(v) or 140) + 0.5), "MSUF2_POWER_TEXT_SPACER_X") end)

    RefreshTextControlState = function()
        local nameOn = ReadBool(unit, "showName", true)
        local hpOn = ReadBool(unit, "showHP", true)
        local powerOn = ReadBool(unit, "showPower", unit ~= "pet" and unit ~= "targettarget")
        SetControlEnabled(nameAnchor, nameOn)
        SetControlEnabled(nameSize, nameOn)
        SetControlEnabled(nameX, nameOn)
        SetControlEnabled(nameY, nameOn)
        SetControlEnabled(nameLayer, nameOn)
        SetControlEnabled(hpMode, hpOn)
        SetControlEnabled(hpAnchor, hpOn)
        SetControlEnabled(hpSep, hpOn)
        SetControlEnabled(hpReverse, hpOn)
        SetControlEnabled(hpSize, hpOn)
        SetControlEnabled(hpX, hpOn)
        SetControlEnabled(hpY, hpOn)
        SetControlEnabled(hpLayer, hpOn)
        SetControlEnabled(hpSpacer, hpOn)
        SetControlEnabled(hpSpacerX, hpOn and ReadText(unit, "hpTextSpacerEnabled", false) == true)
        SetControlEnabled(pMode, powerOn)
        SetControlEnabled(pAnchor, powerOn)
        SetControlEnabled(pSep, powerOn)
        SetControlEnabled(pSize, powerOn)
        SetControlEnabled(pX, powerOn)
        SetControlEnabled(pY, powerOn)
        SetControlEnabled(powerLayer, powerOn)
        SetControlEnabled(powerSpacer, powerOn)
        SetControlEnabled(powerSpacerX, powerOn and ReadText(unit, "powerTextSpacerEnabled", false) == true)
    end
    M.AddRefresher(ctx, RefreshTextControlState)
end

local function BuildInlineText(ctx, builder, unit)
    if unit ~= "target" then return end

    local sec = builder:CollapsibleSection("inline_text", "Inline Text", 164, false)
    W.Text(sec, "Target of Target inline text is shown on the Target frame name line.", 14, -38, ctx.width - 28, T.colors.muted)
    sec._msuf2CursorY = -72

    local show = W.Toggle(sec, "Show Target of Target text inline")
    M.BindToggle(ctx, show,
        function() return GetConf("targettarget").showToTInTargetName == true end,
        function(v)
            local conf = GetConf("targettarget")
            conf.showToTInTargetName = v and true or false
            M.RequestUnitApply("target", "MSUF2_TOT_INLINE", { text = true, preview = true })
            M.RequestUnitApply("targettarget", "MSUF2_TOT_INLINE", { text = true, preview = true })
            Call("MSUF_UpdateTargetToTInlineNow")
            Call("MSUF_UFPreview_RequestRefresh", "MSUF2_TOT_INLINE")
        end)

    local sep = W.Dropdown(sec, "Inline separator", SEPARATORS, 170)
    M.BindDropdown(ctx, sep,
        function() return GetConf("targettarget").totInlineSeparator or "|" end,
        function(v)
            local conf = GetConf("targettarget")
            conf.totInlineSeparator = (v ~= nil and tostring(v) ~= "") and tostring(v) or " "
            M.RequestUnitApply("target", "MSUF2_TOT_INLINE_SEPARATOR", { text = true, preview = true })
            Call("MSUF_ToTInline_RequestRefresh", "MSUF2_TOT_INLINE_SEPARATOR")
            Call("MSUF_UpdateTargetToTInlineNow")
            Call("MSUF_UFPreview_RequestRefresh", "MSUF2_TOT_INLINE_SEPARATOR")
        end)
end

local function BuildAlpha(ctx, builder, unit)
    local sec = builder:CollapsibleSection("transparency", "Transparency", 230, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local rightX = math.max(340, floor(sectionW * 0.50) + 8)
    local sliderW = math.min(300, math.max(220, floor((sectionW - 54) / 2)))
    local function PlaceSlider(control, x, y, width)
        if not control then return end
        width = width or sliderW
        if control._msuf2Title then
            control._msuf2Title:ClearAllPoints()
            control._msuf2Title:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y)
            control._msuf2Title:SetWidth(width)
            control._msuf2Title:SetJustifyH("CENTER")
        end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y - 22)
        if control._msuf2SetLayoutWidth then
            control:_msuf2SetLayoutWidth(width)
        else
            control:SetSize(width, 16)
            if control._msuf2UpdateFill then control:_msuf2UpdateFill() end
        end
    end

    local inCombat = W.Slider(sec, "Alpha in combat", 0, 1, 0.05, 300)
    PlaceSlider(inCombat, leftX, -102, sliderW)
    M.BindSlider(ctx, inCombat,
        function() return ReadNumber(unit, "alphaInCombat", 1) end,
        function(v)
            SetNumber(unit, "alphaInCombat", v, "MSUF2_ALPHA_IN", { alpha = true, preview = true })
            if ReadBool(unit, "alphaSync", false) then
                SetNumber(unit, "alphaOutOfCombat", v, "MSUF2_ALPHA_SYNC", { alpha = true, preview = true })
            end
        end)

    local outCombat = W.Slider(sec, "Alpha out of combat", 0, 1, 0.05, 300)
    PlaceSlider(outCombat, rightX, -102, sliderW)
    M.BindSlider(ctx, outCombat,
        function() return ReadNumber(unit, "alphaOutOfCombat", 1) end,
        function(v) SetNumber(unit, "alphaOutOfCombat", v, "MSUF2_ALPHA_OUT", { alpha = true, preview = true }) end)

    local sync = W.ToggleAt(sec, "Sync both", leftX, -42, 220)
    M.BindToggle(ctx, sync,
        function() return ReadBool(unit, "alphaSync", false) end,
        function(v)
            SetBool(unit, "alphaSync", v, "MSUF2_ALPHA_SYNC_TOGGLE", { alpha = true, preview = true })
            if v then
                SetNumber(unit, "alphaOutOfCombat", ReadNumber(unit, "alphaInCombat", 1), "MSUF2_ALPHA_SYNC_VALUE", { alpha = true, preview = true })
            end
        end)

    local exclude = W.ToggleAt(sec, "Keep text + portrait visible", rightX, -42, 250)
    M.BindToggle(ctx, exclude,
        function() return ReadBool(unit, "alphaExcludeTextPortrait", false) end,
        function(v) SetBool(unit, "alphaExcludeTextPortrait", v, "MSUF2_ALPHA_EXCLUDE", { alpha = true, preview = true }) end)

    local preserve = W.ToggleAt(sec, "Preserve HP color", rightX, -72, 220)
    M.BindToggle(ctx, preserve,
        function() return ReadBool(unit, "alphaPreserveHPColor", false) end,
        function(v) SetBool(unit, "alphaPreserveHPColor", v, "MSUF2_ALPHA_HP_COLOR", { alpha = true, preview = true }) end)

    local affects = T.Font(sec, "GameFontNormalSmall", "Sliders affect", T.colors.text)
    affects:SetPoint("TOPLEFT", sec, "TOPLEFT", leftX, -72)
    local mode = W.Segment(sec, "Fade layer", {
        { value = "foreground", text = "Foreground" },
        { value = "health", text = "Health" },
        { value = "background", text = "Background" },
    }, 420)
    if mode._msuf2Title then
        mode._msuf2Title:ClearAllPoints()
        mode._msuf2Title:SetPoint("TOPLEFT", sec, "TOPLEFT", leftX, -160)
    end
    mode:ClearAllPoints()
    mode:SetPoint("TOPLEFT", sec, "TOPLEFT", leftX, -182)
    mode:SetSize(math.min(520, sectionW - 28), 22)
    do
        local buttons = mode.buttons or {}
        local count = #buttons
        local gap = 8
        local bw = count > 0 and floor((mode:GetWidth() - gap * (count - 1)) / count) or 120
        for i = 1, count do
            local btn = buttons[i]
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", mode, "LEFT", (i - 1) * (bw + gap), 0)
            btn:SetSize(bw, 22)
        end
    end
    M.BindSegment(ctx, mode,
        function() return NormalizeAlphaMode(GetConf(unit).alphaLayerMode) end,
        function(v) M.SetUnitValue(unit, "alphaLayerMode", AlphaModeValue(v), "MSUF2_ALPHA_LAYER", { alpha = true, preview = true }) end)
end

local function BuildPortrait(ctx, builder, unit)
    local sec = builder:CollapsibleSection("portrait", "Portrait", 460, false)
    local portrait = W.Segment(sec, "Portrait mode", {
        { value = "OFF", text = "Off" },
        { value = "LEFT", text = "Left" },
        { value = "RIGHT", text = "Right" },
    }, 300)
    M.BindSegment(ctx, portrait,
        function() return NormalizePortrait(unit) end,
        function(v) SetPortraitValue(unit, "portraitMode", v or "OFF", "MSUF2_PORTRAIT_MODE") end)

    local render = W.Dropdown(sec, "Render", PORTRAIT_RENDER, 220)
    M.BindDropdown(ctx, render,
        function() return GetConf(unit).portraitRender or "2D" end,
        function(v) SetPortraitValue(unit, "portraitRender", v or "2D", "MSUF2_PORTRAIT_RENDER") end)

    local shape = W.Dropdown(sec, "Shape", PORTRAIT_SHAPES, 220)
    M.BindDropdown(ctx, shape,
        function() return GetConf(unit).portraitShape or "SQUARE" end,
        function(v) SetPortraitValue(unit, "portraitShape", v or "SQUARE", "MSUF2_PORTRAIT_SHAPE") end)

    local size = W.Slider(sec, "Size override", 0, 128, 1, 280)
    M.BindSlider(ctx, size,
        function() return ReadNumber(unit, "portraitSizeOverride", 0) end,
        function(v) SetNumber(unit, "portraitSizeOverride", v, "MSUF2_PORTRAIT_SIZE", { preview = true }) end)

    local x = W.Slider(sec, "Portrait X", -120, 120, 1, 280)
    M.BindSlider(ctx, x,
        function() return ReadNumber(unit, "portraitOffsetX", 0) end,
        function(v) SetNumber(unit, "portraitOffsetX", v, "MSUF2_PORTRAIT_X", { preview = true }) end)

    local y = W.Slider(sec, "Portrait Y", -120, 120, 1, 280)
    M.BindSlider(ctx, y,
        function() return ReadNumber(unit, "portraitOffsetY", 0) end,
        function(v) SetNumber(unit, "portraitOffsetY", v, "MSUF2_PORTRAIT_Y", { preview = true }) end)

    local border = W.Dropdown(sec, "Border", PORTRAIT_BORDERS, 220)
    M.BindDropdown(ctx, border,
        function() return GetConf(unit).portraitBorderStyle or "NONE" end,
        function(v) SetPortraitValue(unit, "portraitBorderStyle", v or "NONE", "MSUF2_PORTRAIT_BORDER") end)

    local borderSize = W.Slider(sec, "Border thickness", 1, 12, 1, 280)
    M.BindSlider(ctx, borderSize,
        function() return ReadNumber(unit, "portraitBorderThickness", 2) end,
        function(v) SetNumber(unit, "portraitBorderThickness", v, "MSUF2_PORTRAIT_BORDER_SIZE", { preview = true }) end)
end

local function BuildPower(ctx, builder, unit)
    if not POWER_UNITS[unit] then return end
    local sec = builder:CollapsibleSection("power_bar", "Power Bar", unit == "player" and 640 or 580, false)
    local RefreshPowerEnabled
    local powerControls = {}
    local detachedControls = {}
    local function AddPowerControl(control)
        powerControls[#powerControls + 1] = control
        return control
    end
    local function AddDetachedControl(control)
        detachedControls[#detachedControls + 1] = control
        return AddPowerControl(control)
    end

    local show = W.Toggle(sec, "Show power bar")
    M.BindToggle(ctx, show,
        function() return ReadBool(unit, "showPowerBar", true) end,
        function(v)
            SetBool(unit, "showPowerBar", v, "MSUF2_POWER_SHOW", { power = true, preview = true })
            if RefreshPowerEnabled then RefreshPowerEnabled() end
        end)

    local embed = AddPowerControl(W.Toggle(sec, "Embed into health"))
    M.BindToggle(ctx, embed,
        function()
            local conf = GetConf(unit)
            if conf.embedPowerBarIntoHealth ~= nil then return conf.embedPowerBarIntoHealth == true end
            return GetBars().embedPowerBarIntoHealth == true
        end,
        function(v) SetBool(unit, "embedPowerBarIntoHealth", v, "MSUF2_POWER_EMBED", { power = true, preview = true }) end)

    local border = AddPowerControl(W.Toggle(sec, "Power bar border"))
    M.BindToggle(ctx, border,
        function()
            local conf = GetConf(unit)
            if conf.powerBarBorderEnabled ~= nil then return conf.powerBarBorderEnabled == true end
            return GetBars().powerBarBorderEnabled == true
        end,
        function(v) SetBool(unit, "powerBarBorderEnabled", v, "MSUF2_POWER_BORDER", { power = true, preview = true }) end)

    local smooth = AddPowerControl(W.Toggle(sec, "Smooth fill"))
    M.BindToggle(ctx, smooth,
        function() return ReadBool(unit, "powerSmoothFill", true) end,
        function(v) SetBool(unit, "powerSmoothFill", v, "MSUF2_POWER_SMOOTH", { power = true, preview = true }) end)

    local height = AddPowerControl(W.Slider(sec, "Power bar height", 1, 20, 1, 300))
    M.BindSlider(ctx, height,
        function()
            local conf = GetConf(unit)
            return tonumber(conf.powerBarHeight) or tonumber(GetBars().powerBarHeight) or 3
        end,
        function(v) SetNumber(unit, "powerBarHeight", v, "MSUF2_POWER_HEIGHT", { power = true, preview = true }) end)

    local borderSize = AddPowerControl(W.Slider(sec, "Border thickness", 0, 6, 1, 300))
    M.BindSlider(ctx, borderSize,
        function()
            local conf = GetConf(unit)
            return tonumber(conf.powerBarBorderThickness) or tonumber(GetBars().powerBarBorderThickness or GetBars().powerBarBorderSize) or 1
        end,
        function(v) SetNumber(unit, "powerBarBorderThickness", v, "MSUF2_POWER_BORDER_SIZE", { power = true, preview = true }) end)

    local detached = AddPowerControl(W.Toggle(sec, "Detach from frame"))
    M.BindToggle(ctx, detached,
        function() return ReadBool(unit, "powerBarDetached", false) end,
        function(v)
            local conf = GetConf(unit)
            conf.powerBarDetached = v and true or false
            if conf.powerBarDetached then
                conf.detachedPowerBarOffsetX = tonumber(conf.detachedPowerBarOffsetX) or 0
                conf.detachedPowerBarOffsetY = tonumber(conf.detachedPowerBarOffsetY) or -4
                conf.detachedPowerBarWidth = tonumber(conf.detachedPowerBarWidth) or tonumber(conf.width) or (unit == "focus" and 180 or 275)
                conf.detachedPowerBarHeight = tonumber(conf.detachedPowerBarHeight) or 6
                conf.detachedPowerBarFrameLevelOffset = tonumber(conf.detachedPowerBarFrameLevelOffset) or 6
                if unit == "player" and conf.detachedPowerBarSyncClassPower == nil then conf.detachedPowerBarSyncClassPower = true end
            end
            M.RequestUnitApply(unit, "MSUF2_POWER_DETACHED", { power = true, preview = true })
            if RefreshPowerEnabled then RefreshPowerEnabled() end
        end)

    local textOnBar = AddDetachedControl(W.Toggle(sec, "Text on detached bar"))
    M.BindToggle(ctx, textOnBar,
        function() return ReadBool(unit, "detachedPowerBarTextOnBar", false) end,
        function(v) SetBool(unit, "detachedPowerBarTextOnBar", v, "MSUF2_POWER_DETACHED_TEXT", { power = true, text = true, preview = true }) end)

    if unit == "player" then
        local sync = AddDetachedControl(W.Toggle(sec, "Sync width to Class Resource"))
        M.BindToggle(ctx, sync,
            function() return GetConf(unit).detachedPowerBarSyncClassPower ~= false end,
            function(v) SetBool(unit, "detachedPowerBarSyncClassPower", v, "MSUF2_POWER_DETACHED_SYNC", { power = true, preview = true }) end)

        local anchor = AddDetachedControl(W.Toggle(sec, "Anchor to Class Resource"))
        M.BindToggle(ctx, anchor,
            function() return ReadBool(unit, "detachedPowerBarAnchorToClassPower", false) end,
            function(v) SetBool(unit, "detachedPowerBarAnchorToClassPower", v, "MSUF2_POWER_DETACHED_ANCHOR", { power = true, preview = true }) end)
    end

    local dx = AddDetachedControl(W.Slider(sec, "Detached X", -1000, 1000, 1, 300))
    M.BindSlider(ctx, dx,
        function() return ReadNumber(unit, "detachedPowerBarOffsetX", 0) end,
        function(v) SetNumber(unit, "detachedPowerBarOffsetX", v, "MSUF2_POWER_DETACHED_X", { power = true, preview = true }) end)

    local dy = AddDetachedControl(W.Slider(sec, "Detached Y", -1000, 1000, 1, 300))
    M.BindSlider(ctx, dy,
        function() return ReadNumber(unit, "detachedPowerBarOffsetY", -4) end,
        function(v) SetNumber(unit, "detachedPowerBarOffsetY", v, "MSUF2_POWER_DETACHED_Y", { power = true, preview = true }) end)

    local dw = AddDetachedControl(W.Slider(sec, "Detached width", 20, 800, 1, 300))
    M.BindSlider(ctx, dw,
        function() return ReadNumber(unit, "detachedPowerBarWidth", ReadNumber(unit, "width", 250)) end,
        function(v) SetNumber(unit, "detachedPowerBarWidth", v, "MSUF2_POWER_DETACHED_W", { power = true, preview = true }) end)

    local dh = AddDetachedControl(W.Slider(sec, "Detached height", 2, 80, 1, 300))
    M.BindSlider(ctx, dh,
        function() return ReadNumber(unit, "detachedPowerBarHeight", 6) end,
        function(v) SetNumber(unit, "detachedPowerBarHeight", v, "MSUF2_POWER_DETACHED_H", { power = true, preview = true }) end)

    RefreshPowerEnabled = function()
        local powerOn = ReadBool(unit, "showPowerBar", true)
        local detachedOn = powerOn and ReadBool(unit, "powerBarDetached", false)
        for i = 1, #powerControls do SetControlEnabled(powerControls[i], powerOn) end
        for i = 1, #detachedControls do SetControlEnabled(detachedControls[i], detachedOn) end
        SetControlEnabled(show, true)
    end
    M.AddRefresher(ctx, RefreshPowerEnabled)
    RefreshPowerEnabled()
end

local function BuildCastbar(ctx, builder, unit)
    local fields = CASTBAR_FIELDS[unit]
    if not fields then return end
    local sec = builder:CollapsibleSection("castbar", "Castbar", 116, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local rightX = math.max(340, sectionW - 236)
    local textX = rightX + 86
    local RefreshCastbarEnabled

    local enabledLabel = (unit == "boss") and "Enable boss castbars" or ("Enable " .. UnitTopLabel(unit):lower() .. " castbar")
    local timeLabel = (unit == "boss") and "Show boss cast time" or ("Show " .. UnitTopLabel(unit):lower() .. " cast time")

    local enabled = W.ToggleAt(sec, enabledLabel, leftX, -42, 240)
    M.BindToggle(ctx, enabled,
        function() return ReadGeneralBool(fields.enable, true) end,
        function(v)
            SetGeneralBool(fields.enable, v, "MSUF2_CASTBAR_ENABLE", { castbar = true, preview = true })
            if RefreshCastbarEnabled then RefreshCastbarEnabled() end
        end)

    local time = W.ToggleAt(sec, timeLabel, leftX, -72, 240)
    M.BindToggle(ctx, time,
        function() return ReadGeneralBool(fields.time, true) end,
        function(v) SetGeneralBool(fields.time, v, "MSUF2_CASTBAR_TIME", { castbar = true, preview = true }) end)

    local interrupt = W.ToggleAt(sec, "Show interrupt", leftX, -102, 240)
    M.BindToggle(ctx, interrupt,
        function() return ReadBool(unit, "showInterrupt", true) end,
        function(v) SetBool(unit, "showInterrupt", v, "MSUF2_CASTBAR_INTERRUPT", { castbar = true, preview = true }) end)

    local icon = W.ToggleAt(sec, "Icon", rightX, -42, 70)
    M.BindToggle(ctx, icon,
        function() return ReadGeneralBool(fields.icon, true) end,
        function(v) SetGeneralBool(fields.icon, v, "MSUF2_CASTBAR_ICON", { castbar = true, preview = true }) end)

    local text = W.ToggleAt(sec, "Text", textX, -42, 70)
    M.BindToggle(ctx, text,
        function() return ReadGeneralBool(fields.text, true) end,
        function(v) SetGeneralBool(fields.text, v, "MSUF2_CASTBAR_TEXT", { castbar = true, preview = true }) end)

    RefreshCastbarEnabled = function()
        local on = ReadGeneralBool(fields.enable, true)
        SetControlEnabled(time, on)
        SetControlEnabled(interrupt, on)
        SetControlEnabled(icon, on)
        SetControlEnabled(text, on)
        SetControlEnabled(enabled, true)
    end
    M.AddRefresher(ctx, RefreshCastbarEnabled)
    RefreshCastbarEnabled()
end

local function BuildStatus(ctx, builder, unit)
    local sec = builder:CollapsibleSection("status_icons", "Status icons", 626, false)

    local selector = W.Dropdown(sec, "Indicator", function() return StatusValues(unit) end, 260)
    M.BindDropdown(ctx, selector,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and spec.value or ""
        end,
        function(value)
            local spec = FindStatusSpec(unit, value)
            if not spec then return end
            M.unitStatusSelection = M.unitStatusSelection or {}
            M.unitStatusSelection[unit] = spec.value
            Call("MSUF_UFPreview_SelectStatusIcon", spec.value)
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local midnight = W.Toggle(sec, "Use Midnight style")
    M.BindToggle(ctx, midnight,
        function() return ReadGeneralBool("statusIconsUseMidnightStyle", false) end,
        function(value)
            SetGeneralBool("statusIconsUseMidnightStyle", value, "MSUF2_STATUS_STYLE", { preview = true, applyAll = true })
            Call("MSUF_SetStatusIconStyleUseMidnight", value and true or false)
            Call("MSUF_RequestStatusIconsRefreshForCurrent")
        end)

    local enabled = W.Toggle(sec, "Enabled")
    M.BindToggle(ctx, enabled,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ReadStatusBool(unit, spec.show, spec.defaultShow) or false
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetBool(unit, spec.show, value, "MSUF2_STATUS_ENABLED", { preview = true })
            RefreshStatusRuntime(unit, spec)
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local symbol = W.Dropdown(sec, "Symbol", function()
        local spec = CurrentStatusSpec(unit)
        return (spec and spec.symbols) or DEFAULT_SYMBOLS
    end, 260)
    M.BindDropdown(ctx, symbol,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and spec.symbol and ReadStatusString(unit, spec.symbol, "DEFAULT") or "DEFAULT"
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not (spec and spec.symbol) then return end
            SetString(unit, spec.symbol, value or "DEFAULT", "MSUF2_STATUS_SYMBOL", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)

    local size = W.Slider(sec, "Size", 8, 64, 1, 300)
    M.BindSlider(ctx, size,
        function()
            local spec = CurrentStatusSpec(unit)
            if not spec then return 14 end
            local fallback = spec.defaultSize
            if spec.value == "level" then fallback = ReadStatusNumber(unit, "nameFontSize", fallback or 14) end
            return ReadStatusNumber(unit, spec.size, fallback)
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.size, value, "MSUF2_STATUS_SIZE", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)

    local anchor = W.Dropdown(sec, "Anchor", function()
        local spec = CurrentStatusSpec(unit)
        return (spec and spec.anchors) or STATUS_ANCHORS
    end, 220)
    M.BindDropdown(ctx, anchor,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ReadStatusString(unit, spec.anchor, spec.defaultAnchor) or "TOPLEFT"
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetString(unit, spec.anchor, value or spec.defaultAnchor or "TOPLEFT", "MSUF2_STATUS_ANCHOR", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)

    local x = W.Slider(sec, "X Offset", -500, 500, 1, 300)
    M.BindSlider(ctx, x,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ReadStatusNumber(unit, spec.x, spec.defaultX) or 0
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.x, value, "MSUF2_STATUS_X", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)

    local y = W.Slider(sec, "Y Offset", -500, 500, 1, 300)
    M.BindSlider(ctx, y,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ReadStatusNumber(unit, spec.y, spec.defaultY) or 0
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.y, value, "MSUF2_STATUS_Y", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)

    local layer = W.Slider(sec, "Layer", 1, 10, 1, 300)
    M.BindSlider(ctx, layer,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ClampStatusLayer(ReadStatusNumber(unit, spec.layer, spec.defaultLayer), spec.defaultLayer) or 7
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.layer, ClampStatusLayer(value, spec.defaultLayer), "MSUF2_STATUS_LAYER", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)

    local reset = W.Button(sec, "Reset selected", 150)
    reset:SetScript("OnClick", function()
        local spec = CurrentStatusSpec(unit)
        if not spec then return end
        local conf = GetConf(unit)
        conf[spec.x], conf[spec.y], conf[spec.anchor], conf[spec.size], conf[spec.layer] = nil, nil, nil, nil, nil
        if spec.symbol then conf[spec.symbol] = nil end
        RefreshStatusRuntime(unit, spec)
        if M.SelectPage then M.SelectPage(ctx.key) end
    end)

    local test = W.Toggle(sec, "Test mode")
    M.BindToggle(ctx, test,
        function() return ReadBool(unit, "stateIconsTestMode", ReadGeneralBool("stateIconsTestMode", false)) end,
        function(value)
            SetBool(unit, "stateIconsTestMode", value, "MSUF2_STATUS_TEST", { preview = true })
            Call("MSUF_RequestStatusIconsRefreshForCurrent")
        end)

    local current = W.Button(sec, "Preview current", 142)
    current:SetScript("OnClick", function()
        Call("MSUF_UFPreview_SetStatusPreviewMode", "current")
        local spec = CurrentStatusSpec(unit)
        if spec then Call("MSUF_UFPreview_SelectStatusIcon", spec.value) end
    end)
    local all = W.Button(sec, "Show all", 112)
    all:SetScript("OnClick", function()
        Call("MSUF_UFPreview_SetStatusPreviewMode", "all")
    end)

    M.AddRefresher(ctx, function()
        local spec = CurrentStatusSpec(unit)
        local hasSymbol = spec and spec.symbol
        local showStateStyle = hasSymbol and true or false
        local showTestMode = spec and spec.statusRuntime and true or false
        if W.SetControlShown then
            W.SetControlShown(midnight, showStateStyle)
            W.SetControlShown(symbol, hasSymbol)
            W.SetControlShown(test, showTestMode)
        else
            if midnight then midnight:SetShown(showStateStyle) end
            if symbol then symbol:SetShown(hasSymbol and true or false) end
            if test then test:SetShown(showTestMode) end
        end
        local isEnabled = spec and ReadStatusBool(unit, spec.show, spec.defaultShow)
        SetControlEnabled(symbol, hasSymbol and isEnabled)
        SetControlEnabled(size, isEnabled)
        SetControlEnabled(anchor, isEnabled)
        SetControlEnabled(x, isEnabled)
        SetControlEnabled(y, isEnabled)
        SetControlEnabled(layer, isEnabled)
        SetControlEnabled(reset, spec ~= nil)
    end)
end

local function BuildLoadConditions(ctx, builder, unit)
    local sec = builder:CollapsibleSection("load_conditions", "Load Conditions", 148, false)
    local colW = math.floor(((ctx.width or 720) - 42) / 3)
    for i = 1, #LOAD_CONDITIONS do
        local spec = LOAD_CONDITIONS[i]
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local toggle
        if W.ToggleAt then
            toggle = W.ToggleAt(sec, spec.label, 14 + col * colW, -42 - row * 30, colW - 34)
        else
            toggle = W.Toggle(sec, spec.label)
        end
        M.BindToggle(ctx, toggle,
            function() return ReadBool(unit, spec.key, false) end,
            function(v)
                local conf = GetConf(unit)
                conf[spec.key] = v and true or false
                UpdateLoadActive(unit)
                M.RequestUnitApply(unit, "MSUF2_LOAD_CONDITION", { preview = true })
            end)
    end
end

local function BuildBossLayout(ctx, builder, unit)
    if unit ~= "boss" then return end
    local sec = builder:CollapsibleSection("boss_layout", "Boss Layout", 152, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local rightX = math.max(350, floor(sectionW * 0.50) + 8)
    local sliderW = math.min(300, math.max(220, rightX - leftX - 68))
    local function PlaceSlider(control, x, y, width)
        if not control then return end
        width = width or sliderW
        if control._msuf2Title then
            control._msuf2Title:ClearAllPoints()
            control._msuf2Title:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y)
            control._msuf2Title:SetWidth(width)
            control._msuf2Title:SetJustifyH("CENTER")
        end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y - 22)
        if control._msuf2SetLayoutWidth then
            control:_msuf2SetLayoutWidth(width)
        else
            control:SetSize(width, 16)
            if control._msuf2UpdateFill then control:_msuf2UpdateFill() end
        end
    end
    local function PlaceDropdown(control, x, y, width)
        if not control then return end
        if control._msuf2Title then
            control._msuf2Title:ClearAllPoints()
            control._msuf2Title:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y)
            control._msuf2Title:SetWidth(width or 220)
        end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y - 22)
        control:SetSize(width or 220, 22)
    end

    local spacing = W.Slider(sec, "Boss spacing", -400, 0, 1, 300)
    PlaceSlider(spacing, leftX, -42, sliderW)
    M.BindSlider(ctx, spacing,
        function() return ReadNumber(unit, "spacing", -36) end,
        function(v) SetNumber(unit, "spacing", v, "MSUF2_BOSS_SPACING", { preview = true }) end)

    local layout = W.Dropdown(sec, "Boss frame layout", BOSS_LAYOUT_OPTIONS, 220)
    PlaceDropdown(layout, rightX, -42, 220)
    M.BindDropdown(ctx, layout,
        function()
            local conf = GetConf(unit)
            return NormalizeBossLayoutMode(conf.bossLayoutMode, conf.invertBossOrder)
        end,
        function(v)
            local conf = GetConf(unit)
            conf.bossLayoutMode = NormalizeBossLayoutMode(v)
            conf.invertBossOrder = nil
            M.RequestUnitApply(unit, "MSUF2_BOSS_LAYOUT_MODE", { preview = true })
        end)

    local highlight = W.ToggleAt(sec, "Boss target highlight", leftX, -116, 260)
    M.BindToggle(ctx, highlight,
        function() return ReadGeneralBool("bossTargetHighlightEnabled", true) end,
        function(v)
            local g = GetGeneral()
            g.bossTargetHighlightEnabled = v and true or false
            g.bossTargetOutlineMode = v and 1 or 0
            M.RequestGeneralApply("MSUF2_BOSS_TARGET_HIGHLIGHT", { preview = true })
        end)
end

local function BuildUnitPage(info)
    return function(ctx)
        local builder = W.PageBuilder(ctx)
        BuildTopActions(ctx, builder, info.unit, info.label)
        BuildPreview(ctx, builder, info.unit)
        BuildBasics(ctx, builder, info.unit, info.label)
        BuildText(ctx, builder, info.unit)
        BuildInlineText(ctx, builder, info.unit)
        BuildPortrait(ctx, builder, info.unit)
        BuildPower(ctx, builder, info.unit)
        BuildCastbar(ctx, builder, info.unit)
        BuildStatus(ctx, builder, info.unit)
        BuildBossLayout(ctx, builder, info.unit)
        BuildLoadConditions(ctx, builder, info.unit)
        BuildAlpha(ctx, builder, info.unit)
        BuildLayout(ctx, builder, info.unit)
        ctx:SetContentHeight(math.abs(builder.y) + 42)
    end
end

for key, info in pairs(UNIT_PAGES) do
    M.RegisterPage(key, {
        title = info.title,
        build = BuildUnitPage(info),
        version = 4,
    })
end
