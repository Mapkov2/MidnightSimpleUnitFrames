_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

local MSUF = assert(_G.MSUF_NS, "MSUF namespace missing")
local M = assert(MSUF.MSUF2, "Menu2 namespace missing")
local A = assert(MSUF.Assistant, "Assistant missing")

local loaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local RuntimeManifest = dofile(loaderPath)
local runtimeEntries = RuntimeManifest.ReadRuntimeEntries()

local loadedMenuScripts = {}
local function loadMenuScript(entry)
    if loadedMenuScripts[entry.relative] then return end
    loadedMenuScripts[entry.relative] = true
    local chunk, err = loadfile(entry.path)
    assert(chunk, err)
    return chunk("MidnightSimpleUnitFrames_Assistant", MSUF)
end

local localeScripts = 0
local localeRuntimePath
for _, entry in ipairs(runtimeEntries) do
    local relative = entry.relative
    if relative:match("^MSUF_Menu2_AssistantDialogLocale[_%w]*%.lua$") then
        localeScripts = localeScripts + 1
        if relative:find("_Data%.lua$") then
            if type(MSUF.AssistantDialogLocaleData) ~= "table" then loadMenuScript(entry) end
        elseif not (A.DialogLocale and A.DialogLocale.installed == true) then
            localeRuntimePath = entry.path
            loadMenuScript(entry)
        else
            localeRuntimePath = entry.path
        end
    end
end
assert(localeScripts == 2, "expected exactly two dialog locale scripts in Assistant runtime manifest")

local D = assert(A.DialogLocale, "dialog locale adapter missing")
assert(D.installed == true, "dialog locale adapter was not installed")

local menuOpen = true
if type(M.frame) ~= "table" then M.frame = {} end
M.frame.IsShown = function() return menuOpen end

local inCombat = false
_G.InCombatLockdown = function() return inCombat end
_G.UnitAffectingCombat = function() return inCombat end

local function clearConversationState()
    A.pendingChoices = nil
    A.pendingCandidates = nil
    A.pendingConfirmation = nil
    A.pendingFlow = nil
    A.pendingResults = nil
    A.pendingSelectedResult = nil
    A.lastAssistantHelpContext = nil
    A.lastAssistantPlanningContext = nil
    local ctx = A.GetContext and A.GetContext() or nil
    if type(ctx) == "table" then
        ctx.pendingChoices = nil
        ctx.pendingCandidates = nil
        ctx.pendingConfirmation = nil
        ctx.pendingFlow = nil
        ctx.pendingResults = nil
        ctx.pendingSelectedResult = nil
    end
end

local function statusOf(result)
    return type(result) == "table" and (result.status or result.result) or nil
end

local function hasGermanScaffold(text)
    text = tostring(text or "")
    local markers = {
        "Erledigt", "Bereits eingestellt", "Hier ist", "Ich brauche", "Welche",
        "Aktueller Wert", "Hilfe:", "Assistant-Hilfe", "Technische Details",
        "Abgebrochen", "wurde geöffnet", "Grenzen des MSUF Assistant",
    }
    for i = 1, #markers do
        if text:find(markers[i], 1, true) then return true end
    end
    return false
end

-- Deterministic language policy: explicit language wins, strong prompt language
-- switches, and short/technical follow-ups retain the previous language.
assert(D.DetectPromptLanguage("warum sehe ich meine buffs nicht", "en", "en") == "de", "German detection failed")
assert(D.DetectPromptLanguage("öffne die Auren", "en", "en") == "de", "German UTF-8 detection failed")
assert(D.DetectPromptLanguage("größer und schöner", "en", "en") == "de", "German umlaut normalization failed")
assert(D.DetectPromptLanguage("where can I change target buffs", "de", "de") == "en", "English detection failed")
assert(D.DetectPromptLanguage("option 1", "de", "en") == "de", "neutral follow-up did not retain German")
assert(D.DetectPromptLanguage("option 1", "en", "de") == "en", "neutral follow-up did not retain English")
assert(D.DetectPromptLanguage("open it", "de", "en") == "de", "English-form follow-up did not retain German context")
assert(D.DetectPromptLanguage("why", "de", "en") == "de", "short follow-up did not retain German context")
assert(D.DetectPromptLanguage("bitte answer in English", "de", "de") == "en", "explicit English did not win")
assert(D.DetectPromptLanguage("please answer in German", "en", "en") == "de", "explicit German did not win")
assert(D.DetectPromptLanguage("welche addons passen gut zu msuf", "en", "en") == "de", "German addon question detection failed")

-- Canonical technical names and keys remain byte-for-byte intact in localized
-- dynamic templates.
local technical = "Done. I changed MSUF Style Module (general.styleEnabled) from enabled to disabled."
local localizedTechnical, technicalMode = D.LocalizeText(technical, "de", "applied")
assert(technicalMode == "localized", "technical change did not use the deterministic template")
assert(localizedTechnical:find("MSUF Style Module", 1, true), "setting name was translated or lost")
assert(localizedTechnical:find("general.styleEnabled", 1, true), "setting key was translated or lost")
assert(localizedTechnical:find("enabled", 1, true) and localizedTechnical:find("disabled", 1, true), "technical values were translated or lost")
assert(D.LocalizeText(technical, "en", "applied") == technical, "English output was not an identity transform")

-- The adapter is a strict presentation-only gate. Closed-menu and combat calls
-- stop before parser, setting getters, history, callbacks, or localization work.
D.ResetSession("en")
local parseCalls = 0
local originalParse = A.Parse
A.Parse = function(...)
    parseCalls = parseCalls + 1
    return originalParse(...)
end
local showNameSetting = assert(A.Registry:GetSetting("player.showName"), "player.showName setting missing")
local getterCalls = 0
local originalShowNameGetter = showNameSetting.get
showNameSetting.get = function(...)
    getterCalls = getterCalls + 1
    return originalShowNameGetter(...)
end
local historyBeforeGate = #(A.GetHistory and A.GetHistory() or {})
menuOpen = false
clearConversationState()
local closed = assert(A.Submit("was kannst du alles"), "closed-menu result missing")
assert(statusOf(closed) == "inactive", "closed-menu submit did not return the constant inactive reply")
assert(closed.reason == "menu_closed", "closed-menu reply reason missing")
assert(tostring(closed.text or "") == "Open the MSUF menu to use the Assistant. / Öffne das MSUF-Menü, um den Assistant zu verwenden.", "closed-menu reply was not constant")
local closedReport = D.GetCoverageReport()
assert(closedReport.turns == 0, "closed-menu gate performed dialog work")
assert(parseCalls == 0 and getterCalls == 0, "closed-menu gate reached parser or registry getter")
assert(#(A.GetHistory and A.GetHistory() or {}) == historyBeforeGate, "closed-menu gate wrote Assistant history")

local deferredCallbackCalls = 0
local closedDeferred = assert(A.SubmitDeferred("was kannst du alles", function() deferredCallbackCalls = deferredCallbackCalls + 1 end), "closed-menu deferred result missing")
assert(statusOf(closedDeferred) == "inactive", "closed-menu deferred submit did not return inactive")
assert(deferredCallbackCalls == 0, "closed-menu deferred gate invoked callback")
assert(parseCalls == 0 and getterCalls == 0, "closed-menu deferred gate reached Assistant core")
assert(#(A.GetHistory and A.GetHistory() or {}) == historyBeforeGate, "closed-menu deferred gate wrote history")

menuOpen = true
inCombat = true
local showNameBeforeCombat = _G.MSUF_DB.player and _G.MSUF_DB.player.showName
local combat = assert(A.Submit("spieler name aus"), "combat result missing")
assert(statusOf(combat) == "inactive" and combat.reason == "combat", "combat request did not return inactive/combat")
assert(tostring(combat.text or "") == "Assistant work is disabled during combat. / Assistant-Arbeit ist im Kampf deaktiviert.", "combat reply was not constant")
assert((_G.MSUF_DB.player and _G.MSUF_DB.player.showName) == showNameBeforeCombat, "combat request mutated player.showName")
local combatReport = D.GetCoverageReport()
assert(combatReport.turns == 0, "combat gate performed dialog work")
assert(parseCalls == 0 and getterCalls == 0, "combat gate reached parser or registry getter")
assert(#(A.GetHistory and A.GetHistory() or {}) == historyBeforeGate, "combat gate wrote Assistant history")
inCombat = false
showNameSetting.get = originalShowNameGetter
A.Parse = originalParse

-- German informational prompt and German follow-ups keep German. Questions must
-- not alter the addressed gameplay setting.
clearConversationState()
D.ResetSession("en")
local showNameBeforeQuestion = _G.MSUF_DB.player and _G.MSUF_DB.player.showName
local germanQuestion = assert(A.Submit("wie kann ich den spieler namen ausblenden"), "German question result missing")
assert(hasGermanScaffold(germanQuestion.text), "German question was answered without German scaffolding: " .. tostring(germanQuestion.text))
assert(D.GetLanguage() == "de", "German language was not retained")
assert((_G.MSUF_DB.player and _G.MSUF_DB.player.showName) == showNameBeforeQuestion, "German question mutated player.showName")

local englishFormFollowup = assert(A.Submit("open it"), "English-form follow-up result missing")
assert(D.GetLanguage() == "de", "English-form follow-up lost German conversation context")
assert(hasGermanScaffold(englishFormFollowup.text), "English-form follow-up was not answered in German")
assert((_G.MSUF_DB.player and _G.MSUF_DB.player.showName) == showNameBeforeQuestion, "navigation follow-up mutated player.showName")

local germanFollowup = assert(A.Submit("warum"), "German follow-up result missing")
assert(D.GetLanguage() == "de", "German follow-up lost the turn language")
assert(hasGermanScaffold(germanFollowup.text), "German follow-up was not localized: " .. tostring(germanFollowup.text))
assert((_G.MSUF_DB.player and _G.MSUF_DB.player.showName) == showNameBeforeQuestion, "German follow-up mutated player.showName")

local neutralFollowup = assert(A.Submit("option 1"), "neutral follow-up result missing")
assert(D.GetLanguage() == "de", "neutral follow-up did not retain German")
assert(hasGermanScaffold(neutralFollowup.text), "neutral German-context follow-up was not localized")

-- Curated addon guidance is natural prose, so every line must be translated
-- instead of falling back to an English technical wrapper.
clearConversationState()
D.ResetSession("en")
local germanAddons = assert(A.Submit("welche addons passen gut zu msuf"), "German addon result missing")
local germanAddonText = tostring(germanAddons.text or "")
assert(statusOf(germanAddons) == "info", "German addon guidance was not read-only info")
assert(D.GetLanguage() == "de", "German addon question did not retain German")
assert(germanAddonText:find("Addons, die gut zu MSUF passen", 1, true),
    "German addon heading was not localized: " .. germanAddonText)
assert(germanAddonText:find("Enhance QoL (EQoL)", 1, true), "German addon guidance omitted EQoL")
assert(not germanAddonText:find("Technische Details", 1, true),
    "German addon guidance fell back to the mixed-language technical wrapper: " .. germanAddonText)
assert(not germanAddonText:find("Verified MSUF integrations", 1, true),
    "German addon guidance retained untranslated natural prose: " .. germanAddonText)

-- An explicit English turn switches back and stays canonical English.
clearConversationState()
local english = assert(A.Submit("answer in English what are your limits"), "English result missing")
assert(D.GetLanguage() == "en", "explicit English did not switch language")
assert(tostring(english.text or ""):find("MSUF Assistant limits", 1, true), "English canonical answer was changed")
assert(not hasGermanScaffold(english.text), "English answer contains German scaffolding")

-- The Dashboard uses SubmitDeferred. Its returned value, callback value, and
-- recorded history must share the same language when the gate is open.
clearConversationState()
local deferredCallbacks = 0
local deferredCallbackResult
local deferred = assert(A.SubmitDeferred("was kannst du nicht", function(result)
    deferredCallbacks = deferredCallbacks + 1
    deferredCallbackResult = result
end), "open-menu deferred result missing")
assert(deferredCallbacks == 1, "open-menu deferred callback did not complete exactly once")
assert(hasGermanScaffold(deferred.text), "open-menu deferred return was not localized")
assert(deferredCallbackResult and hasGermanScaffold(deferredCallbackResult.text), "open-menu deferred callback was not localized")

-- German mutation responses localize the transaction status while retaining the
-- real control label. Undo keeps the same language context.
clearConversationState()
local mutation = assert(A.Submit("spieler name aus"), "German mutation result missing")
assert(statusOf(mutation) == "applied" or statusOf(mutation) == "unchanged", "German mutation returned unexpected status: " .. tostring(statusOf(mutation)))
assert(hasGermanScaffold(mutation.text), "German mutation status was not localized: " .. tostring(mutation.text))
assert(tostring(mutation.text or ""):find("Player Name", 1, true), "canonical Player Name label was lost")
local undo = assert(A.Submit("rueckgaengig"), "German undo result missing")
assert(D.GetLanguage() == "de", "German undo lost language context")
assert(hasGermanScaffold(undo.text), "German undo response was not localized: " .. tostring(undo.text))

-- History receives the same localized result because adaptation occurs before the
-- canonical recorder, rather than via a global AddHistory hook.
local history = A.GetHistory and A.GetHistory() or {}
local latestAssistant
for i = #history, 1, -1 do
    if history[i] and history[i].role == "assistant" then latestAssistant = history[i]; break end
end
assert(latestAssistant and hasGermanScaffold(latestAssistant.text), "localized result did not reach Assistant history")

-- Hot-path budget: pure detector and template adaptation remain small and linear.
local started = os.clock()
for i = 1, 10000 do
    D.DetectPromptLanguage((i % 2 == 0) and "warum sehe ich target buffs nicht" or "where are target buffs", "de", "en")
end
for i = 1, 2000 do
    D.LocalizeText(technical, "de", "applied")
end
local elapsedMs = (os.clock() - started) * 1000
assert(elapsedMs < 750, "dialog locale hot path exceeded budget: " .. tostring(elapsedMs) .. "ms")

local report = D.GetCoverageReport()
assert(report.events == 0 and report.timers == 0 and report.onUpdates == 0 and report.warmups == 0, "zero-idle contract missing")
assert(report.menuOpenRequired == true and report.combatAllowed == false, "runtime gates missing from coverage report")
assert(report.deTurns >= 4 and report.enTurns >= 1, "turn coverage accounting incomplete")
assert(report.germanAdapted >= 4, "German output coverage accounting incomplete")

-- Static proof that the adapter cannot schedule background or idle work.
local sourceHandle = assert(io.open(localeRuntimePath, "r"))
local source = sourceHandle:read("*a")
sourceHandle:close()
for _, forbidden in ipairs({ "_G.CreateFrame", "C_Timer.", ":SetScript", ":RegisterEvent", "OnUpdate =" }) do
    assert(not source:find(forbidden, 1, true), "adapter contains forbidden background primitive: " .. forbidden)
end

io.write(string.format(
    "assistant_dialog_locale_audit: ok deTurns=%d enTurns=%d adapted=%d hotPathMs=%.3f\n",
    report.deTurns, report.enTurns, report.germanAdapted, elapsedMs
))
