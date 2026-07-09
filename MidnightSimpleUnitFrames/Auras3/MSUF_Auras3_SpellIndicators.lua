--- Auras3/MSUF_Auras3_SpellIndicators.lua
--- Group-frame spell indicators on WoW 12.1 CustomAuraContainer aura slots.
local _, MSUF = ...
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
local CreateFrame = _G.CreateFrame

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

local function AddNativeFilterToken(out, seen, token, baseToken)
    token = tostring(token or ""):upper():gsub("%s+", "")
    if token == "" then return end
    if token == "PLAYER_CAST" or token == "CAST_BY_ME" or token == "MINE" then token = "PLAYER" end
    if token == "ALL" or token == "ANY" then return end
    if token == "BUFF" then token = "HELPFUL" end
    if token == "DEBUFF" then token = "HARMFUL" end
    if token == "!PLAYER" and seen.PLAYER then return end
    if token == "PLAYER" and seen["!PLAYER"] then
        seen["!PLAYER"] = nil
        for i = #out, 1, -1 do
            if out[i] == "!PLAYER" then table.remove(out, i) end
        end
    end
    if token == "HELPFUL" or token == "HARMFUL" then
        if token ~= baseToken then return end
    end
    if seen[token] then return end
    seen[token] = true
    out[#out + 1] = token
end

local function NormalizeNativeFilterString(filter, fallback)
    fallback = tostring(fallback or "")
    filter = tostring(filter or "")
    local baseToken = (fallback:find("HARMFUL", 1, true) or filter:find("HARMFUL", 1, true)) and "HARMFUL" or "HELPFUL"
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
    local out, parts, count = nil, nil, 0
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
            if not out then out, parts = {}, {} end
            if out[spellID] ~= true then
                out[spellID] = true
                count = count + 1
                parts[count] = tostring(spellID)
            end
        end
    end
    if count == 0 then return nil, nil end
    table_sort(parts)
    return { [fieldName] = out }, fieldName .. ":" .. table_concat(parts, ",")
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

local function SlotTrackingSignature(slot)
    return tostring(slot.unit) .. "\030" .. tostring(slot.slotKey) .. "\030" .. tostring(slot.nativeFilter)
        .. "\030" .. tostring(slot.candidateFilterSignature)
end

local function SlotStructuralSignature(slot)
    return tostring(slot.slotKey) .. "\030" .. tostring(slot.nativeFilter)
end

local function SlotLayoutSignature(slot)
    local frame = slot.frameEffect
    local color = slot.color or {}
    local effectColor = frame and frame.color or {}
    return tostring(slot.visual) .. "\030" .. tostring(slot.hiddenVisual)
        .. "\030" .. tostring(slot.anchor) .. "\030" .. tostring(slot.x) .. "\030" .. tostring(slot.y)
        .. "\030" .. tostring(slot.size) .. "\030" .. tostring(slot.width) .. "\030" .. tostring(slot.height)
        .. "\030" .. tostring(slot.layer) .. "\030" .. tostring(slot.showCooldownText)
        .. "\030" .. tostring(slot.showCooldownSwipe) .. "\030" .. tostring(slot.cooldownSwipeReverse)
        .. "\030" .. tostring(slot.showStacks) .. "\030" .. tostring(color[1]) .. "\030" .. tostring(color[2])
        .. "\030" .. tostring(color[3]) .. "\030" .. tostring(color[4]) .. "\030" .. tostring(frame and frame.type)
        .. "\030" .. tostring(frame and frame.priority) .. "\030" .. tostring(frame and frame.thickness)
        .. "\030" .. tostring(effectColor[1]) .. "\030" .. tostring(effectColor[2]) .. "\030" .. tostring(effectColor[3])
        .. "\030" .. tostring(effectColor[4]) .. "\030" .. tostring(A3._nativeVisualGen or 0)
end

local function FinalizeSlot(slot)
    if slot then
        slot._msufA3TrackingSignature = SlotTrackingSignature(slot)
        slot._msufA3StructuralSignature = SlotStructuralSignature(slot)
        slot._msufA3LayoutSignature = SlotLayoutSignature(slot)
    end
    return slot
end

local function CompileSlot(unit, item, index, fallbackLayer)
    if not (type(unit) == "string" and unit ~= "" and type(item) == "table" and item.enabled == true) then return nil end
    local placed = type(item.placed) == "table" and item.placed or nil
    -- Live frame effects are temporarily disabled on 12.1 PTR. AuraSlot
    -- visibility is secret-backed, so effects must not depend on aura button
    -- show state until there is a non-secret assignment path in this runtime.
    local frameEffect = nil
    if not placed and not frameEffect then return nil end
    local candidateFilters, candidateFilterSignature = CandidateFiltersFromSpellIDs(item.includeSpellIDs, "includeSpellIDs")
    if not candidateFilters then return nil end

    local visual = tostring(placed and placed.type or "none"):lower()
    if visual ~= "icon" and visual ~= "square" and visual ~= "bar" and visual ~= "number" and visual ~= "none" then
        visual = "icon"
    end
    if visual == "none" and frameEffect == nil then return nil end
    local hiddenVisual = visual == "none" and frameEffect ~= nil
    local size = ClampNumber(placed and placed.size, hiddenVisual and 1 or 18, 1, 128)
    local width = visual == "bar" and ClampNumber(placed and placed.barWidth, size * 3, size, 256) or size
    local color = type(item.color) == "table" and item.color or nil
    local nativeFilter = item.onlyOwn ~= false and "HELPFUL|PLAYER" or "HELPFUL"
    return FinalizeSlot({
        spellIndicatorSlot = true,
        kind = "spellIndicator",
        slotKey = SpellIndicatorSlotKey(item, index),
        itemKey = item.key,
        display = item.display or item.auraName or tostring(index or ""),
        unit = unit,
        enabled = true,
        nativeFilter = NormalizeNativeFilterString(nativeFilter, "HELPFUL"),
        candidateFilters = candidateFilters,
        candidateFilterSignature = candidateFilterSignature,
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
        frameEffect = frameEffect,
        size = size,
        width = width,
        height = size,
        anchor = SpellIndicatorAnchor(placed and placed.anchor, "TOPLEFT"),
        x = Round(ClampNumber(placed and placed.x, 0, -4096, 4096)),
        y = Round(ClampNumber(placed and placed.y, 0, -4096, 4096)),
        layer = Round(ClampNumber(item.layer or fallbackLayer, fallbackLayer or 9, 1, 30)),
        alpha = 1,
        max = 1,
        spacing = 0,
        step = size,
        perRow = 1,
        cols = 1,
        rows = 1,
        showCooldownText = placed and placed.showCooldown ~= false and visual == "icon",
        showCooldownSwipe = placed and placed.showCooldownSwipe ~= false and visual == "icon",
        cooldownSwipeReverse = false,
        showDurationBar = false,
        durationBarHeight = DEFAULT_SHARED.durationBarHeight,
        durationBarDisplay = DEFAULT_SHARED.durationBarDisplay,
        durationBarPosition = DEFAULT_SHARED.durationBarPosition,
        durationBarDirection = DEFAULT_SHARED.durationBarDirection,
        showStacks = placed and placed.showStacks ~= false and (visual == "icon" or visual == "number"),
        showTooltip = false,
        showAuraBorder = false,
        showAuraSymbol = false,
        cooldownSize = DEFAULT_SHARED.cooldownTextSize,
        cooldownAnchor = "CENTER",
        cooldownX = 0,
        cooldownY = 0,
        cooldownDecimalSeconds = DEFAULT_SHARED.cooldownDecimalSeconds,
        stackAnchor = "BOTTOMRIGHT",
        stackSize = DEFAULT_SHARED.stackTextSize,
        stackX = 0,
        stackY = 0,
    })
end

function Runtime.CompileSlots(unit, spellIndicators)
    if not (type(spellIndicators) == "table" and spellIndicators.enabled == true and type(spellIndicators.items) == "table") then
        return nil
    end
    local slots, trackingParts, structuralParts, layoutParts = {}, {}, {}, {}
    for i = 1, #spellIndicators.items do
        local slot = CompileSlot(unit, spellIndicators.items[i], i, spellIndicators.layer)
        if slot then
            slots[#slots + 1] = slot
            trackingParts[#trackingParts + 1] = slot._msufA3TrackingSignature
            structuralParts[#structuralParts + 1] = slot._msufA3StructuralSignature
            layoutParts[#layoutParts + 1] = slot._msufA3LayoutSignature
        end
    end
    if #slots == 0 then return nil end
    return {
        spellIndicatorRoot = true,
        kind = "spellIndicators",
        rootKey = "SpellIndicators",
        unit = unit,
        enabled = true,
        slots = slots,
        max = #slots,
        layer = spellIndicators.layer or 9,
        _msufA3TrackingSignature = table_concat(trackingParts, "\029"),
        _msufA3StructuralSignature = table_concat(structuralParts, "\029"),
        _msufA3LayoutSignature = table_concat(layoutParts, "\029"),
    }
end

function Runtime.IsRoot(root)
    return root and root.enabled == true and root.spellIndicatorRoot == true
end

function Runtime.RootConfig(cfg)
    local root = cfg and cfg.spellIndicators
    return Runtime.IsRoot(root) and root or nil
end

function Runtime.Install(deps)
    Runtime._deps = deps or {}
end

local function D()
    return Runtime._deps or {}
end

local function SpellIndicatorTargetFrame(parentFrame)
    return parentFrame and (parentFrame.hpBar or parentFrame.Health or parentFrame.health or parentFrame)
end

local function EnsureEffectRoot(parentFrame)
    if not parentFrame then return nil end
    local root = parentFrame._msufA3SpellIndicatorEffectRoot
    if not root then
        root = CreateFrame("Frame", nil, parentFrame)
        root:SetAllPoints(parentFrame)
        root:SetFrameLevel((parentFrame:GetFrameLevel() or 0) + 24)
        parentFrame._msufA3SpellIndicatorEffectRoot = root
    end
    root:Show()
    return root
end

local function EnsureTint(parentFrame)
    local root = EnsureEffectRoot(parentFrame)
    if not root then return nil end
    local tint = parentFrame._msufA3SpellIndicatorHealthTint
    if not tint then
        tint = root:CreateTexture(nil, "OVERLAY")
        tint:SetTexture("Interface\\Buttons\\WHITE8X8")
        parentFrame._msufA3SpellIndicatorHealthTint = tint
    end
    return tint
end

local function EnsureEdges(parentFrame)
    local root = EnsureEffectRoot(parentFrame)
    if not root then return nil end
    local edges = parentFrame._msufA3SpellIndicatorEdges
    if not edges then
        edges = {}
        for i = 1, 4 do
            local tex = root:CreateTexture(nil, "OVERLAY")
            tex:SetTexture("Interface\\Buttons\\WHITE8X8")
            edges[i] = tex
        end
        parentFrame._msufA3SpellIndicatorEdges = edges
    end
    return edges
end

local function NameFontString(parentFrame)
    if not parentFrame then return nil end
    return parentFrame.Name
        or parentFrame.name
        or parentFrame.NameText
        or parentFrame.nameText
        or parentFrame._nameFS
end

local function ClearNameColor(parentFrame)
    local saved = parentFrame and parentFrame._msufA3SpellIndicatorSavedNameColor
    if not saved then return end
    local fs = saved.fs
    if fs and fs.SetTextColor then
        fs:SetTextColor(saved.r or 1, saved.g or 1, saved.b or 1, saved.a or 1)
    end
    parentFrame._msufA3SpellIndicatorSavedNameColor = nil
end

function Runtime.HideFrameEffects(parentFrame)
    if not parentFrame then return end
    local tint = parentFrame._msufA3SpellIndicatorHealthTint
    if tint then tint:Hide() end
    local edges = parentFrame._msufA3SpellIndicatorEdges
    if edges then
        for i = 1, #edges do
            if edges[i] then edges[i]:Hide() end
        end
    end
    ClearNameColor(parentFrame)
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
    Runtime.HideMissing(parentFrame)
end

local function LayoutEdges(parentFrame, effect)
    local edges = EnsureEdges(parentFrame)
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
    top:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", -thickness, thickness)
    top:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", thickness, thickness)
    top:SetHeight(thickness)
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", -thickness, -thickness)
    bottom:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", thickness, -thickness)
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
        edge:SetVertexColor(r, g, b, a)
        edge:Show()
    end
end

function Runtime.RefreshFrameEffects(parentFrame)
    -- 12.1 AuraButton visibility is secret-backed. Reading IsShown() here
    -- throws "boolean test on a secret boolean"; keep icon slots active and
    -- leave live frame effects off until we have a non-secret native signal.
    Runtime.HideFrameEffects(parentFrame)
    return false
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
    return frame
end

local function SyncMissingFrame(parentFrame, slot, button)
    local frame = EnsureMissingFrame(parentFrame, slot)
    if not frame then
        local missing = parentFrame and parentFrame._msufA3SpellIndicatorMissingFrames and parentFrame._msufA3SpellIndicatorMissingFrames[slot and slot.slotKey]
        if missing then missing:Hide() end
        return
    end
    frame:ClearAllPoints()
    frame:SetSize(slot.width or slot.size or 1, slot.height or slot.size or 1)
    frame:SetPoint(slot.anchor or "TOPLEFT", parentFrame, slot.anchor or "TOPLEFT", slot.x or 0, slot.y or 0)
    frame:SetFrameLevel((parentFrame:GetFrameLevel() or 0) + (slot.layer or 9) - 1)
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

local function SyncButtonGeometry(button, slot, parentFrame)
    if not (button and slot and parentFrame) then return false end
    button:ClearAllPoints()
    button:SetSize(slot.width or slot.size or 1, slot.height or slot.size or 1)
    button:SetPoint(slot.anchor or "TOPLEFT", parentFrame, slot.anchor or "TOPLEFT", slot.x or 0, slot.y or 0)
    if button.SetFrameLevel then button:SetFrameLevel((parentFrame:GetFrameLevel() or 0) + (slot.layer or 9)) end
    return true
end

local function ApplyVisual(button, slot)
    if not (button and slot) then return end
    local icon = button.Icon
    if not icon then
        icon = button:CreateTexture(nil, "ARTWORK")
        button.Icon = icon
    end
    if slot.hiddenVisual == true then
        button:SetAlpha(0)
        button:ClearIcon()
        button:ClearApplicationCount()
        button:ClearDurationCooldown()
        button:ClearDurationText()
        button:ClearDurationBar()
        button:ClearAuraBorder()
        button:ClearAuraSymbol()
        icon:Hide()
        if button._msufA3SpellIndicatorSwatch then button._msufA3SpellIndicatorSwatch:Hide() end
        return
    end
    button:SetAlpha(1)
    if slot.visual == "square" or slot.visual == "bar" then
        icon:SetAlpha(0)
        local swatch = button._msufA3SpellIndicatorSwatch
        if not swatch then
            swatch = button:CreateTexture(nil, "OVERLAY")
            button._msufA3SpellIndicatorSwatch = swatch
        end
        swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
        swatch:SetTexCoord(0, 1, 0, 1)
        swatch:SetVertexColor(slot.color[1] or 1, slot.color[2] or 1, slot.color[3] or 1, slot.color[4] or 1)
        swatch:ClearAllPoints()
        swatch:SetAllPoints(button)
        swatch:Show()
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

local function PrepareButton(button, slot, parentFrame)
    local deps = D()
    if not (button and slot and parentFrame and deps.PrepareAuraButton and deps.ValidateAuraButton) then return false end
    deps.ValidateAuraButton(button)
    button._msufA3ManagedAuraButton = true
    button._msufA3NativeButton = true
    button._msufA3LaneKind = "spellIndicator"
    button._msufA3SpellIndicatorSlot = slot
    button._msufA3SpellIndicatorParentFrame = parentFrame
    button._msufA3ParentFrame = parentFrame
    deps.PrepareAuraButton(button, slot, 1)
    SyncButtonGeometry(button, slot, parentFrame)
    ApplyVisual(button, slot)
    SyncMissingFrame(parentFrame, slot, button)
    if button.EnableMouse then button:EnableMouse(false) end
    button:SetMouseMotionEnabled(false)
    if parentFrame._msufA3SpellIndicatorEffectButtons then
        parentFrame._msufA3SpellIndicatorEffectButtons[button] = nil
    end
    return true
end

local function SlotOptions(container, slot, buttonIndex)
    return {
        maxFrameCount = 1,
        candidateFilters = slot.candidateFilters,
        initializeFrame = function(button)
            container[buttonIndex] = button
            container._msufA3SpellIndicatorButtonSlots[buttonIndex] = slot
            PrepareButton(button, slot, container._msufA3ParentFrame)
        end,
    }
end

function Runtime.SyncGeometry(container, slotRoot, parentFrame)
    if not (container and Runtime.IsRoot(slotRoot)) then return false end
    parentFrame = parentFrame or container._msufA3ParentFrame or container:GetParent()
    if not parentFrame then return false end
    container._msufA3NativeLaneConfig = slotRoot
    container._msufA3ParentFrame = parentFrame
    local root = container:GetParent()
    if root then
        container:ClearAllPoints()
        container:SetAllPoints(root)
    end
    if container.SetFrameLevel then container:SetFrameLevel(parentFrame:GetFrameLevel() or 0) end
    local slots = container._msufA3SpellIndicatorButtonSlots
    if slots then
        for i = 1, #slots do
            if slots[i] and container[i] then
                PrepareButton(container[i], slots[i], parentFrame)
            elseif slots[i] then
                SyncMissingFrame(parentFrame, slots[i], nil)
            end
        end
    end
    if type(slotRoot.slots) == "table" then
        for i = 1, #slotRoot.slots do
            local slot = slotRoot.slots[i]
            if not (slots and slots[i]) then SyncMissingFrame(parentFrame, slot, nil) end
        end
    end
    Runtime.RefreshFrameEffects(parentFrame)
    return true
end

local function CreateSlots(root, slotRoot, parentFrame)
    local deps = D()
    if not (deps.EnsureLoaded and deps.CreateContainer and deps.ConfigureContainer and deps.RegisterContainer) then return nil end
    if not deps.EnsureLoaded() then
        A3.nativeAuraRuntimeAvailable = false
        A3.nativeAuraRuntimeError = (deps.addonName or "Blizzard_AuraContainer") .. " is not loaded: " .. tostring(A3.nativeAuraRuntimeLoadError or "unknown")
        return nil
    end
    local container = deps.CreateContainer(root)
    if not container then return nil end
    A3.nativeAuraRuntimeAvailable = true
    container._msufA3ManagedAuraSlots = true
    container._msufA3SpellIndicatorRoot = true
    container._msufA3NativeLane = slotRoot.kind
    container._msufA3NativeRegistered = nil
    container._msufA3NativeRegistrationPending = nil
    container._msufA3SpellIndicatorButtonSlots = {}
    container._msufA3SpellIndicatorSlotCandidateFilterSignatures = {}
    container.unit = slotRoot.unit
    container.createdButtons = slotRoot.max or 0
    deps.ConfigureContainer(container, slotRoot.unit)
    Runtime.SyncGeometry(container, slotRoot, parentFrame)
    for i = 1, #slotRoot.slots do
        local slot = slotRoot.slots[i]
        local addSlotToken = A3._TraceBeginLane("MSUF.AddAuraSlot", slot, slot.slotKey)
        container:AddAuraSlot(slot.slotKey, slot.nativeFilter, SlotOptions(container, slot, i))
        A3._TraceEnd(addSlotToken)
        container._msufA3SpellIndicatorSlotCandidateFilterSignatures[slot.slotKey] = slot.candidateFilterSignature
    end
    if not deps.RegisterContainer(container) then
        if container.Hide then container:Hide() end
        return nil
    end
    container:Show()
    A3.nativeAuraRuntimeError = nil
    return container
end

local function UpdateSlots(container, slotRoot)
    if not (container and Runtime.IsRoot(slotRoot) and type(slotRoot.slots) == "table") then return false end
    container._msufA3SpellIndicatorButtonSlots = container._msufA3SpellIndicatorButtonSlots or {}
    container._msufA3SpellIndicatorSlotCandidateFilterSignatures = container._msufA3SpellIndicatorSlotCandidateFilterSignatures or {}
    for i = 1, #slotRoot.slots do
        local slot = slotRoot.slots[i]
        container._msufA3SpellIndicatorButtonSlots[i] = slot
        if container._msufA3SpellIndicatorSlotCandidateFilterSignatures[slot.slotKey] ~= slot.candidateFilterSignature then
            container:SetAuraSlotCandidateFilters(slot.slotKey, slot.candidateFilters)
            container._msufA3SpellIndicatorSlotCandidateFilterSignatures[slot.slotKey] = slot.candidateFilterSignature
        end
        if container[i] then
            PrepareButton(container[i], slot, container._msufA3ParentFrame)
        end
    end
    return true
end

function Runtime.Apply(root, slotRoot, parentFrame, forceRecreate)
    if not (root and Runtime.IsRoot(slotRoot)) then return nil end
    local deps = D()
    if not deps.HideContainer then return nil end
    local traceToken = A3._TraceBeginLane("MSUF.ApplySpellIndicators", slotRoot, forceRecreate == true and "force" or "auto")
    local key = slotRoot.rootKey or "SpellIndicators"
    local trackingSignature = slotRoot._msufA3TrackingSignature
    local structuralSignature = slotRoot._msufA3StructuralSignature
    local layoutSignature = slotRoot._msufA3LayoutSignature
    local current = root[key]
    if forceRecreate ~= true and current and current._msufA3StructuralSignature == structuralSignature then
        if deps.RebindUnit then deps.RebindUnit(current, slotRoot.unit) end
        current._msufA3NativeLaneConfig = slotRoot
        UpdateSlots(current, slotRoot)
        Runtime.SyncGeometry(current, slotRoot, parentFrame)
        current:Show()
        if deps.RegisterContainer and not deps.RegisterContainer(current) then return A3._TraceFinish(traceToken, nil) end
        if current._msufA3TrackingSignature ~= trackingSignature and type(current.UpdateAllAuras) == "function" then
            local updateToken = A3._TraceBeginContainer("MSUF.UpdateAllAuras", current, "spellIndicators")
            current:UpdateAllAuras()
            A3._TraceEnd(updateToken)
        end
        current._msufA3TrackingSignature = trackingSignature
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        return A3._TraceFinish(traceToken, current)
    end
    deps.HideContainer(current)
    root[key] = nil
    current = CreateSlots(root, slotRoot, parentFrame)
    if current then
        current._msufA3TrackingSignature = trackingSignature
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        root[key] = current
    end
    return A3._TraceFinish(traceToken, current)
end
