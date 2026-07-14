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
local M = assert(_G.MSUF_NS.MSUF2, "Menu namespace missing after dashboard smoke")

local germanTerms = {
    "zeige", "anzeigen", "oeffne", "waehle", "einstellungen", "assistent",
    "zurueck", "rueck", "nicht", "keine", "abbrechen", "anwenden",
    "ausfuehren", "loeschen", "kopiere", "verschiebe", "groesse",
    "nenn", "nenne", "de", "gruppenlayout", "sonderbereich",
}

local rawPhrases = {
    "copy from profile default",
    "nenn es raid kopie",
    "zu raid neu",
    "zeige castbar einstellungen",
    "target cast bar hoehe 24",
    "target cast bar hoehe 25",
    "target cast bar hoehe 24 und focus cast bar hoehe 20",
    "abbrechen",
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

local function closePanel()
    if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() else A.largeTextPanel = nil end
end

local function resetTransient()
    closePanel()
    A.pendingChoices = nil
    A.pendingResults = nil
    A.pendingSelectedResult = nil
    A.pendingConfirmation = nil
    A.lastAssistantHelpContext = nil
    local ctx = A.GetContext and A.GetContext() or nil
    if type(ctx) == "table" then
        ctx.pendingChoices = nil
        ctx.pendingResults = nil
        ctx.pendingSelectedResult = nil
        ctx.pendingConfirmation = nil
    end
    if type(A.ClearPendingFlow) == "function" then A.ClearPendingFlow() end
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

local function assertNoPendingChoices(label)
    local ctx = A.GetContext and A.GetContext() or nil
    assert(A.pendingChoices == nil, label .. ": stale root pending choices")
    assert(not (type(ctx) == "table" and ctx.pendingChoices ~= nil), label .. ": stale context pending choices")
end

resetTransient()
submit("copy from profile Default", "info", "What do you want me to call the copy")
submit("call it ''", "confirmation_needed", "Say 'cancel' or 'never mind' to stop.")
assert(A.Workflow.PendingFlow() and A.Workflow.PendingFlow().kind == "profileCopyDestination", "empty quoted copy name cleared the pending profile-copy flow")
assert(A.pendingConfirmation == nil, "empty quoted copy name created a confirmation")
submit("nenn es Raid Kopie", "confirmation_needed", "Copy profile Default to Raid Kopie")
submit("cancel", "applied", "Cancelled.")

resetTransient()
submit("rename profile Raid", "info", "What should the new name be")
submit("to ''", "confirmation_needed", "Say 'cancel' or 'never mind' to stop.")
assert(A.Workflow.PendingFlow() and A.Workflow.PendingFlow().kind == "profileRenameDestination", "empty quoted rename name cleared the pending profile-rename flow")
assert(A.pendingConfirmation == nil, "empty quoted rename name created a confirmation")
submit("zu Raid Neu", "confirmation_needed", "Rename profile Raid to Raid Neu")
submit("cancel", "applied", "Cancelled.")

resetTransient()
_G.MSUF_DB.player.showName = true
submit("spieler name aus", "applied", "I changed Player Name")
submit("zeige castbar einstellungen", "ambiguous", "I found multiple matches")
submit("undo", "applied", "Reverted")

resetTransient()
_G.MSUF_DB.target.castbarHeight = 18
submit("target cast bar hoehe 25", "applied", "Target Castbar Height")
submit("reset profile", "confirmation_needed", "Reset active profile")
submit("undo", "applied", "Reverted")

resetTransient()
_G.MSUF_DB.target.castbarHeight = 18
_G.MSUF_DB.focus.castbarHeight = 18
submit("target cast bar hoehe 24 und focus cast bar hoehe 20", "applied", "2 MSUF options")
submit("undo", "applied", "Reverted")

resetTransient()
submit("copy party to raid", "applied", "Party group-frame options to Raid")
submit("undo", "applied", "Reverted")

resetTransient()
submit("reset profile", "confirmation_needed", "Reset active profile")
submit("abbrechen", "failed", "Cancelled.")

resetTransient()
_G.MSUF_DB.target.showBuffs = false
M.activeKey = "auras3"
submit("target buffs not shown", "info", "Suggested fixes")
submit("what can i do on this page", "info", "Assistant help for Auras:")
assert(_G.MSUF_DB.target.showBuffs == false, "fresh page-help question should not apply the pending aura fix")
assertNoPendingChoices("fresh page-help question")

resetTransient()
_G.MSUF_DB.target.showBuffs = false
submit("target buffs not shown", "info", "Suggested fixes")
submit("dispellable debuffs are hard to see", "info", "Dispel visibility help")
assert(_G.MSUF_DB.target.showBuffs == false, "fresh signal question should not apply the pending aura fix")
assertNoPendingChoices("fresh signal question")

resetTransient()
_G.MSUF_DB.target.showBuffs = false
submit("target buffs not shown", "info", "Suggested fixes")
submit("what are class resources", "info", "Class Resources help")
assert(_G.MSUF_DB.target.showBuffs == false, "fresh knowledge question should not apply the pending aura fix")
assertNoPendingChoices("fresh knowledge question")

resetTransient()
submit("make my raid frames easier to read", "info", "Group frame readability help")
submit("what should i change first", "info", "least destructive visible setting")
submit("open that", "navigated", "Opened Group Layout")
submit("show examples", "info", "set raid scale")
submit("make it smaller", "info", "Name the exact MSUF area")

resetTransient()
submit("what should i change first", "info", "native MSUF guided setup")

resetTransient()
submit("make target buffs easier to read", "info", "Aura readability help")
submit("what should i change first", "info", "Aura readability help")
submit("open that", "navigated", "Opened Target and focused Aura Buffs")
submit("make target buffs size 30", "applied", "Target Buff Icon Size")

resetTransient()
_G.MSUF_DB.auras3.target = _G.MSUF_DB.auras3.target or {}
_G.MSUF_DB.auras3.target.buff = { size = 26 }
_G.MSUF_DB.auras3.target.debuff = { size = 26 }
submit("make target buffs bigger", "applied", "Target Buff Icon Size")
submit("same for debuffs", "applied", "Target Debuff Icon Size")

resetTransient()
_G.MSUF_DB.target.portraitMode = "OFF"
_G.MSUF_DB.focus.portraitMode = "OFF"
submit("turn off target portrait", "unchanged", "Already set. Target Portrait Position is already off.")
local unchangedReport = submit("what did you change", "info", "Target Portrait Position was already off.")
assert(not tostring(unchangedReport.text or ""):find("undo", 1, true), "unchanged last-change report should not offer undo: " .. tostring(unchangedReport.text or ""))
submit("same for focus", "unchanged", "Already set. Focus Portrait Position is already off.")

resetTransient()
A.SetPendingResults({
    { kind = "action", actionKey = "support_links_summary", label = "Show Support Links", page = "gf_layout", pageLabel = "DE Gruppenlayout" },
})
submit("explain result 1", "info", "Page: Group Layout")

resetTransient()
A.SetPendingResults({
    { kind = "action", actionKey = "support_links_summary", label = "Show Support Links", pageLabel = "DE Sonderbereich" },
})
submit("why result 1", "info", "on Assistant")

resetTransient()
local openPage = assert(A.Registry and A.Registry.GetAction and A.Registry:GetAction("open_page"), "open_page action missing")
A.pendingChoices = {
    { action = openPage, actionKey = "open_page", args = { page = "gf_layout", label = "DE Gruppenlayout" }, label = "Open Group Layout" },
}
submit("explain option 1", "info", "Page: Group Layout")

io.write("assistant_followup_surface_output_audit: ok cases=36\n")
