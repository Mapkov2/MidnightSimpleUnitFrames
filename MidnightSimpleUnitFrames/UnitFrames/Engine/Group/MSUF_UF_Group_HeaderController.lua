--- Ordered secure-header recipes. Callers own OOC setup, positioning and showing.
local _, MSUF = ...
local GF, UF = MSUF.GF, MSUF.UF
local NIL_ATTRIBUTE = {}
local INITIAL_KEYS = { "auraContainerTemplate", "template", "templateType", "initial-width", "initial-height" }
local VISIBILITY_KEYS = { "showPlayer", "showSolo", "showParty", "showRaid" }
local GEOMETRY_KEYS = { "point", "xOffset", "yOffset", "columnSpacing", "columnAnchorPoint", "unitsPerColumn", "maxColumns" }
local SORT_KEYS = { "nameList", "sortMethod", "sortDir", "groupBy", "groupingOrder", "_msufSortMode", "_msufPlayerFirstInRole" }
local GROUP_HIDE_KEYS = { "auraContainerTemplate", "template", "xOffset", "yOffset", "columnSpacing", "groupFilter",
  "sortMethod", "sortDir", "groupBy", "groupingOrder", "nameList", "_msufSortMode", "_msufPlayerFirstInRole" }
local GROUP_TOPOLOGY_KEYS = { "point", "columnAnchorPoint", "unitsPerColumn", "maxColumns" }
local PRIORITY_TOPOLOGY_KEYS = { "point", "xOffset", "yOffset", "unitsPerColumn", "maxColumns" }
local PRIORITY_SORT_KEYS = { "groupFilter", "roleFilter", "groupBy", "groupingOrder", "nameList", "sortMethod", "sortDir" }
local PET_KEYS = { "template", "templateType", "showRaid", "showParty", "showPlayer", "showSolo", "sortMethod",
  "startingIndex", "point", "xOffset", "yOffset", "columnAnchorPoint", "columnSpacing", "unitsPerColumn", "maxColumns",
  "initialConfigFunction" }

GF.HeaderRecipes = {
  group = {
    versionKey = "_msufSecureInitVersion",
    hideKeys = GROUP_HIDE_KEYS, topologyKeys = GROUP_TOPOLOGY_KEYS,
    steps = { INITIAL_KEYS, "version", { "oUF-headerType" }, "ping", "initial", VISIBILITY_KEYS, GEOMETRY_KEYS, "sort" },
  },
  priority = {
    versionKey = "_msufPrioritySecureInitVersion", kindChange = true,
    hideKeys = { "auraContainerTemplate", "template", "nameList" }, topologyKeys = PRIORITY_TOPOLOGY_KEYS,
    steps = { INITIAL_KEYS, "version", { "oUF-headerType", "_msufPriorityHeader" }, "ping", "initial",
      VISIBILITY_KEYS, PRIORITY_SORT_KEYS, GEOMETRY_KEYS },
  },
  pets = { ignore = true, steps = { PET_KEYS } },
}

local function Different(cache, key, value)
  return cache[key] ~= (value == nil and NIL_ATTRIBUTE or value)
end

local function KeysChanged(cache, keys, values)
  if not keys then return false end
  for i = 1, #keys do
    local key = keys[i]
    local value = values[key]
    if cache[key] ~= (value == nil and NIL_ATTRIBUTE or value) then return true end
  end
  return false
end

local function Write(header, cache, key, value, ignore)
  local normalized = value == nil and NIL_ATTRIBUTE or value
  if cache[key] == normalized then return false end
  if ignore and not header._msufHeaderWriting then
    header:SetAttribute("_ignore", true)
    header._msufHeaderWriting = true
  end
  header:SetAttribute(key, value)
  cache[key] = normalized
  return true
end

local function WriteKeys(header, cache, keys, values, ignore)
  local changed = false
  for i = 1, #keys do
    local key = keys[i]
    changed = Write(header, cache, key, values[key], ignore) or changed
  end
  return changed
end

local function ResetChildAnchors(header)
  for index = 1, 40 do
    local child = header:GetAttribute("child" .. index)
    if not child then return end
    if child.ClearAllPoints then child:ClearAllPoints() end
  end
end

local function WritePingBindings(header, cache)
  if not UF.ForEachPingBindingAttribute then return false end
  if not header._msufHeaderPingWriter then
    header._msufHeaderPingWriter = function(key, value)
      header._msufHeaderPingChanged = Write(header, cache, key, value) or header._msufHeaderPingChanged
    end
  end
  header._msufHeaderPingChanged = false
  UF.ForEachPingBindingAttribute(header._msufHeaderPingWriter)
  return header._msufHeaderPingChanged
end

local function WriteSort(header, cache, values)
  local named = values.sortMethod == "NAMELIST"
  local changed = false
  if not named then changed = Write(header, cache, "groupFilter", values.groupFilter) end
  changed = WriteKeys(header, cache, SORT_KEYS, values) or changed
  if named then changed = Write(header, cache, "groupFilter", nil) or changed end
  return changed
end

-- All recipes use the same nil-aware attribute cache. Only pet recipes batch
-- under _ignore; main recipes retain their hide/configure/show ownership path.
function GF.HeaderController(header, recipe, values, buildInitial)
  local cache = header._msufGFAttrCache
  if not cache then cache = {} header._msufGFAttrCache = cache end
  local kindChanged = recipe.kindChange and header._msufGFKind ~= nil and header._msufGFKind ~= values.kind
  if not kindChanged and not KeysChanged(cache, recipe.attributes, values) then
    if recipe.ignore then return false, false end
    return WritePingBindings(header, cache), false
  end
  local initChanged = recipe.versionKey and (Different(cache, "initial-width", values["initial-width"])
    or Different(cache, "initial-height", values["initial-height"])
    or Different(cache, recipe.versionKey, values[recipe.versionKey]))
  local topologyChanged = KeysChanged(cache, recipe.topologyKeys, values)
  local shouldHide = not recipe.ignore and header.IsShown and header:IsShown()
    and (kindChanged or initChanged or topologyChanged or KeysChanged(cache, recipe.hideKeys, values))
  if shouldHide then header:Hide() end
  if topologyChanged then ResetChildAnchors(header) end

  local changed = kindChanged or false
  for i = 1, #recipe.steps do
    local step = recipe.steps[i]
    if type(step) == "table" then
      changed = WriteKeys(header, cache, step, values, recipe.ignore) or changed
    elseif step == "version" then
      changed = Write(header, cache, recipe.versionKey, values[recipe.versionKey]) or changed
    elseif step == "ping" then
      changed = WritePingBindings(header, cache) or changed
    elseif step == "initial" and initChanged then
      header:SetAttribute("initialConfigFunction", buildInitial(values["initial-width"], values["initial-height"]))
      changed = true
    elseif step == "sort" then
      changed = WriteSort(header, cache, values) or changed
    end
  end
  if recipe.ignore and changed then
    header._msufHeaderWriting = nil
    header:SetAttribute("_ignore", nil)
    header:SetAttribute("_msufLayoutNonce", (header:GetAttribute("_msufLayoutNonce") or 0) + 1)
  end
  return changed, shouldHide
end

-- Flatten once at load for the common unchanged-roster pass. The write steps
-- remain ordered above; this list only checks their same cached attributes.
for _, recipe in pairs(GF.HeaderRecipes) do
  local attributes = {}
  for i = 1, #recipe.steps do
    local step = recipe.steps[i]
    local keys = type(step) == "table" and step or step == "sort" and SORT_KEYS or nil
    if keys then
      for j = 1, #keys do attributes[#attributes + 1] = keys[j] end
    elseif step == "version" then attributes[#attributes + 1] = recipe.versionKey end
    if step == "sort" then attributes[#attributes + 1] = "groupFilter" end
  end
  recipe.attributes = attributes
end
