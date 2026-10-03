-- Classic aura backend: group-frame aura lanes place their stack and cooldown
-- text from the per-lane settings Menu2 Auras > Group writes (Stack Anchor,
-- Stack X/Y, Cooldown X/Y). ApplyAuraLane in
-- UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua stores them as
-- <lane>StackAnchor, <lane>StackX, <lane>StackY, <lane>CooldownX and
-- <lane>CooldownY, as Retail's CompileGroupLane reads them
-- (Auras3/Runtime/MSUF_Auras3_Runtime_LaneConfig.lua).
--   * every lane (buff, tracked buff, debuff, external) compiles its own values
--   * a source without them keeps the old placement (root stack anchor, or
--     BOTTOMRIGHT, and no offset)
--   * a recompiled group spec (a new table, as GF.InvalidateCompiledSpecs
--     builds) and a scoped invalidation of an edited one both reach the lane
--   * the buttons place the stack count at every anchor the group dropdown
--     offers, justified as the menu preview places it, and the cooldown text
--     at its offset
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

-- Widget stub: regions remember their last anchor and justification ---------------------
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
function Widget:SetJustifyH(value) self._justifyH = value end
function Widget:SetJustifyV(value) self._justifyV = value end
function Widget:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "OUTLINE" end
function Widget:GetNumRegions() return self._regions and #self._regions or 0 end
function Widget:GetRegions() if self._regions then return unpack(self._regions) end end
function Widget:CreateTexture() return setmetatable({ _shown = true, _parent = self, _objectType = "Texture" }, Widget) end
Widget.CreateMaskTexture = Widget.CreateTexture
function Widget:CreateFontString() return setmetatable({ _shown = true, _parent = self, _objectType = "FontString" }, Widget) end
for _, name in ipairs({
    "RegisterEvent", "UnregisterEvent", "RegisterUnitEvent", "SetAllPoints", "SetAlpha", "EnableMouse", "SetSize",
    "SetWidth", "SetHeight", "SetDrawSwipe", "SetHideCountdownNumbers", "SetSwipeColor", "SetDrawEdge", "SetTexCoord",
    "SetFont", "SetTextColor", "SetShadowOffset", "SetDesaturated", "SetBlendMode", "SetMinMaxValues", "SetValue",
    "SetStatusBarTexture", "SetStatusBarColor", "SetColorTexture", "SetReverse", "SetMouseClickEnabled",
    "SetMouseMotionEnabled", "SetCountdownMillisecondsThreshold", "SetSwipeTexture", "SetFrameStrata", "SetOwner",
    "SetCooldown", "Clear", "SetAtlas", "AddMaskTexture", "RemoveMaskTexture", "SetTexture", "SetText", "SetVertexColor",
}) do
    Widget[name] = Widget[name] or function() end
end
_G.CreateFrame = function(frameType, _, parent)
    local frame = setmetatable({ _shown = true, _parent = parent, _objectType = frameType }, Widget)
    -- CooldownFrameTemplate owns the countdown FontString the backend repositions.
    if frameType == "Cooldown" then frame._regions = { frame:CreateFontString() } end
    return frame
end

-- Aura API stub ---------------------------------------------------------------------------
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
})
local client = namespace.Client
assert(client and client.IsClassic == true and client.Flavor == flavor,
    "precondition: the client model did not place " .. flavor)
assert(registered, "Classic aura element did not register")
local A3 = namespace.MSUF_Auras3
local Resolve = A3._ClassicCompile.ResolveGroupFrameConfig

local function Fail(label, message) error(("%s (%s): %s"):format(label, flavor, message), 2) end

--- A group aura spec as ApplyAuraLane writes it: the root keeps the constant
--- stackAnchor (Group_Config's spec root), every lane its own text settings.
local LANES = { "buff", "trackedBuff", "debuff", "external" }
local function Source(perLane)
    local source = {
        enabled = true, stackAnchor = "BOTTOMRIGHT",
        showBuffs = true, maxBuffs = 4, buffFilter = "HELPFUL",
        showTrackedBuffs = true, maxTrackedBuffs = 4, trackedBuffFilter = "HELPFUL",
        showDebuffs = true, maxDebuffs = 4, debuffFilter = "HARMFUL",
        showExternals = true, maxExternals = 2,
    }
    for i, kind in ipairs(LANES) do
        local values = perLane and perLane[kind]
        if values then
            source[kind .. "StackAnchor"] = values.anchor
            source[kind .. "StackX"], source[kind .. "StackY"] = values.stackX or i, values.stackY or -i
            source[kind .. "CooldownX"], source[kind .. "CooldownY"] = values.cooldownX or 10 + i, values.cooldownY or -10 - i
        end
    end
    return source
end

local function ExpectLane(lane, label, anchor, stackX, stackY, cooldownX, cooldownY)
    if not lane then Fail(label, "lane did not compile") end
    local got = ("%s %s/%s cooldown %s/%s"):format(tostring(lane.stackAnchor), tostring(lane.stackX),
        tostring(lane.stackY), tostring(lane.cooldownX), tostring(lane.cooldownY))
    local want = ("%s %s/%s cooldown %s/%s"):format(anchor, stackX, stackY, cooldownX, cooldownY)
    if got ~= want then Fail(label, "compiled stack " .. got .. ", expected " .. want) end
end

-- 1. Every lane compiles its own values; no per-lane keys keeps the old placement --------
local perLane = {
    buff = { anchor = "TOPLEFT", stackX = 5, stackY = -3, cooldownX = 4, cooldownY = 2 },
    trackedBuff = { anchor = "BOTTOMLEFT" },
    debuff = { anchor = "TOPRIGHT" },
    external = { anchor = "CENTER" },
}
local frame = { MSUFUnitKey = "party1", _msufIsGroupFrame = true, _msufGFKind = "party",
    MSUFSpec = { scope = "group", auras = Source(perLane) } }
local cfg = Resolve(frame, "party1")
ExpectLane(cfg.lanes.buff, "buff lane", "TOPLEFT", 5, -3, 4, 2)
ExpectLane(cfg.lanes.trackedBuff, "tracked buff lane", "BOTTOMLEFT", 2, -2, 12, -12)
ExpectLane(cfg.lanes.debuff, "debuff lane", "TOPRIGHT", 3, -3, 13, -13)
ExpectLane(cfg.lanes.external, "external lane", "CENTER", 4, -4, 14, -14)

local legacy = { MSUFUnitKey = "party2", _msufIsGroupFrame = true, _msufGFKind = "party",
    MSUFSpec = { scope = "group", auras = Source(nil) } }
legacy.MSUFSpec.auras.stackAnchor = "TOPLEFT"
cfg = Resolve(legacy, "party2")
for _, kind in ipairs(LANES) do ExpectLane(cfg.lanes[kind], kind .. " lane without per-lane keys", "TOPLEFT", 0, 0, 0, 0) end
legacy.MSUFSpec = { scope = "group", auras = Source(nil) }
legacy.MSUFSpec.auras.stackAnchor = nil
legacy.MSUFSpec.auras.buffStackAnchor = "NOT_AN_ANCHOR"
cfg = Resolve(legacy, "party2")
ExpectLane(cfg.lanes.buff, "buff lane with an unknown anchor", "BOTTOMRIGHT", 0, 0, 0, 0)

-- 2. Both write paths reach a cached config ----------------------------------------------
-- A group geometry apply recompiles the spec into new tables.
frame.MSUFSpec = { scope = "group", auras = Source({ buff = { anchor = "BOTTOM", stackX = -6, stackY = 7,
    cooldownX = -8, cooldownY = 9 } }) }
ExpectLane(Resolve(frame, "party1").lanes.buff, "buff lane after a recompiled spec", "BOTTOM", -6, 7, -8, 9)
-- An edit of the same table is seen after the scoped invalidation the menu model sends.
local source = frame.MSUFSpec.auras
source.buffStackAnchor, source.buffStackX, source.buffStackY = "LEFT", 1, 2
source.buffCooldownX, source.buffCooldownY = 3, 4
assert(A3.InvalidateGroupRuntimeConfig("party") == true, "precondition: party invalidation refused")
ExpectLane(Resolve(frame, "party1").lanes.buff, "buff lane after a scoped invalidation", "LEFT", 1, 2, 3, 4)

-- 3. The buttons place the text ------------------------------------------------------------
world.party3 = { { auraInstanceID = 501, spellId = 9501, name = "Renew", icon = 1, applications = 3, duration = 15,
    expirationTime = 60, isHelpful = true, isHarmful = false, isFromPlayerOrPlayerPet = true, mine = true } }
local JUSTIFY = {
    TOPLEFT = { "LEFT", "TOP" }, TOP = { "CENTER", "TOP" }, TOPRIGHT = { "RIGHT", "TOP" },
    LEFT = { "LEFT", "MIDDLE" }, CENTER = { "CENTER", "MIDDLE" }, RIGHT = { "RIGHT", "MIDDLE" },
    BOTTOMLEFT = { "LEFT", "BOTTOM" }, BOTTOM = { "CENTER", "BOTTOM" }, BOTTOMRIGHT = { "RIGHT", "BOTTOM" },
}
for anchor, justify in pairs(JUSTIFY) do
    local label = "stack count at " .. anchor
    local group = setmetatable({ _shown = true, MSUFUnitKey = "party3", _msufIsGroupFrame = true,
        _msufGFKind = "party", _msufActiveElements = { Auras = true }, MSUFSpec = { scope = "group",
            auras = Source({ buff = { anchor = anchor, stackX = 6, stackY = -2, cooldownX = 3, cooldownY = 5 } }) } }, Widget)
    registered.Create(group)
    registered.Enable(group)
    local button = group._msufA3State and group._msufA3State.lanes.buff and group._msufA3State.lanes.buff[1]
    if not (button and button.Count) then Fail(label, "no buff button was rendered") end
    local point = button.Count._point
    if not (point and point.point == anchor and point.relativeTo == button and point.relativePoint == anchor
        and point.x == 6 and point.y == -2) then
        Fail(label, ("stack count placed at %s %s/%s"):format(tostring(point and point.point),
            tostring(point and point.x), tostring(point and point.y)))
    end
    if button.Count._justifyH ~= justify[1] or button.Count._justifyV ~= justify[2] then
        Fail(label, "stack count justified " .. tostring(button.Count._justifyH) .. "/" .. tostring(button.Count._justifyV))
    end
    local text = button.Cooldown and button.Cooldown._regions and button.Cooldown._regions[1]
    local cdPoint = text and text._point
    if not (cdPoint and cdPoint.point == "CENTER" and cdPoint.x == 3 and cdPoint.y == 5) then
        Fail(label, ("cooldown text placed at %s %s/%s"):format(tostring(cdPoint and cdPoint.point),
            tostring(cdPoint and cdPoint.x), tostring(cdPoint and cdPoint.y)))
    end
end

print("classic aura group text offsets smoke passed: " .. flavor)
