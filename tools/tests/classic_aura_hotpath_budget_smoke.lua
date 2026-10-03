-- classic_aura_hotpath_budget_smoke.lua <repoRoot>
--
-- Cost budgets for the Classic aura backend (Game/Classic/Auras), measured with
-- two deterministic counts, never wall-clock time:
--   * Lua VM instructions per operation (a count hook on every instruction);
--   * bytes allocated per hot event, with the collector stopped.
-- It also counts the expensive steps of an element apply: lane full scans
-- (C_UnitAuras.GetAuraSlots calls made by FullScanLane) and config applies
-- (the state root re-anchored by ApplyConfig).
--
-- The apply runs through the real UF.ApplyElementToFrame, sliced out of
-- Libs/MSUFUnitFrames/MSUF_UF_Core.lua, so the Create -> Apply -> Enable order
-- is the shipped one. A re-apply must run one config apply and one full scan
-- per enabled lane (review 2026-10-01, C3.2: Apply and Enable each ran both).
--
-- Budgets are the values measured on 2026-10-01 plus 2 %. A restructure must
-- not exceed them; when a change makes an operation cheaper, lower its budget
-- in the same change. Raise one only together with a recorded reason.
--
-- Arguments: repository root. Runs through .github/scripts/auras3_test_driver.lua.
local root = assert(arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local ADDON = root .. "/MidnightSimpleUnitFrames/"

-- Budgets -------------------------------------------------------------------------------
-- Lua VM instructions per operation: the 2026-10-01 baseline plus 2 %.
-- 2026-10-02 (W-C3): direct module calls instead of guards made three
-- operations cheaper (targetAddRemove 11224 -> 11164, targetForceFull
-- 10942 -> 10898, targetReapply 27935 -> 27653); their budgets are the new
-- values plus 2 %.
-- 2026-10-02 (W4-C5): a lane scan asks UnitIsUnit once per source token
-- instead of once per aura, so a full scan and a re-apply got cheaper
-- (targetForceFull 10975 -> 10749, targetReapply 27730 -> 27432); their
-- budgets are the new values plus 2 %.
-- 2026-10-03 (fx2 C4-2): a group lane compiles its own stack anchor, stack
-- X/Y and cooldown X/Y (Menu2 Auras > Group), which were dead settings on
-- Classic; the re-apply recompiles them (partyReapply 12821 -> 13029, no new
-- native call). Its budget is the new value plus 2 %.
-- MSUF_AURA_BUDGET_MEASURE=1 prints the measured values without asserting.
local BUDGET = {
    targetDelta = 781,         -- UNIT_AURA, one refreshed aura (in-place update)
    targetAddRemove = 11387,   -- UNIT_AURA, one aura added, then removed
    targetForceFull = 10964,   -- ForceUpdate: full scan and render of both lanes
    targetReapply = 27981,     -- UF.ApplyElementToFrame on an active frame (C3.2: was 56621)
    partyDelta = 702,          -- group frame UNIT_AURA, one refreshed aura
    partyReapply = 13290,      -- UF.ApplyElementToFrame on an active group frame (C3.2: was 25598)
    combatRender = 173,        -- PLAYER_REGEN_DISABLED render of the cached lanes
}
-- Native API calls per operation (C_UnitAuras getters, unit queries,
-- issecretvalue, GetTime). A call count is exact, so any extra call fails.
-- Lower one with the change that saves it; raise one only together with a
-- recorded reason. Measured 2026-10-02 (W4-C5) against the wave-3 base
-- (before -> now): a lane scan asks UnitIsUnit once per source token instead
-- of once per aura (targetForceFull 328 -> 294, targetReapply 334 -> 300,
-- partyReapply 109 -> 99), and the restricted-comparison guard on that
-- answer costs a delta one issecretvalue (targetDelta 13 -> 14, partyDelta
-- 12 -> 13, targetAddRemove 312 -> 313).
local NATIVE_BUDGET = {
    targetDelta = 14, targetAddRemove = 313,
    targetForceFull = 294, targetReapply = 300,
    partyDelta = 13, partyReapply = 99, combatRender = 1,
}
local MEASURE_ONLY = os.getenv("MSUF_AURA_BUDGET_MEASURE") == "1"

local registered
local namespace = {
    Client = { IsClassic = true, DispellableDebuffFilter = "HARMFUL|RAID_PLAYER_DISPELLABLE" },
    MSUF_Auras3 = {},
    UF = {},
    ExportPublic = function(name, value) _G[name] = value; return value end,
}
_G.MSUF_NS, _G.MSUF = namespace, namespace
_G.issecretvalue = function() return false end

-- Widget stub ---------------------------------------------------------------------------
-- Writes record per-object call counts; nothing here allocates per call.
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
function Writes:SetText(text) self._text = text end
function Writes:SetCooldown(start, duration) self._start, self._duration = start, duration end
function Writes:Clear() self._start, self._duration = nil, nil end
function Writes:SetVertexColor(r, g, b, a) self._vr, self._vg, self._vb, self._va = r, g, b, a end
function Writes:AddMaskTexture(mask) self._mask = mask end
function Writes:RemoveMaskTexture(mask) if self._mask == mask then self._mask = nil end end
function Writes:SetAllPoints() self._setAllPoints = (self._setAllPoints or 0) + 1 end
for _, name in ipairs({
    "RegisterEvent", "UnregisterEvent", "RegisterUnitEvent", "ClearAllPoints", "SetAlpha", "EnableMouse", "SetPoint",
    "SetSize", "SetWidth", "SetHeight", "SetDrawSwipe", "SetHideCountdownNumbers", "SetSwipeColor", "SetDrawEdge",
    "SetTexCoord", "SetFont", "SetTextColor", "SetShadowOffset", "SetDesaturated", "SetJustifyH", "SetJustifyV",
    "SetBlendMode", "SetMinMaxValues", "SetValue", "SetStatusBarTexture", "SetStatusBarColor", "SetColorTexture",
    "SetReverse", "SetMouseClickEnabled", "SetMouseMotionEnabled", "SetCountdownMillisecondsThreshold",
    "SetSwipeTexture", "SetFrameStrata", "SetOwner", "SetAtlas", "SetDrawLayer",
}) do Writes[name] = function() end end

local Widget = {}
Widget.__index = Widget
for name, write in pairs(Writes) do Widget[name] = write end
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

-- Game API stubs ------------------------------------------------------------------------
_G.UnitExists = function() return true end
_G.UnitIsUnit = function(a, b) return a == b end
_G.UnitInRange = function() return true, true end
_G.UnitGUID = function(unit) return "GUID-" .. tostring(unit) end
_G.GetTime = function() return 50 end
_G.InCombatLockdown = function() return false end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.GameTooltip = setmetatable({}, Widget)
_G.C_Timer = {}
_G.DebuffTypeColor = {
    Magic = { r = 0.20, g = 0.60, b = 1.00, a = 1 },
    Curse = { r = 0.60, g = 0.00, b = 1.00, a = 1 },
    none = { r = 0.80, g = 0.00, b = 0.00, a = 1 },
}

-- Lane full scans are the GetAuraSlots calls made from FullScanLane; the
-- token-membership walk and the direct visual walks are not lane scans. The
-- defining line of FullScanLane is located in the loaded sources, so the
-- count follows the function wherever a split moves it.
local scanSites = {}
local laneScans = 0
local world = {}
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
-- Fixed per-unit slot results: the stub hands back stored values, so the
-- measured allocation is the backend's own.
local slotCache = {}
local function Slots(unit, filter)
    local byFilter = slotCache[unit]
    if not byFilter then byFilter = {}; slotCache[unit] = byFilter end
    local slots = byFilter[filter]
    if not slots then
        slots = { n = 0 }
        local list = UnitList(unit)
        for i = 1, #list do
            if Matches(list[i], filter) then slots.n = slots.n + 1; slots[slots.n] = i end
        end
        byFilter[filter] = slots
    end
    return slots
end
local function InvalidateSlots() for unit in pairs(slotCache) do slotCache[unit] = nil end end
_G.C_UnitAuras = {
    GetAuraSlots = function(unit, filter)
        local info = debug.getinfo(2, "S")
        if info and scanSites[info.source .. ":" .. tostring(info.linedefined)] then laneScans = laneScans + 1 end
        local slots = Slots(unit, filter)
        return nil, unpack(slots, 1, slots.n)
    end,
    GetAuraDataBySlot = function(unit, slot) return UnitList(unit)[slot] end,
    GetAuraDataByAuraInstanceID = function(unit, id)
        local list = UnitList(unit)
        for i = 1, #list do if list[i].auraInstanceID == id then return list[i] end end
        return nil
    end,
    GetAuraDataByIndex = function(unit, index, filter)
        local n, list = 0, UnitList(unit)
        for i = 1, #list do
            if Matches(list[i], filter) then n = n + 1; if n == index then return list[i] end end
        end
        return nil
    end,
}
_G.AuraUtil = {}

local nextID = 1000
local function Aura(helpful, fields)
    nextID = nextID + 1
    local aura = {
        auraInstanceID = nextID, spellId = 900000 + nextID, name = "Aura" .. nextID, icon = 134400 + nextID,
        applications = 1, duration = 30, expirationTime = 80, isHelpful = helpful, isHarmful = not helpful,
        isFromPlayerOrPlayerPet = false, sourceUnit = "target",
    }
    for key, value in pairs(fields or {}) do aura[key] = value end
    return aura
end

-- SavedVariables: the factory-like target layout (default sort, per-aura dispel
-- type border) and a party frame with buffs and debuffs.
_G.MSUF_DB = {
    general = {},
    auras3 = {
        enabled = true, showPlayer = true, showTarget = true,
        shared = {},
        perUnit = {
            target = {
                layout = {}, filters = {},
                layoutShared = { showBuffs = true, showDebuffs = true, debuffTypeBorderMode = "BORDER" },
            },
        },
    },
}


-- The real element apply funnel ----------------------------------------------------------
-- UF.ApplyElementToFrame and the helpers it calls, sliced out of the core.
local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()
local corePath = ADDON .. "Libs/MSUFUnitFrames/MSUF_UF_Core.lua"
local coreSource = Slice.Read(corePath)
local UF = namespace.UF
UF.elements = {}
local coreChunk = table.concat({
    "local UF = ...",
    "local function GetUpdateKey(name) return 'MSUF_Update' .. name end",
    "local function ApplyElementAllowed() return true end",
    "local function RefreshFrameRoutingAfterElementApply() return false end",
    Slice.Function(coreSource, "local function SelectElementUpdate", corePath),
    Slice.Function(coreSource, "local function FrameDisableElement", corePath),
    Slice.Function(coreSource, "function UF.ElementEnabled", corePath),
    Slice.Function(coreSource, "function UF.ApplyElementToFrame", corePath),
}, "\n")
assert((loadstring or load)(coreChunk))(UF)
function UF.SetFrameSpec(frame, spec) frame.MSUFSpec = spec end
function UF.RegisterElement(name, element) UF.elements[name] = element; registered = element end

-- Load the real chain in the shipped TOC order ------------------------------------------
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
local scanFunctionFound = false
manifest.LoadSelected(root, "Vanilla", namespace, chain, function(path)
    local line = 0
    for text in (Slice.Read(path) .. "\n"):gmatch("([^\n]*)\n") do
        line = line + 1
        if text:find("^local function FullScanLane%(") then
            scanSites["@" .. path .. ":" .. line] = true
            scanFunctionFound = true
        end
    end
    return loadfile(path)
end)
assert(scanFunctionFound, "FullScanLane was not found in the loaded backend")
assert(registered and UF.elements.Auras == registered, "Classic aura element did not register")

-- Harness ---------------------------------------------------------------------------------
local function NewFrame(unit, spec, groupKind)
    local frame = setmetatable({ _shown = true, MSUFUnitKey = unit, MSUFSpec = spec or {} }, Widget)
    if groupKind then frame._msufIsGroupFrame, frame._msufGFKind = true, groupKind end
    return frame
end
local function Apply(frame) return UF.ApplyElementToFrame(frame, "Auras", nil, nil) end
local function Update(frame, event, payload) return registered.Update(frame, event, frame.MSUFUnitKey, payload) end

--- Lane full scans and config applies (state root re-anchors) one call makes.
local function Steps(frame, fn)
    local stateRoot = frame.Auras
    local configsBefore = stateRoot and stateRoot._setAllPoints or 0
    laneScans = 0
    fn()
    stateRoot = frame.Auras
    return laneScans, (stateRoot and stateRoot._setAllPoints or 0) - configsBefore
end

local function Instructions(fn, n)
    n = n or 20
    fn() -- warm: first-use buttons, caches and lazily created regions
    local ticks = 0
    local function Tick() ticks = ticks + 1 end
    debug.sethook(Tick, "", 1)
    for _ = 1, n do fn() end
    debug.sethook()
    return math.floor(ticks / n + 0.5)
end

-- Native API calls per operation (wave 4 rule: a hot-path budget also counts
-- the client calls, whose cost no VM instruction count sees). A call hook
-- counts the C API stubs the backend reaches; the stubs stay unwrapped, so the
-- instruction counts above are unchanged.
local NATIVE = {}
for _, name in ipairs({ "issecretvalue", "UnitExists", "UnitIsUnit", "UnitInRange", "UnitGUID", "GetTime" }) do
    NATIVE[_G[name]] = name
end
for name, api in pairs(_G.C_UnitAuras) do NATIVE[api] = "C_UnitAuras." .. name end
local function NativeCalls(fn, n)
    n = n or 20
    fn()
    local calls = 0
    debug.sethook(function()
        if NATIVE[debug.getinfo(2, "f").func] then calls = calls + 1 end
    end, "c")
    for _ = 1, n do fn() end
    debug.sethook()
    return math.floor(calls / n + 0.5)
end

--- Bytes allocated per call with the collector stopped, so nothing is freed.
local function BytesPerCall(fn, n)
    fn()
    collectgarbage("collect"); collectgarbage("collect"); collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, n do fn() end
    local after = collectgarbage("count")
    collectgarbage("restart")
    return (after - before) * 1024 / n
end

-- World -----------------------------------------------------------------------------------
local targetList = UnitList("target")
for _ = 1, 8 do targetList[#targetList + 1] = Aura(true) end
targetList[#targetList + 1] = Aura(true, { sourceUnit = "player", isFromPlayerOrPlayerPet = true, mine = true })
for i = 1, 6 do
    local dispelName = i % 3 == 0 and "Curse" or (i % 3 == 1 and "Magic" or nil)
    targetList[#targetList + 1] = Aura(false, { dispelName = dispelName })
end
local refreshed = targetList[3]
local partyList = UnitList("party1")
for _ = 1, 4 do partyList[#partyList + 1] = Aura(true) end
for _ = 1, 2 do partyList[#partyList + 1] = Aura(false, { dispelName = "Magic" }) end

local target = NewFrame("target", { border = { dispel = true } })
local party = NewFrame("party1", { scope = "group", auras = {
    enabled = true, showBuffs = true, maxBuffs = 4, showDebuffs = true, maxDebuffs = 4,
} }, "party")

local results, failures = {}, {}
local function Record(name, value, budget)
    results[#results + 1] = string.format("%s=%d", name, value)
    if not MEASURE_ONLY and value > budget then
        failures[#failures + 1] = string.format("%s: %d instructions, budget %d", name, value, budget)
    end
end
local function RecordNative(name, fn)
    local value, budget = NativeCalls(fn), NATIVE_BUDGET[name]
    results[#results + 1] = string.format("%sNative=%d", name, value)
    if not MEASURE_ONLY and value > budget then
        failures[#failures + 1] = string.format("%s: %d native calls, budget %d", name, value, budget)
    end
end

-- 1. Element apply ------------------------------------------------------------------------
local scans, configs = Steps(target, function() Apply(target) end)
assert(target._msufActiveElements.Auras == true, "target aura element did not enable")
assert(scans >= 2 and configs >= 1, "precondition: the first target apply did not scan and apply its config")
local targetState = assert(target._msufA3State, "target aura state missing")
assert(targetState.lanes.buff.visible == 9 and targetState.lanes.debuff.visible == 6,
    "precondition: the target lanes did not render the unit's auras")
local targetReapplyScans, targetReapplyConfigs = Steps(target, function() Apply(target) end)
Record("targetReapply", Instructions(function() Apply(target) end), BUDGET.targetReapply)
RecordNative("targetReapply", function() Apply(target) end)

Steps(party, function() Apply(party) end)
assert(party._msufActiveElements.Auras == true, "party aura element did not enable")
local partyState = assert(party._msufA3State, "party aura state missing")
assert(partyState.lanes.buff.visible == 4 and partyState.lanes.debuff.visible == 2,
    "precondition: the party lanes did not render the unit's auras")
local partyReapplyScans, partyReapplyConfigs = Steps(party, function() Apply(party) end)
Record("partyReapply", Instructions(function() Apply(party) end), BUDGET.partyReapply)
RecordNative("partyReapply", function() Apply(party) end)

-- 2. Hot events -----------------------------------------------------------------------------
local refreshPayload = { updatedAuraInstanceIDs = { refreshed.auraInstanceID } }
local function TargetDelta() Update(target, "UNIT_AURA", refreshPayload) end
Record("targetDelta", Instructions(TargetDelta), BUDGET.targetDelta)
RecordNative("targetDelta", TargetDelta)
local bytes = BytesPerCall(TargetDelta, 200)
assert(bytes == 0, string.format("a refreshed target aura allocated %.1f bytes per event", bytes))

local extra = Aura(true)
local addPayload = { addedAuras = { extra } }
local removePayload = { removedAuraInstanceIDs = { extra.auraInstanceID } }
local function TargetAddRemove()
    targetList[#targetList + 1] = extra
    InvalidateSlots()
    Update(target, "UNIT_AURA", addPayload)
    targetList[#targetList] = nil
    InvalidateSlots()
    Update(target, "UNIT_AURA", removePayload)
end
Record("targetAddRemove", Instructions(TargetAddRemove), BUDGET.targetAddRemove)
RecordNative("targetAddRemove", TargetAddRemove)
assert(targetState.lanes.buff.visible == 9, "the add/remove cycle left the target buff lane changed")

local function TargetForceFull() Update(target, "ForceUpdate") end
local forceScans = Steps(target, TargetForceFull)
assert(forceScans == 2, "a forced target update did not scan each enabled lane once: " .. forceScans)
Record("targetForceFull", Instructions(TargetForceFull), BUDGET.targetForceFull)
RecordNative("targetForceFull", TargetForceFull)

local partyPayload = { updatedAuraInstanceIDs = { partyList[1].auraInstanceID } }
local function PartyDelta() Update(party, "UNIT_AURA", partyPayload) end
Record("partyDelta", Instructions(PartyDelta), BUDGET.partyDelta)
RecordNative("partyDelta", PartyDelta)
bytes = BytesPerCall(PartyDelta, 200)
assert(bytes == 0, string.format("a refreshed party aura allocated %.1f bytes per event", bytes))

local function CombatRender() Update(target, "PLAYER_REGEN_DISABLED") end
Record("combatRender", Instructions(CombatRender), BUDGET.combatRender)
RecordNative("combatRender", CombatRender)

local steps = string.format("re-apply steps: target %d scans/%d configs, party %d scans/%d configs",
    targetReapplyScans, targetReapplyConfigs, partyReapplyScans, partyReapplyConfigs)
-- C3.2: one element apply is one config apply and one full scan per enabled
-- lane. Apply followed by Enable used to run both twice.
assert(targetReapplyConfigs == 1 and targetReapplyScans == 2,
    "a target re-apply must apply its config once and scan each lane once; " .. steps)
assert(partyReapplyConfigs == 1 and partyReapplyScans == 2,
    "a party re-apply must apply its config once and scan each lane once; " .. steps)
if MEASURE_ONLY then
    print("classic_aura_hotpath_budget_smoke: measured " .. table.concat(results, " ") .. "; " .. steps)
    return
end
assert(#failures == 0, "Classic aura hot-path budget exceeded:\n  " .. table.concat(failures, "\n  "))
print("classic_aura_hotpath_budget_smoke: ok (" .. table.concat(results, " ") .. "; " .. steps .. ")")
