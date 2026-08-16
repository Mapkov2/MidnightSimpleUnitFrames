local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

local UF = MSUF.UF
if not UF then return end

-- AFK duration ledger for the status-indicator AFK timer text.
--
-- Stamps the moment a unit's AFK flag turns on, keyed by GUID so every frame
-- observing the same character (party slot, target, focus) reads one shared
-- start time. Strictly out-of-combat: entering combat cancels the refresh
-- ticker, unregisters the flags listener and hides every visible timer text,
-- so the in-combat cost is exactly zero and no restricted-identity read can
-- happen while lockdown rules are in force. Durations whose start edge was
-- never observed (unit was already AFK when first seen, or toggled during
-- combat) stay unknown on purpose: the timer text simply does not show.
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UnitGUID = UnitGUID
local UnitIsAFK = UnitIsAFK
local UnitExists = UnitExists
local GetTime = GetTime
local C_Timer = C_Timer
local IsInRaid = IsInRaid
local type = type
local pairs = pairs
local floor = math.floor

local issecretvalue = _G.issecretvalue or function(_) return false end

local afkSince = {}        -- guid -> GetTime() stamp of the observed AFK-on edge
local attached = {}        -- frame -> true while its AFK timer text is visible
local attachedCount = 0
local suspended = {}       -- frames hidden by combat entry, re-poked on combat end
local combatActive = false
local ticker = nil

local TICK_SECONDS = 10
local SAMPLE_TEXT = "5m"

local function Now()
  if type(GetTime) == "function" then
    return GetTime()
  end
  return 0
end

--- Secret-safe GUID read: a restricted identity must neither raise on the
--- table access below nor poison the ledger with a secret key.
local function PlainGUID(unit)
  if type(unit) ~= "string" or unit == "" then return nil end
  if type(UnitGUID) ~= "function" then return nil end
  local guid = UnitGUID(unit)
  if issecretvalue(guid) == true then return nil end
  if type(guid) ~= "string" or guid == "" then return nil end
  return guid
end

--- Secret-safe AFK read collapsed to a plain tri-state: true / false / nil
--- (nil = unknown, never touch the ledger from an unknown).
local function PlainAFK(unit)
  if type(UnitIsAFK) ~= "function" then return nil end
  local afk = UnitIsAFK(unit)
  if issecretvalue(afk) == true then return nil end
  if afk == true or afk == 1 then return true end
  return false
end

local function FormatDuration(seconds)
  if type(seconds) ~= "number" or seconds < 0 then return nil end
  if seconds < 60 then return "<1m" end
  local minutes = floor(seconds / 60)
  if minutes < 60 then return minutes .. "m" end
  local hours = floor(minutes / 60)
  return hours .. "h " .. (minutes % 60) .. "m"
end

local function StopTicker()
  if ticker then
    if ticker.Cancel then ticker:Cancel() end
    ticker = nil
  end
end

local function PokeFrame(frame)
  local runtime = MSUF.UFStatusRuntime
  local update = runtime and runtime.UpdateStatusText
  if type(update) ~= "function" or not frame then return end
  -- Unit frames carry the status via the child element apply; group frames
  -- have no StatusTextIndicator child (noGroup), so fall back to the spec.
  local status = frame._msufStatusIndicatorStatus
  if not status then
    local spec = frame.MSUFSpec
    status = spec and spec.status or nil
  end
  if status then
    update(frame, status, "MSUF_AFK_TIMER_TICK")
  end
end

local function OnTick()
  if combatActive or attachedCount <= 0 then
    StopTicker()
    return
  end
  for frame in pairs(attached) do
    PokeFrame(frame)
  end
end

local function EnsureTicker()
  if ticker or combatActive or attachedCount <= 0 then return end
  if not (C_Timer and type(C_Timer.NewTicker) == "function") then return end
  ticker = C_Timer.NewTicker(TICK_SECONDS, OnTick)
end

local AFKTimer = {}

function AFKTimer.Attach(frame)
  if not frame or attached[frame] then return end
  attached[frame] = true
  attachedCount = attachedCount + 1
  EnsureTicker()
end

function AFKTimer.Detach(frame)
  if not frame or not attached[frame] then return end
  attached[frame] = nil
  attachedCount = attachedCount - 1
  if attachedCount <= 0 then
    attachedCount = 0
    StopTicker()
  end
end

--- Duration text for the frame's unit, or nil when it must not show:
--- in combat, unresolvable identity, or no observed AFK-on edge.
function AFKTimer.ResolveText(unit)
  if combatActive then return nil end
  local guid = PlainGUID(unit)
  local stamp = guid and afkSince[guid]
  if not stamp then return nil end
  return FormatDuration(Now() - stamp)
end

function AFKTimer.SampleText()
  return SAMPLE_TEXT
end

MSUF.UFAFKTimer = AFKTimer

local function StampUnit(unit)
  local guid = PlainGUID(unit)
  if not guid then return end
  local afk = PlainAFK(unit)
  if afk == true then
    if afkSince[guid] == nil then
      afkSince[guid] = Now()
    end
  elseif afk == false then
    afkSince[guid] = nil
  end
end

--- Post-combat resync: AFK edges during combat were deliberately not observed.
--- Drop stamps for every observable unit that is no longer AFK; a unit still
--- AFK keeps its pre-combat stamp (a mid-combat off/on double toggle is not
--- detectable and accepted as stale-but-rare).
local function PruneLedger()
  if next(afkSince) == nil then return end
  if type(UnitExists) ~= "function" then return end
  local function Check(unit)
    if UnitExists(unit) ~= true then return end
    local guid = PlainGUID(unit)
    if guid and afkSince[guid] and PlainAFK(unit) == false then
      afkSince[guid] = nil
    end
  end
  Check("player")
  Check("target")
  Check("focus")
  if type(IsInRaid) == "function" and IsInRaid() == true then
    for i = 1, 40 do Check("raid" .. i) end
  else
    for i = 1, 4 do Check("party" .. i) end
  end
end

local function HideTimerRegion(frame)
  local fs = frame and frame.statusAFKTimerText
  if fs and fs._msufStatusShown ~= false then
    if fs.Hide then fs:Hide() end
    fs._msufStatusShown = false
  end
end

local listener = nil

local function OnCombatStart()
  combatActive = true
  StopTicker()
  if listener and listener.UnregisterEvent then
    listener:UnregisterEvent("PLAYER_FLAGS_CHANGED")
  end
  for frame in pairs(attached) do
    suspended[frame] = true
    HideTimerRegion(frame)
    attached[frame] = nil
  end
  attachedCount = 0
end

local function OnCombatEnd()
  combatActive = false
  if listener and listener.RegisterEvent then
    listener:RegisterEvent("PLAYER_FLAGS_CHANGED")
  end
  PruneLedger()
  for frame in pairs(suspended) do
    suspended[frame] = nil
    PokeFrame(frame)
  end
end

local function OnListenerEvent(_, event, unit)
  if event == "PLAYER_REGEN_DISABLED" then
    OnCombatStart()
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    OnCombatEnd()
    return
  end
  -- PLAYER_FLAGS_CHANGED: a unit event despite the prefix; fires for every
  -- observable unit whose AFK/DND flags toggle. Rare by nature, so this
  -- handler is the entire out-of-combat cost of the ledger.
  if combatActive then return end
  if type(unit) ~= "string" or issecretvalue(unit) == true then return end
  StampUnit(unit)
end

if type(CreateFrame) == "function" then
  listener = CreateFrame("Frame")
  listener:RegisterEvent("PLAYER_REGEN_DISABLED")
  listener:RegisterEvent("PLAYER_REGEN_ENABLED")
  combatActive = type(InCombatLockdown) == "function" and InCombatLockdown() == true
  if not combatActive then
    listener:RegisterEvent("PLAYER_FLAGS_CHANGED")
  end
  listener:SetScript("OnEvent", OnListenerEvent)
end
