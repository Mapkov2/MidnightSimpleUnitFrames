-- Probe: a scope whose "Show spell indicators" switch the user turned off
-- (spellIndicators.enabled = false) after its first spec was seeded. The player
-- then plays another supported spec (alt character on the same profile, or a
-- spec change). Does the cold DB repair turn the switch back on?
local root = arg[1]
local World = dofile(root .. "/tools/tests/client_world.lua")
local flavor = "Mainline"
local w = World.New(root, flavor):Boot()
local f = w:FirstFailure()
print("boot failure:", f and (f.file .. " " .. f.message) or "none")
local GF = w.core.GF
local env = w.env
local SI = GF.SpellIndicators or env.MSUF_GF_SpellIndicators
assert(SI and SI.SpecDefaults, "no spell indicator module")
local specA, specB
for key in pairs(SI.SpecDefaults) do
  if not specA then specA = key elseif not specB and key ~= specA then specB = key end
end
print("specs:", specA, specB)

local function Scope(enabled)
  return { enabled = true, spellIndicators = { enabled = enabled, spec = "auto", specs = {},
    layer = 9, iconZoom = 100, iconScale = 100, _autoSeededSpecs = { [specA] = 1 } } }
end
env.MSUF_DB = { general = {}, gf_party = Scope(false), gf_raid = Scope(false), gf_mythicraid = Scope(true) }
GF.InvalidateConfCache()

-- Player now on specB (the spec resolver is the module's own GetPlayerSpec).
SI.GetPlayerSpec = function() return specB end
GF.EnsureDB()   -- login / profile repair path; ends with SeedCurrentSpecSpellIndicatorDefaults
assert(env.MSUF_DB.gf_party.spellIndicators.enabled == false and env.MSUF_DB.gf_raid.spellIndicators.enabled == false, "explicit disabled overwritten")
print("party enabled after repair (user had false):", env.MSUF_DB.gf_party.spellIndicators.enabled)
print("raid  enabled after repair (user had false):", env.MSUF_DB.gf_raid.spellIndicators.enabled)
print("expected: false / false (explicit user choice kept)")
