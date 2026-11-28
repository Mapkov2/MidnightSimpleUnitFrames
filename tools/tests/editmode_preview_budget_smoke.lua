local root = assert(arg[1]):gsub("\\", "/")
local measure = arg[2] == "measure"
local w = dofile(root .. "/tools/tests/health_tick_world.lua").New(root, "Mainline")
local c, A3 = w.core, w.core.MSUF_Auras3
c.PublicGlobals.MSUF_EditState.active = true
c.ExportPublic("MSUF_UnitPreviewActive", true)
local EM, builds, build = A3.EditMode, 0, A3.BuildAuraLaneMetrics
A3.BuildAuraLaneMetrics = function(...)
    builds = builds + 1
    return build(...)
end
EM.RefreshUnit("target")
local group = assert(EM.groups.target.buff)
local icon, width, x = group._icons[1], group:GetWidth(), select(4, group:GetPoint())
local writes, active = 0, false
local methods = getmetatable(group).__index
for key, fn in pairs(methods) do
    if type(fn) == "function" then
        methods[key] = function(...)
            if active then writes = writes + 1 end
            return fn(...)
        end
    end
end
local function Bench()
    collectgarbage("collect")
    collectgarbage("stop")
    local kb, vm = collectgarbage("count"), 0
    builds, writes, active = 0, 0, true
    debug.sethook(function() vm = vm + 1 end, "", 1)
    for i = 1, 40 do EM.RefreshUnit("target") end
    debug.sethook()
    active = false
    local delta = collectgarbage("count") - kb
    collectgarbage("restart")
    print(string.format("A2 preview-refresh x40 vm=%d kb=%.3f native=%d metrics=%d", vm, delta, writes, builds))
end
Bench()
Bench()
if not measure then assert(builds == 0, "unchanged compiled lanes rebuilt metrics") end
assert(EM.groups.target.buff == group and group._icons[1] == icon and group:GetWidth() == width
    and select(4, group:GetPoint()) == x and group:IsShown(), "unchanged preview geometry/pool drift")
A3._runtimeConfigGen = (A3._runtimeConfigGen or 1) + 1
EM.RefreshUnit("target")
assert(builds > 0, "config generation did not refresh metrics")
EM.HideUnit("target")
assert(not group:IsShown())
EM.RefreshUnit("target")
assert(group:IsShown() and group._icons[1] == icon, "hide/show lost pooled icon")
local static = icon.CooldownText:GetText()
assert(A3.RefreshEditPreviewAnimation("target", 50))
assert(icon.CooldownText:GetText() ~= static, "fixture never animated its cooldown")
A3.RefreshEditPreview("target")
assert(icon.CooldownText:GetText() == static, "stopping animation did not restore the static preview")
c.PreviewAnimation.enabled, c.PreviewAnimation.elapsed = true, 1
EM.RefreshUnit("target")
local animated = icon.CooldownText:GetText()
c.PreviewAnimation.elapsed = 60
EM.RefreshUnit("target")
assert(icon.CooldownText:GetText() ~= animated, "native Edit Mode clock stopped advancing")
c.PreviewAnimation.enabled = false
EM.RefreshUnit("target")
assert(icon.CooldownText:GetText() == static, "native animation stop left animated pixels")
-- The real HUD mover resolves its current owner and writes only its displayed position.
local cfg = assert(A3.ResolveUnitFrameConfig("target"))
local source = assert(cfg.lanes.buff)
local savedX, savedY = source.x, source.y
local resolve, metrics = A3.ResolveOutlineLaneOffset, A3.OutlineLaneMetrics
local owner, resolved = nil, 0
A3.ResolveOutlineLaneOffset = function(frame, lane, x, y, zoom)
    if lane ~= source then return resolve(frame, lane, x, y, zoom) end
    assert(zoom == 1 and x == savedX and y == savedY, "HUD used a menu zoom or projected offsets twice")
    owner, resolved = frame, resolved + 1
    return x + 0.25, y - 0.25, true
end
A3.OutlineLaneMetrics = function(frame, lane, zoom)
    if lane == source then return 17, 19, 0, 2, 43, 19 end
    return metrics(frame, lane, zoom)
end
group._msufA3RefreshSignature = nil
EM.RefreshUnit("target")
local _, rel, _, appliedX, appliedY = group:GetPoint()
local bx, by = A3.AnchorOffset(source.anchor, rel:GetWidth(), rel:GetHeight())
local ax, ay = A3.AnchorOffset(source.anchor, 43, 19)
assert(resolved == 1 and owner == rel and appliedX == bx + savedX + 0.25 - ax
    and appliedY == by + savedY - 0.25 - ay, "HUD mover missed the snapped frame edge")
assert(icon:GetWidth() == 17 and icon:GetHeight() == 19 and group.Body:GetWidth() == 43,
    "HUD aura sample ignored the projected grid")
EM.RefreshUnit("target")
assert(resolved == 1 and source.x == savedX and source.y == savedY, "HUD warm repaint changed placement")
A3.ResolveOutlineLaneOffset, A3.OutlineLaneMetrics = resolve, metrics
print("PASS editmode_preview_budget_smoke")
