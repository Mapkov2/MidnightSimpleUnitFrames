-- Range fade reaches arena castbars the way it reaches boss castbars.
-- Arena and boss castbars are UIParent children (Castbars/MSUF_CastbarDriver.lua),
-- so a unit frame's range alpha never reaches them through the parent chain:
-- the Alpha element hands it over (ApplyCastbarRangeAlpha), and the castbar
-- runtime re-applies it at every cast start through MSUF_UF_ApplyCastbarRangeAlpha.
-- Loads the real castbar pool modules (tools/tests/castbar_pool_namespace.lua),
-- Kernel/MSUF_Require.lua, Kernel/MSUF_Util.lua, MSUF_UF_Visuals_Common.lua and
-- MSUF_UF_Elements_Alpha.lua into one namespace. The bars themselves are
-- published the way EnsureCastbars publishes them (pool table plus named frame).
-- Usage: lua tools/tests/arena_castbar_range_fade_smoke.lua <repoRoot>
local root = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local CORE = root .. "/MidnightSimpleUnitFrames/"

local PoolNamespace = assert(loadfile(root .. "/tools/tests/castbar_pool_namespace.lua"))()
local MSUF = PoolNamespace(root, 3)

_G.InCombatLockdown = function() return false end
_G.issecretvalue = function() return false end

local function NewRegion(name)
  local region = { name = name, alpha = 1 }
  function region:SetAlpha(alpha) self.alpha = alpha end
  function region:GetAlpha() return self.alpha end
  return region
end
_G.CreateFrame = function() return NewRegion("anon") end

local UF = { elements = {} }
UF.Clamp01 = function(v, fallback)
  v = tonumber(v)
  if v == nil then return fallback end
  if v < 0 then return 0 elseif v > 1 then return 1 end
  return v
end
UF.RegisterElement = function(name, element) UF.elements[name] = element end
MSUF.UF = UF
MSUF.Secrets = { IsNil = function(v) return v == nil end, NotSecret = function() return true end }

local function Load(rel) assert(loadfile(CORE .. rel))("MidnightSimpleUnitFrames", MSUF) end
Load("Kernel/MSUF_Require.lua")
Load("Kernel/MSUF_Util.lua")
Load("UnitFrames/Engine/Elements/MSUF_UF_Visuals_Common.lua")
Load("UnitFrames/Engine/Elements/MSUF_UF_Elements_Alpha.lua")

local arenaPool = assert(MSUF.Castbars.Pools.kinds.arena, "arena castbar pool did not register")

local failures = 0
local function Check(ok, message)
  if not ok then
    failures = failures + 1
    print("FAIL " .. message)
  end
end

-- Compiled range spec as MSUF_UF_Config.lua CompileRange builds it for the boss
-- and arena keys (both in RANGE_KEYS; arena rangeFadeEnabled defaults on).
local function Frame(unit)
  local frame = NewRegion(unit)
  frame.MSUFUnitKey = unit
  frame.MSUFSpec = { range = { active = true, layerMode = "frame", alpha = 0.4 } }
  return frame
end
local boss1, arena1, arena2 = Frame("boss1"), Frame("arena1"), Frame("arena2")
UF.frames = { boss1 = boss1, arena1 = arena1, arena2 = arena2 }
for _, frame in ipairs({ boss1, arena1, arena2 }) do UF.CompileAlphaRuntime(frame, frame.MSUFSpec) end

-- arena2 fades before its castbar exists: the miss must stay uncached, because
-- the pool builds its bars only when arena castbars are switched on.
UF.ApplyRangeModifier(arena2, 0.4, true)
Check(arena2.alpha == 0.4, "arena2 frame alpha " .. tostring(arena2.alpha))

local bossCastbar = NewRegion("MSUF_BossCastbar1")
bossCastbar.unit = "boss1"
_G.MSUF_BossCastbars = { bossCastbar }
_G.MSUF_BossCastbar1 = bossCastbar
local arenaCastbars = {}
for index = 1, 2 do
  local castbar = NewRegion("MSUF_ArenaCastbar" .. index)
  castbar.unit = "arena" .. index
  arenaCastbars[index] = castbar
  _G["MSUF_ArenaCastbar" .. index] = castbar
end
_G.MSUF_ArenaCastbars = arenaCastbars
Check(arenaPool.Bar(1) == arenaCastbars[1], "arena pool Bar(1) does not return the published bar")

UF.ApplyRangeModifier(boss1, 0.4, true)
UF.ApplyRangeModifier(arena1, 0.4, true)
UF.ApplyRangeModifier(arena2, 0.4, true)
Check(math.abs(bossCastbar.alpha - 0.4) < 1e-6, "boss1 castbar alpha " .. bossCastbar.alpha .. ", expected 0.40")
Check(math.abs(arenaCastbars[1].alpha - 0.4) < 1e-6,
  "arena1 castbar alpha " .. arenaCastbars[1].alpha .. ", expected 0.40 (frame " .. arena1.alpha .. ")")
Check(math.abs(arenaCastbars[2].alpha - 0.4) < 1e-6,
  "arena2 castbar alpha " .. arenaCastbars[2].alpha .. " after the pool was built, expected 0.40")

-- Cast start: the castbar runtime resets alpha to 1, then re-applies range alpha.
for index = 1, 2 do
  local castbar = arenaCastbars[index]
  castbar.alpha = 1
  local handled = _G.MSUF_UF_ApplyCastbarRangeAlpha(castbar, nil, true)
  Check(handled == true, "MSUF_UF_ApplyCastbarRangeAlpha(arena" .. index .. " castbar) returned " .. tostring(handled))
  Check(math.abs(castbar.alpha - 0.4) < 1e-6, "arena" .. index .. " castbar alpha after cast start " .. castbar.alpha)
end

-- Back in range: the castbar follows the frame back to full alpha.
UF.ApplyRangeModifier(arena1, 1, true)
Check(arenaCastbars[1].alpha == 1, "arena1 castbar alpha back in range " .. arenaCastbars[1].alpha)

-- Units that cannot own a castbar still resolve to nothing.
for _, unit in ipairs({ "party1", "arenapet1" }) do
  UF.frames[unit] = Frame(unit)
  UF.CompileAlphaRuntime(UF.frames[unit], UF.frames[unit].MSUFSpec)
end
Check(_G.MSUF_UF_ApplyCastbarRangeAlpha("party1", 0.4, true) == false, "party1 resolved a castbar")
Check(_G.MSUF_UF_ApplyCastbarRangeAlpha("arenapet1", 0.4, true) == false, "arenapet1 resolved a castbar")

if failures > 0 then error(("arena castbar range fade smoke: %d failure(s)"):format(failures)) end
print("arena castbar range fade smoke: ok")
