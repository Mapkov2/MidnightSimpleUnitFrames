-- Compile real custom configuration into Blizzard-facing filters before any
-- aura event. Reuse the full native driver for ownership and secure boundaries.
local root = arg[1] or "."
local h = assert(loadfile(root .. "/.github/scripts/auras3_native_contract_smoke.lua"))()
local A3 = h.A3
local function Entry()
    return {enabled=true, spellIDs="185313 22812", prioritySpellIDs={22812,185313},
        auraType="BUFF", filters={enabled=true, maxDuration=120, hidePermanent=true},
        placed={max=8, perRow=4, size=24, spacing=2, sortMethod="CUSTOM_PRIORITY"},
        frame={type="none"}}
end
local function Compile(entry, index, unit)
    unit = unit or "target"
    return A3._CompileUnitCustomContainers({shared={}, perUnit={},
        customContainers={perUnit={[unit]={items={[index or 1]=entry}}}}}, unit, nil)
end
local function Count(hash)
    local n=0; for _ in pairs(hash or {}) do n=n+1 end; return n
end
local entry = Entry()
local lanes = Compile(entry)
local lane = assert(lanes.custom1)
assert(lane.candidateFilters.includeSpellIDs[185422] and lane.candidateFilters.includeSpellIDs[20655],
    "custom action IDs were not resolved before native registration")
assert(Count(lane.sourceSpellIDs)==2 and #lane.customPrioritySpellIDs==2
    and lane.customPrioritySpellIDs[1]==22812 and lane.customPrioritySpellIDs[2]==185313,
    "aliases changed configured priority slots")
assert(lane.identityCandidateMode=="assist" and lane.candidateFilters.maxDuration==120,
    "alias expansion lost identity/duration restrictions")
local frame = h.NewFrame("Frame"); frame.unit="target"; frame.MSUFUnitKey="target"
frame.hpBar=h.NewHealthBar(frame); frame.barGroup=frame
local ownerRoot = h.NewFrame("Frame"); ownerRoot.unit="target"
h.unitCanAssistState.target=true
assert(A3._ApplyNormalLaneContainers(ownerRoot, lanes, frame, false))
local owner = assert(ownerRoot.CustomAuras1)
assert(#owner._msufA3PriorityGroupKeys==2, "native priority owner created an alias slot")
for i, expected in ipairs({20655,185422}) do
    local key = owner._msufA3PriorityGroupKeys[i]
    local options = assert(owner.groupOptions[key])
    assert(options.candidateFilters.includeSpellIDs[expected], "priority slot lost its own aliases")
    assert(options.candidateFilters.maxDuration==120, "priority slot lost duration filter")
end

entry.placed.reminderEnabled=true
_G.C_Spell.GetSpellTexture=function(id) return "ICON:"..id end
local reminderLanes, effects = Compile(entry)
assert(reminderLanes.custom1==nil and #effects.slots==2,
    "reminder aliases created extra placeholders or a duplicate flowing lane")
for i, expected in ipairs({22812,185313}) do
    local slot=effects.slots[i]
    assert(slot.castSpellID==expected and slot.icon=="ICON:"..expected,
        "reminder changed click binding or spell art to an aura alias")
    assert(slot.candidateFilters.includeSpellIDs[i==1 and 20655 or 185422],
        "reminder native slot lost action-to-aura aliases")
end

local disabled=Entry(); disabled.enabled=false; disabled.spellIDs="8679"
local old=A3.AuraSpellIDAliases[8679]
assert(not Compile(disabled).custom1 and A3.AuraSpellIDAliases[8679]==old,
    "disabled custom container resolved or registered aliases")
local dots=Entry(); dots.spellIDs="2823 123"; dots.customSpellIDs="2823"
local dotLane=assert(Compile(dots,4).custom4)
assert(dotLane.nativeFilter=="HARMFUL|PLAYER" and dotLane.identityCandidateMode=="hostile"
    and dotLane.candidateFilters.includeSpellIDs[2818] and not dotLane.sourceSpellIDs[123],
    "DoT eligibility pruning or player-owned native selection regressed")

_G.UnitClass=function() return "Rogue", "ROGUE" end
local predefined=A3._PlayerDefensiveSpellIDHash()
local disabledID
for id in pairs(predefined) do if id~=22812 then disabledID=id; break end end
assert(disabledID, "defensive fixture did not exercise a curated class list")
local defense=Entry(); defense.disabledPredefinedSpellIDs=tostring(disabledID)
defense.spellIDs="22812" -- An explicitly chosen custom ID can supplement defaults.
local defensive=assert(Compile(defense,4,"player").custom4)
assert(not defensive.candidateFilters.includeSpellIDs[disabledID]
    and defensive.candidateFilters.includeSpellIDs[20655] and not defensive.customPriority,
    "curated disable rules or custom defensive aliases changed")
print("PASS native custom aliases: initial candidates, two priority groups, two reminders/click bindings, disabled lanes, target DoTs, defensive overrides")
