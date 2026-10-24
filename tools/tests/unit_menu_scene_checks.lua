-- Options owns the stage and interaction; the body is the engine frame.
return function(root, client)
assert(root and client)
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local SECRET = {}
local w = World.Open(root, client, { page = "home", tocMetadata = true, beforeCore = function(world)
 -- Real unit frames spawn here: the native power, formatter and class colour inputs they read.
 World.InstallNativeUnitInputs(world)
 world.env.issecretvalue = function(value) return value == SECRET end
end })
local env, core = w.env, w.core
local Preview = core.UFPreview
assert(type(core.UFPreviewAuras.DispelPreview) == "table"
 and type(core.UFPreviewAuras.DispelPreview.ReadOffsets) == "function"
 and type(core.UFPreviewAuras.DispelPreview.SymbolBounds) == "function", "dispel chrome must be locally bound")
local selected = "player"
local panel = env.CreateFrame("Frame", nil, env.UIParent)
panel._msufGetCurrentKey = function() return selected end
local box = Preview._BuildPreview(env.UIParent, panel, 900, 400)
assert(not box._unitSceneRoot, "scene built before first show")
World.FireVisibilityScripts(box)
box:Show()
box.canvas:SetSize(600, 260)
env.MSUF_DB.bars.showClassPower = true
w.M._msuf2ClassPowerPreviewSpecKey = "rogue_combo"
local checkedClassPower, checkedCastbar = false, false
for _, key in ipairs({ "player", "target", "focus", "targettarget", "focustarget", "pet", "pettarget", "boss", "arena" }) do
 selected = key
 env.MSUF_DB[key].showName = true
 Preview.Refresh(box, "SETTINGS")
 if core.UF.UnitScene.Normalize(key) then
  assert(box._unitScene, key .. ": Options has no engine unit scene")
  assert(box.mock._body == box._unitScene:Frame(), key .. ": body is not the scene frame")
  assert(box.mock.healthBar == box.mock._body.hpBar, key .. ": duplicate health painter")
  assert(box.mock.nameText == box.mock._body.nameText, key .. ": duplicate text painter")
  local body = box.mock._body
  if box.mock.cast:IsShown() then
   checkedCastbar = true
   assert(select(2, box.mock.cast:GetPoint(1)) == body, key .. ": castbar does not anchor to the scene frame")
   assert(math.abs(box.mock.cast:GetWidth() - math.floor(box._msufPreviewScene.castW * box._mockEffectiveScale + 0.5)) < 1e-6,
    key .. ": castbar geometry lost its independent scale")
  end
  if box.mock.classPower:IsShown() then
   checkedClassPower = true
   assert(select(2, box.mock.classPower:GetPoint(1)) == body, key .. ": class power does not anchor to the scene frame")
  end
 end
end
assert(checkedClassPower and checkedCastbar, "slot geometry assertions did not exercise both retained painters")
-- A power layer includes native sibling backgrounds/borders as well as the fill bar.
selected = "target"
env.MSUF_DB.target.powerBarBorderEnabled = true
Preview.Refresh(box, "SETTINGS")
local powerBody = box.mock._body
local powerBorder = powerBody.targetPowerBar.MSUFPowerBorderHost
assert(powerBody.powerBarBG and powerBody.powerBarBG:IsShown() and powerBorder and powerBorder:IsShown(), "power layer check did not exercise its native siblings")
box._unitScene:SetLayerFilter({ power = false })
assert(not powerBody.powerBarBG:IsShown() and not powerBorder:IsShown(), "power layer left its native background or border visible")
box._unitScene:SetLayerFilter(nil)
assert(powerBody.powerBarBG:IsShown() and powerBorder:IsShown(), "power layer did not restore its native siblings")
-- Status All retains the boss number and the static AFK timer without joining its live ledger.
Preview.statusPreviewMode = "all"
if core.UF.UnitScene.Normalize("boss") then
 selected = "boss"
 env.MSUF_DB.boss.showBossNumberIndicator = true
 Preview.Refresh(box, "SETTINGS")
 assert(box.mock.icons.bossNumber and box.mock.icons.bossNumber:GetText() == "1", "boss number sample was lost")
end
selected = "player"
env.MSUF_DB.player.statusAFKTimerEnabled = true
Preview.Refresh(box, "SETTINGS")
assert(box.mock.icons.statusAFKTimer and box.mock.icons.statusAFKTimer:GetText() == core.UFAFKTimer.SampleText(), "AFK timer sample was lost")
Preview.statusPreviewMode = "selected"
-- A drag at 3x zoom must move real engine text immediately by the same screen delta as its handle.
selected = "target"
env.MSUF_DB.target.showName, env.MSUF_DB.target.shortenName = true, false
box._manualZoom = 3
Preview.Refresh(box, "SETTINGS")
env.MSUF_UFCore_NotifyConfigChanged = function() end -- no live-frame factory in this menu geometry world
local text, handle = box.mock.nameText, box.handleName
if box.mock._body._msufNameClipFrame and box.mock._body._msufNameClipFrame:IsShown() then text = box.mock._body._msufNameClipFrame end
-- Exercise the native-region fallback used before a text rectangle is available.
core.UFPreviewCore.PlaceHandle(handle, text)
-- The widget stub does not resolve anchors. Sum their translations to observe an actual handle-following chain.
local function ScreenOffset(region, depth)
 if not (region and region.GetPoint) or (depth or 0) > 30 then return 0, 0 end
 local _, relative, _, x, y = region:GetPoint(1)
 local px, py = ScreenOffset(relative, (depth or 0) + 1)
 local scale = region:GetEffectiveScale()
 return px + (x or 0) * scale, py + (y or 0) * scale
end
local handleX, handleY = ScreenOffset(handle)
local _, _, _, x, y = text:GetPoint(1)
local cx, cy = 500, 400
env.GetCursorPosition = function() return cx, cy end
env.IsMouseButtonDown = function() return true end
env.IsControlKeyDown = function() return false end
handle:GetScript("OnMouseDown")(handle, "LeftButton")
local ratio = text:GetEffectiveScale() / box.mock:GetEffectiveScale()
cx, cy = cx + 30, cy + 18
box.dragFrame:GetScript("OnUpdate")(box.dragFrame, 0.016)
local _, _, _, nx, ny = text:GetPoint(1)
assert(math.abs((nx - x) * ratio - 30) < 1e-6 and math.abs((ny - y) * ratio - 18) < 1e-6,
 "zoomed text does not follow the handle's exact screen delta")
local movedHandleX, movedHandleY = ScreenOffset(handle)
assert(math.abs(movedHandleX-handleX-30)<1e-6 and math.abs(movedHandleY-handleY-18)<1e-6,
 "zoomed handle moved twice through its native text anchor")
local draggedX, draggedY = ScreenOffset(text)
box._unitSceneRoot:SetClock(0.75)
local tickingX, tickingY = ScreenOffset(text)
assert(math.abs(tickingX-draggedX)<1e-6 and math.abs(tickingY-draggedY)<1e-6, "animation repainted a dragged text at its old layout")
box._unitSceneRoot:SetClock(nil, true)
handle:GetScript("OnMouseUp")(handle, "LeftButton")
-- Right anchors store inward-positive X, but the real text must still follow the cursor to the right.
env.MSUF_DB.target.nameTextAnchor, env.MSUF_DB.target.directTextLayout = "TOPRIGHT", false
Preview.Refresh(box, "SETTINGS")
text = box.mock._body._msufNameClipFrame
if not (text and text:IsShown()) then text = box.mock.nameText end
x, y = select(4, text:GetPoint(1)), select(5, text:GetPoint(1))
ratio = text:GetEffectiveScale() / box.mock:GetEffectiveScale()
handle:GetScript("OnMouseDown")(handle, "LeftButton")
cx, cy = cx + 30, cy + 18
box.dragFrame:GetScript("OnUpdate")(box.dragFrame, 0.016)
nx, ny = select(4, text:GetPoint(1)), select(5, text:GetPoint(1))
assert(math.abs((nx-x)*ratio-30)<1e-6 and math.abs((ny-y)*ratio-18)<1e-6, "right-anchored text moved against its handle")
handle:GetScript("OnMouseUp")(handle, "LeftButton")
-- Style remains inspectable with its ordinary lane disabled and capped at zero.
selected = "player"
local model = core.MSUF_Auras3.MenuModel
model.WriteValue("player", "showBuffs", false)
model.WriteValue("player", "maxBuffs", 0)
core.MSUF2.unitAuraTabSelection = { player = "buff" }
core.MSUF2.unitAuraToolSelection = { player = { buff = "style" } }
Preview.Refresh(box, "SETTINGS")
local buff = box.mock._body._msufGFFrameAuraPreviewHosts.buff
assert(buff and buff:IsShown(), "disabled aura style lost its scene sample lane")
core.MSUF2.unitAuraToolSelection = nil
Preview.Refresh(box, "SETTINGS")
assert(not buff:IsShown(), "style sample remained after leaving its tool")
-- Custom-4 keeps Player Defensives player-only and Target DoTs on every supported hostile-unit page.
for _, key in ipairs({ "player", "target", "focus", "boss", "arena" }) do
 if core.UF.UnitScene.Normalize(key) then
  selected = key
  env.MSUF_DB[key].portraitMode = "LEFT"
  local custom = model.CustomContainer(key, 4, true)
  custom.enabled, custom.portraitIcon, custom.portraitPositionWhenDisabled = true, true, true
  custom.spellIDs, custom.customSpellIDs = "12345", { [12345] = true }
  core.MSUF2.unitAuraTabSelection = { [key] = "custom4" }
  core.MSUF2.unitAuraToolSelection = { [key] = { custom4 = "style" } }
  core.MSUF_Auras3.InvalidateUnitRuntimeConfig(key) -- raw fixture edits take the same invalidation edge as the Aura apply service
  Preview.Refresh(box, "SETTINGS")
  local body = box.mock._body
  local lanes = body._msufGFFrameAuraPreviewHosts
  local portraitKey = key == "player" and "defensivePortrait" or "targetDotPortrait"
  assert(lanes and lanes[portraitKey] and lanes[portraitKey]:IsShown(), key .. ": Custom-4 portrait sample was lost")
  assert(select(2, lanes[portraitKey]:GetPoint(1)) == body.MSUFPortraitHolder, key .. ": Custom-4 does not anchor to the native portrait")
  if key ~= "player" then assert(not (lanes.defensivePortrait and lanes.defensivePortrait:IsShown()), "Defensive Portrait escaped Player") end
 end
end
core.MSUF2.unitAuraTabSelection, core.MSUF2.unitAuraToolSelection = nil, nil
-- Exact live values and per-field fallback reach the scene, whose own painter reads no unit.
selected = "player"
env.MSUF_DB.player.showName, env.MSUF_DB.player.portraitMode, env.MSUF_DB.player.portraitRender = true, "LEFT", "2D"
local name, hp, maximum, exists = "Live Mirror", 123456, 900000, true
env.UnitExists = function(unit) return exists and unit == "player" end
env.UnitName = function() return name end
env.UnitClass = function() return "Mage", "MAGE" end
env.UnitIsPlayer = function() return true end
env.UnitHealth = function() return hp end
env.UnitHealthMax = function() return maximum end
env.UnitPower = function() return 47 end
env.UnitPowerMax = function() return 100 end
env.UnitPowerType = function() return 0, "MANA" end
env.UnitGetTotalAbsorbs = function() return 99 end
env.SetPortraitTexture = function(texture) texture:SetTexture(12345) end
Preview.Refresh(box, "SETTINGS")
local body = box.mock._body
assert(body.nameText:GetText() == "Live Mirror", "live name did not reach the scene")
assert(body.hpBar:GetValue() == hp and select(2, body.hpBar:GetMinMaxValues()) == maximum, "exact live HP range was lost")
assert(body.targetPowerBar:GetValue() == 47 and body._msufTextRuntime.healthAbsorb == 99, "exact power/absorb was lost")
assert(body.portrait:GetTexture() == 12345, "live portrait snapshot was lost")
local sample = box._unitScene:Sample()
assert(sample.class == "MAGE" and sample.player, "live class was lost")
name, hp, maximum = SECRET, SECRET, SECRET
-- Only the snapshot read is secret; the unrelated persistent-menu character key stays a plain string.
local secretNameRead = false
env.UnitName = function()
 if not secretNameRead then secretNameRead = true; return SECRET end
 return "Live Mirror"
end
Preview.Refresh(box, "SETTINGS")
assert(body.nameText:GetText() == Preview.Model.UNIT_DATA.player.name, "secret name did not use its field fallback")
assert(body.hpBar:GetValue() == math.floor(Preview.Model.UNIT_DATA.player.hp * core.UF.UnitScene.HEALTH_MAX + 0.5),
 "secret HP did not use its field fallback")
assert(body.targetPowerBar:GetValue() == 47, "a secret HP field discarded usable live power")
maximum = 900000
env.UnitGetTotalAbsorbs = function() return 0 end
Preview.Refresh(box, "SETTINGS")
assert(select(2, body.hpBar:GetMinMaxValues()) == maximum, "secret current HP discarded a readable live maximum")
assert(body._msufTextRuntime.healthAbsorb == maximum * 0.10, "zero live absorb did not use the visible sample shield")
exists = false
Preview.Refresh(box, "SETTINGS")
assert(box._unitScene:Sample().hpMax == nil and body.nameText:GetText() == Preview.Model.UNIT_DATA.player.name,
 "missing unit retained a stale snapshot")
-- Animation keeps the live maximum, even when its fraction replaces the real current value.
name, hp, maximum, exists = "Live Mirror", 123456, 900000, true
box._animationEnabled, box._animationElapsed = true, 0.4
Preview.Refresh(box, "UNIT_PREVIEW_ANIMATE")
box._animationElapsed = 1.1
local nativeTextSlots, paintedLiveMaximum = core.UFText.UpdateTextSlots, false
core.UFText.UpdateTextSlots = function(slots, count, current, maxValue, ...)
 if slots == body._msufTextRuntime.healthSlots then
  assert(maxValue == maximum, "animation formatted health on the old sample maximum")
  paintedLiveMaximum = true
 end
 return nativeTextSlots(slots, count, current, maxValue, ...)
end
assert(Preview.RefreshAnimation(box), "unit scene has no light animation path")
core.UFText.UpdateTextSlots = nativeTextSlots
assert(paintedLiveMaximum, "animation bypassed the native health value texts")
assert(select(2, body.hpBar:GetMinMaxValues()) == maximum, "animation lost the live maximum scale")
assert(body.hpBar:GetValue() ~= hp, "animation did not drive the real health values")
box._animationEnabled = false
local driver = assert(box._msufLiveStateDriver)
assert(driver.events.UNIT_HEALTH, "unit live-state driver lost its listener")
w.world:EnterCombat()
Preview.Refresh(box, "SETTINGS")
for event in pairs(driver.events) do assert(event == "PLAYER_REGEN_ENABLED", "live driver kept a combat listener: " .. event) end
assert(not body:IsShown(), "unit scene stayed visible in combat")
w.world:LeaveCombat()
box:Hide()
assert(not box._unitSceneRoot.host.active and not box._unitScene:IsActive(), "hidden box retained an active scene")
for event in pairs(driver.events) do error("hidden box retained listener " .. event) end
box:Show()
Preview.Refresh(box, "SHOW")
assert(box.mock._body == body, "reopening replaced the scene frame")
box:Hide()
-- The removed Options painters cannot silently return beside the engine scene.
local function Read(path)
 local file = assert(io.open(root .. "/" .. path, "rb")); local text = file:read("*a"); file:close(); return text
end
local prefix = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/"
local render = Read(prefix .. "MSUF_Menu2_UnitPreview_Render.lua")
for _, painter in ipairs({ "Stage.RenderHealth", "Stage.RenderPowerBar", "Stage.PaintValueTexts", "Stage.RenderPortrait", "Stage.RenderAurasAndStatus" }) do
 assert(not render:find("function " .. painter, 1, true), "duplicate Options body painter remains: " .. painter)
end
assert(not Read(prefix .. "MSUF_Menu2_UnitPreview_View.lua"):find('CreateFrame("StatusBar"', 1, true), "Options constructs a second unit bar")
assert(not Read(prefix .. "MSUF_Menu2_UnitPreview_Auras.lua"):find("CreateTexture", 1, true), "Options constructs aura body textures")
assert(not io.open(root .. "/" .. prefix .. "MSUF_Menu2_UnitPreview_Status.lua", "rb"), "duplicate status renderer remains")
print("unit menu scene checks: ok (" .. client .. ")")
end
