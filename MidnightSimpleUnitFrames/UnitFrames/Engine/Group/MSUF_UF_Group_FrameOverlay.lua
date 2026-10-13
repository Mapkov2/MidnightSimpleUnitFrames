--- Binding-owned overlays inherit compiler-owned scope data without copying it.
local _, MSUF = ...
local GF = MSUF.GF
local Num = MSUF.UF.NumberWithFallback
local ROLES = { TANK = true, HEALER = true, DAMAGER = true, NONE = true }
local issecretvalue = issecretvalue
local scopes = setmetatable({}, { __mode = "k" })

-- A scope snapshot contains only inherited fields. Binding-owned dimensions,
-- role/strip tables and identity stay in the overlay, keeping this cold snapshot
-- small. Its one revision replaces the four redundant per-binding stamps.
local OWNED_FIELDS = {
  width = true, height = true, unit = true, key = true, groupKind = true,
  power = true, status = true, group = true, health = true, text = true,
  showPowerText = true, scope = true, _msufGFConf = true,
  _msufA3NativeGroupConfigCache = true,
}

function GF.RefreshFrameOverlayScope(base)
  local scope = scopes[base]
  if not scope then return end
  for key in pairs(scope.values) do scope.values[key] = base[key] end
  for key, value in pairs(base) do
    if not OWNED_FIELDS[key] then scope.values[key] = value end
  end
  scope.revision = scope.revision + 1
end

local function OverlayScope(base)
  local scope = scopes[base]
  if not scope then
    scope = { values = {}, revision = 0 }
    scopes[base] = scope
    GF.RefreshFrameOverlayScope(base)
  end
  return scope
end

local function OverlayTable(metrics, key, base)
  local overlay = metrics[key]
  if not overlay then
    overlay = setmetatable({}, { __index = base })
    metrics[key] = overlay
  else
    local inheritance = getmetatable(overlay)
    if inheritance.__index ~= base then
      for field in pairs(overlay) do overlay[field] = nil end
      inheritance.__index = base
    end
  end
  return overlay
end

local function PatchNameBarHeight(base, spec, metrics, conf, powerHeight)
  local group = base.group
  if not (group and group.nameBarEnabled) then
    spec.group, spec.health, spec.text = group, base.health, base.text
    return
  end
  local power = spec.power
  local powerInset = power and power.enabled and power.embed ~= false and power.detached ~= true and powerHeight or 0
  local height = math.max(0, math.min(group.nameBarHeight, spec.height - powerInset - 1))
  local ownGroup = OverlayTable(metrics, "group", group)
  local health = OverlayTable(metrics, "health", base.health)
  local text = OverlayTable(metrics, "text", base.text)
  ownGroup.nameBarHeight, health.topInset = height, height
  local fontSize = Num(conf.nameFontSize, 12)
  local baseline = base.text.nameY + math.max(0, group.nameBarHeight - fontSize) / 2
  text.nameY = baseline - math.max(0, height - fontSize) / 2
  spec.group, spec.health, spec.text = ownGroup, health, text
end

-- metrics is a persistent binding record: base/conf, optional width/height and
-- reusable overlay tables. unitOrRole accepts a live token or a synthetic role.
-- Only these tables receive per-frame writes; shared scope data stays untouched.
function GF.ComputeFrameOverlay(kind, unitOrRole, metrics)
  local base, conf = metrics.base, metrics.conf
  if issecretvalue(unitOrRole) == true then unitOrRole = nil end
  local role, unit
  if ROLES[unitOrRole] then role = unitOrRole
  else unit, role = unitOrRole, GF.GetUnitGroupRole(unitOrRole) end
  local powerHeight = 0
  if conf.powerBarEnabled ~= false then
    powerHeight = GF.GetEffectivePowerHeight and GF.GetEffectivePowerHeight(kind, unit, role, conf) or Num(conf.powerHeight, 4)
  end
  local scope = OverlayScope(base)
  local spec = metrics.spec
  local width, height = metrics.width or base.width, metrics.height or base.height
  if metrics.scope == scope and metrics.revision == scope.revision and spec.unit == unit
    and spec.width == width and spec.height == height
    and spec.status.roleValue == role and spec.power.height == powerHeight then return spec end
  spec = OverlayTable(metrics, "spec", scope.values)
  if metrics.scope ~= scope then
    -- Retain the existing one-time cache-pointer handoff on a new base. The
    -- cache's ownership and lifetime are unchanged until its separate move.
    spec._msufA3NativeGroupConfigCache = base._msufA3NativeGroupConfigCache
  end
  metrics.scope, metrics.revision = scope, scope.revision
  spec.width, spec.height = width, height
  spec.scope, spec._msufGFConf = base.scope, base._msufGFConf
  spec.unit, spec.key, spec.groupKind = unit, "gf_" .. kind, kind
  local power = OverlayTable(metrics, "power", base.power)
  power.enabled, power.height = powerHeight > 0, powerHeight
  spec.power = power
  spec.showPowerText = powerHeight > 0 and base.showPowerText == true
  local status = OverlayTable(metrics, "status", base.status)
  status.roleValue = role
  spec.status = status
  PatchNameBarHeight(base, spec, metrics, conf, powerHeight)
  return spec
end
