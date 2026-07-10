-- Data-only response policy for the Menu2 Assistant dialog adapter.
--
-- The Assistant core deliberately keeps one canonical set of technical English
-- answers.  This small table localizes stable conversation scaffolding without
-- cloning the setting/action registry or translating identifiers heuristically.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local Data = MSUF.AssistantDialogLocaleData or {}
MSUF.AssistantDialogLocaleData = Data

Data.version = 1
Data.defaultLanguage = "en"
Data.supportedLanguages = { en = true, de = true }
Data.maxPromptBytes = 512
Data.maxResponseBytes = 24000

Data.explicitLanguage = {
    de = {
        "antworte auf deutsch", "antwort auf deutsch", "bitte auf deutsch",
        "sprich deutsch", "deutsche antwort", "in german", "answer in german",
    },
    en = {
        "answer in english", "reply in english", "please use english",
        "speak english", "englische antwort", "antworte auf englisch",
    },
}

-- Weighted markers intentionally exclude MSUF setting names.  A prompt made only
-- from technical names is neutral and therefore keeps the current turn language.
Data.promptMarkers = {
    de = {
        ["aber"] = 1, ["alle"] = 1, ["alles"] = 1, ["auch"] = 1,
        ["ausblenden"] = 3, ["deaktivieren"] = 3, ["deutsch"] = 4,
        ["du"] = 2, ["einblenden"] = 3, ["einstellen"] = 2,
        ["fuer"] = 1, ["geht"] = 2, ["groesser"] = 2, ["hilfe"] = 2,
        ["ich"] = 2, ["ist"] = 1, ["kann"] = 2, ["kannst"] = 3,
        ["kleiner"] = 2, ["loeschen"] = 3, ["mach"] = 2, ["mache"] = 2,
        ["mein"] = 2, ["meine"] = 2, ["mehr"] = 2, ["mir"] = 2,
        ["nicht"] = 2, ["oeffne"] = 3, ["oder"] = 1, ["profil"] = 3,
        ["spieler"] = 3, ["sprache"] = 2, ["stelle"] = 2, ["suche"] = 3,
        ["und"] = 1, ["verstecken"] = 3, ["verschiebe"] = 3,
        ["warum"] = 4, ["was"] = 3, ["weiter"] = 2, ["welche"] = 3,
        ["welcher"] = 3, ["wie"] = 3, ["wo"] = 3, ["zeige"] = 3,
        ["ziel"] = 2, ["zurueck"] = 2,
    },
    en = {
        ["all"] = 1, ["also"] = 1, ["and"] = 1, ["answer"] = 2,
        ["bigger"] = 2, ["can"] = 2, ["change"] = 2, ["disable"] = 3,
        ["english"] = 4, ["explain"] = 3, ["find"] = 2, ["help"] = 2,
        ["hide"] = 3, ["how"] = 3, ["i"] = 2, ["is"] = 1,
        ["language"] = 2, ["me"] = 2, ["more"] = 2, ["my"] = 2,
        ["not"] = 2, ["open"] = 3, ["or"] = 1, ["please"] = 2,
        ["search"] = 3, ["show"] = 3, ["smaller"] = 2, ["tell"] = 2,
        ["the"] = 1, ["this"] = 1, ["what"] = 3, ["where"] = 3,
        ["which"] = 3, ["why"] = 4, ["you"] = 2,
    },
}

Data.neutralPrompts = {
    ["0"] = true, ["1"] = true, ["2"] = true, ["3"] = true,
    ["apply"] = true, ["cancel"] = true, ["confirm"] = true,
    ["current value"] = true, ["do it"] = true, ["explain"] = true,
    ["explain it"] = true, ["explain option 1"] = true, ["fix it"] = true,
    ["more"] = true, ["more details"] = true, ["ok"] = true, ["okay"] = true,
    ["open it"] = true, ["open result 1"] = true, ["option 1"] = true,
    ["option 2"] = true, ["redo"] = true, ["related options"] = true,
    ["show examples"] = true, ["show me where"] = true, ["stop"] = true,
    ["tell me more"] = true, ["undo"] = true, ["what does it do"] = true,
    ["where"] = true, ["why"] = true, ["yes"] = true,
}

Data.de = {
    exact = {
        ["Cancelled."] = "Abgebrochen.",
        ["Cancelled. I kept the options as they were."] = "Abgebrochen. Die Einstellungen bleiben unverändert.",
        ["Cancelled. MSUF stayed as it was."] = "Abgebrochen. MSUF bleibt unverändert.",
        ["Cancelled. I cleared the last search results."] = "Abgebrochen. Die letzten Suchergebnisse wurden verworfen.",
        ["Cancelled. Nothing was waiting for confirmation or a choice."] = "Es gab keine offene Bestätigung oder Auswahl. Es wurde nichts geändert.",
        ["Nothing is running right now."] = "Gerade läuft keine Assistant-Aufgabe.",
        ["I am working on that"] = "Ich bearbeite das gerade",
        ["I am working on that. Press Stop or type stop to cancel."] = "Ich bearbeite das gerade. Drücke Stopp oder schreibe stop, um abzubrechen.",
        ["I am still working on the previous request. Press Stop or type stop to cancel it."] = "Ich bearbeite noch die vorige Anfrage. Drücke Stopp oder schreibe stop, um sie abzubrechen.",
        ["MSUF menu changes have to wait until combat ends. Ask for the same change after combat ends."] = "MSUF-Menüänderungen müssen bis nach dem Kampf warten. Stelle dieselbe Änderungsanfrage danach erneut.",
        ["Which frame, page, or option do you want me to change?"] = "Welchen Frame, welche Seite oder welche Option soll ich ändern?",
        ["Which listed option do you want me to use? A number, label, or unit name is enough."] = "Welche aufgeführte Option meinst du? Eine Nummer, der genaue Name oder eine Unit genügt.",
        ["Which result do you mean?"] = "Welches Ergebnis meinst du?",
        ["Which page and option do you want me to use? Example: 'set target cast bar height to 20'."] = "Welche Seite und Option soll ich verwenden? Beispiel: 'set target cast bar height to 20'.",
        ["I found a likely match:"] = "Ich habe einen wahrscheinlichen Treffer gefunden:",
        ["I found multiple matches:"] = "Ich habe mehrere mögliche Treffer gefunden:",
        ["0. Cancel and keep it as it is."] = "0. Abbrechen und alles unverändert lassen.",
        ["Select one by number or label. Select 0 or cancel to keep it as it is."] = "Wähle per Nummer oder Name. Mit 0 oder cancel bleibt alles unverändert.",
        ["Select 1, yes, or 'fix it' to apply the repair. Select 0 or cancel to keep it as it is."] = "Wähle 1, yes oder 'fix it', um die Reparatur anzuwenden. Mit 0 oder cancel bleibt alles unverändert.",
        ["Select 1, yes, or 'apply it' to make the change. Select 0 or cancel to keep it as it is."] = "Wähle 1, yes oder 'apply it', um die Änderung anzuwenden. Mit 0 oder cancel bleibt alles unverändert.",
        ["Select 1, yes, or a natural answer like 'open it' to continue. Select 0 or cancel to keep it as it is."] = "Wähle 1, yes oder eine Antwort wie 'open it', um fortzufahren. Mit 0 oder cancel bleibt alles unverändert.",
        ["Yes, do it, or apply will continue. Cancel stops it."] = "Mit yes, do it oder apply fahre ich fort. Cancel bricht ab.",
        ["Next: ask for 'undo' to revert, or describe another follow-up change."] = "Als Nächstes: Mit 'undo' kannst du zurückgehen; alternativ beschreibst du eine weitere Änderung.",
        ["Large visual changes can take a moment to settle; /reload is recommended after checking the result."] = "Größere visuelle Änderungen können kurz brauchen. Prüfe das Ergebnis; danach ist /reload empfohlen.",
        ["Done. Reverted the last Assistant change."] = "Erledigt. Die letzte Assistant-Änderung wurde rückgängig gemacht.",
        ["Done. Reapplied the Assistant change."] = "Erledigt. Die Assistant-Änderung wurde erneut angewendet.",
        ["I have no Assistant change to undo."] = "Es gibt keine Assistant-Änderung zum Rückgängigmachen.",
        ["I have no Assistant change to redo."] = "Es gibt keine Assistant-Änderung zum Wiederholen.",
        ["Already set. MSUF already uses that value."] = "Bereits eingestellt. MSUF verwendet diesen Wert schon.",
        ["Already set. I refreshed the related MSUF option so the visible UI uses the current value."] = "Bereits eingestellt. Ich habe die betroffene MSUF-Option aktualisiert, damit die sichtbare UI den aktuellen Wert nutzt.",
        ["MSUF Assistant: what I can do"] = "MSUF Assistant: Das kann ich für dich tun",
        ["MSUF Assistant limits"] = "Grenzen des MSUF Assistant",
        ["Troubleshooting help"] = "Hilfe bei der Fehlersuche",
        ["Simple explanation help"] = "Einfache Erklärung",
        ["I'm the local in-game assistant for MSUF. I use MSUF's menu data on your client, so I don't call an external ChatGPT service."] = "Ich bin der lokale Ingame-Assistant für MSUF. Ich arbeite mit den MSUF-Menüdaten auf deinem Client und rufe keinen externen ChatGPT-Dienst auf.",
        ["I can find and explain MSUF options, open pages, import/export profiles, run checks, use undo/redo, and change MSUF options."] = "Ich kann MSUF-Optionen finden und erklären, Seiten öffnen, Profile importieren oder exportieren, Prüfungen ausführen, Undo/Redo verwenden und MSUF-Einstellungen ändern.",
        ["I can answer WoW questions near UI setup. For current class, talent, or patch guides I point to current external guides because MSUF runs offline."] = "Ich beantworte WoW-Fragen rund um das UI-Setup. Für aktuelle Klassen-, Talent- oder Patch-Guides verweise ich auf aktuelle externe Quellen, weil MSUF offline arbeitet.",
        ["I work locally from MSUF's own menu, registry, profile, and diagnostic data. I can help with MSUF UI setup and WoW UI readability, but I do not call an external AI service, browse the web, or know live class/talent tuning."] = "Ich arbeite lokal mit MSUF-Menü-, Registry-, Profil- und Diagnosedaten. Beim MSUF-Setup und der Lesbarkeit des WoW-UI helfe ich direkt; ich rufe aber keinen externen KI-Dienst auf, durchsuche nicht das Web und kenne kein Live-Tuning für Klassen oder Talente.",
        ["I also will not guess destructive profile actions, bypass WoW combat lockdown, or apply vague changes when several MSUF options could match. In those cases I explain the choice, ask for a specific target, or suggest a safe page to open."] = "Ich rate nicht bei destruktiven Profilaktionen, umgehe den WoW-Combat-Lockdown nicht und wende keine vage Änderung an, wenn mehrere MSUF-Optionen passen könnten. Dann erkläre ich die Auswahl, frage nach dem genauen Ziel oder schlage eine sichere Seite zum Öffnen vor.",
        ["Yes, for MSUF and WoW UI setup. I run locally inside MSUF instead of calling an external ChatGPT service, so I use the addon menu, registry, and current profile state that exist on your client."] = "Ja – für MSUF und das WoW-UI-Setup. Ich laufe lokal in MSUF, statt einen externen ChatGPT-Dienst aufzurufen, und nutze das Addon-Menü, die Registry und den aktuellen Profilzustand auf deinem Client.",
        ["I can answer MSUF questions, find options, open pages, run checks, apply concrete safe changes, and help with undo or redo."] = "Ich kann MSUF-Fragen beantworten, Optionen finden, Seiten öffnen, Prüfungen ausführen, konkrete sichere Änderungen anwenden und bei Undo oder Redo helfen.",
        ["My limits: I do not browse live patch data, invent current class or talent guides, or bypass WoW combat restrictions. For live guides I point you to current external resources, and for protected changes I wait until they are safe."] = "Meine Grenzen: Ich durchsuche keine Live-Patchdaten, erfinde keine aktuellen Klassen- oder Talent-Guides und umgehe keine WoW-Kampfbeschränkungen. Für Live-Guides verweise ich auf aktuelle externe Quellen; geschützte Änderungen führe ich nur sicher außerhalb des Kampfes aus.",
        ["Suggested fixes:"] = "Vorgeschlagene Lösungen:",
        ["Safety: I ask before importing, deleting, resetting, or copying profiles. For imports, you can export or copy the current profile first."] = "Sicherheit: Vor Import, Löschen, Zurücksetzen oder Kopieren eines Profils frage ich nach. Vor einem Import kannst du das aktuelle Profil zuerst exportieren oder kopieren.",
    },
    labels = {
        ["Examples: "] = "Beispiele: ",
        ["Example: "] = "Beispiel: ",
        ["Useful next prompts: "] = "Sinnvolle nächste Eingaben: ",
        ["You can ask: "] = "Du kannst fragen: ",
        ["You can also ask: "] = "Du kannst auch fragen: ",
        ["Current value: "] = "Aktueller Wert: ",
        ["Current live value: "] = "Aktueller Live-Wert: ",
        ["Page: "] = "Seite: ",
        ["Path: "] = "Pfad: ",
        ["Setting key: "] = "Setting-Key: ",
        ["Setting: "] = "Einstellung: ",
        ["Action: "] = "Aktion: ",
        ["What it changes: "] = "Wirkung: ",
        ["Where: "] = "Fundort: ",
        ["Why: "] = "Warum: ",
        ["Note: "] = "Hinweis: ",
        ["Recommended: "] = "Empfehlung: ",
    },
    fallbackLead = {
        applied = "Erledigt. Die MSUF-Änderung wurde angewendet.",
        unchanged = "Das ist bereits so eingestellt.",
        confirmation_needed = "Bevor ich das ändere, brauche ich deine Bestätigung.",
        ambiguous = "Ich brauche noch eine kurze Auswahl oder Präzisierung.",
        failed = "Das konnte ich noch nicht sicher zuordnen.",
        combat = "Im Kampf führe ich keine Assistant-Arbeit aus.",
        queued = "Die Anfrage wartet noch auf ihre Ausführung.",
        busy = "Ich bearbeite noch die vorige Anfrage.",
        navigated = "Die passende MSUF-Ansicht wurde geöffnet.",
        navigation = "Die passende MSUF-Ansicht wurde geöffnet.",
        info = "Hier ist die passende MSUF-Information.",
    },
    technicalLead = "Technische Details mit unveränderten MSUF-Namen:",
}
