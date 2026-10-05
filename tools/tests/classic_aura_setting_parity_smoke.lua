-- Classic aura backend: settings the shared menu offers on every client reach
-- the Classic lanes the way Retail compiles them. Runs the real backend chain
-- of one Classic flavor in its TOC order with counting stubs.
--   * a corner Custom Spell slot scans with its Filter (buff or debuff, any
--     caster or cast by me), as Retail scans customFilter
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

print("classic aura setting parity smoke passed: " .. flavor)
