-- Probe: MSUF_UF_Runtime screen-cache key collapses every arena frame onto one
-- entry ("arena"), while boss frames get "boss:bossN". Loads the real
-- Libs/MSUFUnitFrames/MSUF_UF_Runtime.lua. The factory passes spec.key
-- ("arena", UnitFrames/Engine/MSUF_UF_Config.lua CompileUnitBase out.key = key)
-- and frame.MSUFUnitKey (UnitFrames/Engine/MSUF_UF_Factory.lua:528/591).
local ROOT = assert(arg[1]):gsub("\\", "/"):gsub("/$", "") .. "/MidnightSimpleUnitFrames/"
_G.issecretvalue = function() return false end
_G.InCombatLockdown = function() return false end
local UIParent = { ux = 1000, uy = 500 }
function UIParent:GetCenter() return self.ux, self.uy end
function UIParent:GetEffectiveScale() return 1 end
_G.UIParent = UIParent

local function NewFrame(cx, cy)
  local f = { cx = cx, cy = cy, scale = 1 }
  function f:GetCenter() return self.cx, self.cy end
  function f:GetEffectiveScale() return self.scale end
  function f:GetScale() return self.scale end
  function f:SetScale(s) self.scale = s end
  function f:GetWidth() return 180 end
  function f:GetHeight() return 40 end
  function f:ClearAllPoints() end
  function f:SetPoint(p, rel, rp, x, y) self.cx, self.cy = UIParent.ux + x, UIParent.uy + y end
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
assert(loadfile(ROOT .. "Libs/MSUFUnitFrames/MSUF_UF_Runtime.lua"))("MidnightSimpleUnitFrames", MSUF)

-- Session 1: provider present, arena frames stacked 50 px apart below it.
for i = 1, 3 do
  _G.MSUF_CacheUnitFrameScreenPosition(NewFrame(1400, 600 - (i - 1) * 50), "arena", "arena" .. i, "CENTER")
end
for i = 1, 2 do
  _G.MSUF_CacheUnitFrameScreenPosition(NewFrame(600, 600 - (i - 1) * 50), "boss", "boss" .. i, "CENTER")
end
local keys = {}
for k in pairs(bucket) do keys[#keys + 1] = k end
table.sort(keys)
print("cache keys:", table.concat(keys, ", "))

-- Session 2: provider missing -> every frame restored from the cache.
for i = 1, 3 do
  local f = NewFrame(0, 0)
  _G.MSUF_ApplyCachedUnitFrameScreenPosition(f, "arena", "arena" .. i)
  assert(f.cy == 600 - (i - 1) * 50, "arena frame cache identity collapsed")
  print(string.format("arena%d restored at y=%d (expected %d)", i, f.cy, 600 - (i - 1) * 50))
end
for i = 1, 2 do
  local f = NewFrame(0, 0)
  _G.MSUF_ApplyCachedUnitFrameScreenPosition(f, "boss", "boss" .. i)
  assert(f.cy == 600 - (i - 1) * 50, "boss cache regression")
  print(string.format("boss%d restored at y=%d (expected %d)", i, f.cy, 600 - (i - 1) * 50))
end

bucket["arena"] = {v=3,x=50,y=90}
bucket["arena:arena4"] = nil
assert(not _G.MSUF_ApplyCachedUnitFrameScreenPosition(NewFrame(0, 0), "arena", "arena4"), "ambiguous legacy arena entry reused")
