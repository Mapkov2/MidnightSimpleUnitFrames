_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing after dashboard smoke")
local M = assert(_G.MSUF2 or (_G.MSUF_NS and _G.MSUF_NS.MSUF2),
    "MSUF menu namespace missing after dashboard smoke")

local germanTerms = {
    "zeige", "anzeigen", "oeffne", "waehle", "einstellungen", "assistent",
    "zurueck", "rueck", "nicht", "keine", "abbrechen", "anwenden",
    "ausfuehren", "loeschen", "kopiere", "verschiebe", "groesse",
}

local rawPhrases = {
    "nein danke",
    "abbrechen",
    "spieler name aus",
    "zeige busy",
}

local function normalizedWords(text)
    return " " .. tostring(text or ""):lower():gsub("[%p%c]", " "):gsub("%s+", " ") .. " "
end

local function assertEnglishOutput(label, output)
    local haystack = normalizedWords(output)
    for _, term in ipairs(germanTerms) do
        assert(not haystack:find(" " .. term .. " ", 1, true), label .. ": output contains German visible term " .. term .. ": " .. tostring(output))
    end
    local lower = tostring(output or ""):lower()
    for _, phrase in ipairs(rawPhrases) do
        assert(not lower:find(phrase, 1, true), label .. ": output repeated raw phrase " .. phrase .. ": " .. tostring(output))
    end
end

local function submit(input, expectedStatus, contains)
    local result = A.Submit(input)
    assert(type(result) == "table", input .. ": missing result")
    local status = result.status or result.result
    assert(status == expectedStatus, input .. ": expected " .. tostring(expectedStatus) .. ", got " .. tostring(status) .. ": " .. tostring(result.text or ""))
    assertEnglishOutput(input, result.text or "")
    if contains then
        assert(tostring(result.text or ""):find(contains, 1, true), input .. ": missing text " .. tostring(contains) .. ": " .. tostring(result.text or ""))
    end
    return result
end

submit("delete profile Raid", "confirmation_needed", "Answer with 'yes'")
submit("nein danke", "failed", "Cancelled.")

-- The dashboard smoke deliberately finishes on Party Group Layout. Prove the
-- page-aware contract first: on that visible page, a terse name command owns
-- Party Names and should not fan out into a global choice.
local partyNames = assert(A.Registry and A.Registry:GetSetting("gf_party.showName"),
    "Party Names setting missing")
partyNames.set(true)
submit("name off", "applied", "Party Names")
assert(partyNames.get() == false, "visible Party page did not own the terse name command")

-- The next dialogue case intentionally has no visible or remembered scope.
-- Clear both sources instead of inheriting the dashboard fixture's page and
-- mistaking correct page-aware behavior for a stale-context runtime bug.
local oldActiveKey, oldGfScope = M.activeKey, M.gfScope
M.activeKey, M.gfScope = nil, nil
local ctx = type(A.GetContext) == "function" and A.GetContext() or nil
if type(ctx) == "table" then for key in pairs(ctx) do ctx[key] = nil end end
submit("name off", "ambiguous", "I found")
submit("wat", "ambiguous", "Which listed option")
submit("abbrechen", "info", "Cancelled.")
M.activeKey, M.gfScope = oldActiveKey, oldGfScope

local oldInCombat = _G.InCombatLockdown
local oldUnitCombat = _G.UnitAffectingCombat
_G.InCombatLockdown = function() return true end
_G.UnitAffectingCombat = function() return true end
submit("spieler name aus", "combat", "wait until combat ends")
_G.InCombatLockdown = oldInCombat
_G.UnitAffectingCombat = oldUnitCombat

A.SetBusy(true)
assertEnglishOutput("busy text", A.GetBusyText and A.GetBusyText() or "")
A.SetBusy(false)

io.write("assistant_dialog_output_audit: ok cases=8\n")
