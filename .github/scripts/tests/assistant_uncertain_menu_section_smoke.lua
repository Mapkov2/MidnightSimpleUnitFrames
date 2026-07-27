-- An unresolved request must hand the player the relevant part of the menu.
--
-- Reported in-game: "change reseted icon" answered with "Show options for the
-- current Group Layout page / Show general Assistant examples" -- neither
-- mentions the rested icon. Three independent causes, each pinned here:
--   1. the low-confidence path never consulted the knowledge index at all
--   2. the leading verb dragged the ranking onto an unrelated page
--      ("rested icon" scores 760 on Player, "change rested icon" 485 on Group Auras)
--   3. the typo was never corrected ("reseted" scores 507 on an unrelated control)
--
-- Two guards keep the answer from becoming confidently wrong: a score floor, and
-- respecting Knowledge.Search's cold-index sentinel (nil is "index not ready",
-- NOT "no matches").
_G = _G or _ENV

local root = arg and arg[1] or "."

local function Check(value, message)
    if not value then error(message or "check failed", 2) end
end

local function Exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local MSUF = { MSUF2 = {}, Assistant = {} }
_G.MSUF_NS, _G.MSUF2 = MSUF, MSUF.MSUF2
local loader = root .. "/tools/assistant_runtime_manifest_loader.lua"
dofile(Exists(loader) and loader or (root .. "/../tools/assistant_runtime_manifest_loader.lua"))
local dashboard = root .. "/tools/assistant_dashboard_smoke.lua"
dofile(Exists(dashboard) and dashboard or (root .. "/../../tools/assistant_dashboard_smoke.lua"))
local A = _G.MSUF_NS.Assistant
if A.AutoCoverage and A.AutoCoverage.EnsureFilled then pcall(A.AutoCoverage.EnsureFilled) end
-- The branch under test is deliberately silent while the index is cold, so warm
-- it first; the cold behaviour is asserted separately below.
if A.Knowledge and A.Knowledge.EnsureIndex then A.Knowledge.EnsureIndex() end

local R = A.RouterPrivate or A.Router
Check(type(R) == "table", "router private table missing")
Check(type(R.CorrectControlTypos) == "function", "typo correction must be exported")

local function Reset()
    A.pendingChoices, A.pendingCandidates = nil, nil
    A.pendingConfirmation, A.pendingFlow = nil, nil
    A.lastAssistantHelpContext, A.lastAssistantPlanningContext = nil, nil
    A._helpContextRestored = nil
    if type(A.GetContext) == "function" then
        local ctx = A.GetContext()
        for key in pairs(ctx) do ctx[key] = nil end
    end
end

local function Say(text)
    Reset()
    local ok, result = pcall(A.HandleInput, text)
    Check(ok, "HandleInput errored on '" .. text .. "': " .. tostring(result))
    return tostring((result or {}).text or "")
end

-- 1. Typo correction maps onto a real control word, and only that.
Check(R.CorrectControlTypos("change reseted icon") == "change rested icon",
    "'reseted' must be corrected to 'rested', got: "
    .. tostring(R.CorrectControlTypos("change reseted icon")))
Check(R.CorrectControlTypos("change rested icon") == nil,
    "a correctly spelled request must report no correction")
-- A word nowhere near the vocabulary must not be "corrected" into something.
Check(R.CorrectControlTypos("qqqzzzwww") == nil,
    "an unrelated word must not be rewritten into a control word")

-- 2. The reported request must now name the section the control lives on.
local reported = Say("change reseted icon")
Check(reported:find("Show the ", 1, true) ~= nil,
    "the misspelled request must offer a menu section:\n" .. reported)
Check(reported:find("Player", 1, true) ~= nil,
    "the rested icon lives on the Player page; that section must be offered:\n" .. reported)

-- 3. The offer must never be the only thing shown -- generic help stays as the
--    last resort, so a wrong section guess is never the sole option.
Check(reported:find("Show general Assistant examples", 1, true) ~= nil,
    "generic help must remain available alongside the section offer:\n" .. reported)

-- 4. The score floor: a request with no plausible control must NOT name a page.
local nonsense = Say("change qqqzzzwww")
Check(nonsense:find("Show the ", 1, true) == nil,
    "a request with no plausible control must not name a menu section:\n" .. nonsense)

-- 5. The cold-index sentinel must not be read as "no matches". Simulated by
--    replacing Search with the documented cold return; the branch must stay
--    silent rather than erroring or inventing a section.
do
    local knowledge = A.Knowledge
    local realSearch = knowledge.Search
    knowledge.Search = function() return nil end
    local coldOk, coldResult = pcall(A.HandleInput, "change reseted icon")
    knowledge.Search = realSearch
    Check(coldOk, "a cold knowledge index must not break the uncertain path: " .. tostring(coldResult))
    local coldText = tostring((coldResult or {}).text or "")
    Check(coldText:find("Show the ", 1, true) == nil,
        "a cold index must not produce a section offer:\n" .. coldText)
end

print("assistant_uncertain_menu_section_smoke: PASS")
