--- Shell/Menu2/MSUF_Menu2_LayerOverview.lua
--- Cold-path, addon-wide overview for the unified numeric MSUF layer scale.
--- Providers only read SavedVariables when the overview is requested; there are
--- no events, timers, or continuously running update scripts in this module.

local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local T = M.Theme or {}
local W = M.Widgets or {}
local Tr = M.TranslateText or M.Tr or function(text) return text end
local floor = math.floor
local sort = table.sort

local Overview = M.LayerOverview or {}
M.LayerOverview = Overview
Overview.providers = Overview.providers or {}
local providers = Overview.providers

local InvokeProvider = M.InvokeBoundary or pcall

local UNIT_SCOPES = {
    { key = "player", label = "Player" },
    { key = "target", label = "Target" },
    { key = "targettarget", label = "Target of Target" },
    { key = "focustarget", label = "Focus Target" },
    { key = "focus", label = "Focus" },
    { key = "pet", label = "Pet" },
    { key = "boss", label = "Boss" },
}
local UNIT_AURA_SCOPES = {
    { key = "player", runtimeKey = "player", label = "Player", flag = "showPlayer", flagDefault = false },
    { key = "target", runtimeKey = "target", label = "Target", flag = "showTarget", flagDefault = true },
    { key = "focus", runtimeKey = "focus", label = "Focus", flag = "showFocus", flagDefault = false },
    { key = "boss", runtimeKey = "boss1", label = "Boss", flag = "showBoss", flagDefault = true },
}
local GROUP_SCOPES = {
    { key = "party", dbKey = "gf_party", label = "Party" },
    { key = "raid", dbKey = "gf_raid", label = "Raid" },
    { key = "mythicraid", dbKey = "gf_mythicraid", label = "Mythic Raid" },
}
local BAR_SCOPES = {
    { key = "shared", label = "Shared" },
    { key = "player", label = "Player" },
    { key = "target", label = "Target" },
    { key = "targettarget", label = "Target of Target" },
    { key = "focustarget", label = "Focus Target" },
    { key = "focus", label = "Focus" },
    { key = "pet", label = "Pet" },
    { key = "boss", label = "Boss" },
    { key = "gf_party", label = "Party" },
    { key = "gf_raid", label = "Raid" },
    { key = "gf_mythicraid", label = "Mythic Raid" },
}

local STRATA_RANK = {
    AUTO = 0,
    BACKGROUND = 1,
    LOW = 2,
    MEDIUM = 3,
    HIGH = 4,
    DIALOG = 5,
    FULLSCREEN = 6,
    FULLSCREEN_DIALOG = 7,
    TOOLTIP = 8,
}
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
    { text = "Raid Group", show = "showRaidGroupInName", defaultShow = false, layer = "raidGroupNameLayer", legacyLayer = "nameTextLayer", defaultLayer = 5, units = "player target targettarget focustarget focus" },
    { text = "Elite / Rare", show = "showEliteIcon", defaultShow = true, layer = "eliteIconLayer", defaultLayer = 7, units = "target focus targettarget focustarget boss" },
    { text = "Dead / Offline Text", show = "statusDeadTextEnabled", defaultShow = true, layer = "statusTextLayer", defaultLayer = 7 },
    { text = "Ghost Text", show = "statusGhostTextEnabled", defaultShow = true, layer = "statusGhostTextLayer", defaultLayer = 7 },
    { text = "AFK Text", show = "statusAFKTextEnabled", defaultShow = false, layer = "statusAFKTextLayer", defaultLayer = 7 },
    { text = "AFK Timer", show = "statusAFKTimerEnabled", defaultShow = false, layer = "statusAFKTimerLayer", defaultLayer = 7 },
    { text = "DND Text", show = "statusDNDTextEnabled", defaultShow = false, layer = "statusDNDTextLayer", defaultLayer = 7 },
    { text = "Combat", show = "showCombatStateIndicator", defaultShow = true, layer = "combatStateIndicatorLayer", defaultLayer = 7, units = "player target" },
    { text = "Rested", show = "showRestingIndicator", defaultShow = false, layer = "restedStateIndicatorLayer", defaultLayer = 7, units = "player" },
    { text = "Incoming Rez", show = "showIncomingResIndicator", defaultShow = true, layer = "incomingResIndicatorLayer", defaultLayer = 7, units = "player target" },
    { text = "PvP Flag", show = "showPvpIndicator", defaultShow = true, layer = "pvpIndicatorLayer", defaultLayer = 7, units = "player target focus targettarget focustarget" },
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
}

local function DB()
    return type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {}
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
        local ok, allowed = InvokeProvider(spec.allowed, unit)
        return ok and allowed == true
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

local function AddLayerRow(target, descriptor)
    if type(descriptor) ~= "table" then return end
    local id = tostring(descriptor.id or "")
    if id == "" then return end
    target[id] = {
        id = id,
        kind = "layer",
        area = tostring(descriptor.area or "MSUF"),
        scope = tostring(descriptor.scope or "Shared"),
        label = tostring(descriptor.label or descriptor.settingKey or id),
        layer = Layer(descriptor.value, descriptor.default),
        enabled = descriptor.enabled ~= false,
        inherited = descriptor.inherited == true,
        settingKey = descriptor.settingKey,
        edit = descriptor.edit,
    }
end

local function AddStrataRow(target, descriptor)
    if type(descriptor) ~= "table" then return end
    local id = tostring(descriptor.id or "")
    if id == "" then return end
    target[id] = {
        id = id,
        kind = "strata",
        area = tostring(descriptor.area or "MSUF"),
        scope = tostring(descriptor.scope or "Shared"),
        label = tostring(descriptor.label or descriptor.settingKey or id),
        strata = Strata(descriptor.value, descriptor.default),
        enabled = descriptor.enabled ~= false,
        inherited = descriptor.inherited == true,
        settingKey = descriptor.settingKey,
        edit = descriptor.edit,
    }
end

local function CollectRows(includeLegacyStrata)
    local layerByID = {}
    local strataByID = includeLegacyStrata and {} or nil
    local sink = {
        Layer = function(_, descriptor) AddLayerRow(layerByID, descriptor) end,
        Strata = includeLegacyStrata
            and function(_, descriptor) AddStrataRow(strataByID, descriptor) end
            or function() end,
    }
    local ids = SortedKeys(providers)
    for i = 1, #ids do
        local provider = providers[ids[i]]
        if type(provider) == "function" then InvokeProvider(provider, sink) end
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

Overview.RegisterProvider("unit-frames", function(sink)
    local db = DB()
    local text = {
        { key = "nameTextLayer", label = "Name Text", default = 5, show = "showName", defaultShow = true },
        { key = "hpTextLayer", label = "Health Text", default = 5, show = "showHP", defaultShow = true },
        { key = "powerTextLayer", label = "Power Text", default = 2, show = "showPowerText", defaultShow = false, alternateShow = "showPower" },
    }
    for i = 1, #UNIT_SCOPES do
        local scope = UNIT_SCOPES[i]
        for j = 1, #text do
            local spec = text[j]
            local value, inherited = ReadUnitValue(db, scope.key, spec.key, spec.default)
            local shown = ReadUnitBool(db, scope.key, spec.show, spec.defaultShow)
            if not shown and spec.alternateShow then shown = ReadUnitBool(db, scope.key, spec.alternateShow, false) end
            sink:Layer({
                id = "unit." .. scope.key .. "." .. spec.key,
                area = "Unit Frames", scope = scope.label, label = spec.label,
                value = value, default = spec.default, enabled = shown, inherited = inherited,
                settingKey = scope.key .. "." .. spec.key,
                edit = { kind = "unit", scope = scope.key, key = spec.key },
            })
        end
        local detached, inherited = ReadUnitValue(db, scope.key, "detachedPowerBarFrameLevelOffset", 6)
        sink:Layer({
            id = "unit." .. scope.key .. ".detachedPowerBarFrameLevelOffset",
            area = "Unit Frames", scope = scope.label, label = "Detached Power Bar",
            value = detached, default = 6,
            enabled = ReadUnitBool(db, scope.key, "showPowerBar", true) and ReadUnitBool(db, scope.key, "powerBarDetached", false),
            inherited = inherited, settingKey = scope.key .. ".detachedPowerBarFrameLevelOffset",
            edit = { kind = "unit", scope = scope.key, key = "detachedPowerBarFrameLevelOffset", mode = "detached-power" },
        })
        local portrait, portraitInherited = ReadUnitValue(db, scope.key, "portraitLevelOffset", 7)
        local portraitMode = tostring((type(db[scope.key]) == "table" and db[scope.key].portraitMode) or "OFF"):upper()
        sink:Layer({
            id = "unit." .. scope.key .. ".portraitLevelOffset",
            area = "Unit Frames", scope = scope.label, label = "Portrait",
            value = portrait, default = 7, enabled = portraitMode ~= "OFF",
            inherited = portraitInherited, settingKey = scope.key .. ".portraitLevelOffset",
            edit = { kind = "unit", scope = scope.key, key = "portraitLevelOffset", mode = "portrait" },
        })
        for slot = 1, 3 do
            local prefix = slot == 1 and "texLayer" or ("texLayer" .. slot)
            local value, layerInherited = ReadUnitValue(db, scope.key, prefix .. "Level", 1)
            sink:Layer({
                id = "unit." .. scope.key .. "." .. prefix .. "Level",
                area = "Unit Texture Layers", scope = scope.label, label = string.format(Tr("Texture Layer %s"), tostring(slot)),
                value = value, default = 1,
                enabled = ReadUnitBool(db, scope.key, prefix .. "Enabled", false),
                inherited = layerInherited, settingKey = scope.key .. "." .. prefix .. "Level",
                edit = { kind = "unit", scope = scope.key, key = prefix .. "Level", mode = "texture-layer" },
            })
        end
        local dispelLayer, dispelInherited = ReadUnitValue(db, scope.key, "unitDispelSymbolLayer", 8)
        sink:Layer({
            id = "unit." .. scope.key .. ".unitDispelSymbolLayer",
            area = "Unit Status", scope = scope.label, label = "Dispel Symbol",
            value = dispelLayer, default = 8,
            enabled = ReadUnitBool(db, scope.key, "unitDispelSymbolEnabled", false),
            inherited = dispelInherited, settingKey = scope.key .. ".unitDispelSymbolLayer",
            edit = { kind = "unit", scope = scope.key, key = "unitDispelSymbolLayer", mode = "dispel-symbol" },
        })
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
                local value, inherited = ReadUnitValue(db, scope.key, key, spec.defaultLayer or 7, spec.legacyLayer)
                local label = key == "leaderIconLayer" and "Leader / Assist Icons" or (spec.text or key)
                sink:Layer({
                    id = "unit." .. scope.key .. "." .. key,
                    area = "Unit Status", scope = scope.label, label = label,
                    value = value, default = spec.defaultLayer or 7,
                    enabled = ReadUnitBool(db, scope.key, spec.show, spec.defaultShow ~= false),
                    inherited = inherited, settingKey = scope.key .. "." .. key,
                    edit = { kind = "unit", scope = scope.key, key = key },
                })
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

Overview.RegisterProvider("unit-auras", function(sink)
    local db = DB()
    local auras = type(db.auras3) == "table" and db.auras3 or {}
    local shared = type(auras.shared) == "table" and auras.shared or {}
    local rootEnabled = auras.enabled ~= false
    local lanes = {
        { key = "buff", label = "Buffs", layer = "buffLayer", strata = "buffStrata", defaultLayer = 5, show = "showBuffs", max = "maxBuffs", defaultMax = 8 },
        { key = "debuff", label = "Debuffs", layer = "debuffLayer", strata = "debuffStrata", defaultLayer = 6, show = "showDebuffs", max = "maxDebuffs", defaultMax = 12 },
    }
    for i = 1, #UNIT_AURA_SCOPES do
        local scope = UNIT_AURA_SCOPES[i]
        local unitEnabled = rootEnabled and BoolValue(auras[scope.flag], scope.flagDefault)
        for j = 1, #lanes do
            local lane = lanes[j]
            local value, inherited = EffectiveAuraValue(auras, scope, lane.layer, lane.defaultLayer)
            local maxIcons = EffectiveAuraValue(auras, scope, lane.max, lane.defaultMax)
            sink:Layer({
                id = "auras3." .. scope.key .. "." .. lane.layer,
                area = "Unit Auras", scope = scope.label, label = lane.label,
                value = value, default = lane.defaultLayer,
                enabled = unitEnabled and shared[lane.show] ~= false and Number(maxIcons, lane.defaultMax) > 0,
                inherited = inherited, settingKey = "auras3." .. scope.key .. "." .. lane.layer,
                edit = { kind = "aura-lane", scope = scope.key, lane = lane.key },
            })
            local strata, strataInherited = EffectiveAuraValue(auras, scope, lane.strata, "AUTO")
            sink:Strata({
                id = "auras3." .. scope.key .. "." .. lane.strata,
                area = "Unit Auras", scope = scope.label, label = lane.label,
                value = strata, default = "AUTO",
                enabled = unitEnabled and shared[lane.show] ~= false and Number(maxIcons, lane.defaultMax) > 0,
                inherited = strataInherited, settingKey = "auras3." .. scope.key .. "." .. lane.strata,
                edit = { kind = "aura-lane", scope = scope.key, lane = lane.key },
            })
        end

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
                or ("Custom " .. index)
            local label = tostring(present and item.name or fallback)
            local enabled = present and unitEnabled and item.enabled == true
            sink:Layer({
                id = "auras3." .. scope.key .. ".custom." .. token .. ".layer",
                area = "Unit Auras", scope = scope.label, label = label,
                value = present and item.layer or nil, default = 9, enabled = enabled,
                settingKey = "auras3.customContainers." .. scope.key .. "." .. index .. ".layer",
                edit = { kind = "aura-custom", scope = scope.key, index = index },
            })
            sink:Strata({
                id = "auras3." .. scope.key .. ".custom." .. token .. ".strata",
                area = "Unit Auras", scope = scope.label, label = label .. " Icons",
                value = present and item.strata or nil, default = "AUTO", enabled = enabled,
                settingKey = "auras3.customContainers." .. scope.key .. "." .. index .. ".strata",
                edit = { kind = "aura-custom", scope = scope.key, index = index },
            })
            local frame = present and type(item.frame) == "table" and item.frame or nil
            sink:Layer({
                id = "auras3." .. scope.key .. ".custom." .. token .. ".frame.layer",
                area = "Unit Auras", scope = scope.label, label = string.format(Tr("%s Full-Frame Effect"), Tr(label)),
                value = frame and frame.layer, default = 0,
                enabled = enabled and frame and frame.type ~= nil and frame.type ~= "none",
                settingKey = "auras3.customContainers." .. scope.key .. "." .. index .. ".frame.layer",
                edit = { kind = "aura-custom-frame", scope = scope.key, index = index },
            })
            sink:Strata({
                id = "auras3." .. scope.key .. ".custom." .. token .. ".frame.strata",
                area = "Unit Auras", scope = scope.label, label = string.format(Tr("%s Full-Frame Effect"), Tr(label)),
                value = frame and frame.strata, default = "AUTO",
                enabled = enabled and frame and frame.type ~= nil and frame.type ~= "none",
                settingKey = "auras3.customContainers." .. scope.key .. "." .. index .. ".frame.strata",
                edit = { kind = "aura-custom-frame", scope = scope.key, index = index },
            })
        end
    end
end)

Overview.RegisterProvider("group-frames", function(sink)
    local db = DB()
    local text = {
        { key = "nameTextLayer", label = "Name Text", default = 5, show = "showName", defaultShow = true },
        { key = "textLayer", label = "Health Text", default = 5, show = "showHPText", defaultShow = true },
        { key = "powerTextLayer", label = "Power Text", default = 2, show = "showPowerText", defaultShow = false, alternateShow = "showPower" },
    }
    local statusSpecs = GroupStatusSpecs()
    for i = 1, #GROUP_SCOPES do
        local scope = GROUP_SCOPES[i]
        local conf = type(db[scope.dbKey]) == "table" and db[scope.dbKey] or {}
        local frameEnabled = conf.enabled == true
        for j = 1, #text do
            local spec = text[j]
            local shown = BoolValue(conf[spec.show], spec.defaultShow)
            if not shown and spec.alternateShow then shown = BoolValue(conf[spec.alternateShow], false) end
            sink:Layer({
                id = "group." .. scope.key .. "." .. spec.key,
                area = "Group Frames", scope = scope.label, label = spec.label,
                value = conf[spec.key], default = spec.default, enabled = frameEnabled and shown,
                settingKey = scope.dbKey .. "." .. spec.key,
                edit = { kind = "group", scope = scope.key, dbKey = scope.dbKey, path = { spec.key } },
            })
        end
        if scope.key == "party" then
            local portraitMode = tostring(conf.portraitMode or "OFF"):upper()
            sink:Layer({
                id = "group.party.portraitLevelOffset",
                area = "Group Frames", scope = scope.label, label = "Portrait",
                value = conf.portraitLevelOffset, default = 7,
                enabled = frameEnabled and (portraitMode == "LEFT" or portraitMode == "RIGHT"),
                settingKey = "gf_party.portraitLevelOffset",
                edit = {
                    kind = "group", scope = "party", dbKey = "gf_party",
                    path = { "portraitLevelOffset" }, mode = "config",
                },
            })
        end
        for j = 1, #statusSpecs do
            local spec = statusSpecs[j]
            if type(spec) == "table" and type(spec.layer) == "string" and spec.layer ~= "" then
                sink:Layer({
                    id = "group." .. scope.key .. "." .. spec.layer,
                    area = "Group Status", scope = scope.label, label = spec.text or spec.layer,
                    value = conf[spec.layer], default = spec.defaultLayer or 7,
                    enabled = frameEnabled and BoolValue(conf[spec.enabled], true),
                    settingKey = scope.dbKey .. "." .. spec.layer,
                    edit = { kind = "group", scope = scope.key, dbKey = scope.dbKey, path = { spec.layer } },
                })
            end
        end
        sink:Layer({
            id = "group." .. scope.key .. ".groupNumberLayer",
            area = "Group Status", scope = scope.label, label = "Group Number",
            value = conf.groupNumberLayer, default = 7,
            enabled = frameEnabled and conf.showGroupNumber == true,
            settingKey = scope.dbKey .. ".groupNumberLayer",
            edit = { kind = "group", scope = scope.key, dbKey = scope.dbKey, path = { "groupNumberLayer" } },
        })
        sink:Layer({
            id = "group." .. scope.key .. ".detachedPowerBarFrameLevelOffset",
            area = "Group Frames", scope = scope.label, label = "Detached Power Bar",
            value = conf.detachedPowerBarFrameLevelOffset, default = 6,
            enabled = frameEnabled and conf.powerBarEnabled == true and conf.powerBarDetached == true,
            settingKey = scope.dbKey .. ".detachedPowerBarFrameLevelOffset",
            edit = { kind = "group", scope = scope.key, dbKey = scope.dbKey, path = { "detachedPowerBarFrameLevelOffset" } },
        })
        sink:Layer({
            id = "group." .. scope.key .. ".dispelSymbolLayer",
            area = "Group Status", scope = scope.label, label = "Dispel Symbol",
            value = conf.dispelSymbolLayer, default = 8,
            enabled = frameEnabled and conf.dispelSymbolEnabled == true,
            settingKey = scope.dbKey .. ".dispelSymbolLayer",
            edit = { kind = "group", scope = scope.key, dbKey = scope.dbKey, path = { "dispelSymbolLayer" } },
        })
        sink:Layer({
            id = "group." .. scope.key .. ".ciLayer",
            area = "Group Status", scope = scope.label, label = "Corner Indicators",
            value = conf.ciLayer, default = 7,
            enabled = frameEnabled and BoolValue(conf.ciEnabled, true),
            settingKey = scope.dbKey .. ".ciLayer",
            edit = { kind = "group", scope = scope.key, dbKey = scope.dbKey, path = { "ciLayer" } },
        })
        sink:Strata({
            id = "group." .. scope.key .. ".ciStrata",
            area = "Group Status", scope = scope.label, label = "Corner Indicators",
            value = conf.ciStrata, default = "AUTO",
            enabled = frameEnabled and BoolValue(conf.ciEnabled, true),
            settingKey = scope.dbKey .. ".ciStrata",
            edit = { kind = "group", scope = scope.key, dbKey = scope.dbKey, path = { "ciStrata" } },
        })
        sink:Strata({
            id = "group." .. scope.key .. ".dispelOverlayStrata",
            area = "Group Bars", scope = scope.label, label = "Dispel Overlay",
            value = conf.dispelOverlayStrata, default = "AUTO",
            enabled = frameEnabled and conf.dispelOverlayEnabled == true,
            settingKey = scope.dbKey .. ".dispelOverlayStrata",
            edit = { kind = "group", scope = scope.key, dbKey = scope.dbKey, path = { "dispelOverlayStrata" } },
        })
        sink:Layer({
            id = "group." .. scope.key .. ".dispelOverlayLayer",
            area = "Group Bars", scope = scope.label, label = "Dispel Overlay",
            value = conf.dispelOverlayLayer, default = 0,
            enabled = frameEnabled and conf.dispelOverlayEnabled == true,
            settingKey = scope.dbKey .. ".dispelOverlayLayer",
            edit = { kind = "group", scope = scope.key, dbKey = scope.dbKey, path = { "dispelOverlayLayer" } },
        })

        local auraRoot = type(conf.auras) == "table" and conf.auras or {}
        local auraLanes = {
            { key = "buff", label = "Buffs", defaultLayer = 5 },
            { key = "debuff", label = "Debuffs", defaultLayer = 6 },
            { key = "externals", label = "External Defensives", defaultLayer = 7 },
        }
        for j = 1, #auraLanes do
            local laneSpec = auraLanes[j]
            local lane = type(auraRoot[laneSpec.key]) == "table" and auraRoot[laneSpec.key] or {}
            local enabled = frameEnabled and auraRoot.enabled ~= false and lane.enabled ~= false
            sink:Layer({
                id = "group." .. scope.key .. ".auras." .. laneSpec.key .. ".layer",
                area = "Group Auras", scope = scope.label, label = laneSpec.label,
                value = lane.layer, default = laneSpec.defaultLayer, enabled = enabled,
                settingKey = scope.dbKey .. ".auras." .. laneSpec.key .. ".layer",
                edit = { kind = "group", scope = scope.key, dbKey = scope.dbKey, path = { "auras", laneSpec.key, "layer" }, mode = "auras" },
            })
            sink:Strata({
                id = "group." .. scope.key .. ".auras." .. laneSpec.key .. ".strata",
                area = "Group Auras", scope = scope.label, label = laneSpec.label,
                value = lane.strata, default = "AUTO", enabled = enabled,
                settingKey = scope.dbKey .. ".auras." .. laneSpec.key .. ".strata",
                edit = { kind = "group", scope = scope.key, dbKey = scope.dbKey, path = { "auras", laneSpec.key, "strata" }, mode = "auras" },
            })
        end

        local spell = type(conf.spellIndicators) == "table" and conf.spellIndicators or {}
        local spellEnabled = frameEnabled and spell.enabled == true
        local baseLayer = Layer(spell.layer, 9)
        sink:Layer({
            id = "group." .. scope.key .. ".spellIndicators.layer",
            area = "Spell Indicators", scope = scope.label, label = "Default",
            value = baseLayer, default = 9, enabled = spellEnabled,
            settingKey = scope.dbKey .. ".spellIndicators.layer",
            edit = { kind = "group", scope = scope.key, dbKey = scope.dbKey, path = { "spellIndicators", "layer" } },
        })
        sink:Strata({
            id = "group." .. scope.key .. ".spellIndicators.strata",
            area = "Spell Indicators", scope = scope.label, label = "Default Icons",
            value = spell.strata, default = "AUTO", enabled = spellEnabled,
            settingKey = scope.dbKey .. ".spellIndicators.strata",
            edit = { kind = "group", scope = scope.key, dbKey = scope.dbKey, path = { "spellIndicators", "strata" } },
        })
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
                    sink:Layer({
                        id = "group." .. scope.key .. ".spellIndicators." .. token .. ".layer",
                        area = "Spell Indicators", scope = scope.label, label = label,
                        value = item.layer, default = 9, enabled = enabled,
                        settingKey = scope.dbKey .. ".spellIndicators.specs." .. token .. ".layer",
                        edit = { kind = "group", scope = scope.key, dbKey = scope.dbKey, path = { "spellIndicators", "specs", specKey, auraKey, "layer" } },
                    })
                    sink:Strata({
                        id = "group." .. scope.key .. ".spellIndicators." .. token .. ".strata",
                        area = "Spell Indicators", scope = scope.label, label = label .. " Icon",
                        value = item.strata, default = "AUTO", enabled = enabled,
                        settingKey = scope.dbKey .. ".spellIndicators.specs." .. token .. ".strata",
                        edit = { kind = "group", scope = scope.key, dbKey = scope.dbKey, path = { "spellIndicators", "specs", specKey, auraKey, "strata" } },
                    })
                    local frame = type(item.frame) == "table" and item.frame or nil
                    sink:Layer({
                        id = "group." .. scope.key .. ".spellIndicators." .. token .. ".frame.layer",
                        area = "Spell Indicators", scope = scope.label, label = string.format(Tr("%s Frame Effect"), Tr(label)),
                        value = frame and frame.layer, default = 0,
                        enabled = enabled and frame and frame.type ~= nil and frame.type ~= "none",
                        settingKey = scope.dbKey .. ".spellIndicators.specs." .. token .. ".frame.layer",
                        edit = { kind = "group", scope = scope.key, dbKey = scope.dbKey, path = { "spellIndicators", "specs", specKey, auraKey, "frame", "layer" } },
                    })
                    sink:Strata({
                        id = "group." .. scope.key .. ".spellIndicators." .. token .. ".frame.strata",
                        area = "Spell Indicators", scope = scope.label, label = string.format(Tr("%s Frame Effect"), Tr(label)),
                        value = frame and frame.strata, default = "AUTO",
                        enabled = enabled and frame and frame.type ~= nil and frame.type ~= "none",
                        settingKey = scope.dbKey .. ".spellIndicators.specs." .. token .. ".frame.strata",
                        edit = { kind = "group", scope = scope.key, dbKey = scope.dbKey, path = { "spellIndicators", "specs", specKey, auraKey, "frame", "strata" } },
                    })
                end
            end
        end
    end

end)

Overview.RegisterProvider("castbars", function(sink)
    local db = DB()
    local general = type(db.general) == "table" and db.general or {}
    local rows = {
        { scope = "player", label = "Player", prefix = "castbarPlayer" },
        { scope = "target", label = "Target", prefix = "castbarTarget" },
        { scope = "focus", label = "Focus", prefix = "castbarFocus" },
        { scope = "boss", label = "Boss", prefix = "bossCast" },
    }
    for i = 1, #rows do
        local row = rows[i]
        local rootKey = row.prefix .. "FrameLevelOffset"
        local iconKey = row.prefix .. "IconFrameLevelOffset"
        local rootLayer = Layer(general[rootKey], 6)
        sink:Layer({
            id = "castbar." .. row.scope .. ".root",
            area = "Castbars", scope = row.label, label = "Whole Castbar",
            value = rootLayer, default = 6, settingKey = "general." .. rootKey,
            edit = { kind = "general", key = rootKey, mode = "castbar" },
        })
        local iconValue = Number(general[iconKey], 0)
        sink:Layer({
            id = "castbar." .. row.scope .. ".icon",
            area = "Castbars", scope = row.label, label = "Icon" .. (iconValue <= 0 and " (follows castbar)" or ""),
            value = iconValue <= 0 and rootLayer or iconValue, default = rootLayer,
            inherited = iconValue <= 0, settingKey = "general." .. iconKey,
            edit = { kind = "general", key = iconKey, mode = "castbar-icon" },
        })
    end
end)

Overview.RegisterProvider("class-resources", function(sink)
    local db = DB()
    local bars = type(db.bars) == "table" and db.bars or {}
    sink:Layer({
        id = "class-resources.classPowerFrameLevelOffset",
        area = "Class Resources", scope = "Player", label = "Class Resource Bar",
        value = bars.classPowerFrameLevelOffset, default = 5,
        enabled = bars.showClassPower ~= false,
        settingKey = "bars.classPowerFrameLevelOffset",
        edit = { kind = "class-resources", key = "classPowerFrameLevelOffset" },
    })
    sink:Layer({
        id = "class-resources.classPowerTextLayer",
        area = "Class Resources", scope = "Player", label = "Class Resource Text",
        value = bars.classPowerTextLayer, default = 5,
        enabled = bars.showClassPower ~= false,
        settingKey = "bars.classPowerTextLayer",
        edit = { kind = "class-resources", key = "classPowerTextLayer" },
    })
    sink:Layer({
        id = "class-resources.playerHPBarFrameLevelOffset",
        area = "Class Resources", scope = "Player", label = "Secondary Health Bar",
        value = bars.playerHPBarFrameLevelOffset, default = 7,
        enabled = bars.playerHPBarEnabled == true,
        settingKey = "bars.playerHPBarFrameLevelOffset",
        edit = { kind = "class-resources", key = "playerHPBarFrameLevelOffset" },
    })

    for i = 1, #BAR_SCOPES do
        local scope = BAR_SCOPES[i]
        local value, layerValue, inherited, layerInherited
        if scope.key == "shared" then
            value = bars.barOutlineStrata
            layerValue = bars.barOutlineLayer
            inherited = false
            layerInherited = false
        else
            local conf = type(db[scope.key]) == "table" and db[scope.key] or nil
            if conf and conf.hlOverride == true and conf.barOutlineStrata ~= nil then
                value = conf.barOutlineStrata
                inherited = false
            else
                value = bars.barOutlineStrata
                inherited = true
            end
            if conf and conf.hlOverride == true and conf.barOutlineLayer ~= nil then
                layerValue = conf.barOutlineLayer
                layerInherited = false
            else
                layerValue = bars.barOutlineLayer
                layerInherited = true
            end
        end
        sink:Layer({
            id = "bars." .. scope.key .. ".barOutlineLayer",
            area = "Global Bars", scope = scope.label, label = "Frame Outline",
            value = layerValue, default = 0, inherited = layerInherited,
            settingKey = (scope.key == "shared" and "bars" or scope.key) .. ".barOutlineLayer",
            edit = { kind = "bar-outline", scope = scope.key, key = "barOutlineLayer" },
        })
        sink:Strata({
            id = "bars." .. scope.key .. ".barOutlineStrata",
            area = "Global Bars", scope = scope.label, label = "Frame Outline",
            value = value, default = "AUTO", inherited = inherited,
            settingKey = (scope.key == "shared" and "bars" or scope.key) .. ".barOutlineStrata",
            edit = { kind = "bar-outline", scope = scope.key },
        })
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
        return M.RunWithHistory((fieldLabel or "Layer") .. ": " .. tostring(row.label), "layer-overview:" .. tostring(row.id), callback)
    end
    return callback()
end

function Overview.SetLayerValue(row, value)
    if type(row) ~= "table" or type(row.edit) ~= "table" then return false end
    if type(M.BlockCombatAction) == "function" and M.BlockCombatAction() then return false end
    value = Layer(value, row.layer)
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

    if edit.kind == "aura-lane" then
        local model = MSUF.MSUF_Auras3 and MSUF.MSUF_Auras3.MenuModel
        if type(model) ~= "table" or type(model.WriteLaneLayer) ~= "function" then return false end
        return RunLayerHistory(row, function()
            model.WriteLaneLayer(edit.scope, edit.lane, value)
            local apply = M.ApplyService
            if apply and type(apply.RequestAuras) == "function" then apply.RequestAuras(edit.scope, reason) end
            return true
        end) ~= false
    end

    if edit.kind == "aura-custom" or edit.kind == "aura-custom-frame" then
        local model = MSUF.MSUF_Auras3 and MSUF.MSUF_Auras3.MenuModel
        if type(model) ~= "table" or type(model.CustomContainer) ~= "function" then return false end
        return RunLayerHistory(row, function()
            local item = model.CustomContainer(edit.scope, edit.index, true)
            if type(item) ~= "table" then return false end
            local target = edit.kind == "aura-custom-frame" and EnsureChild(item, "frame") or item
            if not target or target.layer == value then return false end
            target.layer = value
            local apply = M.ApplyService
            if apply and type(apply.RequestAuras) == "function" then apply.RequestAuras(edit.scope, reason) end
            return true
        end) ~= false
    end

    if edit.kind == "group" then
        return RunLayerHistory(row, function()
            local db = DB()
            local conf = EnsureChild(db, edit.dbKey)
            if not WriteNested(conf, edit.path, value) then return false end
            local groupPage = M.GroupPage
            if groupPage and type(groupPage.QueueGF) == "function" then
                groupPage.QueueGF(edit.scope, edit.mode or "visual")
            elseif M.ApplyService and type(M.ApplyService.RequestGroup) == "function" then
                M.ApplyService.RequestGroup(edit.scope, edit.mode or "visual", reason)
            end
            return true
        end) ~= false
    end

    if edit.kind == "class-resources" then
        return RunLayerHistory(row, function()
            local bars = EnsureChild(DB(), "bars")
            if not bars or bars[edit.key] == value then return false end
            bars[edit.key] = value
            local apply = M.ApplyService
            if apply and type(apply.RequestClassPower) == "function" then
                apply.RequestClassPower(reason, { full = true, cdm = true, playerHP = true },
                    { preview = true, applyAll = false, classpower = true })
            end
            return true
        end) ~= false
    end

    if edit.kind == "bar-outline" then
        return RunLayerHistory(row, function()
            if not WriteBarOutlineScope(edit.scope, "barOutlineLayer", value) then return false end
            if type(M.RequestGeneralApply) == "function" then
                M.RequestGeneralApply(reason, {
                    preview = true, applyAll = false, bars = true,
                    barsScope = BarOutlineApplyScope(edit.scope),
                })
            end
            return true
        end) ~= false
    end
    return false
end

M.SetLayerOverviewValue = Overview.SetLayerValue
ExportPublic("MSUF_SetLayerOverviewValue", Overview.SetLayerValue)

function Overview.SetStrataValue(row, value)
    if type(row) ~= "table" or type(row.edit) ~= "table" then return false end
    if type(M.BlockCombatAction) == "function" and M.BlockCombatAction() then return false end
    value = Strata(value, row.strata)
    local edit = row.edit
    local reason = "MSUF2_STRATA_OVERVIEW_EDIT"

    if edit.kind == "aura-lane" then
        local model = MSUF.MSUF_Auras3 and MSUF.MSUF_Auras3.MenuModel
        if type(model) ~= "table" or type(model.WriteLaneStrata) ~= "function" then return false end
        return RunLayerHistory(row, function()
            model.WriteLaneStrata(edit.scope, edit.lane, value)
            local apply = M.ApplyService
            if apply and type(apply.RequestAuras) == "function" then apply.RequestAuras(edit.scope, reason) end
            return true
        end, "FrameStrata") ~= false
    end

    if edit.kind == "aura-custom" or edit.kind == "aura-custom-frame" then
        local model = MSUF.MSUF_Auras3 and MSUF.MSUF_Auras3.MenuModel
        if type(model) ~= "table" or type(model.CustomContainer) ~= "function" then return false end
        return RunLayerHistory(row, function()
            local item = model.CustomContainer(edit.scope, edit.index, true)
            if type(item) ~= "table" then return false end
            local target = item
            if edit.kind == "aura-custom-frame" then target = EnsureChild(item, "frame") end
            if not target or target.strata == value then return false end
            target.strata = value
            local apply = M.ApplyService
            if apply and type(apply.RequestAuras) == "function" then apply.RequestAuras(edit.scope, reason) end
            return true
        end, "FrameStrata") ~= false
    end

    if edit.kind == "group" then
        return RunLayerHistory(row, function()
            local conf = EnsureChild(DB(), edit.dbKey)
            if not WriteNested(conf, edit.path, value) then return false end
            local groupPage = M.GroupPage
            if groupPage and type(groupPage.QueueGF) == "function" then
                groupPage.QueueGF(edit.scope, edit.mode or "visual")
            elseif M.ApplyService and type(M.ApplyService.RequestGroup) == "function" then
                M.ApplyService.RequestGroup(edit.scope, edit.mode or "visual", reason)
            end
            return true
        end, "FrameStrata") ~= false
    end

    if edit.kind == "bar-outline" then
        return RunLayerHistory(row, function()
            if not WriteBarOutlineScope(edit.scope, "barOutlineStrata", value) then return false end
            if type(M.RequestGeneralApply) == "function" then
                M.RequestGeneralApply(reason, {
                    preview = true, applyAll = false, bars = true,
                    barsScope = BarOutlineApplyScope(edit.scope),
                })
            end
            return true
        end, "FrameStrata") ~= false
    end
    return false
end

M.SetStrataOverviewValue = Overview.SetStrataValue
ExportPublic("MSUF_SetStrataOverviewValue", Overview.SetStrataValue)

local function Color(name, fallback)
    local colors = T.colors or {}
    return colors[name] or fallback
end

local function SetFontColor(fontString, color, alpha)
    if not (fontString and fontString.SetTextColor) then return end
    color = color or { 1, 1, 1, 1 }
    fontString:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, alpha or color[4] or 1)
end

local function Font(parent, template, text, color, role)
    local fs
    if T.Font then
        fs = T.Font(parent, template, text or "", color, role)
    else
        fs = parent:CreateFontString(nil, "OVERLAY", template)
        fs:SetText(text or "")
        SetFontColor(fs, color)
    end
    return fs
end

local SCOPE_LABEL = {
    player = "Player", target = "Target", targettarget = "Target of Target",
    focustarget = "Focus Target", focus = "Focus", pet = "Pet", boss = "Boss",
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
        return { key = key, label = (scope == "shared" and "Shared" or (SCOPE_LABEL[scope] or scope)) .. " Auras", scopes = scopes, areas = { ["Unit Auras"] = true, ["Group Auras"] = true }, order = AREA_ORDER.auras }
    end
    if key == "classpower" then
        return { key = key, label = "Class Resources", scopes = { Player = true }, order = AREA_ORDER.class }
    end
    if key == "opt_bars" then
        return { key = key, label = "Bars", areas = { ["Global Bars"] = true, ["Class Resources"] = true, ["Group Bars"] = true }, order = AREA_ORDER.bars }
    end
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
    local haystack = table.concat({ row.area or "", row.scope or "", row.label or "", row.settingKey or "", row.id or "", tostring(row.layer or row.strata or "") }, " "):lower()
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
    row = CreateFrame("Frame", nil, popup._scrollChild)
    row:SetHeight(22)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.09, 0.16, 0.24)
    row._bg = bg
    row._value = Font(row, "GameFontHighlightSmall", "", Color("success", { 0.30, 1.00, 0.62, 1 }), "control")
    row._value:SetJustifyH("CENTER")
    local edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
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
        self:SetText(data and tostring(data.layer) or "")
        self:ClearFocus()
    end)
    row._valueEdit = edit
    row._editTag = Font(row, "GameFontDisableSmall", Tr("EDIT"), Color("success", { 0.30, 1.00, 0.62, 1 }), "caption")
    row._editTag:SetJustifyH("LEFT")

    local strataEdit = CreateFrame("Button", nil, row)
    strataEdit:SetHeight(18)
    strataEdit:EnableMouse(true)
    local strataEdge = strataEdit:CreateTexture(nil, "BACKGROUND")
    strataEdge:SetAllPoints()
    strataEdge:SetColorTexture(0.18, 0.58, 0.92, 0.78)
    local strataBg = strataEdit:CreateTexture(nil, "BACKGROUND", nil, 1)
    strataBg:SetPoint("TOPLEFT", strataEdit, "TOPLEFT", 1, -1)
    strataBg:SetPoint("BOTTOMRIGHT", strataEdit, "BOTTOMRIGHT", -1, 1)
    strataBg:SetColorTexture(0.025, 0.070, 0.125, 0.98)
    strataEdit._edge = strataEdge
    strataEdit._label = Font(strataEdit, "GameFontHighlightSmall", "", Color("accent", { 0.42, 0.78, 1.00, 1 }), "control")
    strataEdit._label:SetPoint("LEFT", strataEdit, "LEFT", 7, 0)
    strataEdit._label:SetPoint("RIGHT", strataEdit, "RIGHT", -18, 0)
    strataEdit._label:SetJustifyH("LEFT")
    strataEdit._chevron = Font(strataEdit, "GameFontHighlightSmall", "v", Color("accent", { 0.42, 0.78, 1.00, 1 }), "control")
    strataEdit._chevron:SetPoint("RIGHT", strataEdit, "RIGHT", -6, 1)
    strataEdit:SetScript("OnEnter", function(self)
        self._edge:SetColorTexture(0.30, 0.82, 1.00, 1)
        if _G.GameTooltip then
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            _G.GameTooltip:SetText(Tr("Edit FrameStrata"))
            _G.GameTooltip:AddLine(Tr("Click and choose the Blizzard layer."), 0.78, 0.88, 1.00, true)
            _G.GameTooltip:Show()
        end
    end)
    strataEdit:SetScript("OnLeave", function(self)
        self._edge:SetColorTexture(0.18, 0.58, 0.92, 0.78)
        if _G.GameTooltip then _G.GameTooltip:Hide() end
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
    row._area = Font(row, "GameFontDisableSmall", "", Color("muted", { 0.62, 0.72, 0.86, 1 }), "caption")
    row._area:SetJustifyH("LEFT")
    row._label = Font(row, "GameFontHighlightSmall", "", Color("text", { 0.88, 0.94, 1.00, 1 }), "control")
    row._label:SetJustifyH("LEFT")
    if row._label.SetWordWrap then row._label:SetWordWrap(false) end
    popup._rows[index] = row
    return row
end

local function ConfigureSectionRow(row, text, y, width)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", 0, -y)
    row:SetSize(width, 28)
    row._rowType = "section"
    row._data = nil
    row:EnableMouse(false)
    row:SetScript("OnMouseDown", nil)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row._bg:SetColorTexture(0.05, 0.20, 0.32, 0.28)
    row._value:Hide()
    row._valueEdit:Hide()
    row._editTag:Hide()
    row._strataEdit:Hide()
    row._area:Hide()
    row._label:ClearAllPoints()
    row._label:SetPoint("LEFT", row, "LEFT", 8, 0)
    row._label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row._label:SetJustifyH("LEFT")
    row._label:SetText(text)
    SetFontColor(row._label, Color("accent", { 0.42, 0.78, 1.00, 1 }))
    row._label:Show()
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
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", 0, -y)
    row:SetSize(width, 22)
    row._rowType = "data"
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
        row._value:SetText(tostring(data.layer))
        if data.edit then
            row._value:Hide()
            row._valueEdit._ownerRow = row
            row._valueEdit:SetText(tostring(data.layer))
            if row._valueEdit.SetTextColor then
                local c = Color("success", { 0.30, 1.00, 0.62, 1 })
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
    local areaText = data.area .. " / " .. data.scope
    if data.inherited then areaText = areaText .. " (shared)" end
    row._area:SetText(areaText)
    row._label:SetText(data.label .. (data.enabled and "" or " (off)"))
    local alpha = data.enabled and 1 or 0.48
    SetFontColor(row._value, strataMode and Color("accent", { 0.42, 0.78, 1.00, 1 }) or Color("success", { 0.30, 1.00, 0.62, 1 }), alpha)
    SetFontColor(row._area, Color("muted", { 0.62, 0.72, 0.86, 1 }), alpha)
    SetFontColor(row._label, Color("text", { 0.88, 0.94, 1.00, 1 }), alpha)
    row._area:Show()
    row._label:Show()
    row:Show()
end

local function ConfigureMoreRow(row, text, y, width, popup)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", 0, -y)
    row:SetSize(width, 30)
    row._rowType = "more"
    row._data = nil
    row._bg:SetColorTexture(0.04, 0.24, 0.20, 0.34)
    row._value:Hide()
    row._valueEdit:Hide()
    row._editTag:Hide()
    row._strataEdit:Hide()
    row._area:Hide()
    row._label:ClearAllPoints()
    row._label:SetPoint("LEFT", row, "LEFT", 10, 0)
    row._label:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row._label:SetJustifyH("CENTER")
    row._label:SetText(text)
    SetFontColor(row._label, Color("success", { 0.30, 1.00, 0.62, 1 }))
    row._label:Show()
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
            Section(Tr("Search results - MSUF Layers 0-30") .. " (" .. tostring(#foundLayers) .. ") | " .. layerEditHint)
            DataRows(foundLayers)
        end
        if #foundLayers == 0 then Section(Tr("No layers match this search.")) end
    else
        if #relevantLayers > 0 then
            Section(context.label .. " - " .. Tr("MSUF Layers 0-30") .. " (" .. tostring(#relevantLayers) .. ") | " .. layerEditHint)
            DataRows(relevantLayers)
        end
        local moreCount = #moreLayers
        if moreCount > 0 then
            y = y + 7
            rowIndex = rowIndex + 1
            ConfigureMoreRow(AcquireVisualRow(popup, rowIndex),
                (popup._showMore and Tr("Less") or Tr("More")) .. " (" .. tostring(moreCount) .. ")",
                y, width, popup)
            y = y + 32
            if popup._showMore then
                if #moreLayers > 0 then
                    Section(Tr("All other MSUF Layers 0-30") .. " (" .. tostring(#moreLayers) .. ") | " .. layerEditHint)
                    DataRows(moreLayers)
                end
            end
        end
    end
    popup._scrollChild:SetSize(width, math.max(y + 4, popup._scroll:GetHeight()))
    popup._count:SetText(tostring(#layers) .. " " .. Tr("editable Layer numbers (0-30)"))
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
        popup = CreateFrame("Frame", "MSUF2LayerOverview", UIParent, _G.BackdropTemplateMixin and "BackdropTemplate" or nil)
        if popup.SetBackdrop then
            popup:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
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

    popup._title = Font(popup, "GameFontNormal", Tr("Layer Overview"), Color("accent", { 0.42, 0.78, 1.00, 1 }), "title")
    popup._title:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -12)
    popup._title:SetJustifyH("LEFT")

    local search = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    search:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -46, -10)
    search:SetSize(156, 20)
    search:SetAutoFocus(false)
    search:SetMaxLetters(60)
    if search.SetTextInsets then search:SetTextInsets(6, 6, 0, 0) end
    if T.SkinEditBox then T.SkinEditBox(search) end
    local placeholder = search.Instructions
    if not (placeholder and placeholder.SetText and placeholder.SetPoint) then
        placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    elseif placeholder.ClearAllPoints then
        placeholder:ClearAllPoints()
    end
    placeholder:SetPoint("LEFT", search, "LEFT", 7, 0)
    placeholder:SetPoint("RIGHT", search, "RIGHT", -6, 0)
    placeholder:SetJustifyH("LEFT")
    placeholder:SetText(Tr("Search layers..."))
    SetFontColor(placeholder, Color("muted", { 0.62, 0.72, 0.86, 1 }), 0.80)
    popup._search = search
    popup._searchPlaceholder = placeholder
    popup._title:SetPoint("RIGHT", search, "LEFT", -10, 0)

    popup._count = Font(popup, "GameFontDisableSmall", "", Color("muted", { 0.62, 0.72, 0.86, 1 }), "caption")
    popup._count:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -35)
    popup._count:SetPoint("RIGHT", popup, "RIGHT", -14, 0)
    popup._count:SetJustifyH("LEFT")
    local hintBG = popup:CreateTexture(nil, "BACKGROUND")
    hintBG:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, -52)
    hintBG:SetPoint("BOTTOMRIGHT", popup, "TOPRIGHT", -10, -86)
    hintBG:SetColorTexture(0.025, 0.22, 0.16, 0.46)
    popup._hintBG = hintBG
    popup._hint = Font(popup, "GameFontHighlightSmall", Tr("EDITABLE: click a green Layer number, type 0-30, press Enter."), Color("success", { 0.30, 1.00, 0.62, 1 }), "control")
    popup._hint:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -58)
    popup._hint:SetPoint("RIGHT", popup, "RIGHT", -14, 0)
    popup._hint:SetJustifyH("LEFT")

    local close = T.CloseButton and T.CloseButton(popup) or CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -8, -8)
    close._msuf2SkipHistoryCheckpoint = true
    close:SetScript("OnClick", function() popup:Hide() end)
    popup._close = close

    local scroll = CreateFrame("ScrollFrame", nil, popup)
    scroll:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -92)
    scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -34, 14)
    local content = CreateFrame("Frame", nil, scroll)
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

    local grip = CreateFrame("Button", nil, popup)
    grip:SetSize(20, 20)
    grip:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(popup:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
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
