-- Probe: does conf.clickCastEnabled=false keep a live group button out of ClickCastFrames?
local ROOT = assert(arg[1]) .. "/MidnightSimpleUnitFrames/"
_G.issecretvalue = function() return false end
_G.InCombatLockdown = function() return false end
_G.C_Timer = { After = function() end }
_G.GetTime = function() return 0 end
local function NewFrame()
  local f = { attrs = {} }
  function f:GetAttribute(k) return self.attrs[k] end
  function f:SetAttribute(k, v) self.attrs[k] = v end
  function f:HookScript() end
  function f:RegisterForClicks() end
  function f:SetSize(w, h) self.w, self.h = w, h end
  function f:UnregisterAllEvents() end
  function f:IsShown() return true end
  return f
end
local MSUF = {}
MSUF.UF = {
  AttachFrame = function() end,
  ApplySpec = function() return true end,
  SetFrameSpec = function(f, spec) f.MSUFSpec = spec end,
}
-- The spec shape Group_Config.lua:1765 compiles for a scope with the toggle off.
MSUF.GF = {
  CompileSpec = function(kind, frame, unit)
    return { width = 80, height = 32, _msufGFCompileSerial = 1,
      groupLayout = { clickCastEnabled = false, hideInClientScene = true, hideInHousing = false } }
  end,
}
-- The real Kernel API (Bootstrap's exports and Public registry, Require/Optional). The pixel regions
-- are the core's (Kernel/MSUF_Util.lua): these stub frames lay out no pixels, so the shared stand-in
-- serves; providers the adapter requires that this probe does not load are deferred.
local REPO = assert(arg[1])
local RequireFixture = assert(loadfile(REPO .. "/tools/tests/require_fixture.lua"))()
RequireFixture.InstallKernel(REPO, MSUF)
MSUF.ExportPublic("MSUF_PixelLayoutRegion",
  assert(loadfile(REPO .. "/tools/tests/classpower_collaborators.lua"))().STANDINS.MSUF_PixelLayoutRegion)
RequireFixture.LoadShipped(REPO, "MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Adapter.lua", MSUF)
local GF = MSUF.GF
local button = NewFrame()
button.attrs.unit = "party1"
GF.ApplyButton(button, "party", "MSUF_GF_SCAN")
print("compiled clickCastEnabled =", tostring(button.MSUFSpec.groupLayout.clickCastEnabled))
print("ClickCastFrames[button]   =", tostring(_G.ClickCastFrames and _G.ClickCastFrames[button]))
print("expected: nil (toggle off); observed: " .. tostring(_G.ClickCastFrames and _G.ClickCastFrames[button]))

assert(not (_G.ClickCastFrames and _G.ClickCastFrames[button]), "group clickcast disabled toggle ignored")
