-- Real aura preview owner: coalescing must preserve latest-request latency.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local h = dofile(root .. "/tools/tests/group_header_world.lua").New(root, "Mainline", {
    beforeBoot = function(world) world.env.MAX_BOSS_FRAMES = 5 end,
})
h:RunDeferred()
local c, calls, hidden = h.core, {}, 0
local A3 = c.MSUF_Auras3
local EM = A3.EditMode
EM.RefreshUnit = function(unit) calls[#calls + 1] = unit end
EM.HideAll = function() hidden = hidden + 1 end
local function Active(on)
    c.PublicGlobals.MSUF_EditState.active = on
    c.ExportPublic("MSUF_UnitPreviewActive", on)
end
Active(true)
A3.RefreshEditPreview("target")
assert(#calls == 1 and calls[1] == "target", "single-unit preview stopped being immediate")
calls = {}
for i = 1, 20 do A3.RefreshEditPreview() end
assert(#calls == 0, "all-unit request unexpectedly blocked on synchronous painting")
local first, peak, previous = nil, 0, 0
h:RunDeferred(1000, function(turn)
    if #calls > 0 and not first then first = turn end
    peak = math.max(peak, #calls - previous)
    previous = #calls
end)
print("aura burst first paint turn=" .. tostring(first) .. " peak=" .. peak .. " units=" .. #calls)
assert(first and first <= 3, "superseded aura jobs delayed the newest request by frame turns")
assert(peak <= 1, "multiple unit paints shared a deferred turn")
assert(#calls == 12, "coalesced all-unit refresh lost or duplicated units")
local seen = {}
for _, unit in ipairs(calls) do assert(not seen[unit], "unit refreshed twice"); seen[unit] = true end
assert(seen.player and seen.pet and seen.target and seen.focus and seen.boss5 and seen.arena3)
calls = {}
local nested = false
EM.RefreshUnit = function(unit)
    calls[#calls + 1] = unit
    if not nested then nested = true; A3.RefreshEditPreview() end
end
A3.RefreshEditPreview()
h:RunDeferred()
assert(#calls == 13 and calls[1] == "player" and calls[2] == "player",
    "reentrant newest aura request was replaced by old continuation")
calls = {}
A3.RefreshEditPreview()
Active(false)
local before = hidden
A3.RefreshEditPreview()
assert(hidden == before + 1, "inactive preview did not hide immediately")
h:RunDeferred()
assert(#calls == 0, "inactive preview left queued paints")
Active(true)
calls = {}
A3.RefreshEditPreview()
h.widgets:SetCombat(true)
h:RunDeferred()
assert(#calls == 0, "combat left queued aura paints")
h.widgets:SetCombat(false)
local marker = false
EM.RefreshUnit = function() error("expected aura painter failure") end
A3.RefreshEditPreview()
c.Scheduler.RunWorkNextFrame(function() marker = true end)
h:RunDeferred()
assert(marker, "aura painter failure stranded another owner")
print("PASS aura_editmode_work_queue_smoke")
