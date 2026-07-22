-- F2: the no-match fallback must reason from the control catalog instead of
-- dead-ending.  R.RouterCatalogSuggestionNoMatch searches the catalog for the
-- nearest registered settings and offers the top matches as read-only "did you
-- mean" suggestions -- but only when the top hit clears the same confidence
-- floor the explain/decision shortcuts use to name a setting, and never as a
-- mutation.  Below the floor the input is noise and it returns nil so the
-- caller falls through to the honest dead-end reply.
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
A.RouterPrivate = A.RouterPrivate or {}
A.RouterPrivate.Normalize = function(text) return tostring(text or ""):lower() end

local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRouter.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)

local R = A.RouterPrivate
Check(type(R.RouterCatalogSuggestionNoMatch) == "function",
    "RouterCatalogSuggestionNoMatch must be defined on the router")

-- Deterministic catalog search + follow-up rendering stubs so the confidence
-- gate and read-only contract are exercised against the real fallback code.
local nextEntries = nil
R.RegistrySettingSearchEntries = function(text, norm, limit)
    Check(type(text) == "string" and text ~= "", "search must receive the raw text")
    Check(type(norm) == "string", "search must receive normalized text")
    return nextEntries
end
local followupCalls = 0
R.RegistryLocationResultFollowups = function(entries, limit)
    followupCalls = followupCalls + 1
    local out = {}
    for i = 1, math.min(limit or 0, #(entries or {})) do
        out[i] = { kind = "setting", label = entries[i].item.label, canExplain = true, canOpen = true }
    end
    return out
end

local function Entry(label, score, raw)
    return { item = { kind = "setting", label = label, settingKey = "k." .. label }, score = score, rawScore = raw }
end

local function AssertReadOnly(result)
    Check(type(result) == "table", "expected a result table")
    Check(result.status == "ambiguous" and result.result == "ambiguous",
        "a suggestion must be read-only/ambiguous, never a mutation status")
    -- A suggestion must never carry an apply/mutation payload.
    Check(result.setting == nil and result.value == nil and result.action == nil
        and result.changes == nil and result.plan == nil and result.confirm == nil,
        "a suggestion must never carry a mutation payload")
    Check(type(result.searchResults) == "table" and #result.searchResults > 0,
        "a suggestion must offer selectable read-only follow-ups")
end

-- 1. Confident near-match: offer up to three read-only suggestions.
nextEntries = {
    Entry("Player Health Bar Color", 520, 480),
    Entry("Player Health Text Color", 410, 360),
    Entry("Target Health Bar Color", 360, 300),
    Entry("Focus Health Bar Color", 300, 260),
}
local suggestion = R.RouterCatalogSuggestionNoMatch("make my healthbar greenish")
AssertReadOnly(suggestion)
Check(suggestion.text:find("closest", 1, true), "suggestion should frame the options as closest matches")
Check(suggestion.text:find("Player Health Bar Color", 1, true), "suggestion must list the top catalog match")
Check(suggestion.text:find("did not change", 1, true), "suggestion must reassure that nothing changed")
Check(#suggestion.searchResults == 3, "suggestion must cap at the top three options")

-- 2. Below the score floor: noise, return nil so the caller dead-ends honestly.
nextEntries = { Entry("Some Loosely Related Option", 300, 220), Entry("Another", 250, 180) }
Check(R.RouterCatalogSuggestionNoMatch("qwerty zxcv asdf") == nil,
    "a below-floor top hit must not produce a suggestion")

-- 3. High display score but low raw score (weak literal match): still nil.
nextEntries = { Entry("Padded Score Option", 900, 200) }
Check(R.RouterCatalogSuggestionNoMatch("vague thing") == nil,
    "a high display score with a weak raw score must not suggest")

-- 4. Empty / missing catalog result: nil, no crash.
nextEntries = {}
Check(R.RouterCatalogSuggestionNoMatch("anything") == nil, "no catalog entries must return nil")
nextEntries = nil
Check(R.RouterCatalogSuggestionNoMatch("anything") == nil, "a nil catalog result must return nil")

-- 5. Empty input: nil.
Check(R.RouterCatalogSuggestionNoMatch("") == nil, "empty input must return nil")

-- 6. The full RouterFriendlyNoMatch ladder reaches the suggestion before the
-- Discord dead-end when context and knowledge decline.
R.TryUncertainContextChoices = function() return nil end
A.Knowledge = nil -- KnowledgeNoMatch -> nil
nextEntries = { Entry("Player Health Bar Color", 520, 480) }
local laddered = A.RouterFriendlyNoMatch("make my healthbar greenish")
Check(type(laddered) == "table" and laddered.status == "ambiguous",
    "RouterFriendlyNoMatch must surface the catalog suggestion before the dead-end")
Check(not tostring(laddered.text or ""):find("Discord", 1, true),
    "a confident suggestion must not fall through to the Discord dead-end")

-- 7. When the catalog also declines, the honest dead-end still fires.
nextEntries = nil
local deadEnd = A.RouterFriendlyNoMatch("qwerty zxcv asdf")
Check(type(deadEnd) == "table" and tostring(deadEnd.text or ""):find("Discord", 1, true),
    "with no catalog match the fallback must still reach the honest dead-end")

print("assistant_catalog_suggestion_nomatch_smoke: PASS")
