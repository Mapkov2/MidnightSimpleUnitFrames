-- F3: read-only reach-back to an earlier conversation subject.
--
-- RememberAppliedBundle keeps a bounded ring of recently discussed distinct
-- subjects, and R.RouterReachBackSubjectChoice resolves a back-reference ("the
-- other one", "the first one", "go back to the player one") against that ring.
-- The ring must dedup/bound/order correctly, and the resolver must only ever
-- restate a subject as a read-only choice -- never mutate, never guess when the
-- reference is ambiguous or the candidate has aged out.
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
_G.time = function() return 1000 end

-- Minimal in-memory DB so the history module's EnsureDB works.
local DB = { assistant = { history = {}, context = {}, historyLimit = 100 } }
M.EnsureDB = function() return DB end

-- Registry with a few labelled settings for the resolver to render.
local SETTINGS = {
    ["player.width"] = { key = "player.width", label = "Player Width", unit = "player", type = "number" },
    ["target.height"] = { key = "target.height", label = "Target Height", unit = "target", type = "number" },
    ["focus.scale"] = { key = "focus.scale", label = "Focus Scale", unit = "focus", type = "number" },
}
local Registry = {}
function Registry:GetSetting(key) return SETTINGS[key] end
function Registry:AllSettings() local o = {} for _, s in pairs(SETTINGS) do o[#o + 1] = s end return o end
A.Registry = Registry
A.RouterPrivate = A.RouterPrivate or {}
A.RouterPrivate.Normalize = function(text) return tostring(text or ""):lower() end

assert(loadfile(root .. "/MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantHistory.lua"))("MidnightSimpleUnitFrames", MSUF)
assert(loadfile(root .. "/MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRouter.lua"))("MidnightSimpleUnitFrames", MSUF)

local R = A.RouterPrivate
Check(type(R.RouterReachBackSubjectChoice) == "function", "resolver must be defined")

-- The real resolver renders a chosen key through RegistrySettingItemForKey,
-- which needs page/label helpers; stub the two it calls so the test targets the
-- ring + resolver logic, not the full page catalog.
R.RegistrySettingItemForKey = function(key)
    local s = SETTINGS[key]
    if not s then return nil end
    return { kind = "setting", key = key, settingKey = key, label = s.label, setting = s, canOpen = true, canExplain = true }
end
R.RegistryLocationResultFollowups = function(entries, limit)
    local out = {}
    for i = 1, math.min(limit or 0, #(entries or {})) do
        out[i] = { kind = "setting", label = entries[i].item.label }
    end
    return out
end

local ctx = A.GetContext()
local function SetTurn(n) ctx.turnSerial = n; ctx.lastTurnSerial = n end
local function Remember(key, unit, label)
    A.RememberAppliedBundle({ action = "change", lastSetting = key, lastUnit = unit, label = label, undoAvailable = true })
end
local function AssertReadOnly(result)
    Check(type(result) == "table", "expected a result table")
    Check(result.status == "ambiguous" and result.result == "ambiguous", "reach-back must be read-only/ambiguous")
    Check(result.setting == nil and result.value == nil and result.action == nil
        and result.changes == nil and result.plan == nil and result.confirm == nil,
        "reach-back must never carry a mutation payload")
end

-- Build a three-subject conversation across three turns.
SetTurn(1); Remember("player.width", "player", "Player Width")
SetTurn(2); Remember("target.height", "target", "Target Height")
SetTurn(3); Remember("focus.scale", "focus", "Focus Scale")

-- 1. Ring order/shape: newest first, ageTurns relative to current turn.
local conv = A.ConversationContext()
Check(#conv.recentSubjects == 3, "ring must hold the three distinct subjects")
Check(conv.recentSubjects[1].settingKey == "focus.scale", "newest subject must be first")
Check(conv.recentSubjects[3].settingKey == "player.width", "oldest subject must be last")
Check(conv.recentSubjects[3].ageTurns == 2, "ageTurns must be current turn minus the entry turn")

-- 2. Dedup: re-touching an earlier subject moves it to the front, no duplicate.
SetTurn(4); Remember("player.width", "player", "Player Width")
conv = A.ConversationContext()
Check(#conv.recentSubjects == 3, "re-touching a subject must not grow the ring")
Check(conv.recentSubjects[1].settingKey == "player.width", "re-touched subject must move to the front")

-- 3. Bound: never exceeds the limit of five.
SetTurn(5); Remember("target.height", "target"); Remember("focus.scale", "focus")
SetTurn(6); Remember("player.width", "player"); Remember("target.height", "target")
Remember("focus.scale", "focus"); Remember("player.width", "player")
Check(#A.ConversationContext().recentSubjects <= 5, "ring must stay within its bound")

-- 4. Ordinal reach-back: "the first one" restates the newest ring subject, read-only.
local ordinalResult = R.RouterReachBackSubjectChoice("go back to the first one")
AssertReadOnly(ordinalResult)
Check(type(ordinalResult.searchResults) == "table" and #ordinalResult.searchResults == 1,
    "reach-back must offer exactly one selectable subject follow-up")

-- 5. "the other one" is ambiguous with several alternatives -> no guess.
Check(R.RouterReachBackSubjectChoice("change the other one") == nil,
    "'the other one' with multiple alternatives must not guess")

-- 6. "the other one" resolves when exactly one alternative remains recent.
-- Rebuild a fresh two-subject context so exactly one alternative exists.
DB.assistant.context = {}
ctx = A.GetContext()
SetTurn(1); Remember("player.width", "player", "Player Width")
SetTurn(2); Remember("target.height", "target", "Target Height")
-- Current subject is target.height (last remembered); the single alternative is player.width.
local otherResult = R.RouterReachBackSubjectChoice("what about the other frame")
AssertReadOnly(otherResult)
Check(otherResult.text:find("Player Width", 1, true), "'the other frame' must resolve to the single alternative")

-- 7. Named reach-back: "go back to the player one".
local namedResult = R.RouterReachBackSubjectChoice("go back to the player one")
AssertReadOnly(namedResult)
Check(namedResult.text:find("Player Width", 1, true), "named reach-back must resolve by subject token")

-- 8. Stale ring: an aged-out subject must not be reachable.
DB.assistant.context = {}
ctx = A.GetContext()
SetTurn(1); Remember("player.width", "player", "Player Width")
SetTurn(2); Remember("target.height", "target", "Target Height")
SetTurn(50) -- both entries are now far older than the max reach-back age
Check(R.RouterReachBackSubjectChoice("go back to the player one") == nil,
    "an aged-out subject must not be reachable")

-- 9. Non-reference text: nil, so the caller falls through to other fallbacks.
DB.assistant.context = {}
SetTurn(1); Remember("player.width", "player", "Player Width")
Check(R.RouterReachBackSubjectChoice("set player width to 300") == nil,
    "a concrete command must not be treated as a reach-back")
Check(R.RouterReachBackSubjectChoice("") == nil, "empty input must return nil")

-- 10. Empty ring: nil.
DB.assistant.context = {}
Check(R.RouterReachBackSubjectChoice("the other one") == nil, "an empty ring must return nil")

print("assistant_reach_back_subject_smoke: PASS")
