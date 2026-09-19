-- Classic aura backend: Bars > Show on follows UNIT_FACTION, as Retail's identity
-- owners do (Auras3/Runtime/MSUF_Auras3_Runtime_IdentityEvents.lua). Runs against
-- the real backend files in the flavor's TOC order, with the flavor's real client
-- model (Game/Shared/Initialize.lua):
--   * a Friendly or Enemy dispel border subscribes to UNIT_FACTION for its own
--     unit, on a group frame, a lane-cached unit frame and a direct unit frame;
--     Both never subscribes, nor does a client without the event
--   * a unit that stops (or starts) being assistable hides (or shows) the border
--     on that UNIT_FACTION alone, with no UNIT_AURA; the cached-lane paths scan
--     nothing and a steady event allocates nothing
--   * UNIT_FACTION for another unit changes nothing and asks nothing
--   * UNIT_FACTION for the player re-checks every shown group frame with such a
--     border through one shared registration, as Retail's identity driver does
--     for its group assist-gated owners; it is armed only while one needs it
-- Arguments: repository root, flavor (Vanilla, TBC or Mists), then optionally the
-- backend, features, compile and visuals paths (mutation runs).
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))
local flavor = assert(arg[2], "flavor argument missing")
local ADDON = root .. "/MidnightSimpleUnitFrames/"
local overrides = {
    ["Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua"] = arg[3],
    ["Game/Classic/Auras/MSUF_Auras3_Features.lua"] = arg[4],
    ["Game/Classic/Auras/MSUF_Auras3_Compile.lua"] = arg[5],
    ["Game/Classic/Auras/MSUF_Auras3_Visuals.lua"] = arg[6],
}

-- Client placement: the project globals and the X-MSUF-Client tag the flavor's
-- TOC carries. C_EventUtils answers every event valid unless listed below.
local PROJECT_IDS = { Vanilla = 2, TBC = 5, Mists = 19 }
assert(PROJECT_IDS[flavor], "unknown Classic flavor: " .. tostring(flavor))
_G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_CLASSIC = 1, 2
_G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, _G.WOW_PROJECT_MISTS_CLASSIC = 5, 19
_G.WOW_PROJECT_ID = PROJECT_IDS[flavor]
_G.C_AddOns = { GetAddOnMetadata = function(_, field)
    if field == "X-MSUF-Client" then return flavor end
    return nil
end }
local invalidEvents = {}
_G.C_EventUtils = { IsEventValid = function(event) return invalidEvents[event] ~= true end }

local registered
local namespace = {
    MSUF_Auras3 = {},
    UF = { RegisterElement = function(_, element) registered = element end },
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
function Widget:GetNumRegions() return 0 end
function Widget:GetRegions() return nil end
function Widget:GetObjectType() return self._objectType or "Frame" end
function Widget:CreateTexture() return setmetatable({ _shown = true, _parent = self }, Widget) end
Widget.CreateMaskTexture = Widget.CreateTexture
Widget.CreateFontString = Widget.CreateTexture
for _, name in ipairs({
    "RegisterEvent", "UnregisterEvent", "ClearAllPoints", "SetAllPoints", "SetAlpha", "EnableMouse", "SetPoint",
    "SetSize", "SetWidth", "SetHeight", "SetDrawSwipe", "SetHideCountdownNumbers", "SetSwipeColor", "SetDrawEdge",
    "SetTexCoord", "SetFont", "SetTextColor", "SetShadowOffset", "SetDesaturated", "SetJustifyH", "SetJustifyV",
    "SetBlendMode", "SetMinMaxValues", "SetValue", "SetStatusBarTexture", "SetStatusBarColor", "SetColorTexture",
    "SetReverse", "SetMouseClickEnabled", "SetMouseMotionEnabled", "SetCountdownMillisecondsThreshold",
    "SetSwipeTexture", "SetFrameStrata", "SetOwner", "SetCooldown", "Clear", "SetAtlas", "AddMaskTexture",
    "RemoveMaskTexture",
}) do Widget[name] = function() end end
function Widget:RegisterUnitEvent(event, unit) self._unitEvents = self._unitEvents or {}; self._unitEvents[event] = unit end
function Widget:UnregisterEvent(event) if self._unitEvents then self._unitEvents[event] = nil end end
local created = {}
_G.CreateFrame = function(frameType, _, parent)
    local frame = setmetatable({ _shown = true, _parent = parent, _objectType = frameType }, Widget)
    created[#created + 1] = frame
    return frame
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
local world, assistable, guids = {}, {}, {}
local api = { slots = 0, index = 0, assist = 0 }
-- UnitCanAssist questions per unit; the keys exist up front so counting allocates nothing.
local askedAbout = { party1 = 0, party2 = 0, party4 = 0, target = 0, player = 0, nameplate3 = 0 }
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
    -- HARMFUL|RAID (Classic Era's dispellable filter and the Any dispel type
    -- trigger) and HARMFUL|RAID_PLAYER_DISPELLABLE both keep typed debuffs only.
    if filter:find("|RAID", 1, true) and aura.dispelName == nil then return false end
    return true
end
_G.UnitExists = function() return true end
_G.UnitIsUnit = function(a, b) return a == b end
_G.UnitInRange = function() return true, true end
_G.UnitCanAssist = function(source, unit)
    api.assist = api.assist + 1
    -- Message built on failure only: the allocation checks run through here.
    if source ~= "player" then error("Show on asked UnitCanAssist about " .. tostring(source)) end
    if askedAbout[unit] then askedAbout[unit] = askedAbout[unit] + 1 end
    return assistable[unit] == true
end
_G.UnitGUID = function(unit) return guids[unit] end
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
    GetAuraDataBySlot = function(unit, slot) return Snapshot(UnitList(unit)[slot]) end,
    GetAuraDataByAuraInstanceID = function(unit, id)
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

local nextID = 8000
local function Magic()
    nextID = nextID + 1
    return {
        auraInstanceID = nextID, spellId = 900000 + nextID, name = "Magic" .. nextID, icon = 134400,
        applications = 1, duration = 30, expirationTime = 80, isHelpful = false, isHarmful = true,
        isFromPlayerOrPlayerPet = false, dispelName = "Magic",
    }
end

-- SavedVariables ------------------------------------------------------------------------
-- player shows no aura icons, so its border resolves straight from the unit
-- (the direct path). target shows a Hide permanent debuff lane, so its border
-- resolves from that lane's cache.
_G.MSUF_DB = {
    general = {},
    auras3 = {
        enabled = true, showPlayer = true, showTarget = true, showFocus = false, showBoss = false,
        shared = {},
        perUnit = {
            player = { layout = {}, layoutShared = { showBuffs = false, showDebuffs = false }, filters = {} },
            target = {
                layout = {}, layoutShared = { showBuffs = false, showDebuffs = true },
                filters = { debuffs = { hidePermanent = true } },
            },
        },
    },
}

-- Load the real chain in the flavor's TOC order -------------------------------------------
local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
local chain = {
    "Game/Shared/Initialize.lua",
    "Auras3/MSUF_Auras3_Core.lua", "Auras3/MSUF_Auras3_IconShape.lua",
    "Game/Classic/Auras/MSUF_Auras3_Visuals.lua", "Game/Classic/Auras/MSUF_Auras3_Features.lua",
    "Game/Classic/Auras/MSUF_Auras3_Preview.lua", "Game/Classic/Auras/MSUF_Auras3_Compile.lua",
    "Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua",
}
local overridePaths = {}
for relative, path in pairs(overrides) do overridePaths[ADDON .. relative] = path end
manifest.LoadSelected(root, flavor, namespace, chain, function(path)
    return loadfile(overridePaths[path] or path)
end)
local client = namespace.Client
assert(client and client.IsClassic == true and client.Flavor == flavor,
    "precondition: the client model did not place " .. flavor)
assert(client.SupportsEvent("UNIT_FACTION") == true, "precondition: " .. flavor .. " reports no UNIT_FACTION")
assert(registered, "Classic aura element did not register")
local A3 = namespace.MSUF_Auras3

-- The core's event topology, reduced to what this test needs: RebuildFrameEvents
-- asks the element for its unit events (GetEvents, else the static list) and
-- RegisterUnitEvent filters them to the frame's own unit.
local frames = {}
local function Subscribe(frame)
    local getter = registered.GetEvents
    frame._smokeUnitEvents = type(getter) == "function" and getter(frame, frame.MSUFSpec) or registered.events
end
local function Fire(event, unit)
    for i = 1, #frames do
        local frame = frames[i]
        local events = frame._smokeUnitEvents
        if frame.MSUFUnitKey == unit and events then
            for j = 1, #events do
                if events[j] == event then
                    registered.Update(frame, event, unit)
                    break
                end
            end
        end
    end
end
local function HasEvent(list, event)
    for i = 1, type(list) == "table" and #list or 0 do if list[i] == event then return true end end
    return false
end
local function Border(frame) return frame._msufA3DispelActive == true end
--- A menu change reaches a live frame as an Auras element apply, after which the
--- core re-derives the frame's event routes.
local function Reapply(frame)
    A3.BumpRuntimeConfig()
    registered.Apply(frame)
    Subscribe(frame)
end
local function NewFrame(unit, spec)
    local frame = setmetatable({
        _shown = true, MSUFUnitKey = unit, _msufActiveElements = { Auras = true }, MSUFSpec = spec,
    }, Widget)
    frame.hpBar = _G.CreateFrame("StatusBar", nil, frame)
    registered.Create(frame)
    assert(registered.Enable(frame) == true, unit .. " aura element did not enable")
    Subscribe(frame)
    frames[#frames + 1] = frame
    return frame
end

-- party1 and target resolve their borders from a lane cache (Hide permanent is
-- filter work); party4 (border only) and player resolve theirs from the unit.
local partySpec = {
    scope = "group", auras = { enabled = true, showDebuffs = true, maxDebuffs = 4, debuffHidePermanent = true },
    border = { dispel = true, dispelTrigger = "DISPEL_TYPE", dispelShowOn = "FRIENDLY" },
}
local party4Spec = {
    scope = "group", auras = { enabled = true },
    border = { dispel = true, dispelTrigger = "DISPEL_TYPE", dispelShowOn = "ENEMY" },
}
local targetSpec = { border = { dispel = true, dispelTrigger = "DISPEL_TYPE", dispelShowOn = "ENEMY" } }
local playerSpec = { border = { dispel = true, dispelTrigger = "DISPEL_TYPE", dispelShowOn = "FRIENDLY" } }
for _, unit in ipairs({ "party1", "party4", "target", "player" }) do UnitList(unit)[1] = Magic() end
guids.party1, guids.party4, guids.target, guids.player = "Player-A", "Player-D", "Creature-B", "Player-C"
assistable.party1, assistable.party4, assistable.target, assistable.player = true, false, false, true
local party = NewFrame("party1", partySpec)
local party4 = NewFrame("party4", party4Spec)
local target = NewFrame("target", targetSpec)
local player = NewFrame("player", playerSpec)

local function LaneCached(frame, cfg)
    local lane = frame._msufA3State.lanes.debuff
    return cfg.visualDirect ~= true and lane ~= nil and lane._msufA3VisualCacheReady == true
end
assert(LaneCached(party, party._msufA3State.config), "precondition: party1's border is not resolved from a cached lane")
assert(party4._msufA3State.config.visualDirect == true, "precondition: party4's border does not resolve from the unit")
assert(LaneCached(target, A3.ResolveUnitFrameConfig("target", targetSpec)),
    "precondition: the target border is not resolved from a cached lane")
assert(A3.ResolveUnitFrameConfig("player", playerSpec).visualDirect == true,
    "precondition: the player border does not resolve directly from the unit")
for _, frame in ipairs(frames) do
    assert(Border(frame), "precondition: " .. frame.MSUFUnitKey .. " does not show its border")
end

--- One frame through a full faction round trip. cached: the frame's border comes
--- from a lane it already holds, so the event must not scan the unit.
local function RoundTrip(label, frame, showOn, cached)
    local unit = frame.MSUFUnitKey
    local shownWhenAssistable = showOn == "FRIENDLY"
    assert(HasEvent(frame._smokeUnitEvents, "UNIT_AURA"), label .. ": the frame lost UNIT_AURA")
    assert(HasEvent(frame._smokeUnitEvents, "UNIT_FACTION"),
        label .. ": a " .. showOn .. " border does not follow UNIT_FACTION, so it stays stale until a debuff changes")
    assistable[unit] = shownWhenAssistable
    Fire("UNIT_FACTION", unit)
    assert(Border(frame), label .. ": precondition: the border is not shown")
    for _, flip in ipairs({ { not shownWhenAssistable, false }, { shownWhenAssistable, true } }) do
        assistable[unit] = flip[1]
        local scans = api.slots + api.index
        Fire("UNIT_FACTION", unit)
        assert(Border(frame) == flip[2], ("%s: UNIT_FACTION with UnitCanAssist %s left the border %s"):format(
            label, tostring(flip[1]), Border(frame) and "shown" or "hidden"))
        if cached then
            assert(api.slots + api.index == scans,
                label .. ": UNIT_FACTION scanned the unit " .. (api.slots + api.index - scans) .. " times")
        end
    end
end
RoundTrip("cached-lane group frame Friendly", party, "FRIENDLY", true)
RoundTrip("direct group frame Enemy", party4, "ENEMY", false)
RoundTrip("cached-lane unit frame Enemy", target, "ENEMY", true)
RoundTrip("direct unit frame Friendly", player, "FRIENDLY", false)

-- UNIT_FACTION for another unit ---------------------------------------------------------
-- party1 turns hostile, but the events name someone else: nothing may change and
-- UnitCanAssist is not asked. The last line reaches the handler with a foreign
-- payload, as a shared registration would.
assistable.party1 = false
local asked = api.assist
Fire("UNIT_FACTION", "party2")
Fire("UNIT_FACTION", "nameplate3")
registered.Update(party, "UNIT_FACTION", "party2")
assert(Border(party), "UNIT_FACTION for another unit re-evaluated party1's border")
assert(api.assist == asked, "UNIT_FACTION for another unit asked UnitCanAssist " .. (api.assist - asked) .. " times")
Fire("UNIT_FACTION", "party1")
assert(not Border(party), "precondition: party1's own UNIT_FACTION did not hide the border")

-- UNIT_FACTION for the player -----------------------------------------------------------
-- A duel or mind control flips the player's side of UnitCanAssist("player", partyN)
-- while no event names the member. The group frames' own registrations only hear
-- their own unit, so one shared registration for the player must re-check them.
local function PlayerFactionDrivers()
    local found = {}
    for i = 1, #created do
        local frame = created[i]
        if frame._unitEvents and frame._unitEvents.UNIT_FACTION == "player" then found[#found + 1] = frame end
    end
    return found
end
local drivers = PlayerFactionDrivers()
assert(#drivers == 1, ("a Friendly or Enemy group border needs one shared UNIT_FACTION registration for "
    .. "the player, so a player-side flip leaves party borders stale; found %d"):format(#drivers))
local playerDriver = drivers[1]
local function FirePlayerFaction()
    local onEvent = playerDriver._scripts and playerDriver._scripts.OnEvent
    assert(type(onEvent) == "function", "the player UNIT_FACTION registration has no handler")
    onEvent(playerDriver, "UNIT_FACTION", "player")
end
assistable.party1, assistable.party4 = true, false
Fire("UNIT_FACTION", "party1")
Fire("UNIT_FACTION", "party4")
assert(Border(party) and Border(party4), "precondition: the party borders are not shown")
for _, flip in ipairs({ { false, true, false }, { true, false, true } }) do
    assistable.party1, assistable.party4 = flip[1], flip[2]
    local slots, asked1, asked4 = api.slots, askedAbout.party1, askedAbout.party4
    Fire("UNIT_FACTION", "player")
    assert(Border(party) == not flip[3] and Border(party4) == not flip[3],
        "precondition: the frames' own registrations re-checked a party border on the player's event")
    FirePlayerFaction()
    assert(Border(party) == flip[3], ("the player's UNIT_FACTION left party1's Friendly border %s"):format(
        Border(party) and "shown" or "hidden"))
    assert(Border(party4) == flip[3], ("the player's UNIT_FACTION left party4's Enemy border %s"):format(
        Border(party4) and "shown" or "hidden"))
    assert(api.slots == slots, "the player's UNIT_FACTION rescanned a group frame")
    assert(askedAbout.party1 == asked1 + 1 and askedAbout.party4 == asked4 + 1,
        ("the player's UNIT_FACTION asked about party1 %d and party4 %d times, once each expected"):format(
            askedAbout.party1 - asked1, askedAbout.party4 - asked4))
end
-- A hidden group frame reconciles on its show edge instead of on the event.
party4._shown = false
local hiddenAsked = askedAbout.party4
FirePlayerFaction()
assert(askedAbout.party4 == hiddenAsked, "the player's UNIT_FACTION re-checked a hidden group frame")
party4._shown = true

-- No allocation per event: steady and flipping, lane-cached and direct -----------------
snapshots = false
for _, frame in ipairs({ party, player }) do
    local unit = frame.MSUFUnitKey
    assistable[unit] = true
    Fire("UNIT_FACTION", unit)
    local bytes = BytesPerCall(function() Fire("UNIT_FACTION", unit) end, 200)
    assert(bytes == 0, ("%s: a steady UNIT_FACTION allocated %.1f bytes per event"):format(unit, bytes))
    local flipTo = false
    bytes = BytesPerCall(function()
        assistable[unit] = flipTo
        flipTo = not flipTo
        Fire("UNIT_FACTION", unit)
    end, 200)
    assert(bytes == 0, ("%s: a flipping UNIT_FACTION allocated %.1f bytes per event"):format(unit, bytes))
    assistable[unit] = true
    Fire("UNIT_FACTION", unit)
    assert(Border(frame), "precondition: " .. unit .. "'s border did not return")
end
do
    local bytes = BytesPerCall(FirePlayerFaction, 200)
    assert(bytes == 0, ("the player's steady UNIT_FACTION allocated %.1f bytes per event"):format(bytes))
    local flipTo = false
    bytes = BytesPerCall(function()
        assistable.party1, assistable.party4 = flipTo, not flipTo
        flipTo = not flipTo
        FirePlayerFaction()
    end, 200)
    assert(bytes == 0, ("the player's flipping UNIT_FACTION allocated %.1f bytes per event"):format(bytes))
    assistable.party1, assistable.party4 = true, false
    FirePlayerFaction()
    assert(Border(party) and Border(party4), "precondition: the party borders did not return")
end
snapshots = true

-- Both ----------------------------------------------------------------------------------
-- Show on Both registers nothing, and a stale registration still does nothing:
-- no UnitCanAssist, no scan, on the lane-cached and on the direct frame.
partySpec.border.dispelShowOn, party4Spec.border.dispelShowOn = "BOTH", "BOTH"
for _, frame in ipairs({ party, party4 }) do
    local unit = frame.MSUFUnitKey
    Reapply(frame)
    assert(HasEvent(frame._smokeUnitEvents, "UNIT_AURA") and not HasEvent(frame._smokeUnitEvents, "UNIT_FACTION"),
        unit .. ": Show on Both still subscribes to UNIT_FACTION")
    assert(Border(frame), "precondition: " .. unit .. " shows no border under Show on Both")
    asked = api.assist
    local scans = api.slots + api.index
    for _, canAssist in ipairs({ false, true, false }) do
        assistable[unit] = canAssist
        registered.Update(frame, "UNIT_FACTION", unit)
        assert(Border(frame), unit .. ": Show on Both let UNIT_FACTION filter the border")
    end
    assert(api.assist == asked and api.slots + api.index == scans, ("%s: Show on Both did UNIT_FACTION work: "
        .. "%d UnitCanAssist calls, %d scans"):format(unit, api.assist - asked, api.slots + api.index - scans))
end
assistable.party1, assistable.party4 = true, false
-- No group frame filters by Show on any more: the player registration is dropped.
assert(playerDriver._unitEvents.UNIT_FACTION == nil,
    "the player's UNIT_FACTION stays registered with no Friendly or Enemy group border")
assert(#PlayerFactionDrivers() == 0, "a second player UNIT_FACTION registration exists")

-- A client without UNIT_FACTION ---------------------------------------------------------
-- A second client model whose event table lacks UNIT_FACTION; the backend reads
-- the live namespace's model, so swapping it in stands for such a client.
invalidEvents.UNIT_FACTION = true
local deniedNamespace = {}
assert(loadfile(ADDON .. "Game/Shared/Initialize.lua"))("MidnightSimpleUnitFrames", deniedNamespace)
_G.MSUF_NS, _G.MSUF = namespace, namespace
local deniedClient = deniedNamespace.Client
assert(deniedClient and deniedClient.SupportsEvent("UNIT_FACTION") == false,
    "precondition: the second client model still reports UNIT_FACTION")
partySpec.border.dispelShowOn = "FRIENDLY"
namespace.Client = deniedClient
Reapply(party)
assert(not HasEvent(party._smokeUnitEvents, "UNIT_FACTION"),
    "the aura element registers UNIT_FACTION on a client that does not have it")
assert(playerDriver._unitEvents.UNIT_FACTION == nil,
    "the player's UNIT_FACTION is registered on a client that does not have it")
namespace.Client = client
Reapply(party)
assert(HasEvent(party._smokeUnitEvents, "UNIT_FACTION"), "precondition: Friendly did not subscribe again")
assert(playerDriver._unitEvents.UNIT_FACTION == "player" and #PlayerFactionDrivers() == 1,
    "a Friendly group border did not re-arm the one player UNIT_FACTION registration")

-- Disabling the last such group frame drops the player registration too.
registered.Disable(party)
assert(playerDriver._unitEvents.UNIT_FACTION == nil,
    "the player's UNIT_FACTION stays registered after the last Friendly or Enemy group frame was disabled")

print("classic aura faction smoke passed: " .. flavor)
