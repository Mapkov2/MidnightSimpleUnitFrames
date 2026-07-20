-- Standalone regression for AuraContainer anchor/growth ownership.
--
-- The selected lane anchor pins the lane bounding box to the unit frame. The
-- growth-derived initialAnchor belongs to Blizzard's internal element flow.
-- PTR 5 leaves AuraButton layout entirely inside Blizzard's native code. A
-- fixed MSUF-owned host keeps the configured full-capacity anchor stable.
-- Native one-icon rows provide true PTR 5-safe single-column UP/DOWN growth.
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
    if frame and frame._ptr5Forbidden and not nativeButtonAccess then
        error("PTR 5 forbidden AuraButton access outside Blizzard native code", 3)
    end
end

function Frame:GetParent() return self.parent end
function Frame:SetParent(parent) self.parent = parent end
function Frame:ClearAllPoints()
    CheckButtonAccess(self)
    self.clearAllPointsCalls = (self.clearAllPointsCalls or 0) + 1
    self.point = nil
end
function Frame:SetPoint(point, relativeTo, relativePoint, x, y)
    CheckButtonAccess(self)
    self.setPointCalls = (self.setPointCalls or 0) + 1
    self.point = { point, relativeTo, relativePoint, x or 0, y or 0 }
end
function Frame:SetAllPoints(relativeTo) self.allPoints = relativeTo or true end
function Frame:SetSize(width, height) CheckButtonAccess(self); self.width, self.height = width, height end
function Frame:SetWidth(width) self.width = width end
function Frame:SetHeight(height) self.height = height end
function Frame:GetWidth() return self.width or 0 end
function Frame:GetHeight() return self.height or 0 end
function Frame:SetAlpha(alpha) self.alpha = alpha end
function Frame:GetAlpha() return self.alpha or 1 end
function Frame:SetFrameLevel(level) CheckButtonAccess(self); self.frameLevel = level end
function Frame:GetFrameLevel() return self.frameLevel or 0 end
function Frame:SetFrameStrata(strata) CheckButtonAccess(self); self.frameStrata = strata end
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
function Frame:GetStatusBarTexture() return self.statusBarTexture end
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
    nativeButtonAccess = true
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
    nativeButtonAccess = false
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
        button._ptr5Forbidden = true
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
function Frame:AddAuraSlot(slotKey, filter, options)
    self.auraSlotOptions = self.auraSlotOptions or {}
    self.auraSlotOptions[slotKey] = { filter = filter, options = options }
    if options and options.initializeFrame then
        local button = NewAuraButton(self)
        options.initializeFrame(button)
        button._ptr5Forbidden = true
    end
end
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
        RegisterElement = function(name, element) registeredElements[name] = element end,
    },
}
_G.MSUF_NS = MSUF

local layersChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Layers.lua"))
layersChunk("MidnightSimpleUnitFrames", MSUF)
local backendChunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua"))
backendChunk("MidnightSimpleUnitFrames", MSUF)

local A3 = assert(MSUF.MSUF_Auras3)
local AurasElement = assert(registeredElements.Auras)
Check(type(A3.ResolveUnitFrameConfig) == "function", "unit aura compiler missing")
Check(type(A3._ApplyNormalLaneContainers) == "function", "normal lane integration surface missing")
local Layers = assert(MSUF.UF.Layers)
Check(Layers.SPELL_FRAME_EFFECT_BASE_OFFSET + 10 < Layers.DISPEL_OVERLAY_EFFECT_OFFSET,
    "Dispel overlay AUTO level is not above the strongest Spell frame effect")
Check(Layers.DISPEL_OVERLAY_EFFECT_OFFSET < Layers.TEXT_BASE_OFFSET + 5,
    "health effects escaped above the default text layer")

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
    UP = { x = 1, y = 1, initial = "BOTTOMLEFT", vertical = true, rowWidth = 10 },
    DOWN = { x = 1, y = -1, initial = "TOPLEFT", vertical = true, rowWidth = 10 },
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

local function ScopedUnitZoom(sharedZoom, overrideZoom, overrideStyle)
    _G.MSUF_DB = {
        auras3 = {
            enabled = true,
            showPlayer = true,
            shared = {
                showBuffs = true,
                showDebuffs = false,
                maxBuffs = 1,
                buffIconZoom = sharedZoom,
            },
            perUnit = {
                player = {
                    overrideStyle = overrideStyle,
                    overrideLayout = true,
                    layout = { buffIconZoom = overrideZoom },
                },
            },
        },
    }
    A3._runtimeConfigGen = (A3._runtimeConfigGen or 1) + 1
    return assert(assert(A3.ResolveUnitFrameConfig("player", {})).lanes.buff).iconZoom
end

Equal(ScopedUnitZoom(135, 175, false), 135, "inherited unit Aura Icon Zoom")
Equal(ScopedUnitZoom(135, 175, true), 175, "overridden unit Aura Icon Zoom")

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
    Near(container.auraLayoutRowWidth, expected.rowWidth or 34, label .. " native row width")
end

local function AssertGrid(frames, container, expected, label)
    local step = 12
    local expectedOffsets
    if expected.vertical == true then
        expectedOffsets = { { 0, 0 }, { 0, step * expected.y }, { 0, 2 * step * expected.y }, { 0, 3 * step * expected.y } }
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

do
    local lane = UnitLane("TOPLEFT", "RIGHTDOWN")
    lane.showCooldownText = true
    lane.showStacks = true
    _G.MSUF_DB.general = {}
    local container = ApplyLane(lane)
    local frames = assert(container:GetAuraGroup(container._msufA3ManagedGroupKey)):GetFramesByIndex()
    Equal(durationFormatterCreateCalls, 1, "duration formatter rebuilt for every AuraButton")
    for i = 1, #frames do
        local overlay = frames[i]._msufA3TextOverlay
        Check(overlay ~= nil, "shared Aura text overlay missing")
        Equal(overlay.clearAllPointsCalls, 1, "Aura text overlay laid out more than once during initialization")
    end
end

local matrixCases = 0
local horizontalChurnCovered = false
for _, anchor in ipairs(ANCHORS) do
    for _, growth in ipairs(GROWTH_ORDER) do
        local expected = GROWTHS[growth]
        local label = "unit " .. anchor .. "/" .. growth
        local lane = UnitLane(anchor, growth)
        Equal(lane.anchor, anchor, label .. " compiled bounding-box anchor")
        Equal(lane.initialAnchor, expected.initial, label .. " compiled initial anchor")
        Equal(lane.verticalGrowth, expected.vertical, label .. " compiled axis")
        local container, auraRoot, parent = ApplyLane(lane)

        -- Selected anchor owns the fixed host. The native container is anchored
        -- at its flow origin inside that host and may resize with active auras.
        local host = assert(container._msufA3LayoutHost)
        AssertPoint(host, anchor, parent, anchor, 7, -5, label .. " host")
        AssertPoint(container, expected.initial, host, expected.initial, 0, 0, label .. " container")
        Near(host.width, lane.width, label .. " fixed-capacity host width")
        Near(host.height, lane.height, label .. " fixed-capacity host height")
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
        Check(container.ApplyLayout == NativeAuraApplyLayout,
            label .. " replaced Blizzard's native ApplyLayout")
        Check((container.nativeApplyLayoutCalls or 0) >= 1, label .. " native layout did not run")

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

        if not horizontalChurnCovered then
            local reordered = { frames[3], frames[1], frames[2], frames[4], frames[5], frames[6] }
            group.frames = reordered
            container:ApplyLayout()
            AssertGrid(reordered, container, expected, label .. " reordered native churn")
            Equal(BindingCalls(frames), bindingsBefore, label .. " reordered native churn rebuilt visual bindings")
            local clears = GeometryCalls(reordered, "clearAllPointsCalls")
            local points = GeometryCalls(reordered, "setPointCalls")
            local stressPasses = 1000
            for _ = 1, stressPasses do container:ApplyLayout() end
            Equal(GeometryCalls(reordered, "clearAllPointsCalls") - clears, #reordered * stressPasses,
                label .. " native clear-point work")
            Equal(GeometryCalls(reordered, "setPointCalls") - points, #reordered * stressPasses,
                label .. " native set-point work")
            Equal(BindingCalls(frames), bindingsBefore, label .. " stress churn rebuilt visual bindings")
            horizontalChurnCovered = true
        end

        matrixCases = matrixCases + 1
    end
end
Equal(matrixCases, 54, "unit anchor/growth matrix coverage")
Check(horizontalChurnCovered, "native reorder coverage incomplete")

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
    local host = assert(container._msufA3LayoutHost)
    host.point = { "CENTER", foreign, "CENTER", 99, 88 }
    host.width, host.height = 3, 4
    local updates = container.updateAllAurasCalls or 0
    Check(A3._DirectIdentityRefreshUnit("player", true) == true,
        "visible player world repair did not run")
    Equal(container.updateAllAurasCalls or 0, updates + 1,
        "visible player world repair did not settle native auras first")
    AssertPoint(host, lane.anchor, parent, lane.anchor, lane.x, lane.y,
        "visible player world repair")
    Near(host.width, lane.width, "visible player world repair width")
    Near(host.height, lane.height, "visible player world repair height")
    Equal(container._msufA3ForceManagedAuraGeometry, nil,
        "visible player world repair marker was not consumed")

    host.point = { "CENTER", foreign, "CENTER", 55, -44 }
    container._msufA3ForceManagedAuraGeometry = true
    updates = container.updateAllAurasCalls or 0
    Check(A3._DirectIdentityRefreshUnit("player") == true,
        "normal direct refresh fast path did not run")
    Equal(container.updateAllAurasCalls or 0, updates + 1,
        "normal direct refresh fast path skipped native aura refresh")
    AssertPoint(host, lane.anchor, parent, lane.anchor, lane.x, lane.y,
        "normal direct refresh pending repair")
    Equal(container._msufA3ForceManagedAuraGeometry, nil,
        "normal direct refresh fast path dropped a pending geometry repair")

    -- Hidden containers skip the native aura refresh but still receive the
    -- one-shot geometry repair immediately, so a lane hidden during a loading
    -- screen does not wait for another zone event to reclaim its saved point.
    container:Hide()
    host.point = { "CENTER", foreign, "CENTER", -77, 66 }
    host.width, host.height = 5, 6
    updates = container.updateAllAurasCalls or 0
    A3._DirectIdentityRefreshUnit("player", true)
    Equal(container.updateAllAurasCalls or 0, updates,
        "hidden player container refreshed native auras")
    AssertPoint(host, lane.anchor, parent, lane.anchor, lane.x, lane.y,
        "hidden player world repair")
    Near(host.width, lane.width, "hidden player world repair width")
    Near(host.height, lane.height, "hidden player world repair height")
    Equal(container._msufA3ForceManagedAuraGeometry, nil,
        "hidden player world repair marker was not consumed")
    local ok, any = A3._ApplyNormalLaneContainers(auraRoot, { buff = lane }, parent, false)
    Check(ok == true and any == true and auraRoot.Buffs == container,
        "hidden player container was not reused on its next config sync")
    AssertPoint(host, lane.anchor, parent, lane.anchor, lane.x, lane.y,
        "post-repair player config sync")
    Near(host.width, lane.width, "post-repair player config sync width")
    Near(host.height, lane.height, "post-repair player config sync height")
end

-- The native Dispel overlay and Spell frame effects share the health bar. At
-- AUTO/equal strata Dispel must win by frame level; an explicit strata remains
-- an intentional user override and is never normalized back to AUTO.
do
    local function ApplyOverlay(strata, onHealth, layer)
        local parent = NewFrame(nil)
        parent.unit = "party1"
        parent.MSUFUnitKey = "party1"
        parent._msufIsGroupFrame = true
        parent._msufGFKind = "party"
        local healthFill
        parent.hpBar, healthFill = NewHealthBar(parent)
        parent.MSUFSpec = {
            auras = {
                enabled = true,
                showBuffs = false,
                maxBuffs = 0,
                showDebuffs = false,
                maxDebuffs = 0,
            },
            border = { dispel = false, dispelTrigger = "BY_ME" },
            group = {
                dispelOverlayEnabled = true,
                dispelOverlayOnHealth = onHealth ~= false,
                dispelOverlayStyle = "FULL",
                dispelOverlayAlpha = 0.35,
                dispelOverlayTrigger = "BORDER",
                dispelOverlayLayer = layer,
                dispelOverlayStrata = strata,
            },
        }
        Check(AurasElement.IsEnabled(parent) == true, "Dispel-only group aura config did not enable")
        Check(AurasElement.Enable(parent) == true, "native Dispel overlay did not apply")
        local container = assert(parent.Auras and parent.Auras.DispelSensor,
            "combined Dispel sensor container missing")
        local button = assert(container[1], "native Dispel overlay AuraButton missing")
        return parent, button, healthFill, container
    end

    local autoParent, autoButton, autoFill, autoContainer = ApplyOverlay("AUTO", true)
    Equal(autoButton.allPoints, autoParent.hpBar,
        "Dispel AuraButton owner is not attached to the health bar")
    Equal(autoButton._msufA3DispelSensorRegion.allPoints, autoFill,
        "Dispel overlay did not follow the current-health fill")
    Equal(autoButton.frameLevel,
        autoParent:GetFrameLevel() + Layers.DISPEL_OVERLAY_EFFECT_OFFSET,
        "AUTO Dispel overlay ignored the shared effect level")
    Equal(autoButton.frameStrata, autoParent:GetFrameStrata(),
        "AUTO Dispel overlay did not inherit parent strata")
    Check(autoContainer.frameLevel < autoButton.frameLevel,
        "Dispel assignment container inherited above its health effect")
    Check(autoButton.frameLevel
        > autoParent:GetFrameLevel() + Layers.SPELL_FRAME_EFFECT_BASE_OFFSET + 10,
        "AUTO Dispel overlay is not above strongest-priority Spell effect")

    local explicitParent, explicitButton = ApplyOverlay("HIGH", true)
    Equal(explicitButton.frameStrata, "HIGH",
        "explicit Dispel effect strata was normalized back to AUTO")
    Equal(explicitButton.frameLevel,
        explicitParent:GetFrameLevel() + Layers.DISPEL_OVERLAY_EFFECT_OFFSET,
        "explicit Dispel strata changed the same-strata level contract")

    local layeredParent, layeredButton = ApplyOverlay("AUTO", true, 13)
    Equal(layeredButton.frameLevel,
        layeredParent:GetFrameLevel() + Layers.DISPEL_OVERLAY_EFFECT_OFFSET + 13,
        "Dispel overlay ignored its compiled 0..30 Layer")

    local fullHealthParent, fullHealthButton = ApplyOverlay("AUTO", false)
    Equal(fullHealthButton.allPoints, fullHealthParent.hpBar,
        "full-health Dispel AuraButton escaped the health bar")
    Equal(fullHealthButton._msufA3DispelSensorRegion.allPoints, fullHealthParent.hpBar,
        "full-health Dispel overlay escaped onto the unit frame")
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
    local foreign = NewFrame(nil)
    button.point = { "CENTER", foreign, "CENTER", 90, 80 }
    button.width, button.height = 2, 3
    button._ptr5Forbidden = true
    Check(A3._SyncManagedAuraContainerGeometry(container, true) == true,
        "forced dispel AuraSlot geometry sync failed")
    Equal(button.point[2], foreign, "forced dispel sync touched a forbidden AuraButton")
    Near(button.width, 2, "forced dispel sync changed forbidden AuraButton width")
    Near(button.height, 3, "forced dispel sync changed forbidden AuraButton height")
    Check(A3._SyncManagedAuraContainerGeometry(container, false) == true,
        "cached dispel AuraSlot sync failed")
    Equal(button.point[2], foreign, "cached dispel sync unexpectedly bypassed geometry cache")
    container._msufA3ForceManagedAuraGeometry = true
    Check(A3._SyncManagedAuraContainerGeometry(container, false) == true,
        "deferred dispel AuraSlot repair failed")
    Equal(button.point[2], foreign, "deferred dispel repair touched a forbidden AuraButton")
    Equal(container._msufA3ForceManagedAuraGeometry, nil,
        "deferred dispel AuraSlot marker survived successful sync")
end

-- UP/DOWN use native one-icon rows. Switching between vertical and horizontal
-- growth recreates the container so all AuraButton setup remains inside
-- initializeFrame.
do
    local upLane = UnitLane("TOPRIGHT", "UP")
    local container, auraRoot, parent = ApplyLane(upLane)
    local group = container:GetAuraGroup(container._msufA3ManagedGroupKey)
    local frames = group:GetFramesByIndex()
    container:ApplyLayout()
    local host = assert(container._msufA3LayoutHost)
    Equal(upLane.verticalGrowth, true, "UP did not compile as vertical growth")
    Equal(upLane.cols, 1, "UP did not compile to one column")
    Equal(upLane.rows, 6, "UP row count")
    Near(upLane.width, 10, "UP lane width")
    Near(upLane.height, 70, "UP lane height")
    AssertGrid(frames, container, GROWTHS.UP, "native up")

    local activeCounts = { 1, 2, 3, 4, 5, 6 }
    for i = 1, #activeCounts do
        local activeCount = activeCounts[i]
        local active = {}
        for index = 1, activeCount do active[index] = frames[index] end
        group.frames = active
        container:ApplyLayout()
        Near(host.width, upLane.width, "fixed host width at active count " .. tostring(activeCount))
        Near(host.height, upLane.height, "fixed host height at active count " .. tostring(activeCount))
    end
    group.frames = frames

    local rightUpLane = UnitLane("TOPRIGHT", "RIGHTUP")
    local ok, any = A3._ApplyNormalLaneContainers(auraRoot, { buff = rightUpLane }, parent, false)
    local rightUpContainer = assert(auraRoot.Buffs)
    Check(ok == true and any == true and rightUpContainer ~= container,
        "vertical-to-horizontal growth did not recreate its PTR 5 container")
    rightUpContainer:ApplyLayout()
    local rightUpGroup = rightUpContainer:GetAuraGroup(rightUpContainer._msufA3ManagedGroupKey)
    local rightUpFrames = rightUpGroup:GetFramesByIndex()
    local rightUpHost = assert(rightUpContainer._msufA3LayoutHost)
    AssertGrid(rightUpFrames, rightUpContainer, GROWTHS.RIGHTUP, "vertical-to-horizontal switch")
    for _, activeCount in ipairs({ 1, 2, 4, 6 }) do
        local active = {}
        for index = 1, activeCount do active[index] = rightUpFrames[index] end
        rightUpGroup.frames = active
        rightUpContainer:ApplyLayout()
        Near(rightUpHost.width, rightUpLane.width,
            "native fixed host width at active count " .. tostring(activeCount))
        Near(rightUpHost.height, rightUpLane.height,
            "native fixed host height at active count " .. tostring(activeCount))
    end
    rightUpGroup.frames = rightUpFrames

    local downLane = UnitLane("TOPRIGHT", "DOWN")
    ok, any = A3._ApplyNormalLaneContainers(auraRoot, { buff = downLane }, parent, false)
    local downContainer = assert(auraRoot.Buffs)
    Check(ok == true and any == true and downContainer ~= rightUpContainer,
        "layout-changing growth did not recreate its PTR 5 container")
    downContainer:ApplyLayout()
    local downFrames = downContainer:GetAuraGroup(downContainer._msufA3ManagedGroupKey):GetFramesByIndex()
    AssertGrid(downFrames, downContainer, GROWTHS.DOWN, "native down switch")
end

-- Group frames compile a different DB/spec shape but feed the same native lane
-- runtime. Exercise horizontal and vertical growth so this cannot regress
-- independently behind the group config cache.
local GROUP_GROWTHS = {
    { name = "RIGHTDOWN", xName = "RIGHT", yName = "DOWN", expected = GROWTHS.RIGHTDOWN },
    { name = "LEFTDOWN", xName = "LEFT", yName = "DOWN", expected = GROWTHS.LEFTDOWN },
    { name = "RIGHTUP", xName = "RIGHT", yName = "UP", expected = GROWTHS.RIGHTUP },
    { name = "LEFTUP", xName = "LEFT", yName = "UP", expected = GROWTHS.LEFTUP },
    { name = "UP", xName = "UP", yName = "UP", expected = GROWTHS.UP },
    { name = "DOWN", xName = "DOWN", yName = "DOWN", expected = GROWTHS.DOWN },
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
            frame.MSUFUnitKey = "party1"
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
            local host = assert(container._msufA3LayoutHost)
            AssertPoint(host, anchor, parent, anchor, 7, -5, label .. " host")
            AssertPoint(container, growth.expected.initial, host, growth.expected.initial, 0, 0,
                label .. " container")
            AssertLayoutSetters(container, growth.expected, label)
            local frames = container:GetAuraGroup(container._msufA3ManagedGroupKey):GetFramesByIndex()
            container:ApplyLayout()
            AssertGrid(frames, container, growth.expected, label)
            Check(container.ApplyLayout == NativeAuraApplyLayout,
                label .. " replaced Blizzard's native ApplyLayout")
            Near(host.width, lane.width, label .. " fixed-capacity host width")
            Near(host.height, lane.height, label .. " fixed-capacity host height")
            groupCases = groupCases + 1
        end
    end
end
Equal(groupCases, 216, "group lane/anchor/growth coverage")

-- Party aura access can change without UNIT_AURA. The element must request the
-- two rare per-unit recovery events and invalidate only the already-registered
-- native containers for that party member. Raid and preview frames deliberately
-- stay off this path so the fix cannot add a 40-frame range subscription.
do
    local frame = NewFrame(nil)
    frame.unit = "party1"
    frame.MSUFUnitKey = "party1"
    frame._msufIsGroupFrame = true
    frame._msufGFKind = "party"
    frame.MSUFSpec = {
        auras = {
            enabled = true,
            showBuffs = true,
            maxBuffs = 3,
            buffIconSize = 10,
            buffSpacing = 2,
            buffPerRow = 3,
            showDebuffs = true,
            maxDebuffs = 2,
            debuffIconSize = 12,
            debuffSpacing = 2,
            debuffPerRow = 2,
        },
    }

    local events = AurasElement.GetEvents(frame)
    Equal(#events, 2, "party aura access event count")
    Equal(events[1], "UNIT_CONNECTION", "party aura connection event")
    Equal(events[2], "UNIT_IN_RANGE_UPDATE", "party aura range event")

    A3._directIdentityAuraContainers = nil
    Check(AurasElement.IsEnabled(frame) == true, "party aura access config did not enable")
    Check(AurasElement.Enable(frame) == true, "party aura access runtime did not enable")
    local containers = assert(A3._directIdentityAuraContainers.party1,
        "party aura containers were not indexed by unit")
    local containerCount = 0
    local geometry = {}
    local function TotalUpdates()
        local total = 0
        for container in pairs(containers) do
            total = total + (container.updateAllAurasCalls or 0)
        end
        return total
    end
    for container in pairs(containers) do
        containerCount = containerCount + 1
        geometry[container] = {
            clears = container.clearAllPointsCalls or 0,
            points = container.setPointCalls or 0,
        }
    end
    Check(containerCount > 0, "party aura access runtime created no native containers")

    local rangeUpdate = AurasElement.SelectEventUpdate(frame, frame.MSUFSpec,
        "UNIT_IN_RANGE_UPDATE", AurasElement.Update)
    Equal(rangeUpdate, AurasElement.UpdatePartyAuraAccess,
        "party range event did not select its secret-safe refresh route")
    local updates = TotalUpdates()
    rangeUpdate(frame, "UNIT_IN_RANGE_UPDATE", {}, {})
    Equal(TotalUpdates(), updates + containerCount,
        "party range transition did not refresh every native container exactly once")

    local connectionUpdate = AurasElement.SelectEventUpdate(frame, frame.MSUFSpec,
        "UNIT_CONNECTION", AurasElement.Update)
    Equal(connectionUpdate, AurasElement.UpdatePartyAuraAccess,
        "party connection event did not select its refresh route")
    updates = TotalUpdates()
    connectionUpdate(frame, "UNIT_CONNECTION", {}, false)
    Equal(TotalUpdates(), updates + containerCount,
        "party connection transition did not refresh every native container exactly once")

    local current = assert(A3._directIdentityAuraContainers.party1)
    local currentCount = 0
    for container in pairs(current) do
        currentCount = currentCount + 1
        Check(containers[container] == true, "party access refresh replaced a native container")
        Equal(container.clearAllPointsCalls or 0, geometry[container].clears,
            "party access refresh repeated container clear-point geometry")
        Equal(container.setPointCalls or 0, geometry[container].points,
            "party access refresh repeated container point geometry")
    end
    Equal(currentCount, containerCount, "party access refresh changed native container count")

    local preview = NewFrame(nil)
    preview.unit = "party1"
    preview.MSUFUnitKey = "party1"
    preview._msufGFKind = "party"
    preview._msufGFIsPreviewFrame = true
    Equal(#AurasElement.GetEvents(preview), 0, "party preview registered aura access events")

    local raid = NewFrame(nil)
    raid.unit = "raid1"
    raid.MSUFUnitKey = "raid1"
    raid._msufGFKind = "raid"
    Equal(#AurasElement.GetEvents(raid), 0, "raid registered party aura access events")

    local target = NewFrame(nil)
    target.unit = "target"
    target.MSUFUnitKey = "target"
    Equal(#AurasElement.GetEvents(target), 0, "single unit registered party aura access events")
end

-- Native maximum-duration filtering is compiled once into every Debuff
-- AuraContainer. Zero keeps the filter disabled; corrupt/out-of-range profile
-- values are clamped to the menu's 180-second ceiling.
do
    local function ResolveUnit(blacklist)
        _G.MSUF_DB = {
            auras3 = {
                enabled = true,
                showPlayer = true,
                shared = { showBuffs = false, showDebuffs = true, maxDebuffs = 3 },
                perUnit = { player = { blacklist = { debuffs = blacklist } } },
            },
        }
        A3._runtimeConfigGen = (A3._runtimeConfigGen or 1) + 1
        return assert(A3.ResolveUnitFrameConfig("player", {})).lanes.debuff
    end

    local limited = assert(ResolveUnit({ maxDuration = 61 }))
    Equal(assert(limited.candidateFilters).maxDuration, 61, "unit Debuff maximum duration")

    local clamped = assert(ResolveUnit({ maxDuration = 999 }))
    Equal(assert(clamped.candidateFilters).maxDuration, 180, "unit Debuff maximum duration clamp")

    local unlimited = assert(ResolveUnit({ maxDuration = 0 }))
    Check(unlimited.candidateFilters == nil or unlimited.candidateFilters.maxDuration == nil,
        "zero unit Debuff maximum duration still filters")

    local permanentHidden = assert(ResolveUnit({ maxDuration = 0, hidePermanent = true }))
    Check(assert(permanentHidden.candidateFilters).maxDuration > 180,
        "Hide Permanent no longer retains its finite-ceiling candidate filter")

    _G.MSUF_DB = {
        auras3 = {
            enabled = true,
            showPlayer = false,
            customContainers = {
                perUnit = {
                    player = {
                        items = {
                            {
                                enabled = true,
                                auraType = "DEBUFF",
                                spellIDs = "12345",
                                filters = { maxDuration = 44 },
                                placed = { max = 1 },
                            },
                        },
                    },
                },
            },
        },
    }
    A3._runtimeConfigGen = (A3._runtimeConfigGen or 1) + 1
    local custom = assert(assert(A3.ResolveUnitFrameConfig("player", {})).lanes.custom1)
    Equal(assert(custom.candidateFilters).maxDuration, 44, "custom Debuff maximum duration")

    A3.TargetDotData = { ROGUE = { { 703, "Garrote" } } }
    A3._targetDotRuntimeLookup = nil
    _G.MSUF_DB = {
        auras3 = {
            enabled = true,
            showPlayer = false,
            customContainers = {
                perUnit = {
                    player = {
                        items = {
                            [4] = {
                                enabled = true,
                                targetDots = true,
                                auraType = "DEBUFF",
                                spellIDs = "703,17",
                                filters = { enabled = true, onlyMine = true },
                                placed = { max = 1 },
                            },
                        },
                    },
                },
            },
        },
    }
    A3._runtimeConfigGen = (A3._runtimeConfigGen or 1) + 1
    local targetDots = assert(assert(A3.ResolveUnitFrameConfig("player", {})).lanes.custom4)
    Equal(targetDots.unit, "target", "target DoT source unit")
    Equal(targetDots.nativeFilter, "HARMFUL|PLAYER", "target DoT native ownership filter")
    Check(assert(targetDots.candidateFilters).includeSpellIDs[703] == true,
        "curated Garrote target DoT was not compiled")
    Check(targetDots.candidateFilters.includeSpellIDs[17] == nil,
        "non-DoT spell escaped the runtime target DoT registry")
    _G.MSUF_DB.auras3.customContainers.perUnit.player.items[4].customSpellIDs = { [17] = true }
    A3._runtimeConfigGen = (A3._runtimeConfigGen or 1) + 1
    local manualTargetDots = assert(assert(A3.ResolveUnitFrameConfig("player", {})).lanes.custom4)
    Check(assert(manualTargetDots.candidateFilters).includeSpellIDs[17] == true,
        "manually approved target DoT ID was removed by the runtime registry guard")
    local targetDotMetrics = assert(A3.BuildAuraLaneMetrics("player", "custom4"))
    Equal(targetDotMetrics.num, 1, "custom4 lane metrics")

    local groupFrame = NewFrame(nil)
    groupFrame.unit = "party1"
    groupFrame.MSUFUnitKey = "party1"
    groupFrame._msufIsGroupFrame = true
    groupFrame.MSUFSpec = {
        auras = {
            enabled = true,
            showDebuffs = true,
            maxDebuffs = 3,
            debuffMaxDuration = 47,
        },
    }
    Check(AurasElement.IsEnabled(groupFrame) == true, "group Debuff duration config did not enable")
    local groupDebuff = assert(assert(groupFrame._msufA3NativeGroupConfig).lanes.debuff)
    Equal(assert(groupDebuff.candidateFilters).maxDuration, 47, "group Debuff maximum duration")
end

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
        CustomContainerSpellEntries = function(_, index)
            if index == 4 then
                return {
                    { spellID = 703, icon = 100703 },
                    { spellID = 1943, icon = 101943 },
                }
            end
            return {}
        end,
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
            Metrics(anchor, 3, 4), Metrics(anchor, -6, 9), Metrics(anchor, 12, -7), Metrics(anchor, -9, -10),
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
        for index = 1, 4 do
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
        local function AssertPreviewLane(bounds, metrics, label, expectedShown)
            Near(bounds.laneLeft, frac[1] * 200 + metrics.x - frac[1] * metrics.width,
                label .. " left")
            Near(bounds.laneBottom, frac[2] * 100 + metrics.y - frac[2] * metrics.height,
                label .. " bottom")
            Near(bounds.laneW, metrics.width, label .. " full-capacity width")
            Near(bounds.laneH, metrics.height, label .. " full-capacity height")
            Equal(bounds.shown, expectedShown or 4, label .. " sample count")
        end
        AssertPreviewLane(state.buff, buffMetrics, "unit preview buff " .. anchor)
        AssertPreviewLane(state.debuff, debuffMetrics, "unit preview debuff " .. anchor)
        for index = 1, 4 do
            AssertPreviewLane(state["custom" .. tostring(index)], customMetrics[index],
                "unit preview custom" .. tostring(index) .. " " .. anchor, index == 4 and 2 or 4)
        end
        Equal(state.custom4.previewTextures[1], 100703,
            "unit preview custom4 did not use the first tracked DoT icon")
        Equal(state.custom4.previewTextures[2], 101943,
            "unit preview custom4 did not use the second tracked DoT icon")
    end

    customItems[4].enabled = false
    local selectedWhileDisabled = assert(previewAuras.BuildState("player", 200, 100).custom4)
    Equal(selectedWhileDisabled.shown, 2,
        "selected target DoTs did not reveal the disabled unit-frame preview lane")
    customItems[4].enabled = true

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

    customItems[1].placed.growth = "UP"
    local verticalFallback = assert(previewAuras.BuildState("player", 200, 100).custom1)
    Near(verticalFallback.laneW, 10, "vertical custom preview fallback width")
    Near(verticalFallback.laneH, 70, "vertical custom preview fallback full-capacity height")
    Near(verticalFallback.laneLeft, 200 - 2 - 10, "vertical custom preview fallback anchored X")
    Near(verticalFallback.laneBottom, 50 + 5 - 35, "vertical custom preview fallback anchored Y")
end

-- Static integration guards: live, Edit Mode, Menu2 unit/group previews, and
-- the group External lane all preserve the same full-capacity rectangle and
-- selected-anchor/internal-flow split.
local runtimeSource = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_UnitFrames.lua")
local coreSource = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Core.lua")
local eventElementsStart = assert(coreSource:find("local EVENT_ELEMENTS = {", 1, true))
local eventElementsStop = assert(coreSource:find("local STATUS_EVENT_ELEMENTS = {", eventElementsStart, true))
Check(coreSource:sub(eventElementsStart, eventElementsStop):find("Auras = true", 1, true),
    "Auras element is not admitted to the core event router")
Check(runtimeSource:find("layoutHost:SetPoint(lane.anchor, parentFrame, lane.anchor, lane.x, lane.y)", 1, true),
    "live lane host no longer anchors its bounding box with lane.anchor")
Check(runtimeSource:find("SetAuraLayoutAnchorPoint", 1, true), "native layout anchor setter missing")
Check(runtimeSource:find("SetAuraLayoutGrowthDirection", 1, true), "native growth setter missing")
Check(runtimeSource:find("SetAuraLayoutRowWidth", 1, true), "native row-width setter missing")
Check(runtimeSource:find("lane.verticalGrowth == true", 1, true)
    and runtimeSource:find("and (lane.size or 1) or (lane.width or lane.size or 1)", 1, true),
    "native vertical layout no longer forces one-icon rows")
Check(Count(runtimeSource, "initialAnchor = ButtonAnchor(xSign, ySign)") >= 2,
    "unit/group compilers no longer share initial-anchor derivation")
Check(runtimeSource:find("local NativeRuntime = (function()", 1, true),
    "native backend no longer has an isolated local-budget boundary")
Check(Count(runtimeSource, "EnsureAuraTextOverlay(button) or button") == 1
    and not runtimeSource:find("SyncButtonGeometry", 1, true)
    and not runtimeSource:find("SyncCooldownTextLayering", 1, true),
    "AuraButton initialization regained duplicate overlay or geometry work")
Check(runtimeSource:find('lane._msufA3DurationFormatter', 1, true)
    and runtimeSource:find('button:SetApplicationCount(count, _applicationCountOptions)', 1, true)
    and runtimeSource:find('button:SetAuraSymbol(symbol, _auraSymbolOptions)', 1, true),
    "AuraButton initialization no longer reuses formatter and option state")
Check(runtimeSource:find('texture._msufA3IconZoomKey == zoom', 1, true)
    and not runtimeSource:find('local key = tostring(zoom)', 1, true),
    "Aura Icon Zoom regained its per-call string allocation")
Check(not runtimeSource:find("ApplyVerticalAwareAuraLayout", 1, true)
    and not runtimeSource:find("InstallVerticalAuraLayoutFallback", 1, true),
    "PTR 5 runtime still overrides Blizzard's native ApplyLayout")
Check(runtimeSource:find("container._msufA3LayoutHost = host", 1, true),
    "fixed native-layout host is missing")
Check(not runtimeSource:find("container.ApplyLayout =", 1, true),
    "PTR 5 runtime assigns a tainted ApplyLayout wrapper")
Check(runtimeSource:find('filter = filter .. "|DISPELLABLE"', 1, true)
    and runtimeSource:find('filter = filter .. "|IMPORTANT"', 1, true),
    "PTR 5 DISPELLABLE/IMPORTANT native filters are missing")
Check(runtimeSource:find('return "HARMFUL|RAID", 1', 1, true)
    and runtimeSource:find('return "HARMFUL|RAID_PLAYER_DISPELLABLE", 1', 1, true)
    and runtimeSource:find('return "HARMFUL|DISPELLABLE", 3', 1, true),
    "dispel trigger modes no longer map to the three distinct PTR 5 filters")
Check(runtimeSource:find("player = true", 1, true),
    "player aura containers are no longer eligible for world repair")
Check(runtimeSource:find("A3._SyncManagedAuraContainerGeometry", 1, true),
    "generic managed-aura world repair dispatcher missing")

local spellIndicatorSource = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_SpellIndicators.lua")
Check(not spellIndicatorSource:find("hooksecurefunc(source", 1, true),
    "PTR 5 spell indicators retain a post-initializer write hook into forbidden AuraButton descendants")
Check(not spellIndicatorSource:find("for button in pairs(buttons) do HideButton", 1, true),
    "PTR 5 spell indicator teardown still calls APIs on initialized AuraButtons")

local editModeSource = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_EditMode.lua")
Check(editModeSource:find('group:SetFrameStrata("FULLSCREEN")', 1, true),
    "Edit Mode Aura preview is no longer kept below the Menu2 edit-mode strata")
Check(editModeSource:find('return IsEditModeActive() and rawget(_G, "MSUF_UnitPreviewActive") == true', 1, true),
    "Edit Mode Aura previews ignore the global Preview toggle")
Check(editModeSource:find("if not UnitPreviewActive(unit) then", 1, true)
    and editModeSource:find("if not UnitPreviewActive() then", 1, true),
    "Aura preview refresh paths do not immediately hide when Preview is off")
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
Check(unitPreviewSource:find("if vertical then return 1, count end", 1, true),
    "unit preview no longer mirrors single-column vertical growth")
Check(unitPreviewSource:find("ApplyIconZoom(icon.tex, bounds.iconZoom)", 1, true),
    "unit-frame preview does not mirror scoped Aura Icon Zoom")

local menuModelSource = Read("MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Menu_Model.lua")
Check(menuModelSource:find("TOPLEFT=true, TOP=true, TOPRIGHT=true", 1, true)
    and menuModelSource:find("LEFT=true, CENTER=true, RIGHT=true", 1, true)
    and menuModelSource:find("BOTTOMLEFT=true, BOTTOM=true, BOTTOMRIGHT=true", 1, true),
    "unit aura menu model no longer accepts all nine anchors")
Check(menuModelSource:find("customMetrics[index] = buildMetrics", 1, true),
    "unit aura preview no longer consumes compiled custom-lane metrics")
Check(menuModelSource:find('text = "Up (Single Column)"', 1, true)
    and menuModelSource:find('text = "Down (Single Column)"', 1, true),
    "unit aura menu no longer exposes explicit vertical growth choices")
Check(menuModelSource:find('iconZoom = "buffIconZoom"', 1, true)
    and menuModelSource:find('iconZoom = "debuffIconZoom"', 1, true)
    and menuModelSource:find('buffIconZoom = buffMetrics and buffMetrics.iconZoom', 1, true),
    "unit Aura Icon Zoom no longer follows Shared/unit and Buff/Debuff scopes")

local aurasMenuSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_Auras.lua")
Check(not aurasMenuSource:find('BindDropdown(ctx, section, "Exclusive"', 1, true)
    and not aurasMenuSource:find("DEBUFF_EXCLUSIVE", 1, true),
    "redundant Exclusive/Raid dropdown returned to the compact Aura filters")
Check(aurasMenuSource:find('Model.ReadFilter(unit, lane, "exclusive", "none") == "raid"', 1, true)
    and aurasMenuSource:find('Model.WriteFilter(unit, lane, "exclusive", "none")', 1, true),
    "legacy Exclusive=Raid profiles are no longer bridged by the visible Raid switch")
Check(aurasMenuSource:find('"Maximum duration", 24, -142, 0, 180, 1', 1, true)
    and aurasMenuSource:find('"Maximum duration", 24, -78 - optionRows * 32, 0, 180, 1', 1, true)
    and aurasMenuSource:find('"Maximum duration", 24, -140, 0, 180, 1', 1, true),
    "unit, group, and custom Debuff filters no longer expose the 0-180 second slider")
Check(aurasMenuSource:find('BindStyleSlider(features, "Icon Zoom (%)"', 1, true)
    and aurasMenuSource:find('ApplyAuraPreviewIconZoom(icon.icon, cfg.iconZoom)', 1, true),
    "unit Aura Style lacks its scope-aware Icon Zoom slider or sample preview")
Check(runtimeSource:find('local zoomDefault = ReadRaw(layout, shared, spec.iconZoomKey)', 1, true)
    and runtimeSource:find('iconZoom = ClampNumber(zoomDefault, DEFAULT_SHARED.iconZoom, 100, 200)', 1, true),
    "unit Aura runtime does not compile scoped Icon Zoom")
Check(editModeSource:find('ApplyIconZoom(icon.Icon, metrics and metrics.iconZoom or cfg.iconZoom)', 1, true),
    "Edit Mode Aura preview does not mirror scoped Icon Zoom")
local defaultsSource = Read("MidnightSimpleUnitFrames/State/MSUF_Defaults.lua")
local profilesSource = Read("MidnightSimpleUnitFrames/State/MSUF_Profiles.lua")
Check(defaultsSource:find('iconZoom = { 100, 200 }, buffIconZoom = { 100, 200 }, debuffIconZoom = { 100, 200 }', 1, true)
    and profilesSource:find('buffIconZoom = { 100, 200 }', 1, true)
    and profilesSource:find('debuffIconZoom = { 100, 200 }', 1, true),
    "unit Aura Icon Zoom is missing from defaults/profile normalization")

Check(menuModelSource:find("function Model.WriteBlacklistMaxDuration", 1, true)
    and menuModelSource:find("function Model.WriteGroupBlacklistMaxDuration", 1, true),
    "Debuff maximum-duration menu persistence helpers are missing")

local groupConfigSource = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua")
Check(groupConfigSource:find("out.debuffMaxDuration = Num(blacklist and blacklist.maxDuration, 0)", 1, true),
    "group Debuff maximum duration no longer reaches the native AuraContainer compiler")

local groupPreviewSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Render.lua")
Check(groupPreviewSource:find("handle:SetPoint(anchor, mock, anchor", 1, true),
    "group preview no longer anchors lane bounds with the selected anchor")
Check(groupPreviewSource:find("tex:SetPoint(rect.anchor, handle, rect.anchor, rect[1], rect[2])", 1, true),
    "group preview no longer flows icons from initialAnchor")
Check(groupPreviewSource:find("if GF_PREVIEW_ANCHOR_FRAC[anchor] then return anchor end", 1, true),
    "group aura preview no longer accepts all nine runtime anchors")
Check(groupPreviewSource:find('LayoutAuraGroup(externalHandle, "external", externalCfg', 1, true),
    "group External aura lane is missing from the preview renderer")
Check(groupConfigSource:find("iconZoom = Num(root and root.iconZoom, 100)", 1, true),
    "Group Aura root Icon Zoom is missing from the compiled scope")
Check(runtimeSource:find("iconZoom = ClampNumber(source.iconZoom, 100, 100, 200)", 1, true)
    and runtimeSource:find("ApplyAuraIconZoom(icon, lane)", 1, true)
    and runtimeSource:find('tostring(lane.iconZoom)', 1, true),
    "Group Aura Icon Zoom is missing from the live cold-layout contract")
Check(groupPreviewSource:find("ApplyPreviewIconZoom(tex, cfg.iconZoom or scene.auraIconZoom, 0)", 1, true),
    "Group Aura preview does not mirror the scope-wide Icon Zoom")
local groupAuraMenuSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupAuras.lua")
Check(groupAuraMenuSource:find('W.Slider(rootSection, "Icon Zoom (%)", 100, 200, 1', 1, true)
    and groupAuraMenuSource:find('GroupAuraSettingKeys(scope, ".auras.iconZoom")', 1, true),
    "Group Aura scope-aware Icon Zoom slider is missing")

local groupHandlesSource = Read("MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua")
Check(groupHandlesSource:find("return ResolveAnchor(rx, ry)", 1, true),
    "group aura drag no longer resolves through the nine-anchor helper")
Check(groupHandlesSource:find('externalHandle._cfgGroup = "externals"', 1, true),
    "group External aura handle no longer writes its persisted lane")

print("PASS aura position parity: 54 unit + 216 group live layouts, 54 unit preview lanes, scope-aware icon zoom, vertical fallback, PTR5 forbidden-button guard, fixed host capacity, player/dispel zone repair, 1000x native churn")
