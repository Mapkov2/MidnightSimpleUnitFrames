--- UnitFrames/Engine/Group/MSUF_UF_Group_SpellRegistry.lua
--- Runtime registry for group-frame spell indicators.
---
--- Data files declare default spells and specs. This registry merges saved
--- profile config with those defaults, builds trackable aura lists, resolves
--- icons, and invalidates runtime caches after profile changes.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local GF = MSUF.GF or {}
MSUF.GF = GF

local SI = GF.SpellIndicators or {}
GF.SpellIndicators = SI
ExportPublic("MSUF_GF_SpellIndicators", SI)

SI.SpecInfo = SI.SpecInfo or {}
SI.SpellIDs = SI.SpellIDs or {}
SI.AltSpellIDs = SI.AltSpellIDs or {}
SI.SecretSpellIDs = SI.SecretSpellIDs or {}
SI.IconTextures = SI.IconTextures or {}
SI.TrackableAuras = SI.TrackableAuras or {}
SI.SpecDefaults = SI.SpecDefaults or {}
SI.ExternalDefensiveAuras = SI.ExternalDefensiveAuras or {}
SI.SpecMap = SI.SpecMap or {}

function SI.IsExternalDefensiveAura(specKey, auraName, entry)
  if type(entry) == "table" and entry.externalDefensive ~= nil then
    return entry.externalDefensive == true
  end
  local specAuras = SI.ExternalDefensiveAuras[specKey]
  return type(specAuras) == "table" and specAuras[auraName] == true
end

local function SpellID(value)
  local id = tonumber(value)
  return id and id > 0 and math.floor(id + 0.5) or nil
end

local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then
    return C_Spell.GetSpellName(id)
  end
  if GetSpellInfo then
    return GetSpellInfo(id)
  end
  return nil
end

local function CopyTable(src)
  if type(src) ~= "table" then return src end
  local dst = {}
  for k, v in pairs(src) do
    dst[k] = CopyTable(v)
  end
  return dst
end

local function NormalizeCustomDefaults(entry)
  if type(entry) ~= "table" or entry.custom ~= true then return end
  if entry._msufCustomOnlyOwnExplicit ~= true then entry.onlyOwn = false end
end

if type(SI.GetPlayerSpec) ~= "function" then
  function SI.GetPlayerSpec()
    local specIndex = GetSpecialization and GetSpecialization() or nil
    if not specIndex then return nil end
    local classToken
    if UnitClass then
      local _, token = UnitClass("player")
      classToken = token
    end
    local mapped = classToken and SI.SpecMap and SI.SpecMap[classToken .. "_" .. specIndex]
    if mapped then return mapped end
    local specID, specName
    if GetSpecializationInfo then
      specID, specName = GetSpecializationInfo(specIndex)
    end
    specID = tonumber(specID)
    if not specID then return nil end
    local key = tostring(specID)
    SI.SpecInfo[key] = SI.SpecInfo[key] or { display = specName or key, specID = specID }
    SI.TrackableAuras[key] = SI.TrackableAuras[key] or {}
    return key
  end
end

--- Convert a saved/default indicator entry into the compact spell-id list that
--- aura runtime can watch. User-entered numeric strings are accepted.
local function EnsureTrackable(specKey, auraKey, entry)
  if not specKey then return end
  local ids = {}
  local id = SpellID(auraKey)
  if id then ids[#ids + 1] = id end
  if type(entry) == "table" then
    id = SpellID(entry.spellID or entry.spellId or entry.id)
    if id then ids[#ids + 1] = id end
    if type(entry.spells) == "string" then
      for token in entry.spells:gmatch("%d+") do
        id = SpellID(token)
        if id then ids[#ids + 1] = id end
      end
    end
  end
  if #ids == 0 then return end

  SI.SpecInfo[specKey] = SI.SpecInfo[specKey] or { display = specKey }
  local list = SI.TrackableAuras[specKey] or {}
  SI.TrackableAuras[specKey] = list
  local name = tostring(ids[1])
  for i = 1, #list do
    if list[i].name == name or SpellID(list[i].spellID or list[i].spellId or list[i].id) == ids[1] then return end
  end
  list[#list + 1] = {
    name = name,
    display = SpellName(ids[1]) or name,
    spellID = ids[1],
    color = { 0.45, 0.85, 1 },
    custom = true,
  }
end

local function ClearCustomTrackables()
  for _, list in pairs(SI.TrackableAuras or {}) do
    if type(list) == "table" then
      for i = #list, 1, -1 do
        if type(list[i]) == "table" and list[i].custom == true then
          table.remove(list, i)
        end
      end
    end
  end
end

function SI.RefreshFromDB()
  if not GF.GetConf then return end
  ClearCustomTrackables()
  local kinds = { "party", "raid", "mythicraid" }
  for i = 1, #kinds do
    local conf = GF.GetConf(kinds[i])
    local root = conf and conf.spellIndicators and conf.spellIndicators.specs
    if type(root) == "table" then
      for specKey, specCfg in pairs(root) do
        if type(specCfg) == "table" then
          for auraKey, entry in pairs(specCfg) do
            NormalizeCustomDefaults(entry)
            EnsureTrackable(specKey, auraKey, entry)
          end
        end
      end
    end
  end
end

--- Ensure one spec has a saved table before menus/runtime read it. Defaults are
--- copied into SavedVariables once; afterward the profile remains authoritative.
function SI.EnsureSpecConfig(siCfg, specKey)
  if not (siCfg and specKey) then return false end
  siCfg.specs = siCfg.specs or {}
  siCfg.specs[specKey] = siCfg.specs[specKey] or {}
  local defaults = SI.SpecDefaults and SI.SpecDefaults[specKey]
  if type(defaults) == "table" then
    for auraKey, def in pairs(defaults) do
      local entry = siCfg.specs[specKey][auraKey]
      if type(entry) ~= "table" then
        entry = (GF._DeepCopyTable or CopyTable)(def)
        siCfg.specs[specKey][auraKey] = entry
      elseif type(def) == "table" then
        local copy = GF._DeepCopyTable or CopyTable
        if entry.placed == nil and def.placed ~= nil then entry.placed = copy(def.placed) end
        if entry.frame == nil and def.frame ~= nil then entry.frame = copy(def.frame) end
        if entry.onlyOwn == nil and def.onlyOwn ~= nil then entry.onlyOwn = def.onlyOwn end
      end
      NormalizeCustomDefaults(entry)
      EnsureTrackable(specKey, auraKey, entry)
    end
  end
  SI.RefreshFromDB()
  return true
end

if type(SI.GetAuraIcon) ~= "function" then
  function SI.GetAuraIcon(specKey, auraName)
    local icon = SI.IconTextures and SI.IconTextures[auraName]
    if icon then return icon end
    local id = SpellID(auraName)
    if not id then
      local ids = specKey and SI.SpellIDs and SI.SpellIDs[specKey]
      id = ids and SpellID(ids[auraName])
    end
    if not id then
      local list = specKey and SI.TrackableAuras and SI.TrackableAuras[specKey]
      if type(list) == "table" then
        for i = 1, #list do
          if list[i].name == auraName then id = SpellID(list[i].spellID); break end
        end
      end
    end
    if id and C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    if id and GetSpellTexture then return GetSpellTexture(id) end
    return 136243
  end
end

--- Materialize one aura entry in the saved spec config so position/shape
--- writes always land in SavedVariables. Preview items can be compiled purely
--- from SpecDefaults; writing through such an item must first create its saved
--- entry, and it must copy the default shape (square/bar/frame effect) so the
--- first write does not flatten the indicator into the generic icon defaults.
function SI.MaterializeAuraConfig(siCfg, specKey, auraName)
  if not (type(siCfg) == "table" and specKey and auraName and auraName ~= "") then return nil end
  siCfg.specs = type(siCfg.specs) == "table" and siCfg.specs or {}
  local specCfg = siCfg.specs[specKey]
  if type(specCfg) ~= "table" then
    specCfg = {}
    siCfg.specs[specKey] = specCfg
  end
  local entry = specCfg[auraName]
  if type(entry) == "table" then return entry end
  local def = SI.SpecDefaults and SI.SpecDefaults[specKey] and SI.SpecDefaults[specKey][auraName]
  if type(def) == "table" then
    entry = (GF._DeepCopyTable or CopyTable)(def)
    if entry.onlyOwn == nil then entry.onlyOwn = true end
  else
    entry = { enabled = true, onlyOwn = true }
  end
  specCfg[auraName] = entry
  return entry
end

function SI.InvalidateRuntimeCaches()
  SI.RefreshFromDB()
  -- Saved geometry can be edited while a live container's cached button
  -- anchors no longer match reality (native re-layout, world transitions).
  -- Flag every spell-indicator container so the refresh that follows this
  -- config change re-imposes saved geometry instead of trusting that cache;
  -- previously only zone-load events requested this repair.
  local a3 = MSUF.MSUF_Auras3
  local runtime = a3 and a3.SpellIndicators
  if runtime and type(runtime.RequestGeometryRepair) == "function" then
    runtime.RequestGeometryRepair()
  end
end
