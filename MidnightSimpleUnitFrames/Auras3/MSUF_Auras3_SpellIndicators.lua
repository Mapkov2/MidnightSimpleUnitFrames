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
local hooksecurefunc = _G.hooksecurefunc
local issecretvalue = _G.issecretvalue or function(_) return false end
local MAX_FINITE_AURA_DURATION = 2147483647
local ICON_ALERT_TEXTURE = [[Interface\SpellActivationOverlay\IconAlert]]
local ICON_ALERT_ANTS_TEXTURE = [[Interface\SpellActivationOverlay\IconAlertAnts]]

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
    if issecretvalue(value) == true then value = nil end
    if value == nil or value == "" or value == "AUTO" then
        return ReadParentFrameStrata(parentFrame)
    end
    local rank = _G.MSUF_FRAME_STRATA_RANK
    if type(value) == "string" and rank and rank[value] then return value end
    value = NormalizeFrameStrata(value, "AUTO")
    if value ~= "AUTO" then return value end
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

local function AddHidePermanentCandidateFilter(candidateFilters, candidateFilterSignature, hidePermanent)
    if hidePermanent ~= true then return candidateFilters, candidateFilterSignature end
    candidateFilters = candidateFilters or {}
    candidateFilters.maxDuration = MAX_FINITE_AURA_DURATION
    local part = "maxDuration:" .. tostring(MAX_FINITE_AURA_DURATION)
    candidateFilterSignature = candidateFilterSignature and (candidateFilterSignature .. ";" .. part) or part
    return candidateFilters, candidateFilterSignature
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
        .. "\030" .. tostring(slot.layer) .. "\030" .. tostring(slot.strata) .. "\030" .. tostring(slot.showCooldownText)
        .. "\030" .. tostring(slot.showCooldownSwipe) .. "\030" .. tostring(slot.cooldownSwipeReverse)
        .. "\030" .. tostring(slot.cooldownSize) .. "\030" .. tostring(slot.cooldownAnchor)
        .. "\030" .. tostring(slot.cooldownX) .. "\030" .. tostring(slot.cooldownY)
        .. "\030" .. tostring(slot.cooldownDecimalSeconds)
        .. "\030" .. tostring(slot.showDurationBar) .. "\030" .. tostring(slot.durationBarHeight)
        .. "\030" .. tostring(slot.durationBarDisplay) .. "\030" .. tostring(slot.durationBarPosition)
        .. "\030" .. tostring(slot.durationBarDirection)
        .. "\030" .. tostring(slot.showStacks) .. "\030" .. tostring(slot.stackSize)
        .. "\030" .. tostring(slot.stackAnchor) .. "\030" .. tostring(slot.stackX) .. "\030" .. tostring(slot.stackY)
        .. "\030" .. tostring(slot.showTooltip) .. "\030" .. tostring(color[1]) .. "\030" .. tostring(color[2])
        .. "\030" .. tostring(color[3]) .. "\030" .. tostring(color[4]) .. "\030" .. tostring(slot.iconEffect)
        .. "\030" .. tostring(frame and frame.type)
        .. "\030" .. tostring(frame and frame.priority) .. "\030" .. tostring(frame and frame.thickness)
        .. "\030" .. tostring(frame and frame.tintAlpha) .. "\030" .. tostring(frame and frame.strata)
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

local function CompileSlot(unit, item, index, fallbackLayer, fallbackStrata, sharedBuffStyle)
    if not (type(unit) == "string" and unit ~= "" and type(item) == "table" and item.enabled == true) then return nil end
    local placed = type(item.placed) == "table" and item.placed or nil
    local frameEffect = type(item.frame) == "table" and item.frame or nil
    if frameEffect and (frameEffect.type == nil or frameEffect.type == "" or frameEffect.type == "none") then frameEffect = nil end
    if not placed and not frameEffect then return nil end
    local candidateFilters, candidateFilterSignature = CandidateFiltersFromSpellIDs(item.includeSpellIDs, "includeSpellIDs")
    if not candidateFilters then return nil end
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
    -- Spell selection and placement stay per indicator. Reusable icon
    -- appearance belongs to the scope's Aura Style > Buffs lane so Party and
    -- Raid never expose a second, drifting cooldown/stack style surface.
    -- Corner custom slots deliberately retain their explicit no-text contract.
    local appearance = item.cornerSlotKey == nil and type(sharedBuffStyle) == "table" and sharedBuffStyle or nil
    local size = ClampNumber(placed and placed.size, hiddenVisual and 1 or 18, 1, 128)
    local width = visual == "bar" and ClampNumber(placed and placed.barWidth, size * 3, size, 256) or size
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
        display = item.display or item.auraName or tostring(index or ""),
        unit = unit,
        enabled = true,
        nativeFilter = NormalizeNativeFilterString(nativeFilter, nativeFilter),
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
        iconEffect = iconEffect,
        frameEffect = frameEffect,
        size = size,
        width = width,
        height = size,
        anchor = SpellIndicatorAnchor(placed and placed.anchor, "TOPLEFT"),
        x = Round(ClampNumber(placed and placed.x, 0, -4096, 4096)),
        y = Round(ClampNumber(placed and placed.y, 0, -4096, 4096)),
        layer = Round(ClampNumber(item.layer or fallbackLayer, fallbackLayer or 9, 0, 30)),
        strata = NormalizeFrameStrata(rawStrata, "AUTO"),
        alpha = 1,
        max = 1,
        spacing = 0,
        step = size,
        perRow = 1,
        cols = 1,
        rows = 1,
        showCooldownText = (appearance and appearance.showCooldownText ~= false or (not appearance and placed and placed.showCooldown ~= false)) and visual == "icon",
        showCooldownSwipe = (appearance and appearance.showCooldownSwipe ~= false or (not appearance and placed and placed.showCooldownSwipe ~= false)) and visual == "icon",
        cooldownSwipeReverse = appearance and appearance.cooldownSwipeReverse == true or false,
        showDurationBar = appearance and appearance.showDurationBar == true and visual == "icon" or false,
        durationBarHeight = ClampNumber(appearance and appearance.durationBarHeight, DEFAULT_SHARED.durationBarHeight, 1, 16),
        durationBarDisplay = appearance and appearance.durationBarDisplay or DEFAULT_SHARED.durationBarDisplay,
        durationBarPosition = appearance and appearance.durationBarPosition or DEFAULT_SHARED.durationBarPosition,
        durationBarDirection = appearance and appearance.durationBarDirection or DEFAULT_SHARED.durationBarDirection,
        showStacks = (appearance and appearance.showStacks ~= false or (not appearance and placed and placed.showStacks ~= false)) and (visual == "icon" or visual == "number"),
        showTooltip = appearance and appearance.showTooltip ~= false or false,
        showAuraBorder = false,
        showAuraSymbol = false,
        cooldownSize = ClampNumber(appearance and appearance.cooldownSize or (placed and placed.cooldownSize), DEFAULT_SHARED.cooldownTextSize, 6, 40),
        cooldownAnchor = SpellIndicatorAnchor(appearance and appearance.cooldownAnchor, "CENTER"),
        cooldownX = ClampNumber(appearance and appearance.cooldownX, 0, -2000, 2000),
        cooldownY = ClampNumber(appearance and appearance.cooldownY, 0, -2000, 2000),
        cooldownDecimalSeconds = ClampNumber(appearance and appearance.cooldownDecimalSeconds, DEFAULT_SHARED.cooldownDecimalSeconds, 0, 30),
        stackAnchor = SpellIndicatorAnchor(appearance and appearance.stackAnchor, "BOTTOMRIGHT"),
        stackSize = ClampNumber(appearance and appearance.stackSize, DEFAULT_SHARED.stackTextSize, 6, 40),
        stackX = ClampNumber(appearance and appearance.stackX, 0, -2000, 2000),
        stackY = ClampNumber(appearance and appearance.stackY, 0, -2000, 2000),
    })
end

function Runtime.CompileSlots(unit, spellIndicators, sharedBuffStyle)
    if not (type(spellIndicators) == "table" and spellIndicators.enabled == true and type(spellIndicators.items) == "table") then
        return nil
    end
    local slots, trackingParts, structuralParts, layoutParts = {}, {}, {}, {}
    for i = 1, #spellIndicators.items do
        local slot = CompileSlot(unit, spellIndicators.items[i], i, spellIndicators.layer, spellIndicators.strata, sharedBuffStyle)
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
        strata = NormalizeFrameStrata(spellIndicators.strata, "AUTO"),
        _msufA3TrackingSignature = table_concat(trackingParts, "\029"),
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

function Runtime.Install(deps)
    Runtime._deps = deps or {}
end

local function D()
    return Runtime._deps or {}
end

local function SpellIndicatorTargetFrame(parentFrame)
    return parentFrame and (parentFrame.hpBar or parentFrame.Health or parentFrame.health or parentFrame)
end

local function EnsureEffectRoot(button, parentFrame)
    if not (button and parentFrame) then return nil end
    local root = button._msufA3SpellIndicatorEffectRoot
    if not root then
        -- The AuraSlot button is shown with Blizzard's secret-wrapped native
        -- assignment state. Parenting the full-frame visual to that button
        -- makes visibility flow through the frame tree without inspecting a
        -- secret boolean in addon Lua.
        root = CreateFrame("Frame", nil, button)
        root:EnableMouse(false)
        root:SetAllPoints(parentFrame)
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
-- Both the full-frame and icon effects use this renderer; because their roots
-- are children of the native AuraSlot button, Blizzard's secret visibility is
-- inherited without reading or branching on it in addon Lua.
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

local function AnchorAnimatedGlow(data, owner, padding)
    if not (data and owner) or data.padding == padding then return end
    data.padding = padding
    local haloPadding = padding * 1.55
    data.halo:ClearAllPoints()
    data.halo:SetPoint("TOPLEFT", owner, "TOPLEFT", -haloPadding, haloPadding)
    data.halo:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", haloPadding, -haloPadding)
    data.ants:ClearAllPoints()
    data.ants:SetPoint("TOPLEFT", owner, "TOPLEFT", -padding, padding)
    data.ants:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", padding, -padding)
end

local function StartAnimatedGlow(owner, r, g, b, a, padding)
    local data = EnsureAnimatedGlow(owner)
    if not data then return false end
    padding = ClampNumber(padding, 3, 1, 24)
    AnchorAnimatedGlow(data, owner, padding)
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
    local registry = overlay and overlay._msufA3NameRegistry
    if registry then registry[overlay] = nil end
    if overlay then
        overlay._msufA3NameRegistry = nil
        overlay._msufA3NameSource = nil
        overlay:Hide()
    end
end

local function SyncNameOverlayFont(overlay, source)
    if not (overlay and source) then return end
    local path, size, flags = source:GetFont()
    if path and size then overlay:SetFont(path, size, flags) end
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
        local registry = source._msufA3SpellIndicatorNameOverlays
        if not registry then
            registry = {}
            source._msufA3SpellIndicatorNameOverlays = registry
        end
        registry[overlay] = true
        overlay._msufA3NameRegistry = registry
        if hooksecurefunc and source._msufA3SpellIndicatorNameHooked ~= true then
            local function SyncRegisteredNameOverlays()
                local value = source:GetText()
                for target in pairs(registry) do target:SetText(value) end
            end
            hooksecurefunc(source, "SetText", SyncRegisteredNameOverlays)
            hooksecurefunc(source, "SetFormattedText", SyncRegisteredNameOverlays)
            source._msufA3SpellIndicatorNameHooked = true
        end
    end
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
        root:Hide()
    end
    UnregisterNameOverlay(button)
end

local function HideButtonIconEffect(button)
    if not button then return end
    local root = button._msufA3SpellIndicatorIconEffectRoot
    if root then
        StopAnimatedGlow(root)
        root:Hide()
    end
end

function Runtime.HideFrameEffects(parentFrame)
    if not parentFrame then return end
    local buttons = parentFrame._msufA3SpellIndicatorEffectButtons
    if buttons then
        for button in pairs(buttons) do HideButtonFrameEffect(button) end
    end
    parentFrame._msufA3SpellIndicatorEffectButtons = nil
    -- Clean up objects created by the pre-native implementation, if a profile
    -- was hot-reloaded from an older build in the same session.
    if parentFrame._msufA3SpellIndicatorEffectRoot then parentFrame._msufA3SpellIndicatorEffectRoot:Hide() end
end

function Runtime.HideIconEffects(parentFrame)
    if not parentFrame then return end
    local buttons = parentFrame._msufA3SpellIndicatorIconEffectButtons
    if buttons then
        for button in pairs(buttons) do HideButtonIconEffect(button) end
    end
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

local function LayoutEdges(button, parentFrame, effect)
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
        if edge.SetBlendMode then edge:SetBlendMode(effect and (effect.type == "glow" or effect.type == "pulse") and "ADD" or "BLEND") end
        edge:SetVertexColor(r, g, b, a)
        edge:Show()
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
    StopAnimatedGlow(button and button._msufA3SpellIndicatorEffectRoot)
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

    local root = EnsureEffectRoot(button, parentFrame)
    if not root then return false end
    root:ClearAllPoints()
    root:SetAllPoints(parentFrame)
    SyncFrameStrata(root, ResolveFrameStrata(parentFrame, effect.strata or slot.strata))
    if root.SetFrameLevel then
        -- Saved priorities use 1 as the strongest effect.
        local priority = Round(ClampNumber(effect.priority, 5, 1, 10))
        root:SetFrameLevel((parentFrame:GetFrameLevel() or 0) + 24 + (11 - priority))
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
        local target = SpellIndicatorTargetFrame(parentFrame) or parentFrame
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
        StartAnimatedGlow(root, r, g, b, a, ClampNumber(effect.thickness, 3, 1, 16) + 2)
    else
        LayoutEdges(button, parentFrame, effect)
        if kind == "pulse" then StartPulse(root) end
    end

    parentFrame._msufA3SpellIndicatorEffectButtons = parentFrame._msufA3SpellIndicatorEffectButtons or {}
    parentFrame._msufA3SpellIndicatorEffectButtons[button] = true
    root:Show()
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

    local root = button._msufA3SpellIndicatorIconEffectRoot
    if not root then
        root = CreateFrame("Frame", nil, button)
        root:EnableMouse(false)
        button._msufA3SpellIndicatorIconEffectRoot = root
    end
    root:ClearAllPoints()
    root:SetAllPoints(button)
    SyncFrameStrata(root, ResolveFrameStrata(parentFrame, slot.strata))
    if root.SetFrameLevel then root:SetFrameLevel((button:GetFrameLevel() or 0) + 4) end
    local color = slot.color or {}
    local size = ClampNumber(slot.size, 18, 1, 128)
    StartAnimatedGlow(root,
        Clamp01(color[1], 1), Clamp01(color[2], 1), Clamp01(color[3], 1), Clamp01(color[4], 1),
        math_max(2, size * 0.15))
    parentFrame._msufA3SpellIndicatorIconEffectButtons = parentFrame._msufA3SpellIndicatorIconEffectButtons or {}
    parentFrame._msufA3SpellIndicatorIconEffectButtons[button] = true
    root:Show()
    return true
end

function Runtime.RefreshFrameEffects(parentFrame)
    -- Visibility is now inherited by per-slot child frames. Refreshing needs no
    -- aura scan and, critically, never reads AuraSlot:IsShown().
    return parentFrame ~= nil
end

function Runtime.ReleaseContainerEffects(container, parentFrame)
    if not container then return end
    parentFrame = parentFrame or container._msufA3ParentFrame
    local buttons = parentFrame and parentFrame._msufA3SpellIndicatorEffectButtons
    local iconButtons = parentFrame and parentFrame._msufA3SpellIndicatorIconEffectButtons
    for i = 1, (container.createdButtons or 0) do
        local button = container[i]
        if button then
            HideButtonFrameEffect(button)
            HideButtonIconEffect(button)
            if buttons then buttons[button] = nil end
            if iconButtons then iconButtons[button] = nil end
        end
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
    SyncFrameStrata(frame, ResolveFrameStrata(parentFrame, slot.strata))
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
    local level = (parentFrame:GetFrameLevel() or 0) + (slot.layer or 9)
    if button.SetFrameLevel and button._msufA3GeomLevel ~= level then
        button._msufA3GeomLevel = level
        button:SetFrameLevel(level)
    end
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
        -- AuraSlot visibility is secret-backed. Effect-only slots therefore
        -- keep alpha at one and hide only their icon regions; descendant
        -- full-frame effects inherit the native secret visibility directly.
        button:SetAlpha(1)
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
    ApplyButtonFrameEffect(button, slot, parentFrame)
    SyncMissingFrame(parentFrame, slot, button)
    if button.EnableMouse then button:EnableMouse(false) end
    button:SetMouseMotionEnabled(false)
    return true
end

local function SlotOptions(container, slot, buttonIndex)
    return {
        maxFrameCount = 1,
        candidateFilters = slot.candidateFilters,
        initializeFrame = function(button)
            container[buttonIndex] = button
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
    if slots then
        for i = 1, #slots do
            if slots[i] and container[i] then
                PrepareButton(container[i], slots[i], parentFrame, forceGeometry)
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
    if forceGeometry == true then container._msufA3ForceSpellIndicatorGeometry = nil end
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
        container:AddAuraSlot(slot.slotKey, slot.nativeFilter, SlotOptions(container, slot, i))
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
        -- Runtime.SyncGeometry performs the single visual/geometry pass after
        -- every slot has been rebound. Doing it here as well configured each
        -- button twice per refresh and repeated expensive region setters.
    end
    return true
end

function Runtime.Apply(root, slotRoot, parentFrame, forceRecreate)
    if not (root and Runtime.IsRoot(slotRoot)) then return nil end
    local deps = D()
    if not deps.HideContainer then return nil end
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
        if deps.RegisterContainer and not deps.RegisterContainer(current) then return nil end
        if current._msufA3TrackingSignature ~= trackingSignature and type(current.UpdateAllAuras) == "function" then
            current:UpdateAllAuras()
        end
        current._msufA3TrackingSignature = trackingSignature
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        return current
    end
    Runtime.ReleaseContainerEffects(current, parentFrame)
    deps.HideContainer(current)
    root[key] = nil
    current = CreateSlots(root, slotRoot, parentFrame)
    if current then
        current._msufA3TrackingSignature = trackingSignature
        current._msufA3StructuralSignature = structuralSignature
        current._msufA3LayoutSignature = layoutSignature
        root[key] = current
    end
    return current
end
