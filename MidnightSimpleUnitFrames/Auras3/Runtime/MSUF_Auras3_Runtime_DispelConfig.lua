-- Auras3 runtime: DispelConfig.
-- Independent border, overlay, corner and symbol descriptors. Preserve each visual's trigger and identity policy, including border-only Show on.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.DispelConfig = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local table_concat = table.concat
local tostring = tostring
local type = type
local BORDER_SENSOR_DETAIL = dependencies.Platform.BORDER_SENSOR_DETAIL
local Clamp01 = dependencies.Platform.Clamp01
local ClampNumber = dependencies.Platform.ClampNumber
local DS = dependencies.Appearance.DS
local DispelSensorNativeFilter = dependencies.ConfigValues.DispelSensorNativeFilter
local NormalizeDispelSensorTrigger = dependencies.ConfigValues.NormalizeDispelSensorTrigger
local NormalizeFrameStrata = dependencies.Platform.NormalizeFrameStrata
local ReadAnchor = dependencies.ConfigValues.ReadAnchor
local Round = dependencies.Platform.Round

local function NormalizeDispelOverlayStyle(value)
    value = tostring(value or "FULL"):upper()
    if value == "TOP" or value == "BOTTOM" or value == "LEFT" or value == "RIGHT" then return value end
    return "FULL"
end

function DS.Style(value)
    value = tostring(value or "BLIZZARD"):upper()
    if DS.folders[value] then return value end
    -- Pre-multi-set profiles stored a single "MSUF" set; that art is now Letters.
    if value == "MSUF" or value == "CUSTOM" then return "MSUF_LETTERS" end
    if value == "BLIZZARD_RING" or value == "RING" then return "BLIZZARD_RING" end
    if value == "BLIZZARD_BORDER" or value == "BORDER" then return "BLIZZARD_BORDER" end
    return "BLIZZARD"
end

--- ALL (the default) shows one symbol per dispel type that is actually present,
--- so two debuffs of different types read as two symbols. It costs one aura slot
--- per type -- see DS.Slots -- but only once the symbol itself is switched on,
--- which is off by default. TOP is the one-slot fallback that shows only the
--- highest-priority matching debuff.
function DS.Mode(value)
    value = tostring(value or "ALL"):upper()
    if value == "TOP" or value == "HIGHEST" or value == "PRIORITY" then return "TOP" end
    return "ALL"
end

function DS.Growth(value)
    value = tostring(value or "RIGHT"):upper()
    if value == "LEFT" or value == "UP" or value == "DOWN" then return value end
    return "RIGHT"
end

--- Resolve the row direction against its anchor.
---
--- A right-edge anchor growing RIGHT (or a left anchor growing LEFT, a top
--- anchor growing UP, a bottom anchor growing DOWN) marches the row straight off
--- the frame: symbol 1 lands on the corner and the rest sit outside, over the
--- world or -- in a raid -- on top of the neighbouring frame. That reads as "only
--- one symbol shows". Outward choices are mirrored so the row always runs ALONG
--- the frame from its anchored corner. Perpendicular choices and CENTER anchors
--- pass through untouched, so "TOPRIGHT + Down" still stacks downwards.
function DS.ResolveGrowth(growth, anchor)
    growth = DS.Growth(growth)
    anchor = tostring(anchor or "TOPRIGHT"):upper()
    if growth == "RIGHT" and anchor:find("RIGHT", 1, true) then return "LEFT" end
    if growth == "LEFT" and anchor:find("LEFT", 1, true) then return "RIGHT" end
    if growth == "UP" and anchor:find("TOP", 1, true) then return "DOWN" end
    if growth == "DOWN" and anchor:find("BOTTOM", 1, true) then return "UP" end
    return growth
end

--- ALL mode: one slot per dispel type, each narrowed by an includeDispelTypes
--- candidate filter. Blizzard evaluates those against the secret dispelName
--- inside its own partition (Blizzard_AuraContainerUtil.lua), and unlike
--- spellID filters they are not gated by CanApplyIdentityCandidateFilters, so
--- this works on friendly units too. Slot i sits at step i-1 along `growth`,
--- which means a missing type leaves a hole rather than reshuffling the row --
--- deliberate: a symbol that keeps its place is readable at a glance.
function DS.Slots(symbol, size, spacing)
    local growth = DS.ResolveGrowth(symbol and symbol.growth, symbol and symbol.anchor)
    local slots, parts = {}, {}
    local step = size + spacing
    for i = 1, #DS.types do
        local dispelType = DS.types[i]
        local offset = (i - 1) * step
        local x, y = 0, 0
        -- Guard the first slot explicitly: negating zero yields "-0", which would
        -- put a pointless variant into the layout signature.
        if offset ~= 0 then
            if growth == "LEFT" then x = -offset
            elseif growth == "UP" then y = offset
            elseif growth == "DOWN" then y = -offset
            else x = offset end
        end
        slots[i] = {
            key = dispelType,
            dispelType = dispelType,
            x = x,
            y = y,
            -- Shared immutable filter table; see DS.filters.
            candidateFilters = DS.filters[dispelType],
            candidateFilterSignature = dispelType,
        }
        parts[i] = dispelType .. ":" .. tostring(x) .. ":" .. tostring(y)
    end
    return slots, table_concat(parts, "|"), growth
end

local function CompileCornerDispelSlots(corner)
    if not (type(corner) == "table" and corner.enabled == true and corner.needsDispel == true and type(corner.dispelSlots) == "table") then
        return nil, nil
    end
    local source = corner.dispelSlots
    local slots, parts = {}, {}
    for i = 1, #source do
        local slot = source[i]
        if type(slot) == "table" then
            local key = tostring(slot.key or i)
            local anchor = ReadAnchor(slot, nil, "anchor", "TOPLEFT")
            local x = Round(ClampNumber(slot.x, 0, -128, 128))
            local y = Round(ClampNumber(slot.y, 0, -128, 128))
            local out = { key = key, anchor = anchor, x = x, y = y }
            slots[#slots + 1] = out
            parts[#parts + 1] = key .. ":" .. anchor .. ":" .. tostring(x) .. ":" .. tostring(y)
        end
    end
    if #slots == 0 then return nil, nil end
    return slots, table_concat(parts, "|")
end

local function CompileDispelSensor(unit, frameSpec, groupMode, visual)
    if not (type(unit) == "string" and unit ~= "" and type(frameSpec) == "table") then return nil end
    local border = frameSpec.border
    local group = frameSpec.group
    local overlay = groupMode and group or frameSpec.dispelOverlay
    local corner = groupMode and frameSpec.cornerIndicators or nil
    -- The symbol sensor is the one dispel visual that is NOT group-only: both
    -- unit frames and group frames compile it from a dispelSymbol table.
    local symbol = frameSpec.dispelSymbol
    local cornerSlots, cornerSignature = nil, nil
    if visual == "corner" then
        cornerSlots, cornerSignature = CompileCornerDispelSlots(corner)
    end
    local borderOn = border and border.dispel == true
    local purgeOn = not groupMode and border and border.purge == true
        and (unit == "target" or unit == "focus")
    local overlayOn = overlay and ((groupMode and overlay.dispelOverlayEnabled == true) or (not groupMode and overlay.enabled == true))
    local symbolOn = type(symbol) == "table" and symbol.enabled == true
    if visual == "border" and not borderOn then return nil end
    if visual == "purge" and not purgeOn then return nil end
    if visual == "overlay" and not overlayOn then return nil end
    if visual == "corner" and not cornerSlots then return nil end
    if visual == "symbol" and not symbolOn then return nil end

    local borderTrigger = NormalizeDispelSensorTrigger(border and border.dispelTrigger, "BY_ME")
    local trigger = borderTrigger
    if visual == "overlay" then
        trigger = NormalizeDispelSensorTrigger(groupMode and overlay.dispelOverlayTrigger or overlay.trigger, "BORDER")
        if trigger == "BORDER" then trigger = borderTrigger end
    elseif visual == "corner" then
        trigger = "BY_ME"
    elseif visual == "symbol" then
        trigger = NormalizeDispelSensorTrigger(symbol.trigger, "BORDER")
        if trigger == "BORDER" then trigger = borderTrigger end
    end

    local symbolMode, symbolStyle, symbolSlots, symbolSignature, symbolGrowth
    local symbolSize, symbolSpacing, symbolAnchor, symbolX, symbolY
    if visual == "symbol" then
        symbolMode = DS.Mode(symbol.mode)
        symbolStyle = DS.Style(symbol.style)
        symbolSize = Round(ClampNumber(symbol.size, 14, 4, 64))
        symbolSpacing = Round(ClampNumber(symbol.spacing, 2, 0, 32))
        symbolAnchor = ReadAnchor(symbol, nil, "anchor", "TOPRIGHT")
        symbolX = Round(ClampNumber(symbol.x, 0, -256, 256))
        symbolY = Round(ClampNumber(symbol.y, 0, -256, 256))
        if symbolMode == "ALL" then
            symbolSlots, symbolSignature, symbolGrowth = DS.Slots(symbol, symbolSize, symbolSpacing)
        else
            symbolGrowth = DS.ResolveGrowth(symbol.growth, symbol.anchor)
        end
    end

    local nativeFilter, maxCount = DispelSensorNativeFilter(trigger)
    if visual == "purge" then nativeFilter, maxCount = "HELPFUL", 1 end
    if visual == "symbol" then
        -- TOP mode is one slot showing the top-priority matching debuff. ALL
        -- mode is one slot PER dispel type, each carrying its own
        -- includeDispelTypes candidate filter -- the only way to have several
        -- types visible at once, because a single slot always resolves to a
        -- single aura.
        maxCount = symbolSlots and #symbolSlots or 1
    elseif visual ~= "corner" and maxCount > 1 then
        -- AuraSlots do not de-duplicate across identical filters: every copy
        -- selects the same top aura. One slot therefore drives the same fixed
        -- border/overlay without duplicate native slot-manager work.
        maxCount = 1
    end
    local overlayOnHealth = visual == "overlay" and ((groupMode and overlay.dispelOverlayOnHealth ~= false) or (not groupMode and overlay.onHealth ~= false))
    local target = visual == "overlay" and (overlayOnHealth and "healthFill" or "healthBar") or "frame"
    local cornerCount = cornerSlots and #cornerSlots or nil
    local strata
    if visual == "overlay" then
        strata = groupMode and overlay.dispelOverlayStrata or overlay.strata
    elseif visual == "corner" then
        strata = corner and corner.strata
    elseif visual == "symbol" then
        strata = symbol.strata
    else
        strata = border and border.strata
    end
    local kind = "dispelBorder"
    local rootKey = "DispelBorderSensor"
    if visual == "purge" then
        kind, rootKey = "purgeBorder", "PurgeBorderSensor"
    elseif visual == "corner" then
        kind, rootKey = "dispelCorner", "DispelCornerSensor"
    elseif visual == "overlay" then
        kind, rootKey = "dispelOverlay", "DispelOverlaySensor"
    elseif visual == "symbol" then
        kind, rootKey = "dispelSymbol", "DispelSymbolSensor"
    end
    -- Dispel and Purge borders sit in the Frame Outline Layer band at the
    -- Borders-element highlight detail; the configured highlight priority
    -- still orders them inside that band (first entry on top).
    local priorityDetail = BORDER_SENSOR_DETAIL - 2
    local priorityOrder = border and border.prioEnabled == true and border.prioOrder
        or A3.DEFAULT_NATIVE_HIGHLIGHT_PRIORITY
    local priorityKey = visual == "purge" and "purge" or (visual == "border" and "dispel" or nil)
    if priorityKey and type(priorityOrder) == "table" then
        for index = 1, #priorityOrder do
            if priorityOrder[index] == priorityKey then priorityDetail = BORDER_SENSOR_DETAIL + 1 - index; break end
        end
    end
    local borderLayer = Round(ClampNumber(border and border.layer, 0, 0, 30))
    -- Native dispel filters are not reaction-scoped. "Dispellable by me/group"
    -- keeps the assist identity gate for friendly cleansing, but "Any dispel
    -- type" intentionally includes typed harmful auras on enemies. Like Purge
    -- and "cast by me", it must use the neutral owner so the assist gate cannot
    -- disable its native sensor. Group sensors stay neutral; their presence
    -- gate already owns offline/phase visibility.
    local identityCandidateMode
    if not groupMode and visual ~= "purge" and trigger ~= "PLAYER_CAST" and trigger ~= "DISPEL_TYPE" then
        identityCandidateMode = "assist"
    end
    -- This is an additional unit filter for the border only. Keep the native
    -- trigger and every other visual's identity policy independent.
    if visual == "border" then
        local showOn = border and border.dispelShowOn
        if showOn == "FRIENDLY" then
            identityCandidateMode = "assist"
        elseif showOn == "ENEMY" then
            -- Ability-scoped Unit cleansing already requires a friendly unit.
            if identityCandidateMode == "assist" then return nil end
            identityCandidateMode = "hostile"
        end
    end
    return {
        sensor = true,
        kind = kind,
        rootKey = rootKey,
        unit = unit,
        enabled = true,
        identityCandidateMode = identityCandidateMode,
        nativeFilter = nativeFilter,
        candidateFilters = visual == "purge" and { isStealable = true } or nil,
        candidateFilterSignature = visual == "purge" and "isStealable:true" or nil,
        -- Corner sensors consolidate onto ONE AuraSlot whose button carries a
        -- texture per corner (PTR 7 multiple dispel textures). Identical
        -- filters always select the same top aura, so N corner slots were N
        -- copies of the same native slot manager doing identical work.
        -- filterCount still records the region count for signatures.
        max = cornerSlots and 1 or maxCount,
        filterCount = cornerCount or (symbolSlots and #symbolSlots) or nil,
        filterMax = cornerCount and 1 or maxCount,
        visual = visual,
        target = target,
        style = visual == "overlay" and NormalizeDispelOverlayStyle(groupMode and overlay.dispelOverlayStyle or overlay.style)
            or (visual == "symbol" and symbolStyle)
            or "FULL",
        alpha = visual == "corner" and Clamp01(corner and corner.alpha, 1)
            or (visual == "overlay" and Clamp01(groupMode and overlay.dispelOverlayAlpha or overlay.alpha, 0.35))
            or (visual == "symbol" and Clamp01(symbol.alpha, 1))
            or 1,
        thickness = ClampNumber(border and border.highlightThickness, 3, 1, 32),
        r = visual == "purge" and Clamp01(border and border.purgeR, 1) or nil,
        g = visual == "purge" and Clamp01(border and border.purgeG, 0.85) or nil,
        b = visual == "purge" and Clamp01(border and border.purgeB, 0) or nil,
        size = cornerSlots and ClampNumber(corner and corner.size, 8, 1, 64) or symbolSize or nil,
        slots = cornerSlots or symbolSlots,
        slotSignature = cornerSignature or symbolSignature,
        mode = symbolMode,
        growth = symbolGrowth,
        spacing = symbolSpacing,
        anchor = symbolAnchor,
        x = symbolX,
        y = symbolY,
        layer = visual == "corner" and (30 + ClampNumber(corner and corner.layer, 7, 0, 30))
            or (visual == "symbol" and (30 + ClampNumber(symbol.layer, 8, 0, 30)))
            or (visual == "overlay" and ClampNumber(groupMode and overlay.dispelOverlayLayer or overlay.layer, 0, 0, 30) or borderLayer),
        detail = priorityDetail,
        strata = NormalizeFrameStrata(strata, "AUTO"),
        trigger = trigger,
    }
end

return {
    CompileDispelSensor = CompileDispelSensor,
}
end
