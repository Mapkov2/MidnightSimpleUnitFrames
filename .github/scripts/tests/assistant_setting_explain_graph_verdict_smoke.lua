-- F1: the plain "explain this setting" answer must surface the live
-- dependency-graph verdict.  R.RegistrySettingGraphVerdictLine turns the
-- graph evaluator's output into one human sentence, and stays silent (nil)
-- for an effective, independent setting or when the graph is unavailable so
-- the common explain answer keeps its length and degrades gracefully.
_G = _G or _ENV

local root = arg and arg[1] or "."

local function Check(value, message)
    if not value then error(message or "check failed", 2) end
end

local MSUF = { MSUF2 = {}, Assistant = {} }
local M, A = MSUF.MSUF2, MSUF.Assistant
_G.MSUF_NS, _G.MSUF2 = MSUF, M
_G.InCombatLockdown = function() return false end
_G.UnitAffectingCombat = function() return false end
_G.GetTime = function() return os.clock() end

-- Labels the verdict line resolves related keys through.
local SETTING_LABELS = {
    ["player.showPowerBar"] = "Show Power Bar",
    ["player.detachedPowerBarShape"] = "Detached Power Shape",
    ["auras3.shared.buffs.iconSize"] = "Shared Buff Icon Size",
    ["auras3.player.buffs.filter.friendlyOnly"] = "Friendly Only",
}
local Registry = { byKey = {} }
function Registry:GetSetting(key) return SETTING_LABELS[key] and { key = key, label = SETTING_LABELS[key] } or nil end
function Registry:AllSettings() return {} end
A.Registry = Registry
A.RouterPrivate = A.RouterPrivate or {}
A.RouterPrivate.Normalize = function(text) return tostring(text or ""):lower() end

local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRouter.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)

local R = A.RouterPrivate
Check(type(R.RegistrySettingGraphVerdictLine) == "function",
    "RegistrySettingGraphVerdictLine must be defined on the router")

-- Drive the real function through the guard-free evaluator so each verdict
-- branch is exercised against the actual sentence-building code.  The verdict
-- line reads only EvaluateSettingDependenciesIfBuilt, which itself returns nil
-- when the graph is not built yet (it must never force a cold build for one
-- extra sentence).  `graphBuilt=false` models that unbuilt state by returning
-- nil from the stub regardless of nextEvaluation.
local graphBuilt = true
local nextEvaluation
A.EvaluateSettingDependenciesIfBuilt = function(key)
    Check(type(key) == "string" and key ~= "", "evaluator must receive a non-empty key")
    if not graphBuilt then return nil end
    if nextEvaluation == "error" then return nil end
    return nextEvaluation
end

local function ItemFor(key) return { settingKey = key, key = key, setting = { key = key } } end

-- 1. Blocked: an ineffective control names the prerequisite that is off.
nextEvaluation = {
    value = 30, valueKnown = true, effective = false,
    blockers = { { to = "player.detachedPowerBarShape", kind = "availability" } },
    activeConflicts = {}, inheritedFrom = {},
}
local blocked = R.RegistrySettingGraphVerdictLine(ItemFor("player.detachedPowerOrbSize"))
Check(type(blocked) == "string", "blocked setting must produce a verdict line")
Check(blocked:find("not fully effective", 1, true), "blocked verdict must explain ineffectiveness")
Check(blocked:find("Detached Power Shape", 1, true), "blocked verdict must name the blocker by label")

-- 2. Conflict: an active mutual exclusion is reported with the other option.
nextEvaluation = {
    value = true, valueKnown = true, effective = true,
    blockers = {}, inheritedFrom = {},
    activeConflicts = { { to = "auras3.player.buffs.filter.friendlyOnly", kind = "conflict" } },
}
local conflict = R.RegistrySettingGraphVerdictLine(ItemFor("auras3.player.buffs.filter.hostileOnly"))
Check(type(conflict) == "string" and conflict:find("conflicts with", 1, true), "conflict verdict must be reported")
Check(conflict:find("Friendly Only", 1, true), "conflict verdict must name the conflicting option by label")

-- 3. Inheritance: a shared-source value tells the user how to make it independent.
nextEvaluation = {
    value = 24, valueKnown = true, effective = true,
    blockers = {}, activeConflicts = {},
    inheritedFrom = { { to = "auras3.shared.buffs.iconSize", kind = "inheritance" } },
}
local inherited = R.RegistrySettingGraphVerdictLine(ItemFor("auras3.player.buffs.iconSize"))
Check(type(inherited) == "string" and inherited:find("inherited from", 1, true), "inheritance verdict must be reported")
Check(inherited:find("scope override", 1, true), "inheritance verdict must mention the override path")

-- 4. Effective + independent: no runtime story to tell -> stay silent.
nextEvaluation = {
    value = 300, valueKnown = true, effective = true,
    blockers = {}, activeConflicts = {}, inheritedFrom = {},
}
Check(R.RegistrySettingGraphVerdictLine(ItemFor("player.width")) == nil,
    "an effective, independent setting must not add a verdict line")

-- 5. Guard-free evaluator returns nil (unknown key / unreadable state): degrade.
nextEvaluation = "error"
Check(R.RegistrySettingGraphVerdictLine(ItemFor("player.width")) == nil,
    "a nil evaluation must degrade to today's answer (nil)")

-- 6. Graph not built yet: stay silent instead of forcing a ~100ms cold build
-- for one extra sentence.  A blocked evaluation would otherwise produce a line.
graphBuilt = false
nextEvaluation = {
    value = 30, valueKnown = true, effective = false,
    blockers = { { to = "player.detachedPowerBarShape", kind = "availability" } },
    activeConflicts = {}, inheritedFrom = {},
}
Check(R.RegistrySettingGraphVerdictLine(ItemFor("player.detachedPowerOrbSize")) == nil,
    "an unbuilt graph must not enrich (and must not force a build)")
graphBuilt = true

-- 7. No evaluator wired at all: still nil, never an error.
A.EvaluateSettingDependenciesIfBuilt = nil
Check(R.RegistrySettingGraphVerdictLine(ItemFor("player.width")) == nil,
    "a missing evaluator must degrade to nil")

-- 8. Empty item / missing key: nil, no crash.
Check(R.RegistrySettingGraphVerdictLine({}) == nil, "an item without a key must return nil")
Check(R.RegistrySettingGraphVerdictLine(nil) == nil, "a nil item must return nil")

print("assistant_setting_explain_graph_verdict_smoke: PASS")
