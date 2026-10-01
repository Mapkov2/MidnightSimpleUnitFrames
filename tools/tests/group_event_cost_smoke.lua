-- group_event_cost_smoke.lua <repoRoot>
--
-- Cold-path costs of the group runtime events (review 2026-10-01, C1.6):
--   (a) UNIT_NAME_UPDATE has no unit filter and nameplates raise it constantly:
--       a non-group unit returns before any config is read;
--   (b) a role poll raises PLAYER_ROLES_ASSIGNED / ROLE_CHANGED_INFORM once per
--       member: the burst folds into one header layout and one role-state pass
--       on the next frame instead of one full pass per event;
--   (c) the target/focus edge update (every group frame on every target change)
--       builds no key strings.
-- Loads the real Metadata and Runtime files on minimal stubs. Plain Lua 5.1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local combat = false
_G.InCombatLockdown = function() return combat end
_G.IsInGroup = function() return true end
_G.IsInRaid = function() return false end
_G.GetNumGroupMembers = function() return 3 end
local timers = {}
_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers()
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do fn() end
end
_G.MSUF_UF_MaskHas = function(mask, flag)
    mask, flag = tonumber(mask) or 0, tonumber(flag) or 0
    if flag == 0 then return false end
    return math.floor(mask / flag) % 2 == 1
end
local eventFrame
_G.CreateFrame = function()
    local frame = { events = {} }
    function frame:SetScript(name, fn) if name == "OnEvent" then self.onEvent = fn end end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    eventFrame = frame
    return frame
end

local counts = {}
local function Count(name) counts[name] = (counts[name] or 0) + 1 end
local function Reset() counts = {} end

local frames = {}
for i = 1, 5 do
    frames[i] = { MSUFUnitKey = i == 1 and "player" or ("party" .. (i - 1)), _msufGFKind = "party",
        _msufUpdateGroupStatusState = function() Count("roleState") end }
end
local ns = {
    ExportPublic = function() end,
    UF = {
        IsUnitToken = function(unit) return type(unit) == "string" and unit ~= "" end,
        RefreshGroupFrameState = function() Count("partyState"); return true end,
    },
    GF = {},
}
local GF = ns.GF
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Metadata.lua"))(
    "MidnightSimpleUnitFrames", ns)
local partyConf = { enabled = true }
function GF.GetConf(kind) Count("GetConf"); return kind == "party" and partyConf or { enabled = false } end
function GF.GetLiveGroupKind() return "party" end
function GF.GetLiveRaidKind() return "raid" end
function GF.GetPriorityBaseKind() Count("GetPriorityBaseKind"); return "party" end
function GF.PriorityFramesConfigured() Count("PriorityFramesConfigured"); return true end
function GF.IsArenaPartyContext() Count("IsArenaPartyContext"); return false end
function GF.IsPriorityGroupUnit(unit) return unit == "player" or unit:match("^party[1-4]$") ~= nil end
function GF.RefreshPriorityFrames() Count("RefreshPriorityFrames"); return true end
GF.EnsureDB = function() end
GF.SetupHeader = function(key) Count("SetupHeader:" .. key); return nil, true end
GF.SetupPriorityHeader = function() return nil end
GF.ResolvePrioritySelection = function() return "Name-player", 1 end
GF.RetireHeader = function() return true end
function GF.ForEachFrame(fn, _, a, b, c)
    local any = false
    for _, frame in ipairs(frames) do
        if fn(frame, frame.MSUFUnitKey, frame._msufGFKind, a, b, c) == true then any = true end
    end
    return any
end
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua"))(
    "MidnightSimpleUnitFrames", ns)
GF.RefreshPriorityFrames = function() Count("RefreshPriorityFrames"); return true end
GF.RefreshHeaderLayout()
RunTimers()
Check(eventFrame.events.UNIT_NAME_UPDATE == true, "Priority Frames did not subscribe UNIT_NAME_UPDATE")

-- (a) A city's worth of nameplate name updates reads no config at all.
Reset()
for i = 1, 200 do eventFrame.onEvent(eventFrame, "UNIT_NAME_UPDATE", "nameplate" .. ((i % 40) + 1)) end
for _, unit in ipairs({ "target", "focus", "mouseover", "boss1", "arena1", "partypet1" }) do
    eventFrame.onEvent(eventFrame, "UNIT_NAME_UPDATE", unit)
end
Check(next(counts) == nil, "non-group UNIT_NAME_UPDATE read group config (" .. (function()
    local parts = {}
    for name, n in pairs(counts) do parts[#parts + 1] = name .. "=" .. n end
    table.sort(parts)
    return table.concat(parts, ", ")
end)() .. ")")
eventFrame.onEvent(eventFrame, "UNIT_NAME_UPDATE", "party2")
RunTimers()
Check((counts.RefreshPriorityFrames or 0) == 1, "a party member's name update did not reach Priority Frames")

-- (b) A role poll in a five-member party: ten role events, one pass.
Reset()
for _ = 1, 5 do
    eventFrame.onEvent(eventFrame, "ROLE_CHANGED_INFORM")
    eventFrame.onEvent(eventFrame, "PLAYER_ROLES_ASSIGNED")
end
Check((counts["SetupHeader:party"] or 0) == 0 and (counts.roleState or 0) == 0,
    "role events ran header layout or role state synchronously, once per event")
Check(#timers == 1, "a role burst queued " .. #timers .. " passes instead of one")
RunTimers()
Check(counts["SetupHeader:party"] == 1, "the role burst set the party header up "
    .. tostring(counts["SetupHeader:party"]) .. " times, expected once")
Check(counts.roleState == #frames, "the role burst refreshed role state " .. tostring(counts.roleState)
    .. " times for " .. #frames .. " frames")
Check(counts.partyState == nil, "a role-only burst ran the roster party-state pass")
-- A roster change in the same frame keeps the wider roster pass.
Reset()
eventFrame.onEvent(eventFrame, "PLAYER_ROLES_ASSIGNED")
eventFrame.onEvent(eventFrame, "GROUP_ROSTER_UPDATE")
eventFrame.onEvent(eventFrame, "ROLE_CHANGED_INFORM")
Check(#timers == 1, "role and roster events queued more than one pass")
RunTimers()
Check(counts["SetupHeader:party"] == 1 and counts.roleState == #frames and counts.partyState == #frames,
    "a merged role and roster burst lost work")
-- In combat the burst defers once, as the roster path does.
Reset()
combat = true
for _ = 1, 4 do eventFrame.onEvent(eventFrame, "PLAYER_ROLES_ASSIGNED") end
Check(#timers == 0 and not counts["SetupHeader:party"], "a role event in combat set headers up")
combat = false
eventFrame.onEvent(eventFrame, "PLAYER_REGEN_ENABLED")
Check(counts["SetupHeader:party"] == 1 and counts.roleState == #frames, "deferred role work was not flushed once at regen")

-- (c) No key strings are built on the target/focus edge path.
local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Visuals.lua", "rb"))
local visuals = file:read("*a"):gsub("\r\n", "\n")
file:close()
local body = assert(visuals:match("\nlocal function UpdateUnitEdges%(.-\nend\n"),
    "UpdateUnitEdges not found in MSUF_UF_Group_Visuals.lua")
Check(not body:find("%.%."), "UpdateUnitEdges concatenates a string on every target or focus change")

print("group_event_cost_smoke: ok")
