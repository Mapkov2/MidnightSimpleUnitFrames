-- status_dedupe_probe.lua <repoRoot>
-- Boots the real Classic core per flavor through tools/tests/client_world.lua and
-- drives the real status runtime (UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua).
-- Question: does a changed leader icon / raid-group style reach a unit frame whose
-- shown state did not change (unit frames always carry serial 0)?
local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Run(flavor)
  local world = World.New(root, flavor)
  local env = world.env
  env.UnitExists = function(u) return u == "player" or u == "target" end
  env.UnitIsPlayer = function() return true end
  env.UnitIsGroupLeader = function(u) return u == "player" end
  env.UnitIsGroupAssistant = function() return false end
  env.UnitInRaid = function(u) if u == "target" then return 5 end end
  env.GetRaidRosterInfo = function(i) if i == 5 then return "Someone", 0, 3 end end
  world:Boot()
  local failure = world:FirstFailure()
  assert(failure == nil, flavor .. ": load failed " .. tostring(failure and failure.file) .. " " .. tostring(failure and failure.message))
  env.MSUF_EnsureDB()
  local Runtime = assert(world.core.UFStatusRuntime, "no status runtime")

  -- Leader icon on the player frame (unit frame: no _msufGFCompileSerial).
  local frame = env.CreateFrame("Button", nil, env.UIParent)
  frame.MSUFUnitKey = "player"
  frame.LeaderIndicator = frame:CreateTexture(nil, "OVERLAY")
  local status = { leader = { enabled = true, style = "BLIZZARD", customIcon = "" }, assist = { enabled = false } }
  frame._msufStatusIndicatorSerial = 0           -- element.Apply for a unit frame spec
  Runtime.UpdateLeaderPair(frame, status)
  local before = tostring(frame.LeaderIndicator:GetTexture()) .. "/" .. tostring(frame.LeaderIndicator:GetAtlas())
  -- User sets a custom leader icon; the spec recompiles and element.Apply re-runs.
  status.leader.customIcon = "Interface\\Icons\\INV_Crown_01"
  frame._msufStatusIndicatorSerial = 0
  Runtime.UpdateLeaderPair(frame, status)
  local after = tostring(frame.LeaderIndicator:GetTexture()) .. "/" .. tostring(frame.LeaderIndicator:GetAtlas())
  print(string.format("%-8s leader: before=%s after=%s expected texture=Interface\\Icons\\INV_Crown_01 -> %s",
    flavor, before, after, (after:find("INV_Crown_01", 1, true) and "applied" or "NOT APPLIED")))

  assert(after:find("INV_Crown_01", 1, true), "leader custom icon not applied")
  -- Raid-group number in the target frame name.
  local tf = env.CreateFrame("Button", nil, env.UIParent)
  tf.MSUFUnitKey = "target"
  tf.raidGroupNameText = tf:CreateFontString(nil, "OVERLAY")
  local st = { raidGroup = { enabled = true, style = "PAREN" } }
  tf._msufStatusIndicatorSerial = 0
  Runtime.UpdateRaidGroup(tf, st)
  local t1 = tf.raidGroupNameText:GetText()
  st.raidGroup.style = "BRACKET"
  Runtime.UpdateRaidGroup(tf, st)
  local t2 = tf.raidGroupNameText:GetText()
  assert(t2 == "[3]", "raid group style not applied")
  print(string.format("%-8s raidGroup: PAREN=%s then BRACKET=%s expected [3] -> %s",
    flavor, tostring(t1), tostring(t2), t2 == "[3]" and "applied" or "NOT APPLIED"))
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do Run(flavor) end
