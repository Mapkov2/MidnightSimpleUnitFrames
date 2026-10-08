-- Probe E: the group target highlight is hidden when the targeted member goes
-- offline (UNIT_CONNECTION), but the next GroupVisuals apply (any visual setting
-- change or a frame re-apply) shows it again from the cached target GUID.
-- Loads the real MSUF_UF_Group_Visuals.lua with minimal stubs.
local ROOT = assert(arg[1]) .. "/MidnightSimpleUnitFrames/"

local connected = { party1 = true, target = true }
local guids = { party1 = "Player-1", target = "Player-1" }
local driver
local methods = {}
local function Region()
  return setmetatable({ shown = true, events = {}, scripts = {} }, { __index = methods })
end
function methods:CreateTexture() return Region() end
function methods:SetShown(v) self.shown = v and true or false end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetAlpha() end
function methods:ClearAllPoints() end
function methods:SetPoint() end
function methods:SetHeight() end
function methods:SetWidth() end
function methods:SetColorTexture() end
function methods:SetAllPoints() end
function methods:HookScript() end
function methods:SetScript(n, fn) self.scripts[n] = fn end
function methods:RegisterEvent(e) self.events[e] = true end
function methods:UnregisterEvent(e) self.events[e] = nil end
function methods:GetFrameLevel() return 1 end

_G.CreateFrame = function() local f = Region(); driver = f; return f end
_G.UnitGUID = function(u) return guids[u] end
_G.UnitIsConnected = function(u) return connected[u] end
_G.UnitIsUnit = function(a, b) return guids[a] ~= nil and guids[a] == guids[b] end
_G.issecretvalue = function() return false end
_G.GetTime = function() return 0 end

local elements = {}
local connectionReads = 0
local UF = {
  RegisterElement = function(name, el) elements[name] = el end,
  IsUnitToken = function(u) return type(u) == "string" and u ~= "" end,
  ReadConnectedCached = function(owner, unit) if owner then connectionReads = connectionReads + 1 end; return connected[unit] == true, true end,
  ReadDeadCached = function() return false, true end,
  Clamp01 = function(v, f) v = tonumber(v) or f if v < 0 then return 0 elseif v > 1 then return 1 end return v end,
}
local GF = { frames = {} }
GF.ForEachFrameForUnit = function(unit, fn, ...)
  local any
  for frame in pairs(GF.frames) do if frame.MSUFUnitKey == unit then fn(frame, unit, ...) any = true end end
  return any
end
local ns = { UF = UF, GF = GF, Secrets = { PlainBool = function(v) return v end } }
assert(loadfile(ROOT .. "UnitFrames/Engine/Group/MSUF_UF_Group_Visuals.lua"))("MidnightSimpleUnitFrames", ns)
local GV = elements.GroupVisuals

local frame = Region()
frame.MSUFUnitKey = "party1"
frame.hpBar = Region()
frame.MSUFSpec = { scope = "group", group = { targetIndicator = true, targetR = 1, targetG = 1, targetB = 1 } }
GF.frames[frame] = true

local function Edge() return frame.MSUFGFTargetEdges and frame.MSUFGFTargetEdges.top.shown end

GV.Apply(frame)                                   -- party1 is the player's target and online
print("online target       : edge shown =", tostring(Edge()))
connected.party1, connected.target = false, false
driver.scripts.OnEvent(driver, "UNIT_CONNECTION", "party1", false)
print("after disconnect    : edge shown =", tostring(Edge()), "(hidden by design: UNIT_CONNECTION path)")
GV.Apply(frame)                                   -- e.g. any "visual" group setting change
print("after visuals apply : edge shown =", tostring(Edge()), "(expected false: member still offline)")

assert(Edge() == false, "offline target edge reappeared")
connected.party1, connected.target = true, true
driver.scripts.OnEvent(driver, "UNIT_CONNECTION", "party1", true)
GV.Apply(frame)
assert(Edge() == true, "reconnected target edge missing")

-- A disabled/nonmatching edge requires no connection query during repaint.
frame.MSUFSpec.group.targetIndicator = false
connectionReads = 0
for _ = 1, 100 do GV.Apply(frame) end
assert(connectionReads == 0, "disabled indicators queried connection")
frame.MSUFSpec.group.targetIndicator = true
guids.target = "OtherPlayer"
driver.scripts.OnEvent(driver, "PLAYER_TARGET_CHANGED")
connectionReads = 0
for _ = 1, 100 do GV.Apply(frame) end
assert(connectionReads == 0, "nonmatching indicators queried connection")
