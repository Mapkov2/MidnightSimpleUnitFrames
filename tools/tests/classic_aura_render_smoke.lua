local root = assert(arg[1], "repository root argument missing")
local backendPath = arg[2]
    or (root .. "/MidnightSimpleUnitFrames/Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua")
local featuresPath = arg[3]
local corePath = arg[4]
    or (root .. "/MidnightSimpleUnitFrames/Auras3/MSUF_Auras3_Core.lua")
local visualsPath = arg[5]

local registered
local namespace = {
    Client = { IsClassic = true },
    MSUF_Auras3 = {},
    UF = {
        RegisterElement = function(name, element)
            assert(name == "Auras", "unexpected element registration")
            registered = element
        end,
    },
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}

_G.MSUF_NS = namespace
_G.MSUF = namespace
_G.issecretvalue = function(value)
    return type(value) == "table" and value._secret == true
end
_G.MSUF_DB = {
    auras3 = {
        enabled = true,
        showPlayer = true,
        showTarget = true,
        showFocus = true,
        showBoss = true,
        shared = {
            showWeaponEnchants = true,
            clickThroughAuras = true,
            showTooltip = true,
            appearanceIconShapes = { buff = "CIRCLE", debuff = "RECTANGLE" },
            appearanceIconStyles = {
                buff = { styleBorderEnabled = true, styleBorderThickness = 2 },
                debuff = { styleBorderEnabled = true, styleBorderThickness = 2 },
            },
        },
        perUnit = {
            target = {
                overrideLayout = true,
                overrideSharedLayout = true,
                overrideFilters = true,
                layout = {
                    buffIconZoom = 125,
                    buffDurationBarHeight = 3,
                    buffSpacing = 4,
                    debuffSpacing = 6,
                    buffStylePadding = 3,
                    debuffStylePadding = 3,
                },
                layoutShared = {
                    showBuffs = true,
                    showDebuffs = true,
                    buffShowCooldownSwipe = true,
                    buffShowCooldownText = true,
                    buffShowStackCount = true,
                    debuffShowCooldownSwipe = true,
                    debuffShowCooldownText = true,
                    debuffShowStackCount = true,
                    buffCooldownSwipeReverse = true,
                    buffShowDurationBar = true,
                    buffDurationBarDisplay = "OVERLAY",
                    buffCooldownDecimalSeconds = 7,
                    buffShowStealable = true,
                    buffStealableStyle = "BORDER_ICON",
                    debuffTypeBorderMode = "SYMBOL",
                    useDebuffTypeBorders = true,
                },
                filters = {
                    buffs = { enabled = true },
                    debuffs = { enabled = true },
                },
            },
        },
    },
}

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
function Widget:SetSize(width, height) self._width, self._height = width, height end
function Widget:SetWidth(width) self._width = width end
function Widget:SetHeight(height) self._height = height end
function Widget:GetFrameLevel() return self._frameLevel or 1 end
function Widget:SetFrameLevel(level) self._frameLevel = level end
function Widget:SetScript(name, handler) self._scripts = self._scripts or {}; self._scripts[name] = handler end
function Widget:HookScript(name, handler)
    self._scripts = self._scripts or {}
    local previous = self._scripts[name]
    if previous then
        self._scripts[name] = function(...)
            previous(...)
            handler(...)
        end
    else
        self._scripts[name] = handler
    end
end
function Widget:RegisterEvent(event) self._events = self._events or {}; self._events[event] = true end
function Widget:UnregisterEvent(event) if self._events then self._events[event] = nil end end
function Widget:CreateTexture()
    local texture = setmetatable({ _shown = true, _parent = self }, Widget)
    self._textures = self._textures or {}
    self._textures[#self._textures + 1] = texture
    return texture
end
function Widget:CreateMaskTexture() return self:CreateTexture() end
function Widget:CreateFontString()
    local fontString = setmetatable({ _shown = true, _parent = self }, Widget)
    self._fontStrings = self._fontStrings or {}
    self._fontStrings[#self._fontStrings + 1] = fontString
    return fontString
end
function Widget:GetNumRegions() return 0 end
function Widget:GetRegions() return nil end
function Widget:GetObjectType() return self._objectType or "Frame" end
function Widget:SetTexture(texture) self._texture = texture end
function Widget:SetText(text) self._text = text end
function Widget:SetCooldown(start, duration) self._start, self._duration = start, duration end
function Widget:SetCooldownFromDurationObject(duration)
    self._durationObject = duration
end
function Widget:Clear()
    self._start, self._duration, self._durationObject = nil, nil, nil
    self._cleared = (self._cleared or 0) + 1
end
function Widget:SetMinMaxValues(minimum, maximum) self._minimum, self._maximum = minimum, maximum end
function Widget:SetValue(value) self._value = value end
function Widget:SetTimerDuration(duration, interpolation, direction)
    self._timerDurationObject = duration
    self._timerInterpolation = interpolation
    self._timerDirection = direction
end
function Widget:SetStatusBarTexture(texture) self._statusTexture = texture end
function Widget:SetStatusBarColor(r, g, b, a) self._statusColor = { r, g, b, a } end
function Widget:SetColorTexture(r, g, b, a) self._colorTexture = { r, g, b, a } end
function Widget:SetReverse(reverse) self._reverse = reverse == true end
function Widget:AddMaskTexture(mask) self._mask = mask end
function Widget:RemoveMaskTexture(mask) if self._mask == mask then self._mask = nil end end
function Widget:SetMouseClickEnabled(enabled) self._mouseClickEnabled = enabled == true end
function Widget:SetMouseMotionEnabled(enabled) self._mouseMotionEnabled = enabled == true end
function Widget:SetCountdownMillisecondsThreshold(seconds) self._millisecondsThreshold = seconds end
function Widget:SetAtlas(atlas) self._atlas = atlas end
function Widget:SetVertexColor(r, g, b, a) self._vertexColor = { r, g, b, a } end
function Widget:SetOwner(owner, anchor) self._owner, self._anchor, self._shown = owner, anchor, true end
function Widget:SetUnitAuraByAuraInstanceID(unit, auraInstanceID)
    self._tooltipUnit, self._tooltipAuraInstanceID = unit, auraInstanceID
end

local noops = {
    "ClearAllPoints", "SetAllPoints", "SetAlpha", "EnableMouse",
    "SetMovable", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
    "SetDrawSwipe", "SetHideCountdownNumbers", "SetSwipeColor", "SetDrawEdge",
    "SetTexCoord", "SetFont", "SetTextColor", "SetShadowOffset", "SetDesaturated",
    "SetJustifyH", "SetJustifyV", "SetBlendMode",
}
for i = 1, #noops do Widget[noops[i]] = function() end end
function Widget:SetPoint(...) self._point = { ... } end

local created = {}
_G.CreateFrame = function(frameType, _, parent)
    local widget = setmetatable({ _shown = true, _parent = parent, _objectType = frameType }, Widget)
    created[#created + 1] = widget
    return widget
end
local targetExists = true
_G.UnitExists = function(unit)
    return unit == "player" or unit == "party1" or unit == "party3" or (unit == "target" and targetExists)
end
_G.UnitIsUnit = function(left, right)
    if left == right then return true end
    return (left == "player" and right == "party1")
        or (left == "party1" and right == "player")
end
_G.GetTime = function() return 50 end
local combat = false
_G.InCombatLockdown = function() return combat end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.Enum = {
    StatusBarInterpolation = { Immediate = 1 },
    StatusBarTimerDirection = { ElapsedTime = 2, RemainingTime = 3 },
}
_G.GameTooltip = setmetatable({}, Widget)
_G.C_Timer = {}
_G.DebuffTypeColor = {
    Magic = { r = 0.20, g = 0.60, b = 1.00, a = 1 },
    Curse = { r = 0.60, g = 0.00, b = 1.00, a = 1 },
}
_G.GetInventoryItemTexture = function(_, slot) return slot * 10 end
_G.GetWeaponEnchantInfo = function()
    return true, 300000, 2, 0, true, 1200000, 1, 0, false, nil, 0, 0
end

local auraBySlot = {
    [101] = {
        auraInstanceID = 1001, spellId = 900001, name = "Helpful Test",
        icon = 134400, applications = 1, duration = 30, expirationTime = 80,
        isHelpful = true, isHarmful = false, isFromPlayerOrPlayerPet = true, isStealable = true,
    },
    [202] = {
        auraInstanceID = 2002, spellId = 900002, name = "Harmful Test",
        icon = 134401, applications = 2, duration = 20, expirationTime = 70,
        isHelpful = false, isHarmful = true, isFromPlayerOrPlayerPet = true, dispelName = "Magic",
    },
}

local scanCalls = 0
-- The backend binds GetAuraSlots as a load-time local, so tests mutate this
-- slot list instead of swapping the function on the C_UnitAuras table.
local helpfulSlots = { 101 }
local harmfulSlots = { 202 }
local nativePlayerAuraIDs = {}
local playerFilterLeaksAll = false
local partyInRange = true
-- The backend binds UnitInRange at load, so the count lives in this stub.
local unitInRangeCalls = 0
_G.UnitInRange = function(unit)
    unitInRangeCalls = unitInRangeCalls + 1
    if unit == "party1" then return partyInRange, true end
    return true, true
end
-- nil leaves HARMFUL|RAID_PLAYER_DISPELLABLE unmodelled (every harmful aura is
-- a member); a set limits that filter to the aura instance IDs it holds.
local dispellableAuraIDs
local function FilteredAuraSlots(slots, filter)
    local playerOnly = filter and filter:find("|PLAYER", 1, true) ~= nil
    local dispellableOnly = dispellableAuraIDs ~= nil and filter ~= nil
        and filter:find("RAID_PLAYER_DISPELLABLE", 1, true) ~= nil
    local out = {}
    for i = 1, #slots do
        local slot = slots[i]
        local data = auraBySlot[slot]
        if data and (not playerOnly or playerFilterLeaksAll
            or nativePlayerAuraIDs[data.auraInstanceID] == true)
            and (not dispellableOnly or dispellableAuraIDs[data.auraInstanceID] == true) then
            out[#out + 1] = slot
        end
    end
    return nil, unpack(out)
end
_G.C_UnitAuras = {
    GetAuraSlots = function(_, filter)
        scanCalls = scanCalls + 1
        if filter and filter:find("HARMFUL", 1, true) then
            return FilteredAuraSlots(harmfulSlots, filter)
        end
        return FilteredAuraSlots(helpfulSlots, filter)
    end,
    GetAuraDataBySlot = function(_, slot) return auraBySlot[slot] end,
    GetAuraDataByIndex = function(_, index, filter)
        if index ~= 1 then return nil end
        if filter and filter:find("HARMFUL", 1, true) then return auraBySlot[202] end
        return auraBySlot[101]
    end,
    GetAuraDuration = function(_, auraInstanceID)
        for _, aura in pairs(auraBySlot) do
            if aura.auraInstanceID == auraInstanceID then
                local zero = aura._durationObjectZero
                return {
                    duration = aura.duration,
                    expirationTime = aura.expirationTime,
                    IsZero = function() return zero == true end,
                }
            end
        end
    end,
}
_G.AuraUtil = {}

assert(loadfile(corePath))("MidnightSimpleUnitFrames", namespace)
local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
manifest.LoadSelected(root, "Vanilla", namespace, {
    "Auras3/MSUF_Auras3_IconShape.lua", "Game/Classic/Auras/MSUF_Auras3_Preview.lua",
    "Game/Classic/Auras/MSUF_Auras3_Compile.lua",
})
if visualsPath then
    assert(loadfile(visualsPath))("MidnightSimpleUnitFrames", namespace)
end
if featuresPath then
    assert(loadfile(featuresPath))("MidnightSimpleUnitFrames", namespace)
end
assert(loadfile(backendPath))("MidnightSimpleUnitFrames", namespace)
assert(registered, "Classic aura element did not register")

local frame = setmetatable({
    _shown = true,
    MSUFUnitKey = "target",
    _msufActiveElements = { Auras = true },
    MSUFSpec = {
        dispel = { r = 0.25, g = 0.75, b = 1, a = 1 },
        dispelOverlay = {
            enabled = true, trigger = "DISPEL_TYPE", style = "FULL", onHealth = false, alpha = 0.35,
        },
        dispelSymbol = {
            enabled = true, style = "MSUF_LETTERS", mode = "ALL", trigger = "DISPEL_TYPE",
            size = 14, spacing = 2, growth = "RIGHT", anchor = "TOPRIGHT", x = 0, y = 0,
            alpha = 1, layer = 8, strata = "AUTO",
        },
    },
}, Widget)

registered.Create(frame)
assert(registered.Enable(frame) == true, "Classic aura element did not enable")
local state = assert(frame._msufA3State, "Classic aura state was not created")
local buff = assert(state.lanes.buff, "buff lane missing")
local debuff = assert(state.lanes.debuff, "debuff lane missing")
assert(buff.visible == 1 and buff[1] and buff[1]._shown == true,
    "helpful aura did not render a visible button")
assert(buff[1].auraInstanceID == 1001 and buff[1].Icon._texture == 134400,
    "helpful aura button data was not applied")
assert(debuff.visible == 1 and debuff[1] and debuff[1]._shown == true,
    "harmful aura did not render a visible button")
assert(debuff[1].auraInstanceID == 2002 and debuff[1].Count._text == 2,
    "harmful aura button data was not applied")
assert(type(debuff.config.visual) == "table" and debuff[1].Icon._texture == 134401
    and debuff[1].Icon._shown == true,
    "normal target debuff was hidden by its compiled dispel visual")
assert(debuff[1]._msufA3CooldownShown == true and debuff[1].Cooldown._shown == true,
    "normal target debuff cooldown was hidden by its compiled dispel visual")
assert(buff[1]._scripts and type(buff[1]._scripts.OnEnter) == "function",
    "Classic aura button tooltip handler missing")
assert(buff[1]._mouseClickEnabled == false and buff[1]._mouseMotionEnabled == true,
    "Classic click-through disabled tooltip hover instead of clicks only")
buff[1]._scripts.OnEnter(buff[1])
assert(_G.GameTooltip._owner == buff[1] and _G.GameTooltip._anchor == "ANCHOR_CURSOR"
    and _G.GameTooltip._tooltipUnit == "target" and _G.GameTooltip._tooltipAuraInstanceID == 1001,
    "Classic aura tooltip did not use the generic aura-instance API")
buff[1]._scripts.OnLeave(buff[1])
assert(_G.GameTooltip._shown == false, "Classic aura tooltip did not hide on leave")

local function HasEvent(events, wanted)
    for i = 1, #(events or {}) do
        if events[i] == wanted then return true end
    end
    return false
end

assert(HasEvent(registered.GetUnitlessEvents(frame), "PLAYER_TARGET_CHANGED"),
    "Classic target aura lifecycle did not bind PLAYER_TARGET_CHANGED")
assert(HasEvent(registered.GetUnitlessEvents({ MSUFUnitKey = "focus", MSUFSpec = {} }), "PLAYER_FOCUS_CHANGED"),
    "Classic focus aura lifecycle did not bind PLAYER_FOCUS_CHANGED")
assert(HasEvent(registered.GetUnitlessEvents({ MSUFUnitKey = "boss1", MSUFSpec = {} }), "INSTANCE_ENCOUNTER_ENGAGE_UNIT"),
    "Classic boss aura lifecycle did not bind INSTANCE_ENCOUNTER_ENGAGE_UNIT")

_G.C_Timer.After = function()
    error("Classic identity aura refresh must stay synchronous")
end

auraBySlot[101] = {
    auraInstanceID = 3003, spellId = 900003, name = "New Helpful Target",
    icon = 134402, applications = 1, duration = 25, expirationTime = 75,
    isHelpful = true, isHarmful = false, isFromPlayerOrPlayerPet = true, isStealable = true,
}
auraBySlot[202] = {
    auraInstanceID = 4004, spellId = 900004, name = "New Harmful Target",
    icon = 134403, applications = 3, duration = 15, expirationTime = 65,
    isHelpful = false, isHarmful = true, isFromPlayerOrPlayerPet = true, dispelName = "Curse",
}
local scansBeforeSwap = scanCalls
assert(registered.Update(frame, "PLAYER_TARGET_CHANGED") == true,
    "Classic target identity refresh did not run")
assert(frame._msufA3IdentityRebuildPending == nil and scanCalls > scansBeforeSwap,
    "Classic target identity refresh was deferred instead of fully applied")
assert(buff[1].auraInstanceID == 3003 and debuff[1].auraInstanceID == 4004,
    "Classic target identity refresh retained the previous target's auras")

targetExists = false
assert(registered.Update(frame, "PLAYER_TARGET_CHANGED") == false,
    "Classic target-clear refresh reported rendered auras")
assert(buff.visible == 0 and debuff.visible == 0
    and buff[1]._shown == false and debuff[1]._shown == false,
    "Classic target-clear refresh left stale aura buttons visible")

targetExists = true
assert(registered.Update(frame, "PLAYER_TARGET_CHANGED") == true,
    "Classic target reacquire refresh did not run")
assert(buff[1].auraInstanceID == 3003 and debuff[1].auraInstanceID == 4004,
    "Classic target reacquire did not rebuild aura lanes")

-- RegisterUnitWatch may show a formerly hidden target/focus/boss frame before
-- its identity event reaches the element dispatcher. OnShow must therefore
-- perform the same cold full scan instead of waiting for another target swap
-- or a menu movement/apply.
frame._shown = false
auraBySlot[101] = {
    auraInstanceID = 3103, spellId = 900013, name = "OnShow Helpful Target",
    icon = 134413, applications = 1, duration = 25, expirationTime = 75,
    isHelpful = true, isHarmful = false, isFromPlayerOrPlayerPet = true, isStealable = true,
}
auraBySlot[202] = {
    auraInstanceID = 4104, spellId = 900014, name = "OnShow Harmful Target",
    icon = 134414, applications = 1, duration = 15, expirationTime = 65,
    isHelpful = false, isHarmful = true, isFromPlayerOrPlayerPet = true, dispelName = "Curse",
}
frame._shown = true
assert(frame._scripts and type(frame._scripts.OnShow) == "function",
    "Classic aura OnShow identity refresh hook missing")
frame._scripts.OnShow(frame)
assert(buff[1].auraInstanceID == 3103 and debuff[1].auraInstanceID == 4104,
    "Classic aura OnShow retained the hidden frame's stale identity")
_G.C_Timer.After = nil

assert(buff.config.iconShape == "CIRCLE" and buff.config.iconZoom == 125,
    "Classic icon shape/zoom settings were not compiled: "
        .. tostring(buff.config.iconShape) .. "/" .. tostring(buff.config.iconZoom))
assert(buff.config.spacing == 4 and debuff.config.spacing == 6,
    "Classic per-lane aura spacing was not compiled")
assert(buff.config.padding == 3 and debuff.config.padding == 3
    and buff.config.width == buff.config.cols * buff.config.size
        + math.max(buff.config.cols - 1, 0) * buff.config.spacing + 6,
    "Classic lane padding was not compiled into live aura geometry")
assert(buff[1]._point and buff[1]._point[1] == "TOPLEFT"
    and buff[1]._point[4] == 3 and buff[1]._point[5] == -3,
    "Classic lane padding did not inset the first live aura button")
assert(buff[1].Cooldown._millisecondsThreshold == 7,
    "Classic cooldown decimal threshold was not applied")
assert(buff.config.showStealableMarker == true and buff.config.stealableStyle == "BORDER_ICON"
    and buff[1]._msufA3ClassicStealableBorder
    and buff[1]._msufA3ClassicStealableBorder._shown == true
    and buff[1]._msufA3ClassicStealableIcon
    and buff[1]._msufA3ClassicStealableIcon._shown == true,
    "Classic stealable border + icon marker did not render")
assert(buff[1].Icon._mask ~= nil and buff[1]._msufA3ShapedStyleBorder
    and buff[1]._msufA3ShapedStyleBorder._shown == true,
    "Classic shaped aura icon border/mask did not render")
assert(debuff.config.showDispelTypeBorder == true and debuff.config.showDispelTypeSymbol == true
    and debuff[1]._msufA3DispelOverlay and debuff[1]._msufA3DispelOverlay._shown == true
    and debuff[1]._msufA3DispelTypeSymbol and debuff[1]._msufA3DispelTypeSymbol._shown == true,
    "Classic per-aura dispel border + symbol mode did not render")
assert(buff.config.showDurationBar == true and buff.config.durationBarDisplay == "OVERLAY",
    "Classic duration-bar settings were not compiled")
assert(buff[1]._msufA3DurationBar and buff[1]._msufA3DurationBar._shown == true,
    "Classic duration bar did not render")
-- Classic must never bind aura LuaDurationObjects (they produced hour-scale
-- timers on Mists/TBC); the bar runs on plain duration/expiration numbers
-- with its own OnUpdate drain. Aura 3003: duration 25, expiration 75, now 50.
assert(buff[1]._msufA3DurationBar._timerDurationObject == nil,
    "Classic duration bar bound an aura duration object")
assert(buff[1]._msufA3DurationBar._maximum == 25
    and buff[1]._msufA3DurationBar._value == 25
    and buff[1]._msufA3DurationBar._scripts
    and buff[1]._msufA3DurationBar._scripts.OnUpdate ~= nil,
    "Classic duration bar did not drive its plain remaining-time animation")
assert(buff[1].Cooldown._reverse == true, "Classic cooldown reverse setting was not applied")
assert(frame._msufA3ClassicDispelSymbolsActive == true
    and frame._msufA3ClassicDispelSymbolHost and frame._msufA3ClassicDispelSymbolHost._shown == true,
    "Classic live dispel symbol did not render")
assert(frame._msufA3ClassicDispelOverlayActive == true
    and frame._msufA3ClassicDispelOverlayHost and frame._msufA3ClassicDispelOverlayHost._shown == true,
    "Classic live dispel overlay did not render")
assert(_G.MSUF_SetDispelOverlayPreview(true, "target") == true,
    "Classic dispel-overlay preview setter missing")
assert(_G.MSUF_ApplyDispelOverlayPreviewToFrame(frame) == true
    and frame._msufA3ClassicDispelOverlayPreviewHost._shown == true,
    "Classic dispel-overlay preview did not render")
assert(_G.MSUF_SetDispelSymbolPreview(true, "target") == true,
    "Classic dispel-symbol preview setter missing")
assert(_G.MSUF_ApplyDispelSymbolPreviewToFrame(frame) == true
    and frame._msufA3ClassicDispelSymbolPreviewHost._shown == true,
    "Classic dispel-symbol preview did not render")
_G.MSUF_SetDispelOverlayPreview(false)
_G.MSUF_SetDispelSymbolPreview(false)

-- The live dispel-symbol path reuses per-frame scratch tables: the backend's
-- present set and the renderer's selected list. Shrinking the dispel-type set
-- must drop the previous update's types from both, or stale tiles survive.
local symbolHost = frame._msufA3ClassicDispelSymbolHost
local savedHarmfulAura = auraBySlot[202]
auraBySlot[202] = {
    auraInstanceID = 4204, spellId = 900024, name = "Symbol Magic Target",
    icon = 134424, applications = 1, duration = 15, expirationTime = 65,
    isHelpful = false, isHarmful = true, isFromPlayerOrPlayerPet = true, dispelName = "Magic",
}
auraBySlot[203] = {
    auraInstanceID = 4205, spellId = 900025, name = "Symbol Curse Target",
    icon = 134425, applications = 1, duration = 15, expirationTime = 65,
    isHelpful = false, isHarmful = true, isFromPlayerOrPlayerPet = true, dispelName = "Curse",
}
harmfulSlots[2] = 203
assert(registered.Update(frame, "UNIT_AURA", "target", { isFullUpdate = true }) == true,
    "Classic two-type dispel-symbol refresh did not run")
assert(symbolHost._shown == true and symbolHost.tiles[1] and symbolHost.tiles[1]._shown == true
    and tostring(symbolHost.tiles[1]._texture):find("magic.tga", 1, true)
    and symbolHost.tiles[2] and symbolHost.tiles[2]._shown == true
    and tostring(symbolHost.tiles[2]._texture):find("curse.tga", 1, true),
    "Classic live dispel symbol did not render both dispel types")
harmfulSlots[2] = nil
auraBySlot[203] = nil
auraBySlot[202] = savedHarmfulAura
assert(registered.Update(frame, "UNIT_AURA", "target", { isFullUpdate = true }) == true,
    "Classic one-type dispel-symbol refresh did not run")
assert(frame._msufA3ClassicDispelPresent and frame._msufA3ClassicDispelPresent.Magic == nil
    and frame._msufA3ClassicDispelPresent.Curse == true,
    "Classic dispel-symbol present set kept the previous update's dispel type")
assert(symbolHost._shown == true and symbolHost.tiles[1]._shown == true
    and tostring(symbolHost.tiles[1]._texture):find("curse.tga", 1, true)
    and symbolHost.tiles[2]._shown == false and symbolHost.tiles[3] == nil,
    "Classic dispel-symbol tiles kept the previous update's dispel type")

-- Dispel-lane membership: the frame overlay, the frame symbols and the
-- per-aura type border follow the configured trigger. DISPEL_TYPE needs a
-- readable dispel type; BY_ME needs native RAID_PLAYER_DISPELLABLE membership.
do
    local A3 = namespace.MSUF_Auras3
    local function DispelLane(label)
        assert(registered.Update(frame, "UNIT_AURA", "target", { isFullUpdate = true }) == true,
            label .. ": refresh did not run")
    end
    local function OverlayActive()
        return frame._msufA3DispelOverlayActive == true and frame._msufA3ClassicDispelOverlayActive == true
    end
    local function SymbolsActive()
        return frame._msufA3ClassicDispelSymbolsActive == true
    end
    local savedDispelAura = auraBySlot[202]
    auraBySlot[202] = {
        auraInstanceID = 4301, spellId = 900031, name = "Typeless Harmful Target",
        icon = 134431, applications = 1, duration = 15, expirationTime = 65,
        isHelpful = false, isHarmful = true, isFromPlayerOrPlayerPet = true,
    }
    DispelLane("typeless debuff")
    local typelessOverlay = debuff[1]._msufA3DispelOverlay
    local typelessSymbol = debuff[1]._msufA3DispelTypeSymbol
    assert(debuff.visible == 1 and debuff.active[4301] == true, "typeless debuff did not render")
    assert(not OverlayActive() and frame._msufA3DispelOverlayActive ~= true,
        "Classic DISPEL_TYPE overlay matched a debuff without a dispel type")
    assert(not SymbolsActive(), "Classic DISPEL_TYPE symbols matched a debuff without a dispel type")
    assert((typelessOverlay == nil or typelessOverlay._shown == false)
        and (typelessSymbol == nil or typelessSymbol._shown == false),
        "Classic per-aura dispel border marked a debuff without a dispel type")

    auraBySlot[202] = {
        auraInstanceID = 4302, spellId = 900032, name = "Magic Harmful Target",
        icon = 134432, applications = 1, duration = 15, expirationTime = 65,
        isHelpful = false, isHarmful = true, isFromPlayerOrPlayerPet = true, dispelName = "Magic",
    }
    DispelLane("magic debuff")
    assert(OverlayActive() and SymbolsActive(),
        "Classic DISPEL_TYPE overlay or symbols missed a Magic debuff")
    assert(debuff[1]._msufA3DispelOverlay and debuff[1]._msufA3DispelOverlay._shown == true,
        "Classic per-aura dispel border missed a Magic debuff")

    -- BY_ME: a Magic debuff the player cannot dispel stays out of the lane; a
    -- member shows it only while that member is present.
    frame.MSUFSpec.dispelOverlay.trigger = "BY_ME"
    frame.MSUFSpec.dispelSymbol.trigger = "BY_ME"
    dispellableAuraIDs = {}
    A3.BumpRuntimeConfig()
    DispelLane("BY_ME non-member")
    assert(debuff.visible == 1 and not OverlayActive() and not SymbolsActive(),
        "Classic BY_ME dispel lane matched a debuff outside RAID_PLAYER_DISPELLABLE")

    auraBySlot[203] = {
        auraInstanceID = 4303, spellId = 900033, name = "Dispellable Harmful Target",
        icon = 134433, applications = 1, duration = 15, expirationTime = 65,
        isHelpful = false, isHarmful = true, isFromPlayerOrPlayerPet = true, dispelName = "Magic",
    }
    harmfulSlots[2] = 203
    dispellableAuraIDs[4303] = true
    assert(registered.Update(frame, "UNIT_AURA", "target", { addedAuras = { auraBySlot[203] } }) == true,
        "Classic BY_ME member add did not render")
    assert(debuff.active[4303] == true and OverlayActive() and SymbolsActive(),
        "Classic BY_ME dispel lane missed a RAID_PLAYER_DISPELLABLE member")

    harmfulSlots[2] = nil
    auraBySlot[203] = nil
    dispellableAuraIDs[4303] = nil
    assert(registered.Update(frame, "UNIT_AURA", "target", { removedAuraInstanceIDs = { 4303 } }) == true,
        "Classic BY_ME member removal did not render")
    assert(debuff.active[4303] == nil and not OverlayActive() and not SymbolsActive(),
        "Classic BY_ME dispel lane stayed active after its member left")

    -- Symbols off makes the visual direct (one native query per trigger). The
    -- disabled border must not veto an overlay that inherits its trigger there
    -- either; the stub's direct query ignores RAID_PLAYER_DISPELLABLE.
    frame.MSUFSpec.dispelSymbol.enabled = false
    A3.BumpRuntimeConfig()
    DispelLane("direct BY_ME overlay")
    assert(frame._msufA3State.config.visualDirect == true and OverlayActive(),
        "Classic direct dispel overlay was vetoed by the disabled border")
    frame.MSUFSpec.dispelSymbol.enabled = true

    frame.MSUFSpec.dispelOverlay.trigger = "DISPEL_TYPE"
    frame.MSUFSpec.dispelSymbol.trigger = "DISPEL_TYPE"
    dispellableAuraIDs = nil
    auraBySlot[202] = savedDispelAura
    A3.BumpRuntimeConfig()
    DispelLane("restored DISPEL_TYPE")
    assert(OverlayActive() and SymbolsActive() and debuff[1].auraInstanceID == savedDispelAura.auraInstanceID,
        "Classic dispel lane did not recover its DISPEL_TYPE trigger")
end

-- A valid permanent aura still has a LuaDurationObject in current Classic,
-- but it must not resurrect a full/stale cooldown swipe over its icon.
auraBySlot[101] = {
    auraInstanceID = 5005, spellId = 900005, name = "Permanent Helpful Target",
    icon = 134404, applications = 1, duration = 0, expirationTime = 0,
    isHelpful = true, isHarmful = false, isFromPlayerOrPlayerPet = false,
}
assert(registered.Update(frame, "UNIT_AURA", "target", { isFullUpdate = true }) == true,
    "Classic permanent-aura refresh did not run")
assert(buff[1].auraInstanceID == 5005 and buff[1].Icon._texture == 134404,
    "Classic permanent aura did not retain its icon")
assert(buff[1]._msufA3CooldownShown == nil and buff[1].Cooldown._shown == false,
    "Classic permanent aura displayed a zero-duration cooldown swipe")
assert(buff[1].Cooldown._durationObject == nil and (buff[1].Cooldown._cleared or 0) > 0,
    "Classic permanent aura retained the previous timed cooldown state")
assert(buff[1]._msufA3DurationBar._shown == false
    and buff[1]._msufA3DurationBar._minimum == 0
    and buff[1]._msufA3DurationBar._maximum == 1
    and buff[1]._msufA3DurationBar._value == 0,
    "Classic permanent aura retained a stale duration bar")
assert(buff[1]._msufA3ClassicStealableBorder._shown == false
    and buff[1]._msufA3ClassicStealableIcon._shown == false,
    "Classic pooled aura button retained a stale stealable marker")

-- Retail-compatible profiles may keep hidePermanent inside the effective
-- per-lane filter block instead of the newer blacklist lane. Both Classic
-- lanes must consume that portable shape and filter real duration-zero data.
_G.MSUF_DB.auras3.perUnit.target.filters = {
    buffs = { hidePermanent = true },
    debuffs = { hidePermanent = true },
}
assert(namespace.MSUF_Auras3.RequestScope("target", "render-smoke-hide-permanent-buff") == true,
    "Classic hide-permanent buff apply did not run")
assert(buff.visible == 0 and buff[1]._shown == false,
    "Classic hide-permanent filter retained a duration-zero buff")

auraBySlot[202] = {
    auraInstanceID = 6006, spellId = 900006, name = "Permanent Harmful Target",
    icon = 134405, applications = 1, duration = 0, expirationTime = 0,
    isHelpful = false, isHarmful = true, isFromPlayerOrPlayerPet = false,
}
assert(namespace.MSUF_Auras3.RequestScope("target", "render-smoke-hide-permanent-debuff") == true,
    "Classic hide-permanent debuff apply did not run")
assert(debuff.visible == 0 and debuff[1]._shown == false,
    "Classic hide-permanent filter retained a duration-zero debuff")
_G.MSUF_DB.auras3.perUnit.target.filters = { buffs = { enabled = true }, debuffs = { enabled = true } }

local visuals = assert(namespace.MSUF_Auras3.ClassicVisuals, "Classic visuals missing")
assert(type(namespace.MSUF_Auras3.PreviewDispelTypeForIndex) == "function",
    "Classic Auras3 preview dispel-type provider missing")
assert(namespace.MSUF_Auras3.PreviewDispelTypeForIndex(1) == "Magic"
    and namespace.MSUF_Auras3.PreviewDispelTypeForIndex(2) == "Curse"
    and namespace.MSUF_Auras3.PreviewDispelTypeForIndex(6) == "Magic",
    "Classic Auras3 preview dispel-type order drifted")
local effectOwner = setmetatable({ _shown = true, hpBar = setmetatable({ _shown = true }, Widget) }, Widget)
local effectButton = setmetatable({ _shown = true }, Widget)
effectButton.Icon = effectButton:CreateTexture()
effectButton.Count = effectButton:CreateFontString()
local effectLane = {
    ownerFrame = effectOwner,
    config = {
        visual = "square", color = { 0.2, 0.8, 0.4, 1 }, size = 18, buttonWidth = 18, buttonHeight = 18,
        iconShape = "RECTANGLE", iconZoom = 100, showCooldown = false, showStacks = false,
        frameEffect = { type = "border", color = { 1, 0, 0, 1 }, thickness = 2, priority = 1 },
    },
}
visuals.UpdateButtonVisual(effectLane, effectButton, "party1", { auraInstanceID = 9, applications = 1 })
assert(effectButton._msufA3ClassicIndicatorSwatch and effectButton._msufA3ClassicIndicatorSwatch._shown == true,
    "Classic square spell-indicator visual did not render")
assert(effectButton._msufA3ClassicFrameEffectRoot and effectButton._msufA3ClassicFrameEffectRoot._shown == true,
    "Classic spell-indicator frame effect did not render")
visuals.HideButtonVisual(effectButton)
assert(effectButton._msufA3ClassicFrameEffectRoot._shown == false,
    "Classic spell-indicator frame effect did not hide")

local playerFrame = setmetatable({
    _shown = true,
    MSUFUnitKey = "player",
    MSUFSpec = {},
}, Widget)
assert(registered.Enable(playerFrame) == true, "Classic player aura element did not enable")
local playerBuff = assert(playerFrame._msufA3State.lanes.buff, "player buff lane missing")
assert(playerBuff.visible == 3, "weapon enchants were not merged into the player buff lane")
assert(playerBuff[1]._msufA3WeaponEnchantSlot == 17 and playerBuff[1].Icon._texture == 170,
    "off-hand weapon enchant did not render first")
assert(playerBuff[2]._msufA3WeaponEnchantSlot == 16 and playerBuff[2].Icon._texture == 160,
    "main-hand weapon enchant did not render")
local unitless = registered.GetUnitlessEvents(playerFrame)
assert(unitless[1] == "WEAPON_ENCHANT_CHANGED" and unitless[2] == "WEAPON_SLOT_CHANGED",
    "weapon enchant events were not bound only for the opted-in player lane")

frame.MSUFSpec.dispelSymbol.enabled = false
frame.MSUFSpec.dispelOverlay.enabled = false
_G.MSUF_DB.auras3.perUnit.target.layoutShared.showBuffs = false
buff[1]._msufA3Shown = nil
buff[1].auraInstanceID = nil
assert(namespace.MSUF_Auras3.RequestScope("target", "render-smoke-disable-buff-lane") == true,
    "Classic buff-lane disable was not applied")
assert(state.root._shown == true and buff.frame._shown == false and buff[1]._shown == false,
    "Classic buff-lane disable left its container or pooled button visible")
assert(debuff.frame._shown == true and debuff[1]._shown == true,
    "Classic buff-lane disable incorrectly hid the debuff lane")
_G.MSUF_DB.auras3.perUnit.target.layoutShared.showBuffs = true
assert(namespace.MSUF_Auras3.RequestScope("target", "render-smoke-enable-buff-lane") == true,
    "Classic buff-lane enable was not applied")

_G.MSUF_DB.auras3.perUnit.target.layoutShared.showDebuffs = false
debuff[1]._msufA3Shown = nil
debuff[1].auraInstanceID = nil
assert(namespace.MSUF_Auras3.RequestScope("target", "render-smoke-disable-debuff-lane") == true,
    "Classic debuff-lane disable was not applied")
assert(state.root._shown == true and debuff.frame._shown == false and debuff[1]._shown == false,
    "Classic debuff-lane disable left its container or pooled button visible")
assert(buff.frame._shown == true and buff[1]._shown == true,
    "Classic debuff-lane disable incorrectly hid the buff lane")
_G.MSUF_DB.auras3.perUnit.target.layoutShared.showDebuffs = true
assert(namespace.MSUF_Auras3.RequestScope("target", "render-smoke-enable-debuff-lane") == true,
    "Classic debuff-lane enable was not applied")

-- Only Mine is a hard native PLAYER scan for both helpful and harmful lanes.
-- AuraData caster fields are deliberately mixed below: visibility must follow
-- Blizzard's filter membership, not an unreliable legacy ownership flag.
auraBySlot[101] = {
    auraInstanceID = 7007, spellId = 900007, name = "Own HoT",
    icon = 134406, applications = 1, duration = 20, expirationTime = 70,
    isHelpful = true, isHarmful = false, sourceUnit = "player",
}
auraBySlot[103] = {
    auraInstanceID = 7008, spellId = 900008, name = "Foreign Buff",
    icon = 134407, applications = 1, duration = 20, expirationTime = 70,
    isHelpful = true, isHarmful = false, sourceUnit = "party2",
    isFromPlayerOrPlayerPet = false,
}
helpfulSlots[2] = 103
nativePlayerAuraIDs[7007] = true
auraBySlot[202] = {
    auraInstanceID = 7201, spellId = 900021, name = "Own DoT",
    icon = 134408, applications = 1, duration = 18, expirationTime = 68,
    isHelpful = false, isHarmful = true, sourceUnit = "player",
}
auraBySlot[204] = {
    auraInstanceID = 7202, spellId = 900022, name = "Foreign Debuff",
    icon = 134409, applications = 1, duration = 18, expirationTime = 68,
    isHelpful = false, isHarmful = true, sourceUnit = "party2",
    isFromPlayerOrPlayerPet = false,
}
harmfulSlots[2] = 204
nativePlayerAuraIDs[7201] = true
_G.MSUF_DB.auras3.perUnit.target.filters = {
    buffs = { enabled = true, onlyMine = true },
    debuffs = { enabled = true, onlyMine = true },
}
assert(namespace.MSUF_Auras3.RequestScope("target", "render-smoke-only-mine") == true,
    "Classic only-mine filter apply did not run")
assert(buff.config.filter == "HELPFUL|PLAYER" and buff.config.nativePlayerFilter == true
    and debuff.config.filter == "HARMFUL|PLAYER" and debuff.config.nativePlayerFilter == true,
    "Classic only-mine lanes did not use native PLAYER scans")
assert(buff.visible == 1 and buff[1].auraInstanceID == 7007,
    "Classic only-mine buff filter retained a foreign aura")
assert(debuff.visible == 1 and debuff[1].auraInstanceID == 7201,
    "Classic only-mine debuff filter retained a foreign aura")

-- UNIT_AURA addedAuras are not pre-filtered by Blizzard. A foreign aura must
-- be rejected through the same native membership set and never render live.
local foreignDelta = {
    auraInstanceID = 7009, spellId = 900009, name = "Foreign Delta Buff",
    icon = 134410, applications = 1, duration = 15, expirationTime = 65,
    isHelpful = true, isHarmful = false, sourceUnit = "party2",
    isFromPlayerOrPlayerPet = true,
}
local foreignDebuffDelta = {
    auraInstanceID = 7203, spellId = 900023, name = "Foreign Delta Debuff",
    icon = 134411, applications = 1, duration = 15, expirationTime = 65,
    isHelpful = false, isHarmful = true, sourceUnit = "party2",
    isFromPlayerOrPlayerPet = true,
}
registered.Update(frame, "UNIT_AURA", "target", {
    addedAuras = { foreignDelta, foreignDebuffDelta },
})
assert(buff.visible == 1 and buff[1].auraInstanceID == 7007
    and buff.active[7009] ~= true,
    "Classic only-mine delta path admitted a foreign buff")
assert(debuff.visible == 1 and debuff[1].auraInstanceID == 7201
    and debuff.active[7203] ~= true,
    "Classic only-mine delta path admitted a foreign debuff")

-- An owned aura arriving through the same delta path must remain visible even
-- when its legacy ownership fields are false or absent.
local ownDelta = {
    auraInstanceID = 7010, spellId = 900010, name = "Own Delta HoT",
    icon = 134412, applications = 1, duration = 15, expirationTime = 65,
    isHelpful = true, isHarmful = false, isFromPlayerOrPlayerPet = false,
}
auraBySlot[105] = ownDelta
helpfulSlots[3] = 105
nativePlayerAuraIDs[7010] = true
assert(registered.Update(frame, "UNIT_AURA", "target", { addedAuras = { ownDelta } }) == true,
    "Classic only-mine delta path did not render an owned buff")
assert(buff.visible == 2 and buff.active[7010] == true,
    "Classic only-mine delta path rejected an owned buff")
helpfulSlots[3] = nil
auraBySlot[105] = nil
nativePlayerAuraIDs[7010] = nil
assert(registered.Update(frame, "UNIT_AURA", "target", { removedAuraInstanceIDs = { 7010 } }) == true,
    "Classic only-mine delta cleanup did not render")
assert(buff.visible == 1 and buff.active[7010] ~= true,
    "Classic only-mine delta cleanup retained the removed buff")

-- Native PLAYER filter trust belongs to the unit, not the lane: one delta event
-- evaluates UnitInRange once however many lanes use the native filter, and the
-- player never needs it.
do
    local A3 = namespace.MSUF_Auras3
    unitInRangeCalls = 0
    assert(registered.Update(frame, "UNIT_AURA", "target", { updatedAuraInstanceIDs = { 7007 } }) ~= nil,
        "Classic only-mine range-trust delta did not run")
    assert(unitInRangeCalls == 1, "Classic only-mine delta evaluated UnitInRange "
        .. unitInRangeCalls .. " times for two native-filter lanes, expected once")
    assert(buff._msufA3NativePlayerFilterTrusted == true and debuff._msufA3NativePlayerFilterTrusted == true,
        "Classic only-mine range trust did not reach both native-filter lanes")

    _G.MSUF_DB.auras3.perUnit.player = {
        overrideFilters = true,
        filters = { buffs = { enabled = true, onlyMine = true }, debuffs = { enabled = true, onlyMine = true } },
    }
    assert(A3.RequestScope("player", "render-smoke-player-only-mine") == true,
        "Classic player only-mine apply did not run")
    local playerLanes = playerFrame._msufA3State.lanes
    assert(playerLanes.buff.config.nativePlayerFilter == true and playerLanes.debuff.config.nativePlayerFilter == true,
        "Classic player only-mine lanes did not use native PLAYER scans")
    unitInRangeCalls = 0
    registered.Update(playerFrame, "UNIT_AURA", "player", { updatedAuraInstanceIDs = { 1001 } })
    assert(unitInRangeCalls == 0, "Classic player aura event evaluated UnitInRange "
        .. unitInRangeCalls .. " times")
    _G.MSUF_DB.auras3.perUnit.player = nil
    assert(A3.RequestScope("player", "render-smoke-player-filters-restored") == true,
        "Classic player filter restore did not run")
end

-- A false legacy flag and missing caster must not hide an aura which the
-- native PLAYER filter identifies as the player's own cast.
auraBySlot[101].sourceUnit = "party1"
assert(namespace.MSUF_Auras3.RequestScope("target", "render-smoke-only-mine-unit-alias") == true,
    "Classic only-mine unit-alias apply did not run")
assert(buff.visible == 1 and buff[1].auraInstanceID == 7007,
    "Classic only-mine native scan rejected an owned aura")
auraBySlot[101].sourceUnit = nil
auraBySlot[101].isFromPlayerOrPlayerPet = false
assert(namespace.MSUF_Auras3.RequestScope("target", "render-smoke-only-mine-membership-fallback") == true,
    "Classic only-mine membership fallback apply did not run")
assert(buff.visible == 1 and buff[1].auraInstanceID == 7007,
    "Classic only-mine filter trusted a false legacy player flag")

local groupFrame = setmetatable({
    _shown = true,
    MSUFUnitKey = "party1",
    _msufGFKind = "party",
    MSUFSpec = {
        scope = "group",
        auras = {
            enabled = true,
            showBuffs = true,
            maxBuffs = 3,
            buffFilter = "HELPFUL|RAID|PLAYER",
            buffHidePermanent = true,
            showDebuffs = true,
            maxDebuffs = 3,
            debuffFilter = "HARMFUL|PLAYER",
            debuffHidePermanent = true,
        },
    },
}, Widget)
auraBySlot[101] = {
    auraInstanceID = 7101, spellId = 900101, name = "Own Timed Group Buff",
    icon = 134406, applications = 1, duration = 20, expirationTime = 70,
    isHelpful = true, isHarmful = false, sourceUnit = "player",
}
auraBySlot[103] = {
    auraInstanceID = 7102, spellId = 900102, name = "Foreign Permanent Group Buff",
    icon = 134407, applications = 1, duration = 0, expirationTime = 0,
    isHelpful = true, isHarmful = false, sourceUnit = "party2",
}
helpfulSlots[2] = 103
nativePlayerAuraIDs[7101] = true
auraBySlot[202] = {
    auraInstanceID = 8101, spellId = 900201, name = "Own Timed Group Debuff",
    icon = 134408, applications = 1, duration = 18, expirationTime = 68,
    isHelpful = false, isHarmful = true, sourceUnit = "player",
}
auraBySlot[204] = {
    auraInstanceID = 8102, spellId = 900202, name = "Foreign Permanent Group Debuff",
    icon = 134409, applications = 1, duration = 0, expirationTime = 0,
    isHelpful = false, isHarmful = true, sourceUnit = "party2",
}
harmfulSlots[2] = 204
nativePlayerAuraIDs[8101] = true
assert(registered.Enable(groupFrame) == true, "Classic group aura element did not enable")
local groupBuff = assert(groupFrame._msufA3State.lanes.buff, "Classic group buff lane missing")
local groupDebuff = assert(groupFrame._msufA3State.lanes.debuff, "Classic group debuff lane missing")
assert(groupBuff.visible == 1 and groupBuff[1].auraInstanceID == 7101,
    "Classic group Only Mine / Hide Permanent filters did not compose")
assert(groupDebuff.visible == 1 and groupDebuff[1].auraInstanceID == 8101,
    "Classic group debuff Only Mine / Hide Permanent filters did not compose")

-- Some Classic clients broaden a native |PLAYER scan to every aura while a
-- group unit is explicitly out of range. Known caster data may still preserve
-- an owned aura, but unreadable caster data must fail closed instead of turning
-- Only Mine into an unfiltered lane.
partyInRange = false
playerFilterLeaksAll = true
auraBySlot[103].duration, auraBySlot[103].expirationTime = 20, 70
auraBySlot[204].duration, auraBySlot[204].expirationTime = 18, 68
auraBySlot[103].sourceUnit = { _secret = true }
auraBySlot[103].isFromPlayerOrPlayerPet = true
auraBySlot[204].sourceUnit = { _secret = true }
auraBySlot[204].isFromPlayerOrPlayerPet = true
assert(registered.Update(groupFrame, "UNIT_AURA", "party1", { isFullUpdate = true }) == true,
    "Classic out-of-range Only Mine refresh did not run")
assert(groupBuff.visible == 1 and groupBuff[1].auraInstanceID == 7101,
    "Classic out-of-range Only Mine broadened to a foreign buff")
assert(groupDebuff.visible == 1 and groupDebuff[1].auraInstanceID == 8101,
    "Classic out-of-range Only Mine broadened to a foreign debuff")

auraBySlot[101].sourceUnit = { _secret = true }
auraBySlot[101].isFromPlayerOrPlayerPet = true
auraBySlot[202].sourceUnit = { _secret = true }
auraBySlot[202].isFromPlayerOrPlayerPet = true
assert(registered.Update(groupFrame, "UNIT_AURA", "party1", { isFullUpdate = true }) == true,
    "Classic protected out-of-range Only Mine refresh did not run")
assert(groupBuff.visible == 0 and groupDebuff.visible == 0,
    "Classic protected out-of-range Only Mine displayed unverified auras")

partyInRange = true
playerFilterLeaksAll = false
auraBySlot[101].sourceUnit, auraBySlot[101].isFromPlayerOrPlayerPet = "player", nil
auraBySlot[202].sourceUnit, auraBySlot[202].isFromPlayerOrPlayerPet = "player", nil
auraBySlot[103].sourceUnit, auraBySlot[103].isFromPlayerOrPlayerPet = "party2", false
auraBySlot[204].sourceUnit, auraBySlot[204].isFromPlayerOrPlayerPet = "party2", false
auraBySlot[103].duration, auraBySlot[103].expirationTime = 0, 0
auraBySlot[204].duration, auraBySlot[204].expirationTime = 0, 0
assert(registered.Update(groupFrame, "UNIT_AURA", "party1", { isFullUpdate = true }) == true,
    "Classic in-range Only Mine recovery refresh did not run")
assert(groupBuff.visible == 1 and groupBuff[1].auraInstanceID == 7101
    and groupDebuff.visible == 1 and groupDebuff[1].auraInstanceID == 8101,
    "Classic Only Mine did not recover after returning in range")

auraBySlot[101].duration = 0
auraBySlot[101].expirationTime = 0
auraBySlot[202].duration = 0
auraBySlot[202].expirationTime = 0
assert(registered.Update(groupFrame, "UNIT_AURA", "party1", { isFullUpdate = true }) == true,
    "Classic group permanent-aura refresh did not run")
assert(groupBuff.visible == 0 and groupBuff[1]._shown == false,
    "Classic group Hide Permanent retained an own duration-zero buff")
assert(groupDebuff.visible == 0 and groupDebuff[1]._shown == false,
    "Classic group Hide Permanent retained an own duration-zero debuff")

-- Group-unit raw timing values can be protected while LuaDurationObject still
-- exposes the non-secret zero-duration classification. Timed auras must remain
-- visible and permanent auras must still be excluded in that payload shape.
auraBySlot[101].duration = { _secret = true }
auraBySlot[101].expirationTime = { _secret = true }
auraBySlot[101]._durationObjectZero = false
auraBySlot[202].duration = { _secret = true }
auraBySlot[202].expirationTime = { _secret = true }
auraBySlot[202]._durationObjectZero = false
assert(registered.Update(groupFrame, "UNIT_AURA", "party1", { isFullUpdate = true }) == true,
    "Classic protected group timed-aura refresh did not run")
assert(groupBuff.visible == 1 and groupBuff[1].auraInstanceID == 7101,
    "Classic group Hide Permanent rejected a protected timed buff")
assert(groupDebuff.visible == 1 and groupDebuff[1].auraInstanceID == 8101,
    "Classic group Hide Permanent rejected a protected timed debuff")
auraBySlot[101]._durationObjectZero = true
auraBySlot[202]._durationObjectZero = true
assert(registered.Update(groupFrame, "UNIT_AURA", "party1", { isFullUpdate = true }) == true,
    "Classic protected group permanent-aura refresh did not run")
assert(groupBuff.visible == 0 and groupBuff[1]._shown == false,
    "Classic group Hide Permanent retained a protected permanent buff")
assert(groupDebuff.visible == 0 and groupDebuff[1]._shown == false,
    "Classic group Hide Permanent retained a protected permanent debuff")

-- A secure header can rebind a group button to another unit in combat. The
-- config recompile may wait for combat end, but the aura rescan must run now
-- or the button keeps showing the previous unit's buffs and debuffs.
local savedAura101, savedAura103 = auraBySlot[101], auraBySlot[103]
local savedAura202, savedAura204 = auraBySlot[202], auraBySlot[204]
local savedHelpfulSlot2, savedHarmfulSlot2 = helpfulSlots[2], harmfulSlots[2]
local savedGroupUnitKey, savedGroupUnit = groupFrame.MSUFUnitKey, groupFrame.unit
helpfulSlots[2] = nil
harmfulSlots[2] = nil
auraBySlot[103] = nil
auraBySlot[204] = nil
auraBySlot[101] = {
    auraInstanceID = 7301, spellId = 900301, name = "Rebound Group Buff",
    icon = 134420, applications = 1, duration = 20, expirationTime = 70,
    isHelpful = true, isHarmful = false, sourceUnit = "player",
}
auraBySlot[202] = {
    auraInstanceID = 8301, spellId = 900401, name = "Rebound Group Debuff",
    icon = 134421, applications = 1, duration = 18, expirationTime = 68,
    isHelpful = false, isHarmful = true, sourceUnit = "player",
}
nativePlayerAuraIDs[7301] = true
nativePlayerAuraIDs[8301] = true
combat = true
groupFrame.MSUFUnitKey = "party3"
assert(namespace.MSUF_Auras3.OnFrameUnitChanged(groupFrame, "party1", "party3") == true,
    "Classic in-combat group rebind did not rescan the new unit")
assert(groupBuff.visible == 1 and groupBuff[1].auraInstanceID == 7301
    and groupDebuff.visible == 1 and groupDebuff[1].auraInstanceID == 8301,
    "Classic in-combat group rebind kept the previous unit's auras")
assert(namespace.MSUF_Auras3._deferredAuraRuntime == true,
    "Classic in-combat group rebind did not defer its config recompile")
combat = false
local rebindDriver = assert(namespace.MSUF_Auras3._deferredAuraRuntimeFrame,
    "Classic in-combat group rebind deferred driver missing")
rebindDriver._scripts.OnEvent(rebindDriver, "PLAYER_REGEN_ENABLED")
assert(namespace.MSUF_Auras3._deferredAuraRuntime ~= true,
    "Classic in-combat group rebind deferral did not flush after combat")

-- A hidden group child receives no UNIT_AURA. A removal delivered while it is
-- hidden must be reconciled on the next show edge instead of leaving a stale icon.
assert(groupFrame._scripts and type(groupFrame._scripts.OnHide) == "function",
    "Classic group aura OnHide reconcile hook missing")
groupFrame._shown = false
groupFrame._scripts.OnHide(groupFrame)
auraBySlot[202] = nil
groupFrame._shown = true
groupFrame._scripts.OnShow(groupFrame)
assert(groupDebuff.visible == 0 and groupBuff.visible == 1 and groupBuff[1].auraInstanceID == 7301,
    "Classic group aura OnShow did not reconcile an aura removed while hidden")
assert(groupFrame._msufA3ClassicHiddenStale == nil,
    "Classic group aura OnShow left its hidden-stale marker set")

auraBySlot[101], auraBySlot[103] = savedAura101, savedAura103
auraBySlot[202], auraBySlot[204] = savedAura202, savedAura204
helpfulSlots[2], harmfulSlots[2] = savedHelpfulSlot2, savedHarmfulSlot2
nativePlayerAuraIDs[7301] = nil
nativePlayerAuraIDs[8301] = nil
groupFrame.MSUFUnitKey, groupFrame.unit = savedGroupUnitKey, savedGroupUnit
registered.Disable(groupFrame)
auraBySlot[101] = {
    auraInstanceID = 7007, spellId = 900007, name = "Own HoT",
    icon = 134406, applications = 1, duration = 20, expirationTime = 70,
    isHelpful = true, isHarmful = false, sourceUnit = "player",
}
auraBySlot[103] = {
    auraInstanceID = 7008, spellId = 900008, name = "Foreign Buff",
    icon = 134407, applications = 1, duration = 20, expirationTime = 70,
    isHelpful = true, isHarmful = false, sourceUnit = "party2",
    isFromPlayerOrPlayerPet = false,
}
helpfulSlots[2] = 103

_G.MSUF_DB.auras3.perUnit.target.filters = { buffs = { enabled = true, raid = true }, debuffs = { enabled = true } }
local tokenScans = {}
_G.C_UnitAuras.GetUnitAuraInstanceIDs = function(_, filter)
    tokenScans[filter] = (tokenScans[filter] or 0) + 1
    if filter == "HELPFUL|RAID" then return { 7008 } end
    return {}
end
assert(namespace.MSUF_Auras3.RequestScope("target", "render-smoke-cold-retail-filter") == true,
    "Classic dormant Retail filter apply did not run")
assert(buff.visible == 2 and buff[1].auraInstanceID == 7007 and buff[2].auraInstanceID == 7008,
    "Classic dormant Retail filter changed visibility or player-first ordering")
assert((tokenScans["HELPFUL|RAID"] or 0) == 0,
    "Classic runtime still scanned a dormant Retail filter token")
_G.C_UnitAuras.GetUnitAuraInstanceIDs = nil
_G.MSUF_DB.auras3.perUnit.target.filters = { buffs = { enabled = true }, debuffs = { enabled = true } }
helpfulSlots[2] = nil
auraBySlot[103] = nil
harmfulSlots[2] = nil
auraBySlot[204] = nil
auraBySlot[101] = {
    auraInstanceID = 5005, spellId = 900005, name = "Permanent Helpful Target",
    icon = 134404, applications = 1, duration = 0, expirationTime = 0,
    isHelpful = true, isHarmful = false, isFromPlayerOrPlayerPet = false,
}
assert(namespace.MSUF_Auras3.RequestScope("target", "render-smoke-filters-off") == true,
    "Classic filter cleanup apply did not run")

-- Simulate a pooled button whose cached visibility/identity bookkeeping was
-- already invalidated before the container-off apply. Lifecycle clearing must
-- still hide the lane and the actual buttons, including portrait-parented
-- lanes that are not descendants of state.root.
local portraitHolder = setmetatable({ _shown = true }, Widget)
buff.frame:SetParent(portraitHolder)
buff.root = portraitHolder
buff[1]._msufA3Shown = nil
buff[1].auraInstanceID = nil
debuff[1]._msufA3Shown = nil
debuff[1].auraInstanceID = nil
_G.MSUF_DB.auras3.showTarget = false
assert(namespace.MSUF_Auras3.RequestScope("target", "render-smoke-disable") == true,
    "Classic target scope disable was not applied")
assert(state.root._shown == false, "Classic RequestScope did not hide disabled target auras")
assert(buff.frame._shown == false and debuff.frame._shown == false,
    "Classic RequestScope did not hide disabled aura lane frames")
assert(buff[1]._shown == false and debuff[1]._shown == false,
    "Classic RequestScope left stale pooled aura buttons visible")
_G.MSUF_DB.auras3.showTarget = true
assert(namespace.MSUF_Auras3.RequestScope("target", "render-smoke-enable") == true,
    "Classic target scope enable did not apply")
assert(state.root._shown == true and state.lanes.buff[1]._shown == true,
    "Classic RequestScope did not render re-enabled target auras")
assert(namespace.MSUF_Auras3.RefreshRuntime == namespace.MSUF_Auras3.RefreshAll,
    "Classic RefreshRuntime still points at the core no-op stub")

combat = true
assert(namespace.MSUF_Auras3.RequestScope("target", "render-smoke-combat") == false,
    "Classic aura apply was not deferred in combat")
local deferred = assert(namespace.MSUF_Auras3._deferredAuraRuntimeFrame, "Classic deferred driver missing")
combat = false
deferred._scripts.OnEvent(deferred, "PLAYER_REGEN_ENABLED")
assert(namespace.MSUF_Auras3._deferredAuraRuntime ~= true,
    "Classic deferred aura apply did not flush after combat")

-- Weapon-enchant synthetic auras reuse one data table per slot on the lane.
-- Consecutive full scans must yield identical entries on the same tables,
-- refresh changed fields in place, and leave no entry for an ended enchant.
local ENCHANT_FIELDS = {
    "auraInstanceID", "isHelpful", "isHarmful", "isFromPlayerOrPlayerPet", "isPlayerAura", "name",
    "icon", "applications", "duration", "expirationTime", "timeMod", "spellId", "_msufA3WeaponEnchantSlot",
}
local function EnchantExpected(slot, icon, applications, duration, expirationTime)
    return {
        auraInstanceID = -1000 - slot, isHelpful = true, isHarmful = false,
        isFromPlayerOrPlayerPet = true, isPlayerAura = true, name = _G.ENCHANTED or "Weapon Enchant",
        icon = icon, applications = applications, duration = duration,
        expirationTime = expirationTime, timeMod = 1, spellId = 0, _msufA3WeaponEnchantSlot = slot,
    }
end
local function AssertEnchantEntry(data, expected, label)
    assert(type(data) == "table", label .. ": weapon enchant entry missing")
    local expectedCount = 0
    for i = 1, #ENCHANT_FIELDS do
        local field = ENCHANT_FIELDS[i]
        if expected[field] ~= nil then expectedCount = expectedCount + 1 end
        assert(data[field] == expected[field], label .. ": weapon enchant field " .. field .. " was "
            .. tostring(data[field]) .. ", expected " .. tostring(expected[field]))
    end
    local fieldCount = 0
    for _ in pairs(data) do fieldCount = fieldCount + 1 end
    assert(fieldCount == expectedCount, label .. ": weapon enchant entry carried " .. fieldCount
        .. " fields, expected " .. expectedCount)
end
local function OrderedIDs(lane)
    local ids = {}
    for i = 1, lane.orderedCount or 0 do ids[#ids + 1] = tostring(lane.ordered[i]) end
    return table.concat(ids, ",")
end
local function EnchantScan(label)
    assert(registered.Update(playerFrame, "WEAPON_ENCHANT_CHANGED") == true, label .. " did not run")
end

EnchantScan("first weapon-enchant scan")
local mainEnchant, offEnchant = playerBuff.all[-1016], playerBuff.all[-1017]
AssertEnchantEntry(playerBuff.all[-1016], EnchantExpected(16, 160, 2, 600, 350), "first scan main hand")
AssertEnchantEntry(playerBuff.all[-1017], EnchantExpected(17, 170, 1, 1800, 1250), "first scan off hand")
local firstVisible, firstOrder = playerBuff.visible, OrderedIDs(playerBuff)
assert(firstOrder:find("^%-1017,%-1016") and playerBuff.active[-1017] == true
    and playerBuff.active[-1016] == true and playerBuff[1]._msufA3WeaponEnchantSlot == 17
    and playerBuff[2]._msufA3WeaponEnchantSlot == 16,
    "first weapon-enchant scan changed lane order or activity: " .. firstOrder)

EnchantScan("second weapon-enchant scan")
assert(rawequal(playerBuff.all[-1016], mainEnchant) and rawequal(playerBuff.all[-1017], offEnchant),
    "consecutive weapon-enchant scans did not reuse the per-slot data tables")
AssertEnchantEntry(playerBuff.all[-1016], EnchantExpected(16, 160, 2, 600, 350), "second scan main hand")
AssertEnchantEntry(playerBuff.all[-1017], EnchantExpected(17, 170, 1, 1800, 1250), "second scan off hand")
assert(playerBuff.visible == firstVisible and OrderedIDs(playerBuff) == firstOrder
    and playerBuff[1]._msufA3WeaponEnchantSlot == 17 and playerBuff[2]._msufA3WeaponEnchantSlot == 16,
    "consecutive weapon-enchant scans produced different lane results")

local savedEnchantInfo, savedItemTexture = _G.GetWeaponEnchantInfo, _G.GetInventoryItemTexture
_G.GetWeaponEnchantInfo = function()
    return true, 900000, 5, 0, false, nil, 0, 0, false, nil, 0, 0
end
_G.GetInventoryItemTexture = function(_, slot)
    if slot == 16 then return nil end
    return slot * 10
end
EnchantScan("weapon-enchant scan after the off-hand enchant ended")
assert(playerBuff.all[-1017] == nil and playerBuff.active[-1017] == nil
    and (playerBuff.visibleByID or {})[-1017] == nil
    and not ("," .. OrderedIDs(playerBuff) .. ","):find(",-1017,", 1, true),
    "ended off-hand weapon enchant left a stale lane entry")
assert(rawequal(playerBuff.all[-1016], mainEnchant),
    "changed main-hand weapon enchant did not reuse its slot data table")
AssertEnchantEntry(playerBuff.all[-1016], EnchantExpected(16, nil, 5, 1800, 950), "changed main hand")
assert(playerBuff.visible == firstVisible - 1 and playerBuff[1]._msufA3WeaponEnchantSlot == 16,
    "ended off-hand weapon enchant still rendered")
for i = 1, playerBuff.visible do
    assert(playerBuff[i]._msufA3WeaponEnchantSlot ~= 17,
        "ended off-hand weapon enchant kept a visible button")
end

_G.GetWeaponEnchantInfo, _G.GetInventoryItemTexture = savedEnchantInfo, savedItemTexture
EnchantScan("weapon-enchant scan after the off-hand enchant returned")
assert(rawequal(playerBuff.all[-1017], offEnchant) and rawequal(playerBuff.all[-1016], mainEnchant),
    "returning weapon enchant did not reuse its slot data table")
AssertEnchantEntry(playerBuff.all[-1016], EnchantExpected(16, 160, 2, 600, 350), "restored main hand")
AssertEnchantEntry(playerBuff.all[-1017], EnchantExpected(17, 170, 1, 1800, 1250), "restored off hand")
assert(playerBuff.visible == firstVisible and OrderedIDs(playerBuff) == firstOrder,
    "restored weapon enchants changed lane results")

-- Token-filter membership is cached per unit and per filter until that unit's
-- next UNIT_AURA bumps its serial. Two units and two filters must never share
-- a cached set, a repeat query must not rescan, and an aura add or remove must
-- reach only the unit whose event arrived.
local tokenSet = assert(namespace.MSUF_Auras3._ClassicAuraTokenSet,
    "Classic token-membership accessor missing")
local memberIDs = {
    target = { ["HELPFUL|PLAYER"] = { 7007 }, ["HARMFUL|PLAYER"] = { 7201 } },
    player = { ["HELPFUL|PLAYER"] = { 9101 }, ["HARMFUL|PLAYER"] = { 9201, 9202 } },
}
local membershipScans = {}
_G.C_UnitAuras.GetUnitAuraInstanceIDs = function(unit, filter)
    local scanKey = unit .. "/" .. filter
    membershipScans[scanKey] = (membershipScans[scanKey] or 0) + 1
    local ids = memberIDs[unit] and memberIDs[unit][filter] or {}
    local out = {}
    for i = 1, #ids do out[i] = ids[i] end
    return out
end
local MEMBERSHIP_QUERIES = {
    { "target", "HELPFUL|PLAYER" }, { "target", "HARMFUL|PLAYER" },
    { "player", "HELPFUL|PLAYER" }, { "player", "HARMFUL|PLAYER" },
}
local function AssertMembership(expected, expectedScans, label)
    for i = 1, #MEMBERSHIP_QUERIES do
        local unit, filter = MEMBERSHIP_QUERIES[i][1], MEMBERSHIP_QUERIES[i][2]
        local ids = {}
        for id in pairs(tokenSet(unit, filter)) do ids[#ids + 1] = id end
        table.sort(ids)
        local actual = table.concat(ids, ",")
        assert(actual == expected[i], label .. ": " .. unit .. " " .. filter
            .. " membership was '" .. actual .. "', expected '" .. expected[i] .. "'")
        local scans = membershipScans[unit .. "/" .. filter] or 0
        assert(scans == expectedScans[i], label .. ": " .. unit .. " " .. filter
            .. " membership scanned " .. scans .. " times, expected " .. expectedScans[i])
    end
end

-- Bump both serials first so sets cached by earlier sections cannot answer.
registered.Update(frame, "UNIT_AURA", "target", { isFullUpdate = true })
registered.Update(playerFrame, "UNIT_AURA", "player", { isFullUpdate = true })
AssertMembership({ "7007", "7201", "9101", "9201,9202" }, { 1, 1, 1, 1 }, "initial token membership")
AssertMembership({ "7007", "7201", "9101", "9201,9202" }, { 1, 1, 1, 1 }, "repeat token membership")
assert(rawequal(tokenSet("target", "HELPFUL|PLAYER"), tokenSet("target", "HELPFUL|PLAYER"))
    and not rawequal(tokenSet("target", "HELPFUL|PLAYER"), tokenSet("player", "HELPFUL|PLAYER"))
    and not rawequal(tokenSet("target", "HELPFUL|PLAYER"), tokenSet("target", "HARMFUL|PLAYER")),
    "Classic token membership sets were shared across units or filters")

-- An aura added on the target stays invisible to the cached set until the
-- target's own UNIT_AURA arrives, and that event must not rescan the player.
memberIDs.target["HELPFUL|PLAYER"] = { 7007, 7011 }
AssertMembership({ "7007", "7201", "9101", "9201,9202" }, { 1, 1, 1, 1 }, "token membership before the target add event")
registered.Update(frame, "UNIT_AURA", "target", { addedAuras = { {
    auraInstanceID = 7011, spellId = 900011, name = "Membership Add",
    icon = 134430, applications = 1, duration = 10, expirationTime = 60,
    isHelpful = true, isHarmful = false, sourceUnit = "player",
} } })
AssertMembership({ "7007,7011", "7201", "9101", "9201,9202" }, { 2, 2, 1, 1 }, "token membership after the target add")

memberIDs.player["HARMFUL|PLAYER"] = { 9202 }
registered.Update(playerFrame, "UNIT_AURA", "player", { removedAuraInstanceIDs = { 9201 } })
AssertMembership({ "7007,7011", "7201", "9101", "9202" }, { 2, 2, 2, 2 }, "token membership after the player remove")

memberIDs.target["HELPFUL|PLAYER"] = { 7007 }
registered.Update(frame, "UNIT_AURA", "target", { removedAuraInstanceIDs = { 7011 } })
AssertMembership({ "7007", "7201", "9101", "9202" }, { 3, 3, 2, 2 }, "token membership after the target remove")

-- An update-only payload refreshes existing auras and cannot change filter
-- membership, so the cached sets must answer; a full update rebuilds them.
registered.Update(frame, "UNIT_AURA", "target", { updatedAuraInstanceIDs = { 7007 } })
AssertMembership({ "7007", "7201", "9101", "9202" }, { 3, 3, 2, 2 }, "token membership after a target update-only payload")
registered.Update(frame, "UNIT_AURA", "target", { isFullUpdate = true })
AssertMembership({ "7007", "7201", "9101", "9202" }, { 4, 4, 2, 2 }, "token membership after a target full update")
-- A newly applied config rescans its lanes, so even an update-only payload
-- that applies it must rebuild the sets.
namespace.MSUF_Auras3.BumpRuntimeConfig()
registered.Update(frame, "UNIT_AURA", "target", { updatedAuraInstanceIDs = { 7007 } })
AssertMembership({ "7007", "7201", "9101", "9202" }, { 5, 5, 2, 2 }, "token membership after a target config apply")
_G.C_UnitAuras.GetUnitAuraInstanceIDs = nil

-- A deferred flush consumes its queue only as work completes. A Lua error while
-- applying one scope must keep that scope queued and PLAYER_REGEN_ENABLED
-- registered; a scope that already applied is consumed.
do
    local A3 = namespace.MSUF_Auras3
    assert(A3._deferredAuraRuntime == nil, "Classic deferred aura queue was not empty before the flush checks")
    local driver = assert(A3._deferredAuraRuntimeFrame, "Classic deferred driver missing")
    local function Armed() return driver._events ~= nil and driver._events.PLAYER_REGEN_ENABLED == true end
    local function QueueInCombat(...)
        combat = true
        for i = 1, select("#", ...) do
            assert(A3.RefreshUnit((select(i, ...))) == false, "Classic in-combat RefreshUnit was not deferred")
        end
        combat = false
    end
    local realRefreshUnit = A3.RefreshUnit
    local calls = {}
    local function FailOnCall(failAt)
        calls = {}
        A3.RefreshUnit = function(scope)
            calls[#calls + 1] = scope
            if #calls == failAt then error("render smoke: injected aura apply failure", 0) end
            return realRefreshUnit(scope)
        end
    end

    QueueInCombat("target", "focus")
    assert(A3._deferredAuraRuntime == true and A3._deferredAuraRuntimeScopes.target == true
        and A3._deferredAuraRuntimeScopes.focus == true and Armed(),
        "Classic in-combat RefreshUnit did not queue both scopes with the combat-end event")
    -- Fire the combat-end event itself, so the driver's own unregister is
    -- covered along with the flush.
    FailOnCall(2)
    local ok, err = pcall(driver._scripts.OnEvent, driver, "PLAYER_REGEN_ENABLED")
    A3.RefreshUnit = realRefreshUnit
    assert(ok == false and tostring(err):find("injected aura apply failure", 1, true) and #calls == 2,
        "Classic deferred flush did not surface the injected apply failure")
    local scopes = A3._deferredAuraRuntimeScopes
    assert(A3._deferredAuraRuntime == true and scopes ~= nil and scopes[calls[2]] == true,
        "Classic deferred flush dropped the scope whose apply failed")
    assert(scopes[calls[1]] == nil, "Classic deferred flush kept a scope that already applied")
    assert(Armed(), "Classic deferred flush unregistered PLAYER_REGEN_ENABLED before its queue was consumed")
    driver._scripts.OnEvent(driver, "PLAYER_REGEN_ENABLED")
    assert(A3._deferredAuraRuntime == nil and A3._deferredAuraRuntimeScopes == nil and not Armed(),
        "Classic combat-end retry did not consume the stale aura queue")

    -- Out of combat, RefreshAll and a scoped RequestApply also retry a stale queue.
    QueueInCombat("target")
    FailOnCall(1)
    assert(pcall(A3._FlushDeferredAuraRuntime) == false, "Classic deferred flush ignored the injected failure")
    A3.RefreshUnit = realRefreshUnit
    assert(A3._deferredAuraRuntimeScopes.target == true and Armed(), "Classic failed flush lost its queue")
    assert(A3.RefreshAll() == true and A3._deferredAuraRuntime == nil and not Armed(),
        "Classic RefreshAll did not consume a stale aura queue")

    QueueInCombat("target")
    FailOnCall(1)
    assert(pcall(A3._FlushDeferredAuraRuntime) == false, "Classic deferred flush ignored the injected failure")
    A3.RefreshUnit = realRefreshUnit
    A3.RequestApply("focus", "render-smoke-stale-queue")
    assert(A3._deferredAuraRuntime == nil and A3._deferredAuraRuntimeScopes == nil and not Armed(),
        "Classic scoped RequestApply did not consume a stale aura queue")
end

print("classic aura render smoke passed: " .. backendPath)
