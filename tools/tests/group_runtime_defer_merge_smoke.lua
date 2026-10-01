-- group_runtime_defer_merge_smoke.lua <repoRoot>
--
-- Group work requested in combat is merged into one deferred pass for
-- PLAYER_REGEN_ENABLED (MSUF_UF_Group_Runtime.lua GF.DeferGroupRuntime). The
-- merged scope must only ever widen:
--   * an unscoped request (kind nil) means every kind and must not be narrowed
--     by a later scoped one;
--   * two different kinds widen to every kind, and stay there;
--   * event names and other non-kinds (RefreshHeaderLayout("PLAYER_DIFFICULTY_CHANGED"),
--     MarkAllDirty's "dirty") are not kinds: they mean every kind too. Used as a
--     kind they made the flush refresh the frames of no kind at all.
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
_G.C_Timer = { After = function(_, fn) fn() end }
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

local applied = {}
local frames = {
    { MSUFUnitKey = "party1", _msufGFKind = "party" },
    { MSUFUnitKey = "raid1", _msufGFKind = "raid" },
}
local ns = {
    ExportPublic = function() end,
    UF = {
        IsUnitToken = function(unit) return type(unit) == "string" and unit ~= "" end,
        ApplySpec = function(frame) applied[#applied + 1] = frame._msufGFKind; return true end,
    },
    GF = {},
}
local GF = ns.GF
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Metadata.lua"))(
    "MidnightSimpleUnitFrames", ns)
function GF.GetConf(kind) return { enabled = kind == "party" or kind == "raid" } end
function GF.GetLiveGroupKind() return "party" end
function GF.GetLiveRaidKind() return "raid" end
GF.EnsureDB = function() end
GF.SetupHeader = function() return nil, true end
GF.RetireHeader = function() return true end
GF.CompileSpec = function(kind) return { kind = kind } end
GF.ApplyStructureSpec = function(frame) applied[#applied + 1] = frame._msufGFKind; return true end
function GF.ForEachFrame(fn, _, a, b, c)
    local any = false
    for _, frame in ipairs(frames) do
        if fn(frame, frame.MSUFUnitKey, frame._msufGFKind, a, b, c) == true then any = true end
    end
    return any
end
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua"))(
    "MidnightSimpleUnitFrames", ns)
Check(type(eventFrame and eventFrame.onEvent) == "function", "the group runtime installed no event handler")
GF.RefreshHeaderLayout() -- subscribes the runtime, out of combat

-- Observers (Edit Mode, extra blocks) receive the flushed kind: nil for every kind.
local observedKinds = {}
GF.RegisterRuntimeObserver("defer-merge-smoke", function(operation, kind)
    if operation == "refreshVisuals" then observedKinds[#observedKinds + 1] = kind == nil and "*" or tostring(kind) end
end)

local function Run(label, requests, expected)
    combat = true
    for _, request in ipairs(requests) do request() end
    combat = false
    applied, observedKinds = {}, {}
    eventFrame.onEvent(eventFrame, "PLAYER_REGEN_ENABLED")
    table.sort(applied)
    local got = table.concat(applied, ",")
    Check(got == expected, label .. ": the regen flush refreshed [" .. got .. "], expected [" .. expected .. "]")
    local observed = table.concat(observedKinds, ",")
    Check(observed == (expected:find(",", 1, true) and "*" or expected),
        label .. ": runtime observers saw kind [" .. observed .. "]")
end

local VISUAL = GF.DIRTY_VISUAL
Run("one scoped request", {
    function() GF.RefreshVisuals("party", VISUAL) end,
}, "party")
Run("an unscoped request, then a scoped one", {
    function() GF.RefreshVisuals(nil, VISUAL) end,
    function() GF.RefreshVisuals("party", VISUAL) end,
}, "party,raid")
Run("a scoped request, then an unscoped one", {
    function() GF.RefreshVisuals("party", VISUAL) end,
    function() GF.RefreshVisuals(nil, VISUAL) end,
}, "party,raid")
Run("two kinds, then the first again", {
    function() GF.RefreshVisuals("party", VISUAL) end,
    function() GF.RefreshVisuals("raid", VISUAL) end,
    function() GF.RefreshVisuals("party", VISUAL) end,
}, "party,raid")
Run("an unscoped repaint, then a layout pass named after its event", {
    function() GF.DeferGroupRuntime("refresh", nil, VISUAL) end,
    function() GF.RefreshHeaderLayout("PLAYER_DIFFICULTY_CHANGED") end,
}, "party,raid")
Run("an event-named layout pass with a mask", {
    function() GF.DeferGroupRuntime("layout", "PLAYER_ROLES_ASSIGNED", VISUAL) end,
}, "party,raid")
Run("MarkAllDirty's layout request", {
    function() GF.MarkAllDirty(GF.DIRTY_LAYOUT) end,
    function() GF.RefreshVisuals("raid", VISUAL) end,
}, "party,raid")

print("group_runtime_defer_merge_smoke: ok")
