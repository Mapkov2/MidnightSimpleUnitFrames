-- Core/MSUF_RangeFade.lua
-- R41z0r-style Range Fade (Target-only, event-driven, 0 polling)
-- Fix: robust 12.0 SpellBook scan so we actually enable at least 1 ranged spell for checksRange=true.

local _G = _G
local type = type
local tonumber = tonumber
local pairs = pairs
local wipe = wipe

-- ==== Feature detection ====
local hasCSpell = (type(C_Spell) == "table")
local EnableSpellRangeCheck = hasCSpell and C_Spell.EnableSpellRangeCheck or nil
local SpellHasRange = hasCSpell and C_Spell.SpellHasRange or nil
local GetSpellIDForSpellIdentifier = hasCSpell and C_Spell.GetSpellIDForSpellIdentifier or nil

local hasCSpellBook = (type(C_SpellBook) == "table")
local GetNumSkillLines = hasCSpellBook and C_SpellBook.GetNumSpellBookSkillLines or nil
local GetSkillLineInfo = hasCSpellBook and C_SpellBook.GetSpellBookSkillLineInfo or nil
local GetSpellBookItemInfo = hasCSpellBook and C_SpellBook.GetSpellBookItemInfo or nil
local GetSpellBookItemSpellInfo = hasCSpellBook and C_SpellBook.GetSpellBookItemSpellInfo or nil
local GetSpellBookItemType = hasCSpellBook and C_SpellBook.GetSpellBookItemType or nil

local SPELLBOOK_BANK =
  (type(Enum) == "table" and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or "player"

local ITEMTYPE_SPELL =
  (type(Enum) == "table" and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or nil

-- ==== State ====
local RF = {
  enabled = false,
  alpha = 0.5,
  ignoreUnlimited = true,

  activeSpells = {}, -- [spellID]=true
  spellState   = {}, -- [spellID]=1 in, 0 out, nil unknown
  activeCount  = 0,

  inRangeAny = true, -- fail-safe
  lastMul = -1,
  lastSetAlpha = -1,

  maxTracked = 512,
  ignoreSpellIDs = { [2096] = true }, -- Mind Vision
}

-- ==== Helpers ====
local function ResolveSpellID(spellIdentifier)
  local id = tonumber(spellIdentifier)
  if id then return id end
  if GetSpellIDForSpellIdentifier then
    local ok = GetSpellIDForSpellIdentifier(spellIdentifier)
    if ok then return ok end
  end
  return nil
end

local function RecomputeInRangeAny()
  local anyKnown = false
  local anyTrue = false
  for _, v in pairs(RF.spellState) do
    if v ~= nil then
      anyKnown = true
      if v == 1 then
        anyTrue = true
        break
      end
    end
  end
  RF.inRangeAny = (not anyKnown) or anyTrue
end

local function DisableSpell(spellID)
  if not RF.activeSpells[spellID] then return end
  RF.activeSpells[spellID] = nil
  RF.activeCount = RF.activeCount - 1
  EnableSpellRangeCheck(spellID, false)
  RF.spellState[spellID] = nil
end

local function DisableAll()
  if EnableSpellRangeCheck then
    for spellID in pairs(RF.activeSpells) do
      EnableSpellRangeCheck(spellID, false)
    end
  end
  wipe(RF.activeSpells)
  wipe(RF.spellState)
  RF.activeCount = 0
  RF.inRangeAny = true
end

local function EnableSpell(spellID)
  if RF.activeSpells[spellID] then return end
  if RF.activeCount >= RF.maxTracked then return end
  RF.activeSpells[spellID] = true
  RF.activeCount = RF.activeCount + 1
  EnableSpellRangeCheck(spellID, true)
end

local function ShouldTrackSpell(spellID)
  if not spellID then return false end
  if RF.ignoreSpellIDs and RF.ignoreSpellIDs[spellID] then return false end
  if (RF.ignoreUnlimited == true) and SpellHasRange then
    if SpellHasRange(spellID) ~= true then
      return false
    end
  end
  return true
end

-- Apply: prefer MSUF alpha pipeline (multiplier), fallback to direct SetAlpha
local function ApplyOutOfRangeState(force)
  local mul = RF.inRangeAny and 1 or RF.alpha

  if (not force) and (mul == RF.lastMul) then
    return
  end
  RF.lastMul = mul

  -- Preferred: integrate with MSUF alpha pipeline if available
  if type(_G.MSUF_ApplyUnitAlpha) == "function" and _G.MSUF_target then
    _G.MSUF_RangeFadeMul = _G.MSUF_RangeFadeMul or {}
    _G.MSUF_RangeFadeMul.target = mul
    _G.MSUF_ApplyUnitAlpha(_G.MSUF_target, "target")
    return
  end

  -- Fallback: direct alpha on the frame
  local f = _G.MSUF_target
  if f and f.SetAlpha then
    if (not force) and (mul == RF.lastSetAlpha) then
      return
    end
    RF.lastSetAlpha = mul
    f:SetAlpha(mul)
  end
end

-- ==== Spellbook scan (robust) ====
local _wanted = {}

local function ClearWanted() wipe(_wanted) end

local function GetSlotSpellID(slot)
  -- Prefer SpellInfo API (most stable)
  if GetSpellBookItemSpellInfo then
    local sp = GetSpellBookItemSpellInfo(slot, SPELLBOOK_BANK)
    if sp then
      local sid = sp.spellID or sp.actionID or sp.spellIdentifier
      if sid then
        return tonumber(sid) or sid
      end
    end
  end

  -- Fallback to item info
  if GetSpellBookItemInfo then
    local info = GetSpellBookItemInfo(slot, SPELLBOOK_BANK)
    if info then
      local sid = info.spellID or info.actionID or info.spellIdentifier
      if sid then
        return tonumber(sid) or sid
      end
    end
  end

  return nil
end

local function IsPassiveSlot(slot)
  local info = GetSpellBookItemInfo and GetSpellBookItemInfo(slot, SPELLBOOK_BANK) or nil
  if info and (info.isPassive == true) then
    return true
  end
  -- Some builds put passive info in spell info
  if GetSpellBookItemSpellInfo then
    local sp = GetSpellBookItemSpellInfo(slot, SPELLBOOK_BANK)
    if sp and (sp.isPassive == true) then
      return true
    end
  end
  return false
end

local function IsSpellSlot(slot)
  local t = nil
  if GetSpellBookItemType then
    t = GetSpellBookItemType(slot, SPELLBOOK_BANK)
  elseif GetSpellBookItemInfo then
    local info = GetSpellBookItemInfo(slot, SPELLBOOK_BANK)
    t = info and info.itemType or nil
  end

  if t == nil then
    return true -- be permissive; we filter by SpellHasRange anyway
  end

  if ITEMTYPE_SPELL and (type(t) == "number") then
    return (t == ITEMTYPE_SPELL)
  end

  if type(t) == "string" then
    return (t == "SPELL") or (t == "Spell")
  end

  return true
end

local function BuildWantedFromSpellBook()
  ClearWanted()

  if (not EnableSpellRangeCheck) or (not SpellHasRange) then
    return
  end
  if (not GetNumSkillLines) or (not GetSkillLineInfo) then
    return
  end

  local numLines = GetNumSkillLines()
  if (not numLines) or (numLines <= 0) then
    return
  end

  local tracked = 0

  for lineIndex = 1, numLines do
    local info = GetSkillLineInfo(lineIndex)
    if info then
      local offset = info.itemIndexOffset or info.itemIndexOffsetFromStart or info.itemIndexOffsetFromStartIndex
      local numItems = info.numSpellBookItems or info.numSpellBookItemSlots or info.numSpellBookItemsInLine
      if offset and numItems and numItems > 0 then
        local first = offset + 1
        local last = offset + numItems
        for slot = first, last do
          if IsSpellSlot(slot) and (IsPassiveSlot(slot) ~= true) then
            local sid = GetSlotSpellID(slot)
            if sid then
              local spellID = tonumber(sid) or sid
              if type(spellID) == "number" and ShouldTrackSpell(spellID) then
                if not _wanted[spellID] then
                  _wanted[spellID] = true
                  tracked = tracked + 1
                  if tracked >= RF.maxTracked then
                    return
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

local function SyncActiveToWanted()
  -- disable removed
  for spellID in pairs(RF.activeSpells) do
    if not _wanted[spellID] then
      DisableSpell(spellID)
    end
  end
  -- enable new
  for spellID in pairs(_wanted) do
    if not RF.activeSpells[spellID] then
      EnableSpell(spellID)
    end
  end
  RecomputeInRangeAny()
end

-- ==== Public ====
function _G.MSUF_RangeFade_GetState()
  return RF.enabled, RF.inRangeAny, RF.alpha, RF.activeCount
end

function _G.MSUF_RangeFade_RebuildSpells()
  local db = _G.MSUF_DB
  local tdb = db and db.target

  local enabled = (tdb and tdb.rangeFadeEnabled == true)
  local alpha = (tdb and tdb.rangeFadeAlpha) or 0.5
  local ignUnl = (tdb == nil) or (tdb.rangeFadeIgnoreUnlimited ~= false)

  if _G.MSUF_UnitEditModeActive == true then
    enabled = false
  end
  if not EnableSpellRangeCheck then
    enabled = false
  end

  RF.enabled = (enabled == true)
  if type(alpha) == "number" then RF.alpha = alpha end
  RF.ignoreUnlimited = (ignUnl == true)

  if RF.enabled ~= true then
    DisableAll()
    RF.lastMul = -1
    ApplyOutOfRangeState(true)
    return
  end

  BuildWantedFromSpellBook()
  SyncActiveToWanted()

  -- If scan yields nothing, we cannot ever get checksRange=true.
  -- In that case: keep enabled but we won't fade (fail-safe). Expose via activeCount=0.
  RF.lastMul = -1
  ApplyOutOfRangeState(true)
end

function _G.MSUF_RangeFade_Reset()
  wipe(RF.spellState)
  RF.inRangeAny = true
  RF.lastMul = -1
  ApplyOutOfRangeState(true)
end

function _G.MSUF_RangeFade_OnEvent_SpellRangeUpdate(spellIdentifier, isInRange, checksRange)
  if RF.enabled ~= true then return end

  local spellID = ResolveSpellID(spellIdentifier)
  if not spellID then return end
  if not RF.activeSpells[spellID] then return end
  if RF.ignoreSpellIDs and RF.ignoreSpellIDs[spellID] then return end

  if checksRange == true then
    RF.spellState[spellID] = ((isInRange == true) or (isInRange == 1)) and 1 or 0
  else
    RF.spellState[spellID] = nil
  end

  RecomputeInRangeAny()
  ApplyOutOfRangeState(false)
end

-- ==== Wiring (no UpdateManager / no polling) ====
local function EnsureInitialized()
  -- only rebuild once target exists; otherwise it would just disable everything again
  if _G.MSUF_target then
    _G.MSUF_RangeFade_RebuildSpells()
  end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("PLAYER_TALENT_UPDATE")
f:RegisterEvent("TRAIT_CONFIG_UPDATED")
f:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")

f:SetScript("OnEvent", function(_, event, ...)
  if event == "SPELL_RANGE_CHECK_UPDATE" then
    _G.MSUF_RangeFade_OnEvent_SpellRangeUpdate(...)
    return
  end

  if event == "PLAYER_TARGET_CHANGED" then
    _G.MSUF_RangeFade_Reset()
    return
  end

  -- rebuild events
  EnsureInitialized()
end)


-- === Compatibility aliases (older MSUF mainfile integrations) ===
-- Some builds call MSUF_RangeFade_Rebuild() instead of MSUF_RangeFade_RebuildSpells().
_G.MSUF_RangeFade_Rebuild = _G.MSUF_RangeFade_RebuildSpells
_G.MSUF_RangeFade_OnSpellRangeUpdate = _G.MSUF_RangeFade_OnEvent_SpellRangeUpdate
