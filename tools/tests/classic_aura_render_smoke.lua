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
    return unit == "player" or unit == "party1" or (unit == "target" and targetExists)
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
local function FilteredAuraSlots(slots, filter)
    local playerOnly = filter and filter:find("|PLAYER", 1, true) ~= nil
    local out = {}
    for i = 1, #slots do
        local slot = slots[i]
        local data = auraBySlot[slot]
        if data and (not playerOnly or nativePlayerAuraIDs[data.auraInstanceID] == true) then
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

print("classic aura render smoke passed: " .. backendPath)
