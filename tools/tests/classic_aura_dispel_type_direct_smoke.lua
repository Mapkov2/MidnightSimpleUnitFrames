-- Classic aura backend: the "Any dispel type" (DISPEL_TYPE) border and overlay
-- light for any debuff that has a dispel type, whoever can dispel it, on the
-- direct visual path as on the lane path (MatchDispelTrigger in
-- Game/Classic/Auras/MSUF_Auras3_Filters.lua). HARMFUL|RAID is not that query:
-- on every Classic client it keeps only the debuffs the PLAYER can dispel
-- (Blizzard's AuraUtil.lua and Blizzard_RaidUI.xml pair it with the
-- showDispelDebuffs option; live AuraUtil documents RAID as "harmful auras the
-- player can dispel"; MSUF uses it as the Classic Era "dispellable by me"
-- filter). The player here is a Warrior and dispels nothing, and the stub's
-- RAID tokens follow the client.
--   * a target frame with the aura icons off and no filter work reads the
--     border from the unit (visualDirect): a Magic debuff behind an untyped
--     one lights it, untyped debuffs alone leave it dark
--   * the same with the debuff icons on, and for the overlay
--   * a group frame whose debuff lane scans natively with PLAYER (Only mine)
--     reads it from the unit the same way
--   * the direct path stays direct and cheap: no lane scan with the icons off,
--     an add or remove reads the debuffs up to the first typed one (40 at
--     most), and an update-only payload reads nothing
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
-- Classic aura data is never secret.
_G.issecretvalue = function() return false end

-- Widget stub ---------------------------------------------------------------------------
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
function Widget:GetNumRegions() return 0 end
function Widget:GetRegions() return nil end
function Widget:GetObjectType() return self._objectType or "Frame" end
function Widget:CreateTexture() return setmetatable({ _shown = true, _parent = self }, Widget) end
Widget.CreateMaskTexture = Widget.CreateTexture
Widget.CreateFontString = Widget.CreateTexture
for _, name in ipairs({
    "RegisterEvent", "UnregisterEvent", "RegisterUnitEvent", "ClearAllPoints", "SetAllPoints", "SetAlpha",
    "EnableMouse", "SetPoint", "SetSize", "SetWidth", "SetHeight", "SetDrawSwipe", "SetHideCountdownNumbers",
    "SetSwipeColor", "SetDrawEdge", "SetTexCoord", "SetFont", "SetTextColor", "SetShadowOffset", "SetDesaturated",
    "SetJustifyH", "SetJustifyV", "SetBlendMode", "SetMinMaxValues", "SetValue", "SetStatusBarTexture",
    "SetStatusBarColor", "SetColorTexture", "SetReverse", "SetMouseClickEnabled", "SetMouseMotionEnabled",
    "SetCountdownMillisecondsThreshold", "SetSwipeTexture", "SetFrameStrata", "SetOwner", "SetCooldown", "Clear",
    "SetAtlas", "AddMaskTexture", "RemoveMaskTexture", "SetTexture", "SetText", "SetVertexColor",
}) do
    Widget[name] = Widget[name] or function() end
end
_G.CreateFrame = function(frameType, _, parent)
    return setmetatable({ _shown = true, _parent = parent, _objectType = frameType }, Widget)
end

-- Aura API stub with the client's filter semantics ---------------------------------------
local PLAYER_CAN_DISPEL = {} -- a Warrior removes no dispel type
local world = {}
local api = { index = 0, slots = 0 }
local unknownFilters = {}
local function UnitList(unit) world[unit] = world[unit] or {}; return world[unit] end
local function Matches(aura, filter)
    local helpful, harmful = false, false
    for token in filter:gmatch("[^|]+") do
        if token == "HELPFUL" then
            helpful = true
        elseif token == "HARMFUL" then
            harmful = true
        elseif token == "PLAYER" then
            if aura.mine ~= true then return false end
        elseif token == "RAID" or token == "RAID_PLAYER_DISPELLABLE" then
            -- HARMFUL|RAID and HARMFUL|RAID_PLAYER_DISPELLABLE: debuffs the player can dispel.
            if not (aura.isHarmful == true and PLAYER_CAN_DISPEL[aura.dispelName or ""] == true) then return false end
        else
            unknownFilters[#unknownFilters + 1] = filter
            return false
        end
    end
    if helpful == harmful then unknownFilters[#unknownFilters + 1] = filter; return false end
    return harmful == (aura.isHarmful == true)
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
_G.DebuffTypeColor = { Magic = { r = 0.20, g = 0.60, b = 1.00, a = 1 } }
_G.C_UnitAuras = {
    GetAuraSlots = function(unit, filter)
        api.slots = api.slots + 1
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
        api.index = api.index + 1
        local n = 0
        for _, aura in ipairs(UnitList(unit)) do
            if Matches(aura, filter) then n = n + 1; if n == index then return aura end end
        end
        return nil
    end,
}
_G.AuraUtil = {}

local function DB(targetIcons)
    _G.MSUF_DB = { general = {}, auras3 = { enabled = true, showTarget = targetIcons == true, shared = {}, perUnit = {
        target = { layout = {}, layoutShared = { showBuffs = false, showDebuffs = true }, filters = { debuffs = {} } },
    } } }
end
DB(false)

local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
manifest.LoadSelected(root, flavor, namespace, {
    "Game/Shared/Initialize.lua",
    "Runtime/MSUF_BorderStyles.lua",
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

local nextID = 7000
local function Debuff(dispelName, mine)
    nextID = nextID + 1
    return {
        auraInstanceID = nextID, spellId = 900000 + nextID, name = "Debuff" .. nextID, icon = 134400,
        applications = 1, duration = 30, expirationTime = 80, isHelpful = false, isHarmful = true,
        isFromPlayerOrPlayerPet = mine == true, mine = mine == true, dispelName = dispelName, sourceUnit = "boss1",
    }
end

local function NewFrame(unit, spec, group)
    local frame = setmetatable({ _shown = true, MSUFUnitKey = unit, _msufActiveElements = { Auras = true },
        MSUFSpec = spec }, Widget)
    if group then frame._msufIsGroupFrame, frame._msufGFKind = true, "party" end
    frame.hpBar = _G.CreateFrame("StatusBar", nil, frame)
    registered.Create(frame)
    registered.Enable(frame)
    return frame
end

local function Expect(frame, field, tokenField, aura, label)
    local active = frame[field] == true
    assert(active == (aura ~= nil), ("%s (%s): %s=%s, expected %s"):format(label, flavor, field,
        tostring(frame[field]), tostring(aura ~= nil)))
    if aura then
        assert(frame[tokenField] == aura.auraInstanceID, ("%s (%s): lit for aura %s, expected %s"):format(label,
            flavor, tostring(frame[tokenField]), tostring(aura.auraInstanceID)))
    end
end
local function ExpectBorder(frame, aura, label)
    return Expect(frame, "_msufA3DispelActive", "_msufA3DispelToken", aura, label)
end

local function Calls(fn)
    local index, slots = api.index, api.slots
    fn()
    return api.index - index, api.slots - slots
end

local borderSpec = { border = { dispel = true, dispelTrigger = "DISPEL_TYPE" } }

-- 1. Icons off, no filter work: the border is read from the unit -------------------------
local untyped, magic = Debuff(nil), Debuff("Magic")
world.target = { untyped, magic }
local target = NewFrame("target", borderSpec)
assert(A3.ResolveUnitFrameConfig("target", borderSpec).visualDirect == true,
    "precondition: an icon-less Any dispel type border is not a direct visual (" .. flavor .. ")")
ExpectBorder(target, magic, "icons off, Magic debuff behind an untyped one")

-- The direct path stays direct and reads only up to the first typed debuff.
local index, slots = Calls(function()
    registered.Update(target, "UNIT_AURA", "target", { updatedAuraInstanceIDs = { magic.auraInstanceID } })
end)
assert(index == 0 and slots == 0, ("update-only payload read %d indexes and %d slot lists (%s)"):format(index, slots, flavor))
world.target = { magic }
index, slots = Calls(function()
    registered.Update(target, "UNIT_AURA", "target", { removedAuraInstanceIDs = { untyped.auraInstanceID } })
end)
ExpectBorder(target, magic, "icons off, Magic debuff alone")
assert(index == 1 and slots == 0, ("typed debuff first: %d index reads and %d slot lists, expected 1 and 0 (%s)")
    :format(index, slots, flavor))
world.target = { untyped, magic }
index, slots = Calls(function()
    registered.Update(target, "UNIT_AURA", "target", { addedAuras = { untyped } })
end)
ExpectBorder(target, magic, "icons off, untyped debuff added before the Magic one")
assert(index == 2 and slots == 0, ("typed debuff second: %d index reads and %d slot lists, expected 2 and 0 (%s)")
    :format(index, slots, flavor))
local untyped2 = Debuff(nil)
world.target = { untyped, untyped2 }
index, slots = Calls(function()
    registered.Update(target, "UNIT_AURA", "target",
        { addedAuras = { untyped2 }, removedAuraInstanceIDs = { magic.auraInstanceID } })
end)
ExpectBorder(target, nil, "icons off, untyped debuffs only")
assert(index == 3 and slots == 0, ("no typed debuff: %d index reads and %d slot lists, expected 3 and 0 (%s)")
    :format(index, slots, flavor))
-- The walk is bounded: 40 index reads at most, however many debuffs answer.
local many = {}
for i = 1, 50 do many[i] = Debuff(nil) end
world.target = many
index, slots = Calls(function()
    registered.Update(target, "UNIT_AURA", "target", { addedAuras = { many[50] } })
end)
ExpectBorder(target, nil, "icons off, 50 untyped debuffs")
assert(index == 40 and slots == 0, ("50 untyped debuffs: %d index reads and %d slot lists, expected 40 and 0 (%s)")
    :format(index, slots, flavor))

-- 2. Overlay on the same trigger, without the border -------------------------------------
world.target = { untyped, magic }
local overlaySpec = { border = { dispel = false }, dispelOverlay = { enabled = true, trigger = "DISPEL_TYPE" } }
local overlay = NewFrame("target", overlaySpec)
assert(A3.ResolveUnitFrameConfig("target", overlaySpec).visualDirect == true,
    "precondition: an icon-less Any dispel type overlay is not a direct visual (" .. flavor .. ")")
Expect(overlay, "_msufA3DispelOverlayActive", "_msufA3DispelOverlayToken", magic, "icons off, overlay")

-- 3. Debuff icons on, still no filter work ----------------------------------------------
DB(true)
A3.BumpRuntimeConfig()
local iconSpec = { border = { dispel = true, dispelTrigger = "DISPEL_TYPE" } }
local icons = NewFrame("target", iconSpec)
local iconCfg = A3.ResolveUnitFrameConfig("target", iconSpec)
assert(iconCfg.visualDirect == true and iconCfg.lanes.debuff and iconCfg.lanes.debuff.renderEnabled == true,
    "precondition: the debuff icons are not on beside a direct border (" .. flavor .. ")")
ExpectBorder(icons, magic, "icons on, Magic debuff behind an untyped one")

-- 4. Group frame, Only mine debuff lane (native PLAYER scan) ------------------------------
world.party1 = { Debuff(nil), Debuff("Curse") }
local groupSpec = { scope = "group", border = { dispel = true, dispelTrigger = "DISPEL_TYPE" }, auras = {
    enabled = true, showDebuffs = true, maxDebuffs = 4, debuffFilter = "HARMFUL|PLAYER",
} }
local group = NewFrame("party1", groupSpec, true)
local groupCfg = assert(group._msufA3GroupConfig, "group aura config missing (" .. flavor .. ")")
assert(groupCfg.visualDirect == true and groupCfg.lanes.debuff.nativePlayerFilter == true,
    "precondition: an Only mine group debuff lane is not a native PLAYER scan (" .. flavor .. ")")
ExpectBorder(group, world.party1[2], "group Only mine lane, Curse debuff from another caster")

assert(#unknownFilters == 0, "the backend queried an unsupported filter: " .. tostring(unknownFilters[1]))
print("classic aura dispel type direct smoke passed: " .. flavor)
