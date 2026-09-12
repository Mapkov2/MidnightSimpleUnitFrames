--- Auras3/SpellIndicator_Config: immutable slot compilation, signatures and shared layout rules.
--- Registered at load time; the original entrypoint owns initialization order.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
A3.SpellIndicatorModules = A3.SpellIndicatorModules or {}
A3.SpellIndicatorModules.Config = function()
local type, tostring, tonumber, pairs = type, tostring, tonumber, pairs
local table_concat, table_sort = table.concat, table.sort
local math_floor = math.floor
local FrameLayers = MSUF.UF and MSUF.UF.Layers or {}
local SPELL_ICON_BASE_OFFSET = tonumber(FrameLayers.SPELL_ICON_BASE_OFFSET) or 64
local UNIT_SPELL_BASE_OFFSET = tonumber(FrameLayers.UNIT_AURA_BASE_OFFSET) or 10
local issecretvalue = _G.issecretvalue
local MAX_FINITE_AURA_DURATION = 2147483647
local Runtime = A3.SpellIndicators
local DEFAULT_SHARED = {
    cooldownTextSize = 8,
    stackTextSize = 10,
    cooldownDecimalSeconds = 5,
    durationBarHeight = 2,
    durationBarDisplay = "BAR_ONLY",
    durationBarPosition = "BOTTOM",
    durationBarDirection = "REMAINING",
}

local function Round(value)
    return math_floor((tonumber(value) or 0) + 0.5)
end

local function ClampNumber(value, fallback, minValue, maxValue)
    local n = tonumber(value)
    if n == nil then n = tonumber(fallback) or 0 end
    if minValue ~= nil and n < minValue then n = minValue end
    if maxValue ~= nil and n > maxValue then n = maxValue end
    return n
end

local function Clamp01(value, fallback)
    local n = tonumber(value)
    if n == nil then n = tonumber(fallback) or 0 end
    if n < 0 then return 0 end
    if n > 1 then return 1 end
    return n
end

local NormalizeFrameStrata = _G.MSUF_NormalizeFrameStrata

local ReadParentFrameStrata = _G.MSUF_AuraReadParentFrameStrata

local function ResolveFrameStrata(parentFrame, value)
    -- Retained legacy strata values are migration data only. All layer-aware
    -- visuals share their owning unit frame's strata.
    return ReadParentFrameStrata(parentFrame)
end

local SyncFrameStrata = _G.MSUF_AuraSyncFrameStrata

local VALID_NATIVE_FILTER_TOKENS = {
    HELPFUL = true, HARMFUL = true, PLAYER = true, RAID = true,
    CANCELABLE = true, MAW = true, INCLUDE_NAME_PLATE_ONLY = true,
    EXTERNAL_DEFENSIVE = true, CROWD_CONTROL = true, RAID_IN_COMBAT = true,
    RAID_PLAYER_DISPELLABLE = true, BIG_DEFENSIVE = true, IMPORTANT = true,
    DISPELLABLE = true,
}

local function AddNativeFilterToken(out, seen, token, baseToken)
    token = tostring(token or ""):upper():gsub("^%s+", ""):gsub("%s+$", "")
    local negated = token:sub(1, 1) == "!"
    if negated then token = token:sub(2):gsub("^%s+", ""):gsub("%s+$", "") end
    if token == "PLAYER_CAST" or token == "CAST_BY_ME" or token == "MINE" then token = "PLAYER" end
    if token == "ALL" or token == "ANY" then return end
    if token == "NOT_CANCELABLE" then token, negated = "CANCELABLE", true end
    if token == "BUFF" then token = "HELPFUL" end
    if token == "DEBUFF" then token = "HARMFUL" end
    if token == "" or not VALID_NATIVE_FILTER_TOKENS[token] then return end
    if negated and (token == "HELPFUL" or token == "HARMFUL") then return end
    if (token == "HELPFUL" or token == "HARMFUL") and token ~= baseToken then return end
    if negated then token = "!" .. token end
    if token == "!PLAYER" and seen.PLAYER then return end
    if token == "PLAYER" and seen["!PLAYER"] then
        seen["!PLAYER"] = nil
        for i = #out, 1, -1 do if out[i] == "!PLAYER" then table.remove(out, i) end end
    end
    if seen[token] then return end
    seen[token] = true
    out[#out + 1] = token
end

local function NormalizeNativeFilterString(filter, fallback)
    fallback = tostring(fallback or "")
    filter = tostring(filter or "")
    local baseToken = "HELPFUL"
    for token in (fallback .. "|" .. filter):gmatch("[^|]+") do
        token = token:upper():gsub("^%s+", ""):gsub("%s+$", "")
        if token == "HARMFUL" or token == "DEBUFF" then
            baseToken = "HARMFUL"
            break
        elseif token == "HELPFUL" or token == "BUFF" then
            baseToken = "HELPFUL"
            break
        end
    end
    local out, seen = {}, {}
    AddNativeFilterToken(out, seen, baseToken, baseToken)
    for token in fallback:gmatch("[^|]+") do AddNativeFilterToken(out, seen, token, baseToken) end
    for token in filter:gmatch("[^|]+") do AddNativeFilterToken(out, seen, token, baseToken) end
    return table_concat(out, "|")
end

local AuraSpellIDFromKey = _G.MSUF_AuraSpellIDFromKey

local function CandidateFiltersFromSpellIDs(spellIDs, fieldName)
    fieldName = fieldName or "includeSpellIDs"
    if type(spellIDs) ~= "table" then return nil, nil end
    local out
    for key, enabled in pairs(spellIDs) do
        local spellID
        if enabled == true or enabled == nil then
            spellID = AuraSpellIDFromKey(key)
        elseif enabled ~= false then
            local valueType = type(enabled)
            if valueType == "number" or valueType == "string" then
                spellID = AuraSpellIDFromKey(enabled) or AuraSpellIDFromKey(key)
            elseif valueType == "table" and enabled.enabled ~= false then
                spellID = AuraSpellIDFromKey(enabled.spellID or enabled.spellId or enabled.id or enabled[1]) or AuraSpellIDFromKey(key)
            end
        end
        if spellID then
            if not out then out = {} end
            if type(A3.AddAuraSpellIDAndAliases) == "function" then
                A3.AddAuraSpellIDAndAliases(out, spellID)
            else
                out[spellID] = true
            end
        end
    end
    if not out then return nil, nil end
    local parts, count = {}, 0
    for spellID in pairs(out) do
        count = count + 1
        parts[count] = tostring(spellID)
    end
    if count == 0 then return nil, nil end
    table_sort(parts)
    return { [fieldName] = out }, fieldName .. ":" .. table_concat(parts, ",")
end

local function AddHidePermanentCandidateFilter(candidateFilters, candidateFilterSignature, hidePermanent)
    if hidePermanent ~= true then return candidateFilters, candidateFilterSignature end
    candidateFilters = candidateFilters or {}
    candidateFilters.maxDuration = MAX_FINITE_AURA_DURATION
    local part = "maxDuration:" .. tostring(MAX_FINITE_AURA_DURATION)
    candidateFilterSignature = candidateFilterSignature and (candidateFilterSignature .. ";" .. part) or part
    return candidateFilters, candidateFilterSignature
end

local function IdentityCandidateMode(nativeFilter, candidateFilters)
    if type(candidateFilters) ~= "table"
        or (candidateFilters.includeSpellIDs == nil and candidateFilters.excludeSpellIDs == nil) then
        return nil
    end
    nativeFilter = tostring(nativeFilter or ""):upper()
    if nativeFilter:find("HARMFUL", 1, true) ~= nil then return "hostile" end
    if nativeFilter:find("HELPFUL", 1, true) ~= nil then return "assist" end
    return nil
end

local SPELL_INDICATOR_ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function SpellIndicatorAnchor(anchor, fallback)
    anchor = tostring(anchor or fallback or "TOPLEFT"):upper()
    return SPELL_INDICATOR_ANCHORS[anchor] and anchor or (fallback or "TOPLEFT")
end

local function SpellIndicatorSlotKey(item, index)
    local key = tostring(item and item.key or index or "spell")
    key = key:gsub("[^%w_]+", "_")
    if key == "" then key = tostring(index or "spell") end
    return "msuf_si_" .. key
end

local SlotLayoutSignature

local function SlotStructuralSignature(slot)
    -- The public 12.1 AuraSlot filter setter reparses assignments without
    -- recreating the access-restricted AuraButton. Only slot topology and
    -- initializeFrame-owned visuals remain structural.
    return tostring(slot.slotKey) .. "\030" .. tostring(slot.identityCandidateMode)
        .. "\030" .. tostring(SlotLayoutSignature(slot))
end

local function SpellIconBaseOffset(parentFrame)
    -- Same relational scale as texts/status/aura lanes (UF.Layers): unit
    -- frames use the shared element base (frame + 10 + layer), group frames
    -- the foreground band base (frame + 64 + layer). A base of 0 parked unit
    -- spell icons a full band below every text at the same popover layer.
    if parentFrame and parentFrame.MSUFSpec and parentFrame.MSUFSpec.scope == "group" then
        return SPELL_ICON_BASE_OFFSET
    end
    return UNIT_SPELL_BASE_OFFSET
end

SlotLayoutSignature = function(slot)
    local frame = slot.frameEffect
    local color = slot.color or {}
    local effectColor = frame and frame.color or {}
    local reminderColor = slot.reminderColor or {}
    return tostring(slot.visual) .. "\030" .. tostring(slot.hiddenVisual)
        .. "\030" .. tostring(slot.anchor) .. "\030" .. tostring(slot.x) .. "\030" .. tostring(slot.y)
        .. "\030" .. tostring(slot.size) .. "\030" .. tostring(slot.width) .. "\030" .. tostring(slot.height)
        .. "\030" .. tostring(slot.iconZoom) .. "\030" .. tostring(slot.iconShape)
        .. "\030" .. tostring(slot.requestedIconShape) .. "\030" .. tostring(slot.alpha)
        .. "\030" .. tostring(slot.layer) .. "\030" .. tostring(slot.strata) .. "\030" .. tostring(slot.showCooldownText)
        .. "\030" .. tostring(slot.showCooldownSwipe) .. "\030" .. tostring(slot.cooldownSwipeReverse)
        .. "\030" .. tostring(slot.cooldownSize) .. "\030" .. tostring(slot.cooldownAnchor)
        .. "\030" .. tostring(slot.cooldownX) .. "\030" .. tostring(slot.cooldownY)
        .. "\030" .. tostring(slot.cooldownDecimalSeconds)
        .. "\030" .. tostring(slot.showDurationBar) .. "\030" .. tostring(slot.durationBarHeight)
        .. "\030" .. tostring(slot.durationBarDisplay) .. "\030" .. tostring(slot.durationBarPosition)
        .. "\030" .. tostring(slot.durationBarDirection) .. "\030" .. tostring(slot.durationBarSmooth)
        .. "\030" .. tostring(slot.durationBarReverseFill) .. "\030" .. tostring(slot.growth)
        .. "\030" .. tostring(slot.showStacks) .. "\030" .. tostring(slot.stackSize)
        .. "\030" .. tostring(slot.stackAnchor) .. "\030" .. tostring(slot.stackX) .. "\030" .. tostring(slot.stackY)
        .. "\030" .. tostring(slot.showTooltip) .. "\030" .. tostring(color[1]) .. "\030" .. tostring(color[2])
        .. "\030" .. tostring(color[3]) .. "\030" .. tostring(color[4]) .. "\030" .. tostring(slot.iconEffect)
        .. "\030" .. tostring(slot.iconStyle and slot.iconStyle.signature)
        .. "\030" .. tostring(frame and frame.type)
        .. "\030" .. tostring(frame and frame.priority) .. "\030" .. tostring(frame and frame.thickness)
        .. "\030" .. tostring(frame and frame.layer)
        .. "\030" .. tostring(frame and frame.tintAlpha) .. "\030" .. tostring(frame and frame.strata)
        .. "\030" .. tostring(effectColor[1]) .. "\030" .. tostring(effectColor[2]) .. "\030" .. tostring(effectColor[3])
        .. "\030" .. tostring(effectColor[4]) .. "\030" .. tostring(A3._nativeVisualGen or 0)
        .. "\030" .. tostring(slot.showWhenMissing)
        .. "\030" .. tostring(slot.reminderAlpha)
        .. "\030" .. tostring(slot.reminderDesaturate)
        .. "\030" .. tostring(reminderColor[1])
        .. "\030" .. tostring(reminderColor[2])
        .. "\030" .. tostring(reminderColor[3])
        .. "\030" .. tostring(slot.castSpellID) .. "\030" .. tostring(slot.castUnit)
        .. "\030" .. tostring(slot.castItem) .. "\030" .. tostring(slot.castItemID)
        .. "\030" .. tostring(slot.enchantSlot) .. "\030" .. tostring(slot.enchantInventorySlot)
        .. "\030" .. tostring(slot.enchantDurationSeconds)
end

local function FinalizeSlot(slot)
    if slot then
        slot._msufA3StructuralSignature = SlotStructuralSignature(slot)
        slot._msufA3LayoutSignature = SlotLayoutSignature(slot)
    end
    return slot
end

local function NormalizeFrameEffect(raw)
    if type(raw) ~= "table" or raw.type == nil or raw.type == "" or raw.type == "none" then return nil end
    local color = type(raw.color) == "table" and raw.color or nil
    return {
        type = raw.type,
        color = color,
        priority = Round(ClampNumber(raw.priority, 5, 1, 10)),
        tintAlpha = Clamp01(raw.tintAlpha or raw.alpha or (color and color[4]), 0.20),
        thickness = ClampNumber(raw.thickness, 2, 1, 32),
        layer = Round(ClampNumber(raw.layer, 0, 0, 30)),
        strata = NormalizeFrameStrata(raw.strata, "AUTO"),
    }
end
Runtime.NormalizeFrameEffect = NormalizeFrameEffect

local function CompileSlot(unit, item, index, fallbackLayer, fallbackStrata, fallbackIconZoom, spellIconStyle)
    if not (type(unit) == "string" and unit ~= "" and type(item) == "table" and item.enabled == true) then return nil end
    local placed = type(item.placed) == "table" and item.placed or nil
    local frameEffect = NormalizeFrameEffect(item.frame)
    if not placed and not frameEffect then return nil end
    local candidateFilters = item.candidateFilters
    local candidateFilterSignature = item.candidateFilterSignature
    if candidateFilters == nil then
        candidateFilters, candidateFilterSignature = CandidateFiltersFromSpellIDs(item.includeSpellIDs, "includeSpellIDs")
    end
    -- A temporary weapon enchant is not an aura at all -- Blizzard keeps them
    -- out of aura parsing, groups and slots entirely -- so an enchant reminder
    -- legitimately has nothing to filter on.
    if not candidateFilters and item.allowAnyAura ~= true and item.enchantSlot == nil then return nil end
    candidateFilters, candidateFilterSignature = AddHidePermanentCandidateFilter(
        candidateFilters, candidateFilterSignature, item.hidePermanent == true)

    local visual = tostring(placed and placed.type or "none"):lower()
    if visual ~= "icon" and visual ~= "square" and visual ~= "bar" and visual ~= "number" and visual ~= "none" then
        visual = "icon"
    end
    if visual == "none" and frameEffect == nil then return nil end
    local iconEffect = tostring(placed and placed.iconEffect or "none"):lower()
    if visual ~= "icon" or iconEffect ~= "glow" then iconEffect = "none" end
    local hiddenVisual = visual == "none" and frameEffect ~= nil
    -- Spell selection and placement stay per indicator. Reusable appearance
    -- comes from the owning Group scope's dedicated Spell Icon Style. Corner
    -- custom slots deliberately retain their explicit no-text contract.
    local appearance = item.cornerSlotKey == nil and type(spellIconStyle) == "table" and spellIconStyle or nil
    local size = ClampNumber(placed and placed.size, hiddenVisual and 1 or 18, 1, 256)
    local width = visual == "bar" and ClampNumber(placed and placed.barWidth, size * 3, size, 384) or size
    local growth = tostring(placed and placed.growth or "RIGHTDOWN"):upper()
    if growth ~= "RIGHTDOWN" and growth ~= "LEFTDOWN" and growth ~= "RIGHTUP" and growth ~= "LEFTUP" then
        growth = "RIGHTDOWN"
    end
    local showBarTimer = visual == "bar" and placed and placed.barShowTimer == true or false
    local color = type(item.color) == "table" and item.color or nil
    local nativeFilter = item.nativeFilter or item.customFilter or (item.onlyOwn ~= false and "HELPFUL|PLAYER" or "HELPFUL")
    local rawStrata = item.strata
    if issecretvalue(rawStrata) == true then rawStrata = nil end
    if rawStrata == nil then rawStrata = fallbackStrata end
    return FinalizeSlot({
        spellIndicatorSlot = true,
        kind = "spellIndicator",
        slotKey = SpellIndicatorSlotKey(item, index),
        itemKey = item.key,
        specKey = item.specKey,
        auraName = item.auraName,
        display = item.display or item.auraName or tostring(index or ""),
        unit = unit,
        enabled = true,
        nativeFilter = NormalizeNativeFilterString(nativeFilter, nativeFilter),
        candidateFilters = candidateFilters,
        candidateFilterSignature = candidateFilterSignature,
        identityCandidateMode = IdentityCandidateMode(nativeFilter, candidateFilters),
        visual = visual,
        hiddenVisual = hiddenVisual == true,
        -- Buff Reminder. The placeholder is an MSUF-owned frame one level
        -- BELOW the native AuraSlot and is never toggled by aura state: the
        -- secret AuraButton simply covers it while the aura is up. Blizzard
        -- pre-allocates every slot's frame batch precisely so the zero and
        -- non-zero transition stays unobservable, so covering the placeholder
        -- is the only honest way to render a missing aura.
        showWhenMissing = item.showWhenMissing == true,
        reminderAlpha = Clamp01(item.reminderAlpha, 0.45),
        reminderDesaturate = item.reminderDesaturate ~= false,
        reminderColor = {
            Clamp01(item.reminderColor and item.reminderColor[1], 1),
            Clamp01(item.reminderColor and item.reminderColor[2], 1),
            Clamp01(item.reminderColor and item.reminderColor[3], 1),
        },
        -- Click-to-cast target for this slot. Purely configuration: the
        -- spell is the one the user whitelisted, so nothing about the live
        -- aura is read to decide it.
        castSpellID = tonumber(item.castSpellID),
        -- A bound item wins over the spell: consumables such as flasks,
        -- runes or oils have to be used, not cast.
        castItem = type(item.castItem) == "string" and item.castItem or nil,
        castItemID = tonumber(item.castItemID),
        enchantSlot = type(item.enchantSlot) == "string" and item.enchantSlot or nil,
        enchantInventorySlot = tonumber(item.enchantInventorySlot),
        enchantDurationSeconds = item.enchantSlot
            and ClampNumber(item.enchantDurationSeconds, 60 * 60, 5 * 60, 240 * 60) or nil,
        castUnit = type(item.castUnit) == "string" and item.castUnit or nil,
        icon = item.icon,
        color = {
            Clamp01(color and color[1], 0.69),
            Clamp01(color and color[2], 0.50),
            Clamp01(color and color[3], 0.88),
            Clamp01(color and color[4], 1),
        },
        -- Only the static border/shadow object inside this dedicated compiled
        -- appearance is shared with normal Auras. Preview and runtime consume
        -- the same slot, so no surface can silently fall back to Buff Style.
        iconStyle = appearance and appearance.iconStyle or nil,
        -- Group scopes own their look through the shared Spell Icon Style.
        -- Unit-side items (Buff Reminder slots) carry their container's own
        -- resolved shape and zoom instead, since no style object applies.
        iconShape = (appearance and appearance.iconShape) or item.iconShape or "RECTANGLE",
        requestedIconShape = (appearance and appearance.requestedIconShape)
            or item.requestedIconShape or "RECTANGLE",
        iconEffect = iconEffect,
        frameEffect = frameEffect,
        size = size,
        iconZoom = ClampNumber(item.iconZoom or fallbackIconZoom, 100, 100, 200),
        width = width,
        height = size,
        growth = growth,
        anchor = SpellIndicatorAnchor(placed and placed.anchor, "TOPLEFT"),
        x = Round(ClampNumber(placed and placed.x, 0, -4096, 4096)),
        y = Round(ClampNumber(placed and placed.y, 0, -4096, 4096)),
        layer = Round(ClampNumber(item.layer or fallbackLayer, fallbackLayer or 9, 0, 30)),
        strata = NormalizeFrameStrata(rawStrata, "AUTO"),
        alpha = Clamp01(appearance and appearance.alpha, 1),
        max = 1,
        spacing = 0,
        step = size,
        perRow = 1,
        cols = 1,
        rows = 1,
        showCooldownText = showBarTimer
            or ((appearance and appearance.showCooldownText ~= false or (not appearance and placed and placed.showCooldown ~= false)) and visual == "icon"),
        showCooldownSwipe = (appearance and appearance.showCooldownSwipe ~= false or (not appearance and placed and placed.showCooldownSwipe ~= false)) and visual == "icon",
        cooldownSwipeReverse = appearance and appearance.cooldownSwipeReverse == true
            or (not appearance and placed and placed.cooldownSwipeReverse == true) or false,
        -- A placed Bar is the aura duration itself, not a static color swatch.
        -- The shared AuraButton preparer binds its full-size StatusBar to
        -- Blizzard's C-side duration object through SetDurationBar().
        showDurationBar = visual == "bar"
            or (appearance and appearance.showDurationBar == true and visual == "icon" or false),
        durationBarHeight = ClampNumber(appearance and appearance.durationBarHeight, DEFAULT_SHARED.durationBarHeight, 1, 16),
        durationBarDisplay = visual == "bar" and "BAR_ONLY"
            or (appearance and appearance.durationBarDisplay or DEFAULT_SHARED.durationBarDisplay),
        durationBarPosition = appearance and appearance.durationBarPosition or DEFAULT_SHARED.durationBarPosition,
        durationBarDirection = appearance and appearance.durationBarDirection or DEFAULT_SHARED.durationBarDirection,
        durationBarSmooth = visual == "bar" and placed and placed.barSmoothFill == true or false,
        durationBarReverseFill = visual == "bar" and growth:sub(1, 4) == "LEFT" or false,
        showStacks = (appearance and appearance.showStacks ~= false or (not appearance and placed and placed.showStacks ~= false)) and (visual == "icon" or visual == "number"),
        showTooltip = appearance and appearance.showTooltip ~= false or false,
        showAuraBorder = false,
        showAuraSymbol = false,
        cooldownSize = ClampNumber(appearance and appearance.cooldownSize or (placed and placed.cooldownSize), DEFAULT_SHARED.cooldownTextSize, 6, 40),
        cooldownAnchor = showBarTimer and SpellIndicatorAnchor(placed and placed.barTimerAnchor, "CENTER")
            or SpellIndicatorAnchor((appearance and appearance.cooldownAnchor)
                or (placed and placed.cooldownAnchor), "CENTER"),
        cooldownX = showBarTimer and ClampNumber(placed and placed.barTimerX, 0, -2000, 2000)
            or ClampNumber((appearance and appearance.cooldownX)
                or (placed and placed.cooldownX), 0, -2000, 2000),
        cooldownY = showBarTimer and ClampNumber(placed and placed.barTimerY, 0, -2000, 2000)
            or ClampNumber((appearance and appearance.cooldownY)
                or (placed and placed.cooldownY), 0, -2000, 2000),
        cooldownDecimalSeconds = ClampNumber((appearance and appearance.cooldownDecimalSeconds)
            or (placed and placed.cooldownDecimalSeconds), DEFAULT_SHARED.cooldownDecimalSeconds, 0, 30),
        stackAnchor = SpellIndicatorAnchor(appearance and appearance.stackAnchor, "BOTTOMRIGHT"),
        stackSize = ClampNumber(appearance and appearance.stackSize, DEFAULT_SHARED.stackTextSize, 6, 40),
        stackX = ClampNumber(appearance and appearance.stackX, 0, -2000, 2000),
        stackY = ClampNumber(appearance and appearance.stackY, 0, -2000, 2000),
    })
end

function Runtime.CompileSlots(unit, spellIndicators, spellIconStyle)
    if not (type(spellIndicators) == "table" and spellIndicators.enabled == true and type(spellIndicators.items) == "table") then
        return nil
    end
    local slots, structuralParts, layoutParts = {}, {}, {}
    local function AddSlot(slot)
        if not slot then return end
        slots[#slots + 1] = slot
        structuralParts[#structuralParts + 1] = slot._msufA3StructuralSignature
        layoutParts[#layoutParts + 1] = slot._msufA3LayoutSignature
    end
    for i = 1, #spellIndicators.items do
        local slot = CompileSlot(unit, spellIndicators.items[i], i, spellIndicators.layer, spellIndicators.strata, spellIndicators.iconZoom, spellIconStyle)
        if slot then AddSlot(slot) end
    end
    if #slots == 0 then return nil end
    return {
        spellIndicatorRoot = true,
        kind = "spellIndicators",
        rootKey = spellIndicators.rootKey or "SpellIndicators",
        unit = unit,
        enabled = true,
        slots = slots,
        max = #slots,
        layer = spellIndicators.layer or 9,
        iconZoom = ClampNumber(spellIndicators.iconZoom, 100, 100, 200),
        strata = NormalizeFrameStrata(spellIndicators.strata, "AUTO"),
        _msufA3StructuralSignature = table_concat(structuralParts, "\029"),
        _msufA3LayoutSignature = table_concat(layoutParts, "\029"),
    }
end

function Runtime.IsRoot(root)
    return root and root.enabled == true and root.spellIndicatorRoot == true
end

--- Flag every live spell-indicator container so its next geometry sync
--- bypasses the per-button anchor cache. Flag-only on purpose: the config
--- refresh that accompanies every indicator write already runs SyncGeometry,
--- so no extra layout pass is added here. This makes position edits apply
--- deterministically instead of waiting for the zone-load geometry repair.
function Runtime.RequestGeometryRepair()
    local byUnit = A3._directIdentityAuraContainers
    if not byUnit then return false end
    local any = false
    for _, containers in pairs(byUnit) do
        for container in pairs(containers) do
            if container._msufA3SpellIndicatorRoot == true then
                container._msufA3ForceSpellIndicatorGeometry = true
                any = true
            end
        end
    end
    return any
end

function Runtime.RootConfig(cfg)
    local root = cfg and cfg.spellIndicators
    return Runtime.IsRoot(root) and root or nil
end

function Runtime.IdentityCandidateMode(slot)
    if type(slot) ~= "table" then return nil end
    return slot.identityCandidateMode
        or IdentityCandidateMode(slot.nativeFilter, slot.candidateFilters)
end

-- Blizzard applies exact spell-ID filters to HELPFUL auras only while the
-- unit is assistable, and to HARMFUL auras only while it is not. Native
-- AuraButtons can become forbidden after assignment, so live group frames
-- partition immutable slot definitions instead of touching buttons later.
function Runtime.PartitionRoot(slotRoot, mode, rootKey)
    if not Runtime.IsRoot(slotRoot) then return nil end
    local slots, structuralParts, layoutParts = {}, {}, {}
    for i = 1, #slotRoot.slots do
        local slot = slotRoot.slots[i]
        local slotMode = Runtime.IdentityCandidateMode(slot) or "neutral"
        if slotMode == mode then
            slots[#slots + 1] = slot
            structuralParts[#structuralParts + 1] = slot._msufA3StructuralSignature
            layoutParts[#layoutParts + 1] = slot._msufA3LayoutSignature
        end
    end
    if #slots == 0 then return nil end
    return {
        spellIndicatorRoot = true,
        kind = slotRoot.kind,
        rootKey = rootKey or slotRoot.rootKey,
        unit = slotRoot.unit,
        enabled = true,
        slots = slots,
        max = #slots,
        layer = slotRoot.layer,
        iconZoom = slotRoot.iconZoom,
        strata = slotRoot.strata,
        identityCandidateMode = mode ~= "neutral" and mode or nil,
        _msufA3StructuralSignature = mode .. "\030" .. table_concat(structuralParts, "\029"),
        _msufA3LayoutSignature = mode .. "\030" .. table_concat(layoutParts, "\029"),
    }
end

-- Ordinary Unit Frames can own mixed neutral/HELPFUL/HARMFUL fixed slots in
-- one compiled root. Exact-ID candidate filters are identity-sensitive, so
-- split only roots that actually contain such slots. The first live partition
-- retains the historical root key; the optional polarity siblings are cold
-- config artifacts and therefore add no UNIT_AURA/runtime dispatch work.
function Runtime.PartitionUnitRoot(slotRoot)
    if not Runtime.IsRoot(slotRoot) then return nil, nil, nil end
    local baseKey = slotRoot.rootKey or "SpellIndicators"
    local assist = Runtime.PartitionRoot(slotRoot, "assist", baseKey .. "Assist")
    local hostile = Runtime.PartitionRoot(slotRoot, "hostile", baseKey .. "Hostile")
    if not assist and not hostile then return slotRoot, nil, nil end

    local neutral = Runtime.PartitionRoot(slotRoot, "neutral", baseKey)
    if neutral then return neutral, assist, hostile end
    if assist then
        assist.rootKey = baseKey
        return assist, nil, hostile
    end
    hostile.rootKey = baseKey
    return hostile, nil, nil
end


return {
    Round = Round,
    ClampNumber = ClampNumber,
    Clamp01 = Clamp01,
    ResolveFrameStrata = ResolveFrameStrata,
    SyncFrameStrata = SyncFrameStrata,
    IdentityCandidateMode = IdentityCandidateMode,
    SpellIconBaseOffset = SpellIconBaseOffset,
    NormalizeFrameEffect = NormalizeFrameEffect,
    SlotLayoutSignature = SlotLayoutSignature,
}
end
