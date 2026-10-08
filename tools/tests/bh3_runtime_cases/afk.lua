-- afk_stale_stamp_probe.lua <repoRoot>
-- Real AFK ledger (MSUF_UF_Elements_StatusAFKTimer.lua). A party member goes AFK,
-- leaves the group while AFK, comes back an hour later and goes AFK again.
local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local GUID = "Player-1-0000BEEF"

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
  local world = World.New(root, flavor)
  local env = world.env
  local slot, afk = "party1", false
  env.UnitExists = function(u) return u == slot or u == "player" end
  env.UnitGUID = function(u) if u == slot then return GUID end end
  env.UnitIsAFK = function(u) return u == slot and afk end
  world:Boot()
  local failure = world:FirstFailure()
  assert(failure == nil, flavor .. ": load failed " .. tostring(failure and failure.file) .. " " .. tostring(failure and failure.message))
  local AFK = assert(world.core.UFAFKTimer)
  local listener
  for _, frame in ipairs(world.widgets.frames) do
    if frame.events and frame.events.PLAYER_FLAGS_CHANGED and frame.events.PLAYER_REGEN_DISABLED
      and frame.events.PLAYER_REGEN_ENABLED then listener = frame end
  end
  assert(listener, "AFK listener missing")
  assert(not listener.events.GROUP_ROSTER_UPDATE, "empty AFK ledger subscribes to roster churn")
  -- 1) member goes AFK while grouped: the edge is observed and stamped.
  afk = true
  world:FireEvent("PLAYER_FLAGS_CHANGED", "party1")
  assert(listener.events.GROUP_ROSTER_UPDATE, "AFK stamp did not arm ledger pruning")
  -- 2) member is removed from the group while still AFK (no AFK-off edge).
  slot = nil
  world:EnterCombat()
  assert(not listener.events.GROUP_ROSTER_UPDATE, "AFK ledger subscribes in combat")
  world:LeaveCombat()
  assert(not listener.events.GROUP_ROSTER_UPDATE, "empty pruned ledger stayed subscribed")
  -- 3) one hour later the member rejoins (now party2), back at the keyboard, then goes AFK again.
  world.widgets:AdvanceTime(3600)
  slot, afk = "party2", false
  afk = true
  world:FireEvent("PLAYER_FLAGS_CHANGED", "party2")
  assert(listener.events.GROUP_ROSTER_UPDATE, "returning AFK member did not rearm pruning")
  local text = AFK.ResolveText("party2")
  assert(text == "<1m", "departed GUID retained AFK stamp")
  afk = false
  world:FireEvent("PLAYER_FLAGS_CHANGED", "party2")
  assert(not listener.events.GROUP_ROSTER_UPDATE, "AFK-off kept empty ledger subscribed")
  print(string.format("%-8s AFK timer for a fresh AFK edge = %s (expected <1m)", flavor, tostring(text)))
end
