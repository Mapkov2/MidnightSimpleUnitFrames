-- Classic aura backend: settings the shared menu offers on every client reach
-- the Classic lanes the way Retail compiles them. Runs the real backend chain
-- of one Classic flavor in its TOC order with counting stubs.
--   * a corner Custom Spell slot scans with its Filter (buff or debuff, any
--     caster or cast by me), as Retail scans customFilter
--   * a custom container keeps its Cooldown swipe with Cooldown text off
--   * Up/Down (Single Column) growth keeps one column on unit and container lanes
--   * portrait icons past the first grow in the lane's Growth direction
--   * group Tracked and External lanes wear the Buff appearance (shape, border, shadow)
-- Arguments: repository root, flavor (Vanilla, TBC or Mists).
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))
local flavor = assert(arg[2], "flavor argument missing")
local PROJECT_IDS = { Vanilla = 2, TBC = 5, Mists = 19 }
assert(PROJECT_IDS[flavor], "unknown Classic flavor: " .. tostring(flavor))
_G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_CLASSIC = 1, 2
_G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, _G.WOW_PROJECT_MISTS_CLASSIC = 5, 19
_G.WOW_PROJECT_ID = PROJECT_IDS[flavor]
_G.C_AddOns = { GetAddOnMetadata = function(_, field)
    if field == "X-MSUF-Client" then return flavor end
    return nil
end }
_G.C_EventUtils = { IsEventValid = function() return true end }

local registered
local namespace = {
    MSUF_Auras3 = {},
    UF = { RegisterElement = function(_, element) registered = element end },
    ExportPublic = function(name, value) _G[name] = value; return value end,
    MSUF_GetGlobalFontSettings = function() return "Fonts\\FRIZQT__.TTF", "OUTLINE", 1, 1, 1, nil, false end,
}
_G.MSUF_NS, _G.MSUF = namespace, namespace
_G.issecretvalue = function() return false end
-- Read by the group indicator compiler.
_G.MSUF_GetGeneralDB = function() return {} end
_G.MSUF_NormalizeFrameStrata = function(value, fallback) return value or fallback end

-- Widget stub: frames remember their anchors -----------------------------------------------
local Widget = {}
Widget.__index = Widget
function Widget:Show() self._shown = true end
function Widget:Hide() self._shown = false end
function Widget:SetShown(shown) self._shown = shown == true end
function Widget:IsShown() return self._shown == true end
function Widget:IsVisible() return self._shown == true end
function Widget:IsForbidden() return false end
function Widget:SetParent(parent) self._parent = parent end
function Widget:GetParent() return self._parent end
function Widget:SetFrameLevel(level) self._frameLevel = level end
function Widget:GetFrameLevel() return self._frameLevel or 1 end
function Widget:SetScript(name, handler) self._scripts = self._scripts or {}; self._scripts[name] = handler end
function Widget:HookScript(name, handler) self:SetScript(name, handler) end
function Widget:GetObjectType() return self._objectType or "Frame" end
function Widget:ClearAllPoints() self._point = nil end
function Widget:SetPoint(point, relativeTo, relativePoint, x, y)
    self._point = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y }
end
function Widget:SetDrawSwipe(draw) self._drawSwipe = draw end
function Widget:SetHideCountdownNumbers(hide) self._hideNumbers = hide end
function Widget:SetCooldown(start, duration) self._start, self._duration = start, duration end
function Widget:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "OUTLINE" end
function Widget:GetNumRegions() return 0 end
function Widget:GetRegions() return nil end
function Widget:CreateTexture() return setmetatable({ _shown = true, _parent = self, _objectType = "Texture" }, Widget) end
Widget.CreateMaskTexture = Widget.CreateTexture
function Widget:CreateFontString() return setmetatable({ _shown = true, _parent = self, _objectType = "FontString" }, Widget) end
for _, name in ipairs({
    "RegisterEvent", "UnregisterEvent", "RegisterUnitEvent", "SetAllPoints", "SetAlpha", "EnableMouse", "SetSize",
    "SetWidth", "SetHeight", "SetSwipeColor", "SetDrawEdge", "SetTexCoord", "SetJustifyH", "SetJustifyV",
    "SetFont", "SetTextColor", "SetShadowOffset", "SetDesaturated", "SetBlendMode", "SetMinMaxValues", "SetValue",
    "SetStatusBarTexture", "SetStatusBarColor", "SetColorTexture", "SetReverse", "SetMouseClickEnabled",
    "SetMouseMotionEnabled", "SetCountdownMillisecondsThreshold", "SetSwipeTexture", "SetFrameStrata", "SetOwner",
    "Clear", "SetAtlas", "AddMaskTexture", "RemoveMaskTexture", "SetTexture", "SetText", "SetVertexColor",
}) do
    Widget[name] = Widget[name] or function() end
end
_G.CreateFrame = function(frameType, _, parent)
    return setmetatable({ _shown = true, _parent = parent, _objectType = frameType }, Widget)
end

-- Aura API stub: Classic filter semantics, |PLAYER keeps the player's own casts ------------
local world = {}
local function UnitList(unit) world[unit] = world[unit] or {}; return world[unit] end
local function Matches(aura, filter)
    if filter:find("HARMFUL", 1, true) then
        if aura.isHarmful ~= true then return false end
    elseif aura.isHelpful ~= true then
        return false
    end
    if filter:find("|PLAYER", 1, true) and aura.mine ~= true then return false end
    return true
end
_G.UnitExists = function() return true end
_G.UnitIsUnit = function(a, b) return a == b end
_G.UnitInRange = function() return true, true end
_G.UnitCanAssist = function() return true end
_G.UnitGUID = function(unit) return "GUID-" .. unit end
_G.GetTime = function() return 50 end
_G.InCombatLockdown = function() return false end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.GameTooltip = setmetatable({}, Widget)
_G.C_Timer = {}
_G.GetSpellInfo = function(spellID) return "Spell" .. tostring(spellID) end
_G.C_UnitAuras = {
    GetAuraSlots = function(unit, filter)
        local list, out = UnitList(unit), {}
        for i = 1, #list do if Matches(list[i], filter) then out[#out + 1] = i end end
        return nil, unpack(out)
    end,
    GetAuraDataBySlot = function(unit, slot) return UnitList(unit)[slot] end,
    GetAuraDataByAuraInstanceID = function(unit, id)
        for _, aura in ipairs(UnitList(unit)) do if aura.auraInstanceID == id then return aura end end
        return nil
    end,
    GetAuraDataByIndex = function(unit, index, filter)
        local n = 0
        for _, aura in ipairs(UnitList(unit)) do
            if Matches(aura, filter) then n = n + 1; if n == index then return aura end end
        end
        return nil
    end,
}
_G.AuraUtil = {}
_G.MSUF_DB = { general = {}, auras3 = { enabled = true, shared = {}, perUnit = {} } }

local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
manifest.LoadSelected(root, flavor, namespace, {
    "Game/Shared/Initialize.lua",
    "State/MSUF_AuraDefaults.lua",
    "Auras3/MSUF_Auras3_Core.lua", "Auras3/MSUF_Auras3_IconShape.lua", "Game/Classic/Auras/MSUF_Auras3_DataShared.lua",
    "Game/Classic/Auras/MSUF_Auras3_Visuals.lua", "Game/Classic/Auras/MSUF_Auras3_Features.lua",
    "Game/Classic/Auras/MSUF_Auras3_Compile.lua",
    "Game/Classic/Auras/MSUF_Auras3_Buttons.lua", "Game/Classic/Auras/MSUF_Auras3_Filters.lua",
    "Game/Classic/Auras/MSUF_Auras3_FrameVisuals.lua", "Game/Classic/Auras/MSUF_Auras3_Lanes.lua",
    "Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua", "Game/Classic/Auras/MSUF_Auras3_Requests.lua",
    "UnitFrames/Engine/Group/MSUF_UF_Group_Config_Indicators.lua",
})
assert(registered, "the Classic aura element did not register")
local A3 = namespace.MSUF_Auras3
local GF = assert(namespace.GF and namespace.GF.CompileCornerIndicators, "group corner compiler missing") and namespace.GF

local function SetAuras(unit, auras)
    local list = UnitList(unit)
    for i = #list, 1, -1 do list[i] = nil end
    for i = 1, #auras do list[i] = auras[i] end
end
local function GroupFrame(unit, spec)
    spec.scope = "group"
    local frame = setmetatable({ _shown = true, MSUFUnitKey = unit, _msufIsGroupFrame = true,
        _msufGFKind = "party", MSUFSpec = spec }, Widget)
    registered.Create(frame)
    registered.Apply(frame)
    assert(registered.Enable(frame) == true, "the group aura element did not enable for " .. unit)
    return frame
end
local function ShownIDs(lane)
    local ids = {}
    for i = 1, lane and lane.visible or 0 do
        local button = lane[i]
        if button and button._msufA3Shown == true then ids[#ids + 1] = tostring(button.auraInstanceID) end
    end
    return table.concat(ids, ",")
end

-- 1. Corner Custom Spell slot: its Filter decides buff or debuff and the caster ----------
-- The menu stores conf.ciCustom<slot>.filter (GF.CI_CUSTOM_FILTERS); the group
-- compiler hands it on as customFilter.
local function CornerLane(filter, spells, auras)
    SetAuras("party1", auras)
    local corners = GF.CompileCornerIndicators({
        ciEnabled = true, ciSlotTL = "custom", ciSlotTR = "none", ciSlotBL = "none", ciSlotBR = "none", ciSlotC = "none",
        ciCustomTL = { spells = spells, mode = "present", filter = filter, r = 0.4, g = 1, b = 0.4 },
    }, "party")
    assert(corners.customSlots[1].customFilter == filter, "precondition: the corner slot lost its Filter")
    local frame = GroupFrame("party1", { cornerIndicators = corners })
    return assert(frame._msufA3State.lanes.cornerIndicator1, "the corner Custom Spell lane did not compile")
end
local otherRenew = { auraInstanceID = 501, spellId = 139, name = "Spell139", icon = 1, duration = 15,
    expirationTime = 60, isHelpful = true, isHarmful = false, mine = false, sourceUnit = "party2" }
local ownRenew = { auraInstanceID = 502, spellId = 139, name = "Spell139", icon = 1, duration = 15,
    expirationTime = 60, isHelpful = true, isHarmful = false, mine = true, sourceUnit = "player",
    isFromPlayerOrPlayerPet = true }
local otherPain = { auraInstanceID = 503, spellId = 589, name = "Spell589", icon = 2, duration = 18,
    expirationTime = 60, isHelpful = false, isHarmful = true, mine = false, sourceUnit = "target" }
local ownPain = { auraInstanceID = 504, spellId = 589, name = "Spell589", icon = 2, duration = 18,
    expirationTime = 60, isHelpful = false, isHarmful = true, mine = true, sourceUnit = "player",
    isFromPlayerOrPlayerPet = true }
assert(ShownIDs(CornerLane("HELPFUL|PLAYER", "139", { otherRenew })) == "",
    "Buff (cast by me): another priest's Renew lit the corner")
assert(ShownIDs(CornerLane("HELPFUL|PLAYER", "139", { otherRenew, ownRenew })) == "502",
    "Buff (cast by me): the player's own Renew did not light the corner")
assert(ShownIDs(CornerLane("HELPFUL", "139", { otherRenew })) == "501",
    "Buff (any caster): another priest's Renew did not light the corner")
assert(ShownIDs(CornerLane("HARMFUL", "589", { otherPain })) == "503",
    "Debuff (any caster): the debuff did not light the corner")
assert(ShownIDs(CornerLane("HARMFUL|PLAYER", "589", { otherPain })) == "",
    "Debuff (cast by me): another caster's debuff lit the corner")
assert(ShownIDs(CornerLane("HARMFUL|PLAYER", "589", { otherPain, ownPain })) == "504",
    "Debuff (cast by me): the player's own debuff did not light the corner")

-- 2. Custom container: Cooldown text and Cooldown swipe are independent switches ----------
-- (MSUF_Menu2_Auras_CustomWorkspace.lua writes placed.showCooldown and
-- placed.showCooldownSwipe; Retail compiles each on its own, CustomConfig.)
_G.MSUF_DB.auras3.showTarget = true
_G.MSUF_DB.auras3.perUnit.target = { layout = {}, filters = {}, layoutShared = { showBuffs = false, showDebuffs = false } }
local containerPlaced = { size = 20, max = 4, perRow = 4, showCooldown = false, showCooldownSwipe = true }
_G.MSUF_DB.auras3.customContainers = { perUnit = { target = { items = {
    [1] = { enabled = true, auraType = "BUFF", spellIDs = "777001", placed = containerPlaced, filters = {} },
} } } }
SetAuras("target", { { auraInstanceID = 601, spellId = 777001, name = "Spell777001", icon = 3, duration = 30,
    expirationTime = 65, isHelpful = true, isHarmful = false, mine = false } })
local function UnitFrame(unit)
    local frame = setmetatable({ _shown = true, MSUFUnitKey = unit, _msufActiveElements = { Auras = true },
        MSUFSpec = {} }, Widget)
    registered.Create(frame)
    assert(registered.Enable(frame) == true, "the aura element did not enable for " .. unit)
    return frame
end
local function ContainerCooldown()
    A3.BumpRuntimeConfig()
    local lane = assert(UnitFrame("target")._msufA3State.lanes.custom1, "the custom container lane did not compile")
    assert(ShownIDs(lane) == "601", "precondition: the custom container does not show its aura")
    return lane[1].Cooldown
end
local cooldown = ContainerCooldown()
assert(cooldown._shown == true and cooldown._drawSwipe == true and cooldown._start == 35,
    "Cooldown text off hid the custom container's Cooldown swipe")
assert(cooldown._hideNumbers == true, "Cooldown text off still showed the countdown numbers")
containerPlaced.showCooldownSwipe = false
cooldown = ContainerCooldown()
assert(cooldown._shown == false, "a custom container with text and swipe off still showed its Cooldown")
containerPlaced.showCooldown, containerPlaced.showCooldownSwipe = true, false
cooldown = ContainerCooldown()
assert(cooldown._shown == true and cooldown._drawSwipe == false and cooldown._hideNumbers == false,
    "Cooldown swipe off hid the custom container's countdown text")

-- 3. Up/Down (Single Column) growth lays out one column -----------------------------------
-- The menus label it "Single Column" and grey out Per row for it; the hidden
-- Per row value must not wrap the icons into more columns.
local function Column(lane, label)
    local x
    for i = 1, lane.visible do
        local point = assert(lane[i]._point, label .. ": icon " .. i .. " was never placed")
        x = x or point.x
        assert(point.x == x, label .. ": icon " .. i .. " left the column (x " .. tostring(point.x) .. ")")
        assert(math.abs(point.y) == (i - 1) * lane.config.stepY,
            label .. ": icon " .. i .. " is not one step below the previous (y " .. tostring(point.y) .. ")")
    end
end
local column = {}
for i = 1, 8 do
    column[i] = { auraInstanceID = 700 + i, spellId = 777001, name = "Spell777001", icon = 3, duration = 30,
        expirationTime = 60 + i, isHelpful = true, isHarmful = false, mine = false }
end
SetAuras("target", column)
containerPlaced.showCooldown, containerPlaced.showCooldownSwipe = true, true
containerPlaced.size, containerPlaced.spacing, containerPlaced.max, containerPlaced.perRow = 24, 2, 8, 4
for _, growth in ipairs({ "UP", "DOWN" }) do
    containerPlaced.growth = growth
    A3.BumpRuntimeConfig()
    local lane = UnitFrame("target")._msufA3State.lanes.custom1
    assert(lane.visible == 8, "precondition: the custom container does not show eight auras")
    assert(lane.config.cols == 1 and lane.config.rows == 8 and lane.config.width == 24 and lane.config.height == 206,
        "custom container " .. growth .. ": the lane is " .. lane.config.cols .. " columns by " .. lane.config.rows .. " rows")
    Column(lane, "custom container " .. growth)
end
_G.MSUF_DB.auras3.customContainers = nil
_G.MSUF_DB.auras3.perUnit.target.layoutShared = {
    showBuffs = true, showDebuffs = false, maxBuffs = 8, buffPerRow = 4, buffGrowthX = "DOWN",
}
A3.BumpRuntimeConfig()
local buffLane = UnitFrame("target")._msufA3State.lanes.buff
assert(buffLane.visible == 8 and buffLane.config.cols == 1 and buffLane.config.rows == 8,
    "target buffs Down: the lane is " .. buffLane.config.cols .. " columns by " .. buffLane.config.rows .. " rows")
Column(buffLane, "target buffs Down")
_G.MSUF_DB.auras3.perUnit.target.layoutShared = { showBuffs = false, showDebuffs = false }

-- 4. Portrait icons grow in the lane's Growth direction ------------------------------------
-- Icon 1 covers the portrait; the menu promises that further icons grow
-- outward in the lane's configured Growth (CustomWorkspace portrait tooltip).
_G.MSUF_DB.auras3.showPlayer = true
_G.MSUF_DB.auras3.perUnit.player = { layout = {}, filters = {}, layoutShared = { showBuffs = false, showDebuffs = false } }
local portraitPlaced = { size = 24, spacing = 2, max = 8, perRow = 4 }
_G.MSUF_DB.auras3.customContainers = { perUnit = { player = { items = {
    [A3.PRESET_CUSTOM_CONTAINER_INDEX] = { enabled = true, playerDefensives = true, portraitIcon = true,
        portraitMaxIcons = 3, spellIDs = "871 33206", placed = portraitPlaced, filters = {} },
} } } }
SetAuras("player", {
    { auraInstanceID = 801, spellId = 871, name = "Spell871", icon = 4, duration = 12, expirationTime = 60,
        isHelpful = true, isHarmful = false, mine = true, isFromPlayerOrPlayerPet = true, sourceUnit = "player" },
    { auraInstanceID = 802, spellId = 33206, name = "Spell33206", icon = 5, duration = 8, expirationTime = 58,
        isHelpful = true, isHarmful = false, mine = false, sourceUnit = "party1" },
})
local function PortraitLane(growth)
    portraitPlaced.growth = growth
    A3.BumpRuntimeConfig()
    local frame = setmetatable({ _shown = true, MSUFUnitKey = "player", _msufActiveElements = { Auras = true },
        MSUFSpec = { portrait = { enabled = true, width = 40, height = 40 } } }, Widget)
    registered.Create(frame)
    assert(registered.Enable(frame) == true, "the player aura element did not enable")
    local lane = assert(frame._msufA3State.lanes.defensivePortrait, "the portrait defensive lane did not compile")
    assert(lane.visible == 2, "precondition: the portrait lane does not show both defensives")
    return lane, lane[2]._point
end
local lane, second = PortraitLane("LEFTDOWN")
assert(second.x == -42 and second.y == 0, ("portrait Left: icon 2 sits at x %s y %s, expected -42, 0"):format(
    tostring(second.x), tostring(second.y)))
lane, second = PortraitLane("RIGHTDOWN")
assert(second.x == 42 and second.y == 0, "portrait Right: icon 2 sits at x " .. tostring(second.x))
lane, second = PortraitLane("UP")
assert(second.x == 0 and second.y == 42 and lane.config.cols == 1 and lane.config.rows == 3
    and lane.config.height == 124, ("portrait Up: icon 2 sits at x %s y %s, lane %sx%s"):format(
    tostring(second.x), tostring(second.y), tostring(lane.config.cols), tostring(lane.config.rows)))
_G.MSUF_DB.auras3.customContainers = nil

-- 5. Group Tracked and External lanes wear the Buff appearance ---------------------------
-- Auras > Appearance offers Buff, Debuff, Player Defensives and Dots on Target
-- (appearanceIconShapes / appearanceIconStyles); Retail gives every group lane
-- but the debuff lane the Buff look (Runtime_LaneConfig sharedLane).
local shared = _G.MSUF_DB.auras3.shared
shared.appearanceIconShapes = { buff = "CIRCLE", debuff = "RECTANGLE" }
shared.appearanceIconStyles = { buff = { styleBorderEnabled = true, styleShadowEnabled = true }, debuff = {} }
A3.BumpRuntimeConfig()
local groupConfig = A3._ClassicCompile.ResolveGroupFrameConfig({ MSUFUnitKey = "party1", _msufIsGroupFrame = true,
    _msufGFKind = "party", MSUFSpec = { scope = "group", auras = {
        enabled = true, showBuffs = true, showTrackedBuffs = true, showDebuffs = true, showExternals = true,
        maxBuffs = 4, maxTrackedBuffs = 2, maxDebuffs = 4, maxExternals = 2,
    } } }, "party1")
for _, kind in ipairs({ "buff", "trackedBuff", "external" }) do
    local laneConfig = assert(groupConfig.lanes[kind], "precondition: the group " .. kind .. " lane did not compile")
    assert(laneConfig.iconShape == "CIRCLE" and laneConfig.iconStyle.borderEnabled == true
        and laneConfig.iconStyle.shadowEnabled == true,
        ("group %s lane: shape %s, border %s, shadow %s; expected the Buff appearance"):format(kind,
        tostring(laneConfig.iconShape), tostring(laneConfig.iconStyle.borderEnabled),
        tostring(laneConfig.iconStyle.shadowEnabled)))
end
assert(groupConfig.lanes.debuff.iconShape == "RECTANGLE" and groupConfig.lanes.debuff.iconStyle.borderEnabled == false,
    "the group debuff lane did not keep the Debuff appearance")
shared.appearanceIconShapes, shared.appearanceIconStyles = nil, nil

print("classic aura setting parity smoke passed: " .. flavor)
