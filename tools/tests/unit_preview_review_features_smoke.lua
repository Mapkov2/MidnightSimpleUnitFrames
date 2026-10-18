-- Restored Options preview features, through the real menu and engine scene.
local root, client, only = assert(arg[1]), arg[2] or "Mainline", arg[3]
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local w = World.Open(root, client, { page = "home" })
local env, core = w.env, w.core
local Preview, A3 = core.UFPreview, core.MSUF_Auras3
local model, selected = A3.MenuModel, "player"
local panel = env.CreateFrame("Frame", nil, env.UIParent)
panel._msufGetCurrentKey = function() return selected end
local box = Preview._BuildPreview(env.UIParent, panel, 900, 400)
World.FireVisibilityScripts(box)
box:Show()
box.canvas:SetSize(600, 260)
local function Refresh()
 A3.InvalidateUnitRuntimeConfig(selected)
 Preview.Refresh(box, "SETTINGS")
 return box.mock._body
end
local function Icons(body, key)
 local icons = {}
 local host = assert(body._msufGFFrameAuraPreviewHosts[key], key .. ": missing lane")
 for _, visual in ipairs(body._msufGFFrameAuraPreviews or {}) do
  if visual:IsShown() and select(2, visual:GetPoint(1)) == host then icons[#icons + 1] = visual end
 end
 assert(#icons >= 2, key .. ": expected both sample slots")
 return icons
end
local function Color(texture, r, g, b, a)
 local cr, cg, cb, ca = texture:GetVertexColor()
 assert(math.abs(cr-r)<1e-6 and math.abs(cg-g)<1e-6 and math.abs(cb-b)<1e-6 and math.abs(ca-a)<1e-6,
  "reminder sample lost its tint/opacity")
end
if not only or only == "marker" then
 selected = "target"
 model.WriteValue(selected, "showBuffs", true)
 model.WriteValue(selected, "maxBuffs", 4)
 model.WriteValue(selected, "buffShowStealable", true)
 for _, style in ipairs({ "ICON", "BORDER", "BORDER_ICON" }) do
  model.WriteValue(selected, "buffStealableStyle", style)
  local icons = Icons(Refresh(), "buff")
  local marker = icons[1]._stealableMarker
  assert(marker and marker:IsShown(), style .. ": stealable marker missing from buff slot 1")
  assert(not (icons[2]._stealableMarker and icons[2]._stealableMarker:IsShown()), "stealable marker escaped slot 1")
  local expected = icons[1]:CreateTexture(nil, "OVERLAY")
  if style == "ICON" then
   assert(marker.atlas == "RaidFrame-Icon-DebuffMagic", "stealable ICON lost the native Magic atlas")
   assert(marker:GetWidth() == math.max(7, math.floor(icons[1]:GetWidth()*.42+.5)), "stealable ICON size drifted")
  else
   if not A3.ApplyAuraDispelPreview(expected, icons[1], icons[1]:GetWidth(),
    style == "BORDER" and "BORDER" or "SYMBOL", box.mock._body._msufSceneAuraLanes.buff.iconShape, "Magic", false) then
    expected:SetAtlas(style == "BORDER" and "ui-debuff-border-magic-noicon" or "ui-debuff-border-magic-icon", false)
   end
   assert(marker.atlas == expected.atlas and marker:GetTexture() == expected:GetTexture(), "stealable border/symbol drifted from Magic painter")
  end
 end
 model.WriteValue(selected, "buffShowStealable", false)
 local icons = Icons(Refresh(), "buff")
 assert(not icons[1]._stealableMarker:IsShown(), "disabled stealable marker remained in pooled icon")
 model.WriteValue(selected, "showBuffs", false)
 Refresh()
 model.WriteValue(selected, "showBuffs", true)
 model.WriteValue(selected, "buffShowStealable", true)
 assert(Icons(Refresh(), "buff")[1]._stealableMarker:IsShown(), "stealable marker did not return after lane restore")
end
if not only or only == "reminder" then
 selected = "player"
 for index = 1, 4 do
  local custom = model.CustomContainer(selected, index, true)
  custom.enabled, custom.spellIDs, custom.customSpellIDs = true, "12345,12346", { [12345] = true, [12346] = true }
  custom.placed = custom.placed or {}
  local placed = custom.placed
  placed.reminderEnabled, placed.reminderColor, placed.reminderAlpha = true, { .2, .4, .6 }, .35
  core.MSUF2.unitAuraTabSelection = { player = "custom" .. index }
  core.MSUF2.unitAuraToolSelection = { player = { ["custom" .. index] = "style" } }
  local icons = Icons(Refresh(), "custom" .. index)
  assert(icons[2]._texture.desaturated == true, "missing reminder sample is not desaturated")
  Color(icons[1]._texture, 1, 1, 1, 1)
  Color(icons[2]._texture, .2, .4, .6, .35)
  box._unitSceneRoot:SetClock(.7)
  Color(icons[2]._texture, .2, .4, .6, .35)
  box._unitSceneRoot:SetClock(nil, true)
  placed.reminderDesaturate = false
  icons = Icons(Refresh(), "custom" .. index)
  assert(icons[2]._texture.desaturated == false, "reminder ignored explicit desaturate=false")
  placed.reminderEnabled = false
  icons = Icons(Refresh(), "custom" .. index)
  assert(icons[2]._texture.desaturated == false, "pooled icon retained reminder desaturation")
  Color(icons[2]._texture, 1, 1, 1, 1)
 end
end
if not only or only == "bounds" then
 Refresh()
 box.layerVisibility.bounds, box.layerVisibility.guides = true, false
 core.UFPreviewCore.ApplyLayerVisibility(box)
 assert(box.mock.sizeTag:IsShown(), "Bounds size tag incorrectly depends on Guides")
 box.layerVisibility.bounds, box.layerVisibility.guides = false, true
 core.UFPreviewCore.ApplyLayerVisibility(box)
 assert(not box.mock.sizeTag:IsShown(), "size tag remained after Bounds was disabled")
end
if not only or only == "absorb" then
 env.UnitExists = function() return true end
 env.UnitHealthMax = function() return 900000 end
 env.UnitHealth = function() return 500000 end
 local amount = 0
 env.UnitGetTotalAbsorbs = function() return amount end
 for _, key in ipairs({ "player", "pet", "arena" }) do
  if core.UF.UnitScene.Normalize(key) then
   selected = key
   env.MSUF_DB.general.enableAbsorbBar = true
   local body = Refresh()
   assert(box._unitScene:Sample().absorb == .10 and body._msufTextRuntime.healthAbsorb == 90000,
    key .. ": zero live absorb blanked the sample shield")
   amount = 45000
   body = Refresh()
   assert(body._msufTextRuntime.healthAbsorb == amount, key .. ": positive live absorb lost its exact value")
   amount = 0
  end
 end
end
box:Hide()
print("unit_preview_review_features_smoke: PASS (" .. client .. ", " .. (only or "all") .. ")")
