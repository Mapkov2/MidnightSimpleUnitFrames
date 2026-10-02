-- Classic aura backend: fixes from the 2026-09-30 aura review (F*, R*) and the
-- 2026-10-01 quality review (C3.*), run against the real backend files with
-- widget, C_UnitAuras, UnitCanAssist and UnitGUID stubs.
-- Each section names the finding it pins and fails on the code before its fix.
-- Arguments: repository root, then optionally the backend, features, compile
-- and visuals paths (mutation runs).
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))
local ADDON = root .. "/MidnightSimpleUnitFrames/"
local overrides = {
    ["Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua"] = arg[2],
    ["Game/Classic/Auras/MSUF_Auras3_Features.lua"] = arg[3],
    ["Game/Classic/Auras/MSUF_Auras3_Compile.lua"] = arg[4],
    ["Game/Classic/Auras/MSUF_Auras3_Visuals.lua"] = arg[5],
}

local registered
local namespace = {
    Client = { IsClassic = true, DispellableDebuffFilter = "HARMFUL|RAID_PLAYER_DISPELLABLE" },
    MSUF_Auras3 = {},
    UF = { RegisterElement = function(_, element) registered = element end, Config = { serial = 1 } },
    ExportPublic = function(name, value) _G[name] = value; return value end,
}
_G.MSUF_NS, _G.MSUF = namespace, namespace
_G.issecretvalue = function(value) return type(value) == "table" and value._secret == true end

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
function Widget:SetTexture(texture) self._texture = texture end
function Widget:SetText(text) self._text = text end
function Widget:SetVertexColor(r, g, b, a) self._vr, self._vg, self._vb, self._va = r, g, b, a end
function Widget:SetFont(path, size, flags) self._font, self._fontSize, self._fontFlags = path, size, flags end
function Widget:SetMouseClickEnabled(enabled) self._mouseClickEnabled = enabled end
function Widget:SetMouseMotionEnabled(enabled) self._mouseMotionEnabled = enabled end
function Widget:RegisterEvent(event) self._events = self._events or {}; self._events[event] = true end
function Widget:RegisterUnitEvent(event) self._events = self._events or {}; self._events[event] = true end
function Widget:UnregisterEvent(event) if self._events then self._events[event] = nil end end
function Widget:GetNumRegions() return 0 end
function Widget:GetRegions() return nil end
function Widget:GetObjectType() return self._objectType or "Frame" end
function Widget:CreateTexture() return setmetatable({ _shown = true, _parent = self }, Widget) end
Widget.CreateMaskTexture = Widget.CreateTexture
Widget.CreateFontString = Widget.CreateTexture
for _, name in ipairs({
    "ClearAllPoints", "SetAllPoints", "SetAlpha", "EnableMouse", "SetPoint",
    "SetSize", "SetWidth", "SetHeight", "SetDrawSwipe", "SetHideCountdownNumbers", "SetSwipeColor", "SetDrawEdge",
    "SetTexCoord", "SetTextColor", "SetShadowOffset", "SetDesaturated", "SetJustifyH", "SetJustifyV",
    "SetBlendMode", "SetMinMaxValues", "SetValue", "SetStatusBarTexture", "SetStatusBarColor", "SetColorTexture",
    "SetReverse", "SetCountdownMillisecondsThreshold",
    "SetSwipeTexture", "SetFrameStrata", "SetOwner", "SetCooldown", "Clear", "SetAtlas", "AddMaskTexture",
    "RemoveMaskTexture",
}) do Widget[name] = function() end end
function Widget:SetCooldownTextColor(r, g, b) self._textR, self._textG, self._textB = r, g, b end
local pulses = { play = 0, stop = 0 }
function Widget:CreateAnimationGroup()
    local group = { playing = false }
    function group:CreateAnimation()
        local animation = {}
        function animation:SetFromAlpha() end
        function animation:SetToAlpha() end
        function animation:SetDuration() end
        function animation:SetSmoothing() end
        return animation
    end
    function group:SetLooping() end
    function group:IsPlaying() return self.playing end
    function group:Play() pulses.play = pulses.play + 1; self.playing = true end
    function group:Stop() pulses.stop = pulses.stop + 1; self.playing = false end
    return group
end
-- Widget writes, counted while a check measures an unchanged refresh.
local writes = { counting = false, n = 0, names = {} }
for name, fn in pairs(Widget) do
    if type(fn) == "function" and (name:match("^Set") or name:match("^Clear") or name == "Show" or name == "Hide") then
        Widget[name] = function(self, ...)
            if writes.counting then
                writes.n = writes.n + 1
                writes.names[name] = (writes.names[name] or 0) + 1
            end
            return fn(self, ...)
        end
    end
end
local createdFrames = {}
_G.CreateFrame = function(frameType, _, parent)
    local frame = setmetatable({ _shown = true, _parent = parent, _objectType = frameType }, Widget)
    createdFrames[#createdFrames + 1] = frame
    return frame
end
--- The Classic aura visuals' shared timer driver: the one frame created with an OnUpdate.
local function TimerDriver()
    for i = 1, #createdFrames do
        local frame = createdFrames[i]
        if frame._scripts and frame._scripts.OnUpdate and frame._objectType == "Frame" then return frame end
    end
end

--- Bytes allocated per call with the collector stopped, so nothing is freed.
local function BytesPerCall(fn, n)
    collectgarbage("collect"); collectgarbage("collect"); collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, n do fn() end
    local after = collectgarbage("count")
    collectgarbage("restart")
    return (after - before) * 1024 / n
end

-- Game API stubs ------------------------------------------------------------------------
-- The backend binds GetAuraSlots and friends as locals at load, so every knob
-- below is data these functions read, never a replacement function.
local world, assistable, guids, exists = {}, {}, {}, {}
local api = { slots = 0, index = 0, assist = 0, guid = 0, byID = 0, unitIsUnit = 0, bySlot = 0, ids = 0 }
local slotFilters = {}
local snapshots = true
local function Snapshot(aura)
    if not (snapshots and aura) then return aura end
    local copy = {}
    for key, value in pairs(aura) do copy[key] = value end
    return copy
end
local function UnitList(unit) world[unit] = world[unit] or {}; return world[unit] end
local function Matches(aura, filter)
    if filter:find("HARMFUL", 1, true) then
        if aura.isHarmful ~= true then return false end
    elseif aura.isHelpful ~= true then
        return false
    end
    if filter:find("|PLAYER", 1, true) and aura.mine ~= true then return false end
    if filter:find("RAID_PLAYER_DISPELLABLE", 1, true) and aura.dispellable ~= true then return false end
    -- Classification tokens apply only to an aura that declares its own set,
    -- so the sections written before C3.4 keep their token-blind membership.
    if aura.tokens then
        for token in filter:gmatch("[^|]+") do
            if token ~= "HELPFUL" and token ~= "HARMFUL" and token ~= "PLAYER"
                and token ~= "RAID_PLAYER_DISPELLABLE" and aura.tokens[token] ~= true then
                return false
            end
        end
    end
    return true
end
_G.UnitExists = function(unit) return exists[unit] ~= false end
_G.UnitIsUnit = function(a, b) api.unitIsUnit = api.unitIsUnit + 1; return a == b end
_G.UnitInRange = function() return true, true end
_G.UnitCanAssist = function(source, unit)
    api.assist = api.assist + 1
    if source ~= "player" then error("Show on asked UnitCanAssist about " .. tostring(source)) end
    return assistable[unit] == true
end
_G.UnitGUID = function(unit) api.guid = api.guid + 1; return guids[unit] end
_G.GetTime = function() return 50 end
local combat = false
_G.InCombatLockdown = function() return combat end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.GameTooltip = setmetatable({}, Widget)
_G.C_Timer = {}
_G.DebuffTypeColor = {
    none = { r = 0.80, g = 0.00, b = 0.00 },
    Magic = { r = 0.20, g = 0.60, b = 1.00 },
    Curse = { r = 0.60, g = 0.00, b = 1.00 },
    Disease = { r = 0.60, g = 0.40, b = 0.00 },
    Poison = { r = 0.00, g = 0.60, b = 0.00 },
}
_G.C_UnitAuras = {
    GetAuraSlots = function(unit, filter)
        api.slots = api.slots + 1
        slotFilters[filter] = (slotFilters[filter] or 0) + 1
        local list, out = UnitList(unit), {}
        for i = 1, #list do if Matches(list[i], filter) then out[#out + 1] = i end end
        return nil, unpack(out)
    end,
    GetAuraDataBySlot = function(unit, slot) api.bySlot = api.bySlot + 1; return Snapshot(UnitList(unit)[slot]) end,
    GetAuraDataByAuraInstanceID = function(unit, id)
        api.byID = api.byID + 1
        local list = UnitList(unit)
        for i = 1, #list do if list[i].auraInstanceID == id then return Snapshot(list[i]) end end
        return nil
    end,
    GetAuraDataByIndex = function(unit, index, filter)
        api.index = api.index + 1
        local n, list = 0, UnitList(unit)
        for i = 1, #list do
            if Matches(list[i], filter) then n = n + 1; if n == index then return Snapshot(list[i]) end end
        end
        return nil
    end,
}
_G.AuraUtil = {}

local nextID = 5000
local function Aura(helpful, fields)
    nextID = nextID + 1
    local aura = {
        auraInstanceID = nextID, spellId = 900000 + nextID, name = "Aura" .. nextID, icon = 134400 + nextID,
        applications = 1, duration = 30, expirationTime = 80, isHelpful = helpful, isHarmful = not helpful,
        isFromPlayerOrPlayerPet = false,
    }
    for key, value in pairs(fields or {}) do aura[key] = value end
    return aura
end
local function Magic(fields)
    local aura = Aura(false, { dispelName = "Magic", dispellable = true })
    for key, value in pairs(fields or {}) do aura[key] = value end
    return aura
end

local function Profile(perUnit)
    return {
        general = {},
        auras3 = {
            enabled = true, showPlayer = true, showTarget = true, showFocus = true, showBoss = true,
            shared = {},
            perUnit = perUnit or {},
        },
    }
end
--- Replaces MSUF_DB's contents in place, the way the profile layer switches.
local function LoadProfile(profile)
    for key in pairs(_G.MSUF_DB) do _G.MSUF_DB[key] = nil end
    for key, value in pairs(profile) do _G.MSUF_DB[key] = value end
end
_G.MSUF_DB = Profile()

-- Load the real chain in the shipped TOC order -------------------------------------------
local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
local chain = {
    "Auras3/MSUF_Auras3_Core.lua", "Auras3/MSUF_Auras3_IconShape.lua", "Game/Classic/Auras/MSUF_Auras3_DataShared.lua",
    "Game/Classic/Auras/MSUF_Auras3_Visuals.lua", "Game/Classic/Auras/MSUF_Auras3_Features.lua",
    "Game/Classic/Auras/MSUF_Auras3_Compile.lua",
    "Game/Classic/Auras/MSUF_Auras3_Buttons.lua", "Game/Classic/Auras/MSUF_Auras3_Filters.lua",
    "Game/Classic/Auras/MSUF_Auras3_FrameVisuals.lua", "Game/Classic/Auras/MSUF_Auras3_Lanes.lua",
    "Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua", "Game/Classic/Auras/MSUF_Auras3_Requests.lua",
    "Game/Classic/Auras/MSUF_Auras3_Preview.lua",
}
local overridePaths = {}
for relative, path in pairs(overrides) do overridePaths[ADDON .. relative] = path end
manifest.LoadSelected(root, "Vanilla", namespace, chain, function(path)
    return loadfile(overridePaths[path] or path)
end)
assert(registered, "Classic aura element did not register")
local A3 = namespace.MSUF_Auras3

--- mayStayOff: a frame whose element the test expects to stay disabled.
local function NewFrame(unit, spec, fields, mayStayOff)
    local frame = setmetatable({
        _shown = true, MSUFUnitKey = unit, _msufActiveElements = { Auras = true }, MSUFSpec = spec or {},
    }, Widget)
    for key, value in pairs(fields or {}) do frame[key] = value end
    frame.hpBar = _G.CreateFrame("StatusBar", nil, frame)
    registered.Create(frame)
    local enabled = registered.Enable(frame) == true
    assert(enabled or mayStayOff == true, unit .. " aura element did not enable")
    return frame, enabled
end
local function GroupFields(kind)
    return { _msufIsGroupFrame = true, _msufGFKind = kind or "party" }
end
local function Update(frame, payload) return registered.Update(frame, "UNIT_AURA", frame.MSUFUnitKey, payload) end
local function Border(frame) return frame._msufA3DispelActive == true end
local function Overlay(frame) return frame._msufA3DispelOverlayActive == true end
local function VisibleIDs(lane)
    local ids = {}
    for i = 1, lane.visible do ids[i] = tostring(lane[i].auraInstanceID) end
    return table.concat(ids, ",")
end
local function IDs(...)
    local ids = {}
    for i = 1, select("#", ...) do ids[i] = tostring((select(i, ...)).auraInstanceID) end
    return table.concat(ids, ",")
end
local function Visible(frame, kind)
    local lane = frame._msufA3State and frame._msufA3State.lanes[kind]
    return lane and lane.visible or 0
end

-- Group frame API: the frames the backend re-applies for a group or shared scope.
local groupFrames = {}
namespace.GF = {
    ForEachFrame = function(fn)
        local any = false
        for i = 1, #groupFrames do
            local frame = groupFrames[i]
            if fn(frame, frame.MSUFUnitKey, frame._msufGFKind) == true then any = true end
        end
        return any
    end,
    CompileSpec = function(_, frame) return frame.MSUFSpec end,
    FrameForUnit = function(unit)
        for i = 1, #groupFrames do
            if groupFrames[i].MSUFUnitKey == unit then return groupFrames[i] end
        end
    end,
    -- No live group runtime or preview here: their refreshes have nothing to redraw.
    RefreshVisuals = function() end,
    RefreshPreviewLayout = function() end,
    DIRTY_AURAS = 0x40,
}
local currentFont = "Fonts\\FontA.ttf"
-- Castbars_Core.lua publishes this as MSUF.MSUF_GetGlobalFontSettings in game.
namespace.MSUF_GetGlobalFontSettings = function() return currentFont, "OUTLINE", 1, 1, 1, nil, false end
local function Config(frame) return frame._msufA3State and frame._msufA3State.config end
local function Lane(frame, kind) return frame._msufA3State and frame._msufA3State.lanes[kind] end
local function ReplayUnitAura(frame) return Update(frame, { updatedAuraInstanceIDs = { UnitList(frame.MSUFUnitKey)[1].auraInstanceID } }) end

-- F1. A profile switch, reset, import or Profile Variant reaches Classic unit-frame auras
do
    local function TargetProfile(maxBuffs)
        return Profile({ target = {
            layout = {}, layoutShared = { showBuffs = true, showDebuffs = false, maxBuffs = maxBuffs }, filters = {},
        } })
    end
    LoadProfile(TargetProfile(12))
    A3.BumpRuntimeConfig()
    world.target = { Aura(true), Aura(true), Aura(true), Aura(true) }
    local target = NewFrame("target", {})
    assert(Lane(target, "buff").config.max == 12 and Visible(target, "buff") == 4,
        "F1: precondition: profile A does not show four target buffs")

    -- The profile layer swaps MSUF_DB's contents, re-applies the elements and
    -- then runs the font followers, which end in ApplyFontsFromGlobal().
    LoadProfile(TargetProfile(2))
    A3.ApplyFontsFromGlobal()
    assert(Lane(target, "buff").config.max == 2 and Visible(target, "buff") == 2,
        "F1: after a profile switch the target buff lane kept the old profile's maximum ("
        .. tostring(Lane(target, "buff").config.max) .. ")")

    -- No refresh at all: the next UNIT_AURA notices the swapped profile table.
    LoadProfile(TargetProfile(3))
    ReplayUnitAura(target)
    assert(Lane(target, "buff").config.max == 3 and Visible(target, "buff") == 3,
        "F1: a UNIT_AURA after a profile switch kept rendering the previous profile")

    -- The unit-frame compiler refills the same spec table in place and bumps
    -- UF.Config.serial: a portrait shape that FOLLOW_PORTRAIT lanes read.
    _G.MSUF_DB.auras3.shared.appearanceIconShapes = { buff = "FOLLOW_PORTRAIT", debuff = "FOLLOW_PORTRAIT" }
    A3.BumpRuntimeConfig()
    local spec = target.MSUFSpec
    spec.portrait = { enabled = true, shape = "CIRCLE" }
    ReplayUnitAura(target)
    local before = Config(target)
    for key in pairs(spec) do spec[key] = nil end
    spec.portrait = { enabled = true, shape = "DIAMOND" }
    namespace.UF.Config.serial = namespace.UF.Config.serial + 1
    local resolved = A3.ResolveUnitFrameConfig("target", spec)
    assert(resolved ~= before, "F1: an in-place unit-frame respec returned the stale compiled aura config")
    ReplayUnitAura(target)
    assert(Config(target) == resolved and Lane(target, "buff").config.iconShape ~= before.lanes.buff.iconShape,
        "F1: an in-place unit-frame respec did not reach the target aura lanes")

    -- Group frames follow the global font follower too, fonts included.
    world.party1 = { Aura(true), Aura(false) }
    local party = NewFrame("party1", { scope = "group", auras = {
        enabled = true, showBuffs = true, maxBuffs = 4, showDebuffs = true, maxDebuffs = 4,
    } }, GroupFields("party"))
    groupFrames[#groupFrames + 1] = party
    local partyButton = Lane(party, "buff")[1]
    assert(partyButton and partyButton.Count._font == currentFont, "F1: precondition: the party aura font was not applied")
    currentFont = "Fonts\\FontB.ttf"
    A3.ApplyFontsFromGlobal()
    assert(partyButton.Count._font == "Fonts\\FontB.ttf", "F1: a global font change left the party aura fonts stale")
    assert(Lane(target, "buff")[1].Count._font == "Fonts\\FontB.ttf", "F1: a global font change left the target aura fonts stale")
    groupFrames[#groupFrames] = nil
end

-- F7. A scoped refresh invalidates only its own frames ---------------------------------
do
    LoadProfile(Profile({
        target = { layout = {}, layoutShared = { showBuffs = true, showDebuffs = true }, filters = {} },
        focus = { layout = {}, layoutShared = { showBuffs = true, showDebuffs = true }, filters = {} },
        boss1 = { layout = {}, layoutShared = { showBuffs = true, showDebuffs = true }, filters = {} },
    }))
    A3.BumpRuntimeConfig()
    world.target, world.focus, world.boss1, world.party2 = { Aura(true) }, { Aura(true) }, { Aura(true) }, { Aura(true) }
    local target, focus, boss = NewFrame("target", {}), NewFrame("focus", {}), NewFrame("boss1", {})
    local party = NewFrame("party2", { scope = "group", auras = { enabled = true, showBuffs = true, maxBuffs = 4 } },
        GroupFields("party"))
    local function Untouched(label, ...)
        local frames = { ... }
        local configs = {}
        for i = 1, #frames do configs[i] = Config(frames[i]) end
        local scans = api.slots
        for i = 1, #frames do ReplayUnitAura(frames[i]) end
        for i = 1, #frames do
            assert(Config(frames[i]) == configs[i], "F7: " .. label .. " recompiled " .. frames[i].MSUFUnitKey)
        end
        assert(api.slots == scans, "F7: " .. label .. " rescanned an unrelated frame")
    end
    Untouched("an update-only payload", target, focus, boss, party)

    local targetConfig = Config(target)
    A3.RefreshUnit("target")
    assert(Config(target) ~= targetConfig, "F7: precondition: RefreshUnit(target) did not recompile the target")
    Untouched("RefreshUnit(target)", focus, boss, party)

    local bossConfig = Config(boss)
    A3.RefreshUnit("boss")
    assert(Config(boss) ~= bossConfig, "F7: precondition: RefreshUnit(boss) did not recompile boss1")
    Untouched("RefreshUnit(boss)", target, focus, party)

    -- The combat-end flush applies each queued scope the same way.
    combat = true
    A3.RefreshUnit("focus")
    combat = false
    local focusConfig = Config(focus)
    A3._FlushDeferredAuraRuntime()
    assert(Config(focus) ~= focusConfig and A3._deferredAuraRuntime == nil,
        "F7: precondition: the combat-end flush did not apply the queued focus scope")
    Untouched("the combat-end flush of a focus scope", target, boss, party)

    -- A secure header rebinding a group button in combat recompiles that
    -- button alone; the unit frames keep their configs.
    combat = true
    world.party3 = { Aura(true) }
    party.MSUFUnitKey = "party3"
    A3.OnFrameUnitChanged(party, "party2", "party3")
    combat = false
    A3._FlushDeferredAuraRuntime()
    Untouched("an in-combat group rebind", target, focus, boss)

    -- The menu apply service drops one unit's cache before re-applying it.
    A3.InvalidateUnitRuntimeConfig("target")
    Untouched("InvalidateUnitRuntimeConfig(target)", focus, boss, party)
end

-- F12 (+F7). The shared menu apply refreshes the pet and bumps the generation once ------
do
    LoadProfile(Profile({
        pet = { layout = {}, layoutShared = { showBuffs = true, showDebuffs = true }, filters = {} },
        target = { layout = {}, layoutShared = { showBuffs = true, showDebuffs = true }, filters = {} },
    }))
    A3.BumpRuntimeConfig()
    assert(loadfile(ADDON .. "Auras3/MSUF_Auras3_Menu_Model.lua"))("MidnightSimpleUnitFrames", namespace)
    local Model = assert(A3.MenuModel and A3.MenuModel.Apply, "F12: the shared menu model did not load")
    world.pet, world.target = { Aura(true) }, { Aura(true) }
    local pet, target = NewFrame("pet", {}), NewFrame("target", {})
    assert(Lane(pet, "buff").config.iconShape ~= "CIRCLE", "F12: precondition: the pet already uses circle icons")
    -- Global Aura Appearance is shared: one apply without a scope.
    _G.MSUF_DB.auras3.shared.appearanceIconShapes = { buff = "CIRCLE", debuff = "CIRCLE" }
    local gen = A3._runtimeConfigGen
    A3.MenuModel.Apply(nil, "REVIEW_SMOKE_SHARED_APPLY")
    assert(Lane(target, "buff").config.iconShape == "CIRCLE",
        "F12: precondition: the shared apply did not restyle the target")
    assert(Lane(pet, "buff").config.iconShape == "CIRCLE",
        "F12: the shared menu apply left the pet on the previous Global Aura Appearance")
    assert(A3._runtimeConfigGen == gen + 1, "F7: one shared menu apply bumped the runtime generation "
        .. tostring(A3._runtimeConfigGen - gen) .. " times")
end

-- C3.3 (review 2026-10-01). A group-scope menu apply keeps the unit-frame configs ------
-- The shared menu model invalidates a group scope through
-- A3.InvalidateGroupRuntimeConfig and bumps the global generation only when
-- that is missing, which it was on Classic: every party edit made every unit
-- frame recompile and rescan on its next UNIT_AURA.
do
    LoadProfile(Profile({
        target = { layout = {}, layoutShared = { showBuffs = true, showDebuffs = true }, filters = {} },
    }))
    A3.BumpRuntimeConfig()
    local Model = A3.MenuModel
    assert(Model and Model.Apply, "C3.3: precondition: the shared menu model is not loaded")
    world.target, world.party1 = { Aura(true) }, { Aura(true), Aura(true), Aura(true) }
    local target = NewFrame("target", {})
    local partySpec = { scope = "group", auras = { enabled = true, showBuffs = true, maxBuffs = 4 } }
    local party = NewFrame("party1", partySpec, GroupFields("party"))
    groupFrames[#groupFrames + 1] = party
    assert(Visible(party, "buff") == 3, "C3.3: precondition: the party frame does not show three buffs")
    local targetConfig, gen = Config(target), A3._runtimeConfigGen
    -- The group settings are edited in place, then the party scope is applied.
    partySpec.auras.maxBuffs = 2
    Model.Apply("party", "C33_PARTY_APPLY")
    assert(A3._runtimeConfigGen == gen, "C3.3: a party apply bumped the global runtime generation")
    assert(Visible(party, "buff") == 2, "C3.3: the party apply did not reach the party frame")
    local scans = api.slots
    ReplayUnitAura(target)
    assert(Config(target) == targetConfig and api.slots == scans,
        "C3.3: a party apply made the target frame recompile and rescan")
    -- Another kind's apply leaves the party frame's compiled config alone.
    local partyConfig = Config(party)
    Model.Apply("raid", "C33_RAID_APPLY")
    ReplayUnitAura(party)
    assert(Config(party) == partyConfig, "C3.3: a raid apply recompiled the party frame")
    assert(A3._runtimeConfigGen == gen, "C3.3: a raid apply bumped the global runtime generation")
    groupFrames[#groupFrames] = nil
end

-- F2. Cleanse visuals never follow the Debuffs lane's icon filters ---------------------
do
    local function TargetFilters(debuffFilters, extra)
        local unit = { layout = {}, layoutShared = { showBuffs = false, showDebuffs = true }, filters = { debuffs = debuffFilters } }
        for key, value in pairs(extra or {}) do unit[key] = value end
        LoadProfile(Profile({ target = unit }))
        A3.BumpRuntimeConfig()
    end
    local cleanse = { border = { dispel = true, dispelTrigger = "BY_ME" } }

    -- A healer's target debuffs on Only mine: a friend's Magic debuff cast by
    -- someone else still lights "Dispellable by me".
    TargetFilters({ enabled = true, onlyMine = true })
    local foreignMagic = Magic({ mine = false })
    world.target = { foreignMagic }
    local target = NewFrame("target", cleanse)
    assert(Visible(target, "debuff") == 0, "F2: precondition: Only mine showed another caster's debuff icon")
    assert(Border(target), "F2: Only mine on the Debuffs lane hid the cleanse border")
    table.remove(world.target)
    Update(target, { removedAuraInstanceIDs = { foreignMagic.auraInstanceID } })
    assert(not Border(target), "F2: the cleanse border outlived its debuff")
    world.target[1] = foreignMagic
    Update(target, { addedAuras = { Snapshot(foreignMagic) } })
    assert(Border(target), "F2: a delta-added foreign Magic debuff did not light the Only mine cleanse border")

    -- Blacklist and Hide permanent drop icons, never the border; the debuff
    -- reaches the lane both by a full scan and by a delta.
    local permanentMagic = Magic({ duration = 0, expirationTime = 0 })
    TargetFilters({ hidePermanent = true }, { overrideBlacklist = true, blacklist = { debuffs = { spells = { [foreignMagic.spellId] = true } } } })
    world.target = { foreignMagic }
    target = NewFrame("target", cleanse)
    assert(Visible(target, "debuff") == 0 and Border(target), "F2: a blacklisted Magic debuff hid the cleanse border")
    -- The lane's cached visual already holds the blacklisted aura; a refresh keeps it (R3).
    Update(target, { updatedAuraInstanceIDs = { foreignMagic.auraInstanceID } })
    assert(Border(target), "F2: rebuilding the lane visual after a refresh skipped the blacklisted Magic debuff")
    world.target = {}
    Update(target, { isFullUpdate = true })
    assert(not Border(target), "F2: precondition: the border stayed without a debuff")
    world.target[1] = permanentMagic
    Update(target, { addedAuras = { Snapshot(permanentMagic) } })
    assert(Visible(target, "debuff") == 0 and Border(target),
        "F2: a delta-added Magic debuff that Hide permanent drops did not light the cleanse border")

    -- Party frames on the Player debuff filter, icons shown and hidden: border
    -- and overlay still follow every dispellable debuff.
    for _, showDebuffs in ipairs({ true, false }) do
        world.party1 = { Magic({ mine = false }) }
        A3.BumpRuntimeConfig()
        local party = NewFrame("party1", {
            scope = "group",
            border = { dispel = true, dispelTrigger = "BY_ME" },
            group = { dispelOverlayEnabled = true, dispelOverlayTrigger = "BORDER" },
            auras = { enabled = true, showDebuffs = showDebuffs, maxDebuffs = 3, debuffFilter = "HARMFUL|PLAYER" },
        }, GroupFields("party"), true)
        assert(Border(party) and Overlay(party), "F2: the Player debuff filter hid the party cleanse border/overlay (icons "
            .. (showDebuffs and "shown" or "hidden") .. ")")
    end

    -- Symbols on an Only mine lane name every dispel type on the unit; the
    -- debuff stripe alone keeps following the lane's own filter.
    world.party2 = { Magic({ mine = false }), Aura(false, { dispelName = "Curse", mine = false }) }
    A3.BumpRuntimeConfig()
    local symbolSpec = {
        scope = "group",
        border = { dispel = true, dispelTrigger = "DISPEL_TYPE" },
        group = { debuffStripeEnabled = true },
        dispelSymbol = { enabled = true, mode = "ALL", trigger = "DISPEL_TYPE", style = "MSUF_LETTERS" },
        auras = { enabled = true, showDebuffs = true, maxDebuffs = 3, debuffFilter = "HARMFUL|PLAYER" },
    }
    local party2 = NewFrame("party2", symbolSpec, GroupFields("party"))
    local present = party2._msufA3ClassicDispelPresent
    assert(party2._msufA3ClassicDispelSymbolsActive == true and present and present.Magic == true and present.Curse == true,
        "F2: an Only mine lane hid other casters' dispel types from the symbols")
    assert(party2._msufA3DebuffStripeActive ~= true,
        "F2: the debuff stripe showed debuffs the Player filter does not match")
    local own = Aura(false, { mine = true, sourceUnit = "player", isFromPlayerOrPlayerPet = true })
    world.party2[#world.party2 + 1] = own
    Update(party2, { addedAuras = { Snapshot(own) } })
    assert(party2._msufA3DebuffStripeActive == true, "F2: the debuff stripe missed the player's own debuff")

    -- On a lane-scanned frame Hide permanent hides a permanent Magic debuff:
    -- the cleanse border still sees it, the filter-following stripe does not.
    world.party3 = { Magic({ duration = 0, expirationTime = 0 }) }
    A3.BumpRuntimeConfig()
    local party3 = NewFrame("party3", {
        scope = "group",
        border = { dispel = true, dispelTrigger = "BY_ME" },
        group = { debuffStripeEnabled = true },
        auras = { enabled = true, showDebuffs = true, maxDebuffs = 3, debuffHidePermanent = true },
    }, GroupFields("party"))
    assert(Visible(party3, "debuff") == 0 and Border(party3),
        "F2: Hide permanent hid the cleanse border on a lane-scanned party frame")
    assert(party3._msufA3DebuffStripeActive ~= true,
        "F2: the debuff stripe showed a debuff the lane's Hide permanent filter drops")
end

-- F22. A custom container's auto-exclusion keeps the capped visible-only scan ----------
do
    LoadProfile(Profile({ target = {
        layout = {}, layoutShared = { showBuffs = true, showDebuffs = false, maxBuffs = 2, buffSortMethod = "INSTANCE_ID" },
        filters = {},
    } }))
    _G.MSUF_DB.auras3.customContainers = { perUnit = { target = { items = {
        [1] = { enabled = true, auraType = "BUFF", spellIDs = "640001", placed = { size = 20, max = 4, perRow = 4 } },
    } } } }
    A3.BumpRuntimeConfig()
    local excluded = Aura(true, { spellId = 640001 })
    world.target = { excluded, Aura(true), Aura(true), Aura(true), Aura(true) }
    local target = NewFrame("target", {})
    local lane = Lane(target, "buff")
    assert(lane.config.classicExcludeSpellIDs and lane.config.classicExcludeSpellIDs[640001] == true,
        "F22: precondition: the container did not auto-exclude its spell from the Buff lane")
    assert(lane.config.cappedFilterScan == true and lane._msufA3CappedFullScan == true,
        "F22: an auto-exclusion turned the Buff lane's capped scan into a full walk")
    assert(Visible(target, "buff") == 2 and lane.active[excluded.auraInstanceID] == nil,
        "F22: the capped scan showed the excluded aura or the wrong count")
    _G.MSUF_DB.auras3.customContainers = nil
end

-- F11. Only APIs Blizzard's Classic UI calls: per-type colours and token membership -------
do
    -- The harness, like Blizzard's Classic UI, has neither C_CurveUtil nor
    -- C_UnitAuras.GetAuraDispelTypeColor: the profile's per-type colours must
    -- still paint the frame border and the per-aura type border.
    assert(_G.C_CurveUtil == nil and _G.C_UnitAuras.GetAuraDispelTypeColor == nil,
        "F11: precondition: the harness models a curve API")
    LoadProfile(Profile({ target = {
        layout = {}, layoutShared = { showBuffs = false, showDebuffs = true, debuffTypeBorderMode = "BORDER" }, filters = {},
    } }))
    A3.BumpRuntimeConfig()
    local curse, typeless = Aura(false, { dispelName = "Curse" }), Aura(false)
    world.target = { curse, typeless }
    local target = NewFrame("target", {
        border = { dispel = true, dispelTrigger = "DISPEL_TYPE" },
        dispel = { colorMode = "TYPE", typeCurseR = 0.1, typeCurseG = 0.9, typeCurseB = 0.3,
            typeNoneR = 0.5, typeNoneG = 0.4, typeNoneB = 0.3 },
    })
    assert(Border(target) and target._msufA3DispelR == 0.1 and target._msufA3DispelG == 0.9
        and target._msufA3DispelB == 0.3, "F11: the frame dispel border ignored the profile's Curse colour")
    local lane = Lane(target, "debuff")
    local cursed = lane[lane.visibleByID[curse.auraInstanceID]]
    local border = cursed and cursed._msufA3DispelOverlay
    assert(border and border._shown == true and border._vr == 0.1 and border._vg == 0.9 and border._vb == 0.3,
        "F11: the per-aura dispel type border ignored the profile's Curse colour")
    -- C2: an untyped debuff takes the profile's None colour, as Blizzard's
    -- Classic AuraUtil.SetAuraBorderColor paints it; it never matches the
    -- frame's Dispel type trigger.
    local plain = lane[lane.visibleByID[typeless.auraInstanceID]]
    local none = plain and plain._msufA3DispelOverlay
    assert(none and none._shown == true and none._vr == 0.5 and none._vg == 0.4 and none._vb == 0.3,
        "C2: an untyped debuff's per-aura type border lost the profile's None colour")
    assert(target._msufA3DispelToken == curse.auraInstanceID, "C2: the untyped debuff matched the Dispel type trigger")
    -- The frame border in Type colours does the same for an Any debuff trigger.
    world.target = { typeless }
    local any = NewFrame("target", {
        border = { dispel = true, dispelTrigger = "ANY_DEBUFF" },
        dispel = { colorMode = "TYPE", typeNoneR = 0.5, typeNoneG = 0.4, typeNoneB = 0.3 },
    })
    assert(Border(any) and any._msufA3DispelR == 0.5 and any._msufA3DispelG == 0.4 and any._msufA3DispelB == 0.3,
        "C2: an Any debuff border in Type colours lost the None colour of an untyped debuff")

    -- Without the instance-ID list API, token-filter membership (Only mine
    -- deltas) walks GetAuraSlots, the pair AuraUtil.ForEachAura uses.
    assert(_G.C_UnitAuras.GetUnitAuraInstanceIDs == nil, "F11: precondition: the harness models an instance-ID list")
    LoadProfile(Profile({ target = {
        layout = {}, layoutShared = { showBuffs = true, showDebuffs = false }, filters = { buffs = { enabled = true, onlyMine = true } },
    } }))
    A3.BumpRuntimeConfig()
    world.target = {}
    target = NewFrame("target", {})
    local mine, theirs = Aura(true, { mine = true }), Aura(true, { mine = false, isFromPlayerOrPlayerPet = true })
    world.target[1], world.target[2] = mine, theirs
    Update(target, { addedAuras = { Snapshot(mine), Snapshot(theirs) } })
    lane = Lane(target, "buff")
    assert(lane.active[mine.auraInstanceID] == true and lane.active[theirs.auraInstanceID] == nil,
        "F11: Only mine membership by scan admitted the wrong delta auras")
end

-- R1. Token membership costs one instance-ID list call per rebuild once verified --------
-- Each delta add bumps the unit's serial; the Only mine lane's next membership
-- query rebuilds the HELPFUL|PLAYER set.
do
    local listBroken = false
    _G.C_UnitAuras.GetUnitAuraInstanceIDs = function(unit, filter)
        api.ids = api.ids + 1
        local out, list = {}, UnitList(unit)
        if listBroken then return out end -- the Mists failure mode of a sibling API: every aura filtered
        for i = 1, #list do if Matches(list[i], filter) then out[#out + 1] = list[i].auraInstanceID end end
        return out
    end
    local N = 10
    LoadProfile(Profile({ target = {
        layout = {}, layoutShared = { showBuffs = true, showDebuffs = true },
        filters = { buffs = { enabled = true, onlyMine = true }, debuffs = { enabled = true, onlyMine = true } },
    } }))
    A3.BumpRuntimeConfig()
    world.target = {}
    for i = 1, N do world.target[i] = Aura(true, { mine = true }) end
    world.target[N + 1] = Aura(true, { mine = false })
    local target = NewFrame("target", {})
    local function AddOwnBuff()
        local aura = Aura(true, { mine = true })
        world.target[#world.target + 1] = aura
        Update(target, { addedAuras = { Snapshot(aura) } })
        return aura
    end
    -- The first rebuild verifies the list against one slot walk; every later
    -- rebuild is one list call and reads no AuraData.
    local first = AddOwnBuff()
    local K = 8
    local slotsBefore, idsBefore = api.bySlot, api.ids
    for _ = 1, K do AddOwnBuff() end
    local walked, listed = api.bySlot - slotsBefore, api.ids - idsBefore
    assert(walked == 0 and listed == K, "R1: " .. K .. " membership rebuilds read " .. walked
        .. " AuraData by slot and made " .. listed .. " list calls (want 0 and " .. K .. ")")
    assert(A3._ClassicBackend.Filters.TokenTrust["HELPFUL|PLAYER"] == true,
        "R1: the instance-ID list was not trusted after agreeing with the slot walk")
    local lane = Lane(target, "buff")
    assert(lane.active[first.auraInstanceID] == true and lane.mine[first.auraInstanceID] == true,
        "R1: an own buff added after the verification left the Only mine lane")
    local serials = A3._ClassicBackend.Filters.TokenSerial
    local bytes = BytesPerCall(function()
        serials.target = serials.target + 1
        A3._ClassicBackend.Filters.TokenSet("target", "HELPFUL|PLAYER")
    end, 50)
    print(("R1: %d rebuilds over %d own buffs: %d AuraData reads, %d list calls; %.0f B per rebuild"):format(
        K, #world.target - 1, walked, listed, bytes))

    -- A list that disagrees with the walk is never trusted again for its filter.
    listBroken = true
    local debuffLane = Lane(target, "debuff")
    local own = Aura(false, { mine = true })
    world.target[#world.target + 1] = own
    Update(target, { addedAuras = { Snapshot(own) } })
    assert(A3._ClassicBackend.Filters.TokenTrust["HARMFUL|PLAYER"] == false and debuffLane.active[own.auraInstanceID] == true,
        "R1: a disagreeing instance-ID list was trusted or hid the player's own debuff")
    idsBefore = api.ids
    local again = Aura(false, { mine = true })
    world.target[#world.target + 1] = again
    Update(target, { addedAuras = { Snapshot(again) } })
    assert(api.ids == idsBefore and debuffLane.active[again.auraInstanceID] == true,
        "R1: membership asked a distrusted instance-ID list again")
    _G.C_UnitAuras.GetUnitAuraInstanceIDs = nil
end

-- R2. Update-only payloads leave direct cleanse visuals alone -----------------------------
-- An Only mine Debuffs lane resolves the frame's border, overlay and symbols from
-- the unit (F2); a lane-less frame does the same. An in-place refresh changes no
-- dispel type, caster or membership, so neither re-reads the unit for it.
do
    local function Costs(fn)
        local index, assist, slots, bySlot = api.index, api.assist, api.slots, api.bySlot
        fn()
        return api.index - index, api.assist - assist, api.slots - slots, api.bySlot - bySlot
    end
    local visuals = {
        border = { dispel = true, dispelTrigger = "BY_ME", dispelShowOn = "FRIENDLY" },
        dispelOverlay = { enabled = true, trigger = "DISPEL_TYPE" },
        dispelSymbol = { enabled = true, trigger = "DISPEL_TYPE" },
    }
    LoadProfile(Profile({
        target = { layout = {}, layoutShared = { showBuffs = true, showDebuffs = true },
            filters = { debuffs = { enabled = true, onlyMine = true } } },
        focus = { layout = {}, layoutShared = { showBuffs = false, showDebuffs = false }, filters = {} },
    }))
    A3.BumpRuntimeConfig()
    local own = Aura(false, { mine = true, dispelName = "Curse" })
    local foreign = Magic({ mine = false })
    local poison = Aura(false, { mine = false, dispelName = "Poison", dispellable = true })
    local hot = Aura(true, { mine = false })
    world.target = { own, foreign, poison, hot }
    world.focus = { Magic({ mine = false }), Aura(true, { mine = false }) }
    assistable.target, assistable.focus = true, true
    local target = NewFrame("target", visuals)
    local focus = NewFrame("focus", { border = { dispel = true, dispelTrigger = "BY_ME", dispelShowOn = "FRIENDLY" } })
    assert(Config(target).visualDirect == true and Lane(target, "debuff").config.nativePlayerFilter == true
        and Border(target) and Overlay(target), "R2: precondition: the Only mine lane's cleanse visuals are not direct")
    assert(Config(focus).visualDirect == true and Visible(focus, "buff") == 0 and Border(focus),
        "R2: precondition: the lane-less focus border is not direct")

    -- The first delta query rebuilds the lane's Only mine membership (R1); warm it.
    Update(target, { updatedAuraInstanceIDs = { own.auraInstanceID } })
    local M = 10
    local index, assist, slots, bySlot = Costs(function()
        for _ = 1, M do
            Update(target, { updatedAuraInstanceIDs = { foreign.auraInstanceID } })
            Update(target, { updatedAuraInstanceIDs = { hot.auraInstanceID } })
            Update(target, { updatedAuraInstanceIDs = { own.auraInstanceID } })
            Update(focus, { updatedAuraInstanceIDs = { world.focus[1].auraInstanceID } })
        end
    end)
    print(("R2: %d update-only payloads: %d GetAuraDataByIndex, %d UnitCanAssist, %d GetAuraSlots, %d AuraData by slot"):format(
        4 * M, index, assist, slots, bySlot))
    assert(index == 0 and assist == 0 and slots == 0 and bySlot == 0,
        ("R2: %d update-only payloads re-read direct visuals: %d GetAuraDataByIndex, %d UnitCanAssist, %d GetAuraSlots, %d AuraData by slot"):format(
            4 * M, index, assist, slots, bySlot))
    assert(Border(target) and Overlay(target) and Border(focus), "R2: an update-only payload dropped a direct visual")

    -- Adds and removes still re-read them.
    for i = #world.target, 1, -1 do
        if world.target[i] == foreign or world.target[i] == poison then table.remove(world.target, i) end
    end
    Update(target, { removedAuraInstanceIDs = { foreign.auraInstanceID, poison.auraInstanceID } })
    -- The player's own Curse is typed (overlay) but not dispellable here (border).
    assert(not Border(target) and Overlay(target), "R2: removing the dispellable debuffs did not re-read the direct visuals")
    world.target[#world.target + 1] = foreign
    Update(target, { addedAuras = { Snapshot(foreign) } })
    assert(Border(target) and Overlay(target), "R2: an added dispellable debuff did not light the direct border")
    local focusMagic = table.remove(world.focus, 1)
    Update(focus, { removedAuraInstanceIDs = { focusMagic.auraInstanceID } })
    assert(not Border(focus), "R2: a removed debuff kept the lane-less direct border")
end

-- R3. A refresh of a filtered-out aura keeps the lane's cached cleanse visual -------------
-- The lane-derived visual comes from every stored aura (F2). An in-place refresh
-- keeps an aura's dispel type and filter membership, so only an owner flip
-- (Cast by me) of a filtered-out aura can move it. Show on asks UnitCanAssist
-- once per visual rebuild, which counts the rebuilds.
do
    local shown = Aura(false, { sourceUnit = "player", dispelName = "Curse" })
    local hidden = Magic({ sourceUnit = "party2" })
    local function Load()
        LoadProfile(Profile({ target = {
            layout = {}, layoutShared = { showBuffs = false, showDebuffs = true }, filters = {},
            overrideBlacklist = true, blacklist = { debuffs = { spells = { [hidden.spellId] = true } } },
        } }))
        A3.BumpRuntimeConfig()
    end
    local spec = { border = { dispel = true, dispelTrigger = "PLAYER_CAST", dispelShowOn = "FRIENDLY" } }
    Load()
    world.target = { shown, hidden }
    assistable.target = true
    local target = NewFrame("target", spec)
    local lane = Lane(target, "debuff")
    assert(Config(target).visualDirect ~= true and lane.config.hasFilterWork == true
        and lane.active[hidden.auraInstanceID] == nil and lane.all[hidden.auraInstanceID] ~= nil and Border(target),
        "R3: precondition: the blacklisted debuff is not a stored, filtered-out aura under a lane-derived border")
    local M = 10
    local asked = api.assist
    for _ = 1, M do Update(target, { updatedAuraInstanceIDs = { hidden.auraInstanceID } }) end
    local rebuilds = api.assist - asked
    print(("R3: %d refreshes of a filtered-out aura: %d visual rebuilds"):format(M, rebuilds))
    assert(rebuilds == 0, ("R3: %d refreshes of a filtered-out aura rebuilt the lane visual %d times"):format(M, rebuilds))
    asked = api.assist
    Update(target, { updatedAuraInstanceIDs = { shown.auraInstanceID } })
    assert(api.assist - asked == 1 and Border(target), "R3: a refresh of a shown aura did not rebuild the lane visual")

    -- An owner flip of a filtered-out aura still moves a Cast by me border.
    world.target = { hidden }
    Update(target, { isFullUpdate = true })
    assert(not Border(target), "R3: precondition: another caster's blacklisted debuff lit Cast by me")
    hidden.sourceUnit = "player"
    Update(target, { updatedAuraInstanceIDs = { hidden.auraInstanceID } })
    assert(lane.mine[hidden.auraInstanceID] == true and Border(target),
        "R3: an owner flip of a filtered-out aura left the Cast by me border stale")
end

-- R4. The shared driver animates only duration bars on screen ---------------------------
do
    -- Visibility follows the parent chain here, as in the client.
    local savedIsVisible = Widget.IsVisible
    function Widget:IsVisible()
        local region = self
        while region do
            if region._shown ~= true then return false end
            region = region._parent
        end
        return true
    end
    LoadProfile(Profile({ target = {
        layout = {}, layoutShared = { showBuffs = true, showDebuffs = false, buffShowDurationBar = true }, filters = {},
    } }))
    A3.BumpRuntimeConfig()
    local timed = Aura(true, { duration = 30, expirationTime = 80 })
    world.target = { timed }
    local target = NewFrame("target", {})
    local buffs = Lane(target, "buff")
    local bar = buffs[buffs.visibleByID[timed.auraInstanceID]]._msufA3DurationBar
    local visuals = A3.ClassicVisuals
    assert(bar and bar:IsVisible() and visuals.TimerTracked(bar) == true,
        "R4: precondition: the visible duration bar is not on the shared driver")
    local painted = 0
    local setValue = bar.SetValue
    function bar:SetValue(value) painted = painted + 1; return setValue(self, value) end
    -- The unit frame hides: the client fires the bar's OnHide; refreshes keep coming.
    target._shown = false
    bar._scripts.OnHide(bar)
    for _ = 1, 3 do Update(target, { updatedAuraInstanceIDs = { timed.auraInstanceID } }) end
    local driver = TimerDriver()
    painted = 0
    for _ = 1, 20 do driver._scripts.OnUpdate(driver, 0.06) end
    print(("R4: 20 driver ticks under a hidden frame: %d duration bar paints"):format(painted))
    assert(visuals.TimerTracked(bar) ~= true and painted == 0,
        ("R4: a duration bar under a hidden frame stayed on the driver (%d paints in 20 ticks)"):format(painted))
    -- Shown again: one paint brings it up to date, then the driver animates it.
    target._shown = true
    painted = 0
    bar._scripts.OnShow(bar)
    assert(painted == 1 and visuals.TimerTracked(bar) == true,
        "R4: a duration bar shown again was not repainted once and tracked")
    painted = 0
    for _ = 1, 2 do driver._scripts.OnUpdate(driver, 0.06) end
    assert(painted == 2, "R4: the driver did not animate the duration bar once it was visible again")
    bar.SetValue = nil
    world.target = {}
    Update(target, { isFullUpdate = true })
    Widget.IsVisible = savedIsVisible
end

-- R5. The shared driver re-checks only countdowns on screen -----------------------------
do
    -- Visibility follows the parent chain, and a visibility edge fires OnShow
    -- or OnHide on every descendant it changes, as in the client.
    local savedIsVisible, savedShow = Widget.IsVisible, Widget.Show
    function Widget:IsVisible()
        local region = self
        while region do
            if region._shown ~= true then return false end
            region = region._parent
        end
        return true
    end
    local function Edge(root, script)
        for i = 1, #createdFrames do
            local frame = createdFrames[i]
            local handler = frame._scripts and frame._scripts[script]
            local region = frame._parent
            while region and region ~= root do region = region._parent end
            if handler and region == root and frame._shown == true then handler(frame) end
        end
    end
    function Widget:Show()
        local was = self:IsVisible()
        savedShow(self)
        if not was and self:IsVisible() then Edge(self, "OnShow") end
    end
    LoadProfile(Profile({ target = {
        layout = {}, layoutShared = { showBuffs = true, showDebuffs = false }, filters = {},
    } }))
    _G.MSUF_DB.general.aurasCooldownTextUseBuckets = true
    A3.BumpRuntimeConfig()
    local timed = Aura(true, { duration = 30, expirationTime = 80 })
    world.target = { timed }
    local target = NewFrame("target", {})
    local buffs = Lane(target, "buff")
    local cfg = buffs.config
    local cooldown = buffs[buffs.visibleByID[timed.auraInstanceID]].Cooldown
    local visuals = A3.ClassicVisuals
    assert(cfg.cooldownTextBuckets == true and cooldown:IsVisible() and visuals.TimerTracked(cooldown) == true,
        "R5: precondition: the visible countdown is not on the shared driver")
    local checks = 0
    local repaint = visuals.RepaintCooldownBucket
    visuals.RepaintCooldownBucket = function(...) checks = checks + 1; return repaint(...) end
    -- The unit frame hides; ticks, then aura refreshes and more ticks follow.
    target._shown = false
    Edge(target, "OnHide")
    local driver = TimerDriver()
    for _ = 1, 10 do driver._scripts.OnUpdate(driver, 0.3) end
    for _ = 1, 3 do Update(target, { updatedAuraInstanceIDs = { timed.auraInstanceID } }) end
    for _ = 1, 10 do driver._scripts.OnUpdate(driver, 0.3) end
    print(("R5: 20 bucket ticks under a hidden frame: %d countdown re-checks"):format(checks))
    assert(visuals.TimerTracked(cooldown) ~= true and checks == 0,
        ("R5: a countdown under a hidden frame stayed on the driver (%d re-checks in 20 ticks)"):format(checks))
    -- Shown again after the warning threshold passed: one re-check catches the
    -- colour up, then the driver tracks it.
    local savedGetTime = _G.GetTime
    _G.GetTime = function() return 70 end
    target._shown = true
    Edge(target, "OnShow")
    assert(checks == 1 and visuals.TimerTracked(cooldown) == true
        and cooldown._textR == cfg.cooldownWarnR and cooldown._textG == cfg.cooldownWarnG,
        "R5: a countdown shown again was not re-checked once and tracked")
    -- Shown past the last threshold: re-checked once, not tracked.
    target._shown = false
    Edge(target, "OnHide")
    _G.GetTime = function() return 78 end
    target._shown = true
    Edge(target, "OnShow")
    assert(checks == 2 and visuals.TimerTracked(cooldown) ~= true and cooldown._textR == cfg.cooldownUrgentR,
        "R5: a countdown shown past its last threshold stayed on the driver")
    _G.GetTime = savedGetTime
    visuals.RepaintCooldownBucket = repaint
    world.target = {}
    Update(target, { isFullUpdate = true })
    _G.MSUF_DB.general.aurasCooldownTextUseBuckets = nil
    Widget.IsVisible, Widget.Show = savedIsVisible, savedShow
end

-- C1. "Any debuff" border and overlay on an Only mine Debuffs lane ----------------------
-- The lane's native PLAYER scan sends every frame visual to the unit (F2); Any
-- debuff must read every harmful aura there, not only the player's own.
do
    LoadProfile(Profile({ target = {
        layout = {}, layoutShared = { showBuffs = false, showDebuffs = true },
        filters = { debuffs = { enabled = true, onlyMine = true } },
    } }))
    A3.BumpRuntimeConfig()
    local foreign = Aura(false, { mine = false })
    world.target = { foreign }
    local border = NewFrame("target", { border = { dispel = true, dispelTrigger = "ANY_DEBUFF" } })
    assert(Config(border).visualDirect == true and Visible(border, "debuff") == 0,
        "C1: precondition: the Only mine lane's Any debuff border is not a direct visual")
    assert(Border(border) and border._msufA3DispelToken == foreign.auraInstanceID,
        "C1: an Only mine Debuffs lane hid the Any debuff border for another caster's debuff")
    local overlay = NewFrame("target", {
        border = { dispel = true, dispelTrigger = "BY_ME" },
        dispelOverlay = { enabled = true, trigger = "ANY_DEBUFF" },
    })
    assert(not Border(overlay) and Overlay(overlay),
        "C1: an Only mine Debuffs lane hid the Any debuff overlay for another caster's debuff")
    world.target = {}
    Update(border, { removedAuraInstanceIDs = { foreign.auraInstanceID } })
    assert(not Border(border), "C1: the Any debuff border outlived the unit's last debuff")
end

-- F20. "Player first" reads the trusted player flag before any UnitIsUnit call ---------
do
    LoadProfile(Profile({ target = { layout = {}, layoutShared = { showBuffs = true, showDebuffs = false }, filters = {} } }))
    A3.BumpRuntimeConfig()
    local flagged = {}
    for i = 1, 3 do flagged[i] = Aura(true, { sourceUnit = "party2", isFromPlayerOrPlayerPet = true }) end
    local foreign = Aura(true, { sourceUnit = "party3", isFromPlayerOrPlayerPet = false })
    world.target = { flagged[1], flagged[2], flagged[3], foreign }
    local calls = api.unitIsUnit
    local target = NewFrame("target", {})
    local lane = Lane(target, "buff")
    assert(lane.config.sortOrder == 1 and lane.config.needsPlayerFlag == true,
        "F20: precondition: the target Buff lane does not sort player first")
    -- Only the one aura without the flag asks UnitIsUnit (player, pet, vehicle).
    assert(api.unitIsUnit - calls == 3, "F20: player-first sorting made " .. (api.unitIsUnit - calls)
        .. " UnitIsUnit calls for one unflagged aura")
    assert(lane.visible == 4 and lane[4].auraInstanceID == foreign.auraInstanceID,
        "F20: precondition: the flagged auras do not sort before the foreign one")
end

-- F21. A UNIT_AURA payload is shared: lanes keep their own ownership answers -------------
do
    LoadProfile(Profile({ target = { layout = {}, layoutShared = { showBuffs = true, showDebuffs = false }, filters = {} } }))
    -- Container 1 (Only mine, a native PLAYER scan) watches the same spell
    -- the Buff lane (player first, source rule) shows: they disagree on X.
    _G.MSUF_DB.auras3.customContainers = { perUnit = { target = { items = {
        [1] = { enabled = true, auraType = "BUFF", spellIDs = "650001", autoBlacklistDebuffs = false,
            filters = { enabled = true, onlyMine = true }, placed = { size = 20, max = 4, perRow = 4 } },
    } } } }
    A3.BumpRuntimeConfig()
    local older = Aura(true, { sourceUnit = "party3" })
    world.target = { older }
    local target = NewFrame("target", {})
    assert(Lane(target, "custom1") and Lane(target, "custom1").config.nativePlayerFilter == true,
        "F21: precondition: the Only mine container does not scan with the native PLAYER filter")
    -- Flagged by the client, but not the player's per Blizzard's PLAYER filter.
    local x = Aura(true, { spellId = 650001, sourceUnit = "party2", isFromPlayerOrPlayerPet = true, mine = false })
    world.target[2] = x
    local payload = Snapshot(x)
    Update(target, { addedAuras = { payload } })
    local fields = 0
    for _ in pairs(payload) do fields = fields + 1 end
    local expected = 0
    for _ in pairs(x) do expected = expected + 1 end
    assert(fields == expected and payload.isPlayerAura == nil,
        "F21: the backend wrote into the shared UNIT_AURA payload table")
    assert(VisibleIDs(Lane(target, "buff")) == IDs(x, older),
        "F21: precondition: the Buff lane does not sort the flagged aura first")
    assert(Lane(target, "custom1").active[x.auraInstanceID] == nil,
        "F21: precondition: the Only mine container admitted another caster's aura")
    -- A later re-sort of the Buff lane must still use the Buff lane's answer.
    local newer = Aura(true, { sourceUnit = "party3" })
    world.target[3] = newer
    Update(target, { addedAuras = { Snapshot(newer) } })
    assert(VisibleIDs(Lane(target, "buff")) == IDs(x, older, newer),
        "F21: another lane's ownership answer reordered the Buff lane: " .. VisibleIDs(Lane(target, "buff")))
    _G.MSUF_DB.auras3.customContainers = nil
end

-- F17. Arrival order with Reverse means newest first, in lanes as in containers ---------
do
    LoadProfile(Profile({
        focus = { layout = {}, filters = {}, layoutShared = {
            showBuffs = true, showDebuffs = false, buffSortMethod = "INSTANCE_ID", buffSortReverse = true,
        } },
    }))
    _G.MSUF_DB.auras3.customContainers = { perUnit = { focus = { items = {
        [1] = { enabled = true, auraType = "BUFF", spellIDs = "660001 660002 660003", autoBlacklistDebuffs = false,
            filters = { enabled = true }, placed = { size = 20, max = 8, perRow = 8, sortMethod = "INSTANCE_ID", sortReverse = true } },
    } } } }
    -- The own-buff highlight makes the lane resolve ownership: Reverse must
    -- still mean newest first, not "other casters first".
    _G.MSUF_DB.auras3.shared.highlightOwnBuffs = true
    A3.BumpRuntimeConfig()
    local first = Aura(true, { spellId = 660001, sourceUnit = "party2" })
    local second = Aura(true, { spellId = 660002, sourceUnit = "party3" })
    local third = Aura(true, { spellId = 660003, sourceUnit = "player", isFromPlayerOrPlayerPet = true })
    world.focus = { first, second, third }
    local focus = NewFrame("focus", {})
    local newestFirst = IDs(third, second, first)
    assert(VisibleIDs(Lane(focus, "buff")) == newestFirst,
        "F17: Arrival order with Reverse ignored Reverse on the Buff lane: " .. VisibleIDs(Lane(focus, "buff")))
    assert(VisibleIDs(Lane(focus, "custom1")) == newestFirst,
        "F17: Arrival order with Reverse is not newest first in a custom container: " .. VisibleIDs(Lane(focus, "custom1")))
    -- Applying the same compiled config again (Apply, then Enable, as
    -- UF.ApplyElementToFrame runs them) must not reverse twice.
    registered.Apply(focus)
    registered.Enable(focus)
    assert(VisibleIDs(Lane(focus, "buff")) == newestFirst and VisibleIDs(Lane(focus, "custom1")) == newestFirst,
        "F17: re-applying the config reversed the order a second time")
    -- Without ownership work the lane would render in arrival order unsorted.
    _G.MSUF_DB.auras3.shared.highlightOwnBuffs = nil
    A3.BumpRuntimeConfig()
    Update(focus, { isFullUpdate = true })
    assert(Lane(focus, "buff").config.needsPlayerFlag ~= true and VisibleIDs(Lane(focus, "buff")) == newestFirst,
        "F17: Arrival order with Reverse ignored Reverse on a Buff lane without ownership work: "
        .. VisibleIDs(Lane(focus, "buff")))
    -- A group lane honours it too.
    world.party4 = { first, second, third }
    local party = NewFrame("party4", { scope = "group", auras = {
        enabled = true, showBuffs = true, maxBuffs = 4, buffSortMethod = "INSTANCE_ID", buffSortReverse = true,
    } }, GroupFields("party"))
    assert(VisibleIDs(Lane(party, "buff")) == newestFirst,
        "F17: Arrival order with Reverse ignored Reverse on a group Buff lane: " .. VisibleIDs(Lane(party, "buff")))
    _G.MSUF_DB.auras3.customContainers = nil
end

-- F19. The compile reads the unit show flags and never writes SavedVariables ------------
do
    LoadProfile({ general = {}, auras3 = {
        enabled = true, showTarget = true, shared = {},
        perUnit = {
            focus = { layout = {}, layoutShared = { showBuffs = true, showDebuffs = true }, filters = {} },
            arena1 = { layout = {}, layoutShared = { showBuffs = true, showDebuffs = true }, filters = {} },
        },
    } })
    A3.BumpRuntimeConfig()
    local auras = _G.MSUF_DB.auras3
    local focus, arena = A3.ResolveUnitFrameConfig("focus"), A3.ResolveUnitFrameConfig("arena1")
    assert(auras.showFocus == nil and auras.showArena == nil and auras.showPlayer == nil and auras.showBoss == nil,
        "F19: compiling the unit aura configs wrote show flags into the profile")
    assert(not (focus.lanes.buff or focus.lanes.debuff) and not (arena.lanes.buff or arena.lanes.debuff),
        "F19: a profile without showFocus/showArena showed focus or arena auras (Midnight shows none)")
    assert(A3.ResolveUnitFrameConfig("target").lanes.buff ~= nil and A3.ResolveUnitFrameConfig("pet").lanes.buff ~= nil,
        "F19: precondition: explicit target or default pet auras did not compile")
end

-- F25. Engine frames keep MSUFUnitKey; the backend never writes frame.unit -------------
do
    LoadProfile(Profile({ target = { layout = {}, layoutShared = { showBuffs = true, showDebuffs = true }, filters = {} } }))
    A3.BumpRuntimeConfig()
    world.target, world.party5, world.party6 = { Aura(true) }, { Aura(true) }, { Aura(true) }
    local target = NewFrame("target", {})
    Update(target, { isFullUpdate = true })
    registered.Update(target, "PLAYER_TARGET_CHANGED")
    local party = NewFrame("party5", { scope = "group", auras = { enabled = true, showBuffs = true, maxBuffs = 4 } },
        GroupFields("party"))
    party.MSUFUnitKey = "party6"
    A3.OnFrameUnitChanged(party, "party5", "party6")
    assert(rawget(target, "unit") == nil and rawget(party, "unit") == nil,
        "F25: the Classic aura backend wrote frame.unit on an engine frame")
    assert(Lane(party, "buff").all[world.party6[1].auraInstanceID] ~= nil,
        "F25: precondition: the rebound group frame did not follow MSUFUnitKey")
end

-- F14. Dead Classic aura entry points stay gone ---------------------------------------
do
    assert(A3.UpdateMenuAuraPreview == nil and A3._ClassicMenuPreviewSourceLane == nil,
        "F14: the uncalled Classic menu aura preview (it could never render) is back")
    -- Review 2026-10-01: no caller in any addon or in a file a Classic TOC loads
    -- (A3._HideLane is called only by Retail's NativeApply, which defines its own).
    assert(A3._HideLane == nil and A3.UnitFrameOwnsUnitAura == nil and A3.IconStylePreviewForScope == nil,
        "F14: an uncalled Classic aura export (_HideLane, UnitFrameOwnsUnitAura, IconStylePreviewForScope) is back")
    -- Review 2026-10-02: A3.RenderCachedFrame had no caller on any client.
    assert(A3.RenderCachedFrame == nil, "F14: the uncalled A3.RenderCachedFrame export is back")
    local source = ""
    for _, module in ipairs({ "Buttons", "Filters", "FrameVisuals", "Lanes", "UnitFrames", "Requests" }) do
        local relative = "Game/Classic/Auras/MSUF_Auras3_" .. module .. ".lua"
        local handle = assert(io.open(overrides[relative] or (ADDON .. relative), "rb"))
        source = source .. handle:read("*a")
        handle:close()
    end
    assert(not source:find("A3.CooldownText", 1, true),
        "F14: the Classic backend calls the A3.CooldownText hook again, which no Classic file defines")
    -- Re-review 2026-10-02 (W3): no addon file, test or sibling repo calls these.
    assert(not source:find("PostCreateButton", 1, true), "F14: the never-set lane.PostCreateButton hook is back")
    for _, name in ipairs({ "MSUF_A3_RequestUnit", "MSUF_Auras3_RefreshUnit", "MSUF_Auras3_RefreshAll",
        "MSUF_Auras3_ApplyFontsFromGlobal" }) do
        assert(_G[name] == nil, "F14: the uncalled global " .. name .. " is back")
    end
    assert(A3.BackendEnabled == nil and A3.NormalizeLegacyDispelBorderMode == nil and A3.DBRef == nil,
        "F14: an unread A3 export (BackendEnabled, NormalizeLegacyDispelBorderMode, DBRef) is back")
    local Model = assert(A3.MenuModel, "F14: precondition: the shared menu model is not loaded")
    for _, name in ipairs({ "BlacklistSummary", "BlacklistPreparedCount", "UseSharedRules", "SetUseSharedRules",
        "ScopeFiltersEnabled", "SetScopeFiltersEnabled", "UseSharedVisuals", "SetUseSharedVisuals",
        "WriteGeneralBool", "WriteGeneralNumber", "WriteGeneralColor", "ReadSharedNumber", "WriteSharedNumber",
        "ReadGrowth", "WriteGrowth", "ReadRowWrap", "WriteRowWrap", "RowWrapValues",
        "GroupBlacklistSummary", "GroupBlacklistCategorySummary" }) do
        assert(Model[name] == nil, "F14: the uncalled menu model export Model." .. name .. " is back")
    end
    assert(type(_G.MSUF_SetDispelOverlayPreview) == "function" and type(_G.MSUF_SetDispelSymbolPreview) == "function",
        "F14: precondition: the live Classic dispel previews are gone")
    -- The dispel previews are an ordinary module loaded after the backend, not an
    -- installer closure the backend calls.
    assert(namespace.InstallClassicAuraPreview == nil and type(A3._ClassicBackend.Preview) == "table",
        "F14: the Classic dispel previews are installed by a closure again")
end

-- F8, F9, F4. Visuals drawn once per config, one shared timer driver, live buckets -------
do
    local DOT = 670001
    local timers = 0
    _G.C_Timer.NewTimer = function() timers = timers + 1; return { Cancel = function() end } end
    LoadProfile(Profile({ target = {
        layout = {}, filters = {},
        -- Overlay keeps the countdown on screen (Bar only hides the cooldown and its text).
        layoutShared = { showBuffs = true, showDebuffs = false, buffShowDurationBar = true, buffShowStealable = true,
            buffDurationBarDisplay = "OVERLAY" },
    } }))
    _G.MSUF_DB.general.aurasCooldownTextUseBuckets = true
    _G.MSUF_DB.auras3.customContainers = { perUnit = { target = { items = {
        [4] = { enabled = true, targetDots = true, auraType = "DEBUFF", spellIDs = tostring(DOT),
            customSpellIDs = { [DOT] = true }, filters = { onlyMine = true },
            placed = { size = 20, max = 4, perRow = 4 },
            frame = { type = "pulse", color = { 1, 0, 0, 1 }, priority = 5, thickness = 2, layer = 0 } },
    } } } }
    A3.BumpRuntimeConfig()
    local dot = Aura(false, { spellId = DOT, mine = true, sourceUnit = "player", isFromPlayerOrPlayerPet = true })
    local buff = Aura(true, { isStealable = true, duration = 30, expirationTime = 80 })
    world.target = { dot, buff }
    local target = NewFrame("target", {})
    local dots = assert(Lane(target, "custom4"), "F8: precondition: the Dots on target container is missing")
    local effectButton = dots[dots.visibleByID[dot.auraInstanceID]]
    assert(effectButton and effectButton._msufA3ClassicFrameEffectRoot
        and effectButton._msufA3ClassicFrameEffectRoot._shown == true and pulses.play == 1,
        "F8: precondition: the Pulse frame effect did not draw")
    -- F8: an unchanged refresh of either aura writes nothing and never restarts the Pulse.
    local plays, stops = pulses.play, pulses.stop
    writes.counting, writes.n, writes.names = true, 0, {}
    for _ = 1, 3 do
        Update(target, { updatedAuraInstanceIDs = { dot.auraInstanceID } })
        Update(target, { updatedAuraInstanceIDs = { buff.auraInstanceID } })
    end
    writes.counting = false
    local named = {}
    for name, count in pairs(writes.names) do named[#named + 1] = name .. "=" .. count end
    assert(writes.n == 0, "F8: an unchanged aura refresh made " .. writes.n .. " widget writes: " .. table.concat(named, " "))
    assert(pulses.play == plays and pulses.stop == stops, "F8: an unchanged refresh restarted the Pulse frame effect")
    -- "Expiring" timing schedules one timer per application, not per refresh.
    _G.MSUF_DB.auras3.customContainers.perUnit.target.items[4].frame.timing = "expiring"
    A3.BumpRuntimeConfig()
    Update(target, { isFullUpdate = true })
    timers = 0
    for _ = 1, 5 do Update(target, { updatedAuraInstanceIDs = { dot.auraInstanceID } }) end
    assert(timers == 0, "F8: an Expiring frame effect created " .. timers .. " timers over five unchanged refreshes")

    -- F9: the shown duration bar has no OnUpdate of its own; one driver animates it.
    local buffs = Lane(target, "buff")
    local bar = buffs[buffs.visibleByID[buff.auraInstanceID]]._msufA3DurationBar
    assert(bar and bar._shown == true and not (bar._scripts and bar._scripts.OnUpdate),
        "F9: a Classic duration bar runs its own per-frame OnUpdate")
    local visuals = A3.ClassicVisuals
    local driver = TimerDriver()
    assert(driver and visuals.TimerTracked(bar) == true, "F9: no shared timer driver animates the shown duration bar")

    -- F4: the countdown text walks safe -> warning -> urgent as time passes.
    local cooldown = buffs[buffs.visibleByID[buff.auraInstanceID]].Cooldown
    local cfg = buffs.config
    assert(cooldown._textR == cfg.cooldownSafeR and cooldown._textG == cfg.cooldownSafeG,
        "F4: precondition: a 30 s aura did not start in the safe colour")
    local savedGetTime = _G.GetTime
    _G.GetTime = function() return 70 end
    driver._scripts.OnUpdate(driver, 0.3)
    assert(cooldown._textR == cfg.cooldownWarnR and cooldown._textG == cfg.cooldownWarnG
        and cooldown._textB == cfg.cooldownWarnB, "F4: the countdown kept its colour after crossing the warning threshold")
    _G.GetTime = function() return 77 end
    driver._scripts.OnUpdate(driver, 0.3)
    assert(cooldown._textR == cfg.cooldownUrgentR and cooldown._textG == cfg.cooldownUrgentG
        and cooldown._textB == cfg.cooldownUrgentB, "F4: the countdown kept its colour after crossing the urgent threshold")
    assert(visuals.TimerTracked(cooldown) ~= true, "F4: a countdown past its last threshold stayed on the timer driver")
    _G.GetTime = savedGetTime
    -- Nothing tracked: the driver stops.
    world.target = {}
    Update(target, { isFullUpdate = true })
    assert(visuals.TimerTracked(bar) ~= true and driver._shown == false,
        "F9: the shared timer driver kept running with nothing to animate")
    _G.MSUF_DB.auras3.customContainers = nil
    _G.C_Timer.NewTimer = nil
end

-- C3.1 (review 2026-10-01). A frame-effect edit reaches an aura that is already shown ---
-- The menu edits the stored effect (the container's `frame` table) in place and
-- applies the unit scope. The draw stamp was that stored table, so the shown
-- effect kept its old colour and kind until the aura went away; it is now the
-- compiled lane config, which every apply rebuilds.
do
    local DOT = 670101
    local timers, cancels = 0, 0
    _G.C_Timer.NewTimer = function()
        timers = timers + 1
        return { Cancel = function() cancels = cancels + 1 end }
    end
    LoadProfile(Profile({ target = {
        layout = {}, filters = {}, layoutShared = { showBuffs = false, showDebuffs = false },
    } }))
    local effect = { type = "border", color = { 1, 0, 0, 1 }, priority = 5, thickness = 2, layer = 0 }
    _G.MSUF_DB.auras3.customContainers = { perUnit = { target = { items = {
        [4] = { enabled = true, targetDots = true, auraType = "DEBUFF", spellIDs = tostring(DOT),
            customSpellIDs = { [DOT] = true }, filters = { onlyMine = true },
            placed = { size = 20, max = 4, perRow = 4 }, frame = effect },
    } } } }
    A3.BumpRuntimeConfig()
    local dot = Aura(false, { spellId = DOT, mine = true, sourceUnit = "player", isFromPlayerOrPlayerPet = true,
        duration = 30, expirationTime = 80 })
    world.target = { dot }
    local target = NewFrame("target", {})
    local dots = assert(Lane(target, "custom4"), "C3.1: precondition: the Dots on target container is missing")
    local button = dots[dots.visibleByID[dot.auraInstanceID]]
    local root = button and button._msufA3ClassicFrameEffectRoot
    local edge = root and root._edges and root._edges[1]
    assert(root and root._shown == true and edge and edge._vr == 1 and edge._vg == 0,
        "C3.1: precondition: the red Border frame effect did not draw")
    -- Colour edit while the aura is shown.
    effect.color = { 0, 1, 0, 1 }
    A3.RefreshUnit("target")
    assert(edge._vr == 0 and edge._vg == 1,
        "C3.1: a frame-effect colour edit did not reach the shown aura (it kept the old colour)")
    -- Kind edit: Border becomes Pulse.
    local plays = pulses.play
    effect.type = "pulse"
    A3.RefreshUnit("target")
    assert(pulses.play == plays + 1, "C3.1: a frame-effect kind edit did not reach the shown aura")
    -- An unchanged refresh still keeps the drawn effect and never restarts the Pulse.
    Update(target, { updatedAuraInstanceIDs = { dot.auraInstanceID } })
    assert(pulses.play == plays + 1, "C3.1: an unchanged refresh restarted the Pulse frame effect")
    -- Expiring timing: a threshold edit replaces the pending timer.
    effect.timing, effect.expireThreshold = "expiring", 5
    A3.RefreshUnit("target")
    assert(timers == 1, "C3.1: precondition: an Expiring effect scheduled " .. timers .. " timers")
    effect.expireThreshold = 10
    A3.RefreshUnit("target")
    assert(timers == 2 and cancels >= 1,
        "C3.1: a threshold edit kept the pending Expiring timer of the old setting")
    _G.MSUF_DB.auras3.customContainers = nil
    _G.C_Timer.NewTimer = nil
end

-- C3.4 (review 2026-10-01). Custom containers honour their filter switches -------------
-- The container Filters tool offers the full Retail switch set on Classic, and
-- Retail ANDs every enabled switch into the container's filter. The Classic
-- compiler read Only mine and Hide permanent alone and fixed Maximum duration
-- at 0, so every other switch and the slider did nothing.
do
    LoadProfile(Profile({ focus = { layout = {}, filters = {}, layoutShared = { showBuffs = false, showDebuffs = false } } }))
    local raidBuff = Aura(true, { spellId = 671001, tokens = { RAID = true } })
    local plainBuff = Aura(true, { spellId = 671002, tokens = {} })
    local longBuff = Aura(true, { spellId = 671003, tokens = { RAID = true }, duration = 600, expirationTime = 650 })
    local permanentBuff = Aura(true, { spellId = 671004, tokens = { RAID = true }, duration = 0, expirationTime = 0 })
    local ccDebuff = Aura(false, { spellId = 671005, tokens = { CROWD_CONTROL = true } })
    local otherDebuff = Aura(false, { spellId = 671006, tokens = {} })
    world.focus = { raidBuff, plainBuff, longBuff, permanentBuff, ccDebuff, otherDebuff }
    local buffs = { enabled = true, raid = true }
    local items = {
        [1] = { enabled = true, auraType = "BUFF", spellIDs = "671001 671002 671003 671004",
            filters = buffs, placed = { size = 20, max = 8, perRow = 8 } },
        [2] = { enabled = true, auraType = "DEBUFF", spellIDs = "671005 671006",
            filters = { enabled = true, crowdControl = true }, placed = { size = 20, max = 8, perRow = 8 } },
    }
    _G.MSUF_DB.auras3.customContainers = { perUnit = { focus = { items = items } } }
    A3.BumpRuntimeConfig()
    local focus = NewFrame("focus", {})
    assert(VisibleIDs(Lane(focus, "custom1")) == IDs(raidBuff, longBuff, permanentBuff),
        "C3.4: the Raid switch of a custom container did not filter: " .. VisibleIDs(Lane(focus, "custom1")))
    assert(VisibleIDs(Lane(focus, "custom2")) == IDs(ccDebuff),
        "C3.4: the Crowd control switch of a custom container did not filter: " .. VisibleIDs(Lane(focus, "custom2")))
    -- Maximum duration hides longer auras and, as Blizzard's container filter
    -- does, permanent ones.
    buffs.maxDuration = 60
    A3.RefreshUnit("focus")
    assert(VisibleIDs(Lane(focus, "custom1")) == IDs(raidBuff),
        "C3.4: Maximum duration did not hide longer and permanent auras: " .. VisibleIDs(Lane(focus, "custom1")))
    -- Enable filters off: the switches stop, Maximum duration stays.
    buffs.enabled = false
    A3.RefreshUnit("focus")
    assert(VisibleIDs(Lane(focus, "custom1")) == IDs(raidBuff, plainBuff),
        "C3.4: turning the container filters off left the switches on or dropped Maximum duration: "
        .. VisibleIDs(Lane(focus, "custom1")))
    _G.MSUF_DB.auras3.customContainers = nil
end

-- C3.5 (review 2026-10-01). Arrival order and lane strata ignore unrelated settings -----
-- Arrival order put the player's auras first as soon as anything needed
-- ownership answers (here the own-buff highlight, an appearance toggle). A
-- container's stored legacy strata lifted it out of the frame's strata, which
-- Retail's native hosts never do: every lane takes its parent's strata.
do
    LoadProfile(Profile({ target = {
        layout = {}, filters = {}, layoutShared = { showBuffs = true, showDebuffs = false, buffSortMethod = "INSTANCE_ID" },
    } }))
    local older = Aura(true, { sourceUnit = "party2" })
    local mine = Aura(true, { sourceUnit = "player", isFromPlayerOrPlayerPet = true, mine = true })
    world.target = { older, mine }
    A3.BumpRuntimeConfig()
    local target = NewFrame("target", {})
    assert(VisibleIDs(Lane(target, "buff")) == IDs(older, mine), "C3.5: precondition: arrival order is not oldest first")
    _G.MSUF_DB.auras3.shared.highlightOwnBuffs = true
    A3.RefreshUnit("target")
    assert(Lane(target, "buff").config.ownHighlight == true, "C3.5: precondition: the own-buff highlight did not compile")
    assert(VisibleIDs(Lane(target, "buff")) == IDs(older, mine),
        "C3.5: the own-buff highlight reordered an Arrival order lane: " .. VisibleIDs(Lane(target, "buff")))
    _G.MSUF_DB.auras3.shared.highlightOwnBuffs = nil

    -- Strata: children inherit the parent's strata until one is set on them.
    local savedSet, savedGet = Widget.SetFrameStrata, Widget.GetFrameStrata
    function Widget:SetFrameStrata(strata) self._strata = strata end
    function Widget:GetFrameStrata()
        return self._strata or (self._parent and self._parent:GetFrameStrata()) or "MEDIUM"
    end
    local DOT = 670201
    _G.MSUF_DB.auras3.customContainers = { perUnit = { target = { items = {
        [1] = { enabled = true, auraType = "BUFF", spellIDs = tostring(DOT), strata = "HIGH",
            filters = { enabled = true }, placed = { size = 20, max = 4, perRow = 4 } },
    } } } }
    world.target = { Aura(true, { spellId = DOT }) }
    local strataFrame = NewFrame("target", {})
    strataFrame:SetFrameStrata("LOW")
    A3.RefreshUnit("target")
    local container = assert(Lane(strataFrame, "custom1"), "C3.5: precondition: the custom container is missing")
    assert(container.frame:GetFrameStrata() == "LOW" and Lane(strataFrame, "buff").frame:GetFrameStrata() == "LOW",
        "C3.5: an aura lane left its frame's strata (custom container: "
        .. tostring(container.frame:GetFrameStrata()) .. ")")
    Widget.SetFrameStrata, Widget.GetFrameStrata = savedSet, savedGet
    _G.MSUF_DB.auras3.customContainers = nil
end

-- C3.5 follow-up. A dispel symbol strata set back to AUTO returns to the frame's --------
-- An explicit "Symbol strata" stays on the symbol host until the host is written
-- again, so going back to AUTO has to restore the frame's strata; it used to keep
-- the last explicit one. Both the live and the menu preview host share the path.
do
    local savedSet, savedGet = Widget.SetFrameStrata, Widget.GetFrameStrata
    function Widget:SetFrameStrata(strata) self._strata = strata end
    function Widget:GetFrameStrata()
        return self._strata or (self._parent and self._parent:GetFrameStrata()) or "MEDIUM"
    end
    -- The menu preview host is draggable.
    local savedMovable, savedDrag = Widget.SetMovable, Widget.RegisterForDrag
    function Widget:SetMovable(movable) self._movable = movable end
    function Widget:RegisterForDrag(button) self._dragButton = button end
    local V = assert(A3.ClassicVisuals, "C3.5: precondition: the Classic aura visuals did not load")
    local symbol = { enabled = true, mode = "ALL", style = "BLIZZARD", size = 14, spacing = 2, growth = "RIGHT",
        anchor = "TOPRIGHT", x = 0, y = 0, alpha = 1, layer = 8, strata = "HIGH" }
    local visual = { symbol = symbol }
    for _, preview in ipairs({ false, true }) do
        local label = preview and "preview" or "live"
        local frame = setmetatable({ _shown = true }, Widget)
        frame:SetFrameStrata("LOW")
        symbol.strata = "HIGH"
        assert(V.UpdateDispelSymbols(frame, visual, { Magic = true }, preview) == true,
            "C3.5: precondition: the " .. label .. " dispel symbol did not render")
        local host = assert(frame[preview and "_msufA3ClassicDispelSymbolPreviewHost" or "_msufA3ClassicDispelSymbolHost"],
            "C3.5: precondition: no " .. label .. " dispel symbol host")
        assert(host:GetFrameStrata() == "HIGH", "C3.5: precondition: an explicit symbol strata was not applied")
        symbol.strata = "AUTO"
        V.UpdateDispelSymbols(frame, visual, { Magic = true }, preview)
        assert(host:GetFrameStrata() == "LOW",
            "C3.5: Symbol strata back on AUTO kept the " .. label .. " symbol on " .. tostring(host:GetFrameStrata()))
        -- A frame on another strata: AUTO follows it on the next render.
        frame:SetFrameStrata("MEDIUM")
        V.UpdateDispelSymbols(frame, visual, { Magic = true, Curse = true }, preview)
        assert(host:GetFrameStrata() == "MEDIUM",
            "C3.5: an AUTO " .. label .. " symbol did not take its frame's strata")
        -- W3.6 (re-review 2026-10-02): the signature keyed on "AUTO", so the same
        -- symbols on a frame that changed strata kept the old one.
        frame:SetFrameStrata("DIALOG")
        V.UpdateDispelSymbols(frame, visual, { Magic = true, Curse = true }, preview)
        assert(host:GetFrameStrata() == "DIALOG",
            "W3.6: an AUTO " .. label .. " symbol kept " .. tostring(host:GetFrameStrata())
            .. " after its frame moved to DIALOG")
    end
    Widget.SetFrameStrata, Widget.GetFrameStrata = savedSet, savedGet
    Widget.SetMovable, Widget.RegisterForDrag = savedMovable, savedDrag
end

-- F10. The icon-style border draws like Retail's ApplyIconStyleBorder ------------------
-- Real border-style catalog; textures remember their draw layer and anchors.
do
    assert(loadfile(ADDON .. "Runtime/MSUF_BorderStyles.lua"))("MidnightSimpleUnitFrames", namespace)
    assert(namespace.BorderStyles, "F10: precondition: the border-style catalog did not load")
    local function StyleButton()
        local button = setmetatable({ _shown = true }, Widget)
        function button:CreateTexture(_, layer, _, sublevel)
            local texture = setmetatable({ _shown = true, _parent = self, _layer = layer, _sublevel = sublevel, _at = {} }, Widget)
            function texture:SetDrawLayer(drawLayer, drawSublevel) self._layer, self._sublevel = drawLayer, drawSublevel end
            function texture:ClearAllPoints() self._at = {} end
            function texture:SetPoint(point, _, _, x, y) self._at[point] = { x or 0, y or 0 } end
            function texture:SetSize(width, height) self._width, self._height = width, height end
            return texture
        end
        return button
    end
    local function Style(key, thickness)
        return A3.ClassicVisuals.SharedIconStyle({ styleBorderEnabled = true, styleBorderStyle = key,
            styleBorderThickness = thickness }, "target", "buff")
    end
    local function Left(texture) return texture._at.TOPLEFT and texture._at.TOPLEFT[1] end

    -- Shaped icons draw one outward ring per pixel of thickness; thinning hides the rest.
    local button = StyleButton()
    A3.ApplyIconStylePreview(button, Style("SOLID", 3), 24, "CIRCLE")
    local rings = button._msufA3ShapedStyleBorders
    assert(rings and #rings == 3 and rings[3]._shown == true and Left(rings[3]) == -3 and rings[1]._layer == "BORDER",
        "F10: a 3 px border on a shaped icon did not draw three outward rings")
    A3.ApplyIconStylePreview(button, Style("SOLID", 1), 24, "CIRCLE")
    assert(rings[1]._shown == true and rings[2]._shown == false and rings[3]._shown == false,
        "F10: thinning a shaped icon's border left its outer rings shown")
    -- An inner style (built-in Shadow) shades a shaped icon from inside, above the artwork ...
    A3.ApplyIconStylePreview(button, Style("SHADOW", 2), 24, "CIRCLE")
    assert(rings[1]._layer == "ARTWORK" and rings[1]._sublevel == 7 and Left(rings[1]) == 0 and Left(rings[2]) == 1,
        "F10: an inner border style on a shaped icon did not draw inside the icon")
    -- ... except on a shape whose ring only works as an outline.
    local star = StyleButton()
    A3.ApplyIconStylePreview(star, Style("SHADOW", 2), 24, "STAR")
    local starRing = star._msufA3ShapedStyleBorders and star._msufA3ShapedStyleBorders[1]
    assert(starRing and starRing._layer == "BORDER" and Left(starRing) == -1,
        "F10: the outline-only Star shape drew an inner border ring")

    -- Square icons: the inner band is clamped to 30 % of the icon and inset by half its width.
    local square = StyleButton()
    local shadow = Style("SHADOW", 8)
    assert(shadow.borderPlacement == "inner" and shadow.borderEdge == 16,
        "F10: precondition: Shadow at thickness 8 is not a 16 px inner style")
    A3.ApplyIconStylePreview(square, shadow, 24, "RECTANGLE")
    local pieces = square._msufA3StyleBorderPieces
    assert(pieces and pieces[1]._layer == "ARTWORK" and pieces[1]._sublevel == 7,
        "F10: precondition: the inner style did not draw above the icon")
    assert(pieces[1]._width == 7 and Left(pieces[1]) == 0,
        "F10: an inner style on a 24 px icon kept a " .. tostring(pieces[1]._width)
            .. " px band hanging " .. tostring(Left(pieces[1])) .. " px past the edge")
    -- Switching to an outer style rebuilds the pieces behind the icon.
    A3.ApplyIconStylePreview(square, Style("GLOW", 2), 24, "RECTANGLE")
    local rebuilt = square._msufA3StyleBorderPieces
    assert(rebuilt ~= pieces and rebuilt[1]._layer == "BORDER" and rebuilt[1]._sublevel == -1
        and pieces[1]._shown == false and rebuilt[1]._width == 6 and Left(rebuilt[1]) == -3,
        "F10: switching an inner border style to an outer one kept the inner draw layer")
    namespace.BorderStyles, _G.MSUF_BorderStyles = nil, nil
end

-- W3.1 (re-review 2026-10-02). Classic lanes accept all nine menu anchors ------------
-- The lane Anchor and cooldown-text Anchor dropdowns offer nine points
-- (AURA_ANCHORS, Menu_Schema). Classic kept only the four corners and CENTER,
-- so TOP/LEFT/RIGHT/BOTTOM fell back to the lane default while the Edit Mode
-- preview drew the choice.
do
    for _, anchor in ipairs({ "TOP", "LEFT", "RIGHT", "BOTTOM", "TOPLEFT", "CENTER", "BOTTOMRIGHT" }) do
        LoadProfile(Profile({ target = {
            layout = { buffAnchor = anchor, debuffAnchor = anchor },
            layoutShared = { showBuffs = true, showDebuffs = true, maxBuffs = 4, maxDebuffs = 4,
                buffCooldownTextAnchor = anchor },
            filters = {},
        } }))
        A3.BumpRuntimeConfig()
        world.target = { Aura(true), Aura(false) }
        local target = NewFrame("target", {})
        assert(Lane(target, "buff").config.anchor == anchor and Lane(target, "debuff").config.anchor == anchor,
            "W3.1: a target lane dropped the menu anchor " .. anchor .. " for "
            .. tostring(Lane(target, "buff").config.anchor))
        assert(Lane(target, "buff").config.cooldownAnchor == anchor,
            "W3.1: the cooldown text dropped the menu anchor " .. anchor)
        local party = NewFrame("party3", { scope = "group", auras = {
            enabled = true, showBuffs = true, maxBuffs = 4, buffAnchor = anchor, buffCooldownAnchor = anchor,
        } }, GroupFields("party"))
        assert(Lane(party, "buff").config.anchor == anchor and Lane(party, "buff").config.cooldownAnchor == anchor,
            "W3.1: a group lane dropped the menu anchor " .. anchor)
    end
    -- A value no menu offers still falls back to the lane default.
    LoadProfile(Profile({ target = {
        layout = { buffAnchor = "MIDDLE" }, layoutShared = { showBuffs = true, maxBuffs = 4 }, filters = {},
    } }))
    A3.BumpRuntimeConfig()
    local target = NewFrame("target", {})
    assert(Lane(target, "buff").config.anchor == "BOTTOMRIGHT", "W3.1: an unknown anchor did not fall back")
end

-- W3.2 (re-review 2026-10-02). "Raid in combat" lanes follow the combat edge ---------
-- RAID_IN_COMBAT membership flips with the player's combat state. The edge
-- handler re-rendered each lane's cached active set without re-running the
-- filters or bumping the unit's token serial, so the container kept showing
-- the other side's auras until an unrelated full update.
do
    LoadProfile(Profile({ focus = { layout = {}, filters = {}, layoutShared = { showBuffs = false, showDebuffs = false } } }))
    local hot = Aura(true, { spellId = 672001, tokens = { RAID_IN_COMBAT = false } })
    local plain = Aura(true, { spellId = 672002, tokens = {} })
    world.focus = { hot, plain }
    _G.MSUF_DB.auras3.customContainers = { perUnit = { focus = { items = {
        [1] = { enabled = true, auraType = "BUFF", spellIDs = "672001 672002",
            filters = { enabled = true, raidInCombat = true }, placed = { size = 20, max = 8, perRow = 8 } },
    } } } }
    A3.BumpRuntimeConfig()
    local focus = NewFrame("focus", {})
    local events = registered.GetUnitlessEvents(focus)
    local hearsEdge = false
    for i = 1, #events do if events[i] == "PLAYER_REGEN_DISABLED" then hearsEdge = true end end
    assert(hearsEdge, "W3.2: precondition: a Raid in combat container does not hear the combat edge")
    assert(VisibleIDs(Lane(focus, "custom1")) == "",
        "W3.2: precondition: the out-of-combat container shows " .. VisibleIDs(Lane(focus, "custom1")))
    hot.tokens.RAID_IN_COMBAT = true
    registered.Update(focus, "PLAYER_REGEN_DISABLED")
    assert(VisibleIDs(Lane(focus, "custom1")) == IDs(hot),
        "W3.2: entering combat kept the out-of-combat Raid in combat set: " .. VisibleIDs(Lane(focus, "custom1")))
    hot.tokens.RAID_IN_COMBAT = false
    registered.Update(focus, "PLAYER_REGEN_ENABLED")
    assert(VisibleIDs(Lane(focus, "custom1")) == "",
        "W3.2: leaving combat kept the in-combat Raid in combat set: " .. VisibleIDs(Lane(focus, "custom1")))
    _G.MSUF_DB.auras3.customContainers = nil
end

-- W3.3 (re-review 2026-10-02). Lane Layer follows the menu's 0..30 slider ---------------
-- The lane Layer control writes 0..30 (Model.ReadLaneLayer, the Layer
-- overview); Classic clamped unit and group lanes to 1..15.
do
    for _, layer in ipairs({ 0, 25, 30 }) do
        LoadProfile(Profile({ target = {
            layout = { buffLayer = layer }, layoutShared = { showBuffs = true, maxBuffs = 4 }, filters = {},
        } }))
        A3.BumpRuntimeConfig()
        world.target = { Aura(true) }
        local target = NewFrame("target", {})
        local lane = Lane(target, "buff")
        assert(lane.config.layer == layer, "W3.3: a target lane clamped Layer " .. layer .. " to " .. tostring(lane.config.layer))
        assert(lane.frame._frameLevel == lane.root:GetFrameLevel() + layer,
            "W3.3: the target lane frame is not on Layer " .. layer)
        local party = NewFrame("party3", { scope = "group", auras = {
            enabled = true, showBuffs = true, maxBuffs = 4, buffLayer = layer,
        } }, GroupFields("party"))
        assert(Lane(party, "buff").config.layer == layer,
            "W3.3: a group lane clamped Layer " .. layer .. " to " .. tostring(Lane(party, "buff").config.layer))
    end
end

-- W3.4 (re-review 2026-10-02). A sorted lane keeps no arrival list ---------------------
-- AddAuraToLane appended every new aura id to lane.ordered, which only the
-- natural-order render reads and compacts. On a sorted lane (the default) the
-- list grew with every delta-added aura until the next full scan.
do
    LoadProfile(Profile({ target = {
        layout = {}, layoutShared = { showBuffs = true, maxBuffs = 4 }, filters = {},
    } }))
    A3.BumpRuntimeConfig()
    world.target = { Aura(true) }
    local target = NewFrame("target", {})
    local lane = Lane(target, "buff")
    assert(lane.config.naturalOrder ~= true, "W3.4: precondition: the default target buff lane is not sorted")
    local list = UnitList("target")
    for _ = 1, 200 do
        local aura = Aura(true)
        list[#list + 1] = aura
        Update(target, { addedAuras = { aura } })
        list[#list] = nil
        Update(target, { removedAuraInstanceIDs = { aura.auraInstanceID } })
    end
    assert(Visible(target, "buff") == 1, "W3.4: precondition: the delta churn changed the visible buffs")
    assert((lane.orderedCount or 0) <= 1 and #lane.ordered <= 1,
        "W3.4: 200 delta-added auras grew a sorted lane's arrival list to " .. tostring(lane.orderedCount))
    -- Arrival order still records and compacts its own list.
    LoadProfile(Profile({ target = {
        layout = {}, layoutShared = { showBuffs = true, maxBuffs = 4, buffSortMethod = "INSTANCE_ID" }, filters = {},
    } }))
    A3.BumpRuntimeConfig()
    local first, second, third = Aura(true), Aura(true), Aura(true)
    world.target = { first, second }
    target = NewFrame("target", {})
    lane = Lane(target, "buff")
    assert(lane.config.naturalOrder == true, "W3.4: precondition: Arrival order is not a natural-order lane")
    world.target[3] = third
    Update(target, { addedAuras = { third } })
    assert(VisibleIDs(lane) == IDs(first, second, third),
        "W3.4: an arrival-order lane lost its order: " .. VisibleIDs(lane))
end

-- W3.5 (re-review 2026-10-02). Every Classic sort mode is a strict weak order ----------
-- table.sort needs one. The default ("Player first") mode compared
-- canApplyAura as true, false or unknown, and unknown (a synthetic weapon
-- enchant, a secret flag) tied with both other classes, so two auras tied
-- with a third while ranking against each other.
do
    local Compile = assert(A3._ClassicCompile, "W3.5: the Classic compile module is missing")
    local auras, mine = {}, {}
    local canApply, durations, expirations, names = { true, false, nil }, { 30, 10 }, { 70, 0, 50 }, { "B", "A" }
    for i = 1, 12 do
        local aura = {
            auraInstanceID = 9000 + i,
            canApplyAura = canApply[(i % 3) + 1],
            duration = durations[(i % 2) + 1],
            expirationTime = expirations[(i % 3) + 1],
            name = names[(i % 2) + 1],
        }
        if i % 4 == 0 then aura.canApplyAura = nil end
        auras[i] = aura
        mine[aura.auraInstanceID] = i % 5 == 0
    end
    Compile.SetSortOwnership(mine)
    for mode = 0, 6 do
        local less = Compile.SortComparator(mode)
        local function Equivalent(a, b) return not less(a, b) and not less(b, a) end
        for i = 1, #auras do
            local a = auras[i]
            assert(not less(a, a), "W3.5: sort mode " .. mode .. " ranks an aura before itself")
            for j = 1, #auras do
                local b = auras[j]
                assert(not (less(a, b) and less(b, a)), "W3.5: sort mode " .. mode .. " is not asymmetric")
                for k = 1, #auras do
                    local c = auras[k]
                    if less(a, b) and less(b, c) then
                        assert(less(a, c), "W3.5: sort mode " .. mode .. " is not transitive")
                    end
                    if Equivalent(a, b) and Equivalent(b, c) then
                        assert(Equivalent(a, c), "W3.5: sort mode " .. mode
                            .. " ties are not transitive (auras " .. a.auraInstanceID .. ", "
                            .. b.auraInstanceID .. ", " .. c.auraInstanceID .. ")")
                    end
                end
            end
        end
    end
    Compile.SetSortOwnership(nil)
end

-- F6. Edit Mode and menu group test frames never run the live backend -------------------
do
    world.player = {
        Aura(true, { sourceUnit = "player", mine = true }), Aura(true, { sourceUnit = "player", mine = true }),
    }
    local spec = { scope = "group", auras = { enabled = true, showBuffs = true, maxBuffs = 4, showDebuffs = true, maxDebuffs = 4 } }
    local fields = GroupFields("raid")
    fields._msufGFIsPreviewFrame = true
    local preview, enabled = NewFrame("player", spec, fields, true)
    assert(registered.IsEnabled(preview) == false, "F6: a group test frame reports the live aura element enabled")
    assert(enabled == false, "F6: a group test frame enabled the live aura backend")
    registered.Apply(preview)
    assert(Visible(preview, "buff") == 0 and preview._msufA3GroupRuntime == nil,
        "F6: a group test frame rendered the player's live auras")
    -- The same spec on a live group frame still renders, so the guard is the flag.
    local live = NewFrame("player", spec, GroupFields("raid"))
    assert(Visible(live, "buff") == 2, "F6: precondition: a live group frame on the player shows no auras")
end

-- F18. Leaving Edit Mode keeps the Menu2 Arena page's aura preview ----------------------
-- Loaded last: the aura Edit Mode wraps A3.RefreshAll and A3.RefreshUnit.
do
    local listener
    local queued = {}
    _G.MSUF_RegisterAnyEditModeListener = function(fn) listener = fn end
    _G.C_Timer.After = function(_, fn) queued[#queued + 1] = fn end
    assert(loadfile(ADDON .. "Auras3/MSUF_Auras3_EditMode.lua"))("MidnightSimpleUnitFrames", namespace)
    local EM = assert(A3.EditMode, "F18: the aura Edit Mode did not load")
    assert(type(listener) == "function", "F18: precondition: the aura Edit Mode registered no listener")
    local refreshed = 0
    EM.RefreshAll = function() refreshed = refreshed + 1; return true end
    EM.HideAll = function() return true end
    for _, flag in ipairs({ "MSUF2_BossPageAuraPreviewActive", "MSUF2_ArenaPageAuraPreviewActive" }) do
        _G.MSUF2_BossPageAuraPreviewActive, _G.MSUF2_ArenaPageAuraPreviewActive = nil, nil
        _G[flag] = true
        refreshed = 0
        listener(false)
        for i = 1, #queued do queued[i]() end
        for i = #queued, 1, -1 do queued[i] = nil end
        assert(refreshed == 1, "F18: leaving Edit Mode removed the page aura preview kept by " .. flag)
    end
    -- F1: the global font follower refreshes a shown Edit Mode preview once.
    _G.MSUF2_BossPageAuraPreviewActive = true
    refreshed = 0
    A3.ApplyFontsFromGlobal()
    for i = 1, #queued do queued[i]() end
    for i = #queued, 1, -1 do queued[i] = nil end
    assert(refreshed == 1, "F1: a global font refresh rebuilt the Edit Mode aura preview " .. refreshed .. " times")
    _G.MSUF2_BossPageAuraPreviewActive, _G.MSUF2_ArenaPageAuraPreviewActive = nil, nil
    _G.C_Timer.After = nil
end

print("classic aura review fixes smoke passed")
