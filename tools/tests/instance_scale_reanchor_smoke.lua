-- <root> [client]: use actual frame scales, not a remembered requested value.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local MenuWorld = dofile(root .. "/tools/tests/menu_core_world.lua")
local writes = 0
local h = Harness.New(root, flavor, { nativeLayout = true, beforeBoot = function(h)
    MenuWorld.ApplyCoreTocMetadata(h.world)
    MenuWorld.InstallNativeUnitInputs(h.world)
    h.env.MAX_BOSS_FRAMES = 5
    local native = h.widgets.Methods.SetScale
    h.widgets.Methods.SetScale = function(self, ...)
        writes = writes + 1
        return native(self, ...)
    end
    local load = h.world.LoadGraph
    function h.world:LoadGraph(addon, ...)
        if addon ~= "MidnightSimpleUnitFrames_Options" then return load(self, addon, ...) end
    end
end })
local env, core = h.env, h.core
assert(core.UF.Factory.SpawnAll(), "unit factory refused to spawn")
h:RunTimers()
local g = env.MSUF_DB.general
g.msufUiScale = 1
g.UIScale = { Enabled = true, Scale = 1 }
env.MSUF_ApplyMsufScale(1)
env.MSUF_SetGlobalUiScale(1, true)
h:RunTimers()
local listener
for _, frame in ipairs(h.widgets.frames) do
    local handler = frame.scripts and frame.scripts.OnEvent
    if handler and frame.events.PLAYER_ENTERING_WORLD
        and debug.getinfo(handler, "S").source:find("MSUF_UIScaleRuntime.lua", 1, true) then
        assert(not listener, "duplicate scale lifecycle listeners")
        listener = frame
    end
end
assert(listener, "saved global scale did not register lifecycle listener")
local function ScaleEvent(event)
    listener.scripts.OnEvent(listener, event or "PLAYER_ENTERING_WORLD")
end
local force, forces = core.UF.Factory.ForceReanchor, 0
core.UF.Factory.ForceReanchor = function(...)
    forces = forces + 1
    return force(...)
end
writes = 0
ScaleEvent()
h:RunTimers()
assert(writes == 0 and forces == 0, "unchanged scale wrote " .. writes .. " times and forced " .. forces .. " reanchors")

-- Native drift, a profile change, and a new frame each require a real repair.
local frame
core.UF.ForEachFrame(function(candidate) if not frame then frame = candidate end end)
assert(frame, "no unit frames built: " .. table.concat(h.eventErrors, "; "))
frame:SetScale(0.75)
writes = 0
ScaleEvent()
h:RunTimers()
assert(frame:GetScale() == 1 and forces == 1 and writes >= 1,
    "native frame scale drift was ignored: " .. tostring(frame:GetScale()) .. "/" .. forces .. "/" .. writes
        .. ": " .. table.concat(h.eventErrors, "; "))
g.msufUiScale = 1.25
ScaleEvent()
h:RunTimers()
assert(frame:GetScale() == 1.25 and forces == 2, "changed saved frame scale was ignored")
env.UIParent:SetScale(0.8)
ScaleEvent("DISPLAY_SIZE_CHANGED")
h:RunTimers()
assert(env.UIParent:GetScale() == 1 and forces == 3, "native global scale drift was ignored")
local each = core.UF.ForEachFrame
local newborn = env.CreateFrame("Frame")
core.UF.ForEachFrame = function(fn)
    each(fn)
    fn(newborn)
end
ScaleEvent()
h:RunTimers()
assert(newborn:GetScale() == 1.25 and forces == 4, "new frame was skipped by a cached scale")
core.UF.ForEachFrame = each

-- Explicit public applies retain their repair semantics even at the same scale.
env.MSUF_ApplyMsufScale(1.25)
h:RunTimers()
assert(forces == 5, "explicit scale repair stopped working")
env.MSUF_ApplyMsufScale(1.25)
core.MSUF2.MenuRuntime._quiesceScale(true)
h:EnterCombat()
h:RunTimers()
assert(forces == 5, "cancelled scale timer wrote during combat")
h:LeaveCombat()
h:RunTimers()
assert(forces >= 6, "cancelled reanchor was not replayed after combat")

local before = forces
h:Event("PLAYER_ENTERING_WORLD")
h:RunTimers()
assert(forces == before + 1, "world transition must retain exactly one forced native-anchor repair, got " .. (forces - before))
-- A resolution change can move anchors without changing any local scale.
before = forces
ScaleEvent("DISPLAY_SIZE_CHANGED")
h:RunTimers()
assert(forces == before + 1, "unchanged display scale still needs screen-geometry repair")
-- A world-entry scale apply during lockdown is deferred and replayed.
h:EnterCombat()
before, writes = forces, 0
ScaleEvent()
h:RunTimers()
assert(writes == 0 and forces == before, "world-entry scaling wrote in combat")
h:LeaveCombat()
h:RunTimers()
assert(forces == before + 1, "world-entry scale repair was lost or duplicated after combat")

-- Keep an external provider's actual moving/replaced frame linked through the
-- real proxy owner, even when the saved scale needs no repair at world entry.
local provider = env.CreateFrame("Frame", "InstanceTestAnchor", env.UIParent)
env.InstanceTestAnchor = provider
provider:SetSize(100, 80)
provider:SetPoint("CENTER", env.UIParent, "CENTER", 10, 20)
env.MSUF_DB.player.anchorFrameName = "InstanceTestAnchor"
env.MSUF_DB.player.point, env.MSUF_DB.player.relativePoint = "CENTER", "CENTER"
env.MSUF_DB.player.x, env.MSUF_DB.player.y = 0, 0
core.UF.Config.Refresh()
assert(core.UF.Factory.Apply("player"))
h:RunTimers()
local player = assert(core.UF.GetFrame("player"))
local proxy = assert(player._msufUnitExternalAnchorProxy, "external provider has no live proxy")
assert(proxy._msufExternalAnchorSource == provider)
local x, y = player:GetCenter()
provider:SetPoint("CENTER", env.UIParent, "CENTER", 110, 70)
before = forces
h:Event("PLAYER_ENTERING_WORLD")
h:RunTimers()
local movedX, movedY = player:GetCenter()
local ratio = provider:GetEffectiveScale() / player:GetEffectiveScale()
assert(math.abs(movedX - x - 100 * ratio) < 0.001 and math.abs(movedY - y - 50 * ratio) < 0.001,
    "unchanged-scale world entry lost native provider movement")
assert(forces == before + 1, "external provider movement duplicated world-entry repair")
local replacement = env.CreateFrame("Frame", "InstanceTestAnchor", env.UIParent)
env.InstanceTestAnchor = replacement
replacement:SetSize(120, 90)
replacement:SetPoint("CENTER", env.UIParent, "CENTER", 210, 120)
h:Event("PLAYER_ENTERING_WORLD")
h:RunTimers()
assert(proxy._msufExternalAnchorSource == replacement and proxy.allPoints == replacement,
    "world-entry repair retained the old external provider")
assert(#h.eventErrors == 0, table.concat(h.eventErrors, "\n"))
assert(#h.violations == 0, table.concat(h.violations, "\n"))
print("PASS instance_scale_reanchor_smoke " .. flavor .. ": unchanged, drift, new frame, explicit apply, combat replay and world repair")
