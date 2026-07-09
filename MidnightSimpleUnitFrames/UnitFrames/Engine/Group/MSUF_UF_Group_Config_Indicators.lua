--- UnitFrames/Engine/Group/MSUF_UF_Group_Config_Indicators.lua
--- Compile-time normalization for group corner and spell indicators.
---
--- Keep SavedVariables interpretation here. Runtime indicator elements should
--- receive simple booleans, slots, colors, layers, and event needs.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF

local GF = MSUF.GF or {}
MSUF.GF = GF

local tonumber = tonumber
local tostring = tostring
local type = type
local pairs = pairs
local floor = math.floor
local table_sort = table.sort
local table_concat = table.concat

local function Num(value, fallback)
  value = tonumber(value)
  if value == nil then return fallback end
  return value
end

local function Alpha(value, fallback)
  value = Num(value, fallback)
  if value < 0 then return 0 end
  if value > 1 then return 1 end
  return value
end

local function Layer(value, fallback)
  value = floor((tonumber(value) or fallback or 7) + 0.5)
  if value < 0 then return 0 end
  if value > 30 then return 30 end
  return value
end

local function GeneralDB()
  local db = _G.MSUF_DB
  return type(db) == "table" and type(db.general) == "table" and db.general or nil
end

local CI_SLOT_FIELDS = {
  { "TL", "TOPLEFT", 2, -2 },
  { "TR", "TOPRIGHT", -2, -2 },
  { "BL", "BOTTOMLEFT", 2, 2 },
  { "BR", "BOTTOMRIGHT", -2, 2 },
  { "C", "CENTER", 0, 0 },
}

--- Corner indicators use normal runtime logic for threat slots and native
--- AuraContainer sensors for dispellable slots.
function GF.CompileCornerIndicators(conf)
  conf = conf or {}
  local general = GeneralDB() or {}
  local slots, slotMap, aggroSlots, dispelSlots = {}, {}, {}, {}
  local hasWork, needsThreat, needsDispel = false, false, false
  for i = 1, #CI_SLOT_FIELDS do
    local field = CI_SLOT_FIELDS[i]
    local slotKey = field[1]
    local category = conf["ciSlot" .. slotKey] or "none"
    if category == "custom" then
      category = "none"
    end
    local slot = {
      key = slotKey,
      category = category,
      anchor = field[2],
      x = field[3],
      y = field[4],
    }
    if category ~= "none" then
      hasWork = true
      if category == "aggro" then
        needsThreat = true
        aggroSlots[#aggroSlots + 1] = slot
      elseif category == "dispel" then
        needsDispel = true
        dispelSlots[#dispelSlots + 1] = slot
      end
    end
    slots[#slots + 1] = slot
    slotMap[slotKey] = slot
  end
  return {
    enabled = conf.ciEnabled == true,
    hasWork = hasWork,
    needsAura = needsDispel,
    needsThreat = needsThreat,
    needsDispel = needsDispel,
    size = Num(conf.ciSize, 8),
    alpha = Alpha(conf.ciAlpha, 1),
    layer = Layer(conf.ciLayer, 7),
    slots = slots,
    aggroSlots = aggroSlots,
    dispelSlots = dispelSlots,
    slotMap = slotMap,
    aggroMode = conf.aggroMode or general.aggroMode or "ALL",
    aggroR = Num(conf.ciAggroColorR, 1),
    aggroG = Num(conf.ciAggroColorG, 0.55),
    aggroB = Num(conf.ciAggroColorB, 0),
  }
end

local function CopyTable(src)
  if type(src) ~= "table" then return src end
  local dst = {}
  for k, v in pairs(src) do
    dst[k] = CopyTable(v)
  end
  return dst
end

local function SpellIndicatorModule()
  return GF.SpellIndicators or _G.MSUF_GF_SpellIndicators
end

local function AddSpellID(hash, list, spellID)
  spellID = tonumber(spellID)
  if not spellID then return 0 end
  spellID = floor(spellID + 0.5)
  if spellID <= 0 or hash[spellID] == true then return 0 end
  hash[spellID] = true
  list[#list + 1] = spellID
  return 1
end

local function AddSpellIDsForAura(hash, list, si, specKey, auraName, entry)
  if not (hash and list and si and specKey and auraName) then return 0 end
  local count = 0
  local id = tonumber(auraName)
  if id then count = count + AddSpellID(hash, list, id) end
  if type(entry) == "table" then
    count = count + AddSpellID(hash, list, entry.spellID or entry.spellId or entry.id)
    if type(entry.spells) == "string" then
      for token in entry.spells:gmatch("%d+") do
        count = count + AddSpellID(hash, list, token)
      end
    end
  end
  local ids = si.SpellIDs and si.SpellIDs[specKey]
  if ids then count = count + AddSpellID(hash, list, ids[auraName]) end
  local secretIDs = si.SecretSpellIDs and si.SecretSpellIDs[specKey]
  if secretIDs then count = count + AddSpellID(hash, list, secretIDs[auraName]) end
  local altIDs = si.AltSpellIDs and si.AltSpellIDs[specKey]
  if type(altIDs) == "table" then
    for spellID, mappedAuraName in pairs(altIDs) do
      if mappedAuraName == auraName then count = count + AddSpellID(hash, list, spellID) end
    end
  end
  local linked = si.LinkedAuraRules and si.LinkedAuraRules[specKey] and si.LinkedAuraRules[specKey][auraName]
  if type(linked) == "table" then
    count = count + AddSpellID(hash, list, linked.sourceSpellID)
    if type(linked.targetSpellIDs) == "table" then
      for i = 1, #linked.targetSpellIDs do
        count = count + AddSpellID(hash, list, linked.targetSpellIDs[i])
      end
    end
  end
  local trackable = si.TrackableAuras and si.TrackableAuras[specKey]
  if type(trackable) == "table" then
    for i = 1, #trackable do
      local info = trackable[i]
      if info and info.name == auraName then
        count = count + AddSpellID(hash, list, info.spellID or info.spellId or info.id)
        break
      end
    end
  end
  if count > 0 then table_sort(list) end
  return count
end

local function SpellIDSignature(list)
  if type(list) ~= "table" or #list == 0 then return nil end
  local parts = {}
  for i = 1, #list do parts[i] = tostring(list[i]) end
  return table_concat(parts, ",")
end

local function TrackableInfo(si, specKey, auraName)
  local list = si and si.TrackableAuras and si.TrackableAuras[specKey]
  if type(list) ~= "table" then return nil end
  for i = 1, #list do
    local info = list[i]
    if info and info.name == auraName then return info, i end
  end
end

local function IsKnownSpec(si, specKey)
  return specKey and si and si.SpecInfo and si.SpecInfo[specKey] ~= nil
end

local function AddSpec(out, seen, si, specKey)
  if IsKnownSpec(si, specKey) and not seen[specKey] then
    seen[specKey] = true
    out[#out + 1] = specKey
  end
end

local function CollectSpecs(siCfg, si)
  local out, seen = {}, {}
  local selected = siCfg and siCfg.spec or "auto"
  if selected == "multi" then
    local multi = type(siCfg and siCfg.multiSpecs) == "table" and siCfg.multiSpecs or nil
    if multi then
      for specKey, enabled in pairs(multi) do
        if enabled == true then AddSpec(out, seen, si, specKey) end
      end
    end
  elseif selected ~= "auto" then
    AddSpec(out, seen, si, selected)
  end
  if #out == 0 and si and type(si.GetPlayerSpec) == "function" then
    AddSpec(out, seen, si, si.GetPlayerSpec())
  end
  return out
end

local function MergeSpellEntry(saved, defaults)
  local out = CopyTable(defaults) or {}
  if type(saved) == "table" then
    for k, v in pairs(saved) do out[k] = CopyTable(v) end
  elseif saved == false then
    out.enabled = false
  end
  return out
end

local function NormalizePlaced(placed)
  if type(placed) ~= "table" then return nil end
  local kind = tostring(placed.type or "icon"):lower()
  if kind ~= "icon" and kind ~= "square" and kind ~= "bar" and kind ~= "number" and kind ~= "none" then
    kind = "icon"
  end
  return {
    type = kind,
    anchor = tostring(placed.anchor or "TOPLEFT"):upper(),
    x = Num(placed.x, 0),
    y = Num(placed.y, 0),
    size = Num(placed.size, 18),
    barWidth = Num(placed.barWidth, Num(placed.width, 54)),
    growth = placed.growth,
    missing = false,
    showCooldownSwipe = placed.showCooldownSwipe ~= false,
    showCooldown = placed.showCooldown ~= false,
    showStacks = placed.showStacks ~= false,
  }
end

local function NormalizeFrameEffect(frame)
  if type(frame) ~= "table" then return nil end
  local kind = tostring(frame.type or "none"):lower()
  if kind == "" or kind == "none" then return nil end
  local color = type(frame.color) == "table" and frame.color or {}
  return {
    type = kind,
    color = {
      Alpha(color[1] or color.r, 1),
      Alpha(color[2] or color.g, 1),
      Alpha(color[3] or color.b, 1),
      Alpha(color[4] or color.a, 1),
    },
    priority = Num(frame.priority, 5),
    tintAlpha = Alpha(frame.tintAlpha or frame.alpha, color[4] or color.a or 0.20),
    thickness = Num(frame.thickness, 2),
  }
end

local function CompileSpellIndicatorItem(si, specKey, auraName, entry, order, globalLayer)
  if type(entry) ~= "table" or entry.enabled == false then return nil end
  local ids, hash = {}, {}
  local idCount = AddSpellIDsForAura(hash, ids, si, specKey, auraName, entry)
  if idCount <= 0 then return nil end
  local placed = NormalizePlaced(entry.placed)
  -- 12.1 PTR AuraSlot frame effects are disabled for now. The icon slot still
  -- compiles normally, but saved border/tint/glow settings do not enter preview
  -- or live runtime until we have a non-secret signal for assigned slots.
  local frame = nil
  if placed and placed.type == "none" and not frame then placed = nil end
  if not placed and not frame then return nil end
  local info = TrackableInfo(si, specKey, auraName)
  local color = type(entry.color) == "table" and entry.color or (type(info and info.color) == "table" and info.color) or nil
  local display = entry.display or (info and info.display) or tostring(auraName)
  return {
    key = tostring(specKey) .. ":" .. tostring(auraName),
    specKey = specKey,
    auraName = auraName,
    display = display,
    enabled = true,
    order = order or 999,
    layer = Layer(entry.layer, globalLayer or 9),
    onlyOwn = entry.onlyOwn ~= false,
    spellIDs = ids,
    includeSpellIDs = hash,
    spellIDSignature = SpellIDSignature(ids),
    placed = placed,
    frame = frame,
    icon = si.GetAuraIcon and si.GetAuraIcon(specKey, auraName) or nil,
    color = {
      Alpha(color and (color[1] or color.r), 0.69),
      Alpha(color and (color[2] or color.g), 0.50),
      Alpha(color and (color[3] or color.b), 0.88),
      Alpha(color and (color[4] or color.a), 1),
    },
  }
end

local function CompileSpecItems(out, si, siCfg, specKey, globalLayer)
  local specCfg = type(siCfg and siCfg.specs) == "table" and siCfg.specs[specKey] or nil
  local defaults = si and si.SpecDefaults and si.SpecDefaults[specKey] or nil
  local trackable = si and si.TrackableAuras and si.TrackableAuras[specKey] or nil
  local seen = {}
  if type(trackable) == "table" then
    for i = 1, #trackable do
      local auraName = trackable[i] and trackable[i].name
      if auraName then
        seen[auraName] = true
        local entry = MergeSpellEntry(type(specCfg) == "table" and specCfg[auraName] or nil, type(defaults) == "table" and defaults[auraName] or nil)
        local item = CompileSpellIndicatorItem(si, specKey, auraName, entry, i, globalLayer)
        if item then out[#out + 1] = item end
      end
    end
  end
  if type(specCfg) == "table" then
    local extras = {}
    for auraName in pairs(specCfg) do
      if not seen[auraName] then extras[#extras + 1] = auraName end
    end
    table_sort(extras, function(a, b) return tostring(a) < tostring(b) end)
    for i = 1, #extras do
      local auraName = extras[i]
      local entry = MergeSpellEntry(specCfg[auraName], type(defaults) == "table" and defaults[auraName] or nil)
      local item = CompileSpellIndicatorItem(si, specKey, auraName, entry, 1000 + i, globalLayer)
      if item then out[#out + 1] = item end
    end
  end
end

--- Spell indicators keep the old 5.7 per-spell model, but the runtime consumes
--- this as 12.1 CustomAuraContainer aura slots. Each item is one manually
--- anchored, exact SpellID-filtered helpful aura slot plus optional frame effect.
function GF.CompileSpellIndicators(conf)
  local si = SpellIndicatorModule()
  local siCfg = type(conf and conf.spellIndicators) == "table" and conf.spellIndicators or nil
  if not (si and siCfg and siCfg.enabled == true) then
    return {
      enabled = false,
      layer = 9,
      spec = siCfg and siCfg.spec or "auto",
      activeSpec = nil,
      specs = {},
      items = {},
      watched = nil,
      hasMissing = false,
      hasEffects = false,
    }
  end
  local layer = Layer(siCfg.layer, 9)
  local specs = CollectSpecs(siCfg, si)
  local items, watched, watchedCount = {}, {}, 0
  for i = 1, #specs do
    CompileSpecItems(items, si, siCfg, specs[i], layer)
  end
  table_sort(items, function(a, b)
    if a.specKey ~= b.specKey then return tostring(a.specKey) < tostring(b.specKey) end
    if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) < (b.order or 0) end
    return tostring(a.display or a.auraName) < tostring(b.display or b.auraName)
  end)
  local hasMissing, hasEffects = false, false
  for i = 1, #items do
    local item = items[i]
    item.index = i
    if item.placed and item.placed.missing == true then hasMissing = true end
    if item.frame then hasEffects = true end
    if type(item.spellIDs) == "table" then
      for j = 1, #item.spellIDs do
        local spellID = item.spellIDs[j]
        if watched[spellID] ~= true then
          watched[spellID] = true
          watchedCount = watchedCount + 1
        end
      end
    end
  end
  return {
    enabled = #items > 0,
    layer = layer,
    spec = siCfg.spec or "auto",
    activeSpec = specs[1],
    specs = specs,
    items = items,
    watched = watchedCount > 0 and watched or nil,
    watchedCount = watchedCount,
    hasMissing = hasMissing,
    hasEffects = hasEffects,
  }
end
