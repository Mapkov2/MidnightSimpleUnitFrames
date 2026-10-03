-- Native aura lanes park retired containers instead of orphaning them
-- (Auras3/Runtime/MSUF_Auras3_Runtime_NativeApply.lua, Retail and WoW Forever).
--
-- A frame is never freed. Every structural edit of a lane (its signature
-- includes size, spacing, anchor, offsets and text layout) built a new
-- CustomAuraContainer and dropped the old one with its batch of AuraButtons,
-- so a slider drag or a lane toggle grew the frame count for the session
-- (re-review 2026-10-02). The real NativeApply factory runs here against
-- counted container stubs: an apply that returns to a parked signature must
-- take that container back, a drag over more values than it once kept (eight)
-- rebuilds none it already built, and a forced recreate (fresh AuraButtons)
-- never revives a parked one and drops the key's park, which may hold
-- containers from before the PLAYER_ENTERING_WORLD that asked for it.
-- Nothing is evicted: no container can be freed or restyled for another signature.
-- Argument: the repository root.
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))

local created = {}
local function NewContainer()
    local host = { shown = true }
    function host:Show() self.shown = true end
    function host:Hide() self.shown = false end
    local container = { shown = true, enabled = false, _msufA3LayoutHost = host }
    function container:Show() self.shown = true end
    function container:Hide() self.shown = false end
    function container:IsShown() return self.shown end
    function container:SetEnabled(value) self.enabled = value == true end
    function container:IsEnabled() return self.enabled end
    function container:SetUnit(unit) self.boundUnit = unit end
    function container:GetUnit() return self.boundUnit end
    function container:SetAuraGroupMaxFrameCount() end
    function container:SetAuraGroupSortMethod() end
    created[#created + 1] = container
    return container
end

local function Stubs(fields)
    return setmetatable(fields or {}, { __index = function() return function() end end })
end
local dependencies = setmetatable({
    Signatures = Stubs({
        LaneStructuralSignature = function(lane) return "S:" .. tostring(lane.size) end,
        LaneLayoutSignature = function(lane) return "L:" .. tostring(lane.size) end,
        LaneTrackingSignature = function(lane) return "T:" .. tostring(lane.unit) end,
        UsesStandaloneAuraSlot = function() return false end,
    }),
    ConfigValues = Stubs({ EffectiveLaneFilters = function() return "HELPFUL", nil, "none" end }),
    Sort = Stubs({ AuraSortSignature = function() return "DEFAULT:N" end, AuraSortEnums = function() return 0, 0 end }),
    OwnerConfig = Stubs({ NORMAL_LANE_ROOT_KEYS = { "Buffs", "Debuffs" }, EFFECT_ROOT_FIELDS = {}, EFFECT_ROOT_KEYS = {} }),
    Identity = Stubs({ IsLiveGroupAuraFrame = function() return false end }),
}, { __index = function(t, group)
    local stub = Stubs()
    rawset(t, group, stub)
    return stub
end })

local MSUF = { Auras3RuntimeFactories = {} }
local A3 = {}
_G.MSUF_NS = MSUF
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_NativeApply.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
local exports = MSUF.Auras3RuntimeFactories.NativeApply("MidnightSimpleUnitFrames", MSUF, A3, {}, function() end, dependencies)
local ApplyLane = assert(exports.ApplyLane, "NativeApply exports no ApplyLane")
A3._RegisterDirectIdentityRefreshContainer = function() end
A3._UnregisterDirectIdentityRefreshContainer = function() end
A3._NativeContainerVisible = function(container)
    return container.shown and (not container._msufA3LayoutHost or container._msufA3LayoutHost.shown)
end
A3._CreateNativeLane = function()
    local container = NewContainer()
    container:SetEnabled(true)
    container._msufA3NativeRegistered = true
    return container
end
A3._normalAuraLaneOrder = { "buff", "debuff" }

local frame = {}
local laneRoot = {}
local function Lane(size, enabled)
    return { enabled = enabled ~= false, rootKey = "Buffs", unit = "target", kind = "buff", size = size, max = 8 }
end
local function Apply(size, force)
    local container = ApplyLane(laneRoot, Lane(size), frame, force)
    assert(container == laneRoot.Buffs, "the applied container is not the root's lane")
    assert(container.shown and container._msufA3LayoutHost.shown and container.enabled,
        "the applied lane container is not shown, hosted and enabled")
    return container
end

local first = Apply(20)
local second = Apply(21)
assert(#created == 2 and second ~= first, "precondition: a structural edit did not rebuild the lane")
assert(not first.shown and not first.enabled, "a retired lane container stayed live")
assert(Apply(20) == first and #created == 2,
    "returning to a parked structural signature built container " .. #created .. " instead of reviving it")
assert(not second.shown and not second.enabled, "the container it replaced stayed live")

-- A lane toggled off and on again takes its own container back.
A3._HideNormalLaneContainers(laneRoot, { buff = Lane(20, false) }, nil)
assert(laneRoot.Buffs == nil and not first.shown, "a disabled lane kept its container")
assert(Apply(20) == first and #created == 2, "re-enabling a lane built another container")

-- A long slider drag builds one container per value it visits, and dragging
-- back over them builds none: every retired container stays parked.
for size = 30, 60 do Apply(size) end
local before = #created
for size = 60, 30, -1 do Apply(size) end
assert(#created == before, "dragging back over 31 parked values built " .. (#created - before) .. " containers")
local parked = laneRoot._msufA3ParkedLanes and laneRoot._msufA3ParkedLanes.Buffs
local count = 0
for _ in pairs(parked or {}) do count = count + 1 end
assert(count == #created - 1, "the lane park holds " .. count .. " of the " .. (#created - 1) .. " retired containers")

-- A forced recreate wants fresh AuraButtons: it builds one, never revives or
-- keeps the container it replaces, and drops the key's park.
local stale = laneRoot.Buffs
local forced = Apply(30, true)
assert(#created == before + 1 and forced ~= stale and forced == created[#created], "a forced recreate reused a container")
assert(next(laneRoot._msufA3ParkedLanes.Buffs or {}) == nil, "a forced recreate kept the parked containers")
Apply(31)
assert(#created == before + 2, "a forced recreate left an older container parked")
assert(Apply(30) == forced and #created == before + 2, "the forced recreate's container was not parked for its signature")

print("aura native lane park smoke: OK (" .. #created .. " containers built)")
