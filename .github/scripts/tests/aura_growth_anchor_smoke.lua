-- Standalone regression for AuraContainer anchor/growth ownership.
--
-- The selected lane anchor pins the lane bounding box to the unit frame. The
-- growth-derived initialAnchor belongs to Blizzard's internal element flow.
-- Horizontal-first lanes delegate to Blizzard's native layout, then restore the
-- configured full-capacity bounds. Vertical-first UP/DOWN lanes use MSUF's small
-- ApplyLayout fallback because the native flow cannot swap its major axis; both
-- paths keep the outer anchor stable as the active aura count changes.
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

function Frame:GetParent() return self.parent end
function Frame:SetParent(parent) self.parent = parent end
function Frame:ClearAllPoints()
    self.clearAllPointsCalls = (self.clearAllPointsCalls or 0) + 1
    self.point = nil
end
function Frame:SetPoint(point, relativeTo, relativePoint, x, y)
    self.setPointCalls = (self.setPointCalls or 0) + 1
    self.point = { point, relativeTo, relativePoint, x or 0, y or 0 }
end
function Frame:SetAllPoints(relativeTo) self.allPoints = relativeTo or true end
function Frame:SetSize(width, height) self.width, self.height = width, height end
function Frame:SetWidth(width) self.width = width end
function Frame:SetHeight(height) self.height = height end
function Frame:GetWidth() return self.width or 0 end
function Frame:GetHeight() return self.height or 0 end
function Frame:SetAlpha(alpha) self.alpha = alpha end
function Frame:GetAlpha() return self.alpha or 1 end
function Frame:SetFrameLevel(level) self.frameLevel = level end
function Frame:GetFrameLevel() return self.frameLevel or 0 end
function Frame:SetFrameStrata(strata) self.frameStrata = strata end
function Frame:GetFrameStrata() return self.frameStrata or "MEDIUM" end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown ~= false end
function Frame:IsVisible() return self.shown ~= false end
function Frame:SetScript(name, callback)
    self.scripts = self.scripts or {}
    self.scripts[name] = callback
end
function Frame:HookScript(name, callback)
    self.hooks = self.hooks or {}
    self.hooks[name] = callback
end
function Frame:RegisterEvent(event)
    self.events = self.events or {}
    self.events[event] = true
end
function Frame:RegisterUnitEvent(event, unit)
    self.events = self.events or {}
    self.events[event] = unit
end
function Frame:UnregisterEvent(event)
    if self.events then self.events[event] = nil end
end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:CreateTexture()
    return setmetatable({ parent = self, shown = true }, Frame)
end
function Frame:CreateFontString()
    return setmetatable({ parent = self, shown = true }, Frame)
end

-- Region/frame methods touched by the deliberately minimal aura-button style.
function Frame:SetTexture() end
function Frame:SetTexCoord() end
function Frame:SetColorTexture() end
function Frame:SetVertexColor() end
function Frame:SetBlendMode() end
function Frame:SetDrawLayer() end
function Frame:SetFont() end
function Frame:SetTextColor() end
function Frame:SetShadowOffset() end
function Frame:SetJustifyH() end
function Frame:SetJustifyV() end
function Frame:SetText() end
function Frame:SetStatusBarTexture() end
function Frame:SetStatusBarColor() end
function Frame:SetMinMaxValues() end
function Frame:SetValue() end
function Frame:SetDrawSwipe() end
function Frame:SetSwipeColor() end
function Frame:SetHideCountdownNumbers() end
function Frame:SetDrawBling() end
function Frame:SetDrawEdge() end
function Frame:SetReverse() end

local function NewFrame(parent)
    return setmetatable({ parent = parent, shown = true, frameLevel = 17, frameStrata = "MEDIUM" }, Frame)
end

local AURA_BUTTON_BINDINGS = {
    "SetIcon", "ClearIcon",
    "SetDurationCooldown", "ClearDurationCooldown",
    "SetDurationBar", "ClearDurationBar",
    "SetDurationText", "ClearDurationText",
    "SetApplicationCount", "ClearApplicationCount",
    "SetAuraBorder", "ClearAuraBorder",
    "SetAuraSymbol", "ClearAuraSymbol",
    "SetMouseMotionEnabled", "SetCancelAuraButtons",
}

local function NewAuraButton(parent)
    local button = NewFrame(parent)
    button._bindingCalls = 0
    for i = 1, #AURA_BUTTON_BINDINGS do
        local methodName = AURA_BUTTON_BINDINGS[i]
        button[methodName] = function(self)
            self._bindingCalls = self._bindingCalls + 1
        end
    end
    return button
end

local function NativeAuraApplyLayout(self)
    self.nativeApplyLayoutCalls = (self.nativeApplyLayoutCalls or 0) + 1
    local groupKey = self._msufA3ManagedGroupKey
    local group = groupKey and self.groups[groupKey]
    if not group then return end
    local frames = group:GetFramesByIndex()
    local options = self.groupLayouts[groupKey] or {}
    local size = options.elementWidth or 10
    local spacing = options.elementSpacingX or 0
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
end

local function NewAuraContainer(parent)
    local container = NewFrame(parent)
    container.groups = {}
    container.groupLayouts = {}
    container.layoutSetterCalls = { anchor = 0, growth = 0, width = 0 }
    container.ApplyLayout = NativeAuraApplyLayout
    return container
end

function Frame:SetUnit(unit) self.configuredUnit = unit end
function Frame:GetUnit() return self.configuredUnit end
function Frame:SetEnabled(enabled) self.enabled = enabled end
function Frame:AddAuraGroup(groupKey, filter, options)
    local group = { frames = {} }
    function group:GetFramesByIndex() return self.frames end
    self.groups[groupKey] = group
    self.groupOptions = self.groupOptions or {}
    self.groupOptions[groupKey] = options
    for index = 1, (options.maxFrameCount or 0) do
        local button = NewAuraButton(self)
        group.frames[index] = button
        options.initializeFrame(button)
    end
end
function Frame:GetAuraGroup(groupKey)
    self.getAuraGroupCalls = (self.getAuraGroupCalls or 0) + 1
    return self.groups and self.groups[groupKey]
end
function Frame:SetAuraGroupLayout(groupKey, options) self.groupLayouts[groupKey] = options end
function Frame:SetAuraGroupMaxFrameCount(groupKey, maxFrameCount)
    self.maxFrameCountCalls = (self.maxFrameCountCalls or 0) + 1
    self.groupOptions[groupKey].maxFrameCount = maxFrameCount
end
function Frame:SetAuraGroupCandidateFilters() end
function Frame:SetAuraGroupSortMethod() end
function Frame:AddAuraSlot() end
function Frame:SetAuraSlotCandidateFilters() end
function Frame:AddItemEnchantment() end
function Frame:UpdateAllAuras() self.updateAllAurasCalls = (self.updateAllAurasCalls or 0) + 1 end
function Frame:SetAuraLayoutAnchorPoint(anchor)
    self.layoutSetterCalls.anchor = self.layoutSetterCalls.anchor + 1
    self.auraLayoutAnchorPoint = anchor
end
function Frame:SetAuraLayoutGrowthDirection(horizontalDirection, verticalDirection)
    self.layoutSetterCalls.growth = self.layoutSetterCalls.growth + 1
    self.auraLayoutHorizontalDirection = horizontalDirection
    self.auraLayoutVerticalDirection = verticalDirection
end
function Frame:SetAuraLayoutRowWidth(width)
    self.layoutSetterCalls.width = self.layoutSetterCalls.width + 1
    self.auraLayoutRowWidth = width
end

local auraContainerCreations = 0
_G.CreateFrame = function(frameType, _, parent)
    if frameType == "AuraContainer" then
        auraContainerCreations = auraContainerCreations + 1
        return NewAuraContainer(parent)
    end
    return NewFrame(parent)
end
_G.C_AddOns = {
    IsAddOnLoaded = function(name) return name == "Blizzard_AuraContainer" end,
}
_G.C_Timer = {
    After = function(_, callback) callback() end,
    NewTimer = function(_, callback) callback(); return { Cancel = function() end } end,
}
local inCombat = false
_G.InCombatLockdown = function() return inCombat end
_G.issecretvalue = function() return false end
_G.UnitExists = function() return true end
_G.AuraContainerSortMethod = { Default = 0, Expiration = 1, Name = 2 }
_G.AuraContainerSortDirection = { Normal = 0, Reverse = 1 }

local registeredElements = {}
local MSUF = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
    UF = {
        Config = { serial = 1 },
        RegisterElement = function(name, element) registeredElements[name] = element end,
    },
}
_G.MSUF_NS = MSUF

local backendChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua"))
backendChunk("MidnightSimpleUnitFrames", MSUF)

local A3 = assert(MSUF.MSUF_Auras3)
local AurasElement = assert(registeredElements.Auras)
Check(type(A3.ResolveUnitFrameConfig) == "function", "unit aura compiler missing")
Check(type(A3._ApplyNormalLaneContainers) == "function", "normal lane integration surface missing")
Check(type(A3._ApplySharedAuraContainer) == "function", "shared aura integration surface missing")
Check(type(A3._ShouldUseSharedAuraContainer) == "function", "adaptive shared aura selector missing")

local ANCHORS = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}
local GROWTHS = {
    RIGHTDOWN = { x = 1, y = -1, initial = "TOPLEFT", vertical = false },
    LEFTDOWN = { x = -1, y = -1, initial = "TOPRIGHT", vertical = false },
    RIGHTUP = { x = 1, y = 1, initial = "BOTTOMLEFT", vertical = false },
    LEFTUP = { x = -1, y = 1, initial = "BOTTOMRIGHT", vertical = false },
    UP = { x = 1, y = 1, initial = "BOTTOMLEFT", vertical = true },
    DOWN = { x = 1, y = -1, initial = "TOPLEFT", vertical = true },
}
local GROWTH_ORDER = { "RIGHTDOWN", "LEFTDOWN", "RIGHTUP", "LEFTUP", "UP", "DOWN" }

local function UnitLane(anchor, growth)
    _G.MSUF_DB = {
        auras3 = {
            enabled = true,
            showPlayer = true,
            shared = {
                showBuffs = true,
                showDebuffs = false,
                maxBuffs = 6,
                buffPerRow = 3,
                buffGroupIconSize = 10,
                spacing = 2,
                buffAnchor = anchor,
                buffGroupOffsetX = 7,
                buffGroupOffsetY = -5,
                buffGrowthX = growth,
                buffGrowthY = "DOWN",
                buffShowCooldownSwipe = false,
                buffShowDurationBar = false,
                buffShowCooldownText = false,
                buffShowStackCount = false,
                buffShowTooltip = false,
            },
        },
    }
    A3._runtimeConfigGen = (A3._runtimeConfigGen or 1) + 1
    local cfg = assert(A3.ResolveUnitFrameConfig("player", {}))
    local lane = assert(cfg.lanes and cfg.lanes.buff)
    Check(lane.enabled == true, "compiled unit buff lane disabled")
    return lane
end

local function ApplyLane(lane)
    local parent = NewFrame(nil)
    local auraRoot = NewFrame(parent)
    local lanes = {}
    lanes[lane.kind] = lane
    local ok, any = A3._ApplyNormalLaneContainers(auraRoot, lanes, parent, false)
    Check(ok == true and any == true, "normal aura lane integration failed")
    return assert(auraRoot[lane.rootKey]), auraRoot, parent
end

local function AssertPoint(frame, point, relativeTo, relativePoint, x, y, label)
    local actual = frame and frame.point
    Check(type(actual) == "table", label .. " has no point")
    Equal(actual[1], point, label .. " point")
    Equal(actual[2], relativeTo, label .. " relative frame")
    Equal(actual[3], relativePoint, label .. " relative point")
    Near(actual[4], x, label .. " x")
    Near(actual[5], y, label .. " y")
end

local function AssertLayoutSetters(container, expected, label)
    Check(container.layoutSetterCalls.anchor >= 1, label .. " did not configure native layout anchor")
    Check(container.layoutSetterCalls.growth >= 1, label .. " did not configure native growth")
    Check(container.layoutSetterCalls.width >= 1, label .. " did not configure native row width")
    Equal(container.auraLayoutAnchorPoint, expected.initial, label .. " native anchor")
    Equal(container.auraLayoutHorizontalDirection, expected.x, label .. " native horizontal growth")
    Equal(container.auraLayoutVerticalDirection, expected.y, label .. " native vertical growth")
    -- Horizontal native flow wraps after three 10px icons plus two 2px gaps.
    -- Vertical lanes are column-major in the fallback; their compiled bounding
    -- box width (two icons plus one gap) is still the harmless native value.
    Near(container.auraLayoutRowWidth, expected.vertical and 22 or 34, label .. " native row width")
end

local function AssertGrid(frames, container, expected, label)
    local step = 12
    local expectedOffsets
    if expected.vertical then
        expectedOffsets = { { 0, 0 }, { 0, step * expected.y }, { 0, 2 * step * expected.y }, { step, 0 } }
    else
        expectedOffsets = { { 0, 0 }, { step * expected.x, 0 }, { 2 * step * expected.x, 0 }, { 0, step * expected.y } }
    end
    for index = 1, #expectedOffsets do
        local offset = expectedOffsets[index]
        AssertPoint(frames[index], expected.initial, container, expected.initial, offset[1], offset[2],
            label .. " button " .. tostring(index))
    end
end

local function BindingCalls(frames)
    local count = 0
    for i = 1, #frames do count = count + (frames[i]._bindingCalls or 0) end
    return count
end

local function GeometryCalls(frames, field)
    local count = 0
    for i = 1, #frames do count = count + (frames[i][field] or 0) end
    return count
end

local matrixCases = 0
local horizontalChurnCovered = false
local verticalChurnCovered = false
for _, anchor in ipairs(ANCHORS) do
    for _, growth in ipairs(GROWTH_ORDER) do
        local expected = GROWTHS[growth]
        local label = "unit " .. anchor .. "/" .. growth
        local lane = UnitLane(anchor, growth)
        Equal(lane.anchor, anchor, label .. " compiled bounding-box anchor")
        Equal(lane.initialAnchor, expected.initial, label .. " compiled initial anchor")
        Equal(lane.verticalGrowth, expected.vertical, label .. " compiled axis")
        local container, auraRoot, parent = ApplyLane(lane)

        -- Selected anchor owns the lane bounds. Growth must not silently replace
        -- this with initialAnchor on the outer container.
        AssertPoint(container, anchor, parent, anchor, 7, -5, label .. " container")
        AssertLayoutSetters(container, expected, label)

        local group = assert(container:GetAuraGroup(container._msufA3ManagedGroupKey))
        local frames = group:GetFramesByIndex()
        local bindingsBefore = BindingCalls(frames)
        local setterCallsBeforeChurn = {
            anchor = container.layoutSetterCalls.anchor,
            growth = container.layoutSetterCalls.growth,
            width = container.layoutSetterCalls.width,
        }
        container:ApplyLayout() -- simulate Blizzard assignment/layout churn
        Equal(BindingCalls(frames), bindingsBefore, label .. " layout churn rebuilt visual bindings")
        Equal(container.layoutSetterCalls.anchor, setterCallsBeforeChurn.anchor,
            label .. " layout churn repeated native anchor setter")
        Equal(container.layoutSetterCalls.growth, setterCallsBeforeChurn.growth,
            label .. " layout churn repeated native growth setter")
        Equal(container.layoutSetterCalls.width, setterCallsBeforeChurn.width,
            label .. " layout churn repeated native width setter")
        AssertGrid(frames, container, expected, label)
        Near(container.width, lane.width, label .. " fixed-capacity width after layout")
        Near(container.height, lane.height, label .. " fixed-capacity height after layout")

        if expected.vertical then
            Check(container.ApplyLayout ~= NativeAuraApplyLayout, label .. " did not install vertical layout fallback")
        else
            Check(container.ApplyLayout ~= NativeAuraApplyLayout,
                label .. " did not install fixed-capacity native layout wrapper")
            Check((container.nativeApplyLayoutCalls or 0) >= 1,
                label .. " horizontal wrapper did not delegate to Blizzard")
        end

        -- Reapplying an unchanged compiled lane is a cold-path no-op for layout
        -- setters and visual bindings.
        local anchorCalls = container.layoutSetterCalls.anchor
        local growthCalls = container.layoutSetterCalls.growth
        local widthCalls = container.layoutSetterCalls.width
        local ok, any = A3._ApplyNormalLaneContainers(auraRoot, { buff = lane }, parent, false)
        Check(ok == true and any == true and auraRoot.Buffs == container, label .. " did not reuse its container")
        Equal(container.layoutSetterCalls.anchor, anchorCalls, label .. " repeated native anchor setter")
        Equal(container.layoutSetterCalls.growth, growthCalls, label .. " repeated native growth setter")
        Equal(container.layoutSetterCalls.width, widthCalls, label .. " repeated native width setter")
        Equal(BindingCalls(frames), bindingsBefore, label .. " cold reapply rebuilt visual bindings")

        if not expected.vertical and not horizontalChurnCovered then
            local reordered = { frames[3], frames[1], frames[2], frames[4], frames[5], frames[6] }
            group.frames = reordered
            container:ApplyLayout()
            AssertGrid(reordered, container, expected, label .. " reordered native churn")
            Equal(BindingCalls(frames), bindingsBefore, label .. " reordered native churn rebuilt visual bindings")
            horizontalChurnCovered = true
        elseif expected.vertical and not verticalChurnCovered then
            local reordered = { frames[3], frames[1], frames[2], frames[4], frames[5], frames[6] }
            group.frames = reordered
            container:ApplyLayout()
            AssertGrid(reordered, container, expected, label .. " reordered vertical churn")
            Equal(BindingCalls(frames), bindingsBefore, label .. " vertical fallback rebuilt visual bindings")

            -- Stress the vertical UNIT_AURA layout route. The stable AuraGroup
            -- is cached, while Blizzard's reordered framesByIndex is fetched on
            -- every pass. Each active icon gets exactly one ClearAllPoints and
            -- one SetPoint; no styling or native setters are repeated.
            local groupLookups = container.getAuraGroupCalls or 0
            local clears = GeometryCalls(reordered, "clearAllPointsCalls")
            local points = GeometryCalls(reordered, "setPointCalls")
            local stressPasses = 1000
            for _ = 1, stressPasses do container:ApplyLayout() end
            Equal(container.getAuraGroupCalls or 0, groupLookups, label .. " repeated AuraGroup lookup")
            Equal(GeometryCalls(reordered, "clearAllPointsCalls") - clears, #reordered * stressPasses,
                label .. " vertical clear-point work")
            Equal(GeometryCalls(reordered, "setPointCalls") - points, #reordered * stressPasses,
                label .. " vertical set-point work")
            Equal(BindingCalls(frames), bindingsBefore, label .. " stress churn rebuilt visual bindings")
            Equal(container.layoutSetterCalls.anchor, setterCallsBeforeChurn.anchor,
                label .. " stress churn repeated native anchor setter")
            Equal(container.layoutSetterCalls.growth, setterCallsBeforeChurn.growth,
                label .. " stress churn repeated native growth setter")
            Equal(container.layoutSetterCalls.width, setterCallsBeforeChurn.width,
                label .. " stress churn repeated native width setter")
            verticalChurnCovered = true
        end

        matrixCases = matrixCases + 1
    end
end
Equal(matrixCases, 54, "unit anchor/growth matrix coverage")
Check(horizontalChurnCovered and verticalChurnCovered, "native/fallback reorder coverage incomplete")

-- Production unit frames use one native container for every normal aura lane
-- on the same unit. Verify the shared cache/event owner, independent lane
-- geometry, selective layout no-op, single forced refresh, max-count no-reparse,
-- and in-combat unit-token reuse.
do
    _G.MSUF_DB = {
        auras3 = {
            enabled = true,
            showPlayer = true,
            showFocus = true,
            shared = {
                showBuffs = true,
                showDebuffs = true,
                maxBuffs = 3,
                maxDebuffs = 2,
                buffPerRow = 3,
                debuffPerRow = 2,
                buffGroupIconSize = 10,
                debuffGroupIconSize = 12,
                spacing = 2,
                buffAnchor = "TOPRIGHT",
                debuffAnchor = "BOTTOMLEFT",
                buffGroupOffsetX = 7,
                buffGroupOffsetY = -5,
                debuffGroupOffsetX = -4,
                debuffGroupOffsetY = 6,
                buffGrowthX = "LEFTDOWN",
                debuffGrowthX = "RIGHTUP",
                buffShowCooldownSwipe = false,
                debuffShowCooldownSwipe = false,
                buffShowDurationBar = false,
                debuffShowDurationBar = false,
                buffShowCooldownText = false,
                debuffShowCooldownText = false,
                buffShowStackCount = false,
                debuffShowStackCount = false,
                buffShowTooltip = false,
                debuffShowTooltip = false,
            },
        },
    }
    A3._runtimeConfigGen = (A3._runtimeConfigGen or 1) + 1
    local frame = NewFrame(nil)
    frame.unit = "player"
    frame.MSUFSpec = {}
    local creationsBefore = auraContainerCreations
    Check(AurasElement.Enable(frame) == true, "production shared aura apply failed")
    local auraRoot = assert(frame.Auras, "production aura root missing")
    local shared = assert(auraRoot.UnitAuras, "production shared aura container missing")
    Equal(auraContainerCreations, creationsBefore + 1,
        "normal buff/debuff lanes allocated more than one native container")
    Check(shared._msufA3SharedAuraGroups == true, "normal aura container is not shared")
    Check(auraRoot.Buffs == nil and auraRoot.Debuffs == nil,
        "legacy isolated normal containers survived shared apply")
    Equal(shared:GetUnit(), "player", "shared aura unit")

    local buffGroup = assert(shared:GetAuraGroup("msuf_buff"), "shared buff group missing")
    local debuffGroup = assert(shared:GetAuraGroup("msuf_debuff"), "shared debuff group missing")
    local buffFrames = buffGroup:GetFramesByIndex()
    local debuffFrames = debuffGroup:GetFramesByIndex()
    shared:ApplyLayout()
    AssertPoint(buffFrames[1], "TOPRIGHT", shared, "TOPRIGHT", 7, -5, "shared buff anchor")
    AssertPoint(debuffFrames[1], "BOTTOMLEFT", shared, "BOTTOMLEFT", -4, 6, "shared debuff anchor")

    local buffPoints = GeometryCalls(buffFrames, "setPointCalls")
    local debuffPoints = GeometryCalls(debuffFrames, "setPointCalls")
    shared:ApplyLayout()
    Equal(GeometryCalls(buffFrames, "setPointCalls"), buffPoints,
        "unchanged shared buff group repeated geometry")
    Equal(GeometryCalls(debuffFrames, "setPointCalls"), debuffPoints,
        "unchanged shared debuff group repeated geometry")

    buffGroup.frames = { buffFrames[2], buffFrames[1], buffFrames[3] }
    shared:ApplyLayout()
    Check(GeometryCalls(buffFrames, "setPointCalls") > buffPoints,
        "reordered shared buff group did not refresh geometry")
    Equal(GeometryCalls(debuffFrames, "setPointCalls"), debuffPoints,
        "reordered shared buff group relaid the unchanged debuff group")

    local updates = shared.updateAllAurasCalls or 0
    Check(A3._RefreshAppliedNativeAuras(frame, true) == true,
        "forced shared aura refresh failed")
    Equal(shared.updateAllAurasCalls or 0, updates + 1,
        "forced shared aura refresh did not parse exactly once")

    _G.MSUF_DB.auras3.shared.maxBuffs = 4
    A3._runtimeConfigGen = A3._runtimeConfigGen + 1
    updates = shared.updateAllAurasCalls or 0
    Check(AurasElement.Enable(frame) == true, "shared max-count reapply failed")
    Check(frame.Auras.UnitAuras == shared, "shared max-count edit recreated the container")
    Equal(shared.updateAllAurasCalls or 0, updates,
        "shared max-count edit forced a redundant full aura parse")
    Check((shared.maxFrameCountCalls or 0) >= 1,
        "shared max-count edit did not update the native group limit")

    local creationsBeforeCombatSwap = auraContainerCreations
    inCombat = true
    Check(A3.RenderUnitChangedFrame(frame, "player", "focus") == true,
        "shared container could not be rebound during combat")
    inCombat = false
    Check(frame.Auras.UnitAuras == shared, "combat unit swap replaced the shared container")
    Equal(auraContainerCreations, creationsBeforeCombatSwap,
        "combat unit swap allocated a new aura container")
    Equal(shared:GetUnit(), "focus", "combat-shared aura unit")

    local foreign = NewFrame(nil)
    buffGroup.frames[1].point = { "CENTER", foreign, "CENTER", 99, 88 }
    updates = shared.updateAllAurasCalls or 0
    Check(A3._DirectIdentityRefreshUnit("focus", true) == true,
        "shared world-repair refresh did not run")
    Equal(shared.updateAllAurasCalls or 0, updates + 1,
        "shared world-repair refresh did not settle native auras exactly once")
    AssertPoint(buffGroup.frames[1], "TOPRIGHT", shared, "TOPRIGHT", 7, -5,
        "shared world-repair buff anchor")
end

-- A single normal lane has no duplicate cache/event work to eliminate. Keep it
-- on Blizzard's lighter native-flow container instead of paying shared-layout
-- bookkeeping for a one-group case.
do
    _G.MSUF_DB.auras3.shared.showDebuffs = false
    A3._runtimeConfigGen = A3._runtimeConfigGen + 1
    local frame = NewFrame(nil)
    frame.unit = "player"
    frame.MSUFSpec = {}
    local creationsBefore = auraContainerCreations
    Check(AurasElement.Enable(frame) == true, "single-lane production apply failed")
    Equal(auraContainerCreations, creationsBefore + 1,
        "single-lane production apply allocated more than one container")
    Check(frame.Auras.Buffs ~= nil, "single-lane production apply lost native buff container")
    Check(frame.Auras.UnitAuras == nil, "single-lane production apply used shared bookkeeping")
end

-- PLAYER_ENTERING_WORLD / ZONE_CHANGED_NEW_AREA use a one-shot geometry pass
-- that deliberately bypasses desired-value caches. Cover a visible repair and
-- the deferred hidden-container marker on a normal player aura lane.
do
    local lane = UnitLane("RIGHT", "RIGHTDOWN")
    local container, auraRoot, parent = ApplyLane(lane)
    Check(A3._DirectIdentityRefreshUnitEligible("player") == true,
        "player aura containers are excluded from world repair")
    Check(container._msufA3DirectIdentityUnit == "player",
        "player aura container was not registered for world repair")

    local foreign = NewFrame(nil)
    container.point = { "CENTER", foreign, "CENTER", 99, 88 }
    container.width, container.height = 3, 4
    local updates = container.updateAllAurasCalls or 0
    Check(A3._DirectIdentityRefreshUnit("player", true) == true,
        "visible player world repair did not run")
    Equal(container.updateAllAurasCalls or 0, updates + 1,
        "visible player world repair did not settle native auras first")
    AssertPoint(container, lane.anchor, parent, lane.anchor, lane.x, lane.y,
        "visible player world repair")
    Near(container.width, lane.width, "visible player world repair width")
    Near(container.height, lane.height, "visible player world repair height")
    Equal(container._msufA3ForceManagedAuraGeometry, nil,
        "visible player world repair marker was not consumed")

    -- Hidden containers skip the native aura refresh but still receive the
    -- one-shot geometry repair immediately, so a lane hidden during a loading
    -- screen does not wait for another zone event to reclaim its saved point.
    container:Hide()
    container.point = { "CENTER", foreign, "CENTER", -77, 66 }
    container.width, container.height = 5, 6
    updates = container.updateAllAurasCalls or 0
    A3._DirectIdentityRefreshUnit("player", true)
    Equal(container.updateAllAurasCalls or 0, updates,
        "hidden player container refreshed native auras")
    AssertPoint(container, lane.anchor, parent, lane.anchor, lane.x, lane.y,
        "hidden player world repair")
    Near(container.width, lane.width, "hidden player world repair width")
    Near(container.height, lane.height, "hidden player world repair height")
    Equal(container._msufA3ForceManagedAuraGeometry, nil,
        "hidden player world repair marker was not consumed")
    local ok, any = A3._ApplyNormalLaneContainers(auraRoot, { buff = lane }, parent, false)
    Check(ok == true and any == true and auraRoot.Buffs == container,
        "hidden player container was not reused on its next config sync")
    AssertPoint(container, lane.anchor, parent, lane.anchor, lane.x, lane.y,
        "post-repair player config sync")
    Near(container.width, lane.width, "post-repair player config sync width")
    Near(container.height, lane.height, "post-repair player config sync height")
end

-- Dispel border/overlay/corner sensors use native AuraSlots rather than aura
-- groups. Their geometry cache must honor the same one-shot world marker.
do
    local parent = NewFrame(nil)
    local auraRoot = NewFrame(parent)
    local container = NewAuraContainer(auraRoot)
    local button = NewAuraButton(container)
    local sensor = {
        sensor = true,
        kind = "dispelCorner",
        unit = "player",
        visual = "corner",
        size = 12,
        max = 1,
        layer = 14,
        strata = "AUTO",
        alpha = 1,
        slots = { { anchor = "BOTTOM", x = 3, y = -2 } },
        _msufA3LayoutSignature = "sensor-layout",
    }
    local sensorRoot = {
        sensorRoot = true,
        kind = "dispelSensors",
        unit = "player",
        layer = 14,
        max = 1,
        sensors = { sensor },
        _msufA3LayoutSignature = "sensor-root-layout",
    }
    container[1] = button
    container.createdButtons = 1
    container._msufA3ManagedAuraSlots = true
    container._msufA3NativeLaneConfig = sensorRoot
    container._msufA3ParentFrame = parent
    container._msufA3SensorButtonSlots = { { sensor = sensor, sensorIndex = 1 } }

    Check(A3._SyncManagedAuraContainerGeometry(container, true) == true,
        "forced dispel AuraSlot geometry sync failed")
    AssertPoint(button, "BOTTOM", parent, "BOTTOM", 3, -2,
        "forced dispel AuraSlot geometry")
    Near(button.width, 12, "forced dispel AuraSlot width")
    Near(button.height, 12, "forced dispel AuraSlot height")

    local foreign = NewFrame(nil)
    button.point = { "CENTER", foreign, "CENTER", 90, 80 }
    button.width, button.height = 2, 3
    Check(A3._SyncManagedAuraContainerGeometry(container, false) == true,
        "cached dispel AuraSlot sync failed")
    Equal(button.point[2], foreign, "cached dispel sync unexpectedly bypassed geometry cache")
    container._msufA3ForceManagedAuraGeometry = true
    Check(A3._SyncManagedAuraContainerGeometry(container, false) == true,
        "deferred dispel AuraSlot repair failed")
    AssertPoint(button, "BOTTOM", parent, "BOTTOM", 3, -2,
        "deferred dispel AuraSlot geometry")
    Near(button.width, 12, "deferred dispel AuraSlot width")
    Near(button.height, 12, "deferred dispel AuraSlot height")
    Equal(container._msufA3ForceManagedAuraGeometry, nil,
        "deferred dispel AuraSlot marker survived successful sync")
end

-- Reusing a lane container across axis changes must keep one stable wrapper:
-- horizontal layouts delegate to Blizzard; vertical layouts return to the
-- column-major point-only fallback without recreating the container.
do
    local upLane = UnitLane("TOPRIGHT", "UP")
    local container, auraRoot, parent = ApplyLane(upLane)
    local group = container:GetAuraGroup(container._msufA3ManagedGroupKey)
    local frames = group:GetFramesByIndex()
    container:ApplyLayout()
    local nativeCalls = container.nativeApplyLayoutCalls or 0

    local activeCounts = { 1, 2, 3, 4, 5, 6 }
    for i = 1, #activeCounts do
        local activeCount = activeCounts[i]
        local active = {}
        for index = 1, activeCount do active[index] = frames[index] end
        group.frames = active
        container:ApplyLayout()
        Near(container.width, upLane.width, "vertical fixed width at active count " .. tostring(activeCount))
        Near(container.height, upLane.height, "vertical fixed height at active count " .. tostring(activeCount))
    end
    group.frames = frames

    local rightUpLane = UnitLane("TOPRIGHT", "RIGHTUP")
    local ok, any = A3._ApplyNormalLaneContainers(auraRoot, { buff = rightUpLane }, parent, false)
    Check(ok == true and any == true and auraRoot.Buffs == container,
        "vertical-to-horizontal switch recreated container")
    container:ApplyLayout()
    Equal(container.nativeApplyLayoutCalls or 0, nativeCalls + 1,
        "vertical wrapper did not delegate horizontal layout to Blizzard")
    AssertGrid(frames, container, GROWTHS.RIGHTUP, "vertical-to-horizontal switch")
    for _, activeCount in ipairs({ 1, 2, 4, 6 }) do
        local active = {}
        for index = 1, activeCount do active[index] = frames[index] end
        group.frames = active
        container:ApplyLayout()
        Near(container.width, rightUpLane.width,
            "horizontal fixed width at active count " .. tostring(activeCount))
        Near(container.height, rightUpLane.height,
            "horizontal fixed height at active count " .. tostring(activeCount))
    end
    group.frames = frames

    local downLane = UnitLane("TOPRIGHT", "DOWN")
    ok, any = A3._ApplyNormalLaneContainers(auraRoot, { buff = downLane }, parent, false)
    Check(ok == true and any == true and auraRoot.Buffs == container,
        "horizontal-to-vertical switch recreated container")
    nativeCalls = container.nativeApplyLayoutCalls or 0
    container:ApplyLayout()
    Equal(container.nativeApplyLayoutCalls or 0, nativeCalls,
        "vertical layout unexpectedly delegated to Blizzard")
    AssertGrid(frames, container, GROWTHS.DOWN, "horizontal-to-vertical switch")
end

-- Group frames compile a different DB/spec shape but feed the same native lane
-- runtime. Exercise all four group horizontal growth pairs so this cannot regress
-- independently behind the group config cache.
local GROUP_GROWTHS = {
    { name = "RIGHTDOWN", xName = "RIGHT", yName = "DOWN", expected = GROWTHS.RIGHTDOWN },
    { name = "LEFTDOWN", xName = "LEFT", yName = "DOWN", expected = GROWTHS.LEFTDOWN },
    { name = "RIGHTUP", xName = "RIGHT", yName = "UP", expected = GROWTHS.RIGHTUP },
    { name = "LEFTUP", xName = "LEFT", yName = "UP", expected = GROWTHS.LEFTUP },
}
local GROUP_LANES = {
    {
        kind = "buff", show = "showBuffs", max = "maxBuffs", size = "buffIconSize",
        spacing = "buffSpacing", perRow = "buffPerRow", growthX = "buffGrowthX",
        growthY = "buffGrowthY", anchor = "buffAnchor", x = "buffOffsetX", y = "buffOffsetY",
    },
    {
        kind = "trackedBuff", show = "showTrackedBuffs", max = "maxTrackedBuffs", size = "trackedBuffIconSize",
        spacing = "trackedBuffSpacing", perRow = "trackedBuffPerRow", growthX = "trackedBuffGrowthX",
        growthY = "trackedBuffGrowthY", anchor = "trackedBuffAnchor", x = "trackedBuffOffsetX", y = "trackedBuffOffsetY",
    },
    {
        kind = "debuff", show = "showDebuffs", max = "maxDebuffs", size = "debuffIconSize",
        spacing = "debuffSpacing", perRow = "debuffPerRow", growthX = "debuffGrowthX",
        growthY = "debuffGrowthY", anchor = "debuffAnchor", x = "debuffOffsetX", y = "debuffOffsetY",
    },
    {
        kind = "external", show = "showExternals", max = "maxExternals", size = "externalIconSize",
        spacing = "externalSpacing", perRow = "externalPerRow", growthX = "externalGrowthX",
        growthY = "externalGrowthY", anchor = "externalAnchor", x = "externalOffsetX", y = "externalOffsetY",
    },
}

local groupCases = 0
for _, laneSpec in ipairs(GROUP_LANES) do
    for _, anchor in ipairs(ANCHORS) do
        for _, growth in ipairs(GROUP_GROWTHS) do
            local source = { enabled = true }
            source[laneSpec.show] = true
            source[laneSpec.max] = 6
            source[laneSpec.size] = 10
            source[laneSpec.spacing] = 2
            source[laneSpec.perRow] = 3
            source[laneSpec.growthX] = growth.xName
            source[laneSpec.growthY] = growth.yName
            source[laneSpec.anchor] = anchor
            source[laneSpec.x] = 7
            source[laneSpec.y] = -5
            local frame = NewFrame(nil)
            frame.unit = "party1"
            frame._msufIsGroupFrame = true
            frame.MSUFSpec = { auras = source }
            Check(AurasElement.IsEnabled(frame) == true, "group aura config did not enable")
            local cfg = assert(frame._msufA3NativeGroupConfig)
            Check(cfg.group == true, "group aura config lost group marker")
            local lane = assert(cfg.lanes[laneSpec.kind])
            local label = "group " .. laneSpec.kind .. " " .. anchor .. "/" .. growth.name
            Equal(lane.anchor, anchor, label .. " compiled bounding-box anchor")
            Equal(lane.initialAnchor, growth.expected.initial, label .. " compiled initial anchor")
            local container, _, parent = ApplyLane(lane)
            AssertPoint(container, anchor, parent, anchor, 7, -5, label .. " container")
            AssertLayoutSetters(container, growth.expected, label)
            local frames = container:GetAuraGroup(container._msufA3ManagedGroupKey):GetFramesByIndex()
            container:ApplyLayout()
            AssertGrid(frames, container, growth.expected, label)
            Check(container.ApplyLayout ~= NativeAuraApplyLayout,
                label .. " did not install fixed-capacity native layout wrapper")
            Near(container.width, lane.width, label .. " fixed-capacity width")
            Near(container.height, lane.height, label .. " fixed-capacity height")
            groupCases = groupCases + 1
        end
    end
end
Equal(groupCases, 144, "group lane/anchor/growth coverage")

-- Execute the Menu2 unit-preview geometry provider directly. This keeps the
-- preview side of the contract covered without constructing WoW UI regions:
-- all nine anchors, both normal lanes, all three custom lanes, compiled metrics,
-- full capacity with only four samples, and the no-runtime-metrics fallback.
do
    local previewConfig
    local customItems = {}
    local previewModel = {
        CanonKey = function(value) return value end,
        CurrentPanelKey = function() return "player" end,
    }
    local menuModel = {
        ReadPreviewConfig = function() return previewConfig end,
        CustomContainer = function(_, index) return customItems[index] end,
    }
    local previewNS = {
        UFPreview = { Model = previewModel },
        MSUF_Auras3 = { MenuModel = menuModel },
    }
    local previewChunk = assert(loadfile(root
        .. "/MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Auras.lua"))
    previewChunk("MidnightSimpleUnitFrames", previewNS)
    local previewAuras = assert(previewNS.UFPreviewAuras)
    local fractions = {
        TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
        LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
        BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
    }
    local function Metrics(anchor, x, y)
        return {
            enabled = true, num = 6, size = 10, spacing = 2, step = 12,
            perRow = 3, width = 34, height = 22,
            growthX = 1, growthY = -1, verticalGrowth = false,
            initialAnchor = "TOPLEFT", anchor = anchor, x = x, y = y,
        }
    end
    for _, anchor in ipairs(ANCHORS) do
        local buffMetrics = Metrics(anchor, 7, -5)
        local debuffMetrics = Metrics(anchor, -11, 8)
        local customMetrics = {
            Metrics(anchor, 3, 4), Metrics(anchor, -6, 9), Metrics(anchor, 12, -7),
        }
        previewConfig = {
            enabled = true,
            showBuffs = true,
            showDebuffs = true,
            buffMetrics = buffMetrics,
            debuffMetrics = debuffMetrics,
            customMetrics = customMetrics,
            buffLayer = 5,
            debuffLayer = 6,
        }
        for index = 1, 3 do
            customItems[index] = {
                enabled = true,
                auraType = index == 2 and "DEBUFF" or "BUFF",
                layer = 8 + index,
                placed = {
                    anchor = anchor, x = customMetrics[index].x, y = customMetrics[index].y,
                    max = 6, size = 10, spacing = 2, perRow = 3, growth = "RIGHTDOWN",
                },
            }
        end
        local state = assert(previewAuras.BuildState("player", 200, 100))
        local frac = fractions[anchor]
        local function AssertPreviewLane(bounds, metrics, label)
            Near(bounds.laneLeft, frac[1] * 200 + metrics.x - frac[1] * metrics.width,
                label .. " left")
            Near(bounds.laneBottom, frac[2] * 100 + metrics.y - frac[2] * metrics.height,
                label .. " bottom")
            Near(bounds.laneW, metrics.width, label .. " full-capacity width")
            Near(bounds.laneH, metrics.height, label .. " full-capacity height")
            Equal(bounds.shown, 4, label .. " sample count")
        end
        AssertPreviewLane(state.buff, buffMetrics, "unit preview buff " .. anchor)
        AssertPreviewLane(state.debuff, debuffMetrics, "unit preview debuff " .. anchor)
        for index = 1, 3 do
            AssertPreviewLane(state["custom" .. tostring(index)], customMetrics[index],
                "unit preview custom" .. tostring(index) .. " " .. anchor)
        end
    end

    previewConfig = {
        enabled = true, showBuffs = false, showDebuffs = false, customMetrics = {},
    }
    customItems[1] = {
        enabled = true,
        auraType = "BUFF",
        layer = 9,
        placed = {
            anchor = "RIGHT", x = -2.5, y = 4.5,
            max = 6, size = 10, spacing = 2, perRow = 3, growth = "RIGHTDOWN",
        },
    }
    customItems[2], customItems[3] = nil, nil
    local fallbackState = assert(previewAuras.BuildState("player", 200, 100))
    local fallback = assert(fallbackState.custom1)
    Near(fallback.laneW, 34, "custom preview fallback full-capacity width")
    Near(fallback.laneH, 22, "custom preview fallback full-capacity height")
    Near(fallback.laneLeft, 200 - 2 - 34, "custom preview fallback runtime-rounded X")
    Near(fallback.laneBottom, 50 + 5 - 11, "custom preview fallback runtime-rounded Y")
    Equal(fallback.shown, 4, "custom preview fallback sample count")
end

-- Static integration guards: live, Edit Mode, Menu2 unit/group previews, and
-- the group External lane all preserve the same full-capacity rectangle and
-- selected-anchor/internal-flow split.
local runtimeSource = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua")
Check(runtimeSource:find("container:SetPoint(lane.anchor, parentFrame, lane.anchor, lane.x, lane.y)", 1, true),
    "live lane no longer anchors its bounding box with lane.anchor")
Check(runtimeSource:find("SetAuraLayoutAnchorPoint", 1, true), "native layout anchor setter missing")
Check(runtimeSource:find("SetAuraLayoutGrowthDirection", 1, true), "native growth setter missing")
Check(runtimeSource:find("SetAuraLayoutRowWidth", 1, true), "native row-width setter missing")
Check(Count(runtimeSource, "initialAnchor = ButtonAnchor(xSign, ySign)") >= 2,
    "unit/group compilers no longer share initial-anchor derivation")
Check(runtimeSource:find("local NativeRuntime = (function()", 1, true),
    "native backend no longer has an isolated local-budget boundary")
Check(runtimeSource:find("local function LayoutVerticalAuraContainer", 1, true),
    "vertical layout helper leaked out of the local runtime")
Check(not runtimeSource:find("function A3._LayoutVerticalAuraContainer", 1, true),
    "vertical churn uses an A3 namespace lookup")
Check(runtimeSource:find("container._msufA3ManagedAuraGroup = group", 1, true),
    "vertical layout no longer caches the stable AuraGroup")
Check(runtimeSource:find("InstallVerticalAuraLayoutFallback(container)", 1, true),
    "normal lanes no longer install the fixed-capacity ApplyLayout wrapper")
Check(Count(runtimeSource, "container:SetSize(lane.width or lane.size or 1, lane.height or lane.size or 1)") >= 2,
    "native horizontal/vertical layout no longer restores full lane capacity")
Check(runtimeSource:find("player = true", 1, true),
    "player aura containers are no longer eligible for world repair")
Check(runtimeSource:find("A3._SyncManagedAuraContainerGeometry", 1, true),
    "generic managed-aura world repair dispatcher missing")

local editModeSource = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_EditMode.lua")
Check(editModeSource:find("PositionPreviewGroup(group, frame, anchor, x, y, laneW, laneH)", 1, true),
    "Edit Mode preview no longer anchors lane bounds with the selected anchor")
Check(editModeSource:find("icon:SetPoint(initialAnchor, body, initialAnchor, col * step * growthX, row * step * growthY)", 1, true),
    "Edit Mode preview no longer flows icons from initialAnchor")
Check(editModeSource:find('if anchor == "TOP" then return w * 0.5, h end', 1, true)
    and editModeSource:find('if anchor == "RIGHT" then return w, h * 0.5 end', 1, true)
    and editModeSource:find('if anchor == "BOTTOM" then return w * 0.5, 0 end', 1, true),
    "Edit Mode preview lost edge-anchor geometry")
Check(not editModeSource:find("PreviewLaneDimensions", 1, true),
    "Edit Mode custom preview still shrinks to its sample icons")

local unitPreviewSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Auras.lua")
Check(unitPreviewSource:find("local laneLeft = baseX + x - anchorLocalX", 1, true),
    "unit preview no longer positions lane bounds from the selected anchor")
Check(unitPreviewSource:find('icon:SetPoint(bounds.initialAnchor or "TOPLEFT", visual, bounds.initialAnchor or "TOPLEFT"', 1, true),
    "unit preview no longer flows icons from initialAnchor")
Check(unitPreviewSource:find("local cols, rows = GridShape(count, perRow, vertical)", 1, true),
    "unit custom preview no longer sizes fallback bounds from full capacity")

local menuModelSource = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Menu_Model.lua")
Check(menuModelSource:find("TOPLEFT=true, TOP=true, TOPRIGHT=true", 1, true)
    and menuModelSource:find("LEFT=true, CENTER=true, RIGHT=true", 1, true)
    and menuModelSource:find("BOTTOMLEFT=true, BOTTOM=true, BOTTOMRIGHT=true", 1, true),
    "unit aura menu model no longer accepts all nine anchors")
Check(menuModelSource:find("customMetrics[index] = buildMetrics", 1, true),
    "unit aura preview no longer consumes compiled custom-lane metrics")

local groupPreviewSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua")
Check(groupPreviewSource:find("handle:SetPoint(anchor, mock, anchor", 1, true),
    "group preview no longer anchors lane bounds with the selected anchor")
Check(groupPreviewSource:find("tex:SetPoint(rect.anchor, handle, rect.anchor, rect[1], rect[2])", 1, true),
    "group preview no longer flows icons from initialAnchor")
Check(groupPreviewSource:find("if GF_PREVIEW_ANCHOR_FRAC[anchor] then return anchor end", 1, true),
    "group aura preview no longer accepts all nine runtime anchors")
Check(groupPreviewSource:find('LayoutAuraGroup(externalHandle, "external", externalCfg', 1, true),
    "group External aura lane is missing from the preview renderer")

local groupHandlesSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua")
Check(groupHandlesSource:find("return ResolveAnchor(rx, ry)", 1, true),
    "group aura drag no longer resolves through the nine-anchor helper")
Check(groupHandlesSource:find('externalHandle._cfgGroup = "externals"', 1, true),
    "group External aura handle no longer writes its persisted lane")

print("PASS aura position parity: shared multi-group runtime, selective layout, combat reuse, 54 unit + 144 group live layouts, 45 unit preview lanes, fixed active-count capacity, player/dispel zone repair, 1000x vertical churn")
