-- Role overlays use normalised roles in combat; OOC changes use the existing dirty apply.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local roles = { raid3 = "HEALER" }
local h = Harness.New(root, flavor, { beforeBoot = function(world)
    world.env.UnitGroupRolesAssigned = function(unit) return roles[unit] or "DAMAGER" end
end })
local GF, Runtime = h.GF, h.core.UFStatusRuntime
GF.EnsureDB()
local raid = GF.GetConf("raid")
raid.enabled, raid.roleIcon = true, true
raid.powerShowHealer, raid.powerShowDamager = true, false
GF.InvalidateCompiledSpecs("raid")
GF.RefreshHeaderLayout()
h:SetRaid(10)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local frame = assert(GF.FrameForUnit("raid3"))
local compile, overlay = GF.CompileSpec, GF.RefreshFrameRoleOverlay
local compiles, overlays = 0, 0
GF.CompileSpec = function(...)
    compiles = compiles + 1
    return compile(...)
end
GF.RefreshFrameRoleOverlay = function(...)
    overlays = overlays + 1
    return overlay(...)
end
roles.raid3 = "NONE"
h:EnterCombat()
for pass = 1, 3 do
    compile("raid", frame, "raid3")
    compiles, overlays = 0, 0
    Runtime.UpdateRole(frame, frame.MSUFSpec.status)
    assert(compiles == 0 and overlays == 0, "NONE role recompiled the normalised DAMAGER overlay")
    assert(not frame.roleIcon:IsShown(), "NONE role showed a DPS icon")
end
h:LeaveCombat()
h:RunTimers()
roles.raid3 = "HEALER"
Runtime.UpdateRole(frame, frame.MSUFSpec.status)
assert(frame.MSUFSpec.power.enabled, "OOC healer role did not apply through MarkDirty")
compiles, overlays = 0, 0
roles.raid3 = "DAMAGER"
Runtime.UpdateRole(frame, frame.MSUFSpec.status)
assert(overlays == 0, "OOC role change repeated the existing MarkDirty apply")
assert(compiles == 1 and not frame.MSUFSpec.power.enabled, "OOC role change did not apply exactly once")
-- The adapter is optional at this boundary, as it is for the adjacent MarkDirty call.
h:EnterCombat()
GF.RefreshFrameRoleOverlay = nil
roles.raid3 = "HEALER"
Runtime.UpdateRole(frame, frame.MSUFSpec.status)
GF.RefreshFrameRoleOverlay = overlay
h:LeaveCombat()
h:RunTimers()
assert(#h.violations == 0, tostring(h.violations[1]))
print("group_role_overlay_refresh_smoke: ok (" .. flavor .. ": NONE normalisation, one OOC apply, guarded provider)")
