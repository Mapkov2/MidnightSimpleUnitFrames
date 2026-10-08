-- forever_group_buff_coverage_smoke.lua <repoRoot>
--
-- Buff coverage icons on WoW Forever party/raid frames
-- (Game/Forever/GroupFrames/MSUF_GroupFrames_BuffCoverage.lua), driven through
-- the real file with a stub client:
--   * the file returns at once outside Forever and only the Mainline manifest
--     loads it;
--   * UNIT_AURA is registered per group unit token, never globally;
--   * payloads apply incrementally (no aura read for an unrelated change, a
--     removal or an update), a full update reads once;
--   * while aura data is restricted, nothing is read and no false "missing"
--     icon appears (the 40-player probe), unless a buff is flagged never
--     secret; the restriction end reads every member once;
--   * unreachable members, roster swaps, duplicates, disable and samples;
--   * the spell data is ordered, unique and keyed by the DB defaults.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg[1], "usage: forever_group_buff_coverage_smoke.lua <root>"):gsub("\\", "/")
local MODULE = "MidnightSimpleUnitFrames/Game/Forever/GroupFrames/MSUF_GroupFrames_BuffCoverage.lua"

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"), "missing " .. path)
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

---------------------------------------------------------------------------
-- Stub client
---------------------------------------------------------------------------
local frames, timers = {}, {}
local methods = {}
local function Region(kind, parent)
    local region = { kind = kind, parent = parent, events = {}, units = {}, scripts = {}, shown = true, points = {} }
    return setmetatable(region, { __index = methods })
end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:RegisterEvent(event)
    assert(event ~= "UNIT_AURA", "UNIT_AURA registered for every unit")
    self.events[event] = true
end
function methods:RegisterUnitEvent(event, ...)
    local units = { ... }
    assert(#units >= 1 and #units <= 2, "unit event registration needs one or two tokens")
    self.events[event] = true
    self.units[event] = units
    return true
end
function methods:UnregisterEvent(event) self.events[event] = nil; self.units[event] = nil end
function methods:IsEventRegistered(event) return self.events[event] == true end
function methods:CreateTexture(_, layer) local t = Region("Texture", self); t.layer = layer; return t end
function methods:SetTexture(texture) self.texture = texture end
function methods:SetTexCoord() end
function methods:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:EnableMouse(enabled) self.mouse = enabled end
function methods:ClearAllPoints() self.points = {} end
function methods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function methods:SetSize(w, h) self.width, self.height = w, h; self.sizeWrites = (self.sizeWrites or 0) + 1 end
function methods:SetBlendMode(mode) self.blend = mode end
function methods:SetVertexColor(r, g, b) self.vertex = { r, g, b } end
function methods:CreateAnimationGroup()
    local group = { animations = {}, playing = false, plays = 0 }
    function group:SetLooping(mode) self.looping = mode end
    function group:CreateAnimation(kind)
        local animation = { kind = kind }
        function animation:SetFromAlpha(value) self.from = value end
        function animation:SetToAlpha(value) self.to = value end
        function animation:SetDuration(value) self.duration = value end
        self.animations[#self.animations + 1] = animation
        return animation
    end
    function group:Play() self.playing = true; self.plays = self.plays + 1 end
    function group:Stop() self.playing = false end
    return group
end
function methods:SetFrameLevel(level) self.level = level; self.levelWrites = (self.levelWrites or 0) + 1 end
function methods:GetFrameLevel() return self.level or 1 end

local env = setmetatable({}, { __index = _G })
env._G = env
env.CreateFrame = function(kind, _, parent)
    local frame = Region(kind, parent)
    frames[#frames + 1] = frame
    return frame
end
env.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
local function RunTimers(maxDelay)
    for _ = 1, 20 do
        local due, rest = {}, {}
        for _, timer in ipairs(timers) do
            if timer.delay <= (maxDelay or 0) then due[#due + 1] = timer else rest[#rest + 1] = timer end
        end
        timers = rest
        if #due == 0 then return end
        for _, timer in ipairs(due) do timer.fn() end
    end
end
env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local SECRET = setmetatable({}, {
    __index = function() error("indexed a secret value", 2) end,
    __eq = function() error("compared a secret value", 2) end,
    __lt = function() error("compared a secret value", 2) end,
    __concat = function() error("concatenated a secret value", 2) end,
})
env.issecretvalue = function(value) return rawequal(value, SECRET) end

local inRaid, raidSize, partySize = false, 0, 4
local classes = { player = "PRIEST", party1 = "DRUID", party2 = "MAGE", party3 = "WARRIOR", party4 = "PALADIN" }
local guids = { player = "P-1", party1 = "P-2", party2 = "P-3", party3 = "P-4", party4 = "P-5" }
local visible, roles = {}, { party3 = "TANK" }
local auras = {}
local reads = 0
env.IsInRaid = function() return inRaid end
env.GetNumGroupMembers = function() return inRaid and raidSize or partySize + 1 end
env.GetNumSubgroupMembers = function() return partySize end
env.UnitClass = function(unit) return "Class", classes[unit] end
env.UnitGUID = function(unit) return guids[unit] end
local connected = {}
env.UnitIsConnected = function(unit) return connected[unit] ~= false end
env.UnitIsVisible = function(unit) return visible[unit] ~= false end
env.InCombatLockdown = function() return false end
env.C_UnitAuras = { GetUnitAuras = function(unit, filter)
    assert(filter == "HELPFUL", "buff coverage read a non-helpful filter")
    reads = reads + 1
    -- The client has no aura data for a member it cannot see.
    if visible[unit] == false then return {} end
    return auras[unit] or {}
end }
env.C_Spell = { GetSpellTexture = function(id) return "tex" .. id end }
local secrecy = {}
env.Enum = {
    SecrecyLevel = { NeverSecret = 0, AlwaysSecret = 1, ContextuallySecret = 2 },
    AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
    AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
}
env.C_Secrets = { GetSpellAuraSecrecy = function(id) return secrecy[id] or 2 end }
env.C_RestrictedActions = { IsAddOnRestrictionActive = function() return false end }

local confs = {
    party = { buffCoverageEnabled = true, buffCoverageWild = true, buffCoverageThorns = false, buffCoverageIntellect = true,
        buffCoverageBlessings = true, buffCoverageStamina = true, buffCoverageSpirit = false, buffCoverageCombat = false,
        buffCoverageSize = 14, buffCoverageAnchor = "BOTTOM", buffCoverageX = 0, buffCoverageY = 2, buffCoverageLayer = 6 },
    raid = { buffCoverageEnabled = false },
    mythicraid = { buffCoverageEnabled = false },
}
local groupFrames = {}
local GF = {}
function GF.GetConf(kind) return confs[kind] end
function GF.GetUnitGroupRole(unit) return roles[unit] or "DAMAGER" end
function GF.ForEachFrame(fn) for _, frame in ipairs(groupFrames) do fn(frame, frame.MSUFUnitKey, frame._msufGFKind) end end
function GF.ForEachFrameForUnit(unit, fn) for _, frame in ipairs(groupFrames) do if frame.MSUFUnitKey == unit then fn(frame, unit) end end end
function GF.RegisterRuntimeObserver(_, fn) GF.observer = fn end
function GF.RegisterFrameRegistryObserver(_, fn) GF.registry = fn end
local function GroupFrame(unit, kind)
    local frame = Region("Button")
    frame.MSUFUnitKey, frame._msufGFKind = unit, kind or "party"
    groupFrames[#groupFrames + 1] = frame
    return frame
end

local function Load(client)
    local chunk = assert(loadfile(root .. "/" .. MODULE))
    setfenv(chunk, env)
    local namespace = { Client = client, GF = GF, UF = { Layers = { StatusLevel = function(_, layer, fallback)
        return 100 + (layer or fallback) * 32 + 8 end } } }
    chunk("MidnightSimpleUnitFrames", namespace)
    return namespace
end

---------------------------------------------------------------------------
-- 1. Outside Forever the file does nothing
---------------------------------------------------------------------------
Load({ IsForever = false })
assert(#frames == 0 and GF.observer == nil and GF.RenderBuffCoveragePreview == nil, "buff coverage ran outside WoW Forever")

---------------------------------------------------------------------------
-- 2. Data: ordered, unique, every key backed by a DB default
---------------------------------------------------------------------------
Load({ IsForever = true, SupportsEvent = function() return true end })
local dispatcher = frames[1]
assert(dispatcher.events.ADDON_RESTRICTION_STATE_CHANGED and dispatcher.events.GROUP_ROSTER_UPDATE
    and not dispatcher.events.PLAYER_REGEN_DISABLED, "restriction events not used where the client has them")
local buffs = assert(GF.BUFF_COVERAGE_BUFFS, "buff list not published")
local defaults = Read("MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua")
local owner, classOrder, lastClass = {}, {}, nil
for index, buff in ipairs(buffs) do
    if buff.class ~= lastClass then classOrder[#classOrder + 1] = buff.class; lastClass = buff.class end
    for i, id in ipairs(buff.ids) do
        assert(i == 1 or id > buff.ids[i - 1], buff.key .. " IDs are not strictly ascending at " .. id)
        assert(owner[id] == nil, "spell " .. id .. " counted by two buffs")
        owner[id] = index
    end
    assert(defaults:find("\n    " .. buff.setting .. " = ", 1, true), "no DB default for " .. buff.setting)
end
assert(table.concat(classOrder, ",") == "DRUID,MAGE,PALADIN,PRIEST", "buffs are not grouped by casting class")
for _, key in ipairs({ "buffCoverageEnabled", "buffCoverageCombat", "buffCoverageSize", "buffCoverageAnchor",
    "buffCoverageX", "buffCoverageY", "buffCoverageLayer", "buffCoverageThornsTankOnly", "buffCoverageGlow" }) do
    assert(defaults:find("\n    " .. key .. " = ", 1, true), "no DB default for " .. key)
end
assert(not defaults:find("missingBuffs", 1, true), "old missing-buff keys survive in the defaults")
local mainline = Read("MidnightSimpleUnitFrames/UnitFrames/Embeds/MSUF_UFCore/MSUF_UFCore_Group.xml")
assert(mainline:find('Game\\Forever\\GroupFrames\\MSUF_GroupFrames_BuffCoverage.lua', 1, true), "Mainline manifest does not load the module")
for _, flavor in ipairs({ "Vanilla", "TBC", "Mists" }) do
    local manifest = Read("MidnightSimpleUnitFrames/Game/" .. flavor .. "/UnitFrames/GroupFrames.xml")
    assert(not manifest:find("BuffCoverage", 1, true) and not manifest:find("MissingBuffs", 1, true),
        flavor .. " manifest loads a Forever-only module")
end

local function IconsOf(frame)
    local holder = frame._msufBuffCoverage
    local out = {}
    if not (holder and holder.shown) then return out end
    for slot, icon in ipairs(holder.icons) do
        if icon.shown then out[#out + 1] = buffs[icon._msufBuff].key; assert(slot == #out, "icon gap") end
    end
    return out
end
local function Keys(frame) return table.concat(IconsOf(frame), ",") end
local function Aura(id, instance) return { spellId = id, auraInstanceID = instance } end
local function Shards()
    local out = {}
    for i = 2, #frames do
        local frame = frames[i]
        if frame.units.UNIT_AURA then for _, unit in ipairs(frame.units.UNIT_AURA) do out[#out + 1] = unit end end
    end
    table.sort(out)
    return table.concat(out, ",")
end
local function Fire(event, ...) dispatcher.scripts.OnEvent(dispatcher, event, ...) end
local function ShardFor(unit)
    for i = 2, #frames do
        local units = frames[i].units.UNIT_AURA
        if units and (units[1] == unit or units[2] == unit) then return frames[i] end
    end
end
local function UnitAura(unit, info)
    local shard = ShardFor(unit) or frames[2]
    shard.scripts.OnEvent(shard, "UNIT_AURA", unit, info)
end

---------------------------------------------------------------------------
-- 3. Party: one read per member, icons only for real gaps
---------------------------------------------------------------------------
local f = {}
for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do f[unit] = GroupFrame(unit) end
local duplicate = GroupFrame("party1")
auras.player = { Aura(10938, 1), Aura(9885, 2), Aura(10157, 3), Aura(25291, 4) }
auras.party1 = {}
auras.party2 = { Aura(1243, 11), Aura(21850, 12), Aura(23028, 13), Aura(20217, 14) }
auras.party3 = { Aura(10938, 21), Aura(9885, 22), Aura(25290, 23) }
auras.party4 = { Aura(21564, 31), Aura(5232, 32), Aura(1461, 33) }
Fire("PLAYER_ENTERING_WORLD")
assert(reads == 0, "aura reads ran before the coalesced pass")
RunTimers(0)
assert(reads == 5, "each member is read exactly once, got " .. reads)
assert(Shards() == "party1,party2,party3,party4,player", "unit-filtered listeners missing: " .. Shards())
assert(Keys(f.player) == "" and Keys(f.party2) == "" and Keys(f.party3) == "", "covered members show icons")

---------------------------------------------------------------------------
-- PROBE D1: a full-update UNIT_AURA and a roster refresh in the same frame
---------------------------------------------------------------------------
print("D1 before: party2 icons = [" .. Keys(f.party2) .. "] (has Fortitude 1243)")
auras.party2 = { Aura(21850, 12), Aura(23028, 13), Aura(20217, 14) } -- Fortitude gone
local before = reads
UnitAura("party2", { isFullUpdate = true })   -- payload cannot be applied: party2 queued for a read
Fire("GROUP_ROSTER_UPDATE")                    -- e.g. a member zones in during the same frame
RunTimers(0)
print("D1 after : party2 icons = [" .. Keys(f.party2) .. "], reads of party2 in that pass = " .. (reads - before))
assert(Keys(f.party2) == "Stamina", "full pending aura read dropped")
assert(reads - before == 1, "coalesced read budget exceeded")
print("D1 expected: [Stamina] (Fortitude is missing and a Priest is in the group)")
UnitAura("party2", { isFullUpdate = false, removedAuraInstanceIDs = { 999 } })
RunTimers(0)
print("D1 later unrelated incremental update: party2 icons = [" .. Keys(f.party2) .. "]")

---------------------------------------------------------------------------
-- PROBE D2: a read member goes offline
---------------------------------------------------------------------------
print("D2 before: party1 icons = [" .. Keys(f.party1) .. "]")
connected.party1 = false
Fire("GROUP_ROSTER_UPDATE")
RunTimers(0)
print("D2 after disconnect + roster pass: party1 icons = [" .. Keys(f.party1) .. "]")
assert(Keys(f.party1) == "", "offline icons retained")
print("D2 expected: [] (file header: an offline member is unknown, and an unknown member never shows an icon)")
