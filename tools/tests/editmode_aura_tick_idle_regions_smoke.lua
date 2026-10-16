-- An Edit Mode aura animation tick advances only the regions its lane shows: a lane without a
-- duration bar leaves the bar alone (no native call), a lane with one keeps its fill following
-- the sample state, and the swipe stays hidden in a lane that has none.
-- Plain Lua 5.1: lua editmode_aura_tick_idle_regions_smoke.lua <repo root> <flavor>
local root = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "flavor required")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local w = World.New(root, flavor)
w.env.MAX_BOSS_FRAMES = 5
w:Boot()
assert(not w:FirstFailure(), "graph boot failed")
w.env.MSUF_EnsureDB(true)

-- The Edit Mode module keeps its painters private; find them through the loaded closures.
local want = { EnsureIcon = true, ApplyPreviewIconText = true, ApplyPreviewAuraAnimation = true }
local edit, seen = {}, {}
local function Walk(fn, name, depth)
    if type(fn) ~= "function" or seen[fn] or depth > 12 then return end
    seen[fn] = true
    local source = debug.getinfo(fn, "S").source
    if source:sub(-32) == "MSUF_Auras3_EditMode_Preview.lua" and want[name] then edit[name] = fn end
    for index = 1, 60 do
        local upvalue, child = debug.getupvalue(fn, index)
        if not upvalue then break end
        if type(child) == "function" then Walk(child, upvalue, depth + 1) end
    end
end
for key, fn in pairs(w.core.MSUF_Auras3.EditMode) do Walk(fn, key, 0) end
Walk(w.core.MSUF_Auras3.EditMode.RefreshUnit, "RefreshUnit", 0)
for name in pairs(want) do assert(edit[name], "Edit Mode preview owner missing: " .. name) end

local readConfig
local function FindConfig(fn)
    if type(fn) ~= "function" or seen[fn] then return end
    seen[fn] = true
    for index = 1, 60 do
        local upvalue, child = debug.getupvalue(fn, index)
        if not upvalue then break end
        if upvalue == "ReadMiniAuraPreviewConfig" then readConfig = child end
        if type(child) == "function" then FindConfig(child) end
    end
end
seen = {}
FindConfig(w.core.MSUF2.AurasPage.BuildAuraStylePreviewWorkbench)
assert(readConfig, "mini preview configuration reader missing")

local parent = w.env.CreateFrame("Frame", nil, w.env.UIParent)
parent:SetSize(300, 100)
local group = w.env.CreateFrame("Frame", nil, parent)
local function Lane(overrides)
    local cfg = readConfig("player", { previewLane = "debuff" })
    for key, value in pairs(overrides) do cfg[key] = value end
    return cfg
end

-- A lane without a duration bar: layout hides the bar once, ticks never touch it.
local cfg = Lane({ showDurationBar = false, showCooldownSwipe = true })
local icon = edit.EnsureIcon(group, 1)
edit.ApplyPreviewIconText(icon, "player", cfg, 1)
assert(icon.DurationBar.shown ~= true, "layout leaves a disabled duration bar hidden")
local touches = 0
for _, method in ipairs({ "Show", "Hide", "SetShown", "SetPoint", "ClearAllPoints", "SetWidth", "SetHeight", "SetVertexColor" }) do
    local original = icon.DurationBar[method]
    icon.DurationBar[method] = function(self, ...)
        touches = touches + 1
        return original(self, ...)
    end
end
for step = 1, 3 do edit.ApplyPreviewAuraAnimation(group, "debuff", 1, cfg, 0.4 * step) end
assert(touches == 0, "an animation tick touched a disabled duration bar " .. touches .. " times")
assert(icon.Swipe.shown == true, "a lane with a swipe keeps animating it")

-- A lane with a bar: the fill follows the sample state tick by tick.
cfg = Lane({ showDurationBar = true, durationBarDisplay = "OVERLAY", durationBarDirection = "REMAINING", durationBarPosition = "BOTTOM" })
edit.ApplyPreviewIconText(icon, "player", cfg, 1)
assert(icon.DurationBar.shown == true, "layout shows an enabled duration bar")
local widths = {}
for step = 1, 3 do
    edit.ApplyPreviewAuraAnimation(group, "debuff", 1, cfg, 0.9 * step)
    widths[#widths + 1] = icon.DurationBar.width
end
assert(widths[1] and widths[2] and widths[3] and (widths[1] ~= widths[2] or widths[2] ~= widths[3]),
    "the duration bar fill does not follow the animation")

-- A bar-only lane hides the swipe and keeps it hidden through ticks.
cfg = Lane({ showDurationBar = true, durationBarDisplay = "BAR_ONLY" })
edit.ApplyPreviewIconText(icon, "player", cfg, 1)
for step = 1, 2 do edit.ApplyPreviewAuraAnimation(group, "debuff", 1, cfg, 0.4 * step) end
assert(icon.Swipe.shown == false, "a bar-only lane shows no swipe")

print("PASS Edit Mode aura tick: idle bar untouched, active bar follows the sample, bar-only lane has no swipe (" .. flavor .. ")")
