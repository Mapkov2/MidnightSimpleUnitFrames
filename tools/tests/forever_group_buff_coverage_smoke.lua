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
env.UnitIsConnected = function() return true end
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
assert(Keys(f.party1) == "Wild,Intellect,Blessings,Stamina", "druid gaps wrong: " .. Keys(f.party1))
assert(Keys(duplicate) == Keys(f.party1), "a duplicate frame missed the shared result")
assert(Keys(f.party4) == "Blessings", "paladin without a blessing: " .. Keys(f.party4))
local holder = f.party1._msufBuffCoverage
assert(holder.level == 100 + 6 * 32 + 8 and holder.points[1][1] == "BOTTOM" and holder.points[1][5] == 2,
    "icons are not on the status layer at the configured point")
assert(holder.width == 4 * 14 + 3 * 2 and holder.height == 14, "row geometry wrong")
assert(holder.icons[1].texture == "tex1126" and holder.icons[4].texture == "tex1243", "icon textures wrong")
assert(holder.icons[1].glow == nil, "a glow ring was built while Glow missing icons is off")

---------------------------------------------------------------------------
-- 3b. Thorns only on tanks (unset = on) and Glow missing icons
---------------------------------------------------------------------------
local function Refresh() GF.observer("refreshVisuals"); RunTimers(0) end
confs.party.buffCoverageThorns = true
Refresh()
assert(Keys(f.party3) == "Thorns", "the tank without Thorns: " .. Keys(f.party3))
assert(Keys(f.party2) == "" and Keys(f.player) == "", "Thorns flagged on a non-tank while Thorns only on tanks is unset")
confs.party.buffCoverageThornsTankOnly = false
Refresh()
assert(Keys(f.party2) == "Thorns" and Keys(f.player) == "Thorns" and Keys(f.party3) == "Thorns",
    "Thorns only on tanks off must check every member: " .. Keys(f.party2))
confs.party.buffCoverageThornsTankOnly = true
Refresh()
assert(Keys(f.party2) == "" and Keys(f.party3) == "Thorns", "Thorns only on tanks on did not limit Thorns to the tank")
confs.party.buffCoverageThorns = false
Refresh()

confs.party.buffCoverageGlow = true
Refresh()
local ring = holder.icons[1].glow
assert(ring and ring.shown and ring.pulse.playing and ring.pulse.plays == 1, "Glow missing icons did not pulse a ring")
assert(ring.texture == "Interface\\Buttons\\UI-ActionButton-Border" and ring.blend == "ADD" and ring.layer == "OVERLAY",
    "the ring is not the additive action-button border")
assert(ring.width == 14 * 1.75 and ring.points[1][1] == "CENTER" and ring.points[1][2] == holder.icons[1],
    "the ring is not centred around its icon")
local pulse = ring.pulse.animations[1]
assert(ring.pulse.looping == "BOUNCE" and pulse.kind == "Alpha" and pulse.from == 0.25 and pulse.to == 1 and pulse.duration == 0.6,
    "the ring does not pulse")
for slot = 1, 4 do assert(holder.icons[slot].glow and holder.icons[slot].glow.shown, "icon " .. slot .. " has no ring") end
local ringWrites = ring.sizeWrites
Refresh()
assert(ring.sizeWrites == ringWrites and ring.pulse.plays == 1, "an unchanged repaint rewrote or restarted the ring")
GF.HideBuffCoveragePreview(f.party1)
assert(not ring.shown and not ring.pulse.playing, "a hidden row kept its rings pulsing")
Refresh()
assert(ring.shown and ring.pulse.playing, "the ring did not come back with its row")
UnitAura("party1", { isFullUpdate = false, addedAuras = { Aura(1243, 61) } })
RunTimers(0)
assert(Keys(f.party1) == "Wild,Intellect,Blessings" and not holder.icons[4].glow.shown and not holder.icons[4].glow.pulse.playing,
    "a covered buff kept its ring")
UnitAura("party1", { isFullUpdate = false, removedAuraInstanceIDs = { 61 } })
RunTimers(0)
assert(holder.icons[4].glow.shown, "a buff missing again lost its ring")
confs.party.buffCoverageGlow = false
Refresh()
for slot = 1, 4 do
    local glow = holder.icons[slot].glow
    assert(not glow.shown and not glow.pulse.playing, "Glow missing icons off left ring " .. slot)
end
confs.party.buffCoverageGlow = nil

---------------------------------------------------------------------------
-- 4. Incremental payloads
---------------------------------------------------------------------------
reads = 0
local levelWrites = holder.levelWrites
UnitAura("party1", { isFullUpdate = false, addedAuras = { Aura(1243, 41) } })
RunTimers(0)
assert(reads == 0 and Keys(f.party1) == "Wild,Intellect,Blessings", "added rank 1 Fortitude not applied without a read")
UnitAura("party1", { isFullUpdate = false, addedAuras = { Aura(774, 42) }, updatedAuraInstanceIDs = { 41 } })
RunTimers(0)
assert(reads == 0, "unrelated HoT or update caused a read")
UnitAura("party1", { isFullUpdate = false, removedAuraInstanceIDs = { 41, 42 } })
RunTimers(0)
assert(reads == 0 and Keys(f.party1) == "Wild,Intellect,Blessings,Stamina", "removal not applied")
assert(holder.levelWrites == levelWrites, "a repaint rewrote an unchanged frame level")
UnitAura("party1", { isFullUpdate = true })
RunTimers(0)
assert(reads == 1, "a full update must read once, got " .. reads)
reads = 0
UnitAura("nameplate3", { isFullUpdate = true })
RunTimers(0)
assert(reads == 0, "a non-group unit reached the reader")
local before = collectgarbage("count")
local add, remove = { isFullUpdate = false, addedAuras = { Aura(1243, 77) } }, { isFullUpdate = false, removedAuraInstanceIDs = { 77 } }
for _ = 1, 2000 do UnitAura("party1", add); UnitAura("party1", remove) end
RunTimers(0)
collectgarbage("collect")
assert(collectgarbage("count") - before < 8, "incremental updates allocate")
assert(reads == 0, "incremental churn read auras")

---------------------------------------------------------------------------
-- 5. Unreachable members are unknown, never missing
---------------------------------------------------------------------------
visible.party2 = false
UnitAura("party2", { isFullUpdate = true })
RunTimers(0)
assert(Keys(f.party2) == "", "an out-of-sight member was reported as missing buffs")
visible.party2 = nil

---------------------------------------------------------------------------
-- 6. Restriction: freeze, no reads, no listeners, one pass afterwards
---------------------------------------------------------------------------
reads = 0
Fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 1)
assert(Shards() == "", "listeners stayed on although no buff is readable in combat")
assert(Keys(f.party1) == "", "icons stayed during combat with Keep showing off")
UnitAura("party1", SECRET)
RunTimers(1)
assert(reads == 0, "restricted UNIT_AURA read auras")
confs.party.buffCoverageCombat = true
GF.observer("refreshVisuals")
RunTimers(0)
assert(reads == 0 and Keys(f.party1) == "Wild,Intellect,Blessings,Stamina", "frozen state not shown during combat")
Fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
RunTimers(0)
assert(reads == 5 and Shards() == "party1,party2,party3,party4,player", "restriction end did not read every member once")
confs.party.buffCoverageCombat = false

-- The reviewer's probe: a fully buffed 40-player raid, every combat UNIT_AURA
-- carries a secret payload. Nothing may be read and no icon may appear.
inRaid, raidSize = true, 40
confs.raid = {}
for k, v in pairs(confs.party) do confs.raid[k] = v end
confs.raid.buffCoverageCombat = true
local raidFrames = {}
local fullyBuffed = { Aura(10938, 1), Aura(9885, 2), Aura(10157, 3), Aura(25291, 4), Aura(467, 5) }
local raidClasses = { "PRIEST", "DRUID", "MAGE", "PALADIN", "WARRIOR" }
for i = 1, 40 do
    local unit = "raid" .. i
    classes[unit], guids[unit], auras[unit] = raidClasses[(i % 5) + 1], "R-" .. i, fullyBuffed
    raidFrames[i] = GroupFrame(unit, "raid")
end
Fire("GROUP_ROSTER_UPDATE")
RunTimers(0)
local raidShards = Shards()
assert(select(2, raidShards:gsub("raid", "")) == 40, "raid listeners incomplete")
reads = 0
Fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 1)
for i = 1, 40 do UnitAura("raid" .. i, SECRET) end
RunTimers(1)
local shown = 0
for i = 1, 40 do shown = shown + #IconsOf(raidFrames[i]) end
assert(reads == 0, "40 secret combat events read auras " .. reads .. " times")
assert(shown == 0, shown .. " false missing icons in combat")
Fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
RunTimers(0)
assert(reads == 40, "restriction end did not read the raid once, got " .. reads)
confs.raid.buffCoverageEnabled = false

---------------------------------------------------------------------------
-- 7. A never-secret buff stays decidable while restricted
---------------------------------------------------------------------------
inRaid, raidSize = false, 0
for _, buff in ipairs(buffs) do
    if buff.key == "Stamina" then for _, id in ipairs(buff.ids) do secrecy[id] = 0 end end
end
-- Secrecy is classified once per session; reload the module for this case.
frames, timers, groupFrames = {}, {}, {}
Load({ IsForever = true, SupportsEvent = function() return true end })
dispatcher = frames[1]
for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do f[unit] = GroupFrame(unit) end
confs.party.buffCoverageCombat = true
Fire("PLAYER_ENTERING_WORLD")
RunTimers(0)
assert(Keys(f.party1) == "Wild,Intellect,Blessings,Stamina", "baseline before restriction")
Fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 1)
assert(Shards() ~= "", "listeners dropped although a never-secret buff can be read")
reads = 0
auras.party1 = { SECRET, Aura(21562, 51), SECRET }
UnitAura("party1", SECRET)
UnitAura("party1", SECRET)
assert(reads == 0, "restricted reads are not throttled")
RunTimers(1)
assert(reads == 1, "restricted burst must read once, got " .. reads)
assert(Keys(f.party1) == "Wild,Intellect,Blessings", "never-secret Fortitude arrival missed in combat")
auras.party3 = { SECRET }
UnitAura("party3", SECRET)
RunTimers(1)
assert(Keys(f.party3) == "Stamina", "never-secret Fortitude loss missed; contextual buffs must stay frozen: " .. Keys(f.party3))
Fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
auras.party1, auras.party3 = {}, { Aura(10938, 21), Aura(9885, 22), Aura(25290, 23) }
RunTimers(0)

---------------------------------------------------------------------------
-- 8. Roster swap, disable, samples
---------------------------------------------------------------------------
reads = 0
guids.party2 = "P-9"
Fire("GROUP_ROSTER_UPDATE")
RunTimers(0)
assert(reads == 1, "a roster change must read only the member whose token changed, got " .. reads)
local preview = GroupFrame("player")
preview._msufGFIsPreviewFrame = true
GF.registry("track", preview, nil, "player")
assert(Keys(preview) == "Wild,Intellect,Blessings,Stamina", "sample frame did not show every enabled buff")
reads = 0
confs.party.buffCoverageEnabled = false
GF.observer("refreshVisuals")
RunTimers(0)
assert(Shards() == "" and Keys(f.party1) == "" and Keys(preview) == "", "disable left listeners or icons")
assert(reads == 0, "disabling read auras")
local mock = Region("Frame")
GF.RenderBuffCoveragePreview(mock, { buffCoverageEnabled = true, buffCoverageWild = true, buffCoverageStamina = true,
    buffCoverageSize = 20, buffCoverageAnchor = "TOPRIGHT", buffCoverageX = -3, buffCoverageY = -4 }, 0.5)
assert(Keys(mock) == "Wild,Stamina" and mock._msufBuffCoverage.width == 10 * 2 + 1 and mock._msufBuffCoverage.points[1][1] == "TOPRIGHT"
    and mock._msufBuffCoverage.points[1][4] == -1.5, "menu sample geometry did not scale")
-- Icon size keeps the missing-buff section's 8-48 px range.
GF.RenderBuffCoveragePreview(mock, { buffCoverageEnabled = true, buffCoverageWild = true, buffCoverageSize = 48 }, 1)
assert(mock._msufBuffCoverage.height == 48, "a 48 px icon was clamped: " .. tostring(mock._msufBuffCoverage.height))
GF.RenderBuffCoveragePreview(mock, { buffCoverageEnabled = true, buffCoverageWild = true, buffCoverageSize = 90 }, 1)
assert(mock._msufBuffCoverage.height == 48, "the icon size is not capped at 48 px")
local page = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupLayoutAdditional.lua")
assert(page:find('"Icon size", 8, 48, 1, width, "buffCoverageSize"', 1, true)
    and page:find('"Horizontal offset", -200, 200, 1, width, "buffCoverageX"', 1, true)
    and page:find('"Vertical offset", -200, 200, 1, width, "buffCoverageY"', 1, true),
    "the buff coverage size or offset sliders lost their range")
GF.HideBuffCoveragePreview(mock)
assert(Keys(mock) == "", "sample hide failed")

print("forever_group_buff_coverage_smoke: PASS")
