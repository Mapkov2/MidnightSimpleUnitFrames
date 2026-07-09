local _, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = MSUF

local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end

local GF = MSUF.GF or {}
MSUF.GF = GF
local UF = MSUF.UF
local Metadata = GF.Metadata or {}

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local floor = math.floor
local tonumber = tonumber
local type = type
local issecretvalue = _G.issecretvalue or function(_) return false end

local eventFrame

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

local IsUnitToken = UF and UF.IsUnitToken or function(unit)
  return issecretvalue(unit) ~= true and type(unit) == "string" and unit ~= ""
end

local function Conf(kind)
  return GF.GetConf and GF.GetConf(kind) or nil
end

local function ConfEnabled(kind)
  local conf = Conf(kind)
  return conf and conf.enabled == true
end

local function AnyGroupFrameEnabled()
  if type(GF.AnyMSUFGroupFrameEnabled) == "function" then
    return GF.AnyMSUFGroupFrameEnabled() == true
  end
  return ConfEnabled("party") or ConfEnabled("raid") or ConfEnabled("mythicraid")
end
GF.AnyGroupRuntimeEnabled = AnyGroupFrameEnabled

local function LiveRaidKind()
  local kind = GF.GetLiveRaidKind and GF.GetLiveRaidKind() or nil
  if kind == "mythicraid" then return "mythicraid" end
  return "raid"
end

local function WantParty()
  local conf = Conf("party")
  if not (conf and conf.enabled == true) then return false end
  if IsInRaid and IsInRaid() then return false end
  if IsInGroup and IsInGroup() then return true end
  return conf.showSolo == true
end

local function WantRaid()
  if not (IsInRaid and IsInRaid()) then return false end
  return ConfEnabled(LiveRaidKind())
end

local function PreviewSuppressesHeader(key)
  if _G.MSUF_UnitEditModeActive == true then return false end
  local active = GF._previewActive
  if not active then return false end
  if key == "party" then return active.party == true end
  if key == "raid" then return active.raid == true or active.mythicraid == true end
  return false
end

local function RetireHeader(key)
  if GF.RetireHeader then return GF.RetireHeader(key) end
  local header = GF.headers and GF.headers[key]
  if header and header.Hide then header:Hide() end
  if GF.headers then GF.headers[key] = nil end
  return true
end

local function HeaderScope(kind)
  if kind == "party" then return "party" end
  if kind == "raid" or kind == "mythicraid" then return "raid" end
  return nil
end

local function SetupWantedHeaders(kind)
  local scope = HeaderScope(kind)
  if not AnyGroupFrameEnabled() then
    if not scope or scope == "party" then RetireHeader("party") end
    if not scope or scope == "raid" then RetireHeader("raid") end
    return true
  end

  local wantParty = WantParty() and not PreviewSuppressesHeader("party")
  local wantRaid = WantRaid() and not PreviewSuppressesHeader("raid")
  local raidKind = LiveRaidKind()

  if scope ~= "raid" and wantParty then
    local header = GF.SetupHeader and GF.SetupHeader("party", "party")
    if header and header.Show then header:Show() end
    if GF.ScheduleScan then GF.ScheduleScan("party", "party") end
  elseif scope ~= "raid" then
    RetireHeader("party")
  end

  if scope ~= "party" and wantRaid then
    local header = GF.SetupHeader and GF.SetupHeader("raid", raidKind)
    if header and header.Show then header:Show() end
    if GF.ScheduleScan then GF.ScheduleScan("raid", raidKind) end
  elseif scope ~= "party" then
    RetireHeader("raid")
  end

  if GF.ApplyBlizzardGroupFrameOwnership then
    GF.ApplyBlizzardGroupFrameOwnership("lean-runtime")
  end
  return true
end

local function ApplyFrameDirty(frame, kind, mask, reason)
  if not (frame and kind) then return false end
  if not IsUnitToken(frame.unit) then return false end
  if not (UF and UF.ApplySpec and GF.CompileSpec) then
    return GF.ApplyButton and GF.ApplyButton(frame, kind, reason)
  end
  local spec = GF.CompileSpec(kind, frame, frame.unit)
  if not spec then return false end
  local applyMask = GF.ApplyMaskForDirtyMask and GF.ApplyMaskForDirtyMask(mask) or Metadata.MASK_RUNTIME
  if GF.ApplyStructureSpec then
    return GF.ApplyStructureSpec(frame, spec, reason or "MSUF_GF_DIRTY", applyMask) == true
  end
  return UF.ApplySpec(frame, spec, reason or "MSUF_GF_DIRTY", applyMask) == true
end

local function MaskHas(mask, flag)
  mask = tonumber(mask) or 0
  flag = tonumber(flag) or 0
  if flag <= 0 then return false end
  return mask % (flag * 2) >= flag
end

local function AddDirty(mask, flag)
  if not flag then return mask end
  mask = tonumber(mask) or 0
  if MaskHas(mask, flag) then return mask end
  return mask + flag
end

local function MergeDirtyMask(current, incoming)
  if not current then return incoming end
  if not incoming then return current end
  if current == true or incoming == true then return true end
  if current == GF.DIRTY_ALL or incoming == GF.DIRTY_ALL then return GF.DIRTY_ALL end
  if current == GF.DIRTY_CONFIG or incoming == GF.DIRTY_CONFIG then return GF.DIRTY_CONFIG end
  if type(current) ~= "number" or type(incoming) ~= "number" then return incoming end
  local out = current
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_VISUAL) and GF.DIRTY_VISUAL or nil)
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_FONT) and GF.DIRTY_FONT or nil)
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_COLOR) and GF.DIRTY_COLOR or nil)
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_BORDER) and GF.DIRTY_BORDER or nil)
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_GEOMETRY) and GF.DIRTY_GEOMETRY or nil)
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_LAYOUT) and GF.DIRTY_LAYOUT or nil)
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_AURAS) and GF.DIRTY_AURAS or nil)
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_UNIT_BINDING) and GF.DIRTY_UNIT_BINDING or nil)
  out = AddDirty(out, MaskHas(incoming, GF.DIRTY_CONFIG) and GF.DIRTY_CONFIG or nil)
  return out
end

local function AddElementNames(out, source)
  if type(source) ~= "table" then return false end
  local did = false
  for name in pairs(source) do
    out[name] = true
    did = true
  end
  return did
end

function GF.ApplyMaskForDirtyMask(mask)
  if mask == nil then return Metadata.MASK_RUNTIME end
  local exact = Metadata.dirtyApplyMasks and Metadata.dirtyApplyMasks[mask]
  if exact then return exact end
  if mask == GF.DIRTY_ALL or mask == GF.DIRTY_CONFIG then return true end
  if type(mask) ~= "number" then return Metadata.MASK_RUNTIME end
  if MaskHas(mask, GF.DIRTY_CONFIG) then return true end
  local out = {}
  local did = false
  if MaskHas(mask, GF.DIRTY_VISUAL) then did = AddElementNames(out, Metadata.MASK_VISUAL) or did end
  if MaskHas(mask, GF.DIRTY_FONT) then did = AddElementNames(out, Metadata.MASK_FONT) or did end
  if MaskHas(mask, GF.DIRTY_COLOR) then did = AddElementNames(out, Metadata.MASK_COLOR) or did end
  if MaskHas(mask, GF.DIRTY_BORDER) then did = AddElementNames(out, Metadata.MASK_BORDER) or did end
  if MaskHas(mask, GF.DIRTY_AURAS) then did = AddElementNames(out, Metadata.MASK_AURAS) or did end
  if MaskHas(mask, GF.DIRTY_GEOMETRY) or MaskHas(mask, GF.DIRTY_LAYOUT) or MaskHas(mask, GF.DIRTY_UNIT_BINDING) then
    did = AddElementNames(out, Metadata.MASK_RUNTIME) or did
  end
  if not did then return Metadata.MASK_RUNTIME end
  return out
end

function GF.DeferGroupRuntime(reason, kind, mask)
  GF._pendingGroupRuntime = true
  reason = reason or GF._pendingGroupRuntimeReason or "refresh"
  local currentReason = GF._pendingGroupRuntimeReason
  if not currentReason or currentReason == "refresh" then
    GF._pendingGroupRuntimeReason = reason
  elseif reason ~= "refresh" then
    GF._pendingGroupRuntimeReason = reason
  end
  if kind ~= nil then
    local currentKind = GF._pendingGroupRuntimeKind
    if currentKind ~= nil and currentKind ~= kind then
      GF._pendingGroupRuntimeKind = nil
    else
      GF._pendingGroupRuntimeKind = kind
    end
  end
  GF._pendingGroupRuntimeMask = MergeDirtyMask(GF._pendingGroupRuntimeMask, mask)
  if eventFrame then eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") end
  return false
end

function GF.UpdateGroupVisibility()
  if InCombat() then return GF.DeferGroupRuntime("visibility") end
  return SetupWantedHeaders()
end

function GF.RefreshHeaderLayout(kind)
  if InCombat() then return GF.DeferGroupRuntime("layout", kind) end
  if GF.EnsureDB then GF.EnsureDB() end
  return SetupWantedHeaders(kind)
end

function GF.RefreshUnitBindings(kind)
  if InCombat() then return GF.DeferGroupRuntime("roster", kind, GF.DIRTY_UNIT_BINDING) end
  local did = false
  if GF.headers and GF.ScheduleScan then
    if (not kind or kind == "party") and GF.headers.party then
      did = GF.ScheduleScan("party", "party") or did
    end
    local raidKind = LiveRaidKind()
    if (not kind or kind == "raid" or kind == "mythicraid" or kind == raidKind) and GF.headers.raid then
      did = GF.ScheduleScan("raid", raidKind) or did
    end
  end
  return did
end

function GF.RebuildAll()
  if InCombat() then return GF.DeferGroupRuntime("rebuild") end
  if GF.InvalidateCompiledSpecs then GF.InvalidateCompiledSpecs() end
  return GF.RefreshHeaderLayout()
end

function GF.Rebuild(kind)
  if kind == nil then return GF.RebuildAll() end
  if InCombat() then return GF.DeferGroupRuntime("rebuild", kind) end
  if GF.InvalidateCompiledSpecs then GF.InvalidateCompiledSpecs(kind) end
  GF.RefreshHeaderLayout(kind)
  GF.RefreshUnitBindings(kind)
  return GF.RefreshVisuals(kind, GF.DIRTY_ALL)
end

function GF.RefreshVisuals(kind, mask)
  if InCombat() then return GF.DeferGroupRuntime("refresh", kind, mask) end
  if GF.InvalidateCompiledSpecs then
    GF.InvalidateCompiledSpecs(kind)
  end
  if not GF.ForEachFrame then return false end
  local did = false
  GF.ForEachFrame(function(frame, _, frameKind)
    if not kind or kind == frameKind then
      did = ApplyFrameDirty(frame, frameKind, mask, "MSUF_GF_REFRESH_VISUALS") or did
    end
  end, true)
  return did
end

function GF.RefreshAll()
  if InCombat() then return GF.DeferGroupRuntime("refreshAll") end
  GF.RefreshHeaderLayout()
  GF.RefreshUnitBindings()
  return GF.RefreshVisuals(nil, GF.DIRTY_ALL)
end

GF.Refresh = GF.RefreshAll
GF.RefreshGeometry = function(kind) return GF.RefreshHeaderLayout(kind) end
GF.RefreshOverlays = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_AURAS) end
GF.RefreshColors = function(kind)
  if GF.InvalidateCompiledSpecs then GF.InvalidateCompiledSpecs(kind) end
  return GF.RefreshVisuals(kind, GF.DIRTY_COLOR)
end
GF.RefreshBorder = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_BORDER) end
GF.RefreshOutlineGeometry = GF.RefreshBorder
GF.RefreshFonts = function(kind) return GF.RefreshVisuals(kind, GF.DIRTY_FONT) end

function GF.MarkDirty(frame, mask)
  if InCombat() then
    return GF.DeferGroupRuntime("refresh", frame and frame._msufGFKind or nil, mask)
  end
  if frame and frame._msufGFKind then
    return ApplyFrameDirty(frame, frame._msufGFKind, mask, "MSUF_GF_MARK_DIRTY")
  end
  return GF.RefreshVisuals(nil, mask)
end

function GF.MarkAllDirty(mask)
  if mask == GF.DIRTY_GEOMETRY or mask == GF.DIRTY_LAYOUT or mask == GF.DIRTY_CONFIG then
    return GF.RefreshHeaderLayout("dirty")
  end
  return GF.RefreshVisuals(nil, mask)
end

function GF.RefreshGroupNames(unit)
  if not (UF and GF.ForEachFrame) then return false end
  local did = false
  if unit and GF.FrameForUnit then
    local frame = GF.FrameForUnit(unit)
    if frame and UF.RunLeanIdentity then did = UF.RunLeanIdentity(frame, "MSUF_GF_NAME_UPDATE") or did end
    return did
  end
  GF.ForEachFrame(function(frame)
    if UF.RunLeanIdentity then did = UF.RunLeanIdentity(frame, "MSUF_GF_NAME_UPDATE") or did end
  end, true)
  return did
end

function GF.BuildFrameCache(frame)
  return frame and frame.MSUFSpec
end

function GF.EM2_SetActivePreviewKind(kind)
  GF._activePreviewKind = kind
  return true
end

function GF.EM2_NudgePreview(key, dx, dy)
  if InCombat() then return true end
  local kind = key
  if key == "gf_party" then kind = "party"
  elseif key == "gf_raid" then kind = "raid"
  elseif key == "gf_mythicraid" then kind = "mythicraid" end
  if kind ~= "party" and kind ~= "raid" and kind ~= "mythicraid" then return false end
  local conf = Conf(kind)
  if not conf then return false end
  conf.offsetX = floor(((tonumber(conf.offsetX) or 0) + (tonumber(dx) or 0)) + 0.5)
  conf.offsetY = floor(((tonumber(conf.offsetY) or 0) + (tonumber(dy) or 0)) + 0.5)
  return GF.RefreshGeometry(kind)
end

local function FlushDeferred()
  local reason = GF._pendingGroupRuntimeReason
  local kind = GF._pendingGroupRuntimeKind
  local mask = GF._pendingGroupRuntimeMask
  GF._pendingGroupRuntime = nil
  GF._pendingGroupRuntimeReason = nil
  GF._pendingGroupRuntimeKind = nil
  GF._pendingGroupRuntimeMask = nil
  if reason == "refresh" then return GF.RefreshVisuals(kind, mask) end
  if reason == "roster" then return GF.RefreshUnitBindings(kind) end
  if reason == "visibility" then return GF.UpdateGroupVisibility() end
  if reason == "layout" then
    local did = GF.RefreshHeaderLayout(kind)
    if mask and type(GF.RefreshVisuals) == "function" then
      did = GF.RefreshVisuals(kind, mask) or did
    end
    return did
  end
  if reason == "rebuild" then
    if kind and type(GF.Rebuild) == "function" then return GF.Rebuild(kind) end
    return GF.RefreshAll()
  end
  if reason == "refreshAll" then return GF.RefreshAll() end
  return GF.RefreshAll()
end

local function RuntimeOnEvent(self, event)
  if event == "PLAYER_REGEN_ENABLED" then
    ExportPublic("MSUF_InCombat", false)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if GF._pendingGroupRuntime then FlushDeferred() end
    return
  elseif event == "PLAYER_REGEN_DISABLED" then
    ExportPublic("MSUF_InCombat", true)
    return
  elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    GF.RefreshHeaderLayout(event)
    return
  elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "ROLE_CHANGED_INFORM" then
    if InCombat() then
      GF.DeferGroupRuntime("roster")
    else
      GF.RefreshHeaderLayout(event)
      GF.RefreshUnitBindings()
    end
    return
  elseif event == "PLAYER_DIFFICULTY_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
    GF.RefreshHeaderLayout(event)
  end
end

eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
eventFrame:RegisterEvent("ROLE_CHANGED_INFORM")
eventFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:SetScript("OnEvent", RuntimeOnEvent)

ExportPublic("MSUF_InCombat", InCombat())

local GF_PUBLIC_ALIASES = {
  { "MSUF_GF_RebuildAll", "RebuildAll" },
  { "MSUF_GF_RefreshAll", "RefreshAll" },
  { "MSUF_GF_Refresh", "RefreshAll" },
  { "MSUF_GF_RefreshVisuals", "RefreshVisuals" },
  { "MSUF_GF_RefreshHeaderLayout", "RefreshHeaderLayout" },
  { "MSUF_GF_RefreshUnitBindings", "RefreshUnitBindings" },
  { "MSUF_GF_RefreshGeometry", "RefreshGeometry" },
  { "MSUF_GF_UpdateGroupVisibility", "UpdateGroupVisibility" },
  { "MSUF_GF_RefreshOverlays", "RefreshOverlays" },
  { "MSUF_GF_RefreshBorder", "RefreshBorder" },
  { "MSUF_GF_RefreshOutlineGeometry", "RefreshOutlineGeometry" },
  { "MSUF_GF_RefreshColors", "RefreshColors" },
  { "MSUF_GF_RefreshFonts", "RefreshFonts" },
  { "MSUF_GF_EM2_SetActivePreviewKind", "EM2_SetActivePreviewKind" },
  { "MSUF_GF_EM2_NudgePreview", "EM2_NudgePreview" },
}

MSUF.GroupFrames = GF
for i = 1, #GF_PUBLIC_ALIASES do
  local alias, method = GF_PUBLIC_ALIASES[i][1], GF_PUBLIC_ALIASES[i][2]
  ExportPublic(alias, function(...)
    return GF[method](...)
  end)
end
ExportPublic("MSUF_GF_ForceAuraTextColorRefresh", function()
  return GF.RefreshVisuals(nil, GF.DIRTY_AURAS)
end)
