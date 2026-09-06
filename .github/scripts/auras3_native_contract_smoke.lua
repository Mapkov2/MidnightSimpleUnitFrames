-- Retained Auras3 refactor regression: actual native backend and Rounded renderer.
-- The bounded frame mock is retained from the local growth harness; this file
-- runs independently and does not require ignored QA fixtures. It guards sealed
-- region ownership, thickness, per-visual reaction gates, and owner reuse.
local root = arg and arg[1] or "."

local function Check(value, message)
    if not value then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function Near(actual, expected, message)
    if math.abs((tonumber(actual) or 0) - (tonumber(expected) or 0)) > 0.001 then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function Read(relativePath)
    local file = assert(io.open(root .. "/" .. relativePath, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function Count(text, needle)
    local count, from = 0, 1
    while true do
        local at = text:find(needle, from, true)
        if not at then return count end
        count = count + 1
        from = at + #needle
    end
end

local Frame = {}
Frame.__index = Frame
local nativeButtonAccess = false

local function CheckButtonAccess(frame)
    if nativeButtonAccess then return end
    while frame do
        if frame._ptr5Forbidden then error("PTR 5 forbidden AuraButton descendant access outside Blizzard native code", 3) end
        frame = frame.parent
    end
end

function Frame:GetParent() return self.parent end
function Frame:SetParent(parent) self.parent = parent end
function Frame:ClearAllPoints()
    CheckButtonAccess(self)
    self.clearAllPointsCalls = (self.clearAllPointsCalls or 0) + 1
    self.point = nil
    self.points = {}
    self.allPoints = nil
end
function Frame:SetPoint(point, relativeTo, relativePoint, x, y)
    CheckButtonAccess(self)
    self.setPointCalls = (self.setPointCalls or 0) + 1
    self.point = { point, relativeTo, relativePoint, x or 0, y or 0 }
    self.points = self.points or {}
    self.points[#self.points + 1] = self.point
end
function Frame:SetAllPoints(relativeTo)
    CheckButtonAccess(self)
    self.allPoints = relativeTo or self.parent or true
    self.points = {}
end
function Frame:SetSize(width, height) CheckButtonAccess(self); self.width, self.height = width, height end
function Frame:SetWidth(width) CheckButtonAccess(self); self.width = width end
function Frame:SetHeight(height) CheckButtonAccess(self); self.height = height end
function Frame:GetWidth() return self.width or 0 end
function Frame:GetHeight() return self.height or 0 end
function Frame:SetAlpha(alpha) CheckButtonAccess(self); self.alpha = alpha end
function Frame:GetAlpha() return self.alpha or 1 end
function Frame:SetAlphaFromBoolean(value, trueAlpha, falseAlpha)
    self.alphaFromBooleanCalls = (self.alphaFromBooleanCalls or 0) + 1
    self.alphaFromBooleanValue = value
    self.alphaFromBooleanTrue = trueAlpha
    self.alphaFromBooleanFalse = falseAlpha
    if type(value) == "boolean" then self.alpha = value and trueAlpha or falseAlpha end
end
function Frame:SetFrameLevel(level) CheckButtonAccess(self); self.frameLevel = level end
function Frame:GetFrameLevel() return self.frameLevel or 0 end
function Frame:SetFrameStrata(strata) CheckButtonAccess(self); self.frameStrata = strata end
function Frame:GetFrameStrata() return self.frameStrata or "MEDIUM" end
function Frame:SetScale(scale) self.scale = scale end
function Frame:GetEffectiveScale() return self.scale or 1 end
function Frame:SetClampedToScreen(value) self.clampedToScreen = value end
function Frame:SetMovable(value) self.movable = value end
function Frame:EnableMouse(value) self.mouseEnabled = value end
function Frame:SetMouseClickEnabled(value) self.mouseClickEnabled = value end
function Frame:SetMouseMotionEnabled(value) self.mouseMotionEnabled = value end
function Frame:RegisterForClicks(...) self.registeredClicks = { ... } end
function Frame:RegisterForDrag(...) self.registeredDrag = { ... } end
function Frame:SetOnUpdateMode(value) self.onUpdateMode = value end
function Frame:Raise() self.raiseCalls = (self.raiseCalls or 0) + 1 end
function Frame:Show()
    local changed = self.shown == false
    self.shown = true
    if changed and self.hooks and self.hooks.OnShow then self.hooks.OnShow(self) end
end
function Frame:Hide()
    local changed = self.shown ~= false
    self.shown = false
    if changed and self.hooks and self.hooks.OnHide then self.hooks.OnHide(self) end
end
function Frame:IsShown() return self.shown ~= false end
function Frame:IsVisible()
    if self.shown == false or self.alpha == 0 then return false end
    local parent = self.parent
    return not parent or not parent.IsVisible or parent:IsVisible()
end
function Frame:SetShown(shown)
    if shown then self:Show() else self:Hide() end
end
function Frame:SetScript(name, callback)
    self.scripts = self.scripts or {}
    self.scripts[name] = callback
end
function Frame:GetScript(name) return self.scripts and self.scripts[name] end
function Frame:HookScript(name, callback)
    if self._secretScriptRestricted == true then
        error("Cannot assign script handler for '" .. tostring(name) .. "' (blocked by secret aspects)", 2)
    end
    self.hooks = self.hooks or {}
    self.hooks[name] = callback
end
function Frame:RegisterEvent(event)
    self.registerEventCalls = (self.registerEventCalls or 0) + 1
    self.events = self.events or {}
    self.events[event] = true
end
function Frame:RegisterUnitEvent(event, unit)
    self.events = self.events or {}
    self.events[event] = unit
end
function Frame:UnregisterEvent(event)
    self.unregisteredEvents = self.unregisteredEvents or {}
    self.unregisteredEvents[event] = (self.unregisteredEvents[event] or 0) + 1
    if self.events then self.events[event] = nil end
end
function Frame:UnregisterAllEvents()
    self.unregisterAllEventsCalls = (self.unregisterAllEventsCalls or 0) + 1
    self.events = {}
end
function Frame:CreateTexture(_, layer, _, sublevel)
    return setmetatable({
        parent = self,
        shown = true,
        regionType = "Texture",
        drawLayer = layer or "ARTWORK",
        drawSublevel = tonumber(sublevel) or 0,
    }, Frame)
end
function Frame:CreateMaskTexture(_, layer)
    return setmetatable({ parent = self, shown = true, drawLayer = layer, isMask = true }, Frame)
end
function Frame:CreateFontString()
    return setmetatable({ parent = self, shown = true }, Frame)
end

-- Region/frame methods touched by the deliberately minimal aura-button style.
function Frame:SetTexture(texture) CheckButtonAccess(self); self.texture = texture end
function Frame:SetTextureSliceMargins(...) CheckButtonAccess(self); self.sliceMargins = {...} end
function Frame:SetTextureSliceMode(mode) CheckButtonAccess(self); self.sliceMode = mode end
function Frame:SetAtlas(atlas) self.atlas = atlas end
function Frame:AddMaskTexture(mask) self.maskTexture = mask end
function Frame:RemoveMaskTexture(mask)
    if self.maskTexture == mask then self.maskTexture = nil end
end
function Frame:SetTexCoord(...) self.texCoord = { ... } end
function Frame:SetColorTexture(...) self.colorTexture = { ... } end
function Frame:SetVertexColor(...) self.vertexColor = { ... } end
function Frame:SetBlendMode() end
function Frame:SetDrawLayer(layer, sublevel) self.drawLayer, self.drawSublevel = layer, sublevel end
function Frame:GetDrawLayer() return self.drawLayer or "ARTWORK", tonumber(self.drawSublevel) or 0 end
function Frame:IsRectValid()
    local anchored = self.allPoints ~= nil or (self.points and #self.points > 0)
    return anchored and self:GetWidth() > 0 and self:GetHeight() > 0
end
function Frame:SetBackdrop(value) self.backdrop = value end
function Frame:SetBackdropColor(...) self.backdropColor = { ... } end
function Frame:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end
function Frame:SetFont(...) self.font = { ... } end
function Frame:SetTextColor() end
function Frame:SetShadowOffset() end
function Frame:SetJustifyH(value) self.justifyH = value end
function Frame:SetJustifyV(value) self.justifyV = value end
function Frame:SetText(value) self.text = value end
function Frame:SetStatusBarTexture(texture) self.statusBarTexturePath = texture end
function Frame:GetStatusBarTexture() return self.statusBarTexture end
function Frame:SetStatusBarColor(...) self.statusBarColor = { ... } end
function Frame:SetMinMaxValues(...) self.minMaxValues = { ... } end
function Frame:SetValue(value) self.statusBarValue = value end
function Frame:SetDrawSwipe() end
function Frame:SetSwipeColor() end
function Frame:SetHideCountdownNumbers() end
function Frame:SetDrawBling() end
function Frame:SetDrawEdge() end
function Frame:SetReverse() end
function Frame:SetReverseFill(value) self.reverseFill = value and true or false end

local nextFrameID = 0
local function NewFrame(parent)
    nextFrameID = nextFrameID + 1
    return setmetatable({ parent = parent, shown = true, frameLevel = 17, frameStrata = "MEDIUM", traceID = nextFrameID }, Frame)
end

local function NewHealthBar(parent)
    local bar = NewFrame(parent)
    local fill = NewFrame(bar)
    bar.statusBarTexture = fill
    return bar, fill
end

local AURA_BUTTON_BINDINGS = {
    "SetIcon", "ClearIcon",
    "SetDurationCooldown", "ClearDurationCooldown",
    "SetDurationBar", "ClearDurationBar",
    "SetDurationText", "ClearDurationText",
    "SetApplicationCount", "ClearApplicationCount",
    -- PTR 7 dispel display names (SetAuraBorder/SetAuraSymbol aliases are
    -- deprecated and no longer called by the runtime).
    "AddDispelTypeTexture", "ClearDispelTypeTextures",
    "SetDispelTypeText", "ClearDispelTypeText",
    "SetMouseMotionEnabled", "SetCancelAuraButtons",
    "SetTooltipAnchorPoint", "SetHideTooltipInCombat",
}

local function NewAuraButton(parent)
    local button = NewFrame(parent)
    button._secretScriptRestricted = true
    button._bindingCalls = 0
    button._bindingByName = {}
    button._bindingValueByName = {}
    button._bindingOptionsByName = {}
    for i = 1, #AURA_BUTTON_BINDINGS do
        local methodName = AURA_BUTTON_BINDINGS[i]
        button[methodName] = function(self, value, options)
            self._bindingCalls = self._bindingCalls + 1
            self._bindingByName[methodName] = (self._bindingByName[methodName] or 0) + 1
            self._bindingValueByName[methodName] = value
            self._bindingOptionsByName[methodName] = options
            if methodName == "AddDispelTypeTexture" then
                self._boundDispelTextures = self._boundDispelTextures or {}
                self._boundDispelTextures[#self._boundDispelTextures + 1] = { region = value, options = options }
                local ancestor = value.parent
                while ancestor and ancestor ~= self do ancestor = ancestor.parent end
                Check(ancestor == self, "native texture belongs to a foreign AuraButton")
                value._ptr5Forbidden = true
            elseif methodName == "ClearDispelTypeTextures" then
                self._boundDispelTextures = {}
            end
            if methodName == "SetMouseMotionEnabled" then self.mouseMotionEnabled = value end
            if methodName == "SetCancelAuraButtons" then self.cancelAuraButtons = value end
        end
    end
    return button
end

local function NativeAuraApplyLayout(self)
    nativeButtonAccess = true
    self.nativeApplyLayoutCalls = (self.nativeApplyLayoutCalls or 0) + 1
    local frames, options = {}, {}
    local priorityKeys = self._msufA3PriorityGroupKeys
    if priorityKeys then
        for index = 1, #priorityKeys do
            local groupKey = priorityKeys[index]
            local group = self.groups[groupKey]
            local groupFrames = group and group:GetFramesByIndex() or {}
            if #groupFrames > 0 then
                options = self.groupLayouts[groupKey] or options
                for frameIndex = 1, #groupFrames do frames[#frames + 1] = groupFrames[frameIndex] end
            end
        end
        if #priorityKeys > 0 and next(options) == nil then
            options = self.groupLayouts[priorityKeys[1]] or {}
        end
    else
        local groupKey = self._msufA3ManagedGroupKey
        local group = groupKey and self.groups[groupKey]
        if not group then nativeButtonAccess = false; return end
        frames = group:GetFramesByIndex()
        options = self.groupLayouts[groupKey] or {}
    end
    local size = options.elementWidth or 10
    local spacing = priorityKeys and (options.groupSpacing or 0) or (options.elementSpacing or 0)
    local step = size + spacing
    local rowWidth = self.auraLayoutRowWidth or size
    local perRow = math.max(1, math.floor(((rowWidth + spacing) / math.max(step, 1)) + 0.0001))
    local anchor = self.auraLayoutAnchorPoint or "TOPLEFT"
    local xSign = self.auraLayoutHorizontalDirection or 1
    local ySign = self.auraLayoutVerticalDirection or -1
    for index = 1, #frames do
        local n = index - 1
        local col = n % perRow
        local row = math.floor(n / perRow)
        local button = frames[index]
        button:ClearAllPoints()
        button:SetPoint(anchor, self, anchor, col * step * xSign, row * step * ySign)
    end
    -- Match Blizzard_CustomAuraContainerMixin:OnLayoutComplete: the native
    -- layout shrinks the live container to the currently assigned frames.
    -- MSUF's wrapper must restore the full configured lane bounds afterwards,
    -- otherwise the selected outer anchor moves as aura count changes.
    local count = #frames
    local cols = count > 0 and math.min(count, perRow) or 1
    local rows = count > 0 and math.floor((count + perRow - 1) / perRow) or 1
    self:SetSize(
        math.max(1, cols * size + math.max(cols - 1, 0) * spacing),
        math.max(1, rows * size + math.max(rows - 1, 0) * spacing)
    )
    nativeButtonAccess = false
end

local createdAuraContainers = {}

local function NewAuraContainer(parent)
    local container = NewFrame(parent)
    container.groups = {}
    container.groupLayouts = {}
    container.layoutSetterCalls = { anchor = 0, growth = 0, width = 0 }
    container.ApplyLayout = NativeAuraApplyLayout
    -- Blizzard's intrinsic AuraContainer OnLoad registers this static event.
    container:RegisterEvent("AURA_DATA_PROVIDER_SWITCH")
    createdAuraContainers[#createdAuraContainers + 1] = container
    return container
end

function Frame:SetUnit(unit) self.configuredUnit = unit end
function Frame:GetUnit() return self.configuredUnit end
function Frame:SetEnabled(enabled) self.enabled = enabled end
function Frame:AddAuraGroup(groupKey, filter, options)
    local group = { frames = {} }
    function group:GetFramesByIndex() return self.frames end
    self.groups[groupKey] = group
    self.groupFilters = self.groupFilters or {}
    self.groupFilters[groupKey] = filter
    self.addAuraGroupCalls = (self.addAuraGroupCalls or 0) + 1
    self.groupOptions = self.groupOptions or {}
    self.groupOptions[groupKey] = options
    for index = 1, (options.maxFrameCount or 0) do
        local button = NewAuraButton(self)
        group.frames[index] = button
        options.initializeFrame(button)
        button._ptr5Forbidden = true
    end
end
function Frame:GetAuraGroup(groupKey)
    self.getAuraGroupCalls = (self.getAuraGroupCalls or 0) + 1
    return self.groups and self.groups[groupKey]
end
function Frame:GetAuraGroupFrame(groupKey, index)
    local group = self.groups and self.groups[groupKey]
    return group and group.frames[index]
end
function Frame:GetAuraGroupFrameCount(groupKey)
    local group = self.groups and self.groups[groupKey]
    return group and #group.frames or 0
end
function Frame:SetAuraGroupLayout(groupKey, options) self.groupLayouts[groupKey] = options end
function Frame:SetAuraGroupFilterString(groupKey, filter)
    self.groupFilterStrings = self.groupFilterStrings or {}
    self.groupFilterStrings[groupKey] = filter
    self.groupFilterSetterCalls = (self.groupFilterSetterCalls or 0) + 1
    self.groupFilters[groupKey] = filter
    self:UpdateAllAuras()
end
function Frame:SetAuraGroupMaxFrameCount(groupKey, maxFrameCount)
    self.groupMaxFrameCounts = self.groupMaxFrameCounts or {}
    self.groupMaxFrameCounts[groupKey] = maxFrameCount
    self.groupMaxSetterCalls = (self.groupMaxSetterCalls or 0) + 1
end
function Frame:SetAuraGroupCandidateFilters() end
function Frame:SetAuraGroupSortMethod() end
function Frame:AddAuraSlot(slotKey, filter, options)
    self.auraSlotOptions = self.auraSlotOptions or {}
    self.auraSlotOptions[slotKey] = { filter = filter, options = options }
    if options and options.initializeFrame then
        local button = NewAuraButton(self)
        self.auraSlotButtons = self.auraSlotButtons or {}
        self.auraSlotButtons[slotKey] = button
        options.initializeFrame(button)
        button._ptr5Forbidden = true
    end
end
function Frame:SetAuraSlotCandidateFilters(slotKey, candidateFilters)
    self.slotCandidateFilters = self.slotCandidateFilters or {}
    self.slotCandidateFilters[slotKey] = candidateFilters
    self.slotCandidateSetterCalls = (self.slotCandidateSetterCalls or 0) + 1
end
function Frame:SetAuraSlotSortMethod(slotKey, sortMethod, sortDirection)
    self.slotSortMethods = self.slotSortMethods or {}
    self.slotSortMethods[slotKey] = { sortMethod, sortDirection }
    self.slotSortSetterCalls = (self.slotSortSetterCalls or 0) + 1
end
function Frame:SetAuraSlotFilterString(slotKey, filter)
    self.slotFilterStrings = self.slotFilterStrings or {}
    self.slotFilterStrings[slotKey] = filter
    self.slotFilterSetterCalls = (self.slotFilterSetterCalls or 0) + 1
    self.auraSlotOptions[slotKey].filter = filter
    self:UpdateAllAuras()
end
local temporaryEnchantDurationSeconds
function Frame:AddItemEnchantment(slot)
    self.addItemEnchantmentCalls = (self.addItemEnchantmentCalls or 0) + 1
    self.itemEnchantmentDurationSnapshots = self.itemEnchantmentDurationSnapshots or {}
    self.itemEnchantmentDurationSnapshots[slot] = temporaryEnchantDurationSeconds
end
function Frame:UpdateAllAuras() self.updateAllAurasCalls = (self.updateAllAurasCalls or 0) + 1 end
-- PTR 7 (12.1) container flow layout API; the legacy SetAuraLayout* setters
-- were removed from the client and from the runtime.
function Frame:SetFlowLayoutAnchorPoint(anchor)
    self.layoutSetterCalls.anchor = self.layoutSetterCalls.anchor + 1
    self.auraLayoutAnchorPoint = anchor
end
function Frame:SetFlowLayoutGrowthDirection(horizontalDirection, verticalDirection)
    self.layoutSetterCalls.growth = self.layoutSetterCalls.growth + 1
    self.auraLayoutHorizontalDirection = horizontalDirection
    self.auraLayoutVerticalDirection = verticalDirection
end
function Frame:SetFlowLayoutMaximumLineSize(width)
    self.layoutSetterCalls.width = self.layoutSetterCalls.width + 1
    self.auraLayoutRowWidth = width
end
-- Mirror the live AnchorUtil.FlowDirection / FlowLayoutAxis enums so the
-- runtime's enum mapping is exercised (values are the same +/-1 signs).
_G.AnchorUtil = _G.AnchorUtil or {
    FlowDirection = { Left = -1, Right = 1, Up = 1, Down = -1 },
    FlowLayoutAxis = { Horizontal = 0, Vertical = 1 },
}
-- PTR 7 dispel texture style enum: the runtime must route sensors through
-- PreserveAsset (keep MSUF art, color only) and lane borders through
-- Border/BorderWithIcon. Values are arbitrary; MSUF resolves by name.
_G.Enum = _G.Enum or {}
_G.Enum.CustomAuraButtonDispelTypeTextureStyle = _G.Enum.CustomAuraButtonDispelTypeTextureStyle or {
    Border = 0, BorderWithIcon = 1, Icon = 2, PreserveAsset = 3, CustomAsset = 4,
}
_G.Enum.StatusBarInterpolation = _G.Enum.StatusBarInterpolation or {
    Immediate = 31, ExponentialEaseOut = 34,
}
_G.Enum.StatusBarTimerDirection = _G.Enum.StatusBarTimerDirection or {
    ElapsedTime = 32, RemainingTime = 33,
}

local createdPlainFrames = {}
_G.CreateFrame = function(frameType, _, parent)
    if frameType == "AuraContainer" then return NewAuraContainer(parent) end
    local frame = NewFrame(parent)
    createdPlainFrames[#createdPlainFrames + 1] = frame
    return frame
end
_G.C_AddOns = {
    IsAddOnLoaded = function(name) return name == "Blizzard_AuraContainer" end,
}
_G.C_Timer = {
    After = function(_, callback) callback() end,
    NewTimer = function(_, callback) callback(); return { Cancel = function() end } end,
}
_G.InCombatLockdown = function() return false end
_G.issecretvalue = function() return false end
_G.UnitExists = function() return true end
local auraAliasSpellNames = {}
local activeAuraAliases = {}
_G.C_Spell = {
    GetSpellName = function(spellID) return auraAliasSpellNames[spellID] end,
}
_G.C_UnitAuras = {
    GetAuraDataBySpellName = function(unit, name, filter)
        local aura = activeAuraAliases[name]
        if aura and aura.unit == unit and aura.filter == filter then return aura end
    end,
}
local unitCanAssistState = {}
local unitCanAssistCalls = {}
local unitGUIDState = {}
_G.UnitCanAssist = function(source, unit)
    Equal(source, "player", "Aura identity eligibility observer")
    unitCanAssistCalls[unit] = (unitCanAssistCalls[unit] or 0) + 1
    return unitCanAssistState[unit] ~= false
end
_G.UnitGUID = function(unit)
    return unitGUIDState[unit] or ("GUID:" .. tostring(unit))
end
_G.UnitOnTaxi = function() return false end
_G.UnitInRange = function()
    error("Auras3 must not consult UnitInRange for identity-filter eligibility", 2)
end
_G.AuraContainerSortMethod = { Default = 0, Expiration = 1, Name = 2 }
_G.AuraContainerSortDirection = { Normal = 0, Reverse = 1 }
local durationFormatterCreateCalls = 0
_G.C_StringUtil = {
    CreateNumericRuleFormatter = function()
        durationFormatterCreateCalls = durationFormatterCreateCalls + 1
        return { AddBreakpoint = function() end }
    end,
}
_G.MSUF_FRAME_STRATA_RANK = {
    BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
    FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}

local registeredElements = {}
local MSUF = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
    UF = {
        Config = { serial = 1 },
        elements = {},
        RegisterElement = function(name, element) registeredElements[name] = element end,
    },
}
_G.MSUF_NS = MSUF

-- Capture only deterministic native operations; no timestamps or table addresses.
-- A frozen baseline can replay the exact same fixture through the test driver.
local nativeOperations, ownerOperations = {}, {}
for _, method in ipairs({ "CreateTexture", "CreateMaskTexture", "CreateFontString" }) do
    local original = assert(Frame[method])
    Frame[method] = function(self, ...)
        local region = original(self, ...)
        nextFrameID = nextFrameID + 1
        region.traceID = nextFrameID
        return region
    end
end
local function RecordOperation(ownerID, method, ...)
    local values = { method }
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        values[#values + 1] = type(value) == "table" and "<table>" or tostring(value)
    end
    local operation = table.concat(values, "|")
    nativeOperations[#nativeOperations + 1] = operation
    local owner = ownerOperations[ownerID]
    if not owner then owner = {}; ownerOperations[ownerID] = owner end
    owner[#owner + 1] = operation
end
for _, method in ipairs({ "RegisterEvent", "RegisterUnitEvent", "UnregisterEvent",
    "SetUnit", "SetEnabled", "AddAuraGroup", "AddAuraSlot", "UpdateAllAuras",
    "SetAuraGroupFilterString", "SetAuraSlotFilterString", "SetAuraSlotCandidateFilters",
    "SetAuraGroupCandidateFilters", "SetPoint", "SetAllPoints", "SetSize" }) do
    local original = assert(Frame[method], "fixture missing operation " .. method)
    Frame[method] = function(self, ...)
        RecordOperation(self.traceID, method, ...)
        return original(self, ...)
    end
end
local createFrame = _G.CreateFrame
_G.CreateFrame = function(kind, ...)
    RecordOperation(0, "CreateFrame", kind)
    return createFrame(kind, ...)
end

local layersChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Layers.lua"))
layersChunk("MidnightSimpleUnitFrames", MSUF)
-- Shared border-style catalog/renderer: the aura icon style draws its border
-- and shadow bands through it.
local borderStylesChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Runtime/MSUF_BorderStyles.lua"))
borderStylesChunk("MidnightSimpleUnitFrames", MSUF)
local defensiveDataChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_DefensiveData.lua"))
defensiveDataChunk("MidnightSimpleUnitFrames", MSUF)
local aliasLoader = assert(loadfile(root .. "/.github/scripts/auras3_test_loader.lua"))()
aliasLoader.SetSourceRoot(os.getenv("MSUF_AURAS3_TEST_SOURCE_ROOT"))
aliasLoader.LoadAliasCatalog(root, MSUF)
local spellIndicatorChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua"))
spellIndicatorChunk("MidnightSimpleUnitFrames", MSUF)
local backendChunk = assert(loadfile(arg and arg[2] or root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua"))
backendChunk("MidnightSimpleUnitFrames", MSUF)

local A3 = assert(MSUF.MSUF_Auras3)
local AurasElement = assert(registeredElements.Auras)
local SpellIndicators = assert(A3.SpellIndicators)
Check(type(A3.ResolveUnitFrameConfig) == "function", "unit aura compiler missing")
Check(type(A3._ApplyNormalLaneContainers) == "function", "normal lane integration surface missing")
local Layers = assert(MSUF.UF.Layers)
Check(Layers.ElementLevel(0, 0, 10) < Layers.ElementLevel(0, 0, 12),
    "Dispel overlay AUTO level is not above the strongest Spell frame effect")
Check(Layers.ElementLevel(0, 0, 12) < Layers.TextLevel(nil, 5, 5),
    "health effects escaped above the default text layer")
Check(Layers.AURA_DURATION_BAR_LEVEL_OFFSET < Layers.AURA_COOLDOWN_LEVEL_OFFSET
    and Layers.AURA_COOLDOWN_LEVEL_OFFSET < Layers.AURA_TEXT_LEVEL_OFFSET
    and Layers.AURA_TEXT_LEVEL_OFFSET < Layers.ELEMENT_LEVEL_STRIDE,
    "Aura child surfaces are not ordered inside one universal Layer slot")

-- Real native initializer + real Rounded renderer, including the screenshot's
-- thickness 23. Bind-time sealing rejects any later geometry writes to a live
-- region, so thickness changes must retire/recreate rather than mutate it.
do
    local oldDB = _G.MSUF_DB
    _G.MSUF_DB = {
        bars = { roundedFramesEnabled = true, roundedUnitFrames = true, roundedGroupFrames = true },
        auras3 = { enabled = true, showTarget = true, showFocus = true, showBoss = true,
            shared = { showBuffs = false, showDebuffs = false }, perUnit = {} },
    }
    _G.Enum.UITextureSliceMode = { Stretched = 1 }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_RoundedFrames.lua"))("MidnightSimpleUnitFrames", MSUF)
    local startup = assert(MSUF.__msufRoundedEventFrame)
    startup.scripts.OnEvent(startup, "ADDON_LOADED", "MidnightSimpleUnitFrames")
    local cases = 0
    for _, scenario in ipairs({ {"target"}, {"focus"}, {"boss1"}, {"party1", "party"}, {"raid1", "raid"}, {"raid1", "mythicraid"} }) do
        for _, rounded in ipairs({ false, true }) do
            _G.MSUF_DB.bars.roundedFramesEnabled = rounded
            for _, visual in ipairs({ "border", "purge" }) do
                if visual == "border" or scenario[1] == "target" or scenario[1] == "focus" then
                    local frame = NewFrame(nil)
                    frame.unit, frame.MSUFUnitKey = scenario[1], scenario[1]
                    frame.hpBar = NewHealthBar(frame)
                    if scenario[2] then
                        frame._msufIsGroupFrame, frame._msufGFKind = true, scenario[2]
                        frame.barGroup, frame.health = NewFrame(frame), frame.hpBar
                    end
                    frame.MSUFSpec = { auras = { enabled = true, showBuffs = false, showDebuffs = false },
                        border = { dispel = visual == "border", purge = visual == "purge", dispelTrigger = "DISPEL_TYPE" } }
                    local priorOwner
                    for _, thickness in ipairs({ 1, 4, 16, 23, 30, 2 }) do
                        local strength = thickness == 1 and 1 or thickness == 30 and 5 or 3
                        _G.MSUF_DB.bars.roundedCornerStrength = strength
                        frame.MSUFSpec.border.highlightThickness = thickness
                        A3._runtimeConfigGen = (A3._runtimeConfigGen or 1) + 1
                        Check(AurasElement.Enable(frame) == true, "native thickness sensor did not apply")
                        local owner = assert(frame.Auras[scenario[2] and "GroupSlots" or "DispelSensorNeutral"])
                        if priorOwner then
                            Check(owner ~= priorOwner, "thickness change reused frozen native border")
                            Equal(priorOwner.enabled, false, "replaced native border kept parsing auras")
                        end
                        local key = visual == "border" and "msuf_dispelBorder_1" or "msuf_purgeBorder_1"
                        local button = assert(owner.auraSlotButtons[key])
                        local bindings = assert(button._boundDispelTextures)
                        Equal(#bindings, rounded and thickness or 4,
                            scenario[1] .. " " .. visual .. " thickness " .. thickness .. " region count")
                        local slotCount = 0
                        for _ in pairs(owner.auraSlotOptions) do slotCount = slotCount + 1 end
                        Equal(slotCount, 1, "border thickness duplicated native aura selection")
                        local anchor = frame.barGroup or frame
                        for index, binding in ipairs(bindings) do
                            local edge = binding.region
                            Equal(edge._ptr5Forbidden, true, "native border was not sealed at bind time")
                            Equal(edge.parent, button, "native border lost its AuraButton owner")
                            Equal(binding.options.style, _G.Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
                                "native dispel style would replace thickness artwork")
                            if rounded then
                                Equal(edge.points[1][2], anchor, "rounded border body anchor")
                                Equal(edge.points[1][4], -index, "rounded ring inner-to-outer geometry")
                                Equal(edge.points[2][4], index, "rounded ring outer extent")
                                Check(edge.texture:find("rounded_clean_edge_s" .. strength, 1, true), "native rounded strength ignored")
                                Equal(edge.sliceMargins[1], 9.5, "native rounded corner slicing missing")
                            else
                                Equal(index <= 2 and edge.height or edge.width, thickness, "square border thickness ignored")
                                Equal(edge.points[1][2], anchor, "square border body anchor")
                                Equal(math.abs(edge.points[1][4]), thickness, "square border outside extent ignored")
                                Equal(edge.texture, "Interface\\Buttons\\WHITE8X8", "square border retained thin edge art")
                            end
                        end
                        Check(AurasElement.Enable(frame) == true, "unchanged native border did not reapply")
                        Equal(frame.Auras[scenario[2] and "GroupSlots" or "DispelSensorNeutral"], owner,
                            "unchanged native border allocated another owner")
                        Equal(button._bindingByName.AddDispelTypeTexture, #bindings,
                            "unchanged native border rebound frozen textures")
                        priorOwner = owner
                        cases = cases + 1
                    end
                    A3.DisableFrame(frame)
                end
            end
        end
    end
    _G.MSUF_DB = oldDB
    print("PASS native border thickness: " .. cases .. " square/rounded Dispel/Purge cases, 1/4/16/23/30/2, single-slot ownership, frozen recreation and unchanged-owner reuse")
end

-- The real Bars request must refresh native sensors AFTER the unit/group spec
-- refreshes and coalesce repeated slider writes into one scoped native apply.
do
    local oldTimer, oldOutline = _G.C_Timer, _G.MSUF_ApplyBarOutlineThickness_All
    local oldDispelRefresh = _G.MSUF_RefreshUnitDispelOverlays
    local unitReady, groupReady, auraCalls, auraScope
    _G.C_Timer = { NewTimer = function() return { Cancel = function() end } end }
    _G.MSUF_ApplyBarOutlineThickness_All = function() unitReady = true end
    _G.MSUF_RefreshUnitDispelOverlays = function() unitReady = true end
    local expectedScope
    local serviceNS = {
        MSUF2 = { InvokeBoundary = function(fn, ...) return pcall(fn, ...) end },
        GF = { DIRTY_BORDER = 16, RefreshVisuals = function() groupReady = true end },
        MSUF_Auras3 = { MenuModel = { Apply = function(scope)
            local groupOnly = expectedScope == "party" or expectedScope == "raid" or expectedScope == "mythicraid"
            Check(groupOnly or unitReady, "native border applied before the unit spec refresh")
            Check(not (groupOnly or expectedScope == "shared") or groupReady,
                "native border applied before the group spec refresh")
            auraCalls, auraScope = auraCalls + 1, scope
        end } },
    }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ApplyService.lua"))(
        "MidnightSimpleUnitFrames_Options", serviceNS)
    local Apply = serviceNS.MSUF2.ApplyService
    for _, scope in ipairs({ "shared", "target", "focus", "boss", "party", "raid", "mythicraid" }) do
        expectedScope = scope
        unitReady, groupReady, auraCalls, auraScope = false, false, 0, nil
        for _ = 1, 3 do Apply.RequestHighlightBorders("MSUF2_ALL_HIGHLIGHT_BORDER_RUNTIME", scope) end
        Equal(auraCalls, 0, "highlight slider bypassed batching")
        Apply.Flush()
        Equal(auraCalls, 1, scope .. " highlight slider did not refresh native border once")
        Equal(auraScope, scope, "highlight slider refreshed an unrelated native scope")
    end
    _G.C_Timer, _G.MSUF_ApplyBarOutlineThickness_All = oldTimer, oldOutline
    _G.MSUF_RefreshUnitDispelOverlays = oldDispelRefresh
    print("PASS highlight thickness Menu apply: 7 scopes, config-before-native ordering and 3-to-1 coalescing")
end

-- "Show on" partitions only the Dispel border; an enemy-only border must not
-- hide the neutral overlay/symbol/Purge, including GroupSlots consolidation.
do
    local oldDB = _G.MSUF_DB
    _G.MSUF_DB = { bars = {}, auras3 = { enabled = true, showTarget = true,
        showFocus = true, showBoss = true, shared = { showBuffs = false, showDebuffs = false }, perUnit = {} } }
    local ownerKeys = { "DispelSensor", "DispelSensorNeutral", "DispelSensorHostile",
        "GroupSlots", "GroupAuraAssist", "GroupAuraHostile" }
    local function OwnerFor(frame, slot)
        local found
        for _, key in ipairs(ownerKeys) do
            local owner = frame.Auras and frame.Auras[key]
            local ownsSlot = owner and owner.auraSlotButtons and owner.auraSlotButtons[slot]
            -- A fused selection retains the first native key; discover the
            -- overlay by its actual initialized visual, not an extra slot.
            if owner and slot == "msuf_dispelOverlay_1" and owner.auraSlotButtons then
                for _, button in pairs(owner.auraSlotButtons) do
                    for _, binding in ipairs(button._boundDispelTextures or {}) do
                        if binding.region.parent._msufA3DispelSensor == "overlay" then ownsSlot = true end
                    end
                end
            end
            if owner and owner:IsShown() and ownsSlot then
                Check(not found, "Show on duplicated a native sensor slot")
                found = owner
            end
        end
        return found
    end
    local cases = 0
    for _, scenario in ipairs({ {"target"}, {"focus"}, {"boss1"}, {"party1", "party"}, {"raid1", "raid"}, {"raid2", "mythicraid"} }) do
        local unit, kind = scenario[1], scenario[2]
        local frame = NewFrame(nil)
        frame.unit, frame.MSUFUnitKey = unit, unit
        frame.hpBar = NewHealthBar(frame)
        if kind then frame._msufIsGroupFrame, frame._msufGFKind, frame.health = true, kind, frame.hpBar end
        frame.MSUFSpec = {
            auras = { enabled = true, showBuffs = false, showDebuffs = false },
            border = { dispel = true, purge = not kind, dispelTrigger = "DISPEL_TYPE" },
            dispelOverlay = { enabled = true, trigger = "DISPEL_TYPE" },
            group = kind and { dispelOverlayEnabled = true, dispelOverlayTrigger = "DISPEL_TYPE" } or nil,
            dispelSymbol = { enabled = true, trigger = "DISPEL_TYPE" },
        }
        for _, showOn in ipairs({ "BOTH", "FRIENDLY", "ENEMY", "BOTH", "invalid" }) do
            frame.MSUFSpec.border.dispelShowOn = showOn
            unitCanAssistState[unit] = true
            A3._runtimeConfigGen = (A3._runtimeConfigGen or 1) + 1
            Check(AurasElement.Enable(frame) == true, "Show on sensor did not apply")
            local owner = assert(OwnerFor(frame, "msuf_dispelBorder_1"), "Show on lost border owner")
            local overlayOwner = assert(OwnerFor(frame, "msuf_dispelOverlay_1"))
            local symbolOwner = assert(OwnerFor(frame, "msuf_dispelSymbol_1"))
            for _, friendly in ipairs({ true, false, true, false }) do
                unitCanAssistState[unit] = friendly
                if kind then
                    A3._UpdateGroupAuraAssistState(unit)
                else
                    local driver = A3._directIdentityAuraFrame
                    driver.scripts.OnEvent(driver, "UNIT_FACTION", unit)
                    if unit == "target" or unit == "focus" then
                        driver.scripts.OnEvent(driver, unit == "target" and "PLAYER_TARGET_CHANGED" or "PLAYER_FOCUS_CHANGED")
                    end
                end
                local visible = showOn == "FRIENDLY" and friendly
                    or showOn == "ENEMY" and not friendly or showOn ~= "FRIENDLY" and showOn ~= "ENEMY"
                Equal(owner:GetAlpha(), visible and 1 or 0, unit .. " " .. showOn .. " reaction visibility")
                Equal(owner.enabled, kind and true or visible, unit .. " " .. showOn .. " native registration")
                Equal(overlayOwner:GetAlpha(), 1, "border Show on hid Dispel Overlay")
                Equal(symbolOwner:GetAlpha(), 1, "border Show on hid Dispel Symbol")
                local purgeOwner = OwnerFor(frame, "msuf_purgeBorder_1")
                if purgeOwner then Equal(purgeOwner:GetAlpha(), 1, "border Show on hid Purge") end
                cases = cases + 1
            end
            local created = #createdAuraContainers
            AurasElement.Enable(frame)
            Equal(OwnerFor(frame, "msuf_dispelBorder_1"), owner, "unchanged Show on recreated border owner")
            Equal(#createdAuraContainers, created, "unchanged Show on allocated native containers")
        end
        A3.DisableFrame(frame)
        Equal(frame.Auras.DispelSensorHostile, nil, "disabled frame retained hostile border owner")
        unitCanAssistState[unit] = nil
    end
    for _, trigger in ipairs({ "BY_ME", "BY_RAID" }) do
        local spec = { auras = { enabled = true }, border = { dispel = true, dispelTrigger = trigger, dispelShowOn = "ENEMY" } }
        local cfg = assert(A3.ResolveUnitFrameConfig("target", spec))
        Check(not cfg.sensors.dispelBorder, "Enemy filter bypassed friendly cleanse restriction")
        spec.border.dispelShowOn = "BOTH"
        A3._runtimeConfigGen = (A3._runtimeConfigGen or 1) + 1
        cfg = assert(A3.ResolveUnitFrameConfig("target", spec))
        Equal(cfg.sensors.dispelBorder.identityCandidateMode, "assist", "Both changed ability-scoped cleansing")
    end
    _G.MSUF_DB = oldDB
    print("PASS Dispel Show on: " .. cases .. " unit/group reaction cases, owner replacement/reuse, per-visual isolation and unchanged cleanse filters")
end

for _, container in ipairs(createdAuraContainers) do
    Equal(container.events and container.events.AURA_DATA_PROVIDER_SWITCH, true,
        "MSUF modified Blizzard's intrinsic event ownership")
end
Equal(#AurasElement.GetEvents(), 0, "Auras3 added a duplicate UF aura event stream")
local tracePath = os.getenv("MSUF_AURAS3_TEST_TRACE_PATH")
if tracePath and tracePath ~= "" then
    local traceFile = assert(io.open(tracePath, "wb"))
    -- Different tables may iterate in a different order under pairs(). Compare
    -- each native owner's ordered operations; order within an owner is retained.
    for ownerID = 0, nextFrameID do
        local operations = ownerOperations[ownerID]
        if operations then
            traceFile:write("OWNER ", ownerID, "\n", table.concat(operations, "\n"), "\n")
        end
    end
    traceFile:close()
end
print("PASS Auras3 native contracts: " .. #nativeOperations .. " deterministic native operations")
return { A3 = A3, Element = AurasElement, NewFrame = NewFrame, NewHealthBar = NewHealthBar,
    created = createdAuraContainers, unitCanAssistState = unitCanAssistState }
