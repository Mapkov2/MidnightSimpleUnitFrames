-- Strict secret watch plus executed-return checks: Lua 5.1 cannot trap f() or nil.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
local env = world.env
local statusPath = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua"
local visualsPath = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Visuals_Common.lua"
local source = { ["@" .. statusPath] = World.Read(statusPath), ["@" .. visualsPath] = World.Read(visualsPath) }
local role = Secrets.New("string")
local errors, reads = {}, 0
env.issecretvalue = Secrets.IsSecret
env.UnitExists = function() return true end
env.UnitThreatSituation = function() return 3 end
env.UnitGroupRolesAssigned = function()
    reads = reads + 1
    if Secrets.IsSecret(role) then
        local info = debug.getinfo(2, "Sl")
        local text = source[info.source] or ""
        local line = 0
        for content in text:gmatch("[^\n]*\n") do
            line = line + 1
            if line == info.currentline and content:find("UnitGroupRolesAssigned%(.-%)%s+or") then
                errors[#errors + 1] = "secret API return truth-tested: " .. content
            end
        end
    end
    return role
end
world:Boot()
local failure = world:FirstFailure()
assert(not failure, failure and failure.message)
env.MSUF_InitProfiles()
env.MSUF_EnsureDB(true)
local Runtime = assert(world.core.UFStatusRuntime)
local Visuals = assert(world.core.UFVisuals)
local frame = env.CreateFrame("Frame", nil, env.UIParent)
frame.MSUFUnitKey = "party1"
frame._msufGFKind = "party"
frame.power = env.CreateFrame("StatusBar", nil, frame)
frame.roleIcon = frame:CreateTexture()
local status = { role = { enabled = true, showTank = true, showHealer = true, showDPS = true } }
local function Case(label, fn)
    reads = 0
    local stop = Secrets.Watch({ statusPath, visualsPath }, { strict = true })
    local ok, err = pcall(fn)
    local violations = stop()
    if not ok then errors[#errors + 1] = label .. ": " .. tostring(err) end
    for _, violation in ipairs(violations) do errors[#errors + 1] = label .. ": " .. violation end
    return reads
end
Case("role icon", function()
    Runtime.UpdateRole(frame, status)
    assert(status.roleValue == nil and not frame.roleIcon:IsShown(), "secret role showed an icon")
end)
-- Exercise the fallback directly through the runtime after the primary role was cleared.
local gf = world.core.GF
local getRole, effectiveHeight = gf.GetUnitGroupRole, gf.GetEffectivePowerHeight
gf.GetUnitGroupRole, gf.GetEffectivePowerHeight = nil, nil
frame._c = { powTank = true, powHealer = true, powDPS = true }
Case("power fallback", function() Runtime.UpdateRole(frame, status) end)
gf.GetUnitGroupRole, gf.GetEffectivePowerHeight = getRole, effectiveHeight
status.roleValue = role
Case("cached power role", function() Runtime.UpdatePowerRoleVisibility(frame, status) end)
Case("aggro filter", function()
    for _, mode in ipairs({ "TANK", "HEALER", "NON_TANK" }) do
        assert(not Visuals.GroupAggroModeAllows(frame, "party1", mode), "secret role passed " .. mode)
    end
end)
local body = source["@" .. visualsPath]:match("local function GroupAggroModeAllows%(.-\nend")
assert(body, "group aggro role filter missing")
if body:find("ReadGroupRole%(.-%)%s+or") then errors[#errors + 1] = "secret group-role return truth-tested" end
frame._msufDispatchActive, frame._msufDispatchToken = true, 101
assert(Case("aggro pair", function()
    local border, corner = Visuals.ResolveGroupAggroPair(frame, "party1", "TANK", "NON_TANK")
    assert(not border and not corner, "secret role enabled group aggro visuals")
    Visuals.ResolveGroupAggroPair(frame, "party1", "HEALER", "TANK")
    assert(frame._msufGroupRoleDispatchValue == nil, "secret role was cached")
end) == 1, "group role read more than once in a dispatch")
frame._msufDispatchActive = nil
local secretAPI = env.issecretvalue
env.issecretvalue = function() error("group role filter reread global secret API", 2) end
Case("cached secret helper", function()
    assert(not Visuals.GroupAggroModeAllows(frame, "party1", "TANK"), "cached helper allowed a secret role")
end)
env.issecretvalue = secretAPI
for _, value in ipairs({ "TANK", "HEALER", "DAMAGER", "NONE", false }) do
    role = value or nil
    Runtime.UpdateRole(frame, status)
    assert(frame.roleIcon:IsShown() == (value == "TANK" or value == "HEALER" or value == "DAMAGER"), "plain role icon")
    assert(Visuals.GroupAggroModeAllows(frame, "party1", "TANK") == (value == "TANK"), "plain tank filter")
    assert(Visuals.GroupAggroModeAllows(frame, "party1", "HEALER") == (value == "HEALER"), "plain healer filter")
end
assert(#errors == 0, table.concat(errors, "\n"))
print("uf_role_secret_reads_smoke: ok (" .. flavor .. ")")
