--- UnitFrames/Engine/MSUF_UF_PreviewDiagnostics.lua
--- On-demand live-vs-preview layer snapshots. No events, timers, or combat work.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local UF = MSUF.UF or {}
local Diag = UF.PreviewDiagnostics or {}
UF.PreviewDiagnostics = Diag

local InCombatLockdown = InCombatLockdown
local type = type
local tostring = tostring

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local function Level(frame)
  return frame and frame.GetFrameLevel and frame:GetFrameLevel() or nil
end

local function Shown(region)
  if not region then return nil end
  if region.IsShown then return region:IsShown() and true or false end
  return nil
end

local function UnitFrameForKey(key)
  local unit = key == "boss" and "boss1" or key
  local frames = _G.MSUF_UnitFrames
  return unit and ((frames and frames[unit]) or _G["MSUF_" .. unit]) or nil
end

local function Add(out, name, live, preview)
  out[#out + 1] = {
    name = name,
    liveLevel = Level(live),
    previewLevel = Level(preview),
    liveShown = Shown(live),
    previewShown = Shown(preview),
  }
end

function Diag.UnitSnapshot(key, box)
  if InCombat() then return nil, "combat" end
  key = key or (box and box.key) or "player"
  local frame = UnitFrameForKey(key)
  local mock = box and box.mock
  local out = { kind = "unit", key = key, entries = {} }
  Add(out.entries, "frame", frame, mock)
  Add(out.entries, "health", frame and (frame.Health or frame.hpBar), mock and mock.hp)
  Add(out.entries, "power", frame and (frame.Power or frame.powerBar or frame.targetPowerBar), mock and mock.power)
  Add(out.entries, "portrait", frame and frame.MSUFPortraitHolder, mock and mock.portrait)
  Add(out.entries, "nameText", frame and frame.MSUFNameTextLayer, mock and mock.nameLayer)
  Add(out.entries, "healthText", frame and frame.MSUFHealthTextLayer, mock and mock.hpLayer)
  Add(out.entries, "powerText", frame and frame.MSUFPowerTextLayer, mock and mock.powerLayer)
  return out
end

function Diag.GroupSnapshot(kind, box)
  if InCombat() then return nil, "combat" end
  kind = kind or (box and box._mock and box._mock._msufGFKind) or "party"
  local gf = MSUF.GF
  local live
  if gf and type(gf.ForEachFrame) == "function" then
    gf.ForEachFrame(function(frame, _, frameKind)
      if frameKind == kind then
        live = frame
        return true
      end
    end, true)
  end
  local mock = box and box._mock
  local out = { kind = "group", key = kind, entries = {} }
  Add(out.entries, "frame", live, mock)
  Add(out.entries, "health", live and (live.Health or live.hpBar or live.health), mock and mock._health)
  Add(out.entries, "power", live and (live.Power or live.powerBar or live.targetPowerBar), mock and mock._power)
  Add(out.entries, "nameText", live and live.MSUFNameTextLayer, mock and mock._nameTextLayer)
  Add(out.entries, "healthText", live and live.MSUFHealthTextLayer, mock and mock._healthTextLayer)
  Add(out.entries, "powerText", live and live.MSUFPowerTextLayer, mock and mock._powerTextLayer)
  return out
end

local function PrintSnapshot(snapshot)
  if not snapshot then return false end
  print("MSUF preview layer snapshot: " .. tostring(snapshot.kind) .. " " .. tostring(snapshot.key))
  for i = 1, #snapshot.entries do
    local e = snapshot.entries[i]
    print(string.format("  %s live=%s preview=%s liveShown=%s previewShown=%s",
      tostring(e.name), tostring(e.liveLevel), tostring(e.previewLevel), tostring(e.liveShown), tostring(e.previewShown)))
  end
  return true
end

function Diag.PrintUnitSnapshot(key, box)
  local snapshot, reason = Diag.UnitSnapshot(key, box)
  if not snapshot then return false, reason end
  return PrintSnapshot(snapshot), snapshot
end

function Diag.PrintGroupSnapshot(kind, box)
  local snapshot, reason = Diag.GroupSnapshot(kind, box)
  if not snapshot then return false, reason end
  return PrintSnapshot(snapshot), snapshot
end

ExportPublic("MSUF_UFPreviewDiagnostics", Diag)
ExportPublic("MSUF_UFPreview_DumpUnitLayers", function(key, box) return Diag.PrintUnitSnapshot(key, box) end)
ExportPublic("MSUF_UFPreview_DumpGroupLayers", function(kind, box) return Diag.PrintGroupSnapshot(kind, box) end)
