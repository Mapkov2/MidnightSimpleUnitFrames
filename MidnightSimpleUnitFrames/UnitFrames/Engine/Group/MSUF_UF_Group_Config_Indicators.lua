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

local function IconZoom(value)
  value = Num(value, 100)
  if value < 100 then return 100 end
  if value > 200 then return 200 end
  return value
end

local function IconScale(value)
  value = Num(value, 100)
  if value < 20 then value = 20 end
  if value > 300 then value = 300 end
  return value / 100
end

local function Scaled(value, scale, fallback)
  value = Num(value, fallback)
  scale = tonumber(scale) or 1
  return floor((value * scale) + 0.5)
end

local function NormalizeFrameStrata(value, fallback)
  local normalize = _G.MSUF_NormalizeFrameStrata
  if type(normalize) == "function" then return normalize(value, fallback or "AUTO") end
  if value == nil or value == "" then return fallback or "AUTO" end
  value = tostring(value):upper()
  if value == "AUTO" then return "AUTO" end
  local rank = _G.MSUF_FRAME_STRATA_RANK
  return rank and rank[value] and value or (fallback or "AUTO")
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

local function AddCustomSpellID(hash, list, spellID)
  spellID = tonumber(spellID)
  if not spellID then return 0 end
  spellID = floor(spellID + 0.5)
  if spellID <= 0 or hash[spellID] == true then return 0 end
  hash[spellID] = true
  list[#list + 1] = spellID
  return 1
end

local function CustomSpellIDSignature(list)
  if type(list) ~= "table" or #list == 0 then return nil end
  local parts = {}
  for i = 1, #list do parts[i] = tostring(list[i]) end
  return table_concat(parts, ",")
end

local function ParseCustomSpellIDs(value)
  if value == nil then return nil, nil, nil end
  local hash, list, count = {}, {}, 0
  value = tostring(value)
  for token in value:gmatch("%d+") do
    count = count + AddCustomSpellID(hash, list, token)
  end
  if count <= 0 then return nil, nil, nil end
  table_sort(list)
  return hash, list, CustomSpellIDSignature(list)
end

local function NormalizeCornerCustomFilter(value)
  value = tostring(value or "HELPFUL|PLAYER"):upper():gsub("%s+", "")
  local base = value:find("HARMFUL", 1, true) and "HARMFUL" or "HELPFUL"
  if value:find("PLAYER", 1, true) then return base .. "|PLAYER" end
  return base
end

local function CustomCornerColor(custom)
  local color = type(custom and custom.color) == "table" and custom.color or nil
  return {
    Alpha(custom and (custom.r or (color and color.r) or (color and color[1])), 0.40),
    Alpha(custom and (custom.g or (color and color.g) or (color and color[2])), 1.00),
    Alpha(custom and (custom.b or (color and color.b) or (color and color[3])), 0.40),
    Alpha(custom and (custom.a or custom.alpha or (color and color.a) or (color and color[4])), 1.00),
  }
end

local function CompileCustomCornerSlot(conf, slot, size, alpha, layer, strata)
  local custom = type(conf and conf["ciCustom" .. tostring(slot and slot.key or "")]) == "table"
    and conf["ciCustom" .. tostring(slot and slot.key or "")] or nil
  local includeSpellIDs, spellIDs, spellIDSignature = ParseCustomSpellIDs(custom and custom.spells)
  if not includeSpellIDs then return nil end
  local color = CustomCornerColor(custom)
  color[4] = Alpha(color[4], 1) * Alpha(alpha, 1)
  return {
    key = "corner:" .. tostring(slot.key),
    cornerSlotKey = slot.key,
    display = "Corner " .. tostring(slot.key),
    enabled = true,
    layer = layer,
    strata = strata,
    onlyOwn = false,
    spellIDs = spellIDs,
    includeSpellIDs = includeSpellIDs,
    spellIDSignature = spellIDSignature,
    customFilter = NormalizeCornerCustomFilter(custom and custom.filter),
    mode = tostring(custom and custom.mode or "present"),
    placed = {
      type = "square",
      anchor = slot.anchor,
      x = slot.x,
      y = slot.y,
      size = size,
      barWidth = size,
      missing = false,
      showCooldownSwipe = false,
      showCooldown = false,
      showStacks = false,
    },
    color = color,
  }
end

--- Corner indicators use normal runtime logic for threat slots and native
--- AuraContainer sensors for dispellable slots.
function GF.CompileCornerIndicators(conf)
  conf = conf or {}
  local general = GeneralDB() or {}
  local size = Num(conf.ciSize, 8)
  local alpha = Alpha(conf.ciAlpha, 1)
  local layer = Layer(conf.ciLayer, 7)
  local strata = NormalizeFrameStrata(conf.ciStrata, "AUTO")
  local slots, slotMap, aggroSlots, dispelSlots, customSlots = {}, {}, {}, {}, {}
  local hasWork, needsThreat, needsDispel, needsCustom = false, false, false, false
  for i = 1, #CI_SLOT_FIELDS do
    local field = CI_SLOT_FIELDS[i]
    local slotKey = field[1]
    local category = conf["ciSlot" .. slotKey] or "none"
    local slot = {
      key = slotKey,
      category = category,
      anchor = field[2],
      x = field[3],
      y = field[4],
    }
    if category ~= "none" then
      if category == "aggro" then
        hasWork = true
        needsThreat = true
        aggroSlots[#aggroSlots + 1] = slot
      elseif category == "dispel" then
        hasWork = true
        needsDispel = true
        dispelSlots[#dispelSlots + 1] = slot
      elseif category == "custom" then
        local customSlot = CompileCustomCornerSlot(conf, slot, size, alpha, layer, strata)
        if customSlot then
          hasWork = true
          needsCustom = true
          customSlots[#customSlots + 1] = customSlot
        end
      end
    end
    slots[#slots + 1] = slot
    slotMap[slotKey] = slot
  end
  return {
    enabled = conf.ciEnabled == true,
    hasWork = hasWork,
    needsAura = needsDispel or needsCustom,
    needsThreat = needsThreat,
    needsDispel = needsDispel,
    needsCustom = needsCustom,
    size = size,
    alpha = alpha,
    layer = layer,
    strata = strata,
    slots = slots,
    aggroSlots = aggroSlots,
    dispelSlots = dispelSlots,
    customSlots = customSlots,
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

local function AddSpellIDAliases(hash, list, si, spellID)
  spellID = tonumber(spellID)
  if not spellID then return 0 end
  spellID = floor(spellID + 0.5)
  local aliases = si and ((si.AuraSpellIDAliases and si.AuraSpellIDAliases[spellID])
    or (si.CustomAuraAliases and si.CustomAuraAliases[spellID]))
  if aliases == nil then return 0 end
  if type(aliases) ~= "table" then return AddSpellID(hash, list, aliases) end
  local count = 0
  for key, value in pairs(aliases) do
    if value == true then
      count = count + AddSpellID(hash, list, key)
    elseif value ~= false then
      count = count + AddSpellID(hash, list, value)
    end
  end
  return count
end

local function AddSpellIDWithAliases(hash, list, si, spellID)
  local count = AddSpellID(hash, list, spellID)
  count = count + AddSpellIDAliases(hash, list, si, spellID)
  return count
end

local function AddSpellIDsForAura(hash, list, si, specKey, auraName, entry)
  if not (hash and list and si and specKey and auraName) then return 0 end
  local count = 0
  local includeAliases = type(entry) == "table" and entry.custom == true
  local function AddResolved(spellID)
    if includeAliases then return AddSpellIDWithAliases(hash, list, si, spellID) end
    return AddSpellID(hash, list, spellID)
  end
  local id = tonumber(auraName)
  if id then count = count + AddResolved(id) end
  if type(entry) == "table" then
    count = count + AddResolved(entry.spellID or entry.spellId or entry.id)
    if type(entry.spells) == "string" then
      for token in entry.spells:gmatch("%d+") do
        count = count + AddResolved(token)
      end
    end
  end
  local ids = si.SpellIDs and si.SpellIDs[specKey]
  if ids then count = count + AddResolved(ids[auraName]) end
  local secretIDs = si.SecretSpellIDs and si.SecretSpellIDs[specKey]
  if secretIDs then count = count + AddResolved(secretIDs[auraName]) end
  local altIDs = si.AltSpellIDs and si.AltSpellIDs[specKey]
  if type(altIDs) == "table" then
    for spellID, mappedAuraName in pairs(altIDs) do
      if mappedAuraName == auraName then count = count + AddResolved(spellID) end
    end
  end
  local linked = si.LinkedAuraRules and si.LinkedAuraRules[specKey] and si.LinkedAuraRules[specKey][auraName]
  if type(linked) == "table" then
    count = count + AddResolved(linked.sourceSpellID)
    if type(linked.targetSpellIDs) == "table" then
      for i = 1, #linked.targetSpellIDs do
        count = count + AddResolved(linked.targetSpellIDs[i])
      end
    end
  end
  local trackable = si.TrackableAuras and si.TrackableAuras[specKey]
  if type(trackable) == "table" then
    for i = 1, #trackable do
      local info = trackable[i]
      if info and info.name == auraName then
        count = count + AddResolved(info.spellID or info.spellId or info.id)
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
    local allSpecsKey = si and si.ALL_SPECS_KEY
    local allSpecsConfig = allSpecsKey and type(siCfg and siCfg.specs) == "table" and siCfg.specs[allSpecsKey]
    if type(allSpecsConfig) == "table" and next(allSpecsConfig) ~= nil then
      AddSpec(out, seen, si, allSpecsKey)
    end
    local multi = type(siCfg and siCfg.multiSpecs) == "table" and siCfg.multiSpecs or nil
    if multi then
      for specKey, enabled in pairs(multi) do
        if enabled == true and specKey ~= allSpecsKey then AddSpec(out, seen, si, specKey) end
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

local function NormalizePlaced(placed, iconScale)
  if type(placed) ~= "table" then return nil end
  local kind = tostring(placed.type or "icon"):lower()
  if kind ~= "icon" and kind ~= "square" and kind ~= "bar" and kind ~= "number" and kind ~= "none" then
    kind = "icon"
  end
  local growth = tostring(placed.growth or "RIGHTDOWN"):upper()
  if growth ~= "RIGHTDOWN" and growth ~= "LEFTDOWN" and growth ~= "RIGHTUP" and growth ~= "LEFTUP" then
    growth = "RIGHTDOWN"
  end
  return {
    type = kind,
    anchor = tostring(placed.anchor or "TOPLEFT"):upper(),
    x = Num(placed.x, 0),
    y = Num(placed.y, 0),
    size = Scaled(placed.size, iconScale, 18),
    barWidth = Scaled(placed.barWidth, iconScale, Num(placed.width, 54)),
    growth = growth,
    barSmoothFill = placed.barSmoothFill == true,
    barShowTimer = placed.barShowTimer == true,
    barTimerAnchor = tostring(placed.barTimerAnchor or "CENTER"):upper(),
    barTimerX = Num(placed.barTimerX, 0),
    barTimerY = Num(placed.barTimerY, 0),
    iconEffect = tostring(placed.iconEffect or "none"):lower(),
    missing = false,
    showCooldownSwipe = placed.showCooldownSwipe ~= false,
    showCooldown = placed.showCooldown ~= false,
    cooldownSize = Num(placed.cooldownSize, 8),
    showStacks = placed.showStacks ~= false,
    _msufIconScaleApplied = true,
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
    layer = Layer(frame.layer, 0),
    strata = NormalizeFrameStrata(frame.strata, "AUTO"),
  }
end

local function CompileSpellIndicatorItem(si, specKey, auraName, entry, order, globalLayer, iconScale)
  if type(entry) ~= "table" or entry.enabled == false then return nil end
  local ids, hash = {}, {}
  local idCount = AddSpellIDsForAura(hash, ids, si, specKey, auraName, entry)
  if idCount <= 0 then return nil end
  local placed = NormalizePlaced(entry.placed, iconScale)
  local frame = NormalizeFrameEffect(entry.frame)
  if placed and placed.type == "none" and not frame then placed = nil end
  if not placed and not frame then return nil end
  local info = TrackableInfo(si, specKey, auraName)
  local color = type(entry.color) == "table" and entry.color or (type(info and info.color) == "table" and info.color) or nil
  local display = entry.display or (info and info.display) or tostring(auraName)
  local custom = entry.custom == true or (info and info.custom == true) or false
  local onlyOwn
  if custom then
    onlyOwn = entry._msufCustomOnlyOwnExplicit == true and entry.onlyOwn == true
  else
    onlyOwn = entry.onlyOwn ~= false
  end
  local externalDefensive = type(si.IsExternalDefensiveAura) == "function"
    and si.IsExternalDefensiveAura(specKey, auraName, entry) == true
  local nativeFilter
  if externalDefensive then
    nativeFilter = onlyOwn and "HELPFUL|EXTERNAL_DEFENSIVE|PLAYER"
      or "HELPFUL|EXTERNAL_DEFENSIVE"
  end
  return {
    key = tostring(specKey) .. ":" .. tostring(auraName),
    specKey = specKey,
    auraName = auraName,
    display = display,
    enabled = true,
    custom = custom,
    order = order or 999,
    layer = Layer(entry.layer, globalLayer or 9),
    strata = entry.strata ~= nil and NormalizeFrameStrata(entry.strata, "AUTO") or nil,
    onlyOwn = onlyOwn,
    externalDefensive = externalDefensive,
    nativeFilter = nativeFilter,
    spellIDs = ids,
    includeSpellIDs = hash,
    spellIDSignature = SpellIDSignature(ids),
    placed = placed,
    frame = frame,
    icon = entry.icon or (si.GetAuraIcon and si.GetAuraIcon(specKey, auraName) or nil),
    color = {
      Alpha(color and (color[1] or color.r), 0.69),
      Alpha(color and (color[2] or color.g), 0.50),
      Alpha(color and (color[3] or color.b), 0.88),
      Alpha(color and (color[4] or color.a), 1),
    },
  }
end

local function CompileSpecItems(out, si, siCfg, specKey, globalLayer, iconScale)
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
        local item = CompileSpellIndicatorItem(si, specKey, auraName, entry, i, globalLayer, iconScale)
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
      local item = CompileSpellIndicatorItem(si, specKey, auraName, entry, 1000 + i, globalLayer, iconScale)
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
      iconZoom = IconZoom(siCfg and siCfg.iconZoom),
      iconScale = IconScale(siCfg and siCfg.iconScale),
      style = CopyTable(siCfg and siCfg.style),
      strata = NormalizeFrameStrata(siCfg and siCfg.strata, "AUTO"),
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
  local strata = NormalizeFrameStrata(siCfg.strata, "AUTO")
  local iconScale = IconScale(siCfg.iconScale)
  local specs = CollectSpecs(siCfg, si)
  local items, watched, watchedCount = {}, {}, 0
  for i = 1, #specs do
    CompileSpecItems(items, si, siCfg, specs[i], layer, iconScale)
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
    iconZoom = IconZoom(siCfg.iconZoom),
    iconScale = iconScale,
    style = CopyTable(siCfg.style),
    strata = strata,
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
