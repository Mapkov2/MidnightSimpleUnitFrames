_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local dashboardSmoke = "tools/assistant_dashboard_smoke.lua"
if not exists(dashboardSmoke) then dashboardSmoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(dashboardSmoke)

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing")
local M = assert(_G.MSUF_NS and _G.MSUF_NS.MSUF2, "Menu namespace missing")
local Registry = assert(A.Registry, "Assistant registry missing")
local G = assert(A.SettingGraph, "Assistant setting graph missing")

assert(G.IsBuilt() == false, "setting graph must stay cold until an explicit API call")

-- Combat must fail before AutoCoverage, registry traversal, graph construction,
-- or a setting getter is touched.
local originalLockdown = _G.InCombatLockdown
local originalAffectingCombat = _G.UnitAffectingCombat
local originalEnsureFilled = A.AutoCoverage and A.AutoCoverage.EnsureFilled
local originalAllSettings = Registry.AllSettings
local originalMenuFrame = M.frame
local ensureFilledCalls = 0
local registryReadCalls = 0
if A.AutoCoverage and type(originalEnsureFilled) == "function" then
    A.AutoCoverage.EnsureFilled = function(...)
        ensureFilledCalls = ensureFilledCalls + 1
        return originalEnsureFilled(...)
    end
end
Registry.AllSettings = function(...)
    registryReadCalls = registryReadCalls + 1
    return originalAllSettings(...)
end

-- A closed menu is an equally hard boundary. This must be checked while the
-- graph is still cold so a hidden-menu call cannot build indexes on demand.
A._menuRuntimeActive = false
local closedReport, closedError = G.GetCoverageReport()
assert(closedReport == nil and tostring(closedError):find("menu", 1, true), "cold closed-menu call must fail closed")
assert(G.IsBuilt() == false, "cold closed-menu call built the graph")
assert(ensureFilledCalls == 0, "cold closed-menu call touched AutoCoverage")
assert(registryReadCalls == 0, "cold closed-menu call touched the registry")
A._menuRuntimeActive = true

M.frame = { IsShown = function() return false end }
local hiddenFrameReport, hiddenFrameError = G.GetCoverageReport()
assert(hiddenFrameReport == nil and tostring(hiddenFrameError):find("menu", 1, true), "cold hidden-frame call must fail closed")
assert(G.IsBuilt() == false, "cold hidden-frame call built the graph")
assert(ensureFilledCalls == 0, "cold hidden-frame call touched AutoCoverage")
assert(registryReadCalls == 0, "cold hidden-frame call touched the registry")
M.frame = originalMenuFrame

_G.InCombatLockdown = function() return true end
_G.UnitAffectingCombat = function() return true end
local blockedReport, blockedError = G.GetCoverageReport()
assert(blockedReport == nil and tostring(blockedError):find("combat", 1, true), "cold combat call must fail closed")
assert(G.IsBuilt() == false, "cold combat call built the graph")
assert(ensureFilledCalls == 0, "cold combat call touched AutoCoverage")

_G.InCombatLockdown = function() return false end
_G.UnitAffectingCombat = function() return false end
local auraNode, auraError = G.GetNode("auras3.target.buff.visible")
assert(auraNode, auraError)
assert(G._state and G._state.buildScope == "aura", "Aura query did not use the lazy Aura graph domain")
assert(not G._state.groupRootsBuilt, "Aura query eagerly built group root edges")
local partialNode, partialError = G.GetNode("player.nameFontSize")
assert(partialNode, partialError)
assert(G._state and G._state.buildScope == "base", "non-Aura query did not promote the graph to its base domain")
assert(not (G._state and G._state.groupRootsBuilt), "non-group query eagerly built group root edges")
local report, reportError = G.GetCoverageReport()
assert(report, reportError)
assert(G._state and G._state.groupRootsBuilt == true, "coverage report did not complete group root edges")
assert(G.IsBuilt() == true, "explicit out-of-combat API call did not build graph")
assert(report.settings >= 4000, "graph did not include the complete Assistant registry")
assert(report.edges >= 4000, "dependency graph is unexpectedly sparse")
assert(report.relatedSettings >= 3000, "dependency graph setting coverage is unexpectedly low")
assert(#report.unresolved == 0, "graph has unresolved endpoints")

local function relationMap(key)
    local relations, err = G.GetDependencies(key)
    assert(relations, err)
    local out = {}
    for _, relation in ipairs(relations) do out[relation.kind .. ":" .. relation.to] = relation end
    return out, relations
end

local nameRelations, orderedNameRelations = relationMap("player.nameFontSize")
assert(nameRelations["enablement:player.enabled"], "player name font is missing the frame root")
assert(nameRelations["visibility:player.showName"], "player name font is missing the name visibility gate")

local castbarRelations = relationMap("general.castbarPlayerBarWidth")
assert(castbarRelations["enablement:general.enablePlayerCastbar"], "player castbar width is missing its enablement gate")

local partyStatusRelations = relationMap("gf_party.leaderIconStyle")
assert(partyStatusRelations["enablement:gf_party.enabled"], "party leader icon style is missing the group-frame root")

local fontRelations = relationMap("fontScope.target.outline")
local fontInheritance = assert(fontRelations["inheritance:fontScope.shared.outline"], "target font outline is missing shared inheritance")
assert(fontInheritance.gateKey == "fontScope.target.override", "font inheritance has the wrong override gate")
assert(fontRelations["override:fontScope.target.override"], "target font outline is missing override semantics")

local barRelations = relationMap("barScope.target.absorbBarOpacity")
assert(barRelations["inheritance:general.absorbBarOpacity"], "target absorb opacity is missing unambiguous global inheritance")

local conflictRelations = relationMap("auras3.player.buff.filter.cancelable")
assert(conflictRelations["conflict:auras3.player.buff.filter.notCancelable"], "Aura cancelable filter conflict is missing")

local requiredRelations = relationMap("bars.runeShowTimeText")
assert(requiredRelations["requires:bars.runeShowTime"], "rune time text prerequisite is missing")

local disabledDiagnosis = assert(G.Diagnose("player.nameFontSize", {
    values = {
        ["player.enabled"] = false,
        ["player.showName"] = true,
    },
}))
assert(disabledDiagnosis.evaluation.enabled == false, "disabled unit root was not diagnosed")
assert(disabledDiagnosis.evaluation.effective == false, "disabled unit root remained effective")
assert(#disabledDiagnosis.evaluation.blockers >= 1, "disabled unit root did not produce a blocker")

local hiddenDiagnosis = assert(G.Diagnose("player.nameFontSize", {
    values = {
        ["player.enabled"] = true,
        ["player.showName"] = false,
    },
}))
assert(hiddenDiagnosis.evaluation.visible == false, "hidden name component was not diagnosed")
assert(hiddenDiagnosis.evaluation.effective == true, "visibility-only gate incorrectly made the setting ineffective")

local inheritedDiagnosis = assert(G.Diagnose("fontScope.target.outline", {
    values = { ["fontScope.target.override"] = false },
}))
assert(#inheritedDiagnosis.evaluation.inheritedFrom == 1, "shared font inheritance was not diagnosed")
assert(inheritedDiagnosis.evaluation.inheritedFrom[1].to == "fontScope.shared.outline", "wrong inherited font source")

local conflictDiagnosis = assert(G.Diagnose("auras3.player.buff.filter.cancelable", {
    values = {
        ["auras3.player.buff.filter.cancelable"] = true,
        ["auras3.player.buff.filter.notCancelable"] = true,
        ["auras3.enabled"] = true,
        ["auras3.player.buff.visible"] = true,
        ["auras3.player.filtersEnabled"] = true,
        ["auras3.player.useSharedRules"] = false,
    },
}))
assert(#conflictDiagnosis.evaluation.activeConflicts == 1, "active Aura filter conflict was not diagnosed")

-- Returned relation tables are copies and relation order is stable.
local orderBefore = {}
for i, edge in ipairs(orderedNameRelations) do orderBefore[i] = edge.kind .. ":" .. edge.to end
orderedNameRelations[1].reason = "mutated by test"
local _, orderAgainRelations = relationMap("player.nameFontSize")
local orderAfter = {}
for i, edge in ipairs(orderAgainRelations) do orderAfter[i] = edge.kind .. ":" .. edge.to end
assert(table.concat(orderBefore, "|") == table.concat(orderAfter, "|"), "relation order is not deterministic")
assert(orderAgainRelations[1].reason ~= "mutated by test", "public relation result leaked internal graph state")

local validation, validationError = G.Validate()
assert(validation, validationError)
assert(validation.ok, "graph validation failed: " .. table.concat(validation.errors or {}, "; "))
assert(#validation.cycles == 0, "dependency graph contains a cycle")

-- A cached graph is also completely inert in combat: no setting getter and no
-- rebuild is allowed.
local watched = assert(Registry:GetSetting("player.nameFontSize"), "watched setting missing")
local originalGet = watched.get
local getCalls = 0
watched.get = function(...)
    getCalls = getCalls + 1
    return originalGet(...)
end
local serialBeforeCombat = report.buildSerial
_G.InCombatLockdown = function() return true end
_G.UnitAffectingCombat = function() return true end
local blockedExplain, cachedCombatError = G.Explain("player.nameFontSize")
assert(blockedExplain == nil and tostring(cachedCombatError):find("combat", 1, true), "cached combat call must fail closed")
assert(getCalls == 0, "cached combat call touched a setting getter")
assert((G._buildSerial or 0) == serialBeforeCombat, "cached combat call rebuilt the graph")

_G.InCombatLockdown = function() return false end
_G.UnitAffectingCombat = function() return false end
A._menuRuntimeActive = false
local closedExplain, cachedClosedError = G.Explain("player.nameFontSize")
assert(closedExplain == nil and tostring(cachedClosedError):find("menu", 1, true), "cached closed-menu call must fail closed")
assert(getCalls == 0, "cached closed-menu call touched a setting getter")
assert((G._buildSerial or 0) == serialBeforeCombat, "cached closed-menu call rebuilt the graph")
A._menuRuntimeActive = true

M.frame = { IsShown = function() return false end }
local hiddenFrameExplain, cachedHiddenFrameError = G.Explain("player.nameFontSize")
assert(hiddenFrameExplain == nil and tostring(cachedHiddenFrameError):find("menu", 1, true), "cached hidden-frame call must fail closed")
assert(getCalls == 0, "cached hidden-frame call touched a setting getter")
assert((G._buildSerial or 0) == serialBeforeCombat, "cached hidden-frame call rebuilt the graph")
M.frame = originalMenuFrame

watched.get = originalGet
_G.InCombatLockdown = originalLockdown
_G.UnitAffectingCombat = originalAffectingCombat
Registry.AllSettings = originalAllSettings
if A.AutoCoverage and type(originalEnsureFilled) == "function" then A.AutoCoverage.EnsureFilled = originalEnsureFilled end

io.write(("assistant_setting_graph_smoke: ok settings=%d related=%d edges=%d coverage=%.2f%%\n")
    :format(report.settings, report.relatedSettings, report.edges, report.coveragePercent))
