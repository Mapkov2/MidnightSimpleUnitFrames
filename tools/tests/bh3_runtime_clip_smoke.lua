-- Probe: a texture clip request made while InCombatLockdown() is true
-- (MSUF_RoundedUF_OnDispelOverlayChanged, used by the Texture Layer
-- "Clip to rounded frame" option) is deferred, but the post-combat ApplyAll
-- does not mask the texture because the request was never recorded.
-- Loads the real RoundedSurface + RoundedFrames files.
local ROOT = assert(arg[1]) .. "/MidnightSimpleUnitFrames/"

local inCombat = false
_G.InCombatLockdown = function() return inCombat end
_G.issecretvalue = function() return false end
_G.C_Timer = { After = function(_, fn) fn() end }

local function NewRegion(name)
  local r = { _name = name, masks = {} }
  local m = {}
  function m.CreateMaskTexture(self) return NewRegion("mask") end
  function m.CreateTexture(self) return NewRegion("tex") end
  function m.AddMaskTexture(self, mask) self.masks[#self.masks + 1] = mask end
  function m.RemoveMaskTexture(self, mask)
    for i = #self.masks, 1, -1 do if self.masks[i] == mask then table.remove(self.masks, i) end end
  end
  function m.GetParent(self) return self._parent end
  function m.GetFrameLevel() return 5 end
  function m.GetWidth() return 200 end
  function m.GetHeight() return 40 end
  function m.RegisterEvent() end
  function m.UnregisterEvent() end
  function m.SetScript(self, k, fn) self._scripts = self._scripts or {}; self._scripts[k] = fn end
  setmetatable(r, { __index = function(_, k)
    if m[k] then return m[k] end
    if type(k) == "string" and k:match("^%u") and not k:match("^MSUF") then return function() end end
    return nil
  end })
  return r
end
_G.CreateFrame = function(_, _, parent) local f = NewRegion("frame"); f._parent = parent; return f end

local registeredModule
local frames = {}
local MSUF = {
  ExportPublic = function(name, value) _G[name] = value end,
  Require = function(name)
    if name == "MSUF_GetBarOutlineColor" then return function() return 0, 0, 0 end end
    return function() end
  end,
  MSUF_RegisterModule = function(_, mod) registeredModule = mod end,
  UF = {
    ForEachFrame = function(fn) for _, f in ipairs(frames) do fn(f) end end,
    RegisterVisualRefreshCallback = function() end,
    UnregisterVisualRefreshCallback = function() end,
    SetRoundedBorderVisualCallback = function() end,
    SetRoundedPowerBorderCallback = function() end,
    GetFrame = function() return nil end,
  },
}
_G.MSUF_DB = { bars = { roundedFramesEnabled = true }, target = {}, general = {} }

assert(loadfile(ROOT .. "UnitFrames/Effects/MSUF_UF_RoundedSurface.lua"))("MidnightSimpleUnitFrames", MSUF)
assert(loadfile(ROOT .. "UnitFrames/Effects/MSUF_UF_RoundedFrames.lua"))("MidnightSimpleUnitFrames", MSUF)
assert(registeredModule, "module not registered")
registeredModule.Enable()

local function NewUnitFrame()
  local f = NewRegion("unitframe")
  f.MSUFUnitKey = "target"
  f.MSUFSpec = { key = "target" }
  f.hpBar = NewRegion("hpBar")
  f.bg = NewRegion("bg")
  return f
end

-- Case A: the clip request arrives in combat (target change in combat).
local frameA = NewUnitFrame(); frames[#frames + 1] = frameA
local texA = NewRegion("textureLayerTex")
inCombat = true
local okA = _G.MSUF_RoundedUF_OnDispelOverlayChanged(frameA, texA)
print("A in combat: request returned " .. tostring(okA) .. ", pending=" .. tostring(MSUF.__msufRoundedPending))
inCombat = false
-- PLAYER_REGEN_ENABLED handler: C_Timer.After(0, ApplyAll) when pending.
_G.MSUF_RoundedUF_OnApplyAll()
print("A after combat ApplyAll: masks on texture = " .. #texA.masks .. " (expected 1)")

-- Case B (control): the same request out of combat.
local frameB = NewUnitFrame(); frames[#frames + 1] = frameB
local texB = NewRegion("textureLayerTex")
local okB = _G.MSUF_RoundedUF_OnDispelOverlayChanged(frameB, texB)
_G.MSUF_RoundedUF_OnApplyAll()
print("B out of combat: request returned " .. tostring(okB) .. ", masks on texture = " .. #texB.masks .. " (expected 1)")

assert(#texA.masks == 1, "combat clip request was dropped")
for i = 1, 100 do
  assert(_G.MSUF_RoundedUF_OnDispelOverlayChanged(frameA, texA, false))
  assert(#texA.masks == 0 and frameA._msufRUF_ClipRequests[texA] == nil, "clip removal leaked request/mask")
  assert(_G.MSUF_RoundedUF_OnDispelOverlayChanged(frameA, texA))
  assert(#texA.masks == 1, "clip reenable stacked masks")
end
inCombat = true
_G.MSUF_RoundedUF_OnDispelOverlayChanged(frameA, texA, false)
inCombat = false
_G.MSUF_RoundedUF_OnApplyAll()
assert(#texA.masks == 0 and frameA._msufRUF_ClipRequests[texA] == nil, "deferred clip release not replayed")
print("PASS combat clip replay and 100 clip/release cycles")
