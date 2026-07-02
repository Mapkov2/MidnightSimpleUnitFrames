--- Shell/Menu2/Assistant/MSUF_Assistant.lua
--- Command execution layer for the Menu2 assistant.
---
--- Owns job scheduling, combat deferral, confirmations, choice handling, undo
--- metadata, and the final apply fanout into Menu2/MSUF runtime systems.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local AP = A.RuntimePrivate or {}
A.RuntimePrivate = AP

--- Keep UI mutation and protected-frame work behind the job/combat helpers here.
--- Parser modules should return plans, not directly change SavedVariables.

local Registry = A.Registry

local function Trim(text)
    if A.Trim then return A.Trim(text) end
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function PerfNowMs()
    local timer = type(_G.GetTimePreciseSec) == "function" and _G.GetTimePreciseSec or _G.GetTime
    if type(timer) == "function" then return (tonumber(timer()) or 0) * 1000 end
    return nil
end

local PERF_TRACE_LIMIT = 80
local JOB_BUDGET_MS = 2
local JOB_MAX_STEPS = 4
A.JOB_YIELD = A.JOB_YIELD or {}
if A.allowPerformanceWarmup == nil then A.allowPerformanceWarmup = true end
if A.jobBudgetMs == nil then A.jobBudgetMs = JOB_BUDGET_MS end
if A.jobMaxStepsPerFrame == nil then A.jobMaxStepsPerFrame = JOB_MAX_STEPS end

local function InCombat()
    return ((_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) and true or false
end

function A.IsCombatLocked()
    return InCombat()
end

local afterCombatFrame
local afterCombatPending
local afterCombatOrder

local function ScheduleAfterCombat(key, fn)
    if not InCombat() then
        if type(fn) == "function" then fn() end
        return true
    end
    if type(_G.CreateFrame) ~= "function" then return false end
    afterCombatPending = afterCombatPending or {}
    afterCombatOrder = afterCombatOrder or {}
    key = tostring(key or "MSUF_ASSISTANT_AFTER_COMBAT")
    if afterCombatPending[key] == nil then
        afterCombatOrder[#afterCombatOrder + 1] = key
    end
    afterCombatPending[key] = fn or true

    if not afterCombatFrame then
        afterCombatFrame = _G.CreateFrame("Frame")
        if afterCombatFrame and type(afterCombatFrame.SetScript) == "function" then
            afterCombatFrame:SetScript("OnEvent", function(self, event)
                if event ~= "PLAYER_REGEN_ENABLED" or InCombat() then return end
                if self and type(self.UnregisterEvent) == "function" then
                    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                end
                local pending = afterCombatPending or {}
                local order = afterCombatOrder or {}
                afterCombatPending = {}
                afterCombatOrder = {}
                for i = 1, #order do
                    local callback = pending[order[i]]
                    if type(callback) == "function" then callback() end
                end
                if afterCombatPending and afterCombatOrder and #afterCombatOrder > 0
                    and self and type(self.RegisterEvent) == "function" then
                    self:RegisterEvent("PLAYER_REGEN_ENABLED")
                end
            end)
        end
    end
    if afterCombatFrame and type(afterCombatFrame.RegisterEvent) == "function" then
        afterCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    return true
end

local function ScheduleNextFrame(key, fn)
    if type(fn) ~= "function" then return false end
    if type(_G.MSUF_ScheduleOnce) == "function" then
        _G.MSUF_ScheduleOnce(tostring(key or "MSUF_ASSISTANT"), fn)
        return true
    end
    local scheduler = (MSUF and MSUF.Scheduler) or _G.MSUF_Scheduler
    if scheduler and type(scheduler.RunNextFrame) == "function" then
        scheduler.RunNextFrame(fn)
        return true
    end
    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, fn)
        return true
    end
    fn()
    return false
end

local function PushPerfTrace(sample)
    if type(sample) ~= "table" then return end
    A._perfTrace = A._perfTrace or {}
    A._perfTrace[#A._perfTrace + 1] = sample
    while #A._perfTrace > PERF_TRACE_LIMIT do table.remove(A._perfTrace, 1) end
end

function A.RecordPerfSample(label, startedMs, detail)
    if not startedMs then return nil end
    if InCombat() then return nil end
    local now = PerfNowMs()
    if not now then return nil end
    local elapsed = now - startedMs
    if elapsed < 0 then elapsed = 0 end
    local sample = {
        label = tostring(label or "assistant"),
        detail = tostring(detail or ""),
        ms = elapsed,
    }
    A.lastAssistantPerf = sample
    if elapsed >= 250 and sample.label ~= "assistant.submit.deferred" then A.lastSlowAssistantPerf = sample end
    PushPerfTrace(sample)
    return sample
end

function A.GetLastPerfSample()
    return A.lastAssistantPerf
end

function A.GetLastSlowPerfSample()
    return A.lastSlowAssistantPerf
end

function A.GetPerfTrace(limit)
    local trace = A._perfTrace or {}
    local count = tonumber(limit) or #trace
    if count < 1 then count = #trace end
    local first = math.max(1, #trace - count + 1)
    local out = {}
    for i = first, #trace do out[#out + 1] = trace[i] end
    return out
end

local function FriendlyJobLabel(label)
    label = tostring(label or "")
    if label == "assistant.warmup" then return "preparing answers" end
    if label == "assistant.submit" then return "answering a request" end
    return "Assistant task"
end

function A.GetJobSummary()
    local jobs = A._assistantJobs
    local out = { count = 0, labels = {} }
    if type(jobs) ~= "table" then return out end
    out.count = #jobs
    local limit = math.min(#jobs, 4)
    for i = 1, limit do
        local job = jobs[i]
        out.labels[#out.labels + 1] = FriendlyJobLabel(job and job.label)
    end
    return out
end

local function WarmupReasonLabel(reason)
    reason = tostring(reason or "")
    if reason == "menu-hide" then return "waiting until the menu is open" end
    if reason == "menu-open" then return "waiting until the menu is idle" end
    if reason == "menu-activity" or reason == "select-page" then return "waiting for menu activity to settle" end
    if reason == "combat" then return "waiting until combat ends" end
    if reason:find("^combat:", 1, false) then return "waiting until combat ends" end
    if reason:find("^busy:", 1, false) then return "waiting until the current request finishes" end
    if reason:find("^jobs:", 1, false) then return "finishing current Assistant work" end
    if reason ~= "" then return "warming up" end
    return "waiting to start"
end

function A.PerformanceWarmupStatusText()
    if A._performanceWarmupCompleted == true then
        return "ready"
    end
    if A._performanceWarmupStarted == true then
        local jobs = A._assistantJobs
        if type(jobs) == "table" then
            for i = 1, #jobs do
                if jobs[i] and jobs[i].label == "assistant.warmup" then
                    return "getting ready"
                end
            end
        end
        return "getting ready"
    end
    if A._performanceWarmupSuppressed then
        return WarmupReasonLabel(A._performanceWarmupSuppressed)
    end
    return "waiting to start"
end

local NO_MATCH_RECENT_LIMIT = 80
local NO_MATCH_COUNT_LIMIT = 200
local NO_MATCH_CANDIDATE_ALIAS_LIMIT = 24

--- no-match telemetry is product feedback stored in SavedVariables. It helps
--- tune registry aliases and parser fallbacks without changing the command
--- execution path for successful matches.
local function NoMatchStore(create)
    local global = _G.MSUF_GlobalDB
    if type(global) ~= "table" then
        if not create then return nil end
        global = {}
        ExportPublic("MSUF_GlobalDB", global)
    end
    if type(global.global) ~= "table" then
        if not create then return nil end
        global.global = {}
    end
    local store = global.global.assistantNoMatch
    if type(store) ~= "table" then
        if not create then return nil end
        store = {}
        global.global.assistantNoMatch = store
    end
    store.recent = type(store.recent) == "table" and store.recent or {}
    store.counts = type(store.counts) == "table" and store.counts or {}
    return store
end

local function NormalizeNoMatchText(text)
    text = Trim(text):lower():gsub("%s+", " ")
    if #text > 160 then text = text:sub(1, 160) end
    return text
end

local function NoMatchHasAny(text, words)
    text = " " .. tostring(text or "") .. " "
    for i = 1, #(words or {}) do
        local word = tostring(words[i] or "")
        if word ~= "" and text:find(word, 1, true) then return true end
    end
    return false
end

local function NoMatchHasToken(text, tokens)
    local set = {}
    for i = 1, #(tokens or {}) do
        local token = NormalizeNoMatchText(tokens[i])
        if token ~= "" then set[token] = true end
    end
    for token in NormalizeNoMatchText(text):gmatch("%S+") do
        if set[token] then return true end
    end
    return false
end

local function NoMatchTags(text)
    local tags, seen = {}, {}
    local function add(tag)
        if tag ~= "" and not seen[tag] then
            seen[tag] = true
            tags[#tags + 1] = tag
        end
    end
    if NoMatchHasAny(text, { "aura", "auras", "buff", "buffs", "debuff", "debuffs" }) then add("aura") end
    if NoMatchHasAny(text, { "copy", "same", "import", "export", "profile", "preset" }) then add("action") end
    if NoMatchHasAny(text, { "anchor", "attach", "cooldownmanager", "cooldown manager", "cdm", "essentialcooldown" }) then add("anchor") end
    if NoMatchHasAny(text, { "player", "target", "focus", "pet", "boss", "party", "raid", "mythic" }) then add("scope") end
    if NoMatchHasAny(text, { "x offset", "y offset" })
        or NoMatchHasToken(text, { "move", "left", "right", "up", "down", "width", "height", "size", "scale", "bigger", "smaller", "wider", "narrower", "taller", "shorter", "x", "y" }) then add("geometry") end
    if NoMatchHasAny(text, { "color", "colour", "red", "green", "blue", "class color", "texture", "font", "sound", "icon" }) then add("media") end
    if NoMatchHasAny(text, { "text", "name", "health", "hp", "power", "mana", "energy", "border", "opacity", "alpha" }) then add("setting") end
    if NoMatchHasAny(text, { "where", "help", "explain", "find", "search", "what is", "how" }) then add("knowledge") end
    return tags
end

local function NoMatchOwnerForTags(tags)
    local set = {}
    for i = 1, #(tags or {}) do set[tags[i]] = true end
    if set.aura and set.action then return "aura-action/backend" end
    if set.aura then return "aura-registry/backend" end
    if set.anchor then return "anchor-intent" end
    if set.action then return "action-parser" end
    if set.knowledge then return "knowledge/help" end
    if set.scope and (set.geometry or set.setting or set.media) then return "registry-alias" end
    if set.media then return "media-alias" end
    return "parser-or-help"
end

local function NoMatchTagText(tags)
    return #(tags or {}) > 0 and table.concat(tags, ",") or "uncategorized"
end

local function NoMatchOwnerLabel(owner)
    owner = tostring(owner or "")
    if owner == "aura-action/backend" then return "Aura tasks" end
    if owner == "aura-registry/backend" then return "Aura options" end
    if owner == "anchor-intent" then return "Anchoring" end
    if owner == "action-parser" then return "Tasks and guided steps" end
    if owner == "knowledge/help" then return "Help answers" end
    if owner == "registry-alias" then return "Option wording" end
    if owner == "media-alias" then return "Media names" end
    if owner == "parser-or-help" then return "General wording" end
    return owner ~= "" and owner or "General wording"
end

local function NoMatchAdvice(owner)
    if owner == "aura-action/backend" then return "teach an existing Aura task this wording if MSUF supports it" end
    if owner == "aura-registry/backend" then return "add clearer Aura wording, or explain why MSUF cannot change it" end
    if owner == "anchor-intent" then return "add anchor wording if this points at a real frame" end
    if owner == "action-parser" then return "connect the phrase to a supported task or guided step" end
    if owner == "knowledge/help" then return "add a clearer help answer or search phrase" end
    if owner == "registry-alias" then return "add clearer option wording after confirming the intended option" end
    if owner == "media-alias" then return "check the visible media names and add a friendlier alias" end
    return "review the phrase, then decide whether it should be an option, task, help answer, or protected response"
end

local function NoMatchCandidate(owner)
    if owner == "aura-action/backend" then return "Aura task wording" end
    if owner == "aura-registry/backend" then return "Aura option wording" end
    if owner == "anchor-intent" then return "Anchor wording" end
    if owner == "action-parser" then return "Task or guided step wording" end
    if owner == "knowledge/help" then return "Help answer wording" end
    if owner == "registry-alias" then return "Option wording" end
    if owner == "media-alias" then return "Media name wording" end
    return "General wording"
end

local function NoMatchPriority(count, owner)
    count = tonumber(count) or 0
    if count >= 5 then return "high" end
    if count >= 2 then return "medium" end
    if owner == "aura-action/backend" or owner == "aura-registry/backend" or owner == "anchor-intent" then return "medium" end
    return "low"
end

local NO_MATCH_PRIORITY_WEIGHT = { high = 3, medium = 2, low = 1 }

local function NoMatchEachTag(tagsText, callback)
    tagsText = tostring(tagsText or "")
    if tagsText == "" then tagsText = "uncategorized" end
    local emitted = false
    for tag in tagsText:gmatch("[^,]+") do
        tag = NormalizeNoMatchText(tag)
        if tag ~= "" then
            emitted = true
            callback(tag)
        end
    end
    if not emitted then callback("uncategorized") end
end

local function NoMatchTagsMatch(tagsText, wanted)
    wanted = NormalizeNoMatchText(wanted)
    if wanted == "" then return true end
    local match = false
    NoMatchEachTag(tagsText, function(tag)
        if tag == wanted then match = true end
    end)
    return match
end

local function NoMatchScopeTokens()
    local unitAliases = A.UnitAliases or {}
    if A._noMatchScopeAliasTable == unitAliases and type(A._noMatchScopeTokens) == "table" then
        return A._noMatchScopeTokens
    end
    local scopeTokens = {}
    for _, aliases in pairs(unitAliases) do
        for i = 1, #(aliases or {}) do
            for token in NormalizeNoMatchText(aliases[i]):gmatch("%S+") do scopeTokens[token] = true end
        end
    end
    A._noMatchScopeAliasTable = unitAliases
    A._noMatchScopeTokens = scopeTokens
    return scopeTokens
end

local function NoMatchRegistryCandidateScore(setting, requestSet, requestList)
    if type(setting) ~= "table" or type(requestSet) ~= "table" or type(requestList) ~= "table" then return 0 end
    local parser = A.Parser
    local tokenSet = {}
    local function addTokens(value)
        value = tostring(value or "")
        if value == "" then return end
        if parser and type(parser.MeaningTokens) == "function" then
            local _, tokens = parser.MeaningTokens(value)
            for i = 1, #(tokens or {}) do tokenSet[tokens[i]] = true end
        else
            for token in NormalizeNoMatchText(value):gmatch("%S+") do
                if #token >= 2 and not token:match("^[-+]?%d") then tokenSet[token] = true end
            end
        end
    end
    addTokens(setting.key)
    addTokens(setting.label)
    addTokens(setting.attribute)
    local aliases = setting.aliases or {}
    for i = 1, math.min(#aliases, NO_MATCH_CANDIDATE_ALIAS_LIMIT) do addTokens(aliases[i]) end
    local exactAliases = setting.exactAliases or {}
    for i = 1, math.min(#exactAliases, NO_MATCH_CANDIDATE_ALIAS_LIMIT) do addTokens(exactAliases[i]) end

    local common, meaningful = 0, 0
    local scopeTokens = NoMatchScopeTokens()
    for i = 1, #requestList do
        local token = requestList[i]
        if tokenSet[token] then
            common = common + 1
            if not scopeTokens[token] then meaningful = meaningful + 1 end
        end
    end
    if common == 0 or (meaningful == 0 and common < 2) then return 0 end
    return (common * 100) + (meaningful * 25)
end

local function NoMatchRegistryCandidateSummary(text, limit)
    if InCombat() then return nil end
    local registry = A.Registry or Registry
    local parser = A.Parser
    if not (registry and parser and type(registry.AllSettings) == "function") then return nil end
    if not (type(parser.RegistryCandidateSettings) == "function" and type(parser.MeaningTokens) == "function") then return nil end
    local requestSet, requestList = parser.MeaningTokens(text)
    if not requestList or #requestList == 0 then return nil end

    local settings = registry:AllSettings() or {}
    local candidates = parser.RegistryCandidateSettings(text, settings, false) or {}
    if #candidates == 0 then return nil end
    local scored = {}
    for i = 1, #(candidates or {}) do
        if i % 64 == 0 and A and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local setting = candidates[i]
        local score = NoMatchRegistryCandidateScore(setting, requestSet, requestList)
        if score > 0 then
            scored[#scored + 1] = { setting = setting, score = score }
        end
    end
    if #scored == 0 then return nil end
    table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return tostring(a.setting and a.setting.key or "") < tostring(b.setting and b.setting.key or "")
    end)
    local maxItems = tonumber(limit) or 3
    if maxItems < 1 then maxItems = 3 end
    local parts = {}
    for i = 1, math.min(#scored, maxItems) do
        local setting = scored[i].setting or {}
        parts[#parts + 1] = tostring(setting.key or "?")
            .. " [" .. tostring(setting.type or "?") .. ", score " .. tostring(scored[i].score) .. "]"
    end
    return #parts > 0 and table.concat(parts, "; ") or nil
end

local function NoMatchTopRegistryKey(registryCandidates)
    registryCandidates = tostring(registryCandidates or "")
    if registryCandidates == "" then return nil end
    local key = registryCandidates:match("^([^%s;]+)")
    return key and key ~= "" and key or nil
end

local function NoMatchPhraseRef(index)
    local n = tonumber(index)
    if n and n > 0 then return "phrase #" .. tostring(n) end
    return "the saved phrase"
end

local function NoMatchLearningPlan(entry)
    if type(entry) ~= "table" then return "" end
    local owner = tostring(entry.owner or "parser-or-help")
    local topKey = NoMatchTopRegistryKey(entry.registryCandidates)
    if owner == "registry-alias" then
        if topKey then
            return "check the saved phrase against " .. topKey .. "; add a setting alias or clearer setting wording"
        end
        return "check the saved phrase against setting names; add wording after confirming the intended option"
    end
    if owner == "aura-registry/backend" then
        if topKey then
            return "check the saved Aura phrase against " .. topKey .. "; prefer simple Aura wording first"
        end
        return "check the saved Aura phrase against Aura options and actions; keep a clear answer when MSUF cannot change it"
    end
    if owner == "aura-action/backend" then
        return "connect the saved phrase to an Aura action before adding wording only"
    end
    if owner == "anchor-intent" then
        return "add anchor wording if the saved phrase points at a real frame"
    end
    if owner == "action-parser" then
        return "connect the saved phrase to an existing action or guided step first"
    end
    if owner == "knowledge/help" then
        return "add help or search wording for the saved phrase"
    end
    if owner == "media-alias" then
        return "check visible media names before adding extra wording"
    end
    return "review the saved phrase and decide whether it should be a setting, action, help answer, or protected response"
end

local function NoMatchResolution(entry)
    if InCombat() then return tostring(entry and entry.resolution or "unknown"), tostring(entry and entry.resolvedBy or "") end
    if type(entry) ~= "table" or type(A.Parse) ~= "function" then return "unresolved", "" end
    local text = NormalizeNoMatchText(entry.text or "")
    if text == "" then return "unresolved", "" end
    if A._noMatchResolutionInProgress then return tostring(entry.resolution or "unknown"), tostring(entry.resolvedBy or "") end

    A._noMatchResolutionInProgress = true
    local parsed = A.Parse(text)
    A._noMatchResolutionInProgress = nil
    if type(parsed) ~= "table" then return "unresolved", "" end

    local kind = tostring(parsed.kind or "")
    local status = tostring(parsed.status or "")
    if kind == "" or kind == "empty" or kind == "unknown" or kind == "unsupported" or status == "failed" then
        return "unresolved", kind ~= "" and kind or status
    end
    if kind == "ambiguous" then return "needs-clarification", "ambiguous" end
    if kind == "action" then
        return "resolved", tostring(parsed.action and parsed.action.key or parsed.label or "action")
    end
    if kind == "changes" then
        local change = parsed.changes and parsed.changes[1]
        local setting = change and change.setting
        return "resolved", tostring(setting and setting.key or parsed.label or "changes")
    end
    return "resolved", kind
end

function A.AnalyzeNoMatchText(text)
    local tags = NoMatchTags(NormalizeNoMatchText(text))
    local owner = NoMatchOwnerForTags(tags)
    return {
        owner = owner,
        tags = NoMatchTagText(tags),
        advice = NoMatchAdvice(owner),
        candidate = NoMatchCandidate(owner),
    }
end

local function RefreshNoMatchEntry(entry)
    if type(entry) ~= "table" then return nil end
    local text = NormalizeNoMatchText(entry.text or "")
    if text == "" then return nil end
    local analysis = A.AnalyzeNoMatchText and A.AnalyzeNoMatchText(text) or {}
    entry.text = text
    entry.owner = tostring(entry.owner or analysis.owner or "parser-or-help")
    entry.tags = tostring(entry.tags or analysis.tags or "uncategorized")
    entry.advice = tostring(entry.advice or analysis.advice or NoMatchAdvice(entry.owner))
    entry.candidate = tostring(entry.candidate or analysis.candidate or NoMatchCandidate(entry.owner))
    entry.registryCandidates = entry.registryCandidates or NoMatchRegistryCandidateSummary(text, 3)
    entry.learningPlan = NoMatchLearningPlan(entry)
    entry.priority = NoMatchPriority(entry.count, entry.owner)
    if not entry.resolution then entry.resolution, entry.resolvedBy = "unknown", "" end
    return entry
end

function A.RecordNoMatch(text, result, source)
    if InCombat() then return nil end
    local key = NormalizeNoMatchText(text)
    if key == "" then return nil end
    local store = NoMatchStore(true)
    if not store then return nil end
    local analysis = A.AnalyzeNoMatchText and A.AnalyzeNoMatchText(key) or nil
    local now = type(_G.GetServerTime) == "function" and _G.GetServerTime() or (_G.time and _G.time()) or nil
    local entry = store.counts[key]
    if type(entry) ~= "table" then
        entry = { text = key, count = 0 }
        store.counts[key] = entry
    end
    entry.count = (tonumber(entry.count) or 0) + 1
    entry.lastSeen = now
    entry.source = tostring(source or "assistant")
    entry.status = type(result) == "table" and tostring(result.status or result.result or result.kind or "") or ""
    entry.owner = analysis and analysis.owner or nil
    entry.tags = analysis and analysis.tags or nil
    entry.advice = analysis and analysis.advice or nil
    entry.candidate = analysis and analysis.candidate or nil
    if entry.owner == "registry-alias" or entry.owner == "aura-registry/backend" then
        entry.registryCandidates = NoMatchRegistryCandidateSummary(key, 3)
    else
        entry.registryCandidates = nil
    end
    entry.learningPlan = NoMatchLearningPlan(entry)
    entry.priority = NoMatchPriority(entry.count, entry.owner)
    if entry.owner == "aura-registry/backend" or entry.owner == "aura-action/backend" then
        entry.resolution, entry.resolvedBy = NoMatchResolution(entry)
    else
        entry.resolution, entry.resolvedBy = "unknown", ""
    end
    store.total = (tonumber(store.total) or 0) + 1
    store.recent[#store.recent + 1] = {
        text = key,
        source = entry.source,
        status = entry.status,
        owner = entry.owner,
        tags = entry.tags,
        candidate = entry.candidate,
        registryCandidates = entry.registryCandidates,
        learningPlan = entry.learningPlan,
        advice = entry.advice,
        priority = entry.priority,
        resolution = entry.resolution,
        resolvedBy = entry.resolvedBy,
        count = entry.count,
        seen = now,
    }
    while #store.recent > NO_MATCH_RECENT_LIMIT do table.remove(store.recent, 1) end
    local countKeys = 0
    local lowestKey, lowestCount
    for seenKey, seenEntry in pairs(store.counts) do
        countKeys = countKeys + 1
        local seenCount = tonumber(seenEntry and seenEntry.count) or 0
        if not lowestCount or seenCount < lowestCount then
            lowestKey, lowestCount = seenKey, seenCount
        end
    end
    if countKeys > NO_MATCH_COUNT_LIMIT and lowestKey and lowestKey ~= key then store.counts[lowestKey] = nil end
    A._lastNoMatch = entry
    return entry
end

function A.GetNoMatchReview(limit, ownerFilter, resolutionFilter, priorityFilter, tagFilter)
    local store = NoMatchStore(false)
    if not store then return { total = 0, items = {}, ownerCounts = {}, resolutionCounts = {}, priorityCounts = {}, tagCounts = {} } end
    local ownerWanted = tostring(ownerFilter or ""):lower()
    local resolutionWanted = tostring(resolutionFilter or ""):lower()
    local priorityWanted = tostring(priorityFilter or ""):lower()
    local tagWanted = NormalizeNoMatchText(tagFilter or "")
    local items = {}
    local ownerCounts = {}
    local resolutionCounts = {}
    local priorityCounts = {}
    local tagCounts = {}
    for _, entry in pairs(store.counts or {}) do
        entry = RefreshNoMatchEntry(entry)
        if entry then
            local owner = tostring(entry.owner or "parser-or-help")
            ownerCounts[owner] = (ownerCounts[owner] or 0) + 1
            local resolution = tostring(entry.resolution or "unknown")
            resolutionCounts[resolution] = (resolutionCounts[resolution] or 0) + 1
            local priority = tostring(entry.priority or NoMatchPriority(entry.count, owner) or "low")
            priorityCounts[priority] = (priorityCounts[priority] or 0) + 1
            NoMatchEachTag(entry.tags, function(tag)
                tagCounts[tag] = (tagCounts[tag] or 0) + 1
            end)
            if (ownerWanted == "" or owner:lower() == ownerWanted)
                and (resolutionWanted == "" or resolution:lower() == resolutionWanted)
                and (priorityWanted == "" or priority:lower() == priorityWanted)
                and NoMatchTagsMatch(entry.tags, tagWanted) then
                items[#items + 1] = entry
            end
        end
    end
    table.sort(items, function(a, b)
        local aw = NO_MATCH_PRIORITY_WEIGHT[tostring(a.priority or "low")] or 0
        local bw = NO_MATCH_PRIORITY_WEIGHT[tostring(b.priority or "low")] or 0
        if aw ~= bw then return aw > bw end
        local ac, bc = tonumber(a.count) or 0, tonumber(b.count) or 0
        if ac ~= bc then return ac > bc end
        local ao, bo = tostring(a.owner or ""), tostring(b.owner or "")
        if ao ~= bo then return ao < bo end
        return tostring(a.text or "") < tostring(b.text or "")
    end)
    local maxItems = tonumber(limit) or 20
    if maxItems < 1 then maxItems = 20 end
    while #items > maxItems do table.remove(items) end
    return {
        total = tonumber(store.total) or 0,
        items = items,
        ownerCounts = ownerCounts,
        resolutionCounts = resolutionCounts,
        priorityCounts = priorityCounts,
        tagCounts = tagCounts,
    }
end

local function RefreshNoMatchRecentEntry(entry, counts)
    if type(entry) ~= "table" then return nil end
    local text = NormalizeNoMatchText(entry.text or "")
    if text == "" then return nil end
    entry.text = text
    local aggregate = type(counts) == "table" and counts[text] or nil
    if type(aggregate) == "table" then
        entry.count = aggregate.count
        entry.owner = aggregate.owner or entry.owner
        entry.tags = aggregate.tags or entry.tags
        entry.advice = aggregate.advice or entry.advice
        entry.candidate = aggregate.candidate or entry.candidate
        entry.registryCandidates = aggregate.registryCandidates or entry.registryCandidates
        entry.learningPlan = aggregate.learningPlan or entry.learningPlan
        entry.priority = aggregate.priority or entry.priority
        entry.resolution = aggregate.resolution or entry.resolution
        entry.resolvedBy = aggregate.resolvedBy or entry.resolvedBy
    end
    if not entry.resolution then entry.resolution, entry.resolvedBy = "unknown", "" end
    return entry
end

function A.GetNoMatchTelemetry(limit)
    local store = NoMatchStore(false)
    if not store then return { total = 0, recent = {}, top = {} } end
    local top = {}
    for _, entry in pairs(store.counts or {}) do
        entry = RefreshNoMatchEntry(entry)
        if entry then top[#top + 1] = entry end
    end
    table.sort(top, function(a, b)
        local ac, bc = tonumber(a.count) or 0, tonumber(b.count) or 0
        if ac == bc then return tostring(a.text or "") < tostring(b.text or "") end
        return ac > bc
    end)
    local maxTop = tonumber(limit) or 20
    if maxTop < 1 then maxTop = 20 end
    while #top > maxTop do table.remove(top) end
    local recent = {}
    local source = store.recent or {}
    local first = math.max(1, #source - maxTop + 1)
    for i = first, #source do
        local entry = RefreshNoMatchRecentEntry(source[i], store.counts)
        if entry then recent[#recent + 1] = entry end
    end
    return {
        total = tonumber(store.total) or 0,
        recent = recent,
        top = top,
    }
end

function A.ClearNoMatchTelemetry()
    local store = NoMatchStore(false)
    if not store then return 0 end
    local total = tonumber(store.total) or 0
    store.total = 0
    store.recent = {}
    store.counts = {}
    A._lastNoMatch = nil
    return total
end

local function NoMatchLine(index, entry)
    if type(entry) ~= "table" then return nil end
    local text = tostring(entry.text or "")
    if text == "" then return nil end
    local count = tonumber(entry.count) or 0
    local source = tostring(entry.source or "")
    local status = tostring(entry.status or "")
    local owner = tostring(entry.owner or "")
    local suffix = ""
    if count > 0 then suffix = suffix .. " (seen " .. tostring(count) .. "x)" end
    if source ~= "" then suffix = suffix .. " from " .. source end
    if status ~= "" then suffix = suffix .. ", result " .. status end
    if owner ~= "" then suffix = suffix .. ", area " .. NoMatchOwnerLabel(owner) end
    if tostring(entry.resolution or "") ~= "" then suffix = suffix .. ", result " .. tostring(entry.resolution) end
    return tostring(index) .. ". " .. NoMatchPhraseRef(index) .. suffix
end

local function NoMatchHintLine(index, entry)
    if type(entry) ~= "table" then return nil end
    local text = tostring(entry.text or "")
    if text == "" then return nil end
    local analysis = entry.owner and entry or (A.AnalyzeNoMatchText and A.AnalyzeNoMatchText(text)) or {}
    local owner = tostring(analysis.owner or "parser-or-help")
    local tags = tostring(analysis.tags or "uncategorized")
    local advice = tostring(analysis.advice or NoMatchAdvice(owner))
    local candidate = tostring(analysis.candidate or NoMatchCandidate(owner))
    local registryCandidates = tostring(entry.registryCandidates or NoMatchRegistryCandidateSummary(text, 3) or "")
    entry.registryCandidates = registryCandidates ~= "" and registryCandidates or entry.registryCandidates
    entry.learningPlan = entry.learningPlan or NoMatchLearningPlan(entry)
    if not entry.resolution then entry.resolution, entry.resolvedBy = "unknown", "" end
    local plan = tostring(entry.learningPlan or "")
    local suffix = registryCandidates ~= "" and (" | closest MSUF options: " .. registryCandidates) or ""
    if tostring(entry.resolution or "") ~= "" then suffix = suffix .. " | result: " .. tostring(entry.resolution) end
    if tostring(entry.resolvedBy or "") ~= "" then suffix = suffix .. " | now handled by: " .. tostring(entry.resolvedBy) end
    local planSuffix = plan ~= "" and (" | note: " .. plan) or ""
    return tostring(index) .. ". " .. NoMatchPhraseRef(index) .. " | area: " .. NoMatchOwnerLabel(owner) .. " | topics: " .. tags .. " | best improvement: " .. candidate .. suffix .. " | next step: " .. advice .. planSuffix
end

local function NoMatchWorkItemLine(index, entry)
    if type(entry) ~= "table" then return nil end
    local text = tostring(entry.text or "")
    if text == "" then return nil end
    local owner = tostring(entry.owner or (A.AnalyzeNoMatchText and A.AnalyzeNoMatchText(text).owner) or "parser-or-help")
    local count = tonumber(entry.count) or 0
    local priority = tostring(entry.priority or NoMatchPriority(count, owner))
    local candidate = tostring(entry.candidate or NoMatchCandidate(owner))
    local advice = tostring(entry.advice or NoMatchAdvice(owner))
    local registryCandidates = tostring(entry.registryCandidates or NoMatchRegistryCandidateSummary(text, 3) or "")
    entry.registryCandidates = registryCandidates ~= "" and registryCandidates or entry.registryCandidates
    entry.learningPlan = entry.learningPlan or NoMatchLearningPlan(entry)
    if not entry.resolution then entry.resolution, entry.resolvedBy = "unknown", "" end
    local plan = tostring(entry.learningPlan or "")
    local suffix = registryCandidates ~= "" and (" | closest MSUF options: " .. registryCandidates) or ""
    if tostring(entry.resolution or "") ~= "" then suffix = suffix .. " | result: " .. tostring(entry.resolution) end
    if tostring(entry.resolvedBy or "") ~= "" then suffix = suffix .. " | now handled by: " .. tostring(entry.resolvedBy) end
    local planSuffix = plan ~= "" and (" | note: " .. plan) or ""
    return tostring(index) .. ". [" .. priority .. "] " .. NoMatchPhraseRef(index) .. " (seen " .. tostring(count) .. "x) | best improvement: " .. candidate .. " | area: " .. NoMatchOwnerLabel(owner) .. suffix .. " | next step: " .. advice .. planSuffix
end

local function NoMatchOwnerSummary(ownerCounts)
    local owners = {}
    for owner, count in pairs(ownerCounts or {}) do
        owners[#owners + 1] = { owner = tostring(owner), count = tonumber(count) or 0 }
    end
    table.sort(owners, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.owner < b.owner
    end)
    local parts = {}
    for i = 1, #owners do
        parts[#parts + 1] = NoMatchOwnerLabel(owners[i].owner) .. ": " .. tostring(owners[i].count)
    end
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

local function NoMatchResolutionSummary(resolutionCounts)
    local order = { "resolved", "needs-clarification", "unresolved", "unknown" }
    local parts = {}
    local seen = {}
    for i = 1, #order do
        local key = order[i]
        seen[key] = true
        if tonumber(resolutionCounts and resolutionCounts[key]) then
            parts[#parts + 1] = key .. ": " .. tostring(tonumber(resolutionCounts[key]) or 0)
        end
    end
    for key, count in pairs(resolutionCounts or {}) do
        key = tostring(key)
        if not seen[key] then parts[#parts + 1] = key .. ": " .. tostring(tonumber(count) or 0) end
    end
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

local function NoMatchPrioritySummary(priorityCounts)
    local order = { "high", "medium", "low" }
    local parts = {}
    local seen = {}
    for i = 1, #order do
        local key = order[i]
        seen[key] = true
        if tonumber(priorityCounts and priorityCounts[key]) then
            parts[#parts + 1] = key .. ": " .. tostring(tonumber(priorityCounts[key]) or 0)
        end
    end
    for key, count in pairs(priorityCounts or {}) do
        key = tostring(key)
        if not seen[key] then parts[#parts + 1] = key .. ": " .. tostring(tonumber(count) or 0) end
    end
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

local function NoMatchTagSummary(tagCounts)
    local tags = {}
    for tag, count in pairs(tagCounts or {}) do
        tags[#tags + 1] = { tag = tostring(tag), count = tonumber(count) or 0 }
    end
    table.sort(tags, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.tag < b.tag
    end)
    local parts = {}
    for i = 1, #tags do
        parts[#parts + 1] = tags[i].tag .. ": " .. tostring(tags[i].count)
    end
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

local NO_MATCH_FILTER_LABELS = {
    result = { resolved = "resolved", ["needs-clarification"] = "needs clarification", unresolved = "unresolved", unknown = "unknown" },
    priority = { high = "high", medium = "medium", low = "low" },
    topic = { action = "tasks", anchor = "anchoring", aura = "auras", geometry = "geometry", knowledge = "help", media = "media", scope = "frame scope", setting = "settings", uncategorized = "uncategorized" },
}

local function NoMatchFilterLabel(kind, value)
    value = kind == "topic" and NormalizeNoMatchText(value or "") or tostring(value or ""):lower()
    if value == "" then return nil end
    if kind == "owner" then
        local label = NoMatchOwnerLabel(value)
        return label ~= "" and label ~= value and label or "custom area"
    end
    local labels = NO_MATCH_FILTER_LABELS[kind]
    if labels and labels[value] then return labels[value] end
    if kind == "result" then return "custom result" end
    if kind == "priority" then return "custom importance" end
    if kind == "topic" then return "custom topic" end
    return "custom filter"
end

local function NoMatchTSVLine(entry)
    local function clean(value)
        value = tostring(value or "")
        value = value:gsub("[\t\r\n]+", " ")
        return value
    end
    return table.concat({
        clean(entry.priority or "low"),
        tostring(tonumber(entry.count) or 0),
        clean(NoMatchOwnerLabel(entry.owner or "parser-or-help")),
        clean(entry.tags or "uncategorized"),
        clean(entry.candidate or NoMatchCandidate(entry.owner)),
        clean(NoMatchPhraseRef()),
        clean(entry.advice or NoMatchAdvice(entry.owner)),
        clean(entry.registryCandidates or NoMatchRegistryCandidateSummary(entry.text or "", 3) or ""),
        clean(entry.learningPlan or NoMatchLearningPlan(entry)),
        clean(entry.resolution or ""),
        clean(entry.resolvedBy or ""),
    }, "\t")
end

function A.NoMatchWorklistText(limit, ownerFilter, resolutionFilter, priorityFilter, tagFilter)
    local data = A.GetNoMatchReview and A.GetNoMatchReview(limit or 20, ownerFilter, resolutionFilter, priorityFilter, tagFilter) or { total = 0, items = {}, ownerCounts = {}, resolutionCounts = {}, priorityCounts = {}, tagCounts = {} }
    local lines = {}
    lines[#lines + 1] = "Assistant wording to improve:"
    lines[#lines + 1] = "- Total recorded: " .. tostring(tonumber(data.total) or 0)
    lines[#lines + 1] = "- Showing now: " .. tostring(#(data.items or {}))
    lines[#lines + 1] = "- Areas: " .. NoMatchOwnerSummary(data.ownerCounts)
    lines[#lines + 1] = "- Result: " .. NoMatchResolutionSummary(data.resolutionCounts)
    lines[#lines + 1] = "- Importance: " .. NoMatchPrioritySummary(data.priorityCounts)
    lines[#lines + 1] = "- Topics: " .. NoMatchTagSummary(data.tagCounts)
    local ownerLabel = NoMatchFilterLabel("owner", ownerFilter)
    if ownerLabel then
        lines[#lines + 1] = "- Filter: " .. ownerLabel
    end
    local resultLabel = NoMatchFilterLabel("result", resolutionFilter)
    if resultLabel then
        lines[#lines + 1] = "- Result filter: " .. resultLabel
    end
    local priorityLabel = NoMatchFilterLabel("priority", priorityFilter)
    if priorityLabel then
        lines[#lines + 1] = "- Importance filter: " .. priorityLabel
    end
    local tagLabel = NoMatchFilterLabel("topic", tagFilter)
    if tagLabel then
        lines[#lines + 1] = "- Topic filter: " .. tagLabel
    end
    if (tonumber(data.total) or 0) <= 0 or #(data.items or {}) == 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "I haven't missed any Assistant requests yet."
        return table.concat(lines, "\n")
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Phrases to improve:"
    for i = 1, #(data.items or {}) do
        local line = NoMatchWorkItemLine(i, data.items[i])
        if line then lines[#lines + 1] = line end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Improvement plan:"
    for i = 1, #(data.items or {}) do
        local entry = data.items[i]
        if type(entry) == "table" then
            entry.learningPlan = entry.learningPlan or NoMatchLearningPlan(entry)
            lines[#lines + 1] = tostring(i) .. ". " .. tostring(entry.learningPlan or "")
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Start with high and medium phrases first. Help questions should become direct Assistant answers."
    return table.concat(lines, "\n")
end

function A.NoMatchTelemetryText(limit)
    local data = A.GetNoMatchTelemetry(limit or 10)
    local lines = {}
    lines[#lines + 1] = "Assistant wording to improve:"
    lines[#lines + 1] = "- Total recorded: " .. tostring(tonumber(data.total) or 0)
    lines[#lines + 1] = "- Common phrases: " .. tostring(#(data.top or {}))
    lines[#lines + 1] = "- Recent phrases: " .. tostring(#(data.recent or {}))
    if (tonumber(data.total) or 0) <= 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "I haven't missed any Assistant requests yet."
        return table.concat(lines, "\n")
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Common phrases:"
    for i = 1, #(data.top or {}) do
        local line = NoMatchLine(i, data.top[i])
        if line then lines[#lines + 1] = line end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "How to improve them:"
    for i = 1, #(data.top or {}) do
        local line = NoMatchHintLine(i, data.top[i])
        if line then lines[#lines + 1] = line end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Phrases to improve:"
    for i = 1, #(data.top or {}) do
        local line = NoMatchWorkItemLine(i, data.top[i])
        if line then lines[#lines + 1] = line end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Recent phrases:"
    for i = 1, #(data.recent or {}) do
        local entry = data.recent[i]
        if type(entry) == "table" and tostring(entry.text or "") ~= "" then
            local source = tostring(entry.source or "")
            local status = tostring(entry.status or "")
            local owner = tostring(entry.owner or "")
            local priority = tostring(entry.priority or "")
            local registryCandidates = tostring(entry.registryCandidates or "")
            local learningPlan = tostring(entry.learningPlan or "")
            local resolution = tostring(entry.resolution or "")
            local resolvedBy = tostring(entry.resolvedBy or "")
            local suffix = ""
            if tonumber(entry.count) then suffix = suffix .. " (seen " .. tostring(tonumber(entry.count) or 0) .. "x)" end
            if source ~= "" then suffix = suffix .. " from " .. source end
            if status ~= "" then suffix = suffix .. ", result " .. status end
            if owner ~= "" then suffix = suffix .. ", area " .. NoMatchOwnerLabel(owner) end
            if priority ~= "" then suffix = suffix .. ", priority " .. priority end
            if registryCandidates ~= "" then suffix = suffix .. ", closest options " .. registryCandidates end
            if resolution ~= "" then suffix = suffix .. ", result " .. resolution end
            if resolvedBy ~= "" then suffix = suffix .. ", now handled by " .. resolvedBy end
            if learningPlan ~= "" then suffix = suffix .. ", note " .. learningPlan end
            lines[#lines + 1] = tostring(i) .. ". " .. NoMatchPhraseRef(i) .. suffix
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Repeated phrases show where Assistant wording, the tasks I can handle, or help examples can improve."
    return table.concat(lines, "\n")
end

local ScheduleJobPump
local combatResumeFrame

--- Assistant jobs are sliced across frames and paused in combat. The assistant
--- can build large indexes or apply multiple changes, but protected UI work must
--- resume only after PLAYER_REGEN_ENABLED.
local function EnsureCombatResumeFrame()
    if combatResumeFrame then return combatResumeFrame end
    if type(_G.CreateFrame) ~= "function" then return nil end
    combatResumeFrame = _G.CreateFrame("Frame")
    if combatResumeFrame and type(combatResumeFrame.SetScript) == "function" then
        combatResumeFrame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_ENABLED" and A.ResumeCombatDeferredJobs then
                A.ResumeCombatDeferredJobs("PLAYER_REGEN_ENABLED")
            end
        end)
    end
    return combatResumeFrame
end

local function DeferJobPumpForCombat(reason)
    local jobs = A._assistantJobs
    if type(jobs) ~= "table" or #jobs == 0 then return false end
    A._assistantJobsCombatDeferred = true
    A._assistantJobsCombatReason = tostring(reason or "combat")
    local frame = EnsureCombatResumeFrame()
    if frame and type(frame.RegisterEvent) == "function" then
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    return true
end

function A.ResumeCombatDeferredJobs(reason)
    if InCombat() then
        return DeferJobPumpForCombat(reason or "combat")
    end
    if combatResumeFrame and type(combatResumeFrame.UnregisterEvent) == "function" then
        combatResumeFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    A._assistantJobsCombatDeferred = nil
    A._assistantJobsCombatReason = nil
    local jobs = A._assistantJobs
    if type(jobs) == "table" and #jobs > 0 and ScheduleJobPump then
        ScheduleJobPump()
        return true
    end
    return false
end

local function ClearCombatDeferredJobsIfIdle()
    local jobs = A._assistantJobs
    if type(jobs) == "table" and #jobs > 0 then return end
    A._assistantJobsCombatDeferred = nil
    A._assistantJobsCombatReason = nil
    if combatResumeFrame and type(combatResumeFrame.UnregisterEvent) == "function" then
        combatResumeFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

local function JobMatches(job, match)
    if type(match) == "function" then return match(job) == true end
    if match == nil then return true end
    return tostring(job and job.label or "") == tostring(match)
end

function A.CancelJobs(match, reason)
    local jobs = A._assistantJobs
    if type(jobs) ~= "table" or #jobs == 0 then
        ClearCombatDeferredJobsIfIdle()
        return 0
    end
    local removed = 0
    for i = #jobs, 1, -1 do
        local job = jobs[i]
        if JobMatches(job, match) then
            job.cancelled = true
            job.cancelReason = tostring(reason or "cancelled")
            table.remove(jobs, i)
            removed = removed + 1
        end
    end
    if removed > 0 then ClearCombatDeferredJobsIfIdle() end
    return removed
end

function ScheduleJobPump()
    if InCombat() then
        DeferJobPumpForCombat("schedule")
        return
    end
    if A._assistantJobPumpScheduled then return end
    A._assistantJobPumpScheduled = true
    ScheduleNextFrame("MSUF_ASSISTANT_JOB_PUMP", function()
        A._assistantJobPumpScheduled = nil
        if type(A._RunJobPump) == "function" then A._RunJobPump() end
    end)
end

function A._RunJobPump()
    local jobs = A._assistantJobs
    if type(jobs) ~= "table" or #jobs == 0 then return end
    if InCombat() then
        DeferJobPumpForCombat("run")
        return false
    end

    local sliceStart = PerfNowMs()
    local budget = tonumber(A.jobBudgetMs) or JOB_BUDGET_MS
    local maxSteps = tonumber(A.jobMaxStepsPerFrame) or JOB_MAX_STEPS
    if budget <= 0 then budget = JOB_BUDGET_MS end
    if maxSteps <= 0 then maxSteps = JOB_MAX_STEPS end

    local stepsRun = 0
    while #jobs > 0 and stepsRun < maxSteps do
        if InCombat() then
            DeferJobPumpForCombat("run")
            return false
        end
        local job = jobs[1]
        local jobMaxSteps = tonumber(job and job.maxStepsPerFrame) or maxSteps
        if jobMaxSteps <= 0 then jobMaxSteps = maxSteps end
        if stepsRun >= jobMaxSteps then break end
        local jobBudget = tonumber(job and job.budgetMs) or budget
        if jobBudget <= 0 then jobBudget = budget end
        local step = job and job.steps and job.steps[job.index]
        if type(step) ~= "function" then
            table.remove(jobs, 1)
            if type(job.callback) == "function" then job.callback(job.result, job) end
        else
            local stepStart = PerfNowMs()
            local result, stopResult = step(job)
            A.RecordPerfSample("assistant.job.step", stepStart, tostring(job.label or "assistant.job") .. "#" .. tostring(job.index))
            stepsRun = stepsRun + 1
            if result == false then
                table.remove(jobs, 1)
                if stopResult ~= nil then job.result = stopResult end
                if type(job.callback) == "function" then job.callback(job.result, job) end
            elseif result == A.JOB_YIELD then
                break
            else
                if result ~= nil then job.result = result end
                job.index = job.index + 1
            end
        end

        if sliceStart and jobBudget > 0 then
            local now = PerfNowMs()
            if now and (now - sliceStart) >= jobBudget then break end
        end
    end

    A.RecordPerfSample("assistant.job.slice", sliceStart, tostring(stepsRun) .. " step(s)")
    if #jobs > 0 then
        if InCombat() then
            DeferJobPumpForCombat("slice")
        else
            ScheduleJobPump()
        end
    end
end

function A.MaybeYield(force)
    if type(coroutine) ~= "table" or type(coroutine.running) ~= "function" or type(coroutine.yield) ~= "function" then return false end
    local co, isMain = coroutine.running()
    if not co or isMain then return false end
    local started = A._jobYieldStartedMs
    if not started then return false end
    local now = PerfNowMs()
    if not now then return false end
    local budget = tonumber(A._jobYieldBudgetMs) or JOB_BUDGET_MS
    if force or (budget > 0 and (now - started) >= budget) then
        A._jobYieldStartedMs = nil
        coroutine.yield(A.JOB_YIELD)
        A._jobYieldStartedMs = PerfNowMs()
        return true
    end
    return false
end

function A.CoroutineStep(fn)
    if type(fn) ~= "function" then return fn end
    local co
    return function(job)
        if not co then
            co = coroutine.create(function()
                return fn(job)
            end)
        end
        A._jobYieldStartedMs = PerfNowMs()
        A._jobYieldBudgetMs = tonumber(job and job.budgetMs) or tonumber(A.jobBudgetMs) or JOB_BUDGET_MS
        local ok, result = coroutine.resume(co, job)
        A._jobYieldStartedMs = nil
        A._jobYieldBudgetMs = nil
        if not ok then error(result) end
        if coroutine.status(co) ~= "dead" then return A.JOB_YIELD end
        return result
    end
end

function A.StartJob(label, steps, callback, opts)
    if type(steps) ~= "table" or #steps == 0 then
        if type(callback) == "function" then callback(nil) end
        return nil
    end
    opts = type(opts) == "table" and opts or {}
    A._assistantJobs = A._assistantJobs or {}
    A._assistantJobSerial = (tonumber(A._assistantJobSerial) or 0) + 1
    local job = {
        id = A._assistantJobSerial,
        label = tostring(label or "assistant.job"),
        steps = steps,
        index = 1,
        callback = callback,
        budgetMs = tonumber(opts.budgetMs),
        maxStepsPerFrame = tonumber(opts.maxStepsPerFrame),
    }
    A._assistantJobs[#A._assistantJobs + 1] = job
    if opts.runInCombat == true or not InCombat() then
        ScheduleJobPump()
    else
        DeferJobPumpForCombat("start:" .. job.label)
    end
    return job
end

function A.RequestRefreshUI(reason)
    A._refreshReason = tostring(reason or A._refreshReason or "assistant")
    if InCombat() then
        A._refreshAfterCombat = true
        return ScheduleAfterCombat("MSUF_ASSISTANT_REFRESH_UI", function()
            A._refreshAfterCombat = nil
            A.RequestRefreshUI(A._refreshReason or "assistant.after_combat")
        end)
    end
    if A._refreshPending then return true end
    A._refreshPending = true
    ScheduleNextFrame("MSUF_ASSISTANT_REFRESH_UI", function()
        A._refreshPending = nil
        if InCombat() then
            A._refreshAfterCombat = true
            ScheduleAfterCombat("MSUF_ASSISTANT_REFRESH_UI", function()
                A._refreshAfterCombat = nil
                A.RequestRefreshUI(A._refreshReason or "assistant.after_combat")
            end)
            return
        end
        local started = PerfNowMs()
        if type(A.RefreshUI) == "function" then A.RefreshUI() end
        A.RecordPerfSample("assistant.refresh_ui", started, A._refreshReason)
    end)
    return true
end

local function SettingValueLabel(setting, value)
    if value == nil then return "not set" end
    if A.Parser and type(A.Parser.ValueDisplay) == "function" then
        local label = A.Parser.ValueDisplay(setting, value)
        if label ~= nil then return tostring(label) end
    end
    if setting and setting.type == "boolean" then return value and "enabled" or "disabled" end
    if setting and setting.type == "color" and type(value) == "table" then
        if type(value.label) == "string" and value.label ~= "" then
            return type(A.DisplayColorLabel) == "function" and A.DisplayColorLabel(value.label) or value.label
        end
        local r = math.floor(((tonumber(value.r or value[1]) or 0) * 255) + 0.5)
        local g = math.floor(((tonumber(value.g or value[2]) or 0) * 255) + 0.5)
        local b = math.floor(((tonumber(value.b or value[3]) or 0) * 255) + 0.5)
        if r < 0 then r = 0 elseif r > 255 then r = 255 end
        if g < 0 then g = 0 elseif g > 255 then g = 255 end
        if b < 0 then b = 0 elseif b > 255 then b = 255 end
        return string.format("#%02X%02X%02X", r, g, b)
    end
    if setting and (setting.type == "enum" or type(setting.values) == "table") and type(A.HumanizeDisplayKey) == "function" then
        return A.HumanizeDisplayKey(value)
    end
    return tostring(value)
end

local function SettingResponseValueLabel(setting, value, explicitLabel)
    if explicitLabel ~= nil then
        if setting and setting.type == "enum" and value ~= nil then return SettingValueLabel(setting, value) end
        if setting and setting.type == "color" and type(A.DisplayColorLabel) == "function" then
            return A.DisplayColorLabel(explicitLabel)
        end
        return tostring(explicitLabel)
    end
    return SettingValueLabel(setting, value)
end

local function ValuesEqual(setting, oldValue, newValue)
    if setting and type(setting.sameValue) == "function" then
        return setting.sameValue(oldValue, newValue) == true
    end
    if setting and setting.type == "number" then
        local oldNumber = tonumber(oldValue)
        local newNumber = tonumber(newValue)
        if oldNumber ~= nil and newNumber ~= nil then
            return math.abs(oldNumber - newNumber) < 0.0001
        end
    end
    return oldValue == newValue
end

local function AssistantSettingLabel(setting, fallback)
    if type(A.DisplaySettingLabel) == "function" then return A.DisplaySettingLabel(setting) end
    return tostring(setting and setting.label or fallback or "MSUF option")
end

local function AssistantActionLabel(action, fallback)
    if type(A.DisplayActionLabel) == "function" then return A.DisplayActionLabel(action) end
    return tostring(action and action.label or fallback or "Assistant task")
end

local function AssistantSettingValueLabel(setting, valueLabel, fallback)
    if type(A.DisplaySettingValueLabel) == "function" then
        return A.DisplaySettingValueLabel(setting, valueLabel, fallback or "MSUF option")
    end
    return AssistantSettingLabel(setting, fallback or "MSUF option") .. ": " .. tostring(valueLabel or "value")
end

local function LabelSuffixAfterPrefix(label, prefix)
    label = tostring(label or "")
    prefix = tostring(prefix or "")
    if prefix == "" or label:sub(1, #prefix) ~= prefix then return nil end
    local suffix = label:sub(#prefix + 1):gsub("^%s+", "")
    if suffix:match("^:%s*.+$") or suffix:match("^%-%>%s*.+$") then return suffix end
    return nil
end

local function SingleSettingPlanLabel(change, explicitLabel, fallback)
    local setting = change and change.setting
    if not setting then return nil end
    local displayLabel = AssistantSettingLabel(setting, fallback or "Assistant change")
    local rawLabel = tostring(setting.label or "")
    explicitLabel = type(explicitLabel) == "string" and explicitLabel or ""
    if explicitLabel ~= "" and explicitLabel ~= "Assistant selected option" and explicitLabel ~= "Assistant selected options" then
        local suffix = LabelSuffixAfterPrefix(explicitLabel, rawLabel) or LabelSuffixAfterPrefix(explicitLabel, displayLabel)
        if suffix then
            suffix = suffix:gsub("^:%s*", ": ")
            return suffix:sub(1, 1) == ":" and (displayLabel .. suffix) or (displayLabel .. " " .. suffix)
        end
    end
    if change.value ~= nil or change.valueLabel ~= nil then
        return AssistantSettingValueLabel(setting, SettingResponseValueLabel(setting, change.value, change.valueLabel), fallback or "Assistant change")
    end
    return displayLabel
end

local function AssistantPlanLabel(plan, fallback)
    if type(plan) ~= "table" then return tostring(fallback or "Assistant change") end
    if type(plan.changes) == "table" and #plan.changes == 1 then
        local label = SingleSettingPlanLabel(plan.changes[1], plan.label, fallback)
        if label then return label end
    end
    if plan.action then
        local rawActionLabel = plan.action and plan.action.label
        if type(plan.label) ~= "string" or plan.label == "" or plan.label == tostring(rawActionLabel or "") then
            return AssistantActionLabel(plan.action, fallback or "Assistant task")
        end
    end
    if type(plan.label) == "string" and plan.label ~= "" then return plan.label end
    if plan.action then return AssistantActionLabel(plan.action, fallback or "Assistant task") end
    return tostring(fallback or "Assistant change")
end

local function ChoiceDisplayLabel(choice)
    local setting = choice and choice.setting
    if setting and (choice.value ~= nil or choice.valueLabel ~= nil) then
        local valueLabel = SettingResponseValueLabel(setting, choice.value, choice.valueLabel)
        local label = tostring(choice.label or "")
        if label == "" or label:find("%-%>") or label:find(":%s*") or label == tostring(choice.valueLabel or "") or label == tostring(setting.label or "") then
            return AssistantSettingValueLabel(setting, valueLabel, "Option")
        end
    end
    return choice and (choice.label or choice.valueLabel) or nil
end

local function ChoiceText(choices)
    local lines = { (#choices == 1) and "I found a likely match:" or "I found multiple matches:" }
    for i = 1, #choices do
        local choice = choices[i]
        local setting = choice and choice.setting
        local action = choice and choice.action
        local label = ChoiceDisplayLabel(choice)
        if not label or label == "" then
            label = setting and AssistantSettingLabel(setting, "Option") or (action and AssistantActionLabel(action, "Assistant task") or "Option")
        end
        label = tostring(label):gsub("%s*%[%s*%]", "")
        lines[#lines + 1] = tostring(i) .. ". " .. tostring(label)
    end
    lines[#lines + 1] = "0. Cancel and keep it as it is."
    if #choices == 1 then
        local only = choices[1]
        if only and only.diagnosticFix == true then
            lines[#lines + 1] = "Select 1, yes, or 'fix it' to apply the repair. Select 0 or cancel to keep it as it is."
        elseif only and (only.action or only.actionKey) then
            lines[#lines + 1] = "Select 1, yes, or a natural answer like 'open it' to continue. Select 0 or cancel to keep it as it is."
        else
            lines[#lines + 1] = "Select 1, yes, or 'apply it' to make the change. Select 0 or cancel to keep it as it is."
        end
    else
        lines[#lines + 1] = "Select one by number or label. Select 0 or cancel to keep it as it is."
    end
    return table.concat(lines, "\n")
end
A._ChoiceTextForTest = ChoiceText

local function SerializeChoices(choices)
    local out = {}
    for i = 1, #(choices or {}) do
        local choice = choices[i]
        local setting = choice and choice.setting
        local action = choice and choice.action
        local changes
        if choice and type(choice.changes) == "table" then
            changes = {}
            for j = 1, #choice.changes do
                local change = choice.changes[j]
                local changeSetting = change and change.setting
                if changeSetting and changeSetting.key then
                    changes[#changes + 1] = {
                        key = changeSetting.key,
                        value = change.value,
                        relativeDelta = change.relativeDelta,
                        direction = change.direction,
                        valueLabel = change.valueLabel,
                        mediaType = change.mediaType,
                        textArea = change.textArea,
                        textSlot = change.textSlot,
                    }
                end
            end
            if #changes == 0 then changes = nil end
        end
        out[#out + 1] = {
            key = setting and setting.key,
            actionKey = (action and action.key) or choice and choice.actionKey,
            args = choice and choice.args,
            confirmRequired = choice and choice.confirmRequired,
            diagnosticFix = choice and choice.diagnosticFix,
            changes = changes,
            bulkSafe = choice and choice.bulkSafe,
            value = choice and choice.value,
            relativeDelta = choice and choice.relativeDelta,
            direction = choice and choice.direction,
            label = choice and choice.label,
            valueLabel = choice and choice.valueLabel,
            summary = choice and choice.summary,
            mediaType = choice and choice.mediaType,
            textArea = choice and choice.textArea,
            textSlot = choice and choice.textSlot,
        }
    end
    return out
end

local function RehydrateChoices(serialized)
    local choices = {}
    if not (Registry and type(serialized) == "table") then return choices end
    for i = 1, #serialized do
        local item = serialized[i]
        local setting = item and Registry:GetSetting(item.key)
        local changes
        if item and type(item.changes) == "table" then
            changes = {}
            for j = 1, #item.changes do
                local changeItem = item.changes[j]
                local changeSetting = changeItem and Registry:GetSetting(changeItem.key)
                if changeSetting then
                    changes[#changes + 1] = {
                        setting = changeSetting,
                        value = changeItem.value,
                        relativeDelta = changeItem.relativeDelta,
                        direction = changeItem.direction,
                        valueLabel = changeItem.valueLabel,
                        mediaType = changeItem.mediaType,
                        textArea = changeItem.textArea,
                        textSlot = changeItem.textSlot,
                    }
                end
            end
            if #changes == 0 then changes = nil end
        end
        if changes then
            choices[#choices + 1] = {
                changes = changes,
                label = item.label,
                valueLabel = item.valueLabel,
                diagnosticFix = item.diagnosticFix,
                summary = item.summary,
                bulkSafe = item.bulkSafe,
            }
        elseif setting then
            choices[#choices + 1] = {
                setting = setting,
                value = item.value,
                relativeDelta = item.relativeDelta,
                direction = item.direction,
                label = item.label,
                valueLabel = item.valueLabel,
                mediaType = item.mediaType,
                textArea = item.textArea,
                textSlot = item.textSlot,
            }
        elseif item and item.actionKey and type(Registry.GetAction) == "function" then
            local action = Registry:GetAction(item.actionKey)
            if action then
                choices[#choices + 1] = {
                    action = action,
                    actionKey = item.actionKey,
                    args = item.args,
                    confirmRequired = item.confirmRequired,
                    diagnosticFix = item.diagnosticFix,
                    label = item.label,
                    valueLabel = item.valueLabel,
                }
            end
        end
    end
    return choices
end

local function CurrentPendingChoices()
    if type(A.pendingChoices) == "table" and #A.pendingChoices > 0 then return A.pendingChoices end
    local ctx = A.GetContext and A.GetContext()
    if ctx and type(ctx.pendingChoices) == "table" then
        local choices = RehydrateChoices(ctx.pendingChoices)
        if #choices > 0 then
            A.pendingChoices = choices
            return choices
        end
        ctx.pendingChoices = nil
    end
    return nil
end

local function NormalizeResultItem(item)
    if item and item.item then item = item.item end
    if type(item) ~= "table" then return nil end
    local kind = tostring(item.kind or "")
    local key = item.key
    local settingKey = item.settingKey or (item.setting and item.setting.key) or (kind == "setting" and key)
    local actionKey = item.actionKey or (item.action and item.action.key) or ((kind == "action" or kind == "diagnostic") and key or nil)
    local setting = item.setting
    if not setting and settingKey and Registry and type(Registry.GetSetting) == "function" then setting = Registry:GetSetting(settingKey) end
    local action = item.action
    if not action and actionKey and Registry and type(Registry.GetAction) == "function" then action = Registry:GetAction(actionKey) end
    local label = item.label or (setting and AssistantSettingLabel(setting, nil)) or (action and AssistantActionLabel(action, nil))
    if not label or label == "" then label = tostring(key or "Result") end
    return {
        kind = kind ~= "" and kind or (setting and "setting" or action and "action" or "result"),
        key = key,
        settingKey = settingKey,
        actionKey = actionKey,
        setting = setting,
        action = action,
        label = label,
        page = item.page,
        pageLabel = item.pageLabel,
        category = item.category,
        description = item.description,
        answer = item.answer,
        target = item.target,
        controlType = item.controlType,
        canOpen = item.canOpen,
        canExplain = item.canExplain,
    }
end

local function SerializeResults(results)
    local out = {}
    for i = 1, #(results or {}) do
        local item = NormalizeResultItem(results[i])
        if item then
            out[#out + 1] = {
                kind = item.kind,
                key = item.key,
                settingKey = item.settingKey,
                actionKey = item.actionKey,
                label = item.label,
                page = item.page,
                pageLabel = item.pageLabel,
                category = item.category,
                description = item.description,
                answer = item.answer,
                target = item.target,
                controlType = item.controlType,
                canOpen = item.canOpen,
                canExplain = item.canExplain,
            }
        end
    end
    return out
end

local function RehydrateResults(serialized)
    local results = {}
    if type(serialized) ~= "table" then return results end
    for i = 1, #serialized do
        local item = NormalizeResultItem(serialized[i])
        if item then results[#results + 1] = item end
    end
    return results
end

local function SerializeResultSelection(item, index)
    local result = NormalizeResultItem(item)
    if not result then return nil end
    local serialized = SerializeResults({ result })[1]
    if serialized then serialized.index = tonumber(index) end
    return serialized
end

local function RehydrateResultSelection(selection)
    if type(selection) ~= "table" then return nil end
    local item = NormalizeResultItem(selection)
    if not item then return nil end
    item.index = tonumber(selection.index)
    return item
end

local function ClearSelectedPendingResult()
    A.pendingSelectedResult = nil
    local ctx = A.GetContext and A.GetContext()
    if ctx then ctx.pendingSelectedResult = nil end
end

local function SetSelectedPendingResult(item, index)
    local selected = NormalizeResultItem(item)
    if not selected then
        ClearSelectedPendingResult()
        return nil
    end
    selected.index = tonumber(index)
    A.pendingSelectedResult = selected
    local ctx = A.GetContext and A.GetContext()
    if ctx then ctx.pendingSelectedResult = SerializeResultSelection(selected, selected.index) end
    return selected
end

local function CurrentSelectedPendingResult()
    if type(A.pendingSelectedResult) == "table" then return A.pendingSelectedResult end
    local ctx = A.GetContext and A.GetContext()
    if ctx and type(ctx.pendingSelectedResult) == "table" then
        local selected = RehydrateResultSelection(ctx.pendingSelectedResult)
        if selected then
            A.pendingSelectedResult = selected
            return selected
        end
        ctx.pendingSelectedResult = nil
    end
    return nil
end

function A.HasPendingSelectedResult()
    return CurrentSelectedPendingResult() ~= nil
end

local function ClearPendingResults()
    A.pendingResults = nil
    ClearSelectedPendingResult()
    local ctx = A.GetContext and A.GetContext()
    if ctx then ctx.pendingResults = nil end
end

function A.SetPendingResults(results)
    local hydrated = RehydrateResults(results)
    if #hydrated == 0 then
        ClearPendingResults()
        return nil
    end
    ClearSelectedPendingResult()
    A.pendingResults = hydrated
    local ctx = A.GetContext and A.GetContext()
    if ctx then ctx.pendingResults = SerializeResults(hydrated) end
    return hydrated
end

local function CurrentPendingResults()
    if type(A.pendingResults) == "table" and #A.pendingResults > 0 then return A.pendingResults end
    local ctx = A.GetContext and A.GetContext()
    if ctx and type(ctx.pendingResults) == "table" then
        local results = RehydrateResults(ctx.pendingResults)
        if #results > 0 then
            A.pendingResults = results
            return results
        end
        ctx.pendingResults = nil
    end
    return nil
end

--- Plans are declarative until this section. Confirmation and combat checks
--- happen before ExecuteChanges/ExecuteAction mutates SavedVariables or live UI.
local function AnyCombatUnsafe(plan)
    if type(plan) ~= "table" then return false end
    if plan.kind == "action" then
        return not (plan.action and plan.action.combatSafe == true)
    end
    if type(plan.changes) == "table" then
        for i = 1, #plan.changes do
            local setting = plan.changes[i].setting
            if not (setting and setting.combatSafe == true) then return true end
        end
    end
    return false
end

local function AnySettingFlag(plan, flag)
    if type(plan) ~= "table" or type(plan.changes) ~= "table" then return false end
    for i = 1, #plan.changes do
        local setting = plan.changes[i].setting
        if setting and setting[flag] == true then return true end
    end
    return false
end

local function PlanNeedsConfirmation(plan)
    if type(plan) ~= "table" then return false end
    if plan.confirmRequired == true then return true end
    if plan.kind == "action" and plan.action and plan.action.confirmRequired == true then return true end
    if AnySettingFlag(plan, "confirmRequired") then return true end
    if type(plan.changes) == "table" and #plan.changes >= 6 and plan.bulkSafe ~= true then return true end
    return false
end

local function ConfirmationText(plan)
    if type(plan) == "table" and type(plan.confirmText) == "string" and plan.confirmText ~= "" then
        return plan.confirmText
    end
    local label = AssistantPlanLabel(plan, "this action")
    return "I can apply " .. label .. ". Answer with 'yes', 'do it', 'apply', or 'cancel'."
end

local function NormalizeReply(text)
    return A.Normalize and A.Normalize(text) or Trim(text):lower()
end

local function ReplyHasPhrase(text, phrase)
    text = " " .. NormalizeReply(text) .. " "
    phrase = NormalizeReply(phrase)
    if phrase == "" then return false end
    return text:find(" " .. phrase .. " ", 1, true) ~= nil
end

local function IsYes(text)
    text = NormalizeReply(text)
    return text == "yes" or text == "y" or text == "ja" or text == "confirm" or text == "apply"
end

local function IsCancel(text)
    text = NormalizeReply(text)
    return text == "cancel" or text == "no" or text == "nein" or text == "abort" or text == "stop"
end

local function IsSimpleExplainIntent(text)
    return ReplyHasPhrase(text, "simpler")
        or ReplyHasPhrase(text, "more simple")
        or ReplyHasPhrase(text, "simple explanation")
        or ReplyHasPhrase(text, "in simple words")
        or ReplyHasPhrase(text, "plain english")
        or ReplyHasPhrase(text, "plain language")
        or ReplyHasPhrase(text, "i dont understand")
        or ReplyHasPhrase(text, "i do not understand")
        or ReplyHasPhrase(text, "what does that mean")
        or ReplyHasPhrase(text, "what does it mean")
end

local function IsValueQuestionIntent(text)
    return ReplyHasPhrase(text, "current value")
        or ReplyHasPhrase(text, "value of")
        or ReplyHasPhrase(text, "value now")
        or ReplyHasPhrase(text, "what is it set to")
        or ReplyHasPhrase(text, "what is this set to")
        or ReplyHasPhrase(text, "what is that set to")
        or ReplyHasPhrase(text, "what is the result set to")
        or ReplyHasPhrase(text, "what is the option set to")
        or ReplyHasPhrase(text, "what is it now")
        or ReplyHasPhrase(text, "what is this now")
        or ReplyHasPhrase(text, "what is that now")
        or ReplyHasPhrase(text, "what is the value")
        or ReplyHasPhrase(text, "what value is it")
        or ReplyHasPhrase(text, "is it on")
        or ReplyHasPhrase(text, "is it off")
        or ReplyHasPhrase(text, "is it enabled")
        or ReplyHasPhrase(text, "is it disabled")
end

local function IsWhyReasonIntent(text)
    local normalized = NormalizeReply(text)
    if normalized:match("^why%s+") then
        for _, word in ipairs({
            "first", "second", "third", "fourth", "fifth",
        "sixth", "seventh", "eighth", "ninth", "tenth",
        "one", "two", "three", "four", "five",
        "six", "seven", "eight", "nine", "ten",
        "1st", "2nd", "3rd", "4th", "5th",
        "6th", "7th", "8th", "9th", "10th",
        "top", "top one", "top result", "top option",
        "last", "last one", "last result", "last option",
        "next", "next one", "next result", "next option",
        "previous", "previous one", "previous result", "previous option", "prev", "prior",
        "second last", "second to last", "second from bottom", "next to last", "penultimate",
        "2nd last", "2nd to last", "2nd from bottom",
        "bottom", "bottom one", "bottom result", "bottom option",
        "final", "final one", "final result", "final option",
    }) do
        local prefix = "why " .. word
        if normalized == prefix or normalized:sub(1, #prefix + 1) == prefix .. " " then return true end
            prefix = "why the " .. word
            if normalized == prefix or normalized:sub(1, #prefix + 1) == prefix .. " " then return true end
        end
    end
    for _, word in ipairs({
        "first", "second", "third", "fourth", "fifth",
        "sixth", "seventh", "eighth", "ninth", "tenth",
        "one", "two", "three", "four", "five",
        "six", "seven", "eight", "nine", "ten",
        "1st", "2nd", "3rd", "4th", "5th",
        "6th", "7th", "8th", "9th", "10th",
        "top", "top one", "top result", "top option",
        "last", "last one", "last result", "last option",
        "next", "next one", "next result", "next option",
        "previous", "previous one", "previous result", "previous option", "prev", "prior",
        "second last", "second to last", "second from bottom", "next to last", "penultimate",
        "2nd last", "2nd to last", "2nd from bottom",
        "bottom", "bottom one", "bottom result", "bottom option",
        "final", "final one", "final result", "final option",
    }) do
        if normalized == "what is " .. word .. " for"
            or normalized == "what is the " .. word .. " for"
            or normalized == "what does " .. word .. " help with"
            or normalized == "what does the " .. word .. " help with" then
            return true
        end
    end
    return ReplyHasPhrase(text, "why this")
        or ReplyHasPhrase(text, "why that")
        or ReplyHasPhrase(text, "why it")
        or ReplyHasPhrase(text, "why result")
        or ReplyHasPhrase(text, "why option")
        or ReplyHasPhrase(text, "why choice")
        or ReplyHasPhrase(text, "why setting")
        or ReplyHasPhrase(text, "why this option")
        or ReplyHasPhrase(text, "why that option")
        or ReplyHasPhrase(text, "why this result")
        or ReplyHasPhrase(text, "why that result")
        or ReplyHasPhrase(text, "why would i use it")
        or ReplyHasPhrase(text, "why would i use this")
        or ReplyHasPhrase(text, "why would i use that")
        or ReplyHasPhrase(text, "why should i use it")
        or ReplyHasPhrase(text, "why should i use this")
        or ReplyHasPhrase(text, "why should i use that")
        or ReplyHasPhrase(text, "what is it for")
        or ReplyHasPhrase(text, "what is this for")
        or ReplyHasPhrase(text, "what is that for")
        or ReplyHasPhrase(text, "what does it help with")
        or ReplyHasPhrase(text, "what does this help with")
        or ReplyHasPhrase(text, "what does that help with")
        or ReplyHasPhrase(text, "purpose")
        or ReplyHasPhrase(text, "reason")
end

local function CompactExplanationText(text, limit)
    text = tostring(text or ""):gsub("[%r\n]+", " "):gsub("%s+", " ")
    text = Trim(text)
    limit = tonumber(limit) or 180
    if text == "" then return nil end
    if #text > limit then text = text:sub(1, limit - 3) .. "..." end
    return text
end

local function IsChoiceAbort(text)
    if IsCancel(text) then return true end
    local normalized = NormalizeReply(text)
    local withoutPrefix = normalized:gsub("^option%s+", ""):gsub("^choice%s+", ""):gsub("^select%s+", ""):gsub("^pick%s+", "")
    if normalized == "0" or withoutPrefix == "0" then return true end
    if normalized == "none" or withoutPrefix == "none" then return true end
    if normalized == "nothing" or withoutPrefix == "nothing" then return true end
    if normalized == "do nothing" or withoutPrefix == "do nothing" then return true end
    local phrases = {
        "nope", "never mind", "nevermind", "forget it", "leave it", "skip it",
        "cancel that", "abort that", "stop that", "stop it", "not now",
        "i dont want", "i do not want", "dont want", "do not want",
        "i dont want to change", "i do not want to change", "dont change", "do not change",
        "not that", "not this", "wrong choice", "wrong list", "none of these", "none of them",
        "abbrechen", "abbruch", "nein danke", "nicht aendern", "nichts aendern",
        "ich will nicht", "will ich nicht", "doch nicht", "vergiss es", "lass es",
    }
    for i = 1, #phrases do
        if ReplyHasPhrase(text, phrases[i]) then return true end
    end
    return false
end

local function IsSingleChoiceApply(text)
    local normalized = NormalizeReply(text)
    if normalized == "1" then return true end
    local phrases = {
        "yes", "y", "yeah", "yep", "yup", "ok", "okay", "sure", "sounds good",
        "yes please", "go ahead", "please do",
        "apply", "apply it", "apply that", "do it", "do that", "fix it", "fix that",
        "use it", "use that", "take it", "take that", "yes do it", "yes apply it",
        "ok do it", "okay do it", "sure do it", "open it", "open that", "show it", "show me",
        "ja", "ja bitte", "mach das", "mach es", "anwenden", "uebernehmen", "ja mach das", "ja anwenden",
        "oeffne es", "oeffne das", "zeig es", "zeig mir das",
    }
    for i = 1, #phrases do
        if ReplyHasPhrase(text, phrases[i]) or normalized == NormalizeReply(phrases[i]) then return true end
    end
    return false
end

local function IsNaturalFixApply(text)
    local normalized = NormalizeReply(text)
    local phrases = {
        "fix it", "fix that", "repair it", "repair that", "apply fix", "apply the fix",
        "do the fix", "use the fix", "do it", "do that", "mach das", "mach es",
        "reparieren", "beheben", "fix anwenden",
    }
    for i = 1, #phrases do
        if ReplyHasPhrase(text, phrases[i]) or normalized == NormalizeReply(phrases[i]) then return true end
    end
    return false
end

local function IsConfirmationApply(text)
    if IsYes(text) then return true end
    local normalized = NormalizeReply(text)
    local phrases = {
        "yes do it", "yes apply it", "yes please", "yep", "yup", "sure",
        "go ahead", "please do", "do it", "do that", "apply it", "apply that",
        "run it", "confirm it", "ok do it", "okay do it", "ok apply it", "okay apply it",
        "ja bitte", "ja mach das", "mach das", "mach es", "mach weiter", "leg los",
        "anwenden", "uebernehmen", "bestaetigen",
    }
    for i = 1, #phrases do
        if ReplyHasPhrase(text, phrases[i]) or normalized == NormalizeReply(phrases[i]) then return true end
    end
    return false
end

local function LooksLikeUndoRedoCommand(text)
    local normalized = NormalizeReply(text)
    if normalized == "undo" or normalized == "redo" then return true end
    local phrases = {
        "undo", "undo that", "undo this", "undo last", "undo last change",
        "redo", "redo that", "redo this", "redo last", "reapply",
        "revert", "revert that", "revert this", "take it back",
        "rueckgaengig", "rueckgaengig machen", "wiederholen", "erneut anwenden",
    }
    for i = 1, #phrases do
        if ReplyHasPhrase(text, phrases[i]) or normalized == NormalizeReply(phrases[i]) then return true end
    end
    return false
end

local function LooksLikeFreshCommand(text)
    local phrases = {
        "change", "set", "turn", "enable", "disable", "show", "hide", "open", "search",
        "help", "diagnose", "move", "copy", "reset", "import", "export", "rename",
        "create", "delete", "profile", "edit mode", "how", "what", "where", "why",
        "make", "increase", "decrease", "switch",
        "aendere", "setze", "schalte", "zeige", "verstecke", "oeffne", "suche",
        "hilfe", "diagnose", "verschiebe", "kopiere", "zuruecksetzen", "profil",
        "wie", "was", "wo", "warum",
    }
    for i = 1, #phrases do
        if ReplyHasPhrase(text, phrases[i]) then return true end
    end
    return false
end

local ClearPendingChoices
local ExecuteChoice

ClearPendingChoices = function()
    A.pendingChoices = nil
    local ctx = A.GetContext and A.GetContext()
    if ctx then ctx.pendingChoices = nil end
end

function A.SetPendingChoices(choices)
    if type(choices) ~= "table" or #choices == 0 then
        ClearPendingChoices()
        return nil
    end
    A.pendingChoices = choices
    local ctx = A.GetContext and A.GetContext()
    if ctx then ctx.pendingChoices = SerializeChoices(A.pendingChoices) end
    return ChoiceText(A.pendingChoices)
end

local function FindChoice(text, choices)
    local normalized = NormalizeReply(text)
    local n = tonumber(normalized)
    if n and choices[n] then return choices[n] end

    local withPrefix = normalized
        :gsub("^run%s+", "")
        :gsub("^execute%s+", "")
        :gsub("^apply%s+", "")
        :gsub("^use%s+", "")
        :gsub("^option%s+", "")
        :gsub("^choice%s+", "")
        :gsub("^result%s+", "")
        :gsub("^select%s+", "")
        :gsub("^pick%s+", "")
    n = tonumber(withPrefix)
    if n and choices[n] then return choices[n] end

    n = tonumber(normalized:match("^(%d+)[a-z]+$"))
    if n and choices[n] then return choices[n] end

    local wordToNumber = {
        ["first"] = 1, ["second"] = 2, ["third"] = 3, ["fourth"] = 4, ["fifth"] = 5,
        ["sixth"] = 6, ["seventh"] = 7, ["eighth"] = 8, ["ninth"] = 9, ["tenth"] = 10,
    }
    local choiceIndex = wordToNumber[normalized] or wordToNumber[withPrefix]
    if choiceIndex and choices[choiceIndex] then return choices[choiceIndex] end

    local units = A.Parse and A.Parse("show " .. normalized .. " name")
    local wantedUnit
    if units and type(units.changes) == "table" and units.changes[1] and units.changes[1].setting then
        wantedUnit = units.changes[1].setting.unit
    end
    if not wantedUnit then
        local aliases = A.UnitAliases or {}
        for unit, list in pairs(aliases) do
            for i = 1, #list do
                if normalized == A.Normalize(list[i]) then wantedUnit = unit; break end
            end
            if wantedUnit then break end
        end
    end
    if wantedUnit then
        for i = 1, #choices do
            local setting = choices[i].setting
            if setting and setting.unit == wantedUnit then return choices[i] end
        end
    end
    if #normalized >= 2 then
        for i = 1, #choices do
            local choice = choices[i]
            local setting = choice and choice.setting
            local action = choice and choice.action
            local label = NormalizeReply(choice and (choice.label or choice.valueLabel) or "")
            local valueLabel = NormalizeReply(choice and choice.valueLabel or "")
            local settingLabel = NormalizeReply(setting and setting.label or "")
            local actionLabel = NormalizeReply(action and action.label or "")
            if label ~= "" and (label == normalized or label:find(normalized, 1, true)) then return choice end
            if valueLabel ~= "" and (valueLabel == normalized or valueLabel:find(normalized, 1, true)) then return choice end
            if settingLabel ~= "" and settingLabel == normalized then return choice end
            if actionLabel ~= "" and actionLabel == normalized then return choice end
        end
    end
    return nil
end

local PENDING_PAGE_LABEL_OVERRIDES = {
    home = "Dashboard",
    profiles = "Profiles",
    gameplay = "Gameplay",
    classpower = "Class Resources",
    modules = "Modules",
    search = "Search",
    opt_castbar = "Cast Bars",
    opt_bars = "Bars",
    opt_colors = "Colors",
    opt_fonts = "Fonts",
    opt_misc = "Miscellaneous",
    gf_layout = "Group Layout",
    gf_bars = "Group Health & Text",
    gf_indicators = "Group Status & Indicators",
    gf_auras = "Group Auras",
    auras3 = "Auras",
    auras3_buffs = "Aura Buffs",
    auras3_debuffs = "Aura Debuffs",
    auras3_filters = "Aura Filters",
    auras3_styling = "Aura Style",
    uf_player = "Player",
    uf_target = "Target",
    uf_focus = "Focus",
    uf_pet = "Pet",
    uf_boss = "Boss",
    uf_targettarget = "Target of Target",
    uf_focustarget = "Focus Target",
}

local function PendingPageLabel(page)
    page = tostring(page or "")
    if page == "" then return nil end
    if A and type(A.DisplayPageLabel) == "function" then return A.DisplayPageLabel(page, "MSUF page") end
    if PENDING_PAGE_LABEL_OVERRIDES[page] then return PENDING_PAGE_LABEL_OVERRIDES[page] end
    return "MSUF page"
end

local function PendingResultPageLabel(item)
    if type(item) ~= "table" then return nil end
    if item.page and tostring(item.page) ~= "" then return PendingPageLabel(item.page) end
    if item.kind == "page" and item.key and tostring(item.key) ~= "" then return PendingPageLabel(item.key) end
    if item.action or item.actionKey or item.kind == "action" or item.kind == "diagnostic" then return "Assistant" end
    return nil
end

local PENDING_GROUP_LAYOUT_ATTRS = {
    enabled = true,
    showPlayer = true,
    showSolo = true,
    clickCast = true,
    clickCastEnabled = true,
    blizzardFallbackMode = true,
    hideInClientScene = true,
    hideOfflineEnabled = true,
    hideOfflineInCombat = true,
    hideOfflineDelay = true,
    smoothFill = true,
    reverseFill = true,
    groupBackdropColor = true,
    bgColor = true,
    width = true,
    height = true,
    offsetX = true,
    offsetY = true,
    spacing = true,
    unitsPerColumn = true,
    maxColumns = true,
    preserveRaidGroups = true,
    growth = true,
    sortMode = true,
    sortByRole = true,
    playerFirstInRole = true,
    roleOrder = true,
    frameScaleMode = true,
    frameScaleEnabled = true,
    frameScaleManual = true,
    scaleAt10 = true,
    scaleAt20 = true,
    scaleAt25 = true,
    scaleOver25 = true,
    anchorToFrame = true,
    customAnchorFrame = true,
    anchorPoint = true,
}

local PENDING_GROUP_INDICATOR_KEY_PARTS = {
    "roleicon", "leadericon", "assisticon", "raidmarker", "readycheck",
    "summonicon", "summonanchor", "summonx", "summony", "summonlayer",
    "resurrecticon", "resurrectanchor", "resurrectx", "resurrecty", "resurrectlayer",
    "phaseicon", "pvpicon", "warmode", "threaticon", "aggroicon",
    "spellindicator", "spellindicators", "cornerindicator", "cornerindicators",
    "targetedspell", "targetedspells",
}

local function PendingGroupSettingPage(setting)
    local attr = tostring(setting and setting.attribute or "")
    local key = NormalizeReply(setting and setting.key or ""):gsub("%s+", "")
    local attrNorm = NormalizeReply(attr):gsub("%s+", "")
    for i = 1, #PENDING_GROUP_INDICATOR_KEY_PARTS do
        local part = PENDING_GROUP_INDICATOR_KEY_PARTS[i]
        if attrNorm:find(part, 1, true) or key:find(part, 1, true) then return "gf_indicators" end
    end
    if PENDING_GROUP_LAYOUT_ATTRS[attr] then return "gf_layout" end
    local suffix = tostring(setting and setting.key or ""):match("%.([^%.]+)$")
    if suffix and PENDING_GROUP_LAYOUT_ATTRS[suffix] then return "gf_layout" end
    return "gf_bars"
end

local function PendingSettingPage(setting)
    if type(setting) ~= "table" then return nil end
    if tostring(setting.frameType or "") == "group" then return PendingGroupSettingPage(setting) end
    local unit = tostring(setting.unit or "")
    if unit ~= "" then
        if unit == "targettarget" then return "uf_targettarget" end
        if unit == "focustarget" then return "uf_focustarget" end
        return "uf_" .. unit
    end
    local frameType = tostring(setting.frameType or "")
    if frameType == "castbar" then return "opt_castbar" end
    if frameType == "fonts" then return "opt_fonts" end
    if frameType == "bars" or frameType == "globalBars" then return "opt_bars" end
    if frameType == "classPower" then return "classpower" end
    if frameType == "gameplay" then return "gameplay" end
    if frameType == "modules" then return "modules" end
    if frameType == "groupAura" then return "gf_auras" end
    if frameType == "aura" then return "auras3_styling" end
    local category = NormalizeReply(setting.category or "")
    if category:find("castbar", 1, true) or category:find("cast bar", 1, true) then return "opt_castbar" end
    if category:find("font", 1, true) then return "opt_fonts" end
    if category:find("color", 1, true) or category:find("colour", 1, true) then return "opt_colors" end
    if category:find("profile", 1, true) then return "profiles" end
    return nil
end

local function PendingChoicePrimarySetting(choice)
    if choice and choice.setting then return choice.setting, choice end
    if choice and type(choice.changes) == "table" then
        for i = 1, #choice.changes do
            local change = choice.changes[i]
            if change and change.setting then return change.setting, change end
        end
    end
    return nil, nil
end

local function PendingChoicePage(choice)
    if type(choice) ~= "table" then return nil end
    if (choice.action or choice.actionKey) and type(choice.args) == "table" and type(choice.args.page) == "string" then
        return choice.args.page, nil
    end
    local setting = PendingChoicePrimarySetting(choice)
    return PendingSettingPage(setting)
end

local function PendingChoiceIndex(text, choices)
    local normalized = NormalizeReply(text)
    local n = tonumber(normalized)
    if n and choices[n] then return n end
    n = tonumber(normalized:match("option%s+(%d+)"))
        or tonumber(normalized:match("choice%s+(%d+)"))
        or tonumber(normalized:match("result%s+(%d+)"))
        or tonumber(normalized:match("number%s+(%d+)"))
        or tonumber(normalized:match("#(%d+)"))
    if n and choices[n] then return n end
    local wordToNumber = {
        first = 1, second = 2, third = 3, fourth = 4, fifth = 5,
        sixth = 6, seventh = 7, eighth = 8, ninth = 9, tenth = 10,
    }
    for word, index in pairs(wordToNumber) do
        if (normalized == word or ReplyHasPhrase(text, word)) and choices[index] then return index end
    end
    if #choices == 1 and (
        ReplyHasPhrase(text, "that")
        or ReplyHasPhrase(text, "this")
        or ReplyHasPhrase(text, "it")
        or ReplyHasPhrase(text, "the fix")
        or ReplyHasPhrase(text, "the option")
        or ReplyHasPhrase(text, "the choice")
        or ReplyHasPhrase(text, "selected option")
        or ReplyHasPhrase(text, "listed option")
    ) then
        return 1
    end
    return nil
end

local function PendingChoiceForFollowup(text, choices)
    local index = PendingChoiceIndex(text, choices)
    if index then return choices[index], index end
    if #choices == 1 then return choices[1], 1 end
    return nil, nil
end

local function IsPendingChoiceExplainIntent(text)
    local normalized = NormalizeReply(text)
    if normalized == "" then return false end
    return ReplyHasPhrase(text, "explain")
        or ReplyHasPhrase(text, "what does")
        or ReplyHasPhrase(text, "what will")
        or ReplyHasPhrase(text, "what would")
        or ReplyHasPhrase(text, "tell me more")
        or ReplyHasPhrase(text, "more details")
        or ReplyHasPhrase(text, "why this")
        or ReplyHasPhrase(text, "why that")
        or ReplyHasPhrase(text, "why it")
        or ReplyHasPhrase(text, "why this fix")
        or ReplyHasPhrase(text, "why that fix")
        or ReplyHasPhrase(text, "why the fix")
        or ReplyHasPhrase(text, "why option")
        or ReplyHasPhrase(text, "why would i use it")
        or ReplyHasPhrase(text, "why would i use this")
        or ReplyHasPhrase(text, "why should i use it")
        or ReplyHasPhrase(text, "what is it for")
        or ReplyHasPhrase(text, "what is this for")
        or ReplyHasPhrase(text, "what does it help with")
        or ReplyHasPhrase(text, "which one should i pick")
        or ReplyHasPhrase(text, "which option should i choose")
        or ReplyHasPhrase(text, "which one should i choose")
        or IsValueQuestionIntent(text)
end

local function IsPendingChoiceOpenIntent(text)
    local normalized = NormalizeReply(text)
    if normalized == "" then return false end
    if normalized == "open" or normalized == "show me" then return true end
    local phrases = {
        "open it", "open that", "open this", "open option", "open choice", "open result",
        "open the option", "open the choice", "open selected", "open listed",
        "show it", "show that", "show this", "show option", "show choice", "show result",
        "show me where", "take me there", "go there",
    }
    for i = 1, #phrases do
        if ReplyHasPhrase(text, phrases[i]) then return true end
    end
    return false
end

local function PendingChoiceExplainText(choice, index, choices)
    if not choice then
        return {
            text = "Tell me which listed option you mean, for example 'explain option 1' or 'open option 2'.",
            result = "info",
        }
    end

    local label = ChoiceDisplayLabel(choice)
    local setting, change = PendingChoicePrimarySetting(choice)
    local action = choice.action
    if not action and choice.actionKey and Registry and type(Registry.GetAction) == "function" then action = Registry:GetAction(choice.actionKey) end
    if not label or label == "" then
        label = setting and AssistantSettingLabel(setting, "MSUF option")
            or (action and AssistantActionLabel(action, "Assistant task") or "listed option")
    end

    local lines = { "Option " .. tostring(index or 1) .. ": " .. tostring(label) .. "." }
    local page, pageLabel = PendingChoicePage(choice)
    pageLabel = pageLabel or PendingPageLabel(page)
    if pageLabel then lines[#lines + 1] = "Page: " .. tostring(pageLabel) .. "." end

    if setting then
        if type(setting.get) == "function" then
            lines[#lines + 1] = "Current value: " .. tostring(SettingValueLabel(setting, setting.get())) .. "."
        end
        local nextValue = change and change.value
        if nextValue == nil then nextValue = choice.value end
        local nextLabel = (change and change.valueLabel) or choice.valueLabel
        if nextValue ~= nil or nextLabel ~= nil then
            lines[#lines + 1] = "Selecting it would set " .. AssistantSettingLabel(setting, "this option") .. " to " .. tostring(SettingResponseValueLabel(setting, nextValue, nextLabel)) .. "."
        else
            lines[#lines + 1] = "Selecting it would change " .. AssistantSettingLabel(setting, "this option") .. "."
        end
        if choice.diagnosticFix == true then
            lines[#lines + 1] = "This is a suggested repair from the last check."
        end
        lines[#lines + 1] = "Say 'fix it' or the option number to apply it, or 'open option " .. tostring(index or 1) .. "' to inspect the page first."
    elseif action then
        if type(choice.summary) == "string" and choice.summary ~= "" then lines[#lines + 1] = choice.summary end
        lines[#lines + 1] = "Selecting it would run this MSUF task."
        lines[#lines + 1] = "Say the option number to run it, or cancel to keep MSUF as it is."
    elseif type(choice.changes) == "table" and #choice.changes > 0 then
        lines[#lines + 1] = "Selecting it would apply " .. tostring(#choice.changes) .. " MSUF changes."
        if choice.diagnosticFix == true then lines[#lines + 1] = "This is a suggested repair from the last check." end
    end

    if type(choices) == "table" and #choices > 1 then
        lines[#lines + 1] = "Other listed options are still available by number."
    end

    return { text = table.concat(lines, "\n"), result = "info", summary = "Explains a pending Assistant option." }
end

local function PendingChoiceSimpleExplainText(choice, index, choices)
    if not choice then
        return {
            text = "Tell me which listed option you want simplified, for example 'explain option 1 simpler'.",
            result = "info",
            summary = "Asks which pending Assistant option to simplify.",
        }
    end

    local label = ChoiceDisplayLabel(choice)
    local setting, change = PendingChoicePrimarySetting(choice)
    local action = choice.action
    if not action and choice.actionKey and Registry and type(Registry.GetAction) == "function" then action = Registry:GetAction(choice.actionKey) end
    if not label or label == "" then
        label = setting and AssistantSettingLabel(setting, "MSUF option")
            or (action and AssistantActionLabel(action, "Assistant task") or "listed option")
    end

    local lines = { "Simple explanation" }
    if setting then
        local settingLabel = AssistantSettingLabel(setting, tostring(label))
        local nextValue = change and change.value
        if nextValue == nil then nextValue = choice.value end
        local nextLabel = (change and change.valueLabel) or choice.valueLabel
        local current
        if type(setting.get) == "function" then current = SettingValueLabel(setting, setting.get()) end
        lines[#lines + 1] = "Option " .. tostring(index or 1) .. " changes " .. tostring(settingLabel) .. "."
        if current ~= nil then lines[#lines + 1] = "Right now it is " .. tostring(current) .. "." end
        if nextValue ~= nil or nextLabel ~= nil then
            lines[#lines + 1] = "If you pick it, I will set it to " .. tostring(SettingResponseValueLabel(setting, nextValue, nextLabel)) .. "."
        end
        if choice.diagnosticFix == true then lines[#lines + 1] = "It is suggested because the last check found this as a likely fix." end
        lines[#lines + 1] = "Say 'fix it' to apply it, or 'open option " .. tostring(index or 1) .. "' to inspect the page first."
    elseif action then
        lines[#lines + 1] = "Option " .. tostring(index or 1) .. " runs the Assistant task " .. tostring(label) .. "."
        local detail = CompactExplanationText(choice.summary, 160)
        if detail then lines[#lines + 1] = detail end
        lines[#lines + 1] = "Say the option number to run it, or cancel to leave MSUF unchanged."
    elseif type(choice.changes) == "table" and #choice.changes > 0 then
        lines[#lines + 1] = "Option " .. tostring(index or 1) .. " applies " .. tostring(#choice.changes) .. " MSUF changes."
        if choice.diagnosticFix == true then lines[#lines + 1] = "It is suggested because the last check found this as a likely fix." end
        lines[#lines + 1] = "Say the option number to apply it, or cancel to leave MSUF unchanged."
    else
        lines[#lines + 1] = "Option " .. tostring(index or 1) .. " is a listed Assistant choice."
        lines[#lines + 1] = "Ask me to open or explain it before applying it."
    end

    if type(choices) == "table" and #choices > 1 then
        lines[#lines + 1] = "Other listed options are still available by number."
    end
    return { text = table.concat(lines, "\n"), result = "info", summary = "Explains a pending Assistant option in simple language." }
end

local function PendingChoiceOpenResult(choice, index)
    if not choice then
        return {
            text = "Tell me which listed option to open, for example 'open option 1'.",
            result = "info",
        }
    end
    if choice.action or choice.actionKey then
        local action = choice.action
        if not action and Registry and type(Registry.GetAction) == "function" then action = Registry:GetAction(choice.actionKey) end
        if action and action.key == "open_page" then
            ClearPendingChoices()
            return ExecuteChoice(choice)
        end
    end
    local page, label = PendingChoicePage(choice)
    label = label or PendingPageLabel(page)
    if not page then
        return {
            text = "I can explain that option, but I do not know a direct MSUF page to open for it yet.",
            result = "info",
        }
    end
    local action = Registry and type(Registry.GetAction) == "function" and Registry:GetAction("open_page") or nil
    if not action then
        return {
            text = "Open " .. tostring(label or page) .. " to inspect option " .. tostring(index or 1) .. ". The listed choice is still waiting.",
            result = "info",
        }
    end
    local result = A.ExecutePlan({
        kind = "action",
        action = action,
        args = { page = page, label = label or page },
        label = "Open " .. tostring(label or page),
        summary = "Opens the page for a pending Assistant option.",
    })
    if type(result) == "table" and type(result.text) == "string" and result.text ~= "" then
        result.text = result.text .. "\nThe listed choice is still waiting. Say 'fix it', the option number, or cancel."
    end
    return result
end

local function PendingChoiceExplainResult(text, choices)
    if not IsPendingChoiceExplainIntent(text) then return nil end
    if #choices > 1 and not PendingChoiceIndex(text, choices) and (
        ReplyHasPhrase(text, "which one should i pick")
        or ReplyHasPhrase(text, "which option should i choose")
        or ReplyHasPhrase(text, "which one should i choose")
    ) then
        return {
            text = "I cannot choose safely without your intent. Pick a number, or ask me to explain a specific one, for example 'explain option 1'.\n" .. ChoiceText(choices),
            result = "info",
            summary = "Explains that a pending Assistant choice needs user intent.",
        }
    end
    local choice, index = PendingChoiceForFollowup(text, choices)
    if IsSimpleExplainIntent(text) then return PendingChoiceSimpleExplainText(choice, index, choices) end
    return PendingChoiceExplainText(choice, index, choices)
end

local function PendingChoiceOpenFollowupResult(text, choices)
    if not IsPendingChoiceOpenIntent(text) then return nil end
    local choice, index = PendingChoiceForFollowup(text, choices)
    return PendingChoiceOpenResult(choice, index)
end

local PENDING_RESULT_ORDINALS = {
    { word = "first", index = 1 },
    { word = "second", index = 2 },
    { word = "third", index = 3 },
    { word = "fourth", index = 4 },
    { word = "fifth", index = 5 },
    { word = "sixth", index = 6 },
    { word = "seventh", index = 7 },
    { word = "eighth", index = 8 },
    { word = "ninth", index = 9 },
    { word = "tenth", index = 10 },
}

AP.PendingResultNumberWords = AP.PendingResultNumberWords or {
    { word = "one", index = 1 },
    { word = "two", index = 2 },
    { word = "three", index = 3 },
    { word = "four", index = 4 },
    { word = "five", index = 5 },
    { word = "six", index = 6 },
    { word = "seven", index = 7 },
    { word = "eight", index = 8 },
    { word = "nine", index = 9 },
    { word = "ten", index = 10 },
}

AP.PendingResultNumberWordActions = AP.PendingResultNumberWordActions or {
    "open", "show", "show me", "explain", "describe", "tell me about",
    "what is", "what does", "is", "run", "execute", "use", "apply", "select", "pick",
    "compare", "set", "change", "make", "turn", "enable", "disable", "hide",
    "increase", "decrease", "raise", "lower", "where is", "where do i change",
    "where can i change", "which page is", "what page is", "what menu is",
    "current value of", "value of", "why", "what about", "how about", "what can i set",
    "move", "nudge", "shift", "put", "place", "position", "anchor",
    "bring", "send", "push", "pull",
}

AP.PendingResultNumberWord = AP.PendingResultNumberWord or function(index)
    index = tonumber(index)
    if not index then return nil end
    local numberWords = AP.PendingResultNumberWords or {}
    for i = 1, #numberWords do
        local row = numberWords[i]
        if row and row.index == index then return row.word end
    end
    return nil
end

AP.PendingResultNumberWordIndex = AP.PendingResultNumberWordIndex or function(text, results)
    local normalized = NormalizeReply(text)
    if normalized == "" then return nil end
    local numberWords = AP.PendingResultNumberWords or {}
    for i = 1, #numberWords do
        local row = numberWords[i]
        local word = row and NormalizeReply(row.word) or ""
        local index = row and tonumber(row.index)
        if word ~= "" and index and results and results[index] then
            if normalized == word or normalized == "the " .. word then return index end
            for _, prefix in ipairs({ "result", "option", "choice", "number" }) do
                local phrase = prefix .. " " .. word
                if normalized == phrase
                    or normalized:sub(1, #phrase + 1) == phrase .. " "
                    or ReplyHasPhrase(normalized, phrase) then
                    return index
                end
            end
            local actions = AP.PendingResultNumberWordActions or {}
            for j = 1, #actions do
                local action = NormalizeReply(actions[j])
                if action ~= "" then
                    local phrase = action .. " " .. word
                    if normalized == phrase or normalized:sub(1, #phrase + 1) == phrase .. " " then
                        return index
                    end
                    phrase = action .. " the " .. word
                    if normalized == phrase or normalized:sub(1, #phrase + 1) == phrase .. " " then
                        return index
                    end
                end
            end
        end
    end
    return nil
end

AP.PendingResultOrdinalSuffix = AP.PendingResultOrdinalSuffix or function(index)
    index = tonumber(index)
    if not index then return nil end
    local suffix = "th"
    if index % 100 < 11 or index % 100 > 13 then
        local last = index % 10
        if last == 1 then suffix = "st"
        elseif last == 2 then suffix = "nd"
        elseif last == 3 then suffix = "rd" end
    end
    return tostring(index) .. suffix
end

AP.PendingResultNumericReferenceIndex = AP.PendingResultNumericReferenceIndex or function(text, results)
    local normalized = NormalizeReply(text)
    if normalized == "" then return nil end
    local function tokenIndex(token)
        token = NormalizeReply(token)
        if token == "" then return nil end
        local n = tonumber(token:match("^(%d+)$")) or tonumber(token:match("^(%d+)%a%a$"))
        if n and results and results[n] then return n end
        return nil
    end
    local n = tokenIndex(normalized)
    if n then return n end
    n = normalized:match("^the%s+(.+)$")
    n = n and tokenIndex(n) or nil
    if n then return n end

    local actions = AP.PendingResultNumberWordActions or {}
    for i = 1, #(results or {}) do
        local tokens = { tostring(i) }
        local ordinalToken = AP.PendingResultOrdinalSuffix and AP.PendingResultOrdinalSuffix(i) or nil
        if ordinalToken then tokens[#tokens + 1] = ordinalToken end
        for tokenIndexValue = 1, #tokens do
            local token = tokens[tokenIndexValue]
            for _, prefix in ipairs({ "result", "option", "choice", "number" }) do
                local phrase = prefix .. " " .. token
                if normalized == phrase or normalized:sub(1, #phrase + 1) == phrase .. " " or ReplyHasPhrase(normalized, phrase) then
                    return i
                end
                phrase = token .. " " .. prefix
                if normalized == phrase or normalized:sub(1, #phrase + 1) == phrase .. " " or ReplyHasPhrase(normalized, phrase) then
                    return i
                end
            end
            for j = 1, #actions do
                local action = NormalizeReply(actions[j])
                if action ~= "" then
                    local phrase = action .. " " .. token
                    if normalized == phrase or normalized:sub(1, #phrase + 1) == phrase .. " " then return i end
                    phrase = action .. " the " .. token
                    if normalized == phrase or normalized:sub(1, #phrase + 1) == phrase .. " " then return i end
                end
            end
        end
    end
    return nil
end

AP.PendingResultListPositionTerms = AP.PendingResultListPositionTerms or {
    first = { "top", "top one", "top result", "top option", "top choice", "top item", "first listed", "first listed result", "first listed option" },
    penultimate = { "second last", "second to last", "second from bottom", "next to last", "penultimate", "2nd last", "2nd to last", "2nd from bottom" },
    last = { "last", "last one", "last result", "last option", "last choice", "last item", "bottom", "bottom one", "bottom result", "bottom option", "final", "final one", "final result", "final option" },
}

AP.PendingResultListPositionIndex = AP.PendingResultListPositionIndex or function(text, results)
    local normalized = NormalizeReply(text)
    if normalized == "" or type(results) ~= "table" or #results == 0 then return nil end
    local function matchesTerm(term)
        term = NormalizeReply(term)
        if term == "" then return false end
        if normalized == term or normalized == "the " .. term then return true end
        if ReplyHasPhrase(normalized, term) then return true end
        local actions = AP.PendingResultNumberWordActions or {}
        for i = 1, #actions do
            local action = NormalizeReply(actions[i])
            if action ~= "" then
                local phrase = action .. " " .. term
                if normalized == phrase or normalized:sub(1, #phrase + 1) == phrase .. " " then return true end
                phrase = action .. " the " .. term
                if normalized == phrase or normalized:sub(1, #phrase + 1) == phrase .. " " then return true end
            end
        end
        return false
    end
    local penultimateTerms = AP.PendingResultListPositionTerms.penultimate or {}
    for i = 1, #penultimateTerms do
        if matchesTerm(penultimateTerms[i]) then return math.max(1, #results - 1) end
    end
    local firstTerms = AP.PendingResultListPositionTerms.first or {}
    for i = 1, #firstTerms do
        if matchesTerm(firstTerms[i]) then return 1 end
    end
    local lastTerms = AP.PendingResultListPositionTerms.last or {}
    for i = 1, #lastTerms do
        if matchesTerm(lastTerms[i]) then return #results end
    end
    return nil
end

AP.PendingResultAdjacentTerms = AP.PendingResultAdjacentTerms or {
    next = {
        "next one", "next result", "next option", "next choice", "next item",
        "following one", "following result", "following option",
        "one after", "result after", "option after", "one below", "below result",
        "next",
    },
    previous = {
        "previous one", "previous result", "previous option", "previous choice", "previous item",
        "prev one", "prev result", "prior one", "prior result",
        "one before", "result before", "option before", "one above", "above result",
        "previous", "prev", "prior",
    },
}

AP.PendingResultAdjacentDirection = AP.PendingResultAdjacentDirection or function(text, wantedDirection)
    local normalized = NormalizeReply(text)
    if normalized == "" then return nil end
    wantedDirection = wantedDirection and NormalizeReply(wantedDirection) or nil

    local function hasPenultimatePhrase()
        local terms = AP.PendingResultListPositionTerms and AP.PendingResultListPositionTerms.penultimate or {}
        for i = 1, #terms do
            local term = NormalizeReply(terms[i])
            if term ~= "" and ReplyHasPhrase(normalized, term) then return true end
        end
        return false
    end

    local penultimateMention = hasPenultimatePhrase()
    local function compareMentions(term)
        if not (ReplyHasPhrase(normalized, "compare")
            or ReplyHasPhrase(normalized, "difference")
            or ReplyHasPhrase(normalized, "differences")
            or ReplyHasPhrase(normalized, "vs")
            or ReplyHasPhrase(normalized, "versus")
            or ReplyHasPhrase(normalized, "better")) then
            return false
        end
        local padded = " " .. normalized .. " "
        if padded:find(" compare " .. term .. " ", 1, true)
            or padded:find(" between " .. term .. " ", 1, true) then
            return true
        end
        for _, separator in ipairs({ " vs ", " versus ", " and ", " or ", " to ", " with " }) do
            if padded:find(" " .. term .. separator, 1, true)
                or padded:find(separator .. term .. " ", 1, true) then
                return true
            end
        end
        return false
    end

    local function matchesTerm(term)
        term = NormalizeReply(term)
        if term == "" then return false end
        if penultimateMention and term == "next" then return false end
        if normalized == term or normalized == "the " .. term then return true end
        local bare = term:find("%s", 1, true) == nil
        if not bare and ReplyHasPhrase(normalized, term) then return true end
        local actions = AP.PendingResultNumberWordActions or {}
        for i = 1, #actions do
            local action = NormalizeReply(actions[i])
            if action ~= "" then
                local phrase = action .. " " .. term
                if normalized == phrase or normalized:sub(1, #phrase + 1) == phrase .. " " then return true end
                phrase = action .. " the " .. term
                if normalized == phrase or normalized:sub(1, #phrase + 1) == phrase .. " " then return true end
            end
        end
        return compareMentions(term)
    end

    local directions = wantedDirection and { wantedDirection } or { "next", "previous" }
    for i = 1, #directions do
        local direction = directions[i]
        local terms = AP.PendingResultAdjacentTerms and AP.PendingResultAdjacentTerms[direction] or {}
        for j = 1, #terms do
            if matchesTerm(terms[j]) then return direction end
        end
    end
    return nil
end

AP.PendingResultAdjacentIndex = AP.PendingResultAdjacentIndex or function(text, results, forcedDirection)
    if type(results) ~= "table" or #results == 0 then return nil end
    local selected = CurrentSelectedPendingResult()
    local selectedIndex = selected and tonumber(selected.index)
    if not selectedIndex then return nil end
    local direction = forcedDirection or (AP.PendingResultAdjacentDirection and AP.PendingResultAdjacentDirection(text))
    if direction ~= "next" and direction ~= "previous" then return nil end
    local index = direction == "next" and (selectedIndex + 1) or (selectedIndex - 1)
    if results[index] then return index end
    return nil
end

AP.PendingResultAdjacentOutOfRange = AP.PendingResultAdjacentOutOfRange or function(text, results)
    if type(results) ~= "table" or #results == 0 then return nil end
    local selected = CurrentSelectedPendingResult()
    local selectedIndex = selected and tonumber(selected.index)
    if not selectedIndex then return nil end
    for _, direction in ipairs({ "previous", "next" }) do
        if AP.PendingResultAdjacentDirection and AP.PendingResultAdjacentDirection(text, direction) then
            local target = direction == "next" and (selectedIndex + 1) or (selectedIndex - 1)
            if not results[target] then
                local side = direction == "next" and "after" or "before"
                return {
                    text = "There is no " .. direction .. " result " .. side .. " result " .. tostring(selectedIndex) .. ". Pick a listed result number, or ask for top result/last result.",
                    result = "ambiguous",
                    summary = "Explains that an adjacent Assistant search result is out of range.",
                }
            end
        end
    end
    return nil
end

AP.PendingResultLabelStopWords = AP.PendingResultLabelStopWords or {
    a = true, an = true, the = true, this = true, that = true, these = true, those = true,
    one = true, result = true, option = true, choice = true, item = true, setting = true, match = true,
    please = true, ["for"] = true, to = true, at = true, of = true,
}

AP.PendingResultLabelPrefixes = AP.PendingResultLabelPrefixes or {
    "what values are supported for", "which values are supported for",
    "what values can i use for", "which values can i use for",
    "supported values for", "allowed values for", "valid values for", "available values for",
    "what can i set", "what can i set the", "what can i set this", "what can i set that",
    "current value of", "value of", "what is the current value of", "what is current value of",
    "where do i change", "where can i change", "which page is", "what page is", "what menu is",
    "tell me about", "tell me more about", "describe", "explain", "open", "show me", "show",
    "where is", "what is", "whats", "is", "why",
    "set", "change", "make", "turn", "enable", "disable", "hide",
    "increase", "decrease", "raise", "lower",
    "move", "nudge", "shift", "put", "place", "position",
}

AP.PendingResultLabelQuery = AP.PendingResultLabelQuery or function(text)
    local normalized = NormalizeReply(text)
    if normalized == "" then return "" end
    local prefixes = AP.PendingResultLabelPrefixes or {}
    local hadPrefix = false
    local prefixChanged = true
    local prefixPasses = 0
    while prefixChanged and prefixPasses < 4 do
        prefixChanged = false
        prefixPasses = prefixPasses + 1
        for i = 1, #prefixes do
            local prefix = NormalizeReply(prefixes[i])
            if prefix ~= "" then
                if normalized == prefix then return "" end
                if normalized:sub(1, #prefix + 1) == prefix .. " " then
                    normalized = Trim(normalized:sub(#prefix + 2))
                    hadPrefix = true
                    prefixChanged = true
                    break
                end
            end
        end
    end
    if hadPrefix then
        normalized = normalized:gsub("%s+to%s+[-+]?%d+%.?%d*$", "")
            :gsub("%s+at%s+[-+]?%d+%.?%d*$", "")
            :gsub("%s+to%s+on$", ""):gsub("%s+to%s+off$", "")
            :gsub("%s+to%s+enabled$", ""):gsub("%s+to%s+disabled$", "")
            :gsub("%s+bigger$", ""):gsub("%s+larger$", ""):gsub("%s+smaller$", "")
            :gsub("%s+higher$", ""):gsub("%s+lower$", "")
            :gsub("%s+left$", ""):gsub("%s+right$", ""):gsub("%s+up$", ""):gsub("%s+down$", "")
    end
    normalized = normalized:gsub("%s+set%s+to$", ""):gsub("%s+set%s+at$", "")
        :gsub("%s+enabled$", ""):gsub("%s+disabled$", "")
        :gsub("%s+on$", ""):gsub("%s+off$", "")
        :gsub("%s+shown$", ""):gsub("%s+hidden$", ""):gsub("%s+visible$", "")
        :gsub("%s+to$", ""):gsub("%s+at$", "")
    local stop = AP.PendingResultLabelStopWords or {}
    local changed = true
    while changed do
        changed = false
        local first, rest = normalized:match("^(%S+)%s*(.*)$")
        if first and stop[first] then
            normalized = Trim(rest)
            changed = true
        end
        local before, last = normalized:match("^(.*%S)%s+(%S+)$")
        if last and stop[last] then
            normalized = Trim(before)
            changed = true
        elseif normalized ~= "" and stop[normalized] then
            normalized = ""
            changed = true
        end
    end
    return normalized
end

AP.PendingResultLabelTokens = AP.PendingResultLabelTokens or function(text)
    local tokens = {}
    local stop = AP.PendingResultLabelStopWords or {}
    for token in NormalizeReply(text):gmatch("%S+") do
        if not stop[token] then tokens[#tokens + 1] = token end
    end
    return tokens
end

AP.PendingResultLabelTermScore = AP.PendingResultLabelTermScore or function(query, queryTokens, term, weight)
    term = NormalizeReply(term)
    if query == "" or term == "" then return 0 end
    weight = tonumber(weight) or 0
    if term == query then return 1000 + weight end
    if term:find(query, 1, true) then return 800 + weight - math.max(0, #term - #query) * 0.01 end

    local termTokenCount = 0
    local termText = " " .. term .. " "
    for _ in term:gmatch("%S+") do termTokenCount = termTokenCount + 1 end
    local matched = 0
    for i = 1, #(queryTokens or {}) do
        if termText:find(" " .. queryTokens[i] .. " ", 1, true) then matched = matched + 1 end
    end
    if matched == 0 then return 0 end
    if matched == #(queryTokens or {}) then
        return 500 + matched * 60 + weight - math.max(0, termTokenCount - matched) * 5
    end
    if termTokenCount == 1 and matched == 1 and #(queryTokens or {}) > 1 then return 90 + weight end
    return 0
end

AP.PendingResultLabelMatch = AP.PendingResultLabelMatch or function(text, results)
    if type(results) ~= "table" or #results == 0 then return nil end
    local original = NormalizeReply(text)
    local query = AP.PendingResultLabelQuery and AP.PendingResultLabelQuery(text) or NormalizeReply(text)
    if query == "" then return nil end
    local queryTokens = AP.PendingResultLabelTokens and AP.PendingResultLabelTokens(query) or {}
    if #queryTokens == 0 then return nil end
    local settingIntent = original:match("^set%s+") ~= nil
        or original:match("^change%s+") ~= nil
        or original:match("^make%s+") ~= nil
        or original:match("^turn%s+") ~= nil
        or original:match("^enable%s+") ~= nil
        or original:match("^disable%s+") ~= nil
        or original:match("^hide%s+") ~= nil
        or original:match("^show%s+") ~= nil
        or original:match("^increase%s+") ~= nil
        or original:match("^decrease%s+") ~= nil
        or original:match("^raise%s+") ~= nil
        or original:match("^lower%s+") ~= nil
        or ReplyHasPhrase(original, "current value")
        or ReplyHasPhrase(original, "value of")
        or ReplyHasPhrase(original, "what can i set")
        or ReplyHasPhrase(original, "allowed values")
        or ReplyHasPhrase(original, "supported values")
        or ReplyHasPhrase(original, "valid values")
        or ReplyHasPhrase(original, "available values")
        or ReplyHasPhrase(original, "what values")
        or ReplyHasPhrase(original, "what range")
        or original:match("^what%s+is%s+.+%s+set%s+to") ~= nil
        or original:match("^is%s+.+%s+on$") ~= nil
        or original:match("^is%s+.+%s+off$") ~= nil
        or original:match("^is%s+.+%s+enabled$") ~= nil
        or original:match("^is%s+.+%s+disabled$") ~= nil
    local booleanIntent = original:match("^turn%s+") ~= nil
        or original:match("^enable%s+") ~= nil
        or original:match("^disable%s+") ~= nil
        or original:match("^hide%s+") ~= nil
        or original:match("%s+on$") ~= nil
        or original:match("%s+off$") ~= nil
        or original:match("%s+enabled$") ~= nil
        or original:match("%s+disabled$") ~= nil
    local numericIntent = original:match("[-+]?%d+%.?%d*") ~= nil
        or original:match("^increase%s+") ~= nil
        or original:match("^decrease%s+") ~= nil
        or original:match("^raise%s+") ~= nil
        or original:match("^lower%s+") ~= nil
        or ReplyHasPhrase(original, "bigger")
        or ReplyHasPhrase(original, "larger")
        or ReplyHasPhrase(original, "smaller")
        or ReplyHasPhrase(original, "shorter")
        or ReplyHasPhrase(original, "wider")
        or ReplyHasPhrase(original, "narrower")
        or ReplyHasPhrase(original, "grow")
        or ReplyHasPhrase(original, "shrink")

    local candidates = {}
    for i = 1, #results do
        local item = results[i]
        if item then
            if settingIntent and not item.setting then item = nil end
            if item and booleanIntent and item.setting and item.setting.type ~= "boolean" then item = nil end
            if item and numericIntent and item.setting and item.setting.type ~= "number" then item = nil end
        end
        if item then
            local terms = {
                { item.label, 80 },
                { item.setting and item.setting.label, 80 },
                { item.pageLabel, 45 },
                { item.category, 25 },
                { item.key, 10 },
            }
            local score = 0
            for j = 1, #terms do
                local value = terms[j][1]
                if value ~= nil then
                    local termScore = AP.PendingResultLabelTermScore and AP.PendingResultLabelTermScore(query, queryTokens, value, terms[j][2]) or 0
                    if termScore > score then score = termScore end
                end
            end
            if score >= 140 then candidates[#candidates + 1] = { index = i, item = item, score = score } end
        end
    end
    if #candidates == 0 then return nil end
    table.sort(candidates, function(a, b)
        if a.score == b.score then return a.index < b.index end
        return a.score > b.score
    end)
    local top = candidates[1]
    local close = { top }
    for i = 2, #candidates do
        if candidates[i].score >= top.score - 20 then close[#close + 1] = candidates[i] end
    end
    if #close == 1 then return { index = top.index, item = top.item, query = query, score = top.score } end
    return { ambiguous = true, candidates = close, query = query, score = top.score }
end

function A._PendingResultLabelReply(text)
    local results = CurrentPendingResults()
    return AP.PendingResultLabelMatch and AP.PendingResultLabelMatch(text, results or {}) ~= nil
end

AP.PendingResultExtraNumberWords = AP.PendingResultExtraNumberWords or {
    { word = "zero", index = 0 },
    { word = "eleven", index = 11 },
    { word = "twelve", index = 12 },
    { word = "thirteen", index = 13 },
    { word = "fourteen", index = 14 },
    { word = "fifteen", index = 15 },
    { word = "sixteen", index = 16 },
    { word = "seventeen", index = 17 },
    { word = "eighteen", index = 18 },
    { word = "nineteen", index = 19 },
    { word = "twenty", index = 20 },
}

AP.PendingResultReferenceWordNumber = AP.PendingResultReferenceWordNumber or function(word)
    word = NormalizeReply(word)
    if word == "" then return nil end
    local numberWords = AP.PendingResultNumberWords or {}
    for i = 1, #numberWords do
        local row = numberWords[i]
        if row and NormalizeReply(row.word) == word then return tonumber(row.index) end
    end
    local extraWords = AP.PendingResultExtraNumberWords or {}
    for i = 1, #extraWords do
        local row = extraWords[i]
        if row and NormalizeReply(row.word) == word then return tonumber(row.index) end
    end
    return nil
end

AP.PendingResultExplicitOutOfRange = AP.PendingResultExplicitOutOfRange or function(text, results)
    if type(results) ~= "table" or #results == 0 then return nil end
    local normalized = NormalizeReply(text)
    if normalized == "" then return nil end
    local maxResult = #results
    local invalidIndex

    local function noteIndex(index)
        index = tonumber(index)
        if index and (index < 1 or index > maxResult) then
            invalidIndex = index
            return true
        end
        return false
    end

    local exactIndex = normalized:match("^the%s+(%d+)%a*$") or normalized:match("^(%d+)%a*$")
    noteIndex(exactIndex)
    if not invalidIndex then
        local exactWord = normalized:match("^the%s+([%a]+)$") or normalized:match("^([%a]+)$")
        noteIndex(AP.PendingResultReferenceWordNumber and AP.PendingResultReferenceWordNumber(exactWord))
    end

    for _, prefix in ipairs({ "result", "option", "choice", "number" }) do
        if invalidIndex then break end
        for index in normalized:gmatch(prefix .. "%s+(%d+)%a*") do
            if noteIndex(index) then break end
        end
        if invalidIndex then break end
        for word in normalized:gmatch(prefix .. "%s+([%a]+)") do
            if noteIndex(AP.PendingResultReferenceWordNumber and AP.PendingResultReferenceWordNumber(word)) then break end
        end
        if invalidIndex then break end
    end
    if not invalidIndex then
        for index in normalized:gmatch("#(%d+)") do
            if noteIndex(index) then break end
        end
    end

    local function checkActionTarget(tail)
        tail = Trim(tostring(tail or ""))
        if tail == "" then return false end
        local index = tail:match("^the%s+(%d+)%a*") or tail:match("^(%d+)%a*")
        if noteIndex(index) then return true end
        local word = tail:match("^the%s+([%a]+)") or tail:match("^([%a]+)")
        return noteIndex(AP.PendingResultReferenceWordNumber and AP.PendingResultReferenceWordNumber(word))
    end

    if not invalidIndex then
        local actions = AP.PendingResultNumberWordActions or {}
        for i = 1, #actions do
            local action = NormalizeReply(actions[i])
            if action ~= "" then
                if normalized:sub(1, #action + 1) == action .. " " and checkActionTarget(normalized:sub(#action + 2)) then break end
            end
        end
    end

    if not invalidIndex and (
        ReplyHasPhrase(normalized, "compare")
        or ReplyHasPhrase(normalized, "difference")
        or ReplyHasPhrase(normalized, "differences")
        or ReplyHasPhrase(normalized, "vs")
        or ReplyHasPhrase(normalized, "versus")
    ) then
        for index in normalized:gmatch("(%d+)%a*") do
            if noteIndex(index) then break end
        end
        if not invalidIndex then
            for word in normalized:gmatch("([%a]+)") do
                if noteIndex(AP.PendingResultReferenceWordNumber and AP.PendingResultReferenceWordNumber(word)) then break end
            end
        end
    end

    if not invalidIndex then return nil end
    local plural = maxResult == 1 and "result" or "results"
    return {
        text = "I only have " .. tostring(maxResult) .. " active search " .. plural .. ", so result " .. tostring(invalidIndex) .. " is not available. Pick a result from 1 to " .. tostring(maxResult) .. ", or search again.",
        result = "ambiguous",
        summary = "Explains that an Assistant search result number is out of range.",
    }
end

local PENDING_RESULT_ORDINAL_NOUNS = { "one", "result", "option", "choice", "item", "match" }
local PENDING_RESULT_ORDINAL_ACTIONS = {
    "open", "show", "show me", "explain", "describe", "tell me about",
    "what is", "what does", "is", "run", "execute", "use", "apply", "select", "pick",
    "compare", "set", "change", "make", "turn", "enable", "disable", "hide",
    "increase", "decrease", "raise", "lower", "where is", "where do i change",
    "where can i change", "which page is", "what page is", "what menu is",
    "current value of", "value of", "why", "what about", "how about", "what can i set",
    "move", "nudge", "shift", "put", "place", "position", "anchor",
    "bring", "send", "push", "pull",
}

local function PendingResultOrdinalWord(index)
    index = tonumber(index)
    for i = 1, #PENDING_RESULT_ORDINALS do
        if PENDING_RESULT_ORDINALS[i].index == index then return PENDING_RESULT_ORDINALS[i].word end
    end
    return nil
end

local function PendingResultOrdinalReferenceTermsForWord(word, includeBare)
    local terms = {}
    word = NormalizeReply(word)
    if word == "" then return terms end
    for i = 1, #PENDING_RESULT_ORDINAL_NOUNS do
        local noun = PENDING_RESULT_ORDINAL_NOUNS[i]
        terms[#terms + 1] = "the " .. word .. " " .. noun
        terms[#terms + 1] = word .. " " .. noun
        if noun ~= "one" then
            terms[#terms + 1] = "the " .. noun .. " " .. word
            terms[#terms + 1] = noun .. " " .. word
        end
    end
    if includeBare then
        terms[#terms + 1] = "the " .. word
        terms[#terms + 1] = word
    end
    return terms
end

local function PendingResultOrdinalActionTargets(normalized, word)
    local function targetMatches(target)
        target = NormalizeReply(target)
        if normalized == target then return true end
        if normalized:sub(1, #target + 1) ~= target .. " " then return false end
        local tail = Trim(normalized:sub(#target + 2))
        if tail == "" then return true end
        if tail == "on" or tail == "off" or tail == "enabled" or tail == "disabled" then return true end
        if tail == "up" or tail == "down" or tail == "higher" or tail == "lower" then return true end
        if tail == "bigger" or tail == "larger" or tail == "smaller" or tail == "shorter" or tail == "taller" then return true end
        if tail == "left" or tail == "right" or tail == "forward" or tail == "back" or tail == "backward" then return true end
        if tail == "for" or tail == "used for" or tail == "help with" or tail == "do" then return true end
        if tail == "to" or tail == "at" then return true end
        if tail:sub(1, 3) == "to " then return true end
        if tail:match("^left%s+") or tail:match("^right%s+") or tail:match("^up%s+") or tail:match("^down%s+") then return true end
        if tail:match("^bigger%s+") or tail:match("^larger%s+") or tail:match("^smaller%s+") then return true end
        if tail:sub(1, 4) == "and " then return true end
        return false
    end
    for i = 1, #PENDING_RESULT_ORDINAL_ACTIONS do
        local action = PENDING_RESULT_ORDINAL_ACTIONS[i]
        if targetMatches(action .. " the " .. word) or targetMatches(action .. " " .. word) then
            return true
        end
    end
    return false
end

local function PendingResultOrdinalMentioned(text, word, includeBare)
    local normalized = NormalizeReply(text)
    if normalized == "" then return false end
    local terms = PendingResultOrdinalReferenceTermsForWord(word, false)
    for i = 1, #terms do
        if ReplyHasPhrase(normalized, terms[i]) then return true end
    end
    if PendingResultOrdinalActionTargets(normalized, word) then return true end
    if includeBare and (normalized == word or normalized == "the " .. word) then return true end
    return false
end

local function PendingResultOrdinalIndex(text, results)
    results = results or {}
    for i = 1, #PENDING_RESULT_ORDINALS do
        local row = PENDING_RESULT_ORDINALS[i]
        if results[row.index] and PendingResultOrdinalMentioned(text, row.word, true) then
            return row.index
        end
    end
    return nil
end

local function HasPendingResultOrdinalReference(text)
    local results = CurrentPendingResults()
    if type(results) ~= "table" or #results == 0 then return false end
    return PendingResultOrdinalIndex(text, results) ~= nil
end

local function IsPendingResultLocationIntent(text)
    local normalized = NormalizeReply(text)
    if normalized == "where" or normalized == "location" then return true end
    return ReplyHasPhrase(text, "where is")
        or ReplyHasPhrase(text, "where are")
        or ReplyHasPhrase(text, "where do i change")
        or ReplyHasPhrase(text, "where can i change")
        or ReplyHasPhrase(text, "where do i configure")
        or ReplyHasPhrase(text, "where can i configure")
        or ReplyHasPhrase(text, "where do i find")
        or ReplyHasPhrase(text, "where can i find")
        or ReplyHasPhrase(text, "which page")
        or ReplyHasPhrase(text, "what page")
        or ReplyHasPhrase(text, "what menu")
end

local function IsPendingResultPluralLocationIntent(text)
    if not IsPendingResultLocationIntent(text) then return false end
    return ReplyHasPhrase(text, "where are they")
        or ReplyHasPhrase(text, "where are these")
        or ReplyHasPhrase(text, "where are those")
        or ReplyHasPhrase(text, "where are the results")
        or ReplyHasPhrase(text, "where are the options")
        or ReplyHasPhrase(text, "which pages")
        or ReplyHasPhrase(text, "what pages")
end

local function IsPendingResultDecisionIntent(text)
    return ReplyHasPhrase(text, "which one should i")
        or ReplyHasPhrase(text, "which should i")
        or ReplyHasPhrase(text, "which result should i")
        or ReplyHasPhrase(text, "which option should i")
        or ReplyHasPhrase(text, "what should i pick")
        or ReplyHasPhrase(text, "what should i use")
        or ReplyHasPhrase(text, "what should i choose")
        or ReplyHasPhrase(text, "should i use")
        or ReplyHasPhrase(text, "should i pick")
        or ReplyHasPhrase(text, "should i choose")
        or ReplyHasPhrase(text, "should i change")
        or ReplyHasPhrase(text, "should i open")
        or ReplyHasPhrase(text, "what should i change first")
        or ReplyHasPhrase(text, "which should i change first")
        or ReplyHasPhrase(text, "which one is safer")
        or ReplyHasPhrase(text, "which result is safer")
        or ReplyHasPhrase(text, "which option is safer")
        or ReplyHasPhrase(text, "safest result")
        or ReplyHasPhrase(text, "safest option")
        or ReplyHasPhrase(text, "best result")
        or ReplyHasPhrase(text, "best option")
        or ReplyHasPhrase(text, "recommend a result")
        or ReplyHasPhrase(text, "recommend an option")
        or ReplyHasPhrase(text, "recommend one")
end

local function PendingResultIndex(text, results)
    local normalized = NormalizeReply(text)
    local n = tonumber(normalized)
    if n and results[n] then return n end
    n = tonumber(normalized:match("result%s+(%d+)"))
        or tonumber(normalized:match("option%s+(%d+)"))
        or tonumber(normalized:match("choice%s+(%d+)"))
        or tonumber(normalized:match("number%s+(%d+)"))
        or tonumber(normalized:match("#(%d+)"))
    if n and results[n] then return n end
    n = AP.PendingResultNumericReferenceIndex and AP.PendingResultNumericReferenceIndex(text, results)
    if n and results[n] then return n end
    n = AP.PendingResultNumberWordIndex and AP.PendingResultNumberWordIndex(text, results)
    if n and results[n] then return n end
    n = AP.PendingResultListPositionIndex and AP.PendingResultListPositionIndex(text, results)
    if n and results[n] then return n end
    n = AP.PendingResultAdjacentIndex and AP.PendingResultAdjacentIndex(text, results)
    if n and results[n] then return n end
    local withoutPrefix = normalized:gsub("^result%s+", ""):gsub("^option%s+", ""):gsub("^choice%s+", "")
    n = tonumber(withoutPrefix)
    if n and results[n] then return n end
    n = PendingResultOrdinalIndex(text, results)
    if n and results[n] then return n end
    local labelMatch = AP.PendingResultLabelMatch and AP.PendingResultLabelMatch(text, results) or nil
    if labelMatch and labelMatch.index and results[labelMatch.index] then return labelMatch.index end
    if #results == 1 and (
        ReplyHasPhrase(text, "that")
        or ReplyHasPhrase(text, "this")
        or ReplyHasPhrase(text, "it")
        or ReplyHasPhrase(text, "the result")
        or ReplyHasPhrase(text, "the option")
        or ReplyHasPhrase(text, "listed result")
    ) then
        return 1
    end
    local selected = CurrentSelectedPendingResult()
    if selected and (
        ReplyHasPhrase(text, "that")
        or ReplyHasPhrase(text, "this")
        or ReplyHasPhrase(text, "it")
        or ReplyHasPhrase(text, "the result")
        or ReplyHasPhrase(text, "the option")
        or ReplyHasPhrase(text, "that result")
        or ReplyHasPhrase(text, "that option")
        or ReplyHasPhrase(text, "this result")
        or ReplyHasPhrase(text, "this option")
    ) then
        return tonumber(selected.index)
    end
    if selected and IsSimpleExplainIntent(text) then return tonumber(selected.index) end
    if selected and IsValueQuestionIntent(text) then return tonumber(selected.index) end
    if selected and IsWhyReasonIntent(text) then return tonumber(selected.index) end
    if selected and IsPendingResultLocationIntent(text) then return tonumber(selected.index) end
    return nil
end

local SELECTED_RESULT_PRONOUNS = {
    "it", "that", "this",
    "the result", "the option",
    "that result", "that option",
    "this result", "this option",
}

local function HasSelectedResultPronoun(text)
    if not CurrentSelectedPendingResult() then return false end
    for i = 1, #SELECTED_RESULT_PRONOUNS do
        if ReplyHasPhrase(text, SELECTED_RESULT_PRONOUNS[i]) then return true end
    end
    return false
end

function A._HasResultPronounReference(text)
    for i = 1, #SELECTED_RESULT_PRONOUNS do
        if ReplyHasPhrase(text, SELECTED_RESULT_PRONOUNS[i]) then return true end
    end
    return false
end

function A._StartsWithResultCommandPronoun(text)
    local normalized = NormalizeReply(text)
    if normalized == "" then return false end
    for _, starter in ipairs({
        "set", "change", "make", "turn", "enable", "disable", "hide", "show", "toggle",
        "increase", "decrease", "raise", "lower",
        "move", "nudge", "shift", "put", "place", "position", "anchor",
        "bring", "send", "push", "pull",
    }) do
        for j = 1, #SELECTED_RESULT_PRONOUNS do
            local target = starter .. " " .. SELECTED_RESULT_PRONOUNS[j]
            if normalized == target or normalized:sub(1, #target + 1) == target .. " " then
                return true
            end
        end
    end
    return false
end

AP.PendingResultValueIntent = AP.PendingResultValueIntent or function(text, results)
    if IsValueQuestionIntent(text) then return true end
    local normalized = NormalizeReply(text)
    if normalized == "" then return false end
    results = results or CurrentPendingResults() or {}
    local index = PendingResultIndex(text, results)
    if not index and not HasSelectedResultPronoun(text) then return false end
    if normalized:match("^what%s+is%s+.+%s+set%s+to$")
        or normalized:match("^what%s+is%s+.+%s+set%s+at$")
        or normalized:match("^whats%s+.+%s+set%s+to$")
        or normalized:match("^whats%s+.+%s+set%s+at$")
        or normalized:match("^what%s+is%s+.+%s+now$")
        or normalized:match("^whats%s+.+%s+now$") then
        return true
    end
    return normalized:match("^is%s+.+%s+on$") ~= nil
        or normalized:match("^is%s+.+%s+off$") ~= nil
        or normalized:match("^is%s+.+%s+enabled$") ~= nil
        or normalized:match("^is%s+.+%s+disabled$") ~= nil
        or normalized:match("^is%s+.+%s+shown$") ~= nil
        or normalized:match("^is%s+.+%s+hidden$") ~= nil
        or normalized:match("^is%s+.+%s+visible$") ~= nil
end

AP.PendingResultAllowedValuesIntent = AP.PendingResultAllowedValuesIntent or function(text, results)
    local normalized = NormalizeReply(text)
    if normalized == "" then return false end
    return ReplyHasPhrase(normalized, "what can i set")
        or ReplyHasPhrase(normalized, "what can it be")
        or ReplyHasPhrase(normalized, "what can this be")
        or ReplyHasPhrase(normalized, "what can that be")
        or ReplyHasPhrase(normalized, "what can the result be")
        or ReplyHasPhrase(normalized, "what can the option be")
        or ReplyHasPhrase(normalized, "what values")
        or ReplyHasPhrase(normalized, "which values")
        or ReplyHasPhrase(normalized, "allowed values")
        or ReplyHasPhrase(normalized, "supported values")
        or ReplyHasPhrase(normalized, "valid values")
        or ReplyHasPhrase(normalized, "available values")
        or ReplyHasPhrase(normalized, "possible values")
        or ReplyHasPhrase(normalized, "what choices")
        or ReplyHasPhrase(normalized, "which choices")
        or ReplyHasPhrase(normalized, "available choices")
        or ReplyHasPhrase(normalized, "supported choices")
        or ReplyHasPhrase(normalized, "choices for")
        or ReplyHasPhrase(normalized, "options for this")
        or ReplyHasPhrase(normalized, "options for it")
        or ReplyHasPhrase(normalized, "what range")
        or ReplyHasPhrase(normalized, "which range")
        or ReplyHasPhrase(normalized, "allowed range")
        or ReplyHasPhrase(normalized, "supported range")
        or ReplyHasPhrase(normalized, "valid range")
        or ReplyHasPhrase(normalized, "minimum")
        or ReplyHasPhrase(normalized, "maximum")
        or ReplyHasPhrase(normalized, "min max")
end

local IsPendingResultCompareIntent

function A._PendingResultRelatedIntent(text)
    local normalized = NormalizeReply(text)
    if normalized == "related" or normalized == "same page" then return true end
    return ReplyHasPhrase(text, "related option")
        or ReplyHasPhrase(text, "related options")
        or ReplyHasPhrase(text, "related setting")
        or ReplyHasPhrase(text, "related settings")
        or ReplyHasPhrase(text, "similar option")
        or ReplyHasPhrase(text, "similar options")
        or ReplyHasPhrase(text, "similar setting")
        or ReplyHasPhrase(text, "same page")
        or ReplyHasPhrase(text, "this page")
        or ReplyHasPhrase(text, "that page")
        or ReplyHasPhrase(text, "page options")
        or ReplyHasPhrase(text, "page settings")
        or ReplyHasPhrase(text, "options on this page")
        or ReplyHasPhrase(text, "settings on this page")
        or ReplyHasPhrase(text, "what else")
        or ReplyHasPhrase(text, "more like this")
        or ReplyHasPhrase(text, "more options")
        or ReplyHasPhrase(text, "other options")
        or ReplyHasPhrase(text, "other settings")
        or ReplyHasPhrase(text, "what else can i change")
        or ReplyHasPhrase(text, "what else is here")
end

local function IsPendingResultReference(text)
    local normalized = NormalizeReply(text)
    if normalized == "" then return false end
    local hasPendingResults = CurrentPendingResults() ~= nil
    if hasPendingResults and PendingResultIndex(text, CurrentPendingResults() or {}) ~= nil then return true end
    if hasPendingResults and AP.PendingResultExplicitOutOfRange and AP.PendingResultExplicitOutOfRange(text, CurrentPendingResults() or {}) then return true end
    if hasPendingResults and CurrentSelectedPendingResult() and AP.PendingResultAdjacentDirection and AP.PendingResultAdjacentDirection(text) ~= nil then return true end
    if hasPendingResults and AP.PendingResultAllowedValuesIntent and AP.PendingResultAllowedValuesIntent(text, CurrentPendingResults() or {}) then return true end
    if hasPendingResults and A._PendingResultLabelReply and A._PendingResultLabelReply(text) then return true end
    return normalized:match("^%d+$") ~= nil
        or normalized:match("^run%s+%d+") ~= nil
        or normalized:match("^execute%s+%d+") ~= nil
        or normalized:match("^compare%s+%d+") ~= nil
        or normalized:match("^result%s+%d+$") ~= nil
        or normalized:match("^option%s+%d+$") ~= nil
        or normalized:match("^choice%s+%d+$") ~= nil
        or ReplyHasPhrase(text, "result")
        or ReplyHasPhrase(text, "option")
        or ReplyHasPhrase(text, "choice")
        or ReplyHasPhrase(text, "listed result")
        or ReplyHasPhrase(text, "results")
        or ReplyHasPhrase(text, "listed results")
        or HasPendingResultOrdinalReference(text)
        or HasSelectedResultPronoun(text)
        or (hasPendingResults and IsPendingResultCompareIntent(text))
        or (hasPendingResults and (
            normalized == "explain"
            or normalized == "details"
            or normalized == "describe"
            or normalized == "open"
            or normalized == "show me"
            or normalized == "current value"
            or normalized == "value now"
            or normalized == "why"
            or ReplyHasPhrase(text, "open it")
            or ReplyHasPhrase(text, "open that")
            or ReplyHasPhrase(text, "open this")
            or ReplyHasPhrase(text, "show me where")
            or ReplyHasPhrase(text, "take me there")
            or ReplyHasPhrase(text, "go there")
            or ReplyHasPhrase(text, "tell me more")
            or ReplyHasPhrase(text, "more details")
            or A._StartsWithResultCommandPronoun(text)
            or IsSimpleExplainIntent(text)
            or (AP.PendingResultValueIntent and AP.PendingResultValueIntent(text, CurrentPendingResults() or {}))
            or IsWhyReasonIntent(text)
            or IsPendingResultLocationIntent(text)
            or IsPendingResultDecisionIntent(text)
        ))
        or (hasPendingResults and A._PendingResultRelatedIntent(text))
        or (hasPendingResults and IsPendingResultLocationIntent(text))
        or (hasPendingResults and IsPendingResultDecisionIntent(text))
        or (CurrentSelectedPendingResult() and IsSimpleExplainIntent(text))
        or (CurrentSelectedPendingResult() and AP.PendingResultValueIntent and AP.PendingResultValueIntent(text, CurrentPendingResults() or {}))
        or (CurrentSelectedPendingResult() and IsWhyReasonIntent(text))
        or (CurrentSelectedPendingResult() and IsPendingResultLocationIntent(text))
        or (CurrentSelectedPendingResult() and IsPendingResultDecisionIntent(text))
end

local function IsPendingResultExplainIntent(text)
    return ReplyHasPhrase(text, "explain")
        or ReplyHasPhrase(text, "what does")
        or ReplyHasPhrase(text, "what is")
        or ReplyHasPhrase(text, "what are")
        or ReplyHasPhrase(text, "what about")
        or ReplyHasPhrase(text, "how about")
        or ReplyHasPhrase(text, "tell me about")
        or ReplyHasPhrase(text, "tell me more")
        or ReplyHasPhrase(text, "more details")
        or ReplyHasPhrase(text, "details")
        or ReplyHasPhrase(text, "describe")
end

local function IsPendingResultOpenIntent(text)
    local normalized = NormalizeReply(text)
    if normalized == "open" or normalized == "show me" then return true end
    return ReplyHasPhrase(text, "open")
        or ReplyHasPhrase(text, "show it")
        or ReplyHasPhrase(text, "show that")
        or ReplyHasPhrase(text, "show this")
        or ReplyHasPhrase(text, "show me where")
        or ReplyHasPhrase(text, "take me there")
        or ReplyHasPhrase(text, "go there")
end

local function IsPendingResultRunIntent(text)
    return ReplyHasPhrase(text, "run")
        or ReplyHasPhrase(text, "execute")
        or ReplyHasPhrase(text, "do result")
        or ReplyHasPhrase(text, "use result")
        or ReplyHasPhrase(text, "apply result")
end

local RESULT_SETTING_CHANGE_STARTERS = {
    "set", "change", "make", "turn", "enable", "disable", "hide", "show",
    "increase", "decrease", "raise", "lower",
    "move", "nudge", "shift", "put", "place", "position", "anchor",
    "bring", "send", "push", "pull",
}

local function StartsWithCommand(text, starters)
    text = tostring(text or "")
    for i = 1, #(starters or {}) do
        local starter = starters[i]
        if text == starter or text:sub(1, #starter + 1) == starter .. " " then return true end
    end
    return false
end

local function ReplaceFirstPhrase(text, phrase, replacement)
    text = tostring(text or "")
    phrase = tostring(phrase or "")
    if phrase == "" then return nil end
    local padded = " " .. text .. " "
    local startPos, endPos = padded:find(" " .. phrase .. " ", 1, true)
    if not startPos then return nil end
    return Trim(text:sub(1, startPos - 1) .. tostring(replacement or "") .. " " .. text:sub(endPos))
end

local function PendingResultReferenceTerms(index)
    local n = tostring(index or "")
    if n == "" then return {} end
    local ordinalSuffix = AP.PendingResultOrdinalSuffix and AP.PendingResultOrdinalSuffix(index) or nil
    local terms = {
        "result " .. n,
        "option " .. n,
        "choice " .. n,
        "number " .. n,
        "#" .. n,
        n,
    }
    if ordinalSuffix then
        terms[#terms + 1] = ordinalSuffix
        terms[#terms + 1] = "the " .. ordinalSuffix
        terms[#terms + 1] = "result " .. ordinalSuffix
        terms[#terms + 1] = "option " .. ordinalSuffix
        terms[#terms + 1] = "choice " .. ordinalSuffix
        terms[#terms + 1] = "number " .. ordinalSuffix
        terms[#terms + 1] = ordinalSuffix .. " result"
        terms[#terms + 1] = ordinalSuffix .. " option"
        terms[#terms + 1] = ordinalSuffix .. " choice"
    end
    local word = PendingResultOrdinalWord(index)
    if word then
        local ordinalTerms = PendingResultOrdinalReferenceTermsForWord(word, true)
        for i = 1, #ordinalTerms do terms[#terms + 1] = ordinalTerms[i] end
    end
    word = AP.PendingResultNumberWord and AP.PendingResultNumberWord(index) or nil
    if word then
        terms[#terms + 1] = "result " .. word
        terms[#terms + 1] = "option " .. word
        terms[#terms + 1] = "choice " .. word
        terms[#terms + 1] = "number " .. word
        terms[#terms + 1] = word
    end
    local selected = CurrentSelectedPendingResult()
    local selectedIndex = selected and tonumber(selected.index)
    local numericIndex = tonumber(index)
    if selectedIndex and numericIndex then
        local adjacentTerms
        if numericIndex == selectedIndex + 1 then
            adjacentTerms = AP.PendingResultAdjacentTerms and AP.PendingResultAdjacentTerms.next or nil
        elseif numericIndex == selectedIndex - 1 then
            adjacentTerms = AP.PendingResultAdjacentTerms and AP.PendingResultAdjacentTerms.previous or nil
        end
        for i = 1, #(adjacentTerms or {}) do terms[#terms + 1] = adjacentTerms[i] end
    end
    return terms
end

local function PendingResultSettingSyntheticText(text, setting, index)
    if not (setting and index) then return nil end
    local normalized = NormalizeReply(text)
    if normalized == "" then return nil end
    local label = AssistantSettingLabel(setting, "MSUF option")
    local refs = PendingResultReferenceTerms(index)
    local labelMatch = AP.PendingResultLabelMatch and AP.PendingResultLabelMatch(text, CurrentPendingResults() or {}) or nil
    if labelMatch and tonumber(labelMatch.index) == tonumber(index) and labelMatch.query and labelMatch.query ~= "" then
        refs[#refs + 1] = labelMatch.query
        refs[#refs + 1] = "the " .. labelMatch.query
    end

    if StartsWithCommand(normalized, RESULT_SETTING_CHANGE_STARTERS) then
        for i = 1, #refs do
            local replaced = ReplaceFirstPhrase(normalized, refs[i], label)
            if replaced then return replaced end
        end
        if A._HasResultPronounReference(normalized) then
            for i = 1, #SELECTED_RESULT_PRONOUNS do
                local replaced = ReplaceFirstPhrase(normalized, SELECTED_RESULT_PRONOUNS[i], label)
                if replaced then return replaced end
            end
        end
    end

    for i = 1, #refs do
        local ref = refs[i]
        if normalized:sub(1, #ref + 1) == ref .. " " then
            local tail = Trim(normalized:sub(#ref + 2))
            if tail ~= "" then
                if tail:sub(1, 3) == "to " then
                    return "set " .. label .. " " .. tail
                end
                return "set " .. label .. " to " .. tail
            end
        end
    end
    return nil
end

local function SafeSingleSettingChangePlan(parsed, setting)
    if not (parsed and parsed.kind == "changes" and type(parsed.changes) == "table" and #parsed.changes == 1) then return nil end
    local change = parsed.changes[1]
    if not (change and change.setting and setting and change.setting.key == setting.key) then return nil end
    parsed.label = parsed.label or AssistantSettingLabel(setting, "Assistant option change")
    parsed.summary = parsed.summary or "Changes an Assistant search result setting."
    return parsed
end

AP.PendingResultRelatedSiblingPlan = function(text, item, index, parser)
    local typoNormalizedText
    local function followupText()
        if typoNormalizedText == nil then
            typoNormalizedText = " " .. NormalizeReply(text) .. " "
            typoNormalizedText = typoNormalizedText:gsub(" rite ", " right ")
            typoNormalizedText = Trim(typoNormalizedText)
        end
        return typoNormalizedText
    end

    local function followupHasPhrase(phrase)
        phrase = NormalizeReply(phrase)
        if phrase == "" then return false end
        return (" " .. followupText() .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
    end

    local amountText
    local function followupAmountText()
        if amountText == nil then
            amountText = " " .. followupText() .. " "
            amountText = amountText:gsub(" result%s+%d+ ", " ")
            amountText = amountText:gsub(" option%s+%d+ ", " ")
            amountText = amountText:gsub(" choice%s+%d+ ", " ")
            amountText = amountText:gsub(" number%s+%d+ ", " ")
            amountText = amountText:gsub(" #%d+ ", " ")
            amountText = amountText:gsub(" %d+%a%a ", " ")
            amountText = amountText:gsub(" result%s+%d+%a%a ", " ")
            amountText = amountText:gsub(" option%s+%d+%a%a ", " ")
            amountText = amountText:gsub(" choice%s+%d+%a%a ", " ")
            amountText = amountText:gsub(" number%s+%d+%a%a ", " ")
            local indexText = tostring(index or "")
            if indexText ~= "" then
                amountText = amountText:gsub(" " .. indexText .. " ", " ", 1)
                local ordinalText = AP.PendingResultOrdinalSuffix and AP.PendingResultOrdinalSuffix(index) or nil
                if ordinalText and ordinalText ~= "" then
                    amountText = amountText:gsub(" " .. ordinalText .. " ", " ", 1)
                end
            end
            amountText = Trim(amountText)
        end
        return amountText
    end

    local function hasAny(phrases)
        for i = 1, #(phrases or {}) do
            if ReplyHasPhrase(text, phrases[i]) or followupHasPhrase(phrases[i]) then return true end
        end
        return false
    end

    local function compactLabel(value)
        value = NormalizeReply(value)
        value = value:gsub("cast%s+bars", "castbars")
        value = value:gsub("cast%s+bar", "castbar")
        value = value:gsub("%s+", "")
        return value
    end

    local function labelMatches(source, candidate, attr)
        if not (source and candidate) then return false end
        if attr == "anchor" then
            if candidate.type ~= "enum" then return false end
        elseif candidate.type ~= "number" then
            return false
        end
        if source.unit ~= candidate.unit or source.frameType ~= candidate.frameType then return false end
        local sourceLabel = compactLabel(source.label or "")
        local candidateLabel = compactLabel(candidate.label or "")
        if sourceLabel == "" or candidateLabel:sub(1, #sourceLabel) ~= sourceLabel then return false end
        local hay = compactLabel(
            tostring(candidate.label or "") .. " " ..
            tostring(candidate.attribute or "") .. " " ..
            tostring(candidate.key or "")
        )
        if attr == "size" then return hay:find("size", 1, true) ~= nil end
        if attr == "height" then return hay:find("height", 1, true) ~= nil or hay:find("hoehe", 1, true) ~= nil end
        if attr == "width" then return hay:find("width", 1, true) ~= nil or hay:find("breite", 1, true) ~= nil end
        if attr == "offsetX" then return hay:find("xoffset", 1, true) ~= nil or hay:find("offsetx", 1, true) ~= nil end
        if attr == "offsetY" then return hay:find("yoffset", 1, true) ~= nil or hay:find("offsety", 1, true) ~= nil end
        if attr == "layer" then return hay:find("layer", 1, true) ~= nil end
        if attr == "anchor" then return hay:find("anchor", 1, true) ~= nil end
        return false
    end

    local function addUnique(out, seen, setting)
        if not (setting and setting.key and (setting.type == "number" or setting.type == "enum")) then return end
        if seen[setting.key] then return end
        seen[setting.key] = true
        out[#out + 1] = setting
    end

    local function directionForText()
        if hasAny({
            "smaller", "make smaller", "make it smaller", "shrink", "shorter", "narrower",
            "decrease", "decrease size", "reduce", "reduce size", "smaller size", "less size",
        }) then
            return "decrease"
        end
        if hasAny({
            "bigger", "make bigger", "make it bigger", "larger", "make larger", "make it larger",
            "grow", "taller", "wider", "increase", "increase size", "larger size", "more size",
        }) then
            return "increase"
        end
        return nil
    end

    local function exactNumberForText()
        local norm = NormalizeReply(text)
        if not (norm:find("^set%s+") or norm:find("^change%s+") or norm:find("^make%s+")) then return nil end
        if hasAny({
            "increase", "decrease", "raise", "lower", "bigger", "larger", "smaller",
            "taller", "shorter", "wider", "narrower", "grow", "shrink",
            "move", "nudge", "shift", "bring", "send", "push", "pull",
            "forward", "backward", "backwards", "front", "back",
        }) then
            return nil
        end
        local valueText = followupAmountText()
        local value = A._ExplicitNumberValue and A._ExplicitNumberValue(valueText) or nil
        if value == nil and A._LastNumberValue then value = A._LastNumberValue(valueText) end
        return value
    end

    local function movementDirectionForText()
        if hasAny({ "left", "move left", "move it left", "nudge left", "shift left", "links" }) then return "left" end
        if hasAny({ "right", "move right", "move it right", "nudge right", "shift right", "rechts" }) then return "right" end
        if hasAny({ "up", "move up", "move it up", "nudge up", "shift up", "hoch", "oben" }) then return "up" end
        if hasAny({ "down", "move down", "move it down", "nudge down", "shift down", "runter", "unten" }) then return "down" end
        return nil
    end

    local function anchorValueForText(setting)
        if not hasAny({ "anchor", "anchor point", "put it", "place it", "position it", "top left", "top right", "bottom left", "bottom right" }) then return nil end
        local ordered = {
            { "top left", "TOPLEFT" }, { "upper left", "TOPLEFT" }, { "topleft", "TOPLEFT" },
            { "top right", "TOPRIGHT" }, { "upper right", "TOPRIGHT" }, { "topright", "TOPRIGHT" },
            { "bottom left", "BOTTOMLEFT" }, { "lower left", "BOTTOMLEFT" }, { "bottomleft", "BOTTOMLEFT" },
            { "bottom right", "BOTTOMRIGHT" }, { "lower right", "BOTTOMRIGHT" }, { "bottomright", "BOTTOMRIGHT" },
            { "center", "CENTER" }, { "centre", "CENTER" }, { "middle", "CENTER" },
            { "top", "TOP" }, { "bottom", "BOTTOM" }, { "left", "LEFT" }, { "right", "RIGHT" },
        }
        local allowed
        if type(setting and setting.values) == "table" then
            allowed = {}
            for i = 1, #setting.values do allowed[setting.values[i]] = true end
        end
        for i = 1, #ordered do
            if hasAny({ ordered[i][1] }) then
                local value = ordered[i][2]
                if not allowed or allowed[value] then return value end
            end
        end
        if parser and type(parser.ValueForRegistrySetting) == "function" then
            local value = parser.ValueForRegistrySetting(setting, text, text)
            if value ~= nil and (not allowed or allowed[value]) then return value end
        end
        return nil
    end

    local setting = item and item.setting
    if not (setting and setting.type == "boolean") then return nil end
    local direction = directionForText()
    local exactValue = exactNumberForText()
    local movementDirection = movementDirectionForText()
    local anchorIntent = hasAny({ "anchor", "anchor point", "put it", "place it", "position it", "top left", "top right", "bottom left", "bottom right" })
    local attrs, enumValue
    if anchorIntent and not hasAny({ "move", "nudge", "shift" }) then
        attrs = { "anchor" }
    elseif movementDirection == "left" or movementDirection == "right" then
        attrs = { "offsetX" }
        direction = movementDirection
    elseif movementDirection == "up" or movementDirection == "down" then
        attrs = { "offsetY" }
        direction = movementDirection
    elseif hasAny({ "layer", "z layer", "z level", "draw layer", "front", "back", "forward", "backward" }) then
        attrs = { "layer" }
        direction = hasAny({ "back", "backward", "lower layer", "behind" }) and "decrease" or "increase"
    elseif hasAny({ "wider", "narrower", "width", "wide" }) then
        attrs = { "width" }
        direction = direction or (hasAny({ "narrower" }) and "decrease" or "increase")
    elseif hasAny({ "taller", "shorter", "height", "high", "higher", "tall" }) then
        attrs = { "height" }
        direction = direction or (hasAny({ "shorter" }) and "decrease" or "increase")
    elseif exactValue == nil and tostring(setting.frameType or "") == "castbar" and tostring(setting.attribute or "") == "enabled" then
        attrs = { "width", "height" }
    else
        attrs = { "size" }
    end
    if exactValue ~= nil and (attrs[1] == "width" or attrs[1] == "height" or attrs[1] == "layer" or attrs[1] == "size") then
        direction = nil
    end
    if not direction and attrs[1] ~= "anchor" and exactValue == nil then return nil end

    if not (Registry and type(Registry.FindSettings) == "function") then return nil end
    local siblings, seen = {}, {}
    for i = 1, #attrs do
        local attr = attrs[i]
        local expectedType = attr == "anchor" and "enum" or "number"
        local exact = Registry:FindSettings({
            unit = setting.unit,
            frameType = setting.frameType,
            attribute = attr,
            type = expectedType,
        })
        for j = 1, #(exact or {}) do
            local candidate = exact[j]
            if tostring(setting.attribute or "") == "enabled" or labelMatches(setting, candidate, attr) then
                addUnique(siblings, seen, candidate)
            end
        end
    end
    if #siblings == 0 then
        local candidates = Registry:FindSettings({
            unit = setting.unit,
            frameType = setting.frameType,
            type = attrs[1] == "anchor" and "enum" or "number",
        })
        for i = 1, #attrs do
            local attr = attrs[i]
            for j = 1, #(candidates or {}) do
                local candidate = candidates[j]
                if labelMatches(setting, candidate, attr) then addUnique(siblings, seen, candidate) end
            end
        end
    end
    if #siblings == 0 then return nil end
    if #siblings > 1 and not (tostring(setting.frameType or "") == "castbar" and #attrs == 2 and #siblings == 2) then return nil end

    local changes = {}
    for i = 1, #siblings do
        local sibling = siblings[i]
        local attr = tostring(sibling.attribute or attrs[i] or attrs[1] or "")
        if sibling.type == "enum" then
            enumValue = anchorValueForText(sibling)
            if enumValue == nil then return nil end
            changes[#changes + 1] = {
                setting = sibling,
                value = enumValue,
                valueLabel = SettingResponseValueLabel(sibling, enumValue),
            }
        else
        local delta
        if exactValue ~= nil then
            changes[#changes + 1] = {
                setting = sibling,
                value = exactValue,
                valueLabel = SettingResponseValueLabel(sibling, exactValue),
            }
        else
        if tostring(sibling.frameType or "") == "castbar" and (attr == "width" or attr == "height") then
            if parser and type(parser.FrameResizeDelta) == "function" then
                delta = parser.FrameResizeDelta(followupAmountText(), attr, direction)
            else
                local amount = A._RelativeNumberAmountForText and A._RelativeNumberAmountForText(followupAmountText()) or nil
                if amount == nil then amount = attr == "width" and 25 or 5 end
                amount = tonumber(amount) or 0
                delta = direction == "decrease" and -math.abs(amount) or math.abs(amount)
            end
        elseif attr == "offsetX" or attr == "offsetY" then
            local amount = A._RelativeNumberAmountForText and A._RelativeNumberAmountForText(followupAmountText()) or nil
            if amount == nil then amount = tonumber(sibling.moveStep) or tonumber(sibling.moveAmount) or tonumber(sibling.step) or 10 end
            amount = tonumber(amount) or 0
            if direction == "left" or direction == "down" then amount = -math.abs(amount) else amount = math.abs(amount) end
            delta = amount
        elseif parser and type(parser.RelativeNumberDeltaForText) == "function" then
            delta = parser.RelativeNumberDeltaForText(sibling, followupAmountText())
        end
        if delta == nil then
            local amount = A._RelativeNumberAmountForText and A._RelativeNumberAmountForText(followupAmountText()) or nil
            if amount == nil then amount = tonumber(sibling.relativeStep) or tonumber(sibling.step) or 1 end
            amount = tonumber(amount) or 0
            delta = direction == "decrease" and -math.abs(amount) or math.abs(amount)
        end
        if delta == nil or delta == 0 then return nil end
        changes[#changes + 1] = {
            setting = sibling,
            relativeDelta = delta,
            direction = direction,
        }
        end
        end
    end
    if #changes == 0 then return nil end

    return {
        kind = "changes",
        changes = changes,
        bulkSafe = #changes > 1,
        label = "Adjust " .. AssistantSettingLabel(setting, "Assistant result"),
        summary = "Continues from an Assistant search result by changing a related size or placement setting.",
    }
end

local function PendingResultSettingChangeResult(text, item, index)
    if not (item and item.setting) then return nil end
    local parser = A.Parser or {}
    local synthetic = PendingResultSettingSyntheticText(text, item.setting, index)
    if not synthetic then
        local siblingPlan = AP.PendingResultRelatedSiblingPlan(text, item, index, parser)
        if siblingPlan then
            SetSelectedPendingResult(item, index)
            return A.ExecutePlan(siblingPlan)
        end
        return nil
    end
    SetSelectedPendingResult(item, index)

    if item.setting.type == "enum" then
        local labelNorm = NormalizeReply(item.label or item.setting.label or "")
        if labelNorm:find("color", 1, true) or labelNorm:find("colour", 1, true) then
            local literalColor
            for _, word in ipairs({ "red", "blue", "green", "yellow", "orange", "purple", "pink", "white", "black", "gray", "grey" }) do
                if ReplyHasPhrase(text, word) then
                    literalColor = word
                    break
                end
            end
            if literalColor and not (parser._ExactEnumValueForText and parser._ExactEnumValueForText(item.setting, literalColor)) then
                local choices = {}
                if type(item.setting.values) == "table" then
                    for i = 1, math.min(#item.setting.values, 8) do
                        choices[#choices + 1] = SettingValueLabel(item.setting, item.setting.values[i])
                    end
                end
                local label = AssistantSettingLabel(item.setting, "that option")
                local lines = {
                    "Result value clarification",
                    label .. " is a mode/choice setting, not a direct RGB color picker.",
                    "I did not treat '" .. tostring(literalColor) .. "' as permission to switch to a different color mode.",
                }
                if #choices > 0 then lines[#lines + 1] = "Supported values: " .. table.concat(choices, ", ") .. "." end
                lines[#lines + 1] = "Use an exact supported value, or search for the direct color setting you want."
                return {
                    text = table.concat(lines, "\n"),
                    result = "ambiguous",
                    summary = "Clarifies enum color-mode values before changing an Assistant search result.",
                }
            end
        end
    end

    local parsed
    if type(parser.ParseRegistryAliasCandidates) == "function" then
        parsed = parser.ParseRegistryAliasCandidates(NormalizeReply(synthetic), synthetic, { item.setting })
    end
    local plan = SafeSingleSettingChangePlan(parsed, item.setting)
    if not plan and type(parser.ValueForRegistrySetting) == "function" then
        local relativeDelta
        if item.setting.type == "number" and type(parser.RelativeNumberDeltaForText) == "function" then
            relativeDelta = parser.RelativeNumberDeltaForText(item.setting, synthetic)
        end
        local value
        if relativeDelta == nil then value = parser.ValueForRegistrySetting(item.setting, synthetic, synthetic) end
        if value ~= nil or relativeDelta ~= nil then
            plan = {
                kind = "changes",
                changes = {
                    {
                        setting = item.setting,
                        value = value,
                        relativeDelta = relativeDelta,
                        valueLabel = value ~= nil and SettingResponseValueLabel(item.setting, value) or nil,
                    },
                },
                label = AssistantSettingLabel(item.setting, "Assistant option change"),
                summary = "Changes an Assistant search result setting.",
            }
        end
    end
    if not plan then
        plan = AP.PendingResultRelatedSiblingPlan(text, item, index, parser)
    end
    if plan then return A.ExecutePlan(plan) end

    local settingLabel = AssistantSettingLabel(item.setting, "that option")
    return {
        text = "I found result " .. tostring(index or 1) .. " (" .. settingLabel .. "), but I need a concrete supported value. Try 'turn result " .. tostring(index or 1) .. " off', 'set result " .. tostring(index or 1) .. " to 20', or ask me to explain it first.",
        result = "ambiguous",
        summary = "Asks for a concrete value for an Assistant search result setting.",
    }
end

IsPendingResultCompareIntent = function(text)
    return ReplyHasPhrase(text, "compare")
        or ReplyHasPhrase(text, "difference")
        or ReplyHasPhrase(text, "differences")
        or ReplyHasPhrase(text, "vs")
        or ReplyHasPhrase(text, "versus")
        or ReplyHasPhrase(text, "which is better")
        or ReplyHasPhrase(text, "which one is better")
end

local function PendingResultIndexes(text, results)
    local normalized = NormalizeReply(text)
    local indexes, seen = {}, {}
    local function add(n)
        n = tonumber(n)
        if n and results[n] and not seen[n] then
            seen[n] = true
            indexes[#indexes + 1] = n
        end
    end
    if IsPendingResultCompareIntent(text) and CurrentSelectedPendingResult() and (
        normalized == "compare it"
        or normalized:sub(1, 11) == "compare it "
        or normalized == "compare this"
        or normalized:sub(1, 13) == "compare this "
        or normalized == "compare that"
        or normalized:sub(1, 13) == "compare that "
        or normalized == "difference between it"
        or normalized:sub(1, 22) == "difference between it "
        or normalized == "difference between this"
        or normalized:sub(1, 24) == "difference between this "
        or normalized == "difference between that"
        or normalized:sub(1, 24) == "difference between that "
    ) then
        add(CurrentSelectedPendingResult().index)
    end
    for n in normalized:gmatch("result%s+(%d+)") do add(n) end
    for n in normalized:gmatch("option%s+(%d+)") do add(n) end
    for n in normalized:gmatch("choice%s+(%d+)") do add(n) end
    if #indexes <= 1 and IsPendingResultCompareIntent(text) then
        for n in normalized:gmatch("(%d+)") do add(n) end
    end
    if IsPendingResultCompareIntent(text) then
        if ReplyHasPhrase(text, "first two")
            or ReplyHasPhrase(text, "first 2")
            or ReplyHasPhrase(text, "the first two")
            or ReplyHasPhrase(text, "the first 2")
            or ReplyHasPhrase(text, "top two")
            or ReplyHasPhrase(text, "top 2")
            or ReplyHasPhrase(text, "the top two")
            or ReplyHasPhrase(text, "the top 2") then
            add(1)
            add(2)
        end
        local padded = " " .. normalized .. " "
        local function compareNumberWordMentioned(word)
            word = NormalizeReply(word)
            if word == "" then return false end
            if padded:find(" compare " .. word .. " ", 1, true)
                or padded:find(" between " .. word .. " ", 1, true) then
                return true
            end
            for _, separator in ipairs({ " vs ", " versus ", " and ", " or ", " to " }) do
                if padded:find(" " .. word .. separator, 1, true)
                    or padded:find(separator .. word .. " ", 1, true) then
                    return true
                end
            end
            return false
        end
        local numberWords = AP.PendingResultNumberWords or {}
        for i = 1, #numberWords do
            local row = numberWords[i]
            if compareNumberWordMentioned(row.word) then add(row.index) end
        end
        local firstPositionTerms = AP.PendingResultListPositionTerms and AP.PendingResultListPositionTerms.first or {}
        for i = 1, #firstPositionTerms do
            if compareNumberWordMentioned(firstPositionTerms[i]) then add(1) end
        end
        local penultimatePositionTerms = AP.PendingResultListPositionTerms and AP.PendingResultListPositionTerms.penultimate or {}
        for i = 1, #penultimatePositionTerms do
            if compareNumberWordMentioned(penultimatePositionTerms[i]) then add(math.max(1, #results - 1)) end
        end
        local lastPositionTerms = AP.PendingResultListPositionTerms and AP.PendingResultListPositionTerms.last or {}
        for i = 1, #lastPositionTerms do
            if compareNumberWordMentioned(lastPositionTerms[i]) then add(#results) end
        end
        local selected = CurrentSelectedPendingResult()
        if selected then
            local selectedIndex = tonumber(selected.index)
            if selectedIndex then
                if AP.PendingResultAdjacentDirection and AP.PendingResultAdjacentDirection(text, "previous") then add(selectedIndex - 1) end
                if AP.PendingResultAdjacentDirection and AP.PendingResultAdjacentDirection(text, "next") then add(selectedIndex + 1) end
            end
        end
        if selected and HasSelectedResultPronoun(text) then add(selected.index) end
        for i = 1, #PENDING_RESULT_ORDINALS do
            local row = PENDING_RESULT_ORDINALS[i]
            if PendingResultOrdinalMentioned(text, row.word, true) or ReplyHasPhrase(text, row.word) then add(row.index) end
        end
        if #indexes == 0 and (
            ReplyHasPhrase(text, "compare them")
            or ReplyHasPhrase(text, "compare these")
            or ReplyHasPhrase(text, "compare those")
            or ReplyHasPhrase(text, "compare results")
            or ReplyHasPhrase(text, "compare the results")
            or ReplyHasPhrase(text, "compare listed results")
            or ReplyHasPhrase(text, "compare options")
            or ReplyHasPhrase(text, "compare the options")
            or ReplyHasPhrase(text, "compare listed options")
            or ReplyHasPhrase(text, "difference between them")
            or ReplyHasPhrase(text, "differences between them")
            or ReplyHasPhrase(text, "difference between the results")
            or ReplyHasPhrase(text, "differences between the results")
            or ReplyHasPhrase(text, "which is better")
            or ReplyHasPhrase(text, "which one is better")
        ) then
            add(1)
            add(2)
        end
    end
    return indexes
end

local function ResultListText(results)
    local lines = { "Which result do you mean?" }
    for i = 1, #(results or {}) do
        local item = results[i]
        local label = item and item.label or "Result"
        local page = PendingResultPageLabel(item)
        lines[#lines + 1] = tostring(i) .. ". " .. tostring(label) .. (page and page ~= "" and (" - " .. tostring(page)) or "")
    end
    return table.concat(lines, "\n")
end

local function PendingResultDecisionLine(index, item)
    if not item then return nil end
    local label = tostring(item.label or "MSUF result")
    local page = PendingResultPageLabel(item)
    local kind
    if item.setting then
        kind = tostring(item.setting.type or "setting") .. " setting"
    elseif item.action then
        kind = "Assistant task"
    elseif item.kind == "page" or item.page then
        kind = "MSUF page"
    else
        kind = tostring(item.kind or "help result")
    end
    return tostring(index) .. ". " .. label .. (page and (" - " .. tostring(page)) or "") .. " (" .. kind .. ")"
end

local function PendingResultDecisionText(item, index, results)
    if item then SetSelectedPendingResult(item, index) end
    local lines = { "Result selection guidance" }
    if item then
        lines[#lines + 1] = "You asked about result " .. tostring(index or 1) .. ". I will not apply it from a vague decision question."
        lines[#lines + 1] = PendingResultDecisionLine(index or 1, item)
        if item.setting then
            if item.setting.type == "boolean" then
                lines[#lines + 1] = "Use it only if you want that exact feature enabled or disabled."
            elseif item.setting.type == "number" then
                lines[#lines + 1] = "Use it only if you want to tune that exact size, offset, alpha, count, or amount."
            elseif item.setting.type == "color" then
                lines[#lines + 1] = "Use it only if you want to change that exact color."
            else
                lines[#lines + 1] = "Use it only if the label matches the exact MSUF option you meant."
            end
        end
        lines[#lines + 1] = "Safer next prompts: explain result " .. tostring(index or 1) .. "; open result " .. tostring(index or 1) .. "; current value."
    else
        lines[#lines + 1] = "I should not silently choose from the active result list. The first result is only the closest text match, not permission to change it."
        for i = 1, math.min(#(results or {}), 5) do
            local line = PendingResultDecisionLine(i, results[i])
            if line then lines[#lines + 1] = line end
        end
        lines[#lines + 1] = "Safer next prompts: explain result 1; compare result 1 and result 2; open result 1."
    end
    return { text = table.concat(lines, "\n"), result = "info", summary = "Gives safe guidance for choosing an Assistant search result." }
end

local function IsPendingResultNumericPronounChangeIntent(text)
    if not A._StartsWithResultCommandPronoun(text) then return false end
    local normalized = NormalizeReply(text)
    if normalized:find("%d") then return true end
    return ReplyHasPhrase(text, "bigger")
        or ReplyHasPhrase(text, "larger")
        or ReplyHasPhrase(text, "wider")
        or ReplyHasPhrase(text, "taller")
        or ReplyHasPhrase(text, "increase")
        or ReplyHasPhrase(text, "raise")
        or ReplyHasPhrase(text, "more")
        or ReplyHasPhrase(text, "grow")
        or ReplyHasPhrase(text, "smaller")
        or ReplyHasPhrase(text, "shorter")
        or ReplyHasPhrase(text, "narrower")
        or ReplyHasPhrase(text, "decrease")
        or ReplyHasPhrase(text, "lower")
        or ReplyHasPhrase(text, "less")
        or ReplyHasPhrase(text, "shrink")
end

local function PendingResultPronounChangeClarificationText(text, results)
    local colorPronoun = A._StartsWithResultCommandPronoun(text) and (
        ReplyHasPhrase(text, "red")
        or ReplyHasPhrase(text, "blue")
        or ReplyHasPhrase(text, "green")
        or ReplyHasPhrase(text, "yellow")
        or ReplyHasPhrase(text, "orange")
        or ReplyHasPhrase(text, "purple")
        or ReplyHasPhrase(text, "pink")
        or ReplyHasPhrase(text, "white")
        or ReplyHasPhrase(text, "black")
        or ReplyHasPhrase(text, "gray")
        or ReplyHasPhrase(text, "grey")
        or ReplyHasPhrase(text, "class color")
        or ReplyHasPhrase(text, "class colour")
        or ReplyHasPhrase(text, "transparent")
        or ReplyHasPhrase(text, "transparency")
        or ReplyHasPhrase(text, "color")
        or ReplyHasPhrase(text, "colour")
    )
    if colorPronoun then
        local colorCandidates = {}
        for i = 1, #(results or {}) do
            local item = results[i]
            local label = item and item.label and NormalizeReply(item.label) or ""
            if item and item.setting and (item.setting.type == "color" or label:find("color", 1, true) or label:find("colour", 1, true)) then
                colorCandidates[#colorCandidates + 1] = { index = i, item = item }
            end
        end
        local colorLines = {
            "Result change clarification",
            "I will not guess which listed result 'it' means for a color change.",
        }
        if #colorCandidates == 1 then
            colorLines[#colorLines + 1] = "The color-related candidate is:"
            colorLines[#colorLines + 1] = PendingResultDecisionLine(colorCandidates[1].index, colorCandidates[1].item)
            colorLines[#colorLines + 1] = "Use the result number if that is what you meant: explain result " .. tostring(colorCandidates[1].index) .. "; set result " .. tostring(colorCandidates[1].index) .. " to a supported color or value."
        elseif #colorCandidates > 1 then
            colorLines[#colorLines + 1] = "Color-related candidates:"
            for i = 1, math.min(#colorCandidates, 5) do
                colorLines[#colorLines + 1] = PendingResultDecisionLine(colorCandidates[i].index, colorCandidates[i].item)
            end
            colorLines[#colorLines + 1] = "Use the result number before changing one, for example: explain result " .. tostring(colorCandidates[1].index) .. "; set result " .. tostring(colorCandidates[1].index) .. " to a supported color or value."
        else
            colorLines[#colorLines + 1] = "I do not see a color-related setting in the active results. Search for the exact color setting or ask me to explain a result first."
        end
        return { text = table.concat(colorLines, "\n"), result = "ambiguous", summary = "Asks which Assistant search result should receive a color pronoun change." }
    end
    local togglePronoun = A._StartsWithResultCommandPronoun(text) and (
        ReplyHasPhrase(text, "turn it")
        or ReplyHasPhrase(text, "turn that")
        or ReplyHasPhrase(text, "turn this")
        or ReplyHasPhrase(text, "enable it")
        or ReplyHasPhrase(text, "enable that")
        or ReplyHasPhrase(text, "enable this")
        or ReplyHasPhrase(text, "disable it")
        or ReplyHasPhrase(text, "disable that")
        or ReplyHasPhrase(text, "disable this")
        or ReplyHasPhrase(text, "hide it")
        or ReplyHasPhrase(text, "hide that")
        or ReplyHasPhrase(text, "hide this")
        or ReplyHasPhrase(text, "show it")
        or ReplyHasPhrase(text, "show that")
        or ReplyHasPhrase(text, "show this")
        or ReplyHasPhrase(text, "toggle it")
        or ReplyHasPhrase(text, "toggle that")
        or ReplyHasPhrase(text, "toggle this")
    )
    if togglePronoun then
        local toggleCandidates = {}
        for i = 1, #(results or {}) do
            local item = results[i]
            if item and item.setting and item.setting.type == "boolean" then
                toggleCandidates[#toggleCandidates + 1] = { index = i, item = item }
            end
        end
        local toggleState = (ReplyHasPhrase(text, "off") or ReplyHasPhrase(text, "hide") or ReplyHasPhrase(text, "disable")) and "off" or "on"
        local toggleLines = {
            "Result change clarification",
            "I will not guess which listed result 'it' means for an on/off or visibility change.",
        }
        if #toggleCandidates == 1 then
            toggleLines[#toggleLines + 1] = "The on/off candidate is:"
            toggleLines[#toggleLines + 1] = PendingResultDecisionLine(toggleCandidates[1].index, toggleCandidates[1].item)
            toggleLines[#toggleLines + 1] = "Use the result number if that is what you meant: turn result " .. tostring(toggleCandidates[1].index) .. " on; turn result " .. tostring(toggleCandidates[1].index) .. " off."
        elseif #toggleCandidates > 1 then
            toggleLines[#toggleLines + 1] = "On/off candidates:"
            for i = 1, math.min(#toggleCandidates, 5) do
                toggleLines[#toggleLines + 1] = PendingResultDecisionLine(toggleCandidates[i].index, toggleCandidates[i].item)
            end
            toggleLines[#toggleLines + 1] = "Use the result number before changing one, for example: turn result " .. tostring(toggleCandidates[1].index) .. " " .. toggleState .. "."
        else
            toggleLines[#toggleLines + 1] = "I do not see an on/off setting in the active results. Ask 'explain result 1' or search for the exact visibility/toggle setting."
        end
        return { text = table.concat(toggleLines, "\n"), result = "ambiguous", summary = "Asks which Assistant search result should receive a toggle pronoun change." }
    end
    if not IsPendingResultNumericPronounChangeIntent(text) then return nil end
    local numeric = {}
    for i = 1, #(results or {}) do
        local item = results[i]
        if item and item.setting and item.setting.type == "number" then
            numeric[#numeric + 1] = { index = i, item = item }
        end
    end
    local relatedNumeric = {}
    if #numeric == 0 then
        local parser = A.Parser or {}
        for i = 1, #(results or {}) do
            local item = results[i]
            local plan = item and AP.PendingResultRelatedSiblingPlan(text, item, i, parser) or nil
            if plan and type(plan.changes) == "table" and #plan.changes > 0 then
                relatedNumeric[#relatedNumeric + 1] = { index = i, item = item, plan = plan }
            end
        end
    end

    local lines = {
        "Result change clarification",
        "I will not guess which listed result 'it' means for a numeric or size change.",
    }
    if #numeric == 1 then
        lines[#lines + 1] = "The numeric candidate is:"
        lines[#lines + 1] = PendingResultDecisionLine(numeric[1].index, numeric[1].item)
        lines[#lines + 1] = "Use the result number if that is what you meant: set result " .. tostring(numeric[1].index) .. " to 20; increase result " .. tostring(numeric[1].index) .. "."
    elseif #numeric > 1 then
        lines[#lines + 1] = "Numeric candidates:"
        for i = 1, math.min(#numeric, 4) do
            lines[#lines + 1] = PendingResultDecisionLine(numeric[i].index, numeric[i].item)
        end
        lines[#lines + 1] = "Use the result number before changing one, for example: set result " .. tostring(numeric[1].index) .. " to 20."
    elseif #relatedNumeric > 0 then
        lines[#lines + 1] = "These results have related size or placement settings:"
        for i = 1, math.min(#relatedNumeric, 4) do
            local entry = relatedNumeric[i]
            local detail = PendingResultDecisionLine(entry.index, entry.item)
            if detail then lines[#lines + 1] = detail end
        end
        lines[#lines + 1] = "Use the result number before changing one, for example: make result " .. tostring(relatedNumeric[1].index) .. " bigger; move result " .. tostring(relatedNumeric[1].index) .. " right 4."
    else
        lines[#lines + 1] = "I do not see a numeric setting in the active results. Ask 'explain result 1' or search for the exact size, width, height, offset, count, alpha, or scale setting."
    end
    return { text = table.concat(lines, "\n"), result = "ambiguous", summary = "Asks which Assistant search result should receive a numeric pronoun change." }
end

local function PendingResultSimpleExplainText(item, index, results)
    if not item then
        return { text = "Tell me which listed result you want simplified, for example 'explain result 1 simpler'.\n" .. ResultListText(results), result = "ambiguous", summary = "Asks which Assistant search result to simplify." }
    end
    SetSelectedPendingResult(item, index)

    local lines = { "Simple explanation" }
    local label = tostring(item.label or "MSUF result")
    local pageLabel = PendingResultPageLabel(item)
    if item.setting then
        lines[#lines + 1] = "Result " .. tostring(index or 1) .. " is an MSUF setting: " .. label .. "."
        if pageLabel then lines[#lines + 1] = "You can find it on " .. tostring(pageLabel) .. "." end
        if type(item.setting.get) == "function" then
            lines[#lines + 1] = "Right now it is " .. tostring(SettingValueLabel(item.setting, item.setting.get())) .. "."
        end
        local detail = CompactExplanationText(item.answer ~= "" and item.answer or item.description, 170)
        if detail then lines[#lines + 1] = detail end
        if item.setting.type == "boolean" then
            lines[#lines + 1] = "Say 'turn it on' or 'turn it off' if you want me to change it."
        elseif item.setting.type == "number" then
            lines[#lines + 1] = "Say 'set it to 18' with the number you want if you want me to change it."
        elseif item.setting.type == "color" then
            lines[#lines + 1] = "Say 'set it to red' with the color you want if you want me to change it."
        else
            lines[#lines + 1] = "Tell me the value you want, or say 'open result " .. tostring(index or 1) .. "' to inspect it first."
        end
    elseif item.action then
        lines[#lines + 1] = "Result " .. tostring(index or 1) .. " is an Assistant task: " .. label .. "."
        if pageLabel then lines[#lines + 1] = "It belongs to " .. tostring(pageLabel) .. "." end
        local detail = CompactExplanationText(item.answer ~= "" and item.answer or item.description, 170)
        if detail then lines[#lines + 1] = detail end
        lines[#lines + 1] = "Say 'run result " .. tostring(index or 1) .. "' if you want me to run it."
    elseif item.kind == "page" or item.page then
        lines[#lines + 1] = "Result " .. tostring(index or 1) .. " opens an MSUF page: " .. label .. "."
        if pageLabel then lines[#lines + 1] = "That page is " .. tostring(pageLabel) .. "." end
        lines[#lines + 1] = "Say 'open result " .. tostring(index or 1) .. "' to go there."
    else
        lines[#lines + 1] = "Result " .. tostring(index or 1) .. " is an MSUF help result: " .. label .. "."
        local detail = CompactExplanationText(item.answer ~= "" and item.answer or item.description, 200)
        if detail then lines[#lines + 1] = detail end
    end
    return { text = table.concat(lines, "\n"), result = "info", summary = "Explains an Assistant search result in simple language." }
end

local function PendingResultCurrentValueText(item, index, results)
    if not item then
        return { text = "Tell me which listed result you want the value for, for example 'current value of result 1'.\n" .. ResultListText(results), result = "ambiguous", summary = "Asks which Assistant search result value to show." }
    end
    SetSelectedPendingResult(item, index)

    local label = tostring(item.label or "MSUF result")
    if item.setting and type(item.setting.get) == "function" then
        local value = SettingValueLabel(item.setting, item.setting.get())
        local lines = {
            "Current value: " .. tostring(label) .. " is " .. tostring(value) .. ".",
        }
        if item.setting.type == "boolean" then
            lines[#lines + 1] = "You can ask: turn it on | turn it off | open result " .. tostring(index or 1)
        elseif item.setting.type == "number" then
            lines[#lines + 1] = "You can ask: set it to a number | open result " .. tostring(index or 1)
        elseif item.setting.type == "color" then
            lines[#lines + 1] = "You can ask: set it to a color | open result " .. tostring(index or 1)
        else
            lines[#lines + 1] = "You can ask: explain it | open result " .. tostring(index or 1)
        end
        return { text = table.concat(lines, "\n"), result = "info", summary = "Shows the current value for an Assistant search result." }
    end

    if item.action then
        return {
            text = "Result " .. tostring(index or 1) .. " (" .. label .. ") is an Assistant task, not a setting with a saved value. Ask 'run result " .. tostring(index or 1) .. "' to run it or 'explain it' for details.",
            result = "info",
            summary = "Explains that an Assistant search result action has no current value.",
        }
    end

    if item.kind == "page" or item.page then
        return {
            text = "Result " .. tostring(index or 1) .. " (" .. label .. ") opens an MSUF page, not a setting with a saved value. Ask 'open result " .. tostring(index or 1) .. "' to go there.",
            result = "info",
            summary = "Explains that an Assistant search result page has no current value.",
        }
    end

    return {
        text = "Result " .. tostring(index or 1) .. " (" .. label .. ") is not a setting with a saved value. Ask 'explain it' for details.",
        result = "info",
        summary = "Explains that an Assistant search result has no current value.",
    }
end

AP.PendingResultAllowedValuesText = AP.PendingResultAllowedValuesText or function(item, index, results)
    if not item then
        return {
            text = "Tell me which listed result you want supported values for, for example 'what can result 1 be?' or 'what values are supported for result 1'.\n" .. ResultListText(results),
            result = "ambiguous",
            summary = "Asks which Assistant search result values to show.",
        }
    end

    SetSelectedPendingResult(item, index)
    local label = tostring(item.label or "MSUF result")
    if not item.setting then
        if item.action then
            return {
                text = "Result " .. tostring(index or 1) .. " (" .. label .. ") is an Assistant task, not a setting with values. Ask 'run result " .. tostring(index or 1) .. "' to execute it or 'explain it' for details.",
                result = "info",
                summary = "Explains that an Assistant task result has no supported setting values.",
            }
        end
        if item.kind == "page" or item.page then
            return {
                text = "Result " .. tostring(index or 1) .. " (" .. label .. ") opens an MSUF page, not a setting with values. Ask 'open result " .. tostring(index or 1) .. "' to inspect that page.",
                result = "info",
                summary = "Explains that an Assistant page result has no supported setting values.",
            }
        end
        return {
            text = "Result " .. tostring(index or 1) .. " (" .. label .. ") is not a settable MSUF option. Ask 'explain it' for details.",
            result = "info",
            summary = "Explains that an Assistant search result has no supported setting values.",
        }
    end

    local setting = item.setting
    local settingLabel = AssistantSettingLabel(setting, label)
    local lines = { "Supported values for result " .. tostring(index or 1) .. ": " .. settingLabel .. "." }
    if type(setting.get) == "function" then
        lines[#lines + 1] = "Current value: " .. tostring(SettingValueLabel(setting, setting.get())) .. "."
    end

    if setting.type == "boolean" then
        lines[#lines + 1] = "Allowed states: enabled/on or disabled/off."
        lines[#lines + 1] = "Examples: turn it on | turn it off"
    elseif setting.type == "number" then
        local minValue = tonumber(setting.min)
        local maxValue = tonumber(setting.max)
        local stepValue = tonumber(setting.step or setting.increment)
        if minValue ~= nil and maxValue ~= nil then
            lines[#lines + 1] = "Allowed range: " .. tostring(minValue) .. " to " .. tostring(maxValue) .. "."
        elseif minValue ~= nil then
            lines[#lines + 1] = "Minimum value: " .. tostring(minValue) .. "."
        elseif maxValue ~= nil then
            lines[#lines + 1] = "Maximum value: " .. tostring(maxValue) .. "."
        else
            lines[#lines + 1] = "Use a numeric value. I will not choose one from this question alone."
        end
        if stepValue ~= nil and stepValue > 0 then lines[#lines + 1] = "Step: " .. tostring(stepValue) .. "." end
        lines[#lines + 1] = "Example: set it to " .. tostring(minValue or maxValue or 20)
    elseif setting.type == "color" then
        lines[#lines + 1] = "Use a supported color value, for example red, green, blue, white, black, gray, class color, or a direct color value if this setting accepts one."
        lines[#lines + 1] = "Example: set it to red"
    elseif type(setting.values) == "table" and #setting.values > 0 then
        local values = {}
        local limit = math.min(#setting.values, 12)
        for i = 1, limit do values[#values + 1] = SettingValueLabel(setting, setting.values[i]) end
        lines[#lines + 1] = "Supported values: " .. table.concat(values, ", ") .. (#setting.values > limit and ", ..." or "") .. "."
        lines[#lines + 1] = "Example: set it to " .. tostring(values[1] or "a supported value")
    else
        lines[#lines + 1] = "Use the exact text, media name, or menu value this option expects. I will not guess a free-form value from this question alone."
        lines[#lines + 1] = "Ask 'open result " .. tostring(index or 1) .. "' if you want to inspect the control first."
    end

    return { text = table.concat(lines, "\n"), result = "info", summary = "Shows supported values for an Assistant search result." }
end

local function PendingResultLocationLine(item, index)
    if not item then return nil end
    local label = tostring(item.label or "MSUF result")
    local pageLabel = PendingResultPageLabel(item)
    if item.setting then
        if pageLabel then return "Result " .. tostring(index or 1) .. ": " .. label .. " lives on " .. tostring(pageLabel) .. "." end
        return "Result " .. tostring(index or 1) .. ": " .. label .. " is an MSUF setting, but I do not know a direct page for it."
    end
    if item.action then
        if pageLabel then return "Result " .. tostring(index or 1) .. ": " .. label .. " belongs to " .. tostring(pageLabel) .. "." end
        return "Result " .. tostring(index or 1) .. ": " .. label .. " is an Assistant task."
    end
    if item.kind == "page" or item.page then
        if pageLabel then return "Result " .. tostring(index or 1) .. ": " .. label .. " opens " .. tostring(pageLabel) .. "." end
        return "Result " .. tostring(index or 1) .. ": " .. label .. " is an MSUF page."
    end
    if pageLabel then return "Result " .. tostring(index or 1) .. ": " .. label .. " is on " .. tostring(pageLabel) .. "." end
    return "Result " .. tostring(index or 1) .. ": " .. label .. "."
end

local function PendingResultLocationText(item, index, results, plural)
    if plural and type(results) == "table" and #results > 1 then
        local lines = { "Search result locations" }
        for i = 1, math.min(#results, 5) do
            local line = PendingResultLocationLine(results[i], i)
            if line then lines[#lines + 1] = line end
        end
        lines[#lines + 1] = "I did not change anything. Ask 'open result 1' to inspect one, or 'explain result 1' before changing it."
        return { text = table.concat(lines, "\n"), result = "info", summary = "Shows where Assistant search results live." }
    end

    if not item then
        return { text = "Tell me which listed result you mean, for example 'where is result 1?'.\n" .. ResultListText(results), result = "ambiguous", summary = "Asks which Assistant search result location to show." }
    end
    SetSelectedPendingResult(item, index)

    local label = tostring(item.label or "MSUF result")
    local lines = { "Result " .. tostring(index or 1) .. " location" }
    local line = PendingResultLocationLine(item, index)
    if line then lines[#lines + 1] = line end
    lines[#lines + 1] = "I did not change anything from this location question."
    if item.setting then
        local settingLabel = AssistantSettingLabel(item.setting, label)
        local example = "open result " .. tostring(index or 1) .. "; explain result " .. tostring(index or 1)
        if item.setting.type == "boolean" then
            example = example .. "; turn on " .. settingLabel
        elseif item.setting.type == "number" then
            example = example .. "; set " .. settingLabel .. " to 20"
        elseif item.setting.type == "color" then
            example = example .. "; set " .. settingLabel .. " to red"
        end
        lines[#lines + 1] = "Examples: " .. example .. "."
    elseif item.action then
        lines[#lines + 1] = "Examples: open result " .. tostring(index or 1) .. "; explain result " .. tostring(index or 1) .. "; run result " .. tostring(index or 1) .. "."
    else
        lines[#lines + 1] = "Examples: open result " .. tostring(index or 1) .. "; explain result " .. tostring(index or 1) .. "."
    end
    return { text = table.concat(lines, "\n"), result = "info", summary = "Shows where an Assistant search result lives." }
end

local function PendingResultWhyText(item, index, results)
    if not item then
        return { text = "Tell me which listed result you mean, for example 'why result 1?'.\n" .. ResultListText(results), result = "ambiguous", summary = "Asks which Assistant search result to explain by purpose." }
    end
    SetSelectedPendingResult(item, index)

    local label = tostring(item.label or "MSUF result")
    local pageLabel = PendingResultPageLabel(item)
    local lines = { "Why this result matters" }
    if item.setting then
        lines[#lines + 1] = "Result " .. tostring(index or 1) .. " is " .. label .. ", an MSUF setting" .. (pageLabel and (" on " .. tostring(pageLabel)) or "") .. "."
        local detail = CompactExplanationText(item.answer ~= "" and item.answer or item.description, 170)
        if detail then lines[#lines + 1] = detail end
        if type(item.setting.get) == "function" then
            lines[#lines + 1] = "Current value: " .. tostring(SettingValueLabel(item.setting, item.setting.get())) .. "."
        end
        if item.setting.type == "boolean" then
            lines[#lines + 1] = "Use it when you want that UI feature enabled or disabled."
            lines[#lines + 1] = "Ask 'turn it on' or 'turn it off' when you want me to change it."
        elseif item.setting.type == "number" then
            lines[#lines + 1] = "Use it when the exact size, spacing, position, alpha, or amount needs tuning."
            lines[#lines + 1] = "Ask 'set it to 18' with the number you want when you want me to change it."
        elseif item.setting.type == "color" then
            lines[#lines + 1] = "Use it when that UI element needs a different color."
            lines[#lines + 1] = "Ask 'set it to red' with the color you want when you want me to change it."
        else
            lines[#lines + 1] = "Use it when you want to change that specific part of the MSUF UI."
            lines[#lines + 1] = "Tell me the exact value or state before I change it."
        end
    elseif item.action then
        lines[#lines + 1] = "Result " .. tostring(index or 1) .. " is " .. label .. ", an Assistant task" .. (pageLabel and (" on " .. tostring(pageLabel)) or "") .. "."
        local detail = CompactExplanationText(item.answer ~= "" and item.answer or item.description, 180)
        if detail then lines[#lines + 1] = detail end
        lines[#lines + 1] = "It is an Assistant task, not a saved option."
        lines[#lines + 1] = "Use it when you want me to run that MSUF helper. Ask 'run result " .. tostring(index or 1) .. "' to execute it."
    elseif item.kind == "page" or item.page then
        lines[#lines + 1] = "Result " .. tostring(index or 1) .. " opens the MSUF page " .. label .. "."
        if pageLabel then lines[#lines + 1] = "That page is " .. tostring(pageLabel) .. "." end
        local detail = CompactExplanationText(item.answer ~= "" and item.answer or item.description, 180)
        if detail then lines[#lines + 1] = detail end
        lines[#lines + 1] = "Use it when you want to inspect or change related settings on that page."
    else
        lines[#lines + 1] = "Result " .. tostring(index or 1) .. " is an MSUF help result: " .. label .. "."
        local detail = CompactExplanationText(item.answer ~= "" and item.answer or item.description, 220)
        if detail then lines[#lines + 1] = detail end
        lines[#lines + 1] = "Use it when you need context before changing MSUF."
    end
    return { text = table.concat(lines, "\n"), result = "info", summary = "Explains why an Assistant search result matters." }
end

function A._PendingResultRelatedPageForItem(item)
    if type(item) ~= "table" then return nil end
    if item.page and item.page ~= "" then return item.page end
    if item.setting then return PendingSettingPage(item.setting) end
    return nil
end

function A._PendingResultRelatedIdentity(item)
    if type(item) ~= "table" then return nil end
    local settingKey = item.settingKey or (item.setting and item.setting.key)
    if settingKey then return "setting:" .. tostring(settingKey) end
    local actionKey = item.actionKey or (item.action and item.action.key)
    if actionKey then return "action:" .. tostring(actionKey) end
    if item.kind and item.key then return tostring(item.kind) .. ":" .. tostring(item.key) end
    return item.key and tostring(item.key) or nil
end

function A._PendingResultRelatedTokenSet(text)
    local out = {}
    local normalized = NormalizeReply(text)
    for token in normalized:gmatch("%S+") do
        if #token > 2 then out[token] = true end
    end
    return out
end

function A._PendingResultRelatedTokenOverlapScore(a, b)
    local aTokens = A._PendingResultRelatedTokenSet(a)
    local score = 0
    for token in NormalizeReply(b):gmatch("%S+") do
        if #token > 2 and aTokens[token] then score = score + 4 end
    end
    return score
end

function A._PendingResultRelatedItems(page, seed, limit)
    local knowledge = A.Knowledge
    if not (knowledge and type(knowledge.EnsureIndex) == "function") then return {} end
    local index = knowledge.EnsureIndex()
    local items = index and index.items or nil
    if type(items) ~= "table" then return {} end
    local seedIdentity = A._PendingResultRelatedIdentity(seed)
    local seedCategory = seed and seed.category
    local seedKind = seed and seed.kind
    local seedLabel = seed and seed.label
    local candidates = {}
    for i = 1, #items do
        if i % 64 == 0 and type(A.MaybeYield) == "function" then A.MaybeYield() end
        local item = items[i]
        if item and item.page == page and (item.kind == "setting" or item.kind == "action" or item.kind == "diagnostic") then
            local identity = A._PendingResultRelatedIdentity(item)
            if not seedIdentity or identity ~= seedIdentity then
                local score = 0
                if item.kind == "setting" then score = score + 30
                elseif item.kind == "action" or item.kind == "diagnostic" then score = score + 18
                end
                if seedCategory and item.category == seedCategory then score = score + 40 end
                if seedKind and item.kind == seedKind then score = score + 12 end
                if seedLabel then score = score + A._PendingResultRelatedTokenOverlapScore(seedLabel, item.label) end
                candidates[#candidates + 1] = { item = item, score = score, order = i }
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.score == b.score then return a.order < b.order end
        return a.score > b.score
    end)
    local out = {}
    limit = tonumber(limit) or 8
    for i = 1, math.min(limit, #candidates) do
        local item = NormalizeResultItem(candidates[i].item)
        if item then out[#out + 1] = item end
    end
    return out
end

function A._PendingResultRelatedCommonPage(results)
    local commonPage, count
    for i = 1, #(results or {}) do
        local page = A._PendingResultRelatedPageForItem(results[i])
        if page then
            if commonPage and commonPage ~= page then return nil end
            commonPage = page
            count = (count or 0) + 1
        end
    end
    return count and commonPage or nil
end

function A._PendingResultRelatedLine(index, item)
    local label = tostring(item and item.label or "MSUF result")
    local kind = item and item.kind and (" [" .. tostring(item.kind) .. "]") or ""
    local value = ""
    if item and item.setting and type(item.setting.get) == "function" then
        value = " - current value " .. tostring(SettingValueLabel(item.setting, item.setting.get()))
    end
    return tostring(index) .. ". " .. label .. kind .. value
end

function A._PendingResultRelatedText(item, index, results)
    if not item then
        local selected = CurrentSelectedPendingResult()
        if selected then
            item = selected
            index = selected.index
        end
    end
    local page = A._PendingResultRelatedPageForItem(item)
    if not page and #((results or {})) == 1 then
        item = results[1]
        index = 1
        page = A._PendingResultRelatedPageForItem(item)
    end
    if not page then page = A._PendingResultRelatedCommonPage(results) end
    if not page then
        return {
            text = "Tell me which listed result you want related options for, for example 'related options for result 1'.\n" .. ResultListText(results),
            result = "ambiguous",
            summary = "Asks which Assistant search result should be used for related options.",
        }
    end

    local related = A._PendingResultRelatedItems(page, item, 8)
    local pageLabel = (item and PendingResultPageLabel(item)) or PendingPageLabel(page)
    if #related == 0 then
        local label = item and item.label or pageLabel or page
        return {
            text = "I know the page for " .. tostring(label) .. ", but I did not find other indexed settings or tasks on that page. Ask 'open result " .. tostring(index or 1) .. "' to inspect it directly.",
            result = "info",
            summary = "No related Assistant search results found.",
        }
    end

    A.SetPendingResults(related)
    local lines = { "Related MSUF options on " .. tostring(pageLabel or page) }
    if item then lines[#lines + 1] = "Based on result " .. tostring(index or 1) .. ": " .. tostring(item.label or "MSUF result") .. "." end
    for i = 1, #related do lines[#lines + 1] = A._PendingResultRelatedLine(i, related[i]) end
    lines[#lines + 1] = "These are now the active results. You can ask: explain result 1 | open result 1 | set result 1 to a value."
    return { text = table.concat(lines, "\n"), result = "info", summary = "Shows related MSUF options for an Assistant search result." }
end

local function PendingResultExplainText(item, index, results)
    if not item then
        return { text = ResultListText(results), result = "ambiguous", summary = "Asks which Assistant search result to explain." }
    end
    SetSelectedPendingResult(item, index)
    local lines = { "Result " .. tostring(index or 1) .. ": " .. tostring(item.label or "MSUF result") .. "." }
    local pageLabel = PendingResultPageLabel(item)
    if pageLabel then lines[#lines + 1] = "Page: " .. tostring(pageLabel) .. "." end
    if item.kind and item.kind ~= "" then lines[#lines + 1] = "Type: " .. tostring(item.kind) .. "." end
    if item.answer and item.answer ~= "" then
        lines[#lines + 1] = tostring(item.answer)
    elseif item.description and item.description ~= "" then
        lines[#lines + 1] = tostring(item.description)
    end
    if item.setting then
        if type(item.setting.get) == "function" then
            lines[#lines + 1] = "Current value: " .. tostring(SettingValueLabel(item.setting, item.setting.get())) .. "."
        end
        local exampleLabel = AssistantSettingLabel(item.setting, "this option")
        if item.setting.type == "boolean" then
            lines[#lines + 1] = "You can ask: turn on " .. exampleLabel .. " | turn off " .. exampleLabel .. " | open result " .. tostring(index or 1)
        elseif item.setting.type == "number" then
            lines[#lines + 1] = "You can ask: set " .. exampleLabel .. " to a number | open result " .. tostring(index or 1)
        elseif item.setting.type == "color" then
            lines[#lines + 1] = "You can ask: set " .. exampleLabel .. " to red | open result " .. tostring(index or 1)
        else
            lines[#lines + 1] = "You can ask: open result " .. tostring(index or 1) .. " | change " .. exampleLabel
        end
    elseif item.action then
        lines[#lines + 1] = "This is an Assistant task. Ask for it by name when you want to run it."
    elseif item.kind == "page" then
        lines[#lines + 1] = "This is an MSUF page. Ask 'open result " .. tostring(index or 1) .. "' to go there."
    end
    return { text = table.concat(lines, "\n"), result = "info", summary = "Explains an Assistant search result." }
end

local function PendingResultValueLine(item)
    if not item then return nil end
    if item.setting and type(item.setting.get) == "function" then
        return "current value " .. tostring(SettingValueLabel(item.setting, item.setting.get()))
    end
    if item.action then return "runs an Assistant task" end
    if item.kind == "page" then return "opens an MSUF page" end
    if item.answer and item.answer ~= "" then return "help answer" end
    return nil
end

local function PendingResultSummaryLine(index, item)
    if not item then return nil end
    local parts = { "Result " .. tostring(index) .. ": " .. tostring(item.label or "MSUF result") }
    local pageLabel = PendingResultPageLabel(item)
    if pageLabel then parts[#parts + 1] = "page " .. tostring(pageLabel) end
    if item.kind and item.kind ~= "" then parts[#parts + 1] = "type " .. tostring(item.kind) end
    local value = PendingResultValueLine(item)
    if value then parts[#parts + 1] = value end
    return table.concat(parts, "; ")
end

local function PendingResultCompareText(indexes, results)
    if #indexes < 2 then
        return {
            text = "Tell me two listed results to compare, for example 'compare result 1 and result 2'.\n" .. ResultListText(results),
            result = "ambiguous",
            summary = "Asks which Assistant search results to compare.",
        }
    end
    local aIndex, bIndex = indexes[1], indexes[2]
    local a, b = results[aIndex], results[bIndex]
    local lines = {
        "Result comparison",
        PendingResultSummaryLine(aIndex, a),
        PendingResultSummaryLine(bIndex, b),
    }
    if a and b then
        if a.page ~= b.page then
            lines[#lines + 1] = "They live on different MSUF pages."
        elseif a.page then
            lines[#lines + 1] = "They live on the same MSUF page."
        end
        if a.kind ~= b.kind then
            lines[#lines + 1] = "They are different result types, so use 'open result " .. tostring(aIndex) .. "' or 'open result " .. tostring(bIndex) .. "' to inspect before changing anything."
        elseif a.kind == "setting" then
            lines[#lines + 1] = "Both are settings. Ask for a concrete value or on/off state before I change one."
        elseif a.action or b.action then
            lines[#lines + 1] = "At least one result is an Assistant task. Ask 'run result " .. tostring(aIndex) .. "' or 'run result " .. tostring(bIndex) .. "' when you want one executed."
        end
    end
    return { text = table.concat(lines, "\n"), result = "info", summary = "Compares Assistant search results." }
end

local function PendingResultOpenResult(item, index)
    if not item then
        return { text = "Tell me which result to open, for example 'open result 1'.", result = "ambiguous" }
    end
    SetSelectedPendingResult(item, index)
    local page = item.page
    local label = PendingResultPageLabel(item) or PendingPageLabel(page)
    if not page then
        return { text = "I can explain result " .. tostring(index or 1) .. ", but I do not know a direct MSUF page to open for it.", result = "info" }
    end
    local action = Registry and type(Registry.GetAction) == "function" and Registry:GetAction("open_page") or nil
    if not action then
        return { text = "Open " .. tostring(label or page) .. " to inspect result " .. tostring(index or 1) .. ".", result = "info" }
    end
    return A.ExecutePlan({
        kind = "action",
        action = action,
        args = { page = page, label = label },
        label = "Open " .. tostring(label or page),
        summary = "Opens the page for an Assistant search result.",
    })
end

local function PendingResultRunResult(item, index)
    if not item then
        return { text = "Tell me which result to run, for example 'run result 1'.", result = "ambiguous" }
    end
    SetSelectedPendingResult(item, index)
    if item.action then
        return A.ExecutePlan({
            kind = "action",
            action = item.action,
            args = {},
            label = AssistantActionLabel(item.action, item.label or "Assistant task"),
            summary = "Runs an Assistant search result.",
        })
    end
    if item.setting then
        local settingLabel = AssistantSettingLabel(item.setting, "that option")
        local example
        if item.setting.type == "boolean" then
            example = "'turn on " .. settingLabel .. "' or 'turn off " .. settingLabel .. "'"
        elseif item.setting.type == "number" then
            example = "'set " .. settingLabel .. " to 20'"
        elseif item.setting.type == "color" then
            example = "'set " .. settingLabel .. " to red'"
        else
            example = "'set " .. settingLabel .. " to a supported value'"
        end
        return {
            text = "Result " .. tostring(index or 1) .. " is a setting, so I will not run it without a concrete value. Tell me the value or state you want, for example " .. example .. ".",
            result = "info",
            summary = "Explains that a setting search result needs a concrete value.",
        }
    end
    if item.kind == "page" or item.page then
        return PendingResultOpenResult(item, index)
    end
    return {
        text = "I can explain result " .. tostring(index or 1) .. ", but it is not a runnable Assistant task.",
        result = "info",
        summary = "Explains that a search result is not runnable.",
    }
end

local function PendingResultFollowupResult(text, results)
    if not IsPendingResultReference(text) then return nil end
    local compareIndexes = PendingResultIndexes(text, results)
    local adjacentOutOfRange = AP.PendingResultAdjacentOutOfRange and AP.PendingResultAdjacentOutOfRange(text, results)
    if adjacentOutOfRange then return adjacentOutOfRange end
    local explicitOutOfRange = AP.PendingResultExplicitOutOfRange and AP.PendingResultExplicitOutOfRange(text, results)
    if explicitOutOfRange then return explicitOutOfRange end
    local adjacentReference = AP.PendingResultAdjacentDirection and AP.PendingResultAdjacentDirection(text) ~= nil
    local labelMatch = AP.PendingResultLabelMatch and AP.PendingResultLabelMatch(text, results) or nil
    if labelMatch and labelMatch.ambiguous and not IsPendingResultCompareIntent(text) then
        local lines = { "I found multiple active results matching '" .. tostring(labelMatch.query or "that") .. "'. Which one do you mean?" }
        for i = 1, math.min(#(labelMatch.candidates or {}), 5) do
            local candidate = labelMatch.candidates[i]
            local line = candidate and PendingResultSummaryLine(candidate.index, candidate.item) or nil
            if line then lines[#lines + 1] = line end
        end
        lines[#lines + 1] = "Use the result number, for example 'explain result " .. tostring(labelMatch.candidates and labelMatch.candidates[1] and labelMatch.candidates[1].index or 1) .. "'."
        return { text = table.concat(lines, "\n"), result = "ambiguous", summary = "Asks which Assistant search result label match to use." }
    end
    if IsPendingResultCompareIntent(text) then return PendingResultCompareText(compareIndexes, results) end
    local index = PendingResultIndex(text, results)
    local item = index and results[index] or nil
    if not item and HasSelectedResultPronoun(text) then
        local selected = CurrentSelectedPendingResult()
        if selected then
            item = selected
            index = selected.index
        end
    end
    if not item and CurrentSelectedPendingResult() and AP.PendingResultAllowedValuesIntent and AP.PendingResultAllowedValuesIntent(text, results) then
        local selected = CurrentSelectedPendingResult()
        if selected then
            item = selected
            index = selected.index
        end
    end
    if AP.PendingResultAllowedValuesIntent and AP.PendingResultAllowedValuesIntent(text, results) then
        return AP.PendingResultAllowedValuesText and AP.PendingResultAllowedValuesText(item, index, results)
    end
    if IsPendingResultDecisionIntent(text) then return PendingResultDecisionText(item, index, results) end
    if not item and not CurrentSelectedPendingResult() and #(results or {}) > 1 then
        local pronounChangeClarification = PendingResultPronounChangeClarificationText(text, results)
        if pronounChangeClarification then return pronounChangeClarification end
    end
    if not item and results[1] and (
        IsPendingResultOpenIntent(text)
        or IsPendingResultExplainIntent(text)
        or (AP.PendingResultValueIntent and AP.PendingResultValueIntent(text, results))
        or IsSimpleExplainIntent(text)
        or IsWhyReasonIntent(text)
        or IsPendingResultLocationIntent(text)
        or IsPendingResultDecisionIntent(text)
        or A._StartsWithResultCommandPronoun(text)
    ) then
        index = 1
        item = results[1]
    end
    if AP.PendingResultValueIntent and AP.PendingResultValueIntent(text, results) then return PendingResultCurrentValueText(item, index, results) end
    local settingChange = PendingResultSettingChangeResult(text, item, index)
    if settingChange then return settingChange end
    if IsPendingResultRunIntent(text) then return PendingResultRunResult(item, index) end
    if A._PendingResultRelatedIntent(text) then return A._PendingResultRelatedText(item, index, results) end
    if IsPendingResultLocationIntent(text) then return PendingResultLocationText(item, index, results, IsPendingResultPluralLocationIntent(text)) end
    if IsSimpleExplainIntent(text) then return PendingResultSimpleExplainText(item, index, results) end
    if IsWhyReasonIntent(text) then return PendingResultWhyText(item, index, results) end
    if IsPendingResultExplainIntent(text) then return PendingResultExplainText(item, index, results) end
    if adjacentReference then return PendingResultExplainText(item, index, results) end
    if IsPendingResultOpenIntent(text) or index then return PendingResultOpenResult(item, index) end
    return { text = ResultListText(results), result = "ambiguous", summary = "Asks which Assistant search result to use." }
end

local function SingleNaturalFixChoice(text, choices)
    if not IsNaturalFixApply(text) then return nil end
    local fixes = {}
    for i = 1, #(choices or {}) do
        local choice = choices[i]
        if choice and (choice.diagnosticFix == true or (choice.setting and choice.diagnosticFix ~= false)) then
            fixes[#fixes + 1] = choice
        end
    end
    return #fixes == 1 and fixes[1] or nil
end

ExecuteChoice = function(choice)
    if choice and type(choice.changes) == "table" and #choice.changes > 0 then
        return A.ExecutePlan({
            kind = "changes",
            changes = choice.changes,
            label = ChoiceDisplayLabel(choice) or "Assistant selected options",
            summary = choice.summary or "Assistant selected options.",
            bulkSafe = choice.bulkSafe,
        })
    end
    if choice and choice.setting then
        return A.ExecutePlan({ kind = "changes", changes = { choice }, label = "Assistant selected option" })
    end
    if choice and (choice.action or choice.actionKey) then
        local action = choice.action
        if not action and Registry and type(Registry.GetAction) == "function" then action = Registry:GetAction(choice.actionKey) end
        if not action then return { text = "That option list changed. Start that change again and I'll rebuild the list.", result = "failed" } end
        return A.ExecutePlan({
            kind = "action",
            action = action,
            args = choice.args or {},
            confirmRequired = choice.confirmRequired,
            label = ChoiceDisplayLabel(choice) or AssistantActionLabel(action, "Assistant selected task"),
            summary = choice.summary or "Assistant selected task.",
        })
    end
    return { text = "That option list changed. Start that change again and I'll rebuild the list.", result = "failed" }
end

local function RunApplies(changedSettings)
    local applied = {}
    for i = 1, #changedSettings do
        local setting = changedSettings[i]
        if setting and type(setting.apply) == "function" and not applied[setting.key] then
            applied[setting.key] = true
            setting.apply()
        end
    end
end

local function NormalizeTextSlot(slot)
    slot = tostring(slot or ""):lower()
    if slot == "left" then return "left" end
    if slot == "center" or slot == "centre" or slot == "middle" then return "center" end
    if slot == "right" then return "right" end
    return nil
end

local function TextContextFromSetting(setting, item)
    local area = item and item.textArea
    local slot = NormalizeTextSlot(item and item.textSlot)
    local attr = tostring(setting and setting.attribute or "")
    local key = tostring(setting and setting.key or "")
    local hay = attr .. " " .. key
    if not area then
        if hay:find("hpText", 1, true) or hay:find(".text", 1, true) or hay:find("healthText", 1, true) then
            area = "hp"
        elseif hay:find("powerText", 1, true) then
            area = "power"
        end
    end
    if not slot then
        if hay:find("Left", 1, true) or hay:find("textLeft", 1, true) then
            slot = "left"
        elseif hay:find("Center", 1, true) or hay:find("textCenter", 1, true) then
            slot = "center"
        elseif hay:find("Right", 1, true) or hay:find("textRight", 1, true) then
            slot = "right"
        end
    end
    if area ~= "hp" and area ~= "power" then return nil end
    if not slot then return nil end
    return area, slot
end

local function RememberTextChangeContext(setting, item, value)
    local area, slot = TextContextFromSetting(setting, item)
    if not area then return end
    local ctx = A.GetContext and A.GetContext()
    if not ctx then return end
    ctx.lastTextArea = area
    ctx.lastTextSlot = slot
    ctx.lastTextSetting = setting and setting.key
    ctx.lastTextValue = value
    ctx.lastTextFrameType = setting and setting.frameType
    ctx.lastTextUnit = setting and setting.unit
    ctx.selectedTextEditorTarget = {
        frameType = setting and setting.frameType,
        unit = setting and setting.unit,
        tab = area,
        slot = slot,
    }
end

local function BuildSerializable(changes)
    local out = {}
    for i = 1, #changes do
        local setting = changes[i].setting
        out[#out + 1] = {
            key = setting and setting.key,
            unit = setting and setting.unit,
            frameType = setting and setting.frameType,
            attribute = setting and setting.attribute,
            oldValue = changes[i].oldValue,
            value = changes[i].newValue,
            valueLabel = changes[i].valueLabel,
            relativeDelta = changes[i].relativeDelta,
            direction = changes[i].direction,
            textArea = changes[i].textArea,
            textSlot = changes[i].textSlot,
        }
    end
    return out
end

local function BuildUnchangedSerializable(changes)
    local out = {}
    local lastSetting, lastUnit, lastFrameType, lastCategory, lastValue
    for i = 1, #(changes or {}) do
        local item = changes[i]
        local setting = item and item.setting
        if setting then
            local currentValue = type(setting.get) == "function" and setting.get() or nil
            local targetValue = item.value
            if targetValue == nil then targetValue = currentValue end
            out[#out + 1] = {
                key = setting.key,
                unit = setting.unit,
                frameType = setting.frameType,
                attribute = setting.attribute,
                oldValue = currentValue,
                value = targetValue,
                valueLabel = item.valueLabel,
                relativeDelta = item.relativeDelta,
                direction = item.direction,
                textArea = item.textArea,
                textSlot = item.textSlot,
                unchanged = true,
            }
            lastSetting = setting.key
            lastUnit = setting.unit
            lastFrameType = setting.frameType
            lastCategory = setting.category
            lastValue = targetValue
        end
    end
    return out, lastSetting, lastUnit, lastFrameType, lastCategory, lastValue
end

local function RememberUnchangedChangeContext(plan, changes)
    if not (A and type(A.RememberAppliedBundle) == "function") then return end
    local serializable, lastSetting, lastUnit, lastFrameType, lastCategory, lastValue = BuildUnchangedSerializable(changes)
    if #serializable == 0 then return end
    A.RememberAppliedBundle({
        label = AssistantPlanLabel(plan, "Assistant change"),
        action = "change",
        lastSetting = lastSetting,
        lastUnit = lastUnit,
        lastFrameType = lastFrameType,
        lastCategory = lastCategory,
        lastValue = lastValue,
        serializable = serializable,
        undoAvailable = false,
    })
end

local function CopySerializableActionArgs(value, depth)
    depth = (depth or 0) + 1
    if depth > 4 then return nil end
    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then return value end
    if valueType ~= "table" then return nil end
    local out = {}
    for k, v in pairs(value) do
        local keyType = type(k)
        if keyType == "string" or keyType == "number" then
            local copied = CopySerializableActionArgs(v, depth)
            if copied ~= nil then out[k] = copied end
        end
    end
    return out
end

local function SettingLabel(setting)
    return AssistantSettingLabel(setting, "MSUF option")
end

local function DescribeChange(setting, undo)
    local oldLabel = SettingValueLabel(setting, undo and undo.oldValue)
    local newLabel = SettingResponseValueLabel(setting, undo and undo.newValue, undo and undo.valueLabel)
    return SettingLabel(setting) .. " from " .. tostring(oldLabel) .. " to " .. tostring(newLabel)
end

local UNDO_FOLLOWUP_HINT = "Next: ask for 'undo' to revert, or describe another follow-up change."
local LARGE_CHANGE_RELOAD_HINT = "Large visual changes can take a moment to settle; /reload is recommended after checking the result."

local function AppendUndoFollowupHint(text)
    text = tostring(text or "")
    if text:find(UNDO_FOLLOWUP_HINT, 1, true) then return text end
    return text .. "\n" .. UNDO_FOLLOWUP_HINT
end

local function AppendLargeChangeReloadHint(text)
    text = tostring(text or "")
    if text:find(LARGE_CHANGE_RELOAD_HINT, 1, true) then return text end
    return text .. "\n" .. LARGE_CHANGE_RELOAD_HINT
end

local function ChangedResponse(changedSettings, undoChanges)
    local count = #undoChanges
    if count == 1 then
        return "Done. I changed " .. DescribeChange(changedSettings[1], undoChanges[1]) .. "."
    end

    local visible = math.min(count, 5)
    local lines = { "Done. I changed " .. tostring(count) .. " MSUF options:" }
    for i = 1, visible do
        lines[#lines + 1] = tostring(i) .. ". " .. DescribeChange(changedSettings[i], undoChanges[i]) .. "."
    end
    if count > visible then
        lines[#lines + 1] = "And " .. tostring(count - visible) .. " more."
    end
    return table.concat(lines, "\n")
end

local function AlreadySetResponse(changes)
    if type(changes) == "table" and #changes == 1 then
        local setting = changes[1].setting
        if setting and type(setting.get) == "function" then
            return "Already set. " .. SettingLabel(setting) .. " is already " .. SettingValueLabel(setting, setting.get()) .. "."
        end
    end
    return "Already set. MSUF already uses that value."
end

local function RefreshedAlreadySetResponse(setting)
    if setting and type(setting.get) == "function" then
        return "Already set. " .. SettingLabel(setting) .. " is already " .. SettingValueLabel(setting, setting.get()) .. ". I refreshed it so the visible UI uses the current value."
    end
    return "Already set. I refreshed the related MSUF option so the visible UI uses the current value."
end

local function BuildChangeBundle(plan, changes, undoChanges, lastSetting, lastUnit, lastFrameType, lastCategory, lastValue)
    return {
        label = AssistantPlanLabel(plan, "Assistant change"),
        action = "change",
        changes = undoChanges,
        lastSetting = lastSetting,
        lastUnit = lastUnit,
        lastFrameType = lastFrameType,
        lastCategory = lastCategory,
        lastValue = lastValue,
        serializable = BuildSerializable(changes),
    }
end

local function PushAndRememberChangeBundle(plan, changes, undoChanges, lastSetting, lastUnit, lastFrameType, lastCategory, lastValue)
    local bundle = BuildChangeBundle(plan, changes, undoChanges, lastSetting, lastUnit, lastFrameType, lastCategory, lastValue)
    bundle.undoAvailable = A.PushUndo(bundle) == true
    A.RememberAppliedBundle(bundle)
    return bundle
end

local function RefreshChangeBundle(bundle, changes, lastSetting, lastUnit, lastFrameType, lastCategory, lastValue)
    if type(bundle) ~= "table" then return end
    bundle.lastSetting = lastSetting
    bundle.lastUnit = lastUnit
    bundle.lastFrameType = lastFrameType
    bundle.lastCategory = lastCategory
    bundle.lastValue = lastValue
    bundle.serializable = BuildSerializable(changes)
end

local function ExecuteChanges(plan)
    local changes = plan.changes or {}
    local undoChanges = {}
    local executedChanges = {}
    local changedSettings = {}
    local unchangedApplySettings = {}
    local lastSetting, lastUnit, lastFrameType, lastCategory, lastValue
    local undoBundle
    local requiresReload

    for i = 1, #changes do
        local item = changes[i]
        local setting = item.setting
        if setting and type(setting.get) == "function" and type(setting.set) == "function" then
            local oldValue = setting.get()
            local newValue = item.value
            if item.relativeDelta ~= nil then
                newValue = (tonumber(oldValue) or 0) + (tonumber(item.relativeDelta) or 0)
            end
            if setting.type == "number" and A.ClampNumber then
                newValue = A.ClampNumber(newValue, setting.min, setting.max, setting.step)
            elseif setting.type == "boolean" then
                newValue = newValue and true or false
            end
            if not ValuesEqual(setting, oldValue, newValue) then
                setting.set(newValue)
                local actualNewValue = newValue
                if setting.verifyAfterSet == true or setting.normalizesValue == true or setting.type == "color" then
                    actualNewValue = setting.get()
                end
                if not ValuesEqual(setting, oldValue, actualNewValue) then
                    local valueLabel = item.valueLabel
                    if not ValuesEqual(setting, newValue, actualNewValue) then
                        valueLabel = SettingValueLabel(setting, actualNewValue)
                    end
                    undoChanges[#undoChanges + 1] = {
                        key = setting.key,
                        oldValue = oldValue,
                        newValue = actualNewValue,
                        valueLabel = valueLabel,
                    }
                    item.oldValue = oldValue
                    item.newValue = actualNewValue
                    item.valueLabel = valueLabel
                    changedSettings[#changedSettings + 1] = setting
                    lastSetting = setting.key
                    lastUnit = setting.unit
                    lastFrameType = setting.frameType
                    lastCategory = setting.category
                    lastValue = actualNewValue
                    if setting.requiresReload == true then requiresReload = true end
                    if item.direction then A.SetContextValue("lastDirection", item.direction) end
                    RememberTextChangeContext(setting, item, actualNewValue)
                    executedChanges[#executedChanges + 1] = item
                    if not undoBundle then
                        undoBundle = PushAndRememberChangeBundle(plan, executedChanges, undoChanges, lastSetting, lastUnit, lastFrameType, lastCategory, lastValue)
                    else
                        RefreshChangeBundle(undoBundle, executedChanges, lastSetting, lastUnit, lastFrameType, lastCategory, lastValue)
                        A.RememberAppliedBundle(undoBundle)
                    end
                elseif setting.applyWhenUnchanged == true then
                    unchangedApplySettings[#unchangedApplySettings + 1] = setting
                end
            elseif setting.applyWhenUnchanged == true then
                unchangedApplySettings[#unchangedApplySettings + 1] = setting
            end
        end
    end

    if #undoChanges == 0 then
        RememberUnchangedChangeContext(plan, changes)
        if #unchangedApplySettings > 0 then
            RunApplies(unchangedApplySettings)
            local first = unchangedApplySettings[1]
            return { text = RefreshedAlreadySetResponse(first), result = "applied", summary = plan.summary }
        end
        return { text = AlreadySetResponse(changes), result = "applied", summary = plan.summary }
    end

    if not undoBundle then
        undoBundle = PushAndRememberChangeBundle(plan, executedChanges, undoChanges, lastSetting, lastUnit, lastFrameType, lastCategory, lastValue)
    else
        RefreshChangeBundle(undoBundle, executedChanges, lastSetting, lastUnit, lastFrameType, lastCategory, lastValue)
        A.RememberAppliedBundle(undoBundle)
    end

    local text = ChangedResponse(changedSettings, undoChanges)
    if requiresReload then text = text .. " Reload the UI for this change to fully take effect." end
    if not requiresReload and #undoChanges >= 6 then text = AppendLargeChangeReloadHint(text) end
    RunApplies(changedSettings)
    text = AppendUndoFollowupHint(text)
    return { text = text, result = "applied", summary = plan.summary }
end

local function ActionResponse(action, plan, message)
    message = Trim(message or "")
    if message == "" or message == "Done." then
        return "Done. I ran " .. AssistantPlanLabel(plan, AssistantActionLabel(action, "that MSUF task")) .. "."
    end
    if message:find("^Done%.") or message:find("^Already set%.") then return message end
    return "Done. " .. message
end

local function ExecuteAction(plan)
    local action = plan.action
    if not (action and type(action.run) == "function") then
        return { text = "Open the MSUF menu first so I can run that task.", result = "failed", summary = plan.summary }
    end
    local before
    local beforeProfile
    local captureProfile = action.captureProfileSnapshot and A.CaptureProfileSnapshot
    local captureSnapshot = action.captureSnapshot and not captureProfile and A.CaptureSnapshot
    local snapshotStart = PerfNowMs()
    if captureSnapshot then before = A.CaptureSnapshot() end
    if captureProfile then beforeProfile = A.CaptureProfileSnapshot(action.key, plan.args or {}) end
    A.RecordPerfSample("assistant.snapshot.before", snapshotStart, action.key)
    local ok, message = action.run(plan.args or {})
    if not ok then
        return { text = message or "I kept that task as it was.", result = "failed", summary = plan.summary }
    end
    local undoAvailable = false
    if before or beforeProfile then
        snapshotStart = PerfNowMs()
        local after = captureSnapshot and A.CaptureSnapshot() or nil
        local afterProfile = captureProfile and A.CaptureProfileSnapshot(action.key, plan.args or {}) or nil
        A.RecordPerfSample("assistant.snapshot.after", snapshotStart, action.key)
        undoAvailable = A.PushUndo({
            label = AssistantPlanLabel(plan, AssistantActionLabel(action, "Assistant task")),
            action = action.key,
            beforeSnapshot = before,
            afterSnapshot = after,
            beforeProfileSnapshot = beforeProfile,
            afterProfileSnapshot = afterProfile,
        })
    end
    local text = ActionResponse(action, plan, message)
    local actionArgs
    if action.key == "copy_unit" or action.key == "copy_group" then
        actionArgs = CopySerializableActionArgs(plan.args or {})
    end
    A.RememberAppliedBundle({
        action = action.key,
        actionLabel = AssistantPlanLabel(plan, AssistantActionLabel(action, "Assistant task")),
        actionMessage = text,
        undoAvailable = undoAvailable,
        actionArgs = actionArgs,
        serializable = {},
    })
    if undoAvailable then text = AppendUndoFollowupHint(text) end
    return { text = text, result = "applied", summary = plan.summary }
end

function A.ShowLargeTextPanel(spec)
    if type(spec) ~= "table" then return false end
    A.largeTextPanel = spec
    if type(A.RequestRefreshUI) == "function" then
        A.RequestRefreshUI("assistant.large_text.show")
    elseif type(A.RefreshUI) == "function" then
        A.RefreshUI()
    end
    return true
end

function A.CloseLargeTextPanel()
    A.largeTextPanel = nil
    if type(A.RequestRefreshUI) == "function" then
        A.RequestRefreshUI("assistant.large_text.close")
    elseif type(A.RefreshUI) == "function" then
        A.RefreshUI()
    end
end

local function ClearPendingConfirmationContext()
    local ctx = A.GetContext and A.GetContext()
    if ctx then ctx.pendingConfirmation = nil end
end

local function NormalizePlanResult(result)
    if type(result) ~= "table" then return result end
    if result.status == nil and result.result ~= nil then result.status = result.result end
    if result.result == nil and result.status ~= nil then result.result = result.status end
    if type(result.searchResults) == "table" and type(A.SetPendingResults) == "function" then
        A.SetPendingResults(result.searchResults)
    end
    return result
end

function A.ExecutePlan(plan, opts)
    opts = opts or {}
    if type(plan) ~= "table" then return NormalizePlanResult({ text = "Which frame, page, or option do you want me to change?", result = "failed" }) end
    if PlanNeedsConfirmation(plan) and opts.confirmed ~= true then
        A.pendingConfirmation = plan
        ClearPendingConfirmationContext()
        return NormalizePlanResult({ text = ConfirmationText(plan), result = "confirmation_needed", summary = plan.summary })
    end
    if InCombat() and AnyCombatUnsafe(plan) and opts.fromQueue ~= true then
        A.QueuePlan(plan)
        return NormalizePlanResult({ text = "I will apply this after combat ends: " .. AssistantPlanLabel(plan, "Assistant change") .. ".", result = "queued", summary = plan.summary })
    end
    if plan.kind == "changes" then return NormalizePlanResult(ExecuteChanges(plan)) end
    if plan.kind == "action" then return NormalizePlanResult(ExecuteAction(plan)) end
    return NormalizePlanResult({ text = "Which page and option do you want me to use? Example: 'set target cast bar height to 20'.", result = "failed", summary = plan.summary })
end

function A._PendingConfirmationPage(plan)
    if type(plan) ~= "table" then return nil end
    if type(plan.args) == "table" and type(plan.args.page) == "string" and plan.args.page ~= "" then return plan.args.page end
    local actionKey = tostring(plan.actionKey or (plan.action and plan.action.key) or ""):lower()
    local label = NormalizeReply((plan.label or "") .. " " .. (plan.summary or "") .. " " .. (plan.action and plan.action.label or ""))
    if actionKey:find("profile", 1, true) or label:find("profile", 1, true) then return "profiles" end
    if actionKey:find("aura", 1, true) or label:find("aura", 1, true) or label:find("buff", 1, true) or label:find("debuff", 1, true) then return "auras3" end
    if actionKey:find("castbar", 1, true) or label:find("castbar", 1, true) or label:find("cast bar", 1, true) then return "opt_castbar" end
    if actionKey:find("editmode", 1, true) or label:find("edit mode", 1, true) then return "home" end
    if type(plan.changes) == "table" and plan.changes[1] and plan.changes[1].setting then
        return PendingSettingPage(plan.changes[1].setting)
    end
    return nil
end

function A._PendingConfirmationQuestionIntent(text)
    local normalized = NormalizeReply(text)
    if normalized == "why" or normalized == "what" or normalized == "details" or normalized == "more details" then return true end
    return ReplyHasPhrase(text, "what will you do")
        or ReplyHasPhrase(text, "what are you doing")
        or ReplyHasPhrase(text, "what are you going to do")
        or ReplyHasPhrase(text, "what does this do")
        or ReplyHasPhrase(text, "what does it do")
        or ReplyHasPhrase(text, "what will change")
        or ReplyHasPhrase(text, "what changes")
        or ReplyHasPhrase(text, "what happens")
        or ReplyHasPhrase(text, "what am i confirming")
        or ReplyHasPhrase(text, "tell me more")
        or ReplyHasPhrase(text, "more details")
        or IsValueQuestionIntent(text)
        or IsWhyReasonIntent(text)
        or IsSimpleExplainIntent(text)
end

function A._PendingConfirmationChangeLines(plan)
    local lines = {}
    if type(plan) ~= "table" or type(plan.changes) ~= "table" then return lines end
    for i = 1, math.min(#plan.changes, 6) do
        local change = plan.changes[i]
        local setting = change and change.setting
        if setting then
            local label = AssistantSettingLabel(setting, "MSUF option")
            local current = type(setting.get) == "function" and SettingValueLabel(setting, setting.get()) or nil
            local target
            if change.relativeDelta ~= nil then
                local delta = tonumber(change.relativeDelta) or 0
                target = (delta >= 0 and "+" or "") .. tostring(delta)
            elseif change.value ~= nil or change.valueLabel ~= nil then
                target = SettingResponseValueLabel(setting, change.value, change.valueLabel)
            end
            if current and target then
                lines[#lines + 1] = "- " .. label .. ": " .. tostring(current) .. " -> " .. tostring(target)
            elseif target then
                lines[#lines + 1] = "- " .. label .. ": set to " .. tostring(target)
            else
                lines[#lines + 1] = "- " .. label
            end
        end
    end
    if #plan.changes > #lines then lines[#lines + 1] = "- " .. tostring(#plan.changes - #lines) .. " more changes are waiting." end
    return lines
end

function A._PendingConfirmationExplainResult(plan)
    local label = AssistantPlanLabel(plan, "this pending action")
    local lines = { "Pending confirmation", "I am waiting before applying: " .. tostring(label) .. "." }
    if type(plan) == "table" and type(plan.summary) == "string" and plan.summary ~= "" then
        lines[#lines + 1] = "What it does: " .. tostring(plan.summary)
    elseif type(plan) == "table" and plan.action then
        lines[#lines + 1] = "What it does: runs the MSUF task " .. AssistantActionLabel(plan.action, "Assistant task") .. "."
    end
    local changes = A._PendingConfirmationChangeLines(plan)
    if #changes > 0 then
        lines[#lines + 1] = "Changes waiting:"
        for i = 1, #changes do lines[#lines + 1] = changes[i] end
    end
    local page = A._PendingConfirmationPage(plan)
    if page then lines[#lines + 1] = "Page: " .. tostring(PendingPageLabel(page)) .. "." end
    lines[#lines + 1] = "Why I am asking: this can change profile data, run an Assistant task, or affect several MSUF options, so I only continue after a clear yes/apply."
    lines[#lines + 1] = "Answer 'yes' to apply it, or 'cancel' to leave MSUF unchanged."
    return { text = table.concat(lines, "\n"), result = "confirmation_needed", summary = "Explains a pending Assistant confirmation." }
end

function A._PendingConfirmationOpenResult(plan)
    local page = A._PendingConfirmationPage(plan)
    if not page then
        return {
            text = "I do not know a direct MSUF page for this pending confirmation yet.\n" .. A._PendingConfirmationExplainResult(plan).text,
            result = "confirmation_needed",
            summary = "Explains a pending Assistant confirmation without a direct page.",
        }
    end
    local action = Registry and type(Registry.GetAction) == "function" and Registry:GetAction("open_page") or nil
    if not action then
        return {
            text = "Open " .. tostring(PendingPageLabel(page)) .. " to inspect this before confirming.\nThe confirmation is still waiting. Answer 'yes' to apply it, or 'cancel' to leave MSUF unchanged.",
            result = "confirmation_needed",
            summary = "Shows where to inspect a pending Assistant confirmation.",
        }
    end
    local result = A.ExecutePlan({
        kind = "action",
        action = action,
        args = { page = page, label = PendingPageLabel(page) },
        label = "Open " .. tostring(PendingPageLabel(page)),
        summary = "Opens the page for a pending Assistant confirmation.",
    })
    if type(result) == "table" then
        result.result = result.result or result.status or "confirmation_needed"
        result.status = result.status or result.result
        result.summary = "Opens the page for a pending Assistant confirmation."
        result.text = tostring(result.text or "") .. "\nThe confirmation is still waiting. Answer 'yes' to apply it, or 'cancel' to leave MSUF unchanged."
    end
    return result
end

function A._PendingConfirmationFollowupResult(text, plan)
    if IsPendingResultOpenIntent(text)
        or ReplyHasPhrase(text, "open it")
        or ReplyHasPhrase(text, "open this")
        or ReplyHasPhrase(text, "open that")
        or ReplyHasPhrase(text, "show me where")
        or ReplyHasPhrase(text, "take me there")
        or ReplyHasPhrase(text, "go there") then
        return A._PendingConfirmationOpenResult(plan)
    end
    if A._PendingConfirmationQuestionIntent(text) then return A._PendingConfirmationExplainResult(plan) end
    return nil
end

local function HandlePending(text)
    if type(A.HandlePendingFlow) == "function" then
        local flowResult = A.HandlePendingFlow(text)
        if flowResult then return flowResult end
    end
    if A.pendingConfirmation then
        if LooksLikeUndoRedoCommand(text) then
            A.pendingConfirmation = nil
            ClearPendingConfirmationContext()
            return nil
        end
        if IsChoiceAbort(text) then
            A.pendingConfirmation = nil
            ClearPendingConfirmationContext()
            return { text = "Cancelled. I kept the options as they were.", result = NormalizeReply(text) == "cancel" and "applied" or "failed" }
        end
        local confirmationFollowup = A._PendingConfirmationFollowupResult(text, A.pendingConfirmation)
        if confirmationFollowup then return confirmationFollowup end
        if IsConfirmationApply(text) then
            local plan = A.pendingConfirmation
            A.pendingConfirmation = nil
            ClearPendingConfirmationContext()
            return A.ExecutePlan(plan, { confirmed = true })
        end
        return { text = "Yes, do it, or apply will continue. Cancel stops it.", result = "confirmation_needed" }
    else
        ClearPendingConfirmationContext()
    end
    local choices = CurrentPendingChoices()
    if choices then
        if LooksLikeUndoRedoCommand(text) then
            ClearPendingChoices()
            return nil
        end
        if IsChoiceAbort(text) then
            ClearPendingChoices()
            return { text = "Cancelled. MSUF stayed as it was.", result = "info" }
        end
        local choiceExplain = PendingChoiceExplainResult(text, choices)
        if choiceExplain then return choiceExplain end
        local choiceOpen = PendingChoiceOpenFollowupResult(text, choices)
        if choiceOpen then return choiceOpen end
        if NormalizeReply(text) == "what" then
            return { text = "Which listed option do you want me to use? A number, label, or unit name is enough.", result = "ambiguous" }
        end
        if LooksLikeFreshCommand(text) then
            ClearPendingChoices()
            return nil
        end
        if #choices == 1 and IsSingleChoiceApply(text) then
            local choice = choices[1]
            ClearPendingChoices()
            return ExecuteChoice(choice)
        end
        local naturalFix = SingleNaturalFixChoice(text, choices)
        if naturalFix then
            ClearPendingChoices()
            return ExecuteChoice(naturalFix)
        end
        local choice = FindChoice(text, choices)
        if choice then
            ClearPendingChoices()
            return ExecuteChoice(choice)
        end
        return { text = "Which listed option do you want me to use? A number, label, or unit name is enough.", result = "ambiguous" }
    end
    local results = CurrentPendingResults()
    if results then
        if IsChoiceAbort(text) then
            ClearPendingResults()
            return { text = "Cancelled. I cleared the last search results.", result = "info" }
        end
        local resultFollowup = PendingResultFollowupResult(text, results)
        if resultFollowup then
            A._pendingResultFollowupHandled = true
            return resultFollowup
        end
        if LooksLikeFreshCommand(text) then ClearSelectedPendingResult() end
    end
    return nil
end

function A.HandleCommandInput(text)
    local pending = HandlePending(text)
    if pending then return NormalizePlanResult(pending) end

    local parsed = A.Parse and A.Parse(text) or nil
    if not parsed then return NormalizePlanResult({ text = "Which frame, page, or option do you want me to change?", result = "failed" }) end

    if parsed.kind == "empty" then return nil end
    if parsed.kind == "undo" then
        local ok, message = A.UndoLast()
        return NormalizePlanResult({ text = message, result = ok and "applied" or "failed" })
    end
    if parsed.kind == "redo" then
        local ok, message = A.RedoLast()
        return NormalizePlanResult({ text = message, result = ok and "applied" or "failed" })
    end
    if parsed.kind == "ambiguous" then
        A.pendingChoices = parsed.choices or {}
        local ctx = A.GetContext and A.GetContext()
        if ctx then ctx.pendingChoices = SerializeChoices(A.pendingChoices) end
        return NormalizePlanResult({ text = ChoiceText(A.pendingChoices), result = "ambiguous", summary = parsed.summary })
    end
    if parsed.kind == "unknown" then
        local result = { text = parsed.text or "Which page and option do you want me to use? Example: 'set target cast bar height to 20'.", result = parsed.status or "failed", kind = "unknown" }
        if A.RecordNoMatch and type(A.RouteInput) ~= "function" then A.RecordNoMatch(text, result, "parser") end
        return NormalizePlanResult(result)
    end
    if parsed.kind == "unsupported" then
        return NormalizePlanResult({ text = parsed.text or "I don't see an MSUF option for that request yet.", result = parsed.status or "info", kind = "unsupported", summary = parsed.summary })
    end
    if parsed.kind == "answer" then
        return NormalizePlanResult({ text = parsed.text or "", result = parsed.status or "info", summary = parsed.summary })
    end
    return NormalizePlanResult(A.ExecutePlan(parsed))
end

local function CombatSubmitResult()
    return {
        text = "MSUF menu changes have to wait until combat ends. Ask for the same change after combat ends.",
        status = "combat",
        summary = "Assistant menu changes wait until combat ends.",
    }
end

local function ShouldClearPendingResultsAfterHandledInput(result, hadPendingResults, pendingResultReply)
    if not hadPendingResults or pendingResultReply then return false end
    if type(result) ~= "table" then return false end
    if type(result.searchResults) == "table" then return false end
    local status = tostring(result.status or result.result or result.kind or "")
    if status == "" then return false end
    if status == "failed" or status == "unknown" or status == "busy" or status == "combat" then return false end
    return true
end

function A.HandleInput(text)
    if InCombat() then return NormalizePlanResult(CombatSubmitResult()) end
    local hadPendingResults = CurrentPendingResults() ~= nil
    A._pendingResultFollowupHandled = nil
    local result
    if type(A.RouteInput) == "function" then
        result = NormalizePlanResult(A.RouteInput(text, A.HandleCommandInput))
    else
        result = NormalizePlanResult(A.HandleCommandInput(text))
    end
    local pendingResultReply = A._pendingResultFollowupHandled == true
    A._pendingResultFollowupHandled = nil
    if ShouldClearPendingResultsAfterHandledInput(result, hadPendingResults, pendingResultReply) then ClearPendingResults() end
    return result
end

function A.IsBusy()
    return A._busy == true
end

function A.GetBusyText()
    return tostring(A._busyText or "I am working on that")
end

function A.SetBusy(active, text)
    A._busy = active and true or false
    A._busyText = A._busy and Trim(text or "I am working on that") or nil
    A._busySerial = (tonumber(A._busySerial) or 0) + 1
    if type(A.RequestRefreshUI) == "function" then
        A.RequestRefreshUI("assistant.busy")
    elseif type(A.RefreshUI) == "function" then
        A.RefreshUI()
    end
    return A._busy
end

-- Build incrementally; this chunk has many top-level locals, and WoW's Lua 5.1
-- parser can exceed its temporary register limit on a large table literal here.
AP.BATCH_COMMAND_STARTERS = {}
AP.BATCH_COMMAND_STARTERS[1] = "set"
AP.BATCH_COMMAND_STARTERS[2] = "change"
AP.BATCH_COMMAND_STARTERS[3] = "make"
AP.BATCH_COMMAND_STARTERS[4] = "turn"
AP.BATCH_COMMAND_STARTERS[5] = "enable"
AP.BATCH_COMMAND_STARTERS[6] = "disable"
AP.BATCH_COMMAND_STARTERS[7] = "show"
AP.BATCH_COMMAND_STARTERS[8] = "hide"
AP.BATCH_COMMAND_STARTERS[9] = "move"
AP.BATCH_COMMAND_STARTERS[10] = "nudge"
AP.BATCH_COMMAND_STARTERS[11] = "shift"
AP.BATCH_COMMAND_STARTERS[12] = "reset"
AP.BATCH_COMMAND_STARTERS[13] = "copy"
AP.BATCH_COMMAND_STARTERS[14] = "add"
AP.BATCH_COMMAND_STARTERS[15] = "put"
AP.BATCH_COMMAND_STARTERS[16] = "clear"
AP.BATCH_COMMAND_STARTERS[17] = "increase"
AP.BATCH_COMMAND_STARTERS[18] = "decrease"
AP.BATCH_COMMAND_STARTERS[19] = "raise"
AP.BATCH_COMMAND_STARTERS[20] = "lower"
AP.BATCH_COMMAND_STARTERS[21] = "detach"
AP.BATCH_COMMAND_STARTERS[22] = "attach"
AP.BATCH_COMMAND_STARTERS[23] = "embed"
AP.BATCH_COMMAND_STARTERS[24] = "remove"
AP.BATCH_COMMAND_STARTERS[25] = "open"
AP.BATCH_COMMAND_STARTERS[26] = "close"
AP.BATCH_COMMAND_STARTERS[27] = "toggle"
AP.BATCH_COMMAND_STARTERS[28] = "diagnose"
AP.BATCH_COMMAND_STARTERS[29] = "start"
AP.BATCH_COMMAND_STARTERS[30] = "stop"
AP.BATCH_COMMAND_STARTERS[31] = "pause"
AP.BATCH_COMMAND_STARTERS[32] = "play"
AP.BATCH_COMMAND_STARTERS[33] = "animate"
AP.BATCH_COMMAND_STARTERS[34] = "preview"
AP.BATCH_COMMAND_STARTERS[35] = "select"
AP.BATCH_COMMAND_STARTERS[36] = "use"
AP.BATCH_COMMAND_STARTERS[37] = "apply"
AP.BATCH_COMMAND_STARTERS[38] = "verschiebe"
AP.BATCH_COMMAND_STARTERS[39] = "verschieben"
AP.BATCH_COMMAND_STARTERS[40] = "setze"
AP.BATCH_COMMAND_STARTERS[41] = "stelle"
AP.BATCH_COMMAND_STARTERS[42] = "kopiere"
AP.BATCH_COMMAND_STARTERS[43] = "kopieren"
AP.BATCH_COMMAND_STARTERS[44] = "uebernehmen"
AP.BATCH_COMMAND_STARTERS[45] = "aktivieren"
AP.BATCH_COMMAND_STARTERS[46] = "deaktivieren"
AP.BATCH_COMMAND_STARTERS[47] = "einschalten"
AP.BATCH_COMMAND_STARTERS[48] = "ausschalten"
AP.BATCH_COMMAND_STARTERS[49] = "anzeigen"
AP.BATCH_COMMAND_STARTERS[50] = "verstecken"
AP.BATCH_COMMAND_STARTERS[51] = "einblenden"
AP.BATCH_COMMAND_STARTERS[52] = "ausblenden"
AP.BATCH_COMMAND_STARTERS[53] = "oeffne"
AP.BATCH_COMMAND_STARTERS[54] = "waehle"
AP.BATCH_COMMAND_STARTERS[55] = "nutze"

--- Batch parsing lets one input fan out into multiple normal assistant commands.
--- It inherits obvious verbs across fragments but only executes after each part
--- goes through the same parser/confirmation path as a single command.
function AP.NormalizeForBatch(text)    if A.Normalize then return A.Normalize(text) end
    text = tostring(text or ""):lower():gsub("[,;:!?%(%)]", " "):gsub("%s+", " ")
    return Trim(text)
end

function AP.StripBatchLead(text)    text = Trim(text)
    local changed = true
    while changed do
        changed = false
        for _, lead in ipairs({ "also", "then", "please", "pls", "and then", "auch", "dann", "bitte", "und dann" }) do
            local prefix = lead .. " "
            if AP.NormalizeForBatch(text):sub(1, #prefix) == prefix then
                text = Trim(text:sub(#prefix + 1))
                changed = true
                break
            end
        end
    end
    return text
end

function AP.StartsBatchCommand(text)    local norm = AP.NormalizeForBatch(AP.StripBatchLead(text))
    if norm == "" then return false end
    for i = 1, #AP.BATCH_COMMAND_STARTERS do
        local starter = AP.BATCH_COMMAND_STARTERS[i]
        if norm == starter or norm:sub(1, #starter + 1) == starter .. " " then return true end
    end
    return false
end

function AP.BatchBooleanLead(text)    local norm = AP.NormalizeForBatch(text)
    for _, lead in ipairs({ "turn on", "turn off", "enable", "disable", "show", "hide", "start", "stop", "preview" }) do
        if norm == lead or norm:sub(1, #lead + 1) == lead .. " " then return lead end
    end
    return nil
end

function AP.HasOwnBatchBoolean(text)    local norm = AP.NormalizeForBatch(text)
    if norm == "" then return false end
    for _, lead in ipairs({ "on", "off", "enable", "disable", "enabled", "disabled", "show", "hide", "true", "false", "yes", "no" }) do
        if norm == lead or norm:sub(1, #lead + 1) == lead .. " " then return true end
        if norm:sub(-#lead - 1) == " " .. lead then return true end
    end
    return false
end

function AP.InheritableActionTail(text)    text = AP.NormalizeForBatch(text)
    if text == "" or AP.StartsBatchCommand(text) then return false end
    if text:find("test", 1, true) and (
        text:find("border", 1, true)
        or text:find("bar", 1, true)
        or text:find("bars", 1, true)
    ) then
        return true
    end
    if text:find("preview", 1, true) and (
        text:find("resource", 1, true)
        or text:find("class", 1, true)
        or text:find("animation", 1, true)
    ) then
        return true
    end
    return false
end

function AP.BatchHasPhrase(text, phrase)    local norm = AP.NormalizeForBatch(text)
    phrase = AP.NormalizeForBatch(phrase)
    if norm == "" or phrase == "" then return false end
    return (" " .. norm .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
end

function AP.BatchContainsAny(text, phrases)    for i = 1, #(phrases or {}) do
        if AP.BatchHasPhrase(text, phrases[i]) then return true end
    end
    return false
end

function AP.HasExplicitBatchScope(text)    local parser = A.Parser or {}
    if type(parser.DetectUnits) == "function" and #(parser.DetectUnits(text) or {}) > 0 then return true end
    if type(parser.DetectGroups) == "function" and #(parser.DetectGroups(text) or {}) > 0 then return true end
    return AP.BatchContainsAny(text, {
        "target of target", "focus target", "mythic raid", "player", "target", "focus", "pet", "boss",
        "party", "raid", "party frames", "raid frames", "group frames",
    })
end

function AP.HasScopedSettingDetail(text)    text = AP.NormalizeForBatch(text)
    if text == "" then return false end
    if not AP.HasExplicitBatchScope(text) then return false end
    return AP.BatchContainsAny(text, {
        "frame", "frames", "name", "names", "portrait", "portraits", "power bar", "powerbar", "mana bar",
        "health bar", "hp bar", "castbar", "cast bar", "text", "raid marker", "leader icon", "assist icon",
        "ready check", "status icon", "rested icon", "combat indicator", "dead indicator", "ghost indicator",
        "afk indicator", "dnd indicator", "load condition", "alpha", "opacity", "width", "height",
    })
end

function AP.InheritableSettingTail(text)    text = AP.NormalizeForBatch(text)
    if text == "" or AP.StartsBatchCommand(text) then return false end
    return AP.HasScopedSettingDetail(text)
end

function AP.InheritedBatchCommand(before, after)    local actionTail = AP.InheritableActionTail(after)
    local settingTail = AP.InheritableSettingTail(after)
    if not actionTail and not settingTail then return nil end
    local lead = AP.BatchBooleanLead(before)
    if not lead then return nil end
    if settingTail and AP.HasOwnBatchBoolean(after) then return nil end
    if settingTail and not AP.HasScopedSettingDetail(before) then return nil end
    return Trim(lead .. " " .. after)
end

function AP.SplitBatchCommands(text)    if A.pendingConfirmation or CurrentPendingChoices() then return nil end
    local parts = { Trim(text) }
    local connectors = { " and ", " then ", " und ", " dann " }
    local changed = true
    while changed do
        changed = false
        for p = 1, #parts do
            local raw = parts[p]
            local lower = raw:lower()
            for c = 1, #connectors do
                local startAt = 1
                while true do
                    local s, e = lower:find(connectors[c], startAt, true)
                    if not s then break end
                    local before = Trim(raw:sub(1, s - 1))
                    local after = AP.StripBatchLead(raw:sub(e + 1))
                    if before ~= "" and after ~= "" and AP.StartsBatchCommand(after) then
                        parts[p] = before
                        table.insert(parts, p + 1, after)
                        changed = true
                        break
                    end
                    local inherited = before ~= "" and after ~= "" and AP.InheritedBatchCommand(before, after) or nil
                    if inherited then
                        parts[p] = before
                        table.insert(parts, p + 1, inherited)
                        changed = true
                        break
                    end
                    startAt = e + 1
                end
                if changed then break end
            end
            if changed then break end
        end
    end
    return #parts > 1 and parts or nil
end

function AP.BatchLine(text)    text = tostring(text or ""):gsub("\r", "")
    text = text:gsub("\nNext:.-$", "")
    local first = text:match("([^\n]+)") or text
    return Trim(first)
end

AP.NORMAL_INPUT_MAX_CHARS = 20000

function AP.ExtractProfileString(text)    text = tostring(text or "")
    local compact = text:match("(MSUF%d+:%S+)")
    if compact then return compact, false end
    local uuf = text:match("(!UUF_%S+)")
    if uuf then return uuf, true end
    return nil, false
end

function AP.LongInputResult(text)    text = tostring(text or "")
    if #text <= AP.NORMAL_INPUT_MAX_CHARS then return nil end
    local value, isUUF = AP.ExtractProfileString(text)
    if value and Registry and type(Registry.GetAction) == "function" then
        local action = Registry:GetAction("import_profile_string")
        if action then
            return A.ExecutePlan({
                kind = "action",
                action = action,
                args = { value = value, uufBestEffortAccepted = isUUF == true },
                confirmRequired = true,
                confirmText = isUUF and A.UUFBestEffortConfirmText() or nil,
                label = isUUF and "Import UnhaltedUnitFrames profile string" or "Import profile string",
                summary = "Imports profile data into the active profile.",
            })
        end
    end
    return {
        text = "That message is too long here. Shorten it, or use the profile import window for large profile strings.",
        status = "failed",
        summary = "Inline input is too long.",
    }
end

function AP.TrySubmitBatch(text)    local parts = AP.SplitBatchCommands(text)
    if not parts then return nil end
    local lines = {}
    local applied = 0
    for i = 1, #parts do
        local result = A.HandleInput(parts[i])
        if not result then
            return { text = "I paused at step " .. tostring(i) .. " because I could not match that request.", result = "failed" }
        end
        if (result.status or result.result) ~= "applied" and (result.status or result.result) ~= "info" then
            return result
        end
        if (result.status or result.result) == "applied" then applied = applied + 1 end
        lines[#lines + 1] = tostring(i) .. ". " .. AP.BatchLine(result.text)
    end
    local textOut = "Done. I handled " .. tostring(#parts) .. " requests:\n" .. table.concat(lines, "\n")
    if applied > 0 then textOut = AppendUndoFollowupHint(textOut) end
    return { text = textOut, result = applied > 0 and "applied" or "info", summary = "Handled multiple Assistant requests." }
end

function AP.RecordAssistantResult(result)    if result and result.text then
        if type(result.searchResults) == "table" and type(A.SetPendingResults) == "function" then
            A.SetPendingResults(result.searchResults)
        end
        A.AddHistory("assistant", result.text, result.status or result.result, result.summary)
        if (result.status or result.result) == "applied" and type(A.RecordSuccessfulAssistantAction) == "function" and type(A.MaybePowerUserSupportHint) == "function" then
            A.RecordSuccessfulAssistantAction()
            local hint = A.MaybePowerUserSupportHint()
            if hint then A.AddHistory("assistant", hint, "info", "Assistant power-user dashboard links hint") end
        end
    end
end

function AP.SubmitNow(text, opts)    opts = opts or {}
    text = Trim(text)
    if text == "" then return nil end
    if InCombat() then return CombatSubmitResult() end
    local startedMs = PerfNowMs()
    if opts.skipUserHistory ~= true then
        A.AddHistory("user", text, "submitted")
    end
    local result = NormalizePlanResult(AP.LongInputResult(text) or AP.TrySubmitBatch(text) or A.HandleInput(text))
    AP.RecordAssistantResult(result)
    if type(A.RequestRefreshUI) == "function" then
        A.RequestRefreshUI("assistant.submit")
    elseif type(A.RefreshUI) == "function" then
        A.RefreshUI()
    end
    A.RecordPerfSample("assistant.submit", startedMs, text)
    return result
end

function A.Submit(text)
    return AP.SubmitNow(text)
end

function AP.BuildDeferredSubmitSteps(text, callback, opts)    opts = opts or {}
    local steps = {}
    local startedMs = PerfNowMs()
    local parts = AP.SplitBatchCommands(text)
    local finalResult
    local finished = false

    local function Complete(result)
        if finished then return end
        finished = true
        finalResult = NormalizePlanResult(result)
        AP.RecordAssistantResult(finalResult)
        A.RecordPerfSample("assistant.submit.deferred", startedMs, text)
        A.SetBusy(false)
        if type(callback) == "function" then callback(finalResult) end
    end

    if opts.userHistoryRecorded ~= true then
        steps[#steps + 1] = function()
            A.AddHistory("user", text, "submitted")
        end
    end

    if parts then
        local lines = {}
        local applied = 0
        local stopped = false
        for i = 1, #parts do
            local partIndex = i
            steps[#steps + 1] = A.CoroutineStep(function()
                if stopped then return end
                local part = parts[partIndex]
                local result = AP.LongInputResult(part) or A.HandleInput(part)
                if not result then
                    result = { text = "I paused at step " .. tostring(partIndex) .. " because I could not match that request.", result = "failed" }
                end
                if (result.status or result.result) ~= "applied" and (result.status or result.result) ~= "info" then
                    finalResult = result
                    stopped = true
                    return
                end
                if (result.status or result.result) == "applied" then applied = applied + 1 end
                lines[#lines + 1] = tostring(partIndex) .. ". " .. AP.BatchLine(result.text)
            end)
        end
        steps[#steps + 1] = function()
            if not finalResult then
                local textOut = "Done. I handled " .. tostring(#parts) .. " requests:\n" .. table.concat(lines, "\n")
                if applied > 0 then textOut = AppendUndoFollowupHint(textOut) end
                finalResult = {
                    text = textOut,
                    status = applied > 0 and "applied" or "info",
                    summary = "Handled multiple Assistant requests.",
                }
            end
            Complete(finalResult)
            return finalResult
        end
    else
        steps[#steps + 1] = A.CoroutineStep(function()
            finalResult = AP.LongInputResult(text) or A.HandleInput(text)
        end)
        steps[#steps + 1] = function()
            Complete(finalResult)
            return finalResult
        end
    end

    return steps, function(result)
        if finished then return end
        Complete(type(result) == "table" and result or {
            text = "Something went wrong while MSUF processed that request.",
            status = "failed",
        })
    end
end

function A.SubmitDeferred(text, callback)
    text = Trim(text)
    if text == "" then return nil end
    if InCombat() then return NormalizePlanResult(CombatSubmitResult()) end
    if A.IsBusy() then
        return NormalizePlanResult({ text = "I am still working on the previous request.", result = "busy" })
    end

    A.SetBusy(true, "I am working on that")

    A.AddHistory("user", text, "submitted")
    local steps, onDone = AP.BuildDeferredSubmitSteps(text, callback, { userHistoryRecorded = true })
    local job = A.StartJob("assistant.submit", steps, onDone)
    if job and type(job.result) == "table" and not A.IsBusy() then
        return NormalizePlanResult(job.result)
    end
    return NormalizePlanResult({ text = A.GetBusyText(), result = "queued" })
end

function A.WarmupPerformanceIndexes(reason)
    reason = tostring(reason or "assistant")
    if A.allowPerformanceWarmup ~= true and _G.MSUF_ASSISTANT_ALLOW_WARMUP ~= true then
        A._performanceWarmupSuppressed = reason
        return false, "disabled"
    end
    if A._performanceWarmupStarted then return false end
    if InCombat() then A._performanceWarmupSuppressed = "combat:" .. reason; return false, "combat" end
    if A.IsBusy and A.IsBusy() then A._performanceWarmupSuppressed = "busy:" .. reason; return false, "busy" end
    if type(A._assistantJobs) == "table" and #A._assistantJobs > 0 then A._performanceWarmupSuppressed = "jobs:" .. reason; return false, "jobs" end
    A._performanceWarmupStarted = true
    A._performanceWarmupCompleted = nil
    A._performanceWarmupSuppressed = nil
    A._performanceWarmupReason = reason

    local steps = {
        A.CoroutineStep(function()
            local parser = A.Parser
            local registry = A.Registry
            local settings = registry and type(registry.AllSettings) == "function" and registry:AllSettings() or nil
            if registry and type(registry.BuildFindSettingsIndex) == "function" then
                registry:BuildFindSettingsIndex()
            end
            if parser and settings and type(parser._EnsureRegistryCandidateIndex) == "function" then
                parser._EnsureRegistryCandidateIndex(settings, false)
            end
        end),
        A.CoroutineStep(function()
            local parser = A.Parser
            local registry = A.Registry
            local settings = registry and type(registry.AllSettings) == "function" and registry:AllSettings() or nil
            if parser and settings and type(parser._EnsureRegistryCandidateIndex) == "function" then
                parser._EnsureRegistryCandidateIndex(settings, true)
            end
        end),
        A.CoroutineStep(function()
            local parser = A.Parser
            local registry = A.Registry
            local actions = registry and type(registry.AllActions) == "function" and registry:AllActions() or nil
            if parser and actions and type(parser._EnsureExactActionPhraseIndex) == "function" then
                parser._EnsureExactActionPhraseIndex(actions)
            end
            if parser and actions and type(parser._EnsureRegistryActionAliasIndex) == "function" then
                parser._EnsureRegistryActionAliasIndex(actions)
            end
        end),
        A.CoroutineStep(function()
            if A.Knowledge and type(A.Knowledge.EnsureIndex) == "function" then
                A.Knowledge.EnsureIndex()
            end
        end),
    }
    local warmupBudget = tonumber(A.warmupJobBudgetMs) or 0.75
    if warmupBudget <= 0 or warmupBudget > 1 then warmupBudget = 0.75 end
    A.StartJob("assistant.warmup", steps, function()
        A._performanceWarmupCompleted = true
    end, {
        budgetMs = warmupBudget,
        maxStepsPerFrame = 1,
    })
    return true, reason
end

function A.CancelPerformanceWarmup(reason)
    reason = tostring(reason or "cancelled")
    local removed = A.CancelJobs and A.CancelJobs("assistant.warmup", reason) or 0
    if removed > 0 or (A._performanceWarmupStarted == true and A._performanceWarmupCompleted ~= true) then
        A._performanceWarmupStarted = nil
        A._performanceWarmupCompleted = nil
        A._performanceWarmupSuppressed = reason
        A._performanceWarmupReason = nil
    end
    return removed > 0
end

function A.RegisteredSettingSummary()
    local settings = Registry and Registry:AllSettings() or {}
    local out = {}
    for i = 1, #settings do out[#out + 1] = settings[i].key end
    return out
end

function A.TodoSummary()
    return Registry and Registry:GetTodos() or {}
end
