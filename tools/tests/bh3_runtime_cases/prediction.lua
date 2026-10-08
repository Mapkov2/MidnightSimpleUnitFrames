-- overabsorb_bucket_probe.lua <repoRoot>
-- Real Prediction element (MSUF_UF_Elements_Prediction.lua) on a plain-value client.
-- Partial over-absorb overlay on; absorb 5 of max 1000. Health moves 99.2% -> 99.6%
-- (same integer percent bucket). Plain rule: hp + incoming + absorb >= max.
local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

for _, flavor in ipairs({ "Vanilla", "TBC", "Mists" }) do
  local world = World.New(root, flavor)
  local env = world.env
  local hp, maxHP, absorb = 992, 1000, 5
  env.UnitExists = function(u) return u == "party1" end
  env.UnitIsConnected = function() return true end
  env.UnitHealth = function() return hp end
  env.UnitHealthMax = function() return maxHP end
  env.UnitGetTotalAbsorbs = function() return absorb end
  env.UnitGetIncomingHeals = function() return 0 end
  env.UnitGetTotalHealAbsorbs = function() return 0 end
  world:Boot()
  local failure = world:FirstFailure()
  assert(failure == nil, flavor .. ": load failed " .. tostring(failure and failure.file) .. " " .. tostring(failure and failure.message))
  local UF = world.core.UF
  local P = assert(UF.elements.Prediction)
  local frame = env.CreateFrame("Button", nil, env.UIParent)
  frame.MSUFUnitKey = "party1"
  frame.hpBar = env.CreateFrame("StatusBar", nil, frame)
  frame.hpBar:SetSize(100, 20)
  local spec = { key = "party", scope = "group", width = 100, health = {},
    prediction = { enabled = true, absorb = true, overAbsorbOverlay = true } }
  frame.MSUFSpec = spec
  P.Apply(frame, spec)
  assert(frame._msufUpdatePredictionHealthValue == P.UpdateGlowHealthFast, "fast follower not bound")
  -- Absorb data event seeds the cache (the queue flushes synchronously or via the driver).
  P.Update(frame, "MSUF_FORCE_UPDATE", "party1")
  local function tick(newHP)
    hp = newHP
    frame.hpBar._msufHealthPercentValue = newHP / maxHP * 100
    frame.hpBar._msufHealthPercentUnit = "party1"
    P.UpdateGlowHealthFast(frame, "UNIT_HEALTH", "party1", hp, maxHP)
    local holder = frame.overAbsorbGlowBar
    return holder and holder._msufOverAbsorbShown == true
  end
  local a = tick(992)
  local b = tick(996)
  local c = tick(1000 - 1) -- 99.9%, still bucket 99
  local d = tick(990)      -- leaves via bucket 99 -> 99 (990 = 99.0%)
  local e = tick(980)      -- bucket 98, re-renders
  local f = tick(996)      -- bucket 99 again, re-renders
  assert(not a and b and c and not d and not e and f, "fractional threshold missed")
  print(string.format("%-8s glow shown: hp992=%s (expect false) hp996=%s (expect true) hp999=%s (expect true) hp990=%s (expect false) hp980=%s (expect false) hp996=%s (expect true)",
    flavor, tostring(a), tostring(b), tostring(c), tostring(d), tostring(e), tostring(f)))
end
