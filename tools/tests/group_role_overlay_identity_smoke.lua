-- Real secure-header identity shifts must repaint the role overlay in lockdown.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
local roles = { raid3 = "HEALER", raid4 = "DAMAGER" }
local guids = { raid3 = "Player-Healer", raid4 = "Player-DPS" }
local h = Harness.New(root, flavor, { beforeBoot = function(world)
    world.env.issecretvalue = Secrets.IsSecret
    world.env.UnitGroupRolesAssigned = function(unit) return roles[unit] or "DAMAGER" end
    local guid = world.env.UnitGUID
    world.env.UnitGUID = function(unit) return guids[unit] or guid(unit) end
end })
local GF = h.GF
GF.EnsureDB()
local raid = GF.GetConf("raid")
raid.enabled, raid.showPowerText = true, true
raid.roleIcon = arg[3] ~= "icon-off"
raid.powerTextCenter = "PERCENT"
raid.powerShowHealer, raid.powerShowDamager = true, false
raid.height, raid.powerHeight = 20, 8
raid.nameBarEnabled, raid.nameBarHeight = true, 18
GF.InvalidateCompiledSpecs("raid")
GF.RefreshHeaderLayout()
h:SetRaid(10)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local healer, dps = assert(GF.FrameForUnit("raid3")), assert(GF.FrameForUnit("raid4"))
local stripHeight = GF.CompileSpec("raid").group.nameBarHeight

local function CheckOverlay(frame, unit, enabled)
    local label = flavor .. ": " .. unit
    local spec = frame.MSUFSpec
    assert(spec.unit == unit and frame.MSUFUnitKey == unit, label .. " retained the old identity")
    assert(spec.power.enabled == enabled, label .. " retained the previous occupant's power overlay")
    assert(spec.status.roleValue == roles[unit], label .. " retained the previous role")
    assert(spec.showPowerText == enabled, label .. " retained the previous power-text overlay")
    assert((frame._msufActiveElements.Power == true) == enabled, label .. " has stale Power ownership")
    assert((frame._msufActiveElements.PowerText == true) == enabled, label .. " has stale PowerText ownership")
    assert((frame.power ~= nil and frame.power:IsShown()) == enabled, label .. " has stale power-bar visibility")
    local inset = enabled and spec.power.height or 0
    local top = math.min(stripHeight, spec.height - inset - 1)
    assert(frame.hpBar._msufHealthPowerInset == inset, label .. " has stale health/power inset")
    assert(frame.hpBar._msufHealthTopInset == top, label .. " has stale name-bar inset: "
        .. tostring(frame.hpBar._msufHealthTopInset) .. "/" .. top .. ", strip " .. spec.group.nameBarHeight)
    assert(frame.MSUFGFNameBar:GetHeight() == top, label .. " has stale name-bar geometry")
end
CheckOverlay(healer, "raid3", true)
CheckOverlay(dps, "raid4", false)

local layout, layoutCalls = GF.RefreshHeaderLayout, 0
local identity, identityCalls = h.UF.OnUnitChanged, 0
h.UF.OnUnitChanged = function(...)
    identityCalls = identityCalls + 1
    return identity(...)
end
GF.RefreshHeaderLayout = function(...)
    assert(not h.env.InCombatLockdown(), "identity overlay requested protected header layout in combat")
    layoutCalls = layoutCalls + 1
    return layout(...)
end
local width, height = healer:GetWidth(), healer:GetHeight()
for pass = 1, 2 do
    h:EnterCombat()
    local before, identityBefore = layoutCalls, identityCalls
    h.units[3], h.units[4] = h.units[4], h.units[3]
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    CheckOverlay(healer, pass == 1 and "raid4" or "raid3", pass == 2)
    CheckOverlay(dps, pass == 1 and "raid3" or "raid4", pass == 1)
    assert(identityCalls == identityBefore + 2, "role overlay bypassed the unit identity/aura callback")
    assert(healer:GetWidth() == width and healer:GetHeight() == height, "secure button size changed in combat")
    assert(layoutCalls == before and GF._pendingGroupRuntime == true, "layout was not deferred")
    assert(#h.violations == 0, tostring(h.violations[1]))
    h:LeaveCombat()
    h:RunTimers()
    assert(layoutCalls > before and not GF._pendingGroupRuntime, "REGEN_ENABLED did not flush deferred layout")
end
-- A native raid token can stay the same while its occupant GUID changes.
local overlay, overlayCalls = GF.RefreshFrameRoleOverlay, 0
GF.RefreshFrameRoleOverlay = function(...)
    overlayCalls = overlayCalls + 1
    return overlay(...)
end
for pass = 1, 2 do
    h:EnterCombat()
    local before = layoutCalls
    overlayCalls = 0
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    assert(overlayCalls == 0, "unchanged roster recompiled role overlays")
    guids.raid3, guids.raid4 = guids.raid4, guids.raid3
    roles.raid3, roles.raid4 = roles.raid4, roles.raid3
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    assert(overlayCalls == 2, "GUID shift refreshed frames other than the two changed identities")
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
    assert(overlayCalls == 2, "repeated roster recompiled unchanged identities")
    CheckOverlay(healer, "raid3", pass == 2)
    CheckOverlay(dps, "raid4", pass == 1)
    assert(layoutCalls == before and GF._pendingGroupRuntime == true, "same-token layout was not deferred")
    assert(#h.violations == 0, tostring(h.violations[1]))
    h:LeaveCombat()
    h:RunTimers()
    assert(layoutCalls > before and not GF._pendingGroupRuntime, "same-token regen layout was not flushed")
end
local stop = Secrets.Watch({
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua",
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Adapter.lua",
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua",
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_FrameOverlay.lua",
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua",
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Status_Regions.lua",
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Status_Indicators.lua",
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Status_GroupRuntime.lua",
    root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Status_Level.lua",
    root .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB_Geometry.lua",
}, { strict = true })
h:EnterCombat()
local oldGUID = guids.raid3
guids.raid3 = Secrets.New("string")
overlayCalls = 0
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
assert(overlayCalls == 0, "secret GUID triggered an identity comparison or overlay")
assert(healer._msufGFRoleOverlayGUID == oldGUID, "secret GUID replaced the last readable identity")
roles.raid3 = Secrets.New("string")
guids.raid3 = "Player-UnknownRole"
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
assert(healer.MSUFSpec.power.enabled == false and healer._msufActiveElements.Power ~= true,
    "a secret role retained healer power")
local violations = stop()
assert(#violations == 0, table.concat(violations, "\n"))
assert(#h.violations == 0, tostring(h.violations[1]))
h:LeaveCombat()
-- The harness propagates group event/timer errors; unrelated fixture errors are isolated there.
assert(#h.callMethodErrors == 0, "group child adoption raised: " .. tostring(h.callMethodErrors[1]))
for _, err in ipairs(h.eventErrors) do
    assert(not err:find("Engine/Elements/", 1, true), "unit-frame element raised: " .. err)
end
print("group_role_overlay_identity_smoke: ok (" .. flavor .. ": token/GUID shifts, secret role, role icon "
    .. tostring(raid.roleIcon) .. ", 0 protected writes)")
