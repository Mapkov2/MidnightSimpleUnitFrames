--- Auras3/MSUF_Auras3_UnitFrames.lua
--- Delta-first UnitFrame aura backend.
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
_G.MSUF_Auras3 = A3

local UF = MSUF.UF
if not (UF and UF.RegisterElement) then return end

if A3.__unitFrameBackendLoaded then return end
A3.__unitFrameBackendLoaded = true

local type, tostring, tonumber, pairs, next = type, tostring, tonumber, pairs, next
local math_floor, math_ceil, math_min, math_max = math.floor, math.ceil, math.min, math.max
local table_sort = table.sort
local wipe = table.wipe or wipe
local CreateFrame = _G.CreateFrame
local GameTooltip = _G.GameTooltip
local UnitExists = _G.UnitExists
local C_Timer = _G.C_Timer
local C_UnitAuras = _G.C_UnitAuras
local AuraUtil = _G.AuraUtil
local nativeSecrets = _G.issecretvalue ~= nil
local IsSecret = _G.issecretvalue or function() return false end

local GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local GetAuraDataByAuraInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
local IsAuraFilteredOutByInstanceID = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
local GetAuraDuration = C_UnitAuras and C_UnitAuras.GetAuraDuration
local GetAuraApplicationDisplayCount = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount

local BOSS_UNITS = {
    boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
}
local MANAGED_UNITS = {
    player = true, target = true, focus = true,
    boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
}
local EMPTY_EVENTS = {}
local COMBAT_AURA_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

local UNIT_FLAG = {
    player = "showPlayer",
    target = "showTarget",
    focus = "showFocus",
    boss1 = "showBoss",
    boss2 = "showBoss",
    boss3 = "showBoss",
    boss4 = "showBoss",
    boss5 = "showBoss",
}

local DEFAULT_SHARED = {
    showBuffs = true,
    showDebuffs = true,
    showTooltip = true,
    showCooldownSwipe = true,
    showCooldownText = true,
    showStackCount = true,
    buffShowCooldownSwipe = true,
    buffShowCooldownText = true,
    buffShowStackCount = true,
    debuffShowCooldownSwipe = true,
    debuffShowCooldownText = true,
    debuffShowStackCount = true,
    clickThroughAuras = false,
    iconSize = 26,
    spacing = 2,
    perRow = 12,
    maxBuffs = 12,
    maxDebuffs = 12,
    growth = "RIGHT",
    rowWrap = "DOWN",
    offsetX = 0,
    offsetY = 6,
    buffOffsetX = 0,
    buffOffsetY = 30,
    buffGroupOffsetX = 0,
    buffGroupOffsetY = 36,
    debuffGroupOffsetX = 0,
    debuffGroupOffsetY = 6,
    buffGroupIconSize = 26,
    debuffGroupIconSize = 26,
    buffAnchor = "BOTTOMRIGHT",
    debuffAnchor = "TOPLEFT",
    buffLayer = 5,
    debuffLayer = 6,
    stackCountAnchor = "TOPRIGHT",
    buffStackCountAnchor = "TOPRIGHT",
    debuffStackCountAnchor = "TOPRIGHT",
    stackTextSize = 14,
    stackTextOffsetX = -1,
    stackTextOffsetY = 1,
    cooldownTextSize = 14,
    cooldownTextOffsetX = 0,
    cooldownTextOffsetY = 0,
    buffStackTextSize = 14,
    buffStackTextOffsetX = -1,
    buffStackTextOffsetY = 1,
    buffCooldownTextSize = 14,
    buffCooldownTextOffsetX = 0,
    buffCooldownTextOffsetY = 0,
    debuffStackTextSize = 14,
    debuffStackTextOffsetX = -1,
    debuffStackTextOffsetY = 1,
    debuffCooldownTextSize = 14,
    debuffCooldownTextOffsetX = 0,
    debuffCooldownTextOffsetY = 0,
}

local LANE_SPECS = {
    buff = {
        dbKey = "buffs",
        filter = "HELPFUL",
        showKey = "showBuffs",
        maxKey = "maxBuffs",
        xKey = "buffGroupOffsetX",
        yKey = "buffGroupOffsetY",
        sizeKey = "buffGroupIconSize",
        anchorKey = "buffAnchor",
        layerKey = "buffLayer",
        perRowKey = "buffPerRow",
        growthKey = "buffGrowthX",
        wrapKey = "buffGrowthY",
        stackAnchorKey = "buffStackCountAnchor",
        showSwipeKey = "buffShowCooldownSwipe",
        showTextKey = "buffShowCooldownText",
        showStackKey = "buffShowStackCount",
        stackSizeKey = "buffStackTextSize",
        stackXKey = "buffStackTextOffsetX",
        stackYKey = "buffStackTextOffsetY",
        defaultAnchor = "BOTTOMRIGHT",
        defaultLayer = 5,
        harmful = false,
    },
    debuff = {
        dbKey = "debuffs",
        filter = "HARMFUL",
        showKey = "showDebuffs",
        maxKey = "maxDebuffs",
        xKey = "debuffGroupOffsetX",
        yKey = "debuffGroupOffsetY",
        sizeKey = "debuffGroupIconSize",
        anchorKey = "debuffAnchor",
        layerKey = "debuffLayer",
        perRowKey = "debuffPerRow",
        growthKey = "debuffGrowthX",
        wrapKey = "debuffGrowthY",
        stackAnchorKey = "debuffStackCountAnchor",
        showSwipeKey = "debuffShowCooldownSwipe",
        showTextKey = "debuffShowCooldownText",
        showStackKey = "debuffShowStackCount",
        stackSizeKey = "debuffStackTextSize",
        stackXKey = "debuffStackTextOffsetX",
        stackYKey = "debuffStackTextOffsetY",
        defaultAnchor = "TOPLEFT",
        defaultLayer = 6,
        harmful = true,
    },
}

local function WipeTable(tbl)
    if not tbl then return {} end
    if wipe then return wipe(tbl) end
    for k in pairs(tbl) do tbl[k] = nil end
    return tbl
end

local function ClampNumber(value, defaultValue, minValue, maxValue)
    value = tonumber(value)
    if value == nil then value = defaultValue end
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

local function Round(value)
    value = tonumber(value) or 0
    if value < 0 then return -math_floor((-value) + 0.5) end
    return math_floor(value + 0.5)
end

local function NormalizeRuntimeUnit(unit)
    unit = tostring(unit or "player")
    if unit == "boss" then return "boss1" end
    if BOSS_UNITS[unit] or unit == "player" or unit == "target" or unit == "focus" then
        return unit
    end
    return nil
end

local function NormalizeConfigUnit(unit)
    unit = NormalizeRuntimeUnit(unit)
    return BOSS_UNITS[unit] and "boss" or unit
end

local function EachRuntimeUnit(unit, fn)
    unit = tostring(unit or "")
    if unit == "" or unit == "*" then
        fn("player")
        fn("target")
        fn("focus")
        for i = 1, 5 do fn("boss" .. i) end
        return
    end
    if unit == "boss" then
        for i = 1, 5 do fn("boss" .. i) end
        return
    end
    unit = NormalizeRuntimeUnit(unit)
    if unit then fn(unit) end
end

local function EnsureRootDB()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then
        db = {}
        _G.MSUF_DB = db
    end
    if type(db.auras3) ~= "table" then db.auras3 = {} end
    local auras = db.auras3
    if type(auras.shared) ~= "table" then auras.shared = {} end
    if type(auras.perUnit) ~= "table" then auras.perUnit = {} end
    if auras.enabled == nil then auras.enabled = true end
    if auras.showPlayer == nil then auras.showPlayer = false end
    if auras.showTarget == nil then auras.showTarget = true end
    if auras.showFocus == nil then auras.showFocus = true end
    if auras.showBoss == nil then auras.showBoss = true end
    return auras, auras.shared
end

local function ReadRaw(primary, secondary, key)
    if primary and primary[key] ~= nil then return primary[key] end
    if secondary and secondary[key] ~= nil then return secondary[key] end
    return nil
end

local function ReadShared(shared, key)
    local v = shared and shared[key]
    if v == nil then v = DEFAULT_SHARED[key] end
    return v
end

local function ReadBool(primary, secondary, key, defaultValue)
    local v = ReadRaw(primary, secondary, key)
    if v == nil then return defaultValue and true or false end
    return v == true
end

local function ReadNumber(primary, secondary, key, defaultValue, minValue, maxValue)
    local v = ReadRaw(primary, secondary, key)
    return ClampNumber(v, defaultValue, minValue, maxValue)
end

local function ReadAnchor(primary, secondary, key, fallback)
    local value = ReadRaw(primary, secondary, key) or fallback or "TOPLEFT"
    if value ~= "TOPLEFT" and value ~= "TOPRIGHT" and value ~= "BOTTOMLEFT"
        and value ~= "BOTTOMRIGHT" and value ~= "CENTER" then
        value = fallback or "TOPLEFT"
    end
    return value
end

local function GrowthParts(growth, rowWrap)
    if growth ~= "LEFT" and growth ~= "UP" and growth ~= "DOWN" then growth = "RIGHT" end
    if rowWrap ~= "UP" then rowWrap = "DOWN" end
    local xSign = growth == "LEFT" and -1 or 1
    local ySign = rowWrap == "UP" and 1 or -1
    if growth == "UP" or growth == "DOWN" then
        xSign = 1
        ySign = growth == "UP" and 1 or -1
    end
    return growth, rowWrap, xSign, ySign
end

local function ButtonAnchor(xSign, ySign)
    if ySign > 0 then
        return xSign < 0 and "BOTTOMRIGHT" or "BOTTOMLEFT"
    end
    return xSign < 0 and "TOPRIGHT" or "TOPLEFT"
end

local function EffectiveTables(auras, runtimeUnit)
    local pu = auras and auras.perUnit and auras.perUnit[runtimeUnit]
    local shared = auras and auras.shared
    local layout = pu and pu.overrideLayout == true and type(pu.layout) == "table" and pu.layout or nil
    local sharedLayout = pu and pu.overrideSharedLayout == true and type(pu.layoutShared) == "table" and pu.layoutShared or nil
    local blacklist = nil
    if pu and pu.overrideBlacklist == true and type(pu.blacklist) == "table" then
        blacklist = pu.blacklist
    else
        blacklist = shared and shared.blacklist
    end
    local filters = nil
    if pu and pu.overrideFilters == true and type(pu.filters) == "table" then
        filters = pu.filters
    else
        filters = shared and shared.filters
    end
    return layout, sharedLayout, blacklist, filters
end

local function CompileBlacklist(blacklist)
    local spells = type(blacklist) == "table" and blacklist.spells
    if type(spells) ~= "table" then return nil end
    local out, n = nil, 0
    for key, enabled in pairs(spells) do
        if enabled == true then
            local id = tonumber(key)
            if id then
                if not out then out = {} end
                out[math_floor(id + 0.5)] = true
                n = n + 1
            end
        end
    end
    return n > 0 and out or nil
end

local function FilterTable(filtersRoot, dbKey)
    local root = type(filtersRoot) == "table" and filtersRoot or nil
    if not root or root.enabled == false then return nil end
    local filters = root[dbKey]
    return type(filters) == "table" and filters or nil
end

local function CompileLane(runtimeUnit, shared, layout, sharedLayout, blacklist, filtersRoot, kind)
    local spec = LANE_SPECS[kind]
    local sizeDefault = tonumber(ReadRaw(layout, shared, spec.sizeKey))
        or tonumber(ReadRaw(layout, shared, "iconSize"))
        or DEFAULT_SHARED.iconSize
    local size = ClampNumber(sizeDefault, DEFAULT_SHARED.iconSize, 1, 128)
    local spacing = ReadNumber(layout, shared, "spacing", DEFAULT_SHARED.spacing, 0, 64)
    local perRow = ReadNumber(sharedLayout, shared, spec.perRowKey, ReadShared(shared, "perRow"), 1, 40)
    local maxCount = ReadNumber(sharedLayout, shared, spec.maxKey, DEFAULT_SHARED[spec.maxKey] or 12, 0, 80)
    local show = ReadBool(sharedLayout, shared, spec.showKey, true)
    local growth = ReadRaw(sharedLayout, shared, spec.growthKey) or ReadRaw(sharedLayout, shared, "growth") or DEFAULT_SHARED.growth
    local rowWrap = ReadRaw(sharedLayout, shared, spec.wrapKey) or ReadRaw(sharedLayout, shared, "rowWrap") or DEFAULT_SHARED.rowWrap
    local growthX, growthY, xSign, ySign = GrowthParts(growth, rowWrap)
    local x = ReadNumber(layout, shared, spec.xKey, DEFAULT_SHARED[spec.xKey] or 0, -4096, 4096)
    local y = ReadNumber(layout, shared, spec.yKey, DEFAULT_SHARED[spec.yKey] or 0, -4096, 4096)
    local anchor = ReadAnchor(layout, shared, spec.anchorKey, spec.defaultAnchor)
    local layer = ReadNumber(layout, shared, spec.layerKey, spec.defaultLayer, 1, 15)
    local stackAnchor = ReadAnchor(sharedLayout, shared, spec.stackAnchorKey, ReadShared(shared, "stackCountAnchor") or "TOPRIGHT")
    local filters = FilterTable(filtersRoot, spec.dbKey)
    local exclusive = filters and filters.exclusive
    local onlyImportant = filters and (filters.onlyImportant == true or exclusive == "important")
    local onlyMine = filters and filters.onlyMine == true
    local raid = filters and filters.raid == true
    local includeStealable = kind == "buff" and filters and filters.includeStealable == true
    local includeDispellable = kind == "debuff" and filters and (filters.includeDispellable == true or filters.dispellable == true)
    local notDispellable = kind == "debuff" and filters and filters.notDispellable == true
    local boss = kind == "debuff" and filters and filters.boss == true
    local raidInCombat = filters and (
        filters.raidInCombat == true
        or filters.raidInCombatPlayer == true
        or filters.RaidInCombat == true
        or filters.RaidInCombatPlayer == true
    )
    local hasInclusive = onlyMine or raid or includeStealable or includeDispellable or notDispellable or boss or raidInCombat
    local black = CompileBlacklist(blacklist)
    local enabled = show and maxCount > 0
    local step = size + spacing
    local cols = math_min(math_max(maxCount, 1), math_max(perRow, 1))
    local rows = math_ceil(math_max(maxCount, 1) / math_max(perRow, 1))
    local showCooldownSwipe = ReadBool(sharedLayout, shared, spec.showSwipeKey, ReadShared(shared, "showCooldownSwipe") ~= false)
    local showCooldownText = ReadBool(sharedLayout, shared, spec.showTextKey, ReadShared(shared, "showCooldownText") ~= false)

    return {
        kind = kind,
        unit = runtimeUnit,
        enabled = enabled == true,
        harmful = spec.harmful == true,
        filter = spec.filter,
        playerFilter = spec.filter .. "|PLAYER",
        importantFilter = spec.filter .. "|IMPORTANT",
        raidFilter = spec.filter .. "|RAID",
        raidInCombatFilter = spec.filter .. "|RAID_IN_COMBAT",
        stealableFilter = "HELPFUL|STEALABLE",
        dispellableFilter = "HARMFUL|RAID_PLAYER_DISPELLABLE",
        bossFilter = "HARMFUL|BOSS",
        max = Round(maxCount),
        size = size,
        spacing = spacing,
        step = step,
        perRow = Round(perRow),
        cols = cols,
        rows = rows,
        width = math_max(1, cols * size + math_max(cols - 1, 0) * spacing),
        height = math_max(1, rows * size + math_max(rows - 1, 0) * spacing),
        x = Round(x),
        y = Round(y),
        anchor = anchor,
        layer = Round(layer),
        growthX = growthX,
        growthY = growthY,
        xSign = xSign,
        ySign = ySign,
        initialAnchor = ButtonAnchor(xSign, ySign),
        clickThrough = ReadBool(nil, shared, "clickThroughAuras", false),
        showTooltip = ReadBool(nil, shared, "showTooltip", true),
        showCooldownSwipe = showCooldownSwipe,
        showCooldownText = showCooldownText,
        showCooldown = showCooldownSwipe ~= false or showCooldownText ~= false,
        showStacks = ReadBool(sharedLayout, shared, spec.showStackKey, ReadShared(shared, "showStackCount") ~= false),
        stackAnchor = stackAnchor,
        stackSize = ReadNumber(layout, shared, spec.stackSizeKey, ReadShared(shared, "stackTextSize"), 6, 40),
        stackX = ReadNumber(layout, shared, spec.stackXKey, ReadShared(shared, "stackTextOffsetX"), -2000, 2000),
        stackY = ReadNumber(layout, shared, spec.stackYKey, ReadShared(shared, "stackTextOffsetY"), -2000, 2000),
        blacklist = black,
        hasFilterWork = black ~= nil or onlyImportant or hasInclusive,
        exclusiveImportant = exclusive == "important",
        onlyImportant = onlyImportant == true,
        onlyMine = onlyMine == true,
        raid = raid == true,
        includeStealable = includeStealable == true,
        includeDispellable = includeDispellable == true,
        notDispellable = notDispellable == true,
        boss = boss == true,
        raidInCombat = raidInCombat == true,
        hasInclusive = hasInclusive == true,
        needsPlayerFlag = onlyMine == true,
        needsCombatRefresh = raidInCombat == true,
    }
end

function A3.ResolveUnitFrameConfig(unit)
    unit = NormalizeRuntimeUnit(unit)
    if not unit then return nil end
    A3._runtimeConfigCache = A3._runtimeConfigCache or {}
    local gen = A3._runtimeConfigGen or 1
    local cached = A3._runtimeConfigCache[unit]
    if cached and cached.gen == gen then return cached.config end

    local auras, shared = EnsureRootDB()
    local flag = UNIT_FLAG[unit]
    local cfg = { unit = unit, enabled = false, lanes = {} }
    if auras.enabled == true and flag and auras[flag] == true then
        local layout, sharedLayout, blacklist, filtersRoot = EffectiveTables(auras, unit)
        local buff = CompileLane(unit, shared, layout, sharedLayout, blacklist, filtersRoot, "buff")
        local debuff = CompileLane(unit, shared, layout, sharedLayout, blacklist, filtersRoot, "debuff")
        cfg.showTooltip = ReadBool(nil, shared, "showTooltip", true)
        cfg.clickThrough = ReadBool(nil, shared, "clickThroughAuras", false)
        cfg.lanes.buff = buff
        cfg.lanes.debuff = debuff
        cfg.enabled = buff.enabled == true or debuff.enabled == true
    end

    A3._runtimeConfigCache[unit] = { gen = gen, config = cfg }
    return cfg
end

function A3.BuildAuraLaneMetrics(configOrUnit, kind)
    kind = (kind == "debuff" or kind == "debuffs") and "debuff" or "buff"
    local cfg = type(configOrUnit) == "table" and configOrUnit or A3.ResolveUnitFrameConfig(configOrUnit)
    local lane = cfg and cfg.lanes and cfg.lanes[kind]
    if not lane then return nil end
    return {
        enabled = lane.enabled == true,
        num = lane.max,
        size = lane.size,
        spacing = lane.spacing,
        step = lane.step,
        perRow = lane.perRow,
        width = lane.width,
        height = lane.height,
        growthX = lane.xSign,
        growthY = lane.ySign,
        x = lane.x,
        y = lane.y,
        anchor = lane.anchor,
    }
end

function A3.UnitFrameAuraEnabled(unit)
    local cfg = A3.ResolveUnitFrameConfig(unit)
    return cfg and cfg.enabled == true
end

local function OnAuraEnter(button)
    if not (button and button:IsVisible() and GameTooltip and not GameTooltip:IsForbidden()) then return end
    local lane = button._msufA3Lane
    if not (lane and lane.config and lane.config.showTooltip and button.auraInstanceID) then return end
    GameTooltip:SetOwner(button, "ANCHOR_CURSOR")
    if GameTooltip.SetUnitAuraByAuraInstanceID then
        GameTooltip:SetUnitAuraByAuraInstanceID(lane.unit, button.auraInstanceID)
    end
end

local function OnAuraLeave()
    if GameTooltip and not GameTooltip:IsForbidden() then GameTooltip:Hide() end
end

local function ApplyFont(fs, size)
    if not fs then return end
    local fontPath, fontFlags, r, g, b, _, useShadow
    local gfs = _G.MSUF_GetGlobalFontSettings
    if type(gfs) == "function" then
        fontPath, fontFlags, r, g, b, _, useShadow = gfs()
    end
    fontPath = fontPath or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    fontFlags = fontFlags or "OUTLINE"
    local fontKey = (_G.MSUF_DB and _G.MSUF_DB.general and _G.MSUF_DB.general.fontKey) or "FRIZQT"
    if type(_G.MSUF_SetFontSafe) == "function" then
        _G.MSUF_SetFontSafe(fs, fontPath, size or 14, fontFlags, fontKey)
    elseif fs.SetFont then
        fs:SetFont(fontPath, size or 14, fontFlags)
    end
    if fs.SetTextColor then fs:SetTextColor(r or 1, g or 1, b or 1, 1) end
    if fs.SetShadowOffset then
        if useShadow then fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
    end
end

local function PlaceStackText(fs, button, cfg)
    if not (fs and button and cfg) then return end
    fs:ClearAllPoints()
    if cfg.stackAnchor == "TOPLEFT" then
        fs:SetPoint("TOPLEFT", button, "TOPLEFT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
    elseif cfg.stackAnchor == "BOTTOMLEFT" then
        fs:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("BOTTOM")
    elseif cfg.stackAnchor == "BOTTOMRIGHT" then
        fs:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("BOTTOM")
    else
        fs:SetPoint("TOPRIGHT", button, "TOPRIGHT", cfg.stackX, cfg.stackY)
        fs:SetJustifyH("RIGHT")
        fs:SetJustifyV("TOP")
    end
end

local function PositionButton(lane, button, index)
    local cfg = lane.config
    local perRow = cfg.perRow > 0 and cfg.perRow or 1
    local col = (index - 1) % perRow
    local row = math_floor((index - 1) / perRow)
    local x = col * cfg.step * cfg.xSign
    local y = row * cfg.step * cfg.ySign
    button:ClearAllPoints()
    button:SetPoint(cfg.initialAnchor, lane.frame, cfg.initialAnchor, x, y)
end

local function ApplyButtonLayout(lane, button, index)
    local cfg = lane.config
    if not cfg then return end
    button._msufA3Lane = lane
    button:SetSize(cfg.size, cfg.size)
    button:EnableMouse(not cfg.clickThrough)
    if button.Cooldown then
        if button.Cooldown.SetDrawSwipe then button.Cooldown:SetDrawSwipe(cfg.showCooldown == true and cfg.showCooldownSwipe ~= false) end
        if button.Cooldown.SetHideCountdownNumbers then button.Cooldown:SetHideCountdownNumbers(cfg.showCooldownText == false) end
        if cfg.showCooldown ~= true then
            button.Cooldown:Hide()
            button._msufA3CooldownShown = nil
        end
    end
    if button.Count then
        if cfg.showStacks == false then
            button.Count:Hide()
        else
            button.Count:Show()
            ApplyFont(button.Count, cfg.stackSize)
            PlaceStackText(button.Count, button, cfg)
        end
    end
    PositionButton(lane, button, index)
end

local function CreateAuraButton(lane, index)
    local button = CreateFrame("Button", nil, lane.frame)
    local icon = button:CreateTexture(nil, "BORDER")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.Icon = icon

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
    if cooldown.SetReverse then cooldown:SetReverse(true) end
    button.Cooldown = cooldown

    local textLayer = CreateFrame("Frame", nil, button)
    textLayer:SetAllPoints(button)
    if cooldown.GetFrameLevel and textLayer.SetFrameLevel then
        textLayer:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    end
    local count = textLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.Count = count

    button:SetScript("OnEnter", OnAuraEnter)
    button:SetScript("OnLeave", OnAuraLeave)
    ApplyButtonLayout(lane, button, index)
    button:Hide()

    lane[index] = button
    lane.createdButtons = index
    if type(lane.PostCreateButton) == "function" then
        lane:PostCreateButton(button)
    end
    local CT = A3.CooldownText
    if CT and type(CT.RegisterButton) == "function" then
        CT.RegisterButton(button, "unit")
    end
    return button
end

local function EnsureButton(lane, index)
    return lane[index] or CreateAuraButton(lane, index)
end

local function ApplyLaneLayout(lane)
    local cfg = lane.config
    if not (lane.frame and cfg) then return end
    lane.frame:ClearAllPoints()
    lane.frame:SetPoint(cfg.anchor, lane.root, cfg.anchor, cfg.x, cfg.y)
    lane.frame:SetSize(cfg.width, cfg.height)
    if lane.root.GetFrameLevel and lane.frame.SetFrameLevel then
        lane.frame:SetFrameLevel((lane.root:GetFrameLevel() or 0) + cfg.layer)
    end
    for i = 1, lane.createdButtons or 0 do
        local button = lane[i]
        if button then ApplyButtonLayout(lane, button, i) end
    end
end

local HideButton

local function ClearLane(lane)
    lane.all = WipeTable(lane.all)
    lane.active = WipeTable(lane.active)
    lane.sorted = WipeTable(lane.sorted)
    lane.visibleByID = WipeTable(lane.visibleByID)
    lane.visible = 0
    for i = 1, lane.createdButtons or 0 do
        local button = lane[i]
        if button then
            button.auraInstanceID = nil
            HideButton(button)
        end
    end
end

local function ResetLaneData(lane)
    lane.all = WipeTable(lane.all)
    lane.active = WipeTable(lane.active)
    lane.sorted = WipeTable(lane.sorted)
    lane.visibleByID = WipeTable(lane.visibleByID)
end

local function EnsureLane(root, state, kind)
    local lanes = state.lanes
    local lane = lanes[kind]
    if lane then return lane end
    local frame = CreateFrame("Frame", nil, root)
    lane = {
        kind = kind,
        root = root,
        frame = frame,
        all = {},
        active = {},
        sorted = {},
        visibleByID = {},
        visible = 0,
        createdButtons = 0,
    }
    lanes[kind] = lane
    return lane
end

local function EnsureState(frame)
    local state = frame._msufA3State
    if state then return state end
    local root = frame.Auras
    if not (root and root.SetAllPoints) then
        root = CreateFrame("Frame", nil, frame)
        root:SetAllPoints(frame)
        frame.Auras = root
    end
    state = {
        frame = frame,
        root = root,
        lanes = {},
        configGen = 0,
        needFullUpdate = true,
    }
    frame._msufA3State = state
    root.__owner = frame
    root.Buffs = EnsureLane(root, state, "buff")
    root.Debuffs = EnsureLane(root, state, "debuff")
    return state
end

local function ApplyConfig(frame, cfg)
    local state = EnsureState(frame)
    local root = state.root
    root:SetAllPoints(frame)
    root:Show()
    state.unit = cfg.unit
    state.config = cfg
    state.configGen = A3._runtimeConfigGen or 1
    state.needFullUpdate = true

    for kind in pairs(LANE_SPECS) do
        local lane = EnsureLane(root, state, kind)
        lane.unit = cfg.unit
        lane.config = cfg.lanes and cfg.lanes[kind]
        if lane.config and lane.config.enabled then
            lane.frame:Show()
            ApplyLaneLayout(lane)
        else
            lane.frame:Hide()
            ClearLane(lane)
        end
    end
    return state
end

local function HideState(frame)
    local state = frame and frame._msufA3State
    if not state then return end
    for _, lane in pairs(state.lanes) do ClearLane(lane) end
    if state.root then state.root:Hide() end
end

local function Filtered(unit, auraInstanceID, filter)
    if not IsAuraFilteredOutByInstanceID then return false end
    local filtered = IsAuraFilteredOutByInstanceID(unit, auraInstanceID, filter)
    if IsSecret(filtered) then return false end
    return filtered == true
end

local function ProcessData(lane, unit, data)
    if type(data) ~= "table" then return nil end
    local auraInstanceID = data.auraInstanceID
    if auraInstanceID == nil then return nil end
    local cfg = lane.config
    if cfg.needsPlayerFlag == true then
        data.isPlayerAura = not Filtered(unit, auraInstanceID, cfg.playerFilter)
    else
        data.isPlayerAura = false
    end
    data.isHarmfulAura = cfg.harmful == true
    return data
end

local function Blacklisted(cfg, data)
    local blacklist = cfg.blacklist
    if not blacklist then return false end
    local spellID = data and data.spellId
    if spellID == nil or IsSecret(spellID) then return false end
    spellID = tonumber(spellID)
    return spellID and blacklist[math_floor(spellID + 0.5)] == true or false
end

local function MatchFilter(unit, auraInstanceID, filter)
    return not Filtered(unit, auraInstanceID, filter)
end

local function ShouldShowAura(lane, unit, data)
    local cfg = lane.config
    if Blacklisted(cfg, data) then return false end
    if not cfg.hasFilterWork then return true end
    local auraInstanceID = data.auraInstanceID
    if cfg.exclusiveImportant then
        return MatchFilter(unit, auraInstanceID, cfg.importantFilter)
    end
    if cfg.onlyImportant and not cfg.hasInclusive then
        return MatchFilter(unit, auraInstanceID, cfg.importantFilter)
    end
    if cfg.hasInclusive then
        if cfg.onlyMine and data.isPlayerAura then return true end
        if cfg.raid and MatchFilter(unit, auraInstanceID, cfg.raidFilter) then return true end
        if cfg.raidInCombat and MatchFilter(unit, auraInstanceID, cfg.raidInCombatFilter) then return true end
        if cfg.includeStealable and MatchFilter(unit, auraInstanceID, cfg.stealableFilter) then return true end
        if cfg.includeDispellable and MatchFilter(unit, auraInstanceID, cfg.dispellableFilter) then return true end
        if cfg.notDispellable and not MatchFilter(unit, auraInstanceID, cfg.dispellableFilter) then return true end
        if cfg.boss and MatchFilter(unit, auraInstanceID, cfg.bossFilter) then return true end
        if cfg.onlyImportant and MatchFilter(unit, auraInstanceID, cfg.importantFilter) then return true end
        return false
    end
    return true
end

local function SortAuras(a, b)
    if a.isPlayerAura ~= b.isPlayerAura then return a.isPlayerAura end
    return (a.auraInstanceID or 0) < (b.auraInstanceID or 0)
end

local function DataMatchesLane(data, cfg)
    if nativeSecrets ~= true and type(data) == "table" then
        local harmful = data.isHarmful
        if harmful ~= nil and not IsSecret(harmful) then
            return (harmful == true) == (cfg.harmful == true)
        end
        local helpful = data.isHelpful
        if helpful ~= nil and not IsSecret(helpful) then
            return (helpful == true) ~= (cfg.harmful == true)
        end
    end
    local auraInstanceID = data and data.auraInstanceID
    return auraInstanceID ~= nil and not Filtered(cfg.unit, auraInstanceID, cfg.filter)
end

local function AddAuraToLane(lane, unit, data)
    data = ProcessData(lane, unit, data)
    if not data then return false end
    local auraInstanceID = data.auraInstanceID
    lane.all[auraInstanceID] = data
    if lane.config.hasFilterWork ~= true then
        lane.active[auraInstanceID] = true
        return true
    end
    if ShouldShowAura(lane, unit, data) then
        lane.active[auraInstanceID] = true
        return true
    end
    lane.active[auraInstanceID] = nil
    return false
end

local function FullScanLane(lane, unit)
    local cfg = lane.config
    ResetLaneData(lane)
    if not (cfg and cfg.enabled) then return false end

    if GetAuraSlots and GetAuraDataBySlot then
        local slots = { GetAuraSlots(unit, cfg.filter) }
        for i = 2, #slots do
            local data = GetAuraDataBySlot(unit, slots[i])
            AddAuraToLane(lane, unit, data)
        end
        return true
    end

    if AuraUtil and type(AuraUtil.ForEachAura) == "function" then
        AuraUtil.ForEachAura(unit, cfg.filter, nil, function(data)
            AddAuraToLane(lane, unit, data)
        end, true)
        return true
    end

    return true
end

local UpdateButton

local function ShowButton(button)
    if button._msufA3Shown ~= true then
        button._msufA3Shown = true
        button:Show()
    end
end

HideButton = function(button)
    if button._msufA3Shown ~= nil then
        button._msufA3Shown = nil
        button:Hide()
    elseif button.auraInstanceID ~= nil then
        button:Hide()
    end
end

local function ShowCooldown(button, cooldown)
    if button._msufA3CooldownShown ~= true then
        button._msufA3CooldownShown = true
        cooldown:Show()
    end
end

local function HideCooldown(button, cooldown)
    if button._msufA3CooldownShown ~= nil then
        button._msufA3CooldownShown = nil
        cooldown:Hide()
    end
end

local function UpdateLaneFromDelta(lane, unit, updateInfo)
    local cfg = lane.config
    if not (cfg and cfg.enabled) then return false end
    local needsRender = false

    local added = updateInfo and updateInfo.addedAuras
    if added then
        for i = 1, #added do
            local data = added[i]
            local auraInstanceID = data and data.auraInstanceID
            if auraInstanceID ~= nil and DataMatchesLane(data, cfg) then
                if AddAuraToLane(lane, unit, data) then needsRender = true end
            end
        end
    end

    local updated = updateInfo and updateInfo.updatedAuraInstanceIDs
    if updated and GetAuraDataByAuraInstanceID then
        for i = 1, #updated do
            local auraInstanceID = updated[i]
            if auraInstanceID ~= nil and lane.all[auraInstanceID] then
                local oldData = lane.all[auraInstanceID]
                local oldPlayer = oldData and oldData.isPlayerAura
                local wasActive = lane.active[auraInstanceID] == true
                local data = ProcessData(lane, unit, GetAuraDataByAuraInstanceID(unit, auraInstanceID))
                if data then
                    lane.all[auraInstanceID] = data
                    local nowActive = cfg.hasFilterWork ~= true or ShouldShowAura(lane, unit, data)
                    if nowActive then
                        lane.active[auraInstanceID] = true
                        if wasActive then
                            if oldPlayer ~= data.isPlayerAura then
                                needsRender = true
                            else
                                local index = lane.visibleByID and lane.visibleByID[auraInstanceID]
                                local button = index and lane[index]
                                if button then
                                    UpdateButton(lane, button, unit, data)
                                end
                            end
                        else
                            needsRender = true
                        end
                    else
                        lane.active[auraInstanceID] = nil
                        if wasActive then needsRender = true end
                    end
                else
                    lane.all[auraInstanceID] = nil
                    if wasActive then
                        lane.active[auraInstanceID] = nil
                        needsRender = true
                    end
                end
            end
        end
    end

    local removed = updateInfo and updateInfo.removedAuraInstanceIDs
    if removed then
        for i = 1, #removed do
            local auraInstanceID = removed[i]
            if auraInstanceID ~= nil and lane.all[auraInstanceID] then
                lane.all[auraInstanceID] = nil
                if lane.active[auraInstanceID] then
                    lane.active[auraInstanceID] = nil
                    needsRender = true
                end
            end
        end
    end

    return needsRender
end

local function SetIcon(button, icon)
    local tex = button.Icon
    if not tex then return end
    if nativeSecrets == true then
        tex:SetTexture(icon)
        return
    end
    if IsSecret(icon) then
        tex:SetTexture(icon)
        button._msufA3Icon = nil
        button._msufA3IconPlain = nil
        return
    end
    if button._msufA3IconPlain == true and button._msufA3Icon == icon then
        return
    end
    tex:SetTexture(icon)
    button._msufA3Icon = icon
    button._msufA3IconPlain = true
end

local function SetCount(button, text)
    local count = button.Count
    if not count then return end
    if nativeSecrets == true then
        count:SetText(text or "")
        return
    end
    if IsSecret(text) then
        count:SetText(text)
        button._msufA3Count = nil
        button._msufA3CountPlain = nil
        return
    end
    text = text or ""
    if button._msufA3CountPlain == true and button._msufA3Count == text then
        return
    end
    count:SetText(text)
    button._msufA3Count = text
    button._msufA3CountPlain = true
end

local function UpdateCooldown(button, cooldown, unit, data)
    if nativeSecrets ~= true then
        local duration = data.duration
        local expirationTime = data.expirationTime
        if not IsSecret(duration) and not IsSecret(expirationTime)
            and type(duration) == "number" and type(expirationTime) == "number"
            and duration > 0 and expirationTime > 0 then
            local start = expirationTime - duration
            if button._msufA3CooldownPlain ~= true
                or button._msufA3CooldownStart ~= start
                or button._msufA3CooldownDuration ~= duration then
                cooldown:SetCooldown(start, duration)
                button._msufA3CooldownStart = start
                button._msufA3CooldownDuration = duration
                button._msufA3CooldownPlain = true
            end
            ShowCooldown(button, cooldown)
            return
        end
    end

    local durationObject = GetAuraDuration and GetAuraDuration(unit, data.auraInstanceID)
    button._msufA3CooldownStart = nil
    button._msufA3CooldownDuration = nil
    button._msufA3CooldownPlain = nil
    if durationObject then
        if cooldown.SetCooldownFromDurationObject then
            cooldown:SetCooldownFromDurationObject(durationObject)
        end
        ShowCooldown(button, cooldown)
    else
        HideCooldown(button, cooldown)
    end
end

UpdateButton = function(lane, button, unit, data)
    button.auraInstanceID = data.auraInstanceID
    button.isHarmfulAura = lane.config.harmful == true
    SetIcon(button, data.icon)
    local cooldown = button.Cooldown
    if cooldown and lane.config.showCooldown == true then
        UpdateCooldown(button, cooldown, unit, data)
    elseif cooldown then
        HideCooldown(button, cooldown)
    end
    if lane.config.showStacks ~= false then
        local applications = data.applications
        if nativeSecrets ~= true and not IsSecret(applications) and type(applications) == "number" then
            SetCount(button, applications > 1 and applications or "")
        elseif GetAuraApplicationDisplayCount then
            SetCount(button, GetAuraApplicationDisplayCount(unit, data.auraInstanceID, 2, 999))
        else
            SetCount(button, "")
        end
    end
    ShowButton(button)
end

local function RenderLane(lane, unit)
    local cfg = lane.config
    if not (cfg and cfg.enabled) then
        ClearLane(lane)
        return false
    end
    local sorted = WipeTable(lane.sorted)
    local count = 0
    for auraInstanceID in next, lane.active do
        local data = lane.all[auraInstanceID]
        if data then
            count = count + 1
            sorted[count] = data
        end
    end
    if count > 1 then
        table_sort(sorted, SortAuras)
    end

    local visible = math_min(cfg.max, count)
    local visibleByID = WipeTable(lane.visibleByID)
    for i = 1, visible do
        local button = EnsureButton(lane, i)
        local data = sorted[i]
        UpdateButton(lane, button, unit, data)
        visibleByID[data.auraInstanceID] = i
    end
    for i = visible + 1, lane.visible do
        local button = lane[i]
        if button then
            if button.auraInstanceID ~= nil then
                visibleByID[button.auraInstanceID] = nil
            end
            button.auraInstanceID = nil
            HideButton(button)
        end
    end
    lane.visible = visible
    return true
end

local function EmptyAuraPayload(updateInfo)
    return updateInfo and not updateInfo.isFullUpdate
        and not updateInfo.addedAuras
        and not updateInfo.updatedAuraInstanceIDs
        and not updateInfo.removedAuraInstanceIDs
end

local function CurrentFrameState(frame, unit)
    local state = frame and frame._msufA3State
    local gen = A3._runtimeConfigGen or 1
    if state and state.configGen == gen and state.config and state.unit == unit then
        return state, state.config
    end

    local cfg = A3.ResolveUnitFrameConfig(unit)
    if not (cfg and cfg.enabled) then
        return state, cfg
    end
    state = ApplyConfig(frame, cfg)
    return state, cfg
end

local function UpdateAuras(frame, event, unit, updateInfo, forceFull)
    if not frame then return false end
    unit = unit or frame.unit
    if unit ~= frame.unit then return false end
    if EmptyAuraPayload(updateInfo) and forceFull ~= true then return false end

    local state, cfg = CurrentFrameState(frame, unit)
    if not (cfg and cfg.enabled) then
        HideState(frame)
        return false
    end

    forceFull = forceFull == true or state.config ~= cfg
    local full = forceFull == true or state.needFullUpdate == true or not updateInfo or updateInfo.isFullUpdate == true
    state.needFullUpdate = false

    if full and UnitExists then
        local exists = UnitExists(unit)
        if not IsSecret(exists) and exists == false then
            local lanes = state.lanes
            local lane = lanes and lanes.buff
            if lane then ClearLane(lane) end
            lane = lanes and lanes.debuff
            if lane then ClearLane(lane) end
            return false
        end
    end

    local changedCount = 0

    local lanes = state.lanes
    local lane = lanes and lanes.buff
    if lane and lane.config and lane.config.enabled then
        if full then
            if FullScanLane(lane, unit) then
                changedCount = changedCount + 1
                RenderLane(lane, unit)
            end
        elseif UpdateLaneFromDelta(lane, unit, updateInfo) then
            changedCount = changedCount + 1
            RenderLane(lane, unit)
        end
    end

    lane = lanes and lanes.debuff
    if lane and lane.config and lane.config.enabled then
        if full then
            if FullScanLane(lane, unit) then
                changedCount = changedCount + 1
                RenderLane(lane, unit)
            end
        elseif UpdateLaneFromDelta(lane, unit, updateInfo) then
            changedCount = changedCount + 1
            RenderLane(lane, unit)
        end
    end

    return changedCount > 0
end

local function RenderCachedAuras(frame)
    if not frame then return false end
    local unit = frame.unit
    local state, cfg = CurrentFrameState(frame, unit)
    if not (state and cfg and cfg.enabled) then
        HideState(frame)
        return false
    end
    if state.needFullUpdate == true then
        return UpdateAuras(frame, "ForceUpdate", unit, nil, true)
    end

    local changed = false
    local lanes = state.lanes
    local lane = lanes and lanes.buff
    if lane and lane.config and lane.config.enabled then
        RenderLane(lane, unit)
        changed = true
    end
    lane = lanes and lanes.debuff
    if lane and lane.config and lane.config.enabled then
        RenderLane(lane, unit)
        changed = true
    end
    return changed
end

local function NeedsCombatAuraEvents(cfg)
    if not (cfg and cfg.enabled and cfg.lanes) then return false end
    local lane = cfg.lanes.buff
    if lane and lane.enabled and lane.needsCombatRefresh == true then return true end
    lane = cfg.lanes.debuff
    return lane and lane.enabled and lane.needsCombatRefresh == true or false
end

function A3.EnableFrame(frame)
    if not (frame and frame.unit and MANAGED_UNITS[frame.unit]) then return false end
    local cfg = A3.ResolveUnitFrameConfig(frame.unit)
    if not (cfg and cfg.enabled) then
        HideState(frame)
        A3.SetUnitFrameOwner(frame.unit, frame, false)
        return false
    end
    ApplyConfig(frame, cfg)
    A3._runtimeFrames = A3._runtimeFrames or {}
    A3._runtimeFrames[frame.unit] = frame
    A3.SetUnitFrameOwner(frame.unit, frame, true)
    UpdateAuras(frame, "ForceUpdate", frame.unit, nil, true)
    return true
end

function A3.DisableFrame(frame)
    if not frame then return true end
    local unit = frame.unit
    HideState(frame)
    if unit then
        if A3._runtimeFrames and A3._runtimeFrames[unit] == frame then
            A3._runtimeFrames[unit] = nil
        end
        A3.SetUnitFrameOwner(unit, frame, false)
    end
    frame._msufA3UnitAuraOwner = nil
    return true
end

function A3.RenderFrame(frame)
    if not frame then return false end
    return UpdateAuras(frame, "ForceUpdate", frame.unit, nil, true)
end

A3.ForceUpdateFrame = A3.RenderFrame
A3.RenderCachedFrame = RenderCachedAuras

function A3.HandleUnitAura(frame, event, unit, updateInfo)
    return UpdateAuras(frame, event, unit, updateInfo, false)
end

function A3.UnitFrameOwnsUnitAura(unit, frame)
    unit = NormalizeRuntimeUnit(unit)
    return unit and A3._runtimeFrames and A3._runtimeFrames[unit] == frame or false
end

function A3.RuntimeOwnsUnit(unit)
    unit = NormalizeRuntimeUnit(unit)
    return unit and A3._runtimeFrames and A3._runtimeFrames[unit] ~= nil or false
end

local function RequestUnitNow(unit)
    local didWork = false
    EachRuntimeUnit(unit, function(runtimeUnit)
        local frame = (A3._runtimeFrames and A3._runtimeFrames[runtimeUnit])
            or (UF.frames and UF.frames[runtimeUnit])
            or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames[runtimeUnit])
            or _G["MSUF_" .. runtimeUnit]
        if frame then
            if UF.ApplyElementToFrame then
                UF.ApplyElementToFrame(frame, "Auras", frame.MSUFSpec, nil)
            else
                A3.EnableFrame(frame)
            end
            didWork = true
        end
    end)
    return didWork
end

function A3.RequestUnit(unit, delay)
    delay = tonumber(delay) or 0
    if delay > 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, function() RequestUnitNow(unit) end)
        return true
    end
    return RequestUnitNow(unit)
end

function A3.RefreshAll()
    A3.BumpRuntimeConfig()
    A3._runtimeConfigCache = nil
    RequestUnitNow("*")
    return true
end

function A3.RefreshUnit(unit)
    A3.BumpRuntimeConfig()
    A3._runtimeConfigCache = nil
    return A3.RequestUnit(unit, 0)
end

function _G.MSUF_Auras3_ApplyFontsFromGlobal()
    local frames = A3._runtimeFrames
    if not frames then return true end
    for _, frame in pairs(frames) do
        local state = frame and frame._msufA3State
        if state then
            for _, lane in pairs(state.lanes) do
                for i = 1, lane.createdButtons or 0 do
                    local button = lane[i]
                    if button then ApplyButtonLayout(lane, button, i) end
                end
            end
        end
    end
    return true
end

local AurasElement = {
    events = { "UNIT_AURA" },
    unitlessEvents = EMPTY_EVENTS,
}

function AurasElement.IsEnabled(frame)
    return frame and frame.unit and A3.UnitFrameAuraEnabled(frame.unit) == true
end

function AurasElement.GetUnitlessEvents(frame)
    local cfg = frame and frame.unit and A3.ResolveUnitFrameConfig(frame.unit)
    return NeedsCombatAuraEvents(cfg) and COMBAT_AURA_EVENTS or EMPTY_EVENTS
end

function AurasElement.Create(frame)
    if frame then EnsureState(frame) end
end

function AurasElement.Apply(frame)
    if not frame then return end
    local cfg = A3.ResolveUnitFrameConfig(frame.unit)
    if cfg and cfg.enabled then
        ApplyConfig(frame, cfg)
        if frame._msufActiveElements and frame._msufActiveElements.Auras == true then
            UpdateAuras(frame, "ForceUpdate", frame.unit, nil, true)
        end
    else
        HideState(frame)
    end
end

function AurasElement.Enable(frame)
    return A3.EnableFrame(frame)
end

function AurasElement.Disable(frame)
    return A3.DisableFrame(frame)
end

function AurasElement.Update(frame, event, unit, updateInfo)
    if event == "ForceUpdate"
        or event == "MSUF_FORCE_UPDATE" then
        return A3.RenderFrame(frame)
    end
    if event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED" then
        return RenderCachedAuras(frame)
    end
    return A3.HandleUnitAura(frame, event, unit, updateInfo)
end

UF.RegisterElement("Auras", AurasElement)

A3.frontendOnly = false
A3.backendEnabled = true
A3.unitFrameAuras = true
MSUF.AuraBackendEnabled = true

_G.MSUF_A3_RequestUnit = A3.RequestUnit
_G.MSUF_Auras3_RefreshUnit = A3.RefreshUnit
_G.MSUF_Auras3_RefreshAll = A3.RefreshAll
