--- Classic feature compiler for the scan-based Auras3 runtime.
---
--- Retail 12.1 assigns custom aura groups and fixed indicators through
--- CustomAuraContainerTemplate. Mists/TBC expose the same AuraData/filter
--- contract, but not that protected container. This module translates the
--- shared MSUF profile model into ordinary scan lanes consumed by the Classic
--- backend. It owns no events and performs no polling.
if not (select(2, ...) and select(2, ...).Client and select(2, ...).Client.IsClassic) then return end

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then return end

local Features = A3.ClassicFeatures or {}
A3.ClassicFeatures = Features

local type, tostring, tonumber, pairs, next, select = type, tostring, tonumber, pairs, next, select
local math_floor, math_max, math_min = math.floor, math.max, math.min
local table_sort = table.sort
local UnitClass = _G.UnitClass
local C_Spell = _G.C_Spell
local GetSpellInfo = _G.GetSpellInfo
local IsSecret = _G.issecretvalue or function() return false end

local function Number(value, fallback, minValue, maxValue)
    value = tonumber(value)
    if value == nil then value = fallback end
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

local function Round(value)
    value = tonumber(value) or 0
    return math_floor(value + 0.5)
end

local function Bool(value, fallback)
    if value == nil then return fallback == true end
    return value == true
end

local function Scope(unit)
    if type(unit) == "string" and unit:match("^boss%d+$") then return "boss" end
    return unit
end

local function SpellName(spellID)
    spellID = tonumber(spellID)
    if not (spellID and spellID > 0) then return nil end
    -- Legacy GetSpellInfo resolves synchronously on Classic clients, so the
    -- compile-time name hashes (rank/alias matching, auto-exclusions) are
    -- deterministic at login. C_Spell.GetSpellName is lazy-load backed and
    -- returned nil for uncached IDs, which left name hashes empty and let the
    -- same DoT render in both the custom container and the debuff lane.
    local name
    if type(GetSpellInfo) == "function" then
        name = GetSpellInfo(spellID)
    end
    if (type(name) ~= "string" or name == "")
        and C_Spell and type(C_Spell.GetSpellName) == "function" then
        name = C_Spell.GetSpellName(spellID)
    end
    return type(name) == "string" and name ~= "" and name or nil
end

local function SpellIDHash(value)
    local out, count = {}, 0
    local function Add(raw)
        local spellID = tonumber(type(raw) == "number" and raw or tostring(raw or ""):match("%d+"))
        if spellID and spellID > 0 then
            spellID = math_floor(spellID + 0.5)
            if out[spellID] ~= true then
                out[spellID] = true
                count = count + 1
            end
        end
    end
    if type(value) == "string" then
        for token in value:gmatch("%d+") do Add(token) end
    elseif type(value) == "table" then
        for key, enabled in pairs(value) do
            if enabled ~= false then
                Add((type(enabled) == "number" or type(enabled) == "string") and enabled or key)
            end
        end
    elseif value ~= nil then
        Add(value)
    end
    return count > 0 and out or nil
end

local function MergeSpellIDs(out, source, disabled)
    out = out or {}
    for spellID in pairs(source or {}) do
        if not (disabled and disabled[spellID] == true) then
            if type(A3.AddAuraSpellIDAndAliases) == "function" then
                A3.AddAuraSpellIDAndAliases(out, spellID)
            else
                out[spellID] = true
            end
        end
    end
    return out
end

local function NameHash(spellIDs)
    local out
    for spellID in pairs(spellIDs or {}) do
        local name = SpellName(spellID)
        if name then
            out = out or {}
            out[name] = true
        end
    end
    return out
end

--- Compile Retail's aura-filter model into a Classic-safe scan filter plus
--- post-scan requirements.  Mists/TBC expose most modern AuraData fields, but
--- their AuraUtil whitelist does not accept every Retail token (notably
--- IMPORTANT, DISPELLABLE, BOSS, STEALABLE, and !PLAYER).  Passing those
--- strings into GetAuraSlots can silently empty a lane, so Classic scans only
--- with the universally valid base token and the additive nameplate flag.
local function NewFilterRequirements()
    return {}
end

local function HasFilterRequirements(req)
    return req and next(req) ~= nil or false
end

local function FinalizeFilterPlan(helpful, includeNameplateOnly, req)
    local base = helpful and "HELPFUL" or "HARMFUL"
    return {
        helpful = helpful == true,
        scanFilter = includeNameplateOnly and (base .. "|INCLUDE_NAME_PLATE_ONLY") or base,
        requirements = HasFilterRequirements(req) and req or nil,
        hasRequirements = HasFilterRequirements(req),
        needsPlayerFlag = req and (req.player == true or req.notPlayer == true) or false,
        needsCombatRefresh = req and req.raidInCombat == true or false,
    }
end


function Features.CompileSettingsFilter(filters, helpful)
    filters = type(filters) == "table" and filters.enabled ~= false and filters or {}
    local req = NewFilterRequirements()
    -- Classic deliberately exposes only the stable PLAYER token. Keep every
    -- other Retail-era setting untouched in SavedVariables so profiles can be
    -- moved between clients without losing their richer Retail configuration.
    if filters.onlyMine == true then req.player = true end
    return FinalizeFilterPlan(helpful, false, req)
end

function Features.CompileRawFilter(filter, helpful)
    local req = NewFilterRequirements()
    local includeNameplateOnly = false
    for raw in tostring(filter or ""):gmatch("[^|]+") do
        local token = raw:upper():gsub("^%s+", ""):gsub("%s+$", "")
        if token == "PLAYER" then req.player = true
        elseif token == "!PLAYER" or token == "NOT_PLAYER" then req.notPlayer = true
        elseif token == "IMPORTANT" then req.important = true
        elseif token == "RAID" then req.raid = true
        elseif token == "RAID_IN_COMBAT" then req.raidInCombat = true
        elseif token == "RAID_PLAYER_DISPELLABLE" then req.raidPlayerDispellable = true
        elseif token == "DISPELLABLE" then req.dispellableAny = true
        elseif token == "CANCELABLE" then req.cancelable = true
        elseif token == "!CANCELABLE" or token == "NOT_CANCELABLE" then req.notCancelable = true
        elseif token == "CROWD_CONTROL" then req.crowdControl = true
        elseif token == "EXTERNAL_DEFENSIVE" then req.externalDefensive = true
        elseif token == "BIG_DEFENSIVE" then req.bigDefensive = true
        elseif token == "STEALABLE" then req.stealable = true
        elseif token == "BOSS" then req.boss = true
        elseif token == "INCLUDE_NAME_PLATE_ONLY" then includeNameplateOnly = true end
    end
    return FinalizeFilterPlan(helpful, includeNameplateOnly, req)
end

function Features.IsImportantAura(data)
    local rawSpellID = data and data.spellId
    local spellID = not IsSecret(rawSpellID) and tonumber(rawSpellID) or nil
    local isImportant = C_Spell and C_Spell.IsSpellImportant
    if not (spellID and type(isImportant) == "function") then return false end
    return isImportant(spellID) == true
end

function Features.MatchFilterRequirements(plan, unit, data, matchFilter)
    local req = plan and plan.requirements or plan
    if not req then return true end
    if req.player == true and data.isPlayerAura ~= true then return false end
    if req.notPlayer == true and data.isPlayerAura == true then return false end
    if req.important == true and not Features.IsImportantAura(data) then return false end
    if req.stealable == true and data.isStealable ~= true then return false end
    if req.boss == true and data.isBossAura ~= true then return false end
    if req.dispellableAny == true then
        local dispelName = not IsSecret(data.dispelName) and data.dispelName or nil
        if type(dispelName) ~= "string" or dispelName == "" then return false end
    end
    local auraInstanceID = data.auraInstanceID
    local base = plan and plan.helpful == false and "HARMFUL" or "HELPFUL"
    if req.raid == true and not matchFilter(unit, auraInstanceID, base .. "|RAID") then return false end
    if req.raidInCombat == true and not matchFilter(unit, auraInstanceID, base .. "|RAID_IN_COMBAT") then return false end
    if req.raidPlayerDispellable == true
        and not matchFilter(unit, auraInstanceID, base .. "|RAID_PLAYER_DISPELLABLE") then return false end
    if req.cancelable == true and not matchFilter(unit, auraInstanceID, "HELPFUL|CANCELABLE") then return false end
    if req.notCancelable == true and not matchFilter(unit, auraInstanceID, "HELPFUL|NOT_CANCELABLE") then return false end
    if req.crowdControl == true and not matchFilter(unit, auraInstanceID, "HARMFUL|CROWD_CONTROL") then return false end
    if req.externalDefensive == true
        and not matchFilter(unit, auraInstanceID, "HELPFUL|EXTERNAL_DEFENSIVE") then return false end
    if req.bigDefensive == true
        and not matchFilter(unit, auraInstanceID, "HELPFUL|BIG_DEFENSIVE") then return false end
    return true
end

local function PlayerClass()
    if type(UnitClass) ~= "function" then return nil end
    local _, class = UnitClass("player")
    return class
end

local function PlayerDefensiveHash(entry)
    local class = PlayerClass()
    local spells = class and A3.PlayerDefensiveData and A3.PlayerDefensiveData[class]
    local base = {}
    for i = 1, type(spells) == "table" and #spells or 0 do
        local spellID = tonumber(spells[i] and spells[i][1])
        if spellID then base[spellID] = true end
    end
    local disabled = SpellIDHash(entry and entry.disabledPredefinedSpellIDs)
    local out = MergeSpellIDs(nil, base, disabled)
    out = MergeSpellIDs(out, SpellIDHash(entry and (entry.spellIDs or entry.includeSpellIDs)))
    return next(out) and out or nil
end

local function TargetDotKnownHash()
    local cached = Features._targetDotKnownHash
    if cached then return cached end
    cached = {}
    for _, spells in pairs(A3.TargetDotData or {}) do
        for i = 1, #spells do
            local spellID = tonumber(spells[i] and spells[i][1])
            if spellID then cached[spellID] = true end
        end
    end
    Features._targetDotKnownHash = cached
    return cached
end

local function TargetDotHash(entry)
    local selected = SpellIDHash(entry and (entry.spellIDs or entry.includeSpellIDs))
    if not selected then return nil end
    local known = TargetDotKnownHash()
    local custom = SpellIDHash(entry and entry.customSpellIDs)
    local out = {}
    for spellID in pairs(selected) do
        if known[spellID] == true or (custom and custom[spellID] == true) then
            if type(A3.AddAuraSpellIDAndAliases) == "function" then
                A3.AddAuraSpellIDAndAliases(out, spellID)
            else
                out[spellID] = true
            end
        end
    end
    return next(out) and out or nil
end

local function Growth(value)
    value = tostring(value or "LEFTDOWN"):upper():gsub("[^A-Z]", "")
    local vertical = value:find("UP", 1, true) == 1 or value:find("DOWN", 1, true) == 1
    local xSign = value:find("LEFT", 1, true) and -1 or 1
    local ySign = value:find("UP", 1, true) and 1 or -1
    return xSign, ySign, vertical
end

local function Grid(maxCount, perRow, vertical)
    if maxCount <= 0 then return 0, 0 end
    local primary = math_min(maxCount, perRow)
    local secondary = math_floor((maxCount + perRow - 1) / perRow)
    if vertical then return secondary, primary end
    return primary, secondary
end

local function ButtonAnchor(xSign, ySign)
    return (ySign > 0 and "BOTTOM" or "TOP") .. (xSign < 0 and "RIGHT" or "LEFT")
end

local function Anchor(value, fallback)
    value = tostring(value or ""):upper()
    if value == "TOPLEFT" or value == "TOP" or value == "TOPRIGHT"
        or value == "LEFT" or value == "CENTER" or value == "RIGHT"
        or value == "BOTTOMLEFT" or value == "BOTTOM" or value == "BOTTOMRIGHT" then
        return value
    end
    return fallback or "TOPRIGHT"
end

local function SortMode(value)
    value = tostring(value or "DEFAULT"):upper():gsub("[%s%-]+", "_")
    if value == "DEFAULT" or value == "PLAYER" then return 1 end
    if value == "EXPIRATION" or value == "EXPIRATION_ONLY" then return 3 end
    if value == "NAME" or value == "NAME_ONLY" then return 5 end
    if value == "DURATION" or value == "DURATION_ONLY" or value == "BIG_DEFENSIVE" then return 2 end
    if value == "INSTANCE_ID" then return 0 end
    return 0
end

local function BaseLane(unit, kind, entry, index, spellIDs, helpful, rootKey, forcePlayer)
    local placed = type(entry.placed) == "table" and entry.placed or {}
    local filters = type(entry.filters) == "table" and entry.filters
        or { enabled = true, onlyMine = entry.onlyOwn == true }
    local activeFilters = filters.enabled ~= false and filters or nil
    local size = Number(placed.size, 24, 1, 128)
    local buttonWidth = tostring(placed.type or "icon"):lower() == "bar"
        and Number(placed.barWidth, 54, 1, 512) or size
    local buttonHeight = size
    local spacing = Number(placed.spacing, 2, 0, 64)
    local maxCount = Round(Number(placed.max, 8, 0, 40))
    local perRow = Round(Number(placed.perRow, 4, 1, 40))
    local xSign, ySign, vertical = Growth(placed.growth)
    local cols, rows = Grid(maxCount, perRow, vertical)
    local sortOrder = SortMode(placed.sortMethod)
    if forcePlayer == true and (not activeFilters or activeFilters.onlyMine ~= true) then
        local source = activeFilters or {}
        activeFilters = {}
        for key, value in pairs(source) do activeFilters[key] = value end
        activeFilters.onlyMine = true
    end
    local filterPlan = Features.CompileSettingsFilter(activeFilters, helpful)
    local filter = filterPlan.scanFilter
    local onlyMine = activeFilters and activeFilters.onlyMine == true or false
    local hasInclusive = filterPlan.hasRequirements == true
    local cfg = {
        kind = kind,
        rootKey = rootKey,
        sourceIndex = index,
        unit = unit,
        enabled = maxCount > 0,
        renderEnabled = maxCount > 0,
        harmful = helpful ~= true,
        filter = filter,
        playerFilter = filter .. "|PLAYER",
        importantFilter = filter .. "|IMPORTANT",
        raidFilter = filter .. "|RAID",
        raidInCombatFilter = filter .. "|RAID_IN_COMBAT",
        stealableFilter = "HELPFUL|STEALABLE",
        dispellableFilter = "HARMFUL|RAID_PLAYER_DISPELLABLE",
        bossFilter = "HARMFUL|BOSS",
        crowdControlFilter = filter .. "|CROWD_CONTROL",
        externalDefensiveFilter = filter .. "|EXTERNAL_DEFENSIVE",
        bigDefensiveFilter = filter .. "|BIG_DEFENSIVE",
        max = maxCount,
        size = size,
        buttonWidth = buttonWidth,
        buttonHeight = buttonHeight,
        spacing = spacing,
        step = size + spacing,
        stepX = buttonWidth + spacing,
        stepY = buttonHeight + spacing,
        perRow = perRow,
        cols = cols,
        rows = rows,
        width = math_max(1, cols * buttonWidth + math_max(cols - 1, 0) * spacing),
        height = math_max(1, rows * buttonHeight + math_max(rows - 1, 0) * spacing),
        x = Round(Number(placed.x, 0, -4096, 4096)),
        y = Round(Number(placed.y, 0, -4096, 4096)),
        anchor = Anchor(placed.anchor, "TOPRIGHT"),
        layer = Round(Number(entry.layer, 9, 0, 30)),
        strata = tostring(entry.strata or "AUTO"):upper(),
        alpha = Number(placed.alpha, 1, 0, 1),
        xSign = xSign,
        ySign = ySign,
        verticalGrowth = vertical,
        initialAnchor = ButtonAnchor(xSign, ySign),
        sortOrder = sortOrder,
        naturalOrder = sortOrder == 0 and placed.sortReverse ~= true,
        visibleOnlyScan = false,
        cappedFilterScan = false,
        reorderOnUpdate = sortOrder ~= 0 or placed.sortReverse == true,
        sortReverse = placed.sortReverse == true,
        clickThrough = placed.clickThrough == true,
        showTooltip = placed.showTooltip ~= false,
        showCooldownSwipe = placed.showCooldownSwipe ~= false,
        showCooldownText = placed.showCooldown ~= false,
        showCooldown = placed.showCooldown ~= false,
        showStacks = placed.showStacks ~= false,
        cooldownSize = Number(placed.cooldownSize, 14, 6, 40),
        cooldownAnchor = Anchor(placed.cooldownAnchor, "CENTER"),
        cooldownX = Number(placed.cooldownX, 0, -2000, 2000),
        cooldownY = Number(placed.cooldownY, 0, -2000, 2000),
        stackAnchor = Anchor(placed.stackAnchor, "BOTTOMRIGHT"),
        stackSize = Number(placed.stackSize, 14, 6, 40),
        stackX = Number(placed.stackX, 0, -2000, 2000),
        stackY = Number(placed.stackY, 0, -2000, 2000),
        stackR = 1, stackG = 1, stackB = 1,
        includeSpellIDs = spellIDs,
        includeSpellNames = NameHash(spellIDs),
        filterPlan = filterPlan,
        filterRequirements = filterPlan.requirements,
        hasFilterWork = true,
        classicFeatureMatch = true,
        hidePermanent = filters.hidePermanent == true,
        maxDuration = 0,
        onlyMine = onlyMine,
        onlyImportant = false,
        raid = false,
        raidInCombat = false,
        includeDispellable = false,
        dispellableAny = false,
        crowdControl = false,
        externalDefensive = false,
        bigDefensive = false,
        hasInclusive = hasInclusive,
        needsPlayerFlag = filterPlan.needsPlayerFlag == true
            or sortOrder == 1 or sortOrder == 2 or sortOrder == 3 or sortOrder == 5,
        needsCombatRefresh = filterPlan.needsCombatRefresh == true,
        frameEffect = type(entry.frame) == "table" and entry.frame or nil,
        visual = tostring(placed.type or "icon"):lower(),
        iconEffect = tostring(placed.iconEffect or "none"):lower(),
        color = type(entry.color) == "table" and entry.color or { 0.69, 0.50, 0.88, 1 },
        display = entry.name or ("Custom " .. tostring(index)),
        icon = entry.icon,
        missing = placed.missing == true,
    }
    return cfg
end

local function PortraitLane(lane, frameSpec, entry, kind, rootKey)
    local portrait = frameSpec and frameSpec.portrait
    local holderEnabled = portrait and (portrait.enabled == true or entry.portraitPositionWhenDisabled == true)
    if not holderEnabled then return nil end
    local width = Number(portrait.width or portrait.size, lane.size, 1, 512)
    local height = Number(portrait.height or portrait.size, lane.size, 1, 512)
    local maxCount = Round(Number(entry.portraitMaxIcons, 1, 1, 8))
    local out = {}
    for key, value in pairs(lane) do out[key] = value end
    out.kind = kind
    out.rootKey = rootKey
    out.anchorTarget = "portrait"
    out.portraitOverlay = true
    out.max = maxCount
    out.size = math_min(width, height)
    out.buttonWidth = width
    out.buttonHeight = height
    out.step = out.size + out.spacing
    out.stepX = width + out.spacing
    out.stepY = height + out.spacing
    out.perRow = maxCount
    out.cols, out.rows = maxCount, 1
    out.width = maxCount * width + math_max(maxCount - 1, 0) * out.spacing
    out.height = height
    out.anchor = "CENTER"
    out.initialAnchor = "CENTER"
    out.x, out.y = 0, 0
    out.xSign, out.ySign, out.verticalGrowth = 1, -1, false
    out.showCooldownText = lane.showCooldownText == true and entry.portraitCooldownText ~= false
    return out
end

local function EffectiveContainers(auras, unit)
    local root = type(auras) == "table" and auras.customContainers or nil
    local record = type(root) == "table" and type(root.perUnit) == "table" and root.perUnit[Scope(unit)] or nil
    return type(record) == "table" and type(record.items) == "table" and record.items or nil
end

local function EffectiveDisplays(auras, unit)
    local root = type(auras) == "table" and auras.customDisplays or nil
    local record = type(root) == "table" and type(root.perUnit) == "table" and root.perUnit[Scope(unit)] or nil
    if type(record) == "table" and record.override == true and type(record.items) == "table" then
        return record.items
    end
    return nil
end

function Features.CompileUnitLanes(auras, unit, frameSpec)
    local source = EffectiveContainers(auras, unit)
    local lanes, order = {}, {}
    if type(source) == "table" then
        for index = 1, 4 do
            local entry = source[index]
            if type(entry) == "table" and entry.enabled == true then
                local playerDefensive = unit == "player" and (index == 4 or entry.playerDefensives == true)
                local targetDot = not playerDefensive and index == 4 and unit ~= "player"
                local spellIDs = playerDefensive and PlayerDefensiveHash(entry)
                    or (targetDot and TargetDotHash(entry) or SpellIDHash(entry.spellIDs or entry.includeSpellIDs))
                if spellIDs then
                    local helpful = playerDefensive or tostring(entry.auraType or "BUFF"):upper() ~= "DEBUFF"
                    local kind = "custom" .. tostring(index)
                    local lane = BaseLane(unit, kind, entry, index, spellIDs, helpful,
                        "CustomAuras" .. tostring(index), targetDot)
                    if entry.portraitIcon == true and playerDefensive then
                        lane = PortraitLane(lane, frameSpec, entry, "defensivePortrait", "DefensivePortrait") or lane
                    elseif entry.portraitIcon == true and targetDot then
                        lane = PortraitLane(lane, frameSpec, entry, "targetDotPortrait", "TargetDotPortrait") or lane
                    end
                    if A3.ClassicVisuals and type(A3.ClassicVisuals.EnrichCustomLane) == "function" then
                        A3.ClassicVisuals.EnrichCustomLane(lane, entry, frameSpec)
                    end
                    lanes[lane.kind] = lane
                    order[#order + 1] = lane.kind
                end
            end
        end
        return lanes, order, source
    end

    local legacy = EffectiveDisplays(auras, unit)
    for index = 1, type(legacy) == "table" and #legacy or 0 do
        local entry = legacy[index]
        if type(entry) == "table" and entry.enabled ~= false then
            local spellIDs = SpellIDHash(entry.spellIDs or entry.includeSpellIDs)
            if spellIDs then
                local kind = "customDisplay" .. tostring(index)
                local lane = BaseLane(unit, kind, entry, index, spellIDs,
                    tostring(entry.auraType or "BUFF"):upper() ~= "DEBUFF", "CustomDisplay" .. tostring(index))
                lane.max = 1
                if A3.ClassicVisuals and type(A3.ClassicVisuals.EnrichCustomLane) == "function" then
                    A3.ClassicVisuals.EnrichCustomLane(lane, entry, frameSpec)
                end
                lanes[kind] = lane
                order[#order + 1] = kind
            end
        end
    end
    return next(lanes) and lanes or nil, order, nil
end

local function AddIndicatorLane(lanes, order, unit, item, index, prefix)
    if type(item) ~= "table" or item.enabled == false then return end
    local spellIDs = item.includeSpellIDs or SpellIDHash(item.spellIDs)
    if not spellIDs then return end
    local entry = {
        name = item.display or item.auraName,
        auraType = "BUFF",
        onlyOwn = item.onlyOwn == true,
        placed = item.placed,
        frame = item.frame,
        layer = item.layer,
        strata = item.strata,
        color = item.color,
        icon = item.icon,
        filters = { onlyMine = item.onlyOwn == true },
    }
    local kind = prefix .. tostring(index)
    local lane = BaseLane(unit, kind, entry, index, spellIDs, true, "ClassicIndicator" .. tostring(prefix) .. tostring(index))
    lane.max = 1
    lane.cols, lane.rows = 1, 1
    lane.width, lane.height = lane.buttonWidth, lane.buttonHeight
    if A3.ClassicVisuals and type(A3.ClassicVisuals.EnrichCustomLane) == "function" then
        A3.ClassicVisuals.EnrichCustomLane(lane, entry, nil)
    end
    lanes[kind] = lane
    order[#order + 1] = kind
end

function Features.CompileGroupIndicatorLanes(frame, unit)
    local spec = frame and frame.MSUFSpec
    local lanes, order = {}, {}
    local spellRoot = spec and spec.spellIndicators
    local items = spellRoot and spellRoot.enabled == true and spellRoot.items
    for i = 1, type(items) == "table" and #items or 0 do
        AddIndicatorLane(lanes, order, unit, items[i], i, "spellIndicator")
    end
    local corners = spec and spec.cornerIndicators
    local customSlots = corners and corners.enabled == true and corners.customSlots
    for i = 1, type(customSlots) == "table" and #customSlots or 0 do
        AddIndicatorLane(lanes, order, unit, customSlots[i], i, "cornerIndicator")
    end
    return next(lanes) and lanes or nil, order
end

local function PublicNumber(value)
    if value == nil or IsSecret(value) then return nil end
    return tonumber(value)
end

function Features.MatchAura(cfg, unit, data, matchFilter)
    if not (cfg and type(data) == "table") then return false end
    local spellID = PublicNumber(data.spellId)
    local name = not IsSecret(data.name) and data.name or nil
    if cfg.includeSpellIDs then
        if not ((spellID and cfg.includeSpellIDs[spellID] == true)
            or (type(name) == "string" and cfg.includeSpellNames and cfg.includeSpellNames[name] == true)) then
            return false
        end
    end
    local duration = PublicNumber(data.duration) or 0
    if cfg.hidePermanent == true and duration <= 0 then return false end
    if cfg.maxDuration and cfg.maxDuration > 0 and duration > cfg.maxDuration then return false end
    if cfg.filterRequirements then
        return Features.MatchFilterRequirements(cfg.filterPlan or cfg.filterRequirements, unit, data, matchFilter)
    end
    if cfg.hasInclusive == true then
        if cfg.onlyMine == true and data.isPlayerAura == true then return true end
        local auraInstanceID = data.auraInstanceID
        if cfg.onlyImportant == true and matchFilter(unit, auraInstanceID, cfg.importantFilter) then return true end
        if cfg.raid == true and matchFilter(unit, auraInstanceID, cfg.raidFilter) then return true end
        if cfg.raidInCombat == true and matchFilter(unit, auraInstanceID, cfg.raidInCombatFilter) then return true end
        if cfg.includeDispellable == true and matchFilter(unit, auraInstanceID, cfg.dispellableFilter) then return true end
        if cfg.crowdControl == true and matchFilter(unit, auraInstanceID, cfg.crowdControlFilter) then return true end
        if cfg.externalDefensive == true and matchFilter(unit, auraInstanceID, cfg.externalDefensiveFilter) then return true end
        if cfg.bigDefensive == true and matchFilter(unit, auraInstanceID, cfg.bigDefensiveFilter) then return true end
        return false
    end
    return true
end

function Features.ApplyAutoExclusions(buff, debuff, customLanes, source, unit)
    if type(customLanes) ~= "table" then return end
    for _, lane in pairs(customLanes) do
        local entry
        if type(source) == "table" then
            -- Portrait lane kinds carry no trailing index; sourceIndex is the
            -- authoritative link back to the container entry.
            local index = tonumber(lane.sourceIndex)
                or tonumber(tostring(lane.kind):match("(%d+)$"))
            entry = index and source[index] or nil
        end
        local target = lane.harmful == true and debuff or buff
        -- entry is nil for legacy customDisplay lanes (no source table) and
        -- for portrait lane kinds without a trailing index. Exclusion is the
        -- opt-out default, so a missing entry must still deduplicate -- those
        -- lanes previously rendered their auras a second time in the base
        -- buff/debuff lane.
        local allow
        if entry then
            allow = (unit == "player" and entry.autoBlacklistPlayerBuffs ~= false)
                or (unit ~= "player" and entry.autoBlacklistDebuffs ~= false)
        else
            allow = true
        end
        if allow and target then
            target.classicExcludeSpellIDs = target.classicExcludeSpellIDs or {}
            target.classicExcludeSpellNames = target.classicExcludeSpellNames or {}
            for spellID in pairs(lane.includeSpellIDs or {}) do target.classicExcludeSpellIDs[spellID] = true end
            for name in pairs(lane.includeSpellNames or {}) do target.classicExcludeSpellNames[name] = true end
            target.hasFilterWork = true
        end
    end
end

function Features.IsAutoExcluded(cfg, data)
    if not (cfg and data) then return false end
    local spellID = PublicNumber(data.spellId)
    if spellID and cfg.classicExcludeSpellIDs and cfg.classicExcludeSpellIDs[spellID] == true then return true end
    local name = not IsSecret(data.name) and data.name or nil
    return type(name) == "string" and cfg.classicExcludeSpellNames
        and cfg.classicExcludeSpellNames[name] == true or false
end

Features.SpellIDHash = SpellIDHash
Features.NameHash = NameHash
Features.Scope = Scope
