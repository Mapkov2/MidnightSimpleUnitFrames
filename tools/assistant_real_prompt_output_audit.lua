_G = _G or _ENV

local verbose = not (type(arg) == "table" and arg[1] == "--quiet")

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local sourcePath = debug and debug.getinfo and debug.getinfo(1, "S").source or ""
if sourcePath:sub(1, 1) == "@" then sourcePath = sourcePath:sub(2) end
local sourceDir = sourcePath:match("^(.*[/\\])") or ""
local smokeCandidates = {
    sourceDir .. "assistant_dashboard_smoke.lua",
    "tools/assistant_dashboard_smoke.lua",
    "../tools/assistant_dashboard_smoke.lua",
    "../../tools/assistant_dashboard_smoke.lua",
}
local smoke
for i = 1, #smokeCandidates do
    if exists(smokeCandidates[i]) then
        smoke = smokeCandidates[i]
        break
    end
end
assert(smoke, "assistant_dashboard_smoke.lua not found")
dofile(smoke)

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing after dashboard smoke")

-- The product menu owns the exact-control navigation facade. The headless
-- Dashboard smoke does not load that menu layer, so mirror the focused-control
-- bridge used by assistant_context_alignment_regression.lua. This keeps the
-- audit on the real Assistant navigation path without treating a missing UI
-- harness dependency as a product failure.
local openedControl
_G.MSUF_OpenExactSettingControl = function(settingKey, label, page)
    openedControl = { settingKey = settingKey, label = label, page = page }
    return true, "Opened " .. tostring(label) .. " and focused its exact control."
end

local prompts = {
    "ich brauche hilfe",
    "hilfe",
    "hilf mir",
    "was ist msuf",
    "style module",
    "was kann der assistent",
    "welche befehle gibt es",
    "kannst du mit wow helfen",
    "wie werde ich besser in wow",
    "combat timer help",
    "totem frame help",
    "combat crosshair help",
    "display recovery help",
    "what is gcd",
    "what is global cooldown",
    "interrupt help",
    "how do i make interrupts easier to see",
    "i cant see interrupts",
    "my focus kick tracker is missing",
    "mouseover healing help",
    "click casting help",
    "what are nameplates",
    "can msuf change nameplates",
    "what are unit frames",
    "can msuf change unit frames",
    "what are party frames",
    "what are raid frames",
    "what is a boss frame",
    "what are auras",
    "what are buffs and debuffs",
    "what is a health bar",
    "what is a power bar",
    "what are class resources",
    "what are ready checks",
    "what are raid markers",
    "what are absorbs",
    "what are incoming heals",
    "what is alpha",
    "what does opacity mean",
    "what is an anchor point",
    "what is x offset",
    "what is scaling",
    "what is a bar texture",
    "what is font outline",
    "what is cooldown swipe",
    "what is stack text",
    "what is growth direction",
    "what does click-through mean",
    "what is focus target",
    "what is target of target",
    "range check help",
    "what is dispel",
    "dispellable debuffs help",
    "dispellable debuffs are hard to see",
    "i cant see dispels on raid frames",
    "what is threat",
    "aggro help",
    "i cant see aggro in party frames",
    "i cant see ready checks",
    "raid markers are missing",
    "boss casts are hard to see",
    "my class resources are missing",
    "combo points are gone",
    "combat timer not showing",
    "totem frame is gone",
    "totems not showing",
    "crosshair is missing",
    "target sound not working",
    "alternative mana is missing",
    "alt mana not showing",
    "minimap icon is missing",
    "tooltips not showing",
    "blizzard frames are still visible",
    "blizzard player frame still shows",
    "menu language is wrong",
    "welcome message keeps showing",
    "version popup keeps showing",
    "snap menu to screen",
    "i cannot move frames",
    "how do i move frames",
    "grid not showing in edit mode",
    "snap is not working in edit mode",
    "previews not showing in edit mode",
    "my settings are gone after reload",
    "profile string invalid",
    "export my profile",
    "profile backup help",
    "copy my current profile",
    "profile switch not working",
    "restore old profile",
    "raid frames are in the wrong order",
    "raid frames are in one column",
    "party frames grow the wrong way",
    "raid frames are too far apart",
    "click casting not working",
    "raid frames are not clickable",
    "raid frames too faded",
    "blizzard party frames show instead",
    "target cast bar is in the wrong place",
    "castbar not moving",
    "castbar preview not working",
    "castbar icon is missing",
    "target debuffs are on wrong side",
    "buffs grow the wrong way",
    "buff filter not working",
    "blacklist spell not working",
    "only my buffs are showing",
    "aura cooldown text missing",
    "aura stack text missing",
    "health text shows wrong format",
    "player health text is missing",
    "target power bar wrong place",
    "power bar is missing",
    "class resources wrong position",
    "class resources not moving",
    "combo points wrong color",
    "class resources preview not working",
    "combat timer wrong position",
    "combat timer not moving",
    "crosshair wrong color",
    "combat crosshair wrong size",
    "totem icons wrong position",
    "player frame wrong position",
    "target frame not moving",
    "focus frame wrong size",
    "boss frames wrong position",
    "target frame too faded",
    "player portrait is missing",
    "target portrait wrong style",
    "portrait is wrong",
    "raid marker wrong position",
    "role icon wrong position",
    "ready check icon wrong position",
    "leader icon missing",
    "resting icon missing",
    "pvp icon wrong position",
    "assistant is not answering",
    "assistant does not understand me",
    "assistant keeps giving search results",
    "assistant answered in german",
    "assistant output is too long",
    "chat box is too small",
    "menu is off screen",
    "menu search not working",
    "search results are wrong",
    "where is search",
    "undo not working",
    "redo not working",
    "how do i undo a change",
    "assistant history is missing",
    "support link not working",
    "discord link not working",
    "factory reset scares me",
    "i reset everything by accident",
    "run checks not working",
    "my profile changed after switching spec",
    "frames reset after relog",
    "combat lockdown help",
    "interface kaputt",
    "ui ist kaputt",
    "unitframes weg",
    "unit frames not shown",
    "unitframes not shown",
    "my frames are gone",
    "my unit frames vanished",
    "all frames disappeared",
    "frames are missing",
    "frames not showing",
    "meine frames sind weg",
    "warum werden meine frames nicht angezeigt",
    "settings disappeared",
    "settings are gone",
    "options are gone",
    "everything is gone",
    "everything vanished",
    "alles ist weg",
    "my text is too small",
    "player name too small",
    "party frames too small",
    "make my raid frames easier to read",
    "make party frames easier to read",
    "raid frames are too busy",
    "party frames are hard to understand",
    "target castbar too small",
    "make cast bars easier to see",
    "make boss casts easier to track",
    "auras are too small",
    "buff icons overlap",
    "make target buffs easier to read",
    "my target debuffs are too busy",
    "ui is too tiny",
    "make everything more readable",
    "text is hard to read",
    "make player text easier to read",
    "make health text cleaner",
    "text zu klein",
    "auren ueberlappen",
    "castbar zu klein",
    "i cannot see my frames",
    "i cannot see target frame",
    "ich sehe ziel frame nicht",
    "frames are too transparent",
    "party frames too transparent",
    "castbar color is wrong",
    "auras are too faded",
    "class colors are wrong",
    "text has no contrast",
    "farben sind falsch",
    "text kontrast schlecht",
    "where are group auras",
    "group auras help",
    "what can i change in group auras",
    "group text help",
    "group health and text help",
    "what can i change in group health and text",
    "what can i change in group indicators",
    "what can i change in target buffs",
    "what can i change in target debuffs",
    "where can i change profiles",
    "where can i change colors",
    "where can i change group health and text",
    "where can i change aura filters",
    "where can i change target buffs",
    "where can i change target health text",
    "which page has profile export",
    "which page has raid ready check icons",
    "how do i change profiles",
    "how do i set target buffs",
    "how do i change target debuffs",
    "how do i change target health text",
    "how do i change castbar interrupt color",
    "which menu has profile export",
    "which menu has raid ready check icons",
    "what menu has target buffs",
    "where should i go to change profiles",
    "where do i manage target buffs",
    "what controls castbar interrupt color",
    "what option changes target health text",
    "what setting controls target powerbar offset",
    "tell me where profile export is",
    "show me profile options",
    "show me target buff options",
    "show me target debuff options",
    "list profile options",
    "list raid ready check options",
    "list castbar interrupt color options",
    "explain where profile export is",
    "i want to change profiles",
    "i want profile export options",
    "i want to change target buffs",
    "i want to adjust target debuffs",
    "i want to configure raid ready check icons",
    "i want to change castbar interrupt colors",
    "i want to change target health text",
    "i need profile options",
    "i need target buff options",
    "i need raid ready check options",
    "i need castbar interrupt color options",
    "help me find target buffs",
    "help me find profile export",
    "help me locate raid ready checks",
    "help me locate target powerbar offset",
    "i want to change target width to 300",
    "i am trying to change target buffs",
    "i'm trying to change target debuffs",
    "im trying to configure raid ready check icons",
    "i am looking for profile export",
    "i'm looking for target buff options",
    "im looking for raid ready checks",
    "i need help with target buffs",
    "i need help with profile export",
    "i am trying to change target width to 300",
    "where are target buff options",
    "where are target debuff options",
    "where are modules",
    "modules help",
    "what can i change in modules",
    "what can i change in profiles",
    "what can i change in colors",
    "what can i change in fonts",
    "what can i change in gameplay",
    "what can i change in player frame",
    "dashboard scaling help",
    "where is dashboard scaling",
    "where is display recovery",
    "where are support links",
    "where is changelog",
    "help me set up my UI",
    "help me configure my frames",
    "i am new to unit frames",
    "what should i do first",
    "what should i change first",
    "recommend settings for healer",
    "what should i change as healer",
    "make my ui better for healer",
    "i mainly heal",
    "recommend settings for tank",
    "tank ui setup",
    "i play tank",
    "recommend settings for dps",
    "dps ui recommendations",
    "mythic plus ui setup",
    "i mostly do mythic plus",
    "make my ui better for mythic plus",
    "raid ui setup",
    "i mostly raid",
    "pvp interface recommendations",
    "make my ui better for pvp",
    "solo ui setup",
    "i mostly play solo",
    "healer mythic plus setup",
    "tank raid ui setup",
    "dps mythic plus ui",
    "pvp healer setup",
    "i play rogue",
    "rogue ui setup",
    "shaman ui setup",
    "i play restoration druid",
    "holy paladin setup",
    "fire mage ui setup",
    "warlock class resources",
    "death knight ui setup",
    "evoker ui setup",
    "make my ui better",
    "make my UI cleaner",
    "can you fix it",
    "fix it",
    "please fix this",
    "that did not work",
    "that didn't work",
    "it still does not work",
    "still broken",
    "what now",
    "what should i do now",
    "where should i start",
    "i am confused",
    "i dont understand",
    "explain it simpler",
    "explain that",
    "which one is safer",
    "which one should i use",
    "which one should i pick",
    "which option should i choose",
    "choose the best one",
    "do what you recommend",
    "explain like im new",
    "why would i change this",
    "is this safe",
    "will this break my profile",
    "i dont know what to choose",
    "can you undo later",
    "which settings are risky",
    "what changes are reversible",
    "apply safe defaults",
    "fix my ui automatically",
    "give me a checklist",
    "what should i check first",
    "can you diagnose my ui",
    "make this less cluttered",
    "hide useless buffs",
    "show important debuffs",
    "optimize my ui for mythic plus",
    "i want a healer ui",
    "i want a minimal ui",
    "make target important",
    "backup before changes",
    "how do i make a backup",
    "party frames vs raid frames",
    "should i use party or raid frames",
    "aura filters vs aura layout",
    "which frame should show debuffs",
    "i only want important info",
    "reduce aura spam",
    "can you explain your recommendation",
    "do the first safe step",
    "class resources vs power bar",
    "cast bar vs focus kick tracker",
    "target of target vs focus target",
    "boss frames vs target frame",
    "raid markers vs role icons",
    "absorb bar vs heal prediction",
    "font outline vs font shadow",
    "cooldown swipe vs cooldown text",
    "growth direction vs anchor",
    "menu scale vs ui scale",
    "profile copy vs profile export",
    "reset profile vs factory reset",
    "edit mode vs unlock frames",
    "blizzard frames vs msuf frames",
    "unit frames vs group frames",
    "dispellable debuffs vs all debuffs",
    "what should healers track",
    "what should tanks track",
    "why use target of target",
    "why use aura filters",
    "why is target buffs disabled",
    "what affects target buffs",
    "what depends on target buffs",
    "explain dependencies for target buffs",
    "open the right page",
    "show me where",
    "take me there",
    "do the safe thing",
    "choose for me",
    "explain option 1",
    "open option 1",
    "open that",
    "what does option 1 do",
    "why did that fail",
    "undo that",
    "revert that",
    "revert last change",
    "put it back",
    "restore previous",
    "that was wrong",
    "wrong change",
    "i changed the wrong thing",
    "i do not like that",
    "cancel that change",
    "nevermind undo",
    "mach das rueckgaengig",
    "rueckgaengig machen",
    "das war falsch",
    "falsche aenderung",
    "was hast du geaendert",
    "what did you just do",
    "show last change",
    "redo that",
    "do it again",
    "restore undone change",
    "ziel buffs weg",
    "ziel buffs nicht angezeigt",
    "ziel buffs werden nicht angezeigt",
    "ziel buffs versteckt",
    "ziel buffs ausgeblendet",
    "ziel buffs verschwunden",
    "target buffs not displayed",
    "target buffs not shown",
    "spieler buffs weg",
    "fokus buffs weg",
    "boss buffs weg",
    "party buffs weg",
    "raid buffs weg",
    "mythic raid buffs weg",
    "party frames weg",
    "party frames versteckt",
    "raid frames weg",
    "raid frames ausgeblendet",
    "boss frames weg",
    "fokus frame weg",
    "ziel des ziels frame weg",
    "ziel castbar weg",
    "ziel castbar wird nicht angezeigt",
    "spieler castbar weg",
    "fokus castbar weg",
    "boss castbar weg",
    "spieler frame unsichtbar",
    "spieler frame wird nicht angezeigt",
    "player frame not shown",
    "profile kaputt",
    "profile disappeared",
    "profile missing",
    "mein profil ist weg",
    "profil fehlt",
    "import kaputt",
    "import geht nicht",
    "profile import not working",
    "ich finde auren nicht",
    "wo sind castbars",
    "öffne auren",
    "öffne profile",
    "öffne castbars",
    "zeige mir alles",
    "zeige mir hilfe",
    "zeig mir befehle",
    "normal reden",
    "wie chatgpt",
    "how close are you to chatgpt ingame",
    "what are your limits",
    "was kannst du nicht",
    "erzaehl mir einen witz",
    "erzähl mir einen witz",
    "danke",
    "nein",
    "abbrechen",
}

local germanTerms = {
    "zeige", "anzeigen", "oeffne", "öffne", "waehle", "wähle", "einstellungen",
    "assistent", "zurueck", "zurück", "rueck", "nicht", "keine", "bitte",
    "abbrechen", "anwenden", "ausfuehren", "ausführen", "loeschen", "löschen",
    "kopiere", "verschiebe", "groesse", "größe", "hoehe", "höhe", "breite",
    "kampf", "kaputt", "hilfe", "befehle", "kannst", "erzähle", "erzaehl",
    "ziel", "spieler", "rahmen", "auren",
}

local badPhrases = {
    "- create/switch/copy/delete/rename:",
    "- import/export:",
}

local internalLabels = {
    "Auras3",
    "Opt castbar",
    "Opt bars",
    "Opt colors",
    "Opt fonts",
    "Opt misc",
    "Classpower",
    "Gf ",
    "Uf_",
}

local function normalizedWords(text)
    return " " .. tostring(text or ""):lower():gsub("[%p%c]", " "):gsub("%s+", " ") .. " "
end

local function checkDuplicateChoiceLabels(label, output)
    local seen = {}
    for line in tostring(output or ""):gmatch("[^\n]+") do
        local index, choice = line:match("^%s*(%d+)%.%s*(.-)%s*$")
        if index and choice and index ~= "0" then
            local key = choice:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
            if key ~= "" then
                if seen[key] then
                    failures[#failures + 1] = label .. " contains duplicate choice label " .. choice .. ": " .. tostring(output or "")
                end
                seen[key] = true
            end
        end
    end
end

local expectedContains = {
    ["unit frames not shown"] = "Troubleshooting help",
    ["unitframes not shown"] = "Troubleshooting help",
    ["combat timer help"] = "Combat Timer help",
    ["totem frame help"] = "Totem Frame help",
    ["combat crosshair help"] = "Combat Crosshair help",
    ["display recovery help"] = "Display & Recovery help",
    ["what is gcd"] = "Global cooldown help",
    ["what is global cooldown"] = "Global cooldown help",
    ["interrupt help"] = "Interrupt help",
    ["how do i make interrupts easier to see"] = "Interrupt help",
    ["i cant see interrupts"] = "Interrupt visibility help",
    ["my focus kick tracker is missing"] = "Focus Kick Tracker visibility help",
    ["mouseover healing help"] = "Mouseover and click casting help",
    ["click casting help"] = "Mouseover and click casting help",
    ["what are nameplates"] = "Nameplates help",
    ["can msuf change nameplates"] = "Nameplates help",
    ["what are unit frames"] = "Unit Frames help",
    ["can msuf change unit frames"] = "Unit Frames help",
    ["what are party frames"] = "Party and raid frame help",
    ["what are raid frames"] = "Party and raid frame help",
    ["what is a boss frame"] = "Boss Frames help",
    ["what are auras"] = "Auras, buffs, and debuffs help",
    ["what are buffs and debuffs"] = "Auras, buffs, and debuffs help",
    ["what is a health bar"] = "Health Bar help",
    ["what is a power bar"] = "Power Bar help",
    ["what are class resources"] = "Class Resources help",
    ["what are ready checks"] = "Ready Check help",
    ["what are raid markers"] = "Raid Marker help",
    ["what are absorbs"] = "Absorb and shield help",
    ["what are incoming heals"] = "Incoming Heal and Heal Prediction help",
    ["what is alpha"] = "Alpha and opacity help",
    ["what does opacity mean"] = "Alpha and opacity help",
    ["what is an anchor point"] = "Anchoring help",
    ["what is x offset"] = "Offset help",
    ["what is scaling"] = "Scale help",
    ["what is a bar texture"] = "Texture help",
    ["what is font outline"] = "Font rendering help",
    ["what is cooldown swipe"] = "Cooldown display help",
    ["what is stack text"] = "Aura stack help",
    ["what is growth direction"] = "Growth direction help",
    ["what does click-through mean"] = "Click-through and lock help",
    ["what is focus target"] = "Focus Target help",
    ["what is target of target"] = "Target of Target help",
    ["range check help"] = "Range check help",
    ["what is dispel"] = "Dispel help",
    ["dispellable debuffs help"] = "Dispel help",
    ["dispellable debuffs are hard to see"] = "Dispel visibility help",
    ["i cant see dispels on raid frames"] = "Dispel visibility help",
    ["what is threat"] = "Threat and aggro help",
    ["aggro help"] = "Threat and aggro help",
    ["i cant see aggro in party frames"] = "Threat and aggro visibility help",
    ["i cant see ready checks"] = "Ready Check visibility help",
    ["raid markers are missing"] = "Raid Marker visibility help",
    ["boss casts are hard to see"] = "Cast bar readability help",
    ["my class resources are missing"] = "Class Resources diagnostic",
    ["combo points are gone"] = "Class Resources diagnostic",
    ["combat timer not showing"] = "Gameplay feature check",
    ["totem frame is gone"] = "Totem Frame",
    ["totems not showing"] = "Totem Frame",
    ["crosshair is missing"] = "Combat Crosshair",
    ["target sound not working"] = "Target sound help",
    ["alternative mana is missing"] = "Class Resources diagnostic",
    ["alt mana not showing"] = "Class Resources diagnostic",
    ["minimap icon is missing"] = "MSUF Minimap Icon",
    ["tooltips not showing"] = "Show Unit Frame Tooltips",
    ["blizzard frames are still visible"] = "Blizzard Unit Frames",
    ["blizzard player frame still shows"] = "Fully Hide Blizzard PlayerFrame",
    ["menu language is wrong"] = "Menu language help",
    ["welcome message keeps showing"] = "Welcome Message",
    ["version popup keeps showing"] = "Peer Version Check",
    ["snap menu to screen"] = "Menu Edge Snap",
    ["i cannot move frames"] = "Edit Mode troubleshooting help",
    ["how do i move frames"] = "Edit Mode help",
    ["grid not showing in edit mode"] = "Edit Mode grid help",
    ["snap is not working in edit mode"] = "Edit Mode snap help",
    ["previews not showing in edit mode"] = "Edit Mode Preview",
    ["my settings are gone after reload"] = "Profile storage help",
    ["profile string invalid"] = "Profile import help",
    ["export my profile"] = "Profile backup and export help",
    ["profile backup help"] = "Profile backup and export help",
    ["copy my current profile"] = "Profile copy help",
    ["profile switch not working"] = "Specialization profile help",
    ["restore old profile"] = "Profile recovery help",
    ["raid frames are in the wrong order"] = "Group sorting help",
    ["raid frames are in one column"] = "Group columns help",
    ["party frames grow the wrong way"] = "Group spacing and growth help",
    ["raid frames are too far apart"] = "Group spacing and growth help",
    ["click casting not working"] = "Mouseover and click casting help",
    ["raid frames are not clickable"] = "Mouseover and click casting help",
    ["raid frames too faded"] = "Group range fade help",
    ["blizzard party frames show instead"] = "Blizzard group-frame fallback help",
    ["target cast bar is in the wrong place"] = "Cast bar position help",
    ["castbar not moving"] = "Cast bar position help",
    ["castbar preview not working"] = "Cast bar preview help",
    ["castbar icon is missing"] = "Cast bar text and icon help",
    ["target debuffs are on wrong side"] = "Aura layout help",
    ["buffs grow the wrong way"] = "Aura layout help",
    ["buff filter not working"] = "Aura filter help",
    ["blacklist spell not working"] = "Aura filter help",
    ["only my buffs are showing"] = "Aura filter help",
    ["aura cooldown text missing"] = "Aura text visibility help",
    ["aura stack text missing"] = "Aura text visibility help",
    ["health text shows wrong format"] = "Text format help",
    ["player health text is missing"] = "Text visibility help",
    ["target power bar wrong place"] = "Power bar position help",
    ["power bar is missing"] = "Power bar visibility help",
    ["class resources wrong position"] = "Class Resources position help",
    ["class resources not moving"] = "Class Resources position help",
    ["combo points wrong color"] = "Which Rogue / Feral Druid Combo Points color",
    ["class resources preview not working"] = "Class Resources preview help",
    ["combat timer wrong position"] = "Combat Timer position help",
    ["combat timer not moving"] = "Combat Timer position help",
    ["crosshair wrong color"] = "Combat Crosshair color help",
    ["combat crosshair wrong size"] = "Combat Crosshair size help",
    ["totem icons wrong position"] = "Totem Frame position help",
    ["player frame wrong position"] = "Unit frame position help",
    ["target frame not moving"] = "Unit frame position help",
    ["focus frame wrong size"] = "Unit frame size help",
    ["boss frames wrong position"] = "Unit frame position help",
    ["target frame too faded"] = "Unit frame color and opacity help",
    ["player portrait is missing"] = "Portrait help",
    ["target portrait wrong style"] = "Portrait help",
    ["portrait is wrong"] = "Portrait help",
    ["raid marker wrong position"] = "Indicator position help",
    ["role icon wrong position"] = "Indicator position help",
    ["ready check icon wrong position"] = "Indicator position help",
    ["leader icon missing"] = "Indicator visibility help",
    ["resting icon missing"] = "Indicator visibility help",
    ["pvp icon wrong position"] = "Indicator position help",
    ["assistant is not answering"] = "Assistant matching help",
    ["assistant does not understand me"] = "Assistant matching help",
    ["assistant keeps giving search results"] = "Menu search help",
    ["assistant answered in german"] = "Assistant language help",
    ["assistant output is too long"] = "Assistant matching help",
    ["chat box is too small"] = "Menu and Assistant size help",
    ["menu is off screen"] = "Menu and Assistant size help",
    ["menu search not working"] = "Menu search help",
    ["search results are wrong"] = "Menu search help",
    ["where is search"] = "Done. Opened Search.",
    ["undo not working"] = "Undo and history help",
    ["redo not working"] = "Undo and history help",
    ["how do i undo a change"] = "Undo and history help",
    ["assistant history is missing"] = "Undo and history help",
    ["support link not working"] = "Support link help",
    ["discord link not working"] = "Support link help",
    ["factory reset scares me"] = "Factory reset and recovery help",
    ["i reset everything by accident"] = "Factory reset and recovery help",
    ["run checks not working"] = "Checks and diagnostics help",
    ["my profile changed after switching spec"] = "Specialization profile help",
    ["frames reset after relog"] = "Profile storage help",
    ["combat lockdown help"] = "Combat lockdown help",
    ["my frames are gone"] = "Troubleshooting help",
    ["my unit frames vanished"] = "Troubleshooting help",
    ["all frames disappeared"] = "Troubleshooting help",
    ["frames are missing"] = "Troubleshooting help",
    ["frames not showing"] = "Troubleshooting help",
    ["meine frames sind weg"] = "Troubleshooting help",
    ["warum werden meine frames nicht angezeigt"] = "Troubleshooting help",
    ["settings disappeared"] = "Troubleshooting help",
    ["settings are gone"] = "Troubleshooting help",
    ["options are gone"] = "Troubleshooting help",
    ["everything is gone"] = "Troubleshooting help",
    ["everything vanished"] = "Troubleshooting help",
    ["alles ist weg"] = "Troubleshooting help",
    ["my text is too small"] = "Text readability help",
    ["player name too small"] = "Text readability help",
    ["party frames too small"] = "Group frame readability help",
    ["make my raid frames easier to read"] = "Group frame readability help",
    ["make party frames easier to read"] = "Group frame readability help",
    ["raid frames are too busy"] = "Group frame readability help",
    ["party frames are hard to understand"] = "Group frame readability help",
    ["target castbar too small"] = "Cast bar readability help",
    ["make cast bars easier to see"] = "Cast bar readability help",
    ["make boss casts easier to track"] = "Cast bar readability help",
    ["auras are too small"] = "Aura readability help",
    ["buff icons overlap"] = "Aura readability help",
    ["make target buffs easier to read"] = "Aura readability help",
    ["my target debuffs are too busy"] = "Aura readability help",
    ["ui is too tiny"] = "Scaling readability help",
    ["make everything more readable"] = "Scaling readability help",
    ["text is hard to read"] = "Text readability help",
    ["make player text easier to read"] = "Text readability help",
    ["make health text cleaner"] = "Text readability help",
    ["text zu klein"] = "Text readability help",
    ["auren ueberlappen"] = "Aura readability help",
    ["castbar zu klein"] = "Cast bar readability help",
    ["i cannot see my frames"] = "Troubleshooting help",
    ["i cannot see target frame"] = "Target frame",
    ["ich sehe ziel frame nicht"] = "Target frame",
    ["frames are too transparent"] = "Frame color and opacity help",
    ["party frames too transparent"] = "Group frame color and opacity help",
    ["castbar color is wrong"] = "Cast bar color help",
    ["auras are too faded"] = "Aura color and opacity help",
    ["class colors are wrong"] = "Color and contrast help",
    ["text has no contrast"] = "Text contrast help",
    ["farben sind falsch"] = "Color and contrast help",
    ["text kontrast schlecht"] = "Text contrast help",
    ["where are group auras"] = "Opened Group Auras",
    ["group auras help"] = "Group Auras help",
    ["what can i change in group auras"] = "Group Auras help",
    ["group text help"] = "Group Layout help",
    ["group health and text help"] = "Group Layout help",
    ["what can i change in group health and text"] = "Group Layout help",
    ["what can i change in group indicators"] = "Group Status & Indicators help",
    ["what can i change in target buffs"] = "Aura Buffs help",
    ["what can i change in target debuffs"] = "Aura Debuffs help",
    ["where can i change profiles"] = "Profiles help",
    ["where can i change colors"] = "Colors help",
    ["where can i change group health and text"] = "Group Layout help",
    ["where can i change aura filters"] = "Aura Filter help",
    ["where can i change target buffs"] = "Aura Buffs help",
    ["where can i change target health text"] = "Unit frame text help",
    ["which page has profile export"] = "Profiles help",
    ["which page has raid ready check icons"] = "Group Status & Indicators help",
    ["how do i change profiles"] = "Profiles help",
    ["how do i set target buffs"] = "Aura Buffs help",
    ["how do i change target debuffs"] = "Aura Debuffs help",
    ["how do i change target health text"] = "Unit frame text help",
    ["how do i change castbar interrupt color"] = "Cast Bar interrupt color help",
    ["which menu has profile export"] = "Profiles help",
    ["which menu has raid ready check icons"] = "Group Status & Indicators help",
    ["what menu has target buffs"] = "Aura Buffs help",
    ["where should i go to change profiles"] = "Profiles help",
    ["where do i manage target buffs"] = "Aura Buffs help",
    ["what controls castbar interrupt color"] = "Cast Bar interrupt color help",
    ["what option changes target health text"] = "Unit frame text help",
    ["what setting controls target powerbar offset"] = "Power Bar offset help",
    ["tell me where profile export is"] = "Profiles help",
    ["show me profile options"] = "Opened Profiles",
    ["show me target buff options"] = "Opened Target and focused Aura Buffs",
    ["show me target debuff options"] = "Opened Target and focused Aura Debuffs",
    ["list profile options"] = "Profiles help",
    ["list raid ready check options"] = "Group Status & Indicators help",
    ["list castbar interrupt color options"] = "Cast Bar interrupt color help",
    ["explain where profile export is"] = "Profiles help",
    ["i want to change profiles"] = "Profiles help",
    ["i want profile export options"] = "Profiles help",
    ["i want to change target buffs"] = "Target Buffs - Target",
    ["i want to adjust target debuffs"] = "Target Debuffs - Target",
    ["i want to configure raid ready check icons"] = "Group Status & Indicators help",
    ["i want to change castbar interrupt colors"] = "Interruptible Cast Color",
    ["i want to change target health text"] = "Target HP Text",
    ["i need profile options"] = "Profiles help",
    ["i need target buff options"] = "Aura Buffs help",
    ["i need raid ready check options"] = "Group Status & Indicators help",
    ["i need castbar interrupt color options"] = "Cast Bar interrupt color help",
    ["help me find target buffs"] = "Aura Buffs help",
    ["help me find profile export"] = "Profiles help",
    ["help me locate raid ready checks"] = "Raid Ready Check Icon",
    ["help me locate target powerbar offset"] = "Power Bar offset help",
    ["i want to change target width to 300"] = "Target Width",
    ["i am trying to change target buffs"] = "Target Buffs - Target",
    ["i'm trying to change target debuffs"] = "Target Debuffs - Target",
    ["im trying to configure raid ready check icons"] = "Group Status & Indicators help",
    ["i am looking for profile export"] = "Profiles help",
    ["i'm looking for target buff options"] = "Aura Buffs help",
    ["im looking for raid ready checks"] = "Group Status & Indicators help",
    ["i need help with target buffs"] = "Aura Buffs help",
    ["i need help with profile export"] = "Profiles help",
    ["i am trying to change target width to 300"] = "Target Width",
    ["where are target buff options"] = "Opened Aura Buffs",
    ["where are target debuff options"] = "Opened Aura Debuffs",
    ["where are modules"] = "Opened Modules",
    ["modules help"] = "Modules help",
    ["what can i change in modules"] = "Modules help",
    ["what can i change in profiles"] = "Profiles help",
    ["what can i change in colors"] = "Colors help",
    ["what can i change in fonts"] = "Fonts help",
    ["what can i change in gameplay"] = "Gameplay help",
    ["what can i change in player frame"] = "Player frame help",
    ["dashboard scaling help"] = "Dashboard scaling help",
    ["where is dashboard scaling"] = "Opened Dashboard scaling tools",
    ["where is display recovery"] = "Opened Dashboard recovery tools",
    ["where are support links"] = "MSUF support links",
    ["where is changelog"] = "Opened Dashboard changelog",
    ["help me set up my UI"] = "native MSUF guided setup",
    ["help me configure my frames"] = "native MSUF guided setup",
    ["i am new to unit frames"] = "native MSUF guided setup",
    ["what should i do first"] = "native MSUF guided setup",
    ["what should i change first"] = "native MSUF guided setup",
    ["recommend settings for healer"] = "Role setup guidance",
    ["what should i change as healer"] = "raid click casting",
    ["make my ui better for healer"] = "raid click casting",
    ["i mainly heal"] = "Role setup guidance",
    ["recommend settings for tank"] = "Role setup guidance",
    ["tank ui setup"] = "Target of Target",
    ["i play tank"] = "Target of Target",
    ["recommend settings for dps"] = "Role setup guidance",
    ["dps ui recommendations"] = "Class Resources",
    ["mythic plus ui setup"] = "Mythic+ and dungeon UI",
    ["i mostly do mythic plus"] = "Mythic+ and dungeon UI",
    ["make my ui better for mythic plus"] = "Mythic+ and dungeon UI",
    ["raid ui setup"] = "Group Layout",
    ["i mostly raid"] = "Group Layout",
    ["pvp interface recommendations"] = "PvP UI",
    ["make my ui better for pvp"] = "PvP UI",
    ["solo ui setup"] = "solo and open-world UI",
    ["i mostly play solo"] = "solo and open-world UI",
    ["healer mythic plus setup"] = "Mythic+ healing",
    ["tank raid ui setup"] = "raid tanking",
    ["dps mythic plus ui"] = "Mythic+ DPS",
    ["pvp healer setup"] = "PvP with this role",
    ["i play rogue"] = "Rogue UI guidance",
    ["rogue ui setup"] = "Rogue UI guidance",
    ["shaman ui setup"] = "Totem/Statue frame",
    ["i play restoration druid"] = "Druid healing UI",
    ["holy paladin setup"] = "Paladin healing UI",
    ["fire mage ui setup"] = "Mage UI guidance",
    ["warlock class resources"] = "Warlock UI guidance",
    ["death knight ui setup"] = "Death Knight UI guidance",
    ["evoker ui setup"] = "Evoker UI guidance",
    ["make my ui better"] = "native MSUF guided setup",
    ["make my UI cleaner"] = "native MSUF guided setup",
    ["can you fix it"] = "Recovery guidance",
    ["fix it"] = "Recovery guidance",
    ["please fix this"] = "Recovery guidance",
    ["that did not work"] = "Recovery guidance",
    ["that didn't work"] = "Recovery guidance",
    ["it still does not work"] = "Recovery guidance",
    ["still broken"] = "Recovery guidance",
    ["what now"] = "I need a little more MSUF context",
    ["what should i do now"] = "I need a little more MSUF context",
    ["where should i start"] = "native MSUF guided setup",
    ["i am confused"] = "Pick a direction:",
    ["i dont understand"] = "I need a little more MSUF context",
    ["explain it simpler"] = "Simple explanation help",
    ["explain that"] = "I need a little more MSUF context",
    ["which one is safer"] = "Selection guidance",
    ["which one should i use"] = "Selection guidance",
    ["which one should i pick"] = "Selection guidance",
    ["which option should i choose"] = "Selection guidance",
    ["choose the best one"] = "Selection guidance",
    ["do what you recommend"] = "Selection guidance",
    ["explain like im new"] = "Simple explanation help",
    ["why would i change this"] = "Simple explanation help",
    ["is this safe"] = "Safety guidance",
    ["will this break my profile"] = "Safety guidance",
    ["i dont know what to choose"] = "Selection guidance",
    ["can you undo later"] = "Safety guidance",
    ["which settings are risky"] = "Safety guidance",
    ["what changes are reversible"] = "Safety guidance",
    ["apply safe defaults"] = "Safe setup planning",
    ["fix my ui automatically"] = "Safe setup planning",
    ["give me a checklist"] = "native MSUF guided setup",
    ["what should i check first"] = "native MSUF guided setup",
    ["can you diagnose my ui"] = "Diagnostic planning",
    ["make this less cluttered"] = "Clutter planning",
    ["hide useless buffs"] = "Aura filter planning",
    ["show important debuffs"] = "Aura filter planning",
    ["optimize my ui for mythic plus"] = "Mythic+ and dungeon UI",
    ["i want a healer ui"] = "Role setup guidance",
    ["i want a minimal ui"] = "Minimal UI planning",
    ["make target important"] = "Priority frame planning",
    ["backup before changes"] = "Profile backup planning",
    ["how do i make a backup"] = "Profile backup planning",
    ["party frames vs raid frames"] = "Group frame comparison",
    ["should i use party or raid frames"] = "Group frame comparison",
    ["aura filters vs aura layout"] = "Aura system comparison",
    ["which frame should show debuffs"] = "Aura placement planning",
    ["i only want important info"] = "Information density planning",
    ["reduce aura spam"] = "Information density planning",
    ["can you explain your recommendation"] = "Recommendation guidance",
    ["do the first safe step"] = "Recommendation guidance",
    ["class resources vs power bar"] = "Resource bar comparison",
    ["cast bar vs focus kick tracker"] = "Cast bar and kick tracker comparison",
    ["target of target vs focus target"] = "Target-of-target and focus-target comparison",
    ["boss frames vs target frame"] = "Boss and target frame comparison",
    ["raid markers vs role icons"] = "Group indicator comparison",
    ["absorb bar vs heal prediction"] = "Absorb and heal prediction comparison",
    ["font outline vs font shadow"] = "Font outline and shadow comparison",
    ["cooldown swipe vs cooldown text"] = "Aura text and cooldown comparison",
    ["growth direction vs anchor"] = "Positioning option comparison",
    ["menu scale vs ui scale"] = "Scale option comparison",
    ["profile copy vs profile export"] = "Profile action comparison",
    ["reset profile vs factory reset"] = "Profile action comparison",
    ["edit mode vs unlock frames"] = "Edit Mode and unlock comparison",
    ["blizzard frames vs msuf frames"] = "Blizzard and MSUF frame comparison",
    ["unit frames vs group frames"] = "Unit and group frame comparison",
    ["dispellable debuffs vs all debuffs"] = "Aura system comparison",
    ["what should healers track"] = "Healer tracking guidance",
    ["what should tanks track"] = "Tank tracking guidance",
    ["why use target of target"] = "Why Target of Target matters",
    ["why use aura filters"] = "Filters do not move icons or resize them",
    ["why is target buffs disabled"] = "Target Buffs relationships",
    ["what affects target buffs"] = "Can affect:",
    ["what depends on target buffs"] = "Depends on:",
    ["explain dependencies for target buffs"] = "I only inspected current MSUF state",
    ["open the right page"] = "Pick the one you want me to open:",
    ["show me where"] = "I need a little more MSUF context",
    ["take me there"] = "I need a little more MSUF context",
    ["do the safe thing"] = "Selection guidance",
    ["choose for me"] = "Selection guidance",
    ["explain option 1"] = "I need a little more MSUF context",
    ["open option 1"] = "Pick the one you want me to open:",
    ["open that"] = "Pick the one you want me to open:",
    ["what does option 1 do"] = "I need a little more MSUF context",
    ["why did that fail"] = "Recovery guidance",
    ["undo that"] = "I have no Assistant change to undo",
    ["revert that"] = "I have no Assistant change to undo",
    ["revert last change"] = "I have no Assistant change to undo",
    ["put it back"] = "I have no Assistant change to undo",
    ["restore previous"] = "I have no Assistant change to undo",
    ["that was wrong"] = "I have no Assistant change to undo",
    ["wrong change"] = "I have no Assistant change to undo",
    ["i changed the wrong thing"] = "I have no Assistant change to undo",
    ["i do not like that"] = "I have no Assistant change to undo",
    ["cancel that change"] = "I have no Assistant change to undo",
    ["nevermind undo"] = "I have no Assistant change to undo",
    ["mach das rueckgaengig"] = "I have no Assistant change to undo",
    ["rueckgaengig machen"] = "I have no Assistant change to undo",
    ["das war falsch"] = "I have no Assistant change to undo",
    ["falsche aenderung"] = "I have no Assistant change to undo",
    ["was hast du geaendert"] = "I do not have a recorded Assistant change yet",
    ["what did you just do"] = "I do not have a recorded Assistant change yet",
    ["show last change"] = "I do not have a recorded Assistant change yet",
    ["redo that"] = "I have no Assistant change to redo",
    ["do it again"] = "I have no Assistant change to redo",
    ["restore undone change"] = "I have no Assistant change to redo",
    ["ziel buffs weg"] = "Target aura check",
    ["ziel buffs nicht angezeigt"] = "Target aura check",
    ["ziel buffs werden nicht angezeigt"] = "Target aura check",
    ["ziel buffs versteckt"] = "Target aura check",
    ["ziel buffs ausgeblendet"] = "Target aura check",
    ["ziel buffs verschwunden"] = "Target aura check",
    ["target buffs not displayed"] = "Target aura check",
    ["target buffs not shown"] = "Target aura check",
    ["spieler buffs weg"] = "Player aura check",
    ["fokus buffs weg"] = "Focus aura check",
    ["boss buffs weg"] = "Boss aura check",
    ["party buffs weg"] = "Party group aura check",
    ["raid buffs weg"] = "Raid group aura check",
    ["mythic raid buffs weg"] = "Mythic Raid group aura check",
    ["ziel castbar weg"] = "Target cast bar",
    ["ziel castbar wird nicht angezeigt"] = "Target cast bar",
    ["spieler castbar weg"] = "Player cast bar",
    ["fokus castbar weg"] = "Focus cast bar",
    ["boss castbar weg"] = "Boss cast bar",
    ["party frames weg"] = "Party Group Frames",
    ["party frames versteckt"] = "Party Group Frames",
    ["raid frames weg"] = "Raid Group Frames",
    ["raid frames ausgeblendet"] = "Raid Group Frames",
    ["boss frames weg"] = "Boss frames",
    ["fokus frame weg"] = "Focus frame",
    ["ziel des ziels frame weg"] = "Target of Target",
    ["spieler frame unsichtbar"] = "Player frame",
    ["spieler frame wird nicht angezeigt"] = "Player frame",
    ["player frame not shown"] = "Player frame",
    ["profile disappeared"] = "I treated that as a problem report",
    ["profile missing"] = "I treated that as a problem report",
    ["mein profil ist weg"] = "I treated that as a problem report",
    ["profil fehlt"] = "I treated that as a problem report",
    ["import geht nicht"] = "Profile import help",
    ["profile import not working"] = "Profile import help",
}

local rawEchoBlocked = {
    ["ich brauche hilfe"] = true,
    ["hilf mir"] = true,
    ["was kann der assistent"] = true,
    ["welche befehle gibt es"] = true,
    ["kannst du mit wow helfen"] = true,
    ["wie werde ich besser in wow"] = true,
    ["i cant see interrupts"] = true,
    ["my focus kick tracker is missing"] = true,
    ["dispellable debuffs are hard to see"] = true,
    ["i cant see dispels on raid frames"] = true,
    ["i cant see aggro in party frames"] = true,
    ["i cant see ready checks"] = true,
    ["raid markers are missing"] = true,
    ["boss casts are hard to see"] = true,
    ["my class resources are missing"] = true,
    ["combo points are gone"] = true,
    ["combat timer not showing"] = true,
    ["totem frame is gone"] = true,
    ["totems not showing"] = true,
    ["crosshair is missing"] = true,
    ["target sound not working"] = true,
    ["alternative mana is missing"] = true,
    ["alt mana not showing"] = true,
    ["minimap icon is missing"] = true,
    ["tooltips not showing"] = true,
    ["blizzard frames are still visible"] = true,
    ["blizzard player frame still shows"] = true,
    ["menu language is wrong"] = true,
    ["welcome message keeps showing"] = true,
    ["version popup keeps showing"] = true,
    ["snap menu to screen"] = true,
    ["i cannot move frames"] = true,
    ["how do i move frames"] = true,
    ["grid not showing in edit mode"] = true,
    ["snap is not working in edit mode"] = true,
    ["previews not showing in edit mode"] = true,
    ["my settings are gone after reload"] = true,
    ["profile string invalid"] = true,
    ["export my profile"] = true,
    ["profile backup help"] = true,
    ["copy my current profile"] = true,
    ["profile switch not working"] = true,
    ["restore old profile"] = true,
    ["raid frames are in the wrong order"] = true,
    ["raid frames are in one column"] = true,
    ["party frames grow the wrong way"] = true,
    ["raid frames are too far apart"] = true,
    ["click casting not working"] = true,
    ["raid frames are not clickable"] = true,
    ["raid frames too faded"] = true,
    ["blizzard party frames show instead"] = true,
    ["target cast bar is in the wrong place"] = true,
    ["castbar not moving"] = true,
    ["castbar preview not working"] = true,
    ["castbar icon is missing"] = true,
    ["target debuffs are on wrong side"] = true,
    ["buffs grow the wrong way"] = true,
    ["buff filter not working"] = true,
    ["blacklist spell not working"] = true,
    ["only my buffs are showing"] = true,
    ["aura cooldown text missing"] = true,
    ["aura stack text missing"] = true,
    ["health text shows wrong format"] = true,
    ["player health text is missing"] = true,
    ["target power bar wrong place"] = true,
    ["power bar is missing"] = true,
    ["class resources wrong position"] = true,
    ["class resources not moving"] = true,
    ["combo points wrong color"] = true,
    ["class resources preview not working"] = true,
    ["combat timer wrong position"] = true,
    ["combat timer not moving"] = true,
    ["crosshair wrong color"] = true,
    ["combat crosshair wrong size"] = true,
    ["totem icons wrong position"] = true,
    ["player frame wrong position"] = true,
    ["target frame not moving"] = true,
    ["focus frame wrong size"] = true,
    ["boss frames wrong position"] = true,
    ["target frame too faded"] = true,
    ["player portrait is missing"] = true,
    ["target portrait wrong style"] = true,
    ["portrait is wrong"] = true,
    ["raid marker wrong position"] = true,
    ["role icon wrong position"] = true,
    ["ready check icon wrong position"] = true,
    ["leader icon missing"] = true,
    ["resting icon missing"] = true,
    ["pvp icon wrong position"] = true,
    ["assistant is not answering"] = true,
    ["assistant does not understand me"] = true,
    ["assistant keeps giving search results"] = true,
    ["assistant answered in german"] = true,
    ["assistant output is too long"] = true,
    ["chat box is too small"] = true,
    ["menu is off screen"] = true,
    ["menu search not working"] = true,
    ["search results are wrong"] = true,
    ["where is search"] = true,
    ["undo not working"] = true,
    ["redo not working"] = true,
    ["how do i undo a change"] = true,
    ["assistant history is missing"] = true,
    ["support link not working"] = true,
    ["discord link not working"] = true,
    ["factory reset scares me"] = true,
    ["i reset everything by accident"] = true,
    ["run checks not working"] = true,
    ["my profile changed after switching spec"] = true,
    ["frames reset after relog"] = true,
    ["interface kaputt"] = true,
    ["ui ist kaputt"] = true,
    ["unitframes weg"] = true,
    ["unit frames not shown"] = true,
    ["unitframes not shown"] = true,
    ["my frames are gone"] = true,
    ["my unit frames vanished"] = true,
    ["all frames disappeared"] = true,
    ["frames are missing"] = true,
    ["frames not showing"] = true,
    ["meine frames sind weg"] = true,
    ["warum werden meine frames nicht angezeigt"] = true,
    ["settings disappeared"] = true,
    ["settings are gone"] = true,
    ["options are gone"] = true,
    ["everything is gone"] = true,
    ["everything vanished"] = true,
    ["alles ist weg"] = true,
    ["my text is too small"] = true,
    ["player name too small"] = true,
    ["party frames too small"] = true,
    ["make my raid frames easier to read"] = true,
    ["make party frames easier to read"] = true,
    ["raid frames are too busy"] = true,
    ["party frames are hard to understand"] = true,
    ["target castbar too small"] = true,
    ["make cast bars easier to see"] = true,
    ["make boss casts easier to track"] = true,
    ["auras are too small"] = true,
    ["buff icons overlap"] = true,
    ["make target buffs easier to read"] = true,
    ["my target debuffs are too busy"] = true,
    ["ui is too tiny"] = true,
    ["make everything more readable"] = true,
    ["text is hard to read"] = true,
    ["make player text easier to read"] = true,
    ["make health text cleaner"] = true,
    ["text zu klein"] = true,
    ["auren ueberlappen"] = true,
    ["castbar zu klein"] = true,
    ["i cannot see my frames"] = true,
    ["i cannot see target frame"] = true,
    ["ich sehe ziel frame nicht"] = true,
    ["frames are too transparent"] = true,
    ["party frames too transparent"] = true,
    ["castbar color is wrong"] = true,
    ["auras are too faded"] = true,
    ["class colors are wrong"] = true,
    ["text has no contrast"] = true,
    ["farben sind falsch"] = true,
    ["text kontrast schlecht"] = true,
    ["help me set up my UI"] = true,
    ["help me configure my frames"] = true,
    ["i am new to unit frames"] = true,
    ["what should i do first"] = true,
    ["what should i change first"] = true,
    ["recommend settings for healer"] = true,
    ["make my ui better for healer"] = true,
    ["i mainly heal"] = true,
    ["recommend settings for tank"] = true,
    ["i play tank"] = true,
    ["recommend settings for dps"] = true,
    ["mythic plus ui setup"] = true,
    ["i mostly do mythic plus"] = true,
    ["make my ui better for mythic plus"] = true,
    ["raid ui setup"] = true,
    ["i mostly raid"] = true,
    ["pvp interface recommendations"] = true,
    ["make my ui better for pvp"] = true,
    ["solo ui setup"] = true,
    ["i mostly play solo"] = true,
    ["healer mythic plus setup"] = true,
    ["tank raid ui setup"] = true,
    ["dps mythic plus ui"] = true,
    ["pvp healer setup"] = true,
    ["i play rogue"] = true,
    ["rogue ui setup"] = true,
    ["shaman ui setup"] = true,
    ["i play restoration druid"] = true,
    ["holy paladin setup"] = true,
    ["fire mage ui setup"] = true,
    ["warlock class resources"] = true,
    ["death knight ui setup"] = true,
    ["evoker ui setup"] = true,
    ["make my ui better"] = true,
    ["make my UI cleaner"] = true,
    ["can you fix it"] = true,
    ["fix it"] = true,
    ["please fix this"] = true,
    ["that did not work"] = true,
    ["that didn't work"] = true,
    ["it still does not work"] = true,
    ["still broken"] = true,
    ["what now"] = true,
    ["what should i do now"] = true,
    ["where should i start"] = true,
    ["i am confused"] = true,
    ["i dont understand"] = true,
    ["explain it simpler"] = true,
    ["explain that"] = true,
    ["which one is safer"] = true,
    ["which one should i use"] = true,
    ["which one should i pick"] = true,
    ["which option should i choose"] = true,
    ["choose the best one"] = true,
    ["do what you recommend"] = true,
    ["explain like im new"] = true,
    ["why would i change this"] = true,
    ["is this safe"] = true,
    ["will this break my profile"] = true,
    ["i dont know what to choose"] = true,
    ["can you undo later"] = true,
    ["which settings are risky"] = true,
    ["what changes are reversible"] = true,
    ["apply safe defaults"] = true,
    ["fix my ui automatically"] = true,
    ["give me a checklist"] = true,
    ["what should i check first"] = true,
    ["can you diagnose my ui"] = true,
    ["make this less cluttered"] = true,
    ["hide useless buffs"] = true,
    ["show important debuffs"] = true,
    ["optimize my ui for mythic plus"] = true,
    ["i want a healer ui"] = true,
    ["i want a minimal ui"] = true,
    ["make target important"] = true,
    ["backup before changes"] = true,
    ["how do i make a backup"] = true,
    ["party frames vs raid frames"] = true,
    ["should i use party or raid frames"] = true,
    ["aura filters vs aura layout"] = true,
    ["which frame should show debuffs"] = true,
    ["i only want important info"] = true,
    ["reduce aura spam"] = true,
    ["can you explain your recommendation"] = true,
    ["do the first safe step"] = true,
    ["class resources vs power bar"] = true,
    ["cast bar vs focus kick tracker"] = true,
    ["target of target vs focus target"] = true,
    ["boss frames vs target frame"] = true,
    ["raid markers vs role icons"] = true,
    ["absorb bar vs heal prediction"] = true,
    ["font outline vs font shadow"] = true,
    ["cooldown swipe vs cooldown text"] = true,
    ["growth direction vs anchor"] = true,
    ["menu scale vs ui scale"] = true,
    ["profile copy vs profile export"] = true,
    ["reset profile vs factory reset"] = true,
    ["edit mode vs unlock frames"] = true,
    ["blizzard frames vs msuf frames"] = true,
    ["unit frames vs group frames"] = true,
    ["dispellable debuffs vs all debuffs"] = true,
    ["what should healers track"] = true,
    ["what should tanks track"] = true,
    ["why use target of target"] = true,
    ["why use aura filters"] = true,
    ["why is target buffs disabled"] = true,
    ["what affects target buffs"] = true,
    ["what depends on target buffs"] = true,
    ["explain dependencies for target buffs"] = true,
    ["open the right page"] = true,
    ["show me where"] = true,
    ["take me there"] = true,
    ["do the safe thing"] = true,
    ["choose for me"] = true,
    ["explain option 1"] = true,
    ["open option 1"] = true,
    ["open that"] = true,
    ["what does option 1 do"] = true,
    ["why did that fail"] = true,
    ["undo that"] = true,
    ["revert that"] = true,
    ["revert last change"] = true,
    ["put it back"] = true,
    ["restore previous"] = true,
    ["that was wrong"] = true,
    ["wrong change"] = true,
    ["i changed the wrong thing"] = true,
    ["i do not like that"] = true,
    ["cancel that change"] = true,
    ["nevermind undo"] = true,
    ["mach das rueckgaengig"] = true,
    ["rueckgaengig machen"] = true,
    ["das war falsch"] = true,
    ["falsche aenderung"] = true,
    ["was hast du geaendert"] = true,
    ["what did you just do"] = true,
    ["show last change"] = true,
    ["redo that"] = true,
    ["do it again"] = true,
    ["restore undone change"] = true,
    ["ziel buffs weg"] = true,
    ["ziel buffs nicht angezeigt"] = true,
    ["ziel buffs werden nicht angezeigt"] = true,
    ["ziel buffs versteckt"] = true,
    ["ziel buffs ausgeblendet"] = true,
    ["ziel buffs verschwunden"] = true,
    ["target buffs not displayed"] = true,
    ["target buffs not shown"] = true,
    ["spieler buffs weg"] = true,
    ["fokus buffs weg"] = true,
    ["boss buffs weg"] = true,
    ["party buffs weg"] = true,
    ["raid buffs weg"] = true,
    ["mythic raid buffs weg"] = true,
    ["party frames weg"] = true,
    ["party frames versteckt"] = true,
    ["raid frames weg"] = true,
    ["raid frames ausgeblendet"] = true,
    ["boss frames weg"] = true,
    ["fokus frame weg"] = true,
    ["ziel des ziels frame weg"] = true,
    ["ziel castbar weg"] = true,
    ["ziel castbar wird nicht angezeigt"] = true,
    ["spieler castbar weg"] = true,
    ["fokus castbar weg"] = true,
    ["boss castbar weg"] = true,
    ["spieler frame unsichtbar"] = true,
    ["spieler frame wird nicht angezeigt"] = true,
    ["player frame not shown"] = true,
    ["profile disappeared"] = true,
    ["profile missing"] = true,
    ["mein profil ist weg"] = true,
    ["profil fehlt"] = true,
    ["import kaputt"] = true,
    ["import geht nicht"] = true,
    ["profile import not working"] = true,
    ["ich finde auren nicht"] = true,
    ["zeige mir alles"] = true,
    ["zeige mir hilfe"] = true,
    ["zeig mir befehle"] = true,
    ["normal reden"] = true,
    ["wie chatgpt"] = true,
    ["how close are you to chatgpt ingame"] = true,
    ["what are your limits"] = true,
    ["was kannst du nicht"] = true,
    ["erzaehl mir einen witz"] = true,
    ["erzÃ¤hl mir einen witz"] = true,
}

local failures = {}
local function check(label, output, input)
    output = tostring(output or "")
    local hay = normalizedWords(output)
    for _, term in ipairs(germanTerms) do
        if hay:find(" " .. tostring(term):lower() .. " ", 1, true) then
            failures[#failures + 1] = label .. " contains German term " .. term .. ": " .. output
        end
    end
    for _, phrase in ipairs(badPhrases) do
        if output:find(phrase, 1, true) then
            failures[#failures + 1] = label .. " contains bad visible phrase " .. phrase .. ": " .. output
        end
    end
    for _, labelText in ipairs(internalLabels) do
        if output:find(labelText, 1, true) then
            failures[#failures + 1] = label .. " contains internal page label " .. labelText .. ": " .. output
        end
    end
    checkDuplicateChoiceLabels(label, output)
    local lower = output:lower()
    if input and rawEchoBlocked[input] and input ~= "" and lower:find(tostring(input):lower(), 1, true) then
        failures[#failures + 1] = label .. " repeats raw input: " .. output
    end
end

local pendingMirrorFields = {
    "pendingCandidates",
    "pendingChoices",
    "pendingResults",
    "pendingSelectedResult",
    "pendingConfirmation",
    "pendingFlow",
}

local function clearTable(tbl)
    if type(tbl) ~= "table" then return end
    for key in pairs(tbl) do tbl[key] = nil end
end

local function clearPendingMirrors()
    local ctx = A.GetContext and A.GetContext() or nil
    for i = 1, #pendingMirrorFields do
        local field = pendingMirrorFields[i]
        A[field] = nil
        if type(ctx) == "table" then ctx[field] = nil end
        if type(A.context) == "table" then A.context[field] = nil end
    end
end

local function assertNoPendingMirrors(label)
    local ctx = A.GetContext and A.GetContext() or nil
    for i = 1, #pendingMirrorFields do
        local field = pendingMirrorFields[i]
        assert(A[field] == nil, label .. " left Assistant." .. field .. " populated")
        assert(type(ctx) ~= "table" or ctx[field] == nil, label .. " left saved context." .. field .. " populated")
        assert(type(A.context) ~= "table" or A.context[field] == nil, label .. " left fallback context." .. field .. " populated")
    end
end

local function reset()
    if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() else A.largeTextPanel = nil end
    clearPendingMirrors()

    -- GetContext is the persisted conversation mirror. Every key in it is
    -- conversational/session state; retaining only a subset makes independent
    -- prompts inherit old subjects, planning replies, or guided flows.
    local ctx = A.GetContext and A.GetContext() or nil
    clearTable(ctx)
    if type(A.context) == "table" and A.context ~= ctx then clearTable(A.context) end

    A.lastAssistantHelpContext = nil
    A.lastAssistantPlanningContext = nil
    A._pendingResultFollowupHandled = nil
    A._lastNoMatch = nil
    A.undoNextFramePending = nil
    A.undoStack = {}
    A.redoStack = {}
    assertNoPendingMirrors("reset")
end

local function clearPendingOnly()
    clearPendingMirrors()
    A._pendingResultFollowupHandled = nil
    assertNoPendingMirrors("clearPendingOnly")
end

for _, input in ipairs(prompts) do
    reset()
    local result = A.Submit(input)
    local text = result and result.text or ""
    check(input, text, input)
    local expected = expectedContains[input]
    if expected and not tostring(text or ""):find(expected, 1, true) then
        failures[#failures + 1] = string.format(
            "%s missing expected text %q: %q",
            input,
            tostring(expected),
            tostring(text or "")
        )
    end
    local panel = A.largeTextPanel
    if type(panel) == "table" then
        check(input .. " panel title", panel.title, input)
        check(input .. " panel help", panel.help, input)
        check(input .. " panel status", panel.status, input)
        check(input .. " panel text", panel.text, input)
    end
    if verbose then
        print(input .. " => " .. tostring(result and (result.status or result.result) or "nil") .. " | " .. tostring(text):gsub("\n", " | "))
    end
end

local function expectSequenceContains(label, result, expected)
    local text = result and result.text or ""
    check(label, text, nil)
    if not tostring(text or ""):find(expected, 1, true) then
        failures[#failures + 1] = string.format(
            "%s missing expected text %q: %q",
            label,
            tostring(expected),
            tostring(text or "")
        )
    end
    if verbose then
        print(label .. " => " .. tostring(result and (result.status or result.result) or "nil") .. " | " .. tostring(text):gsub("\n", " | "))
    end
end

local function expectReadOnlyBooleanPrompt(label, input, settingKey, baseline)
    local setting = assert(A.Registry:GetSetting(settingKey), "missing read-only probe setting " .. tostring(settingKey))
    local original = setting.get()
    assert(setting.set(baseline) ~= false, "could not establish read-only probe baseline for " .. tostring(settingKey))
    reset()

    local before = setting.get()
    local result = A.Submit(input)
    local after = setting.get()
    local status = result and (result.status or result.result) or nil
    if before ~= after then
        failures[#failures + 1] = string.format(
            "%s mutated %s from %s to %s: %q",
            label,
            settingKey,
            tostring(before),
            tostring(after),
            tostring(result and result.text or "")
        )
    end
    if status == "applied" or status == "changed" then
        failures[#failures + 1] = string.format(
            "%s returned mutating status %s for a problem report: %q",
            label,
            tostring(status),
            tostring(result and result.text or "")
        )
    end

    assert(setting.set(original) ~= false, "could not restore read-only probe setting " .. tostring(settingKey))
    reset()
end

-- Regression probes for the highest-risk natural problem wording. These are
-- deliberately checked against a known enabled baseline so a prior prompt
-- cannot turn an unsafe write into an innocent-looking "already set" reply.
expectReadOnlyBooleanPrompt("party buffs missing safety", "party buffs weg", "gf_party.auras.buff.enabled", true)
expectReadOnlyBooleanPrompt("raid buffs missing safety", "raid buffs weg", "gf_raid.auras.buff.enabled", true)
expectReadOnlyBooleanPrompt("mythic raid buffs missing safety", "mythic raid buffs weg", "gf_mythicraid.auras.buff.enabled", true)
expectReadOnlyBooleanPrompt("party frames missing safety", "party frames weg", "gf_party.enabled", true)
expectReadOnlyBooleanPrompt("party frames hidden safety", "party frames versteckt", "gf_party.enabled", true)
expectReadOnlyBooleanPrompt("raid frames missing safety", "raid frames weg", "gf_raid.enabled", true)
expectReadOnlyBooleanPrompt("raid frames hidden safety", "raid frames ausgeblendet", "gf_raid.enabled", true)

reset()
local resultSearch = A.Submit("style module")
expectSequenceContains("search result followup sequence search", resultSearch, "I found these MSUF matches")
local resultCompare = A.Submit("compare result 1 and result 2")
expectSequenceContains("search result followup sequence compare", resultCompare, "Result comparison")
local resultRunSetting = A.Submit("run result 1")
expectSequenceContains("search result followup sequence run setting", resultRunSetting, "will not run it without a concrete value")
local resultExplain = A.Submit("explain result 1")
expectSequenceContains("search result followup sequence explain", resultExplain, "Result 1: MSUF Style Module")
local resultWhy = A.Submit("why this option")
expectSequenceContains("search result followup sequence why", resultWhy, "Why this result matters")
expectSequenceContains("search result followup sequence why selected", resultWhy, "MSUF Style Module")
local resultPronounCompare = A.Submit("compare it with result 2")
expectSequenceContains("search result followup sequence pronoun compare", resultPronounCompare, "Result comparison")
expectSequenceContains("search result followup sequence pronoun compare selected", resultPronounCompare, "Result 1: MSUF Style Module")
local resultPronounCompareShort = A.Submit("compare it with 2")
expectSequenceContains("search result followup sequence pronoun compare short", resultPronounCompareShort, "Result comparison")
expectSequenceContains("search result followup sequence pronoun compare short selected", resultPronounCompareShort, "Result 1: MSUF Style Module")
local resultCurrentValue = A.Submit("what is it set to")
expectSequenceContains("search result followup sequence current value", resultCurrentValue, "Current value: MSUF Style Module is enabled")
local resultSimpleExplain = A.Submit("explain it simpler")
expectSequenceContains("search result followup sequence simple explain", resultSimpleExplain, "Simple explanation")
local resultOpen = A.Submit("open result 1")
expectSequenceContains("search result followup sequence open", resultOpen, "Opened MSUF Style Module")
local resultSelect = A.Submit("result 2")
expectSequenceContains("search result followup sequence select", resultSelect, "Done. Opened")
local resultRelated = A.Submit("related options")
expectSequenceContains("search result followup sequence related options", resultRelated, "Related MSUF options")
expectSequenceContains("search result followup sequence related active results", resultRelated, "These are now the active results")

reset()
local ordinalResultSearch = A.Submit("style module")
expectSequenceContains("search result ordinal sequence search", ordinalResultSearch, "I found these MSUF matches")
local ordinalResultCompare = A.Submit("compare the first one and the second one")
expectSequenceContains("search result ordinal sequence compare", ordinalResultCompare, "Result comparison")
local ordinalResultCompareFirstTwo = A.Submit("compare first two results")
expectSequenceContains("search result ordinal sequence compare first two", ordinalResultCompareFirstTwo, "Result comparison")
local ordinalResultExplain = A.Submit("explain the first one")
expectSequenceContains("search result ordinal sequence explain", ordinalResultExplain, "Result 1: MSUF Style Module")
local ordinalResultOpen = A.Submit("open the second one")
expectSequenceContains("search result ordinal sequence open", ordinalResultOpen, "Done. Opened")

reset()
local compareThemSearch = A.Submit("style module")
expectSequenceContains("search result compare-them sequence search", compareThemSearch, "I found these MSUF matches")
local compareThemResult = A.Submit("compare them")
expectSequenceContains("search result compare-them sequence compare", compareThemResult, "Result comparison")

reset()
local bareExplainSearch = A.Submit("search target buff cooldown text size")
expectSequenceContains("search result bare explain sequence search", bareExplainSearch, "Target Buff Cooldown Text Size")
local bareExplainResult = A.Submit("explain")
expectSequenceContains("search result bare explain sequence explain", bareExplainResult, "Result 1: Target Buff Cooldown Text Size")

reset()
local bareValueSearch = A.Submit("search target buff cooldown text size")
expectSequenceContains("search result bare value sequence search", bareValueSearch, "Target Buff Cooldown Text Size")
local bareValueResult = A.Submit("current value")
expectSequenceContains("search result bare value sequence value", bareValueResult, "Current value: Target Buff Cooldown Text Size")

reset()
local bareOpenSearch = A.Submit("search target buff cooldown text size")
expectSequenceContains("search result bare open sequence search", bareOpenSearch, "Target Buff Cooldown Text Size")
local bareOpenResult = A.Submit("open")
expectSequenceContains("search result bare open sequence open", bareOpenResult, "Opened Target")

reset()
local pronounOpenSearch = A.Submit("search target buff cooldown text size")
expectSequenceContains("search result pronoun open sequence search", pronounOpenSearch, "Target Buff Cooldown Text Size")
local pronounOpenResult = A.Submit("open it")
expectSequenceContains("search result pronoun open sequence open", pronounOpenResult, "Opened Target")

reset()
local placeOpenSearch = A.Submit("search target buff cooldown text size")
expectSequenceContains("search result place-open sequence search", placeOpenSearch, "Target Buff Cooldown Text Size")
local placeOpenResult = A.Submit("show me where")
expectSequenceContains("search result place-open sequence open", placeOpenResult, "Opened Target")

reset()
local moreSearch = A.Submit("search target buff cooldown text size")
expectSequenceContains("search result tell-more sequence search", moreSearch, "Target Buff Cooldown Text Size")
local moreResult = A.Submit("tell me more")
expectSequenceContains("search result tell-more sequence explain", moreResult, "Result 1: Target Buff Cooldown Text Size")

reset()
local whyThisSearch = A.Submit("search target buff cooldown text size")
expectSequenceContains("search result why-this sequence search", whyThisSearch, "Target Buff Cooldown Text Size")
local whyThisResult = A.Submit("why would I use this")
expectSequenceContains("search result why-this sequence why", whyThisResult, "Why this result matters")

reset()
A.Submit("set target buff cooldown text size to 14")
local pronounNumberSearch = A.Submit("search target buff cooldown text size")
expectSequenceContains("search result pronoun number-change sequence search", pronounNumberSearch, "Target Buff Cooldown Text Size")
local pronounNumberChange = A.Submit("set it to 18")
expectSequenceContains("search result pronoun number-change sequence apply", pronounNumberChange, "I will not guess which listed result 'it' means")
local pronounNumberUndo = A.Submit("undo")
expectSequenceContains("search result pronoun number-change sequence undo", pronounNumberUndo, "I have no Assistant change to undo")

reset()
A.Submit("turn on MSUF Style Module")
local pronounBooleanSearch = A.Submit("style module")
expectSequenceContains("search result pronoun boolean-change sequence search", pronounBooleanSearch, "MSUF Style Module")
local pronounBooleanChange = A.Submit("turn it off")
expectSequenceContains("search result pronoun boolean-change sequence apply", pronounBooleanChange, "I will not guess which listed result 'it' means")
local pronounBooleanUndo = A.Submit("undo")
expectSequenceContains("search result pronoun boolean-change sequence undo", pronounBooleanUndo, "I have no Assistant change to undo")

reset()
A.Submit("turn on player raid marker")
reset()
local locationPronounMoon = A.Submit("where can I turn off the moon icon from player frame?")
expectSequenceContains("location pronoun moon sequence location", locationPronounMoon, "Player Raid Marker")
local locationPronounMoonValue = A.Submit("current value")
expectSequenceContains("location pronoun moon sequence current value", locationPronounMoonValue, "Current value: Player Raid Marker is enabled")
local locationPronounMoonOpen = A.Submit("open it")
expectSequenceContains("location pronoun moon sequence open", locationPronounMoonOpen, "Opened Player")
local locationPronounMoonChange = A.Submit("turn it off")
expectSequenceContains("location pronoun moon sequence apply", locationPronounMoonChange, "Player Raid Marker from enabled to disabled")
local locationPronounMoonUndo = A.Submit("undo")
expectSequenceContains("location pronoun moon sequence undo", locationPronounMoonUndo, "Reverted the last Assistant change")

reset()
A.Submit("turn off target buffs")
reset()
local locationPronounBuffs = A.Submit("where can I turn on target buffs?")
expectSequenceContains("location pronoun target buffs sequence location", locationPronounBuffs, "Target Buffs")
local locationPronounBuffsValue = A.Submit("current value")
expectSequenceContains("location pronoun target buffs sequence current value", locationPronounBuffsValue, "Current value: Target Buffs is disabled")
local locationPronounBuffsChange = A.Submit("turn it on")
expectSequenceContains("location pronoun target buffs sequence apply", locationPronounBuffsChange, "Target Buffs from disabled to enabled")
local locationPronounBuffsUndo = A.Submit("undo")
expectSequenceContains("location pronoun target buffs sequence undo", locationPronounBuffsUndo, "Reverted the last Assistant change")

reset()
A.Submit("turn off target debuffs")
reset()
local locationPronounDebuffs = A.Submit("where can I show target debuffs?")
expectSequenceContains("location pronoun target debuffs sequence location", locationPronounDebuffs, "Target Debuffs")
local locationPronounDebuffsChange = A.Submit("turn it on")
expectSequenceContains("location pronoun target debuffs sequence apply", locationPronounDebuffsChange, "Target Debuffs from disabled to enabled")
local locationPronounDebuffsUndo = A.Submit("undo")
expectSequenceContains("location pronoun target debuffs sequence undo", locationPronounDebuffsUndo, "Reverted the last Assistant change")

reset()
A.Submit("turn on player name")
reset()
local locationPlayerName = A.Submit("how do I hide player name?")
expectSequenceContains("location pronoun player name sequence location", locationPlayerName, "Player Name Text setting location")
local locationPlayerNameValue = A.Submit("current value")
expectSequenceContains("location pronoun player name sequence current value", locationPlayerNameValue, "Current value: Player Name is enabled")
local locationPlayerNameOpen = A.Submit("open it")
expectSequenceContains("location pronoun player name sequence open", locationPlayerNameOpen, "Opened Player")
local locationPlayerNameChange = A.Submit("turn it off")
expectSequenceContains("location pronoun player name sequence apply", locationPlayerNameChange, "Player Name from enabled to disabled")
local locationPlayerNameUndo = A.Submit("undo")
expectSequenceContains("location pronoun player name sequence undo", locationPlayerNameUndo, "Reverted the last Assistant change")

reset()
A.Submit("turn on target power bar")
reset()
local locationTargetPowerBar = A.Submit("how do I disable target power bar?")
expectSequenceContains("location pronoun target power bar sequence location", locationTargetPowerBar, "Target Power Bar setting location")
local locationTargetPowerBarValue = A.Submit("current value")
expectSequenceContains("location pronoun target power bar sequence current value", locationTargetPowerBarValue, "Current value: Target Power Bar is enabled")
local locationTargetPowerBarChange = A.Submit("turn it off")
expectSequenceContains("location pronoun target power bar sequence apply", locationTargetPowerBarChange, "Target Power Bar from enabled to disabled")
local locationFormatAfterPowerBar = A.Submit("where can I change target health text format?")
expectSequenceContains("location format clears prior setting context", locationFormatAfterPowerBar, "Target Health Text Format setting location")
local locationFormatAfterPowerBarValue = A.Submit("current value")
expectSequenceContains("location format page current value", locationFormatAfterPowerBarValue, "opens an MSUF page, not a setting")
local locationFormatAfterPowerBarOpen = A.Submit("open it")
expectSequenceContains("location format page open", locationFormatAfterPowerBarOpen, "Opened Target")
local locationTargetPowerBarUndo = A.Submit("undo")
expectSequenceContains("location pronoun target power bar sequence undo", locationTargetPowerBarUndo, "Reverted the last Assistant change")

local locationFollowupCases = {
    {
        input = "where can I disable target cast bar icon?",
        start = "setting location",
        value = "Current value: Target Castbar Icon",
        open = "Opened Target",
    },
    {
        input = "where can I move target cast bar?",
        start = "setting location",
        value = "Result 1 (Cast Bars) opens an MSUF page",
        open = "Opened Cast Bars",
    },
    {
        input = "where can I make raid health text bigger?",
        start = "setting location",
        value = "Current value: Raid HP Font Size",
        open = "Opened Raid HP Font Size",
    },
    {
        input = "where can I disable class resources?",
        start = "setting location",
        value = "Current value: Class Resource",
        open = "Opened Class Resource",
    },
    {
        input = "where can I move combat timer?",
        start = "setting location",
        value = "Result 1 (Gameplay) opens an MSUF page",
        open = "Opened Gameplay",
    },
    {
        input = "where can I export profile?",
        start = "Profile backup and export help",
        value = "Result 1 (Profiles) opens an MSUF page",
        open = "Opened Profiles",
    },
    {
        input = "where can I turn off focus kick tracker?",
        start = "setting location",
        value = "Current value: Focus Interrupt Tracker",
        open = "Opened Focus Interrupt Tracker",
    },
}

for i, case in ipairs(locationFollowupCases) do
    reset()
    A.Submit("turn on MSUF Style Module")
    clearPendingOnly()
    local location = A.Submit(case.input)
    expectSequenceContains("cross-domain location followup start " .. tostring(i), location, case.start)
    local value = A.Submit("current value")
    expectSequenceContains("cross-domain location followup current value " .. tostring(i), value, case.value)
    local open = A.Submit("open it")
    expectSequenceContains("cross-domain location followup open " .. tostring(i), open, case.open)
end

reset()
_G.MSUF_DB.targettarget.showToTInTargetName = false
reset()
local inlineTargetTargetNameChange = A.Submit("can you show me the target of target name on the target frame?")
expectSequenceContains("inline target-target name direct request", inlineTargetTargetNameChange, "Target Target Inline Text from disabled to enabled")
local inlineTargetTargetNameUndo = A.Submit("undo")
expectSequenceContains("inline target-target name direct request undo", inlineTargetTargetNameUndo, "Reverted the last Assistant change")

reset()
_G.MSUF_DB.targettarget.showToTInTargetName = false
reset()
local inlineTargetTargetNameLocation = A.Submit("can you show me where to enable target of target name on target frame?")
expectSequenceContains("inline target-target name location request", inlineTargetTargetNameLocation, "Target Target Inline Text setting location")
local inlineTargetTargetNameValue = A.Submit("current value")
expectSequenceContains("inline target-target name location current value", inlineTargetTargetNameValue, "Current value: Target Target Inline Text is disabled")
local inlineTargetTargetNameOpen = A.Submit("open it")
expectSequenceContains("inline target-target name location open", inlineTargetTargetNameOpen, "Opened Target")
local inlineTargetTargetNameApply = A.Submit("turn it on")
expectSequenceContains("inline target-target name location apply", inlineTargetTargetNameApply, "Target Target Inline Text from disabled to enabled")
local inlineTargetTargetNameLocationUndo = A.Submit("undo")
expectSequenceContains("inline target-target name location undo", inlineTargetTargetNameLocationUndo, "Reverted the last Assistant change")

reset()
_G.MSUF_DB.targettarget.showToTInTargetName = false
reset()
local dependentTargetTrouble = A.Submit("why is my target frame missing target of target?")
expectSequenceContains("dependent target troubleshooting sequence start", dependentTargetTrouble, "Target of Target visibility help")
expectSequenceContains("dependent target troubleshooting sequence inline", dependentTargetTrouble, "Target Target Inline Text")
local dependentTargetValue = A.Submit("current value")
expectSequenceContains("dependent target troubleshooting sequence current value", dependentTargetValue, "Current value: Target Target Inline Text is disabled")
local dependentTargetOpen = A.Submit("open it")
expectSequenceContains("dependent target troubleshooting sequence open", dependentTargetOpen, "Opened Target")

reset()
A.Submit("turn on MSUF Style Module")
local resultSettingSearch = A.Submit("style module")
expectSequenceContains("search result setting change sequence search", resultSettingSearch, "I found these MSUF matches")
local resultSettingChange = A.Submit("set option 1 to off")
expectSequenceContains("search result setting change sequence apply", resultSettingChange, "MSUF Style Module from enabled to disabled")
local resultSettingUndo = A.Submit("undo")
expectSequenceContains("search result setting change sequence undo", resultSettingUndo, "Reverted the last Assistant change")

reset()
A.Submit("turn on MSUF Style Module")
local resultOrdinalSettingSearch = A.Submit("style module")
expectSequenceContains("search result ordinal setting sequence search", resultOrdinalSettingSearch, "I found these MSUF matches")
local resultOrdinalSettingChange = A.Submit("turn the first one off")
expectSequenceContains("search result ordinal setting sequence apply", resultOrdinalSettingChange, "MSUF Style Module from enabled to disabled")
local resultOrdinalSettingUndo = A.Submit("undo")
expectSequenceContains("search result ordinal setting sequence undo", resultOrdinalSettingUndo, "Reverted the last Assistant change")

reset()
A.Submit("turn on MSUF Style Module")
local resultPronounSearch = A.Submit("style module")
expectSequenceContains("search result pronoun setting sequence search", resultPronounSearch, "I found these MSUF matches")
local resultPronounExplain = A.Submit("explain result 1")
expectSequenceContains("search result pronoun setting sequence explain", resultPronounExplain, "Result 1: MSUF Style Module")
local resultPronounChange = A.Submit("turn it off")
expectSequenceContains("search result pronoun setting sequence apply", resultPronounChange, "MSUF Style Module from enabled to disabled")
local resultPronounUndo = A.Submit("undo")
expectSequenceContains("search result pronoun setting sequence undo", resultPronounUndo, "Reverted the last Assistant change")

reset()
A.Submit("set target buff cooldown text size to 14")
local resultNumberSearch = A.Submit("search target buff cooldown text size")
expectSequenceContains("search result number change sequence search", resultNumberSearch, "Target Buff Cooldown Text Size")
local resultNumberChange = A.Submit("set result 1 to 18")
expectSequenceContains("search result number change sequence apply", resultNumberChange, "Target Buff Cooldown Text Size from 14 to 18")
local resultNumberUndo = A.Submit("undo")
expectSequenceContains("search result number change sequence undo", resultNumberUndo, "Reverted the last Assistant change")

reset()
A.Submit("set target buff cooldown text size to 14")
local resultNumberOrdinalSearch = A.Submit("search target buff cooldown text size")
expectSequenceContains("search result number ordinal sequence search", resultNumberOrdinalSearch, "Target Buff Cooldown Text Size")
local resultNumberOrdinalChange = A.Submit("set the first one to 18")
expectSequenceContains("search result number ordinal sequence apply", resultNumberOrdinalChange, "Target Buff Cooldown Text Size from 14 to 18")
local resultNumberOrdinalUndo = A.Submit("undo")
expectSequenceContains("search result number ordinal sequence undo", resultNumberOrdinalUndo, "Reverted the last Assistant change")

reset()
A.Submit("set target buff cooldown text size to 14")
local resultNumberPronounSearch = A.Submit("search target buff cooldown text size")
expectSequenceContains("search result number pronoun sequence search", resultNumberPronounSearch, "Target Buff Cooldown Text Size")
local resultNumberPronounExplain = A.Submit("explain result 1")
expectSequenceContains("search result number pronoun sequence explain", resultNumberPronounExplain, "Result 1: Target Buff Cooldown Text Size")
local resultNumberCurrentValue = A.Submit("current value")
expectSequenceContains("search result number pronoun sequence current value", resultNumberCurrentValue, "Current value: Target Buff Cooldown Text Size is 14")
local resultNumberPronounSimple = A.Submit("simpler")
expectSequenceContains("search result number pronoun sequence simple explain", resultNumberPronounSimple, "Right now it is 14")
local resultNumberPronounChange = A.Submit("set it to 18")
expectSequenceContains("search result number pronoun sequence apply", resultNumberPronounChange, "Target Buff Cooldown Text Size from 14 to 18")
local resultNumberPronounUndo = A.Submit("undo")
expectSequenceContains("search result number pronoun sequence undo", resultNumberPronounUndo, "Reverted the last Assistant change")

reset()
local actionSearch = A.Submit("support link action")
expectSequenceContains("search action followup sequence search", actionSearch, "I found these MSUF matches")
local actionCompare = A.Submit("compare result 1 and result 2")
expectSequenceContains("search action followup sequence compare", actionCompare, "Result comparison")
local actionExplain = A.Submit("explain result 2")
expectSequenceContains("search action followup sequence explain", actionExplain, "Result 2: Show Support Links")
local actionWhy = A.Submit("why would i use it")
expectSequenceContains("search action followup sequence why", actionWhy, "Why this result matters")
expectSequenceContains("search action followup sequence why task", actionWhy, "Assistant task")
local actionCurrentValue = A.Submit("current value")
expectSequenceContains("search action followup sequence current value", actionCurrentValue, "not a setting with a saved value")
local actionRun = A.Submit("run result 2")
expectSequenceContains("search action followup sequence run", actionRun, "MSUF support links")

reset()
local actionOrdinalSearch = A.Submit("support link action")
expectSequenceContains("search action ordinal followup sequence search", actionOrdinalSearch, "I found these MSUF matches")
local actionOrdinalRun = A.Submit("run the second one")
expectSequenceContains("search action ordinal followup sequence run", actionOrdinalRun, "MSUF support links")

reset()
local planningCompare = A.Submit("class resources vs power bar")
expectSequenceContains("planning followup comparison sequence start", planningCompare, "Resource bar comparison")
local planningExamples = A.Submit("show examples")
expectSequenceContains("planning followup comparison sequence examples", planningExamples, "make class resources wider")
local planningOpen = A.Submit("open it")
expectSequenceContains("planning followup comparison sequence open", planningOpen, "Opened Class Resources")
local planningApplyGuard = A.Submit("do it")
expectSequenceContains("planning followup comparison sequence guarded apply", planningApplyGuard, "I will not apply a planning suggestion")

reset()
local planningProfile = A.Submit("backup before changes")
expectSequenceContains("planning followup context switch profile", planningProfile, "Profile backup planning")
local planningProfileOpen = A.Submit("open it")
expectSequenceContains("planning followup context switch profile open", planningProfileOpen, "Opened Profiles")
local planningAura = A.Submit("why use aura filters")
expectSequenceContains("planning followup context switch aura", planningAura, "Filters do not move icons or resize them")
local planningAuraOpen = A.Submit("open it")
expectSequenceContains("planning followup context switch aura open", planningAuraOpen, "Opened Player and focused Aura Filters")
local planningAuraExamples = A.Submit("show examples")
expectSequenceContains("planning followup context switch aura examples", planningAuraExamples, "hide spell 12345")

-- This sequence exercises the diagnostic repair choices, so establish the
-- hidden-lane precondition explicitly instead of inheriting a value changed by
-- one of the hundreds of independent prompts above.
local targetBuffsSetting = assert(A.Registry:GetSetting("auras3.target.buff.visible"), "Target Buffs setting missing")
assert(targetBuffsSetting.set(false) ~= false, "could not establish hidden Target Buffs precondition")
reset()
local pendingDiag = A.Submit("target buffs not shown")
expectSequenceContains("pending followup sequence diagnostic", pendingDiag, "Target aura check")
local pendingExplain = A.Submit("explain option 1")
expectSequenceContains("pending followup sequence explain", pendingExplain, "Option 1: Show Target Buffs")
local pendingWhy = A.Submit("why this")
expectSequenceContains("pending followup sequence why", pendingWhy, "Option 1: Show Target Buffs")
local pendingMore = A.Submit("tell me more")
expectSequenceContains("pending followup sequence tell more", pendingMore, "Option 1: Show Target Buffs")
local pendingCurrentValue = A.Submit("current value")
expectSequenceContains("pending followup sequence current value", pendingCurrentValue, "Current value: disabled")
local pendingSimple = A.Submit("explain it simpler")
expectSequenceContains("pending followup sequence simple explain", pendingSimple, "Simple explanation")
local pendingOpen = A.Submit("open option 1")
expectSequenceContains("pending followup sequence open", pendingOpen, "Opened Target")
local pendingApply = A.Submit("fix it")
expectSequenceContains("pending followup sequence apply", pendingApply, "Target Buffs from disabled to enabled")

reset()
local profilePending = A.Submit("profile missing")
expectSequenceContains("profile pending followup sequence diagnostic", profilePending, "I treated that as a problem report")
local profilePendingWhy = A.Submit("why this")
expectSequenceContains("profile pending followup sequence why", profilePendingWhy, "Option 1: Open Profiles page")
local profilePendingMore = A.Submit("more details")
expectSequenceContains("profile pending followup sequence more details", profilePendingMore, "Option 1: Open Profiles page")

reset()
local resetConfirm = A.Submit("reset profile")
expectSequenceContains("confirmation followup reset sequence prompt", resetConfirm, "Reset active profile")
local resetConfirmExplain = A.Submit("what will you do")
expectSequenceContains("confirmation followup reset sequence explain", resetConfirmExplain, "Pending confirmation")
expectSequenceContains("confirmation followup reset sequence explain label", resetConfirmExplain, "Reset active profile")
local resetConfirmOpen = A.Submit("open it")
expectSequenceContains("confirmation followup reset sequence open", resetConfirmOpen, "Opened Profiles")
local resetConfirmCancel = A.Submit("cancel")
expectSequenceContains("confirmation followup reset sequence cancel", resetConfirmCancel, "Cancelled. I kept the options as they were.")

reset()
local copyConfirmStart = A.Submit("copy from profile Default")
expectSequenceContains("confirmation followup copy sequence start", copyConfirmStart, "What do you want me to call the copy")
local copyConfirm = A.Submit("name it Raid Copy")
expectSequenceContains("confirmation followup copy sequence prompt", copyConfirm, "Copy profile Default to Raid Copy")
local copyConfirmWhy = A.Submit("why")
expectSequenceContains("confirmation followup copy sequence why", copyConfirmWhy, "Pending confirmation")
expectSequenceContains("confirmation followup copy sequence why label", copyConfirmWhy, "Copy profile Default to Raid Copy")
local copyConfirmCancel = A.Submit("cancel")
expectSequenceContains("confirmation followup copy sequence cancel", copyConfirmCancel, "Cancelled. I kept the options as they were.")

reset()
local guidedStart = A.Submit("help me set up my UI")
expectSequenceContains("guided setup native sequence start", guidedStart, "native MSUF guided setup")
local guidedResume = A.Submit("show setup")
expectSequenceContains("guided setup native sequence resume", guidedResume, "native MSUF guided setup")

reset()
A.Submit("turn off player name")
local sequenceChange = A.Submit("turn on player name")
expectSequenceContains("correction sequence change", sequenceChange, "Player Name from disabled to enabled")
local sequenceHistory = A.Submit("what did you just do")
expectSequenceContains("correction sequence history", sequenceHistory, "Last change I made: Player Name from disabled to enabled")
local sequenceUndo = A.Submit("that was wrong")
expectSequenceContains("correction sequence undo", sequenceUndo, "Reverted the last Assistant change")
local sequenceRedo = A.Submit("redo that")
expectSequenceContains("correction sequence redo", sequenceRedo, "Reapplied the Assistant change")
if #failures > 0 then
    io.stderr:write("failures=" .. tostring(#failures) .. "\n")
    for i = 1, #failures do io.stderr:write(failures[i], "\n") end
    os.exit(1)
end

print("assistant_real_prompt_output_audit: ok prompts=" .. tostring(#prompts))
