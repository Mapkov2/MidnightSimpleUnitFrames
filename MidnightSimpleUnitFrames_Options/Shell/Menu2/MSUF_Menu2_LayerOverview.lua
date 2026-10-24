--- Shell/Menu2/MSUF_Menu2_LayerOverview.lua
--- Cold-path, addon-wide overview for the unified numeric MSUF layer scale.
--- Providers only read SavedVariables when the overview is requested; there are
--- no events, timers, or continuously running update scripts in this module.

local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Shell/Menu2/MSUF_Menu2_LayerOverview.lua")
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local T = M.Theme or {}
local W = M.Widgets or {}
local Tr = M.TranslateText or M.Tr
local floor = math.floor
local sort = table.sort

local Overview = M.LayerOverview or {}
M.LayerOverview = Overview
Overview.providers = Overview.providers or {}
local providers = Overview.providers

-- Unit scope keys and labels in menu order; the unit and bar scope lists below share them.
local UNIT_SCOPE_LABELS = {
    "player", "Player", "target", "Target", "targettarget", "Target of Target",
    "focustarget", "Focus Target", "focus", "Focus", "pet", "Pet", "pettarget", "Pet Target",
    "boss", "Boss", "arena", "Arena",
}
local function AppendUnitScopes(list)
    for i = 1, #UNIT_SCOPE_LABELS, 2 do
        list[#list + 1] = { key = UNIT_SCOPE_LABELS[i], label = UNIT_SCOPE_LABELS[i + 1] }
    end
    return list
end
local UNIT_SCOPES = AppendUnitScopes({})
local UNIT_AURA_SCOPES = {
    { key = "player", runtimeKey = "player", label = "Player", flag = "showPlayer", flagDefault = false },
    { key = "target", runtimeKey = "target", label = "Target", flag = "showTarget", flagDefault = true },
    { key = "focus", runtimeKey = "focus", label = "Focus", flag = "showFocus", flagDefault = false },
    { key = "boss", runtimeKey = "boss1", label = "Boss", flag = "showBoss", flagDefault = true },
    { key = "arena", runtimeKey = "arena1", label = "Arena", flag = "showArena", flagDefault = true },
}
local GROUP_SCOPES = {
    { key = "party", dbKey = "gf_party", label = "Party" },
    { key = "raid", dbKey = "gf_raid", label = "Raid" },
    { key = "mythicraid", dbKey = "gf_mythicraid", label = "Mythic Raid" },
}
local BAR_SCOPES = AppendUnitScopes({ { key = "shared", label = "Shared" } })
BAR_SCOPES[#BAR_SCOPES + 1] = { key = "gf_party", label = "Party" }
BAR_SCOPES[#BAR_SCOPES + 1] = { key = "gf_raid", label = "Raid" }
BAR_SCOPES[#BAR_SCOPES + 1] = { key = "gf_mythicraid", label = "Mythic Raid" }

if M.FilterSupportedUnitValues then
    M.FilterSupportedUnitValues(UNIT_SCOPES)
    M.FilterSupportedUnitValues(UNIT_AURA_SCOPES)
    M.FilterSupportedUnitValues(GROUP_SCOPES)
    M.FilterSupportedUnitValues(BAR_SCOPES)
end

local STRATA_RANK = MSUF.Require("MSUF_FRAME_STRATA_RANK", "Menu2/LayerOverview")
local FRAME_STRATA_CHOICES = {
    { value = "AUTO", text = "Auto (inherit)" },
    { value = "BACKGROUND", text = "Background" },
    { value = "LOW", text = "Low" },
    { value = "MEDIUM", text = "Medium" },
    { value = "HIGH", text = "High" },
    { value = "DIALOG", text = "Dialog" },
    { value = "FULLSCREEN", text = "Fullscreen" },
    { value = "FULLSCREEN_DIALOG", text = "Fullscreen Dialog" },
    { value = "TOOLTIP", text = "Tooltip" },
}

local FALLBACK_UNIT_STATUS_SPECS = {
    { text = "Leader / Assist Icons", show = "showLeaderIcon", defaultShow = true, layer = "leaderIconLayer", defaultLayer = 7, units = "player target" },
    { text = "Raid Marker", show = "showRaidMarker", defaultShow = true, layer = "raidMarkerLayer", defaultLayer = 7 },
    { text = "Level", show = "showLevelIndicator", defaultShow = true, layer = "levelIndicatorLayer", defaultLayer = 7 },
    { text = "Boss Number", show = "showBossNumberIndicator", defaultShow = false, layer = "bossNumberIndicatorLayer", defaultLayer = 7, units = "boss" },
    { text = "Raid Group", show = "showRaidGroupInName", defaultShow = false, layer = "raidGroupNameLayer", legacyLayer = "nameTextLayer", defaultLayer = 5,
        units = "player target targettarget focustarget focus pettarget" },
    { text = "Elite / Rare", show = "showEliteIcon", defaultShow = true, layer = "eliteIconLayer", defaultLayer = 7,
        units = "target focus targettarget focustarget pettarget boss" },
    { text = "Dead / Offline Text", show = "statusDeadTextEnabled", defaultShow = true, layer = "statusTextLayer", defaultLayer = 7 },
    { text = "Ghost Text", show = "statusGhostTextEnabled", defaultShow = true, layer = "statusGhostTextLayer", defaultLayer = 7 },
    { text = "AFK Text", show = "statusAFKTextEnabled", defaultShow = false, layer = "statusAFKTextLayer", defaultLayer = 7 },
    { text = "AFK Timer", show = "statusAFKTimerEnabled", defaultShow = false, layer = "statusAFKTimerLayer", defaultLayer = 7 },
    { text = "DND Text", show = "statusDNDTextEnabled", defaultShow = false, layer = "statusDNDTextLayer", defaultLayer = 7 },
    { text = "Combat", show = "showCombatStateIndicator", defaultShow = true, layer = "combatStateIndicatorLayer", defaultLayer = 7, units = "player target" },
    { text = "Rested", show = "showRestingIndicator", defaultShow = false, layer = "restedStateIndicatorLayer", defaultLayer = 7, units = "player" },
    { text = "Incoming Rez", show = "showIncomingResIndicator", defaultShow = true, layer = "incomingResIndicatorLayer", defaultLayer = 7,
        units = "player target" },
    { text = "PvP Flag", show = "showPvpIndicator", defaultShow = true, layer = "pvpIndicatorLayer", defaultLayer = 7,
        units = "player target focus targettarget focustarget pettarget" },
    { text = "Stance", show = "showStanceIndicator", defaultShow = false, layer = "stanceIndicatorLayer", defaultLayer = 7, units = "player" },
}
local FALLBACK_GROUP_STATUS_SPECS = {
    { text = "Role Icon", enabled = "roleIcon", layer = "roleIconLayer", defaultLayer = 1 },
    { text = "Leader", enabled = "leaderIcon", layer = "leaderIconLayer", defaultLayer = 2 },
    { text = "Assist", enabled = "assistIcon", layer = "assistIconLayer", defaultLayer = 2 },
    { text = "Raid Marker", enabled = "raidMarker", layer = "raidMarkerLayer", defaultLayer = 3 },
    { text = "Ready Check", enabled = "readyCheckIcon", layer = "readyCheckLayer", defaultLayer = 4 },
    { text = "Summon", enabled = "summonIcon", layer = "summonLayer", defaultLayer = 4 },
    { text = "Resurrect", enabled = "resurrectIcon", layer = "resurrectLayer", defaultLayer = 4 },
    { text = "PvP Flag", enabled = "pvpIcon", layer = "pvpIconLayer", defaultLayer = 3 },
    { text = "Phase", enabled = "phaseIcon", layer = "phaseLayer", defaultLayer = 3 },
    { text = "Dead Text", enabled = "statusText", layer = "statusTextLayer", defaultLayer = 7 },
    { text = "Ghost Text", enabled = "statusGhostText", layer = "statusGhostTextLayer", defaultLayer = 7 },
    { text = "AFK Text", enabled = "statusAFKText", layer = "statusAFKTextLayer", defaultLayer = 7 },
    { text = "AFK Timer", enabled = "statusAFKTimerText", layer = "statusAFKTimerTextLayer", defaultLayer = 7 },
    { text = "DND Text", enabled = "statusDNDText", layer = "statusDNDTextLayer", defaultLayer = 7 },
    { text = "Level Text", enabled = "levelText", layer = "levelTextLayer", defaultLayer = 7 },
}

local function DB()
    return type(MSUF_DB) == "table" and MSUF_DB or {}
end

local function Number(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value then return tonumber(fallback) or 0 end
    return value
end

local function Layer(value, fallback)
    value = Number(value, fallback)
    if value < 0 then value = 0 elseif value > 30 then value = 30 end
    return floor(value + 0.5)
end

local function BoolValue(value, fallback)
    if value == nil then return fallback and true or false end
    return value == true
end

local function Strata(value, fallback)
    value = tostring(value or fallback or "AUTO"):upper()
    if STRATA_RANK[value] ~= nil then return value end
    return "AUTO"
end

local function SortedKeys(tbl)
    local keys = {}
    if type(tbl) == "table" then
        for key in pairs(tbl) do keys[#keys + 1] = key end
    end
    sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function WordContains(words, needle)
    if type(words) ~= "string" then return false end
    needle = tostring(needle or "")
    for word in words:gmatch("%S+") do
        if word == needle then return true end
    end
    return false
end

local function ReadUnitValue(db, unit, key, fallback, legacyKey)
    local conf = type(db[unit]) == "table" and db[unit] or nil
    local general = type(db.general) == "table" and db.general or nil
    local value = conf and conf[key]
    local inherited = value == nil
    if value == nil and legacyKey then value = conf and conf[legacyKey] end
    if value == nil then value = general and general[key] end
    if value == nil and legacyKey then value = general and general[legacyKey] end
    if value == nil then value = fallback end
    return value, inherited
end

local function ReadUnitBool(db, unit, key, fallback)
    local value = ReadUnitValue(db, unit, key, fallback)
    return BoolValue(value, fallback)
end

local function UnitStatusAllowed(spec, unit)
    if type(spec) ~= "table" then return false end
    if type(spec.allowed) == "function" then
        local allowed = spec.allowed(unit)
        return allowed == true
    end
    if spec.units then return WordContains(spec.units, unit) end
    return true
end

local function UnitStatusSpecs()
    local specs = M.UnitPage and M.UnitPage.STATUS_CONTROLS
    if type(specs) == "table" and #specs > 0 then return specs end
    return FALLBACK_UNIT_STATUS_SPECS
end

local function GroupStatusSpecs()
    local specs = M.GroupSpecs and M.GroupSpecs.GF_STATUS_ICON_SPECS
    if type(specs) == "table" and #specs > 0 then return specs end
    return FALLBACK_GROUP_STATUS_SPECS
end

function Overview.RegisterProvider(id, provider)
    if type(id) ~= "string" or id == "" or type(provider) ~= "function" then return false end
    providers[id] = provider
    return true
end
M.RegisterLayerOverviewProvider = Overview.RegisterProvider

--- Normalizes a provider descriptor into the "layer" or "strata" row stored under its id.
local function AddRow(target, kind, descriptor)
    if type(descriptor) ~= "table" then return end
    local id = tostring(descriptor.id or "")
    if id == "" then return end
    local row = {
        id = id,
        kind = kind,
        area = tostring(descriptor.area or "MSUF"),
        scope = tostring(descriptor.scope or "Shared"),
        label = tostring(descriptor.label or descriptor.settingKey or id),
        enabled = descriptor.enabled ~= false,
        inherited = descriptor.inherited == true,
        settingKey = descriptor.settingKey,
        edit = descriptor.edit,
    }
    if kind == "layer" then
        row.layer = Layer(descriptor.value, descriptor.default)
        row.automatic = descriptor.automatic == true
    else
        row.strata = Strata(descriptor.value, descriptor.default)
    end
    target[id] = row
end

local function CollectRows(includeLegacyStrata)
    local layerByID = {}
    local strataByID = includeLegacyStrata and {} or nil
    local sink = {
        Layer = function(_, descriptor) AddRow(layerByID, "layer", descriptor) end,
        Strata = function(_, descriptor)
            if includeLegacyStrata then AddRow(strataByID, "strata", descriptor) end
        end,
    }
    local ids = SortedKeys(providers)
    for i = 1, #ids do
        local provider = providers[ids[i]]
        if type(provider) == "function" then provider(sink) end
    end
    local layers, strataRows = {}, {}
    for _, row in pairs(layerByID) do layers[#layers + 1] = row end
    if strataByID then
        for _, row in pairs(strataByID) do strataRows[#strataRows + 1] = row end
    end
    sort(layers, function(a, b)
        if a.layer ~= b.layer then return a.layer > b.layer end
        if a.area ~= b.area then return a.area < b.area end
        if a.scope ~= b.scope then return a.scope < b.scope end
        return a.label < b.label
    end)
    if strataByID then
        sort(strataRows, function(a, b)
            local ar, br = STRATA_RANK[a.strata] or 0, STRATA_RANK[b.strata] or 0
            if ar ~= br then return ar > br end
            if a.area ~= b.area then return a.area < b.area end
            if a.scope ~= b.scope then return a.scope < b.scope end
            return a.label < b.label
        end)
    end
    return layers, strataRows
end

function Overview.CollectLayerOverviewRows()
    local layers = CollectRows()
    return layers
end

function Overview.CollectFrameStrataRows()
    local _, strataRows = CollectRows(true)
    return strataRows
end

M.CollectLayerOverviewRows = Overview.CollectLayerOverviewRows
M.CollectFrameStrataRows = Overview.CollectFrameStrataRows
ExportPublic("MSUF_CollectLayerOverviewRows", Overview.CollectLayerOverviewRows)
ExportPublic("MSUF_CollectFrameStrataRows", Overview.CollectFrameStrataRows)

-- Text rows of the unit frame provider: key, label, default layer, show flag, show default, alternate show flag.
local UNIT_TEXT_ROWS = {
    { key = "nameTextLayer", label = "Name Text", default = 5, show = "showName", defaultShow = true },
    { key = "hpTextLayer", label = "Health Text", default = 5, show = "showHP", defaultShow = true },
    { key = "powerTextLayer", label = "Power Text", default = 2, show = "showPowerText", defaultShow = false, alternateShow = "showPower" },
}

--- One unit frame layer row: the value and its inheritance come from the unit profile.
local function UnitLayerRow(sink, db, scope, area, key, label, default, enabled, mode, legacyKey)
    local value, inherited = ReadUnitValue(db, scope.key, key, default, legacyKey)
    sink:Layer({
        id = "unit." .. scope.key .. "." .. key,
        area = area, scope = scope.label, label = label,
        value = value, default = default, enabled = enabled, inherited = inherited,
        settingKey = scope.key .. "." .. key,
        edit = { kind = "unit", scope = scope.key, key = key, mode = mode },
    })
end

Overview.RegisterProvider("unit-frames", function(sink)
    local db = DB()
    for i = 1, #UNIT_SCOPES do
        local scope = UNIT_SCOPES[i]
        local key = scope.key
        for j = 1, #UNIT_TEXT_ROWS do
            local spec = UNIT_TEXT_ROWS[j]
            local shown = ReadUnitBool(db, key, spec.show, spec.defaultShow)
            if not shown and spec.alternateShow then shown = ReadUnitBool(db, key, spec.alternateShow, false) end
            UnitLayerRow(sink, db, scope, "Unit Frames", spec.key, spec.label, spec.default, shown)
        end
        UnitLayerRow(sink, db, scope, "Unit Frames", "detachedPowerBarFrameLevelOffset", "Detached Power Bar", 6,
            ReadUnitBool(db, key, "showPowerBar", true) and ReadUnitBool(db, key, "powerBarDetached", false), "detached-power")
        local portraitMode = tostring((type(db[key]) == "table" and db[key].portraitMode) or "OFF"):upper()
        UnitLayerRow(sink, db, scope, "Unit Frames", "portraitLevelOffset", "Portrait", 7, portraitMode ~= "OFF", "portrait")
        for slot = 1, 3 do
            local prefix = slot == 1 and "texLayer" or ("texLayer" .. slot)
            UnitLayerRow(sink, db, scope, "Unit Texture Layers", prefix .. "Level", string.format(Tr("Texture Layer %s"), tostring(slot)),
                1, ReadUnitBool(db, key, prefix .. "Enabled", false), "texture-layer")
        end
        UnitLayerRow(sink, db, scope, "Unit Status", "unitDispelSymbolLayer", "Dispel Symbol", 8,
            ReadUnitBool(db, key, "unitDispelSymbolEnabled", false), "dispel-symbol")
    end

    local specs = UnitStatusSpecs()
    for i = 1, #UNIT_SCOPES do
        local scope = UNIT_SCOPES[i]
        local seen = {}
        for j = 1, #specs do
            local spec = specs[j]
            local key = type(spec) == "table" and spec.layer or nil
            if type(key) == "string" and key ~= "" and not seen[key] and UnitStatusAllowed(spec, scope.key) then
                seen[key] = true
                UnitLayerRow(sink, db, scope, "Unit Status", key, key == "leaderIconLayer" and "Leader / Assist Icons" or (spec.text or key),
                    spec.defaultLayer or 7, ReadUnitBool(db, scope.key, spec.show, spec.defaultShow ~= false), nil, spec.legacyLayer)
            end
        end
    end
end)

local function EffectiveAuraValue(auras, scope, key, fallback)
    local shared = type(auras.shared) == "table" and auras.shared or nil
    local perUnit = type(auras.perUnit) == "table" and auras.perUnit or nil
    local pu = perUnit and perUnit[scope.runtimeKey]
    local layout = type(pu) == "table" and pu.overrideLayout == true and type(pu.layout) == "table" and pu.layout or nil
    local sharedLayout = type(pu) == "table" and pu.overrideSharedLayout == true and type(pu.layoutShared) == "table" and pu.layoutShared or nil
    if layout and layout[key] ~= nil then return layout[key], false end
    if sharedLayout and sharedLayout[key] ~= nil then return sharedLayout[key], false end
    if shared and shared[key] ~= nil then return shared[key], true end
    return fallback, true
end

local AURA_LANES = {
    { key = "buff", label = "Buffs", layer = "buffLayer", strata = "buffStrata", defaultLayer = 5, show = "showBuffs", max = "maxBuffs", defaultMax = 8 },
    { key = "debuff", label = "Debuffs", layer = "debuffLayer", strata = "debuffStrata", defaultLayer = 6, show = "showDebuffs",
        max = "maxDebuffs", defaultMax = 12 },
}

--- The Buff / Debuff lane rows of one unit scope: layer and strata share one enabled state.
local function AuraLaneRows(sink, auras, scope, unitEnabled)
    local shared = type(auras.shared) == "table" and auras.shared or {}
    for j = 1, #AURA_LANES do
        local lane = AURA_LANES[j]
        local maxIcons = EffectiveAuraValue(auras, scope, lane.max, lane.defaultMax)
        local enabled = unitEnabled and shared[lane.show] ~= false and Number(maxIcons, lane.defaultMax) > 0
        local function Emit(kind, key, default)
            local value, inherited = EffectiveAuraValue(auras, scope, key, default)
            sink[kind](sink, {
                id = "auras3." .. scope.key .. "." .. key,
                area = "Unit Auras", scope = scope.label, label = lane.label,
                value = value, default = default, enabled = enabled, inherited = inherited,
                settingKey = "auras3." .. scope.key .. "." .. key,
                edit = { kind = "aura-lane", scope = scope.key, lane = lane.key },
            })
        end
        Emit("Layer", lane.layer, lane.defaultLayer)
        Emit("Strata", lane.strata, "AUTO")
    end
end

--- The four custom container slots of one unit scope, each with its full-frame effect block.
local function AuraCustomRows(sink, auras, scope, unitEnabled)
    local customRoot = type(auras.customContainers) == "table" and auras.customContainers or nil
    local customPerUnit = customRoot and type(customRoot.perUnit) == "table" and customRoot.perUnit or nil
    local record = customPerUnit and customPerUnit[scope.key]
    local items = type(record) == "table" and type(record.items) == "table" and record.items or nil
    for index = 1, 4 do
        local item = items and items[index]
        local present = type(item) == "table"
        local token = tostring(present and item.id or index)
        local fallback = index == 4
            and (scope.key == "player" and "Defensive Buffs" or "Dots on target")
            or M.Format("Custom %d", index)
        local label = tostring(present and item.name or fallback)
        local enabled = present and unitEnabled and item.enabled == true
        local frame = present and type(item.frame) == "table" and item.frame or nil
        local frameEnabled = enabled == true and frame ~= nil and frame.type ~= nil and frame.type ~= "none"
        local frameLabel = string.format(Tr("%s Full-Frame Effect"), Tr(label))
        local function Emit(kind, suffix, rowLabel, value, default, rowEnabled, editKind)
            sink[kind](sink, {
                id = "auras3." .. scope.key .. ".custom." .. token .. "." .. suffix,
                area = "Unit Auras", scope = scope.label, label = rowLabel,
                value = value, default = default, enabled = rowEnabled,
                settingKey = "auras3.customContainers." .. scope.key .. "." .. index .. "." .. suffix,
                edit = { kind = editKind, scope = scope.key, index = index },
            })
        end
        Emit("Layer", "layer", label, present and item.layer or nil, 9, enabled, "aura-custom")
        Emit("Strata", "strata", M.Format("%s Icons", Tr(label)), present and item.strata or nil, "AUTO", enabled, "aura-custom")
        Emit("Layer", "frame.layer", frameLabel, frame and frame.layer, 0, frameEnabled, "aura-custom-frame")
        Emit("Strata", "frame.strata", frameLabel, frame and frame.strata, "AUTO", frameEnabled, "aura-custom-frame")
    end
end

Overview.RegisterProvider("unit-auras", function(sink)
    local auras = DB().auras3
    auras = type(auras) == "table" and auras or {}
    local rootEnabled = auras.enabled ~= false
    for i = 1, #UNIT_AURA_SCOPES do
        local scope = UNIT_AURA_SCOPES[i]
        local unitEnabled = rootEnabled and BoolValue(auras[scope.flag], scope.flagDefault)
        AuraLaneRows(sink, auras, scope, unitEnabled)
        AuraCustomRows(sink, auras, scope, unitEnabled)
    end
end)

local GROUP_TEXT_ROWS = {
    { key = "nameTextLayer", label = "Name Text", default = 5, show = "showName", defaultShow = true },
    { key = "textLayer", label = "Health Text", default = 5, show = "showHPText", defaultShow = true },
    { key = "powerTextLayer", label = "Power Text", default = 2, show = "showPowerText", defaultShow = false, alternateShow = "showPower" },
}
local GROUP_AURA_LANES = {
    { key = "buff", label = "Buffs", defaultLayer = 5 },
    { key = "debuff", label = "Debuffs", defaultLayer = 6 },
    { key = "externals", label = "External Defensives", defaultLayer = 7 },
}
local function CornerEnabled(conf) return BoolValue(conf.ciEnabled, true) end
local function OverlayEnabled(conf) return conf.dispelOverlayEnabled == true end
--- Group rows read straight from the group profile: { kind, area, key, label, default, enabled(conf) }.
local GROUP_PROFILE_ROWS = {
    { "Layer", "Group Status", "groupNumberLayer", "Group Number", 7, function(conf) return conf.showGroupNumber == true end },
    { "Layer", "Group Frames", "detachedPowerBarFrameLevelOffset", "Detached Power Bar", 6,
        function(conf) return conf.powerBarEnabled == true and conf.powerBarDetached == true end },
    { "Layer", "Group Status", "dispelSymbolLayer", "Dispel Symbol", 8, function(conf) return conf.dispelSymbolEnabled == true end },
    { "Layer", "Group Status", "ciLayer", "Corner Indicators", 7, CornerEnabled },
    { "Strata", "Group Status", "ciStrata", "Corner Indicators", "AUTO", CornerEnabled },
    { "Strata", "Group Bars", "dispelOverlayStrata", "Dispel Overlay", "AUTO", OverlayEnabled },
    { "Layer", "Group Bars", "dispelOverlayLayer", "Dispel Overlay", 0, OverlayEnabled },
}

--- One group frame row. `key` is the id and setting suffix (and, split at the dots, the edit
--- path); `extra` may carry a different `setting` suffix, `path`, `mode` and `inherited`.
local function GroupRow(sink, g, kind, area, key, label, value, default, enabled, extra)
    extra = extra or {}
    local path = extra.path
    if not path then
        path = {}
        for part in key:gmatch("[^.]+") do path[#path + 1] = part end
    end
    sink[kind](sink, {
        id = "group." .. g.scope.key .. "." .. key,
        area = area, scope = g.scope.label, label = label,
        value = value, default = default, enabled = enabled, inherited = extra.inherited,
        settingKey = g.scope.dbKey .. "." .. (extra.setting or key),
        edit = { kind = "group", scope = g.scope.key, dbKey = g.scope.dbKey, path = path, mode = extra.mode },
    })
end

local function GroupProfileRows(sink, g, statusSpecs)
    local conf, on = g.conf, g.on
    for j = 1, #GROUP_TEXT_ROWS do
        local spec = GROUP_TEXT_ROWS[j]
        local shown = BoolValue(conf[spec.show], spec.defaultShow)
        if not shown and spec.alternateShow then shown = BoolValue(conf[spec.alternateShow], false) end
        GroupRow(sink, g, "Layer", "Group Frames", spec.key, spec.label, conf[spec.key], spec.default, on and shown)
    end
    if g.scope.key == "party" then
        local portraitMode = tostring(conf.portraitMode or "OFF"):upper()
        GroupRow(sink, g, "Layer", "Group Frames", "portraitLevelOffset", "Portrait", conf.portraitLevelOffset, 7,
            on and (portraitMode == "LEFT" or portraitMode == "RIGHT"), { mode = "config" })
    end
    for j = 1, #statusSpecs do
        local spec = statusSpecs[j]
        if type(spec) == "table" and type(spec.layer) == "string" and spec.layer ~= "" then
            GroupRow(sink, g, "Layer", "Group Status", spec.layer, spec.text or spec.layer, conf[spec.layer],
                spec.defaultLayer or 7, on and BoolValue(conf[spec.enabled], true))
        end
    end
    for j = 1, #GROUP_PROFILE_ROWS do
        local row = GROUP_PROFILE_ROWS[j]
        GroupRow(sink, g, row[1], row[2], row[3], row[4], conf[row[3]], row[5], on and row[6](conf))
    end
end

local function GroupAuraRows(sink, g)
    local auraRoot = type(g.conf.auras) == "table" and g.conf.auras or {}
    for j = 1, #GROUP_AURA_LANES do
        local laneSpec = GROUP_AURA_LANES[j]
        local lane = type(auraRoot[laneSpec.key]) == "table" and auraRoot[laneSpec.key] or {}
        local enabled = g.on and auraRoot.enabled ~= false and lane.enabled ~= false
        local prefix = "auras." .. laneSpec.key
        GroupRow(sink, g, "Layer", "Group Auras", prefix .. ".layer", laneSpec.label, lane.layer, laneSpec.defaultLayer, enabled,
            { mode = "auras" })
        GroupRow(sink, g, "Strata", "Group Auras", prefix .. ".strata", laneSpec.label, lane.strata, "AUTO", enabled,
            { mode = "auras" })
    end
end

local function GroupSpellRows(sink, g)
    local spell = type(g.conf.spellIndicators) == "table" and g.conf.spellIndicators or {}
    local spellEnabled = g.on and spell.enabled == true
    local baseLayer = Layer(spell.layer, 9)
    GroupRow(sink, g, "Layer", "Spell Indicators", "spellIndicators.layer", "Default", baseLayer, 9, spellEnabled)
    GroupRow(sink, g, "Strata", "Spell Indicators", "spellIndicators.strata", "Default Icons", spell.strata, "AUTO", spellEnabled)
    local specs = type(spell.specs) == "table" and spell.specs or nil
    local specKeys = SortedKeys(specs)
    for specIndex = 1, #specKeys do
        local specKey = specKeys[specIndex]
        local specItems = type(specs[specKey]) == "table" and specs[specKey] or nil
        local auraKeys = SortedKeys(specItems)
        for auraIndex = 1, #auraKeys do
            local auraKey = auraKeys[auraIndex]
            local item = type(specItems[auraKey]) == "table" and specItems[auraKey] or nil
            if item then
                local token = tostring(specKey) .. "." .. tostring(auraKey)
                local label = tostring(item.display or auraKey) .. " [" .. tostring(specKey) .. "]"
                local enabled = spellEnabled and item.enabled ~= false
                local frame = type(item.frame) == "table" and item.frame or nil
                local frameEnabled = enabled == true and frame ~= nil and frame.type ~= nil and frame.type ~= "none"
                local frameLabel = string.format(Tr("%s Frame Effect"), Tr(label))
                local function Emit(kind, tail, rowLabel, value, default, rowEnabled, path, inherited)
                    GroupRow(sink, g, kind, "Spell Indicators", "spellIndicators." .. token .. "." .. tail, rowLabel, value, default, rowEnabled,
                        { setting = "spellIndicators.specs." .. token .. "." .. tail, path = path, inherited = inherited })
                end
                Emit("Layer", "layer", label, item.layer, baseLayer, enabled,
                    { "spellIndicators", "specs", specKey, auraKey, "layer" }, item.layer == nil)
                Emit("Strata", "strata", M.Format("%s Icon", Tr(label)), item.strata, "AUTO", enabled,
                    { "spellIndicators", "specs", specKey, auraKey, "strata" })
                Emit("Layer", "frame.layer", frameLabel, frame and frame.layer, 0, frameEnabled,
                    { "spellIndicators", "specs", specKey, auraKey, "frame", "layer" })
                Emit("Strata", "frame.strata", frameLabel, frame and frame.strata, "AUTO", frameEnabled,
                    { "spellIndicators", "specs", specKey, auraKey, "frame", "strata" })
            end
        end
    end
end

Overview.RegisterProvider("group-frames", function(sink)
    local db = DB()
    local statusSpecs = GroupStatusSpecs()
    for i = 1, #GROUP_SCOPES do
        local scope = GROUP_SCOPES[i]
        local conf = type(db[scope.dbKey]) == "table" and db[scope.dbKey] or {}
        local g = { scope = scope, conf = conf, on = conf.enabled == true }
        GroupProfileRows(sink, g, statusSpecs)
        GroupAuraRows(sink, g)
        GroupSpellRows(sink, g)
    end
end)

Overview.RegisterProvider("castbars", function(sink)
    local db = DB()
    local general = type(db.general) == "table" and db.general or {}
    local rows = {
        { key = "player", label = "Player", prefix = "castbarPlayer" },
        { key = "target", label = "Target", prefix = "castbarTarget" },
        { key = "focus", label = "Focus", prefix = "castbarFocus" },
        { key = "boss", label = "Boss", prefix = "bossCast" },
        { key = "arena", label = "Arena", prefix = "arenaCast" },
    }
    if M.FilterSupportedUnitValues then M.FilterSupportedUnitValues(rows) end
    for i = 1, #rows do
        local row = rows[i]
        local rootKey = row.prefix .. "FrameLevelOffset"
        local iconKey = row.prefix .. "IconFrameLevelOffset"
        local rootLayer = Layer(general[rootKey], 6)
        sink:Layer({
            id = "castbar." .. row.key .. ".root",
            area = "Castbars", scope = row.label, label = "Whole Castbar",
            value = rootLayer, default = 6, settingKey = "general." .. rootKey,
            edit = { kind = "general", key = rootKey, mode = "castbar" },
        })
        local iconValue = Number(general[iconKey], 0)
        sink:Layer({
            id = "castbar." .. row.key .. ".icon",
            area = "Castbars", scope = row.label, label = iconValue <= 0 and "Icon (follows castbar)" or "Icon",
            value = iconValue <= 0 and rootLayer or iconValue, default = rootLayer,
            inherited = iconValue <= 0, settingKey = "general." .. iconKey,
            edit = { kind = "general", key = iconKey, mode = "castbar-icon" },
        })
    end
end)

-- The arena PvP trinket icon (Arena page > PvP Trinket). Its value, factory
-- layer and visibility come from the trinket runtime; clients without arena
-- frames list no row.
Overview.RegisterProvider("arena-trinket", function(sink)
    local scopes = { { key = "arena", label = "Arena" } }
    if M.FilterSupportedUnitValues then M.FilterSupportedUnitValues(scopes) end
    if #scopes == 0 then return end
    local runtime = MSUF.ArenaTrinkets
    local arena = DB().arena
    sink:Layer({
        id = "unit.arena.trinketLayer",
        area = "Unit Status", scope = scopes[1].label, label = "PvP Trinket",
        value = type(arena) == "table" and arena.trinketLayer or nil, default = runtime.DEFAULTS.layer,
        enabled = runtime.Shown(), settingKey = "arena.trinketLayer",
        edit = { kind = "unit", scope = "arena", key = "trinketLayer" },
    })
end)

local function ClassPowerShown(bars) return bars.showClassPower ~= false end
--- Player class resource rows: { bars key, label, default layer, enabled(bars) }.
local CLASS_RESOURCE_ROWS = {
    { "classPowerFrameLevelOffset", "Class Resource Bar", 5, ClassPowerShown },
    { "classPowerTextLayer", "Class Resource Text", 5, ClassPowerShown },
    { "playerHPBarFrameLevelOffset", "Secondary Health Bar", 7, function(bars) return bars.playerHPBarEnabled == true end },
}

--- Outline value of a bar scope: its own override when set, else the shared bars value.
local function BarOutlineValue(bars, scope, conf, key)
    if scope.key == "shared" then return bars[key], false end
    if conf and conf.hlOverride == true and conf[key] ~= nil then return conf[key], false end
    return bars[key], true
end

Overview.RegisterProvider("class-resources", function(sink)
    local db = DB()
    local bars = type(db.bars) == "table" and db.bars or {}
    for i = 1, #CLASS_RESOURCE_ROWS do
        local row = CLASS_RESOURCE_ROWS[i]
        sink:Layer({
            id = "class-resources." .. row[1],
            area = "Class Resources", scope = "Player", label = row[2],
            value = bars[row[1]], default = row[3],
            enabled = row[4](bars),
            settingKey = "bars." .. row[1],
            edit = { kind = "class-resources", key = row[1] },
        })
    end

    for i = 1, #BAR_SCOPES do
        local scope = BAR_SCOPES[i]
        local conf = type(db[scope.key]) == "table" and db[scope.key] or nil
        local settingScope = scope.key == "shared" and "bars" or scope.key
        local function Emit(kind, key, default, edit)
            local value, inherited = BarOutlineValue(bars, scope, conf, key)
            sink[kind](sink, {
                id = "bars." .. scope.key .. "." .. key,
                area = "Global Bars", scope = scope.label, label = "Frame Outline",
                value = value, default = default, inherited = inherited,
                settingKey = settingScope .. "." .. key,
                edit = edit,
            })
        end
        Emit("Layer", "barOutlineLayer", 0, { kind = "bar-outline", scope = scope.key, key = "barOutlineLayer" })
        Emit("Strata", "barOutlineStrata", "AUTO", { kind = "bar-outline", scope = scope.key })
    end
end)

local function EnsureChild(parent, key)
    if type(parent) ~= "table" then return nil end
    local child = parent[key]
    if type(child) ~= "table" then
        child = {}
        parent[key] = child
    end
    return child
end

local function WriteNested(root, path, value)
    if type(root) ~= "table" or type(path) ~= "table" or #path == 0 then return false end
    local target = root
    for i = 1, #path - 1 do
        target = EnsureChild(target, path[i])
        if not target then return false end
    end
    local key = path[#path]
    if target[key] == value then return false end
    target[key] = value
    return true
end

local function BarOutlineScopeKeys(scope)
    local globalPage = M.GlobalPage
    if globalPage and type(globalPage.ScopeDBKeys) == "function" then
        local keys = globalPage.ScopeDBKeys(scope)
        if type(keys) == "table" and #keys > 0 then return keys end
    end
    if scope == "gf_raid" or scope == "gf_mythicraid" then
        return { "gf_raid", "gf_mythicraid" }
    end
    return { scope }
end

local function WriteBarOutlineScope(scope, key, value)
    local db = DB()
    if scope == "shared" then
        local bars = EnsureChild(db, "bars")
        if not bars or bars[key] == value then return false end
        bars[key] = value
        return true
    end

    local changed = false
    local keys = BarOutlineScopeKeys(scope)
    for i = 1, #keys do
        local conf = EnsureChild(db, keys[i])
        if conf then
            if conf.hlOverride ~= true or conf[key] ~= value then changed = true end
            conf.hlOverride = true
            conf[key] = value
        end
    end
    return changed
end

local function BarOutlineApplyScope(scope)
    if scope == "gf_mythicraid" then return "gf_raid" end
    return scope
end

local function RunLayerHistory(row, callback, fieldLabel)
    if type(M.RunWithHistory) == "function" then
        return M.RunWithHistory(M.TranslatedHistoryLabel(M.Format("%s: %s", Tr(fieldLabel or "Layer"), Tr(tostring(row.label)))),
            "layer-overview:" .. tostring(row.id), callback)
    end
    return callback()
end

local function RequestAuras(edit, reason)
    local apply = M.ApplyService
    if apply and type(apply.RequestAuras) == "function" then apply.RequestAuras(edit.scope, reason) end
end

local function AuraMenuModel()
    return MSUF.MSUF_Auras3 and MSUF.MSUF_Auras3.MenuModel
end

--- Writes field on a custom aura container (or on its frame block) in one
--- history step and queues the aura apply; false when nothing changed.
local function WriteCustomContainerField(row, edit, field, value, reason, fieldLabel)
    local model = AuraMenuModel()
    if type(model) ~= "table" or type(model.CustomContainer) ~= "function" then return false end
    return RunLayerHistory(row, function()
        local item = model.CustomContainer(edit.scope, edit.index, true)
        if type(item) ~= "table" then return false end
        local target = edit.kind == "aura-custom-frame" and EnsureChild(item, "frame") or item
        if not target or target[field] == value then return false end
        target[field] = value
        RequestAuras(edit, reason)
        return true
    end, fieldLabel) ~= false
end

--- Writes an aura lane layer or strata (model writer `writer`) in one history step.
local function WriteAuraLane(row, edit, writer, value, reason, fieldLabel)
    local model = AuraMenuModel()
    if type(model) ~= "table" or type(model[writer]) ~= "function" then return false end
    return RunLayerHistory(row, function()
        model[writer](edit.scope, edit.lane, value)
        RequestAuras(edit, reason)
        return true
    end, fieldLabel) ~= false
end

--- Writes a bar outline layer or strata for its scope and queues the bars apply.
local function WriteBarOutline(row, edit, key, value, reason, fieldLabel)
    return RunLayerHistory(row, function()
        if not WriteBarOutlineScope(edit.scope, key, value) then return false end
        if type(M.RequestGeneralDomains) == "function" then
            M.RequestGeneralDomains(reason, {
                preview = true, applyAll = false, bars = true,
                barsScope = BarOutlineApplyScope(edit.scope),
            })
        end
        return true
    end, fieldLabel) ~= false
end
local AURA_RENDERER_PATH = { "auras", "renderer" }

--- Writes a group frame setting at edit.path in one history step and queues
--- the group refresh (the Group page's queue when it is loaded).
local function WriteGroupField(row, edit, value, reason, fieldLabel)
    return RunLayerHistory(row, function()
        local conf = EnsureChild(DB(), edit.dbKey)
        if not WriteNested(conf, edit.path, value) then return false end
        -- Group Aura lanes only render in the CUSTOM renderer; the edit has to show.
        if edit.path[1] == "auras" then WriteNested(conf, AURA_RENDERER_PATH, "CUSTOM") end
        local groupPage = M.GroupPage
        if groupPage and type(groupPage.QueueGF) == "function" then
            groupPage.QueueGF(edit.scope, edit.mode or "visual")
        elseif M.ApplyService and type(M.ApplyService.RequestGroup) == "function" then
            M.ApplyService.RequestGroup(edit.scope, edit.mode or "visual", reason)
        end
        return true
    end, fieldLabel) ~= false
end

function Overview.SetLayerValue(row, value)
    if type(row) ~= "table" or type(row.edit) ~= "table" then return false end
    if type(M.BlockCombatAction) == "function" and M.BlockCombatAction() then return false end
    if row.edit.kind == "external" and type(row.edit.set) == "function" then
        if type(value) == "string" and value:lower() == "auto" then value = -1 end
        value = tonumber(value)
        if not value or value < -1 or value > 30 or value ~= floor(value) then return false end
        return row.edit.set(row.edit, value) == true
    end
    value = Layer(value, row.layer)
    if row.inherited and value == row.layer then return true end
    local edit = row.edit
    local reason = "MSUF2_LAYER_OVERVIEW_EDIT"

    if edit.kind == "unit" then
        if type(M.SetUnitValue) == "function" then
            local opts
            if edit.mode == "detached-power" then
                opts = { power = true, detachedPowerBar = true, preview = true }
            elseif edit.mode == "portrait" then
                opts = { portrait = true, preview = true }
            elseif edit.mode == "texture-layer" then
                opts = { preview = true, applyAll = false }
            elseif edit.mode == "dispel-symbol" then
                opts = { auras = true, preview = true }
            else
                opts = { text = true, preview = true }
            end
            return M.SetUnitValue(edit.scope, edit.key, value, reason, opts) ~= false
        end
        local db = DB()
        local conf = EnsureChild(db, edit.scope)
        if not conf or conf[edit.key] == value then return false end
        conf[edit.key] = value
        return true
    end

    if edit.kind == "general" then
        if type(M.SetGeneralValue) == "function" then
            return M.SetGeneralValue(edit.key, value, reason, {
                castbar = edit.mode == "castbar" or edit.mode == "castbar-icon",
                preview = true, applyAll = false,
            }) ~= false
        end
        local db = DB()
        local general = EnsureChild(db, "general")
        if not general or general[edit.key] == value then return false end
        general[edit.key] = value
        return true
    end

    if edit.kind == "aura-lane" then return WriteAuraLane(row, edit, "WriteLaneLayer", value, reason) end
    if edit.kind == "aura-custom" or edit.kind == "aura-custom-frame" then
        return WriteCustomContainerField(row, edit, "layer", value, reason)
    end
    if edit.kind == "group" then return WriteGroupField(row, edit, value, reason) end

    if edit.kind == "class-resources" then
        return RunLayerHistory(row, function()
            local bars = EnsureChild(DB(), "bars")
            if not bars or bars[edit.key] == value then return false end
            bars[edit.key] = value
            local apply = M.ApplyService
            if apply and type(apply.RequestClassPowerDomains) == "function" then
                apply.RequestClassPowerDomains(reason, { full = true, cdm = true, playerHP = true },
                    { preview = true, applyAll = false, classpower = true })
            end
            return true
        end) ~= false
    end

    if edit.kind == "bar-outline" then return WriteBarOutline(row, edit, "barOutlineLayer", value, reason) end
    return false
end

ExportPublic("MSUF_SetLayerOverviewValue", Overview.SetLayerValue)

function Overview.SetStrataValue(row, value)
    if type(row) ~= "table" or type(row.edit) ~= "table" then return false end
    if type(M.BlockCombatAction) == "function" and M.BlockCombatAction() then return false end
    value = Strata(value, row.strata)
    local edit = row.edit
    local reason = "MSUF2_STRATA_OVERVIEW_EDIT"

    if edit.kind == "aura-lane" then return WriteAuraLane(row, edit, "WriteLaneStrata", value, reason, "FrameStrata") end
    if edit.kind == "aura-custom" or edit.kind == "aura-custom-frame" then
        return WriteCustomContainerField(row, edit, "strata", value, reason, "FrameStrata")
    end
    if edit.kind == "group" then return WriteGroupField(row, edit, value, reason, "FrameStrata") end
    if edit.kind == "bar-outline" then return WriteBarOutline(row, edit, "barOutlineStrata", value, reason, "FrameStrata") end
    return false
end

ExportPublic("MSUF_SetStrataOverviewValue", Overview.SetStrataValue)

local FALLBACK_COLORS = {
    success = { 0.30, 1.00, 0.62, 1 }, accent = { 0.42, 0.78, 1.00, 1 },
    muted = { 0.62, 0.72, 0.86, 1 }, text = { 0.88, 0.94, 1.00, 1 },
}
local function Color(name)
    return (T.colors or {})[name] or FALLBACK_COLORS[name]
end

local function SetFontColor(fontString, color, alpha)
    if not (fontString and fontString.SetTextColor) then return end
    color = color or { 1, 1, 1, 1 }
    fontString:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, alpha or color[4] or 1)
end

local function Font(parent, template, text, color, role)
    if T.Font then return T.Font(parent, template, text or "", color, role) end
    local fs = PixelLayoutRegion(parent:CreateFontString(nil, "OVERLAY", template))
    fs:SetText(text or "")
    SetFontColor(fs, color)
    return fs
end
local function LeftFont(parent, template, text, color, role)
    local fs = Font(parent, template, text, color, role)
    fs:SetJustifyH("LEFT")
    return fs
end

local SCOPE_LABEL = {
    player = "Player", target = "Target", targettarget = "Target of Target",
    focustarget = "Focus Target", focus = "Focus", pet = "Pet", pettarget = "Pet Target", boss = "Boss", arena = "Arena",
    party = "Party", raid = "Raid", mythicraid = "Mythic Raid",
}
local AREA_ORDER = {
    unit = { "Unit Frames", "Unit Status", "Unit Auras", "Class Resources", "Global Bars" },
    group = { "Group Frames", "Group Status", "Group Bars", "Group Auras", "Spell Indicators", "Global Bars" },
    group_bars = { "Group Bars", "Group Frames", "Group Status", "Group Auras", "Spell Indicators", "Global Bars" },
    group_indicators = { "Group Status", "Spell Indicators", "Group Frames", "Group Auras", "Group Bars", "Global Bars" },
    group_auras = { "Group Auras", "Group Frames", "Group Status", "Spell Indicators", "Group Bars", "Global Bars" },
    auras = { "Unit Auras", "Group Auras" },
    class = { "Class Resources", "Unit Frames", "Unit Status", "Unit Auras", "Global Bars" },
    bars = { "Global Bars", "Class Resources", "Group Bars", "Unit Frames", "Group Frames" },
}

local SUITE_AREA_BY_PAGE = {
    suite_cooldownManager = "Suite Cooldown Manager",
    suite_actionbars = "Suite Action Bars",
    suite_dataTexts = "Suite DataTexts",
    suite_damageMeter = "Suite Damage Meter",
    suite_qualityOfLife = "Suite Quality of Life",
}

local function CurrentLayerContext()
    local key = tostring(M.activeKey or "")
    local unit = key:match("^uf_(.+)$")
    if unit and SCOPE_LABEL[unit] then
        return { key = key, label = SCOPE_LABEL[unit], scopes = { [SCOPE_LABEL[unit]] = true }, order = AREA_ORDER.unit }
    end
    if key:match("^gf_") then
        local scope = tostring(M.gfScope or "party")
        local order = key == "gf_indicators" and AREA_ORDER.group_indicators
            or key == "gf_auras" and AREA_ORDER.group_auras
            or key == "gf_bars" and AREA_ORDER.group_bars or AREA_ORDER.group
        return { key = key, label = SCOPE_LABEL[scope] or "Group Frames", scopes = { [SCOPE_LABEL[scope] or "Party"] = true }, order = order }
    end
    if key:match("^auras3_") then
        local scope = tostring(M.auraScope or "shared")
        local scopes
        if scope == "raid" then
            scopes = {}
            scopes.Raid, scopes["Mythic Raid"] = true, true
        elseif scope ~= "shared" then
            scopes = {}
            scopes[SCOPE_LABEL[scope] or scope] = true
        end
        return { key = key, label = M.Format("%s Auras", Tr(scope == "shared" and "Shared" or (SCOPE_LABEL[scope] or scope))), scopes = scopes,
            areas = { ["Unit Auras"] = true, ["Group Auras"] = true }, order = AREA_ORDER.auras }
    end
    if key == "classpower" then
        return { key = key, label = "Class Resources", scopes = { Player = true }, order = AREA_ORDER.class }
    end
    if key == "opt_bars" then
        return { key = key, label = "Bars", areas = { ["Global Bars"] = true, ["Class Resources"] = true, ["Group Bars"] = true }, order = AREA_ORDER.bars }
    end
    local area = SUITE_AREA_BY_PAGE[key]
    if area then return { key = key, label = area, areas = { [area] = true }, order = { area } } end
    return { key = key, label = "Current menu", all = true, order = {} }
end

local function ContextMatches(row, context)
    if context.all then return true end
    if context.areas and context.areas[row.area] ~= true then return false end
    if context.scopes and context.scopes[row.scope] ~= true then return false end
    return true
end

local function SortForContext(rows, context)
    local rank = {}
    for i = 1, #(context.order or {}) do rank[context.order[i]] = i end
    sort(rows, function(a, b)
        local ar, br = rank[a.area] or 99, rank[b.area] or 99
        if ar ~= br then return ar < br end
        if a.area ~= b.area then return a.area < b.area end
        local av, bv = a.layer or (STRATA_RANK[a.strata] or 0), b.layer or (STRATA_RANK[b.strata] or 0)
        if av ~= bv then return av > bv end
        if a.scope ~= b.scope then return a.scope < b.scope end
        return a.label < b.label
    end)
end

local function PartitionForContext(rows, context)
    local relevant, more = {}, {}
    for i = 1, #rows do
        local target = ContextMatches(rows[i], context) and relevant or more
        target[#target + 1] = rows[i]
    end
    SortForContext(relevant, context)
    return relevant, more
end

local function SearchMatches(row, query)
    if query == "" then return true end
    local haystack = table.concat({ row.area or "", row.scope or "", row.label or "", row.settingKey or "", row.id or "",
        tostring(row.layer or row.strata or "") }, " "):lower()
    for token in query:gmatch("%S+") do
        if not haystack:find(token, 1, true) then return false end
    end
    return true
end

local RebuildPopupRows

local function AcquireVisualRow(popup, index)
    popup._rows = popup._rows or {}
    local row = popup._rows[index]
    if row then return row end
    row = PixelLayoutRegion(CreateFrame("Frame", nil, popup._scrollChild))
    row:SetHeight(22)
    local bg = PixelLayoutRegion(row:CreateTexture(nil, "BACKGROUND"))
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.09, 0.16, 0.24)
    row._bg = bg
    row._value = Font(row, "GameFontHighlightSmall", "", Color("success"), "control")
    row._value:SetJustifyH("CENTER")
    local edit = PixelLayoutRegion(CreateFrame("EditBox", nil, row, "InputBoxTemplate"))
    edit:SetSize(38, 18)
    edit:SetAutoFocus(false)
    edit:SetNumeric(true)
    edit:SetMaxLetters(2)
    edit:SetJustifyH("CENTER")
    if edit.SetTextInsets then edit:SetTextInsets(2, 2, 0, 0) end
    if T.SkinEditBox then T.SkinEditBox(edit) end
    edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    edit:SetScript("OnEnterPressed", function(self)
        local owner = self._ownerRow
        local data = owner and owner._data
        if data then Overview.SetLayerValue(data, self:GetText()) end
        self:ClearFocus()
        if RebuildPopupRows then RebuildPopupRows(popup, true) end
    end)
    edit:SetScript("OnEscapePressed", function(self)
        local data = self._ownerRow and self._ownerRow._data
        self:SetText(data and (data.automatic and "Auto" or tostring(data.layer)) or "")
        self:ClearFocus()
    end)
    row._valueEdit = edit
    row._editTag = LeftFont(row, "GameFontDisableSmall", Tr("EDIT"), Color("success"), "caption")

    local strataEdit = PixelLayoutRegion(CreateFrame("Button", nil, row))
    strataEdit:SetHeight(18)
    strataEdit:EnableMouse(true)
    local strataEdge = PixelLayoutRegion(strataEdit:CreateTexture(nil, "BACKGROUND"))
    strataEdge:SetAllPoints()
    strataEdge:SetColorTexture(0.18, 0.58, 0.92, 0.78)
    local strataBg = PixelLayoutRegion(strataEdit:CreateTexture(nil, "BACKGROUND", nil, 1))
    strataBg:SetPoint("TOPLEFT", strataEdit, "TOPLEFT", 1, -1)
    strataBg:SetPoint("BOTTOMRIGHT", strataEdit, "BOTTOMRIGHT", -1, 1)
    strataBg:SetColorTexture(0.025, 0.070, 0.125, 0.98)
    strataEdit._edge = strataEdge
    strataEdit._label = LeftFont(strataEdit, "GameFontHighlightSmall", "", Color("accent"), "control")
    strataEdit._label:SetPoint("LEFT", strataEdit, "LEFT", 7, 0)
    strataEdit._label:SetPoint("RIGHT", strataEdit, "RIGHT", -18, 0)
    strataEdit._chevron = Font(strataEdit, "GameFontHighlightSmall", "v", Color("accent"), "control")
    strataEdit._chevron:SetPoint("RIGHT", strataEdit, "RIGHT", -6, 1)
    strataEdit:SetScript("OnEnter", function(self)
        self._edge:SetColorTexture(0.30, 0.82, 1.00, 1)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(Tr("Edit FrameStrata"))
            GameTooltip:AddLine(Tr("Click and choose the Blizzard layer."), 0.78, 0.88, 1.00, true)
            GameTooltip:Show()
        end
    end)
    strataEdit:SetScript("OnLeave", function(self)
        self._edge:SetColorTexture(0.18, 0.58, 0.92, 0.78)
        if GameTooltip then GameTooltip:Hide() end
    end)
    strataEdit:SetScript("OnClick", function(self)
        local owner = self._ownerRow
        local data = owner and owner._data
        if not (data and data.edit and type(W.OpenDropdown) == "function") then return end
        W.OpenDropdown(self, FRAME_STRATA_CHOICES, data.strata, function(value)
            Overview.SetStrataValue(data, value)
            if RebuildPopupRows then RebuildPopupRows(popup, true) end
        end)
    end)
    row._strataEdit = strataEdit
    row._area = LeftFont(row, "GameFontDisableSmall", "", Color("muted"), "caption")
    row._label = LeftFont(row, "GameFontHighlightSmall", "", Color("text"), "control")
    if row._label.SetWordWrap then row._label:SetWordWrap(false) end
    popup._rows[index] = row
    return row
end

--- Anchors a pooled row at offset y of its parent and tags its type.
local function PlaceRow(row, y, width, height, rowType)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", 0, -y)
    row:SetSize(width, height)
    row._rowType = rowType
end

--- Turns a pooled row into a one-label strip (section heading or "more" toggle).
local function SetLabelOnlyRow(row, text, inset, justify, color)
    row._data = nil
    row._value:Hide()
    row._valueEdit:Hide()
    row._editTag:Hide()
    row._strataEdit:Hide()
    row._area:Hide()
    row._label:ClearAllPoints()
    row._label:SetPoint("LEFT", row, "LEFT", inset, 0)
    row._label:SetPoint("RIGHT", row, "RIGHT", -inset, 0)
    row._label:SetJustifyH(justify)
    row._label:SetText(text)
    SetFontColor(row._label, color)
    row._label:Show()
end

local function ConfigureSectionRow(row, text, y, width)
    PlaceRow(row, y, width, 28, "section")
    row:EnableMouse(false)
    row:SetScript("OnMouseDown", nil)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row._bg:SetColorTexture(0.05, 0.20, 0.32, 0.28)
    SetLabelOnlyRow(row, text, 8, "LEFT", Color("accent"))
    row:Show()
end

local function LayoutDataRow(row, width, strataMode)
    row:SetWidth(width)
    row._value:ClearAllPoints()
    row._valueEdit:ClearAllPoints()
    row._editTag:ClearAllPoints()
    row._strataEdit:ClearAllPoints()
    row._area:ClearAllPoints()
    row._label:ClearAllPoints()
    if strataMode then
        local valueW = math.max(96, math.min(128, floor(width * 0.25)))
        local areaW = math.max(126, math.min(180, floor(width * 0.34)))
        row._value:SetPoint("LEFT", row, "LEFT", 4, 0)
        row._value:SetWidth(valueW)
        row._strataEdit:SetPoint("LEFT", row, "LEFT", 4, 0)
        row._strataEdit:SetWidth(valueW)
        row._area:SetPoint("LEFT", row, "LEFT", valueW + 12, 0)
        row._area:SetWidth(areaW)
        row._label:SetPoint("LEFT", row, "LEFT", valueW + areaW + 20, 0)
    else
        local areaW = math.max(132, math.min(196, floor(width * 0.36)))
        row._value:SetPoint("LEFT", row, "LEFT", 4, 0)
        row._value:SetWidth(42)
        row._valueEdit:SetPoint("LEFT", row, "LEFT", 6, 0)
        row._editTag:SetPoint("LEFT", row, "LEFT", 47, 0)
        row._editTag:SetWidth(30)
        row._area:SetPoint("LEFT", row, "LEFT", 82, 0)
        row._area:SetWidth(areaW)
        row._label:SetPoint("LEFT", row, "LEFT", areaW + 90, 0)
    end
    row._label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
end

local function ConfigureDataRow(row, data, y, width, alternate, strataMode)
    PlaceRow(row, y, width, 22, "data")
    row._strataMode = strataMode and true or false
    row._data = data
    row:EnableMouse(false)
    row:SetScript("OnMouseDown", nil)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row._label:SetJustifyH("LEFT")
    row._editTag:Hide()
    row._strataEdit:Hide()
    row._bg:SetColorTexture(0.035, 0.080, 0.145, alternate and 0.25 or 0.10)
    LayoutDataRow(row, width, strataMode)
    if strataMode then
        row._value:SetText(data.strata)
        if data.edit then
            row._value:Hide()
            row._strataEdit._ownerRow = row
            row._strataEdit._label:SetText(data.strata)
            row._strataEdit:SetAlpha(data.enabled and 1 or 0.62)
            row._strataEdit:Show()
        else
            row._value:Show()
        end
        row._valueEdit:Hide()
    else
        row._value:SetText(data.automatic and "Auto" or tostring(data.layer))
        if data.edit then
            row._value:Hide()
            row._valueEdit._ownerRow = row
            row._valueEdit:SetNumeric(not data.automatic and data.edit.kind ~= "external")
            row._valueEdit:SetMaxLetters(data.edit.kind == "external" and 4 or 2)
            row._valueEdit:SetText(data.automatic and "Auto" or tostring(data.layer))
            if row._valueEdit.SetTextColor then
                local c = Color("success")
                row._valueEdit:SetTextColor(c[1], c[2], c[3], data.enabled and 1 or 0.62)
            end
            row._valueEdit:Show()
            row._editTag:SetAlpha(data.enabled and 1 or 0.62)
            row._editTag:Show()
        else
            row._value:Show()
            row._valueEdit:Hide()
        end
    end
    local areaText = M.Format("%s / %s", Tr(data.area), Tr(data.scope))
    if data.inherited then areaText = M.Format("%s (shared)", areaText) end
    row._area:SetText(areaText)
    row._label:SetText(data.enabled and Tr(data.label) or M.Format("%s (off)", Tr(data.label)))
    local alpha = data.enabled and 1 or 0.48
    SetFontColor(row._value, Color(strataMode and "accent" or "success"), alpha)
    SetFontColor(row._area, Color("muted"), alpha)
    SetFontColor(row._label, Color("text"), alpha)
    row._area:Show()
    row._label:Show()
    row:Show()
end

local function ConfigureMoreRow(row, text, y, width, popup)
    PlaceRow(row, y, width, 30, "more")
    row._bg:SetColorTexture(0.04, 0.24, 0.20, 0.34)
    SetLabelOnlyRow(row, text, 10, "CENTER", Color("success"))
    row:EnableMouse(true)
    row:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        popup._showMore = not popup._showMore
        RebuildPopupRows(popup)
    end)
    row:SetScript("OnEnter", function(self) self._bg:SetColorTexture(0.05, 0.34, 0.27, 0.48) end)
    row:SetScript("OnLeave", function(self) self._bg:SetColorTexture(0.04, 0.24, 0.20, 0.34) end)
    row:Show()
end

RebuildPopupRows = function(popup, preserveScroll)
    local layers = CollectRows()
    local rows = popup._rows or {}
    for i = 1, #rows do rows[i]:Hide() end
    local width = popup._contentWidth or math.max(414, (popup:GetWidth() or 548) - 56)
    local context = CurrentLayerContext()
    local query = popup._search and tostring(popup._search:GetText() or ""):lower() or ""
    query = query:match("^%s*(.-)%s*$") or ""
    local relevantLayers, moreLayers = PartitionForContext(layers, context)
    if #relevantLayers == 0 then
        relevantLayers, moreLayers = layers, {}
    end
    local rowIndex, y = 0, 0
    local layerEditHint = Tr("EDIT: click green number")
    local function Section(text)
        rowIndex = rowIndex + 1
        ConfigureSectionRow(AcquireVisualRow(popup, rowIndex), text, y, width)
        y = y + 30
    end
    local function DataRows(dataRows)
        for i = 1, #dataRows do
            rowIndex = rowIndex + 1
            ConfigureDataRow(AcquireVisualRow(popup, rowIndex), dataRows[i], y, width, i % 2 == 0, false)
            y = y + 22
        end
    end

    if query ~= "" then
        local foundLayers = {}
        for i = 1, #layers do if SearchMatches(layers[i], query) then foundLayers[#foundLayers + 1] = layers[i] end end
        if #foundLayers > 0 then
            Section(M.Format("Search results - MSUF Layers 0-30 (%d) | %s", #foundLayers, layerEditHint))
            DataRows(foundLayers)
        end
        if #foundLayers == 0 then Section(Tr("No layers match this search.")) end
    else
        if #relevantLayers > 0 then
            Section(M.Format("%s - MSUF Layers 0-30 (%d) | %s", Tr(context.label), #relevantLayers, layerEditHint))
            DataRows(relevantLayers)
        end
        local moreCount = #moreLayers
        if moreCount > 0 then
            y = y + 7
            rowIndex = rowIndex + 1
            ConfigureMoreRow(AcquireVisualRow(popup, rowIndex),
                M.Format(popup._showMore and "Less (%d)" or "More (%d)", moreCount),
                y, width, popup)
            y = y + 32
            if popup._showMore then
                if #moreLayers > 0 then
                    Section(M.Format("All other MSUF Layers 0-30 (%d) | %s", #moreLayers, layerEditHint))
                    DataRows(moreLayers)
                end
            end
        end
    end
    popup._scrollChild:SetSize(width, math.max(y + 4, popup._scroll:GetHeight()))
    popup._count:SetText(M.Format("%d editable Layer numbers (0-30)", #layers))
    popup._context = context
    if not preserveScroll then popup._scroll:SetVerticalScroll(0) end
    if popup._scroll._msuf2RefreshScrollBar then popup._scroll:_msuf2RefreshScrollBar() end
end

local function CapturePopupGeometry(popup, positioned)
    local geometry = Overview.geometry or {}
    Overview.geometry = geometry
    geometry.width, geometry.height = popup:GetWidth(), popup:GetHeight()
    if positioned ~= nil then geometry.positioned = positioned and true or false end
    if geometry.positioned then
        geometry.left, geometry.top = popup:GetLeft(), popup:GetTop()
    end
end

local function ApplyPopupResizeBounds(popup)
    local maxW = math.max(470, math.min(900, (UIParent:GetWidth() or 900) - 24))
    local maxH = math.max(300, math.min(760, (UIParent:GetHeight() or 760) - 24))
    if popup.SetResizeBounds then
        popup:SetResizeBounds(470, 300, maxW, maxH)
    else
        if popup.SetMinResize then popup:SetMinResize(470, 300) end
        if popup.SetMaxResize then popup:SetMaxResize(maxW, maxH) end
    end
end

local function LayoutPopupWidth(popup)
    if not popup._scrollChild then return end
    local width = math.max(414, (popup:GetWidth() or 548) - 56)
    popup._contentWidth = width
    popup._scrollChild:SetWidth(width)
    local rows = popup._rows or {}
    for i = 1, #rows do
        local row = rows[i]
        if row:IsShown() then
            if row._rowType == "data" then LayoutDataRow(row, width, row._strataMode) else row:SetWidth(width) end
        end
    end
end

local function CreatePopup()
    local popup
    if type(M.CreateMenuPopupPanel) == "function" then
        popup = M.CreateMenuPopupPanel(UIParent, { name = "MSUF2LayerOverview", glass = "popup" })
    else
        popup = PixelLayoutRegion(CreateFrame("Frame", "MSUF2LayerOverview", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil))
        if popup.SetBackdrop then
            PixelLayoutRegion(popup, "SetBackdrop", { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            popup:SetBackdropColor(0.014, 0.024, 0.050, 0.985)
            popup:SetBackdropBorderColor(0.10, 0.22, 0.44, 0.80)
        end
    end
    local geometry = Overview.geometry or {}
    popup:SetSize(tonumber(geometry.width) or 548, tonumber(geometry.height) or 390)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetMovable(true)
    if popup.SetResizable then popup:SetResizable(true) end
    popup:RegisterForDrag("LeftButton")
    ApplyPopupResizeBounds(popup)
    popup:Hide()

    popup._title = LeftFont(popup, "GameFontNormal", Tr("Layer Overview"), Color("accent"), "title")
    popup._title:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -12)

    local search = PixelLayoutRegion(CreateFrame("EditBox", nil, popup, "InputBoxTemplate"))
    search:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -46, -10)
    search:SetSize(156, 20)
    search:SetAutoFocus(false)
    search:SetMaxLetters(60)
    if search.SetTextInsets then search:SetTextInsets(6, 6, 0, 0) end
    if T.SkinEditBox then T.SkinEditBox(search) end
    local placeholder = search.Instructions
    if not (placeholder and placeholder.SetText and placeholder.SetPoint) then
        placeholder = PixelLayoutRegion(search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
    elseif placeholder.ClearAllPoints then
        placeholder:ClearAllPoints()
    end
    placeholder:SetPoint("LEFT", search, "LEFT", 7, 0)
    placeholder:SetPoint("RIGHT", search, "RIGHT", -6, 0)
    placeholder:SetJustifyH("LEFT")
    placeholder:SetText(Tr("Search layers..."))
    SetFontColor(placeholder, Color("muted"), 0.80)
    popup._search = search
    popup._searchPlaceholder = placeholder
    popup._title:SetPoint("RIGHT", search, "LEFT", -10, 0)

    popup._count = LeftFont(popup, "GameFontDisableSmall", "", Color("muted"), "caption")
    popup._count:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -35)
    popup._count:SetPoint("RIGHT", popup, "RIGHT", -14, 0)
    local hintBG = PixelLayoutRegion(popup:CreateTexture(nil, "BACKGROUND"))
    hintBG:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, -52)
    hintBG:SetPoint("BOTTOMRIGHT", popup, "TOPRIGHT", -10, -86)
    hintBG:SetColorTexture(0.025, 0.22, 0.16, 0.46)
    popup._hintBG = hintBG
    popup._hint = LeftFont(popup, "GameFontHighlightSmall", Tr("EDITABLE: click a green Layer number, type 0-30, press Enter."),
        Color("success"), "control")
    popup._hint:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -58)
    popup._hint:SetPoint("RIGHT", popup, "RIGHT", -14, 0)

    local close = T.CloseButton and T.CloseButton(popup) or PixelLayoutRegion(CreateFrame("Button", nil, popup, "UIPanelCloseButton"))
    close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -8, -8)
    close._msuf2SkipHistoryCheckpoint = true
    close:SetScript("OnClick", function() popup:Hide() end)
    popup._close = close

    local scroll = PixelLayoutRegion(CreateFrame("ScrollFrame", nil, popup))
    scroll:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -92)
    scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -34, 14)
    local content = PixelLayoutRegion(CreateFrame("Frame", nil, scroll))
    popup._contentWidth = 492
    content:SetSize(popup._contentWidth, 1)
    scroll:SetScrollChild(content)
    popup._scroll = scroll
    popup._scrollChild = content
    if T.StyleScrollFrame then T.StyleScrollFrame(scroll, popup) end

    search:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
        if popup:IsShown() and RebuildPopupRows then RebuildPopupRows(popup) end
    end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end
    end)

    popup:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    popup:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        CapturePopupGeometry(self, true)
    end)
    popup:SetScript("OnSizeChanged", function(self)
        LayoutPopupWidth(self)
    end)
    popup:SetScript("OnHide", function(self)
        self._anchor = nil
        if self._search then self._search:ClearFocus() end
        if W and type(W.CloseDropdown) == "function" then W.CloseDropdown({ immediate = true }) end
    end)

    local grip = PixelLayoutRegion(CreateFrame("Button", nil, popup))
    grip:SetSize(20, 20)
    grip:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(popup:GetFrameLevel() + 20)
    PixelLayoutRegion(grip, "SetNormalTexture", "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    PixelLayoutRegion(grip, "SetHighlightTexture", "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    PixelLayoutRegion(grip, "SetPushedTexture", "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then popup:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        popup:StopMovingOrSizing()
        CapturePopupGeometry(popup, Overview.geometry and Overview.geometry.positioned)
        LayoutPopupWidth(popup)
    end)
    grip:SetScript("OnHide", function() popup:StopMovingOrSizing() end)
    popup._resizeGrip = grip
    LayoutPopupWidth(popup)
    Overview.popup = popup
    return popup
end

function Overview.HideForAnchor(anchor)
    local popup = Overview.popup
    if not (popup and popup._anchor == anchor) then return end
    popup._anchor = nil
    if not (M.frame and M.frame.IsShown and M.frame:IsShown()) then popup:Hide() end
end

function Overview.RefreshContext()
    local popup = Overview.popup
    if not (popup and popup:IsShown()) then return false end
    popup._showMore = false
    RebuildPopupRows(popup)
    return true
end

function Overview.Hide()
    local popup = Overview.popup
    if popup then popup:Hide() end
end

function Overview.Show(anchor)
    local popup = Overview.popup or CreatePopup()
    if popup:IsShown() and popup._anchor == anchor then
        popup:Hide()
        return popup
    end
    popup._showMore = false
    if popup._search and popup._search:GetText() ~= "" then popup._search:SetText("") end
    RebuildPopupRows(popup)
    popup._anchor = anchor
    popup:ClearAllPoints()
    local geometry = Overview.geometry
    if geometry and geometry.positioned and tonumber(geometry.left) and tonumber(geometry.top) then
        popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", geometry.left, geometry.top)
    elseif anchor and anchor.GetTop then
        popup:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 8)
    else
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    if type(M.ApplyPopupFramePriority) == "function" then M.ApplyPopupFramePriority(popup) end
    popup:Show()
    if popup.Raise then popup:Raise() end
    return popup
end

M.ShowLayerOverview = Overview.Show
M.HideLayerOverviewForAnchor = Overview.HideForAnchor
M.RefreshLayerOverviewContext = Overview.RefreshContext
M.HideLayerOverview = Overview.Hide
ExportPublic("MSUF_ShowLayerOverview", Overview.Show)
ExportPublic("MSUF_HideLayerOverviewForAnchor", Overview.HideForAnchor)
