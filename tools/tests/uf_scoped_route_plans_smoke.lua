-- Scoped element lifetime, mutable provider snapshots and private/reentrant recipes.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/classpower_world.lua")
local fixtureRoot = arg[2] or root
local t = World.Start(root, "Mainline", "WARRIOR", 1, World.PT.RAGE, { showClassPower = false }, {
    beforeLoad = function()
        -- The baseline CP fixture used an inert registry. Both source trees
        -- must exercise their actual UF core with the same provider fixture.
        dofile(fixtureRoot .. "/tools/tests/classpower_collaborators.lua").Install(root, MSUF_NS)
    end })
local UF = MSUF_NS.UF
local name, applied, updates = "ScopedRouteProbe", 0, 0
local events = { "UNIT_HEALTH" }
local nested, reenter
local function Update() updates = updates + 1 end
local element = { Routes = { events = true, forceUpdate = true }, Update = Update,
    IsEnabled = function() return true end,
    Apply = function() applied = applied + 1 end,
    SelectUpdate = function(frame) return frame.probeUpdate or Update end,
    GetEvents = function(frame)
        if frame == reenter then
            reenter = nil
            UF.ApplySpec(nested, { unit = "player", enabled = true, scope = "probe" }, nil, { [name] = true })
        end
        return events
    end }
assert(UF.RegisterElement(name, element, { apply = true, scope = "probe" }))
local function Frame(scope)
    local frame = t.env:CreateFrame("Frame", nil, UIParent)
    frame:Show()
    UF.AttachFrame(frame, { scope = scope })
    return frame
end
local ordinary = Frame("single")
UF.ApplySpec(ordinary, { unit = "player", enabled = true, scope = "single" }, nil, { [name] = true })
assert(applied == 0 and not ordinary:IsElementEnabled(name), "a resource-only element applied to an ordinary unit frame")
local first, second = Frame("probe"), Frame("probe")
local function Apply(frame)
    UF.ApplySpec(frame, { unit = "player", enabled = true, scope = "probe" }, nil, { [name] = true })
end
Apply(first); Apply(second)
local plan, route = first._msufElementEventRoutes, first.UNIT_HEALTH
assert(plan == second._msufElementEventRoutes and route == second.UNIT_HEALTH, "scoped immutable routes did not intern")
events[2] = "UNIT_MAXHEALTH"
Apply(second)
assert(#plan[name].events == 1 and not first:IsEventRegistered("UNIT_MAXHEALTH"), "a mutable provider changed another owner's recipe")
assert(second:IsEventRegistered("UNIT_MAXHEALTH"), "a changed scoped event set was not adopted")
local private = Frame("probe")
local privateCalls = 0
private.probeUpdate = function() privateCalls = privateCalls + 1 end
Apply(private)
local privatePlan = private._msufElementEventRoutes
assert(privatePlan ~= second._msufElementEventRoutes and privatePlan[name].update == private.probeUpdate,
    "frame-specific update ownership was lost")
nested = Frame("probe")
local outer = Frame("probe")
reenter = outer
Apply(outer)
assert(private._msufElementEventRoutes == privatePlan and first._msufElementEventRoutes == plan,
    "reentrant compilation mutated a retained route plan")
private:GetScript("OnEvent")(private, "UNIT_HEALTH", "player")
assert(privateCalls == 1, "a private compiled route delivered the wrong callback")
first:GetScript("OnEvent")(first, "UNIT_HEALTH", "player")
assert(updates == 1 and first.UNIT_HEALTH == route, "another compilation changed the original dispatch closure")
for _, frame in ipairs({ first, second, private, outer, nested }) do UF.DetachFrame(frame) end
assert(not first:IsEventRegistered("UNIT_HEALTH") and not private:IsElementEnabled(name), "scope detach left an active owner")
print("uf_scoped_route_plans_smoke: OK (scope, shared/private/mutable/reentrant recipes, detach)")
