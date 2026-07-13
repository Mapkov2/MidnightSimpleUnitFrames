-- Standalone regression for AuraContainer anchor/growth ownership.
--
-- The selected lane anchor pins the lane bounding box to the unit frame. The
-- growth-derived initialAnchor belongs to Blizzard's internal element flow.
-- Horizontal-first lanes use Blizzard's native layout setters; vertical-first
-- UP/DOWN lanes use MSUF's small ApplyLayout fallback because the native flow
-- cannot swap its major axis.
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
function Frame:SetAuraGroupMaxFrameCount() end
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

_G.CreateFrame = function(frameType, _, parent)
    if frameType == "AuraContainer" then return NewAuraContainer(parent) end
    return NewFrame(parent)
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

local ANCHORS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER" }
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
    local ok, any = A3._ApplyNormalLaneContainers(auraRoot, { buff = lane }, parent, false)
    Check(ok == true and any == true, "normal aura lane integration failed")
    return assert(auraRoot.Buffs), auraRoot, parent
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

        if expected.vertical then
            Check(container.ApplyLayout ~= NativeAuraApplyLayout, label .. " did not install vertical layout fallback")
        else
            Equal(container.ApplyLayout, NativeAuraApplyLayout, label .. " replaced Blizzard's horizontal layout")
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
Equal(matrixCases, 30, "unit anchor/growth matrix coverage")
Check(horizontalChurnCovered and verticalChurnCovered, "native/fallback reorder coverage incomplete")

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

    local activeSizes = {
        { count = 2, width = 10, height = 22 },
        { count = 3, width = 10, height = 34 },
        { count = 4, width = 22, height = 34 },
    }
    for i = 1, #activeSizes do
        local expected = activeSizes[i]
        local active = {}
        for index = 1, expected.count do active[index] = frames[index] end
        group.frames = active
        container:ApplyLayout()
        Near(container.width, expected.width, "vertical active-count width " .. tostring(expected.count))
        Near(container.height, expected.height, "vertical active-count height " .. tostring(expected.count))
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

local groupCases = 0
for _, anchor in ipairs(ANCHORS) do
    for _, growth in ipairs(GROUP_GROWTHS) do
        local source = {
            enabled = true,
            showBuffs = true,
            maxBuffs = 6,
            buffIconSize = 10,
            buffSpacing = 2,
            buffPerRow = 3,
            buffGrowthX = growth.xName,
            buffGrowthY = growth.yName,
            buffAnchor = anchor,
            buffOffsetX = 7,
            buffOffsetY = -5,
            buffShowCooldown = false,
            buffShowStacks = false,
            buffShowCooldownSwipe = false,
            buffShowDurationBar = false,
            buffShowTooltip = false,
        }
        local frame = NewFrame(nil)
        frame.unit = "party1"
        frame._msufIsGroupFrame = true
        frame.MSUFSpec = { auras = source }
        Check(AurasElement.IsEnabled(frame) == true, "group aura config did not enable")
        local cfg = assert(frame._msufA3NativeGroupConfig)
        Check(cfg.group == true, "group aura config lost group marker")
        local lane = assert(cfg.lanes.buff)
        local label = "group " .. anchor .. "/" .. growth.name
        Equal(lane.anchor, anchor, label .. " compiled bounding-box anchor")
        Equal(lane.initialAnchor, growth.expected.initial, label .. " compiled initial anchor")
        local container, _, parent = ApplyLane(lane)
        AssertPoint(container, anchor, parent, anchor, 7, -5, label .. " container")
        AssertLayoutSetters(container, growth.expected, label)
        local frames = container:GetAuraGroup(container._msufA3ManagedGroupKey):GetFramesByIndex()
        container:ApplyLayout()
        AssertGrid(frames, container, growth.expected, label)
        Equal(container.ApplyLayout, NativeAuraApplyLayout, label .. " replaced Blizzard's horizontal layout")
        groupCases = groupCases + 1
    end
end
Equal(groupCases, 20, "group anchor/growth coverage")

-- Static parity guards: live, Edit Mode, and both Menu2 previews all preserve
-- the same bounding-box/initial-anchor split. These assertions intentionally
-- avoid requiring preview code changes for a native-container-only bug.
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

local editModeSource = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_EditMode.lua")
Check(editModeSource:find("PositionPreviewGroup(group, frame, anchor, x, y, laneW, laneH)", 1, true),
    "Edit Mode preview no longer anchors lane bounds with the selected anchor")
Check(editModeSource:find("icon:SetPoint(initialAnchor, body, initialAnchor, col * step * growthX, row * step * growthY)", 1, true),
    "Edit Mode preview no longer flows icons from initialAnchor")

local unitPreviewSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Auras.lua")
Check(unitPreviewSource:find("local laneLeft = baseX + x - anchorLocalX", 1, true),
    "unit preview no longer positions lane bounds from the selected anchor")
Check(unitPreviewSource:find('icon:SetPoint(bounds.initialAnchor or "TOPLEFT", visual, bounds.initialAnchor or "TOPLEFT"', 1, true),
    "unit preview no longer flows icons from initialAnchor")

local groupPreviewSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua")
Check(groupPreviewSource:find("handle:SetPoint(anchor, mock, anchor", 1, true),
    "group preview no longer anchors lane bounds with the selected anchor")
Check(groupPreviewSource:find("tex:SetPoint(rect.anchor, handle, rect.anchor, rect[1], rect[2])", 1, true),
    "group preview no longer flows icons from initialAnchor")

print("PASS aura growth anchoring: 30 unit + 20 group layouts, 1000x vertical churn, axis reuse, cold-path reuse")
