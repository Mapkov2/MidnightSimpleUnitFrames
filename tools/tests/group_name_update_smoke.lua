-- group_name_update_smoke.lua <repoRoot> [flavor]
-- Real group compiler, providers, event router and text sinks. Native unit-event
-- filtering follows each frame's observed RegisterUnitEvent token recipe;
-- the shared widgets do not emulate that filtering or fire visibility scripts.
-- No candidate provider, synthetic name painter or roster recovery is installed.

local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local World = dofile(root .. "/tools/tests/client_world.lua")
local world = World.New(root, flavor)
local env = world.env
env.type, env.issecretvalue = type, issecretvalue
local names = { player = "Player", raid1 = "Unknown", raid2 = "Other", raid3 = "Third" }
local exists = { raid1 = true, raid2 = true, raid3 = true }
local guids = { raid1 = "Player-first", raid2 = "Player-second", raid3 = "Player-third" }
local reads = { raid1 = 0, raid2 = 0, raid3 = 0 }
local nameReads, existsReads, rosterReads, guidReads, layoutWrites, timerSchedules = 0, 0, 0, 0, 0, 0
local measured = false
env.IsInGroup = function() return true end
env.IsInRaid = function() return true end
env.GetNumGroupMembers = function() rosterReads = rosterReads + 1
return 3 end
env.GetNumSubgroupMembers = function() rosterReads = rosterReads + 1
return 0 end
env.GetRaidRosterInfo = function() rosterReads = rosterReads + 1
return "RosterFallback" end
env.UnitExists = function(unit) existsReads = existsReads + 1
return exists[unit] == true end
env.UnitIsConnected = function() return true end
env.UnitIsPlayer = function() return true end
env.UnitIsDeadOrGhost = function() return false end
env.UnitGUID = function(unit) guidReads = guidReads + 1
return guids[unit] end
env.UnitName = function(unit)
    nameReads = nameReads + 1
    reads[unit] = (reads[unit] or 0) + 1
    return names[unit]
end
env.UnitClass = function() return "Warrior", "WARRIOR", 1 end
env.UnitHealth = function() return 100 end
env.UnitHealthMax = function() return 100 end
env.UnitHealthPercent = function() return 100 end
env.UnitPower = function() return 50 end
env.UnitPowerMax = function() return 100 end
env.UnitPowerPercent = function() return 50 end
env.UnitPowerType = function() return 0, "MANA" end
local methods = world.widgets.Methods
for _, key in ipairs({ "SetPoint", "ClearAllPoints", "SetSize", "SetWidth", "SetHeight", "SetParent" }) do
    local native = methods[key]
    methods[key] = function(self, ...)
        if measured then layoutWrites = layoutWrites + 1 end
        return native(self, ...)
    end
end
for _, key in ipairs({ "After", "NewTimer", "NewTicker" }) do
    local native = env.C_Timer[key]
    if native then
        env.C_Timer[key] = function(...)
            if measured then timerSchedules = timerSchedules + 1 end
            return native(...)
        end
    end
end
world:Boot()
assert(not world:FirstFailure(), flavor .. ": real source graph failed to load")
env.MSUF_EnsureDB(true)
env.MSUF_ActiveProfile = "Default"
env.MSUF_GlobalDB = { profiles = { Default = env.MSUF_DB }, char = {}, global = {} }
local GF, UF, Text = world.core.GF, world.core.UF, world.core.UFText
GF.EnsureDB()
for _, kind in ipairs({ "raid", "priority" }) do
    local conf = GF.GetConf(kind)
    conf.enabled, conf.showName, conf.hideNameOnDeadOffline = true, true, false
    GF.InvalidateCompiledSpecs(kind)
end

local frames = {}
local function Frame(unit, priority)
    local frame = env.CreateFrame("Button", nil, env.UIParent)
    frame:SetSize(120, 40)
    frame._nameUnitEvents, frame._nameUnitlessEvents, frame._namePaints = {}, {}, 0
    local nativeUnit, nativeEvent = frame.RegisterUnitEvent, frame.RegisterEvent
    frame.RegisterUnitEvent = function(self, event, ...)
        self._nameUnitEvents[event] = { ... }
        self._nameUnitlessEvents[event] = nil
        return nativeUnit(self, event, ...)
    end
    frame.RegisterEvent = function(self, event)
        self._nameUnitlessEvents[event] = true
        self._nameUnitEvents[event] = nil
        return nativeEvent(self, event)
    end
    frame._msufGFPriorityFrame = priority or nil
    UF.AttachFrame(frame, { scope = "group" })
    UF.ApplySpec(frame, GF.CompileSpec(priority and "priority" or "raid", frame, unit), nil, GF.GROUP_APPLY_MASK)
    assert(frame._msufActiveElements.NameText == true, "group NameText must be enabled")
    assert(UF.RefreshGroupFrameState(frame, "MSUF_GF_ONSHOW"), "group lifecycle seed must run")
    local nativeText = frame.nameText.SetText
    frame.nameText.SetText = function(self, text)
        frame._namePaints = frame._namePaints + 1
        return nativeText(self, text)
    end
    frames[#frames + 1] = frame
    return frame
end
local first, other, duplicate = Frame("raid1"), Frame("raid2"), Frame("raid1", true)
local function ResetCounters()
    nameReads, existsReads, rosterReads, guidReads, layoutWrites, timerSchedules = 0, 0, 0, 0, 0, 0
    for unit in pairs(reads) do reads[unit] = 0 end
    for _, frame in ipairs(frames) do frame._namePaints = 0 end
end
local function Name(frame) return frame.nameText:GetText() end
local function Event(event, unit)
    for _, frame in ipairs(frames) do
        local tokens = frame._nameUnitEvents[event]
        local accepts = frame._nameUnitlessEvents[event] == true
        if tokens then
            for index = 1, #tokens do if tokens[index] == unit then accepts = true end end
        end
        if accepts and frame:IsEventRegistered(event) then
            local handler = assert(frame:GetScript("OnEvent"), "missing real event handler")
            handler(frame, event, unit)
        end
    end
end
local function ScopedNameEvent(expectedReads)
    ResetCounters()
    measured = true
    Event("UNIT_NAME_UPDATE", "raid1")
    measured = false
    assert(nameReads == expectedReads and reads.raid1 == expectedReads and reads.raid2 == 0 and reads.raid3 == 0,
        "name event must read only its registered member, once per visible view: expected " .. expectedReads .. ", got " .. nameReads)
    assert(other._namePaints == 0, "name event repainted another raid member")
    assert(rosterReads == 0 and guidReads == 0, "name event scanned roster or read GUID identity")
    assert(layoutWrites == 0 and timerSchedules == 0, "name event rebuilt geometry or scheduled delayed work")
end

-- This first behavior assertion is red on the original real provider, which
-- already registered UNIT_NAME_UPDATE for other elements but never read names.
assert(Name(first) == "Unknown" and Name(duplicate) == "Unknown", "initial unknown names not seeded")
names.raid1 = "Arrived"
ScopedNameEvent(2)
assert(Name(first) == "Arrived" and Name(duplicate) == "Arrived", "late Unknown name did not recover")
assert(Name(other) == "Other", "late name replaced an unrelated member")
for _, frame in ipairs(frames) do
    local route = assert(frame._msufElementEventRoutes.NameText, "NameText has no compiled owner")
    assert(#route.events == 1 and route.events[1] == "UNIT_NAME_UPDATE", "group name owner subscribed to value ticks")
    local tokens = assert(frame._nameUnitEvents.UNIT_NAME_UPDATE, "name event must use native unit registration")
    assert(#tokens == 1 and tokens[1] == frame.MSUFUnitKey, "name event registered the wrong unit token")
end

-- Other-instance members can have neither a name nor a locally existing unit
-- when built. A later readable name must work without waiting for UnitExists.
names.raid3, exists.raid3 = nil, false
local remote = Frame("raid3")
assert(Name(remote) == nil or Name(remote) == "", "missing initial name became a guessed identity")
names.raid3 = "Remote"
ResetCounters()
measured = true
Event("UNIT_NAME_UPDATE", "raid3")
measured = false
assert(Name(remote) == "Remote" and nameReads == 1 and reads.raid3 == 1,
    "nil name outside this instance did not recover with one name read")
assert(reads.raid1 == 0 and reads.raid2 == 0 and other._namePaints == 0, "remote event scanned other members")
assert(existsReads <= 1 and rosterReads == 0 and layoutWrites == 0 and timerSchedules == 0,
    string.format("remote name presence/roster/layout/timer work: %d/%d/%d/%d", existsReads, rosterReads, layoutWrites, timerSchedules))

-- A known member moving away remains name-event-driven, including combat.
exists.raid1, names.raid1 = false, "Moved"
world.widgets:SetCombat(true)
ScopedNameEvent(2)
assert(Name(first) == "Moved" and Name(duplicate) == "Moved", "name recovery was deferred in combat/out of instance")
world.widgets:SetCombat(false)

-- Reusing the same raid token for another GUID must replace its old text.
guids.raid1, names.raid1 = "Player-replacement", "Unknown"
ScopedNameEvent(2)
assert(Name(first) == "Unknown", "same-token occupant retained the previous name")
names.raid1 = "NewMember"
ScopedNameEvent(2)
assert(Name(first) == "NewMember", "replacement occupant's late name did not recover")
-- A frame changing tokens must stop consuming the old registration.
UF.OnUnitChanged(first, "raid1", "raid3")
assert(first.MSUFUnitKey == "raid3", "real unit rebind did not change token")
assert(first._nameUnitEvents.UNIT_NAME_UPDATE[1] == "raid3", "unit rebind retained old name registration")
names.raid1 = "PriorityOnly"
ScopedNameEvent(1)
assert(Name(first) == "Remote" and Name(duplicate) == "PriorityOnly", "rebound raid frame consumed its old token")

-- A hidden child drops native registrations; OnShow restores the recipe and
-- catches up once. Shared widgets need explicit dispatch of the real scripts.
remote:Hide()
assert(remote:GetScript("OnHide"), "real hidden lifecycle hook missing")(remote)
assert(remote._msufCoreEventsSuspended == true and not remote:IsEventRegistered("UNIT_NAME_UPDATE"),
    "hidden child retained name subscriptions")
names.raid3 = "WhileHidden"
ResetCounters()
Event("UNIT_NAME_UPDATE", "raid3")
assert(nameReads == 1 and remote._namePaints == 0 and Name(remote) == "Remote",
    "hidden child received a name event")
remote:Show()
assert(remote:GetScript("OnShow"), "real reshow lifecycle hook missing")(remote)
assert(remote:IsEventRegistered("UNIT_NAME_UPDATE") and Name(remote) == "WhileHidden", "reshow did not restore/catch up name")
names.raid3 = "AfterReshow"
ResetCounters()
Event("UNIT_NAME_UPDATE", "raid3")
assert(Name(remote) == "AfterReshow" and nameReads == 2, "restored remote subscription failed")

-- Health ticks must retain their existing zero-name-read path.
ResetCounters()
for _ = 1, 100 do Event("UNIT_HEALTH", "raid1")
Event("UNIT_HEALTH", "raid3") end
assert(nameReads == 0, "health ticks acquired name reads")

-- Secret names go straight to the native text sink; guard-order watches use
-- the real resolver/runtime/helper paths, not a permissive table-only check.
local runtime = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/"
local secret = Secrets.New("string")
names.raid1 = secret
local stop = Secrets.Watch({ runtime .. "MSUF_UF_Text_Runtime.lua", runtime .. "MSUF_UF_Text_Common.lua",
    runtime .. "MSUF_UF_Text_Format.lua", runtime .. "MSUF_UF_Text_SlotCompile.lua", runtime .. "MSUF_UF_Text_Name.lua",
    runtime .. "MSUF_UF_Text_Drain.lua", root .. "/MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Apply.lua" }, { strict = true })
ScopedNameEvent(1)
local violations = stop()
assert(#violations == 0, table.concat(violations, "\n"))
assert(rawequal(Name(duplicate), secret), "secret name did not reach the native text sink unchanged")
names.raid1 = "Budget"
ScopedNameEvent(1)

-- Bounded repeatable hot path: 100 same-member name notifications with the
-- existing text cache warm. Two measures keep the smaller allocation reading
-- so Lua 5.1 string-table regrowth cannot dominate the 32-bit path budget.
local function Measure()
    local ticks = 0
    local function Tick() ticks = ticks + 1 end
    ResetCounters()
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    measured = true
    debug.sethook(Tick, "", 1000)
    for _ = 1, 100 do Event("UNIT_NAME_UPDATE", "raid1") end
    debug.sethook()
    measured = false
    local kb = collectgarbage("count") - before
    collectgarbage("restart")
    assert(nameReads == 100 and existsReads <= 100 and rosterReads == 0 and guidReads == 0,
        "repeat name events exceed native read budget")
    assert(layoutWrites == 0 and timerSchedules == 0, "repeat name events rebuilt layout or scheduled work")
    assert(duplicate._namePaints == 0, "warm cached text was repainted")
    return ticks, kb
end
local ticks, kb = Measure()
local ticks2, kb2 = Measure()
ticks, kb = math.max(ticks, ticks2), math.min(kb, kb2)
-- Lua 5.1 x86 measured 2026-10-13: 107k on Mainline/Classic and 113k on
-- Forever; 2% rounded headroom. Minimum repeat allocation was zero on all five.
local instructionLimit = flavor == "Forever" and 116 or 110
assert(ticks <= instructionLimit, "100 targeted names exceed Lua instruction budget: " .. ticks)
assert(kb <= 0.1, "100 targeted names exceed 0.1KB allocation budget: " .. kb)

-- Native work measured separately, so hook introspection allocations cannot
-- enter the VM/allocation budget. Invoke the same actual registered handler
-- without counting the test harness's unit-token filtering and GetScript calls.
local natives = {}
for _, key in ipairs({ "UnitName", "UnitExists", "UnitGUID", "UnitClass", "UnitIsPlayer", "UnitIsConnected",
    "UnitIsDead", "UnitIsDeadOrGhost", "UnitHealth", "UnitHealthMax", "UnitHealthPercent", "UnitPower",
    "UnitPowerMax", "UnitPowerPercent", "UnitGroupRolesAssigned", "GetRaidRosterInfo", "GetNumGroupMembers",
    "GetNumSubgroupMembers", "GetTime" }) do
    if type(env[key]) == "function" then natives[env[key]] = true end
end
for _, key in ipairs({ "Show", "Hide", "IsShown", "IsVisible", "SetText", "SetFormattedText", "SetTextColor",
    "SetTexture", "SetColorTexture", "SetVertexColor", "SetValue", "SetMinMaxValues", "SetPoint", "ClearAllPoints",
    "SetSize", "SetWidth", "SetHeight", "SetParent", "RegisterEvent", "RegisterUnitEvent", "UnregisterEvent" }) do
    if type(methods[key]) == "function" then natives[methods[key]] = true end
end
local nativeCalls = 0
local function NativeTick()
    if natives[debug.getinfo(2, "f").func] then nativeCalls = nativeCalls + 1 end
end
local handler = assert(duplicate:GetScript("OnEvent"))
ResetCounters()
debug.sethook(NativeTick, "c")
for _ = 1, 100 do handler(duplicate, "UNIT_NAME_UPDATE", "raid1") end
debug.sethook()
assert(nameReads == 100 and rosterReads == 0 and guidReads == 0, "native-count path did not remain scoped")
-- All five flavors measured 500 counted native calls (5 per notification).
assert(nativeCalls <= 510, "100 targeted names exceed native call budget: " .. nativeCalls)
print(string.format("group_name_update_smoke: PASS (%s: late Unknown/nil, remote/combat, duplicate/rebind, hidden/reshow, strict secret"
    .. "; 100 events %dk/%.3fKB/%d natives)",
    flavor, ticks, kb, nativeCalls))
