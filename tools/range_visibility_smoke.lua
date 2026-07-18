_G = _G or _ENV

local sourcePath = "MidnightSimpleUnitFrames/UnitFrames/Range/MSUF_UF_RangeFade.lua"
local handle = io.open(sourcePath, "r")
if not handle then
  sourcePath = "UnitFrames/Range/MSUF_UF_RangeFade.lua"
else
  handle:close()
end

local knownSpell = 2139
local spellChecks = {}
local driver
local visible = false

local MSUF = {
  UF = {
    frames = {},
    RegisterElement = function() end,
    UnitExistsSafe = function() return true end,
    ApplyRangeModifier = function() return true end,
  },
}

_G.MSUF_NS = MSUF
_G.C_Timer = { After = function() end }
_G.GetTime = function() return 1 end
_G.GetUnitSpeed = function() return 0 end
_G.InCombatLockdown = function() return false end
_G.issecretvalue = function() return false end
_G.UnitCanAssist = function() return false end
_G.UnitCanAttack = function() return true end
_G.UnitClass = function() return "Mage", "MAGE" end
_G.UnitExists = function() return true end
_G.UnitIsDeadOrGhost = function() return false end
_G.IsPlayerSpell = function(spellID) return spellID == knownSpell end
_G.C_Spell = {
  EnableSpellRangeCheck = function() end,
  GetOverrideSpell = function(spellID) return spellID end,
  IsSpellInRange = function(spellID)
    spellChecks[#spellChecks + 1] = spellID
    return true
  end,
}

_G.CreateFrame = function()
  local frame = { events = {} }
  function frame:SetScript(kind, callback) self[kind] = callback end
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:RegisterUnitEvent(event) self.events[event] = true end
  function frame:UnregisterAllEvents() self.events = {} end
  driver = frame
  return frame
end

local frame = { unit = "target", MSUFUnitKey = "target", hooks = {} }
function frame:HookScript(kind, callback)
  local callbacks = self.hooks[kind] or {}
  callbacks[#callbacks + 1] = callback
  self.hooks[kind] = callbacks
end
function frame:IsShown()
  -- The child itself remains shown while a hidden parent controls effective
  -- visibility. Range scheduling must use IsVisible, not this flag.
  return true
end
function frame:IsVisible() return visible end
function frame:SetAlpha() end

MSUF.UF.frames.target = frame

local chunk, err = loadfile(sourcePath)
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", MSUF)

local Range = assert(MSUF.UF.Range, "range runtime missing")
Range.RegisterFrame(frame, { range = { active = true, alpha = 0.4 } })
assert(driver == nil,
  "an effectively hidden frame must not activate the shared range driver")

local function RunVisibilityHook(kind)
  local callbacks = assert(frame.hooks[kind], kind .. " hook missing")
  for i = 1, #callbacks do callbacks[i](frame) end
end

knownSpell = 44614
spellChecks = {}
visible = true
RunVisibilityHook("OnShow")
assert(driver and driver.events.SPELLS_CHANGED,
  "showing the first range consumer must register the shared driver")
assert(spellChecks[1] == 44614,
  "first visible evaluation used a spell cached while the driver was inactive")

visible = false
RunVisibilityHook("OnHide")
assert(next(driver.events) == nil,
  "hiding the last range consumer must unregister the shared driver")

knownSpell = 2139
spellChecks = {}
visible = true
RunVisibilityHook("OnShow")
assert(spellChecks[1] == 2139,
  "showing after an inactive talent window did not rebuild the spell cache")

print("range visibility smoke: ok")
