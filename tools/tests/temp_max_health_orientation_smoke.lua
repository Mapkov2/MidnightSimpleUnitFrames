-- Temporary max health overlay follows the health bar's fill axis.
-- Health.Apply turns the health bar VERTICAL when Fill Direction is vertical
-- (spec.health.vertical from verticalFillBars, MSUF_UF_Config.lua). The overlay
-- covers the reduced part of the max health at the far end of the fill, so it
-- must share that axis; reverse then picks the far end within the axis.
-- Loads the real MSUF_UF_Elements_TempMaxHealth.lua.
-- Usage: lua tools/tests/temp_max_health_orientation_smoke.lua <repoRoot>
local root = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

-- StatusBar/Texture model: only the methods the client has; a call to anything
-- else raises. A StatusBar starts HORIZONTAL and not reversed, as in the client.
local Widget = {}
local WidgetMT = { __index = Widget }
local function NewWidget(kind)
  return setmetatable({ kind = kind, orientation = "HORIZONTAL", reverse = false, level = 3, shown = true }, WidgetMT)
end
function Widget:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
function Widget:SetValue(value) self.value = value end
function Widget:SetStatusBarTexture(texture) self.texture = texture end
function Widget:GetStatusBarTexture() self.fill = self.fill or NewWidget("Texture"); return self.fill end
function Widget:SetStatusBarColor(r, g, b, a) self.color = { r, g, b, a } end
function Widget:EnableMouse(enabled) self.mouse = enabled end
function Widget:CreateTexture() return NewWidget("Texture") end
function Widget:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function Widget:SetAllPoints(target) self.anchor = target end
function Widget:ClearAllPoints() self.anchor = nil end
function Widget:SetOrientation(orientation)
  assert(orientation == "HORIZONTAL" or orientation == "VERTICAL", "bad orientation " .. tostring(orientation))
  self.orientation = orientation
end
function Widget:GetOrientation() return self.orientation end
function Widget:SetReverseFill(reverse) self.reverse = reverse == true end
function Widget:GetReverseFill() return self.reverse end
function Widget:SetFrameLevel(level) self.level = level end
function Widget:GetFrameLevel() return self.level end
function Widget:Show() self.shown = true end
function Widget:Hide() self.shown = false end
_G.CreateFrame = function(kind) return NewWidget(kind) end
_G.GetUnitTotalModifiedMaxHealthPercent = function() return 0.25 end

local UF = { elements = {} }
UF.RegisterElement = function(name, element) UF.elements[name] = element end
local MSUF = { UF = UF }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_TempMaxHealth.lua"))(
  "MidnightSimpleUnitFrames", MSUF)
local TempMaxHealth = assert(UF.elements.TempMaxHealth, "TempMaxHealth did not register")

local failures = 0
local function Check(ok, message)
  if not ok then
    failures = failures + 1
    print("FAIL " .. message)
  end
end

local function Spec(vertical, reverse)
  return {
    health = { vertical = vertical, reverse = reverse },
    tempMaxHealth = { enabled = true },
  }
end

local frame = { hpBar = NewWidget("StatusBar") }
local CASES = {
  -- Fill Direction:   vertical, reverse, expected overlay axis, expected overlay reverse
  { "left to right", false, false, "HORIZONTAL", true },
  { "bottom to top", true, false, "VERTICAL", true },
  { "top to bottom", true, true, "VERTICAL", false },
  { "right to left", false, true, "HORIZONTAL", false },
  { "back to bottom to top", true, false, "VERTICAL", true },
}
for _, case in ipairs(CASES) do
  local label, vertical, reverse, axis, overlayReverse = case[1], case[2], case[3], case[4], case[5]
  local spec = Spec(vertical, reverse)
  frame.MSUFSpec = spec
  TempMaxHealth.Apply(frame, spec)
  local bar = assert(frame.tempMaxHealthBar, "overlay bar missing")
  Check(bar.orientation == axis, ("%s: overlay axis %s, expected %s"):format(label, bar.orientation, axis))
  Check(bar.reverse == overlayReverse, ("%s: overlay reverse %s, expected %s")
    :format(label, tostring(bar.reverse), tostring(overlayReverse)))
  Check(bar.anchor == frame.hpBar, label .. ": overlay is not anchored on the health bar")
end

if failures > 0 then error(("temp max health orientation smoke: %d failure(s)"):format(failures)) end
print("temp max health orientation smoke: ok (" .. #CASES .. " fill directions)")
