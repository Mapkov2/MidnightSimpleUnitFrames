--- Auras3/MSUF_Auras3_SpellIndicators.lua
--- Group-frame spell indicators on WoW 12.1 CustomAuraContainer aura slots.
local addonName, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end

local Runtime = A3.SpellIndicators or {}
A3.SpellIndicators = Runtime

local type, tostring, tonumber, pairs = type, tostring, tonumber, pairs
local table_concat, table_sort = table.concat, table.sort
local math_floor, math_min, math_max = math.floor, math.min, math.max
local FrameLayers = MSUF.UF and MSUF.UF.Layers or {}
local SPELL_FRAME_EFFECT_BASE_OFFSET = tonumber(FrameLayers.SPELL_FRAME_EFFECT_BASE_OFFSET) or 1
local SPELL_ICON_BASE_OFFSET = tonumber(FrameLayers.SPELL_ICON_BASE_OFFSET) or 64
local UNIT_SPELL_BASE_OFFSET = tonumber(FrameLayers.UNIT_AURA_BASE_OFFSET) or 10
local CreateFrame = _G.CreateFrame
local issecretvalue = _G.issecretvalue or function(_) return false end
local MAX_FINITE_AURA_DURATION = 2147483647
local ICON_ALERT_TEXTURE = [[Interface\SpellActivationOverlay\IconAlert]]
local ICON_ALERT_ANTS_TEXTURE = [[Interface\SpellActivationOverlay\IconAlertAnts]]
local FRAME_GLOW_TEXTURE = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames")
    .. "\\Media\\Borders\\frame_glow_radial.tga"
local SetAssistAlpha

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

local function NormalizeFrameStrata(value, fallback)
    local normalize = _G.MSUF_NormalizeFrameStrata
    if type(normalize) == "function" then return normalize(value, fallback or "AUTO") end
    if issecretvalue(value) == true then return fallback or "AUTO" end
    if value == nil or value == "" then return fallback or "AUTO" end
    value = tostring(value):upper()
    if value == "AUTO" then return "AUTO" end
    local rank = _G.MSUF_FRAME_STRATA_RANK
    return rank and rank[value] and value or (fallback or "AUTO")
end

local function ReadParentFrameStrata(parentFrame)
    local strata
    if parentFrame and parentFrame.GetFrameStrata then strata = parentFrame:GetFrameStrata() end
    if issecretvalue(strata) == true then return nil end
    return strata
end

local function ResolveFrameStrata(parentFrame, value)
    -- Retained legacy strata values are migration data only. All layer-aware
    -- visuals share their owning unit frame's strata.
    return ReadParentFrameStrata(parentFrame)
end

local function SyncFrameStrata(frame, strata)
    if not (frame and frame.SetFrameStrata) then return false end
    if issecretvalue(strata) == true then return false end
    if strata == nil or strata == "" then return false end
    local cachedStrata = frame._msufA3FrameStrata
    if issecretvalue(cachedStrata) ~= true and cachedStrata == strata then return false end
    frame._msufA3FrameStrata = strata
    local currentStrata
    if frame.GetFrameStrata then currentStrata = frame:GetFrameStrata() end
    if issecretvalue(currentStrata) == true or currentStrata ~= strata then
        frame:SetFrameStrata(strata)
        return true
    end
    return false
end

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

local function AuraSpellIDFromKey(value)
    value = tostring(value or "")
    local id = tonumber(value:match("spell:(%d+)") or value:match("#(%d+)") or value:match("^(%d+)$"))
    return id and math_floor(id + 0.5) or nil
end

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
    if not candidateFilters and item.allowAnyAura ~= true then return nil end
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
        showWhenMissing = false,
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
        iconShape = appearance and appearance.iconShape or "RECTANGLE",
        requestedIconShape = appearance and appearance.requestedIconShape or "RECTANGLE",
        iconEffect = iconEffect,
        frameEffect = frameEffect,
        size = size,
        iconZoom = ClampNumber(fallbackIconZoom, 100, 100, 200),
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
        cooldownSwipeReverse = appearance and appearance.cooldownSwipeReverse == true or false,
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
            or SpellIndicatorAnchor(appearance and appearance.cooldownAnchor, "CENTER"),
        cooldownX = showBarTimer and ClampNumber(placed and placed.barTimerX, 0, -2000, 2000)
            or ClampNumber(appearance and appearance.cooldownX, 0, -2000, 2000),
        cooldownY = showBarTimer and ClampNumber(placed and placed.barTimerY, 0, -2000, 2000)
            or ClampNumber(appearance and appearance.cooldownY, 0, -2000, 2000),
        cooldownDecimalSeconds = ClampNumber(appearance and appearance.cooldownDecimalSeconds, DEFAULT_SHARED.cooldownDecimalSeconds, 0, 30),
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

function Runtime.Install(deps)
    Runtime._deps = deps
    SetAssistAlpha = deps.SetAssistAlpha
end

local function D()
    return Runtime._deps
end

local function SpellIndicatorHealthBar(parentFrame)
    return parentFrame and (parentFrame.hpBar or parentFrame.Health or parentFrame.health)
end

local function SpellIndicatorHealthFill(parentFrame)
    local bar = SpellIndicatorHealthBar(parentFrame)
    if not (bar and bar.GetStatusBarTexture) then return nil end
    return bar:GetStatusBarTexture()
end

local function EnsureEffectRoot(button, parentFrame)
    if not (button and parentFrame) then return nil end
    local target = SpellIndicatorHealthBar(parentFrame)
    if not target then return nil end
    local root = button._msufA3SpellIndicatorEffectRoot
    if not root then
        -- Live effects stay below the native AuraSlot so Blizzard's secret
        -- visibility is inherited. The AuraSlot itself sits at the universal
        -- base; this child's absolute level therefore remains independent from
        -- the separately levelled icon host. Menu previews use a neutral owner.
        root = CreateFrame("Frame", nil, button)
        root:EnableMouse(false)
        root:SetAllPoints(target)
        button._msufA3SpellIndicatorEffectRoot = root
    end
    return root
end

local function EnsureTint(button, parentFrame)
    local root = EnsureEffectRoot(button, parentFrame)
    if not root then return nil end
    local tint = button._msufA3SpellIndicatorHealthTint
    if not tint then
        tint = root:CreateTexture(nil, "OVERLAY")
        tint:SetTexture("Interface\\Buttons\\WHITE8X8")
        button._msufA3SpellIndicatorHealthTint = tint
    end
    return tint
end

local function EnsureEdges(button, parentFrame)
    local root = EnsureEffectRoot(button, parentFrame)
    if not root then return nil end
    local edges = button._msufA3SpellIndicatorEdges
    if not edges then
        edges = {}
        for i = 1, 4 do
            local tex = root:CreateTexture(nil, "OVERLAY")
            tex:SetTexture("Interface\\Buttons\\WHITE8X8")
            edges[i] = tex
        end
        button._msufA3SpellIndicatorEdges = edges
    end
    return edges
end

-- Genuine animated action-button glow. The 22-frame ants animation is driven
-- by a C-side AnimationGroup, so active indicators add no Lua OnUpdate work.
-- Only the square icon effect uses this renderer; the full-frame glow has its
-- own aspect-ratio-safe halo below. Because the roots are children of the
-- native AuraSlot button, Blizzard's secret visibility is inherited without
-- reading or branching on it in addon Lua.
local function EnsureAnimatedGlow(owner)
    if not owner then return nil end
    local data = owner._msufA3AnimatedGlow
    if data then return data end

    local halo = owner:CreateTexture(nil, "OVERLAY", nil, 6)
    halo:SetTexture(ICON_ALERT_TEXTURE)
    halo:SetTexCoord(0.0078125, 0.5078125, 0.27734375, 0.52734375)
    halo:SetBlendMode("ADD")

    local ants = owner:CreateTexture(nil, "OVERLAY", nil, 7)
    ants:SetTexture(ICON_ALERT_ANTS_TEXTURE)
    ants:SetBlendMode("ADD")
    local animation = ants:CreateAnimationGroup()
    animation:SetLooping("REPEAT")
    local flipbook = animation:CreateAnimation("FlipBook")
    flipbook:SetFlipBookRows(5)
    flipbook:SetFlipBookColumns(5)
    flipbook:SetFlipBookFrames(22)
    flipbook:SetFlipBookFrameWidth(48)
    flipbook:SetFlipBookFrameHeight(48)
    flipbook:SetDuration(0.37)

    data = { halo = halo, ants = ants, animation = animation }
    owner._msufA3AnimatedGlow = data
    return data
end

local function AnchorAnimatedGlow(data, target, padding)
    if not (data and target) or (data.target == target and data.padding == padding) then return end
    data.target = target
    data.padding = padding
    local haloPadding = padding * 1.55
    data.halo:ClearAllPoints()
    data.halo:SetPoint("TOPLEFT", target, "TOPLEFT", -haloPadding, haloPadding)
    data.halo:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", haloPadding, -haloPadding)
    data.ants:ClearAllPoints()
    data.ants:SetPoint("TOPLEFT", target, "TOPLEFT", -padding, padding)
    data.ants:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", padding, -padding)
end

local function StartAnimatedGlow(owner, target, r, g, b, a, padding)
    local data = EnsureAnimatedGlow(owner)
    if not data then return false end
    padding = ClampNumber(padding, 3, 1, 24)
    AnchorAnimatedGlow(data, target or owner, padding)
    if data.r ~= r or data.g ~= g or data.b ~= b or data.a ~= a then
        data.r, data.g, data.b, data.a = r, g, b, a
        data.halo:SetDesaturated(true)
        data.ants:SetDesaturated(true)
        data.halo:SetVertexColor(r, g, b, a)
        data.ants:SetVertexColor(r, g, b, a)
    end
    data.active = true
    data.halo:Show()
    data.ants:Show()
    if not data.animation:IsPlaying() then data.animation:Play() end
    return true
end

local function StopAnimatedGlow(owner)
    local data = owner and owner._msufA3AnimatedGlow
    if not data then return end
    data.active = nil
    if data.animation:IsPlaying() then data.animation:Stop() end
    data.halo:Hide()
    data.ants:Hide()
end

-- Full-frame glow: a soft halo built from eight static slices of one radial
-- gradient (4 corner quarters + 4 center-cross edge strips). Corners stay
-- round at any bar aspect ratio instead of smearing Blizzard's square
-- action-button alert art across a wide health bar, and there is no
-- animation, so an active glow costs zero Lua and zero C-side ticks.
local FRAME_GLOW_EDGE_LOW, FRAME_GLOW_EDGE_HIGH = 31 / 64, 33 / 64
-- The glow rectangle sits this many pixels inside the bar edge, so the bright
-- core overlaps the bar's own border art and the halo reads as attached to
-- the frame instead of floating next to it.
local FRAME_GLOW_INSET = 2

local function EnsureFrameGlow(owner)
    if not owner then return nil end
    local data = owner._msufA3FrameGlow
    if data then return data end
    local pieces = {}
    for i = 1, 8 do
        local tex = owner:CreateTexture(nil, "OVERLAY", nil, 6)
        tex:SetTexture(FRAME_GLOW_TEXTURE)
        pieces[i] = tex
    end
    pieces[1]:SetTexCoord(0, 0.5, 0, 0.5)                                   -- top-left corner
    pieces[2]:SetTexCoord(0.5, 1, 0, 0.5)                                   -- top-right corner
    pieces[3]:SetTexCoord(0, 0.5, 0.5, 1)                                   -- bottom-left corner
    pieces[4]:SetTexCoord(0.5, 1, 0.5, 1)                                   -- bottom-right corner
    pieces[5]:SetTexCoord(FRAME_GLOW_EDGE_LOW, FRAME_GLOW_EDGE_HIGH, 0, 0.5) -- top edge
    pieces[6]:SetTexCoord(FRAME_GLOW_EDGE_LOW, FRAME_GLOW_EDGE_HIGH, 0.5, 1) -- bottom edge
    pieces[7]:SetTexCoord(0, 0.5, FRAME_GLOW_EDGE_LOW, FRAME_GLOW_EDGE_HIGH) -- left edge
    pieces[8]:SetTexCoord(0.5, 1, FRAME_GLOW_EDGE_LOW, FRAME_GLOW_EDGE_HIGH) -- right edge
    data = { pieces = pieces }
    owner._msufA3FrameGlow = data
    return data
end

local function AnchorFrameGlow(data, target, extent)
    if not (data and target) or (data.target == target and data.extent == extent) then return end
    data.target = target
    data.extent = extent
    local pieces = data.pieces
    local inset = FRAME_GLOW_INSET
    for i = 1, 8 do pieces[i]:ClearAllPoints() end
    pieces[1]:SetPoint("BOTTOMRIGHT", target, "TOPLEFT", inset, -inset)
    pieces[2]:SetPoint("BOTTOMLEFT", target, "TOPRIGHT", -inset, -inset)
    pieces[3]:SetPoint("TOPRIGHT", target, "BOTTOMLEFT", inset, inset)
    pieces[4]:SetPoint("TOPLEFT", target, "BOTTOMRIGHT", -inset, inset)
    for i = 1, 4 do pieces[i]:SetSize(extent, extent) end
    pieces[5]:SetPoint("BOTTOMLEFT", target, "TOPLEFT", inset, -inset)
    pieces[5]:SetPoint("BOTTOMRIGHT", target, "TOPRIGHT", -inset, -inset)
    pieces[5]:SetHeight(extent)
    pieces[6]:SetPoint("TOPLEFT", target, "BOTTOMLEFT", inset, inset)
    pieces[6]:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", -inset, inset)
    pieces[6]:SetHeight(extent)
    pieces[7]:SetPoint("TOPRIGHT", target, "TOPLEFT", inset, -inset)
    pieces[7]:SetPoint("BOTTOMRIGHT", target, "BOTTOMLEFT", inset, inset)
    pieces[7]:SetWidth(extent)
    pieces[8]:SetPoint("TOPLEFT", target, "TOPRIGHT", -inset, -inset)
    pieces[8]:SetPoint("BOTTOMLEFT", target, "BOTTOMRIGHT", -inset, inset)
    pieces[8]:SetWidth(extent)
end

local function StartFrameGlow(owner, target, r, g, b, a, extent)
    local data = EnsureFrameGlow(owner)
    if not data then return false end
    extent = ClampNumber(extent, 8, 4, 48)
    AnchorFrameGlow(data, target or owner, extent)
    local pieces = data.pieces
    if data.r ~= r or data.g ~= g or data.b ~= b or data.a ~= a then
        data.r, data.g, data.b, data.a = r, g, b, a
        for i = 1, 8 do pieces[i]:SetVertexColor(r, g, b, a) end
    end
    data.active = true
    for i = 1, 8 do pieces[i]:Show() end
    return true
end

local function StopFrameGlow(owner)
    local data = owner and owner._msufA3FrameGlow
    if not (data and data.active) then return end
    data.active = nil
    local pieces = data.pieces
    for i = 1, 8 do pieces[i]:Hide() end
end

local function NameFontString(parentFrame)
    if not parentFrame then return nil end
    return parentFrame.Name
        or parentFrame.name
        or parentFrame.NameText
        or parentFrame.nameText
        or parentFrame._nameFS
end

local function UnregisterNameOverlay(button)
    local overlay = button and button._msufA3SpellIndicatorNameOverlay
    if overlay then
        overlay._msufA3NameSource = nil
        overlay:Hide()
    end
end

local function SyncNameOverlayFont(overlay, source)
    if not (overlay and source) then return end
    local path, size, flags = source:GetFont()
    if path and size then
        local general = _G.MSUF_DB and _G.MSUF_DB.general
        local applyResolved = _G.MSUF_ApplyResolvedFont
        if type(applyResolved) == "function" then
            applyResolved(overlay, path, size, flags, general and general.fontKey)
        else
            local ok, applied = pcall(overlay.SetFont, overlay, path, size, flags)
            if (not ok or applied == false) and type(_G.MSUF_MarkFontApplyFailed) == "function" then
                _G.MSUF_MarkFontApplyFailed()
            end
        end
    end
    if source.GetJustifyH then overlay:SetJustifyH(source:GetJustifyH()) end
    if source.GetJustifyV then overlay:SetJustifyV(source:GetJustifyV()) end
    if source.GetShadowColor then overlay:SetShadowColor(source:GetShadowColor()) end
    if source.GetShadowOffset then overlay:SetShadowOffset(source:GetShadowOffset()) end
    overlay:ClearAllPoints()
    overlay:SetAllPoints(source)
    -- GetText can itself be secret on restricted units. It is forwarded as an
    -- opaque value only; no comparison or branch is performed on it.
    overlay:SetText(source:GetText())
end

local function RegisterNameOverlay(button, parentFrame, root)
    local source = NameFontString(parentFrame)
    if not (button and source and root) then return nil end
    local overlay = button._msufA3SpellIndicatorNameOverlay
    if not overlay then
        overlay = root:CreateFontString(nil, "OVERLAY")
        button._msufA3SpellIndicatorNameOverlay = overlay
    end
    if overlay._msufA3NameSource ~= source then
        UnregisterNameOverlay(button)
        overlay._msufA3NameSource = source
    end
    -- PTR 5 applies AuraButton access restrictions immediately after this
    -- initializer returns. Do not retain a SetText hook that would later write
    -- to this descendant while aura data is secret.
    SyncNameOverlayFont(overlay, source)
    return overlay
end

local function StopPulse(root)
    local pulse = root and root._msufA3SpellIndicatorPulse
    if pulse and pulse:IsPlaying() then pulse:Stop() end
    if root then root:SetAlpha(1) end
end

local function StartPulse(root)
    if not root then return end
    local pulse = root._msufA3SpellIndicatorPulse
    if not pulse then
        pulse = root:CreateAnimationGroup()
        local alpha = pulse:CreateAnimation("Alpha")
        alpha:SetFromAlpha(0.45)
        alpha:SetToAlpha(1)
        alpha:SetDuration(0.7)
        if alpha.SetSmoothing then alpha:SetSmoothing("IN_OUT") end
        pulse:SetLooping("BOUNCE")
        root._msufA3SpellIndicatorPulse = pulse
    end
    if not pulse:IsPlaying() then pulse:Play() end
end

local function HideButtonFrameEffect(button)
    if not button then return end
    local root = button._msufA3SpellIndicatorEffectRoot
    if root then
        StopPulse(root)
        StopAnimatedGlow(root)
        StopFrameGlow(root)
        root:Hide()
    end
    UnregisterNameOverlay(button)
end

local function HideButtonIconEffect(button)
    if not button then return end
    local root = button._msufA3SpellIndicatorIconEffectRoot
    if root then
        StopAnimatedGlow(root)
        root:SetAlpha(1)
        root:Hide()
    end
end

function Runtime.HideFrameEffects(parentFrame)
    if not parentFrame then return end
    -- The owning native container is hidden before this cleanup. Native
    -- AuraButtons may be forbidden, so do not touch them from Lua here.
    parentFrame._msufA3SpellIndicatorEffectButtons = nil
    -- Clean up objects created by the pre-native implementation, if a profile
    -- was hot-reloaded from an older build in the same session.
    if parentFrame._msufA3SpellIndicatorEffectRoot then parentFrame._msufA3SpellIndicatorEffectRoot:Hide() end
end

function Runtime.HideIconEffects(parentFrame)
    if not parentFrame then return end
    parentFrame._msufA3SpellIndicatorIconEffectButtons = nil
end

function Runtime.HideMissing(parentFrame)
    if not parentFrame then return end
    local missing = parentFrame._msufA3SpellIndicatorMissingFrames
    if missing then
        for _, frame in pairs(missing) do
            if frame then frame:Hide() end
        end
    end
end

function Runtime.HideAll(parentFrame)
    Runtime.HideFrameEffects(parentFrame)
    Runtime.HideIconEffects(parentFrame)
    Runtime.HideMissing(parentFrame)
end

function Runtime.HideRootMissing(parentFrame, slotRoot, ownerContainer)
    local missing = parentFrame and parentFrame._msufA3SpellIndicatorMissingFrames
    local slots = slotRoot and slotRoot.slots
    if not (missing and type(slots) == "table") then return false end
    local any = false
    for i = 1, #slots do
        local frame = missing[slots[i] and slots[i].slotKey]
        if frame and (ownerContainer == nil
            or frame._msufA3MissingOwnerContainer == ownerContainer) then
            frame:Hide()
            any = true
        end
    end
    return any
end

local function LayoutEdges(button, parentFrame, target, effect)
    local edges = EnsureEdges(button, parentFrame)
    if not edges then return end
    local color = effect and effect.color or {}
    local r, g, b = Clamp01(color[1], 1), Clamp01(color[2], 1), Clamp01(color[3], 1)
    local a = Clamp01(color[4], 1)
    local thickness = ClampNumber(effect and effect.thickness, effect and effect.type == "glow" and 3 or 2, 1, 16)
    if effect and (effect.type == "glow" or effect.type == "pulse") then
        thickness = math_max(thickness, 3)
        a = math_min(1, a * 0.85)
    end
    local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", target, "TOPLEFT", -thickness, thickness)
    top:SetPoint("TOPRIGHT", target, "TOPRIGHT", thickness, thickness)
    top:SetHeight(thickness)
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -thickness, -thickness)
    bottom:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", thickness, -thickness)
    bottom:SetHeight(thickness)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT", 0, 0)
    left:SetWidth(thickness)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)
    right:SetWidth(thickness)
    for i = 1, 4 do
        local edge = edges[i]
        if edge.SetBlendMode then edge:SetBlendMode(effect and (effect.type == "glow" or effect.type == "pulse") and "ADD" or "BLEND") end
        edge:SetVertexColor(r, g, b, a)
        edge:Show()
    end
    local rounded = _G.MSUF_RoundedUF_OnSpellIndicatorEdge
    if rounded and rounded(button, parentFrame, target, true, thickness, r, g, b, a,
        effect and effect.type == "pulse" and "ADD" or "BLEND") then
        for i = 1, 4 do edges[i]:Hide() end
    end
end

local function HideEffectRegions(button)
    local tint = button and button._msufA3SpellIndicatorHealthTint
    if tint then tint:Hide() end
    local edges = button and button._msufA3SpellIndicatorEdges
    if edges then
        for i = 1, #edges do
            if edges[i] then edges[i]:Hide() end
        end
    end
    local rounded = _G.MSUF_RoundedUF_OnSpellIndicatorEdge
    if rounded then rounded(button, nil, nil, false) end
    StopAnimatedGlow(button and button._msufA3SpellIndicatorEffectRoot)
    StopFrameGlow(button and button._msufA3SpellIndicatorEffectRoot)
    UnregisterNameOverlay(button)
end

local function ApplyButtonFrameEffect(button, slot, parentFrame)
    if not (button and slot and parentFrame) then return false end
    local effect = slot.frameEffect
    if type(effect) ~= "table" then
        local buttons = parentFrame._msufA3SpellIndicatorEffectButtons
        if buttons then buttons[button] = nil end
        HideButtonFrameEffect(button)
        return false
    end
    local kind = tostring(effect.type or "none"):lower()
    if kind ~= "healthtint" and kind ~= "border" and kind ~= "glow" and kind ~= "pulse" and kind ~= "namecolor" then
        local buttons = parentFrame._msufA3SpellIndicatorEffectButtons
        if buttons then buttons[button] = nil end
        HideButtonFrameEffect(button)
        return false
    end

    -- Visible frame effects must follow the C-side StatusBar fill. The owning
    -- frame stays on the stable health-bar rectangle; only its textures/edges
    -- inherit the current-health geometry, so no UNIT_HEALTH Lua work is added.
    local target = SpellIndicatorHealthFill(parentFrame)
    local root = target and EnsureEffectRoot(button, parentFrame)
    local healthBar = SpellIndicatorHealthBar(parentFrame)
    if not (root and healthBar) then
        HideButtonFrameEffect(button)
        return false
    end
    root:ClearAllPoints()
    root:SetAllPoints(healthBar)
    SyncFrameStrata(root, ResolveFrameStrata(parentFrame, effect.strata or slot.strata))
    if root.SetFrameLevel then
        -- Saved priorities use 1 as the strongest effect.
        local priority = effect.priority or 5
        -- Layer is a cold-compiled 0..30 local offset. Zero preserves the
        -- established priority band exactly; no SavedVariables reads occur here.
        local layer = effect.layer or 0
        local targetOwner = healthBar
        if kind == "namecolor" then
            local nameSource = NameFontString(parentFrame)
            targetOwner = nameSource and nameSource.GetParent and nameSource:GetParent() or parentFrame
        end
        root:SetFrameLevel(FrameLayers.AuraEffectLevel and FrameLayers.AuraEffectLevel(layer, priority, targetOwner)
            or FrameLayers.ElementLevel and FrameLayers.ElementLevel(layer, 0, 11 - priority)
            or ((parentFrame:GetFrameLevel() or 0) + SPELL_FRAME_EFFECT_BASE_OFFSET + (11 - priority) + layer))
    end
    StopPulse(root)
    HideEffectRegions(button)

    local color = effect.color or {}
    local r = Clamp01(color[1], 1)
    local g = Clamp01(color[2], 1)
    local b = Clamp01(color[3], 1)
    local a = Clamp01(color[4], 1)
    if kind == "healthtint" then
        local tint = EnsureTint(button, parentFrame)
        tint:ClearAllPoints()
        tint:SetAllPoints(target)
        if tint.SetBlendMode then tint:SetBlendMode("BLEND") end
        tint:SetVertexColor(r, g, b, Clamp01(effect.tintAlpha, a > 0 and a or 0.20))
        tint:Show()
    elseif kind == "namecolor" then
        local name = RegisterNameOverlay(button, parentFrame, root)
        if name then
            name:SetTextColor(r, g, b, a)
            name:Show()
        end
    elseif kind == "glow" then
        -- The +0.16 alpha boost matches the Menu2 effect preview; the halo's
        -- soft falloff otherwise reads dimmer than the same alpha on a solid
        -- border. Extent compensates for the inset overlap into the bar.
        StartFrameGlow(root, target, r, g, b, math_min(1, a + 0.16),
            Round((ClampNumber(effect.thickness, 3, 1, 16) + 2) * 2.5) + FRAME_GLOW_INSET)
    else
        LayoutEdges(button, parentFrame, target, effect)
        if kind == "pulse" then StartPulse(root) end
    end

    parentFrame._msufA3SpellIndicatorEffectButtons = parentFrame._msufA3SpellIndicatorEffectButtons or {}
    parentFrame._msufA3SpellIndicatorEffectButtons[button] = true
    root:Show()
    return true
end

-- Presence is an independent, plain-boolean output gate.  Keep it outside the
-- secret-backed AuraButton tree and compose it with the already validated
-- UnitCanAssist polarity rather than letting either lifecycle overwrite the
-- other's alpha.
local function GroupOutputVisible(parentFrame, identityMode)
    if not parentFrame then return false end
    -- Unit-frame Spell Indicators do not participate in the Group presence or
    -- UnitCanAssist state machines. Their outer effect surfaces must therefore
    -- remain transparent to this Group-only composition helper.
    if parentFrame._msufA3GroupAuraOutputOwned ~= true then return true end
    if parentFrame._msufA3GroupAuraPresenceVisible == false then
        return false
    end
    if identityMode == "assist" then
        return parentFrame._msufA3GroupAuraAssistReady == true
            and parentFrame._msufA3GroupAuraCanAssist == true
    end
    if identityMode == "hostile" then
        return parentFrame._msufA3GroupAuraAssistReady == true
            and parentFrame._msufA3GroupAuraCanAssist == false
    end
    return true
end

--- Cold-path adapter for the options preview.  It deliberately reuses the
--- live renderer so Border, Glow, Pulse, Health Tint, Name Overlay, layer and
--- priority cannot drift into a second Menu2-only implementation.
function Runtime.ApplyPreviewFrameEffect(owner, effect, parentFrame)
    if not (owner and type(effect) == "table" and parentFrame) then
        if owner then HideButtonFrameEffect(owner) end
        return false
    end
    if owner.Show then owner:Show() end
    local applied = ApplyButtonFrameEffect(owner, {
        frameEffect = effect,
        strata = effect.strata,
    }, parentFrame)
    if not applied and owner.Hide then owner:Hide() end
    return applied
end

function Runtime.HidePreviewFrameEffect(owner)
    if not owner then return false end
    HideButtonFrameEffect(owner)
    if owner.Hide then owner:Hide() end
    return true
end

local function ApplyAlwaysButtonFrameEffect(button, slot, parentFrame)
    if not (button and slot and parentFrame and type(slot.frameEffect) == "table") then
        HideButtonFrameEffect(button)
        return false
    end

    -- The full-frame surface remains a descendant of the one native AuraSlot.
    -- Its absolute level is independent from the icon host, while native secret
    -- visibility, Group presence, range and identity alpha all flow through the
    -- existing ancestor chain without Lua lifecycle hooks.
    return ApplyButtonFrameEffect(button, slot, parentFrame)
end

--- Installs a full-frame effect as one of Blizzard's native Pandemic regions.
--- The region is a descendant of the AuraButton, so the protected Shown aspect
--- is owned entirely by CustomAuraButtonMixin. No MSUF event, ticker, aura-data
--- read, or Lua OnUpdate participates in the visibility transition.
function Runtime.BindPandemicFrameEffect(button, effect, parentFrame)
    if not (button and type(button.AddPandemicRegion) == "function" and parentFrame) then return false end
    effect = NormalizeFrameEffect(effect)
    if not effect then return false end
    if button._msufA3PandemicFrameEffectRegion then return true end
    if not ApplyButtonFrameEffect(button, { frameEffect = effect, strata = effect.strata }, parentFrame) then return false end
    local region = button._msufA3SpellIndicatorEffectRoot
    if not region then return false end
    region:Hide()
    button:AddPandemicRegion(region)
    button._msufA3PandemicFrameEffectRegion = region
    return true
end

local function ApplyButtonIconEffect(button, slot, parentFrame)
    if not (button and slot and parentFrame) then return false end
    if slot.visual ~= "icon" or slot.iconEffect ~= "glow" then
        local buttons = parentFrame._msufA3SpellIndicatorIconEffectButtons
        if buttons then buttons[button] = nil end
        HideButtonIconEffect(button)
        return false
    end

    local visualOwner = button._msufA3SpellIndicatorVisualHost or button
    local root = button._msufA3SpellIndicatorIconEffectRoot
    if not root then
        root = CreateFrame("Frame", nil, visualOwner)
        root:EnableMouse(false)
        button._msufA3SpellIndicatorIconEffectRoot = root
    end
    root:ClearAllPoints()
    root:SetAllPoints(visualOwner)
    SyncFrameStrata(root, ResolveFrameStrata(parentFrame, slot.strata))
    if root.SetFrameLevel then root:SetFrameLevel((visualOwner:GetFrameLevel() or 0) + 4) end
    local color = slot.color or {}
    local size = ClampNumber(slot.size, 18, 1, 128)
    StartAnimatedGlow(root, root,
        Clamp01(color[1], 1), Clamp01(color[2], 1), Clamp01(color[3], 1), Clamp01(color[4], 1),
        math_max(2, size * 0.15))
    parentFrame._msufA3SpellIndicatorIconEffectButtons = parentFrame._msufA3SpellIndicatorIconEffectButtons or {}
    parentFrame._msufA3SpellIndicatorIconEffectButtons[button] = true
    root:Show()
    root:SetAlpha(1)
    return true
end

-- Fixed-slot buttons and their effect descendants already inherit the owning
-- AuraContainer's assist alpha. This helper only mirrors the same plain boolean
-- onto addon-owned missing-indicator previews.
function Runtime.ApplyGroupAssistGate(parentFrame, canAssist, ready)
    if not parentFrame then return false end
    parentFrame._msufA3GroupAuraOutputOwned = true
    local any = false
    local known = issecretvalue(canAssist) ~= true and type(canAssist) == "boolean"
    parentFrame._msufA3GroupAuraAssistReady = ready ~= false and known
    if known then
        parentFrame._msufA3GroupAuraCanAssist = canAssist
    else
        parentFrame._msufA3GroupAuraCanAssist = nil
    end
    local assistVisible = GroupOutputVisible(parentFrame, "assist")
    local hostileVisible = GroupOutputVisible(parentFrame, "hostile")
    local missing = parentFrame._msufA3SpellIndicatorMissingFrames
    if missing then
        for _, frame in pairs(missing) do
            local mode = frame and frame._msufA3IdentityCandidateMode
            if mode == "assist" then
                any = SetAssistAlpha(frame, assistVisible, 1) or any
            elseif mode == "hostile" then
                any = SetAssistAlpha(frame, hostileVisible, 1) or any
            end
        end
    end
    return any
end

-- Ordinary Unit exact-ID containers inherit their visible AuraButtons and
-- effect descendants through container alpha. Missing-indicator surfaces are
-- parent-frame siblings, so mirror the same identity gate only onto surfaces
-- owned by this container. Neutral and other-container surfaces stay untouched.
function Runtime.ApplyUnitIdentityGate(container, canAssist, ready)
    local parentFrame = container and container._msufA3ParentFrame
    local missing = parentFrame and parentFrame._msufA3SpellIndicatorMissingFrames
    if not missing then return false end
    local known = issecretvalue(canAssist) ~= true and type(canAssist) == "boolean"
    local any = false
    for _, frame in pairs(missing) do
        if frame and frame._msufA3MissingOwnerContainer == container then
            local mode = frame._msufA3IdentityCandidateMode
            if mode == "assist" or mode == "hostile" then
                local visible = ready == true and known
                    and (mode == "hostile" and canAssist == false
                        or mode == "assist" and canAssist == true)
                any = SetAssistAlpha(frame, visible, 1) or any
            end
        end
    end
    return any
end

function Runtime.ApplyGroupPresenceGate(parentFrame, present)
    if not parentFrame or type(present) ~= "boolean" then return false end
    parentFrame._msufA3GroupAuraOutputOwned = true
    parentFrame._msufA3GroupAuraPresenceVisible = present
    local any = false
    local missing = parentFrame._msufA3SpellIndicatorMissingFrames
    if missing then
        for _, frame in pairs(missing) do
            local mode = frame and frame._msufA3IdentityCandidateMode or "neutral"
            any = SetAssistAlpha(frame, GroupOutputVisible(parentFrame, mode), 1) or any
        end
    end
    return any
end

function Runtime.RefreshFrameEffects(parentFrame)
    -- Effect descendants inherit native AuraSlot visibility directly. Refreshing
    -- needs no aura scan and never reads AuraSlot:IsShown().
    return parentFrame ~= nil
end

function Runtime.ReleaseContainerEffects(container, parentFrame)
    if not container then return end
    parentFrame = parentFrame or container._msufA3ParentFrame
    -- Initialized AuraButtons and descendants can be access-restricted while
    -- aura data is secret. Their effect and icon descendants disappear with
    -- the owning container without addon-side lifecycle work.
    if parentFrame then
        parentFrame._msufA3SpellIndicatorEffectButtons = nil
        parentFrame._msufA3SpellIndicatorIconEffectButtons = nil
    end
end

local function EnsureMissingFrame(parentFrame, slot)
    if not (parentFrame and slot and slot.showWhenMissing == true) then return nil end
    parentFrame._msufA3SpellIndicatorMissingFrames = parentFrame._msufA3SpellIndicatorMissingFrames or {}
    local frame = parentFrame._msufA3SpellIndicatorMissingFrames[slot.slotKey]
    if not frame then
        frame = CreateFrame("Frame", nil, parentFrame)
        frame._tex = frame:CreateTexture(nil, "OVERLAY")
        frame._tex:SetAllPoints(frame)
        frame._label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame._label:SetPoint("CENTER", frame, "CENTER", 0, 0)
        parentFrame._msufA3SpellIndicatorMissingFrames[slot.slotKey] = frame
    end
    frame._msufA3IdentityCandidateMode = Runtime.IdentityCandidateMode(slot)
    SetAssistAlpha(frame, GroupOutputVisible(parentFrame,
        frame._msufA3IdentityCandidateMode or "neutral"), 1)
    return frame
end

local function SyncMissingFrame(parentFrame, slot, button, ownerContainer)
    local frame = EnsureMissingFrame(parentFrame, slot)
    if not frame then
        local missing = parentFrame and parentFrame._msufA3SpellIndicatorMissingFrames and parentFrame._msufA3SpellIndicatorMissingFrames[slot and slot.slotKey]
        if missing then missing:Hide() end
        return
    end
    frame._msufA3MissingOwnerContainer = ownerContainer
    frame:ClearAllPoints()
    frame:SetSize(slot.width or slot.size or 1, slot.height or slot.size or 1)
    frame:SetPoint(slot.anchor or "TOPLEFT", parentFrame, slot.anchor or "TOPLEFT", slot.x or 0, slot.y or 0)
    SyncFrameStrata(frame, ResolveFrameStrata(parentFrame, slot.strata))
    frame:SetFrameLevel(FrameLayers.ElementLevel and FrameLayers.ElementLevel(slot.layer, 9, 0)
        or ((parentFrame:GetFrameLevel() or 0) + SpellIconBaseOffset(parentFrame) + (slot.layer or 9) - 1))
    local tex = frame._tex
    local label = frame._label
    if slot.visual == "square" or slot.visual == "bar" then
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetVertexColor(slot.color[1] or 1, slot.color[2] or 1, slot.color[3] or 1, math_min(slot.color[4] or 1, 0.45))
        tex:Show()
        label:Hide()
    elseif slot.visual == "number" then
        tex:Hide()
        label:SetText("0")
        label:SetTextColor(slot.color[1] or 1, slot.color[2] or 1, slot.color[3] or 1, 0.65)
        label:Show()
    elseif slot.visual == "icon" then
        tex:SetTexture(slot.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tex:SetVertexColor(0.35, 0.35, 0.35, 0.55)
        tex:Show()
        label:Hide()
    else
        tex:Hide()
        label:Hide()
    end
    frame:SetShown(slot.showWhenMissing == true and button == nil)
end

local function SyncButtonGeometry(button, slot, parentFrame, forceGeometry)
    if not (button and slot and parentFrame) then return false end
    local width, height = slot.width or slot.size or 1, slot.height or slot.size or 1
    local anchor, x, y = slot.anchor or "TOPLEFT", slot.x or 0, slot.y or 0
    if forceGeometry == true
        or button._msufA3GeomParent ~= parentFrame or button._msufA3GeomAnchor ~= anchor
        or button._msufA3GeomX ~= x or button._msufA3GeomY ~= y
        or button._msufA3GeomWidth ~= width or button._msufA3GeomHeight ~= height then
        button._msufA3GeomParent, button._msufA3GeomAnchor = parentFrame, anchor
        button._msufA3GeomX, button._msufA3GeomY = x, y
        button._msufA3GeomWidth, button._msufA3GeomHeight = width, height
        button:ClearAllPoints()
        button:SetSize(width, height)
        button:SetPoint(anchor, parentFrame, anchor, x, y)
    end
    SyncFrameStrata(button, ResolveFrameStrata(parentFrame, slot.strata))
    -- The native AuraSlot is only the lowest-level secret-visibility owner.
    -- Its independently levelled icon host and frame-effect root carry the two
    -- user Layers, so one assignment can render both in either order.
    local level
    if slot.frameEffect then
        level = (tonumber(FrameLayers.ELEMENT_LEVEL_BASE)
            or (FrameLayers.ElementLevel and FrameLayers.ElementLevel(0, 0, 0))
            or ((parentFrame:GetFrameLevel() or 0) + 1)) - 1
    else
        level = FrameLayers.ElementLevel and FrameLayers.ElementLevel(slot.layer, 9, 1)
            or ((parentFrame:GetFrameLevel() or 0) + SpellIconBaseOffset(parentFrame) + (slot.layer or 9))
    end
    if button.SetFrameLevel and button._msufA3GeomLevel ~= level then
        button._msufA3GeomLevel = level
        button:SetFrameLevel(level)
    end
    return true
end

local function ApplyVisual(button, slot)
    if not (button and slot) then return end
    local icon = button.Icon
    -- Display-as-Bar has no icon surface. Avoid allocating one after the native
    -- duration StatusBar has already been installed in initializeFrame.
    if not icon and slot.visual ~= "bar" then
        icon = button:CreateTexture(nil, "ARTWORK")
        button.Icon = icon
    end
    if slot.hiddenVisual == true then
        -- AuraSlot visibility is secret-backed. Effect-only slots therefore
        -- keep alpha at one and hide only their icon regions; the descendant
        -- frame-effect root inherits the native visibility directly.
        button:SetAlpha(1)
        button:ClearIcon()
        button:ClearApplicationCount()
        button:ClearDurationCooldown()
        button:ClearDurationText()
        button:ClearDurationBar()
        button:ClearDispelTypeTextures()
        button:ClearDispelTypeText()
        if icon then icon:Hide() end
        if button._msufA3SpellIndicatorSwatch then button._msufA3SpellIndicatorSwatch:Hide() end
        return
    end
    local visualOwner = button._msufA3SpellIndicatorVisualHost or button
    if visualOwner ~= button then
        button:SetAlpha(1)
        visualOwner:SetAlpha(slot.alpha or 1)
    else
        button:SetAlpha(slot.alpha or 1)
    end
    if slot.visual == "square" then
        icon:SetAlpha(0)
        local swatch = button._msufA3SpellIndicatorSwatch
        if not swatch then
            swatch = visualOwner:CreateTexture(nil, "OVERLAY")
            button._msufA3SpellIndicatorSwatch = swatch
        end
        swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
        swatch:SetTexCoord(0, 1, 0, 1)
        swatch:SetVertexColor(slot.color[1] or 1, slot.color[2] or 1, slot.color[3] or 1, slot.color[4] or 1)
        swatch:ClearAllPoints()
        swatch:SetAllPoints(visualOwner)
        swatch:Show()
    elseif slot.visual == "bar" then
        -- PrepareAuraButton owns the C-side duration StatusBar. Never cover it
        -- with the legacy static swatch used by Square indicators.
        if button._msufA3SpellIndicatorSwatch then button._msufA3SpellIndicatorSwatch:Hide() end
        if icon then icon:Hide() end
    elseif slot.visual == "number" then
        if button._msufA3SpellIndicatorSwatch then button._msufA3SpellIndicatorSwatch:Hide() end
        icon:Hide()
    elseif slot.visual == "icon" then
        if button._msufA3SpellIndicatorSwatch then button._msufA3SpellIndicatorSwatch:Hide() end
        icon:SetVertexColor(1, 1, 1, 1)
        icon:SetAlpha(1)
    else
        if button._msufA3SpellIndicatorSwatch then button._msufA3SpellIndicatorSwatch:Hide() end
        icon:Hide()
    end
end

local function PrepareButton(button, slot, parentFrame, forceGeometry)
    local deps = D()
    if not (button and slot and parentFrame and deps.PrepareAuraButton and deps.ValidateAuraButton) then return false end
    deps.ValidateAuraButton(button)
    button._msufA3ManagedAuraButton = true
    button._msufA3NativeButton = true
    button._msufA3LaneKind = "spellIndicator"
    button._msufA3SpellIndicatorSlot = slot
    button._msufA3SpellIndicatorParentFrame = parentFrame
    button._msufA3ParentFrame = parentFrame
    local prepareSignature = slot._msufA3LayoutSignature or SlotLayoutSignature(slot)
    local needsFullPrepare = button._msufA3SpellIndicatorPrepareSignature ~= prepareSignature
    if needsFullPrepare then
        -- The shared preparer creates MSUF-owned duration/text child surfaces
        -- from the button's current frame level. Put the AuraSlot on its final
        -- universal Layer first so those children stay inside the same 0..30
        -- slot instead of retaining the assignment container's birth level.
        SyncButtonGeometry(button, slot, parentFrame, true)
        -- The shared aura preparer finishes with the normal aura-grid layout,
        -- which temporarily anchors this manually placed slot to its container.
        -- Re-running it for an unchanged slot used to leave the button there:
        -- SyncButtonGeometry's desired-value cache then (correctly but
        -- misleadingly) skipped the saved anchor. Prepare only when visual
        -- configuration changed, and force our manual anchor after that pass.
        deps.PrepareAuraButton(button, slot, 1)
        button._msufA3SpellIndicatorPrepareSignature = prepareSignature
    end
    SyncButtonGeometry(button, slot, parentFrame, forceGeometry == true or needsFullPrepare)
    ApplyVisual(button, slot)
    ApplyButtonIconEffect(button, slot, parentFrame)
    ApplyAlwaysButtonFrameEffect(button, slot, parentFrame)
    SyncMissingFrame(parentFrame, slot, button, button._msufA3SpellIndicatorContainer)
    -- The shared AuraButton preparer permanently disables click input for
    -- every Unit/Group aura. Only tooltip motion remains lane-selectable here.
    button:SetMouseMotionEnabled(slot.showTooltip ~= false)
    return true
end

local function SlotOptions(container, slot, buttonIndex)
    return {
        maxFrameCount = 1,
        candidateFilters = slot.candidateFilters,
        initializeFrame = function(button)
            container[buttonIndex] = button
            button._msufA3SpellIndicatorContainer = container
            -- This closure lives for the container's whole lifetime, but the
            -- native container re-runs it every time it recreates the slot's
            -- button (every aura reapplication). Config edits replace the slot
            -- tables in _msufA3SpellIndicatorButtonSlots; re-installing the
            -- table captured at creation resurrected pre-edit geometry, so
            -- always prepare with the container's current slot instead.
            local slots = container._msufA3SpellIndicatorButtonSlots
            local currentSlot = (slots and slots[buttonIndex]) or slot
            if slots then slots[buttonIndex] = currentSlot end
            PrepareButton(button, currentSlot, container._msufA3ParentFrame)
        end,
    }
end

function Runtime.SyncGeometry(container, slotRoot, parentFrame, forceGeometry)
    if not (container and Runtime.IsRoot(slotRoot)) then return false end
    parentFrame = parentFrame or container._msufA3ParentFrame or container:GetParent()
    if not parentFrame then return false end
    forceGeometry = forceGeometry == true or container._msufA3ForceSpellIndicatorGeometry == true
    container._msufA3NativeLaneConfig = slotRoot
    container._msufA3ParentFrame = parentFrame
    local root = container:GetParent()
    if root then
        container:ClearAllPoints()
        container:SetAllPoints(root)
    end
    SyncFrameStrata(container, ResolveFrameStrata(parentFrame, slotRoot.strata))
    if container.SetFrameLevel then container:SetFrameLevel(parentFrame:GetFrameLevel() or 0) end
    local slots = container._msufA3SpellIndicatorButtonSlots
    -- Initialized AuraButtons can be forbidden while aura data is secret. This
    -- path updates only addon-owned geometry; a force request with live native
    -- buttons remains pending until Runtime.Recreate replaces the container.
    local requiresRecreate = false
    if slots then
        for i = 1, #slots do
            if slots[i] then
                if container[i] then
                    requiresRecreate = forceGeometry == true or requiresRecreate
                else
                    SyncMissingFrame(parentFrame, slots[i], nil, container)
                end
            end
        end
    end
    if type(slotRoot.slots) == "table" then
        for i = 1, #slotRoot.slots do
            local slot = slotRoot.slots[i]
            if not (slots and slots[i]) then SyncMissingFrame(parentFrame, slot, nil, container) end
        end
    end
    Runtime.RefreshFrameEffects(parentFrame)
    if forceGeometry == true and not requiresRecreate then container._msufA3ForceSpellIndicatorGeometry = nil end
    return true
end

-- Slot-family bridge for the group-frame runtime. Spell Indicators and the
-- dispel sensors are both fixed-position AddAuraSlot consumers, so they can
-- share one native AuraContainer without changing either initializer. Keep
-- Spell Indicator slots first: their logical slot index then remains identical
-- to the native button index used by SyncGeometry and the forbidden-button
-- recreation path.
function Runtime.AttachSlots(container, slotRoot)
    if not (container and Runtime.IsRoot(slotRoot)) then return nil end
    container._msufA3ManagedAuraSlots = true
    container._msufA3SpellIndicatorRoot = true
    container._msufA3SpellIndicatorButtonSlots = {}
    container._msufA3SpellIndicatorSlotFilterStrings = {}
    container._msufA3SpellIndicatorSlotCandidateFilterSignatures = {}
    for i = 1, #slotRoot.slots do
        local slot = slotRoot.slots[i]
        container._msufA3SpellIndicatorButtonSlots[i] = slot
        container:AddAuraSlot(slot.slotKey, slot.nativeFilter, SlotOptions(container, slot, i))
        container._msufA3SpellIndicatorSlotFilterStrings[slot.slotKey] = slot.nativeFilter
        container._msufA3SpellIndicatorSlotCandidateFilterSignatures[slot.slotKey] = slot.candidateFilterSignature
    end
    return #slotRoot.slots
end

local function CreateSlots(root, slotRoot, parentFrame)
    local deps = D()
    if not deps.EnsureLoaded() then
        A3.nativeAuraRuntimeAvailable = false
        A3.nativeAuraRuntimeError = (deps.addonName or "Blizzard_AuraContainer") .. " is not loaded: " .. tostring(A3.nativeAuraRuntimeLoadError or "unknown")
        return nil
    end
    local container = deps.CreateContainer(root)
    if not container then return nil end
    A3.nativeAuraRuntimeAvailable = true
    container._msufA3NativeLane = slotRoot.kind
    container._msufA3NativeRegistered = nil
    container._msufA3NativeRegistrationPending = nil
    container.unit = slotRoot.unit
    container.createdButtons = slotRoot.max or 0
    deps.ConfigureContainer(container, slotRoot.unit)
    Runtime.SyncGeometry(container, slotRoot, parentFrame)
    Runtime.AttachSlots(container, slotRoot)
    if not deps.RegisterContainer(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    container:Show()
    A3.nativeAuraRuntimeError = nil
    return container
end

local function UpdateSlots(container, slotRoot)
    if not (container and Runtime.IsRoot(slotRoot)) then return false end
    container._msufA3SpellIndicatorButtonSlots = container._msufA3SpellIndicatorButtonSlots or {}
    container._msufA3SpellIndicatorSlotFilterStrings = container._msufA3SpellIndicatorSlotFilterStrings or {}
    container._msufA3SpellIndicatorSlotCandidateFilterSignatures = container._msufA3SpellIndicatorSlotCandidateFilterSignatures or {}
    for i = 1, #slotRoot.slots do
        local slot = slotRoot.slots[i]
        container._msufA3SpellIndicatorButtonSlots[i] = slot
        if container._msufA3SpellIndicatorSlotFilterStrings[slot.slotKey] ~= slot.nativeFilter then
            container:SetAuraSlotFilterString(slot.slotKey, slot.nativeFilter)
            container._msufA3SpellIndicatorSlotFilterStrings[slot.slotKey] = slot.nativeFilter
        end
        if container._msufA3SpellIndicatorSlotCandidateFilterSignatures[slot.slotKey] ~= slot.candidateFilterSignature then
            container:SetAuraSlotCandidateFilters(slot.slotKey, slot.candidateFilters)
            container._msufA3SpellIndicatorSlotCandidateFilterSignatures[slot.slotKey] = slot.candidateFilterSignature
        end
        -- Runtime.SyncGeometry performs the single visual/geometry pass after
        -- every slot has been rebound. Doing it here as well configured each
        -- button twice per refresh and repeated expensive region setters.
    end
    return true
end

function Runtime.Apply(root, slotRoot, parentFrame, forceRecreate)
    if not (root and Runtime.IsRoot(slotRoot)) then return nil end
    local deps = D()
    local key = slotRoot.rootKey or "SpellIndicators"
    local structuralSignature = slotRoot._msufA3StructuralSignature
    local layoutSignature = slotRoot._msufA3LayoutSignature
    local current = root[key]
    if forceRecreate ~= true and current and current._msufA3StructuralSignature == structuralSignature then
        deps.RebindUnit(current, slotRoot.unit)
        current._msufA3NativeLaneConfig = slotRoot
        UpdateSlots(current, slotRoot)
        Runtime.SyncGeometry(current, slotRoot, parentFrame)
        current:Show()
        if not deps.RegisterContainer(current) then return nil end
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        return current
    end
    Runtime.ReleaseContainerEffects(current, parentFrame)
    deps.HideContainer(current)
    root[key] = nil
    current = CreateSlots(root, slotRoot, parentFrame)
    if current then
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        root[key] = current
    end
    return current
end

Runtime.UpdateSlots = UpdateSlots

function Runtime.Recreate(container)
    if not (container and container._msufA3SpellIndicatorRoot == true) then return nil end
    if container._msufA3GroupSlotsRoot == true then
        return D().RecreateGroupSlots(container)
    end
    local slotRoot = container._msufA3NativeLaneConfig
    local parentFrame = container._msufA3ParentFrame
    local root = container.GetParent and container:GetParent() or nil
    if not (root and Runtime.IsRoot(slotRoot) and parentFrame) then return nil end
    local replacement = Runtime.Apply(root, slotRoot, parentFrame, true)
    if replacement then replacement._msufA3ForceSpellIndicatorGeometry = nil end
    return replacement
end
