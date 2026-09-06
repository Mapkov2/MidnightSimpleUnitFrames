--- Auras3/EditMode_Config: saved layout readers and preview scope/style schema; no frame ownership.
--- Registered at load time; the original entrypoint owns initialization order.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
A3.EditModeModules = A3.EditModeModules or {}
A3.EditModeModules.Config = function()
local type, tonumber, tostring, pairs = type, tonumber, tostring, pairs
local math_floor = math.floor
local AURA_UNITS = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
local BOSS_UNITS = { boss1=true, boss2=true, boss3=true, boss4=true, boss5=true }
local GROUPS = {
    buff = {
        label = "Buffs",
        xKey = "buffGroupOffsetX",
        yKey = "buffGroupOffsetY",
        sizeKey = "buffGroupIconSize",
        paddingKey = "buffStylePadding",
        iconZoomKey = "buffIconZoom",
        iconShapeKey = "buffIconShape",
        anchorKey = "buffAnchor",
        layerKey = "buffLayer",
        maxKey = "maxBuffs",
        showKey = "showBuffs",
        perRowKey = "buffPerRow",
        spacingKey = "buffSpacing",
        growthKey = "buffGrowthX",
        wrapKey = "buffGrowthY",
        texture = "Interface\\Icons\\Spell_Holy_WordFortitude",
        color = { 0.16, 0.82, 0.35, 0.28 },
        defaultAnchor = "BOTTOMRIGHT",
        defaultLayer = 5,
    },
    debuff = {
        label = "Debuffs",
        xKey = "debuffGroupOffsetX",
        yKey = "debuffGroupOffsetY",
        sizeKey = "debuffGroupIconSize",
        paddingKey = "debuffStylePadding",
        iconZoomKey = "debuffIconZoom",
        iconShapeKey = "debuffIconShape",
        anchorKey = "debuffAnchor",
        layerKey = "debuffLayer",
        maxKey = "maxDebuffs",
        showKey = "showDebuffs",
        perRowKey = "debuffPerRow",
        spacingKey = "debuffSpacing",
        growthKey = "debuffGrowthX",
        wrapKey = "debuffGrowthY",
        texture = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
        color = { 0.92, 0.20, 0.20, 0.28 },
        defaultAnchor = "TOPLEFT",
        defaultLayer = 6,
    },
    custom1 = { customIndex = 1, label = "Custom 1", texture = "Interface\\Icons\\INV_Misc_QuestionMark", color = { 0.45, 0.72, 1.00, 0.28 }, defaultAnchor = "TOPRIGHT", defaultLayer = 9 },
    custom2 = { customIndex = 2, label = "Custom 2", texture = "Interface\\Icons\\INV_Misc_QuestionMark", color = { 0.70, 0.48, 1.00, 0.28 }, defaultAnchor = "TOPRIGHT", defaultLayer = 9 },
    custom3 = { customIndex = 3, label = "Custom 3", texture = "Interface\\Icons\\INV_Misc_QuestionMark", color = { 1.00, 0.58, 0.28, 0.28 }, defaultAnchor = "TOPRIGHT", defaultLayer = 9 },
    custom4 = { customIndex = 4, label = "Dots on target", texture = "Interface\\Icons\\Ability_Rogue_Garrote", color = { 0.88, 0.24, 0.42, 0.28 }, defaultAnchor = "TOPRIGHT", defaultLayer = 9 },
}

local LANE_STYLE_KEYS = {
    buff = {
        showStackCount = "buffShowStackCount",
        showCooldownText = "buffShowCooldownText",
        showCooldownSwipe = "buffShowCooldownSwipe",
        cooldownSwipeReverse = "buffCooldownSwipeReverse",
        stackCountAnchor = "buffStackCountAnchor",
        cooldownTextAnchor = "buffCooldownTextAnchor",
        stackTextSize = "buffStackTextSize",
        stackTextOffsetX = "buffStackTextOffsetX",
        stackTextOffsetY = "buffStackTextOffsetY",
        cooldownTextSize = "buffCooldownTextSize",
        cooldownTextOffsetX = "buffCooldownTextOffsetX",
        cooldownTextOffsetY = "buffCooldownTextOffsetY",
        cooldownDecimalSeconds = "buffCooldownDecimalSeconds",
        showDurationBar = "buffShowDurationBar",
        durationBarHeight = "buffDurationBarHeight",
        durationBarDisplay = "buffDurationBarDisplay",
        durationBarPosition = "buffDurationBarPosition",
        durationBarDirection = "buffDurationBarDirection",
    },
    debuff = {
        showStackCount = "debuffShowStackCount",
        showCooldownText = "debuffShowCooldownText",
        showCooldownSwipe = "debuffShowCooldownSwipe",
        cooldownSwipeReverse = "debuffCooldownSwipeReverse",
        debuffTypeBorderMode = "debuffTypeBorderMode",
        useDebuffTypeBorders = "useDebuffTypeBorders",
        stackCountAnchor = "debuffStackCountAnchor",
        cooldownTextAnchor = "debuffCooldownTextAnchor",
        stackTextSize = "debuffStackTextSize",
        stackTextOffsetX = "debuffStackTextOffsetX",
        stackTextOffsetY = "debuffStackTextOffsetY",
        cooldownTextSize = "debuffCooldownTextSize",
        cooldownTextOffsetX = "debuffCooldownTextOffsetX",
        cooldownTextOffsetY = "debuffCooldownTextOffsetY",
        cooldownDecimalSeconds = "debuffCooldownDecimalSeconds",
        showDurationBar = "debuffShowDurationBar",
        durationBarHeight = "debuffDurationBarHeight",
        durationBarDisplay = "debuffDurationBarDisplay",
        durationBarPosition = "debuffDurationBarPosition",
        durationBarDirection = "debuffDurationBarDirection",
    },
}

local TEXT_STYLE_LAYOUT_KEYS = {
    stackTextSize = true,
    stackTextOffsetX = true,
    stackTextOffsetY = true,
    cooldownTextSize = true,
    cooldownTextOffsetX = true,
    cooldownTextOffsetY = true,
    cooldownDecimalSeconds = true,
    durationBarHeight = true,
    buffStackTextSize = true,
    buffStackTextOffsetX = true,
    buffStackTextOffsetY = true,
    buffCooldownTextSize = true,
    buffCooldownTextOffsetX = true,
    buffCooldownTextOffsetY = true,
    buffCooldownDecimalSeconds = true,
    buffDurationBarHeight = true,
    debuffStackTextSize = true,
    debuffStackTextOffsetX = true,
    debuffStackTextOffsetY = true,
    debuffCooldownTextSize = true,
    debuffCooldownTextOffsetX = true,
    debuffCooldownTextOffsetY = true,
    debuffCooldownDecimalSeconds = true,
    debuffDurationBarHeight = true,
}
local TEXT_STYLE_SHARED_KEYS = {
    stackCountAnchor = true,
    cooldownTextAnchor = true,
    showStackCount = true,
    showCooldownText = true,
    showCooldownSwipe = true,
    cooldownSwipeReverse = true,
    showDurationBar = true,
    durationBarDisplay = true,
    durationBarPosition = true,
    durationBarDirection = true,
    buffStackCountAnchor = true,
    buffCooldownTextAnchor = true,
    buffShowStackCount = true,
    buffShowCooldownText = true,
    buffShowCooldownSwipe = true,
    buffCooldownSwipeReverse = true,
    buffShowDurationBar = true,
    buffDurationBarDisplay = true,
    buffDurationBarPosition = true,
    buffDurationBarDirection = true,
    debuffStackCountAnchor = true,
    debuffCooldownTextAnchor = true,
    debuffShowStackCount = true,
    debuffShowCooldownText = true,
    debuffShowCooldownSwipe = true,
    debuffCooldownSwipeReverse = true,
    debuffTypeBorderMode = true,
    useDebuffTypeBorders = true,
    debuffShowDurationBar = true,
    debuffDurationBarDisplay = true,
    debuffDurationBarPosition = true,
    debuffDurationBarDirection = true,
}
local AURA_TEXT_ANCHOR_OK = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function Clamp(v, defaultValue, minValue, maxValue)
    v = tonumber(v)
    if not v then v = defaultValue end
    if minValue and v < minValue then v = minValue end
    if maxValue and v > maxValue then v = maxValue end
    return v
end

local function Round(v)
    v = tonumber(v) or 0
    if v < -4096 then v = -4096 elseif v > 4096 then v = 4096 end
    if v < 0 then return -math_floor((-v) + 0.5) end
    return math_floor(v + 0.5)
end
local function NormalizeKind(kind)
    kind = (type(kind) == "string") and kind:lower() or "buff"
    if kind == "buffs" then return "buff" end
    if kind == "debuffs" then return "debuff" end
    if GROUPS[kind] then return kind end
    return "buff"
end

local function CustomItem(unit, index, create)
    local model = A3 and A3.MenuModel
    if not (model and type(model.CustomContainer) == "function") then return nil end
    return model.CustomContainer(unit, index, create == true)
end

--- Real tracked spells for a custom lane so previews mirror the runtime 1:1:
--- each preview icon shows an actually configured spell (dots keep the runtime
--- include filter). Returns nil while nothing is configured; edit mode then
--- keeps a placeholder drag surface, the boss page preview shows nothing.
local function CustomPreviewEntries(unit, kind)
    local spec = GROUPS[kind]
    local customIndex = spec and spec.customIndex
    if not customIndex then return nil end
    local model = A3 and A3.MenuModel
    local fetch = model and (model.CustomContainerPreviewEntries or model.CustomContainerSpellEntries)
    if type(fetch) ~= "function" then return nil end
    local entries = fetch(unit, customIndex)
    if type(entries) ~= "table" or #entries == 0 then return nil end
    return entries
end

local function CustomPreviewEntriesSignature(entries)
    if type(entries) ~= "table" then return "none" end
    local out = ""
    for i = 1, #entries do
        local entry = entries[i]
        out = out .. tostring(entry and (entry.spellID or entry.value) or "?") .. ","
    end
    return out
end

local function UnitLabel(unit)
    if unit == "player" then return "Player" end
    if unit == "target" then return "Target" end
    if unit == "focus" then return "Focus" end
    if BOSS_UNITS[unit] then return "Boss " .. tostring(unit):match("%d+") end
    return tostring(unit or "")
end

local function GroupLabel(unit, kind, spec)
    if unit == "player" and kind == "custom4" then return "Defensive Buffs" end
    return spec and spec.label or tostring(kind or "")
end

local function EnsureDB()
    local auras, shared
    if A3.EnsureDB then
        auras, shared = A3.EnsureDB()
    else
        local db = _G.MSUF_DB
        auras = db and (db.auras3 or db.auras3)
        shared = auras and auras.shared
    end
    if type(auras) ~= "table" then return nil, nil end
    if type(shared) ~= "table" then
        shared = {}
        auras.shared = shared
    end
    return auras, shared
end

local function UnitEnabled(auras, unit)
    if type(auras) ~= "table" or auras.enabled ~= true then return false end
    if unit == "player" then return auras.showPlayer == true end
    if unit == "target" then return auras.showTarget == true end
    if unit == "focus" then return auras.showFocus == true end
    if BOSS_UNITS[unit] then return auras.showBoss == true end
    return false
end

local function UnitHasCustomPreview(unit)
    for index = 1, 4 do
        local item = CustomItem and CustomItem(unit, index, false)
        local placed = item and item.placed
        if item and (tonumber(placed and placed.max) or 8) > 0 then
            if item.enabled == true then return true end
            -- Tracked target DoTs keep their configuration preview while the
            -- lane is disabled. Player Defensives use `enabled` as a strict
            -- master switch, matching both Runtime and the Menu2 preview.
            if unit ~= "player" and index == 4
                and CustomPreviewEntries(unit, "custom4") then return true end
        end
    end
    return false
end

local function GetLayout(auras, unit, create)
    if type(auras) ~= "table" or not unit then return nil end
    if create then
        auras.perUnit = (type(auras.perUnit) == "table") and auras.perUnit or {}
        local pu = auras.perUnit[unit]
        if type(pu) ~= "table" then
            pu = {}
            auras.perUnit[unit] = pu
        end
        --- Shared-layout scopes may still carry an old dormant local table.
        --- The first Edit Mode drag must follow the same ownership transition
        --- as Menu/Popup writes instead of reactivating stale geometry/style.
        if pu.overrideLayout ~= true then pu.layout = {} end
        pu.overrideLayout = true
        pu.layout = (type(pu.layout) == "table") and pu.layout or {}
        return pu.layout, pu
    end

    local pu = auras.perUnit and auras.perUnit[unit]
    if pu and type(pu.layout) == "table" then
        return pu.layout, pu
    end
    return nil, pu
end

local function GetSharedLayout(auras, unit)
    local pu = auras and auras.perUnit and auras.perUnit[unit]
    if pu and type(pu.layoutShared) == "table" then
        return pu.layoutShared
    end
    return nil
end

local function TableHasAnyKey(tbl, keys)
    if type(tbl) ~= "table" or type(keys) ~= "table" then return false end
    for key in pairs(keys) do
        if tbl[key] ~= nil then return true end
    end
    return false
end

local function UnitStyleOverrideActive(pu)
    if type(pu) ~= "table" then return false end
    if pu.overrideStyle ~= nil then return pu.overrideStyle == true end
    return TableHasAnyKey(pu.layout, TEXT_STYLE_LAYOUT_KEYS) or TableHasAnyKey(pu.layoutShared, TEXT_STYLE_SHARED_KEYS)
end

local function ReadNumber(shared, layout, key, defaultValue, minValue, maxValue)
    local v = shared and shared[key]
    if layout and layout[key] ~= nil then v = layout[key] end
    return Clamp(v, defaultValue, minValue, maxValue)
end

local function ReadRawNumber(shared, layout, key)
    local v = layout and layout[key]
    if v == nil then v = shared and shared[key] end
    return tonumber(v)
end

local function ReadRawValue(shared, layout, key)
    if layout and layout[key] ~= nil then return layout[key] end
    return shared and shared[key]
end

local function ReadLaneTextNumber(shared, layout, kind, key, defaultValue, minValue, maxValue)
    kind = NormalizeKind(kind)
    local laneKey = kind and LANE_STYLE_KEYS[kind] and LANE_STYLE_KEYS[kind][key]
    local v = laneKey and ReadRawNumber(nil, layout, laneKey) or nil
    return Clamp(v, defaultValue, minValue, maxValue)
end

local function ReadLaneTextBool(shared, layout, kind, key, defaultValue)
    kind = NormalizeKind(kind)
    local laneKey = kind and LANE_STYLE_KEYS[kind] and LANE_STYLE_KEYS[kind][key]
    -- `false` is a real per-lane override. The usual and/or shortcut turns it
    -- into nil and incorrectly falls back to the generic/shared On value.
    local v
    if laneKey then v = ReadRawValue(nil, layout, laneKey) end
    if v == nil then return defaultValue == true end
    return v == true
end

local function ReadLaneTextString(shared, layout, kind, key, fallback)
    kind = NormalizeKind(kind)
    local laneKey = kind and LANE_STYLE_KEYS[kind] and LANE_STYLE_KEYS[kind][key]
    local v = laneKey and ReadRawValue(nil, layout, laneKey) or nil
    return tostring(v or fallback or "")
end

local function ReadLaneTextAnchor(shared, layoutShared, kind)
    kind = NormalizeKind(kind)
    local laneKey = kind and LANE_STYLE_KEYS[kind] and LANE_STYLE_KEYS[kind].stackCountAnchor
    local anchor = laneKey and layoutShared and layoutShared[laneKey] or nil
    anchor = anchor or "TOPRIGHT"
    if anchor ~= "TOPLEFT" and anchor ~= "BOTTOMLEFT" and anchor ~= "BOTTOMRIGHT" then
        anchor = "TOPRIGHT"
    end
    return anchor
end

local function ReadLaneCooldownTextAnchor(shared, layoutShared, kind)
    kind = NormalizeKind(kind)
    local laneKey = kind and LANE_STYLE_KEYS[kind] and LANE_STYLE_KEYS[kind].cooldownTextAnchor
    local anchor = laneKey and layoutShared and layoutShared[laneKey] or nil
    anchor = anchor or "CENTER"
    return AURA_TEXT_ANCHOR_OK[anchor] and anchor or "CENTER"
end

local function NormalizeDebuffBorderMode(value, useLegacy)
    if value == true then return "SYMBOL" end
    value = tostring(value or ""):upper()
    if value == "BORDER" or value == "COLOR" or value == "ON" then return "BORDER" end
    if value == "SYMBOL" or value == "BORDER_SYMBOL" or value == "BORDER_SYMBOLS"
        or value == "BORDER+SYMBOL" or value == "ICON" or value == "WITH_SYMBOL" then
        return "SYMBOL"
    end
    return useLegacy == true and "SYMBOL" or "OFF"
end

local function ReadTextConfig(unit, kind)
    kind = NormalizeKind(kind)
    local customSpec = GROUPS[kind]
    if customSpec and customSpec.customIndex then
        local item = CustomItem(unit, customSpec.customIndex, false)
        local placed = item and item.placed or {}
        local isDebuff = item and item.auraType == "DEBUFF"
        return {
            showStackCount = placed.showStacks ~= false,
            showCooldownText = placed.showCooldown ~= false,
            showCooldownSwipe = placed.showCooldownSwipe ~= false,
            cooldownSwipeReverse = placed.cooldownSwipeReverse == true,
            stackSize = Clamp(placed.stackSize, 14, 6, 40),
            stackX = Clamp(placed.stackX, 0, -2000, 2000),
            stackY = Clamp(placed.stackY, 0, -2000, 2000),
            cooldownSize = Clamp(placed.cooldownSize, 14, 6, 40),
            cooldownX = Clamp(placed.cooldownX, 0, -2000, 2000),
            cooldownY = Clamp(placed.cooldownY, 0, -2000, 2000),
            cooldownDecimalSeconds = Clamp(placed.cooldownDecimalSeconds, 3, 0, 30),
            showDurationBar = placed.showDurationBar == true,
            durationBarHeight = Clamp(placed.durationBarHeight, 2, 1, 16),
            durationBarDisplay = placed.durationBarDisplay == "OVERLAY" and "OVERLAY" or "BAR_ONLY",
            durationBarPosition = placed.durationBarPosition == "TOP" and "TOP" or "BOTTOM",
            durationBarDirection = placed.durationBarDirection == "ELAPSED" and "ELAPSED" or "REMAINING",
            stackAnchor = placed.stackAnchor or "BOTTOMRIGHT",
            cooldownAnchor = placed.cooldownAnchor or "CENTER",
            debuffBorderMode = isDebuff and NormalizeDebuffBorderMode(placed.debuffTypeBorderMode, placed.useDebuffTypeBorders) or "OFF",
        }
    end
    local auras, shared = EnsureDB()
    local layout = GetLayout(auras, unit, false)
    local ls = GetSharedLayout(auras, unit)
    return {
        showStackCount = ReadLaneTextBool(shared, ls, kind, "showStackCount", true),
        showCooldownText = ReadLaneTextBool(shared, ls, kind, "showCooldownText", true),
        showCooldownSwipe = ReadLaneTextBool(shared, ls, kind, "showCooldownSwipe", true),
        cooldownSwipeReverse = ReadLaneTextBool(shared, ls, kind, "cooldownSwipeReverse", false),
        stackSize = ReadLaneTextNumber(shared, layout, kind, "stackTextSize", 14, 6, 40),
        stackX = ReadLaneTextNumber(shared, layout, kind, "stackTextOffsetX", -1, -2000, 2000),
        stackY = ReadLaneTextNumber(shared, layout, kind, "stackTextOffsetY", 1, -2000, 2000),
        cooldownSize = ReadLaneTextNumber(shared, layout, kind, "cooldownTextSize", 14, 6, 40),
        cooldownX = ReadLaneTextNumber(shared, layout, kind, "cooldownTextOffsetX", 0, -2000, 2000),
        cooldownY = ReadLaneTextNumber(shared, layout, kind, "cooldownTextOffsetY", 0, -2000, 2000),
        cooldownDecimalSeconds = ReadLaneTextNumber(shared, layout, kind, "cooldownDecimalSeconds", 3, 0, 30),
        showDurationBar = ReadLaneTextBool(shared, ls, kind, "showDurationBar", false),
        durationBarHeight = ReadLaneTextNumber(shared, layout, kind, "durationBarHeight", 2, 1, 16),
        durationBarDisplay = ReadLaneTextString(shared, ls, kind, "durationBarDisplay", "BAR_ONLY") == "OVERLAY" and "OVERLAY" or "BAR_ONLY",
        durationBarPosition = ReadLaneTextString(shared, ls, kind, "durationBarPosition", "BOTTOM") == "TOP" and "TOP" or "BOTTOM",
        durationBarDirection = ReadLaneTextString(shared, ls, kind, "durationBarDirection", "REMAINING") == "ELAPSED" and "ELAPSED" or "REMAINING",
        stackAnchor = ReadLaneTextAnchor(shared, ls, kind),
        cooldownAnchor = ReadLaneCooldownTextAnchor(shared, ls, kind),
        debuffBorderMode = kind == "debuff" and NormalizeDebuffBorderMode(
            ReadLaneTextString(shared, ls, kind, "debuffTypeBorderMode", "OFF"),
            ReadLaneTextBool(shared, ls, kind, "useDebuffTypeBorders", false)) or "OFF",
    }
end

local function ReadGroupConfig(unit, kind)
    kind = NormalizeKind(kind)
    local spec = GROUPS[kind]
    if spec and spec.customIndex then
        local item = CustomItem(unit, spec.customIndex, false)
        local placed = item and item.placed or {}
        local auraType = item and item.auraType == "DEBUFF" and "DEBUFF" or "BUFF"
        local anchor = placed.anchor
        if not AURA_TEXT_ANCHOR_OK[anchor] then anchor = spec.defaultAnchor end
        return {
            x = Round(placed.x or 0),
            y = Round(placed.y or 0),
            anchor = anchor,
            layer = Clamp(item and item.layer, spec.defaultLayer, 0, 30),
            alpha = Clamp(placed.alpha, 1, 0, 1),
            iconZoom = Clamp(placed.iconZoom, 100, 100, 200),
            iconShape = type(placed.iconShape) == "string" and placed.iconShape or "RECTANGLE",
            size = Clamp(placed.size, 24, 1, 128),
            padding = Clamp(placed.stylePadding, 0, 0, 16),
            spacing = Clamp(placed.spacing, 2, 0, 64),
            perRow = Clamp(placed.perRow, 4, 1, 40),
            max = Clamp(placed.max, 8, 0, 40),
            growth = placed.growth or "LEFTDOWN",
            rowWrap = "DOWN",
            show = item and item.enabled == true or false,
            -- The dots container keeps its own placeholder (Garrote) instead of
            -- the generic debuff icon; tracked entries override it anyway.
            texture = spec.customIndex == 4 and spec.texture
                or (auraType == "DEBUFF" and "Interface\\Icons\\Spell_Shadow_ShadowWordPain" or "Interface\\Icons\\Spell_Holy_WordFortitude"),
        }
    end
    local auras, shared = EnsureDB()
    local layout = GetLayout(auras, unit, false)
    local ls = GetSharedLayout(auras, unit)

    local x = layout and layout[spec.xKey] or 0
    local y = layout and layout[spec.yKey] or 0
    local size = layout and layout[spec.sizeKey] or 26
    local iconZoom = layout and layout[spec.iconZoomKey] or 100
    local shapes = type(shared) == "table" and shared.appearanceIconShapes or nil
    local iconShape = type(shapes) == "table" and shapes[kind] or "RECTANGLE"
    local spacing = layout and layout[spec.spacingKey] or 2
    spacing = Clamp(spacing, 2, 0, 64)
    local perRow = (ls and type(ls[spec.perRowKey]) == "number" and ls[spec.perRowKey])
        or 12
    local maxN = (ls and type(ls[spec.maxKey]) == "number" and ls[spec.maxKey])
        or 12
    local growth = (ls and ls[spec.growthKey])
        or "RIGHT"
    if growth ~= "RIGHT" and growth ~= "LEFT" and growth ~= "UP" and growth ~= "DOWN" then growth = "RIGHT" end
    local rowWrap = (ls and ls[spec.wrapKey])
        or "DOWN"
    if rowWrap ~= "UP" and rowWrap ~= "DOWN" then rowWrap = "DOWN" end
    local anchor = (layout and layout[spec.anchorKey])
        or spec.defaultAnchor
        or "TOPLEFT"
    if not AURA_TEXT_ANCHOR_OK[anchor] then
        anchor = spec.defaultAnchor or "TOPLEFT"
    end
    local layer = (layout and layout[spec.layerKey] ~= nil and layout[spec.layerKey])
        or spec.defaultLayer
        or 5

    return {
        x = Round(x),
        y = Round(y),
        anchor = anchor,
        layer = Clamp(layer, spec.defaultLayer or 5, 0, 30),
        size = Clamp(size, 26, 1, 128),
        iconZoom = Clamp(iconZoom, 100, 100, 200),
        iconShape = iconShape,
        padding = Clamp(layout and layout[spec.paddingKey], 0, 0, 16),
        spacing = spacing,
        perRow = Clamp(perRow, 12, 1, 40),
        max = Clamp(maxN, 12, 0, 80),
        growth = growth,
        rowWrap = rowWrap,
        show = not ls or ls[spec.showKey] ~= false,
    }
end

return {
    Clamp = Clamp,
    Round = Round,
    NormalizeKind = NormalizeKind,
    CustomItem = CustomItem,
    CustomPreviewEntries = CustomPreviewEntries,
    CustomPreviewEntriesSignature = CustomPreviewEntriesSignature,
    UnitLabel = UnitLabel,
    GroupLabel = GroupLabel,
    EnsureDB = EnsureDB,
    UnitEnabled = UnitEnabled,
    UnitHasCustomPreview = UnitHasCustomPreview,
    GetLayout = GetLayout,
    ReadTextConfig = ReadTextConfig,
    ReadGroupConfig = ReadGroupConfig,
    AURA_UNITS = AURA_UNITS,
    BOSS_UNITS = BOSS_UNITS,
    GROUPS = GROUPS,
    AURA_TEXT_ANCHOR_OK = AURA_TEXT_ANCHOR_OK,
}
end
