--- Shared Classic-family spell-indicator data contract.
--- Flavor files populate only spells/specs that exist on their client.
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
local ExportPublic = ns.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local GF = ns.GF
if not GF then return end
local SI = GF.SpellIndicators or {}
GF.SpellIndicators = SI

SI.SpecMap = {}
SI.SpecInfo = {}
SI.SpellIDs = {}
SI.AltSpellIDs = {}
SI.AuraSpellIDAliases = {}
SI.CustomAuraAliases = SI.AuraSpellIDAliases
SI.SelfOnlySpellIDs = {}
SI.LinkedAuraRules = {}
SI.SecretSpellIDs = {}
SI.ExternalDefensiveAuras = {}
SI.SecretAuraInfo = {}
SI.IconTextures = {}
SI.TrackableAuras = {}
SI.SpecDefaults = {}

function SI.DefineClassicSpec(classToken, specIndex, specKey, specID)
  SI.SpecMap[classToken .. "_" .. specIndex] = specKey
  SI.SpecInfo[specKey] = {
    display = specKey:gsub("(%l)(%u)", "%1 %2"),
    class = classToken,
    specID = specID,
  }
end

function SI.ClassicAura(name, r, g, b, display)
  return {
    name = name,
    display = display or name:gsub("(%l)(%u)", "%1 %2"),
    color = { r, g, b },
  }
end

function SI.ClassicPlaced(kind, anchor, x, y, size)
  return { placed = { type = kind, anchor = anchor, x = x, y = y, size = size } }
end

function SI.ClassicFrame(kind, r, g, b, a, priority)
  priority = tonumber(priority) or 1
  local index = math.max(0, math.floor(priority + 0.5) - 1)
  return {
    placed = { type = "icon", anchor = "RIGHT", x = 2 + (index * 22), y = 0, size = 20 },
    frame = { type = kind, color = { r, g, b, a }, priority = priority },
  }
end

function SI.BuildNameLookup(specKey)
  local ids = SI.SpellIDs[specKey]
  if type(ids) ~= "table" then return nil end
  local lookup, any = {}, false
  for auraName, spellID in pairs(ids) do
    local name
    if C_Spell and type(C_Spell.GetSpellName) == "function" then
      name = C_Spell.GetSpellName(spellID)
    elseif type(GetSpellInfo) == "function" then
      name = GetSpellInfo(spellID)
    end
    if name then lookup[name] = auraName; any = true end
  end
  return any and lookup or nil
end

function SI.BuildReverseLookup(specKey)
  local lookup = {}
  for auraName, spellID in pairs(SI.SpellIDs[specKey] or {}) do
    lookup[spellID] = auraName
  end
  for altID, auraName in pairs(SI.AltSpellIDs[specKey] or {}) do
    lookup[altID] = auraName
  end
  return lookup
end

local cachedClass, cachedIndex, cachedKey
function SI.GetPlayerSpec()
  local _, classToken = UnitClass("player")
  if not classToken then return nil end
  local specIndex
  if type(GetSpecialization) == "function" then
    specIndex = GetSpecialization()
  elseif C_SpecializationInfo and type(C_SpecializationInfo.GetSpecialization) == "function" then
    specIndex = C_SpecializationInfo.GetSpecialization()
  end
  if not specIndex and ns.Client and ns.Client.IsVanilla == true then specIndex = 0 end
  if not specIndex then return nil end
  if classToken == cachedClass and specIndex == cachedIndex then return cachedKey end
  cachedClass, cachedIndex = classToken, specIndex
  cachedKey = SI.SpecMap[classToken .. "_" .. specIndex]
  return cachedKey
end

function SI.GetAuraIcon(specKey, auraName)
  local texture = SI.IconTextures[auraName]
  if texture then return texture end
  local spellID = tonumber(auraName) or (SI.SpellIDs[specKey] and SI.SpellIDs[specKey][auraName])
  if spellID and C_Spell and type(C_Spell.GetSpellTexture) == "function" then
    texture = C_Spell.GetSpellTexture(spellID)
  elseif spellID and type(GetSpellInfo) == "function" then
    texture = select(3, GetSpellInfo(spellID))
  end
  return texture or 136243
end

ExportPublic("MSUF_GF_SpellIndicators", SI)
