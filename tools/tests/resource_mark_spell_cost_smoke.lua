local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local source = arg[2] or root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_ResourceMarks.lua"
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local checks, calls, combat, known = 0, 0, false, true
local function Check(value, message) checks = checks + 1 assert(value, message) end
local cost = { type = 3, minCost = 40, cost = 60, requiredAuraID = 0, hasRequiredAura = false, costPerSec = 0 }
local costs = { cost }
local info = { spellID = 123, name = "Test spell" }
C_Spell = {
    GetSpellInfo = function(id)
        if type(id) == "number" then assert(id == id and id > 0 and id < 2147483647 and id % 1 == 0, "invalid native spell identifier") end
        if id == 123 or id == "Test spell" then return info end
    end,
    GetSpellPowerCost = function() calls = calls + 1 return costs end,
}
C_SpellBook = { IsSpellInSpellBook = function() return known end }
Enum = { SpellBookSpellBank = { Player = 0 } }
local MSUF = { Client = { IsRetail = true }, CPBuilders = {},
    Secrets = { NotSecret = function(v) return not issecretvalue(v) end },
    Util = { InCombat = function() return combat end },
    Require = function() return function(region) return region end end,
    Optional = function() return nil end }
assert(loadfile(source))("Core", MSUF)
local B = MSUF.CPBuilders
Check(B.ResourceMarkCost ~= nil, "spell-cost source is missing")
local stop = Secrets.Watch(source, { strict = true })
Check(B.ResourceMarkCost(123, 3) == 40, "must use minimum, not optional full cost")
Check(B.ResourceMarkSpellID("|Hspell:123|h[Test spell]|h") == 123, "spell link")
Check(B.ResourceMarkSpellID("Test spell") == 123, "spell name")
for _, invalid in ipairs({ -1, 0, 1.5, math.huge, 0/0, "1e999", "-4" }) do
    Check(B.ResourceMarkSpellID(invalid) == nil, "invalid IDs never reach the native API")
end
Check(B.ResourceMarkCost(123, 0) == nil, "different resource must not borrow energy cost")
known = false
Check(B.ResourceMarkCost(123, 3) == nil, "unlearned spell")
known = true
combat = true
local before = calls
Check(B.ResourceMarkCost(123, 3) == nil and calls == before, "combat must not read costs")
combat = false
cost.minCost = 0
Check(B.ResourceMarkCost(123, 3) == 0, "free spell is a zero threshold")
cost.minCost = 40
cost.requiredAuraID = 55
Check(B.ResourceMarkCost(123, 3) == nil, "inactive form cost")
cost.hasRequiredAura = true
Check(B.ResourceMarkCost(123, 3) == 40, "active form cost")
cost.requiredAuraID, cost.hasRequiredAura = 0, false
cost.costPerSec = 5
Check(B.ResourceMarkCost(123, 3) == nil, "ongoing drain is not an upfront cost")
cost.costPerSec = 0
costs[2] = cost
Check(B.ResourceMarkCost(123, 3) == nil, "ambiguous duplicate power costs")
costs[2] = nil
local originalCost = C_Spell.GetSpellPowerCost
C_Spell.GetOverrideSpell = function() return 456 end
C_Spell.GetSpellPowerCost = function(id)
    if id == 456 then return {{ type = 3, minCost = 30 }} end
    return originalCost(id)
end
Check(B.ResourceMarkCost(123, 3) == 30, "current talent override cost")
C_Spell.GetOverrideSpell = function() return Secrets.New("number") end
Check(B.ResourceMarkCost(123, 3) == nil, "restricted override ID")
C_Spell.GetOverrideSpell = function(id) return id end
C_Spell.GetSpellPowerCost = originalCost
for _, key in ipairs({ "type", "minCost", "requiredAuraID", "hasRequiredAura", "costPerSec" }) do
    local old = cost[key]
    cost[key] = Secrets.New(key == "hasRequiredAura" and "boolean" or "number")
    Check(B.ResourceMarkCost(123, 3) == nil, "restricted field " .. key)
    cost[key] = old
end
local oldCosts = costs
costs = Secrets.New("table")
Check(B.ResourceMarkCost(123, 3) == nil, "restricted result table")
costs = oldCosts
known = Secrets.New("boolean")
Check(B.ResourceMarkCost(123, 3) == nil, "restricted known-spell result")
known = true
local violations = stop()
Check(#violations == 0, "secret access: " .. table.concat(violations, "\n"))
MSUF.Client.IsRetail = false
Check(not B.ResourceMarkCostSupported() and B.ResourceMarkCost(123, 3) == nil, "unaudited clients remain unsupported")
MSUF.Client.IsRetail = true

-- Exercise the actual mark painter and event lifetime, not just the reader.
local function Region()
    local r = { points = {}, registered = {}, shown = true }
    function r:SetAllPoints() end
    function r:EnableMouse() end
    function r:SetFrameLevel() end
    function r:GetFrameLevel() return 1 end
    function r:GetWidth() return 200 end
    function r:GetHeight() return 20 end
    function r:GetOrientation() return "HORIZONTAL" end
    function r:GetReverseFill() return false end
    function r:SetWidth(v) self.width = v end
    function r:SetHeight(v) self.height = v end
    function r:ClearAllPoints() self.points = {} end
    function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function r:SetColorTexture() end
    function r:SetShown(v) self.shown = v end
    function r:Hide() self.shown = false end
    function r:GetStatusBarColor() return 1, 1, 1, 1 end
    function r:SetStatusBarColor() end
    function r:HookScript() end
    function r:SetScript(_, fn) self.event = fn end
    function r:RegisterEvent(e) self.registered[e] = true end
    function r:RegisterUnitEvent(e) self.registered[e] = true end
    function r:UnregisterEvent(e) self.registered[e] = nil end
    function r:UnregisterAllEvents() self.registered = {} end
    function r:CreateTexture() return Region() end
    return r
end
local created = {}
function CreateFrame() local r = Region() created[#created+1] = r return r end
function InCombatLockdown() return combat end
function hooksecurefunc() end
function wipe(t) for k in pairs(t) do t[k] = nil end end
local bar, events = Region(), Region()
local rule = { target = "PLAYER", mode = "SPELL", spellID = 123, mark = true }
local E = { CP = {}, AM = {}, db = { bars = { resourceMarks = { rule } } }, events = events,
    NotSecret = MSUF.Secrets.NotSecret, GetPlayerFrame = function() return { targetPowerBar = bar } end,
    UnitPowerType = function() return 3, "ENERGY" end, UnitPowerMax = function() return 100 end,
    UnitPower = function() return 30 end, SupportsEvent = function() return true end }
local marks = B.ResourceMarks(E)
E.RequestRefresh = marks.Refresh
marks.Refresh()
local mark = created[1].marks[1]
Check(mark.shown and mark.points[1][4] == 80, "40/100 must mark 80 pixels on a 200 pixel bar")
Check(events.registered.SPELLS_CHANGED and events.registered.PLAYER_REGEN_ENABLED, "spell and combat-end refresh")
cost.minCost = 25
events.event(events, "SPELLS_CHANGED")
Check(mark.points[1][4] == 50, "changed spell cost must move the mark")
combat = true
before = calls
cost.minCost = 55
events.event(events, "SPELLS_CHANGED")
Check(mark.points[1][4] == 50 and calls == before, "combat keeps the out-of-combat snapshot")
combat = false
events.event(events, "PLAYER_REGEN_ENABLED")
Check(math.abs(mark.points[1][4] - 110) < .0001, "combat end refreshes the snapshot")
known = false
events.event(events, "SPELLS_CHANGED")
Check(not mark.shown and events.registered.SPELLS_CHANGED, "unavailable marks hide but retain recovery event")
known = true
events.event(events, "SPELLS_CHANGED")
Check(mark.shown, "learning the spell restores its mark")
rule.mode, rule.value = "ABSOLUTE", 30
marks.Refresh()
Check(mark.points[1][4] == 60 and not events.registered.SPELLS_CHANGED, "legacy absolute mark remains independent")
marks.Disable()
Check(not mark.shown and next(events.registered) == nil, "disable releases events and overlays")
print("resource_mark_spell_cost_smoke: " .. checks .. " checks passed")
