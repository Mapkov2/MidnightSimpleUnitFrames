-- Classic aura backend: UNIT_AURA update-path contracts, run against the real
-- backend files with counting widget and C_UnitAuras stubs.
--   * a shaped per-aura dispel border keeps its dispel colour across repaints
--   * a lane update that raised forces the next event to rescan in full
--   * natural-order compaction keeps tracked auras that are filtered out
--   * only time-keyed sorts re-render a lane on a refresh, and only when a
--     sort input moved
--   * an unchanged refreshed aura writes no layout and allocates nothing
-- Arguments: repository root, then optionally the backend, features, core,
-- visuals and compile paths (the same order as classic_aura_render_smoke.lua).
local root = assert(arg[1], "repository root argument missing")
local ADDON = root .. "/MidnightSimpleUnitFrames/"
local overrides = {
    ["Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua"] = arg[2],
    ["Game/Classic/Auras/MSUF_Auras3_Features.lua"] = arg[3],
    ["Auras3/MSUF_Auras3_Core.lua"] = arg[4],
    ["Game/Classic/Auras/MSUF_Auras3_Visuals.lua"] = arg[5],
    ["Game/Classic/Auras/MSUF_Auras3_Compile.lua"] = arg[6],
}

local registered
local namespace = {
    Client = { IsClassic = true, DispellableDebuffFilter = "HARMFUL|RAID_PLAYER_DISPELLABLE" },
    MSUF_Auras3 = {},
    UF = { RegisterElement = function(_, element) registered = element end },
    ExportPublic = function(name, value) _G[name] = value; return value end,
}
_G.MSUF_NS, _G.MSUF = namespace, namespace
_G.issecretvalue = function(value) return type(value) == "table" and value._secret == true end

-- Widget stub ---------------------------------------------------------------------------
-- Every write is counted globally and per widget while `counting` is set. The
-- wrapper itself allocates nothing, so the allocation check can run through it.
local counting, total, counts = false, 0, {}
local Writes = {}
function Writes:Show() self._shown = true end
function Writes:Hide() self._shown = false end
function Writes:SetShown(shown) self._shown = shown == true end
function Writes:SetParent(parent) self._parent = parent end
function Writes:SetFrameLevel(level) self._frameLevel = level end
function Writes:SetScript(name, handler) self._scripts = self._scripts or {}; self._scripts[name] = handler end
function Writes:HookScript(name, handler)
    self._scripts = self._scripts or {}
    local previous = self._scripts[name]
    if previous then
        self._scripts[name] = function(...) previous(...); handler(...) end
    else
        self._scripts[name] = handler
    end
end
function Writes:SetTexture(texture) self._texture = texture end
function Writes:SetAtlas(atlas) self._atlas = atlas end
function Writes:SetText(text) self._text = text end
function Writes:SetCooldown(start, duration) self._start, self._duration = start, duration end
function Writes:Clear() self._start, self._duration = nil, nil end
function Writes:SetVertexColor(r, g, b, a) self._vr, self._vg, self._vb, self._va = r, g, b, a end
function Writes:AddMaskTexture(mask) self._mask = mask end
function Writes:RemoveMaskTexture(mask) if self._mask == mask then self._mask = nil end end
for _, name in ipairs({
    "RegisterEvent", "UnregisterEvent", "ClearAllPoints", "SetAllPoints", "SetAlpha", "EnableMouse", "SetPoint",
    "SetSize", "SetWidth", "SetHeight", "SetDrawSwipe", "SetHideCountdownNumbers", "SetSwipeColor", "SetDrawEdge",
    "SetTexCoord", "SetFont", "SetTextColor", "SetShadowOffset", "SetDesaturated", "SetJustifyH", "SetJustifyV",
    "SetBlendMode", "SetMinMaxValues", "SetValue", "SetStatusBarTexture", "SetStatusBarColor", "SetColorTexture",
    "SetReverse", "SetMouseClickEnabled", "SetMouseMotionEnabled", "SetCountdownMillisecondsThreshold",
    "SetSwipeTexture", "SetFrameStrata", "SetOwner",
}) do Writes[name] = function() end end

local Widget = {}
Widget.__index = Widget
for name, write in pairs(Writes) do
    Widget[name] = function(self, ...)
        if counting then
            total = total + 1
            counts[name] = (counts[name] or 0) + 1
            local own = self._calls
            if not own then own = {}; self._calls = own end
            own[name] = (own[name] or 0) + 1
        end
        return write(self, ...)
    end
end
function Widget:IsShown() return self._shown == true end
function Widget:IsVisible() return self._shown == true end
function Widget:IsForbidden() return false end
function Widget:GetParent() return self._parent end
function Widget:GetFrameLevel() return self._frameLevel or 1 end
function Widget:GetNumRegions() return 0 end
function Widget:GetRegions() return nil end
function Widget:GetObjectType() return self._objectType or "Frame" end
function Widget:CreateTexture() return setmetatable({ _shown = true, _parent = self }, Widget) end
Widget.CreateMaskTexture = Widget.CreateTexture
Widget.CreateFontString = Widget.CreateTexture
_G.CreateFrame = function(frameType, _, parent)
    return setmetatable({ _shown = true, _parent = parent, _objectType = frameType }, Widget)
end

--- Runs fn with write counting on and returns the total and the per-method counts.
local function CountWrites(fn)
    counting, total, counts = true, 0, {}
    fn()
    counting = false
    return total, counts
end
local function Describe(byName)
    local parts = {}
    for name, n in pairs(byName) do parts[#parts + 1] = name .. "=" .. n end
    table.sort(parts)
    return table.concat(parts, " ")
end
--- Bytes allocated per call with the collector stopped, so nothing is freed.
local function BytesPerCall(fn, n)
    counting = false
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
_G.UnitExists = function() return true end
_G.UnitIsUnit = function(a, b) return a == b end
_G.UnitInRange = function() return true, true end
_G.GetTime = function() return 50 end
_G.InCombatLockdown = function() return false end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.GameTooltip = setmetatable({}, Widget)
_G.C_Timer = {}
_G.DebuffTypeColor = {
    Magic = { r = 0.20, g = 0.60, b = 1.00, a = 1 },
    Curse = { r = 0.60, g = 0.00, b = 1.00, a = 1 },
}
local world = {}
local api = { slots = 0 }
local failSlotScan       -- predicate: GetAuraDataBySlot raises for a matching aura
local failInstanceFetch  -- true: GetAuraDataByAuraInstanceID raises
-- The client builds a new AuraData table for every query, so the lane's stored
-- table is the previous snapshot. Off only while allocations are measured.
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
    if filter:find("RAID_PLAYER_DISPELLABLE", 1, true) and aura.dispelName == nil then return false end
    return true
end
_G.C_UnitAuras = {
    GetAuraSlots = function(unit, filter)
        api.slots = api.slots + 1
        local list, out = UnitList(unit), {}
        for i = 1, #list do if Matches(list[i], filter) then out[#out + 1] = i end end
        return nil, unpack(out)
    end,
    GetAuraDataBySlot = function(unit, slot)
        local aura = UnitList(unit)[slot]
        if failSlotScan and aura and failSlotScan(aura) then error("injected scan failure") end
        return Snapshot(aura)
    end,
    GetAuraDataByAuraInstanceID = function(unit, id)
        if failInstanceFetch then error("injected delta failure") end
        local list = UnitList(unit)
        for i = 1, #list do if list[i].auraInstanceID == id then return Snapshot(list[i]) end end
        return nil
    end,
    GetAuraDataByIndex = function(unit, index, filter)
        local n, list = 0, UnitList(unit)
        for i = 1, #list do
            if Matches(list[i], filter) then n = n + 1; if n == index then return Snapshot(list[i]) end end
        end
        return nil
    end,
    GetUnitAuraInstanceIDs = function(unit, filter)
        local out, list = {}, UnitList(unit)
        for i = 1, #list do if Matches(list[i], filter) then out[#out + 1] = list[i].auraInstanceID end end
        return out
    end,
}
_G.AuraUtil = {}

local nextID = 1000
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

-- SavedVariables ------------------------------------------------------------------------
-- target: default sort, shaped debuff lane with the per-aura dispel type border.
-- player: expiration-sorted buffs, bar-only debuffs. focus: only a custom
-- container whose sort name the Features parser does not know.
_G.MSUF_DB = {
    general = {},
    auras3 = {
        enabled = true, showPlayer = true, showTarget = true, showFocus = true, showBoss = true,
        shared = { appearanceIconShapes = { buff = "RECTANGLE", debuff = "CIRCLE" } },
        perUnit = {
            target = {
                layout = {}, filters = {},
                layoutShared = { showBuffs = true, showDebuffs = true, debuffTypeBorderMode = "BORDER" },
            },
            player = {
                layout = {}, filters = {},
                layoutShared = {
                    showBuffs = true, showDebuffs = true, buffSortMethod = "EXPIRATION",
                    debuffShowDurationBar = true, debuffDurationBarDisplay = "BAR_ONLY",
                },
            },
            focus = {
                layout = {}, filters = {},
                layoutShared = { showBuffs = false, showDebuffs = false },
            },
        },
        customContainers = { perUnit = { focus = { items = {
            [1] = {
                enabled = true, auraType = "BUFF", spellIDs = "777001 777002",
                filters = { enabled = true, hidePermanent = true },
                placed = { size = 20, max = 8, perRow = 8, sortMethod = "CUSTOM_PRIORITY" },
            },
        } } } },
    },
}

-- Load the real chain in the shipped TOC order -------------------------------------------
local manifest = assert(loadfile(root .. "/tools/tests/client_manifest.lua"))()
local chain = {
    "Auras3/MSUF_Auras3_Core.lua", "Auras3/MSUF_Auras3_IconShape.lua",
    "Game/Classic/Auras/MSUF_Auras3_Visuals.lua", "Game/Classic/Auras/MSUF_Auras3_Features.lua",
    "Game/Classic/Auras/MSUF_Auras3_Preview.lua", "Game/Classic/Auras/MSUF_Auras3_Compile.lua",
    "Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua",
}
local overridePaths = {}
for relative, path in pairs(overrides) do overridePaths[ADDON .. relative] = path end
manifest.LoadSelected(root, "Vanilla", namespace, chain, function(path)
    return loadfile(overridePaths[path] or path)
end)
assert(registered, "Classic aura element did not register")
local A3 = namespace.MSUF_Auras3
local visuals = assert(A3.ClassicVisuals, "Classic visuals missing")

local function NewFrame(unit, spec)
    local frame = setmetatable({
        _shown = true, MSUFUnitKey = unit, _msufActiveElements = { Auras = true }, MSUFSpec = spec or {},
    }, Widget)
    registered.Create(frame)
    return frame
end
local function Update(frame, payload) return registered.Update(frame, "UNIT_AURA", frame.MSUFUnitKey, payload) end
local function CountKeys(map) local n = 0; for _ in pairs(map) do n = n + 1 end; return n end
local function VisibleIDs(lane)
    local ids = {}
    for i = 1, lane.visible do ids[i] = tostring(lane[i].auraInstanceID) end
    return table.concat(ids, ",")
end
--- Counts lane.updateButton calls. ApplyConfigLane reassigns the field, so
--- wrap only after the config under test was applied.
local function CountUpdater(lane)
    local inner, counter = assert(lane.updateButton, "lane has no button updater"), { n = 0 }
    lane.updateButton = function(...) counter.n = counter.n + 1; return inner(...) end
    return counter
end
local function SameColor(tex, r, g, b)
    return tex._vr == r and tex._vg == g and tex._vb == b
end

-- 1. Shaped per-aura dispel border ------------------------------------------------------
local targetList = UnitList("target")
for _ = 1, 6 do targetList[#targetList + 1] = Aura(true) end
local curse = Aura(false, { dispelName = "Curse" })
targetList[#targetList + 1] = curse
targetList[#targetList + 1] = Aura(false, { dispelName = "Curse" })
targetList[#targetList + 1] = Aura(false, { dispelName = "Curse" })
local target = NewFrame("target")
counting = true
assert(registered.Enable(target) == true, "target aura element did not enable")
local targetState = assert(target._msufA3State, "target aura state missing")
local buff, debuff = targetState.lanes.buff, targetState.lanes.debuff
assert(buff.visible == 6 and debuff.visible == 3, "target lanes did not render the unit's auras")
assert(debuff.config.iconShape == "CIRCLE" and debuff.config.showDispelTypeBorder == true,
    "precondition: the debuff lane is not a shaped lane with the dispel type border")
local border = assert(debuff[1]._msufA3DispelOverlay, "shaped debuff has no dispel border")
assert(border._shown == true and tostring(border._texture):find("circle_ring_thin", 1, true),
    "shaped dispel border did not take the shape's ring texture: " .. tostring(border._texture))
assert(SameColor(border, 0.6, 0, 1), "shaped dispel border is not Curse coloured after the first paint: "
    .. tostring(border._vr) .. "," .. tostring(border._vg) .. "," .. tostring(border._vb))
local geometryWrites = border._calls.SetTexture
for pass = 1, 2 do
    Update(target, { isFullUpdate = true })
    assert(debuff[1].auraInstanceID == curse.auraInstanceID and SameColor(border, 0.6, 0, 1),
        "shaped dispel border lost its Curse colour on repaint " .. pass .. ": "
        .. tostring(border._vr) .. "," .. tostring(border._vg) .. "," .. tostring(border._vb))
end
assert(border._calls.SetTexture == geometryWrites,
    "an unchanged repaint rewrote the dispel border geometry")
-- The colour cache must still follow a real change of dispel type, both ways.
curse.dispelName = "Magic"
Update(target, { isFullUpdate = true })
assert(SameColor(border, 0.2, 0.6, 1), "dispel border did not follow a Curse to Magic change")
curse.dispelName = "Curse"
Update(target, { isFullUpdate = true })
assert(SameColor(border, 0.6, 0, 1), "dispel border did not follow a Magic to Curse change")
-- A shape change re-applies the geometry, once, and keeps the colour.
_G.MSUF_DB.auras3.shared.appearanceIconShapes.debuff = "RECTANGLE"
A3.BumpRuntimeConfig()
Update(target, { isFullUpdate = true })
assert(tostring(border._texture):find("UI-Debuff-Overlays", 1, true) and SameColor(border, 0.6, 0, 1),
    "dispel border did not return to the rectangle art: " .. tostring(border._texture))
local rectangleWrites = border._calls.SetTexture
Update(target, { isFullUpdate = true })
assert(border._calls.SetTexture == rectangleWrites,
    "an unchanged rectangle repaint rewrote the dispel border geometry")
_G.MSUF_DB.auras3.shared.appearanceIconShapes.debuff = "DIAMOND"
A3.BumpRuntimeConfig()
Update(target, { isFullUpdate = true })
assert(tostring(border._texture):find("diamond_ring_thin", 1, true) and SameColor(border, 0.6, 0, 1)
    and border._shown == true, "dispel border did not follow a shape change: " .. tostring(border._texture))
counting = false
-- The preview helper keeps its sample colour; the geometry helper never paints.
local sample = setmetatable({ _shown = false }, Widget)
assert(A3.ApplyAuraDispelShape(sample, debuff[1].Icon, 24, "CIRCLE") == true
    and sample._vr == nil and sample._shown == false and tostring(sample._texture):find("circle_ring_thin", 1, true),
    "the dispel geometry helper painted or showed the texture")
assert(A3.ApplyAuraDispelShape(sample, debuff[1].Icon, 24, "RECTANGLE") == false,
    "the dispel geometry helper claimed a rectangle icon")
assert(A3.ApplyAuraDispelPreview(sample, debuff[1].Icon, 24, "BORDER", "CIRCLE") == true
    and SameColor(sample, 0.20, 0.60, 1.00) and sample._shown == true,
    "the dispel preview lost its sample colour")
assert(A3.ApplyAuraDispelPreview(sample, debuff[1].Icon, 24, "OFF", "CIRCLE") == false
    and A3.ApplyAuraDispelPreview(sample, debuff[1].Icon, 24, "BORDER", "RECTANGLE") == false,
    "the dispel preview accepted an OFF mode or a rectangle icon")

-- 2. A lane update that raised forces a full rescan ---------------------------------------
local function AssertTargetLanes(label)
    assert(CountKeys(buff.all) == #targetList - 3 and CountKeys(debuff.all) == 3
        and buff.visible == #targetList - 3 and debuff.visible == 3
        and debuff[1].auraInstanceID == curse.auraInstanceID,
        label .. ": lanes track " .. CountKeys(buff.all) .. " buffs and " .. CountKeys(debuff.all)
        .. " debuffs, show " .. buff.visible .. " and " .. debuff.visible)
end
local function PlainDelta()
    local added = Aura(true)
    targetList[#targetList + 1] = added
    return { addedAuras = { Snapshot(added) } }
end
AssertTargetLanes("before the injected failures")
-- A plain delta is not a rescan: this is what the repair below is measured against.
local scans = api.slots
Update(target, PlainDelta())
assert(api.slots == scans, "precondition: a plain delta rescanned the unit")

failSlotScan = function(aura) return aura.isHarmful == true end
local ok, err = pcall(Update, target, { isFullUpdate = true })
failSlotScan = nil
assert(ok == false and tostring(err):find("injected scan failure", 1, true),
    "the injected full-scan failure did not surface: " .. tostring(err))
scans = api.slots
Update(target, PlainDelta())
assert(api.slots > scans, "a full scan raised, and the next plain delta did not rescan the unit")
AssertTargetLanes("after the delta that followed a raised full scan")
scans = api.slots
Update(target, PlainDelta())
assert(api.slots == scans, "the repaired frame kept rescanning on every delta")
AssertTargetLanes("after the delta that followed the repair")

failInstanceFetch = true
ok, err = pcall(Update, target, { updatedAuraInstanceIDs = { curse.auraInstanceID } })
failInstanceFetch = nil
assert(ok == false and tostring(err):find("injected delta failure", 1, true),
    "the injected delta failure did not surface: " .. tostring(err))
scans = api.slots
Update(target, PlainDelta())
assert(api.slots > scans, "a delta merge raised, and the next plain delta did not rescan the unit")
AssertTargetLanes("after the delta that followed a raised delta merge")

-- An empty payload and the combat re-render repair an aborted update as well.
failInstanceFetch = true
assert(pcall(Update, target, { updatedAuraInstanceIDs = { curse.auraInstanceID } }) == false)
failInstanceFetch = nil
scans = api.slots
Update(target, {})
assert(api.slots > scans, "an empty payload did not repair an aborted update")
failInstanceFetch = true
assert(pcall(Update, target, { updatedAuraInstanceIDs = { curse.auraInstanceID } }) == false)
failInstanceFetch = nil
scans = api.slots
registered.Update(target, "PLAYER_REGEN_ENABLED")
assert(api.slots > scans, "the combat re-render trusted the lanes of an aborted update")
scans = api.slots
Update(target, {})
assert(api.slots == scans, "an empty payload rescanned a healthy frame")
AssertTargetLanes("after every repair")

-- 3. Natural-order compaction keeps tracked auras that are filtered out -------------------
local focusList = UnitList("focus")
local sleeper = Aura(true, { spellId = 777001, duration = 0, expirationTime = 0 })
focusList[#focusList + 1] = sleeper
local focus = NewFrame("focus")
assert(registered.Enable(focus) == true, "focus aura element did not enable")
local custom = assert(focus._msufA3State.lanes.custom1, "custom container lane missing")
assert(custom.config.naturalOrder == true and custom.config.sortOrder == 0 and custom.config.hidePermanent == true,
    "precondition: an unknown custom sort name no longer falls back to natural order")
assert(custom.all[sleeper.auraInstanceID] ~= nil and custom.active[sleeper.auraInstanceID] == nil
    and custom.visible == 0, "precondition: the permanent aura is not tracked-but-hidden")
for _ = 1, 100 do
    local churn = Aura(true, { spellId = 777002 })
    focusList[#focusList + 1] = churn
    Update(focus, { addedAuras = { Snapshot(churn) } })
    table.remove(focusList)
    Update(focus, { removedAuraInstanceIDs = { churn.auraInstanceID } })
end
assert(custom.orderedCount <= 8, "precondition: the natural order list was never compacted: "
    .. tostring(custom.orderedCount))
sleeper.duration, sleeper.expirationTime = 30, 80
Update(focus, { updatedAuraInstanceIDs = { sleeper.auraInstanceID } })
assert(custom.active[sleeper.auraInstanceID] == true and custom.visible == 1
    and custom.visibleByID[sleeper.auraInstanceID] == 1 and custom[1].auraInstanceID == sleeper.auraInstanceID
    and custom[1]._shown == true,
    "an aura that was filtered out at compaction time never rendered once it became visible")

-- 4. Only time-keyed sorts re-render on a refresh ----------------------------------------
-- Default sort: a refresh updates the one button in place, whatever it changed.
assert(buff.config.sortOrder == 1 and buff.config.naturalOrder == false and buff.visible > 1,
    "precondition: the target buff lane is not on the default sort")
local refreshed = targetList[1]
local order = VisibleIDs(buff)
local updater = CountUpdater(buff)
Update(target, { updatedAuraInstanceIDs = { refreshed.auraInstanceID } })
assert(updater.n == 1, "default sort: an unchanged refresh ran the button updater " .. updater.n .. " times")
refreshed.expirationTime = 95
updater.n = 0
Update(target, { updatedAuraInstanceIDs = { refreshed.auraInstanceID } })
assert(updater.n == 1 and VisibleIDs(buff) == order,
    "default sort: a refreshed aura re-rendered the lane (" .. updater.n .. " updater calls)")
local refreshedCooldown = buff[buff.visibleByID[refreshed.auraInstanceID]].Cooldown
assert(refreshedCooldown._start == 65 and refreshedCooldown._duration == 30,
    "default sort: the in-place refresh did not reach the button's cooldown")

-- Expiration sort: in place while the times stand still, re-sorted when they move.
local playerList = UnitList("player")
local early = Aura(true, { expirationTime = 60 })
local middle = Aura(true, { expirationTime = 70 })
local late = Aura(true, { expirationTime = 80 })
playerList[1], playerList[2], playerList[3] = late, early, middle
local player = NewFrame("player")
assert(registered.Enable(player) == true, "player aura element did not enable")
local playerBuff = player._msufA3State.lanes.buff
local function IDs(...)
    local ids = {}
    for i = 1, select("#", ...) do ids[i] = tostring((select(i, ...)).auraInstanceID) end
    return table.concat(ids, ",")
end
assert(playerBuff.config.sortOrder == 3 and playerBuff.config.reorderOnUpdate == true
    and VisibleIDs(playerBuff) == IDs(early, middle, late), "precondition: the player buff lane is not expiration sorted")
updater = CountUpdater(playerBuff)
Update(player, { updatedAuraInstanceIDs = { early.auraInstanceID } })
assert(updater.n == 1 and VisibleIDs(playerBuff) == IDs(early, middle, late),
    "expiration sort: an unchanged refresh re-rendered the lane (" .. updater.n .. " updater calls)")
early.expirationTime = 90
updater.n = 0
Update(player, { updatedAuraInstanceIDs = { early.auraInstanceID } })
assert(updater.n == 3 and VisibleIDs(playerBuff) == IDs(middle, late, early),
    "expiration sort: a moved expiration did not re-sort the lane: " .. VisibleIDs(playerBuff))
-- A secret time ranks as one constant; it is never compared or subtracted.
middle.expirationTime = { _secret = true }
updater.n = 0
Update(player, { updatedAuraInstanceIDs = { middle.auraInstanceID } })
assert(updater.n == 3 and VisibleIDs(playerBuff) == IDs(late, early, middle),
    "expiration sort: a time that turned secret did not re-sort the lane: " .. VisibleIDs(playerBuff))
updater.n = 0
Update(player, { updatedAuraInstanceIDs = { middle.auraInstanceID } })
assert(updater.n == 1 and VisibleIDs(playerBuff) == IDs(late, early, middle),
    "expiration sort: an unchanged secret time re-rendered the lane (" .. updater.n .. " updater calls)")

-- Both sort parsers: the unit lane compiler, the group lane compiler (Compile)
-- and the custom container compiler (Features), which maps some names differently.
local function ExpectReorder(actual, expected, label)
    assert(actual == expected, label .. ": reorderOnUpdate is " .. tostring(actual) .. ", expected " .. tostring(expected))
end
local UNIT_SORTS = {
    DEFAULT = false, PLAYER = false, NAME = false, NAME_ONLY = false, INSTANCE_ID = false,
    DURATION = true, BIG_DEFENSIVE = true, EXPIRATION = true, TIME_REMAINING = true, EXPIRATION_ONLY = true,
}
local targetShared = _G.MSUF_DB.auras3.perUnit.target.layoutShared
for name, expected in pairs(UNIT_SORTS) do
    for _, reverse in ipairs({ false, true }) do
        targetShared.buffSortMethod, targetShared.buffSortReverse = name, reverse
        A3.BumpRuntimeConfig()
        ExpectReorder(A3.ResolveUnitFrameConfig("target", nil).lanes.buff.reorderOnUpdate, expected,
            "unit lane " .. name .. (reverse and " reversed" or ""))
    end
end
targetShared.buffSortMethod, targetShared.buffSortReverse = nil, nil

local partyList = UnitList("party1")
for _ = 1, 4 do partyList[#partyList + 1] = Aura(true) end
local partySpec = { scope = "group", auras = { enabled = true, showBuffs = true, maxBuffs = 4 } }
local party = NewFrame("party1", partySpec)
local function PartyBuffConfig()
    A3.BumpRuntimeConfig()
    assert(registered.Enable(party) == true, "party aura element did not enable")
    return party._msufA3State.lanes.buff.config
end
for name, expected in pairs(UNIT_SORTS) do
    partySpec.auras.sortMethod = name
    ExpectReorder(PartyBuffConfig().reorderOnUpdate, expected, "group lane " .. name)
end
partySpec.auras.sortMethod, partySpec.auras.sortByDuration = nil, true
ExpectReorder(PartyBuffConfig().reorderOnUpdate, true, "group lane sortByDuration")
partySpec.auras.sortByDuration, partySpec.auras.sortReverse = nil, true
ExpectReorder(PartyBuffConfig().reorderOnUpdate, false, "group lane default reversed")
partySpec.auras.sortReverse = nil

local CUSTOM_SORTS = {
    DEFAULT = false, NAME = false, NAME_ONLY = false, INSTANCE_ID = false, CUSTOM_PRIORITY = false,
    DURATION = true, EXPIRATION = true, EXPIRATION_ONLY = true,
}
local placed = _G.MSUF_DB.auras3.customContainers.perUnit.focus.items[1].placed
for name, expected in pairs(CUSTOM_SORTS) do
    for _, reverse in ipairs({ false, true }) do
        placed.sortMethod, placed.sortReverse = name, reverse
        A3.BumpRuntimeConfig()
        ExpectReorder(A3.ResolveUnitFrameConfig("focus", nil).lanes.custom1.reorderOnUpdate, expected,
            "custom container " .. name .. (reverse and " reversed" or ""))
    end
end
placed.sortMethod, placed.sortReverse = "CUSTOM_PRIORITY", nil

-- 5. An unchanged refreshed aura writes no layout and allocates nothing -------------------
-- The first update also applies the config generations the matrix above bumped.
local refreshPayload = { updatedAuraInstanceIDs = { refreshed.auraInstanceID } }
Update(target, refreshPayload)
assert(buff.config.reorderOnUpdate == false and buff.visible > 1,
    "precondition: the target buff lane is not on the default sort")
local refreshedButton = buff[buff.visibleByID[refreshed.auraInstanceID]]
local layoutTotal, layoutByName = CountWrites(function() visuals.ApplyButtonLayout(buff, refreshedButton) end)
assert(layoutTotal >= 5 and layoutByName.SetTexCoord == 1 and layoutByName.SetReverse == 1,
    "precondition: a layout pass no longer writes the icon crop and swipe direction: " .. Describe(layoutByName))
local refreshTotal, refreshByName = CountWrites(function() Update(target, refreshPayload) end)
assert((refreshByName.SetTexCoord or 0) == 0 and (refreshByName.SetReverse or 0) == 0
    and (refreshByName.SetSwipeTexture or 0) == 0 and refreshTotal <= 1,
    "an unchanged refreshed aura re-applied its button layout: " .. Describe(refreshByName))
-- Allocation: the stub must hand back the stored table, or its own snapshot
-- would be the only thing measured.
snapshots = false
Update(target, refreshPayload)
local bytes = BytesPerCall(function() Update(target, refreshPayload) end, 200)
assert(bytes == 0, ("an unchanged refreshed aura allocated %.1f bytes per event"):format(bytes))
local partyPayload = { updatedAuraInstanceIDs = { partyList[1].auraInstanceID } }
PartyBuffConfig()
Update(party, partyPayload)
bytes = BytesPerCall(function() Update(party, partyPayload) end, 200)
assert(bytes == 0, ("an unchanged refreshed group aura allocated %.1f bytes per event"):format(bytes))
snapshots = true

-- The stamp follows both layout inputs: the compiled lane config and whether
-- UpdateCooldown currently shows the cooldown.
local owner = setmetatable({ _shown = true }, Widget)
local probe = setmetatable({ _shown = true }, Widget)
probe.Icon, probe.Count = probe:CreateTexture(), probe:CreateFontString()
probe.Cooldown = _G.CreateFrame("Cooldown", nil, probe)
local probeLane = { ownerFrame = owner, config = { size = 20, iconZoom = 100, iconShape = "RECTANGLE", showCooldown = true } }
local probeData = { auraInstanceID = 7, applications = 1 }
local function ProbeLayoutWrites()
    local _, byName = CountWrites(function() visuals.UpdateButtonVisual(probeLane, probe, "target", probeData) end)
    return byName.SetTexCoord or 0
end
assert(ProbeLayoutWrites() == 1, "a button without a layout stamp was not laid out")
assert(ProbeLayoutWrites() == 0, "an unchanged button was laid out again")
probeLane.config = { size = 20, iconZoom = 150, iconShape = "RECTANGLE", showCooldown = true }
assert(ProbeLayoutWrites() == 1, "a new lane config did not re-apply the button layout")
probe._msufA3CooldownShown = true
assert(ProbeLayoutWrites() == 1 and probe.Cooldown._shown == true,
    "a cooldown that UpdateCooldown showed did not re-apply the button layout")
assert(ProbeLayoutWrites() == 0, "an unchanged button was laid out again after the cooldown stamp")

-- Bar-only lanes hide the swipe the core updater shows for a newly timed aura;
-- that is the per-update half of the layout and must survive the stamp.
local permanent = Aura(false, { duration = 0, expirationTime = 0 })
playerList[#playerList + 1] = permanent
Update(player, { isFullUpdate = true })
local playerDebuff = player._msufA3State.lanes.debuff
assert(playerDebuff.config.showDurationBar == true and playerDebuff.config.durationBarDisplay == "BAR_ONLY"
    and playerDebuff.config.showCooldown == true and playerDebuff.visible == 1
    and playerDebuff[1]._msufA3CooldownShown == nil, "precondition: the player debuff lane is not a bar-only lane")
permanent.duration, permanent.expirationTime = 30, 80
Update(player, { updatedAuraInstanceIDs = { permanent.auraInstanceID } })
assert(playerDebuff[1]._msufA3CooldownShown == true and playerDebuff[1].Cooldown._shown == false,
    "a bar-only lane kept the cooldown swipe of a newly timed aura")

print("classic aura update path smoke passed")
