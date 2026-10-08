-- Probe: group portrait click target vs. combat lockdown.
-- Loads the real Portrait element file and fetches its local
-- ApplyPortraitClickTarget through Portrait.Disable's upvalues.
local ROOT = assert(arg[1]) .. "/MidnightSimpleUnitFrames/"
local lockdown = false
_G.InCombatLockdown = function() return lockdown end

local created = {}
local function NewObject(kind)
  local o = { _kind = kind, _attrs = {}, _shown = false, _scripts = {} }
  local mt = {}
  mt.__index = function(t, k)
    if k == "SetAttribute" then return function(self, a, v) self._attrs[a] = v end end
    if k == "Show" then return function(self) self._shown = true end end
    if k == "Hide" then return function(self) self._shown = false end end
    if k == "GetFrameLevel" then return function() return 5 end end
    if k == "CreateTexture" then return function() return NewObject("Texture") end end
    if k == "SetScript" or k == "HookScript" then return function(self, n, f) self._scripts[n] = f end end
    if k == "IsShown" then return function(self) return self._shown end end
    if type(k) ~= "string" or k:find("^MSUF") or k:find("^_") or not k:find("^%u") then return nil end
    return function() return nil end
  end
  return setmetatable(o, mt)
end
_G.CreateFrame = function(kind, name, parent, template)
  local o = NewObject(kind)
  o._template = template
  created[#created + 1] = o
  return o
end
_G.UIParent = NewObject("Frame")

local registered = {}
local UF = {
  RegisterElement = function(name, el) registered[name] = el end,
  Layers = {},
}
local MSUF = { UF = UF, UFVisuals = { UF = UF }, Client = { IsClassic = true, IsVanilla = false } }
setmetatable(MSUF, { __index = function(t, k)
  -- Any other namespace the file reads at load time: an empty table.
  local v = {}
  rawset(t, k, v)
  return v
end })
_G.MSUF_NS = MSUF

local chunk = assert(loadfile(ROOT .. "UnitFrames/Engine/Elements/MSUF_UF_Elements_Portrait.lua"))
local ok, err = pcall(chunk, "MidnightSimpleUnitFrames", MSUF)
if not ok then print("load error: " .. tostring(err)) return end
local Portrait = assert(registered.Portrait, "Portrait not registered")

local ApplyPortraitClickTarget
for i = 1, 60 do
  local n, v = debug.getupvalue(Portrait.Disable, i)
  if not n then break end
  if n == "ApplyPortraitClickTarget" then ApplyPortraitClickTarget = v end
end
assert(ApplyPortraitClickTarget, "upvalue not found")

local p = { enabled = true, clickable = true }

-- 1) A raid member joins mid-combat: SecureGroupHeader births the child and
--    writes its unit in lockdown; the adapter's structure apply runs Portrait.Apply.
lockdown = true
local child = NewObject("Button")
child.MSUFPortraitHolder = NewObject("Frame")
child._msufPortraitRuntimeCfg = p
ApplyPortraitClickTarget(child, p)
print("in combat : click target created =", child.MSUFPortraitClickTarget ~= nil)

-- 2) Combat ends. The regen rescan reaches ApplyUnitFrame without forceApply;
--    SameApplied(...) is true for this child, so Portrait.Apply is not called
--    again (static: MSUF_UF_Group_Adapter.lua:688-696). Nothing else calls it.
lockdown = false
for _, f in ipairs(created) do if f._scripts.OnEvent then f._scripts.OnEvent(f, "PLAYER_REGEN_ENABLED") end end
assert(child.MSUFPortraitClickTarget and child.MSUFPortraitClickTarget._shown, "combat-born portrait click target missing")
print("after regen: click target exists  =", child.MSUFPortraitClickTarget ~= nil, "(no re-apply path)")

-- 3) Control: the same child applied out of combat.
local control = NewObject("Button")
control.MSUFPortraitHolder = NewObject("Frame")
ApplyPortraitClickTarget(control, p)
local b = control.MSUFPortraitClickTarget
print("out of combat: click target created =", b ~= nil, "template =", b and b._template, "shown =", b and b._shown)
assert(b and b._shown, "out-of-combat control missing")
lockdown=true
ApplyPortraitClickTarget(child,p)
child._msufPortraitRuntimeCfg={enabled=false,clickable=false}
lockdown=false
for _,f in ipairs(created) do if f._scripts.OnEvent then f._scripts.OnEvent(f,"PLAYER_REGEN_ENABLED") end end
assert(not child.MSUFPortraitClickTarget._shown,"queued replay ignored latest disabled state")
print("PASS portrait combat birth, latest-state cancellation and out-of-combat control")
