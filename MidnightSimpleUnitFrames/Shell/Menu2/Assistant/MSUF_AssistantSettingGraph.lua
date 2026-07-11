-- Lazy, deterministic dependency graph for Assistant settings.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local D = A.SettingGraphData
if type(D) ~= "table" then return end

local G = A.SettingGraph or {}
A.SettingGraph = G
M.AssistantSettingGraph = G

G.schemaVersion = D.schemaVersion or 1

local DEFAULT_TRUE = { operator = "equals", value = true }
local DEPENDENCY_KINDS = { enablement = true, visibility = true, availability = true, requires = true }
local COMBAT_ERROR = "assistant setting graph is unavailable during combat"
local MENU_CLOSED_ERROR = "assistant setting graph is unavailable while the MSUF menu is closed"

-- The Assistant has a hard zero-work-in-combat contract.  Public graph calls
-- check this before touching the registry, AutoCoverage, a setting getter, or
-- any cached graph table.  There is intentionally no event/ticker that retries
-- later; an explicit menu/Assistant request after combat may call again.
local function IsCombatBlocked()
    local lockdown = _G.InCombatLockdown
    if type(lockdown) == "function" and lockdown() then return true end
    local affectingCombat = _G.UnitAffectingCombat
    if type(affectingCombat) == "function" and affectingCombat("player") then return true end
    return false
end

local function IsMenuClosed()
    local frame = M and M.frame
    if frame and type(frame.IsShown) == "function" then
        local ok, shown = pcall(frame.IsShown, frame)
        if ok then return shown ~= true or A._menuRuntimeActive == false end
    end
    return A._menuRuntimeActive == false
end

local function ArraySet(values)
    local out = {}
    for i = 1, #(values or {}) do out[values[i]] = true end
    return out
end

local function ShallowCopy(source)
    local out = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            local nested = {}
            for nestedKey, nestedValue in pairs(value) do nested[nestedKey] = nestedValue end
            out[key] = nested
        else
            out[key] = value
        end
    end
    return out
end

local function CopyArray(source)
    local out = {}
    for i = 1, #(source or {}) do out[i] = ShallowCopy(source[i]) end
    return out
end

local function SortedKeys(source)
    local out = {}
    for key in pairs(source or {}) do out[#out + 1] = key end
    table.sort(out)
    return out
end

local function ReplaceCaptures(template, captures)
    return (tostring(template or ""):gsub("{(%d+)}", function(index)
        return tostring(captures[tonumber(index)] or "")
    end))
end

local function ReplaceScope(template, scope)
    return (tostring(template or ""):gsub("{scope}", tostring(scope or "")))
end

local function StartsWith(text, prefix)
    return tostring(text or ""):sub(1, #tostring(prefix or "")) == tostring(prefix or "")
end

local EMPTY_SETTINGS = {}

local function TopSegment(key)
    return tostring(key or ""):match("^([^.]+)") or ""
end

-- Build one compact, transient scan index for the graph construction pass.
-- Most rules target a single top-level namespace (bars, gameplay, fontScope,
-- auras3, ...). Re-scanning the entire registry for every such prefix made a
-- first dependency question pay O(settings * rules) work. The index keeps the
-- rule data generic while limiting each scan to the namespace it can match.
local function BuildScanIndex(settings)
    local byTop = {}
    for _, setting in ipairs(settings) do
        local key = type(setting) == "table" and setting.key or nil
        if type(key) == "string" then
            local top = TopSegment(key)
            local bucket = byTop[top]
            if not bucket then
                bucket = {}
                byTop[top] = bucket
            end
            bucket[#bucket + 1] = setting
        end
    end
    return { byTop = byTop }
end

local function PrefixSettings(scanIndex, prefix)
    local byTop = scanIndex and scanIndex.byTop
    return byTop and byTop[TopSegment(prefix)] or EMPTY_SETTINGS
end

local function EdgeSort(a, b)
    local ak, bk = tostring(a.kind), tostring(b.kind)
    if ak ~= bk then return ak < bk end
    ak, bk = tostring(a.from), tostring(b.from)
    if ak ~= bk then return ak < bk end
    ak, bk = tostring(a.to), tostring(b.to)
    if ak ~= bk then return ak < bk end
    return tostring(a.ruleId) < tostring(b.ruleId)
end

local function EnsureAutoCoverage()
    local Auto = A.AutoCoverage
    if Auto and type(Auto.EnsureFilled) == "function" then
        pcall(Auto.EnsureFilled)
    end
end

local function CurrentRegistry()
    local Registry = A.Registry
    if type(Registry) ~= "table" or type(Registry.AllSettings) ~= "function" then return nil, {} end
    local settings = Registry:AllSettings()
    return Registry, type(settings) == "table" and settings or {}
end

local function AddEdge(state, edge)
    if type(edge) ~= "table" then return false end
    local from, to, kind = tostring(edge.from or ""), tostring(edge.to or ""), tostring(edge.kind or "")
    if from == "" or to == "" or from == to or not D.relationKinds[kind] then return false end
    if not state.settingsByKey[from] or not state.settingsByKey[to] then
        state.unresolved[#state.unresolved + 1] = {
            from = from,
            to = to,
            kind = kind,
            ruleId = edge.ruleId,
        }
        return false
    end
    local identity = kind .. "\031" .. from .. "\031" .. to .. "\031" .. tostring(edge.ruleId or "")
    if state.edgeIdentity[identity] then return false end
    state.edgeIdentity[identity] = true

    edge.from, edge.to, edge.kind = from, to, kind
    -- Conditions are immutable declarative data internally; copies are made
    -- only at the public API boundary.
    edge.condition = edge.condition or DEFAULT_TRUE
    edge.confidence = edge.confidence or "explicit"
    state.edges[#state.edges + 1] = edge
    state.outgoing[from] = state.outgoing[from] or {}
    state.incoming[to] = state.incoming[to] or {}
    state.outgoing[from][#state.outgoing[from] + 1] = edge
    state.incoming[to][#state.incoming[to] + 1] = edge
    state.byKind[kind] = (state.byKind[kind] or 0) + 1
    state.ruleHits[edge.ruleId or "unknown"] = (state.ruleHits[edge.ruleId or "unknown"] or 0) + 1
    return true
end

local function EdgeFromRule(rule, from, to, extra)
    local edge = {
        from = from,
        to = to,
        kind = rule.kind,
        condition = rule.condition or DEFAULT_TRUE,
        impact = rule.impact,
        reason = rule.reason,
        evidence = rule.evidence,
        ruleId = rule.id,
    }
    for key, value in pairs(extra or {}) do edge[key] = value end
    return edge
end

local function ApplyScopeRoots(state, settings, scanIndex, mode)
    for _, rule in ipairs(D.scopeRootRules or {}) do
        local isGroupRoot = rule.id == "group-frame-root"
        local applyRule = mode == "all"
            or (mode == "group" and isGroupRoot)
            or (mode == "base" and not isGroupRoot)
            or (mode == "aura" and rule.id == "unit-aura-root")
        if applyRule then
        local scopeSet = ArraySet(D[rule.scopes] or {})
        if rule.keyPrefix then
            for _, setting in ipairs(PrefixSettings(scanIndex, rule.keyPrefix)) do
                local key = tostring(setting.key or "")
                if StartsWith(key, rule.keyPrefix) then
                    local parent = ReplaceScope(rule.parent, tostring(setting.unit or ""))
                    if key ~= parent then AddEdge(state, EdgeFromRule(rule, key, parent)) end
                end
            end
        else
            local frameTypes = ArraySet(rule.frameTypes or {})
            for _, scope in ipairs(D[rule.scopes] or {}) do
                for _, setting in ipairs(PrefixSettings(scanIndex, scope .. ".")) do
                    local key = tostring(setting.key or "")
                    if scopeSet[scope] and frameTypes[tostring(setting.frameType or "")] then
                        local parent = ReplaceScope(rule.parent, scope)
                        if key ~= parent then AddEdge(state, EdgeFromRule(rule, key, parent)) end
                    end
                end
            end
        end
        end
    end
end

local function ApplyPatternCandidates(state, rule, allowed, denied, candidates)
    for _, setting in ipairs(candidates) do
        local key = tostring(setting.key or "")
        local captures = { key:match(rule.match) }
        if #captures > 0 then
            local accepted = true
            if allowed then accepted = allowed[captures[rule.allowedCapture.index]] == true end
            if denied and denied[captures[rule.deniedCapture.index]] then accepted = false end
            if accepted then
                local parent = ReplaceCaptures(rule.parent, captures)
                if key ~= parent then AddEdge(state, EdgeFromRule(rule, key, parent)) end
            end
        end
    end
end

local function ApplyPatternGates(state, settings, scanIndex, mode)
    for _, rule in ipairs(D.patternGateRules or {}) do
        local applyRule = mode ~= "aura" or rule.scanTop == "auras3"
        if applyRule then
        local allowed, denied
        if rule.allowedCapture then allowed = ArraySet(rule.allowedCapture.values) end
        if rule.deniedCapture then denied = ArraySet(rule.deniedCapture.values) end
        if rule.scanTops then
            for _, top in ipairs(D[rule.scanTops] or {}) do
                ApplyPatternCandidates(state, rule, allowed, denied, PrefixSettings(scanIndex, top .. "."))
            end
        elseif rule.scanTop then
            ApplyPatternCandidates(state, rule, allowed, denied, PrefixSettings(scanIndex, rule.scanTop .. "."))
        else
            ApplyPatternCandidates(state, rule, allowed, denied, settings)
        end
        end
    end
end

local function ApplyScopedFieldGates(state, scanIndex)
    local rulesByScope = {}
    local scopeOrder, seenScope = {}, {}
    for _, rule in ipairs(D.scopedFieldGateRules or {}) do
        for _, scope in ipairs(D[rule.scopes] or {}) do
            local parent = scope .. "." .. rule.parentSuffix
            if state.settingsByKey[parent] then
                local byInitial = rulesByScope[scope]
                if not byInitial then
                    byInitial = {}
                    rulesByScope[scope] = byInitial
                end
                if not seenScope[scope] then
                    seenScope[scope] = true
                    scopeOrder[#scopeOrder + 1] = scope
                end

                local prefixesByInitial = {}
                for _, prefix in ipairs(rule.childPrefixes or {}) do
                    local initial = tostring(prefix):sub(1, 1)
                    local prefixes = prefixesByInitial[initial]
                    if not prefixes then
                        prefixes = {}
                        prefixesByInitial[initial] = prefixes
                    end
                    prefixes[#prefixes + 1] = prefix
                end
                for initial, prefixes in pairs(prefixesByInitial) do
                    local entries = byInitial[initial]
                    if not entries then
                        entries = {}
                        byInitial[initial] = entries
                    end
                    entries[#entries + 1] = {
                        rule = rule,
                        parent = parent,
                        prefixes = prefixes,
                    }
                end
            end
        end
    end

    for _, scope in ipairs(scopeOrder) do
        local byInitial = rulesByScope[scope]
        for _, setting in ipairs(PrefixSettings(scanIndex, scope .. ".")) do
            local key = tostring(setting.key or "")
            local suffix = key:sub(#scope + 2)
            for _, entry in ipairs(byInitial[suffix:sub(1, 1)] or EMPTY_SETTINGS) do
                if key ~= entry.parent then
                    for _, prefix in ipairs(entry.prefixes) do
                        if StartsWith(suffix, prefix) then
                            AddEdge(state, EdgeFromRule(entry.rule, key, entry.parent))
                            break
                        end
                    end
                end
            end
        end
    end
end

local function ApplyPrefixGates(state, scanIndex)
    for _, rule in ipairs(D.prefixGateRules or {}) do
        if state.settingsByKey[rule.parent] then
            for _, setting in ipairs(PrefixSettings(scanIndex, rule.childPrefix)) do
                local key = tostring(setting.key or "")
                if key ~= rule.parent and StartsWith(key, rule.childPrefix) then
                    AddEdge(state, EdgeFromRule(rule, key, rule.parent))
                end
            end
        end
    end
end

local function ApplyFeatureGates(state, scanIndex)
    for _, rule in ipairs(D.featureGateRules or {}) do
        if state.settingsByKey[rule.parent] then
            for _, childPrefix in ipairs(rule.children or {}) do
                for _, setting in ipairs(PrefixSettings(scanIndex, childPrefix)) do
                    local key = tostring(setting.key or "")
                    if key ~= rule.parent and StartsWith(key, childPrefix) then
                        AddEdge(state, EdgeFromRule(rule, key, rule.parent))
                    end
                end
            end
        end
    end
end

local function ApplyCastbarGates(state, settings)
    local data = A.CastbarsRegistry and A.CastbarsRegistry.CASTBAR_KEYS or {}
    for _, setting in ipairs(settings) do
        if setting.frameType == "castbar" then
            local unit = tostring(setting.unit or "")
            local keys = data[unit]
            local parent = keys and ("general." .. tostring(keys.enable or "")) or nil
            if parent and setting.key ~= parent and state.settingsByKey[parent] then
                AddEdge(state, {
                    from = setting.key,
                    to = parent,
                    kind = "enablement",
                    condition = DEFAULT_TRUE,
                    impact = "runtimeEffectiveness",
                    reason = "Cast-bar details affect the live bar only while that unit's cast bar is enabled.",
                    evidence = "MSUF_AssistantRegistry_Castbars_Core_Data.lua:CASTBAR_KEYS and Castbars_Core.lua:RegisterUnitCastbarBoolean",
                    ruleId = "castbar-unit-root",
                })
            end
        end
    end
end

local function ApplyRequires(state)
    for _, rule in ipairs(D.requiresEdges or {}) do
        AddEdge(state, {
            from = rule.from,
            to = rule.to,
            kind = "requires",
            condition = rule.condition or DEFAULT_TRUE,
            impact = "hardPrerequisite",
            reason = rule.reason,
            evidence = rule.evidence,
            ruleId = rule.id,
        })
    end
end

local function ApplyScopedInheritance(state, scanIndex)
    for _, rule in ipairs(D.scopedInheritanceRules or {}) do
        for _, scope in ipairs(rule.scopes or {}) do
            local scopePrefix = rule.prefix .. "." .. scope .. "."
            local gate = scopePrefix .. rule.overrideSuffix
            if state.settingsByKey[gate] then
                for _, setting in ipairs(PrefixSettings(scanIndex, scopePrefix)) do
                    local key = tostring(setting.key or "")
                    if key ~= gate and StartsWith(key, scopePrefix) then
                        local suffix = key:sub(#scopePrefix + 1)
                        local candidates = {}
                        for _, sourcePrefix in ipairs(rule.sourcePrefixes or {}) do
                            local candidate = sourcePrefix .. "." .. suffix
                            if state.settingsByKey[candidate] then candidates[#candidates + 1] = candidate end
                        end
                        if #candidates == 1 or (not rule.requireUniqueSource and #candidates > 0) then
                            local source = candidates[1]
                            AddEdge(state, {
                                from = key,
                                to = source,
                                kind = "inheritance",
                                condition = { operator = "equals", value = false },
                                gateKey = gate,
                                gateCondition = { operator = "equals", value = false },
                                impact = "effectiveValueSource",
                                reason = "This scoped value inherits its shared value while the scope override is off.",
                                evidence = rule.evidence,
                                ruleId = rule.id,
                            })
                            AddEdge(state, {
                                from = key,
                                to = gate,
                                kind = "override",
                                condition = { operator = "equals", value = true },
                                impact = "effectiveValueSource",
                                reason = "Turn on the scope override to make this value independent from its shared source.",
                                evidence = rule.evidence,
                                ruleId = rule.id .. "-override",
                            })
                        end
                    end
                end
            end
        end
    end
end

local function ApplyAuraInheritance(state, scanIndex)
    local info = D.auraInheritance or {}
    local styleLeaves = ArraySet(info.styleLeafKeys or {})
    local auraScopes = ArraySet(D.auraScopes or {})
    for _, setting in ipairs(PrefixSettings(scanIndex, "auras3.")) do
        local key = tostring(setting.key or "")
        local scope, relative = key:match("^auras3%.([^.]+)%.(.+)$")
        if auraScopes[scope] then
            local prefix = "auras3." .. scope .. "."
            local styleGate = prefix .. tostring(info.styleGateSuffix or "useSharedStyle")
            local rulesGate = prefix .. tostring(info.rulesGateSuffix or "useSharedRules")
            local source = "auras3.shared." .. relative
            if state.settingsByKey[source] then
                local leaf = relative:match("([^.]+)$") or ""
                local isFilter = relative:find("%.filter%.", 1, false) ~= nil
                local gate, evidence, ruleId
                if isFilter and state.settingsByKey[rulesGate] then
                    gate, evidence, ruleId = rulesGate, info.evidenceRules, "aura-rules-inheritance"
                elseif styleLeaves[leaf] and state.settingsByKey[styleGate] then
                    gate, evidence, ruleId = styleGate, info.evidenceStyle, "aura-style-inheritance"
                end
                if gate then
                    AddEdge(state, {
                        from = key,
                        to = source,
                        kind = "inheritance",
                        condition = DEFAULT_TRUE,
                        gateKey = gate,
                        gateCondition = DEFAULT_TRUE,
                        impact = "effectiveValueSource",
                        reason = "This Aura value comes from Shared while the scope uses shared rules or style.",
                        evidence = evidence,
                        ruleId = ruleId,
                    })
                    AddEdge(state, {
                        from = key,
                        to = gate,
                        kind = "override",
                        condition = { operator = "equals", value = false },
                        impact = "effectiveValueSource",
                        reason = "Disable shared inheritance to give this Aura scope an independent value.",
                        evidence = evidence,
                        ruleId = ruleId .. "-override",
                    })
                end
            end
        end
    end
end

local function ApplyConflicts(state)
    local data = A.AurasRegistryData or {}
    for _, provider in ipairs(D.conflictProviders or {}) do
        if provider.provider == "auraFilterSpecs" then
            for _, spec in ipairs(data.AURA_FILTER_BOOLEAN_SPECS or {}) do
                for _, conflictLeaf in ipairs(spec.conflicts or {}) do
                    for _, scope in ipairs({ "shared", "player", "target", "focus", "boss" }) do
                        local from = table.concat({ "auras3", scope, spec.lane, "filter", spec.key }, ".")
                        local to = table.concat({ "auras3", scope, spec.lane, "filter", conflictLeaf }, ".")
                        AddEdge(state, {
                            from = from,
                            to = to,
                            kind = "conflict",
                            condition = DEFAULT_TRUE,
                            impact = "mutualExclusion",
                            reason = "Enabling either filter disables the conflicting filter in the same Aura lane.",
                            evidence = provider.evidence,
                            ruleId = provider.id,
                        })
                    end
                end
            end
        end
    end
end

local function Finalize(state, settings)
    -- Sorting every adjacency list makes a cold build needlessly expensive.
    -- Public APIs sort only the small copied list they return, preserving a
    -- deterministic contract without front-loading work for unused nodes.
    table.sort(state.unresolved, EdgeSort)

    local related = {}
    for key in pairs(state.outgoing) do related[key] = true end
    for key in pairs(state.incoming) do related[key] = true end
    state.relatedNodeCount = 0
    for _ in pairs(related) do state.relatedNodeCount = state.relatedNodeCount + 1 end
    state.settingCount = #settings
end

local function Build(includeGroupRoots, requestedKey)
    EnsureAutoCoverage()
    local Registry, settings = CurrentRegistry()
    local state = {
        Registry = Registry,
        settingsByKey = {},
        edges = {},
        outgoing = {},
        incoming = {},
        byKind = {},
        ruleHits = {},
        unresolved = {},
        edgeIdentity = {},
    }
    for _, setting in ipairs(settings) do
        if type(setting) == "table" and type(setting.key) == "string" then
            state.settingsByKey[setting.key] = setting
        end
    end
    local scanIndex = BuildScanIndex(settings)
    local auraOnly = not includeGroupRoots
        and tostring(requestedKey or ""):match("^auras3%.") ~= nil

    if auraOnly then
        ApplyScopeRoots(state, settings, scanIndex, "aura")
        ApplyPatternGates(state, settings, scanIndex, "aura")
        ApplyAuraInheritance(state, scanIndex)
        ApplyConflicts(state)
    else
        ApplyScopeRoots(state, settings, scanIndex, includeGroupRoots and "all" or "base")
        ApplyPatternGates(state, settings, scanIndex, "base")
        ApplyScopedFieldGates(state, scanIndex)
        ApplyPrefixGates(state, scanIndex)
        ApplyFeatureGates(state, scanIndex)
        ApplyCastbarGates(state, settings)
        ApplyRequires(state)
        ApplyScopedInheritance(state, scanIndex)
        ApplyAuraInheritance(state, scanIndex)
        ApplyConflicts(state)
    end
    Finalize(state, settings)

    G._state = state
    G._built = true
    G._registryCount = #settings
    state.buildScope = auraOnly and "aura" or "base"
    state.groupRootsBuilt = includeGroupRoots == true
    G._buildSerial = (G._buildSerial or 0) + 1
    return state
end

local function CompleteGroupRoots(state, settings)
    if state.groupRootsBuilt then return state end
    ApplyScopeRoots(state, settings, BuildScanIndex(settings), "group")
    Finalize(state, settings)
    state.groupRootsBuilt = true
    G._buildSerial = (G._buildSerial or 0) + 1
    return state
end

local function EnsureBuilt(requestedKey, requireComplete)
    if IsCombatBlocked() then return nil, COMBAT_ERROR end
    if IsMenuClosed() then return nil, MENU_CLOSED_ERROR end
    local _, before = CurrentRegistry()
    local needsGroupRoots = requireComplete == true
        or tostring(requestedKey or ""):match("^gf_") ~= nil
    local requestedAura = tostring(requestedKey or ""):match("^auras3%.") ~= nil
    if G._built ~= true then return Build(needsGroupRoots, requestedKey) end
    EnsureAutoCoverage()
    local _, after = CurrentRegistry()
    if G._registryCount ~= #after or #before ~= #after then return Build(needsGroupRoots, requestedKey) end
    if G._state.buildScope == "aura" and (requireComplete == true or not requestedAura) then
        return Build(needsGroupRoots, requestedKey)
    end
    if needsGroupRoots and not G._state.groupRootsBuilt then
        return CompleteGroupRoots(G._state, after)
    end
    return G._state
end

function G.Invalidate()
    G._state = nil
    G._built = false
    G._registryCount = nil
end

function G.IsBuilt()
    return G._built == true
end

function G.GetNode(key)
    key = type(key) == "table" and key.key or key
    key = tostring(key or "")
    local state, readyError = EnsureBuilt(key)
    if not state then return nil, readyError end
    local setting = state.settingsByKey[key]
    if not setting then return nil, "unknown setting: " .. key end
    local dependencies = CopyArray(state.outgoing[key])
    local dependents = CopyArray(state.incoming[key])
    table.sort(dependencies, EdgeSort)
    table.sort(dependents, EdgeSort)
    return {
        key = key,
        label = setting.label,
        category = setting.category,
        unit = setting.unit,
        frameType = setting.frameType,
        type = setting.type,
        dependencies = dependencies,
        dependents = dependents,
    }
end

function G.GetRelations(key, direction, kind)
    key = type(key) == "table" and key.key or key
    key = tostring(key or "")
    local state, readyError = EnsureBuilt(key)
    if not state then return nil, readyError end
    if not state.settingsByKey[key] then return nil, "unknown setting: " .. key end
    local source = direction == "dependents" and state.incoming[key] or state.outgoing[key]
    local out = {}
    for _, edge in ipairs(source or {}) do
        if not kind or edge.kind == kind then out[#out + 1] = ShallowCopy(edge) end
    end
    table.sort(out, EdgeSort)
    return out
end

function G.GetDependencies(key, kind)
    return G.GetRelations(key, "dependencies", kind)
end

function G.GetDependents(key, kind)
    return G.GetRelations(key, "dependents", kind)
end

local function ReadValue(state, key, context, cache)
    if cache[key] then return cache[key].value, cache[key].known, cache[key].error end
    local values = context and context.values
    if type(values) == "table" and rawget(values, key) ~= nil then
        local item = { value = values[key], known = true }
        cache[key] = item
        return item.value, item.known
    end
    local setting = state.settingsByKey[key]
    if not setting or type(setting.get) ~= "function" then
        local item = { known = false, error = "setting has no reader" }
        cache[key] = item
        return nil, false, item.error
    end
    local ok, value = pcall(setting.get)
    local item = ok and { value = value, known = true } or { known = false, error = tostring(value) }
    cache[key] = item
    return item.value, item.known, item.error
end

local function ConditionMatches(value, known, condition)
    if not known then return nil end
    condition = condition or DEFAULT_TRUE
    local operator = condition.operator or "equals"
    if operator == "equals" then return value == condition.value end
    if operator == "notEquals" then return value ~= condition.value end
    if operator == "truthy" then return not not value end
    if operator == "falsy" then return not value end
    if operator == "oneOf" then
        for _, candidate in ipairs(condition.values or {}) do if value == candidate then return true end end
        return false
    end
    return nil
end

local function EvaluateInternal(state, key, context)
    local cache = {}
    local current, currentKnown, currentError = ReadValue(state, key, context, cache)
    local result = {
        key = key,
        value = current,
        valueKnown = currentKnown,
        valueError = currentError,
        enabled = true,
        visible = true,
        available = true,
        requirementsMet = true,
        effective = true,
        blockers = {},
        unknownConditions = {},
        inheritedFrom = {},
        activeOverrides = {},
        activeConflicts = {},
    }

    for _, edge in ipairs(state.outgoing[key] or {}) do
        if DEPENDENCY_KINDS[edge.kind] then
            local value, known, readError = ReadValue(state, edge.to, context, cache)
            local matches = ConditionMatches(value, known, edge.condition)
            if matches == false then
                local blocker = ShallowCopy(edge)
                blocker.actualValue = value
                result.blockers[#result.blockers + 1] = blocker
                if edge.kind == "enablement" then result.enabled = false end
                if edge.kind == "visibility" then result.visible = false end
                if edge.kind == "availability" then result.available = false end
                if edge.kind == "requires" then result.requirementsMet = false end
            elseif matches == nil then
                result.unknownConditions[#result.unknownConditions + 1] = {
                    key = edge.to,
                    kind = edge.kind,
                    error = readError,
                }
            end
        elseif edge.kind == "inheritance" then
            local gateValue, gateKnown = ReadValue(state, edge.gateKey, context, cache)
            if ConditionMatches(gateValue, gateKnown, edge.gateCondition) == true then
                local inherited = ShallowCopy(edge)
                inherited.gateValue = gateValue
                result.inheritedFrom[#result.inheritedFrom + 1] = inherited
            end
        elseif edge.kind == "override" then
            local value, known = ReadValue(state, edge.to, context, cache)
            if ConditionMatches(value, known, edge.condition) == true then
                result.activeOverrides[#result.activeOverrides + 1] = ShallowCopy(edge)
            end
        elseif edge.kind == "conflict" then
            local ownActive = currentKnown and current == true
            local otherValue, otherKnown = ReadValue(state, edge.to, context, cache)
            if ownActive and ConditionMatches(otherValue, otherKnown, edge.condition) == true then
                local conflict = ShallowCopy(edge)
                conflict.actualValue = otherValue
                result.activeConflicts[#result.activeConflicts + 1] = conflict
            end
        end
    end
    result.effective = result.enabled and result.available and result.requirementsMet
    return result
end

function G.Evaluate(key, context)
    key = type(key) == "table" and key.key or key
    key = tostring(key or "")
    local state, readyError = EnsureBuilt(key)
    if not state then return nil, readyError end
    if not state.settingsByKey[key] then return nil, "unknown setting: " .. key end
    return EvaluateInternal(state, key, context)
end

local function DisplayValue(value, known)
    if not known then return "unknown" end
    if value == true then return "on" end
    if value == false then return "off" end
    if type(value) == "table" then return "a configured value" end
    return tostring(value)
end

local function SettingLabel(state, key)
    local setting = state.settingsByKey[key]
    return tostring(setting and setting.label or key)
end

local function BuildExplanation(state, key, context, diagnostic)
    local setting = state.settingsByKey[key]
    local evaluation = EvaluateInternal(state, key, context)
    local dependencies = CopyArray(state.outgoing[key])
    local dependents = CopyArray(state.incoming[key])
    table.sort(dependencies, EdgeSort)
    table.sort(dependents, EdgeSort)
    local sentences = {
        SettingLabel(state, key) .. " is currently " .. DisplayValue(evaluation.value, evaluation.valueKnown) .. ".",
    }

    if #evaluation.blockers > 0 then
        local labels = {}
        for _, blocker in ipairs(evaluation.blockers) do labels[#labels + 1] = SettingLabel(state, blocker.to) end
        sentences[#sentences + 1] = "It is not fully effective right now because " .. table.concat(labels, ", ") .. " does not meet its required state."
    elseif evaluation.effective then
        sentences[#sentences + 1] = "Its runtime prerequisites are currently satisfied."
    end
    if evaluation.visible == false then
        sentences[#sentences + 1] = "Its related component is currently hidden, but the value can still be configured for later."
    end
    if #evaluation.inheritedFrom > 0 then
        local labels = {}
        for _, edge in ipairs(evaluation.inheritedFrom) do labels[#labels + 1] = SettingLabel(state, edge.to) end
        sentences[#sentences + 1] = "The effective value is inherited from " .. table.concat(labels, ", ") .. "."
    elseif #evaluation.activeOverrides > 0 then
        sentences[#sentences + 1] = "A scope override is active, so this value is independent from its shared source."
    end
    if #evaluation.activeConflicts > 0 then
        local labels = {}
        for _, edge in ipairs(evaluation.activeConflicts) do labels[#labels + 1] = SettingLabel(state, edge.to) end
        sentences[#sentences + 1] = "It currently conflicts with " .. table.concat(labels, ", ") .. "."
    end
    if diagnostic and #evaluation.unknownConditions > 0 then
        sentences[#sentences + 1] = "Some prerequisite values could not be read safely, so the diagnosis is incomplete."
    end

    return {
        key = key,
        label = setting.label,
        category = setting.category,
        settingType = setting.type,
        evaluation = evaluation,
        dependencies = dependencies,
        dependents = dependents,
        text = table.concat(sentences, " "),
    }
end

function G.Explain(key, context)
    key = type(key) == "table" and key.key or key
    key = tostring(key or "")
    local state, readyError = EnsureBuilt(key)
    if not state then return nil, readyError end
    if not state.settingsByKey[key] then return nil, "unknown setting: " .. key end
    return BuildExplanation(state, key, context, false)
end

function G.Diagnose(key, context)
    key = type(key) == "table" and key.key or key
    key = tostring(key or "")
    local state, readyError = EnsureBuilt(key)
    if not state then return nil, readyError end
    if not state.settingsByKey[key] then return nil, "unknown setting: " .. key end
    return BuildExplanation(state, key, context, true)
end

local function FindDependencyCycles(state)
    local visiting, visited, cycles = {}, {}, {}
    local path = {}
    local function Visit(key)
        if visiting[key] then
            local cycle = {}
            local include = false
            for i = 1, #path do
                if path[i] == key then include = true end
                if include then cycle[#cycle + 1] = path[i] end
            end
            cycle[#cycle + 1] = key
            cycles[#cycles + 1] = table.concat(cycle, " -> ")
            return
        end
        if visited[key] then return end
        visiting[key], path[#path + 1] = true, key
        for _, edge in ipairs(state.outgoing[key] or {}) do
            if DEPENDENCY_KINDS[edge.kind] then Visit(edge.to) end
        end
        path[#path] = nil
        visiting[key], visited[key] = nil, true
    end
    for _, key in ipairs(SortedKeys(state.settingsByKey)) do Visit(key) end
    table.sort(cycles)
    return cycles
end

function G.Validate()
    local state, readyError = EnsureBuilt(nil, true)
    if not state then return nil, readyError end
    local errors = {}
    local identities = {}
    for _, edge in ipairs(state.edges) do
        if not state.settingsByKey[edge.from] or not state.settingsByKey[edge.to] then
            errors[#errors + 1] = "missing endpoint: " .. tostring(edge.from) .. " -> " .. tostring(edge.to)
        end
        if edge.from == edge.to then errors[#errors + 1] = "self edge: " .. edge.from end
        if not D.relationKinds[edge.kind] then errors[#errors + 1] = "unknown relation kind: " .. tostring(edge.kind) end
        if tostring(edge.evidence or "") == "" then errors[#errors + 1] = "missing evidence: " .. tostring(edge.ruleId) end
        local identity = table.concat({ edge.kind, edge.from, edge.to, tostring(edge.ruleId or "") }, "\031")
        if identities[identity] then errors[#errors + 1] = "duplicate edge: " .. identity end
        identities[identity] = true
    end
    local cycles = FindDependencyCycles(state)
    for _, cycle in ipairs(cycles) do errors[#errors + 1] = "dependency cycle: " .. cycle end
    table.sort(errors)
    return {
        ok = #errors == 0,
        errors = errors,
        cycles = cycles,
        unresolved = CopyArray(state.unresolved),
    }
end

function G.GetCoverageReport()
    local state, readyError = EnsureBuilt(nil, true)
    if not state then return nil, readyError end
    local related = {}
    for key in pairs(state.outgoing) do related[key] = true end
    for key in pairs(state.incoming) do related[key] = true end
    local withoutRelations = {}
    for key in pairs(state.settingsByKey) do
        if not related[key] then withoutRelations[#withoutRelations + 1] = key end
    end
    table.sort(withoutRelations)
    local byKind, ruleHits = {}, {}
    local specificallyRelated = {}
    for _, edge in ipairs(state.edges) do
        if not tostring(edge.ruleId or ""):find("root", 1, true) then
            specificallyRelated[edge.from] = true
            specificallyRelated[edge.to] = true
        end
    end
    local rootOnly = {}
    for key in pairs(related) do
        if not specificallyRelated[key] then rootOnly[#rootOnly + 1] = key end
    end
    table.sort(rootOnly)
    for _, kind in ipairs(SortedKeys(D.relationKinds)) do byKind[kind] = state.byKind[kind] or 0 end
    for _, ruleId in ipairs(SortedKeys(state.ruleHits)) do ruleHits[ruleId] = state.ruleHits[ruleId] end
    local percentage = state.settingCount > 0 and (state.relatedNodeCount * 100 / state.settingCount) or 0
    local specificCount = 0
    for _ in pairs(specificallyRelated) do specificCount = specificCount + 1 end
    local specificPercentage = state.settingCount > 0 and (specificCount * 100 / state.settingCount) or 0
    return {
        schemaVersion = G.schemaVersion,
        buildSerial = G._buildSerial or 0,
        settings = state.settingCount,
        relatedSettings = state.relatedNodeCount,
        settingsWithoutRelations = withoutRelations,
        coveragePercent = percentage,
        specificRelatedSettings = specificCount,
        specificCoveragePercent = specificPercentage,
        rootOnlySettings = rootOnly,
        edges = #state.edges,
        byKind = byKind,
        ruleHits = ruleHits,
        unresolved = CopyArray(state.unresolved),
    }
end

-- Stable Assistant-facing aliases for future Router/Knowledge integration.
A.GetSettingDependencyNode = G.GetNode
A.GetSettingDependencies = G.GetDependencies
A.GetSettingDependents = G.GetDependents
A.EvaluateSettingDependencies = G.Evaluate
A.ExplainSettingDependencies = G.Explain
A.DiagnoseSettingDependencies = G.Diagnose
A.GetSettingDependencyGraphCoverageReport = G.GetCoverageReport
A.ValidateSettingDependencyGraph = G.Validate
