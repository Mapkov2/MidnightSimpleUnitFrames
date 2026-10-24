-- Preview requests have one owner; public flags are compatibility output only.
local _, MSUF = ...
MSUF = MSUF.Require("MSUF", "UnitFrames/Engine/MSUF_UF_Preview.lua")
MSUF.UF = MSUF.UF or {}
local UF = MSUF.UF
local Secrets = assert(MSUF.Secrets, "MSUF: missing required dependency 'Secrets' required by UF.Preview")
local IsSecret = Secrets.IsSecret
local secretKind = type(IsSecret)
assert(secretKind == "function", "MSUF: missing required dependency 'Secrets.IsSecret' required by UF.Preview")
local exportKind = type(MSUF.ExportPublic)
assert(exportKind == "function", "MSUF: missing required dependency 'ExportPublic' required by UF.Preview")
-- Both tables name every field up front, so a first request or a first forcing never rehashes them.
-- A forcing value is true (forced) or false; an arena slot that is not forced holds "prep", the only value
-- that also depends on the live arena-prep facts, so every other unit is classified by one table read.
local state = { bossHealth = false, editMode = nil, all = nil, boss = nil, arena = nil,
  bossPage = nil, arenaPage = nil, unitPage = nil }
local forcedUnits = {
  target = false, focus = false, targettarget = false, focustarget = false, pet = false, pettarget = false,
  boss1 = false, boss2 = false, boss3 = false, boss4 = false, boss5 = false,
  arena1 = "prep", arena2 = "prep", arena3 = "prep", arena4 = "prep", arena5 = "prep",
}
local Preview = { State = state, ForcedUnits = forcedUnits }
UF.Preview = Preview

-- Declare the seven initial nil outputs through the real Bootstrap publisher.
-- Subsequent commits publish through it too, so the namespace mirror and the
-- global export policy stay in one place; no request is made at declaration.
local ExportPublic, value = MSUF.ExportPublic, nil
ExportPublic("MSUF_UnitEditModeActive", value)
ExportPublic("MSUF_PreviewTestMode", value)
ExportPublic("MSUF_BossTestMode", value)
ExportPublic("MSUF_ArenaTestMode", value)
ExportPublic("MSUF2_BossUnitframePreviewActive", value)
ExportPublic("MSUF2_ArenaUnitframePreviewActive", value)
ExportPublic("MSUF_UnitPreviewActive", value)
local MIRRORS = {
  editMode = "MSUF_UnitEditModeActive", all = "MSUF_PreviewTestMode",
  boss = "MSUF_BossTestMode", arena = "MSUF_ArenaTestMode",
  bossPage = "MSUF2_BossUnitframePreviewActive", arenaPage = "MSUF2_ArenaUnitframePreviewActive",
  unitPage = "MSUF_UnitPreviewActive",
}

-- Forcing caches start derived false; no request or public mirror is touched here.
local normalForced, bossForced, arenaForced = false, false, false
local function UpdateNormalForce()
  local state, forcedUnits = state, forcedUnits
  local forced = state.all == true
  if forced ~= normalForced then
    forcedUnits.target = forced
    forcedUnits.focus = forced
    forcedUnits.targettarget = forced
    forcedUnits.focustarget = forced
    forcedUnits.pet = forced
    forcedUnits.pettarget = forced
    normalForced = forced
  end
end
local function UpdateBossForce()
  local state, forcedUnits = state, forcedUnits
  state.bossHealth = state.boss == true or state.bossPage == true
  local forced = state.bossHealth or state.all == true
  if forced ~= bossForced then
    forcedUnits.boss1 = forced
    forcedUnits.boss2 = forced
    forcedUnits.boss3 = forced
    forcedUnits.boss4 = forced
    forcedUnits.boss5 = forced
    bossForced = forced
  end
end
local function UpdateArenaForce()
  local state, forcedUnits = state, forcedUnits
  local forced = state.arena == true or state.arenaPage == true or state.all == true
  if forced ~= arenaForced then
    local value = forced or "prep"
    forcedUnits.arena1 = value
    forcedUnits.arena2 = value
    forcedUnits.arena3 = value
    forcedUnits.arena4 = value
    forcedUnits.arena5 = value
    arenaForced = forced
  end
end
local function EnableArenaForce()
  if arenaForced then return end
  local forcedUnits = forcedUnits
  forcedUnits.arena1 = true
  forcedUnits.arena2 = true
  forcedUnits.arena3 = true
  forcedUnits.arena4 = true
  forcedUnits.arena5 = true
  arenaForced = true
end
local function UpdateAllForce()
  UpdateNormalForce()
  UpdateBossForce()
  UpdateArenaForce()
end
local DERIVED = { all = UpdateAllForce, boss = UpdateBossForce, bossPage = UpdateBossForce,
  arena = UpdateArenaForce, arenaPage = UpdateArenaForce }
local function BuildRequestWriter(key, value)
  local name = MIRRORS[key]
  local updateDerived = DERIVED[key]
  if value == true and (key == "arena" or key == "arenaPage") then updateDerived = EnableArenaForce end
  return function()
    local state = state
    if state[key] == value then return false end
    state[key] = value
    if updateDerived then updateDerived() end
    ExportPublic(name, value)
    return true
  end
end

-- Fixed commands capture their literal value once and accept no runtime data.
local writers, commands = {}, {}
for key in pairs(MIRRORS) do
  local clear = BuildRequestWriter(key, nil)
  local enable, disable = BuildRequestWriter(key, true), BuildRequestWriter(key, false)
  commands[key] = { clear = clear, enable = enable, disable = disable }
  writers[key] = function(value)
    assert(not IsSecret(value), "UF.Preview.Set: protected request")
    assert(value == nil or type(value) == "boolean", "UF.Preview.Set: expected boolean or nil")
    if value == nil then return clear() end
    if value then return enable() end
    return disable()
  end
end

-- Bind a literal once. The resulting operation accepts no runtime request data.
function Preview.Bind(key, value)
  assert(not IsSecret(key), "UF.Preview.Bind: protected key")
  local command = commands[key]
  assert(command, "UF.Preview.Bind: unknown request")
  assert(not IsSecret(value), "UF.Preview.Bind: protected request")
  assert(value == nil or type(value) == "boolean", "UF.Preview.Bind: expected boolean or nil")
  if value == nil then return command.clear end
  if value then return command.enable end
  return command.disable
end

function Preview.Set(key, value)
  assert(not IsSecret(key), "UF.Preview.Set: protected key")
  local write = writers[key]
  assert(write, "UF.Preview.Set: unknown request")
  return write(value)
end

-- Named writers bind trusted keys once; generic callers still validate keys.
Preview.SetEditMode, Preview.SetAll = writers.editMode, writers.all
Preview.SetBoss, Preview.SetArena = writers.boss, writers.arena
Preview.SetBossPage, Preview.SetArenaPage = writers.bossPage, writers.arenaPage
Preview.SetUnitPage = writers.unitPage

-- Castbar boot used to publish existing-or-false; an existing request wins.
function Preview.InitializeBoss()
  if state.boss == nil then return Preview.SetBoss(false) end
  return false
end

-- Consumers validate the complete early provider once, then retain its functions.
local REQUIRED = { "SetEditMode", "SetAll", "SetBoss", "SetArena", "SetBossPage", "SetArenaPage", "SetUnitPage",
  "Set", "Bind", "InitializeBoss" }
function Preview.Validate(file)
  for i = 1, #REQUIRED do
    local name = REQUIRED[i]
    local kind = type(Preview[name])
    assert(kind == "function", "MSUF: missing required dependency 'UF.Preview." .. name .. "' required by " .. file)
  end
  local stateKind, forceKind = type(Preview.State), type(Preview.ForcedUnits)
  assert(stateKind == "table" and forceKind == "table", "MSUF: missing required preview state required by " .. file)
  return Preview
end
