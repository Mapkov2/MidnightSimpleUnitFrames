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

local function RuntimeNowMs()
    local timer = type(_G.GetTimePreciseSec) == "function" and _G.GetTimePreciseSec or _G.GetTime
    if type(timer) == "function" then return (tonumber(timer()) or 0) * 1000 end
    return nil
end

local JOB_BUDGET_MS = 2
local JOB_MAX_STEPS = 4
A.JOB_YIELD = A.JOB_YIELD or {}
if A.jobBudgetMs == nil then A.jobBudgetMs = JOB_BUDGET_MS end
if A.jobMaxStepsPerFrame == nil then A.jobMaxStepsPerFrame = JOB_MAX_STEPS end
if A.ContextEngineEnabled == nil then A.ContextEngineEnabled = true end

A.RELATIVE_INTENT_MARKERS = A.RELATIVE_INTENT_MARKERS or {
    "more",
    "further",
    "farther",
    "a bit",
    "bit more",
    "slightly",
    "a little",
    "little more",
    "again",
    "keep going",
    "even more",
    "much more",
    "way more",
}

local function InCombat()
    return ((_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))) and true or false
end

local function MenuRuntimeActive()
    local frame = M and M.frame
    if frame and type(frame.IsShown) == "function" then
        return frame:IsShown() == true and A._menuRuntimeActive ~= false
    end
    -- Headless audit harnesses have no Menu2 frame. In the game the Assistant
    -- runtime is loaded only from an explicit menu action, so the flag is set
    -- before any asynchronous work can be scheduled.
    return A._menuRuntimeActive ~= false
end

function A.IsCombatLocked()
    return InCombat()
end

local afterCombatPending
local afterCombatOrder

local function ScheduleAfterCombat(key, fn)
    if not InCombat() then
        if type(fn) == "function" then fn() end
        return true
    end
    afterCombatPending = afterCombatPending or {}
    afterCombatOrder = afterCombatOrder or {}
    key = tostring(key or "MSUF_ASSISTANT_AFTER_COMBAT")
    if afterCombatPending[key] == nil then
        afterCombatOrder[#afterCombatOrder + 1] = key
    end
    afterCombatPending[key] = fn or true

    -- Zero-idle contract: never subscribe the Assistant to combat events.
    -- Pending work resumes only when the MSUF menu is explicitly opened again.
    return true
end

local function ResumeAfterCombatCallbacks()
    if InCombat() or not MenuRuntimeActive() then return false end
    local pending = afterCombatPending or {}
    local order = afterCombatOrder or {}
    afterCombatPending = {}
    afterCombatOrder = {}
    for i = 1, #order do
        local callback = pending[order[i]]
        if type(callback) == "function" then callback() end
    end
    return #order > 0
end

local function ScheduleNextFrame(key, fn)
    if type(fn) ~= "function" then return false end
    if InCombat() or not MenuRuntimeActive() then return false end
    AP.nextFramePending = AP.nextFramePending or {}
    AP.nextFrameOrder = AP.nextFrameOrder or {}
    local nextFramePending = AP.nextFramePending
    local nextFrameOrder = AP.nextFrameOrder
    key = tostring(key or "MSUF_ASSISTANT")
    if nextFramePending[key] == nil then
        nextFrameOrder[#nextFrameOrder + 1] = key
    end
    nextFramePending[key] = fn
    if AP.nextFrameQueued then return true end
    AP.nextFrameQueued = true
    local function Run()
        AP.nextFrameTimer = nil
        AP.nextFrameQueued = false
        if InCombat() or not MenuRuntimeActive() then return end
        local pending = AP.nextFramePending or {}
        local order = AP.nextFrameOrder or {}
        AP.nextFramePending = {}
        AP.nextFrameOrder = {}
        for i = 1, #order do
            local cb = pending[order[i]]
            if type(cb) == "function" then
                local ok, failure = pcall(cb)
                if not ok and type(A.RecoverAssistantFailure) == "function" then
                    pcall(A.RecoverAssistantFailure, failure, {
                        label = "assistant.next-frame",
                    })
                end
            end
        end
    end
    if _G.C_Timer and type(_G.C_Timer.NewTimer) == "function" then
        local ran = false
        local function ProtectedRun()
            ran = true
            Run()
        end
        local scheduled, timer = pcall(_G.C_Timer.NewTimer, 0, ProtectedRun)
        local cancellable = timer and type(timer.Cancel) == "function"
        if scheduled and cancellable and not ran then
            AP.nextFrameTimer = timer
            return true
        end
        if ran then return true end
        -- A timer API failure must not leave nextFrameQueued stuck or discard
        -- accepted work. Execute the bounded pending batch now; callers still
        -- receive an honest success result and cannot submit it a second time.
        Run()
        return true
    end
    Run()
    return true
end

-- Public only for the tiny load-on-demand bridge and sibling Assistant
-- modules. It keeps every next-frame callback under the core menu/combat
-- lifecycle instead of allowing untracked timers.
function A.ScheduleMenuRuntimeNextFrame(key, fn)
    if type(fn) ~= "function" or InCombat() or not MenuRuntimeActive() then return false end
    return ScheduleNextFrame(key, fn)
end

local function FriendlyJobLabel(label)
    label = tostring(label or "")
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

local function DeferJobPumpForCombat(reason)
    local jobs = A._assistantJobs
    if type(jobs) ~= "table" or #jobs == 0 then return false end
    A._assistantJobsCombatDeferred = true
    A._assistantJobsCombatReason = tostring(reason or "combat")
    -- Do not register PLAYER_REGEN_ENABLED. The menu closes for combat and
    -- explicitly resumes pending work on its next out-of-combat OnShow.
    return true
end

function A.ResumeCombatDeferredJobs(reason)
    if InCombat() or not MenuRuntimeActive() then
        return DeferJobPumpForCombat(reason or "combat")
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
end

local function JobMatches(job, match)
    if type(match) == "function" then return match(job) == true end
    if match == nil then return true end
    return tostring(job and job.label or "") == tostring(match)
end

local function FailureContainsAny(text, terms)
    text = " " .. tostring(text or "") .. " "
    for i = 1, #(terms or {}) do
        if text:find(tostring(terms[i]), 1, true) then return true end
    end
    return false
end

local function FailureScopeLabel(text)
    if FailureContainsAny(text, { " target of target ", " targettarget " }) then return "Target of Target" end
    if FailureContainsAny(text, { " focus target ", " focustarget " }) then return "Focus Target" end
    if FailureContainsAny(text, { " mythic raid ", " mythicraid " }) then return "Mythic Raid" end
    if FailureContainsAny(text, { " target " }) then return "Target" end
    if FailureContainsAny(text, { " focus " }) then return "Focus" end
    if FailureContainsAny(text, { " pet " }) then return "Pet" end
    if FailureContainsAny(text, { " boss " }) then return "Boss" end
    if FailureContainsAny(text, { " party " }) then return "Party" end
    if FailureContainsAny(text, { " raid " }) then return "Raid" end
    if FailureContainsAny(text, { " player ", " my ", " self " }) then return "Player" end
    return nil
end

local function AddFailurePageHint(hints, seen, page, label, detail)
    page = tostring(page or "")
    if page == "" or seen[page] then return end
    seen[page] = true
    hints[#hints + 1] = {
        kind = "page",
        key = page,
        page = page,
        label = tostring(label or page),
        pageLabel = tostring(label or page),
        description = tostring(detail or "Likely MSUF page for this request."),
        canOpen = true,
        canExplain = true,
    }
end

-- This is deliberately independent of the parser, router, and knowledge
-- index: it is the last-resort path used when one of those systems throws.
-- It performs only a few bounded string checks and creates no passive work.
local function FailurePageHints(query)
    local normalized = " " .. tostring(query or ""):lower():gsub("[%p%c]", " "):gsub("%s+", " ") .. " "
    local hints, seen = {}, {}
    local scope = FailureScopeLabel(normalized)
    local aura = FailureContainsAny(normalized, { " aura ", " auras ", " buff ", " buffs ", " debuff ", " debuffs " })

    if aura then
        local groupScope = scope == "Party" or scope == "Raid" or scope == "Mythic Raid"
        local sharedAppearance = FailureContainsAny(normalized,
            { " appearance ", " shared ", " theme ", " icon shape ", " icon border ", " icon shadow " })
        local unitPage = scope == "Target" and "uf_target" or scope == "Focus" and "uf_focus"
            or scope == "Boss" and "uf_boss" or "uf_player"
        local page = groupScope and "gf_auras" or sharedAppearance and "auras3_styling" or unitPage
        local pageLabel = groupScope and "Group Auras" or sharedAppearance and "Global Aura Appearance"
            or tostring(scope or "Player") .. " UnitFrame"
        local control = FailureContainsAny(normalized, { " growth ", " grow ", " direction " }) and "Growth"
            or FailureContainsAny(normalized, { " anchor ", " attach " }) and "Anchor"
            or FailureContainsAny(normalized, { " spacing ", " gap " }) and "Spacing"
            or FailureContainsAny(normalized, { " size ", " bigger ", " smaller " }) and "Icon Size"
            or FailureContainsAny(normalized, { " cooldown ", " timer " }) and "Cooldown"
            or FailureContainsAny(normalized, { " stack ", " count " }) and "Stack Text"
            or "the matching aura control"
        local detail = "Choose " .. tostring(scope or "the intended frame") .. " as the editing scope, then look for " .. control .. "."
        AddFailurePageHint(hints, seen, page, pageLabel, detail)
        if FailureContainsAny(normalized, { " filter ", " blacklist ", " whitelist ", " hide ", " show only " }) then
            AddFailurePageHint(hints, seen, "auras3_filters", "Aura Filters", "Check the relevant aura filter or list for " .. tostring(scope or "that frame") .. ".")
        end
    elseif FailureContainsAny(normalized, { " cast bar ", " castbar ", " casting bar " }) then
        AddFailurePageHint(hints, seen, "opt_castbar", "Cast Bars", "Look for the " .. tostring(scope or "matching frame") .. " cast-bar control.")
    elseif FailureContainsAny(normalized, { " class resource ", " class resources ", " class power ", " combo point ", " holy power " }) then
        AddFailurePageHint(hints, seen, "classpower", "Class Resources", "Look for the matching resource, detached power, placement, or appearance control.")
    elseif FailureContainsAny(normalized, { " profile ", " import ", " export ", " backup " }) then
        AddFailurePageHint(hints, seen, "profiles", "Profiles", "Profile creation, switching, import, export, and backup controls live here.")
    elseif FailureContainsAny(normalized, { " party ", " raid ", " mythic raid ", " group frame ", " group frames " }) then
        if FailureContainsAny(normalized, { " indicator ", " icon ", " ready check ", " role ", " leader ", " summon " }) then
            AddFailurePageHint(hints, seen, "gf_indicators", "Group Status & Indicators", "Look for the named Party/Raid status icon or indicator.")
        elseif FailureContainsAny(normalized, { " growth ", " direction ", " spacing ", " columns ", " anchor ", " layout ", " scale " }) then
            AddFailurePageHint(hints, seen, "gf_layout", "Group Layout", "Choose the intended Party, Raid, or Mythic Raid scope, then inspect its layout control.")
        elseif FailureContainsAny(normalized, { " dispel ", " stripe " }) then
            AddFailurePageHint(hints, seen, "gf_bars", "Group Dispel Overlay", "Choose the intended group scope and inspect its Dispel Overlay or Debuff Stripe control.")
        elseif FailureContainsAny(normalized, { " range fade ", " out of range " }) then
            AddFailurePageHint(hints, seen, "gf_layout", "Group Layout", "Choose the intended group scope and inspect its Range Fade control.")
        else
            AddFailurePageHint(hints, seen, "gf_layout", "Group Layout", "Choose the intended group scope and inspect its health, resource, text, or layout control.")
        end
    elseif FailureContainsAny(normalized, { " bar ", " bars " })
        and FailureContainsAny(normalized, { " outline ", " outlines ", " border ", " borders " })
    then
        AddFailurePageHint(hints, seen, "opt_bars", "Bars", "Shared bar outline, border, texture, and appearance controls live here.")
    elseif FailureContainsAny(normalized, { " font ", " outline ", " monochrome " }) then
        AddFailurePageHint(hints, seen, "opt_fonts", "Fonts", "Shared and frame-specific font controls live here.")
    elseif FailureContainsAny(normalized, { " color ", " colour ", " colored ", " coloured " }) then
        AddFailurePageHint(hints, seen, "opt_colors", "Colors", "Look for the named shared or frame color control.")
    elseif FailureContainsAny(normalized, { " texture ", " absorb ", " health bar ", " power bar ", " bar " }) then
        AddFailurePageHint(hints, seen, "opt_bars", "Bars", "Shared textures, absorb behavior, and bar appearance controls live here.")
    elseif FailureContainsAny(normalized, { " combat timer ", " crosshair ", " totem ", " gameplay " }) then
        AddFailurePageHint(hints, seen, "gameplay", "Gameplay", "Look for the named gameplay feature and its placement controls.")
    end

    if #hints == 0 and scope then
        local pages = {
            Player = { "uf_player", "Player" }, Target = { "uf_target", "Target" }, Focus = { "uf_focus", "Focus" },
            Pet = { "uf_pet", "Pet" }, Boss = { "uf_boss", "Boss Frames" },
            ["Target of Target"] = { "uf_targettarget", "Target of Target" }, ["Focus Target"] = { "uf_focustarget", "Focus Target" },
        }
        local match = pages[scope]
        if match then AddFailurePageHint(hints, seen, match[1], match[2], "Look for the control named in your request on this frame page.") end
    end
    if #hints == 0 then
        AddFailurePageHint(hints, seen, "search", "Search", "Search for the main MSUF noun from your request.")
        AddFailurePageHint(hints, seen, "home", "Dashboard", "The Dashboard can guide you to a feature area or run local checks.")
    end
    return hints
end

function AP.AssistantFailureResult(err, context)
    context = type(context) == "table" and context or {}
    local message = type(err) == "table" and err.message or err
    message = tostring(message or "unknown error")
    A.lastAssistantJobError = {
        label = tostring(context.label or (context.job and context.job.label) or "assistant.runtime"),
        message = message,
        stack = type(err) == "table" and err.stack or nil,
        requestText = tostring(context.text or (context.job and context.job.requestText) or ""),
    }
    local hints = FailurePageHints(context.text)
    local lines = {
        "Sorry — I couldn't finish a reliable answer for that request, but the Assistant recovered and is still ready.",
        #hints == 1 and "My best suggestion is:" or "My best suggestions are:",
    }
    for i = 1, math.min(#hints, 3) do
        local hint = hints[i]
        lines[#lines + 1] = tostring(i) .. ". " .. tostring(hint.pageLabel or hint.label or "MSUF page") .. " — " .. tostring(hint.description or "check this page")
    end
    lines[#lines + 1] = "Reply with a number or 'open it', or rephrase the request and I will try again."
    return {
        text = table.concat(lines, "\n"),
        status = "failed",
        summary = "Assistant job failed: " .. message,
        searchResults = hints,
        selectPendingResult = #hints == 1 and 1 or nil,
        retryText = tostring(context.text or (context.job and context.job.requestText) or ""),
    }
end

function AP.AssistantJobErrorResult(err, job)
    return AP.AssistantFailureResult(err, {
        job = job,
        label = job and job.label,
        text = job and job.requestText,
    })
end

function AP.AssistantJobErrorHandler(err)
    return {
        message = tostring(err or "unknown error"),
        stack = type(_G.debugstack) == "function" and _G.debugstack(2) or nil,
    }
end

local function AssistantResultWasRecorded(result)
    if type(result) ~= "table" or tostring(result.text or "") == "" or type(A.GetHistory) ~= "function" then return false end
    local ok, history = pcall(A.GetHistory)
    if not ok or type(history) ~= "table" then return false end
    for i = #history, math.max(1, #history - 2), -1 do
        local item = history[i]
        if item and item.role ~= "user" then return tostring(item.text or "") == tostring(result.text or "") end
    end
    return false
end

local function RecordFailureUserIfMissing(text)
    text = Trim(text)
    if text == "" or type(A.AddHistory) ~= "function" then return end
    local latest
    if type(A.GetHistory) == "function" then
        local ok, history = pcall(A.GetHistory)
        if ok and type(history) == "table" then latest = history[#history] end
    end
    if latest and latest.role == "user" and tostring(latest.text or "") == text then return end
    pcall(A.AddHistory, "user", text, "submitted")
end

local function RestoreAssistantInputAfterFailure()
    A._busy = false
    A._busyText = nil
    A._busySerial = (tonumber(A._busySerial) or 0) + 1
    A._assistantCurrentJob = nil

    local jobs = A._assistantJobs
    if type(jobs) == "table" then
        for i = #jobs, 1, -1 do
            if tostring(jobs[i] and jobs[i].label or "") == "assistant.submit" then table.remove(jobs, i) end
        end
    end

    local ui = A.dashboardUI
    if type(ui) ~= "table" then return end
    local busyTimer = ui._msufAssistantBusyTimer
    if busyTimer and type(busyTimer.Cancel) == "function" then pcall(busyTimer.Cancel, busyTimer) end
    if type(A.UntrackMenuRuntimeTimer) == "function" then pcall(A.UntrackMenuRuntimeTimer, "assistant.dashboard.busy", busyTimer) end
    ui._msufAssistantBusyTimer = nil
    ui._msufAssistantBusyPulse = nil
    local controls = { ui.input, ui.send }
    for i = 1, #controls do
        local control = controls[i]
        if control and type(control.Enable) == "function" then pcall(control.Enable, control) end
    end
    local sendLabel = ui.send and ui.send._msuf2Label
    if sendLabel and type(sendLabel.SetText) == "function" then
        pcall(sendLabel.SetText, sendLabel, "Send")
    elseif ui.send and type(ui.send.SetText) == "function" then
        pcall(ui.send.SetText, ui.send, "Send")
    end
    if ui.input and type(ui.input.SetFocus) == "function" and MenuRuntimeActive() and not InCombat() then
        pcall(ui.input.SetFocus, ui.input)
    end
end

-- Public so the load-on-demand bridge can hand an unexpected post-load error
-- to the full runtime without duplicating recovery policy.
function A.RecoverAssistantFailure(err, context)
    context = type(context) == "table" and context or {}
    local result = AP.AssistantFailureResult(err, context)
    RestoreAssistantInputAfterFailure()
    RecordFailureUserIfMissing(context.text)
    local recorded = false
    if type(AP.RecordAssistantResult) == "function" then
        local ok = pcall(AP.RecordAssistantResult, result)
        recorded = ok
    end
    if not recorded and type(A.AddHistory) == "function" then
        pcall(A.AddHistory, "assistant", result.text, result.status, result.summary)
    end
    if type(A.RequestRefreshUI) == "function" then
        pcall(A.RequestRefreshUI, "assistant.failure.recovered")
    elseif type(A.RefreshUI) == "function" then
        pcall(A.RefreshUI)
    end
    if type(context.callback) == "function" then pcall(context.callback, result) end
    return result
end

function AP.CompleteAssistantJob(job, result)
    if type(job) ~= "table" or job._callbackCompleted == true then return false end
    job._callbackCompleted = true
    if type(job.callback) ~= "function" then return true end
    local ok, callbackError = xpcall(function()
        job.callback(result, job)
    end, AP.AssistantJobErrorHandler)
    if not ok then
        AP.AssistantJobErrorResult(callbackError, job)
        if A._busy == true or not AssistantResultWasRecorded(result) then
            A.RecoverAssistantFailure(callbackError, { job = job, label = job.label, text = job.requestText })
        else
            RestoreAssistantInputAfterFailure()
        end
    end
    return ok
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
            AP.CompleteAssistantJob(job, {
                text = "Stopped. I cancelled the assistant work that was still running.",
                status = "info",
                summary = "Cancelled running Assistant work.",
                cancelled = true,
                suppressAssistantRecord = true,
            })
            removed = removed + 1
        end
    end
    if removed > 0 then ClearCombatDeferredJobsIfIdle() end
    return removed
end

function ScheduleJobPump()
    if InCombat() or not MenuRuntimeActive() then
        DeferJobPumpForCombat(InCombat() and "combat:schedule" or "menu-hidden:schedule")
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
    if InCombat() or not MenuRuntimeActive() then
        DeferJobPumpForCombat(InCombat() and "combat:run" or "menu-hidden:run")
        return false
    end

    local sliceStart = RuntimeNowMs()
    local budget = tonumber(A.jobBudgetMs) or JOB_BUDGET_MS
    local maxSteps = tonumber(A.jobMaxStepsPerFrame) or JOB_MAX_STEPS
    if budget <= 0 then budget = JOB_BUDGET_MS end
    if maxSteps <= 0 then maxSteps = JOB_MAX_STEPS end

    local stepsRun = 0
    while #jobs > 0 and stepsRun < maxSteps do
        if InCombat() or not MenuRuntimeActive() then
            DeferJobPumpForCombat(InCombat() and "combat:run" or "menu-hidden:run")
            return false
        end
        local job = jobs[1]
        if job and job.cancelled then
            table.remove(jobs, 1)
            AP.CompleteAssistantJob(job, {
                text = "Stopped. I cancelled the assistant work that was still running.",
                status = "info",
                summary = "Cancelled running Assistant work.",
                cancelled = true,
                suppressAssistantRecord = true,
            })
            break
        end
        local jobMaxSteps = tonumber(job and job.maxStepsPerFrame) or maxSteps
        if jobMaxSteps <= 0 then jobMaxSteps = maxSteps end
        if stepsRun >= jobMaxSteps then break end
        local jobBudget = tonumber(job and job.budgetMs) or budget
        if jobBudget <= 0 then jobBudget = budget end
        local step = job and job.steps and job.steps[job.index]
        if type(step) ~= "function" then
            table.remove(jobs, 1)
            AP.CompleteAssistantJob(job, job.result)
        else
            A._assistantCurrentJob = job
            local ok, result, stopResult = xpcall(function()
                return step(job)
            end, AP.AssistantJobErrorHandler)
            A._assistantCurrentJob = nil
            stepsRun = stepsRun + 1
            if not ok then
                table.remove(jobs, 1)
                job.result = AP.AssistantJobErrorResult(result, job)
                AP.CompleteAssistantJob(job, job.result)
            elseif result == false then
                table.remove(jobs, 1)
                if stopResult ~= nil then job.result = stopResult end
                AP.CompleteAssistantJob(job, job.result)
            elseif result == A.JOB_YIELD then
                break
            else
                if result ~= nil then job.result = result end
                job.index = job.index + 1
            end
        end

        if sliceStart and jobBudget > 0 then
            local now = RuntimeNowMs()
            if now and (now - sliceStart) >= jobBudget then break end
        end
    end

    if #jobs > 0 then
        if InCombat() or not MenuRuntimeActive() then
            DeferJobPumpForCombat(InCombat() and "combat:slice" or "menu-hidden:slice")
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
    local now = RuntimeNowMs()
    if not now then return false end
    local budget = tonumber(A._jobYieldBudgetMs) or JOB_BUDGET_MS
    if force or (budget > 0 and (now - started) >= budget) then
        A._jobYieldStartedMs = nil
        coroutine.yield(A.JOB_YIELD)
        A._jobYieldStartedMs = RuntimeNowMs()
        return true
    end
    return false
end

function A.CoroutineStep(fn)
    if type(fn) ~= "function" then return fn end
    local co
    return function(job)
        if job and job.cancelled then
            return false, {
                text = "Stopped. I cancelled the assistant work that was still running.",
                status = "info",
                summary = "Cancelled running Assistant work.",
            }
        end
        if not co then
            co = coroutine.create(function()
                return fn(job)
            end)
        end
        A._jobYieldStartedMs = RuntimeNowMs()
        A._jobYieldBudgetMs = tonumber(job and job.budgetMs) or tonumber(A.jobBudgetMs) or JOB_BUDGET_MS
        local ok, result = coroutine.resume(co, job)
        A._jobYieldStartedMs = nil
        A._jobYieldBudgetMs = nil
        if not ok then
            local detail = result
            if type(debug) == "table" and type(debug.traceback) == "function" then
                local traced, value = pcall(debug.traceback, co, tostring(result), 0)
                if traced and type(value) == "string" and value ~= "" then detail = value end
            end
            error(detail, 0)
        end
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
        lowPriority = opts.lowPriority == true,
        requestText = opts.requestText,
    }
    -- The pump is strict FIFO on jobs[1]. Background work (index warmup) can
    -- take minutes at its tiny frame budget, and a user command queued behind
    -- it would starve exactly that long. Normal jobs therefore enqueue ahead
    -- of any low-priority job; low-priority work resumes afterwards (its
    -- coroutine state lives in the step closure, so reordering is safe).
    local jobs = A._assistantJobs
    if job.lowPriority then
        jobs[#jobs + 1] = job
    else
        local insertAt = #jobs + 1
        for i = 1, #jobs do
            if jobs[i].lowPriority then
                insertAt = i
                break
            end
        end
        table.insert(jobs, insertAt, job)
    end
    if not InCombat() and MenuRuntimeActive() then
        ScheduleJobPump()
    else
        DeferJobPumpForCombat((InCombat() and "combat:start:" or "menu-hidden:start:") .. job.label)
    end
    return job
end

function A.TrackMenuRuntimeTimer(key, timer)
    if not timer then return nil end
    if InCombat() or not MenuRuntimeActive() then
        if type(timer.Cancel) == "function" then timer:Cancel() end
        return nil
    end
    key = tostring(key or timer)
    A._menuRuntimeTimers = A._menuRuntimeTimers or {}
    local previous = A._menuRuntimeTimers[key]
    if previous and previous ~= timer and type(previous.Cancel) == "function" then previous:Cancel() end
    A._menuRuntimeTimers[key] = timer
    return timer
end

function A.UntrackMenuRuntimeTimer(key, timer)
    local timers = A._menuRuntimeTimers
    key = tostring(key or timer)
    if type(timers) == "table" and (timer == nil or timers[key] == timer) then timers[key] = nil end
end

local function CancelMenuRuntimeTimers()
    local timers = A._menuRuntimeTimers
    if type(timers) == "table" then
        for _, timer in pairs(timers) do
            if timer and type(timer.Cancel) == "function" then timer:Cancel() end
        end
    end
    A._menuRuntimeTimers = {}
end

function A.SetMenuRuntimeActive(active, reason)
    active = active == true and not InCombat()
    A._menuRuntimeActive = active and true or false
    A._menuRuntimeReason = tostring(reason or (active and "menu-show" or "menu-hide"))

    if not active then
        CancelMenuRuntimeTimers()
        if type(A.SuspendPendingBroadApply) == "function" then A.SuspendPendingBroadApply() end
        if type(A.ClearRouterTransientCaches) == "function" then A.ClearRouterTransientCaches() end
        if A.Parser and type(A.Parser.ClearRegistryCandidateFuzzyCache) == "function" then A.Parser.ClearRegistryCandidateFuzzyCache() end
        if A.Parser and type(A.Parser.ClearActionAliasFuzzyCache) == "function" then A.Parser.ClearActionAliasFuzzyCache() end
        if AP.nextFrameTimer and type(AP.nextFrameTimer.Cancel) == "function" then
            AP.nextFrameTimer:Cancel()
        end
        AP.nextFrameTimer = nil
        AP.nextFrameQueued = nil
        AP.nextFramePending = {}
        AP.nextFrameOrder = {}
        A._assistantJobPumpScheduled = nil
        A._refreshPending = nil
        return false
    end

    if type(A.ResumePendingBroadApply) == "function" then A.ResumePendingBroadApply() end
    ResumeAfterCombatCallbacks()
    A.ResumeCombatDeferredJobs(A._menuRuntimeReason)
    if type(A.FlushQueue) == "function" and type(A.HasQueuedPlans) == "function" and A.HasQueuedPlans() then
        ScheduleNextFrame("MSUF_ASSISTANT_QUEUE_MENU_RESUME", function()
            if not InCombat() and MenuRuntimeActive() then A.FlushQueue() end
        end)
    end
    return true
end

function A.RequestRefreshUI(reason)
    -- A staged full reset deliberately leaves all SavedVariables globals nil
    -- until reload. Rendering Assistant history would call EnsureDB and undo
    -- that contract by recreating a profile immediately.
    if A._preserveNilSavedVariablesUntilReload == true
        and rawget(_G, "MSUF_DB") == nil
        and rawget(_G, "MSUF_GlobalDB") == nil
        and rawget(_G, "MSUF_ActiveProfile") == nil
    then
        return false
    end
    if not MenuRuntimeActive() then
        A._refreshPending = nil
        return false
    end
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
        if type(A.RefreshUI) == "function" then A.RefreshUI() end
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

function A.IsFiniteAssistantNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

function A.RefreshAssistantSettingValues(setting)
    local refresh = setting and setting.refreshValues
    if type(refresh) ~= "function" then return true end
    local ok, values, labels = pcall(refresh, setting)
    if not ok then return false, "value domain refresh failed" end
    if type(values) ~= "table" or #values == 0 then return false, "value domain is empty" end
    setting.values = values
    if type(labels) == "table" then setting.valueLabels = labels end
    return true
end

function AP.ValueInAssistantSettingDomain(setting, value)
    local values = setting and setting.values
    if type(values) ~= "table" or #values == 0 then return false end
    for i = 1, #values do
        if values[i] == value then return true end
    end
    return false
end

-- This is the transaction-boundary type contract for registry settings.  It
-- deliberately accepts only native values; natural-language coercion belongs
-- to the parser and must have completed before a plan reaches ExecuteChanges.
-- The boolean result keeps false itself usable as a normalized setting value.
-- Out-of-range corrections collected while planning the current request, so the
-- reply can tell the player what MSUF actually allows instead of quietly
-- substituting a different number. Cleared at the start of every input.
function A.RecordAssistantValueClamp(setting, requested, applied, minValue, maxValue)
    if type(setting) ~= "table" then return end
    A._assistantValueClamps = A._assistantValueClamps or {}
    local list = A._assistantValueClamps
    if #list >= 6 then return end
    local key = tostring(setting.key or setting.label or "")
    for i = 1, #list do
        if list[i].key == key then return end
    end
    list[#list + 1] = {
        key = key,
        label = tostring(setting.label or setting.key or "that option"),
        requested = requested,
        applied = applied,
        min = minValue,
        max = maxValue,
    }
end

local function FormatClampNumber(value)
    if type(value) ~= "number" then return tostring(value) end
    if math.abs(value - math.floor(value + 0.5)) < 0.001 then return tostring(math.floor(value + 0.5)) end
    return string.format("%.2f", value)
end

function AP.AppendValueClampNotes(text)
    local list = A._assistantValueClamps
    if type(list) ~= "table" or #list == 0 then return text end
    -- The correction explains the change, so it belongs with the change rather
    -- than after the "Next: ..." sign-off.
    local body, tail = tostring(text or ""), nil
    local hintAt = body:find("\nNext: ", 1, true)
    if hintAt then
        tail = body:sub(hintAt + 1)
        body = body:sub(1, hintAt - 1)
    end
    local lines = { body }
    for i = 1, #list do
        local clamp = list[i]
        local range
        if clamp.min ~= nil and clamp.max ~= nil then
            range = FormatClampNumber(clamp.min) .. " to " .. FormatClampNumber(clamp.max)
        elseif clamp.min ~= nil then
            range = FormatClampNumber(clamp.min) .. " or higher"
        elseif clamp.max ~= nil then
            range = FormatClampNumber(clamp.max) .. " or lower"
        end
        lines[#lines + 1] = "You asked for " .. FormatClampNumber(clamp.requested) .. ", but "
            .. clamp.label .. " only accepts " .. tostring(range or "a narrower range")
            .. ", so I used " .. FormatClampNumber(clamp.applied) .. "."
    end
    if tail then lines[#lines + 1] = tail end
    return table.concat(lines, "\n")
end

function A.NormalizeRegistrySettingValue(setting, value, opts)
    if type(setting) ~= "table" then return false, "missing setting" end
    opts = type(opts) == "table" and opts or nil
    local settingType = tostring(setting.type or "")

    if settingType == "boolean" then
        if type(value) ~= "boolean" then return false, "expected boolean" end
        return true, value
    end

    if settingType == "number" then
        if not A.IsFiniteAssistantNumber(value) then return false, "expected finite number" end
        local minValue = setting.min
        local maxValue = setting.max
        local step = setting.step
        if step == nil then step = setting.increment end
        if minValue ~= nil and not A.IsFiniteAssistantNumber(minValue) then return false, "invalid minimum metadata" end
        if maxValue ~= nil and not A.IsFiniteAssistantNumber(maxValue) then return false, "invalid maximum metadata" end
        if step ~= nil and not A.IsFiniteAssistantNumber(step) then return false, "invalid step metadata" end
        if minValue ~= nil and maxValue ~= nil and minValue > maxValue then return false, "invalid numeric range" end

        local normalized = value
        if minValue ~= nil and normalized < minValue then normalized = minValue end
        if maxValue ~= nil and normalized > maxValue then normalized = maxValue end
        if step ~= nil and step > 0 then
            normalized = math.floor((normalized / step) + 0.5) * step
        end
        -- Rounding around zero can cross a non-step-aligned bound, so enforce
        -- the declared range again after applying the step.
        if minValue ~= nil and normalized < minValue then normalized = minValue end
        if maxValue ~= nil and normalized > maxValue then normalized = maxValue end
        if not A.IsFiniteAssistantNumber(normalized) then return false, "normalized number is not finite" end
        if math.abs(normalized - math.floor(normalized + 0.5)) < 0.001 then
            normalized = math.floor(normalized + 0.5)
        end
        -- Silently clamping is the one place the Assistant could look like it
        -- obeyed while doing something else: "set player width to 4000" applied
        -- 900 and said so, but never mentioned that 4000 was out of range, so
        -- the player is left guessing whether MSUF or the Assistant decided.
        -- Record the correction; the reply surfaces it.
        if (minValue ~= nil and value < minValue) or (maxValue ~= nil and value > maxValue) then
            A.RecordAssistantValueClamp(setting, value, normalized, minValue, maxValue)
        end
        return true, normalized
    end

    if settingType == "enum" then
        if not (opts and opts.skipRefresh == true) then
            local refreshed, reason = A.RefreshAssistantSettingValues(setting)
            if not refreshed then return false, reason end
        end
        if not AP.ValueInAssistantSettingDomain(setting, value) then return false, "unsupported enum value" end
        return true, value
    end

    if settingType == "string" then
        if type(value) ~= "string" then return false, "expected string" end
        if setting.closedValues == true then
            if not (opts and opts.skipRefresh == true) then
                local refreshed, reason = A.RefreshAssistantSettingValues(setting)
                if not refreshed then return false, reason end
            end
            if not AP.ValueInAssistantSettingDomain(setting, value) then return false, "unsupported string value" end
        end
        return true, value
    end

    if settingType == "color" then
        if type(value) ~= "table" then return false, "expected color table" end
        local r = value.r
        local g = value.g
        local b = value.b
        local a = value.a
        if r == nil then r = value[1] end
        if g == nil then g = value[2] end
        if b == nil then b = value[3] end
        if a == nil then a = value[4] end
        if not A.IsFiniteAssistantNumber(r) or not A.IsFiniteAssistantNumber(g) or not A.IsFiniteAssistantNumber(b) then
            return false, "expected finite RGB components"
        end
        if r < 0 or r > 1 or g < 0 or g > 1 or b < 0 or b > 1 then
            return false, "RGB components must be between 0 and 1"
        end
        if a ~= nil and (not A.IsFiniteAssistantNumber(a) or a < 0 or a > 1) then
            return false, "alpha component must be between 0 and 1"
        end
        return true, value
    end

    return false, "unsupported setting type"
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
            -- A generated-schema control has no registry owner to serialize;
            -- its semantic id is the stable handle Schema.Execute resolves.
            schemaSemanticId = choice and choice.schemaSemanticId,
            schemaSourceText = choice and choice.schemaSourceText,
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
            successText = choice and choice.successText,
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
                successText = item.successText,
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
                successText = item.successText,
            }
        elseif item and type(item.schemaSemanticId) == "string" and item.schemaSemanticId ~= "" then
            choices[#choices + 1] = {
                schemaSemanticId = item.schemaSemanticId,
                schemaSourceText = item.schemaSourceText,
                value = item.value,
                label = item.label,
                valueLabel = item.valueLabel,
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

function AP.ClearPendingCandidates()
    A.pendingCandidates = nil
    local ctx = A.GetContext and A.GetContext()
    if ctx then ctx.pendingCandidates = nil end
end

function AP.SetPendingCandidates(choices)
    if type(choices) ~= "table" or #choices == 0 then
        AP.ClearPendingCandidates()
        return nil
    end
    A.pendingCandidates = choices
    local ctx = A.GetContext and A.GetContext()
    if ctx then ctx.pendingCandidates = SerializeChoices(choices) end
    return choices
end

function AP.CurrentPendingCandidates()
    if type(A.pendingCandidates) == "table" and #A.pendingCandidates > 0 then return A.pendingCandidates end
    local ctx = A.GetContext and A.GetContext()
    if ctx and type(ctx.pendingCandidates) == "table" then
        local candidates = RehydrateChoices(ctx.pendingCandidates)
        if #candidates > 0 then
            A.pendingCandidates = candidates
            return candidates
        end
        ctx.pendingCandidates = nil
    end
    return nil
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

-- Switching a lot of things off at once is the one bulk edit a user cannot
-- check afterwards: the frames they would look at to notice are the frames
-- that disappeared. bulkSafe only records that a multi-change plan was
-- deliberate ("apply this to every unit"), so it must not waive this one.
local DESTRUCTIVE_SWEEP_MINIMUM = 5

function AP.PlanIsDestructiveSweep(plan)
    if type(plan) ~= "table" or plan.kind ~= "changes" then return false end
    local changes = plan.changes
    if type(changes) ~= "table" or #changes < DESTRUCTIVE_SWEEP_MINIMUM then return false end
    local disabling = 0
    for i = 1, #changes do
        local change = changes[i]
        -- A planned change carries .value; only an executed one carries
        -- .newValue, and this runs before execution.
        local target = change and change.value
        if target == nil and change then target = change.newValue end
        if target == false or target == "disabled" or target == "hidden" then
            disabling = disabling + 1
        end
    end
    return disabling >= DESTRUCTIVE_SWEEP_MINIMUM
end

local function PlanNeedsConfirmation(plan)
    if type(plan) ~= "table" then return false end
    if plan.confirmRequired == true then return true end
    if plan.kind == "action" and plan.action and plan.action.confirmRequired == true then return true end
    if AnySettingFlag(plan, "confirmRequired") then return true end
    if type(plan.changes) == "table" and #plan.changes >= 6 and plan.bulkSafe ~= true then return true end
    if AP.PlanIsDestructiveSweep(plan) then return true end
    return false
end

local function ConfirmationText(plan)
    if type(plan) == "table" and type(plan.confirmText) == "string" and plan.confirmText ~= "" then
        return plan.confirmText
    end
    -- Name what disappears. "I can apply this action" is not enough warning
    -- when the answer is "seven of your frames stop being drawn".
    if AP.PlanIsDestructiveSweep(plan) then
        local lines = { "That switches off " .. tostring(#plan.changes) .. " MSUF options at once:" }
        local shown = math.min(6, #plan.changes)
        for i = 1, shown do
            local setting = plan.changes[i] and plan.changes[i].setting
            lines[#lines + 1] = "  " .. i .. ". " .. tostring((setting and setting.label) or "an MSUF option")
        end
        if #plan.changes > shown then
            lines[#lines + 1] = "  ... and " .. (#plan.changes - shown) .. " more."
        end
        lines[#lines + 1] = "You will not be able to see those frames afterwards, so I did not apply it yet."
        lines[#lines + 1] = "Answer with 'yes', 'do it', or 'apply' to go ahead, or 'cancel' to keep everything. You can also say 'undo' after applying."
        return table.concat(lines, "\n")
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

function AP.ContextNormalizedHasPhrase(normalized, phrase)
    normalized = tostring(normalized or "")
    phrase = NormalizeReply(phrase)
    if normalized == "" or phrase == "" then return false end
    return (" " .. normalized .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
end

function A.HasRelativeIntentMarker(text)
    local normalized = NormalizeReply(text)
    local markers = A.RELATIVE_INTENT_MARKERS or {}
    for i = 1, #markers do
        if AP.ContextNormalizedHasPhrase(normalized, markers[i]) then return true end
    end
    return false
end

function A.HasSmallNudgeIntent(text)
    local normalized = NormalizeReply(text)
    return AP.ContextNormalizedHasPhrase(normalized, "a bit")
        or AP.ContextNormalizedHasPhrase(normalized, "bit more")
        or AP.ContextNormalizedHasPhrase(normalized, "slightly")
        or AP.ContextNormalizedHasPhrase(normalized, "a little")
        or AP.ContextNormalizedHasPhrase(normalized, "little more")
        or AP.ContextNormalizedHasPhrase(normalized, "tiny")
end

-- Every verb that means "relatively reposition this element" (an X/Y offset),
-- as opposed to a fixed anchor.  Kept in one place because both the parser and
-- the router gate their move-vs-anchor decision on it; a verb missing here let
-- "drag/scoot/slide name to the left" silently set the Name Text Anchor.
A.NUDGE_MOVEMENT_VERBS = A.NUDGE_MOVEMENT_VERBS or {
    "move", "nudge", "shift", "push", "raise", "lower",
    "drag", "scoot", "slide", "bump", "pull", "reposition", "budge", "shove",
}
function A.HasNudgeMovementVerb(text)
    local normalized = NormalizeReply(text)
    for i = 1, #A.NUDGE_MOVEMENT_VERBS do
        if AP.ContextNormalizedHasPhrase(normalized, A.NUDGE_MOVEMENT_VERBS[i]) then return true end
    end
    return false
end

function AP.IsSpatialRelationshipIntent(text)
    local normalized = NormalizeReply(text)
    if normalized == "" then return false end
    -- These phrases describe where one MSUF object belongs relative to its
    -- owner or another object. They are not requests to add pixels after an
    -- already-satisfied side/anchor choice. Keep this list deliberately about
    -- relationships; comparative follow-ups such as "more to the right" must
    -- still reach the component-local nudge path.
    local phrases = {
        "next to", "beside", "alongside", "adjacent to", "relative to",
        "attached to", "attach to", "anchored to", "anchor to", "docked to", "dock to",
        "left side", "right side", "on top of", "at the top of", "at the bottom of",
        "top left", "top right", "bottom left", "bottom right",
        "top center", "bottom center", "center left", "center right",
        "on the left side", "on left side", "at the left side", "at left side",
        "on the right side", "on right side", "at the right side", "at right side",
        "to the left of", "left side of", "to the right of", "right side of",
        "above the", "above my", "above player", "above target", "above focus",
        "below the", "below my", "below player", "below target", "below focus",
        "under the", "under my", "under player", "under target", "under focus",
        "above frame", "below frame", "under frame", "over frame",
        "above boss", "below boss", "under boss", "over boss",
        "above pet", "below pet", "under pet", "over pet",
    }
    for i = 1, #phrases do
        if AP.ContextNormalizedHasPhrase(normalized, phrases[i]) then return true end
    end
    return false
end

function A.ExtractNudgeDirection(text)
    local normalized = NormalizeReply(text)
    if normalized == "" then return nil end
    if AP.ContextNormalizedHasPhrase(normalized, "to the right")
        or AP.ContextNormalizedHasPhrase(normalized, "rightward")
        or AP.ContextNormalizedHasPhrase(normalized, "rightwards")
        or AP.ContextNormalizedHasPhrase(normalized, "right") then
        return "right"
    end
    if AP.ContextNormalizedHasPhrase(normalized, "to the left")
        or AP.ContextNormalizedHasPhrase(normalized, "leftward")
        or AP.ContextNormalizedHasPhrase(normalized, "leftwards")
        or AP.ContextNormalizedHasPhrase(normalized, "left") then
        return "left"
    end
    if AP.ContextNormalizedHasPhrase(normalized, "upward")
        or AP.ContextNormalizedHasPhrase(normalized, "upwards")
        or AP.ContextNormalizedHasPhrase(normalized, "up") then
        return "up"
    end
    if AP.ContextNormalizedHasPhrase(normalized, "downward")
        or AP.ContextNormalizedHasPhrase(normalized, "downwards")
        or AP.ContextNormalizedHasPhrase(normalized, "down")
        or AP.ContextNormalizedHasPhrase(normalized, "lower") then
        return "down"
    end
    return nil
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
    local router = A.RouterPrivate
    if router and type(router.IsExplicitMutationRefusal) == "function"
        and router.IsExplicitMutationRefusal(text)
    then
        return true
    end
    local normalized = NormalizeReply(text)
    local withoutPrefix = normalized:gsub("^option%s+", ""):gsub("^choice%s+", ""):gsub("^select%s+", ""):gsub("^pick%s+", "")
    if normalized == "0" or withoutPrefix == "0" then return true end
    if normalized == "none" or withoutPrefix == "none" then return true end
    if normalized == "nothing" or withoutPrefix == "nothing" then return true end
    if normalized == "do nothing" or withoutPrefix == "do nothing" then return true end
    local phrases = {
        "nope", "never mind", "nevermind", "forget it", "leave it", "skip it",
        "cancel it", "cancel this", "cancel that", "abort it", "abort this", "abort that",
        "stop that", "stop it", "not now", "maybe later", "no thanks", "no thank you",
        "please do not", "please dont", "please don t",
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
    if IsChoiceAbort(text) then return false end
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
    if IsChoiceAbort(text) then return false end
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
    if IsChoiceAbort(text) then return false end
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
    if IsChoiceAbort(text) then return false end
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
    AP.ClearPendingCandidates()
    local ctx = A.GetContext and A.GetContext()
    if ctx then ctx.pendingChoices = nil end
end

function A.SetPendingChoices(choices)
    if type(choices) ~= "table" or #choices == 0 then
        ClearPendingChoices()
        return nil
    end
    A.pendingChoices = choices
    AP.SetPendingCandidates(choices)
    local ctx = A.GetContext and A.GetContext()
    if ctx then ctx.pendingChoices = SerializeChoices(A.pendingChoices) end
    return ChoiceText(A.pendingChoices)
end

AP.PendingChoiceOrdinalWords = AP.PendingChoiceOrdinalWords or {
    { word = "first", index = 1 }, { word = "second", index = 2 },
    { word = "third", index = 3 }, { word = "fourth", index = 4 },
    { word = "fifth", index = 5 }, { word = "sixth", index = 6 },
    { word = "seventh", index = 7 }, { word = "eighth", index = 8 },
    { word = "ninth", index = 9 }, { word = "tenth", index = 10 },
}

function AP.PendingChoiceExcludedOrdinalIndex(text, choices)
    choices = choices or {}
    local normalized = NormalizeReply(text)
    local padded = " " .. normalized .. " "
    local function HasPhrase(phrase)
        return padded:find(" " .. phrase .. " ", 1, true) ~= nil
    end

    local excluded, candidates = {}, {}
    local hasExclusion = false
    for i = 1, #AP.PendingChoiceOrdinalWords do
        local spec = AP.PendingChoiceOrdinalWords[i]
        if HasPhrase("not " .. spec.word)
            or HasPhrase("not the " .. spec.word)
            or HasPhrase("except " .. spec.word)
            or HasPhrase("except the " .. spec.word)
        then
            excluded[spec.index] = true
            hasExclusion = true
        end
    end

    if HasPhrase("not last") or HasPhrase("not the last")
        or HasPhrase("except last") or HasPhrase("except the last")
    then
        excluded[#choices] = true
        hasExclusion = true
    end

    if hasExclusion then
        for i = 1, #AP.PendingChoiceOrdinalWords do
            local spec = AP.PendingChoiceOrdinalWords[i]
            if choices[spec.index] and HasPhrase(spec.word) and not excluded[spec.index] then
                candidates[spec.index] = true
            end
        end
        if choices[#choices] and HasPhrase("last") and not excluded[#choices] then candidates[#choices] = true end

        local selected
        for index in pairs(candidates) do
            if selected ~= nil then return nil, true end
            selected = index
        end
        return selected, true
    end

    if normalized == "last" or normalized == "last one" or normalized == "the last" or normalized == "the last one" then
        return #choices > 0 and #choices or nil, true
    end
    return nil, false
end

function AP.PendingCandidateIndex(text, choices)
    choices = choices or {}
    local excludedSelection, handledExclusion = AP.PendingChoiceExcludedOrdinalIndex(text, choices)
    if handledExclusion then return excludedSelection end
    local normalized = NormalizeReply(text)
    normalized = normalized
        :gsub("^the%s+", "")
        :gsub("%s+one$", "")
        :gsub("%s+item$", "")
        :gsub("%s+option$", "")
        :gsub("%s+choice$", "")
    normalized = Trim(normalized:gsub("%s+", " "))

    local n = tonumber(normalized)
    if n and choices[n] then return n end
    n = tonumber(normalized:match("^(%d+)[a-z]+$"))
    if n and choices[n] then return n end
    n = tonumber(normalized:match("^option%s+(%d+)$")) or tonumber(normalized:match("^choice%s+(%d+)$")) or tonumber(normalized:match("^result%s+(%d+)$"))
    if n and choices[n] then return n end

    local stripped = normalized
        :gsub("^apply%s+", "")
        :gsub("^choose%s+", "")
        :gsub("^pick%s+", "")
        :gsub("^select%s+", "")
        :gsub("^use%s+", "")
        :gsub("^run%s+", "")
        :gsub("^execute%s+", "")
        :gsub("^option%s+", "")
        :gsub("^choice%s+", "")
        :gsub("^result%s+", "")
        :gsub("^number%s+", "")
    stripped = Trim(stripped:gsub("^the%s+", ""):gsub("%s+one$", ""):gsub("%s+", " "))
    n = tonumber(stripped)
    if n and choices[n] then return n end
    n = tonumber(stripped:match("^(%d+)[a-z]+$"))
    if n and choices[n] then return n end

    local wordToNumber = {
        first = 1, second = 2, third = 3, fourth = 4, fifth = 5,
        sixth = 6, seventh = 7, eighth = 8, ninth = 9, tenth = 10,
        one = 1, two = 2, three = 3, four = 4, five = 5,
        six = 6, seven = 7, eight = 8, nine = 9, ten = 10,
    }
    n = wordToNumber[stripped] or wordToNumber[normalized]
    if n and choices[n] then return n end
    return nil
end

local function FindChoice(text, choices)
    local normalized = NormalizeReply(text)
    local candidateIndex = AP.PendingCandidateIndex and AP.PendingCandidateIndex(text, choices)
    if candidateIndex and choices[candidateIndex] then return choices[candidateIndex] end
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

    -- Labels and value labels are the cheapest and most precise natural
    -- follow-up match. Resolve them before the legacy unit-name probe below;
    -- otherwise a reply such as "single color" needlessly invokes the full
    -- parser (and can warm/yield through its registry indexes) before reaching
    -- the already displayed choice text.
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
    return nil
end

local function FindExactDisplayedChoice(text, choices)
    local normalized = NormalizeReply(text)
    if normalized == "" then return nil end
    for i = 1, #(choices or {}) do
        local choice = choices[i]
        local setting = choice and choice.setting
        local action = choice and choice.action
        local labels = {
            choice and choice.label,
            choice and choice.valueLabel,
            setting and setting.label,
            action and action.label,
        }
        for j = 1, #labels do
            local label = NormalizeReply(labels[j] or "")
            if label ~= "" and label == normalized then return choice end
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
    gf_bars = "Group Dispel Overlay",
    gf_indicators = "Group Status & Indicators",
    gf_auras = "Group Auras",
    auras3 = "Auras",
    auras3_buffs = "Aura Buffs",
    auras3_debuffs = "Aura Debuffs",
    auras3_custom = "Custom Auras",
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
}

local PENDING_GROUP_EFFECT_KEY_PARTS = {
    "dispeloverlay",
    "debuffstripe",
}

local function PendingGroupSettingPage(setting)
    local attr = tostring(setting and setting.attribute or "")
    local key = NormalizeReply(setting and setting.key or ""):gsub("%s+", "")
    local attrNorm = NormalizeReply(attr):gsub("%s+", "")
    for i = 1, #PENDING_GROUP_INDICATOR_KEY_PARTS do
        local part = PENDING_GROUP_INDICATOR_KEY_PARTS[i]
        if attrNorm:find(part, 1, true) or key:find(part, 1, true) then return "gf_indicators" end
    end
    for i = 1, #PENDING_GROUP_EFFECT_KEY_PARTS do
        local part = PENDING_GROUP_EFFECT_KEY_PARTS[i]
        if attrNorm:find(part, 1, true) or key:find(part, 1, true) then return "gf_bars" end
    end
    if PENDING_GROUP_LAYOUT_ATTRS[attr] then return "gf_layout" end
    local suffix = tostring(setting and setting.key or ""):match("%.([^%.]+)$")
    if suffix and PENDING_GROUP_LAYOUT_ATTRS[suffix] then return "gf_layout" end
    return "gf_layout"
end

local function PendingSettingPage(setting)
    if type(setting) ~= "table" then return nil end
    local explicitPage = tostring(setting.page or "")
    if explicitPage ~= "" then return explicitPage end
    local unit = tostring(setting.unit or "")
    if unit ~= "" then
        if unit == "targettarget" then return "uf_targettarget" end
        if unit == "focustarget" then return "uf_focustarget" end
        return "uf_" .. unit
    end
    local category = NormalizeReply(setting.category or "")
    -- Class-resource colors are edited on the Colors page even though their
    -- runtime owner is classPower.  Keep follow-ups on the same concrete page
    -- selected by the Registry/Knowledge resolver.
    if category:find("color", 1, true) or category:find("colour", 1, true) then return "opt_colors" end
    local frameType = tostring(setting.frameType or "")
    if frameType == "group" then return PendingGroupSettingPage(setting) end
    if frameType == "castbar" then return "opt_castbar" end
    if frameType == "fonts" then return "opt_fonts" end
    if frameType == "bars" or frameType == "globalBars" then return "opt_bars" end
    if frameType == "classPower" then return "classpower" end
    if frameType == "gameplay" then return "gameplay" end
    if frameType == "modules" then return "modules" end
    if frameType == "groupAura" then return "gf_auras" end
    if frameType == "aura" then
        local unit = tostring(setting and setting.unit or "target"):lower()
        if unit == "party" or unit == "raid" or unit == "mythicraid" or unit:match("^gf_") then return "gf_auras" end
        if unit:match("^boss") then return "uf_boss" end
        if unit == "player" or unit == "target" or unit == "focus" then return "uf_" .. unit end
        return "uf_target"
    end
    if category:find("castbar", 1, true) or category:find("cast bar", 1, true) then return "opt_castbar" end
    if category:find("font", 1, true) then return "opt_fonts" end
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
    local excludedSelection, handledExclusion = AP.PendingChoiceExcludedOrdinalIndex(text, choices)
    if handledExclusion then return excludedSelection end
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

function AP.PortraitRenderFollowupPlan(text, sourceSetting)
    if not (sourceSetting and tostring(sourceSetting.attribute or "") == "portraitMode") then return nil end
    local normalized = NormalizeReply(text)
    local value
    if ReplyHasPhrase(normalized, "2d") or ReplyHasPhrase(normalized, "2d portrait") then
        value = "2D"
    elseif ReplyHasPhrase(normalized, "class portrait") then
        value = "CLASS"
    end
    if not value then return nil end
    local unit = tostring(sourceSetting.unit or "")
    local setting = unit ~= "" and Registry and Registry:GetSetting(unit .. ".portraitRender") or nil
    if not setting then return nil end
    return {
        kind = "changes",
        changes = { { setting = setting, value = value, valueLabel = SettingValueLabel(setting, value) } },
        label = AssistantSettingLabel(setting, "Portrait Render"),
        summary = "Continues a portrait choice by selecting its render type.",
    }
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
    local portraitPlan = AP.PortraitRenderFollowupPlan(text, item.setting)
    if portraitPlan then
        SetSelectedPendingResult(item, index)
        return A.ExecutePlan(portraitPlan)
    end
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
        kind = type(A.DisplaySettingControl) == "function"
            and A.DisplaySettingControl(item.setting, "noun") or "MSUF option"
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
    local settingKey = (item.kind == "setting" or item.setting) and (item.settingKey or item.key or (item.setting and item.setting.key)) or nil
    local actionKey = settingKey and "open_setting_control" or "open_page"
    local action = Registry and type(Registry.GetAction) == "function" and Registry:GetAction(actionKey) or nil
    if not action then
        return { text = "Open " .. tostring(label or page) .. " to inspect result " .. tostring(index or 1) .. ".", result = "info" }
    end
    return A.ExecutePlan({
        kind = "action",
        action = action,
        args = { page = page, label = item.label or label, settingKey = settingKey },
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

-- "What is it" is a follow-up; "what is <some other control>" is a new
-- request that merely starts with the same two words. The explain-intent test
-- only looks for the phrase, so leftover results from an earlier search used to
-- swallow a question about a completely different setting and explain result 1.
local function NamesSettingOutsidePendingResults(text, results)
    if type(A.RouterNamedSettingLabel) ~= "function" then return false end
    local label = A.RouterNamedSettingLabel(text)
    if not label or label == "" then return false end
    for i = 1, #(results or {}) do
        local item = results[i]
        local candidate = item and tostring((item.setting and item.setting.label) or item.label or "")
        if candidate ~= "" and candidate:lower() == label:lower() then return false end
    end
    return true
end

local function PendingResultFollowupResult(text, results)
    if not IsPendingResultReference(text) then return nil end
    if NamesSettingOutsidePendingResults(text, results) then return nil end
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
    if not item and not CurrentSelectedPendingResult() and #(results or {}) > 0 then
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
    -- A follow-up that spells out the control's own name is asking about it.
    -- The value words inside that name are part of the name: "show me Mythic
    -- Raid Masque Enabled" was read as "set it to enabled" and switched it on,
    -- but only once the control was already an active result -- which is why it
    -- passed every isolated test and only appeared deep into a long run.
    -- Explaining, locating and opening the result stay available below.
    local namedLookupFollowup = type(A.RouterIsNamedSettingLookup) == "function"
        and A.RouterIsNamedSettingLookup(text) == true
    local settingChange = not namedLookupFollowup
        and PendingResultSettingChangeResult(text, item, index) or nil
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
            successText = choice.successText,
        })
    end
    if choice and choice.setting then
        return A.ExecutePlan({
            kind = "changes",
            changes = { choice },
            label = "Assistant selected option",
            successText = choice.successText,
        })
    end
    -- A generated-schema control the player picked out of an ambiguity list.
    -- Schema.Execute owns the whole transaction (resolve, value normalization,
    -- undo snapshot), so this stays a thin hand-off.
    if choice and type(choice.schemaSemanticId) == "string" and choice.schemaSemanticId ~= "" then
        local Schema = A.ControlSchema
        if not (Schema and type(Schema.Execute) == "function") then
            return { text = "That option list changed. Start that change again and I'll rebuild the list.", result = "failed" }
        end
        local label = ChoiceDisplayLabel(choice) or choice.label or "that control"
        local ok, result = Schema.Execute(choice.schemaSemanticId, choice.value,
            { sourceText = choice.schemaSourceText })
        if type(result) == "table" then return result end
        if ok then
            return { text = "Done. I changed " .. tostring(label) .. ".", result = "applied", summary = label }
        end
        return { text = "I found " .. tostring(label) .. ", but the change could not be applied safely.",
            result = tostring(result or "failed"), summary = label }
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

function AP.RunApplies(changedSettings)
    local applied = {}
    for i = 1, #changedSettings do
        local setting = changedSettings[i]
        if setting and type(setting.apply) == "function" and not applied[setting.key] then
            applied[setting.key] = true
            local ok, applied, detail = pcall(setting.apply)
            if not ok or applied == false then
                return false, "apply", setting.key or setting.label or i,
                    ok and (detail or "apply callback returned false") or applied
            end
        end
    end
    local apply = (MSUF and MSUF.MSUF2 and MSUF.MSUF2.ApplyService) or _G.MSUF_Menu2_ApplyService
    if apply and type(apply.Flush) == "function" then
        local ok, flushed, detail = pcall(apply.Flush)
        if not ok or flushed == false then
            return false, "flush", "ApplyService.Flush",
                ok and (detail or "ApplyService.Flush returned false") or flushed
        end
    end
    return true
end

function AP.CopyTransactionValue(value)
    if type(value) ~= "table" then return value end
    if type(A.DeepCopy) == "function" then return A.DeepCopy(value) end
    local out = {}
    for key, child in pairs(value) do out[key] = AP.CopyTransactionValue(child) end
    return out
end

function AP.TransactionFailure(plan, phase, target, err, rollbackErrors)
    rollbackErrors = rollbackErrors or {}
    A.lastAssistantTransactionError = {
        phase = tostring(phase or "unknown"),
        target = tostring(target or ""),
        error = tostring(err or "unknown error"),
        rollbackErrors = rollbackErrors,
        time = type(_G.GetTime) == "function" and _G.GetTime() or nil,
    }
    local text
    local phaseText = tostring(phase or "")
    if (phaseText:find("preflight", 1, true) or phaseText == "read") and #rollbackErrors == 0 then
        text = "I could not safely validate that change, so no MSUF value was changed."
    elseif #rollbackErrors == 0 then
        text = "I could not safely apply that change, so I restored the previous MSUF values."
    else
        text = "I could not safely finish that change. I restored every value I could, but the runtime refresh also reported an error; use /reload before making another change."
    end
    return {
        text = text,
        result = "failed",
        summary = plan and plan.summary,
        transactionPhase = tostring(phase or "unknown"),
        transactionTarget = tostring(target or ""),
    }
end

function AP.RollbackSettingOperations(operations, changedSettings)
    local errors = {}
    for i = #operations, 1, -1 do
        local operation = operations[i]
        local setting = operation and operation.setting
        if setting and type(setting.set) == "function" then
            local transactionRestore = type(setting.restoreTransactionState) == "function" and operation.oldTransactionState ~= nil
            local restore = transactionRestore and setting.restoreTransactionState or setting.set
            local value = transactionRestore and operation.oldTransactionState or operation.oldValue
            local ok, restored = pcall(restore, AP.CopyTransactionValue(value), "MSUF_ASSISTANT_SETTING_ROLLBACK")
            if not ok or (transactionRestore and restored ~= true) then
                errors[#errors + 1] = "set:" .. tostring(setting.key or setting.label or i) .. ":" .. tostring(restored)
            end
        end
    end
    if #operations > 0 then
        local ok, phase, target, err = AP.RunApplies(changedSettings or {})
        if not ok then
            errors[#errors + 1] = tostring(phase) .. ":" .. tostring(target) .. ":" .. tostring(err)
        end
    end
    return errors
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

function AP.BuildSerializable(changes)
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

function AP.BuildUnchangedSerializable(changes)
    local out = {}
    local lastSetting, lastUnit, lastFrameType, lastCategory, lastValue
    for i = 1, #(changes or {}) do
        local item = changes[i]
        local setting = item and item.setting
        if setting then
            local currentValue
            if type(setting.get) == "function" then
                local ok, value = pcall(setting.get)
                if ok then currentValue = value end
            end
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

function AP.RememberUnchangedChangeContext(plan, changes)
    if not (A and type(A.RememberAppliedBundle) == "function") then return end
    local serializable, lastSetting, lastUnit, lastFrameType, lastCategory, lastValue = AP.BuildUnchangedSerializable(changes)
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

function AP.AppendUndoFollowupHint(text)
    text = tostring(text or "")
    if text:find(UNDO_FOLLOWUP_HINT, 1, true) then return text end
    return text .. "\n" .. UNDO_FOLLOWUP_HINT
end

function AP.AppendLargeChangeReloadHint(text)
    text = tostring(text or "")
    if text:find(LARGE_CHANGE_RELOAD_HINT, 1, true) then return text end
    return text .. "\n" .. LARGE_CHANGE_RELOAD_HINT
end

function AP.ChangedResponse(changedSettings, undoChanges)
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

function AP.AlreadySetResponse(changes)
    if type(changes) == "table" and #changes == 1 then
        local setting = changes[1].setting
        if setting and type(setting.get) == "function" then
            local ok, value = pcall(setting.get)
            if ok then return "Already set. " .. SettingLabel(setting) .. " is already " .. SettingValueLabel(setting, value) .. "." end
        end
    end
    return "Already set. MSUF already uses that value."
end

function AP.RefreshedAlreadySetResponse(setting)
    if setting and type(setting.get) == "function" then
        local ok, value = pcall(setting.get)
        if ok then return "Already set. " .. SettingLabel(setting) .. " is already " .. SettingValueLabel(setting, value) .. ". I refreshed it so the visible UI uses the current value." end
    end
    return "Already set. I refreshed the related MSUF option so the visible UI uses the current value."
end

function AP.BuildChangeBundle(plan, changes, undoChanges, lastSetting, lastUnit, lastFrameType, lastCategory, lastValue)
    return {
        label = AssistantPlanLabel(plan, "Assistant change"),
        action = "change",
        changes = undoChanges,
        lastSetting = lastSetting,
        lastUnit = lastUnit,
        lastFrameType = lastFrameType,
        lastCategory = lastCategory,
        lastValue = lastValue,
        serializable = AP.BuildSerializable(changes),
    }
end

function AP.AddContextAxisCandidate(out, seen, attr)
    attr = tostring(attr or "")
    if attr == "" or seen[attr] then return end
    seen[attr] = true
    out[#out + 1] = attr
end

function AP.AddContextAxisStemCandidates(out, seen, stem, axisSuffix)
    stem = tostring(stem or "")
    if stem == "" then return end
    AP.AddContextAxisCandidate(out, seen, stem .. "Offset" .. axisSuffix)
    AP.AddContextAxisCandidate(out, seen, stem .. axisSuffix)
    local textStem = stem:gsub("Text$", "")
    if textStem ~= stem and textStem ~= "" then
        AP.AddContextAxisCandidate(out, seen, textStem .. "Offset" .. axisSuffix)
        AP.AddContextAxisCandidate(out, seen, textStem .. axisSuffix)
    end
end

function AP.ContextAxisAttributeStem(attribute)
    attribute = tostring(attribute or "")
    -- Preserve the semantic text subject when a layer/strata setting is
    -- followed by movement. powerTextLayer -> powerText -> powerOffsetY,
    -- instead of falling through to the Unit Frame's generic offsetY.
    local suffixes = { "Alignment", "Anchor", "Align", "Side", "Layer", "Mode" }
    for i = 1, #suffixes do
        local suffix = suffixes[i]
        if #attribute > #suffix and attribute:sub(-#suffix) == suffix then
            return attribute:sub(1, #attribute - #suffix)
        end
    end
    return attribute
end

function AP.ContextSettingOwnsFrameRoot(setting)
    if type(setting) ~= "table" then return false end
    local category = tostring(setting.category or "")
    if category == "Frame" or category == "Anchoring" then return true end
    local attribute = tostring(setting.attribute or "")
    return attribute == "point" or attribute == "anchorPoint" or attribute == "anchorToUnitframe"
        or attribute == "offsetX" or attribute == "offsetY" or attribute == "x" or attribute == "y"
end

function AP.PickContextAxisSetting(candidates)
    local first
    for i = 1, #(candidates or {}) do
        local candidate = candidates[i]
        if candidate and candidate.type == "number" then
            if not first then first = candidate end
            if candidate.generated ~= true then return candidate end
        end
    end
    return first
end

function A.ResolveContextAxisSetting(setting, direction)
    if type(setting) ~= "table" then return nil end
    direction = tostring(direction or "")
    local axisSuffix
    if direction == "left" or direction == "right" then
        axisSuffix = "X"
    elseif direction == "up" or direction == "down" then
        axisSuffix = "Y"
    else
        return nil
    end

    local attrs, seen = {}, {}
    local axisLower = axisSuffix:lower()
    local declaredAxis = tostring(setting.moveAxis or "")
    if declaredAxis ~= "" then
        if declaredAxis:lower() == axisLower then
            AP.AddContextAxisCandidate(attrs, seen, setting.attribute)
        else
            AP.AddContextAxisCandidate(attrs, seen, declaredAxis)
        end
    end

    local stem = AP.ContextAxisAttributeStem(setting.attribute)
    AP.AddContextAxisStemCandidates(attrs, seen, stem, axisSuffix)

    local ctx = A.GetContext and A.GetContext() or nil
    if ctx and ctx.lastTextUnit == setting.unit and (setting.text == true or tostring(setting.category or ""):find("Text", 1, true)) then
        local area = tostring(ctx.lastTextArea or "")
        local slot = tostring(ctx.lastTextSlot or "")
        if area ~= "" then
            if slot == "left" or slot == "center" or slot == "right" then
                AP.AddContextAxisCandidate(attrs, seen, area .. "Text" .. slot:sub(1, 1):upper() .. slot:sub(2) .. "Offset" .. axisSuffix)
            end
            AP.AddContextAxisCandidate(attrs, seen, area .. "Offset" .. axisSuffix)
        end
    end

    -- Root X/Y is a valid companion only for a root-frame setting. A missing
    -- portrait/text/icon companion must fail closed instead of moving the
    -- entire unit frame as a seemingly reasonable fallback.
    if AP.ContextSettingOwnsFrameRoot(setting) then
        AP.AddContextAxisCandidate(attrs, seen, "offset" .. axisSuffix)
        AP.AddContextAxisCandidate(attrs, seen, axisLower)
    end

    local registry = A.Registry or Registry
    if not (registry and type(registry.FindSettings) == "function") then return nil end
    for i = 1, #attrs do
        local candidates = registry:FindSettings({
            unit = setting.unit,
            frameType = setting.frameType,
            attribute = attrs[i],
        })
        local match = AP.PickContextAxisSetting(candidates)
        if match then return match end
    end
    return nil
end

function AP.ContextEscalationAmount(axisSetting, sourceText)
    local amount = tonumber(axisSetting and (axisSetting.moveStep or axisSetting.moveAmount)) or 10
    if A.HasSmallNudgeIntent and A.HasSmallNudgeIntent(sourceText) then
        amount = amount / 2
        if amount < 2 then amount = 2 end
    end
    return amount
end

function AP.TryNoOpEscalation(plan, changes)
    if type(plan) ~= "table" or plan._noOpEscalated == true then return nil end
    if type(changes) ~= "table" or #changes ~= 1 then return nil end
    local change = changes[1]
    if type(change) ~= "table" or change.relativeDelta ~= nil then return nil end
    local setting = change.setting
    if type(setting) ~= "table" or setting.type == "number" then return nil end

    local sourceText = tostring(plan.sourceText or A._currentInputText or "")
    if sourceText == "" then return nil end
    if AP.IsSpatialRelationshipIntent(sourceText) then return nil end
    local direction = A.ExtractNudgeDirection and A.ExtractNudgeDirection(sourceText) or nil
    if not direction then return nil end

    local hasRelativeMarker = A.HasRelativeIntentMarker and A.HasRelativeIntentMarker(sourceText)
    if not hasRelativeMarker and not (A.HasNudgeMovementVerb and A.HasNudgeMovementVerb(sourceText)) then return nil end

    local axisSetting = A.ResolveContextAxisSetting(setting, direction)
    if not axisSetting then return nil end
    local amount = AP.ContextEscalationAmount(axisSetting, sourceText)
    if direction == "left" or direction == "down" then amount = -math.abs(amount) else amount = math.abs(amount) end
    if amount == 0 then return nil end

    return AP.ExecuteChanges({
        kind = "changes",
        changes = {
            {
                setting = axisSetting,
                relativeDelta = amount,
                direction = direction,
            },
        },
        summary = plan.summary,
        label = plan.label,
        sourceText = sourceText,
        _noOpEscalated = true,
    })
end

local GROUP_NAME_SHORTENING_FIELDS = {
    "fontOverride", "nameShortenEnabled", "nameMaxChars", "nameClipSide", "nameNoEllipsis",
    "nameShortenOverride", "_msufGFNameTruncationOverride",
}

local UNIT_NAME_SHORTENING_FIELDS = {
    "fontOverride", "shortenNames", "shortenNameMaxChars", "shortenNameClipSide", "shortenNameShowDots",
}

local function NameShorteningStateScopes(changes)
    local scopes, seen = {}, {}
    for i = 1, #(changes or {}) do
        local key = tostring(changes[i] and changes[i].setting and changes[i].setting.key or "")
        local scope, suffix = key:match("^fontScope%.([^.]+)%.(.+)$")
        local isNameSetting = suffix == "shortenNames" or suffix == "shortenNameMaxChars"
            or suffix == "shortenNameClipSide" or suffix == "shortenNameNoEllipsis"
        if not isNameSetting then
            scope, suffix = key:match("^(gf_[^.]+)%.(.+)$")
            isNameSetting = suffix == "nameShortenEnabled" or suffix == "nameMaxChars"
                or suffix == "nameClipSide" or suffix == "nameNoEllipsis"
        end
        if isNameSetting and scope and scope ~= "shared" and not seen[scope] then
            seen[scope] = true
            scopes[#scopes + 1] = scope
        end
    end
    return scopes
end

function A.CaptureNameShorteningStates(scopes)
    if type(scopes) ~= "table" or #scopes == 0 then return nil end
    local db = M and type(M.EnsureDB) == "function" and M.EnsureDB() or _G.MSUF_DB
    if type(db) ~= "table" then return nil end
    local states = {}
    for i = 1, #scopes do
        local scope = tostring(scopes[i] or "")
        if scope ~= "" then
            local conf = type(db[scope]) == "table" and db[scope] or nil
            local fields = scope:find("^gf_") and GROUP_NAME_SHORTENING_FIELDS or UNIT_NAME_SHORTENING_FIELDS
            local state = { scope = scope, scopeWasTable = conf ~= nil, fields = {} }
            conf = conf or {}
            for j = 1, #fields do
                local field = fields[j]
                local value = rawget(conf, field)
                state.fields[field] = {
                    present = value ~= nil,
                    value = AP.CopyTransactionValue(value),
                }
            end
            states[#states + 1] = state
        end
    end
    return #states > 0 and states or nil
end

function A.RestoreNameShorteningStates(states)
    if type(states) ~= "table" then return false end
    local db = M and type(M.EnsureDB) == "function" and M.EnsureDB() or _G.MSUF_DB
    if type(db) ~= "table" then return false end
    for i = 1, #states do
        local state = states[i]
        local scope = type(state) == "table" and tostring(state.scope or "") or ""
        if scope ~= "" and type(state.fields) == "table" then
            local conf = type(db[scope]) == "table" and db[scope] or {}
            db[scope] = conf
            for field, saved in pairs(state.fields) do
                if type(saved) == "table" and saved.present == true then
                    conf[field] = AP.CopyTransactionValue(saved.value)
                else
                    conf[field] = nil
                end
            end
            if state.scopeWasTable ~= true and next(conf) == nil then db[scope] = nil end
        end
    end
    return true
end

-- Open the real Menu2 Color Painter on an Assistant-resolved setting. This is
-- intentionally a cold, user-triggered bridge: the Assistant does not own a
-- second picker and does not keep any picker state while idle.
function A.OpenColorSettingPickerForSetting(setting, page, label)
    if not (type(setting) == "table" and setting.type == "color") then return false, "not_color" end
    local settingKey = tostring(setting.key or "")
    if settingKey == "" then return false, "missing_setting_key" end

    page = tostring(page or setting.page or "")
    label = tostring(label or setting.label or settingKey)
    local schema = A.ControlSchema
    if page == "" and schema and type(schema.GetBySettingKey) == "function" then
        local descriptors = schema.GetBySettingKey(settingKey)
        for i = 1, #(descriptors or {}) do
            local descriptor = descriptors[i]
            if tostring(descriptor and descriptor.kind or "") == "color"
                and tostring(descriptor.pageKey or "") ~= ""
            then
                page = tostring(descriptor.pageKey)
                if label == settingKey and tostring(descriptor.label or "") ~= "" then
                    label = tostring(descriptor.label)
                end
                break
            end
        end
    end
    if page == "" then
        local router = A.RouterPrivate
        local item = router and type(router.RegistrySettingItemForKey) == "function"
            and router.RegistrySettingItemForKey(settingKey) or nil
        page = tostring(item and item.page or "")
        if label == settingKey and item and item.label then label = tostring(item.label) end
    end
    if page == "" then return false, "missing_page" end

    local openPicker = _G.MSUF_OpenExactColorSettingPicker
        or (M and M.OpenExactColorSettingPicker)
    if type(openPicker) ~= "function" then return false, "picker_unavailable" end
    local called, opened, message = pcall(openPicker, settingKey, label, page)
    if not called then return false, tostring(opened or "picker_failed") end
    return opened ~= false, message
end

function AP.TryOpenSingleColorSettingPicker(changes)
    local selected, selectedKey
    for i = 1, #(changes or {}) do
        local setting = changes[i] and changes[i].setting
        if setting and setting.type == "color" then
            local key = tostring(setting.key or setting)
            if selected and key ~= selectedKey then return false, "multiple_color_settings" end
            selected, selectedKey = setting, key
        end
    end
    if not selected then return false, "no_color_setting" end
    return A.OpenColorSettingPickerForSetting(selected)
end

local function ExecuteChanges(plan)
    local changes = plan.changes or {}
    local nameStateScopes = NameShorteningStateScopes(changes)
    local beforeNameShorteningStates = A.CaptureNameShorteningStates(nameStateScopes)
    local undoChanges = {}
    local undoIndexByKey = {}
    local executedChanges = {}
    local changedSettings = {}
    local responseSettings = {}
    local unchangedApplySettings = {}
    local lastSetting, lastUnit, lastFrameType, lastCategory, lastValue
    local requiresReload

    local function RestoreNameStateSnapshot()
        if beforeNameShorteningStates then
            pcall(A.RestoreNameShorteningStates, beforeNameShorteningStates)
        end
    end

    local refreshedDomains = {}

    local function ResolveNewValue(setting, item, oldValue)
        local newValue = item.value
        if item.relativeDelta ~= nil then
            if setting.type ~= "number" then return false, "relative change requires a number setting" end
            if not A.IsFiniteAssistantNumber(oldValue) then return false, "relative change requires a finite current value" end
            if not A.IsFiniteAssistantNumber(item.relativeDelta) then return false, "relative change requires a finite delta" end
            newValue = oldValue + item.relativeDelta
        end
        local domainSetting = setting.type == "enum" or (setting.type == "string" and setting.closedValues == true)
        local skipRefresh = domainSetting and refreshedDomains[setting] == true
        local ok, normalized = A.NormalizeRegistrySettingValue(setting, newValue, { skipRefresh = skipRefresh })
        if ok and domainSetting then refreshedDomains[setting] = true end
        return ok, normalized
    end

    -- Resolve every target and read every starting value before the first write.
    -- This keeps malformed multi-setting plans from partially mutating the DB.
    local prepared = {}
    local virtualValues = {}
    local virtualKnown = {}
    for i = 1, #changes do
        local item = changes[i]
        local setting = item and item.setting
        if not (setting and type(setting.get) == "function" and type(setting.set) == "function") then
            return AP.TransactionFailure(plan, "preflight", setting and (setting.key or setting.label) or i, "setting is not readable and writable")
        end
        local oldValue
        if virtualKnown[setting] then
            oldValue = AP.CopyTransactionValue(virtualValues[setting])
        else
            local ok, value = pcall(setting.get)
            if not ok then
                return AP.TransactionFailure(plan, "preflight.read", setting.key or setting.label or i, value)
            end
            oldValue = AP.CopyTransactionValue(value)
        end
        local valueOk, newValue = ResolveNewValue(setting, item, oldValue)
        if not valueOk then
            return AP.TransactionFailure(plan, "preflight.value", setting.key or setting.label or i, newValue)
        end
        prepared[#prepared + 1] = {
            item = item,
            setting = setting,
            newValue = AP.CopyTransactionValue(newValue),
        }
        virtualKnown[setting] = true
        virtualValues[setting] = AP.CopyTransactionValue(newValue)
    end

    local appliedOperations = {}
    local committed = {}
    for i = 1, #prepared do
        local pending = prepared[i]
        local item = pending.item
        local setting = pending.setting
        local readOk, currentValue = pcall(setting.get)
        if not readOk then
            local rollbackErrors = AP.RollbackSettingOperations(appliedOperations, changedSettings)
            RestoreNameStateSnapshot()
            return AP.TransactionFailure(plan, "read", setting.key or setting.label or i, currentValue, rollbackErrors)
        end
        local oldValue = AP.CopyTransactionValue(currentValue)
        local newValue = AP.CopyTransactionValue(pending.newValue)
        if ValuesEqual(setting, oldValue, newValue) then
            if setting.applyWhenUnchanged == true then unchangedApplySettings[#unchangedApplySettings + 1] = setting end
        else
            local oldTransactionState
            local hasCapture = type(setting.captureTransactionState) == "function"
            local hasRestore = type(setting.restoreTransactionState) == "function"
            if hasCapture ~= hasRestore then
                local rollbackErrors = AP.RollbackSettingOperations(appliedOperations, changedSettings)
                RestoreNameStateSnapshot()
                return AP.TransactionFailure(plan, "preflight.transaction-state", setting.key or setting.label or i,
                    "setting transaction-state capture and restore must be declared together", rollbackErrors)
            end
            if hasCapture then
                local captureOk, captured = pcall(setting.captureTransactionState)
                if not captureOk or captured == nil then
                    local rollbackErrors = AP.RollbackSettingOperations(appliedOperations, changedSettings)
                    RestoreNameStateSnapshot()
                    return AP.TransactionFailure(plan, "preflight.transaction-state", setting.key or setting.label or i, captured, rollbackErrors)
                end
                oldTransactionState = AP.CopyTransactionValue(captured)
            end
            local setOk, setErr = pcall(setting.set, AP.CopyTransactionValue(newValue))
            if not setOk then
                local currentRestoreError
                if hasRestore then
                    local restored, detail = pcall(setting.restoreTransactionState,
                        AP.CopyTransactionValue(oldTransactionState), "MSUF_ASSISTANT_SETTING_SET_ROLLBACK")
                    if not restored or detail ~= true then currentRestoreError = detail end
                end
                local rollbackErrors = AP.RollbackSettingOperations(appliedOperations, changedSettings)
                if currentRestoreError ~= nil then
                    rollbackErrors[#rollbackErrors + 1] = "set:" .. tostring(setting.key or setting.label or i)
                        .. ":" .. tostring(currentRestoreError)
                end
                RestoreNameStateSnapshot()
                return AP.TransactionFailure(plan, "set", setting.key or setting.label or i, setErr, rollbackErrors)
            end

            local operation = { setting = setting, oldValue = oldValue, oldTransactionState = oldTransactionState }
            appliedOperations[#appliedOperations + 1] = operation
            changedSettings[#changedSettings + 1] = setting

            local verifyOk, actualNewValue = pcall(setting.get)
            if not verifyOk then
                local rollbackErrors = AP.RollbackSettingOperations(appliedOperations, changedSettings)
                RestoreNameStateSnapshot()
                return AP.TransactionFailure(plan, "verify.read", setting.key or setting.label or i, actualNewValue, rollbackErrors)
            end
            actualNewValue = AP.CopyTransactionValue(actualNewValue)
            local acceptsNormalization = setting.normalizesValue == true or setting.type == "color"
            if ValuesEqual(setting, oldValue, actualNewValue) and acceptsNormalization then
                -- The setter legitimately normalized the requested representation
                -- back to the value already stored. This is an idempotent success,
                -- not a failed write and not an undoable mutation.
                table.remove(appliedOperations)
                table.remove(changedSettings)
                if setting.applyWhenUnchanged == true then unchangedApplySettings[#unchangedApplySettings + 1] = setting end
            else
                if ValuesEqual(setting, oldValue, actualNewValue) then
                    local rollbackErrors = AP.RollbackSettingOperations(appliedOperations, changedSettings)
                    RestoreNameStateSnapshot()
                    return AP.TransactionFailure(plan, "verify.unchanged", setting.key or setting.label or i, "setter did not change the requested value", rollbackErrors)
                end
                if not acceptsNormalization and not ValuesEqual(setting, newValue, actualNewValue) then
                    local rollbackErrors = AP.RollbackSettingOperations(appliedOperations, changedSettings)
                    RestoreNameStateSnapshot()
                    return AP.TransactionFailure(plan, "verify.value", setting.key or setting.label or i, "stored value differs from requested value", rollbackErrors)
                end

                local valueLabel = item.valueLabel
                if not ValuesEqual(setting, newValue, actualNewValue) then
                    valueLabel = SettingValueLabel(setting, actualNewValue)
                end
                local newTransactionState
                if hasCapture then
                    local captureOk, captured = pcall(setting.captureTransactionState)
                    if not captureOk or captured == nil then
                        local rollbackErrors = AP.RollbackSettingOperations(appliedOperations, changedSettings)
                        RestoreNameStateSnapshot()
                        return AP.TransactionFailure(plan, "verify.transaction-state", setting.key or setting.label or i, captured, rollbackErrors)
                    end
                    newTransactionState = AP.CopyTransactionValue(captured)
                end
                operation.newValue = actualNewValue
                operation.newTransactionState = newTransactionState
                committed[#committed + 1] = {
                    item = item,
                    setting = setting,
                    oldValue = oldValue,
                    newValue = actualNewValue,
                    valueLabel = valueLabel,
                    oldTransactionState = oldTransactionState,
                    newTransactionState = newTransactionState,
                }
            end
        end
    end

    if #committed == 0 then
        if A.ContextEngineEnabled ~= false then
            local escalated = AP.TryNoOpEscalation(plan, changes)
            if escalated then return escalated end
        end
        if #unchangedApplySettings > 0 then
            local ok, phase, target, err = AP.RunApplies(unchangedApplySettings)
            if not ok then return AP.TransactionFailure(plan, phase, target, err) end
            AP.RememberUnchangedChangeContext(plan, changes)
            local first = unchangedApplySettings[1]
            local pickerOpened = AP.TryOpenSingleColorSettingPicker(changes)
            return { text = AP.RefreshedAlreadySetResponse(first), result = "unchanged", summary = plan.summary,
                colorPickerOpened = pickerOpened == true or nil }
        end
        AP.RememberUnchangedChangeContext(plan, changes)
        local pickerOpened = AP.TryOpenSingleColorSettingPicker(changes)
        return { text = AP.AlreadySetResponse(changes), result = "unchanged", summary = plan.summary,
            colorPickerOpened = pickerOpened == true or nil }
    end

    local applyOk, applyPhase, applyTarget, applyErr = AP.RunApplies(changedSettings)
    if not applyOk then
        local rollbackErrors = AP.RollbackSettingOperations(appliedOperations, changedSettings)
        RestoreNameStateSnapshot()
        return AP.TransactionFailure(plan, applyPhase, applyTarget, applyErr, rollbackErrors)
    end

    for i = 1, #committed do
        local record = committed[i]
        local item = record.item
        local setting = record.setting
        item.oldValue = record.oldValue
        item.newValue = record.newValue
        item.valueLabel = record.valueLabel
        local undoKey = setting.key or setting
        local undoIndex = undoIndexByKey[undoKey]
        if undoIndex then
            undoChanges[undoIndex].newValue = record.newValue
            undoChanges[undoIndex].valueLabel = record.valueLabel
            undoChanges[undoIndex].newTransactionState = record.newTransactionState
            responseSettings[undoIndex] = setting
        else
            undoChanges[#undoChanges + 1] = {
                key = setting.key,
                oldValue = record.oldValue,
                newValue = record.newValue,
                valueLabel = record.valueLabel,
                oldTransactionState = record.oldTransactionState,
                newTransactionState = record.newTransactionState,
            }
            undoIndexByKey[undoKey] = #undoChanges
            responseSettings[#responseSettings + 1] = setting
        end
        executedChanges[#executedChanges + 1] = item
        lastSetting = setting.key
        lastUnit = setting.unit
        lastFrameType = setting.frameType
        lastCategory = setting.category
        lastValue = record.newValue
        if setting.requiresReload == true then requiresReload = true end
    end

    local bundle = AP.BuildChangeBundle(plan, executedChanges, undoChanges, lastSetting, lastUnit, lastFrameType, lastCategory, lastValue)
    if beforeNameShorteningStates then
        bundle.beforeNameShorteningStates = beforeNameShorteningStates
        bundle.afterNameShorteningStates = A.CaptureNameShorteningStates(nameStateScopes)
    end
    local pushOk, undoAvailable = pcall(A.PushUndo, bundle)
    if not pushOk then
        local rollbackErrors = AP.RollbackSettingOperations(appliedOperations, changedSettings)
        RestoreNameStateSnapshot()
        return AP.TransactionFailure(plan, "commit.undo", lastSetting, undoAvailable, rollbackErrors)
    end
    bundle.undoAvailable = undoAvailable == true
    local rememberOk, rememberErr = pcall(A.RememberAppliedBundle, bundle)
    if not rememberOk then
        if bundle.undoAvailable and type(A.undoStack) == "table" and A.undoStack[#A.undoStack] == bundle then
            table.remove(A.undoStack)
        end
        local rollbackErrors = AP.RollbackSettingOperations(appliedOperations, changedSettings)
        RestoreNameStateSnapshot()
        return AP.TransactionFailure(plan, "commit.context", lastSetting, rememberErr, rollbackErrors)
    end

    for i = 1, #committed do
        local record = committed[i]
        if record.item.direction then A.SetContextValue("lastDirection", record.item.direction) end
        RememberTextChangeContext(record.setting, record.item, record.newValue)
    end

    local customSuccess = type(plan.successText) == "string" and Trim(plan.successText) or ""
    local text = customSuccess ~= "" and customSuccess or AP.ChangedResponse(responseSettings, undoChanges)
    if requiresReload then text = text .. " Reload the UI for this change to fully take effect." end
    if not requiresReload and #undoChanges >= 6 then text = AP.AppendLargeChangeReloadHint(text) end
    text = AP.AppendUndoFollowupHint(text)
    local pickerOpened = AP.TryOpenSingleColorSettingPicker(committed)
    return { text = text, result = "applied", summary = plan.summary,
        colorPickerOpened = pickerOpened == true or nil }
end

AP.ExecuteChanges = ExecuteChanges

function AP.ActionResponse(action, plan, message)
    message = Trim(message or "")
    if message == "" or message == "Done." then
        return "Done. I ran " .. AssistantPlanLabel(plan, AssistantActionLabel(action, "that MSUF task")) .. "."
    end
    if message:find("^Done%.") or message:find("^Already set%.") then return message end
    return "Done. " .. message
end

function AP.ReadOnlyActionResponse(action, plan, message)
    message = Trim(message or "")
    message = message:gsub("^Done%.%s*", "")
    if message ~= "" then return message end
    return AssistantPlanLabel(plan, AssistantActionLabel(action, "MSUF information"))
end

local function ExecuteAction(plan)
    local action = plan.action
    if not (action and type(action.run) == "function") then
        return { text = "Open the MSUF menu first so I can run that task.", result = "failed", summary = plan.summary }
    end
    local mutability = tostring(action.mutability or "")
    if mutability ~= "readOnly" and mutability ~= "navigation"
        and mutability ~= "ephemeral" and mutability ~= "savedState"
    then
        return AP.TransactionFailure(plan, "preflight.action_policy", action.key, "action mutability policy is missing or invalid")
    end
    local args = plan.args or {}
    local actionKey = type(action.key) == "string" and action.key or ""
    local inputCatalog = A.ActionInputs
    local getInputContract = inputCatalog and inputCatalog.GetContract
    local normalizeActionInput = A.NormalizeAssistantActionInput
    if actionKey == "" or type(getInputContract) ~= "function" or type(normalizeActionInput) ~= "function" then
        return AP.TransactionFailure(plan, "preflight.action_input", action.key,
            "explicit action input contract is unavailable")
    end
    local contractOk, inputContract = pcall(getInputContract, actionKey)
    if not contractOk or type(inputContract) ~= "table" then
        return AP.TransactionFailure(plan, "preflight.action_input", action.key,
            contractOk and "explicit action input contract is unavailable" or inputContract)
    end
    -- The catalog key is authoritative.  Never accept a contract supplied on
    -- an action table, because plans and test doubles may carry copied or
    -- forged metadata even when their action key is legitimate.
    local inputOk, normalizedArgs, inputError = pcall(normalizeActionInput, actionKey, args)
    if not inputOk or type(normalizedArgs) ~= "table" then
        return AP.TransactionFailure(plan, "preflight.action_input", action.key,
            inputOk and inputError or normalizedArgs)
    end
    args = normalizedArgs
    plan.args = normalizedArgs
    local adapterName = action.transactionAdapter
    local adapterMode
    if adapterName ~= nil then
        if action.transactionAdapterReady ~= true then
            return AP.TransactionFailure(plan, "preflight.action_adapter", action.key, "action transaction adapter is not ready")
        end
        if type(A.GetActionTransactionAdapterMode) ~= "function" then
            return AP.TransactionFailure(plan, "preflight.action_adapter", action.key, "action transaction adapter service is unavailable")
        end
        adapterMode = A.GetActionTransactionAdapterMode(adapterName, action.key)
        if adapterMode == nil or (action.transactionAdapterMode ~= nil and action.transactionAdapterMode ~= adapterMode) then
            return AP.TransactionFailure(plan, "preflight.action_adapter", action.key, "unknown, unsupported, or mismatched action transaction adapter")
        end
    elseif action.rollbackStrategy == "transactionAdapter" then
        return AP.TransactionFailure(plan, "preflight.action_adapter", action.key, "action transaction adapter is missing")
    end

    local captureAction = adapterMode == "capturedOwnerState" and A.CaptureActionTransaction or nil
    if adapterMode == "capturedOwnerState"
        and (type(captureAction) ~= "function" or type(A.RestoreActionTransaction) ~= "function")
    then
        return AP.TransactionFailure(plan, "preflight.action_adapter", action.key, "captured owner-state services are unavailable")
    end
    local before
    local beforeProfile
    local beforeAction
    local captureProfile = not captureAction and action.captureProfileSnapshot and A.CaptureProfileSnapshot
    local captureSnapshot = not captureAction and action.captureSnapshot and not captureProfile and A.CaptureSnapshot
    if not captureAction and action.captureSnapshot == true and type(captureSnapshot) ~= "function" then
        return AP.TransactionFailure(plan, "preflight.snapshot", action.key, "snapshot service is unavailable")
    end
    if not captureAction and action.captureProfileSnapshot == true and type(captureProfile) ~= "function" then
        return AP.TransactionFailure(plan, "preflight.profile_snapshot", action.key, "profile snapshot service is unavailable")
    end
    if captureAction then
        local snapshotOk, snapshot, snapshotErr = pcall(captureAction, action.key, args, adapterName)
        if not snapshotOk or type(snapshot) ~= "table" then
            return AP.TransactionFailure(plan, "preflight.action_owner_snapshot", action.key, snapshotErr or snapshot)
        end
        beforeAction = snapshot
    elseif captureSnapshot then
        local snapshotOk, snapshot = pcall(captureSnapshot)
        if not snapshotOk or type(snapshot) ~= "table" then
            return AP.TransactionFailure(plan, "preflight.snapshot", action.key, snapshot)
        end
        before = snapshot
    end
    if captureProfile then
        local snapshotOk, snapshot = pcall(captureProfile, action.key, args)
        if not snapshotOk or type(snapshot) ~= "table" then
            return AP.TransactionFailure(plan, "preflight.profile_snapshot", action.key, snapshot)
        end
        beforeProfile = snapshot
    end
    local function RollbackAction()
        local errors = {}
        if beforeAction then
            local restored, value, detail = pcall(A.RestoreActionTransaction, beforeAction, "MSUF_ASSISTANT_ACTION_ROLLBACK")
            if not restored or value ~= true then errors[#errors + 1] = tostring(detail or value or "action owner restore failed") end
        elseif beforeProfile then
            if type(A.RestoreProfileSnapshot) ~= "function" then
                errors[#errors + 1] = "profile restore service is unavailable"
            else
                local restored, value = pcall(A.RestoreProfileSnapshot, beforeProfile)
                if not restored or value ~= true then errors[#errors + 1] = tostring(value or "profile restore failed") end
                if restored and value == true and type(A.RequestBroadApply) == "function" then
                    local applyOk, applyErr = pcall(A.RequestBroadApply, "MSUF_ASSISTANT_ACTION_ROLLBACK")
                    if not applyOk then errors[#errors + 1] = tostring(applyErr) end
                end
            end
        elseif before then
            if type(A.RestoreSnapshot) ~= "function" then
                errors[#errors + 1] = "snapshot restore service is unavailable"
            else
                local restored, value = pcall(A.RestoreSnapshot, before, "MSUF_ASSISTANT_ACTION_ROLLBACK")
                if not restored or value ~= true then errors[#errors + 1] = tostring(value or "snapshot restore failed") end
            end
        end
        return errors
    end

    local preserveNilSavedVariables
    local ran, ok, message, runMeta = pcall(function() return action.run(args) end)
    if not ran or not ok then
        -- Some action guards can prove that they rejected the request before
        -- touching owner state. Preserve their useful guidance instead of
        -- describing a rollback that did not happen. This escape hatch is
        -- deliberately explicit so ordinary false returns still restore the
        -- captured snapshot below.
        if ran and type(runMeta) == "table"
            and runMeta.noMutation == true
            and runMeta.userFacingFailure == true
        then
            return {
                text = Trim(message or "I could not complete that MSUF task."),
                result = "failed",
                summary = plan.summary,
            }
        end
        local rollbackErrors = RollbackAction()
        if not before and not beforeProfile and not beforeAction then
            local failureMessage = ran and message or nil
            A.lastAssistantTransactionError = {
                phase = "action.run",
                target = tostring(action.key or ""),
                error = tostring(ran and message or ok),
                rollbackUnavailable = true,
            }
            return {
                text = tostring(failureMessage or "I could not complete that MSUF task. I did not record it as applied; verify the current setting before retrying."),
                result = "failed",
                summary = plan.summary,
                transactionPhase = "action.run",
                transactionTarget = action.key,
            }
        end
        return AP.TransactionFailure(plan, "action.run", action.key, ran and message or ok, rollbackErrors)
    end
    if A._preserveNilSavedVariablesUntilReload == true
        and rawget(_G, "MSUF_DB") == nil
        and rawget(_G, "MSUF_GlobalDB") == nil
        and rawget(_G, "MSUF_ActiveProfile") == nil
    then
        preserveNilSavedVariables = true
    end
    local undoAvailable = false
    local committedUndoBundle
    local undoStackBeforePush
    local redoStackBeforePush
    local noChange = type(runMeta) == "table" and runMeta.noChange == true
    if (before or beforeProfile or beforeAction) and not noChange then
        local after
        local afterProfile
        local afterAction
        if captureAction then
            local afterOk, snapshot, snapshotErr = pcall(captureAction, action.key, args, adapterName, beforeAction)
            if not afterOk or type(snapshot) ~= "table" then
                local rollbackErrors = RollbackAction()
                return AP.TransactionFailure(plan, "commit.action_owner_snapshot", action.key, snapshotErr or snapshot, rollbackErrors)
            end
            afterAction = snapshot
            if adapterName == "factoryResetAll"
                and snapshot.state and snapshot.state.globalDB and snapshot.state.globalDB.exists ~= true
                and snapshot.state.db and snapshot.state.db.exists ~= true
                and snapshot.state.activeProfile and snapshot.state.activeProfile.exists ~= true
            then
                preserveNilSavedVariables = true
                A._preserveNilSavedVariablesUntilReload = true
            end
        elseif captureSnapshot then
            local afterOk, snapshot = pcall(captureSnapshot)
            if not afterOk or type(snapshot) ~= "table" then
                local rollbackErrors = RollbackAction()
                return AP.TransactionFailure(plan, "commit.snapshot", action.key, snapshot, rollbackErrors)
            end
            after = snapshot
        end
        if captureProfile then
            local afterOk, snapshot = pcall(captureProfile, action.key, args)
            if not afterOk or type(snapshot) ~= "table" then
                local rollbackErrors = RollbackAction()
                return AP.TransactionFailure(plan, "commit.profile_snapshot", action.key, snapshot, rollbackErrors)
            end
            afterProfile = snapshot
        end
        local undoBundle = {
            label = AssistantPlanLabel(plan, AssistantActionLabel(action, "Assistant task")),
            action = action.key,
            beforeSnapshot = before,
            afterSnapshot = after,
            beforeProfileSnapshot = beforeProfile,
            afterProfileSnapshot = afterProfile,
            beforeActionTransaction = beforeAction,
            afterActionTransaction = afterAction,
        }
        undoStackBeforePush = {}
        redoStackBeforePush = {}
        for i = 1, #(A.undoStack or {}) do undoStackBeforePush[i] = A.undoStack[i] end
        for i = 1, #(A.redoStack or {}) do redoStackBeforePush[i] = A.redoStack[i] end
        local pushOk, pushed = pcall(A.PushUndo, undoBundle)
        if not pushOk or pushed ~= true then
            A.undoStack = undoStackBeforePush or {}
            A.redoStack = redoStackBeforePush or {}
            local rollbackErrors = RollbackAction()
            return AP.TransactionFailure(plan, "commit.undo", action.key, pushOk and "undo bundle was rejected" or pushed, rollbackErrors)
        end
        committedUndoBundle = undoBundle
        undoAvailable = true
    end
    local text = mutability == "readOnly"
        and AP.ReadOnlyActionResponse(action, plan, message)
        or AP.ActionResponse(action, plan, message)
    local actionArgs
    if action.key == "copy_unit" or action.key == "copy_group" then
        actionArgs = CopySerializableActionArgs(args)
    end
    local remembered, rememberErr = true, nil
    if mutability == "savedState" and not preserveNilSavedVariables and not noChange then
        remembered, rememberErr = pcall(A.RememberAppliedBundle, {
            action = action.key,
            actionLabel = AssistantPlanLabel(plan, AssistantActionLabel(action, "Assistant task")),
            actionMessage = text,
            undoAvailable = undoAvailable,
            actionArgs = actionArgs,
            serializable = {},
        })
    end
    if not remembered then
        if committedUndoBundle then
            A.undoStack = undoStackBeforePush or {}
            A.redoStack = redoStackBeforePush or {}
            local rollbackErrors = RollbackAction()
            return AP.TransactionFailure(plan, "commit.context", action.key, rememberErr, rollbackErrors)
        end
        A.lastAssistantTransactionError = {
            phase = "commit.context",
            target = tostring(action.key or ""),
            error = tostring(rememberErr),
            committed = true,
        }
    end
    if undoAvailable then text = AP.AppendUndoFollowupHint(text) end
    local resultStatus = mutability == "savedState" and (noChange and "info" or "applied")
        or (mutability == "navigation" and "navigated" or "info")
    return {
        text = text,
        result = resultStatus,
        summary = plan.summary,
        preserveNilSavedVariables = preserveNilSavedVariables == true or nil,
    }
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

function AP._MentionedSettingFromItem(item)
    if type(item) ~= "table" then return nil end
    if type(item.setting) == "table" then return item.setting end
    if type(item.key) == "string" and item.key ~= "" and Registry and type(Registry.GetSetting) == "function" then
        local setting = Registry:GetSetting(item.key)
        if setting then return setting end
    end
    if type(item.settingKey) == "string" and item.settingKey ~= "" and Registry and type(Registry.GetSetting) == "function" then
        local setting = Registry:GetSetting(item.settingKey)
        if setting then return setting end
    end
    if type(item.changes) == "table" then
        for i = 1, #item.changes do
            local setting = AP._MentionedSettingFromItem(item.changes[i])
            if setting then return setting end
        end
    end
    return nil
end

function AP._MentionedContextFromList(items)
    if type(items) ~= "table" then return nil, nil end
    local commonUnit, commonCategory
    local sawUnit, sawCategory = false, false
    for i = 1, #items do
        local item = items[i]
        local setting = AP._MentionedSettingFromItem(item)
        local unit = setting and setting.unit or item and item.unit
        local category = setting and setting.category or item and item.category
        if item and type(item.args) == "table" then
            if unit == nil then unit = item.args.unit or item.args.scope end
            if category == nil then category = item.args.category end
        end
        if unit ~= nil then
            if not sawUnit then
                commonUnit = unit
                sawUnit = true
            elseif commonUnit ~= unit then
                commonUnit = nil
            end
        end
        if category ~= nil then
            if not sawCategory then
                commonCategory = category
                sawCategory = true
            elseif commonCategory ~= category then
                commonCategory = nil
            end
        end
    end
    return commonUnit, commonCategory
end

function AP.RememberMentionedContext(source)
    if type(source) ~= "table" then return end
    local setting = AP._MentionedSettingFromItem(source)
    local unit = setting and setting.unit or source.unit or source.lastUnit or source.mentionedUnit
    local category = setting and setting.category or source.category or source.lastCategory or source.mentionedCategory
    if (unit == nil or category == nil) and type(source.args) == "table" then
        if unit == nil then unit = source.args.unit or source.args.scope end
        if category == nil then category = source.args.category end
    end

    if (unit == nil or category == nil) and type(source.changes) == "table" then
        local listUnit, listCategory = AP._MentionedContextFromList(source.changes)
        if unit == nil then unit = listUnit end
        if category == nil then category = listCategory end
    end
    if (unit == nil or category == nil) and type(source.choices) == "table" then
        local listUnit, listCategory = AP._MentionedContextFromList(source.choices)
        if unit == nil then unit = listUnit end
        if category == nil then category = listCategory end
    end
    if (unit == nil or category == nil) and type(source.searchResults) == "table" then
        local listUnit, listCategory = AP._MentionedContextFromList(source.searchResults)
        if unit == nil then unit = listUnit end
        if category == nil then category = listCategory end
    end

    if unit == nil and category == nil then return end
    local ctx = A.GetContext and A.GetContext()
    if not ctx then return end
    if unit ~= nil then ctx.lastMentionedUnit = unit end
    if category ~= nil then ctx.lastMentionedCategory = category end
    ctx.lastMentionedTurn = tonumber(ctx.turnSerial or ctx.lastTurnSerial) or ctx.lastMentionedTurn
end

local function NormalizePlanResult(result)
    if type(result) ~= "table" then return result end
    if result.status == nil and result.result ~= nil then result.status = result.result end
    if result.result == nil and result.status ~= nil then result.result = result.status end
    AP.RememberMentionedContext(result)
    if type(result.searchResults) == "table" and type(A.SetPendingResults) == "function" then
        local hydrated = A.SetPendingResults(result.searchResults)
        local selectedIndex = tonumber(result.selectPendingResult)
        if selectedIndex and type(hydrated) == "table" and hydrated[selectedIndex] then
            SetSelectedPendingResult(hydrated[selectedIndex], selectedIndex)
        end
    end
    return result
end

function AP.ReadOnlyGuardResult(text)
    -- Refusing to write is right; refusing to answer is not. "Can I change
    -- Boss Buff Player Filter" names the control, so say yes and point at it
    -- instead of describing the guard that stopped the write.
    local label = type(A.RouterNamedSettingLabel) == "function"
        and A.RouterNamedSettingLabel(text) or nil
    if label and label ~= "" then
        local noop = function() return nil end
        local located = type(A.RouterTryRegistrySettingLocationShortcut) == "function"
            and A.RouterTryRegistrySettingLocationShortcut("where is " .. label, noop) or nil
        local body = located and tostring(located.text or "") or nil
        if not body or body == "" then
            local router = A.RouterPrivate
            local direct = router and type(router.NamedSettingDirectAnswer) == "function"
                and router.NamedSettingDirectAnswer(label) or nil
            body = direct and tostring(direct.text or "") or nil
        end
        if body and body ~= "" then
            return {
                text = "Yes - " .. label .. " can be changed. I kept it unchanged because you asked about it rather than for a value.\n"
                    .. body .. "\nTell me the value you want and I will set it.",
                result = "info",
                status = "info",
                summary = "Assistant read-only safety guard",
                _readOnlyGuard = true,
                sourceText = text,
            }
        end
    end
    return {
        text = "I treated that as a read-only question and kept MSUF unchanged. Ask for the option's location, current value, or explanation; to change it, use a direct command with an explicit value.",
        result = "info",
        status = "info",
        summary = "Assistant read-only safety guard",
        _readOnlyGuard = true,
        sourceText = text,
    }
end

function A.CancelPendingMutationState()
    local ctx = A.GetContext and A.GetContext()
    local hadPending = A.pendingConfirmation ~= nil
        or (type(A.pendingChoices) == "table" and #A.pendingChoices > 0)
        or (type(A.pendingFlow) == "table")
        or (type(ctx) == "table" and (ctx.pendingConfirmation ~= nil
            or type(ctx.pendingChoices) == "table"
            or ctx.pendingFlow ~= nil))
    A.pendingConfirmation = nil
    ClearPendingConfirmationContext()
    ClearPendingChoices()
    if A.Workflow and type(A.Workflow.CancelActiveWorkflow) == "function" then
        A.Workflow.CancelActiveWorkflow()
    end
    if type(A.ClearPendingFlow) == "function" then A.ClearPendingFlow() end
    return hadPending
end

local function UnsafeGeneratedSettingResult(setting)
    local label = tostring(setting and setting.label or setting and setting.key or "MSUF setting")
    local reason = tostring(setting and setting.unsafeMutationReason
        or "Its generated registry metadata does not define a reviewed value domain.")
    local result = {
        text = table.concat({
            "I found " .. label .. ", but I kept MSUF unchanged because this raw fallback is not safe for automatic writes yet.",
            reason,
            "Options:",
            "1. Open its MSUF page and use the native control.",
            "2. Ask for its current value or an explanation.",
            "3. Name a different, fully described MSUF control.",
        }, "\n"),
        result = "info",
        status = "info",
        kind = "unsupported",
        summary = "Assistant protected an unconstrained generated setting",
    }
    local router = A.RouterPrivate
    if router and type(router.RegistrySettingItemForKey) == "function"
        and type(router.RegistryLocationResultFollowups) == "function"
    then
        local item = router.RegistrySettingItemForKey(setting and setting.key)
        if item then result.searchResults = router.RegistryLocationResultFollowups({ { item = item } }, 1) end
    end
    return result
end

function A.ExecutePlan(plan, opts)
    opts = opts or {}
    if type(plan) ~= "table" then return NormalizePlanResult({ text = "Which frame, page, or option do you want me to change?", result = "failed" }) end
    local sourceText = opts.sourceText or plan.sourceText or plan.raw
    local guarded = sourceText
        and type(A.RouterIsFailClosedReadOnlyRequest) == "function"
        and A.RouterIsFailClosedReadOnlyRequest(sourceText)
    local actionMutability = plan.kind == "action" and tostring(plan.action and plan.action.mutability or "") or nil
    local actionKey = plan.kind == "action" and tostring(plan.action and plan.action.key or "") or ""
    local guidedTourAction = actionKey == "guided_setup" or actionKey == "guided_setup_step"
        or actionKey == "restart_upgrade_highlight_tour"
    if guarded and not guidedTourAction
        and (plan.kind == "changes" or (plan.kind == "action" and actionMutability ~= "readOnly" and actionMutability ~= "navigation")) then
        return NormalizePlanResult(AP.ReadOnlyGuardResult(sourceText))
    end
    -- Enabled per-unit filter values require that exact lane's gate. Expand
    -- this dependency into the same transaction. Group filter dropdowns
    -- similarly require their lane to be active.
    if plan.kind == "changes" and type(plan.changes) == "table" then
        local existing, unitScopes, groupLanes = {}, {}, {}
        for i = 1, #plan.changes do
            local change = plan.changes[i]
            local key = tostring(change and change.setting and change.setting.key or "")
            existing[key] = true
            local scope, lane = key:match("^auras3%.([^.]+)%.([^.]+)%.filter%.")
            if scope and scope ~= "shared" then
                local owner = scope .. "." .. tostring(lane)
                local need = unitScopes[owner] or { scope = scope, lane = lane, enable = false }
                need.enable = need.enable or (change.value ~= false and change.value ~= "none")
                unitScopes[owner] = need
            end
            local lanePrefix = key:match("^(gf_[^.]+%.auras%.[^.]+)%.filterToken$")
            if lanePrefix then groupLanes[lanePrefix] = true end
        end
        local dependencies = {}
        local function AddDependency(key, value)
            if existing[key] then return end
            local setting = Registry and type(Registry.GetSetting) == "function" and Registry:GetSetting(key) or nil
            if setting then
                existing[key] = true
                dependencies[#dependencies + 1] = { setting = setting, value = value }
            end
        end
        for _, owner in ipairs({ "player.buff", "player.debuff", "target.buff", "target.debuff", "focus.buff", "focus.debuff", "boss.buff", "boss.debuff" }) do
            local need = unitScopes[owner]
            if need then
                if need.enable then
                    AddDependency("auras3." .. need.scope .. "." .. need.lane .. ".filtersEnabled", true)
                end
            end
        end
        local orderedGroupLanes = {}
        for lanePrefix in pairs(groupLanes) do orderedGroupLanes[#orderedGroupLanes + 1] = lanePrefix end
        table.sort(orderedGroupLanes)
        for i = 1, #orderedGroupLanes do AddDependency(orderedGroupLanes[i] .. ".enabled", true) end
        if #dependencies > 0 then
            for i = 1, #plan.changes do dependencies[#dependencies + 1] = plan.changes[i] end
            plan.changes = dependencies
            plan.bulkSafe = #dependencies > 1 and true or plan.bulkSafe
        end
    end
    if plan.kind == "changes" and type(plan.changes) == "table" then
        for i = 1, #plan.changes do
            local setting = plan.changes[i] and plan.changes[i].setting
            if setting and setting.assistantMutationSafe == false then
                return NormalizePlanResult(UnsafeGeneratedSettingResult(setting))
            end
        end
    end
    AP.RememberMentionedContext(plan)
    if PlanNeedsConfirmation(plan) and opts.confirmed ~= true then
        A.pendingConfirmation = plan
        ClearPendingConfirmationContext()
        return NormalizePlanResult({ text = ConfirmationText(plan), result = "confirmation_needed", summary = plan.summary })
    end
    if InCombat() and AnyCombatUnsafe(plan) and opts.fromQueue ~= true then
        A.QueuePlan(plan)
        return NormalizePlanResult({ text = "I paused this request for combat: " .. AssistantPlanLabel(plan, "Assistant change") .. ". Reopen the MSUF menu after combat to resume it.", result = "queued", summary = plan.summary })
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

function AP.PendingCandidateFollowupResult(text)
    local candidates = AP.CurrentPendingCandidates and AP.CurrentPendingCandidates() or nil
    if type(candidates) ~= "table" or #candidates == 0 then return nil end
    local choice = FindChoice(text, candidates)
    if not choice then return nil end
    ClearPendingChoices()
    return ExecuteChoice(choice)
end

-- A pending confirmation must not swallow a brand-new question. Re-prompting
-- the same one-line reminder for "why is my health bar empty" discarded the
-- question and read as the Assistant ignoring the player. Only a request that
-- parses into its own plan counts as a topic switch, so vague replies still get
-- the reminder -- and abandoning an unanswered confirmation is always the safe
-- direction, because nothing is applied.
function AP.PendingTopicSwitchRequest(text)
    if type(A.Parse) ~= "function" then return false end
    local normalized = NormalizeReply(text)
    if normalized == "" or #normalized < 6 then return false end
    -- Parsing is the expensive part, so only pay for it when the reply already
    -- reads like a fresh command rather than an answer to the question asked.
    if not LooksLikeFreshCommand(text) then return false end
    local ok, parsed = pcall(A.Parse, text)
    if not ok or type(parsed) ~= "table" then return false end
    local kind = tostring(parsed.kind or "")
    return kind == "changes" or kind == "action" or kind == "answer" or kind == "diagnostic"
end

local function HandlePending(text)
    if type(A.HandlePendingFlow) == "function" then
        local flowResult = A.HandlePendingFlow(text)
        if flowResult then return flowResult end
    end
    if A.pendingConfirmation then
        if IsChoiceAbort(text) then
            A.pendingConfirmation = nil
            ClearPendingConfirmationContext()
            local normalized = NormalizeReply(text)
            local status = normalized == "cancel" and "applied"
                or ((normalized == "abbrechen" or normalized == "nein danke") and "failed") or "info"
            return { text = "Cancelled. I kept the options as they were.", result = status }
        end
        if LooksLikeUndoRedoCommand(text) then
            A.pendingConfirmation = nil
            ClearPendingConfirmationContext()
            return nil
        end
        local confirmationFollowup = A._PendingConfirmationFollowupResult(text, A.pendingConfirmation)
        if confirmationFollowup then return confirmationFollowup end
        if IsConfirmationApply(text) then
            local plan = A.pendingConfirmation
            A.pendingConfirmation = nil
            ClearPendingConfirmationContext()
            return A.ExecutePlan(plan, { confirmed = true })
        end
        if AP.PendingTopicSwitchRequest(text) then
            A.pendingConfirmation = nil
            ClearPendingConfirmationContext()
            A._droppedPendingConfirmation = true
            return nil
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
        -- A displayed choice label is an explicit answer even when it starts
        -- with a command verb (for example "Hide no-expiration buffs" or
        -- "Show all auras"). Resolve exact labels before the fresh-command
        -- escape so the Assistant never discards its own guided options.
        local exactDisplayedChoice = FindExactDisplayedChoice(text, choices)
        if exactDisplayedChoice then
            ClearPendingChoices()
            return ExecuteChoice(exactDisplayedChoice)
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
        if type(A.RouterLooksLikeExplicitSettingRelationshipRequest) == "function"
            and A.RouterLooksLikeExplicitSettingRelationshipRequest(text)
        then
            ClearPendingResults()
            return nil
        end
        if IsChoiceAbort(text) then
            ClearPendingResults()
            return { text = "Cancelled. I cleared the last search results.", result = "info" }
        end
        -- Fail closed before any fresh-command parser sees a bare result
        -- pronoun.  A result becomes an actionable referent only after the
        -- user explicitly selects/explains it; a search list alone is not
        -- permission to mutate its first text match.
        if not CurrentSelectedPendingResult() then
            local pronounClarification = PendingResultPronounChangeClarificationText(text, results)
            if pronounClarification then
                A._pendingResultFollowupHandled = true
                return pronounClarification
            end
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
    local router = A.RouterPrivate
    local explicitReadOnlyAction = router and (
        (type(router.IsExplicitReadOnlyDiagnosticCommand) == "function" and router.IsExplicitReadOnlyDiagnosticCommand(text))
        or (type(router.IsExplicitNavigationCommand) == "function" and router.IsExplicitNavigationCommand(text))
        or (type(router.LooksLikeGuidedTourRequest) == "function" and router.LooksLikeGuidedTourRequest(text))
        or (type(router.IsCurrentPageHelpRequest) == "function" and router.IsCurrentPageHelpRequest(text))
        or (type(A.RouterHasPendingAssistantState) == "function" and A.RouterHasPendingAssistantState())
    )
    if not explicitReadOnlyAction
        and type(A.RouterIsFailClosedReadOnlyRequest) == "function"
        and A.RouterIsFailClosedReadOnlyRequest(text)
    then
        return NormalizePlanResult(AP.ReadOnlyGuardResult(text))
    end

    local parsed = A.Parse and A.Parse(text) or nil
    if not parsed then return NormalizePlanResult({ text = "Which frame, page, or option do you want me to change?", result = "failed" }) end
    AP.RememberMentionedContext(parsed)

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
        -- Two rows that are the same boolean setting split only by polarity
        -- ("Aggro Border: off / on") are not a real ambiguity when the
        -- sentence states its own direction ("stop highlighting frames...",
        -- "highlight the frame when something is attacking me"). Ask the
        -- shared polarity vocabulary first; only a sentence with no stated
        -- polarity still gets the question.
        local pairChoices = parsed.choices or {}
        if #pairChoices == 2 then
            -- Booleans arrive as true/false, on/off-style string settings
            -- (aggroOutlineMode) as "on"/"off"; both are the same two-state
            -- question to the player.
            local function ChoicePolarity(value)
                if type(value) == "boolean" then return value end
                local v = tostring(value or ""):lower()
                if v == "on" or v == "true" or v == "enabled" then return true end
                if v == "off" or v == "false" or v == "disabled" then return false end
                return nil
            end
            local first, second = pairChoices[1], pairChoices[2]
            local firstKey = first and first.setting and first.setting.key
            local firstPolarity = first and ChoicePolarity(first.value)
            local secondPolarity = second and ChoicePolarity(second.value)
            if firstKey and second and second.setting and second.setting.key == firstKey
                and firstPolarity ~= nil and secondPolarity ~= nil
                and firstPolarity ~= secondPolarity
            then
                local Parser = A.Parser
                local implied
                if Parser and type(Parser.DetectBoolean) == "function" then
                    -- No and-or shorthand here: a detected OFF is `false`,
                    -- which the idiom would collapse into nil.
                    implied = Parser.DetectBoolean(text)
                end
                if implied ~= nil then
                    return NormalizePlanResult(ExecuteChoice(firstPolarity == implied and first or second))
                end
            end
        end
        A.pendingChoices = parsed.choices or {}
        AP.SetPendingCandidates(A.pendingChoices)
        local ctx = A.GetContext and A.GetContext()
        if ctx then ctx.pendingChoices = SerializeChoices(A.pendingChoices) end
        local choiceText = ChoiceText(A.pendingChoices)
        if type(parsed.choiceIntro) == "string" and Trim(parsed.choiceIntro) ~= "" then
            choiceText = Trim(parsed.choiceIntro) .. "\n" .. choiceText
        end
        return NormalizePlanResult({ text = choiceText, result = "ambiguous", summary = parsed.summary })
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
        if type(parsed.pendingSetting) == "table" and type(A.StartPendingFlow) == "function" then
            A.StartPendingFlow("settingValue", parsed.pendingSetting)
        end
        return NormalizePlanResult({ text = parsed.text or "", result = parsed.status or "info", summary = parsed.summary })
    end
    if (parsed.kind == "changes" or parsed.kind == "action") and parsed.sourceText == nil then parsed.sourceText = NormalizeReply(text) end
    return NormalizePlanResult(A.ExecutePlan(parsed))
end

local function CombatSubmitResult()
    return {
        text = "MSUF menu changes have to wait until combat ends. Ask for the same change after combat ends.",
        status = "combat",
        summary = "Assistant menu changes wait until combat ends.",
    }
end

local function InactiveSubmitResult()
    return {
        text = "The MSUF Assistant is paused because its menu is closed.",
        status = "inactive",
        summary = "Assistant work is paused while the menu is closed.",
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

function AP.AdvanceTurnSerial()
    local ctx = A.GetContext and A.GetContext() or nil
    if not ctx then return nil end
    local serial = (tonumber(ctx.turnSerial or ctx.lastTurnSerial) or 0) + 1
    ctx.turnSerial = serial
    ctx.lastTurnSerial = serial
    return serial
end

function AP.BarOutlineColorSemanticPlan(text)
    local parser = A.Parser
    if type(parser) ~= "table" or type(parser.Normalize) ~= "function"
        or type(A._ParseScopedBarOutlineColorFastShortcut) ~= "function"
    then return nil end
    local normalized = parser.Normalize(text)
    if normalized == "" then return nil end
    return A._ParseScopedBarOutlineColorFastShortcut(normalized, text)
end

function AP.ExecuteBarOutlineColorSemanticPlan(plan)
    if type(plan) ~= "table" then return nil end
    AP.RememberMentionedContext(plan)
    if plan.kind == "ambiguous" then
        A.pendingChoices = plan.choices or {}
        AP.SetPendingCandidates(A.pendingChoices)
        local ctx = A.GetContext and A.GetContext()
        if ctx then ctx.pendingChoices = SerializeChoices(A.pendingChoices) end
        local choiceText = ChoiceText(A.pendingChoices)
        if type(plan.choiceIntro) == "string" and Trim(plan.choiceIntro) ~= "" then
            choiceText = Trim(plan.choiceIntro) .. "\n" .. choiceText
        end
        return NormalizePlanResult({ text = choiceText, result = "ambiguous", summary = plan.summary })
    end
    if plan.kind == "unknown" then
        return NormalizePlanResult({
            text = plan.text or "I kept MSUF unchanged because that bar-outline request needs clarification.",
            result = plan.status or "info",
            kind = "unknown",
            summary = plan.summary,
        })
    end
    return NormalizePlanResult(A.ExecutePlan(plan))
end

function A.HandleInput(text, handleOpts)
    if InCombat() then return NormalizePlanResult(CombatSubmitResult()) end
    if not MenuRuntimeActive() then return NormalizePlanResult(InactiveSubmitResult()) end
    handleOpts = type(handleOpts) == "table" and handleOpts or {}
    if handleOpts.skipTurnSerialAdvance == true then
        A._skipTurnSerialAdvance = nil
    elseif A._skipTurnSerialAdvance == true then
        A._skipTurnSerialAdvance = nil
    else
        AP.AdvanceTurnSerial()
    end
    local hadPendingResults = CurrentPendingResults() ~= nil
    A._pendingResultFollowupHandled = nil
    A._droppedPendingConfirmation = nil
    A._assistantValueClamps = nil
    local result
    local routed, routeResult
    local semanticBarOutlineColor = AP.BarOutlineColorSemanticPlan(text)
    local function RunRoute()
        if semanticBarOutlineColor then
            return AP.ExecuteBarOutlineColorSemanticPlan(semanticBarOutlineColor)
        end
        if type(A.RouteInput) == "function" then return A.RouteInput(text, A.HandleCommandInput) end
        return A.HandleCommandInput(text)
    end
    -- Lua 5.1 cannot yield through xpcall. Deferred requests run inside the
    -- Assistant's resumable coroutine and may cooperatively yield while a
    -- cold registry/search index is built, so let the coroutine/job boundary
    -- own error recovery there. Synchronous callers retain the local guard.
    if A._jobYieldStartedMs ~= nil then
        routed, routeResult = true, RunRoute()
    else
        routed, routeResult = xpcall(RunRoute, AP.AssistantJobErrorHandler)
    end
    if routed then
        result = NormalizePlanResult(routeResult)
    else
        result = NormalizePlanResult(AP.AssistantFailureResult(routeResult, {
            label = "assistant.route",
            text = text,
        }))
    end
    local pendingResultReply = A._pendingResultFollowupHandled == true
    A._pendingResultFollowupHandled = nil
    if ShouldClearPendingResultsAfterHandledInput(result, hadPendingResults, pendingResultReply) then ClearPendingResults() end
    -- Say when MSUF's own range overrode the number that was asked for.
    if type(result) == "table" and type(A._assistantValueClamps) == "table" and #A._assistantValueClamps > 0 then
        local status = tostring(result.status or result.result or "")
        if status == "applied" or status == "changed" or status == "unchanged" then
            result.text = AP.AppendValueClampNotes(result.text)
        end
    end
    A._assistantValueClamps = nil
    -- Never drop a confirmation silently: the player asked for it and is
    -- entitled to know it was not applied.
    if A._droppedPendingConfirmation and type(result) == "table" then
        result.text = tostring(result.text or "")
            .. "\nI dropped the confirmation that was waiting, because you moved on to something else. Nothing was applied."
    end
    A._droppedPendingConfirmation = nil
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

function AP.IsAssistantStopCommand(text)
    local normalized = NormalizeReply(text)
    return normalized == "stop"
        or normalized == "cancel"
        or normalized == "abort"
        or normalized == "stop assistant"
        or normalized == "cancel assistant"
        or normalized == "abort assistant"
        or normalized == "stop that"
        or normalized == "stop it"
        or normalized == "cancel that"
        or normalized == "cancel request"
        or normalized == "cancel current request"
        or normalized == "cancel previous request"
        or normalized == "abbrechen"
        or normalized == "stopp"
        or normalized == "stoppen"
end

function A.StopAssistantWork(reason)
    reason = tostring(reason or "cancelled")
    A._assistantStopSerial = (tonumber(A._assistantStopSerial) or 0) + 1
    if type(A._assistantCurrentJob) == "table" then
        A._assistantCurrentJob.cancelled = true
        A._assistantCurrentJob.cancelReason = reason
    end
    local removed = A.CancelJobs and A.CancelJobs(nil, reason) or 0
    A._assistantJobPumpScheduled = nil
    A._assistantJobsCombatDeferred = nil
    A._assistantJobsCombatReason = nil
    A.SetBusy(false)
    return removed
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

function AP.BatchSettingLead(text)    local norm = AP.NormalizeForBatch(text)
    for _, lead in ipairs({ "set", "change", "adjust", "setze", "stelle", "aendere" }) do
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

AP.BATCH_READ_ONLY_LEADS = {
    "what ", "why ", "how ", "where ", "which ", "when ",
    "is ", "are ", "can ", "could ", "would ", "should ",
    "do ", "does ", "did ", "tell ", "explain ", "describe ",
    "show me ", "open ", "find ", "search ", "help ",
    "diagnose ", "check ", "preview ",
}

function AP.BatchReadOnlyGuardCandidate(norm)
    for i = 1, #AP.BATCH_READ_ONLY_LEADS do
        if norm:sub(1, #AP.BATCH_READ_ONLY_LEADS[i]) == AP.BATCH_READ_ONLY_LEADS[i] then
            return true
        end
    end
    return norm:find("without changing", 1, true) ~= nil
        or norm:find("without applying", 1, true) ~= nil
        or norm:find("without setting", 1, true) ~= nil
        or norm:find("do not change", 1, true) ~= nil
        or norm:find("dont change", 1, true) ~= nil
        or norm:find("no changes", 1, true) ~= nil
        or norm:find("read only", 1, true) ~= nil
        or norm:find("read-only", 1, true) ~= nil
end

function AP.IsReadOnlyBatchTail(text)
    local norm = AP.NormalizeForBatch(AP.StripBatchLead(text))
    if norm == "" then return false end
    local router = A.RouterPrivate
    if router and (
        (type(router.IsExplicitReadOnlyDiagnosticCommand) == "function"
            and router.IsExplicitReadOnlyDiagnosticCommand(norm))
        or (type(router.IsExplicitNavigationCommand) == "function"
            and router.IsExplicitNavigationCommand(norm))
    ) then
        return true
    end
    -- The full fail-closed classifier may build fuzzy/alias indexes. Running it
    -- for an ordinary inherited mutation tail ("target portrait position ...")
    -- blocked SubmitDeferred for tens of milliseconds before the yielding job
    -- even existed. Only question, navigation, preview, or explicit no-write
    -- shapes can be read-only here; mutation-shaped tails proceed to the cheap
    -- inheritance checks below.
    return AP.BatchReadOnlyGuardCandidate(norm)
        and type(A.RouterIsFailClosedReadOnlyRequest) == "function"
        and A.RouterIsFailClosedReadOnlyRequest(norm)
        or false
end

function AP.InheritedBatchCommand(before, after)    local actionTail = AP.InheritableActionTail(after)
    if AP.IsReadOnlyBatchTail(after) then return nil end
    local settingTail = AP.InheritableSettingTail(after)
    if not actionTail and not settingTail then return nil end
    local lead = AP.BatchBooleanLead(before)
    if not lead and settingTail then lead = AP.BatchSettingLead(before) end
    if not lead then return nil end
    if settingTail and AP.HasOwnBatchBoolean(after) then return nil end
    if settingTail and not AP.HasScopedSettingDetail(before) then return nil end
    return Trim(lead .. " " .. after)
end

-- "set target width to 250 and set height to 60" repeats the verb but not the
-- frame. Batch parts are planned independently, so the second clause arrived
-- without a frame and fell back to a default unit -- writing Player Height for
-- a sentence that only ever named the target. Carry the first clause's frame
-- over when the follow-up clause names none of its own.
function AP.InheritBatchScope(before, after)
    local parser = A.Parser
    if type(parser) ~= "table" then return after end
    local detectUnits = parser.DetectUnits
    local detectGroups = parser.DetectGroups
    if type(detectUnits) ~= "function" or type(detectGroups) ~= "function" then return after end
    if #detectUnits(after) > 0 or #detectGroups(after) > 0 then return after end

    local units, groups = detectUnits(before), detectGroups(before)
    local scope
    if #units == 1 and #groups == 0 then
        scope = units[1]
    elseif #groups == 1 and #units == 0 then
        scope = groups[1]
    end
    if not scope then return after end

    local trimmed = Trim(after)
    local starter = trimmed:match("^(%a+)")
    if not starter then return after end
    local starterNorm = starter:lower()
    for i = 1, #AP.BATCH_COMMAND_STARTERS do
        if starterNorm == AP.BATCH_COMMAND_STARTERS[i] then
            return starter .. " " .. scope .. " " .. Trim(trimmed:sub(#starter + 1))
        end
    end
    return after
end

function AP.IsNamedConjunctionBoundary(before, after)
    before = AP.NormalizeForBatch(before)
    after = AP.NormalizeForBatch(after)
    if before == "" or after == "" then return false end
    local names = {
        { left = "group health", right = "text" },
        { left = "group status", right = "indicators" },
        { left = "display", right = "recovery" },
    }
    for i = 1, #names do
        local item = names[i]
        local left = item.left
        local right = item.right
        local leftMatches = before == left
            or before:sub(-#left - 1) == " " .. left
        local rightMatches = after == right
            or after:sub(1, #right + 1) == right .. " "
        if leftMatches and rightMatches then return true end
    end
    return false
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
                    -- Keep a conversational pronoun attached to the feature
                    -- named by the first clause.  Without this, the fast
                    -- registry matcher sees "player frame" and can turn the
                    -- second clause into Player Frame Enabled instead of the
                    -- Combat Timer anchor requested by the user.
                    local beforeNorm = AP.NormalizeForBatch(before)
                    local afterNorm = AP.NormalizeForBatch(after)
                    if AP.IsNamedConjunctionBoundary(beforeNorm, afterNorm) then
                        startAt = e + 1
                    else
                    local combatTimerAnchor = afterNorm:match("^anchor%s+it%s+to%s+(.+)$")
                    if combatTimerAnchor and AP.BatchHasPhrase(beforeNorm, "combat timer") then
                        after = "set combat timer anchor to " .. combatTimerAnchor
                    end
                    if before ~= "" and after ~= ""
                        and (AP.StartsBatchCommand(after) or AP.IsReadOnlyBatchTail(after))
                    then
                        parts[p] = before
                        table.insert(parts, p + 1, AP.InheritBatchScope(before, after))
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

function AP.IsSuccessfulResultStatus(status)
    return status == "applied" or status == "changed" or status == "info" or status == "answered"
        or status == "unchanged" or status == "navigated"
end

function AP.IsMutationResultStatus(status)
    return status == "applied" or status == "changed"
end

AP.NORMAL_INPUT_MAX_CHARS = 20000

function AP.ExtractProfileString(text)    text = tostring(text or "")
    return text:match("(MSUF%d+:%S+)")
end

function AP.LongInputResult(text)    text = tostring(text or "")
    if #text <= AP.NORMAL_INPUT_MAX_CHARS then return nil end
    local value = AP.ExtractProfileString(text)
    if value and Registry and type(Registry.GetAction) == "function" then
        local action = Registry:GetAction("import_profile_string")
        if action then
            return A.ExecutePlan({
                kind = "action",
                action = action,
                args = { value = value },
                confirmRequired = true,
                label = "Import profile string",
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

function AP.BuildAtomicSettingBatch(parts)
    if type(parts) ~= "table" or #parts < 2 or type(A.Parse) ~= "function" then return nil end
    local combined = {}
    local labels = {}
    local confirmRequired = false
    local bulkSafe = true
    for i = 1, #parts do
        local parsed = A.Parse(parts[i])
        if type(parsed) ~= "table" or parsed.kind ~= "changes" or type(parsed.changes) ~= "table" or #parsed.changes == 0 then
            return nil
        end
        confirmRequired = confirmRequired or parsed.confirmRequired == true or AnySettingFlag(parsed, "confirmRequired")
        bulkSafe = bulkSafe and parsed.bulkSafe == true
        labels[#labels + 1] = AssistantPlanLabel(parsed, "request " .. tostring(i))
        for j = 1, #parsed.changes do combined[#combined + 1] = parsed.changes[j] end
    end
    return {
        kind = "changes",
        changes = combined,
        confirmRequired = confirmRequired,
        bulkSafe = bulkSafe,
        label = table.concat(labels, "; "),
        summary = "Applies " .. tostring(#parts) .. " setting requests as one atomic Assistant transaction.",
        sourceText = table.concat(parts, " and "),
        _atomicBatchCount = #parts,
    }
end

function AP.TrySubmitMixedBatch(parts, opts)
    if type(parts) ~= "table" or #parts < 2 then return nil end
    local mutationParts, readOnlyParts = {}, {}
    for i = 1, #parts do
        if AP.IsReadOnlyBatchTail(parts[i]) then
            readOnlyParts[#readOnlyParts + 1] = { index = i, text = parts[i] }
        else
            mutationParts[#mutationParts + 1] = parts[i]
        end
    end
    if #mutationParts == 0 or #readOnlyParts == 0 then return nil end

    local atomicPlan
    if #mutationParts == 1 and type(A.Parse) == "function" then
        local parsed = A.Parse(mutationParts[1])
        if type(parsed) == "table" and parsed.kind == "changes"
            and type(parsed.changes) == "table" and #parsed.changes > 0
        then
            atomicPlan = parsed
        end
    else
        atomicPlan = AP.BuildAtomicSettingBatch(mutationParts)
    end
    if not atomicPlan then return AP.BatchPlanFailure(parts) end

    local informational = {}
    for i = 1, #readOnlyParts do
        local part = readOnlyParts[i]
        local result = A.HandleInput(part.text, {
            skipTurnSerialAdvance = opts and opts.turnSerialAdvanced == true,
        })
        local status = result and (result.status or result.result)
        if not result or AP.IsMutationResultStatus(status)
            or not AP.IsSuccessfulResultStatus(status)
        then
            return AP.BatchPlanFailure(parts)
        end
        informational[#informational + 1] = {
            index = part.index,
            text = tostring(result.text or ""),
        }
    end

    local changed = A.ExecutePlan(atomicPlan)
    local changedStatus = changed and (changed.status or changed.result)
    if not changed or not AP.IsSuccessfulResultStatus(changedStatus) then return changed end

    local lines = {
        "Done. I handled " .. tostring(#parts) .. " parts safely.",
        tostring(changed.text or ""),
    }
    for i = 1, #informational do
        lines[#lines + 1] = informational[i].text
    end
    changed.text = table.concat(lines, "\n")
    changed.summary = "Handled a mixed atomic setting change and read-only Assistant request."
    return changed
end

function AP.BatchPlanFailure(parts)
    return {
        text = "I could not safely plan every part of that combined request, so I kept MSUF unchanged. Rephrase the unclear part or send the requests separately.",
        status = "ambiguous",
        summary = "Combined request needs clarification before anything changes.",
        batchParts = type(parts) == "table" and #parts or 0,
    }
end

function AP.TrySubmitBatch(text, preSplitParts, opts)    local parts = preSplitParts or AP.SplitBatchCommands(text)
    if not parts then return nil end
    local mixed = AP.TrySubmitMixedBatch(parts, opts)
    if mixed then return mixed end
    local atomicPlan = AP.BuildAtomicSettingBatch(parts)
    if atomicPlan then
        local result = A.ExecutePlan(atomicPlan)
        if type(result) == "table" and AP.IsSuccessfulResultStatus(result.status or result.result) then
            local detail = tostring(result.text or ""):gsub("^Done%.%s*", "", 1)
            result.text = "Done. I handled " .. tostring(#parts) .. " requests together:\n" .. detail
            result.summary = atomicPlan.summary
        end
        return result
    end
    return AP.BatchPlanFailure(parts)
end

function AP.RecordAssistantResult(result)    if result and result.text then
        -- Recording this response would recreate the SavedVariables that a
        -- confirmed factory reset intentionally left nil until reload.
        if result.preserveNilSavedVariables == true then return end
        if type(result.searchResults) == "table" and type(A.SetPendingResults) == "function" then
            local hydrated = A.SetPendingResults(result.searchResults)
            local selectedIndex = tonumber(result.selectPendingResult)
            if selectedIndex and type(hydrated) == "table" and hydrated[selectedIndex] then
                SetSelectedPendingResult(hydrated[selectedIndex], selectedIndex)
            end
        end
        A.AddHistory("assistant", result.text, result.status or result.result, result.summary)
        if AP.IsMutationResultStatus(result.status or result.result) and type(A.RecordSuccessfulAssistantAction) == "function" and type(A.MaybePowerUserSupportHint) == "function" then
            A.RecordSuccessfulAssistantAction()
            local hint = A.MaybePowerUserSupportHint()
            if hint then A.AddHistory("assistant", hint, "info", "Assistant power-user dashboard links hint") end
        end
    end
end

function AP.TryImmediateSubmitResult(text, opts)
    if type(A.TryImmediateConversationReply) ~= "function" then return nil end
    if AP.SplitBatchCommands(text) then return nil end
    local parser = A.Parser or {}
    local normalized = type(parser.Normalize) == "function" and parser.Normalize(text) or tostring(text or ""):lower()
    if AP.BarOutlineColorSemanticPlan(text) then return nil end
    -- Pure small talk is exempt: it can only produce text, so the fail-closed
    -- read-only gate has nothing to protect against, and applying it here sent
    -- "tell me a joke" to the settings advisory instead of the joke lane.
    local smallTalk = type(A.RouterIsPureSmallTalk) == "function"
        and A.RouterIsPureSmallTalk(text) == true
    if not smallTalk and type(A.RouterIsFailClosedReadOnlyRequest) == "function"
        and A.RouterIsFailClosedReadOnlyRequest(text)
    then
        return nil
    end
    if AP.RequiresExactMovementRouting and AP.RequiresExactMovementRouting(text) then return nil end
    if AP.RequiresCrossFrameTextRouting and AP.RequiresCrossFrameTextRouting(text) then return nil end
    -- "Is there Player Bar Outline Color in MSUF?" is a question about whether
    -- the control exists. The conversational lane answers a different question
    -- (it explains frame layers), so let the router's existence lane own it.
    if type(A.RouterIsFeatureExistenceQuestion) == "function"
        and A.RouterIsFeatureExistenceQuestion(text) == true
    then
        return nil
    end
    local context = type(A.GetContext) == "function" and A.GetContext() or {}
    -- A retained object owns pronoun follow-ups before the generic
    -- conversational lane. Otherwise "move it down" can be reinterpreted as
    -- moving the whole last unit frame before the follow-up parser sees the
    -- portrait/icon/text object stored in lastChangeBundle.
    if AP.LastChangeBundleIsImmediate(context)
        and AP.LooksLikeImmediateLastChangeFollowup
        and AP.LooksLikeImmediateLastChangeFollowup(normalized)
    then
        return nil
    end
    local nameDotsPlan = type(parser.ParseNameShorteningDotsShortcut) == "function"
        and parser.ParseNameShorteningDotsShortcut(normalized, context, text) or nil
    if type(nameDotsPlan) == "table" and nameDotsPlan.kind == "ambiguous" then
        -- Negated dots/ellipsis wording deliberately produces a clarification.
        -- Do not let the conversational fast path replace that fail-closed
        -- result before the mutation planner can preserve the ambiguity.
        return nil
    end
    local auraFilteringIntent = type(parser.LooksLikeAuraFilteringConversation) == "function"
        and parser.LooksLikeAuraFilteringConversation(
            normalized,
            context
        )
    local adjacentJokeFollowup = type(A.RouterIsAdjacentJokeFollowup) == "function"
        and A.RouterIsAdjacentJokeFollowup(normalized) == true
    -- Search results own pronoun/ordinal follow-ups ("set it to 18", "the
    -- second one", ...).  Let the pending-state router resolve or clarify
    -- them before the generic conversational shortcut can reinterpret the
    -- sentence as a fresh exact-alias mutation.
    local pendingResults = CurrentPendingResults()
    if not adjacentJokeFollowup and type(pendingResults) == "table" and #pendingResults > 0 then return nil end
    -- Exact aura-list requests require lane/scope-aware action parsers and
    -- native blacklist/whitelist transaction semantics.  The conversational
    -- shortcut must not collapse "hide Rejuvenation in target buffs" into
    -- hiding the entire Target Buff lane.
    local auraListValue = type(parser.AuraBlacklistSpellValue) == "function"
        and parser.AuraBlacklistSpellValue(text) or nil
    local noDurationAuraQuestion = normalized:find("permanent", 1, true)
        or normalized:find("no timer", 1, true) or normalized:find("without timer", 1, true)
        or normalized:find("no duration", 1, true) or normalized:find("without duration", 1, true)
        or normalized:find("timeless", 1, true)
    if auraFilteringIntent then return nil end
    if not noDurationAuraQuestion and (normalized:find("blacklist", 1, true) or normalized:find("whitelist", 1, true)
        or (auraListValue and (normalized:find("aura", 1, true)
            or normalized:find("buff", 1, true) or normalized:find("debuff", 1, true))))
    then
        return nil
    end
    local result = A.TryImmediateConversationReply(text)
    if not result then return nil end
    if not (opts and opts.skipUserHistory == true) then
        A.AddHistory("user", text, "submitted")
    end
    result = NormalizePlanResult(result)
    AP.RecordAssistantResult(result)
    if type(A.RequestRefreshUI) == "function" then
        A.RequestRefreshUI("assistant.submit.immediate")
    elseif type(A.RefreshUI) == "function" then
        A.RefreshUI()
    end
    return result
end

function AP.LastChangeBundleAvailable(ctx)
    return type(ctx) == "table" and type(ctx.lastChangeBundle) == "table" and #ctx.lastChangeBundle > 0
end

function AP.LastChangeBundleIsImmediate(ctx)
    if not AP.LastChangeBundleAvailable(ctx) then return false end
    local currentTurn = tonumber(ctx.turnSerial or ctx.lastTurnSerial) or 0
    local subjectTurn = tonumber(ctx.lastSubjectTurn)
    -- Bare retained-object wording is safe only on the very next turn. Once
    -- the conversation has moved through help, navigation, or examples, it
    -- must name an MSUF area instead of reviving an older mutation target.
    return subjectTurn ~= nil and currentTurn - subjectTurn == 1
end

function AP.NormalizedHasPhrase(text, phrase)
    text = tostring(text or "")
    phrase = tostring(phrase or "")
    if text == "" or phrase == "" then return false end
    return (" " .. text .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
end

function AP.NormalizedHasAnyPhrase(text, phrases)
    for i = 1, #(phrases or {}) do
        if AP.NormalizedHasPhrase(text, phrases[i]) then return true end
    end
    return false
end

function AP.LooksLikeImmediateLastChangeFollowup(normalized)
    normalized = Trim(tostring(normalized or ""))
    if normalized == "" then return false end
    if normalized:match("^(what|why|where|how|explain|describe|show|open)%s") then return false end
    if AP.NormalizedHasAnyPhrase(normalized, {
        "tell me more", "more details", "more options", "more settings", "more like this",
        "show more", "open more", "result", "results", "option", "options",
    }) then
        return false
    end
    if normalized == "more"
        or normalized == "less"
        or normalized == "again"
        or normalized == "same again"
        or normalized == "do it again"
        or normalized == "once more"
        or normalized == "one more"
        or normalized == "continue"
        or normalized == "keep going"
        or normalized == "mehr"
        or normalized == "weniger"
        or normalized == "weiter"
        or normalized == "nochmal"
        or normalized == "noch mal"
    then
        return true
    end
    local hasRetainedReference = AP.NormalizedHasAnyPhrase(normalized, {
        "it", "its", "that", "this", "them", "those", "these", "their",
        "the frame", "the bar", "the text", "the icon", "the icons",
    })
    if hasRetainedReference and AP.NormalizedHasAnyPhrase(normalized, {
        "make", "change", "set", "move", "nudge", "shift", "resize",
        "bigger", "larger", "smaller", "shrink", "wider", "narrower", "taller", "shorter",
        "left", "right", "up", "down", "size", "width", "height", "anchor", "layer",
        "color", "colour", "red", "green", "blue", "yellow", "orange", "purple", "white", "black", "gray", "grey",
        "shape", "circle", "circular", "round", "rounded", "square", "diamond", "style", "render",
        "2d", "3d", "zoom", "spacing", "gap", "thickness", "border", "align", "alignment",
        "opacity", "alpha", "transparent", "opaque",
        "show", "hide", "enable", "disable", "turn on", "turn off",
    }) then
        return true
    end
    return AP.NormalizedHasAnyPhrase(normalized, {
        "a bit more", "a little more", "still more", "more still",
        "not enough", "needs more", "need more", "not far enough",
        "too much", "too far", "not that much", "went too far",
        "go back a bit", "back a bit", "a bit back",
        "opposite", "opposite way", "other way", "reverse it",
        "nicht genug", "mehr noch", "zu viel", "zu weit", "etwas zurueck",
        "andersrum", "umgekehrt",
    })
end

function AP.RequiresExactTextMovementRouting(text)
    local router = A.RouterPrivate
    return router and type(router.TextMovementIntent) == "function"
        and router.TextMovementIntent(text) ~= nil
end

function AP.RequiresCrossFrameTextRouting(text)
    local router = A.RouterPrivate
    if not (router and type(router.CrossFrameTextRequestParts) == "function") then return false end
    local subjectUnit, _, frameUnit = router.CrossFrameTextRequestParts(text)
    return subjectUnit ~= nil and frameUnit ~= nil and subjectUnit ~= frameUnit
end

function AP.RequiresDirectionalTextMovementRouting(text)
    local router = A.RouterPrivate
    local intent = router and type(router.TextMovementIntent) == "function"
        and router.TextMovementIntent(text) or nil
    return type(intent) == "table"
        and (intent.direction ~= nil or intent.conflictingDirections == true or intent.fixedAnchorRequested == true)
end

function AP.RequiresExactCastbarMovementRouting(text)
    local router = A.RouterPrivate
    if not router then return false end
    if type(router.CastbarComponentMovementIntent) == "function"
        and router.CastbarComponentMovementIntent(text) ~= nil
    then
        return true
    end
    return type(router.CastbarMovementIntent) == "function"
        and router.CastbarMovementIntent(text) ~= nil
end

function AP.RequiresExactCastbarPositionRouting(text)
    local router = A.RouterPrivate
    return router and type(router.CastbarIconFixedPositionIntent) == "function"
        and router.CastbarIconFixedPositionIntent(text) ~= nil
end

function AP.RequiresOwnedComponentMovementRouting(text)
    local parser = A.Parser or {}
    if type(parser.Normalize) ~= "function" or type(parser.ParseUnitDetailMove) ~= "function" then return false end
    local normalized = parser.Normalize(text)
    -- Numeric component movement must reach the geometry owner before an enum
    -- shortcut can consume only "left/right" and silently discard the amount.
    if not normalized:match("[%+%-]?%d") then return false end
    local plan = parser.ParseUnitDetailMove(normalized)
    return type(plan) == "table" and plan.kind == "changes" and type(plan.changes) == "table" and #plan.changes > 0
end

function AP.RequiresExactMovementRouting(text)
    return AP.RequiresExactCastbarMovementRouting(text)
        or AP.RequiresExactCastbarPositionRouting(text)
        or AP.RequiresExactTextMovementRouting(text)
        or AP.RequiresOwnedComponentMovementRouting(text)
end

function AP.TryImmediateMutationResult(text, opts)
    if InCombat() or A.pendingConfirmation or CurrentPendingChoices() then return nil end
    local pendingResults = CurrentPendingResults()
    if type(pendingResults) == "table" and #pendingResults > 0 then return nil end
    local parser = A.Parser or {}
    local normalize = parser.Normalize
    if type(normalize) ~= "function" then return nil end
    local normalized = normalize(text)
    if normalized == "" then return nil end
    if AP.BarOutlineColorSemanticPlan(text) then return nil end
    local routePrivate = A.RouterPrivate
    -- A build request is not a mutation. "I want to track a spell on my player
    -- frame" contains "player frame", which this fast path matched to Player
    -- Frame Enabled and answered "already enabled". Let the Router explain how
    -- to build the thing instead.
    if routePrivate and type(routePrivate.TryCreationGuidance) == "function"
        and routePrivate.TryCreationGuidance(text)
    then
        return nil
    end
    -- Context-aware Aura filtering intentionally bypasses some broad
    -- read-only heuristics for concrete filter commands. Subjective planning
    -- phrases are the exception: a retained group-Aura scope must never turn
    -- "show important debuffs" into an Important-token write (or the
    -- transaction guard's generic reply) before RouteInput can explain the
    -- missing preference. Hand these exact phrases to the Router first.
    if routePrivate and type(routePrivate.IsSubjectiveSafePlanningRequest) == "function"
        and routePrivate.IsSubjectiveSafePlanningRequest(text)
    then
        return nil
    end
    if routePrivate and type(routePrivate.IsExplicitNavigationCommand) == "function"
        and routePrivate.IsExplicitNavigationCommand(text)
    then
        -- Navigation owns value-bearing Aura phrases too. The Aura immediate
        -- mutation lane deliberately bypasses several generic read-only
        -- guards, so without this explicit handoff "take me to Raid Debuff
        -- Filter: dispellable" is answered generically before the Router can
        -- open the resolved control.
        return nil
    end
    -- "Target of Target name ... on Target frame" names two different
    -- owners. Let the Router explain the relationship (or offer the correct
    -- frame) before an exact boolean alias can toggle only the first phrase.
    if AP.RequiresCrossFrameTextRouting(text) then return nil end
    -- Concrete directional movement and typed cast-bar icon placement have
    -- reviewed O(1) owners. Bypass exact label detection before it can lazily
    -- build the broad registry indices; value-only commands such as "set
    -- target power text Y offset to 5" do not satisfy these guards and retain
    -- exact-label precedence.
    if AP.RequiresExactCastbarMovementRouting(text)
        or AP.RequiresExactCastbarPositionRouting(text)
        or AP.RequiresDirectionalTextMovementRouting(text)
        or AP.RequiresOwnedComponentMovementRouting(text)
    then
        return nil
    end
    -- A complete visible setting label must reach the Router's deterministic
    -- exact-control lane before any low-latency topical shortcut can consume a
    -- broader word such as layer, smooth, buff, color, scale, or dots.
    if routePrivate and type(routePrivate.IsExactRegistrySettingMutation) == "function"
        and routePrivate.IsExactRegistrySettingMutation(text)
    then
        return nil
    end
    if AP.RequiresExactTextMovementRouting(text) then return nil end
    if routePrivate and type(routePrivate.IncompleteMovementSubject) == "function"
        and routePrivate.IncompleteMovementSubject(text)
    then
        return nil
    end
    local ctx = A.GetContext and A.GetContext() or {}
    local auraFilteringIntent = type(parser.LooksLikeAuraFilteringConversation) == "function"
        and parser.LooksLikeAuraFilteringConversation(normalized, ctx)
    -- Exact value-less font text-color requests have a reviewed enum-choice
    -- parser. Preserve that O(1) clarification before the generic open-ended
    -- guard either guesses a mode or sends the request through fuzzy guidance.
    local priorityClarification
    if parser.ParseBareFontTextColorModeChoice then
        priorityClarification = parser.ParseBareFontTextColorModeChoice(normalized)
    elseif parser.ParseBareHPTextColorModeChoice then
        priorityClarification = parser.ParseBareHPTextColorModeChoice(normalized)
    end
    -- Multiple explicit clauses must stay together.  Let the deferred batch
    -- path parse and apply them atomically instead of allowing a warm exact-
    -- alias index to consume only the final frame name.
    if normalized:find(" but ", 1, true) then return nil end
    if AP.SplitBatchCommands(text) then return nil end
    -- Never let continuation/exact-alias fast paths reinterpret a problem,
    -- capability question, location lookup, or subjective request as a write.
    -- The full Router will provide the diagnostic/help response.
    if (not auraFilteringIntent and not priorityClarification
            and type(A.RouterIsFailClosedReadOnlyRequest) == "function"
            and A.RouterIsFailClosedReadOnlyRequest(text))
        or (not auraFilteringIntent and type(parser.NonMutatingIntent) == "function" and parser.NonMutatingIntent(normalized))
        or (not auraFilteringIntent and type(A.RouterIsBroadPageNavigationRequest) == "function" and A.RouterIsBroadPageNavigationRequest(text))
    then
        return nil
    end
    -- Native aura list commands need the action parser because lane, unit,
    -- custom-container index, confirmation, and snapshot semantics matter.
    -- The generic exact-setting fast path would otherwise turn e.g. "hide
    -- spell:774 in raid buffs" into disabling the entire Raid Buffs lane.
    local auraListValue = type(parser.AuraBlacklistSpellValue) == "function"
        and parser.AuraBlacklistSpellValue(text) or nil
    if not auraFilteringIntent and (normalized:find("blacklist", 1, true) or normalized:find("whitelist", 1, true)
        or (auraListValue and (normalized:find("aura", 1, true)
            or normalized:find("buff", 1, true) or normalized:find("debuff", 1, true))))
    then
        return nil
    end
    local router = A.RouterPrivate
    if not auraFilteringIntent and ((router and type(router.AuraSpecificSpellRequest) == "function" and router.AuraSpecificSpellRequest(normalized))
        or (router and type(router.AuraSpecificIconFilterRequest) == "function" and router.AuraSpecificIconFilterRequest(normalized))
    ) then
        return nil
    end
    if not auraFilteringIntent
        and (normalized:find("buff", 1, true) or normalized:find("debuff", 1, true) or normalized:find("aura", 1, true))
        and (normalized:find("only my", 1, true) or normalized:find("only mine", 1, true)
            or normalized:find("show only", 1, true))
    then
        -- "Only mine" can replace several live filter tokens. Let the full
        -- aura parser ask whether to replace or combine instead of letting an
        -- exact-alias fast path apply one incomplete write.
        return nil
    end
    -- Aura cooldown/stack text sizing is narrower than the lane's Show Text
    -- toggle. Let the lane-aware Router build the exact size command instead
    -- of allowing a warm alias index to stop at the boolean parent setting.
    local auraTextKind = normalized:find("cooldown text", 1, true)
        or normalized:find("timer text", 1, true)
        or normalized:find("stack text", 1, true)
    local auraTextFamily = normalized:find("buff", 1, true)
        or normalized:find("debuff", 1, true)
        or normalized:find("aura", 1, true)
        or (auraTextKind
            and not normalized:find("castbar", 1, true)
            and (normalized:find("player", 1, true)
                or normalized:find("target", 1, true)
                or normalized:find("focus", 1, true)
                or normalized:find("boss", 1, true)
                or normalized:find("party", 1, true)
                or normalized:find("raid", 1, true)
                or normalized:find("group", 1, true)))
    local auraTextSize = normalized:find("size", 1, true)
        or normalized:find("bigger", 1, true)
        or normalized:find("larger", 1, true)
        or normalized:find("smaller", 1, true)
        or normalized:find("increase", 1, true)
        or normalized:find("decrease", 1, true)
        or normalized:find("reduce", 1, true)
        or normalized:find("grow", 1, true)
        or normalized:find("shrink", 1, true)
    if auraTextFamily and auraTextKind and auraTextSize then return nil end
    -- Cross-frame wording is intentionally handled by the Router before the
    -- parser. Running the exact-alias fast path here can otherwise apply the
    -- subject setting while silently ignoring the different destination frame
    -- (for example, "show target buffs on player frame").
    if (type(A.RouterTryCrossFrameTextRequestShortcut) == "function" and A.RouterTryCrossFrameTextRequestShortcut(text))
        or (type(A.RouterTryCrossFrameVisualRequestShortcut) == "function" and A.RouterTryCrossFrameVisualRequestShortcut(text))
    then
        return nil
    end
    if not priorityClarification and type(A.RouterShouldPreferPageContext) == "function"
        and A.RouterShouldPreferPageContext(text)
    then
        return nil
    end

    local plan = priorityClarification
    if not plan and auraFilteringIntent and parser.ParseAuraFilteringConversationShortcut then
        plan = parser.ParseAuraFilteringConversationShortcut(normalized, ctx, text)
    end
    if not plan and AP.LastChangeBundleIsImmediate(ctx)
        and AP.LooksLikeImmediateLastChangeFollowup(normalized)
        and type(parser.BuildFollowup) == "function"
    then
        plan = parser.BuildFollowup(normalized, ctx)
    end
    -- Dots/ellipsis wording has a narrow semantic owner and can stay on the
    -- constant-time path. The full name-shortening specialist must not run
    -- here: generated exact-label commands such as "set target shorten name
    -- max chars to 20" belong to their leaf registry settings.
    if not plan and parser.ParseNameShorteningDotsShortcut then
        plan = parser.ParseNameShorteningDotsShortcut(normalized, ctx, text)
    end
    -- Keep the reported value-less first prompt off the yielding exact-alias
    -- build without broadening precedence over concrete registry commands.
    local bareTargetNameShortening = normalized == "shorten target name"
        or normalized == "shorten the target name"
    if not plan and bareTargetNameShortening and parser.ParseNameShorteningShortcut then
        plan = parser.ParseNameShorteningShortcut(normalized, ctx, text)
    end
    -- Preview is an action, not the similarly named Boss Frame Enabled
    -- setting.  This priority is needed once the exact-alias cache is warm.
    if parser.ParseBossFramePreviewShortcut and normalized:find("boss", 1, true)
        and normalized:find("preview", 1, true)
    then
        plan = parser.ParseBossFramePreviewShortcut(normalized)
    end
    if not plan and Registry and type(Registry.GetSetting) == "function" then
        local lastSetting = ctx and ctx.lastSetting and Registry:GetSetting(ctx.lastSetting) or nil
        plan = AP.PortraitRenderFollowupPlan(text, lastSetting)
    end
    -- Broad "target text bigger" wording names the frame and the kind of
    -- adjustment, but not which text line.  Ask Name/HP/Power explicitly;
    -- the warm exact-alias index otherwise returns unrelated text offsets.
    if not plan and A._ParseTextFontSizeShortcut
        and (normalized:find("text", 1, true) or normalized:find("font", 1, true))
        and (normalized:find("bigger", 1, true) or normalized:find("larger", 1, true)
            or normalized:find("smaller", 1, true) or normalized:find("font size", 1, true)
            or normalized:find("text size", 1, true))
    then
        plan = A._ParseTextFontSizeShortcut(normalized)
    end
    -- Named status indicators own their X/Y offsets. Resolve them before the
    -- generic frame-movement fallback can interpret "ready check up" as the
    -- Party/Raid frame's own Y position.
    if not plan and A._ParseHumanIndicatorMoveFastShortcut
        and (normalized:find("ready check", 1, true)
            or normalized:find("raid marker", 1, true)
            or normalized:find("role icon", 1, true)
            or normalized:find("leader icon", 1, true)
            or normalized:find("assist icon", 1, true)
            or normalized:find("summon", 1, true)
            or normalized:find("resurrect", 1, true)
            or normalized:find("resurrection", 1, true)
            or normalized:find("phase icon", 1, true))
    then
        plan = A._ParseHumanIndicatorMoveFastShortcut(normalized)
    end
    if parser.BuildContinuationFollowup then
        plan = plan or parser.BuildContinuationFollowup(normalized, ctx)
    end
    if not plan and AP.LastChangeBundleIsImmediate(ctx)
        and AP.LooksLikeImmediateLastChangeFollowup(normalized)
        and type(A.ParseSimpleChange) == "function"
    then
        local followupPlan = A.ParseSimpleChange(text, ctx)
        if followupPlan and followupPlan.kind == "changes" and followupPlan.confirmRequired ~= true then
            plan = followupPlan
        end
    end
    if not plan and A._ParseLastBarGradientGroupFollowup and (normalized:find("group", 1, true) or normalized:find("party", 1, true) or normalized:find("raid", 1, true)) then
        plan = A._ParseLastBarGradientGroupFollowup(normalized, ctx)
    end
    if not plan and A._ParseDashboardScaleFastShortcut and normalized:find("scale", 1, true) then
        plan = A._ParseDashboardScaleFastShortcut(normalized)
    end
    if not plan and parser.ParseGlobalFontFamilyShortcut and normalized:find("font", 1, true) then
        plan = parser.ParseGlobalFontFamilyShortcut(normalized, text)
    end
    if not plan and A._ParseCastbarColorFastShortcut and (normalized:find("cast", 1, true) or normalized:find("interrupt", 1, true) or normalized:find("kick", 1, true)) then
        plan = A._ParseCastbarColorFastShortcut(normalized, text)
    end
    if not plan and A._ParseCastbarOverrideModeFastShortcut and normalized:find("cast", 1, true) then
        plan = A._ParseCastbarOverrideModeFastShortcut(normalized)
    end
    if not plan and A._ParseGlobalHighlightColorFastShortcut
        and (normalized:find("highlight", 1, true) or normalized:find("combat timer", 1, true)) then
        plan = A._ParseGlobalHighlightColorFastShortcut(normalized, text)
    end
    local exactColorCandidate = normalized:find("color", 1, true)
        or normalized:find("colour", 1, true)
        or normalized:find("farbe", 1, true)
    if not exactColorCandidate and parser and type(parser.ExtractColor) == "function" then
        exactColorCandidate = parser.ExtractColor(text, normalized) ~= nil
    end
    local registry = A.Registry
    local settings = registry and type(registry.AllSettings) == "function" and registry:AllSettings() or nil
    local exactColorIndexReady = type(settings) == "table"
        and parser._exactColorSettingIndexSettings == settings
        and parser._exactColorSettingIndexCount == #settings
        and type(parser._exactColorSettingIndex) == "table"
    local exactAliasIndexReady = type(settings) == "table"
        and parser._registryExactAliasSettings == settings
        and parser._registryExactAliasCount == #settings
        and type(parser._registryExactAliasIndex) == "table"
    -- A bare HP-text color request is a small, deterministic clarification:
    -- single font color or health gradient. Keep it out of the full registry
    -- alias/index path so the first LoD request cannot pay the multi-thousand
    -- setting scan (or trip WoW's script watchdog) just to show two choices.
    if not plan and exactColorCandidate and parser.ParseHPTextColorModePriority
        and normalized:find("hp", 1, true)
        and normalized:find("text", 1, true)
        and normalized:find("color", 1, true)
    then
        plan = parser.ParseHPTextColorModePriority(normalized)
    end
    if not plan and A._ParseSpecResourceColorShortcut and exactColorCandidate then
        plan = A._ParseSpecResourceColorShortcut(normalized, text)
    end
    if not plan and A._ParseClassPowerColorPriorityShortcut and exactColorCandidate then
        plan = A._ParseClassPowerColorPriorityShortcut(normalized, text)
    end
    if not plan and A._ParseClassColorFastShortcut and exactColorCandidate then
        plan = A._ParseClassColorFastShortcut(normalized, text)
    end
    if not plan and A._ParsePowerColorTokenFastShortcut and exactColorCandidate then
        plan = A._ParsePowerColorTokenFastShortcut(normalized, text)
    end
    if not plan and exactColorIndexReady and A._ParseExactColorSettingFastShortcut and exactColorCandidate then
        plan = A._ParseExactColorSettingFastShortcut(normalized, text)
    end
    if not plan and A._ParseMouseoverHighlightFastShortcut and normalized:find("highlight", 1, true) then
        plan = A._ParseMouseoverHighlightFastShortcut(normalized, text)
    end
    if not plan and A._ParseBarGradientPriorityShortcut and normalized:find("gradient", 1, true) then
        plan = A._ParseBarGradientPriorityShortcut(normalized)
    end
    -- Name-shortening has both reviewed scoped controls and raw AutoCoverage
    -- compatibility fields with overlapping aliases.  The warm non-full
    -- matcher can otherwise select the raw General field from a precise
    -- Target command (depending on which earlier prompt warmed the index).
    -- Let A.Parse's full-phrase matcher resolve these exact labels
    -- deterministically; the bare natural request above remains O(1).
    local nameShorteningExactCandidate = normalized:find("shorten name", 1, true)
        or normalized:find("shorten names", 1, true)
    if not plan and nameShorteningExactCandidate
        and exactAliasIndexReady and parser.ParseRegistryExactAliasShortcut then
        local exactPlan = parser.ParseRegistryExactAliasShortcut(normalized, text, {
            minTokens = 3,
            fullPhrase = true,
        })
        if not exactPlan and A._ParseFontScopePriorityShortcut then
            exactPlan = A._ParseFontScopePriorityShortcut(normalized)
        end
        if exactPlan and exactPlan.kind == "changes" and exactPlan.confirmRequired ~= true then
            plan = exactPlan
        end
    end
    if not plan and not nameShorteningExactCandidate
        and exactAliasIndexReady and parser.ParseRegistryExactAliasShortcut then
        local firstWord = normalized:match("^(%S+)")
        local deterministicRegistryMutation =
            firstWord == "set" or firstWord == "change" or firstWord == "make"
            or firstWord == "turn" or firstWord == "enable" or firstWord == "disable"
            or firstWord == "show" or firstWord == "hide"
            or firstWord == "move" or firstWord == "nudge" or firstWord == "shift"
            or firstWord == "increase" or firstWord == "decrease" or firstWord == "raise" or firstWord == "lower"
            or firstWord == "setze" or firstWord == "stelle" or firstWord == "verschiebe" or firstWord == "verschieben"
            or firstWord == "aktivieren" or firstWord == "deaktivieren"
            or firstWord == "anzeigen" or firstWord == "verstecken" or firstWord == "einblenden" or firstWord == "ausblenden"
        if deterministicRegistryMutation then
            local exactPlan = parser.ParseRegistryExactAliasShortcut(normalized, text)
            if exactPlan and exactPlan.kind == "changes" and exactPlan.confirmRequired ~= true then
                plan = exactPlan
            end
        end
    end
    if not plan and type(A.ParseSimpleChange) == "function" then
        local firstWord = normalized:match("^(%S+)")
        local simpleMovementMutation =
            firstWord == "move" or firstWord == "nudge" or firstWord == "shift"
            or firstWord == "increase" or firstWord == "decrease" or firstWord == "raise" or firstWord == "lower"
            or firstWord == "verschiebe" or firstWord == "verschieben"
            or normalized:find(" offset", 1, true) or normalized:find("layer", 1, true)
            or normalized:find("left", 1, true) or normalized:find("right", 1, true)
            or normalized:find("up", 1, true) or normalized:find("down", 1, true)
            or normalized:find("links", 1, true) or normalized:find("rechts", 1, true)
            or normalized:find("hoch", 1, true) or normalized:find("runter", 1, true)
        if simpleMovementMutation then
            local simplePlan = A.ParseSimpleChange(text, ctx)
            if simplePlan and simplePlan.kind == "changes" and simplePlan.confirmRequired ~= true then
                plan = simplePlan
            end
        end
    end
    if not plan or plan.confirmRequired == true or plan.kind == "action" then return nil end

    if not (opts and opts.skipUserHistory == true) then
        A.AddHistory("user", text, "submitted")
    end
    plan.raw = plan.raw or text
    plan.normalized = plan.normalized or normalized
    if plan.kind == "changes" and plan.sourceText == nil then plan.sourceText = normalized end
    local result
    if plan.kind == "ambiguous" then
        A.pendingChoices = plan.choices or {}
        AP.SetPendingCandidates(A.pendingChoices)
        local activeContext = A.GetContext and A.GetContext()
        if activeContext then activeContext.pendingChoices = SerializeChoices(A.pendingChoices) end
        local choiceText = ChoiceText(A.pendingChoices)
        if type(plan.choiceIntro) == "string" and Trim(plan.choiceIntro) ~= "" then
            choiceText = Trim(plan.choiceIntro) .. "\n" .. choiceText
        end
        result = NormalizePlanResult({ text = choiceText, result = "ambiguous", summary = plan.summary })
    elseif plan.kind == "answer" then
        if type(plan.pendingSetting) == "table" and type(A.StartPendingFlow) == "function" then
            A.StartPendingFlow("settingValue", plan.pendingSetting)
        end
        result = NormalizePlanResult({ text = plan.text or "", result = plan.status or "info", summary = plan.summary })
    elseif plan.kind == "unknown" or plan.kind == "unsupported" then
        result = NormalizePlanResult({
            text = plan.text or "Which page and option do you want me to use? Example: 'set target cast bar height to 20'.",
            result = plan.status or "failed",
            kind = plan.kind,
            summary = plan.summary,
        })
    else
        result = NormalizePlanResult(A.ExecutePlan(plan))
    end
    AP.RecordAssistantResult(result)
    if type(A.RequestRefreshUI) == "function" then
        A.RequestRefreshUI("assistant.submit.immediate_mutation")
    elseif type(A.RefreshUI) == "function" then
        A.RefreshUI()
    end
    return result
end

function AP.SubmitNow(text, opts)    opts = opts or {}
    text = Trim(text)
    if text == "" then return nil end
    if InCombat() then return NormalizePlanResult(CombatSubmitResult()) end
    if not MenuRuntimeActive() then return NormalizePlanResult(InactiveSubmitResult()) end
    AP.AdvanceTurnSerial()
    -- Range corrections are reported from here rather than from HandleInput,
    -- because the low-latency mutation lanes below return without ever
    -- reaching it -- which is why "set player health text size to 200" applied
    -- 48 with no explanation while "set player width to 4000" explained itself.
    A._assistantValueClamps = nil
    local immediate = AP.TryImmediateSubmitResult(text, opts)
    if immediate then return immediate end
    -- A complete multi-command sentence must be split before the low-latency
    -- single-plan path sees it. Otherwise that path can confidently apply the
    -- first clause and silently discard the remaining commands (for example,
    -- "turn off target name and turn off focus name").
    local failClosedReadOnly = type(A.RouterIsFailClosedReadOnlyRequest) == "function" and A.RouterIsFailClosedReadOnlyRequest(text)
    local exactMovement = AP.RequiresExactMovementRouting(text)
    local batchParts = not failClosedReadOnly and not exactMovement and AP.SplitBatchCommands(text) or nil
    -- "Is there Boss Texture Layer 3 Offset X in MSUF?" asks whether a control
    -- exists. The immediate mutation lane would treat the "3" inside the label
    -- as the value to apply and move the frame, so existence questions have to
    -- reach the router instead of being answered by a write.
    local existenceQuestion = type(A.RouterIsFeatureExistenceQuestion) == "function"
        and A.RouterIsFeatureExistenceQuestion(text) == true
    -- Same reason: "the bar color for NPCs should be class color" reached this
    -- lane and wrote Party Bar Color Mode, dropping the NPC qualifier.
    local npcBarColor = type(A.RouterIsNpcQualifiedBarColorRequest) == "function"
        and A.RouterIsNpcQualifiedBarColorRequest(text) == true
    -- A question that names a control ("show me Mythic Raid Masque Enabled")
    -- is a lookup, not the instruction its label happens to spell out.
    local namedLookup = type(A.RouterIsNamedSettingLookup) == "function"
        and A.RouterIsNamedSettingLookup(text) == true
    if not batchParts and not existenceQuestion and not npcBarColor and not namedLookup then
        local immediateMutation = AP.TryImmediateMutationResult(text, opts)
        if immediateMutation then return immediateMutation end
    end
    if opts.skipUserHistory ~= true then
        A.AddHistory("user", text, "submitted")
    end
    local result = NormalizePlanResult(AP.LongInputResult(text)
        or AP.TrySubmitBatch(text, batchParts, { turnSerialAdvanced = true })
        or A.HandleInput(text, { skipTurnSerialAdvance = true }))
    AP.RecordAssistantResult(result)
    if type(A.RequestRefreshUI) == "function" then
        A.RequestRefreshUI("assistant.submit")
    elseif type(A.RefreshUI) == "function" then
        A.RefreshUI()
    end
    return result
end

function A.Submit(text)
    local ok, result = xpcall(function()
        local produced = AP.SubmitNow(text)
        -- Last word before the reply leaves: dozens of specialised lanes can
        -- claim a sentence and then hand back a list, an article or an
        -- apology. When the sentence's own subject resolves to exactly ONE
        -- control, that is not a guess -- it is the control the player named,
        -- so act on it rather than answering with a question.
        local status = type(produced) == "table" and tostring(produced.status or produced.result or "") or ""
        -- "navigated" is also a non-answer to a change request: opening the
        -- page is what the Assistant does when it recognised the area but not
        -- the control ("let the target frame have its own bar settings").
        local unresolved = status == "ambiguous" or status == "failed" or status == "info"
            or status == "needs_choice" or status == "unknown" or status == "navigated"
        -- Only for openers that can ONLY mean navigation. "direct me to target
        -- portrait position left" names the value to identify the control, and
        -- this hook applied it. Deliberately not every navigation-shaped
        -- sentence: "show me how much maximum health i lost" asks for a feature
        -- to be switched on, and blocking that stopped it working. The other
        -- half of the problem -- an enum value the sentence never contains at
        -- all -- is fixed at its source in Router.EnumValueAppearsInText.
        if type(A.RouterPrivate) == "table"
            and type(A.RouterPrivate.IsUnambiguousNavigationCommand) == "function"
            and A.RouterPrivate.IsUnambiguousNavigationCommand(text)
        then
            unresolved = false
        end
        -- Same rule for a question: "should i turn off Boss Buff Show Cooldown
        -- Swipe?" names one control and one polarity, which is exactly what
        -- this hook looks for -- so it answered the question by doing the
        -- thing. Asking is never permission.
        if type(A.RouterPrivate) == "table"
            and type(A.RouterPrivate.IsAdviceQuestion) == "function"
            and A.RouterPrivate.IsAdviceQuestion(text)
        then
            unresolved = false
        end
        -- A reply that offered real choices is a deliberate clarification and
        -- the player's answer is expected next; overriding it would discard
        -- the retained control (assistant_router_safety_regression pins this).
        -- "turn on the dispel border for party frames" names a frame, and a
        -- reply that changed nothing means the SHARED control answered while
        -- the player asked about that frame's own copy.
        -- "already set" is also what a near-miss looks like: the shared control
        -- answering a frame-scoped question, or the aggro TOGGLE answering
        -- "only show the aggro border when i am not the tank", which is about
        -- the role filter. Nothing was written, so re-resolving costs nothing:
        -- a plan that lands on the same control simply reports unchanged again
        -- and the original reply stands.
        if status == "unchanged" then unresolved = true end
        -- A choice list is a deliberate clarification, so it normally stands.
        -- The exception is a sentence that spells one control's registered
        -- wording in full: offering that control among three guesses is not a
        -- clarification, it is a miss, and the wording decides it.
        local spelledOut = type(A.RouterPrivate) == "table"
            and type(A.RouterPrivate.NamedBooleanIntentPlan) == "function"
            and A.RouterPrivate.NamedBooleanIntentPlan(text) or nil
        -- A size stated as a dimension idiom ("make the shield bar 6 pixels
        -- tall") hides the attribute noun the registry indexes, so the lanes
        -- above see a bare number on a subject and list every control whose
        -- name contains that subject -- seven per-unit frame Heights, none of
        -- them the shield bar. That list is a miss for the same reason spelled
        -- out wording is: the rewrite resolves to exactly ONE control (checked
        -- inside CanonicalDimensionCommand), so it decides the sentence.
        local sized = type(A.RouterPrivate) == "table"
            and type(A.RouterPrivate.CanonicalDimensionCommand) == "function"
            and A.RouterPrivate.CanonicalDimensionCommand(text) or nil
        if not sized and not (spelledOut and (tonumber(spelledOut.namedWordingTokens) or 0) >= 4) then
            if type(A.pendingChoices) == "table" and #A.pendingChoices > 0 then unresolved = false end
            if type(A.pendingCandidates) == "table" and #A.pendingCandidates > 0 then unresolved = false end
        end
        if unresolved and type(A.RouterPrivate) == "table" and type(A.ExecutePlan) == "function" then
            local router = A.RouterPrivate
            -- The dimension rewrite is consulted last so nothing the existing
            -- two plans already claim moves.
            local plan = (type(router.StatedValueKindSiblingPlan) == "function"
                    and router.StatedValueKindSiblingPlan(text))
                or (type(router.NamedBooleanIntentPlan) == "function"
                    and router.NamedBooleanIntentPlan(text))
                or (sized and type(router.ExactAliasSingleChange) == "function"
                    and router.ExactAliasSingleChange(sized))
                or nil
            if plan then
                -- The normal path already declined this sentence, and the
                -- fail-closed read-only gate would decline it again for the
                -- same reason -- leaving a request that names one control
                -- answered with "ask for its location". The plan resolved from
                -- the control's own registered wording, so run it without
                -- re-submitting the sentence to that gate.
                plan.sourceText, plan.raw = nil, nil
                local okPlan, planned = pcall(A.ExecutePlan, plan, {})
                local plannedStatus = okPlan and type(planned) == "table"
                    and tostring(planned.status or planned.result or "") or ""
                if plannedStatus == "applied" or plannedStatus == "changed" then return planned end
            end
        end
        return produced
    end, AP.AssistantJobErrorHandler)
    if ok then
        -- Every submit path funnels through here, so this is the one place that
        -- can guarantee a clamped value is explained regardless of which lane
        -- applied it.
        if type(result) == "table" and type(A._assistantValueClamps) == "table"
            and #A._assistantValueClamps > 0
        then
            local status = tostring(result.status or result.result or "")
            if status == "applied" or status == "changed" or status == "unchanged" then
                result.text = AP.AppendValueClampNotes(result.text)
            end
        end
        A._assistantValueClamps = nil
        return result
    end
    A._assistantValueClamps = nil
    return A.RecoverAssistantFailure(result, { label = "assistant.submit", text = text })
end

function AP.BuildDeferredSubmitSteps(text, callback, opts)    opts = opts or {}
    local steps = {}
    local parts
    if opts.batchChecked == true then
        parts = opts.preSplitParts
    else
        local failClosedReadOnly = type(A.RouterIsFailClosedReadOnlyRequest) == "function" and A.RouterIsFailClosedReadOnlyRequest(text)
        local exactMovement = AP.RequiresExactMovementRouting(text)
        parts = not failClosedReadOnly and not exactMovement and AP.SplitBatchCommands(text) or nil
    end
    local finalResult
    local finished = false

    local function Complete(result)
        if finished then return end
        finalResult = NormalizePlanResult(result)
        A.SetBusy(false)
        if finalResult.suppressAssistantRecord ~= true then AP.RecordAssistantResult(finalResult) end
        finished = true
        if type(callback) == "function" then callback(finalResult) end
    end

    if opts.userHistoryRecorded ~= true then
        steps[#steps + 1] = function()
            A.AddHistory("user", text, "submitted")
        end
    end

    if parts then
        -- Planning can build cold registry indices. Keep it inside the
        -- yielding job coroutine so accepting a compound prompt never blocks
        -- the Dashboard frame while each clause is resolved.
        steps[#steps + 1] = A.CoroutineStep(function()
            finalResult = AP.TrySubmitBatch(text, parts, { turnSerialAdvanced = true })
                or AP.BatchPlanFailure(parts)
        end)
        steps[#steps + 1] = function()
            Complete(finalResult or AP.BatchPlanFailure(parts))
            return finalResult
        end
    else
        steps[#steps + 1] = A.CoroutineStep(function()
            finalResult = AP.LongInputResult(text) or A.HandleInput(text, {
                skipTurnSerialAdvance = opts.turnSerialAdvanced == true,
            })
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

function AP.RunSubmitCallback(callback, result, label, text)
    if type(callback) ~= "function" then return true end
    local ok, callbackError = xpcall(function() callback(result) end, AP.AssistantJobErrorHandler)
    if not ok then AP.AssistantFailureResult(callbackError, { label = label or "assistant.callback", text = text }) end
    return ok
end

function AP.SubmitDeferredNow(text, callback)
    text = Trim(text)
    if text == "" then return nil end
    if InCombat() then return NormalizePlanResult(CombatSubmitResult()) end
    if not MenuRuntimeActive() then return NormalizePlanResult(InactiveSubmitResult()) end
    if A.IsBusy() then
        if AP.IsAssistantStopCommand and AP.IsAssistantStopCommand(text) then
            AP.AdvanceTurnSerial()
            local removed = A.StopAssistantWork("user")
            local result = NormalizePlanResult({
                text = removed > 0 and "Stopped. I cancelled the assistant work that was still running." or "Stopped. I cleared the assistant busy state.",
                result = "info",
                summary = "Cancelled running Assistant work.",
            })
            A.AddHistory("user", text, "submitted")
            AP.RecordAssistantResult(result)
            AP.RunSubmitCallback(callback, result, "assistant.stop.callback", text)
            if type(A.RequestRefreshUI) == "function" then
                A.RequestRefreshUI("assistant.stop")
            elseif type(A.RefreshUI) == "function" then
                A.RefreshUI()
            end
            return result
        end
        return NormalizePlanResult({ text = "I am still working on the previous request. Press Stop or type stop to cancel it.", result = "busy" })
    end
    -- A rejected message is not added to history or executed, so it must not
    -- age conversational referents either. Advance only once the turn has
    -- actually been accepted (including an accepted Stop command above).
    AP.AdvanceTurnSerial()
    if AP.IsAssistantStopCommand and AP.IsAssistantStopCommand(text) then
        return NormalizePlanResult({ text = "Nothing is running right now.", result = "info" })
    end
    -- Detect compound commands before either immediate lane. Those lanes are
    -- single-intent optimizations and can otherwise spend cold-start time
    -- proving that a multi-clause request does not belong there before the
    -- scheduler receives it. The deferred batch owner parses every clause and
    -- commits exactly one atomic transaction (or no writes at all).
    local batchParts = AP.SplitBatchCommands(text)
    if batchParts and AP.RequiresExactMovementRouting(text) then batchParts = nil end
    -- Same standdown as AP.SubmitNow. This is the path the live menu uses, so
    -- without it the immediate mutation lane still answered questions with a
    -- write in game even though the synchronous path was fixed.
    local deferredExistenceQuestion = type(A.RouterIsFeatureExistenceQuestion) == "function"
        and A.RouterIsFeatureExistenceQuestion(text) == true
    local deferredNpcBarColor = type(A.RouterIsNpcQualifiedBarColorRequest) == "function"
        and A.RouterIsNpcQualifiedBarColorRequest(text) == true
    local deferredNamedLookup = type(A.RouterIsNamedSettingLookup) == "function"
        and A.RouterIsNamedSettingLookup(text) == true
    if not batchParts then
        local immediate = AP.TryImmediateSubmitResult(text)
        if immediate then
            AP.RunSubmitCallback(callback, immediate, "assistant.immediate.callback", text)
            return immediate
        end
        if not deferredExistenceQuestion and not deferredNpcBarColor and not deferredNamedLookup then
            local immediateMutation = AP.TryImmediateMutationResult(text)
            if immediateMutation then
                AP.RunSubmitCallback(callback, immediateMutation, "assistant.immediate-mutation.callback", text)
                return immediateMutation
            end
        end
    end

    A.SetBusy(true, "I am working on that. Press Stop or type stop to cancel.")

    A.AddHistory("user", text, "submitted")
    local steps, onDone = AP.BuildDeferredSubmitSteps(text, callback, {
        userHistoryRecorded = true,
        turnSerialAdvanced = true,
        batchChecked = true,
        preSplitParts = batchParts,
    })
    local job = A.StartJob("assistant.submit", steps, onDone, { requestText = text })
    if job and type(job.result) == "table" and not A.IsBusy() then
        return NormalizePlanResult(job.result)
    end
    return NormalizePlanResult({ text = A.GetBusyText(), result = "queued" })
end

function A.SubmitDeferred(text, callback)
    local ok, result = xpcall(function() return AP.SubmitDeferredNow(text, callback) end, AP.AssistantJobErrorHandler)
    if ok then return result end
    return A.RecoverAssistantFailure(result, {
        label = "assistant.submit.deferred",
        text = text,
        callback = callback,
    })
end

function A.StartNewTask()
    if InCombat() or not MenuRuntimeActive() or A.IsBusy() then return false end
    if A.Workflow and type(A.Workflow.CancelActiveWorkflow) == "function" then
        A.Workflow.CancelActiveWorkflow()
    end
    if type(A.ClearPendingFlow) == "function" then A.ClearPendingFlow() end
    ClearPendingChoices()
    ClearPendingResults()
    ClearPendingConfirmationContext()
    if type(A.CloseLargeTextPanel) == "function" then
        A.CloseLargeTextPanel()
    else
        A.largeTextPanel = nil
    end
    local context = A.GetContext and A.GetContext() or nil
    if type(context) == "table" then
        for key in pairs(context) do context[key] = nil end
    end
    if type(A.ClearRouterTransientCaches) == "function" then A.ClearRouterTransientCaches() end
    if A.Parser and type(A.Parser.ClearRegistryCandidateFuzzyCache) == "function" then A.Parser.ClearRegistryCandidateFuzzyCache() end
    if A.Parser and type(A.Parser.ClearActionAliasFuzzyCache) == "function" then A.Parser.ClearActionAliasFuzzyCache() end
    if type(A.ClearHistory) == "function" then A.ClearHistory() end
    local ui = A.dashboardUI
    if ui and ui.input then
        if type(ui.input.SetText) == "function" then ui.input:SetText("") end
        if type(ui.input.SetFocus) == "function" then ui.input:SetFocus() end
        local placeholder = ui.input._msufAssistantPlaceholder
        if placeholder and type(placeholder.SetShown) == "function" then placeholder:SetShown(true) end
    end
    A.RequestRefreshUI("assistant.new_task")
    return true
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
