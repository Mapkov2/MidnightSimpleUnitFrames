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
-- The boot kit publishes inert stand-ins for client globals. Its metadata has
-- no frame-name prefix, so the factory looks up MidnightSimpleUnitFrames_player,
-- gets a stand-in and adopts it as the player frame. They are not runtime
-- frames: they must not join the rounded frame list or the unit map that the
-- Auras3 refresh below walks.
for i = #UF.frameList, 1, -1 do
    if tostring(UF.frameList[i]) == "<client_world stub>" then table.remove(UF.frameList, i) end
end
for unit, frame in pairs(UF.frames) do
    if tostring(frame) == "<client_world stub>" then UF.frames[unit] = nil end
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
-- Combat end and raid join carry +11 over 76d9a9fd: the kit's Event() walks
-- every widget frame, and the lifecycle's three PLAYER_LOGOUT frames replace
-- two load frames. No addon line runs more often; the client dispatches only to
-- registered frames. Until 62aba089, a boot-time Auras3 refresh left its
-- next-frame latch set (this kit pumps no OnUpdate), so no later refresh ran
-- here. Now the rounded apply above runs it and raid frames gain their Auras3
-- surfaces; cc552759 measures the same raid join 11 lower on both clients.
local limits = {
    Mainline = { 10438, 271832, 2049299 }, Forever = { 10837, 269792, 2052956 },
    Vanilla = { 12987, 269712, 1793570 },
    TBC = { 12987, 271200, 1793900 }, Mists = { 12868, 271210, 1790250 },
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
