local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local w = World.Open(root, flavor, { page = "gameplay", beforeCore = function(world)
    world.env.TotemFrame = false
end })
local M, env, core = w.M, w.env, w.core
local gameplay = M.EnsureDB().gameplay
gameplay.enableCombatTimer = true
local chat = env.CreateFrame("Frame", nil, env.UIParent)
chat:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 5, 5)
chat:SetSize(294, 157)
env.ChatFrame1 = chat
core.MSUF_ApplyGameplayVisuals()
for _, section in pairs(M.cache.gameplay.sections) do
    if section._msuf2CollapsibleEntry then section._msuf2CollapsibleEntry.SetOpenImmediate(true) end
end
w:RunTimers()
M.Refresh(M.cache.gameplay.ctx)
local _, dropdown = M.RuntimeControlCatalog.FindBySettingKey("gameplay.combatTimerAnchor", "gameplay")
assert(dropdown, "Combat timer anchor dropdown missing")
dropdown._msuf2CommandAction.set("chat")
gameplay.combatOffsetX, gameplay.combatOffsetY = 3, 119
core.MSUF_ApplyGameplayVisuals()
local timer
for _, frame in ipairs(w.world.widgets.frames) do
    if frame:GetName() == "MSUF_CombatTimerFrame" then timer = frame break end
end
assert(timer, "Combat timer frame was not created")
local selfPoint, relative, relativePoint, x, y = timer:GetPoint()
assert(gameplay.combatTimerAnchor == "chat" and selfPoint == "CENTER"
    and relative == chat and relativePoint == "TOPRIGHT" and x == 3 and y == 119,
    "Combat timer did not anchor to the chat's top-right edge")
local mockAnchor = { GetCenter = function() return 100, 200 end,
    GetRight = function() return 150 end, GetTop = function() return 240 end }
local dragged = { GetCenter = function() return 155, 250 end }
local stored = {}
core.EditModeKinds.gameplay:applyDrag(dragged, stored, "x", "y", mockAnchor, false, nil, "TOPRIGHT")
assert(stored.x == 5 and stored.y == 10, "Combat timer drag did not store offsets from the chat corner")
dropdown._msuf2CommandAction.set("none")
core.MSUF_ApplyGameplayVisuals()
local _, resetAnchor, resetPoint = timer:GetPoint()
assert(resetAnchor == env.UIParent and resetPoint == "CENTER", "Combat timer kept the chat anchor after changing it")
print("PASS combat timer chat anchor, menu and drag: " .. flavor)
