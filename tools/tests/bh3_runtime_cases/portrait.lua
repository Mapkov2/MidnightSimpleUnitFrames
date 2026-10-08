-- portrait_reaction_probe.lua <repoRoot>
-- Boots the real core per flavor and asks the real Portrait element which unit
-- events a target portrait with a REACTION (or CLASS_COLOR) border subscribes to,
-- then drives Portrait.Update with UNIT_FACTION-equivalent state change to show
-- the border colour is only re-resolved on the portrait's own events.
local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Has(list, ev)
  for i = 1, #list do if list[i] == ev then return true end end
  return false
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
  local world = World.New(root, flavor)
  local env = world.env
  local reaction = 5
  env.UnitExists = function(u) return u == "target" or u == "player" end
  env.UnitReaction = function(u) if u == "target" then return reaction end end
  world:Boot()
  local failure = world:FirstFailure()
  assert(failure == nil, flavor .. ": load failed " .. tostring(failure and failure.file) .. " " .. tostring(failure and failure.message))
  local UF = assert(world.core.UF, "no UF")
  local Portrait = assert(UF.elements.Portrait, "no Portrait element")
  local frame = env.CreateFrame("Button", nil, env.UIParent)
  frame.MSUFUnitKey = "target"
  local spec = { key = "target", unit = "target", height = 30, width = 200,
    portrait = { enabled = true, render = "2D", shape = "SQUARE", size = 30,
      border = { style = "REACTION", thickness = 2 } } }
  local events = Portrait.GetEvents(frame, spec)
  local unitless = Portrait.GetUnitlessEvents(frame, spec)
  assert(Has(events,"UNIT_FACTION"), "reaction event missing")
  print(string.format("%-8s Portrait.GetEvents(target, REACTION border) = {%s}; unitless = {%s}; UNIT_FACTION subscribed: %s",
    flavor, table.concat(events, ","), table.concat(unitless, ","),
    tostring(Has(events, "UNIT_FACTION") or Has(unitless, "UNIT_FACTION"))))
  -- Live colour path: apply with a friendly target, then flip reaction and deliver
  -- the events the portrait is subscribed to that are not identity changes.
  frame.MSUFSpec = spec
  Portrait.Create(frame)
  Portrait.Apply(frame, spec)
  local edge = frame.MSUFPortraitHolder.edges[1]
  local r1, g1 = edge._msufVertexR, edge._msufVertexG
  reaction = 2 -- the NPC turned hostile; Blizzard announces this with UNIT_FACTION
  local before = string.format("%s,%s", tostring(r1), tostring(g1))
  Portrait.Update(frame, "UNIT_FACTION", "target")
  local r2, g2 = edge._msufVertexR, edge._msufVertexG
  assert(r2 == 1 and g2 == 0, "reaction color stale")
  print(string.format("%-8s border colour friendly=(%s) after reaction->hostile with no portrait event=(%s,%s) expected (1,0)",
    flavor, before, tostring(r2), tostring(g2)))
  -- Health element (same frame) does listen to UNIT_FACTION:
  local health = UF.elements.Health
  if health and health.GetEvents then
    local ok, hev = pcall(health.GetEvents, frame, { health = { mode = "reaction" }, key = "target", unit = "target" })
    if ok and type(hev) == "table" then
      print(string.format("%-8s Health.GetEvents includes UNIT_FACTION: %s", flavor, tostring(Has(hev, "UNIT_FACTION"))))
    end
  end
end
