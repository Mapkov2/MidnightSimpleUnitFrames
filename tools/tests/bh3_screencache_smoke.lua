-- Probe: MSUF_UF_Runtime screen cache round trip with an MSUF scale != 1.
-- Loads the real Libs/MSUFUnitFrames/MSUF_UF_Runtime.lua. Geometry model follows
-- Blizzard's rule that SetPoint offsets are in the anchored frame's own scale
-- (ui\live: Blizzard_EditMode/Shared/EditModeSystemTemplates.lua:373-375
-- "Make sure offsets are relative to our current scale ... offsetX / scale").
local ROOT = assert(arg[1]):gsub("\\", "/"):gsub("/$", "") .. "/MidnightSimpleUnitFrames/"
_G.issecretvalue = function() return false end
_G.InCombatLockdown = function() return false end

local US = 0.7111 -- UIParent effective scale (UI scale 0.71)
local UIParent = { cx = 960 / US * US, cy = 540 }
-- UIParent coordinates: width 1920/US? keep simple: center at (1350, 759) in UI units
UIParent.ux, UIParent.uy = 1350, 759
function UIParent:GetCenter() return self.ux, self.uy end
function UIParent:GetEffectiveScale() return US end
_G.UIParent = UIParent

local function NewFrame(scale)
  local f = { scale = scale, phys = nil }
  function f:GetEffectiveScale() return self.scale * US end
  function f:GetScale() return self.scale end
  function f:SetScale(s) self.scale = s end
  function f:GetWidth() return 200 end
  function f:GetHeight() return 40 end
  function f:ClearAllPoints() self.phys = nil end
  -- CENTER-to-UIParent-CENTER anchor: offsets are in this frame's own scale.
  function f:SetPoint(point, rel, relPoint, ox, oy)
    assert(point == "CENTER" and rel == UIParent and relPoint == "CENTER")
    local fs = self:GetEffectiveScale()
    self.phys = { UIParent.ux * US + ox * fs, UIParent.uy * US + oy * fs }
  end
  function f:GetCenter()
    local fs = self:GetEffectiveScale()
    return self.phys[1] / fs, self.phys[2] / fs
  end
  return f
end

local bucket = {}
local MSUF = {
  UF = { Metadata = {}, frames = {}, frameList = {}, visualRefreshCallbacks = {},
         ForEachFrame = function() end, pendingElementRefreshes = {}, pendingApply = {}, unitOrder = {} },
  ExportPublic = function(name, v) _G[name] = v; return v end,
}
MSUF.UF.GetService = function(name)
  if name == "ProfileScopedCache" then return function() return bucket end end
end
local chunk = assert(loadfile(ROOT .. "Libs/MSUFUnitFrames/MSUF_UF_Runtime.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)

for _, s in ipairs({ 1.0, 0.8, 1.25 }) do
  -- A frame that the external provider placed 400 UI units left / 200 up of centre.
  local live = NewFrame(s)
  live.phys = { (UIParent.ux - 400) * US, (UIParent.uy + 200) * US }
  assert(_G.MSUF_CacheUnitFrameScreenPosition(live, "player", "player", "CENTER") == true)
  local restored = NewFrame(s)
  assert(_G.MSUF_ApplyCachedUnitFrameScreenPosition(restored, "player", "player") == true)
  local dx = (restored.phys[1] - live.phys[1]) / US
  local dy = (restored.phys[2] - live.phys[2]) / US
  assert(math.abs(dx) < .001 and math.abs(dy) < .001, "scaled screen-cache roundtrip drifted")
  print(string.format("MSUF scale %.2f: cached x=%d y=%d  restored centre off by dx=%.1f dy=%.1f UI units (expected 0)",
    s, bucket.player.x, bucket.player.y, dx, dy))
end
