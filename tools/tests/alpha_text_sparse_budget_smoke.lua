-- Sparse text-layer alpha: preserve writes, order, lazy regions and cache semantics.
-- Nalorakk capture 3: SetTextLayerAlpha 6,503 calls, SetAlphaCached 208,406.
-- Repeated loops must not invoke the generic writer for absent text regions.
-- VM budgets include the shared writer: remeasure deliberate writer changes.
assert(_VERSION == "Lua 5.1" and not rawget(_G, "jit"), "standard Lua 5.1 required")
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local measure = arg[2] == "measure"
local function Read(path)
  local file = assert(io.open(root .. "/" .. path, "rb"))
  local source = file:read("*a"):gsub("\r\n", "\n")
  file:close()
  return source
end
local function Between(source, first, last)
  local a = assert(source:find(first, 1, true), first)
  local b = assert(source:find(last, a + #first, true), last)
  return source:sub(a, b - 1)
end
local base = "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/"
local alphaSource = Read(base .. "MSUF_UF_Elements_Alpha.lua")
local commonSource = Read(base .. "MSUF_UF_Visuals_Common.lua")
local metadata = Read("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Metadata.lua")
local clamp = assert(loadstring(Between(metadata, "local function Clamp01(", "UF.Clamp01 =") .. "return Clamp01"))()
local common = Between(commonSource, "local function AlphaDiffers(", "local function SetFrameAlpha(")
  .. Between(commonSource, "local function SetAlphaCached(", "local function ReadGroupRole(")
  .. "return SetAlphaCached"
local chunk = assert(loadstring(common, "@alpha_text_real_writer"))
setfenv(chunk, setmetatable({ Clamp01 = clamp, abs = math.abs }, { __index = _G }))
local write = chunk()
local fieldsCode = Between(alphaSource, "local TEXT_ALPHA_FIELDS =", "local HEALTH_GRADIENT_FIELDS =")
local fields = assert(loadstring(fieldsCode .. "return TEXT_ALPHA_FIELDS"))()
local laneCode = Between(alphaSource, "local function SetTextLayerAlpha(", "local function SetPortraitLayerAlpha(")
local truthyEntries, absent = 0, 0
local function CountedWrite(region, ...)
  if region then truthyEntries = truthyEntries + 1 else absent = absent + 1 end
  return write(region, ...)
end
local function Lane(writer)
  local fn = assert(loadstring(fieldsCode .. laneCode .. "return SetTextLayerAlpha", "@alpha_text_real_lane"))
  setfenv(fn, { SetAlphaCached = writer })
  return fn()
end
local apply, timed = Lane(CountedWrite), Lane(write)
local log = {}
local function Region(name, status)
  return { _msufStatusAlpha = status, SetAlpha = function(self, value)
    self.value = value
    log[#log + 1] = name .. ":" .. tostring(value)
  end }
end
local frame = { nameText = Region("name"), hpTextCenter = Region("health", 0.5), statusIndicatorText = Region("status", 0) }
apply(frame, 0.8)
assert(table.concat(log, ",") == "name:0.8,health:0.4,status:0", "alpha/status composition or traversal order changed")
local before = #log
apply(frame, 0.8001)
assert(#log == before, "existing alpha tolerance changed")
apply(frame, 0.8, true)
assert(#log == before + 3, "forced repaint lost")
frame.levelText = Region("late", 0.25)
apply(frame, 0.8)
assert(frame.levelText.value == 0.2, "late-created text was cached out")
frame.nameText = false
frame.hpTextCenter = nil
frame.levelText = Region("replacement", 2)
apply(frame, 0.8)
assert(frame.levelText.value == 1, "replacement or clamp changed")
local shared = Region("alias", false)
local aliasStart = #log
apply({ nameText = shared, levelText = shared }, 0.7)
assert(shared.value == 0.7, "alias or false status fallback changed")
assert(#log == aliasStart + 1, "unforced alias cache changed")
local aliasCount = #log
apply({ nameText = shared, levelText = shared }, 0.7, true)
assert(#log == aliasCount + 2, "forced alias writes were deduplicated")
local dynamic = { nameText = Region("creator") }
dynamic.nameText.SetAlpha = function(self, value)
  self.value = value
  dynamic.threatIndicatorHolder = Region("created-during-write")
end
apply(dynamic, 0.6)
assert(dynamic.threatIndicatorHolder.value == 0.6, "same-pass region creation lost")
local removed = { nameText = Region("remover"), threatIndicatorHolder = Region("removed") }
removed.nameText.SetAlpha = function() removed.threatIndicatorHolder = nil end
local removalStart = #log
apply(removed, 0.6)
assert(#log == removalStart, "removed later field was still written")
local entriesBefore = truthyEntries
apply({ nameText = {} }, 0.5)
assert(truthyEntries == entriesBefore + 1, "truthy non-writable region skipped its writer")
local seen = {}
local lazy = setmetatable({}, { __index = function(self, key)
  seen[#seen + 1] = key
  if key == "levelText" then local region = Region("lazy"); rawset(self, key, region); return region end
end })
apply(lazy, 0.3)
assert(table.concat(seen, ",") == table.concat(fields, ","), "field lookup order changed")
assert(lazy.levelText.value == 0.3, "lazy field creation lost")
apply(nil, 1)
apply(false, 1)
assert(#fields == 20, "text field inventory changed; review coverage")

-- Real helper + real clamp, allocation-free native stand-in; include nil,
-- sparse, and fully populated frames so a fast path cannot hide its trade.
local native = 0
local function SetAlpha(self, value) native = native + 1; self.value = value end
local function Budget(name, count)
  local item = {}
  for i = 1, count do item[fields[i]] = { SetAlpha = SetAlpha } end
  for i = 1, 3 do timed(item, 0.5, true) end
  native = 0
  local instructions = 0
  debug.sethook(function() instructions = instructions + 1 end, "", 1)
  for i = 1, 100 do timed(item, 0.5, true) end
  debug.sethook()
  assert(native == count * 100, name .. ": native paint count changed")
  local best, worst = math.huge, 0
  for pass = 1, 2 do
    collectgarbage("collect"); collectgarbage("stop")
    local start = collectgarbage("count")
    for i = 1, 100 do timed(item, 0.5, true) end
    local delta = collectgarbage("count") - start
    collectgarbage("restart")
    best = math.min(best, delta)
    worst = math.max(worst, delta)
  end
  print(string.format("%s: VM %d/100 passes, natives %d/100, warm allocation %.4f KiB", name, instructions, count * 100, best))
  assert(best <= 0.001 and worst <= 0.001, name .. ": repeated allocation")
  return instructions
end
local empty = Budget("empty", 0)
local sparse = Budget("three text fields", 3)
local dense = Budget("all text fields", #fields)
if not measure then
  assert(absent == 0, "empty text fields still enter the generic alpha writer: " .. absent)
  assert(empty <= 13575 and sparse <= 24897 and dense <= 89055, "text-layer VM budget exceeded")
end
print((measure and "MEASURE" or "PASS") .. " alpha_text_sparse_budget: semantics, native writes and allocation; missing-writer calls " .. absent)

-- Exercise the shipped Alpha element on real single/group frames across clients.
local World = dofile(root .. "/tools/tests/health_tick_world.lua")
for _, flavor in ipairs({ "Mainline", "Vanilla", "TBC", "Mists", "Forever" }) do
  local w = World.New(root, flavor)
  local element = w.UF.elements.Alpha
  for _, body in ipairs({ w.single, w.group }) do
    for _, key in ipairs(fields) do body[key] = nil end
    body.nameText = body:CreateFontString(nil, "OVERLAY")
    body.statusIndicatorText = body:CreateFontString(nil, "OVERLAY")
    body.statusIndicatorText._msufStatusAlpha = 0.25
    local cfg = { active = true, hpAlpha = 0.6 }
    body.MSUFSpec.alpha = cfg
    element.Apply(body, body.MSUFSpec)
    assert(body.nameText:GetAlpha() == 0.6 and body.statusIndicatorText:GetAlpha() == 0.15,
      flavor .. ": actual element lost sparse text/status alpha")
    cfg.excludeTextPortrait = true
    element.Apply(body, body.MSUFSpec)
    assert(body.nameText:GetAlpha() == 1 and body.statusIndicatorText:GetAlpha() == 0.25,
      flavor .. ": foreground exclusion changed")
    body.levelText = body:CreateFontString(nil, "OVERLAY")
    body.levelText._msufStatusAlpha = 0.7
    element.Update(body, "MSUF_FORCE_UPDATE")
    assert(body.levelText:GetAlpha() == 0.7, flavor .. ": real late text missed forced refresh")
    w.UF.ApplyRangeBoolean(body, true, true, true)
    assert(body.nameText:GetAlpha() == 1, flavor .. ": boolean range changed excluded text")
    w.UF.ApplyRangeModifier(body, 1, true)
    element.Disable(body)
    assert(body.nameText:GetAlpha() == 1 and body.statusIndicatorText:GetAlpha() == 0.25,
      flavor .. ": disable/reset changed status opacity")
  end
  print("PASS alpha_text_sparse_budget real single/group: " .. flavor)
end
