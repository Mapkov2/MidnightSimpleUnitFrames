local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}

local UF = MSUF.UF
if not UF then return end

-- Player stance name resolver behind the player frame's Stance status text.
--
-- Data source is the native stance bar (GetShapeshiftForm /
-- GetShapeshiftFormInfo): warrior stances, paladin auras, druid forms, rogue
-- stealth - whatever the class puts there. This is the player's own action-bar
-- state, so the reads are unrestricted in combat and never involve identity.
--
-- Zero standing cost by design: no listener frame, no ticker, no polling. The
-- StanceIndicator element registers UPDATE_SHAPESHIFT_FORM/_FORMS on the
-- player frame only, so this module runs exactly once per stance change. The
-- spellID -> localized name cache is immutable for the session (a spell's name
-- never changes), so stance-bar rebuilds need no invalidation here.
local GetShapeshiftForm = GetShapeshiftForm
local GetShapeshiftFormInfo = GetShapeshiftFormInfo
local type = type

local issecretvalue = _G.issecretvalue or function(_) return false end

local nameBySpellID = {}

local function PlainNumber(value)
  if issecretvalue(value) == true then return nil end
  if type(value) ~= "number" then return nil end
  return value
end

local Stance = {}

--- Localized name of the active stance-bar form, or nil while no form is
--- active (form index 0) or the class has no stance bar at all.
function Stance.Resolve()
  if type(GetShapeshiftForm) ~= "function" or type(GetShapeshiftFormInfo) ~= "function" then
    return nil
  end
  local index = PlainNumber(GetShapeshiftForm())
  if not index or index <= 0 then
    return nil
  end
  local _, _, _, spellID = GetShapeshiftFormInfo(index)
  spellID = PlainNumber(spellID)
  if not spellID then
    return nil
  end
  local name = nameBySpellID[spellID]
  if name == nil then
    local spell = _G.C_Spell
    local getName = spell and spell.GetSpellName
    if type(getName) ~= "function" then return nil end
    name = getName(spellID)
    if issecretvalue(name) == true or type(name) ~= "string" or name == "" then
      -- Spell data may still be streaming in; resolve again on the next event
      -- instead of caching a miss.
      return nil
    end
    nameBySpellID[spellID] = name
  end
  return name
end

--- Test-mode sample: the real stance when one is active, so the preview
--- matches the live frame; a plain placeholder for classes without a
--- stance bar.
function Stance.SampleText()
  return Stance.Resolve() or "Stance"
end

MSUF.UFStance = Stance
