-- unit_preview_scene_lifecycle_smoke.lua <repoRoot> [flavor]
--
-- The lifecycle of static unit preview scenes (root:Unit on GF.NewPreviewScene). Pins that
--   * nothing exists at load and a new root or scene object creates no frame, timer, script or event;
--   * a closed root is silent: no subscription, no timer, no frame shown, whatever signal arrives, and a scene asked to
--     show while it is closed only remembers that it was asked;
--   * an open root answers a burst of config signals with one repaint per wanted scene, on the next frame;
--   * combat hides every scene at once and touches neither a live header nor a live frame, no work is done in combat,
--     and the end of combat brings back exactly the scenes that were wanted (an explicit hide is not undone);
--   * a repaint creates no frame and no region: the scene's frame and pools are reused, also across close and reopen;
--     the heap cost of a repaint stays within its budget;
--   * a new sample changes the paint, the unit's own restores it, and a scene shows its static sample whatever the shared
--     preview animation does;
--   * releasing a root leaves nothing behind that listens, repaints or holds a timer.
-- Boots the real core through tools/tests/unit_scene_world.lua. Plain Lua 5.1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local World = dofile(root .. "/tools/tests/unit_scene_world.lua")

local function Check(condition, message)
    if not condition then error("unit_preview_scene_lifecycle_smoke " .. flavor .. ": " .. message, 2) end
end

local w = World.New(root, flavor)
local h, UF, GF, env = w.h, w.UF, w.GF, w.env
w:Enable()
local MSUF = assert(env.MSUF, "no MSUF namespace in the sandbox")
local Bus = assert(MSUF.EventBus, "no event bus")
local timers = h.widgets.timers
local U = UF.UnitScene
Check(type(U) == "table", "the core has no unit scene module")

local function Queued()
    local count = 0
    for _, entry in ipairs(timers) do if not entry.cancelled then count = count + 1 end end
    return count
end
local function Subscribed(event, key)
    local ev = Bus.handlers[event]
    return ev ~= nil and ev.index[key] ~= nil
end
local function Regions(frame)
    local count = 1 + #(frame.regions or {})
    for _, child in ipairs(frame.children or {}) do count = count + Regions(child) end
    return count
end
local function FamilyOf(unit)
    if U.SAMPLES[unit] then return unit end
    return (unit:gsub("%d+$", ""))
end
-- A repaint is the apply of one spec: count them through the one entry point the scenes use.
local applies = 0
local applySceneSpec = UF.ApplySceneSpec
UF.ApplySceneSpec = function(...)
    applies = applies + 1
    return applySceneSpec(...)
end

local units = { "player", "target", "targettarget", "pet" }
for index = #units, 1, -1 do if not UF.IsManagedUnit(units[index]) then table.remove(units, index) end end
if UF.IsManagedUnit("boss1") then units[#units + 1] = "boss1" end
Check(#units >= 4, "too few units to test with")

h:RunTimers()
Check(Queued() == 0, "the timer queue was not idle before the test")

---------------------------------------------------------------------------
-- 1. Nothing at load; a root and a scene object create nothing.
---------------------------------------------------------------------------
local framesAtLoad = #h.widgets.frames
local host = env.CreateFrame("Frame", nil, env.UIParent)
host:SetSize(400, 300)
local rootA = GF.NewPreviewScene(host)
local key = rootA.eventKey
local framesWithRoot = #h.widgets.frames
local scenes = {}
for _, unit in ipairs(units) do scenes[unit] = rootA:Unit(unit) end
Check(#h.widgets.frames == framesWithRoot, "making unit scene objects built a frame")
Check(Queued() == 0, "making a root and its scenes queued a timer")
for _, unit in ipairs(units) do
    Check(not scenes[unit]:IsActive() and not scenes[unit].frame, unit .. ": a new scene has a frame or shows")
end

---------------------------------------------------------------------------
-- 2. Closed: nothing shows, nothing listens, a scene asked to show remembers it.
---------------------------------------------------------------------------
Check(not Subscribed("CONFIG_APPLIED", key) and not Subscribed("PLAYER_REGEN_ENABLED", key)
    and not Subscribed("PLAYER_REGEN_DISABLED", key), "a closed root subscribed")
for _, unit in ipairs(units) do
    Check(scenes[unit]:Show() == false, unit .. ": a scene of a closed root reported that it showed")
    Check(scenes[unit].want == true and not scenes[unit]:IsActive() and not scenes[unit].frame,
        unit .. ": a scene of a closed root built a frame or forgot it was asked")
    Check(scenes[unit]:RefreshData() == false and scenes[unit]:Refresh() == false, unit .. ": a closed scene repainted")
end
Check(rootA:Request("test") == false and Queued() == 0, "a closed root queued a repaint")
Bus:Publish("CONFIG_APPLIED", "MSUF_Test")
Check(Queued() == 0 and applies == 0, "a config signal reached a closed root")

---------------------------------------------------------------------------
-- 3. Open: scenes show, the signals are subscribed, a burst of signals is one repaint per wanted scene.
---------------------------------------------------------------------------
local paints = {}
local hostOpts = rootA.host.opts
local originalPaint = hostOpts.paint
hostOpts.paint = function(host_, reason)
    paints[#paints + 1] = reason
    return originalPaint(host_, reason)
end
Check(rootA:Activate() == true and rootA:IsActive(), "activate failed")
h:RunTimers()
Check(#paints == 1 and paints[1] == "activate", "activate painted " .. #paints .. " times")
for _, unit in ipairs(units) do
    Check(scenes[unit]:IsActive() and scenes[unit].frame:IsShown(), unit .. ": activate did not show the wanted scene")
end
Check(applies == #units, "activate applied " .. applies .. " specs for " .. #units .. " scenes")
Check(Subscribed("CONFIG_APPLIED", key) and Subscribed("PLAYER_REGEN_ENABLED", key) and Subscribed("PLAYER_REGEN_DISABLED", key),
    "an active root did not subscribe")
applies = 0
for _ = 1, 6 do Bus:Publish("CONFIG_APPLIED", "MSUF_Test") end
Check(Queued() == 1, "six config signals queued " .. Queued() .. " repaints, not one")
Check(applies == 0 and #paints == 1, "a config signal repainted before the next frame")
h:RunTimers()
Check(#paints == 2 and paints[2] == "config" and applies == #units, "the coalesced repaint did not run once per wanted scene (" .. applies .. ")")
Check(Queued() == 0, "an open root keeps a timer")

-- The lockdown can begin before any scene heard of it (the event comes first, the lockdown just after): a scene that is
-- still shown does no work from the moment the client says it is in combat.
do
    local scene = scenes[units[1]]
    Check(scene:IsActive(), "the control scene is not shown")
    applies = 0
    h.widgets:SetCombat(true)
    Check(scene:Refresh() == false and scene:RefreshData() == false and scene:SetSample({ hp = 0.1 }) == false
        and scene:Show() == false, "a scene shown at the start of the lockdown painted")
    Check(applies == 0, "a scene applied its spec during the lockdown")
    h.widgets:SetCombat(false)
    scene:SetSample(nil)
    applies = 0
end

---------------------------------------------------------------------------
-- 4. Combat: scenes hide at once, nothing is touched, nothing is done, the end brings back the wanted ones.
---------------------------------------------------------------------------
-- A live frame of the same token, in the unit index. It listens to the combat edges itself, so its state after a combat
-- cycle is what a cycle does to a live frame; two cycles settle it, and the cycle with the scenes open must leave it there.
local liveUnit = units[1]
local liveBefore = UF.frames[liveUnit]
local live = w:LiveFrame(liveUnit, U.SAMPLES[FamilyOf(liveUnit)], "MSUF_" .. liveUnit, true)
w:Unmodel()
local function Cycle()
    h:EnterCombat()
    h:RunTimers()
    h:LeaveCombat()
    h:RunTimers()
end
rootA:Deactivate()
Cycle()
Cycle()
local digest = World.Digest(live)
Cycle()
Check(World.Digest(live) == digest, "the control: a combat cycle does not settle on a live frame")
rootA:Activate()
h:RunTimers()
local handoffs = 0
do
    local original = assert(GF.ApplyBlizzardGroupFrameOwnership, "the header pass no longer ends in the ownership handoff")
    GF.ApplyBlizzardGroupFrameOwnership = function(...)
        handoffs = handoffs + 1
        return original(...)
    end
end
scenes[units[2]]:Hide()
Check(scenes[units[2]].want == nil and not scenes[units[2]]:IsActive(), "an explicit hide kept the wanted state")
applies = 0
h:EnterCombat()
for _, unit in ipairs(units) do
    Check(not scenes[unit]:IsActive() and not scenes[unit].frame:IsShown(), unit .. ": combat left a scene visible")
end
Check(handoffs == 0, "combat with only unit scenes open rebuilt the live headers (" .. handoffs .. " handoffs)")
Check(rootA.host.active == true and scenes[units[1]].want == true, "combat made the root forget its scenes")
local before = #paints
Check(scenes[units[1]]:Show() == false and scenes[units[1]]:Refresh() == false and scenes[units[1]]:RefreshData() == false
    and scenes[units[1]]:SetSample({ hp = 0.1 }) == false, "a scene painted during combat")
scenes[units[1]]:SetSample(nil)
Bus:Publish("CONFIG_APPLIED", "MSUF_Test")
h:RunTimers()
Check(#paints == before and applies == 0, "a repaint ran during combat")
Check(UF.frames[liveUnit] == live, "combat changed the unit index")
h:LeaveCombat()
h:RunTimers()
Check(#paints == before + 1 and paints[#paints] == "regen", "combat end did not request one repaint")
for _, unit in ipairs(units) do
    if unit == units[2] then
        Check(not scenes[unit]:IsActive(), unit .. ": combat end showed a scene the owner had hidden")
    else
        Check(scenes[unit]:IsActive() and scenes[unit].frame:IsShown(), unit .. ": combat end did not bring the scene back")
    end
end
h:EnterCombat()
h:LeaveCombat()
h:RunTimers()
Check(World.Digest(live) == digest, "a combat cycle with the scenes open changed the live frame of a scene's token")
UF.frames[liveUnit] = liveBefore
scenes[units[2]]:Show()

---------------------------------------------------------------------------
-- 5. A repaint creates no frame and no region; the heap cost stays in budget.
---------------------------------------------------------------------------
-- Measured per repaint with the collector stopped: a full refresh recompiles the unit's spec into the scene's own table
-- (about 40 to 60 KB), a data repaint writes the sample into the regions (about 8 KB, the strings the slot writers build).
local REFRESH_KB, DATA_KB = 80, 12
local REPAINTS = 10
for _, unit in ipairs(units) do
    local scene = scenes[unit]
    local frame = scene.frame
    local regionsBefore, framesBefore = Regions(frame), #h.widgets.frames
    -- Collection shrinks the VM stack; regrow it so the first deep call is not counted as the repaint's.
    local function Regrow(depth)
        local a, b, c, d = 1, 2, 3, 4
        if depth > 0 then return Regrow(depth - 1) + a + b + c + d end
        return 0
    end
    collectgarbage("collect")
    collectgarbage("stop")
    Regrow(200)
    local start = collectgarbage("count")
    for _ = 1, REPAINTS do scene:Refresh() end
    local refreshed = (collectgarbage("count") - start) / REPAINTS
    start = collectgarbage("count")
    for _ = 1, REPAINTS do scene:RefreshData() end
    local painted = (collectgarbage("count") - start) / REPAINTS
    collectgarbage("restart")
    Check(Regions(frame) == regionsBefore and #h.widgets.frames == framesBefore, unit .. ": a repaint created a frame or region")
    Check(scene.frame == frame, unit .. ": a repaint replaced the scene's frame")
    Check(refreshed <= REFRESH_KB, unit .. ": a full refresh costs " .. string.format("%.1f", refreshed) .. " KB (budget " .. REFRESH_KB .. ")")
    Check(painted <= DATA_KB, unit .. ": a data repaint costs " .. string.format("%.1f", painted) .. " KB (budget " .. DATA_KB .. ")")
end
-- Close and reopen reuse the frames.
local frameOf = {}
for _, unit in ipairs(units) do frameOf[unit] = scenes[unit].frame end
local framesBeforeCycle = #h.widgets.frames
rootA:Deactivate()
h:RunTimers()
for _, unit in ipairs(units) do
    Check(not scenes[unit]:IsActive() and not frameOf[unit]:IsShown(), unit .. ": deactivate left a scene shown")
end
Check(not Subscribed("CONFIG_APPLIED", key) and not Subscribed("PLAYER_REGEN_ENABLED", key)
    and not Subscribed("PLAYER_REGEN_DISABLED", key), "deactivate kept a subscription")
Check(Queued() == 0, "a deactivated root keeps a timer")
local quiet, quietApplies = #paints, applies
Bus:Publish("CONFIG_APPLIED", "MSUF_Test")
h:EnterCombat()
h:LeaveCombat()
h:RunTimers()
Check(#paints == quiet and applies == quietApplies and Queued() == 0, "a deactivated root repainted")
Check(scenes[units[1]]:Show() == false and not scenes[units[1]]:IsActive(), "a scene of a deactivated root showed")
Check(rootA:Activate() == true, "re-activate failed")
h:RunTimers()
for _, unit in ipairs(units) do
    Check(scenes[unit].frame == frameOf[unit] and scenes[unit]:IsActive(), unit .. ": re-activate did not bring the scene back on its own frame")
end
Check(#h.widgets.frames == framesBeforeCycle, "close and reopen created frames")

---------------------------------------------------------------------------
-- 6. The sample changes the paint; the shared preview animation does not.
---------------------------------------------------------------------------
do
    local unit = units[1]
    local scene = scenes[unit]
    local frame = scene.frame
    local base = U.SAMPLES[FamilyOf(unit)]
    local function Fill() return frame.hpBar.value / (frame.hpBar.maximum - (frame.hpBar.minimum or 0)) end
    Check(math.abs(Fill() - base.hp) < 1e-6, "the scene does not show the unit's static sample hp")
    local nameBefore = frame.nameText and frame.nameText.text
    local colorBefore = frame.hpBar.color and frame.hpBar.color[1]
    Check(scene:SetSample({ hp = 0.25, name = "Someone", class = "PRIEST", player = true }) == true, "a new sample did not repaint")
    Check(math.abs(Fill() - 0.25) < 1e-6, "a new sample did not change the health bar")
    Check(frame.nameText == nil or frame.nameText.text == "Someone", "a new sample did not change the name")
    Check(frame.hpBar.color[1] ~= colorBefore or base.class == "PRIEST", "a new class did not change the health colour")
    Check(frame.nameText == nil or frame.nameText.text ~= nameBefore or nameBefore == "Someone", "the name did not change")
    Check(scene:SetSample(nil) == true and math.abs(Fill() - base.hp) < 1e-6, "clearing the sample did not restore the unit's own")
    -- Static: an animation that is on, and a sampler that is asked, change nothing.
    local PA = assert(MSUF.PreviewAnimation, "no shared preview animation")
    local isEnabled, sampler, asked = PA.IsEnabled, env.MSUF_GetPreviewAnimationFrameState, 0
    PA.IsEnabled = function() return true end
    env.MSUF_GetPreviewAnimationFrameState = function(_, _, _, state)
        asked = asked + 1
        state.hpPct, state.powerPct = 0.5, 0.5
        return state
    end
    scene:RefreshData()
    scene:Refresh()
    h:RunTimers()
    PA.IsEnabled, env.MSUF_GetPreviewAnimationFrameState = isEnabled, sampler
    Check(asked == 0 and math.abs(Fill() - base.hp) < 1e-6, "a scene followed the shared preview animation")
    Check(Queued() == 0, "an open root keeps a timer after repaints")
end

---------------------------------------------------------------------------
-- 7. Re-parenting follows the owner; release leaves nothing that listens or repaints.
---------------------------------------------------------------------------
local mover = env.CreateFrame("Frame", nil, env.UIParent)
rootA:SetParent(mover)
for _, unit in ipairs(units) do
    Check(scenes[unit].frame:GetParent() == mover, unit .. ": re-parenting the root did not move the scene")
end
-- Native preview effects can own pulse/glow registrations: release must stop them, not merely hide an ancestor.
local effects = MSUF.MSUF_Auras3 and MSUF.MSUF_Auras3.SpellIndicators
local effectStops = 0
if effects and effects.HidePreviewFrameEffect then
    local stopEffect = effects.HidePreviewFrameEffect
    effects.HidePreviewFrameEffect = function(owner)
        effectStops = effectStops + 1
        return stopEffect(owner)
    end
    scenes[units[1]].frame._msufSceneEffectOwner = env.CreateFrame("Frame", nil, scenes[units[1]].frame)
end
rootA:Release()
h:RunTimers()
if effects and effects.HidePreviewFrameEffect then Check(effectStops > 0, "release retained native effect registrations") end
for _, unit in ipairs(units) do
    Check(not scenes[unit]:IsActive() and not frameOf[unit]:IsShown(), unit .. ": release left a scene shown")
end
Check(not Subscribed("CONFIG_APPLIED", key) and not Subscribed("PLAYER_REGEN_ENABLED", key)
    and not Subscribed("PLAYER_REGEN_DISABLED", key), "release kept a subscription")
Check(Queued() == 0, "a released root keeps a timer")
local sealed = applies
Bus:Publish("CONFIG_APPLIED", "MSUF_Test")
h:EnterCombat()
h:LeaveCombat()
h:RunTimers()
Check(applies == sealed and Queued() == 0, "a released root repainted")
GF.HidePreviewsForCombat()
Check(rootA:Unit(units[1]) ~= scenes[units[1]], "a released root reused a released scene")

print("unit_preview_scene_lifecycle_smoke: PASS (" .. flavor .. ")")
