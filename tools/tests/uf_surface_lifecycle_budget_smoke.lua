-- Pin the original show, combat-end and rounded roster work at 76d9a9fd.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local measureOnly = os.getenv("MSUF_BUDGET_MEASURE") == "1"
local w = dofile(root .. "/tools/tests/health_tick_world.lua").New(root, flavor)
local h, env, UF, GF = w.h, w.env, w.UF, w.GF
local db = UF.Config.GetDB()
db.bars = db.bars or {}
db.bars.roundedFramesEnabled = true
db.target.texLayerEnabled, db.target.texLayerVisibility = true, "COMBAT"
db.target.texLayerRoundedClip = true
-- The boot kit publishes inert stand-ins for client globals. They are not
-- runtime frames and must not join the rounded frame enumeration.
for i = #UF.frameList, 1, -1 do
    if tostring(UF.frameList[i]) == "<client_world stub>" then table.remove(UF.frameList, i) end
end
env.MSUF_ApplyRoundedUnitframes()
env.MSUF_RefreshUnitTextureLayers(nil)
h:RunTimers()
-- This kit's synthetic login has incomplete profile APIs. Establish the
-- measured lifecycle only after the real target/raid frames are configured.
h.eventErrors = {}
local frame = w.single
local function ShowUnit()
    frame:Hide()
    frame:GetScript("OnHide")(frame)
    frame:Show()
    frame:GetScript("OnShow")(frame)
end
local function Instructions(run)
    local count = 0
    debug.sethook(function() count = count + 1 end, "", 1)
    run()
    debug.sethook()
    return count
end
ShowUnit()
local show = Instructions(ShowUnit)
h:EnterCombat()
ShowUnit()
local combatEnd = Instructions(function() h:LeaveCombat() h:RunTimers() end)
local raidJoin = Instructions(function()
    h:SetRaid(20)
    h:Event("GROUP_ROSTER_UPDATE")
    h:RunTimers()
end)
local costs = { show, combatEnd, raidJoin }
local limits = {
    Mainline = { 10438, 271821, 1815307 }, Forever = { 10837, 269781, 1817534 },
    Vanilla = { 12987, 269701, 1793570 },
    TBC = { 12987, 271189, 1793900 }, Mists = { 12868, 271199, 1790250 },
}
local labels = { "unit OnShow", "combat end after combat show", "rounded raid join" }
local failures = {}
for i = 1, #costs do
    if not measureOnly then
        if costs[i] > limits[flavor][i] then
            failures[#failures + 1] = labels[i] .. ": " .. costs[i] .. " > BASE " .. limits[flavor][i]
        end
    end
end
assert(#failures == 0, table.concat(failures, "\n"))
assert(#h.eventErrors == 0, tostring(h.eventErrors[1]))
assert(#h.violations == 0, tostring(h.violations[1]))
print(string.format("uf_surface_lifecycle_budget_smoke: %s (%s: show=%d combat-end=%d rounded-raid-join=%d)",
    measureOnly and "measure" or "ok", flavor, show, combatEnd, raidJoin))
