-- Regression: Spell Indicator auto-blacklists are compiled once into the
-- normal Group Buff lane without mutating or replacing its manual blacklist.
local root = arg and arg[1] or "."

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

_G.wipe = function(tbl)
  for key in pairs(tbl) do tbl[key] = nil end
  return tbl
end

local entry = {
  enabled = true,
  onlyOwn = true,
  autoBlacklist = true,
}

_G.MSUF_DB = {
  general = {},
  gf_party = {
    enabled = true,
    auras = {
      enabled = true,
      buff = { enabled = true },
      debuff = { enabled = true },
      externals = { enabled = true },
    },
    spellIndicators = {
      enabled = true,
      spec = "RestorationDruid",
      specs = {
        RestorationDruid = { Rejuvenation = entry },
      },
    },
  },
}

local MSUF = { UF = {} }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/GroupFrames/MSUF_GroupFrames_DB.lua"))(
  "MidnightSimpleUnitFrames", MSUF)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Metadata.lua"))(
  "MidnightSimpleUnitFrames", MSUF)
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_SpellIndicators_Data.lua"))(
  "MidnightSimpleUnitFrames", MSUF)

local manualHash = { [999001] = true }
MSUF.GF.AuraFilter = {
  GetBlacklistHashForGroup = function(kind, lane)
    Check(kind == "party", "unexpected Group scope")
    if lane == "buff" then return manualHash end
    return nil
  end,
}
MSUF.GF.SpellIndicators.GetPlayerSpec = function() return "RestorationDruid" end

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua"))(
  "MidnightSimpleUnitFrames", MSUF)

local function Compile()
  MSUF.GF.InvalidateCompiledSpecs("party")
  return MSUF.GF.CompileSpec("party", nil, "party1")
end

local spec = Compile()
local hash = spec.auras and spec.auras.buffBlacklistHash
Check(type(hash) == "table", "compiled Buff blacklist missing")
Check(hash[774] == true, "Rejuvenation was not auto-blacklisted")
Check(hash[999001] == true, "manual Buff blacklist entry was lost")
Check(manualHash[774] == nil, "cached manual blacklist was mutated")

entry.enabled = false
spec = Compile()
hash = spec.auras and spec.auras.buffBlacklistHash
Check(hash and hash[774] == nil, "disabled Spell Indicator stayed auto-blacklisted")
Check(hash and hash[999001] == true, "manual blacklist vanished with disabled indicator")

entry.enabled = true
_G.MSUF_DB.gf_party.spellIndicators.enabled = false
spec = Compile()
hash = spec.auras and spec.auras.buffBlacklistHash
Check(hash and hash[774] == nil, "disabled Spell Indicators feature still hid the Buff")

_G.MSUF_DB.gf_party.spellIndicators.enabled = true
entry.autoBlacklist = nil
spec = Compile()
hash = spec.auras and spec.auras.buffBlacklistHash
Check(hash and hash[774] == nil, "disabled auto-blacklist toggle still hid the Buff")
Check(hash and hash[999001] == true, "manual blacklist did not survive toggle-off")

print("PASS Spell Indicator auto-blacklist: merged, isolated, and disable-safe")
